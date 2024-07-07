/*
  This file is part of TALER
  Copyright (C) 2021-2024 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-start.c
 * @brief Handle request for starting a KYC process with an external provider.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_kyc-wallet.h"
#include "taler-exchange-httpd_responses.h"


/**
 * POST request in asynchronous processing.
 */
struct KycPoller
{

  /**
   * Access token for the KYC data of the account.
   */
  struct TALER_AccountAccessTokenP access_token;

  /**
   * Hash of the payto:// URI we are starting to the KYC for.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Kept in a DLL.
   */
  struct KycPoller *next;

  /**
   * Kept in a DLL.
   */
  struct KycPoller *prev;

  /**
   * Connection we are handling.
   */
  struct MHD_Connection *connection;

  /**
   * Logic for @e ih
   */
  struct TALER_KYCLOGIC_Plugin *ih_logic;

  /**
   * Handle to asynchronously running KYC initiation
   * request.
   */
  struct TALER_KYCLOGIC_InitiateHandle *ih;

  /**
   * Set of applicable KYC measures.
   */
  json_t *jmeasures;

  /**
   * Where to redirect the user to start the KYC process.
   */
  char *redirect_url;

  /**
   * Set to the name of the KYC provider.
   */
  char *provider_name;

  /**
   * Set to error details, on error (@ec not TALER_EC_NONE).
   */
  char *hint;

  /**
   * Row of the requirement being started.
   */
  unsigned long long legitimization_measure_serial_id;

  /**
   * Row of KYC process being initiated.
   */
  uint64_t process_row;

  /**
   * Index of the measure this upload is for.
   */
  unsigned int measure_index;

  /**
   * Set to error encountered with KYC logic, if any.
   */
  enum TALER_ErrorCode ec;

  /**
   * True if we are still suspended.
   */
  bool suspended;

};


/**
 * Head of list of requests in asynchronous processing.
 */
static struct KycPoller *kyp_head;

/**
 * Tail of list of requests in asynchronous processing.
 */
static struct KycPoller *kyp_tail;


void
TEH_kyc_start_cleanup ()
{
  struct KycPoller *kyp;

  while (NULL != (kyp = kyp_head))
  {
    GNUNET_CONTAINER_DLL_remove (kyp_head,
                                 kyp_tail,
                                 kyp);
    if (NULL != kyp->ih)
    {
      kyp->ih_logic->initiate_cancel (kyp->ih);
      kyp->ih = NULL;
    }
    if (kyp->suspended)
    {
      kyp->suspended = false;
      MHD_resume_connection (kyp->connection);
    }
  }
}


/**
 * Function called once a connection is done to
 * clean up the `struct ReservePoller` state.
 *
 * @param rc context to clean up for
 */
static void
kyp_cleanup (struct TEH_RequestContext *rc)
{
  struct KycPoller *kyp = rc->rh_ctx;

  GNUNET_assert (! kyp->suspended);
  if (NULL != kyp->ih)
  {
    kyp->ih_logic->initiate_cancel (kyp->ih);
    kyp->ih = NULL;
  }
  GNUNET_free (kyp->redirect_url);
  GNUNET_free (kyp->provider_name);
  GNUNET_free (kyp->hint);
  json_decref (kyp->jmeasures);
  GNUNET_free (kyp);
}


/**
 * Function called with the result of a KYC initiation
 * operation.
 *
 * @param cls closure with our `struct KycPoller *`
 * @param ec #TALER_EC_NONE on success
 * @param redirect_url set to where to redirect the user on success, NULL on failure
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param error_msg_hint set to additional details to return to user, NULL on success
 */
static void
initiate_cb (
  void *cls,
  enum TALER_ErrorCode ec,
  const char *redirect_url,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  const char *error_msg_hint)
{
  struct KycPoller *kyp = cls;
  enum GNUNET_DB_QueryStatus qs;

  kyp->ih = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_START,
              "KYC initiation `%s' completed with ec=%d (%s)\n",
              provider_legitimization_id,
              ec,
              (TALER_EC_NONE == ec)
              ? redirect_url
              : error_msg_hint);
  kyp->ec = ec;
  if (TALER_EC_NONE == ec)
  {
    kyp->redirect_url = GNUNET_strdup (redirect_url);
  }
  else
  {
    kyp->hint = GNUNET_strdup (error_msg_hint);
  }
  // FIXME: also store errors!
  qs = TEH_plugin->update_kyc_process_by_row (
    TEH_plugin->cls,
    kyp->process_row,
    kyp->provider_name,
    &kyp->h_payto,
    provider_user_id,
    provider_legitimization_id,
    redirect_url,
    GNUNET_TIME_UNIT_ZERO_ABS);
  if (qs <= 0)
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "KYC requirement update failed for %s with status %d at %s:%u\n",
                TALER_B2S (&kyp->h_payto),
                qs,
                __FILE__,
                __LINE__);
  GNUNET_assert (kyp->suspended);
  kyp->suspended = false;
  GNUNET_CONTAINER_DLL_remove (kyp_head,
                               kyp_tail,
                               kyp);
  MHD_resume_connection (kyp->connection);
  TALER_MHD_daemon_trigger ();
}


