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
 * @file taler-mint-httpd_parsing.h
 * @brief functions to parse incoming requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_MICROHTTPD_LIB_H_
#define TALER_MICROHTTPD_LIB_H_

#include <microhttpd.h>
#include <jansson.h>
#include "taler_util.h"


/**
 * Process a POST request containing a JSON object.  This
 * function realizes an MHD POST processor that will
 * (incrementally) process JSON data uploaded to the HTTP
 * server.  It will store the required state in the
 * "connection_cls", which must be cleaned up using
 * #TALER_MINT_parse_post_cleanup_callback().
 *
 * @param connection the MHD connection
 * @param con_cs the closure (points to a `struct Buffer *`)
 * @param upload_data the POST data
 * @param upload_data_size number of bytes in @a upload_data
 * @param json the JSON object for a completed request
 * @return
 *    #GNUNET_YES if json object was parsed or at least
 *               may be parsed in the future (call again);
 *               `*json` will be NULL if we need to be called again,
 *                and non-NULL if we are done.
 *    #GNUNET_NO is request incomplete or invalid
 *               (error message was generated)
 *    #GNUNET_SYSERR on internal error
 *               (we could not even queue an error message,
 *                close HTTP session with MHD_NO)
 */
int
TALER_MINT_parse_post_json (struct MHD_Connection *connection,
                            void **con_cls,
                            const char *upload_data,
                            size_t *upload_data_size,
                            json_t **json);


/**
 * Function called whenever we are done with a request
 * to clean up our state.
 *
 * @param con_cls value as it was left by
 *        #TALER_MINT_parse_post_json(), to be cleaned up
 */
void
TALER_MINT_parse_post_cleanup_callback (void *con_cls);


/**
 * Constants for JSON navigation description.
 */
enum TALER_MINT_JsonNavigationCommand
{
  /**
   * Access a field.
   * Param: const char *
   */
  JNAV_FIELD,

  /**
   * Access an array index.
   * Param: int
   */
  JNAV_INDEX,

  /**
   * Return base32crockford encoded data of
   * constant size.
   * Params: (void *, size_t)
   */
  JNAV_RET_DATA,

  /**
   * Return base32crockford encoded data of
   * variable size.
   * Params: (void **, size_t *)
   */
  JNAV_RET_DATA_VAR,

  /**
   * Return a json object, which must be
   * of the given type (JSON_* type constants,
   * or -1 for any type).
   * Params: (int, json_t **)
   */
  JNAV_RET_TYPED_JSON,

  /**
   * Return a `struct GNUNET_CRYPTO_rsa_PublicKey` which was
   * encoded as variable-size base32crockford encoded data.
   */
  JNAV_RET_RSA_PUBLIC_KEY,

  /**
   * Return a `struct GNUNET_CRYPTO_rsa_Signature` which was
   * encoded as variable-size base32crockford encoded data.
   */
  JNAV_RET_RSA_SIGNATURE,

  /**
   * Return a `struct TALER_Amount` which was
   * encoded within its own json object.
   */
  JNAV_RET_AMOUNT
};


/**
 * Navigate through a JSON tree.
 *
 * Sends an error response if navigation is impossible (i.e.
 * the JSON object is invalid)
 *
 * @param connection the connection to send an error response to
 * @param root the JSON node to start the navigation at.
 * @param ... navigation specification (see `enum TALER_MINT_JsonNavigationCommand`)
 * @return
 *    #GNUNET_YES if navigation was successful
 *    #GNUNET_NO if json is malformed, error response was generated
 *    #GNUNET_SYSERR on internal error
 */
int
GNUNET_MINT_parse_navigate_json (struct MHD_Connection *connection,
                                 const json_t *root,
                                 ...);


/**
 * Specification for how to parse a JSON field.
 */
struct GNUNET_MINT_ParseFieldSpec
{
  /**
   * Name of the field.  NULL only to terminate array.
   */
  const char *field_name;

  /**
   * Where to store the result.  Must have exactly
   * @e destination_size bytes, except if @e destination_size is zero.
   * NULL to skip assignment (but check presence of the value).
   */
  void *destination;

  /**
   * How big should the result be, 0 for variable size.  In
   * this case, @e destination must be a "void **", pointing
   * to a location that is currently NULL and is to be allocated.
   */
  size_t destination_size_in;

  /**
   * @e destination_size_out will then be set to the size of the
   * value that was stored in @e destination (useful for
   * variable-size allocations).
   */
  size_t destination_size_out;

  /**
   * Navigation command to use to extract the value.  Note that
   * #JNAV_RET_DATA or #JNAV_RET_DATA_VAR must be used for @e
   * destination_size_in and @e destination_size_out to have a
   * meaning.  #JNAV_FIELD and #JNAV_INDEX must not be used here!
   */
  enum TALER_MINT_JsonNavigationCommand command;

  /**
   * JSON type to use, only meaningful in connection with a @e command
   * value of #JNAV_RET_TYPED_JSON.  Typical values are
   * #JSON_ARRAY and #JSON_OBJECT.
   */
  int type;

};


