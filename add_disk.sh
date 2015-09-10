#!/bin/bash 
# Created by Kollin Prince (kollin.prince@emc.com)
## This script will go through the procedure for either a healthy disk or unhealthy
echo "The script needs to be ran on the node where the failed disk is located." 
host_name=$HOSTNAME
version=1.0.9
echo "Version: "$version
black='\E[30m' #display color when outputting information
red='\E[31m'
green='\E[0;32m'
yellow='\E[33m'
blue='\E[1;34m'
magenta='\E[35m'
cyan='\E[36m'
white='\E[1;37m'
orange='\E[0;33m'
atmos_version=$(cut -d '.' -f1,2,3 /etc/maui/atmos_version)
rmgmaster=$(awk -F "," '/localDb/{print $2}' /etc/maui/cm_cfg.xml)
atmos_check_version='^[2-9].[2-9].[0-9]' # Checks if the version is higher than 2.2.0
Usage() { #Help on running this tool
	echo "
		This script is intended for adding disks either failed or healthy back into the atmos.
									Usage:  
		./add_disk.sh -o <FSUUID of Disk> (Option to add one disk back in).
		./add_disk.sh -a (Option to add all failed disks in). MAKE SURE THE DISKS ARE HEALTHY BEFORE RUNNING THIS OPTION.
		"
	exit
}
valid_fsuuid='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
val() {
  [[ ! "${fsuuid}" =~ $valid_fsuuid ]] && { echo -e "Invalid fsuuid entered, ${red}${fsuuid}${white}" && exit; }
  echo -e "fsuuid validation"$green "Passed"$white
}
add_disk_counter(){
  [[ -f /var/service/fsuuid_SRs/${fsuuid}.info ]] || { touch /var/service/fsuuid_SRs/${fsuuid}.info; }
  add_disk_number=$(awk -F '=' '/add_disk/{print $2}' /var/service/fsuuid_SRs/${fsuuid}.info)
  [[ -z $add_disk_number ]] && { echo "add_disk=" >> /var/service/fsuuid_SRs/${fsuuid}.info; }
  [[ ${add_disk_number} -ge 3 ]] && { echo -e $white"Disk $fsuuid has been added back in too many times: $add_disk_number ,exiting..." && exit; }
  add_disk_numberP1=$((${add_disk_number}+1))
  sed -i "s/add_disk=${add_disk_number}/add_disk=${add_disk_numberP1}/g" /var/service/fsuuid_SRs/${fsuuid}.info
}
count_timer() {
count=240
for (( x=1; x<=240; x++)); do 
  count=$(($count-1))
  echo -ne "Seconds left: "$count " "'\r'
  sleep 1
done
}
onedisk() {
	read -p "Is the disk healthy? [yY] [nN]: " ishealth
	val
	rmgmaster=$(grep localDb /etc/maui/cm_cfg.xml|cut -d ',' -f2)
	serialnumber=$(psql -U postgres rmg.db -h $rmgmaster -c "select diskuuid from fsdisks where fsuuid='$fsuuid'" |grep -v row|grep -v diskuuid |grep -v '^$'|grep -v '-'|cut -d ' ' -f2)
	[[ $(echo $serialnumber | awk '{print length}') -ne 8 ]] && continue
	dev=$(awk -F "<osDevPath>|</osDevPath>" '/osDevPath/{print$2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
	mount=$(df | grep -c $dev)
	ss_config_inuse=$(grep -c $fsuuid /etc/maui/ss_cfg.xml)
	mauisvcmgr_inuse=$(mauisvcmgr -s mauiss -c disk_status_list | grep -c $fsuuid)
	check2=$(awk -F  "<managementState>|</managementState>" '/management/{print$2}' /var/local/maui/atmos-diskman/FILESYSTEM/$fsuuid/latest.xml)
  [[ $mount -ne 0 ]] && { echo -e "$dev is still mounted... Exiting" && exit; }
  [[ $ss_config_inuse -ne 0 ]] && { echo -e "Fsuuid $fsuuid is still in use by the ss_cfg.xml file... Exiting" && exit; }
  [[ $mauisvcmgr_inuse -ne 0 ]] && { echo -e "Fsuuid $fsuuid is still found in mauisvcmgr -s mauiss -c disk_status_list... Please correct this before adding the disk back in... Exiting" && exit; }
	if [[ "${ishealth}" =~ [nN] ]]; then	
		destageset=$(mauisvcmgr -s mauiss -c mauiss_disk_destage_status -a fsuuid=<fsuuid>,duration=0)
		destagechk=$(mauisvcmgr -s mauiss -c mauiss_destage_status | awk -F '=' '{print $2}')
		if [[ "$destagechk" == "normal" ]]; then
			echo "Node is not destaged... Please verify the node is destage and run the script again"; exit
		else
			echo "The node is destaged. Continuing..."
		fi
		mauisvcmgr -s mauiss -c mauiss_reset_diskerror -a "fsuuid=$fsuuid" 
		cmgenevent --event=disk --type=reuse --diskid=$serialnumber
		cmgenevent --event=disk --type=reuse --fsuuid=$fsuuid
		echo "Verify that the disk was added back in... Script is exiting
Once finished working on the disk please run the below commands to fail out the disk cmgenevent --event=disk --type=ioerror --fsuuid="$fsuuid"
mauisvcmgr -s mauiss -c mauiss_destage_clear
Then node should be not be destaged and disk not mounted after above commands are ran"
	elif [[ "${ishealth}" =~ [yY] ]]; then
    add_disk_counter
		mauisvcmgr -s mauiss -c mauiss_reset_diskerror -a "fsuuid=$fsuuid"
		cmgenevent --event=disk --type=reuse --fsuuid=$fsuuid 
	fi
}
allrun() {
  echo "This option is to start all disks on the node. Please make sure all disks are healthy before use."
  echo "Gathering disks"
  for disk in $(psql -U postgres rmg.db -h $rmgmaster -t -c "select mnt,uuid from filesystems where hostname='$host_name'" | grep mauiss | awk '{print $3}'); do 
    if ! grep -q $disk /proc/mounts; then
      serialnumber=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select diskuuid from fsdisks where fsuuid='$disk'"|tr -d ' '| grep -v "^$")
      if [[ -f /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml ]]; then #Checks if the serial number exists in atmos-diskman
        manslotreplaced=$(awk -F "<slotReplaced>|</slotReplaced>" '/slotReplaced/{print $2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
        slotID=$(awk -F "<slotId>|</slotId>" '/slotId/{print $2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
        dev=$(awk -F "<osDevPath>|</osDevPath>" '/osDevPath/{print$2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
      else
        manslotreplaced='true'
      fi
      slotreplaced=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select slot_replaced from disks where serialnumber='$serialnumber'" |tr -d ' ' | grep -v '^$')
      [[ -z $slotreplaced ]] && { slotreplaced=1; }
      [[ $slotreplaced -eq 1 && $manslotreplaced = 'true' ]] && continue 
      mauisvcmgr -s mauiss -c mauiss_reset_diskerror -a "fsuuid=$fsuuid"
      cmgenevent --event=disk --type=reuse --fsuuid=$fsuuid
      add_disk_counter
    fi
  done
  rm -rf tmpoutput tmpfsuuid
  echo -e $green"All disks have had the disk error reset and used cmgenevent to be added back in"$white
}
while getopts "o:ahvf" options
do
  case $options in
    o)  fsuuid=$2
        onedisk
			  exit
      ;;
    a)  allrun
			;;
    v)	echo $version
        exit
			;;
    h)	Usage
			;;
    *)  Usage
      ;;
    esac
done
echo "Finished with kb 166904"
