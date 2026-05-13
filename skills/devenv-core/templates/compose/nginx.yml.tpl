# 자동 생성됨 — devenv-dev / Nginx 리버스 프록시
# DOMAIN 변수가 설정될 때만 생성됩니다.
# SSL_TYPE=letsencrypt 이면 certbot 서비스가 인증서를 발급 후 nginx를 reload합니다.
# SSL_TYPE=self-signed 이면 아래 certbot 서비스 대신 self-signed 인증서를 직접 마운트하세요:
#   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
#     -keyout configs/nginx/ssl/privkey.pem -out configs/nginx/ssl/fullchain.pem \
#     -subj "/CN=${DOMAIN}"
services:
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx-${PROJECT_NAME}
    volumes:
      - ../configs/nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ../configs/nginx/ssl:/etc/nginx/ssl:ro
      - certbot_www:/var/www/certbot:ro
      - certbot_conf:/etc/letsencrypt:ro
    ports:
      - "80:80"
      - "443:443"
    networks:
      - devenv-internal
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "nginx -t 2>/dev/null && curl -fsS http://localhost/health 2>/dev/null || curl -fsS http://localhost/ -o /dev/null -w '%{http_code}' | grep -q '200\\|301\\|302'"]
      interval: 30s
      timeout: 10s
      retries: 3

  # certbot: SSL_TYPE=letsencrypt 일 때 인증서 자동 갱신
  # SSL_TYPE=none 또는 self-signed 이면 이 서비스를 docker-compose.yml에서 제거하세요.
  certbot:
    image: certbot/certbot:latest
    container_name: certbot-${PROJECT_NAME}
    volumes:
      - certbot_www:/var/www/certbot
      - certbot_conf:/etc/letsencrypt
    entrypoint: >
      sh -c "
        trap exit TERM;
        while :; do
          certbot renew --webroot --webroot-path=/var/www/certbot --quiet
          sleep 12h & wait $${!};
        done
      "
    restart: unless-stopped

volumes:
  certbot_www:
  certbot_conf:

networks:
  devenv-internal:
    external: true

# ============================================================
# 최초 인증서 발급 (certbot 서비스 외 별도 실행):
#   docker run --rm -v certbot_www:/var/www/certbot -v certbot_conf:/etc/letsencrypt \
#     certbot/certbot certonly --webroot \
#     --webroot-path=/var/www/certbot \
#     -d ${DOMAIN} --email <your-email> --agree-tos --no-eff-email
# 발급 후 nginx 재시작: docker compose restart nginx
# ============================================================