/**
 * Parse JSON object into components based on the given field
 * specification.
 *
 * @param connection the connection to send an error response to
 * @param root the JSON node to start the navigation at.
 * @param spec field specification for the parser
 * @return
 *    #GNUNET_YES if navigation was successful (caller is responsible
 *                for freeing allocated variable-size data using
 *                #TALER_MINT_release_parsed_data() when done)
 *    #GNUNET_NO if json is malformed, error response was generated
 *    #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_parse_json_data (struct MHD_Connection *connection,
                            const json_t *root,
                            struct GNUNET_MINT_ParseFieldSpec *spec);


/**
 * Release all memory allocated for the variable-size fields in
 * the parser specification.
 *
 * @param spec specification to free
 */
void
TALER_MINT_release_parsed_data (struct GNUNET_MINT_ParseFieldSpec *spec);


/**
 * Generate line in parser specification for fixed-size value.
 *
 * @param field name of the field
 * @param value where to store the value
 */
#define TALER_MINT_PARSE_FIXED(field,value) { field, value, sizeof (*value), 0, JNAV_RET_DATA, 0 }

/**
 * Generate line in parser specification for variable-size value.
 *
 * @param field name of the field
 */
#define TALER_MINT_PARSE_VARIABLE(field) { field, NULL, 0, 0, JNAV_RET_DATA_VAR, 0 }

/**
 * Generate line in parser specification for JSON array value.
 *
 * @param field name of the field
 * @param ptraddr address of pointer to initialize (a `void **`)
 */
#define TALER_MINT_PARSE_ARRAY(field,ptraddr) { field, ptraddr, 0, 0, JNAV_RET_TYPED_JSON, JSON_ARRAY }

/**
 * Generate line in parser specification for JSON object value.
 *
 * @param field name of the field
 * @param ptraddr address of pointer to initialize (a `void **`)
 */
#define TALER_MINT_PARSE_OBJECT(field,ptraddr) { field, ptraddr, 0, 0, JNAV_RET_TYPED_JSON, JSON_OBJECT }

/**
 * Generate line in parser specification for RSA public key.
 *
 * @param field name of the field
 * @param ptraddr address of `struct GNUNET_CRYPTO_rsa_PublicKey *` initialize
 */
#define TALER_MINT_PARSE_RSA_PUBLIC_KEY(field,ptrpk) { field, ptrpk, 0, 0, JNAV_RET_RSA_PUBLIC_KEY, 0 }

/**
 * Generate line in parser specification for RSA public key.
 *
 * @param field name of the field
 * @param ptrsig address of `struct GNUNET_CRYPTO_rsa_Signature *` initialize
 */
#define TALER_MINT_PARSE_RSA_SIGNATURE(field,ptrsig) { field, ptrsig, 0, 0, JNAV_RET_RSA_SIGNATURE, 0 }

/**
 * Generate line in parser specification for an amount.
 *
 * @param field name of the field
 * @param amount a `struct TALER_Amount *` to initialize
 */
#define TALER_MINT_PARSE_AMOUNT(field,amount) { field, amount, sizeof(*amount), 0, JNAV_RET_AMOUNT, 0 }

/**
 * Generate line in parser specification indicating the end of the spec.
 */
#define TALER_MINT_PARSE_END { NULL, NULL, 0, 0, JNAV_FIELD, 0 }


/**
 * Parse amount specified in JSON format.
 *
 * @param connection the MHD connection (to report errors)
 * @param f json specification of the amount
 * @param amount[OUT] set to the amount specified in @a f
 * @return
 *    #GNUNET_YES if parsing was successful
 *    #GNUNET_NO if json is malformed, error response was generated
 *    #GNUNET_SYSERR on internal error, error response was not generated
 */
int
TALER_MINT_parse_amount_json (struct MHD_Connection *connection,
                              json_t *f,
                              struct TALER_Amount *amount);


/**
 * Extraxt fixed-size base32crockford encoded data from request.
 *
 * Queues an error response to the connection if the parameter is missing or
 * invalid.
 *
 * @param connection the MHD connection
 * @param param_name the name of the parameter with the key
 * @param[out] out_data pointer to store the result
 * @param out_size expected size of @a out_data
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is absent or malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
int
TALER_MINT_mhd_request_arg_data (struct MHD_Connection *connection,
                                 const char *param_name,
                                 void *out_data,
                                 size_t out_size);


/**
 * Extraxt variable-size base32crockford encoded data from request.
 *
 * Queues an error response to the connection if the parameter is missing
 * or the encoding is invalid.
 *
 * @param connection the MHD connection
 * @param param_name the name of the parameter with the key
 * @param[out] out_data pointer to allocate buffer and store the result
 * @param[out] out_size set to the size of the buffer allocated in @a out_data
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is absent or malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
int
TALER_MINT_mhd_request_var_arg_data (struct MHD_Connection *connection,
                                     const char *param_name,
                                     void **out_data,
                                     size_t *out_size);




#endif /* TALER_MICROHTTPD_LIB_H_ */
