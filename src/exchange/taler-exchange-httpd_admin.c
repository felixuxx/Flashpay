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
 * Add an incoming transaction to the database.  Checks if the
 * transaction is fresh (not a duplicate) and if so adds it to
 * the database.
 *
 * @param connection the MHD connection to handle
 * @param reserve_pub public key of the reserve
 * @param amount amount to add to the reserve
 * @param execution_time when did we receive the wire transfer
 * @param sender_account_details which account send the funds
 * @param transfer_details information that uniquely identifies the transfer
 * @return MHD result code
 */
static int
execute_admin_add_incoming (struct MHD_Connection *connection,
			    const struct TALER_ReservePublicKeyP *reserve_pub,
			    const struct TALER_Amount *amount,
			    struct GNUNET_TIME_Absolute execution_time,
			    const json_t *sender_account_details,
			    const json_t *transfer_details)
{
  struct TALER_EXCHANGEDB_Session *session;
  int ret;
  void *json_str;

  if (NULL == (session = TEH_plugin->get_session (TEH_plugin->cls)))
  {
    GNUNET_break (0);
    return TEH_RESPONSE_reply_internal_db_error (connection,
						 TALER_EC_DB_SETUP_FAILED);
  }
  json_str = json_dumps (transfer_details,
                         JSON_INDENT(2));
  if (NULL == json_str)
  {
    GNUNET_break (0);
    return TEH_RESPONSE_reply_internal_db_error (connection,
						 TALER_EC_PARSER_OUT_OF_MEMORY);
  }
  ret = TEH_plugin->reserves_in_insert (TEH_plugin->cls,
                                        session,
                                        reserve_pub,
                                        amount,
                                        execution_time,
                                        sender_account_details,
                                        json_str,
                                        strlen (json_str));
  free (json_str);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return TEH_RESPONSE_reply_internal_db_error (connection,
						 TALER_EC_ADMIN_ADD_INCOMING_DB_STORE);
  }
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:s}",
                                       "status",
                                       (GNUNET_OK == ret)
                                       ? "NEW"
                                       : "DUP");
}


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
TEH_ADMIN_handler_admin_add_incoming (struct TEH_RequestHandler *rh,
                                      struct MHD_Connection *connection,
                                      void **connection_cls,
                                      const char *upload_data,
                                      size_t *upload_data_size)
{
  struct TALER_ReservePublicKeyP reserve_pub;
  struct TALER_Amount amount;
  struct GNUNET_TIME_Absolute at;
  enum TALER_ErrorCode ec;
  char *emsg;
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

  res = TEH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == root) )
    return MHD_YES;
  res = TEH_PARSE_json_data (connection,
                             root,
                             spec);
  json_decref (root);
  if (GNUNET_OK != res)
  {
    GNUNET_break_op (0);
    json_decref (root);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  if (TALER_EC_NONE !=
      (ec = TEH_json_validate_wireformat (sender_account_details,
                                          GNUNET_NO,
                                          &emsg)))
  {
    GNUNET_JSON_parse_free (spec);
    res = TEH_RESPONSE_reply_external_error (connection,
                                             ec,
                                             emsg);
    GNUNET_free (emsg);
    return res;
  }
  if (0 != strcasecmp (amount.currency,
                       TEH_exchange_currency_string))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Exchange uses currency `%s', but /admin/add/incoming tried to use currency `%s'\n",
                TEH_exchange_currency_string,
                amount.currency);
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_arg_invalid (connection,
					   TALER_EC_ADMIN_ADD_INCOMING_CURRENCY_UNSUPPORTED,
                                           "amount:currency");
  }
  res = execute_admin_add_incoming (connection,
				    &reserve_pub,
				    &amount,
				    at,
				    sender_account_details,
				    transfer_details);
  GNUNET_JSON_parse_free (spec);
  return res;
}

/* end of taler-exchange-httpd_admin.c */
