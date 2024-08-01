/*
  This file is part of TALER
  Copyright (C) 2023, 2024 Taler Systems SA

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
   * Handle to fallback processing.
   */
  struct TEH_KycAmlFallback *fb;

  /**
   * Name of the fallback @e fb is running (or NULL).
   */
  char *fallback_name;

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
 * Function called with the result of activating a
 * fallback measure.
 *
 * @param cls a `struct TEH_KycAmlTrigger *`
 * @param result true if the fallback was activated
 *    successfully
 * @param requirement_row row of
 *    new KYC requirement that was created, 0 for none
 */
static void
fallback_result_cb (void *cls,
                    bool result,
                    uint64_t requirement_row)
{
  struct TEH_KycAmlTrigger *kat = cls;
  struct GNUNET_AsyncScopeSave old_scope;

  kat->fb = NULL;
  (void) requirement_row;
  // FIXME: return new requirement_row!?
  GNUNET_async_scope_enter (&kat->scope,
                            &old_scope);
  if (result)
  {
    kat->cb (kat->cb_cls,
             MHD_HTTP_INTERNAL_SERVER_ERROR,
             TALER_MHD_make_error (
               TALER_EC_EXCHANGE_KYC_AML_PROGRAM_FAILURE,
               NULL));
  }
  else
  {
    kat->cb (kat->cb_cls,
             MHD_HTTP_INTERNAL_SERVER_ERROR,
             TALER_MHD_make_error (
               TALER_EC_EXCHANGE_GENERIC_KYC_FALLBACK_FAILED,
               kat->fallback_name));
  }
  TEH_kyc_finished_cancel (kat);
  GNUNET_async_scope_restore (&old_scope);
}


/**
 * Type of a callback that receives a JSON @a result.
 *
 * @param cls closure of type `struct TEH_KycAmlTrigger *`
 * @param apr AML program result
 */
static void
kyc_aml_finished (
  void *cls,
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
    if (! TEH_kyc_failed (
          kat->process_row,
          &kat->account_id,
          kat->provider_name,
          kat->provider_user_id,
          kat->provider_legitimization_id,
          apr->details.failure.error_message,
          apr->details.failure.ec))
    {
      /* double-bad: error during error handling */
      GNUNET_break (0);
      kat->cb (kat->cb_cls,
               MHD_HTTP_INTERNAL_SERVER_ERROR,
               TALER_MHD_make_error (
                 TALER_EC_GENERIC_DB_STORE_FAILED,
                 "insert_kyc_failure"));
      TEH_kyc_finished_cancel (kat);
      GNUNET_async_scope_restore (&old_scope);
      return;
    }
    if (NULL == apr->details.failure.fallback_measure)
    {
      /* Not sure this can happen (fallback required?),
         but report AML program failure to client */
      kat->cb (kat->cb_cls,
               MHD_HTTP_INTERNAL_SERVER_ERROR,
               TALER_MHD_make_error (
                 TALER_EC_EXCHANGE_KYC_AML_PROGRAM_FAILURE,
                 NULL));
      TEH_kyc_finished_cancel (kat);
      GNUNET_async_scope_restore (&old_scope);
      return;
    }
    kat->fallback_name
      = GNUNET_strdup (
          apr->details.failure.fallback_measure);
    kat->fb
      = TEH_kyc_fallback (
          &kat->scope,
          &kat->account_id,
          kat->process_row,
          kat->attributes,
          kat->aml_history,
          kat->kyc_history,
          kat->fallback_name,
          &fallback_result_cb,
          kat);
    if (NULL == kat->fb)
    {
      GNUNET_break (0);
      kat->cb (kat->cb_cls,
               MHD_HTTP_INTERNAL_SERVER_ERROR,
               TALER_MHD_make_error (
                 TALER_EC_EXCHANGE_GENERIC_KYC_FALLBACK_UNKNOWN,
                 kat->fallback_name));
      TEH_kyc_finished_cancel (kat);
      GNUNET_async_scope_restore (&old_scope);
      return;
    }
    GNUNET_async_scope_restore (&old_scope);
    return;
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
    ea);
  GNUNET_free (ea);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Stored encrypted KYC process #%llu attributes: %d\n",
              (unsigned long long) kat->process_row,
              qs);
  if (qs <= 0)
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


