/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

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
#include "taler_rsa.h"


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
 * Signature where the refresh session confirms
 * the list of melted coins and requested denominations.
 */
#define TALER_SIGNATURE_REFRESH_MELT 5

/**
 * Signature where the refresh session confirms
 * the commits.
 */
#define TALER_SIGNATURE_REFRESH_COMMIT 6

/**
 * Signature where the mint (current signing key)
 * confirms the list of blind session keys.
 */
#define TALER_SIGNATURE_REFRESH_MELT_RESPONSE 7

/**
 * Signature where the mint (current signing key)
 * confirms the no-reveal index for cut-and-choose.
 */
#define TALER_SIGNATURE_REFRESH_COMMIT_RESPONSE 8

/**
 * Signature where coins confirm that they want
 * to be melted into a certain session.
 */
#define TALER_SIGNATURE_REFRESH_MELT_CONFIRM 9

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
#define TALER_SIGNATURE_DEPOSIT 201

/**
 * Signature made by the wallet of a user to confirm a incremental deposit permission
 */
#define TALER_SIGNATURE_INCREMENTAL_DEPOSIT 202



GNUNET_NETWORK_STRUCT_BEGIN


/**
 * Request to withdraw coins from a reserve.
 */
struct TALER_WithdrawRequest
{
  /**
   * Signature over the rest of the message
   * by the withdraw public key.
   */
  struct GNUNET_CRYPTO_EddsaSignature sig;

  /**
   * Purpose must be #TALER_SIGNATURE_WITHDRAW.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Reserve public key.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;

  /**
   * Denomination public key for the coin that is withdrawn.
   * FIXME: change to the hash of the public key (so this
   * is fixed-size).
   */
  struct TALER_RSA_PublicKeyBinaryEncoded denomination_pub;

  /**
   * Purpose containing coin's blinded public key.
   *
   * FIXME: this should be explicitly a variable-size field with the
   * (blinded) message to be signed by the Mint.
   */
  struct TALER_RSA_BlindedSignaturePurpose coin_envelope;
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
  struct TALER_RSA_PublicKeyBinaryEncoded denom_pub;
  struct TALER_AmountNBO value;
  struct TALER_AmountNBO fee_withdraw;
  struct TALER_AmountNBO fee_deposit;
  struct TALER_AmountNBO fee_refresh;
};


/**
 * FIXME
 */
struct RefreshMeltSignatureBody
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_HashCode melt_hash;
};

/**
 * FIXME
 */
struct RefreshCommitSignatureBody
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_HashCode commit_hash;
};


/**
 * FIXME
 */
struct RefreshCommitResponseSignatureBody
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  uint16_t noreveal_index;
};


/**
 * FIXME
 */
struct RefreshMeltResponseSignatureBody
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_HashCode melt_response_hash;
};


/**
 * FIXME
 */
struct RefreshMeltConfirmSignRequestBody
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;
};


GNUNET_NETWORK_STRUCT_END

#endif

