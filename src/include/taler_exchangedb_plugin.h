/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file include/taler_exchangedb_plugin.h
 * @brief Low-level (statement-level) database access for the exchange
 * @author Florian Dold
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGEDB_PLUGIN_H
#define TALER_EXCHANGEDB_PLUGIN_H
#include <jansson.h>
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_db_lib.h>
#include "taler_signatures.h"


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief On disk format used for a exchange signing key.  Signing keys are used
 * by the exchange to affirm its messages, but not to create coins.
 * Includes the private key followed by the public information about
 * the signing key.
 */
struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP
{
  /**
   * Private key part of the exchange's signing key.
   */
  struct TALER_ExchangePrivateKeyP signkey_priv;

  /**
   * Signature over @e issue
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * Public information about a exchange signing key.
   */
  struct TALER_ExchangeSigningKeyValidityPS issue;

};


/**
 * Information about a denomination key.
 */
struct TALER_EXCHANGEDB_DenominationKeyInformationP
{

  /**
   * Signature over this struct to affirm the validity of the key.
   */
  struct TALER_MasterSignatureP signature;

  /**
   * Signed properties of the denomination key.
   */
  struct TALER_DenominationKeyValidityPS properties;
};


GNUNET_NETWORK_STRUCT_END

/**
 * Meta data about an exchange online signing key.
 */
struct TALER_EXCHANGEDB_SignkeyMetaData
{
  /**
   * Start time of the validity period for this key.
   */
  struct GNUNET_TIME_Absolute start;

  /**
   * The exchange will sign messages with this key between @e start and this time.
   */
  struct GNUNET_TIME_Absolute expire_sign;

  /**
   * When do signatures with this sign key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_sign (by a year or more).
   */
  struct GNUNET_TIME_Absolute expire_legal;

};


/**
 * Enumeration of all of the tables replicated by exchange-auditor
 * database replication.
 */
enum TALER_EXCHANGEDB_ReplicatedTable
{
  TALER_EXCHANGEDB_RT_DENOMINATIONS,
  TALER_EXCHANGEDB_RT_DENOMINATION_REVOCATIONS,
  TALER_EXCHANGEDB_RT_RESERVES,
  TALER_EXCHANGEDB_RT_RESERVES_IN,
  TALER_EXCHANGEDB_RT_RESERVES_CLOSE,
  TALER_EXCHANGEDB_RT_RESERVES_OUT,
  TALER_EXCHANGEDB_RT_AUDITORS,
  TALER_EXCHANGEDB_RT_AUDITOR_DENOM_SIGS,
  TALER_EXCHANGEDB_RT_EXCHANGE_SIGN_KEYS,
  TALER_EXCHANGEDB_RT_SIGNKEY_REVOCATIONS,
  TALER_EXCHANGEDB_RT_KNOWN_COINS,
  TALER_EXCHANGEDB_RT_REFRESH_COMMITMENTS,
  TALER_EXCHANGEDB_RT_REFRESH_REVEALED_COINS,
  TALER_EXCHANGEDB_RT_REFRESH_TRANSFER_KEYS,
  TALER_EXCHANGEDB_RT_DEPOSITS,
  TALER_EXCHANGEDB_RT_REFUNDS,
  TALER_EXCHANGEDB_RT_WIRE_OUT,
  TALER_EXCHANGEDB_RT_AGGREGATION_TRACKING,
  TALER_EXCHANGEDB_RT_WIRE_FEE,
  TALER_EXCHANGEDB_RT_RECOUP,
  TALER_EXCHANGEDB_RT_RECOUP_REFRESH
};


/**
 * Record of a single entry in a replicated table.
 */
struct TALER_EXCHANGEDB_TableData
{
  /**
   * Data of which table is returned here?
   */
  enum TALER_EXCHANGEDB_ReplicatedTable table;

  /**
   * Serial number of the record.
   */
  uint64_t serial;

  /**
   * Table-specific details.
   */
  union
  {

    /**
     * Details from the 'denominations' table.
     */
    struct
    {
      struct TALER_DenominationPublicKey denom_pub;
      struct TALER_MasterSignatureP master_sig;
      struct GNUNET_TIME_Absolute valid_from;
      struct GNUNET_TIME_Absolute expire_withdraw;
      struct GNUNET_TIME_Absolute expire_deposit;
      struct GNUNET_TIME_Absolute expire_legal;
      struct TALER_Amount coin;
      struct TALER_Amount fee_withdraw;
      struct TALER_Amount fee_deposit;
      struct TALER_Amount fee_refresh;
      struct TALER_Amount fee_refund;
    } denominations;

    struct
    {
      struct TALER_MasterSignatureP master_sig;
      uint64_t denominations_serial;
    } denomination_revocations;

    struct
    {
      struct TALER_ReservePublicKeyP reserve_pub;
      char *account_details;
      /**
       * Note: not useful for auditor, because not UPDATEd!
       */
      struct TALER_Amount current_balance;
      struct GNUNET_TIME_Absolute expiration_date;
      struct GNUNET_TIME_Absolute gc_date;
    } reserves;

    struct
    {
      uint64_t wire_reference;
      struct TALER_Amount credit;
      char *sender_account_details;
      char *exchange_account_section;
      struct GNUNET_TIME_Absolute execution_date;
      uint64_t reserve_uuid;
    } reserves_in;

    struct
    {
      struct GNUNET_TIME_Absolute execution_date;
      struct TALER_WireTransferIdentifierRawP wtid;
      char *receiver_account;
      struct TALER_Amount amount;
      struct TALER_Amount closing_fee;
      uint64_t reserve_uuid;
    } reserves_close;

    struct
    {
      struct GNUNET_HashCode h_blind_ev;
      struct TALER_DenominationSignature denom_sig;
      struct TALER_ReserveSignatureP reserve_sig;
      struct GNUNET_TIME_Absolute execution_date;
      struct TALER_Amount amount_with_fee;
      uint64_t reserve_uuid;
      uint64_t denominations_serial;
    } reserves_out;

    struct
    {
      struct TALER_AuditorPublicKeyP auditor_pub;
      char *auditor_url;
      char *auditor_name;
      bool is_active;
      struct GNUNET_TIME_Absolute last_change;
    } auditors;

    struct
    {
      uint64_t auditor_uuid;
      uint64_t denominations_serial;
      struct TALER_AuditorSignatureP auditor_sig;
    } auditor_denom_sigs;

    struct
    {
      struct TALER_ExchangePublicKeyP exchange_pub;
      struct TALER_MasterSignatureP master_sig;
      struct TALER_EXCHANGEDB_SignkeyMetaData meta;
    } exchange_sign_keys;

    struct
    {
      uint64_t esk_serial;
      struct TALER_MasterSignatureP master_sig;
    } signkey_revocations;

    struct
    {
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct TALER_DenominationSignature denom_sig;
      uint64_t denominations_serial;
    } known_coins;

    struct
    {
      struct TALER_RefreshCommitmentP rc;
      struct TALER_CoinSpendSignatureP old_coin_sig;
      struct TALER_Amount amount_with_fee;
      uint32_t noreveal_index;
      uint64_t old_known_coin_id;
    } refresh_commitments;

    struct
    {
      uint32_t freshcoin_index;
      struct TALER_CoinSpendSignatureP link_sig;
      void *coin_ev;
      size_t coin_ev_size;
      // h_coin_ev omitted, to be recomputed!
      struct TALER_DenominationSignature ev_sig;
      uint64_t denominations_serial;
      uint64_t melt_serial_id;
    } refresh_revealed_coins;

    struct
    {
      struct TALER_TransferPublicKeyP tp;
      struct TALER_TransferPrivateKeyP tprivs[TALER_CNC_KAPPA - 1];
      uint64_t melt_serial_id;
    } refresh_transfer_keys;

    struct
    {
      struct TALER_Amount amount_with_fee;
      struct GNUNET_TIME_Absolute wallet_timestamp;
      struct GNUNET_TIME_Absolute exchange_timestamp;
      struct GNUNET_TIME_Absolute refund_deadline;
      struct GNUNET_TIME_Absolute wire_deadline;
      struct TALER_MerchantPublicKeyP merchant_pub;
      struct GNUNET_HashCode h_contract_terms;
      // h_wire omitted, to be recomputed!
      struct TALER_CoinSpendSignatureP coin_sig;
      json_t *wire;
      bool tiny;
      bool done;
      uint64_t known_coin_id;
    } deposits;

    struct
    {
      struct TALER_MerchantSignatureP merchant_sig;
      uint64_t rtransaction_id;
      struct TALER_Amount amount_with_fee;
      uint64_t deposit_serial_id;
    } refunds;

    struct
    {
      struct GNUNET_TIME_Absolute execution_date;
      struct TALER_WireTransferIdentifierRawP wtid_raw;
      json_t *wire_target;
      char *exchange_account_section;
      struct TALER_Amount amount;
    } wire_out;

    struct
    {
      uint64_t deposit_serial_id;
      struct TALER_WireTransferIdentifierRawP wtid_raw;
    } aggregation_tracking;

    struct
    {
      char *wire_method;
      struct GNUNET_TIME_Absolute start_date;
      struct GNUNET_TIME_Absolute end_date;
      struct TALER_Amount wire_fee;
      struct TALER_Amount closing_fee;
      struct TALER_MasterSignatureP master_sig;
    } wire_fee;

    struct
    {
      struct TALER_CoinSpendSignatureP coin_sig;
      struct TALER_DenominationBlindingKeyP coin_blind;
      struct TALER_Amount amount;
      struct GNUNET_TIME_Absolute timestamp;
      uint64_t known_coin_id;
      uint64_t reserve_out_serial_id;
    } recoup;

    struct
    {
      struct TALER_CoinSpendSignatureP coin_sig;
      struct TALER_DenominationBlindingKeyP coin_blind;
      struct TALER_Amount amount;
      struct GNUNET_TIME_Absolute timestamp;
      uint64_t known_coin_id;
      uint64_t rrc_serial;
    } recoup_refresh;

  } details;

};


/**
 * Function called on data to replicate in the auditor's database.
 *
 * @param cls closure
 * @param td record from an exchange table
 * @return #GNUNET_OK to continue to iterate,
 *         #GNUNET_SYSERR to fail with an error
 */
typedef int
(*TALER_EXCHANGEDB_ReplicationCallback)(
  void *cls,
  const struct TALER_EXCHANGEDB_TableData *td);


/**
 * @brief All information about a denomination key (which is used to
 * sign coins into existence).
 */
struct TALER_EXCHANGEDB_DenominationKey
{
  /**
   * The private key of the denomination.  Will be NULL if the private
   * key is not available (this is the case after the key has expired
   * for signing coins, but is still valid for depositing coins).
   */
  struct TALER_DenominationPrivateKey denom_priv;

  /**
   * Decoded denomination public key (the hash of it is in
   * @e issue, but we sometimes need the full public key as well).
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * Signed public information about a denomination key.
   */
  struct TALER_EXCHANGEDB_DenominationKeyInformationP issue;
};


/**
 * @brief Information we keep on bank transfer(s) that established a reserve.
 */
struct TALER_EXCHANGEDB_BankTransfer
{

  /**
   * Public key of the reserve that was filled.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Amount that was transferred to the exchange.
   */
  struct TALER_Amount amount;

  /**
   * When did the exchange receive the incoming transaction?
   * (This is the execution date of the exchange's database,
   * the execution date of the bank should be in @e wire).
   */
  struct GNUNET_TIME_Absolute execution_date;

  /**
   * Detailed wire information about the sending account
   * in "payto://" format.
   */
  char *sender_account_details;

  /**
   * Data uniquely identifying the wire transfer (wire transfer-type specific)
   */
  uint64_t wire_reference;

};


/**
 * @brief Information we keep on bank transfer(s) that
 * closed a reserve.
 */
struct TALER_EXCHANGEDB_ClosingTransfer
{

  /**
   * Public key of the reserve that was depleted.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Amount that was transferred to the exchange.
   */
  struct TALER_Amount amount;

  /**
   * Amount that was charged by the exchange.
   */
  struct TALER_Amount closing_fee;

  /**
   * When did the exchange execute the transaction?
   */
  struct GNUNET_TIME_Absolute execution_date;

  /**
   * Detailed wire information about the receiving account
   * in payto://-format.
   */
  char *receiver_account_details;

