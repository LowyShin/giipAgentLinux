# 네트워크 수집 테스트 가이드

## 변경 사항 요약

### 1. 문제점
- **원인**: `ip -o link show | awk '{print $2}'`가 "eth0:" (콜론 포함) 추출
- **결과**: `ip addr show "eth0:"` 실패 → IPv4/IPv6 비어있음 → network array 비어있음

### 2. 해결책
```bash
# ❌ 이전 (잘못된 파싱)
ip -o link show | awk '{print $2}' | tr -d ':'

# ✅ 수정 (정확한 파싱)
ip -o link show | awk -F': ' '{print $2}'
```

### 3. 추가 개선
- OS별 분기 처리 (CentOS 6 ifconfig 지원)
- /sys/class/net fallback
- KVS 업로드 스크립트 추가

---

## 서버 테스트 방법

### Step 1: Git Pull (자동 실행됨)
```bash
# cron이 1분마다 실행하므로 대기
# 또는 수동 실행:
cd /opt/giipAgentLinux
bash git-auto-sync.sh
```

**확인**:
```bash
# 최신 커밋 확인
git log --oneline -1
# 출력: 67c3ecf Feature: OS-aware network collection with KVS upload
```

### Step 2: 자동 수집 대기 (1분 이내)
```bash
# giip-auto-discover.sh가 자동 실행됨 (git pull 후)
# 로그 확인:
tail -f /var/log/giip-auto-discover.log
```

### Step 3: 결과 확인

#### 3-1. JSON 파일 확인
```bash
# 전체 JSON
cat /var/log/giip-discovery-latest.json | jq .

# 네트워크 부분만
cat /var/log/giip-discovery-latest.json | jq .network

# 예상 출력:
# [
#   {
#     "name": "eth0",
#     "ipv4": "10.2.0.5",
#     "ipv6": null,
#     "mac": "00:22:48:0e:a4:93"
#   }
# ]
```

#### 3-2. 네트워크 로그 확인
```bash
cat /opt/giipAgentLinux/tmp/network.log

# 예상 출력:
# ========================================
# Network Discovery Log
# Date: 2025-10-30 16:30:45
# ========================================
# 
# Network Interfaces Found: 1
# 
# Interface: eth0
#   IPv4: 10.2.0.5
#   IPv6: <empty>
#   MAC:  00:22:48:0e:a4:93
```

#### 3-3. 데이터베이스 확인 (Windows에서)
```powershell
# PowerShell에서 실행
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb
.\check_network_data_detail.ps1

# 예상 결과:
# SNsn     LSsn  InterfaceName IPv4       IPv6 MAC               RegisterDate
# 1917625  71174 eth0          10.2.0.5   NULL 00:22:48:0e:a4:93 2025/10/30 16:30:50
```

---

## 디버그 도구 사용

### 도구 1: debug-network.sh (상세 분석)
```bash
cd /opt/giipAgentLinux/giipscripts
bash debug-network.sh

# 이 스크립트는:
# - 각 명령의 raw 출력 표시
# - 파싱 단계별 결과 표시
# - 최종 JSON 생성 과정 표시
```

**출력 예시**:
```
1. Testing 'ip -o link show' command:
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...

2. Filtering out loopback:
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...

3. Extracting interface names:
eth0

4. Testing eth0 specifically:
Interface: eth0
  IPv4 command: ip -4 addr show eth0 | grep inet
    inet 10.2.0.5/16 brd 10.2.255.255 scope global eth0
  IPv4 result:
    ipv4='10.2.0.5'
  
  MAC result:
    mac='00:22:48:0e:a4:93'

6. Final network_json:
network_json='{"name":"eth0","ipv4":"10.2.0.5","mac":"00:22:48:0e:a4:93"}'

Formatted:
[{"name":"eth0","ipv4":"10.2.0.5","mac":"00:22:48:0e:a4:93"}]
```

### 도구 2: collect-network-by-os.sh (KVS 업로드)
```bash
cd /opt/giipAgentLinux/giipscripts
bash collect-network-by-os.sh

# 이 스크립트는:
# - OS 감지 및 표시
# - 네트워크 데이터 수집
# - /tmp/network-info.json 저장
# - kvsput.sh로 KVS 업로드 (kfactor: netdiag)
```

**출력 예시**:
```
==========================================
Network Collection by OS
==========================================
[INFO] Detected OS: Ubuntu 20.04.6 LTS (ID: ubuntu, Version: 20.04)
[INFO] Using Debian/Ubuntu network collection method

[INFO] Network data collected to: /tmp/network-info.json
[INFO] Preview:
{
  "timestamp": "2025-10-30T16:30:45+09:00",
  "hostname": "cctrank03",
  "os": {
    "id": "ubuntu",
    "version": "20.04",
    "name": "Ubuntu 20.04.6 LTS"
  },
  "network": [
    {
      "name": "eth0",
      "ipv4": "10.2.0.5",
      "ipv6": null,
      "mac": "00:22:48:0e:a4:93",
      "state": "UP",
      "mtu": 1500
    }
  ]
}

[INFO] Uploading to KVS with kfactor 'netdiag'...
[DIAG] Endpoint: https://...
[DIAG] KVSP text: KVSPut lssn cctrank03 netdiag
[INFO] KVS upload result: {"status":"success"}
[SUCCESS] Upload completed
```

