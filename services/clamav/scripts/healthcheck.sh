#!/bin/sh
set -eu

# ClamAV healthcheck via TCP ping
# clamd might take a while to start (loading definitions)

if echo PING | nc -w 5 127.0.0.1 3310 | awk 'BEGIN{ok=0} /PONG/{ok=1} END{exit(ok?0:1)}'; then
    exit 0
else
    echo "ClamAV clamd TCP check failed"
    exit 1
fi
