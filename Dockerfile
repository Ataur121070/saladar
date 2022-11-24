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
