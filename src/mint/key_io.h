/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

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
 * @file key_io.h
 * @brief IO operations for the mint's private keys
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 *
 * TODO:
 * - document better
 */
#ifndef KEY_IO_H
#define KEY_IO_H

#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_common.h>
#include "taler_util.h"
#include "taler_signatures.h"

#define DIR_SIGNKEYS "signkeys"
#define DIR_DENOMKEYS "denomkeys"

/**
 * On disk format used for a mint signing key.
 * Includes the private key followed by the signed
 * issue message.
 */
struct TALER_MINT_SignKeyIssuePriv
{
  struct GNUNET_CRYPTO_EddsaPrivateKey signkey_priv;

  struct TALER_MINT_SignKeyIssue issue;
};



struct TALER_MINT_DenomKeyIssuePriv
{
  /**
   * The private key of the denomination.  Will be NULL if the private key is
   * not available.
   */
  struct GNUNET_CRYPTO_rsa_PrivateKey *denom_priv;

  struct TALER_MINT_DenomKeyIssue issue;
};




/**
 * Iterator for sign keys.
 *
 * @param cls closure
 * @param ski the sign key issue
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
typedef int
(*TALER_MINT_SignkeyIterator)(void *cls,
                              const struct TALER_MINT_SignKeyIssuePriv *ski);

/**
 * Iterator for denomination keys.
 *
 * @param cls closure
 * @param dki the denomination key issue
 * @param alias coin alias
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
typedef int
(*TALER_MINT_DenomkeyIterator)(void *cls,
                               const char *alias,
                               const struct TALER_MINT_DenomKeyIssuePriv *dki);



/**
 * FIXME
 */
int
TALER_MINT_signkeys_iterate (const char *mint_base_dir,
                             TALER_MINT_SignkeyIterator it, void *cls);


/**
 * FIXME
 */
int
TALER_MINT_denomkeys_iterate (const char *mint_base_dir,
                              TALER_MINT_DenomkeyIterator it, void *cls);


/**
 * Exports a denomination key to the given file
 *
 * @param filename the file where to write the denomination key
 * @param dki the denomination key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure.
 */
int
TALER_MINT_write_denom_key (const char *filename,
                            const struct TALER_MINT_DenomKeyIssuePriv *dki);


/**
 * Import a denomination key from the given file
 *
 * @param filename the file to import the key from
 * @param dki pointer to return the imported denomination key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
int
TALER_MINT_read_denom_key (const char *filename,
                           struct TALER_MINT_DenomKeyIssuePriv *dki);





#endif
