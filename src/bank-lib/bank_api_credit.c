/*
  This file is part of TALER
  Copyright (C) 2017--2024 Taler Systems SA

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
 * @file bank-lib/bank_api_credit.c
 * @brief Implementation of the /history/incoming
 *        requests of the bank's HTTP API.
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "bank_api_common.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include "taler_signatures.h"


/**
 * How much longer than the application-specified timeout
 * do we wait (giving the server a chance to respond)?
 */
#define GRACE_PERIOD_MS 1000


/**
 * @brief A /history/incoming Handle
 */
struct TALER_BANK_CreditHistoryHandle
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
  TALER_BANK_CreditHistoryCallback hcb;

  /**
   * Closure for @a cb.
   */
  void *hcb_cls;
};


/**
 * Parse history given in JSON format and invoke the callback on each item.
 *
 * @param hh handle to the account history request
 * @param history JSON array with the history
 * @return #GNUNET_OK if history was valid and @a rhistory and @a balance
 *         were set,
 *         #GNUNET_SYSERR if there was a protocol violation in @a history
 */
static enum GNUNET_GenericReturnValue
parse_account_history (struct TALER_BANK_CreditHistoryHandle *hh,
                       const json_t *history)
{
  struct TALER_BANK_CreditHistoryResponse chr = {
    .http_status = MHD_HTTP_OK,
    .ec = TALER_EC_NONE,
    .response = history
  };
  const json_t *history_array;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("incoming_transactions",
                                  &history_array),
    GNUNET_JSON_spec_string ("credit_account",
                             &chr.details.ok.credit_account_uri),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (history,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  {
    size_t len = json_array_size (history_array);
    struct TALER_BANK_CreditDetails cd[GNUNET_NZL (len)];

    GNUNET_break_op (0 != len);
    for (size_t i = 0; i<len; i++)
    {
      struct TALER_BANK_CreditDetails *td = &cd[i];
      const char *type;
      struct GNUNET_JSON_Specification hist_spec[] = {
        GNUNET_JSON_spec_string ("type",
                                 &type),
        TALER_JSON_spec_amount_any ("amount",
                                    &td->amount),
        GNUNET_JSON_spec_timestamp ("date",
                                    &td->execution_date),
        GNUNET_JSON_spec_uint64 ("row_id",
                                 &td->serial_id),
        GNUNET_JSON_spec_string ("debit_account",
                                 &td->debit_account_uri),
        GNUNET_JSON_spec_end ()
      };
      json_t *transaction = json_array_get (history_array,
                                            i);

      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             hist_spec,
                             NULL,
                             NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (0 == strcasecmp ("RESERVE",
                           type))
      {
        struct GNUNET_JSON_Specification reserve_spec[] = {
          GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                       &td->details.reserve.reserve_pub),
          GNUNET_JSON_spec_end ()
        };

        if (GNUNET_OK !=
            GNUNET_JSON_parse (transaction,
                               reserve_spec,
                               NULL,
                               NULL))
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
      }
      else if (0 == strcasecmp ("KYCAUTH",
                                type))
      {
        struct GNUNET_JSON_Specification kycauth_spec[] = {
          GNUNET_JSON_spec_fixed_auto ("account_pub",
                                       &td->details.kycauth.account_pub),
          GNUNET_JSON_spec_end ()
        };

        if (GNUNET_OK !=
            GNUNET_JSON_parse (transaction,
                               kycauth_spec,
                               NULL,
                               NULL))
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
      }
      else if (0 == strcasecmp ("WAD",
                                type))
      {
        struct GNUNET_JSON_Specification wad_spec[] = {
          GNUNET_JSON_spec_string ("origin_exchange_url",
                                   &td->details.wad.origin_exchange_url),
          GNUNET_JSON_spec_fixed_auto ("wad_id",
                                       &td->details.wad.wad_id),
          GNUNET_JSON_spec_end ()
        };

        if (GNUNET_OK !=
            GNUNET_JSON_parse (transaction,
                               wad_spec,
                               NULL,
                               NULL))
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
      }
      else
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
    }
    chr.details.ok.details_length = len;
    chr.details.ok.details = cd;
    hh->hcb (hh->hcb_cls,
             &chr);
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /history/incoming request.
 *
 * @param cls the `struct TALER_BANK_CreditHistoryHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_credit_history_finished (void *cls,
                                long response_code,
                                const void *response)
{
  struct TALER_BANK_CreditHistoryHandle *hh = cls;
  struct TALER_BANK_CreditHistoryResponse chr = {
    .http_status = response_code,
    .response = response
  };

  hh->job = NULL;
  switch (response_code)
  {
  case 0:
    chr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        parse_account_history (hh,
                               chr.response))
    {
      GNUNET_break_op (0);
      json_dumpf (chr.response,
                  stderr,
                  JSON_INDENT (2));
      chr.http_status = 0;
      chr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      break;
    }
    TALER_BANK_credit_history_cancel (hh);
    return;
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the bank is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break_op (0);
    chr.ec = TALER_JSON_get_error_code (chr.response);
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, bank says the HTTP Authentication
       failed. May happen if HTTP authentication is used and the
       user supplied a wrong username/password combination. */
    chr.ec = TALER_JSON_get_error_code (chr.response);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify: the bank is either unaware
       of the endpoint (not a bank), or of the account.
       We should pass the JSON (?) reply to the application */
    chr.ec = TALER_JSON_get_error_code (chr.response);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    chr.ec = TALER_JSON_get_error_code (chr.response);
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    chr.ec = TALER_JSON_get_error_code (chr.response);
    break;
  }
  hh->hcb (hh->hcb_cls,
           &chr);
  TALER_BANK_credit_history_cancel (hh);
}


struct TALER_BANK_CreditHistoryHandle *
TALER_BANK_credit_history (struct GNUNET_CURL_Context *ctx,
                           const struct TALER_BANK_AuthenticationData *auth,
                           uint64_t start_row,
                           int64_t num_results,
                           struct GNUNET_TIME_Relative timeout,
                           TALER_BANK_CreditHistoryCallback hres_cb,
                           void *hres_cb_cls)
{
  char url[128];
  struct TALER_BANK_CreditHistoryHandle *hh;
  CURL *eh;
  unsigned long long tms;

  if (0 == num_results)
  {
    GNUNET_break (0);
    return NULL;
  }

  tms = (unsigned long long) (timeout.rel_value_us
                              / GNUNET_TIME_UNIT_MILLISECONDS.rel_value_us);
  if ( ( (UINT64_MAX == start_row) &&
         (0 > num_results) ) ||
       ( (0 == start_row) &&
         (0 < num_results) ) )
  {
    if ( (0 < num_results) &&
         (! GNUNET_TIME_relative_is_zero (timeout)) )
      /* 0 == start_row is implied, go with timeout into future */
      GNUNET_snprintf (url,
                       sizeof (url),
                       "history/incoming?delta=%lld&long_poll_ms=%llu",
                       (long long) num_results,
                       tms);
    else
      /* Going back from current transaction or have no timeout;
         hence timeout makes no sense */
      GNUNET_snprintf (url,
                       sizeof (url),
                       "history/incoming?delta=%lld",
                       (long long) num_results);
  }
  else
  {
    if ( (0 < num_results) &&
         (! GNUNET_TIME_relative_is_zero (timeout)) )
      /* going forward from num_result */
      GNUNET_snprintf (url,
                       sizeof (url),
                       "history/incoming?delta=%lld&start=%llu&long_poll_ms=%llu",
                       (long long) num_results,
                       (unsigned long long) start_row,
                       tms);
    else
      /* going backwards or have no timeout;
         hence timeout makes no sense */
      GNUNET_snprintf (url,
                       sizeof (url),
                       "history/incoming?delta=%lld&start=%llu",
                       (long long) num_results,
                       (unsigned long long) start_row);
  }
  hh = GNUNET_new (struct TALER_BANK_CreditHistoryHandle);
  hh->hcb = hres_cb;
  hh->hcb_cls = hres_cb_cls;
  hh->request_url = TALER_url_join (auth->wire_gateway_url,
                                    url,
                                    NULL);
  if (NULL == hh->request_url)
  {
    GNUNET_free (hh);
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requesting credit history at `%s'\n",
              hh->request_url);
  eh = curl_easy_init ();
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_BANK_setup_auth_ (eh,
                                auth)) ||
       (CURLE_OK !=
        curl_easy_setopt (eh,
                          CURLOPT_URL,
                          hh->request_url)) )
  {
    GNUNET_break (0);
    TALER_BANK_credit_history_cancel (hh);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    return NULL;
  }
  if (0 != tms)
  {
    GNUNET_break (CURLE_OK ==
                  curl_easy_setopt (eh,
                                    CURLOPT_TIMEOUT_MS,
                                    (long) tms + GRACE_PERIOD_MS));
  }
  hh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  NULL,
                                  &handle_credit_history_finished,
                                  hh);
  return hh;
}


void
TALER_BANK_credit_history_cancel (struct TALER_BANK_CreditHistoryHandle *hh)
{
  if (NULL != hh->job)
  {
    GNUNET_CURL_job_cancel (hh->job);
    hh->job = NULL;
  }
  GNUNET_free (hh->request_url);
  GNUNET_free (hh);
}


/* end of bank_api_credit.c */
