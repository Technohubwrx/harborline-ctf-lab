#!/usr/bin/env bash
# =============================================================================
# Harborline - CTFd setup on Kali Linux
#
#   sudo bash kali_ctfd_setup.sh
#
# Installs Docker, downloads CTFd (pinned release), builds and starts it.
# CTFd will be available at http://<kali-ip>:8000  (and port 8080 via nginx).
# (nginx is moved off port 80, which Kali's own web server often occupies.)
# Re-running is safe: it reuses the existing ~/CTFd folder and data.
# =============================================================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

CTFD_VERSION="3.8.9"

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }
USER_NAME="${SUDO_USER:-kali}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
CTFD_DIR="${USER_HOME}/CTFd"

log() { echo -e "\n\e[1;32m[ctfd]\e[0m $*"; }

log "Installing Docker, git and Python requests"
apt-get update -y
apt-get install -y docker.io git curl python3-requests
systemctl enable --now docker

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
else
  apt-get install -y docker-compose
  COMPOSE="docker-compose"
fi
log "Using: $($COMPOSE version | head -1)"

usermod -aG docker "$USER_NAME"

if [ ! -d "$CTFD_DIR" ]; then
  log "Downloading CTFd ${CTFD_VERSION}"
  sudo -u "$USER_NAME" git clone --depth 1 --branch "$CTFD_VERSION" \
       https://github.com/CTFd/CTFd.git "$CTFD_DIR"
else
  log "CTFd folder already exists at ${CTFD_DIR}, reusing it"
fi

log "Building and starting CTFd (first build takes a few minutes)"
cd "$CTFD_DIR"

# Kali often already serves on port 80, which would clash with CTFd's nginx.
# Move the nginx front-end to 8080. CTFd itself stays on 8000.
if grep -q '^\s*- 80:80' docker-compose.yml; then
  sed -i 's/- 80:80/- 8080:80/' docker-compose.yml
  log "Moved CTFd nginx to port 8080 (port 80 left free for your tools)"
fi
$COMPOSE up -d --build

log "Waiting for CTFd to answer on port 8000"
for i in $(seq 1 60); do
  if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000 | grep -qE '200|302'; then
    READY=1; break
  fi
  sleep 5
done

if [ "${READY:-0}" = "1" ]; then
  log "CTFd is running."
else
  log "CTFd did not answer yet. Check with: cd ${CTFD_DIR} && sudo ${COMPOSE} logs ctfd"
fi

echo
echo "  Open in Kali browser: http://127.0.0.1:8000  (nginx also on :8080)"
echo "  From other VMs/host use one of these IPs:"
ip -4 -o addr show scope global | awk '{print "    " $2 ": http://" substr($4,1,index($4,"/")-1) ":8000"}'
echo
echo "  Next:"
echo "   1. Finish the setup wizard (choose User mode)."
echo "   2. Admin > Settings (your profile) > Access Tokens > Generate."
echo "   3. python3 push_challenges.py --url http://127.0.0.1:8000 --token <token> --flags harborline_flags.json"
echo
echo "  Stop CTFd:  cd ${CTFD_DIR} && sudo ${COMPOSE} down"
echo "  Start it:   cd ${CTFD_DIR} && sudo ${COMPOSE} up -d"
