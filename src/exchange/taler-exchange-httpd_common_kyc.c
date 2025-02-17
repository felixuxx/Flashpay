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
#include "taler_exchangedb_lib.h"
#include <gnunet/gnunet_common.h>

/**
 * How often do we allow a legitimization rule to
 * automatically trigger the next rule before bailing
 * out?
 */
#define MAX_LEGI_LOOPS 5

/**
 * Enable additional sanity-checks for debugging?
 */
#define EXTRA_CHECK 0


struct TEH_KycMeasureRunContext
{

  /**
   * Our logging scope.
   */
  struct GNUNET_AsyncScopeId scope;

  /**
   * account the operation is about
   */
  struct TALER_NormalizedPaytoHashP account_id;

  /**
   * legitimization process the KYC data is about
   */
  uint64_t process_row;

  /**
   * function to call with the result
   */
  TEH_KycMeasureRunContextCallback cb;

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
   * Measures this KYC process is responding to.
   */
  json_t *jmeasures;

  /**
   * KYC measure the client is (trying to) satisfy.
   */
  uint32_t measure_index;

  /**
   * Handle to an external process that evaluates the
   * need to run AML on the account.
   */
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *kyc_aml;

  /**
   * Task scheduled to return a result asynchronously.
   */
  struct GNUNET_SCHEDULER_Task *async_task;

};


/**
 * Function called with the result of activating a
 * fallback measure.
 *
 * @param cls a `struct TEH_KycMeasureRunContext *`
 * @param fallback_ok true if the fallback was activated
 *    successfully
 * @param requirement_row row of
 *    new KYC requirement that was created, 0 for none
 */
static void
fallback_result_cb (void *cls,
                    bool fallback_ok,
                    uint64_t requirement_row)
{
  struct TEH_KycMeasureRunContext *kat = cls;
  struct GNUNET_AsyncScopeSave old_scope;

  kat->fb = NULL;
  (void) requirement_row;
  GNUNET_async_scope_enter (&kat->scope,
                            &old_scope);
  if (fallback_ok)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Fallback completed (row %llu)\n",
                (unsigned long long) requirement_row);
    kat->cb (kat->cb_cls,
             TALER_EC_EXCHANGE_KYC_AML_PROGRAM_FAILURE,
             NULL);
  }
  else
  {
    GNUNET_break (0);
    kat->cb (kat->cb_cls,
             TALER_EC_EXCHANGE_GENERIC_KYC_FALLBACK_FAILED,
             kat->fallback_name);
  }
  TEH_kyc_run_measure_cancel (kat);
  GNUNET_async_scope_restore (&old_scope);
}


/**
 * Type of a callback that receives a JSON @a result.
 *
 * @param cls closure of type `struct TEH_KycMeasureRunContext *`
 * @param apr AML program result
 */
static void
kyc_aml_finished (
  void *cls,
  const struct TALER_KYCLOGIC_AmlProgramResult *apr)
{
  struct TEH_KycMeasureRunContext *kat = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_AsyncScopeSave old_scope;

  kat->kyc_aml = NULL;
  if (NULL != kat->async_task)
  {
    GNUNET_SCHEDULER_cancel (kat->async_task);
    kat->async_task = NULL;
  }
  GNUNET_async_scope_enter (&kat->scope,
                            &old_scope);
  TEH_plugin->preflight (TEH_plugin->cls);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "AML program finished with status %d\n",
              (int) apr->status);
  qs = TALER_EXCHANGEDB_persist_aml_program_result (
    TEH_plugin,
    kat->process_row,
    &kat->account_id,
    apr);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0);
    kat->cb (kat->cb_cls,
             TALER_EC_GENERIC_DB_STORE_FAILED,
             "persist_aml_program_result");
    TEH_kyc_run_measure_cancel (kat);
    GNUNET_async_scope_restore (&old_scope);
    return;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
  switch (apr->status)
  {
  case TALER_KYCLOGIC_AMLR_FAILURE:
    if (NULL == apr->details.failure.fallback_measure)
    {
      /* Not sure this can happen (fallback required?),
         but report AML program failure to client */
      GNUNET_break (0);
      kat->cb (kat->cb_cls,
               TALER_EC_EXCHANGE_KYC_AML_PROGRAM_FAILURE,
               NULL);
      break;
    }
    kat->fallback_name
      = GNUNET_strdup (
          apr->details.failure.fallback_measure);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "AML program failed, running fallback %s\n",
                kat->fallback_name);
    kat->fb
      = TEH_kyc_fallback (
          &kat->scope,
          &kat->account_id,
          kat->process_row,
          kat->fallback_name,
          &fallback_result_cb,
          kat);
    if (NULL == kat->fb)
    {
      GNUNET_break (0);
      kat->cb (kat->cb_cls,
               TALER_EC_EXCHANGE_GENERIC_KYC_FALLBACK_UNKNOWN,
               kat->fallback_name);
      break;
    }
    /* continued in fallback_result_cb */
    GNUNET_async_scope_restore (&old_scope);
    return;
  case TALER_KYCLOGIC_AMLR_SUCCESS:
    /* Finally, return result to main handler */
    kat->cb (kat->cb_cls,
             TALER_EC_NONE,
             0);
    break;
  }
  TEH_kyc_run_measure_cancel (kat);
  GNUNET_async_scope_restore (&old_scope);
}


