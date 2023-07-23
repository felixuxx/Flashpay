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
 * @file taler-exchange-httpd_aml-decision.c
 * @brief Handle request about an AML decision.
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
#include "taler_kyclogic_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Closure for #make_aml_decision()
 */
struct DecisionContext
{
  /**
   * Justification given for the decision.
   */
  const char *justification;

  /**
   * When was the decision taken.
   */
  struct GNUNET_TIME_Timestamp decision_time;

  /**
   * New threshold for revising the decision.
   */
  struct TALER_Amount new_threshold;

  /**
   * Hash of payto://-URI of affected account.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * New AML state.
   */
  enum TALER_AmlDecisionState new_state;

  /**
   * Signature affirming the decision.
   */
  struct TALER_AmlOfficerSignatureP officer_sig;

  /**
   * Public key of the AML officer.
   */
  const struct TALER_AmlOfficerPublicKeyP *officer_pub;

  /**
   * KYC requirements imposed, NULL for none.
   */
  const json_t *kyc_requirements;

};


/**
 * Function implementing AML decision database transaction.
 *
 * Runs the transaction logic; IF it returns a non-error code, the
 * transaction logic MUST NOT queue a MHD response.  IF it returns an hard
 * error, the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls closure with a `struct DecisionContext`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
make_aml_decision (void *cls,
                   struct MHD_Connection *connection,
                   MHD_RESULT *mhd_ret)
{
  struct DecisionContext *dc = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Timestamp last_date;
  bool invalid_officer;
  uint64_t requirement_row = 0;

  if ( (NULL != dc->kyc_requirements) &&
       (0 != json_array_size (dc->kyc_requirements)) )
  {
    char *res = NULL;
    size_t idx;
    json_t *req;
    bool satisfied;

    json_array_foreach (dc->kyc_requirements, idx, req)
    {
      const char *r = json_string_value (req);

      if (NULL == res)
      {
        res = GNUNET_strdup (r);
      }
      else
      {
        char *tmp;

        GNUNET_asprintf (&tmp,
                         "%s %s",
                         res,
                         r);
        GNUNET_free (res);
        res = tmp;
      }
    }

    {
      json_t *kyc_details = NULL;

      qs = TALER_KYCLOGIC_check_satisfied (
        &res,
        &dc->h_payto,
        &kyc_details,
        TEH_plugin->select_satisfied_kyc_processes,
        TEH_plugin->cls,
        &satisfied);
      json_decref (kyc_details);
    }
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR != qs)
      {
        GNUNET_break (0);
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               "select_satisfied_kyc_processes");
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
      return qs;
    }
    if (! satisfied)
    {
      qs = TEH_plugin->insert_kyc_requirement_for_account (
        TEH_plugin->cls,
        res,
        &dc->h_payto,
        NULL, /* not a reserve */
        &requirement_row);
      if (qs < 0)
      {
        if (GNUNET_DB_STATUS_SOFT_ERROR != qs)
        {
          GNUNET_break (0);
          *mhd_ret = TALER_MHD_reply_with_error (connection,
                                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                                 TALER_EC_GENERIC_DB_STORE_FAILED,
                                                 "insert_kyc_requirement_for_account");
          return GNUNET_DB_STATUS_HARD_ERROR;
        }
        return qs;
      }
    }
    GNUNET_free (res);
  }

  qs = TEH_plugin->insert_aml_decision (TEH_plugin->cls,
                                        &dc->h_payto,
                                        &dc->new_threshold,
                                        dc->new_state,
                                        dc->decision_time,
                                        dc->justification,
                                        dc->kyc_requirements,
                                        requirement_row,
                                        dc->officer_pub,
                                        &dc->officer_sig,
                                        &invalid_officer,
                                        &last_date);
  if (qs <= 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR != qs)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "insert_aml_decision");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    return qs;
  }
  if (invalid_officer)
  {
    GNUNET_break_op (0);
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_AML_DECISION_INVALID_OFFICER,
      NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_TIME_timestamp_cmp (last_date,
                                 >=,
                                 dc->decision_time))
  {
    GNUNET_break_op (0);
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_CONFLICT,
      TALER_EC_EXCHANGE_AML_DECISION_MORE_RECENT_PRESENT,
      NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


MHD_RESULT
TEH_handler_post_aml_decision (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const json_t *root)
{
  struct MHD_Connection *connection = rc->connection;
  struct DecisionContext dc = {
    .officer_pub = officer_pub
  };
  uint32_t new_state32;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("officer_sig",
                                 &dc.officer_sig),
    GNUNET_JSON_spec_fixed_auto ("h_payto",
                                 &dc.h_payto),
    TALER_JSON_spec_amount ("new_threshold",
                            TEH_currency,
                            &dc.new_threshold),
    GNUNET_JSON_spec_string ("justification",
                             &dc.justification),
    GNUNET_JSON_spec_timestamp ("decision_time",
                                &dc.decision_time),
    GNUNET_JSON_spec_uint32 ("new_state",
                             &new_state32),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_array_const ("kyc_requirements",
                                    &dc.kyc_requirements),
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
    {
      GNUNET_break_op (0);
      return MHD_YES; /* failure */
    }
  }
  dc.new_state = (enum TALER_AmlDecisionState) new_state32;
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_officer_aml_decision_verify (dc.justification,
                                         dc.decision_time,
                                         &dc.new_threshold,
                                         &dc.h_payto,
                                         dc.new_state,
                                         dc.kyc_requirements,
                                         dc.officer_pub,
                                         &dc.officer_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_AML_DECISION_ADD_SIGNATURE_INVALID,
      NULL);
  }

  if (NULL != dc.kyc_requirements)
  {
    size_t index;
    json_t *elem;

    json_array_foreach (dc.kyc_requirements, index, elem)
    {
      const char *val;

      if (! json_is_string (elem))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_BAD_REQUEST,
          TALER_EC_GENERIC_PARAMETER_MALFORMED,
          "kyc_requirements array members must be strings");
      }
      val = json_string_value (elem);
      if (GNUNET_SYSERR ==
          TALER_KYCLOGIC_check_satisfiable (val))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_BAD_REQUEST,
          TALER_EC_EXCHANGE_AML_DECISION_UNKNOWN_CHECK,
          val);
      }
    }
  }

  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "make-aml-decision",
                                TEH_MT_REQUEST_OTHER,
                                &mhd_ret,
                                &make_aml_decision,
                                &dc))
    {
      return mhd_ret;
    }
  }
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_aml-decision.c */
