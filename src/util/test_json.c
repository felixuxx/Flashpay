/*
  This file is part of TALER
  (C) 2015 GNUnet e.V.

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
 * @file util/test_json.c
 * @brief Tests for Taler-specific crypto logic
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_json_lib.h"


/**
 * Test amount conversion from/to JSON.
 *
 * @return 0 on success
 */
static int
test_amount ()
{
  json_t *j;
  struct TALER_Amount a1;
  struct TALER_Amount a2;

  GNUNET_assert (GNUNET_OK ==
		 TALER_string_to_amount ("EUR:4.3",
					 &a1));
  j = TALER_json_from_amount (&a1);
  GNUNET_assert (NULL != j);
  GNUNET_assert (GNUNET_OK ==
		 TALER_json_to_amount (j,
				       &a2));
  GNUNET_assert (0 ==
		 TALER_amount_cmp (&a1,
				   &a2));
  json_decref (j);
  return 0;
}


/**
 * Test time conversion from/to JSON.
 *
 * @return 0 on success
 */
static int
test_time ()
{
  json_t *j;
  struct GNUNET_TIME_Absolute a1;
  struct GNUNET_TIME_Absolute a2;

  a1 = GNUNET_TIME_absolute_get ();
  TALER_round_abs_time (&a1);
  j = TALER_json_from_abs (a1);
  GNUNET_assert (NULL != j);
  GNUNET_assert (GNUNET_OK ==
		 TALER_json_to_abs (j,
				    &a2));
  GNUNET_assert (a1.abs_value_us ==
		 a2.abs_value_us);
  json_decref (j);

  a1 = GNUNET_TIME_UNIT_FOREVER_ABS;
  j = TALER_json_from_abs (a1);
  GNUNET_assert (NULL != j);
  GNUNET_assert (GNUNET_OK ==
		 TALER_json_to_abs (j,
				    &a2));
  GNUNET_assert (a1.abs_value_us ==
		 a2.abs_value_us);
  json_decref (j);
  return 0;
}


/**
 * Test raw (binary) conversion from/to JSON.
 *
 * @return 0 on success
 */
static int
test_raw ()
{
  char blob[256];
  char blob2[256];
  unsigned int i;
  json_t *j;

  for (i=0;i<=256;i++)
  {
    memset (blob, i, i);
    j = TALER_json_from_data (blob, i);
    GNUNET_assert (NULL != j);
    GNUNET_assert (GNUNET_OK ==
		   TALER_json_to_data (j,
				       blob2,
				       i));
    GNUNET_assert (0 ==
		   memcmp (blob,
			   blob2,
			   i));
  }
  return 0;
}


/**
 * Test rsa conversions from/to JSON.
 *
 * @return 0 on success
 */
static int
test_rsa ()
{
  struct GNUNET_CRYPTO_rsa_PublicKey *pub;
  struct GNUNET_CRYPTO_rsa_PublicKey *pub2;
  struct GNUNET_CRYPTO_rsa_Signature *sig;
  struct GNUNET_CRYPTO_rsa_Signature *sig2;
  struct GNUNET_CRYPTO_rsa_PrivateKey *priv;
  char msg[] = "Hello";
  json_t *jp;
  json_t *js;

  priv = GNUNET_CRYPTO_rsa_private_key_create (1024);
  pub = GNUNET_CRYPTO_rsa_private_key_get_public (priv);
  sig = GNUNET_CRYPTO_rsa_sign (priv,
				msg,
				sizeof (msg));
  GNUNET_assert (NULL != (jp = TALER_json_from_rsa_public_key (pub)));
  GNUNET_assert (NULL != (js = TALER_json_from_rsa_signature (sig)));
  GNUNET_assert (NULL != (pub2 = TALER_json_to_rsa_public_key (jp)));
  GNUNET_assert (NULL != (sig2 = TALER_json_to_rsa_signature (js)));
  GNUNET_break (0 ==
		GNUNET_CRYPTO_rsa_signature_cmp (sig,
						 sig2));
  GNUNET_break (0 ==
		GNUNET_CRYPTO_rsa_public_key_cmp (pub,
						  pub2));
  GNUNET_CRYPTO_rsa_signature_free (sig);
  GNUNET_CRYPTO_rsa_signature_free (sig2);
  GNUNET_CRYPTO_rsa_private_key_free (priv);
  GNUNET_CRYPTO_rsa_public_key_free (pub);
  GNUNET_CRYPTO_rsa_public_key_free (pub2);
  return 0;
}


int
main(int argc,
     const char *const argv[])
{
  GNUNET_log_setup ("test-json",
		    "WARNING",
		    NULL);
  if (0 != test_amount ())
    return 1;
  if (0 != test_time ())
    return 1;
  if (0 != test_raw ())
    return 1;
  if (0 != test_rsa ())
    return 1;
  /* FIXME: test EdDSA signature conversion... */
  return 0;
}

/* end of test_json.c */
