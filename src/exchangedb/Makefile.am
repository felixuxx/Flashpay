# This Makefile.am is in the public domain
AM_CPPFLAGS = -I$(top_srcdir)/src/include -I$(top_srcdir)/src/pq/ $(POSTGRESQL_CPPFLAGS)

if USE_COVERAGE
  AM_CFLAGS = --coverage -O0
  XLIB = -lgcov
endif

pkgcfgadir = $(prefix)/share/taler-auditor/config.d/
pkgcfgedir = $(prefix)/share/taler-exchange/config.d/

# Auditor also needs to access the exchange DB, so we install
# the exchange configuration for it here as well!
pkgcfga_DATA = \
  exchangedb.conf \
  exchangedb-postgres.conf

pkgcfge_DATA = \
  exchangedb.conf \
  exchangedb-postgres.conf

sqldir = $(prefix)/share/taler-exchange/sql/

sqlinputs = \
  exchange_do_*.sql \
  procedures.sql.in \
  0002-*.sql \
  0003-*.sql \
  0004-*.sql \
  0005-*.sql \
  0006-*.sql \
  0007-*.sql \
  exchange-0002.sql.in \
  exchange-0003.sql.in \
  exchange-0004.sql.in \
  exchange-0005.sql.in \
  exchange-0006.sql.in \
  exchange-0007.sql.in

sql_DATA = \
  benchmark-0001.sql \
  versioning.sql \
  auditor-triggers-0001.sql \
  exchange-0001.sql \
  exchange-0002.sql \
  exchange-0003.sql \
  exchange-0004.sql \
  exchange-0005.sql \
  exchange-0006.sql \
  exchange-0007.sql \
  drop.sql \
  procedures.sql

BUILT_SOURCES = \
  benchmark-0001.sql \
  drop.sql \
  exchange-0001.sql \
  procedures.sql

CLEANFILES = \
  exchange-0002.sql \
  exchange-0003.sql \
  exchange-0004.sql \
  exchange-0005.sql \
  exchange-0006.sql \
  exchange-0007.sql \
  procedures.sql

procedures.sql: procedures.sql.in exchange_do_*.sql
	chmod +w $@ 2> /dev/null || true
	gcc -E -P -undef - < procedures.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

exchange-0002.sql: exchange-0002.sql.in 0002-*.sql
	chmod +w $@ 2> /dev/null || true
	gcc -E -P -undef - < exchange-0002.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

exchange-0003.sql: exchange-0003.sql.in 0003-*.sql
	chmod +w $@ 2> /dev/null || true
	gcc -E -P -undef - < exchange-0003.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

exchange-0004.sql: exchange-0004.sql.in 0004-*.sql
	chmod +w $@ 2> /dev/null || true
	gcc -E -P -undef - < exchange-0004.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

exchange-0005.sql: exchange-0005.sql.in 0005-*.sql
	chmod +w $@ 2> /dev/null || true
	gcc -E -P -undef - < exchange-0005.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

exchange-0006.sql: exchange-0006.sql.in 0006-*.sql
	chmod +w $@ 2> /dev/null || true
	gcc -E -P -undef - < exchange-0006.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

exchange-0007.sql: exchange-0007.sql.in 0007-*.sql
	chmod +w $@ 2> /dev/null || true
	gcc -E -P -undef - < exchange-0007.sql.in 2>/dev/null | sed -e "s/--.*//" | awk 'NF' - >$@
	chmod ugo-w $@

check_SCRIPTS = \
  test_idempotency.sh

EXTRA_DIST = \
  exchangedb.conf \
  exchangedb-postgres.conf \
  bench-db-postgres.conf \
  test-exchange-db-postgres.conf \
  $(sqlinputs) \
  $(sql_DATA) \
  $(check_SCRIPTS) \
  pg_template.h pg_template.c \
  pg_template.sh

plugindir = $(libdir)/taler-exchange

if HAVE_POSTGRESQL
plugin_LTLIBRARIES = \
  libtaler_plugin_exchangedb_postgres.la
endif

