#!/bin/bash
echo "sidhd12#45" | sudo -S sed -i 's|giipapisk"|giipApiSk2"|g' /home/giip/giipAgentLinux/giipAgent.cnf
echo "sidhd12#45" | sudo -S sed -i 's|giipapisk"|giipApiSk2"|g' /home/giip/giipAgent.cnf
echo "sidhd12#45" | sudo -S grep apiaddrv2 /home/giip/giipAgent.cnf
