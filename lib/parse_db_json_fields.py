#!/usr/bin/env python3
# Parse DB JSON fields
# Usage: echo '{"mdb_id":1,"db_type":"MySQL",...}' | python3 parse_db_json_fields.py
# Output: TSV format - mdb_id<TAB>db_type<TAB>db_name<TAB>...

import sys
import json

try:
    obj = json.load(sys.stdin)
    
    # Output all fields as TSV
    fields = [
        str(obj.get('mdb_id', '')),
        obj.get('db_type', ''),
        obj.get('db_name', ''),
        obj.get('db_host', ''),
        str(obj.get('db_port', '')),
        obj.get('db_user', ''),
        obj.get('db_password', ''),
        obj.get('db_database', ''),
        str(obj.get('http_check_enabled', 0)),
        obj.get('http_check_url', ''),
        obj.get('http_check_method', 'GET'),
        str(obj.get('http_check_timeout', 10)),
        obj.get('http_check_expected_code', '200')
    ]
    
    print('\t'.join(fields))
except:
    sys.exit(1)
