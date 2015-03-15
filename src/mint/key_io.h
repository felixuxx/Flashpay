/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file mint/key_io.h
 * @brief IO operations for the mint's private keys
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef KEY_IO_H
#define KEY_IO_H

#include <gnunet/gnunet_util_lib.h>
#include "taler_signatures.h"

/**
 * Subdirectroy under the mint's base directory which contains
 * the mint's signing keys.
 */
#define DIR_SIGNKEYS "signkeys"

/**
 * Subdirectory under the mint's base directory which contains
 * the mint's denomination keys.
 */
#define DIR_DENOMKEYS "denomkeys"


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * On disk format used for a mint signing key.  Signing keys are used
 * by the mint to affirm its messages, but not to create coins.
 * Includes the private key followed by the public information about
 * the signing key.
 */
struct TALER_MINT_SignKeyIssuePriv
{
  /**
   * Private key part of the mint's signing key.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey signkey_priv;

  /**
   * Public information about a mint signing key.
   */
  struct TALER_MINT_SignKeyIssue issue;
};


GNUNET_NETWORK_STRUCT_END


/**
 * All information about a denomination key (which is used to
 * sign coins into existence).
 */
struct TALER_MINT_DenomKeyIssuePriv
{
  /**
   * The private key of the denomination.  Will be NULL if the private
   * key is not available (this is the case after the key has expired
   * for signing coins, but is still valid for depositing coins).
   */
  struct GNUNET_CRYPTO_rsa_PrivateKey *denom_priv;

  /**
   * Decoded denomination public key (the hash of it is in
   * @e issue, but we sometimes need the full public key as well).
   */
  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;

  /**
   * Signed public information about a denomination key.
   */
  struct TALER_MINT_DenomKeyIssue issue;
};


/**
 * Iterator over signing keys.
 *
 * @param cls closure
 * @param filename name of the file the key came from
 * @param ski the sign key
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
typedef int
(*TALER_MINT_SignkeyIterator)(void *cls,
                              const char *filename,
                              const struct TALER_MINT_SignKeyIssuePriv *ski);


/**
 * Iterator over denomination keys.
 *
 * @param cls closure
 * @param dki the denomination key
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
 * Call @a it for each signing key found in the @a mint_base_dir.
 *
 * @param mint_base_dir base directory for the mint,
 *                      the signing keys must be in the #DIR_SIGNKEYS
 *                      subdirectory
 * @param it function to call on each signing key
 * @param it_cls closure for @a it
 * @return number of files found (may not match
 *         number of keys given to @a it as malformed
 *         files are simply skipped), -1 on error
 */
int
TALER_MINT_signkeys_iterate (const char *mint_base_dir,
                             TALER_MINT_SignkeyIterator it,
                             void *it_cls);


/**
 * Call @a it for each denomination key found in the @a mint_base_dir.
 *
 * @param mint_base_dir base directory for the mint,
 *                      the signing keys must be in the #DIR_DENOMKEYS
 *                      subdirectory
 * @param it function to call on each denomination key found
 * @param it_cls closure for @a it
 * @return -1 on error, 0 if no files were found, otherwise
 *         a positive number (however, even with a positive
 *         number it is possible that @a it was never called
 *         as maybe none of the files were well-formed)
 */
int
TALER_MINT_denomkeys_iterate (const char *mint_base_dir,
                              TALER_MINT_DenomkeyIterator it,
                              void *it_cls);


/**
 * Exports a denomination key to the given file.
 *
 * @param filename the file where to write the denomination key
 * @param dki the denomination key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure.
 */
int
TALER_MINT_write_denom_key (const char *filename,
                            const struct TALER_MINT_DenomKeyIssuePriv *dki);


/**
 * Import a denomination key from the given file.
 *
 * @param filename the file to import the key from
 * @param[OUT] dki set to the imported denomination key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
int
TALER_MINT_read_denom_key (const char *filename,
                           struct TALER_MINT_DenomKeyIssuePriv *dki);


#endif
