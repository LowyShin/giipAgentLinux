# DPA Upload Troubleshooting Guide

## 문제 해결 가이드

### 1. 새로운 디버깅 스크립트 사용

기존 스크립트 대신 개선된 버전을 사용하세요:

```bash
cd /home/shinh/scripts/p-cnsldb01m/giipAgentLinux/giipscripts
chmod +x run_dpa_upload_debug.sh
./run_dpa_upload_debug.sh
```

### 2. 로그 확인

스크립트 실행 후 생성되는 로그 파일을 확인:

```bash
ls -lh dpa_upload_*.log
tail -100 dpa_upload_*.log
```

### 3. 주요 실패 원인 및 해결 방법

#### 원인 1: Azure Function 타임아웃
**증상:**
```
[ERROR] curl failed with exit code 28
[ERROR] Operation timeout after 60s
```

**해결방법:**
```bash
# 타임아웃 시간 늘리기 (초 단위)
export CURL_TIMEOUT=120
./run_dpa_upload_debug.sh
```

또는 SQL 쿼리에 LIMIT 추가:
```sql
-- giip-dpa.sql 파일 수정
SELECT ... FROM ... LIMIT 1000;
```

#### 원인 2: Config 파일 경로 문제
**증상:**
```
[ERROR] giipAgent.cnf not found in expected locations
[ERROR] Config file does not exist: /path/to/giipAgent.cnf
そのようなファイルやディレクトリはありません
```

**해결방법:**

**옵션 A: 환경변수로 경로 지정**
```bash
export CONFIG_FILE="/home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipAgent.cnf"
./run_dpa_upload_debug.sh
```

**옵션 B: 심볼릭 링크 생성**
```bash
cd /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts
ln -s ../giipAgent.cnf .
# 또는 절대 경로로
ln -s /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipAgent.cnf .
```

**옵션 C: Config 파일 복사**
```bash
cp /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipAgent.cnf \
   /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts/
```

**파일 위치 확인:**
```bash
find /home/shinh -name "giipAgent.cnf" 2>/dev/null
ls -la /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipAgent.cnf
```

#### 원인 3: 인증 실패
**증상:**
```
[ERROR] KVS upload failed: RstVal=401
```

**해결방법:**
giipAgent.cnf 파일 확인:
```bash
cd /home/shinh/scripts/p-cnsldb01m/giipAgentLinux
cat giipAgent.cnf | grep -E 'apiaddrv2|UserToken|sk'
```

올바른 형식:
```ini
apiaddrv2=https://your-function-app.azurewebsites.net/api/giipApiSk2
apiaddrcode=your-function-key-here
UserToken=your-user-token-here
```

#### 원인 4: 네트워크 연결 문제
**증상:**
```
[ERROR] curl failed with exit code 6
[ERROR] Could not resolve host
```

**해결방법:**
```bash
# DNS 및 네트워크 확인
ping your-function-app.azurewebsites.net
nslookup your-function-app.azurewebsites.net

# Azure endpoint 직접 테스트
curl -v "https://your-function-app.azurewebsites.net/api/giipApiSk2?code=xxx"
```

#### 원인 5: MySQL 연결 실패
**증상:**
```
[ERROR] Cannot connect to MySQL server
```

**해결방법:**
```bash
# MySQL 연결 테스트
mysql -h p-cnsldb01m -u admin -p'I,FtEV=8' -P 3306 -D counseling -e "SELECT 1;"

# MySQL 서비스 상태 확인
sudo systemctl status mysql
```

#### 원인 6: 데이터 크기 문제
**증상:**
- JSON 파일이 1MB 이상
- 타임아웃 발생

**해결방법:**

**옵션 A: SQL 쿼리 최적화**
```sql
-- TOP N 또는 최근 데이터만 가져오기
SELECT TOP 500 * FROM ...
WHERE start_time > DATEADD(hour, -1, GETDATE())
```

**옵션 B: 배치 업로드**
```bash
# dpa.json을 여러 파일로 분할
jq -c '.[:500]' dpa.json > dpa_part1.json
jq -c '.[500:1000]' dpa.json > dpa_part2.json

# 각각 업로드
sh kvsput.sh dpa_part1.json sqlnetinv
sh kvsput.sh dpa_part2.json sqlnetinv
```

### 4. 수동 테스트

각 단계를 개별적으로 테스트:

