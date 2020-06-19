#!/bin/bash
# You can see secret key in service page of giip
. ./giipAgent.cnf

# if you registered logical server name same as hostname then below, or put your label name
lb=`hostname`
giippath=`pwd`

# Append to crontab
cntgiip=`crontab -l | grep giipAgent.sh | wc -l`
if [ $cntgiip -eq 0 ]; then
    (crontab -l ; echo "# 160701 Lowy, for giip")| crontab -
    (crontab -l ; echo "* * * * * cd ${giippath}; bash --login -c 'sh ${giippath}/giipAgent.sh'")| crontab -
    (crontab -l ; echo "59 2 * * * cd ${giippath}; bash --login -c 'sh ${giippath}/giiprecycle.sh'")| crontab -

    crontab -l
else
    echo "already giip agent installed... abort install process. "
fi

# check and install dos2unix
ret=`sh giipinstmodule.sh dos2unix`

# check and install wget
ret=`sh giipinstmodule.sh wget`
