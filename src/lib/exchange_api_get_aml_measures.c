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
 * @file lib/exchange_api_get_aml_measures.c
 * @brief Implementation of the GET /aml/$OFFICER_PUB/measures request
 * @author Christian Grothoff
 */
#include "platform.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * Scrap buffer of temporary arrays.
 */
struct Scrap
{
  /**
   * Kept in DLL.
   */
  struct Scrap *next;

  /**
   * Kept in DLL.
   */
  struct Scrap *prev;

  /**
   * Pointer to our allocation.
   */
  const char **ptr;
};


/**
 * @brief A GET /aml/$OFFICER_PUB/measures Handle
 */
struct TALER_EXCHANGE_AmlGetMeasuresHandle
{

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_AmlMeasuresCallback measures_cb;

  /**
   * Closure for @e measures_cb.
   */
  void *measures_cb_cls;

  /**
   * HTTP headers for the job.
   */
  struct curl_slist *job_headers;

  /**
   * Head of scrap list.
   */
  struct Scrap *scrap_head;

  /**
   * Tail of scrap list.
   */
  struct Scrap *scrap_tail;
};


/**
 * Parse AML measures.
 *
 * @param jroots JSON object with measure data
 * @param[out] roots where to write the result
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_aml_roots (
  const json_t *jroots,
  struct TALER_EXCHANGE_AvailableAmlMeasures *roots)
{
  const json_t *obj;
  const char *name;
  size_t idx = 0;

  json_object_foreach ((json_t *) jroots, name, obj)
  {
    struct TALER_EXCHANGE_AvailableAmlMeasures *root
      = &roots[idx++];
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("check_name",
                               &root->check_name),
      GNUNET_JSON_spec_string ("prog_name",
                               &root->prog_name),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_object_const ("context",
                                       &root->context),
        NULL),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (obj,
                           spec,
                           NULL,
                           NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    root->measure_name = name;
  }
  return GNUNET_OK;
}


/**
 * Create array of length @a len in scrap book.
 *
 * @param[in,out] lh context for allocations
 * @param len length of array
 * @return scrap array
 */
static const char **
make_scrap (
  struct TALER_EXCHANGE_AmlGetMeasuresHandle *lh,
  unsigned int len)
{
  struct Scrap *s = GNUNET_new (struct Scrap);

  s->ptr = GNUNET_new_array (len,
                             const char *);
  GNUNET_CONTAINER_DLL_insert (lh->scrap_head,
                               lh->scrap_tail,
                               s);
  return s->ptr;
}


/**
 * Free all scrap space.
 *
 * @param[in,out] lh scrap context
 */
static void
free_scrap (struct TALER_EXCHANGE_AmlGetMeasuresHandle *lh)
{
  struct Scrap *s;

  while (NULL != (s = lh->scrap_head))
  {
    GNUNET_CONTAINER_DLL_remove (lh->scrap_head,
                                 lh->scrap_tail,
                                 s);
    GNUNET_free (s->ptr);
    GNUNET_free (s);
  }
}


/**
 * Convert JSON array of strings to string array.
 *
 * @param j JSON array to convert
 * @param[out] a array to initialize
 * @return true on success
 */
static bool
j_to_a (const json_t *j,
        const char **a)
{
  const json_t *e;
  size_t idx;

  json_array_foreach ((json_t *) j, idx, e)
  {
    if (NULL == (a[idx] = json_string_value (e)))
      return false;
  }
  return true;
}


