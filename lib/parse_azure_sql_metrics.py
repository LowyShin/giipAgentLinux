#!/usr/bin/env python3
# Parse `az monitor metrics list -o json` output into a flat diagnostics object.
# Takes the most recent non-null "average" data point per requested metric.

import sys
import json

METRIC_KEY_MAP = {
    "cpu_percent": "cpu_percent",
    "dtu_consumption_percent": "dtu_consumption_percent",
    "physical_data_read_percent": "physical_data_read_percent",
    "log_write_percent": "log_write_percent",
    "storage_percent": "storage_percent",
    "workers_percent": "workers_percent",
    "sessions_percent": "sessions_percent",
}


def latest_average(series_list):
    """series_list: list of {"data":[{"timeStamp":..,"average":..}, ...]}"""
    latest_val = None
    latest_ts = None
    for series in series_list or []:
        for point in series.get("data", []) or []:
            avg = point.get("average")
            ts = point.get("timeStamp")
            if avg is None or ts is None:
                continue
            if latest_ts is None or ts > latest_ts:
                latest_ts = ts
                latest_val = avg
    return latest_val


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        print(json.dumps({"azure_status": "forbidden", "reason": "invalid_json_from_az_cli"}))
        return

    result = {"azure_status": "ok"}
    for entry in payload.get("value", []) or []:
        metric_name = (entry.get("name") or {}).get("value")
        out_key = METRIC_KEY_MAP.get(metric_name)
        if not out_key:
            continue
        val = latest_average(entry.get("timeseries"))
        result[out_key] = round(val, 1) if isinstance(val, (int, float)) else None

    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
