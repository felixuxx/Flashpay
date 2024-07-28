/*
   This file is part of GNUnet
   Copyright (C) 2020-2024 Taler Systems SA

   GNUnet is free software: you can redistribute it and/or modify it
   under the terms of the GNU Affero General Public License as published
   by the Free Software Foundation, either version 3 of the License,
   or (at your option) any later version.

   GNUnet is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Affero General Public License for more details.

   You should have received a copy of the GNU Affero General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.

     SPDX-License-Identifier: AGPL3.0-or-later
 */
/**
 * @file exchangedb/pg_lookup_records_by_table.c
 * @brief implementation of lookup_records_by_table
 * @author Christian Grothoff
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_records_by_table.h"
#include "pg_helper.h"
#include <gnunet/gnunet_pq_lib.h>


/**
 * Closure for callbacks used by #postgres_lookup_records_by_table.
 */
struct LookupRecordsByTableContext
{
  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_ReplicationCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Set to true on errors.
   */
  bool error;
};


/**
 * Function called with denominations table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_denominations (void *cls,
                             PGresult *result,
                             unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_DENOMINATIONS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_uint32 (
        "denom_type",
        &td.details.denominations.denom_type),
      GNUNET_PQ_result_spec_uint32 (
        "age_mask",
        &td.details.denominations.age_mask),
      TALER_PQ_result_spec_denom_pub (
        "denom_pub",
        &td.details.denominations.denom_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "master_sig",
        &td.details.denominations.master_sig),
      GNUNET_PQ_result_spec_timestamp (
        "valid_from",
        &td.details.denominations.valid_from),
      GNUNET_PQ_result_spec_timestamp (
        "expire_withdraw",
        &td.details.denominations.
        expire_withdraw),
      GNUNET_PQ_result_spec_timestamp (
        "expire_deposit",
        &td.details.denominations.
        expire_deposit),
      GNUNET_PQ_result_spec_timestamp (
        "expire_legal",
        &td.details.denominations.expire_legal),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "coin",
        &td.details.denominations.coin),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "fee_withdraw",
        &td.details.denominations.fees.withdraw),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "fee_deposit",
        &td.details.denominations.fees.deposit),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "fee_refresh",
        &td.details.denominations.fees.refresh),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "fee_refund",
        &td.details.denominations.fees.refund),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with denomination_revocations table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_denomination_revocations (void *cls,
                                        PGresult *result,
                                        unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_DENOMINATION_REVOCATIONS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_uint64 (
        "denominations_serial",
        &td.details.denomination_revocations.denominations_serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "master_sig",
        &td.details.denomination_revocations.master_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with wire_targets table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_wire_targets (void *cls,
                            PGresult *result,
                            unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_WIRE_TARGETS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "access_token",
        &td.details.wire_targets.target_token),
      GNUNET_PQ_result_spec_string (
        "payto_uri",
        &td.details.wire_targets.payto_uri),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with reserves table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_reserves (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RESERVES
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &td.details.reserves.reserve_pub),
      GNUNET_PQ_result_spec_timestamp ("expiration_date",
                                       &td.details.reserves.expiration_date),
      GNUNET_PQ_result_spec_timestamp ("gc_date",
                                       &td.details.reserves.gc_date),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with reserves_in table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_reserves_in (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RESERVES_IN
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.reserves_in.reserve_pub),
      GNUNET_PQ_result_spec_uint64 (
        "wire_reference",
        &td.details.reserves_in.wire_reference),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "credit",
        &td.details.reserves_in.credit),
      GNUNET_PQ_result_spec_auto_from_type (
        "wire_source_h_payto",
        &td.details.reserves_in.sender_account_h_payto),
      GNUNET_PQ_result_spec_string (
        "exchange_account_section",
        &td.details.reserves_in.exchange_account_section),
      GNUNET_PQ_result_spec_timestamp (
        "execution_date",
        &td.details.reserves_in.execution_date),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with reserves_close table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_reserves_close (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RESERVES_CLOSE
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.reserves_close.reserve_pub),
      GNUNET_PQ_result_spec_timestamp (
        "execution_date",
        &td.details.reserves_close.execution_date),
      GNUNET_PQ_result_spec_auto_from_type (
        "wtid",
        &td.details.reserves_close.wtid),
      GNUNET_PQ_result_spec_auto_from_type (
        "wire_target_h_payto",
        &td.details.reserves_close.sender_account_h_payto),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount",
        &td.details.reserves_close.amount),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "closing_fee",
        &td.details.reserves_close.closing_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with reserves_open_requests table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_reserves_open_requests (void *cls,
                                      PGresult *result,
                                      unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RESERVES_OPEN_REQUESTS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.reserves_open_requests.reserve_pub),
      GNUNET_PQ_result_spec_timestamp (
        "request_timestamp",
        &td.details.reserves_open_requests.request_timestamp),
      GNUNET_PQ_result_spec_timestamp (
        "expiration_date",
        &td.details.reserves_open_requests.expiration_date),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_sig",
        &td.details.reserves_open_requests.reserve_sig),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "reserve_payment",
        &td.details.reserves_open_requests.reserve_payment),
      GNUNET_PQ_result_spec_uint32 (
        "requested_purse_limit",
        &td.details.reserves_open_requests.requested_purse_limit),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with reserves_open_deposits table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_reserves_open_deposits (void *cls,
                                      PGresult *result,
                                      unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RESERVES_OPEN_DEPOSITS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_sig",
        &td.details.reserves_open_deposits.reserve_sig),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.reserves_open_deposits.reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_pub",
        &td.details.reserves_open_deposits.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_sig",
        &td.details.reserves_open_deposits.coin_sig),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "contribution",
        &td.details.reserves_open_deposits.contribution),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with reserves_out table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_reserves_out (void *cls,
                            PGresult *result,
                            unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RESERVES_OUT
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_blind_ev",
        &td.details.reserves_out.h_blind_ev),
      GNUNET_PQ_result_spec_uint64 (
        "denominations_serial",
        &td.details.reserves_out.denominations_serial),
      TALER_PQ_result_spec_blinded_denom_sig (
        "denom_sig",
        &td.details.reserves_out.denom_sig),
      GNUNET_PQ_result_spec_uint64 (
        "reserve_uuid",
        &td.details.reserves_out.reserve_uuid),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_sig",
        &td.details.reserves_out.reserve_sig),
      GNUNET_PQ_result_spec_timestamp (
        "execution_date",
        &td.details.reserves_out.execution_date),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount_with_fee",
        &td.details.reserves_out.amount_with_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with auditors table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_auditors (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_AUDITORS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("auditor_pub",
                                            &td.details.auditors.auditor_pub),
      GNUNET_PQ_result_spec_string ("auditor_url",
                                    &td.details.auditors.auditor_url),
      GNUNET_PQ_result_spec_string ("auditor_name",
                                    &td.details.auditors.auditor_name),
      GNUNET_PQ_result_spec_bool ("is_active",
                                  &td.details.auditors.is_active),
      GNUNET_PQ_result_spec_timestamp ("last_change",
                                       &td.details.auditors.last_change),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with auditor_denom_sigs table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_auditor_denom_sigs (void *cls,
                                  PGresult *result,
                                  unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_AUDITOR_DENOM_SIGS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_uint64 (
        "auditor_uuid",
        &td.details.auditor_denom_sigs.auditor_uuid),
      GNUNET_PQ_result_spec_uint64 (
        "denominations_serial",
        &td.details.auditor_denom_sigs.denominations_serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "auditor_sig",
        &td.details.auditor_denom_sigs.auditor_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with exchange_sign_keys table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_exchange_sign_keys (void *cls,
                                  PGresult *result,
                                  unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_EXCHANGE_SIGN_KEYS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("exchange_pub",
                                            &td.details.exchange_sign_keys.
                                            exchange_pub),
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &td.details.exchange_sign_keys.
                                            master_sig),
      GNUNET_PQ_result_spec_timestamp ("valid_from",
                                       &td.details.exchange_sign_keys.meta.
                                       start),
      GNUNET_PQ_result_spec_timestamp ("expire_sign",
                                       &td.details.exchange_sign_keys.meta.
                                       expire_sign),
      GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                       &td.details.exchange_sign_keys.meta.
                                       expire_legal),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with signkey_revocations table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_signkey_revocations (void *cls,
                                   PGresult *result,
                                   unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_SIGNKEY_REVOCATIONS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_uint64 ("esk_serial",
                                    &td.details.signkey_revocations.esk_serial),
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &td.details.signkey_revocations.
                                            master_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with known_coins table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_known_coins (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_KNOWN_COINS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_pub",
        &td.details.known_coins.coin_pub),
      TALER_PQ_result_spec_denom_sig (
        "denom_sig",
        &td.details.known_coins.denom_sig),
      GNUNET_PQ_result_spec_uint64 (
        "denominations_serial",
        &td.details.known_coins.denominations_serial),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with refresh_commitments table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_refresh_commitments (void *cls,
                                   PGresult *result,
                                   unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_REFRESH_COMMITMENTS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "rc",
        &td.details.refresh_commitments.rc),
      GNUNET_PQ_result_spec_auto_from_type (
        "old_coin_sig",
        &td.details.refresh_commitments.old_coin_sig),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount_with_fee",
        &td.details.refresh_commitments.amount_with_fee),
      GNUNET_PQ_result_spec_uint32 (
        "noreveal_index",
        &td.details.refresh_commitments.noreveal_index),
      GNUNET_PQ_result_spec_auto_from_type (
        "old_coin_pub",
        &td.details.refresh_commitments.old_coin_pub),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with refresh_revealed_coins table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_refresh_revealed_coins (void *cls,
                                      PGresult *result,
                                      unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_REFRESH_REVEALED_COINS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_uint32 (
        "freshcoin_index",
        &td.details.refresh_revealed_coins.freshcoin_index),
      GNUNET_PQ_result_spec_auto_from_type (
        "link_sig",
        &td.details.refresh_revealed_coins.link_sig),
      GNUNET_PQ_result_spec_variable_size (
        "coin_ev",
        (void **) &td.details.refresh_revealed_coins.coin_ev,
        &td.details.refresh_revealed_coins.coin_ev_size),
      TALER_PQ_result_spec_blinded_denom_sig (
        "ev_sig",
        &td.details.refresh_revealed_coins.ev_sig),
      TALER_PQ_result_spec_exchange_withdraw_values (
        "ewv",
        &td.details.refresh_revealed_coins.ewv),
      GNUNET_PQ_result_spec_uint64 (
        "denominations_serial",
        &td.details.refresh_revealed_coins.denominations_serial),
      GNUNET_PQ_result_spec_uint64 (
        "melt_serial_id",
        &td.details.refresh_revealed_coins.melt_serial_id),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with refresh_transfer_keys table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_refresh_transfer_keys (void *cls,
                                     PGresult *result,
                                     unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_REFRESH_TRANSFER_KEYS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    void *tpriv;
    size_t tpriv_size;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("transfer_pub",
                                            &td.details.refresh_transfer_keys.tp
                                            ),
      GNUNET_PQ_result_spec_variable_size ("transfer_privs",
                                           &tpriv,
                                           &tpriv_size),
      GNUNET_PQ_result_spec_uint64 ("melt_serial_id",
                                    &td.details.refresh_transfer_keys.
                                    melt_serial_id),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    /* Both conditions should be identical, but we conservatively also guard against
       unwarranted changes to the structure here. */
    if ( (tpriv_size !=
          sizeof (td.details.refresh_transfer_keys.tprivs)) ||
         (tpriv_size !=
          (TALER_CNC_KAPPA - 1) * sizeof (struct TALER_TransferPrivateKeyP)) )
    {
      GNUNET_break (0);
      GNUNET_PQ_cleanup_result (rs);
      ctx->error = true;
      return;
    }
    GNUNET_memcpy (&td.details.refresh_transfer_keys.tprivs[0],
                   tpriv,
                   tpriv_size);
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with batch deposits table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_batch_deposits (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_BATCH_DEPOSITS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_uint64 (
        "shard",
        &td.details.batch_deposits.shard),
      GNUNET_PQ_result_spec_auto_from_type (
        "merchant_pub",
        &td.details.batch_deposits.merchant_pub),
      GNUNET_PQ_result_spec_timestamp (
        "wallet_timestamp",
        &td.details.batch_deposits.wallet_timestamp),
      GNUNET_PQ_result_spec_timestamp (
        "exchange_timestamp",
        &td.details.batch_deposits.exchange_timestamp),
      GNUNET_PQ_result_spec_timestamp (
        "refund_deadline",
        &td.details.batch_deposits.refund_deadline),
      GNUNET_PQ_result_spec_timestamp (
        "wire_deadline",
        &td.details.batch_deposits.wire_deadline),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_contract_terms",
        &td.details.batch_deposits.h_contract_terms),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type (
          "wallet_data_hash",
          &td.details.batch_deposits.wallet_data_hash),
        &td.details.batch_deposits.no_wallet_data_hash),
      GNUNET_PQ_result_spec_auto_from_type (
        "wire_salt",
        &td.details.batch_deposits.wire_salt),
      GNUNET_PQ_result_spec_auto_from_type (
        "wire_target_h_payto",
        &td.details.batch_deposits.wire_target_h_payto),
      GNUNET_PQ_result_spec_auto_from_type (
        "policy_blocked",
        &td.details.batch_deposits.policy_blocked),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_uint64 (
          "policy_details_serial_id",
          &td.details.batch_deposits.policy_details_serial_id),
        &td.details.batch_deposits.no_policy_details),
      GNUNET_PQ_result_spec_end
    };

    td.details.batch_deposits.policy_details_serial_id = 0;
    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with coin deposits table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_coin_deposits (void *cls,
                             PGresult *result,
                             unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_COIN_DEPOSITS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_uint64 (
        "batch_deposit_serial_id",
        &td.details.coin_deposits.batch_deposit_serial_id),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_pub",
        &td.details.coin_deposits.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_sig",
        &td.details.coin_deposits.coin_sig),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount_with_fee",
        &td.details.coin_deposits.amount_with_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with refunds table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_refunds (void *cls,
                       PGresult *result,
                       unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_REFUNDS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_pub",
        &td.details.refunds.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "merchant_sig",
        &td.details.refunds.merchant_sig),
      GNUNET_PQ_result_spec_uint64 (
        "rtransaction_id",
        &td.details.refunds.rtransaction_id),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount_with_fee",
        &td.details.refunds.amount_with_fee),
      GNUNET_PQ_result_spec_uint64 (
        "batch_deposit_serial_id",
        &td.details.refunds.batch_deposit_serial_id),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with wire_out table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_wire_out (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_WIRE_OUT
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_timestamp (
        "execution_date",
        &td.details.wire_out.execution_date),
      GNUNET_PQ_result_spec_auto_from_type (
        "wtid_raw",
        &td.details.wire_out.wtid_raw),
      GNUNET_PQ_result_spec_auto_from_type (
        "wire_target_h_payto",
        &td.details.wire_out.wire_target_h_payto),
      GNUNET_PQ_result_spec_string (
        "exchange_account_section",
        &td.details.wire_out.exchange_account_section),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount",
        &td.details.wire_out.amount),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with aggregation_tracking table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_aggregation_tracking (void *cls,
                                    PGresult *result,
                                    unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_AGGREGATION_TRACKING
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_uint64 (
        "batch_deposit_serial_id",
        &td.details.aggregation_tracking.batch_deposit_serial_id),
      GNUNET_PQ_result_spec_auto_from_type (
        "wtid_raw",
        &td.details.aggregation_tracking.wtid_raw),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with wire_fee table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_wire_fee (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_WIRE_FEE
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_string ("wire_method",
                                    &td.details.wire_fee.wire_method),
      GNUNET_PQ_result_spec_timestamp ("start_date",
                                       &td.details.wire_fee.start_date),
      GNUNET_PQ_result_spec_timestamp ("end_date",
                                       &td.details.wire_fee.end_date),
      TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee",
                                   &td.details.wire_fee.fees.wire),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &td.details.wire_fee.fees.closing),
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &td.details.wire_fee.master_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with wire_fee table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_global_fee (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_GLOBAL_FEE
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      GNUNET_PQ_result_spec_timestamp (
        "start_date",
        &td.details.global_fee.start_date),
      GNUNET_PQ_result_spec_timestamp (
        "end_date",
        &td.details.global_fee.end_date),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "history_fee",
        &td.details.global_fee.fees.history),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "account_fee",
        &td.details.global_fee.fees.account),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "purse_fee",
        &td.details.global_fee.fees.purse),
      GNUNET_PQ_result_spec_relative_time (
        "purse_timeout",
        &td.details.global_fee.purse_timeout),
      GNUNET_PQ_result_spec_relative_time (
        "history_expiration",
        &td.details.global_fee.history_expiration),
      GNUNET_PQ_result_spec_uint32 (
        "purse_account_limit",
        &td.details.global_fee.purse_account_limit),
      GNUNET_PQ_result_spec_auto_from_type (
        "master_sig",
        &td.details.global_fee.master_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with recoup table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_recoup (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RECOUP
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &td.details.recoup.coin_sig),
      GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                            &td.details.recoup.coin_blind),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &td.details.recoup.amount),
      GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                       &td.details.recoup.timestamp),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_pub",
        &td.details.recoup.coin_pub),
      GNUNET_PQ_result_spec_uint64 ("reserve_out_serial_id",
                                    &td.details.recoup.reserve_out_serial_id),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with recoup_refresh table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_recoup_refresh (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RECOUP_REFRESH
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &td.details.recoup_refresh.coin_sig)
      ,
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_blind",
        &td.details.recoup_refresh.coin_blind),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &td.details.recoup_refresh.amount),
      GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                       &td.details.recoup_refresh.timestamp),
      GNUNET_PQ_result_spec_uint64 ("known_coin_id",
                                    &td.details.recoup_refresh.known_coin_id),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_pub",
        &td.details.recoup_refresh.coin_pub),
      GNUNET_PQ_result_spec_uint64 ("rrc_serial",
                                    &td.details.recoup_refresh.rrc_serial),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with extensions table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_extensions (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_EXTENSIONS
  };
  bool no_manifest = false;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("extension_id",
                                    &td.serial),
      GNUNET_PQ_result_spec_string ("name",
                                    &td.details.extensions.name),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("manifest",
                                      &td.details.extensions.manifest),
        &no_manifest),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with policy_details table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_policy_details (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_POLICY_DETAILS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("policy_details_serial_id",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("hash_code",
                                            &td.details.policy_details.
                                            hash_code),
      GNUNET_PQ_result_spec_allow_null (
        TALER_PQ_result_spec_json ("policy_json",
                                   &td.details.policy_details.
                                   policy_json),
        &td.details.policy_details.no_policy_json),
      GNUNET_PQ_result_spec_timestamp ("deadline",
                                       &td.details.policy_details.
                                       deadline),
      TALER_PQ_RESULT_SPEC_AMOUNT ("commitment",
                                   &td.details.policy_details.
                                   commitment),
      TALER_PQ_RESULT_SPEC_AMOUNT ("accumulated_total",
                                   &td.details.policy_details.
                                   accumulated_total),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee",
                                   &td.details.policy_details.
                                   fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("transferable",
                                   &td.details.policy_details.
                                   transferable),
      GNUNET_PQ_result_spec_uint16 ("fulfillment_state",
                                    &td.details.policy_details.
                                    fulfillment_state),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_uint64 ("fulfillment_id",
                                      &td.details.policy_details.
                                      fulfillment_id),
        &td.details.policy_details.no_fulfillment_id),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with policy_fulfillments table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_policy_fulfillments (void *cls,
                                   PGresult *result,
                                   unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_POLICY_FULFILLMENTS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    bool no_proof = false;
    bool no_timestamp = false;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("fulfillment_id",
                                    &td.serial),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_timestamp ("fulfillment_timestamp",
                                         &td.details.policy_fulfillments.
                                         fulfillment_timestamp),
        &no_timestamp),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("fulfillment_proof",
                                      &td.details.policy_fulfillments.
                                      fulfillment_proof),
        &no_proof),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with purse_requests table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_purse_requests (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_PURSE_REQUESTS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "purse_requests_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_pub",
        &td.details.purse_requests.purse_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "merge_pub",
        &td.details.purse_requests.merge_pub),
      GNUNET_PQ_result_spec_timestamp (
        "purse_creation",
        &td.details.purse_requests.purse_creation),
      GNUNET_PQ_result_spec_timestamp (
        "purse_expiration",
        &td.details.purse_requests.purse_expiration),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_contract_terms",
        &td.details.purse_requests.h_contract_terms),
      GNUNET_PQ_result_spec_uint32 (
        "age_limit",
        &td.details.purse_requests.age_limit),
      GNUNET_PQ_result_spec_uint32 (
        "flags",
        &td.details.purse_requests.flags),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount_with_fee",
        &td.details.purse_requests.amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "purse_fee",
        &td.details.purse_requests.purse_fee),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_sig",
        &td.details.purse_requests.purse_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with purse_decision table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_purse_decision (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_PURSE_DECISION
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "purse_refunds_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_pub",
        &td.details.purse_decision.purse_pub),
      GNUNET_PQ_result_spec_timestamp (
        "action_timestamp",
        &td.details.purse_decision.action_timestamp),
      GNUNET_PQ_result_spec_bool (
        "refunded",
        &td.details.purse_decision.refunded),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with purse_merges table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_purse_merges (void *cls,
                            PGresult *result,
                            unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_PURSE_MERGES
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "purse_merge_request_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_uint64 (
        "partner_serial_id",
        &td.details.purse_merges.partner_serial_id),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.purse_merges.reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_pub",
        &td.details.purse_merges.purse_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "merge_sig",
        &td.details.purse_merges.merge_sig),
      GNUNET_PQ_result_spec_timestamp (
        "merge_timestamp",
        &td.details.purse_merges.merge_timestamp),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with purse_deposits table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_purse_deposits (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_PURSE_DEPOSITS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "purse_deposit_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_uint64 (
        "partner_serial_id",
        &td.details.purse_deposits.partner_serial_id),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_pub",
        &td.details.purse_deposits.purse_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_pub",
        &td.details.purse_deposits.coin_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount_with_fee",
        &td.details.purse_deposits.amount_with_fee),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_sig",
        &td.details.purse_deposits.coin_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with account_merges table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_account_merges (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_ACCOUNT_MERGES
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "account_merge_request_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.account_merges.reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_sig",
        &td.details.account_merges.reserve_sig),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_pub",
        &td.details.account_merges.purse_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "wallet_h_payto",
        &td.details.account_merges.wallet_h_payto),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with history_requests table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_history_requests (void *cls,
                                PGresult *result,
                                unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_HISTORY_REQUESTS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "history_request_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.history_requests.reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_sig",
        &td.details.history_requests.reserve_sig),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "history_fee",
        &td.details.history_requests.history_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with close_requests table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_close_requests (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_CLOSE_REQUESTS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "close_request_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.close_requests.reserve_pub),
      GNUNET_PQ_result_spec_timestamp (
        "close_timestamp",
        &td.details.close_requests.close_timestamp),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_sig",
        &td.details.close_requests.reserve_sig),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "close",
        &td.details.close_requests.close),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "close_fee",
        &td.details.close_requests.close_fee),
      GNUNET_PQ_result_spec_string (
        "payto_uri",
        &td.details.close_requests.payto_uri),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with wads_out table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_wads_out (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_WADS_OUT
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "wad_out_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "wad_id",
        &td.details.wads_out.wad_id),
      GNUNET_PQ_result_spec_uint64 (
        "partner_serial_id",
        &td.details.wads_out.partner_serial_id),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount",
        &td.details.wads_out.amount),
      GNUNET_PQ_result_spec_timestamp (
        "execution_time",
        &td.details.wads_out.execution_time),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with wads_out_entries table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_wads_out_entries (void *cls,
                                PGresult *result,
                                unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_WADS_OUT_ENTRIES
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "wad_out_entry_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.wads_out_entries.reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_pub",
        &td.details.wads_out_entries.purse_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_contract",
        &td.details.wads_out_entries.h_contract),
      GNUNET_PQ_result_spec_timestamp (
        "purse_expiration",
        &td.details.wads_out_entries.purse_expiration),
      GNUNET_PQ_result_spec_timestamp (
        "merge_timestamp",
        &td.details.wads_out_entries.merge_timestamp),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount_with_fee",
        &td.details.wads_out_entries.amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "wad_fee",
        &td.details.wads_out_entries.wad_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "deposit_fees",
        &td.details.wads_out_entries.deposit_fees),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_sig",
        &td.details.wads_out_entries.reserve_sig),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_sig",
        &td.details.wads_out_entries.purse_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with wads_in table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_wads_in (void *cls,
                       PGresult *result,
                       unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_WADS_IN
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "wad_in_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "wad_id",
        &td.details.wads_in.wad_id),
      GNUNET_PQ_result_spec_string (
        "origin_exchange_url",
        &td.details.wads_in.origin_exchange_url),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount",
        &td.details.wads_in.amount),
      GNUNET_PQ_result_spec_timestamp (
        "arrival_time",
        &td.details.wads_in.arrival_time),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with wads_in_entries table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_wads_in_entries (void *cls,
                               PGresult *result,
                               unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_WADS_IN_ENTRIES
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "wad_in_entry_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.wads_in_entries.reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_pub",
        &td.details.wads_in_entries.purse_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_contract",
        &td.details.wads_in_entries.h_contract),
      GNUNET_PQ_result_spec_timestamp (
        "purse_expiration",
        &td.details.wads_in_entries.purse_expiration),
      GNUNET_PQ_result_spec_timestamp (
        "merge_timestamp",
        &td.details.wads_in_entries.merge_timestamp),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount_with_fee",
        &td.details.wads_in_entries.amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "wad_fee",
        &td.details.wads_in_entries.wad_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "deposit_fees",
        &td.details.wads_in_entries.deposit_fees),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_sig",
        &td.details.wads_in_entries.reserve_sig),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_sig",
        &td.details.wads_in_entries.purse_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with profit_drains table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_profit_drains (void *cls,
                             PGresult *result,
                             unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_PROFIT_DRAINS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "profit_drain_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "wtid",
        &td.details.profit_drains.wtid),
      GNUNET_PQ_result_spec_string (
        "account_section",
        &td.details.profit_drains.account_section),
      GNUNET_PQ_result_spec_string (
        "payto_uri",
        &td.details.profit_drains.payto_uri),
      GNUNET_PQ_result_spec_timestamp (
        "trigger_date",
        &td.details.profit_drains.trigger_date),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount",
        &td.details.profit_drains.amount),
      GNUNET_PQ_result_spec_auto_from_type (
        "master_sig",
        &td.details.profit_drains.master_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with aml_staff table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_aml_staff (void *cls,
                         PGresult *result,
                         unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_AML_STAFF
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "aml_staff_uuid",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "decider_pub",
        &td.details.aml_staff.decider_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "master_sig",
        &td.details.aml_staff.master_sig),
      GNUNET_PQ_result_spec_string (
        "decider_name",
        &td.details.aml_staff.decider_name),
      GNUNET_PQ_result_spec_bool (
        "is_active",
        &td.details.aml_staff.is_active),
      GNUNET_PQ_result_spec_bool (
        "read_only",
        &td.details.aml_staff.read_only),
      GNUNET_PQ_result_spec_timestamp (
        "last_change",
        &td.details.aml_staff.last_change),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with purse_deletion table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_purse_deletion (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_PURSE_DELETION
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "purse_deletion_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_sig",
        &td.details.purse_deletion.purse_sig),
      GNUNET_PQ_result_spec_auto_from_type (
        "purse_pub",
        &td.details.purse_deletion.purse_pub),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with age_withdraw table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_age_withdraw (void *cls,
                            PGresult *result,
                            unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_AGE_WITHDRAW
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "age_withdraw_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_commitment",
        &td.details.age_withdraw.h_commitment),
      GNUNET_PQ_result_spec_uint16 (
        "max_age",
        &td.details.age_withdraw.max_age),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount_with_fee",
        &td.details.age_withdraw.amount_with_fee),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_pub",
        &td.details.age_withdraw.reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "reserve_sig",
        &td.details.age_withdraw.reserve_sig),
      GNUNET_PQ_result_spec_uint32 (
        "noreveal_index",
        &td.details.age_withdraw.noreveal_index),
      /* TODO[oec]: more fields! */
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with legitimization_measures table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_legitimization_measures (void *cls,
                                       PGresult *result,
                                       unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_LEGITIMIZATION_MEASURES
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "access_token",
        &td.details.legitimization_measures.target_token),
      GNUNET_PQ_result_spec_timestamp (
        "start_time",
        &td.details.legitimization_measures.start_time),
      TALER_PQ_result_spec_json (
        "jmeasures",
        &td.details.legitimization_measures.measures),
      GNUNET_PQ_result_spec_uint32 (
        "display_priority",
        &td.details.legitimization_measures.display_priority),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with legitimization_outcomes table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_legitimization_outcomes (void *cls,
                                       PGresult *result,
                                       unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_LEGITIMIZATION_OUTCOMES
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_payto",
        &td.details.legitimization_outcomes.h_payto),
      GNUNET_PQ_result_spec_timestamp (
        "decision_time",
        &td.details.legitimization_outcomes.decision_time),
      GNUNET_PQ_result_spec_timestamp (
        "expiration_time",
        &td.details.legitimization_outcomes.expiration_time),
      TALER_PQ_result_spec_json (
        "jproperties",
        &td.details.legitimization_outcomes.properties),
      GNUNET_PQ_result_spec_bool (
        "to_investigate_id",
        &td.details.legitimization_outcomes.to_investigate),
      TALER_PQ_result_spec_json (
        "jnew_rules",
        &td.details.legitimization_outcomes.new_rules),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with legitimization_processes table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_legitimization_processes (void *cls,
                                        PGresult *result,
                                        unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_LEGITIMIZATION_PROCESSES
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_payto",
        &td.details.legitimization_processes.h_payto),
      GNUNET_PQ_result_spec_timestamp (
        "start_time",
        &td.details.legitimization_processes.start_time),
      GNUNET_PQ_result_spec_timestamp (
        "expiration_time",
        &td.details.legitimization_processes.expiration_time),
      GNUNET_PQ_result_spec_uint64 (
        "legitimization_measure_serial_id",
        &td.details.legitimization_processes.legitimization_measure_serial_id),
      GNUNET_PQ_result_spec_uint32 (
        "measure_index",
        &td.details.legitimization_processes.measure_index),
      GNUNET_PQ_result_spec_string (
        "provider_name",
        &td.details.legitimization_processes.provider_name),
      GNUNET_PQ_result_spec_string (
        "provider_user_id",
        &td.details.legitimization_processes.provider_user_id),
      GNUNET_PQ_result_spec_string (
        "provider_legitimization_id",
        &td.details.legitimization_processes.provider_legitimization_id),
      GNUNET_PQ_result_spec_string (
        "redirect_url",
        &td.details.legitimization_processes.redirect_url),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with kyc_attributes table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_kyc_attributes (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_KYC_ATTRIBUTES
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "kyc_attributes_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_payto",
        &td.details.kyc_attributes.h_payto),
      GNUNET_PQ_result_spec_uint64 (
        "legitimization_serial",
        &td.details.kyc_attributes.legitimization_serial),
      GNUNET_PQ_result_spec_timestamp (
        "collection_time",
        &td.details.kyc_attributes.collection_time),
      GNUNET_PQ_result_spec_timestamp (
        "expiration_time",
        &td.details.kyc_attributes.expiration_time),
      GNUNET_PQ_result_spec_uint64 (
        "trigger_outcome_serial",
        &td.details.kyc_attributes.trigger_outcome_serial),
      GNUNET_PQ_result_spec_variable_size (
        "encrypted_attributes",
        &td.details.kyc_attributes.encrypted_attributes,
        &td.details.kyc_attributes.encrypted_attributes_size),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with aml_history table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_aml_history (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_AML_HISTORY
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "aml_history_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_payto",
        &td.details.aml_history.h_payto),
      GNUNET_PQ_result_spec_uint64 (
        "outcome_serial_id",
        &td.details.aml_history.outcome_serial_id),
      GNUNET_PQ_result_spec_string (
        "justification",
        &td.details.aml_history.justification),
      GNUNET_PQ_result_spec_auto_from_type (
        "decider_pub",
        &td.details.aml_history.decider_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "decider_sig",
        &td.details.aml_history.decider_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with kyc_events table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
lrbt_cb_table_kyc_events (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_KYC_EVENTS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "kyc_event_serial_id",
        &td.serial),
      GNUNET_PQ_result_spec_timestamp (
        "event_timestamp",
        &td.details.kyc_events.event_timestamp),
      GNUNET_PQ_result_spec_string (
        "event_type",
        &td.details.kyc_events.event_type),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->error = true;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Assign statement to @a n and PREPARE
 * @a sql under name @a n.
 */
#define XPREPARE(n,sql) \
        statement = n;        \
        PREPARE (pg, n, sql);


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_records_by_table (void *cls,
                                enum TALER_EXCHANGEDB_ReplicatedTable table,
                                uint64_t serial,
                                TALER_EXCHANGEDB_ReplicationCallback cb,
                                void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial),
    GNUNET_PQ_query_param_end
  };
  struct LookupRecordsByTableContext ctx = {
    .pg = pg,
    .cb = cb,
    .cb_cls = cb_cls
  };
  GNUNET_PQ_PostgresResultHandler rh = NULL;
  const char *statement = NULL;
  enum GNUNET_DB_QueryStatus qs;

  switch (table)
  {
  case TALER_EXCHANGEDB_RT_DENOMINATIONS:
    XPREPARE ("select_above_serial_by_table_denominations",
              "SELECT"
              " denominations_serial AS serial"
              ",denom_type"
              ",denom_pub"
              ",master_sig"
              ",valid_from"
              ",expire_withdraw"
              ",expire_deposit"
              ",expire_legal"
              ",coin"
              ",fee_withdraw"
              ",fee_deposit"
              ",fee_refresh"
              ",fee_refund"
              ",age_mask"
              " FROM denominations"
              " WHERE denominations_serial > $1"
              " ORDER BY denominations_serial ASC;");
    rh = &lrbt_cb_table_denominations;
    break;
  case TALER_EXCHANGEDB_RT_DENOMINATION_REVOCATIONS:
    XPREPARE ("select_above_serial_by_table_denomination_revocations",
              "SELECT"
              " denom_revocations_serial_id AS serial"
              ",master_sig"
              ",denominations_serial"
              " FROM denomination_revocations"
              " WHERE denom_revocations_serial_id > $1"
              " ORDER BY denom_revocations_serial_id ASC;");
    rh = &lrbt_cb_table_denomination_revocations;
    break;
  case TALER_EXCHANGEDB_RT_WIRE_TARGETS:
    XPREPARE ("select_above_serial_by_table_wire_targets",
              "SELECT"
              " wire_target_serial_id AS serial"
              ",access_token"
              ",payto_uri"
              " FROM wire_targets"
              " WHERE wire_target_serial_id > $1"
              " ORDER BY wire_target_serial_id ASC;");
    rh = &lrbt_cb_table_wire_targets;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES:
    XPREPARE ("select_above_serial_by_table_reserves",
              "SELECT"
              " reserve_uuid AS serial"
              ",reserve_pub"
              ",expiration_date"
              ",gc_date"
              " FROM reserves"
              " WHERE reserve_uuid > $1"
              " ORDER BY reserve_uuid ASC;");
    rh = &lrbt_cb_table_reserves;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_IN:
    XPREPARE ("select_above_serial_by_table_reserves_in",
              "SELECT"
              " reserve_in_serial_id AS serial"
              ",reserve_pub"
              ",wire_reference"
              ",credit"
              ",wire_source_h_payto"
              ",exchange_account_section"
              ",execution_date"
              " FROM reserves_in"
              " WHERE reserve_in_serial_id > $1"
              " ORDER BY reserve_in_serial_id ASC;");
    rh = &lrbt_cb_table_reserves_in;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_CLOSE:
    XPREPARE ("select_above_serial_by_table_reserves_close",
              "SELECT"
              " close_uuid AS serial"
              ",reserve_pub"
              ",execution_date"
              ",wtid"
              ",wire_target_h_payto"
              ",amount"
              ",closing_fee"
              " FROM reserves_close"
              " WHERE close_uuid > $1"
              " ORDER BY close_uuid ASC;");
    rh = &lrbt_cb_table_reserves_close;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OPEN_REQUESTS:
    XPREPARE ("select_above_serial_by_table_reserves_open_requests",
              "SELECT"
              " open_request_uuid AS serial"
              ",reserve_pub"
              ",request_timestamp"
              ",expiration_date"
              ",reserve_sig"
              ",reserve_payment"
              ",requested_purse_limit"
              " FROM reserves_open_requests"
              " WHERE open_request_uuid > $1"
              " ORDER BY open_request_uuid ASC;");
    rh = &lrbt_cb_table_reserves_open_requests;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OPEN_DEPOSITS:
    XPREPARE ("select_above_serial_by_table_reserves_open_deposits",
              "SELECT"
              " reserves_open_deposit_uuid AS serial"
              ",reserve_sig"
              ",reserve_pub"
              ",coin_pub"
              ",coin_sig"
              ",contribution"
              " FROM reserves_open_deposits"
              " WHERE reserves_open_deposit_uuid > $1"
              " ORDER BY reserves_open_deposit_uuid ASC;");
    rh = &lrbt_cb_table_reserves_open_deposits;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OUT:
    XPREPARE ("select_above_serial_by_table_reserves_out",
              "SELECT"
              " reserve_out_serial_id AS serial"
              ",h_blind_ev"
              ",denominations_serial"
              ",denom_sig"
              ",reserve_uuid"
              ",reserve_sig"
              ",execution_date"
              ",amount_with_fee"
              " FROM reserves_out"
              " JOIN reserves USING (reserve_uuid)"
              " WHERE reserve_out_serial_id > $1"
              " ORDER BY reserve_out_serial_id ASC;");
    rh = &lrbt_cb_table_reserves_out;
    break;
  case TALER_EXCHANGEDB_RT_AUDITORS:
    XPREPARE ("select_above_serial_by_table_auditors",
              "SELECT"
              " auditor_uuid AS serial"
              ",auditor_pub"
              ",auditor_name"
              ",auditor_url"
              ",is_active"
              ",last_change"
              " FROM auditors"
              " WHERE auditor_uuid > $1"
              " ORDER BY auditor_uuid ASC;");
    rh = &lrbt_cb_table_auditors;
    break;
  case TALER_EXCHANGEDB_RT_AUDITOR_DENOM_SIGS:
    XPREPARE ("select_above_serial_by_table_auditor_denom_sigs",
              "SELECT"
              " auditor_denom_serial AS serial"
              ",auditor_uuid"
              ",denominations_serial"
              ",auditor_sig"
              " FROM auditor_denom_sigs"
              " WHERE auditor_denom_serial > $1"
              " ORDER BY auditor_denom_serial ASC;");
    rh = &lrbt_cb_table_auditor_denom_sigs;
    break;
  case TALER_EXCHANGEDB_RT_EXCHANGE_SIGN_KEYS:
    XPREPARE ("select_above_serial_by_table_exchange_sign_keys",
              "SELECT"
              " esk_serial AS serial"
              ",exchange_pub"
              ",master_sig"
              ",valid_from"
              ",expire_sign"
              ",expire_legal"
              " FROM exchange_sign_keys"
              " WHERE esk_serial > $1"
              " ORDER BY esk_serial ASC;");
    rh = &lrbt_cb_table_exchange_sign_keys;
    break;
  case TALER_EXCHANGEDB_RT_SIGNKEY_REVOCATIONS:
    XPREPARE ("select_above_serial_by_table_signkey_revocations",
              "SELECT"
              " signkey_revocations_serial_id AS serial"
              ",esk_serial"
              ",master_sig"
              " FROM signkey_revocations"
              " WHERE signkey_revocations_serial_id > $1"
              " ORDER BY signkey_revocations_serial_id ASC;");
    rh = &lrbt_cb_table_signkey_revocations;
    break;
  case TALER_EXCHANGEDB_RT_KNOWN_COINS:
    XPREPARE ("select_above_serial_by_table_known_coins",
              "SELECT"
              " known_coin_id AS serial"
              ",coin_pub"
              ",denom_sig"
              ",denominations_serial"
              " FROM known_coins"
              " WHERE known_coin_id > $1"
              " ORDER BY known_coin_id ASC;");
    rh = &lrbt_cb_table_known_coins;
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_COMMITMENTS:
    XPREPARE ("select_above_serial_by_table_refresh_commitments",
              "SELECT"
              " melt_serial_id AS serial"
              ",rc"
              ",old_coin_sig"
              ",amount_with_fee"
              ",noreveal_index"
              ",old_coin_pub"
              " FROM refresh_commitments"
              " WHERE melt_serial_id > $1"
              " ORDER BY melt_serial_id ASC;");
    rh = &lrbt_cb_table_refresh_commitments;
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_REVEALED_COINS:
    XPREPARE ("select_above_serial_by_table_refresh_revealed_coins",
              "SELECT"
              " rrc_serial AS serial"
              ",freshcoin_index"
              ",link_sig"
              ",coin_ev"
              ",ev_sig"
              ",ewv"
              ",denominations_serial"
              ",melt_serial_id"
              " FROM refresh_revealed_coins"
              " WHERE rrc_serial > $1"
              " ORDER BY rrc_serial ASC;");
    rh = &lrbt_cb_table_refresh_revealed_coins;
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_TRANSFER_KEYS:
    XPREPARE ("select_above_serial_by_table_refresh_transfer_keys",
              "SELECT"
              " rtc_serial AS serial"
              ",transfer_pub"
              ",transfer_privs"
              ",melt_serial_id"
              " FROM refresh_transfer_keys"
              " WHERE rtc_serial > $1"
              " ORDER BY rtc_serial ASC;");
    rh = &lrbt_cb_table_refresh_transfer_keys;
    break;
  case TALER_EXCHANGEDB_RT_BATCH_DEPOSITS:
    XPREPARE ("select_above_serial_by_table_batch_deposits",
              "SELECT"
              " batch_deposit_serial_id AS serial"
              ",shard"
              ",merchant_pub"
              ",wallet_timestamp"
              ",exchange_timestamp"
              ",refund_deadline"
              ",wire_deadline"
              ",h_contract_terms"
              ",wallet_data_hash"
              ",wire_salt"
              ",wire_target_h_payto"
              ",done"
              ",policy_blocked"
              ",policy_details_serial_id"
              " FROM batch_deposits"
              " WHERE batch_deposit_serial_id > $1"
              " ORDER BY batch_deposit_serial_id ASC;");
    rh = &lrbt_cb_table_batch_deposits;
    break;
  case TALER_EXCHANGEDB_RT_COIN_DEPOSITS:
    XPREPARE ("select_above_serial_by_table_coin_deposits",
              "SELECT"
              " coin_deposit_serial_id AS serial"
              ",batch_deposit_serial_id"
              ",coin_pub"
              ",coin_sig"
              ",amount_with_fee"
              " FROM coin_deposits"
              " WHERE coin_deposit_serial_id > $1"
              " ORDER BY coin_deposit_serial_id ASC;");
    rh = &lrbt_cb_table_coin_deposits;
    break;
  case TALER_EXCHANGEDB_RT_REFUNDS:
    XPREPARE ("select_above_serial_by_table_refunds",
              "SELECT"
              " refund_serial_id AS serial"
              ",coin_pub"
              ",merchant_sig"
              ",rtransaction_id"
              ",amount_with_fee"
              ",batch_deposit_serial_id"
              " FROM refunds"
              " WHERE refund_serial_id > $1"
              " ORDER BY refund_serial_id ASC;");
    rh = &lrbt_cb_table_refunds;
    break;
  case TALER_EXCHANGEDB_RT_WIRE_OUT:
    XPREPARE ("select_above_serial_by_table_wire_out",
              "SELECT"
              " wireout_uuid AS serial"
              ",execution_date"
              ",wtid_raw"
              ",wire_target_h_payto"
              ",exchange_account_section"
              ",amount"
              " FROM wire_out"
              " WHERE wireout_uuid > $1"
              " ORDER BY wireout_uuid ASC;");
    rh = &lrbt_cb_table_wire_out;
    break;
  case TALER_EXCHANGEDB_RT_AGGREGATION_TRACKING:
    XPREPARE ("select_above_serial_by_table_aggregation_tracking",
              "SELECT"
              " aggregation_serial_id AS serial"
              ",batch_deposit_serial_id"
              ",wtid_raw"
              " FROM aggregation_tracking"
              " WHERE aggregation_serial_id > $1"
              " ORDER BY aggregation_serial_id ASC;");
    rh = &lrbt_cb_table_aggregation_tracking;
    break;
  case TALER_EXCHANGEDB_RT_WIRE_FEE:
    XPREPARE ("select_above_serial_by_table_wire_fee",
              "SELECT"
              " wire_fee_serial AS serial"
              ",wire_method"
              ",start_date"
              ",end_date"
              ",wire_fee"
              ",closing_fee"
              ",master_sig"
              " FROM wire_fee"
              " WHERE wire_fee_serial > $1"
              " ORDER BY wire_fee_serial ASC;");
    rh = &lrbt_cb_table_wire_fee;
    break;
  case TALER_EXCHANGEDB_RT_GLOBAL_FEE:
    XPREPARE ("select_above_serial_by_table_global_fee",
              "SELECT"
              " global_fee_serial AS serial"
              ",start_date"
              ",end_date"
              ",history_fee"
              ",account_fee"
              ",purse_fee"
              ",purse_timeout"
              ",history_expiration"
              ",purse_account_limit"
              ",master_sig"
              " FROM global_fee"
              " WHERE global_fee_serial > $1"
              " ORDER BY global_fee_serial ASC;");
    rh = &lrbt_cb_table_global_fee;
    break;
  case TALER_EXCHANGEDB_RT_RECOUP:
    XPREPARE ("select_above_serial_by_table_recoup",
              "SELECT"
              " recoup_uuid AS serial"
              ",coin_sig"
              ",coin_blind"
              ",amount"
              ",recoup_timestamp"
              ",coin_pub"
              ",reserve_out_serial_id"
              " FROM recoup"
              " WHERE recoup_uuid > $1"
              " ORDER BY recoup_uuid ASC;");
    rh = &lrbt_cb_table_recoup;
    break;
  case TALER_EXCHANGEDB_RT_RECOUP_REFRESH:
    XPREPARE ("select_above_serial_by_table_recoup_refresh",
              "SELECT"
              " recoup_refresh_uuid AS serial"
              ",coin_sig"
              ",coin_blind"
              ",amount"
              ",recoup_timestamp"
              ",coin_pub"
              ",known_coin_id"
              ",rrc_serial"
              " FROM recoup_refresh"
              " WHERE recoup_refresh_uuid > $1"
              " ORDER BY recoup_refresh_uuid ASC;");
    rh = &lrbt_cb_table_recoup_refresh;
    break;
  case TALER_EXCHANGEDB_RT_EXTENSIONS:
    statement = "select_above_serial_by_table_extensions";
    rh = &lrbt_cb_table_extensions;
    break;
  case TALER_EXCHANGEDB_RT_POLICY_DETAILS:
    statement = "select_above_serial_by_table_policy_details";
    rh = &lrbt_cb_table_policy_details;
    break;
  case TALER_EXCHANGEDB_RT_POLICY_FULFILLMENTS:
    statement = "select_above_serial_by_table_policy_fulfillments";
    rh = &lrbt_cb_table_policy_fulfillments;
    break;
  case TALER_EXCHANGEDB_RT_PURSE_REQUESTS:
    XPREPARE ("select_above_serial_by_table_purse_requests",
              "SELECT"
              " purse_requests_serial_id"
              ",purse_pub"
              ",merge_pub"
              ",purse_creation"
              ",purse_expiration"
              ",h_contract_terms"
              ",age_limit"
              ",flags"
              ",amount_with_fee"
              ",purse_fee"
              ",purse_sig"
              " FROM purse_requests"
              " WHERE purse_requests_serial_id > $1"
              " ORDER BY purse_requests_serial_id ASC;");
    rh = &lrbt_cb_table_purse_requests;
    break;
  case TALER_EXCHANGEDB_RT_PURSE_DECISION:
    XPREPARE ("select_above_serial_by_table_purse_decision",
              "SELECT"
              " purse_decision_serial_id"
              ",action_timestamp"
              ",refunded"
              ",purse_pub"
              " FROM purse_decision"
              " WHERE purse_decision_serial_id > $1"
              " ORDER BY purse_decision_serial_id ASC;");
    rh = &lrbt_cb_table_purse_decision;
    break;
  case TALER_EXCHANGEDB_RT_PURSE_MERGES:
    XPREPARE ("select_above_serial_by_table_purse_merges",
              "SELECT"
              " purse_merge_request_serial_id"
              ",partner_serial_id"
              ",reserve_pub"
              ",purse_pub"
              ",merge_sig"
              ",merge_timestamp"
              " FROM purse_merges"
              " WHERE purse_merge_request_serial_id > $1"
              " ORDER BY purse_merge_request_serial_id ASC;");
    rh = &lrbt_cb_table_purse_merges;
    break;
  case TALER_EXCHANGEDB_RT_PURSE_DEPOSITS:
    XPREPARE ("select_above_serial_by_table_purse_deposits",
              "SELECT"
              " purse_deposit_serial_id"
              ",partner_serial_id"
              ",purse_pub"
              ",coin_pub"
              ",amount_with_fee"
              ",coin_sig"
              " FROM purse_deposits"
              " WHERE purse_deposit_serial_id > $1"
              " ORDER BY purse_deposit_serial_id ASC;");
    rh = &lrbt_cb_table_purse_deposits;
    break;
  case TALER_EXCHANGEDB_RT_ACCOUNT_MERGES:
    XPREPARE ("select_above_serial_by_table_account_merges",
              "SELECT"
              " account_merge_request_serial_id"
              ",reserve_pub"
              ",reserve_sig"
              ",purse_pub"
              ",wallet_h_payto"
              " FROM account_merges"
              " WHERE account_merge_request_serial_id > $1"
              " ORDER BY account_merge_request_serial_id ASC;");
    rh = &lrbt_cb_table_account_merges;
    break;
  case TALER_EXCHANGEDB_RT_HISTORY_REQUESTS:
    XPREPARE ("select_above_serial_by_table_history_requests",
              "SELECT"
              " history_request_serial_id"
              ",reserve_pub"
              ",request_timestamp"
              ",reserve_sig"
              ",history_fee"
              " FROM history_requests"
              " WHERE history_request_serial_id > $1"
              " ORDER BY history_request_serial_id ASC;");
    rh = &lrbt_cb_table_history_requests;
    break;
  case TALER_EXCHANGEDB_RT_CLOSE_REQUESTS:
    XPREPARE ("select_above_serial_by_table_close_requests",
              "SELECT"
              " close_request_serial_id"
              ",reserve_pub"
              ",close_timestamp"
              ",reserve_sig"
              ",close"
              " FROM close_requests"
              " WHERE close_request_serial_id > $1"
              " ORDER BY close_request_serial_id ASC;");
    rh = &lrbt_cb_table_close_requests;
    break;
  case TALER_EXCHANGEDB_RT_WADS_OUT:
    XPREPARE ("select_above_serial_by_table_wads_out",
              "SELECT"
              " wad_out_serial_id"
              ",wad_id"
              ",partner_serial_id"
              ",amount"
              ",execution_time"
              " FROM wads_out"
              " WHERE wad_out_serial_id > $1"
              " ORDER BY wad_out_serial_id ASC;");
    rh = &lrbt_cb_table_wads_out;
    break;
  case TALER_EXCHANGEDB_RT_WADS_OUT_ENTRIES:
    XPREPARE ("select_above_serial_by_table_wads_out_entries",
              "SELECT"
              " wad_out_entry_serial_id"
              ",reserve_pub"
              ",purse_pub"
              ",h_contract"
              ",purse_expiration"
              ",merge_timestamp"
              ",amount_with_fee"
              ",wad_fee"
              ",deposit_fees"
              ",reserve_sig"
              ",purse_sig"
              " FROM wad_out_entries"
              " WHERE wad_out_entry_serial_id > $1"
              " ORDER BY wad_out_entry_serial_id ASC;");
    rh = &lrbt_cb_table_wads_out_entries;
    break;
  case TALER_EXCHANGEDB_RT_WADS_IN:
    XPREPARE ("select_above_serial_by_table_wads_in",
              "SELECT"
              " wad_in_serial_id"
              ",wad_id"
              ",origin_exchange_url"
              ",amount"
              ",arrival_time"
              " FROM wads_in"
              " WHERE wad_in_serial_id > $1"
              " ORDER BY wad_in_serial_id ASC;");
    rh = &lrbt_cb_table_wads_in;
    break;
  case TALER_EXCHANGEDB_RT_WADS_IN_ENTRIES:
    XPREPARE ("select_above_serial_by_table_wads_in_entries",
              "SELECT"
              " wad_in_entry_serial_id"
              ",reserve_pub"
              ",purse_pub"
              ",h_contract"
              ",purse_expiration"
              ",merge_timestamp"
              ",amount_with_fee"
              ",wad_fee"
              ",deposit_fees"
              ",reserve_sig"
              ",purse_sig"
              " FROM wad_in_entries"
              " WHERE wad_in_entry_serial_id > $1"
              " ORDER BY wad_in_entry_serial_id ASC;");
    rh = &lrbt_cb_table_wads_in_entries;
    break;
  case TALER_EXCHANGEDB_RT_PROFIT_DRAINS:
    XPREPARE ("select_above_serial_by_table_profit_drains",
              "SELECT"
              " profit_drain_serial_id"
              ",wtid"
              ",account_section"
              ",payto_uri"
              ",trigger_date"
              ",amount"
              ",master_sig"
              " FROM profit_drains"
              " WHERE profit_drain_serial_id > $1"
              " ORDER BY profit_drain_serial_id ASC;");
    rh = &lrbt_cb_table_profit_drains;
    break;

  case TALER_EXCHANGEDB_RT_AML_STAFF:
    XPREPARE ("select_above_serial_by_table_aml_staff",
              "SELECT"
              " aml_staff_uuid"
              ",decider_pub"
              ",master_sig"
              ",decider_name"
              ",is_active"
              ",read_only"
              ",last_change"
              " FROM aml_staff"
              " WHERE aml_staff_uuid > $1"
              " ORDER BY aml_staff_uuid ASC;");
    rh = &lrbt_cb_table_aml_staff;
    break;
  case TALER_EXCHANGEDB_RT_PURSE_DELETION:
    XPREPARE ("select_above_serial_by_table_purse_deletion",
              "SELECT"
              " purse_deletion_serial_id"
              ",purse_pub"
              ",purse_sig"
              " FROM purse_deletion"
              " WHERE purse_deletion_serial_id > $1"
              " ORDER BY purse_deletion_serial_id ASC;");
    rh = &lrbt_cb_table_purse_deletion;
    break;
  case TALER_EXCHANGEDB_RT_AGE_WITHDRAW:
    XPREPARE ("select_above_serial_by_table_age_withdraw",
              "SELECT"
              " age_withdraw_id"
              ",h_commitment"
              ",amount_with_fee"
              ",max_age"
              ",reserve_pub"
              ",reserve_sig"
              ",noreveal_index"
              " FROM age_withdraw"
              " WHERE age_withdraw_id > $1"
              " ORDER BY age_withdraw_id ASC;");
    /* TODO[oec]: MORE FIELDS! */
    rh = &lrbt_cb_table_age_withdraw;
    break;
  case TALER_EXCHANGEDB_RT_LEGITIMIZATION_MEASURES:
    XPREPARE ("select_above_serial_by_table_legitimization_measures",
              "SELECT"
              " legitimization_measure_serial_id AS serial"
              ",access_token"
              ",start_time"
              ",jmeasures"
              ",display_priority"
              " FROM legitimization_measures"
              " WHERE legitimization_measure_serial_id > $1"
              " ORDER BY legitimization_measure_serial_id ASC;");
    rh = &lrbt_cb_table_legitimization_measures;
    break;
  case TALER_EXCHANGEDB_RT_LEGITIMIZATION_OUTCOMES:
    XPREPARE ("select_above_serial_by_table_legitimization_outcomes",
              "SELECT"
              " outcome_serial_id AS serial"
              ",h_payto"
              ",decision_time"
              ",expiration_time"
              ",jproperties"
              ",to_investigate"
              ",jnew_rules"
              " FROM legitimization_outcomes"
              " WHERE outcome_serial_id > $1"
              " ORDER BY outcome_serial_id ASC;");
    rh = &lrbt_cb_table_legitimization_outcomes;
    break;
  case TALER_EXCHANGEDB_RT_LEGITIMIZATION_PROCESSES:
    XPREPARE ("select_above_serial_by_table_legitimization_processes",
              "SELECT"
              " legitimization_process_serial_id AS serial"
              ",h_payto"
              ",start_time"
              ",expiration_time"
              ",legitimization_measure_serial_id"
              ",measure_index"
              ",provider_name"
              ",provider_user_id"
              ",provider_legitimization_id"
              ",redirect_url"
              " FROM legitimization_processes"
              " WHERE legitimization_process_serial_id > $1"
              " ORDER BY legitimization_process_serial_id ASC;");
    rh = &lrbt_cb_table_legitimization_processes;
    break;
  case TALER_EXCHANGEDB_RT_KYC_ATTRIBUTES:
    XPREPARE ("select_above_serial_by_table_kyc_attributes",
              "SELECT"
              " kyc_attributes_serial_id"
              ",h_payto"
              ",legitimization_serial"
              ",collection_time"
              ",expiration_time"
              ",trigger_outcome_serial"
              ",encrypted_attributes"
              " FROM kyc_attributes"
              " WHERE kyc_attributes_serial_id > $1"
              " ORDER BY kyc_attributes_serial_id ASC;");
    rh = &lrbt_cb_table_kyc_attributes;
    break;
  case TALER_EXCHANGEDB_RT_AML_HISTORY:
    XPREPARE ("select_above_serial_by_table_aml_history",
              "SELECT"
              " aml_history_serial_id"
              ",h_payto"
              ",outcome_serial_id"
              ",justification"
              ",decider_pub"
              ",decider_sig"
              " FROM aml_history"
              " WHERE aml_history_serial_id > $1"
              " ORDER BY aml_history_serial_id ASC;");
    rh = &lrbt_cb_table_aml_history;
    break;
  case TALER_EXCHANGEDB_RT_KYC_EVENTS:
    XPREPARE ("select_above_serial_by_table_kyc_events",
              "SELECT"
              " kyc_event_serial_id AS serial"
              ",event_timestamp"
              ",event_type"
              " FROM kyc_events"
              " WHERE kyc_event_serial_id > $1"
              " ORDER BY kyc_event_serial_id ASC;");
    rh = &lrbt_cb_table_kyc_events;
    break;
  }
  if (NULL == rh)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             statement,
                                             params,
                                             rh,
                                             &ctx);
  if (qs < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to run `%s'\n",
                statement);
    return qs;
  }
  if (ctx.error)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


#undef XPREPARE

/* end of pg_lookup_records_by_table.c */
