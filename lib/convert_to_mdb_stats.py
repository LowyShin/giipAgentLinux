#!/usr/bin/env python3
# Convert DB check results to MdbStatsUpdate format
# Input: JSON Lines from perform_check_* functions
# Output: JSON array for pApiMdbStatsUpdatebySK

import sys
import json
import os
import time

STATE_DIR = "/tmp/giip_mdb_perf_state"


def load_prev_state(mdb_id):
    path = os.path.join(STATE_DIR, f"{mdb_id}.json")
    try:
        with open(path, "r") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_state(mdb_id, cumulative_batch_requests, ts):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        path = os.path.join(STATE_DIR, f"{mdb_id}.json")
        with open(path, "w") as f:
            json.dump({"total_batch_requests": cumulative_batch_requests, "ts": ts}, f)
    except OSError:
        pass


def compute_qps_delta(mdb_id, cumulative_value):
    """total_batch_requests (MSSQL) is a CUMULATIVE counter since server start.
    QPS must be the delta between two collection cycles divided by elapsed seconds
    (SQL_SERVER_PERFORMANCE_STORAGE_RULES.md Sec 3.1, giip-issue #921). First run / missing
    state / counter reset (cumulative_value < prev, e.g. SQL Server restart) safely falls
    back to 0 rather than reporting a bogus huge or negative number."""
    now = time.time()
    prev = load_prev_state(mdb_id)
    save_state(mdb_id, cumulative_value, now)

    if not prev:
        return 0
    elapsed = now - prev.get("ts", now)
    prev_value = prev.get("total_batch_requests", cumulative_value)
    if elapsed <= 0 or cumulative_value < prev_value:
        return 0
    return int((cumulative_value - prev_value) / elapsed)


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
            except Exception:
                perf = {}

        mdb_id = check_result.get('mdb_id')

        # QPS: MySQL already sends a directly-usable 'questions'/'total_questions' value.
        # MSSQL sends 'total_batch_requests', a CUMULATIVE counter (giip-issue #921 fix —
        # previously this branch didn't exist at all, so MSSQL QPS was always 0) that must be
        # delta'd across collection cycles per-mdb_id, never used as-is.
        if 'total_batch_requests' in perf and perf.get('total_batch_requests') is not None:
            try:
                qps = compute_qps_delta(mdb_id, int(perf.get('total_batch_requests') or 0))
            except (TypeError, ValueError):
                qps = 0
        else:
            qps = int(perf.get('total_questions', 0) or perf.get('questions', 0) or 0)

        # CPU: MSSQL now reports real_cpu_percent (ring-buffer based, giip-issue #921 fix —
        # previously hardcoded to 0 here regardless of what the agent collected). Other DB
        # types keep prior behavior (perf['cpu'] if ever populated, else 0 — unchanged).
        cpu = perf.get('real_cpu_percent', None)
        if cpu is None:
            cpu = perf.get('cpu', 0) or 0
        try:
            cpu = float(cpu)
        except (TypeError, ValueError):
            cpu = 0

        # Map to SP format (match Windows Agent format)
        mdb_stats = {
            "mdb_id": mdb_id,
            "uptime": int(perf.get('uptime', 0) or perf.get('uptime_seconds', 0) or 0),
            "threads": int(perf.get('threads_connected', 0) or perf.get('connections', 0) or perf.get('user_connections', 0) or 0),
            "qps": qps,
            "buffer_pool": float(perf.get('buffer_cache_hit_ratio', 0) or 0),
            "cpu": cpu,
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
