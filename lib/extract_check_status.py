#!/usr/bin/env python3
# Extract status from check result JSON
# Usage: echo '{"status":"success",...}' | python3 extract_check_status.py

import sys
import json

try:
    obj = json.load(sys.stdin)
    print(obj.get('status', 'unknown'))
except:
    print('unknown')
