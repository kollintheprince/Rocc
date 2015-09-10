#!/bin/bash
#####################################################################
# dispatch_template.sh  -- all Atmos versions                       #
#                                                                   #
# Outputs pre-filled dispatch templates for Atmos.                  #
# Can troubleshoot some issues - see options list.                  #
#                                                                   #
# Created by Claiton Weeks (claiton.weeks<at>emc.com)               #
# Templates based off of CS ROCC team's dispatch templates.         #
#           --Thanks Robert, Kollin, Leo, and everyone else.        #
#                                                                   #
# May be freely distributed and modified as needed,                 #
# as long as proper credit is given.                                #
#                                                                   #
  version=1.4.4.4                                                   #
#####################################################################
# See bottom of file for version tracking.

############################################################################################################
#########################################   Variables/Parameters   #########################################
############################################################################################################
  source_directory="${BASH_SOURCE%/*}"; [[ ! -d "$source_directory" ]] && source_directory="$PWD"
  full_path="${BASH_SOURCE}";this_script=$(basename "$full_path");
  #. "$source_directory/incl.sh"
  #. "$source_directory/main.sh"
  script_name="dispatch_template.sh"
  cm_cfg="/etc/maui/cm_cfg.xml" 
  export RMG_MASTER=$(awk -F, '/localDb/ {print $(NF-1)}' $cm_cfg)										# top_view.py -r local | sed -n '4p' | sed 's/.*"\(.*\)"[^"]*$/\1/'
  export INITIAL_MASTER=$(awk -F"\"|," '/systemDb/ {print $(NF-2)}' $cm_cfg)				  # show_master.py |  awk '/System Master/ {print $NF}'
  xdr_disabled_flag=0																					                        # Initialize xdr disable flag.
  node_uuid=$(dmidecode | grep -i uuid | awk '{print $2}')                            # Find UUID of current node.
  cloudlet_name=$(awk -F",|\"" '/localDb/ {print $(NF-3)}' $cm_cfg);   problem_node=$HOSTNAME;  node_location="$(echo $HOSTNAME | cut -c 1-4)_address"
  atmos_ver=$(awk -F\" '/version\" val/ {print $4}' /etc/maui/nodeconfig.xml);   atmos_ver3=$(awk -F\" '/version\" val/ {print substr($4,1,3)}' /etc/maui/nodeconfig.xml)
  atmos_ver5=$(awk -F\" '/version\" val/ {print substr($4,1,5)}' /etc/maui/nodeconfig.xml);   atmos_ver7=$(awk -F\" '/version\" val/ {print substr($4,1,7)}' /etc/maui/nodeconfig.xml)
  site_id=$(awk '/site/ {print ($3)}' /etc/maui/reporting/syr_reporting.conf)
  tla_number=$(awk '/hardware/{if (length($NF)!=14) print "Not found";else print $NF}' /etc/maui/reporting/tla_reporting.conf)
  customer_site_info_file="/usr/local/bin/customer_site_info"
  log_dir="/var/log/maui/"; log_out="${log_dir}dispatch_template.out"; log_err="${log_dir}dispatch_template.err"; log_dispatch="${log_dir}dispatch.log"
  display_test_switch=0   

###########################################       Functions      ###########################################
############################################################################################################
display_usage() {                 # Display usage table.
    cat <<EOF

${lt_green}Overview:
    Display pre-filled template to copy/paste into Service Manager for dispatch. 
    Can also help troubleshoot some issues, like DAE fans.
    Send comments or suggestions to claiton.weeks@emc.com.
    
${lt_cyan}Synopsis:
  Disk templates / functions:
    `basename $0` -d (<FSUUID>)	# Print MDS/SS/Mixed disk dispatch template, defaults to -k if no or invalid FSUUID specified.
    `basename $0` -e (<FSUUID>)	# Combines -d and -s to print dispatch template, and then update SR#.
    `basename $0` -k		# Runs Kollin's show_offline_disks script first, then asks for fsuuid for dispatch.
    `basename $0` -b		# Set replacable bit to 1 in recoverytasks table.
    `basename $0` -s		# Update SR# reported in Kollin's show_offline_disks script.
    
    Examples:
    `basename $0` -d        -or-        `basename $0` -d 513b24f9-6af0-41c4-b1f4-d6d131bc50a2
    `basename $0` -e        -or-        `basename $0` -e 513b24f9-6af0-41c4-b1f4-d6d131bc50a2
    
${lt_magenta}  Other templates:
    `basename $0` -f		# Troubleshoot DAE fan issues / Print DAE fan replacement template.
    `basename $0` -i		# Internal disk replacement template.
    `basename $0` -l		# LCC replacement/reseat template.
    `basename $0` -n		# Node replacement template.
    `basename $0` -p		# Power Supply replacement template.

${lt_blue}  Administrative options:
    `basename $0` -h		# Display this usage info (help).
    `basename $0` -v		# Display script's current version.
    `basename $0` -V		# Display system info (site id, tla, hardware gen, atmos version, etc.)
    `basename $0` -x		# Distribute script to all nodes and set execute permissions.
    
${lt_gray}  Planned additions:
    `basename $0` -c		# Switch/eth0 connectivity template.
    `basename $0` -m		# DAE power cycle template.
    `basename $0` -o		# Reboot / Power On dispatch template.
    `basename $0` -r		# Reseat disk dispatch template.
    `basename $0` -w		# Private Switch replacement template.
${clear_color}  
EOF
  exit 1
}

cleanup() {                       # Clean-up if script fails or finishes.
  #restore files.. [ -f /usr/sbin/sgdisk.bak ] && /bin/mv /usr/sbin/sgdisk.bak /usr/sbin/sgdisk
  ps -p $spinner_pid >/dev/null 2>&1 && kill $spinner_pid >/dev/null 2>&1
  unset fsuuid_var
  unset sr_number
  unset new_sr_num
  find $log_dir -type f -size +100M -name "dispatch_template.out" -exec rm -f {} \;
  find $log_dir -type f -size +10M -name "dispatch_template.err" -exec rm -f {} \;
  [[ $2 -ne 0 ]] && echo -e "$(date +'%x %X') $problem_node $0 -x Failure - sent to cleanup. Reason: $1 Exit: $2" >> $log_err
  [[ $testing_switch_flag -eq 1 ]] && sed -i "${dts_line_number}s/  display_test_switch=0/  display_test_switch=1/" ${full_path}
  (( $xdr_disabled_flag )) && echo -e "\n## Enabling Dialhomes (xDoctor/SYR) now.\n" && ssh $INITIAL_MASTER xdoctor --tool --exec=syr_maintenance --method=enable && xdr_disabled_flag=0
  [[ -e ${full_path}_tmp ]] && /bin/rm -f ${full_path}_tmp
  [[ "$1" != "" && "$2" -ne 0 ]] && echo -e "\n${red}#${clear_color}#${red}# ${1}${clear_color}\n" || echo -e "${clear_color}"
  [[ $display_test_switch -eq 1 ]] && { echo $2;return 0; }
  exit $2
}

control_c() {                     # Runs if user hits Ctrl-C.
  display_test_switch=0
  echo -e "\n${orange}## Ouch! Keyboard interrupt detected.\n${green}## Cleaning up..."
  cleanup "Done cleaning up, exiting..." 1
}

display_template_body() {         # Displays template to screen.
  printf '%.0s=' {1..80};echo -e "${template_header}";
  echo -e "${lt_gray} \n\nAtmos ${atmos_ver3} Dispatch\t(Disp Notification - Generic)\n\nCST please create a Task for the field CE from the information below.\nReason for Dispatch: ${template_dispatch_reason}\n\nSys. Serial#:\t${tla_number}\nLocation:\t${problem_node} \nHardware:\tGEN${hardware_gen}"
  echo -e "${template_additional_info}"
  [[ -n ${template_var_line1} ]] && echo -e "${template_var_line1}";   [[ -n ${template_var_line2} ]] && echo -e "${template_var_line2}"
  echo -e "CE Action Required:  On Site";   printf '%.0s-' {1..30};  echo -e "\n${template_instruction_list}"       # Instructions to CE.
  [[ $node_location != "lond" || $node_location != "amst" ]] && echo -e "*Note: If any assistance is needed, contact your FSS."
  echo -e "\nIssue Description: ${issue_description}.";   printf '%.0s-' {1..58}
  echo -e "\n${customer_contact_info}${customer_contact_location}";   echo -e "Next Action:\tDispatch CE onsite\nPlease notify the CE to contact ${customer_name} prior to going on site and to complete the above tasks in their entirety.\n ${clear_color}";   
  echo -e "\n${template_footer}";printf '%.0s=' {1..80};echo
  [[ display_test_switch -eq 1 ]] || echo -e "$(date +'%x %X') $problem_node $0 -$1 Reason: $template_dispatch_reason TLA#:${tla_number} GEN${hardware_gen} ${template_additional_info}" >> $log_dispatch
  return 0
##Variable Fields  
# template_header="";             template_dispatch_reason="";    template_additional_info="";   template_var_line1="";   template_var_line2=""
# template_instruction_list="";   issue_description="";           template_footer=""
}
  
prepare_disk_template() {         # Prepares input for use in display_disk_template function.
  # Check if disk is ready for replacement:
  disk_sn_uuid=$(psql -U postgres -d rmg.db -h ${RMG_MASTER} -t -c "select diskuuid from fsdisks where fsuuid='${fsuuid_var}';"| awk 'NR==1{print $1}')
  disk_status=$(psql -U postgres rmg.db -h ${RMG_MASTER} -t -c "select status from disks where uuid='$disk_sn_uuid'"| awk 'NR==1{print $1}')
  disk_replaceable_status=$(psql -U postgres rmg.db -h ${RMG_MASTER} -t -c "select replacable from disks where uuid='$disk_sn_uuid'"| awk 'NR==1{print $1}')
  recovery_status=$(psql -U postgres rmg.db -h ${RMG_MASTER} -t -c "select status from recoverytasks where fsuuid='${fsuuid_var}'"| awk 'NR==1{print $1}')
  if [[ disk_replaceable_status -eq 0 ]]; then
    is_disk_replaceable ${disk_replaceable_status} ${disk_status} ${recovery_status} 
    echo -e "${boldwhite}" 
    read -p "# Are you sure you'd like to proceed? (y/n) " -t 120 -n 1 -s unreplaceable_continue 
    echo -e "${clear_color}" 
    [[ "$unreplaceable_continue" =~ [yY] ]] && echo -e "\n" || cleanup "Please try again once the disk is recovered." 99
  fi
  fail_count=0
  disk_size=`df --block-size=1T | awk '/mauiss/ {n=$2}; END {print n}'`
  set_customer_contact_info
  set_disk_part_info $hardware_gen $disk_size $atmos_ver3
  set_disk_type $hardware_gen $atmos_ver3
  [[ if_mixed ]] && replace_method="Admin GUI or CLI" || replace_method="CLI"
  validate_fsuuid_text_file
  disk_slot=$(psql -U postgres -d rmg.db -h $RMG_MASTER -t -c "select d.slot from fsdisks fs RIGHT JOIN disks d ON fs.diskuuid=d.uuid where fsuuid='${fsuuid_var}';" | tr -d ' |\n') 
  psql -U postgres -d rmg.db -h $RMG_MASTER -c "select d.devpath,d.slot,d.status,d.connected,d.slot_replaced,d.uuid,d.replacable from fsdisks fs RIGHT JOIN disks d ON fs.diskuuid=d.uuid where fsuuid='${fsuuid_var}';" | egrep -v '^$|row'
  
  template_dispatch_reason="Disk Ready for Replacement"
  template_additional_info="Disk Type:\t${disk_type}\nDisk Model:\t${model_num}\nPart Number:\t${lt_green}${part_num}${lt_gray}\nDisk Serial#:\t${disk_sn_uuid}\nDAE Slot#:\t${disk_slot}\nDisk Capacity:\t$disk_size TB\nDisk FSUUID:\t${fsuuid_var}"
  template_instruction_list="\n1- Contact ${customer_name} and arrange for disk replacement prior to going on site.\n2- Follow procedure document for replacing GEN${hardware_gen} DAE Disk for Atmos ${atmos_ver5} using ${replace_method}.\n3- Notify ${customer_name} when disk replacement is completed."
  issue_description="Failed disk is ready for replacement"

  display_template_body
  return 0
}

is_disk_replaceable () { 			    # Checks the status of the recovery and replacement
  [[ $(echo ${#disk_sn_uuid}) -ne 8 ]] && return 1
  unrec_obj_num=$(psql -U postgres rmg.db -h ${RMG_MASTER} -t -c "select unrecoverobj from recoverytasks where fsuuid='${fsuuid_var}'"| awk 'NR==1{print $1}')
  impacted_obj_num=$(psql -U postgres rmg.db -h ${RMG_MASTER} -t -c "select impactobj from recoverytasks where fsuuid='${fsuuid_var}'"| awk 'NR==1{print $1}')
  [[ ${#unrec_obj_num} -eq 0 ]] && percent_recovered=$(echo -e ${lt_cyan}"Not found"${white}) || [[ ${unrec_obj_num} -eq 0 || ${impacted_obj_num} -eq 0 ]] && percent_tmp=0 || percent_tmp=$(echo "scale=6; 100-${unrec_obj_num}*100/${impacted_obj_num}"|bc|cut -c1-5)
  percent_recovered=$(echo -e ${lt_yellow}${percent_tmp}"%"${lt_gray})
  clear; echo -e "\n\n"; not_repl_txt='Disk is not currently marked replaceable.'  
  case "$1:$2:$3" in   	# echo "Replacement: ${disk_replaceable_status}  Disk status: ${disk_status}  RecoveryStatus: ${recovery_status}"
        0:*:1)  	echo -e "${red}# $not_repl_txt \n${lt_gray}# RecoveryStatus: ${yellow}Cancelled/Paused${lt_gray}\n# Objects ${percent_recovered} recovered."  ;;		
        0:*:2)  	#echo -e "${green}# Recovery completed, however the replaceable bit needs to be changed to a 1 in the disks table.${lt_gray}"
                  mark_disk_replaceable  ;;        
        0:*:3)  	echo -e "${red}# $not_repl_txt \n${lt_gray}# RecoveryStatus: ${green}In Progress		${lt_gray}\n# Objects ${percent_recovered} recovered."    ;;		
        0:*:[45]) echo -e "${red}# $not_repl_txt \n${lt_gray}# RecoveryStatus: ${red}FAILED/ABORTED		${lt_gray}\n# Objects ${percent_recovered} recovered."    ;;    
        0:*:6)  	echo -e "${red}# $not_repl_txt \n${lt_gray}# RecoveryStatus: ${yellow}Pending			${lt_gray}\n# Objects ${percent_recovered} recovered."      ;;		
        0:*:*)  	echo -e "${red}# $not_repl_txt \n${lt_gray}# RecoveryStatus: ${yellow}Status not found${lt_gray}\n# Objects ${percent_recovered} recovered."  ;;		
        1:6:*)  	touch /var/service/fsuuid_SRs/${fsuuid_var}.txt; touch /var/service/fsuuid_SRs/${fsuuid_var}.info
                  [[ $(grep -c "^" /var/service/fsuuid_SRs/${fsuuid_var}.txt) -eq 1 ]] && for log in $(ls -t /var/log/maui/cm.log*); do bzgrep -m1 "Successfully updated replacable bit for $disk_sn_uuid" ${log} | awk -F\" '{print $2}' >> /var/service/fsuuid_SRs/${fsuuid_var}.info && break; done
                  [[ $(cat /var/service/fsuuid_SRs/${fsuuid_var}.txt | wc -l) -eq 1 ]] && date >> /var/service/fsuuid_SRs/${fsuuid_var}.info
                  set_replaced=$(cat /var/service/fsuuid_SRs/${fsuuid_var}.txt | tail -1)
                  date_replaceable=$(date +%s --date="$set_replaced")
                  date_plus_seven=$((604800+${date_replaceable}))
                  past_seven=''
                  [[ $(date +%s) -ge ${date_plus_seven} ]] && past_seven=$(echo "Disk has been replaceable over 7 days, please check the SR")
                  echo -e "# Replaceable="${green}"Yes"${white} "DiskSize="${yellow}${fsuuid_var}size"TB"${white} ${past_seven}        ;;
        1:4:*)  	echo -e "# The disk is set for replaceable, Disk status is set to 4. The disk may not be seen by the hardware"       ;;
        1:*:*)  	echo -e "# Disk set for replaceable, but status is incorrect. Please update status=6 in disks table.\n# Can use \"${script_name} -b\" to do this automatically."  ;;
        *)  cleanup "Something failed... " 144   ;;
    esac
  return 0
}

