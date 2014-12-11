#!/bin/bash
# Created by Kollin Prince (kollin.prince@emc.com
# Co-author Claiton Weeks
################################
# This script will find all the unmounted ss/mds disks and output the fsuuid, devpath, if replaceable, and the status in recoverytasks.
################################
# 1.5.3 Checks health and if internal drives are fully covered. New 1.5.5 See mixed drives
# New 1.5.6a trap control c. Improved options and cleaner script
# 1.5.6b Improved internal disk output
# 1.5.7 Improved internal disk reliability output and improvement of the -c option

version=1.5.7b

Usage() { # Displays how to run the tool.
  echo "
This script will find all the unmounted ss/mds/internal disks and output the fsuuid, devpath, if replaceable, and the status in recoverytasks%.

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
disksize=$(df --block-size=1T | egrep mauiss | tail -1 |awk {'print $2'})
black='\E[30m' #display color when outputting information
red='\E[31m'
green='\E[0;32m'
yellow='\E[33m'
blue='\E[1;34m'
magenta='\E[35m'
cyan='\E[36m'
white='\E[1;37m'
orange='\E[0;33m'
touch /var/service/local.output; touch /var/service/output.txt

TotalPdisks=$(awk -F "<theoreticalDiskNum>|</theoreticalDiskNum>" '/theoreticalDiskNum/{print $2}' /var/local/maui/atmos-diskman/NODE/$(hostname)/latest.xml)
if [[ $TotalPdisks -le 60 && $TotalPdisks -gt 30 ]]; then # Making sure the numbers are either 60-30-15 so the calc ratio doesn't go into inifi loop
  Totaldisks=60
elif [[ $TotalPdisks -le 30 && $TotalPdisks -gt 15 ]]; then
  Totaldisks=30
elif [[ $TotalPdisks -le 15 && $TotalPdisks -gt 0 ]]; then
  Totaldisks=15
fi
rmgmaster=$(awk -F "," '/localDb/{print $2}' /etc/maui/cm_cfg.xml)
system_master=$(awk -F 'value="|,' '/systemDb/{print $2}' /etc/maui/cm_cfg.xml)
ifmixed=$(ssh $rmgmaster grep dmMixDriveMode /etc/maui/maui_cfg.xml | grep -c true)
if [[ $ifmixed -eq 1 ]]; then
  mixed='true'
  Totaldisks=$(($TotalPdisks*2))
  ratio='1:1'
else
  mixed='false'
  ratio=$(awk -F "=" '/Ratio/{print $2}' /etc/maui/node.cfg) #Finds the ratio to predict how many ss and mds disks are supposed to be installed on the atmos.
fi
Oss=$(echo $ratio | awk -F ':' '{print $2}')
Omds=$(echo $ratio | awk -F ':' '{print $1}')
ss=$(echo $ratio | awk -F ':' '{print $2}')
mds=$(echo $ratio | awk -F ':' '{print $1}')
timescounter=1
while [[ $(($ss+$mds)) -ne $Totaldisks ]]; do
  timescounter=$(($timescounter+1))
  ss=$(($ss+$Oss))
  mds=$(($mds+$Omds))
done
bothdisks=$(df -h | egrep -c 'ss|atmos')
valid_fsuuid='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
control_c() { # Runs the if user hits control-c
  echo -e "\n## Ouch! Keyboard interrupt detected.\n## Cleaning up..."
  NORM
  Cleanup "Done cleaning up, exiting..." 1
  exit 1
}
Cleanup() { # Cleaning up temp files
  /bin/rm -f /var/service/local.output
  /bin/rm -f /var/service/output.txt
}
assign_sr() { # Assigning the SR to the fsuuid
  echo -e $white"Please enter the serialnumber when that is the only info you have"
  read -p "Enter the fsuuid/serialnumber: " assign_disk
  disk_length=$(echo $assign_disk |awk '{print length}')
  case "${hardware_gen}:${disk_length}" in              # Checks if the disk entered is an fsuuid or serialnumber
    [123]:8)
      echo -e "Serial number detected on Gen ${hardware_gen}"
      for rmg_host in $(show_master.py | awk '/RMG/ {print $3}'); do
        node_uuid=$(psql -U postgres rmg.db -t -h $rmg_host -c "select nodeuuid from disks where uuid='$serialnumber'"|tr -d ' '| grep -v "^$")
        [[ -n $node_uuid ]] && { host=$(psql -U postgres rmg.db -h $rmg_host -t -c "select hostname from nodes where uuid='$node_uuid'"|tr -d ' '| grep -v "^$"); }
      done
      [[ -z $node_uuid ]] && { read -p "Not able to find the host, please enter the host: " host; }
      ;;
    [12]:33)
      echo -e "Internal serial number detected on Gen ${hardware_gen}"
      read -p "Please enter the host of the disk: " host
      ;;
    [123]:36)
      [[ ! "${assign_disk}" =~ $valid_fsuuid ]] && { echo -e "Invalid fsuuid entered, ${red}${assign_disk}${white}" && assign_sr; }
      echo -e "fsuuid validation"$green "Passed"$white
      for rmg_host in $(show_master.py | awk '/RMG/ {print $3}'); do
        host=$(psql -U postgres rmg.db -h $rmg_host -t -c "select hostname from filesystems where uuid='$assign_disk'"|tr -d ' '| grep -v "^$")
        [[ -n $host ]] && break
      done
      [[ -z $host ]] && read -p "Not able to find the host, please enter the host: " host
      ;;
    [123]:*)
      echo -e "Invalid Input, please try again."
      assign sr
      ;;
  esac
  read -p "Enter the SR number: " -t 60 -n 8 sr; echo
  [[ $sr != [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] ]] && { echo -e "Invalid Service Request Number, ${red}${sr}${white} please try again" && assign_sr; }
  [[ $(grep -c $host /etc/hosts) -eq 0 ]] && { echo -e "The host entered is not found, ${red}${host}${white} please try again" && assign_sr; }
  echo "Adding disk "$assign_disk" to SR"$sr "on host: "$host
  dircheck=$(ssh $host ls /var/service | grep -c fsuuid_SRs)
  [[ $dircheck -ne 1 ]] && { ssh $host /bin/mkdir /var/service/fsuuid_SRs; }
  ssh $host touch /var/service/fsuuid_SRs/$assign_disk.txt
  if [[ $(ssh $host grep -c $assign_disk /var/service/fsuuid_SRs/$assign_disk.txt) -eq 1 ]]; then
    echo -e "Fsuuid "${yellow}${assign_disk}${white}" already has an SR assigned to it"
    read -p "Are you sure you want to overwrite the previous SR? [yY] [nN]: " yousure
    [[ $yousure =~ [nN] ]] && { echo 'Exiting'; exit 16; }
  fi
  echo $assign_disk","$sr > /var/service/$assign_disk.tmp
  /usr/bin/scp /var/service/$assign_disk.tmp $host:/var/service/fsuuid_SRs/$assign_disk.txt
  /bin/rm -f /var/service/$assign_disk.tmp
}
diskhealth() { # Checking the disk health function
  if [[ $type = 'Internal' ]]; then
    diskh=$(cs_hal info $dev | grep SMART | awk '{print $3}') 1>/dev/null 2>/dev/null
    if [[ "$diskh" = 'FAILED:' || -z "$diskh" ]]; then
      diskh=$red"FAILED"$white
    elif [[ "$diskh" = 'SUSPECT' ]]; then
      diskh=${yellow}${diskh}${white}
    else
      diskh=${green}${diskh}${white}
    fi
  else
    smart=$(smartctl -A $dev | egrep -i 'failing|failed' | grep -v 'WHEN_FAILED' -c)
    reallocate=$(smartctl -A $dev |grep Reallocated_Sector_Ct | awk '{print $10}')
    offline=$(smartctl -A $dev |awk '/Offline_Uncorrectable/ {print $10}')
    linedev=$(echo $dev | awk -F '/' '{print $3}')
    messagecheck=$(grep -i corruption /var/log/messages | grep -c $linedev)
    if [[ $smart -ge 1 ]]; then
      diskh=$(echo -e $red"FAILED"$white)
    elif [[ $reallocate -ge 10 || $offline -ge 10 ]]; then
      diskh=$(echo -e $yellow"SUSPECT"$white)
    elif [[ $messagecheck -ge 1 ]]; then
      diskh=$(echo -e $red"CORRUPTION"$white)
    else
      diskh=$(echo -e $green"GOOD"$white)
    fi
  fi
}
SRinput() { # How to assign an SR to an specific fsuuid or serial number
  if [[ -a /var/service/fsuuid_SRs/$disk.txt ]]; then
    SRnumber=$(awk -F ',' '{print $2}' /var/service/fsuuid_SRs/$disk.txt)
    SR=$(echo -e ${cyan}${SRnumber}${white})
  else
    SR=$(echo -e $red"Needs SR"$white)
  fi
  [[ -z "$SRnumber" ]] && SR=$(echo -e $red"Needs SR"$white)
}
diskreplaceableinfo() { # Gathering disk replaceable information
  serialnumber=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select diskuuid from fsdisks where fsuuid='$disk'"|tr -d ' '| grep -v "^$")
  [[ $(echo $serialnumber | awk '{print length}') -ne 8 ]] && return 1
  diskstatus=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select status from disks where uuid='$serialnumber'"|tr -d ' '| grep -v "^$")
  replacement=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select replacable from disks where uuid='$serialnumber'"|tr -d ' '| grep -v "^$")
  unrec=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select unrecoverobj from recoverytasks where fsuuid='${disk}'"| awk 'NR==1{print $1}')
  imprec=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select impactobj from recoverytasks where fsuuid='${disk}'"| awk 'NR==1{print $1}')
  [[ $(echo ${#unrec}) -eq 0 ]] && Rpercent=$(echo -e $cyan"Not found"$white) || \
  [[ $unrec -eq 0 || $imprec -eq 0 ]] && percent=0 || percent=$(echo "scale=6; 100-$unrec*100/$imprec"|bc|cut -c1-5)
  Rpercent=$(echo -e $yellow$percent"%"$white "Unrecovered: "$yellow$unrec$white)
}
progress() { # Progress bar function
  percDone=$(echo 'scale=2;'$1/$2*100 | bc)
  halfDone=$(echo $percDone/2 | bc) #I prefer a half sized bar graph
  barLen=$(echo ${percDone%'.00'})
  halfDone=$(expr $halfDone + 6)
  disksfound=$(grep -c -i fsuuid /var/service/output.txt)
  tput bold
  PUT 7 28; printf "%4.4s  " $barLen%     #Print the percentage
  PUT 7 42; printf "%2.12s  " Disks_found: $disksfound  #Prints the number of failed disks found
  for (( x=6; x<=$(expr $halfDone); x++))
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
end() { # Exiting out of the progress bar mode and outputting the finally progress made
  realcount=$(($total-$count))
  progress $realcount $total
  PUT 10 12
  echo -e ""
  NORM
}
replacementdisk () {  # Checks the status of the recovery and replacement
  diskreplaceableinfo
  case "$1:$2:$3" in    # echo "Replacement: $replacement  Disk status: $diskstatus  RecoveryStatus: $recoverystatus"
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
    1:[46]:2)       touch /var/service/fsuuid_SRs/$disk.txt
      [[ $(grep -c "^" /var/service/fsuuid_SRs/$disk.txt) -eq 1 ]] && for log in $(ls -t /var/log/maui/cm.log*); do
        bzgrep -m1 "Successfully updated replacable bit for $serialnumber" $log | awk -F\" '{print $2}' >> /var/service/fsuuid_SRs/$disk.txt && break; done
      [[ $(cat /var/service/fsuuid_SRs/$disk.txt | wc -l) -eq 1 ]] && date >> /var/service/fsuuid_SRs/$disk.txt
      setreplaced=$(tail -1 /var/service/fsuuid_SRs/$disk.txt)
      datereplaceable=$(date +%s --date="$setreplaced")
      dateplusseven=$((604800+$datereplaceable))
      pastseven=''
      [[ $(date +%s) -ge $dateplusseven ]] && pastseven=$(echo "Disk has been replaceable since $setreplaced, please check the SR")
      echo -e "Replaceable="$green"Yes"$white "DiskSize="${yellow}${disksize}"TB"$white $pastseven >> /var/service/local.output
        ;;
    1:4:*)    echo "The disk is set for replaceable, Disk status is set to 4. The disk may not been seen by the hardware" >> /var/service/local.output
        ;;
    0:[46]:*)    echo -e "Replaceable="$red"No"$white "RecoveryStatus="$cyan"Not found"$white "Recovery="$Rpercent >> /var/service/local.output
        ;;
    1:*:*)    echo -e "Disk is set for replaceable, but disk status is incorrect. Please update disk status=6 in the disks table" >> /var/service/local.output
        ;;
    0:*:*)    echo -e "Unable to see one of the following: $replacement $diskstatus $recoverystatus" >> /var/service/local.output
        ;;
        *)    echo -e "Something failed....."
        ;;
  esac

  [[ "${ifmixed}" -eq 1 ]] && { A_MDS_temp=$(awk -v pattern=${disk} -F '/|mds_' '/EnvRoot/ {n=$0};$n ~ pattern {p=$6};END {if(p) print "${red}\""p"\"${white}";else print "${cyan}\"None Found\"${white}"}' /etc/maui/mds/*/mds_cfg.xml); eval echo -e "Associated MDSs: $A_MDS_temp" >> /var/service/local.output; }
  return 0
}
outputinfo() { #Set up for what will be outputted to the user.
  diskhealth
  echo -e $white"Host: "${orange}${host_name} $white"IP:" ${orange}${nodeip} $white>> /var/service/local.output
  echo -e "TLA: "${cyan}${TLA}${white} "SiteID: "${cyan}${site}${white} "SR: "$SR >> /var/service/local.output
  echo -e "Devpath: "${red}${dev} $white"FSUUID: "${red}${disk} $white >> /var/service/local.output
  echo -e "Disk_type: "${yellow}${type}${white} "slotID: "${yellow}${slotID}${white} "Health: "$diskh "SN: "${yellow}${serialnumber}${white}  >> /var/service/local.output
}

hardware_product=$(dmidecode | awk '/Product Name/{print $NF; exit}') # Gets and sets HW Gen.
case "$hardware_product" in
  1950)                   # > Dell 1950 is the Gen 1 hardware
  hardware_gen=1
    ;;
  R610)                       # > Dell r610 is the Gen 2 hardware.
  hardware_gen=2
    ;;
  S2600JF)                    # > Product Name: S2600JF is Gen3
  hardware_gen=3
    ;;
  *)  cleanup "Invalid hardware information. Could not determine generation. Please email Kollin.Prince@emc.com to get corrected. "
    ;;
esac

internaldisk() { # Determine if there is a internal disk issue.
case "${hardware_gen}" in
  [1-2])
    if [[ $(omreport storage vdisk controller=0 | awk '/Status/ {print $3}') != 'Ok' ]]; then
      if [[ -z $(omreport storage pdisk controller=0 | grep -A 2 ID | grep -A 2 0:0:0 | grep Ok) ]]; then
        serialnumber=$(smartctl -i /dev/sg0|awk '/Serial Number/ {print $3}')
        slotID=$(omreport storage pdisk controller=0 | awk '/Name/ {print $5}' |head -1)
      else
        serialnumber=$(smartctl -i /dev/sg1|awk '/Serial Number/ {print $3}')
        slotID=$(omreport storage pdisk controller=0 | awk '/Name/ {print $5}'|tail -1)
      fi
      disk=$serialnumber; dev=$slotID
      SRinput
      type='Internal'
      outputinfo
      echo ""  >> /var/service/local.output; cat /var/service/local.output; rm -f /var/service/local.output
    fi
    ;;
  3)
    internalnum=$(awk '/ active / {print $1}' /proc/mdstat)
    if [[ $(cs_hal info $internalnum | awk '/status/ {print $3}') = 'REDUNDANCY_LOST' ]]; then
      if [[ $(cs_hal info $internalnum| awk '/array disk count/ {print $5}') -eq  2 ]]; then
        slotID=' Syncing'; dev='Syncing'; serialnumber='Syncing'
      elif [[ $(cs_hal info $internalnum | awk '/array disk/ {print $4}' | grep -v : |tr '\n' ' ') == 'sg1' ]]; then
        slotID='0'; dev=$(sg_map |awk '/sg0/ {print $2}'); serialnumber=$(smartctl -i /dev/sg0|awk '/Serial/ {print $3}')
      else
        slotID='1'; dev=$(sg_map |awk '/sg1 / {print $2}'); serialnumber=$(smartctl -i /dev/sg1| awk '/Serial/ {print $3}')
      fi
      disk=$serialnumber
      SRinput
      type='Internal'
      outputinfo
      awk '/recovery/' /proc/mdstat |cut -d '[' -f2 >> /var/service/local.output
      echo ""  >> /var/service/local.output; cat /var/service/local.output
      rm -f /var/service/local.output
    fi
    ;;
  *)
    echo $host_name "Not able to find the hardware gen"
    exit
    ;;
esac
}
localrun() { # Finds the un-mounted DAE drives
  nodeip=$(/bin/hostname -i) # Running on the local node to find missing disks and output their information
  [[ ! -d /var/service/fsuuid_SRs ]] && { /bin/mkdir /var/service/fsuuid_SRs; }
  if [[ $(awk '/hardware/ {print length($3)}' /etc/maui/reporting/tla_reporting.conf) -eq 14 ]]; then #Finds the hardware serialnumber
    TLA=$(awk '/hardware/ {print ($3)}' /etc/maui/reporting/tla_reporting.conf)
  else
    TLA='Not found'
  fi
  if [[ $(awk '/site/ {print length($3)}' /etc/maui/reporting/syr_reporting.conf) -ge 5 ]]; then
    site=$(awk '/site/ {print ($3)}' /etc/maui/reporting/syr_reporting.conf)
  else
    site='Not found'
  fi
  internaldisk
  if [[ $bothdisks -eq $Totaldisks ]]; then
    exit
  else
    disktotal=$(($Oss*$timescounter)) # Checks if there are any missing disks.
    diskseen=$(df | grep -c mauiss)
    diskcounter=0
    dircheck=$(ls /var/service | grep -c fsuuid_SRs)
    mdsdisktotal=$(($Omds*$timescounter))
    mdsdiskseen=$(df | grep -c atmos)
    for disk in $(psql -U postgres rmg.db -h $rmgmaster -t -c "select mnt,uuid from filesystems where hostname='$host_name'" | grep mauiss | awk '{print $3}'); do #Pulls a list from the psql database and compares it to what is mounted.
      if ! grep -q $disk /proc/mounts; then
        [[ $disktotal -eq $diskseen ]] && continue
        if [[ $mixed = 'true' ]]; then
          type='Mixed'
        else
          type='SS'
        fi
        diskreplaceableinfo
        if [[ -f /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml ]]; then #Checks if the serial number exists in atmos-diskman
          manslotreplaced=$(awk -F "<slotReplaced>|</slotReplaced>" '/slotReplaced/{print $2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
          slotID=$(awk -F "<slotId>|</slotId>" '/slotId/{print $2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
          dev=$(awk -F "<osDevPath>|</osDevPath>" '/osDevPath/{print$2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
        else
          manslotreplaced='true'
        fi
        slotreplaced=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select slot_replaced from disks where serialnumber='$serialnumber'" |tr -d ' ' | grep -v '^$')
        [[ $slotreplaced -eq 1 && $manslotreplaced = 'true' ]] && continue #Checks if has been replaced and if it has it will continue to the next fsuuid found in the loop.
        diskcounter=$(($diskcounter+1))
        SRinput
        outputinfo
        recoverystatus=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select status from recoverytasks where fsuuid='$disk'"|tr -d ' '| grep -v "^$")
        replacementdisk $replacement $diskstatus $recoverystatus
        echo ""  >> /var/service/local.output
      fi
    done
    mdsdiskcounter=0
    if [[ $mdsdisktotal -gt $(($mdsdiskseen+$mdsdiskcounter)) ]]; then # Checks if mds disks are missing
      for disk in $(psql -U postgres rmg.db -h $rmgmaster -c "select mnt,uuid from filesystems where hostname='$host_name'"| awk '/atmos/ {print $3}'); do #Pulls a list from the rmg.db of mds disks
        if ! grep -q $disk /proc/mounts; then # comparing the list found in the rmg.db to what is mounted
          SRinput
          serialnumber=$(grep parentUniqueId /var/local/maui/atmos-diskman/FILESYSTEM/$disk/latest.xml | awk -F '-' '{print $1}' | awk -F '>' '{print $2}')
          diskstatus=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select status from disks where serialnumber='$serialnumber'"|tr -d ' ' | grep -v '^$')
          replacement=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select replacable from disks where serialnumber='$serialnumber'"|tr -d ' ' | grep -v '^$')
          if [[ -f /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml ]]; then
            manslotreplaced=$(awk -F "<slotReplaced>|</slotReplaced>" '/slotReplaced/{print $2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
            slotID=$(awk -F "<slotId>|</slotId>" '/slotId/{print $2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
            dev=$(awk -F "<osDevPath>|</osDevPath>" '/osDevPath/{print$2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
          else
            manslotreplaced='true'
          fi
          slotreplaced=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select slot_replaced from disks where serialnumber='$serialnumber'"|tr -d ' ' | grep -v '^$')
          [[ $slotreplaced -eq 1 && $manslotreplaced = 'true' ]] && { continue; }
          mdsnumbermissdisk=$(($mdsdisktotal-$(($mdsdiskseen+$mdsdiskcounter))))
          mdsdiskcounter=$(($mdsdiskcounter+1))
          type='MDS' # Should only pull up if it is an mds disk.
          outputinfo
          AMDSs=$(grep $disk /etc/maui/mds/*/mds_cfg.xml | awk -F '/' '{print $5}' | tr '\n' ',' | cut -d ',' -f1-)
          if [[ $replacement -eq 0 || $diskstatus -eq 1 ]]; then
            echo -e "Replaceable="$red"No"$white "Associated MDSs: "${cyan}${AMDSs}${white} >> /var/service/local.output
            echo "Please check the disk table for this mds disk" >> /var/service/local.output
            echo "" >> /var/service/local.output
          else
            echo -e "Replaceable="$green"Yes"$white "DiskSize="${yellow}${disksize}"TB"$white "Associated MDSs: "${cyan}${AMDSs}${white} >> /var/service/local.output
            echo "" >> /var/service/local.output
          fi
        fi
      done
    fi
    if [[ $disktotal -gt $(($diskseen+$diskcounter)) ]]; then # Checks if there are any other missing disks
      for dev in $(awk -F "<osDevPath>|</osDevPath>" '/osDevPath/{print$2}' /var/local/maui/atmos-diskman/DISK/[a-z]*/latest.xml|sort -u); do # Checks for disks not configured properly
        if ! grep -q $dev /proc/mounts  && [[ $disktotal -gt $(($diskseen+$diskcounter)) ]]; then # Compares the list to what is mounted with also checking the total of missing disks
          serialnumber=$(smartctl -i $dev | grep Serial | cut -d ' ' -f6)
          disk=$serialnumber
          hardwarediskfind=$(smartctl -i $dev | grep -c failed)
          manslotreplaced=0
          if [[ $hardwarediskfind -eq 1 ]]; then
            disk=$(echo $dev | cut -d '/' -f3)
            SRinput
            disk='Not Found'; type='Not Configured'; slotID='Unknown'; diskh=$(echo -e $red"Failed"$white)
            outputinfo
            continue
          fi
          diskstatus=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select status from disks where serialnumber='$serialnumber'" |tr -d ' ' | grep -v '^$')
          if [[ -f /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml ]]; then
            manslotreplaced=$(awk -F "<slotReplaced>|</slotReplaced>" '/slotReplaced/{print $2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
            slotID=$(awk -F "<slotId>|</slotId>" '/slotId/{print $2}' /var/local/maui/atmos-diskman/DISK/$serialnumber/latest.xml)
          else
            slotID='Unknown'
          fi
          slotreplaced=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select slot_replaced from disks where serialnumber='$serialnumber'" |tr -d ' ' | grep -v '^$')
          [[ $slotreplaced -eq 1 && $manslotreplaced = 'true' ]] && continue
          SRinput
          diskhealth
          diskcounter=$(($diskcounter+1))
          disk='Not Found'; type='Not Configured'
          outputinfo
          echo ""  >> /var/service/local.output
        fi
      done
    fi
  fi
  cat /var/service/local.output
  /bin/rm -f /var/service/local.output # Cleaning up the tmp file.
}
allrun() { # Running the check on all nodes with the option of an report of what was found at the end
  echo "Show_offline_disks.sh version:" $version
  echo "$(date): Copying the script to all nodes."
  mauiscp /var/service/show_offline_disks.sh /var/service/show_offline_disks.sh
  echo "$(date): Finished with copying the script, now running on all nodes.
  "
  total=$(/usr/local/xdoctor/pacemaker/hosts.py | awk -F '"' '{print $4}'|grep -v "^$" | wc -l); touch /var/service/output.txt
  timeout=180
  endtime=$(( $(date +%s) + $timeout ))
  begin
  for x in $(/usr/local/xdoctor/pacemaker/hosts.py | awk -F '"' '{print $4}'|grep -v "^$"); # During this check there is a timeout if it is running for more than 180 seconds. It will exit out and output the troubled host taking too long
    do
    ssh $x /var/service/show_offline_disks.sh -l >> /var/service/output.txt 2>&1 &
  done
  count=$(ps -ef | grep -v grep | grep -v bash| grep -v scp | grep -c show_offline_disks)
  while [[ $count -ne 0 ]];
    do
    count=$(ps -ef | grep -v grep | grep -v bash| grep -v scp | grep -c show_offline_disks)
    realcount=$(($total-$count))
    progress $realcount $total
    if [[ $(date +%s) -ge $endtime ]];
      then
      end
      echo "Below hosts took longer than 5 minutes to finish
"$(ps -ef | grep -v grep | grep -v /bin/bash | grep -v scp |grep show_offline_disks | awk '{print $8,$9,$10}') >> /var/service/output.txt
      count=0
    fi
  done
  end
  if [[ $(cat /var/service/output.txt | wc -l) -lt 3 ]]; #If no disks are found it will output it in green.
    then
    echo -e $green"No failed disks found"$white
  else
    grep -v ssh_exchange_identification /var/service/output.txt 
  fi
}
endreport() { # Set up for what will be outputted to the users in the -ar or -ra option. The end report
  if [[ $diskreport -eq 0 ]]; then
    echo -e ${msgreport}${green}"None"${white}
  else
    echo -e ${msgreport}${yellow}${diskreport}${white}
  fi
}
report() { # Gives a report of all disks found
  ssfound=$(grep -c 'SS' /var/service/output.txt); ssmsg="Failed SS disks found:"
  mdsfound=$(grep -v Associated /var/service/output.txt | grep -c 'MDS'); mdsmsg="Failed MDS disks found:"
  pending=$(grep -c Pending /var/service/output.txt); pendingmsg="Pending state:"
  failed=$(grep RecoveryStatus /var/service/output.txt | grep -c FAILED); failedmsg="Failed state:"
  paused=$(grep -c Paused /var/service/output.txt); pausedmsg="Cancelled/Paused state:"
  disksreplaceable=$(grep -c -i replaceable /var/service/output.txt); replaceablemsg="Replaceable:"
  inprogress=$(grep -c 'In Progress' /var/service/output.txt); progressmsg="In Progress:"
  echo "Finial report of all nodes:
 "
  diskreport=$ssfound; msgreport=$ssmsg
  endreport
  diskreport=$mdsfound; msgreport=$mdsmsg
  endreport
  diskreport=$pending; msgreport=$pendingmsg
  endreport
  diskreport=$failed; msgreport=$failedmsg
  endreport
  diskreport=$paused; msgreport=$pausedmsg
  endreport
  diskreport=$disksreplaceable; msgreport=$replaceablemsg
  endreport
  diskreport=$inprogress; msgreport=$progressmsg
  endreport
  echo ""
  Cleanup
}
while getopts "hlarvc" options; do
  case $options in
    l)  localrun
        exit
        ;;
    a)  allrun
        ;;
    c)  assign_sr
        exit
        ;;
    r)  report
        ;;
    v)  echo $version
        exit
        ;;
    h)  Usage
        ;;
    *)  Usage
        ;;
  esac
done
Cleanup
