# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/pq/ $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgdir = $(prefix)/share/taler/config.d/

pkgcfg_DATA = \
  exchangedb.conf \
  exchangedb-postgres.conf

sqldir = $(prefix)/share/taler/sql/exchange/

sqlinputs = \
  common-0001.sql \
  exchange-0001.sql.in \
  exchange-0001-part.sql \
  shard-0001-part.sql \
  shard-0001.sql.in

sql_DATA = \
  benchmark-0001.sql \
  versioning.sql \
  exchange-0001.sql \
  drop.sql \
  procedures.sql \
  shard-0001.sql

BUILT_SOURCES = \
  shard-0001.sql \
  exchange-0001.sql \
  drop.sql \
  procedures.sql

CLEANFILES = \
  shard-0001.sql \
  exchange-0001.sql

exchange-0001.sql: common-0001.sql exchange-0001-part.sql exchange-0001.sql.in
	chmod +w $@ || true
	gcc -E -P -undef - < exchange-0001.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

shard-0001.sql: common-0001.sql shard-0001-part.sql exchange-0001.sql.in
	chmod +w $@ || true
	gcc -E -P -undef - < shard-0001.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

EXTRA_DIST = \
  exchangedb.conf \
  exchangedb-postgres.conf \
  bench-db-postgres.conf \
  test-exchange-db-postgres.conf \
  $(sqlinputs) \
  $(sql_DATA) \
  pg_template.h pg_template.c \
  pg_template.sh

plugindir = $(libdir)/taler

if HAVE_POSTGRESQL
plugin_LTLIBRARIES = \
  libtaler_plugin_exchangedb_postgres.la
endif

