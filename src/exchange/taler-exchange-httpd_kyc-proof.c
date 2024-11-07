/*
  This file is part of TALER
  Copyright (C) 2021-2023 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-proof.c
 * @brief Handle request for proof for KYC check.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_attributes.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler_templating_lib.h"
#include "taler-exchange-httpd_common_kyc.h"
#include "taler-exchange-httpd_kyc-proof.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Context for the proof.
 */
struct KycProofContext
{

  /**
   * Kept in a DLL while suspended.
   */
  struct KycProofContext *next;

  /**
   * Kept in a DLL while suspended.
   */
  struct KycProofContext *prev;

  /**
   * Details about the connection we are processing.
   */
  struct TEH_RequestContext *rc;

  /**
   * Proof logic to run.
   */
  struct TALER_KYCLOGIC_Plugin *logic;

  /**
   * Configuration for @a logic.
   */
  struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * Asynchronous operation with the proof system.
   */
  struct TALER_KYCLOGIC_ProofHandle *ph;

  /**
   * KYC AML trigger operation.
   */
  struct TEH_KycAmlTrigger *kat;

  /**
   * Process information about the user for the plugin from the database, can
   * be NULL.
   */
  char *provider_user_id;

  /**
   * Process information about the legitimization process for the plugin from the
   * database, can be NULL.
   */
  char *provider_legitimization_id;

  /**
   * Hash of payment target URI this is about.
   */
  struct TALER_NormalizedPaytoHashP h_payto;

  /**
   * Final HTTP response to return.
   */
  struct MHD_Response *response;

  /**
   * Final HTTP response code to return.
   */
  unsigned int response_code;

  /**
   * HTTP response from the KYC provider plugin.
   */
  struct MHD_Response *proof_response;

  /**
   * HTTP response code from the KYC provider plugin.
   */
  unsigned int proof_response_code;

  /**
   * Provider configuration section name of the logic we are running.
   */
  const char *provider_name;

  /**
   * Row in the database for this legitimization operation.
   */
  uint64_t process_row;

  /**
   * True if we are suspended,
   */
  bool suspended;

};


/**
 * Contexts are kept in a DLL while suspended.
 */
static struct KycProofContext *kpc_head;

/**
 * Contexts are kept in a DLL while suspended.
 */
static struct KycProofContext *kpc_tail;


/**
 * Generate HTML error for @a connection using @a template.
 *
 * @param connection HTTP client connection
 * @param template template to expand
 * @param[in,out] http_status HTTP status of the response
 * @param ec Taler error code to return
 * @param message extended message to return
 * @return MHD response object
 */
static struct MHD_Response *
make_html_error (struct MHD_Connection *connection,
                 const char *template,
                 unsigned int *http_status,
                 enum TALER_ErrorCode ec,
                 const char *message)
{
  struct MHD_Response *response = NULL;
  json_t *body;

  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string ("message",
                               message)),
    TALER_JSON_pack_ec (
      ec));
  GNUNET_break (
    GNUNET_SYSERR !=
    TALER_TEMPLATING_build (connection,
                            http_status,
                            template,
                            NULL,
                            NULL,
                            body,
                            &response));
  json_decref (body);
  return response;
}


/**
 * Resume processing the @a kpc request.
 *
 * @param kpc request to resume
 */
static void
kpc_resume (struct KycProofContext *kpc)
{
  GNUNET_assert (GNUNET_YES == kpc->suspended);
  kpc->suspended = false;
  GNUNET_CONTAINER_DLL_remove (kpc_head,
                               kpc_tail,
                               kpc);
  MHD_resume_connection (kpc->rc->connection);
  TALER_MHD_daemon_trigger ();
}


void
TEH_kyc_proof_cleanup (void)
{
  struct KycProofContext *kpc;

  while (NULL != (kpc = kpc_head))
  {
    if (NULL != kpc->ph)
    {
      kpc->logic->proof_cancel (kpc->ph);
      kpc->ph = NULL;
    }
    kpc_resume (kpc);
  }
}


/**
 * Function called after the KYC-AML trigger is done.
 *
 * @param cls closure
 * @param ec error code or 0 on success
 * @param detail error message or NULL on success / no info
 */
static void
proof_finish (
  void *cls,
  enum TALER_ErrorCode ec,
  const char *detail)
{
  struct KycProofContext *kpc = cls;

  kpc->kat = NULL;
  if (TALER_EC_NONE != ec)
  {
    kpc->response_code  = MHD_HTTP_INTERNAL_SERVER_ERROR;
    kpc->response = make_html_error (
      kpc->rc->connection,
      "kyc-proof-internal-error",
      &kpc->response_code,
      ec,
      detail);
  }
  else
  {
    GNUNET_assert (NULL != kpc->proof_response);
    kpc->response_code = kpc->proof_response_code;
    kpc->response = kpc->proof_response;
    kpc->proof_response = NULL;
    kpc->proof_response_code = 0;
  }
  GNUNET_assert (NULL == kpc->response);
  kpc_resume (kpc);
}