validate_fsuuid_text_file(){      # validate the fsuuid file for show_offline_disks script.
  [[ -z $fsuuid_var && $1 -ne 1 ]] && get_fsuuid
  if [[ ! -e /var/service/fsuuid_SRs/${fsuuid_var}.txt ]]; then 
    echo -e "${red}# No show_offline_disks text file found for fsuuid: ${fsuuid_var}! ${clear_color}"
    read -p "# Would you like to create the file? (y/Y) " -n 1 -s -t 120 create_text_file_flag
    [[ $create_text_file_flag =~ [yY] ]] && { [[ -z $sr_number ]] && { read -p "# Enter new SR#: " -t 600 -n 8 new_sr_num && sr_number=${new_sr_num} || cleanup "Timeout: No SR# given." 181; }; echo -en "${fsuuid_var},${sr_number}" > /var/service/fsuuid_SRs/${fsuuid_var}.txt; validate_fsuuid_text_file 1; return 0; } || cleanup "File not created." 191
  else
    [[ $display_test_switch -eq 1 ]] && echo "test validate_fsuuid_text_file 1"
    #Check that the file is valid.. fsuuid,sr#session..etc.
    #file_text=$(cat /var/service/fsuuid_SRs/${fsuuid_var}.txt | head -1)
    [[ ! "$(cat /var/service/fsuuid_SRs/${fsuuid_var}.txt | head -1)" =~ .*${fsuuid_var}.* ]] && sed -i "1 s/^/${fsuuid_var}/;q" /var/service/fsuuid_SRs/${fsuuid_var}.txt
    [[ ! "$(cat /var/service/fsuuid_SRs/${fsuuid_var}.txt | head -1)" =~ .*,.* ]] && sed -i "1 s/${fsuuid_var}/&,/;q" /var/service/fsuuid_SRs/${fsuuid_var}.txt
    [[ "$(cat /var/service/fsuuid_SRs/${fsuuid_var}.txt | head -1)" =~ .*,[0-9]{8}.* ]] && sr_number=$(awk -F",|-D|_|#" 'NR==1 {print $2}' /var/service/fsuuid_SRs/${fsuuid_var}.txt) || update_sr_num 1 
    # validate sr number?
    [[ ! "$(cat /var/service/fsuuid_SRs/${fsuuid_var}.txt | head -1)" =~ .*${sr_number}.* ]] && update_sr_num 2
    [[ $display_test_switch -eq 1 ]] && echo "test validate_fsuuid_text_file 2"
    return 0
  fi
  return 2
}

update_sr_num() {					        # Reference SR number in show_offline_disks script . info file.
  if [[ $1 -eq 1 ]]; then
    [[ -z "$sr_number" ]] && { echo -e "${red}# No SR# found in show_offline_disks text file. If new SR is needed, use -u option for site/tla info.${clear_color}";read -p "# Enter SR#: (ctrl-c to quit)" -t 600 -n 8 new_sr_num && { echo; sr_number=${new_sr_num}; } || cleanup "Timeout: No SR# given." 181; }
    sed -i "1 s/,/,${new_sr_num}/" /var/service/fsuuid_SRs/${fsuuid_var}.txt
    [[ display_test_switch -eq 1 ]] || echo -e "$(date +'%x %X') $problem_node $0 Updated SR#${new_sr_num} in .txt file." >> $log_dispatch
  elif [[ $1 -eq 2 ]]; then
    echo "# SR# given doesn't match number on record. Please work through the current SR ${sr_number}. Would you like to reference your current SR in the notes file? (y/Y) "
    read -s -n 1 -t 120 update_sr_num_flag; [[ "${update_sr_num_flag}" =~ [yY] ]] || return 2
    echo "note_referenced_SR=${new_sr_num} - added $(date)" >> /var/service/fsuuid_SRs/${fsuuid_var}.info
    [[ display_test_switch -eq 1 ]] || echo -e "$(date +'%x %X') $problem_node $0 Referenced SR#${new_sr_num} in .info file." >> $log_dispatch
  else
    echo -e "${red}# Will associate new SR# given in the .info file.\nPlease ensure the new SR has been opened against Site ID: ${site_id} TLA: ${tla_number} Host: $HOSTNAME"validate_fsuuid_text_file
    [[ -z "$new_sr_num" ]] && read -p "# Enter new SR#: " -t 600 -n 8 new_sr_num || cleanup "Timeout: No SR# given." 181          # Validate sr number?      
    echo "note_referenceSR=${new_sr_num} - added $(date)" >> /var/service/fsuuid_SRs/${fsuuid_var}.info                           # Write new SR num to txt file.
    echo -e "\n# SR# ${new_sr_num} has been added to the show_offline_disks .info file.${clear_color}"
    [[ display_test_switch -eq 1 ]] || echo -e "$(date +'%x %X') $problem_node $0 Referenced SR#${new_sr_num} in .info file." >> $log_dispatch
  fi
  return 0
}

