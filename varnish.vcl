vcl 4.1;

import std;
import directors;
import dynamic;

backend default none;

sub vcl_init {

  new cluster = dynamic.director(port = "<VARNISH_BACKEND_PORT>", ttl = <VARNISH_DNS_TTL>);

}

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

    set req.backend_hint = cluster.backend("<VARNISH_BACKEND>");
    set req.http.X-Varnish-Routed = "1";

    if (req.http.X-Forwarded-Proto == "https" ) {
        set req.http.X-Forwarded-Port = "443";
    } else {
        set req.http.X-Forwarded-Port = "80";
        set req.http.X-Forwarded-Proto = "http";
    }

    set req.http.X-Username = "Anonymous";

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

    if (req.method == "BAN") {
        # Same ACL check as above:
        if (!client.ip ~ purge) {
            return(synth(403, "Not allowed."));
        }
        ban("req.http.host == " + req.http.host +
            " && req.url == " + req.url);
            # Throw a synthetic page so the
            # request won't go to the backend.
            return(synth(200, "Ban added")
        );
    }

    # Only deal with "normal" types
    if (req.method != "GET" &&
           req.method != "HEAD" &&
           req.method != "PUT" &&
           req.method != "POST" &&
           req.method != "TRACE" &&
           req.method != "OPTIONS" &&
           req.method != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return(pipe);
    }


    # Only cache GET or HEAD requests. This makes sure the POST requests are always passed.
    if (req.method != "GET" && req.method != "HEAD") {
        return(pass);
    }


    if (req.http.Expect) {
        return(pipe);
    }

    if (req.http.If-None-Match && !req.http.If-Modified-Since) {
        return(pass);
    }

    # Do not cache RestAPI authenticated requests
    if (req.http.Authorization || req.http.Authenticate) {
        set req.http.X-Username = "Authenticated (RestAPI)";

        # pass (no caching)
        unset req.http.If-Modified-Since;
        return(pass);
    }

    # Cache static files, except the big ones
    if (req.method == "GET" && req.url ~ "^(/[a-zA-Z0-9\_\-]*)?/static/" && !(req.url ~ "^[^?]*\.(mp[34]|rar|rpm|tar|tgz|gz|wav|zip|bz2|xz|7z|avi|mov|ogm|mpe?g|mk[av]|webm)(\?.*)?$")) {
        return(hash);
    }

    set req.http.UrlNoQs = regsub(req.url, "\?.*$", "");
    # Do not cache authenticated requests
    if (req.http.Cookie && req.http.Cookie ~ "__ac(|_(name|password|persistent))=")
    {
       if (req.http.UrlNoQs ~ "\.(js|css)$") {
            unset req.http.cookie;
            return(pipe);
        }

        set req.http.X-Username = regsub( req.http.Cookie, "^.*?__ac=([^;]*);*.*$", "\1" );

        # pass (no caching)
        unset req.http.If-Modified-Since;
        return(pass);
    }

    # Do not cache login form
    if (req.url ~ "login_form$" || req.url ~ "login$")
    {
        # pass (no caching)
        unset req.http.If-Modified-Since;
        return(pass);
    }

    ### always cache these items:

    # javascript and css
    if (req.method == "GET" && req.url ~ "\.(js|css)") {
        return(hash);
    }

    ## images
    if (req.method == "GET" && req.url ~ "\.(gif|jpg|jpeg|bmp|png|tiff|tif|ico|img|tga|wmf|webp)$") {
        return(hash);
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
    if (!(req.http.Authorization || req.http.Cookie && req.http.cookie ~ "(^|.*; )beaker\.session|_ZopeId|__ginger_snap=")) {
        set req.http.X-Anonymous = "True";
    } else {
        set req.http.X-Anonymous = "False";
    }

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

    if (req.url ~ "^[^?]*\.(mp[34]|rar|rpm|tar|tgz|gz|wav|zip|bz2|xz|7z|avi|mov|ogm|mpe?g|mk[av]|webm)(\?.*)?$") {
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
        // A pure unadultered hit, deliver it
        # normal hit
        return (deliver);
    }

    # We have no fresh fish. Lets look at the stale ones.
    if (std.healthy(req.backend_hint)) {
        # Backend is healthy. Limit age to 10s.
        if (obj.ttl + 10s > 0s) {
            set req.http.grace = "normal(limited)";
            return (deliver);
        } else {
            # No candidate for grace. Fetch a fresh object.
            return(pass);
        }
    } else {
        # backend is sick - use full grace
        // Object is in grace, deliver it
        // Automatically triggers a background fetch
        if (obj.ttl + obj.grace > 0s) {
            set req.http.grace = "full";
            return (deliver);
        } else {
            # no graced object.
            return (pass);
        }
    }

    if (req.method == "PURGE") {
        set req.method = "GET";
        set req.http.X-purger = "Purged";
        return(synth(200, "Purged. in hit " + req.url));
    }

    // fetch & deliver once we get the result
    return (pass); # Dead code, keep as a safeguard
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
    // workaround for #292877
    if (bereq.url ~ "run_conversion") {
        set bereq.http.Connection = "close";
    }

    return (fetch);
}

