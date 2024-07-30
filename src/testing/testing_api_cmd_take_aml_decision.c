/*
  This file is part of TALER
  Copyright (C) 2023, 2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_take_aml_decision.c
 * @brief command for testing /aml/$OFFICER_PUB/decision
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "take_aml_decision" CMD.
 */
struct AmlDecisionState
{

  /**
   * Auditor enable handle while operation is running.
   */
  struct TALER_EXCHANGE_AddAmlDecision *dh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Reference to command to previous set officer command that gives
   * us an officer_priv trait.
   */
  const char *officer_ref_cmd;

  /**
   * Reference to command to previous AML-triggering event that gives
   * us a payto-hash trait.
   */
  const char *account_ref_cmd;

  /**
   * Payto hash of the account we are manipulating the AML settings for.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Justification given.
   */
  const char *justification;

  /**
   * Delay to apply to compute the expiration time
   * for the rules.
   */
  struct GNUNET_TIME_Relative expiration_delay;

  /**
   * Successor measure to activate upon expiration.
   */
  const char *successor_measure;

  /**
   * True to keep AML investigation open.
   */
  bool keep_investigating;

  /**
   * New rules to enforce.
   */
  json_t *new_rules;

  /**
   * Account properties to set.
   */
  json_t *properties;

  /**
   * Expected response code.
   */
  unsigned int expected_response;
};


/**
 * Callback to analyze the /aml-decision/$OFFICER_PUB response, just used to check
 * if the response code is acceptable.
 *
 * @param cls closure.
 * @param adr response details
 */
