apiVersion: 1

providers:
  - name: ${PROJECT_NAME}-dashboards
    folder: Observability
    folderUid: ${PROJECT_NAME}-obs
    type: file
    disableDeletion: true
    updateIntervalSeconds: 30
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards
