#!/usr/bin/env python3
# Parse Query Store regression query TSV output into JSON
# Input columns: query_id, avg_dur_recent(us), avg_dur_baseline(us), exec_recent, query_text

import sys
import json

results = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue

    fields = line.split("\t")
    if len(fields) >= 5:
        try:
            results.append({
                "query_id": int(fields[0].strip()),
                "avg_dur_recent_ms": round(int(fields[1].strip()) / 1000.0, 1),
                "avg_dur_baseline_ms": round(int(fields[2].strip()) / 1000.0, 1),
                "exec_count": int(fields[3].strip()),
                "query_text": fields[4].strip()[:500]
            })
        except (ValueError, IndexError):
            continue

print(json.dumps(results, ensure_ascii=False))
