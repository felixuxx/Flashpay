/*
  This file is part of TALER
  Copyright (C) 2023-2024 Taler Systems SA

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
 * @file taler-exchange-httpd_aml-decision.c
 * @brief Handle POST request about an AML decision.
 * @author Christian Grothoff
 * @author Florian Dold
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd_common_kyc.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_aml-decision.h"


/**
 * Context used for processing the AML decision request.
 */
struct AmlDecisionContext
{

  /**
   * Kept in a DLL.
   */
  struct AmlDecisionContext *next;

  /**
   * Kept in a DLL.
   */
  struct AmlDecisionContext *prev;

  /**
   * HTTP status code to use with @e response.
   */
  unsigned int response_code;

  /**
   * Response to return, NULL if none yet.
   */
  struct MHD_Response *response;

  /**
   * Request we are processing.
   */
  struct TEH_RequestContext *rc;

  /**
   * Handle for async KYC processing.
   */
  struct TEH_KycAmlTrigger *kat;

};

/**
 * Kept in a DLL.
 */
static struct AmlDecisionContext *adc_head;

/**
 * Kept in a DLL.
 */
static struct AmlDecisionContext *adc_tail;


void
TEH_aml_decision_cleanup ()
{
  struct AmlDecisionContext *adc;

  while (NULL != (adc = adc_head))
  {
    MHD_resume_connection (adc->rc->connection);
    GNUNET_CONTAINER_DLL_remove (adc_head,
                                 adc_tail,
                                 adc);
  }
}


/**
 * Function called to clean up aml decision context.
 *
 * @param[in,out] rc context to clean up
 */
static void
aml_decision_cleaner (struct TEH_RequestContext *rc)
{
  struct AmlDecisionContext *adc = rc->rh_ctx;

  if (NULL != adc->kat)
  {
    TEH_kyc_finished_cancel (adc->kat);
    adc->kat = NULL;
  }
  if (NULL != adc->response)
  {
    MHD_destroy_response (adc->response);
    adc->response = NULL;
  }
  GNUNET_free (adc);
}


/**
 * Function called after the KYC-AML trigger is done.
 *
 * @param cls closure
 * @param http_status final HTTP status to return
 * @param[in] response final HTTP ro return
 */
static void
aml_trigger_callback (
  void *cls,
  unsigned int http_status,
  struct MHD_Response *response)
{
  struct AmlDecisionContext *adc = cls;

  adc->kat = NULL;
  GNUNET_assert (NULL == adc->response);
  GNUNET_assert (NULL != response);
  adc->response_code = http_status;
  adc->response = response;
  MHD_resume_connection (adc->rc->connection);
  GNUNET_CONTAINER_DLL_remove (adc_head,
                               adc_tail,
                               adc);
  TALER_MHD_daemon_trigger ();
}


