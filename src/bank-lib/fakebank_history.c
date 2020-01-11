/*
  This file is part of TALER
  (C) 2016-2020 Taler Systems SA

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
 * @file bank-lib/fakebank_history.c
 * @brief definitions for the "/history" layer.
 * @author Marcello Stanisci <stanisci.m@gmail.com>
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_json_lib.h"
#include "fakebank.h"


int
TFH_build_history_response (struct MHD_Connection *connection,
                            struct Transaction *pos,
                            struct HistoryArgs *ha,
                            Skip skip,
                            Step step,
                            CheckAdvance advance)
{

  struct HistoryElement *history_results_head = NULL;
  struct HistoryElement *history_results_tail = NULL;
  struct HistoryElement *history_element = NULL;
  json_t *history;
  json_t *jresponse;
  int ret;

  while ( (NULL != pos) &&
          advance (ha,
                   pos) )
  {
    json_t *trans;
    char *subject;
    const char *sign;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Found transaction over %s from %llu to %llu\n",
                TALER_amount2s (&pos->amount),
                (unsigned long long) pos->debit_account,
                (unsigned long long) pos->credit_account);

    if ( (! ( ( (ha->account_number == pos->debit_account) &&
                (0 != (ha->direction & TALER_BANK_DIRECTION_DEBIT)) ) ||
              ( (ha->account_number == pos->credit_account) &&
                (0 != (ha->direction & TALER_BANK_DIRECTION_CREDIT) ) ) ) ) ||
         ( (0 == (ha->direction & TALER_BANK_DIRECTION_CANCEL)) &&
           (GNUNET_YES == pos->rejected) ) )
    {
      pos = skip (ha,
                  pos);
      continue;
    }

    GNUNET_asprintf (&subject,
                     "%s %s",
                     pos->subject,
                     pos->exchange_base_url);
    sign =
      (ha->account_number == pos->debit_account)
      ? (pos->rejected ? "cancel-" : "-")
      : (pos->rejected ? "cancel+" : "+");
    trans = json_pack
              ("{s:I, s:o, s:o, s:s, s:I, s:s}",
              "row_id", (json_int_t) pos->row_id,
              "date", GNUNET_JSON_from_time_abs (pos->date),
              "amount", TALER_JSON_from_amount (&pos->amount),
              "sign", sign,
              "counterpart", (json_int_t)
              ( (ha->account_number == pos->debit_account)
                ? pos->credit_account
                : pos->debit_account),
              "wt_subject", subject);
    GNUNET_assert (NULL != trans);
    GNUNET_free (subject);

    history_element = GNUNET_new (struct HistoryElement);
    history_element->element = trans;


    /* XXX: the ordering feature is missing.  */

    GNUNET_CONTAINER_DLL_insert_tail (history_results_head,
                                      history_results_tail,
                                      history_element);
    pos = step (ha, pos);
  }

  history = json_array ();
  if (NULL != history_results_head)
    history_element = history_results_head;

  while (NULL != history_element)
  {
    GNUNET_assert (0 ==
                   json_array_append_new (history,
                                          history_element->element));
    history_element = history_element->next;
    if (NULL != history_element)
      GNUNET_free_non_null (history_element->prev);
  }
  GNUNET_free_non_null (history_results_tail);

  if (0 == json_array_size (history))
  {
    struct MHD_Response *resp;

    json_decref (history);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Returning empty transaction history\n");
    resp = MHD_create_response_from_buffer
             (0,
             "",
             MHD_RESPMEM_PERSISTENT);
    ret = MHD_queue_response (connection,
                              MHD_HTTP_NO_CONTENT,
                              resp);
    MHD_destroy_response (resp);
    return ret;
  }

  jresponse = json_pack ("{s:o}",
                         "data",
                         history);
  if (NULL == jresponse)
  {
    GNUNET_break (0);
    return MHD_NO;
  }

  /* Finally build response object */
  {
    struct MHD_Response *resp;
    void *json_str;
    size_t json_len;

    json_str = json_dumps (jresponse,
                           JSON_INDENT (2));
    json_decref (jresponse);
    if (NULL == json_str)
    {
      GNUNET_break (0);
      return MHD_NO;
    }
    json_len = strlen (json_str);
    resp = MHD_create_response_from_buffer (json_len,
                                            json_str,
                                            MHD_RESPMEM_MUST_FREE);
    if (NULL == resp)
    {
      GNUNET_break (0);
      free (json_str);
      return MHD_NO;
    }
    (void) MHD_add_response_header (resp,
                                    MHD_HTTP_HEADER_CONTENT_TYPE,
                                    "application/json");
    ret = MHD_queue_response (connection,
                              MHD_HTTP_OK,
                              resp);
    MHD_destroy_response (resp);
  }
  return ret;
}
