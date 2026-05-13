#!/usr/bin/env bash
set -euo pipefail
if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi
cat > /etc/wsl.conf <<'EOF'
[boot]
systemd=true
[user]
default=ubuntu
[interop]
appendWindowsPath=false
EOF
id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ubuntu-nopasswd
chmod 440 /etc/sudoers.d/90-ubuntu-nopasswd
