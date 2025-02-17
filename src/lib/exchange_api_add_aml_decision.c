/*
  This file is part of TALER
  Copyright (C) 2023, 2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_add_aml_decision.c
 * @brief functions to add an AML decision by an AML officer
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "exchange_api_curl_defaults.h"
#include "taler_signatures.h"
#include "taler_curl_lib.h"
#include "taler_json_lib.h"


struct TALER_EXCHANGE_AddAmlDecision
{

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Minor context that holds body and headers.
   */
  struct TALER_CURL_PostContext post_ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_AddAmlDecisionCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Reference to the execution context.
   */
  struct GNUNET_CURL_Context *ctx;
};


/**
 * Function called when we're done processing the
 * HTTP POST /aml/$OFFICER_PUB/decision request.
 *
 * @param cls the `struct TALER_EXCHANGE_AddAmlDecision *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_add_aml_decision_finished (void *cls,
                                  long response_code,
                                  const void *response)
{
  struct TALER_EXCHANGE_AddAmlDecision *wh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_AddAmlDecisionResponse adr = {
    .hr.http_status = (unsigned int) response_code,
    .hr.reply = json
  };

  wh->job = NULL;
  switch (response_code)
  {
  case 0:
    /* no reply */
    adr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    adr.hr.hint = "server offline?";
    break;
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    adr.hr.ec = TALER_JSON_get_error_code (json);
    adr.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  case MHD_HTTP_CONFLICT:
    adr.hr.ec = TALER_JSON_get_error_code (json);
    adr.hr.hint = TALER_JSON_get_error_hint (json);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    adr.hr.ec = TALER_JSON_get_error_code (json);
    adr.hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange AML decision\n",
                (unsigned int) response_code,
                (int) adr.hr.ec);
    break;
  }
  if (NULL != wh->cb)
  {
    wh->cb (wh->cb_cls,
            &adr);
    wh->cb = NULL;
  }
  TALER_EXCHANGE_post_aml_decision_cancel (wh);
}


