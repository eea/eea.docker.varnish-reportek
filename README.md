reportek Varnish image
=============================

[![Docker]( https://dockerbuildbadges.quelltext.eu/status.svg?organization=eeacms&repository=reportek-varnish)](https://hub.docker.com/r/eeacms/reportek-varnish/builds)

### Prerequisites

* Install [Docker](https://docs.docker.com/engine/installation/)
* Install [Docker Compose](https://docs.docker.com/compose/install/)

### Installation

1. Get the source code:

        $ git clone https://github.com/eea/eea.docker.varnish-reportek
        $ cd eea.docker.varnish-reportek

2. Build and run the image locally:

        $ docker build -t varnish:local .
        $ docker run varnish:local

# Environment variables

## From official varnish image

* `VARNISH_HTTP_PORT` - varnish port
* `VARNISH_HTTPS_PORT` - varnish ssl port
* `VARNISH_SIZE` - varnish cache size

## From eeacms/varnish image

* `AUTOKILL_CRON` - Varnish re-create crontab, will force a recreation of the container. Uses UTC time, format is linux crontab - for example -  `0 2 * * *` is 02:00 UTC each day" 
* `VARNISH_CFG_CONTENT` - Multiline variable that will be written in the `default.vcl` file

## From this image (`reportek-entrypoint.sh`)

* `VARNISH_TRANSIENT_SIZE` - size of the `Transient` storage (default `1G`), used for uncacheable / pass objects and not counted in `VARNISH_SIZE`. Varnish leaves it unbounded by default, so large uncacheable responses can grow memory until the container is OOM-killed. When the cap is reached, requests that need Transient space fail (`FetchError: Could not get storage`, truncated body for slow clients) while the main cache is untouched. Keep `VARNISH_SIZE` + `VARNISH_TRANSIENT_SIZE` + ~2G overhead below the container memory limit. Only applied when the container is started with no arguments or with `varnishd` flags (the default `CMD`).

## varnish.vcl variables

* `VARNISH_BACKEND` - hostname / rancher service name
* `VARNISH_BACKEND_PORT` - service internal port
* `VARNISH_DNS_TTL` - how often will varnish check the IP of the hostname/rancher service
* `VARNISH_BERESP_TTL`, `VARNISH_BERESP_GRACE`, `VARNISH_BERESP_KEEP` - Object timeline configuration https://docs.varnish-software.com/tutorials/object-lifetime/
* `VARNISH_STATIC_TTL` - TTL for `/static/`, `/styles/`, `/favicon.ico`, legacy Zope `/misc_/Reportek/` and Zope `++resource++static` / `++resource++images` resources

## How to add new variable in varnish.vcl

1. Choose relevant variable name, starting with `VARNISH_` - eg. `VARNISH_EXAMPLE`

2. Add default value in Dockerfile 

      ENV VARNISH_EXAMPLE="GET"

3. Add variable in `<>` in varnish.vcl

      set req.http.X-Varnish-Routed = "<VARNISH_EXAMPLE>";