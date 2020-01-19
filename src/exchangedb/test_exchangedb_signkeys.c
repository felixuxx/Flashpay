/*
  This file is part of TALER
  Copyright (C) 2016 Taler Systems SA

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
 * @file exchangedb/test_exchangedb_signkeys.c
 * @brief test cases for some functions in exchangedb/exchangedb_signkeys.c
 * @author Christian Grothoff
 */
#include "platform.h"
#include "gnunet/gnunet_util_lib.h"
#include "taler_signatures.h"
#include "taler_exchangedb_lib.h"


#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)


/**
 * @brief Iterator over signing keys.
 *
 * @param cls closure
 * @param filename name of the file the key came from
 * @param ski the sign key
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
ski_iter (void *cls,
          const char *filename,
          const struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP *ski)
{
  const struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP *exp = cls;

  if (0 != GNUNET_memcmp (ski,
                          exp))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


int
main (int argc,
      const char *const argv[])
{
  struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP ski;
  struct GNUNET_TIME_Absolute now;
  char *tmpfile;
  int ret;

  ret = 1;
  tmpfile = NULL;
  GNUNET_log_setup ("test-exchangedb-signkeys",
                    "WARNING",
                    NULL);
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &ski,
                              sizeof (struct
                                      TALER_EXCHANGEDB_PrivateSigningKeyInformationP));
  now = GNUNET_TIME_absolute_get ();
  EXITIF (NULL == (tmpfile = GNUNET_DISK_mkdtemp ("test_exchangedb_ski")));
  EXITIF (GNUNET_OK !=
          TALER_EXCHANGEDB_signing_key_write (tmpfile,
                                              now,
                                              &ski));
  EXITIF (1 !=
          TALER_EXCHANGEDB_signing_keys_iterate (tmpfile,
                                                 &ski_iter,
                                                 &ski));
  ret = 0;
EXITIF_exit:
  if (NULL != tmpfile)
  {
    (void) GNUNET_DISK_directory_remove (tmpfile);
    GNUNET_free (tmpfile);
  }
  return ret;
}