struct TALER_EXCHANGE_AddAmlDecision *
TALER_EXCHANGE_post_aml_decision (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const struct TALER_FullPayto payto_uri,
  struct GNUNET_TIME_Timestamp decision_time,
  const char *successor_measure,
  const char *new_measures,
  struct GNUNET_TIME_Timestamp expiration_time,
  unsigned int num_rules,
  const struct TALER_EXCHANGE_AccountRule *rules,
  unsigned int num_measures,
  const struct TALER_EXCHANGE_MeasureInformation *measures,
  const json_t *properties,
  bool keep_investigating,
  const char *justification,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  TALER_EXCHANGE_AddAmlDecisionCallback cb,
  void *cb_cls)
{
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  struct TALER_AmlOfficerSignatureP officer_sig;
  struct TALER_EXCHANGE_AddAmlDecision *wh;
  CURL *eh;
  json_t *body;
  json_t *new_rules;
  json_t *jrules;
  json_t *jmeasures;

  jrules = json_array ();
  GNUNET_assert (NULL != jrules);
  for (unsigned int i = 0; i<num_rules; i++)
  {
    const struct TALER_EXCHANGE_AccountRule *al = &rules[i];
    json_t *rule;
    json_t *ameasures;

    ameasures = json_array ();
    GNUNET_assert (NULL != ameasures);
    for (unsigned int j = 0; j<al->num_measures; j++)
      GNUNET_assert (0 ==
                     json_array_append_new (ameasures,
                                            json_string (al->measures[j])));
    rule = GNUNET_JSON_PACK (
      TALER_JSON_pack_kycte ("operation_type",
                             al->operation_type),
      TALER_JSON_pack_amount ("threshold",
                              &al->threshold),
      GNUNET_JSON_pack_time_rel ("timeframe",
                                 al->timeframe),
      GNUNET_JSON_pack_array_steal ("measures",
                                    ameasures),
      GNUNET_JSON_pack_bool ("exposed",
                             al->exposed),
      GNUNET_JSON_pack_bool ("is_and_combinator",
                             al->is_and_combinator),
      GNUNET_JSON_pack_uint64 ("display_priority",
                               al->display_priority)
      );
    GNUNET_break (0 ==
                  json_array_append_new (jrules,
                                         rule));
  }

  jmeasures = json_object ();
  GNUNET_assert (NULL != jmeasures);
  for (unsigned int i = 0; i<num_measures; i++)
  {
    const struct TALER_EXCHANGE_MeasureInformation *mi = &measures[i];
    json_t *measure;

    measure = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("check_name",
                               mi->check_name),
      GNUNET_JSON_pack_string ("prog_name",
                               mi->prog_name),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("context",
                                        (json_t *) mi->context))
      );
    GNUNET_break (0 ==
                  json_object_set_new (jmeasures,
                                       mi->measure_name,
                                       measure));
  }

  new_rules = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_timestamp ("expiration_time",
                                expiration_time),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string ("successor_measure",
                               successor_measure)),
    GNUNET_JSON_pack_array_steal ("rules",
                                  jrules),
    GNUNET_JSON_pack_object_steal ("custom_measures",
                                   jmeasures)
    );

  GNUNET_CRYPTO_eddsa_key_get_public (
    &officer_priv->eddsa_priv,
    &officer_pub.eddsa_pub);
  TALER_officer_aml_decision_sign (justification,
                                   decision_time,
                                   h_payto,
                                   new_rules,
                                   properties,
                                   new_measures,
                                   keep_investigating,
                                   officer_priv,
                                   &officer_sig);
  wh = GNUNET_new (struct TALER_EXCHANGE_AddAmlDecision);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ctx = ctx;
  {
    char *path;
    char opus[sizeof (officer_pub) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &officer_pub,
      sizeof (officer_pub),
      opus,
      sizeof (opus));
    *end = '\0';
    GNUNET_asprintf (&path,
                     "aml/%s/decision",
                     opus);
    wh->url = TALER_url_join (url,
                              path,
                              NULL);
    GNUNET_free (path);
  }
  if (NULL == wh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (wh);
    json_decref (new_rules);
    return NULL;
  }
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("justification",
                             justification),
    GNUNET_JSON_pack_data_auto ("h_payto",
                                h_payto),
    GNUNET_JSON_pack_allow_null (
      TALER_JSON_pack_full_payto ("payto_uri",
                                  payto_uri)),
    GNUNET_JSON_pack_object_steal ("new_rules",
                                   new_rules),
    GNUNET_JSON_pack_object_incref ("properties",
                                    (json_t *) properties),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string ("new_measures",
                               new_measures)),
    GNUNET_JSON_pack_bool ("keep_investigating",
                           keep_investigating),
    GNUNET_JSON_pack_data_auto ("officer_sig",
                                &officer_sig),
    GNUNET_JSON_pack_timestamp ("decision_time",
                                decision_time));
  eh = TALER_EXCHANGE_curl_easy_get_ (wh->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&wh->post_ctx,
                              eh,
                              body)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (body);
    GNUNET_free (wh->url);
    return NULL;
  }
  json_decref (body);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              wh->url);
  wh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  wh->post_ctx.headers,
                                  &handle_add_aml_decision_finished,
                                  wh);
  if (NULL == wh->job)
  {
    TALER_EXCHANGE_post_aml_decision_cancel (wh);
    return NULL;
  }
  return wh;
}


void
TALER_EXCHANGE_post_aml_decision_cancel (
  struct TALER_EXCHANGE_AddAmlDecision *wh)
{
  if (NULL != wh->job)
  {
    GNUNET_CURL_job_cancel (wh->job);
    wh->job = NULL;
  }
  TALER_curl_easy_post_finished (&wh->post_ctx);
  GNUNET_free (wh->url);
  GNUNET_free (wh);
}