/**
 * Respond with an HTML message on the given @a rc.
 *
 * @param[in,out] rc request to respond to
 * @param http_status HTTP status code to use
 * @param template template to fill in
 * @param ec error code to use for the template
 * @param message additional message to return
 * @return MHD result code
 */
static MHD_RESULT
respond_html_ec (struct TEH_RequestContext *rc,
                 unsigned int http_status,
                 const char *template,
                 enum TALER_ErrorCode ec,
                 const char *message)
{
  struct MHD_Response *response;
  MHD_RESULT res;

  response = make_html_error (rc->connection,
                              template,
                              &http_status,
                              ec,
                              message);
  res = MHD_queue_response (rc->connection,
                            http_status,
                            response);
  MHD_destroy_response (response);
  return res;
}


/**
 * Function called with the result of a proof check operation.
 *
 * Note that the "decref" for the @a response
 * will be done by the callee and MUST NOT be done by the plugin.
 *
 * @param cls closure
 * @param status KYC status
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param expiration until when is the KYC check valid
 * @param attributes user attributes returned by the provider
 * @param http_status HTTP status code of @a response
 * @param[in] response to return to the HTTP client
 */
static void
proof_cb (
  void *cls,
  enum TALER_KYCLOGIC_KycStatus status,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Absolute expiration,
  const json_t *attributes,
  unsigned int http_status,
  struct MHD_Response *response)
{
  struct KycProofContext *kpc = cls;
  struct TEH_RequestContext *rc = kpc->rc;
  struct GNUNET_AsyncScopeSave old_scope;

  kpc->ph = NULL;
  kpc->proof_response = response;
  kpc->proof_response_code = http_status;
  GNUNET_async_scope_enter (&rc->async_scope_id,
                            &old_scope);
  switch (status)
  {
  case TALER_KYCLOGIC_STATUS_SUCCESS:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC process #%llu succeeded with KYC provider\n",
                (unsigned long long) kpc->process_row);
    kpc->kat = TEH_kyc_finished (
      &rc->async_scope_id,
      kpc->process_row,
      NULL, /* instant_measure */
      &kpc->h_payto,
      kpc->provider_name,
      provider_user_id,
      provider_legitimization_id,
      expiration,
      attributes,
      &proof_finish,
      kpc);
    if (NULL == kpc->kat)
    {
      proof_finish (kpc,
                    TALER_EC_EXCHANGE_GENERIC_BAD_CONFIGURATION,
                    "[exchange] AML_KYC_TRIGGER");
    }
    break;
  case TALER_KYCLOGIC_STATUS_FAILED:
  case TALER_KYCLOGIC_STATUS_PROVIDER_FAILED:
  case TALER_KYCLOGIC_STATUS_USER_ABORTED:
  case TALER_KYCLOGIC_STATUS_ABORTED:
    GNUNET_assert (NULL == kpc->kat);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC process %s/%s (Row #%llu) failed: %d\n",
                provider_user_id,
                provider_legitimization_id,
                (unsigned long long) kpc->process_row,
                status);
    if (5 == http_status / 100)
    {
      char *msg;

      /* OAuth2 server had a problem, do NOT log this as a KYC failure */
      GNUNET_asprintf (&msg,
                       "Failure by KYC provider (HTTP status %u)\n",
                       http_status);
      http_status = MHD_HTTP_BAD_GATEWAY;
      proof_finish (
        kpc,
        TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY,
        msg);
      GNUNET_free (msg);
    }
    else
    {
      if (! TEH_kyc_failed (
            kpc->process_row,
            &kpc->h_payto,
            kpc->provider_name,
            provider_user_id,
            provider_legitimization_id,
            TALER_KYCLOGIC_status2s (status),
            TALER_EC_EXCHANGE_GENERIC_KYC_FAILED))
      {
        GNUNET_break (0);
        proof_finish (
          kpc,
          TALER_EC_GENERIC_DB_STORE_FAILED,
          "insert_kyc_failure");
      }
      else
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "KYC process #%llu failed with status %d\n",
                    (unsigned long long) kpc->process_row,
                    status);
        proof_finish (kpc,
                      TALER_EC_NONE,
                      NULL);
      }
    }
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC status of %s/%s (Row #%llu) is %d\n",
                provider_user_id,
                provider_legitimization_id,
                (unsigned long long) kpc->process_row,
                (int) status);
    break;
  }
  GNUNET_async_scope_restore (&old_scope);
}


/**
 * Function called to clean up a context.
 *
 * @param rc request context
 */
