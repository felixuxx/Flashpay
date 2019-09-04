/*
  This file is part of TALER
  Copyright (C) 2017 GNUnet e.V. & Inria

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
 * @file bank-lib/bank_api_history.c
 * @brief Implementation of the /history[-range]
 *        requests of the bank's HTTP API.
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "bank_api_common.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include "taler_signatures.h"


/**
 * @brief A /history Handle
 */
struct TALER_BANK_HistoryHandle
{

  /**
   * The url for this request.
   */
  char *request_url;

  /**
   * The base URL of the bank.
   */
  char *bank_base_url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * HTTP authentication-related headers for the request.
   */
  struct curl_slist *authh;

  /**
   * Function to call with the result.
   */
  TALER_BANK_HistoryResultCallback hcb;

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
static int
parse_account_history (struct TALER_BANK_HistoryHandle *hh,
                       const json_t *history)
{
  json_t *history_array;
  char *bank_hostname;

  if (NULL == (history_array = json_object_get (history, "data")))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  for (unsigned int i = 0; i<json_array_size (history_array); i++)
  {
    struct TALER_BANK_TransferDetails td;
    const char *sign;
    uint64_t other_account;
    uint64_t row_id;
    enum TALER_BANK_Direction direction;
    struct GNUNET_JSON_Specification hist_spec[] = {
      GNUNET_JSON_spec_string ("sign",
                               &sign),
      TALER_JSON_spec_amount ("amount",
                              &td.amount),
      GNUNET_JSON_spec_absolute_time ("date",
                                      &td.execution_date),
      GNUNET_JSON_spec_uint64 ("row_id",
                               &row_id),
      GNUNET_JSON_spec_string ("wt_subject",
                               (const char **) &td.wire_transfer_subject),
      GNUNET_JSON_spec_uint64 ("counterpart",
                               &other_account),
      GNUNET_JSON_spec_end ()
    };
    json_t *transaction = json_array_get (history_array,
                                          i);

    if (GNUNET_OK !=
        GNUNET_JSON_parse (transaction,
                           hist_spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }

    if (0 == strcasecmp (sign,
                         "+"))
      direction = TALER_BANK_DIRECTION_CREDIT;
    else if (0 == strcasecmp (sign,
                              "-"))
      direction = TALER_BANK_DIRECTION_DEBIT;
    else if (0 == strcasecmp (sign,
                              "cancel+"))
      direction = TALER_BANK_DIRECTION_CREDIT | TALER_BANK_DIRECTION_CANCEL;
    else if (0 == strcasecmp (sign,
                              "cancel-"))
      direction = TALER_BANK_DIRECTION_DEBIT | TALER_BANK_DIRECTION_CANCEL;
    else
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (hist_spec);
      return GNUNET_SYSERR;
    }
    /* Note, bank_base_url has _always_ the protocol scheme
     * and it proved to be good at this point.  */
    bank_hostname = strchr (hh->bank_base_url, ':');
    GNUNET_assert (NULL != bank_hostname);
    bank_hostname += 3;

    GNUNET_asprintf (&td.account_url,
                     ('/' == bank_hostname[strlen (bank_hostname) - 1])
                     ? "payto://x-taler-bank/%s%llu"
                     : "payto://x-taler-bank/%s/%llu",
                     bank_hostname,
                     (unsigned long long) other_account);
    hh->hcb (hh->hcb_cls,
             MHD_HTTP_OK,
             TALER_EC_NONE,
             direction,
             row_id,
             &td,
             transaction);
    GNUNET_free (td.account_url);
    GNUNET_JSON_parse_free (hist_spec);
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /history request.
 *
 * @param cls the `struct TALER_BANK_HistoryHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_history_finished (void *cls,
                         long response_code,
                         const void *response)
{
  struct TALER_BANK_HistoryHandle *hh = cls;
  enum TALER_ErrorCode ec;
  const json_t *j = response;

  hh->job = NULL;
  switch (response_code)
  {
  case 0:
    ec = TALER_EC_BANK_HISTORY_HTTP_FAILURE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        parse_account_history (hh,
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
  case MHD_HTTP_NO_CONTENT:
    ec = TALER_EC_NONE;
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the bank is buggy
       (or API version conflict); just pass JSON reply to the application */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Access denied */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, bank says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    ec = TALER_BANK_parse_ec_ (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break (0);
    ec = TALER_BANK_parse_ec_ (j);
    response_code = 0;
    break;
  }
  hh->hcb (hh->hcb_cls,
           response_code,
           ec,
           TALER_BANK_DIRECTION_NONE,
           0LLU,
           NULL,
           j);
  TALER_BANK_history_cancel (hh);
}



/**
 * Backend of both the /history[-range] requests.
 *
 * @param ctx curl context for the event loop
 * @param bank_base_url base URL of the bank.
 * @param urlargs path + URL arguments.
 * @param auth authentication data to use
 * @param hres_cb the callback to call with the transaction
 *        history
 * @param hres_cb_cls closure for the above callback
 * @return NULL if the inputs are invalid (i.e. zero value for
 *         @e num_results). In this case, the callback is not
 *         called.
 */
static struct TALER_BANK_HistoryHandle *
put_history_job (struct GNUNET_CURL_Context *ctx,
                 const char *bank_base_url,
                 const char *urlargs,
                 const struct TALER_BANK_AuthenticationData *auth,
                 TALER_BANK_HistoryResultCallback hres_cb,
                 void *hres_cb_cls)
{
  struct TALER_BANK_HistoryHandle *hh;
  CURL *eh;

  hh = GNUNET_new (struct TALER_BANK_HistoryHandle);
  hh->hcb = hres_cb;
  hh->hcb_cls = hres_cb_cls;
  hh->bank_base_url = GNUNET_strdup (bank_base_url);
  hh->request_url = TALER_BANK_path_to_url_ (bank_base_url,
                                             urlargs);

  hh->authh = TALER_BANK_make_auth_header_ (auth);
  eh = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   hh->request_url));
  hh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  hh->authh,
                                  &handle_history_finished,
                                  hh);
  return hh;
}


/**
 * Convert fixed value 'direction' into string.
 *
 * @param direction the value to convert.
 * @return string representation of @a direction.  NULL on error
 */
static const char *
conv_direction (enum TALER_BANK_Direction direction)
{
  if (TALER_BANK_DIRECTION_NONE == direction)
  {
    /* Should just never happen.  */
    GNUNET_break (0);
    return NULL;
  }
  if (TALER_BANK_DIRECTION_BOTH ==
      (TALER_BANK_DIRECTION_BOTH & direction))
    return "both";
  else if (TALER_BANK_DIRECTION_CREDIT ==
           (TALER_BANK_DIRECTION_CREDIT & direction))
    return "credit";
  else if (TALER_BANK_DIRECTION_DEBIT ==
           (TALER_BANK_DIRECTION_BOTH & direction)) /*why use 'both' flag?*/
    return "debit";
  /* Should just never happen.  */
  GNUNET_break (0);
  return NULL;
}


/**
 * Convert fixed value 'direction' into string representation
 * of the "cancel" argument.
 *
 * @param direction the value to convert.
 * @return string representation of @a direction
 */
static const char *
conv_cancel (enum TALER_BANK_Direction direction)
{
  if (TALER_BANK_DIRECTION_CANCEL ==
      (TALER_BANK_DIRECTION_CANCEL & direction))
    return "show";
  return "omit";
}


/**
 * Request the wire transfer history of a bank account,
 * using time stamps to narrow the results.
 *
 * @param ctx curl context for the event loop
 * @param bank_base_url URL of the bank (used to execute this
 *        request)
 * @param auth authentication data to use
 * @param account_number which account number should we query
 * @param direction what kinds of wire transfers should be
 *        returned
 * @param ascending if GNUNET_YES, history elements will
 *        be returned in chronological order.
 * @param start_date threshold for oldest result.
 * @param end_date threshold for youngest result.
 * @param hres_cb the callback to call with the transaction
 *        history
 * @param hres_cb_cls closure for the above callback
 * @return NULL if the inputs are invalid (i.e. zero value for
 *         @e num_results). In this case, the callback is not
 *         called.
 */
struct TALER_BANK_HistoryHandle *
TALER_BANK_history_range
  (struct GNUNET_CURL_Context *ctx,
   const char *bank_base_url,
   const struct TALER_BANK_AuthenticationData *auth,
   uint64_t account_number,
   enum TALER_BANK_Direction direction,
   unsigned int ascending,
   struct GNUNET_TIME_Absolute start_date,
   struct GNUNET_TIME_Absolute end_date,
   TALER_BANK_HistoryResultCallback hres_cb,
   void *hres_cb_cls)
{
  struct TALER_BANK_HistoryHandle *hh;
  char *url;

  GNUNET_TIME_round_abs (&start_date);
  GNUNET_TIME_round_abs (&end_date);

  GNUNET_asprintf (&url,
                   "/history-range?auth=basic&account_number=%llu&start=%llu&end=%llu&direction=%s&cancelled=%s&ordering=%s",
                   (unsigned long long) account_number,
                   start_date.abs_value_us / 1000LL / 1000LL,
                   end_date.abs_value_us / 1000LL / 1000LL,
                   conv_direction (direction),
                   conv_cancel (direction),
                   (GNUNET_YES == ascending) ? "ascending" : "descending");

  hh = put_history_job (ctx,
                        bank_base_url,
                        url,
                        auth,
                        hres_cb,
                        hres_cb_cls);

  GNUNET_free (url);
  return hh;
}



/**
 * Request the wire transfer history of a bank account.
 *
 * @param ctx curl context for the event loop
 * @param bank_base_url URL of the bank (used to execute this
 *        request)
 * @param auth authentication data to use
 * @param account_number which account number should we query
 * @param direction what kinds of wire transfers should be
 *        returned
 * @param ascending if GNUNET_YES, history elements will
 *        be returned in chronological order.
 * @param start_row from which row on do we want to get results,
 *        use UINT64_MAX for the latest; exclusive
 * @param num_results how many results do we want;
 *        negative numbers to go into the past, positive numbers
 *        to go into the future starting at @a start_row;
 *        must not be zero.
 * @param hres_cb the callback to call with the transaction
 *        history
 * @param hres_cb_cls closure for the above callback
 * @return NULL if the inputs are invalid (i.e. zero value for
 *         @e num_results). In this case, the callback is not
 *         called.
 */
struct TALER_BANK_HistoryHandle *
TALER_BANK_history (struct GNUNET_CURL_Context *ctx,
                    const char *bank_base_url,
                    const struct TALER_BANK_AuthenticationData *auth,
                    uint64_t account_number,
                    enum TALER_BANK_Direction direction,
                    unsigned int ascending,
                    uint64_t start_row,
                    int64_t num_results,
                    TALER_BANK_HistoryResultCallback hres_cb,
                    void *hres_cb_cls)
{
  struct TALER_BANK_HistoryHandle *hh;
  char *url;

  if (0 == num_results)
  {
    GNUNET_break (0);
    return NULL;
  }

  if (UINT64_MAX == start_row)
    GNUNET_asprintf (&url,
                     "/history?auth=basic&account_number=%llu&delta=%lld&direction=%s&cancelled=%s&ordering=%s",
                     (unsigned long long) account_number,
                     (long long) num_results,
                     conv_direction (direction),
                     conv_cancel (direction),
                     (GNUNET_YES == ascending) ? "ascending" : "descending");
  else
    GNUNET_asprintf (&url,
                     "/history?auth=basic&account_number=%llu&delta=%lld&direction=%s&cancelled=%s&ordering=%s&start=%llu",
                     (unsigned long long) account_number,
                     (long long) num_results,
                     conv_direction (direction),
                     conv_cancel (direction),
                     (GNUNET_YES == ascending) ? "ascending" : "descending",
                     start_row);
  hh = put_history_job (ctx,
                        bank_base_url,
                        url,
                        auth,
                        hres_cb,
                        hres_cb_cls);

  GNUNET_free (url);
  return hh;
}


/**
 * Cancel a history request.  This function cannot be
 * used on a request handle if a response is already
 * served for it.
 *
 * @param hh the history request handle
 */
void
TALER_BANK_history_cancel (struct TALER_BANK_HistoryHandle *hh)
{
  if (NULL != hh->job)
  {
    GNUNET_CURL_job_cancel (hh->job);
    hh->job = NULL;
  }
  curl_slist_free_all (hh->authh);
  GNUNET_free (hh->request_url);
  GNUNET_free (hh->bank_base_url);
  GNUNET_free (hh);
}


/* end of bank_api_history.c */
