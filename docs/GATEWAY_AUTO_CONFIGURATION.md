# Gateway Server Auto-Configuration via CQE

## 🎯 목표

Gateway 서버에서 수동 설정 작업을 최소화하고, 웹 UI에서 Gateway 서버를 등록하면 CQE를 통해 자동으로 필요한 설정과 스크립트를 배포하는 구조로 개선

## 📋 현재 구조 (Before)

### 문제점
1. **수동 설정 필요**
   - `giipAgentGateway.cnf` 수동 작성
   - `giipAgentGateway_servers.csv` 수동 관리
   - SSH 키 수동 배포
   - 원격 서버별 스크립트 수동 설치

2. **관리 복잡성**
   - 여러 파일 동기화 필요
   - 서버 추가/삭제 시 파일 수정
   - 설정 변경 사항 추적 어려움

3. **에러 발생 가능성**
   - CSV 파일 문법 오류
   - SSH 키 경로 오류
   - 원격 서버 접속 실패 시 수동 개입 필요

## 🚀 개선 구조 (After)

### 핵심 컨셉
```
웹 UI → Gateway 서버 등록 (is_gateway=1) → CQE로 설정 스크립트 배포
                                                    ↓
                                         Gateway 설정 자동화
                                                    ↓
                                         원격 서버 목록 자동 동기화
                                                    ↓
                                         실행 결과 자동 수집
```

### 1. 데이터베이스 스키마 변경

#### `tLSvr` 테이블 - Gateway 서버 식별 추가

```sql
ALTER TABLE tLSvr ADD 
    is_gateway bit DEFAULT 0,              -- Gateway 서버 여부
    gateway_lssn int NULL,                 -- 소속된 Gateway 서버 (원격 서버용)
    gateway_ssh_host varchar(255) NULL,    -- SSH 접속 호스트
    gateway_ssh_port int DEFAULT 22,       -- SSH 접속 포트
    gateway_ssh_user varchar(100) NULL,    -- SSH 사용자
    gateway_ssh_key_path varchar(500) NULL -- SSH 키 경로 (Gateway 서버 기준)
```

**인덱스 추가**:
```sql
CREATE INDEX IX_tLSvr_Gateway ON tLSvr(is_gateway, LSSN) 
WHERE is_gateway = 1

CREATE INDEX IX_tLSvr_GatewayServers ON tLSvr(gateway_lssn, LSSN)
WHERE gateway_lssn IS NOT NULL
```

---

### 2. 새로운 Stored Procedures

#### A. Gateway 서버 목록 조회
```sql
CREATE PROCEDURE pGatewayServerList
    @csn int
AS
BEGIN
    SET NOCOUNT ON
    
    -- Gateway 서버 목록
    SELECT 
        ls.LSSN,
        ls.LSHostname,
        ls.LSIP,
        ls.LSOSVer,
        ls.LSRegdt,
        ls.LSChkdt,
        COUNT(remote.LSSN) AS remote_server_count,
        MAX(remote.LSChkdt) AS last_remote_check
    FROM tLSvr ls WITH(NOLOCK)
    LEFT JOIN tLSvr remote WITH(NOLOCK) 
        ON remote.gateway_lssn = ls.LSSN 
        AND remote.csn = ls.csn
    WHERE ls.csn = @csn 
        AND ls.is_gateway = 1
    GROUP BY ls.LSSN, ls.LSHostname, ls.LSIP, ls.LSOSVer, ls.LSRegdt, ls.LSChkdt
    ORDER BY ls.LSHostname
    
    -- 응답 코드
    SELECT 200 AS RstVal, N'조회 성공' AS RstMsg
END
```

#### B. Gateway에 연결된 원격 서버 목록
```sql
CREATE PROCEDURE pGatewayRemoteServerList
    @gateway_lssn int
AS
BEGIN
    SET NOCOUNT ON
    
    SELECT 
        ls.LSSN,
        ls.LSHostname,
        ls.LSIP,
        ls.LSOSVer,
        ls.LSChkdt,
        ls.gateway_ssh_host,
        ls.gateway_ssh_port,
        ls.gateway_ssh_user,
        ls.gateway_ssh_key_path,
        CASE 
            WHEN DATEDIFF(MINUTE, ls.LSChkdt, GETDATE()) < 10 THEN N'정상'
            WHEN DATEDIFF(MINUTE, ls.LSChkdt, GETDATE()) < 60 THEN N'지연'
            ELSE N'오프라인'
        END AS status
    FROM tLSvr ls WITH(NOLOCK)
    WHERE ls.gateway_lssn = @gateway_lssn
    ORDER BY ls.LSHostname
    
    SELECT 200 AS RstVal, N'조회 성공' AS RstMsg
END
```

