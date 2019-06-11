#!/bin/bash

cnt=`ps aux | grep giipAgent.sh | grep -v grep | wc -l`
if [ $cnt -gt 0 ]; then
    ps aux | grep giipAgent.sh | grep -v grep | awk '{ print "kill -9", $2 }' | sh
else
    echo "no process you checked..."
fi
