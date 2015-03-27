/*
  This file is part of TALER
  Copyright (C) 2014 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-mint-httpd.h
 * @brief Global declarations for the mint
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_MINT_HTTPD_H
#define TALER_MINT_HTTPD_H

#include <microhttpd.h>

/**
 * For now, we just do EUR.  Should become configurable
 * in the future!
 */
#define TMH_MINT_CURRENCY "EUR"


/**
 * The mint's configuration.
 */
extern struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Main directory with mint data.
 * FIXME: should we have those globals really here?
 */
extern char *TMH_mint_directory;

/**
 * In which format does this MINT expect wiring instructions?
 */
extern char *TMH_expected_wire_format;

/**
 * Master public key (according to the
 * configuration in the mint directory).
 */
extern struct GNUNET_CRYPTO_EddsaPublicKey TMH_master_public_key;

/**
 * Private key of the mint we use to sign messages.
 */
extern struct GNUNET_CRYPTO_EddsaPrivateKey TMH_mint_private_signing_key;


/**
 * Struct describing an URL and the handler for it.
 */
struct TMH_RequestHandler
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
   * @param[IN|OUT] connection_cls the connection's closure (can be updated)
   * @param upload_data upload data
   * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
   * @return MHD result code
   */
  int (*handler)(struct TMH_RequestHandler *rh,
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
