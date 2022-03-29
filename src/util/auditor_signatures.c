/*
  This file is part of TALER
  Copyright (C) 2020, 2022 Taler Systems SA

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
 * @file auditor_signatures.c
 * @brief Utility functions for Taler auditor signatures
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


/**
 * @brief Information signed by an auditor affirming
 * the master public key and the denomination keys
 * of a exchange.
 */
struct TALER_ExchangeKeyValidityPS
{

  /**
   * Purpose is #TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the auditor's URL (including 0-terminator).
   */
  struct GNUNET_HashCode auditor_url_hash;

  /**
   * The long-term offline master key of the exchange, affirmed by the
   * auditor.
   */
  struct TALER_MasterPublicKeyP master;

  /**
   * Start time of the validity period for this key.
   */
  struct GNUNET_TIME_TimestampNBO start;

  /**
   * The exchange will sign fresh coins between @e start and this time.
   * @e expire_withdraw will be somewhat larger than @e start to
   * ensure a sufficiently large anonymity set, while also allowing
   * the Exchange to limit the financial damage in case of a key being
   * compromised.  Thus, exchanges with low volume are expected to have a
   * longer withdraw period (@e expire_withdraw - @e start) than exchanges
   * with high transaction volume.  The period may also differ between
   * types of coins.  A exchange may also have a few denomination keys
   * with the same value with overlapping validity periods, to address
   * issues such as clock skew.
   */
  struct GNUNET_TIME_TimestampNBO expire_withdraw;

  /**
   * Coins signed with the denomination key must be spent or refreshed
   * between @e start and this expiration time.  After this time, the
   * exchange will refuse transactions involving this key as it will
   * "drop" the table with double-spending information (shortly after)
   * this time.  Note that wallets should refresh coins significantly
   * before this time to be on the safe side.  @e expire_deposit must be
   * significantly larger than @e expire_withdraw (by months or even
   * years).
   */
  struct GNUNET_TIME_TimestampNBO expire_deposit;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_deposit (by a year or more).
   */
  struct GNUNET_TIME_TimestampNBO expire_legal;

  /**
   * The value of the coins signed with this denomination key.
   */
  struct TALER_AmountNBO value;

  /**
   * Fees for the coin.
   */
  struct TALER_DenomFeeSetNBOP fees;

  /**
   * Hash code of the denomination public key. (Used to avoid having
   * the variable-size RSA key in this struct.)
   */
  struct TALER_DenominationHashP denom_hash GNUNET_PACKED;

};


void
TALER_auditor_denom_validity_sign (
  const char *auditor_url,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Timestamp stamp_start,
  struct GNUNET_TIME_Timestamp stamp_expire_withdraw,
  struct GNUNET_TIME_Timestamp stamp_expire_deposit,
  struct GNUNET_TIME_Timestamp stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_DenomFeeSet *fees,
  const struct TALER_AuditorPrivateKeyP *auditor_priv,
  struct TALER_AuditorSignatureP *auditor_sig)
{
  struct TALER_ExchangeKeyValidityPS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS),
    .purpose.size = htonl (sizeof (kv)),
    .start = GNUNET_TIME_timestamp_hton (stamp_start),
    .expire_withdraw = GNUNET_TIME_timestamp_hton (stamp_expire_withdraw),
    .expire_deposit = GNUNET_TIME_timestamp_hton (stamp_expire_deposit),
    .expire_legal = GNUNET_TIME_timestamp_hton (stamp_expire_legal),
    .denom_hash = *h_denom_pub,
    .master = *master_pub,
  };

  TALER_amount_hton (&kv.value,
                     coin_value);
  TALER_denom_fee_set_hton (&kv.fees,
                            fees);
  GNUNET_CRYPTO_hash (auditor_url,
                      strlen (auditor_url) + 1,
                      &kv.auditor_url_hash);
  GNUNET_CRYPTO_eddsa_sign (&auditor_priv->eddsa_priv,
                            &kv,
                            &auditor_sig->eddsa_sig);
}


enum GNUNET_GenericReturnValue
TALER_auditor_denom_validity_verify (
  const char *auditor_url,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Timestamp stamp_start,
  struct GNUNET_TIME_Timestamp stamp_expire_withdraw,
  struct GNUNET_TIME_Timestamp stamp_expire_deposit,
  struct GNUNET_TIME_Timestamp stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_DenomFeeSet *fees,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct TALER_AuditorSignatureP *auditor_sig)
{
  struct TALER_ExchangeKeyValidityPS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS),
    .purpose.size = htonl (sizeof (kv)),
    .start = GNUNET_TIME_timestamp_hton (stamp_start),
    .expire_withdraw = GNUNET_TIME_timestamp_hton (stamp_expire_withdraw),
    .expire_deposit = GNUNET_TIME_timestamp_hton (stamp_expire_deposit),
    .expire_legal = GNUNET_TIME_timestamp_hton (stamp_expire_legal),
    .denom_hash = *h_denom_pub,
    .master = *master_pub,
  };

  TALER_amount_hton (&kv.value,
                     coin_value);
  TALER_denom_fee_set_hton (&kv.fees,
                            fees);
  GNUNET_CRYPTO_hash (auditor_url,
                      strlen (auditor_url) + 1,
                      &kv.auditor_url_hash);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS,
                                &kv,
                                &auditor_sig->eddsa_sig,
                                &auditor_pub->eddsa_pub);
}


/* end of auditor_signatures.c */
