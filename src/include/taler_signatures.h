/*
  This file is part of TALER
  Copyright (C) 2014-2017 GNUnet e.V.

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


/*********************************************/
/* Exchange offline signatures (with master key) */
/*********************************************/

/**
 * Purpose for signing public keys signed by the exchange master key.
 */
#define TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY 1024

/**
 * Purpose for denomination keys signed by the exchange master key.
 */
#define TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY 1025

/**
 * Fees charged per (aggregate) wire transfer to the merchant.
 */
#define TALER_SIGNATURE_MASTER_WIRE_FEES 1028

/**
 * The given revocation key was revoked and must no longer be used.
 */
#define TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED 1029

/**
 * Signature where the Exchange confirms its IBAN details in
 * the /wire response.
 */
#define TALER_SIGNATURE_MASTER_WIRE_DETAILS 1030

/*********************************************/
/* Exchange online signatures (with signing key) */
/*********************************************/

/**
 * Purpose for the state of a reserve, signed by the exchange's signing
 * key.
 */
#define TALER_SIGNATURE_EXCHANGE_RESERVE_STATUS 1032

/**
 * Signature where the Exchange confirms a deposit request.
 */
#define TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT 1033

/**
 * Signature where the exchange (current signing key) confirms the
 * no-reveal index for cut-and-choose and the validity of the melted
 * coins.
 */
#define TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT 1034

/**
 * Signature where the Exchange confirms the full /keys response set.
 */
#define TALER_SIGNATURE_EXCHANGE_KEY_SET 1035

/**
 * Signature where the Exchange confirms the /track/transaction response.
 */
#define TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE 1036

/**
 * Signature where the Exchange confirms the /wire/deposit response.
 */
#define TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE_DEPOSIT 1037

/**
 * Signature where the Exchange confirms a refund request.
 */
#define TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND 1038

/**
 * Signature where the Exchange confirms a payback.
 */
#define TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK 1039

/**
 * Signature where the Exchange confirms it closed a reserve.
 */
#define TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED 1040


/**********************/
/* Auditor signatures */
/**********************/

/**
 * Signature where the auditor confirms that he is
 * aware of certain denomination keys from the exchange.
 */
#define TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS 1064


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
#define TALER_SIGNATURE_MERCHANT_TRACK_TRANSACTION 1103

/**
 * Signature where the merchant confirms that the payment was
 * successful
 */
#define TALER_SIGNATURE_MERCHANT_PAYMENT_OK 1104

/**
 * Signature where the merchant confirms a refund increase
 */
#define TALER_SIGNATURE_MERCHANT_REFUND_OK 1105

/**
 * Signature where the merchant confirms that the user replayed
 * a payment for a browser session.
 */
#define TALER_SIGNATURE_MERCHANT_PAY_SESSION 1106

/**
 * Signature where the merchant confirms its own (salted)
 * wire details (not yet really used).
 */
#define TALER_SIGNATURE_MERCHANT_WIRE_DETAILS 1107


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

/**
 * Signature using a coin key requesting payback.
 */
#define TALER_SIGNATURE_WALLET_COIN_PAYBACK 1203

/**
 * Signature using a coin key authenticating link data.
 */
#define TALER_SIGNATURE_WALLET_COIN_LINK 1204


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
#define TALER_SIGNATURE_EXCHANGE_TEST_EDDSA 1303



GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Format used for to allow the wallet to authenticate
 * link data provided by the exchange.
 */
struct TALER_LinkDataPS
{

  /**
   * Purpose must be #TALER_SIGNATURE_WALLET_COIN_LINK.
   * Used with an EdDSA signature of a `struct TALER_CoinPublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the denomination public key of the new coin.
   */
  struct GNUNET_HashCode h_denom_pub;

  /**
   * Public key of the old coin being refreshed.
   */
  struct TALER_CoinSpendPublicKeyP old_coin_pub;

  /**
   * Transfer public key (for which the private key was not revealed)
   */
  struct TALER_TransferPublicKeyP transfer_pub;