  /**
   * Detailed wire transfer information that uniquely identifies the
   * wire transfer.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

};


/**
 * @brief A summary of a Reserve
 */
struct TALER_EXCHANGEDB_Reserve
{
  /**
   * The reserve's public key.  This uniquely identifies the reserve
   */
  struct TALER_ReservePublicKeyP pub;

  /**
   * The balance amount existing in the reserve
   */
  struct TALER_Amount balance;

  /**
   * The expiration date of this reserve; funds will be wired back
   * at this time.
   */
  struct GNUNET_TIME_Absolute expiry;

  /**
   * The legal expiration date of this reserve; we will forget about
   * it at this time.
   */
  struct GNUNET_TIME_Absolute gc;
};


/**
 * Meta data about a denomination public key.
 */
struct TALER_EXCHANGEDB_DenominationKeyMetaData
{
  /**
 * Start time of the validity period for this key.
 */
  struct GNUNET_TIME_Absolute start;

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
  struct GNUNET_TIME_Absolute expire_withdraw;

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
  struct GNUNET_TIME_Absolute expire_deposit;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_deposit (by a year or more).
   */
  struct GNUNET_TIME_Absolute expire_legal;

  /**
   * The value of the coins signed with this denomination key.
   */
  struct TALER_Amount value;

  /**
   * The fee the exchange charges when a coin of this type is withdrawn.
   * (can be zero).
   */
  struct TALER_Amount fee_withdraw;

  /**
   * The fee the exchange charges when a coin of this type is deposited.
   * (can be zero).
   */
  struct TALER_Amount fee_deposit;

  /**
   * The fee the exchange charges when a coin of this type is refreshed.
   * (can be zero).
   */
  struct TALER_Amount fee_refresh;

