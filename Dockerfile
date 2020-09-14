FROM eeacms/varnish:4.1-6.4
MAINTAINER "EEA: IDM2 C-TEAM" <eea-edw-c-team-alerts@googlegroups.com>



ENV  PARAM_VALUE="-p thread_pool_min=100 -p thread_pool_max=1000 -p thread_pool_timeout=300 -p lru_interval=1800 -p max_restarts=6 -p http_range_support=on -p http_max_hdr=128 -p http_req_hdr_len=20000 -p http_resp_hdr_len=20000" \
     BACKENDS="instance" \
     BACKENDS_PORT="8080" \
     BACKENDS_PROBE_ENABLED="false"

COPY varnish.vcl /etc/varnish/conf.d/


