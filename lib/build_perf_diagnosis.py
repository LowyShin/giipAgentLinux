#!/usr/bin/env python3
# Combine Query Store diagnostics + Azure Monitor metrics into one diag_json with a
# rule-based "diagnosis" summary. Reads {"query_store": {...}, "azure": {...}} from stdin.
# Always prints valid JSON, even on malformed input (degrades to diagnosis="unknown").

import sys
import json
import datetime

THRESH_STORAGE = 90
THRESH_DTU = 90
THRESH_AZURE_CPU = 90
THRESH_REAL_CPU = 80


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, ValueError):
        payload = {}

    qs = payload.get("query_store") or {}
    az = payload.get("azure") or {}

    evidence = []
    diagnosis = "normal"

    azure_status = az.get("azure_status")
    storage_pct = az.get("storage_percent")
    dtu_pct = az.get("dtu_consumption_percent")
    azure_cpu = az.get("cpu_percent")

    real_cpu = qs.get("real_cpu_percent")
    waits = qs.get("wait_stats") or []
    regressions = qs.get("regressions") or []
    top_wait = waits[0] if waits else None

    # Priority: storage > resource saturation (DTU/CPU) > blocking > IO bottleneck > query regression > high real CPU
    if azure_status == "ok" and isinstance(storage_pct, (int, float)) and storage_pct >= THRESH_STORAGE:
        diagnosis = "storage_pressure"
        evidence.append(f"Azure storage_percent={storage_pct}% (>= {THRESH_STORAGE}%)")
    elif azure_status == "ok" and (
        (isinstance(dtu_pct, (int, float)) and dtu_pct >= THRESH_DTU)
        or (isinstance(azure_cpu, (int, float)) and azure_cpu >= THRESH_AZURE_CPU)
    ):
        diagnosis = "resource_saturation"
        if isinstance(dtu_pct, (int, float)) and dtu_pct >= THRESH_DTU:
            evidence.append(f"Azure dtu_consumption_percent={dtu_pct}% (>= {THRESH_DTU}%)")
        if isinstance(azure_cpu, (int, float)) and azure_cpu >= THRESH_AZURE_CPU:
            evidence.append(f"Azure cpu_percent={azure_cpu}% (>= {THRESH_AZURE_CPU}%)")
    elif top_wait and str(top_wait.get("wait_category", "")).lower() == "lock":
        diagnosis = "blocking"
        evidence.append(f"Top wait category=Lock, total_wait_ms={top_wait.get('total_wait_ms')}")
    elif (
        top_wait
        and str(top_wait.get("wait_category", "")).lower().replace(" ", "").replace("_", "") == "bufferio"
        and (real_cpu is None or (isinstance(real_cpu, (int, float)) and real_cpu < 50))
    ):
        diagnosis = "io_bottleneck"
        evidence.append(
            f"Top wait category={top_wait.get('wait_category')}, total_wait_ms={top_wait.get('total_wait_ms')}, real_cpu_percent={real_cpu}"
        )
    elif regressions:
        diagnosis = "query_regression"
        top_r = regressions[0]
        evidence.append(
            f"Query {top_r.get('query_id')} regressed: recent={top_r.get('avg_dur_recent_ms')}ms vs baseline={top_r.get('avg_dur_baseline_ms')}ms"
        )
    elif isinstance(real_cpu, (int, float)) and real_cpu >= THRESH_REAL_CPU:
        diagnosis = "high_cpu"
        evidence.append(f"real_cpu_percent={real_cpu}% (>= {THRESH_REAL_CPU}%)")
    elif qs.get("query_store_status") not in ("READ_WRITE", "READ_ONLY") and azure_status != "ok":
        diagnosis = "insufficient_data"
        evidence.append(f"query_store_status={qs.get('query_store_status')}, azure_status={azure_status}")

    result = {
        "diagnosis": diagnosis,
        "evidence": evidence,
        "query_store": qs,
        "azure": az,
        "collected_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
