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
  taler-wire-auditor \
  taler-auditor-sign

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
