/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file taler_signatures.h
 * @brief message formats and signature constants used to define
 *        the binary formats of signatures in Taler
 * @author Florian Dold
 * @author Benedikt Mueller
 *
 * This file should define the constants and C structs that one
 * needs to know to implement Taler clients (wallets or merchants)
 * that need to produce or verify Taler signatures.
 */

#ifndef TALER_SIGNATURES_H
#define TALER_SIGNATURES_H

#include "taler_util.h"

/**
 * Cut-and-choose size for refreshing.  Client looses the gamble (of
 * unaccountable transfers) with probability 1/KAPPA.  Refresh cost
 * increases linearly with KAPPA, and 3 is sufficient up to a
 * income/sales tax of 66% of total transaction value.  As there is
 * no good reason to change this security parameter, we declare it
 * fixed and part of the protocol.
 */
#define KAPPA 3


/**
 * Purpose for signing public keys signed
 * by the mint master key.
 */
#define TALER_SIGNATURE_MASTER_SIGNKEY 1

/**
 * Purpose for denomination keys signed
 * by the mint master key.
 */
#define TALER_SIGNATURE_MASTER_DENOM 2

/**
 * Purpose for the state of a reserve,
 * signed by the mint's signing key.
 */
#define TALER_SIGNATURE_RESERVE_STATUS 3

/**
 * Signature where the reserve key
 * confirms a withdraw request.
 */
#define TALER_SIGNATURE_WITHDRAW 4

/**
 * Signature using a coin key confirming the melting of
 * a coin.
 */
#define TALER_SIGNATURE_REFRESH_MELT_COIN 5

/**
 * Signature where the mint (current signing key)
 * confirms the no-reveal index for cut-and-choose and
 * the validity of the melted coins.
 */
#define TALER_SIGNATURE_REFRESH_MELT_RESPONSE 6

/**
 * Signature where the Mint confirms a deposit request.
 */
#define TALER_SIGNATURE_MINT_DEPOSIT 7


/***********************/
/* Merchant signatures */
/***********************/

/**
 * Signature where the merchant confirms a contract
 */
#define TALER_SIGNATURE_MERCHANT_CONTRACT 101

/*********************/
/* Wallet signatures */
/*********************/

/**
 * Signature made by the wallet of a user to confirm a deposit permission
 */
#define TALER_SIGNATURE_WALLET_DEPOSIT 201

/**
 * Signature made by the wallet of a user to confirm a incremental deposit permission
 */
#define TALER_SIGNATURE_INCREMENTAL_WALLET_DEPOSIT 202



GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Format used for to generate the signature on a request to withdraw
 * coins from a reserve.
 */
struct TALER_WithdrawRequest
{

  /**
   * Purpose must be #TALER_SIGNATURE_WITHDRAW.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Reserve public key (which reserve to withdraw from).  This is
   * the public key which must match the signature.
   */
  struct TALER_ReservePublicKey reserve_pub;

  /**
   * Value of the coin being minted (matching the denomination key)
   * plus the transaction fee.  We include this in what is being
   * signed so that we can verify a reserve's remaining total balance
   * without needing to access the respective denomination key
   * information each time.
   */
  struct TALER_AmountNBO amount_with_fee;

  /**
   * Hash of the denomination public key for the coin that is withdrawn.
   */
  struct GNUNET_HashCode h_denomination_pub;

  /**
   * Hash of the (blinded) message to be signed by the Mint.
   */
  struct GNUNET_HashCode h_coin_envelope;
};


/**
 * Format used to generate the signature on a request to deposit
 * a coin into the account of a merchant.
 */
struct TALER_DepositRequest
{
  /**
   * Purpose must be #TALER_SIGNATURE_WALLET_DEPOSIT
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct GNUNET_HashCode h_contract;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Merchant-generated transaction ID to detect duplicate
   * transactions.
   */
  uint64_t transaction_id GNUNET_PACKED;

  /**
   * Amount to be deposited, including fee.
   */
  struct TALER_AmountNBO amount_with_fee;
  /* FIXME: we should probably also include the value of
     the depositing fee here as well! */

  /**
   * The coin's public key.
   */
  struct TALER_CoinSpendPublicKey coin_pub;

};


/**
 * Format used to generate the signature on a confirmation
 * from the mint that a deposit request succeeded.
 */
struct TALER_DepositConfirmation
{
  /**
   * Purpose must be #TALER_SIGNATURE_MINT_DEPOSIT
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct GNUNET_HashCode h_contract;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Merchant-generated transaction ID to detect duplicate
   * transactions.
   */
  uint64_t transaction_id GNUNET_PACKED;

  /**
   * Amount to be deposited, including fee.
   */
  struct TALER_AmountNBO amount_with_fee;

