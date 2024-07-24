/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file taler-exchange-httpd_common_kyc.c
 * @brief shared logic for finishing a KYC process
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler-exchange-httpd.h"
#include "taler-exchange-httpd_common_kyc.h"
#include "taler_attributes.h"
#include "taler_error_codes.h"
#include "taler_kyclogic_lib.h"
#include "taler_exchangedb_plugin.h"
#include <gnunet/gnunet_common.h>

struct TEH_KycAmlTrigger
{

  /**
   * Our logging scope.
   */
  struct GNUNET_AsyncScopeId scope;

  /**
   * account the operation is about
   */
  struct TALER_PaytoHashP account_id;

  /**
   * until when is the KYC data valid
   */
  struct GNUNET_TIME_Absolute expiration;

  /**
   * legitimization process the KYC data is about
   */
  uint64_t process_row;

  /**
   * name of the provider with the logic that was run
   */
  char *provider_name;

  /**
   * set to user ID at the provider, or NULL if not supported or unknown
   */
  char *provider_user_id;

  /**
   * provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
   */
  char *provider_legitimization_id;

  /**
   * function to call with the result
   */
  TEH_KycAmlTriggerCallback cb;

  /**
   * closure for @e cb
   */
  void *cb_cls;

  /**
   * user attributes returned by the provider
   */
  json_t *attributes;

  /**
   * Measures this KYC process is responding to.
   */
  json_t *jmeasures;

  /**
   * KYC history of the account.
   */
  json_t *kyc_history;

  /**
   * AML history of the account.
   */
  json_t *aml_history;

  /**
   * KYC measure the client is (trying to) satisfy.
   */
  uint32_t measure_index;

  /**
   * response to return to the HTTP client
   */
  struct MHD_Response *response;

  /**
   * Handle to an external process that evaluates the
   * need to run AML on the account.
   */
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *kyc_aml;

  /**
   * HTTP status code of @e response
   */
  unsigned int http_status;

};


/**
 * Type of a callback that receives a JSON @a result.
 *
 * @param cls closure of type `struct TEH_KycAmlTrigger *`
 * @param apr AML program result
 */
