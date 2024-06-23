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


MHD_RESULT
TEH_handler_post_aml_decision (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const json_t *root)
{
  struct MHD_Connection *connection = rc->connection;
  const char *justification;
  bool to_investigate;
  struct GNUNET_TIME_Timestamp decision_time;
  const json_t *new_rules;
  const json_t *properties = NULL;
  struct TALER_PaytoHashP h_payto;
  struct TALER_AmlOfficerSignatureP officer_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("justification",
                             &justification),
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
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_officer_aml_decision_verify (
        justification,
        decision_time,
        &h_payto,
        new_rules,
        properties,
        to_investigate,
        officer_pub,
        &officer_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_AML_DECISION_ADD_SIGNATURE_INVALID,
      NULL);
  }

  {
    struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs;

    lrs = TALER_KYCLOGIC_rules_parse (new_rules);
    if (NULL == lrs)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "legitimization rule malformed");
    }
    expiration_time = TALER_KYCLOGIC_rules_get_expiration (lrs);

    TALER_KYCLOGIC_rules_free (lrs);
  }

  {
    enum GNUNET_DB_QueryStatus qs;
    struct GNUNET_TIME_Timestamp last_date;
    bool invalid_officer = true;

    qs = TEH_plugin->insert_aml_decision (TEH_plugin->cls,
                                          &h_payto,
                                          decision_time,
                                          expiration_time,
                                          properties,
                                          new_rules,
                                          to_investigate,
                                          justification,
                                          officer_pub,
                                          &officer_sig,
                                          &invalid_officer,
                                          &last_date);
    if (qs <= 0)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_STORE_FAILED,
        "insert_aml_decision");
    }
    if (invalid_officer)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_AML_DECISION_INVALID_OFFICER,
        NULL);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (GNUNET_TIME_timestamp_cmp (last_date,
                                   >=,
                                   decision_time))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_CONFLICT,
        TALER_EC_EXCHANGE_AML_DECISION_MORE_RECENT_PRESENT,
        NULL);
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
