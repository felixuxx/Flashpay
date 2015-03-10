/*
  This file is part of TALER
  Copyright (C) 2014 Christian Grothoff (and other contributing authors)

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

#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"

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
 * Signature where the refresh session confirms
 * the commits.
 */
#define TALER_SIGNATURE_REFRESH_MELT_SESSION 6

/**
 * Signature where the mint (current signing key)
 * confirms the no-reveal index for cut-and-choose and
 * the validity of the melted coins.
 */
#define TALER_SIGNATURE_REFRESH_MELT_RESPONSE 7

/**
 * Signature where coins confirm that they want
 * to be melted into a certain session.
 */
#define TALER_SIGNATURE_REFRESH_MELT_CONFIRM 9

/**
 * Signature where the Mint confirms a deposit request.
 */
#define TALER_SIGNATURE_MINT_DEPOSIT 10


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
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;

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
   * Amount to be deposited.
   */
  struct TALER_AmountNBO amount;

  /**
   * The coin's public key.
   */
  struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;

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
   * Amount to be deposited.
   */
  struct TALER_AmountNBO amount;

  /**
   * The coin's public key.
   */
  struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;

  /**
   * The Merchant's public key.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey merchant;

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
   * Which melting operation should the coin become a part of.
   */
  struct GNUNET_HashCode melt_hash;

  /**
   * How much of the value of the coin should be melted?
   * This amount includes the fees, so the final amount contributed
   * to the melt is this value minus the fee for melting the coin.
   */
  struct TALER_AmountNBO amount;

  /**
   * The coin's public key.
   */
  struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;
};


/**
 * Message signed by a coin to indicate that the coin should
 * be melted.
 */
struct RefreshMeltSessionSignature
{
  /**
   * Purpose is #TALER_SIGNATURE_REFRESH_MELT_SESSION
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Which melting operation should the coin become a part of.
   */
  struct GNUNET_HashCode melt_hash;

  /**
   * Public key of the refresh session for which
   * @e melt_client_signature must be a valid signature.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey session_key;

  /**
   * What is the total value of the coins created during the
   * refresh, excluding fees?
   */
  struct TALER_AmountNBO amount;
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
 * Message signed by the client requesting the final
 * result of the melting operation.
 */
struct RefreshMeltConfirmSignRequestBody
{
  /**
   * Purpose is #TALER_SIGNATURE_REFRESH_MELT_CONFIRM.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * FIXME.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;
};


/**
 * FIXME
 */
struct TALER_MINT_SignKeyIssue
{
  struct GNUNET_CRYPTO_EddsaSignature signature;
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_CRYPTO_EddsaPublicKey master_pub;
  struct GNUNET_TIME_AbsoluteNBO start;
  struct GNUNET_TIME_AbsoluteNBO expire;
  struct GNUNET_CRYPTO_EddsaPublicKey signkey_pub;
};


/**
 * FIXME
 */
struct TALER_MINT_DenomKeyIssue
{
  struct GNUNET_CRYPTO_EddsaSignature signature;
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_CRYPTO_EddsaPublicKey master;
  struct GNUNET_TIME_AbsoluteNBO start;
  struct GNUNET_TIME_AbsoluteNBO expire_withdraw;
  struct GNUNET_TIME_AbsoluteNBO expire_spend;
  // FIXME: does not work like this:
  struct GNUNET_CRYPTO_rsa_PublicKey * denom_pub;
  struct TALER_AmountNBO value;
  struct TALER_AmountNBO fee_withdraw;
  struct TALER_AmountNBO fee_deposit;
  struct TALER_AmountNBO fee_refresh;
};



GNUNET_NETWORK_STRUCT_END

#endif
