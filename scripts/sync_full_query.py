#!/usr/bin/env python3
import sys
import json
import subprocess
import os
import requests
import pyodbc
import pymysql

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
        req_data = {"lssn": int(lssn or 0)}
        headers = {"x-api-key": sk, "Content-Type": "application/json"}
        params = {"jsondata": json.dumps(req_data)}
        
        api_endpoint = f"{api_url}/ManagedDatabaseListForAgent"
        response = requests.get(api_endpoint, headers=headers, params=params, timeout=10)
        db_list = response.json().get("data", [])
    except Exception as e:
        log(f"Failed to fetch DB list: {e}")
        sys.exit(1)

    # 3. Process each DB
    for db in db_list:
        db_type = db.get("db_type")
        host = db.get("db_host")
        port = db.get("db_port")
        user = db.get("db_user")
        password = db.get("db_password")
        
        if not all([host, user, password]):
            continue
            
        log(f"Syncing queries for {db_type} at {host}...")
        
        try:
            if db_type == "MSSQL":
                port = port or "1433"
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
                rows = cursor.fetchall()
                conn.close()
                
            elif db_type == "MySQL":
                port = int(port or 3306)
                conn = pymysql.connect(host=host, port=port, user=user, password=password, 
                                     charset='utf8mb4', cursorclass=pymysql.cursors.DictCursor)
                with conn.cursor() as cursor:
                    cursor.execute("""
                        SELECT 
                            DIGEST as query_hash,
                            QUERY_SAMPLE_TEXT as full_text
                        FROM performance_schema.events_statements_summary_by_digest
                        WHERE LAST_SEEN > DATE_SUB(NOW(), INTERVAL 1 HOUR)
                          AND DIGEST IS NOT NULL
                    """)
                    rows = cursor.fetchall()
                conn.close()
            else:
                continue
                
            for row in rows:
                if isinstance(row, dict):
                    qhash = row['query_hash']
                    text = row['full_text']
                else:
                    qhash = row.query_hash
                    text = row.full_text
                    
                if qhash and text:
                    # Upload to KVS
                    kvs_data = {
                        "text": f"KVSPut query {qhash} full_text", 
                        "token": sk, 
                        "jsondata": text
                    }
                    requests.post(api_url, data=kvs_data, timeout=5)
                    
        except Exception as e:
            log(f"Failed to sync for {host} ({db_type}): {e}")

if __name__ == "__main__":
    main()