MHD_RESULT
TEH_handler_post_aml_decision (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const json_t *root)
{
  struct MHD_Connection *connection = rc->connection;
  struct AmlDecisionContext *adc = rc->rh_ctx;
  const char *justification;
  const char *new_measures = NULL;
  bool to_investigate;
  struct GNUNET_TIME_Timestamp decision_time;
  const json_t *new_rules;
  const json_t *properties = NULL;
  struct TALER_FullPayto payto_uri = {
    .full_payto = NULL
  };
  struct TALER_NormalizedPaytoHashP h_payto;
  struct TALER_AmlOfficerSignatureP officer_sig;
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs = NULL;
  uint64_t legi_measure_serial_id = 0;
  MHD_RESULT ret;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_string (
        "new_measures",
        &new_measures),
      NULL),
    GNUNET_JSON_spec_string ("justification",
                             &justification),
    GNUNET_JSON_spec_mark_optional (
      TALER_JSON_spec_full_payto_uri ("payto_uri",
                                      &payto_uri),
      NULL),
    GNUNET_JSON_spec_fixed_auto ("h_payto",
                                 &h_payto),
    GNUNET_JSON_spec_object_const ("new_rules",
                                   &new_rules),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_object_const ("properties",
                                     &properties),
      NULL),
    GNUNET_JSON_spec_bool ("keep_investigating",
                           &to_investigate),
    GNUNET_JSON_spec_fixed_auto ("officer_sig",
                                 &officer_sig),
    GNUNET_JSON_spec_timestamp ("decision_time",
                                &decision_time),
    GNUNET_JSON_spec_end ()
  };
  struct GNUNET_TIME_Timestamp expiration_time;
  json_t *jmeasures = NULL;

  if (NULL == adc)
  {
    /* Initialize context */
    adc = GNUNET_new (struct AmlDecisionContext);
    adc->rc = rc;
    rc->rh_ctx = adc;
    rc->rh_cleaner = aml_decision_cleaner;
  }

  if (NULL != adc->response)
  {
    ret = MHD_queue_response (rc->connection,
                              adc->response_code,
                              adc->response);
    goto done;
  }

  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
    {
      ret = MHD_NO; /* hard failure */
      goto done;
    }
    if (GNUNET_NO == res)
    {
      GNUNET_break_op (0);
      ret = MHD_YES /* failure */;
      goto done;
    }
  }
  if (NULL != payto_uri.full_payto)
  {
    struct TALER_NormalizedPaytoHashP h_payto2;

    TALER_full_payto_normalize_and_hash (payto_uri,
                                         &h_payto2);
    if (0 !=
        GNUNET_memcmp (&h_payto,
                       &h_payto2))
    {
      GNUNET_break (0);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "payto_uri");
      goto done;
    }
  }

  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_officer_aml_decision_verify (
        justification,
        decision_time,
        &h_payto,
        new_rules,
        properties,
        new_measures,
        to_investigate,
        officer_pub,
        &officer_sig))
  {
    GNUNET_break_op (0);
    ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_AML_DECISION_ADD_SIGNATURE_INVALID,
      NULL);
    goto done;
  }

  lrs = TALER_KYCLOGIC_rules_parse (new_rules);
  if (NULL == lrs)
  {
    GNUNET_break_op (0);
    ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "legitimization rule malformed");
    goto done;
  }

  expiration_time = TALER_KYCLOGIC_rules_get_expiration (lrs);
  if (NULL != new_measures)
  {
    jmeasures
      = TALER_KYCLOGIC_get_measures (lrs,
                                     new_measures);
    if (NULL == jmeasures)
    {
      GNUNET_break_op (0);
      /* Request specified a new_measure for which the given
         rule set does not work as it does not define the measure */
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "new_measures/new_rules");
      goto done;
    }
  }

  {
    enum GNUNET_DB_QueryStatus qs;
    struct GNUNET_TIME_Timestamp last_date;
    bool invalid_officer = true;
    bool unknown_account = false;

    /* We keep 'new_measures' around mostly so that
       the auditor can later verify officer_sig */
    qs = TEH_plugin->insert_aml_decision (TEH_plugin->cls,
                                          payto_uri,
                                          &h_payto,
                                          decision_time,
                                          expiration_time,
                                          properties,
                                          new_rules,
                                          to_investigate,
                                          new_measures,
                                          jmeasures,
                                          justification,
                                          officer_pub,
                                          &officer_sig,
                                          &invalid_officer,
                                          &unknown_account,
                                          &last_date,
                                          &legi_measure_serial_id);
    json_decref (jmeasures);
    if (qs <= 0)
    {
      GNUNET_break (0);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_STORE_FAILED,
        "insert_aml_decision");
      goto done;
    }
    if (invalid_officer)
    {
      GNUNET_break_op (0);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_AML_DECISION_INVALID_OFFICER,
        NULL);
      goto done;
    }
    if (unknown_account)
    {
      GNUNET_break_op (0);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_NOT_FOUND,
        TALER_EC_EXCHANGE_GENERIC_BANK_ACCOUNT_UNKNOWN,
        "h_payto");
      goto done;
    }
    if (GNUNET_TIME_timestamp_cmp (last_date,
                                   >=,
                                   decision_time))
    {
      GNUNET_break_op (0);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_CONFLICT,
        TALER_EC_EXCHANGE_AML_DECISION_MORE_RECENT_PRESENT,
        NULL);
      goto done;
    }
  }
  /* Run instant measure if necessary */
  {
    const struct TALER_KYCLOGIC_Measure *instant_ms = NULL;
    struct MHD_Response *empty_response;
    enum GNUNET_DB_QueryStatus qs;

    if (NULL != new_measures)
    {
      instant_ms = TALER_KYCLOGIC_get_instant_measure (lrs, new_measures);
    }

    if (NULL != instant_ms)
    {
      /* We have an 'instant' measure which means we must run the
         AML program immediately instead of waiting for the account owner
         to select some measure and contribute their KYC data. */
      json_t *attributes
        = json_object ();   /* instant: empty attributes */
      uint64_t process_row;

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Running instant measure after AML decision\n");

      GNUNET_assert (NULL != attributes);
      empty_response
        = MHD_create_response_from_buffer_static (0,
                                                  "");
      GNUNET_assert (NULL != empty_response);

      qs = TEH_plugin->insert_kyc_requirement_process (
        TEH_plugin->cls,
        &h_payto,
        0, /* measure index */
        legi_measure_serial_id,
        "SKIP",
        NULL, /* provider_account_id */
        NULL, /* provider_legitimziation_id */
        &process_row);
      if (qs < 0)
      {
        GNUNET_break (0);
        ret = TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_GENERIC_DB_STORE_FAILED,
          "insert_kyc_requirement_process");
        goto done;
      }
      /* FIXME: Insert start time of KYC process' AML program */
      adc->kat
        = TEH_kyc_finished2 (
            &rc->async_scope_id,
            process_row,
            instant_ms,
            &h_payto,
            "SKIP",   /* provider */
            NULL,
            NULL,
            GNUNET_TIME_UNIT_FOREVER_ABS,
            attributes,
            MHD_HTTP_NO_CONTENT,      /* http status */
            empty_response,   /* MHD_Response */
            &aml_trigger_callback,
            adc);
      json_decref (attributes);
      if (NULL == adc->kat)
      {
        GNUNET_break (0);
        ret = TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_EXCHANGE_KYC_GENERIC_AML_LOGIC_BUG,
          "TEH_kyc_finished");
        goto done;
      }

      MHD_suspend_connection (adc->rc->connection);
      GNUNET_CONTAINER_DLL_insert (adc_head,
                                   adc_tail,
                                   adc);
      ret = MHD_YES;
      goto done;
    }
  }
  ret = TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
  goto done;

done:
  TALER_KYCLOGIC_rules_free (lrs);
  return ret;
}


/* end of taler-exchange-httpd_aml-decision.c */
