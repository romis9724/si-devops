server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: containers
    static_configs:
      - targets: [localhost]
        labels:
          project: ${PROJECT_NAME}
          job: containerlogs
          owner: operator
          log_format: docker-json
          __path__: /var/lib/docker/containers/*/*.log
    pipeline_stages:
      # LogQL에서 {project=~".+", owner="operator"} 로 운영자 뷰를 좁히기 쉽게 함
      - json:
          expressions:
            stream: stream
            log: log
      - timestamp:
          source: time
          format: RFC3339Nano

  - job_name: system
    static_configs:
      - targets: [localhost]
        labels:
          project: ${PROJECT_NAME}
          job: syslog
          owner: operator
          log_format: host-file
          __path__: /var/log/*.log
