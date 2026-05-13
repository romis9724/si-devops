# 자동 생성됨 — devenv-dev / Nginx 리버스 프록시
# DOMAIN 변수가 설정되어 있을 때만 생성됩니다.
# SSL_TYPE=letsencrypt 이면 certbot 획득 후 아래 ssl 블록 주석 해제 필요.

server_tokens off;

# HTTP → HTTPS 리다이렉트 (SSL 사용 시)
server {
    listen 80;
    server_name ${DOMAIN};

    # ACME challenge (certbot letsencrypt용)
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS (SSL_TYPE=letsencrypt or self-signed 시 활성화)
# SSL_TYPE=none 이면 아래 블록 전체를 주석 처리하고 HTTP only 블록(아래)을 사용하세요.
# server {
#     listen 443 ssl http2;
#     server_name ${DOMAIN};
#
#     ssl_certificate     /etc/nginx/ssl/fullchain.pem;
#     ssl_certificate_key /etc/nginx/ssl/privkey.pem;
#     ssl_protocols       TLSv1.2 TLSv1.3;
#     ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
#     ssl_prefer_server_ciphers on;
#     ssl_session_cache   shared:SSL:10m;
#     ssl_session_timeout 1d;
#
#     add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
#     add_header X-Frame-Options "SAMEORIGIN" always;
#     add_header X-Content-Type-Options "nosniff" always;
#     add_header Referrer-Policy "strict-origin-when-cross-origin" always;
#
#     # Frontend
#     location / {
#         proxy_pass http://frontend-${PROJECT_NAME}:${FRONTEND_PORT};
#         proxy_http_version 1.1;
#         proxy_set_header Host $host;
#         proxy_set_header X-Real-IP $remote_addr;
#         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#         proxy_set_header X-Forwarded-Proto $scheme;
#     }
#
#     # Backend API
#     location /api/ {
#         proxy_pass http://backend-${PROJECT_NAME}:${APP_PORT};
#         proxy_http_version 1.1;
#         proxy_set_header Host $host;
#         proxy_set_header X-Real-IP $remote_addr;
#         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#         proxy_set_header X-Forwarded-Proto $scheme;
#     }
# }

# HTTP only (SSL_TYPE=none 또는 SSL 미설정 시)
server {
    listen 80;
    server_name ${DOMAIN};

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Frontend
    location / {
        proxy_pass http://frontend-${PROJECT_NAME}:${FRONTEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }

    # Backend API
    location /api/ {
        proxy_pass http://backend-${PROJECT_NAME}:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }
}
