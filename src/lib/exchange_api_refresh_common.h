/*
  This file is part of TALER
  Copyright (C) 2015-2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_refresh_common.h
 * @brief shared (serialization) logic for refresh protocol
 * @author Christian Grothoff
 */
#ifndef REFRESH_COMMON_H
#define REFRESH_COMMON_H
#include <jansson.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "taler_signatures.h"


/**
 * Information about a coin we are melting.
 */
struct MeltedCoin
{
  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Amount this coin contributes to the melt, including fee.
   */
  struct TALER_Amount melt_amount_with_fee;

  /**
   * The applicable fee for melting a coin of this denomination
   */
  struct TALER_Amount fee_melt;

  /**
   * The original value of the coin.
   */
  struct TALER_Amount original_value;

  /**
   * The original age commitment, its proof and its hash.  MUST be NULL if no
   * age commitment was set.
   */
  const struct TALER_AgeCommitmentProof *age_commitment_proof;
  const struct TALER_AgeCommitmentHash *h_age_commitment;

  /**
   * Timestamp indicating when coins of this denomination become invalid.
   */
  struct GNUNET_TIME_Timestamp expire_deposit;

  /**
   * Denomination key of the original coin.
   */
  struct TALER_DenominationPublicKey pub_key;

  /**
   * Exchange's signature over the coin.
   */
  struct TALER_DenominationSignature sig;

};


/**
 * Data we keep for each fresh coin created in the
 * melt process.
 */
struct FreshCoinData
{
  /**
   * Denomination public key of the coin.
   */
  struct TALER_DenominationPublicKey fresh_pk;

  /**
   * Array of planchet secrets for the coins, depending
   * on the cut-and-choose.
   */
  struct TALER_PlanchetMasterSecretP ps[TALER_CNC_KAPPA];

  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Arrays of age commitments and proofs to be created, one for each
   * cut-and-choose dimension.  NULL if age restriction is not applicable.
   */
  struct TALER_AgeCommitmentProof *age_commitment_proofs[TALER_CNC_KAPPA];

  /**
   * Blinding key secrets for the coins, depending on the
   * cut-and-choose.
   */
  union GNUNET_CRYPTO_BlindingSecretP bks[TALER_CNC_KAPPA];

};


/**
 * Melt data in non-serialized format for convenient processing.
 */
struct MeltData
{

  /**
   * Hash over the committed data during refresh operation.
   */
  struct TALER_RefreshCommitmentP rc;

  /**
   * Information about the melted coin.
   */
  struct MeltedCoin melted_coin;

  /**
   * Array of length @e num_fresh_coins with information
   * about each fresh coin.
   */
  struct FreshCoinData *fcds;

  /**
   * Transfer secrets, one per cut and choose.
   */
  struct TALER_TransferSecretP trans_sec[TALER_CNC_KAPPA];

  /**
   * Transfer private keys for each cut-and-choose dimension.
   */
  struct TALER_TransferPrivateKeyP transfer_priv[TALER_CNC_KAPPA];

  /**
   * Transfer public key of this commitment.
   */
  struct TALER_TransferPublicKeyP transfer_pub[TALER_CNC_KAPPA];

  /**
   * Transfer secrets, one per cut and choose.
   */
  struct TALER_RefreshCommitmentEntry rce[TALER_CNC_KAPPA];

  /**
   * Blinded planchets and denominations of the fresh coins, depending on the cut-and-choose.  Array of length
   * @e num_fresh_coins.
   */
  struct TALER_RefreshCoinData *rcd[TALER_CNC_KAPPA];

  /**
   * Number of coins we are creating
   */
  uint16_t num_fresh_coins;

};


/**
 * Compute the melt data from the refresh data and secret.
 *
 * @param rms secret internals of the refresh-reveal operation
 * @param rd refresh data with the characteristics of the operation
 * @param alg_values contributions from the exchange into the melt
 * @param[out] md where to write the derived melt data
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_get_melt_data_ (
  const struct TALER_RefreshMasterSecretP *rms,
  const struct TALER_EXCHANGE_RefreshData *rd,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  struct MeltData *md);


/**
 * Free all information associated with a melting session.  Note
 * that we allow the melting session to be only partially initialized,
 * as we use this function also when freeing melt data that was not
 * fully initialized.
 *
 * @param[in] md melting data to release, the pointer itself is NOT
 *           freed (as it is typically not allocated by itself)
 */
void
TALER_EXCHANGE_free_melt_data_ (struct MeltData *md);

#endif
