# DPA - database performance analysis
# for mysql version. 
# sqlserver(on Windows) : https://github.com/LowyShin/giipAgentWin/blob/main/giipscripts/sqlnet_put.bat

# call me when you want use DPA, we can help to use. contact@littleworld.net

# for logging
date

# pw set
export MYSQL_PWD='yourpassword'
# export json
mypath="/home/giip/logs"
myhost="mydb01"
cd $mypath
sh $mypath/mysql_rst2json.sh --sql-file $mypath/giip-dpa.sql --host $myhost --user admin --port 3306 --database counseling --out $mypath/dpa.json
sh $mypath/kvsput.sh $mypath/dpa.json sqlnetinv

# endlogging
date
echo "----"

# Cron add
## 事前にログディレクトリを作る
# mkdir -p /home/giip/logs
## 現在の crontab を保持しつつ追加（重複防止しないので注意）
# ( crontab -l 2>/dev/null; echo '*/5 * * * * sh /home/giip/db01/execmysql.sh >> /home/giip/logs/execmysql.log 2>&1' ) | crontab -
