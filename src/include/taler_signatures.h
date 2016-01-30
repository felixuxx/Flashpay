/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V.

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
 * This file should define the constants and C structs that one needs
 * to know to implement Taler clients (wallets or merchants or
 * auditor) that need to produce or verify Taler signatures.
 */

#ifndef TALER_SIGNATURES_H
#define TALER_SIGNATURES_H

#if HAVE_GNUNET_GNUNET_UTIL_LIB_H
#include <gnunet/gnunet_util_lib.h>
#elif HAVE_GNUNET_GNUNET_UTIL_TALER_WALLET_LIB_H
#include <gnunet/gnunet_util_taler_wallet_lib.h>
#endif

#include "taler_amount_lib.h"
#include "taler_crypto_lib.h"

/**
 * Cut-and-choose size for refreshing.  Client looses the gamble (of
 * unaccountable transfers) with probability 1/TALER_CNC_KAPPA.  Refresh cost
 * increases linearly with TALER_CNC_KAPPA, and 3 is sufficient up to a
 * income/sales tax of 66% of total transaction value.  As there is
 * no good reason to change this security parameter, we declare it
 * fixed and part of the protocol.
 */
#define TALER_CNC_KAPPA 3

/**
 * After what time do idle reserves "expire"?  We might want to make
 * this a configuration option (eventually).
 */
#define TALER_IDLE_RESERVE_EXPIRATION_TIME GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_YEARS, 5)

/*********************************************/
/* Mint offline signatures (with master key) */
/*********************************************/

/**
 * Purpose for signing public keys signed by the mint master key.
 */
#define TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY 1024

/**
 * Purpose for denomination keys signed by the mint master key.
 */
#define TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY 1025

/**
 * Signature where the Mint confirms its SEPA details in
 * the /wire/sepa response.
 */
#define TALER_SIGNATURE_MASTER_SEPA_DETAILS 1026


/*********************************************/
/* Mint online signatures (with signing key) */
/*********************************************/

/**
 * Purpose for the state of a reserve, signed by the mint's signing
 * key.
 */
#define TALER_SIGNATURE_MINT_RESERVE_STATUS 1032

/**
 * Signature where the Mint confirms a deposit request.
 */
#define TALER_SIGNATURE_MINT_CONFIRM_DEPOSIT 1033

/**
 * Signature where the mint (current signing key) confirms the
 * no-reveal index for cut-and-choose and the validity of the melted
 * coins.
 */
#define TALER_SIGNATURE_MINT_CONFIRM_MELT 1034

/**
 * Signature where the Mint confirms the full /keys response set.
 */
#define TALER_SIGNATURE_MINT_KEY_SET 1035

/**
 * Signature where the Mint confirms the /wire response.
 */
#define TALER_SIGNATURE_MINT_WIRE_TYPES 1036

/**
 * Signature where the Mint confirms the /deposit/wtid response.
 */
#define TALER_SIGNATURE_MINT_CONFIRM_WIRE 1036


/*********************/
/* Wallet signatures */
/*********************/

/**
 * Signature where the auditor confirms that he is
 * aware of certain denomination keys from the mint.
 */
#define TALER_SIGNATURE_AUDITOR_MINT_KEYS 1064


/***********************/
/* Merchant signatures */
/***********************/

/**
 * Signature where the merchant confirms a contract (to the customer).
 */
#define TALER_SIGNATURE_MERCHANT_CONTRACT 1101

/**
 * Signature where the merchant confirms a refund (of a coin).
 */
#define TALER_SIGNATURE_MERCHANT_REFUND 1102

/**
 * Signature where the merchant confirms that he needs the wire
 * transfer identifier for a deposit operation.
 */
#define TALER_SIGNATURE_MERCHANT_DEPOSIT_WTID 1103


/*********************/
/* Wallet signatures */
/*********************/

/**
 * Signature where the reserve key confirms a withdraw request.
 */
#define TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW 1200

/**
 * Signature made by the wallet of a user to confirm a deposit of a coin.
 */