static void
kyc_aml_finished (void *cls,
                  const struct TALER_KYCLOGIC_AmlProgramResult *apr)
{
  struct TEH_KycAmlTrigger *kat = cls;
  enum GNUNET_DB_QueryStatus qs;
  size_t eas;
  void *ea;
  unsigned int birthday = 0;
  struct GNUNET_AsyncScopeSave old_scope;

  kat->kyc_aml = NULL;
  GNUNET_async_scope_enter (&kat->scope,
                            &old_scope);
  if (TALER_KYCLOGIC_AMLR_SUCCESS != apr->status)
  {
    // FIXME ...
    GNUNET_break (0); // not implemented!
  }
  {
    const char *birthdate;

    birthdate = json_string_value (
      json_object_get (kat->attributes,
                       TALER_ATTRIBUTE_BIRTHDATE));
    if ( (TEH_age_restriction_enabled) &&
         (NULL != birthdate) )
    {
      enum GNUNET_GenericReturnValue ret;

      ret = TALER_parse_coarse_date (birthdate,
                                     &TEH_age_restriction_config.mask,
                                     &birthday);

      if (GNUNET_OK != ret)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to parse birthdate `%s' from KYC attributes\n",
                    birthdate);
        if (NULL != kat->response)
          MHD_destroy_response (kat->response);
        kat->http_status = MHD_HTTP_BAD_REQUEST;
        kat->response = TALER_MHD_make_error (
          TALER_EC_GENERIC_PARAMETER_MALFORMED,
          TALER_ATTRIBUTE_BIRTHDATE);
        goto RETURN_RESULT;
      }
    }
  }

  TALER_CRYPTO_kyc_attributes_encrypt (&TEH_attribute_key,
                                       kat->attributes,
                                       &ea,
                                       &eas);
  qs = TEH_plugin->insert_kyc_attributes (
    TEH_plugin->cls,
    kat->process_row,
    &kat->account_id,
    birthday,
    GNUNET_TIME_timestamp_get (),
    kat->provider_name,
    kat->provider_user_id,
    kat->provider_legitimization_id,
    kat->expiration,
    apr->details.success.account_properties,
    apr->details.success.new_rules,
    apr->details.success.to_investigate,
    apr->details.success.num_events,
    apr->details.success.events,
    eas,
    ea,
    0 != code);
  GNUNET_free (ea);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Stored encrypted KYC process #%llu attributes: %d\n",
              (unsigned long long) kat->process_row,
              qs);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    if (NULL != kat->response)
      MHD_destroy_response (kat->response);
    kat->http_status = MHD_HTTP_INTERNAL_SERVER_ERROR;
    kat->response = TALER_MHD_make_error (TALER_EC_GENERIC_DB_STORE_FAILED,
                                          "do_insert_kyc_attributes");
    /* Continued below to return the response */
  }
RETURN_RESULT:
  /* Finally, return result to main handler */
  kat->cb (kat->cb_cls,
           kat->http_status,
           kat->response);
  kat->response = NULL;
  TEH_kyc_finished_cancel (kat);
  GNUNET_async_scope_restore (&old_scope);
}


struct TEH_KycAmlTrigger *
TEH_kyc_finished (const struct GNUNET_AsyncScopeId *scope,
                  uint64_t process_row,
                  const struct TALER_PaytoHashP *account_id,
                  const char *provider_name,
                  const char *provider_user_id,
                  const char *provider_legitimization_id,
                  struct GNUNET_TIME_Absolute expiration,
                  const json_t *attributes,
                  unsigned int http_status,
                  struct MHD_Response *response,
                  TEH_KycAmlTriggerCallback cb,
                  void *cb_cls)
{
  struct TEH_KycAmlTrigger *kat;
  enum GNUNET_DB_QueryStatus qs;

  kat = GNUNET_new (struct TEH_KycAmlTrigger);
  kat->scope = *scope;
  kat->process_row = process_row;
  kat->account_id = *account_id;
  kat->provider_name
    = GNUNET_strdup (provider_name);
  if (NULL != provider_user_id)
    kat->provider_user_id
      = GNUNET_strdup (provider_user_id);
  if (NULL != provider_legitimization_id)
    kat->provider_legitimization_id
      = GNUNET_strdup (provider_legitimization_id);
  kat->expiration = expiration;
  kat->attributes = json_incref ((json_t*) attributes);
  kat->http_status = http_status;
  kat->response = response;
  kat->cb = cb;
  kat->cb_cls = cb_cls;
  qs = TEH_plugin->lookup_active_legitimization (
    TEH_plugin->cls,
    process_row,
    &kat->measure_index,
    &kat->jmeasures);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    TEH_kyc_finished_cancel (kat);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0);
    TEH_kyc_finished_cancel (kat);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
#if FIXME
  qs = TEH_plugin->lookup_aml_history (
    TEH_plugin->cls,
    account_id,
    &kat->aml_history,
    &kat->kyc_history);
#else
  kat->aml_history = json_array ();
  kat->kyc_history = json_array ();
#endf
  kat->kyc_aml
    = TALER_KYCLOGIC_run_aml_program (kat->attributes,
                                      kat->aml_history,
                                      kat->kyc_history,
                                      kat->jmeasures,
                                      kat->measure_index,
                                      &kyc_aml_finished,
                                      kat);
  if (NULL == kat->kyc_aml)
  {
    GNUNET_break (0);
    TEH_kyc_finished_cancel (kat);
    return NULL;
  }
  return kat;
}


void
TEH_kyc_finished_cancel (struct TEH_KycAmlTrigger *kat)
{
  if (NULL != kat->kyc_aml)
  {
    TALER_KYCLOGIC_run_aml_program_cancel (kat->kyc_aml);
    kat->kyc_aml = NULL;
  }
  GNUNET_free (kat->provider_name);
  GNUNET_free (kat->provider_user_id);
  GNUNET_free (kat->provider_legitimization_id);
  json_decref (kat->jmeasures);
  json_decref (kat->attributes);
  json_decref (kat->aml_history);
  json_decref (kat->kyc_history);
  if (NULL != kat->response)
  {
    MHD_destroy_response (kat->response);
    kat->response = NULL;
  }
  GNUNET_free (kat);
}


bool
TEH_kyc_failed (uint64_t process_row,
                const struct TALER_PaytoHashP *account_id,
                const char *provider_name,
                const char *provider_user_id,
                const char *provider_legitimization_id)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->insert_kyc_failure (
    TEH_plugin->cls,
    process_row,
    account_id,
    provider_name,
    provider_user_id,
    provider_legitimization_id);
  GNUNET_break (qs >= 0);
  return qs >= 0;
}
