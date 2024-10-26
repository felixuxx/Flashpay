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
          GNUNET_assert (a != NULL); \
          GNUNET_assert (b != NULL); \
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

  (void) argc;
  (void) argv;
  GNUNET_log_setup ("test-payto",
                    "WARNING",
                    NULL);
  GNUNET_assert (GNUNET_TIME_absolute_is_never (
                   GNUNET_TIME_UNIT_FOREVER_TS.abs_time));
  GNUNET_assert (NULL ==
                 TALER_iban_validate ("FR1420041010050500013M02606"));
  GNUNET_assert (NULL ==
                 TALER_iban_validate ("DE89370400440532013000"));
  r = TALER_payto_validate (
    "payto://x-taler-bank/hostname/username?receiver-name=foo");
  GNUNET_assert (NULL == r);
  r = TALER_payto_validate (
    "payto://x-taler-bank/hostname/~path/username?receiver-name=foo");
  GNUNET_assert (NULL == r);
  r = TALER_payto_validate (
    "payto://x-taler-bank/hostname/~path/username?receiver-name=fo/o");
  GNUNET_assert (NULL == r);
  r = TALER_payto_validate (
    "payto://x-taler-bank/host_name/~path/username?receiver-name=fo_o");
  GNUNET_assert (NULL == r);
  r = TALER_payto_validate (
    "payto://x-taler-bank/hostname/path/username?receiver-name=foo");
  GNUNET_assert (NULL == r);
  r = TALER_payto_validate (
    "payto://x-taler-bank/https://hostname/username?receiver-name=foo");
  GNUNET_assert (NULL != r);
  GNUNET_free (r);
  r = TALER_payto_validate (
    "payto://x-taler-bank/hostname:4a2/path/username?receiver-name=foo");
  GNUNET_assert (NULL != r);
  GNUNET_free (r);
  r = TALER_payto_validate (
    "payto://x-taler-bank/-hostname/username?receiver-name=foo");
  GNUNET_assert (NULL != r);
  GNUNET_free (r);
  r = TALER_payto_validate (
    "payto://x-taler-bank/domain..name/username?receiver-name=foo");
  GNUNET_assert (NULL != r);
  GNUNET_free (r);
  r = TALER_payto_validate (
    "payto://x-taler-bank/domain..name/?receiver-name=foo");
  GNUNET_assert (NULL != r);
  GNUNET_free (r);
  r = TALER_payto_validate (
    "payto://x-taler-bank/domain.name/username");
  GNUNET_assert (NULL != r);
  GNUNET_free (r);
  r = TALER_xtalerbank_account_from_payto (
    "payto://x-taler-bank/localhost:1080/alice");
  CHECK ("alice",
         r);
  r = TALER_xtalerbank_account_from_payto (
    "payto://x-taler-bank/localhost:1080/path/alice");
  CHECK ("alice",
         r);
  r = TALER_xtalerbank_account_from_payto (
    "payto://x-taler-bank/localhost:1080/path/alice?receiver-name=ali/cia");
  CHECK ("alice",
         r);
  r = TALER_xtalerbank_account_from_payto (
    "payto://x-taler-bank/localhost:1080/alice?subject=hello&amount=EUR:1");
  CHECK ("alice",
         r);

  r = TALER_payto_get_subject (
    "payto://x-taler-bank/localhost:1080/alice?subject=hello&amount=EUR:1");
  CHECK ("hello",
         r);

  r = TALER_payto_get_subject (
    "payto://x-taler-bank/localhost:1080/alice");
  GNUNET_assert (r == NULL);
  return 0;
}


/* end of test_payto.c */
