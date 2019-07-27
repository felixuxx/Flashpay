/*
  This file is part of TALER
  Copyright (C) 2014--2019 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file plugin_exchangedb_postgres.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Florian Dold
 * @author Christian Grothoff
 * @author Sree Harsha Totakura
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_pq_lib.h"
#include "taler_exchangedb_plugin.h"
#include <pthread.h>
#include <libpq-fe.h>

#include "plugin_exchangedb_common.c"

/**
 * Set to 1 to enable Postgres auto_explain module. This will
 * slow down things a _lot_, but also provide extensive logging
 * in the Postgres database logger for performance analysis.
 */
#define AUTO_EXPLAIN 1

/**
 * Log a really unexpected PQ error with all the details we can get hold of.
 *
 * @param result PQ result object of the PQ operation that failed
 * @param conn SQL connection that was used
 */
#define BREAK_DB_ERR(result,conn) do {                                      \
    GNUNET_break (0); \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, \
                "Database failure: %s/%s/%s/%s/%s", \
                PQresultErrorField (result, PG_DIAG_MESSAGE_PRIMARY), \
                PQresultErrorField (result, PG_DIAG_MESSAGE_DETAIL), \
                PQresultErrorMessage (result), \
                PQresStatus (PQresultStatus (result)), \
                PQerrorMessage (conn)); \
  } while (0)


/**
 * Handle for a database session (per-thread, for transactions).
 */
struct TALER_EXCHANGEDB_Session
{
  /**
   * Postgres connection handle.
   */
  PGconn *conn;

  /**
   * Name of the current transaction, for debugging.
   */
  const char *transaction_name;

};


/**
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct PostgresClosure
{

  /**
   * Thread-local database connection.
   * Contains a pointer to `PGconn` or NULL.
   */
  pthread_key_t db_conn_threadlocal;

  /**
   * Database connection string, as read from
   * the configuration.
   */
  char *connection_cfg_str;

  /**
   * After how long should idle reserves be closed?
   */
  struct GNUNET_TIME_Relative idle_reserve_expiration_time;

  /**
   * After how long should reserves that have seen withdraw operations
   * be garbage collected?
   */
  struct GNUNET_TIME_Relative legal_reserve_expiration_time;
};


/**
 * Drop all Taler tables.  This should only be used by testcases.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static int
postgres_drop_tables (void *cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS kyc_events CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS kyc_merchants CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS prewire CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS payback CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS payback_refresh CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS aggregation_tracking CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS wire_out CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS wire_fee CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS deposits CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS refunds CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS refresh_commitments CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS refresh_revealed_coins CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS refresh_transfer_keys CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS known_coins CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS reserves_close CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS reserves_out CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS reserves_in CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS reserves CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS denomination_revocations CASCADE;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS denominations CASCADE;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };
  PGconn *conn;
  int ret;

  /* FIXME: use GNUNET_PQ_connect_with_cfg instead? */
  conn = GNUNET_PQ_connect (pc->connection_cfg_str);
  if (NULL == conn)
    return GNUNET_SYSERR;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Dropping ALL tables\n");
  ret = GNUNET_PQ_exec_statements (conn,
                                   es);
  PQfinish (conn);
  return ret;
}


/**
 * Create the necessary tables if they are not present
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static int
postgres_create_tables (void *cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    /* Denomination table for holding the publicly available information of
       denominations keys.  The denominations are to be referred to using
       foreign keys. */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS denominations"
                            "(denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)"
                            ",denom_pub BYTEA NOT NULL"
                            ",master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
                            ",master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)"
                            ",valid_from INT8 NOT NULL"
                            ",expire_withdraw INT8 NOT NULL"
                            ",expire_deposit INT8 NOT NULL"
                            ",expire_legal INT8 NOT NULL"
                            ",coin_val INT8 NOT NULL" /* value of this denom */
                            ",coin_frac INT4 NOT NULL" /* fractional value of this denom */
                            ",coin_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL" /* assuming same currency for fees */
                            ",fee_withdraw_val INT8 NOT NULL"
                            ",fee_withdraw_frac INT4 NOT NULL"
                            ",fee_withdraw_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                            ",fee_deposit_val INT8 NOT NULL"
                            ",fee_deposit_frac INT4 NOT NULL"
                            ",fee_deposit_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                            ",fee_refresh_val INT8 NOT NULL"
                            ",fee_refresh_frac INT4 NOT NULL"
                            ",fee_refresh_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                            ",fee_refund_val INT8 NOT NULL"
                            ",fee_refund_frac INT4 NOT NULL"
                            ",fee_refund_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                            ")"),
    /* index for gc_denominations */
    GNUNET_PQ_make_try_execute ("CREATE INDEX denominations_expire_legal_index ON "
                                "denominations (expire_legal);"),

    /* denomination_revocations table is for remembering which denomination keys have been revoked */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS denomination_revocations"
                            "(denom_revocations_serial_id BIGSERIAL UNIQUE"
                            ",denom_pub_hash BYTEA PRIMARY KEY REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE"
                            ",master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)"
                            ");"),
    /* reserves table is for summarization of a reserve.  It is updated when new
       funds are added and existing funds are withdrawn.  The 'expiration_date'
       can be used to eventually get rid of reserves that have not been used
       for a very long time (either by refunding the owner or by greedily
       grabbing the money, depending on the Exchange's terms of service) */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS reserves"
                            "(reserve_pub BYTEA PRIMARY KEY CHECK(LENGTH(reserve_pub)=32)"
                            ",account_details TEXT NOT NULL "
                            ",current_balance_val INT8 NOT NULL"
                            ",current_balance_frac INT4 NOT NULL"
                            ",current_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                            ",expiration_date INT8 NOT NULL"
                            ",gc_date INT8 NOT NULL"
                            ");"),
    /* index on reserves table (TODO: useless due to primary key!?) */
    GNUNET_PQ_make_try_execute ("CREATE INDEX reserves_reserve_pub_index ON "
                                "reserves (reserve_pub);"),
    /* index for get_expired_reserves */
    GNUNET_PQ_make_try_execute ("CREATE INDEX reserves_expiration_index"
                                " ON reserves (expiration_date,current_balance_val,current_balance_frac);"),
    /* index for reserve GC operations */
    GNUNET_PQ_make_try_execute ("CREATE INDEX reserves_gc_index"
                                " ON reserves (gc_date);"),
    /* reserves_in table collects the transactions which transfer funds
       into the reserve.  The rows of this table correspond to each
       incoming transaction. */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS reserves_in"
                           "(reserve_in_serial_id BIGSERIAL UNIQUE"
                           ",reserve_pub BYTEA NOT NULL REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
                           ",wire_reference BYTEA NOT NULL"
                           ",credit_val INT8 NOT NULL"
                           ",credit_frac INT4 NOT NULL"
                           ",credit_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ",sender_account_details TEXT NOT NULL"
                           ",exchange_account_section TEXT NOT NULL"
                           ",execution_date INT8 NOT NULL"
                           ",PRIMARY KEY (reserve_pub, wire_reference)"
                           ");"),
    /* Create indices on reserves_in */
    GNUNET_PQ_make_try_execute ("CREATE INDEX reserves_in_execution_index"
                                " ON reserves_in (exchange_account_section,execution_date);"),
    /* TODO: verify this actually helps, given the PRIMARY_KEY already includes
       reserve_pub as the first dimension! */
    GNUNET_PQ_make_try_execute ("CREATE INDEX reserves_in_reserve_pub"
                                " ON reserves_in (reserve_pub);"),
    GNUNET_PQ_make_try_execute ("CREATE INDEX reserves_in_exchange_account_serial"
                                " ON reserves_in (exchange_account_section,reserve_in_serial_id DESC);"),

    /* This table contains the data for wire transfers the exchange has
       executed to close a reserve. */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS reserves_close "
                           "(close_uuid BIGSERIAL PRIMARY KEY"
                           ",reserve_pub BYTEA NOT NULL REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
                           ",execution_date INT8 NOT NULL"
                           ",wtid BYTEA NOT NULL CHECK (LENGTH(wtid)=32)"
                           ",receiver_account TEXT NOT NULL"
                           ",amount_val INT8 NOT NULL"
                           ",amount_frac INT4 NOT NULL"
                           ",amount_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ",closing_fee_val INT8 NOT NULL"
                           ",closing_fee_frac INT4 NOT NULL"
                           ",closing_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ");"),
    GNUNET_PQ_make_try_execute("CREATE INDEX reserves_close_by_reserve "
                               "ON reserves_close(reserve_pub)"),
    /* Table with the withdraw operations that have been performed on a reserve.
       The 'h_blind_ev' is the hash of the blinded coin. It serves as a primary
       key, as (broken) clients that use a non-random coin and blinding factor
       should fail to even withdraw, as otherwise the coins will fail to deposit
       (as they really must be unique). */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS reserves_out"
                            "(reserve_out_serial_id BIGSERIAL UNIQUE"
                            ",h_blind_ev BYTEA PRIMARY KEY CHECK (LENGTH(h_blind_ev)=64)"
                            ",denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash)" /* do NOT CASCADE on DELETE, we may keep the denomination key alive! */
                            ",denom_sig BYTEA NOT NULL"
                            ",reserve_pub BYTEA NOT NULL REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
                            ",reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)"
                            ",execution_date INT8 NOT NULL"
                            ",amount_with_fee_val INT8 NOT NULL"
                            ",amount_with_fee_frac INT4 NOT NULL"
                            ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                            ");"),
    /* Index blindcoins(reserve_pub) for get_reserves_out statement */
    GNUNET_PQ_make_try_execute ("CREATE INDEX reserves_out_reserve_pub_index ON"
                                " reserves_out (reserve_pub)"),
    GNUNET_PQ_make_try_execute ("CREATE INDEX reserves_out_execution_date ON "
                                "reserves_out (execution_date)"),
    GNUNET_PQ_make_try_execute ("CREATE INDEX reserves_out_for_get_withdraw_info ON "
                                "reserves_out (denom_pub_hash,h_blind_ev)"),
    /* Table with coins that have been (partially) spent, used to track
       coin information only once. */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS known_coins "
                           "(coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)"
                           ",denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE"
                           ",denom_sig BYTEA NOT NULL"
                           ");"),
    GNUNET_PQ_make_try_execute ("CREATE INDEX known_coins_by_denomination ON "
                                "known_coins (denom_pub_hash)"),

    /* Table with the commitments made when melting a coin. */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS refresh_commitments "
                           "(melt_serial_id BIGSERIAL UNIQUE"
                           ",rc BYTEA PRIMARY KEY CHECK (LENGTH(rc)=64)"
                           ",old_coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE"
                           ",old_coin_sig BYTEA NOT NULL CHECK(LENGTH(old_coin_sig)=64)"
                           ",amount_with_fee_val INT8 NOT NULL"
                           ",amount_with_fee_frac INT4 NOT NULL"
                           ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ",noreveal_index INT4 NOT NULL"
                           ");"),
    GNUNET_PQ_make_try_execute ("CREATE INDEX refresh_commitments_old_coin_pub_index ON "
                                "refresh_commitments (old_coin_pub);"),

    /* Table with the revelations about the new coins that are to be created
       during a melting session.  Includes the session, the cut-and-choose
       index and the index of the new coin, and the envelope of the new
       coin to be signed, as well as the encrypted information about the
       private key and the blinding factor for the coin (for verification
       in case this newcoin_index is chosen to be revealed) */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS refresh_revealed_coins "
                           "(rc BYTEA NOT NULL REFERENCES refresh_commitments (rc) ON DELETE CASCADE"
                           ",newcoin_index INT4 NOT NULL"
                           ",link_sig BYTEA NOT NULL CHECK(LENGTH(link_sig)=64)"
                           ",denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE"
                           ",coin_ev BYTEA UNIQUE NOT NULL"
                           ",h_coin_ev BYTEA NOT NULL CHECK(LENGTH(h_coin_ev)=64)"
                           ",ev_sig BYTEA NOT NULL"
                           ",PRIMARY KEY (rc, newcoin_index)"
                           ",UNIQUE (h_coin_ev)"
                           ");"),
    GNUNET_PQ_make_try_execute ("CREATE INDEX refresh_revealed_coins_coin_pub_index ON "
                                "refresh_revealed_coins (denom_pub_hash);"),

    /* Table with the transfer keys of a refresh operation; includes
       the rc for which this is the link information, the
       transfer public key (for gamma) and the revealed transfer private
       keys (array of TALER_CNC_KAPPA - 1 entries, with gamma being skipped) */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS refresh_transfer_keys "
                           "(rc BYTEA NOT NULL PRIMARY KEY REFERENCES refresh_commitments (rc) ON DELETE CASCADE"
                           ",transfer_pub BYTEA NOT NULL CHECK(LENGTH(transfer_pub)=32)"
                           ",transfer_privs BYTEA NOT NULL"
                           ");"),
    /* for "get_link" (not sure if this helps, as there should be very few
       transfer_pubs per rc, but at least in theory this helps the ORDER BY
       clause. */
    GNUNET_PQ_make_try_execute ("CREATE INDEX refresh_transfer_keys_coin_tpub ON "
                                "refresh_transfer_keys (rc,transfer_pub);"),


    /* This table contains the wire transfers the exchange is supposed to
       execute to transmit funds to the merchants (and manage refunds). */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS deposits "
                           "(deposit_serial_id BIGSERIAL PRIMARY KEY"
                           ",coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE"
                           ",amount_with_fee_val INT8 NOT NULL"
                           ",amount_with_fee_frac INT4 NOT NULL"
                           ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ",timestamp INT8 NOT NULL"
                           ",refund_deadline INT8 NOT NULL"
                           ",wire_deadline INT8 NOT NULL"
                           ",merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)"
                           ",h_contract_terms BYTEA NOT NULL CHECK (LENGTH(h_contract_terms)=64)"
                           ",h_wire BYTEA NOT NULL CHECK (LENGTH(h_wire)=64)"
                           ",coin_sig BYTEA NOT NULL CHECK (LENGTH(coin_sig)=64)"
                           ",wire TEXT NOT NULL"
                           ",tiny BOOLEAN NOT NULL DEFAULT FALSE"
                           ",done BOOLEAN NOT NULL DEFAULT FALSE"
                           ",UNIQUE (coin_pub, merchant_pub, h_contract_terms)"
                           ");"),
    /* Index for get_deposit_for_wtid and get_deposit_statement */
    GNUNET_PQ_make_try_execute("CREATE INDEX deposits_coin_pub_merchant_contract_index "
                               "ON deposits(coin_pub, merchant_pub, h_contract_terms)"),
    /* Index for deposits_get_ready */
    GNUNET_PQ_make_try_execute("CREATE INDEX deposits_get_ready_index "
                               "ON deposits(tiny,done,wire_deadline,refund_deadline)"),
    /* Index for deposits_iterate_matching */
    GNUNET_PQ_make_try_execute("CREATE INDEX deposits_iterate_matching "
                               "ON deposits(merchant_pub,h_wire,done,wire_deadline)"),

    /* Table with information about coins that have been refunded. (Technically
       one of the deposit operations that a coin was involved with is refunded.)*/
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS refunds "
                           "(refund_serial_id BIGSERIAL UNIQUE"
                           ",coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE"
                           ",merchant_pub BYTEA NOT NULL CHECK(LENGTH(merchant_pub)=32)"
                           ",merchant_sig BYTEA NOT NULL CHECK(LENGTH(merchant_sig)=64)"
                           ",h_contract_terms BYTEA NOT NULL CHECK(LENGTH(h_contract_terms)=64)"
                           ",rtransaction_id INT8 NOT NULL"
                           ",amount_with_fee_val INT8 NOT NULL"
                           ",amount_with_fee_frac INT4 NOT NULL"
                           ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ",PRIMARY KEY (coin_pub, merchant_pub, h_contract_terms, rtransaction_id)" /* this combo must be unique, and we usually select by coin_pub */
                           ");"),
    GNUNET_PQ_make_try_execute("CREATE INDEX refunds_coin_pub_index "
                               "ON refunds(coin_pub)"),
    /* This table contains the data for
       wire transfers the exchange has executed. */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS wire_out "
                           "(wireout_uuid BIGSERIAL PRIMARY KEY"
                           ",execution_date INT8 NOT NULL"
                           ",wtid_raw BYTEA UNIQUE NOT NULL CHECK (LENGTH(wtid_raw)=" TALER_WIRE_TRANSFER_IDENTIFIER_LEN_STR ")"
                           ",wire_target TEXT NOT NULL"
                           ",exchange_account_section TEXT NOT NULL"
                           ",amount_val INT8 NOT NULL"
                           ",amount_frac INT4 NOT NULL"
                           ",amount_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ");"),
    /* Table for the tracking API, mapping from wire transfer identifiers
       to transactions and back */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS aggregation_tracking "
                           "(aggregation_serial_id BIGSERIAL UNIQUE"
                           ",deposit_serial_id INT8 PRIMARY KEY REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE"
                           ",wtid_raw BYTEA  CONSTRAINT wire_out_ref REFERENCES wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE"
                           ");"),
    /* Index for lookup_transactions statement on wtid */
    GNUNET_PQ_make_try_execute("CREATE INDEX aggregation_tracking_wtid_index "
                               "ON aggregation_tracking(wtid_raw)"),
    /* Table for the wire fees. */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS wire_fee "
                           "(wire_method VARCHAR NOT NULL"
                           ",start_date INT8 NOT NULL"
                           ",end_date INT8 NOT NULL"
                           ",wire_fee_val INT8 NOT NULL"
                           ",wire_fee_frac INT4 NOT NULL"
                           ",wire_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ",closing_fee_val INT8 NOT NULL"
                           ",closing_fee_frac INT4 NOT NULL"
                           ",closing_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ",master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)"
                           ",PRIMARY KEY (wire_method, start_date)" /* this combo must be unique */
                           ");"),
    /* Index for lookup_transactions statement on wtid */
    GNUNET_PQ_make_try_execute("CREATE INDEX aggregation_tracking_wtid_index "
                               "ON aggregation_tracking(wtid_raw);"),
    /* Index for gc_wire_fee */
    GNUNET_PQ_make_try_execute("CREATE INDEX wire_fee_gc_index "
                               "ON wire_fee(end_date);"),
    /* Table for /payback information */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS payback "
                           "(payback_uuid BIGSERIAL UNIQUE"
                           ",coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub)" /* do NOT CASCADE on delete, we may keep the coin alive! */
                           ",coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)"
                           ",coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)"
                           ",amount_val INT8 NOT NULL"
                           ",amount_frac INT4 NOT NULL"
                           ",amount_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ",timestamp INT8 NOT NULL"
                           ",h_blind_ev BYTEA NOT NULL REFERENCES reserves_out (h_blind_ev) ON DELETE CASCADE"
                           ");"),
    GNUNET_PQ_make_try_execute("CREATE INDEX payback_by_coin_index "
                               "ON payback(coin_pub);"),
    GNUNET_PQ_make_try_execute("CREATE INDEX payback_by_h_blind_ev "
                               "ON payback(h_blind_ev);"),
    GNUNET_PQ_make_try_execute("CREATE INDEX payback_by_reserve_index "
                               "ON payback(reserve_pub);"),
    GNUNET_PQ_make_try_execute("CREATE INDEX payback_for_by_reserve "
                               "ON payback(coin_pub,denom_pub_hash,h_blind_ev);"),

    /* Table for /payback-refresh information */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS payback_refresh "
                           "(payback_refresh_uuid BIGSERIAL UNIQUE"
                           ",coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub)" /* do NOT CASCADE on delete, we may keep the coin alive! */
                           ",coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)"
                           ",coin_blind BYTEA NOT NULL CHECK(LENGTH(coin_blind)=32)"
                           ",amount_val INT8 NOT NULL"
                           ",amount_frac INT4 NOT NULL"
                           ",amount_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ",timestamp INT8 NOT NULL"
                           ",h_blind_ev BYTEA NOT NULL REFERENCES refresh_revealed_coins (h_coin_ev) ON DELETE CASCADE"
                           ");"),
    GNUNET_PQ_make_try_execute("CREATE INDEX payback_refresh_by_coin_index "
                               "ON payback_refresh(coin_pub);"),
    GNUNET_PQ_make_try_execute("CREATE INDEX payback_refresh_by_h_blind_ev "
                               "ON payback_refresh(h_blind_ev);"),
    GNUNET_PQ_make_try_execute("CREATE INDEX payback_refresh_by_reserve_index "
                               "ON payback_refresh(reserve_pub);"),
    GNUNET_PQ_make_try_execute("CREATE INDEX payback_refresh_for_by_reserve "
                               "ON payback_refresh(coin_pub,denom_pub_hash,h_blind_ev);"),

    /* This table contains the pre-commit data for
       wire transfers the exchange is about to execute. */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS prewire "
                           "(prewire_uuid BIGSERIAL PRIMARY KEY"
                           ",type TEXT NOT NULL"
                           ",finished BOOLEAN NOT NULL DEFAULT false"
                           ",buf BYTEA NOT NULL"
                           ");"),


    /**
     * The 'general_id' column represents _some_ identificator
     * from the institution that cares about the merchant KYC status.
     * If the institution is a bank, then this values might be
     * _any_ alphanumeric code that uniquely identifies that merchant
     * at that bank.  Could also be NULL, if that bank's policy
     * admits so.
     */
    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS kyc_merchants "
                           "(merchant_serial_id BIGSERIAL PRIMARY KEY"
                           ",kyc_checked BOOLEAN NOT NULL DEFAULT FALSE"
                           ",payto_url VARCHAR UNIQUE NOT NULL"
                           ",general_id VARCHAR NOT NULL"
                           ");"),

    GNUNET_PQ_make_try_execute ("CREATE INDEX kyc_merchants_payto_url ON "
                                "kyc_merchants (payto_url);"),

    GNUNET_PQ_make_execute("CREATE TABLE IF NOT EXISTS kyc_events "
                           "(merchant_serial_id BIGSERIAL NOT NULL REFERENCES kyc_merchants (merchant_serial_id) ON DELETE CASCADE"
                           ",amount_val INT8 NOT NULL"
                           ",amount_frac INT4 NOT NULL"
                           ",amount_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                           ",timestamp INT8 NOT NULL"
                           ");"),

    GNUNET_PQ_make_try_execute ("CREATE INDEX kyc_events_timestamp ON "
                                "kyc_events (timestamp);"),

    /* Index for wire_prepare_data_get and gc_prewire statement */
    GNUNET_PQ_make_try_execute("CREATE INDEX prepare_iteration_index "
                               "ON prewire(finished);"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };
  PGconn *conn;
  int ret;

  /* FIXME: use GNUNET_PQ_connect_with_cfg instead? */
  conn = GNUNET_PQ_connect (pc->connection_cfg_str);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_PQ_exec_statements (conn,
                                   es);
  PQfinish (conn);
  return ret;
}


