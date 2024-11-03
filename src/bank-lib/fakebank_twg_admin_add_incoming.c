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
 * @file bank-lib/fakebank_twg_admin_add_incoming.c
 * @brief library that fakes being a Taler bank for testcases
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_common_make_admin_transfer.h"
#include "fakebank_twg_admin_add_incoming.h"

MHD_RESULT
TALER_FAKEBANK_twg_admin_add_incoming_ (
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
  struct GNUNET_TIME_Timestamp timestamp;

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
    struct TALER_FullPayto debit_account;
    struct TALER_Amount amount;
    struct TALER_ReservePublicKeyP reserve_pub;
    char *debit;
    enum GNUNET_GenericReturnValue ret;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                   &reserve_pub),
      TALER_JSON_spec_full_payto_uri ("debit_account",
                                      &debit_account),
      TALER_JSON_spec_amount ("amount",
                              h->currency,
                              &amount),
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
    if (0 != strcasecmp (amount.currency,
                         h->currency))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Currency `%s' does not match our configuration\n",
                  amount.currency);
      json_decref (json);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_CONFLICT,
        TALER_EC_GENERIC_CURRENCY_MISMATCH,
        NULL);
    }
    debit = TALER_xtalerbank_account_from_payto (debit_account);
    if (NULL == debit)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PAYTO_URI_MALFORMED,
        debit_account.full_payto);
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Receiving incoming wire transfer: %s->%s, subject: %s, amount: %s\n",
                debit,
                account,
                TALER_B2S (&reserve_pub),
                TALER_amount2s (&amount));
    ret = TALER_FAKEBANK_make_admin_transfer_ (h,
                                               debit,
                                               account,
                                               &amount,
                                               &reserve_pub,
                                               &row_id,
                                               &timestamp);
    GNUNET_free (debit);
    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Reserve public key not unique\n");
      json_decref (json);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_CONFLICT,
        TALER_EC_BANK_DUPLICATE_RESERVE_PUB_SUBJECT,
        NULL);
    }
  }
  json_decref (json);

  /* Finally build response object */
  return TALER_MHD_REPLY_JSON_PACK (connection,
                                    MHD_HTTP_OK,
                                    GNUNET_JSON_pack_uint64 ("row_id",
                                                             row_id),
                                    GNUNET_JSON_pack_timestamp ("timestamp",
                                                                timestamp));
}
