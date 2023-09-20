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
 * @file bank-lib/fakebank_bank_testing_register.c
 * @brief implementation of /testing/register endpoint for the bank API
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_bank_testing_register.h"


MHD_RESULT
TALER_FAKEBANK_bank_testing_register_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
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
    const char *username;
    const char *password;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("username",
                               &username),
      GNUNET_JSON_spec_string ("password",
                               &password),
      GNUNET_JSON_spec_end ()
    };
    enum GNUNET_GenericReturnValue ret;
    struct Account *acc;

    if (GNUNET_OK !=
        (ret = TALER_MHD_parse_json_data (connection,
                                          json,
                                          spec)))
    {
      GNUNET_break_op (0);
      json_decref (json);
      return (GNUNET_NO == ret) ? MHD_YES : MHD_NO;
    }
    acc = TALER_FAKEBANK_lookup_account_ (h,
                                          username,
                                          NULL);
    if (NULL != acc)
    {
      if (0 != strcmp (password,
                       acc->password))
      {
        return TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_CONFLICT,
                                           TALER_EC_BANK_REGISTER_CONFLICT,
                                           "password");
      }
    }
    else
    {
      acc = TALER_FAKEBANK_lookup_account_ (h,
                                            username,
                                            username);
      GNUNET_assert (NULL != acc);
      acc->password = GNUNET_strdup (password);
      acc->balance = h->signup_bonus; /* magic money creation! */
    }
    res = TALER_MHD_reply_static (connection,
                                  MHD_HTTP_NO_CONTENT,
                                  NULL,
                                  NULL,
                                  0);
  }
  json_decref (json);
  return res;
}
