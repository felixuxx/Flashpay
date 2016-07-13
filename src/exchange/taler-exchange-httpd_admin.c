/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_admin.c
 * @brief Handle /admin/ requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler-exchange-httpd_admin.h"
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_validation.h"



/**
 * Handle a "/admin/add/incoming" request.  Parses the
 * given "reserve_pub", "amount", "transaction" and "h_wire"
 * details and adds the respective transaction to the database.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_ADMIN_handler_admin_add_incoming (struct TMH_RequestHandler *rh,
                                      struct MHD_Connection *connection,
                                      void **connection_cls,
                                      const char *upload_data,
                                      size_t *upload_data_size)
{
  struct TALER_ReservePublicKeyP reserve_pub;
  struct TALER_Amount amount;
  struct GNUNET_TIME_Absolute at;
  json_t *sender_account_details;
  json_t *transfer_details;
  json_t *root;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_pub", &reserve_pub),
    TALER_JSON_spec_amount ("amount", &amount),
    GNUNET_JSON_spec_absolute_time ("execution_date", &at),
    GNUNET_JSON_spec_json ("sender_account_details", &sender_account_details),
    GNUNET_JSON_spec_json ("transfer_details", &transfer_details),
    GNUNET_JSON_spec_end ()
  };
  int res;

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == root) )
    return MHD_YES;
  res = TMH_PARSE_json_data (connection,
                             root,
                             spec);
  json_decref (root);
  if (GNUNET_OK != res)
  {
    GNUNET_break_op (0);
    json_decref (root);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  if (GNUNET_YES !=
      TMH_json_validate_wireformat (sender_account_details,
                                    GNUNET_NO))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TMH_RESPONSE_reply_arg_unknown (connection,
                                           "sender_account_details");
  }
  if (0 != strcasecmp (amount.currency,
                       TMH_exchange_currency_string))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Exchange uses currency `%s', but /admin/add/incoming tried to use currency `%s'\n",
                TMH_exchange_currency_string,
                amount.currency);
    GNUNET_JSON_parse_free (spec);
    return TMH_RESPONSE_reply_arg_invalid (connection,
                                           "amount:currency");
  }
  res = TMH_DB_execute_admin_add_incoming (connection,
                                           &reserve_pub,
                                           &amount,
                                           at,
                                           sender_account_details,
                                           transfer_details);
  GNUNET_JSON_parse_free (spec);
  return res;
}

/* end of taler-exchange-httpd_admin.c */
