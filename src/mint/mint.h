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
 * @file mint.h
 * @brief Common functionality for the mint
 * @author Florian Dold
 * @author Benedikt Mueller
 *
 * TODO:
 * - revisit and document `struct Deposit` members.
 */
#ifndef _MINT_H
#define _MINT_H

#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_common.h>
#include <libpq-fe.h>
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
 * Public information about a coin.
 */
struct TALER_CoinPublicInfo
{
  /**
   * The coin's public key.
   */
  struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;

  /*
   * The public key signifying the coin's denomination.
   */
  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;

  /**
   * Signature over coin_pub by denom_pub.
   */
  struct GNUNET_CRYPTO_rsa_Signature *denom_sig;
};



/**
 * Information we keep for a withdrawn coin to reproduce
 * the /withdraw operation if needed, and to have proof
 * that a reserve was drained by this amount.
 */
struct CollectableBlindcoin
{

  /**
   * Our signature over the (blinded) coin.
   */
  struct GNUNET_CRYPTO_rsa_Signature *sig;

  /**
   * Denomination key (which coin was generated).
   */
  struct GNUNET_CRYPOT_rsa_PublicKey *denom_pub;

  /**
   * Public key of the reserve that was drained.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;

  /**
   * Signature confirming the withdrawl, matching @e reserve_pub,
   * @e denom_pub and @e h_blind.
   */
  struct GNUNET_CRYPTO_EddsaSignature reserve_sig;
};


struct RefreshSession
{
  int has_commit_sig;
  struct GNUNET_CRYPTO_EddsaSignature commit_sig;
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;
  uint16_t num_oldcoins;
  uint16_t num_newcoins;
  uint16_t kappa;
  uint16_t noreveal_index;
  uint8_t reveal_ok;
};


#define TALER_REFRESH_SHARED_SECRET_LENGTH (sizeof (struct GNUNET_HashCode))
#define TALER_REFRESH_LINK_LENGTH (sizeof (struct LinkData))

struct RefreshCommitLink
{
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;
  struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub;
  uint16_t cnc_index;
  uint16_t oldcoin_index;
  char shared_secret_enc[sizeof (struct GNUNET_HashCode)];
};

struct LinkData
{
  struct GNUNET_CRYPTO_EcdsaPrivateKey coin_priv;
  struct GNUNET_CRYPTO_rsa_BlindingKey *bkey_enc;
};


GNUNET_NETWORK_STRUCT_BEGIN

struct SharedSecretEnc
{
  char data[TALER_REFRESH_SHARED_SECRET_LENGTH];
};


struct LinkDataEnc
{
  char data[sizeof (struct LinkData)];
};

GNUNET_NETWORK_STRUCT_END

struct RefreshCommitCoin
{
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;

  /**
   * Blinded message to be signed (in envelope).
   */
  char *coin_ev;

  /**
   * Number of bytes in @e coin_ev.
   */
  size_t coin_ev_size;

  uint16_t cnc_index;
  uint16_t newcoin_index;
  char link_enc[sizeof (struct LinkData)];
};


struct KnownCoin
{
  struct TALER_CoinPublicInfo public_info;
  struct TALER_Amount expended_balance;
  int is_refreshed;
  /**
   * Refreshing session, only valid if
   * is_refreshed==1.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey refresh_session_pub;
};


/**
 * Specification for a /deposit operation.
 */
struct Deposit
{
  /* FIXME: should be TALER_CoinPublicInfo */
  struct GNUNET_CRYPTO_EddsaPublicKey coin_pub;

  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;

  struct GNUNET_CRYPTO_rsa_Signature *coin_sig;

  struct GNUNET_CRYPTO_rsa_Signature *ubsig; // ???

  /**
   * Type of the deposit (also purpose of the signature).  Either
   * #TALER_SIGNATURE_DEPOSIT or #TALER_SIGNATURE_INCREMENTAL_DEPOSIT.
   */
  // struct TALER_RSA_SignaturePurpose purpose; // FIXME: bad type!

  uint64_t transaction_id;

  struct TALER_AmountNBO amount;

  struct GNUNET_CRYPTO_EddsaPublicKey merchant_pub;

  struct GNUNET_HashCode h_contract;

  struct GNUNET_HashCode h_wire;

  /* TODO: uint16_t wire_size */
  char wire[];                  /* string encoded wire JSON object */

};


/**
 * Reserve row.  Corresponds to table 'reserves' in the mint's
 * database.  FIXME: not sure this is how we want to store this
 * information.  Also, may currently used in different ways in the
 * code, so we might need to separate the struct into different ones
 * depending on the context it is used in.
 */
struct Reserve
{
  /**
   * Signature over the purse.
   * Only valid if (blind_session_missing==GNUNET_YES).
   */
  struct GNUNET_CRYPTO_EddsaSignature status_sig;
  /**
   * Signature with purpose TALER_SIGNATURE_PURSE.
   * Only valid if (blind_session_missing==GNUNET_YES).
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose status_sig_purpose;
  /**
   * Signing key used to sign the purse.
   * Only valid if (blind_session_missing==GNUNET_YES).
   */
  struct GNUNET_CRYPTO_EddsaPublicKey status_sign_pub;
  /**
   * Withdraw public key, identifies the purse.
   * Only the customer knows the corresponding private key.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;
  /**
   * Remaining balance in the purse.
   */
  struct TALER_AmountNBO balance;

  /**
   * Expiration date for the purse.
   */
  struct GNUNET_TIME_AbsoluteNBO expiration;
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
