/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file plugin_auditordb_postgres.c
 * @brief Low-level (statement-level) Postgres database access for the auditor
 * @author Christian Grothoff
 * @author Gabor X Toth
 */
#include "platform.h"
#include "taler_pq_lib.h"
#include "taler_auditordb_plugin.h"
#include <pthread.h>
#include <libpq-fe.h>


#define LOG(kind,...) GNUNET_log_from (kind, "taler-auditordb-postgres", \
                                       __VA_ARGS__)


/**
 * Wrapper macro to add the currency from the plugin's state
 * when fetching amounts from the database.
 *
 * @param field name of the database field to fetch amount from
 * @param[out] amountp pointer to amount to set
 */
#define TALER_PQ_RESULT_SPEC_AMOUNT(field,amountp) \
  TALER_PQ_result_spec_amount (                    \
    field,pg->currency,amountp)

/**
 * Wrapper macro to add the currency from the plugin's state
 * when fetching amounts from the database.  NBO variant.
 *
 * @param field name of the database field to fetch amount from
 * @param[out] amountp pointer to amount to set
 */
#define TALER_PQ_RESULT_SPEC_AMOUNT_NBO(field, \
                                        amountp) TALER_PQ_result_spec_amount_nbo ( \
    field,pg->currency,amountp)


/**
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct PostgresClosure
{

  /**
   * Postgres connection handle.
   */
  struct GNUNET_PQ_Context *conn;

  /**
   * Name of the ongoing transaction, used to debug cases where
   * a transaction is not properly terminated via COMMIT or
   * ROLLBACK.
   */
  const char *transaction_name;

  /**
   * Our configuration.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Which currency should we assume all amounts to be in?
   */
  char *currency;
};


