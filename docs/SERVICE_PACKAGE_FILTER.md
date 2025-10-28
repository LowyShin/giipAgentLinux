# 서비스 패키지 필터링 규칙

## 개요
auto-discover-linux.sh는 서버에 설치된 **모든 RPM/DEB 패키지** 대신, **운영에 필요한 주요 서비스 패키지만** 수집합니다.

## 필터링 이유
- CentOS/RHEL 서버: 평균 700-1000개 패키지 설치
- 대부분은 시스템 라이브러리, 의존성 패키지 (운영 감시 불필요)
- **실제 모니터링 대상**: 백업/감시/웹/DB/미들웨어 등 주요 서비스

## 수집 대상 카테고리

### 1. 웹 서버 / 프록시
- nginx, httpd, apache
- haproxy, varnish, squid
- tomcat, jboss, wildfly, weblogic, glassfish

### 2. 데이터베이스
- mysql, mariadb
- postgresql, postgres
- mongodb, redis, memcache
- elasticsearch, cassandra

### 3. 메시징 / 큐
- kafka, rabbitmq, activemq
- zeromq, nsq

### 4. 백업 솔루션
- bacula, amanda
- rsync, rclone
- borg, duplicity, restic
- bareos

### 5. 모니터링 / 로깅
- nagios, zabbix, prometheus, grafana
- sensu, icinga, monit
- collectd, telegraf, datadog, newrelic
- splunk, logstash, filebeat, fluentd
- syslog-ng, rsyslog

### 6. 컨테이너 / 오케스트레이션
- docker, podman
- kubernetes (kubectl, kubelet)
- openshift

### 7. 자동화 / 배포
- ansible, puppet, chef, salt
- terraform, packer
- jenkins, gitlab-runner
- nexus, artifactory

### 8. 보안 / 인증
- vault (HashiCorp)
- consul, etcd
- openldap, sssd

### 9. 언어 런타임
- python3 (애플리케이션 실행용)
- nodejs, node-*
- php, php-fpm
- java, openjdk

### 10. 기타 서비스
- sonarqube (코드 품질)
- airflow (워크플로우)
- spark (빅데이터)

## 필터 패턴 (Regex)
```bash
SERVICE_FILTER='nginx|httpd|apache|mysql|mariadb|postgresql|postgres|redis|memcache|mongodb|elastic|kafka|rabbitmq|haproxy|varnish|tomcat|jboss|wildfly|weblogic|glassfish|nodejs|node-|php|python3|java-|openjdk|bacula|amanda|rsync|rclone|borg|duplicity|restic|nagios|zabbix|prometheus|grafana|sensu|icinga|monit|collectd|telegraf|datadog|newrelic|splunk|logstash|filebeat|fluentd|syslog|docker|kubernetes|openshift|ansible|puppet|chef|salt|terraform|jenkins|gitlab|nexus|artifactory|sonarqube|vault|consul|etcd'
```

## 수집 결과 예시

### Before (필터링 전)
```
Total packages: 749
- systemd-libs
- glibc-common
- libgcc
- bash
- coreutils
- ... (대부분 시스템 라이브러리)
```

### After (필터링 후)
```
Service packages: 12
- nginx-1.20.1
- mysql-5.7.38
- php-7.4.30
- rsync-3.1.2
- zabbix-agent-5.0.12
- docker-ce-20.10.17
- python36-3.6.8
- redis-6.2.7
```

## 필터 수정 방법

### 패키지 추가
```bash
# auto-discover-linux.sh 수정
SERVICE_FILTER='기존패턴|새패키지명'

# 예: vault 추가
SERVICE_FILTER='nginx|...|vault'
```

### 패키지 제외
```bash
# grep에서 -v 옵션 사용
| grep -iE "$SERVICE_FILTER" | grep -v '불필요한패키지'
```

### 카테고리별 필터링
```bash
# 웹서버만
WEB_FILTER='nginx|httpd|apache|tomcat'

# DB만
DB_FILTER='mysql|mariadb|postgresql|redis|mongodb'
```

## 로그 확인
```bash
tail -f /var/log/giip-auto-discover.log

# 예시 출력:
# [2025-10-28 14:30:00] Starting auto-discovery...
# [2025-10-28 14:30:01] Collected service-related packages: 12
# [2025-10-28 14:30:02] Sending data to API...
# [2025-10-28 14:30:03] SUCCESS: {"status":"ok","lssn":71174}
```

## 장점
1. **성능**: JSON 크기 95% 감소 (749개 → 12개)
2. **가독성**: UI에서 실제 서비스만 표시
3. **관리**: 백업/모니터링 대상이 명확함
4. **비용**: API 호출 크기 감소 → Azure Function 비용 절감

## 추가 필터 제안

### 보안 관련
```bash
# SELinux, firewall, fail2ban
SECURITY_FILTER='selinux|firewalld|iptables|fail2ban|aide|tripwire'
```

### 네트워크 도구
```bash
NETWORK_FILTER='bind|dnsmasq|dhcp|nfs|samba|cifs'
```

### 클라우드 Agent
```bash
CLOUD_FILTER='aws-cli|azure-cli|google-cloud|terraform'
```

## 참고
- 필터링은 **auto-discover-linux.sh**에서만 적용
- DB에는 필터링된 패키지만 저장 (tLSvrSoftware)
- 전체 패키지 목록이 필요하면 서버에서 직접 `rpm -qa` 실행
