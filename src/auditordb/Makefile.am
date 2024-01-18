# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/pq/ $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  auditordb-postgres.conf

sqldir = $(prefix)/share/taler/sql/auditor/

sqlinputs = \
  0002-*.sql \
  auditor-0002.sql.in \
  auditor_do_*.sql \
  procedures.sql.in

sql_DATA = \
  versioning.sql \
  auditor-0001.sql \
  auditor-0002.sql \
  drop.sql \
  restart.sql \
  procedures.sql

CLEANFILES = \
  auditor-0002.sql

procedures.sql: procedures.sql.in auditor_do_*.sql
	chmod +w $@ || true
	gcc -E -P -undef - < procedures.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

auditor-0002.sql: auditor-0002.sql.in 0002-*.sql
	chmod +w $@ || true
	gcc -E -P -undef - < auditor-0002.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@


EXTRA_DIST = \
  auditordb-postgres.conf \
  test-auditor-db-postgres.conf \
  $(sqlinputs) \
  $(sql_DATA) \
  pg_template.h pg_template.c \
  pg_template.sh

plugindir = $(libdir)/taler

if HAVE_POSTGRESQL
plugin_LTLIBRARIES = \
  libtaler_plugin_auditordb_postgres.la
endif

libtaler_plugin_auditordb_postgres_la_SOURCES = \
  plugin_auditordb_postgres.c pg_helper.h \
  pg_delete_deposit_confirmations.c pg_delete_deposit_confirmations.h \
  pg_delete_pending_deposit.c pg_delete_pending_deposit.h \
  pg_delete_purse_info.c pg_delete_purse_info.h \
  pg_del_denomination_balance.h pg_del_denomination_balance.c \
  pg_del_reserve_info.c pg_del_reserve_info.h \
  pg_get_auditor_progress.c pg_get_auditor_progress.h \
  pg_get_balance.c pg_get_balance.h \
  pg_get_denomination_balance.c pg_get_denomination_balance.h \
  pg_get_deposit_confirmations.c pg_get_deposit_confirmations.h \
  pg_get_purse_info.c pg_get_purse_info.h \
  pg_get_reserve_info.c pg_get_reserve_info.h \
  pg_get_wire_fee_summary.c pg_get_wire_fee_summary.h \
  pg_insert_auditor_progress.c pg_insert_auditor_progress.h \
  pg_insert_balance.c pg_insert_balance.h \
  pg_insert_denomination_balance.c pg_insert_denomination_balance.h \
  pg_insert_deposit_confirmation.c pg_insert_deposit_confirmation.h \
  pg_insert_exchange_signkey.c pg_insert_exchange_signkey.h \
  pg_insert_historic_denom_revenue.c pg_insert_historic_denom_revenue.h \
  pg_insert_historic_reserve_revenue.c pg_insert_historic_reserve_revenue.h \
  pg_insert_pending_deposit.c pg_insert_pending_deposit.h \
  pg_insert_purse_info.c pg_insert_purse_info.h \
  pg_insert_reserve_info.c pg_insert_reserve_info.h \
  pg_select_historic_denom_revenue.c pg_select_historic_denom_revenue.h \
  pg_select_historic_reserve_revenue.c pg_select_historic_reserve_revenue.h \
  pg_select_pending_deposits.c pg_select_pending_deposits.h \
  pg_select_purse_expired.c pg_select_purse_expired.h \
  pg_update_auditor_progress.c pg_update_auditor_progress.h \
  pg_update_balance.c pg_update_balance.h \
  pg_update_denomination_balance.c pg_update_denomination_balance.h \
  pg_update_purse_info.c pg_update_purse_info.h \
  pg_update_reserve_info.c pg_update_reserve_info.h \
  pg_update_wire_fee_summary.c pg_update_wire_fee_summary.h
libtaler_plugin_auditordb_postgres_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS)
libtaler_plugin_auditordb_postgres_la_LIBADD = \
  $(LTLIBINTL) \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetpq \
  -lgnunetutil \
  -lpq \
  $(XLIB)

lib_LTLIBRARIES = \
  libtalerauditordb.la

libtalerauditordb_la_SOURCES = \
  auditordb_plugin.c
libtalerauditordb_la_LIBADD = \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil  $(XLIB)
libtalerauditordb_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 0:0:0 \
  -no-undefined


#EXTRA_test_auditordb_postgres_DEPENDENCIES = \
#  libtaler_plugin_auditordb_postgres.la


check_PROGRAMS = \
  test_auditordb_checkpoints-postgres \
  test_auditordb-postgres

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;
TESTS = \
  test_auditordb_checkpoints-postgres \
  test_auditordb-postgres

test_auditordb_checkpoints_postgres_SOURCES = \
  test_auditordb_checkpoints.c
test_auditordb_checkpoints_postgres_LDADD = \
  libtalerauditordb.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  -lgnunetutil  \
  $(XLIB)

test_auditordb_postgres_SOURCES = \
  test_auditordb.c
test_auditordb_postgres_LDADD = \
  libtalerauditordb.la \
  $(top_srcdir)/src/pq/libtalerpq.la \
  $(top_srcdir)/src/util/libtalerutil.la \
  -lgnunetutil  \
  $(XLIB)