#define TALER_SIGNATURE_WALLET_COIN_DEPOSIT 1201

/**
 * Signature using a coin key confirming the melting of a coin.
 */
#define TALER_SIGNATURE_WALLET_COIN_MELT 1202


/*******************/
/* Test signatures */
/*******************/

/**
 * EdDSA test signature.
 */
#define TALER_SIGNATURE_CLIENT_TEST_EDDSA 1302

/**
 * EdDSA test signature.
 */
#define TALER_SIGNATURE_MINT_TEST_EDDSA 1303



GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Format used for to generate the signature on a request to withdraw
 * coins from a reserve.
 */
struct TALER_WithdrawRequestPS
{

  /**
   * Purpose must be #TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW.
   * Used with an EdDSA signature of a `struct TALER_ReservePublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Reserve public key (which reserve to withdraw from).  This is
   * the public key which must match the signature.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Value of the coin being minted (matching the denomination key)
   * plus the transaction fee.  We include this in what is being
   * signed so that we can verify a reserve's remaining total balance
   * without needing to access the respective denomination key
   * information each time.
   */
  struct TALER_AmountNBO amount_with_fee;

  /**
   * Withdrawl fee charged by the mint.  This must match the Mint's
   * denomination key's withdrawl fee.  If the client puts in an
   * invalid withdrawl fee (too high or too low) that does not match
   * the Mint's denomination key, the withdraw operation is invalid
   * and will be rejected by the mint.  The @e amount_with_fee minus
   * the @e withdraw_fee is must match the value of the generated
   * coin.  We include this in what is being signed so that we can
   * verify a mint's accounting without needing to access the
   * respective denomination key information each time.
   */
  struct TALER_AmountNBO withdraw_fee;

  /**
   * Hash of the denomination public key for the coin that is withdrawn.
   */
  struct GNUNET_HashCode h_denomination_pub GNUNET_PACKED;

  /**
   * Hash of the (blinded) message to be signed by the Mint.
   */
  struct GNUNET_HashCode h_coin_envelope GNUNET_PACKED;
};


/**
 * @brief Format used to generate the signature on a request to deposit
 * a coin into the account of a merchant.
 */