/**
 * Setup prepared statements.
 *
 * @param db_conn connection handle to initialize
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
static int
postgres_prepare (PGconn *db_conn)
{
  struct GNUNET_PQ_PreparedStatement ps[] = {
    /* Used in #postgres_insert_denomination_info() */
    GNUNET_PQ_make_prepare ("denomination_insert",
                            "INSERT INTO denominations "
                            "(denom_pub_hash"
                            ",denom_pub"
                            ",master_pub"
                            ",master_sig"
                            ",valid_from"
                            ",expire_withdraw"
                            ",expire_deposit"
                            ",expire_legal"
                            ",coin_val" /* value of this denom */
                            ",coin_frac" /* fractional value of this denom */
                            ",coin_curr" /* assuming same currency for fees */
                            ",fee_withdraw_val"
                            ",fee_withdraw_frac"
                            ",fee_withdraw_curr" /* must match coin_curr */
                            ",fee_deposit_val"
                            ",fee_deposit_frac"
                            ",fee_deposit_curr"  /* must match coin_curr */
                            ",fee_refresh_val"
                            ",fee_refresh_frac"
                            ",fee_refresh_curr" /* must match coin_curr */
                            ",fee_refund_val"
                            ",fee_refund_frac"
                            ",fee_refund_curr" /* must match coin_curr */
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
                            " $11, $12, $13, $14, $15, $16, $17, $18,"
                            " $19, $20, $21, $22, $23);",
                            23),
    /* Used in #postgres_iterate_denomination_info() */
    GNUNET_PQ_make_prepare ("denomination_iterate",
                            "SELECT"
                            " master_pub"
                            ",master_sig"
                            ",valid_from"
                            ",expire_withdraw"
                            ",expire_deposit"
                            ",expire_legal"
                            ",coin_val"  /* value of this denom */
                            ",coin_frac" /* fractional value of this denom */
                            ",coin_curr" /* assuming same currency for fees */
                            ",fee_withdraw_val"
                            ",fee_withdraw_frac"
                            ",fee_withdraw_curr" /* must match coin_curr */
                            ",fee_deposit_val"
                            ",fee_deposit_frac"
                            ",fee_deposit_curr"  /* must match coin_curr */
                            ",fee_refresh_val"
                            ",fee_refresh_frac"
                            ",fee_refresh_curr" /* must match coin_curr */
                            ",fee_refund_val"
                            ",fee_refund_frac"
                            ",fee_refund_curr" /* must match coin_curr */
                            ",denom_pub"
                            " FROM denominations;",
                            0),
    /* Used in #postgres_get_denomination_info() */
    GNUNET_PQ_make_prepare ("denomination_get",
                            "SELECT"
                            " master_pub"
                            ",master_sig"
                            ",valid_from"
                            ",expire_withdraw"
                            ",expire_deposit"
                            ",expire_legal"
                            ",coin_val"  /* value of this denom */
                            ",coin_frac" /* fractional value of this denom */
                            ",coin_curr" /* assuming same currency for fees */
                            ",fee_withdraw_val"
                            ",fee_withdraw_frac"
                            ",fee_withdraw_curr" /* must match coin_curr */
                            ",fee_deposit_val"
                            ",fee_deposit_frac"
                            ",fee_deposit_curr"  /* must match coin_curr */
                            ",fee_refresh_val"
                            ",fee_refresh_frac"
                            ",fee_refresh_curr" /* must match coin_curr */
                            ",fee_refund_val"
                            ",fee_refund_frac"
                            ",fee_refund_curr" /* must match coin_curr */
                            " FROM denominations"
                            " WHERE denom_pub_hash=$1;",
                            1),
    /* Used in #postgres_insert_denomination_revocation() */
    GNUNET_PQ_make_prepare ("denomination_revocation_insert",
                            "INSERT INTO denomination_revocations "
                            "(denom_pub_hash"
                            ",master_sig"
                            ") VALUES "
                            "($1, $2);",
                            2),
    /* Used in #postgres_get_denomination_revocation() */
    GNUNET_PQ_make_prepare ("denomination_revocation_get",
                            "SELECT"
                            " master_sig"
                            ",denom_revocations_serial_id"
                            " FROM denomination_revocations"
                            " WHERE denom_pub_hash=$1;",
                            1),
    /* Used in #postgres_reserve_get() */
    GNUNET_PQ_make_prepare ("reserve_get",
                            "SELECT"
                            " current_balance_val"
                            ",current_balance_frac"
                            ",current_balance_curr"
                            ",expiration_date"
                            ",gc_date"
                            " FROM reserves"
                            " WHERE reserve_pub=$1"
                            " LIMIT 1"
                            " FOR UPDATE;",
                            1),
    /* Used in #postgres_reserves_in_insert() when the reserve is new */
    GNUNET_PQ_make_prepare ("reserve_create",
                            "INSERT INTO reserves "
                            "(reserve_pub"
                            ",account_details"
                            ",current_balance_val"
                            ",current_balance_frac"
                            ",current_balance_curr"
                            ",expiration_date"
                            ",gc_date"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7);",
                            7),
    /* Used in #postgres_insert_reserve_closed() */
    GNUNET_PQ_make_prepare ("reserves_close_insert",
                            "INSERT INTO reserves_close "
                            "(reserve_pub"
                            ",execution_date"
                            ",wtid"
                            ",receiver_account"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ",closing_fee_val"
                            ",closing_fee_frac"
                            ",closing_fee_curr"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);",
                            10),
    /* Used in #reserves_update() when the reserve is updated */
    GNUNET_PQ_make_prepare ("reserve_update",
                            "UPDATE reserves"
                            " SET"
                            " expiration_date=$1"
                            ",gc_date=$2"
                            ",current_balance_val=$3"
                            ",current_balance_frac=$4"
                            ",current_balance_curr=$5"
                            " WHERE"
                            " reserve_pub=$6;",
                            6),
    /* Used in #postgres_reserves_in_insert() to store transaction details */
    GNUNET_PQ_make_prepare ("reserves_in_add_transaction",
                            "INSERT INTO reserves_in "
                            "(reserve_pub"
                            ",wire_reference"
                            ",credit_val"
                            ",credit_frac"
                            ",credit_curr"
                            ",exchange_account_section"
                            ",sender_account_details"
                            ",execution_date"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7, $8) "
                            "ON CONFLICT DO NOTHING;",
                            8),
    /* Used in postgres_select_reserves_in_above_serial_id() to obtain inbound
       transactions for reserves with serial id '\geq' the given parameter */
    GNUNET_PQ_make_prepare ("reserves_in_get_latest_wire_reference",
                            "SELECT"
                            " wire_reference"
                            " FROM reserves_in"
                            " WHERE exchange_account_section=$1"
                            " ORDER BY reserve_in_serial_id DESC"
                            " LIMIT 1;",
                            1),
    /* Used in postgres_select_reserves_in_above_serial_id() to obtain inbound
       transactions for reserves with serial id '\geq' the given parameter */
    GNUNET_PQ_make_prepare ("audit_reserves_in_get_transactions_incr",
                            "SELECT"
                            " reserve_pub"
                            ",wire_reference"
                            ",credit_val"
                            ",credit_frac"
                            ",credit_curr"
                            ",execution_date"
                            ",sender_account_details"
                            ",reserve_in_serial_id"
                            " FROM reserves_in"
                            " WHERE reserve_in_serial_id>=$1"
                            " ORDER BY reserve_in_serial_id;",
                            1),
    /* Used in postgres_select_reserves_in_above_serial_id() to obtain inbound
       transactions for reserves with serial id '\geq' the given parameter */
    GNUNET_PQ_make_prepare ("audit_reserves_in_get_transactions_incr_by_account",
                            "SELECT"
                            " reserve_pub"
                            ",wire_reference"
                            ",credit_val"
                            ",credit_frac"
                            ",credit_curr"
                            ",execution_date"
                            ",sender_account_details"
                            ",reserve_in_serial_id"
                            " FROM reserves_in"
                            " WHERE reserve_in_serial_id>=$1 AND exchange_account_section=$2"
                            " ORDER BY reserve_in_serial_id;",
                            2),
    /* Used in #postgres_get_reserve_history() to obtain inbound transactions
       for a reserve */
    GNUNET_PQ_make_prepare ("reserves_in_get_transactions",
                            "SELECT"
                            " wire_reference"
                            ",credit_val"
                            ",credit_frac"
                            ",credit_curr"
                            ",execution_date"
                            ",sender_account_details"
                            " FROM reserves_in"
                            " WHERE reserve_pub=$1"
                            " FOR UPDATE;",
                            1),
    /* Lock withdraw table; NOTE: we may want to eventually shard the
       deposit table to avoid this lock being the main point of
       contention limiting transaction performance. */
    GNUNET_PQ_make_prepare ("lock_withdraw",
                            "LOCK TABLE reserves_out;",
                            0),
    /* Used in #postgres_insert_withdraw_info() to store
       the signature of a blinded coin with the blinded coin's
       details before returning it during /reserve/withdraw. We store
       the coin's denomination information (public key, signature)
       and the blinded message as well as the reserve that the coin
       is being withdrawn from and the signature of the message
       authorizing the withdrawal. */
    GNUNET_PQ_make_prepare ("insert_withdraw_info",
                            "INSERT INTO reserves_out "
                            "(h_blind_ev"
                            ",denom_pub_hash"
                            ",denom_sig"
                            ",reserve_pub"
                            ",reserve_sig"
                            ",execution_date"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7, $8, $9);",
                            9),
    /* Used in #postgres_get_withdraw_info() to
       locate the response for a /reserve/withdraw request
       using the hash of the blinded message.  Used to
       make sure /reserve/withdraw requests are idempotent. */
    GNUNET_PQ_make_prepare ("get_withdraw_info",
                            "SELECT"
                            " denom_pub_hash"
                            ",denom_sig"
                            ",reserve_sig"
                            ",reserve_pub"
                            ",execution_date"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",denom.fee_withdraw_val"
                            ",denom.fee_withdraw_frac"
                            ",denom.fee_withdraw_curr"
                            " FROM reserves_out"
                            "    JOIN denominations denom"
                            "      USING (denom_pub_hash)"
                            " WHERE h_blind_ev=$1"
                            " FOR UPDATE;",
                            1),
    /* Used during #postgres_get_reserve_history() to
       obtain all of the /reserve/withdraw operations that
       have been performed on a given reserve. (i.e. to
       demonstrate double-spending) */
    GNUNET_PQ_make_prepare ("get_reserves_out",
                            "SELECT"
                            " h_blind_ev"
                            ",denom_pub_hash"
                            ",denom_sig"
                            ",reserve_sig"
                            ",execution_date"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",denom.fee_withdraw_val"
                            ",denom.fee_withdraw_frac"
                            ",denom.fee_withdraw_curr"
                            " FROM reserves_out"
                            "    JOIN denominations denom"
                            "      USING (denom_pub_hash)"
                            " WHERE reserve_pub=$1"
                            " FOR UPDATE",
                            1),
    /* Used in #postgres_select_reserves_out_above_serial_id() */
    GNUNET_PQ_make_prepare ("audit_get_reserves_out_incr",
                            "SELECT"
                            " h_blind_ev"
                            ",denom.denom_pub"
                            ",denom_sig"
                            ",reserve_sig"
                            ",reserve_pub"
                            ",execution_date"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",reserve_out_serial_id"
                            " FROM reserves_out"
                            "    JOIN denominations denom"
                            "      USING (denom_pub_hash)"
                            " WHERE reserve_out_serial_id>=$1"
                            " ORDER BY reserve_out_serial_id ASC;",
                            1),

    /* Used in #postgres_count_known_coins() */
    GNUNET_PQ_make_prepare ("count_known_coins",
                            "SELECT"
                            " COUNT(*) AS count"
                            " FROM known_coins"
                            " WHERE denom_pub_hash=$1;",
                            1),
    /* Used in #postgres_get_known_coin() to fetch
       the denomination public key and signature for
       a coin known to the exchange. */
    GNUNET_PQ_make_prepare ("get_known_coin",
                            "SELECT"
                            " denom_pub_hash"
                            ",denom_sig"
                            " FROM known_coins"
                            " WHERE coin_pub=$1"
                            " FOR UPDATE;",
                            1),
    /* Used in #postgres_insert_known_coin() to store
       the denomination public key and signature for
       a coin known to the exchange. */
    GNUNET_PQ_make_prepare ("insert_known_coin",
                            "INSERT INTO known_coins "
                            "(coin_pub"
                            ",denom_pub_hash"
                            ",denom_sig"
                            ") VALUES "
                            "($1,$2,$3);",
                            3),

    /* Used in #postgres_insert_melt() to store
       high-level information about a melt operation */
    GNUNET_PQ_make_prepare ("insert_melt",
                            "INSERT INTO refresh_commitments "
                            "(rc "
                            ",old_coin_pub "
                            ",old_coin_sig "
                            ",amount_with_fee_val "
                            ",amount_with_fee_frac "
                            ",amount_with_fee_curr "
                            ",noreveal_index "
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7);",
                            7),
    /* Used in #postgres_get_melt() to fetch
       high-level information about a melt operation */
    GNUNET_PQ_make_prepare ("get_melt",
                            "SELECT"
                            " kc.denom_pub_hash"
                            ",denom.fee_refresh_val"
                            ",denom.fee_refresh_frac"
                            ",denom.fee_refresh_curr"
                            ",kc.denom_sig"
                            ",old_coin_pub"
                            ",old_coin_sig"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",noreveal_index"
                            " FROM refresh_commitments"
                            "   JOIN known_coins kc"
                            "     ON (refresh_commitments.old_coin_pub = kc.coin_pub)"
                            "   JOIN denominations denom"
                            "     ON (kc.denom_pub_hash = denom.denom_pub_hash)"
                            " WHERE rc=$1;",
                            1),
    /* Used in #postgres_get_melt_index() to fetch
       the noreveal index from a previous melt operation */
    GNUNET_PQ_make_prepare ("get_melt_index",
                            "SELECT"
                            " noreveal_index"
                            " FROM refresh_commitments"
                            " WHERE rc=$1;",
                            1),
    /* Used in #postgres_select_refreshs_above_serial_id() to fetch
       refresh session with id '\geq' the given parameter */
    GNUNET_PQ_make_prepare ("audit_get_refresh_commitments_incr",
                            "SELECT"
                            " denom.denom_pub"
                            ",old_coin_pub"
                            ",old_coin_sig"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",noreveal_index"
                            ",melt_serial_id"
                            ",rc"
                            " FROM refresh_commitments"
                            "   JOIN known_coins kc"
                            "     ON (refresh_commitments.old_coin_pub = kc.coin_pub)"
                            "   JOIN denominations denom"
                            "     ON (kc.denom_pub_hash = denom.denom_pub_hash)"
                            " WHERE melt_serial_id>=$1"
                            " ORDER BY melt_serial_id ASC;",
                            1),
    /* Query the 'refresh_commitments' by coin public key */
    GNUNET_PQ_make_prepare ("get_refresh_session_by_coin",
                            "SELECT"
                            " rc"
                            ",old_coin_sig"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",denom.fee_refresh_val "
                            ",denom.fee_refresh_frac "
                            ",denom.fee_refresh_curr "
                            " FROM refresh_commitments"
                            "    JOIN known_coins "
                            "      ON (refresh_commitments.old_coin_pub = known_coins.coin_pub)"
                            "    JOIN denominations denom USING (denom_pub_hash)"
                            " WHERE old_coin_pub=$1;",
                            1),

    /* Store information about the desired denominations for a
       refresh operation, used in #postgres_insert_refresh_reveal() */
    GNUNET_PQ_make_prepare ("insert_refresh_revealed_coin",
                            "INSERT INTO refresh_revealed_coins "
                            "(rc "
                            ",newcoin_index "
                            ",link_sig "
                            ",denom_pub_hash "
                            ",coin_ev"
                            ",h_coin_ev"
                            ",ev_sig"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7);",
                            7),
    /* Obtain information about the coins created in a refresh
       operation, used in #postgres_get_refresh_reveal() */
    GNUNET_PQ_make_prepare ("get_refresh_revealed_coins",
                            "SELECT "
                            " newcoin_index"
                            ",denom.denom_pub"
                            ",link_sig"
                            ",coin_ev"
                            ",ev_sig"
                            " FROM refresh_revealed_coins"
                            "    JOIN denominations denom "
                            "      USING (denom_pub_hash)"
                            " WHERE rc=$1"
                            "   ORDER BY newcoin_index ASC"
                            " FOR UPDATE;",
                            1),

    /* Used in #postgres_insert_refresh_reveal() to store the transfer
       keys we learned */
    GNUNET_PQ_make_prepare ("insert_refresh_transfer_keys",
                            "INSERT INTO refresh_transfer_keys "
                            "(rc"
                            ",transfer_pub"
                            ",transfer_privs"
                            ") VALUES "
                            "($1, $2, $3);",
                            3),
    /* Used in #postgres_get_refresh_reveal() to retrieve transfer
       keys from /refresh/reveal */
    GNUNET_PQ_make_prepare ("get_refresh_transfer_keys",
                            "SELECT"
                            " transfer_pub"
                            ",transfer_privs"
                            " FROM refresh_transfer_keys"
                            " WHERE rc=$1;",
                            1),


    /* Used in #postgres_insert_refund() to store refund information */
    GNUNET_PQ_make_prepare ("insert_refund",
                            "INSERT INTO refunds "
                            "(coin_pub "
                            ",merchant_pub "
                            ",merchant_sig "
                            ",h_contract_terms "
                            ",rtransaction_id "
                            ",amount_with_fee_val "
                            ",amount_with_fee_frac "
                            ",amount_with_fee_curr "
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7, $8);",
                            8),
    /* Query the 'refunds' by coin public key */
    GNUNET_PQ_make_prepare ("get_refunds_by_coin",
                            "SELECT"
                            " merchant_pub"
                            ",merchant_sig"
                            ",h_contract_terms"
                            ",rtransaction_id"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",denom.fee_refund_val "
                            ",denom.fee_refund_frac "
                            ",denom.fee_refund_curr "
                            " FROM refunds"
                            "    JOIN known_coins USING (coin_pub)"
                            "    JOIN denominations denom USING (denom_pub_hash)"
                            " WHERE coin_pub=$1;",
                            1),
    /* Fetch refunds with rowid '\geq' the given parameter */
    GNUNET_PQ_make_prepare ("audit_get_refunds_incr",
                            "SELECT"
                            " merchant_pub"
                            ",merchant_sig"
                            ",h_contract_terms"
                            ",rtransaction_id"
                            ",denom.denom_pub"
                            ",coin_pub"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",refund_serial_id"
                            " FROM refunds"
                            "   JOIN known_coins kc USING (coin_pub)"
                            "   JOIN denominations denom ON (kc.denom_pub_hash = denom.denom_pub_hash)"
                            " WHERE refund_serial_id>=$1"
                            " ORDER BY refund_serial_id ASC;",
                            1),
    /* Lock deposit table; NOTE: we may want to eventually shard the
       deposit table to avoid this lock being the main point of
       contention limiting transaction performance. */
    GNUNET_PQ_make_prepare ("lock_deposit",
                            "LOCK TABLE deposits;",
                            0),
    /* Store information about a /deposit the exchange is to execute.
       Used in #postgres_insert_deposit(). */
    GNUNET_PQ_make_prepare ("insert_deposit",
                            "INSERT INTO deposits "
                            "(coin_pub"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",timestamp"
                            ",refund_deadline"
                            ",wire_deadline"
                            ",merchant_pub"
                            ",h_contract_terms"
                            ",h_wire"
                            ",coin_sig"
                            ",wire"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
                            " $11, $12);",
                            12),
    /* Fetch an existing deposit request, used to ensure idempotency
       during /deposit processing. Used in #postgres_have_deposit(). */
    GNUNET_PQ_make_prepare ("get_deposit",
                            "SELECT"
                            " amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",timestamp"
                            ",refund_deadline"
                            ",wire_deadline"
                            ",h_contract_terms"
                            ",h_wire"
                            " FROM deposits"
                            " WHERE ((coin_pub=$1)"
                            "    AND (merchant_pub=$3)"
                            "    AND (h_contract_terms=$2))"
                            " FOR UPDATE;",
                            3),
    /* Fetch deposits with rowid '\geq' the given parameter */
    GNUNET_PQ_make_prepare ("audit_get_deposits_incr",
                            "SELECT"
                            " amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",timestamp"
                            ",merchant_pub"
                            ",denom.denom_pub"
                            ",coin_pub"
                            ",coin_sig"
                            ",refund_deadline"
                            ",wire_deadline"
                            ",h_contract_terms"
                            ",wire"
                            ",done"
                            ",deposit_serial_id"
                            " FROM deposits"
                            "    JOIN known_coins USING (coin_pub)"
                            "    JOIN denominations denom USING (denom_pub_hash)"
                            " WHERE ("
                            "  (deposit_serial_id>=$1)"
                            " )"
                            " ORDER BY deposit_serial_id ASC;",
                            1),
    /* Fetch an existing deposit request.
       Used in #postgres_wire_lookup_deposit_wtid(). */
    GNUNET_PQ_make_prepare ("get_deposit_for_wtid",
                            "SELECT"
                            " amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",denom.fee_deposit_val"
                            ",denom.fee_deposit_frac"
                            ",denom.fee_deposit_curr"
                            ",wire_deadline"
                            " FROM deposits"
                            "    JOIN known_coins USING (coin_pub)"
                            "    JOIN denominations denom USING (denom_pub_hash)"
                            " WHERE ("
                            "      (coin_pub=$1)"
                            "    AND (merchant_pub=$2)"
                            "    AND (h_contract_terms=$3)"
                            "    AND (h_wire=$4)"
                            " );",
                            4),
    /* Used in #postgres_get_ready_deposit() */
    GNUNET_PQ_make_prepare ("deposits_get_ready",
                            "SELECT"
                            " deposit_serial_id"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",denom.fee_deposit_val"
                            ",denom.fee_deposit_frac"
                            ",denom.fee_deposit_curr"
                            ",wire_deadline"
                            ",h_contract_terms"
                            ",wire"
                            ",merchant_pub"
                            ",coin_pub"
                            " FROM deposits"
                            "    JOIN known_coins USING (coin_pub)"
                            "    JOIN denominations denom USING (denom_pub_hash)"
                            " WHERE tiny=FALSE"
                            "    AND done=FALSE"
                            "    AND wire_deadline<=$1"
                            "    AND refund_deadline<$1"
                            " ORDER BY wire_deadline ASC"
                            " LIMIT 1;",
                            1),
    /* Used in #postgres_iterate_matching_deposits() */
    GNUNET_PQ_make_prepare ("deposits_iterate_matching",
                            "SELECT"
                            " deposit_serial_id"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",denom.fee_deposit_val"
                            ",denom.fee_deposit_frac"
                            ",denom.fee_deposit_curr"
                            ",wire_deadline"
                            ",h_contract_terms"
                            ",coin_pub"
                            " FROM deposits"
                            "    JOIN known_coins"
                            "      USING (coin_pub)"
                            "    JOIN denominations denom"
                            "      USING (denom_pub_hash)"
                            " WHERE"
                            " merchant_pub=$1 AND"
                            " h_wire=$2 AND"
                            " done=FALSE"
                            " ORDER BY wire_deadline ASC"
                            " LIMIT " TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT_STR ";",
                            2),
    /* Used in #postgres_mark_deposit_tiny() */
    GNUNET_PQ_make_prepare ("mark_deposit_tiny",
                            "UPDATE deposits"
                            " SET tiny=TRUE"
                            " WHERE deposit_serial_id=$1",
                            1),
    /* Used in #postgres_mark_deposit_done() */
    GNUNET_PQ_make_prepare ("mark_deposit_done",
                            "UPDATE deposits"
                            " SET done=TRUE"
                            " WHERE deposit_serial_id=$1;",
                            1),
    /* Used in #postgres_test_deposit_done() */
    GNUNET_PQ_make_prepare ("test_deposit_done",
                            "SELECT done"
                            " FROM deposits"
                            " WHERE coin_pub=$1"
                            "   AND merchant_pub=$2"
                            "   AND h_contract_terms=$3"
                            "   AND h_wire=$4;",
                            5),
    /* Used in #postgres_get_coin_transactions() to obtain information
       about how a coin has been spend with /deposit requests. */
    GNUNET_PQ_make_prepare ("get_deposit_with_coin_pub",
                            "SELECT"
                            " amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",denom.fee_deposit_val"
                            ",denom.fee_deposit_frac"
                            ",denom.fee_deposit_curr"
                            ",timestamp"
                            ",refund_deadline"
                            ",wire_deadline"
                            ",merchant_pub"
                            ",h_contract_terms"
                            ",h_wire"
                            ",wire"
                            ",coin_sig"
                            " FROM deposits"
                            "    JOIN known_coins"
                            "      USING (coin_pub)"
                            "    JOIN denominations denom"
                            "      USING (denom_pub_hash)"
                            " WHERE coin_pub=$1"
                            " FOR UPDATE;",
                            1),

    /* Used in #postgres_get_link_data(). */
    GNUNET_PQ_make_prepare ("get_link",
                            "SELECT "
                            " tp.transfer_pub"
                            ",denoms.denom_pub"
                            ",rrc.ev_sig"
                            ",rrc.link_sig"
                            " FROM refresh_commitments"
                            "     JOIN refresh_revealed_coins rrc"
                            "       USING (rc)"
                            "     JOIN refresh_transfer_keys tp"
                            "       USING (rc)"
                            "     JOIN denominations denoms"
                            "       ON (rrc.denom_pub_hash = denoms.denom_pub_hash)"
                            " WHERE old_coin_pub=$1"
                            " ORDER BY tp.transfer_pub",
                            1),
    /* Used in #postgres_lookup_wire_transfer */
    GNUNET_PQ_make_prepare ("lookup_transactions",
                            "SELECT"
                            " aggregation_serial_id"
                            ",deposits.h_contract_terms"
                            ",deposits.wire"
                            ",deposits.h_wire"
                            ",deposits.coin_pub"
                            ",deposits.merchant_pub"
                            ",wire_out.execution_date"
                            ",deposits.amount_with_fee_val"
                            ",deposits.amount_with_fee_frac"
                            ",deposits.amount_with_fee_curr"
                            ",denom.fee_deposit_val"
                            ",denom.fee_deposit_frac"
                            ",denom.fee_deposit_curr"
                            ",denom.denom_pub"
                            " FROM aggregation_tracking"
                            "    JOIN deposits"
                            "      USING (deposit_serial_id)"
                            "    JOIN known_coins"
                            "      USING (coin_pub)"
                            "    JOIN denominations denom"
                            "      USING (denom_pub_hash)"
                            "    JOIN wire_out"
                            "      USING (wtid_raw)"
                            " WHERE wtid_raw=$1;",
                            1),
    /* Used in #postgres_wire_lookup_deposit_wtid */
    GNUNET_PQ_make_prepare ("lookup_deposit_wtid",
                            "SELECT"
                            " aggregation_tracking.wtid_raw"
                            ",wire_out.execution_date"
                            ",amount_with_fee_val"
                            ",amount_with_fee_frac"
                            ",amount_with_fee_curr"
                            ",denom.fee_deposit_val"
                            ",denom.fee_deposit_frac"
                            ",denom.fee_deposit_curr"
                            " FROM deposits"
                            "    JOIN aggregation_tracking"
                            "      USING (deposit_serial_id)"
                            "    JOIN known_coins"
                            "      USING (coin_pub)"
                            "    JOIN denominations denom"
                            "      USING (denom_pub_hash)"
                            "    JOIN wire_out"
                            "      USING (wtid_raw)"
                            " WHERE coin_pub=$1"
                            "  AND h_contract_terms=$2"
                            "  AND h_wire=$3"
                            "  AND merchant_pub=$4;",
                            4),
    /* Used in #postgres_insert_aggregation_tracking */
    GNUNET_PQ_make_prepare ("insert_aggregation_tracking",
                            "INSERT INTO aggregation_tracking "
                            "(deposit_serial_id"
                            ",wtid_raw"
                            ") VALUES "
                            "($1, $2);",
                            2),
    /* Used in #postgres_get_wire_fee() */
    GNUNET_PQ_make_prepare ("get_wire_fee",
                            "SELECT "
                            " start_date"
                            ",end_date"
                            ",wire_fee_val"
                            ",wire_fee_frac"
                            ",wire_fee_curr"
                            ",closing_fee_val"
                            ",closing_fee_frac"
                            ",closing_fee_curr"
                            ",master_sig"
                            " FROM wire_fee"
                            " WHERE wire_method=$1"
                            "   AND start_date <= $2"
                            "   AND end_date > $2;",
                            2),
    /* Used in #postgres_insert_wire_fee */
    GNUNET_PQ_make_prepare ("insert_wire_fee",
                            "INSERT INTO wire_fee "
                            "(wire_method"
                            ",start_date"
                            ",end_date"
                            ",wire_fee_val"
                            ",wire_fee_frac"
                            ",wire_fee_curr"
                            ",closing_fee_val"
                            ",closing_fee_frac"
                            ",closing_fee_curr"
                            ",master_sig"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);",
                            19),
    /* Used in #postgres_store_wire_transfer_out */
    GNUNET_PQ_make_prepare ("insert_wire_out",
                            "INSERT INTO wire_out "
                            "(execution_date"
                            ",wtid_raw"
                            ",wire_target"
                            ",exchange_account_section"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7);",
                            7),
    /* Used in #postgres_wire_prepare_data_insert() to store
       wire transfer information before actually committing it with the bank */
    GNUNET_PQ_make_prepare ("wire_prepare_data_insert",
                            "INSERT INTO prewire "
                            "(type"
                            ",buf"
                            ") VALUES "
                            "($1, $2);",
                            2),
    /* Used in #postgres_wire_prepare_data_mark_finished() */
    GNUNET_PQ_make_prepare ("wire_prepare_data_mark_done",
                            "UPDATE prewire"
                            " SET finished=true"
                            " WHERE prewire_uuid=$1;",
                            1),
    /* Used in #postgres_wire_prepare_data_get() */
    GNUNET_PQ_make_prepare ("wire_prepare_data_get",
                            "SELECT"
                            " prewire_uuid"
                            ",type"
                            ",buf"
                            " FROM prewire"
                            " WHERE finished=false"
                            " ORDER BY prewire_uuid ASC"
                            " LIMIT 1;",
                            0),

    GNUNET_PQ_make_prepare ("clean_kyc_events",
                            "DELETE"
                            " FROM kyc_events"
                            " WHERE merchant_serial_id=$1",
                            1),

    /* Assume a merchant _unchecked_ if their events
     * are stored into the table queried below.  */
    GNUNET_PQ_make_prepare ("get_kyc_events",
                            "SELECT"
                            " merchant_serial_id"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            " FROM kyc_events"
                            " WHERE merchant_serial_id=$1",
                            1),

    GNUNET_PQ_make_prepare ("get_kyc_status",
                            "SELECT"
                            " general_id"
                            ",kyc_checked"
                            ",merchant_serial_id"
                            " FROM kyc_merchants"
                            " WHERE payto_url=$1",
                            1),

    GNUNET_PQ_make_prepare ("insert_kyc_merchant",
                            "INSERT INTO kyc_merchants "
                            "(payto_url"
                            ",general_id"
                            ",kyc_checked) VALUES "
                            "($1, $2, FALSE)",
                            2),


    /* NOTE: NOT used yet, just _potentially_ needed.  */
    GNUNET_PQ_make_prepare ("unmark_kyc_merchant",
                            "UPDATE kyc_merchants"
                            " SET"
                            " kyc_checked=FALSE"
                            " WHERE"
                            " payto_url=$1",
                            1),

    GNUNET_PQ_make_prepare ("mark_kyc_merchant",
                            "UPDATE kyc_merchants"
                            " SET"
                            " kyc_checked=TRUE"
                            " WHERE"
                            " payto_url=$1",
                            1),

    GNUNET_PQ_make_prepare ("insert_kyc_event",
                            "INSERT INTO kyc_events "
                            "(merchant_serial_id"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ",timestamp)"
                            " VALUES ($1, $2, $3, $4, $5)",
                            5),

    /* Used in #postgres_select_deposits_missing_wire */
    GNUNET_PQ_make_prepare ("deposits_get_overdue",
			    "SELECT"
			    " deposit_serial_id"
			    ",coin_pub"
			    ",amount_with_fee_val"
			    ",amount_with_fee_frac"
			    ",amount_with_fee_curr"
			    ",wire"
			    ",wire_deadline"
			    ",tiny"
			    ",done"
			    " FROM deposits"
			    " WHERE wire_deadline >= $1"
			    " AND wire_deadline < $2"
			    " AND NOT (EXISTS (SELECT 1"
			    "            FROM refunds"
			    "            WHERE (refunds.coin_pub = deposits.coin_pub))"
			    "       OR EXISTS (SELECT 1"
			    "            FROM aggregation_tracking"
			    "            WHERE (aggregation_tracking.deposit_serial_id = deposits.deposit_serial_id)))"
			    " ORDER BY wire_deadline ASC",
			    2),
    /* Used in #postgres_gc() */
    GNUNET_PQ_make_prepare ("gc_prewire",
                            "DELETE"
                            " FROM prewire"
                            " WHERE finished=true;",
                            0),
    /* Used in #postgres_select_wire_out_above_serial_id() */
    GNUNET_PQ_make_prepare ("audit_get_wire_incr",
                            "SELECT"
                            " wireout_uuid"
                            ",execution_date"
                            ",wtid_raw"
                            ",wire_target"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            " FROM wire_out"
                            " WHERE wireout_uuid>=$1"
                            " ORDER BY wireout_uuid ASC;",
                            1),
    /* Used in #postgres_select_wire_out_above_serial_id_by_account() */
    GNUNET_PQ_make_prepare ("audit_get_wire_incr_by_account",
                            "SELECT"
                            " wireout_uuid"
                            ",execution_date"
                            ",wtid_raw"
                            ",wire_target"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            " FROM wire_out"
                            " WHERE wireout_uuid>=$1 AND exchange_account_section=$2"
                            " ORDER BY wireout_uuid ASC;",
                            2),
    /* Used in #postgres_insert_payback_request() to store payback
       information */
    GNUNET_PQ_make_prepare ("payback_insert",
                            "INSERT INTO payback "
                            "(coin_pub"
                            ",coin_sig"
                            ",coin_blind"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ",timestamp"
                            ",h_blind_ev"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7, $8);",
                            8),
    /* Used in #postgres_insert_payback_request() to store payback-refresh
       information */
    GNUNET_PQ_make_prepare ("payback_refresh_insert",
                            "INSERT INTO payback_refresh "
                            "(coin_pub"
                            ",coin_sig"
                            ",coin_blind"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ",timestamp"
                            ",h_blind_ev"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7, $8);",
                            8),
    /* Used in #postgres_select_payback_above_serial_id() to obtain payback transactions */
    GNUNET_PQ_make_prepare ("payback_get_incr",
                            "SELECT"
                            " payback_uuid"
                            ",timestamp"
                            ",ro.reserve_pub"
                            ",coin_pub"
                            ",coin_sig"
                            ",coin_blind"
                            ",h_blind_ev"
                            ",coins.denom_pub_hash"
                            ",denoms.denom_pub"
                            ",coins.denom_sig"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            " FROM payback"
                            "    JOIN known_coins coins"
                            "      USING (coin_pub)"
                            "    JOIN reserves_out ro"
                            "      USING (h_blind_ev)"
                            "    JOIN denominations denoms"
                            "      ON (coins.denom_pub_hash = denoms.denom_pub_hash)"
                            " WHERE payback_uuid>=$1"
                            " ORDER BY payback_uuid ASC;",
                            1),
    /* Used in #postgres_select_payback_refresh_above_serial_id() to obtain
       payback-refresh transactions */
    GNUNET_PQ_make_prepare ("payback_refresh_get_incr",
                            "SELECT"
                            " payback_refresh_uuid"
                            ",timestamp"
                            ",rc.old_coin_pub"
                            ",coin_pub"
                            ",coin_sig"
                            ",coin_blind"
                            ",h_blind_ev"
                            ",coins.denom_pub_hash"
                            ",denoms.denom_pub"
                            ",coins.denom_sig"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            " FROM payback_refresh"
                            "    JOIN refresh_revealed_coins rrc"
                            "      ON (rrc.coin_ev = h_blind_ev)"
                            "    JOIN refresh_commitments rc"
                            "      ON (rrc.rc = rc.rc)"
                            "    JOIN known_coins coins"
                            "      USING (coin_pub)"
                            "    JOIN denominations denoms"
                            "      ON (coins.denom_pub_hash = denoms.denom_pub_hash)"
                            " WHERE payback_refresh_uuid>=$1"
                            " ORDER BY payback_refresh_uuid ASC;",
                            1),
    /* Used in #postgres_select_reserve_closed_above_serial_id() to
       obtain information about closed reserves */
    GNUNET_PQ_make_prepare ("reserves_close_get_incr",
                            "SELECT"
                            " close_uuid"
                            ",reserve_pub"
                            ",execution_date"
                            ",wtid"
                            ",receiver_account"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ",closing_fee_val"
                            ",closing_fee_frac"
                            ",closing_fee_curr"
                            " FROM reserves_close"
                            " WHERE close_uuid>=$1"
                            " ORDER BY close_uuid ASC;",
                            1),
    /* Used in #postgres_get_reserve_history() to obtain payback transactions
       for a reserve */
    GNUNET_PQ_make_prepare ("payback_by_reserve",
                            "SELECT"
                            " coin_pub"
                            ",coin_sig"
                            ",coin_blind"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ",timestamp"
                            ",coins.denom_pub_hash"
                            ",coins.denom_sig"
                            " FROM payback"
                            "    JOIN known_coins coins"
                            "      USING (coin_pub)"
                            "    JOIN reserves_out ro"
                            "      USING (h_blind_ev)"
                            " WHERE ro.reserve_pub=$1"
                            " FOR UPDATE;",
                            1),
    /* Used in #postgres_get_coin_transactions() to obtain payback transactions
       affecting old coins of refreshed coins */
    GNUNET_PQ_make_prepare ("payback_by_old_coin",
                            "SELECT"
                            " coin_pub"
                            ",coin_sig"
                            ",coin_blind"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ",timestamp"
                            ",coins.denom_pub_hash"
                            ",coins.denom_sig"
                            " FROM payback_refresh"
                            "    JOIN known_coins coins"
                            "      USING (coin_pub)"
                            " WHERE h_blind_ev IN"
                            "   (SELECT rrc.h_coin_ev"
                            "    FROM refresh_commitments"
                            "       JOIN refresh_revealed_coins rrc"
                            "           USING (rc)"
                            "    WHERE old_coin_pub=$1)"
                            " FOR UPDATE;",
                            1),
    /* Used in #postgres_get_reserve_history() */
    GNUNET_PQ_make_prepare ("close_by_reserve",
                            "SELECT"
                            " amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ",closing_fee_val"
                            ",closing_fee_frac"
                            ",closing_fee_curr"
                            ",execution_date"
                            ",receiver_account"
                            ",wtid"
                            " FROM reserves_close"
                            " WHERE reserve_pub=$1"
                            " FOR UPDATE",
                            1),
    /* Used in #postgres_get_expired_reserves() */
    GNUNET_PQ_make_prepare ("get_expired_reserves",
                            "SELECT"
                            " expiration_date"
                            ",account_details"
                            ",reserve_pub"
                            ",current_balance_val"
                            ",current_balance_frac"
                            ",current_balance_curr"
                            " FROM reserves"
                            " WHERE expiration_date<=$1"
                            "   AND (current_balance_val != 0 "
                            "        OR current_balance_frac != 0)"
                            " ORDER BY expiration_date ASC"
                            " LIMIT 1;",
                            1),
    /* Used in #postgres_get_coin_transactions() to obtain payback transactions
       for a coin */
    GNUNET_PQ_make_prepare ("payback_by_coin",
                            "SELECT"
                            " ro.reserve_pub"
                            ",coin_sig"
                            ",coin_blind"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ",timestamp"
                            ",coins.denom_pub_hash"
                            ",coins.denom_sig"
                            " FROM payback"
                            "    JOIN known_coins coins"
                            "      USING (coin_pub)"
                            "    JOIN reserves_out ro"
                            "      USING (h_blind_ev)"
                            " WHERE payback.coin_pub=$1"
                            " FOR UPDATE;",
                            1),
    /* Used in #postgres_get_coin_transactions() to obtain payback transactions
       for a refreshed coin */
    GNUNET_PQ_make_prepare ("payback_by_refreshed_coin",
                            "SELECT"
                            " rc.old_coin_pub"
                            ",coin_sig"
                            ",coin_blind"
                            ",amount_val"
                            ",amount_frac"
                            ",amount_curr"
                            ",timestamp"
                            ",coins.denom_pub_hash"
                            ",coins.denom_sig"
                            " FROM payback_refresh"
                            "    JOIN refresh_revealed_coins rrc"
                            "      ON (rrc.coin_ev = h_blind_ev)"
                            "    JOIN refresh_commitments rc"
                            "      ON (rrc.rc = rc.rc)"
                            "    JOIN known_coins coins"
                            "      USING (coin_pub)"
                            " WHERE coin_pub=$1"
                            " FOR UPDATE;",
                            1),
    /* Used in #postgres_get_reserve_by_h_blind() */
    GNUNET_PQ_make_prepare ("reserve_by_h_blind",
                            "SELECT"
                            " reserve_pub"
                            " FROM reserves_out"
                            " WHERE h_blind_ev=$1"
                            " LIMIT 1"
                            " FOR UPDATE;",
                            1),
    /* Used in #postgres_get_old_coin_by_h_blind() */
    GNUNET_PQ_make_prepare ("old_coin_by_h_blind",
                            "SELECT"
                            " rcom.old_coin_pub"
                            " FROM refresh_revealed_coins"
                            "   JOIN refresh_commitments rcom"
                            "      USING (rc)"
                            " WHERE h_coin_ev=$1"
                            " LIMIT 1"
                            " FOR UPDATE;",
                            1),
    /* used in #postgres_commit */
    GNUNET_PQ_make_prepare ("do_commit",
                            "COMMIT",
                            0),
    GNUNET_PQ_make_prepare ("gc_denominations",
                            "DELETE"
                            " FROM denominations"
                            " WHERE expire_legal < $1;",
                            1),
    GNUNET_PQ_make_prepare ("gc_reserves",
                            "DELETE"
                            " FROM reserves"
                            " WHERE gc_date < $1"
                            "   AND current_balance_val = 0"
                            "   AND current_balance_frac = 0;",
                            1),
    GNUNET_PQ_make_prepare ("gc_wire_fee",
                            "DELETE"
                            " FROM wire_fee"
                            " WHERE end_date < $1;",
                            1),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };

  return GNUNET_PQ_prepare_statements (db_conn,
                                       ps);
}


