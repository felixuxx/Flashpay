/*
  This file is part of TALER
  Copyright (C) 2021-2022 Taler Systems SA

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
#include <pthread.h>
#include "taler_attributes.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
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
  struct TALER_PaytoHashP h_payto;

  /**
   * HTTP response to return.
   */
  struct MHD_Response *response;

  /**
   * Provider configuration section name of the logic we are running.
   */
  const char *provider_section;

  /**
   * Row in the database for this legitimization operation.
   */
  uint64_t process_row;

  /**
   * HTTP response code to return.
   */
  unsigned int response_code;

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
  GNUNET_async_scope_enter (&rc->async_scope_id,
                            &old_scope);

  if (TALER_KYCLOGIC_STATUS_SUCCESS == status)
  {
    enum GNUNET_DB_QueryStatus qs;
    size_t eas;
    void *ea;
    const char *birthdate;
    struct GNUNET_ShortHashCode kyc_prox;

    TALER_CRYPTO_attributes_to_kyc_prox (attributes,
                                         &kyc_prox);
    birthdate = json_string_value (json_object_get (attributes,
                                                    TALER_ATTRIBUTE_BIRTHDATE));
    TALER_CRYPTO_kyc_attributes_encrypt (&TEH_attribute_key,
                                         attributes,
                                         &ea,
                                         &eas);
    qs = TEH_plugin->insert_kyc_attributes (
      TEH_plugin->cls,
      &kpc->h_payto,
      &kyc_prox,
      kpc->provider_section,
      birthdate,
      GNUNET_TIME_timestamp_get (),
      GNUNET_TIME_absolute_to_timestamp (expiration),
      eas,
      ea);
    GNUNET_free (ea);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      if (NULL != response)
        MHD_destroy_response (response);
      kpc->response_code = MHD_HTTP_INTERNAL_SERVER_ERROR;
      kpc->response = TALER_MHD_make_error (TALER_EC_GENERIC_DB_STORE_FAILED,
                                            "insert_kyc_attributes");
      GNUNET_async_scope_restore (&old_scope);
      return;
    }
    qs = TEH_plugin->update_kyc_process_by_row (TEH_plugin->cls,
                                                kpc->process_row,
                                                kpc->provider_section,
                                                &kpc->h_payto,
                                                provider_user_id,
                                                provider_legitimization_id,
                                                expiration);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      if (NULL != response)
        MHD_destroy_response (response);
      kpc->response_code = MHD_HTTP_INTERNAL_SERVER_ERROR;
      kpc->response = TALER_MHD_make_error (TALER_EC_GENERIC_DB_STORE_FAILED,
                                            "set_kyc_ok");
      GNUNET_async_scope_restore (&old_scope);
      return;
    }
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC process #%llu failed with status %d\n",
                (unsigned long long) kpc->process_row,
                status);
  }
  kpc->response_code = http_status;
  kpc->response = response;
  kpc_resume (kpc);
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
  if (NULL != kpc->response)
  {
    MHD_destroy_response (kpc->response);
    kpc->response = NULL;
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
  const char *provider_section_or_logic = args[0];

  if (NULL == kpc)
  {
    /* first time */
    if (NULL == provider_section_or_logic)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                         "'/kyc-proof/$PROVIDER_SECTION?state=$H_PAYTO' required");
    }
    kpc = GNUNET_new (struct KycProofContext);
    kpc->rc = rc;
    rc->rh_ctx = kpc;
    rc->rh_cleaner = &clean_kpc;
    TALER_MHD_parse_request_arg_auto_t (rc->connection,
                                        "state",
                                        &kpc->h_payto);
    if (GNUNET_OK !=
        TALER_KYCLOGIC_lookup_logic (provider_section_or_logic,
                                     &kpc->logic,
                                     &kpc->pd,
                                     &kpc->provider_section))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_UNKNOWN,
                                         provider_section_or_logic);
    }
    if (NULL != kpc->provider_section)
    {
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_TIME_Absolute expiration;

      if (0 != strcmp (provider_section_or_logic,
                       kpc->provider_section))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           "PROVIDER_SECTION");
      }

      qs = TEH_plugin->lookup_kyc_process_by_account (
        TEH_plugin->cls,
        kpc->provider_section,
        &kpc->h_payto,
        &kpc->process_row,
        &expiration,
        &kpc->provider_user_id,
        &kpc->provider_legitimization_id);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
      case GNUNET_DB_STATUS_SOFT_ERROR:
        return TALER_MHD_reply_with_ec (rc->connection,
                                        TALER_EC_GENERIC_DB_STORE_FAILED,
                                        "lookup_kyc_requirement_by_account");
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_KYC_PROOF_REQUEST_UNKNOWN,
                                           kpc->provider_section);
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        break;
      }
      if (GNUNET_TIME_absolute_is_future (expiration))
      {
        /* KYC not required */
        return TALER_MHD_reply_static (
          rc->connection,
          MHD_HTTP_NO_CONTENT,
          NULL,
          NULL,
          0);
      }
    }
    kpc->ph = kpc->logic->proof (kpc->logic->cls,
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
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
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
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                       "handler resumed without response");
  }

  /* return response from KYC logic */
  return MHD_queue_response (rc->connection,
                             kpc->response_code,
                             kpc->response);
}


/* end of taler-exchange-httpd_kyc-proof.c */