void
TEH_kyc_run_measure_cancel (struct TEH_KycMeasureRunContext *kat)
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
  if (NULL != kat->async_task)
  {
    GNUNET_SCHEDULER_cancel (kat->async_task);
    kat->async_task = NULL;
  }
  GNUNET_free (kat->fallback_name);
  json_decref (kat->jmeasures);
  GNUNET_free (kat);
}


enum GNUNET_DB_QueryStatus
TEH_kyc_store_attributes (
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *account_id,
  const char *provider_name,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Absolute expiration,
  const json_t *new_attributes)
{
  enum GNUNET_DB_QueryStatus qs;
  unsigned int birthday = 0;
  size_t eas = 0;
  void *ea = NULL;

  if (TEH_age_restriction_enabled)
  {
    const char *birthdate;

    birthdate = json_string_value (
      json_object_get (new_attributes,
                       TALER_ATTRIBUTE_BIRTHDATE));
    if (NULL != birthdate)
    {
      enum GNUNET_GenericReturnValue ret;

      ret = TALER_parse_coarse_date (birthdate,
                                     &TEH_age_restriction_config.mask,
                                     &birthday);

      if (GNUNET_OK != ret)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Failed to parse birthdate `%s' from KYC attributes of %s\n",
                    birthdate,
                    provider_name);
      }
    }
  }
  if (NULL != new_attributes)
  {
    TALER_CRYPTO_kyc_attributes_encrypt (&TEH_attribute_key,
                                         new_attributes,
                                         &ea,
                                         &eas);
  }
  qs = TEH_plugin->persist_kyc_attributes (
    TEH_plugin->cls,
    process_row,
    account_id,
    provider_name,
    provider_user_id,
    provider_legitimization_id,
    birthday,
    expiration,
    eas,
    ea);
  GNUNET_free (ea);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    break;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    break;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0);
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Stored encrypted KYC process #%llu attributes: %d\n",
              (unsigned long long) process_row,
              qs);
  return qs;
}


struct TEH_KycMeasureRunContext *
TEH_kyc_run_measure_for_attributes (
  const struct GNUNET_AsyncScopeId *scope,
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *account_id,
  TEH_KycMeasureRunContextCallback cb,
  void *cb_cls)
{
  struct TEH_KycMeasureRunContext *kat;
  enum GNUNET_DB_QueryStatus qs;

  kat = GNUNET_new (struct TEH_KycMeasureRunContext);
  kat->scope = *scope;
  kat->process_row = process_row;
  kat->account_id = *account_id;
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
    TEH_kyc_run_measure_cancel (kat);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0);
    TEH_kyc_run_measure_cancel (kat);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
  {
    struct TALER_EXCHANGEDB_HistoryBuilderContext hbc = {
      .account = &kat->account_id,
      .db_plugin = TEH_plugin,
      .attribute_key = &TEH_attribute_key
    };

    kat->kyc_aml
      = TALER_KYCLOGIC_run_aml_program (
          kat->jmeasures,
          kat->measure_index,
          &TALER_EXCHANGEDB_current_attributes_builder,
          &hbc,
          &TALER_EXCHANGEDB_current_rule_builder,
          &hbc,
          &TALER_EXCHANGEDB_aml_history_builder,
          &hbc,
          &TALER_EXCHANGEDB_kyc_history_builder,
          &hbc,
          TEH_aml_program_timeout,
          &kyc_aml_finished,
          kat);
  }
  if (NULL == kat->kyc_aml)
  {
    GNUNET_break (0);
    TEH_kyc_run_measure_cancel (kat);
    return NULL;
  }
  return kat;
}


/**
 * Helper task that asynchronously calls the result
 * callback and then cleans up.
 *
 * @param[in] cls a `struct TEH_LegitimizationCheckHandle *`
 */
static void
async_return_measure_result (void *cls)
{
  struct TEH_KycMeasureRunContext *kat = cls;

  kat->async_task = NULL;
  kat->cb (kat->cb_cls,
           TALER_EC_NONE,
           NULL);
  TEH_kyc_run_measure_cancel (kat);
}


struct TEH_KycMeasureRunContext *
TEH_kyc_run_measure_directly (
  const struct GNUNET_AsyncScopeId *scope,
  const struct TALER_KYCLOGIC_Measure *instant_ms,
  const struct TALER_NormalizedPaytoHashP *account_id,
  TEH_KycMeasureRunContextCallback cb,
  void *cb_cls)
{
  struct TEH_KycMeasureRunContext *kat;
  uint64_t legi_measure_serial_id;
  bool bad_kyc_auth;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_FullPayto null_account = {
    .full_payto = NULL
  };

  kat = GNUNET_new (struct TEH_KycMeasureRunContext);
  kat->jmeasures = TALER_KYCLOGIC_measure_to_jmeasures (instant_ms);
  kat->measure_index = 0;
  kat->scope = *scope;
  kat->account_id = *account_id;
  kat->cb = cb;
  kat->cb_cls = cb_cls;

  GNUNET_assert (NULL != kat->jmeasures);

  qs = TEH_plugin->trigger_kyc_rule_for_account (
    TEH_plugin->cls,
    null_account,
    account_id,
    NULL,
    NULL,
    kat->jmeasures,
    0, /* no particular priority */
    &legi_measure_serial_id,
    &bad_kyc_auth);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    TEH_kyc_run_measure_cancel (kat);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0);
    TEH_kyc_run_measure_cancel (kat);
    return NULL;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }

  if (0 !=
      strcasecmp (instant_ms->check_name,
                  "SKIP"))
  {
    /* Not an instant measure, it's enough to trigger it.
       The AMP will be run later. */
    kat->async_task
      = GNUNET_SCHEDULER_add_now (
          &async_return_measure_result,
          kat);
    return kat;
  }

  qs = TEH_plugin->insert_kyc_requirement_process (
    TEH_plugin->cls,
    account_id,
    0, /* measure index */
    legi_measure_serial_id,
    "SKIP",
    NULL, /* provider_account_id */
    NULL, /* provider_legitimziation_id */
    &kat->process_row);
  if (qs < 0)
  {
    GNUNET_break (0);
    TEH_kyc_run_measure_cancel (kat);
    return NULL;
  }
  {
    struct TALER_EXCHANGEDB_HistoryBuilderContext hbc = {
      .account = &kat->account_id,
      .db_plugin = TEH_plugin,
      .attribute_key = &TEH_attribute_key
    };

    kat->kyc_aml
      = TALER_KYCLOGIC_run_aml_program3 (
          instant_ms,
          &TALER_EXCHANGEDB_current_attributes_builder,
          &hbc,
          &TALER_EXCHANGEDB_current_rule_builder,
          &hbc,
          &TALER_EXCHANGEDB_aml_history_builder,
          &hbc,
          &TALER_EXCHANGEDB_kyc_history_builder,
          &hbc,
          TEH_aml_program_timeout,
          &kyc_aml_finished,
          kat);
  }
  if (NULL == kat->kyc_aml)
  {
    GNUNET_break (0);
    TEH_kyc_run_measure_cancel (kat);
    return NULL;
  }
  return kat;
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
  struct TALER_NormalizedPaytoHashP account_id;

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
          "FALLBACK",
          NULL,
          NULL,
          apr->details.failure.error_message,
          apr->details.failure.ec))
    {
      /* triple-bad: error during error handling of fallback */
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

  qs = TEH_plugin->insert_kyc_measure_result (
    TEH_plugin->cls,
    fb->orig_requirement_row,
    &fb->account_id,
    apr->details.success.expiration_time,
    apr->details.success.account_properties,
    apr->details.success.new_rules,
    apr->details.success.to_investigate,
    apr->details.success.num_events,
    apr->details.success.events);
  if (qs < 0)
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
  const struct TALER_NormalizedPaytoHashP *account_id,
  uint64_t orig_requirement_row,
  const char *fallback_measure,
  TEH_KycAmlFallbackCallback cb,
  void *cb_cls)
{
  struct TEH_KycAmlFallback *fb;
  struct TALER_KYCLOGIC_KycCheckContext kcc;

  if (GNUNET_OK !=
      TALER_KYCLOGIC_get_original_measure (
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
    struct TALER_EXCHANGEDB_HistoryBuilderContext hbc = {
      .account = &fb->account_id,
      .db_plugin = TEH_plugin,
      .attribute_key = &TEH_attribute_key
    };

    /* check was set to 'SKIP', run program immediately */
    fb->aprh
      = TALER_KYCLOGIC_run_aml_program2 (
          kcc.prog_name,
          kcc.context,
          &TALER_EXCHANGEDB_current_attributes_builder,
          &hbc,
          &TALER_EXCHANGEDB_current_rule_builder,
          &hbc,
          &TALER_EXCHANGEDB_aml_history_builder,
          &hbc,
          &TALER_EXCHANGEDB_kyc_history_builder,
          &hbc,
          TEH_aml_program_timeout,
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
    bool bad_kyc_auth;
    struct TALER_FullPayto null_account = {
      .full_payto = NULL
    };

    jmeasures = TALER_KYCLOGIC_check_to_jmeasures (&kcc);
    qs = TEH_plugin->trigger_kyc_rule_for_account (
      TEH_plugin->cls,
      null_account, /* account_id is already in wire targets */
      account_id,
      NULL, /* account_pub */
      NULL, /* merchant_pub */
      jmeasures,
      65536, /* high priority (does it matter?) */
      &fb->requirement_row,
      &bad_kyc_auth);
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
  const struct TALER_NormalizedPaytoHashP *account_id,
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


struct TEH_LegitimizationCheckHandle
{
  /**
   * Function to call with the result.
   */
  TEH_LegitimizationCheckCallback result_cb;

  /**
   * Closure for @e result_cb.
   */
  void *result_cb_cls;

  /**
   * Task scheduled to return a result asynchronously.
   */
  struct GNUNET_SCHEDULER_Task *async_task;

  /**
   * Handle to asynchronously running instant measure.
   */
  struct TEH_KycMeasureRunContext *kat;

  /**
   * Handle for the task that gets us the latest
   * applicable rules.
   */
  struct TALER_EXCHANGEDB_RuleUpdater *ru;

  /**
   * Payto-URI of the account.
   */
  struct TALER_FullPayto payto_uri;

  /**
   * Amount iterator to call to check for amounts.
   */
  TALER_KYCLOGIC_KycAmountIterator ai;

  /**
   * Closure for @e ai.
   */
  void *ai_cls;

  /**
   * Handle to AML program we are running, or NULL for none.
   */
  struct TEH_KycMeasureRunContext *measure_run_ctx;

  /**
   * Hash of @e payto_uri.
   */
  struct TALER_NormalizedPaytoHashP h_payto;

  /**
   * Public key of the account. We should associate this public
   * key with the account if @e have_account_pub is true.  Do not
   * confuse with @e lcr.kyc.have_account_pub which refers to us
   * already having an @e lcr.kyc.account_pub in the database for
   * the given @e h_payto.
   */
  union TALER_AccountPublicKeyP account_pub;

  /**
   * Public key of the merchant.  Checks that the KYC
   * data was actually provided for this merchant if
   * @e have_merchant_pub is true, and if not rejects
   * the operation.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Our request scope for logging.
   */
  struct GNUNET_AsyncScopeId scope;

  /**
   * Legitimization result we have been building and
   * should return.
   */
  struct TEH_LegitimizationCheckResult lcr;

  /**
   * Event we were triggered for.
   */
  enum TALER_KYCLOGIC_KycTriggerEvent et;

  /**
   * Number of instant rule triggers we have experienced
   * in this check already.
   */
  unsigned int rerun;

  /**
   * Do we have @e account_pub?
   */
  bool have_account_pub;

  /**
   * Do we have @e merchant_pub?
   */
  bool have_merchant_pub;

  /**
   * Set to true if the merchant public key does not
   * match the public key we have on file for this
   * target account *and* a rule actually triggered
   * for this operation (and thus a new KYC AUTH is
   * required).
   */
  bool bad_kyc_auth;

};


/**
 * Helper task that asynchronously calls the result
 * callback and then cleans up.
 *
 * @param[in] cls a `struct TEH_LegitimizationCheckHandle *`
 */
static void
async_return_legi_result (void *cls)
{
  struct TEH_LegitimizationCheckHandle *lch = cls;
  struct GNUNET_AsyncScopeSave old_scope;

  lch->async_task = NULL;
  GNUNET_async_scope_enter (&lch->scope,
                            &old_scope);
  lch->result_cb (lch->result_cb_cls,
                  &lch->lcr);
  lch->lcr.response = NULL;
  TEH_legitimization_check_cancel (lch);
  GNUNET_async_scope_restore (&old_scope);
}


/**
 * The legitimization process failed, return an error
 * response.
 *
 * @param[in,out] lch legitimization check that failed
 * @param ec error code to return
 * @param details error details to return (can be NULL)
 */
static void
legi_fail (struct TEH_LegitimizationCheckHandle *lch,
           enum TALER_ErrorCode ec,
           const char *details)
{
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Legitimziation process failed: %s (%s)\n",
              TALER_ErrorCode_get_hint (ec),
              details);
  lch->lcr.http_status
    = TALER_ErrorCode_get_http_status (ec);
  lch->lcr.response
    = TALER_MHD_make_error (
        ec,
        details);
  lch->async_task
    = GNUNET_SCHEDULER_add_now (
        &async_return_legi_result,
        lch);
}


/**
 * Actually (re)-run the legitimization check @a lch.
 *
 * @param[in,out] lch legitimization check to run
 */
static void
legitimization_check_run (
  struct TEH_LegitimizationCheckHandle *lch);


/**
 * Function called after the KYC-AML trigger is done.
 *
 * @param cls must be a `struct TEH_LegitimizationCheckHandle *`
 * @param ec error code or 0 on success
 * @param detail error message or NULL on success / no info
 */
static void
legi_check_aml_trigger_cb (
  void *cls,
  enum TALER_ErrorCode ec,
  const char *detail)
{
  struct TEH_LegitimizationCheckHandle *lch = cls;

  lch->kat = NULL;
  if (TALER_EC_NONE != ec)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "AML program failed: %s (%s, %d)\n",
                TALER_ErrorCode_get_hint (ec),
                detail,
                (int) ec);
    lch->lcr.http_status = MHD_HTTP_INTERNAL_SERVER_ERROR;
    lch->lcr.response = TALER_MHD_make_error (
      ec,
      detail);
    lch->async_task
      = GNUNET_SCHEDULER_add_now (
          &async_return_legi_result,
          lch);
    return;
  }
  /* re-run the check, we got new rules! */
  if (lch->rerun > MAX_LEGI_LOOPS)
  {
    /* deep recursion not allowed, abort! */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Deep recursion (> %u) detected in AML programs, aborting\n",
                (unsigned int) MAX_LEGI_LOOPS);
    legi_fail (lch,
               TALER_EC_EXCHANGE_KYC_RECURSIVE_RULE_DETECTED,
               NULL);
    return;
  }
  lch->rerun++;
  legitimization_check_run (lch);
}


/**
 * Setup legitimization check.
 *
 * @param scope scope for logging
 * @param et type of event we are checking
 * @param payto_uri account we are checking for
 * @param h_payto hash of @a payto_uri
 * @param account_pub public key to enable for the
 *    KYC authorization, NULL if not known
 * @param ai callback to get amounts involved historically
 * @param ai_cls closure for @a ai
 * @param result_cb function to call with the result
 * @param result_cb_cls closure for @a result_cb
 * @return handle for the operation
 */
static struct TEH_LegitimizationCheckHandle *
setup_legitimization_check (
  const struct GNUNET_AsyncScopeId *scope,
  enum TALER_KYCLOGIC_KycTriggerEvent et,
  const struct TALER_FullPayto payto_uri,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const union TALER_AccountPublicKeyP *account_pub,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  TEH_LegitimizationCheckCallback result_cb,
  void *result_cb_cls)
{
  struct TEH_LegitimizationCheckHandle *lch;

#if EXTRA_CHECK
  {
    struct TALER_NormalizedPaytoHashP npt;

    TALER_full_payto_normalize_and_hash (payto_uri,
                                         &npt);
    GNUNET_assert (0 ==
                   GNUNET_memcmp (&npt,
                                  h_payto));
  }
#endif
  lch = GNUNET_new (struct TEH_LegitimizationCheckHandle);
  lch->scope = *scope;
  lch->et = et;
  lch->payto_uri.full_payto
    = GNUNET_strdup (payto_uri.full_payto);
  lch->h_payto = *h_payto;
  if (NULL != account_pub)
  {
    lch->account_pub = *account_pub;
    lch->have_account_pub = true;
  }
  lch->ai = ai;
  lch->ai_cls = ai_cls;
  lch->result_cb = result_cb;
  lch->result_cb_cls = result_cb_cls;
  return lch;
}


struct TEH_LegitimizationCheckHandle *
TEH_legitimization_check (
  const struct GNUNET_AsyncScopeId *scope,
  enum TALER_KYCLOGIC_KycTriggerEvent et,
  const struct TALER_FullPayto payto_uri,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const union TALER_AccountPublicKeyP *account_pub,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  TEH_LegitimizationCheckCallback result_cb,
  void *result_cb_cls)
{
  struct TEH_LegitimizationCheckHandle *lch;

  lch = setup_legitimization_check (scope,
                                    et,
                                    payto_uri,
                                    h_payto,
                                    account_pub,
                                    ai,
                                    ai_cls,
                                    result_cb,
                                    result_cb_cls);
  legitimization_check_run (lch);
  return lch;
}


struct TEH_LegitimizationCheckHandle *
TEH_legitimization_check2 (
  const struct GNUNET_AsyncScopeId *scope,
  enum TALER_KYCLOGIC_KycTriggerEvent et,
  const struct TALER_FullPayto payto_uri,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  TEH_LegitimizationCheckCallback result_cb,
  void *result_cb_cls)
{
  struct TEH_LegitimizationCheckHandle *lch;

  lch = setup_legitimization_check (scope,
                                    et,
                                    payto_uri,
                                    h_payto,
                                    NULL,
                                    ai,
                                    ai_cls,
                                    result_cb,
                                    result_cb_cls);
  lch->merchant_pub = *merchant_pub;
  lch->have_merchant_pub = true;
  legitimization_check_run (lch);
  return lch;
}


/**
 * The KYC check failed because KYC auth is required
 * to match and it does not.
 *
 * @param[in,out] lch legitimization check to fail
 */
static void
fail_kyc_auth (struct TEH_LegitimizationCheckHandle *lch)
{
  lch->lcr.kyc.requirement_row = 0;
  lch->lcr.kyc.ok = false;
  lch->lcr.bad_kyc_auth = true;
  lch->lcr.expiration_date
    = GNUNET_TIME_UNIT_FOREVER_TS;
  memset (&lch->lcr.next_threshold,
          0,
          sizeof (struct TALER_Amount));
  lch->lcr.http_status = 0;
  lch->lcr.response = NULL;
  lch->async_task
    = GNUNET_SCHEDULER_add_now (
        &async_return_legi_result,
        lch);
}


/**
 * Function called to iterate over KYC-relevant
 * transaction amounts for a particular time range.
 * Called within a database transaction, so must
 * not start a new one.
 *
 * Given that there *is* a KYC requirement, we also
 * check if the kyc_auth_bad is set and react
 * accordingly.
 *
 * @param cls closure, a `struct TEH_LegitimizationCheckHandle *`
 * @param limit maximum time-range for which events
 *        should be fetched (timestamp in the past)
 * @param cb function to call on each event found,
 *        events must be returned in reverse chronological
 *        order
 * @param cb_cls closure for @a cb
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
amount_iterator_wrapper_cb (
  void *cls,
  struct GNUNET_TIME_Absolute limit,
  TALER_EXCHANGEDB_KycAmountCallback cb,
  void *cb_cls)
{
  struct TEH_LegitimizationCheckHandle *lch = cls;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC: Checking amounts until %s\n",
              GNUNET_TIME_absolute2s (limit));
  if (lch->lcr.bad_kyc_auth)
  {
    /* We *do* have applicable KYC rules *and* the
       target_pub does not match the merchant_pub,
       so we indeed have a problem! */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC: Mismatch between merchant_pub and target_pub is relevant!\n");
    lch->bad_kyc_auth = true;
  }
  return lch->ai (lch->ai_cls,
                  limit,
                  cb,
                  cb_cls);
}


/**
 * Function called with the current rule set. Called with an open
 * database transaction.
 *
 * @param cls a `struct TEH_LegitimizationCheckHandle *`
 * @param rur includes legitimziation rule set that applies to the account
 *   (owned by callee, callee must free the lrs!)
 */
static void
current_rules_cb (
  void *cls,
  struct TALER_EXCHANGEDB_RuleUpdaterResult *rur)
{
  struct TEH_LegitimizationCheckHandle *lch = cls;
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs = rur->lrs;
  struct GNUNET_AsyncScopeSave old_scope;
  enum GNUNET_DB_QueryStatus qs;
  const struct TALER_KYCLOGIC_KycRule *requirement;
  const struct TALER_KYCLOGIC_Measure *instant_ms;

  GNUNET_async_scope_enter (&lch->scope,
                            &old_scope);
  if (TALER_EC_NONE != rur->ec)
  {
    /* rollback should not be needed, but better be safe */
    TEH_plugin->rollback (TEH_plugin->cls);
    legi_fail (lch,
               rur->ec,
               rur->hint);
    goto cleanup;
  }

  qs = TALER_KYCLOGIC_kyc_test_required (
    lch->et,
    lrs,
    &amount_iterator_wrapper_cb,
    lch,
    &requirement,
    &lch->lcr.next_threshold);
  if (qs < 0)
  {
    GNUNET_break (0);
    TEH_plugin->rollback (TEH_plugin->cls);
    legi_fail (lch,
               TALER_EC_GENERIC_DB_FETCH_FAILED,
               "kyc_test_required");
    goto cleanup;
  }
  if (lch->bad_kyc_auth)
  {
    qs = TEH_plugin->commit (TEH_plugin->cls);
    if (0 > qs)
    {
      legi_fail (lch,
                 TALER_EC_GENERIC_DB_COMMIT_FAILED,
                 "kyc_test_required");
      goto cleanup;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC auth required\n");
    fail_kyc_auth (lch);
    goto cleanup;
  }

  if (NULL == requirement)
  {
    qs = TEH_plugin->commit (TEH_plugin->cls);
    if (0 > qs)
    {
      legi_fail (lch,
                 TALER_EC_GENERIC_DB_COMMIT_FAILED,
                 "kyc_test_required");
      goto cleanup;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC check passed\n");
    lch->lcr.kyc.ok = true;
    lch->lcr.expiration_date
      = TALER_KYCLOGIC_rules_get_expiration (lrs);
    memset (&lch->lcr.next_threshold,
            0,
            sizeof (struct TALER_Amount));
    /* return success! */
    lch->async_task
      = GNUNET_SCHEDULER_add_now (
          &async_return_legi_result,
          lch);
    goto cleanup;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC requirement is %s\n",
              TALER_KYCLOGIC_rule2s (requirement));
  instant_ms
    = TALER_KYCLOGIC_rule_get_instant_measure (
        requirement);
  if (NULL != instant_ms)
  {
    /* We have an 'instant' measure which means we must run the
       AML program immediately instead of waiting for the account owner
       to select some measure and contribute their KYC data. */

    lch->kat = TEH_kyc_run_measure_directly (
      &lch->scope,
      instant_ms,
      &lch->h_payto,
      &legi_check_aml_trigger_cb,
      lch
      );
    if (NULL == lch->kat)
    {
      GNUNET_break (0);
      TEH_plugin->rollback (TEH_plugin->cls);
      legi_fail (lch,
                 TALER_EC_EXCHANGE_KYC_AML_PROGRAM_FAILURE,
                 NULL);
    }
    qs = TEH_plugin->commit (TEH_plugin->cls);
    if (0 > qs)
    {
      legi_fail (lch,
                 TALER_EC_GENERIC_DB_COMMIT_FAILED,
                 "kyc_test_required");
      goto cleanup;
    }
    goto cleanup;
  }

  /* No instant measure, store all measures in the database and
     wait for the user to select one (via /kyc-info) and to then
     provide the data. */
  lch->lcr.kyc.ok = false;
  {
    json_t *jmeasures;

    jmeasures = TALER_KYCLOGIC_rule_to_measures (requirement);
    qs = TEH_plugin->trigger_kyc_rule_for_account (
      TEH_plugin->cls,
      lch->payto_uri,
      &lch->h_payto,
      lch->have_account_pub ? &lch->account_pub : NULL,
      lch->have_merchant_pub ? &lch->merchant_pub : NULL,
      jmeasures,
      TALER_KYCLOGIC_rule2priority (requirement),
      &lch->lcr.kyc.requirement_row,
      &lch->lcr.bad_kyc_auth);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "trigger_kyc_rule_for_account-1 on %d/%d returned %d/%llu/%d\n",
                lch->have_account_pub,
                lch->have_merchant_pub,
                (int) qs,
                (unsigned long long) lch->lcr.kyc.requirement_row,
                lch->lcr.bad_kyc_auth);
    json_decref (jmeasures);
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_break (0);
    TEH_plugin->rollback (TEH_plugin->cls);
    legi_fail (lch,
               TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
               "trigger_kyc_rule_for_account");
    goto cleanup;
  }
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    TEH_plugin->rollback (TEH_plugin->cls);
    legi_fail (lch,
               TALER_EC_GENERIC_DB_STORE_FAILED,
               "trigger_kyc_rule_for_account");
    goto cleanup;
  }
  qs = TEH_plugin->commit (TEH_plugin->cls);
  if (0 > qs)
  {
    legi_fail (lch,
               TALER_EC_GENERIC_DB_COMMIT_FAILED,
               "kyc_test_required");
    goto cleanup;
  }
  /* return success! */
  TEH_plugin->preflight (TEH_plugin->cls);
  lch->async_task
    = GNUNET_SCHEDULER_add_now (
        &async_return_legi_result,
        lch);
cleanup:
  TALER_KYCLOGIC_rules_free (lrs);
  GNUNET_async_scope_restore (&old_scope);
}


static void
legitimization_check_run (
  struct TEH_LegitimizationCheckHandle *lch)
{
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs = NULL;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_AsyncScopeSave old_scope;
  enum GNUNET_GenericReturnValue res;

  if (! TEH_enable_kyc)
  {
    /* AML/KYC disabled, just immediately return success! */
    lch->lcr.kyc.requirement_row = 0;
    lch->lcr.kyc.ok = true;
    lch->lcr.bad_kyc_auth = false;
    lch->lcr.expiration_date
      = GNUNET_TIME_UNIT_FOREVER_TS;
    memset (&lch->lcr.next_threshold,
            0,
            sizeof (struct TALER_Amount));
    lch->lcr.http_status = 0;
    lch->lcr.response = NULL;
    lch->async_task
      = GNUNET_SCHEDULER_add_now (
          &async_return_legi_result,
          lch);
    return;
  }
  GNUNET_async_scope_enter (&lch->scope,
                            &old_scope);
  res = TEH_plugin->start (TEH_plugin->cls,
                           "legi-check-run-start-precheck");
  if (GNUNET_OK != res)
  {
    GNUNET_break (0);
    legi_fail (lch,
               TALER_EC_GENERIC_DB_START_FAILED,
               "legi-check-run-start-precheck");
    return;
  }
  {
    json_t *jrules;
    bool no_account_pub;
    bool no_reserve_pub;

    qs = TEH_plugin->get_kyc_rules (
      TEH_plugin->cls,
      &lch->h_payto,
      &no_account_pub,
      &lch->lcr.kyc.account_pub,
      &no_reserve_pub,
      &lch->lcr.reserve_pub.reserve_pub,
      &jrules);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_break (0);
      TEH_plugin->rollback (TEH_plugin->cls);
      legi_fail (lch,
                 TALER_EC_GENERIC_DB_FETCH_FAILED,
                 "get_kyc_rules");
      GNUNET_async_scope_restore (&old_scope);
      return;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      break;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "get_kyc_rules returned %d/%d/%d/%d\n",
                (int) qs,
                ! no_account_pub,
                ! no_reserve_pub,
                NULL != jrules);

    lch->lcr.kyc.have_account_pub
      = ! no_account_pub;
    lch->lcr.have_reserve_pub
      = ! no_reserve_pub;
    if ( (lch->have_merchant_pub) &&
         ( (! lch->lcr.kyc.have_account_pub) ||
           (0 !=
            GNUNET_memcmp (&lch->merchant_pub,
                           &lch->lcr.kyc.account_pub.merchant_pub)) ) &&
         ( (! lch->lcr.have_reserve_pub) ||
           (0 !=
            GNUNET_memcmp (&lch->merchant_pub,
                           &lch->lcr.reserve_pub.merchant_pub)) ) )
    {
      if (NULL == jrules)
      {
        /* We do not have custom rules, defer enforcing merchant_pub
           match until we actually have deposit constraints */
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "KYC: merchant_pub given but no known target_pub(%d)/reserve_pub(%d) match (%d)!\n",
                    lch->lcr.kyc.have_account_pub,
                    lch->lcr.have_reserve_pub,
                    (int) qs);
        lch->lcr.bad_kyc_auth = true;
      }
      else
      {
        /* We have custom rules, but the target_pub for
           those custom rules does not match the
           merchant_pub. Fail the KYC process! */
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "KYC: merchant_pub does not match target_pub of custom rules!\n");
        TEH_plugin->rollback (TEH_plugin->cls);
        json_decref (jrules);
        fail_kyc_auth (lch);
        goto cleanup;
      }
    }

    /* parse and free jrules (if we had any) */
    if (NULL != jrules)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "KYC: have custom KYC rules for this account!\n");
      lrs = TALER_KYCLOGIC_rules_parse (jrules);
      GNUNET_break (NULL != lrs);
      /* Fall back to default rules on parse error! */
      json_decref (jrules);
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "KYC: default KYC rules apply to this account!\n");
    }
  }

  if (NULL != lrs)
  {
    TEH_plugin->rollback (TEH_plugin->cls);
    lch->ru = TALER_EXCHANGEDB_update_rules (TEH_plugin,
                                             &TEH_attribute_key,
                                             &lch->h_payto,
                                             &current_rules_cb,
                                             lch);
  }
  else
  {
    struct TALER_EXCHANGEDB_RuleUpdaterResult rur = { 0 };

    current_rules_cb (lch,
                      &rur);
  }
cleanup:
  GNUNET_async_scope_restore (&old_scope);
}


void
TEH_legitimization_check_cancel (
  struct TEH_LegitimizationCheckHandle *lch)
{
  if (NULL != lch->async_task)
  {
    GNUNET_SCHEDULER_cancel (lch->async_task);
    lch->async_task = NULL;
  }
  if (NULL != lch->kat)
  {
    TEH_kyc_run_measure_cancel (lch->kat);
    lch->kat = NULL;
  }
  if (NULL != lch->measure_run_ctx)
  {
    TEH_kyc_run_measure_cancel (lch->measure_run_ctx);
    lch->measure_run_ctx = NULL;
  }
  if (NULL != lch->lcr.response)
  {
    MHD_destroy_response (lch->lcr.response);
    lch->lcr.response = NULL;
  }
  GNUNET_free (lch->payto_uri.full_payto);
  GNUNET_free (lch);
}
