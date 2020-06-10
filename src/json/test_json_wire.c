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
  struct TALER_MasterPrivateKeyP master_priv;
  json_t *wire_xtalerbank;
  json_t *wire_iban;
  const char *payto_xtalerbank = "payto://x-taler-bank/42";
  const char *payto_iban = "payto://iban/BIC-TO-BE-SKIPPED/DE89370400440532013000";
  char *p_xtalerbank;
  char *p_iban;

  (void) argc;
  (void) argv;
  GNUNET_log_setup ("test-json-wire",
                    "WARNING",
                    NULL);
  GNUNET_CRYPTO_eddsa_key_create (&master_priv.eddsa_priv);
  GNUNET_CRYPTO_eddsa_key_get_public (&master_priv.eddsa_priv,
                                      &master_pub.eddsa_pub);
  wire_xtalerbank = TALER_JSON_exchange_wire_signature_make (payto_xtalerbank,
                                                             &master_priv);
  wire_iban = TALER_JSON_exchange_wire_signature_make (payto_iban,
                                                       &master_priv);
  if (NULL == wire_iban)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not parse payto/IBAN (%s) into 'wire object'\n",
                payto_iban);
    return 1;
  }
  p_xtalerbank = TALER_JSON_wire_to_payto (wire_xtalerbank);
  p_iban = TALER_JSON_wire_to_payto (wire_iban);
  GNUNET_assert (0 == strcmp (p_xtalerbank, payto_xtalerbank));
  GNUNET_assert (0 == strcmp (p_iban, payto_iban));
  GNUNET_free (p_xtalerbank);
  GNUNET_free (p_iban);

  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_exchange_wire_signature_check (wire_xtalerbank,
                                                           &master_pub));
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_exchange_wire_signature_check (wire_iban,
                                                           &master_pub));
  json_decref (wire_xtalerbank);
  json_decref (wire_iban);

  return 0;
}


/* end of test_json_wire.c */
