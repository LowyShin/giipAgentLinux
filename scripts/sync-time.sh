#!/bin/bash
# Sync Linux server time with NTP

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Syncing system time..."

# Check if chronyd or ntpd is installed
if command -v chronyc &> /dev/null; then
    echo "Using chronyd for time sync..."
    sudo chronyc makestep
    sudo systemctl restart chronyd
    echo "Chronyd status:"
    chronyc tracking
elif command -v ntpdate &> /dev/null; then
    echo "Using ntpdate for time sync..."
    sudo ntpdate -s time.nist.gov
elif command -v timedatectl &> /dev/null; then
    echo "Using timedatectl for time sync..."
    sudo timedatectl set-ntp true
    sleep 2
    timedatectl status
else
    echo "Installing chrony..."
    if command -v yum &> /dev/null; then
        sudo yum install -y chrony
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y chrony
    fi
    sudo systemctl enable chronyd
    sudo systemctl start chronyd
    sudo chronyc makestep
fi

echo ""
echo "Current system time: $(date)"
echo "Timezone: $(timedatectl | grep 'Time zone' || cat /etc/timezone 2>/dev/null || echo 'Unknown')"
