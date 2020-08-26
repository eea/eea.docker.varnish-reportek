copernicus-land Varnish image
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
