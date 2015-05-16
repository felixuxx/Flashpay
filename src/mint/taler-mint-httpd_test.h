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
 * @file taler-mint-httpd_test.h
 * @brief Handle /test requests
 * @author Christian Grothoff
 */
#ifndef TALER_MINT_HTTPD_TEST_H
#define TALER_MINT_HTTPD_TEST_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-mint-httpd.h"


/**
 * Handle a "/test/base32" request.  Parses the JSON in the post, runs
 * the Crockford Base32 decoder on the "input" field in the JSON,
 * hashes the result and sends the hashed value back as a JSON 
 * string with in Base32 Crockford encoding.  Thus, this API
 * allows testing the hashing and Crockford encoding/decoding
 * functions.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_TEST_handler_test_base32 (struct TMH_RequestHandler *rh,
			      struct MHD_Connection *connection,
			      void **connection_cls,
			      const char *upload_data,
			      size_t *upload_data_size);


/**
 * Handle a "/test/encrypt" request.  Parses the JSON in the post,
 * runs the Crockford Base32 decoder on the "input" field in the JSON,
 * and encrypts the result with a shared secret derived using the HKDF
 * function with salt "skey" and IV derived with salt "iv" of the
 * Crockford Base32-encoded "key_hash" field in the JSON.  The
 * symmetric encryption is the AES/Twofish double-encryption used in
 * Taler/GNUnet.  The resulting ciphertext is returned as a Crockford
 * Base32 encoded JSON string.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TMH_TEST_handler_test_encrypt (struct TMH_RequestHandler *rh,
			       struct MHD_Connection *connection,
			       void **connection_cls,
			       const char *upload_data,
			       size_t *upload_data_size);


/**
 * Handle a "/test/hkdf" request.  Parses the JSON in the post, runs
 * the Crockford Base32 decoder on the "input" field in the JSON,
 * computes `HKDF(input, "salty")` and sends the result back as a JSON
 * string with in Base32 Crockford encoding.  Thus, this API allows
 * testing the use of the (H)KDF.  Note that the test fixes the
 * input and output sizes and the salt (and the hash functions used
 * by the HKDF), so this is only useful to test the HKDF in the
 * same way it will be used within Taler/GNUnet.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TMH_TEST_handler_test_hkdf (struct TMH_RequestHandler *rh,
			    struct MHD_Connection *connection,
			    void **connection_cls,
			    const char *upload_data,
			    size_t *upload_data_size);


/**
 * Handle a "/test/ecdhe" request.  Parses the JSON in the post, which
 * must contain a "ecdhe_pub" with a public key and an "ecdhe_priv"
 * with a private key.  The reply is the resulting JSON is an object
 * with the field "ecdh_hash" containing a Crockford Base32-encoded
 * string representing the hash derived via ECDH of the two keys.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_TEST_handler_test_ecdhe (struct TMH_RequestHandler *rh,
			     struct MHD_Connection *connection,
			     void **connection_cls,
			     const char *upload_data,
			     size_t *upload_data_size);


/**
 * Handle a "/test/eddsa" request.  Parses the JSON in the post, 
 * which must contain a "eddsa_pub" with a public key and an
 *"ecdsa_sig" with the corresponding signature for a purpose
 * of #TALER_SIGNATURE_CLIENT_TEST_EDDSA.  If the signature is
 * valid, a reply with a #TALER_SIGNATURE_MINT_TEST_EDDSA is 
 * returned using the same JSON format.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_TEST_handler_test_eddsa (struct TMH_RequestHandler *rh,
			     struct MHD_Connection *connection,
			     void **connection_cls,
			     const char *upload_data,
			     size_t *upload_data_size);

/**
 * Handle a "/test/rsa" request.  Parses the JSON in the post, which
 * must contain an "blind_ev" blinded value.  An RSA public key
 * ("rsa_pub") and a blinded signature ("rsa_blind_sig") are returned.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_TEST_handler_test_rsa (struct TMH_RequestHandler *rh,
			   struct MHD_Connection *connection,
			   void **connection_cls,
			   const char *upload_data,
			   size_t *upload_data_size);


/**
 * Handle a "/test/transfer" request.  Parses the JSON in the post, 
 * which must contain a "secret_enc" with the encrypted link secret,
 * a "trans_priv" with the transfer private key, a "coin_pub" with
 * a coin public key.  A reply with the decrypted "secret" is
 * returned.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_TEST_handler_test_transfer (struct TMH_RequestHandler *rh,
				struct MHD_Connection *connection,
				void **connection_cls,
				const char *upload_data,
				size_t *upload_data_size);


/**
 * Handle a "/test" request.  Parses the JSON in the post.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_TEST_handler_test (struct TMH_RequestHandler *rh,
		       struct MHD_Connection *connection,
		       void **connection_cls,
		       const char *upload_data,
		       size_t *upload_data_size);

#endif