append_dispatch_date() {			    # Write date to show_offline file.  
# Appends dispatch date in show_offline_disks script text file.
  validate_fsuuid_text_file 1
  [[ -e /var/service/show_offline_disks.sh ]] && show_offline_disks_ver=$(/var/service/show_offline_disks.sh -v) || echo -e "${red}# Error: show_offline_disks.sh version not detected.${clear_color}"
  [[ $display_test_switch == 1 ]] && echo "Show offline version: ${show_offline_disks_ver}"
  case "${show_offline_disks_ver}:${atmos_ver3}:${hardware_gen}" in   						
  # hardware_gen:atmos_ver3
    1.[0-5].[0-9]*:*)                                 # For versions pre .info file - add SR# in text file.
        if [[ "$(cat /var/service/fsuuid_SRs/${fsuuid_var}.txt | head -1)" =~ .*-Dispatched_[0-1][0-9]-[0-3][0-9]-[0-9][0-9]_.* ]]; then 
          echo -e "${red}# Dispatch date already appended to .txt file. Please check to ensure this disk hasn't already been dispatched 
          against.${clear_color} " 
          read -p "# Would you like to proceed with updating the dispatch date? (y/Y) " -s -n 1 -t 120 redispatch_flag
          [[ ${redispatch_flag} =~ [yY] ]] || cleanup "" 192
          sed -i "s/-Dispatched_[0-1][0-9]-[0-3][0-9]-[0-9][0-9]_/-Dispatched_$(date +%m-%d-%y)_/" /var/service/fsuuid_SRs/${fsuuid_var}.txt
        elif
          [[ ! "$(cat /var/service/fsuuid_SRs/${fsuuid_var}.txt | head -1)" =~ .*'#session'.* ]]; then
          sed -i "1s/\(,[0-9]\{8\}\)\($\)/\1-Dispatched_$(date +%m-%d-%y)_\2/" /var/service/fsuuid_SRs/${fsuuid_var}.txt
        else 
          sed -i "1s/\(,[0-9]\{8\}\)\([#_]\)/\1-Dispatched_$(date +%m-%d-%y)_\2/" /var/service/fsuuid_SRs/${fsuuid_var}.txt
        fi
        echo -e "\n${lt_green}# Dispatch date has been appended to show_offline_disks text file: ${clear_color}"
        awk -F"," 'NR==1 {print $0}' /var/service/fsuuid_SRs/${fsuuid_var}.txt
      ;;
    1.[6-9].[0-9]*:*|[2-9].[0-9].[0-9]*:*)            # For versions post .info file
        if [[ "$(grep -c 'Date_dispatched=' /var/service/fsuuid_SRs/${fsuuid_var}.info)" -gt 0 ]]; then 
          echo -e "${red}# Dispatch date already appended to .info file. Please check to ensure this disk hasn't already been dispatched against.${clear_color} " 
          read -p "# Would you like to proceed with updating the dispatch date? (y/Y) " -s -n 1 -t 120 redispatch_flag
          [[ ${redispatch_flag} =~ [yY] ]] || cleanup "" 193
          sed -i "s/Date_dispatched=[0-1][0-9]-[0-3][0-9]-[0-9][0-9]/Date_dispatched=$(date +%m-%d-%y)/" /var/service/fsuuid_SRs/${fsuuid_var}.info
        else 
          echo "Date_dispatched=$(date +%m-%d-%y)" >> /var/service/fsuuid_SRs/${fsuuid_var}.info
        fi
        echo -e "\n${lt_green}# Dispatch date has been appended to show_offline_disks .info file: ${clear_color}"
        grep "Date_dispatched" /var/service/fsuuid_SRs/${fsuuid_var}.info
      ;;
    *)                              
    # Catch-all
        echo -e "${red}# Error: invalid show_offline_disks.sh version.\n# Date not written to file.${clear_color}"
      ;;
  esac
  return 0
}

set_customer_contact_info() {		  # Set Customer contact info/location.
  #source_directory="${BASH_SOURCE%/*}"; [[ ! -d "$source_directory" ]] && source_directory="$PWD"
  #. "$source_directory/incl.sh"
  #. "$source_directory/main.sh"
  [[ -f "${customer_site_info_file}" ]] && . "${customer_site_info_file}"
  
  eval is_att_rocc_system=\$$node_location
  if [[ ${#is_att_rocc_system} -gt 0 && "${is_att_rocc_system}" =~ "AT&T"[\ ]* ]] ; then
    customer_name="ROCC"
    cust_con_name="rocc@roccops.com"
    cust_con_numb="877-362-0253"
    cust_con_time="(7x24x356)"
    customer_contact_location="\nSite Location: \n${is_att_rocc_system}\n"
    customer_contact_info="Contact Name:\t${cust_con_name}\nContact Num.:\t${cust_con_numb}\nContact Time:\t${cust_con_time}"
  else
    [[ $display_test_switch -eq 1 ]] && return 0
    customer_name="customer"
    echo -e "${lt_green}"
    read -p "# Enter customer's name: " -t 300 cust_con_name || cleanup "Timed out. Please get the information and try again." 111
    read -p "# Enter customer's number: " -t 300 cust_con_numb || cleanup "Timed out. Please get the information and try again." 112
    read -p "# Enter customer's available contact time: " -t 300 cust_con_time || cleanup "Timed out. Please get the information and try again." 113
    read -p "# Enter site's address: (Press \"Enter\" to skip..)" -t 300 cust_con_location || cleanup "Timed out. Please get the information and try again." 114
    echo -e "${clear_color}"
    customer_contact_info="Contact Name:\t${cust_con_name}\nContact Num.:\t${cust_con_numb}\nContact Time:\t${cust_con_time}"
    [[ ${#cust_con_location} -gt 1 ]] && customer_contact_location="\nLocation: ${cust_con_location}\n" || customer_contact_location=""
  fi
  return 0
}

set_disk_type() {					        # Sets disk type.
  [[ $display_test_switch -eq 1 ]] && timeout_value='2s' || timeout_value='45s'
  if_mixed=$(timeout "${timeout_value}" ssh $RMG_MASTER grep dmMixDriveMode /etc/maui/maui_cfg.xml | grep -c true)
  (( $if_mixed )) && disk_type="MIXED SS/MDS" && return 0
  
  disk_type_temp=$(psql -tq -U postgres rmg.db -h $RMG_MASTER -c "select mnt from filesystems where uuid='${fsuuid_var}'" | awk '{print substr($1,1,6)}')
  [[ "$disk_type_temp" == "/atmos" ]] && disk_type="MDS" || disk_type="SS"
  return 0
}

set_disk_part_info() {				    # Gets and sets disk part info.
  
    case "$1:$2:$3" in   						# hardware_gen:disk_size:atmos_ver3
    1:1:*)  	                  # Gen 1 hardware - 1TB disk
      part_num='005048818'				  # part: 005048818
      model_num='HUA721010KLA330'		# model: HUA721010KLA330
      ;;		
    1:[234]:*)  	                  # Gen 1 Hardware - 2TB,3TB, or 4TB disk
      cleanup "Error: Disk is showing as ${2}TB, but in Gen${1} hardware." 31
      ;;
    2:[14]:*)                     	# Gen 2 Hardware - 1TB or 4TB disk
      cleanup "Error: Disk is showing as ${2}TB, but in Gen${1} hardware." 32
      ;;
    2:2:*)  	                      # Gen 2 hardware - 2TB disk
      part_num='005049565'				  # part: 005049565
      model_num='HUA723020ALA640'		# model: HUA723020ALA640
      ;;
    2:3:*)  	                      # Gen 2 hardware - 3TB disk
      part_num='005049828'				  # part: 005049828
      model_num='HUA723030ALA640'		# model: HUA723030ALA640
      ;;
    3:[12]:*)  	                    # Gen 3 Hardware - 1TB or 2TB disk
      cleanup "Error: Disk is showing as ${2}TB, but in Gen${1} hardware." 31
      ;;
    3:3:*)  	                      # Gen 3 Hardware - 3TB disk
      part_num='005049828'			    # part: 005049828
      model_num='HUA723030ALA640'		# model: HUA723030ALA640
      ;;
    3:4:*)		                      # Gen 3 Hardware - 4TB disk
      part_num='005050062'				  # part: 005050062
      part_description=''           # 
      model_num='HUS724040ALA640'		# model: HUS724040ALA640
      ;;
    *)  cleanup "Gen${1} / ${2}TB Disk size combination not supported yet. \nPlease email Claiton.Weeks@emc.com to get corrected. " 004
      ;;
    esac
  return 0
}

get_hardware_gen() {				      # Gets and sets HW Gen.
  hardware_product=$(dmidecode | awk '/Product Name/{print $NF; exit}')
    case "$hardware_product" in
    1950)                       # > Dell 1950 is the Gen 1 hardware
      hardware_gen=1
      [[ $display_test_switch -eq 1 ]] && echo "Hardware Gen: $hardware_gen"
      return 0
            ;;
    R610)                       # > Dell r610 is the Gen 2 hardware.
      hardware_gen=2
      [[ $display_test_switch -eq 1 ]] && echo "Hardware Gen: $hardware_gen"
      return 0
      ;;
    S2600JF)                    # > Product Name: S2600JF is Gen3 
      hardware_gen=3
      [[ $display_test_switch -eq 1 ]] && echo "Hardware Gen: $hardware_gen"
      return 0
      ;;
        *)  cleanup "Invalid hardware information. Could not determine generation. Please email Claiton.Weeks@emc.com to get corrected. " 51
      ;;
    esac
    return
}