  /**
   * The fee the exchange charges when a coin of this type is refunded.
   * (can be zero).  Note that refund fees are charged to the customer;
   * if a refund is given, the deposit fee is also refunded.
   */
  struct TALER_Amount fee_refund;

};


/**
 * Signature of a function called with information about the exchange's
 * denomination keys.
 *
 * @param cls closure with a `struct TEH_KeyStateHandle *`
 * @param denom_pub public key of the denomination
 * @param h_denom_pub hash of @a denom_pub
 * @param meta meta data information about the denomination type (value, expirations, fees)
 * @param master_sig master signature affirming the validity of this denomination
 * @param recoup_possible true if the key was revoked and clients can currently recoup
 *        coins of this denomination
 */
typedef void
(*TALER_EXCHANGEDB_DenominationsCallback)(
  void *cls,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta,
  const struct TALER_MasterSignatureP *master_sig,
  bool recoup_possible);


/**
 * Signature of a function called with information about the exchange's
 * online signing keys.
 *
 * @param cls closure with a `struct TEH_KeyStateHandle *`
 * @param exchange_pub public key of the exchange
 * @param meta meta data information about the signing type (expirations)
 * @param master_sig master signature affirming the validity of this denomination
 */
typedef void
(*TALER_EXCHANGEDB_ActiveSignkeysCallback)(
  void *cls,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_EXCHANGEDB_SignkeyMetaData *meta,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Function called with information about the exchange's auditors.
 *
 * @param cls closure with a `struct TEH_KeyStateHandle *`
 * @param auditor_pub the public key of the auditor
 * @param auditor_url URL of the REST API of the auditor
 * @param auditor_name human readable official name of the auditor
 */
typedef void
(*TALER_EXCHANGEDB_AuditorsCallback)(
  void *cls,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const char *auditor_url,
  const char *auditor_name);


/**
 * Function called with information about the denominations
 * audited by the exchange's auditors.
 *
 * @param cls closure with a `struct TEH_KeyStateHandle *`
 * @param auditor_pub the public key of an auditor
 * @param h_denom_pub hash of a denomination key audited by this auditor
 * @param auditor_sig signature from the auditor affirming this
 */
typedef void
(*TALER_EXCHANGEDB_AuditorDenominationsCallback)(
  void *cls,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_AuditorSignatureP *auditor_sig);


/**
 * @brief Information we keep for a withdrawn coin to reproduce
 * the /withdraw operation if needed, and to have proof
 * that a reserve was drained by this amount.
 */
struct TALER_EXCHANGEDB_CollectableBlindcoin
{

  /**
   * Our signature over the (blinded) coin.
   */
  struct TALER_DenominationSignature sig;

  /**
   * Hash of the denomination key (which coin was generated).
   */
  struct GNUNET_HashCode denom_pub_hash;

  /**
   * Value of the coin being exchangeed (matching the denomination key)
   * plus the transaction fee.  We include this in what is being
   * signed so that we can verify a reserve's remaining total balance
   * without needing to access the respective denomination key
   * information each time.
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Withdrawal fee charged by the exchange.  This must match the Exchange's
   * denomination key's withdrawal fee.  If the client puts in an
   * invalid withdrawal fee (too high or too low) that does not match
   * the Exchange's denomination key, the withdraw operation is invalid
   * and will be rejected by the exchange.  The @e amount_with_fee minus
   * the @e withdraw_fee is must match the value of the generated
   * coin.  We include this in what is being signed so that we can
   * verify a exchange's accounting without needing to access the
   * respective denomination key information each time.
   */
  struct TALER_Amount withdraw_fee;

  /**
   * Public key of the reserve that was drained.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Hash over the blinded message, needed to verify
   * the @e reserve_sig.
   */
  struct GNUNET_HashCode h_coin_envelope;

  /**
   * Signature confirming the withdrawal, matching @e reserve_pub,
   * @e denom_pub and @e h_coin_envelope.
   */
  struct TALER_ReserveSignatureP reserve_sig;
};


/**
 * Information the exchange records about a recoup request
 * in a reserve history.
 */
struct TALER_EXCHANGEDB_Recoup
{

  /**
   * Information about the coin that was paid back.
   */
  struct TALER_CoinPublicInfo coin;

  /**
   * Blinding factor supplied to prove to the exchange that
   * the coin came from this reserve.
   */
  struct TALER_DenominationBlindingKeyP coin_blind;

  /**
   * Signature of the coin of type
   * #TALER_SIGNATURE_WALLET_COIN_RECOUP.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Public key of the reserve the coin was paid back into.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * How much was the coin still worth at this time?
   */
  struct TALER_Amount value;

  /**
   * When did the recoup operation happen?
   */
  struct GNUNET_TIME_Absolute timestamp;

};


/**
 * Information the exchange records about a recoup request
 * in a coin history.
 */
struct TALER_EXCHANGEDB_RecoupListEntry
{

  /**
   * Blinding factor supplied to prove to the exchange that
   * the coin came from this reserve.
   */
  struct TALER_DenominationBlindingKeyP coin_blind;

  /**
   * Signature of the coin of type
   * #TALER_SIGNATURE_WALLET_COIN_RECOUP.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Hash of the public denomination key used to sign the coin.
   */
  struct GNUNET_HashCode h_denom_pub;

  /**
   * Public key of the reserve the coin was paid back into.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * How much was the coin still worth at this time?
   */
  struct TALER_Amount value;

  /**
   * When did the /recoup operation happen?
   */
  struct GNUNET_TIME_Absolute timestamp;

};


/**
 * Information the exchange records about a recoup-refresh request in
 * a coin transaction history.
 */
struct TALER_EXCHANGEDB_RecoupRefreshListEntry
{

  /**
   * Information about the coin that was paid back
   * (NOT the coin we are considering the history of!)
   */
  struct TALER_CoinPublicInfo coin;

  /**
   * Blinding factor supplied to prove to the exchange that
   * the coin came from this @e old_coin_pub.
   */
  struct TALER_DenominationBlindingKeyP coin_blind;

  /**
   * Signature of the coin of type
   * #TALER_SIGNATURE_WALLET_COIN_RECOUP.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Public key of the old coin that the refreshed coin was paid back to.
   */
  struct TALER_CoinSpendPublicKeyP old_coin_pub;

  /**
   * How much was the coin still worth at this time?
   */
  struct TALER_Amount value;

  /**
   * When did the recoup operation happen?
   */
  struct GNUNET_TIME_Absolute timestamp;

};


/**
 * @brief Types of operations on a reserve.
 */
enum TALER_EXCHANGEDB_ReserveOperation
{
  /**
   * Money was deposited into the reserve via a bank transfer.
   * This is how customers establish a reserve at the exchange.
   */
  TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE = 0,

  /**
   * A Coin was withdrawn from the reserve using /withdraw.
   */
  TALER_EXCHANGEDB_RO_WITHDRAW_COIN = 1,

  /**
   * A coin was returned to the reserve using /recoup.
   */
  TALER_EXCHANGEDB_RO_RECOUP_COIN = 2,

  /**
   * The exchange send inactive funds back from the reserve to the
   * customer's bank account.  This happens when the exchange
   * closes a reserve with a non-zero amount left in it.
   */
  TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK = 3
};


/**
 * @brief Reserve history as a linked list.  Lists all of the transactions
 * associated with this reserve (such as the bank transfers that
 * established the reserve and all /withdraw operations we have done
 * since).
 */
struct TALER_EXCHANGEDB_ReserveHistory
{

  /**
   * Next entry in the reserve history.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *next;

  /**
   * Type of the event, determines @e details.
   */
  enum TALER_EXCHANGEDB_ReserveOperation type;

  /**
   * Details of the operation, depending on @e type.
   */
  union
  {

    /**
     * Details about a bank transfer to the exchange (reserve
     * was established).
     */
    struct TALER_EXCHANGEDB_BankTransfer *bank;

    /**
     * Details about a /withdraw operation.
     */
    struct TALER_EXCHANGEDB_CollectableBlindcoin *withdraw;

    /**
     * Details about a /recoup operation.
     */
    struct TALER_EXCHANGEDB_Recoup *recoup;

    /**
     * Details about a bank transfer from the exchange (reserve
     * was closed).
     */
    struct TALER_EXCHANGEDB_ClosingTransfer *closing;

  } details;

};


/**
 * @brief Data from a deposit operation.  The combination of
 * the coin's public key, the merchant's public key and the
 * transaction ID must be unique.  While a coin can (theoretically) be
 * deposited at the same merchant twice (with partial spending), the
 * merchant must either use a different public key or a different
 * transaction ID for the two transactions.  The same coin must not
 * be used twice at the same merchant for the same transaction
 * (as determined by transaction ID).
 */
struct TALER_EXCHANGEDB_Deposit
{
  /**
   * Information about the coin that is being deposited.
   */
  struct TALER_CoinPublicInfo coin;

  /**
   * ECDSA signature affirming that the customer intends
   * this coin to be deposited at the merchant identified
   * by @e h_wire in relation to the proposal data identified
   * by @e h_contract_terms.
   */
  struct TALER_CoinSpendSignatureP csig;

  /**
   * Public key of the merchant.  Enables later identification
   * of the merchant in case of a need to rollback transactions.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Hash over the proposa data between merchant and customer
   * (remains unknown to the Exchange).
   */
  struct GNUNET_HashCode h_contract_terms;

  /**
   * Hash of the (canonical) representation of @e wire, used
   * to check the signature on the request.  Generated by
   * the exchange from the detailed wire data provided by the
   * merchant.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Detailed information about the receiver for executing the transaction.
   * Includes URL in payto://-format and salt.
   */
  json_t *receiver_wire_account;

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
  struct GNUNET_TIME_Absolute timestamp;

  /**
   * How much time does the merchant have to issue a refund request?
   * Zero if refunds are not allowed.  After this time, the coin
   * cannot be refunded.
   */
  struct GNUNET_TIME_Absolute refund_deadline;

  /**
   * How much time does the merchant have to execute the wire transfer?
   * This time is advisory for aggregating transactions, not a hard
   * constraint (as the merchant can theoretically pick any time,
   * including one in the past).
   */
  struct GNUNET_TIME_Absolute wire_deadline;

  /**
   * Fraction of the coin's remaining value to be deposited, including
   * depositing fee (if any).  The coin is identified by @e coin_pub.
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Depositing fee.
   */
  struct TALER_Amount deposit_fee;

};


/**
 * @brief Specification for a deposit operation in the
 * `struct TALER_EXCHANGEDB_TransactionList`.
 */
struct TALER_EXCHANGEDB_DepositListEntry
{

  /**
   * ECDSA signature affirming that the customer intends
   * this coin to be deposited at the merchant identified
   * by @e h_wire in relation to the proposal data identified
   * by @e h_contract_terms.
   */
  struct TALER_CoinSpendSignatureP csig;

  /**
   * Public key of the merchant.  Enables later identification
   * of the merchant in case of a need to rollback transactions.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Hash over the proposa data between merchant and customer
   * (remains unknown to the Exchange).
   */
  struct GNUNET_HashCode h_contract_terms;

  /**
   * Hash of the (canonical) representation of @e wire, used
   * to check the signature on the request.  Generated by
   * the exchange from the detailed wire data provided by the
   * merchant.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Hash of the public denomination key used to sign the coin.
   */
  struct GNUNET_HashCode h_denom_pub;

  /**
   * Detailed information about the receiver for executing the transaction.
   * Includes URL in payto://-format and salt.
   */
  json_t *receiver_wire_account;

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
  struct GNUNET_TIME_Absolute timestamp;

  /**
   * How much time does the merchant have to issue a refund request?
   * Zero if refunds are not allowed.  After this time, the coin
   * cannot be refunded.
   */
  struct GNUNET_TIME_Absolute refund_deadline;

  /**
   * How much time does the merchant have to execute the wire transfer?
   * This time is advisory for aggregating transactions, not a hard
   * constraint (as the merchant can theoretically pick any time,
   * including one in the past).
   */
  struct GNUNET_TIME_Absolute wire_deadline;

  /**
   * Fraction of the coin's remaining value to be deposited, including
   * depositing fee (if any).  The coin is identified by @e coin_pub.
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Depositing fee.
   */
  struct TALER_Amount deposit_fee;

  /**
   * Has the deposit been wired?
   */
  bool done;

};


/**
 * @brief Specification for a refund operation in a coin's transaction list.
 */
struct TALER_EXCHANGEDB_RefundListEntry
{

  /**
   * Public key of the merchant.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Signature from the merchant affirming the refund.
   */
  struct TALER_MerchantSignatureP merchant_sig;

  /**
   * Hash over the proposal data between merchant and customer
   * (remains unknown to the Exchange).
   */
  struct GNUNET_HashCode h_contract_terms;

  /**
   * Merchant-generated REFUND transaction ID to detect duplicate
   * refunds.
   */
  uint64_t rtransaction_id;

  /**
   * Fraction of the original deposit's value to be refunded, including
   * refund fee (if any).  The coin is identified by @e coin_pub.
   */
  struct TALER_Amount refund_amount;

  /**
   * Refund fee to be covered by the customer.
   */
  struct TALER_Amount refund_fee;

};


/**
 * @brief Specification for a refund operation.  The combination of
 * the coin's public key, the merchant's public key and the
 * transaction ID must be unique.  While a coin can (theoretically) be
 * deposited at the same merchant twice (with partial spending), the
 * merchant must either use a different public key or a different
 * transaction ID for the two transactions.  The same goes for
 * refunds, hence we also have a "rtransaction" ID which is disjoint
 * from the transaction ID.  The same coin must not be used twice at
 * the same merchant for the same transaction or rtransaction ID.
 */
struct TALER_EXCHANGEDB_Refund
{
  /**
   * Information about the coin that is being refunded.
   */
  struct TALER_CoinPublicInfo coin;

  /**
   * Details about the refund.
   */
  struct TALER_EXCHANGEDB_RefundListEntry details;

};


/**
 * @brief Specification for coin in a melt operation.
 */
struct TALER_EXCHANGEDB_Refresh
{
  /**
   * Information about the coin that is being melted.
   */
  struct TALER_CoinPublicInfo coin;

  /**
   * Signature over the melting operation.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Refresh commitment this coin is melted into.
   */
  struct TALER_RefreshCommitmentP rc;

  /**
   * How much value is being melted?  This amount includes the fees,
   * so the final amount contributed to the melt is this value minus
   * the fee for melting the coin.  We include the fee in what is
   * being signed so that we can verify a reserve's remaining total
   * balance without needing to access the respective denomination key
   * information each time.
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Index (smaller #TALER_CNC_KAPPA) which the exchange has chosen to not
   * have revealed during cut and choose.
   */
  uint32_t noreveal_index;

};


/**
 * Information about a /coins/$COIN_PUB/melt operation in a coin transaction history.
 */
struct TALER_EXCHANGEDB_MeltListEntry
{

  /**
   * Signature over the melting operation.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Refresh commitment this coin is melted into.
   */
  struct TALER_RefreshCommitmentP rc;

  /**
   * Hash of the public denomination key used to sign the coin.
   */
  struct GNUNET_HashCode h_denom_pub;

  /**
   * How much value is being melted?  This amount includes the fees,
   * so the final amount contributed to the melt is this value minus
   * the fee for melting the coin.  We include the fee in what is
   * being signed so that we can verify a reserve's remaining total
   * balance without needing to access the respective denomination key
   * information each time.
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Melt fee the exchange charged.
   */
  struct TALER_Amount melt_fee;

  /**
   * Index (smaller #TALER_CNC_KAPPA) which the exchange has chosen to not
   * have revealed during cut and choose.
   */
  uint32_t noreveal_index;

};


/**
 * Information about a melt operation.
 */
struct TALER_EXCHANGEDB_Melt
{

  /**
   * Overall session data.
   */
  struct TALER_EXCHANGEDB_Refresh session;

  /**
   * Melt fee the exchange charged.
   */
  struct TALER_Amount melt_fee;

};


/**
 * @brief Linked list of refresh information linked to a coin.
 */
struct TALER_EXCHANGEDB_LinkList
{
  /**
   * Information is stored in a NULL-terminated linked list.
   */
  struct TALER_EXCHANGEDB_LinkList *next;

  /**
   * Denomination public key, determines the value of the coin.
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * Signature over the blinded envelope.
   */
  struct TALER_DenominationSignature ev_sig;

  /**
   * Signature of the original coin being refreshed over the
   * link data, of type #TALER_SIGNATURE_WALLET_COIN_LINK
   */
  struct TALER_CoinSpendSignatureP orig_coin_link_sig;

};


/**
 * @brief Enumeration to classify the different types of transactions
 * that can be done with a coin.
 */
enum TALER_EXCHANGEDB_TransactionType
{

  /**
   * Deposit operation.
   */
  TALER_EXCHANGEDB_TT_DEPOSIT = 0,

  /**
   * Melt operation.
   */
  TALER_EXCHANGEDB_TT_MELT = 1,

  /**
   * Refund operation.
   */
  TALER_EXCHANGEDB_TT_REFUND = 2,

  /**
   * Recoup-refresh operation (on the old coin, adding to the old coin's value)
   */
  TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP = 3,

  /**
   * Recoup operation.
   */
  TALER_EXCHANGEDB_TT_RECOUP = 4,

  /**
   * Recoup-refresh operation (on the new coin, eliminating its value)
   */
  TALER_EXCHANGEDB_TT_RECOUP_REFRESH = 5

};


/**
 * @brief List of transactions we performed for a particular coin.
 */
struct TALER_EXCHANGEDB_TransactionList
{

  /**
   * Next pointer in the NULL-terminated linked list.
   */
  struct TALER_EXCHANGEDB_TransactionList *next;

  /**
   * Type of the transaction, determines what is stored in @e details.
   */
  enum TALER_EXCHANGEDB_TransactionType type;

  /**
   * Serial ID of this entry in the database.
   */
  uint64_t serial_id;

  /**
   * Details about the transaction, depending on @e type.
   */
  union
  {

    /**
     * Details if transaction was a deposit operation.
     * (#TALER_EXCHANGEDB_TT_DEPOSIT)
     */
    struct TALER_EXCHANGEDB_DepositListEntry *deposit;

    /**
     * Details if transaction was a melt operation.
     * (#TALER_EXCHANGEDB_TT_MELT)
     */
    struct TALER_EXCHANGEDB_MeltListEntry *melt;

    /**
     * Details if transaction was a refund operation.
     * (#TALER_EXCHANGEDB_TT_REFUND)
     */
    struct TALER_EXCHANGEDB_RefundListEntry *refund;

    /**
     * Details if transaction was a recoup-refund operation where
     * this coin was the OLD coin.
     * (#TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP).
     */
    struct TALER_EXCHANGEDB_RecoupRefreshListEntry *old_coin_recoup;

    /**
     * Details if transaction was a recoup operation.
     * (#TALER_EXCHANGEDB_TT_RECOUP)
     */
    struct TALER_EXCHANGEDB_RecoupListEntry *recoup;

    /**
     * Details if transaction was a recoup-refund operation where
     * this coin was the REFRESHED coin.
     * (#TALER_EXCHANGEDB_TT_RECOUP_REFRESH)
     */
    struct TALER_EXCHANGEDB_RecoupRefreshListEntry *recoup_refresh;

  } details;

};


/**
 * @brief Handle for a database session (per-thread, for transactions).
 */
struct TALER_EXCHANGEDB_Session;


/**
 * Function called with details about deposits that have been made,
 * with the goal of executing the corresponding wire transaction.
 *
 * @param cls closure
 * @param rowid unique ID for the deposit in our DB, used for marking
 *              it as 'tiny' or 'done'
 * @param coin_pub public key of the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param deposit_fee amount the exchange gets to keep as transaction fees
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @return transaction status code, #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT to continue to iterate
 */
typedef enum GNUNET_DB_QueryStatus
(*TALER_EXCHANGEDB_MatchingDepositIterator)(
  void *cls,
  uint64_t rowid,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *deposit_fee,
  const struct GNUNET_HashCode *h_contract_terms);


/**
 * Function called with details about deposits that have been made,
 * with the goal of executing the corresponding wire transaction.
 *
 * @param cls closure
 * @param rowid unique ID for the deposit in our DB, used for marking
 *              it as 'tiny' or 'done'
 * @param exchange_timestamp when did the exchange receive the deposit
 * @param wallet_timestamp when did the wallet sign the contract
 * @param merchant_pub public key of the merchant
 * @param coin_pub public key of the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param deposit_fee amount the exchange gets to keep as transaction fees
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @param wire_deadline by which the merchant advised that he would like the
 *        wire transfer to be executed
 * @param receiver_wire_account wire details for the merchant, includes
 *        'url' in payto://-format;
 * @return transaction status code, #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT to continue to iterate
 */
typedef enum GNUNET_DB_QueryStatus
(*TALER_EXCHANGEDB_DepositIterator)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Absolute exchange_timestamp,
  struct GNUNET_TIME_Absolute wallet_timestamp,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *deposit_fee,
  const struct GNUNET_HashCode *h_contract_terms,
  struct GNUNET_TIME_Absolute wire_deadline,
  const json_t *receiver_wire_account);


/**
 * Callback with data about a prepared wire transfer.
 *
 * @param cls closure
 * @param rowid row identifier used to mark prepared transaction as done
 * @param wire_method which wire method is this preparation data for
 * @param buf transaction data that was persisted, NULL on error
 * @param buf_size number of bytes in @a buf, 0 on error
 */
typedef void
(*TALER_EXCHANGEDB_WirePreparationIterator) (void *cls,
                                             uint64_t rowid,
                                             const char *wire_method,
                                             const char *buf,
                                             size_t buf_size);


/**
 * Function called with details about deposits that have been made,
 * with the goal of auditing the deposit's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param exchange_timestamp when did the deposit happen
 * @param wallet_timestamp when did the contract happen
 * @param merchant_pub public key of the merchant
 * @param denom_pub denomination public key of @a coin_pub
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @param refund_deadline by which the merchant advised that he might want
 *        to get a refund
 * @param wire_deadline by which the merchant advised that he would like the
 *        wire transfer to be executed
 * @param receiver_wire_account wire details for the merchant including 'url' in payto://-format;
 *        NULL from iterate_matching_deposits()
 * @param done flag set if the deposit was already executed (or not)
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef int
(*TALER_EXCHANGEDB_DepositCallback)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Absolute exchange_timestamp,
  struct GNUNET_TIME_Absolute wallet_timestamp,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_Amount *amount_with_fee,
  const struct GNUNET_HashCode *h_contract_terms,
  struct GNUNET_TIME_Absolute refund_deadline,
  struct GNUNET_TIME_Absolute wire_deadline,
  const json_t *receiver_wire_account,
  int done);


/**
 * Function called with details about coins that were melted,
 * with the goal of auditing the refresh's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refresh session in our DB
 * @param denom_pub denomination public key of @a coin_pub
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param noreveal_index which index was picked by the exchange in cut-and-choose
 * @param rc what is the commitment
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef int
(*TALER_EXCHANGEDB_RefreshesCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_Amount *amount_with_fee,
  uint32_t noreveal_index,
  const struct TALER_RefreshCommitmentP *rc);


/**
 * Callback invoked with information about refunds applicable
 * to a particular coin and contract.
 *
 * @param cls closure
 * @param amount_with_fee amount being refunded
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef int
(*TALER_EXCHANGEDB_RefundCoinCallback)(
  void *cls,
  const struct TALER_Amount *amount_with_fee);


/**
 * Information about a coin that was revealed to the exchange
 * during reveal.
 */
struct TALER_EXCHANGEDB_RefreshRevealedCoin
{
  /**
   * Public denomination key of the coin.
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * Signature of the original coin being refreshed over the
   * link data, of type #TALER_SIGNATURE_WALLET_COIN_LINK
   */
  struct TALER_CoinSpendSignatureP orig_coin_link_sig;

