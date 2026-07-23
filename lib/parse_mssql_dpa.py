#!/usr/bin/env python3
# Parse MSSQL DPA data
# Purpose: Convert MSSQL query result to JSON format

import sys
import json

queries = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    
    fields = line.split("\t")
    if len(fields) >= 10:
        try:
            queries.append({
                "host_name": fields[0].strip(),
                "login_name": fields[1].strip(),
                "status": fields[2].strip(),
                "cpu_time": int(fields[3]),
                "reads": int(fields[4]),
                "writes": int(fields[5]),
                "logical_reads": int(fields[6]),
                "start_time": fields[7].strip(),
                "command": fields[8].strip(),
                "query_text": fields[9].strip()
            })
        except (ValueError, IndexError):
            continue

print(json.dumps(queries, ensure_ascii=False))
