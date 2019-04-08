/*
  This file is part of TALER
  Copyright (C) 2014-2017 GNUnet e. V. (and other contributing authors)

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
 * @file exchangedb/test_exchangedb_denomkeys.c
 * @brief test cases for some functions in exchangedb/exchangedb_denomkeys.c
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
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


/**
 * @brief Iterator called on denomination key.
 *
 * @param cls closure with expected DKI
 * @param dki the denomination key
 * @param alias coin alias
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
dki_iter (void *cls,
          const char *alias,
          const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki)
{
  const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *exp = cls;

  if (0 != GNUNET_memcmp (&exp->issue,
                          &dki->issue))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 !=
      GNUNET_CRYPTO_rsa_private_key_cmp (exp->denom_priv.rsa_private_key,
                                         dki->denom_priv.rsa_private_key))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 !=
      GNUNET_CRYPTO_rsa_public_key_cmp (exp->denom_pub.rsa_public_key,
                                        dki->denom_pub.rsa_public_key))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * @brief Iterator called on revoked denomination key.
 *
 * @param cls closure with expected DKI
 * @param denom_hash hash of the revoked denomination key
 * @param revocation_master_sig non-NULL if @a dki was revoked
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
dki_iter_revoked (void *cls,
                  const struct GNUNET_HashCode *denom_hash,
                  const struct TALER_MasterSignatureP *revocation_master_sig)
{
  const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *exp = cls;

  if (NULL == revocation_master_sig)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 != memcmp (denom_hash,
                   &exp->issue.properties.denom_hash,
                   sizeof (struct GNUNET_HashCode)))
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
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation dki;
  char *enc;
  size_t enc_size;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation dki_read;
  struct GNUNET_CRYPTO_EddsaPrivateKey *pk;
  struct TALER_MasterPrivateKeyP master_priv;
  struct TALER_MasterPublicKeyP master_pub;
  char *enc_read;
  size_t enc_read_size;
  char *tmpfile;
  char *tmpdir;
  char *revdir;
  int ret;
  struct GNUNET_TIME_Absolute start;

  ret = 1;
  GNUNET_log_setup ("test-exchangedb-denomkeys",
                    "WARNING",
                    NULL);
  enc = NULL;
  enc_read = NULL;
  tmpfile = NULL;
  dki.denom_priv.rsa_private_key = NULL;
  dki_read.denom_priv.rsa_private_key = NULL;
  pk = GNUNET_CRYPTO_eddsa_key_create ();
  master_priv.eddsa_priv = *pk;
  GNUNET_CRYPTO_eddsa_key_get_public (pk,
                                      &master_pub.eddsa_pub);
  GNUNET_free (pk);
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &dki.issue,
                              sizeof (struct TALER_EXCHANGEDB_DenominationKeyInformationP));
  dki.denom_priv.rsa_private_key
    = GNUNET_CRYPTO_rsa_private_key_create (RSA_KEY_SIZE);
  dki.denom_pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_private_key_get_public (dki.denom_priv.rsa_private_key);
  enc_size = GNUNET_CRYPTO_rsa_private_key_encode (dki.denom_priv.rsa_private_key,
                                                   &enc);
  EXITIF (NULL == (tmpdir = GNUNET_DISK_mkdtemp ("test_exchangedb_dki")));
  start = GNUNET_TIME_absolute_ntoh (dki.issue.properties.start);
  GNUNET_asprintf (&tmpfile,
                   "%s/%s/%s/%llu",
                   tmpdir,
                   TALER_EXCHANGEDB_DIR_DENOMINATION_KEYS,
                   "cur-unit-uuid",
                   (unsigned long long) start.abs_value_us);
  GNUNET_asprintf (&revdir,
                   "%s/revocations/",
                   tmpdir,
                   TALER_EXCHANGEDB_DIR_DENOMINATION_KEYS);
  EXITIF (GNUNET_OK !=
          TALER_EXCHANGEDB_denomination_key_write (tmpfile,
                                                   &dki));
  EXITIF (GNUNET_OK !=
          TALER_EXCHANGEDB_denomination_key_read (tmpfile,
                                                  &dki_read));
  EXITIF (1 !=
          TALER_EXCHANGEDB_denomination_keys_iterate (tmpdir,
                                                      &dki_iter,
                                                      &dki));

  EXITIF (GNUNET_OK !=
          TALER_EXCHANGEDB_denomination_key_revoke (revdir,
                                                    &dki.issue.properties.denom_hash,
                                                    &master_priv));
  EXITIF (1 !=
          TALER_EXCHANGEDB_revocations_iterate (revdir,
						&master_pub,
						&dki_iter_revoked,
						&dki));
  GNUNET_free (revdir);

  enc_read_size = GNUNET_CRYPTO_rsa_private_key_encode (dki_read.denom_priv.rsa_private_key,
                                                        &enc_read);
  EXITIF (enc_size != enc_read_size);
  EXITIF (0 != memcmp (enc,
                       enc_read,
                       enc_size));
  ret = 0;

 EXITIF_exit:
  GNUNET_free_non_null (enc);
  GNUNET_free_non_null (tmpfile);
  if (NULL != tmpdir)
  {
    (void) GNUNET_DISK_directory_remove (tmpdir);
    GNUNET_free (tmpdir);
  }
  GNUNET_free_non_null (enc_read);
  if (NULL != dki.denom_priv.rsa_private_key)
    GNUNET_CRYPTO_rsa_private_key_free (dki.denom_priv.rsa_private_key);
  if (NULL != dki.denom_pub.rsa_public_key)
    GNUNET_CRYPTO_rsa_public_key_free (dki.denom_pub.rsa_public_key);
  if (NULL != dki_read.denom_priv.rsa_private_key)
    GNUNET_CRYPTO_rsa_private_key_free (dki_read.denom_priv.rsa_private_key);
  return ret;
}
