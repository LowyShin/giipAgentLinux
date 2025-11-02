#!/usr/bin/env bash
#
# DPA Upload Script with Enhanced Debugging
# Purpose: Upload DPA (Database Performance Analysis) data to KVS with detailed error tracking
#

set -euo pipefail

# Configuration
export MYSQL_PWD='I,FtEV=8'
mypath="/home/shinh/scripts/p-cnsldb01m/giipAgentLinux/giipscripts"
myhost="p-cnsldb01m"
log_file="${mypath}/dpa_upload_$(date +%Y%m%d_%H%M%S).log"

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$log_file"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$log_file" >&2
}

log "=== DPA Upload Process Started ==="
log "Working directory: $mypath"
log "MySQL host: $myhost"
log "Log file: $log_file"

# Check prerequisites
log "Checking prerequisites..."
for cmd in mysql python3 jq curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "$cmd is not installed or not in PATH"
    exit 1
  fi
  log "  ✓ $cmd found: $(command -v $cmd)"
done

# Check if files exist
log "Checking required files..."
if [ ! -f "$mypath/mysql_rst2json.sh" ]; then
  log_error "mysql_rst2json.sh not found"
  exit 1
fi
if [ ! -f "$mypath/giip-dpa.sql" ]; then
  log_error "giip-dpa.sql not found"
  exit 1
fi
if [ ! -f "$mypath/kvsput.sh" ]; then
  log_error "kvsput.sh not found"
  exit 1
fi
log "  ✓ All required files exist"

# Check MySQL connectivity
log "Testing MySQL connectivity..."
if ! mysql -h"$myhost" -uadmin -P3306 -Dcounseling -e "SELECT 1;" >/dev/null 2>&1; then
  log_error "Cannot connect to MySQL server $myhost"
  log_error "Please check:"
  log_error "  1. MySQL server is running"
  log_error "  2. Host/port is correct"
  log_error "  3. Username/password is correct"
  log_error "  4. Network connectivity"
  exit 1
fi
log "  ✓ MySQL connection successful"

# Change to working directory
cd "$mypath" || { log_error "Cannot change to $mypath"; exit 1; }

# Step 1: Generate JSON from SQL query
log "Step 1: Executing SQL query and converting to JSON..."
if ! sh "$mypath/mysql_rst2json.sh" \
  --sql-file "$mypath/giip-dpa.sql" \
  --host "$myhost" \
  --user admin \
  --port 3306 \
  --database counseling \
  --out "$mypath/dpa.json" 2>&1 | tee -a "$log_file"; then
  log_error "mysql_rst2json.sh failed"
  exit 1
fi

# Check if JSON file was created
if [ ! -f "$mypath/dpa.json" ]; then
  log_error "dpa.json was not created"
  exit 1
fi

# Check JSON file size
json_size=$(stat -f%z "$mypath/dpa.json" 2>/dev/null || stat -c%s "$mypath/dpa.json" 2>/dev/null || echo "0")
log "  ✓ JSON file created: dpa.json (size: $json_size bytes)"

if [ "$json_size" -eq 0 ]; then
  log_error "dpa.json is empty"
  exit 1
fi

# Validate JSON format
log "Validating JSON format..."
if ! jq empty "$mypath/dpa.json" 2>&1 | tee -a "$log_file"; then
  log_error "Invalid JSON format in dpa.json"
  exit 1
fi

# Count records
record_count=$(jq '. | length' "$mypath/dpa.json")
log "  ✓ JSON is valid: $record_count records"

if [ "$record_count" -eq 0 ]; then
  log "Warning: No records to upload (empty result set)"
  exit 0
fi

# Show sample data (first record only)
log "Sample data (first record):"
jq '.[0]' "$mypath/dpa.json" 2>&1 | head -20 | tee -a "$log_file" || true

# Step 2: Upload to KVS
log "Step 2: Uploading to KVS..."
log "kFactor: sqlnetinv"

# Set timeout for curl (prevent hanging)
export CURL_TIMEOUT=60

# Run kvsput.sh with detailed output
if ! sh "$mypath/kvsput.sh" "$mypath/dpa.json" sqlnetinv 2>&1 | tee -a "$log_file"; then
  log_error "kvsput.sh failed"
  log_error "Possible causes:"
  log_error "  1. Azure Function timeout (data too large: $json_size bytes)"
  log_error "  2. Authentication failure (check token in giipAgent.cnf)"
  log_error "  3. Network connectivity to Azure"
  log_error "  4. API endpoint issue"
  log_error ""
  log_error "Troubleshooting steps:"
  log_error "  1. Check giipAgent.cnf for correct apiaddrv2 and UserToken"
  log_error "  2. Test Azure Function endpoint manually:"
  log_error "     curl -v '<endpoint_url>'"
  log_error "  3. Check Azure Function logs in Azure Portal"
  log_error "  4. If data is too large, consider:"
  log_error "     - Adding LIMIT clause to giip-dpa.sql"
  log_error "     - Splitting data into smaller batches"
  exit 1
fi

log "=== DPA Upload Process Completed Successfully ==="
log "Total records uploaded: $record_count"
log "JSON file size: $json_size bytes"
log "Full log saved to: $log_file"

# Optional: Archive old JSON file
backup_dir="${mypath}/backup"
mkdir -p "$backup_dir"
cp "$mypath/dpa.json" "$backup_dir/dpa_$(date +%Y%m%d_%H%M%S).json"
log "Backup created in: $backup_dir"

exit 0
