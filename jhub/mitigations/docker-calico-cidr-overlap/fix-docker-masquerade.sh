#!/bin/sh

while true; do
    while iptables -w 5 -t nat -C POSTROUTING \
        -s 172.17.0.0/16 ! -o docker0 \
        -j MASQUERADE 2>/dev/null
    do
        echo "$(date -u +%FT%TZ) removing conflicting Docker MASQUERADE rule"

        iptables -w 5 -t nat -D POSTROUTING \
            -s 172.17.0.0/16 ! -o docker0 \
            -j MASQUERADE || break
    done

    sleep 30
done
