#!/bin/bash
# ==========================================================
# Agent 보안 및 운영 환경 구성 스크립트
# 작성 목적:
#   - SSH 보안 강화
#   - 방화벽 제한
#   - 계정/그룹 및 디렉토리 권한 구성
#   - 환경 변수 고정
#   - 앱 실행 환경 준비
#   - cron 자동화 설정
# ==========================================================

set -euo pipefail

# 이 스크립트는 루트 권한으로 실행하는 것을 전제로 한다.
# 일반적으로 다음과 같이 실행한다.
#   sudo bash setup.sh

AGENT_USER="agent-admin"
AGENT_HOME="/home/${AGENT_USER}/agent-app"
AGENT_PORT="15034"
AGENT_UPLOAD_DIR="${AGENT_HOME}/upload_files"
AGENT_KEY_PATH="${AGENT_HOME}/api_keys/t_secret.key"
AGENT_LOG_DIR="/var/log/agent-app"

# ==========================================================
# 1. 시스템 기본 준비
# ==========================================================
# apt 패키지 설치가 필요한 경우에만 수행한다.
# ssh와 ufw는 보통 기본적으로 존재하지만, 없는 경우를 대비한다.
if ! command -v sshd >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
fi

if ! command -v ufw >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
fi

# ----------------------------------------------------------
# 2. SSH 보안 설정
# ----------------------------------------------------------
# 포트 변경: 22번 대신 20022로 변경한다.
# root 원격 로그인은 비활성화하여 가장 기본적인 보안 수칙을 따른다.
# sshd 설정 파일을 직접 수정한 뒤, 서비스를 재시작한다.
if grep -Eq '^#?Port ' /etc/ssh/sshd_config; then
  sed -i 's/^#\?Port .*/Port 20022/' /etc/ssh/sshd_config
else
  echo 'Port 20022' >> /etc/ssh/sshd_config
fi

if grep -Eq '^#?PermitRootLogin ' /etc/ssh/sshd_config; then
  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
else
  echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
fi

systemctl restart ssh || service ssh restart

# ==========================================================
# 3. 방화벽 설정
# ==========================================================
# 인바운드 허용 포트는 SSH(20022)와 애플리케이션(15034)만 허용한다.
# 나머지 인바운드는 기본 차단을 유지한다.
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw --force enable
ufw status verbose

# ==========================================================
# 4. 그룹과 사용자 생성
# ==========================================================
# agent-common: 공용 파일 접근 그룹
# agent-core: 핵심 보안 자원 접근 그룹
# agent-admin: 운영/관리 계정
# agent-dev: 개발 및 스크립트 작성 계정
# agent-test: QA/테스트 계정
if ! getent group agent-common >/dev/null; then
  groupadd agent-common
fi

if ! getent group agent-core >/dev/null; then
  groupadd agent-core
fi

if ! id -u agent-admin >/dev/null 2>&1; then
  useradd -m -s /bin/bash agent-admin
fi

if ! id -u agent-dev >/dev/null 2>&1; then
  useradd -m -s /bin/bash agent-dev
fi

if ! id -u agent-test >/dev/null 2>&1; then
  useradd -m -s /bin/bash agent-test
fi

usermod -a -G agent-common agent-admin
usermod -a -G agent-core agent-admin
usermod -a -G agent-common agent-dev
usermod -a -G agent-core agent-dev
usermod -a -G agent-common agent-test

# ==========================================================
# 5. 디렉토리 구조 생성 및 권한 부여
# ==========================================================
mkdir -p "${AGENT_HOME}"
mkdir -p "${AGENT_HOME}/upload_files"
mkdir -p "${AGENT_HOME}/api_keys"
mkdir -p "${AGENT_HOME}/bin"
mkdir -p "${AGENT_LOG_DIR}"

# 공용 업로드 디렉토리는 agent-common 그룹이 접근할 수 있도록 구성한다.
chown -R "${AGENT_USER}:${AGENT_USER}" "${AGENT_HOME}"
chgrp agent-common "${AGENT_HOME}/upload_files"
chmod 2775 "${AGENT_HOME}/upload_files"

