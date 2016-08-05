/*
  This file is part of TALER
  Copyright (C) 2015 GNUnet e.V.

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
 * @file taler-exchange-httpd_test.c
 * @brief Handle /test requests; parses the POST and JSON and
 *        checks that the client is binary-compatible
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_signatures.h"
#include "taler-exchange-httpd_test.h"
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Private key the test module uses for signing.
 */
static struct GNUNET_CRYPTO_RsaPrivateKey *rsa_pk;


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
			      size_t *upload_data_size)
{
  json_t *json;
  int res;
  void *in_ptr;
  size_t in_ptr_size;
  struct GNUNET_HashCode hc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_varsize ("input", &in_ptr, &in_ptr_size),
    GNUNET_JSON_spec_end ()
  };

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  res = TMH_PARSE_json_data (connection,
			     json,
			     spec);
  if (GNUNET_YES != res)
    return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
  GNUNET_CRYPTO_hash (in_ptr,
		      in_ptr_size,
		      &hc);
  GNUNET_JSON_parse_free (spec);
  json_decref (json);
  return TMH_RESPONSE_reply_json_pack (connection,
				       MHD_HTTP_OK,
				       "{s:o}",
				       "output",
				       GNUNET_JSON_from_data_auto (&hc));
}


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
			       size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct GNUNET_HashCode key;
  struct GNUNET_CRYPTO_SymmetricInitializationVector iv;
  struct GNUNET_CRYPTO_SymmetricSessionKey skey;
  void *in_ptr;
  size_t in_ptr_size;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_varsize ("input", &in_ptr, &in_ptr_size),
    GNUNET_JSON_spec_fixed_auto ("key_hash", &key),
    GNUNET_JSON_spec_end ()
  };
  char *out;

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  res = TMH_PARSE_json_data (connection,
			     json,
			     spec);
  json_decref (json);
  if (GNUNET_YES != res)
    return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
  GNUNET_assert (GNUNET_YES ==
		 GNUNET_CRYPTO_kdf (&skey, sizeof (struct GNUNET_CRYPTO_SymmetricSessionKey),
				    "skey", strlen ("skey"),
				    &key, sizeof (key),
				    NULL, 0));
  GNUNET_assert (GNUNET_YES ==
		 GNUNET_CRYPTO_kdf (&iv, sizeof (struct GNUNET_CRYPTO_SymmetricInitializationVector),
				    "iv", strlen ("iv"),
				    &key, sizeof (key),
				    NULL, 0));
  out = GNUNET_malloc (in_ptr_size);
  GNUNET_break (in_ptr_size ==
		GNUNET_CRYPTO_symmetric_encrypt (in_ptr,
						 in_ptr_size,
						 &skey,
						 &iv,
						 out));
  json = GNUNET_JSON_from_data (out,
                                in_ptr_size);
  GNUNET_free (out);
  GNUNET_JSON_parse_free (spec);
  return TMH_RESPONSE_reply_json_pack (connection,
				       MHD_HTTP_OK,
				       "{s:o}",
				       "output",
				       json);
}


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
			    size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct GNUNET_HashCode hc;
  void *in_ptr;
  size_t in_ptr_size;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_varsize ("input", &in_ptr, &in_ptr_size),
    GNUNET_JSON_spec_end ()
  };

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  res = TMH_PARSE_json_data (connection,
			     json,
			     spec);
  json_decref (json);
  if (GNUNET_YES != res)
    return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
  GNUNET_CRYPTO_kdf (&hc, sizeof (hc),
		     "salty", strlen ("salty"),
		     in_ptr,
		     in_ptr_size,
		     NULL, 0);
  GNUNET_JSON_parse_free (spec);
  json = GNUNET_JSON_from_data_auto (&hc);
  return TMH_RESPONSE_reply_json_pack (connection,
				       MHD_HTTP_OK,
				       "{s:o}",
				       "output",
				       json);
}


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
			     size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct GNUNET_CRYPTO_EcdhePublicKey pub;
  struct GNUNET_CRYPTO_EcdhePrivateKey priv;
  struct GNUNET_HashCode hc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("ecdhe_pub", &pub),
    GNUNET_JSON_spec_fixed_auto ("ecdhe_priv", &priv),
    GNUNET_JSON_spec_end ()
  };

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  res = TMH_PARSE_json_data (connection,
			     json,
			     spec);
  json_decref (json);
  if (GNUNET_YES != res)
    return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecc_ecdh (&priv,
			      &pub,
			      &hc))
  {
    GNUNET_JSON_parse_free (spec);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to perform ECDH");
  }
  GNUNET_JSON_parse_free (spec);
  return TMH_RESPONSE_reply_json_pack (connection,
				       MHD_HTTP_OK,
				       "{s:o}",
				       "ecdh_hash",
				       GNUNET_JSON_from_data_auto (&hc));
}


