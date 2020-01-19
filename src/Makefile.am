# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include
if HAVE_POSTGRESQL
  PQ_DIR = pq
endif

pkgcfgdir = $(prefix)/share/taler/config.d/
pkgcfg_DATA = \
  taler.conf

EXTRA_DIST = \
  taler.conf

SUBDIRS = \
  include \
  util \
  json \
  curl \
  $(PQ_DIR) \
  mhd \
  bank-lib \
  exchangedb \
  exchange \
  exchange-tools \
  auditordb \
  auditor \
  lib \
  testing \
  benchmark
