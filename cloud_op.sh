#!/bin/bash
# Created by Kollin Prince (kollin.prince@emc.com
########
# Tool Create to help copy files in /var/service of all beatle nodes
########
Version=1.0.4
trap control_c SIGINT
control_c() {
  echo -e "Control_c detected.... Ending Connections"
  sudo pkill vpnc
  rm -f tmp.cmd
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
Usage() {
  echo "
This tool will copy a file in /var/service of all beatle nodes or run a command on the master nodes of each cloud. 

                                                Usage:
./cloud.op.sh -a (Copies a file from -f option to /var/service in all beatle nodes)
                        -x (command to run)
                        -f (The file to be copied)
                        -v (Shows the current version.)
Example:

./cloud.op.sh -f show_offline_disks.sh -a
The above will copy show_offline_disks to /var/service in all beatle nodes.

./cloud.op.sh -x uptime -a
The above will run uptime on all the master nodes. If you have a command longer than one word please put them in double quotes
"
  exit
}
all_clouds() {
  special=0
  sudo pkill vpnc
  echo -e $cyan"Connecting to Phase 2 West Clouds"$white; sudo vpnc beatle-rdcy01.conf > /dev/null; list=$(cat West_list);eval "${action}"
  sudo pkill vpnc
  echo -e $cyan"Connecting to EMEA Clouds"$white; sudo vpnc beatle-amst01.conf > /dev/null; list=$(cat Amst_list);eval "${action}"
  sudo pkill vpnc
  echo -e $cyan"Connecting to Phase 2 APJK Clouds"$white;sudo vpnc beatle-hnkg01.conf > /dev/null; list=$(cat tkyo_list); eval "${action}"
  sudo pkill vpnc
  echo -e $cyan"Connecting to Phase 1 APJK Cloud"$white; sudo vpnc beatle-syd1.conf > /dev/null; list=$(cat syd_tyo); eval "${action}"
  sudo pkill vpnc
  special=1
  echo -e $cyan"Connection to Phase 1 AMER Clouds"$white; sudo vpnc beatle-rwc1.conf > /dev/null; list=$(cat Phase_1); eval "${action}"
  sudo pkill vpnc
}
cloudselect ()
{
echo "Select the site:"
select site in DFW RWC LIS SEC SYD TYO ALLN RDCY SNDG STLS LOND AMST HNKG TKYO;do break; done

case $site in
	DFW) ip=172.16.; one=22.11; cnum=3; cloudletNODESiP1; eval "${action}" ;;
	RWC) ip=172.17.; one=22.11; cnum=3; cloudletNODESiP1; eval "${action}" ;;
	LIS) ip=172.18.; one=22.11; cnum=3; cloudletNODESiP1; eval "${action}" ;;
	SEC) ip=172.19.; one=22.11; cnum=3; cloudletNODESiP1; eval "${action}" ;;
	SYD) ip=172.30.; one=22.11; eval "${action}" ;;
	TYO) ip=172.31.; one=22.11; eval "${action}" ;;
	ALLN) ip=172.20.; cnum=19; cloudletNODESiP22; eval "${action}" ;;
	RDCY) ip=172.20.; cnum=19; cloudletNODESiP21; eval "${action}" ;;
	SNDG) ip=172.21.; cnum=19; cloudletNODESiP21; eval "${action}" ;;
	STLS) ip=172.21.; cnum=19; cloudletNODESiP22; eval "${action}" ;;
	LOND) ip=172.22.; cnum=9; cloudletNODESiP21; eval "${action}" ;;
	AMST) ip=172.22.; cnum=9; cloudletNODESiP22; eval "${action}" ;;
	HNKG) ip=172.23.; cnum=6; cloudletNODESiP22; eval "${action}" ;;
	TKYO) ip=172.23.; cnum=6; cloudletNODESiP21; eval "${action}" ;;
#	DFWgc) ;;
#	IADgc) ;;
#	DFWcs) ;;
#	IADcs) ;;
	*) echo Invalid selection; exit 1
esac
}
IPs () {
case $1 in
	DFW) ip=172.16.; one=22.11; cnum=3; cloudletNODESiP1 ;;
	RWC) ip=172.17.; one=22.11; cnum=3; cloudletNODESiP1 ;;
	LIS) ip=172.18.; one=22.11; cnum=3; cloudletNODESiP1 ;;
	SEC) ip=172.19.; one=22.11; cnum=3; cloudletNODESiP1 ;;
	SYD) ip=172.30.; one=22.11 ;;
	TYO) ip=172.31.; one=22.11 ;;
	ALLN) ip=172.20.; cnum=19; cloudletNODESiP22 ;;
	RDCY) ip=172.20.; cnum=19; cloudletNODESiP21 ;;
	SNDG) ip=172.21.; cnum=19; cloudletNODESiP21 ;;
	STLS) ip=172.21.; cnum=19; cloudletNODESiP22 ;;
	LOND) ip=172.22.; cnum=9; cloudletNODESiP21 ;;
	AMST) ip=172.22.; cnum=9; cloudletNODESiP22 ;;
	HNKG) ip=172.23.; cnum=6; cloudletNODESiP22 ;;
	TKYO) ip=172.23.; cnum=6; cloudletNODESiP21 ;;
