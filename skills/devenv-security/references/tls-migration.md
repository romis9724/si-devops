# SonarQube TLS Migration

`ssl_type=letsencrypt|self-signed` 기준으로 분기합니다.

1. `ssl_type=letsencrypt`: reverse proxy(nginx/caddy)에서 80/443 terminate
2. `ssl_type=self-signed`: 내부망 테스트용 인증서 발급 후 trust store 배포
3. `SONAR_HOST_URL`을 `https://`로 전환
4. Jenkins Sonar server URL도 `https://`로 교체
5. webhook endpoint TLS 통신 확인
