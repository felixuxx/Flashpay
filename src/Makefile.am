# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include
if HAVE_POSTGRESQL
  PQ_DIR = pq
endif
if HAVE_SQLITE
  SQ_DIR = sq
endif

pkgcfgdir = $(prefix)/share/taler-exchange/config.d/
pkgcfg_DATA = \
  taler-exchange.conf

EXTRA_DIST = \
  $(pkgcfg_DATA)

SUBDIRS = \
  include \
  util \
  json \
  extensions \
  curl \
  $(PQ_DIR) \
  $(SQ_DIR) \
  mhd \
  templating \
  bank-lib \
  kyclogic \
  exchangedb \
  exchange \
  auditordb \
  auditor \
  lib \
  exchange-tools \
  extensions/age_restriction \
  testing \
  benchmark
