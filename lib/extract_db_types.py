#!/usr/bin/env python3
# extract_db_types.py
# Purpose: Extract unique database types from managed database list
# Usage: python3 extract_db_types.py < db_list.jsonl

import json
import sys

db_types = set()
for line in sys.stdin:
    if line.strip():
        try:
            data = json.loads(line)
            db_type = data.get('db_type', '')
            if db_type:
                db_types.add(db_type)
        except:
            pass
print(' '.join(sorted(db_types)))
