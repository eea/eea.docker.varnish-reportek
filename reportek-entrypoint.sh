#!/bin/sh
set -e

# Cap Transient storage (uncacheable / streamed objects), which is unbounded by default
# and not covered by VARNISH_SIZE. Only add the flag when the base entrypoint will build
# the varnishd command itself (no args, or first arg is a flag).
if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
    set -- -s "Transient=malloc,${VARNISH_TRANSIENT_SIZE:-1G}" "$@"
fi

exec /docker-entrypoint.sh "$@"
