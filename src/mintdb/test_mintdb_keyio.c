/*
  This file is part of TALER
  Copyright (C) 2014 GNUnet e. V. (and other contributing authors)

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
 * @file mint/test_mint_common.c
 * @brief test cases for some functions in mint/mint_common.c
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include "gnunet/gnunet_util_lib.h"
#include "taler_signatures.h"
#include "key_io.h"

#define RSA_KEY_SIZE 1024


#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)


int
main (int argc,
      const char *const argv[])
{
  struct TALER_DenominationKeyIssueInformation dki;
  char *enc;
  size_t enc_size;
  struct TALER_DenominationKeyIssueInformation dki_read;
  char *enc_read;
  size_t enc_read_size;
  char *tmpfile;
  int ret;

  ret = 1;
  enc = NULL;
  enc_read = NULL;
  tmpfile = NULL;
  dki.denom_priv.rsa_private_key = NULL;
  dki_read.denom_priv.rsa_private_key = NULL;
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &dki.issue.signature,
                              sizeof (dki) - offsetof (struct TALER_DenominationKeyValidityPS,
                                                       signature));
  dki.denom_priv.rsa_private_key
    = GNUNET_CRYPTO_rsa_private_key_create (RSA_KEY_SIZE);
  enc_size = GNUNET_CRYPTO_rsa_private_key_encode (dki.denom_priv.rsa_private_key,
                                                   &enc);
  EXITIF (NULL == (tmpfile = GNUNET_DISK_mktemp ("test_mint_common")));
  EXITIF (GNUNET_OK != TALER_MINT_write_denom_key (tmpfile, &dki));
  EXITIF (GNUNET_OK != TALER_MINT_read_denom_key (tmpfile, &dki_read));
  enc_read_size = GNUNET_CRYPTO_rsa_private_key_encode (dki_read.denom_priv.rsa_private_key,
                                                        &enc_read);
  EXITIF (enc_size != enc_read_size);
  EXITIF (0 != memcmp (enc,
                       enc_read,
                       enc_size));
  ret = 0;

  EXITIF_exit:
  GNUNET_free_non_null (enc);
  if (NULL != tmpfile)
  {
    (void) unlink (tmpfile);
    GNUNET_free (tmpfile);
  }
  GNUNET_free_non_null (enc_read);
  if (NULL != dki.denom_priv.rsa_private_key)
    GNUNET_CRYPTO_rsa_private_key_free (dki.denom_priv.rsa_private_key);
  if (NULL != dki_read.denom_priv.rsa_private_key)
    GNUNET_CRYPTO_rsa_private_key_free (dki_read.denom_priv.rsa_private_key);
  return ret;
}
