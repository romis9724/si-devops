$ErrorActionPreference = "Stop"
$distros = wsl --list --verbose 2>$null
if (-not $distros) {
  Write-Host "[CORE-E020] WSL 미설치 | cause=wsl --list failed | action=wsl --install -d Ubuntu-22.04 --no-launch | next=retry"
  wsl --install -d Ubuntu-22.04 --no-launch
}
$systemdOk = wsl -d Ubuntu-22.04 -u root -- bash -lc "grep -q '^systemd=true' /etc/wsl.conf"
if ($LASTEXITCODE -ne 0) {
  Write-Host "[CORE-E021] systemd 비활성 | cause=/etc/wsl.conf | action=apply setup-wsl.sh.tpl | next=retry"
  exit 1
}
Write-Host "[OK] windows bootstrap check passed"