get_fsuuid() { 						        # Get fsuuid from user.
  [[ ${display_test_switch} -eq 1 ]] && echo "test get_fsuuid 1"
  if [[ $1 -eq 0 ]]
  then
    [[ ${display_test_switch} -eq 1 ]] && echo "test get_fsuuid 2"
    [[ -d /var/service/ ]] || cleanup "/var/service directory not found" 152
    [[ -e /var/service/show_offline_disks.sh ]] || cleanup "/var/service/show_offline_disks.sh script not found" 152
    echo -e "\n# Please wait... running ${lt_green}show_offline_disks.sh${clear_color}"
    offline_disks=$(/var/service/show_offline_disks.sh -l)
    [[ -z $offline_disks ]] && { echo -e "${lt_green}# No offline disks found.\n# Exiting.${clear_color}"; cleanup "" 0; }
  else 
    [[ ${display_test_switch} -eq 1 ]] && echo "test get_fsuuid 3"
    echo "# Please choose a fsuuid from an offline disk: "
  fi
  
  [[ ${display_test_switch} -eq 1 ]] && echo "test get_fsuuid 4"
  echo -e "\n${offline_disks}\n\E[21m${clear_color}${lt_green}"
  read -p "# Enter fsuuid for disk to dispatch: " -t 120 -n 36 fsuuid_var || cleanup "Timeout: FSUUID not given." 151
  echo -e "${clear_color}\n"
  if [[ ! validate_fsuuid ]]; then
  [[ ${display_test_switch} -eq 1 ]] && echo "test get_fsuuid 6"
    fail_count=$((fail_count+1))
    [[ "$fail_count" -gt 4 ]] && cleanup "Please try again with a valid fsuuid." 60
    #clear
    echo -e "\n\n${red}# Invalid fsuuid attempt: $fail_count, please try again.${clear_color}"
    get_fsuuid $fail_count
    else [[ -n ${fsuuid_var} ]] && dev_path=$(blkid | grep ${fsuuid_var} | sed 's/1.*//')
  [[ ${display_test_switch} -eq 1 ]] && echo "test get_fsuuid 7"
    return 0
  fi 
  [[ ${display_test_switch} -eq 1 ]] && echo "test get_fsuuid 8"
  return 1
  [[ ${display_test_switch} -eq 1 ]] && echo "test get_fsuuid 9"

}

validate_fsuuid() {					      # Validate fsuuid against regex pattern.
  [[ ${display_test_switch} -eq 1 ]] && echo "test validate_fsuuid 10"
  if [[ -z ${fsuuid_var} ]]; then
    get_fsuuid $fail_count
  else
    valid_fsuuid='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' # Regex to confirm a valid UUID - only allows for hexidecimal characters.
    valid_fsuuid_on_host=$(psql -t -U postgres rmg.db -h $RMG_MASTER -c "select fs.fsuuid from disks d join fsdisks fs ON d.uuid=fs.diskuuid where d.nodeuuid='$node_uuid' and fs.fsuuid='${fsuuid_var}'"| awk 'NR==1{print $1}')
    if [[ ! ${#valid_fsuuid_on_host} -eq 36 ]] ; then
      [[ ${display_test_switch} -eq 1 ]] && echo "test validate_fsuuid 12"
      echo -e "${red}# FSUUID not found on host.\n# Please try again.${clear_color}"
      get_fsuuid $fail_count
    else
      [[ ${display_test_switch} -eq 1 ]] && echo "test validate_fsuuid 13"
      [[ "${fsuuid_var}" =~ $valid_fsuuid ]] && return 0 || echo -e "${red}# Invalid fsuuid.${clear_color}" && get_fsuuid
    fi
    [[ ${display_test_switch} -eq 1 ]] && echo "test validate_fsuuid 14"
    return 1
  fi
  
  [[ ${display_test_switch} -eq 1 ]] && echo "test validate_fsuuid 15"
  return 1
  # valid_fsuuid='^[[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}$' # Regex to confirm a valid UUID - allows for letters g-z, which aren't allowed 
  # valid_fsuuid='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' # Regex to confirm a valid UUID - allows for capital letters, which aren't allowed.
  # if [[ "${fsuuid_var}" != [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f] ]]
    # then echo -e "${red}# Invalid fsuuid.${clear_color}"
    # get_fsuuid
    # else return 0
  # fi
    [[ ${display_test_switch} -eq 1 ]] && echo "test validate_fsuuid 16"

}

distribute_script() {				      # Distribute script across all nodes, and sets permissions.
  [[ display_test_switch -eq 1 ]] || echo -e "$(date +'%x %X') $problem_node $0 -x Self-distributing across system.  " >> $log_dispatch
  mauirexec "/bin/rm -f /var/service/dispatch_template-*" | awk '/Output/{n=$NF}; !/Output|^$|Runnin/{print n": "$0}'
  dts_line_number=$(grep -n -m1 display_test_switch /var/service/dispatch_template.sh |awk -F: '{print $1}')
  [[ "${display_test_switch}" -eq 1 ]] && { sed -i "${dts_line_number}s/  display_test_switch=1/  display_test_switch=0/" ${full_path} && testing_switch_flag=1; }
  script_loc="/var/service"
  [[ "$script_name" == "$this_script" ]] || cleanup "Please rename script to $script_name and try again. (err: $this_script)" 20
  if ! [[ -z $list_location ]]; then
    dispatch_template.sh -v || cleanup "dispatch script failed to run." 28 
    time for x in `cat $list_location`; do echo -n "$x  -  ";ssh $x 'echo "$HOSTNAME"' && { echo -n "# Copying script: ";scp $full_path $x:$script_loc/ ; [[ -e /usr/local/bin/customer_site_info ]] && scp /usr/local/bin/customer_site_info $x:/usr/local/bin/;ssh $x sh $script_loc/dispatch_template.sh -x; }; done && exit 0 || cleanup "Distributing through list file failed." 29
  fi
  echo -en "\n# Distributing script across all nodes.. "
  copy_script=$(mauiscp ${full_path} ${full_path} | awk '/Output/{n=$NF}; !/Output|^$|Runnin/{print n": "$0}' | wc -l)
  [[ $copy_script -eq 0 ]] && echo -e "${lt_green}Done!${clear_color} ($this_script copied to all nodes)" || { echo -e "${red}Failed.${clear_color}";fail_flag=1; fail_text="Failed to copy $this_script to all nodes"; }
  if [[ -e "${customer_site_info_file}" ]]; then
    echo -en "# Detected customer site info file. Distributing file across all nodes.. "
    copy_cust_info_file=$(mauiscp ${customer_site_info_file} ${customer_site_info_file} | awk '/Output/{n=$NF}; !/Output|^$|Runnin/{print n": "$0}' | wc -l)
    [[ $copy_cust_info_file -eq 0 ]] && echo -e "${lt_green}Done!${clear_color} (File copied to all nodes)" || { echo -e "${red}Failed.${clear_color}";fail_flag=1; fail_text="Failed to copy $this_script to all nodes"; }
  fi
  echo -en "# Setting script permissions across all nodes.. "
  set_permissions=$(mauirexec "chmod +x ${full_path}" | awk '/Output/{n=$NF}; !/Output|^$|Runnin/{print n": "$0}' | wc -l)
  [[ $set_permissions -eq 0 ]] && echo -e "${lt_green}Permissions set!${clear_color}" || { echo -e "${red}Failed.${clear_color}";fail_flag=1; fail_text="Failed to set permissions across all nodes"; }
  echo -en "# Creating symlink in /var/service/ directory.. "
  mauirexec "[[ -e /var/service/$this_script ]] && /bin/rm -f /var/service/$this_script" | awk '/Output/{n=$NF}; !/Output|^$|Runnin/{print n": "$0}'
  create_sym_link=$(mauirexec "ln -s ${full_path} /usr/local/bin/${this_script}"| awk '/Output/{n=$NF}; !/Output|^$|Runnin/{print n": "$0}' | wc -l)
  [[ $create_sym_link -eq 0 ]]  && echo -e "${lt_green}Done!${clear_color}" || echo -e "${red} Failed.${clear_color}"
  [[ ${fail_flag} -eq 1 ]] && { mauirexec -e "${full_path} -v" | awk '/Output/{n=$NF;m++}; !/Output|^$|Runnin|is 0|dispatch/{l++;print n": Error "}';cleanup "${fail_text}" 21; }
  echo -e "\n\n"
  [[ $testing_switch_flag -eq 1 ]] && sed -i "${dts_line_number}s/  display_test_switch=0/  display_test_switch=1/" ${full_path}
  exit 0
}

update_script(){                  # Allows for updating script with passcode.
  [[ display_test_switch -eq 1 ]] || echo -e "$(date +'%x %X') $problem_F $0 Update from console." >> $log_dispatch
  display_test_switch=0
    [[ "$script_name" == "$this_script" ]] || cleanup "Please rename script to $script_name and try again." 20
  read -p "Update script: please enter passcode: " -t 30 -s -n 4 update_passcode_ver || cleanup "Timeout: No passcode given." 252
  echo -e "\n${full_path}";sleep 1
  [[ ${update_passcode_ver} == "7777" ]] && { vim ${full_path}_tmp && wait && [[ -n $(bash ${full_path}_tmp -v | awk -F":| " '/version/{print $5}') ]] && { /bin/mv -f ${full_path}_tmp ${full_path}; wait; chmod +x ${full_path}; echo -e "${lt_green}# Updated successfully!";echo "$(${full_path} -v)";${full_path} -x;cleanup "Updated successfully!" 0; } || cleanup "update failed..." 253; } || { cleanup "wrong code..." 254;exit 254; }
  cleanup "Wrong passcode entered. Exiting." 255
}

init_colors() {						        # Initialize text color variables.
foreground=$(echo -e "\E[39m");   black=$(echo -e "\E[30m");      red=$(echo -e "\E[31m");        green=$(echo -e "\E[32m");      yellow=$(echo -e "\E[33m")
blue=$(echo -e "\E[34m");         magenta=$(echo -e "\E[35m");    cyan=$(echo -e "\E[36m");       lt_gray=$(echo -e "\E[37m");    dark_gray=$(echo -e "\E[90m")
lt_red=$(echo -e "\E[91m");       lt_green=$(echo -e "\E[92m");   lt_yellow=$(echo -e "\E[93m");  lt_blue=$(echo -e "\E[94m");    lt_magenta=$(echo -e "\E[95m")
lt_cyan=$(echo -e "\E[96m");      white=$(echo -e "\E[97m");      green2=$(echo -e "\E[0;32m");   blue2=$(echo -e "\E[1;34m");    boldwhite=$(echo -e "\E[1;97m")
orange=$(echo -e "\E[0;33m");     default=$(echo -e "\E[0m");     clear_color=$(echo -e "\E[0m")
}

prep_int_disk_template() {        # Prepares input for use in display_template_body function.
  case "${hardware_gen}:${atmos_ver3}" in   						# hardware_gen:atmos_ver3
    [12]:*)  	                        # Gen 1 hardware
      if [[ -z ${internal_disk_dev_path} ]]; then
        echo -en "\n${lt_green}# Gen${hardware_gen}: Enter internal disk's device slot/ID ( 0:0:0 / 0:0:1 ) [0 or 1 is fine]: "
        read -t 120 -n 5 internal_disk_dev_path || cleanup "Timeout: No internal disk given." 171
        echo -e "\n${clear_color}"
      fi
      [[ ${internal_disk_dev_path} == "0" ]] && internal_disk_dev_path="0:0:0"
      [[ ${internal_disk_dev_path} == "1" ]] && internal_disk_dev_path="0:0:1"
      [[ ${internal_disk_dev_path} =~ "0:0:"[01] ]] || cleanup "Internal disk slot#/ID# not recognized." 131
      [[ ${hardware_gen} -eq 1 ]] && { part_num='105-000-160';int_disk_description='250GB 7.2K RPM 3.5IN DELL SATA DRV/SLED' ;int_disk0_placement='left';int_disk1_placement='right'; }
      [[ ${hardware_gen} -eq 2 ]] && { part_num='105-000-179';int_disk_description='DELL 250GB 7.2KRPM SATA2.5IN DK 11G SLED';int_disk0_placement='top';int_disk1_placement='bottom'; }
      [[ ${internal_disk_dev_path} == "0:0:0" ]] && int_disk_dev_num='0'; [[ ${internal_disk_dev_path} == "0:0:1" ]] && int_disk_dev_num='1'
      disk_sn_uuid=$(omreport storage pdisk controller=0 | grep -A28 ": 0:0:${int_disk_dev_num}" | awk '/Serial No./{print $4}') && omreport storage pdisk controller=0 | grep -A28 ": 0:0:${int_disk_dev_num}" && int_drive_loc_note="Drive ID 0:0:${int_disk_dev_num} is the ${int_disk${int_disk_dev_num}_placement} drive"
      omreport storage vdisk controller=0|grep "State"; omreport system alertlog | grep -B1 -A4 ": 2095"
      omreport system alertlog | grep -A5 ": Critical"; grep -B1 -A3 'Sense key: 3' /var/log/messages
      template_var_line1="Dev ID/Slot:\t${internal_disk_dev_path}"
      template_var_line2="Note: Each drive’s slot is labeled 0 or 1 at the node. ${int_drive_loc_note}."
      # Gen 1 (Dell 1950 III) Server Platform internal 3.5” SATA Drive: 105-000-160 (250GB)   "250GB 7.2K RPM 3.5IN DELL SATA DRV/SLED"
      # Gen 1 (Dell 1950 III) Server Platform internal 3.5” SATA Drive: 105-000-153 (500GB)   "500GB 7.2K RPM 3.5IN DELL 10K SATA SLED"
      # Note: 105-000-160 and 105-000-153 are compatible. Refer to Product Compatibility Database for latest compatibility information. (https://alliance.emc.com/Pages/PcdHome.aspx)
      # Gen 2 (Dell R610) Server Platform internal 2.5” SATA Drive: 105-000-179   "DELL 250GB 7.2KRPM SATA2.5IN DK 11G SLED"
      ;;		
    3:*)                            # Gen 3 Hardware
      [[ $display_test_switch == 1 ]] && echo $internal_disk_dev_path
      if [[ -z ${internal_disk_dev_path} ]]; then
        echo -en "\n${lt_green}# Enter internal disk's device path (sda/sdb): "
        read -t 120 -n 3 internal_disk_dev_path || cleanup "Timeout: No internal disk given." 171
        echo -e "\n${clear_color}"
      fi
      [[ ${internal_disk_dev_path} == "a" ]] && internal_disk_dev_path="sda"
      [[ ${internal_disk_dev_path} == "b" ]] && internal_disk_dev_path="sdb"
      [[ ${internal_disk_dev_path} =~ "sd"[ab] ]] || cleanup "Internal disk device path not recognized." 131
      part_num='105-000-316-00'
      int_disk_description='300GB 2.5" 10K RPM SAS 512bps DDA ATMOS'
      internal_uuid=$(mdadm -D /dev/md126 | awk '/UUID/{print $3}')
      [[ ${internal_disk_dev_path} == "sda" ]] && disk_sn_uuid=$(smartctl -i /dev/sg0 | awk '/Serial number/{print $3}')
      [[ ${internal_disk_dev_path} == "sdb" ]] && disk_sn_uuid=$(smartctl -i /dev/sg1 | awk '/Serial number/{print $3}')
      int_dev_path="/dev/${internal_disk_dev_path}"
      template_var_line1="Raid UUID:\t${internal_uuid}"
      template_var_line2="Dev Path:\t${int_dev_path}"
      echo -e "\n${lt_cyan}# Checking utilization of disks, please wait 30 seconds: (iostat -xk 10 3 /dev/sda /dev/sdb) ${clear_color}\n" && iostat -xk 10 3 /dev/sda /dev/sdb
      echo -e "\n${lt_cyan}# Checking Raid status: (cat /proc/mdstat) ${clear_color}\n" && cat /proc/mdstat
      echo -e "\n${lt_cyan}# Checking Raid status: (mdadm -D /dev/md126) ${clear_color}\n" && mdadm -D /dev/md126
      echo -e "\n${lt_cyan}# Checking Disk status: (mdadm -E ${int_dev_path}) ${clear_color}\n" && mdadm -E ${int_dev_path}
      echo -e "\n${lt_cyan}# Checking Disk health: (smartctl -x ${int_dev_path}) ${clear_color}\n" && smartctl -x ${int_dev_path}
      echo -e "\n${lt_cyan}# Checking Disk health: (sg_inq ${int_dev_path}) ${clear_color}\n" && sg_inq ${int_dev_path}
      ;;
    *) cleanup "Hardware Gen / Internal disk type detection failed." 130
      ;;
    esac

  set_customer_contact_info
  disk_type='Internal'
  replace_method=" - FRU Replacement Procedure"
  template_dispatch_reason="Internal* Disk Replacement\n*Note:\tINTERNAL DISK!!!"
  template_additional_info="Disk Type:\t${disk_type}\nDescription:\t${int_disk_description}\nPart Number:\t${lt_green}${part_num}${lt_gray}\nDisk Serial#:\t${disk_sn_uuid}"
  template_instruction_list="\n1- Contact ${customer_name} and arrange for disk replacement prior to going on site.\n2- Follow procedure document for replacing GEN${hardware_gen} *Internal* Disk for Atmos ${atmos_ver5}${replace_method}.\n3- Verify correct disk has been replaced by comparing disk serial# shown above, with SN shown on disk."
  issue_description="Failed *internal* disk is ready for replacement"
  
  [[ -a /var/service/fsuuid_SRs/${internal_uuid}.txt  ]]  && { fsuuid_var=${internal_uuid};validate_fsuuid_text_file; }
  [[ -a /var/service/fsuuid_SRs/${internal_serial}.txt  ]]  && { fsuuid_var=${internal_serial};validate_fsuuid_text_file; }
  # psql -U postgres -d rmg.db -h $RMG_MASTER -c "select d.devpath,d.slot,d.status,d.connected,d.slot_replaced,d.uuid,d.replacable from fsdisks fs RIGHT JOIN disks d ON fs.diskuuid=d.uuid where fsuuid='$internal_uuid';" | egrep -v '^$|row'
  # psql -U postgres -d rmg.db -h $RMG_MASTER -tx -c "select * from disks d where d.devpath='${int_dev_path}';"
  
  if [[ ${no_print} -ne 0 ]]; then
  echo -en "\n${lt_green}# Continue printing dispatch template? (y/Y) [Default = y]: ${clear_color}"
  read -t 120 -n 1 display_internal_disk_temp_flag || cleanup "Timeout: No internal disk given." 171
  echo
  [[ ${display_internal_disk_temp_flag} =~ [yY] ]] && display_template_body 
  [[ -z ${display_internal_disk_temp_flag} ]] && display_template_body
  fi
  return 0
}

