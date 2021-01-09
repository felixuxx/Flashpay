/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file secmod_signatures.c
 * @brief Utility functions for Taler security module signatures
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


void
TALER_wallet_link_sign (const struct GNUNET_HashCode *h_denom_pub,
                        const struct TALER_TransferPublicKeyP *transfer_pub,
                        const void *coin_ev,
                        size_t coin_ev_size,
                        const struct TALER_CoinSpendPrivateKeyP *old_coin_priv,
                        struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_LinkDataPS ldp = {
    .purpose.size = htonl (sizeof (ldp)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_LINK),
    .h_denom_pub = *h_denom_pub,
    .transfer_pub = *transfer_pub
  };

  GNUNET_CRYPTO_hash (coin_ev,
                      coin_ev_size,
                      &ldp.coin_envelope_hash);
  GNUNET_CRYPTO_eddsa_key_get_public (&old_coin_priv->eddsa_priv,
                                      &ldp.old_coin_pub.eddsa_pub);
  GNUNET_CRYPTO_eddsa_sign (&old_coin_priv->eddsa_priv,
                            &ldp,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_link_verify (
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_TransferPublicKeyP *transfer_pub,
  const void *coin_ev,
  size_t coin_ev_size,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_LinkDataPS ldp = {
    .purpose.size = htonl (sizeof (ldp)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_LINK),
    .h_denom_pub = *h_denom_pub,
    .old_coin_pub = *old_coin_pub,
    .transfer_pub = *transfer_pub
  };

  GNUNET_CRYPTO_hash (coin_ev,
                      coin_ev_size,
                      &ldp.coin_envelope_hash);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_LINK,
                                &ldp,
                                &coin_sig->eddsa_signature,
                                &old_coin_pub->eddsa_pub);
}


/* end of wallet_signatures.c */
