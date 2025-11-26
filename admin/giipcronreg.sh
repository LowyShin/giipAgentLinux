#!/bin/bash
# You can see secret key in service page of giip
. ./giipAgent.cnf

# if you registered logical server name same as hostname then below, or put your label name
lb=`hostname`
giippath=`pwd`

echo "========================================="
echo "GIIP Agent Installation Script"
echo "========================================="
echo "Installation path: ${giippath}"
echo ""

# Check if crontab exists
crontab -l > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Creating new crontab..."
    echo "" | crontab -
fi

# Check existing GIIP installations
cntgiip=`crontab -l 2>/dev/null | grep "giipAgent.sh\|giip-auto-discover.sh\|giiprecycle.sh" | wc -l`

if [ $cntgiip -gt 0 ]; then
    echo "⚠ Existing GIIP Agent installation detected!"
    echo ""
    echo "Current GIIP cron entries:"
    crontab -l | grep "giipAgent.sh\|giip-auto-discover.sh\|giiprecycle.sh"
    echo ""
    read -p "Do you want to REMOVE old entries and reinstall? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing old GIIP cron entries..."
        # Remove all GIIP related entries
        crontab -l | grep -v "giipAgent.sh\|giip-auto-discover.sh\|giiprecycle.sh\|# 160701 Lowy, for giip" | crontab -
        echo "Old entries removed."
        echo ""
    else
        echo "Installation cancelled. Existing cron entries kept."
        exit 0
    fi
fi

# Install new crontab entries
echo "Installing GIIP Agent cron entries..."
(crontab -l 2>/dev/null; echo "# GIIP Agent - installed $(date '+%Y-%m-%d %H:%M:%S')") | crontab -
(crontab -l; echo "* * * * * cd ${giippath}; bash --login -c 'sh ${giippath}/giipAgent.sh'") | crontab -
(crontab -l; echo "59 23 * * * cd ${giippath}; bash --login -c 'sh ${giippath}/giiprecycle.sh'") | crontab -
(crontab -l; echo "*/5 * * * * cd ${giippath}; bash --login -c 'sh ${giippath}/giip-auto-discover.sh'") | crontab -

echo ""
echo "✓ GIIP Agent cron entries installed:"
crontab -l | grep "giipAgent.sh\|giip-auto-discover.sh\|giiprecycle.sh"
echo ""

# check and install dos2unix
echo "Checking required packages..."
ret=`sh giipinstmodule.sh dos2unix`

# check and install wget
ret=`sh giipinstmodule.sh wget`

# check and install curl (for auto-discovery API calls)
ret=`sh giipinstmodule.sh curl`

echo ""
echo "Setting up auto-discovery scripts..."

# Make auto-discovery script executable
if [ -f "${giippath}/giip-auto-discover.sh" ]; then
    chmod +x "${giippath}/giip-auto-discover.sh"
    echo "✓ giip-auto-discover.sh is ready."
else
    echo "⚠ Warning: giip-auto-discover.sh not found"
fi

# Make discovery script executable
if [ -f "${giippath}/giipscripts/auto-discover-linux.sh" ]; then
    chmod +x "${giippath}/giipscripts/auto-discover-linux.sh"
    echo "✓ auto-discover-linux.sh is ready."
else
    echo "⚠ Warning: auto-discover-linux.sh not found"
fi

echo ""
echo "========================================="
echo "✓ Installation completed successfully!"
echo "========================================="
echo ""
echo "Installed components:"
echo "  • GIIP Agent (runs every 1 minute)"
echo "  • Auto-Discovery (runs every 5 minutes)"
echo "  • Daily recycle (runs at 23:59)"
echo ""
echo "Log files:"
echo "  • /var/log/giipAgent_YYYYMMDD.log"
echo "  • /var/log/giip-auto-discover.log"
echo ""
echo "To verify installation:"
echo "  crontab -l"
echo ""
echo "To test auto-discovery:"
echo "  ./giip-auto-discover.sh"
echo ""
echo "========================================="
