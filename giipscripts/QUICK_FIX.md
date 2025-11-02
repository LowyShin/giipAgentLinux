# DPA 업로드 실패 빠른 해결

## 현재 에러

```
[ERROR] Missing config: Endpoint
そのようなファイルやディレクトリはありません
```

## 즉시 해결 방법

### 1단계: Config 파일 위치 확인

```bash
# 현재 서버에서 실행
find /home/shinh/scripts -name "giipAgent.cnf" 2>/dev/null
```

결과 예시:
```
/home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipAgent.cnf
```

### 2단계: 환경변수 설정하고 실행

```bash
cd /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts

# Config 파일 경로 설정
export CONFIG_FILE="/home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipAgent.cnf"

# MySQL 비밀번호 설정
export MYSQL_PWD='I,FtEV=8'

# DPA 업로드 실행
sh mysql_rst2json.sh \
  --sql-file giip-dpa.sql \
  --host p-cnsldb03m \
  --user admin \
  --port 3306 \
  --database counseling \
  --out dpa.json

sh kvsput.sh dpa.json sqlnetinv
```

### 3단계: 자동화 (크론잡 수정)

기존 크론잡을 수정하여 환경변수 포함:

```bash
crontab -e
```

다음과 같이 수정:
```bash
# Before (실패함)
0 * * * * cd /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts && sh mysql_rst2json.sh ...

# After (성공)
0 * * * * export CONFIG_FILE="/home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipAgent.cnf" && export MYSQL_PWD='I,FtEV=8' && cd /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts && sh mysql_rst2json.sh --sql-file giip-dpa.sql --host p-cnsldb03m --user admin --port 3306 --database counseling --out dpa.json && sh kvsput.sh dpa.json sqlnetinv
```

또는 래퍼 스크립트 생성:

```bash
cat > /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts/run_dpa.sh <<'EOF'
#!/bin/bash
export CONFIG_FILE="/home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipAgent.cnf"
export MYSQL_PWD='I,FtEV=8'

cd /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts

sh mysql_rst2json.sh \
  --sql-file giip-dpa.sql \
  --host p-cnsldb03m \
  --user admin \
  --port 3306 \
  --database counseling \
  --out dpa.json

sh kvsput.sh dpa.json sqlnetinv
EOF

chmod +x /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts/run_dpa.sh
```

크론잡을 간단하게:
```bash
0 * * * * /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts/run_dpa.sh >> /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts/dpa_cron.log 2>&1
```

## 대안: 심볼릭 링크

Config 파일 심볼릭 링크 생성:

```bash
cd /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipscripts
ln -sf ../giipAgent.cnf giipAgent.cnf

# 확인
ls -la giipAgent.cnf
# giipAgent.cnf -> ../giipAgent.cnf
```

이렇게 하면 환경변수 없이도 자동으로 찾음:
```bash
sh kvsput.sh dpa.json sqlnetinv
```

## 스크립트 개선사항

새 버전의 `kvsput.sh`는:
- ✅ Config 파일 존재 여부 확인 후 명확한 에러 메시지
- ✅ 여러 경로 자동 탐색 (환경변수 → 상위 디렉토리 → /opt → /home/giip → /root)
- ✅ 타임아웃 설정 (기본 60초, CURL_TIMEOUT 환경변수로 조정 가능)
- ✅ 페이로드 크기 경고 (>1MB 시)
- ✅ 상세한 curl 에러 진단

## 테스트

```bash
# 수동 테스트
export CONFIG_FILE="/home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipAgent.cnf"
sh kvsput.sh dpa.json sqlnetinv

# 성공 시 출력:
# [INFO] Using config: /home/shinh/scripts/p-cnsldb03m/giipAgentLinux/giipAgent.cnf
# [INFO] Uploading to KVS: kFactor=sqlnetinv, kKey=p-cnsldb03m
# [INFO] Payload size: 12345 bytes
# [INFO] Sending request to: https://...
# [INFO] Timeout: 60s
# [SUCCESS] KVS uploaded successfully
```

## 다른 서버들도 확인

같은 문제가 있을 수 있는 다른 서버들:

```bash
# 다른 서버에서도 동일하게 처리
for server in p-cnsldb01m p-cnsldb02m p-cnsldb03m; do
  echo "Checking $server..."
  ssh $server "cd /home/shinh/scripts/$server/giipAgentLinux/giipscripts && ln -sf ../giipAgent.cnf giipAgent.cnf"
done
```

## 문제가 계속되면

1. Config 파일 내용 확인:
```bash
cat $CONFIG_FILE | grep -E "apiaddrv2|UserToken|apiaddrcode"
```

2. 필수 항목이 있는지 확인:
   - `apiaddrv2` 또는 `Endpoint`
   - `UserToken` 또는 `sk`
   - `apiaddrcode` 또는 `FunctionCode` (선택사항)

3. 자세한 로그로 다시 실행:
```bash
bash -x kvsput.sh dpa.json sqlnetinv 2>&1 | tee debug.log
```
