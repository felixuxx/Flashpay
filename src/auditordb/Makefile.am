# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/pq/ $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler-auditor/config.d/

pkgcfg_DATA = \
  auditordb-postgres.conf

sqldir = $(prefix)/share/taler-auditor/sql/

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
	chmod +w $@ 2> /dev/null || true
	gcc -E -P -undef - < procedures.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

auditor-0002.sql: auditor-0002.sql.in 0002-*.sql
	chmod +w $@ 2> /dev/null || true
	gcc -E -P -undef - < auditor-0002.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@


EXTRA_DIST = \
  auditordb-postgres.conf \
  test-auditor-db-postgres.conf \
  $(sqlinputs) \
  $(sql_DATA) \
  pg_template.h pg_template.c \
  pg_template.sh

plugindir = $(libdir)/taler-auditor

if HAVE_POSTGRESQL
plugin_LTLIBRARIES = \
  libtaler_plugin_auditordb_postgres.la
endif

# MARK: CRUD

libtaler_plugin_auditordb_postgres_la_SOURCES = \
  plugin_auditordb_postgres.c \
  pg_helper.h pg_helper.c \
  pg_delete_generic.c pg_delete_generic.h \
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
  pg_get_progress_points.h pg_get_progress_points.c \
  pg_insert_historic_reserve_revenue.c pg_insert_historic_reserve_revenue.h \
  pg_insert_pending_deposit.c pg_insert_pending_deposit.h \
  pg_insert_purse_info.c pg_insert_purse_info.h \
  pg_insert_reserve_info.c pg_insert_reserve_info.h \
  pg_select_historic_denom_revenue.c pg_select_historic_denom_revenue.h \
  pg_select_historic_reserve_revenue.c pg_select_historic_reserve_revenue.h \
  pg_select_pending_deposits.c pg_select_pending_deposits.h \
  pg_select_purse_expired.c pg_select_purse_expired.h \
  pg_update_generic_suppressed.c pg_update_generic_suppressed.h \
  pg_update_auditor_progress.c pg_update_auditor_progress.h \
  pg_update_denomination_balance.c pg_update_denomination_balance.h \
  pg_update_purse_info.c pg_update_purse_info.h \
  pg_update_reserve_info.c pg_update_reserve_info.h \
  pg_update_wire_fee_summary.c pg_update_wire_fee_summary.h \
  pg_get_amount_arithmetic_inconsistency.c pg_get_amount_arithmetic_inconsistency.h \
  pg_get_coin_inconsistency.c pg_get_coin_inconsistency.h \
  pg_get_row_inconsistency.c pg_get_row_inconsistency.h \
  pg_insert_amount_arithmetic_inconsistency.c pg_insert_amount_arithmetic_inconsistency.h \
  pg_insert_coin_inconsistency.c pg_insert_coin_inconsistency.h \
  pg_insert_row_inconsistency.c pg_insert_row_inconsistency.h \
  pg_insert_emergency.c pg_insert_emergency.h \
  pg_get_emergency.c pg_get_emergency.h \
  pg_insert_emergency_by_count.c pg_insert_emergency_by_count.h \
  pg_get_emergency_by_count.c pg_get_emergency_by_count.h \
  pg_insert_denomination_key_validity_withdraw_inconsistency.c pg_insert_denomination_key_validity_withdraw_inconsistency.h \
  pg_get_denomination_key_validity_withdraw_inconsistency.c pg_get_denomination_key_validity_withdraw_inconsistency.h \
  pg_insert_purse_not_closed_inconsistencies.c pg_insert_purse_not_closed_inconsistencies.h \
  pg_get_purse_not_closed_inconsistencies.c pg_get_purse_not_closed_inconsistencies.h \
  pg_insert_reserve_balance_insufficient_inconsistency.c pg_insert_reserve_balance_insufficient_inconsistency.h \
  pg_get_reserve_balance_insufficient_inconsistency.c pg_get_reserve_balance_insufficient_inconsistency.h \
  pg_insert_bad_sig_losses.c pg_insert_bad_sig_losses.h \
  pg_get_bad_sig_losses.c pg_get_bad_sig_losses.h \
  pg_insert_auditor_closure_lags.c pg_insert_auditor_closure_lags.h \
  pg_get_auditor_closure_lags.c pg_get_auditor_closure_lags.h \
  pg_insert_refreshes_hanging.c pg_insert_refreshes_hanging.h \
  pg_get_refreshes_hanging.c pg_get_refreshes_hanging.h \
  pg_get_reserve_in_inconsistency.c pg_get_reserve_in_inconsistency.h \
  pg_lookup_reserve_in_inconsistency.c pg_lookup_reserve_in_inconsistency.h \
  pg_insert_reserve_in_inconsistency.c pg_insert_reserve_in_inconsistency.h \
  pg_get_reserve_not_closed_inconsistency.c pg_get_reserve_not_closed_inconsistency.h \
  pg_insert_reserve_not_closed_inconsistency.c pg_insert_reserve_not_closed_inconsistency.h \
  pg_get_denominations_without_sigs.c pg_get_denominations_without_sigs.h \
  pg_insert_denominations_without_sigs.c pg_insert_denominations_without_sigs.h \
  pg_get_misattribution_in_inconsistency.c pg_get_misattribution_in_inconsistency.h \
  pg_insert_misattribution_in_inconsistency.c pg_insert_misattribution_in_inconsistency.h \
  pg_update_balance.c pg_update_balance.h \
  pg_get_reserves.c pg_get_reserves.h \
  pg_get_purses.c pg_get_purses.h \
  pg_insert_historic_denom_revenue.c pg_insert_historic_denom_revenue.h \
  pg_get_denomination_pending.c pg_get_denomination_pending.h \
  pg_insert_denomination_pending.c pg_insert_denomination_pending.h \
  pg_get_exchange_signkeys.c pg_get_exchange_signkeys.h \
  pg_get_wire_format_inconsistency.c pg_get_wire_format_inconsistency.h \
  pg_insert_wire_format_inconsistency.c pg_insert_wire_format_inconsistency.h \
  pg_get_wire_out_inconsistency.c pg_get_wire_out_inconsistency.h \
  pg_insert_wire_out_inconsistency.c pg_insert_wire_out_inconsistency.h \
  pg_delete_wire_out_inconsistency_if_matching.c pg_delete_wire_out_inconsistency_if_matching.h \
  pg_get_reserve_balance_summary_wrong_inconsistency.c pg_get_reserve_balance_summary_wrong_inconsistency.h \
  pg_insert_reserve_balance_summary_wrong_inconsistency.c pg_insert_reserve_balance_summary_wrong_inconsistency.h \
  pg_get_row_minor_inconsistencies.c pg_get_row_minor_inconsistencies.h \
  pg_insert_row_minor_inconsistencies.c pg_insert_row_minor_inconsistencies.h \
  pg_get_fee_time_inconsistency.c pg_get_fee_time_inconsistency.h \
  pg_insert_fee_time_inconsistency.c pg_insert_fee_time_inconsistency.h \
  pg_get_balances.c pg_get_balances.h \
  pg_insert_exchange_signkey.c pg_insert_exchange_signkey.h

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

AM_TESTS_ENVIRONMENT=export TALER_EXCHANGE_PREFIX=$${TALER_EXCHANGE_PREFIX:-@libdir@};export PATH=$${TALER_EXCHANGE_PREFIX:-@prefix@}/bin:$$PATH;export TALER_AUDITOR_PREFIX=$${TALER_AUDITOR_PREFIX:-@libdir@};

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