/**
 * Parse AML programs.
 *
 * @param[in,out] lh context for allocations
 * @param jroots JSON object with program data
 * @param[out] roots where to write the result
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_aml_programs (
  struct TALER_EXCHANGE_AmlGetMeasuresHandle *lh,
  const json_t *jprogs,
  struct TALER_EXCHANGE_AvailableAmlPrograms *progs)
{
  const json_t *obj;
  const char *name;
  size_t idx = 0;

  json_object_foreach ((json_t *) jprogs, name, obj)
  {
    struct TALER_EXCHANGE_AvailableAmlPrograms *prog
      = &progs[idx++];
    const json_t *jcontext;
    const json_t *jinputs;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("description",
                               &prog->description),
      GNUNET_JSON_spec_array_const ("context",
                                    &jcontext),
      GNUNET_JSON_spec_array_const ("inputs",
                                    &jinputs),
      GNUNET_JSON_spec_end ()
    };
    unsigned int len;
    const char **ptr;

    if (GNUNET_OK !=
        GNUNET_JSON_parse (obj,
                           spec,
                           NULL,
                           NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    prog->prog_name = name;
    prog->contexts_length
      = (unsigned int) json_array_size (jcontext);
    prog->inputs_length
      = (unsigned int) json_array_size (jinputs);
    len = prog->contexts_length + prog->inputs_length;
    if ( ((unsigned long long) len) !=
         (unsigned long long) json_array_size (jcontext)
         + (unsigned long long) json_array_size (jinputs) )
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    ptr = make_scrap (lh,
                      len);
    prog->contexts = ptr;
    if (! j_to_a (jcontext,
                  prog->contexts))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    prog->inputs = &ptr[prog->contexts_length];
    if (! j_to_a (jinputs,
                  prog->inputs))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


/**
 * Parse AML measures.
 *
 * @param[in,out] lh context for allocations
 * @param jchecks JSON object with measure data
 * @param[out] checks where to write the result
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_aml_checks (
  struct TALER_EXCHANGE_AmlGetMeasuresHandle *lh,
  const json_t *jchecks,
  struct TALER_EXCHANGE_AvailableKycChecks *checks)
{
  const json_t *obj;
  const char *name;
  size_t idx = 0;

  json_object_foreach ((json_t *) jchecks, name, obj)
  {
    struct TALER_EXCHANGE_AvailableKycChecks *check
      = &checks[idx++];
    const json_t *jrequires;
    const json_t *joutputs;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("description",
                               &check->description),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_object_const ("description_i18n",
                                       &check->description_i18n),
        NULL),
      GNUNET_JSON_spec_array_const ("requires",
                                    &jrequires),
      GNUNET_JSON_spec_array_const ("outputs",
                                    &joutputs),
      GNUNET_JSON_spec_string ("fallback",
                               &check->fallback),
      GNUNET_JSON_spec_end ()
    };
    unsigned int len;
    const char **ptr;

    if (GNUNET_OK !=
        GNUNET_JSON_parse (obj,
                           spec,
                           NULL,
                           NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    check->check_name = name;

    check->requires_length
      = (unsigned int) json_array_size (jrequires);
    check->outputs_length
      = (unsigned int) json_array_size (joutputs);
    len = check->requires_length + check->outputs_length;
    if ( ((unsigned long long) len) !=
         (unsigned long long) json_array_size (jrequires)
         + (unsigned long long) json_array_size (joutputs) )
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    ptr = make_scrap (lh,
                      len);
    check->requires = ptr;
    if (! j_to_a (jrequires,
                  check->requires))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    check->outputs = &ptr[check->requires_length];
    if (! j_to_a (joutputs,
                  check->outputs))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


/**
 * Parse the provided decision data from the "200 OK" response.
 *
 * @param[in,out] lh handle (callback may be zero'ed out)
 * @param json json reply with the data for one coin
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static enum GNUNET_GenericReturnValue
parse_measures_ok (struct TALER_EXCHANGE_AmlGetMeasuresHandle *lh,
                   const json_t *json)
{
  struct TALER_EXCHANGE_AmlGetMeasuresResponse lr = {
    .hr.reply = json,
    .hr.http_status = MHD_HTTP_OK
  };
  const json_t *jroots;
  const json_t *jprograms;
  const json_t *jchecks;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_object_const ("roots",
                                   &jroots),
    GNUNET_JSON_spec_object_const ("programs",
                                   &jprograms),
    GNUNET_JSON_spec_object_const ("checks",
                                   &jchecks),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  lr.details.ok.roots_length
    = (unsigned int) json_object_size (jroots);
  lr.details.ok.programs_length
    = (unsigned int) json_object_size (jprograms);
  lr.details.ok.checks_length
    = (unsigned int) json_object_size (jchecks);
  if ( ( ((size_t) lr.details.ok.roots_length)
         != json_object_size (jroots)) ||
       ( ((size_t) lr.details.ok.programs_length)
         != json_object_size (jprograms)) ||
       ( ((size_t) lr.details.ok.checks_length)
         != json_object_size (jchecks)) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  {
    struct TALER_EXCHANGE_AvailableAmlMeasures roots[
      GNUNET_NZL (lr.details.ok.roots_length)];
    struct TALER_EXCHANGE_AvailableAmlPrograms progs[
      GNUNET_NZL (lr.details.ok.programs_length)];
    struct TALER_EXCHANGE_AvailableKycChecks checks[
      GNUNET_NZL (lr.details.ok.checks_length)];
    enum GNUNET_GenericReturnValue ret;

    memset (roots,
            0,
            sizeof (roots));
    memset (progs,
            0,
            sizeof (progs));
    memset (checks,
            0,
            sizeof (checks));
    lr.details.ok.roots = roots;
    lr.details.ok.programs = progs;
    lr.details.ok.checks = checks;
    ret = parse_aml_roots (jroots,
                           roots);
    if (GNUNET_OK == ret)
      ret = parse_aml_programs (lh,
                                jprograms,
                                progs);
    if (GNUNET_OK == ret)
      ret = parse_aml_checks (lh,
                              jchecks,
                              checks);
    if (GNUNET_OK == ret)
    {
      lh->measures_cb (lh->measures_cb_cls,
                       &lr);
      lh->measures_cb = NULL;
    }
    free_scrap (lh);
    return ret;
  }
}


/**
 * Function called when we're done processing the
 * HTTP /aml/$OFFICER_PUB/measures request.
 *
 * @param cls the `struct TALER_EXCHANGE_AmlGetMeasuresHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_lookup_finished (void *cls,
                        long response_code,
                        const void *response)
{
  struct TALER_EXCHANGE_AmlGetMeasuresHandle *lh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_AmlGetMeasuresResponse lr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  lh->job = NULL;
  switch (response_code)
  {
  case 0:
    lr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        parse_measures_ok (lh,
                           j))
    {
      GNUNET_break_op (0);
      lr.hr.http_status = 0;
      lr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == lh->measures_cb);
    TALER_EXCHANGE_aml_get_measures_cancel (lh);
    return;
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_BAD_REQUEST:
    lr.hr.ec = TALER_JSON_get_error_code (j);
    lr.hr.hint = TALER_JSON_get_error_hint (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    lr.hr.ec = TALER_JSON_get_error_code (j);
    lr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, exchange says this coin was not melted; we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    lr.hr.ec = TALER_JSON_get_error_code (j);
    lr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    lr.hr.ec = TALER_JSON_get_error_code (j);
    lr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for get AML measures\n",
                (unsigned int) response_code,
                (int) lr.hr.ec);
    break;
  }
  if (NULL != lh->measures_cb)
    lh->measures_cb (lh->measures_cb_cls,
                     &lr);
  TALER_EXCHANGE_aml_get_measures_cancel (lh);
}


struct TALER_EXCHANGE_AmlGetMeasuresHandle *
TALER_EXCHANGE_aml_get_measures (
  struct GNUNET_CURL_Context *ctx,
  const char *exchange_url,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  TALER_EXCHANGE_AmlMeasuresCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_AmlGetMeasuresHandle *lh;
  CURL *eh;
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  struct TALER_AmlOfficerSignatureP officer_sig;
  char arg_str[sizeof (struct TALER_AmlOfficerPublicKeyP) * 2
               + 32];

  GNUNET_CRYPTO_eddsa_key_get_public (&officer_priv->eddsa_priv,
                                      &officer_pub.eddsa_pub);
  TALER_officer_aml_query_sign (officer_priv,
                                &officer_sig);
  {
    char pub_str[sizeof (officer_pub) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &officer_pub,
      sizeof (officer_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "aml/%s/measures",
                     pub_str);
  }
  lh = GNUNET_new (struct TALER_EXCHANGE_AmlGetMeasuresHandle);
  lh->measures_cb = cb;
  lh->measures_cb_cls = cb_cls;
  lh->url = TALER_url_join (exchange_url,
                            arg_str,
                            NULL);
  if (NULL == lh->url)
  {
    GNUNET_free (lh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (lh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (lh->url);
    GNUNET_free (lh);
    return NULL;
  }
  {
    char *hdr;
    char sig_str[sizeof (officer_sig) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &officer_sig,
      sizeof (officer_sig),
      sig_str,
      sizeof (sig_str));
    *end = '\0';

    GNUNET_asprintf (&hdr,
                     "%s: %s",
                     TALER_AML_OFFICER_SIGNATURE_HEADER,
                     sig_str);
    lh->job_headers = curl_slist_append (NULL,
                                         hdr);
    GNUNET_free (hdr);
    lh->job_headers = curl_slist_append (lh->job_headers,
                                         "Content-type: application/json");
    lh->job = GNUNET_CURL_job_add2 (ctx,
                                    eh,
                                    lh->job_headers,
                                    &handle_lookup_finished,
                                    lh);
  }
  return lh;
}


void
TALER_EXCHANGE_aml_get_measures_cancel (
  struct TALER_EXCHANGE_AmlGetMeasuresHandle *lh)
{
  if (NULL != lh->job)
  {
    GNUNET_CURL_job_cancel (lh->job);
    lh->job = NULL;
  }
  curl_slist_free_all (lh->job_headers);
  GNUNET_free (lh->url);
  GNUNET_free (lh);
}


/* end of exchange_api_get_aml_measures.c */