  /**
   * Hash of the blinded new coin.
   */
  struct GNUNET_HashCode coin_envelope_hash;
};


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
   * Value of the coin being exchangeed (matching the denomination key)
   * plus the transaction fee.  We include this in what is being
   * signed so that we can verify a reserve's remaining total balance
   * without needing to access the respective denomination key
   * information each time.
   */
  struct TALER_AmountNBO amount_with_fee;

  /**
   * Withdrawl fee charged by the exchange.  This must match the Exchange's
   * denomination key's withdrawl fee.  If the client puts in an
   * invalid withdrawl fee (too high or too low) that does not match
   * the Exchange's denomination key, the withdraw operation is invalid
   * and will be rejected by the exchange.  The @e amount_with_fee minus
   * the @e withdraw_fee is must match the value of the generated
   * coin.  We include this in what is being signed so that we can
   * verify a exchange's accounting without needing to access the
   * respective denomination key information each time.
   */
  struct TALER_AmountNBO withdraw_fee;

  /**
   * Hash of the denomination public key for the coin that is withdrawn.
   */
  struct GNUNET_HashCode h_denomination_pub GNUNET_PACKED;

  /**
   * Hash of the (blinded) message to be signed by the Exchange.
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
  struct GNUNET_HashCode h_contract_terms GNUNET_PACKED;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire GNUNET_PACKED;

  /**
   * Time when this request was generated.  Used, for example, to
   * assess when (roughly) the income was achieved for tax purposes.
   * Note that the Exchange will only check that the timestamp is not "too
   * far" into the future (i.e. several days).  The fact that the
   * timestamp falls within the validity period of the coin's
   * denomination key is irrelevant for the validity of the deposit
   * request, as obviously the customer and merchant could conspire to
   * set any timestamp.  Also, the Exchange must accept very old deposit
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
   * Amount to be deposited, including deposit fee charged by the
   * exchange.  This is the total amount that the coin's value at the exchange
   * will be reduced by.
   */
  struct TALER_AmountNBO amount_with_fee;

  /**
   * Depositing fee charged by the exchange.  This must match the Exchange's
   * denomination key's depositing fee.  If the client puts in an
   * invalid deposit fee (too high or too low) that does not match the
   * Exchange's denomination key, the deposit operation is invalid and
   * will be rejected by the exchange.  The @e amount_with_fee minus the
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
   * signed (blindly) by the Exchange.  The deposit request is to be
   * signed by the corresponding private key (using EdDSA).
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

};


/**
 * @brief Format used to generate the signature on a confirmation
 * from the exchange that a deposit request succeeded.
 */