/**
 * Close thread-local database connection when a thread is destroyed.
 *
 * @param cls closure we get from pthreads (the db handle)
 */
static void
db_conn_destroy (void *cls)
{
  struct TALER_EXCHANGEDB_Session *session = cls;
  PGconn *db_conn;

  if (NULL == session)
    return;
  db_conn = session->conn;
  if (NULL != db_conn)
    PQfinish (db_conn);
  GNUNET_free (session);
}


/**
 * Get the thread-local database-handle.
 * Connect to the db if the connection does not exist yet.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return the database connection, or NULL on error
 */
static struct TALER_EXCHANGEDB_Session *
postgres_get_session (void *cls)
{
  struct PostgresClosure *pc = cls;
  PGconn *db_conn;
  struct TALER_EXCHANGEDB_Session *session;

  if (NULL != (session = pthread_getspecific (pc->db_conn_threadlocal)))
  {
    if (CONNECTION_BAD == PQstatus (session->conn))
    {
      /**
       * Reset the thread-local database-handle.  Disconnects from the
       * DB.  Needed after the database server restarts as we need to
       * properly reconnect. */
      GNUNET_assert (0 ==
		     pthread_setspecific (pc->db_conn_threadlocal,
					  NULL));
      PQfinish (session->conn);
      GNUNET_free (session);
    }
    else
    {
      return session;
    }
  }
  /* FIXME: use GNUNET_PQ_connect_with_cfg instead? */
  db_conn = GNUNET_PQ_connect (pc->connection_cfg_str);
  if (NULL == db_conn)
    return NULL;
  if (GNUNET_OK !=
      postgres_prepare (db_conn))
  {
    GNUNET_break (0);
    PQfinish (db_conn);
    return NULL;
  }

#if AUTO_EXPLAIN
  /* Enable verbose logging to see where queries do not
     properly use indices */
  {
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_make_try_execute ("LOAD 'auto_explain';"),
      GNUNET_PQ_make_try_execute ("SET auto_explain.log_min_duration=50;"),
      GNUNET_PQ_make_try_execute ("SET auto_explain.log_timing=TRUE;"),
      GNUNET_PQ_make_try_execute ("SET auto_explain.log_analyze=TRUE;"),
      GNUNET_PQ_make_try_execute ("SET enable_sort=OFF;"),
      GNUNET_PQ_make_try_execute ("SET enable_seqscan=OFF;"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };

    (void) GNUNET_PQ_exec_statements (db_conn,
                                      es);
  }
#endif

  session = GNUNET_new (struct TALER_EXCHANGEDB_Session);
  session->conn = db_conn;
  if (0 != pthread_setspecific (pc->db_conn_threadlocal,
                                session))
  {
    GNUNET_break (0);
    PQfinish (db_conn);
    GNUNET_free (session);
    return NULL;
  }
  return session;
}


/**
 * Start a transaction.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @param name unique name identifying the transaction (for debugging)
   *             must point to a constant
 * @return #GNUNET_OK on success
 */
static int
postgres_start (void *cls,
                struct TALER_EXCHANGEDB_Session *session,
                const char *name)
{
  PGresult *result;
  ExecStatusType ex;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting transaction on %p\n",
              session->conn);
  result = PQexec (session->conn,
                   "START TRANSACTION ISOLATION LEVEL SERIALIZABLE");
  if (PGRES_COMMAND_OK !=
      (ex = PQresultStatus (result)))
  {
    TALER_LOG_ERROR ("Failed to start transaction (%s): %s\n",
                     PQresStatus (ex),
                     PQerrorMessage (session->conn));
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  session->transaction_name = name;
  return GNUNET_OK;
}


/**
 * Roll back the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @return #GNUNET_OK on success
 */
static void
postgres_rollback (void *cls,
                   struct TALER_EXCHANGEDB_Session *session)
{
  PGresult *result;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Rolling back transaction on %p\n",
              session->conn);
  result = PQexec (session->conn,
                   "ROLLBACK");
  GNUNET_break (PGRES_COMMAND_OK ==
                PQresultStatus (result));
  PQclear (result);
  session->transaction_name = NULL;
}


/**
 * Commit the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @return final transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_commit (void *cls,
                 struct TALER_EXCHANGEDB_Session *session)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                           "do_commit",
                                           params);
  session->transaction_name = NULL;
  return qs;
}


/**
 * Do a pre-flight check that we are not in an uncommitted transaction.
 * If we are, try to commit the previous transaction and output a warning.
 * Does not return anything, as we will continue regardless of the outcome.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 */
static void
postgres_preflight (void *cls,
                    struct TALER_EXCHANGEDB_Session *session)
{
  PGresult *result;
  ExecStatusType status;

