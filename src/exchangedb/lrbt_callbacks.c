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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_DENOMINATIONS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RESERVES
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RESERVES_IN
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RESERVES_CLOSE
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RESERVES_OUT
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
    struct GNUNET_PQ_ResultSpec rs[] = {
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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_REFRESH_COMMITMENTS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
    struct GNUNET_PQ_ResultSpec rs[] = {
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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_DEPOSITS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
 * @param num_result the number of results in @a result
 */
static void
lrbt_cb_table_refunds (void *cls,
                       PGresult *result,
                       unsigned int num_results)
{
  struct LookupRecordsByTableContext *ctx = cls;
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_REFUNDS
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_WIRE_OUT
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_WIRE_FEE
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RECOUP
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
  struct TALER_EXCHANGEDB_TableData td = {
    .table = TALER_EXCHANGEDB_RT_RECOUP_REFRESH
  };

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
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