struct TALER_DepositConfirmationPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT.  Signed
   * by a `struct TALER_ExchangePublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct GNUNET_HashCode h_contract_terms GNUNET_PACKED;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire GNUNET_PACKED;

  /**
   * Time when this confirmation was generated.
   */
  struct GNUNET_TIME_AbsoluteNBO timestamp;

  /**
   * How much time does the @e merchant have to issue a refund
   * request?  Zero if refunds are not allowed.  After this time, the
   * coin cannot be refunded.  Note that the wire transfer will not be
   * performed by the exchange until the refund deadline.  This value
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
   * signed (blindly) by the Exchange.  The deposit request is to be
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
 * @brief Format used to generate the signature on a request to refund
 * a coin into the account of the customer.
 */
struct TALER_RefundRequestPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_MERCHANT_REFUND.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the proposal data to identify the contract
   * which is being refunded.
   */
  struct GNUNET_HashCode h_contract_terms GNUNET_PACKED;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Exchange.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * The Merchant's public key.  Allows the merchant to later refund
   * the transaction or to inquire about the wire transfer identifier.
   */
  struct TALER_MerchantPublicKeyP merchant;

  /**
   * Merchant-generated transaction ID for the refund.
   */
  uint64_t rtransaction_id GNUNET_PACKED;

  /**
   * Amount to be refunded, including refund fee charged by the
   * exchange to the customer.
   */
  struct TALER_AmountNBO refund_amount;

  /**
   * Refund fee charged by the exchange.  This must match the
   * Exchange's denomination key's refund fee.  If the client puts in
   * an invalid refund fee (too high or too low) that does not match
   * the Exchange's denomination key, the refund operation is invalid
   * and will be rejected by the exchange.  The @e amount_with_fee
   * minus the @e refund_fee is the amount that will be credited to
   * the original coin.
   */
  struct TALER_AmountNBO refund_fee;

};


/**
 * @brief Format used to generate the signature on a request to refund
 * a coin into the account of the customer.
 */
struct TALER_RefundConfirmationPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the proposal data to identify the contract
   * which is being refunded.
   */
  struct GNUNET_HashCode h_contract_terms GNUNET_PACKED;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Exchange.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * The Merchant's public key.  Allows the merchant to later refund
   * the transaction or to inquire about the wire transfer identifier.
   */
  struct TALER_MerchantPublicKeyP merchant;

  /**
   * Merchant-generated transaction ID for the refund.
   */
  uint64_t rtransaction_id GNUNET_PACKED;

  /**
   * Amount to be refunded, including refund fee charged by the
   * exchange to the customer.
   */
  struct TALER_AmountNBO refund_amount;

  /**
   * Refund fee charged by the exchange.  This must match the
   * Exchange's denomination key's refund fee.  If the client puts in
   * an invalid refund fee (too high or too low) that does not match
   * the Exchange's denomination key, the refund operation is invalid
   * and will be rejected by the exchange.  The @e amount_with_fee
   * minus the @e refund_fee is the amount that will be credited to
   * the original coin.
   */
  struct TALER_AmountNBO refund_fee;

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
   * Which melt commitment is made by the wallet.
   */
  struct TALER_RefreshCommitmentP rc GNUNET_PACKED;

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
   * Melting fee charged by the exchange.  This must match the Exchange's
   * denomination key's melting fee.  If the client puts in an invalid
   * melting fee (too high or too low) that does not match the Exchange's
   * denomination key, the melting operation is invalid and will be
   * rejected by the exchange.  The @e amount_with_fee minus the @e
   * melt_fee is the amount that will be credited to the melting
   * session.
   */
  struct TALER_AmountNBO melt_fee;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Exchange.  The deposit request is to be
   * signed by the corresponding private key (using EdDSA).
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;
};


/**
 * @brief Format of the block signed by the Exchange in response to a successful
 * "/refresh/melt" request.  Hereby the exchange affirms that all of the
 * coins were successfully melted.  This also commits the exchange to a
 * particular index to not be revealed during the refresh.
 */
struct TALER_RefreshMeltConfirmationPS
{
  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT.   Signed
   * by a `struct TALER_ExchangePublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Commitment made in the /refresh/melt.
   */
  struct TALER_RefreshCommitmentP rc GNUNET_PACKED;

  /**
   * Index that the client will not have to reveal, in NBO.
   * Must be smaller than #TALER_CNC_KAPPA.
   */
  uint32_t noreveal_index GNUNET_PACKED;

};


/**
 * @brief Information about a signing key of the exchange.  Signing keys are used
 * to sign exchange messages other than coins, i.e. to confirm that a
 * deposit was successful or that a refresh was accepted.
 */
struct TALER_ExchangeSigningKeyValidityPS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Master public key of the exchange corresponding to @e signature.
   * This is the long-term offline master key of the exchange.
   */
  struct TALER_MasterPublicKeyP master_public_key;

  /**
   * When does this signing key begin to be valid?
   */
  struct GNUNET_TIME_AbsoluteNBO start;

  /**
   * When does this signing key expire? Note: This is currently when
   * the Exchange will definitively stop using it.  Signatures made with
   * the key remain valid until @e end.  When checking validity periods,
   * clients should allow for some overlap between keys and tolerate
   * the use of either key during the overlap time (due to the
   * possibility of clock skew).
   */
  struct GNUNET_TIME_AbsoluteNBO expire;

  /**
   * When do signatures with this signing key become invalid?  After
   * this point, these signatures cannot be used in (legal) disputes
   * anymore, as the Exchange is then allowed to destroy its side of the
   * evidence.  @e end is expected to be significantly larger than @e
   * expire (by a year or more).
   */
  struct GNUNET_TIME_AbsoluteNBO end;

  /**
   * The public online signing key that the exchange will use
   * between @e start and @e expire.
   */
  struct TALER_ExchangePublicKeyP signkey_pub;
};


