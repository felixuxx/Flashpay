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
 * @file taler-exchange-httpd.h
 * @brief Global declarations for the exchange
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 *
 * FIXME: Consider which of these need to really be globals...
 */
#ifndef TALER_EXCHANGE_HTTPD_H
#define TALER_EXCHANGE_HTTPD_H

#include <microhttpd.h>


/**
 * Which currency is used by this exchange?
 */
extern char *TEH_exchange_currency_string;

/**
 * Should we return "Connection: close" in each response?
 */
extern int TEH_exchange_connection_close;

/**
 * How long is caching /keys allowed at most?
 */
extern struct GNUNET_TIME_Relative max_keys_caching;

/**
 * The exchange's configuration.
 */
extern struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Main directory with exchange data.
 */
extern char *TEH_exchange_directory;

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
 * Private key of the exchange we use to sign messages.
 */
extern struct GNUNET_CRYPTO_EddsaPrivateKey TEH_exchange_private_signing_key;

/**
 * Our DB plugin.
 */
extern struct TALER_EXCHANGEDB_Plugin *TEH_plugin;


/**
 * @brief Struct describing an URL and the handler for it.
 */
struct TEH_RequestHandler
{

  /**
   * URL the handler is for.
   */
  const char *url;

  /**
   * Method the handler is for, NULL for "all".
   */
  const char *method;

  /**
   * Mime type to use in reply (hint, can be NULL).
   */
  const char *mime_type;

  /**
   * Raw data for the @e handler
   */
  const void *data;

  /**
   * Number of bytes in @e data, 0 for 0-terminated.
   */
  size_t data_size;

  /**
   * Function to call to handle the request.
   *
   * @param rh this struct
   * @param mime_type the @e mime_type for the reply (hint, can be NULL)
   * @param connection the MHD connection to handle
   * @param[in,out] connection_cls the connection's closure (can be updated)
   * @param upload_data upload data
   * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
   * @return MHD result code
   */
  int (*handler)(struct TEH_RequestHandler *rh,
                 struct MHD_Connection *connection,
                 void **connection_cls,
                 const char *upload_data,
                 size_t *upload_data_size);

  /**
   * Default response code.
   */
  int response_code;
};


#endif