#### C. Gateway 서버 등록/수정
```sql
CREATE PROCEDURE pGatewayServerPut
    @lssn int,
    @is_gateway bit,
    @gateway_lssn int = NULL,
    @gateway_ssh_host varchar(255) = NULL,
    @gateway_ssh_port int = 22,
    @gateway_ssh_user varchar(100) = NULL,
    @gateway_ssh_key_path varchar(500) = NULL
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        BEGIN TRAN
        
        -- Gateway 서버로 설정
        IF @is_gateway = 1
        BEGIN
            UPDATE tLSvr 
            SET is_gateway = 1,
                gateway_lssn = NULL,  -- Gateway는 다른 Gateway에 속할 수 없음
                gateway_ssh_host = NULL,
                gateway_ssh_port = 22,
                gateway_ssh_user = NULL,
                gateway_ssh_key_path = NULL
            WHERE LSSN = @lssn
            
            -- Gateway 초기 설정 스크립트를 CQE 큐에 자동 등록
            -- pMgmtScriptQueforcebyCsn 호출하여 setup_gateway.sh 실행
            DECLARE @mssn_setup int
            SELECT @mssn_setup = msSn 
            FROM tMgmtScript 
            WHERE msName = 'setup_gateway_auto'
            
            IF @mssn_setup IS NOT NULL
            BEGIN
                -- 강제로 큐에 추가
                EXEC pMgmtScriptQueforcebyCsn 
                    @mssn = @mssn_setup,
                    @lssn = @lssn
            END
        END
        -- 원격 서버로 설정 (Gateway에 연결)
        ELSE IF @gateway_lssn IS NOT NULL
        BEGIN
            -- Gateway 서버 존재 확인
            IF NOT EXISTS(SELECT 1 FROM tLSvr WHERE LSSN = @gateway_lssn AND is_gateway = 1)
            BEGIN
                SELECT 404 AS RstVal, N'지정한 Gateway 서버가 존재하지 않습니다' AS RstMsg
                ROLLBACK TRAN
                RETURN
            END
            
            UPDATE tLSvr 
            SET is_gateway = 0,
                gateway_lssn = @gateway_lssn,
                gateway_ssh_host = @gateway_ssh_host,
                gateway_ssh_port = @gateway_ssh_port,
                gateway_ssh_user = @gateway_ssh_user,
                gateway_ssh_key_path = @gateway_ssh_key_path
            WHERE LSSN = @lssn
            
            -- Gateway 서버의 서버 목록 갱신 스크립트 실행
            DECLARE @mssn_refresh int
            SELECT @mssn_refresh = msSn 
            FROM tMgmtScript 
            WHERE msName = 'refresh_gateway_serverlist'
            
            IF @mssn_refresh IS NOT NULL
            BEGIN
                EXEC pMgmtScriptQueforcebyCsn 
                    @mssn = @mssn_refresh,
                    @lssn = @gateway_lssn
            END
        END
        
        COMMIT TRAN
        SELECT 200 AS RstVal, N'Gateway 설정이 완료되었습니다' AS RstMsg
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN
        SELECT 500 AS RstVal, ERROR_MESSAGE() AS RstMsg
    END CATCH
END
```

#### D. Gateway 서버 목록 CSV 생성
```sql
CREATE PROCEDURE pGatewayExportServerList
    @gateway_lssn int
AS
BEGIN
    SET NOCOUNT ON
    
    -- CSV 형식으로 서버 목록 반환
    SELECT 
        ls.LSHostname + ',' +
        CAST(ls.LSSN AS varchar) + ',' +
        ISNULL(ls.gateway_ssh_host, ls.LSIP) + ',' +
        ISNULL(ls.gateway_ssh_user, 'root') + ',' +
        CAST(ISNULL(ls.gateway_ssh_port, 22) AS varchar) + ',' +
        ISNULL(ls.gateway_ssh_key_path, '') + ',' +
        ISNULL(ls.LSOSVer, 'Linux') + ',1' AS csv_line
    FROM tLSvr ls WITH(NOLOCK)
    WHERE ls.gateway_lssn = @gateway_lssn
    ORDER BY ls.LSHostname
    
    SELECT 200 AS RstVal, N'CSV 생성 완료' AS RstMsg
END
```

---

### 3. 자동 설정 스크립트

#### A. Gateway 초기 설정 스크립트 (`setup_gateway_auto.sh`)

tMgmtScript에 등록할 내용:

