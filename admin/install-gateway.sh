#!/bin/bash
# Installation script for GIIP Agent Gateway
# This script sets up the gateway agent on a bastion/gateway server

echo "======================================"
echo "GIIP Agent Gateway Installation"
echo "======================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
	echo "⚠️  Warning: Not running as root. Some operations may fail."
	echo "   Consider running with: sudo $0"
	echo ""
fi

# Check required commands
echo "Checking required packages..."
MISSING=""

for cmd in ssh scp dos2unix wget curl; do
	if ! command -v $cmd &> /dev/null; then
		MISSING="$MISSING $cmd"
	fi
done

if [ "$MISSING" != "" ]; then
	echo "❌ Missing packages:$MISSING"
	echo ""
	echo "Installing missing packages..."
	
	# Detect OS
	if [ -f /etc/redhat-release ]; then
		# RedHat/CentOS
		yum install -y openssh-clients dos2unix wget curl
	elif [ -f /etc/debian_version ]; then
		# Debian/Ubuntu
		apt-get update
		apt-get install -y openssh-client dos2unix wget curl
	else
		echo "⚠️  Unknown OS. Please install manually:$MISSING"
		exit 1
	fi
fi

echo "✓ All required packages are installed"
echo ""

# Create working directory
INSTALL_DIR="$HOME/giipAgentGateway"

if [ -d "$INSTALL_DIR" ]; then
	echo "⚠️  Installation directory already exists: $INSTALL_DIR"
	read -p "Do you want to overwrite? (y/N): " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		echo "Installation cancelled"
		exit 1
	fi
	rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "✓ Created installation directory: $INSTALL_DIR"
echo ""

# Copy gateway files
echo "Installing gateway agent files..."
cp ../giipAgentLinux/giipAgentGateway.sh .
cp ../giipAgentLinux/giipAgent.cnf .
cp ../giipAgentLinux/giipAgentGateway_servers.csv .

chmod +x giipAgentGateway.sh

echo "✓ Gateway agent files installed"
echo ""

# Setup SSH keys
echo "======================================"
echo "SSH Key Setup"
echo "======================================"
echo ""
echo "The gateway agent needs SSH access to remote servers."
echo ""
echo "Options:"
echo "  1. Use existing SSH key"
echo "  2. Generate new SSH key"
echo "  3. Skip (configure manually later)"
echo ""

read -p "Select option (1-3): " -n 1 -r
echo
echo ""

if [[ $REPLY == "1" ]]; then
	read -p "Enter path to existing SSH private key: " SSH_KEY_PATH
	if [ -f "$SSH_KEY_PATH" ]; then
		echo "✓ SSH key found: $SSH_KEY_PATH"
		echo ""
		echo "Make sure this key is added to authorized_keys on remote servers:"
		echo "  ssh-copy-id -i ${SSH_KEY_PATH}.pub user@remote_host"
	else
		echo "❌ SSH key not found: $SSH_KEY_PATH"
	fi
elif [[ $REPLY == "2" ]]; then
	SSH_KEY_PATH="$HOME/.ssh/giip_gateway_key"
	
	if [ -f "$SSH_KEY_PATH" ]; then
		echo "⚠️  Key already exists: $SSH_KEY_PATH"
	else
		echo "Generating new SSH key..."
		ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "giip-gateway@$(hostname)"
		echo "✓ SSH key generated: $SSH_KEY_PATH"
	fi
	
	echo ""
	echo "📋 Next steps:"
	echo "  1. Copy public key to remote servers:"
	echo "     ssh-copy-id -i ${SSH_KEY_PATH}.pub user@remote_host"
	echo ""
	echo "  2. Or manually add to ~/.ssh/authorized_keys on remote servers:"
	echo "     cat ${SSH_KEY_PATH}.pub"
	cat "${SSH_KEY_PATH}.pub"
else
	echo "⚠️  SSH key configuration skipped"
	SSH_KEY_PATH="~/.ssh/id_rsa"
fi

echo ""
echo "======================================"
echo "Configuration"
echo "======================================"
echo ""

read -p "Enter your GIIP Secret Key (sk): " GIIP_SK

if [ "$GIIP_SK" != "" ]; then
	sed -i "s|sk=\"<your secret key>\"|sk=\"$GIIP_SK\"|g" giipAgent.cnf
	echo "✓ Secret key configured"
fi

echo ""
echo "======================================"
echo "Server List Configuration"
echo "======================================"
echo ""
echo "Edit giipAgentGateway_servers.csv to add your remote servers."
echo "Format: hostname,lssn,ssh_host,ssh_user,ssh_port,ssh_key_path,os_info,enabled"
echo ""
echo "Example:"
echo "webserver01,1001,192.168.1.10,root,22,$SSH_KEY_PATH,CentOS%207,1"
echo ""

read -p "Do you want to edit the server list now? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
	${EDITOR:-vi} giipAgentGateway_servers.csv
fi

echo ""
echo "======================================"
echo "Cron Job Setup"
echo "======================================"
echo ""
echo "The gateway agent should run continuously. You can:"
echo "  1. Run manually: ./giipAgentGateway.sh"
echo "  2. Add to crontab for auto-restart"
echo ""

read -p "Do you want to add to crontab? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
	CRON_LINE="*/5 * * * * cd $INSTALL_DIR && ./giipAgentGateway.sh >/dev/null 2>&1"
	
	# Check if already in crontab
	(crontab -l 2>/dev/null | grep -q "giipAgentGateway.sh") && {
		echo "⚠️  Cron job already exists"
	} || {
		(crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
		echo "✓ Cron job added (runs every 5 minutes)"
	}
fi

echo ""
echo "======================================"
echo "Installation Complete!"
echo "======================================"
echo ""
echo "📁 Installation directory: $INSTALL_DIR"
echo "🔑 SSH key: $SSH_KEY_PATH"
echo ""
echo "Next steps:"
echo "  1. Configure server list: vi $INSTALL_DIR/giipAgentGateway_servers.csv"
echo "  2. Test SSH connections to remote servers"
echo "  3. Start gateway agent: cd $INSTALL_DIR && ./giipAgentGateway.sh"
echo "  4. Check logs: tail -f /var/log/giipAgentGateway_*.log"
echo ""
echo "For more information, see README_GATEWAY.md"
echo ""