sub vcl_backend_response {
    # needed for ban-lurker
    # Cleanup double slashes: '//' -> '/' - refs #95891
    set beresp.http.x-url = regsub(bereq.url, "\/\/", "/");

    set beresp.http.Vary = "X-Anonymous,Accept-Encoding";

    # stream possibly large files
    if (bereq.url ~ "^[^?]*\.(mp[34]|rar|rpm|tar|tgz|gz|xml|gml|wav|zip|bz2|xz|7z|avi|mov|ogm|mpe?g|mk[av]|webm)(\?.*)?$") {
        unset beresp.http.set-cookie;
        set beresp.http.X-Cache-Stream = "YES";
        set beresp.http.X-Cacheable = "NO - File Stream";
        set beresp.uncacheable = true;
        set beresp.do_stream = true;
        return(deliver);
    }

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

    # Header does not exist
    if (!beresp.http.Cache-Control) {
         set beresp.ttl = <VARNISH_BERESP_TTL>;
    }

    # The object is not cacheable
    if (beresp.http.Set-Cookie) {
        set beresp.http.X-Cacheable = "NO - Set Cookie";
        set beresp.ttl = 0s;
        set beresp.uncacheable = true;
    } elsif (beresp.http.Cache-Control ~ "private") {
        set beresp.http.X-Cacheable = "NO - Cache-Control=private";
        set beresp.uncacheable = true;
        set beresp.ttl = <VARNISH_BERESP_TTL>;
    } elsif (beresp.http.Surrogate-control ~ "no-store") {
        set beresp.http.X-Cacheable = "NO - Surrogate-control=no-store";
        set beresp.uncacheable = true;
        set beresp.ttl = <VARNISH_BERESP_TTL>;
    } elsif (!beresp.http.Surrogate-Control && beresp.http.Cache-Control ~ "no-cache|no-store") {
        set beresp.http.X-Cacheable = "NO - Cache-Control=no-cache|no-store";
        set beresp.uncacheable = true;
        set beresp.ttl = <VARNISH_BERESP_TTL>;
    } elsif (beresp.http.Vary == "*") {
        set beresp.http.X-Cacheable = "NO - Vary=*";
        set beresp.uncacheable = true;
        set beresp.ttl = <VARNISH_BERESP_TTL>;

    # ttl handling
    } elsif (beresp.ttl < 0s) {
        set beresp.http.X-Cacheable = "NO - TTL < 0";
        set beresp.uncacheable = true;
    } elsif (beresp.ttl == 0s) {
        set beresp.http.X-Cacheable = "NO - TTL = 0";
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

    set beresp.grace = <VARNISH_BERESP_GRACE>;
    set beresp.keep = <VARNISH_BERESP_KEEP>;
    return (deliver);

}

sub vcl_deliver {
    set resp.http.grace = req.http.grace;

    # add a note in the header regarding the backend
    set resp.http.X-Backend = req.backend_hint;

    if (obj.hits > 0) {
         set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
    /* Rewrite s-maxage to exclude from intermediary proxies
      (to cache *everywhere*, just use 'max-age' token in the response to avoid
      this override) */
    if (resp.http.Cache-Control ~ "s-maxage") {
        set resp.http.Cache-Control = regsub(resp.http.Cache-Control, "s-maxage=[0-9]+", "s-maxage=0");
    }
    /* Remove proxy-revalidate for intermediary proxies */
    if (resp.http.Cache-Control ~ ", proxy-revalidate") {
        set resp.http.Cache-Control = regsub(resp.http.Cache-Control, ", proxy-revalidate", "");
    }
    # set audio, video and pdf for inline display
    if (resp.http.Content-Type ~ "audio/" || resp.http.Content-Type ~ "video/" || resp.http.Content-Type ~ "/pdf") {
        set resp.http.Content-Disposition = regsub(resp.http.Content-Disposition, "attachment;", "inline;");
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
