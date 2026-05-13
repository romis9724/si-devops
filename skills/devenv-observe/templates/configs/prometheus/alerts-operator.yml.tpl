# 운영자용 알림 규칙 예시 — 기본 스택에는 포함하지 않음(파일 누락 시 Prometheus 기동 실패 방지).
# 사용 시: prometheus.yml 에 rule_files 추가 + compose 에 본 파일을 /etc/prometheus/ 로 마운트.
# 운영자용 기본 알림 규칙 (Alertmanager 없어도 Prometheus /rules·UI에서 확인 가능)
groups:
  - name: operator-infra
    interval: 30s
    rules:
      - alert: TargetDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
          team: operator
        annotations:
          summary: "스크레이프 실패 — {{ $labels.job }} / {{ $labels.instance }}"
          description: "Prometheus가 2분 이상 이 타깃에서 메트릭을 가져오지 못했습니다. 호스트·네트워크·에이전트·방화벽을 확인하세요."

      - alert: NodeCpuHigh
        expr: '100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85'
        for: 10m
        labels:
          severity: warning
          team: operator
        annotations:
          summary: "노드 CPU 부하 높음 — {{ $labels.instance }}"
          description: "5분 평균 대비 idle이 아닌 CPU 사용이 85%를 10분 이상 넘었습니다. Grafana Core 대시보드와 컨테이너 CPU를 함께 보세요."

      - alert: NodeMemoryPressure
        expr: '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90'
        for: 5m
        labels:
          severity: warning
          team: operator
        annotations:
          summary: "노드 메모리 압박 — {{ $labels.instance }}"
          description: "MemAvailable 기준 사용률이 90%를 5분 이상 유지했습니다. OOM·스왑·캐시를 확인하세요."
