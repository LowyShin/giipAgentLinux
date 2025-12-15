# KVS Spec for giipAgentLinux (`kvs.sh`)

## 1. Overview
`kvs.sh` is a core library for logging operations and data storage in the `giipAgentLinux` system. It interacts with the backend `KVSPut` API to store Key-Value pairs.

**File Path**: `giipAgentLinux/lib/kvs.sh`
**Main Function**: `kvs_put()`

## 2. API Contract (Critical Rules)
The `KVSPut` API follows a strict contract defined in `giipapi_rules.md` (implied).

### 2.1. Request Parameters
When invoking the API (e.g., via `wget` or `curl`), the POST body MUST contain:

1.  **`token`**: The Security Key (`sk`).
2.  **`text`**: A string listing the parameter names required by the SP logic.
    *   **Value**: `"KVSPut kType kKey kFactor"`
    *   **Purpose**: Tells the API Gateway/SP which keys to look for in the `jsondata`.
3.  **`jsondata`**: A JSON string containing the actual values.

### 2.2. `jsondata` Structure
The `jsondata` MUST form a valid JSON object with the following keys:

```json
{
  "kType": "string",   // Key Type (e.g., "lssn", "database")
  "kKey": "string",    // Key Value (e.g., "71199", "8")
  "kFactor": "string", // Factor Name (e.g., "giipagent", "db_connections")
  "kValue": RawData    // The payload to store.
}
```

#### kValue Handling
*   **Raw Data**: `kValue` can be ANY valid JSON data type (Object, Array, String, Number, Boolean, Null).
*   **No Double Encoding**: The content of `kValue` is embedded directly into the `jsondata` JSON structure. It is NOT passed as a separate string-escaped parameter.
*   **Example**:
    ```bash
    local kvalue_json='{"status":"ok", "cpu":80}'
    local jsondata="{\"kType\":\"...\", ..., \"kValue\":${kvalue_json}}"
    ```
    Resulting `jsondata`:
    ```json
    { "kType": "...", ..., "kValue": {"status":"ok", "cpu":80} }
    ```

## 3. Function Logic (`kvs_put`)

### 3.1. Signature
```bash
kvs_put "kType" "kKey" "kFactor" "kValue_json"
```

### 3.2. Validation
- Checks for `sk` and `apiaddrv2` variables.
- If `kValue_json` is empty/null, it defaults to `{}` (empty object).

### 3.3. Execution Flow
1.  Constructs `text` = `"KVSPut kType kKey kFactor"`.
2.  Constructs `jsondata` dictionary including `kType`, `kKey`, `kFactor`, and `kValue`.
3.  **URL Encodes** `text`, `token`, and `jsondata` individually (using `jq -sRr @uri`).
4.  Sends POST request to `apiaddrv2`.
5.  Logs success/failure to stdout/stderr and optional log file.

## 4. Usage Examples

### 4.1. Storing Agent Logs
```bash
kvs_put "lssn" "$lssn" "giipagent" "{\"event\":\"startup\"}"
```

### 4.2. Storing DB Connections (Equivalent Logic)
```bash
kvs_put "database" "$mdb_id" "db_connections" "[{\"ip\":\"10.0.0.1\"}, ...]"
```

## 5. Constraints
- **Do Not Modify**: Review the warning header in `kvs.sh`. Do not change the JSON structure or text parameter without authorization.
- **Dependency**: Requires `jq` for robust URL encoding.