/**
 * Drop all auditor tables OR deletes recoverable auditor state.
 * This should only be used by testcases or when restarting the
 * auditor from scratch.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param drop_exchangelist drop all tables, including schema versioning
 *        and the exchange and deposit_confirmations table; NOT to be
 *        used when restarting the auditor
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static enum GNUNET_GenericReturnValue
postgres_drop_tables (void *cls,
                      bool drop_exchangelist)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret;

  conn = GNUNET_PQ_connect_with_cfg (pc->cfg,
                                     "auditordb-postgres",
                                     NULL,
                                     NULL,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_PQ_exec_sql (conn,
                            (drop_exchangelist) ? "drop" : "restart");
  GNUNET_PQ_disconnect (conn);
  return ret;
}


/**
 * Create the necessary tables if they are not present
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static enum GNUNET_GenericReturnValue
postgres_create_tables (void *cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_Context *conn;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO auditor;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pc->cfg,
                                     "auditordb-postgres",
                                     "auditor-",
                                     es,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  GNUNET_PQ_disconnect (conn);
  return GNUNET_OK;
}


/**
 * Connect to the db if the connection does not exist yet.
 *
 * @param[in,out] pg the plugin-specific state
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
setup_connection (struct PostgresClosure *pg)
{
  struct GNUNET_PQ_PreparedStatement ps[] = {
    /* used in #postgres_commit */
    GNUNET_PQ_make_prepare ("do_commit",
                            "COMMIT"),
    /* used in #postgres_insert_exchange */
    GNUNET_PQ_make_prepare ("auditor_insert_exchange",
                            "INSERT INTO auditor_exchanges "
                            "(master_pub"
                            ",exchange_url"
                            ") VALUES ($1,$2);"),
    /* used in #postgres_delete_exchange */
    GNUNET_PQ_make_prepare ("auditor_delete_exchange",
                            "DELETE"
                            " FROM auditor_exchanges"
                            " WHERE master_pub=$1;"),
    /* used in #postgres_list_exchanges */
    GNUNET_PQ_make_prepare ("auditor_list_exchanges",
                            "SELECT"
                            " master_pub"
                            ",exchange_url"
                            " FROM auditor_exchanges"),
    /* used in #postgres_insert_exchange_signkey */
    GNUNET_PQ_make_prepare ("auditor_insert_exchange_signkey",
                            "INSERT INTO auditor_exchange_signkeys "
                            "(master_pub"
                            ",ep_start"
                            ",ep_expire"
                            ",ep_end"
                            ",exchange_pub"
                            ",master_sig"
                            ") VALUES ($1,$2,$3,$4,$5,$6);"),
    /* Used in #postgres_insert_deposit_confirmation() */
    GNUNET_PQ_make_prepare ("auditor_deposit_confirmation_insert",
                            "INSERT INTO deposit_confirmations "
                            "(master_pub"
                            ",h_contract_terms"
                            ",h_extensions"
                            ",h_wire"
                            ",exchange_timestamp"
                            ",wire_deadline"
                            ",refund_deadline"
                            ",amount_without_fee_val"
                            ",amount_without_fee_frac"
                            ",coin_pub"
                            ",merchant_pub"
                            ",exchange_sig"
                            ",exchange_pub"
                            ",master_sig" /* master_sig could be normalized... */
                            ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14);"),
    /* Used in #postgres_get_deposit_confirmations() */
    GNUNET_PQ_make_prepare ("auditor_deposit_confirmation_select",
                            "SELECT"
                            " serial_id"
                            ",h_contract_terms"
                            ",h_extensions"
                            ",h_wire"
                            ",exchange_timestamp"
                            ",wire_deadline"
                            ",refund_deadline"
                            ",amount_without_fee_val"
                            ",amount_without_fee_frac"
                            ",coin_pub"
                            ",merchant_pub"
                            ",exchange_sig"
                            ",exchange_pub"
                            ",master_sig" /* master_sig could be normalized... */
                            " FROM deposit_confirmations"
                            " WHERE master_pub=$1"
                            " AND serial_id>$2"),
    /* Used in #postgres_update_auditor_progress_reserve() */
    GNUNET_PQ_make_prepare ("auditor_progress_update_reserve",
                            "UPDATE auditor_progress_reserve SET "
                            " last_reserve_in_serial_id=$1"
                            ",last_reserve_out_serial_id=$2"
                            ",last_reserve_recoup_serial_id=$3"
                            ",last_reserve_close_serial_id=$4"
                            ",last_purse_merges_serial_id=$5"
                            ",last_purse_deposits_serial_id=$6"
                            ",last_account_merges_serial_id=$7"
                            ",last_history_requests_serial_id=$8"
                            ",last_close_requests_serial_id=$9"
                            " WHERE master_pub=$10"),
    /* Used in #postgres_get_auditor_progress_reserve() */
    GNUNET_PQ_make_prepare ("auditor_progress_select_reserve",
                            "SELECT"
                            " last_reserve_in_serial_id"
                            ",last_reserve_out_serial_id"
                            ",last_reserve_recoup_serial_id"
                            ",last_reserve_close_serial_id"
                            ",last_purse_merges_serial_id"
                            ",last_purse_deposits_serial_id"
                            ",last_account_merges_serial_id"
                            ",last_history_requests_serial_id"
                            ",last_close_requests_serial_id"
                            " FROM auditor_progress_reserve"
                            " WHERE master_pub=$1;"),
    /* Used in #postgres_insert_auditor_progress_reserve() */
    GNUNET_PQ_make_prepare ("auditor_progress_insert_reserve",
                            "INSERT INTO auditor_progress_reserve "
                            "(master_pub"
                            ",last_reserve_in_serial_id"
                            ",last_reserve_out_serial_id"
                            ",last_reserve_recoup_serial_id"
                            ",last_reserve_close_serial_id"
                            ",last_purse_merges_serial_id"
                            ",last_purse_deposits_serial_id"
                            ",last_account_merges_serial_id"
                            ",last_history_requests_serial_id"
                            ",last_close_requests_serial_id"
                            ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);"),
    /* Used in #postgres_update_auditor_progress_aggregation() */
    GNUNET_PQ_make_prepare ("auditor_progress_update_aggregation",
                            "UPDATE auditor_progress_aggregation SET "
                            " last_wire_out_serial_id=$1"
                            " WHERE master_pub=$2"),
    /* Used in #postgres_get_auditor_progress_aggregation() */
    GNUNET_PQ_make_prepare ("auditor_progress_select_aggregation",
                            "SELECT"
                            " last_wire_out_serial_id"
                            " FROM auditor_progress_aggregation"
                            " WHERE master_pub=$1;"),
    /* Used in #postgres_insert_auditor_progress_aggregation() */
    GNUNET_PQ_make_prepare ("auditor_progress_insert_aggregation",
                            "INSERT INTO auditor_progress_aggregation "
                            "(master_pub"
                            ",last_wire_out_serial_id"
                            ") VALUES ($1,$2);"),
    /* Used in #postgres_update_auditor_progress_deposit_confirmation() */
    GNUNET_PQ_make_prepare ("auditor_progress_update_deposit_confirmation",
                            "UPDATE auditor_progress_deposit_confirmation SET "
                            " last_deposit_confirmation_serial_id=$1"
                            " WHERE master_pub=$2"),
    /* Used in #postgres_get_auditor_progress_deposit_confirmation() */
    GNUNET_PQ_make_prepare ("auditor_progress_select_deposit_confirmation",
                            "SELECT"
                            " last_deposit_confirmation_serial_id"
                            " FROM auditor_progress_deposit_confirmation"
                            " WHERE master_pub=$1;"),
    /* Used in #postgres_insert_auditor_progress_deposit_confirmation() */
    GNUNET_PQ_make_prepare ("auditor_progress_insert_deposit_confirmation",
                            "INSERT INTO auditor_progress_deposit_confirmation "
                            "(master_pub"
                            ",last_deposit_confirmation_serial_id"
                            ") VALUES ($1,$2);"),
    /* Used in #postgres_update_auditor_progress_coin() */
    GNUNET_PQ_make_prepare ("auditor_progress_update_coin",
                            "UPDATE auditor_progress_coin SET "
                            " last_withdraw_serial_id=$1"
                            ",last_deposit_serial_id=$2"
                            ",last_melt_serial_id=$3"
                            ",last_refund_serial_id=$4"
                            ",last_recoup_serial_id=$5"
                            ",last_recoup_refresh_serial_id=$6"
                            ",last_purse_deposits_serial_id=$7"
                            ",last_purse_refunds_serial_id=$8"
                            " WHERE master_pub=$9"),
    /* Used in #postgres_get_auditor_progress_coin() */
    GNUNET_PQ_make_prepare ("auditor_progress_select_coin",
                            "SELECT"
                            " last_withdraw_serial_id"
                            ",last_deposit_serial_id"
                            ",last_melt_serial_id"
                            ",last_refund_serial_id"
                            ",last_recoup_serial_id"
                            ",last_recoup_refresh_serial_id"
                            ",last_purse_deposits_serial_id"
                            ",last_purse_refunds_serial_id"
                            " FROM auditor_progress_coin"
                            " WHERE master_pub=$1;"),
    /* Used in #postgres_insert_auditor_progress() */
    GNUNET_PQ_make_prepare ("auditor_progress_insert_coin",
                            "INSERT INTO auditor_progress_coin "
                            "(master_pub"
                            ",last_withdraw_serial_id"
                            ",last_deposit_serial_id"
                            ",last_melt_serial_id"
                            ",last_refund_serial_id"
                            ",last_recoup_serial_id"
                            ",last_recoup_refresh_serial_id"
                            ",last_purse_deposits_serial_id"
                            ",last_purse_refunds_serial_id"
                            ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9);"),
    /* Used in #postgres_insert_wire_auditor_account_progress() */
    GNUNET_PQ_make_prepare ("wire_auditor_account_progress_insert",
                            "INSERT INTO wire_auditor_account_progress "
                            "(master_pub"
                            ",account_name"
                            ",last_wire_reserve_in_serial_id"
                            ",last_wire_wire_out_serial_id"
                            ",wire_in_off"
                            ",wire_out_off"
                            ") VALUES ($1,$2,$3,$4,$5,$6);"),
    /* Used in #postgres_update_wire_auditor_account_progress() */
    GNUNET_PQ_make_prepare ("wire_auditor_account_progress_update",
                            "UPDATE wire_auditor_account_progress SET "
                            " last_wire_reserve_in_serial_id=$1"
                            ",last_wire_wire_out_serial_id=$2"
                            ",wire_in_off=$3"
                            ",wire_out_off=$4"
                            " WHERE master_pub=$5 AND account_name=$6"),
    /* Used in #postgres_get_wire_auditor_account_progress() */
    GNUNET_PQ_make_prepare ("wire_auditor_account_progress_select",
                            "SELECT"
                            " last_wire_reserve_in_serial_id"
                            ",last_wire_wire_out_serial_id"
                            ",wire_in_off"
                            ",wire_out_off"
                            " FROM wire_auditor_account_progress"
                            " WHERE master_pub=$1 AND account_name=$2;"),
    /* Used in #postgres_insert_wire_auditor_progress() */
    GNUNET_PQ_make_prepare ("wire_auditor_progress_insert",
                            "INSERT INTO wire_auditor_progress "
                            "(master_pub"
                            ",last_timestamp"
                            ",last_reserve_close_uuid"
                            ") VALUES ($1,$2,$3);"),
    /* Used in #postgres_update_wire_auditor_progress() */
    GNUNET_PQ_make_prepare ("wire_auditor_progress_update",
                            "UPDATE wire_auditor_progress SET "
                            " last_timestamp=$1"
                            ",last_reserve_close_uuid=$2"
                            " WHERE master_pub=$3"),
    /* Used in #postgres_get_wire_auditor_progress() */
    GNUNET_PQ_make_prepare ("wire_auditor_progress_select",
                            "SELECT"
                            " last_timestamp"
                            ",last_reserve_close_uuid"
                            " FROM wire_auditor_progress"
                            " WHERE master_pub=$1;"),
    /* Used in #postgres_insert_reserve_info() */
    GNUNET_PQ_make_prepare ("auditor_reserves_insert",
                            "INSERT INTO auditor_reserves "
                            "(reserve_pub"
                            ",master_pub"
                            ",reserve_balance_val"
                            ",reserve_balance_frac"
                            ",withdraw_fee_balance_val"
                            ",withdraw_fee_balance_frac"
                            ",expiration_date"
                            ",origin_account"
                            ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8);"),
    /* Used in #postgres_update_reserve_info() */
    GNUNET_PQ_make_prepare ("auditor_reserves_update",
                            "UPDATE auditor_reserves SET"
                            " reserve_balance_val=$1"
                            ",reserve_balance_frac=$2"
                            ",withdraw_fee_balance_val=$3"
                            ",withdraw_fee_balance_frac=$4"
                            ",expiration_date=$5"
                            " WHERE reserve_pub=$6 AND master_pub=$7;"),
    /* Used in #postgres_get_reserve_info() */
    GNUNET_PQ_make_prepare ("auditor_reserves_select",
                            "SELECT"
                            " reserve_balance_val"
                            ",reserve_balance_frac"
                            ",withdraw_fee_balance_val"
                            ",withdraw_fee_balance_frac"
                            ",expiration_date"
                            ",auditor_reserves_rowid"
                            ",origin_account"
                            " FROM auditor_reserves"
                            " WHERE reserve_pub=$1 AND master_pub=$2;"),
    /* Used in #postgres_del_reserve_info() */
    GNUNET_PQ_make_prepare ("auditor_reserves_delete",
                            "DELETE"
                            " FROM auditor_reserves"
                            " WHERE reserve_pub=$1 AND master_pub=$2;"),
    /* Used in #postgres_insert_reserve_summary() */
    GNUNET_PQ_make_prepare ("auditor_reserve_balance_insert",
                            "INSERT INTO auditor_reserve_balance"
                            "(master_pub"
                            ",reserve_balance_val"
                            ",reserve_balance_frac"
                            ",withdraw_fee_balance_val"
                            ",withdraw_fee_balance_frac"
                            ",purse_fee_balance_val"
                            ",purse_fee_balance_frac"
                            ",history_fee_balance_val"
                            ",history_fee_balance_frac"
                            ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)"),
    /* Used in #postgres_update_reserve_summary() */
    GNUNET_PQ_make_prepare ("auditor_reserve_balance_update",
                            "UPDATE auditor_reserve_balance SET"
                            " reserve_balance_val=$1"
                            ",reserve_balance_frac=$2"
                            ",withdraw_fee_balance_val=$3"
                            ",withdraw_fee_balance_frac=$4"
                            ",purse_fee_balance_val=$5"
                            ",purse_fee_balance_frac=$6"
                            ",history_fee_balance_val=$7"
                            ",history_fee_balance_frac=$8"
                            " WHERE master_pub=$9;"),
    /* Used in #postgres_get_reserve_summary() */
    GNUNET_PQ_make_prepare ("auditor_reserve_balance_select",
                            "SELECT"
                            " reserve_balance_val"
                            ",reserve_balance_frac"
                            ",withdraw_fee_balance_val"
                            ",withdraw_fee_balance_frac"
                            ",purse_fee_balance_val"
                            ",purse_fee_balance_frac"
                            ",history_fee_balance_val"
                            ",history_fee_balance_frac"
                            " FROM auditor_reserve_balance"
                            " WHERE master_pub=$1;"),
    /* Used in #postgres_insert_wire_fee_summary() */
    GNUNET_PQ_make_prepare ("auditor_wire_fee_balance_insert",
                            "INSERT INTO auditor_wire_fee_balance"
                            "(master_pub"
                            ",wire_fee_balance_val"
                            ",wire_fee_balance_frac"
                            ") VALUES ($1,$2,$3)"),
    /* Used in #postgres_update_wire_fee_summary() */
    GNUNET_PQ_make_prepare ("auditor_wire_fee_balance_update",
                            "UPDATE auditor_wire_fee_balance SET"
                            " wire_fee_balance_val=$1"
                            ",wire_fee_balance_frac=$2"
                            " WHERE master_pub=$3;"),
    /* Used in #postgres_get_wire_fee_summary() */
    GNUNET_PQ_make_prepare ("auditor_wire_fee_balance_select",
                            "SELECT"
                            " wire_fee_balance_val"
                            ",wire_fee_balance_frac"
                            " FROM auditor_wire_fee_balance"
                            " WHERE master_pub=$1;"),
    /* Used in #postgres_insert_denomination_balance() */
    GNUNET_PQ_make_prepare ("auditor_denomination_pending_insert",
                            "INSERT INTO auditor_denomination_pending "
                            "(denom_pub_hash"
                            ",denom_balance_val"
                            ",denom_balance_frac"
                            ",denom_loss_val"
                            ",denom_loss_frac"
                            ",num_issued"
                            ",denom_risk_val"
                            ",denom_risk_frac"
                            ",recoup_loss_val"
                            ",recoup_loss_frac"
                            ") VALUES ("
                            "$1,$2,$3,$4,$5,$6,$7,$8,$9,$10"
                            ");"),
    /* Used in #postgres_update_denomination_balance() */
    GNUNET_PQ_make_prepare ("auditor_denomination_pending_update",
                            "UPDATE auditor_denomination_pending SET"
                            " denom_balance_val=$1"
                            ",denom_balance_frac=$2"
                            ",denom_loss_val=$3"
                            ",denom_loss_frac=$4"
                            ",num_issued=$5"
                            ",denom_risk_val=$6"
                            ",denom_risk_frac=$7"
                            ",recoup_loss_val=$8"
                            ",recoup_loss_frac=$9"
                            " WHERE denom_pub_hash=$10"),
    /* Used in #postgres_get_denomination_balance() */
    GNUNET_PQ_make_prepare ("auditor_denomination_pending_select",
                            "SELECT"
                            " denom_balance_val"
                            ",denom_balance_frac"
                            ",denom_loss_val"
                            ",denom_loss_frac"
                            ",num_issued"
                            ",denom_risk_val"
                            ",denom_risk_frac"
                            ",recoup_loss_val"
                            ",recoup_loss_frac"
                            " FROM auditor_denomination_pending"
                            " WHERE denom_pub_hash=$1"),
    /* Used in #postgres_insert_balance_summary() */
    GNUNET_PQ_make_prepare ("auditor_balance_summary_insert",
                            "INSERT INTO auditor_balance_summary "
                            "(master_pub"
                            ",denom_balance_val"
                            ",denom_balance_frac"
                            ",deposit_fee_balance_val"
                            ",deposit_fee_balance_frac"
                            ",melt_fee_balance_val"
                            ",melt_fee_balance_frac"
                            ",refund_fee_balance_val"
                            ",refund_fee_balance_frac"
                            ",risk_val"
                            ",risk_frac"
                            ",loss_val"
                            ",loss_frac"
                            ",irregular_recoup_val"
                            ",irregular_recoup_frac"
                            ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,"
                            "          $11,$12,$13,$14,$15);"),
    /* Used in #postgres_update_balance_summary() */
    GNUNET_PQ_make_prepare ("auditor_balance_summary_update",
                            "UPDATE auditor_balance_summary SET"
                            " denom_balance_val=$1"
                            ",denom_balance_frac=$2"
                            ",deposit_fee_balance_val=$3"
                            ",deposit_fee_balance_frac=$4"
                            ",melt_fee_balance_val=$5"
                            ",melt_fee_balance_frac=$6"
                            ",refund_fee_balance_val=$7"
                            ",refund_fee_balance_frac=$8"
                            ",risk_val=$9"
                            ",risk_frac=$10"
                            ",loss_val=$11"
                            ",loss_frac=$12"
                            ",irregular_recoup_val=$13"
                            ",irregular_recoup_frac=$14"
                            " WHERE master_pub=$15;"),
    /* Used in #postgres_get_balance_summary() */
    GNUNET_PQ_make_prepare ("auditor_balance_summary_select",
                            "SELECT"
                            " denom_balance_val"
                            ",denom_balance_frac"
                            ",deposit_fee_balance_val"
                            ",deposit_fee_balance_frac"
                            ",melt_fee_balance_val"
                            ",melt_fee_balance_frac"
                            ",refund_fee_balance_val"
                            ",refund_fee_balance_frac"
                            ",risk_val"
                            ",risk_frac"
                            ",loss_val"
                            ",loss_frac"
                            ",irregular_recoup_val"
                            ",irregular_recoup_frac"
                            " FROM auditor_balance_summary"
                            " WHERE master_pub=$1;"),
    /* Used in #postgres_insert_historic_denom_revenue() */
    GNUNET_PQ_make_prepare ("auditor_historic_denomination_revenue_insert",
                            "INSERT INTO auditor_historic_denomination_revenue"
                            "(master_pub"
                            ",denom_pub_hash"
                            ",revenue_timestamp"
                            ",revenue_balance_val"
                            ",revenue_balance_frac"
                            ",loss_balance_val"
                            ",loss_balance_frac"
                            ") VALUES ($1,$2,$3,$4,$5,$6,$7);"),
    /* Used in #postgres_select_historic_denom_revenue() */
    GNUNET_PQ_make_prepare ("auditor_historic_denomination_revenue_select",
                            "SELECT"
                            " denom_pub_hash"
                            ",revenue_timestamp"
                            ",revenue_balance_val"
                            ",revenue_balance_frac"
                            ",loss_balance_val"
                            ",loss_balance_frac"
                            " FROM auditor_historic_denomination_revenue"
                            " WHERE master_pub=$1;"),
    /* Used in #postgres_insert_historic_reserve_revenue() */
    GNUNET_PQ_make_prepare ("auditor_historic_reserve_summary_insert",
                            "INSERT INTO auditor_historic_reserve_summary"
                            "(master_pub"
                            ",start_date"
                            ",end_date"
                            ",reserve_profits_val"
                            ",reserve_profits_frac"
                            ") VALUES ($1,$2,$3,$4,$5);"),
    /* Used in #postgres_select_historic_reserve_revenue() */
    GNUNET_PQ_make_prepare ("auditor_historic_reserve_summary_select",
                            "SELECT"
                            " start_date"
                            ",end_date"
                            ",reserve_profits_val"
                            ",reserve_profits_frac"
                            " FROM auditor_historic_reserve_summary"
                            " WHERE master_pub=$1;"),
    /* Used in #postgres_insert_predicted_result() */
    GNUNET_PQ_make_prepare ("auditor_predicted_result_insert",
                            "INSERT INTO auditor_predicted_result"
                            "(master_pub"
                            ",balance_val"
                            ",balance_frac"
                            ",drained_val"
                            ",drained_frac"
                            ") VALUES ($1,$2,$3,$4,$5);"),
    /* Used in #postgres_update_predicted_result() */
    GNUNET_PQ_make_prepare ("auditor_predicted_result_update",
                            "UPDATE auditor_predicted_result SET"
                            " balance_val=$1"
                            ",balance_frac=$2"
                            ",drained_val=$3"
                            ",drained_frac=$4"
                            " WHERE master_pub=$5;"),
    /* Used in #postgres_get_predicted_balance() */
    GNUNET_PQ_make_prepare ("auditor_predicted_result_select",
                            "SELECT"
                            " balance_val"
                            ",balance_frac"
                            ",drained_val"
                            ",drained_frac"
                            " FROM auditor_predicted_result"
                            " WHERE master_pub=$1;"),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO auditor;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };
  struct GNUNET_PQ_Context *db_conn;

  if (NULL != pg->conn)
  {
    GNUNET_PQ_reconnect_if_down (pg->conn);
    return GNUNET_OK;
  }
  db_conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                        "auditordb-postgres",
                                        NULL,
                                        es,
                                        ps);
  if (NULL == db_conn)
    return GNUNET_SYSERR;
  pg->conn = db_conn;
  return GNUNET_OK;
}