/**
 * Function called to expand AML history for the account.
 *
 * @param cls a `json_t *` array to build
 * @param decision_time when was the decision taken
 * @param justification what was the given justification
 * @param decider_pub which key signed the decision
 * @param jproperties what are the new account properties
 * @param jnew_rules what are the new account rules
 * @param to_investigate should AML staff investigate
 *          after the decision
 * @param is_active is this the active decision
 */
static void
add_aml_history_entry (
  void *cls,
  struct GNUNET_TIME_Timestamp decision_time,
  const char *justification,
  const struct TALER_AmlOfficerPublicKeyP *decider_pub,
  const json_t *jproperties,
  const json_t *jnew_rules,
  bool to_investigate,
  bool is_active)
{
  json_t *aml_history = cls;
  json_t *e;

  e = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_timestamp ("decision_time",
                                decision_time),
    GNUNET_JSON_pack_string ("justification",
                             justification),
    GNUNET_JSON_pack_data_auto ("decider_pub",
                                decider_pub),
    GNUNET_JSON_pack_object_incref ("properties",
                                    (json_t *) jproperties),
    GNUNET_JSON_pack_object_incref ("new_rules",
                                    (json_t *) jnew_rules),
    GNUNET_JSON_pack_bool ("to_investigate",
                           to_investigate),
    GNUNET_JSON_pack_bool ("is_active",
                           is_active)
    );
  GNUNET_assert (0 ==
                 json_array_append_new (aml_history,
                                        e));
}


/**
 * Function called to expand KYC history for the account.
 *
 * @param cls a `json_t *` array to build
 * @param provider_name name of the KYC provider
 *    or NULL for none
 * @param finished did the KYC process finish
 * @param error_code error code from the KYC process
 * @param error_message error message from the KYC process,
 *    or NULL for none
 * @param provider_user_id user ID at the provider
 *    or NULL for none
 * @param provider_legitimization_id legitimization process ID at the provider
 *    or NULL for none
 * @param collection_time when was the data collected
 * @param expiration_time when does the collected data expire
 * @param encrypted_attributes_len number of bytes in @a encrypted_attributes
 * @param encrypted_attributes encrypted KYC attributes
 */
static void
add_kyc_history_entry (
  void *cls,
  const char *provider_name,
  bool finished,
  enum TALER_ErrorCode error_code,
  const char *error_message,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Timestamp collection_time,
  struct GNUNET_TIME_Absolute expiration_time,
  size_t encrypted_attributes_len,
  const void *encrypted_attributes)
{
  json_t *kyc_history = cls;
  json_t *attributes;
  json_t *e;

  attributes = TALER_CRYPTO_kyc_attributes_decrypt (
    &TEH_attribute_key,
    encrypted_attributes,
    encrypted_attributes_len);
  e = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string (
      "provider_name",
      provider_name),
    GNUNET_JSON_pack_bool (
      "finished",
      finished),
    TALER_JSON_pack_ec (error_code),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string (
        "error_message",
        error_message)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string (
        "provider_user_id",
        provider_user_id)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string (
        "provider_legitimization_id",
        provider_legitimization_id)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_timestamp (
        "collection_time",
        collection_time)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_timestamp (
        "expiration_time",
        GNUNET_TIME_absolute_to_timestamp (
          expiration_time))),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_object_steal (
        "attributes",
        attributes))
    );

  GNUNET_assert (0 ==
                 json_array_append_new (kyc_history,
                                        e));
}


