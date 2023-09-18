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
 * @file lib/exchange_api_common.h
 * @brief common functions for the exchange API
 * @author Christian Grothoff
 */
#ifndef EXCHANGE_API_COMMON_H
#define EXCHANGE_API_COMMON_H

#include "taler_json_lib.h"
#include "taler_exchange_service.h"


/**
 * Check proof of a purse creation conflict.
 *
 * @param cpurse_sig conflicting signature (must
 *        not match the signature from the proof)
 * @param purse_pub the public key (must match
 *        the signature from the proof)
 * @param proof the proof to check
 * @return #GNUNET_OK if the @a proof is OK for @a purse_pub and conflicts with @a cpurse_sig
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_create_conflict_ (
  const struct TALER_PurseContractSignatureP *cpurse_sig,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *proof);


/**
 * Check proof of a purse merge conflict.
 *
 * @param cmerge_sig conflicting signature (must
 *        not match the signature from the proof)
 * @param merge_pub the public key (must match
 *        the signature from the proof)
 * @param purse_pub the public key of the purse
 * @param exchange_url the base URL of this exchange
 * @param proof the proof to check
 * @return #GNUNET_OK if the @a proof is OK for @a purse_pub and @a merge_pub and conflicts with @a cmerge_sig
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_merge_conflict_ (
  const struct TALER_PurseMergeSignatureP *cmerge_sig,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const char *exchange_url,
  const json_t *proof);


/**
 * Check @a proof that claims this coin was spend
 * differently on the same purse already. Note that
 * the caller must still check that @a coin_pub is
 * in the list of coins that were used, and that
 * @a coin_sig is different from the signature the
 * caller used.
 *
 * @param purse_pub the public key of the purse
 * @param exchange_url base URL of our exchange
 * @param proof the proof to check
 * @param[out] h_denom_pub hash of the coin's denomination
 * @param[out] phac age commitment hash of the coin
 * @param[out] coin_pub set to the conflicting coin
 * @param[out] coin_sig set to the conflicting signature
 * @return #GNUNET_OK if the @a proof is OK for @a purse_pub and showing that @a coin_pub was spent using @a coin_sig.
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_coin_conflict_ (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const char *exchange_url,
  const json_t *proof,
  struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_AgeCommitmentHash *phac,
  struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Check proof of a contract conflict.
 *
 * @param ccontract_sig conflicting signature (must
 *        not match the signature from the proof)
 * @param purse_pub public key of the purse
 * @param proof the proof to check
 * @return #GNUNET_OK if the @a proof is OK for @a purse_pub and conflicts with @a ccontract_sig
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_econtract_conflict_ (
  const struct TALER_PurseContractSignatureP *ccontract_sig,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *proof);


/**
 * Check proof of a coin spend value conflict.
 *
 * @param keys exchange /keys structure
 * @param proof the proof to check
 * @param[out] coin_pub set to the public key of the
 *        coin that is claimed to have an insufficient
 *        balance
 * @param[out] remaining set to the remaining balance
 *        of the coin as provided by the proof
 * @return #GNUNET_OK if the @a proof is OK for @a purse_pub demonstrating that @a coin_pub has only @a remaining balance.
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_coin_amount_conflict_ (
  const struct TALER_EXCHANGE_Keys *keys,
  const json_t *proof,
  struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_Amount *remaining);


/**
 * Verify that @a proof contains a coin history that demonstrates that @a
 * coin_pub was previously used with a denomination key that is different from
 * @a ch_denom_pub.  Note that the coin history MUST have been checked before
 * using #TALER_EXCHANGE_check_coin_amount_conflict_().
 *
 * @param proof a proof to check
 * @param ch_denom_pub hash of the conflicting denomination
 * @return #GNUNET_OK if @a ch_denom_pub differs from the
 *         denomination hash given by the history of the coin
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_coin_denomination_conflict_ (
  const json_t *proof,
  const struct TALER_DenominationHashP *ch_denom_pub);


/**
 * Find the smallest denomination amount in @e keys.
 *
 * @param keys keys to search
 * @param[out] min set to the smallest amount
 * @return #GNUNET_SYSERR if there are no denominations in @a keys
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_get_min_denomination_ (
  const struct TALER_EXCHANGE_Keys *keys,
  struct TALER_Amount *min);


/**
 * Verify signature information about the deposit.
 *
 * @param dcd contract details
 * @param ech hashed policy (passed to avoid recomputation)
 * @param h_wire hashed wire details (passed to avoid recomputation)
 * @param cdd coin-specific details
 * @param dki denomination of the coin
 * @return #GNUNET_OK if signatures are OK, #GNUNET_SYSERR if not
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_verify_deposit_signature_ (
  const struct TALER_EXCHANGE_DepositContractDetail *dcd,
  const struct TALER_ExtensionPolicyHashP *ech,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_EXCHANGE_CoinDepositDetail *cdd,
  const struct TALER_EXCHANGE_DenomPublicKey *dki);


#endif