  /**
   * Blinded message to be signed (in envelope), with @e coin_env_size bytes.
   */
  char *coin_ev;

  /**
   * Number of bytes in @e coin_ev.
   */
  size_t coin_ev_size;

  /**
   * Signature generated by the exchange over the coin (in blinded format).
   */
  struct TALER_DenominationSignature coin_sig;
};


/**
 * Function called with information about a refresh order.
 *
 * @param cls closure
 * @param num_freshcoins size of the @a rrcs array
 * @param rrcs array of @a num_freshcoins information about coins to be created
 * @param num_tprivs number of entries in @a tprivs, should be #TALER_CNC_KAPPA - 1
 * @param tprivs array of @e num_tprivs transfer private keys
 * @param tp transfer public key information
 */
typedef void
(*TALER_EXCHANGEDB_RefreshCallback)(
  void *cls,
  uint32_t num_freshcoins,
  const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
  unsigned int num_tprivs,
  const struct TALER_TransferPrivateKeyP *tprivs,
  const struct TALER_TransferPublicKeyP *tp);


/**
 * Function called with details about coins that were refunding,
 * with the goal of auditing the refund's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refund in our DB
 * @param denom_pub denomination public key of @a coin_pub
 * @param coin_pub public key of the coin
 * @param merchant_pub public key of the merchant
 * @param merchant_sig signature of the merchant
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @param rtransaction_id refund transaction ID chosen by the merchant
 * @param amount_with_fee amount that was deposited including fee
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef int
(*TALER_EXCHANGEDB_RefundCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_MerchantSignatureP *merchant_sig,
  const struct GNUNET_HashCode *h_contract_terms,
  uint64_t rtransaction_id,
  const struct TALER_Amount *amount_with_fee);


/**
 * Function called with details about incoming wire transfers.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refresh session in our DB
 * @param reserve_pub public key of the reserve (also the wire subject)
 * @param credit amount that was received
 * @param sender_account_details information about the sender's bank account, in payto://-format
 * @param wire_reference unique identifier for the wire transfer
 * @param execution_date when did we receive the funds
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef int
(*TALER_EXCHANGEDB_ReserveInCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *credit,
  const char *sender_account_details,
  uint64_t wire_reference,
  struct GNUNET_TIME_Absolute execution_date);


/**
 * Provide information about a wire account.
 *
 * @param cls closure
 * @param payto_uri the exchange bank account URI
 * @param master_sig master key signature affirming that this is a bank
 *                   account of the exchange (of purpose #TALER_SIGNATURE_MASTER_WIRE_DETAILS)
 */
typedef void
(*TALER_EXCHANGEDB_WireAccountCallback)(
  void *cls,
  const char *payto_uri,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Provide information about wire fees.
 *
 * @param cls closure
 * @param wire_fee the wire fee we charge
 * @param closing_fee the closing fee we charge
 * @param start_date from when are these fees valid (start date)
 * @param end_date until when are these fees valid (end date, exclusive)
 * @param master_sig master key signature affirming that this is the correct
 *                   fee (of purpose #TALER_SIGNATURE_MASTER_WIRE_FEES)
 */
typedef void
(*TALER_EXCHANGEDB_WireFeeCallback)(
  void *cls,
  const struct TALER_Amount *wire_fee,
  const struct TALER_Amount *closing_fee,
  struct GNUNET_TIME_Absolute start_date,
  struct GNUNET_TIME_Absolute end_date,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Function called with details about withdraw operations.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refresh session in our DB
 * @param h_blind_ev blinded hash of the coin's public key
 * @param denom_pub public denomination key of the deposited coin
 * @param reserve_pub public key of the reserve
 * @param reserve_sig signature over the withdraw operation
 * @param execution_date when did the wallet withdraw the coin
 * @param amount_with_fee amount that was withdrawn
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef int
(*TALER_EXCHANGEDB_WithdrawCallback)(
  void *cls,
  uint64_t rowid,
  const struct GNUNET_HashCode *h_blind_ev,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Absolute execution_date,
  const struct TALER_Amount *amount_with_fee);


/**
 * Function called with the session hashes and transfer secret
 * information for a given coin.
 *
 * @param cls closure
 * @param transfer_pub public transfer key for the session
 * @param ldl link data for @a transfer_pub
 */
typedef void
(*TALER_EXCHANGEDB_LinkCallback)(
  void *cls,
  const struct TALER_TransferPublicKeyP *transfer_pub,
  const struct TALER_EXCHANGEDB_LinkList *ldl);


/**
 * Function called with the results of the lookup of the wire transfer
 * identifier information.  Only called if we are at least aware of the
 * transaction existing.
 *
 * @param cls closure
 * @param wtid wire transfer identifier, NULL
 *         if the transaction was not yet done
 * @param coin_contribution how much did the coin we asked about
 *        contribute to the total transfer value? (deposit value including fee)
 * @param coin_fee how much did the exchange charge for the deposit fee
 * @param execution_time when was the transaction done, or
 *         when we expect it to be done (if @a wtid was NULL)
 */
typedef void
(*TALER_EXCHANGEDB_WireTransferByCoinCallback)(
  void *cls,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_Amount *coin_contribution,
  const struct TALER_Amount *coin_fee,
  struct GNUNET_TIME_Absolute execution_time);


/**
 * Function called with the results of the lookup of the
 * transaction data associated with a wire transfer identifier.
 *
 * @param cls closure
 * @param rowid which row in the table is the information from (for diagnostics)
 * @param merchant_pub public key of the merchant (should be same for all callbacks with the same @e cls)
 * @param h_wire hash of wire transfer details of the merchant (should be same for all callbacks with the same @e cls)
 * @param account_details which account did the transfer go to?
 * @param exec_time execution time of the wire transfer (should be same for all callbacks with the same @e cls)
 * @param h_contract_terms which proposal was this payment about
 * @param denom_pub denomination of @a coin_pub
 * @param coin_pub which public key was this payment about
 * @param coin_value amount contributed by this coin in total (with fee)
 * @param coin_fee applicable fee for this coin
 */
typedef void
(*TALER_EXCHANGEDB_AggregationDataCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct GNUNET_HashCode *h_wire,
  const json_t *account_details,
  struct GNUNET_TIME_Absolute exec_time,
  const struct GNUNET_HashCode *h_contract_terms,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *coin_fee);


/**
 * Function called with the results of the lookup of the
 * wire transfer data of the exchange.
 *
 * @param cls closure
 * @param rowid identifier of the respective row in the database
 * @param date timestamp of the wire transfer (roughly)
 * @param wtid wire transfer subject
 * @param wire wire transfer details of the receiver, including "url" in payto://-format
 * @param amount amount that was wired
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to stop iteration
 */
typedef int
(*TALER_EXCHANGEDB_WireTransferOutCallback)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Absolute date,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const json_t *wire,
  const struct TALER_Amount *amount);


/**
 * Callback with data about a prepared wire transfer.
 *
 * @param cls closure
 * @param rowid row identifier used to mark prepared transaction as done
 * @param wire_method which wire method is this preparation data for
 * @param buf transaction data that was persisted, NULL on error
 * @param buf_size number of bytes in @a buf, 0 on error
 * @param finished did we complete the transfer yet?
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to stop iteration
 */
typedef int
(*TALER_EXCHANGEDB_WirePreparationCallback)(void *cls,
                                            uint64_t rowid,
                                            const char *wire_method,
                                            const char *buf,
                                            size_t buf_size,
                                            int finished);


/**
 * Function called about recoups the exchange has to perform.
 *
 * @param cls closure
 * @param rowid row identifier used to uniquely identify the recoup operation
 * @param timestamp when did we receive the recoup request
 * @param amount how much should be added back to the reserve
 * @param reserve_pub public key of the reserve
 * @param coin public information about the coin
 * @param denom_pub denomination key of @a coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef int
(*TALER_EXCHANGEDB_RecoupCallback)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Absolute timestamp,
  const struct TALER_Amount *amount,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_CoinPublicInfo *coin,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_DenominationBlindingKeyP *coin_blind);


/**
 * Function called about recoups on refreshed coins the exchange has to
 * perform.
 *
 * @param cls closure
 * @param rowid row identifier used to uniquely identify the recoup operation
 * @param timestamp when did we receive the recoup request
 * @param amount how much should be added back to the reserve
 * @param old_coin_pub original coin that was refreshed to create @a coin
 * @param old_denom_pub_hash hash of public key of @a old_coin_pub
 * @param coin public information about the coin
 * @param denom_pub denomination key of @a coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef int
(*TALER_EXCHANGEDB_RecoupRefreshCallback)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Absolute timestamp,
  const struct TALER_Amount *amount,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  const struct GNUNET_HashCode *old_denom_pub_hash,
  const struct TALER_CoinPublicInfo *coin,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_DenominationBlindingKeyP *coin_blind);


/**
 * Function called about reserve closing operations
 * the aggregator triggered.
 *
 * @param cls closure
 * @param rowid row identifier used to uniquely identify the reserve closing operation
 * @param execution_date when did we execute the close operation
 * @param amount_with_fee how much did we debit the reserve
 * @param closing_fee how much did we charge for closing the reserve
 * @param reserve_pub public key of the reserve
 * @param receiver_account where did we send the funds, in payto://-format
 * @param wtid identifier used for the wire transfer
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef int
(*TALER_EXCHANGEDB_ReserveClosedCallback)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Absolute execution_date,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *closing_fee,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *receiver_account,
  const struct TALER_WireTransferIdentifierRawP *wtid);


/**
 * Function called with details about expired reserves.
 *
 * @param cls closure
 * @param reserve_pub public key of the reserve
 * @param left amount left in the reserve
 * @param account_details information about the reserve's bank account, in payto://-format
 * @param expiration_date when did the reserve expire
 * @return transaction status code to pass on
 */
typedef enum GNUNET_DB_QueryStatus
(*TALER_EXCHANGEDB_ReserveExpiredCallback)(
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *left,
  const char *account_details,
  struct GNUNET_TIME_Absolute expiration_date);


/**
 * Function called with information justifying an aggregate recoup.
 * (usually implemented by the auditor when verifying losses from recoups).
 *
 * @param cls closure
 * @param rowid row identifier used to uniquely identify the recoup operation
 * @param coin information about the coin
 * @param coin_sig signature of the coin of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
 * @param coin_blind blinding key of the coin
 * @param h_blinded_ev blinded envelope, as calculated by the exchange
 * @param amount total amount to be paid back
 */
typedef void
(*TALER_EXCHANGEDB_RecoupJustificationCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_CoinPublicInfo *coin,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_DenominationBlindingKeyP *coin_blind,
  const struct GNUNET_HashCode *h_blinded_ev,
  const struct TALER_Amount *amount);


/**
 * Function called on deposits that are past their due date
 * and have not yet seen a wire transfer.
 *
 * @param cls closure
 * @param rowid deposit table row of the coin's deposit
 * @param coin_pub public key of the coin
 * @param amount value of the deposit, including fee
 * @param wire where should the funds be wired, including 'url' in payto://-format
 * @param deadline what was the requested wire transfer deadline
 * @param tiny did the exchange defer this transfer because it is too small?
 * @param done did the exchange claim that it made a transfer?
 */
typedef void
(*TALER_EXCHANGEDB_WireMissingCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *amount,
  const json_t *wire,
  struct GNUNET_TIME_Absolute deadline,
  /* bool? */ int tiny,
  /* bool? */ int done);


/**
 * Function called with information about the exchange's denomination keys.
 * Note that the 'master' field in @a issue will not yet be initialized when
 * this function is called!
 *
 * @param cls closure
 * @param denom_pub public key of the denomination
 * @param issue detailed information about the denomination (value, expiration times, fees);
 */
typedef void
(*TALER_EXCHANGEDB_DenominationCallback)(
  void *cls,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue);


/**
 * @brief The plugin API, returned from the plugin's "init" function.
 * The argument given to "init" is simply a configuration handle.
 */
struct TALER_EXCHANGEDB_Plugin
{

  /**
   * Closure for all callbacks.
   */
  void *cls;

  /**
   * Name of the library which generated this plugin.  Set by the
   * plugin loader.
   */
  char *library_name;

  /**
   * Get the thread-local (!) database-handle.
   * Connect to the db if the connection does not exist yet.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @returns the database connection, or NULL on error
   */
  struct TALER_EXCHANGEDB_Session *
  (*get_session) (void *cls);


  /**
   * Drop the Taler tables.  This should only be used in testcases.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
   */
  int
  (*drop_tables) (void *cls);


  /**
   * Create the necessary tables if they are not present
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
   */
  int
  (*create_tables) (void *cls);


  /**
   * Start a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param name unique name identifying the transaction (for debugging),
   *             must point to a constant
   * @return #GNUNET_OK on success
   */
  int
  (*start) (void *cls,
            struct TALER_EXCHANGEDB_Session *session,
            const char *name);


  /**
   * Start a READ COMMITTED transaction.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param session the database connection
   * @param name unique name identifying the transaction (for debugging)
   *             must point to a constant
   * @return #GNUNET_OK on success
   */
  int
  (*start_read_committed)(void *cls,
                          struct TALER_EXCHANGEDB_Session *session,
                          const char *name);


  /**
   * Commit a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
  (*commit)(void *cls,
            struct TALER_EXCHANGEDB_Session *session);


  /**
   * Do a pre-flight check that we are not in an uncommitted transaction.
   * If we are, try to commit the previous transaction and output a warning.
   * Does not return anything, as we will continue regardless of the outcome.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param session the database connection
   */
  void
  (*preflight) (void *cls,
                struct TALER_EXCHANGEDB_Session *session);


  /**
   * Abort/rollback a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   */
  void
  (*rollback) (void *cls,
               struct TALER_EXCHANGEDB_Session *session);


  /**
   * Register callback to be invoked on events of type @a es.
   *
   * @param cls database context to use
   * @param session connection to use
   * @param es specification of the event to listen for
   * @param cb function to call when the event happens, possibly
   *         multiple times (until cancel is invoked)
   * @param cb_cls closure for @a cb
   * @return handle useful to cancel the listener
   */
  struct GNUNET_DB_EventHandler *
  (*event_listen)(void *cls,
                  struct TALER_EXCHANGEDB_Session *session,
                  const struct GNUNET_DB_EventHeaderP *es,
                  GNUNET_DB_EventCallback cb,
                  void *cb_cls);

  /**
   * Stop notifications.
   *
   * @param cls database context to use
   * @param eh handle to unregister.
   */
  void
  (*event_listen_cancel)(void *cls,
                         struct GNUNET_DB_EventHandler *eh);


  /**
   * Notify all that listen on @a es of an event.
   *
   * @param cls database context to use
   * @param session connection to use
   * @param es specification of the event to generate
   * @param extra additional event data provided
   * @param extra_size number of bytes in @a extra
   */
  void
  (*event_notify)(void *cls,
                  struct TALER_EXCHANGEDB_Session *session,
                  const struct GNUNET_DB_EventHeaderP *es,
                  const void *extra,
                  size_t extra_size);


  /**
   * Insert information about a denomination key and in particular
   * the properties (value, fees, expiration times) the coins signed
   * with this key have.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param denom_pub the public key used for signing coins of this denomination
   * @param issue issuing information with value, fees and other info about the denomination
   * @return status of the query
   */
  enum GNUNET_DB_QueryStatus
  (*insert_denomination_info)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct TALER_DenominationPublicKey *denom_pub,
    const struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue);


  /**
   * Fetch information about a denomination key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param denom_pub_hash hash of the public key used for signing coins of this denomination
   * @param[out] issue set to issue information with value, fees and other info about the coin
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_denomination_info)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct GNUNET_HashCode *denom_pub_hash,
    struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue);


  /**
   * Function called on every known denomination key.  Runs in its
   * own read-only transaction (hence no session provided).  Note that
   * the "master" field in the callback's 'issue' argument will NOT
   * be initialized yet.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session session to use
   * @param cb function to call on each denomination key
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*iterate_denomination_info)(void *cls,
                               struct TALER_EXCHANGEDB_Session *session,
                               TALER_EXCHANGEDB_DenominationCallback cb,
                               void *cb_cls);


  /**
   * Function called to invoke @a cb on every known denomination key (revoked
   * and non-revoked) that has been signed by the master key. Runs in its own
   * read-only transaction (hence no session provided).
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param cb function to call on each denomination key
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*iterate_denominations)(void *cls,
                           TALER_EXCHANGEDB_DenominationsCallback cb,
                           void *cb_cls);

  /**
   * Function called to invoke @a cb on every non-revoked exchange signing key
   * that has been signed by the master key.  Revoked and (for signing!)
   * expired keys are skipped. Runs in its own read-only transaction (hence no
   * session provided).
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param cb function to call on each signing key
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*iterate_active_signkeys)(void *cls,
                             TALER_EXCHANGEDB_ActiveSignkeysCallback cb,
                             void *cb_cls);


  /**
   * Function called to invoke @a cb on every active auditor. Disabled
   * auditors are skipped. Runs in its own read-only transaction (hence no
   * session provided).
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param cb function to call on each active auditor
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*iterate_active_auditors)(void *cls,
                             TALER_EXCHANGEDB_AuditorsCallback cb,
                             void *cb_cls);


  /**
   * Function called to invoke @a cb on every denomination with an active
   * auditor. Disabled auditors and denominations without auditor are
   * skipped. Runs in its own read-only transaction (hence no session
   * provided).
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param cb function to call on each active auditor-denomination pair
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*iterate_auditor_denominations)(
    void *cls,
    TALER_EXCHANGEDB_AuditorDenominationsCallback cb,
    void *cb_cls);


  /**
   * Get the summary of a reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session the database connection handle
   * @param[in,out] reserve the reserve data.  The public key of the reserve should be set
   *          in this structure; it is used to query the database.  The balance
   *          and expiration are then filled accordingly.
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
  (*reserves_get)(void *cls,
                  struct TALER_EXCHANGEDB_Session *session,
                  struct TALER_EXCHANGEDB_Reserve *reserve);


  /**
   * Insert a incoming transaction into reserves.  New reserves are
   * also created through this function.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session the database session handle
   * @param reserve_pub public key of the reserve
   * @param balance the amount that has to be added to the reserve
   * @param execution_time when was the amount added
   * @param sender_account_details information about the sender's bank account, in payto://-format
   * @param wire_reference unique reference identifying the wire transfer
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*reserves_in_insert)(void *cls,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_ReservePublicKeyP *reserve_pub,
                        const struct TALER_Amount *balance,
                        struct GNUNET_TIME_Absolute execution_time,
                        const char *sender_account_details,
                        const char *exchange_account_name,
                        uint64_t wire_reference);


  /**
   * Obtain the most recent @a wire_reference that was inserted via @e reserves_in_insert.
   * Used by the wirewatch process when resuming.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session the database connection handle
   * @param exchange_account_name name of the section in the exchange's configuration
   *                       for the account that we are tracking here
   * @param[out] wire_reference set to unique reference identifying the wire transfer
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_latest_reserve_in_reference)(void *cls,
                                     struct TALER_EXCHANGEDB_Session *session,
                                     const char *exchange_account_name,
                                     uint64_t *wire_reference);


  /**
   * Locate the response for a withdraw request under the
   * key of the hash of the blinded message.  Used to ensure
   * idempotency of the request.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session database connection to use
   * @param h_blind hash of the blinded coin to be signed (will match
   *                `h_coin_envelope` in the @a collectable to be returned)
   * @param collectable corresponding collectable coin (blind signature)
   *                    if a coin is found
   * @return statement execution status
   */
  enum GNUNET_DB_QueryStatus
  (*get_withdraw_info)(void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       const struct GNUNET_HashCode *h_blind,
                       struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable);


  /**
   * Store collectable coin under the corresponding hash of the blinded
   * message.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session database connection to use
   * @param collectable corresponding collectable coin (blind signature)
   *                    if a coin is found
   * @return statement execution status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_withdraw_info)(void *cls,
                          struct TALER_EXCHANGEDB_Session *session,
                          const struct
                          TALER_EXCHANGEDB_CollectableBlindcoin *collectable);


  /**
   * Get all of the transaction history associated with the specified
   * reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param reserve_pub public key of the reserve
   * @param[out] rhp set to known transaction history (NULL if reserve is unknown)
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
  (*get_reserve_history)(void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const struct TALER_ReservePublicKeyP *reserve_pub,
                         struct TALER_EXCHANGEDB_ReserveHistory **rhp);


  /**
   * Free memory associated with the given reserve history.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param rh history to free.
   */
  void
  (*free_reserve_history) (void *cls,
                           struct TALER_EXCHANGEDB_ReserveHistory *rh);


  /**
   * Count the number of known coins by denomination.
   *
   * @param cls database connection plugin state
   * @param session database session
   * @param denom_pub_hash denomination to count by
   * @return number of coins if non-negative, otherwise an `enum GNUNET_DB_QueryStatus`
   */
  long long
  (*count_known_coins) (void *cls,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct GNUNET_HashCode *denom_pub_hash);


  /**
   * Make sure the given @a coin is known to the database.
   *
   * @param cls database connection plugin state
   * @param session database session
   * @param coin the coin that must be made known
   * @return database transaction status, non-negative on success
   */
  enum TALER_EXCHANGEDB_CoinKnownStatus
  {
    /**
     * The coin was successfully added.
     */
    TALER_EXCHANGEDB_CKS_ADDED = 1,

    /**
     * The coin was already present.
     */
    TALER_EXCHANGEDB_CKS_PRESENT = 0,

    /**
     * Serialization failure.
     */
    TALER_EXCHANGEDB_CKS_SOFT_FAIL = -1,

    /**
     * Hard database failure.
     */
    TALER_EXCHANGEDB_CKS_HARD_FAIL = -2,

    /**
     * Conflicting coin (different denomination key) already in database.
     */
    TALER_EXCHANGEDB_CKS_CONFLICT = -3,
  }
  (*ensure_coin_known)(void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       const struct TALER_CoinPublicInfo *coin);


  /**
   * Retrieve information about the given @a coin from the database.
   *
   * @param cls database connection plugin state
   * @param session database session
   * @param coin the coin that must be made known
   * @return database transaction status, non-negative on success
   */
  enum GNUNET_DB_QueryStatus
  (*get_known_coin)(void *cls,
                    struct TALER_EXCHANGEDB_Session *session,
                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                    struct TALER_CoinPublicInfo *coin_info);


  /**
   * Retrieve the denomination of a known coin.
   *
   * @param cls the plugin closure
   * @param session the database session handle
   * @param coin_pub the public key of the coin to search for
   * @param[out] denom_hash where to store the hash of the coins denomination
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_coin_denomination)(void *cls,
                           struct TALER_EXCHANGEDB_Session *session,
                           const struct TALER_CoinSpendPublicKeyP *coin_pub,
                           struct GNUNET_HashCode *denom_hash);


  /**
   * Check if we have the specified deposit already in the database.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session database connection
   * @param deposit deposit to search for
   * @param check_extras whether to check extra fields or not
   * @param[out] deposit_fee set to the deposit fee the exchange charged
   * @param[out] exchange_timestamp set to the time when the exchange received the deposit
   * @return 1 if we know this operation,
   *         0 if this exact deposit is unknown to us,
   *         otherwise transaction error status
   */
  enum GNUNET_DB_QueryStatus
  (*have_deposit)(void *cls,
                  struct TALER_EXCHANGEDB_Session *session,
                  const struct TALER_EXCHANGEDB_Deposit *deposit,
                  int check_extras,
                  struct TALER_Amount *deposit_fee,
                  struct GNUNET_TIME_Absolute *exchange_timestamp);


  /**
   * Insert information about deposited coin into the database.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param exchange_timestamp time the exchange received the deposit request
   * @param deposit deposit information to store
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_deposit)(void *cls,
                    struct TALER_EXCHANGEDB_Session *session,
                    struct GNUNET_TIME_Absolute exchange_timestamp,
                    const struct TALER_EXCHANGEDB_Deposit *deposit);


  /**
   * Insert information about refunded coin into the database.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param refund refund information to store
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_refund)(void *cls,
                   struct TALER_EXCHANGEDB_Session *session,
                   const struct TALER_EXCHANGEDB_Refund *refund);


  /**
   * Select refunds by @a coin_pub, @a merchant_pub and @a h_contract.
   *
   * @param cls closure of plugin
   * @param session database handle to use
   * @param coin_pub coin to get refunds for
   * @param merchant_pub merchant to get refunds for
   * @param h_contract_pub contract (hash) to get refunds for
   * @param cb function to call for each refund found
   * @param cb_cls closure for @a cb
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*select_refunds_by_coin)(void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct TALER_CoinSpendPublicKeyP *coin_pub,
                            const struct TALER_MerchantPublicKeyP *merchant_pub,
                            const struct GNUNET_HashCode *h_contract,
                            TALER_EXCHANGEDB_RefundCoinCallback cb,
                            void *cb_cls);


  /**
   * Mark a deposit as tiny, thereby declaring that it cannot be executed by
   * itself (only included in a larger aggregation) and should no longer be
   * returned by @e iterate_ready_deposits()
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param deposit_rowid identifies the deposit row to modify
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*mark_deposit_tiny)(void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       uint64_t rowid);


  /**
   * Test if a deposit was marked as done, thereby declaring that it
   * cannot be refunded anymore.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param coin_pub the coin to check for deposit
   * @param merchant_pub merchant to receive the deposit
   * @param h_contract_terms contract terms of the deposit
   * @param h_wire hash of the merchant's wire details
   * @return #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT if is is marked done,
   *         #GNUNET_DB_STATUS_SUCCESS_NO_RESULTS if not,
   *         otherwise transaction error status (incl. deposit unknown)
   */
  enum GNUNET_DB_QueryStatus
  (*test_deposit_done)(void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub,
                       const struct TALER_MerchantPublicKeyP *merchant_pub,
                       const struct GNUNET_HashCode *h_contract_terms,
                       const struct GNUNET_HashCode *h_wire);


  /**
   * Mark a deposit as done, thereby declaring that it cannot be
   * executed at all anymore, and should no longer be returned by
   * @e iterate_ready_deposits() or @e iterate_matching_deposits().
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param deposit_rowid identifies the deposit row to modify
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*mark_deposit_done)(void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       uint64_t rowid);


  /**
   * Obtain information about deposits that are ready to be executed.
   * Such deposits must not be marked as "tiny" or "done", and the
   * execution time and refund deadlines must both be in the past.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param deposit_cb function to call for ONE such deposit
   * @param deposit_cb_cls closure for @a deposit_cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_ready_deposit)(void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       TALER_EXCHANGEDB_DepositIterator deposit_cb,
                       void *deposit_cb_cls);


/**
 * Maximum number of results we return from iterate_matching_deposits().
 *
 * Limit on the number of transactions we aggregate at once.  Note
 * that the limit must be big enough to ensure that when transactions
 * of the smallest possible unit are aggregated, they do surpass the
 * "tiny" threshold beyond which we never trigger a wire transaction!
 */
#define TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT 10000

  /**
   * Obtain information about other pending deposits for the same
   * destination.  Those deposits must not already be "done".
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param h_wire destination of the wire transfer
   * @param merchant_pub public key of the merchant
   * @param deposit_cb function to call for each deposit
   * @param deposit_cb_cls closure for @a deposit_cb
   * @param limit maximum number of matching deposits to return; should
   *        be #TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT, larger values
   *        are not supported, smaller values would be inefficient.
   * @return number of rows processed, 0 if none exist,
   *         transaction status code on error
   */
  enum GNUNET_DB_QueryStatus
  (*iterate_matching_deposits)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct GNUNET_HashCode *h_wire,
    const struct TALER_MerchantPublicKeyP *merchant_pub,
    TALER_EXCHANGEDB_MatchingDepositIterator deposit_cb,
    void *deposit_cb_cls,
    uint32_t limit);


  /**
   * Store new melt commitment data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session database handle to use
   * @param refresh_session operational data to store
   * @return query status for the transaction
   */
  enum GNUNET_DB_QueryStatus
  (*insert_melt)(void *cls,
                 struct TALER_EXCHANGEDB_Session *session,
                 const struct TALER_EXCHANGEDB_Refresh *refresh_session);


  /**
   * Lookup melt commitment data under the given @a rc.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session database handle to use
   * @param rc commitment to use for the lookup
   * @param[out] melt where to store the result; note that
   *             melt->session.coin.denom_sig will be set to NULL
   *             and is not fetched by this routine (as it is not needed by the client)
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
  (*get_melt)(void *cls,
              struct TALER_EXCHANGEDB_Session *session,
              const struct TALER_RefreshCommitmentP *rc,
              struct TALER_EXCHANGEDB_Melt *melt);


  /**
   * Lookup noreveal index of a previous melt operation under the given
   * @a rc.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param session database handle to use
   * @param rc commitment hash to use to locate the operation
   * @param[out] noreveal_index returns the "gamma" value selected by the
   *             exchange which is the index of the transfer key that is
   *             not to be revealed to the exchange
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
  (*get_melt_index)(void *cls,
                    struct TALER_EXCHANGEDB_Session *session,
                    const struct TALER_RefreshCommitmentP *rc,
                    uint32_t *noreveal_index);


  /**
   * Store in the database which coin(s) the wallet wanted to create
   * in a given refresh operation and all of the other information
   * we learned or created in the reveal step.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session database connection
   * @param rc identify commitment and thus refresh operation
   * @param num_rrcs number of coins to generate, size of the @a rrcs array
   * @param rrcs information about the new coins
   * @param num_tprivs number of entries in @a tprivs, should be #TALER_CNC_KAPPA - 1
   * @param tprivs transfer private keys to store
   * @param tp public key to store
   * @return query status for the transaction
   */
  enum GNUNET_DB_QueryStatus
  (*insert_refresh_reveal)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct TALER_RefreshCommitmentP *rc,
    uint32_t num_rrcs,
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
    unsigned int num_tprivs,
    const struct TALER_TransferPrivateKeyP *tprivs,
    const struct TALER_TransferPublicKeyP *tp);


