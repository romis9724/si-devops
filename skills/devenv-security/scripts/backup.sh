#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"

docker exec "sonar-db-${PROJECT_NAME:-devenv}" pg_dump -U sonar sonarqube > "${BACKUP_DIR}/sonar-db-${TS}.sql"
tar -czf "${BACKUP_DIR}/sonar-volumes-${TS}.tgz" \
  /var/lib/docker/volumes/sonar_data \
  /var/lib/docker/volumes/sonar_logs \
  /var/lib/docker/volumes/sonar_extensions

echo "backup created: ${BACKUP_DIR}"