libtaler_plugin_exchangedb_postgres_la_SOURCES = \
  pg_abort_shard.h pg_abort_shard.c \
  pg_activate_signing_key.h pg_activate_signing_key.c \
  pg_add_denomination_key.h pg_add_denomination_key.c \
  pg_add_policy_fulfillment_proof.h pg_add_policy_fulfillment_proof.c \
  pg_aggregate.h pg_aggregate.c \
  pg_batch_ensure_coin_known.h pg_batch_ensure_coin_known.c \
  pg_begin_revolving_shard.h pg_begin_revolving_shard.c \
  pg_begin_shard.h pg_begin_shard.c \
  pg_clear_aml_lock.h pg_clear_aml_lock.c \
  pg_commit.h pg_commit.c \
  pg_complete_shard.h pg_complete_shard.c \
  pg_compute_shard.h pg_compute_shard.c \
  pg_count_known_coins.h pg_count_known_coins.c \
  pg_create_aggregation_transient.h pg_create_aggregation_transient.c \
  pg_create_tables.h pg_create_tables.c \
  pg_delete_aggregation_transient.h pg_delete_aggregation_transient.c \
  pg_delete_shard_locks.h pg_delete_shard_locks.c \
  pg_do_age_withdraw.h pg_do_age_withdraw.c \
  pg_do_batch_withdraw.h pg_do_batch_withdraw.c \
  pg_do_batch_withdraw_insert.h pg_do_batch_withdraw_insert.c \
  pg_do_check_deposit_idempotent.h pg_do_check_deposit_idempotent.c \
  pg_do_deposit.h pg_do_deposit.c \
  pg_do_melt.h pg_do_melt.c \
  pg_do_purse_delete.c pg_do_purse_delete.h \
  pg_do_purse_deposit.h pg_do_purse_deposit.c \
  pg_do_purse_merge.h pg_do_purse_merge.c \
  pg_do_recoup.h pg_do_recoup.c \
  pg_do_recoup_refresh.h pg_do_recoup_refresh.c \
  pg_do_refund.h pg_do_refund.c \
  pg_do_reserve_open.c pg_do_reserve_open.h \
  pg_do_reserve_purse.h pg_do_reserve_purse.c \
  pg_drain_kyc_alert.h pg_drain_kyc_alert.c \
  pg_drop_tables.h pg_drop_tables.c \
  pg_ensure_coin_known.h pg_ensure_coin_known.c \
  pg_event_listen.h pg_event_listen.c \
  pg_event_listen_cancel.h pg_event_listen_cancel.c \
  pg_event_notify.h pg_event_notify.c \
  pg_expire_purse.h pg_expire_purse.c \
  pg_find_aggregation_transient.h pg_find_aggregation_transient.c \
  pg_gc.h pg_gc.c \
  pg_get_age_withdraw.h pg_get_age_withdraw.c \
  pg_get_coin_denomination.h pg_get_coin_denomination.c \
  pg_get_coin_transactions.c pg_get_coin_transactions.h \
  pg_get_denomination_info.h pg_get_denomination_info.c \
  pg_get_denomination_revocation.h pg_get_denomination_revocation.c \
  pg_get_drain_profit.h pg_get_drain_profit.c \
  pg_get_expired_reserves.c pg_get_expired_reserves.h \
  pg_get_extension_manifest.h pg_get_extension_manifest.c \
  pg_get_global_fee.h pg_get_global_fee.c \
  pg_get_global_fees.h pg_get_global_fees.c \
  pg_get_known_coin.h pg_get_known_coin.c \
  pg_get_kyc_rules.h pg_get_kyc_rules.c \
  pg_get_link_data.h pg_get_link_data.c \
  pg_get_melt.h pg_get_melt.c \
  pg_get_old_coin_by_h_blind.h pg_get_old_coin_by_h_blind.c \
  pg_get_pending_kyc_requirement_process.h pg_get_pending_kyc_requirement_process.c \
  pg_get_policy_details.h pg_get_policy_details.c \
  pg_get_purse_deposit.h pg_get_purse_deposit.c \
  pg_get_purse_request.c pg_get_purse_request.h \
  pg_get_ready_deposit.h pg_get_ready_deposit.c \
  pg_get_refresh_reveal.h pg_get_refresh_reveal.c \
  pg_get_reserve_balance.h pg_get_reserve_balance.c \
  pg_get_reserve_by_h_blind.h pg_get_reserve_by_h_blind.c \
  pg_get_reserve_history.c pg_get_reserve_history.h \
  pg_get_signature_for_known_coin.h pg_get_signature_for_known_coin.c \
  pg_get_unfinished_close_requests.c pg_get_unfinished_close_requests.h \
  pg_get_wire_accounts.h pg_get_wire_accounts.c \
  pg_get_wire_fee.h pg_get_wire_fee.c \
  pg_get_wire_fees.h pg_get_wire_fees.c \
  pg_get_wire_hash_for_contract.h pg_get_wire_hash_for_contract.c \
  pg_get_withdraw_info.h pg_get_withdraw_info.c \
  pg_have_deposit2.h pg_have_deposit2.c \
  pg_helper.h \
  pg_inject_auditor_triggers.h pg_inject_auditor_triggers.c \
  pg_insert_active_legitimization_measure.h pg_insert_active_legitimization_measure.c \
  pg_insert_aml_decision.h pg_insert_aml_decision.c \
  pg_insert_aml_officer.h pg_insert_aml_officer.c \
  pg_insert_aml_program_failure.h pg_insert_aml_program_failure.c \
  pg_insert_auditor.h pg_insert_auditor.c \
  pg_insert_auditor_denom_sig.h pg_insert_auditor_denom_sig.c \
  pg_insert_close_request.c pg_insert_close_request.h \
  pg_insert_contract.h pg_insert_contract.c \
  pg_insert_denomination_info.h pg_insert_denomination_info.c \
  pg_insert_denomination_revocation.h pg_insert_denomination_revocation.c \
  pg_insert_drain_profit.h pg_insert_drain_profit.c \
  pg_insert_global_fee.h pg_insert_global_fee.c \
  pg_insert_kyc_failure.h pg_insert_kyc_failure.c \
  pg_insert_kyc_measure_result.h pg_insert_kyc_measure_result.c \
  pg_insert_kyc_requirement_process.h pg_insert_kyc_requirement_process.c \
  pg_insert_partner.h pg_insert_partner.c \
  pg_insert_purse_request.h pg_insert_purse_request.c \
  pg_insert_records_by_table.c pg_insert_records_by_table.h \
  pg_insert_refresh_reveal.h pg_insert_refresh_reveal.c \
  pg_insert_refund.h pg_insert_refund.c \
  pg_insert_reserve_closed.h pg_insert_reserve_closed.c \
  pg_insert_reserve_open_deposit.c pg_insert_reserve_open_deposit.h \
  pg_insert_signkey_revocation.h pg_insert_signkey_revocation.c \
  pg_insert_successor_measure.h pg_insert_successor_measure.c \
  pg_insert_wire.h pg_insert_wire.c \
  pg_insert_wire_fee.h pg_insert_wire_fee.c \
  pg_iterate_active_auditors.h pg_iterate_active_auditors.c \
  pg_iterate_active_signkeys.h pg_iterate_active_signkeys.c \
  pg_iterate_auditor_denominations.h pg_iterate_auditor_denominations.c \
  pg_iterate_denomination_info.h pg_iterate_denomination_info.c \
  pg_iterate_denominations.h pg_iterate_denominations.c \
  pg_iterate_kyc_reference.c pg_iterate_kyc_reference.h \
  pg_iterate_reserve_close_info.c pg_iterate_reserve_close_info.h \
  pg_kyc_provider_account_lookup.h pg_kyc_provider_account_lookup.c \
  pg_kycauth_in_insert.h pg_kycauth_in_insert.c \
  pg_lookup_active_legitimization.h pg_lookup_active_legitimization.c \
  pg_lookup_aml_history.h pg_lookup_aml_history.c \
  pg_lookup_aml_officer.h pg_lookup_aml_officer.c \
  pg_lookup_auditor_status.h pg_lookup_auditor_status.c \
  pg_lookup_auditor_timestamp.h pg_lookup_auditor_timestamp.c \
  pg_lookup_completed_legitimization.h pg_lookup_completed_legitimization.c \
  pg_lookup_denomination_key.h pg_lookup_denomination_key.c \
  pg_lookup_global_fee_by_time.h pg_lookup_global_fee_by_time.c \
  pg_lookup_h_payto_by_access_token.h pg_lookup_h_payto_by_access_token.c \
  pg_lookup_kyc_history.h pg_lookup_kyc_history.c \
  pg_lookup_kyc_process_by_account.h pg_lookup_kyc_process_by_account.c \
  pg_lookup_kyc_requirement_by_row.h pg_lookup_kyc_requirement_by_row.c \
  pg_lookup_kyc_status_by_token.h pg_lookup_kyc_status_by_token.c \
  pg_lookup_pending_legitimization.h pg_lookup_pending_legitimization.c \
  pg_lookup_records_by_table.c pg_lookup_records_by_table.h \
  pg_lookup_rules_by_access_token.h pg_lookup_rules_by_access_token.c \
  pg_lookup_serial_by_table.c pg_lookup_serial_by_table.h \
  pg_lookup_signing_key.h pg_lookup_signing_key.c \
  pg_lookup_signkey_revocation.h pg_lookup_signkey_revocation.c \
  pg_lookup_transfer_by_deposit.h pg_lookup_transfer_by_deposit.c \
  pg_lookup_wire_fee_by_time.h pg_lookup_wire_fee_by_time.c \
  pg_lookup_wire_timestamp.h pg_lookup_wire_timestamp.c \
  pg_lookup_wire_transfer.h pg_lookup_wire_transfer.c \
  pg_persist_kyc_attributes.h pg_persist_kyc_attributes.c \
  pg_persist_policy_details.h pg_persist_policy_details.c \
  pg_preflight.h pg_preflight.c \
  pg_profit_drains_get_pending.h pg_profit_drains_get_pending.c \
  pg_profit_drains_set_finished.h pg_profit_drains_set_finished.c \
  pg_release_revolving_shard.h pg_release_revolving_shard.c \
  pg_reserves_get.h pg_reserves_get.c \
  pg_reserves_get_origin.h pg_reserves_get_origin.c \
  pg_reserves_in_insert.h pg_reserves_in_insert.c \
  pg_reserves_update.h pg_reserves_update.c \
  pg_rollback.h pg_rollback.c \
  pg_select_account_merges_above_serial_id.h pg_select_account_merges_above_serial_id.c \
  pg_select_aggregation_amounts_for_kyc_check.h pg_select_aggregation_amounts_for_kyc_check.c \
  pg_select_aggregation_transient.h pg_select_aggregation_transient.c \
  pg_select_aggregations_above_serial.h pg_select_aggregations_above_serial.c \
  pg_select_all_purse_decisions_above_serial_id.h pg_select_all_purse_decisions_above_serial_id.c \
  pg_select_aml_attributes.h pg_select_aml_attributes.c \
  pg_select_aml_decisions.h pg_select_aml_decisions.c \
  pg_select_aml_measures.h pg_select_aml_measures.c \
  pg_select_aml_statistics.h pg_select_aml_statistics.c \
  pg_select_auditor_denom_sig.h pg_select_auditor_denom_sig.c \
  pg_select_batch_deposits_missing_wire.h pg_select_batch_deposits_missing_wire.c \
  pg_select_coin_deposits_above_serial_id.h pg_select_coin_deposits_above_serial_id.c \
  pg_select_contract.h pg_select_contract.c \
  pg_select_contract_by_purse.h pg_select_contract_by_purse.c \
  pg_select_deposit_amounts_for_kyc_check.h pg_select_deposit_amounts_for_kyc_check.c \
  pg_select_kyc_attributes.h pg_select_kyc_attributes.c \
  pg_select_merge_amounts_for_kyc_check.h pg_select_merge_amounts_for_kyc_check.c \
  pg_select_purse.h pg_select_purse.c \
  pg_select_purse_by_merge_pub.h pg_select_purse_by_merge_pub.c \
  pg_select_purse_decisions_above_serial_id.h pg_select_purse_decisions_above_serial_id.c \
  pg_select_purse_deposits_above_serial_id.h pg_select_purse_deposits_above_serial_id.c \
  pg_select_purse_deposits_by_purse.h pg_select_purse_deposits_by_purse.c \
  pg_select_purse_merge.h pg_select_purse_merge.c \
  pg_select_purse_merges_above_serial_id.h pg_select_purse_merges_above_serial_id.c \
  pg_select_purse_requests_above_serial_id.h pg_select_purse_requests_above_serial_id.c \
  pg_select_recoup_above_serial_id.h pg_select_recoup_above_serial_id.c \
  pg_select_recoup_refresh_above_serial_id.h pg_select_recoup_refresh_above_serial_id.c \
  pg_select_refreshes_above_serial_id.h pg_select_refreshes_above_serial_id.c \
  pg_select_refunds_above_serial_id.h pg_select_refunds_above_serial_id.c \
  pg_select_refunds_by_coin.h pg_select_refunds_by_coin.c \
  pg_select_reserve_close_info.c pg_select_reserve_close_info.h \
  pg_select_reserve_closed_above_serial_id.c pg_select_reserve_closed_above_serial_id.h \
  pg_select_reserve_open_above_serial_id.c pg_select_reserve_open_above_serial_id.h \
  pg_select_reserves_in_above_serial_id.h pg_select_reserves_in_above_serial_id.c \
  pg_select_reserves_in_above_serial_id_by_account.h pg_select_reserves_in_above_serial_id_by_account.c \
  pg_select_wire_out_above_serial_id.h pg_select_wire_out_above_serial_id.c \
  pg_select_wire_out_above_serial_id_by_account.h pg_select_wire_out_above_serial_id_by_account.c \
  pg_select_withdraw_amounts_for_kyc_check.h pg_select_withdraw_amounts_for_kyc_check.c \
  pg_select_withdrawals_above_serial_id.h pg_select_withdrawals_above_serial_id.c \
  pg_set_aml_lock.h pg_set_aml_lock.c \
  pg_set_extension_manifest.h pg_set_extension_manifest.c \
  pg_set_purse_balance.h pg_set_purse_balance.c \
  pg_start.h pg_start.c \
  pg_start_deferred_wire_out.h pg_start_deferred_wire_out.c \
  pg_start_read_committed.h pg_start_read_committed.c \
  pg_start_read_only.h pg_start_read_only.c \
  pg_store_wire_transfer_out.h pg_store_wire_transfer_out.c \
  pg_test_aml_officer.h pg_test_aml_officer.c \
  pg_trigger_kyc_rule_for_account.h pg_trigger_kyc_rule_for_account.c \
  pg_update_aggregation_transient.h pg_update_aggregation_transient.c \
  pg_update_auditor.h pg_update_auditor.c \
  pg_update_kyc_process_by_row.h pg_update_kyc_process_by_row.c \
  pg_update_wire.h pg_update_wire.c \
  pg_wad_in_insert.h pg_wad_in_insert.c \
  pg_wire_prepare_data_get.h pg_wire_prepare_data_get.c \
  pg_wire_prepare_data_insert.h pg_wire_prepare_data_insert.c \
  pg_wire_prepare_data_mark_failed.h pg_wire_prepare_data_mark_failed.c \
  pg_wire_prepare_data_mark_finished.h pg_wire_prepare_data_mark_finished.c \
  plugin_exchangedb_common.c plugin_exchangedb_common.h \
  plugin_exchangedb_postgres.c plugin_exchangedb_postgres.h