  if (NULL == session->transaction_name)
    return; /* all good */
  result = PQexec (session->conn,
                   "COMMIT");
  status = PQresultStatus (result);
  if (PGRES_COMMAND_OK == status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "BUG: Preflight check committed transaction `%s'!\n",
                session->transaction_name);
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "BUG: Preflight check failed to commit transaction `%s'!\n",
                session->transaction_name);
  }
  session->transaction_name = NULL;
  PQclear (result);
}


/**
 * Insert a denomination key's public information into the database for
 * reference by auditors and other consistency checks.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub the public key used for signing coins of this denomination
 * @param issue issuing information with value, fees and other info about the coin
 * @return status of the query
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_denomination_info (void *cls,
                                   struct TALER_EXCHANGEDB_Session *session,
                                   const struct TALER_DenominationPublicKey *denom_pub,
                                   const struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&issue->properties.denom_hash),
    GNUNET_PQ_query_param_rsa_public_key (denom_pub->rsa_public_key),
    GNUNET_PQ_query_param_auto_from_type (&issue->properties.master),
    GNUNET_PQ_query_param_auto_from_type (&issue->signature),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.start),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.expire_withdraw),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.expire_deposit),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.expire_legal),
    TALER_PQ_query_param_amount_nbo (&issue->properties.value),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_withdraw),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_deposit),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_refresh),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_refund),
    GNUNET_PQ_query_param_end
  };

  /* check fees match coin currency */
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->properties.value,
                                                &issue->properties.fee_withdraw));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->properties.value,
                                                &issue->properties.fee_deposit));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->properties.value,
                                                &issue->properties.fee_refresh));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->properties.value,
                                               &issue->properties.fee_refund));

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "denomination_insert",
					     params);
}


/**
 * Fetch information about a denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub_hash hash of the public key used for signing coins of this denomination
 * @param[out] issue set to issue information with value, fees and other info about the coin
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_denomination_info (void *cls,
                                struct TALER_EXCHANGEDB_Session *session,
                                const struct GNUNET_HashCode *denom_pub_hash,
                                struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("master_pub",
					  &issue->properties.master),
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
					  &issue->signature),
    TALER_PQ_result_spec_absolute_time_nbo ("valid_from",
					     &issue->properties.start),
    TALER_PQ_result_spec_absolute_time_nbo ("expire_withdraw",
					     &issue->properties.expire_withdraw),
    TALER_PQ_result_spec_absolute_time_nbo ("expire_deposit",
					     &issue->properties.expire_deposit),
    TALER_PQ_result_spec_absolute_time_nbo ("expire_legal",
					     &issue->properties.expire_legal),
    TALER_PQ_result_spec_amount_nbo ("coin",
				     &issue->properties.value),
    TALER_PQ_result_spec_amount_nbo ("fee_withdraw",
				     &issue->properties.fee_withdraw),
    TALER_PQ_result_spec_amount_nbo ("fee_deposit",
				     &issue->properties.fee_deposit),
    TALER_PQ_result_spec_amount_nbo ("fee_refresh",
				     &issue->properties.fee_refresh),
    TALER_PQ_result_spec_amount_nbo ("fee_refund",
				     &issue->properties.fee_refund),
    GNUNET_PQ_result_spec_end
  };

  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						 "denomination_get",
						 params,
						 rs);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    return qs;
  issue->properties.purpose.size = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
  issue->properties.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  issue->properties.denom_hash = *denom_pub_hash;
  return qs;
}


/**
 * Closure for #domination_cb_helper()
 */
struct DenomIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_DenominationInfoIterator cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;
};


/**
 * Helper function for #postgres_iterate_denomination_info().
 * Calls the callback with each denomination key.
 *
 * @param cls a `struct DenomIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
domination_cb_helper (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct DenomIteratorContext *dic = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_EXCHANGEDB_DenominationKeyInformationP issue;
    struct TALER_DenominationPublicKey denom_pub;
    struct GNUNET_PQ_ResultSpec rs[] = {
       GNUNET_PQ_result_spec_auto_from_type ("master_pub",
                                             &issue.properties.master),
       GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                             &issue.signature),
       TALER_PQ_result_spec_absolute_time_nbo ("valid_from",
                                               &issue.properties.start),
       TALER_PQ_result_spec_absolute_time_nbo ("expire_withdraw",
                                               &issue.properties.expire_withdraw),
       TALER_PQ_result_spec_absolute_time_nbo ("expire_deposit",
                                               &issue.properties.expire_deposit),
       TALER_PQ_result_spec_absolute_time_nbo ("expire_legal",
                                               &issue.properties.expire_legal),
       TALER_PQ_result_spec_amount_nbo ("coin",
                                        &issue.properties.value),
       TALER_PQ_result_spec_amount_nbo ("fee_withdraw",
                                        &issue.properties.fee_withdraw),
       TALER_PQ_result_spec_amount_nbo ("fee_deposit",
                                        &issue.properties.fee_deposit),
       TALER_PQ_result_spec_amount_nbo ("fee_refresh",
                                        &issue.properties.fee_refresh),
       TALER_PQ_result_spec_amount_nbo ("fee_refund",
                                        &issue.properties.fee_refund),
       GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                             &denom_pub.rsa_public_key),
       GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      return;
    }
    issue.properties.purpose.size
      = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
    issue.properties.purpose.purpose
      = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
    GNUNET_CRYPTO_rsa_public_key_hash (denom_pub.rsa_public_key,
                                       &issue.properties.denom_hash);
    dic->cb (dic->cb_cls,
             &denom_pub,
             &issue);
    GNUNET_CRYPTO_rsa_public_key_free (denom_pub.rsa_public_key);
  }
}


/**
 * Fetch information about all known denomination keys.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param cb function to call on each denomination key
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_iterate_denomination_info (void *cls,
                                    TALER_EXCHANGEDB_DenominationInfoIterator cb,
                                    void *cb_cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct DenomIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls
  };

  return GNUNET_PQ_eval_prepared_multi_select (postgres_get_session (pc)->conn,
					       "denomination_iterate",
					       params,
					       &domination_cb_helper,
					       &dic);
}


/**
 * Get the summary of a reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection handle
 * @param[in,out] reserve the reserve data.  The public key of the reserve should be
 *          set in this structure; it is used to query the database.  The balance
 *          and expiration are then filled accordingly.
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_reserve_get (void *cls,
                      struct TALER_EXCHANGEDB_Session *session,
                      struct TALER_EXCHANGEDB_Reserve *reserve)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type(&reserve->pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount("current_balance", &reserve->balance),
    TALER_PQ_result_spec_absolute_time("expiration_date", &reserve->expiry),
    TALER_PQ_result_spec_absolute_time("gc_date", &reserve->gc),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "reserve_get",
                                                   params,
                                                   rs);
}


/**
 * Updates a reserve with the data from the given reserve structure.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @param reserve the reserve structure whose data will be used to update the
 *          corresponding record in the database.
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserves_update (void *cls,
                 struct TALER_EXCHANGEDB_Session *session,
                 const struct TALER_EXCHANGEDB_Reserve *reserve)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&reserve->expiry),
    TALER_PQ_query_param_absolute_time (&reserve->gc),
    TALER_PQ_query_param_amount (&reserve->balance),
    GNUNET_PQ_query_param_auto_from_type (&reserve->pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "reserve_update",
                                             params);
}


/**
 * Insert an incoming transaction into reserves.  New reserves are also created
 * through this function.  Note that this API call starts (and stops) its
 * own transaction scope (so the application must not do so).
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection handle
 * @param reserve_pub public key of the reserve
 * @param balance the amount that has to be added to the reserve
 * @param execution_time when was the amount added
 * @param sender_account_details account information for the sender (payto://-URL)
 * @param exchange_account_section name of the section in the configuration for the exchange's
 *                       account into which the deposit was made
 * @param wire_reference unique reference identifying the wire transfer (binary blob)
 * @param wire_reference_size number of bytes in @a wire_reference
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_reserves_in_insert (void *cls,
                             struct TALER_EXCHANGEDB_Session *session,
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             const struct TALER_Amount *balance,
                             struct GNUNET_TIME_Absolute execution_time,
                             const char *sender_account_details,
                             const char *exchange_account_section,
                             const void *wire_reference,
                             size_t wire_reference_size)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus reserve_exists;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_TIME_Absolute expiry;

  reserve.pub = *reserve_pub;
  reserve_exists = postgres_reserve_get (cls,
                                         session,
                                         &reserve);
  if (0 > reserve_exists)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == reserve_exists);
    return reserve_exists;
  }
  if ( (0 == reserve.balance.value) &&
       (0 == reserve.balance.fraction) )
  {
    /* TODO: reserve balance is empty, we might want to update
       sender_account_details here.  (So that IF a customer uses the
       same reserve public key from a different account, we USUALLY
       switch to the new account (but only if the old reserve was
       drained).)  This helps make sure that on reserve expiration the
       funds go back to a valid account in cases where the customer
       has closed the old bank account and some (buggy?) wallet keeps
       using the same reserve key with the customer's new account.

       Note that for a non-drained reserve we should not switch,
       as that opens an attack vector for an adversary who can see
       the wire transfer subjects (i.e. when using Bitcoin).
    */
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Creating reserve %s with expiration in %s\n",
              TALER_B2S (reserve_pub),
              GNUNET_STRINGS_relative_time_to_string (pg->idle_reserve_expiration_time,
                                                      GNUNET_NO));
  expiry = GNUNET_TIME_absolute_add (execution_time,
                                     pg->idle_reserve_expiration_time);
  (void) GNUNET_TIME_round_abs (&expiry);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == reserve_exists)
  {
    /* New reserve, create balance for the first time; we do this
       before adding the actual transaction to "reserves_in", as
       for a new reserve it can't be a duplicate 'add' operation,
       and as the 'add' operation may need the reserve entry
       as a foreign key. */
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (reserve_pub),
      GNUNET_PQ_query_param_string (sender_account_details),
      TALER_PQ_query_param_amount (balance),
      TALER_PQ_query_param_absolute_time (&expiry),
      TALER_PQ_query_param_absolute_time (&expiry),
      GNUNET_PQ_query_param_end
    };

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Reserve does not exist; creating a new one\n");
    qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "reserve_create",
                                             params);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
      return qs;
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      /* Maybe DB did not detect serializiability error already,
         but clearly there must be one. Still odd. */
      GNUNET_break (0);
      return GNUNET_DB_STATUS_SOFT_ERROR;
    }
  }
  /* Create new incoming transaction, "ON CONFLICT DO NOTHING"
     is used to guard against duplicates. */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&reserve.pub),
      GNUNET_PQ_query_param_fixed_size (wire_reference,
                                        wire_reference_size),
      TALER_PQ_query_param_amount (balance),
      GNUNET_PQ_query_param_string (exchange_account_section),
      GNUNET_PQ_query_param_string (sender_account_details),
      TALER_PQ_query_param_absolute_time (&execution_time),
      GNUNET_PQ_query_param_end
    };

    qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "reserves_in_add_transaction",
                                             params);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
      return qs;
    }
  }

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == reserve_exists)
  {
    /* If the reserve already existed, we need to still update the
       balance; we do this after checking for duplication, as
       otherwise we might have to actually pay the cost to roll this
       back for duplicate transactions; like this, we should virtually
       never actually have to rollback anything. */
    struct TALER_EXCHANGEDB_Reserve updated_reserve;

    updated_reserve.pub = reserve.pub;
    if (GNUNET_OK !=
        TALER_amount_add (&updated_reserve.balance,
                          &reserve.balance,
                          balance))
    {
      /* currency overflow or incompatible currency */
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Attempt to deposit incompatible amount into reserve\n");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    updated_reserve.expiry = GNUNET_TIME_absolute_max (expiry,
                                                       reserve.expiry);
    (void) GNUNET_TIME_round_abs (&updated_reserve.expiry);
    updated_reserve.gc = GNUNET_TIME_absolute_max (updated_reserve.expiry,
                                                   reserve.gc);
    (void) GNUNET_TIME_round_abs (&updated_reserve.gc);
    return reserves_update (cls,
                            session,
                            &updated_reserve);
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Obtain the most recent @a wire_reference that was inserted via @e reserves_in_insert.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session the database session handle
 * @param exchange_account_name name of the section in the exchange's configuration
 *                       for the account that we are tracking here
 * @param[out] wire_reference set to unique reference identifying the wire transfer (binary blob)
 * @param[out] wire_reference_size set to number of bytes in @a wire_reference
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_latest_reserve_in_reference (void *cls,
                                          struct TALER_EXCHANGEDB_Session *session,
                                          const char *exchange_account_name,
                                          void **wire_reference,
                                          size_t *wire_reference_size)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (exchange_account_name),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_variable_size ("wire_reference",
					 wire_reference,
					 wire_reference_size),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "reserves_in_get_latest_wire_reference",
						   params,
						   rs);
}


/**
 * Locate the response for a /reserve/withdraw request under the
 * key of the hash of the blinded message.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param h_blind hash of the blinded coin to be signed (will match
 *                `h_coin_envelope` in the @a collectable to be returned)
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return statement execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_withdraw_info (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct GNUNET_HashCode *h_blind,
                            struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable)
{
  struct GNUNET_PQ_QueryParam no_params[] = {
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_blind),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &collectable->denom_pub_hash),
    GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                         &collectable->sig.rsa_signature),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
					  &collectable->reserve_sig),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
					  &collectable->reserve_pub),
    TALER_PQ_result_spec_amount ("amount_with_fee",
				 &collectable->amount_with_fee),
    TALER_PQ_result_spec_amount ("fee_withdraw",
				 &collectable->withdraw_fee),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  if (0 > (qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                                    "lock_withdraw",
                                                    no_params)))
    return qs;
  collectable->h_coin_envelope = *h_blind;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "get_withdraw_info",
                                                   params,
                                                   rs);
}


/**
 * Store collectable bit coin under the corresponding
 * hash of the blinded message.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_withdraw_info (void *cls,
                               struct TALER_EXCHANGEDB_Session *session,
                               const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable)
{
  struct PostgresClosure *pg = cls;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute expiry;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&collectable->h_coin_envelope),
    GNUNET_PQ_query_param_auto_from_type (&collectable->denom_pub_hash),
    GNUNET_PQ_query_param_rsa_signature (collectable->sig.rsa_signature),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_sig),
    TALER_PQ_query_param_absolute_time (&now),
    TALER_PQ_query_param_amount (&collectable->amount_with_fee),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                           "insert_withdraw_info",
                                           params);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  /* update reserve balance */
  reserve.pub = collectable->reserve_pub;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      (qs = postgres_reserve_get (cls,
                                  session,
                                  &reserve)))
  {
    /* Should have been checked before we got here... */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    return qs;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&reserve.balance,
                             &reserve.balance,
                             &collectable->amount_with_fee))
  {
    /* The reserve history was checked to make sure there is enough of a balance
       left before we tried this; however, concurrent operations may have changed
       the situation by now.  We should re-try the transaction.  */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Withdrawal from reserve `%s' refused due to balance missmatch. Retrying.\n",
                TALER_B2S (&collectable->reserve_pub));
    return GNUNET_DB_STATUS_SOFT_ERROR;
  }
  expiry = GNUNET_TIME_absolute_add (now,
                                     pg->legal_reserve_expiration_time);
  reserve.gc = GNUNET_TIME_absolute_max (expiry,
                                         reserve.gc);
  (void) GNUNET_TIME_round_abs (&reserve.gc);
  qs = reserves_update (cls,
                        session,
                        &reserve);
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_break (0);
    qs = GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


/**
 * Closure for callbacks invoked via #postgres_get_reserve_history.
 */
struct ReserveHistoryContext
{

  /**
   * Which reserve are we building the history for?
   */
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /**
   * Where we build the history.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *rh;

  /**
   * Tail of @e rh list.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *rh_tail;

  /**
   * Set to #GNUNET_SYSERR on serious internal errors during
   * the callbacks.
   */
  int status;
};


/**
 * Append and return a fresh element to the reserve
 * history kept in @a rhc.
 *
 * @param rhc where the history is kept
 * @return the fresh element that was added
 */
static struct TALER_EXCHANGEDB_ReserveHistory *
append_rh (struct ReserveHistoryContext *rhc)
{
  struct TALER_EXCHANGEDB_ReserveHistory *tail;

  tail = GNUNET_new (struct TALER_EXCHANGEDB_ReserveHistory);
  if (NULL != rhc->rh_tail)
  {
    rhc->rh_tail->next = tail;
    rhc->rh_tail = tail;
  }
  else
  {
    rhc->rh_tail = tail;
    rhc->rh = tail;
  }
  return tail;
}


/**
 * Add bank transfers to result set for #postgres_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_bank_to_exchange (void *cls,
		      PGresult *result,
		      unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_BankTransfer *bt;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    bt = GNUNET_new (struct TALER_EXCHANGEDB_BankTransfer);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
	GNUNET_PQ_result_spec_variable_size ("wire_reference",
					     &bt->wire_reference,
					     &bt->wire_reference_size),
	TALER_PQ_result_spec_amount ("credit",
				     &bt->amount),
	TALER_PQ_result_spec_absolute_time ("execution_date",
					     &bt->execution_date),
	GNUNET_PQ_result_spec_string ("sender_account_details",
                                      &bt->sender_account_details),
	GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
	  GNUNET_PQ_extract_result (result,
				    rs,
				    --num_results))
      {
	GNUNET_break (0);
	GNUNET_free (bt);
	rhc->status = GNUNET_SYSERR;
	return;
      }
    }
    bt->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE;
    tail->details.bank = bt;
  } /* end of 'while (0 < rows)' */
}


/**
 * Add coin withdrawals to result set for #postgres_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_withdraw_coin (void *cls,
		   PGresult *result,
		   unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_CollectableBlindcoin *cbc;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    cbc = GNUNET_new (struct TALER_EXCHANGEDB_CollectableBlindcoin);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
	GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
					      &cbc->h_coin_envelope),
	GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
					      &cbc->denom_pub_hash),
	GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
					     &cbc->sig.rsa_signature),
	GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
					      &cbc->reserve_sig),
	TALER_PQ_result_spec_amount ("amount_with_fee",
				     &cbc->amount_with_fee),
	TALER_PQ_result_spec_amount ("fee_withdraw",
				     &cbc->withdraw_fee),
	GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
	  GNUNET_PQ_extract_result (result,
				    rs,
				    --num_results))
      {
	GNUNET_break (0);
	GNUNET_free (cbc);
	rhc->status = GNUNET_SYSERR;
	return;
      }
    }
    cbc->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_WITHDRAW_COIN;
    tail->details.withdraw = cbc;
  }
}


/**
 * Add paybacks to result set for #postgres_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_payback (void *cls,
	     PGresult *result,
	     unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_Payback *payback;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    payback = GNUNET_new (struct TALER_EXCHANGEDB_Payback);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount ("amount",
				     &payback->value),
	GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
					      &payback->coin.coin_pub),
	GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
					      &payback->coin_blind),
	GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
					      &payback->coin_sig),
	TALER_PQ_result_spec_absolute_time ("timestamp",
					     &payback->timestamp),
	GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &payback->coin.denom_pub_hash),
	GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                         &payback->coin.denom_sig.rsa_signature),
	GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
	  GNUNET_PQ_extract_result (result,
				    rs,
				    --num_results))
      {
	GNUNET_break (0);
	GNUNET_free (payback);
	rhc->status = GNUNET_SYSERR;
	return;
      }
    }
    payback->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_PAYBACK_COIN;
    tail->details.payback = payback;
  } /* end of 'while (0 < rows)' */
}


/**
 * Add exchange-to-bank transfers to result set for
 * #postgres_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_exchange_to_bank (void *cls,
		      PGresult *result,
		      unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_ClosingTransfer *closing;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    closing = GNUNET_new (struct TALER_EXCHANGEDB_ClosingTransfer);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
	TALER_PQ_result_spec_amount ("amount",
				     &closing->amount),
	TALER_PQ_result_spec_amount ("closing_fee",
				     &closing->closing_fee),
	TALER_PQ_result_spec_absolute_time ("execution_date",
					     &closing->execution_date),
	GNUNET_PQ_result_spec_string ("receiver_account",
                                      &closing->receiver_account_details),
	GNUNET_PQ_result_spec_auto_from_type ("wtid",
					      &closing->wtid),
	GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
	  GNUNET_PQ_extract_result (result,
				    rs,
				    --num_results))
      {
	GNUNET_break (0);
	GNUNET_free (closing);
	rhc->status = GNUNET_SYSERR;
	return;
      }
    }
    closing->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK;
    tail->details.closing = closing;
  } /* end of 'while (0 < rows)' */
}


/**
 * Get all of the transaction history associated with the specified
 * reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session connection to use
 * @param reserve_pub public key of the reserve
 * @param[out] rhp set to known transaction history (NULL if reserve is unknown)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_history (void *cls,
                              struct TALER_EXCHANGEDB_Session *session,
                              const struct TALER_ReservePublicKeyP *reserve_pub,
			      struct TALER_EXCHANGEDB_ReserveHistory **rhp)
{
  struct ReserveHistoryContext rhc;
  struct {
    /**
     * Name of the prepared statement to run.
     */
    const char *statement;
    /**
     * Function to use to process the results.
     */
    GNUNET_PQ_PostgresResultHandler cb;
  } work[] = {
    /** #TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE */
    { "reserves_in_get_transactions",
      add_bank_to_exchange },
    /** #TALER_EXCHANGEDB_RO_WITHDRAW_COIN */
    { "get_reserves_out",
      &add_withdraw_coin },
    /** #TALER_EXCHANGEDB_RO_PAYBACK_COIN */
    { "payback_by_reserve",
      &add_payback },
    /** #TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK */
    { "close_by_reserve",
      &add_exchange_to_bank },
    /* List terminator */
    { NULL,
      NULL }
  };
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_end
  };

  rhc.reserve_pub = reserve_pub;
  rhc.rh = NULL;
  rhc.rh_tail = NULL;
  rhc.status = GNUNET_OK;
  qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS; /* make static analysis happy */
  for (unsigned int i=0;NULL != work[i].cb;i++)
  {
    qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					       work[i].statement,
					       params,
					       work[i].cb,
					       &rhc);
    if ( (0 > qs) ||
	 (GNUNET_OK != rhc.status) )
      break;
  }
  if ( (qs < 0) ||
       (rhc.status != GNUNET_OK) )
  {
    common_free_reserve_history (cls,
                                 rhc.rh);
    rhc.rh = NULL;
    if (qs >= 0)
    {
      /* status == SYSERR is a very hard error... */
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  *rhp = rhc.rh;
  return qs;
}


/**
 * Check if we have the specified deposit already in the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param deposit deposit to search for
 * @param check_extras wether to check extra fields match or not
 * @return 1 if we know this operation,
 *         0 if this exact deposit is unknown to us,
 *         otherwise transaction error status
 */
static enum GNUNET_DB_QueryStatus
postgres_have_deposit (void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       const struct TALER_EXCHANGEDB_Deposit *deposit,
                       int check_extras)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_QueryParam no_params[] = {
    GNUNET_PQ_query_param_end
  };
  struct TALER_EXCHANGEDB_Deposit deposit2;
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount ("amount_with_fee",
                                 &deposit2.amount_with_fee),
    TALER_PQ_result_spec_absolute_time ("timestamp",
                                        &deposit2.timestamp),
    TALER_PQ_result_spec_absolute_time ("refund_deadline",
                                        &deposit2.refund_deadline),
    TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                        &deposit2.wire_deadline),
    GNUNET_PQ_result_spec_auto_from_type ("h_wire",
                                          &deposit2.h_wire),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  if (0 > (qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                                    "lock_deposit",
                                                    no_params)))
    return qs;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting deposits for coin %s\n",
              TALER_B2S (&deposit->coin.coin_pub));
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "get_deposit",
                                                 params,
                                                 rs);
  if (0 >= qs)
    return qs;
  /* Now we check that the other information in @a deposit
     also matches, and if not report inconsistencies. */
  if ( ( (check_extras) &&
         ( (0 != TALER_amount_cmp (&deposit->amount_with_fee,
                                   &deposit2.amount_with_fee)) ||
           (deposit->timestamp.abs_value_us !=
            deposit2.timestamp.abs_value_us) ) ) ||
       (deposit->refund_deadline.abs_value_us !=
        deposit2.refund_deadline.abs_value_us) ||
       (0 != GNUNET_memcmp (&deposit->h_wire,
                            &deposit2.h_wire) ) )
  {
    /* Inconsistencies detected! Does not match!  (We might want to
       expand the API with a 'get_deposit' function to return the
       original transaction details to be used for an error message
       in the future!) #3838 */
    return 0; /* Counts as if the transaction was not there */
  }
  return 1;
}


/**
 * Mark a deposit as tiny, thereby declaring that it cannot be
 * executed by itself and should no longer be returned by
 * @e iterate_ready_deposits()
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param rowid identifies the deposit row to modify
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_mark_deposit_tiny (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            uint64_t rowid)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "mark_deposit_tiny",
					     params);
}


/**
 * Test if a deposit was marked as done, thereby declaring that it cannot be
 * refunded anymore.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param deposit the deposit to check
 * @return #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT if is is marked done,
 *         #GNUNET_DB_STATUS_SUCCESS_NO_RESULTS if not,
 *         otherwise transaction error status (incl. deposit unknown)
 */
static enum GNUNET_DB_QueryStatus
postgres_test_deposit_done (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_wire),
    GNUNET_PQ_query_param_end
  };
  uint8_t done = 0;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("done",
					  &done),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						 "test_deposit_done",
						 params,
						 rs);
  if (qs < 0)
    return qs;
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return GNUNET_DB_STATUS_HARD_ERROR; /* deposit MUST exist */
  return (done
	  ? GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
	  : GNUNET_DB_STATUS_SUCCESS_NO_RESULTS);
}


/**
 * Mark a deposit as done, thereby declaring that it cannot be
 * executed at all anymore, and should no longer be returned by
 * @e iterate_ready_deposits() or @e iterate_matching_deposits().
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param rowid identifies the deposit row to modify
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_mark_deposit_done (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            uint64_t rowid)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "mark_deposit_done",
					     params);
}


/**
 * Obtain information about deposits that are ready to be executed.
 * Such deposits must not be marked as "tiny" or "done", and the
 * execution time must be in the past.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param deposit_cb function to call for ONE such deposit
 * @param deposit_cb_cls closure for @a deposit_cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_ready_deposit (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            TALER_EXCHANGEDB_DepositIterator deposit_cb,
                            void *deposit_cb_cls)
{
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct TALER_Amount amount_with_fee;
  struct TALER_Amount deposit_fee;
  struct GNUNET_TIME_Absolute wire_deadline;
  struct GNUNET_HashCode h_contract_terms;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  uint64_t serial_id;
  json_t *wire;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
				  &serial_id),
    TALER_PQ_result_spec_amount ("amount_with_fee",
				 &amount_with_fee),
    TALER_PQ_result_spec_amount ("fee_deposit",
				 &deposit_fee),
    TALER_PQ_result_spec_absolute_time ("wire_deadline",
					 &wire_deadline),
    GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
					  &h_contract_terms),
    GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
					  &merchant_pub),
    GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
					  &coin_pub),
    TALER_PQ_result_spec_json ("wire",
                               &wire),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  (void) GNUNET_TIME_round_abs (&now);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
	      "Finding ready deposits by deadline %s (%llu)\n",
	      GNUNET_STRINGS_absolute_time_to_string (now),
	      (unsigned long long) now.abs_value_us);

  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						 "deposits_get_ready",
						 params,
						 rs);
  if (qs <= 0)
    return qs;

  qs = deposit_cb (deposit_cb_cls,
		   serial_id,
		   &merchant_pub,
		   &coin_pub,
		   &amount_with_fee,
		   &deposit_fee,
		   &h_contract_terms,
		   wire_deadline,
		   wire);
  GNUNET_PQ_cleanup_result (rs);
  return qs;
}


/**
 * Closure for #match_deposit_cb().
 */
struct MatchingDepositContext
{
  /**
   * Function to call for each result
   */
  TALER_EXCHANGEDB_DepositIterator deposit_cb;

  /**
   * Closure for @e deposit_cb.
   */
  void *deposit_cb_cls;

  /**
   * Public key of the merchant against which we are matching.
   */
  const struct TALER_MerchantPublicKeyP *merchant_pub;

  /**
   * Maximum number of results to return.
   */
  uint32_t limit;

  /**
   * Loop counter, actual number of results returned.
   */
  unsigned int i;

  /**
   * Set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function for #postgres_iterate_matching_deposits().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct MatchingDepositContext *`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
match_deposit_cb (void *cls,
		  PGresult *result,
		  unsigned int num_results)
{
  struct MatchingDepositContext *mdc = cls;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Found %u/%u matching deposits\n",
	      num_results,
	      mdc->limit);
  num_results = GNUNET_MIN (num_results,
			    mdc->limit);
  for (mdc->i=0;mdc->i<num_results;mdc->i++)
  {
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct GNUNET_TIME_Absolute wire_deadline;
    struct GNUNET_HashCode h_contract_terms;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    uint64_t serial_id;
    enum GNUNET_DB_QueryStatus qs;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &serial_id),
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &amount_with_fee),
      TALER_PQ_result_spec_amount ("fee_deposit",
                                   &deposit_fee),
      TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                           &wire_deadline),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &h_contract_terms),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin_pub),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  mdc->i))
    {
      GNUNET_break (0);
      mdc->status = GNUNET_SYSERR;
      return;
    }
    qs = mdc->deposit_cb (mdc->deposit_cb_cls,
			  serial_id,
			  mdc->merchant_pub,
			  &coin_pub,
			  &amount_with_fee,
			  &deposit_fee,
			  &h_contract_terms,
			  wire_deadline,
			  NULL);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
      break;
  }
}


