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
 * @file taler-exchange-httpd_common_deposit.h
 * @brief shared logic for handling deposited coins
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_COMMON_DEPOSIT_H
#define TALER_EXCHANGE_HTTPD_COMMON_DEPOSIT_H

#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"


/**
 * Information about an individual coin being deposited.
 */
struct TEH_PurseDepositedCoin
{
  /**
   * Public information about the coin.
   */
  struct TALER_CoinPublicInfo cpi;

  /**
   * Signature affirming spending the coin.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Amount to be put into the purse from this coin.
   */
  struct TALER_Amount amount;

  /**
   * Deposit fee applicable for this coin.
   */
  struct TALER_Amount deposit_fee;

  /**
   * Amount to be put into the purse from this coin.
   */
  struct TALER_Amount amount_minus_fee;

  /**
   * Age attestation provided, set if @e no_attest is false.
   */
  struct TALER_AgeAttestation attest;

  /**
   * Age commitment provided, set if @e cpi.no_age_commitment is false.
   */
  struct TALER_AgeCommitment age_commitment;

  /**
   * ID of the coin in known_coins.
   */
  uint64_t known_coin_id;

  /**
   * True if @e attest was not provided.
   */
  bool no_attest;

};


/**
 * Parse a coin and check signature of the coin and the denomination
 * signature over the coin.
 *
 * @param[in,out] connection our HTTP connection
 * @param[out] coin coin to initialize
 * @param jcoin coin to parse
 * @return #GNUNET_OK on success, #GNUNET_NO if an error was returned,
 *         #GNUNET_SYSERR on failure and no error could be returned
 */
enum GNUNET_GenericReturnValue
TEH_common_purse_deposit_parse_coin (
  struct MHD_Connection *connection,
  struct TEH_PurseDepositedCoin *coin,
  const json_t *jcoin);


/**
 * Check that the deposited @a coin is valid for @a purse_pub
 * and has a valid age commitment for @a min_age.
 *
 * @param[in,out] connection our HTTP connection
 * @param coin the coin to evaluate
 * @param purse_pub public key of the purse the coin was deposited into
 * @param min_age minimum age restriction expected for this purse
 * @return #GNUNET_OK on success, #GNUNET_NO if an error was returned,
 *         #GNUNET_SYSERR on failure and no error could be returned
 */
enum GNUNET_GenericReturnValue
TEH_common_deposit_check_purse_deposit (
  struct MHD_Connection *connection,
  const struct TEH_PurseDepositedCoin *coin,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  uint32_t min_age);


/**
 * Release data structures of @a coin. Note that
 * @a coin itself is NOT freed.
 *
 * @param[in] coin information to release
 */
void
TEH_common_purse_deposit_free_coin (struct TEH_PurseDepositedCoin *coin);

#endif
