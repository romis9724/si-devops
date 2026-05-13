# SkyWalking H2 -> Elasticsearch 마이그레이션 가이드

H2는 PoC 전용입니다. 운영 사용 전 반드시 Elasticsearch backend로 전환합니다.

## 1) 버전 매트릭스

| Elasticsearch | SW_STORAGE | 추가 환경변수 예시 |
|---|---|---|
| 6.x | `elasticsearch` | `SW_STORAGE_ES_CLUSTER_NODES=elasticsearch:9200` |
| 7.x | `elasticsearch7` | `SW_STORAGE_ES_CLUSTER_NODES=elasticsearch:9200` |
| 8.x | `elasticsearch` (SW 버전 호환 확인 필수) | `SW_STORAGE_ES_CLUSTER_NODES=https://elasticsearch:9200` |

## 2) compose 환경변수 예시

```yaml
environment:
  SW_STORAGE: elasticsearch7
  SW_STORAGE_ES_CLUSTER_NODES: http://elasticsearch-${PROJECT_NAME}:9200
  SW_STORAGE_ES_INDEX_SHARDS_NUMBER: 1
  SW_STORAGE_ES_INDEX_REPLICAS_NUMBER: 0
```

보안(ES 8 TLS/인증) 사용 시:

```yaml
environment:
  SW_STORAGE: elasticsearch
  SW_STORAGE_ES_CLUSTER_NODES: https://elasticsearch-${PROJECT_NAME}:9200
  SW_ES_USER: skywalking
  SW_ES_PASSWORD: <secret>
  SW_STORAGE_ES_SSL_JKS_PATH: /skywalking/config/es-client.jks
```

## 3) 절차

1. Elasticsearch readiness 확인
2. OAP를 ES 설정으로 변경
3. OAP 재기동 후 `http://<OAP>:12800/healthcheck` 확인 (SkyWalking 10.1+; `/internal/l7check` 제거됨)
4. SkyWalking UI에서 신규 trace 유입 확인

## 4) 주의사항

- H2 데이터는 파일 기반 임시 데이터로 재배포/볼륨 제거 시 손실됩니다.
- 기존 H2 데이터는 일반적으로 ES로 직접 이전하지 않고 컷오버 시점 이후 데이터부터 적재합니다.