```bash
# Step 1: SQL → JSON 변환만 테스트
sh mysql_rst2json.sh \
  --sql-file giip-dpa.sql \
  --host p-cnsldb01m \
  --user admin \
  --port 3306 \
  --database counseling \
  --out dpa_test.json

# JSON 파일 확인
jq '.' dpa_test.json | head -50
jq '. | length' dpa_test.json

# Step 2: KVS 업로드만 테스트 (작은 데이터로)
jq -c '.[:10]' dpa_test.json > dpa_small.json
sh kvsput.sh dpa_small.json sqlnetinv
```

### 5. Azure Function 로그 확인

Azure Portal에서 Function App 로그 확인:
1. Azure Portal → Function Apps → [your-function-app]
2. Monitor → Logs
3. Application Insights → Logs

실패한 요청 쿼리:
```kusto
requests
| where timestamp > ago(1h)
| where success == false
| project timestamp, name, resultCode, duration, customDimensions
| order by timestamp desc
```

### 6. 크론잡 설정 확인

만약 cron으로 실행 중이라면:

```bash
# 크론 로그 확인
sudo tail -f /var/log/cron
sudo tail -f /var/log/syslog | grep CRON

# 크론잡 목록
crontab -l

# 크론 환경에서 테스트
# (크론은 PATH와 환경변수가 다름)
env -i HOME=$HOME /bin/bash -l -c "cd /home/shinh/scripts/p-cnsldb01m/giipAgentLinux/giipscripts && ./run_dpa_upload_debug.sh"
```

### 7. 긴급 해결 방법

임시로 데이터를 로컬에만 저장:

```bash
# giipAgent.cnf에 추가
Enabled=false

# 이렇게 하면 JSON만 생성되고 업로드는 건너뜀
./run_dpa_upload_debug.sh

# JSON 파일들은 backup/ 폴더에 보관됨
ls -lh backup/
```

### 8. 모니터링 설정

```bash
# 정기적으로 로그 체크하는 스크립트 생성
cat > check_dpa_status.sh <<'EOF'
#!/bin/bash
latest_log=$(ls -t dpa_upload_*.log 2>/dev/null | head -1)
if [ -n "$latest_log" ]; then
  echo "=== Latest DPA Upload Log ==="
  echo "File: $latest_log"
  echo "Time: $(stat -c %y "$latest_log" 2>/dev/null || stat -f %Sm "$latest_log")"
  echo ""
  if grep -q "ERROR" "$latest_log"; then
    echo "❌ Errors found:"
    grep "ERROR" "$latest_log"
  else
    echo "✓ No errors"
  fi
  echo ""
  grep "records uploaded" "$latest_log" || echo "Upload status unknown"
else
  echo "No log files found"
fi
EOF

chmod +x check_dpa_status.sh
```

### 9. 연락처

문제가 계속되면 다음 정보와 함께 문의:
- 최신 로그 파일 (`dpa_upload_*.log`)
- giipAgent.cnf 내용 (민감 정보 제외)
- JSON 파일 크기 (`ls -lh dpa.json`)
- 레코드 수 (`jq '. | length' dpa.json`)

## 체크리스트

실패 시 다음을 순서대로 확인:

- [ ] MySQL 서버 연결 가능
- [ ] giip-dpa.sql 파일 존재
- [ ] dpa.json 파일 생성됨
- [ ] dpa.json이 유효한 JSON 형식
- [ ] giipAgent.cnf에 올바른 endpoint와 token
- [ ] Azure Function이 정상 작동 중
- [ ] 네트워크 연결 정상
- [ ] 데이터 크기가 적절함 (< 1MB 권장)
- [ ] 타임아웃 설정이 충분함

## 성능 최적화

### SQL 쿼리 최적화
```sql
-- 인덱스 사용 확인
EXPLAIN SELECT ... FROM ...;

-- 필요한 컬럼만 선택
SELECT col1, col2, col3 
FROM table 
WHERE timestamp > NOW() - INTERVAL 1 HOUR
LIMIT 1000;
```

### JSON 크기 줄이기
```bash
# 불필요한 필드 제거
jq '[.[] | {sql_server, spid, cpu_time, query_text}]' dpa.json > dpa_optimized.json
```

### 압축 전송 (향후 개선)
```bash
# gzip 압축 후 전송 (API에서 지원 시)
gzip -c dpa.json | base64 > dpa.json.gz.b64
```
