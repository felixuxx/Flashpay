# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  auditor.conf

bin_PROGRAMS = \
  taler-auditor \
  taler-auditor-httpd \
  taler-wire-auditor \
  taler-auditor-sign \
  taler-auditor-dbinit

taler_auditor_dbinit_SOURCES = \
  taler-auditor-dbinit.c
taler_auditor_dbinit_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  -lgnunetutil  $(XLIB)
taler_auditor_dbinit_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS)
taler_auditor_dbinit_CPPFLAGS = \
  -I$(top_srcdir)/src/include \
  -I$(top_srcdir)/src/pq/ \
  $(POSTGRESQL_CPPFLAGS)

taler_auditor_SOURCES = \
  taler-auditor.c
taler_auditor_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/wire/libtalerwire.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil

taler_auditor_httpd_SOURCES = \
  taler-auditor-httpd.c taler-auditor-httpd.h \
  taler-auditor-httpd_db.c taler-auditor-httpd_db.h \
  taler-auditor-httpd_deposit-confirmation.c taler-auditor-httpd_deposit-confirmation.h \
  taler-auditor-httpd_mhd.c taler-auditor-httpd_mhd.h \
  taler-auditor-httpd_parsing.c taler-auditor-httpd_parsing.h \
  taler-auditor-httpd_responses.c taler-auditor-httpd_responses.h
taler_auditor_httpd_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/wire/libtalerwire.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  -lmicrohttpd \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  -lz

taler_wire_auditor_SOURCES = \
  taler-wire-auditor.c
taler_wire_auditor_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/wire/libtalerwire.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil

taler_auditor_sign_SOURCES = \
  taler-auditor-sign.c
taler_auditor_sign_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -lgnunetutil $(XLIB)



EXTRA_DIST = \
  auditor.conf
