#!/usr/bin/env python3
# Parse Query Store wait-stats query TSV output into JSON
# Input columns: wait_category_desc, total_wait_ms

import sys
import json

results = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue

    fields = line.split("\t")
    if len(fields) >= 2:
        try:
            results.append({
                "wait_category": fields[0].strip(),
                "total_wait_ms": int(fields[1].strip())
            })
        except (ValueError, IndexError):
            continue

print(json.dumps(results, ensure_ascii=False))
