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
  taler-auditor-dbinit \
  taler-auditor-exchange \
  taler-auditor-httpd \
  taler-helper-auditor-aggregation \
  taler-helper-auditor-coins \
  taler-helper-auditor-deposits \
  taler-helper-auditor-reserves \
  taler-helper-auditor-wire

bin_SCRIPTS = \
  taler-auditor \
  taler-helper-auditor-render.py

edit_script = $(SED) -e 's,%pkgdatadir%,$(pkgdatadir),'g $(NULL)

taler-auditor: taler-auditor.in
	rm -f $@ $@.tmp && \
	$(edit_script) $< >$@.tmp && \
	chmod a-w+x $@.tmp && \
	mv $@.tmp $@

lib_LTLIBRARIES = \
  libauditorreport.la

libauditorreport_la_SOURCES = \
  report-lib.c report-lib.h
libauditorreport_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  -lgnunetutil $(XLIB)

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

taler_helper_auditor_reserves_SOURCES = \
  taler-helper-auditor-reserves.c
taler_helper_auditor_reserves_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_coins_SOURCES = \
  taler-helper-auditor-coins.c
taler_helper_auditor_coins_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_aggregation_SOURCES = \
  taler-helper-auditor-aggregation.c
taler_helper_auditor_aggregation_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_deposits_SOURCES = \
  taler-helper-auditor-deposits.c
taler_helper_auditor_deposits_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

taler_helper_auditor_wire_SOURCES = \
  taler-helper-auditor-wire.c
taler_helper_auditor_wire_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/exchangedb/libtalerexchangedb.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  libauditorreport.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetcurl \
  -lgnunetutil \
  $(XLIB)


taler_auditor_httpd_SOURCES = \
  taler-auditor-httpd.c taler-auditor-httpd.h \
  taler-auditor-httpd_deposit-confirmation.c taler-auditor-httpd_deposit-confirmation.h \
  taler-auditor-httpd_exchanges.c taler-auditor-httpd_exchanges.h \
  taler-auditor-httpd_mhd.c taler-auditor-httpd_mhd.h
taler_auditor_httpd_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/mhd/libtalermhd.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  -lmicrohttpd \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  -lz \
  $(XLIB)

taler_auditor_exchange_SOURCES = \
  taler-auditor-exchange.c
taler_auditor_exchange_LDADD = \
  $(LIBGCRYPT_LIBS) \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/auditordb/libtalerauditordb.la \
  -lgnunetutil \
  $(XLIB)

check_SCRIPTS = \
  test-auditor.sh \
  test-revocation.sh

.NOTPARALLEL:
TESTS = $(check_SCRIPTS)

EXTRA_DIST = \
  taler-auditor.in \
  taler-helper-auditor-render.py \
  auditor.conf \
  test-auditor.conf \
  generate-auditor-basedb.sh \
  generate-revoke-basedb.sh \
  generate-auditor-basedb.conf \
  generate-auditor-basedb-template.conf \
  $(check_SCRIPTS) \
  auditor-basedb.age \
  auditor-basedb.sql \
  auditor-basedb.mpub \
  revoke-basedb.age \
  revoke-basedb.sql \
  revoke-basedb.mpub