libtaler_plugin_exchangedb_postgres_la_LDFLAGS = \
  $(TALER_PLUGIN_LDFLAGS)
libtaler_plugin_exchangedb_postgres_la_LIBADD = \
  $(LTLIBINTL) \
  $(top_builddir)/src/pq/libtalerpq.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetpq \
  -lgnunetutil \
  -ljansson \
  -lpq \
  $(XLIB)

lib_LTLIBRARIES = \
  libtalerexchangedb.la

libtalerexchangedb_la_SOURCES = \
  exchangedb_accounts.c \
  exchangedb_aml.c \
  exchangedb_history.c \
  exchangedb_plugin.c \
  exchangedb_transactions.c
libtalerexchangedb_la_LIBADD = \
  $(top_builddir)/src/bank-lib/libtalerbank.la \
  $(top_builddir)/src/kyclogic/libtalerkyclogic.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  -lgnunetjson \
  -lgnunetutil \
  -ljansson \
  -lcurl \
  $(XLIB)
libtalerexchangedb_la_LDFLAGS = \
  $(POSTGRESQL_LDFLAGS) \
  -version-info 1:0:0 \
  -no-undefined


check_PROGRAMS = \
  test-exchangedb-postgres

noinst_PROGRAMS = \
  bench-db-postgres\
  perf_get_link_data-postgres\
  perf_select_refunds_by_coin-postgres\
  perf_reserves_in_insert-postgres \
  perf_deposits_get_ready-postgres

