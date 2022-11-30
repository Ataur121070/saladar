# syntax=docker/dockerfile:1.4

ARG PACKAGE_TYPE=deb
ARG ARCHITECTURE=amd64

# List out all image permutation to trick dependabot
FROM ghcr.io/hutchic/kong-openresty:1.0.3-x86_64-linux-gnu as amd64-deb
FROM ghcr.io/hutchic/kong-openresty:1.0.3-x86_64-linux-gnu as amd64-rpm
FROM ghcr.io/hutchic/kong-openresty:1.0.3-x86_64-linux-musl as amd64-apk
FROM ghcr.io/hutchic/kong-openresty:1.0.3-aarch64-linux-gnu as arm64-deb
FROM ghcr.io/hutchic/kong-openresty:1.0.3-aarch64-linux-gnu as arm64-rpm
FROM ghcr.io/hutchic/kong-openresty:1.0.3-aarch64-linux-musl as arm64-apk


FROM $ARCHITECTURE-$PACKAGE_TYPE as build

RUN rm -rf /kong && rm -rf /distribution/*

COPY . /kong
WORKDIR /kong
RUN ./install-kong.sh && \
    cp -r /tmp/build/* / && \
    ./install-test.sh && \
    kong version


# COPY --from doesn't support args so use an intermediary image
FROM build-$ARCHITECTURE-$PACKAGE_TYPE as build-result


# Use FPM to change the contents of /tmp/build into a deb / rpm / apk.tar.gz
FROM kong/fpm:0.5.1 as fpm

COPY --from=build-result /tmp/build /tmp/build
COPY --link /fpm /fpm

# Keep sync'd with the fpm/package.sh variables
ARG PACKAGE_TYPE=deb
ENV PACKAGE_TYPE=${PACKAGE_TYPE}

ARG KONG_VERSION=3.0.1
ENV KONG_VERSION=${KONG_VERSION}

ARG OPERATING_SYSTEM=ubuntu
ENV OPERATING_SYSTEM=${OPERATING_SYSTEM}

ARG OPERATING_SYSTEM_VERSION="22.04"
ENV OPERATING_SYSTEM_VERSION=${OPERATING_SYSTEM_VERSION}

ARG ARCHITECTURE=amd64
ENV ARCHITECTURE=${ARCHITECTURE}

WORKDIR /fpm
RUN ./package.sh


# Drop the fpm results into scratch so buildx can export it
FROM scratch as package

COPY --from=fpm /output/* /


FROM kong/kong-build-tools:deb-1.6.4 as develop

COPY --from=build-result /tmp/build /

ENV PATH=$PATH:/kong/bin:/usr/local/openresty/bin/:/usr/local/kong/bin/:/usr/local/openresty/nginx/sbin/
ENV LUA_PATH=/kong/?.lua;/kong/?/init.lua;/root/.luarocks/share/lua/5.1/?.lua;/root/.luarocks/share/lua/5.1/?/init.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;./?.lua;/usr/local/openresty/luajit/share/luajit-2.1.0-beta3/?.lua;/usr/local/openresty/luajit/share/lua/5.1/?.lua;/usr/local/openresty/luajit/share/lua/5.1/?/init.lua
ENV LUA_CPATH=/root/.luarocks/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/?.so;./?.so;/usr/local/openresty/luajit/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so

RUN rm -rf /usr/local/bin/kong
RUN ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
    ca-certificates \
    tzdata \
    vim \
    jq \
    httpie \
    iputils-ping \
    net-tools \
    valgrind \
    net-tools && \
    dpkg-reconfigure --frontend noninteractive tzdata && \
    apt-get install -y postgresql

RUN curl -L https://cpanmin.us | perl - App::cpanminus \
    && cpanm --notest Test::Nginx \
    && cpanm --notest local::lib

COPY . /kong
WORKDIR /kong
RUN ./fpm/after-install.sh && \
    git config --global --add safe.directory /kong && \
    make dev
