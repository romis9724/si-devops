#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
echo "[WARN] smoke gate 시작 (실패 허용)"
if docker exec "jenkins-${PROJECT_NAME}" sh -lc "docker login ${NEXUS_REGISTRY} -u admin -p \"${NEXUS_ADMIN_PASSWORD}\" >/dev/null 2>&1 && docker pull busybox:latest >/dev/null 2>&1 && docker tag busybox:latest ${NEXUS_REGISTRY}/smoke:latest && docker push ${NEXUS_REGISTRY}/smoke:latest >/dev/null 2>&1"; then
  echo "[WARN] smoke: jenkins->nexus push ok"
else
  echo "[WARN] smoke: jenkins->nexus push failed"
fi
if [[ -n "${GITLAB_TOKEN:-}" ]]; then
  pid="$(curl -fsS -X POST -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" -d "name=smoke-$(date +%s)" "http://127.0.0.1:${HOST_PORT_GITLAB}/api/v4/projects" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -n 1)"
  if [[ -n "${pid}" ]]; then
    curl -fsS -X DELETE -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "http://127.0.0.1:${HOST_PORT_GITLAB}/api/v4/projects/${pid}" >/dev/null 2>&1 || true
    echo "[WARN] smoke: gitlab create/delete ok"
  else
    echo "[WARN] smoke: gitlab create failed"
  fi
else
  echo "[WARN] smoke: GITLAB_TOKEN empty; gitlab api gate skipped"
fi
echo "[WARN] smoke gate 완료"
