/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

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
 */
#ifndef TALER_JSON_LIB_H_
#define TALER_JSON_LIB_H_

#include <jansson.h>


/**
 * Convert a TALER amount to a JSON object.
 *
 * @param amount the amount
 * @return a json object describing the amount
 */
json_t *
TALER_JSON_from_amount (struct TALER_Amount amount);


/**
 * Convert absolute timestamp to a json string.
 *
 * @param the time stamp
 * @return a json string with the timestamp in @a stamp
 */
json_t *
TALER_JSON_from_abs (struct GNUNET_TIME_Absolute stamp);


/**
 * Convert a signature (with purpose) to a JSON object representation.
 *
 * @param purpose purpose of the signature
 * @param signature the signature
 * @return the JSON reporesentation of the signature with purpose
 */
json_t *
TALER_JSON_from_sig (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
                     const struct GNUNET_CRYPTO_EddsaSignature *signature);


/**
 * Convert binary data to a JSON string
 * with the base32crockford encoding.
 *
 * @param data binary data
 * @param size size of @a data in bytes
 * @return json string that encodes @a data
 */
json_t *
TALER_JSON_from_data (const void *data, size_t size);


/**
 * Parse given JSON object to Amount
 *
 * @param json the json object representing Amount
 * @param r_amount where the amount has to be written
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
int
TALER_JSON_to_amount (json_t *json,
                      struct TALER_Amount *r_amount);

/**
 * Parse given JSON object to absolute time.
 *
 * @param json the json object representing absolute time in seconds
 * @param r_abs where the time has to be written
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
int
TALER_JSON_to_abs (json_t *json,
                   struct GNUNET_TIME_Absolute *r_abs);

/**
 * Parse given JSON object to data
 *
 * @param json the json object representing data
 * @param out the pointer to hold the parsed data.
 * @param out_size the size of @a out
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
int
TALER_JSON_to_data (json_t *json,
                    void *out,
                    size_t out_size);


#endif /* TALER_JSON_LIB_H_ */

/* End of taler_json_lib.h */
