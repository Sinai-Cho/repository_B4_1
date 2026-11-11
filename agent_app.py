#!/usr/bin/env python3
"""Simple health-check application for the Agent environment.

이 앱은 실습용으로 제공되며, 부트 절차를 5단계로 표시하고 마지막에
"Agent READY" 메시지를 출력한 뒤 15034 포트에서 대기한다.
"""

import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def print_step(step: int, message: str) -> None:
    print(f"[{step}/5] {message} [OK]")


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        payload = '{"status": "ok", "service": "agent-app"}'
        self.wfile.write(payload.encode("utf-8"))

    def log_message(self, format, *args):
        return


def main() -> None:
    agent_home = os.environ.get("AGENT_HOME", "/home/agent-admin/agent-app")
    port = int(os.environ.get("AGENT_PORT", "15034"))
    upload_dir = os.environ.get("AGENT_UPLOAD_DIR", os.path.join(agent_home, "upload_files"))
    key_path = os.environ.get("AGENT_KEY_PATH", os.path.join(agent_home, "api_keys", "t_secret.key"))
    log_dir = os.environ.get("AGENT_LOG_DIR", "/var/log/agent-app")

    print("Boot Sequence")
    print("[1/5] 환경 변수 확인")
    required = {
        "AGENT_HOME": agent_home,
        "AGENT_PORT": str(port),
        "AGENT_UPLOAD_DIR": upload_dir,
        "AGENT_KEY_PATH": key_path,
        "AGENT_LOG_DIR": log_dir,
    }
    for key, value in required.items():
        print(f"  {key}={value}")
    print_step(1, "환경 변수 확인")

    print("[2/5] 키 파일 확인")
    if not os.path.exists(key_path):
        raise FileNotFoundError(f"Missing key: {key_path}")
    with open(key_path, "r", encoding="utf-8") as handle:
        secret = handle.read().strip()
    print(f"  key={secret}")
    print_step(2, "키 파일 확인")

    print("[3/5] 디렉토리 준비")
    os.makedirs(upload_dir, exist_ok=True)
    os.makedirs(log_dir, exist_ok=True)
    print(f"  upload_dir={upload_dir}")
    print(f"  log_dir={log_dir}")
    print_step(3, "디렉토리 준비")

    print("[4/5] 네트워크 바인딩")
    address = ("0.0.0.0", port)
    server = ThreadingHTTPServer(address, HealthHandler)
    print(f"  listening on {address[0]}:{address[1]}")
    print_step(4, "네트워크 바인딩")

    print("[5/5] 서비스 시작")
    print("Agent READY")
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        print("\nShutting down agent-app")
        server.server_close()


if __name__ == "__main__":
    main()
