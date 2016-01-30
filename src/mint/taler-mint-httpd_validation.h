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
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-mint-httpd_validation.h
 * @brief helpers for calling the wire plugins to validate addresses
 * @author Christian Grothoff
 */
#ifndef TALER_MINT_HTTPD_VALIDATION_H
#define TALER_MINT_HTTPD_VALIDATION_H
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>


/**
 * Initialize validation subsystem.
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
int
TMH_VALIDATION_init (const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Shutdown validation subsystem.
 */
void
TMH_VALIDATION_done (void);


/**
 * Check if the given wire format JSON object is correctly formatted as
 * a wire address.
 *
 * @param wire the JSON wire format object
 * @return #GNUNET_YES if correctly formatted; #GNUNET_NO if not
 */
int
TMH_json_validate_wireformat (const json_t *wire);

/**
 * Check if we support the given wire method.
 *
 * @param type type of wire method to check
 * @return #GNUNET_YES if the method is supported
 */
int
TMH_VALIDATION_test_method (const char *type);


/**
 * Obtain supported validation methods as a JSON array,
 * and as a hash.
 *
 * @param[out] h set to the hash of the JSON methods
 * @return JSON array with the supported validation methods
 */
json_t *
TMH_VALIDATION_get_methods (struct GNUNET_HashCode *h);


#endif
