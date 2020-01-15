/*
  This file is part of TALER
  (C) 2020 Taler Systems SA

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
 * @file util/test_payto.c
 * @brief Tests for payto helpers
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"

#define CHECK(a,b) do { \
    if (0 != strcmp (a,b)) {   \
      GNUNET_break (0); \
      fprintf (stderr, "Got %s, wanted %s\n", b, a); \
      GNUNET_free (b); \
      return 1; \
    } else { \
      GNUNET_free (b); \
    }  \
} while (0)


int
main (int argc,
      const char *const argv[])
{
  char *r;

  GNUNET_log_setup ("test-payto",
                    "WARNING",
                    NULL);
  r = TALER_payto_xtalerbank_make ("https://localhost/",
                                   "account");
  CHECK ("payto://x-taler-bank/localhost/account",
         r);
  r = TALER_payto_xtalerbank_make ("https://localhost",
                                   "account");
  CHECK ("payto://x-taler-bank/localhost/account",
         r);
  r = TALER_payto_xtalerbank_make ("http://localhost:80/",
                                   "account");
  CHECK ("payto://x-taler-bank/localhost:80/account",
         r);
  r = TALER_payto_xtalerbank_make ("http://localhost:80",
                                   "account");
  CHECK ("payto://x-taler-bank/localhost:80/account",
         r);
  r = TALER_payto_xtalerbank_make ("http://localhost/",
                                   "account");
  CHECK ("payto://x-taler-bank/localhost:80/account",
         r);
  r = TALER_xtalerbank_base_url_from_payto (
    "payto://x-taler-bank/localhost/bob");
  CHECK ("https://localhost/",
         r);
  r = TALER_xtalerbank_base_url_from_payto (
    "payto://x-taler-bank/localhost:1080/bob");
  CHECK ("http://localhost:1080/",
         r);
  r = TALER_xtalerbank_account_url_from_payto (
    "payto://x-taler-bank/localhost/bob");
  CHECK ("https://localhost/bob",
         r);
  r = TALER_xtalerbank_account_url_from_payto (
    "payto://x-taler-bank/localhost:1080/alice");
  CHECK ("http://localhost:1080/alice",
         r);
  r = TALER_xtalerbank_account_from_payto (
    "payto://x-taler-bank/localhost:1080/alice");
  CHECK ("alice",
         r);
  r = TALER_xtalerbank_account_from_payto (
    "payto://x-taler-bank/localhost:1080/alice?subject=hello&amount=EUR:1");
  CHECK ("alice",
         r);
  return 0;
}


/* end of test_payto.c */
