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
#include "fakebank_tbr.h"
#include "fakebank_twg.h"
#include "fakebank_bank_get_accounts.h"
#include "fakebank_bank_get_withdrawals.h"
#include "fakebank_bank_get_root.h"
#include "fakebank_bank_post_accounts_withdrawals.h"
#include "fakebank_bank_post_withdrawals_abort.h"
#include "fakebank_bank_post_withdrawals_confirm.h"
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
                     "/")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    /* GET / */
    return TALER_FAKEBANK_bank_get_root_ (h,
                                          connection);
  }

  if ( (0 == strcmp (url,
                     "/config")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    /* GET /config */
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_string ("version",
                               "0:0:0"),
      GNUNET_JSON_pack_string ("currency",
                               h->currency),
      GNUNET_JSON_pack_string ("name",
                               "taler-corebank"));
  }

  if ( (0 == strcmp (url,
                     "/public-accounts")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    /* GET /public-accounts */
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_array_steal ("public_accounts",
                                    json_array ()));
  }

  /* account registration API */
  if ( (0 == strcmp (url,
                     "/accounts")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_POST)) )
  {
    /* POST /accounts */
    return TALER_FAKEBANK_bank_testing_register_ (h,
                                                  connection,
                                                  upload_data,
                                                  upload_data_size,
                                                  con_cls);
  }

  if ( (0 == strcmp (url,
                     "/accounts")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    /* GET /accounts */
    GNUNET_break (0); /* not implemented */
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_NOT_IMPLEMENTED,
      TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
      url);
  }

  if ( (0 == strcmp (url,
                     "/cashout-rate")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    /* GET /cashout-rate */
    GNUNET_break (0); /* not implemented */
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_NOT_IMPLEMENTED,
      TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
      url);
  }

  if ( (0 == strcmp (url,
                     "/cashouts")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    /* GET /cashouts */
    GNUNET_break (0); /* not implemented */
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_NOT_IMPLEMENTED,
      TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
      url);
  }

  if ( (0 == strncmp (url,
                      "/withdrawals/",
                      strlen ("/withdrawals/"))) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    /* GET /withdrawals/$WID */
    const char *wid;

    wid = &url[strlen ("/withdrawals/")];
    return TALER_FAKEBANK_bank_get_withdrawals_ (h,
                                                 connection,
                                                 wid);
  }

  if ( (0 == strncmp (url,
                      "/withdrawals/",
                      strlen ("/withdrawals/"))) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_POST)) )
  {
    /* POST /withdrawals/$WID* */
    const char *wid = url + strlen ("/withdrawals/");
    const char *opid = strchr (wid,
                               '/');
    char *wi;

    if (NULL == opid)
    {
      /* POST /withdrawals/$WID (not defined) */
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                         url);
    }
    wi = GNUNET_strndup (wid,
                         opid - wid);
    if (0 == strcmp (opid,
                     "/abort"))
    {
      /* POST /withdrawals/$WID/abort */
      MHD_RESULT ret;

      ret = TALER_FAKEBANK_bank_withdrawals_abort_ (h,
                                                    connection,
                                                    wi);
      GNUNET_free (wi);
      return ret;
    }
    if (0 == strcmp (opid,
                     "/confirm"))
    {
      /* POST /withdrawals/$WID/confirm */
      MHD_RESULT ret;

      ret = TALER_FAKEBANK_bank_withdrawals_confirm_ (h,
                                                      connection,
                                                      wi);
      GNUNET_free (wi);
      return ret;
    }
  }

  if (0 == strncmp (url,
                    "/accounts/",
                    strlen ("/accounts/")))
  {
    const char *acc_name = &url[strlen ("/accounts/")];
    const char *end_acc = strchr (acc_name,
                                  '/');

    if ( (NULL != end_acc) &&
         (0 == strncmp (end_acc,
                        "/taler-wire-gateway/",
                        strlen ("/taler-wire-gateway/"))) )
    {
      /* $METHOD /accounts/$ACCOUNT/taler-wire-gateway/ */
      char *acc;
      MHD_RESULT ret;

      acc = GNUNET_strndup (acc_name,
                            end_acc - acc_name);
      end_acc += strlen ("/taler-wire-gateway");
      ret = TALER_FAKEBANK_twg_main_ (h,
                                      connection,
                                      acc,
                                      end_acc,
                                      method,
                                      upload_data,
                                      upload_data_size,
                                      con_cls);
      GNUNET_free (acc);
      return ret;
    }

    if ( (NULL != end_acc) &&
         (0 == strncmp (end_acc,
                        "/taler-revenue/",
                        strlen ("/taler-revenue/"))) )
    {
      /* $METHOD /accounts/$ACCOUNT/taler-revenue/ */
      char *acc;
      MHD_RESULT ret;

      acc = GNUNET_strndup (acc_name,
                            end_acc - acc_name);
      end_acc += strlen ("/taler-revenue");
      ret = TALER_FAKEBANK_tbr_main_ (h,
                                      connection,
                                      acc,
                                      end_acc,
                                      method,
                                      upload_data,
                                      upload_data_size,
                                      con_cls);
      GNUNET_free (acc);
      return ret;
    }

    if ( (NULL == end_acc) &&
         (0 == strcasecmp (method,
                           MHD_HTTP_METHOD_GET)) )
    {
      /* GET /accounts/$ACCOUNT */
      return TALER_FAKEBANK_bank_get_accounts_ (h,
                                                connection,
                                                acc_name);
    }

    if ( (NULL == end_acc) &&
         (0 == strcasecmp (method,
                           MHD_HTTP_METHOD_PATCH)) )
    {
      /* PATCH /accounts/$USERNAME */
      GNUNET_break (0); /* not implemented */
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_NOT_IMPLEMENTED,
        TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
        url);
    }

    if ( (NULL == end_acc) &&
         (0 == strcasecmp (method,
                           MHD_HTTP_METHOD_DELETE)) )
    {
      /* DELETE /accounts/$USERNAME */
      GNUNET_break (0); /* not implemented */
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_NOT_IMPLEMENTED,
        TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
        url);
    }

    if ( (NULL != end_acc) &&
         (0 == strcmp ("/auth",
                       end_acc)) &&
         (0 == strcasecmp (method,
                           MHD_HTTP_METHOD_PATCH)) )
    {
      /* PATCH /accounts/$USERNAME/auth */
      GNUNET_break (0); /* not implemented */
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_NOT_IMPLEMENTED,
        TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
        url);
    }

    if ( (NULL != end_acc) &&
         (0 == strcasecmp (method,
                           MHD_HTTP_METHOD_GET)) )
    {
      /* GET /accounts/$ACCOUNT/+ */

      if (0 == strcmp (end_acc,
                       "/transactions"))
      {
        /* GET /accounts/$USERNAME/transactions */
        GNUNET_break (0); /* not implemented */
        return TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_NOT_IMPLEMENTED,
          TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
          url);
      }
      if (0 == strncmp (end_acc,
                        "/transactions/",
                        strlen ("/transactions/")))
      {
        /* GET /accounts/$USERNAME/transactions/$TID */
        GNUNET_break (0); /* not implemented */
        return TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_NOT_IMPLEMENTED,
          TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
          url);
      }
      if (0 == strcmp (end_acc,
                       "/withdrawals"))
      {
        /* GET /accounts/$USERNAME/withdrawals */
        GNUNET_break (0); /* not implemented */
        return TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_NOT_IMPLEMENTED,
          TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
          url);
      }
      if (0 == strcmp (end_acc,
                       "/cashouts"))
      {
        /* GET /accounts/$USERNAME/cashouts */
        GNUNET_break (0); /* not implemented */
        return TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_NOT_IMPLEMENTED,
          TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
          url);
      }
      if (0 == strncmp (end_acc,
                        "/cashouts/",
                        strlen ("/cashouts/")))
      {
        /* GET /accounts/$USERNAME/cashouts/$CID */
        GNUNET_break (0); /* not implemented */
        return TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_NOT_IMPLEMENTED,
          TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
          url);
      }


      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                         acc_name);
    }

    if ( (NULL != end_acc) &&
         (0 == strcasecmp (method,
                           MHD_HTTP_METHOD_POST)) )
    {
      /* POST /accounts/$ACCOUNT/+ */
      char *acc;

      acc = GNUNET_strndup (acc_name,
                            end_acc - acc_name);
      if (0 == strcmp (end_acc,
                       "/cashouts"))
      {
        /* POST /accounts/$USERNAME/cashouts */
        GNUNET_break (0); /* not implemented */
        GNUNET_free (acc);
        return TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_NOT_IMPLEMENTED,
          TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
          url);
      }
      if (0 == strncmp (end_acc,
                        "/cashouts/",
                        strlen ("/cashouts/")))
      {
        /* POST /accounts/$USERNAME/cashouts/+ */
        const char *cid = end_acc + strlen ("/cashouts/");
        const char *opid = strchr (cid,
                                   '/');
        char *ci;

        if (NULL == opid)
        {
          /* POST /accounts/$ACCOUNT/cashouts/$CID (not defined) */
          GNUNET_break_op (0);
          GNUNET_free (acc);
          return TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_NOT_FOUND,
                                             TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                             acc_name);
        }
        ci = GNUNET_strndup (cid,
                             opid - cid);
        if (0 == strcmp (opid,
                         "/abort"))
        {
          GNUNET_break (0); /* not implemented */
          GNUNET_free (ci);
          GNUNET_free (acc);
          return TALER_MHD_reply_with_error (
            connection,
            MHD_HTTP_NOT_IMPLEMENTED,
            TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
            url);
        }
        if (0 == strcmp (opid,
                         "/confirm"))
        {
          GNUNET_break (0); /* not implemented */
          GNUNET_free (ci);
          GNUNET_free (acc);
          return TALER_MHD_reply_with_error (
            connection,
            MHD_HTTP_NOT_IMPLEMENTED,
            TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR,
            url);
        }
      }

      if (0 == strcmp (end_acc,
                       "/withdrawals"))
      {
        /* POST /accounts/$ACCOUNT/withdrawals */
        MHD_RESULT ret;

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
    }
  }

  GNUNET_break_op (0);
  TALER_LOG_ERROR ("Breaking URL: %s %s\n",
                   method,
                   url);
  return TALER_MHD_reply_with_error (connection,
                                     MHD_HTTP_NOT_FOUND,
                                     TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                     url);
}
