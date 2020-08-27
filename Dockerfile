FROM ubuntu:18.04 AS nginx-build

WORKDIR /build

ENV NGINX_VERSION     "1.18.0"
ENV OPENSSL_VERSION   "1.1.1g"
ENV PCRE_VERSION      "8.44"
ENV ZLIB_VERSION      "1.2.11"

ENV BUILD_ROOT        "/build"
ENV BUILD_SRC         "/build/src"
ENV BUILD_RELEASE     "/build/release"
ENV NGINX_USER        "nginx"
ENV NGINX_GROUP       "nginx"
ENV NGINX_PREFIX      "/etc/nginx"
ENV NGINX_SBIN_PATH   "/usr/sbin/nginx"
ENV NGINX_CONF_PATH   "/etc/nginx/nginx.conf"
ENV NGINX_ERROR_LOG_PATH  "stderr"
ENV NGINX_HTTP_LOG_PATH   "/dev/stdout"
ENV NGINX_PID_PATH    "/var/run/nginx.pid"
ENV NGINX_LOCK_PATH   "/var/run/nginx.lock"

RUN apt update \
    && apt install -y git wget build-essential autoconf libtool automake golang cmake \
    && rm -rf ${BUILD_SRC} \
    && mkdir -p ${BUILD_SRC} \
    && mkdir -p ${BUILD_RELEASE} \
    && cd ${BUILD_SRC} \
    && wget -O- https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz | tar xz \
    && wget -O- https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VERSION}.tar.gz | tar xz \
    && wget -O- https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz | tar xz \
    # ngx_brotli & libbrotli
    && git clone https://github.com/google/ngx_brotli \
    && cd ngx_brotli \
    && git submodule update --init \
    && cd ${BUILD_SRC} \
    && wget -O- http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xz \
    && cd nginx-${NGINX_VERSION} \
    && ./configure \
        --add-module=../ngx_brotli \
        --with-openssl=../openssl-${OPENSSL_VERSION} \
        --with-openssl-opt='enable-tls1_3 enable-weak-ssl-ciphers' \
        --with-threads \
        --with-select_module \
        --with-poll_module \
        --with-pcre=../pcre-${PCRE_VERSION} \
        --with-zlib=../zlib-${ZLIB_VERSION} \
        --with-pcre-jit \
        --with-http_v2_module \
        --with-http_ssl_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-stream  \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-http_realip_module \
        --with-http_auth_request_module \
        --with-debug \
        --user=${NGINX_USER} \
        --group=${NGINX_GROUP} \
        --prefix=${NGINX_PREFIX} \
        --sbin-path=${NGINX_SBIN_PATH} \
        --conf-path=${NGINX_CONF_PATH} \
        --error-log-path=${NGINX_ERROR_LOG_PATH} \
        --http-log-path=${NGINX_HTTP_LOG_PATH} \
        --pid-path=${NGINX_PID_PATH} \
        --lock-path=${NGINX_LOCK_PATH} \
    && make \
    && cd ${BUILD_SRC} \
    && mkdir -p ${BUILD_RELEASE}${NGINX_PREFIX}/conf.d \
    && cp nginx-${NGINX_VERSION}/objs/nginx ${BUILD_RELEASE} \
    && cp nginx-${NGINX_VERSION}/conf/* ${BUILD_RELEASE}${NGINX_PREFIX}

FROM ubuntu:18.04

COPY --from=nginx-build /build/release/nginx /usr/sbin/nginx
COPY --from=nginx-build /build/release/etc/nginx /etc/nginx
COPY --from=nginx-build /build/release/etc/nginx /etc/nginx.sample

RUN set -x \
    && addgroup --system --gid 101 nginx \
    && adduser --system --disabled-login --ingroup nginx --no-create-home --home /nonexistent --gecos "nginx user" --shell /bin/false --uid 101 nginx \
    && apt update \
    && apt install -y openssl \
    && apt remove --purge --auto-remove -y \
    && mkdir -p /var/log/nginx \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
# create a docker-entrypoint.d directory
    && mkdir /docker-entrypoint.d

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80
EXPOSE 443

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]