struct TALER_DepositRequestPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_WALLET_COIN_DEPOSIT.
   * Used for an EdDSA signature with the `struct TALER_CoinSpendPublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct GNUNET_HashCode h_contract GNUNET_PACKED;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire GNUNET_PACKED;

  /**
   * Time when this request was generated.  Used, for example, to
   * assess when (roughly) the income was achieved for tax purposes.
   * Note that the Mint will only check that the timestamp is not "too
   * far" into the future (i.e. several days).  The fact that the
   * timestamp falls within the validity period of the coin's
   * denomination key is irrelevant for the validity of the deposit
   * request, as obviously the customer and merchant could conspire to
   * set any timestamp.  Also, the Mint must accept very old deposit
   * requests, as the merchant might have been unable to transmit the
   * deposit request in a timely fashion (so back-dating is not
   * prevented).
   */
  struct GNUNET_TIME_AbsoluteNBO timestamp;

  /**
   * How much time does the merchant have to issue a refund request?
   * Zero if refunds are not allowed.  After this time, the coin
   * cannot be refunded.
   */
  struct GNUNET_TIME_AbsoluteNBO refund_deadline;

  /**
   * Merchant-generated transaction ID to detect duplicate
   * transactions.  The merchant must communicate a merchant-unique ID
   * to the customer for each transaction.  Note that different coins
   * that are part of the same transaction can use the same
   * transaction ID.  The transaction ID is useful for later disputes,
   * and the merchant's contract offer (@e h_contract) with the
   * customer should include the offer's term and transaction ID
   * signed with a key from the merchant.
   */
  uint64_t transaction_id GNUNET_PACKED;

  /**
   * Amount to be deposited, including deposit fee charged by the
   * mint.  This is the total amount that the coin's value at the mint
   * will be reduced by.
   */
  struct TALER_AmountNBO amount_with_fee;

  /**
   * Depositing fee charged by the mint.  This must match the Mint's
   * denomination key's depositing fee.  If the client puts in an
   * invalid deposit fee (too high or too low) that does not match the
   * Mint's denomination key, the deposit operation is invalid and
   * will be rejected by the mint.  The @e amount_with_fee minus the
   * @e deposit_fee is the amount that will be transferred to the
   * account identified by @e h_wire.
   */
  struct TALER_AmountNBO deposit_fee;

  /**
   * The Merchant's public key.  Allows the merchant to later refund
   * the transaction or to inquire about the wire transfer identifier.
   */
  struct TALER_MerchantPublicKeyP merchant;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Mint.  The deposit request is to be
   * signed by the corresponding private key (using EdDSA).
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

};


/**
 * @brief Format used to generate the signature on a confirmation
 * from the mint that a deposit request succeeded.
 */
struct TALER_DepositConfirmationPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_MINT_CONFIRM_DEPOSIT.  Signed
   * by a `struct TALER_MintPublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct GNUNET_HashCode h_contract GNUNET_PACKED;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire GNUNET_PACKED;

  /**
   * Merchant-generated transaction ID to detect duplicate
   * transactions.
   */
  uint64_t transaction_id GNUNET_PACKED;

  /**
   * Time when this confirmation was generated.
   */
  struct GNUNET_TIME_AbsoluteNBO timestamp;

  /**
   * How much time does the @e merchant have to issue a refund
   * request?  Zero if refunds are not allowed.  After this time, the
   * coin cannot be refunded.  Note that the wire transfer will not be
   * performed by the mint until the refund deadline.  This value
   * is taken from the original deposit request.
   */
  struct GNUNET_TIME_AbsoluteNBO refund_deadline;

  /**
   * Amount to be deposited, excluding fee.  Calculated from the
   * amount with fee and the fee from the deposit request.
   */
  struct TALER_AmountNBO amount_without_fee;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Mint.  The deposit request is to be
   * signed by the corresponding private key (using EdDSA).
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * The Merchant's public key.  Allows the merchant to later refund
   * the transaction or to inquire about the wire transfer identifier.
   */
  struct TALER_MerchantPublicKeyP merchant;

};


/**
 * @brief Message signed by a coin to indicate that the coin should be
 * melted.
 */
struct TALER_RefreshMeltCoinAffirmationPS
{
  /**
   * Purpose is #TALER_SIGNATURE_WALLET_COIN_MELT.
   * Used for an EdDSA signature with the `struct TALER_CoinSpendPublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Which melting session should the coin become a part of.
   */
  struct GNUNET_HashCode session_hash GNUNET_PACKED;

  /**
   * How much of the value of the coin should be melted?  This amount
   * includes the fees, so the final amount contributed to the melt is
   * this value minus the fee for melting the coin.  We include the
   * fee in what is being signed so that we can verify a reserve's
   * remaining total balance without needing to access the respective
   * denomination key information each time.
   */
  struct TALER_AmountNBO amount_with_fee;

  /**
   * Melting fee charged by the mint.  This must match the Mint's
   * denomination key's melting fee.  If the client puts in an invalid
   * melting fee (too high or too low) that does not match the Mint's
   * denomination key, the melting operation is invalid and will be
   * rejected by the mint.  The @e amount_with_fee minus the @e
   * melt_fee is the amount that will be credited to the melting
   * session.
   */
  struct TALER_AmountNBO melt_fee;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Mint.  The deposit request is to be
   * signed by the corresponding private key (using EdDSA).
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;
};


/**
 * @brief Format of the block signed by the Mint in response to a successful
 * "/refresh/melt" request.  Hereby the mint affirms that all of the
 * coins were successfully melted.  This also commits the mint to a
 * particular index to not be revealed during the refresh.
 */
