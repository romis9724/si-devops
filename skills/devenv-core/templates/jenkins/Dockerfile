# Jenkins 커스텀 이미지 — Docker CLI + Compose Plugin 포함
# 이유: Jenkins Pipeline에서 docker build/push/compose 명령 사용을 위해
#       표준 jenkins/jenkins:lts-jdk17 이미지에는 Docker CLI가 없음
FROM jenkins/jenkins:lts-jdk17
USER root

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
         -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && ARCH=$(dpkg --print-architecture) \
    && CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME}") \
    && echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${CODENAME} stable" \
         | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update -qq \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

USER jenkins
