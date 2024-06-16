# This file is separate as trixie does not offer a stable riscv on docker yet.
FROM docker.io/library/debian:unstable

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -yqq && \
  apt-get upgrade -yqq && \
  apt-get install -yqq \
    git \
    autoconf \
    libextractor-dev \
    libjansson-dev \
    libgcrypt-dev \
    libqrencode-dev \
    libpq-dev \
    libmicrohttpd-dev \
    pkg-config \
    libtool \
    recutils \
    make \
    python3-sphinx \
    python3-sphinx-book-theme \
    python3-sphinx-multiversion \
    python3-sphinx-rtd-theme \
    texinfo \
    autopoint \
    curl \
    libcurl4-openssl-dev \
    libsodium-dev \
    libidn11-dev \
    zlib1g-dev \
    libunistring-dev \
    iptables

# Debian packaging tools
RUN apt-get install -yqq \
                  po-debconf \
                  build-essential \
                  debhelper-compat \
                  devscripts \
                  git-buildpackage \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /workdir

CMD ["/bin/bash"]