struct TALER_RefreshMeltConfirmationPS
{
  /**
   * Purpose is #TALER_SIGNATURE_MINT_CONFIRM_MELT.   Signed
   * by a `struct TALER_MintPublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the refresh session.
   */
  struct GNUNET_HashCode session_hash GNUNET_PACKED;

  /**
   * Index that the client will not have to reveal, in NBO.
   * Must be smaller than #TALER_CNC_KAPPA.
   */
  uint16_t noreveal_index GNUNET_PACKED;

  /**
   * Zero.
   */
  uint16_t reserved GNUNET_PACKED;
};


/**
 * @brief Information about a signing key of the mint.  Signing keys are used
 * to sign mint messages other than coins, i.e. to confirm that a
 * deposit was successful or that a refresh was accepted.
 */
struct TALER_MintSigningKeyValidityPS
{
  /**
   * Signature over the signing key (by the master key of the mint).
   *
   * FIXME: should be moved outside of the "PS" struct, this is ugly.
   * (and makes this struct different from all of the others)
   */
  struct TALER_MasterSignatureP signature;

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Master public key of the mint corresponding to @e signature.
   * This is the long-term offline master key of the mint.
   */
  struct TALER_MasterPublicKeyP master_public_key;

  /**
   * When does this signing key begin to be valid?
   */
  struct GNUNET_TIME_AbsoluteNBO start;

  /**
   * When does this signing key expire? Note: This is currently when
   * the Mint will definitively stop using it.  Signatures made with
   * the key remain valid until @e end.  When checking validity periods,
   * clients should allow for some overlap between keys and tolerate
   * the use of either key during the overlap time (due to the
   * possibility of clock skew).
   */
  struct GNUNET_TIME_AbsoluteNBO expire;

  /**
   * When do signatures with this signing key become invalid?  After
   * this point, these signatures cannot be used in (legal) disputes
   * anymore, as the Mint is then allowed to destroy its side of the
   * evidence.  @e end is expected to be significantly larger than @e
   * expire (by a year or more).
   */
  struct GNUNET_TIME_AbsoluteNBO end;

  /**
   * The public online signing key that the mint will use
   * between @e start and @e expire.
   */
  struct TALER_MintPublicKeyP signkey_pub;
};


/**
 * @brief Signature made by the mint over the full set of keys, used
 * to detect cheating mints that give out different sets to
 * different users.
 */
struct TALER_MintKeySetPS
{

  /**
   * Purpose is #TALER_SIGNATURE_MINT_KEY_SET.   Signed
   * by a `struct TALER_MintPublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Time of the key set issue.
   */
  struct GNUNET_TIME_AbsoluteNBO list_issue_date;

  /**
   * Hash over the various denomination signing keys returned.
   */
  struct GNUNET_HashCode hc GNUNET_PACKED;
};


/**
 * @brief Information about a denomination key. Denomination keys
 * are used to sign coins of a certain value into existence.
 */
struct TALER_DenominationKeyValidityPS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * The long-term offline master key of the mint that was
   * used to create @e signature.
   */
  struct TALER_MasterPublicKeyP master;

  /**
   * Start time of the validity period for this key.
   */
  struct GNUNET_TIME_AbsoluteNBO start;

  /**
   * The mint will sign fresh coins between @e start and this time.
   * @e expire_withdraw will be somewhat larger than @e start to
   * ensure a sufficiently large anonymity set, while also allowing
   * the Mint to limit the financial damage in case of a key being
   * compromised.  Thus, mints with low volume are expected to have a
   * longer withdraw period (@e expire_withdraw - @e start) than mints
   * with high transaction volume.  The period may also differ between
   * types of coins.  A mint may also have a few denomination keys
   * with the same value with overlapping validity periods, to address
   * issues such as clock skew.
   */
  struct GNUNET_TIME_AbsoluteNBO expire_withdraw;

  /**
   * Coins signed with the denomination key must be spent or refreshed
   * between @e start and this expiration time.  After this time, the
   * mint will refuse transactions involving this key as it will
   * "drop" the table with double-spending information (shortly after)
   * this time.  Note that wallets should refresh coins significantly
   * before this time to be on the safe side.  @e expire_spend must be
   * significantly larger than @e expire_withdraw (by months or even
   * years).
   */
  struct GNUNET_TIME_AbsoluteNBO expire_spend;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Mint is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_spend (by a year or more).
   */
  struct GNUNET_TIME_AbsoluteNBO expire_legal;

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
   * Hash code of the denomination public key. (Used to avoid having
   * the variable-size RSA key in this struct.)
   */
  struct GNUNET_HashCode denom_hash GNUNET_PACKED;

};


