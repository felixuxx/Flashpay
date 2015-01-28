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
 * @brief Common structs passed all over the mint logic
 * @author Florian Dold
 * @author Benedikt Mueller
 */
#ifndef _MINT_H
#define _MINT_H

#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_util.h"


/**
 * For now, we just do EUR.  Should become configurable
 * in the future!
 */
#define MINT_CURRENCY "EUR"



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



#endif /* _MINT_H */