  /**
   * Lookup in the database for the @a num_freshcoins coins that we
   * created in the given refresh operation.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session database connection
   * @param rc identify commitment and thus refresh operation
   * @param cb function to call with the results
   * @param cb_cls closure for @a cb
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
  (*get_refresh_reveal)(void *cls,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_RefreshCommitmentP *rc,
                        TALER_EXCHANGEDB_RefreshCallback cb,
                        void *cb_cls);


  /**
   * Obtain shared secret and transfer public key from the public key of
   * the coin.  This information and the link information returned by
   * @e get_link_data_list() enable the owner of an old coin to determine
   * the private keys of the new coins after the melt.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session database connection
   * @param coin_pub public key of the coin
   * @param ldc function to call for each session the coin was melted into
   * @param ldc_cls closure for @a tdc
   * @return statement execution status
   */
  enum GNUNET_DB_QueryStatus
  (*get_link_data)(void *cls,
                   struct TALER_EXCHANGEDB_Session *session,
                   const struct TALER_CoinSpendPublicKeyP *coin_pub,
                   TALER_EXCHANGEDB_LinkCallback ldc,
                   void *tdc_cls);


  /**
   * Compile a list of all (historic) transactions performed
   * with the given coin (melt, refund, recoup and deposit operations).
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session database connection
   * @param coin_pub coin to investigate
   * @param include_recoup include recoup transactions of the coin?
   * @param[out] tlp set to list of transactions, NULL if coin is fresh
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
  (*get_coin_transactions)(void *cls,
                           struct TALER_EXCHANGEDB_Session *session,
                           const struct TALER_CoinSpendPublicKeyP *coin_pub,
                           int include_recoup,
                           struct TALER_EXCHANGEDB_TransactionList **tlp);


  /**
   * Free linked list of transactions.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param list list to free
   */
  void
  (*free_coin_transaction_list) (void *cls,
                                 struct TALER_EXCHANGEDB_TransactionList *list);