/**
 * @brief Signature made by the exchange over the full set of keys, used
 * to detect cheating exchanges that give out different sets to
 * different users.
 */
struct TALER_ExchangeKeySetPS
{

  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_KEY_SET.   Signed
   * by a `struct TALER_ExchangePublicKeyP` using EdDSA.
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
   * The long-term offline master key of the exchange that was
   * used to create @e signature.
   */
  struct TALER_MasterPublicKeyP master;

  /**
   * Start time of the validity period for this key.
   */
  struct GNUNET_TIME_AbsoluteNBO start;

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
  struct GNUNET_TIME_AbsoluteNBO expire_withdraw;

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
  struct GNUNET_TIME_AbsoluteNBO expire_deposit;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_deposit (by a year or more).
   */
  struct GNUNET_TIME_AbsoluteNBO expire_legal;

  /**
   * The value of the coins signed with this denomination key.
   */
  struct TALER_AmountNBO value;

  /**
   * The fee the exchange charges when a coin of this type is withdrawn.
   * (can be zero).
   */
  struct TALER_AmountNBO fee_withdraw;

  /**
   * The fee the exchange charges when a coin of this type is deposited.
   * (can be zero).
   */
  struct TALER_AmountNBO fee_deposit;

  /**
   * The fee the exchange charges when a coin of this type is refreshed.
   * (can be zero).
   */
  struct TALER_AmountNBO fee_refresh;

  /**
   * The fee the exchange charges when a coin of this type is refunded.
   * (can be zero).  Note that refund fees are charged to the customer;
   * if a refund is given, the deposit fee is also refunded.
   */
  struct TALER_AmountNBO fee_refund;

  /**
   * Hash code of the denomination public key. (Used to avoid having
   * the variable-size RSA key in this struct.)
   */
  struct GNUNET_HashCode denom_hash GNUNET_PACKED;

};


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
   * auditor.  Hashed string, including 0-terminator.
   */
  struct TALER_MasterPublicKeyP master;

  /**
   * Start time of the validity period for this key.
   */
  struct GNUNET_TIME_AbsoluteNBO start;

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
  struct GNUNET_TIME_AbsoluteNBO expire_withdraw;

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
  struct GNUNET_TIME_AbsoluteNBO expire_deposit;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_deposit (by a year or more).
   */
  struct GNUNET_TIME_AbsoluteNBO expire_legal;

  /**
   * The value of the coins signed with this denomination key.
   */
  struct TALER_AmountNBO value;

  /**
   * The fee the exchange charges when a coin of this type is withdrawn.
   * (can be zero).
   */
  struct TALER_AmountNBO fee_withdraw;

  /**
   * The fee the exchange charges when a coin of this type is deposited.
   * (can be zero).
   */
  struct TALER_AmountNBO fee_deposit;

  /**
   * The fee the exchange charges when a coin of this type is refreshed.
   * (can be zero).
   */
  struct TALER_AmountNBO fee_refresh;

  /**
   * The fee the exchange charges when a coin of this type is refreshed.
   * (can be zero).
   */
  struct TALER_AmountNBO fee_refund;

  /**
   * Hash code of the denomination public key. (Used to avoid having
   * the variable-size RSA key in this struct.)
   */
  struct GNUNET_HashCode denom_hash GNUNET_PACKED;

};


/**
 * @brief Information signed by the exchange's master
 * key affirming the IBAN details for the exchange.
 */
