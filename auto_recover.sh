#!/bin/bash
# Created by Kollin Prince (kollin.prince@emc.com) -- BEATLE ONLY --
#### Created to help automate disk recoveries that need manual intervention 
version=1.0.3b
trap control_c SIGINT
control_c() { # Runs, if user hits control-c
  echo -e "\n## Ouch! Keyboard interrupt detected.\n## Cleaning up..."
  NORM
  /bin/rm -f tmp.data 2>&1
  /bin/rm -f ${full_dir_path}/obj_list 2>&1
  /bin/rm -f /var/tmp/${fsuuid}.oids 2>&1
  exit 
}
Usage() { # Displays how to run the tool.
  echo "
This script will help automate disk recoveries that need manual intervention by querying the impacted objects and running
ObjectForensics then try to fix the following: 0kb, OpenObjectslist, and NeedsRecovery.
              
                                                Usage:
./auto_recover -f <fsuuid> (Runs auto recover on the disk.)
               -v (Shows the current version.)
               -h (Shows how to run the tool)
"
  exit
}
black='\E[30m' #display color when outputting information
red='\E[31m'
green='\E[0;32m'
yellow='\E[33m'
blue='\E[1;34m'
magenta='\E[35m'
cyan='\E[36m'
white='\E[1;37m'
orange='\E[0;33m'
rmgmaster=$(awk -F "," '/localDb/{print $2}' /etc/maui/cm_cfg.xml); js_restart_num=0
progress () { # Progress bar function
  percDone=$(echo 'scale=2;'$1/$2*100 | bc)
  halfDone=$(echo $percDone/2 | bc) #I prefer a half sized bar graph
  barLen=$(echo ${percDone%'.00'})
  halfDone=$(expr $halfDone + 6)
  tput bold
  PUT 7 6; printf "%2.8s " Working: $status
  PUT 7 28; printf "%4.4s  " $barLen%     #Print the percentage
  PUT 7 40; printf "%2.13s  " Objects_done: $count out_of: $total
  for (( x=6; x<=$(expr $halfDone); x++)); do
		PUT 5 $x;  echo -e "\033[7m \033[0m" #Draw the bar
	done
  tput sgr0
}
PUT(){ echo -en "\033[${1};${2}H";}  # Set up for the progress bar
DRAW(){ echo -en "\033%";echo -en "\033(0";}
WRITE(){ echo -en "\033(B";}
HIDECURSOR(){ echo -en "\033[?25l";}
NORM(){ echo -en "\033[?12l\033[?25h";}
begin() { # Part of the progress bar to begin the set up.
  clear
  HIDECURSOR
  echo -e ""
  echo -e ""
  DRAW    #magic starts here - must use caps in draw mode
  echo -e "            WORKING ON THE REQUESTED OBJECTS"
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
fix_zero_kb() { # Steps to remove 0kb objects 
  status='kb     '
  echo -e $white"$(date): Starting with 0 kb objects ...." >> $output_log
	for kbobj in $(cat ${full_dir_path}/ObjectID_0_KB| cut -d ',' -f1,2); do
		progress $count $total; count=$(($count+1))
    #Gathering object information 
		tenantid=$(echo $kbobj | awk -F ',' '{print $2}')
		oid=$(echo $kbobj | awk -F ',' '{print $1}')
		mauiobjbrowser -t $tenantid -i $oid > tmp.data 2>&1
		[[ $(cat tmp.data | wc -l) -eq 1 ]] && { echo -e "$(date): Object ${yellow}${oid}${white} has been deleted already skipping" >> $output_log && continue; }
		sub=$(grep subtenant tmp.data | awk '{print $2}')
		uid=$(grep uid tmp.data | awk '{print $2}')
		key=$(mauikeymgr -c WSKEY -r $tenantid:$sub:$uid | grep KeyData: | awk '{print $2}' 2>&1)
		#Deleting object
		deleteobj=$(rest_client.rb -f deleteobject -p $sub/$uid -k $key -i $oid)
		check=$(rest_client.rb -f readobject -p $sub/$uid -k $key -i $oid)
		if [[ $(echo $check | awk '{print length}') -eq 35 ]]; then
			echo -e "$(date): Object "${yellow}${oid}${white}" was "$green"successfully deleted"$white >> $output_log
		else
			echo -e "$(date): Object "${yellow}${oid}${white}" was "$red" not deleted successfully"$white >> $output_log
		fi
		progress $count $total
	done
  /bin/rm -f tmp.data
}
fix_Opened_objects() { # Steps on fixing opened objects kb 15840
  echo -e $white"$(date): Starting with refcount objects... kb 15840" >> $output_log
  for refobj in $(cat ${full_dir_path}/OpenedObjectList| awk '{print $1}'); do
    status='refcount'
    oid=$(echo $refobj | awk -F ',' '{print $1}')
    tenantid=$(echo $refobj | awk -F ',' '{print $2}')
    mauioutput=$(mauiobjbrowser -t $tenantid -i $oid -m 2>&1)
		progress $count $total
    if [[ $(echo $mauioutput| awk '{print length}') -le 102 ]]; then
      echo "$(date): ${oid} has no output from mauiobjbrowser" >> $output_log
    else
      master_host=$(mauiobjbrowser -t $tenantid -i $oid -m| grep MdsMaster: | awk '{print $2}' | awk -F ':' '{print $1}')
      jsstop=$(ssh $master_host service mauijs stop 2>&1)
      jsstart=$(ssh $master_host service mauijs start 2>&1) 
      unlock=$(mauiobjbrowser -t $tenantid -i $oid -w0 2>&1)
      trigger=$(mauisvcmgr -s mauicc -c trigger_cc_checkObj -a "objid=$oid,tenant=$tenantid,port=10301" 2>&1) 
      sleep 2
      objcheck=$(mauiobjbrowser -t $tenantid -i $oid -m 2>&1| grep refcount | awk '{print $2}') 
      if [[ $objcheck -eq 0 ]]; then
        echo -e $(date)":" $yellow$oid$white "has been successfully unlocked: S1"  >> $output_log
      else
        client_host=$(mauirexec "grep ${oid} /var/log/maui/mds.log |grep 'open object conflict w/ sess '|tail -1" | grep -v Output |awk -F 'address:|, client' '{print $2}'| grep -v "^$"|tail -1)
        client_jsstop=$(ssh ${client_host} service mauijs stop 2>&1)
        client_jsstart=$(ssh ${client_host} service mauijs start 2>&1)
        trigger=$(mauisvcmgr -s mauicc -c trigger_cc_checkObj -a "objid=$oid,tenant=$tenantid,port=10301" 2>&1)
        sleep 2
        objcheck=$(mauiobjbrowser -t $tenantid -i $oid -m 2>&1| grep refcount | awk '{print $2}')
        if [[ $objcheck -eq 0 ]]; then
          echo -e $(date)":" ${yellow}${oid}${white} "has been successfully unlocked: S2"  >> $output_log
        else
          status='MDS_ref'; master_mds_port=$(echo $refobj | awk -F ',' '{print $3}'); progress $count $total
          check_mds_set_healthy $master_host $master_mds_port
          if [[ $mds_not_ready -eq 0 ]]; then
            master_mds_restart=$(ssh $master_host service mauimds_$master_mds_port restart 2>&1); sleep 60; mds_counter=0
            check_mds_set_healthy $master_host $master_mds_port
            while [[ $mds_not_ready -ne 0 ]];do
              sleep 30; mds_counter=$(($mds_counter+1))
              check_mds_set_healthy $master_host $master_mds_port
              [[ $mds_counter -ge 50 ]] && break
            done
            [[ $mds_counter -ge 50 ]] && { echo -e $(date)": MDS ${red}${master_host}:${master_host}${white} took over 25 minutes to initialized, skipping... please investigate" >> $output_log && break; }
            master_host=$(mauiobjbrowser -t $tenantid -i $oid -m| grep MdsMaster: | awk '{print $2}' | awk -F ':' '{print $1}')
            jsstop=$(ssh $master_host service mauijs stop 2>&1)
            jsstart=$(ssh $master_host service mauijs start 2>&1) 
            unlock=$(mauiobjbrowser -t $tenantid -i $oid -w0)
            trigger=$(mauisvcmgr -s mauicc -c trigger_cc_checkObj -a "objid=$oid,tenant=$tenantid,port=10301" 2>&1) 
            sleep 2
            objcheck=$(mauiobjbrowser -t $tenantid -i $oid -m 2>&1| grep refcount | awk '{print $2}') 
            if [[ $objcheck -eq 0 ]]; then
              echo -e $(date)":" $yellow$oid$white "has been successfully unlocked: S3"  >> $output_log
            else
              self_restart=$(service mauijs restart)
              echo -e $(date)":" $yellow$oid$white "has not been unlocked: S3">> $output_log
            fi
          fi
        fi
      fi	
    fi
    count=$(($count+1))
		progress $count $total
	done
	progress $count $total
	/bin/rm -f tmp.data
}
fix_needs_recover() { # Steps to either see if possible garbage or just needs cc triggered 
  status=recover
  echo -e $white"$(date): Starting on NeedsRecovery objects...." >> $output_log
	for Nobj in $(cat ${full_dir_path}/NeedsRecovery| awk '{print $1}'); do	
		oid=$(echo $Nobj | awk -F ',' '{print $1}')
		tenantid=$(echo $Nobj | awk -F ',' '{print $2}')
		port=$(echo $Nobj | awk -F ',' '{print $3}')
		progress $count $total
    mauiobjbrowser -t $tenantid -i $oid -m > /var/tmp/output.txt
    time_out_check=$(grep -c x-maui-ccAsyncTimeout: /var/tmp/output.txt)
    #if [[ $time_out_check -ge 1 ]]; then  
     # host_list=$(mauirexec "grep $oid /var/log/maui/mds.log" | grep 'client address.*$' -o  | sort | uniq -c|awk -F "client address:|, client port:" '{print $2}')
      #[[ -n $host_list ]] && { for js_host in $host_list; do cc_js_restart=$(ssh $js_host service mauijs restart 2>&1);done;js_restart_num=1; }; [[ $js_restart_num -lt 1 ]] && { mauirexec "service mauijs restart"; js_restart_num=1; echo -e "All JS's have been restarted" >> $output_log; }
    #fi
    mastermds_host=$(grep MdsMaster: /var/tmp/output.txt| awk '{print $2}' | awk -F ':' '{print $1}')
    size=$(grep size: /var/tmp/output.txt| head -1 | awk '{print $2}') 
    maui_size=$(grep x-maui-create-size: /var/tmp/output.txt| awk '{print $2}')
    [[ $size -lt $maui_size ]] && { echo "$oid,$tenantid,$port" >> ${full_dir_path}/NeedsWork && count=$(($count+1)) && progress $count $total && echo -e "maui-create-size and size does not match: maui_size=$maui_size, size=$size ${yellow}${oid}$white... " >> $output_log && continue; }
		echo -e $(mauisvcmgr -s mauicc -c trigger_cc_checkObj -a "objid=$oid,tenant=$tenantid,port=$port" -m $mastermds_host) js_restart=$js_restart_num >> $output_log
		second=$(mauisvcmgr -s mauicc -c trigger_cc_checkObj -a "objid=$oid,tenant=$tenantid,port=10301")
		count=$(($count+1)); progress $count $total
	done
  /bin/rm -f tmp.data /var/tmp/output.txt
}
check_mds_set_healthy () { # Checks to ensure that there is at least three local MDS running
  mds_not_ready=0
  for mds_check in $(mauimdlsutil -q -m  '*' -n $rmgmaster | grep -A 2 $1:$2| awk '{print $4}');do
    check_host=$(echo $mds_check|awk -F ':' '{print $1}'); check_mds=$(echo $mds_check|awk -F ':' '{print $2}')
    [[ $(ssh ${check_host} mauisvcmgr -s mauimds -c mauimds_isNodeInitialized|grep ${check_mds}|awk -F '=' '{print $2}') == 'true' ]] && continue
    echo -e $(date)":" ${red}${check_host}:${check_mds}${white} "reported mds not initialized, please investigate mds before the object can be unlocked " >> $output_log && mds_not_ready=1 && break
  done
}
obj_repair() { # Steps to fix stubborn objects
  status=recover
  echo -e $white"$(date): Starting on NeedsRecovery objects...." >> $output_log
	for Nobj in $(cat ${full_dir_path}/NeedsRecovery| cut -d ',' -f1,2); do	
		oid=$(echo $Nobj | awk -F ',' '{print $1}')
		tenantid=$(echo $Nobj | awk -F ',' '{print $2}')
		progress $count $total
		fix=$(mauiobjbrowser -t $tenantid -i $oid -x > tmp;/var/service/AET/workdir/tools/Recovery/objrepair.py -f tmp -t $tenantid 2<&1)
		check=$(echo $fix | awk '{print $2}')
		count=$(($count+1)); mancheck=0
		while [ "$check" != "PASS" ]; do	
			mauiobjbrowser -t $tenantid -i $oid -x > tmp;/var/service/AET/workdir/tools/Recovery/objrepair.py -f tmp -t $tenantid | egrep 'mauiobjchk|mauisvcmgr' 2>&1 > commands
			chmod +x commands
			do=$(./commands 2<&1)
			if [ "$check" != "PASS" ]; then
				counter=$(($counter+1))
				if [ $counter -eq 5 ]; then
					echo "$(date): Object" $oid "has gone through five times and may need more work" >> $output_log
					check="PASS"
					mancheck=1; continue
				fi
			fi
			fix=$(mauiobjbrowser -t $tenantid -i $oid -x > tmp;/var/service/AET/workdir/tools/Recovery/objrepair.py -f tmp -t $tenantid 2<&1)
			check=$(echo $fix | awk '{print $2}')
		done
		counter=0
		progress $count $total
		/bin/rm -f commands tmp
		[[ $mancheck -eq 0 ]] && { echo -e "$(date): Object"$green $oid $white"has passed" >> $output_log; }
	done
}
CRS () {
	datanum=$(grep -A 13 'Replica #1' output.tmp |awk '/data/ {print $3}')
	codenum=$(grep -A 15 'Replica #1' output.tmp |awk '/code/ {print $3}')
	totalnum=$(($datanum+$codenum)); rep_num="Replica #$(($x)):"; rep_num_plus="Replica #$(($x+1))"
  echo "Replica #$((x))" >> ${full_dir_path}/Val_count.output
  awk "/$rep_num_plus/{p=0};p;/$rep_num/{p=1}" output.tmp|egrep 'type:|current:' >> ${full_dir_path}/Val_count.output
	awk "/$rep_num_plus/{p=0};p;/$rep_num/{p=1}" output.tmp|egrep 'Size|OSD'|sort|uniq -c >> ${full_dir_path}/Val_count.output
}
mirror () {
  rep_num="Replica #$(($x)):"; rep_num_plus="Replica #$(($x+1))"
  echo "Replica #$((x))" >> ${full_dir_path}/Val_count.output
  awk "/$rep_num_plus/{p=0};p;/$rep_num/{p=1}" output.tmp|egrep 'type:|current:|Total pieces:' >> ${full_dir_path}/Val_count.output
	awk "/$rep_num_plus/{p=0};p;/$rep_num/{p=1}" output.tmp|egrep 'Size|OSD'|sort|uniq -c >> ${full_dir_path}/Val_count.output
}
column_count() { # Help determines if the objects in the list is garbage by giving the size on disk with it sorted and counted
val_count=0
for valoid in $(cat ${full_dir_path}/NeedsWork); do 
	echo $(date)" : $valoid" >> ${full_dir_path}/Val_count.output
	tid=$(echo $valoid | awk -F ',' '{print $2}')
	oid=$(echo $valoid | awk -F ',' '{print $1}')
	mauiobjbrowser -t $tid -i $oid > output.tmp
	numberRep=$(awk '/Number/ {print $4}' output.tmp)
  grep -i 'size:' output.tmp | grep -v fragment >> ${full_dir_path}/Val_count.output
	for (( x=1; x<=$(expr $numberRep); x++)); do
		algorithm=$(grep -A 10 "Replica #$(($x)):" output.tmp |awk '/algorithm:/ {print $2}')
		if [ "$algorithm" = "CRS" ]; then
			CRS
		else
			mirror 
		fi   
	done
  mauicreatesize=$(grep x-maui-create output.tmp | awk '{print $2}')
  correctsize=$(echo "$mauicreatesize/9"|bc)
  echo "Column size should equal around: $correctsize" >> ${full_dir_path}/Val_count.output; val_count=$(($val_count+1))
  echo -ne "Objects counted: $val_count/$(cat ${full_dir_path}/NeedsWork |wc -l)" '\r'
done
rm -rf output.tmp
}
valid_fsuuid='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
main(){ # Main code
  [[ ! "${fsuuid}" =~ $valid_fsuuid ]] && { echo -e "Invalid fsuuid entered, ${red}${fsuuid}${white}" && read -p "Please re-enter the fsuuid: " fsuuid && main && exit; }
  host=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select hostname from filesystems where uuid='$fsuuid'"|tr -d ' '| grep -v "^$")
  [[ $HOSTNAME != $host ]] && { echo "Please run the script on host $host"; echo exiting; exit; }
  echo -e $white"Querying the impacted objects... It could take a few minutes."
  /bin/rm -f /var/tmp/${fsuuid}.oids 2>&1; query_fail_num=0
  while [[ ${query_fail_num} -le 5 || $query == 'finish' ]]; do 
    query_impact_objects.py -i $fsuuid -l | grep -v "^$"|awk '{print $4}' > /var/tmp/${fsuuid}.oids
    [[ $(grep -c from /var/tmp/${fsuuid}.oids) -ge 1 ]] && { echo -e "Query failed on a host; re-running the query" && query_fail_num=$(($query_fail_num+1)); } || { query='finish' && break; }
    [[ $query_fail_num -ge 5 ]] && { echo "Query failed $query_fail_num times, please check the host(s) $(query_impact_objects.py -i $fsuuid -l | grep -v "^$"| grep from)" && exit; }
  done
  total_objects=$(cat /var/tmp/${fsuuid}.oids|wc -l)
  [[ $total_objects -eq 0 ]] && { echo && echo -e "Disk is ${green}fully recovered,$white please run show_offline_disks.sh to verify the disk is replaceable." && echo && exit;}
  echo -e "Objects found on fsuuid ${cyan}${fsuuid}${white} #${yellow}$total_objects"${white};echo -e "Running ObjectForensics on the above objects"
  perl /var/service/AET/workdir/tools/ObjectForensic/ObjectForensic.pl -file /var/tmp/${fsuuid}.oids 2>&1
  dir_path=$(ls -tr /var/service/AET/workdir/tools/ObjectForensic/ | grep ObjectForensic |tail -1)
  full_dir_path="/var/service/AET/workdir/tools/ObjectForensic/$dir_path"
  objects_left=$(awk '/Gathering/{print $8}' ${full_dir_path}/ObjectForensic.log|tail -1)
  sleep 3
  while [[ $objects_left -ne $total_objects ]]; do
    objects_left=$(awk '/Gathering/{print $8}' ${full_dir_path}/ObjectForensic.log|tail -1)
    echo -ne "Waiting for ObjectForensic to finish, Objects checked: ${cyan}${objects_left}${white}/${yellow}$total_objects.${white}" '\r'
    sleep 1
    objects_left=$(awk '/Gathering/{print $8}' ${full_dir_path}/ObjectForensic.log|tail -1)
  done
  echo -e "ObjectForensic has finished, anaylzing the report"
  needs_recover_count=$(cat ${full_dir_path}/NeedsRecovery |wc -l 2>&1); zero_kb_count=$(cat ${full_dir_path}/ObjectID_0_KB | wc -l 2>&1)
  OpenObjects_count=$(cat ${full_dir_path}/OpenedObjectList | wc -l 2>&1)
  needs_val_count=$(cat ${full_dir_path}/NeedsValidation|wc -l 2>&1)
  echo -e "Objects found:
  NeedsRecovery=$needs_recover_count
  0_kb=$zero_kb_count
  OpenedObjects=$OpenObjects_count
  NeedsValidation=$needs_val_count"
  output_log="${full_dir_path}/repair.log"
  count=0; counter=0
  [[ $needs_recover_count -eq 0 ]] && { recovery=0; } || { cat ${full_dir_path}/NeedsRecovery >> ${full_dir_path}/obj_list && recovery=1; }
  [[ $OpenObjects_count -eq 0 ]] && { refcount=0; } || { cat ${full_dir_path}/OpenedObjectList >> ${full_dir_path}/obj_list && refcount=1; }
  [[ $zero_kb_count -eq -0 ]] && { kb=0; } || { cat ${full_dir_path}/ObjectID_0_KB >> ${full_dir_path}/obj_list && kb=1; }
  [[ -f ${full_dir_path}/obj_list ]] && { total=$(cat ${full_dir_path}/obj_list | wc -l 2>&1); }
  if [[ -n $total ]]; then
    echo "$(date): Total objects "$total
    begin
    [[ -n $unsafe && $recovery -eq 1 ]] && { obj_repair; }; [[ -z $unsafe && $recovery -eq 1 ]] && { fix_needs_recover; }
    [[ $kb -eq 1 ]] && { fix_zero_kb; }
    [[ $refcount -eq 1 ]] && { fix_Opened_objects; }
    end
    echo -e $white"$(date): "$green"All Finished" >> $output_log
    echo -e "$(date): $green All Finished,$white please check the ${full_dir_path}/repair.log for the results"; /bin/rm -f ${full_dir_path}/obj_list
  else
    echo -e $yellow" 0 Objects found, skipping work section... "$white; touch ${full_dir_path}/repair.log
  fi
  needs_val=$(cat ${full_dir_path}/NeedsValidation |wc -l 2>&1)
  [[ -f ${full_dir_path}/NeedsValidation ]] && cat ${full_dir_path}/NeedsValidation >> ${full_dir_path}/NeedsWork
  [[ $needs_val -ne 0 || -f ${full_dir_path}/NeedsWork ]] && { column_count; }
  echo -e "$orange Final Report:                                     $white
  Objects triggered: $(egrep -c 'triger_cc_checkObj=Succeed|passed' ${full_dir_path}/repair.log 2>&1) of $(cat ${full_dir_path}/NeedsRecovery|wc -l 2>&1)
  Opened Objects unlocked: $(grep -c 'has been successfully unlocked' ${full_dir_path}/repair.log 2>&1) of $(cat ${full_dir_path}/OpenedObjectList|wc -l 2>&1)
  0kb objects deleted: $(grep -c '"successfully deleted"' ${full_dir_path}/repair.log 2>&1) of $(cat ${full_dir_path}/ObjectID_0_KB|wc -l 2>&1)
  Needs more investigation: $(cat ${full_dir_path}/NeedsWork|wc -l)" # Final Report
  [[ $(cat ${full_dir_path}/NeedsWork|wc -l) -ge 1 ]] && { echo "Please see ${full_dir_path}/NeedsWork"; }
  recovery_status=$(psql -U postgres rmg.db -h $rmgmaster -t -c "select status from recoverytasks where fsuuid='$fsuuid'"|tr -d ' '| grep -v "^$" )
  [[ ! "$recovery_status" =~ ^[2-3] ]] && { echo "Fsuuid $fsuuid is not In-progress. Submitting $fsuuid to In-progress" && bash /var/service/recoverdisk.sh -s $fsuuid; }
}
while getopts "sf:vh" options; do
  case $options in
    s)  unsafe=1
        ;;
    a)  Js_locked
        ;;
    f)  fsuuid=$OPTARG
        main
        exit
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
