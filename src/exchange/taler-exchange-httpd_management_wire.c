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
 * @file taler-exchange-httpd_management_wire.c
 * @brief Handle request to add wire account.
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
#include "taler-exchange-httpd_refund.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"

/**
 * Closure for the #add_wire transaction.
 */
struct AddWireContext
{
  /**
   * Master signature affirming the WIRE ADD operation
   * (includes timestamp).
   */
  struct TALER_MasterSignatureP master_sig_add;

  /**
   * Master signature to share with clients affirming the
   * wire details of the bank.
   */
  struct TALER_MasterSignatureP master_sig_wire;

  /**
   * Payto:// URI this is about.
   */
  const char *payto_url;

  /**
   * Timestamp for checking against replay attacks.
   */
  struct GNUNET_TIME_Absolute validity_start;

};


/**
 * Function implementing database transaction to add an wire.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction logic
 * MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct AddWireContext`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
add_wire (void *cls,
          struct MHD_Connection *connection,
          struct TALER_EXCHANGEDB_Session *session,
          MHD_RESULT *mhd_ret)
{
  struct AddWireContext *awc = cls;
  struct GNUNET_TIME_Absolute last_date;

  qs = TEH_plugin->lookup_wire (TEH_plugin->cls,
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
                                           TALER_EC_GENERIC_DB_LOOKUP_FAILED,
                                           "lookup wire");
    return qs;
  }
  if (last_date.abs_value_us > awc->start_date.abs_value_us)
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_CONFLICT,
      TALER_EC_EXCHANGE_WIRE_MORE_RECENT_PRESENT,
      NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (0 == qs)
    qs = TEH_plugin->insert_wire (TEH_plugin->cls,
                                  session,
                                  &awc->payto_uri,
                                  awc->start_date,
                                  &awc->master_sig_add);
  else
    qs = TEH_plugin->update_wire (TEH_plugin->cls,
                                  session,
                                  &awc->payto_uri,
                                  awc->start_date,
                                  &awc->master_sig_add,
                                  true);
  if (qs < 0)
  {
    GNUNET_break (0);
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "add wire");
    return qs;
  }
  qs = TEH_plugin->insert_wire_details (TEH_plugin->cls,
                                        session,
                                        &awc->payto_uri,
                                        &awc->master_sig_wire);
  if (qs < 0)
  {
    GNUNET_break (0);
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "add wire details");
    return qs;
  }
  return qs;
}


/**
 * Handle a "/management/wire" request.
 *
 * @param connection the MHD connection to handle
 * @param root uploaded JSON data
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_management_denominations_wire (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct AddWireContext awc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig_wire",
                                 &awc.master_sig_wire),
    GNUNET_JSON_spec_fixed_auto ("master_sig_add",
                                 &awc.master_sig_add),
    GNUNET_JSON_spec_string ("payto_uri",
                             &awc.payto_uri),
    TALER_JSON_spec_absolute_time ("validity_start",
                                   &awc.validity_start),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_DB_QueryStatus qs;

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
    struct TALER_MasterAddWirePS aw = {
      .purpose.purpose = htonl (
        TALER_SIGNATURE_MASTER_ADD_WIRE),
      .purpose.size = htonl (sizeof (aw)),
      .start_date = GNUNET_TIME_absolute_hton (validity_start),
    };

    GNUNET_CRYPTO_hash (awc.payto_uri,
                        strlen (awc.payto_uri) + 1,
                        &aw.h_wire);
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (
          TALER_SIGNATURE_MASTER_ADD_WIRE,
          &aw,
          &master_sig.eddsa_sig,
          &TEH_master_public_key.eddsa_pub))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_WIRE_ADD_SIGNATURE_INVALID,
        NULL);
    }
  }
  {
    struct TALER_MasterWireDetailsPS wd = {
      .purpose.purpose = htonl (
        TALER_SIGNATURE_MASTER_ADD_WIRE),
      .purpose.size = htonl (sizeof (wd)),
    };

    GNUNET_CRYPTO_hash (awc.payto_uri,
                        strlen (awc.payto_uri) + 1,
                        &wd.h_wire);
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (
          TALER_SIGNATURE_MASTER_WIRE_DETAILS,
          &wd,
          &master_sig.eddsa_sig,
          &TEH_master_public_key.eddsa_pub))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_WIRE_DETALS_SIGNATURE_INVALID,
        NULL);
    }
  }

  qs = TEH_DB_run_transaction (connection,
                               "add wire",
                               &res,
                               &add_wire,
                               &awc);
  if (qs < 0)
    return res;
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_management_wire.c */
