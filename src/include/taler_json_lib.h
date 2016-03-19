/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file include/taler_json_lib.h
 * @brief helper functions for JSON processing using libjansson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#ifndef TALER_JSON_LIB_H_
#define TALER_JSON_LIB_H_

#include <jansson.h>
#include <gnunet/gnunet_json_lib.h>
#include "taler_util.h"

/**
 * Print JSON parsing related error information
 * @deprecated
 */
#define TALER_json_warn(error)                                         \
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,                                \
              "JSON parsing failed at %s:%u: %s (%s)\n",                  \
              __FILE__, __LINE__, error.text, error.source)


/**
 * Convert a TALER amount to a JSON object.
 *
 * @param amount the amount
 * @return a json object describing the amount
 */
json_t *
TALER_JSON_from_amount (const struct TALER_Amount *amount);


/**
 * Provide specification to parse given JSON object to an amount.
 *
 * @param name name of the amount field in the JSON
 * @param[out] r_amount where the amount has to be written
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_amount (const char *name,
                        struct TALER_Amount *r_amount);


/**
 * Generate line in parser specification for denomination public key.
 *
 * @param field name of the field
 * @param[out] pk key to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_denomination_public_key (const char *field,
                                         struct TALER_DenominationPublicKey *pk);


/**
 * Generate line in parser specification for denomination signature.
 *
 * @param field name of the field
 * @param sig the signature to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_denomination_signature (const char *field,
                                        struct TALER_DenominationSignature *sig);


/**
 * Hash a JSON for binary signing.
 *
 * @param[in] json some JSON value to hash
 * @param[out] hc resulting hash code
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_JSON_hash (json_t *json,
                 struct GNUNET_HashCode *hc);

#endif /* TALER_JSON_LIB_H_ */

/* End of taler_json_lib.h */
