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
ret=`sh giipinstmodule.sh dos2unix`

# check and install wget
ret=`sh giipinstmodule.sh wget`
