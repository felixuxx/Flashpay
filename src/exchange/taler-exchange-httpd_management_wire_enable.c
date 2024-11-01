/*
  This file is part of TALER
  Copyright (C) 2020-2024 Taler Systems SA

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
 * @file taler-exchange-httpd_management_wire_enable.c
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
#include "taler_signatures.h"
#include "taler-exchange-httpd_management.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"


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
  struct TALER_FullPayto payto_uri;

  /**
   * (optional) address of a conversion service for this account.
   */
  const char *conversion_url;

  /**
   * Restrictions imposed when crediting this account.
   */
  const json_t *credit_restrictions;

  /**
   * Restrictions imposed when debiting this account.
   */
  const json_t *debit_restrictions;

  /**
   * Timestamp for checking against replay attacks.
   */
  struct GNUNET_TIME_Timestamp validity_start;

  /**
   * Label to use for this bank. Default is empty.
   */
  const char *bank_label;

  /**
   * Priority of the bank in the list. Default 0.
   */
  int64_t priority;

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
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
add_wire (void *cls,
          struct MHD_Connection *connection,
          MHD_RESULT *mhd_ret)
{
  struct AddWireContext *awc = cls;
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
  if ( (0 < qs) &&
       (GNUNET_TIME_timestamp_cmp (last_date,
                                   >,
                                   awc->validity_start)) )
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_CONFLICT,
      TALER_EC_EXCHANGE_MANAGEMENT_WIRE_MORE_RECENT_PRESENT,
      NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    qs = TEH_plugin->insert_wire (TEH_plugin->cls,
                                  awc->payto_uri,
                                  awc->conversion_url,
                                  awc->debit_restrictions,
                                  awc->credit_restrictions,
                                  awc->validity_start,
                                  &awc->master_sig_wire,
                                  awc->bank_label,
                                  awc->priority);
  else
    qs = TEH_plugin->update_wire (TEH_plugin->cls,
                                  awc->payto_uri,
                                  awc->conversion_url,
                                  awc->debit_restrictions,
                                  awc->credit_restrictions,
                                  awc->validity_start,
                                  &awc->master_sig_wire,
                                  awc->bank_label,
                                  awc->priority,
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
  return qs;
}


MHD_RESULT
TEH_handler_management_post_wire (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct AddWireContext awc = {
    .conversion_url = NULL
  };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig_wire",
                                 &awc.master_sig_wire),
    GNUNET_JSON_spec_fixed_auto ("master_sig_add",
                                 &awc.master_sig_add),
    TALER_JSON_spec_full_payto_uri ("payto_uri",
                                    &awc.payto_uri),
    GNUNET_JSON_spec_mark_optional (
      TALER_JSON_spec_web_url ("conversion_url",
                               &awc.conversion_url),
      NULL),
    GNUNET_JSON_spec_array_const ("credit_restrictions",
                                  &awc.credit_restrictions),
    GNUNET_JSON_spec_array_const ("debit_restrictions",
                                  &awc.debit_restrictions),
    GNUNET_JSON_spec_timestamp ("validity_start",
                                &awc.validity_start),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_string ("bank_label",
                               &awc.bank_label),
      NULL),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_int64 ("priority",
                              &awc.priority),
      NULL),
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
  {
    char *msg = TALER_payto_validate (awc.payto_uri);

    if (NULL != msg)
    {
      MHD_RESULT ret;

      GNUNET_break_op (0);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PAYTO_URI_MALFORMED,
        msg);
      GNUNET_JSON_parse_free (spec);
      GNUNET_free (msg);
      return ret;
    }
  }
  if (GNUNET_OK !=
      TALER_exchange_offline_wire_add_verify (
        awc.payto_uri,
        awc.conversion_url,
        awc.debit_restrictions,
        awc.credit_restrictions,
        awc.validity_start,
        &TEH_master_public_key,
        &awc.master_sig_add))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_MANAGEMENT_WIRE_ADD_SIGNATURE_INVALID,
      NULL);
  }
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_exchange_wire_signature_check (
        awc.payto_uri,
        awc.conversion_url,
        awc.debit_restrictions,
        awc.credit_restrictions,
        &TEH_master_public_key,
        &awc.master_sig_wire))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_MANAGEMENT_WIRE_DETAILS_SIGNATURE_INVALID,
      NULL);
  }
  {
    char *wire_method;

    wire_method = TALER_payto_get_method (awc.payto_uri.full_payto);
    if (NULL == wire_method)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "payto:// URI `%s' is malformed\n",
                  awc.payto_uri.full_payto);
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "payto_uri");
    }
    GNUNET_free (wire_method);
  }

  {
    enum GNUNET_GenericReturnValue res;
    MHD_RESULT ret;

    res = TEH_DB_run_transaction (connection,
                                  "add wire",
                                  TEH_MT_REQUEST_OTHER,
                                  &ret,
                                  &add_wire,
                                  &awc);
    GNUNET_JSON_parse_free (spec);
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


/* end of taler-exchange-httpd_management_wire.c */