/**
 * Obtain information about other pending deposits for the same
 * destination.  Those deposits must not already be "done".
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param h_wire destination of the wire transfer
 * @param merchant_pub public key of the merchant
 * @param deposit_cb function to call for each deposit
 * @param deposit_cb_cls closure for @a deposit_cb
 * @param limit maximum number of matching deposits to return
 * @return transaction status code, if positive:
 *         number of rows processed, 0 if none exist
 */
static enum GNUNET_DB_QueryStatus
postgres_iterate_matching_deposits (void *cls,
                                    struct TALER_EXCHANGEDB_Session *session,
                                    const struct GNUNET_HashCode *h_wire,
                                    const struct TALER_MerchantPublicKeyP *merchant_pub,
                                    TALER_EXCHANGEDB_DepositIterator deposit_cb,
                                    void *deposit_cb_cls,
                                    uint32_t limit)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_wire),
    GNUNET_PQ_query_param_end
  };
  struct MatchingDepositContext mdc;
  enum GNUNET_DB_QueryStatus qs;

  mdc.deposit_cb = deposit_cb;
  mdc.deposit_cb_cls = deposit_cb_cls;
  mdc.merchant_pub = merchant_pub;
  mdc.limit = limit;
  mdc.status = GNUNET_OK;
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "deposits_iterate_matching",
					     params,
					     &match_deposit_cb,
					     &mdc);
  if (GNUNET_OK != mdc.status)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (qs >= 0)
    return mdc.i;
  return qs;
}


/**
 * Retrieve the record for a known coin.
 *
 * @param cls the plugin closure
 * @param session the database session handle
 * @param coin_pub the public key of the coin to search for
 * @param coin_info place holder for the returned coin information object
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_known_coin (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const struct TALER_CoinSpendPublicKeyP *coin_pub,
                         struct TALER_CoinPublicInfo *coin_info)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &coin_info->denom_pub_hash),
    GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
					 &coin_info->denom_sig.rsa_signature),
    GNUNET_PQ_result_spec_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting known coin data for coin %s\n",
              TALER_B2S (coin_pub));
  coin_info->coin_pub = *coin_pub;
  if (NULL == session)
    session = postgres_get_session (pc);
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "get_known_coin",
						   params,
						   rs);
}


/**
 * Insert a coin we know of into the DB.  The coin can then be
 * referenced by tables for deposits, refresh and refund
 * functionality.
 *
 * @param cls plugin closure
 * @param session the shared database session
 * @param coin_info the public coin info
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
insert_known_coin (void *cls,
                   struct TALER_EXCHANGEDB_Session *session,
                   const struct TALER_CoinPublicInfo *coin_info)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin_info->coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin_info->denom_pub_hash),
    GNUNET_PQ_query_param_rsa_signature (coin_info->denom_sig.rsa_signature),
    GNUNET_PQ_query_param_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Creating known coin %s\n",
              TALER_B2S (&coin_info->coin_pub));
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "insert_known_coin",
					     params);
}


/**
 * Count the number of known coins by denomination.
 *
 * @param cls database connection plugin state
 * @param session database session
 * @param denom_pub_hash denomination to count by
 * @return number of coins if non-negative, otherwise an `enum GNUNET_DB_QueryStatus`
 */
static long long
postgres_count_known_coins (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct GNUNET_HashCode *denom_pub_hash)
{
  uint64_t count;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("count",
                                  &count),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "count_known_coins",
                                                 params,
                                                 rs);
  if (0 > qs)
    return (long long) qs;
  return (long long) count;
}


/**
 * Make sure the given @a coin is known to the database.
 *
 * @param cls database connection plugin state
 * @param session database session
 * @param coin the coin that must be made known
 * @return database transaction status, non-negative on success
 */
static enum GNUNET_DB_QueryStatus
postgres_ensure_coin_known (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct TALER_CoinPublicInfo *coin)
{
  struct PostgresClosure *pc = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_CoinPublicInfo known_coin;

  /* check if the coin is already known */
  qs = postgres_get_known_coin (pc,
                                session,
                                &coin->coin_pub,
                                &known_coin);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    GNUNET_CRYPTO_rsa_signature_free (known_coin.denom_sig.rsa_signature);
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS; /* no change! */
  }
  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs);
  /* if not known, insert it */
  qs = insert_known_coin (pc,
			  session,
			  coin);
  if (0 >= qs)
  {
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      qs = GNUNET_DB_STATUS_HARD_ERROR; /* should be impossible */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  return qs;
}


/**
 * Insert information about deposited coin into the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session connection to the database
 * @param deposit deposit information to store
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_deposit (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    TALER_PQ_query_param_amount (&deposit->amount_with_fee),
    TALER_PQ_query_param_absolute_time (&deposit->timestamp),
    TALER_PQ_query_param_absolute_time (&deposit->refund_deadline),
    TALER_PQ_query_param_absolute_time (&deposit->wire_deadline),
    GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_wire),
    GNUNET_PQ_query_param_auto_from_type (&deposit->csig),
    TALER_PQ_query_param_json (deposit->receiver_wire_account),
    GNUNET_PQ_query_param_end
  };

#if 0
  enum GNUNET_DB_QueryStatus qs;

  if (0 > (qs = postgres_ensure_coin_known (cls,
                                            session,
                                            &deposit->coin)))
    return qs;
#endif
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
	      "Inserting deposit to be executed at %s (%llu/%llu)\n",
	      GNUNET_STRINGS_absolute_time_to_string (deposit->wire_deadline),
	      (unsigned long long) deposit->wire_deadline.abs_value_us,
	      (unsigned long long) deposit->refund_deadline.abs_value_us);
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "insert_deposit",
					     params);
}


/**
 * Insert information about refunded coin into the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param refund refund information to store
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_refund (void *cls,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_EXCHANGEDB_Refund *refund)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&refund->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->merchant_sig),
    GNUNET_PQ_query_param_auto_from_type (&refund->h_contract_terms),
    GNUNET_PQ_query_param_uint64 (&refund->rtransaction_id),
    TALER_PQ_query_param_amount (&refund->refund_amount),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (&refund->refund_amount,
                                            &refund->refund_fee));
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "insert_refund",
					     params);
}


/**
 * Closure for #get_refunds_cb().
 */
struct SelectRefundContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_RefundCoinCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Set to #GNUNET_SYSERR on error.
   */
  int status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct SelectRefundContext *`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
get_refunds_cb (void *cls,
		PGresult *result,
		unsigned int num_results)
{
  struct SelectRefundContext *srctx = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_MerchantPublicKeyP merchant_pub;
    struct TALER_MerchantSignatureP merchant_sig;
    struct GNUNET_HashCode h_contract;
    uint64_t rtransaction_id;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount refund_fee;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
					    &merchant_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_sig",
					    &merchant_sig),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
					    &h_contract),
      GNUNET_PQ_result_spec_uint64 ("rtransaction_id",
				    &rtransaction_id),
      TALER_PQ_result_spec_amount ("amount_with_fee",
				   &amount_with_fee),
      TALER_PQ_result_spec_amount ("fee_refund",
				   &refund_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
	GNUNET_PQ_extract_result (result,
				  rs,
				  i))
    {
      GNUNET_break (0);
      srctx->status = GNUNET_SYSERR;
      return;
    }
    if (GNUNET_OK !=
	srctx->cb (srctx->cb_cls,
		   &merchant_pub,
		   &merchant_sig,
		   &h_contract,
		   rtransaction_id,
		   &amount_with_fee,
		   &refund_fee))
      return;
  }
}


/**
 * Select refunds by @a coin_pub.
 *
 * @param cls closure of plugin
 * @param session database handle to use
 * @param coin_pub coin to get refunds for
 * @param cb function to call for each refund found
 * @param cb_cls closure for @a cb
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_select_refunds_by_coin (void *cls,
				 struct TALER_EXCHANGEDB_Session *session,
				 const struct TALER_CoinSpendPublicKeyP *coin_pub,
				 TALER_EXCHANGEDB_RefundCoinCallback cb,
				 void *cb_cls)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  struct SelectRefundContext srctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "get_refunds_by_coin",
                                             params,
                                             &get_refunds_cb,
                                             &srctx);
  if (GNUNET_SYSERR == srctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Lookup refresh melt commitment data under the given @a rc.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database handle to use, NULL if not run in any transaction
 * @param rc commitment hash to use to locate the operation
 * @param[out] refresh_melt where to store the result
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_melt (void *cls,
                   struct TALER_EXCHANGEDB_Session *session,
                   const struct TALER_RefreshCommitmentP *rc,
                   struct TALER_EXCHANGEDB_RefreshMelt *refresh_melt)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (rc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &refresh_melt->session.coin.denom_pub_hash),
    TALER_PQ_result_spec_amount ("fee_refresh",
                                 &refresh_melt->melt_fee),
    GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                         &refresh_melt->session.coin.denom_sig.rsa_signature),
    GNUNET_PQ_result_spec_uint32 ("noreveal_index",
                                  &refresh_melt->session.noreveal_index),
    GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                          &refresh_melt->session.coin.coin_pub),
    GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                          &refresh_melt->session.coin_sig),
    TALER_PQ_result_spec_amount ("amount_with_fee",
                                 &refresh_melt->session.amount_with_fee),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  if (NULL == session)
    session = postgres_get_session (pc);
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						 "get_melt",
						 params,
						 rs);
  refresh_melt->session.rc = *rc;
  return qs;
}


/**
 * Lookup noreveal index of a previous melt operation under the given
 * @a rc.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database handle to use
 * @param rc commitment hash to use to locate the operation
 * @param[out] refresh_melt where to store the result
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_melt_index (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const struct TALER_RefreshCommitmentP *rc,
                         uint32_t *noreveal_index)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (rc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint32 ("noreveal_index",
				  noreveal_index),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "get_melt_index",
                                                   params,
                                                   rs);
}


/**
 * Store new refresh melt commitment data.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database handle to use
 * @param refresh_session session data to store
 * @return query status for the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_melt (void *cls,
                      struct TALER_EXCHANGEDB_Session *session,
                      const struct TALER_EXCHANGEDB_RefreshSession *refresh_session)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&refresh_session->rc),
    GNUNET_PQ_query_param_auto_from_type (&refresh_session->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refresh_session->coin_sig),
    TALER_PQ_query_param_amount (&refresh_session->amount_with_fee),
    GNUNET_PQ_query_param_uint32 (&refresh_session->noreveal_index),
    GNUNET_PQ_query_param_end
  };
#if 0
  enum GNUNET_DB_QueryStatus qs;

  if (0 > (qs = postgres_ensure_coin_known (cls,
                                            session,
                                            &refresh_session->coin)))
    return qs;
#endif
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "insert_melt",
					     params);
}


/**
 * Store in the database which coin(s) the wallet wanted to create
 * in a given refresh operation and all of the other information
 * we learned or created in the /refresh/reveal step.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session database connection
 * @param rc identify commitment and thus refresh operation
 * @param num_rrcs_newcoins number of coins to generate, size of the
 *            @a rrcs array
 * @param rrcs information about the new coins
 * @param num_tprivs number of entries in @a tprivs, should be #TALER_CNC_KAPPA - 1
 * @param tprivs transfer private keys to store
 * @param tp public key to store
 * @return query status for the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_refresh_reveal (void *cls,
                                struct TALER_EXCHANGEDB_Session *session,
                                const struct TALER_RefreshCommitmentP *rc,
                                uint32_t num_rrcs,
                                const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
                                unsigned int num_tprivs,
                                const struct TALER_TransferPrivateKeyP *tprivs,
                                const struct TALER_TransferPublicKeyP *tp)
{
  if (TALER_CNC_KAPPA != num_tprivs + 1)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  for (uint32_t i=0;i<num_rrcs;i++)
  {
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &rrcs[i];
    struct GNUNET_HashCode denom_pub_hash;
    struct GNUNET_HashCode h_coin_ev;
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (rc),
      GNUNET_PQ_query_param_uint32 (&i),
      GNUNET_PQ_query_param_auto_from_type (&rrc->orig_coin_link_sig),
      GNUNET_PQ_query_param_auto_from_type (&denom_pub_hash),
      GNUNET_PQ_query_param_fixed_size (rrc->coin_ev,
                                        rrc->coin_ev_size),
      GNUNET_PQ_query_param_auto_from_type (&h_coin_ev),
      GNUNET_PQ_query_param_rsa_signature (rrc->coin_sig.rsa_signature),
      GNUNET_PQ_query_param_end
    };
    enum GNUNET_DB_QueryStatus qs;

    GNUNET_CRYPTO_rsa_public_key_hash (rrc->denom_pub.rsa_public_key,
                                       &denom_pub_hash);
    GNUNET_CRYPTO_hash (rrc->coin_ev,
                        rrc->coin_ev_size,
                        &h_coin_ev);
    qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_refresh_revealed_coin",
                                             params);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
      return qs;
  }

  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (rc),
      GNUNET_PQ_query_param_auto_from_type (tp),
      GNUNET_PQ_query_param_fixed_size (tprivs,
                                        num_tprivs * sizeof (struct TALER_TransferPrivateKeyP)),
      GNUNET_PQ_query_param_end
    };

    return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                               "insert_refresh_transfer_keys",
                                               params);
  }
}


/**
 * Context where we aggregate data from the database.
 * Closure for #add_revealed_coins().
 */
struct GetRevealContext
{
  /**
   * Array of revealed coins we obtained from the DB.
   */
  struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs;

  /**
   * Length of the @a rrcs array.
   */
  unsigned int rrcs_len;

  /**
   * Set to an error code if we ran into trouble.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct GetRevealContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
add_revealed_coins (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct GetRevealContext *grctx = cls;

  if (0 == num_results)
    return;
  grctx->rrcs = GNUNET_new_array (num_results,
                                  struct TALER_EXCHANGEDB_RefreshRevealedCoin);
  grctx->rrcs_len = num_results;
  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &grctx->rrcs[i];
    uint32_t off;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint32 ("newcoin_index",
                                    &off),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
					    &rrc->denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("link_sig",
                                            &rrc->orig_coin_link_sig),
      GNUNET_PQ_result_spec_variable_size ("coin_ev",
					   (void **) &rrc->coin_ev,
					   &rrc->coin_ev_size),
      GNUNET_PQ_result_spec_rsa_signature ("ev_sig",
                                           &rrc->coin_sig.rsa_signature),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    if (off != i)
    {
      GNUNET_break (0);
      grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
  }
}


/**
 * Lookup in the database the coins that we want to
 * create in the given refresh operation.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param rc identify commitment and thus refresh operation
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_refresh_reveal (void *cls,
                             struct TALER_EXCHANGEDB_Session *session,
                             const struct TALER_RefreshCommitmentP *rc,
                             TALER_EXCHANGEDB_RefreshCallback cb,
                             void *cb_cls)
{
  struct GetRevealContext grctx;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_TransferPublicKeyP tp;
  void *tpriv;
  size_t tpriv_size;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (rc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("transfer_pub",
                                          &tp),
    GNUNET_PQ_result_spec_variable_size ("transfer_privs",
                                         &tpriv,
                                         &tpriv_size),
    GNUNET_PQ_result_spec_end
  };

  /* First get the coins */
  memset (&grctx,
          0,
          sizeof (grctx));
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "get_refresh_revealed_coins",
                                             params,
                                             &add_revealed_coins,
                                             &grctx);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    goto cleanup;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
  default: /* can have more than one result */
    break;
  }
  switch (grctx.qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    goto cleanup;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT: /* should be impossible */
    break;
  }

  /* now also get the transfer keys (public and private) */
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "get_refresh_transfer_keys",
                                                 params,
                                                 rs);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    goto cleanup;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  default:
    GNUNET_assert (0);
  }
  if ( (0 != tpriv_size % sizeof (struct TALER_TransferPrivateKeyP)) ||
       (TALER_CNC_KAPPA - 1 != tpriv_size / sizeof (struct TALER_TransferPrivateKeyP)) )
  {
    GNUNET_break (0);
    qs = GNUNET_DB_STATUS_HARD_ERROR;
    GNUNET_PQ_cleanup_result (rs);
    goto cleanup;
  }

  /* Pass result back to application */
  cb (cb_cls,
      grctx.rrcs_len,
      grctx.rrcs,
      tpriv_size / sizeof (struct TALER_TransferPrivateKeyP),
      (const struct TALER_TransferPrivateKeyP *) tpriv,
      &tp);
  GNUNET_PQ_cleanup_result (rs);

 cleanup:
  for (unsigned int i = 0; i < grctx.rrcs_len; i++)
  {
    struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &grctx.rrcs[i];

    if (NULL != rrc->denom_pub.rsa_public_key)
      GNUNET_CRYPTO_rsa_public_key_free (rrc->denom_pub.rsa_public_key);
    if (NULL != rrc->coin_sig.rsa_signature)
      GNUNET_CRYPTO_rsa_signature_free (rrc->coin_sig.rsa_signature);
    GNUNET_free_non_null (rrc->coin_ev);
  }
  GNUNET_free_non_null (grctx.rrcs);

  return qs;
}


/**
 * Closure for #add_ldl().
 */
struct LinkDataContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_LinkDataCallback ldc;

  /**
   * Closure for @e ldc.
   */
  void *ldc_cls;

  /**
   * Last transfer public key for which we have information in @e last.
   * Only valid if @e last is non-NULL.
   */
  struct TALER_TransferPublicKeyP transfer_pub;

  /**
   * Link data for @e transfer_pub
   */
  struct TALER_EXCHANGEDB_LinkDataList *last;

  /**
   * Status, set to #GNUNET_SYSERR on errors,
   */
  int status;
};


/**
 * Free memory of the link data list.
 *
 * @param cls the @e cls of this struct with the plugin-specific state (unused)
 * @param ldl link data list to release
 */
static void
free_link_data_list (void *cls,
                     struct TALER_EXCHANGEDB_LinkDataList *ldl)
{
  struct TALER_EXCHANGEDB_LinkDataList *next;

  while (NULL != ldl)
  {
    next = ldl->next;
    if (NULL != ldl->denom_pub.rsa_public_key)
        GNUNET_CRYPTO_rsa_public_key_free (ldl->denom_pub.rsa_public_key);
      if (NULL != ldl->ev_sig.rsa_signature)
        GNUNET_CRYPTO_rsa_signature_free (ldl->ev_sig.rsa_signature);
    GNUNET_free (ldl);
    ldl = next;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct LinkDataContext *`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
