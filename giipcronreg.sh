# You can see secret key in service page of giip
. giipAgent.cnf

# if you registered logical server name same as hostname then below, or put your label name
lb=`hostname`

# Append to crontab
crontab -l
(crontab -l ; echo "# 160701 Lowy, for giip")| crontab -
(crontab -l ; echo "* * * * * bash --login -c 'sh /usr/local/giip/scripts/giipAgent.sh'")| crontab -
(crontab -l ; echo "59 2 * * * bash --login -c 'sh /usr/local/giip/scripts/giiprecycle.sh'")| crontab -
crontab -l

# check and install dos2unix
CHECK_Converter=`which dos2unix`
RESULT=`echo $?`
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


# check and install wget
CHECK_Converter=`which wget`
RESULT=`echo $?`
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
