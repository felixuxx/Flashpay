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
#include "taler-exchange-httpd_keystate.h"

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
  struct GNUNET_TIME_Absolute validity_end;

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
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
del_wire (void *cls,
          struct MHD_Connection *connection,
          struct TALER_EXCHANGEDB_Session *session,
          MHD_RESULT *mhd_ret)
{
  struct DelWireContext *awc = cls;
  struct GNUNET_TIME_Absolute last_date;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->lookup_wire_timestamp (TEH_plugin->cls,
                                          session,
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
  if (last_date.abs_value_us > awc->validity_end.abs_value_us)
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_CONFLICT,
      TALER_EC_EXCHANGE_MANAGEMENT_WIRE_MORE_RECENT_PRESENT,
      NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (0 == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_NOT_FOUND,
      TALER_EC_EXCHANGE_MANAGEMENT_WIRE_NOT_FOUND,
      NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  qs = TEH_plugin->update_wire (TEH_plugin->cls,
                                session,
                                awc->payto_uri,
                                awc->validity_end,
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
TEH_handler_management_denominations_wire_disable (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct DelWireContext awc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &awc.master_sig),
    GNUNET_JSON_spec_string ("payto_uri",
                             &awc.payto_uri),
    TALER_JSON_spec_absolute_time ("validity_end",
                                   &awc.validity_end),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_DB_QueryStatus qs;
  MHD_RESULT ret;

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
  {
    struct TALER_MasterDelWirePS aw = {
      .purpose.purpose = htonl (
        TALER_SIGNATURE_MASTER_DEL_WIRE),
      .purpose.size = htonl (sizeof (aw)),
      .end_date = GNUNET_TIME_absolute_hton (awc.validity_end),
    };

    GNUNET_CRYPTO_hash (awc.payto_uri,
                        strlen (awc.payto_uri) + 1,
                        &aw.h_wire);
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (
          TALER_SIGNATURE_MASTER_DEL_WIRE,
          &aw,
          &awc.master_sig.eddsa_signature,
          &TEH_master_public_key.eddsa_pub))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_MANAGEMENT_WIRE_DEL_SIGNATURE_INVALID,
        NULL);
    }
  }
  qs = TEH_DB_run_transaction (connection,
                               "del wire",
                               &ret,
                               &del_wire,
                               &awc);
  if (qs < 0)
    return ret;
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_management_wire_disable.c */
