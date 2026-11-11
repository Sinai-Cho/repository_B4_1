#!/bin/bash
# ==========================================================
# Agent 시스템 상태 수집 스크립트
# 작성 의도:
#   - 프로세스 상태 확인
#   - 포트 리스닝 확인
#   - CPU/MEM/DISK 수집
#   - 경고 출력
#   - 로그 남기기
# ==========================================================

set -u

APP_NAME="agent_app.py"
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/monitor.log}"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"

# 로그 디렉토리가 없으면 생성한다.
mkdir -p "${LOG_DIR}"

# ==========================================================
# 1. Health Check: 프로세스 확인
# ==========================================================
APP_PID="$(pgrep -af "${APP_NAME}" | awk 'NR==1 {print $1}')"
if [[ -z "${APP_PID}" ]]; then
  echo "[${NOW}] [ERROR] ${APP_NAME} 프로세스가 실행 중이 아닙니다."
  exit 1
fi

# ==========================================================
# 2. Health Check: 포트 15034 확인
# ==========================================================
PORT_STATUS="$(ss -lnt "sport = :${AGENT_PORT}" 2>/dev/null | tail -n +2 | awk 'NF {print $5}')"
if [[ -z "${PORT_STATUS}" ]]; then
  echo "[${NOW}] [ERROR] TCP ${AGENT_PORT} LISTEN 상태가 아닙니다."
  exit 1
fi

# ==========================================================
# 3. 방화벽 상태 점검
# ==========================================================
if command -v ufw >/dev/null 2>&1; then
  if ! ufw status 2>/dev/null | grep -q "Status: active"; then
    echo "[${NOW}] [WARNING] UFW가 비활성 상태입니다."
  fi
elif command -v firewall-cmd >/dev/null 2>&1; then
  if ! firewall-cmd --state 2>/dev/null | grep -q "running"; then
    echo "[${NOW}] [WARNING] firewalld가 비활성 상태입니다."
  fi
else
  echo "[${NOW}] [WARNING] 방화벽 관리 도구를 찾을 수 없습니다."
fi

# ==========================================================
# 4. CPU 사용률 계산
# ==========================================================
CPU_USAGE="$(top -bn1 | grep '%Cpu' | tail -n 1 | sed 's/.*,//' | awk '{print $1}' | tr -d '%')"
if [[ -z "${CPU_USAGE}" ]]; then
  CPU_USAGE="0"
fi
CPU_USAGE="${CPU_USAGE%%.*}"

# ==========================================================
# 5. 메모리 사용률 계산
# ==========================================================
MEM_USAGE="$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')"
if [[ -z "${MEM_USAGE}" ]]; then
  MEM_USAGE="0"
fi

# ==========================================================
# 6. 디스크 사용률 계산 (루트 파티션)
# ==========================================================
DISK_USED="$(df -P / | awk 'NR==2 {print $5}' | tr -d '%')"
if [[ -z "${DISK_USED}" ]]; then
  DISK_USED="0"
fi

# ==========================================================
# 7. 경고 출력
# ==========================================================
if (( CPU_USAGE > 20 )); then
  echo "[${NOW}] [WARNING] CPU 사용률이 ${CPU_USAGE}%로 임계치 20%를 초과했습니다."
fi

if (( MEM_USAGE > 10 )); then
  echo "[${NOW}] [WARNING] 메모리 사용률이 ${MEM_USAGE}%로 임계치 10%를 초과했습니다."
fi

if (( DISK_USED > 80 )); then
  echo "[${NOW}] [WARNING] 디스크 사용률이 ${DISK_USED}%로 임계치 80%를 초과했습니다."
fi

# ==========================================================
# 8. 로그 파일 기록
# ==========================================================
LOG_LINE="[${NOW}] PID:${APP_PID} CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USED}%"
printf '%s\n' "${LOG_LINE}" >> "${LOG_FILE}"

# 로그 파일 용량 관리 (10MB 제한, 10개 파일 유지)
# - 로그가 10MB를 넘으면 기존 파일을 압축/회전한다.
MAX_BYTES=$((10 * 1024 * 1024))
if [[ -f "${LOG_FILE}" ]] && [[ $(stat -c %s "${LOG_FILE}") -gt ${MAX_BYTES} ]]; then
  for i in 9 8 7 6 5 4 3 2 1; do
    if [[ -f "${LOG_FILE}.${i}" ]]; then
      mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i+1))"
    fi
  done
  mv "${LOG_FILE}" "${LOG_FILE}.1"
  touch "${LOG_FILE}"
fi

# 마지막으로 최신 로그라인을 출력한다.
printf '%s\n' "${LOG_LINE}"

# ==========================================================
# 9. 종료 코드
# ==========================================================
exit 0
