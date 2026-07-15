FROM haproxy:3.2-alpine

USER root
RUN apk upgrade --no-cache
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
USER haproxy
