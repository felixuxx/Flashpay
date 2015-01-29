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
