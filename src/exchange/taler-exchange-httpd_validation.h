/*
  This file is part of TALER
  Copyright (C) 2016 GNUnet e.V.

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
 * @file taler-exchange-httpd_validation.h
 * @brief helpers for calling the wire plugins to validate addresses
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_VALIDATION_H
#define TALER_EXCHANGE_HTTPD_VALIDATION_H
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>


/**
 * Initialize validation subsystem.
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
int
TEH_VALIDATION_init (const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Shutdown validation subsystem.
 */
void
TEH_VALIDATION_done (void);


/**
 * Check if the given wire format JSON object is correctly formatted as
 * a wire address.
 *
 * @param wire the JSON wire format object
 * @param ours #GNUNET_YES if the signature should match our master key
 * @param[out] emsg set to error message if we return an error code
 * @return #TALER_EC_NONE if correctly formatted; otherwise error code
 */
enum TALER_ErrorCode
TEH_json_validate_wireformat (const json_t *wire,
                              int ours,
                              char **emsg);


/**
 * Obtain JSON of the supported wire methods for a given
 * account name prefix.
 *
 * @return JSON array with the supported validation methods
 */
json_t *
TEH_VALIDATION_get_wire_methods (void);


#endif