libtaler_plugin_exchangedb_postgres_la_SOURCES = \
  plugin_exchangedb_common.c plugin_exchangedb_common.h \
  plugin_exchangedb_postgres.c pg_helper.h \
  pg_insert_aggregation_tracking.h pg_insert_aggregation_tracking.c \
  pg_select_aggregation_amounts_for_kyc_check.h pg_select_aggregation_amounts_for_kyc_check.c \
  pg_lookup_wire_fee_by_time.h pg_lookup_wire_fee_by_time.c \
  pg_select_satisfied_kyc_processes.h pg_select_satisfied_kyc_processes.c \
  pg_kyc_provider_account_lookup.h pg_kyc_provider_account_lookup.c \
  pg_lookup_kyc_requirement_by_row.h pg_lookup_kyc_requirement_by_row.c \
  pg_insert_kyc_requirement_for_account.h pg_insert_kyc_requirement_for_account.c \
  pg_lookup_kyc_process_by_account.h pg_lookup_kyc_process_by_account.c \
  pg_update_kyc_process_by_row.h pg_update_kyc_process_by_row.c \
  pg_insert_kyc_requirement_process.h pg_insert_kyc_requirement_process.c \
  pg_select_withdraw_amounts_for_kyc_check.h pg_select_withdraw_amounts_for_kyc_check.c \
  pg_select_merge_amounts_for_kyc_check.h pg_select_merge_amounts_for_kyc_check.c \
  pg_profit_drains_set_finished.h pg_profit_drains_set_finished.c \
  pg_profit_drains_get_pending.h pg_profit_drains_get_pending.c \
  pg_get_drain_profit.h pg_get_drain_profit.c \
  pg_get_purse_deposit.h pg_get_purse_deposit.c \
  pg_insert_contract.h pg_insert_contract.c \
  pg_select_contract.h pg_select_contract.c \
  pg_select_purse_merge.h pg_select_purse_merge.c \
  pg_select_contract_by_purse.h pg_select_contract_by_purse.c \
  pg_insert_drain_profit.h pg_insert_drain_profit.c \
  pg_do_reserve_purse.h pg_do_reserve_purse.c \
  pg_lookup_global_fee_by_time.h pg_lookup_global_fee_by_time.c \
  pg_do_purse_deposit.h pg_do_purse_deposit.c \
  pg_activate_signing_key.h pg_activate_signing_key.c \
  pg_update_auditor.h pg_update_auditor.c \
  pg_begin_revolving_shard.h pg_begin_revolving_shard.c \
  pg_get_extension_manifest.h pg_get_extension_manifest.c \
  pg_insert_history_request.h pg_insert_history_request.c \
  pg_do_purse_merge.h pg_do_purse_merge.c \
  pg_start_read_committed.h pg_start_read_committed.c \
  pg_start_read_only.h pg_start_read_only.c \
  pg_insert_denomination_info.h pg_insert_denomination_info.c \
  pg_do_batch_withdraw_insert.h pg_do_batch_withdraw_insert.c \
  pg_do_reserve_open.c pg_do_reserve_open.h \
  pg_do_withdraw.h pg_do_withdraw.c \
  pg_create_shard_tables.h pg_create_shard_tables.c \
  pg_preflight.h pg_preflight.c \
  pg_iterate_active_signkeys.h pg_iterate_active_signkeys.c \
  pg_commit.h pg_commit.c \
  pg_get_coin_transactions.c pg_get_coin_transactions.h \
  pg_get_expired_reserves.c pg_get_expired_reserves.h \
  pg_start.h pg_start.c \
  pg_rollback.h pg_rollback.c \
  pg_setup_partitions.h pg_setup_partitions.c \
  pg_get_purse_request.c pg_get_purse_request.h \
  pg_get_reserve_history.c pg_get_reserve_history.h \
  pg_get_unfinished_close_requests.c pg_get_unfinished_close_requests.h \
  pg_insert_close_request.c pg_insert_close_request.h \
  pg_delete_aggregation_transient.h pg_delete_aggregation_transient.c \
  pg_get_link_data.h pg_get_link_data.c \
  pg_drop_tables.h pg_drop_tables.c \
  pg_insert_purse_request.h pg_insert_purse_request.c \
  pg_insert_records_by_table.c pg_insert_records_by_table.h \
  pg_insert_reserve_open_deposit.c pg_insert_reserve_open_deposit.h \
  pg_iterate_kyc_reference.c pg_iterate_kyc_reference.h \
  pg_iterate_reserve_close_info.c pg_iterate_reserve_close_info.h \
  pg_lookup_records_by_table.c pg_lookup_records_by_table.h \
  pg_lookup_serial_by_table.c pg_lookup_serial_by_table.h \
  pg_select_reserve_close_info.c pg_select_reserve_close_info.h \
  pg_select_reserve_closed_above_serial_id.c pg_select_reserve_closed_above_serial_id.h \
  pg_select_purse.h pg_select_purse.c \
  pg_select_purse_requests_above_serial_id.h pg_select_purse_requests_above_serial_id.c \
  pg_select_purse_merges_above_serial_id.h pg_select_purse_merges_above_serial_id.c \
  pg_select_purse_deposits_above_serial_id.h pg_select_purse_deposits_above_serial_id.c \
  pg_select_account_merges_above_serial_id.h pg_select_account_merges_above_serial_id.c \
  pg_select_all_purse_decisions_above_serial_id.h pg_select_all_purse_decisions_above_serial_id.c \
  pg_select_reserve_open_above_serial_id.c pg_select_reserve_open_above_serial_id.h
libtaler_plugin_exchangedb_postgres_la_LIBADD = \
  $(LTLIBINTL)
libtaler_plugin_exchangedb_postgres_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS) \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lpq \
  -lpthread \
  -lgnunetpq \
  -lgnunetutil \
  -ljansson \
  $(XLIB)

lib_LTLIBRARIES = \
  libtalerexchangedb.la

libtalerexchangedb_la_SOURCES = \
  exchangedb_accounts.c \
  exchangedb_plugin.c \
  exchangedb_transactions.c
libtalerexchangedb_la_LIBADD = \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetutil \
  $(XLIB)
libtalerexchangedb_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 1:0:0 \
  -no-undefined


check_PROGRAMS = \
  test-exchangedb-postgres \
  bench-db-postgres

AM_TESTS_ENVIRONMENT=export TALER_PREFIX=$${TALER_PREFIX:-@libdir@};export PATH=$${TALER_PREFIX:-@prefix@}/bin:$$PATH;
TESTS = \
  test-exchangedb-postgres

test_exchangedb_postgres_SOURCES = \
  test_exchangedb.c
test_exchangedb_postgres_LDADD = \
  libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  $(XLIB)

bench_db_postgres_SOURCES = \
  bench_db.c
bench_db_postgres_LDADD = \
  libtalerexchangedb.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  -lgnunetpq \
  -lgnunetutil \
  $(XLIB)

EXTRA_test_exchangedb_postgres_DEPENDENCIES = \
  libtaler_plugin_exchangedb_postgres.la
