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
 * @file auditor_signatures.c
 * @brief Utility functions for Taler auditor signatures
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


void
TALER_auditor_denom_validity_sign (
  const char *auditor_url,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Absolute stamp_start,
  struct GNUNET_TIME_Absolute stamp_expire_withdraw,
  struct GNUNET_TIME_Absolute stamp_expire_deposit,
  struct GNUNET_TIME_Absolute stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *fee_withdraw,
  const struct TALER_Amount *fee_deposit,
  const struct TALER_Amount *fee_refresh,
  const struct TALER_Amount *fee_refund,
  const struct TALER_AuditorPrivateKeyP *auditor_priv,
  struct TALER_AuditorSignatureP *auditor_sig)
{
  struct TALER_ExchangeKeyValidityPS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS),
    .purpose.size = htonl (sizeof (kv)),
    .start = GNUNET_TIME_absolute_hton (stamp_start),
    .expire_withdraw = GNUNET_TIME_absolute_hton (stamp_expire_withdraw),
    .expire_deposit = GNUNET_TIME_absolute_hton (stamp_expire_deposit),
    .expire_legal = GNUNET_TIME_absolute_hton (stamp_expire_legal),
    .denom_hash = *h_denom_pub,
    .master = *master_pub,
  };

  TALER_amount_hton (&kv.value,
                     coin_value);
  TALER_amount_hton (&kv.fee_withdraw,
                     fee_withdraw);
  TALER_amount_hton (&kv.fee_deposit,
                     fee_deposit);
  TALER_amount_hton (&kv.fee_refresh,
                     fee_refresh);
  TALER_amount_hton (&kv.fee_refund,
                     fee_refund);
  GNUNET_CRYPTO_hash (auditor_url,
                      strlen (auditor_url) + 1,
                      &kv.auditor_url_hash);
  GNUNET_CRYPTO_eddsa_sign (&auditor_priv->eddsa_priv,
                            &kv,
                            &auditor_sig->eddsa_sig);
}


int
TALER_auditor_denom_validity_verify (
  const char *auditor_url,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Absolute stamp_start,
  struct GNUNET_TIME_Absolute stamp_expire_withdraw,
  struct GNUNET_TIME_Absolute stamp_expire_deposit,
  struct GNUNET_TIME_Absolute stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *fee_withdraw,
  const struct TALER_Amount *fee_deposit,
  const struct TALER_Amount *fee_refresh,
  const struct TALER_Amount *fee_refund,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct TALER_AuditorSignatureP *auditor_sig)
{
  struct TALER_ExchangeKeyValidityPS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS),
    .purpose.size = htonl (sizeof (kv)),
    .start = GNUNET_TIME_absolute_hton (stamp_start),
    .expire_withdraw = GNUNET_TIME_absolute_hton (stamp_expire_withdraw),
    .expire_deposit = GNUNET_TIME_absolute_hton (stamp_expire_deposit),
    .expire_legal = GNUNET_TIME_absolute_hton (stamp_expire_legal),
    .denom_hash = *h_denom_pub,
    .master = *master_pub,
  };

  TALER_amount_hton (&kv.value,
                     coin_value);
  TALER_amount_hton (&kv.fee_withdraw,
                     fee_withdraw);
  TALER_amount_hton (&kv.fee_deposit,
                     fee_deposit);
  TALER_amount_hton (&kv.fee_refresh,
                     fee_refresh);
  TALER_amount_hton (&kv.fee_refund,
                     fee_refund);
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
