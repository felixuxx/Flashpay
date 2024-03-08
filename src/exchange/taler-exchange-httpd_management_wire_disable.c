/*
  This file is part of TALER
  Copyright (C) 2020-2023 Taler Systems SA

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
 * @file taler-exchange-httpd_management_wire_disable.c
 * @brief Handle request to disable wire account.
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
#include "taler-exchange-httpd_management.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Closure for the #del_wire transaction.
 */
struct DelWireContext
{
  /**
   * Master signature affirming the WIRE DEL operation
   * (includes timestamp).
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * Payto:// URI this is about.
   */
  const char *payto_uri;

  /**
   * Timestamp for checking against replay attacks.
   */
  struct GNUNET_TIME_Timestamp validity_end;

};


/**
 * Function implementing database transaction to del an wire.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction logic
 * MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct DelWireContext`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
del_wire (void *cls,
          struct MHD_Connection *connection,
          MHD_RESULT *mhd_ret)
{
  struct DelWireContext *awc = cls;
  struct GNUNET_TIME_Timestamp last_date;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->lookup_wire_timestamp (TEH_plugin->cls,
                                          awc->payto_uri,
                                          &last_date);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "lookup wire");
    return qs;
  }
  if (GNUNET_TIME_timestamp_cmp (last_date,
                                 >,
                                 awc->validity_end))
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_CONFLICT,
      TALER_EC_EXCHANGE_MANAGEMENT_WIRE_MORE_RECENT_PRESENT,
      NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_NOT_FOUND,
      TALER_EC_EXCHANGE_MANAGEMENT_WIRE_NOT_FOUND,
      NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  qs = TEH_plugin->update_wire (TEH_plugin->cls,
                                awc->payto_uri,
                                NULL,
                                NULL,
                                NULL,
                                awc->validity_end,
                                NULL,
                                false);
  if (qs < 0)
  {
    GNUNET_break (0);
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "del wire");
    return qs;
  }
  return qs;
}


MHD_RESULT
TEH_handler_management_post_wire_disable (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct DelWireContext awc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig_del",
                                 &awc.master_sig),
    TALER_JSON_spec_payto_uri ("payto_uri",
                               &awc.payto_uri),
    GNUNET_JSON_spec_timestamp ("validity_end",
                                &awc.validity_end),
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
  if (GNUNET_OK !=
      TALER_exchange_offline_wire_del_verify (
        awc.payto_uri,
        awc.validity_end,
        &TEH_master_public_key,
        &awc.master_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_MANAGEMENT_WIRE_DEL_SIGNATURE_INVALID,
      NULL);
  }

  {
    enum GNUNET_GenericReturnValue res;
    MHD_RESULT ret;

    res = TEH_DB_run_transaction (connection,
                                  "del wire",
                                  TEH_MT_REQUEST_OTHER,
                                  &ret,
                                  &del_wire,
                                  &awc);
    if (GNUNET_SYSERR == res)
      return ret;
  }
  TEH_wire_update_state ();
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_management_wire_disable.c */