/**
 * Do a pre-flight check that we are not in an uncommitted transaction.
 * If we are, rollback the previous transaction and output a warning.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if we rolled back an earlier transaction
 *         #GNUNET_SYSERR if we have no DB connection
 */
static enum GNUNET_GenericReturnValue
postgres_preflight (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("ROLLBACK"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  if (NULL == pg->conn)
  {
    if (GNUNET_OK !=
        setup_connection (pg))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }
  if (NULL == pg->transaction_name)
    return GNUNET_OK; /* all good */
  if (GNUNET_OK ==
      GNUNET_PQ_exec_statements (pg->conn,
                                 es))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "BUG: Preflight check rolled back transaction `%s'!\n",
                pg->transaction_name);
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "BUG: Preflight check failed to rollback transaction `%s'!\n",
                pg->transaction_name);
  }
  pg->transaction_name = NULL;
  return GNUNET_NO;
}


/**
 * Start a transaction.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
postgres_start (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("START TRANSACTION ISOLATION LEVEL SERIALIZABLE"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  postgres_preflight (cls);
  if (GNUNET_OK !=
      GNUNET_PQ_exec_statements (pg->conn,
                                 es))
  {
    TALER_LOG_ERROR ("Failed to start transaction\n");
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Roll back the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 */
static void
postgres_rollback (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("ROLLBACK"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  GNUNET_break (GNUNET_OK ==
                GNUNET_PQ_exec_statements (pg->conn,
                                           es));
}


/**
 * Commit the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
postgres_commit (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "do_commit",
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
static enum GNUNET_GenericReturnValue
postgres_gc (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = {0};
  struct GNUNET_PQ_QueryParam params_time[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_PreparedStatement ps[] = {
#if 0
    GNUNET_PQ_make_prepare ("gc_auditor",
                            "TODO: #4960",
                            0),
#endif
    GNUNET_PQ_PREPARED_STATEMENT_END
  };
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO auditor;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  now = GNUNET_TIME_absolute_get ();
  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "auditordb-postgres",
                                     NULL,
                                     es,
                                     ps);
  if (NULL == conn)
    return GNUNET_SYSERR;
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "TODO: Auditor GC not implemented (#4960)\n");
  qs = GNUNET_PQ_eval_prepared_non_select (conn,
                                           "gc_auditor",
                                           params_time);
  GNUNET_PQ_disconnect (conn);
  if (0 > qs)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Insert information about an exchange this auditor will be auditing.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param exchange_url public (base) URL of the API of the exchange
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_exchange (void *cls,
                          const struct TALER_MasterPublicKeyP *master_pub,
                          const char *exchange_url)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_string (exchange_url),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_insert_exchange",
                                             params);
}


/**
 * Delete an exchange from the list of exchanges this auditor is auditing.
 * Warning: this will cascade and delete all knowledge of this auditor related
 * to this exchange!
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_delete_exchange (void *cls,
                          const struct TALER_MasterPublicKeyP *master_pub)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_delete_exchange",
                                             params);
}


/**
 * Closure for #exchange_info_cb().
 */
struct ExchangeInfoContext
{

  /**
   * Function to call for each exchange.
   */
  TALER_AUDITORDB_ExchangeCallback cb;

  /**
   * Closure for @e cb
   */
  void *cb_cls;

  /**
   * Query status to return.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #postgres_list_exchanges().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ExchangeInfoContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
exchange_info_cb (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct ExchangeInfoContext *eic = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_MasterPublicKeyP master_pub;
    char *exchange_url;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_pub", &master_pub),
      GNUNET_PQ_result_spec_string ("exchange_url", &exchange_url),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      eic->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    eic->qs = i + 1;
    eic->cb (eic->cb_cls,
             &master_pub,
             exchange_url);
    GNUNET_free (exchange_url);
  }
}


/**
 * Obtain information about exchanges this auditor is auditing.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_list_exchanges (void *cls,
                         TALER_AUDITORDB_ExchangeCallback cb,
                         void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct ExchangeInfoContext eic = {
    .cb = cb,
    .cb_cls = cb_cls
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "auditor_list_exchanges",
                                             params,
                                             &exchange_info_cb,
                                             &eic);
  if (qs > 0)
    return eic.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}


/**
 * Insert information about a signing key of the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param sk signing key information to store
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_exchange_signkey (
  void *cls,
  const struct TALER_AUDITORDB_ExchangeSigningKey *sk)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&sk->master_public_key),
    GNUNET_PQ_query_param_timestamp (&sk->ep_start),
    GNUNET_PQ_query_param_timestamp (&sk->ep_expire),
    GNUNET_PQ_query_param_timestamp (&sk->ep_end),
    GNUNET_PQ_query_param_auto_from_type (&sk->exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (&sk->master_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_insert_exchange_signkey",
                                             params);
}


/**
 * Insert information about a deposit confirmation into the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param dc deposit confirmation information to store
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_deposit_confirmation (
  void *cls,
  const struct TALER_AUDITORDB_DepositConfirmation *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&dc->master_public_key),
    GNUNET_PQ_query_param_auto_from_type (&dc->h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&dc->h_extensions),
    GNUNET_PQ_query_param_auto_from_type (&dc->h_wire),
    GNUNET_PQ_query_param_timestamp (&dc->exchange_timestamp),
    GNUNET_PQ_query_param_timestamp (&dc->wire_deadline),
    GNUNET_PQ_query_param_timestamp (&dc->refund_deadline),
    TALER_PQ_query_param_amount (&dc->amount_without_fee),
    GNUNET_PQ_query_param_auto_from_type (&dc->coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&dc->merchant),
    GNUNET_PQ_query_param_auto_from_type (&dc->exchange_sig),
    GNUNET_PQ_query_param_auto_from_type (&dc->exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (&dc->master_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_deposit_confirmation_insert",
                                             params);
}


/**
 * Closure for #deposit_confirmation_cb().
 */
struct DepositConfirmationContext
{

  /**
   * Master public key that is being used.
   */
  const struct TALER_MasterPublicKeyP *master_pub;

  /**
   * Function to call for each deposit confirmation.
   */
  TALER_AUDITORDB_DepositConfirmationCallback cb;

  /**
   * Closure for @e cb
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Query status to return.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #postgres_get_deposit_confirmations().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct DepositConfirmationContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
deposit_confirmation_cb (void *cls,
                         PGresult *result,
                         unsigned int num_results)
{
  struct DepositConfirmationContext *dcc = cls;
  struct PostgresClosure *pg = dcc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    uint64_t serial_id;
    struct TALER_AUDITORDB_DepositConfirmation dc = {
      .master_public_key = *dcc->master_pub
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial_id",
                                    &serial_id),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &dc.h_contract_terms),
      GNUNET_PQ_result_spec_auto_from_type ("h_extensions",
                                            &dc.h_extensions),
      GNUNET_PQ_result_spec_auto_from_type ("h_wire",
                                            &dc.h_wire),
      GNUNET_PQ_result_spec_timestamp ("exchange_timestamp",
                                       &dc.exchange_timestamp),
      GNUNET_PQ_result_spec_timestamp ("refund_deadline",
                                       &dc.refund_deadline),
      GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                       &dc.wire_deadline),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_without_fee",
                                   &dc.amount_without_fee),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &dc.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &dc.merchant),
      GNUNET_PQ_result_spec_auto_from_type ("exchange_sig",
                                            &dc.exchange_sig),
      GNUNET_PQ_result_spec_auto_from_type ("exchange_pub",
                                            &dc.exchange_pub),
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &dc.master_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      dcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    dcc->qs = i + 1;
    if (GNUNET_OK !=
        dcc->cb (dcc->cb_cls,
                 serial_id,
                 &dc))
      break;
  }
}


/**
 * Get information about deposit confirmations from the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_public_key for which exchange do we want to get deposit confirmations
 * @param start_id row/serial ID where to start the iteration (0 from
 *                  the start, exclusive, i.e. serial_ids must start from 1)
 * @param cb function to call with results
 * @param cb_cls closure for @a cb
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_deposit_confirmations (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_public_key,
  uint64_t start_id,
  TALER_AUDITORDB_DepositConfirmationCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_public_key),
    GNUNET_PQ_query_param_uint64 (&start_id),
    GNUNET_PQ_query_param_end
  };
  struct DepositConfirmationContext dcc = {
    .master_pub = master_public_key,
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "auditor_deposit_confirmation_select",
                                             params,
                                             &deposit_confirmation_cb,
                                             &dcc);
  if (qs > 0)
    return dcc.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param ppr where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor_progress_reserve (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ProgressPointReserve *ppr)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_in_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_out_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_recoup_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_close_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_purse_merges_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_purse_deposits_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_account_merges_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_history_requests_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_close_requests_serial_id),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_progress_insert_reserve",
                                             params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param ppr where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_auditor_progress_reserve (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ProgressPointReserve *ppr)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_in_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_out_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_recoup_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_close_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_purse_merges_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_purse_deposits_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_account_merges_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_history_requests_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_close_requests_serial_id),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_progress_update_reserve",
                                             params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param[out] ppr set to where the auditor is in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_auditor_progress_reserve (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct TALER_AUDITORDB_ProgressPointReserve *ppr)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_reserve_in_serial_id",
                                  &ppr->last_reserve_in_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_reserve_out_serial_id",
                                  &ppr->last_reserve_out_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_reserve_recoup_serial_id",
                                  &ppr->last_reserve_recoup_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_reserve_close_serial_id",
                                  &ppr->last_reserve_close_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_purse_merges_serial_id",
                                  &ppr->last_purse_merges_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_purse_deposits_serial_id",
                                  &ppr->last_purse_deposits_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_account_merges_serial_id",
                                  &ppr->last_account_merges_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_history_requests_serial_id",
                                  &ppr->last_history_requests_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_close_requests_serial_id",
                                  &ppr->last_close_requests_serial_id),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_progress_select_reserve",
                                                   params,
                                                   rs);
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param ppa where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor_progress_aggregation (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ProgressPointAggregation *ppa)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_uint64 (&ppa->last_wire_out_serial_id),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_progress_insert_aggregation",
                                             params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param ppa where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_auditor_progress_aggregation (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ProgressPointAggregation *ppa)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&ppa->last_wire_out_serial_id),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_progress_update_aggregation",
                                             params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param[out] ppa set to where the auditor is in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_auditor_progress_aggregation (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct TALER_AUDITORDB_ProgressPointAggregation *ppa)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_wire_out_serial_id",
                                  &ppa->last_wire_out_serial_id),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_progress_select_aggregation",
                                                   params,
                                                   rs);
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param ppdc where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor_progress_deposit_confirmation (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_uint64 (&ppdc->last_deposit_confirmation_serial_id),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_progress_insert_deposit_confirmation",
                                             params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param ppdc where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_auditor_progress_deposit_confirmation (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&ppdc->last_deposit_confirmation_serial_id),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_progress_update_deposit_confirmation",
                                             params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param[out] ppdc set to where the auditor is in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_auditor_progress_deposit_confirmation (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_deposit_confirmation_serial_id",
                                  &ppdc->last_deposit_confirmation_serial_id),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_progress_select_deposit_confirmation",
                                                   params,
                                                   rs);
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param ppc where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor_progress_coin (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ProgressPointCoin *ppc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_uint64 (&ppc->last_withdraw_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_deposit_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_melt_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_refund_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_recoup_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_recoup_refresh_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_purse_deposits_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_purse_refunds_serial_id),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_progress_insert_coin",
                                             params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param ppc where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_auditor_progress_coin (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ProgressPointCoin *ppc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&ppc->last_withdraw_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_deposit_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_melt_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_refund_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_recoup_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_recoup_refresh_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_purse_deposits_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_purse_refunds_serial_id),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_progress_update_coin",
                                             params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param[out] ppc set to where the auditor is in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_auditor_progress_coin (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct TALER_AUDITORDB_ProgressPointCoin *ppc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_withdraw_serial_id",
                                  &ppc->last_withdraw_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_deposit_serial_id",
                                  &ppc->last_deposit_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_melt_serial_id",
                                  &ppc->last_melt_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_refund_serial_id",
                                  &ppc->last_refund_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_recoup_serial_id",
                                  &ppc->last_recoup_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_recoup_refresh_serial_id",
                                  &ppc->last_recoup_refresh_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_purse_deposits_serial_id",
                                  &ppc->last_purse_deposits_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_purse_refunds_serial_id",
                                  &ppc->last_purse_refunds_serial_id),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_progress_select_coin",
                                                   params,
                                                   rs);
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param account_name name of the wire account we are auditing
 * @param pp how far are we in the auditor's tables
 * @param in_wire_off how far are we in the incoming wire transfers
 * @param out_wire_off how far are we in the outgoing wire transfers
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_wire_auditor_account_progress (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const char *account_name,
  const struct TALER_AUDITORDB_WireAccountProgressPoint *pp,
  uint64_t in_wire_off,
  uint64_t out_wire_off)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_uint64 (&pp->last_reserve_in_serial_id),
    GNUNET_PQ_query_param_uint64 (&pp->last_wire_out_serial_id),
    GNUNET_PQ_query_param_uint64 (&in_wire_off),
    GNUNET_PQ_query_param_uint64 (&out_wire_off),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "wire_auditor_account_progress_insert",
                                             params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param account_name name of the wire account we are auditing
 * @param pp where is the auditor in processing
 * @param in_wire_off how far are we in the incoming wire transaction history
 * @param out_wire_off how far are we in the outgoing wire transaction history
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_wire_auditor_account_progress (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const char *account_name,
  const struct TALER_AUDITORDB_WireAccountProgressPoint *pp,
  uint64_t in_wire_off,
  uint64_t out_wire_off)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&pp->last_reserve_in_serial_id),
    GNUNET_PQ_query_param_uint64 (&pp->last_wire_out_serial_id),
    GNUNET_PQ_query_param_uint64 (&in_wire_off),
    GNUNET_PQ_query_param_uint64 (&out_wire_off),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "wire_auditor_account_progress_update",
                                             params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param account_name name of the wire account we are auditing
 * @param[out] pp where is the auditor in processing
 * @param[out] in_wire_off how far are we in the incoming wire transaction history
 * @param[out] out_wire_off how far are we in the outgoing wire transaction history
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_wire_auditor_account_progress (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const char *account_name,
  struct TALER_AUDITORDB_WireAccountProgressPoint *pp,
  uint64_t *in_wire_off,
  uint64_t *out_wire_off)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_wire_reserve_in_serial_id",
                                  &pp->last_reserve_in_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_wire_wire_out_serial_id",
                                  &pp->last_wire_out_serial_id),
    GNUNET_PQ_result_spec_uint64 ("wire_in_off",
                                  in_wire_off),
    GNUNET_PQ_result_spec_uint64 ("wire_out_off",
                                  out_wire_off),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "wire_auditor_account_progress_select",
                                                   params,
                                                   rs);
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param pp where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_wire_auditor_progress (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_WireProgressPoint *pp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_timestamp (&pp->last_timestamp),
    GNUNET_PQ_query_param_uint64 (&pp->last_reserve_close_uuid),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "wire_auditor_progress_insert",
                                             params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param pp where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_wire_auditor_progress (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_WireProgressPoint *pp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&pp->last_timestamp),
    GNUNET_PQ_query_param_uint64 (&pp->last_reserve_close_uuid),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "wire_auditor_progress_update",
                                             params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param[out] pp set to where the auditor is in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_wire_auditor_progress (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct TALER_AUDITORDB_WireProgressPoint *pp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("last_timestamp",
                                     &pp->last_timestamp),
    GNUNET_PQ_result_spec_uint64 ("last_reserve_close_uuid",
                                  &pp->last_reserve_close_uuid),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "wire_auditor_progress_select",
                                                   params,
                                                   rs);
}


/**
 * Insert information about a reserve.  There must not be an
 * existing record for the reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param master_pub master public key of the exchange
 * @param reserve_balance amount stored in the reserve
 * @param withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @param expiration_date expiration date of the reserve
 * @param origin_account where did the money in the reserve originally come from
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_reserve_info (void *cls,
                              const struct TALER_ReservePublicKeyP *reserve_pub,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              const struct TALER_Amount *reserve_balance,
                              const struct TALER_Amount *withdraw_fee_balance,
                              struct GNUNET_TIME_Timestamp expiration_date,
                              const char *origin_account)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (reserve_balance),
    TALER_PQ_query_param_amount (withdraw_fee_balance),
    GNUNET_PQ_query_param_timestamp (&expiration_date),
    GNUNET_PQ_query_param_string (origin_account),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (reserve_balance,
                                            withdraw_fee_balance));

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_reserves_insert",
                                             params);
}


/**
 * Update information about a reserve.  Destructively updates an
 * existing record, which must already exist.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param master_pub master public key of the exchange
 * @param reserve_balance amount stored in the reserve
 * @param withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @param expiration_date expiration date of the reserve
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_reserve_info (void *cls,
                              const struct TALER_ReservePublicKeyP *reserve_pub,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              const struct TALER_Amount *reserve_balance,
                              const struct TALER_Amount *withdraw_fee_balance,
                              struct GNUNET_TIME_Timestamp expiration_date)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (reserve_balance),
    TALER_PQ_query_param_amount (withdraw_fee_balance),
    GNUNET_PQ_query_param_timestamp (&expiration_date),
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (reserve_balance,
                                            withdraw_fee_balance));

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_reserves_update",
                                             params);
}


/**
 * Delete information about a reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param master_pub master public key of the exchange
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_del_reserve_info (void *cls,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           const struct TALER_MasterPublicKeyP *master_pub)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_reserves_delete",
                                             params);
}


/**
 * Get information about a reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param master_pub master public key of the exchange
 * @param[out] rowid which row did we get the information from
 * @param[out] reserve_balance amount stored in the reserve
 * @param[out] withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @param[out] expiration_date expiration date of the reserve
 * @param[out] sender_account from where did the money in the reserve originally come from
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_info (void *cls,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           const struct TALER_MasterPublicKeyP *master_pub,
                           uint64_t *rowid,
                           struct TALER_Amount *reserve_balance,
                           struct TALER_Amount *withdraw_fee_balance,
                           struct GNUNET_TIME_Timestamp *expiration_date,
                           char **sender_account)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("reserve_balance", reserve_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("withdraw_fee_balance", withdraw_fee_balance),
    GNUNET_PQ_result_spec_timestamp ("expiration_date", expiration_date),
    GNUNET_PQ_result_spec_uint64 ("auditor_reserves_rowid", rowid),
    GNUNET_PQ_result_spec_string ("origin_account", sender_account),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_reserves_select",
                                                   params,
                                                   rs);
}


/**
 * Insert information about all reserves.  There must not be an
 * existing record for the @a master_pub.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param reserve_balance amount stored in the reserve
 * @param withdraw_fee_balance amount the exchange gained in withdraw fees
 * @param purse_fee_balance amount the exchange gained in purse fees
 * @param history_fee_balance amount the exchange gained in history fees
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_reserve_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *reserve_balance,
  const struct TALER_Amount *withdraw_fee_balance,
  const struct TALER_Amount *purse_fee_balance,
  const struct TALER_Amount *history_fee_balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (reserve_balance),
    TALER_PQ_query_param_amount (withdraw_fee_balance),
    TALER_PQ_query_param_amount (purse_fee_balance),
    TALER_PQ_query_param_amount (history_fee_balance),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (reserve_balance,
                                            withdraw_fee_balance));

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_reserve_balance_insert",
                                             params);
}


/**
 * Update information about all reserves.  Destructively updates an
 * existing record, which must already exist.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param reserve_balance amount stored in the reserve
 * @param withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @param purse_fee_balance amount the exchange gained in purse fees
 * @param history_fee_balance amount the exchange gained in history fees
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_reserve_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *reserve_balance,
  const struct TALER_Amount *withdraw_fee_balance,
  const struct TALER_Amount *purse_fee_balance,
  const struct TALER_Amount *history_fee_balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (reserve_balance),
    TALER_PQ_query_param_amount (withdraw_fee_balance),
    TALER_PQ_query_param_amount (purse_fee_balance),
    TALER_PQ_query_param_amount (history_fee_balance),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_reserve_balance_update",
                                             params);
}


/**
 * Get summary information about all reserves.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param[out] reserve_balance amount stored in reserves
 * @param[out] withdraw_fee_balance amount the exchange gained in withdraw fees
 * @param[out] purse_fee_balance amount the exchange gained in purse fees
 * @param[out] history_fee_balance amount the exchange gained in history fees
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_summary (void *cls,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              struct TALER_Amount *reserve_balance,
                              struct TALER_Amount *withdraw_fee_balance,
                              struct TALER_Amount *purse_fee_balance,
                              struct TALER_Amount *history_fee_balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("reserve_balance", reserve_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("withdraw_fee_balance", withdraw_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee_balance", purse_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee_balance", history_fee_balance),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_reserve_balance_select",
                                                   params,
                                                   rs);
}


/**
 * Insert information about exchange's wire fee balance. There must not be an
 * existing record for the same @a master_pub.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param wire_fee_balance amount the exchange gained in wire fees
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_wire_fee_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *wire_fee_balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (wire_fee_balance),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_wire_fee_balance_insert",
                                             params);
}


/**
 * Insert information about exchange's wire fee balance.  Destructively updates an
 * existing record, which must already exist.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param wire_fee_balance amount the exchange gained in wire fees
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_wire_fee_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *wire_fee_balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (wire_fee_balance),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_wire_fee_balance_update",
                                             params);
}


/**
 * Get summary information about an exchanges wire fee balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param[out] wire_fee_balance set amount the exchange gained in wire fees
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_wire_fee_summary (void *cls,
                               const struct TALER_MasterPublicKeyP *master_pub,
                               struct TALER_Amount *wire_fee_balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee_balance",
                                 wire_fee_balance),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_wire_fee_balance_select",
                                                   params,
                                                   rs);
}


/**
 * Insert information about a denomination key's balances.  There
 * must not be an existing record for the denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param denom_pub_hash hash of the denomination public key
 * @param denom_balance value of coins outstanding with this denomination key
 * @param denom_loss value of coins redeemed that were not outstanding (effectively, negative @a denom_balance)
 * @param denom_risk value of coins issued with this denomination key
 * @param recoup_loss losses from recoup (if this denomination was revoked)
 * @param num_issued how many coins of this denomination did the exchange blind-sign
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_denomination_balance (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  const struct TALER_Amount *denom_balance,
  const struct TALER_Amount *denom_loss,
  const struct TALER_Amount *denom_risk,
  const struct TALER_Amount *recoup_loss,
  uint64_t num_issued)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    TALER_PQ_query_param_amount (denom_balance),
    TALER_PQ_query_param_amount (denom_loss),
    GNUNET_PQ_query_param_uint64 (&num_issued),
    TALER_PQ_query_param_amount (denom_risk),
    TALER_PQ_query_param_amount (recoup_loss),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_denomination_pending_insert",
                                             params);
}


/**
 * Update information about a denomination key's balances.  There
 * must be an existing record for the denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param denom_pub_hash hash of the denomination public key
 * @param denom_balance value of coins outstanding with this denomination key
 * @param denom_loss value of coins redeemed that were not outstanding (effectively, negative @a denom_balance)
* @param denom_risk value of coins issued with this denomination key
 * @param recoup_loss losses from recoup (if this denomination was revoked)
 * @param num_issued how many coins of this denomination did the exchange blind-sign
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_denomination_balance (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  const struct TALER_Amount *denom_balance,
  const struct TALER_Amount *denom_loss,
  const struct TALER_Amount *denom_risk,
  const struct TALER_Amount *recoup_loss,
  uint64_t num_issued)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (denom_balance),
    TALER_PQ_query_param_amount (denom_loss),
    GNUNET_PQ_query_param_uint64 (&num_issued),
    TALER_PQ_query_param_amount (denom_risk),
    TALER_PQ_query_param_amount (recoup_loss),
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_denomination_pending_update",
                                             params);
}


/**
 * Get information about a denomination key's balances.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param denom_pub_hash hash of the denomination public key
 * @param[out] denom_balance value of coins outstanding with this denomination key
 * @param[out] denom_risk value of coins issued with this denomination key
 * @param[out] denom_loss value of coins redeemed that were not outstanding (effectively, negative @a denom_balance)
 * @param[out] recoup_loss losses from recoup (if this denomination was revoked)
 * @param[out] num_issued how many coins of this denomination did the exchange blind-sign
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_denomination_balance (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct TALER_Amount *denom_balance,
  struct TALER_Amount *denom_loss,
  struct TALER_Amount *denom_risk,
  struct TALER_Amount *recoup_loss,
  uint64_t *num_issued)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("denom_balance", denom_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("denom_loss", denom_loss),
    TALER_PQ_RESULT_SPEC_AMOUNT ("denom_risk", denom_risk),
    TALER_PQ_RESULT_SPEC_AMOUNT ("recoup_loss", recoup_loss),
    GNUNET_PQ_result_spec_uint64 ("num_issued", num_issued),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_denomination_pending_select",
                                                   params,
                                                   rs);
}


/**
 * Insert information about an exchange's denomination balances.  There
 * must not be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param denom_balance value of coins outstanding with this denomination key
 * @param deposit_fee_balance total deposit fees collected for this DK
 * @param melt_fee_balance total melt fees collected for this DK
 * @param refund_fee_balance total refund fees collected for this DK
 * @param risk maximum risk exposure of the exchange
 * @param loss materialized @a risk from recoup
 * @param irregular_recoup recoups on non-revoked coins
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_balance_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *denom_balance,
  const struct TALER_Amount *deposit_fee_balance,
  const struct TALER_Amount *melt_fee_balance,
  const struct TALER_Amount *refund_fee_balance,
  const struct TALER_Amount *risk,
  const struct TALER_Amount *loss,
  const struct TALER_Amount *irregular_recoup)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (denom_balance),
    TALER_PQ_query_param_amount (deposit_fee_balance),
    TALER_PQ_query_param_amount (melt_fee_balance),
    TALER_PQ_query_param_amount (refund_fee_balance),
    TALER_PQ_query_param_amount (risk),
    TALER_PQ_query_param_amount (loss),
    TALER_PQ_query_param_amount (irregular_recoup),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (denom_balance,
                                            deposit_fee_balance));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (denom_balance,
                                            melt_fee_balance));

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (denom_balance,
                                            refund_fee_balance));

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_balance_summary_insert",
                                             params);
}


/**
 * Update information about an exchange's denomination balances.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param denom_balance value of coins outstanding with this denomination key
 * @param deposit_fee_balance total deposit fees collected for this DK
 * @param melt_fee_balance total melt fees collected for this DK
 * @param refund_fee_balance total refund fees collected for this DK
 * @param risk maximum risk exposure of the exchange
 * @param loss materialized @a risk from recoup
 * @param irregular_recoup recoups made on non-revoked coins
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_balance_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *denom_balance,
  const struct TALER_Amount *deposit_fee_balance,
  const struct TALER_Amount *melt_fee_balance,
  const struct TALER_Amount *refund_fee_balance,
  const struct TALER_Amount *risk,
  const struct TALER_Amount *loss,
  const struct TALER_Amount *irregular_recoup)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (denom_balance),
    TALER_PQ_query_param_amount (deposit_fee_balance),
    TALER_PQ_query_param_amount (melt_fee_balance),
    TALER_PQ_query_param_amount (refund_fee_balance),
    TALER_PQ_query_param_amount (risk),
    TALER_PQ_query_param_amount (loss),
    TALER_PQ_query_param_amount (irregular_recoup),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_balance_summary_update",
                                             params);
}


/**
 * Get information about an exchange's denomination balances.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param[out] denom_balance value of coins outstanding with this denomination key
 * @param[out] deposit_fee_balance total deposit fees collected for this DK
 * @param[out] melt_fee_balance total melt fees collected for this DK
 * @param[out] refund_fee_balance total refund fees collected for this DK
 * @param[out] risk maximum risk exposure of the exchange
 * @param[out] loss losses from recoup (on revoked denominations)
 * @param[out] irregular_recoup recoups on NOT revoked denominations
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_balance_summary (void *cls,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              struct TALER_Amount *denom_balance,
                              struct TALER_Amount *deposit_fee_balance,
                              struct TALER_Amount *melt_fee_balance,
                              struct TALER_Amount *refund_fee_balance,
                              struct TALER_Amount *risk,
                              struct TALER_Amount *loss,
                              struct TALER_Amount *irregular_recoup)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("denom_balance", denom_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("deposit_fee_balance", deposit_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("melt_fee_balance", melt_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("refund_fee_balance", refund_fee_balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("risk", risk),
    TALER_PQ_RESULT_SPEC_AMOUNT ("loss", loss),
    TALER_PQ_RESULT_SPEC_AMOUNT ("irregular_recoup", irregular_recoup),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_balance_summary_select",
                                                   params,
                                                   rs);
}


/**
 * Insert information about an exchange's historic
 * revenue about a denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param denom_pub_hash hash of the denomination key
 * @param revenue_timestamp when did this profit get realized
 * @param revenue_balance what was the total profit made from
 *                        deposit fees, melting fees, refresh fees
 *                        and coins that were never returned?
 * @param loss_balance total losses suffered by the exchange at the time
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_historic_denom_revenue (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct GNUNET_TIME_Timestamp revenue_timestamp,
  const struct TALER_Amount *revenue_balance,
  const struct TALER_Amount *loss_balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_timestamp (&revenue_timestamp),
    TALER_PQ_query_param_amount (revenue_balance),
    TALER_PQ_query_param_amount (loss_balance),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_historic_denomination_revenue_insert",
                                             params);
}


/**
 * Closure for #historic_denom_revenue_cb().
 */
struct HistoricDenomRevenueContext
{
  /**
   * Function to call for each result.
   */
  TALER_AUDITORDB_HistoricDenominationRevenueDataCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Number of results processed.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #postgres_select_historic_denom_revenue().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct HistoricRevenueContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
historic_denom_revenue_cb (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct HistoricDenomRevenueContext *hrc = cls;
  struct PostgresClosure *pg = hrc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_DenominationHashP denom_pub_hash;
    struct GNUNET_TIME_Timestamp revenue_timestamp;
    struct TALER_Amount revenue_balance;
    struct TALER_Amount loss;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &denom_pub_hash),
      GNUNET_PQ_result_spec_timestamp ("revenue_timestamp",
                                       &revenue_timestamp),
      TALER_PQ_RESULT_SPEC_AMOUNT ("revenue_balance",
                                   &revenue_balance),
      TALER_PQ_RESULT_SPEC_AMOUNT ("loss_balance",
                                   &loss),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      hrc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }

    hrc->qs = i + 1;
    if (GNUNET_OK !=
        hrc->cb (hrc->cb_cls,
                 &denom_pub_hash,
                 revenue_timestamp,
                 &revenue_balance,
                 &loss))
      break;
  }
}


/**
 * Obtain all of the historic denomination key revenue
 * of the given @a master_pub.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_historic_denom_revenue (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  TALER_AUDITORDB_HistoricDenominationRevenueDataCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct HistoricDenomRevenueContext hrc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "auditor_historic_denomination_revenue_select",
                                             params,
                                             &historic_denom_revenue_cb,
                                             &hrc);
  if (qs <= 0)
    return qs;
  return hrc.qs;
}


/**
 * Insert information about an exchange's historic revenue from reserves.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param start_time beginning of aggregated time interval
 * @param end_time end of aggregated time interval
 * @param reserve_profits total profits made
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_historic_reserve_revenue (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_Amount *reserve_profits)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_timestamp (&start_time),
    GNUNET_PQ_query_param_timestamp (&end_time),
    TALER_PQ_query_param_amount (reserve_profits),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_historic_reserve_summary_insert",
                                             params);
}


/**
 * Closure for #historic_reserve_revenue_cb().
 */
struct HistoricReserveRevenueContext
{
  /**
   * Function to call for each result.
   */
  TALER_AUDITORDB_HistoricReserveRevenueDataCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Number of results processed.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #postgres_select_historic_reserve_revenue().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct HistoricRevenueContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
historic_reserve_revenue_cb (void *cls,
                             PGresult *result,
                             unsigned int num_results)
{
  struct HistoricReserveRevenueContext *hrc = cls;
  struct PostgresClosure *pg = hrc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct GNUNET_TIME_Timestamp start_date;
    struct GNUNET_TIME_Timestamp end_date;
    struct TALER_Amount reserve_profits;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_timestamp ("start_date",
                                       &start_date),
      GNUNET_PQ_result_spec_timestamp ("end_date",
                                       &end_date),
      TALER_PQ_RESULT_SPEC_AMOUNT ("reserve_profits",
                                   &reserve_profits),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      hrc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    hrc->qs = i + 1;
    if (GNUNET_OK !=
        hrc->cb (hrc->cb_cls,
                 start_date,
                 end_date,
                 &reserve_profits))
      break;
  }
}


/**
 * Return information about an exchange's historic revenue from reserves.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param cb function to call with results
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_historic_reserve_revenue (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  TALER_AUDITORDB_HistoricReserveRevenueDataCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;
  struct HistoricReserveRevenueContext hrc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "auditor_historic_reserve_summary_select",
                                             params,
                                             &historic_reserve_revenue_cb,
                                             &hrc);
  if (0 >= qs)
    return qs;
  return hrc.qs;
}


/**
 * Insert information about the predicted exchange's bank
 * account balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param balance what the bank account balance of the exchange should show
 * @param drained amount that was drained in profits
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_predicted_result (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *balance,
  const struct TALER_Amount *drained)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (balance),
    TALER_PQ_query_param_amount (drained),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_predicted_result_insert",
                                             params);
}


/**
 * Update information about an exchange's predicted balance.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param balance what the bank account balance of the exchange should show
 * @param drained amount that was drained in profits
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_predicted_result (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *balance,
  const struct TALER_Amount *drained)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (balance),
    TALER_PQ_query_param_amount (drained),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_predicted_result_update",
                                             params);
}


/**
 * Get an exchange's predicted balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param[out] balance expected bank account balance of the exchange
 * @param[out] drained amount drained so far
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_predicted_balance (void *cls,
                                const struct TALER_MasterPublicKeyP *master_pub,
                                struct TALER_Amount *balance,
                                struct TALER_Amount *drained)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                 balance),
    TALER_PQ_RESULT_SPEC_AMOUNT ("drained",
                                 drained),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "auditor_predicted_result_select",
                                                   params,
                                                   rs);
}


/**
 * Initialize Postgres database subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_AUDITORDB_Plugin`
 */
void *
libtaler_plugin_auditordb_postgres_init (void *cls)
{
  const struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct PostgresClosure *pg;
  struct TALER_AUDITORDB_Plugin *plugin;

  pg = GNUNET_new (struct PostgresClosure);
  pg->cfg = cfg;
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &pg->currency))
  {
    GNUNET_free (pg);
    return NULL;
  }
  plugin = GNUNET_new (struct TALER_AUDITORDB_Plugin);
  plugin->cls = pg;
  plugin->preflight = &postgres_preflight;
  plugin->drop_tables = &postgres_drop_tables;
  plugin->create_tables = &postgres_create_tables;
  plugin->start = &postgres_start;
  plugin->commit = &postgres_commit;
  plugin->rollback = &postgres_rollback;
  plugin->gc = &postgres_gc;

  plugin->insert_exchange = &postgres_insert_exchange;
  plugin->delete_exchange = &postgres_delete_exchange;
  plugin->list_exchanges = &postgres_list_exchanges;
  plugin->insert_exchange_signkey = &postgres_insert_exchange_signkey;
  plugin->insert_deposit_confirmation = &postgres_insert_deposit_confirmation;
  plugin->get_deposit_confirmations = &postgres_get_deposit_confirmations;

  plugin->get_auditor_progress_reserve = &postgres_get_auditor_progress_reserve;
  plugin->update_auditor_progress_reserve =
    &postgres_update_auditor_progress_reserve;
  plugin->insert_auditor_progress_reserve =
    &postgres_insert_auditor_progress_reserve;
  plugin->get_auditor_progress_aggregation =
    &postgres_get_auditor_progress_aggregation;
  plugin->update_auditor_progress_aggregation =
    &postgres_update_auditor_progress_aggregation;
  plugin->insert_auditor_progress_aggregation =
    &postgres_insert_auditor_progress_aggregation;
  plugin->get_auditor_progress_deposit_confirmation =
    &postgres_get_auditor_progress_deposit_confirmation;
  plugin->update_auditor_progress_deposit_confirmation =
    &postgres_update_auditor_progress_deposit_confirmation;
  plugin->insert_auditor_progress_deposit_confirmation =
    &postgres_insert_auditor_progress_deposit_confirmation;
  plugin->get_auditor_progress_coin = &postgres_get_auditor_progress_coin;
  plugin->update_auditor_progress_coin = &postgres_update_auditor_progress_coin;
  plugin->insert_auditor_progress_coin = &postgres_insert_auditor_progress_coin;

  plugin->get_wire_auditor_account_progress =
    &postgres_get_wire_auditor_account_progress;
  plugin->update_wire_auditor_account_progress =
    &postgres_update_wire_auditor_account_progress;
  plugin->insert_wire_auditor_account_progress =
    &postgres_insert_wire_auditor_account_progress;
  plugin->get_wire_auditor_progress = &postgres_get_wire_auditor_progress;
  plugin->update_wire_auditor_progress = &postgres_update_wire_auditor_progress;
  plugin->insert_wire_auditor_progress = &postgres_insert_wire_auditor_progress;

  plugin->del_reserve_info = &postgres_del_reserve_info;
  plugin->get_reserve_info = &postgres_get_reserve_info;
  plugin->update_reserve_info = &postgres_update_reserve_info;
  plugin->insert_reserve_info = &postgres_insert_reserve_info;

  plugin->get_reserve_summary = &postgres_get_reserve_summary;
  plugin->update_reserve_summary = &postgres_update_reserve_summary;
  plugin->insert_reserve_summary = &postgres_insert_reserve_summary;

  plugin->get_wire_fee_summary = &postgres_get_wire_fee_summary;
  plugin->update_wire_fee_summary = &postgres_update_wire_fee_summary;
  plugin->insert_wire_fee_summary = &postgres_insert_wire_fee_summary;

  plugin->get_denomination_balance = &postgres_get_denomination_balance;
  plugin->update_denomination_balance = &postgres_update_denomination_balance;
  plugin->insert_denomination_balance = &postgres_insert_denomination_balance;

  plugin->get_balance_summary = &postgres_get_balance_summary;
  plugin->update_balance_summary = &postgres_update_balance_summary;
  plugin->insert_balance_summary = &postgres_insert_balance_summary;

  plugin->select_historic_denom_revenue =
    &postgres_select_historic_denom_revenue;
  plugin->insert_historic_denom_revenue =
    &postgres_insert_historic_denom_revenue;

  plugin->select_historic_reserve_revenue =
    &postgres_select_historic_reserve_revenue;
  plugin->insert_historic_reserve_revenue =
    &postgres_insert_historic_reserve_revenue;

  plugin->get_predicted_balance = &postgres_get_predicted_balance;
  plugin->update_predicted_result = &postgres_update_predicted_result;
  plugin->insert_predicted_result = &postgres_insert_predicted_result;

  return plugin;
}


/**
 * Shutdown Postgres database subsystem.
 *
 * @param cls a `struct TALER_AUDITORDB_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_auditordb_postgres_done (void *cls)
{
  struct TALER_AUDITORDB_Plugin *plugin = cls;
  struct PostgresClosure *pg = plugin->cls;

  if (NULL != pg->conn)
    GNUNET_PQ_disconnect (pg->conn);
  GNUNET_free (pg->currency);
  GNUNET_free (pg);
  GNUNET_free (plugin);
  return NULL;
}


/* end of plugin_auditordb_postgres.c */