  /**
   * Lookup the list of Taler transactions that was aggregated
   * into a wire transfer by the respective @a raw_wtid.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session database connection
   * @param wtid the raw wire transfer identifier we used
   * @param cb function to call on each transaction found
   * @param cb_cls closure for @a cb
   * @return query status of the transaction
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_wire_transfer)(void *cls,
                          struct TALER_EXCHANGEDB_Session *session,
                          const struct TALER_WireTransferIdentifierRawP *wtid,
                          TALER_EXCHANGEDB_AggregationDataCallback cb,
                          void *cb_cls);


  /**
   * Try to find the wire transfer details for a deposit operation.
   * If we did not execute the deposit yet, return when it is supposed
   * to be executed.
   *
   * @param cls closure
   * @param session database connection
   * @param h_contract_terms hash of the proposal data
   * @param h_wire hash of merchant wire details
   * @param coin_pub public key of deposited coin
   * @param merchant_pub merchant public key
   * @param cb function to call with the result
   * @param cb_cls closure to pass to @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_transfer_by_deposit)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct GNUNET_HashCode *h_contract_terms,
    const struct GNUNET_HashCode *h_wire,
    const struct TALER_CoinSpendPublicKeyP *coin_pub,
    const struct TALER_MerchantPublicKeyP *merchant_pub,
    TALER_EXCHANGEDB_WireTransferByCoinCallback cb,
    void *cb_cls);


  /**
   * Function called to insert aggregation information into the DB.
   *
   * @param cls closure
   * @param session database connection
   * @param wtid the raw wire transfer identifier we used
   * @param deposit_serial_id row in the deposits table for which this is aggregation data
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_aggregation_tracking)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct TALER_WireTransferIdentifierRawP *wtid,
    unsigned long long deposit_serial_id);


  /**
   * Insert wire transfer fee into database.
   *
   * @param cls closure
   * @param session database connection
   * @param wire_method which wire method is the fee about?
   * @param start_date when does the fee go into effect
   * @param end_date when does the fee end being valid
   * @param wire_fee how high is the wire transfer fee
   * @param closing_fee how high is the closing fee
   * @param master_sig signature over the above by the exchange master key
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_wire_fee)(void *cls,
                     struct TALER_EXCHANGEDB_Session *session,
                     const char *wire_method,
                     struct GNUNET_TIME_Absolute start_date,
                     struct GNUNET_TIME_Absolute end_date,
                     const struct TALER_Amount *wire_fee,
                     const struct TALER_Amount *closing_fee,
                     const struct TALER_MasterSignatureP *master_sig);


  /**
   * Obtain wire fee from database.
   *
   * @param cls closure
   * @param session database connection
   * @param type type of wire transfer the fee applies for
   * @param date for which date do we want the fee?
   * @param[out] start_date when does the fee go into effect
   * @param[out] end_date when does the fee end being valid
   * @param[out] wire_fee how high is the wire transfer fee
   * @param[out] closing_fee how high is the closing fee
   * @param[out] master_sig signature over the above by the exchange master key
   * @return query status of the transaction
   */
  enum GNUNET_DB_QueryStatus
  (*get_wire_fee)(void *cls,
                  struct TALER_EXCHANGEDB_Session *session,
                  const char *type,
                  struct GNUNET_TIME_Absolute date,
                  struct GNUNET_TIME_Absolute *start_date,
                  struct GNUNET_TIME_Absolute *end_date,
                  struct TALER_Amount *wire_fee,
                  struct TALER_Amount *closing_fee,
                  struct TALER_MasterSignatureP *master_sig);