# 보안 자원 디렉토리: api_keys, 로그 디렉토리는 agent-core 그룹만 접근 가능하게 한다.
chown "${AGENT_USER}:agent-core" "${AGENT_HOME}/api_keys"
chmod 750 "${AGENT_HOME}/api_keys"

chown "${AGENT_USER}:agent-core" "${AGENT_LOG_DIR}"
chmod 750 "${AGENT_LOG_DIR}"

# 디렉터리 내부 파일 허용을 위해 ACL 설정을 추가한다.
# 업로드 디렉토리는 개발, 운영, 테스트가 모두 R/W 가능해야 한다.
setfacl -m g:agent-common:rwx "${AGENT_HOME}/upload_files"
setfacl -m d:g:agent-common:rwx "${AGENT_HOME}/upload_files"

# 보안 디렉토리는 agent-core 그룹 전용으로 분리한다.
setfacl -m g:agent-core:rwx "${AGENT_HOME}/api_keys"
setfacl -m d:g:agent-core:rwx "${AGENT_HOME}/api_keys"
setfacl -m g:agent-core:rwx "${AGENT_LOG_DIR}"
setfacl -m d:g:agent-core:rwx "${AGENT_LOG_DIR}"

# ==========================================================
# 6. 환경 변수 정의
# ==========================================================
# AGENT_HOME, AGENT_PORT, AGENT_UPLOAD_DIR, AGENT_KEY_PATH, AGENT_LOG_DIR
# 등을 고정해 런타임 환경이 일관되게 유지되도록 한다.
tee /etc/profile.d/agent-env.sh >/dev/null <<EOF
export AGENT_HOME=${AGENT_HOME}
export AGENT_PORT=${AGENT_PORT}
export AGENT_UPLOAD_DIR=${AGENT_UPLOAD_DIR}
export AGENT_KEY_PATH=${AGENT_KEY_PATH}
export AGENT_LOG_DIR=${AGENT_LOG_DIR}
EOF

# ==========================================================
# 7. 키 파일 생성
# ==========================================================
# 키 파일은 보안 디렉토리에 보관하고, 운영 계정이 소유하도록 한다.
printf '%s\n' 'agent_api_key_test' > "${AGENT_KEY_PATH}"
chown "${AGENT_USER}:agent-core" "${AGENT_KEY_PATH}"
chmod 640 "${AGENT_KEY_PATH}"

# ==========================================================
# 8. cron 등록
# ==========================================================
# monitor.sh를 매분 실행해 상태를 수집한다.
# 이 cron은 agent-admin 계정 기준으로 동작한다.
CRON_LINE="*/1 * * * * ${AGENT_HOME}/bin/monitor.sh >> ${AGENT_LOG_DIR}/monitor.log 2>&1"
if ! crontab -u agent-admin -l 2>/dev/null | grep -Fq "${AGENT_HOME}/bin/monitor.sh"; then
  (crontab -u agent-admin -l 2>/dev/null; echo "${CRON_LINE}") | crontab -u agent-admin -
fi

# ==========================================================
# 9. 확인 안내
# ==========================================================
# 실습 진행자는 아래 명령으로 결과를 확인할 수 있다.
#   id agent-admin
#   id agent-dev
#   id agent-test
#   ss -tulnp | grep 20022
#   ss -tulnp | grep 15034
#   sudo ufw status
#   ls -ld ${AGENT_HOME}/upload_files ${AGENT_HOME}/api_keys ${AGENT_LOG_DIR}
#   getfacl -p ${AGENT_HOME}/upload_files ${AGENT_HOME}/api_keys ${AGENT_LOG_DIR}

echo "[INFO] 보안 설정 및 권한 구성이 완료되었습니다."
echo "[INFO] SSH: 20022/tcp, APP: 15034/tcp만 허용 상태입니다."
echo "[INFO] AGENT_HOME=${AGENT_HOME}"
echo "[INFO] 설정 완료. 일반 사용자에서 앱을 실행해 주세요."