add_ldl (void *cls,
         PGresult *result,
         unsigned int num_results)
{
  struct LinkDataContext *ldctx = cls;

  for (int i = num_results - 1; i >= 0; i--)
  {
    struct TALER_EXCHANGEDB_LinkDataList *pos;
    struct TALER_TransferPublicKeyP transfer_pub;

    pos = GNUNET_new (struct TALER_EXCHANGEDB_LinkDataList);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("transfer_pub",
                                              &transfer_pub),
        GNUNET_PQ_result_spec_auto_from_type ("link_sig",
                                              &pos->orig_coin_link_sig),
        GNUNET_PQ_result_spec_rsa_signature ("ev_sig",
                                             &pos->ev_sig.rsa_signature),
        GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                              &pos->denom_pub.rsa_public_key),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
	  GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
	GNUNET_break (0);
	GNUNET_free (pos);
	ldctx->status = GNUNET_SYSERR;
	return;
      }
    }
    if ( (NULL != ldctx->last) &&
         (0 == GNUNET_memcmp (&transfer_pub,
                              &ldctx->transfer_pub)) )
    {
      pos->next = ldctx->last;
    }
    else
    {
      if (NULL != ldctx->last)
      {
        ldctx->ldc (ldctx->ldc_cls,
                    &ldctx->transfer_pub,
                    ldctx->last);
        free_link_data_list (cls,
                             ldctx->last);
      }
      ldctx->transfer_pub = transfer_pub;
    }
    ldctx->last = pos;
  }
}


/**
 * Obtain the link data of a coin, that is the encrypted link
 * information, the denomination keys and the signatures.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param coin_pub public key of the coin
 * @param ldc function to call for each session the coin was melted into
 * @param ldc_cls closure for @a tdc
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_link_data (void *cls,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_CoinSpendPublicKeyP *coin_pub,
                        TALER_EXCHANGEDB_LinkDataCallback ldc,
                        void *ldc_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;
  struct LinkDataContext ldctx;

  ldctx.ldc = ldc;
  ldctx.ldc_cls = ldc_cls;
  ldctx.last = NULL;
  ldctx.status = GNUNET_OK;
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "get_link",
                                             params,
                                             &add_ldl,
                                             &ldctx);
  if (NULL != ldctx.last)
  {
    if (GNUNET_OK == ldctx.status)
    {
      /* call callback one more time! */
      ldc (ldc_cls,
           &ldctx.transfer_pub,
           ldctx.last);
    }
    free_link_data_list (cls,
                         ldctx.last);
    ldctx.last = NULL;
  }
  if (GNUNET_OK != ldctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for callbacks called from #postgres_get_coin_transactions()
 */
struct CoinHistoryContext
{
  /**
   * Head of the coin's history list.
   */
  struct TALER_EXCHANGEDB_TransactionList *head;

  /**
   * Public key of the coin we are building the history for.
   */
  const struct TALER_CoinSpendPublicKeyP *coin_pub;

  /**
   * Closure for all callbacks of this database plugin.
   */
  void *db_cls;

  /**
   * Database session we are using.
   */
  struct TALER_EXCHANGEDB_Session *session;

  /**
   * Set to transaction status.
   */
  enum GNUNET_DB_QueryStatus status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
add_coin_deposit (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_EXCHANGEDB_Deposit *deposit;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    enum GNUNET_DB_QueryStatus qs;

    deposit = GNUNET_new (struct TALER_EXCHANGEDB_Deposit);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_result_spec_amount ("amount_with_fee",
                                     &deposit->amount_with_fee),
        TALER_PQ_result_spec_amount ("fee_deposit",
                                     &deposit->deposit_fee),
        TALER_PQ_result_spec_absolute_time ("timestamp",
                                            &deposit->timestamp),
        TALER_PQ_result_spec_absolute_time ("refund_deadline",
                                            &deposit->refund_deadline),
        TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                            &deposit->wire_deadline),
        GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                              &deposit->merchant_pub),
        GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                              &deposit->h_contract_terms),
        GNUNET_PQ_result_spec_auto_from_type ("h_wire",
                                              &deposit->h_wire),
        TALER_PQ_result_spec_json ("wire",
                                   &deposit->receiver_wire_account),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &deposit->csig),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (deposit);
        chc->status = GNUNET_DB_STATUS_HARD_ERROR;
        return;
      }
      deposit->coin.coin_pub = *chc->coin_pub;
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_DEPOSIT;
    tl->details.deposit = deposit;
    qs = postgres_get_known_coin (chc->db_cls,
                                  chc->session,
                                  chc->coin_pub,
                                  &deposit->coin);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_free (deposit);
      chc->status = qs;
      return;
    }
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
add_coin_melt (void *cls,
               PGresult *result,
               unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_EXCHANGEDB_RefreshMelt *melt;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    enum GNUNET_DB_QueryStatus qs;

    melt = GNUNET_new (struct TALER_EXCHANGEDB_RefreshMelt);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
  	    GNUNET_PQ_result_spec_auto_from_type ("rc",
                                              &melt->session.rc),
        /* oldcoin_index not needed */
        GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                              &melt->session.coin_sig),
        TALER_PQ_result_spec_amount ("amount_with_fee",
                                     &melt->session.amount_with_fee),
        TALER_PQ_result_spec_amount ("fee_refresh",
                                     &melt->melt_fee),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (melt);
        chc->status = GNUNET_DB_STATUS_HARD_ERROR;
        return;
      }
      melt->session.coin.coin_pub = *chc->coin_pub;
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_REFRESH_MELT;
    tl->details.melt = melt;
    /* FIXME: integrate via JOIN in main select, instead of using separate query */
    qs = postgres_get_known_coin (chc->db_cls,
                                  chc->session,
                                  chc->coin_pub,
                                  &melt->session.coin);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_free (melt);
      chc->status = qs;
      return;
    }
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
add_coin_refund (void *cls,
                 PGresult *result,
                 unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_EXCHANGEDB_Refund *refund;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    enum GNUNET_DB_QueryStatus qs;

    refund = GNUNET_new (struct TALER_EXCHANGEDB_Refund);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                              &refund->merchant_pub),
        GNUNET_PQ_result_spec_auto_from_type ("merchant_sig",
                                              &refund->merchant_sig),
        GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                              &refund->h_contract_terms),
        GNUNET_PQ_result_spec_uint64 ("rtransaction_id",
                                      &refund->rtransaction_id),
        TALER_PQ_result_spec_amount ("amount_with_fee",
                                     &refund->refund_amount),
        TALER_PQ_result_spec_amount ("fee_refund",
                                     &refund->refund_fee),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (refund);
        chc->status = GNUNET_DB_STATUS_HARD_ERROR;
        return;
      }
      refund->coin.coin_pub = *chc->coin_pub;
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_REFUND;
    tl->details.refund = refund;
    qs = postgres_get_known_coin (chc->db_cls,
                                  chc->session,
                                  chc->coin_pub,
                                  &refund->coin);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_free (refund);
      chc->status = qs;
      return;
    }
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
add_old_coin_payback (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_EXCHANGEDB_PaybackRefresh *payback;
    struct TALER_EXCHANGEDB_TransactionList *tl;

    payback = GNUNET_new (struct TALER_EXCHANGEDB_PaybackRefresh);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                              &payback->coin.coin_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &payback->coin_sig),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &payback->coin_blind),
        TALER_PQ_result_spec_amount ("amount",
                                     &payback->value),
        TALER_PQ_result_spec_absolute_time ("timestamp",
                                            &payback->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &payback->coin.denom_pub_hash),
        GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                             &payback->coin.denom_sig.rsa_signature),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (payback);
        chc->status = GNUNET_DB_STATUS_HARD_ERROR;
        return;
      }
      payback->old_coin_pub = *chc->coin_pub;
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_OLD_COIN_PAYBACK;
    tl->details.old_coin_payback = payback;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
add_coin_payback (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_EXCHANGEDB_Payback *payback;
    struct TALER_EXCHANGEDB_TransactionList *tl;

    payback = GNUNET_new (struct TALER_EXCHANGEDB_Payback);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_result_spec_amount ("amount",
                                     &payback->value),
        GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                              &payback->reserve_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &payback->coin_blind),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &payback->coin_sig),
        TALER_PQ_result_spec_absolute_time ("timestamp",
                                            &payback->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &payback->coin.denom_pub_hash),
        GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                             &payback->coin.denom_sig.rsa_signature),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (payback);
        chc->status = GNUNET_DB_STATUS_HARD_ERROR;
        return;
      }
      payback->coin.coin_pub = *chc->coin_pub;
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_PAYBACK;
    tl->details.payback = payback;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
add_coin_payback_refresh (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_EXCHANGEDB_PaybackRefresh *payback;
    struct TALER_EXCHANGEDB_TransactionList *tl;

    payback = GNUNET_new (struct TALER_EXCHANGEDB_PaybackRefresh);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                              &payback->old_coin_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &payback->coin_sig),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &payback->coin_blind),
        TALER_PQ_result_spec_amount ("amount",
                                     &payback->value),
        TALER_PQ_result_spec_absolute_time ("timestamp",
                                            &payback->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &payback->coin.denom_pub_hash),
        GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                             &payback->coin.denom_sig.rsa_signature),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (payback);
        chc->status = GNUNET_DB_STATUS_HARD_ERROR;
        return;
      }
      payback->coin.coin_pub = *chc->coin_pub;
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_PAYBACK_REFRESH;
    tl->details.payback_refresh = payback;
    chc->head = tl;
  }
}


/**
 * Work we need to do.
 */
struct Work
{
  /**
   * SQL prepared statement name.
   */
  const char *statement;

  /**
   * Function to call to handle the result(s).
   */
  GNUNET_PQ_PostgresResultHandler cb;
};


/**
 * Compile a list of all (historic) transactions performed with the given coin
 * (/refresh/melt, /deposit, /refund and /payback operations).
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param coin_pub coin to investigate
 * @param[out] tlp set to list of transactions, NULL if coin is fresh
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_coin_transactions (void *cls,
                                struct TALER_EXCHANGEDB_Session *session,
                                const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                int include_payback,
                                struct TALER_EXCHANGEDB_TransactionList **tlp)
{
  static const struct Work work_op[] = {
    /** #TALER_EXCHANGEDB_TT_DEPOSIT */
    { "get_deposit_with_coin_pub",
      &add_coin_deposit },
    /** #TALER_EXCHANGEDB_TT_REFRESH_MELT */
    { "get_refresh_session_by_coin",
      &add_coin_melt },
    /** #TALER_EXCHANGEDB_TT_REFUND */
    { "get_refunds_by_coin",
      &add_coin_refund },
    { NULL, NULL }
  };
  static const struct Work work_wp[] = {
    /** #TALER_EXCHANGEDB_TT_DEPOSIT */
    { "get_deposit_with_coin_pub",
      &add_coin_deposit },
    /** #TALER_EXCHANGEDB_TT_REFRESH_MELT */
    { "get_refresh_session_by_coin",
      &add_coin_melt },
    /** #TALER_EXCHANGEDB_TT_REFUND */
    { "get_refunds_by_coin",
      &add_coin_refund },
    /** #TALER_EXCHANGEDB_TT_OLD_COIN_PAYBACK */
    { "payback_by_old_coin",
      &add_old_coin_payback },
    /** #TALER_EXCHANGEDB_TT_PAYBACK */
    { "payback_by_coin",
      &add_coin_payback },
    /** #TALER_EXCHANGEDB_TT_PAYBACK_REFRESH */
    { "payback_by_refreshed_coin",
      &add_coin_payback_refresh },
    { NULL, NULL }
  };
  struct CoinHistoryContext chc;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;
  const struct Work * work;

  work = (GNUNET_YES == include_payback) ? work_wp : work_op;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting transactions for coin %s\n",
              TALER_B2S (coin_pub));
  chc.head = NULL;
  chc.status = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  chc.coin_pub = coin_pub;
  chc.session = session;
  chc.db_cls = cls;
  for (unsigned int i=0;NULL != work[i].statement; i++)
  {
    qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                               work[i].statement,
                                               params,
                                               work[i].cb,
                                               &chc);
    if ( (0 > qs) ||
	 (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != chc.status) )
    {
      if (NULL != chc.head)
        common_free_coin_transaction_list (cls,
                                           chc.head);
      *tlp = NULL;
      if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != chc.status)
        qs = chc.status;
      return qs;
    }
  }
  *tlp = chc.head;
  if (NULL == chc.head)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Closure for #handle_wt_result.
 */
struct WireTransferResultContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_WireTransferDataCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Set to #GNUNET_SYSERR on serious errors.
   */
  int status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.  Helper function
 * for #postgres_lookup_wire_transfer().
 *
 * @param cls closure of type `struct WireTransferResultContext *`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
handle_wt_result (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct WireTransferResultContext *ctx = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    uint64_t rowid;
    struct GNUNET_HashCode h_contract_terms;
    struct GNUNET_HashCode h_wire;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_MerchantPublicKeyP merchant_pub;
    struct GNUNET_TIME_Absolute exec_time;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct TALER_DenominationPublicKey denom_pub;
    json_t *wire;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("aggregation_serial_id", &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms", &h_contract_terms),
      TALER_PQ_result_spec_json ("wire", &wire),
      GNUNET_PQ_result_spec_auto_from_type ("h_wire", &h_wire),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub", &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub", &coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub", &merchant_pub),
      TALER_PQ_result_spec_absolute_time ("execution_date", &exec_time),
      TALER_PQ_result_spec_amount ("amount_with_fee", &amount_with_fee),
      TALER_PQ_result_spec_amount ("fee_deposit", &deposit_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->status = GNUNET_SYSERR;
      return;
    }
    ctx->cb (ctx->cb_cls,
             rowid,
             &merchant_pub,
             &h_wire,
             wire,
             exec_time,
             &h_contract_terms,
             &denom_pub,
             &coin_pub,
             &amount_with_fee,
             &deposit_fee);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Lookup the list of Taler transactions that were aggregated
 * into a wire transfer by the respective @a wtid.
 *
 * @param cls closure
 * @param session database connection
 * @param wtid the raw wire transfer identifier we used
 * @param cb function to call on each transaction found
 * @param cb_cls closure for @a cb
 * @return query status of the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_wire_transfer (void *cls,
                               struct TALER_EXCHANGEDB_Session *session,
                               const struct TALER_WireTransferIdentifierRawP *wtid,
                               TALER_EXCHANGEDB_WireTransferDataCallback cb,
                               void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };
  struct WireTransferResultContext ctx;
  enum GNUNET_DB_QueryStatus qs;

  ctx.cb = cb;
  ctx.cb_cls = cb_cls;
  ctx.status = GNUNET_OK;
  /* check if the melt record exists and get it */
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "lookup_transactions",
                                             params,
                                             &handle_wt_result,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Try to find the wire transfer details for a deposit operation.
 * If we did not execute the deposit yet, return when it is supposed
 * to be executed.
 *
 * @param cls closure
 * @param session database connection
 * @param h_contract_terms hash of the proposal data
 * @param h_wire hash of merchant wire details
 * @param coin_pub public key of deposited coin
 * @param merchant_pub merchant public key
 * @param cb function to call with the result
 * @param cb_cls closure to pass to @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_lookup_deposit_wtid (void *cls,
                                   struct TALER_EXCHANGEDB_Session *session,
				   const struct GNUNET_HashCode *h_contract_terms,
				   const struct GNUNET_HashCode *h_wire,
				   const struct TALER_CoinSpendPublicKeyP *coin_pub,
				   const struct TALER_MerchantPublicKeyP *merchant_pub,
				   TALER_EXCHANGEDB_TrackTransactionCallback cb,
				   void *cb_cls)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (h_wire),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_end
  };
  struct TALER_WireTransferIdentifierRawP wtid;
  struct GNUNET_TIME_Absolute exec_time;
  struct TALER_Amount amount_with_fee;
  struct TALER_Amount deposit_fee;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("wtid_raw", &wtid),
    TALER_PQ_result_spec_absolute_time ("execution_date", &exec_time),
    TALER_PQ_result_spec_amount ("amount_with_fee", &amount_with_fee),
    TALER_PQ_result_spec_amount ("fee_deposit", &deposit_fee),
    GNUNET_PQ_result_spec_end
  };

  /* check if the melt record exists and get it */
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						 "lookup_deposit_wtid",
						 params,
						 rs);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    cb (cb_cls,
        &wtid,
        &amount_with_fee,
        &deposit_fee,
        exec_time);
    return qs;
  }
  if (0 > qs)
    return qs;

  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
	      "lookup_deposit_wtid returned 0 matching rows\n");
  {
    /* Check if transaction exists in deposits, so that we just
       do not have a WTID yet, if so, do call the CB with a NULL wtid
       and return #GNUNET_YES! */
    struct GNUNET_PQ_QueryParam params2[] = {
      GNUNET_PQ_query_param_auto_from_type (coin_pub),
      GNUNET_PQ_query_param_auto_from_type (merchant_pub),
      GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
      GNUNET_PQ_query_param_auto_from_type (h_wire),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_TIME_Absolute exec_time;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct GNUNET_PQ_ResultSpec rs2[] = {
      TALER_PQ_result_spec_amount ("amount_with_fee", &amount_with_fee),
      TALER_PQ_result_spec_amount ("fee_deposit", &deposit_fee),
      TALER_PQ_result_spec_absolute_time ("wire_deadline", &exec_time),
      GNUNET_PQ_result_spec_end
    };

    qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "get_deposit_for_wtid",
						   params2,
						   rs2);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    {
      /* Ok, we're aware of the transaction, but it has not yet been
	 executed */
      cb (cb_cls,
          NULL,
          &amount_with_fee,
          &deposit_fee,
          exec_time);
      return qs;
    }
    return qs;
  }
}


/**
 * Function called to insert aggregation information into the DB.
 *
 * @param cls closure
 * @param session database connection
 * @param wtid the raw wire transfer identifier we used
 * @param deposit_serial_id row in the deposits table for which this is aggregation data
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_aggregation_tracking (void *cls,
                                      struct TALER_EXCHANGEDB_Session *session,
                                      const struct TALER_WireTransferIdentifierRawP *wtid,
                                      unsigned long long deposit_serial_id)
{
  uint64_t rid = deposit_serial_id;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rid),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "insert_aggregation_tracking",
					     params);
}


/**
 * Obtain wire fee from database.
 *
 * @param cls closure
 * @param session database connection
 * @param type type of wire transfer the fee applies for
 * @param date for which date do we want the fee?
 * @param[out] start_date when does the fee go into effect
 * @param[out] end_date when does the fee end being valid
 * @param[out] wire_fee how high is the wire transfer fee
 * @param[out] closing_fee how high is the closing fee
 * @param[out] master_sig signature over the above by the exchange master key
 * @return status of the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_get_wire_fee (void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       const char *type,
                       struct GNUNET_TIME_Absolute date,
                       struct GNUNET_TIME_Absolute *start_date,
                       struct GNUNET_TIME_Absolute *end_date,
                       struct TALER_Amount *wire_fee,
		       struct TALER_Amount *closing_fee,
                       struct TALER_MasterSignatureP *master_sig)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    TALER_PQ_query_param_absolute_time (&date),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_absolute_time ("start_date", start_date),
    TALER_PQ_result_spec_absolute_time ("end_date", end_date),
    TALER_PQ_result_spec_amount ("wire_fee", wire_fee),
    TALER_PQ_result_spec_amount ("closing_fee", closing_fee),
    GNUNET_PQ_result_spec_auto_from_type ("master_sig", master_sig),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "get_wire_fee",
						   params,
						   rs);
}


/**
 * Insert wire transfer fee into database.
 *
 * @param cls closure
 * @param session database connection
 * @param type type of wire transfer this fee applies for
 * @param start_date when does the fee go into effect
 * @param end_date when does the fee end being valid
 * @param wire_fee how high is the wire transfer fee
 * @param closing_fee how high is the closing fee
 * @param master_sig signature over the above by the exchange master key
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_wire_fee (void *cls,
                          struct TALER_EXCHANGEDB_Session *session,
                          const char *type,
                          struct GNUNET_TIME_Absolute start_date,
                          struct GNUNET_TIME_Absolute end_date,
                          const struct TALER_Amount *wire_fee,
                          const struct TALER_Amount *closing_fee,
                          const struct TALER_MasterSignatureP *master_sig)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    TALER_PQ_query_param_absolute_time (&start_date),
    TALER_PQ_query_param_absolute_time (&end_date),
    TALER_PQ_query_param_amount (wire_fee),
    TALER_PQ_query_param_amount (closing_fee),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };
  struct TALER_Amount wf;
  struct TALER_Amount cf;
  struct TALER_MasterSignatureP sig;
  struct GNUNET_TIME_Absolute sd;
  struct GNUNET_TIME_Absolute ed;
  enum GNUNET_DB_QueryStatus qs;

  qs = postgres_get_wire_fee (cls,
			      session,
			      type,
			      start_date,
			      &sd,
			      &ed,
			      &wf,
			      &cf,
			      &sig);
  if (qs < 0)
    return qs;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    if (0 != GNUNET_memcmp (&sig,
                            master_sig))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (0 != TALER_amount_cmp (wire_fee,
                               &wf))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (0 != TALER_amount_cmp (closing_fee,
                               &cf))
      {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (sd.abs_value_us != start_date.abs_value_us) ||
         (ed.abs_value_us != end_date.abs_value_us) )
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    /* equal record already exists */
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "insert_wire_fee",
					     params);
}


/**
 * Closure for #reserve_expired_cb().
 */
struct ExpiredReserveContext
{
  /**
   * Function to call for each expired reserve.
   */
  TALER_EXCHANGEDB_ReserveExpiredCallback rec;

  /**
   * Closure to give to @e rec.
   */
  void *rec_cls;

