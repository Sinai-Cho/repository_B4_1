# Agent 보안 및 모니터링 환경 구성 문서

## 1. 개요

본 문서는 Ubuntu Linux 환경에서 다음을 구성하는 절차와 증거를 정리한 문서이다.

- SSH 포트 변경 및 Root 원격 접속 차단
- UFW 방화벽 활성화 및 필요한 포트만 허용
- 역할 기반 계정 및 그룹 생성
- 공유/보안 디렉토리 분리와 ACL 적용
- 환경 변수 고정 및 애플리케이션 실행
- 시스템 상태 모니터링 스크립트 작성
- crontab 기반 자동 실행

이 문서는 운영 보안 기본 원칙을 정리하고, 실습 환경에서 확인 가능한 증거 자료를 남기는 데 목적이 있다.

## 2. 구성 목표

- SSH 기본 포트를 20022로 변경하고, root 원격 로그인을 비활성화한다.
- 인바운드 허용 포트를 20022/tcp, 15034/tcp만 허용하도록 방화벽을 구성한다.
- 계정과 그룹을 역할별로 분리하고, 최소 권한 원칙을 적용한다.
- API 키 및 로그 디렉토리를 별도 보안 구역으로 분리한다.
- 애플리케이션 환경 변수를 고정하여 실행 경로와 포트, 키 파일, 로그 경로를 일관되게 유지한다.
- monitor.sh를 실행해 프로세스, 포트, CPU, 메모리, 디스크 상태를 수집하고 로그에 기록한다.
- cron에 등록해 1분마다 자동으로 점검하도록 구성한다.

## 3. 예상 디렉토리 구조

```bash
/home/agent-admin/agent-app/
├── api_keys/
│   └── t_secret.key
├── bin/
│   └── monitor.sh
├── upload_files/
├── agent_app.py
└── .env
/var/log/agent-app/
└── monitor.log
```

## 4. 주요 설정 기록

아래 명령은 실습 환경에서 실행한 핵심 설정 기록이다.

### 4.1 SSH 보안 설정

