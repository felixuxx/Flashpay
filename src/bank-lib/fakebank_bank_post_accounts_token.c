/*
  This file is part of TALER
  (C) 2016-2023 Taler Systems SA

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
 * @file bank-lib/fakebank_bank_post_accounts_token.c
 * @brief implementation of the bank API's POST /accounts/AID/token endpoint
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include <pthread.h>
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_bank_post_accounts_token.h"
#include "fakebank_common_lookup.h"


/**
 * Execute POST /accounts/$account_name/token request.
 *
 * @param h our fakebank handle
 * @param connection the connection
 * @param account_name name of the account
 * @param scope scope of the token
 * @param refreshable true if the token can be refreshed
 * @param duration how long should the token be valid
 * @return MHD result code
 */
static MHD_RESULT
do_post_account_token (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account_name,
  const char *scope_s,
  bool refreshable,
  struct GNUNET_TIME_Relative duration)
{
  struct Account *acc;
  char *tok;
  struct GNUNET_TIME_Absolute expiration;
  MHD_RESULT res;

  expiration = GNUNET_TIME_relative_to_absolute (duration);
  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  acc = TALER_FAKEBANK_lookup_account_ (h,
                                        account_name,
                                        NULL);
  if (NULL == acc)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_BANK_UNKNOWN_ACCOUNT,
                                       account_name);
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  /* We keep it simple and encode everything explicitly in the token,
     no real security here => no need to actually track tokens!
     (Note: this also means we cannot implement the token
     deletion/revocation or list APIs.) */
  GNUNET_asprintf (&tok,
                   "%s-%s-%s-%llu",
                   account_name,
                   scope_s,
                   refreshable ? "r" : "n",
                   (unsigned long long) expiration.abs_value_us);
  res = TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_string ("access_token",
                             tok),
    GNUNET_JSON_pack_timestamp ("expiration",
                                GNUNET_TIME_absolute_to_timestamp (expiration)))
  ;
  GNUNET_free (tok);
  return res;
}


/**
 * Handle POST /accounts/$account_name/token request.
 *
 * @param h our fakebank handle
 * @param connection the connection
 * @param account_name name of the account
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request
 * @return MHD result code
 */
MHD_RESULT
TALER_FAKEBANK_bank_post_accounts_token_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account_name,
  const void *upload_data,
  size_t *upload_data_size,
  void **con_cls)
{
  struct ConnectionContext *cc = *con_cls;
  enum GNUNET_JSON_PostResult pr;
  json_t *json;
  MHD_RESULT res;

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
    const char *scope_s;
    struct GNUNET_TIME_Relative duration
      = GNUNET_TIME_UNIT_HOURS; /* default */
    bool refreshable = false;
    const char *description = NULL;
    enum GNUNET_GenericReturnValue ret;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("scope",
                               &scope_s),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_relative_time ("duration",
                                        &duration),
        NULL),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_bool ("refreshable",
                               &refreshable),
        NULL),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_string ("description",
                                 &description),
        NULL),
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

    res = do_post_account_token (h,
                                 connection,
                                 account_name,
                                 scope_s,
                                 refreshable,
                                 duration);
  }
  json_decref (json);
  return res;
}
