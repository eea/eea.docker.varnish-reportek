vcl 4.0;

acl purge {
    "localhost";
    "127.0.0.1";
    "172.17.0.0/16"; # Docker network
    "10.42.0.0/16";  # Rancher network
    "10.62.0.0/16";  # Rancher network
    "10.120.10.0/24"; # Internal networks
    "10.120.20.0/24"; # Internal networks
    "10.120.30.0/24"; # Internal networks
}

sub vcl_recv {


    # Before anything else we need to fix gzip compression
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
            # No point in compressing these
            unset req.http.Accept-Encoding;
        } else if (req.http.Accept-Encoding ~ "br") {
            set req.http.Accept-Encoding = "br";
        } else if (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } else if (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unknown algorithm
            unset req.http.Accept-Encoding;
        }
    }

    if (req.http.X-Forwarded-Proto == "https" ) {
        set req.http.X-Forwarded-Port = "443";
    } else {
        set req.http.X-Forwarded-Port = "80";
        set req.http.X-Forwarded-Proto = "http";
    }


    # Handle special requests
    if (req.method != "GET" && req.method != "HEAD") {

        # POST - Logins and edits
        if (req.method == "POST") {
            return(pass);
        }

        # PURGE - The CacheFu product can invalidate updated URLs
        if (req.method == "PURGE") {
            if (!client.ip ~ purge) {
                return (synth(405, "Not allowed."));
            }

            # replace normal purge with ban-lurker way - may not work
            # Cleanup double slashes: '//' -> '/' - refs #95891
            ban ("obj.http.x-url == " + regsub(req.url, "\/\/", "/"));
            return (synth(200, "Ban added. URL will be purged by lurker"));
        }

        return(pass);
    }

    ## for some urls or request we can do a pass here (no caching)
    if (req.method == "GET" && (
                req.url ~ "robots\.txt$" ||
                req.url ~ "aq_parent" ||
                req.url ~ "manage$" ||
                req.url ~ "help" ||
                req.url ~ "xmlexports" ||
                req.url ~ "manage_workspace$" ||
                req.url ~ "manage_main$")) {
        return(pass);
    }

    # disable caching in ZMI
    if (req.url ~ "manage" && req.http.cookie ~ "(beaker\.session|_ZopeId|__ginger_snap)="){
        return(pass);
    }

    # Keep auth/anon variants apart if "Vary: X-Anonymous" is in the response
#    if (!(req.http.Authorization || req.http.cookie ~ "(^|.*; )beaker\.session|_ZopeId|__ginger_snap=")) {
###        set req.http.X-Anonymous = "True";
   # }

    # Only deal with "normal" types
    if (req.method != "GET" &&
      req.method != "HEAD" &&
      req.method != "PUT" &&
      req.method != "POST" &&
      req.method != "TRACE" &&
      req.method != "OPTIONS" &&
      req.method != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pipe);
    }

    # Only cache GET or HEAD requests. This makes sure the POST requests are always passed.
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    if (req.http.Expect) {
        return(pipe);
    }

    if (req.http.If-None-Match && !req.http.If-Modified-Since) {
        return(pass);
    }

    /* Do not cache other authorized content by default */
    if (req.http.Authenticate || req.http.Authorization) {
        return(pass);
    }

    # Large static files should be piped, so they are delivered directly to the end-user without
    # waiting for Varnish to fully read the file first.

    if (req.url ~ "^[^?]*\.(mp3,mp4|rar|tar|tgz|gz|wav|zip)(\?.*)?$") {
        return(pipe);
    }

    return (hash);
}

sub vcl_pipe {

    # By default Connection: close is set on all piped requests, to stop
    # connection reuse from sending future requests directly to the
    # (potentially) wrong backend. If you do want this to happen, you can undo
    # it here.
    # unset bereq.http.connection;

    return(pipe);
}

sub vcl_pass {

    return (fetch);
}

sub vcl_hash {
    hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }
    return (lookup);
}

sub vcl_purge {

    return (synth(200, "Purged"));
}