#	DFWgc) ;;
#	IADgc) ;;
#	DFWcs) ;;
#	IADcs) ;;
	*) echo Invalid selection; exit 1
esac
}
cloudletNODESiP1 ()
{
a=30.11; b=30.75; c=30.139; d=30.203
}

cloudletNODESiP21 ()
{
a=16.11; b=16.75; c=16.139; d=16.203; e=17.11; f=17.75; g=17.139; h=17.203; i=18.11; j=18.75; k=18.139; l=18.203; m=19.11; n=19.75; o=19.139; p=19.203; q=20.11; r=20.75; s=20.139; t=20.203
}

cloudletNODESiP22 ()
{
a=48.11; b=48.75; c=48.139; d=48.203; e=49.11; f=49.75; g=49.139; h=49.203; i=50.11; j=50.75; k=50.139; l=50.203; m=51.11; n=51.75; o=51.139; p=51.203; q=52.11; r=52.75; s=52.139; t=52.203
}

update() {
case "$special" in
  0)  hosts_done=0
      for host in $(echo $list); do
        sshpass -p 'C0untingstars' scp $file root@$host:/var/service
        sshpass -p 'C0untingstars' ssh -o StrictHostKeyChecking=no root@$host mauiscp /var/service/$file /var/service/
        hosts_done=$(($hosts_done+1)); echo -ne "Hosts finished: "${green}${hosts_done}${white}    "Total hosts: $orange"$(echo $list |wc -w)'\r'$white
      done
      echo -ne '\n';;
  1)  hosts_done=0; sshpass -p 'C0untingstars' scp $file root@172.19.22.11:/var/service
      for host in $(echo $list); do
        sshpass -p 'C0untingstars' ssh -o StrictHostKeyChecking=no -t -t -R 8080:127.0.0.1:80 root@172.17.22.11 scp /var/service/$file root@$host:/var/service 2>/dev/null
        sshpass -p 'C0untingstars' ssh -o StrictHostKeyChecking=no -t -t -R 8080:127.0.0.1:80 root@172.17.22.11 ssh $host mauiscp /var/service/$file /var/service/ 2>/dev/null
        hosts_done=$(($hosts_done+1)); echo -ne "Hosts finished: "${green}${hosts_done}${white}    "Total hosts: $orange"$(echo $list |wc -w)'\r'$white
      done
      echo -ne '\n';;
esac
}
run_cmd() {
case "$special" in
  0)  hosts_done=0
      for host in $(echo $list); do
        sshpass -p 'C0untingstars' ssh -o StrictHostKeyChecking=no root@$host $cmd > tmp.cmd
        echo -ne "                                        "'\r'; cat tmp.cmd
        hosts_done=$(($hosts_done+1)); echo -ne "Hosts finished: "${green}${hosts_done}${white}     "Total hosts: $orange"$(echo $list |wc -w)'\r'$white
      done
      echo -ne '\n';;
  1)  hosts_done=0
      sshpass -p 'C0untingstars' ssh -o StrictHostKeyChecking=no -t -t -R 8080:127.0.0.1:80 root@172.17.22.11 $cmd 2>/dev/null
      for host in $(echo $list); do
        sshpass -p 'C0untingstars' ssh -o StrictHostKeyChecking=no -t -t -R 8080:127.0.0.1:80 root@172.17.22.11 ssh $host $cmd  2>/dev/null > tmp.cmd
        echo -ne "                                        "'\r'; cat tmp.cmd
        hosts_done=$(($hosts_done+1)); echo -ne "Hosts finished: "${green}${hosts_done}${white}    "Total hosts: $orange"$(echo $list |wc -w)'\r'$white
        echo
      done
      echo -ne '\n';;
esac
}
while getopts "f:x:ahvs" options; do
  case $options in
    f)  file=$OPTARG
        action='update'
        ;;
    v)	echo $version; exit
        ;;
    x)  cmd="${OPTARG}"
        action='run_cmd'
        ;;
    s)  echo "In development, planned release in the next major release "#cloudselect
        ;;
    a)  all_clouds
        ;;
    h)	Usage
        ;;
    *)  Usage
        ;;
  esac
done