```bash
sudo sed -i 's/^#\?Port .*/Port 20022/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

검증 명령:

```bash
sudo sshd -T | grep -E 'port|permitrootlogin'
ss -tulnp | grep sshd
```

필수 확인 항목:

- Port 20022
- PermitRootLogin no
- sshd가 20022/tcp에서 리슨 중

### 4.2 방화벽(UFW) 설정

```bash
sudo apt-get update
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 20022/tcp
sudo ufw allow 15034/tcp
sudo ufw --force enable
sudo ufw status verbose
```

검증 명령:

```bash
sudo ufw status
```

이 때 허용 목록은 다음만 남아 있어야 한다.

- 20022/tcp
- 15034/tcp

### 4.3 계정 및 그룹 생성

```bash
sudo groupadd agent-common
sudo groupadd agent-core
sudo useradd -m -s /bin/bash agent-admin
sudo useradd -m -s /bin/bash agent-dev
sudo useradd -m -s /bin/bash agent-test
sudo usermod -a -G agent-common agent-admin
sudo usermod -a -G agent-core agent-admin
sudo usermod -a -G agent-common agent-dev
sudo usermod -a -G agent-core agent-dev
sudo usermod -a -G agent-common agent-test
```

검증 명령:

```bash
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core
```

### 4.4 디렉토리 및 권한 구성

```bash
sudo mkdir -p /home/agent-admin/agent-app/upload_files
sudo mkdir -p /home/agent-admin/agent-app/api_keys
sudo mkdir -p /var/log/agent-app
sudo chown -R agent-admin:agent-admin /home/agent-admin/agent-app
sudo chgrp agent-common /home/agent-admin/agent-app/upload_files
sudo chmod 2775 /home/agent-admin/agent-app/upload_files
sudo chgrp agent-core /home/agent-admin/agent-app/api_keys
sudo chmod 750 /home/agent-admin/agent-app/api_keys
sudo chgrp agent-core /var/log/agent-app
sudo chmod 750 /var/log/agent-app
```

ACL을 사용할 경우:

```bash
sudo setfacl -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files
sudo setfacl -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys
sudo setfacl -m g:agent-core:rwx /var/log/agent-app
```

검증 명령:

```bash
ls -ld /home/agent-admin/agent-app/upload_files
ls -ld /home/agent-admin/agent-app/api_keys
ls -ld /var/log/agent-app
getfacl -p /home/agent-admin/agent-app/upload_files
getfacl -p /home/agent-admin/agent-app/api_keys
```

### 4.5 환경 변수 설정

```bash
sudo tee /etc/profile.d/agent-env.sh >/dev/null <<'EOF'
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key
export AGENT_LOG_DIR=/var/log/agent-app
EOF
```

검증:

```bash
source /etc/profile.d/agent-env.sh
echo $AGENT_HOME
echo $AGENT_PORT
```

### 4.6 키 파일 생성

```bash
sudo mkdir -p /home/agent-admin/agent-app/api_keys
sudo bash -c 'printf "%s\n" "agent_api_key_test" > /home/agent-admin/agent-app/api_keys/t_secret.key'
sudo chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys/t_secret.key
sudo chmod 640 /home/agent-admin/agent-app/api_keys/t_secret.key
```

### 4.7 애플리케이션 실행

일반 사용자 계정에서 실행하도록 구성한다.

```bash
su - agent-admin
cd $AGENT_HOME
python3 agent_app.py
```

기대 결과:

- Boot Sequence 5단계가 모두 [OK]
- 마지막 줄에 Agent READY 출력
- 0.0.0.0:15034에서 LISTEN 상태

검증:

```bash
ss -tulnp | grep 15034
```

## 5. 필수 증거 자료 체크리스트

다음은 과제 수행 시 반드시 확인해야 하는 증거 자료 목록이다.

### 5.1 SSH 포트 변경 및 Root 원격 접속 차단

- `/etc/ssh/sshd_config`에서 `Port 20022` 확인
- `/etc/ssh/sshd_config`에서 `PermitRootLogin no` 확인
- `ss -tulnp | grep sshd`에서 `*:20022` 확인

### 5.2 방화벽 활성화 및 허용 포트 확인

- `sudo ufw status`를 통해 방화벽 활성 여부 확인
- 허용 포트: `20022/tcp`, `15034/tcp`만 허용됨을 확인

### 5.3 계정/그룹 생성 확인

- `id agent-admin`
- `id agent-dev`
- `id agent-test`
- `getent group agent-common`
- `getent group agent-core`

### 5.4 디렉토리 및 권한 확인

- `ls -ld $AGENT_HOME`
- `ls -ld $AGENT_HOME/upload_files`
- `ls -ld $AGENT_HOME/api_keys`
- `ls -ld /var/log/agent-app`
- `getfacl` 결과로 ACL 확인

### 5.5 앱 부트 시퀀스 및 READY 확인

- Boot Sequence 5단계 모두 [OK]
- 마지막에 `Agent READY` 출력

### 5.6 monitor.sh 실행 결과

```bash
bash /home/agent-admin/agent-app/bin/monitor.sh
```

기대 결과:

- 프로세스 상태 확인
- 포트 15034 확인
- CPU / MEM / DISK 사용률 확인
- 경고 메시지 출력 여부 확인

### 5.7 로그 파일 누적 기록 확인

```bash
tail -n 20 /var/log/agent-app/monitor.log
ls -lh /var/log/agent-app
```

기대 결과:

- 타임스탬프와 점검 결과가 로그에 누적됨
- 최근 마지막 라인이 정상적으로 추가 됨

### 5.8 cron 자동 실행 확인

```bash
sudo crontab -u agent-admin -l
```

예시:

```cron
*/1 * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/monitor.log 2>&1
```

1분 뒤 다시 확인:

```bash
tail -n 5 /var/log/agent-app/monitor.log
```

로그가 증가하면 cron 자동 실행이 정상 동작한 것이다.

## 6. monitor.sh 동작 원리

`monitor.sh`는 Bash 기반으로 작성되며, 다음 항목을 점검한다.

- `agent_app.py` 프로세스 상태 확인
- 포트 15034 LISTEN 상태 확인
- UFW/firewalld 활성 여부 확인
- CPU 사용률
- 메모리 사용률
- 루트 파티션 디스크 사용률
- 임계값 초과 시 경고 표시
- 결과를 `/var/log/agent-app/monitor.log`에 기록

로그 형식은 다음과 같다.

```text
[YYYY-MM-DD HH:MM:SS] PID:1234 CPU:12% MEM:33% DISK_USED:58%
```

## 7. 로그 파일 용량 관리

로그를 계속 누적하면 파일 크기가 커질 수 있으므로, 아래와 같은 정책을 적용한다.

- 10MB 이상이면 이전 로그를 압축/회전
- 최대 10개 파일 유지
- 불필요한 오래된 로그는 삭제

예시:

```bash
sudo logrotate -d /etc/logrotate.d/agent-app
```

또는 monitor.sh 내부에서 파일 크기 기준으로 로테이션을 수행할 수 있다.

## 8. 보안 원칙 정리

- SSH 포트 변경과 root 원격 로그인을 막는 것은 기본 보안이다.
- 방화벽에서 필요한 포트만 열어두면 공격 표면이 줄어든다.
- 역할 기반 계정과 그룹, ACL은 권한 분리를 통해 보안 사고 범위를 최소화한다.
- 환경 변수와 키 파일 경로를 고정하면 잘못된 실행 경로로 인한 장애를 막을 수 있다.
- cron과 로그 통합은 운영 상태를 자동으로 추적할 수 있도록 한다.

## 9. 실행 권장 단계

1. `setup.sh`를 root 권한으로 실행한다.
2. `agent-admin` 계정으로 로그인한다.
3. `agent_app.py`를 실행한다.
4. `monitor.sh`를 수동으로 실행한다.
5. cron 등록 후 1분 뒤 로그 증가를 확인한다.

## 10. 제출 포인트 요약

- 요구사항 수행 내역서: 본 문서
- 자동화 스크립트: `bin/monitor.sh`
- 보안 설정 스크립트: `setup.sh`
- 앱 샘플: `agent_app.py`

본 문서는 실습 환경을 기준으로 작성되었고, 실제 Linux 서버에서 적용 시 환경에 맞게 경로와 사용자 이름을 조정하면 된다.
