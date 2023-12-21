/*
  This file is part of TALER
  Copyright (C) 2014-2017, 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_db.c
 * @brief Generic database operations for the exchange.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_db_lib.h>
#include <pthread.h>
#include <jansson.h>
#include <gnunet/gnunet_json_lib.h>
#include "taler_error_codes.h"
#include "taler_exchangedb_plugin.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_db.h"
#include "taler-exchange-httpd_responses.h"


enum GNUNET_DB_QueryStatus
TEH_make_coin_known (const struct TALER_CoinPublicInfo *coin,
                     struct MHD_Connection *connection,
                     uint64_t *known_coin_id,
                     MHD_RESULT *mhd_ret)
{
  enum TALER_EXCHANGEDB_CoinKnownStatus cks;
  struct TALER_DenominationHashP h_denom_pub;
  struct TALER_AgeCommitmentHash h_age_commitment = {{{0}}};

  /* make sure coin is 'known' in database */
  cks = TEH_plugin->ensure_coin_known (TEH_plugin->cls,
                                       coin,
                                       known_coin_id,
                                       &h_denom_pub,
                                       &h_age_commitment);
  switch (cks)
  {
  case TALER_EXCHANGEDB_CKS_ADDED:
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  case TALER_EXCHANGEDB_CKS_PRESENT:
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  case TALER_EXCHANGEDB_CKS_SOFT_FAIL:
    return GNUNET_DB_STATUS_SOFT_ERROR;
  case TALER_EXCHANGEDB_CKS_HARD_FAIL:
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_STORE_FAILED,
                                    NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  case TALER_EXCHANGEDB_CKS_DENOM_CONFLICT:
    /* The exchange has a seen this coin before, but with a different denomination.
     * Get the corresponding signature and sent it to the client as proof */
    {
      struct conflict
      {
        struct TALER_DenominationPublicKey pub;
        struct TALER_DenominationSignature sig;
      } conflict = {0};

      if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          TEH_plugin->get_signature_for_known_coin (TEH_plugin->cls,
                                                    &coin->coin_pub,
                                                    &conflict.pub,
                                                    &conflict.sig))
      {
        /* There _should_ have been a result, because
         * we ended here due to a conflict! */
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               NULL);
        return GNUNET_DB_STATUS_HARD_ERROR;
      }

      *mhd_ret = TEH_RESPONSE_reply_coin_denomination_conflict (
        connection,
        TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_DENOMINATION_KEY,
        &coin->coin_pub,
        &conflict.pub,
        &conflict.sig);

      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  case TALER_EXCHANGEDB_CKS_AGE_CONFLICT_EXPECTED_NULL:
  case TALER_EXCHANGEDB_CKS_AGE_CONFLICT_EXPECTED_NON_NULL:
  case TALER_EXCHANGEDB_CKS_AGE_CONFLICT_VALUE_DIFFERS:
    *mhd_ret = TEH_RESPONSE_reply_coin_age_commitment_conflict (
      connection,
      TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_AGE_HASH,
      cks,
      &h_denom_pub,
      &coin->coin_pub,
      &h_age_commitment);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_assert (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


enum GNUNET_GenericReturnValue
TEH_DB_run_transaction (struct MHD_Connection *connection,
                        const char *name,
                        enum TEH_MetricTypeRequest mt,
                        MHD_RESULT *mhd_ret,
                        TEH_DB_TransactionCallback cb,
                        void *cb_cls)
{
  if (NULL != mhd_ret)
    *mhd_ret = -1; /* set to invalid value, to help detect bugs */
  if (GNUNET_OK !=
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    GNUNET_break (0);
    if (NULL != mhd_ret)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_SETUP_FAILED,
                                             NULL);
    return GNUNET_SYSERR;
  }
  GNUNET_assert (mt < TEH_MT_REQUEST_COUNT);
  TEH_METRICS_num_requests[mt]++;
  for (unsigned int retries = 0;
       retries < MAX_TRANSACTION_COMMIT_RETRIES;
       retries++)
  {
    enum GNUNET_DB_QueryStatus qs;

    if (GNUNET_OK !=
        TEH_plugin->start (TEH_plugin->cls,
                           name))
    {
      GNUNET_break (0);
      if (NULL != mhd_ret)
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_START_FAILED,
                                               NULL);
      return GNUNET_SYSERR;
    }
    qs = cb (cb_cls,
             connection,
             mhd_ret);
    if (0 > qs)
    {
      TEH_plugin->rollback (TEH_plugin->cls);
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
        return GNUNET_SYSERR;
    }
    else
    {
      qs = TEH_plugin->commit (TEH_plugin->cls);
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      {
        TEH_plugin->rollback (TEH_plugin->cls);
        if (NULL != mhd_ret)
          *mhd_ret = TALER_MHD_reply_with_error (connection,
                                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                                 TALER_EC_GENERIC_DB_COMMIT_FAILED,
                                                 NULL);
        return GNUNET_SYSERR;
      }
      if (0 > qs)
        TEH_plugin->rollback (TEH_plugin->cls);
    }
    /* make sure callback did not violate invariants! */
    GNUNET_assert ( (NULL == mhd_ret) ||
                    (-1 == (int) *mhd_ret) );
    if (0 <= qs)
      return GNUNET_OK;
    TEH_METRICS_num_conflict[mt]++;
  }
  TEH_plugin->rollback (TEH_plugin->cls);
  TALER_LOG_ERROR ("Transaction `%s' commit failed %u times\n",
                   name,
                   MAX_TRANSACTION_COMMIT_RETRIES);
  if (NULL != mhd_ret)
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_SOFT_FAILURE,
                                           NULL);
  return GNUNET_SYSERR;
}


/* end of taler-exchange-httpd_db.c */
