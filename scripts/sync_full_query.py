#!/usr/bin/env python3
import sys
import json
import subprocess
import os

def log(msg):
    print(f"[SyncFullQuery] {msg}")

def main():
    agent_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    config_file = os.path.join(agent_root, "giipAgent.cnf")
    
    if not os.path.exists(config_file):
        log(f"Error: Config file not found at {config_file}")
        sys.exit(1)

    # 1. Load config
    config = {}
    with open(config_file, "r") as f:
        for line in f:
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                config[k.strip()] = v.strip().strip('"').strip("'")

    lssn = config.get("lssn")
    sk = config.get("sk")
    api_url = config.get("apiaddrv2")
    
    if not all([lssn, sk, api_url]):
        log("Error: Missing required config (lssn, sk, apiaddrv2)")
        sys.exit(1)

    # 2. Get DB List via API
    try:
        req_data = {"lssn": int(lssn)}
        # Simulate Invoke-GiipApiV2 logic
        # Note: In real scenarios, we'd use requests library, but here we'll assume it's available or use curl
        import requests
        headers = {"x-api-key": sk, "Content-Type": "application/json"}
        params = {"jsondata": json.dumps(req_data)}
        # CommandText equivalent for ManagedDatabaseListForAgent lssn
        # This part depends on how the GIIP API routes commands. 
        # For simplicity, we assume a known endpoint or command pattern.
        # Based on SyncFullQuery.ps1: Invoke-GiipApiV2 -CommandText "ManagedDatabaseListForAgent lssn"
        # We'll use a placeholder URL structure or the specified api_url
        
        # Actually, let's use subprocess curl to stay consistent with other shell scripts if needed,
        # but Python requests is better if available.
        api_endpoint = f"{api_url}/ManagedDatabaseListForAgent"
        response = requests.get(api_endpoint, headers=headers, params=params, timeout=10)
        db_list = response.json().get("data", [])
    except Exception as e:
        log(f"Failed to fetch DB list: {e}")
        sys.exit(1)

    # 3. Process each MSSQL DB
    import pyodbc
    for db in db_list:
        if db.get("db_type") != "MSSQL":
            continue
            
        host = db.get("db_host")
        port = db.get("db_port", "1433")
        user = db.get("db_user")
        password = db.get("db_password")
        
        log(f"Syncing queries for {host}...")
        try:
            conn_str = f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={host},{port};DATABASE=master;UID={user};PWD={password};Connection Timeout=10;"
            conn = pyodbc.connect(conn_str)
            cursor = conn.cursor()
            cursor.execute("""
                SELECT 
                    CONVERT(NVARCHAR(64), qs.query_hash, 1) as query_hash,
                    st.text as full_text
                FROM sys.dm_exec_query_stats qs
                CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
                WHERE qs.last_execution_time > DATEADD(HOUR, -1, GETDATE())
            """)
            
            for row in cursor.fetchall():
                qhash = row.query_hash
                text = row.full_text
                if qhash and text:
                    # Upload to KVS
                    # kvsput.sh <json_file/string> <factor>
                    # We'll use curl directly for simplicity or call kvsput.sh
                    kvs_data = {"text": f"KVSPut query {qhash} full_text", "token": sk, "jsondata": text}
                    requests.post(api_url, data=kvs_data, timeout=5)
            
            conn.close()
        except Exception as e:
            log(f"Failed to sync for {host}: {e}")

if __name__ == "__main__":
    main()