  /**
   * Obtain information about expired reserves and their
   * remaining balances.
   *
   * @param cls closure of the plugin
   * @param session database connection
   * @param now timestamp based on which we decide expiration
   * @param rec function to call on expired reserves
   * @param rec_cls closure for @a rec
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
  (*get_expired_reserves)(void *cls,
                          struct TALER_EXCHANGEDB_Session *session,
                          struct GNUNET_TIME_Absolute now,
                          TALER_EXCHANGEDB_ReserveExpiredCallback rec,
                          void *rec_cls);


  /**
   * Insert reserve close operation into database.
   *
   * @param cls closure
   * @param session database connection
   * @param reserve_pub which reserve is this about?
   * @param execution_date when did we perform the transfer?
   * @param receiver_account to which account do we transfer, in payto://-format
   * @param wtid identifier for the wire transfer
   * @param amount_with_fee amount we charged to the reserve
   * @param closing_fee how high is the closing fee
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_reserve_closed)(void *cls,
                           struct TALER_EXCHANGEDB_Session *session,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           struct GNUNET_TIME_Absolute execution_date,
                           const char *receiver_account,
                           const struct TALER_WireTransferIdentifierRawP *wtid,
                           const struct TALER_Amount *amount_with_fee,
                           const struct TALER_Amount *closing_fee);


  /**
   * Function called to insert wire transfer commit data into the DB.
   *
   * @param cls closure
   * @param session database connection
   * @param type type of the wire transfer (i.e. "iban")
   * @param buf buffer with wire transfer preparation data
   * @param buf_size number of bytes in @a buf
   * @return query status code
   */
  enum GNUNET_DB_QueryStatus
  (*wire_prepare_data_insert)(void *cls,
                              struct TALER_EXCHANGEDB_Session *session,
                              const char *type,
                              const char *buf,
                              size_t buf_size);


  /**
   * Function called to mark wire transfer commit data as finished.
   *
   * @param cls closure
   * @param session database connection
   * @param rowid which entry to mark as finished
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*wire_prepare_data_mark_finished)(void *cls,
                                     struct TALER_EXCHANGEDB_Session *session,
                                     uint64_t rowid);


  /**
   * Function called to mark wire transfer as failed.
   *
   * @param cls closure
   * @param session database connection
   * @param rowid which entry to mark as failed
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*wire_prepare_data_mark_failed)(void *cls,
                                   struct TALER_EXCHANGEDB_Session *session,
                                   uint64_t rowid);


  /**
   * Function called to get an unfinished wire transfer
   * preparation data. Fetches at most one item.
   *
   * @param cls closure
   * @param session database connection
   * @param cb function to call for ONE unfinished item
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*wire_prepare_data_get)(void *cls,
                           struct TALER_EXCHANGEDB_Session *session,
                           TALER_EXCHANGEDB_WirePreparationIterator cb,
                           void *cb_cls);


  /**
   * Start a transaction where we transiently violate the foreign
   * constraints on the "wire_out" table as we insert aggregations
   * and only add the wire transfer out at the end.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @return #GNUNET_OK on success
   */
  int
  (*start_deferred_wire_out) (void *cls,
                              struct TALER_EXCHANGEDB_Session *session);


  /**
   * Store information about an outgoing wire transfer that was executed.
   *
   * @param cls closure
   * @param session database connection
   * @param date time of the wire transfer
   * @param wtid subject of the wire transfer
   * @param wire_account details about the receiver account of the wire transfer,
   *        including 'url' in payto://-format
   * @param amount amount that was transmitted
   * @param exchange_account_section configuration section of the exchange specifying the
   *        exchange's bank account being used
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*store_wire_transfer_out)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    struct GNUNET_TIME_Absolute date,
    const struct TALER_WireTransferIdentifierRawP *wtid,
    const json_t *wire_account,
    const char *exchange_account_section,
    const struct TALER_Amount *amount);


  /**
   * Function called to perform "garbage collection" on the
   * database, expiring records we no longer require.
   *
   * @param cls closure
   * @return #GNUNET_OK on success,
   *         #GNUNET_SYSERR on DB errors
   */
  int
  (*gc) (void *cls);