MHD_RESULT
TEH_handler_kyc_start (
  struct TEH_RequestContext *rc,
  const char *const args[1])
{
  struct KycPoller *kyp = rc->rh_ctx;
  MHD_RESULT res;
  enum GNUNET_GenericReturnValue ret;

  if (NULL == kyp)
  {
    enum GNUNET_DB_QueryStatus qs;
    const struct TALER_KYCLOGIC_KycProvider *provider;

    kyp = GNUNET_new (struct KycPoller);
    kyp->connection = rc->connection;
    rc->rh_ctx = kyp;
    rc->rh_cleaner = &kyp_cleanup;

    {
      unsigned long long requirement_row;
      char dummy;
      const char *slash;

      slash = strchr (id, '-');
      if (NULL == slash)
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_NOT_FOUND,
          TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
          rc->url);
      }
      if (GNUNET_OK !=
          GNUNET_STRINGS_string_to_data (id,
                                         slash - id,
                                         &kyp->access_token,
                                         sizeof (kyp->access_token)))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_BAD_REQUEST,
          TALER_EC_GENERIC_PARAMETER_MALFORMED,
          "Access token in ID is malformed");
      }
      if (2 !=
          sscanf (slash + 1,
                  "%u-%llu%c",
                  &kyp->measure_index,
                  &kyp->legitimization_measure_serial_id,
                  &dummy))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_BAD_REQUEST,
          TALER_EC_GENERIC_PARAMETER_MALFORMED,
          "ID is malformed");
      }
    }

    // FIXME: bad check, cannot return jmeasures,
    // we need a redirect_url AND an EC to see if
    // we should restart 'initiate' anyway!
    qs = TEH_plugin->lookup_pending_legitimization (
      TEH_plugin->cls,
      kyp->legitimization_measure_serial_id,
      &kyp->access_token,
      &kyp->h_payto,
      &kyp->jmeasures);
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
      return TALER_MHD_reply_with_ec (
        rc->connection,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "lookup_pending_legitimization");
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_NOT_FOUND,
        TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
        rc->url);
    }

    {
      const char *check_name;
      const char *prog_name;
      const json_t *context;
      json_t *req;

      kyp->ec = TALER_KYCLOGIC_select_measure (
        kyp->jmeasures,
        kyp->measure_index,
        &check_name,
        &prog_name);
      if (TALER_EC_NONE != kyp->ec)
      {
        /* return EC in next call to this function */
        GNUNET_break_op (0);
        kyp->hint
          = GNUNET_strdup ("TALER_KYCLOGIC_select_measure");
        return MHD_YES;
      }

      provider = TALER_KYCLOGIC_check_to_provider (
        check_name);
      if (NULL == provider)
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_CONFLICT,
          42, // FIXME: TALER_EC_EXCHANGE_BAD_CHECK_FOR_KYC_START,
          check_name);
      }
    }

    ret = TALER_KYCLOGIC_provider_to_logic (
      provider,
      &kyp->ih_logic,
      &pd,
      &kyp->provider_name);
    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "KYC requirements `%s' cannot be started, but are set as required in database!\n",
                  requirements);
      GNUNET_free (requirements);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_GONE,
        NULL);
    }

    /* FIXME: the next two DB interactions should be ONE
       transaction */
    /* Check if we already initiated this process */
    qs = TEH_plugin->get_pending_kyc_requirement_process (
      TEH_plugin->cls,
      &h_payto,
      kyp->provider_name,
      &kyp->redirect_url);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "get_pending_kyc_requirement_process");
    }
    if (NULL != kyp->redirect_url)
      return MHD_YES; /* success, return the redirect URL
                         (in next call to this function) */

    /* set up new requirement process */
    qs = TEH_plugin->insert_kyc_requirement_process (
      TEH_plugin->cls,
      &h_payto,
      kyp->measure_index,
      kyp->legitimization_measure_serial_id,
      kyp->provider_name,
      NULL, /* provider_account_id */
      NULL, /* provider_legitimziation_id */
      &kyp->process_row);
    if (qs < 0)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_STORE_FAILED,
        "insert_kyc_requirement_process");
    }

    kyp->ih = kyp->ih_logic->initiate (
      kyp->ih_logic->cls,
      pd,
      &h_payto,
      kyp->process_row,
      &initiate_cb,
      kyp);
    if (NULL == kyp->ih)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_BUG,
        "initiate KYC process");
    }
    kyp->suspended = true;
    GNUNET_CONTAINER_DLL_insert (kyp_head,
                                 kyp_tail,
                                 kyp);
    MHD_suspend_connection (kyp->connection);
    return MHD_YES;
  }

  if ( (TALER_EC_NONE != kyp->ec) ||
       (NULL == kyp->redirect_url) )
  {
    GNUNET_break (0);
    if (TALER_EC_NONE == kyp->ec)
    {
      GNUNET_break (0);
      kyp->ec = TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE;
    }
    return TALER_MHD_reply_with_ec (rc->connection,
                                    kyp->ec,
                                    kyp->hint);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    rc->connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_string ("redirect_url",
                             kyp->redirect_url));
}


/* end of taler-exchange-httpd_kyc-start.c */
