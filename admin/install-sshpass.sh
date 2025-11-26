#!/bin/bash
# Install sshpass for password-based SSH authentication
# This is required for servers with PubkeyAuthentication disabled

echo "Installing sshpass..."

# Detect OS and install accordingly
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    echo "Detected Debian/Ubuntu"
    apt-get update
    apt-get install -y sshpass
elif [ -f /etc/redhat-release ]; then
    # CentOS/RHEL
    echo "Detected CentOS/RHEL"
    
    # Check if EPEL is enabled
    if ! rpm -q epel-release &>/dev/null; then
        echo "Installing EPEL repository..."
        yum install -y epel-release
    fi
    
    yum install -y sshpass
else
    echo "Unsupported OS. Please install sshpass manually."
    exit 1
fi

# Verify installation
if command -v sshpass &> /dev/null; then
    echo "✅ sshpass installed successfully"
    sshpass -V
else
    echo "❌ Failed to install sshpass"
    exit 1
fi
