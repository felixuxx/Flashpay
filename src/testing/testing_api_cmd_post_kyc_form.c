/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file testing/testing_api_cmd_post_kyc_form.c
 * @brief Implement the testing CMDs for a POST /kyc-form operation.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

/**
 * State for a POST /kyc-upload/$ID CMD.
 */
struct PostKycFormState
{

  /**
   * Command that did a GET on /kyc-info
   */
  const char *kyc_info_reference;

  /**
   * Index of the requirement to form.
   */
  unsigned int requirement_index;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * HTTP header to use.
   */
  struct curl_slist *form_header;

  /**
   * Form data to POST.
   */
  const char *form_data;

  /**
   * Curl handle performing the POST.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};


/**
 * Handle response to the command.
 *
 * @param cls closure.
 * @param response_code HTTP response code from server, 0 on hard error
 * @param response in JSON, NULL if response was not in JSON format
 */
static void
post_kyc_form_cb (
  void *cls,
  long response_code,
  const void *response)
{
  struct PostKycFormState *kcg = cls;
  struct TALER_TESTING_Interpreter *is = kcg->is;

  (void) response;
  kcg->job = NULL;
  if (kcg->expected_response_code != response_code)
  {
    TALER_TESTING_unexpected_status (is,
                                     (unsigned int) response_code,
                                     kcg->expected_response_code);
    return;
  }
  TALER_TESTING_interpreter_next (kcg->is);
}


/**
 * Get a curl handle with the right defaults.
 *
 * @param url URL to query
 */
static CURL *
curl_easy_setup (const char *url)
{
  CURL *eh;

  eh = curl_easy_init ();
  if (NULL == eh)
  {
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   url));
  /* Enable compression (using whatever curl likes), see
     https://curl.se/libcurl/c/CURLOPT_ACCEPT_ENCODING.html  */
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_ACCEPT_ENCODING,
                                  ""));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_TCP_FASTOPEN,
                                   1L));
  return eh;
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
post_kyc_form_run (void *cls,
                   const struct TALER_TESTING_Command *cmd,
                   struct TALER_TESTING_Interpreter *is)
{
  struct PostKycFormState *kcg = cls;
  const struct TALER_TESTING_Command *res_cmd;
  const char *id;
  CURL *eh;

  (void) cmd;
  kcg->is = is;
  res_cmd = TALER_TESTING_interpreter_lookup_command (
    kcg->is,
    kcg->kyc_info_reference);
  if (NULL == res_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_kyc_id (
        res_cmd,
        kcg->requirement_index,
        &id))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  if (NULL == id)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (kcg->is);
    return;
  }
  {
    char *url;

    GNUNET_asprintf (&url,
                     "%skyc-upload/%s",
                     TALER_TESTING_get_exchange_url (is),
                     id);
    eh = curl_easy_setup (url);
    if (NULL == eh)
    {
      GNUNET_break (0);
      GNUNET_free (url);
      TALER_TESTING_interpreter_fail (kcg->is);
      return;
    }
    GNUNET_free (url);
  }
  GNUNET_assert (
    CURLE_OK ==
    curl_easy_setopt (eh,
                      CURLOPT_POST,
                      1L));
  GNUNET_assert (
    CURLE_OK ==
    curl_easy_setopt (eh,
                      CURLOPT_POSTFIELDS,
                      kcg->form_data));
  GNUNET_assert (
    CURLE_OK ==
    curl_easy_setopt (eh,
                      CURLOPT_POSTFIELDSIZE_LARGE,
                      (curl_off_t) strlen (kcg->form_data)));
  kcg->job = GNUNET_CURL_job_add2 (
    TALER_TESTING_interpreter_get_context (is),
    eh,
    kcg->form_header,
    &post_kyc_form_cb,
    kcg);
  GNUNET_assert (NULL != kcg->job);
}


/**
 * Cleanup the state from a "track transaction" CMD, and possibly
 * cancel a operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
post_kyc_form_cleanup (void *cls,
                       const struct TALER_TESTING_Command *cmd)
{
  struct PostKycFormState *kcg = cls;

  if (NULL != kcg->job)
  {
    TALER_TESTING_command_incomplete (kcg->is,
                                      cmd->label);
    GNUNET_CURL_job_cancel (kcg->job);
    kcg->job = NULL;
  }
  curl_slist_free_all (kcg->form_header);
  GNUNET_free (kcg);
}


/**
 * Offer internal data from a "check KYC" CMD.
 *
 * @param cls closure.
 * @param[out] ret result (could be anything).
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
post_kyc_form_traits (void *cls,
                      const void **ret,
                      const char *trait,
                      unsigned int index)
{
  struct PostKycFormState *kcg = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_trait_end ()
  };

  (void) kcg;
  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_post_kyc_form (
  const char *label,
  const char *kyc_info_reference,
  unsigned int requirement_index,
  const char *form_data_content_type,
  const char *form_data,
  unsigned int expected_response_code)
{
  struct PostKycFormState *kcg;

  kcg = GNUNET_new (struct PostKycFormState);
  kcg->kyc_info_reference = kyc_info_reference;
  kcg->requirement_index = requirement_index;
  if (NULL != form_data_content_type)
  {
    char *hdr;

    GNUNET_asprintf (&hdr,
                     "%s: %s",
                     MHD_HTTP_HEADER_CONTENT_ENCODING,
                     form_data_content_type);
    kcg->form_header
      = curl_slist_append (NULL,
                           hdr);
    GNUNET_free (hdr);
  }
  kcg->form_data = form_data;
  kcg->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = kcg,
      .label = label,
      .run = &post_kyc_form_run,
      .cleanup = &post_kyc_form_cleanup,
      .traits = &post_kyc_form_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_post_kyc_form.c */
