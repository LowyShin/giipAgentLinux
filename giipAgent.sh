#!/bin/bash
# giipAgent Ver. 1.4
sv="1.72"
# Written by Lowy Shin at 20140922
# Supported OS : MacOS, CentOS, Ubuntu, Some Linux
# 190611 Lowy, Change agent download method to git repository.

# Usable giip variables =========
# {{today}} : Replace today to "YYYYMMDD"

# User Variables ===============================================
. ./giipAgent.cnf

if [ "${giipagentdelay}" = "" ];then
	giipagentdelay="60"
fi

# Self Check
cntgiip=`ps aux | grep giipAgent.sh | grep -v grep | wc -l`

# Check dos2unix
CHECK_Converter=`which dos2unix`
RESULT=`echo $?`

#OS Check
# Check MacOS
uname=`uname -a | awk '{print $1}'`
if [ "${uname}" = "Darwin" ];then
	osname=`sw_vers -productName`
	osver=`sw_vers -productVersion`
	os="${osname} ${osver}"
	os=`echo "$os" | sed 's/^ *\| *$//'`
	os=`echo "$os" | sed -e "s/ /%20/g"`
	if [ ${RESULT} -ne 0 ];then
		brew install dos2unix
	fi
else
	ostype=`head -n 1 /etc/issue | awk '{print $1}'`
	if [ "${ostype}" = "Ubuntu" ];then
		os=`lsb_release -d`
		os=`echo "$os" | sed 's/^ *\| *$//'`
		os=`echo "$os" | sed -e "s/Description\://g"`

		if [ ${RESULT} -ne 0 ];then
			apt-get install -y dos2unix
		fi
	else
		os=`cat /etc/redhat-release`

		if [ ${RESULT} -ne 0 ];then
			yum install -y dos2unix
		fi
	fi
fi

hn=`hostname`
tmpFileName="giipTmpScript.sh"
logdt=`date '+%Y%m%d%H%M%S'`
Today=`date '+%Y%m%d'`
LogFileName="/var/log/giipAgent_$Today.log"
lwDownloadURL=`echo "https://giipasp.azurewebsites.net/api/cqe/cqequeueget03.asp?sk=$sk&lssn=$lssn&hn=${hn}&os=$os&df=os&sv=${sv}" | sed -e "s/ /\%20/g"`
#echo $lwDownloadURL

# Add Server
if [ "${lssn}" = "0" ];then
	curl -o $tmpFileName "$lwDownloadURL"
	lssn=`cat ${tmpFileName}`
	cnfdmp=`cat ./giipAgent.cnf | sed -e "s|lssn=\"0\"|lssn=\"${lssn}\"|g"`
	echo "${cnfdmp}" >giipAgent.cnf
	rm -f $tmpFileName
	lwDownloadURL=`echo "https://giipasp.azurewebsites.net/api/cqe/cqequeueget03.asp?sk=$sk&lssn=$lssn&hn=${hn}&os=$os&df=os&sv=${sv}" | sed -e "s/ /\%20/g"`
fi

# self process count = 2
while [ ${cntgiip} -le 3 ];
do

	curl -o $tmpFileName "$lwDownloadURL"

	if [ -s ${tmpFileName} ];then
		ls -l $tmpFileName
		dos2unix $tmpFileName
		echo "[$logdt] Downloaded queue... " >> $LogFileName
	else
		echo "[$logdt] No queue" >> $LogFileName
	fi

	cmpFile=`cat $tmpFileName`
	ErrChk=`cat ${tmpFileName} | grep "HTTP Error"`
	if [ "${ErrChk}" != "" ]; then
		rm -f $tmpFileName
	    echo "[$logdt]Stop by error. ${ErrChk}" >> $LogFileName
		exit 0
	else
		if [ -s ${tmpFileName} ];then
			n=`cat giipTmpScript.sh | grep 'expect=' | wc -l`
			if [ ${n} -ge 1 ]; then
				expect ./giipTmpScript.sh >> $LogFileName
				echo "[$logdt]Executed expect script..." >> $LogFileName
				rm -f $tmpFileName
			else
				sh ./giipTmpScript.sh >> $LogFileName
				echo "[$logdt]Executed script..." >> $LogFileName
				rm -f $tmpFileName
			fi
		else
			echo "[$logdt]Work Done $giipagentdelay" >> $LogFileName
	        sleep $giipagentdelay
		fi
	fi
	rm -f $tmpFileName

done
if [ ${cntgiip} -ge 4 ]; then
	echo "[$logdt]terminate by process count $cntgiip" >> $LogFileName
	ret=`ps aux | grep giipAgent.sh | grep -v grep`
	echo "$ret" >> $LogFileName
fi

rm -f $tmpFileName
