appname="$1"
CHECK_Converter=`which $appname`
RESULT=`echo $?`

uname=`uname -a | awk '{print $1}'`
if [ $uname = "Darwin" ];then
	osname=`sw_vers -productName`
	osver=`sw_vers -productVersion`
	os="${osname} ${osver}"
	os=`echo "$os" | sed -e "s/ /%20/g"`
	if [ ${RESULT} != 0 ];then
		brew install $appname
	fi
else
	ostype=`head -n 1 /etc/issue | awk '{print $1}'`
	if [ $ostype = "Ubuntu" ];then
		os=`lsb_release -d`
		os=`echo "$os"| sed -e "s/Description\://g"`

		if [ ${RESULT} != 0 ];then
			apt-get install -y $appname
		fi
	else
		os=`cat /etc/redhat-release`

		if [ ${RESULT} != 0 ];then
			yum install -y $appname
		fi
	fi
fi
