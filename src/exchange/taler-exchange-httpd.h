/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2020 Taler Systems SA

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
 * @file taler-exchange-httpd.h
 * @brief Global declarations for the exchange
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_H
#define TALER_EXCHANGE_HTTPD_H

#include <microhttpd.h>
#include "taler_json_lib.h"
#include "taler_crypto_lib.h"
#include <gnunet/gnunet_mhd_compat.h>


/**
 * How long is caching /keys allowed at most?
 */
extern struct GNUNET_TIME_Relative TEH_max_keys_caching;

/**
 * The exchange's configuration.
 */
extern struct GNUNET_CONFIGURATION_Handle *TEH_cfg;

/**
 * Main directory with exchange data.
 */
extern char *TEH_exchange_directory;

/**
 * Are clients allowed to request /keys for times other than the
 * current time? Allowing this could be abused in a DoS-attack
 * as building new /keys responses is expensive. Should only be
 * enabled for testcases, development and test systems.
 */
extern int TEH_allow_keys_timetravel;

/**
 * Main directory with revocation data.
 */
extern char *TEH_revocation_directory;

/**
 * Master public key (according to the
 * configuration in the exchange directory).
 */
extern struct TALER_MasterPublicKeyP TEH_master_public_key;

/**
 * Our DB plugin.
 */
extern struct TALER_EXCHANGEDB_Plugin *TEH_plugin;

/**
 * Our currency.
 */
extern char *TEH_currency;

/**
 * @brief Struct describing an URL and the handler for it.
 */
struct TEH_RequestHandler
{

  /**
   * URL the handler is for (first part only).
   */
  const char *url;

  /**
   * Method the handler is for.
   */
  const char *method;

  /**
   * Callbacks for handling of the request. Which one is used
   * depends on @e method.
   */
  union
  {
    /**
     * Function to call to handle a GET requests (and those
     * with @e method NULL).
     *
     * @param rh this struct
     * @param mime_type the @e mime_type for the reply (hint, can be NULL)
     * @param connection the MHD connection to handle
     * @param args array of arguments, needs to be of length @e args_expected
     * @return MHD result code
     */
    MHD_RESULT (*get)(const struct TEH_RequestHandler *rh,
                      struct MHD_Connection *connection,
                      const char *const args[]);


    /**
     * Function to call to handle a POST request.
     *
     * @param rh this struct
     * @param mime_type the @e mime_type for the reply (hint, can be NULL)
     * @param connection the MHD connection to handle
     * @param json uploaded JSON data
     * @param args array of arguments, needs to be of length @e args_expected
     * @return MHD result code
     */
    MHD_RESULT (*post)(const struct TEH_RequestHandler *rh,
                       struct MHD_Connection *connection,
                       const json_t *root,
                       const char *const args[]);

  } handler;

  /**
   * Number of arguments this handler expects in the @a args array.
   */
  unsigned int nargs;

  /**
   * Is the number of arguments given in @e nargs only an upper bound,
   * and calling with fewer arguments could be OK?
   */
  bool nargs_is_upper_bound;

  /**
   * Mime type to use in reply (hint, can be NULL).
   */
  const char *mime_type;

  /**
   * Raw data for the @e handler, can be NULL for none provided.
   */
  const void *data;

  /**
   * Number of bytes in @e data, 0 for data is 0-terminated (!).
   */
  size_t data_size;

  /**
   * Default response code. 0 for none provided.
   */
  unsigned int response_code;
};


#endif
