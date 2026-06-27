# Admin

설치, 등록, 유지보수 관련 관리자용 스크립트

## 📄 파일 목록

### 설치 스크립트
- `install-gateway.sh` - Gateway 설치
- `install-sshpass.sh` - sshpass 설치 (SSH 자동화용)

### 등록 & 스케줄
- `giipcronreg.sh` - Cron 작업 등록

### 유지보수
- `giipinstmodule.sh` - 모듈 설치
- `giiprecycle.sh` - 프로세스 재시작/재활용

## ⚠️ 주의사항

이 폴더의 스크립트는 **시스템 관리자 권한이 필요**합니다.

## 🚀 사용법

### 설치
```bash
sudo bash admin/install-gateway.sh
sudo bash admin/install-sshpass.sh
```

### Cron 등록
```bash
sudo bash admin/giipcronreg.sh
```

### 모듈 설치
```bash
sudo bash admin/giipinstmodule.sh
```

### 프로세스 재활용
```bash
bash admin/giiprecycle.sh
```

## 📌 각 스크립트 설명

각 스크립트의 헤더 주석에서 상세한 사용법과 옵션을 확인할 수 있습니다.