  /**
   * Set to #GNUNET_SYSERR on error.
   */
  int status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
reserve_expired_cb (void *cls,
		    PGresult *result,
		    unsigned int num_results)
{
  struct ExpiredReserveContext *erc = cls;
  int ret;

  ret = GNUNET_OK;
  for (unsigned int i=0;i<num_results;i++)
  {
    struct GNUNET_TIME_Absolute exp_date;
    char *account_details;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_Amount remaining_balance;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_absolute_time ("expiration_date",
					   &exp_date),
      GNUNET_PQ_result_spec_string ("account_details",
                                    &account_details),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
					    &reserve_pub),
      TALER_PQ_result_spec_amount ("current_balance",
				   &remaining_balance),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
	GNUNET_PQ_extract_result (result,
				  rs,
				  i))
    {
      GNUNET_break (0);
      ret = GNUNET_SYSERR;
      break;
    }
    ret = erc->rec (erc->rec_cls,
		    &reserve_pub,
		    &remaining_balance,
		    account_details,
		    exp_date);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
  erc->status = ret;
}


/**
 * Obtain information about expired reserves and their
 * remaining balances.
 *
 * @param cls closure of the plugin
 * @param session database connection
 * @param now timestamp based on which we decide expiration
 * @param rec function to call on expired reserves
 * @param rec_cls closure for @a rec
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_expired_reserves (void *cls,
			       struct TALER_EXCHANGEDB_Session *session,
			       struct GNUNET_TIME_Absolute now,
			       TALER_EXCHANGEDB_ReserveExpiredCallback rec,
			       void *rec_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct ExpiredReserveContext ectx;
  enum GNUNET_DB_QueryStatus qs;

  ectx.rec = rec;
  ectx.rec_cls = rec_cls;
  ectx.status = GNUNET_OK;
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "get_expired_reserves",
					     params,
					     &reserve_expired_cb,
					     &ectx);
  if (GNUNET_OK != ectx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Insert reserve close operation into database.
 *
 * @param cls closure
 * @param session database connection
 * @param reserve_pub which reserve is this about?
 * @param execution_date when did we perform the transfer?
 * @param receiver_account to which account do we transfer?
 * @param wtid wire transfer details
 * @param amount_with_fee amount we charged to the reserve
 * @param closing_fee how high is the closing fee
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_reserve_closed (void *cls,
				struct TALER_EXCHANGEDB_Session *session,
				const struct TALER_ReservePublicKeyP *reserve_pub,
				struct GNUNET_TIME_Absolute execution_date,
				const char *receiver_account,
				const struct TALER_WireTransferIdentifierRawP *wtid,
				const struct TALER_Amount *amount_with_fee,
				const struct TALER_Amount *closing_fee)
{
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    TALER_PQ_query_param_absolute_time (&execution_date),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_string (receiver_account),
    TALER_PQ_query_param_amount (amount_with_fee),
    TALER_PQ_query_param_amount (closing_fee),
    GNUNET_PQ_query_param_end
  };
  int ret;
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                           "reserves_close_insert",
                                           params);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    return qs;

  /* update reserve balance */
  reserve.pub = *reserve_pub;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      (qs = postgres_reserve_get (cls,
                                  session,
                                  &reserve)))
  {
    /* Existence should have been checked before we got here... */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    return qs;
  }
  ret = TALER_amount_subtract (&reserve.balance,
                               &reserve.balance,
                               amount_with_fee);
  if (GNUNET_SYSERR == ret)
  {
    /* The reserve history was checked to make sure there is enough of a balance
       left before we tried this; however, concurrent operations may have changed
       the situation by now.  We should re-try the transaction.  */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Closing of reserve `%s' refused due to balance missmatch. Retrying.\n",
                TALER_B2S (reserve_pub));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_break (GNUNET_NO == ret);
  return reserves_update (cls,
                          session,
                          &reserve);
}


/**
 * Function called to insert wire transfer commit data into the DB.
 *
 * @param cls closure
 * @param session database connection
 * @param type type of the wire transfer (i.e. "iban")
 * @param buf buffer with wire transfer preparation data
 * @param buf_size number of bytes in @a buf
 * @return query status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_insert (void *cls,
                                   struct TALER_EXCHANGEDB_Session *session,
                                   const char *type,
                                   const char *buf,
                                   size_t buf_size)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    GNUNET_PQ_query_param_fixed_size (buf, buf_size),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "wire_prepare_data_insert",
					     params);
}


/**
 * Function called to mark wire transfer commit data as finished.
 *
 * @param cls closure
 * @param session database connection
 * @param rowid which entry to mark as finished
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_mark_finished (void *cls,
                                          struct TALER_EXCHANGEDB_Session *session,
                                          uint64_t rowid)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "wire_prepare_data_mark_done",
					     params);
}


/**
 * Function called to get an unfinished wire transfer
 * preparation data. Fetches at most one item.
 *
 * @param cls closure
 * @param session database connection
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_get (void *cls,
                                struct TALER_EXCHANGEDB_Session *session,
                                TALER_EXCHANGEDB_WirePreparationIterator cb,
                                void *cb_cls)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  uint64_t prewire_uuid;
  char *type;
  void *buf = NULL;
  size_t buf_size;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("prewire_uuid",
				  &prewire_uuid),
    GNUNET_PQ_result_spec_string ("type",
				  &type),
    GNUNET_PQ_result_spec_variable_size ("buf",
					 &buf,
					 &buf_size),
    GNUNET_PQ_result_spec_end
  };

  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						 "wire_prepare_data_get",
						 params,
						 rs);
  if (0 >= qs)
    return qs;
  cb (cb_cls,
      prewire_uuid,
      type,
      buf,
      buf_size);
  GNUNET_PQ_cleanup_result (rs);
  return qs;
}


/**
 * Start a transaction where we transiently violate the foreign
 * constraints on the "wire_out" table as we insert aggregations
 * and only add the wire transfer out at the end.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @return #GNUNET_OK on success
 */
static int
postgres_start_deferred_wire_out (void *cls,
                                  struct TALER_EXCHANGEDB_Session *session)
{
  PGresult *result;
  ExecStatusType ex;

  postgres_preflight (cls,
                      session);
  if (GNUNET_OK !=
      postgres_start (cls,
                      session,
                      "deferred wire out"))
    return GNUNET_SYSERR;
  result = PQexec (session->conn,
                   "SET CONSTRAINTS wire_out_ref DEFERRED");
  if (PGRES_COMMAND_OK !=
      (ex = PQresultStatus (result)))
  {
    TALER_LOG_ERROR ("Failed to defer wire_out_ref constraint on transaction (%s): %s\n",
                     PQresStatus (ex),
                     PQerrorMessage (session->conn));
    GNUNET_break (0);
    PQclear (result);
    postgres_rollback (cls,
                       session);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Store information about an outgoing wire transfer that was executed.
 *
 * @param cls closure
 * @param session database connection
 * @param date time of the wire transfer
 * @param wtid subject of the wire transfer
 * @param wire_account details about the receiver account of the wire transfer
 * @param exchange_account_section configuration section of the exchange specifying the
 *        exchange's bank account being used
 * @param amount amount that was transmitted
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_store_wire_transfer_out (void *cls,
                                  struct TALER_EXCHANGEDB_Session *session,
                                  struct GNUNET_TIME_Absolute date,
                                  const struct TALER_WireTransferIdentifierRawP *wtid,
                                  const json_t *wire_account,
                                  const char *exchange_account_section,
                                  const struct TALER_Amount *amount)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&date),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    TALER_PQ_query_param_json (wire_account),
    GNUNET_PQ_query_param_string (exchange_account_section),
    TALER_PQ_query_param_amount (amount),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "insert_wire_out",
					     params);
}


/**
 * Function called to perform "garbage collection" on the
 * database, expiring records we no longer require.
 *
 * @param cls closure
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR on DB errors
 */
static int
postgres_gc (void *cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute long_ago;
  struct GNUNET_PQ_QueryParam params_none[] = {
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_QueryParam params_time[] = {
    TALER_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_QueryParam params_ancient_time[] = {
    TALER_PQ_query_param_absolute_time (&long_ago),
    GNUNET_PQ_query_param_end
  };
  PGconn *conn;
  int ret;

  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  /* Keep wire fees for 10 years, that should always
     be enough _and_ they are tiny so it does not
     matter to make this tight */
  long_ago = GNUNET_TIME_absolute_subtract (now,
                                            GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_YEARS,
                                                                           10));
  /* FIXME: use GNUNET_PQ_connect_with_cfg instead? */
  conn = GNUNET_PQ_connect (pc->connection_cfg_str);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = postgres_prepare (conn);
  if (GNUNET_OK == ret)
  {
    if (
	 (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                              "gc_reserves",
                                              params_time)) ||
	 (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                              "gc_prewire",
                                              params_none)) ||
	 (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                              "gc_wire_fee",
                                              params_ancient_time))
	)
      ret = GNUNET_SYSERR;
    /* This one may fail due to foreign key constraints from
       payback and reserves_out tables to known_coins; these
       are NOT using 'ON DROP CASCADE' and might keep denomination
       keys alive for a bit longer, thus causing this statement
       to fail. */
    (void) GNUNET_PQ_eval_prepared_non_select (conn,
					       "gc_denominations",
					       params_time);
  }
  PQfinish (conn);
  return ret;
}


/**
 * Closure for #deposit_serial_helper_cb().
 */
struct DepositSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_DepositCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct DepositSerialContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
deposit_serial_helper_cb (void *cls,
			  PGresult *result,
			  unsigned int num_results)
{
  struct DepositSerialContext *dsc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_EXCHANGEDB_Deposit deposit;
    struct TALER_DenominationPublicKey denom_pub;
    uint8_t done = 0;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &deposit.amount_with_fee),
      TALER_PQ_result_spec_absolute_time ("timestamp",
                                          &deposit.timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &deposit.merchant_pub),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                           &deposit.coin.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                           &deposit.csig),
      TALER_PQ_result_spec_absolute_time ("refund_deadline",
                                           &deposit.refund_deadline),
      TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                           &deposit.wire_deadline),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                           &deposit.h_contract_terms),
      TALER_PQ_result_spec_json ("wire",
                                 &deposit.receiver_wire_account),
      GNUNET_PQ_result_spec_auto_from_type ("done",
                                            &done),
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      dsc->status = GNUNET_SYSERR;
      return;
    }
    ret = dsc->cb (dsc->cb_cls,
		   rowid,
		   deposit.timestamp,
		   &deposit.merchant_pub,
		   &denom_pub,
		   &deposit.coin.coin_pub,
		   &deposit.csig,
		   &deposit.amount_with_fee,
		   &deposit.h_contract_terms,
		   deposit.refund_deadline,
		   deposit.wire_deadline,
		   deposit.receiver_wire_account,
		   done);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select deposits above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_deposits_above_serial_id (void *cls,
                                          struct TALER_EXCHANGEDB_Session *session,
                                          uint64_t serial_id,
                                          TALER_EXCHANGEDB_DepositCallback cb,
                                          void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct DepositSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "audit_get_deposits_incr",
					     params,
					     &deposit_serial_helper_cb,
					     &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #refreshs_serial_helper_cb().
 */
struct RefreshsSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_RefreshSessionCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct RefreshsSerialContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
refreshs_serial_helper_cb (void *cls,
			   PGresult *result,
			   unsigned int num_results)
{
  struct RefreshsSerialContext *rsc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_CoinSpendSignatureP coin_sig;
    struct TALER_Amount amount_with_fee;
    uint32_t noreveal_index;
    uint64_t rowid;
    struct TALER_RefreshCommitmentP rc;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                            &coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                            &coin_sig),
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_uint32 ("noreveal_index",
                                    &noreveal_index),
      GNUNET_PQ_result_spec_uint64 ("melt_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("rc",
                                            &rc),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rsc->status = GNUNET_SYSERR;
      return;
    }
    ret = rsc->cb (rsc->cb_cls,
		   rowid,
		   &denom_pub,
		   &coin_pub,
		   &coin_sig,
		   &amount_with_fee,
		   noreveal_index,
		   &rc);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select refresh sessions above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_refreshs_above_serial_id (void *cls,
                                          struct TALER_EXCHANGEDB_Session *session,
                                          uint64_t serial_id,
                                          TALER_EXCHANGEDB_RefreshSessionCallback cb,
                                          void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct RefreshsSerialContext rsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "audit_get_refresh_commitments_incr",
					     params,
					     &refreshs_serial_helper_cb,
					     &rsc);
  if (GNUNET_OK != rsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #refunds_serial_helper_cb().
 */
struct RefundsSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_RefundCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct RefundsSerialContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
refunds_serial_helper_cb (void *cls,
			  PGresult *result,
			  unsigned int num_results)
{
  struct RefundsSerialContext *rsc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_EXCHANGEDB_Refund refund;
    struct TALER_DenominationPublicKey denom_pub;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &refund.merchant_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_sig",
                                           &refund.merchant_sig),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                           &refund.h_contract_terms),
      GNUNET_PQ_result_spec_uint64 ("rtransaction_id",
                                    &refund.rtransaction_id),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                           &refund.coin.coin_pub),
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &refund.refund_amount),
      GNUNET_PQ_result_spec_uint64 ("refund_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rsc->status = GNUNET_SYSERR;
      return;
    }
    ret = rsc->cb (rsc->cb_cls,
		   rowid,
		   &denom_pub,
		   &refund.coin.coin_pub,
		   &refund.merchant_pub,
		   &refund.merchant_sig,
		   &refund.h_contract_terms,
		   refund.rtransaction_id,
		   &refund.refund_amount);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select refunds above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_refunds_above_serial_id (void *cls,
                                         struct TALER_EXCHANGEDB_Session *session,
                                         uint64_t serial_id,
                                         TALER_EXCHANGEDB_RefundCallback cb,
                                         void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct RefundsSerialContext rsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "audit_get_refunds_incr",
					     params,
					     &refunds_serial_helper_cb,
					     &rsc);
  if (GNUNET_OK != rsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #reserves_in_serial_helper_cb().
 */
struct ReservesInSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_ReserveInCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ReservesInSerialContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
reserves_in_serial_helper_cb (void *cls,
			      PGresult *result,
			      unsigned int num_results)
{
  struct ReservesInSerialContext *risc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_Amount credit;
    char *sender_account_details;
    struct GNUNET_TIME_Absolute execution_date;
    uint64_t rowid;
    void *wire_reference;
    size_t wire_reference_size;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_variable_size ("wire_reference",
                                           &wire_reference,
                                           &wire_reference_size),
      TALER_PQ_result_spec_amount ("credit",
                                   &credit),
      TALER_PQ_result_spec_absolute_time("execution_date",
                                          &execution_date),
      GNUNET_PQ_result_spec_string ("sender_account_details",
                                    &sender_account_details),
      GNUNET_PQ_result_spec_uint64 ("reserve_in_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      risc->status = GNUNET_SYSERR;
      return;
    }
    ret = risc->cb (risc->cb_cls,
		    rowid,
		    &reserve_pub,
		    &credit,
		    sender_account_details,
		    wire_reference,
		    wire_reference_size,
		    execution_date);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select inbound wire transfers into reserves_in above @a serial_id
 * in monotonically increasing order.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_reserves_in_above_serial_id (void *cls,
                                             struct TALER_EXCHANGEDB_Session *session,
                                             uint64_t serial_id,
                                             TALER_EXCHANGEDB_ReserveInCallback cb,
                                             void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct ReservesInSerialContext risc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "audit_reserves_in_get_transactions_incr",
					     params,
					     &reserves_in_serial_helper_cb,
					     &risc);
  if (GNUNET_OK != risc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Select inbound wire transfers into reserves_in above @a serial_id
 * in monotonically increasing order by account.
 *
 * @param cls closure
 * @param session database connection
 * @param account_name name of the account to select by
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_reserves_in_above_serial_id_by_account (void *cls,
                                                        struct TALER_EXCHANGEDB_Session *session,
                                                        const char *account_name,
                                                        uint64_t serial_id,
                                                        TALER_EXCHANGEDB_ReserveInCallback cb,
                                                        void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_end
  };
  struct ReservesInSerialContext risc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "audit_reserves_in_get_transactions_incr_by_account",
					     params,
					     &reserves_in_serial_helper_cb,
					     &risc);
  if (GNUNET_OK != risc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #reserves_out_serial_helper_cb().
 */
struct ReservesOutSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_WithdrawCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ReservesOutSerialContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
reserves_out_serial_helper_cb (void *cls,
			       PGresult *result,
			       unsigned int num_results)
{
  struct ReservesOutSerialContext *rosc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    struct GNUNET_HashCode h_blind_ev;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_DenominationSignature denom_sig;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_ReserveSignatureP reserve_sig;
    struct GNUNET_TIME_Absolute execution_date;
    struct TALER_Amount amount_with_fee;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                           &denom_sig.rsa_signature),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                            &reserve_sig),
      TALER_PQ_result_spec_absolute_time ("execution_date",
                                           &execution_date),
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_uint64 ("reserve_out_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rosc->status = GNUNET_SYSERR;
      return;
    }
    ret = rosc->cb (rosc->cb_cls,
		    rowid,
		    &h_blind_ev,
		    &denom_pub,
		    &denom_sig,
		    &reserve_pub,
		    &reserve_sig,
		    execution_date,
		    &amount_with_fee);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select withdraw operations from reserves_out above @a serial_id
 * in monotonically increasing order.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_reserves_out_above_serial_id (void *cls,
                                              struct TALER_EXCHANGEDB_Session *session,
                                              uint64_t serial_id,
                                              TALER_EXCHANGEDB_WithdrawCallback cb,
                                              void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct ReservesOutSerialContext rosc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "audit_get_reserves_out_incr",
					     params,
					     &reserves_out_serial_helper_cb,
					     &rosc);
  if (GNUNET_OK != rosc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #wire_out_serial_helper_cb().
 */
struct WireOutSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_WireTransferOutCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct WireOutSerialContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
wire_out_serial_helper_cb (void *cls,
			   PGresult *result,
			   unsigned int num_results)
{
  struct WireOutSerialContext *wosc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    uint64_t rowid;
    struct GNUNET_TIME_Absolute date;
    struct TALER_WireTransferIdentifierRawP wtid;
    json_t *wire;
    struct TALER_Amount amount;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("wireout_uuid",
                                    &rowid),
      TALER_PQ_result_spec_absolute_time ("execution_date",
                                           &date),
      GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                            &wtid),
      TALER_PQ_result_spec_json ("wire_target",
                                 &wire),
      TALER_PQ_result_spec_amount ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      wosc->status = GNUNET_SYSERR;
      return;
    }
    ret = wosc->cb (wosc->cb_cls,
		    rowid,
		    date,
		    &wtid,
		    wire,
		    &amount);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Function called to select all wire transfers the exchange
 * executed.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_wire_out_above_serial_id (void *cls,
                                          struct TALER_EXCHANGEDB_Session *session,
                                          uint64_t serial_id,
                                          TALER_EXCHANGEDB_WireTransferOutCallback cb,
                                          void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct WireOutSerialContext wosc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "audit_get_wire_incr",
					     params,
					     &wire_out_serial_helper_cb,
					     &wosc);
  if (GNUNET_OK != wosc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Function called to select all wire transfers the exchange
 * executed by account.
 *
 * @param cls closure
 * @param session database connection
 * @param account_name account to select
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_wire_out_above_serial_id_by_account (void *cls,
                                                     struct TALER_EXCHANGEDB_Session *session,
                                                     const char *account_name,
                                                     uint64_t serial_id,
                                                     TALER_EXCHANGEDB_WireTransferOutCallback cb,
                                                     void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_end
  };
  struct WireOutSerialContext wosc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "audit_get_wire_incr_by_account",
					     params,
					     &wire_out_serial_helper_cb,
					     &wosc);
  if (GNUNET_OK != wosc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #payback_serial_helper_cb().
 */
struct PaybackSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PaybackCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct PaybackSerialContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
payback_serial_helper_cb (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct PaybackSerialContext *psc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    uint64_t rowid;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_CoinPublicInfo coin;
    struct TALER_CoinSpendSignatureP coin_sig;
    struct TALER_DenominationBlindingKeyP coin_blind;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_Amount amount;
    struct GNUNET_HashCode h_blind_ev;
    struct GNUNET_TIME_Absolute timestamp;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("payback_uuid",
                                    &rowid),
      TALER_PQ_result_spec_absolute_time ("timestamp",
                                           &timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &coin_sig),
      GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                            &coin_blind),
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &coin.denom_pub_hash),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                           &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                           &coin.denom_sig.rsa_signature),
      TALER_PQ_result_spec_amount ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      psc->status = GNUNET_SYSERR;
      return;
    }
    ret = psc->cb (psc->cb_cls,
                   rowid,
                   timestamp,
                   &amount,
                   &reserve_pub,
                   &coin,
                   &denom_pub,
                   &coin_sig,
                   &coin_blind);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Function called to select payback requests the exchange
 * received, ordered by serial ID (monotonically increasing).
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_payback_above_serial_id (void *cls,
                                         struct TALER_EXCHANGEDB_Session *session,
                                         uint64_t serial_id,
                                         TALER_EXCHANGEDB_PaybackCallback cb,
                                         void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct PaybackSerialContext psc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "payback_get_incr",
					     params,
					     &payback_serial_helper_cb,
					     &psc);
  if (GNUNET_OK != psc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #payback_refresh_serial_helper_cb().
 */
struct PaybackRefreshSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PaybackRefreshCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct PaybackRefreshSerialContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
payback_refresh_serial_helper_cb (void *cls,
                                  PGresult *result,
                                  unsigned int num_results)
{
  struct PaybackRefreshSerialContext *psc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    uint64_t rowid;
    struct TALER_CoinSpendPublicKeyP old_coin_pub;
    struct TALER_CoinPublicInfo coin;
    struct TALER_CoinSpendSignatureP coin_sig;
    struct TALER_DenominationBlindingKeyP coin_blind;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_Amount amount;
    struct GNUNET_HashCode h_blind_ev;
    struct GNUNET_TIME_Absolute timestamp;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("payback_uuid",
                                    &rowid),
      TALER_PQ_result_spec_absolute_time ("timestamp",
                                           &timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                            &old_coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &coin_sig),
      GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                            &coin_blind),
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &coin.denom_pub_hash),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                           &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                           &coin.denom_sig.rsa_signature),
      TALER_PQ_result_spec_amount ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      psc->status = GNUNET_SYSERR;
      return;
    }
    ret = psc->cb (psc->cb_cls,
                   rowid,
                   timestamp,
                   &amount,
                   &old_coin_pub,
                   &coin,
                   &denom_pub,
                   &coin_sig,
                   &coin_blind);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Function called to select payback requests the exchange received for
 * refreshed coins, ordered by serial ID (monotonically increasing).
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_payback_refresh_above_serial_id (void *cls,
                                                 struct TALER_EXCHANGEDB_Session *session,
                                                 uint64_t serial_id,
                                                 TALER_EXCHANGEDB_PaybackRefreshCallback cb,
                                                 void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct PaybackRefreshSerialContext psc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "payback_refresh_get_incr",
                                             params,
                                             &payback_refresh_serial_helper_cb,
                                             &psc);
  if (GNUNET_OK != psc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #reserve_closed_serial_helper_cb().
 */
struct ReserveClosedSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_ReserveClosedCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ReserveClosedSerialContext`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
reserve_closed_serial_helper_cb (void *cls,
				 PGresult *result,
				 unsigned int num_results)
{
  struct ReserveClosedSerialContext *rcsc = cls;

  for (unsigned int i=0;i<num_results;i++)
  {
    uint64_t rowid;
    struct TALER_ReservePublicKeyP reserve_pub;
    char *receiver_account;
    struct TALER_WireTransferIdentifierRawP wtid;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount closing_fee;
    struct GNUNET_TIME_Absolute execution_date;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("close_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      TALER_PQ_result_spec_absolute_time ("execution_date",
                                           &execution_date),
      GNUNET_PQ_result_spec_auto_from_type ("wtid",
					    &wtid),
      GNUNET_PQ_result_spec_string ("receiver_account",
                                    &receiver_account),
      TALER_PQ_result_spec_amount ("amount",
                                   &amount_with_fee),
      TALER_PQ_result_spec_amount ("closing_fee",
                                   &closing_fee),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rcsc->status = GNUNET_SYSERR;
      return;
    }
    ret = rcsc->cb (rcsc->cb_cls,
		    rowid,
		    execution_date,
		    &amount_with_fee,
		    &closing_fee,
		    &reserve_pub,
		    receiver_account,
		    &wtid);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Function called to select reserve close operations the aggregator
 * triggered, ordered by serial ID (monotonically increasing).
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_reserve_closed_above_serial_id (void *cls,
                                                struct TALER_EXCHANGEDB_Session *session,
                                                uint64_t serial_id,
                                                TALER_EXCHANGEDB_ReserveClosedCallback cb,
                                                void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct ReserveClosedSerialContext rcsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "reserves_close_get_incr",
					     params,
					     &reserve_closed_serial_helper_cb,
					     &rcsc);
  if (GNUNET_OK != rcsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Function called to add a request for an emergency payback for a
 * coin.  The funds are to be added back to the reserve.  The function
 * should return the @a deadline by which the exchange will trigger a
 * wire transfer back to the customer's account for the reserve.
 *
 * @param cls closure
 * @param session database connection
 * @param reserve_pub public key of the reserve that is being refunded
 * @param coin information about the coin
 * @param coin_sig signature of the coin of type #TALER_SIGNATURE_WALLET_COIN_PAYBACK
 * @param coin_blind blinding key of the coin
 * @param amount total amount to be paid back
 * @param h_blind_ev hash of the blinded coin's envelope (must match reserves_out entry)
 * @param timestamp current time (rounded)
 * @return transaction result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_payback_request (void *cls,
                                 struct TALER_EXCHANGEDB_Session *session,
                                 const struct TALER_ReservePublicKeyP *reserve_pub,
                                 const struct TALER_CoinPublicInfo *coin,
                                 const struct TALER_CoinSpendSignatureP *coin_sig,
                                 const struct TALER_DenominationBlindingKeyP *coin_blind,
                                 const struct TALER_Amount *amount,
                                 const struct GNUNET_HashCode *h_blind_ev,
                                 struct GNUNET_TIME_Absolute timestamp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute expiry;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin->coin_pub),
    GNUNET_PQ_query_param_auto_from_type (coin_sig),
    GNUNET_PQ_query_param_auto_from_type (coin_blind),
    TALER_PQ_query_param_amount (amount),
    TALER_PQ_query_param_absolute_time (&timestamp),
    GNUNET_PQ_query_param_auto_from_type (h_blind_ev),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  /* now store actual payback information */
  qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                           "payback_insert",
                                           params);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  /* Update reserve balance */
  reserve.pub = *reserve_pub;
  qs = postgres_reserve_get (cls,
                             session,
                             &reserve);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_add (&reserve.balance,
                        &reserve.balance,
                        amount))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  expiry = GNUNET_TIME_absolute_add (timestamp,
                                     pg->legal_reserve_expiration_time);
  reserve.gc = GNUNET_TIME_absolute_max (expiry,
                                         reserve.gc);
  (void) GNUNET_TIME_round_abs (&reserve.gc);
  expiry = GNUNET_TIME_absolute_add (timestamp,
                                     pg->idle_reserve_expiration_time);
  reserve.expiry = GNUNET_TIME_absolute_max (expiry,
                                             reserve.expiry);
  (void) GNUNET_TIME_round_abs (&reserve.expiry);
  qs = reserves_update (cls,
                        session,
                        &reserve);
  if (0 >= qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  return qs;
}


/**
 * Function called to add a request for an emergency payback for a
 * refreshed coin.  The funds are to be added back to the original coin
 * (which is implied via @a h_blind_ev, see the prepared statement
 * "payback_by_old_coin" used in #postgres_get_coin_transactions()).
 *
 * @param cls closure
 * @param session database connection
 * @param coin public information about the refreshed coin
 * @param coin_sig signature of the coin of type #TALER_SIGNATURE_WALLET_COIN_PAYBACK
 * @param coin_blind blinding key of the coin
 * @param h_blind_ev blinded envelope, as calculated by the exchange
 * @param amount total amount to be paid back
 * @param h_blind_ev hash of the blinded coin's envelope (must match reserves_out entry)
 * @param timestamp a timestamp to store
 * @return transaction result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_payback_refresh_request (void *cls,
                                         struct TALER_EXCHANGEDB_Session *session,
                                         const struct TALER_CoinPublicInfo *coin,
                                         const struct TALER_CoinSpendSignatureP *coin_sig,
                                         const struct TALER_DenominationBlindingKeyP *coin_blind,
                                         const struct TALER_Amount *amount,
                                         const struct GNUNET_HashCode *h_blind_ev,
                                         struct GNUNET_TIME_Absolute timestamp)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin->coin_pub),
    GNUNET_PQ_query_param_auto_from_type (coin_sig),
    GNUNET_PQ_query_param_auto_from_type (coin_blind),
    TALER_PQ_query_param_amount (amount),
    TALER_PQ_query_param_absolute_time (&timestamp),
    GNUNET_PQ_query_param_auto_from_type (h_blind_ev),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  /* now store actual payback information */
  qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                           "payback_refresh_insert",
                                           params);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  return qs;
}