struct TEH_KycAmlTrigger *
TEH_kyc_finished (
  const struct GNUNET_AsyncScopeId *scope,
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
  kat->aml_history = json_array ();
  kat->kyc_history = json_array ();
  qs = TEH_plugin->lookup_aml_history (
    TEH_plugin->cls,
    account_id,
    &add_aml_history_entry,
    kat->aml_history);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    TEH_kyc_finished_cancel (kat);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* empty history is fine! */
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
  qs = TEH_plugin->lookup_kyc_history (
    TEH_plugin->cls,
    account_id,
    &add_kyc_history_entry,
    kat->kyc_history);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    TEH_kyc_finished_cancel (kat);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* empty history is fine! */
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
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
  if (NULL != kat->fb)
  {
    TEH_kyc_fallback_cancel (kat->fb);
    kat->fb = NULL;
  }
  GNUNET_free (kat->provider_name);
  GNUNET_free (kat->provider_user_id);
  GNUNET_free (kat->provider_legitimization_id);
  GNUNET_free (kat->fallback_name);
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


struct TEH_KycAmlFallback
{

  /**
   * Our logging scope.
   */
  struct GNUNET_AsyncScopeId scope;

  /**
   * Account this is for.
   */
  struct TALER_PaytoHashP account_id;

  /**
   * Function to call when done.
   */
  TEH_KycAmlFallbackCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Handle for asynchronously running AML program.
   */
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *aprh;

  /**
   * Task for asynchronously returning of the result.
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * New requirement row we created, 0 if none.
   */
  uint64_t requirement_row;

  /**
   * Original requirement row the fallback is for.
   */
  uint64_t orig_requirement_row;

  /**
   * True if we failed.
   */
  bool failure;

};


/**
 * Handle result from AML fallback program.
 *
 * @param cls a `struct TEH_KycAmlFallback`
 * @param apr AML program result to handle
 */
static void
handle_aml_fallback_result (
  void *cls,
  const struct TALER_KYCLOGIC_AmlProgramResult *apr)
{
  struct TEH_KycAmlFallback *fb = cls;
  size_t eas;
  void *ea;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_AsyncScopeSave old_scope;

  fb->aprh = NULL;
  GNUNET_async_scope_enter (&fb->scope,
                            &old_scope);
  if (TALER_KYCLOGIC_AMLR_SUCCESS != apr->status)
  {
    if (! TEH_kyc_failed (
          fb->orig_requirement_row,
          &fb->account_id,
          NULL,
          NULL,
          NULL,
          apr->details.failure.error_message,
          apr->details.failure.ec))
    {
      /* tripple-bad: error during error handling of fallback */
      GNUNET_break (0);
      fb->cb (fb->cb_cls,
              false,
              0);
      TEH_kyc_fallback_cancel (fb);
      GNUNET_async_scope_restore (&old_scope);
      return;
    }
    /* Fallback not allowed on fallback */
    GNUNET_break (0);
    fb->cb (fb->cb_cls,
            false,
            0);
    TEH_kyc_fallback_cancel (fb);
    GNUNET_async_scope_restore (&old_scope);
    return;
  }

  {
    json_t *attributes;

    /* empty attributes for fallback */
    attributes = json_object ();
    GNUNET_assert (NULL != attributes);
    TALER_CRYPTO_kyc_attributes_encrypt (&TEH_attribute_key,
                                         attributes,
                                         &ea,
                                         &eas);
    json_decref (attributes);
  }
  qs = TEH_plugin->insert_kyc_attributes (
    TEH_plugin->cls,
    fb->orig_requirement_row,
    &fb->account_id,
    0,
    GNUNET_TIME_timestamp_get (),
    NULL,
    NULL,
    NULL,
    GNUNET_TIME_UNIT_FOREVER_ABS,
    apr->details.success.account_properties,
    apr->details.success.new_rules,
    apr->details.success.to_investigate,
    apr->details.success.num_events,
    apr->details.success.events,
    eas,
    ea);
  GNUNET_free (ea);
  if (qs <= 0)
  {
    GNUNET_break (0);
    fb->cb (fb->cb_cls,
            false,
            0);
    GNUNET_async_scope_restore (&old_scope);
    TEH_kyc_fallback_cancel (fb);
    return;
  }
  /* Finally, return result to main handler */
  fb->cb (fb->cb_cls,
          true,
          0);
  TEH_kyc_fallback_cancel (fb);
  GNUNET_async_scope_restore (&old_scope);
}


/**
 * Helper task function to asynchronously return
 * the result of the operation.
 *
 * @param cls a `struct TEH_KycAmlFallback`.
 */
static void
return_fallback_result (void *cls)
{
  struct TEH_KycAmlFallback *fb = cls;
  struct GNUNET_AsyncScopeSave old_scope;

  fb->task = NULL;
  GNUNET_async_scope_enter (&fb->scope,
                            &old_scope);
  fb->cb (fb->cb_cls,
          ! fb->failure,
          fb->requirement_row);
  TEH_kyc_fallback_cancel (fb);
  GNUNET_async_scope_restore (&old_scope);
}


struct TEH_KycAmlFallback*
TEH_kyc_fallback (
  const struct GNUNET_AsyncScopeId *scope,
  const struct TALER_PaytoHashP *account_id,
  uint64_t orig_requirement_row,
  const json_t *attributes,
  const json_t *aml_history,
  const json_t *kyc_history,
  const char *fallback_measure,
  TEH_KycAmlFallbackCallback cb,
  void *cb_cls)
{
  struct TEH_KycAmlFallback *fb;
  struct TALER_KYCLOGIC_KycCheckContext kcc;

  if (GNUNET_OK !=
      TALER_KYCLOGIC_get_default_measure (
        fallback_measure,
        &kcc))
  {
    /* very bad, could not find fallback measure!? */
    GNUNET_break (0);
    return NULL;
  }
  fb = GNUNET_new (struct TEH_KycAmlFallback);
  fb->scope = *scope;
  fb->account_id = *account_id;
  fb->orig_requirement_row = orig_requirement_row;
  fb->cb = cb;
  fb->cb_cls = cb_cls;
  if (NULL == kcc.check)
  {
    fb->aprh
      = TALER_KYCLOGIC_run_aml_program2 (kcc.prog_name,
                                         attributes,
                                         aml_history,
                                         kyc_history,
                                         kcc.context,
                                         &handle_aml_fallback_result,
                                         fb);
    if (NULL == fb->aprh)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Fallback AML program `%s' unknown\n",
                  kcc.prog_name);
      TEH_kyc_fallback_cancel (fb);
      return NULL;
    }
    return fb;
  }
  /* activate given check */
  {
    json_t *jmeasures;
    enum GNUNET_DB_QueryStatus qs;

    jmeasures = TALER_KYCLOGIC_check_to_measures (&kcc);
    qs = TEH_plugin->trigger_kyc_rule_for_account (
      TEH_plugin->cls,
      NULL, /* account_id is already in wire targets */
      account_id,
      NULL,
      jmeasures,
      65536, /* high priority (does it matter?) */
      &fb->requirement_row);
    json_decref (jmeasures);
    fb->failure = (qs <= 0);
    fb->task = GNUNET_SCHEDULER_add_now (&return_fallback_result,
                                         fb);
  }
  return fb;
}


void
TEH_kyc_fallback_cancel (
  struct TEH_KycAmlFallback *fb)
{
  if (NULL != fb->task)
  {
    GNUNET_SCHEDULER_cancel (fb->task);
    fb->task = NULL;
  }
  if (NULL != fb->aprh)
  {
    TALER_KYCLOGIC_run_aml_program_cancel (fb->aprh);
    fb->aprh = NULL;
  }
  GNUNET_free (fb);
}


bool
TEH_kyc_failed (
  uint64_t process_row,
  const struct TALER_PaytoHashP *account_id,
  const char *provider_name,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  const char *error_message,
  enum TALER_ErrorCode ec)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->insert_kyc_failure (
    TEH_plugin->cls,
    process_row,
    account_id,
    provider_name,
    provider_user_id,
    provider_legitimization_id,
    error_message,
    ec);
  if (qs <= 0)
  {
    GNUNET_break (0);
    return false;
  }
  return true;
}