struct TALER_MasterWireDetailsPS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_WIRE_DETAILS.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the account holder's payto:// URL and
   * the salt, as done by #TALER_wire_signature_hash().
   */
  struct GNUNET_HashCode h_wire_details GNUNET_PACKED;

};



/**
 * @brief Information signed by the exchange's master
 * key stating the wire fee to be paid per wire transfer.
 */
struct TALER_MasterWireFeePS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_WIRE_FEES.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the wire method (yes, H("x-taler-bank") or H("iban")), in lower
   * case, including 0-terminator.  Used to uniquely identify which
   * wire method these fees apply to.
   */
  struct GNUNET_HashCode h_wire_method;

  /**
   * Start date when the fee goes into effect.
   */
  struct GNUNET_TIME_AbsoluteNBO start_date;

  /**
   * End date when the fee stops being in effect (exclusive)
   */
  struct GNUNET_TIME_AbsoluteNBO end_date;

  /**
   * Fee charged to the merchant per wire transfer.
   */
  struct TALER_AmountNBO wire_fee;

  /**
   * Closing fee charged when we wire back funds of a reserve.
   */
  struct TALER_AmountNBO closing_fee;

};


/**
 * @brief Message confirming that a denomination key was revoked.
 */
struct TALER_MasterDenominationKeyRevocationPS
{
  /**
   * Purpose is #TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the denomination key.
   */
  struct GNUNET_HashCode h_denom_pub;

};


/**
 * @brief Format used to generate the signature on a request to obtain
 * the wire transfer identifier associated with a deposit.
 */
struct TALER_DepositTrackPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_MERCHANT_TRACK_TRANSACTION.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the proposal data of the contract for which this deposit is made.
   */
  struct GNUNET_HashCode h_contract_terms GNUNET_PACKED;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire GNUNET_PACKED;

  /**
   * The Merchant's public key.  The deposit inquiry request is to be
   * signed by the corresponding private key (using EdDSA).
   */
  struct TALER_MerchantPublicKeyP merchant;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Exchange.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

};


/**
 * @brief Format internally used for packing the detailed information
 * to generate the signature for /track/transfer signatures.
 */
struct TALER_WireDepositDetailP
{

  /**
   * Hash of the contract
   */
  struct GNUNET_HashCode h_contract_terms;

  /**
   * Time when the wire transfer was performed by the exchange.
   */
  struct GNUNET_TIME_AbsoluteNBO execution_time;

  /**
   * Coin's public key.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Total value of the coin.
   */
  struct TALER_AmountNBO deposit_value;

  /**
   * Fees charged by the exchange for the deposit.
   */
  struct TALER_AmountNBO deposit_fee;

};


/**
 * @brief Format used to generate the signature for /wire/deposit
 * replies.
 */
struct TALER_WireDepositDataPS
{
  /**
   * Purpose header for the signature over the contract with
   * purpose #TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE_DEPOSIT.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Total amount that was transferred.
   */
  struct TALER_AmountNBO total;

  /**
   * Wire fee that was charged.
   */
  struct TALER_AmountNBO wire_fee;

  /**
   * Public key of the merchant (for all aggregated transactions).
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Hash of wire details of the merchant.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Hash of the individual deposits that were aggregated,
   * each in the format of a `struct TALER_WireDepositDetailP`.
   */
  struct GNUNET_HashCode h_details;

};

/**
 * The contract sent by the merchant to the wallet.
 */
struct TALER_ProposalDataPS
{
  /**
   * Purpose header for the signature over the proposal data
   * with purpose #TALER_SIGNATURE_MERCHANT_CONTRACT.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the JSON contract in UTF-8 including 0-termination,
   * using JSON_COMPACT | JSON_SORT_KEYS
   */
  struct GNUNET_HashCode hash;
};

/**
 * Used by merchants to return signed responses to /pay requests.
 * Currently only used to return 200 OK signed responses.
 */
