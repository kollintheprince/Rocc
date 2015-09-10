#!/bin/bash
# Created by Kollin Prince
# This script will either start a recovery with -s or pause a recovery with -p

version=1.0.1

function helpinfo
{
	echo "
This script will either start a recovery with -s or pause a recovery with -p
	"
	echo "Usage: ./recoverdisk.sh -s (prompts for information to start a disk recovery
Usage: ./recoverdisk.sh -p (prompts for information to pause a disk recovery
Usage: ./recoverdisk.sh -v (Shows the current version.)"
	echo ""
}

if [ $# != 1 ];
	then
	echo "No option given, see below for help
	"
	helpinfo
	exit
fi

if [ "$1" == "-h" ];
	then
	helpinfo
	exit
fi

function val
{
	if [ `echo $fsuuid | awk '{print length}'` == "36" ];
		then
		echo -e "fsuuid" "validation"'\E[32m' "Passed"'\E[37m'
	else
		echo "The input is not a valid fsuuid, it needs to be 36 characters"
		exit
	fi	
}

function ifdiskcheck
{
	# Check if there is another disk recovery in progress
	rmgmaster=`grep localDb /etc/maui/cm_cfg.xml|cut -d ',' -f2`
	status=`psql -U postgres rmg.db -h $rmgmaster -c 'select status from recoverytasks' | grep -v status | grep -v rows | grep -v '-'|grep -v "^$"|awk -F ' ' '{print $1}'`
	rfsuuid=`psql -U postgres rmg.db -h $rmgmaster -c 'select fsuuid from recoverytasks where status='3'' | grep -v fsuuid | grep -v rows | grep -v "^$" | grep -v '(' | awk -F ' ' '{print $1}' |tail -1`
	for x in $status;
		do
		if [ $x -eq 3 ];
			then 
			echo -e "`date`: There is still a disk recovery in progress. 
Please wait till disk" '\E[31m'$rfsuuid '\E[37m'"is finished"
			exit
		fi
	done
}

if [ "$1" == "-p" ];
	then
	echo "This option is to pause a disk recovery"
	read -p "Enter fsuuid: " fsuuid
	val
	read -p "Enter host: " host
	echo ""
	ssh $host mauisvcmgr -s mauicm -c  mauicm_cancel_recover_disk -a "fsuuid=$fsuuid,host=$host"
	echo "`date`: fsuuid" $fsuuid" has been paused"
fi	

if [ "$1" == "-s" ];
	then
	ifdiskcheck
	echo "This option is to start a disk recovery"
	read -p "Enter fsuuid: " fsuuid
	val
	read -p "Enter host: " host
	echo ""
	ssh $host mauisvcmgr -s mauicm -c  mauicm_recover_disk -a "fsuuid=$fsuuid,host=$host"
	echo "fsuuid" $fsuuid "has been resubmitted to recover again"
fi

if [ "$1" == "-v" ];
then 
echo $version
exit
fi
