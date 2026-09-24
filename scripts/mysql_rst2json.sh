#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: mysql_getslowsql_json.sh --sql-file PATH [--host HOST] [--user USER] [--password PASS] [--port PORT] [--database DB] [--out OUT.json]

Execute the provided SQL file with the mysql client and convert the tab-separated result to JSON.

Notes:
  - The script expects a single SELECT resultset. Multiple resultsets are not handled.
  - To avoid passing password on the command line, set MYSQL_PWD environment variable.
  - Requires `mysql` and `python3` available in PATH.
  - The mysql client is invoked with --batch --raw --silent to emit a header row and tab-separated values.
USAGE
}

if [ $# -eq 0 ]; then
  usage
  exit 1
fi

# defaults
HOST=localhost
PORT=3306
USER=$(whoami)
PASSWORD=""
DB=""
OUT=""
SQLFILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --sql-file) SQLFILE="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --database|--db) DB="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$SQLFILE" ]; then
  echo "--sql-file is required" >&2
  usage
  exit 2
fi

if [ ! -f "$SQLFILE" ]; then
  echo "SQL file not found: $SQLFILE" >&2
  exit 2
fi

command -v mysql >/dev/null 2>&1 || { echo "mysql client not found in PATH" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found in PATH" >&2; exit 3; }

# output path default: same name as SQL file with .json
if [ -z "$OUT" ]; then
  base="${SQLFILE%.*}"
  OUT="${base}.json"
fi

TMP_OUT=$(mktemp)
TMP_ERR=$(mktemp)
trap 'rm -f "$TMP_OUT" "$TMP_ERR"' EXIT

MYSQL_ARGS=( -h"$HOST" -P"$PORT" -u"$USER" )
if [ -n "$DB" ]; then
  MYSQL_ARGS+=( -D"$DB" )
fi

# If password provided via --password, include it (note: appears in process list)
if [ -n "$PASSWORD" ]; then
  MYSQL_ARGS+=( -p"$PASSWORD" )
fi

echo "Running SQL -> JSON: $SQLFILE -> $OUT" >&2

# run mysql: read SQL from file and output tab-separated with header
# --batch (-B) emits tab-separated with header; --raw prevents character escaping; --silent removes extra markers
if ! mysql "${MYSQL_ARGS[@]}" --batch --raw --silent < "$SQLFILE" > "$TMP_OUT" 2> "$TMP_ERR"; then
  echo "mysql client failed; stderr:" >&2
  sed -n '1,200p' "$TMP_ERR" >&2 || true
  echo "---- stdout (first 200 lines) ----" >&2
  sed -n '1,200p' "$TMP_OUT" >&2 || true
  exit 4
fi

# inspect stderr: if it contains ERROR, fail; if it only contains password warning, show hint and continue
if [ -s "$TMP_ERR" ]; then
  if grep -qi "error" "$TMP_ERR"; then
    echo "mysql reported error(s):" >&2
    sed -n '1,200p' "$TMP_ERR" >&2 || true
    exit 5
  fi
  if grep -q "Using a password on the command line" "$TMP_ERR" || grep -q "Using a password on the command line interface can be insecure" "$TMP_ERR"; then
    echo "Warning: you passed password on the command line; consider using MYSQL_PWD environment variable or ~/.my.cnf to avoid this warning." >&2
    # continue; do not treat as fatal
  else
    # other non-fatal warnings: print them
    echo "mysql warnings (non-fatal):" >&2
    sed -n '1,200p' "$TMP_ERR" >&2 || true
  fi
fi

# convert TSV (first line headers) to JSON using python
python3 - <<'PY' "$TMP_OUT" "$OUT"
import sys, json, re

in_path = sys.argv[1]
out_path = sys.argv[2]

with open(in_path, 'r', encoding='utf-8', errors='replace') as f:
  # keep non-empty lines (strip trailing newlines)
  lines = [ln.rstrip('\n') for ln in f if ln.rstrip('\n') != '']

if not lines:
  open(out_path, 'w', encoding='utf-8').write('[]')
  print('No rows returned', file=sys.stderr)
  sys.exit(0)

# split first line into fields
first_tokens = lines[0].split('\t')

def looks_like_header(tokens):
  # heuristic: header tokens are short and match [A-Za-z0-9_]+
  if not tokens:
    return False
  # known header names we expect from giip-dpa query (lowercase)
  known = {'sql_server','spid','host_name','login_name','status','cpu_time','reads_count','writes_count','logical_reads_count','start_time','command','query_text'}
  # if any token matches a known header name, treat as header
  for t in tokens:
    if t.lower() in known:
      return True
  for t in tokens:
    if len(t) > 100:
      return False
    if not re.match(r'^[A-Za-z0-9_]+$', t):
      return False
  return True

# decide header vs no-header
if looks_like_header(first_tokens) and len(lines) > 1:
  headers = first_tokens
  data_lines = lines[1:]
else:
  # no header present: generate generic column names based on first line token count
  ncols = len(first_tokens)
  # Known giip-dpa order when no header is present
  known_order = ['sql_server','spid','host_name','login_name','status','cpu_time','reads_count','writes_count','logical_reads_count','start_time','command','query_text']
  if ncols >= len(known_order):
    headers = known_order + [f'col{i+1}' for i in range(len(known_order), ncols)]
  else:
    headers = known_order[:ncols]
  data_lines = lines

rows = []
from datetime import datetime, timezone

def to_date_ms(dt_str):
  # try parsing common datetime formats; if fails return None
  try:
    # MySQL outputs 'YYYY-MM-DD HH:MM:SS[.fraction]'
    dt = datetime.fromisoformat(dt_str.replace(' ', 'T'))
    ms = int(dt.replace(tzinfo=timezone.utc).timestamp() * 1000)
    return f"/Date({ms})/"
  except Exception:
    return None

for ln in data_lines:
  parts = ln.split('\t')
  if parts == headers:
    continue
  if len(parts) < len(headers):
    parts += [''] * (len(headers) - len(parts))
  elif len(parts) > len(headers):
    parts = parts[:len(headers)]
  rec = dict(zip(headers, parts))
  # determine sql_server (use host_name fallback)
  sql_server_val = (rec.get('sql_server') or rec.get('host_name') or '')
  if not sql_server_val or str(sql_server_val).strip() == '':
    # skip rows without sql_server target
    continue

  def to_int_safe(v):
    try:
      return int(float(v))
    except Exception:
      return 0

  # Map to required fields
  now_iso = datetime.now(timezone.utc).astimezone().isoformat()
  start_time_raw = rec.get('start_time') or ''
  start_time_conv = to_date_ms(start_time_raw) if start_time_raw else None
  out = {
    'collected_at': now_iso,
    'sql_server': sql_server_val,
    'spid': to_int_safe(rec.get('spid') or 0),
    'target_host': rec.get('host_name') or '',
    'login_name': rec.get('login_name') or '',
    'status': rec.get('status') or '',
    'cpu_time': to_int_safe(rec.get('cpu_time') or 0),
    'reads': to_int_safe(rec.get('reads_count') or rec.get('reads') or 0),
    'writes': to_int_safe(rec.get('writes_count') or rec.get('writes') or 0),
    'logical_reads': to_int_safe(rec.get('logical_reads_count') or rec.get('logical_reads') or 0),
    'start_time': start_time_conv,
    'command': rec.get('command') or '',
    'query_text': rec.get('query_text') or ''
  }
  rows.append(out)

with open(out_path, 'w', encoding='utf-8') as fo:
  json.dump(rows, fo, ensure_ascii=False, indent=2)

print(f'Wrote {len(rows)} rows to {out_path}', file=sys.stderr)
PY

echo "done" >&2