sub vcl_hit {
    if (obj.ttl >= 0s) {
        # A standard hit, deliver from cache
        return (deliver);
    }


    if (req.method == "PURGE") {
        set req.method = "GET";
        set req.http.X-purger = "Purged";
        return(synth(200, "Purged. in hit " + req.url));
    }

    // fetch & deliver once we get the result
    return (fetch);
}

sub vcl_miss {


    if (req.method == "PURGE") {
        set req.method = "GET";
        set req.http.X-purger = "Purged-possibly";
        return(synth(200, "Purged. in miss " + req.url));
    }

    // fetch & deliver once we get the result
    return (fetch);
}

sub vcl_backend_fetch{

    return (fetch);
}

sub vcl_backend_response {
    # needed for ban-lurker
    # Cleanup double slashes: '//' -> '/' - refs #95891
    set beresp.http.x-url = regsub(bereq.url, "\/\/", "/");

    set beresp.http.Vary = "Accept-Encoding";

    # Only cache css/js/image content types and custom specified content types
    if (beresp.http.Content-Type !~ "application/javascript|text/html|application/x-javascript|text/css|image/*|${VARNISH_CACHE_CTYPES}") {
        unset beresp.http.Cache-Control;
        set beresp.http.Cache-Control = "no-cache, max-age=0, must-revalidate";
        set beresp.ttl = 0s;
        set beresp.http.Pragma = "no-cache";
        set beresp.uncacheable = true;
        set beresp.http.X-Cache = "NEVER";
        return(deliver);
    }

    # The object is not cacheable
    if (beresp.http.Set-Cookie) {
        set beresp.http.X-Cacheable = "NO - Set Cookie";
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
    } elsif (beresp.http.Cache-Control ~ "private") {
        set beresp.http.X-Cacheable = "NO - Cache-Control=private";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
    } elsif (beresp.http.Surrogate-control ~ "no-store") {
        set beresp.http.X-Cacheable = "NO - Surrogate-control=no-store";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
    } elsif (!beresp.http.Surrogate-Control && beresp.http.Cache-Control ~ "no-cache|no-store") {
        set beresp.http.X-Cacheable = "NO - Cache-Control=no-cache|no-store";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;
    } elsif (beresp.http.Vary == "*") {
        set beresp.http.X-Cacheable = "NO - Vary=*";
        set beresp.uncacheable = true;
        set beresp.ttl = 120s;


    # ttl handling
    } elsif (beresp.ttl < 0s) {
        set beresp.http.X-Cacheable = "NO - TTL < 0";
        set beresp.uncacheable = true;

    # Varnish determined the object was cacheable
    } else {
        set beresp.http.X-Cacheable = "YES";
    }

    # Do not cache 5xx errors
    if (beresp.status >= 500 && beresp.status < 600) {
        unset beresp.http.Cache-Control;
        set beresp.http.X-Cache = "NOCACHE";
        set beresp.http.Cache-Control = "no-cache, max-age=0, must-revalidate";
        set beresp.ttl = 0s;
        set beresp.http.Pragma = "no-cache";
        set beresp.uncacheable = true;
        return(deliver);
    }

    return (deliver);
}

sub vcl_deliver {
    set resp.http.grace = req.http.grace;
    if (obj.hits > 0) {
         set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
}

/*
 We can come here "invisibly" with the following errors: 413, 417 & 503
*/
sub vcl_synth {
    set resp.http.Content-Type = "text/html; charset=utf-8";
    set resp.http.Retry-After = "5";

    synthetic( {"
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
        <html>
          <head>
            <title>Varnish cache server: "} + resp.status + " " + resp.reason + {" </title>
          </head>
          <body>
            <h1>Error "} + resp.status + " " + resp.reason + {"</h1>
            <p>"} + resp.reason + {"</p>
            <h3>Guru Meditation:</h3>
            <p>XID: "} + req.xid + {"</p>
            <hr>
            <p>Varnish cache server</p>
          </body>
        </html>
    "} );

    return (deliver);
}
