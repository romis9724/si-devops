# Upgrade and Rollback

- 대상: SonarQube `10.4-community` 기준
- 업그레이드:
  1. `scripts/backup.sh` 실행
  2. 신규 태그로 compose 업데이트
  3. `docker compose up -d` 후 `/api/system/status` 확인
- 롤백:
  1. 이전 이미지 태그로 되돌림
  2. volume/DB backup 복원
  3. health-check 재검증

EOL/LTA 정책은 릴리즈 노트 확인 후 quarterly 점검합니다.