/**
 * Obtain information about which reserve a coin was generated
 * from given the hash of the blinded coin.
 *
 * @param cls closure
 * @param session a session
 * @param h_blind_ev hash of the blinded coin
 * @param[out] reserve_pub set to information about the reserve (on success only)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_by_h_blind (void *cls,
                                 struct TALER_EXCHANGEDB_Session *session,
                                 const struct GNUNET_HashCode *h_blind_ev,
                                 struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_blind_ev),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
					  reserve_pub),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "reserve_by_h_blind",
                                                   params,
                                                   rs);
}


/**
 * Obtain information about which old coin a coin was refreshed
 * given the hash of the blinded (fresh) coin.
 *
 * @param cls closure
 * @param session a session
 * @param h_blind_ev hash of the blinded coin
 * @param[out] reserve_pub set to information about the reserve (on success only)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_old_coin_by_h_blind (void *cls,
                                  struct TALER_EXCHANGEDB_Session *session,
                                  const struct GNUNET_HashCode *h_blind_ev,
                                  struct TALER_CoinSpendPublicKeyP *old_coin_pub)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_blind_ev),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                          old_coin_pub),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "old_coin_by_h_blind",
                                                   params,
                                                   rs);
}


/**
 * Store information that a denomination key was revoked
 * in the database.
 *
 * @param cls closure
 * @param session a session
 * @param denom_pub_hash hash of the revoked denomination key
 * @param master_sig signature affirming the revocation
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_denomination_revocation (void *cls,
                                         struct TALER_EXCHANGEDB_Session *session,
                                         const struct GNUNET_HashCode *denom_pub_hash,
                                         const struct TALER_MasterSignatureP *master_sig)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "denomination_revocation_insert",
					     params);
}


/**
 * Obtain information about a denomination key's revocation from
 * the database.
 *
 * @param cls closure
 * @param session a session
 * @param denom_pub_hash hash of the revoked denomination key
 * @param[out] master_sig signature affirming the revocation
 * @param[out] rowid row where the information is stored
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_denomination_revocation (void *cls,
                                      struct TALER_EXCHANGEDB_Session *session,
                                      const struct GNUNET_HashCode *denom_pub_hash,
                                      struct TALER_MasterSignatureP *master_sig,
				      uint64_t *rowid)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("master_sig", master_sig),
    GNUNET_PQ_result_spec_uint64 ("denom_revocations_serial_id", rowid),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "denomination_revocation_get",
						   params,
						   rs);
}


/**
 * Closure for #missing_wire_cb().
 */
struct MissingWireContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_WireMissingCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Set to #GNUNET_SYSERR on error.
   */
  int status;
};


/**
 * Invoke the callback for each result.
 *
 * @param cls a `struct MissingWireContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
missing_wire_cb (void *cls,
		 PGresult *result,
		 unsigned int num_results)
{
  struct MissingWireContext *mwc = cls;

  while (0 < num_results)
  {
    uint64_t rowid;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_Amount amount;
    json_t *wire;
    struct GNUNET_TIME_Absolute deadline;
    uint8_t tiny;
    uint8_t done;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
				    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
					    &coin_pub),
      TALER_PQ_result_spec_amount ("amount_with_fee",
				   &amount),
      TALER_PQ_result_spec_json ("wire",
                                 &wire),
      TALER_PQ_result_spec_absolute_time ("wire_deadline",
					   &deadline),
      GNUNET_PQ_result_spec_auto_from_type ("tiny",
                                            &tiny),
      GNUNET_PQ_result_spec_auto_from_type ("done",
                                            &done),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
	GNUNET_PQ_extract_result (result,
				  rs,
				  --num_results))
    {
      GNUNET_break (0);
      mwc->status = GNUNET_SYSERR;
      return;
    }
    mwc->cb (mwc->cb_cls,
	     rowid,
	     &coin_pub,
	     &amount,
	     wire,
	     deadline,
	     tiny,
	     done);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Select all of those deposits in the database for which we do
 * not have a wire transfer (or a refund) and which should have
 * been deposited between @a start_date and @a end_date.
 *
 * @param cls closure
 * @param session a session
 * @param start_date lower bound on the requested wire execution date
 * @param end_date upper bound on the requested wire execution date
 * @param cb function to call on all such deposits
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_deposits_missing_wire (void *cls,
				       struct TALER_EXCHANGEDB_Session *session,
				       struct GNUNET_TIME_Absolute start_date,
				       struct GNUNET_TIME_Absolute end_date,
				       TALER_EXCHANGEDB_WireMissingCallback cb,
				       void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&start_date),
    TALER_PQ_query_param_absolute_time (&end_date),
    GNUNET_PQ_query_param_end
  };
  struct MissingWireContext mwc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "deposits_get_overdue",
					     params,
					     &missing_wire_cb,
					     &mwc);
  if (GNUNET_OK != mwc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}

/**
 * Delete wire transfer records related to a particular merchant.
 * This method would be called by the logic once that merchant
 * gets successfully KYC checked.
 *
 * @param cls closure
 * @param session DB session
 * @param merchant_serial_id serial id of the merchant whose
 *        KYC records have to be deleted.
 * @return DB transaction status.
 */
static enum GNUNET_DB_QueryStatus
postgres_clean_kyc_events (void *cls,
                           struct TALER_EXCHANGEDB_Session *session,
                           uint64_t merchant_serial_id)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&merchant_serial_id),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "clean_kyc_events",
                                             params);

}


/**
 * Mark a merchant as NOT KYC-checked.
 *
 * @param cls closure
 * @param session DB session
 * @param payto_url payto:// URL indentifying the merchant
 *        to unmark.  Note, different banks may have different
 *        policies to check their customers.
 * @return database transaction status.
 */
static enum GNUNET_DB_QueryStatus
postgres_unmark_kyc_merchant
  (void *cls,
   struct TALER_EXCHANGEDB_Session *session,
   const char *payto_url)
{

  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_url),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select
    (session->conn,
     "unmark_kyc_merchant",
     params);
}

/**
 * Record timestamp where a particular merchant performed
 * a wire transfer.
 *
 * @param cls closure.
 * @param session db session.
 * @param merchant_serial_id serial id of the merchant who
 *        performed the wire transfer.
 * @param amount amount of the wire transfer being monitored.
 * @return database transaction status.
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_kyc_event
  (void *cls,
   struct TALER_EXCHANGEDB_Session *session,
   uint64_t merchant_serial_id,
   struct TALER_Amount *amount)
{
  struct GNUNET_TIME_Absolute now;

  now = GNUNET_TIME_absolute_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&merchant_serial_id),
    TALER_PQ_query_param_amount (amount),
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_kyc_event",
                                             params);
}

/**
 * Mark a merchant as KYC-checked.
 *
 * @param payto_url payto:// URL indentifying the merchant
 *        to mark.  Note, different banks may have different
 *        policies to check their customers.
 * @return database transaction status.
 */
static enum GNUNET_DB_QueryStatus
postgres_mark_kyc_merchant
  (void *cls,
   struct TALER_EXCHANGEDB_Session *session,
   const char *payto_url)
{

  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_url),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "mark_kyc_merchant",
                                             params);
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
sum_kyc_events (void *cls,
                PGresult *result,
                unsigned int num_results)
{
  struct TALER_Amount *tot = cls;
  struct TALER_Amount tmp;

  int ntuples = PQntuples (result);

  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount ("amount", &tmp),
    GNUNET_PQ_result_spec_end
  };

  for (unsigned int i = 0; i < ntuples; i++)
  {
    GNUNET_assert
      (GNUNET_OK == GNUNET_PQ_extract_result (result,
                                              rs,
                                              i));

    if ((0 == tot->value) && (0 == tot->fraction))
      *tot = tmp;
    else
      GNUNET_assert
        (GNUNET_SYSERR != TALER_amount_add (tot,
                                            tot,
                                            &tmp));

  }

}


/**
 * Calculate sum of money flow related to a particular merchant,
 * used for KYC monitoring.
 *
 * @param cls closure
 * @param session DB session
 * @param merchant_serial_id serial id identifying the merchant
 *        into the KYC monitoring system.
 * @param amount[out] will store the amount of money received
 *        by this merchant.
 */
static enum GNUNET_DB_QueryStatus
postgres_get_kyc_events (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         uint64_t merchant_serial_id,
                         struct TALER_Amount *amount)
{
  enum GNUNET_DB_QueryStatus qs;

  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&merchant_serial_id),
    GNUNET_PQ_query_param_end
  };

  /* make sure sum object starts virgin.  */
  memset (amount,
          0,
          sizeof (struct TALER_Amount));

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "get_kyc_events",
                                             params,
                                             sum_kyc_events,
                                             amount);
  return qs;
}

/**
 * Retrieve KYC-check status related to a particular merchant.
 *
 * @param payto_url URL identifying a merchant bank account,
 *        whose KYC is going to be retrieved.
 * @param[out] status store the result.
 * @return transaction status.
 */
static enum GNUNET_DB_QueryStatus
postgres_get_kyc_status (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const char *payto_url,
                         TALER_EXCHANGEDB_KycStatusCallback ksc,
                         void *ksc_cls)
{
  uint8_t status;
  uint64_t merchant_serial_id;
  enum GNUNET_DB_QueryStatus qs;
  char *general_id;

  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_url),
    GNUNET_PQ_query_param_end
  };


  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_string ("general_id",
                                  &general_id),
    GNUNET_PQ_result_spec_auto_from_type ("kyc_checked",
                                          &status),
    GNUNET_PQ_result_spec_uint64 ("merchant_serial_id",
                                  &merchant_serial_id),
    GNUNET_PQ_result_spec_end
  };

  qs = GNUNET_PQ_eval_prepared_singleton_select
    (session->conn,
     "get_kyc_status",
     params,
     rs);

  if (0 >= qs)
    return qs;

  ksc (ksc_cls,
       payto_url,
       general_id,
       status,
       merchant_serial_id);

  return qs;
}



/**
 * Insert a merchant into the KYC monitor table.
 *
 * @param payto_url payto:// URL indentifying the merchant
 *        bank account.
 * @return database transaction status.
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_kyc_merchant (void *cls,
                              struct TALER_EXCHANGEDB_Session *session,
                              const char *general_id,
                              const char *payto_url)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_url),
    GNUNET_PQ_query_param_string (general_id),
    GNUNET_PQ_query_param_end
  };
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_kyc_merchant",
                                             params);
}


/**
 * Initialize Postgres database subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct
 *         TALER_EXCHANGEDB_Plugin`
 */
void *
libtaler_plugin_exchangedb_postgres_init (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct PostgresClosure *pg;
  struct TALER_EXCHANGEDB_Plugin *plugin;
  const char *ec;

  pg = GNUNET_new (struct PostgresClosure);

  if (0 != pthread_key_create (&pg->db_conn_threadlocal,
                               &db_conn_destroy))
  {
    TALER_LOG_ERROR ("Cannnot create pthread key.\n");
    GNUNET_free (pg);
    return NULL;
  }
  ec = getenv ("TALER_EXCHANGEDB_POSTGRES_CONFIG");
  if (NULL != ec)
  {
    pg->connection_cfg_str = GNUNET_strdup (ec);
  }
  else
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchangedb-postgres",
                                               "CONFIG",
                                               &pg->connection_cfg_str))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchangedb-postgres",
                                 "CONFIG");
      GNUNET_free (pg);
      return NULL;
    }
  }

  if ( (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_time (cfg,
                                             "exchangedb",
                                             "IDLE_RESERVE_EXPIRATION_TIME",
                                             &pg->idle_reserve_expiration_time)) ||
       (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_time (cfg,
                                             "exchangedb",
                                             "LEGAL_RESERVE_EXPIRATION_TIME",
                                             &pg->legal_reserve_expiration_time)) )
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "LEGAL/IDLE_RESERVE_EXPIRATION_TIME");
    GNUNET_free (pg);
    return NULL;
  }
  plugin = GNUNET_new (struct TALER_EXCHANGEDB_Plugin);
  plugin->cls = pg;
  plugin->get_session = &postgres_get_session;
  plugin->drop_tables = &postgres_drop_tables;
  plugin->create_tables = &postgres_create_tables;
  plugin->start = &postgres_start;
  plugin->commit = &postgres_commit;
  plugin->preflight = &postgres_preflight;
  plugin->rollback = &postgres_rollback;
  plugin->insert_denomination_info = &postgres_insert_denomination_info;
  plugin->get_denomination_info = &postgres_get_denomination_info;
  plugin->iterate_denomination_info = &postgres_iterate_denomination_info;
  plugin->reserve_get = &postgres_reserve_get;
  plugin->reserves_in_insert = &postgres_reserves_in_insert;
  plugin->get_latest_reserve_in_reference = &postgres_get_latest_reserve_in_reference;
  plugin->get_withdraw_info = &postgres_get_withdraw_info;
  plugin->insert_withdraw_info = &postgres_insert_withdraw_info;
  plugin->get_reserve_history = &postgres_get_reserve_history;
  plugin->free_reserve_history = &common_free_reserve_history;
  plugin->count_known_coins = &postgres_count_known_coins;
  plugin->ensure_coin_known = &postgres_ensure_coin_known;
  plugin->get_known_coin = &postgres_get_known_coin;
  plugin->have_deposit = &postgres_have_deposit;
  plugin->mark_deposit_tiny = &postgres_mark_deposit_tiny;
  plugin->test_deposit_done = &postgres_test_deposit_done;
  plugin->mark_deposit_done = &postgres_mark_deposit_done;
  plugin->get_ready_deposit = &postgres_get_ready_deposit;
  plugin->iterate_matching_deposits = &postgres_iterate_matching_deposits;
  plugin->insert_deposit = &postgres_insert_deposit;
  plugin->insert_refund = &postgres_insert_refund;
  plugin->select_refunds_by_coin = &postgres_select_refunds_by_coin;
  plugin->insert_melt = &postgres_insert_melt;
  plugin->get_melt = &postgres_get_melt;
  plugin->get_melt_index = &postgres_get_melt_index;
  plugin->insert_refresh_reveal = &postgres_insert_refresh_reveal;
  plugin->get_refresh_reveal = &postgres_get_refresh_reveal;
  plugin->get_link_data = &postgres_get_link_data;
  plugin->get_coin_transactions = &postgres_get_coin_transactions;
  plugin->free_coin_transaction_list = &common_free_coin_transaction_list;
  plugin->lookup_wire_transfer = &postgres_lookup_wire_transfer;
  plugin->wire_lookup_deposit_wtid = &postgres_wire_lookup_deposit_wtid;
  plugin->insert_aggregation_tracking = &postgres_insert_aggregation_tracking;
  plugin->insert_wire_fee = &postgres_insert_wire_fee;
  plugin->get_wire_fee = &postgres_get_wire_fee;
  plugin->get_expired_reserves = &postgres_get_expired_reserves;
  plugin->insert_reserve_closed = &postgres_insert_reserve_closed;
  plugin->wire_prepare_data_insert = &postgres_wire_prepare_data_insert;
  plugin->wire_prepare_data_mark_finished = &postgres_wire_prepare_data_mark_finished;
  plugin->wire_prepare_data_get = &postgres_wire_prepare_data_get;
  plugin->start_deferred_wire_out = &postgres_start_deferred_wire_out;
  plugin->store_wire_transfer_out = &postgres_store_wire_transfer_out;
  plugin->gc = &postgres_gc;
  plugin->select_deposits_above_serial_id
    = &postgres_select_deposits_above_serial_id;
  plugin->select_refreshs_above_serial_id
    = &postgres_select_refreshs_above_serial_id;
  plugin->select_refunds_above_serial_id
    = &postgres_select_refunds_above_serial_id;
  plugin->select_reserves_in_above_serial_id
    = &postgres_select_reserves_in_above_serial_id;
  plugin->select_reserves_in_above_serial_id_by_account
    = &postgres_select_reserves_in_above_serial_id_by_account;
  plugin->select_reserves_out_above_serial_id
    = &postgres_select_reserves_out_above_serial_id;
  plugin->select_wire_out_above_serial_id
    = &postgres_select_wire_out_above_serial_id;
  plugin->select_wire_out_above_serial_id_by_account
    = &postgres_select_wire_out_above_serial_id_by_account;
  plugin->select_payback_above_serial_id
    = &postgres_select_payback_above_serial_id;
  plugin->select_payback_refresh_above_serial_id
    = &postgres_select_payback_refresh_above_serial_id;
  plugin->select_reserve_closed_above_serial_id
    = &postgres_select_reserve_closed_above_serial_id;
  plugin->insert_payback_request
    = &postgres_insert_payback_request;
  plugin->insert_payback_refresh_request
    = &postgres_insert_payback_refresh_request;
  plugin->get_reserve_by_h_blind
    = &postgres_get_reserve_by_h_blind;
  plugin->get_old_coin_by_h_blind
    = &postgres_get_old_coin_by_h_blind;
  plugin->insert_denomination_revocation
    = &postgres_insert_denomination_revocation;
  plugin->get_denomination_revocation
    = &postgres_get_denomination_revocation;
  plugin->select_deposits_missing_wire
    = &postgres_select_deposits_missing_wire;

  plugin->insert_kyc_merchant = postgres_insert_kyc_merchant;
  plugin->mark_kyc_merchant = postgres_mark_kyc_merchant;
  plugin->unmark_kyc_merchant = postgres_unmark_kyc_merchant;
  plugin->get_kyc_status = postgres_get_kyc_status;
  plugin->insert_kyc_event = postgres_insert_kyc_event;
  plugin->get_kyc_events = postgres_get_kyc_events;
  plugin->clean_kyc_events = postgres_clean_kyc_events;

  return plugin;
}


/**
 * Shutdown Postgres database subsystem.
 *
 * @param cls a `struct TALER_EXCHANGEDB_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_exchangedb_postgres_done (void *cls)
{
  struct TALER_EXCHANGEDB_Plugin *plugin = cls;
  struct PostgresClosure *pg = plugin->cls;

  GNUNET_free (pg->connection_cfg_str);
  GNUNET_free (pg);
  GNUNET_free (plugin);
  return NULL;
}

/* end of plugin_exchangedb_postgres.c */
