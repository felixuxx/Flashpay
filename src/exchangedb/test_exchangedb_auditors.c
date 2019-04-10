/*
  This file is part of TALER
  Copyright (C) 2016 Inria & GNUnet e. V.

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
 * @file exchangedb/test_exchangedb_auditors.c
 * @brief test cases for some functions in exchangedb/exchangedb_auditorkeys.c
 * @author Christian Grothoff
 */
#include "platform.h"
#include "gnunet/gnunet_util_lib.h"
#include "taler_signatures.h"
#include "taler_exchangedb_lib.h"


#define RSA_KEY_SIZE 1024


#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)


static struct TALER_AuditorPublicKeyP want_apub;

static struct TALER_AuditorSignatureP want_asigs;

static struct TALER_MasterPublicKeyP want_mpub;

static struct TALER_DenominationKeyValidityPS want_dki;



/**
 * @brief Function called with auditor information.
 *
 * @param cls NULL
 * @param apub the auditor's public key
 * @param auditor_url URL of the auditor
 * @param mpub the exchange's public key (as expected by the auditor)
 * @param dki_len length of @a asig and @a dki arrays
 * @param asigs array of the auditor's signatures over the @a dks, of length @a dki_len
 * @param dki array of denomination coin data signed by the auditor, of length @a dki_len
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
auditor_cb (void *cls,
            const struct TALER_AuditorPublicKeyP *apub,
            const char *auditor_url,
            const struct TALER_MasterPublicKeyP *mpub,
            unsigned int dki_len,
            const struct TALER_AuditorSignatureP *asigs,
            const struct TALER_DenominationKeyValidityPS *dki)
{
  GNUNET_assert (NULL == cls);
  if (0 != strcmp (auditor_url,
                   "http://auditor/"))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (1 != dki_len)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 != GNUNET_memcmp (&want_apub,
                          apub))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 != GNUNET_memcmp (&want_mpub,
                          mpub))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 != GNUNET_memcmp (&want_asigs,
                          asigs))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 != GNUNET_memcmp (&want_dki,
                          dki))
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
  char *tmpfile = NULL;
  char *tmpdir;
  struct GNUNET_CONFIGURATION_Handle *cfg = NULL;
  int ret;

  ret = 1;
  GNUNET_log_setup ("test-exchangedb-auditors",
                    "WARNING",
                    NULL);
  EXITIF (NULL == (tmpdir = GNUNET_DISK_mkdtemp ("test_exchangedb_auditors")));
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &want_apub,
                              sizeof (want_apub));
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &want_asigs,
                              sizeof (want_asigs));
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &want_mpub,
                              sizeof (want_mpub));
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &want_dki,
                              sizeof (struct TALER_DenominationKeyValidityPS));
  EXITIF (NULL == (tmpdir = GNUNET_DISK_mkdtemp ("test_exchangedb_auditors")));
  GNUNET_asprintf (&tmpfile,
                   "%s/%s",
                   tmpdir,
                   "testauditor");
  EXITIF (GNUNET_OK !=
          TALER_EXCHANGEDB_auditor_write (tmpfile,
                                          &want_apub,
                                          "http://auditor/",
                                          &want_asigs,
                                          &want_mpub,
                                          1,
                                          &want_dki));
  cfg = GNUNET_CONFIGURATION_create ();

  GNUNET_CONFIGURATION_set_value_string (cfg,
                                         "exchangedb",
                                         "AUDITOR_BASE_DIR",
                                         tmpdir);
  EXITIF (1 !=
          TALER_EXCHANGEDB_auditor_iterate (cfg,
                                            &auditor_cb,
                                            NULL));
  ret = 0;
 EXITIF_exit:
  if (NULL != tmpdir)
  {
    (void) GNUNET_DISK_directory_remove (tmpdir);
    GNUNET_free (tmpdir);
  }
  if (NULL != cfg)
    GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free_non_null (tmpfile);
  return ret;
}
