/*
  This file is part of TALER
  (C) 2015, 2016 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file json/test_json_wire.c
 * @brief Tests for Taler-specific crypto logic
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_json_lib.h"


int
main (int argc,
      const char *const argv[])
{
  struct TALER_MasterPublicKeyP master_pub;
  struct GNUNET_CRYPTO_EddsaPrivateKey *priv;
  struct TALER_MasterPrivateKeyP master_priv;
  json_t *wire;
  const char *payto = "payto://x-taler-bank/42";
  char *p;

  GNUNET_log_setup ("test-json-wire",
                    "WARNING",
                    NULL);
  priv = GNUNET_CRYPTO_eddsa_key_create ();
  master_priv.eddsa_priv = *priv;
  GNUNET_free (priv);
  GNUNET_CRYPTO_eddsa_key_get_public (&master_priv.eddsa_priv,
                                      &master_pub.eddsa_pub);
  wire = TALER_JSON_exchange_wire_signature_make (payto,
                                                  &master_priv);
  p = TALER_JSON_wire_to_payto (wire);
  GNUNET_assert (0 == strcmp (p, payto));
  GNUNET_free (p);
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_exchange_wire_signature_check (wire,
                                                           &master_pub));
  json_decref (wire);

  return 0;
}


/* end of test_json_wire.c */
