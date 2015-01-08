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
 * @file taler_mint.h
 * @brief Common functionality for the mint
 * @author Florian Dold
 * @author Benedikt Mueller
 */

#ifndef _MINT_H
#define _MINT_H

#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_common.h>
#include <libpq-fe.h>
#include "taler_util.h"
#include "taler_rsa.h"

#define DIR_SIGNKEYS "signkeys"
#define DIR_DENOMKEYS "denomkeys"


GNUNET_NETWORK_STRUCT_BEGIN


/**
 * FIXME
 */
struct TALER_MINT_SignKeyIssue
{
  struct GNUNET_CRYPTO_EddsaPrivateKey signkey_priv;
  struct GNUNET_CRYPTO_EddsaSignature signature;
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_CRYPTO_EddsaPublicKey master_pub;
  struct GNUNET_TIME_AbsoluteNBO start;
  struct GNUNET_TIME_AbsoluteNBO expire;
  struct GNUNET_CRYPTO_EddsaPublicKey signkey_pub;
};

struct TALER_MINT_DenomKeyIssue
{
  /**
   * The private key of the denomination.  Will be NULL if the private key is
   * not available.
   */
  struct TALER_RSA_PrivateKey *denom_priv;
  struct GNUNET_CRYPTO_EddsaSignature signature;
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_CRYPTO_EddsaPublicKey master;
  struct GNUNET_TIME_AbsoluteNBO start;
  struct GNUNET_TIME_AbsoluteNBO expire_withdraw;
  struct GNUNET_TIME_AbsoluteNBO expire_spend;
  struct TALER_RSA_PublicKeyBinaryEncoded denom_pub;
  struct TALER_AmountNBO value;
  struct TALER_AmountNBO fee_withdraw;
  struct TALER_AmountNBO fee_deposit;
  struct TALER_AmountNBO fee_refresh;
};

struct RefreshMeltSignatureBody
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_HashCode melt_hash;
};

struct RefreshCommitSignatureBody
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_HashCode commit_hash;
};

struct RefreshCommitResponseSignatureBody
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  uint16_t noreveal_index;
};

struct RefreshMeltResponseSignatureBody
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_HashCode melt_response_hash;
};


struct RefreshMeltConfirmSignRequestBody
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;
};


GNUNET_NETWORK_STRUCT_END



/**
 * Iterator for sign keys.
 *
 * @param cls closure
 * @param ski the sign key issue
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
typedef int (*TALER_MINT_SignkeyIterator)(void *cls,
                                          const struct TALER_MINT_SignKeyIssue *ski);

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
typedef int (*TALER_MINT_DenomkeyIterator)(void *cls,
                                           const char *alias,
                                           const struct TALER_MINT_DenomKeyIssue *dki);



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
                            const struct TALER_MINT_DenomKeyIssue *dki);


/**
 * Import a denomination key from the given file
 *
 * @param filename the file to import the key from
 * @param dki pointer to return the imported denomination key
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
int
TALER_MINT_read_denom_key (const char *filename,
                           struct TALER_MINT_DenomKeyIssue *dki);


/**
 * Load the configuration for the mint in the given
 * directory.
 *
 * @param mint_base_dir the mint's base directory
 * @return the mint configuratin, or NULL on error
 */
struct GNUNET_CONFIGURATION_Handle *
TALER_MINT_config_load (const char *mint_base_dir);


int
TALER_TALER_DB_extract_amount (PGresult *result, unsigned int row,
                        int indices[3], struct TALER_Amount *denom);

int
TALER_TALER_DB_extract_amount_nbo (PGresult *result, unsigned int row,
                             int indices[3], struct TALER_AmountNBO *denom_nbo);

#endif /* _MINT_H */