prep_dae_fan_template() {         # Prepares input for use in display_dae_fan_template function.
  # Check if disk is ready for replacement:
  
  if [ -z "${cooling_fan_num}"  -a "${cooling_fan_num}" != " " ]; then
    enclosure_number=$(cs_hal list enclosures | awk -F"/dev/sg| " '/\/dev\//{print $2}')
    export GREP_COLORS="sl=37:cx=37"
    echo -e "\n\n\n${cyan}# Following KB# 86979"
    printf '%.0s=' {1..80}
    echo -e "\n# If not running script on node with issue, see KB above for instructions.\n${lt_cyan}# Checking all fans: ( 0=A#0 | 1=B#0 | 2=C#0 )${lt_gray}"
    for i in `seq 0 2`; do 
      echo -en "$i: "
      sg_ses /dev/sg${enclosure_number} --index=coo$i 2>/dev/null | egrep "EMC|INVOP|Predicted|Ident" | egrep --color "^|Noncritical|Critical"; done
    echo -e "\n${lt_cyan}# Checking DM log: ( /var/log/maui/dm.log )${lt_gray}"
    tac /var/log/maui/dm.log | grep -m3 "Cooling Fan" | tac | egrep --color "^|Cooling Fan [ABC]#0"
    echo -en "\n${lt_cyan}# If no alerts after first line, probably false alert: ${clear_color}\n"
    ipmi_alerts=$(ipmitool sel elist)
    [[ $(echo ${ipmi_alerts} | wc -l) -gt 1 ]] && echo -en "${red}${ipmi_alerts}" || echo -en "${lt_green}${ipmi_alerts}"
    echo -en "\n\n${lt_cyan}# Checking disk temperature.\n${lt_gray}# Temperature Range of all SS disks: ${clear_color}"
    device_list=$(df -h | awk -F1 '/mauiss/{print $1}')
    for dev in $device_list; do smartctl -l scttempsts $dev | awk '/Current/{print $3}';done | sort | uniq | awk 'ORS="";function red(string) { printf ("%s%s%s%s", "\033[1;31m", string, "\033[0;37m", "C"); }; function green(string) { printf ("%s%s%s%s", "\033[1;32m", string, "\033[0;37m", "C"); };NR==1{n=$1};END { m=$1;if (n < 34){print green(n)" - "} else {print red(n)" - "};{if (m < 37){print green(m)} else {print red(m)}}}' 
    echo -e "\n${lt_gray}# *Note: The temperature of disks will vary based on the model and the activity and location.\n\n${lt_cyan}# Either way, dispatch out to have the CE check the DAE for amber alert.\n${lt_gray}# For other DAE hardware errors, check the following logs: \ngrep DAE /var/log/maui/dm.log /var/log/messages\n\tError detected on DAE %s. Error details: %s.${clear_color}\n\n\n"
    #sleep 6; echo -e "\n\n\n\n";prep_dae_fan_template 1; 
    fi
    echo $cooling_fan_num
  
  rep=0
  until [[ ${cooling_fan_num} =~ [A-Ca-c] ]]; do
    [[ $rep -ge 4 ]] && break 
    [[ $rep -ge 1 ]] && echo -e "${red}# DAE Fan number not recognized. Please try again.${clear_color}"
    echo -en "\n${lt_green}# Enter DAE fan number reported faulty ( A#0, B#0, C#0 ): "
    read -t 300 -n 3 cooling_fan_num; echo -e "\n${clear_color}"
    rep=$rep+1
  done
  [[ "${cooling_fan_num}" =~ [Aa] ]] && cooling_fan_num="A#0" 
  [[ "${cooling_fan_num}" =~ [Bb] ]] && cooling_fan_num="B#0"
  [[ "${cooling_fan_num}" =~ [Cc] ]] && cooling_fan_num="C#0"
 
  [[ "${cooling_fan_num}" =~ [ABCabc]"#0" ]] || cleanup "DAE Fan number not recognized." 131
  set_customer_contact_info
  
  # set cooling fan part number
  case "${hardware_gen}:${atmos_ver3}" in  # hardware_gen:atmos_ver3
    1:*)  	                        # Gen 1 hardware
      part_num='303-173-000B'				  
      fan_description='Front Fan control module'
      ;;		
    2:*)  	                        # Gen 2 Hardware 
      part_num='303-173-000B'
      fan_description='Front Fan control module'
      ;;
    3:*)                            # Gen 3 Hardware
      part_num='303-173-000B'
      fan_description='Front Fan control module'
      ;;
    *) cleanup "Hardware Gen / DAE Fan part number detection failed." 130
      ;;
  esac

  replace_method=" - FRU Replacement Procedure"
  template_dispatch_reason="DAE Fan Replacement"
  template_additional_info="Error details:\tCooling Fan ${cooling_fan_num}\nPart Number:\t${lt_green}${part_num}${lt_gray} - ${fan_description}"
  template_instruction_list="\n1- Contact ${customer_name} and arrange for DAE cooling fan replacement prior to going on site.\n2- Attention: Possible false alert, please verify the DAE fan modules are all showing green and are functioning.\n - Note: Fans are located across the front of the DAE and numbered 0-2, left to right.\n - Note: If all green lights / no further DAE issues seen, then close task and SR.\n - Note: If any fan is showing amber alert, follow procedure document for replacing GEN${hardware_gen} DAE cooling fan for Atmos ${atmos_ver5}.\n3- Select the Gen${hardware_gen} Series FRU component you wish to replace: G${hardware_gen} Series - DAE7S Fan Module\n    a- Remove the failed fan.\n    b- Reseat to see if it returns to green.\n    c- If it stays green - wait 5 minutes and if no change, close out the task and close the SR.\n    d- If it stays amber or changes to amber, then replace fan.\n    e- After replacing the failed fan - verify the DAE amber fault LED transitions to OFF, and the replacement fan has no amber fault LEDs.\nNote: Please add a note to the SR if the fan with the amber alert is different than the fan specified above.\nNote: If you cannot locate the DAE - \"no amber fault light found\" - log onto the node specified above and use the following commands:\n# cs_hal list enclosures\t(Should return /dev/sg2 or /dev/sg3)\n# cs_hal led /dev/sg2 blink\t(Will blink the DAE led)\n# cs_hal led /dev/sg2 off\t(Will turn off the blinking led on the DAE)"
  issue_description="Failed DAE fan check / replace"
  display_template_body 
  [[ $1 ]] && cleanup "" 0
  return 0
}

