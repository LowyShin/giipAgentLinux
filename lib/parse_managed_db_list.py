#!/usr/bin/env python3
# parse_managed_db_list.py
# Purpose: Extract database records from API response JSON
# Usage: python3 parse_managed_db_list.py < api_response.json

import json
import sys

try:
    data = json.load(sys.stdin)
    if 'data' in data and isinstance(data['data'], list):
        for item in data['data']:
            print(json.dumps(item))
except Exception as e:
    print(f'Error parsing JSON: {e}', file=sys.stderr)
    sys.exit(1)