/**
 * @brief Information signed by an auditor affirming
 * the master public key and the denomination keys
 * of a mint.
 */
struct TALER_MintKeyValidityPS
{

  /**
   * Purpose is #TALER_SIGNATURE_AUDITOR_MINT_KEYS.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * The long-term offline master key of the mint, affirmed by the
   * auditor.
   */
  struct TALER_MasterPublicKeyP master;

  /**
   * Start time of the validity period for this key.
   */
  struct GNUNET_TIME_AbsoluteNBO start;

  /**
   * The mint will sign fresh coins between @e start and this time.
   * @e expire_withdraw will be somewhat larger than @e start to
   * ensure a sufficiently large anonymity set, while also allowing
   * the Mint to limit the financial damage in case of a key being
   * compromised.  Thus, mints with low volume are expected to have a
   * longer withdraw period (@e expire_withdraw - @e start) than mints
   * with high transaction volume.  The period may also differ between
   * types of coins.  A mint may also have a few denomination keys
   * with the same value with overlapping validity periods, to address
   * issues such as clock skew.
   */
  struct GNUNET_TIME_AbsoluteNBO expire_withdraw;

  /**
   * Coins signed with the denomination key must be spent or refreshed
   * between @e start and this expiration time.  After this time, the
   * mint will refuse transactions involving this key as it will
   * "drop" the table with double-spending information (shortly after)
   * this time.  Note that wallets should refresh coins significantly
   * before this time to be on the safe side.  @e expire_spend must be
   * significantly larger than @e expire_withdraw (by months or even
   * years).
   */
  struct GNUNET_TIME_AbsoluteNBO expire_spend;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Mint is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_spend (by a year or more).
   */
  struct GNUNET_TIME_AbsoluteNBO expire_legal;

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
   * Hash code of the denomination public key. (Used to avoid having
   * the variable-size RSA key in this struct.)
   */
  struct GNUNET_HashCode denom_hash GNUNET_PACKED;

};


/**
 * @brief For each (old) coin being melted, we have a `struct
 * RefreshCommitLinkP` that allows the user to find the shared secret
 * to decrypt the respective refresh links for the new coins in the
 * `struct TALER_MINTDB_RefreshCommitCoin`.
 *
 * Part of the construction of the refresh session's hash and
 * thus of what is signed there.
 */
struct TALER_RefreshCommitLinkP
{
  /**
   * Transfer public key, used to decrypt the @e shared_secret_enc
   * in combintation with the corresponding private key of the
   * coin.
   */
  struct TALER_TransferPublicKeyP transfer_pub;

  /**
   * Encrypted shared secret to decrypt the link.
   */
  struct TALER_EncryptedLinkSecretP shared_secret_enc;
};


/**
 * @brief Information signed by the mint's master
 * key affirming the SEPA details for the mint.
 */
struct TALER_MasterWireSepaDetailsPS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_SEPA_DETAILS.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the account holder's name, IBAN and BIC
   * code (all as 0-terminated strings).
   */
  struct GNUNET_HashCode h_sepa_details GNUNET_PACKED;

};


/**
 * @brief Information signed by a mint's online signing key affirming
 * the wire formats supported by the mint.
 */
struct TALER_MintWireSupportMethodsPS
{

  /**
   * Purpose is #TALER_SIGNATURE_MINT_WIRE_TYPES.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the various wire formats supported by this mint
   * (all as 0-terminated strings).
   */
  struct GNUNET_HashCode h_wire_types GNUNET_PACKED;

};


