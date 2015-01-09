/*
  This file is part of TALER
  (C) 2014 GNUnet e. V. (and other contributing authors)

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
#include "taler_rsa.h"
#include "mint.h"

#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)

int
main (int argc, const char *const argv[])
{
  struct TALER_MINT_DenomKeyIssuePriv dki;
  struct TALER_RSA_PrivateKeyBinaryEncoded *enc;
  struct TALER_MINT_DenomKeyIssuePriv dki_read;
  struct TALER_RSA_PrivateKeyBinaryEncoded *enc_read;
  char *tmpfile;

  int ret;

  ret = 1;
  enc = NULL;
  enc_read = NULL;
  tmpfile = NULL;
  dki.denom_priv = NULL;
  dki_read.denom_priv = NULL;
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &dki.issue.signature,
                              sizeof (dki) - offsetof (struct TALER_MINT_DenomKeyIssue,
                                                       signature));
  dki.denom_priv = TALER_RSA_key_create ();
  EXITIF (NULL == (enc = TALER_RSA_encode_key (dki.denom_priv)));
  EXITIF (NULL == (tmpfile = GNUNET_DISK_mktemp ("test_mint_common")));
  EXITIF (GNUNET_OK != TALER_MINT_write_denom_key (tmpfile, &dki));
  EXITIF (GNUNET_OK != TALER_MINT_read_denom_key (tmpfile, &dki_read));
  EXITIF (NULL == (enc_read = TALER_RSA_encode_key (dki_read.denom_priv)));
  EXITIF (enc->len != enc_read->len);
  EXITIF (0 != memcmp (enc,
                       enc_read,
                       ntohs(enc->len)));
  EXITIF (0 != memcmp (&dki.issue.signature,
                       &dki_read.issue.signature,
                       sizeof (dki) - offsetof (struct TALER_MINT_DenomKeyIssue,
                                                signature)));
  ret = 0;

  EXITIF_exit:
  GNUNET_free_non_null (enc);
  if (NULL != tmpfile)
  {
    (void) unlink (tmpfile);
    GNUNET_free (tmpfile);
  }
  GNUNET_free_non_null (enc_read);
  if (NULL != dki.denom_priv)
    TALER_RSA_key_free (dki.denom_priv);
  if (NULL != dki_read.denom_priv)
    TALER_RSA_key_free (dki_read.denom_priv);
  return ret;
}