mark_disk_replaceable(){          # Mark disk as replaceable in rmg database.
  # from KB 000088361 
  # https://emc--c.na5.visual.force.com/apex/KB_BreakFix_1?id=kA1700000000QPP

  # One-liner:
  echo -e "\n"
  [[ -z $fsuuid_var ]] && read -p "## Enter FSUUID: " -t 60 -n 36 fsuuid_var; echo
  psql -U postgres -d rmg.db -h $RMG_MASTER -tqxc "select d.uuid \"Disk Serial\",d.devpath,d.slot,d.connected,d.slot_replaced,d.status \"Disk status\",d.replacable,r.status \"Recovery status\",r.unrecoverobj from fsdisks fs RIGHT JOIN disks d ON fs.diskuuid=d.uuid JOIN recoverytasks r ON fs.fsuuid=r.fsuuid where fs.fsuuid='$fsuuid_var';"
  is_replaceable=$(psql -U postgres -d rmg.db -h $RMG_MASTER -tq -c "select d.replacable from fsdisks fs RIGHT JOIN disks d ON fs.diskuuid=d.uuid where fsuuid='${fsuuid_var}';" | tr -d ' |\n')
  disk_uuid=$(psql -U postgres -d rmg.db -h $RMG_MASTER -tq -c "select d.uuid from fsdisks fs RIGHT JOIN disks d ON fs.diskuuid=d.uuid where fsuuid='${fsuuid_var}';" | tr -d ' |\n') 
  echo -e "\n"
  [[ $is_replaceable -eq 1 ]] && { read -p "${lt_green}# The disk is already set to 'replacable' would you like to proceed with updating recoverytasks status, disk status, and cancel recovery through mauisvcmgr? (y/n) ${clear_color}" -t 60 -n 1 update_replaceable_confirm; echo; } || { read -p "${red}# The disk is not currently set to 'replacable' would you like to update replacable bit? (y/n) ${clear_color}" -t 60 -n 1 update_replaceable_confirm; echo; }
  if [[ "$update_replaceable_confirm" =~ [yY] ]]; then echo -e "\n" ;\
    psql -U postgres -d rmg.db -h $RMG_MASTER -tqxc "select d.uuid,d.replacable from fsdisks fs RIGHT JOIN disks d ON fs.diskuuid=d.uuid where fsuuid='${fsuuid_var}';" ;\
    psql -U postgres -d rmg.db -h $RMG_MASTER -c "UPDATE disks SET replacable=1,status=6 WHERE uuid='${disk_uuid}';" ; echo; \
    mauisvcmgr -s mauicm -c mauicm_cancel_recover_disk -a "host=$HOSTNAME,fsuuid=${fsuuid_var}" -m $HOSTNAME ;\
    psql -U postgres -d rmg.db -h $RMG_MASTER -c "UPDATE recoverytasks SET status=2 WHERE fsuuid='${fsuuid_var}';" ;\
    psql -U postgres -d rmg.db -h $RMG_MASTER -tqxc "select d.uuid \"Disk Serial\",d.devpath,d.slot,d.connected,d.slot_replaced,d.status \"Disk status\",d.replacable,r.status \"Recovery status\",r.unrecoverobj from fsdisks fs RIGHT JOIN disks d ON fs.diskuuid=d.uuid JOIN recoverytasks r ON fs.fsuuid=r.fsuuid where fs.fsuuid='$fsuuid_var';"
    [[ display_test_switch -eq 1 ]] || echo -e "$(date +'%x %X') $problem_node $0 -b Mark disk replaceable: ${fsuuid_var}" >> $log_dispatch
  else 
    echo -e "\n## No updates performed. "
  fi
  return 0
}

spinner_time() {                  # Function that will display a spinner based on time.
i=1
x=0
seconds="$(echo "$1*7.172" | bc | sed 's/[.].*//')"
[[ $1 == 0 ]] && seconds=10
sp="/-\|"
echo -n ' '
while [ $x -le $seconds ]
do
    x=$(( $x + 1 ))
    printf "\b${sp:i++%${#sp}:1}"
sleep .12
[[ $1 == 0 ]] && x=0
done
echo -en "\b \b"
}

spinner_while() {                 # Function that will display a spinner based waiting for function to finish.
spinner_time 0 2>$log_err &
spinner_pid=$!
[[ $display_test_switch -eq 1 ]] && echo "$@"
$@
function_pid=$!
sleep .1
echo "lame" >$log_err
kill $spinner_pid 2&>1 >$log_err
echo -en "\b \b"
return 0
}