/**
 * @brief Format used to generate the signature on a request to obtain
 * the wire transfer identifier associated with a deposit.
 */
struct TALER_DepositTrackPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_MERCHANT_DEPOSIT_WTID.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct GNUNET_HashCode h_contract GNUNET_PACKED;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire GNUNET_PACKED;

  /**
   * Merchant-generated transaction ID to detect duplicate
   * transactions.  The merchant must communicate a merchant-unique ID
   * to the customer for each transaction.  Note that different coins
   * that are part of the same transaction can use the same
   * transaction ID.  The transaction ID is useful for later disputes,
   * and the merchant's contract offer (@e h_contract) with the
   * customer should include the offer's term and transaction ID
   * signed with a key from the merchant.
   */
  uint64_t transaction_id GNUNET_PACKED;

  /**
   * The Merchant's public key.  The deposit inquiry request is to be
   * signed by the corresponding private key (using EdDSA).
   */
  struct TALER_MerchantPublicKeyP merchant;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Mint.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

};


/**
 * The contract sent by the merchant to the wallet.
 */
struct TALER_ContractPS
{
  /**
   * Purpose header for the signature over the contract with
   * purpose #TALER_SIGNATURE_MERCHANT_CONTRACT.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Merchant-generated transaction ID to detect duplicate
   * transactions, in big endian.  The merchant must communicate a
   * merchant-unique ID to the customer for each transaction.  Note
   * that different coins that are part of the same transaction can
   * use the same transaction ID.  The transaction ID is useful for
   * later disputes, and the merchant's contract offer (@e h_contract)
   * with the customer should include the offer's term and transaction
   * ID signed with a key from the merchant.  This field must match
   * the corresponding field in the JSON contract.
   */
  uint64_t transaction_id GNUNET_PACKED;

  /**
   * The total amount to be paid to the merchant. Note that if deposit
   * fees are higher than @e max_fee, the actual total must be higher
   * to cover the additional fees.  This field must match the
   * corresponding field in the JSON contract.
   */
  struct TALER_AmountNBO total_amount;

  /**
   * The maximum fee the merchant is willing to cover.  This field
   * must match the corresponding field in the JSON contract.
   */
  struct TALER_AmountNBO max_fee;

  /**
   * Hash of the JSON contract in UTF-8 including 0-termination,
   * using JSON_COMPACT | JSON_SORT_KEYS
   */
  struct GNUNET_HashCode h_contract;

};


/**
 * Details affirmed by the mint about a wire transfer the mint
 * claims to have done with respect to a deposit operation.
 */
struct TALER_ConfirmWirePS
{
  /**
   * Purpose header for the signature over the contract with
   * purpose #TALER_SIGNATURE_MINT_CONFIRM_WIRE.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire GNUNET_PACKED;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct GNUNET_HashCode h_contract GNUNET_PACKED;

  /**
   * Raw value (binary encoding) of the wire transfer subject.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Mint.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Merchant-generated transaction ID to detect duplicate
   * transactions, in big endian.  The merchant must communicate a
   * merchant-unique ID to the customer for each transaction.  Note
   * that different coins that are part of the same transaction can
   * use the same transaction ID.  The transaction ID is useful for
   * later disputes, and the merchant's contract offer (@e h_contract)
   * with the customer should include the offer's term and transaction
   * ID signed with a key from the merchant.
   */
  uint64_t transaction_id GNUNET_PACKED;

  /**
   * When did the mint execute this transfer? Note that the
   * timestamp may not be exactly the same on the wire, i.e.
   * because the wire has a different timezone or resolution.
   */
  struct GNUNET_TIME_AbsoluteNBO execution_time;

  /**
   * The contribution of @e coin_pub to the total transfer volume.
   * This is the value of the deposit minus the fee.
   */
  struct TALER_AmountNBO coin_contribution;

};

GNUNET_NETWORK_STRUCT_END

#endif
