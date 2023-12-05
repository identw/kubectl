FROM docker.io/alpine:3.18.5
LABEL org.opencontainers.image.source https://github.com/identw/kubectl

RUN apk add --no-cache curl \
    && curl -L https://dl.k8s.io/release/v1.24.17/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl
