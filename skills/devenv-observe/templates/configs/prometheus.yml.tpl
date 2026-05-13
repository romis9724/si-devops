global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    project: '${PROJECT_NAME}'

# 동일 compose 스택의 alertmanager 서비스(DNS 이름 alertmanager)
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets:
          - '${BASTION_IP}:9100'
          - '${GITLAB_IP}:9100'
          - '${NEXUS_IP}:9100'
          - '${JENKINS_IP}:9100'
          - '${DB_IP}:9100'
          - '${BACKEND_IP}:9100'
          - '${FRONTEND_IP}:9100'
          - '${SECURITY_IP}:9100'
          - '${MONITORING_IP}:9100'
          - '${APM_IP}:9100'
          - '${LOGGING_IP}:9100'

  - job_name: 'cadvisor'
    static_configs:
      - targets:
          - '${BACKEND_IP}:8088'
          - '${FRONTEND_IP}:8088'
          - '${JENKINS_IP}:8088'

  - job_name: 'jenkins'
    metrics_path: '/prometheus/'
    static_configs:
      - targets: ['${JENKINS_IP}:8080']

  - job_name: 'gitlab'
    metrics_path: '/-/metrics'
    static_configs:
      - targets: ['${GITLAB_IP}:80']
