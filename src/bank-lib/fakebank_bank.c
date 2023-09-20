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
 * @file bank-lib/fakebank_bank.c
 * @brief Main dispatcher for the Taler Bank API
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_bank.h"
#include "fakebank_bank_get_accounts.h"
#include "fakebank_bank_get_accounts_withdrawals.h"
#include "fakebank_bank_get_root.h"
#include "fakebank_bank_post_accounts_withdrawals.h"
#include "fakebank_bank_post_accounts_withdrawals_abort.h"
#include "fakebank_bank_post_accounts_withdrawals_confirm.h"
#include "fakebank_bank_testing_register.h"


MHD_RESULT
TALER_FAKEBANK_bank_main_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *url,
  const char *method,
  const char *upload_data,
  size_t *upload_data_size,
  void **con_cls)
{
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_HEAD))
    method = MHD_HTTP_METHOD_GET;
  if ( (0 == strcmp (url,
                     "/config")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_string ("version",
                               "0:0:0"),
      GNUNET_JSON_pack_string ("currency",
                               h->currency),
      GNUNET_JSON_pack_string ("name",
                               "taler-bank-access"));
  }
  if ( (0 == strcmp (url,
                     "/public-accounts")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_array_steal ("public_accounts",
                                    json_array ()));
  }
  if ( (0 == strncmp (url,
                      "/accounts/",
                      strlen ("/accounts/"))) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_POST)) )
  {
    const char *acc_name = &url[strlen ("/accounts/")];
    const char *end_acc = strchr (acc_name,
                                  '/');
    char *acc;
    MHD_RESULT ret;

    if ( (NULL == end_acc) ||
         (0 != strncmp (end_acc,
                        "/withdrawals",
                        strlen ("/withdrawals"))) )
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                         acc_name);
    }
    acc = GNUNET_strndup (acc_name,
                          end_acc - acc_name);
    end_acc += strlen ("/withdrawals");
    if ('/' == *end_acc)
    {
      const char *wid = end_acc + 1;
      const char *opid = strchr (wid,
                                 '/');
      char *wi;

      if ( (NULL == opid) ||
           ( (0 != strcmp (opid,
                           "/abort")) &&
             (0 != strcmp (opid,
                           "/confirm")) ) )
      {
        GNUNET_break_op (0);
        GNUNET_free (acc);
        return TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                           acc_name);
      }
      wi = GNUNET_strndup (wid,
                           opid - wid);
      if (0 == strcmp (opid,
                       "/abort"))
      {
        ret = TALER_FAKEBANK_bank_withdrawals_abort_ (h,
                                                      connection,
                                                      acc,
                                                      wi);
        GNUNET_free (wi);
        GNUNET_free (acc);
        return ret;
      }
      if (0 == strcmp (opid,
                       "/confirm"))
      {
        ret = TALER_FAKEBANK_bank_withdrawals_confirm_ (h,
                                                        connection,
                                                        acc,
                                                        wi);
        GNUNET_free (wi);
        GNUNET_free (acc);
        return ret;
      }
      GNUNET_assert (0);
    }
    ret = TALER_FAKEBANK_bank_post_account_withdrawals_ (
      h,
      connection,
      acc,
      upload_data,
      upload_data_size,
      con_cls);
    GNUNET_free (acc);
    return ret;
  }

  if ( (0 == strncmp (url,
                      "/accounts/",
                      strlen ("/accounts/"))) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    const char *acc_name = &url[strlen ("/accounts/")];
    const char *end_acc = strchr (acc_name,
                                  '/');
    const char *wid;
    char *acc;
    MHD_RESULT ret;

    if (NULL == end_acc)
    {
      return TALER_FAKEBANK_bank_get_accounts_ (h,
                                                connection,
                                                acc_name);
    }
    if (0 != strncmp (end_acc,
                      "/withdrawals/",
                      strlen ("/withdrawals/")))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                         acc_name);
    }
    acc = GNUNET_strndup (acc_name,
                          end_acc - acc_name);
    wid = &end_acc[strlen ("/withdrawals/")];
    ret = TALER_FAKEBANK_bank_get_accounts_withdrawals_ (h,
                                                         connection,
                                                         acc,
                                                         wid);
    GNUNET_free (acc);
    return ret;
  }
  /* FIXME: implement transactions API: 1.12.2 */

  /* registration API */
  if ( (0 == strcmp (url,
                     "/testing/register")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_POST)) )
  {
    return TALER_FAKEBANK_bank_testing_register_ (h,
                                                  connection,
                                                  upload_data,
                                                  upload_data_size,
                                                  con_cls);
  }
  TALER_LOG_ERROR ("Breaking URL: %s %s\n",
                   method,
                   url);
  GNUNET_break_op (0);
  return TALER_MHD_reply_with_error (
    connection,
    MHD_HTTP_NOT_FOUND,
    TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
    url);
}