/**
 * Handle a "/test/eddsa" request.  Parses the JSON in the post,
 * which must contain a "eddsa_pub" with a public key and an
 *"eddsa_sig" with the corresponding signature for a purpose
 * of #TALER_SIGNATURE_CLIENT_TEST_EDDSA.  If the signature is
 * valid, a reply with a #TALER_SIGNATURE_EXCHANGE_TEST_EDDSA is
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
			     size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct GNUNET_CRYPTO_EddsaPublicKey pub;
  struct GNUNET_CRYPTO_EddsaSignature sig;
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("eddsa_pub", &pub),
    GNUNET_JSON_spec_fixed_auto ("eddsa_sig", &sig),
    GNUNET_JSON_spec_end ()
  };
  struct GNUNET_CRYPTO_EddsaPrivateKey *pk;

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  res = TMH_PARSE_json_data (connection,
			     json,
			     spec);
  json_decref (json);
  if (GNUNET_YES != res)
    return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
  purpose.size = htonl (sizeof (struct GNUNET_CRYPTO_EccSignaturePurpose));
  purpose.purpose = htonl (TALER_SIGNATURE_CLIENT_TEST_EDDSA);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_CLIENT_TEST_EDDSA,
				  &purpose,
				  &sig,
				  &pub))
  {
    GNUNET_JSON_parse_free (spec);
    return TMH_RESPONSE_reply_signature_invalid (connection,
						 "eddsa_sig");
  }
  GNUNET_JSON_parse_free (spec);
  pk = GNUNET_CRYPTO_eddsa_key_create ();
  purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_TEST_EDDSA);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_sign (pk,
				&purpose,
				&sig))
  {
    GNUNET_free (pk);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to EdDSA-sign");
  }
  GNUNET_CRYPTO_eddsa_key_get_public (pk,
				      &pub);
  GNUNET_free (pk);
  return TMH_RESPONSE_reply_json_pack (connection,
				       MHD_HTTP_OK,
				       "{s:o, s:o}",
				       "eddsa_pub",
				       GNUNET_JSON_from_data_auto (&pub),
				       "eddsa_sig",
				       GNUNET_JSON_from_data_auto (&sig));
}


/**
 * Handle a "/test/rsa/get" request.  Returns the RSA public key
 * ("rsa_pub") which is used for signing in "/test/rsa/sign".
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_TEST_handler_test_rsa_get (struct TMH_RequestHandler *rh,
                               struct MHD_Connection *connection,
                               void **connection_cls,
                               const char *upload_data,
                               size_t *upload_data_size)
{
  int res;
  struct GNUNET_CRYPTO_RsaPublicKey *pub;

  if (NULL == rsa_pk)
    rsa_pk = GNUNET_CRYPTO_rsa_private_key_create (1024);
  if (NULL == rsa_pk)
  {
    GNUNET_break (0);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to create RSA key");
  }
  pub = GNUNET_CRYPTO_rsa_private_key_get_public (rsa_pk);
  if (NULL == pub)
  {
    GNUNET_break (0);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to get public RSA key");
  }
  res = TMH_RESPONSE_reply_json_pack (connection,
				      MHD_HTTP_OK,
				      "{s:o}",
				      "rsa_pub",
				      GNUNET_JSON_from_rsa_public_key (pub));
  GNUNET_CRYPTO_rsa_public_key_free (pub);
  return res;
}


/**
 * Handle a "/test/rsa/sign" request.  Parses the JSON in the post, which
 * must contain an "blind_ev" blinded value.  A a blinded signature
 * ("rsa_blind_sig") is returned.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_TEST_handler_test_rsa_sign (struct TMH_RequestHandler *rh,
                                struct MHD_Connection *connection,
                                void **connection_cls,
                                const char *upload_data,
                                size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct GNUNET_CRYPTO_RsaSignature *sig;
  void *in_ptr;
  size_t in_ptr_size;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_varsize ("blind_ev", &in_ptr, &in_ptr_size),
    GNUNET_JSON_spec_end ()
  };

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  res = TMH_PARSE_json_data (connection,
			     json,
			     spec);
  json_decref (json);
  if (GNUNET_YES != res)
    return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
  if (NULL == rsa_pk)
    rsa_pk = GNUNET_CRYPTO_rsa_private_key_create (1024);
  if (NULL == rsa_pk)
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to create RSA key");
  }
  sig = GNUNET_CRYPTO_rsa_sign_blinded (rsa_pk,
					in_ptr,
					in_ptr_size);
  if (NULL == sig)
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to RSA-sign");
  }
  GNUNET_JSON_parse_free (spec);
  res = TMH_RESPONSE_reply_json_pack (connection,
				      MHD_HTTP_OK,
				      "{s:o}",
				      "rsa_blind_sig",
				      GNUNET_JSON_from_rsa_signature (sig));
  GNUNET_CRYPTO_rsa_signature_free (sig);
  return res;
}


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
				size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct TALER_TransferPrivateKeyP trans_priv;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("trans_priv", &trans_priv),
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &coin_pub),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_TransferSecretP secret;

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  res = TMH_PARSE_json_data (connection,
			     json,
			     spec);
  json_decref (json);
  if (GNUNET_YES != res)
    return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
  TALER_link_reveal_transfer_secret (&trans_priv,
                                     &coin_pub,
                                     &secret);
  return TMH_RESPONSE_reply_json_pack (connection,
				       MHD_HTTP_OK,
				       "{s:o}",
				       "secret",
				       GNUNET_JSON_from_data_auto (&secret));
}


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
		       size_t *upload_data_size)
{
  json_t *json;
  int res;

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;

  json_decref (json);
  return MHD_NO;
}


/* end of taler-exchange-httpd_test.c */
