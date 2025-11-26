#!/bin/bash
# Test script for GIIP Agent Gateway
# This script validates the gateway configuration and SSH connectivity

echo "======================================"
echo "GIIP Agent Gateway Test Script"
echo "======================================"
echo ""

# Load configuration
if [ ! -f "./giipAgent.cnf" ]; then
	echo "❌ Error: giipAgent.cnf not found"
	echo "   Run this script from giipAgentGateway installation directory"
	exit 1
fi

. ./giipAgent.cnf

echo "✓ Configuration loaded"
echo ""

# Check server list
if [ ! -f "${serverlist_file}" ]; then
	echo "❌ Error: Server list not found: ${serverlist_file}"
	exit 1
fi

echo "✓ Server list found: ${serverlist_file}"
echo ""

# Test required commands
echo "Checking required commands..."
MISSING=""

for cmd in ssh scp dos2unix wget curl; do
	if command -v $cmd &> /dev/null; then
		echo "  ✓ $cmd"
	else
		echo "  ❌ $cmd (missing)"
		MISSING="$MISSING $cmd"
	fi
done

if [ "$MISSING" != "" ]; then
	echo ""
	echo "❌ Missing packages:$MISSING"
	echo "   Install with: yum install -y$MISSING"
	exit 1
fi

echo ""
echo "======================================"
echo "Testing Server Connections"
echo "======================================"
echo ""

SUCCESS=0
FAILED=0

while IFS=',' read -r hostname lssn ssh_host ssh_user ssh_port ssh_key os_info enabled; do
	# Skip comments and empty lines
	[[ $hostname =~ ^#.*$ ]] && continue
	[[ -z $hostname ]] && continue
	
	# Skip disabled servers
	if [ "$enabled" = "0" ]; then
		echo "⊘ $hostname - DISABLED (skipped)"
		continue
	fi
	
	# Clean variables
	hostname=`echo $hostname | xargs`
	ssh_host=`echo $ssh_host | xargs`
	ssh_user=`echo $ssh_user | xargs`
	ssh_port=`echo $ssh_port | xargs`
	ssh_key=`echo $ssh_key | xargs`
	
	# Default port
	if [ "${ssh_port}" = "" ]; then
		ssh_port="22"
	fi
	
	echo -n "Testing $hostname (${ssh_user}@${ssh_host}:${ssh_port})... "
	
	# Build SSH options
	ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes"
	
	if [ "${ssh_key}" != "" ] && [ -f "${ssh_key}" ]; then
		ssh_opts="${ssh_opts} -i ${ssh_key}"
	fi
	
	# Test connection
	result=$(ssh ${ssh_opts} -p ${ssh_port} ${ssh_user}@${ssh_host} "echo 'SUCCESS' && hostname && uname -a" 2>&1)
	
	if echo "$result" | grep -q "SUCCESS"; then
		echo "✓ OK"
		echo "     Remote hostname: $(echo "$result" | sed -n '2p')"
		SUCCESS=$((SUCCESS + 1))
	else
		echo "❌ FAILED"
		echo "     Error: $result" | head -3
		FAILED=$((FAILED + 1))
	fi
	echo ""
	
done < ${serverlist_file}

echo "======================================"
echo "Test Summary"
echo "======================================"
echo "  ✓ Success: $SUCCESS"
echo "  ❌ Failed: $FAILED"
echo ""

if [ $FAILED -gt 0 ]; then
	echo "⚠️  Some servers failed connection test"
	echo "   Check SSH keys, network connectivity, and credentials"
	exit 1
else
	echo "✅ All enabled servers are accessible!"
	echo ""
	echo "Next steps:"
	echo "  1. Start gateway agent: ./giipAgentGateway.sh"
	echo "  2. Check logs: tail -f /var/log/giipAgentGateway_*.log"
	echo "  3. Monitor from GIIP web portal"
fi

echo ""
