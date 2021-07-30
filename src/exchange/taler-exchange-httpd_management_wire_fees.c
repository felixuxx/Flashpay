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
 * @file taler-exchange-httpd_management_wire_fees.c
 * @brief Handle request to add wire fee details
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
#include "taler-exchange-httpd_management.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_wire.h"


/**
 * Closure for the #add_fee transaction.
 */
struct AddFeeContext
{
  /**
   * Fee's signature affirming the #TALER_SIGNATURE_MASTER_WIRE_FEES operation.
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * Wire method this is about.
   */
  const char *wire_method;

  /**
   * Starting period.
   */
  struct GNUNET_TIME_Absolute start_time;

  /**
   * End of period.
   */
  struct GNUNET_TIME_Absolute end_time;

  /**
   * Wire fee amount.
   */
  struct TALER_Amount wire_fee;

  /**
   * Closing fee amount.
   */
  struct TALER_Amount closing_fee;

};


/**
 * Function implementing database transaction to add a fee.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction logic
 * MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct AddFeeContext`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
add_fee (void *cls,
         struct MHD_Connection *connection,
         struct TALER_EXCHANGEDB_Session *session,
         MHD_RESULT *mhd_ret)
{
  struct AddFeeContext *afc = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_Amount wire_fee;
  struct TALER_Amount closing_fee;

  qs = TEH_plugin->lookup_wire_fee_by_time (
    TEH_plugin->cls,
    session,
    afc->wire_method,
    afc->start_time,
    afc->end_time,
    &wire_fee,
    &closing_fee);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "lookup wire fee");
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs)
  {
    if ( (GNUNET_OK ==
          TALER_amount_is_valid (&wire_fee)) &&
         (0 ==
          TALER_amount_cmp (&wire_fee,
                            &afc->wire_fee)) &&
         (0 ==
          TALER_amount_cmp (&closing_fee,
                            &afc->closing_fee)) )
    {
      /* this will trigger the 'success' response */
      return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
    }
    else
    {
      *mhd_ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_CONFLICT,
        TALER_EC_EXCHANGE_MANAGEMENT_WIRE_FEE_MISMATCH,
        NULL);
    }
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  qs = TEH_plugin->insert_wire_fee (
    TEH_plugin->cls,
    session,
    afc->wire_method,
    afc->start_time,
    afc->end_time,
    &afc->wire_fee,
    &afc->closing_fee,
    &afc->master_sig);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "insert fee");
    return qs;
  }
  return qs;
}


MHD_RESULT
TEH_handler_management_post_wire_fees (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct AddFeeContext afc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &afc.master_sig),
    GNUNET_JSON_spec_string ("wire_method",
                             &afc.wire_method),
    TALER_JSON_spec_absolute_time ("fee_start",
                                   &afc.start_time),
    TALER_JSON_spec_absolute_time ("fee_end",
                                   &afc.end_time),
    TALER_JSON_spec_amount ("closing_fee",
                            TEH_currency,
                            &afc.closing_fee),
    TALER_JSON_spec_amount ("wire_fee",
                            TEH_currency,
                            &afc.wire_fee),
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
      TALER_exchange_offline_wire_fee_verify (
        afc.wire_method,
        afc.start_time,
        afc.end_time,
        &afc.wire_fee,
        &afc.closing_fee,
        &TEH_master_public_key,
        &afc.master_sig))
  {
    /* signature invalid */
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_MANAGEMENT_WIRE_FEE_SIGNATURE_INVALID,
      NULL);
  }

  {
    enum GNUNET_GenericReturnValue res;
    MHD_RESULT ret;

    res = TEH_DB_run_transaction (connection,
                                  "add wire fee",
                                  &ret,
                                  &add_fee,
                                  &afc);
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


/* end of taler-exchange-httpd_management_wire_fees.c */
