#!/bin/bash
# You can see secret key in service page of giip
# cnf lives in the repo's PARENT directory (see README quick-start), not repo root.
. ../giipAgent.cnf

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
cntgiip=`crontab -l 2>/dev/null | grep "giipAgent.sh\|giipAgent3.sh\|giip-auto-discover.sh\|giiprecycle.sh\|collect-server-diagnostics.sh" | wc -l`

if [ $cntgiip -gt 0 ]; then
    echo "⚠ Existing GIIP Agent installation detected!"
    echo ""
    echo "Current GIIP cron entries:"
    crontab -l | grep "giipAgent.sh\|giipAgent3.sh\|giip-auto-discover.sh\|giiprecycle.sh\|collect-server-diagnostics.sh"
    echo ""
    read -p "Do you want to REMOVE old entries and reinstall? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing old GIIP cron entries..."
        # Remove all GIIP related entries
        crontab -l | grep -v "giipAgent.sh\|giipAgent3.sh\|giip-auto-discover.sh\|giiprecycle.sh\|collect-server-diagnostics.sh\|# 160701 Lowy, for giip" | crontab -
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
(crontab -l; echo "* * * * * cd ${giippath}; bash --login -c 'sh ${giippath}/giipAgent3.sh'") | crontab -
(crontab -l; echo "0 * * * * cd ${giippath}; bash --login -c 'sh ${giippath}/scripts/collect-server-diagnostics.sh'") | crontab -
(crontab -l; echo "59 23 * * * cd ${giippath}; bash --login -c 'sh ${giippath}/admin/giiprecycle.sh'") | crontab -
(crontab -l; echo "*/5 * * * * cd ${giippath}; bash --login -c 'sh ${giippath}/scripts/giip-auto-discover.sh'") | crontab -

echo ""
echo "✓ GIIP Agent cron entries installed:"
crontab -l | grep "giipAgent.sh\|giipAgent3.sh\|giip-auto-discover.sh\|giiprecycle.sh\|collect-server-diagnostics.sh"
echo ""

# check and install dos2unix
echo "Checking required packages..."
ret=`sh admin/giipinstmodule.sh dos2unix`

# check and install wget
ret=`sh admin/giipinstmodule.sh wget`

# check and install curl (for auto-discovery API calls)
ret=`sh admin/giipinstmodule.sh curl`

# check and install jq (giipAgent3.sh uses jq for all API request/response JSON encoding)
ret=`sh admin/giipinstmodule.sh jq`

echo ""
echo "Setting up auto-discovery scripts..."

# Make auto-discovery script executable
if [ -f "${giippath}/scripts/giip-auto-discover.sh" ]; then
    chmod +x "${giippath}/scripts/giip-auto-discover.sh"
    echo "✓ giip-auto-discover.sh is ready."
else
    echo "⚠ Warning: giip-auto-discover.sh not found"
fi

# Make discovery script executable
if [ -f "${giippath}/scripts/auto-discover-linux.sh" ]; then
    chmod +x "${giippath}/scripts/auto-discover-linux.sh"
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
echo "  sudo crontab -l   # entries are installed under root's crontab (apt needs sudo)"
echo ""
echo "To test auto-discovery:"
echo "  ./scripts/giip-auto-discover.sh"
echo ""
echo "========================================="
