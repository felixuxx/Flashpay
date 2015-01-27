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
#include <jansson.h>
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

  /**
   * Public key representing the denomination of the coin
   * that is being deposited.
   */
  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;

  /**
   * (Unblinded) signature over @e coin_pub with @e denom_pub,
   * which demonstrates that the coin is valid.
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
  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;

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


/**
 * Global information for a refreshing session.
 */
struct RefreshSession
{
  /**
   * Signature over the commitments by the client.
   */
  struct GNUNET_CRYPTO_EddsaSignature commit_sig;

  /**
   * Public key of the refreshing session, used to sign
   * the client's commit message.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;

  /**
   * Number of coins we are melting.
   */
  uint16_t num_oldcoins;

  /**
   * Number of new coins we are creating.
   */
  uint16_t num_newcoins;

  /**
   * Number of parallel operations we perform for the cut and choose.
   * (must be greater or equal to three for security).
   */
  uint16_t kappa;

  /**
   * Index (smaller @e kappa) which the mint has chosen to not
   * have revealed during cut and choose.
   */
  uint16_t noreveal_index;

  /**
   * FIXME.
   */
  int has_commit_sig;

  /**
   * FIXME.
   */
  uint8_t reveal_ok;
};


/**
 * For each (old) coin being melted, we have a `struct
 * RefreshCommitLink` that allows the user to find the shared secret
 * to decrypt the respective refresh links for the new coins in the
 * `struct RefreshCommitCoin`.
 */
struct RefreshCommitLink
{
  /**
   * Transfer public key (FIXME: explain!)
   */
  struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub;

  /**
   * Encrypted shared secret to decrypt the link.
   */
  struct TALER_EncryptedLinkSecret shared_secret_enc;
};


/**
 * We have as many `struct RefreshCommitCoin` as there are new
 * coins being created by the refresh.
 */
struct RefreshCommitCoin
{

  /**
   * Encrypted data allowing those able to decrypt it to derive
   * the private keys of the new coins created by the refresh.
   */
  struct TALER_RefreshLinkEncrypted *refresh_link;

  /**
   * Blinded message to be signed (in envelope), with @e coin_env_size bytes.
   */
  char *coin_ev;

  /**
   * Number of bytes in @e coin_ev.
   */
  size_t coin_ev_size;

};


/**
 * FIXME
 */
struct KnownCoin
{
  struct TALER_CoinPublicInfo public_info;

  /**
   * Refreshing session, only valid if
   * is_refreshed==1.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey refresh_session_pub;

  struct TALER_Amount expended_balance;

  int is_refreshed;

};


/**
 * Specification for a /deposit operation.
 */
struct Deposit
{
  /**
   * Information about the coin that is being deposited.
   */
  struct TALER_CoinPublicInfo coin;

  /**
   * EdDSA signature affirming that the customer intends
   * this coin to be deposited at the merchant identified
   * by @e h_wire in relation to the contract identified
   * by @e h_contract.
   */
  struct GNUNET_CRYPTO_EddsaSignature csig;

  /**
   * Public key of the merchant.  Enables later identification
   * of the merchant in case of a need to rollback transactions.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey merchant_pub;

  /**
   * Hash over the contract between merchant and customer
   * (remains unknown to the Mint).
   */
  struct GNUNET_HashCode h_contract;

  /**
   * Hash of the (canonical) representation of @e wire, used
   * to check the signature on the request.  Generated by
   * the mint from the detailed wire data provided by the
   * merchant.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Detailed wire information for executing the transaction.
   */
  const json_t *wire;

  /**
   * Merchant-generated transaction ID to detect duplicate
   * transactions.
   */
  uint64_t transaction_id;

  /**
   * Fraction of the coin's remaining value to be deposited.
   * The coin is identified by @e coin_pub.
   */
  struct TALER_AmountNBO amount;

  /**
   * Type of the deposit (also purpose of the signature).  Either
   * #TALER_SIGNATURE_DEPOSIT or #TALER_SIGNATURE_INCREMENTAL_DEPOSIT.
   */
  uint32_t purpose; // FIXME: bad type, use ENUM!


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
TALER_TALER_DB_extract_amount (PGresult *result,
                               unsigned int row,
                               int indices[3],
                               struct TALER_Amount *denom);

int
TALER_TALER_DB_extract_amount_nbo (PGresult *result,
                                   unsigned int row,
                                   int indices[3],
                                   struct TALER_AmountNBO *denom_nbo);

#endif /* _MINT_H */
