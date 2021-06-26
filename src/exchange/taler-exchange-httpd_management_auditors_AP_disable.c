/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file taler-exchange-httpd_management_auditors_AP_disable.c
 * @brief Handle request to disable auditor.
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
 * Closure for the #del_auditor transaction.
 */
struct DelAuditorContext
{

  /**
   * Auditor public key this is about.
   */
  struct TALER_AuditorPublicKeyP auditor_pub;

  /**
   * Auditor URL this is about.
   */
  const char *auditor_url;

  /**
   * Timestamp for checking against replay attacks.
   */
  struct GNUNET_TIME_Absolute validity_end;

};


/**
 * Function implementing database transaction to del an auditor.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction logic
 * MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct DelAuditorContext`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
del_auditor (void *cls,
             struct MHD_Connection *connection,
             struct TALER_EXCHANGEDB_Session *session,
             MHD_RESULT *mhd_ret)
{
  struct DelAuditorContext *dac = cls;
  struct GNUNET_TIME_Absolute last_date;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->lookup_auditor_timestamp (TEH_plugin->cls,
                                             session,
                                             &dac->auditor_pub,
                                             &last_date);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "lookup auditor");
    return qs;
  }
  if (last_date.abs_value_us > dac->validity_end.abs_value_us)
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_CONFLICT,
      TALER_EC_EXCHANGE_MANAGEMENT_AUDITOR_MORE_RECENT_PRESENT,
      NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (0 == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_NOT_FOUND,
      TALER_EC_EXCHANGE_MANAGEMENT_AUDITOR_NOT_FOUND,
      NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  qs = TEH_plugin->update_auditor (TEH_plugin->cls,
                                   session,
                                   &dac->auditor_pub,
                                   "", /* auditor URL */
                                   "", /* auditor name */
                                   dac->validity_end,
                                   false);
  if (qs < 0)
  {
    GNUNET_break (0);
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "del auditor");
    return qs;
  }
  TEH_keys_update_states ();
  return qs;
}


MHD_RESULT
TEH_handler_management_auditors_AP_disable (
  struct MHD_Connection *connection,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const json_t *root)
{
  struct TALER_MasterSignatureP master_sig;
  struct DelAuditorContext dac = {
    .auditor_pub = *auditor_pub
  };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    TALER_JSON_spec_absolute_time ("validity_end",
                                   &dac.validity_end),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_DB_QueryStatus qs;
  MHD_RESULT res;

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
      TALER_exchange_offline_auditor_del_verify (
        auditor_pub,
        dac.validity_end,
        &TEH_master_public_key,
        &master_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_MANAGEMENT_AUDITOR_DEL_SIGNATURE_INVALID,
      NULL);
  }

  qs = TEH_DB_run_transaction (connection,
                               "del auditor",
                               &res,
                               &del_auditor,
                               &dac);
  if (qs < 0)
    return res;
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_management_auditors_AP_disable.c */
