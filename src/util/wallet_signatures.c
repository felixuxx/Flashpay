/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
 * @file wallet_signatures.c
 * @brief Utility functions for Taler wallet signatures
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


void
TALER_wallet_deposit_sign (
  const struct TALER_Amount *amount,
  const struct TALER_Amount *deposit_fee,
  const struct TALER_MerchantWireHash *h_wire,
  const struct TALER_PrivateContractHash *h_contract_terms,
  const struct TALER_ExtensionContractHash *h_extensions,
  const struct TALER_DenominationHash *h_denom_pub,
  struct GNUNET_TIME_Timestamp wallet_timestamp,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_DepositRequestPS dr = {
    .purpose.size = htonl (sizeof (dr)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT),
    .h_contract_terms = *h_contract_terms,
    .h_wire = *h_wire,
    .h_denom_pub = *h_denom_pub,
    .wallet_timestamp = GNUNET_TIME_timestamp_hton (wallet_timestamp),
    .refund_deadline = GNUNET_TIME_timestamp_hton (refund_deadline),
    .merchant = *merchant_pub
  };

  if (NULL != h_extensions)
    dr.h_extensions = *h_extensions;
  TALER_amount_hton (&dr.amount_with_fee,
                     amount);
  TALER_amount_hton (&dr.deposit_fee,
                     deposit_fee);
  GNUNET_CRYPTO_eddsa_sign (&coin_priv->eddsa_priv,
                            &dr,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_deposit_verify (
  const struct TALER_Amount *amount,
  const struct TALER_Amount *deposit_fee,
  const struct TALER_MerchantWireHash *h_wire,
  const struct TALER_PrivateContractHash *h_contract_terms,
  const struct TALER_ExtensionContractHash *h_extensions,
  const struct TALER_DenominationHash *h_denom_pub,
  struct GNUNET_TIME_Timestamp wallet_timestamp,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_DepositRequestPS dr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT),
    .purpose.size = htonl (sizeof (dr)),
    .h_contract_terms = *h_contract_terms,
    .h_wire = *h_wire,
    .h_denom_pub = *h_denom_pub,
    .wallet_timestamp = GNUNET_TIME_timestamp_hton (wallet_timestamp),
    .refund_deadline = GNUNET_TIME_timestamp_hton (refund_deadline),
    .merchant = *merchant_pub
  };

  if (NULL != h_extensions)
    dr.h_extensions = *h_extensions;
  TALER_amount_hton (&dr.amount_with_fee,
                     amount);
  TALER_amount_hton (&dr.deposit_fee,
                     deposit_fee);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                  &dr,
                                  &coin_sig->eddsa_signature,
                                  &coin_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


void
TALER_wallet_link_sign (const struct TALER_DenominationHash *h_denom_pub,
                        const struct TALER_TransferPublicKeyP *transfer_pub,
                        // FIXME: consider passing hash!
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
                      &ldp.coin_envelope_hash.hash);
  GNUNET_CRYPTO_eddsa_sign (&old_coin_priv->eddsa_priv,
                            &ldp,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_link_verify (
  const struct TALER_DenominationHash *h_denom_pub,
  const struct TALER_TransferPublicKeyP *transfer_pub,
  // FIXME: consider passing hash!
  const void *coin_ev,
  size_t coin_ev_size,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_LinkDataPS ldp = {
    .purpose.size = htonl (sizeof (ldp)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_LINK),
    .h_denom_pub = *h_denom_pub,
    .transfer_pub = *transfer_pub
  };

  GNUNET_CRYPTO_hash (coin_ev,
                      coin_ev_size,
                      &ldp.coin_envelope_hash.hash);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_LINK,
                                &ldp,
                                &coin_sig->eddsa_signature,
                                &old_coin_pub->eddsa_pub);
}


enum GNUNET_GenericReturnValue
TALER_wallet_recoup_verify (
  const struct TALER_DenominationHash *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_Amount *requested_amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RecoupRequestPS pr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_RECOUP),
    .purpose.size = htonl (sizeof (pr)),
    .h_denom_pub = *h_denom_pub,
    .coin_blind = *coin_bks
  };

  TALER_amount_hton (&pr.recoup_amount,
                     requested_amount);
  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_RECOUP,
                                     &pr,
                                     &coin_sig->eddsa_signature,
                                     &coin_pub->eddsa_pub);
}


void
TALER_wallet_recoup_sign (
  const struct TALER_DenominationHash *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_Amount *requested_amount,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RecoupRequestPS pr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_RECOUP),
    .purpose.size = htonl (sizeof (struct TALER_RecoupRequestPS)),
    .h_denom_pub = *h_denom_pub,
    .coin_blind = *coin_bks
  };

  TALER_amount_hton (&pr.recoup_amount,
                     requested_amount);
  GNUNET_CRYPTO_eddsa_sign (&coin_priv->eddsa_priv,
                            &pr,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_recoup_refresh_verify (
  const struct TALER_DenominationHash *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_Amount *requested_amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RecoupRequestPS pr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_RECOUP_REFRESH),
    .purpose.size = htonl (sizeof (pr)),
    .h_denom_pub = *h_denom_pub,
    .coin_blind = *coin_bks
  };

  TALER_amount_hton (&pr.recoup_amount,
                     requested_amount);
  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_RECOUP_REFRESH,
                                     &pr,
                                     &coin_sig->eddsa_signature,
                                     &coin_pub->eddsa_pub);
}


void
TALER_wallet_recoup_refresh_sign (
  const struct TALER_DenominationHash *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_Amount *requested_amount,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RecoupRequestPS pr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_RECOUP_REFRESH),
    .purpose.size = htonl (sizeof (struct TALER_RecoupRequestPS)),
    .h_denom_pub = *h_denom_pub,
    .coin_blind = *coin_bks
  };

  TALER_amount_hton (&pr.recoup_amount,
                     requested_amount);
  GNUNET_CRYPTO_eddsa_sign (&coin_priv->eddsa_priv,
                            &pr,
                            &coin_sig->eddsa_signature);
}


void
TALER_wallet_melt_sign (
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *melt_fee,
  const struct TALER_RefreshCommitmentP *rc,
  const struct TALER_DenominationHash *h_denom_pub,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RefreshMeltCoinAffirmationPS melt = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT),
    .purpose.size = htonl (sizeof (melt)),
    .rc = *rc,
    .h_denom_pub = *h_denom_pub
  };

  TALER_amount_hton (&melt.amount_with_fee,
                     amount_with_fee);
  TALER_amount_hton (&melt.melt_fee,
                     melt_fee);
  GNUNET_CRYPTO_eddsa_sign (&coin_priv->eddsa_priv,
                            &melt,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_melt_verify (
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *melt_fee,
  const struct TALER_RefreshCommitmentP *rc,
  const struct TALER_DenominationHash *h_denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RefreshMeltCoinAffirmationPS melt = {
    .purpose.size = htonl (sizeof (melt)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT),
    .rc = *rc,
    .h_denom_pub = *h_denom_pub
  };

  TALER_amount_hton (&melt.amount_with_fee,
                     amount_with_fee);
  TALER_amount_hton (&melt.melt_fee,
                     melt_fee);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_COIN_MELT,
    &melt,
    &coin_sig->eddsa_signature,
    &coin_pub->eddsa_pub);
}


/* end of wallet_signatures.c */
