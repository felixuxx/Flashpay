# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include
if HAVE_POSTGRESQL
  PQ_DIR = pq
endif
if HAVE_SQLITE
  SQ_DIR = sq
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
  $(SQ_DIR) \
  mhd \
  bank-lib \
  exchangedb \
  exchange \
  auditordb \
  auditor \
  lib \
  exchange-tools \
  testing \
  benchmark
