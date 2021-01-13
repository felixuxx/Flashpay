/*
   This file is part of GNUnet
   Copyright (C) 2020 Taler Systems SA

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
 * @file exchangedb/lrbt_callbacks.c
 * @brief callbacks used by postgres_lookup_records_by_table, to be
 *        inlined into the plugin
 * @author Christian Grothoff
 */


/**
 * Function called with denominations table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_result the number of results in @a result
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
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_rsa_public_key (
        "denom_pub",
        &td.details.denominations.denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &td.details.denominations.master_sig),
      TALER_PQ_result_spec_absolute_time ("valid_from",
                                          &td.details.denominations.valid_from),
      TALER_PQ_result_spec_absolute_time ("expire_withdraw",
                                          &td.details.denominations.
                                          expire_withdraw),
      TALER_PQ_result_spec_absolute_time ("expire_deposit",
                                          &td.details.denominations.
                                          expire_deposit),
      TALER_PQ_result_spec_absolute_time ("expire_legal",
                                          &td.details.denominations.expire_legal),
      TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                   &td.details.denominations.coin),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                   &td.details.denominations.fee_withdraw),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   &td.details.denominations.fee_deposit),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                   &td.details.denominations.fee_refresh),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                   &td.details.denominations.fee_refund),
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
 * @param num_result the number of results in @a result
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
 * Function called with reserves table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
lrbt_cb_table_reserves (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
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
      GNUNET_PQ_result_spec_string ("account_details",
                                    &td.details.reserves.account_details),
      TALER_PQ_RESULT_SPEC_AMOUNT ("current_balance",
                                   &td.details.reserves.current_balance),
      TALER_PQ_result_spec_absolute_time ("expiration_date",
                                          &td.details.reserves.expiration_date),
      TALER_PQ_result_spec_absolute_time ("gc_date",
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
 * @param num_result the number of results in @a result
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
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_uint64 ("wire_reference",
                                    &td.details.reserves_in.wire_reference),
      TALER_PQ_RESULT_SPEC_AMOUNT ("credit",
                                   &td.details.reserves_in.credit),
      GNUNET_PQ_result_spec_string ("sender_account_details",
                                    &td.details.reserves_in.
                                    sender_account_details),
      GNUNET_PQ_result_spec_string ("exchange_account_section",
                                    &td.details.reserves_in.
                                    exchange_account_section),
      TALER_PQ_result_spec_absolute_time ("execution_date",
                                          &td.details.reserves_in.execution_date),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid",
                                    &td.details.reserves_in.reserve_uuid),
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
 * @param num_result the number of results in @a result
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
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      TALER_PQ_result_spec_absolute_time (
        "execution_date",
        &td.details.reserves_close.execution_date),
      GNUNET_PQ_result_spec_auto_from_type ("wtid",
                                            &td.details.reserves_close.wtid),
      GNUNET_PQ_result_spec_string (
        "receiver_account",
        &td.details.reserves_close.receiver_account),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &td.details.reserves_close.amount),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &td.details.reserves_close.closing_fee),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid",
                                    &td.details.reserves_close.reserve_uuid),

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
 * @param num_result the number of results in @a result
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
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &td.details.reserves_out.h_blind_ev),
      GNUNET_PQ_result_spec_rsa_signature (
        "denom_sig",
        &td.details.reserves_out.denom_sig.rsa_signature),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                            &td.details.reserves_out.reserve_sig),
      TALER_PQ_result_spec_absolute_time (
        "execution_date",
        &td.details.reserves_out.execution_date),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &td.details.reserves_out.amount_with_fee),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid",
                                    &td.details.reserves_out.reserve_uuid),
      GNUNET_PQ_result_spec_uint64 ("denominations_serial",
                                    &td.details.reserves_out.
                                    denominations_serial),
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
 * @param num_result the number of results in @a result
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
    uint8_t is_active8 = 0;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("auditor_pub",
                                            &td.details.auditors.auditor_pub),
      GNUNET_PQ_result_spec_string ("auditor_url",
                                    &td.details.auditors.auditor_url),
      GNUNET_PQ_result_spec_string ("auditor_name",
                                    &td.details.auditors.auditor_name),
      GNUNET_PQ_result_spec_auto_from_type ("is_active",
                                            &is_active8),
      TALER_PQ_result_spec_absolute_time ("last_change",
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
    td.details.auditors.is_active = (0 != is_active8);
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
 * @param num_result the number of results in @a result
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
 * @param num_result the number of results in @a result
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
      TALER_PQ_result_spec_absolute_time ("valid_from",
                                          &td.details.exchange_sign_keys.meta.
                                          start),
      TALER_PQ_result_spec_absolute_time ("expire_sign",
                                          &td.details.exchange_sign_keys.meta.
                                          expire_sign),
      TALER_PQ_result_spec_absolute_time ("expire_legal",
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
 * @param num_result the number of results in @a result
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
 * @param num_result the number of results in @a result
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
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &td.details.known_coins.coin_pub),
      GNUNET_PQ_result_spec_rsa_signature (
        "denom_sig",
        &td.details.known_coins.denom_sig.rsa_signature),
      GNUNET_PQ_result_spec_uint64 ("denominations_serial",
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
 * @param num_result the number of results in @a result
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
      GNUNET_PQ_result_spec_uint64 (
        "old_known_coin_id",
        &td.details.refresh_commitments.old_known_coin_id),
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
 * @param num_result the number of results in @a result
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
      GNUNET_PQ_result_spec_rsa_signature (
        "ev_sig",
        &td.details.refresh_revealed_coins.ev_sig.rsa_signature),
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
 * @param num_result the number of results in @a result
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
                                            &td.details.refresh_transfer_keys.tp),
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
    memcpy (&td.details.refresh_transfer_keys.tprivs[0],
            tpriv,
            tpriv_size);
    ctx->cb (ctx->cb_cls,
             &td);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called with deposits table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
lrbt_cb_table_deposits (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_DEPOSITS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint8_t tiny = 0; /* initialized to make compiler happy */
    uint8_t done = 0; /* initialized to make compiler happy */
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 (
        "serial",
        &td.serial),
      TALER_PQ_RESULT_SPEC_AMOUNT (
        "amount_with_fee",
        &td.details.deposits.amount_with_fee),
      TALER_PQ_result_spec_absolute_time (
        "wallet_timestamp",
        &td.details.deposits.wallet_timestamp),
      TALER_PQ_result_spec_absolute_time (
        "exchange_timestamp",
        &td.details.deposits.exchange_timestamp),
      TALER_PQ_result_spec_absolute_time (
        "refund_deadline",
        &td.details.deposits.refund_deadline),
      TALER_PQ_result_spec_absolute_time (
        "wire_deadline",
        &td.details.deposits.wire_deadline),
      GNUNET_PQ_result_spec_auto_from_type (
        "merchant_pub",
        &td.details.deposits.merchant_pub),
      GNUNET_PQ_result_spec_auto_from_type (
        "h_contract_terms",
        &td.details.deposits.h_contract_terms),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_sig",
        &td.details.deposits.coin_sig),
      TALER_PQ_result_spec_json (
        "wire",
        &td.details.deposits.wire),
      GNUNET_PQ_result_spec_auto_from_type (
        "tiny",
        &td.details.deposits.tiny),
      GNUNET_PQ_result_spec_auto_from_type (
        "done",
        &td.details.deposits.done),
      GNUNET_PQ_result_spec_uint64 (
        "known_coin_id",
        &td.details.deposits.known_coin_id),
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
    td.details.deposits.tiny = (0 != tiny);
    td.details.deposits.done = (0 != done);
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
 * @param num_result the number of results in @a result
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
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_sig",
                                            &td.details.refunds.merchant_sig),
      GNUNET_PQ_result_spec_uint64 ("rtransaction_id",
                                    &td.details.refunds.rtransaction_id),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &td.details.refunds.amount_with_fee),
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &td.details.refunds.deposit_serial_id),
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
 * @param num_result the number of results in @a result
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
      TALER_PQ_result_spec_absolute_time ("execution_date",
                                          &td.details.wire_out.execution_date),
      GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                            &td.details.wire_out.wtid_raw),
      TALER_PQ_result_spec_json ("wire_target",
                                 &td.details.wire_out.wire_target),
      GNUNET_PQ_result_spec_string (
        "exchnage_account_section",
        &td.details.wire_out.exchange_account_section),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
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
 * @param num_result the number of results in @a result
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
      GNUNET_PQ_result_spec_uint64 ("serial",
                                    &td.serial),
      GNUNET_PQ_result_spec_uint64 (
        "deposit_serial_id",
        &td.details.aggregation_tracking.deposit_serial_id),
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
 * @param num_result the number of results in @a result
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
      TALER_PQ_result_spec_absolute_time ("start_date",
                                          &td.details.wire_fee.start_date),
      TALER_PQ_result_spec_absolute_time ("end_date",
                                          &td.details.wire_fee.end_date),
      TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee",
                                   &td.details.wire_fee.wire_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &td.details.wire_fee.closing_fee),
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
 * Function called with recoup table entries.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_result the number of results in @a result
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
      TALER_PQ_result_spec_absolute_time ("timestamp",
                                          &td.details.recoup.timestamp),
      GNUNET_PQ_result_spec_uint64 ("known_coin_id",
                                    &td.details.recoup.known_coin_id),
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
 * @param num_result the number of results in @a result
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
                                            &td.details.recoup_refresh.coin_sig),
      GNUNET_PQ_result_spec_auto_from_type (
        "coin_blind",
        &td.details.recoup_refresh.coin_blind),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &td.details.recoup_refresh.amount),
      TALER_PQ_result_spec_absolute_time ("timestamp",
                                          &td.details.recoup_refresh.timestamp),
      GNUNET_PQ_result_spec_uint64 ("known_coin_id",
                                    &td.details.recoup_refresh.known_coin_id),
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


/* end of lrbt_callbacks.c */
