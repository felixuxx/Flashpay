/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_common_deposit.c
 * @brief shared logic for handling deposited coins
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler-exchange-httpd_common_deposit.h"
#include "taler-exchange-httpd.h"
#include "taler-exchange-httpd_keys.h"


enum GNUNET_GenericReturnValue
TEH_common_purse_deposit_parse_coin (
  struct MHD_Connection *connection,
  struct TEH_PurseDepositedCoin *coin,
  const json_t *jcoin)
{
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("amount",
                            TEH_currency,
                            &coin->amount),
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &coin->cpi.denom_pub_hash),
    TALER_JSON_spec_denom_sig ("ub_sig",
                               &coin->cpi.denom_sig),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("attest",
                                   &coin->attest),
      &coin->no_attest),
    GNUNET_JSON_spec_mark_optional (
      TALER_JSON_spec_age_commitment ("age_commitment",
                                      &coin->age_commitment),
      &coin->cpi.no_age_commitment),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin->coin_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &coin->cpi.coin_pub),
    GNUNET_JSON_spec_end ()
  };

  memset (coin,
          0,
          sizeof (*coin));
  coin->cpi.no_age_commitment = true;
  coin->no_attest = true;
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     jcoin,
                                     spec);
    if (GNUNET_OK != res)
      return res;
  }

  /* check denomination exists and is valid */
  {
    struct TEH_DenominationKey *dk;
    MHD_RESULT mret;

    dk = TEH_keys_denomination_by_hash (&coin->cpi.denom_pub_hash,
                                        connection,
                                        &mret);
    if (NULL == dk)
    {
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES == mret) ? GNUNET_NO : GNUNET_SYSERR;
    }
    if (! coin->cpi.no_age_commitment)
    {
      coin->age_commitment.mask = dk->meta.age_mask;
      TALER_age_commitment_hash (&coin->age_commitment,
                                 &coin->cpi.h_age_commitment);
    }
    if (0 > TALER_amount_cmp (&dk->meta.value,
                              &coin->amount))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_BAD_REQUEST,
                                          TALER_EC_EXCHANGE_GENERIC_AMOUNT_EXCEEDS_DENOMINATION_VALUE,
                                          NULL))
             ? GNUNET_NO : GNUNET_SYSERR;
    }
    if (GNUNET_TIME_absolute_is_past (dk->meta.expire_deposit.abs_time))
    {
      /* This denomination is past the expiration time for deposits */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TEH_RESPONSE_reply_expired_denom_pub_hash (
                connection,
                &coin->cpi.denom_pub_hash,
                TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
                "PURSE CREATE"))
             ? GNUNET_NO : GNUNET_SYSERR;
    }
    if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
    {
      /* This denomination is not yet valid */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TEH_RESPONSE_reply_expired_denom_pub_hash (
                connection,
                &coin->cpi.denom_pub_hash,
                TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
                "PURSE CREATE"))
             ? GNUNET_NO : GNUNET_SYSERR;
    }
    if (dk->recoup_possible)
    {
      /* This denomination has been revoked */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TEH_RESPONSE_reply_expired_denom_pub_hash (
                connection,
                &coin->cpi.denom_pub_hash,
                TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
                "PURSE CREATE"))
             ? GNUNET_NO : GNUNET_SYSERR;
    }
    if (dk->denom_pub.cipher != coin->cpi.denom_sig.cipher)
    {
      /* denomination cipher and denomination signature cipher not the same */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_BAD_REQUEST,
                                          TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                                          NULL))
             ? GNUNET_NO : GNUNET_SYSERR;
    }

    coin->deposit_fee = dk->meta.fees.deposit;
    if (0 < TALER_amount_cmp (&coin->deposit_fee,
                              &coin->amount))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_DEPOSIT_NEGATIVE_VALUE_AFTER_FEE,
                                         NULL);
    }
    GNUNET_assert (0 <=
                   TALER_amount_subtract (&coin->amount_minus_fee,
                                          &coin->amount,
                                          &coin->deposit_fee));

    /* check coin signature */
    switch (dk->denom_pub.cipher)
    {
    case TALER_DENOMINATION_RSA:
      TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_RSA]++;
      break;
    case TALER_DENOMINATION_CS:
      TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_CS]++;
      break;
    default:
      break;
    }
    if (GNUNET_YES !=
        TALER_test_coin_valid (&coin->cpi,
                               &dk->denom_pub))
    {
      TALER_LOG_WARNING ("Invalid coin passed for /deposit\n");
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_FORBIDDEN,
                                          TALER_EC_EXCHANGE_DENOMINATION_SIGNATURE_INVALID,
                                          NULL))
             ? GNUNET_NO : GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TEH_common_deposit_check_purse_deposit (
  struct MHD_Connection *connection,
  const struct TEH_PurseDepositedCoin *coin,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  uint32_t min_age)
{
  if (GNUNET_OK !=
      TALER_wallet_purse_deposit_verify (TEH_base_url,
                                         purse_pub,
                                         &coin->amount,
                                         &coin->cpi.denom_pub_hash,
                                         &coin->cpi.h_age_commitment,
                                         &coin->cpi.coin_pub,
                                         &coin->coin_sig))
  {
    TALER_LOG_WARNING (
      "Invalid coin signature to deposit into purse\n");
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_FORBIDDEN,
                                        TALER_EC_EXCHANGE_PURSE_DEPOSIT_COIN_SIGNATURE_INVALID,
                                        TEH_base_url))
           ? GNUNET_NO
           : GNUNET_SYSERR;
  }

  if (0 == min_age)
    return GNUNET_OK; /* no need to apply age checks */

  /* Check and verify the age restriction. */
  if (coin->no_attest != coin->cpi.no_age_commitment)
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_PURSE_DEPOSIT_COIN_CONFLICTING_ATTEST_VS_AGE_COMMITMENT,
                                       "mismatch of attest and age_commitment");
  }

  if (coin->cpi.no_age_commitment)
    return GNUNET_OK; /* unrestricted coin */

  /* age attestation must be valid */
  if (GNUNET_OK !=
      TALER_age_commitment_verify (&coin->age_commitment,
                                   min_age,
                                   &coin->attest))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_PURSE_DEPOSIT_COIN_AGE_ATTESTATION_FAILURE,
                                       "invalid attest for minimum age");
  }
  return GNUNET_OK;
}


/**
 * Release data structures of @a coin. Note that
 * @a coin itself is NOT freed.
 *
 * @param[in] coin information to release
 */
void
TEH_common_purse_deposit_free_coin (struct TEH_PurseDepositedCoin *coin)
{
  TALER_denom_sig_free (&coin->cpi.denom_sig);
  if (! coin->cpi.no_age_commitment)
    GNUNET_free (coin->age_commitment.keys); /* Only the keys have been allocated */
}
