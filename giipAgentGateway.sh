#!/bin/bash
# giipAgentGateway Ver. 1.0
# Gateway Agent for managing multiple remote servers via SSH
# Written by Lowy Shin
# This agent runs on a gateway server and executes commands on remote servers

sv="1.0"

# Load configuration
. ./giipAgent.cnf

if [ "${giipagentdelay}" = "" ];then
	giipagentdelay="60"
fi

# Load server list
if [ ! -f "${serverlist_file}" ]; then
	echo "Error: Server list file not found: ${serverlist_file}"
	exit 1
fi

# Self Check
cntgiip=`ps aux | grep giipAgentGateway.sh | grep -v grep | wc -l`

# Check required tools
for cmd in ssh dos2unix wget curl; do
	if ! command -v $cmd &> /dev/null; then
		echo "Error: $cmd is not installed"
		exit 1
	fi
done

logdt=`date '+%Y%m%d%H%M%S'`
Today=`date '+%Y%m%d'`
LogFileName="/var/log/giipAgentGateway_$Today.log"
tmpDir="/tmp/giipAgent_$$"
mkdir -p $tmpDir

echo "[$logdt] Gateway Agent Started (v${sv})" >> $LogFileName

# Function to execute command on remote server via SSH
execute_remote_command() {
	local remote_host=$1
	local remote_user=$2
	local remote_port=$3
	local remote_lssn=$4
	local ssh_key=$5
	local ssh_password=$6
	local script_file=$7
	
	local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
	
	# Determine authentication method
	local use_password=0
	local use_key=0
	
	if [ -n "${ssh_password}" ]; then
		# Password authentication
		use_password=1
		echo "  → Using password authentication"
	elif [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
		# Key authentication
		use_key=1
		ssh_opts="${ssh_opts} -i ${ssh_key}"
		echo "  → Using key authentication: ${ssh_key}"
	else
		echo "  → Warning: No authentication method specified, using default"
	fi
	
	# Copy script to remote server
	if [ ${use_password} -eq 1 ]; then
		# Check if sshpass is installed
		if ! command -v sshpass &> /dev/null; then
			echo "  → Error: sshpass not installed. Run install-sshpass.sh first"
			return 1
		fi
		
		# Use sshpass for password authentication
		sshpass -p "${ssh_password}" scp ${ssh_opts} -P ${remote_port} ${script_file} ${remote_user}@${remote_host}:/tmp/giipTmpScript.sh 2>&1
		
		if [ $? -ne 0 ]; then
			echo "  → Failed to copy script (password auth)"
			return 1
		fi
		
		# Execute script on remote server
		sshpass -p "${ssh_password}" ssh ${ssh_opts} -p ${remote_port} ${remote_user}@${remote_host} "chmod +x /tmp/giipTmpScript.sh && /tmp/giipTmpScript.sh && rm -f /tmp/giipTmpScript.sh" 2>&1
	else
		# Use key authentication (or default)
		scp ${ssh_opts} -P ${remote_port} ${script_file} ${remote_user}@${remote_host}:/tmp/giipTmpScript.sh 2>&1
		
		if [ $? -ne 0 ]; then
			echo "  → Failed to copy script (key auth)"
			return 1
		fi
		
		# Execute script on remote server
		ssh ${ssh_opts} -p ${remote_port} ${remote_user}@${remote_host} "chmod +x /tmp/giipTmpScript.sh && /tmp/giipTmpScript.sh && rm -f /tmp/giipTmpScript.sh" 2>&1
	fi
	
	return $?
}

# Function to get queue for specific server
get_server_queue() {
	local lssn=$1
	local hostname=$2
	local os=$3
	local tmpFile=$4
	
	local downloadURL=`echo "${apiaddr}/api/cqe/cqequeueget03.asp?sk=$sk&lssn=$lssn&hn=${hostname}&os=$os&df=os&sv=${sv}" | sed -e "s/ /\%20/g"`
	
	wget -O $tmpFile "$downloadURL" --no-check-certificate -q
	
	if [ -s ${tmpFile} ];then
		dos2unix $tmpFile 2>/dev/null
		return 0
	else
		return 1
	fi
}

# Main loop - Process each server in the list
process_servers() {
	while IFS=',' read -r hostname lssn ssh_host ssh_user ssh_port ssh_key ssh_password os_info enabled; do
		# Skip comments and empty lines
		[[ $hostname =~ ^#.*$ ]] && continue
		[[ -z $hostname ]] && continue
		
		# Skip disabled servers
		[[ $enabled == "0" ]] && continue
		
		logdt=`date '+%Y%m%d%H%M%S'`
		
		# Clean variables
		hostname=`echo $hostname | xargs`
		lssn=`echo $lssn | xargs`
		ssh_host=`echo $ssh_host | xargs`
		ssh_user=`echo $ssh_user | xargs`
		ssh_port=`echo $ssh_port | xargs`
		ssh_key=`echo $ssh_key | xargs`
		ssh_password=`echo $ssh_password | xargs`
		os_info=`echo $os_info | xargs`
		
		# Default SSH port
		if [ "${ssh_port}" = "" ]; then
			ssh_port="22"
		fi
		
		# Default OS info
		if [ "${os_info}" = "" ]; then
			os_info="Linux"
		fi
		
		echo "[$logdt] Processing server: $hostname (LSSN: $lssn, SSH: ${ssh_user}@${ssh_host}:${ssh_port})" >> $LogFileName
		
		# Get queue from GIIP API
		tmpFileName="${tmpDir}/giipTmpScript_${lssn}.sh"
		
		get_server_queue "$lssn" "$hostname" "$os_info" "$tmpFileName"
		
		if [ -s ${tmpFileName} ]; then
			# Check for errors
			ErrChk=`cat ${tmpFileName} | grep "HTTP Error"`
			if [ "${ErrChk}" != "" ]; then
				echo "[$logdt] Error getting queue for ${hostname}: ${ErrChk}" >> $LogFileName
				rm -f $tmpFileName
				continue
			fi
			
			echo "[$logdt] Queue received for ${hostname}, executing remotely..." >> $LogFileName
			
			# Execute on remote server via SSH (with password support)
			execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" "$lssn" "$ssh_key" "$ssh_password" "$tmpFileName"
			
			if [ $? -eq 0 ]; then
				echo "[$logdt] Successfully executed on ${hostname}" >> $LogFileName
			else
				echo "[$logdt] Failed to execute on ${hostname}" >> $LogFileName
			fi
			
			rm -f $tmpFileName
		else
			echo "[$logdt] No queue for ${hostname}" >> $LogFileName
		fi
		
	done < ${serverlist_file}
}

# Main execution loop
while [ ${cntgiip} -le 3 ];
do
	logdt=`date '+%Y%m%d%H%M%S'`
	echo "[$logdt] Starting server processing cycle..." >> $LogFileName
	
	process_servers
	
	echo "[$logdt] Cycle completed, sleeping ${giipagentdelay} seconds..." >> $LogFileName
	sleep $giipagentdelay
	
	# Re-check process count
	cntgiip=`ps aux | grep giipAgentGateway.sh | grep -v grep | wc -l`
done

# Cleanup
rm -rf $tmpDir

logdt=`date '+%Y%m%d%H%M%S'`
if [ ${cntgiip} -ge 4 ]; then
	echo "[$logdt] Terminate by process count $cntgiip" >> $LogFileName
	ret=`ps aux | grep giipAgentGateway.sh | grep -v grep`
	echo "$ret" >> $LogFileName
fi

echo "[$logdt] Gateway Agent Stopped" >> $LogFileName