```bash
#!/bin/bash
#
# Gateway Server Auto Setup Script
# 이 스크립트는 CQE를 통해 Gateway 서버에 자동으로 배포됩니다
#

set -e

INSTALL_DIR="/opt/giipAgentLinux"
CONFIG_FILE="$INSTALL_DIR/giipAgentGateway.cnf"
SERVERLIST_FILE="$INSTALL_DIR/giipAgentGateway_servers.csv"

echo "===== Gateway Server Auto Setup Started ====="

# 1. 설치 디렉토리 생성
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# 2. giipAgentLinux 레포지토리 클론 (없으면)
if [ ! -d "$INSTALL_DIR/.git" ]; then
    echo "Cloning giipAgentLinux repository..."
    git clone https://github.com/LowyShin/giipAgentLinux.git .
else
    echo "Repository already exists, pulling latest..."
    git pull
fi

# 3. Config 파일 생성 (환경변수에서 읽음)
cat > $CONFIG_FILE <<EOF
# Gateway Agent Configuration (Auto-generated)
sk="{{SK}}"
lssn={{LSSN}}
apiaddr="{{APIADDR}}"
apiaddrv2="{{APIADDRV2}}"
apiaddrcode="{{APIADDRCODE}}"
giipagentdelay="300"
serverlist_file="$SERVERLIST_FILE"
EOF

echo "Config file created: $CONFIG_FILE"

# 4. 서버 목록 파일 초기화 (API에서 가져옴)
echo "Fetching remote server list from API..."
curl -s -X POST "{{APIADDRV2}}" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'text=GatewayExportServerList lssn' \
    --data-urlencode "token={{SK}}" \
    --data-urlencode "jsondata={\"lssn\":{{LSSN}}}" \
    | jq -r '.data[].csv_line' > $SERVERLIST_FILE

if [ -s $SERVERLIST_FILE ]; then
    echo "Server list created: $SERVERLIST_FILE"
    cat $SERVERLIST_FILE
else
    echo "# hostname,lssn,ssh_host,ssh_user,ssh_port,ssh_key_path,os_info,enabled" > $SERVERLIST_FILE
    echo "# No remote servers configured yet" >> $SERVERLIST_FILE
fi

# 5. giipAgentGateway.sh 실행 권한 부여
chmod +x $INSTALL_DIR/giipAgentGateway.sh

# 6. Cron 등록 (5분마다 실행)
CRON_LINE="*/5 * * * * cd $INSTALL_DIR && bash giipAgentGateway.sh >> /var/log/giipAgentGateway.log 2>&1"
(crontab -l 2>/dev/null | grep -v "giipAgentGateway.sh"; echo "$CRON_LINE") | crontab -

echo "Cron job registered"

# 7. 로그 디렉토리 생성
mkdir -p /var/log/giip
touch /var/log/giipAgentGateway.log

# 8. SSH 키 디렉토리 생성
mkdir -p $INSTALL_DIR/ssh_keys
chmod 700 $INSTALL_DIR/ssh_keys

echo "===== Gateway Server Auto Setup Completed ====="
echo "Gateway is now ready to manage remote servers"
echo "Server list: $SERVERLIST_FILE"
echo "Config: $CONFIG_FILE"
echo "Log: /var/log/giipAgentGateway.log"

# 결과 반환 (KVS로 전송)
cat > /tmp/gateway_setup_result.json <<EOF
{
  "status": "success",
  "gateway_lssn": {{LSSN}},
  "config_file": "$CONFIG_FILE",
  "serverlist_file": "$SERVERLIST_FILE",
  "remote_servers": $(cat $SERVERLIST_FILE | grep -v "^#" | wc -l),
  "setup_time": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF

# KVS에 결과 업로드
if [ -f "$INSTALL_DIR/giipscripts/kvsput.sh" ]; then
    bash $INSTALL_DIR/giipscripts/kvsput.sh /tmp/gateway_setup_result.json "gateway_setup"
fi
```

**tMgmtScript 등록 SQL**:
```sql
INSERT INTO tMgmtScript (
    usn, msName, msDetail, msBody, msRegdt, 
    msType, category, timeout_seconds, enabled
) VALUES (
    1, 
    'setup_gateway_auto',
    'Gateway 서버 자동 설정 스크립트 - CQE를 통해 Gateway 서버 초기 설정',
    N'#!/bin/bash
    [위 스크립트 내용]',
    GETDATE(),
    'bash',
    'gateway',
    600,  -- 10분 타임아웃
    1
)
```

#### B. Gateway 서버 목록 갱신 스크립트 (`refresh_gateway_serverlist.sh`)

