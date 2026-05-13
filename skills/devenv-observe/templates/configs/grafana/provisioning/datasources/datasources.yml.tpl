apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://prometheus-${PROJECT_NAME}:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: 15s

  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://loki-${PROJECT_NAME}:3100
    editable: false
    jsonData:
      maxLines: 1000