static void
clean_kpc (struct TEH_RequestContext *rc)
{
  struct KycProofContext *kpc = rc->rh_ctx;

  if (NULL != kpc->ph)
  {
    kpc->logic->proof_cancel (kpc->ph);
    kpc->ph = NULL;
  }
  if (NULL != kpc->kat)
  {
    TEH_kyc_finished_cancel (kpc->kat);
    kpc->kat = NULL;
  }
  if (NULL != kpc->response)
  {
    MHD_destroy_response (kpc->response);
    kpc->response = NULL;
  }
  if (NULL != kpc->proof_response)
  {
    MHD_destroy_response (kpc->proof_response);
    kpc->proof_response = NULL;
  }
  GNUNET_free (kpc->provider_user_id);
  GNUNET_free (kpc->provider_legitimization_id);
  GNUNET_free (kpc);
}


MHD_RESULT
TEH_handler_kyc_proof (
  struct TEH_RequestContext *rc,
  const char *const args[1])
{
  struct KycProofContext *kpc = rc->rh_ctx;
  const char *provider_name_or_logic = args[0];

  if (NULL == kpc)
  {
    /* first time */
    if (NULL == provider_name_or_logic)
    {
      GNUNET_break_op (0);
      return respond_html_ec (
        rc,
        MHD_HTTP_NOT_FOUND,
        "kyc-proof-endpoint-unknown",
        TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
        "'/kyc-proof/$PROVIDER_NAME?state=$H_PAYTO' required");
    }
    kpc = GNUNET_new (struct KycProofContext);
    kpc->rc = rc;
    rc->rh_ctx = kpc;
    rc->rh_cleaner = &clean_kpc;
    TALER_MHD_parse_request_arg_auto_t (rc->connection,
                                        "state",
                                        &kpc->h_payto);
    if (GNUNET_OK !=
        TALER_KYCLOGIC_lookup_logic (
          provider_name_or_logic,
          &kpc->logic,
          &kpc->pd,
          &kpc->provider_name))
    {
      GNUNET_break_op (0);
      return respond_html_ec (
        rc,
        MHD_HTTP_NOT_FOUND,
        "kyc-proof-target-unknown",
        TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_UNKNOWN,
        provider_name_or_logic);
    }
    if (NULL != kpc->provider_name)
    {
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_TIME_Absolute expiration;

      if (0 != strcmp (provider_name_or_logic,
                       kpc->provider_name))
      {
        GNUNET_break_op (0);
        return respond_html_ec (
          rc,
          MHD_HTTP_BAD_REQUEST,
          "kyc-proof-bad-request",
          TALER_EC_GENERIC_PARAMETER_MALFORMED,
          "PROVIDER_NAME");
      }

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Looking for KYC process at %s\n",
                  kpc->provider_name);
      qs = TEH_plugin->lookup_kyc_process_by_account (
        TEH_plugin->cls,
        kpc->provider_name,
        &kpc->h_payto,
        &kpc->process_row,
        &expiration,
        &kpc->provider_user_id,
        &kpc->provider_legitimization_id);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
      case GNUNET_DB_STATUS_SOFT_ERROR:
        return respond_html_ec (
          rc,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          "kyc-proof-internal-error",
          TALER_EC_GENERIC_DB_FETCH_FAILED,
          "lookup_kyc_process_by_account");
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        GNUNET_break_op (0);
        return respond_html_ec (
          rc,
          MHD_HTTP_NOT_FOUND,
          "kyc-proof-target-unknown",
          TALER_EC_EXCHANGE_KYC_PROOF_REQUEST_UNKNOWN,
          kpc->provider_name);
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        break;
      }
      if (GNUNET_TIME_absolute_is_future (expiration))
      {
        /* KYC not required */
        return respond_html_ec (
          rc,
          MHD_HTTP_OK,
          "kyc-proof-already-done",
          TALER_EC_NONE,
          NULL);
      }
    }
    kpc->ph = kpc->logic->proof (
      kpc->logic->cls,
      kpc->pd,
      rc->connection,
      &kpc->h_payto,
      kpc->process_row,
      kpc->provider_user_id,
      kpc->provider_legitimization_id,
      &proof_cb,
      kpc);
    if (NULL == kpc->ph)
    {
      GNUNET_break (0);
      return respond_html_ec (
        rc,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        "kyc-proof-internal-error",
        TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
        "could not start proof with KYC logic");
    }


    kpc->suspended = true;
    GNUNET_CONTAINER_DLL_insert (kpc_head,
                                 kpc_tail,
                                 kpc);
    MHD_suspend_connection (rc->connection);
    return MHD_YES;
  }

  if (NULL == kpc->response)
  {
    GNUNET_break (0);
    return respond_html_ec (
      rc,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      "kyc-proof-internal-error",
      TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
      "handler resumed without response");
  }

  /* return response from KYC logic */
  return MHD_queue_response (rc->connection,
                             kpc->response_code,
                             kpc->response);
}


/* end of taler-exchange-httpd_kyc-proof.c */
