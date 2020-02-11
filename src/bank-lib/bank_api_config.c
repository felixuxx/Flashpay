/*
  This file is part of TALER
  Copyright (C) 2017--2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file bank-lib/bank_api_config.c
 * @brief Implementation of the /config request
 * @author Christian Grothoff
 */
#include "platform.h"
#include "bank_api_common.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include "taler_signatures.h"

/**
 * Protocol version we implement.
 */
#define BANK_PROTOCOL_CURRENT 0

/**
 * How many revisions back are we compatible to.
 */
#define BANK_PROTOCOL_AGE 0


/**
 * @brief A /config Handle
 */
struct TALER_BANK_ConfigHandle
{

  /**
   * The url for this request.
   */
  char *request_url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_BANK_ConfigCallback hcb;

  /**
   * Closure for @a cb.
   */
  void *hcb_cls;
};


/**
 * Parse configuration given in JSON format and invoke the callback on each item.
 *
 * @param ch handle to the account configuration request
 * @param config JSON object with the configuration
 * @return #GNUNET_OK if configuration was valid and @a rconfiguration and @a balance
 *         were set,
 *         #GNUNET_SYSERR if there was a protocol violation in @a configuration
 */
static int
parse_config (struct TALER_BANK_ConfigHandle *ch,
              const json_t *config)
{
  struct TALER_BANK_Configuration cfg;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("version",
                             &cfg.version),
    GNUNET_JSON_spec_string ("currency",
                             &cfg.version),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (config,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  ch->hcb (ch->hcb_cls,
           MHD_HTTP_OK,
           TALER_EC_NONE,
           &cfg);
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /config request.
 *
 * @param cls the `struct TALER_BANK_ConfigHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_configuration_finished (void *cls,
                               long response_code,
                               const void *response)
{
  struct TALER_BANK_ConfigHandle *ch = cls;
  enum TALER_ErrorCode ec;
  const json_t *j = response;

  ch->job = NULL;
  switch (response_code)
  {
  case 0:
    ec = TALER_EC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        parse_config (ch,
                      j))
    {
      GNUNET_break_op (0);
      response_code = 0;
      ec = TALER_EC_INVALID_RESPONSE;
      break;
    }
    response_code = MHD_HTTP_NO_CONTENT; /* signal end of list */
    ec = TALER_EC_NONE;
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the bank is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break_op (0);
    ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, bank says the HTTP Authentication
       failed. May happen if HTTP authentication is used and the
       user supplied a wrong username/password combination. */
    ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    ec = TALER_JSON_get_error_code (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break_op (0);
    ec = TALER_JSON_get_error_code (j);
    response_code = 0;
    break;
  }
  ch->hcb (ch->hcb_cls,
           response_code,
           ec,
           NULL);
  TALER_BANK_configuration_cancel (ch);
}


/**
 * Request the configuration of the bank.
 *
 * @param ctx curl context for the event loop
 * @param auth authentication data to use
 * @param hres_cb the callback to call with the
 *        configuration
 * @param hres_cb_cls closure for the above callback
 * @return NULL if the inputs are invalid
 */
struct TALER_BANK_ConfigHandle *
TALER_BANK_configuration (struct GNUNET_CURL_Context *ctx,
                          const struct TALER_BANK_AuthenticationData *auth,
                          TALER_BANK_ConfigCallback hres_cb,
                          void *hres_cb_cls)
{
  struct TALER_BANK_ConfigHandle *ch;
  CURL *eh;

  ch = GNUNET_new (struct TALER_BANK_ConfigHandle);
  ch->hcb = hres_cb;
  ch->hcb_cls = hres_cb_cls;
  ch->request_url = TALER_url_join (auth->wire_gateway_url,
                                    "config",
                                    NULL);
  if (NULL == ch->request_url)
  {
    GNUNET_free (ch);
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requesting configuration at `%s'\n",
              ch->request_url);
  eh = curl_easy_init ();
  if ( (GNUNET_OK !=
        TALER_BANK_setup_auth_ (eh,
                                auth)) ||
       (CURLE_OK !=
        curl_easy_setopt (eh,
                          CURLOPT_URL,
                          ch->request_url)) )
  {
    GNUNET_break (0);
    TALER_BANK_configuration_cancel (ch);
    curl_easy_cleanup (eh);
    return NULL;
  }
  ch->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  NULL,
                                  &handle_configuration_finished,
                                  ch);
  return ch;
}


/**
 * Cancel a configuration request.  This function cannot be
 * used on a request handle if a response is already
 * served for it.
 *
 * @param ch the configuration request handle
 */
void
TALER_BANK_configuration_cancel (struct TALER_BANK_ConfigHandle *ch)
{
  if (NULL != ch->job)
  {
    GNUNET_CURL_job_cancel (ch->job);
    ch->job = NULL;
  }
  GNUNET_free (ch->request_url);
  GNUNET_free (ch);
}


/* end of bank_api_config.c */
