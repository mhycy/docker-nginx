#!/bin/sh
# vim:sw=4:ts=4:et

set -e

if [ -z "${NGINX_ENTRYPOINT_QUIET_LOGS:-}" ]; then
    exec 3>&1
else
    exec 3>/dev/null
fi

if [ "$1" = "nginx" -o "$1" = "nginx-debug" ]; then
    if [ "`ls -A /docker/empty`" = "" ]; then
        echo >&3 "$0: No files found in /etc/nginx, create configure file"
        cp -R /etc/nginx.sample/* /etc/nginx/ 2>/dev/null
        mkdir -p /etc/nginx/ban-ip-access-cert 2>/dev/null
        mkdir -p /etc/nginx/conf.d 2>/dev/null
        
# create ssl pem file
        echo >&3 "$0: create /etc/nginx/dhparams.pem, please wait."
        openssl dhparam -out /etc/nginx/dhparams.pem 2048
        
        echo >&3 "$0: create /etc/nginx/ban-ip-access-cert/default-key.pem, please wait."
        openssl rand -writerand /root/.rnd
        openssl genrsa -out /etc/nginx/ban-ip-access-cert/default-key.pem 2048
        
        echo >&3 "$0: create /etc/nginx/ban-ip-access-cert/default.pem, please wait."
        openssl req -x509 -new -nodes -key /etc/nginx/ban-ip-access-cert/default-key.pem -days 36500 -out /etc/nginx/ban-ip-access-cert/default.pem -subj "/CN=default"

        echo >&3 "$0: create pem file success."
        
        echo >&3 "$0: create configfile file, please wait."
# create default config
cat>/etc/nginx/ssl_params<<EOF
ssl_session_cache         shared:SSL:10m;
ssl_session_timeout       60m;

ssl_session_tickets       on;
# ssl_session_ticket_key   "ticket.key";

ssl_dhparam               "dhparams.pem";

ssl_protocols             TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
ssl_ciphers               TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+ECDSA+AES256:EECDH+ECDSA+3DES:EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH:ECDHE-RSA-AES128-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA128:DHE-RSA-AES128-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES128-GCM-SHA128:ECDHE-RSA-AES128-SHA384:ECDHE-RSA-AES128-SHA128:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES128-SHA:DHE-RSA-AES128-SHA128:DHE-RSA-AES128-SHA128:DHE-RSA-AES128-SHA:DHE-RSA-AES128-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA384:AES128-GCM-SHA128:AES128-SHA128:AES128-SHA128:AES128-SHA:AES128-SHA:DES-CBC3-SHA:HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4;
ssl_prefer_server_ciphers on;
EOF

cat>/etc/nginx/nginx.conf<<EOF
user                    www-data;

worker_processes        auto;
events {
    worker_connections  1024;
    # multi_accept on;
}

pid                     /var/run/nginx.pid;

http {
    # Basic Settings
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;

    keepalive_timeout   60;
    
    types_hash_max_size 2048;
    server_tokens      off;

    # server_names_hash_bucket_size 64;
    # server_name_in_redirect off;

    include            /etc/nginx/mime.types;
    default_type       application/octet-stream;

    # Logging Settings
    access_log         /var/log/nginx/access.log;
    error_log          /var/log/nginx/errors.log;

    # Gzip Settings
    gzip               on;
    gzip_vary          on;
    
    gzip_comp_level    6;
    gzip_buffers       16 8k;

    gzip_min_length    1000;
    gzip_proxied       any;
    gzip_disable       "msie6";

    gzip_http_version  1.0;
    gzip_types         text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript application/javascript image/svg+xml;

    # Brotli Settings
    brotli             on;
    brotli_comp_level  6;
    brotli_types       text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript application/javascript image/svg+xml;

    # Ban IP access
    include conf.d/ban-ip-access;

    # Virtual Host Configs
    include conf.d/*.conf;
}

stream {
    # Stream Proxy Configs
    include conf.d/*.stream;
}
EOF

# ban-ip-access
cat>/etc/nginx/conf.d/ban-ip-access<<EOF
server {
    listen                    80 default;
    server_name               _;
    
    return                    444;
}

server {
    listen                    443 ssl http2 default;
    server_name               _;
    
    ssl_certificate           "ban-ip-access-cert/default.pem";
    ssl_certificate_key       "ban-ip-access-cert/default-key.pem";
    
    include                   ssl_params;
    return                    444;
}
EOF
        echo >&3 "$0: create configfile file success."
    fi
    
    if /usr/bin/find "/docker-entrypoint.d/" -mindepth 1 -maxdepth 1 -type f -print -quit 2>/dev/null | read v; then
        echo >&3 "$0: /docker-entrypoint.d/ is not empty, will attempt to perform configuration"

        echo >&3 "$0: Looking for shell scripts in /docker-entrypoint.d/"
        find "/docker-entrypoint.d/" -follow -type f -print | sort -n | while read -r f; do
            case "$f" in
                *.sh)
                    if [ -x "$f" ]; then
                        echo >&3 "$0: Launching $f";
                        "$f"
                    else
                        # warn on shell scripts without exec bit
                        echo >&3 "$0: Ignoring $f, not executable";
                    fi
                    ;;
                *) echo >&3 "$0: Ignoring $f";;
            esac
        done

        echo >&3 "$0: Configuration complete; ready for start up"
    else
        echo >&3 "$0: No files found in /docker-entrypoint.d/, skipping configuration"
    fi
fi

exec "$@"
