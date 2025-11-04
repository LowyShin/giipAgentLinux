#!/usr/bin/env python3
"""
Database Query Helper for GIIP Agent
Supports MSSQL and Oracle connections using Python libraries
"""

import argparse
import sys
import os

def execute_mssql_query(args):
    """Execute MSSQL query using pyodbc"""
    try:
        import pyodbc
    except ImportError:
        print("Error: pyodbc not installed. Run: pip3 install pyodbc", file=sys.stderr)
        sys.exit(1)
    
    # Connection string
    conn_str = (
        f'DRIVER={{ODBC Driver 17 for SQL Server}};'
        f'SERVER={args.host},{args.port};'
        f'DATABASE={args.database};'
        f'UID={args.user};'
        f'PWD={args.password};'
        f'Connection Timeout={args.timeout}'
    )
    
    try:
        conn = pyodbc.connect(conn_str, timeout=args.timeout)
        cursor = conn.cursor()
        cursor.execute(args.query)
        
        # Open output file
        with open(args.output, 'w', encoding='utf-8') as f:
            # Check if there are results (SELECT query)
            if cursor.description:
                # Write column headers
                columns = [column[0] for column in cursor.description]
                f.write('\t'.join(columns) + '\n')
                
                # Write data rows
                row_count = 0
                for row in cursor:
                    f.write('\t'.join(str(x) if x is not None else '' for x in row) + '\n')
                    row_count += 1
                
                print(f"Query executed successfully: {row_count} rows returned", file=sys.stderr)
            else:
                # Non-SELECT query (INSERT, UPDATE, DELETE, etc.)
                f.write(f"Query executed successfully. Rows affected: {cursor.rowcount}\n")
                print(f"Query executed successfully. Rows affected: {cursor.rowcount}", file=sys.stderr)
        
        conn.close()
        sys.exit(0)
        
    except pyodbc.Error as e:
        print(f"MSSQL Error: {e}", file=sys.stderr)
        # Write error to output file
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(f"Error: {e}\n")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(f"Error: {e}\n")
        sys.exit(1)

def execute_oracle_query(args):
    """Execute Oracle query using cx_Oracle"""
    try:
        import cx_Oracle
    except ImportError:
        print("Error: cx_Oracle not installed. Run: pip3 install cx_Oracle", file=sys.stderr)
        print("Also ensure Oracle Instant Client is installed", file=sys.stderr)
        sys.exit(1)
    
    # Create DSN
    if args.instance:
        # Service name
        dsn = cx_Oracle.makedsn(args.host, args.port, service_name=args.instance)
    else:
        print("Error: Oracle instance/service name is required", file=sys.stderr)
        sys.exit(1)
    
    try:
        conn = cx_Oracle.connect(user=args.user, password=args.password, dsn=dsn)
        cursor = conn.cursor()
        cursor.execute(args.query)
        
        # Open output file
        with open(args.output, 'w', encoding='utf-8') as f:
            # Check if there are results (SELECT query)
            if cursor.description:
                # Write column headers
                columns = [desc[0] for desc in cursor.description]
                f.write('\t'.join(columns) + '\n')
                
                # Write data rows
                row_count = 0
                for row in cursor:
                    f.write('\t'.join(str(x) if x is not None else '' for x in row) + '\n')
                    row_count += 1
                
                print(f"Query executed successfully: {row_count} rows returned", file=sys.stderr)
            else:
                # Non-SELECT query
                conn.commit()
                f.write(f"Query executed successfully. Rows affected: {cursor.rowcount}\n")
                print(f"Query executed successfully. Rows affected: {cursor.rowcount}", file=sys.stderr)
        
        conn.close()
        sys.exit(0)
        
    except cx_Oracle.Error as e:
        error, = e.args
        print(f"Oracle Error: {error.message}", file=sys.stderr)
        # Write error to output file
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(f"Error: {error.message}\n")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(f"Error: {e}\n")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(
        description='Database Query Helper for GIIP Agent',
        epilog='Supports MSSQL (pyodbc) and Oracle (cx_Oracle)'
    )
    
    parser.add_argument('--type', required=True, choices=['mssql', 'oracle'],
                        help='Database type')
    parser.add_argument('--host', required=True,
                        help='Database host')
    parser.add_argument('--port', required=True, type=int,
                        help='Database port')
    parser.add_argument('--user', required=True,
                        help='Database user')
    parser.add_argument('--password', required=True,
                        help='Database password')
    parser.add_argument('--database',
                        help='Database name (MSSQL only)')
    parser.add_argument('--instance',
                        help='Instance/Service name (Oracle only)')
    parser.add_argument('--query', required=True,
                        help='SQL query to execute')
    parser.add_argument('--output', required=True,
                        help='Output file path')
    parser.add_argument('--timeout', type=int, default=30,
                        help='Query timeout in seconds (default: 30)')
    
    args = parser.parse_args()
    
    # Validate database-specific arguments
    if args.type == 'mssql' and not args.database:
        print("Error: --database is required for MSSQL", file=sys.stderr)
        sys.exit(1)
    
    if args.type == 'oracle' and not args.instance:
        print("Error: --instance is required for Oracle", file=sys.stderr)
        sys.exit(1)
    
    # Execute query
    if args.type == 'mssql':
        execute_mssql_query(args)
    elif args.type == 'oracle':
        execute_oracle_query(args)

if __name__ == '__main__':
    main()
