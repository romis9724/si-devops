# Windows + WSL2 Ubuntu 설정 가이드

**Windows에서 이 스킬을 사용하려면 반드시 WSL2 Ubuntu에서 실행해야 합니다.**

PowerShell에서 직접 실행 시 발생하는 문제:
- 한글 인코딩 깨짐 (CP949 ↔ UTF-8)
- Docker Desktop 파이프 통신 오류 (`/pipe/dockerDesktopLinuxEngine/_ping: 500`)
- 경로 mount 실패 (`/mnt/c/...` → 컨테이너 내부 권한 문제)
- bash heredoc 스크립트 파일 생성 시 줄바꿈/인코딩 손상

---

## 1. WSL2 + Ubuntu 설치

### Windows 11 또는 Windows 10 (build 19041+)
PowerShell **관리자 권한**으로 1회만 실행:

```powershell
wsl --install -d Ubuntu-22.04
```

설치 완료 후 PC 재시작. 시작 메뉴에서 "Ubuntu 22.04" 실행 → 사용자명/비밀번호 입력.

### 확인
```powershell
wsl --list --verbose
# NAME            STATE           VERSION
# Ubuntu-22.04    Running         2          ← VERSION이 2여야 함
```

VERSION이 1이라면:
```powershell
wsl --set-version Ubuntu-22.04 2
```

---

## 2. WSL 리소스 설정 (`.wslconfig`)

기본 설정으로는 메모리가 부족합니다. Windows의 사용자 홈에 `.wslconfig` 파일 생성:

**파일 경로**: `C:\Users\<사용자명>\.wslconfig`

```ini
[wsl2]
memory=16GB        # 단일 서버 모드 권장 (최소 12GB)
processors=8
swap=8GB
localhostForwarding=true

[experimental]
sparseVhd=true     # 디스크 자동 회수 (선택)
```

설정 적용:
```powershell
wsl --shutdown   # WSL 재시작
```

---

## 3. Docker 설치 (두 가지 방식 중 택일)

### 방식 A: Docker Desktop + WSL2 backend (간편)

1. https://docs.docker.com/desktop/install/windows-install/ 에서 Docker Desktop 설치
2. Settings → Resources → WSL Integration → "Ubuntu-22.04" 토글 ON
3. WSL Ubuntu 터미널에서 확인:
   ```bash
   docker --version
   docker info
   ```

### 방식 B: WSL Ubuntu 내부에 Docker 직접 설치 (가벼움, 권장)

WSL Ubuntu 터미널에서:

```bash
# Docker 설치
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# systemd 활성화 (Ubuntu 22.04는 WSL2에서 systemd 지원)
sudo bash -c 'cat > /etc/wsl.conf <<EOF
[boot]
systemd=true
EOF'

# Windows에서 wsl --shutdown 후 재진입
```

PowerShell에서:
```powershell
wsl --shutdown
```

다시 Ubuntu 터미널 실행 후:
```bash
sudo systemctl enable --now docker
docker info   # 정상 출력되어야 함
```

---

## 4. WSL Ubuntu 내부 도구 설치

스킬이 요구하는 도구들 일괄 설치:

```bash
sudo apt update
sudo apt install -y \
  curl wget git vim \
  gettext-base \
  netcat-openbsd \
  jq \
  openssl \
  ca-certificates
```

---

## 5. 파일 위치 권장사항

**WSL에서 작업 디렉토리는 반드시 Linux 파일시스템(`~/`)에 두세요.**

```bash
# ✅ 좋음 — 빠르고 권한 문제 없음
cd ~
mkdir devenv-{project} && cd devenv-{project}

# ❌ 나쁨 — Windows 파일시스템 마운트는 느리고 chmod/symlink 동작 이상
cd /mnt/c/Users/myuser/devenv-{project}
```

VS Code에서 WSL 폴더 열기:
```bash
cd ~/devenv-{project}
code .   # WSL Remote 확장이 자동 실행
```

---

## 6. 파일 공유 / 접근

### Windows에서 WSL 파일 접근
탐색기 주소창: `\\wsl$\Ubuntu-22.04\home\<사용자명>`

### WSL에서 Windows 파일 접근
```bash
ls /mnt/c/Users/<사용자명>/
```

---

## 7. 한글 / 로케일 설정

```bash
sudo locale-gen ko_KR.UTF-8
sudo update-locale LANG=ko_KR.UTF-8

# .bashrc에 추가
echo 'export LANG=ko_KR.UTF-8' >> ~/.bashrc
echo 'export LC_ALL=ko_KR.UTF-8' >> ~/.bashrc
source ~/.bashrc
```

---

## 8. 문제 해결

### "docker: command not found" (WSL에서)
- 방식 A 사용 시: Docker Desktop의 WSL Integration이 켜져있는지 확인
- 방식 B 사용 시: `sudo systemctl status docker` 확인 → 종료 상태면 `sudo systemctl start docker`

### "Cannot connect to the Docker daemon" 
- `docker info` 결과 확인
- 방식 A: Docker Desktop 실행 중인지 확인
- 방식 B: `sudo systemctl restart docker`

### WSL이 매우 느림
- `.wslconfig`의 메모리 할당 확인
- 작업 폴더가 `/mnt/c/...`가 아닌 `~/`인지 확인
- `wsl --shutdown` 후 재실행

### Docker가 갑자기 죽음 / 메모리 부족
- `.wslconfig`의 memory 값 증가
- `docker system prune` 으로 정리

---

## 9. 자주 묻는 질문

**Q. PowerShell에서 docker 명령이 되는데 왜 WSL을 써야 하나?**
A. 명령은 되지만 한글 인코딩, 파일 경로, heredoc 스크립트 등 미묘한 비호환이 누적되어 결국 "왜 안되는지 모르는" 오류로 이어집니다. 처음부터 WSL을 쓰는 게 가장 빠릅니다.

**Q. WSL1을 쓰면 안 되나?**
A. 안 됩니다. WSL1은 Linux 커널이 아닌 호환 레이어이고, Docker가 동작하지 않습니다.

**Q. Hyper-V / VirtualBox와 WSL2 동시 사용?**
A. WSL2는 Hyper-V 기반이라 함께 동작합니다. VirtualBox 6.0+도 호환됩니다.