struct PaymentResponsePS
{
  /**
   * Set to TALER_SIGNATURE_MERCHANT_PAYMENT_OK so far. Note that
   * unsuccessful payments are usually proven by some exchange's signature,
   * thus it is unlikely that a merchant needs to set a purpose other than
   * the above mentioned
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the proposal data associated with this confirmation
   */
  struct GNUNET_HashCode h_contract_terms;
};


/**
 * Details affirmed by the exchange about a wire transfer the exchange
 * claims to have done with respect to a deposit operation.
 */
struct TALER_ConfirmWirePS
{
  /**
   * Purpose header for the signature over the contract with
   * purpose #TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire GNUNET_PACKED;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct GNUNET_HashCode h_contract_terms GNUNET_PACKED;

  /**
   * Raw value (binary encoding) of the wire transfer subject.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Exchange.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * When did the exchange execute this transfer? Note that the
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


/**
 * Signed data to request that a coin should be refunded as part of
 * the "emergency" /payback protocol.  The refund will go back to the bank
 * account that created the reserve.
 */
struct TALER_PaybackRequestPS
{
  /**
   * Purpose is #TALER_SIGNATURE_WALLET_COIN_PAYBACK
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Public key of the coin to be refunded.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Hash of the denomination public key of the coin.
   */
  struct GNUNET_HashCode h_denom_pub;

  /**
   * Blinding factor that was used to withdraw the coin.
   */
  struct TALER_DenominationBlindingKeyP coin_blind;
};


/**
 * Response by which the exchange affirms that it will
 * refund a coin as part of the emergency /payback
 * protocol.  The refund will go back to the bank
 * account that created the reserve.
 */
struct TALER_PaybackConfirmationPS
{

  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When did the exchange receive the payback request?
   * Indirectly determines when the wire transfer is (likely)
   * to happen.
   */
  struct GNUNET_TIME_AbsoluteNBO timestamp;

  /**
   * How much of the coin's value will the exchange transfer?
   * (Needed in case the coin was partially spent.)
   */
  struct TALER_AmountNBO payback_amount;

  /**
   * Public key of the coin.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Public key of the reserve that will receive the payback.
   */
  struct TALER_ReservePublicKeyP reserve_pub;
};


/**
 * Response by which the exchange affirms that it has
 * closed a reserve and send back the funds.
 */
struct TALER_ReserveCloseConfirmationPS
{

  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When did the exchange initiate the wire transfer.
   */
  struct GNUNET_TIME_AbsoluteNBO timestamp;

  /**
   * How much did the exchange send?
   */
  struct TALER_AmountNBO closing_amount;

  /**
   * How much did the exchange charge for closing the reserve?
   */
  struct TALER_AmountNBO closing_fee;

  /**
   * Public key of the reserve that received the payback.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Hash of the receiver's bank account.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Wire transfer subject.
   */
  struct TALER_WireTransferIdentifierRawP wtid;
};


/**
 * Used by the merchant to confirm with a signature that the refund has
 * been successfully done. Even though the frontend doesn't usually do crypto,
 * this signature may turn useful in court.
 */
struct TALER_MerchantRefundConfirmationPS
{
  /**
   * Set to #TALER_SIGNATURE_MERCHANT_REFUND_OK.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hashed order id; in case frontend wants to check it.
   * Hashed without the 0-termination.
   */
  struct GNUNET_HashCode h_order_id GNUNET_PACKED;

};

/**
 * Used by the merchant to confirm to the frontend that
 * the user did a payment replay with the current browser session.
 */
struct TALER_MerchantPaySessionSigPS
{
  /**
   * Set to #TALER_SIGNATURE_MERCHANT_PAY_SESSION.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hashed order id.
   * Hashed without the 0-termination.
   */
  struct GNUNET_HashCode h_order_id GNUNET_PACKED;

  /**
   * Hashed session id.
   * Hashed without the 0-termination.
   */
  struct GNUNET_HashCode h_session_id GNUNET_PACKED;

};

GNUNET_NETWORK_STRUCT_END

#endif
