/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_management_drain.c
 * @brief Handle request to drain profits
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_management.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Closure for the #drain transaction.
 */
struct DrainContext
{
  /**
   * Fee's signature affirming the #TALER_SIGNATURE_MASTER_DRAIN_PROFITS operation.
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * Wire transfer identifier to use.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Account to credit.
   */
  const char *payto_uri;

  /**
   * Configuration section with account to debit.
   */
  const char *account_section;

  /**
   * Signature time.
   */
  struct GNUNET_TIME_Timestamp date;

  /**
   * Amount to transfer.
   */
  struct TALER_Amount amount;

};


/**
 * Function implementing database transaction to drain profits.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction logic
 * MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct DrainContext`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
drain (void *cls,
       struct MHD_Connection *connection,
       MHD_RESULT *mhd_ret)
{
  struct DrainContext *dc = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->insert_drain_profit (
    TEH_plugin->cls,
    &dc->wtid,
    dc->account_section,
    dc->payto_uri,
    dc->date,
    &dc->amount,
    &dc->master_sig);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "insert drain profit");
    return qs;
  }
  return qs;
}


MHD_RESULT
TEH_handler_management_post_drain (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct DrainContext dc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("debit_account_section",
                             &dc.account_section),
    TALER_JSON_spec_payto_uri ("credit_payto_uri",
                               &dc.payto_uri),
    GNUNET_JSON_spec_fixed_auto ("wtid",
                                 &dc.wtid),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &dc.master_sig),
    GNUNET_JSON_spec_timestamp ("date",
                                &dc.date),
    TALER_JSON_spec_amount ("amount",
                            TEH_currency,
                            &dc.amount),
    GNUNET_JSON_spec_end ()
  };

  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
      return MHD_NO; /* hard failure */
    if (GNUNET_NO == res)
      return MHD_YES; /* failure */
  }

  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_exchange_offline_profit_drain_verify (
        &dc.wtid,
        dc.date,
        &dc.amount,
        dc.account_section,
        dc.payto_uri,
        &TEH_master_public_key,
        &dc.master_sig))
  {
    /* signature invalid */
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_MANAGEMENT_DRAIN_PROFITS_SIGNATURE_INVALID,
      NULL);
  }

  {
    enum GNUNET_GenericReturnValue res;
    MHD_RESULT ret;

    res = TEH_DB_run_transaction (connection,
                                  "insert drain profit",
                                  TEH_MT_REQUEST_OTHER,
                                  &ret,
                                  &drain,
                                  &dc);
    if (GNUNET_SYSERR == res)
      return ret;
  }
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_management_drain.c */