  /**
   * Select deposits above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param session database connection
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_deposits_above_serial_id)(void *cls,
                                     struct TALER_EXCHANGEDB_Session *session,
                                     uint64_t serial_id,
                                     TALER_EXCHANGEDB_DepositCallback cb,
                                     void *cb_cls);

  /**
   * Select refresh sessions above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param session database connection
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_refreshes_above_serial_id)(void *cls,
                                      struct TALER_EXCHANGEDB_Session *session,
                                      uint64_t serial_id,
                                      TALER_EXCHANGEDB_RefreshesCallback cb,
                                      void *cb_cls);


  /**
   * Select refunds above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param session database connection
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_refunds_above_serial_id)(void *cls,
                                    struct TALER_EXCHANGEDB_Session *session,
                                    uint64_t serial_id,
                                    TALER_EXCHANGEDB_RefundCallback cb,
                                    void *cb_cls);


  /**
   * Select inbound wire transfers into reserves_in above @a serial_id
   * in monotonically increasing order.
   *
   * @param cls closure
   * @param session database connection
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_reserves_in_above_serial_id)(void *cls,
                                        struct TALER_EXCHANGEDB_Session *session,
                                        uint64_t serial_id,
                                        TALER_EXCHANGEDB_ReserveInCallback cb,
                                        void *cb_cls);


  /**
   * Select inbound wire transfers into reserves_in above @a serial_id
   * in monotonically increasing order by @a account_name.
   *
   * @param cls closure
   * @param session database connection
   * @param account_name name of the account for which we do the selection
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_reserves_in_above_serial_id_by_account)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const char *account_name,
    uint64_t serial_id,
    TALER_EXCHANGEDB_ReserveInCallback cb,
    void *cb_cls);


  /**
   * Select withdraw operations from reserves_out above @a serial_id
   * in monotonically increasing order.
   *
   * @param cls closure
   * @param session database connection
   * @param account_name name of the account for which we do the selection
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_withdrawals_above_serial_id)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    uint64_t serial_id,
    TALER_EXCHANGEDB_WithdrawCallback cb,
    void *cb_cls);


  /**
   * Function called to select outgoing wire transfers the exchange
   * executed, ordered by serial ID (monotonically increasing).
   *
   * @param cls closure
   * @param session database connection
   * @param serial_id lowest serial ID to include (select larger or equal)
   * @param cb function to call for ONE unfinished item
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_wire_out_above_serial_id)(void *cls,
                                     struct TALER_EXCHANGEDB_Session *session,
                                     uint64_t serial_id,
                                     TALER_EXCHANGEDB_WireTransferOutCallback cb,
                                     void *cb_cls);

  /**
   * Function called to select outgoing wire transfers the exchange
   * executed, ordered by serial ID (monotonically increasing).
   *
   * @param cls closure
   * @param session database connection
   * @param account_name name to select by
   * @param serial_id lowest serial ID to include (select larger or equal)
   * @param cb function to call for ONE unfinished item
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_wire_out_above_serial_id_by_account)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const char *account_name,
    uint64_t serial_id,
    TALER_EXCHANGEDB_WireTransferOutCallback cb,
    void *cb_cls);


  /**
   * Function called to select recoup requests the exchange
   * received, ordered by serial ID (monotonically increasing).
   *
   * @param cls closure
   * @param session database connection
   * @param serial_id lowest serial ID to include (select larger or equal)
   * @param cb function to call for ONE unfinished item
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_recoup_above_serial_id)(void *cls,
                                   struct TALER_EXCHANGEDB_Session *session,
                                   uint64_t serial_id,
                                   TALER_EXCHANGEDB_RecoupCallback cb,
                                   void *cb_cls);


  /**
   * Function called to select recoup requests the exchange received for
   * refreshed coins, ordered by serial ID (monotonically increasing).
   *
   * @param cls closure
   * @param session database connection
   * @param serial_id lowest serial ID to include (select larger or equal)
   * @param cb function to call for ONE unfinished item
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_recoup_refresh_above_serial_id)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    uint64_t serial_id,
    TALER_EXCHANGEDB_RecoupRefreshCallback cb,
    void *cb_cls);


  /**
   * Function called to select reserve close operations the aggregator
   * triggered, ordered by serial ID (monotonically increasing).
   *
   * @param cls closure
   * @param session database connection
   * @param serial_id lowest serial ID to include (select larger or equal)
   * @param cb function to call
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_reserve_closed_above_serial_id)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    uint64_t serial_id,
    TALER_EXCHANGEDB_ReserveClosedCallback cb,
    void *cb_cls);


  /**
   * Function called to add a request for an emergency recoup for a
   * coin.  The funds are to be added back to the reserve.
   *
   * @param cls closure
   * @param session database connection
   * @param reserve_pub public key of the reserve that is being refunded
   * @param coin public information about a coin
   * @param coin_sig signature of the coin of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
   * @param coin_blind blinding key of the coin
   * @param h_blind_ev blinded envelope, as calculated by the exchange
   * @param amount total amount to be paid back
   * @param h_blind_ev hash of the blinded coin's envelope (must match reserves_out entry)
   * @param timestamp the timestamp to store
   * @return transaction result status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_recoup_request)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    const struct TALER_CoinPublicInfo *coin,
    const struct TALER_CoinSpendSignatureP *coin_sig,
    const struct TALER_DenominationBlindingKeyP *coin_blind,
    const struct TALER_Amount *amount,
    const struct GNUNET_HashCode *h_blind_ev,
    struct GNUNET_TIME_Absolute timestamp);


  /**
   * Function called to add a request for an emergency recoup for a
   * refreshed coin.  The funds are to be added back to the original coin.
   *
   * @param cls closure
   * @param session database connection
   * @param coin public information about the refreshed coin
   * @param coin_sig signature of the coin of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
   * @param coin_blind blinding key of the coin
   * @param h_blind_ev blinded envelope, as calculated by the exchange
   * @param amount total amount to be paid back
   * @param h_blind_ev hash of the blinded coin's envelope (must match reserves_out entry)
   * @param timestamp a timestamp to store
   * @return transaction result status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_recoup_refresh_request)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct TALER_CoinPublicInfo *coin,
    const struct TALER_CoinSpendSignatureP *coin_sig,
    const struct TALER_DenominationBlindingKeyP *coin_blind,
    const struct TALER_Amount *amount,
    const struct GNUNET_HashCode *h_blind_ev,
    struct GNUNET_TIME_Absolute timestamp);


  /**
   * Obtain information about which reserve a coin was generated
   * from given the hash of the blinded coin.
   *
   * @param cls closure
   * @param session a session
   * @param h_blind_ev hash of the blinded coin
   * @param[out] reserve_pub set to information about the reserve (on success only)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_reserve_by_h_blind)(void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct GNUNET_HashCode *h_blind_ev,
                            struct TALER_ReservePublicKeyP *reserve_pub);


  /**
   * Obtain information about which old coin a coin was refreshed
   * given the hash of the blinded (fresh) coin.
   *
   * @param cls closure
   * @param session a session
   * @param h_blind_ev hash of the blinded coin
   * @param[out] old_coin_pub set to information about the old coin (on success only)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_old_coin_by_h_blind)(void *cls,
                             struct TALER_EXCHANGEDB_Session *session,
                             const struct GNUNET_HashCode *h_blind_ev,
                             struct TALER_CoinSpendPublicKeyP *old_coin_pub);


  /**
   * Store information that a denomination key was revoked
   * in the database.
   *
   * @param cls closure
   * @param session a session
   * @param denom_pub_hash hash of the revoked denomination key
   * @param master_sig signature affirming the revocation
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_denomination_revocation)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct GNUNET_HashCode *denom_pub_hash,
    const struct TALER_MasterSignatureP *master_sig);


  /**
   * Obtain information about a denomination key's revocation from
   * the database.
   *
   * @param cls closure
   * @param session a session
   * @param denom_pub_hash hash of the revoked denomination key
   * @param[out] master_sig signature affirming the revocation
   * @param[out] rowid row where the information is stored
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_denomination_revocation)(void *cls,
                                 struct TALER_EXCHANGEDB_Session *session,
                                 const struct GNUNET_HashCode *denom_pub_hash,
                                 struct TALER_MasterSignatureP *master_sig,
                                 uint64_t *rowid);


  /**
   * Select all of those deposits in the database for which we do
   * not have a wire transfer (or a refund) and which should have
   * been deposited between @a start_date and @a end_date.
   *
   * @param cls closure
   * @param session a session
   * @param start_date lower bound on the requested wire execution date
   * @param end_date upper bound on the requested wire execution date
   * @param cb function to call on all such deposits
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_deposits_missing_wire)(void *cls,
                                  struct TALER_EXCHANGEDB_Session *session,
                                  struct GNUNET_TIME_Absolute start_date,
                                  struct GNUNET_TIME_Absolute end_date,
                                  TALER_EXCHANGEDB_WireMissingCallback cb,
                                  void *cb_cls);


  /**
   * Check the last date an auditor was modified.
   *
   * @param cls closure
   * @param session a session
   * @param auditor_pub key to look up information for
   * @param[out] last_date last modification date to auditor status
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_auditor_timestamp)(void *cls,
                              struct TALER_EXCHANGEDB_Session *session,
                              const struct TALER_AuditorPublicKeyP *auditor_pub,
                              struct GNUNET_TIME_Absolute *last_date);


  /**
   * Lookup current state of an auditor.
   *
   * @param cls closure
   * @param session a session
   * @param auditor_pub key to look up information for
   * @param[out] auditor_url set to the base URL of the auditor's REST API; memory to be
   *            released by the caller!
   * @param[out] enabled set if the auditor is currently in use
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_auditor_status)(void *cls,
                           struct TALER_EXCHANGEDB_Session *session,
                           const struct TALER_AuditorPublicKeyP *auditor_pub,
                           char **auditor_url,
                           bool *enabled);


  /**
   * Insert information about an auditor that will audit this exchange.
   *
   * @param cls closure
   * @param session a session
   * @param auditor_pub key of the auditor
   * @param auditor_url base URL of the auditor's REST service
   * @param auditor_name name of the auditor (for humans)
   * @param start_date date when the auditor was added by the offline system
   *                      (only to be used for replay detection)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor)(void *cls,
                    struct TALER_EXCHANGEDB_Session *session,
                    const struct TALER_AuditorPublicKeyP *auditor_pub,
                    const char *auditor_url,
                    const char *auditor_name,
                    struct GNUNET_TIME_Absolute start_date);


  /**
   * Update information about an auditor that will audit this exchange.
   *
   * @param cls closure
   * @param session a session
   * @param auditor_pub key of the auditor (primary key for the existing record)
   * @param auditor_url base URL of the auditor's REST service, to be updated
   * @param auditor_name name of the auditor (for humans)
   * @param change_date date when the auditor status was last changed
   *                      (only to be used for replay detection)
   * @param enabled true to enable, false to disable
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_auditor)(void *cls,
                    struct TALER_EXCHANGEDB_Session *session,
                    const struct TALER_AuditorPublicKeyP *auditor_pub,
                    const char *auditor_url,
                    const char *auditor_name,
                    struct GNUNET_TIME_Absolute change_date,
                    bool enabled);


  /**
   * Check the last date an exchange wire account was modified.
   *
   * @param cls closure
   * @param session a session
   * @param payto_uri key to look up information for
   * @param[out] last_date last modification date to auditor status
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_wire_timestamp)(void *cls,
                           struct TALER_EXCHANGEDB_Session *session,
                           const char *payto_uri,
                           struct GNUNET_TIME_Absolute *last_date);


  /**
   * Insert information about an wire account used by this exchange.
   *
   * @param cls closure
   * @param session a session
   * @param payto_uri wire account of the exchange
   * @param start_date date when the account was added by the offline system
   *                      (only to be used for replay detection)
   * @param master_sig public signature affirming the existence of the account,
   *         must be of purpose #TALER_SIGNATURE_MASTER_WIRE_DETAILS
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_wire)(void *cls,
                 struct TALER_EXCHANGEDB_Session *session,
                 const char *payto_uri,
                 struct GNUNET_TIME_Absolute start_date,
                 const struct TALER_MasterSignatureP *master_sig);


  /**
   * Update information about a wire account of the exchange.
   *
   * @param cls closure
   * @param session a session
   * @param payto_uri account the update is about
   * @param change_date date when the account status was last changed
   *                      (only to be used for replay detection)
   * @param enabled true to enable, false to disable (the actual change)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_wire)(void *cls,
                 struct TALER_EXCHANGEDB_Session *session,
                 const char *payto_uri,
                 struct GNUNET_TIME_Absolute change_date,
                 bool enabled);


  /**
   * Obtain information about the enabled wire accounts of the exchange.
   *
   * @param cls closure
   * @param cb function to call on each account
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_wire_accounts)(void *cls,
                       TALER_EXCHANGEDB_WireAccountCallback cb,
                       void *cb_cls);


  /**
   * Obtain information about the fee structure of the exchange for
   * a given @a wire_method
   *
   * @param cls closure
   * @param wire_method which wire method to obtain fees for
   * @param cb function to call on each account
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_wire_fees)(void *cls,
                   const char *wire_method,
                   TALER_EXCHANGEDB_WireFeeCallback cb,
                   void *cb_cls);


  /**
   * Store information about a revoked online signing key.
   *
   * @param cls closure
   * @param session a session (can be NULL)
   * @param exchange_pub exchange online signing key that was revoked
   * @param master_sig signature affirming the revocation
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_signkey_revocation)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct TALER_ExchangePublicKeyP *exchange_pub,
    const struct TALER_MasterSignatureP *master_sig);


  /**
   * Obtain information about a revoked online signing key.
   *
   * @param cls closure
   * @param session a session (can be NULL)
   * @param exchange_pub exchange online signing key that was revoked
   * @param[out] master_sig signature affirming the revocation
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_signkey_revocation)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct TALER_ExchangePublicKeyP *exchange_pub,
    struct TALER_MasterSignatureP *master_sig);


  /**
   * Lookup information about current denomination key.
   *
   * @param cls closure
   * @param session a session
   * @param h_denom_pub hash of the denomination public key
   * @param[out] meta set to various meta data about the key
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_denomination_key)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct GNUNET_HashCode *h_denom_pub,
    struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta);


  /**
   * Add denomination key.
   *
   * @param cls closure
   * @param session a session
   * @param h_denom_pub hash of the denomination public key
   * @param denom_pub the denomination public key
   * @param meta meta data about the denomination
   * @param master_sig master signature to add
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*add_denomination_key)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct GNUNET_HashCode *h_denom_pub,
    const struct TALER_DenominationPublicKey *denom_pub,
    const struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta,
    const struct TALER_MasterSignatureP *master_sig);


  /**
   * Activate future signing key, turning it into a "current" or "valid"
   * denomination key by adding the master signature.
   *
   * @param cls closure
   * @param session a session
   * @param exchange_pub the exchange online signing public key
   * @param meta meta data about @a exchange_pub
   * @param master_sig master signature to add
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*activate_signing_key)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct TALER_ExchangePublicKeyP *exchange_pub,
    const struct TALER_EXCHANGEDB_SignkeyMetaData *meta,
    const struct TALER_MasterSignatureP *master_sig);


  /**
   * Lookup signing key meta data.
   *
   * @param cls closure
   * @param session a session
   * @param exchange_pub the exchange online signing public key
   * @param[out] meta meta data about @a exchange_pub
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_signing_key)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct TALER_ExchangePublicKeyP *exchange_pub,
    struct TALER_EXCHANGEDB_SignkeyMetaData *meta);


  /**
   * Insert information about an auditor auditing a denomination key.
   *
   * @param cls closure
   * @param session a session
   * @param h_denom_pub the audited denomination
   * @param auditor_pub the auditor's key
   * @param auditor_sig signature affirming the auditor's audit activity
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor_denom_sig)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct GNUNET_HashCode *h_denom_pub,
    const struct TALER_AuditorPublicKeyP *auditor_pub,
    const struct TALER_AuditorSignatureP *auditor_sig);


  /**
   * Obtain information about an auditor auditing a denomination key.
   *
   * @param cls closure
   * @param session a session
   * @param h_denom_pub the audited denomination
   * @param auditor_pub the auditor's key
   * @param[out] auditor_sig set to signature affirming the auditor's audit activity
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_auditor_denom_sig)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const struct GNUNET_HashCode *h_denom_pub,
    const struct TALER_AuditorPublicKeyP *auditor_pub,
    struct TALER_AuditorSignatureP *auditor_sig);


  /**
   * Lookup information about known wire fees.
   *
   * @param cls closure
   * @param session a session
   * @param wire_method the wire method to lookup fees for
   * @param start_time starting time of fee
   * @param end_time end time of fee
   * @param[out] wire_fee wire fee for that time period; if
   *             different wire fee exists within this time
   *             period, an 'invalid' amount is returned.
   * @param[out] closing_fee wire fee for that time period; if
   *             different wire fee exists within this time
   *             period, an 'invalid' amount is returned.
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_wire_fee_by_time)(
    void *cls,
    struct TALER_EXCHANGEDB_Session *session,
    const char *wire_method,
    struct GNUNET_TIME_Absolute start_time,
    struct GNUNET_TIME_Absolute end_time,
    struct TALER_Amount *wire_fee,
    struct TALER_Amount *closing_fee);


  /**
   * Lookup the latest serial number of @a table.  Used in
   * exchange-auditor database replication.
   *
   * @param cls closure
   * @param session a session
   * @param table table for which we should return the serial
   * @param[out] latest serial number in use
   * @return transaction status code, #GNUNET_DB_STATUS_HARD_ERROR if
   *         @a table does not have a serial number
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_serial_by_table)(void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            enum TALER_EXCHANGEDB_ReplicatedTable table,
                            uint64_t *serial);

  /**
   * Lookup records above @a serial number in @a table. Used in
   * exchange-auditor database replication.
   *
   * @param cls closure
   * @param session a session
   * @param table table for which we should return the serial
   * @param serial largest serial number to exclude
   * @param cb function to call on the records
   * @param cb_cls closure for @a cb
   * @return transaction status code, GNUNET_DB_STATUS_HARD_ERROR if
   *         @a table does not have a serial number
   */
  enum GNUNET_DB_QueryStatus
  (*lookup_records_by_table)(void *cls,
                             struct TALER_EXCHANGEDB_Session *session,
                             enum TALER_EXCHANGEDB_ReplicatedTable table,
                             uint64_t serial,
                             TALER_EXCHANGEDB_ReplicationCallback cb,
                             void *cb_cls);


  /**
   * Insert record set into @a table.  Used in exchange-auditor database
   * replication.
   *
   * @param cls closure
   * @param session a session
   * @param tb table data to insert
   * @return transaction status code, #GNUNET_DB_STATUS_HARD_ERROR if
   *         @a table does not have a serial number
   */
  enum GNUNET_DB_QueryStatus
  (*insert_records_by_table)(void *cls,
                             struct TALER_EXCHANGEDB_Session *session,
                             const struct TALER_EXCHANGEDB_TableData *td);


  /**
   * Function called to grab a work shard on an operation @a op. Runs in its
   * own transaction (hence no session provided).
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param job_name name of the operation to grab a word shard for
   * @param delay minimum age of a shard to grab
   * @param size desired shard size
   * @param[out] start_row inclusive start row of the shard (returned)
   * @param[out] end_row exclusive end row of the shard (returned)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*begin_shard)(void *cls,
                 const char *job_name,
                 struct GNUNET_TIME_Relative delay,
                 uint64_t shard_size,
                 uint64_t *start_row,
                 uint64_t *end_row);


  /**
   * Function called to persist that work on a shard was completed.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session a session
   * @param job_name name of the operation to grab a word shard for
   * @param start_row inclusive start row of the shard
   * @param end_row exclusive end row of the shard
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*complete_shard)(void *cls,
                    struct TALER_EXCHANGEDB_Session *session,
                    const char *job_name,
                    uint64_t start_row,
                    uint64_t end_row);

};

#endif /* _TALER_EXCHANGE_DB_H */
