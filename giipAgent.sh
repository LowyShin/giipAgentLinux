#!/bin/bash
# giipAgent Ver. 1.4
# Written by Lowy Shin at 20140922
# Supported OS : MacOS, CentOS, Ubuntu, Some Linux
# 190611 Lowy, Change agent download method to git repository.

# Usable giip variables =========
# {{today}} : Replace today to "YYYYMMDD"

# User Variables ===============================================
. ./giipAgent.cnf

# Self Check
cntgiip=`ps aux | grep giipAgent.sh | grep -v grep | wc -l`

# Check dos2unix
CHECK_Converter=`which dos2unix`
RESULT=`echo $?`

#OS Check
# Check MacOS
uname=`uname -a | awk '{print $1}'`
if [ $uname = "Darwin" ];then
	osname=`sw_vers -productName`
	osver=`sw_vers -productVersion`
	os="${osname} ${osver}"
	os=`echo "$os" | sed -e "s/ /%20/g"`
	if [ ${RESULT} != 0 ];then
		brew install dos2unix
	fi
else
	ostype=`head -n 1 /etc/issue | awk '{print $1}'`
	if [ $ostype = "Ubuntu" ];then
		os=`lsb_release -d`
		os=`echo "$os"| sed -e "s/Description\://g"`

		if [ ${RESULT} != 0 ];then
			apt-get install -y dos2unix
		fi
	else
		os=`cat /etc/redhat-release`

		if [ ${RESULT} != 0 ];then
			yum install -y dos2unix
		fi
	fi
fi

tmpFileName="giipTmpScript.sh"
logdt=`date '+%Y/%m/%d %H:%M:%S'`
Today=`date '+%Y%m%d'`
LogFileName="/var/log/giipAgent_$Today.log"
lwDownloadURL=`cat "http://giipapi.littleworld.net/api/cqe/queue/get03?sk=$sk&lssn=$lssn&os=$os&df=os" | sed -e "s/ /\%20/g"`
#echo $lwDownloadURL

curl -o $tmpFileName "$lwDownloadURL"

if [[ -s $tmpFileName ]];then
	ls -l $tmpFileName
	dos2unix $tmpFileName
	echo "[$logdt] Downloaded queue... " >> $LogFileName
else
	echo "[$logdt] No queue" >> $LogFileName
fi

# self process count = 2
while [ $cntgiip -eq 2 ];
do

	cmpFile=`cat $tmpFileName`
	n=`sed -n '/\/expect/=' giipTmpScript.sh`
	if [[ n -eq 1 ]]; then
		expect ./giipTmpScript.sh >> $LogFileName
		echo "Executed expect script..." >> $LogFileName
	else
		sh ./giipTmpScript.sh >> $LogFileName
		echo "Executed script..." >> $LogFileName
	fi

	orgFile=`cat $tmpFileName`

	curl -o $tmpFileName "$lwDownloadURL"

	if [[ -s $tmpFileName ]];then
		ls -l $tmpFileName
		dos2unix $tmpFileName
		echo "[$logdt] Downloaded queue..... " >> $LogFileName
	else
		echo "[$logdt] Process done..." >> $LogFileName
	fi

	if [[ $cmpFile = $orgFile ]];then
		rm -f $tmpFileName
	fi

	if [ -s $tmpFileName ]; then
	    echo "next process..."
	else
		echo "sleep $giipagentdelay"
        sleep $giipagentdelay
	fi

done

rm -f $tmpFileName