---

## KVS 데이터 확인

### 데이터베이스에서 확인
```sql
-- 최신 netdiag 데이터 확인
SELECT TOP 1
    KVSsn,
    LSsn,
    KFactor,
    LEFT(KData, 500) AS Preview,
    kRegdt
FROM tKVS
WHERE KFactor = 'netdiag'
ORDER BY kRegdt DESC;

-- 전체 JSON 확인
SELECT KData FROM tKVS WHERE KVSsn = <위에서 나온 KVSsn>;
```

### PowerShell로 확인
```powershell
# tKVS 쿼리
$query = @"
SELECT TOP 1 KData 
FROM tKVS 
WHERE KFactor = 'netdiag' 
  AND LSsn = (SELECT LSsn FROM tLSvr WHERE LCode = 'cctrank03')
ORDER BY kRegdt DESC
"@

$config = Get-Content "c:\Users\lowys\Downloads\projects\giipprj\giipdb\mgmt\dbconfig.json" | ConvertFrom-Json
$result = Invoke-Sqlcmd -ServerInstance $config.server -Database $config.database -Query $query

# JSON 예쁘게 출력
$result.KData | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

---

## 문제 해결

### 문제 1: network array가 여전히 비어있음
```bash
# 1. 명령 사용 가능 여부 확인
command -v ip && echo "✓ ip available" || echo "✗ ip not found"
command -v ifconfig && echo "✓ ifconfig available" || echo "✗ ifconfig not found"

# 2. 인터페이스 목록 확인
ip -o link show | awk -F': ' '{print $2}'

# 3. eth0 IP 확인
ip -4 addr show eth0 | grep "inet "

# 4. debug-network.sh 실행
bash /opt/giipAgentLinux/giipscripts/debug-network.sh
```

### 문제 2: KVS 업로드 실패
```bash
# kvsput.sh 확인
ls -l /opt/giipAgentLinux/giipscripts/kvsput.sh

# giipAgent.cnf 확인
cat /opt/giipAgentLinux/giipAgent.cnf | grep -E 'Endpoint|UserToken|Enabled'

# 수동 업로드 테스트
echo '{"test":"value"}' > /tmp/test.json
bash /opt/giipAgentLinux/giipscripts/kvsput.sh /tmp/test.json testfactor
```

### 문제 3: Git pull이 안됨
```bash
# 수동 pull
cd /opt/giipAgentLinux
git pull origin master

# pull 상태 확인
git log --oneline -5

# 최신 커밋이 67c3ecf인지 확인
```

---

## 성공 기준

### ✅ 네트워크 수집 성공
```bash
# 1. JSON에 network 데이터 있음
cat /var/log/giip-discovery-latest.json | jq .network
# → [{"name":"eth0","ipv4":"10.2.0.5",...}]

# 2. 로그에 인터페이스 정보 있음
grep "Interface:" /opt/giipAgentLinux/tmp/network.log
# → Interface: eth0

# 3. DB에 IPv4 저장됨
# check_network_data_detail.ps1 결과에서 IPv4 컬럼이 NULL이 아님
```

### ✅ Web UI 표시 성공
```
http://your-web-ui/ko/infrastructure-detail?lssn=71174

Network 탭:
┌──────────┬────────────┬──────────────────────┬─────────────────────┐
│ Name     │ IPv4       │ MAC                  │ Registered          │
├──────────┼────────────┼──────────────────────┼─────────────────────┤
│ eth0     │ 10.2.0.5   │ 00:22:48:0e:a4:93    │ 2025-10-30 16:30:50 │
└──────────┴────────────┴──────────────────────┴─────────────────────┘
```

---

## 관련 문서
- `docs/KVSPUT_USAGE_GUIDE.md` - kvsput.sh 사용법
- `docs/NETWORK_COLLECTION_BY_OS.md` - OS별 네트워크 수집 상세
- `docs/SQLNETINV_DATA_FLOW.md` - 네트워크 데이터 전체 흐름

## 지원 요청
문제 발생 시 다음 정보와 함께 문의:

```bash
# 진단 정보 수집
{
    echo "=== System Info ==="
    uname -a
    cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null
    
    echo -e "\n=== Git Version ==="
    cd /opt/giipAgentLinux && git log --oneline -1
    
    echo -e "\n=== Network Commands ==="
    command -v ip && echo "ip: YES" || echo "ip: NO"
    command -v ifconfig && echo "ifconfig: YES" || echo "ifconfig: NO"
    
    echo -e "\n=== Interface List ==="
    ip -o link show 2>/dev/null || ifconfig -s 2>/dev/null
    
    echo -e "\n=== Latest JSON ==="
    cat /var/log/giip-discovery-latest.json | jq .network 2>/dev/null || echo "jq not available"
    
    echo -e "\n=== Network Log ==="
    cat /opt/giipAgentLinux/tmp/network.log 2>/dev/null || echo "Log not found"
    
} | tee /tmp/giip-diagnostic.txt

# 진단 파일 전송
cat /tmp/giip-diagnostic.txt
```

---

**작성일**: 2025-10-30  
**버전**: 1.0.0  
**커밋**: 67c3ecf