  /* FIXME: we should probably also include the value of
     the depositing fee here as well! */

  /**
   * The coin's public key.
   */
  struct TALER_CoinSpendPublicKey coin_pub;

  /**
   * The Merchant's public key.
   */
  struct TALER_MerchantPublicKey merchant;

};


/**
 * Message signed by a coin to indicate that the coin should
 * be melted.
 */
struct RefreshMeltCoinSignature
{
  /**
   * Purpose is #TALER_SIGNATURE_REFRESH_MELT_COIN.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Which melting session should the coin become a part of.
   */
  struct GNUNET_HashCode session_hash;

  /**
   * How much of the value of the coin should be melted?  This amount
   * includes the fees, so the final amount contributed to the melt is
   * this value minus the fee for melting the coin.  We include the
   * fee in what is being signed so that we can verify a reserve's
   * remaining total balance without needing to access the respective
   * denomination key information each time.
   */
  struct TALER_AmountNBO amount_with_fee;

  /* FIXME: we should probably also include the value of
     the melting fee here as well! */

  /**
   * The coin's public key.
   */
  struct TALER_CoinSpendPublicKey coin_pub;
};


/**
 * Format of the block signed by the Mint in response to a successful
 * "/refresh/melt" request.  Hereby the mint affirms that all of the
 * coins were successfully melted.  This also commits the mint to a
 * particular index to not be revealed during the refresh.
 */
struct RefreshMeltResponseSignatureBody
{
  /**
   * Purpose is #TALER_SIGNATURE_REFRESH_MELT_RESPONSE.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the refresh session.
   */
  struct GNUNET_HashCode session_hash;

  /**
   * Index that the client will not have to reveal.
   */
  uint16_t noreveal_index GNUNET_PACKED;
};


/**
 * Information about a signing key of the mint.  Signing keys are used
 * to sign mint messages other than coins, i.e. to confirm that a
 * deposit was successful or that a refresh was accepted.
 */
struct TALER_MINT_SignKeyIssue
{
  /**
   * Signature over the signing key (by the master key of the mint).
   */
  struct TALER_MasterSignature signature;

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_SIGNKEY.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Master public key of the mint corresponding to @e signature.
   * This is the long-term offline master key of the mint.
   */
  struct TALER_MasterPublicKey master_pub;

  /**
   * When does this signing key begin to be valid?
   */
  struct GNUNET_TIME_AbsoluteNBO start;

  /**
   * When does this signing key expire? Note: This is
   * currently when the Mint will definitively stop using it.
   * This does not mean that all signatures with tkey key are
   * afterwards invalid.
   */
  struct GNUNET_TIME_AbsoluteNBO expire;

  /**
   * The public online signing key that the mint will use
   * between @e start and @e expire.
   */
  struct TALER_MintPublicKey signkey_pub;
};


/**
 * Information about a denomination key. Denomination keys
 * are used to sign coins of a certain value into existence.
 */
struct TALER_MINT_DenomKeyIssue
{
  /**
   * Signature over this struct to affirm the validity
   * of the key.
   */
  struct TALER_MasterSignature signature;

  /**
   * Purpose ist #TALER_SIGNATURE_MASTER_DENOM.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * The long-term offline master key of the mint that was
   * used to create @e signature.
   */
  struct TALER_MasterPublicKey master;

  /**
   * Start time of the validity period for this key.
   */
  struct GNUNET_TIME_AbsoluteNBO start;

  /**
   * The mint will sign fresh coins between @e start and
   * this time.
   */
  struct GNUNET_TIME_AbsoluteNBO expire_withdraw;

  /**
   * Coins signed with the denomination key must be spent or refreshed
   * between @e start and this expiration time.  After this time, the
   * mint will refuse transactions involving this key as it will
   * "drop" the table with double-spending information (shortly after)
   * this time.  Note that wallets should refresh coins significantly
   * before this time to be on the safe side.
   */
  struct GNUNET_TIME_AbsoluteNBO expire_spend;

  /**
   * The value of the coins signed with this denomination key.
   */
  struct TALER_AmountNBO value;

  /**
   * The fee the mint charges when a coin of this type is withdrawn.
   * (can be zero).
   */
  struct TALER_AmountNBO fee_withdraw;

  /**
   * The fee the mint charges when a coin of this type is deposited.
   * (can be zero).
   */
  struct TALER_AmountNBO fee_deposit;

  /**
   * The fee the mint charges when a coin of this type is refreshed.
   * (can be zero).
   */
  struct TALER_AmountNBO fee_refresh;

  /**
   * Hash code of the denomination public key.
   */
  struct GNUNET_HashCode denom_hash;

};

GNUNET_NETWORK_STRUCT_END

#endif
