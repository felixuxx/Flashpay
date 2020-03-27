/*
  This file is part of TALER
  Copyright (C) 2017 Taler Systems SA

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
 * @file exchangedb/test_exchangedb_fees.c
 * @brief test cases for functions in exchangedb/exchangedb_fees.c
 * @author Christian Grothoff
 */
#include "platform.h"
#include "gnunet/gnunet_util_lib.h"
#include "taler_signatures.h"
#include "taler_exchangedb_lib.h"


/**
 * Sign @a af with @a priv
 *
 * @param[in|out] af fee structure to sign
 * @param priv private key to use for signing
 */
static void
sign_af (struct TALER_EXCHANGEDB_AggregateFees *af,
         const struct GNUNET_CRYPTO_EddsaPrivateKey *priv)
{
  struct TALER_MasterWireFeePS wf;

  TALER_EXCHANGEDB_fees_2_wf ("test",
                              af,
                              &wf);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (priv,
                                           &wf.purpose,
                                           &af->master_sig.eddsa_signature));
}


int
main (int argc,
      const char *const argv[])
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  struct TALER_EXCHANGEDB_AggregateFees *af;
  struct TALER_EXCHANGEDB_AggregateFees *n;
  struct TALER_MasterPublicKeyP master_pub;
  struct GNUNET_CRYPTO_EddsaPrivateKey *priv;
  char *tmpdir;
  char *tmpfile = NULL;
  int ret;
  unsigned int year;

  (void) argc;
  (void) argv;
  GNUNET_log_setup ("test-exchangedb-fees",
                    "WARNING",
                    NULL);
  tmpdir = GNUNET_DISK_mkdtemp ("test_exchangedb_fees");
  if (NULL == tmpdir)
    return 77; /* skip test */
  priv = GNUNET_CRYPTO_eddsa_key_create ();
  GNUNET_CRYPTO_eddsa_key_get_public (priv,
                                      &master_pub.eddsa_pub);
  cfg = GNUNET_CONFIGURATION_create ();
  GNUNET_CONFIGURATION_set_value_string (cfg,
                                         "exchangedb",
                                         "WIREFEE_BASE_DIR",
                                         tmpdir);
  GNUNET_asprintf (&tmpfile,
                   "%s/%s.fee",
                   tmpdir,
                   "test");
  ret = 0;
  af = GNUNET_new (struct TALER_EXCHANGEDB_AggregateFees);
  year = GNUNET_TIME_get_current_year ();
  af->start_date = GNUNET_TIME_year_to_time (year);
  af->end_date = GNUNET_TIME_year_to_time (year + 1);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:1.0",
                                         &af->wire_fee));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:1.0",
                                         &af->closing_fee));
  sign_af (af,
           priv);
  n = GNUNET_new (struct TALER_EXCHANGEDB_AggregateFees);
  n->start_date = GNUNET_TIME_year_to_time (year + 1);
  n->end_date = GNUNET_TIME_year_to_time (year + 2);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:0.1",
                                         &n->wire_fee));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:0.1",
                                         &n->closing_fee));
  sign_af (n,
           priv);
  af->next = n;

  if (GNUNET_OK !=
      TALER_EXCHANGEDB_fees_write (tmpfile,
                                   "test",
                                   af))
  {
    GNUNET_break (0);
    ret = 1;
  }
  TALER_EXCHANGEDB_fees_free (af);
  GNUNET_free (tmpfile);
  af = TALER_EXCHANGEDB_fees_read (cfg,
                                   "test");
  if (NULL == af)
  {
    GNUNET_break (0);
    ret = 1;
  }
  else
  {
    for (struct TALER_EXCHANGEDB_AggregateFees *p = af;
         NULL != p;
         p = p->next)
    {
      struct TALER_MasterWireFeePS wf;

      TALER_EXCHANGEDB_fees_2_wf ("test",
                                  p,
                                  &wf);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_WIRE_FEES,
                                      &wf.purpose,
                                      &p->master_sig.eddsa_signature,
                                      &master_pub.eddsa_pub))
      {
        GNUNET_break (0);
        ret = 1;
      }
    }
    TALER_EXCHANGEDB_fees_free (af);
  }

  (void) GNUNET_DISK_directory_remove (tmpdir);
  GNUNET_free (tmpdir);
  GNUNET_free (priv);
  GNUNET_CONFIGURATION_destroy (cfg);
  return ret;
}
