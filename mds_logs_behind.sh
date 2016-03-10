#!/bin/bash
##################### from the CS-ROCC scripting committee #########################
##### Created to help find logs behind on the local host while waiting for an MDS to initialize ##########
#########################################################################
version=1.0.0
black='\E[30m' #display colour when outputting information
red='\E[1;31m'
green='\E[0;32m'
yellow='\E[33m'
blue='\E[1;34m'
magenta='\E[35m'
cyan='\E[36m'
white='\E[1;37m'
orange='\E[0;33m'
blink='\E[5m'  # Only works on konsole and xterm
normal='\E[0m'
usage(){
echo "    
    This is a script that checks the log difference between MDS's in a set
    This is useful for monitoring an MDS that is running but not initialized due to log differences.
                Usage mds_logs_behind [options] <port(s)>
  Options:
    -a  =  Checks the log differences for all MDS's on the node/
    -u  =  Only checks the log differences for uninitialized MDS's. (This is a quicker method)
    -p  =  Checks one or more specified ports
                 Note: to use the -p option you must also specify ports proceeding the -p
                     i.e. mds_logs_behind -p 10401,10402 or mds_logs_behind -p \"10401 10402\""
exit
}
gather_remote_logs(){
[[ -d /var/tmp/logsbehind ]] || { mkdir /var/tmp/logsbehind; }
rmgmaster=$(grep localDb /etc/maui/cm_cfg.xml|cut -d ',' -f2)
mauimdlsutil -q -m  '*' -n $rmgmaster > /var/tmp/logsbehind/mdls
for port in $allmds;do
  remotehosts+=$(grep -B 3 $HOSTNAME:$port /var/tmp/logsbehind/mdls | awk -F " |:" '/Master/ {print$5" "}')
  current_host=$(echo $remotehosts|awk '{print $NF}')
  echo $(grep -B 3 $HOSTNAME:$port /var/tmp/logsbehind/mdls | awk -F " |:" '/Master/ {print$6" "}') >> /var/tmp/logsbehind/$current_host
done
for host in $(echo $remotehosts | awk '{for (i = 1; i <= NF; i++) print$i}' | sort -u); do
  mds_num=$(cat /var/tmp/logsbehind/$host)
  ssh $host 'for i in '$mds_num'; do echo $i $(ls -tr $(mdsdir $i) 2> /dev/null | grep log | tail -1); done' > /var/tmp/logsbehind/$host
done
}
trap control_c SIGINT
control_c() { # Runs the if user hits control-c
 cleanup
 echo "Clean up done";exit 
}
cleanup(){
clean_files=$(ls /var/tmp/logsbehind/ | grep -e [a-z])
for file in $clean_files;do 
  rm -rf /var/tmp/logsbehind/$file
done
}
compare_logs(){
for port in $allmds; do
  echo -ne " Checking port $port" '\r'
  masterport=$(grep -B 3 $HOSTNAME:$port /var/tmp/logsbehind/mdls |awk -F: '/Master/ {print $3}')
  masterhost=$(grep -B 3 $HOSTNAME:$port /var/tmp/logsbehind/mdls | awk -F " |:" '/Master/ {print$5}')
  localhlsn=$(ls -tr $(mdsdir $port) 2> /dev/null | grep log | tail -1 |awk -F '.' '{print$2}')
  [[ -z $localhlsn ]] && localhlsn="Not_Found"
  masterhlsn=$(grep $masterport /var/tmp/logsbehind/$masterhost | awk -F '.' '{print$NF}')
  [[ -z $masterhlsn ]] && masterhlsn="Not_Found"
  if [[ ${masterhlsn} == Not_Found ]] || [[ ${localhlsn} == Not_Found ]]; then
    logsbehind="404_hes-dead-jim"
    logchange="x-x"
    eta="not_a_chance"
  else logsbehind=$((10#$masterhlsn-10#$localhlsn))
  fi
  if [[ $logsbehind -ne 0 ]] || [[ $logsbehind = "404_hes-dead-jim" ]]; then
    if [[ -a /var/tmp/logsbehind/$port ]]; then
      previouslogcount=$(awk '{print$NF}' /var/tmp/logsbehind/$port)
      diffmin=$(echo "($(date +%s) - $(awk '{print$1}' /var/tmp/logsbehind/$port))/ 60" |bc -l)
      logchange=$(echo "$previouslogcount - $logsbehind" | bc)
      if [[ $logchange -eq 0 ]]; then 
        eta=$(echo -e ${red}INFINITY\!\!\!${normal})
        logchange=$(echo -e ${yellow}${logchange}${normal})
      else minutesperlog=$(echo "scale=2; $diffmin / $logchange" | bc -l)
        eta=$(echo "$logsbehind * $minutesperlog" | bc)
      fi
    else logchange="First_run"
    eta="NA"
    echo $(date +%s) $logsbehind > /var/tmp/logsbehind/$port
   fi
   [[ $(echo $logchange|sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g") -lt 0 ]] && { logchange=$(echo -e ${red}${logchange}${normal}); } || { logchange=$(echo -e ${green}${logchange}${normal}); }
   printf "Port  : %-6s Master Host-Port: %17s:%-7s Master Log HLSN: %-11s\nChange: %-6s LogsBehind: %-6s ETA Minutes: %-6s Local Log HLSN: %-11s\n" $(echo $port $masterhost $masterport $masterhlsn $logchange $logsbehind $eta $localhlsn)
  else initmds+=" $port"
  fi
done
[[ ! -z $initmds ]] && echo -e $green"The following MDSS are fully initialized: \n${normal}${initmds[@]}"
}
while getopts "aup:hv" options;do
  case $options in
    a) allmds=$(chkconfig | awk -F "_| " '/mauimds_|mauimdsremt_/ {print$2}')
    ;;
    u) allmds=$(mauisvcmgr -s mauimds -c mauimds_isNodeInitialized | grep -v true | awk -F ':' '{print$2}')
       [[ -z $allmds ]] && { echo -e $green"All MDSs are initialized"$normal; }
    ;;
    p) allmds=$(echo $OPTARG | tr "," " ")
    ;;
    h) usage
    ;;
    v) echo $version
    exit
    ;;
    c) echo "not yet completed"
    usage
    ;;
    *) echo "invalid option"
    usage
    ;;
  esac
done
[[ -z $1 ]] && { allmds=$(chkconfig | awk -F "_| " '/mauimds_|mauimdsremt_/ {print$2}'); } 
gather_remote_logs
compare_logs
cleanup