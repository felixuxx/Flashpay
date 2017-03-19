/*
  This file is part of TALER
  Copyright (C) 2015-2017 GNUnet e.V. and INRIA

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
 * @file taler-exchange-httpd_wire.c
 * @brief Handle /wire requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_validation.h"
#include "taler-exchange-httpd_wire.h"
#include "taler_json_lib.h"
#include <jansson.h>

/**
 * Cached JSON for /wire response.
 */
static json_t *wire_methods;


/**
 * Convert fee structure to JSON result to be returned
 * as part of a /wire response.
 *
 * @param af fee structure to convert
 * @return NULL on error, otherwise json data structure for /wire.
 */
static json_t *
fees_to_json (struct TALER_EXCHANGEDB_AggregateFees *af)
{
  json_t *a;

  a = json_array ();
  while (NULL != af)
  {
    if ( (GNUNET_NO == GNUNET_TIME_round_abs (&af->start_date)) ||
         (GNUNET_NO == GNUNET_TIME_round_abs (&af->end_date)) )
    {
      json_decref (a);
      return NULL;
    }
    if (0 !=
        json_array_append_new (a,
                               json_pack ("{s:o, s:o, s:o, s:o}",
                                          "wire_fee", TALER_JSON_from_amount (&af->wire_fee),
                                          "start_date", GNUNET_JSON_from_time_abs (af->start_date),
                                          "end_date", GNUNET_JSON_from_time_abs (af->end_date),
                                          "sig", GNUNET_JSON_from_data_auto (&af->master_sig))))
    {
      GNUNET_break (0);
      json_decref (a);
      return NULL;
    }
    af = af->next;
  }
  return a;
}


/**
 * Obtain fee structure for @a wire_plugin_name wire transfers.
 *
 * @param wire_plugin_name name of the plugin to load fees for
 * @return JSON object (to be freed by caller) with fee structure
 */
json_t *
TEH_WIRE_get_fees (const char *wire_plugin_name)
{
  struct TALER_EXCHANGEDB_AggregateFees *af;
  json_t *j;
  struct GNUNET_TIME_Absolute now;

  af = TALER_EXCHANGEDB_fees_read (cfg,
                                   wire_plugin_name);
  now = GNUNET_TIME_absolute_get ();
  while ( (NULL != af) &&
          (af->end_date.abs_value_us < now.abs_value_us) )
  {
    struct TALER_EXCHANGEDB_AggregateFees *n = af->next;

    GNUNET_free (af);
    af = n;
  }
  if (NULL == af)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to find current wire transfer fees for `%s'\n",
                wire_plugin_name);
    return NULL;
  }
  j = fees_to_json (af);
  TALER_EXCHANGEDB_fees_free (af);
  return j;
}


/**
 * Handle a "/wire" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TEH_WIRE_handler_wire (struct TEH_RequestHandler *rh,
                       struct MHD_Connection *connection,
                       void **connection_cls,
                       const char *upload_data,
                       size_t *upload_data_size)
{
  GNUNET_assert (NULL != wire_methods);
  return TEH_RESPONSE_reply_json (connection,
                                  wire_methods,
                                  MHD_HTTP_OK);
}


/**
 * Initialize wire subsystem.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if we found no valid
 *         wire methods
 */
int
TEH_WIRE_init ()
{
  wire_methods = TEH_VALIDATION_get_wire_methods ("exchange-wire-incoming");
  if ( (NULL == wire_methods) ||
       (0 == json_object_size (wire_methods)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to find properly configured wire transfer method\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Initialize libgcrypt.
 */
void  __attribute__ ((destructor))
TEH_wire_cleanup ()
{
  if (NULL != wire_methods)
  {
    json_decref (wire_methods);
    wire_methods = NULL;
  }
}



/* end of taler-exchange-httpd_wire.c */