show_system_info(){               # Display system information.
  echo -e "\n# `basename $0` version: $version\n"
  maui_ver=$(cat /etc/maui/maui_version)
  atmos_hotfixes=$(awk -F\" '/value=/ {if($2=="hotfixes") if($4=="")printf "None found"; else printf $4}' /etc/maui/nodeconfig.xml)
  echo -e "Site ID: \t${site_id}\t\tTLA:\t${tla_number}"
  echo -e "Hardware:\t${hardware_product} \tGen:\t${hardware_gen}"
  
  echo -e "\n\t\t\t(maui_version file)\t(nodeconfig.xml)\nAtmos Version:\t\t${maui_ver}\t\t${atmos_ver}\nInstalled Hotfixes:\t${atmos_hotfixes}\n"
  dmidecode | grep -i 'system information' -A4 && xdoctor -v | xargs -I{} echo 'xDoctor Version {}' && (ls -l /var/service/AET/workdir || ls -l /var/support/AET/workdir ) 2>/dev/null | awk '{print $11}'&& xdoctor -y | grep 'System Master:' | awk '{print $3,$4,$5}';echo -e "-------\n\n"
}
  
prep_lcc_templates() {            # Prepares lcc templates.
        # # cs_hal list enclosures
        # /dev/sg2     30   < 30 disks = 303-172-002D-001
        # total: 1
  cs_hal --version 1>/dev/null && until [[ -n $enclosure_size ]]; do enclosure_size=$(cs_hal info $(cs_hal list enclosures 2>/dev/null | awk '/\/dev\/sg/{print $1}') 2>/dev/null| awk '/disk slot count/ {print $5}'); done
  mds_layout=$(mauisvcmgr -s mauimds -c getReplicaMode | awk -F= 'NR==1{print $2}')
  
  #Note:	In Atmos versions => 2.1.7.0 the command above will output a “Zoned” value. If this value is “No” the system is a G3 DENSE-480 or G3 FLEX-240.
  #Note:	The cs_hal list enclosures command may not display as shown above if run on the node connected to the defective ICM or LCC. Run commands on an operational node 
  #15 or 30 disks, Zoned=Yes = G3 FLEX-180/360
  #total: 1                    Order 303-171-003D-00 or 303-171-002D-00
  #                          Escalate to Atmos Global Technical Support for assistance. 
  #                                                           DO NOT use this procedure for G3 FLEX-180/360 models.
  # 3. [   ]	. Run the following command.  “test_eses -e 0 -C "eeprom 0 size set 0x2000"” to determine the LCC replacement part number to order. 
  # Example:
  # # test_eses -e 0 -C "eeprom 0 size set 0x2000"
  # unknown_cmd       << 4K LCC Order 303-171-000B
  # #
  # # test_eses -e 0 -C "eeprom 0 size set 0x2000"
  # #                << 8K LCC Order 303-171-002C-00 or 303-171-003C-00
  # 4. [   ]	Once the G3 system model has been validated and the LCC replacement part has been determined and ordered, the LCC replacement engagement can be scheduled. If G3 FLEX-180/360 model escalate to L3 Engineering to schedule assistance.
  # Caveats
  # •	LCC in an Atmos G3 DENSE-480 and G3 FLEX-240 disk-array enclosure (Voyager DAE). 
  # •	Do not remove a faulted LCC until you have the replacement part available.
  # •	The LCCs 303-171-000B and 303-171-00xC-00 are not compatible and cannot be interchanged. See Atmos FRU matrix for details. 
  # •	DO NOT use this procedures to replace a ICM or LCC on G3 FLEX-180/360 without Atmos L3 assistance. 
  # 4. [   ]	Use the following commands to identify the DAE chassis that contains the defective LCC and the node the DAE chassis is configured to.
  # Note:	The LCC failure should set the DAE chassis fault LED by default. Depending on the failure of the LCC, the identify command for the DAE chassis may not function.
  # a.	Use the following command to identify the DAE chassis (blink yellow fault LED).  The SCSI Device “/dev/sdx” for the DAE enclosure with defective LCC 
  # # cs_hal led /dev/sg2 blink
  # cs_hal: setting LED state of enclosure /dev/sg2 from '0' to '1'

  # b.	Use the following command to identify the Location (illuminate Blue ID LED), the DAE chassis is connected to.
     # # cs_hal led node on
     # cs_hal: setting LED state of node to 'ON'
  
  #Add current firmware version: # test_eses -R | grep LCC
  case "${hardware_gen}:${enclosure_size}:${atmos_ver3}" in   						# hardware_gen:atmos_ver3
    1:*)  	                                                              # Gen 1 hardware
      part_num='303-076-000D'				  
      part_description='SAS / SATA LCC'
      ;;		
    2:*)  	                          # Gen 2 Hardware 
      part_num='303-076-000D'				  
      part_description='SAS / SATA LCC'
      ;;	
    3:30:*)                            # Gen 3 Hardware
      part_num='303-171-002C-00'			 # 303-171-002C-00 - VOYAGER 6G SAS LCC ASSY W/ 8K EPROM - G3-FLEX Model ONLY      - Substitution:303-171-003C-00
      part_description='VOYAGER 6G SAS LCC ASSY W/ 8K EPROM'          # note: G3-FLEX is supported on Atmos software release 2.1.4.0 and above, configured with 30 disks in each DAE.
      ;;	
    3:60:*)                            # Gen 3 Hardware
      part_num='303-171-000B'		       # 303-171-000B  – VOYAGER 6G SAS LCC ASSY - G3-DENSE Model ONLY
      part_description='VOYAGER 6G SAS LCC ASSY'
      ;;	
    *) cleanup "Hardware Gen / LCC type detection failed." 130
      ;;
    esac

  set_customer_contact_info
  replace_method=""
  echo -en "\n${lt_green}# LCC Menu: \n  1. LCC Reseat template\n  2. LCC Replacement template\n\n# Please make your selection ( 1 or 2 ): ${clear_color}"
  read -t 120 -n 1 display_lcc_type_flag || cleanup "Timeout: No internal disk given." 171
  echo
  [[ ${display_lcc_type_flag} =~ [12] ]] || cleanup "LCC - Invalid selection." 172
  [[ ${display_lcc_type_flag} -eq 2 ]] && {
    template_dispatch_reason="DAE LCC Replacement"
    template_additional_info="MDS Type:\t${mds_layout}-way\nPart Number:\t${lt_green}${part_num}${lt_gray}\t(${part_description})"
    template_instruction_list="\n1- Contact ${customer_name} and arrange for LCC Replacement prior to going on site.\n2- Follow procedure document for replacing GEN${hardware_gen} DAE LCC (Link Control Card) for Atmos ${atmos_ver5}${replace_method}."
    issue_description="LCC needs replacement"
  }
  [[ ${display_lcc_type_flag} -eq 1 ]] && {
    template_dispatch_reason="DAE LCC Reseat"
    template_additional_info="MDS Type:\t${mds_layout}-way\nPart Number:\tNot required for reseat."
    template_instruction_list="\n1- Contact ${customer_name} and arrange for LCC Reseat prior to going on site.\n2- Follow procedure document for *replacing* GEN${hardware_gen} DAE LCC (Link Control Card) for Atmos ${atmos_ver5} using the existing hardware.\n3- Verify all DAE disks are seen by cs_hal ( cs_hal list disks ) after finishing the procedure.\n4- Requeue to lab after finishing procedure for further work."
    issue_description="LCC needs reseating"
  }
  display_template_body
  return 0
}

prep_power_supply_template() {    # Prepares power supply template.
  case "${hardware_gen}:${atmos_ver3}" in   						# hardware_gen:atmos_ver3
  1:*)  	                          # Gen 1 hardware
    cleanup "Gen 1 not supported yet. Need part info." 170
    part_num=''				  
    part_description=''
    ;;		
  2:*)  	                          # Gen 2 Hardware 
    cleanup "Gen 2 not supported yet. Need part info." 170
    part_num=''				  
    part_description=''
    ;;	
  3:*)                            # Gen 3 Hardware
    part_num='105-000-243-01'				  
    part_description='INTEL 1200W POWER SUPPLY ROMELY'
    ;;	
  *) cleanup "Hardware Gen / Power Supply type detection failed." 170
    ;;
  esac

  echo -en "\n${lt_green}# Hardware - Power Supply options: \n  1. Troubleshoot\n  2. Power Supply Replacement template\n\n# Please make your selection ( 1 or 2 ): ${clear_color}"
  read -t 120 -n 1 display_power_supply_type_flag || cleanup "Timeout: No selection made." 171
  [[ ${display_power_supply_type_flag} =~ [12] ]] || cleanup "Power Supply - Invalid selection." 172
  [[ ${display_power_supply_type_flag} -eq 1 ]] && {
    ## Power Supply Replacement -- KB 87316 -- Symptom Code 51013
    # https://emc--c.na5.visual.force.com/apex/KB_BreakFix_1?id=kA1700000000Q8Y
    # Ref: BZ 34320
    echo -e "\n\n\n${cyan}# Following KB# 86979${clear_color}";printf '%.0s=' {1..80}
    echo -e "\n\n${cyan}# If not running script on node with issue, see KB above for instructions.\n${clear_color}"
    echo -e "\n\n${cyan}# bzgrep SENSOR_ /var/log/messages*${clear_color}";bzgrep SENSOR_ /var/log/messages*
    echo -e "\n\n${cyan}# cs_hal sensors power${clear_color}";cs_hal sensors power
    echo -e "\n\n${cyan}# cs_hal sensors psu${clear_color}";cs_hal sensors psu
    display_power_supply_type_flag=2
    }
  [[ ${display_power_supply_type_flag} -eq 2 ]] && display_power_supply_type="display_template_body"
  
  display_power_supply_temp_flag="y"
  echo -en "\n${lt_green}# Continue printing dispatch template for Power Supply? (y/Y) [Default = y]: ${clear_color}"
  read -t 120 -n 1 display_power_supply_temp_flag || cleanup "Timeout: No selection made." 173
  echo
  [[ ${display_power_supply_temp_flag} =~ [yY] ]] && { echo -en "\n${lt_green}# Select which power supply showed faulty? (1/2): ${clear_color}";read -t 220 -n 1 power_supply_num || cleanup "Timeout: No selection made." 174;echo;
  set_customer_contact_info
  template_dispatch_reason="Chassis Power Supply (PS) Replacement"
  template_additional_info="Part Number:\t${lt_green}${part_num}${lt_gray}\t(${part_description})\nPower Supply #:\tUnit ${power_supply_num} (PS${power_supply_num})\n"
  template_instruction_list="1- Contact ROCC and arrange for checking PS for the above node and probable PS replacement.\n2- Sensors for PS${power_supply_num} for ${HOSTNAME} have alerted - please physically locate the node.\n3- Open Atmos G${hardware_gen} rear cabinet door; locate any illuminated solid/blinking amber LEDs for the PS.\n4- If solid amber, confirm AC input is operational and cords are fully seated.\n5- If defective chassis power supply is determined, follow procgen for Gen ${hardware_gen} Node Chassis Power Supply${replace_method}.\n*Note: An Amber solid LED can denote AC input loss or power supply critical event.\n*Note: PS can display flashing green LED which signifies less than 4 nodes powered on in the chassis.\n\t# PS will be in a cold redundant state, this is normal operation."
  replace_method=""
  issue_description="Chassis Power Supply needs replacement"
  $display_power_supply_type; } || { [[ ${display_power_supply_temp_flag} =~ [nN] ]] || cleanup "Invalid selection." 175; }
  return 0 
}

verify_host() {
echo -en "# Verifying entered hostname is on the system...";
awk '{print $2}' /etc/hosts|egrep -q "$1" && echo -e "${lt_green} Passed.${clear_color}" || { echo -e "${red} Failed.${clear_color}";cleanup "Please try again with a proper hostname for this system." 9;  }
host_is=$(echo $HOSTNAME|sed 's/...$//'); problem_host_is=$(echo $1|sed 's/...$//')
echo -en "# Verifying problematic node is in the same Installation Segment..."
[[ $host_is == $problem_host_is ]] && echo -e "${lt_green} Passed.${clear_color}" || { echo -e "${red} Failed.${clear_color}";cleanup "Please try again from a node in the same installation segment." 9;  }
}