static void
take_aml_decision_cb (
  void *cls,
  const struct TALER_EXCHANGE_AddAmlDecisionResponse *adr)
{
  struct AmlDecisionState *ds = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &adr->hr;

  ds->dh = NULL;
  if (ds->expected_response != hr->http_status)
  {
    TALER_TESTING_unexpected_status (ds->is,
                                     hr->http_status,
                                     ds->expected_response);
    return;
  }
  TALER_TESTING_interpreter_next (ds->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
take_aml_decision_run (void *cls,
                       const struct TALER_TESTING_Command *cmd,
                       struct TALER_TESTING_Interpreter *is)
{
  struct AmlDecisionState *ds = cls;
  struct GNUNET_TIME_Timestamp now;
  const struct TALER_PaytoHashP *h_payto;
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv;
  const struct TALER_TESTING_Command *ref;
  const char *exchange_url;
  const json_t *jrules;
  const json_t *jmeasures = NULL;
  struct GNUNET_TIME_Timestamp expiration_time
    = GNUNET_TIME_relative_to_timestamp (ds->expiration_delay);
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("rules",
                                  &jrules),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_object_const ("custom_measures",
                                     &jmeasures),
      NULL),
    GNUNET_JSON_spec_end ()
  };
  unsigned int num_rules;
  unsigned int num_measures;

  (void) cmd;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (ds->new_rules,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  {
    const struct TALER_TESTING_Command *exchange_cmd;

    exchange_cmd = TALER_TESTING_interpreter_get_command (is,
                                                          "exchange");
    if (NULL == exchange_cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_exchange_url (exchange_cmd,
                                                         &exchange_url));
  }
  now = GNUNET_TIME_timestamp_get ();
  ds->is = is;
  ref = TALER_TESTING_interpreter_lookup_command (is,
                                                  ds->account_ref_cmd);
  if (NULL == ref)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_h_payto (ref,
                                       &h_payto))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  ref = TALER_TESTING_interpreter_lookup_command (is,
                                                  ds->officer_ref_cmd);
  if (NULL == ref)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_officer_priv (ref,
                                            &officer_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  ds->h_payto = *h_payto;

  num_rules = (unsigned int) json_array_size (jrules);
  num_measures = (unsigned int) json_object_size (jmeasures);
  {
    struct TALER_EXCHANGE_AccountRule rules[
      GNUNET_NZL (num_rules)];
    struct TALER_EXCHANGE_MeasureInformation measures[
      GNUNET_NZL (num_measures)];
    const json_t *jrule;
    size_t i;
    const json_t *jmeasure;
    const char *mname;
    unsigned int off;

    memset (rules,
            0,
            sizeof (rules));
    memset (measures,
            0,
            sizeof (measures));
    json_array_foreach ((json_t *) jrules, i, jrule)
    {
      struct TALER_EXCHANGE_AccountRule *rule = &rules[i];
      const json_t *jmeasures = NULL;
      const char *ots;
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_relative_time ("timeframe",
                                        &rule->timeframe),
        TALER_JSON_spec_amount_any ("threshold",
                                    &rule->threshold),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_array_const ("measures",
                                        &jmeasures),
          NULL),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_uint32 ("display_priority",
                                   &rule->display_priority),
          NULL),
        GNUNET_JSON_spec_string ("operation_type",
                                 &ots),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_bool ("verboten",
                                 &rule->verboten),
          NULL),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_bool ("exposed",
                                 &rule->exposed),
          NULL),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_bool ("is_and_combinator",
                                 &rule->is_and_combinator),
          NULL),
        GNUNET_JSON_spec_end ()
      };
      const char *err_name;
      unsigned int err_line;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (jrule,
                             ispec,
                             &err_name,
                             &err_line))
      {
        GNUNET_break_op (0);
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Malformed rule #%u in field %s\n",
                    (unsigned int) i,
                    err_name);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (GNUNET_OK !=
          TALER_KYCLOGIC_kyc_trigger_from_string (ots,
                                                  &rule->operation_type))
      {
        GNUNET_break_op (0);
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Malformed operation type in rule #%u: %s unknown\n",
                    (unsigned int) i,
                    ots);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (NULL != jmeasures)
      {
        rule->num_measures
          = (unsigned int) json_array_size (jmeasures);
        rule->measures
          = GNUNET_new_array (rule->num_measures,
                              const char *);
        for (unsigned int k = 0; k<rule->num_measures; k++)
          rule->measures[k]
            = json_string_value (
                json_array_get (jmeasures,
                                k));
      }
    }
    off = 0;
    json_object_foreach ((json_t *) jrules, mname, jmeasure)
    {
      struct TALER_EXCHANGE_MeasureInformation *mi = &measures[off++];
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_string ("check_name",
                                   &mi->check_name),
          NULL),
        GNUNET_JSON_spec_string ("prog_name",
                                 &mi->prog_name),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_object_const ("context",
                                         &mi->context),
          NULL),
        GNUNET_JSON_spec_end ()
      };
      const char *err_name;
      unsigned int err_line;

      mi->measure_name = mname;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (jmeasure,
                             ispec,
                             &err_name,
                             &err_line))
      {
        GNUNET_break_op (0);
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Malformed measure %s in field %s\n",
                    mname,
                    err_name);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
    }
    GNUNET_assert (off == num_measures);

    ds->dh = TALER_EXCHANGE_add_aml_decision (
      TALER_TESTING_interpreter_get_context (is),
      exchange_url,
      h_payto,
      now,
      ds->successor_measure,
      expiration_time,
      num_rules,
      rules,
      num_measures,
      measures,
      ds->properties,
      ds->keep_investigating,
      ds->justification,
      officer_priv,
      &take_aml_decision_cb,
      ds);
    for (unsigned int i = 0; i<num_rules; i++)
    {
      struct TALER_EXCHANGE_AccountRule *rule = &rules[i];

      GNUNET_free (rule->measures);
    }
  }

  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "take_aml_decision" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct AmlDecisionState`.
 * @param cmd the command which is being cleaned up.
 */
static void
take_aml_decision_cleanup (void *cls,
                           const struct TALER_TESTING_Command *cmd)
{
  struct AmlDecisionState *ds = cls;

  if (NULL != ds->dh)
  {
    TALER_TESTING_command_incomplete (ds->is,
                                      cmd->label);
    TALER_EXCHANGE_add_aml_decision_cancel (ds->dh);
    ds->dh = NULL;
  }
  json_decref (ds->new_rules);
  GNUNET_free (ds);
}


/**
 * Offer internal data of a "AML decision" CMD state to other
 * commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
take_aml_decision_traits (void *cls,
                          const void **ret,
                          const char *trait,
                          unsigned int index)
{
  struct AmlDecisionState *ws = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_h_payto (&ws->h_payto),
    TALER_TESTING_make_trait_aml_justification (ws->justification),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_take_aml_decision (
  const char *label,
  const char *ref_officer,
  const char *ref_operation,
  bool keep_investigating,
  struct GNUNET_TIME_Relative expiration_delay,
  const char *successor_measure,
  const char *new_rules,
  const char *properties,
  const char *justification,
  unsigned int expected_response)
{
  struct AmlDecisionState *ds;
  json_error_t err;

  ds = GNUNET_new (struct AmlDecisionState);
  ds->officer_ref_cmd = ref_officer;
  ds->account_ref_cmd = ref_operation;
  ds->keep_investigating = keep_investigating;
  ds->expiration_delay = expiration_delay;
  ds->successor_measure = successor_measure;
  ds->new_rules = json_loads (new_rules,
                              JSON_DECODE_ANY,
                              &err);
  if (NULL == ds->new_rules)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid JSON in new rules of %s: %s\n",
                label,
                err.text);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Input was: `%s'\n",
                new_rules);
    GNUNET_assert (0);
  }
  GNUNET_assert (NULL != ds->new_rules);
  ds->properties = json_loads (properties,
                               0,
                               &err);
  if (NULL == ds->properties)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid JSON in properties of %s: %s\n",
                label,
                err.text);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Input was: `%s'\n",
                properties);
    GNUNET_assert (0);
  }
  ds->justification = justification;
  ds->expected_response = expected_response;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &take_aml_decision_run,
      .cleanup = &take_aml_decision_cleanup,
      .traits = &take_aml_decision_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_take_aml_decision.c */
