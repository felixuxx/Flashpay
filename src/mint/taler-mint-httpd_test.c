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
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-mint-httpd_test.c
 * @brief Handle /test requests; parses the POST and JSON and
 *        checks that the client is binary-compatible
 * @author Christian Grothoff
 *
 * TODO:
 * - ECDHE operations
 * - HKDF operations
 * - Symmetric encryption/decryption
 * - high-level transfer key logic
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_signatures.h"
#include "taler_util.h"
#include "taler-mint-httpd_test.h"
#include "taler-mint-httpd_parsing.h"
#include "taler-mint-httpd_responses.h"


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
  struct GNUNET_HashCode hc;
  struct TMH_PARSE_FieldSpecification spec[] = {
    TMH_PARSE_MEMBER_VARIABLE ("input"),
    TMH_PARSE_MEMBER_END
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
  GNUNET_CRYPTO_hash (spec[0].destination,
		      spec[0].destination_size_out,
		      &hc);
  TMH_PARSE_release_data (spec);
  json_decref (json);
  json = TALER_json_from_data (&hc, sizeof (struct GNUNET_HashCode));
  res = TMH_RESPONSE_reply_json (connection,
				 json,
				 MHD_HTTP_OK);
  json_decref (json);
  return res;
}


/**
 * Handle a "/test/ecdsa" request.  Parses the JSON in the post, 
 * which must contain a "ecdsa_pub" with a public key and an
 *"ecdsa_sig" with the corresponding signature for a purpose
 * of #TALER_SIGNATURE_CLIENT_TEST_ECDSA.  If the signature is
 * valid, a reply with a #TALER_SIGNATURE_MINT_TEST_ECDSA is 
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
TMH_TEST_handler_test_ecdsa (struct TMH_RequestHandler *rh,
			     struct MHD_Connection *connection,
			     void **connection_cls,
			     const char *upload_data,
			     size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct GNUNET_CRYPTO_EcdsaPublicKey pub;
  struct GNUNET_CRYPTO_EcdsaSignature sig;
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct TMH_PARSE_FieldSpecification spec[] = {
    TMH_PARSE_MEMBER_FIXED ("ecdsa_pub", &pub),
    TMH_PARSE_MEMBER_FIXED ("ecdsa_sig", &sig),
    TMH_PARSE_MEMBER_END
  };
  struct GNUNET_CRYPTO_EcdsaPrivateKey *pk;

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
  purpose.purpose = htonl (TALER_SIGNATURE_CLIENT_TEST_ECDSA);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecdsa_verify (TALER_SIGNATURE_CLIENT_TEST_ECDSA,
				  &purpose,
				  &sig,
				  &pub))
  {
    TMH_PARSE_release_data (spec);
    return TMH_RESPONSE_reply_signature_invalid (connection,
						 "ecdsa_sig");
  }
  TMH_PARSE_release_data (spec);
  pk = GNUNET_CRYPTO_ecdsa_key_create ();
  purpose.purpose = htonl (TALER_SIGNATURE_MINT_TEST_ECDSA);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecdsa_sign (pk,
				&purpose,
				&sig))
  {
    GNUNET_free (pk);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to ECDSA-sign");
  }
  GNUNET_CRYPTO_ecdsa_key_get_public (pk,
				      &pub);
  GNUNET_free (pk);
  return TMH_RESPONSE_reply_json_pack (connection,
				       MHD_HTTP_OK,
				       "{s:o, s:o}",
				       "ecdsa_pub",
				       TALER_json_from_data (&pub,
							     sizeof (pub)),
				       "ecdsa_sig",
				       TALER_json_from_data (&sig,
							     sizeof (sig)));
}


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
			     size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct GNUNET_CRYPTO_EddsaPublicKey pub;
  struct GNUNET_CRYPTO_EddsaSignature sig;
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct TMH_PARSE_FieldSpecification spec[] = {
    TMH_PARSE_MEMBER_FIXED ("eddsa_pub", &pub),
    TMH_PARSE_MEMBER_FIXED ("eddsa_sig", &sig),
    TMH_PARSE_MEMBER_END
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
    TMH_PARSE_release_data (spec);
    return TMH_RESPONSE_reply_signature_invalid (connection,
						 "eddsa_sig");
  }
  TMH_PARSE_release_data (spec);
  pk = GNUNET_CRYPTO_eddsa_key_create ();
  purpose.purpose = htonl (TALER_SIGNATURE_MINT_TEST_EDDSA);
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
				       TALER_json_from_data (&pub,
							     sizeof (pub)),
				       "eddsa_sig",
				       TALER_json_from_data (&sig,
							     sizeof (sig)));
}


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
			   size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct GNUNET_CRYPTO_rsa_PublicKey *pub;
  struct GNUNET_CRYPTO_rsa_Signature *sig;
  struct TMH_PARSE_FieldSpecification spec[] = {
    TMH_PARSE_MEMBER_VARIABLE ("blind_ev"),
    TMH_PARSE_MEMBER_END
  };
  struct GNUNET_CRYPTO_rsa_PrivateKey *pk;

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
  pk = GNUNET_CRYPTO_rsa_private_key_create (1024);
  if (NULL == pk)
  {
    GNUNET_break (0);
    TMH_PARSE_release_data (spec);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to create RSA key");
  }
  sig = GNUNET_CRYPTO_rsa_sign (pk,
				spec[0].destination,
				spec[0].destination_size_out);
  if (NULL == sig)
  {
    GNUNET_break (0);
    GNUNET_CRYPTO_rsa_private_key_free (pk);
    TMH_PARSE_release_data (spec);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to RSA-sign");
  }
  TMH_PARSE_release_data (spec);
  pub = GNUNET_CRYPTO_rsa_private_key_get_public (pk);
  GNUNET_CRYPTO_rsa_private_key_free (pk);
  if (NULL == pub)
  {
    GNUNET_break (0);
    GNUNET_CRYPTO_rsa_signature_free (sig);
    return TMH_RESPONSE_reply_internal_error (connection,
					      "Failed to get public RSA key");
  }
  res = TMH_RESPONSE_reply_json_pack (connection,
				      MHD_HTTP_OK,
				      "{s:o, s:o}",
				      "rsa_pub",
				      TALER_json_from_rsa_public_key (pub),
				      "rsa_blind_sig",
				      TALER_json_from_rsa_signature (sig));
  GNUNET_CRYPTO_rsa_signature_free (sig);
  GNUNET_CRYPTO_rsa_public_key_free (pub);
  return res;
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
  return res;
}


/* end of taler-mint-httpd_test.c */