AM_TESTS_ENVIRONMENT=export TALER_EXCHANGE_PREFIX=$${TALER_EXCHANGE_PREFIX:-@libdir@};export PATH=$${TALER_EXCHANGE_PREFIX:-@prefix@}/bin:$$PATH;
TESTS = \
  $(check_SCRIPTS) \
  $(check_PROGRAMS)

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

perf_reserves_in_insert_postgres_SOURCES = \
  perf_reserves_in_insert.c
perf_reserves_in_insert_postgres_LDADD = \
  libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  -lm \
  $(XLIB)

perf_select_refunds_by_coin_postgres_SOURCES = \
  perf_select_refunds_by_coin.c
perf_select_refunds_by_coin_postgres_LDADD = \
  libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  -lm \
  $(XLIB)

perf_get_link_data_postgres_SOURCES = \
  perf_get_link_data.c
perf_get_link_data_postgres_LDADD = \
  libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  -lm \
  $(XLIB)

perf_deposits_get_ready_postgres_SOURCES = \
  perf_deposits_get_ready.c
perf_deposits_get_ready_postgres_LDADD = \
  libtalerexchangedb.la \
  $(top_builddir)/src/json/libtalerjson.la \
  $(top_builddir)/src/util/libtalerutil.la \
  $(top_builddir)/src/pq/libtalerpq.la \
  -ljansson \
  -lgnunetjson \
  -lgnunetutil \
  -lm \
  $(XLIB)


EXTRA_test_exchangedb_postgres_DEPENDENCIES = \
  libtaler_plugin_exchangedb_postgres.la
