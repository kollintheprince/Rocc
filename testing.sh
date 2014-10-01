#!/bin/bash
# Created by Kollin Prince (kollin.prince@emc.com
# Co-author Claiton Weeks 
# This script will find all the unmounted ss/mds disks and output the fsuuid, devpath, if replaceable, and the status in recoverytasks. 
# New in 1.5.3 Checks health and if internal drives are fully covered. New 1.5.5 See mixed drives
version=1.5.6a
## Check if correct number of options were specified.
[[ $# -lt 1 ]] || [[ $# -gt 2 ]] && echo -e "\n${red}Invalid number of options, see usage:${clear_color}" && Usage

#displays how to run the tool.
Usage() { 
 echo "
This script will find all the unmounted ss/mds disks and output the fsuuid, devpath, if replaceable, and the status in recoverytasks%.

						Usage: 
./show_offline_disks.sh -a (Runs on all nodes. Make sure the script is in /var/service)
                        -l (Runs on the local node.)
                        -v (Shows the current version.)
                        -c (Creates a file to store the SR number for the associated disk, it will prompt for the information needed.)
                        -ar (Gives a report of the disks found on all nodes.)
"
 exit
}
trap control_c SIGINT
host_name=$HOSTNAME
disksize=`df --block-size=1T | egrep mauiss | tail -1 |awk {'print $2'}`
black='\E[30m' #display color when outputting information
red='\E[31m'
green='\E[0;32m'
yellow='\E[33m'
blue='\E[1;34m'
magenta='\E[35m'
cyan='\E[36m'
white='\E[1;37m'
orange='\E[0;33m'
touch /var/service/local.output
touch /var/service/output.txt
TotalPdisks=`grep theoreticalDiskNum /var/local/maui/atmos-diskman/NODE/$host_name/latest.xml | cut -d '>' -f2| cut -d '<' -f1` 
if [[ $TotalPdisks -le 60 ]] && [[ $TotalPdisks -gt 30 ]]; then # Making sure the numbers are either 60-30-15 so the calc ratio doesn't go into inifi loop
 Totaldisks=60
elif [[ $TotalPdisks -le 30 ]] && [[ $TotalPdisks -gt 15 ]]; then
 Totaldisks=30
elif [[ $TotalPdisks -le 15 ]] && [[ $TotalPdisks -gt 0 ]]; then
 Totaldisks=15
fi
rmgmaster=`grep localDb /etc/maui/cm_cfg.xml|cut -d ',' -f2`
ifmixed=`ssh $rmgmaster grep dmMixDriveMode /etc/maui/maui_cfg.xml | grep -c true`
if [[ $ifmixed -eq 1 ]]; then
 mixed='true'
 Totaldisks=$(($TotalPdisks*2))
 ratio='1:1'
else
 mixed='false'
 ratio=`grep Ratio /etc/maui/node.cfg | awk -F '=' '{print $2}'` #Finds the ratio to predict how many ss and mds disks are supposed to be installed on the atmos.
fi
Oss=`echo $ratio | awk -F ':' '{print $2}'`
Omds=`echo $ratio | awk -F ':' '{print $1}'`
ss=`echo $ratio | awk -F ':' '{print $2}'`
mds=`echo $ratio | awk -F ':' '{print $1}'`
timescounter=1
while [ $(($ss+$mds)) -ne $Totaldisks ]; do
 timescounter=$(($timescounter+1))
 ss=$(($ss+$Oss))
 mds=$(($mds+$Omds))
done
bothdisks=`df -h | egrep -c 'ss|atmos'`
control_c() {						# run if user hits control-c
	echo -e "\n## Ouch! Keyboard interrupt detected.\n## Cleaning up..."
	NORM
	Cleanup "Done cleaning up, exiting..." 1
	exit 1
}
Cleanup() {							
	/bin/rm -f /var/service/local.output
	/bin/rm -f /var/service/output.txt
}
assign_sr() { # Assigning the SR to the fsuuid 
 echo -e $white"Please enter the serialnumber when that is the only info you have"
 read -p "Enter the fsuuid/serialnumber: " disk 
 read -p "Enter the SR number: " sr
 read -p "Enter the host of the failed disk: " host
 echo "Adding disk "$disk" to SR"$sr "on host: "$host
 dircheck=`ssh $host ls /var/service | grep -c fsuuid_SRs`
 if [ $dircheck -ne 1 ]; then 
  ssh $host /bin/mkdir /var/service/fsuuid_SRs	
 fi
 ssh $host touch /var/service/fsuuid_SRs/$disk.txt
 if [ `ssh $host grep -c $disk /var/service/fsuuid_SRs/$disk.txt` -eq 1 ]; then
  echo -e "Fsuuid "$yellow$disk$white" already has an SR assigned to it"
  read -p "Are you sure you want to overwrite the previous SR? (y/n) " yousure
  if [ $yousure = 'y' ]; then
   echo $disk","$sr > /var/service/$disk.tmp
   /usr/bin/scp /var/service/$disk.tmp $host:/var/service/fsuuid_SRs/$disk.txt
   /bin/rm -f /var/service/$disk.tmp
   exit
  else
   echo "Exiting"
   exit 16
  fi
 fi	
 echo $disk","$sr > /var/service/$disk.tmp
 /usr/bin/scp /var/service/$disk.tmp $host:/var/service/fsuuid_SRs/$disk.txt
 /bin/rm -f /var/service/$disk.tmp
}
diskhealth() { # Checking the disk health function 
 if [ $type = 'Internal' ]; then
  diskh=`cs_hal info $dev | grep SMART | awk -F ' ' '{print $3}'` 1>/dev/null 2>/dev/null
  if [[ $diskh = 'FAILED' || -z $diskh ]]; then
   diskh=$red"FAILED"$white
  elif [ "$diskh" = "SUSPECT" ]; then
   diskh=$yellow$diskh$white
  else 
   diskh=$green$diskh$white
  fi
 else
  smart=`smartctl -A $dev | egrep -i 'failing|failed' | grep -v 'WHEN_FAILED' -c`
  reallocate=`smartctl -A $dev |grep Reallocated_Sector_Ct | awk -F ' ' '{print $10}'`
  offline=`smartctl -A $dev |grep Offline_Uncorrectable | awk -F ' ' '{print $10}'`
  linedev=`echo $dev | awk -F '/' '{print $3}'`
  messagecheck=`grep -i corruption /var/log/messages | grep -c $linedev`
  if [[ $smart -ge 1 ]]; then
   diskh=`echo -e $red"FAILED"$white`
  elif [[ $reallocate -ge 10 ]] || [[ $offline -ge 10 ]]; then	
   diskh=`echo -e $yellow"SUSPECT"$white`
  elif [[ $messagecheck -ge 1 ]]; then
   diskh=`echo -e $red"CORRUPTION"$white`
  else
   diskh=`echo -e $green"GOOD"$white`
  fi
 fi
}
SRinput() { # How to assign an SR to an specific fsuuid or serial number
 if [[ -a  /var/service/fsuuid_SRs/$disk.txt ]]; then
  SRnumber=`cat /var/service/fsuuid_SRs/$disk.txt|awk -F ',' '{print $2}'` #clean up
  SR=`echo -e $cyan$SRnumber$white`
 else
  SR=`echo -e $red"Needs SR"$white`
 fi
 if [ -z "$SRnumber" ]; then
  SR=`echo -e $red"Needs SR"$white`
 fi 
}
diskreplaceableinfo() { 			#gathering disk replaceable information
 serialnumber=`psql -U postgres rmg.db -h $rmgmaster -t -c "select diskuuid from fsdisks where fsuuid='$disk'"|tr -d ' '| grep -v "^$"`
 [[ `echo ${#serialnumber}` -ne 8 ]] && return 1
 diskstatus=`psql -U postgres rmg.db -h $rmgmaster -t -c "select status from disks where uuid='$serialnumber'"|tr -d ' '| grep -v "^$"`
 replacement=`psql -U postgres rmg.db -h $rmgmaster -t -c "select replacable from disks where uuid='$serialnumber'"|tr -d ' '| grep -v "^$"`
 unrec=`psql -U postgres rmg.db -h $rmgmaster -t -c "select unrecoverobj from recoverytasks where fsuuid='${disk}'"| awk 'NR==1{print $1}'`
 imprec=`psql -U postgres rmg.db -h $rmgmaster -t -c "select impactobj from recoverytasks where fsuuid='${disk}'"| awk 'NR==1{print $1}'`
 [[ `echo ${#unrec}` -eq 0 ]] && Rpercent=`echo -e $cyan"Not found"$white` || \
 [[ $unrec -eq 0 || $imprec -eq 0 ]] && percent=0 || percent=`echo "scale=6; 100-$unrec*100/$imprec"|bc|cut -c1-5`
 Rpercent=`echo -e $yellow$percent"%"$white "Unrecovered: "$yellow$unrec$white`
}
progress() { # Progress bar function 
 percDone=$(echo 'scale=2;'$1/$2*100 | bc)
 halfDone=$(echo $percDone/2 | bc) #I prefer a half sized bar graph
 barLen=$(echo ${percDone%'.00'})
 halfDone=`expr $halfDone + 6`
 disksfound=`grep -c -i fsuuid /var/service/output.txt`
 tput bold
 PUT 7 28; printf "%4.4s  " $barLen%     #Print the percentage
 PUT 7 54; printf "%4.4s  " $disksfound #Prints the number of failed disks found
 for (( x=6; x<=`expr $halfDone`; x++))
  do
  PUT 5 $x;  echo -e "\033[7m \033[0m" #Draw the bar
 done
 tput sgr0
}
PUT(){ echo -en "\033[${1};${2}H";}  # Set up for the progress bar
DRAW(){ echo -en "\033%";echo -en "\033(0";}         
WRITE(){ echo -en "\033(B";}  
HIDECURSOR(){ echo -en "\033[?25l";} 
NORM(){ echo -en "\033[?12l\033[?25h";}
replacementdisk () { 				# Checks the status of the recovery and replacement 
 diskreplaceableinfo
 case "$1:$2:$3" in   			# echo "Replacement: $replacement  Disk status: $diskstatus  RecoveryStatus: $recoverystatus"
  0:[46]:1)    echo -e "Replaceable="$red"No"$white "RecoveryStatus="$yellow"Cancelled/Paused"$white "Recovery="$Rpercent >> /var/service/local.output
      ;;		
  0:[46]:2)    echo -e $green"Recovery completed,"$white" however the replaceable bit needs to be changed to a 1 in the disks table"  >> /var/service/local.output
      ;;        
  0:[46]:3)    echo -e "Replaceable="$red"No"$white "RecoveryStatus="$green"In Progress"$white "Recovery="$Rpercent >> /var/service/local.output
      ;;		
  0:[46]:[45]) echo -e "Replaceable="$red"No"$white "RecoveryStatus="$red"FAILED"$white "Recovery="$Rpercent >> /var/service/local.output
      ;;    
  0:[46]:6)    echo -e "Replaceable="$red"No"$white "RecoveryStatus="$yellow"Pending"$white "Recovery="$Rpercent >> /var/service/local.output
      ;;		
  1:6:[13456]) echo "The disk is set for replaceable, but the recovery has not completed... Please correct the status before dispatching." >> /var/service/local.output
      ;;	  
  1:6:2)    touch /var/service/fsuuid_SRs/${disk}.txt
    [[ `grep -c "^" /var/service/fsuuid_SRs/${disk}.txt` -eq 1 ]] && for log in `ls -t /var/log/maui/cm.log*`; do bzgrep -m1 "Successfully updated replacable bit for $serialnumber" $log | awk -F\" '{print $2}' >> /var/service/fsuuid_SRs/${disk}.txt && break; done
    [[ `cat /var/service/fsuuid_SRs/${disk}.txt | wc -l` -eq 1 ]] && date >> /var/service/fsuuid_SRs/${disk}.txt
   setreplaced=`cat /var/service/fsuuid_SRs/${disk}.txt | tail -1`
   datereplaceable=`date +%s --date="$setreplaced"`
   dateplusseven=$((604800+$datereplaceable))
   pastseven=''
    [[ `date +%s` -ge $dateplusseven ]] && pastseven=`echo "Disk has been replaceable since $setreplaced, please check the SR"`
    echo -e "Replaceable="$green"Yes"$white "DiskSize="$yellow$disksize"TB"$white $pastseven >> /var/service/local.output
      ;;
  1:4:*)    echo "The disk is set for replaceable, Disk status is set to 4. The disk may not been seen by the hardware" >> /var/service/local.output
      ;;
  0:[46]:*)    echo -e "Replaceable="$red"No"$white "RecoveryStatus="$cyan"Not found"$white "Recovery="$Rpercent >> /var/service/local.output
      ;;
  1:*:*)    echo -e "Disk is set for replaceable, but disk status is incorrect. Please update disk status=6 in the disks table" >> /var/service/local.output
      ;;
      *)    exit 1 #Cleanup "Something failed... " 144
      ;;
 esac

 [[ $ifmixed ]] && A_MDS_temp=`awk -v pattern=${disk} -F '/|mds_' '/EnvRoot/ {n=$0};$n ~ pattern {p=$6};END {if(p) print "${red}\""p"\"${white}";else print "${cyan}\"None Found\"${white}"}' /etc/maui/mds/*/mds_cfg.xml`; eval echo -e "Associated MDSs: $A_MDS_temp" >> /var/service/local.output
 return 0
}
outputinfo() { #Set up for what will be outputted to the user.
 diskhealth
 echo -e $white"Host: "$orange$host_name $white"IP:" $orange$nodeip $white>> /var/service/local.output
 echo -e "TLA: "$cyan$TLA$white "SiteID: "$cyan$site$white "SR: "$SR >> /var/service/local.output
 echo -e "Devpath: "$red$dev $white"FSUUID: "$red$disk $white $rebuild >> /var/service/local.output
 echo -e "Disk_type: "$yellow$type$white "slotID: "$yellow$slotID$white "Health: "$diskh "SN: "$yellow$serialnumber$white  >> /var/service/local.output
}
internaldisk() {
internalnum=`awk '/ active / {print $1}' /proc/mdstat` 
 if [ -z `cs_hal info $internalnum | awk '/status/ {print $3}'` ]; then
  if [ `omreport storage vdisk controller=0 | awk '/Status/ {print $3}'` != "Ok" ]; then 
   if [ -z `omreport storage pdisk controller=0 | grep -A 2 ID | grep -A 2 0:0:0 | grep Ok` ]; then
    disk=`omreport storage pdisk controller=0 | awk '/Serial/ {print $4}' | head -1`
    slotID=" 0"
    dev="/dev/sg0"
	SRinput
    type='Internal'
    outputinfo
    echo ""  >> /var/service/local.output
    cat /var/service/local.output 
    rm -f /var/service/local.output
   else 
    disk=`omreport storage pdisk controller=0 | awk '/Serial/ {print $4}' | tail -1`
    slotID=" 1"
    dev="/dev/sg1"
    SRinput
    type='Internal'
    outputinfo
    echo ""  >> /var/service/local.output
    cat /var/service/local.output 
    rm -f /var/service/local.output
   fi
  fi
 elif [ `cs_hal info $internalnum | awk '/status/ {print $3}'` = "REDUNDANCY_LOST" ]; then
  if [ `cs_hal info $internalnum| awk '/array disk count/ {print $5}'` -eq  2 ]; then
   slotID=" Syncing"
   dev="Syncing"
   serialnumber="Syncing"
  elif [ `cs_hal info $internalnum | awk '/array disk/ {print $4}' | grep -v : |tr '\n' ',' ` == "sg1" ]; then
   slotID=" 0"
   dev="/dev/sda"
   serialnumber=`smartctl -i /dev/sg0|awk '/Serial/ {print $3}'` 
  else
   slotID=" 1"
   dev="/dev/sdb"
   serialnumber=`smartctl -i /dev/sg1| awk '/Serial/ {print $3}'` 
  fi
  fsuuid=`mdadm -D /dev/$internalnum |awk '/UUID/ {print $3}'` 
  disk=$fsuuid
  SRinput
  type='Internal'
  rebuild=`mdadm -D /dev/$internalnum | grep Rebuild`
  outputinfo
  echo ""  >> /var/service/local.output
  cat /var/service/local.output 
  Cleanup
 fi
}
localrun() { 
 nodeip=`/bin/hostname -i` # Running on the local node to find missing disks and output their information
 if [ ! -d /var/service/fsuuid_SRs ]; then 
  /bin/mkdir /var/service/fsuuid_SRs
 fi
 if [ `awk '/hardware/ {print length($3)}' /etc/maui/reporting/tla_reporting.conf` == "14" ]; then #Finds the hardware serialnumber 
  TLA=`awk '/hardware/ {print ($3)}' /etc/maui/reporting/tla_reporting.conf` 
 else 
  TLA="Not found" 
 fi
 if [ `awk '/site/ {print length($3)}' /etc/maui/reporting/syr_reporting.conf` -ge "5" ]; then # Finds the site id information # awk '/site/ {print length($3)}' /etc/maui/reporting/syr_reporting.conf
  site=`awk '/site/ {print ($3)}' /etc/maui/reporting/syr_reporting.conf` 
 else 
  site="Not found" 
 fi
 internaldisk
 if [ $bothdisks == $Totaldisks ]; then
  exit
 else
  disktotal=$(($Oss*$timescounter)) # Checks if there are any missing disks. 
  diskseen=`df | grep -c mauiss`
  diskcounter=0
  dircheck=`ls /var/service | grep -c fsuuid_SRs`
  mdsdisktotal=$(($Omds*$timescounter))
  mdsdiskseen=`df | grep -c atmos`
  for disk in `psql -U postgres rmg.db -h $rmgmaster -t -c "select mnt,uuid from filesystems where hostname='$host_name'" | grep mauiss | awk '{print $3}'`; do #Pulls a list from the psql database and compares it to what is mounted.
   if ! grep -q $disk /proc/mounts; then
    if [[ $disktotal -eq $diskseen ]]; then
     continue
    fi
    if [ $mixed = 'true' ]; then
     type='Mixed'
    else
     type='SS' 
    fi 
    diskreplaceableinfo
    if [ -f /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml ]; then #Checks if the serial number exists in atmos-diskman
     manslotreplaced=`grep slotReplaced /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml | awk -F '>' '{print $2}'| awk -F '<' '{print $1}'` #clean up
    else
     manslotreplaced='true'
    fi
    slotreplaced=`psql -U postgres rmg.db -h $rmgmaster -t -c "select slot_replaced from disks where serialnumber='$serialnumber'" |tr -d ' ' | grep -v '^$'`
    if [[ $slotreplaced -eq 1 && $manslotreplaced = 'true' ]]; then #Checks if has been replaced and if it has it will continue to the next fsuuid found in the loop.	
     continue
    fi
    diskcounter=$(($diskcounter+1))
    SRinput
    slotID=`psql -U postgres rmg.db -h $rmgmaster -t -c "select slot from disks where serialnumber='$serialnumber'" |tr -d ' ' | grep -v '^$'`
    dev=`psql -U postgres rmg.db -h $rmgmaster -t -c "select devpath from disks where serialnumber='$serialnumber'"|tr -d ' ' | grep -v '^$'`
    outputinfo
	recoverystatus=`psql -U postgres rmg.db -h $rmgmaster -t -c "select status from recoverytasks where fsuuid='$disk'"|tr -d ' '| grep -v "^$"`
    replacementdisk $replacement $diskstatus $recoverystatus
    echo ""  >> /var/service/local.output
   fi
  done
  mdsdiskcounter=0
  if [[ $mdsdisktotal -gt $(($mdsdiskseen+$mdsdiskcounter)) || $mixed = 'false' ]]; then # Checks if mds disks are missing
   for disk in `psql -U postgres rmg.db -h $rmgmaster -c "select mnt,uuid from filesystems where hostname='$host_name'"| awk '/atmos/ {print $3}'`; do #Pulls a list from the rmg.db of mds disks
    if ! grep -q $disk /proc/mounts; then # comparing the list found in the rmg.db to what is mounted
     SRinput
     serialnumber=`grep parentUniqueId /var/local/maui/atmos-diskman/FILESYSTEM/$disk/latest.xml | awk -F '-' '{print $1}' | awk -F '>' '{print $2}'`
     diskstatus=`psql -U postgres rmg.db -h $rmgmaster -t -c "select status from disks where serialnumber='$serialnumber'"|tr -d ' ' | grep -v '^$'`
     replacement=`psql -U postgres rmg.db -h $rmgmaster -t -c "select replacable from disks where serialnumber='$serialnumber'"|tr -d ' ' | grep -v '^$'`
     if [ -f /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml ]; then
      manslotreplaced=`grep slotReplaced /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml | awk -F '>' '{print $2}'| awk -F '<' '{print $1}'` #clean up
     fi
     slotreplaced=`psql -U postgres rmg.db -h $rmgmaster -t -c "select slot_replaced from disks where serialnumber='$serialnumber'"|tr -d ' ' | grep -v '^$'`
     if [[ $slotreplaced -eq 1 && $manslotreplaced = 'true' ]]; then	
      continue
     fi
     mdsnumbermissdisk=$(($mdsdisktotal-$(($mdsdiskseen+$mdsdiskcounter))))
     mdsdiskcounter=$(($mdsdiskcounter+1))
     type='MDS' # Should only pull up if it is an mds disk. 
     slotID=`psql -U postgres rmg.db -h $rmgmaster -t -c "select slot from disks where serialnumber='$serialnumber'"|tr -d ' ' | grep -v '^$'`
     dev=`psql -U postgres rmg.db -h $rmgmaster -t -c "select devpath from disks where serialnumber='$serialnumber'"|tr -d ' ' | grep -v '^$'`
     outputinfo
     AMDSs=`grep EnvRoot /etc/maui/mds/*/mds_cfg.xml | grep $disk | awk -F '_' '{print $3}' | awk -F '/' '{print $1}' | tr '\n' ',' | cut -d ',' -f1-` #clean up
     if [[ $replacement -eq 0 || $diskstatus -eq 1 ]]; then
      echo -e "Replaceable="$red"No"$white "Associated MDSs: "$cyan$AMDSs$white >> /var/service/local.output
      echo "Please check the disk table for this mds disk" >> /var/service/local.output
      echo "" >> /var/service/local.output
     else
      echo -e "Replaceable="$green"Yes"$white "DiskSize="$yellow$disksize"TB"$white "Associated MDSs:"$cyan$AMDSs$white >> /var/service/local.output
      echo "" >> /var/service/local.output
     fi
    fi
   done
  fi
  if [ $disktotal -gt $(($diskseen+$diskcounter)) ]; then # Checks if there are any other missing disks 
   nodeuuid=`psql -U postgres rmg.db -h $rmgmaster -c "select uuid from nodes where hostname='$host_name'" | grep -v row | grep -v '^$' | tail -1 | grep -v row | grep -v '^$' | tail -1 | awk -F ' ' '{print $1}'`
   for dev in `psql -U postgres rmg.db -h $rmgmaster -c "select devpath from disks where nodeuuid='$nodeuuid'" | grep /dev | sort -u`; do # Checks for disks not configured properly
    if ! grep -q $dev /proc/mounts  && [[ $disktotal -gt $(($diskseen+$diskcounter)) ]]; then # Compares the list to what is mounted with also checking the total of missing disks
     serialnumber=`smartctl -i $dev | grep Serial | cut -d ' ' -f6`
     disk=`echo $serialnumber`
     hardwarediskfind=`smartctl -i $dev | grep -c failed`
     manslotreplaced=0
     if [[ $hardwarediskfind -eq 1 ]]; then
      disk=`echo $dev | cut -d '/' -f3`
      SRcheck=`ls /var/service/fsuuid_SRs | grep -c $disk`
      SRinput
      echo -e $white"Host: "$orange$host_name $white"IP:" $orange$nodeip $white >> /var/service/local.output
      echo -e "TLA: "$cyan$TLA$white "SiteID: "$cyan$site$white "SR: "$SR >> /var/service/local.output
      echo -e "Devpath: "$red$dev $white"FSUUID: "$red"Not Found" $white >> /var/service/local.output
      echo -e "Disk_type: "$red"Not Configured"$white "slotID: "$red"Try cs_hal to find the slot" $white >> /var/service/local.output
      echo ""  >> /var/service/local.output
      continue
     fi
     diskstatus=`psql -U postgres rmg.db -h $rmgmaster -t -c "select status from disks where serialnumber='$serialnumber'" |tr -d ' ' | grep -v '^$'`
     if [ -f /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml ]; then
      manslotreplaced=`grep slotReplaced /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml | awk -F '>' '{print $2}'| awk -F '<' '{print $1}'`
     fi
     slotreplaced=`psql -U postgres rmg.db -h $rmgmaster -t -c "select slot_replaced from disks where serialnumber='$serialnumber'" |tr -d ' ' | grep -v '^$'`
     if [[ $slotreplaced -eq 1 && $manslotreplaced = 'true' ]]; then	
      continue
     fi
     if [[ `psql -U postgres rmg.db -h $rmgmaster -t -c "select slot from disks where serialnumber='$serialnumber'" |tr -d ' ' | grep -v '^$'` -eq 1 ]]; then #Checks if it is found in the rmg.db 
      slotID=`psql -U postgres rmg.db -h $rmgmaster -t -c "select slot from disks where serialnumber='$serialnumber'" |tr -d ' ' | grep -v '^$'`
     else 
      slotID='Unknown'
     fi
     SRcheck=`ls /var/service/fsuuid_SRs | grep -c $serialnumber`
     SRinput
     diskhealth
     diskcounter=$(($diskcounter+1))
     echo -e $white"Host: "$orange$host_name $white"IP:" $orange$nodeip $white >> /var/service/local.output
     echo -e "TLA: "$cyan$TLA$white "SiteID: "$cyan$site$white "SR: "$SR >> /var/service/local.output
     echo -e "Devpath: "$red$dev $white"FSUUID: "$red"Not Found" $white >> /var/service/local.output
     echo -e "Disk_type: "$red"Not Configured"$white "slotID: "$yellow$slotID$white "Health: "$diskh "SN: "$yellow$serialnumber$white  >> /var/service/local.output
     echo ""  >> /var/service/local.output
    fi	
   done
  fi
 fi
 cat /var/service/local.output 
 /bin/rm -f /var/service/local.output # Cleaning up the tmp file.
}
begin() { #part of the progress bar to begin the set up.
 clear
 HIDECURSOR
 echo -e ""                                           
 echo -e ""                                          
 DRAW    #magic starts here - must use caps in draw mode                                              
 echo -e "         GATHERING DISK INFORMATION PLEASE WAIT"
 echo -e "    lqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqk"  
 echo -e "    x                                                   x" 
 echo -e "    mqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqj"
 WRITE
}
end() { # exiting out of the progress bar mode and outputting the finally progress made 
 realcount=$(($total-$count))
 progress $realcount $total
 PUT 10 12                                           
 echo -e ""                                        
 NORM
}
endreport() { #Set up for what will be outputted to the users in the -ar or -ra option. The end report
 if [ $diskreport -eq 0 ]; then 
  echo -e $msgreport$green"None"$white
 else
  echo -e $msgreport$yellow$diskreport$white
 fi
}
allrun() { # Running the check on all nodes with the option of an report of what was found at the end 
 echo "Show_offline_disks.sh version:" $version
 echo "`date`: Copying the script to all nodes."
 mauiscp /var/service/show_offline_disks.sh /var/service/show_offline_disks.sh
 echo "`date`: Finished with copying the script, now running on all nodes.
 "
 total=`/usr/local/xdoctor/pacemaker/hosts.py | awk -F '"' '{print $4}'|grep -v "^$" | wc -l`
 timeout=180
 endtime=$(( $(date +%s) + $timeout )) 
 begin
 for x in `/usr/local/xdoctor/pacemaker/hosts.py | awk -F '"' '{print $4}'|grep -v "^$"`; # During this check there is a timeout if it is running for more than 180 seconds. It will exit out and output the troubled host taking too long
  do
  ssh $x /var/service/show_offline_disks.sh -l >> /var/service/output.txt 2>&1 &
 done
 count=`ps -ef | grep -v grep | grep -v bash| grep -v scp | grep -c show_offline_disks `
 while [ $count -ne 0 ];
  do
  count=`ps -ef | grep -v grep | grep -v bash| grep -v scp | grep -c show_offline_disks`
  realcount=$(($total-$count))
  progress $realcount $total
  if [[ $(date +%s) -ge $endtime ]];
   then
   end
   echo "Below hosts took longer than 5 minutes to finish
"`ps -ef | grep -v grep | grep -v /bin/bash | grep -v scp |grep show_offline_disks | awk -F ' ' '{print $8,$9,$10}'` >> /var/service/output.txt
   count=0
  fi 
 done
 end
 if [[ `cat /var/service/output.txt | wc -l` -lt 3 ]]; #If no disks are found it will output it in green. 
  then 
  echo -e $green"No failed disks found"$white
 else
  cat /var/service/output.txt | grep -v ssh_exchange_identification
 fi
}
 report() { 
  ssfound=`grep -c 'SS' /var/service/output.txt`
  ssmsg="Failed SS disks found:"
  mdsfound=`grep -v Associated /var/service/output.txt | grep -c 'MDS'`
  mdsmsg="Failed MDS disks found:"
  pending=`grep -c Pending /var/service/output.txt`
  pendingmsg="Pending state:"
  failed=`grep RecoveryStatus /var/service/output.txt | grep -c FAILED`
  failedmsg="Failed state:"
  paused=`grep -c Paused /var/service/output.txt`
  pausedmsg="Cancelled/Paused state:"
  disksreplaceable=`grep -c Yes /var/service/output.txt`
  replaceablemsg="Replaceable:"
  inprogress=`grep -c 'In Progress' /var/service/output.txt`
  progressmsg="In Progress:"
  echo "Finial report of all nodes:
 "
  diskreport=$ssfound
  msgreport=$ssmsg
  endreport
  diskreport=$mdsfound
  msgreport=$mdsmsg
  endreport
  diskreport=$pending
  msgreport=$pendingmsg
  endreport
  diskreport=$failed
  msgreport=$failedmsg
  endreport
  diskreport=$paused
  msgreport=$pausedmsg
  endreport
  diskreport=$disksreplaceable
  msgreport=$replaceablemsg
  endreport
  diskreport=$inprogress
  msgreport=$progressmsg
  endreport
 echo ""
 Cleanup 
} 
while getopts "hlarvc" options
do
    case $options in
        l)  localrun
			exit
            ;;
		a)  allrun
			;;
		c)  assign_sr
			exit
			;;
		r)	report
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
Cleanup