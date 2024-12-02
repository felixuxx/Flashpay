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
 * @file exchangedb_aml.c
 * @brief helper function to handle AML programs
 * @author Christian Grothoff
 */
#include "taler_exchangedb_plugin.h"
#include "taler_exchangedb_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_common.h>

/**
 * Maximum recursion depth we allow for AML programs.
 * Basically, after this number of "skip" processes
 * we forcefully terminate the recursion and fail hard.
 */
#define MAX_DEPTH 16


enum GNUNET_DB_QueryStatus
TALER_EXCHANGEDB_persist_aml_program_result (
  struct TALER_EXCHANGEDB_Plugin *plugin,
  uint64_t process_row,
  const char *provider_name,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  const json_t *attributes,
  const struct TALER_AttributeEncryptionKeyP *attribute_key,
  unsigned int birthday,
  struct GNUNET_TIME_Absolute expiration,
  const struct TALER_NormalizedPaytoHashP *account_id,
  const struct TALER_KYCLOGIC_AmlProgramResult *apr)
{
  enum GNUNET_DB_QueryStatus qs;
  size_t eas = 0;
  void *ea = NULL;

  /* TODO: also clear lock on AML program (#9303) */
  switch (apr->status)
  {
  case TALER_KYCLOGIC_AMLR_FAILURE:
    qs = plugin->insert_kyc_failure (
      plugin->cls,
      process_row,
      account_id,
      provider_name,
      provider_user_id,
      provider_legitimization_id,
      apr->details.failure.error_message,
      apr->details.failure.ec);
    GNUNET_break (qs > 0);
    return qs;
  case TALER_KYCLOGIC_AMLR_SUCCESS:
    if (NULL != attributes)
    {
      TALER_CRYPTO_kyc_attributes_encrypt (attribute_key,
                                           attributes,
                                           &ea,
                                           &eas);
    }
    qs = plugin->insert_kyc_measure_result (
      plugin->cls,
      process_row,
      account_id,
      birthday,
      GNUNET_TIME_timestamp_get (),
      provider_name,
      provider_user_id,
      provider_legitimization_id,
      expiration,
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
                (unsigned long long) process_row,
                qs);
    GNUNET_break (qs > 0);
    return qs;
  }
  GNUNET_assert (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


struct TALER_EXCHANGEDB_RuleUpdater
{
  /**
   * database plugin to use
   */
  struct TALER_EXCHANGEDB_Plugin *plugin;

  /**
   * key to use to decrypt attributes
   */
  struct TALER_AttributeEncryptionKeyP attribute_key;

  /**
   * account to get the rule set for
   */
  struct TALER_NormalizedPaytoHashP account;

  /**
   * function to call with the result
   */
  TALER_EXCHANGEDB_CurrentRulesCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Current rule set we are working on.
   */
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs;

  /**
   * Task for asynchronous continuations.
   */
  struct GNUNET_SCHEDULER_Task *t;

  /**
   * Handle to running AML program.
   */
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *amlh;

  /**
   * Error hint to return with @e ec.
   */
  const char *hint;

  /**
   * Row the rule set in @a lrs is based on.
   */
  uint64_t legitimization_outcome_last_row;

  /**
   * Taler error code to return.
   */
  enum TALER_ErrorCode ec;

  /**
   * Counter used to limit recursion depth.
   */
  unsigned int depth;
};


/**
 * Function that finally returns the result to the application and
 * cleans up.
 *
 * @param[in,out] cls a `struct TALER_EXCHANGEDB_RuleUpdater *`
 */
static void
return_result (void *cls)
{
  struct TALER_EXCHANGEDB_RuleUpdater *ru = cls;
  struct TALER_EXCHANGEDB_RuleUpdaterResult rur = {
    .legitimization_outcome_last_row = ru->legitimization_outcome_last_row,
    .lrs = ru->lrs,
    .ec = ru->ec,
  };

  ru->t = NULL;
  ru->cb (ru->cb_cls,
          &rur);
  ru->lrs = NULL;
  TALER_EXCHANGEDB_update_rules_cancel (ru);
}


/**
 * Finish the update returning the current lrs in @a ru.
 *
 * @param[in,out] ru account we are processing
 */
static void
finish_update (struct TALER_EXCHANGEDB_RuleUpdater *ru)
{
  GNUNET_break (TALER_EC_NONE == ru->ec);
  ru->t = GNUNET_SCHEDULER_add_now (&return_result,
                                    ru);
}


/**
 * Fail the update with the given @a ec and @a hint.
 *
 * @param[in,out] ru account we are processing
 * @param ec error code to fail with
 * @param hint hint to return, can be NULL
 */
static void
fail_update (struct TALER_EXCHANGEDB_RuleUpdater *ru,
             enum TALER_ErrorCode ec,
             const char *hint)
{
  GNUNET_assert (NULL == ru->t);
  ru->plugin->rollback (ru->plugin->cls);
  ru->ec = ec;
  ru->hint = hint;
  ru->t = GNUNET_SCHEDULER_add_now (&return_result,
                                    ru);
}


/**
 * Check the rules in @a ru to see if they are current, and
 * if not begin the updating process.
 *
 * @param[in] ru rule updater context
 */
static void
check_rules (struct TALER_EXCHANGEDB_RuleUpdater *ru);


/**
 * Run the measure @a m in the context of the legitimisation rules
 * of @a ru.
 *
 * @param ru updating context we are using
 * @param m measure we need to run next
 */
static void
run_measure (struct TALER_EXCHANGEDB_RuleUpdater *ru,
             const struct TALER_KYCLOGIC_Measure *m);


/**
 * Function called after AML program was run.
 *
 * @param cls the `struct TALER_EXCHANGEDB_RuleUpdater *`
 * @param apr result of the AML program.
 */
static void
aml_result_callback (
  void *cls,
  const struct TALER_KYCLOGIC_AmlProgramResult *apr)
{
  struct TALER_EXCHANGEDB_RuleUpdater *ru = cls;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_GenericReturnValue res;

  ru->amlh = NULL;
  res = ru->plugin->start (ru->plugin->cls,
                           "aml-persist-aml-program-result");
  if (GNUNET_OK != res)
  {
    GNUNET_break (0);
    fail_update (ru,
                 TALER_EC_GENERIC_DB_START_FAILED,
                 "aml_result_callback");
    return;
  }
  // FIXME: #9303 logic here?

  /* Update database update based on result */
  qs = TALER_EXCHANGEDB_persist_aml_program_result (
    ru->plugin,
    0,   // FIXME: process row - #9303 may give us something here!?
    NULL /* no provider */,
    NULL /* no user ID */,
    NULL /* no legi ID */,
    NULL /* no attributes */,
    &ru->attribute_key,
    0 /* no birthday */,
    GNUNET_TIME_UNIT_FOREVER_ABS,
    &ru->account,
    apr);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    fail_update (ru,
                 TALER_EC_GENERIC_DB_STORE_FAILED,
                 "persist_aml_program_result");
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* Bad, couldn't persist AML result. Try again... */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Serialization issue persisting result of AML program. Restarting.\n");
    fail_update (ru,
                 TALER_EC_GENERIC_DB_SOFT_FAILURE,
                 "persist_aml_program_result");
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* Strange, but let's just continue */
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* normal case */
    break;
  }
  switch (apr->status)
  {
  case TALER_KYCLOGIC_AMLR_SUCCESS:
    TALER_KYCLOGIC_rules_free (ru->lrs);
    ru->lrs = NULL;
    ru->lrs = TALER_KYCLOGIC_rules_parse (apr->details.success.new_rules);
    /* Fall back to default rules on parse error! */
    GNUNET_break (NULL != ru->lrs);
    check_rules (ru);
    return;
  case TALER_KYCLOGIC_AMLR_FAILURE:
    {
      const char *fmn = apr->details.failure.fallback_measure;
      const struct TALER_KYCLOGIC_Measure *m;

      m = TALER_KYCLOGIC_get_measure (ru->lrs,
                                      fmn);
      if (NULL == m)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Fallback measure `%s' does not exist (anymore?).\n",
                    fmn);
        TALER_KYCLOGIC_rules_free (ru->lrs);
        ru->lrs = NULL;
        finish_update (ru);
        return;
      }
      run_measure (ru,
                   m);
      return;
    }
  }
  /* This should be impossible */
  GNUNET_assert (0);
}


static void
run_measure (struct TALER_EXCHANGEDB_RuleUpdater *ru,
             const struct TALER_KYCLOGIC_Measure *m)
{
  if (NULL == m)
  {
    /* fall back to default rules */
    TALER_KYCLOGIC_rules_free (ru->lrs);
    ru->lrs = NULL;
    finish_update (ru);
    return;
  }
  ru->depth++;
  if (ru->depth > MAX_DEPTH)
  {
    fail_update (ru,
                 TALER_EC_EXCHANGE_GENERIC_AML_PROGRAM_RECURSION_DETECTED,
                 NULL);
    return;
  }
  if ( (NULL == m->check_name) ||
       (0 ==
        strcasecmp ("skip",
                    m->check_name)) )
  {
    struct TALER_EXCHANGEDB_HistoryBuilderContext hbc = {
      .account = &ru->account,
      .db_plugin = ru->plugin,
      .attribute_key = &ru->attribute_key
    };
    enum GNUNET_DB_QueryStatus qs;

    // FIXME: #9303 logic here?
    qs = ru->plugin->commit (ru->plugin->cls);
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      fail_update (ru,
                   GNUNET_DB_STATUS_SOFT_ERROR == qs
                   ? TALER_EC_GENERIC_DB_SOFT_FAILURE
                   : TALER_EC_GENERIC_DB_COMMIT_FAILED,
                   "current-aml-rule-fetch");
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Check is of type 'skip', running AML program %s.\n",
                m->prog_name);
    ru->amlh = TALER_KYCLOGIC_run_aml_program3 (
      m,
      NULL /* no attributes */,
      &TALER_EXCHANGEDB_current_rule_builder,
      &hbc,
      &TALER_EXCHANGEDB_aml_history_builder,
      &hbc,
      &TALER_EXCHANGEDB_kyc_history_builder,
      &hbc,
      &aml_result_callback,
      ru);
    return;
  }

  /* User MUST pass interactive check */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Measure %s involves check %s\n",
              m->measure_name,
              m->check_name);
  {
    /* activate the measure/check */
    json_t *succ_jmeasures
      = TALER_KYCLOGIC_get_jmeasures (
          ru->lrs,
          m->measure_name);
    bool unknown_account;
    struct GNUNET_TIME_Timestamp last_date;
    enum GNUNET_DB_QueryStatus qs;

    qs = ru->plugin->insert_successor_measure (
      ru->plugin->cls,
      &ru->account,
      GNUNET_TIME_timestamp_get (),
      m->measure_name,
      succ_jmeasures,
      &unknown_account,
      &last_date);
    json_decref (succ_jmeasures);
    switch (qs)
    {
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_log (
        GNUNET_ERROR_TYPE_INFO,
        "Serialization issue!\n");
      fail_update (ru,
                   TALER_EC_GENERIC_DB_SOFT_FAILURE,
                   "insert_successor_measure");
      return;
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      fail_update (ru,
                   TALER_EC_GENERIC_DB_STORE_FAILED,
                   "insert_successor_measure");
      return;
    default:
      break;
    }
  }
  /* The rules remain these rules until the user passes the check */
  finish_update (ru);
}


/**
 * Update the expired legitimization rules in @a ru, checking for
 * expiration first.
 *
 * @param[in,out] ru account we are processing
 */
static void
update_rules (struct TALER_EXCHANGEDB_RuleUpdater *ru)
{
  const struct TALER_KYCLOGIC_Measure *m;

  GNUNET_assert (NULL != ru->lrs);
  GNUNET_assert (GNUNET_TIME_absolute_is_past (
                   TALER_KYCLOGIC_rules_get_expiration (ru->lrs).abs_time));
  m = TALER_KYCLOGIC_rules_get_successor (ru->lrs);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Successor measure is %s.\n",
              m->measure_name);
  run_measure (ru,
               m);
}


static void
check_rules (struct TALER_EXCHANGEDB_RuleUpdater *ru)
{
  ru->depth++;
  if (ru->depth > MAX_DEPTH)
  {
    fail_update (ru,
                 TALER_EC_EXCHANGE_GENERIC_AML_PROGRAM_RECURSION_DETECTED,
                 NULL);
    return;
  }
  if (NULL == ru->lrs)
  {
    /* return NULL, aka default rules */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Default rules apply\n");
    finish_update (ru);
    return;
  }
  if (! GNUNET_TIME_absolute_is_past
        (TALER_KYCLOGIC_rules_get_expiration (ru->lrs).abs_time) )
  {
    /* Rules did not expire, return them! */
    finish_update (ru);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Custom rules expired, updating...\n");
  update_rules (ru);
}


/**
 * Entrypoint that fetches the latest rules from the database
 * and starts processing them.
 *
 * @param[in,out] ru account we are processing
 */
static void
fetch_latest_rules (struct TALER_EXCHANGEDB_RuleUpdater *ru)
{
  enum GNUNET_DB_QueryStatus qs;
  json_t *jnew_rules;
  enum GNUNET_GenericReturnValue res;

  GNUNET_break (NULL == ru->lrs);
  res = ru->plugin->start (ru->plugin->cls,
                           "aml-begin-lookup-rules-by-access-token");
  if (GNUNET_OK != res)
  {
    GNUNET_break (0);
    fail_update (ru,
                 TALER_EC_GENERIC_DB_START_FAILED,
                 "aml_result_callback");
    return;
  }
  qs = ru->plugin->lookup_rules_by_access_token (
    ru->plugin->cls,
    &ru->account,
    &jnew_rules,
    &ru->legitimization_outcome_last_row);
  if (qs < 0)
  {
    GNUNET_break (0);
    fail_update (ru,
                 TALER_EC_GENERIC_DB_FETCH_FAILED,
                 "lookup_rules_by_access_token");
    return;
  }
  if ( (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs) &&
       (NULL != jnew_rules) )
  {
    ru->lrs = TALER_KYCLOGIC_rules_parse (jnew_rules);
    GNUNET_break (NULL != ru->lrs);
    json_decref (jnew_rules);
  }
  check_rules (ru);
}


struct TALER_EXCHANGEDB_RuleUpdater *
TALER_EXCHANGEDB_update_rules (
  struct TALER_EXCHANGEDB_Plugin *plugin,
  const struct TALER_AttributeEncryptionKeyP *attribute_key,
  const struct TALER_NormalizedPaytoHashP *account,
  TALER_EXCHANGEDB_CurrentRulesCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGEDB_RuleUpdater *ru;

  ru = GNUNET_new (struct TALER_EXCHANGEDB_RuleUpdater);
  ru->plugin = plugin;
  ru->attribute_key = *attribute_key;
  ru->account = *account;
  ru->cb = cb;
  ru->cb_cls = cb_cls;
  fetch_latest_rules (ru);
  return ru;
}


void
TALER_EXCHANGEDB_update_rules_cancel (
  struct TALER_EXCHANGEDB_RuleUpdater *ru)
{
  if (NULL != ru->t)
  {
    GNUNET_SCHEDULER_cancel (ru->t);
    ru->t = NULL;
  }
  if (NULL != ru->amlh)
  {
    TALER_KYCLOGIC_run_aml_program_cancel (ru->amlh);
    ru->amlh = NULL;
  }
  if (NULL != ru->lrs)
  {
    TALER_KYCLOGIC_rules_free (ru->lrs);
    ru->lrs = NULL;
  }
  GNUNET_free (ru);
}