prep_node_template() {            # Prepares node template.
    node_replace_type_selection=0;[[ -z "${1}" ]] && node_replace_type_selection=$1
    [[ $node_replace_type_selection -eq 0 ]] && {
    case "${hardware_gen}:${atmos_ver3}" in   						            # hardware_gen:atmos_ver3
    1:*)  	                                                          # Gen 1 hardware
      cleanup "Gen 1 not supported yet. Need part info." 176
      part_num=''				  
      part_description=''
      ;;		
    2:*)  	                                                          # Gen 2 Hardware 
      cleanup "Gen 2 not supported yet. Need part info." 176
      part_num=''				  
      part_description=''
      ;;	
    3:*)                                                              # Gen 3 Hardware
      part_num='105-000-260'				  
      part_description='INA ATMOS G3 DENSE BLADE'
      ;;	
    *) cleanup "Hardware Gen / Node type detection failed." 177
      ;;
    esac
    
    read -p "${lt_green}# Enter node with issue (Leave blank to use current host): " -t 60 problem_node; echo -e " ${clear_color}"
    [[ -z "$problem_node" ]] && problem_node="$HOSTNAME"
    [[ "$problem_node" == $HOSTNAME ]] || spinner_while verify_host $problem_node

    spinner_while set_customer_contact_info
    hotfixes_needed=$(awk -F\" '/value=/ {if($2=="hotfixes") if($4=="")printf "None found"; else printf $4}' /etc/maui/nodeconfig.xml)
    template_dispatch_reason="Node Replacement"
    template_additional_info="Part Number:\t${lt_green}${part_num}${lt_gray}\t(${part_description})\nAtmos Ver:\t${atmos_ver}\n"
    template_instruction_list="1. Contact ROCC and arrange for node replacement prior to going on site.\n2. Check node:\n	a- Connect KVM to node, then power off node - wait 1 minute, then power on node. \n	b- See if the node will boot up - watch for hardware errors on boot.\n	c- If power on is successful and you can log in, \n	  i) capture node hardware serial number - \n			# dmidecode | grep -i 'system information' -A4\n	  ii) check node health.  See Article Number:175566 \n			Search the logs in /var/log/hardware/sel*.log  to get node hardware events\n	  iii) Determine if node needs to be replaced.\n			If node does not stay up long enough to follow steps in Article 175566 - then go to step 3.\n	d- If power on fails, continue to step 3.\n3. Follow procedure document for replacing GEN${hardware_gen} Node for Atmos ${atmos_ver5} - FRU Replacement Procedure.\n   **Contact ROCC before applying hotfixes, as this will bring the node to Opertional Mode**\n   HotFixes Needed: ${hotfixes_needed}"
    replace_method=""
    issue_description="Failed node ready for replacement"
    }
    echo -en "\n${lt_green}# Hardware - Node Options: \n  1. Troubleshoot\n  2. Node Replacement template (Normal procedure)\n  3. Node Replacement template (Special FA Procedure for HF415 - Section A&C [First 2 nodes].)\n  4. Node Replacement template (Special FA Procedure for HF415 - Section B&C.)\n\n# Please make your selection ( 1 - 4 ): ${clear_color}"
    read -t 120 -n 1 node_replace_type_selection || cleanup "Timeout: No selection made." 178
    case "${node_replace_type_selection}" in 
    1)echo -e "\n\n\n${cyan}# Following KB# ...${clear_color}";printf '%.0s=' {1..80}
      echo -e "\n\n${cyan}# If not running script on node with issue, see KB above for instructions.\n${clear_color}"
      echo -e "\n\n${cyan}# cat /var/log/warn${clear_color}";cat /var/log/warn
      echo -e "\n\n${cyan}# cs_hal sel elist power${clear_color}";cs_hal sel elist
      echo -e "\n\n${cyan}# cs_hal sdr elist${clear_color}";cs_hal sdr elist
      prep_node_template 1 && cleanup "" 0
    ;;
    2)
    ;;
    3)template_dispatch_reason="Node Replacement and Internal disk *SPECIAL FA*"
      template_additional_info="Part Number:\t${lt_green}${part_num}${lt_gray}\t(${part_description})\nInt. Disk:\t${lt_green}105-000-316-00${lt_gray}\t(300GB 2.5\" 10K RPM SAS 512bps DDA ATMOS)\nAtmos Ver:\t${atmos_ver}\n"
      template_var_line1="(NON STANDARD PROCEDURE)"
      template_instruction_list="1. Contact ROCC and arrange for node replacement prior to going on site.\n2. Check node:\n	a- Connect KVM to node, then power off node - wait 1 minute, then power on node. \n	b- See if the node will boot up - watch for hardware errors on boot.\n	c- If power on is successful and you can log in, \n	  i) capture node hardware serial number - \n			# dmidecode | grep -i 'system information' -A4\n	  ii) check node health.  See Article Number:175566 \n			Search the logs in /var/log/hardware/sel*.log  to get node hardware events\n	  iii) Determine if node needs to be replaced.\n			If node does not stay up long enough to follow steps in Article 175566 - then go to step 3.\n	d- If power on fails, continue to step 3.\n3. Follow the standard node replacement procedure (GEN3 Atmos 2.2.0) up to physically installing the new node (DO NOT INSTALL THE NEW NODE YET)\n4. Remove the internal server drive (PN 105-000-316-xx) in HDD SLOT 1 of the failed node (contact CS via ROCC if further help is needed)\n5. Return the drive with the node - PRIORITY FA - instructions listed below***.\n6. Replace with a new drive (PN: 105-000-316-xx)\n7. Continue the node replacement from where you left off in step 3\n   **Contact ROCC before applying hotfixes, as this will bring the node to Opertional Mode**\n   HotFixes Needed: ${hotfixes_needed}"
      template_footer="\n***Send ALL failed material PRIORITY FA to engineering at the address below:\nAtt: Christian Bellefontaine \nEMC²\n145 Broadway\nCambridge, MA 02142\nUSA"
      ;;
    4)template_dispatch_reason="Node Replacement *SPECIAL FA*"
      template_footer="\n***Send ALL failed material PRIORITY FA to engineering at the address below:\nAtt: Christian Bellefontaine \nEMC²\n145 Broadway\nCambridge, MA 02142\nUSA"
    ;;
    *)cleanup "Node Menu - Invalid selection." 178
    ;;
    esac 
    node_replace_verify_flag="y"
    echo -en "\n${lt_green}# Continue printing dispatch template for Node Replacement? (y/Y) [Default = y]: ${clear_color}"
    read -t 120 -n 1 node_replace_verify_flag || cleanup "Timeout: No selection made." 179
    echo
    display_template_body
  [[ $called_option -gt 0 ]] && cleanup "---" 0 || return 0 
}

###########################################   Start main code..  ###########################################
############################################################################################################
main() {    ################################################################################################
init_colors
get_hardware_gen

## Trap keyboard interrupt (control-c)
trap control_c SIGINT

## Testing switch warning
[[ $display_test_switch -eq 1 ]] && echo "${red}# Testing option: ON (run script with -z option to turn off)${clear_color}"

## If more than 2 options
## Check if correct number of options were specified.
[[ $# -lt 1 || $# -gt 3 ]] && echo -e "\n${red}Invalid number of options, see usage:${clear_color}" && display_usage

## Check if option is blank.
# [[ $1 ]] && echo -e "\n${red}Invalid option, see usage:${clear_color}" && display_usage
[[ $1 == "-\$" || $1 == "?" ]] && echo -e "\n${red}Invalid option, see usage:${clear_color}" && display_usage

## Check for invalid options:
if ( ! getopts ":bcdefhiklmnoprsuvVwxyz" options ); then echo -e "\n${red}Invalid options, see usage:${clear_color}" && display_usage; fi

## Parse the options:
while getopts ":bcdefhiklmnoprsuvVwxyz" options
do
    case $options in
    b)  fsuuid_var="$2"
        mark_disk_replaceable
        ;;
    c)  cleanup "Not supported yet, will print switch/eth0 connectivity dispatch template." 99
        ;;
    d)  fsuuid_var="$2"
        validate_fsuuid 
        prepare_disk_template
        append_dispatch_date
        ;;
    e)  fsuuid_var="$2"
        validate_fsuuid 
        prepare_disk_template
        update_sr_num
        append_dispatch_date
        ;;
    f)  cooling_fan_num="$2"
        prep_dae_fan_template
        ;;
    h)  display_usage
        ;;
    i)  internal_disk_dev_path="$2"
        [[ "$3" == '' ]] && no_print='1' || no_print="$3"
        prep_int_disk_template
        ;;
    k)  get_fsuuid
        prepare_disk_template
        ;;
    l)  prep_lcc_templates
        ;;			
    m)  cleanup "Not supported yet, will print DAE power cycle template." 99
        ;;
    n)	prep_node_template
        ;;
    o)	cleanup "Not supported yet, will print node reboot/power on template." 99
        ;;
    p)	prep_power_supply_template
        ;;
    r)	cleanup "Not supported yet, will print reseat disk template." 99
        ;;
    s)	update_sr_num
        ;;
    u)	update_sr_num
        ;;
    v)	echo -e "# `basename $0` version: $version\n"
        exit 0
        ;;
    V)  show_system_info
        ;;
    w)	cleanup "Not supported yet, will print private switch replacement template." 99
        ;;
    x)  list_location="$2"
        distribute_script
        ;;
    y)  update_script
        distribute_script
        ;;
    z)  dts_line_number=$(grep -n -m1 display_test_switch /usr/local/bin/dispatch_template.sh |awk -F: '{print $1}')
        [[ "${display_test_switch}" -eq 1 ]] && { sed -i "${dts_line_number}s/  display_test_switch=1/  display_test_switch=0/" ${full_path} && echo -e "# Testing: OFF."; } || { sed -i "${dts_line_number}s/  display_test_switch=0/  display_test_switch=1/" ${full_path} && echo -e "# Testing: ON."; }
        ;;
    :)  # Multiple options..
        #echo "testing.. mult options."
        fsuuid_var="$2"
        [[ "$OPTARG" =~ [de] ]] && validate_fsuuid
        [[ "$OPTARG" =~ [de] ]] && prepare_disk_template
        [[ "$OPTARG" == "e" ]] && update_sr_num
        [[ ! "$OPTARG" =~ [de] ]] && display_usage
        ;;
    \?) echo -e "# Invalid option: -$OPTARG" >&2
        display_usage
        ;;
    *)  echo -e "# Invalid option: -$OPTARG" >&2
        display_usage
        ;;
    esac
done

##Exit successfully if script reaches this point.
cleanup "---" 0
}

# Call main function.
[[ $display_test_switch -eq 1 ]] && main "$@" |tee -a $log_out || main "$@" 2>$log_err | tee -a $log_out

# TODO
# fsuuid valid on current node.                                             - done
# customer contact info to text file?                                       - done
# move dispatched date to .info file in show_offline_disks versions 1.6.0+  - done
# complete other dispatch templates.                                        - 2/7
    # # `basename $0` -c		# Switch/eth0 connectivity template.            - pending
    # # `basename $0` -l		# LCC replacement template.                     - done
    # # `basename $0` -n		# Node replacement template.                    - wip
    # # `basename $0` -o		# Reboot / Power On dispatch template.          - pending
    # # `basename $0` -p		# Power Supply replacement template.            - done      
    # # `basename $0` -r		# Reseat disk dispatch template.                - pending
    # # `basename $0` -w		# Private Switch replacement template.          - pending
# BZ standardized templates.                                                - pending
# Automate dispatch through Service Center with script option.

###########################################       Testing..       ##########################################
############################################################################################################
############################################################################################################
# Testing: 
# Gen1: dfw01-is01-003
# Gen2: iad01-is05-006
# Gen3: lis1d01-is5-001
# amst a,  rwc a, tkyo a, tyo1/syd1
# script_loc="/usr/local/bin";time for x in `cat /var/service/list`; do echo -n "$x  -  ";ssh $x 'echo "$HOSTNAME"' && { echo -n "# Copying script: ";scp $script_loc/dispatch_template.sh $x:$script_loc/ ; [[ -e /usr/local/bin/customer_site_info ]] && scp /usr/local/bin/customer_site_info $x:/usr/local/bin/;ssh $x "sh $script_loc/dispatch_template.sh -x"; };done

# Version tracking
# 1.3.7.0 - Started tracking major version changes.
# 1.4.0.0 - Added Power Supply Replacement option.
# 1.4.1.0 - Code efficiency revision - common template body function.
# 1.4.2.0 - Added Node replacement option.
# 1.4.3.0 - Added stdout/stderr logs.
# 1.4.4.0 - Added historical logging for dispatches and utilities.