```bash
#!/bin/bash
#
# Refresh Gateway Server List
# Gateway 서버의 원격 서버 목록을 API에서 다시 가져옵니다
#

set -e

INSTALL_DIR="/opt/giipAgentLinux"
CONFIG_FILE="$INSTALL_DIR/giipAgentGateway.cnf"
SERVERLIST_FILE="$INSTALL_DIR/giipAgentGateway_servers.csv"

echo "===== Refreshing Gateway Server List ====="

# Config 파일에서 인증 정보 읽기
SK=$(grep 'sk=' $CONFIG_FILE | cut -d'"' -f2)
LSSN=$(grep 'lssn=' $CONFIG_FILE | cut -d'=' -f2)
APIADDRV2=$(grep 'apiaddrv2=' $CONFIG_FILE | cut -d'"' -f2)

# 서버 목록 백업
if [ -f "$SERVERLIST_FILE" ]; then
    cp $SERVERLIST_FILE ${SERVERLIST_FILE}.bak
    echo "Backup created: ${SERVERLIST_FILE}.bak"
fi

# API에서 최신 서버 목록 가져오기
echo "Fetching latest server list from API..."
curl -s -X POST "$APIADDRV2" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'text=GatewayExportServerList lssn' \
    --data-urlencode "token=$SK" \
    --data-urlencode "jsondata={\"lssn\":$LSSN}" \
    | jq -r '.data[].csv_line' > ${SERVERLIST_FILE}.new

# 파일 검증
if [ -s ${SERVERLIST_FILE}.new ]; then
    mv ${SERVERLIST_FILE}.new $SERVERLIST_FILE
    echo "Server list updated successfully"
    
    # 변경 사항 로그
    echo "Current servers:"
    cat $SERVERLIST_FILE | grep -v "^#"
    
    SERVER_COUNT=$(cat $SERVERLIST_FILE | grep -v "^#" | wc -l)
    echo "Total servers: $SERVER_COUNT"
else
    echo "Error: Failed to fetch server list"
    # 백업 복원
    if [ -f "${SERVERLIST_FILE}.bak" ]; then
        mv ${SERVERLIST_FILE}.bak $SERVERLIST_FILE
        echo "Restored from backup"
    fi
    exit 1
fi

# 결과 반환
cat > /tmp/gateway_refresh_result.json <<EOF
{
  "status": "success",
  "gateway_lssn": $LSSN,
  "server_count": $SERVER_COUNT,
  "refresh_time": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF

if [ -f "$INSTALL_DIR/giipscripts/kvsput.sh" ]; then
    bash $INSTALL_DIR/giipscripts/kvsput.sh /tmp/gateway_refresh_result.json "gateway_refresh"
fi

echo "===== Refresh Completed ====="
```

---

### 4. 웹 UI 개선

#### A. Gateway 서버 관리 페이지 (`/admin/gateway`)

**기능**:
1. Gateway 서버 목록 조회
2. Gateway로 설정 (버튼 클릭)
3. 연결된 원격 서버 목록 보기
4. 서버 목록 갱신 (강제)
5. 상태 모니터링

**API 호출**:
```typescript
// Gateway 서버 목록
const gateways = await fetchAzureCommand('GatewayServerList', { 
  jsondata: { csn: currentCsn }
});

// Gateway로 설정
await fetchAzureCommand('GatewayServerPut', {
  jsondata: {
    lssn: selectedLssn,
    is_gateway: 1
  }
});

// 원격 서버 목록
const remoteServers = await fetchAzureCommand('GatewayRemoteServerList', {
  jsondata: { gateway_lssn: gatewayLssn }
});
```

#### B. 서버 상세 페이지에 Gateway 설정 추가

**lsvrdetail 페이지 개선**:
```tsx
<section className="gateway-settings">
  <h3>Gateway 설정</h3>
  
  {!server.is_gateway && (
    <>
      <button onClick={() => setAsGateway(server.lssn)}>
        이 서버를 Gateway로 설정
      </button>
      
      <label>Gateway 서버 선택:</label>
      <select onChange={(e) => setGatewayLssn(e.target.value)}>
        <option value="">Gateway 사용 안함</option>
        {gateways.map(gw => (
          <option key={gw.lssn} value={gw.lssn}>
            {gw.hostname} ({gw.lsip})
          </option>
        ))}
      </select>
      
      {gatewayLssn && (
        <div className="ssh-config">
          <input placeholder="SSH Host" />
          <input placeholder="SSH User" />
          <input placeholder="SSH Port (default: 22)" />
          <input placeholder="SSH Key Path" />
        </div>
      )}
    </>
  )}
  
  {server.is_gateway && (
    <div className="gateway-info">
      <p>✅ 이 서버는 Gateway 서버입니다</p>
      <p>관리 중인 원격 서버: {server.remote_server_count}개</p>
      <button onClick={() => refreshGatewayList(server.lssn)}>
        서버 목록 갱신
      </button>
    </div>
  )}
</section>
```

