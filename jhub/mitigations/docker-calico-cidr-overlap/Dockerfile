FROM alpine:3.22

RUN apk add --no-cache iptables

COPY fix-docker-masquerade.sh /usr/local/bin/fix-docker-masquerade.sh

ENTRYPOINT ["/bin/sh", "/usr/local/bin/fix-docker-masquerade.sh"]
