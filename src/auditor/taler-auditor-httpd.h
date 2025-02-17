/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2018 Taler Systems SA

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
 * @file taler-auditor-httpd.h
 * @brief Global declarations for the auditor
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_AUDITOR_HTTPD_H
#define TALER_AUDITOR_HTTPD_H

#include <microhttpd.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_plugin.h"


/**
 * Our DB plugin.
 */
extern struct TALER_AUDITORDB_Plugin *TAH_plugin;

/**
 * Our DB plugin to talk to the *exchange* database.
 */
extern struct TALER_EXCHANGEDB_Plugin *TAH_eplugin;

/**
 * Exchange master public key (according to the
 * configuration).  (global)
 */
extern struct TALER_MasterPublicKeyP TAH_master_public_key;

/**
 * Our currency.
 */
extern char *TAH_currency;

/**
 * @brief Struct describing an URL and the handler for it.
 */
struct TAH_RequestHandler
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
   * @param connection the MHD connection to handle
   * @param[in,out] connection_cls the connection's closure (can be updated)
   * @param upload_data upload data
   * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
   * @return MHD result code
   */
  MHD_RESULT (*handler)(
    /* const */ struct TAH_RequestHandler *rh,
    struct MHD_Connection *connection,
    void **connection_cls,
    const char *upload_data,
    size_t *upload_data_size,
    const char *const args[]);

  /**
   * Default response code.
   */
  unsigned int response_code;

  /**
   * Is client authentication required for this endpoint?
   */
  bool requires_auth;

  enum TALER_AUDITORDB_DeletableSuppressableTables table;
};


#endif
