#!/usr/bin/env python3
# Convert DB check results to MdbStatsUpdate format
# Input: JSON Lines from perform_check_* functions
# Output: JSON array for pApiMdbStatsUpdatebySK

import sys
import json

results = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    
    try:
        check_result = json.loads(line)
        
        # Extract performance_metrics (JSON string or object)
        perf = check_result.get('performance_metrics', {})
        if isinstance(perf, str):
            try:
                perf = json.loads(perf)
            except:
                perf = {}
        
        # Map to SP format (match Windows Agent format)
        mdb_stats = {
            "mdb_id": check_result.get('mdb_id'),
            "uptime": int(perf.get('uptime', 0) or perf.get('uptime_seconds', 0) or 0),
            "threads": int(perf.get('threads_connected', 0) or perf.get('connections', 0) or perf.get('user_connections', 0) or 0),
            "qps": int(perf.get('total_questions', 0) or perf.get('questions', 0) or 0),  # Cumulative value
            "buffer_pool": float(perf.get('buffer_cache_hit_ratio', 0) or 0),
            "cpu": 0,  # Not available from health check
            "memory": int((perf.get('memory_usage_mb', 0) or 0) // 1024 if perf.get('memory_usage_mb') else 0)
        }
        
        # Add db_connections if available
        db_conns = check_result.get('db_connections')
        if db_conns:
            mdb_stats['db_connections'] = db_conns if isinstance(db_conns, str) else json.dumps(db_conns)
        
        results.append(mdb_stats)
    except Exception as e:
        print(f"Warning: Failed to parse line: {e}", file=sys.stderr)
        continue

print(json.dumps(results, ensure_ascii=False))
