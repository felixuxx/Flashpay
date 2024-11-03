/*
  This file is part of TALER
  (C) 2016-2024 Taler Systems SA

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
 * @file bank-lib/fakebank_twg_transfer.c
 * @brief implementation of the Taler Wire Gateway "/transfer" endpoint
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_common_transact.h"
#include "fakebank_twg_transfer.h"


/**
 * Handle incoming HTTP request for /transfer.
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @param account account making the transfer
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request (a `struct ConnectionContext *`)
 * @return MHD result code
 */
MHD_RESULT
TALER_FAKEBANK_handle_transfer_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  const char *upload_data,
  size_t *upload_data_size,
  void **con_cls)
{
  struct ConnectionContext *cc = *con_cls;
  enum GNUNET_JSON_PostResult pr;
  json_t *json;
  uint64_t row_id;
  struct GNUNET_TIME_Timestamp ts;

  if (NULL == cc)
  {
    cc = GNUNET_new (struct ConnectionContext);
    cc->ctx_cleaner = &GNUNET_JSON_post_parser_cleanup;
    *con_cls = cc;
  }
  pr = GNUNET_JSON_post_parser (REQUEST_BUFFER_MAX,
                                connection,
                                &cc->ctx,
                                upload_data,
                                upload_data_size,
                                &json);
  switch (pr)
  {
  case GNUNET_JSON_PR_OUT_OF_MEMORY:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_CONTINUE:
    return MHD_YES;
  case GNUNET_JSON_PR_REQUEST_TOO_LARGE:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_JSON_INVALID:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_SUCCESS:
    break;
  }
  {
    struct GNUNET_HashCode uuid;
    struct TALER_WireTransferIdentifierRawP wtid;
    struct TALER_FullPayto credit_account;
    char *credit;
    const char *base_url;
    struct TALER_Amount amount;
    enum GNUNET_GenericReturnValue ret;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("request_uid",
                                   &uuid),
      TALER_JSON_spec_amount ("amount",
                              h->currency,
                              &amount),
      GNUNET_JSON_spec_string ("exchange_base_url",
                               &base_url),
      GNUNET_JSON_spec_fixed_auto ("wtid",
                                   &wtid),
      TALER_JSON_spec_full_payto_uri ("credit_account",
                                      &credit_account),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        (ret = TALER_MHD_parse_json_data (connection,
                                          json,
                                          spec)))
    {
      GNUNET_break_op (0);
      json_decref (json);
      return (GNUNET_NO == ret) ? MHD_YES : MHD_NO;
    }
    credit = TALER_xtalerbank_account_from_payto (credit_account);
    if (NULL == credit)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PAYTO_URI_MALFORMED,
        credit_account.full_payto);
    }
    ret = TALER_FAKEBANK_make_transfer_ (h,
                                         account,
                                         credit,
                                         &amount,
                                         &wtid,
                                         base_url,
                                         &uuid,
                                         &row_id,
                                         &ts);
    if (GNUNET_OK != ret)
    {
      MHD_RESULT res;
      char *uids;

      GNUNET_break (0);
      uids = GNUNET_STRINGS_data_to_string_alloc (&uuid,
                                                  sizeof (uuid));
      json_decref (json);
      res = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_CONFLICT,
                                        TALER_EC_BANK_TRANSFER_REQUEST_UID_REUSED,
                                        uids);
      GNUNET_free (uids);
      return res;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Receiving incoming wire transfer: %s->%s, subject: %s, amount: %s, from %s\n",
                account,
                credit,
                TALER_B2S (&wtid),
                TALER_amount2s (&amount),
                base_url);
    GNUNET_free (credit);
  }
  json_decref (json);

  /* Finally build response object */
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_uint64 ("row_id",
                             row_id),
    GNUNET_JSON_pack_timestamp ("timestamp",
                                ts));
}