---

### 5. giipAgent.sh 통합 개선

**현재 문제**: giipAgent.sh와 giipAgentGateway.sh가 분리되어 있음

**개선안**: giipAgent.sh가 자동으로 Gateway 모드 감지

```bash
#!/bin/bash
# giipAgent Ver. 2.0 - Unified Agent with Gateway Support

# Config 로드
. ./giipAgent.cnf

# Gateway 모드 확인
if [ -f "/opt/giipAgentLinux/giipAgentGateway.cnf" ]; then
    echo "Gateway mode detected"
    exec /opt/giipAgentLinux/giipAgentGateway.sh
    exit 0
fi

# 일반 Agent 모드로 계속...
```

---

## 📊 워크플로우

### Gateway 서버 설정 플로우
```
1. 웹 UI에서 서버 선택
2. "Gateway로 설정" 버튼 클릭
3. API: pGatewayServerPut (is_gateway=1)
4. DB: tLSvr.is_gateway = 1
5. CQE: setup_gateway_auto.sh 큐에 자동 등록
6. Agent: giipAgent.sh가 setup_gateway_auto.sh 다운로드 및 실행
7. Gateway 서버에 giipAgentGateway.sh 설치 및 cron 등록
8. 완료: Gateway 서버 활성화
```

### 원격 서버 추가 플로우
```
1. 웹 UI에서 서버 선택
2. "Gateway에 연결" 선택 및 SSH 정보 입력
3. API: pGatewayServerPut (gateway_lssn=X, SSH 정보)
4. DB: tLSvr.gateway_lssn = X
5. CQE: refresh_gateway_serverlist.sh 큐에 등록 (Gateway 서버로)
6. Gateway Agent: 서버 목록 갱신
7. 완료: 원격 서버가 Gateway를 통해 관리됨
```

---

## 🎯 장점

### Before (수동 설정)
- ❌ 서버 SSH 접속하여 파일 편집
- ❌ CSV 파일 수동 관리
- ❌ 설정 실수 가능성
- ❌ 서버 추가마다 SSH 접속 필요

### After (자동 설정)
- ✅ 웹 UI에서 클릭 한 번
- ✅ DB 기반 자동 동기화
- ✅ 설정 오류 최소화
- ✅ 중앙 관리 및 모니터링

---

## 🚀 다음 단계

1. **SP 작성** (6개)
   - pGatewayServerList
   - pGatewayRemoteServerList
   - pGatewayServerPut
   - pGatewayExportServerList
   - (위 문서 참조)

2. **스크립트 등록** (2개)
   - setup_gateway_auto.sh → tMgmtScript
   - refresh_gateway_serverlist.sh → tMgmtScript

3. **웹 UI 페이지** (1개)
   - /admin/gateway 페이지 생성
   - lsvrdetail에 Gateway 설정 추가

4. **Agent 업데이트**
   - giipAgent.sh Gateway 모드 자동 감지 추가

5. **테스트**
   - Gateway 서버 설정 테스트
   - 원격 서버 추가/제거 테스트
   - 서버 목록 자동 동기화 테스트

---

## 📝 마이그레이션 가이드

### 기존 Gateway 서버 마이그레이션

```sql
-- 1. 기존 Gateway 서버 식별 및 등록
UPDATE tLSvr 
SET is_gateway = 1
WHERE LSSN IN (
    -- 수동으로 Gateway로 사용 중인 서버 LSSN
    SELECT LSSN FROM tLSvr 
    WHERE LSHostname LIKE '%gateway%'  -- 예시
)

-- 2. 원격 서버들을 Gateway에 연결
UPDATE tLSvr
SET gateway_lssn = <gateway_lssn>
WHERE LSSN IN (
    -- CSV 파일에 있던 원격 서버들
)

-- 3. Gateway 초기 설정 스크립트 실행
EXEC pGatewayServerPut 
    @lssn = <gateway_lssn>,
    @is_gateway = 1
```

---

## 🔗 관련 문서
- [CQE_ARCHITECTURE.md](../../giipAgentAdmLinux/docs/CQE_ARCHITECTURE.md)
- [CQE_V2_SUMMARY.md](./CQE_V2_SUMMARY.md)
- [giipAgentGateway.sh](../giipAgentGateway.sh)
