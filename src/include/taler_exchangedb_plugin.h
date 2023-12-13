/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @author Özgür Kesim
 */
#ifndef TALER_EXCHANGEDB_PLUGIN_H
#define TALER_EXCHANGEDB_PLUGIN_H
#include <jansson.h>
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_db_lib.h>
#include "taler_json_lib.h"
#include "taler_signatures.h"
#include "taler_extensions_policy.h"

/**
 * The conflict that can occur for the age restriction
 */
enum TALER_EXCHANGEDB_AgeCommitmentHash_Conflict
{
  /* Value OK, no conflict */
  TALER_AgeCommitmentHash_NoConflict    = 0,

  /* Given hash had a value, but NULL (or zero) was expected */
  TALER_AgeCommitmentHash_NullExpected  = 1,

  /* Given hash was NULL, but value was expected */
  TALER_AgeCommitmentHash_ValueExpected = 2,

  /* Given hash differs from value in the known coin */
  TALER_AgeCommitmentHash_ValueDiffers  = 3,
};

/**
 * Per-coin information returned when doing a batch insert.
 */
struct TALER_EXCHANGEDB_CoinInfo
{
  /**
   * Row of the coin in the known_coins table.
   */
  uint64_t known_coin_id;

  /**
   * Hash of the denomination, relevant on @e denom_conflict.
   */
  struct TALER_DenominationHashP denom_hash;

  /**
   * Hash of the age commitment, relevant on @e age_conflict.
   */
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * True if the coin was known previously.
   */
  bool existed;

  /**
   * True if the known coin has a different denomination;
   * application will find denomination of the already
   * known coin in @e denom_hash.
   */
  bool denom_conflict;

  /**
   * Indicates if and what kind of conflict with the age
   * restriction of the known coin was present;
   * application will find age commitment of the already
   * known coin in @e h_age_commitment.
   */
  enum TALER_EXCHANGEDB_AgeCommitmentHash_Conflict age_conflict;
};


/**
 * Information about a denomination key.
 */
struct TALER_EXCHANGEDB_DenominationKeyInformation
{

  /**
   * Signature over this struct to affirm the validity of the key.
   */
  struct TALER_MasterSignatureP signature;

  /**
   * Start time of the validity period for this key.
   */
  struct GNUNET_TIME_Timestamp start;

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
  struct GNUNET_TIME_Timestamp expire_withdraw;

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
  struct GNUNET_TIME_Timestamp expire_deposit;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_deposit (by a year or more).
   */
  struct GNUNET_TIME_Timestamp expire_legal;

  /**
   * The value of the coins signed with this denomination key.
   */
  struct TALER_Amount value;

  /**
   * Fees for the coin.
   */
  struct TALER_DenomFeeSet fees;

  /**
   * Hash code of the denomination public key. (Used to avoid having
   * the variable-size RSA key in this struct.)
   */
  struct TALER_DenominationHashP denom_hash;

  /**
   * If denomination was setup for age restriction, non-zero age mask.
   * Note that the mask is not part of the signature.
   */
  struct TALER_AgeMask age_mask;
};


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Events signalling that a coin deposit status
 * changed.
 */
struct TALER_CoinDepositEventP
{
  /**
   * Of type #TALER_DBEVENT_EXCHANGE_DEPOSIT_STATUS_CHANGED.
   */
  struct GNUNET_DB_EventHeaderP header;

  /**
   * Public key of the merchant.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

};

/**
 * Events signalling a reserve got funding.
 */
struct TALER_ReserveEventP
{
  /**
   * Of type #TALER_DBEVENT_EXCHANGE_RESERVE_INCOMING.
   */
  struct GNUNET_DB_EventHeaderP header;

  /**
   * Public key of the reserve the event is about.
   */
  struct TALER_ReservePublicKeyP reserve_pub;
};


/**
 * Signature of events signalling a purse changed its status.
 */
struct TALER_PurseEventP
{
  /**
   * Of type #TALER_DBEVENT_EXCHANGE_PURSE_MERGED or
   * #TALER_DBEVENT_EXCHANGE_PURSE_DEPOSITED.
   */
  struct GNUNET_DB_EventHeaderP header;

  /**
   * Public key of the purse the event is about.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;
};


/**
 * Signature of events signalling a KYC process was completed.
 */
struct TALER_KycCompletedEventP
{
  /**
   * Of type #TALER_DBEVENT_EXCHANGE_KYC_COMPLETED.
   */
  struct GNUNET_DB_EventHeaderP header;

  /**
   * Public key of the reserve the event is about.
   */
  struct TALER_PaytoHashP h_payto;
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
  struct GNUNET_TIME_Timestamp start;

  /**
   * The exchange will sign messages with this key between @e start and this time.
   */
  struct GNUNET_TIME_Timestamp expire_sign;

  /**
   * When do signatures with this sign key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_sign (by a year or more).
   */
  struct GNUNET_TIME_Timestamp expire_legal;

};


/**
 * Enumeration of all of the tables replicated by exchange-auditor
 * database replication.
 */
enum TALER_EXCHANGEDB_ReplicatedTable
{
  /* From exchange-0002.sql: */
  TALER_EXCHANGEDB_RT_DENOMINATIONS,
  TALER_EXCHANGEDB_RT_DENOMINATION_REVOCATIONS,
  TALER_EXCHANGEDB_RT_WIRE_TARGETS,
  TALER_EXCHANGEDB_RT_LEGITIMIZATION_PROCESSES,
  TALER_EXCHANGEDB_RT_LEGITIMIZATION_REQUIREMENTS,
  TALER_EXCHANGEDB_RT_RESERVES,
  TALER_EXCHANGEDB_RT_RESERVES_IN,
  TALER_EXCHANGEDB_RT_RESERVES_CLOSE,
  TALER_EXCHANGEDB_RT_RESERVES_OPEN_REQUESTS,
  TALER_EXCHANGEDB_RT_RESERVES_OPEN_DEPOSITS,
  TALER_EXCHANGEDB_RT_RESERVES_OUT,
  TALER_EXCHANGEDB_RT_AUDITORS,
  TALER_EXCHANGEDB_RT_AUDITOR_DENOM_SIGS,
  TALER_EXCHANGEDB_RT_EXCHANGE_SIGN_KEYS,
  TALER_EXCHANGEDB_RT_SIGNKEY_REVOCATIONS,
  TALER_EXCHANGEDB_RT_KNOWN_COINS,
  TALER_EXCHANGEDB_RT_REFRESH_COMMITMENTS,
  TALER_EXCHANGEDB_RT_REFRESH_REVEALED_COINS,
  TALER_EXCHANGEDB_RT_REFRESH_TRANSFER_KEYS,
  TALER_EXCHANGEDB_RT_BATCH_DEPOSITS,
  TALER_EXCHANGEDB_RT_COIN_DEPOSITS,
  TALER_EXCHANGEDB_RT_REFUNDS,
  TALER_EXCHANGEDB_RT_WIRE_OUT,
  TALER_EXCHANGEDB_RT_AGGREGATION_TRACKING,
  TALER_EXCHANGEDB_RT_WIRE_FEE,
  TALER_EXCHANGEDB_RT_GLOBAL_FEE,
  TALER_EXCHANGEDB_RT_RECOUP,
  TALER_EXCHANGEDB_RT_RECOUP_REFRESH,
  TALER_EXCHANGEDB_RT_EXTENSIONS,
  TALER_EXCHANGEDB_RT_POLICY_DETAILS,
  TALER_EXCHANGEDB_RT_POLICY_FULFILLMENTS,
  TALER_EXCHANGEDB_RT_PURSE_REQUESTS,
  TALER_EXCHANGEDB_RT_PURSE_DECISION,
  TALER_EXCHANGEDB_RT_PURSE_MERGES,
  TALER_EXCHANGEDB_RT_PURSE_DEPOSITS,
  TALER_EXCHANGEDB_RT_ACCOUNT_MERGES,
  TALER_EXCHANGEDB_RT_HISTORY_REQUESTS,
  TALER_EXCHANGEDB_RT_CLOSE_REQUESTS,
  TALER_EXCHANGEDB_RT_WADS_OUT,
  TALER_EXCHANGEDB_RT_WADS_OUT_ENTRIES,
  TALER_EXCHANGEDB_RT_WADS_IN,
  TALER_EXCHANGEDB_RT_WADS_IN_ENTRIES,
  TALER_EXCHANGEDB_RT_PROFIT_DRAINS,
  /* From exchange-0003.sql: */
  TALER_EXCHANGEDB_RT_AML_STAFF,
  TALER_EXCHANGEDB_RT_AML_HISTORY,
  TALER_EXCHANGEDB_RT_KYC_ATTRIBUTES,
  TALER_EXCHANGEDB_RT_PURSE_DELETION,
  TALER_EXCHANGEDB_RT_AGE_WITHDRAW,
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
      uint32_t denom_type;
      uint32_t age_mask;
      struct TALER_DenominationPublicKey denom_pub;
      struct TALER_MasterSignatureP master_sig;
      struct GNUNET_TIME_Timestamp valid_from;
      struct GNUNET_TIME_Timestamp expire_withdraw;
      struct GNUNET_TIME_Timestamp expire_deposit;
      struct GNUNET_TIME_Timestamp expire_legal;
      struct TALER_Amount coin;
      struct TALER_DenomFeeSet fees;
    } denominations;

    struct
    {
      struct TALER_MasterSignatureP master_sig;
      uint64_t denominations_serial;
    } denomination_revocations;

    struct
    {
      char *payto_uri;
    } wire_targets;

    struct
    {
      struct TALER_PaytoHashP h_payto;
      struct GNUNET_TIME_Timestamp expiration_time;
      char *provider_section;
      char *provider_user_id;
      char *provider_legitimization_id;
    } legitimization_processes;

    struct
    {
      struct TALER_PaytoHashP h_payto;
      struct TALER_ReservePublicKeyP reserve_pub;
      bool no_reserve_pub;
      char *required_checks;
    } legitimization_requirements;

    struct
    {
      struct TALER_ReservePublicKeyP reserve_pub;
      struct GNUNET_TIME_Timestamp expiration_date;
      struct GNUNET_TIME_Timestamp gc_date;
    } reserves;

    struct
    {
      uint64_t wire_reference;
      struct TALER_Amount credit;
      struct TALER_PaytoHashP sender_account_h_payto;
      char *exchange_account_section;
      struct GNUNET_TIME_Timestamp execution_date;
      struct TALER_ReservePublicKeyP reserve_pub;
    } reserves_in;

    struct
    {
      struct TALER_ReservePublicKeyP reserve_pub;
      struct GNUNET_TIME_Timestamp request_timestamp;
      struct GNUNET_TIME_Timestamp expiration_date;
      struct TALER_ReserveSignatureP reserve_sig;
      struct TALER_Amount reserve_payment;
      uint32_t requested_purse_limit;
    } reserves_open_requests;

    struct
    {
      struct TALER_ReservePublicKeyP reserve_pub;
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct TALER_CoinSpendSignatureP coin_sig;
      struct TALER_ReserveSignatureP reserve_sig;
      struct TALER_Amount contribution;
    } reserves_open_deposits;

    struct
    {
      struct TALER_ReservePublicKeyP reserve_pub;
      struct GNUNET_TIME_Timestamp execution_date;
      struct TALER_WireTransferIdentifierRawP wtid;
      struct TALER_PaytoHashP sender_account_h_payto;
      struct TALER_Amount amount;
      struct TALER_Amount closing_fee;
    } reserves_close;

    struct
    {
      struct TALER_BlindedCoinHashP h_blind_ev;
      uint64_t denominations_serial;
      struct TALER_BlindedDenominationSignature denom_sig;
      uint64_t reserve_uuid;
      struct TALER_ReserveSignatureP reserve_sig;
      struct GNUNET_TIME_Timestamp execution_date;
      struct TALER_Amount amount_with_fee;
    } reserves_out;

    struct
    {
      struct TALER_AuditorPublicKeyP auditor_pub;
      char *auditor_url;
      char *auditor_name;
      bool is_active;
      struct GNUNET_TIME_Timestamp last_change;
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
      struct TALER_AgeCommitmentHash age_hash;
      uint64_t denominations_serial;
      struct TALER_DenominationSignature denom_sig;
    } known_coins;

    struct
    {
      struct TALER_RefreshCommitmentP rc;
      struct TALER_CoinSpendPublicKeyP old_coin_pub;
      struct TALER_CoinSpendSignatureP old_coin_sig;
      struct TALER_Amount amount_with_fee;
      uint32_t noreveal_index;
    } refresh_commitments;

    struct
    {
      uint64_t melt_serial_id;
      uint32_t freshcoin_index;
      struct TALER_CoinSpendSignatureP link_sig;
      uint64_t denominations_serial;
      void *coin_ev;
      size_t coin_ev_size;
      struct TALER_ExchangeWithdrawValues ewv;
      // h_coin_ev omitted, to be recomputed!
      struct TALER_BlindedDenominationSignature ev_sig;
    } refresh_revealed_coins;

    struct
    {
      uint64_t melt_serial_id;
      struct TALER_TransferPublicKeyP tp;
      struct TALER_TransferPrivateKeyP tprivs[TALER_CNC_KAPPA - 1];
    } refresh_transfer_keys;

    struct
    {
      uint64_t shard;
      struct TALER_MerchantPublicKeyP merchant_pub;
      struct GNUNET_TIME_Timestamp wallet_timestamp;
      struct GNUNET_TIME_Timestamp exchange_timestamp;
      struct GNUNET_TIME_Timestamp refund_deadline;
      struct GNUNET_TIME_Timestamp wire_deadline;
      struct TALER_PrivateContractHashP h_contract_terms;
      struct GNUNET_HashCode wallet_data_hash;
      bool no_wallet_data_hash;
      struct TALER_WireSaltP wire_salt;
      struct TALER_PaytoHashP wire_target_h_payto;
      bool policy_blocked;
      uint64_t policy_details_serial_id;
      bool no_policy_details;
    } batch_deposits;

    struct
    {
      uint64_t batch_deposit_serial_id;
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct TALER_CoinSpendSignatureP coin_sig;
      struct TALER_Amount amount_with_fee;
    } coin_deposits;

    struct
    {
      struct TALER_CoinSpendPublicKeyP coin_pub;
      uint64_t batch_deposit_serial_id;
      struct TALER_MerchantSignatureP merchant_sig;
      uint64_t rtransaction_id;
      struct TALER_Amount amount_with_fee;
    } refunds;

    struct
    {
      struct GNUNET_TIME_Timestamp execution_date;
      struct TALER_WireTransferIdentifierRawP wtid_raw;
      struct TALER_PaytoHashP wire_target_h_payto;
      char *exchange_account_section;
      struct TALER_Amount amount;
    } wire_out;

    struct
    {
      uint64_t batch_deposit_serial_id;
      struct TALER_WireTransferIdentifierRawP wtid_raw;
    } aggregation_tracking;

    struct
    {
      char *wire_method;
      struct GNUNET_TIME_Timestamp start_date;
      struct GNUNET_TIME_Timestamp end_date;
      struct TALER_WireFeeSet fees;
      struct TALER_MasterSignatureP master_sig;
    } wire_fee;

    struct
    {
      struct GNUNET_TIME_Timestamp start_date;
      struct GNUNET_TIME_Timestamp end_date;
      struct TALER_GlobalFeeSet fees;
      struct GNUNET_TIME_Relative purse_timeout;
      struct GNUNET_TIME_Relative history_expiration;
      uint32_t purse_account_limit;
      struct TALER_MasterSignatureP master_sig;
    } global_fee;

    struct
    {
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct TALER_CoinSpendSignatureP coin_sig;
      union GNUNET_CRYPTO_BlindingSecretP coin_blind;
      struct TALER_Amount amount;
      struct GNUNET_TIME_Timestamp timestamp;
      uint64_t reserve_out_serial_id;
    } recoup;

    struct
    {
      uint64_t known_coin_id;
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct TALER_CoinSpendSignatureP coin_sig;
      union GNUNET_CRYPTO_BlindingSecretP coin_blind;
      struct TALER_Amount amount;
      struct GNUNET_TIME_Timestamp timestamp;
      uint64_t rrc_serial;
    } recoup_refresh;

    struct
    {
      char *name;
      char *manifest;
    } extensions;

    struct
    {
      struct GNUNET_HashCode hash_code;
      json_t *policy_json;
      bool no_policy_json;
      struct GNUNET_TIME_Timestamp deadline;
      struct TALER_Amount commitment;
      struct TALER_Amount accumulated_total;
      struct TALER_Amount fee;
      struct TALER_Amount transferable;
      uint16_t fulfillment_state; /* will also be recomputed */
      uint64_t fulfillment_id;
      bool no_fulfillment_id;
    } policy_details;

    struct
    {
      struct GNUNET_TIME_Timestamp fulfillment_timestamp;
      char *fulfillment_proof;
      struct GNUNET_HashCode h_fulfillment_proof;
      struct GNUNET_HashCode *policy_hash_codes;
      size_t policy_hash_codes_count;
    } policy_fulfillments;

    struct
    {
      struct TALER_PurseContractPublicKeyP purse_pub;
      struct TALER_PurseMergePublicKeyP merge_pub;
      struct GNUNET_TIME_Timestamp purse_creation;
      struct GNUNET_TIME_Timestamp purse_expiration;
      struct TALER_PrivateContractHashP h_contract_terms;
      uint32_t age_limit;
      uint32_t flags;
      struct TALER_Amount amount_with_fee;
      struct TALER_Amount purse_fee;
      struct TALER_PurseContractSignatureP purse_sig;
    } purse_requests;

    struct
    {
      struct TALER_PurseContractPublicKeyP purse_pub;
      struct GNUNET_TIME_Timestamp action_timestamp;
      bool refunded;
    } purse_decision;

    struct
    {
      uint64_t partner_serial_id;
      struct TALER_ReservePublicKeyP reserve_pub;
      struct TALER_PurseContractPublicKeyP purse_pub;
      struct TALER_PurseMergeSignatureP merge_sig;
      struct GNUNET_TIME_Timestamp merge_timestamp;
    } purse_merges;

    struct
    {
      uint64_t partner_serial_id;
      struct TALER_PurseContractPublicKeyP purse_pub;
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct TALER_Amount amount_with_fee;
      struct TALER_CoinSpendSignatureP coin_sig;
    } purse_deposits;

    struct
    {
      struct TALER_ReservePublicKeyP reserve_pub;
      struct TALER_ReserveSignatureP reserve_sig;
      struct TALER_PurseContractPublicKeyP purse_pub;
      struct TALER_PaytoHashP wallet_h_payto;
    } account_merges;

    struct
    {
      struct TALER_ReservePublicKeyP reserve_pub;
      struct TALER_ReserveSignatureP reserve_sig;
      struct GNUNET_TIME_Timestamp request_timestamp;
      struct TALER_Amount history_fee;
    } history_requests;

    struct
    {
      struct TALER_ReservePublicKeyP reserve_pub;
      struct GNUNET_TIME_Timestamp close_timestamp;
      struct TALER_ReserveSignatureP reserve_sig;
      struct TALER_Amount close;
      struct TALER_Amount close_fee;
      char *payto_uri;
    } close_requests;

    struct
    {
      struct TALER_WadIdentifierP wad_id;
      uint64_t partner_serial_id;
      struct TALER_Amount amount;
      struct GNUNET_TIME_Timestamp execution_time;
    } wads_out;

    struct
    {
      uint64_t wad_out_serial_id;
      struct TALER_ReservePublicKeyP reserve_pub;
      struct TALER_PurseContractPublicKeyP purse_pub;
      struct TALER_PrivateContractHashP h_contract;
      struct GNUNET_TIME_Timestamp purse_expiration;
      struct GNUNET_TIME_Timestamp merge_timestamp;
      struct TALER_Amount amount_with_fee;
      struct TALER_Amount wad_fee;
      struct TALER_Amount deposit_fees;
      struct TALER_ReserveSignatureP reserve_sig;
      struct TALER_PurseContractSignatureP purse_sig;
    } wads_out_entries;

    struct
    {
      struct TALER_WadIdentifierP wad_id;
      char *origin_exchange_url;
      struct TALER_Amount amount;
      struct GNUNET_TIME_Timestamp arrival_time;
    } wads_in;

    struct
    {
      uint64_t wad_in_serial_id;
      struct TALER_ReservePublicKeyP reserve_pub;
      struct TALER_PurseContractPublicKeyP purse_pub;
      struct TALER_PrivateContractHashP h_contract;
      struct GNUNET_TIME_Timestamp purse_expiration;
      struct GNUNET_TIME_Timestamp merge_timestamp;
      struct TALER_Amount amount_with_fee;
      struct TALER_Amount wad_fee;
      struct TALER_Amount deposit_fees;
      struct TALER_ReserveSignatureP reserve_sig;
      struct TALER_PurseContractSignatureP purse_sig;
    } wads_in_entries;

    struct
    {
      struct TALER_WireTransferIdentifierRawP wtid;
      char *account_section;
      char *payto_uri;
      struct GNUNET_TIME_Timestamp trigger_date;
      struct TALER_Amount amount;
      struct TALER_MasterSignatureP master_sig;
    } profit_drains;

    struct
    {
      struct TALER_AmlOfficerPublicKeyP decider_pub;
      struct TALER_MasterSignatureP master_sig;
      char *decider_name;
      bool is_active;
      bool read_only;
      struct GNUNET_TIME_Timestamp last_change;
    } aml_staff;

    struct
    {
      struct TALER_PaytoHashP h_payto;
      struct TALER_Amount new_threshold;
      enum TALER_AmlDecisionState new_status;
      struct GNUNET_TIME_Timestamp decision_time;
      char *justification;
      char *kyc_requirements; /* NULL allowed! */
      uint64_t kyc_req_row;
      struct TALER_AmlOfficerPublicKeyP decider_pub;
      struct TALER_AmlOfficerSignatureP decider_sig;
    } aml_history;

    struct
    {
      struct TALER_PaytoHashP h_payto;
      struct GNUNET_ShortHashCode kyc_prox;
      char *provider;
      struct GNUNET_TIME_Timestamp collection_time;
      struct GNUNET_TIME_Timestamp expiration_time;
      void *encrypted_attributes;
      size_t encrypted_attributes_size;
    } kyc_attributes;

    struct
    {
      struct TALER_PurseContractPublicKeyP purse_pub;
      struct TALER_PurseContractSignatureP purse_sig;
    } purse_deletion;

    struct
    {
      struct TALER_AgeWithdrawCommitmentHashP h_commitment;
      struct TALER_Amount amount_with_fee;
      uint16_t max_age;
      uint32_t noreveal_index;
      struct TALER_ReservePublicKeyP reserve_pub;
      struct TALER_ReserveSignatureP reserve_sig;
      uint64_t num_coins;
      uint64_t *denominations_serials;
      void *h_blind_evs;
      struct TALER_BlindedDenominationSignature denom_sigs;
    } age_withdraw;

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
  struct TALER_EXCHANGEDB_DenominationKeyInformation issue;
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
  struct GNUNET_TIME_Timestamp execution_date;

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
   * Amount that was transferred from the exchange.
   */
  struct TALER_Amount amount;

  /**
   * Amount that was charged by the exchange.
   */
  struct TALER_Amount closing_fee;

  /**
   * When did the exchange execute the transaction?
   */
  struct GNUNET_TIME_Timestamp execution_date;

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
  struct GNUNET_TIME_Timestamp expiry;

  /**
   * The legal expiration date of this reserve; we will forget about
   * it at this time.
   */
  struct GNUNET_TIME_Timestamp gc;
};


/**
 * Meta data about a denomination public key.
 */
struct TALER_EXCHANGEDB_DenominationKeyMetaData
{
  /**
   * Serial of the denomination key as in the DB.
   * Can be used in calls to stored procedures in order to spare
   * additional lookups.
   */
  uint64_t serial;

  /**
   * Start time of the validity period for this key.
   */
  struct GNUNET_TIME_Timestamp start;

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
  struct GNUNET_TIME_Timestamp expire_withdraw;

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
  struct GNUNET_TIME_Timestamp expire_deposit;

  /**
   * When do signatures with this denomination key become invalid?
   * After this point, these signatures cannot be used in (legal)
   * disputes anymore, as the Exchange is then allowed to destroy its side
   * of the evidence.  @e expire_legal is expected to be significantly
   * larger than @e expire_deposit (by a year or more).
   */
  struct GNUNET_TIME_Timestamp expire_legal;

  /**
   * The value of the coins signed with this denomination key.
   */
  struct TALER_Amount value;

  /**
   * The fees the exchange charges for operations with
   * coins of this denomination.
   */
  struct TALER_DenomFeeSet fees;

  /**
   * Age restriction for the denomination. (can be zero). If not zero, the bits
   * set in the mask mark the edges at the beginning of a next age group.  F.e.
   * for the age groups
   *     0-7, 8-9, 10-11, 12-14, 14-15, 16-17, 18-21, 21-*
   * the following bits are set:
   *
   *   31     24        16        8         0
   *   |      |         |         |         |
   *   oooooooo  oo1oo1o1  o1o1o1o1  ooooooo1
   *
   * A value of 0 means that the denomination does not support the extension for
   * age-restriction.
   */
  struct TALER_AgeMask age_mask;
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
  const struct TALER_DenominationHashP *h_denom_pub,
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
 * Function called on all KYC process names that the given
 * account has already passed.
 *
 * @param cls closure
 * @param kyc_provider_section_name configuration section
 *        of the respective KYC process
 */
typedef void
(*TALER_EXCHANGEDB_SatisfiedProviderCallback)(
  void *cls,
  const char *kyc_provider_section_name);


/**
 * Function called on all legitimization operations
 * we have performed for the given account so far
 * (and that have not yet expired).
 *
 * @param cls closure
 * @param kyc_provider_section_name configuration section
 *        of the respective KYC process
 * @param provider_user_id UID at a provider (can be NULL)
 * @param legi_id legitimization process ID (can be NULL)
 */
typedef void
(*TALER_EXCHANGEDB_LegitimizationProcessCallback)(
  void *cls,
  const char *kyc_provider_section_name,
  const char *provider_user_id,
  const char *legi_id);


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
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AuditorSignatureP *auditor_sig);


/**
 * @brief Information we keep for a withdrawn coin to reproduce
 * the /withdraw operation if needed, and to have proof
 * that a reserve was drained by this amount.
 */
struct TALER_EXCHANGEDB_CollectableBlindcoin
{

  /**
   * Our (blinded) signature over the (blinded) coin.
   */
  struct TALER_BlindedDenominationSignature sig;

  /**
   * Hash of the denomination key (which coin was generated).
   */
  struct TALER_DenominationHashP denom_pub_hash;

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
  struct TALER_BlindedCoinHashP h_coin_envelope;

  /**
   * Signature confirming the withdrawal, matching @e reserve_pub,
   * @e denom_pub and @e h_coin_envelope.
   */
  struct TALER_ReserveSignatureP reserve_sig;
};


/**
 * @brief Information we keep for an age-withdraw request
 * to reproduce the /age-withdraw operation if needed, and to have proof
 * that a reserve was drained by this amount.
 */
struct TALER_EXCHANGEDB_AgeWithdraw
{
  /**
   * Total amount (with fee) committed to withdraw
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Maximum age (in years) that the coins are restricted to.
   */
  uint16_t max_age;

  /**
   * The hash of the commitment of all n*kappa coins
   */
  struct TALER_AgeWithdrawCommitmentHashP h_commitment;

  /**
   * Index (smaller #TALER_CNC_KAPPA) which the exchange has chosen to not have
   * revealed during cut and choose.  This value applies to all n coins in the
   * commitment.
   */
  uint16_t noreveal_index;

  /**
   * Public key of the reserve that was drained.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Signature confirming the age withdrawal commitment, matching @e
   * reserve_pub, @e max_age and @e h_commitment and @e amount_with_fee.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * Number of coins to be withdrawn.
   */
  size_t num_coins;

  /**
   * Array of @a num_coins blinded coins.  These are the chosen coins
   * (according to @a noreveal_index) from the request, which contained
   * kappa*num_coins blinded coins.
   */
  struct TALER_BlindedCoinHashP *h_coin_evs;

  /**
   * Array of @a num_coins denomination signatures of the blinded coins @a
   * h_coin_evs.
   */
  struct TALER_BlindedDenominationSignature *denom_sigs;

  /**
   * Array of @a num_coins serial id's of the denominations, corresponding to
   * the coins in @a h_coin_evs.
   */
  uint64_t *denom_serials;

  /**
   * [out]-Array of @a num_coins hashes of the public keys of the denominations
   * identified by @e denom_serials.  This field is set when calling
   * get_age_withdraw
   */
  struct TALER_DenominationHashP *denom_pub_hashes;
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
  union GNUNET_CRYPTO_BlindingSecretP coin_blind;

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
  struct GNUNET_TIME_Timestamp timestamp;

};


/**
 * Public key to which a nonce is locked.
 */
union TALER_EXCHANGEDB_NonceLockTargetP
{
  /**
   * Nonce is locked to this coin key.
   */
  struct TALER_CoinSpendPublicKeyP coin;

  /**
   * Nonce is locked to this reserve key.
   */
  struct TALER_ReservePublicKeyP reserve;
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
  union GNUNET_CRYPTO_BlindingSecretP coin_blind;

  /**
   * Signature of the coin of type
   * #TALER_SIGNATURE_WALLET_COIN_RECOUP.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Hash of the public denomination key used to sign the coin.
   */
  struct TALER_DenominationHashP h_denom_pub;

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
  struct GNUNET_TIME_Timestamp timestamp;

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
  union GNUNET_CRYPTO_BlindingSecretP coin_blind;

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
  struct GNUNET_TIME_Timestamp timestamp;

};


/**
 * Details about a purse merge operation.
 */
struct TALER_EXCHANGEDB_PurseMerge
{

  /**
   * Public key of the reserve the coin was merged into.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Amount in the purse, with fees.
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Fee paid for the purse.
   */
  struct TALER_Amount purse_fee;

  /**
   * Hash over the contract.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Merge capability key.
   */
  struct TALER_PurseMergePublicKeyP merge_pub;

  /**
   * Purse public key.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Signature by the reserve approving the merge.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * When was the merge made.
   */
  struct GNUNET_TIME_Timestamp merge_timestamp;

  /**
   * When was the purse set to expire.
   */
  struct GNUNET_TIME_Timestamp purse_expiration;

  /**
   * Minimum age required for depositing into the purse.
   */
  uint32_t min_age;

  /**
   * Flags of the purse.
   */
  enum TALER_WalletAccountMergeFlags flags;

  /**
   * true if the purse was actually successfully merged,
   * false if the @e purse_fee was charged but the
   * @e amount was not credited to the reserve.
   */
  bool merged;
};


/**
 * Details about a (paid for) reserve history request.
 */
struct TALER_EXCHANGEDB_HistoryRequest
{
  /**
   * Public key of the reserve the history request was for.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Fee paid for the request.
   */
  struct TALER_Amount history_fee;

  /**
   * When was the request made.
   */
  struct GNUNET_TIME_Timestamp request_timestamp;

  /**
   * Signature by the reserve approving the history request.
   */
  struct TALER_ReserveSignatureP reserve_sig;
};


/**
 * Details about a (paid for) reserve open request.
 */
struct TALER_EXCHANGEDB_OpenRequest
{
  /**
   * Public key of the reserve the open request was for.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Fee paid for the request from the reserve.
   */
  struct TALER_Amount open_fee;

  /**
   * When was the request made.
   */
  struct GNUNET_TIME_Timestamp request_timestamp;

  /**
   * How long was the reserve supposed to be open.
   */
  struct GNUNET_TIME_Timestamp reserve_expiration;

  /**
   * Signature by the reserve approving the open request,
   * with purpose #TALER_SIGNATURE_WALLET_RESERVE_OPEN.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * How many open purses should be included with the
   * open reserve?
   */
  uint32_t purse_limit;

};


/**
 * Details about an (explicit) reserve close request.
 */
struct TALER_EXCHANGEDB_CloseRequest
{
  /**
   * Public key of the reserve the history request was for.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * When was the request made.
   */
  struct GNUNET_TIME_Timestamp request_timestamp;

  /**
   * Hash of the payto://-URI of the target account
   * for the closure, or all zeros for the reserve
   * origin account.
   */
  struct TALER_PaytoHashP target_account_h_payto;

  /**
   * Signature by the reserve approving the history request.
   */
  struct TALER_ReserveSignatureP reserve_sig;

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
  TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK = 3,

  /**
   * Event where a purse was merged into a reserve.
   */
  TALER_EXCHANGEDB_RO_PURSE_MERGE = 4,

  /**
   * Event where a wallet paid for a full reserve history.
   */
  TALER_EXCHANGEDB_RO_HISTORY_REQUEST = 5,

  /**
   * Event where a wallet paid to open a reserve for longer.
   */
  TALER_EXCHANGEDB_RO_OPEN_REQUEST = 6,

  /**
   * Event where a wallet requested a reserve to be closed.
   */
  TALER_EXCHANGEDB_RO_CLOSE_REQUEST = 7
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

    /**
     * Details about a purse merge operation.
     */
    struct TALER_EXCHANGEDB_PurseMerge *merge;

    /**
     * Details about a (paid for) reserve history request.
     */
    struct TALER_EXCHANGEDB_HistoryRequest *history;

    /**
     * Details about a (paid for) open reserve request.
     */
    struct TALER_EXCHANGEDB_OpenRequest *open_request;

    /**
     * Details about an (explicit) reserve close request.
     */
    struct TALER_EXCHANGEDB_CloseRequest *close_request;

  } details;

};


/**
 * @brief Data about a coin for a deposit operation.
 */
struct TALER_EXCHANGEDB_CoinDepositInformation
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
   * Fraction of the coin's remaining value to be deposited, including
   * depositing fee (if any).  The coin is identified by @e coin_pub.
   */
  struct TALER_Amount amount_with_fee;

};


/**
 * @brief Data from a batch deposit operation.
 */
struct TALER_EXCHANGEDB_BatchDeposit
{

  /**
   * Public key of the merchant.  Enables later identification
   * of the merchant in case of a need to rollback transactions.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Hash over the proposal data between merchant and customer
   * (remains unknown to the Exchange).
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Hash over additional inputs by the wallet.
   */
  struct GNUNET_HashCode wallet_data_hash;

  /**
   * Unsalted hash over @e receiver_wire_account.
   */
  struct TALER_PaytoHashP wire_target_h_payto;

  /**
   * Salt used by the merchant to compute "h_wire".
   */
  struct TALER_WireSaltP wire_salt;

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
  struct GNUNET_TIME_Timestamp wallet_timestamp;

  /**
   * How much time does the merchant have to issue a refund request?
   * Zero if refunds are not allowed.  After this time, the coin
   * cannot be refunded.
   */
  struct GNUNET_TIME_Timestamp refund_deadline;

  /**
   * How much time does the merchant have to execute the wire transfer?
   * This time is advisory for aggregating transactions, not a hard
   * constraint (as the merchant can theoretically pick any time,
   * including one in the past).
   */
  struct GNUNET_TIME_Timestamp wire_deadline;

  /**
   * Row ID of the policy details; 0 if no policy applies.
   */
  uint64_t policy_details_serial_id;

  /**
   * Information about the receiver for executing the transaction.  URI in
   * payto://-format.
   */
  const char *receiver_wire_account;

  /**
   * Array about the coins that are being deposited.
   */
  const struct TALER_EXCHANGEDB_CoinDepositInformation *cdis;

  /**
   * Length of the @e cdis array.
   */
  unsigned int num_cdis;

  /**
   * False if @e wallet_data_hash was provided
   */
  bool no_wallet_data_hash;

  /**
   * True if further processing is blocked by policy.
   */
  bool policy_blocked;

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
   * Hash over the proposal data between merchant and customer
   * (remains unknown to the Exchange).
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Salt used by the merchant to compute "h_wire".
   */
  struct TALER_WireSaltP wire_salt;

  /**
   * Hash over inputs from the wallet to customize the contract.
   */
  struct GNUNET_HashCode wallet_data_hash;

  /**
   * Hash over the policy data for this deposit (remains unknown to the
   * Exchange).  Needed for the verification of the deposit's signature
   */
  struct TALER_ExtensionPolicyHashP h_policy;

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
  struct GNUNET_TIME_Timestamp timestamp;

  /**
   * How much time does the merchant have to issue a refund request?
   * Zero if refunds are not allowed.  After this time, the coin
   * cannot be refunded.
   */
  struct GNUNET_TIME_Timestamp refund_deadline;

  /**
   * How much time does the merchant have to execute the wire transfer?
   * This time is advisory for aggregating transactions, not a hard
   * constraint (as the merchant can theoretically pick any time,
   * including one in the past).
   */
  struct GNUNET_TIME_Timestamp wire_deadline;

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
   * Information about the receiver for executing the transaction.  URI in
   * payto://-format.
   */
  char *receiver_wire_account;

  /**
   * True if @e policy_json was provided
   */
  bool has_policy;

  /**
   * True if @e wallet_data_hash is not in use.
   */
  bool no_wallet_data_hash;

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
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Hash over inputs from the wallet to customize the contract.
   */
  struct GNUNET_HashCode wallet_data_hash;

  /**
   * Hash of the public denomination key used to sign the coin.
   */
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * Age commitment hash, if applicable to the denomination.  Should be all
   * zeroes if age commitment is not applicable to the denonimation.
   */
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * Salt used to compute h_wire from the @e receiver_wire_account.
   */
  struct TALER_WireSaltP wire_salt;

  /**
   * Hash over the policy data for this deposit (remains unknown to the
   * Exchange).  Needed for the verification of the deposit's signature
   */
  struct TALER_ExtensionPolicyHashP h_policy;

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
  struct GNUNET_TIME_Timestamp timestamp;

  /**
   * How much time does the merchant have to issue a refund request?
   * Zero if refunds are not allowed.  After this time, the coin
   * cannot be refunded.
   */
  struct GNUNET_TIME_Timestamp refund_deadline;

  /**
   * How much time does the merchant have to execute the wire transfer?
   * This time is advisory for aggregating transactions, not a hard
   * constraint (as the merchant can theoretically pick any time,
   * including one in the past).
   */
  struct GNUNET_TIME_Timestamp wire_deadline;

  /**
   * Detailed information about the receiver for executing the transaction.
   * URL in payto://-format.
   */
  char *receiver_wire_account;

  /**
   * true, if age commitment is not applicable
   */
  bool no_age_commitment;

  /**
   * true, if wallet data hash is not present
   */
  bool no_wallet_data_hash;

  /**
   * True if a policy was provided with the deposit request
   */
  bool has_policy;

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
  struct TALER_PrivateContractHashP h_contract_terms;

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
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * Hash of the age commitment used to sign the coin, if age restriction was
   * applicable to the denomination.  May be all zeroes if no age restriction
   * applies.
   */
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * true, if no h_age_commitment is applicable
   */
  bool no_age_commitment;

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
 * Information about a /purses/$PID/deposit operation in a coin transaction history.
 */
struct TALER_EXCHANGEDB_PurseDepositListEntry
{

  /**
   * Exchange hosting the purse, NULL for this exchange.
   */
  char *exchange_base_url;

  /**
   * Public key of the purse.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Contribution of the coin to the purse, including
   * deposit fee.
   */
  struct TALER_Amount amount;

  /**
   * Depositing fee.
   */
  struct TALER_Amount deposit_fee;

  /**
   * Signature by the coin affirming the deposit.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Hash of the age commitment used to sign the coin, if age restriction was
   * applicable to the denomination.
   */
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * Set to true if the coin was refunded.
   */
  bool refunded;

  /**
   * Set to true if there was no age commitment.
   */
  bool no_age_commitment;

};


/**
 * @brief Specification for a purse refund operation in a coin's transaction list.
 */
struct TALER_EXCHANGEDB_PurseRefundListEntry
{

  /**
   * Public key of the purse.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

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
 * Information about a /reserves/$RID/open operation in a coin transaction history.
 */
struct TALER_EXCHANGEDB_ReserveOpenListEntry
{

  /**
   * Signature of the reserve.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * Contribution of the coin to the open fee, including
   * deposit fee.
   */
  struct TALER_Amount coin_contribution;

  /**
   * Signature by the coin affirming the open deposit.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

};


/**
 * Information about a /purses/$PID/deposit operation.
 */
struct TALER_EXCHANGEDB_PurseDeposit
{

  /**
   * Exchange hosting the purse, NULL for this exchange.
   */
  char *exchange_base_url;

  /**
   * Public key of the purse.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Contribution of the coin to the purse, including
   * deposit fee.
   */
  struct TALER_Amount amount;

  /**
   * Depositing fee.
   */
  struct TALER_Amount deposit_fee;

  /**
   * Signature by the coin affirming the deposit.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * Public key of the coin.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Hash of the age commitment used to sign the coin, if age restriction was
   * applicable to the denomination.  May be all zeroes if no age restriction
   * applies.
   */
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * Set to true if @e h_age_commitment is not available.
   */
  bool no_age_commitment;

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
  struct TALER_BlindedDenominationSignature ev_sig;

  /**
   * Exchange-provided values during the coin generation.
   */
  struct TALER_ExchangeWithdrawValues alg_values;

  /**
   * Signature of the original coin being refreshed over the
   * link data, of type #TALER_SIGNATURE_WALLET_COIN_LINK
   */
  struct TALER_CoinSpendSignatureP orig_coin_link_sig;

  /**
   * Session nonce, if cipher has one.
   */
  union GNUNET_CRYPTO_BlindSessionNonce nonce;

  /**
   * Offset that generated this coin in the refresh
   * operation.
   */
  uint32_t coin_refresh_offset;

  /**
   * Set to true if @e nonce was initialized.
   */
  bool have_nonce;
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
  TALER_EXCHANGEDB_TT_RECOUP_REFRESH = 5,

  /**
   * Purse deposit operation.
   */
  TALER_EXCHANGEDB_TT_PURSE_DEPOSIT = 6,

  /**
   * Purse deposit operation.
   */
  TALER_EXCHANGEDB_TT_PURSE_REFUND = 7,

  /**
   * Reserve open deposit operation.
   */
  TALER_EXCHANGEDB_TT_RESERVE_OPEN = 8

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

    /**
     * Coin was deposited into a purse.
     * (#TALER_EXCHANGEDB_TT_PURSE_DEPOSIT)
     */
    struct TALER_EXCHANGEDB_PurseDepositListEntry *purse_deposit;

    /**
     * Coin was refunded upon purse expiration
     * (#TALER_EXCHANGEDB_TT_PURSE_REFUND)
     */
    struct TALER_EXCHANGEDB_PurseRefundListEntry *purse_refund;

    /**
     * Coin was used to pay to open a reserve.
     * (#TALER_EXCHANGEDB_TT_RESERVE_OPEN)
     */
    struct TALER_EXCHANGEDB_ReserveOpenListEntry *reserve_open;

  } details;

};


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
 * Callback with KYC attributes about a particular user.
 *
 * @param cls closure
 * @param h_payto account for which the attribute data is stored
 * @param provider_section provider that must be checked
 * @param collection_time when was the data collected
 * @param expiration_time when does the data expire
 * @param enc_attributes_size number of bytes in @a enc_attributes
 * @param enc_attributes encrypted attribute data
 */
typedef void
(*TALER_EXCHANGEDB_AttributeCallback)(
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const char *provider_section,
  struct GNUNET_TIME_Timestamp collection_time,
  struct GNUNET_TIME_Timestamp expiration_time,
  size_t enc_attributes_size,
  const void *enc_attributes);


/**
 * Function called with details about deposits that have been made,
 * with the goal of auditing the deposit's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param exchange_timestamp when did the deposit happen
 * @param deposit deposit details
 * @param denom_pub denomination public key of @a coin_pub
 * @param done flag set if the deposit was already executed (or not)
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_DepositCallback)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  const struct TALER_EXCHANGEDB_Deposit *deposit,
  const struct TALER_DenominationPublicKey *denom_pub,
  bool done);


/**
 * Function called with details about purse deposits that have been made, with
 * the goal of auditing the deposit's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param deposit deposit details
 * @param reserve_pub which reserve is the purse merged into, NULL if unknown
 * @param flags purse flags
 * @param auditor_balance purse balance (according to the
 *          auditor during auditing)
 * @param purse_total target amount the purse should reach
 * @param denom_pub denomination public key of @a coin_pub
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_PurseDepositCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_EXCHANGEDB_PurseDeposit *deposit,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_Amount *auditor_balance,
  const struct TALER_Amount *purse_total,
  const struct TALER_DenominationPublicKey *denom_pub);


/**
 * Function called with details about
 * account merge requests that have been made, with
 * the goal of auditing the account merge execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param reserve_pub reserve affected by the merge
 * @param purse_pub purse being merged
 * @param h_contract_terms hash over contract of the purse
 * @param purse_expiration when would the purse expire
 * @param amount total amount in the purse
 * @param min_age minimum age of all coins deposited into the purse
 * @param flags how was the purse created
 * @param purse_fee if a purse fee was paid, how high is it
 * @param merge_timestamp when was the merge approved
 * @param reserve_sig signature by reserve approving the merge
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_AccountMergeCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_Amount *amount,
  uint32_t min_age,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_Amount *purse_fee,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Function called with details about purse
 * merges that have been made, with
 * the goal of auditing the purse merge execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param partner_base_url where is the reserve, NULL for this exchange
 * @param amount total amount expected in the purse
 * @param balance current balance in the purse (according to the auditor)
 * @param flags purse flags
 * @param merge_pub merge capability key
 * @param reserve_pub reserve the merge affects
 * @param merge_sig signature affirming the merge
 * @param purse_pub purse key
 * @param merge_timestamp when did the merge happen
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_PurseMergeCallback)(
  void *cls,
  uint64_t rowid,
  const char *partner_base_url,
  const struct TALER_Amount *amount,
  const struct TALER_Amount *balance,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp merge_timestamp);


/**
 * Function called with details about purse decisions that have been made, with
 * the goal of auditing the purse's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param purse_pub public key of the purse
 * @param reserve_pub public key of the target reserve, NULL if not known / refunded
 * @param purse_value what is the (target) value of the purse
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_PurseDecisionCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *purse_value);


/**
 * Function called with details about purse decisions that have been made, with
 * the goal of auditing the purse's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param purse_pub public key of the purse
 * @param refunded true if decision was to refund
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_AllPurseDecisionCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  bool refunded);


/**
 * Function called with details about purse refunds that have been made, with
 * the goal of auditing the purse refund's execution.
 *
 * @param cls closure
 * @param rowid row of the refund event
 * @param amount_with_fee amount of the deposit into the purse
 * @param coin_pub coin that is to be refunded the @a given amount_with_fee
 * @param denom_pub denomination of @a coin_pub
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_PurseRefundCoinCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_DenominationPublicKey *denom_pub);


/**
 * Function called with details about coins that were melted,
 * with the goal of auditing the refresh's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refresh session in our DB
 * @param denom_pub denomination public key of @a coin_pub
 * @param h_age_commitment age commitment that went into the signing of the coin, may be NULL
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param noreveal_index which index was picked by the exchange in cut-and-choose
 * @param rc what is the commitment
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_RefreshesCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
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
typedef enum GNUNET_GenericReturnValue
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
   * Hash of the public denomination key of the coin.
   */
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * Signature of the original coin being refreshed over the
   * link data, of type #TALER_SIGNATURE_WALLET_COIN_LINK
   */
  struct TALER_CoinSpendSignatureP orig_coin_link_sig;

  /**
   * Hash of the blinded new coin, that is @e coin_ev.
   */
  struct TALER_BlindedCoinHashP coin_envelope_hash;

  /**
   * Signature generated by the exchange over the coin (in blinded format).
   */
  struct TALER_BlindedDenominationSignature coin_sig;

  /**
   * Values contributed from the exchange to the
   * coin generation (see /csr).
   */
  struct TALER_ExchangeWithdrawValues exchange_vals;

  /**
   * Blinded message to be signed (in envelope).
   */
  struct TALER_BlindedPlanchet blinded_planchet;

};


/**
 * Information per Clause-Schnorr (CS) fresh coin to
 * be persisted for idempotency during refreshes-reveal.
 */
struct TALER_EXCHANGEDB_CsRevealFreshCoinData
{
  /**
   * Denomination of the fresh coin.
   */
  struct TALER_DenominationHashP new_denom_pub_hash;

  /**
   * Blind signature of the fresh coin (possibly updated
   * in case if a replay!).
   */
  struct TALER_BlindedDenominationSignature bsig;

  /**
   * Offset of the fresh coin in the reveal operation.
   * (May not match the array offset as we may have
   * a mixture of RSA and CS coins being created, and
   * this request is only made for the CS subset).
   */
  uint32_t coin_off;
};


/**
 * Generic KYC status for some operation.
 */
struct TALER_EXCHANGEDB_KycStatus
{
  /**
   * Number that identifies the KYC requirement the operation
   * was about.
   */
  uint64_t requirement_row;

  /**
   * True if the KYC status is "satisfied".
   */
  bool ok;

};


struct TALER_EXCHANGEDB_ReserveInInfo
{
  const struct TALER_ReservePublicKeyP *reserve_pub;
  const struct TALER_Amount *balance;
  struct GNUNET_TIME_Timestamp execution_time;
  const char *sender_account_details;
  const char *exchange_account_name;
  uint64_t wire_reference;
};


/**
 * Function called on each @a amount that was found to
 * be relevant for a KYC check.
 *
 * @param cls closure to allow the KYC module to
 *        total up amounts and evaluate rules
 * @param amount encountered transaction amount
 * @param date when was the amount encountered
 * @return #GNUNET_OK to continue to iterate,
 *         #GNUNET_NO to abort iteration
 *         #GNUNET_SYSERR on internal error (also abort itaration)
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_KycAmountCallback)(
  void *cls,
  const struct TALER_Amount *amount,
  struct GNUNET_TIME_Absolute date);


/**
 * Function called with information about a refresh order.
 *
 * @param cls closure
 * @param num_freshcoins size of the @a rrcs array
 * @param rrcs array of @a num_freshcoins information about coins to be created
 */
typedef void
(*TALER_EXCHANGEDB_RefreshCallback)(
  void *cls,
  uint32_t num_freshcoins,
  const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs);


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
 * @param full_refund true if the refunds total up to the entire value of the deposit
 * @param amount_with_fee amount that was deposited including fee
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_RefundCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_MerchantSignatureP *merchant_sig,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint64_t rtransaction_id,
  bool full_refund,
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
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_ReserveInCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *credit,
  const char *sender_account_details,
  uint64_t wire_reference,
  struct GNUNET_TIME_Timestamp execution_date);


/**
 * Provide information about a wire account.
 *
 * @param cls closure
 * @param payto_uri the exchange bank account URI
 * @param conversion_url URL of a conversion service, NULL if there is no conversion
 * @param debit_restrictions JSON array with debit restrictions on the account
 * @param credit_restrictions JSON array with credit restrictions on the account
 * @param master_sig master key signature affirming that this is a bank
 *                   account of the exchange (of purpose #TALER_SIGNATURE_MASTER_WIRE_DETAILS)
 */
typedef void
(*TALER_EXCHANGEDB_WireAccountCallback)(
  void *cls,
  const char *payto_uri,
  const char *conversion_url,
  const json_t *debit_restrictions,
  const json_t *credit_restrictions,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Provide information about wire fees.
 *
 * @param cls closure
 * @param fees the wire fees we charge
 * @param start_date from when are these fees valid (start date)
 * @param end_date until when are these fees valid (end date, exclusive)
 * @param master_sig master key signature affirming that this is the correct
 *                   fee (of purpose #TALER_SIGNATURE_MASTER_WIRE_FEES)
 */
typedef void
(*TALER_EXCHANGEDB_WireFeeCallback)(
  void *cls,
  const struct TALER_WireFeeSet *fees,
  struct GNUNET_TIME_Timestamp start_date,
  struct GNUNET_TIME_Timestamp end_date,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Provide information about global fees.
 *
 * @param cls closure
 * @param fees the global fees we charge
 * @param purse_timeout when do purses time out
 * @param history_expiration how long are account histories preserved
 * @param purse_account_limit how many purses are free per account
 * @param start_date from when are these fees valid (start date)
 * @param end_date until when are these fees valid (end date, exclusive)
 * @param master_sig master key signature affirming that this is the correct
 *                   fee (of purpose #TALER_SIGNATURE_MASTER_GLOBAL_FEES)
 */
typedef void
(*TALER_EXCHANGEDB_GlobalFeeCallback)(
  void *cls,
  const struct TALER_GlobalFeeSet *fees,
  struct GNUNET_TIME_Relative purse_timeout,
  struct GNUNET_TIME_Relative history_expiration,
  uint32_t purse_account_limit,
  struct GNUNET_TIME_Timestamp start_date,
  struct GNUNET_TIME_Timestamp end_date,
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
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_WithdrawCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_BlindedCoinHashP *h_blind_ev,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Timestamp execution_date,
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
 * Function called with the results of the lookup of the
 * transaction data associated with a wire transfer identifier.
 *
 * @param cls closure
 * @param rowid which row in the table is the information from (for diagnostics)
 * @param merchant_pub public key of the merchant (should be same for all callbacks with the same @e cls)
 * @param account_payto_uri which account did the transfer go to?
 * @param h_payto hash over @a account_payto_uri as it is in the DB
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
  const char *account_payto_uri,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp exec_time,
  const struct TALER_PrivateContractHashP *h_contract_terms,
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
 * @param payto_uri details of the receiver, URI in payto://-format
 * @param amount amount that was wired
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to stop iteration
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_WireTransferOutCallback)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Timestamp date,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const char *payto_uri,
  const struct TALER_Amount *amount);


/**
 * Function called on transient aggregations matching
 * a particular hash of a payto URI.
 *
 * @param cls
 * @param payto_uri corresponding payto URI
 * @param wtid wire transfer identifier of transient aggregation
 * @param merchant_pub public key of the merchant
 * @param total amount aggregated so far
 * @return true to continue iterating
 */
typedef bool
(*TALER_EXCHANGEDB_TransientAggregationCallback)(
  void *cls,
  const char *payto_uri,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_Amount *total);


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
typedef enum GNUNET_GenericReturnValue
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
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_RecoupCallback)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *amount,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_CoinPublicInfo *coin,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const union GNUNET_CRYPTO_BlindingSecretP *coin_blind);


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
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_RecoupRefreshCallback)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *amount,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  const struct TALER_DenominationHashP *old_denom_pub_hash,
  const struct TALER_CoinPublicInfo *coin,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const union GNUNET_CRYPTO_BlindingSecretP *coin_blind);


/**
 * Function called about reserve opening operations.
 *
 * @param cls closure
 * @param rowid row identifier used to uniquely identify the reserve closing operation
 * @param reserve_payment how much to pay from the
 *        reserve's own balance for opening the reserve
 * @param request_timestamp when was the request created
 * @param reserve_expiration desired expiration time for the reserve
 * @param purse_limit minimum number of purses the client
 *       wants to have concurrently open for this reserve
 * @param reserve_pub public key of the reserve
 * @param reserve_sig signature affirming the operation
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_ReserveOpenCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_Amount *reserve_payment,
  struct GNUNET_TIME_Timestamp request_timestamp,
  struct GNUNET_TIME_Timestamp reserve_expiration,
  uint32_t purse_limit,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig);


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
 * @param close_request_row row with the responsible close
 *            request, 0 if regular expiration triggered close
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_ReserveClosedCallback)(
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Timestamp execution_date,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *closing_fee,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *receiver_account,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  uint64_t close_request_row);


/**
 * Function called with the amounts historically
 * withdrawn from the same origin account.
 *
 * @param cls closure
 * @param val one of the withdrawn amounts
 */
typedef void
(*TALER_EXCHANGEDB_WithdrawHistoryCallback)(
  void *cls,
  const struct TALER_Amount *val);

/**
 * Function called with details about expired reserves.
 *
 * @param cls closure
 * @param reserve_pub public key of the reserve
 * @param left amount left in the reserve
 * @param account_details information about the reserve's bank account, in payto://-format
 * @param expiration_date when did the reserve expire
 * @param close_request_row row that caused the reserve
 *        to be closed, 0 if it expired without request
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO to retry
 *         #GNUNET_SYSERR on hard failures (exit)
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_ReserveExpiredCallback)(
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *left,
  const char *account_details,
  struct GNUNET_TIME_Timestamp expiration_date,
  uint64_t close_request_row);


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
  const union GNUNET_CRYPTO_BlindingSecretP *coin_blind,
  const struct TALER_BlindedCoinHashP *h_blinded_ev,
  const struct TALER_Amount *amount);


/**
 * Function called on (batch) deposits will need a wire
 * transfer.
 *
 * @param cls closure
 * @param batch_deposit_serial_id where in the table are we
 * @param total_amount value of all missing deposits, including fees
 * @param wire_target_h_payto hash of the recipient account's payto URI
 * @param deadline what was the earliest requested wire transfer deadline
 */
typedef void
(*TALER_EXCHANGEDB_WireMissingCallback)(
  void *cls,
  uint64_t batch_deposit_serial_id,
  const struct TALER_Amount *total_amount,
  const struct TALER_PaytoHashP *wire_target_h_payto,
  struct GNUNET_TIME_Timestamp deadline);


/**
 * Function called on aggregations that were done for
 * a (batch) deposit.
 *
 * @param cls closure
 * @param tracking_serial_id where in the table are we
 * @param batch_deposit_serial_id which batch deposit was aggregated
 */
typedef void
(*TALER_EXCHANGEDB_AggregationCallback)(
  void *cls,
  uint64_t tracking_serial_id,
  uint64_t batch_deposit_serial_id);


/**
 * Function called on purse requests.
 *
 * @param cls closure
 * @param rowid purse request table row of the purse
 * @param purse_pub public key of the purse
 * @param merge_pub public key representing the merge capability
 * @param purse_creation when was the purse created?
 * @param purse_expiration when would an unmerged purse expire
 * @param h_contract_terms contract associated with the purse
 * @param age_limit the age limit for deposits into the purse
 * @param target_amount amount to be put into the purse
 * @param purse_sig signature of the purse over the initialization data
 * @return #GNUNET_OK to continue to iterate
   */
typedef enum GNUNET_GenericReturnValue
(*TALER_EXCHANGEDB_PurseRequestCallback)(
  void *cls,
  uint64_t rowid,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  struct GNUNET_TIME_Timestamp purse_creation,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint32_t age_limit,
  const struct TALER_Amount *target_amount,
  const struct TALER_PurseContractSignatureP *purse_sig);


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
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue);


/**
 * Return AML status.
 *
 * @param cls closure
 * @param row_id current row in AML status table
 * @param h_payto account for which the attribute data is stored
 * @param threshold currently monthly threshold that would trigger an AML check
 * @param status what is the current AML decision
 */
typedef void
(*TALER_EXCHANGEDB_AmlStatusCallback)(
  void *cls,
  uint64_t row_id,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_Amount *threshold,
  enum TALER_AmlDecisionState status);


/**
 * Return historic AML decision.
 *
 * @param cls closure
 * @param new_threshold new monthly threshold that would trigger an AML check
 * @param new_status AML decision status
 * @param decision_time when was the decision made
 * @param justification human-readable text justifying the decision
 * @param decider_pub public key of the staff member
 * @param decider_sig signature of the staff member
 */
typedef void
(*TALER_EXCHANGEDB_AmlHistoryCallback)(
  void *cls,
  const struct TALER_Amount *new_threshold,
  enum TALER_AmlDecisionState new_status,
  struct GNUNET_TIME_Timestamp decision_time,
  const char *justification,
  const struct TALER_AmlOfficerPublicKeyP *decider_pub,
  const struct TALER_AmlOfficerSignatureP *decider_sig);


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
   * Drop the Taler tables.  This should only be used in testcases.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
   */
  enum GNUNET_GenericReturnValue
    (*drop_tables)(void *cls);

  /**
   * Create the necessary tables if they are not present
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param support_partitions true to enable partitioning support (disables foreign key constraints)
   * @param num_partitions number of partitions to create,
   *     (0 to not actually use partitions, 1 to only
   *      setup a default partition, >1 for real partitions)
   * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
   */
  enum GNUNET_GenericReturnValue
    (*create_tables)(void *cls,
                     bool support_partitions,
                     uint32_t num_partitions);


  /**
   * Start a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param name unique name identifying the transaction (for debugging),
   *             must point to a constant
   * @return #GNUNET_OK on success
   */
  enum GNUNET_GenericReturnValue
    (*start)(void *cls,
             const char *name);


  /**
   * Start a READ COMMITTED transaction.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param name unique name identifying the transaction (for debugging)
   *             must point to a constant
   * @return #GNUNET_OK on success
   */
  enum GNUNET_GenericReturnValue
    (*start_read_committed)(void *cls,
                            const char *name);

  /**
   * Start a READ ONLY serializable transaction.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param name unique name identifying the transaction (for debugging)
   *             must point to a constant
   * @return #GNUNET_OK on success
   */
  enum GNUNET_GenericReturnValue
    (*start_read_only)(void *cls,
                       const char *name);


  /**
   * Commit a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*commit)(void *cls);


  /**
   * Do a pre-flight check that we are not in an uncommitted transaction.
   * If we are, try to commit the previous transaction and output a warning.
   * Does not return anything, as we will continue regardless of the outcome.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @return #GNUNET_OK if everything is fine
   *         #GNUNET_NO if a transaction was rolled back
   *         #GNUNET_SYSERR on hard errors
   */
  enum GNUNET_GenericReturnValue
    (*preflight)(void *cls);


  /**
   * Abort/rollback a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   */
  void
  (*rollback) (void *cls);


  /**
   * Register callback to be invoked on events of type @a es.
   *
   * @param cls database context to use
   * @param timeout how long to wait at most
   * @param es specification of the event to listen for
   * @param cb function to call when the event happens, possibly
   *         multiple times (until cancel is invoked)
   * @param cb_cls closure for @a cb
   * @return handle useful to cancel the listener
   */
  struct GNUNET_DB_EventHandler *
  (*event_listen)(void *cls,
                  struct GNUNET_TIME_Relative timeout,
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
   * @param es specification of the event to generate
   * @param extra additional event data provided
   * @param extra_size number of bytes in @a extra
   */
  void
  (*event_notify)(void *cls,
                  const struct GNUNET_DB_EventHeaderP *es,
                  const void *extra,
                  size_t extra_size);


  /**
   * Insert information about a denomination key and in particular
   * the properties (value, fees, expiration times) the coins signed
   * with this key have.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param denom_pub the public key used for signing coins of this denomination
   * @param issue issuing information with value, fees and other info about the denomination
   * @return status of the query
   */
  enum GNUNET_DB_QueryStatus
    (*insert_denomination_info)(
    void *cls,
    const struct TALER_DenominationPublicKey *denom_pub,
    const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue);


  /**
   * Fetch information about a denomination key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param denom_pub_hash hash of the public key used for signing coins of this denomination
   * @param[out] issue set to issue information with value, fees and other info about the coin
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_denomination_info)(
    void *cls,
    const struct TALER_DenominationHashP *denom_pub_hash,
    struct TALER_EXCHANGEDB_DenominationKeyInformation *issue);


  /**
   * Function called on every known denomination key.  Runs in its
   * own read-only transaction (hence no session provided).  Note that
   * the "master" field in the callback's 'issue' argument will NOT
   * be initialized yet.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param cb function to call on each denomination key
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*iterate_denomination_info)(void *cls,
                                 TALER_EXCHANGEDB_DenominationCallback cb,
                                 void *cb_cls);


  /**
   * Function called to invoke @a cb on every known denomination key (revoked
   * and non-revoked) that has been signed by the master key. Runs in its own
   * read-only transaction.
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
   * expired keys are skipped. Runs in its own read-only transaction.
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
   * auditors are skipped. Runs in its own read-only transaction.
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
   * skipped. Runs in its own read-only transaction.
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
   * @param[in,out] reserve the reserve data.  The public key of the reserve should be set
   *          in this structure; it is used to query the database.  The balance
   *          and expiration are then filled accordingly.
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*reserves_get)(void *cls,
                    struct TALER_EXCHANGEDB_Reserve *reserve);


  /**
   * Get the origin of funds of a reserve.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param reserve_pub public key of the reserve
   * @param[out] h_payto set to hash of the wire source payto://-URI
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*reserves_get_origin)(
    void *cls,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    struct TALER_PaytoHashP *h_payto);


  /**
   * Extract next KYC alert.  Deletes the alert.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param trigger_type which type of alert to drain
   * @param[out] h_payto set to hash of payto-URI where KYC status changed
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*drain_kyc_alert)(void *cls,
                       uint32_t trigger_type,
                       struct TALER_PaytoHashP *h_payto);


  /**
   * Insert a batch of incoming transaction into reserves.  New reserves are
   * also created through this function.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param reserves
   * @param reserves_length length of the @a reserves array
   * @param[out] results array of transaction status codes of length @a reserves_length,
   *             set to the status of the
   */
  enum GNUNET_DB_QueryStatus
    (*reserves_in_insert)(
    void *cls,
    const struct TALER_EXCHANGEDB_ReserveInInfo *reserves,
    unsigned int reserves_length,
    enum GNUNET_DB_QueryStatus *results);


  /**
   * Locate a nonce for use with a particular public key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param nonce the nonce to be locked
   * @param denom_pub_hash hash of the public key of the denomination
   * @param target public key the nonce is to be locked to
   * @return statement execution status
   */
  enum GNUNET_DB_QueryStatus
    (*lock_nonce)(void *cls,
                  const struct GNUNET_CRYPTO_CsSessionNonce *nonce,
                  const struct TALER_DenominationHashP *denom_pub_hash,
                  const union TALER_EXCHANGEDB_NonceLockTargetP *target);


  /**
   * Locate the response for a withdraw request under a hash that uniquely
   * identifies the withdraw operation.  Used to ensure idempotency of the
   * request.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param bch hash that uniquely identifies the withdraw operation
   * @param[out] collectable corresponding collectable coin (blind signature)
   *                    if a coin is found
   * @return statement execution status
   */
  enum GNUNET_DB_QueryStatus
    (*get_withdraw_info)(void *cls,
                         const struct TALER_BlindedCoinHashP *bch,
                         struct TALER_EXCHANGEDB_CollectableBlindcoin *
                         collectable);


  /**
   * FIXME: merge do_batch_withdraw and do_batch_withdraw_insert into one API,
   * which takes as input (among others)
   *   - denom_serial[]
   *   - blinded_coin_evs[]
   *   - denom_sigs[]
   * The implementation should persist the data as _arrays_ in the DB.
   */

  /**
   * Perform reserve update as part of a batch withdraw operation, checking
   * for sufficient balance. Persisting the withdrawal details is done
   * separately!
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param now current time (rounded)
   * @param reserve_pub public key of the reserve to debit
   * @param amount total amount to withdraw
   * @param do_age_check if set, the batch-withdrawal can only succeed when the reserve has no age restriction (birthday) set.
   * @param[out] found set to true if the reserve was found
   * @param[out] balance_ok set to true if the balance was sufficient
   * @param[out] reserve_balance set to original balance of the reserve
   * @param[out] age_ok set to true if no age requirements were defined on the reserve or @e do_age_check was false
   * @param[out] allowed_maximum_age when @e age_ok is false, set to the allowed maximum age for withdrawal from the reserve.  The client MUST then use the age-withdraw endpoint
   * @param[out] ruuid set to the reserve's UUID (reserves table row)
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*do_batch_withdraw)(
    void *cls,
    struct GNUNET_TIME_Timestamp now,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    const struct TALER_Amount *amount,
    bool do_age_check,
    bool *found,
    bool *balance_ok,
    struct TALER_Amount *reserve_balance,
    bool *age_ok,
    uint16_t *allowed_maximum_age,
    uint64_t *ruuid);


  /**
   * Perform insert as part of a batch withdraw operation, and persisting the
   * withdrawal details.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param nonce client-contributed input for CS denominations that must be checked for idempotency, or NULL for non-CS withdrawals
   * @param collectable corresponding collectable coin (blind signature)
   * @param now current time (rounded)
   * @param ruuid reserve UUID
   * @param[out] denom_unknown set if the denomination is unknown in the DB
   * @param[out] conflict if the envelope was already in the DB
   * @param[out] nonce_reuse if @a nonce was non-NULL and reused
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*do_batch_withdraw_insert)(
    void *cls,
    const union GNUNET_CRYPTO_BlindSessionNonce *nonce,
    const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable,
    struct GNUNET_TIME_Timestamp now,
    uint64_t ruuid,
    bool *denom_unknown,
    bool *conflict,
    bool *nonce_reuse);

  /**
   * Locate the response for a age-withdraw request under a hash of the
   * commitment and reserve_pub that uniquely identifies the age-withdraw
   * operation.  Used to ensure idempotency of the request.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param reserve_pub public key of the reserve for which the age-withdraw request is made
   * @param ach hash that uniquely identifies the age-withdraw operation
   * @param[out] aw corresponding details of the previous age-withdraw request if an entry was found
   * @return statement execution status
   */
  enum GNUNET_DB_QueryStatus
    (*get_age_withdraw)(
    void *cls,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    const struct TALER_AgeWithdrawCommitmentHashP *ach,
    struct TALER_EXCHANGEDB_AgeWithdraw *aw);

  /**
   * Perform an age-withdraw operation, checking for sufficient balance and
   * fulfillment of age requirements and possibly persisting the withdrawal
   * details.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param commitment corresponding commitment for the age-withdraw
   * @param[out] found set to true if the reserve was found
   * @param[out] balance_ok set to true if the balance was sufficient
   * @param[out] reserve_balance set to original balance of the reserve
   * @param[out] age_ok set to true if age requirements were met
   * @param[out] allowed_maximum_age if @e age_ok is FALSE, this is set to the allowed maximum age
   * @param[out] reserve_birthday if @e age_ok is FALSE, this is set to the reserve's birthday
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*do_age_withdraw)(
    void *cls,
    const struct TALER_EXCHANGEDB_AgeWithdraw *commitment,
    struct GNUNET_TIME_Timestamp now,
    bool *found,
    bool *balance_ok,
    struct TALER_Amount *reserve_balance,
    bool *age_ok,
    uint16_t *allowed_maximum_age,
    uint32_t *reserve_birthday,
    bool *conflict);

  /**
   * Retrieve the details to a policy given by its hash_code
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param hc Hash code that identifies the policy
   * @param[out] detail retrieved policy details
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*get_policy_details)(
    void *cls,
    const struct GNUNET_HashCode *hc,
    struct TALER_PolicyDetails *detail);

  /**
   * Persist the policy details that extends a deposit.  The particular policy
   * - referenced by details->hash_code - might already exist in the table, in
   * which case the call will update the contents of the record with @e details
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param details The parsed `struct TALER_PolicyDetails` according to the responsible policy extension.
   * @param[out] policy_details_serial_id The ID of the entry in the policy_details table
   * @param[out] accumulated_total The total amount accumulated in that policy
   * @param[out] fulfillment_state The state of policy.  If the state was Insufficient prior to the call and the provided deposit raises the accumulated_total above the commitment, it will be set to Ready.
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*persist_policy_details)(
    void *cls,
    const struct TALER_PolicyDetails *details,
    uint64_t *policy_details_serial_id,
    struct TALER_Amount *accumulated_total,
    enum TALER_PolicyFulfillmentState *fulfillment_state);


  /**
   * Perform deposit operation, checking for sufficient balance
   * of the coin and possibly persisting the deposit details.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param bd batch deposit operation details
   * @param[in,out] exchange_timestamp time to use for the deposit (possibly updated)
   * @param[out] balance_ok set to true if the balance was sufficient
   * @param[out] bad_balance_index set to the first index of a coin for which the balance was insufficient,
   *             only used if @a balance_ok is set to false.
   * @param[out] ctr_conflict set to true if the same contract terms hash was previously submitted with other meta data (deadlines, wallet_data_hash, wire data etc.)
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*do_deposit)(
    void *cls,
    const struct TALER_EXCHANGEDB_BatchDeposit *bd,
    struct GNUNET_TIME_Timestamp *exchange_timestamp,
    bool *balance_ok,
    uint32_t *bad_balance_index,
    bool *ctr_conflict);


  /**
   * Perform melt operation, checking for sufficient balance
   * of the coin and possibly persisting the melt details.
   *
   * @param cls the plugin-specific state
   * @param rms client-contributed input for CS denominations that must be checked for idempotency, or NULL for non-CS withdrawals
   * @param[in,out] refresh refresh operation details; the noreveal_index
   *                is set in case the coin was already melted before
   * @param known_coin_id row of the coin in the known_coins table
   * @param[in,out] zombie_required true if the melt must only succeed if the coin is a zombie, set to false if the requirement was satisfied
   * @param[out] balance_ok set to true if the balance was sufficient
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*do_melt)(
    void *cls,
    const struct TALER_RefreshMasterSecretP *rms,
    struct TALER_EXCHANGEDB_Refresh *refresh,
    uint64_t known_coin_id,
    bool *zombie_required,
    bool *balance_ok);


  /**
   * Add a proof of fulfillment of an policy
   *
   * @param cls the plugin-specific state
   * @param[in,out] fulfillment The proof of fulfillment and serial_ids of the policy_details along with their new state and potential new amounts.
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*add_policy_fulfillment_proof)(
    void *cls,
    struct TALER_PolicyFulfillmentTransactionData *fulfillment);


  /**
   * Check if the given @a nonce was properly locked to the given @a old_coin_pub. If so, check if we already
   * created CS signatures for the given @a nonce and @a new_denom_pub_hashes,
   * and if so, return them in @a s_scalars.  Otherwise, persist the
   * signatures from @a s_scalars in the database.
   *
   * @param cls the plugin-specific state
   * @param nonce the client-provided nonce where we must prevent reuse
   * @param old_coin_pub public key the nonce was locked to
   * @param num_fresh_coins array length, number of fresh coins revealed
   * @param[in,out] crfcds array of data about the fresh coins, of length @a num_fresh_coins
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*cs_refreshes_reveal)(
    void *cls,
    const struct GNUNET_CRYPTO_CsSessionNonce *nonce,
    const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
    unsigned int num_fresh_coins,
    struct TALER_EXCHANGEDB_CsRevealFreshCoinData *crfcds);


  /**
   * Perform refund operation, checking for sufficient deposits
   * of the coin and possibly persisting the refund details.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param refund refund operation details
   * @param deposit_fee deposit fee applicable for the coin, possibly refunded
   * @param known_coin_id row of the coin in the known_coins table
   * @param[out] not_found set if the deposit was not found
   * @param[out] refund_ok  set if the refund succeeded (below deposit amount)
   * @param[out] gone if the merchant was already paid
   * @param[out] conflict set if the refund ID was re-used
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*do_refund)(
    void *cls,
    const struct TALER_EXCHANGEDB_Refund *refund,
    const struct TALER_Amount *deposit_fee,
    uint64_t known_coin_id,
    bool *not_found,
    bool *refund_ok,
    bool *gone,
    bool *conflict);


  /**
   * Perform recoup operation, checking for sufficient deposits
   * of the coin and possibly persisting the recoup details.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param reserve_pub public key of the reserve to credit
   * @param reserve_out_serial_id row in the reserves_out table justifying the recoup
   * @param coin_bks coin blinding key secret to persist
   * @param coin_pub public key of the coin being recouped
   * @param known_coin_id row of the @a coin_pub in the known_coins table
   * @param coin_sig signature of the coin requesting the recoup
   * @param[in,out] recoup_timestamp recoup timestamp, set if recoup existed
   * @param[out] recoup_ok  set if the recoup succeeded (balance ok)
   * @param[out] internal_failure set on internal failures
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*do_recoup)(
    void *cls,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    uint64_t reserve_out_serial_id,
    const union GNUNET_CRYPTO_BlindingSecretP *coin_bks,
    const struct TALER_CoinSpendPublicKeyP *coin_pub,
    uint64_t known_coin_id,
    const struct TALER_CoinSpendSignatureP *coin_sig,
    struct GNUNET_TIME_Timestamp *recoup_timestamp,
    bool *recoup_ok,
    bool *internal_failure);


  /**
   * Perform recoup-refresh operation, checking for sufficient deposits of the
   * coin and possibly persisting the recoup-refresh details.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param old_coin_pub public key of the old coin to credit
   * @param rrc_serial row in the refresh_revealed_coins table justifying the recoup-refresh
   * @param coin_bks coin blinding key secret to persist
   * @param coin_pub public key of the coin being recouped
   * @param known_coin_id row of the @a coin_pub in the known_coins table
   * @param coin_sig signature of the coin requesting the recoup
   * @param[in,out] recoup_timestamp recoup timestamp, set if recoup existed
   * @param[out] recoup_ok  set if the recoup-refresh succeeded (balance ok)
   * @param[out] internal_failure set on internal failures
   * @return query execution status
   */
  enum GNUNET_DB_QueryStatus
    (*do_recoup_refresh)(
    void *cls,
    const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
    uint64_t rrc_serial,
    const union GNUNET_CRYPTO_BlindingSecretP *coin_bks,
    const struct TALER_CoinSpendPublicKeyP *coin_pub,
    uint64_t known_coin_id,
    const struct TALER_CoinSpendSignatureP *coin_sig,
    struct GNUNET_TIME_Timestamp *recoup_timestamp,
    bool *recoup_ok,
    bool *internal_failure);


  /**
   * Compile a list of (historic) transactions performed with the given reserve
   * (withdraw, incoming wire, open, close operations).  Should return 0 if the @a
   * reserve_pub is unknown, otherwise determine @a etag_out and if it is past @a
   * etag_in return the history after @a start_off. @a etag_out should be set
   * to the last row ID of the given @a reserve_pub in the reserve history table.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param reserve_pub public key of the reserve
   * @param start_off maximum starting offset in history to exclude from returning
   * @param etag_in up to this offset the client already has a response, do not
   *                   return anything unless @a etag_out will be larger
   * @param[out] etag_out set to the latest history offset known for this @a coin_pub
   * @param[out] balance set to the reserve balance
   * @param[out] rhp set to known transaction history (NULL if reserve is unknown)
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*get_reserve_history)(void *cls,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           uint64_t start_off,
                           uint64_t etag_in,
                           uint64_t *etag_out,
                           struct TALER_Amount *balance,
                           struct TALER_EXCHANGEDB_ReserveHistory **rhp);


  /**
   * The current reserve balance of the specified reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param reserve_pub public key of the reserve
   * @param[out] balance set to the reserve balance
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*get_reserve_balance)(void *cls,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           struct TALER_Amount *balance);


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
   * @param denom_pub_hash denomination to count by
   * @return number of coins if non-negative, otherwise an `enum GNUNET_DB_QueryStatus`
   */
  long long
  (*count_known_coins) (void *cls,
                        const struct TALER_DenominationHashP *denom_pub_hash);


  /**
   * Make sure the given @a coin is known to the database.
   *
   * @param cls database connection plugin state
   * @param coin the coin that must be made known
   * @param[out] known_coin_id set to the unique row of the coin
   * @param[out] denom_pub_hash set to the conflicting denomination hash on conflict
   * @param[out] age_hash set to the conflicting age hash on conflict
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
    TALER_EXCHANGEDB_CKS_DENOM_CONFLICT = -3,

    /**
     * Conflicting coin (expected NULL age hash) already in database.
     */
    TALER_EXCHANGEDB_CKS_AGE_CONFLICT_EXPECTED_NULL = -4,

    /**
     * Conflicting coin (unexpected NULL age hash) already in database.
     */
    TALER_EXCHANGEDB_CKS_AGE_CONFLICT_EXPECTED_NON_NULL = -5,

    /**
     * Conflicting coin (different age hash) already in database.
     */
    TALER_EXCHANGEDB_CKS_AGE_CONFLICT_VALUE_DIFFERS = -6,

  }
  (*ensure_coin_known)(void *cls,
                       const struct TALER_CoinPublicInfo *coin,
                       uint64_t *known_coin_id,
                       struct TALER_DenominationHashP *denom_pub_hash,
                       struct TALER_AgeCommitmentHash *age_hash);


  /**
   * Make sure the array of given @a coin is known to the database.
   *
   * @param cls database connection plugin state
   * @param coin array of coins that must be made known
   * @param[out] result array where to store information about each coin
   * @param coin_length length of the @a coin and @a result arraysf
   * @param batch_size desired (maximum) batch size
   * @return database transaction status, non-negative on success
   */
  enum GNUNET_DB_QueryStatus
    (*batch_ensure_coin_known)(
    void *cls,
    const struct TALER_CoinPublicInfo *coin,
    struct TALER_EXCHANGEDB_CoinInfo *result,
    unsigned int coin_length,
    unsigned int batch_size);


  /**
   * Retrieve information about the given @a coin from the database.
   *
   * @param cls database connection plugin state
   * @param coin the coin that must be made known
   * @return database transaction status, non-negative on success
   */
  enum GNUNET_DB_QueryStatus
    (*get_known_coin)(void *cls,
                      const struct TALER_CoinSpendPublicKeyP *coin_pub,
                      struct TALER_CoinPublicInfo *coin_info);


  /**
   * Retrieve the denomination of a known coin.
   *
   * @param cls the plugin closure
   * @param coin_pub the public key of the coin to search for
   * @param[out] known_coin_id set to the ID of the coin in the known_coins table
   * @param[out] denom_hash where to store the hash of the coins denomination
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_coin_denomination)(void *cls,
                             const struct TALER_CoinSpendPublicKeyP *coin_pub,
                             uint64_t *known_coin_id,
                             struct TALER_DenominationHashP *denom_hash);


  /**
   * Check if we have the specified deposit already in the database.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param h_contract_terms contract to check for
   * @param h_wire wire hash to check for
   * @param coin_pub public key of the coin to check for
   * @param merchant merchant public key to check for
   * @param refund_deadline expected refund deadline
   * @param[out] deposit_fee set to the deposit fee the exchange charged
   * @param[out] exchange_timestamp set to the time when the exchange received the deposit
   * @return 1 if we know this operation,
   *         0 if this exact deposit is unknown to us,
   *         otherwise transaction error status
   */
  // FIXME: rename!
  enum GNUNET_DB_QueryStatus
    (*have_deposit2)(
    void *cls,
    const struct TALER_PrivateContractHashP *h_contract_terms,
    const struct TALER_MerchantWireHashP *h_wire,
    const struct TALER_CoinSpendPublicKeyP *coin_pub,
    const struct TALER_MerchantPublicKeyP *merchant,
    struct GNUNET_TIME_Timestamp refund_deadline,
    struct TALER_Amount *deposit_fee,
    struct GNUNET_TIME_Timestamp *exchange_timestamp);


  /**
   * Insert information about refunded coin into the database.
   * Used in tests and for benchmarking.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param refund refund information to store
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
    (*insert_refund)(void *cls,
                     const struct TALER_EXCHANGEDB_Refund *refund);


  /**
   * Select refunds by @a coin_pub, @a merchant_pub and @a h_contract.
   *
   * @param cls closure of plugin
   * @param coin_pub coin to get refunds for
   * @param merchant_pub merchant to get refunds for
   * @param h_contract_pub contract (hash) to get refunds for
   * @param cb function to call for each refund found
   * @param cb_cls closure for @a cb
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
    (*select_refunds_by_coin)(void *cls,
                              const struct TALER_CoinSpendPublicKeyP *coin_pub,
                              const struct
                              TALER_MerchantPublicKeyP *merchant_pub,
                              const struct
                              TALER_PrivateContractHashP *h_contract,
                              TALER_EXCHANGEDB_RefundCoinCallback cb,
                              void *cb_cls);


  /**
   * Obtain information about deposits that are ready to be executed.
   * Such deposits must not be marked as "done", and the
   * execution time, the refund deadlines must both be in the past and
   * the KYC status must be 'ok'.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param start_shard_row minimum shard row to select
   * @param end_shard_row maximum shard row to select (inclusive)
   * @param[out] merchant_pub set to the public key of a merchant with a ready deposit
   * @param[out] payto_uri set to the account of the merchant, to be freed by caller
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_ready_deposit)(void *cls,
                         uint64_t start_shard_row,
                         uint64_t end_shard_row,
                         struct TALER_MerchantPublicKeyP *merchant_pub,
                         char **payto_uri);


  /**
   * Aggregate all matching deposits for @a h_payto and
   * @a merchant_pub, returning the total amounts.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto destination of the wire transfer
   * @param merchant_pub public key of the merchant
   * @param wtid wire transfer ID to set for the aggregate
   * @param[out] total set to the sum of the total deposits minus applicable deposit fees and refunds
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*aggregate)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    const struct TALER_MerchantPublicKeyP *merchant_pub,
    const struct TALER_WireTransferIdentifierRawP *wtid,
    struct TALER_Amount *total);


  /**
   * Create a new entry in the transient aggregation table.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto destination of the wire transfer
   * @param exchange_account_section exchange account to use
   * @param merchant_pub public key of the merchant
   * @param wtid the raw wire transfer identifier to be used
   * @param kyc_requirement_row row in legitimization_requirements that need to be satisfied to continue, or 0 for none
   * @param total amount to be wired in the future
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*create_aggregation_transient)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    const char *exchange_account_section,
    const struct TALER_MerchantPublicKeyP *merchant_pub,
    const struct TALER_WireTransferIdentifierRawP *wtid,
    uint64_t kyc_requirement_row,
    const struct TALER_Amount *total);


  /**
   * Select existing entry in the transient aggregation table.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto destination of the wire transfer
   * @param merchant_pub public key of the merchant
   * @param exchange_account_section exchange account to use
   * @param[out] wtid set to the raw wire transfer identifier to be used
   * @param[out] total existing amount to be wired in the future
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*select_aggregation_transient)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    const struct TALER_MerchantPublicKeyP *merchant_pub,
    const char *exchange_account_section,
    struct TALER_WireTransferIdentifierRawP *wtid,
    struct TALER_Amount *total);


  /**
   * Find existing entry in the transient aggregation table.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto destination of the wire transfer
   * @param cb function to call on each matching entry
   * @param cb_cls closure for @a cb
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*find_aggregation_transient)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    TALER_EXCHANGEDB_TransientAggregationCallback cb,
    void *cb_cls);


  /**
   * Update existing entry in the transient aggregation table.
   * @a h_payto is only needed for query performance.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto destination of the wire transfer
   * @param wtid the raw wire transfer identifier to update
   * @param kyc_requirement_row row in legitimization_requirements that need to be satisfied to continue, or 0 for none
   * @param total new total amount to be wired in the future
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*update_aggregation_transient)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    const struct TALER_WireTransferIdentifierRawP *wtid,
    uint64_t kyc_requirement_row,
    const struct TALER_Amount *total);


  /**
   * Delete existing entry in the transient aggregation table.
   * @a h_payto is only needed for query performance.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto destination of the wire transfer
   * @param wtid the raw wire transfer identifier to update
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*delete_aggregation_transient)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    const struct TALER_WireTransferIdentifierRawP *wtid);


  /**
   * Lookup melt commitment data under the given @a rc.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param rc commitment to use for the lookup
   * @param[out] melt where to store the result; note that
   *             melt->session.coin.denom_sig will be set to NULL
   *             and is not fetched by this routine (as it is not needed by the client)
   * @param[out] melt_serial_id set to the row ID of @a rc in the refresh_commitments table
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*get_melt)(void *cls,
                const struct TALER_RefreshCommitmentP *rc,
                struct TALER_EXCHANGEDB_Melt *melt,
                uint64_t *melt_serial_id);


  /**
   * Store in the database which coin(s) the wallet wanted to create
   * in a given refresh operation and all of the other information
   * we learned or created in the reveal step.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param melt_serial_id row ID of the commitment / melt operation in refresh_commitments
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
    uint64_t melt_serial_id,
    uint32_t num_rrcs,
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
    unsigned int num_tprivs,
    const struct TALER_TransferPrivateKeyP *tprivs,
    const struct TALER_TransferPublicKeyP *tp);


  /**
   * Lookup in the database for the fresh coins that we
   * created in the given refresh operation.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param rc identify commitment and thus refresh operation
   * @param cb function to call with the results
   * @param cb_cls closure for @a cb
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*get_refresh_reveal)(void *cls,
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
   * @param coin_pub public key of the coin
   * @param ldc function to call for each session the coin was melted into
   * @param ldc_cls closure for @a tdc
   * @return statement execution status
   */
  enum GNUNET_DB_QueryStatus
    (*get_link_data)(void *cls,
                     const struct TALER_CoinSpendPublicKeyP *coin_pub,
                     TALER_EXCHANGEDB_LinkCallback ldc,
                     void *tdc_cls);


  /**
   * Compile a list of (historic) transactions performed with the given coin
   * (melt, refund, recoup and deposit operations).  Should return 0 if the @a
   * coin_pub is unknown, otherwise determine @a etag_out and if it is past @a
   * etag_in return the history after @a start_off. @a etag_out should be set
   * to the last row ID of the given @a coin_pub in the coin history table.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param coin_pub coin to investigate
   * @param start_off starting offset from which on to return entries
   * @param etag_in up to this offset the client already has a response, do not
   *                   return anything unless @a etag_out will be larger
   * @param[out] etag_out set to the latest history offset known for this @a coin_pub
   * @param[out] balance set to current balance of the coin
   * @param[out] h_denom_pub set to denomination public key of the coin
   * @param[out] tlp set to list of transactions, set to NULL if coin has no
   *             transaction history past @a start_off or if @a etag_in is equal
   *             to the value written to @a etag_out.
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*get_coin_transactions)(
    void *cls,
    const struct TALER_CoinSpendPublicKeyP *coin_pub,
    uint64_t start_off,
    uint64_t etag_in,
    uint64_t *etag_out,
    struct TALER_Amount *balance,
    struct TALER_DenominationHashP *h_denom_pub,
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
   * @param wtid the raw wire transfer identifier we used
   * @param cb function to call on each transaction found
   * @param cb_cls closure for @a cb
   * @return query status of the transaction
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_wire_transfer)(void *cls,
                            const struct TALER_WireTransferIdentifierRawP *wtid,
                            TALER_EXCHANGEDB_AggregationDataCallback cb,
                            void *cb_cls);


  /**
   * Try to find the wire transfer details for a deposit operation.
   * If we did not execute the deposit yet, return when it is supposed
   * to be executed.
   *
   * @param cls closure
   * @param h_contract_terms hash of the proposal data
   * @param h_wire hash of merchant wire details
   * @param coin_pub public key of deposited coin
   * @param merchant_pub merchant public key
   * @param[out] pending set to true if the transaction is still pending
   * @param[out] wtid wire transfer identifier, only set if @a pending is false
   * @param[out] coin_contribution how much did the coin we asked about
   *        contribute to the total transfer value? (deposit value including fee)
   * @param[out] coin_fee how much did the exchange charge for the deposit fee
   * @param[out] execution_time when was the transaction done, or
   *         when we expect it to be done (if @a pending is false)
   * @param[out] kyc set to the kyc status of the receiver (if @a pending)
   * @param[out] aml_decision set to the current AML status for the target account
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_transfer_by_deposit)(
    void *cls,
    const struct TALER_PrivateContractHashP *h_contract_terms,
    const struct TALER_MerchantWireHashP *h_wire,
    const struct TALER_CoinSpendPublicKeyP *coin_pub,
    const struct TALER_MerchantPublicKeyP *merchant_pub,
    bool *pending,
    struct TALER_WireTransferIdentifierRawP *wtid,
    struct GNUNET_TIME_Timestamp *exec_time,
    struct TALER_Amount *amount_with_fee,
    struct TALER_Amount *deposit_fee,
    struct TALER_EXCHANGEDB_KycStatus *kyc,
    enum TALER_AmlDecisionState *aml_decision);


  /**
   * Insert wire transfer fee into database.
   *
   * @param cls closure
   * @param wire_method which wire method is the fee about?
   * @param start_date when does the fee go into effect
   * @param end_date when does the fee end being valid
   * @param fees how high is are the wire fees
   * @param master_sig signature over the above by the exchange master key
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_wire_fee)(void *cls,
                       const char *wire_method,
                       struct GNUNET_TIME_Timestamp start_date,
                       struct GNUNET_TIME_Timestamp end_date,
                       const struct TALER_WireFeeSet *fees,
                       const struct TALER_MasterSignatureP *master_sig);


  /**
   * Insert global fee set into database.
   *
   * @param cls closure
   * @param start_date when does the fees go into effect
   * @param end_date when does the fees end being valid
   * @param fees how high is are the global fees
   * @param purse_timeout when do purses time out
   * @param history_expiration how long are account histories preserved
   * @param purse_account_limit how many purses are free per account
   * @param master_sig signature over the above by the exchange master key
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_global_fee)(void *cls,
                         struct GNUNET_TIME_Timestamp start_date,
                         struct GNUNET_TIME_Timestamp end_date,
                         const struct TALER_GlobalFeeSet *fees,
                         struct GNUNET_TIME_Relative purse_timeout,
                         struct GNUNET_TIME_Relative history_expiration,
                         uint32_t purse_account_limit,

                         const struct TALER_MasterSignatureP *master_sig);


  /**
   * Obtain wire fee from database.
   *
   * @param cls closure
   * @param type type of wire transfer the fee applies for
   * @param date for which date do we want the fee?
   * @param[out] start_date when does the fee go into effect
   * @param[out] end_date when does the fee end being valid
   * @param[out] fees how high are the wire fees
   * @param[out] master_sig signature over the above by the exchange master key
   * @return query status of the transaction
   */
  enum GNUNET_DB_QueryStatus
    (*get_wire_fee)(void *cls,
                    const char *type,
                    struct GNUNET_TIME_Timestamp date,
                    struct GNUNET_TIME_Timestamp *start_date,
                    struct GNUNET_TIME_Timestamp *end_date,
                    struct TALER_WireFeeSet *fees,
                    struct TALER_MasterSignatureP *master_sig);


  /**
   * Obtain global fees from database.
   *
   * @param cls closure
   * @param date for which date do we want the fee?
   * @param[out] start_date when does the fee go into effect
   * @param[out] end_date when does the fee end being valid
   * @param[out] fees how high are the global fees
   * @param[out] purse_timeout when do purses time out
   * @param[out] history_expiration how long are account histories preserved
   * @param[out] purse_account_limit how many purses are free per account
   * @param[out] master_sig signature over the above by the exchange master key
   * @return query status of the transaction
   */
  enum GNUNET_DB_QueryStatus
    (*get_global_fee)(void *cls,
                      struct GNUNET_TIME_Timestamp date,
                      struct GNUNET_TIME_Timestamp *start_date,
                      struct GNUNET_TIME_Timestamp *end_date,
                      struct TALER_GlobalFeeSet *fees,
                      struct GNUNET_TIME_Relative *purse_timeout,
                      struct GNUNET_TIME_Relative *history_expiration,
                      uint32_t *purse_account_limit,
                      struct TALER_MasterSignatureP *master_sig);


  /**
   * Obtain information about expired reserves and their
   * remaining balances.
   *
   * @param cls closure of the plugin
   * @param now timestamp based on which we decide expiration
   * @param rec function to call on expired reserves
   * @param rec_cls closure for @a rec
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*get_expired_reserves)(void *cls,
                            struct GNUNET_TIME_Timestamp now,
                            TALER_EXCHANGEDB_ReserveExpiredCallback rec,
                            void *rec_cls);


  /**
   * Obtain information about force-closed reserves
   * where the close was not yet done (and their remaining
   * balances).  Updates the returned reserve's close
   * status to "done".
   *
   * @param cls closure of the plugin
   * @param rec function to call on (to be) closed reserves
   * @param rec_cls closure for @a rec
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*get_unfinished_close_requests)(
    void *cls,
    TALER_EXCHANGEDB_ReserveExpiredCallback rec,
    void *rec_cls);


  /**
   * Insert reserve open coin deposit data into database.
   * Subtracts the @a coin_total from the coin's balance.
   *
   * @param cls closure
   * @param cpi public information about the coin
   * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_RESERVE_OPEN_DEPOSIT
   * @param known_coin_id ID of the coin in the known_coins table
   * @param coin_total amount to be spent of the coin (including deposit fee)
   * @param reserve_sig signature by the reserve affirming the open operation
   * @param reserve_pub public key of the reserve being opened
   * @param[out] insufficient_funds set to true if the coin's balance is insufficient, otherwise to false
   * @return transaction status code, 0 if operation is already in the DB
   */
  enum GNUNET_DB_QueryStatus
    (*insert_reserve_open_deposit)(
    void *cls,
    const struct TALER_CoinPublicInfo *cpi,
    const struct TALER_CoinSpendSignatureP *coin_sig,
    uint64_t known_coin_id,
    const struct TALER_Amount *coin_total,
    const struct TALER_ReserveSignatureP *reserve_sig,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    bool *insufficient_funds);


  /**
   * Insert reserve close operation into database.
   *
   * @param cls closure
   * @param reserve_pub which reserve is this about?
   * @param total_paid total amount paid (coins and reserve)
   * @param reserve_payment amount to be paid from the reserve
   * @param min_purse_limit minimum number of purses we should be able to open
   * @param reserve_sig signature by the reserve for the operation
   * @param desired_expiration when should the reserve expire (earliest time)
   * @param now when did we the client initiate the action
   * @param open_fee annual fee to be charged for the open operation by the exchange
   * @param[out] no_funds set to true if reserve balance is insufficient
   * @param[out] reserve_balance set to original balance of the reserve
   * @param[out] open_cost set to the actual cost
   * @param[out] final_expiration when will the reserve expire now
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*do_reserve_open)(void *cls,
                       const struct TALER_ReservePublicKeyP *reserve_pub,
                       const struct TALER_Amount *total_paid,
                       const struct TALER_Amount *reserve_payment,
                       uint32_t min_purse_limit,
                       const struct TALER_ReserveSignatureP *reserve_sig,
                       struct GNUNET_TIME_Timestamp desired_expiration,
                       struct GNUNET_TIME_Timestamp now,
                       const struct TALER_Amount *open_fee,
                       bool *no_funds,
                       struct TALER_Amount *reserve_balance,
                       struct TALER_Amount *open_cost,
                       struct GNUNET_TIME_Timestamp *final_expiration);


  /**
   * Select information needed to see if we can close
   * a reserve.
   *
   * @param cls closure
   * @param reserve_pub which reserve is this about?
   * @param[out] balance current reserve balance
   * @param[out] payto_uri set to URL of account that
   *             originally funded the reserve;
   *             could be set to NULL if not known
   * @return transaction status code, 0 if reserve unknown
   */
  enum GNUNET_DB_QueryStatus
    (*select_reserve_close_info)(
    void *cls,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    struct TALER_Amount *balance,
    char **payto_uri);


  /**
   * Select information about reserve close requests.
   *
   * @param cls closure
   * @param reserve_pub which reserve is this about?
   * @param rowid row ID of the close request
   * @param[out] reserve_sig reserve signature affirming
   * @param[out] request_timestamp when was the request made
   * @param[out] close_balance reserve balance at close time
   * @param[out] close_fee closing fee to be charged
   * @param[out] payto_uri set to URL of account that
   *             should receive the money;
   *             could be set to NULL for origin
   * @return transaction status code, 0 if reserve unknown
   */
  enum GNUNET_DB_QueryStatus
    (*select_reserve_close_request_info)(
    void *cls,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    uint64_t rowid,
    struct TALER_ReserveSignatureP *reserve_sig,
    struct GNUNET_TIME_Timestamp *request_timestamp,
    struct TALER_Amount *close_balance,
    struct TALER_Amount *close_fee,
    char **payto_uri);


  /**
   * Select information needed for KYC checks on reserve close: historic
   * reserve closures going to the same account.
   *
   * @param cls closure
   * @param h_payto which target account is this about?
   * @param h_payto account identifier
   * @param time_limit oldest transaction that could be relevant
   * @param kac function to call for each applicable amount, in reverse chronological order (or until @a kac aborts by returning anything except #GNUNET_OK).
   * @param kac_cls closure for @a kac
   * @return transaction status code, @a kac aborting with #GNUNET_NO is not an error
   */
  enum GNUNET_DB_QueryStatus
    (*iterate_reserve_close_info)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    struct GNUNET_TIME_Absolute time_limit,
    TALER_EXCHANGEDB_KycAmountCallback kac,
    void *kac_cls);


  /**
   * Insert reserve close operation into database.
   *
   * @param cls closure
   * @param reserve_pub which reserve is this about?
   * @param execution_date when did we perform the transfer?
   * @param receiver_account to which account do we transfer, in payto://-format
   * @param wtid identifier for the wire transfer
   * @param amount_with_fee amount we charged to the reserve
   * @param closing_fee how high is the closing fee
   * @param close_request_row identifies explicit close request, 0 for none
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_reserve_closed)(void *cls,
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             struct GNUNET_TIME_Timestamp execution_date,
                             const char *receiver_account,
                             const struct
                             TALER_WireTransferIdentifierRawP *wtid,
                             const struct TALER_Amount *amount_with_fee,
                             const struct TALER_Amount *closing_fee,
                             uint64_t close_request_row);


  /**
   * Function called to insert wire transfer commit data into the DB.
   *
   * @param cls closure
   * @param type type of the wire transfer (i.e. "iban")
   * @param buf buffer with wire transfer preparation data
   * @param buf_size number of bytes in @a buf
   * @return query status code
   */
  enum GNUNET_DB_QueryStatus
    (*wire_prepare_data_insert)(void *cls,
                                const char *type,
                                const char *buf,
                                size_t buf_size);


  /**
   * Function called to mark wire transfer commit data as finished.
   *
   * @param cls closure
   * @param rowid which entry to mark as finished
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*wire_prepare_data_mark_finished)(void *cls,
                                       uint64_t rowid);


  /**
   * Function called to mark wire transfer as failed.
   *
   * @param cls closure
   * @param rowid which entry to mark as failed
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*wire_prepare_data_mark_failed)(void *cls,
                                     uint64_t rowid);


  /**
   * Function called to get an unfinished wire transfer
   * preparation data.
   *
   * @param cls closure
   * @param start_row offset to query table at
   * @param limit maximum number of results to return
   * @param cb function to call for unfinished work
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*wire_prepare_data_get)(void *cls,
                             uint64_t start_row,
                             uint64_t limit,
                             TALER_EXCHANGEDB_WirePreparationIterator cb,
                             void *cb_cls);


  /**
   * Starts a READ COMMITTED transaction where we transiently violate the foreign
   * constraints on the "wire_out" table as we insert aggregations
   * and only add the wire transfer out at the end.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK on success
   */
  enum GNUNET_GenericReturnValue
    (*start_deferred_wire_out)(void *cls);


  /**
   * Store information about an outgoing wire transfer that was executed.
   *
   * @param cls closure
   * @param date time of the wire transfer
   * @param h_payto identifies the receiver account of the wire transfer
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
    struct GNUNET_TIME_Timestamp date,
    const struct TALER_WireTransferIdentifierRawP *wtid,
    const struct TALER_PaytoHashP *h_payto,
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
  enum GNUNET_GenericReturnValue
    (*gc)(void *cls);


  /**
   * Select deposits above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_coin_deposits_above_serial_id)(void *cls,
                                            uint64_t serial_id,
                                            TALER_EXCHANGEDB_DepositCallback cb,
                                            void *cb_cls);


  /**
   * Function called to return meta data about a purses
   * above a certain serial ID.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param serial_id number to select requests by
   * @param cb function to call on each request
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_purse_requests_above_serial_id)(
    void *cls,
    uint64_t serial_id,
    TALER_EXCHANGEDB_PurseRequestCallback cb,
    void *cb_cls);


  /**
   * Select purse deposits above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_purse_deposits_above_serial_id)(
    void *cls,
    uint64_t serial_id,
    TALER_EXCHANGEDB_PurseDepositCallback cb,
    void *cb_cls);


  /**
   * Select account merges above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_account_merges_above_serial_id)(
    void *cls,
    uint64_t serial_id,
    TALER_EXCHANGEDB_AccountMergeCallback cb,
    void *cb_cls);


  /**
   * Select purse merges deposits above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_purse_merges_above_serial_id)(
    void *cls,
    uint64_t serial_id,
    TALER_EXCHANGEDB_PurseMergeCallback cb,
    void *cb_cls);


  /**
   * Select purse refunds above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param refunded which refund status to select for
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_purse_decisions_above_serial_id)(
    void *cls,
    uint64_t serial_id,
    bool refunded,
    TALER_EXCHANGEDB_PurseDecisionCallback cb,
    void *cb_cls);


  /**
   * Select all purse refunds above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_all_purse_decisions_above_serial_id)(
    void *cls,
    uint64_t serial_id,
    TALER_EXCHANGEDB_AllPurseDecisionCallback cb,
    void *cb_cls);


  /**
   * Select coins deposited into a purse.
   *
   * @param cls closure
   * @param purse_pub public key of the purse
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_purse_deposits_by_purse)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    TALER_EXCHANGEDB_PurseRefundCoinCallback cb,
    void *cb_cls);


  /**
   * Select refresh sessions above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_refreshes_above_serial_id)(void *cls,
                                        uint64_t serial_id,
                                        TALER_EXCHANGEDB_RefreshesCallback cb,
                                        void *cb_cls);


  /**
   * Select refunds above @a serial_id in monotonically increasing
   * order.
   *
   * @param cls closure
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_refunds_above_serial_id)(void *cls,
                                      uint64_t serial_id,
                                      TALER_EXCHANGEDB_RefundCallback cb,
                                      void *cb_cls);


  /**
   * Select inbound wire transfers into reserves_in above @a serial_id
   * in monotonically increasing order.
   *
   * @param cls closure
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_reserves_in_above_serial_id)(void *cls,
                                          uint64_t serial_id,
                                          TALER_EXCHANGEDB_ReserveInCallback cb,
                                          void *cb_cls);


  /**
   * Select inbound wire transfers into reserves_in above @a serial_id
   * in monotonically increasing order by @a account_name.
   *
   * @param cls closure
   * @param account_name name of the account for which we do the selection
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_reserves_in_above_serial_id_by_account)(
    void *cls,
    const char *account_name,
    uint64_t serial_id,
    TALER_EXCHANGEDB_ReserveInCallback cb,
    void *cb_cls);


  /**
   * Select withdraw operations from reserves_out above @a serial_id
   * in monotonically increasing order.
   *
   * @param cls closure
   * @param account_name name of the account for which we do the selection
   * @param serial_id highest serial ID to exclude (select strictly larger)
   * @param cb function to call on each result
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_withdrawals_above_serial_id)(
    void *cls,
    uint64_t serial_id,
    TALER_EXCHANGEDB_WithdrawCallback cb,
    void *cb_cls);


  /**
   * Function called to select outgoing wire transfers the exchange
   * executed, ordered by serial ID (monotonically increasing).
   *
   * @param cls closure
   * @param serial_id lowest serial ID to include (select larger or equal)
   * @param cb function to call for ONE unfinished item
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_wire_out_above_serial_id)(void *cls,
                                       uint64_t serial_id,
                                       TALER_EXCHANGEDB_WireTransferOutCallback
                                       cb,
                                       void *cb_cls);

  /**
   * Function called to select outgoing wire transfers the exchange
   * executed, ordered by serial ID (monotonically increasing).
   *
   * @param cls closure
   * @param account_name name to select by
   * @param serial_id lowest serial ID to include (select larger or equal)
   * @param cb function to call for ONE unfinished item
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_wire_out_above_serial_id_by_account)(
    void *cls,
    const char *account_name,
    uint64_t serial_id,
    TALER_EXCHANGEDB_WireTransferOutCallback cb,
    void *cb_cls);


  /**
   * Function called to select recoup requests the exchange
   * received, ordered by serial ID (monotonically increasing).
   *
   * @param cls closure
   * @param serial_id lowest serial ID to include (select larger or equal)
   * @param cb function to call for ONE unfinished item
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_recoup_above_serial_id)(void *cls,
                                     uint64_t serial_id,
                                     TALER_EXCHANGEDB_RecoupCallback cb,
                                     void *cb_cls);


  /**
   * Function called to select recoup requests the exchange received for
   * refreshed coins, ordered by serial ID (monotonically increasing).
   *
   * @param cls closure
   * @param serial_id lowest serial ID to include (select larger or equal)
   * @param cb function to call for ONE unfinished item
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_recoup_refresh_above_serial_id)(
    void *cls,
    uint64_t serial_id,
    TALER_EXCHANGEDB_RecoupRefreshCallback cb,
    void *cb_cls);


  /**
   * Function called to select reserve open operations, ordered by serial ID
   * (monotonically increasing).
   *
   * @param cls closure
   * @param serial_id lowest serial ID to include (select larger or equal)
   * @param cb function to call
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_reserve_open_above_serial_id)(
    void *cls,
    uint64_t serial_id,
    TALER_EXCHANGEDB_ReserveOpenCallback cb,
    void *cb_cls);


  /**
 * Function called to select reserve close operations the aggregator
 * triggered, ordered by serial ID (monotonically increasing).
 *
 * @param cls closure
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
  enum GNUNET_DB_QueryStatus
    (*select_reserve_closed_above_serial_id)(
    void *cls,
    uint64_t serial_id,
    TALER_EXCHANGEDB_ReserveClosedCallback cb,
    void *cb_cls);


  /**
   * Obtain information about which reserve a coin was generated
   * from given the hash of the blinded coin.
   *
   * @param cls closure
   * @param bch hash identifying the withdraw operation
   * @param[out] reserve_pub set to information about the reserve (on success only)
   * @param[out] reserve_out_serial_id set to row of the @a h_blind_ev in reserves_out
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_reserve_by_h_blind)(
    void *cls,
    const struct TALER_BlindedCoinHashP *bch,
    struct TALER_ReservePublicKeyP *reserve_pub,
    uint64_t *reserve_out_serial_id);


  /**
   * Obtain information about which old coin a coin was refreshed
   * given the hash of the blinded (fresh) coin.
   *
   * @param cls closure
   * @param h_blind_ev hash of the blinded coin
   * @param[out] old_coin_pub set to information about the old coin (on success only)
   * @param[out] rrc_serial set to the row of the @a h_blind_ev in the refresh_revealed_coins table
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_old_coin_by_h_blind)(
    void *cls,
    const struct TALER_BlindedCoinHashP *h_blind_ev,
    struct TALER_CoinSpendPublicKeyP *old_coin_pub,
    uint64_t *rrc_serial);


  /**
   * Store information that a denomination key was revoked
   * in the database.
   *
   * @param cls closure
   * @param denom_pub_hash hash of the revoked denomination key
   * @param master_sig signature affirming the revocation
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_denomination_revocation)(
    void *cls,
    const struct TALER_DenominationHashP *denom_pub_hash,
    const struct TALER_MasterSignatureP *master_sig);


  /**
   * Obtain information about a denomination key's revocation from
   * the database.
   *
   * @param cls closure
   * @param denom_pub_hash hash of the revoked denomination key
   * @param[out] master_sig signature affirming the revocation
   * @param[out] rowid row where the information is stored
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_denomination_revocation)(
    void *cls,
    const struct TALER_DenominationHashP *denom_pub_hash,
    struct TALER_MasterSignatureP *master_sig,
    uint64_t *rowid);


  /**
   * Select all (batch) deposits in the database
   * above a given @a min_batch_deposit_serial_id.
   *
   * @param cls closure
   * @param min_batch_deposit_serial_id only return entries strictly above this row (and in order)
   * @param cb function to call on all such deposits
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_batch_deposits_missing_wire)(
    void *cls,
    uint64_t min_batch_deposit_serial_id,
    TALER_EXCHANGEDB_WireMissingCallback cb,
    void *cb_cls);


  /**
   * Select all aggregation tracking IDs in the database
   * above a given @a min_tracking_serial_id.
   *
   * @param cls closure
   * @param min_tracking_serial_id only return entries strictly above this row (and in order)
   * @param cb function to call on all such aggregations
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_aggregations_above_serial)(
    void *cls,
    uint64_t min_tracking_serial_id,
    TALER_EXCHANGEDB_AggregationCallback cb,
    void *cb_cls);


  /**
   * Return any applicable justification as to why
   * a wire transfer might have been held.  Used
   * by the auditor to determine if a wire transfer
   * is legitimately stalled.
   *
   * @param cls closure
   * @param wire_target_h_payto effected target account
   * @param[out] payto_uri target account URI, set to NULL if unknown
   * @param[out] kyc_pending set to string describing missing KYC data
   * @param[out] status set to AML status
   * @param[out] aml_limit set to AML limit, or invalid amount for none
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_justification_for_missing_wire)(
    void *cls,
    const struct TALER_PaytoHashP *wire_target_h_payto,
    char **payto_uri,
    char **kyc_pending,
    enum TALER_AmlDecisionState *status,
    struct TALER_Amount *aml_limit);


  /**
   * Check the last date an auditor was modified.
   *
   * @param cls closure
   * @param auditor_pub key to look up information for
   * @param[out] last_date last modification date to auditor status
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_auditor_timestamp)(
    void *cls,
    const struct TALER_AuditorPublicKeyP *auditor_pub,
    struct GNUNET_TIME_Timestamp *last_date);


  /**
   * Lookup current state of an auditor.
   *
   * @param cls closure
   * @param auditor_pub key to look up information for
   * @param[out] auditor_url set to the base URL of the auditor's REST API; memory to be
   *            released by the caller!
   * @param[out] enabled set if the auditor is currently in use
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_auditor_status)(
    void *cls,
    const struct TALER_AuditorPublicKeyP *auditor_pub,
    char **auditor_url,
    bool *enabled);


  /**
   * Insert information about an auditor that will audit this exchange.
   *
   * @param cls closure
   * @param auditor_pub key of the auditor
   * @param auditor_url base URL of the auditor's REST service
   * @param auditor_name name of the auditor (for humans)
   * @param start_date date when the auditor was added by the offline system
   *                      (only to be used for replay detection)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_auditor)(
    void *cls,
    const struct TALER_AuditorPublicKeyP *auditor_pub,
    const char *auditor_url,
    const char *auditor_name,
    struct GNUNET_TIME_Timestamp start_date);


  /**
   * Update information about an auditor that will audit this exchange.
   *
   * @param cls closure
   * @param auditor_pub key of the auditor (primary key for the existing record)
   * @param auditor_url base URL of the auditor's REST service, to be updated
   * @param auditor_name name of the auditor (for humans)
   * @param change_date date when the auditor status was last changed
   *                      (only to be used for replay detection)
   * @param enabled true to enable, false to disable
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*update_auditor)(
    void *cls,
    const struct TALER_AuditorPublicKeyP *auditor_pub,
    const char *auditor_url,
    const char *auditor_name,
    struct GNUNET_TIME_Timestamp change_date,
    bool enabled);


  /**
   * Check the last date an exchange wire account was modified.
   *
   * @param cls closure
   * @param payto_uri key to look up information for
   * @param[out] last_date last modification date to auditor status
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_wire_timestamp)(void *cls,
                             const char *payto_uri,
                             struct GNUNET_TIME_Timestamp *last_date);


  /**
   * Insert information about an wire account used by this exchange.
   *
   * @param cls closure
   * @param payto_uri wire account of the exchange
   * @param conversion_url URL of a conversion service, NULL if there is no conversion
   * @param debit_restrictions JSON array with debit restrictions on the account
   * @param credit_restrictions JSON array with credit restrictions on the account
   * @param start_date date when the account was added by the offline system
   *                      (only to be used for replay detection)
   * @param master_sig public signature affirming the existence of the account,
   *         must be of purpose #TALER_SIGNATURE_MASTER_WIRE_DETAILS
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_wire)(void *cls,
                   const char *payto_uri,
                   const char *conversion_url,
                   const json_t *debit_restrictions,
                   const json_t *credit_restrictions,
                   struct GNUNET_TIME_Timestamp start_date,
                   const struct TALER_MasterSignatureP *master_sig);


  /**
   * Update information about a wire account of the exchange.
   *
   * @param cls closure
   * @param payto_uri account the update is about
   * @param conversion_url URL of a conversion service, NULL if there is no conversion
   * @param debit_restrictions JSON array with debit restrictions on the account; NULL allowed if not @a enabled
   * @param credit_restrictions JSON array with credit restrictions on the account; NULL allowed if not @a enabled
   * @param change_date date when the account status was last changed
   *                      (only to be used for replay detection)
   * @param enabled true to enable, false to disable (the actual change)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*update_wire)(void *cls,
                   const char *payto_uri,
                   const char *conversion_url,
                   const json_t *debit_restrictions,
                   const json_t *credit_restrictions,
                   struct GNUNET_TIME_Timestamp change_date,
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
   * Obtain information about the global fee structure of the exchange.
   *
   * @param cls closure
   * @param cb function to call on each fee entry
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_global_fees)(void *cls,
                       TALER_EXCHANGEDB_GlobalFeeCallback cb,
                       void *cb_cls);


  /**
   * Store information about a revoked online signing key.
   *
   * @param cls closure
   * @param exchange_pub exchange online signing key that was revoked
   * @param master_sig signature affirming the revocation
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_signkey_revocation)(
    void *cls,
    const struct TALER_ExchangePublicKeyP *exchange_pub,
    const struct TALER_MasterSignatureP *master_sig);


  /**
   * Obtain information about a revoked online signing key.
   *
   * @param cls closure
   * @param exchange_pub exchange online signing key that was revoked
   * @param[out] master_sig signature affirming the revocation
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_signkey_revocation)(
    void *cls,
    const struct TALER_ExchangePublicKeyP *exchange_pub,
    struct TALER_MasterSignatureP *master_sig);


  /**
   * Lookup information about current denomination key.
   *
   * @param cls closure
   * @param h_denom_pub hash of the denomination public key
   * @param[out] meta set to various meta data about the key
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_denomination_key)(
    void *cls,
    const struct TALER_DenominationHashP *h_denom_pub,
    struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta);


  /**
   * Add denomination key.
   *
   * @param cls closure
   * @param h_denom_pub hash of the denomination public key
   * @param denom_pub the denomination public key
   * @param meta meta data about the denomination
   * @param master_sig master signature to add
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*add_denomination_key)(
    void *cls,
    const struct TALER_DenominationHashP *h_denom_pub,
    const struct TALER_DenominationPublicKey *denom_pub,
    const struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta,
    const struct TALER_MasterSignatureP *master_sig);


  /**
   * Activate future signing key, turning it into a "current" or "valid"
   * denomination key by adding the master signature.
   *
   * @param cls closure
   * @param exchange_pub the exchange online signing public key
   * @param meta meta data about @a exchange_pub
   * @param master_sig master signature to add
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*activate_signing_key)(
    void *cls,
    const struct TALER_ExchangePublicKeyP *exchange_pub,
    const struct TALER_EXCHANGEDB_SignkeyMetaData *meta,
    const struct TALER_MasterSignatureP *master_sig);


  /**
   * Lookup signing key meta data.
   *
   * @param cls closure
   * @param exchange_pub the exchange online signing public key
   * @param[out] meta meta data about @a exchange_pub
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_signing_key)(
    void *cls,
    const struct TALER_ExchangePublicKeyP *exchange_pub,
    struct TALER_EXCHANGEDB_SignkeyMetaData *meta);


  /**
   * Insert information about an auditor auditing a denomination key.
   *
   * @param cls closure
   * @param h_denom_pub the audited denomination
   * @param auditor_pub the auditor's key
   * @param auditor_sig signature affirming the auditor's audit activity
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_auditor_denom_sig)(
    void *cls,
    const struct TALER_DenominationHashP *h_denom_pub,
    const struct TALER_AuditorPublicKeyP *auditor_pub,
    const struct TALER_AuditorSignatureP *auditor_sig);


  /**
   * Obtain information about an auditor auditing a denomination key.
   *
   * @param cls closure
   * @param h_denom_pub the audited denomination
   * @param auditor_pub the auditor's key
   * @param[out] auditor_sig set to signature affirming the auditor's audit activity
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_auditor_denom_sig)(
    void *cls,
    const struct TALER_DenominationHashP *h_denom_pub,
    const struct TALER_AuditorPublicKeyP *auditor_pub,
    struct TALER_AuditorSignatureP *auditor_sig);


  /**
   * Lookup information about known wire fees.
   *
   * @param cls closure
   * @param wire_method the wire method to lookup fees for
   * @param start_time starting time of fee
   * @param end_time end time of fee
   * @param[out] fees set to wire fees for that time period; if
   *             different wire fee exists within this time
   *             period, an 'invalid' amount is returned.
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_wire_fee_by_time)(
    void *cls,
    const char *wire_method,
    struct GNUNET_TIME_Timestamp start_time,
    struct GNUNET_TIME_Timestamp end_time,
    struct TALER_WireFeeSet *fees);


  /**
   * Lookup information about known global fees.
   *
   * @param cls closure
   * @param start_time starting time of fee
   * @param end_time end time of fee
   * @param[out] fees set to wire fees for that time period; if
   *             different global fee exists within this time
   *             period, an 'invalid' amount is returned.
   * @param[out] purse_timeout set to when unmerged purses expire
   * @param[out] history_expiration set to when we expire reserve histories
   * @param[out] purse_account_limit set to number of free purses
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_global_fee_by_time)(
    void *cls,
    struct GNUNET_TIME_Timestamp start_time,
    struct GNUNET_TIME_Timestamp end_time,
    struct TALER_GlobalFeeSet *fees,
    struct GNUNET_TIME_Relative *purse_timeout,
    struct GNUNET_TIME_Relative *history_expiration,
    uint32_t *purse_account_limit);


  /**
   * Lookup the latest serial number of @a table.  Used in
   * exchange-auditor database replication.
   *
   * @param cls closure
   * @param table table for which we should return the serial
   * @param[out] latest serial number in use
   * @return transaction status code, #GNUNET_DB_STATUS_HARD_ERROR if
   *         @a table does not have a serial number
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_serial_by_table)(void *cls,
                              enum TALER_EXCHANGEDB_ReplicatedTable table,
                              uint64_t *serial);

  /**
   * Lookup records above @a serial number in @a table. Used in
   * exchange-auditor database replication.
   *
   * @param cls closure
   * @param table table for which we should return the serial
   * @param serial largest serial number to exclude
   * @param cb function to call on the records
   * @param cb_cls closure for @a cb
   * @return transaction status code, GNUNET_DB_STATUS_HARD_ERROR if
   *         @a table does not have a serial number
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_records_by_table)(void *cls,
                               enum TALER_EXCHANGEDB_ReplicatedTable table,
                               uint64_t serial,
                               TALER_EXCHANGEDB_ReplicationCallback cb,
                               void *cb_cls);


  /**
   * Insert record set into @a table.  Used in exchange-auditor database
   * replication.
   *
  memset (&awc, 0, sizeof (awc));
   * @param cls closure
   * @param tb table data to insert
   * @return transaction status code, #GNUNET_DB_STATUS_HARD_ERROR if
   *         @a table does not have a serial number
   */
  enum GNUNET_DB_QueryStatus
    (*insert_records_by_table)(void *cls,
                               const struct TALER_EXCHANGEDB_TableData *td);


  /**
   * Function called to grab a work shard on an operation @a op. Runs in its
   * own transaction.
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
   * Function called to abort work on a shard.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param job_name name of the operation to abort a word shard for
   * @param start_row inclusive start row of the shard
   * @param end_row exclusive end row of the shard
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*abort_shard)(void *cls,
                   const char *job_name,
                   uint64_t start_row,
                   uint64_t end_row);

  /**
   * Function called to persist that work on a shard was completed.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param job_name name of the operation to grab a word shard for
   * @param start_row inclusive start row of the shard
   * @param end_row exclusive end row of the shard
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*complete_shard)(void *cls,
                      const char *job_name,
                      uint64_t start_row,
                      uint64_t end_row);


  /**
   * Function called to grab a revolving work shard on an operation @a op. Runs
   * in its own transaction. Returns the oldest inactive shard.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param job_name name of the operation to grab a revolving shard for
   * @param shard_size desired shard size
   * @param shard_limit exclusive end of the shard range
   * @param[out] start_row inclusive start row of the shard (returned)
   * @param[out] end_row inclusive end row of the shard (returned)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*begin_revolving_shard)(void *cls,
                             const char *job_name,
                             uint32_t shard_size,
                             uint32_t shard_limit,
                             uint32_t *start_row,
                             uint32_t *end_row);


  /**
   * Function called to release a revolving shard back into the work pool.
   * Clears the "completed" flag.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param job_name name of the operation to grab a word shard for
   * @param start_row inclusive start row of the shard
   * @param end_row inclusive end row of the shard
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*release_revolving_shard)(void *cls,
                               const char *job_name,
                               uint32_t start_row,
                               uint32_t end_row);


  /**
   * Function called to delete all revolving shards.
   * To be used after a crash or when the shard size is
   * changed.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK on success
   *         #GNUNET_SYSERR on failure
   */
  enum GNUNET_GenericReturnValue
    (*delete_shard_locks)(void *cls);


  /**
   * Function called to save the manifest of an extension
   * (age-restriction, policy-extension, ...)
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param extension_name the name of the extension
   * @param manifest JSON object of the Manifest as string, maybe NULL (== disabled extension)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*set_extension_manifest)(void *cls,
                              const char *extension_name,
                              const char *manifest);


  /**
   * Function called to retrieve the manifest of an extension
   * (age-restriction, policy-extension, ...)
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param extension_name the name of the extension
   * @param[out] manifest Manifest of the extension in JSON encoding, maybe NULL (== disabled extension)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_extension_manifest)(void *cls,
                              const char *extension_name,
                              char **manifest);


  /**
   * Function called to store configuration data about a partner
   * exchange that we are federated with.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub public offline signing key of the partner exchange
   * @param start_date when does the following data start to be valid
   * @param end_date when does the validity end (exclusive)
   * @param wad_frequency how often do we do exchange-to-exchange settlements?
   * @param wad_fee how much do we charge for transfers to the partner
   * @param partner_base_url base URL of the partner exchange
   * @param master_sig signature with our offline signing key affirming the above
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_partner)(void *cls,
                      const struct TALER_MasterPublicKeyP *master_pub,
                      struct GNUNET_TIME_Timestamp start_date,
                      struct GNUNET_TIME_Timestamp end_date,
                      struct GNUNET_TIME_Relative wad_frequency,
                      const struct TALER_Amount *wad_fee,
                      const char *partner_base_url,
                      const struct TALER_MasterSignatureP *master_sig);


  /**
   * Function called to persist an encrypted contract associated with a reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param econtract the encrypted contract
   * @param[out] econtract_sig set to the signature over the encrypted contract
   * @param[out] in_conflict set to true if @a econtract
   *             conflicts with an existing contract;
   *             in this case, the return value will be
   *             #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT despite the failure
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_contract)(void *cls,
                       const struct TALER_PurseContractPublicKeyP *purse_pub,
                       const struct TALER_EncryptedContract *econtract,
                       bool *in_conflict);


  /**
   * Function called to retrieve an encrypted contract.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param pub_ckey set to the ephemeral DH used to encrypt the contract, key used to lookup the contract by
   * @param[out] purse_pub public key of the purse of the contract
   * @param[out] econtract_sig set to the signature over the encrypted contract
   * @param[out] econtract_size set to the number of bytes in @a econtract
   * @param[out] econtract set to the encrypted contract on success, to be freed by the caller
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_contract)(
    void *cls,
    const struct TALER_ContractDiffiePublicP *pub_ckey,
    struct TALER_PurseContractPublicKeyP *purse_pub,
    struct TALER_PurseContractSignatureP *econtract_sig,
    size_t *econtract_size,
    void **econtract);


  /**
   * Function called to retrieve an encrypted contract.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub key to lookup the contract by
   * @param[out] econtract set to the encrypted contract on success, to be freed by the caller
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_contract_by_purse)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    struct TALER_EncryptedContract *econtract);


  /**
   * Function called to create a new purse with certain meta data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub public key of the new purse
   * @param merge_pub public key providing the merge capability
   * @param purse_expiration time when the purse will expire
   * @param h_contract_terms hash of the contract for the purse
   * @param age_limit age limit to enforce for payments into the purse
   * @param flags flags for the operation
   * @param purse_fee fee we are allowed to charge to the reserve (depending on @a flags)
   * @param amount target amount (with fees) to be put into the purse
   * @param purse_sig signature with @a purse_pub's private key affirming the above
   * @param[out] in_conflict set to true if the meta data
   *             conflicts with an existing purse;
   *             in this case, the return value will be
   *             #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT despite the failure
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_purse_request)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_PurseMergePublicKeyP *merge_pub,
    struct GNUNET_TIME_Timestamp purse_expiration,
    const struct TALER_PrivateContractHashP *h_contract_terms,
    uint32_t age_limit,
    enum TALER_WalletAccountMergeFlags flags,
    const struct TALER_Amount *purse_fee,
    const struct TALER_Amount *amount,
    const struct TALER_PurseContractSignatureP *purse_sig,
    bool *in_conflict);


  /**
   * Function called to clean up one expired purse.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param start_time select purse expired after this time
   * @param end_time select purse expired before this time
   * @return transaction status code (#GNUNET_DB_STATUS_SUCCESS_NO_RESULTS if no purse expired in the given time interval).
   */
  enum GNUNET_DB_QueryStatus
    (*expire_purse)(
    void *cls,
    struct GNUNET_TIME_Absolute start_time,
    struct GNUNET_TIME_Absolute end_time);


  /**
   * Function called to obtain information about a purse.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub public key of the new purse
   * @param[out] purse_creation set to time when the purse was created
   * @param[out] purse_expiration set to time when the purse will expire
   * @param[out] amount set to target amount (with fees) to be put into the purse
   * @param[out] deposited set to actual amount put into the purse so far
   * @param[out] h_contract_terms set to hash of the contract for the purse
   * @param[out] merge_timestamp set to time when the purse was merged, or NEVER if not
   * @param[out] purse_deleted set to true if purse was deleted
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_purse)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    struct GNUNET_TIME_Timestamp *purse_creation,
    struct GNUNET_TIME_Timestamp *purse_expiration,
    struct TALER_Amount *amount,
    struct TALER_Amount *deposited,
    struct TALER_PrivateContractHashP *h_contract_terms,
    struct GNUNET_TIME_Timestamp *merge_timestamp,
    bool *purse_deleted);


  /**
   * Function called to return meta data about a purse by the
   * purse public key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub public key of the purse
   * @param[out] merge_pub public key representing the merge capability
   * @param[out] purse_expiration when would an unmerged purse expire
   * @param[out] h_contract_terms contract associated with the purse
   * @param[out] age_limit the age limit for deposits into the purse
   * @param[out] target_amount amount to be put into the purse
   * @param[out] balance amount put so far into the purse
   * @param[out] purse_sig signature of the purse over the initialization data
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_purse_request)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    struct TALER_PurseMergePublicKeyP *merge_pub,
    struct GNUNET_TIME_Timestamp *purse_expiration,
    struct TALER_PrivateContractHashP *h_contract_terms,
    uint32_t *age_limit,
    struct TALER_Amount *target_amount,
    struct TALER_Amount *balance,
    struct TALER_PurseContractSignatureP *purse_sig);


  /**
   * Function called to return meta data about a purse by the
   * merge capability key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param merge_pub public key representing the merge capability
   * @param[out] purse_pub public key of the purse
   * @param[out] purse_expiration when would an unmerged purse expire
   * @param[out] h_contract_terms contract associated with the purse
   * @param[out] age_limit the age limit for deposits into the purse
   * @param[out] target_amount amount to be put into the purse
   * @param[out] balance amount put so far into the purse
   * @param[out] purse_sig signature of the purse over the initialization data
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_purse_by_merge_pub)(
    void *cls,
    const struct TALER_PurseMergePublicKeyP *merge_pub,
    struct TALER_PurseContractPublicKeyP *purse_pub,
    struct GNUNET_TIME_Timestamp *purse_expiration,
    struct TALER_PrivateContractHashP *h_contract_terms,
    uint32_t *age_limit,
    struct TALER_Amount *target_amount,
    struct TALER_Amount *balance,
    struct TALER_PurseContractSignatureP *purse_sig);


  /**
   * Function called to execute a transaction crediting
   * a purse with @a amount from @a coin_pub. Reduces the
   * value of @a coin_pub and increase the balance of
   * the @a purse_pub purse. If the balance reaches the
   * target amount and the purse has been merged, triggers
   * the updates of the reserve/account balance.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub purse to credit
   * @param coin_pub coin to deposit (debit)
   * @param amount fraction of the coin's value to deposit
   * @param coin_sig signature affirming the operation
   * @param amount_minus_fee amount to add to the purse
   * @param[out] balance_ok set to false if the coin's
   *        remaining balance is below @a amount;
   *             in this case, the return value will be
   *             #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT despite the failure
   * @param[out] too_late it is too late to deposit into this purse
   * @param[out] conflict the same coin was deposited into
   *        this purse with a different amount already
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*do_purse_deposit)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_CoinSpendPublicKeyP *coin_pub,
    const struct TALER_Amount *amount,
    const struct TALER_CoinSpendSignatureP *coin_sig,
    const struct TALER_Amount *amount_minus_fee,
    bool *balance_ok,
    bool *too_late,
    bool *conflict);


  /**
   * Function called to explicitly delete a purse.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub purse to delete
   * @param purse_sig signature affirming the deletion
   * @param[out] decided set to true if the purse was
   *        already decided and thus could not be deleted
   * @param[out] found set to true if the purse was found
   *        (if false, purse could not be deleted)
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*do_purse_delete)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_PurseContractSignatureP *purse_sig,
    bool *decided,
    bool *found);


  /**
   * Set the current @a balance in the purse
   * identified by @a purse_pub. Used by the auditor
   * to update the balance as calculated by the auditor.
   *
   * @param cls closure
   * @param purse_pub public key of a purse
   * @param balance new balance to store under the purse
   * @return transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*set_purse_balance)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_Amount *balance);


  /**
   * Function called to obtain a coin deposit data from
   * depositing the coin into a purse.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub purse to credit
   * @param coin_pub coin to deposit (debit)
   * @param[out] amount set fraction of the coin's value that was deposited (with fee)
   * @param[out] h_denom_pub set to hash of denomination of the coin
   * @param[out] phac set to hash of age restriction on the coin
   * @param[out] coin_sig set to signature affirming the operation
   * @param[out] partner_url set to the URL of the partner exchange, or NULL for ourselves, must be freed by caller
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_purse_deposit)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_CoinSpendPublicKeyP *coin_pub,
    struct TALER_Amount *amount,
    struct TALER_DenominationHashP *h_denom_pub,
    struct TALER_AgeCommitmentHash *phac,
    struct TALER_CoinSpendSignatureP *coin_sig,
    char **partner_url);


  /**
   * Function called to approve merging a purse into a
   * reserve by the respective purse merge key. The purse
   * must not have been merged into a different reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub purse to merge
   * @param merge_sig signature affirming the merge
   * @param merge_timestamp time of the merge
   * @param reserve_sig signature of the reserve affirming the merge
   * @param partner_url URL of the partner exchange, can be NULL if the reserves lives with us
   * @param reserve_pub public key of the reserve to credit
   * @param[out] no_partner set to true if @a partner_url is unknown
   * @param[out] no_balance set to true if the @a purse_pub is not paid up yet
   * @param[out] no_reserve set to true if the @a reserve_pub is not known
   * @param[out] in_conflict set to true if @a purse_pub was merged into a different reserve already
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*do_purse_merge)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_PurseMergeSignatureP *merge_sig,
    const struct GNUNET_TIME_Timestamp merge_timestamp,
    const struct TALER_ReserveSignatureP *reserve_sig,
    const char *partner_url,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    bool *no_partner,
    bool *no_balance,
    bool *in_conflict);


  /**
   * Function called insert request to merge a purse into a reserve by the
   * respective purse merge key. The purse must not have been merged into a
   * different reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub purse to merge
   * @param merge_sig signature affirming the merge
   * @param merge_timestamp time of the merge
   * @param reserve_sig signature of the reserve affirming the merge
   * @param purse_fee amount to charge the reserve for the purse creation, NULL to use the quota
   * @param reserve_pub public key of the reserve to credit
   * @param[out] in_conflict set to true if @a purse_pub was merged into a different reserve already
   * @param[out] no_reserve set to true if @a reserve_pub is not a known reserve
   * @param[out] insufficient_funds set to true if @a reserve_pub has insufficient capacity to create another purse
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*do_reserve_purse)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_PurseMergeSignatureP *merge_sig,
    const struct GNUNET_TIME_Timestamp merge_timestamp,
    const struct TALER_ReserveSignatureP *reserve_sig,
    const struct TALER_Amount *purse_fee,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    bool *in_conflict,
    bool *no_reserve,
    bool *insufficient_funds);


  /**
   * Function called to approve merging of a purse with
   * an account, made by the receiving account.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub public key of the purse
   * @param[out] merge_sig set to the signature confirming the merge
   * @param[out] merge_timestamp set to the time of the merge
   * @param[out] partner_url set to the URL of the target exchange, or NULL if the target exchange is us. To be freed by the caller.
   * @param[out] reserve_pub set to the public key of the reserve/account being credited
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_purse_merge)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    struct TALER_PurseMergeSignatureP *merge_sig,
    struct GNUNET_TIME_Timestamp *merge_timestamp,
    char **partner_url,
    struct TALER_ReservePublicKeyP *reserve_pub);


  /**
   * Function called to initiate closure of an account.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param reserve_pub public key of the account to close
   * @param payto_uri where to wire the funds
   * @param reserve_sig signature affiming that the account is to be closed
   * @param request_timestamp timestamp of the close request
   * @param balance balance at the time of closing
   * @param closing_fee closing fee to charge
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_close_request)(void *cls,
                            const struct TALER_ReservePublicKeyP *reserve_pub,
                            const char *payto_uri,
                            const struct TALER_ReserveSignatureP *reserve_sig,
                            struct GNUNET_TIME_Timestamp request_timestamp,
                            const struct TALER_Amount *balance,
                            const struct TALER_Amount *closing_fee);


  /**
   * Function called to persist a request to drain profits.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param wtid wire transfer ID to use
   * @param account_section account to drain
   * @param payto_uri account to wire funds to
   * @param request_timestamp time of the signature
   * @param amount amount to wire
   * @param master_sig signature affirming the operation
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*insert_drain_profit)(void *cls,
                           const struct TALER_WireTransferIdentifierRawP *wtid,
                           const char *account_section,
                           const char *payto_uri,
                           struct GNUNET_TIME_Timestamp request_timestamp,
                           const struct TALER_Amount *amount,
                           const struct TALER_MasterSignatureP *master_sig);


  /**
   * Function called to get information about a profit drain event.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param wtid wire transfer ID to look up drain event for
   * @param[out] serial set to serial ID of the entry
   * @param[out] account_section set to account to drain
   * @param[out] payto_uri set to account to wire funds to
   * @param[out] request_timestamp set to time of the signature
   * @param[out] amount set to amount to wire
   * @param[out] master_sig set to signature affirming the operation
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*get_drain_profit)(void *cls,
                        const struct TALER_WireTransferIdentifierRawP *wtid,
                        uint64_t *serial,
                        char **account_section,
                        char **payto_uri,
                        struct GNUNET_TIME_Timestamp *request_timestamp,
                        struct TALER_Amount *amount,
                        struct TALER_MasterSignatureP *master_sig);


  /**
   * Get profit drain operation ready to execute.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param[out] serial set to serial ID of the entry
   * @param[out] wtid set set to wire transfer ID to use
   * @param[out] account_section set to  account to drain
   * @param[out] payto_uri set to account to wire funds to
   * @param[out] request_timestamp set to time of the signature
   * @param[out] amount set to amount to wire
   * @param[out] master_sig set to signature affirming the operation
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*profit_drains_get_pending)(
    void *cls,
    uint64_t *serial,
    struct TALER_WireTransferIdentifierRawP *wtid,
    char **account_section,
    char **payto_uri,
    struct GNUNET_TIME_Timestamp *request_timestamp,
    struct TALER_Amount *amount,
    struct TALER_MasterSignatureP *master_sig);


  /**
   * Set profit drain operation to finished.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param serial serial ID of the entry to mark finished
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*profit_drains_set_finished)(
    void *cls,
    uint64_t serial);


  /**
   * Insert KYC requirement for @a h_payto account into table.
   *
   * @param cls closure
   * @param requirements requirements that must be checked
   * @param h_payto account that must be KYC'ed
   * @param reserve_pub if account is a reserve, its public key, NULL otherwise
   * @param[out] requirement_row set to legitimization requirement row for this check
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*insert_kyc_requirement_for_account)(
    void *cls,
    const char *requirements,
    const struct TALER_PaytoHashP *h_payto,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    uint64_t *requirement_row);


  /**
   * Begin KYC requirement process.
   *
   * @param cls closure
   * @param h_payto account that must be KYC'ed
   * @param provider_section provider that must be checked
   * @param provider_account_id provider account ID
   * @param provider_legitimization_id provider legitimization ID
   * @param[out] process_row row the process is stored under
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*insert_kyc_requirement_process)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    const char *provider_section,
    const char *provider_account_id,
    const char *provider_legitimization_id,
    uint64_t *process_row);


  /**
   * Fetch information about pending KYC requirement process.
   *
   * @param cls closure
   * @param h_payto account that must be KYC'ed
   * @param provider_section provider that must be checked
   * @param[out] redirect_url set to redirect URL for the process
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*get_pending_kyc_requirement_process)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    const char *provider_section,
    char **redirect_url);


  /**
   * Update KYC process with updated provider-linkage and/or
   * expiration data.
   *
   * @param cls closure
   * @param process_row row to select by
   * @param provider_section provider that must be checked (technically redundant)
   * @param h_payto account that must be KYC'ed (helps access by shard, otherwise also redundant)
   * @param provider_account_id provider account ID
   * @param provider_legitimization_id provider legitimization ID
   * @param redirect_url where the user should be redirected to start the KYC process
   * @param expiration how long is this KYC check set to be valid (in the past if invalid)
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*update_kyc_process_by_row)(
    void *cls,
    uint64_t process_row,
    const char *provider_section,
    const struct TALER_PaytoHashP *h_payto,
    const char *provider_account_id,
    const char *provider_legitimization_id,
    const char *redirect_url,
    struct GNUNET_TIME_Absolute expiration);


  /**
   * Lookup KYC requirement.
   *
   * @param cls closure
   * @param legi_row identifies requirement to look up
   * @param[out] requirements space-separated list of requirements
   * @param[out] aml_status set to the AML status of the account
   * @param[out] h_payto account that must be KYC'ed
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_kyc_requirement_by_row)(
    void *cls,
    uint64_t requirement_row,
    char **requirements,
    enum TALER_AmlDecisionState *aml_status,
    struct TALER_PaytoHashP *h_payto);


  /**
   * Lookup KYC process meta data.
   *
   * @param cls closure
   * @param provider_section provider that must be checked
   * @param h_payto account that must be KYC'ed
   * @param[out] process_row set to row with the legitimization data
   * @param[out] expiration how long is this KYC check set to be valid (in the past if invalid)
   * @param[out] provider_account_id provider account ID
   * @param[out] provider_legitimization_id provider legitimization ID
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_kyc_process_by_account)(
    void *cls,
    const char *provider_section,
    const struct TALER_PaytoHashP *h_payto,
    uint64_t *process_row,
    struct GNUNET_TIME_Absolute *expiration,
    char **provider_account_id,
    char **provider_legitimization_id);


  /**
   * Lookup an
   * @a h_payto by @a provider_legitimization_id.
   *
   * @param cls closure
   * @param provider_section
   * @param provider_legitimization_id legi to look up
   * @param[out] h_payto where to write the result
   * @param[out] process_row identifies the legitimization process on our end
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*kyc_provider_account_lookup)(
    void *cls,
    const char *provider_section,
    const char *provider_legitimization_id,
    struct TALER_PaytoHashP *h_payto,
    uint64_t *process_row);


  /**
   * Call us on KYC processes satisfied for the given
   * account.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto account identifier
   * @param spc function to call for each satisfied KYC process
   * @param spc_cls closure for @a spc
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*select_satisfied_kyc_processes)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    TALER_EXCHANGEDB_SatisfiedProviderCallback spc,
    void *spc_cls);


  /**
   * Call us on KYC legitimization processes satisfied and not expired for the
   * given account.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto account identifier
   * @param lpc function to call for each satisfied KYC legitimization process
   * @param lpc_cls closure for @a lpc
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
    (*iterate_kyc_reference)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    TALER_EXCHANGEDB_LegitimizationProcessCallback lpc,
    void *lpc_cls);


  /**
   * Call @a kac on withdrawn amounts after @a time_limit which are relevant
   * for a KYC trigger for a the (debited) account identified by @a h_payto.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto account identifier
   * @param time_limit oldest transaction that could be relevant
   * @param kac function to call for each applicable amount, in reverse chronological order (or until @a kac aborts by returning anything except #GNUNET_OK).
   * @param kac_cls closure for @a kac
   * @return transaction status code, @a kac aborting with #GNUNET_NO is not an error
   */
  enum GNUNET_DB_QueryStatus
    (*select_withdraw_amounts_for_kyc_check)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    struct GNUNET_TIME_Absolute time_limit,
    TALER_EXCHANGEDB_KycAmountCallback kac,
    void *kac_cls);


  /**
   * Call @a kac on aggregated amounts after @a time_limit which are relevant for a
   * KYC trigger for a the (credited) account identified by @a h_payto.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto account identifier
   * @param time_limit oldest transaction that could be relevant
   * @param kac function to call for each applicable amount, in reverse chronological order (or until @a kac aborts by returning anything except #GNUNET_OK).
   * @param kac_cls closure for @a kac
   * @return transaction status code, @a kac aborting with #GNUNET_NO is not an error
   */
  enum GNUNET_DB_QueryStatus
    (*select_aggregation_amounts_for_kyc_check)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    struct GNUNET_TIME_Absolute time_limit,
    TALER_EXCHANGEDB_KycAmountCallback kac,
    void *kac_cls);


  /**
   * Call @a kac on merged reserve amounts after @a time_limit which are relevant for a
   * KYC trigger for a the wallet identified by @a h_payto.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param h_payto account identifier
   * @param time_limit oldest transaction that could be relevant
   * @param kac function to call for each applicable amount, in reverse chronological order (or until @a kac aborts by returning anything except #GNUNET_OK).
   * @param kac_cls closure for @a kac
   * @return transaction status code, @a kac aborting with #GNUNET_NO is not an error
   */
  enum GNUNET_DB_QueryStatus
    (*select_merge_amounts_for_kyc_check)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    struct GNUNET_TIME_Absolute time_limit,
    TALER_EXCHANGEDB_KycAmountCallback kac,
    void *kac_cls);


  /**
   * Store KYC attribute data, update KYC process status and
   * AML status for the given account.
   *
   * @param cls closure
   * @param process_row KYC process row to update
   * @param h_payto account for which the attribute data is stored
   * @param kyc_prox key for similarity search
   * @param provider_section provider that must be checked
   * @param num_checks how many checks do these attributes satisfy
   * @param satisfied_checks array of checks satisfied by these attributes
   * @param provider_account_id provider account ID
   * @param provider_legitimization_id provider legitimization ID
   * @param birthday birthdate of user, in days after 1990, or 0 if unknown or definitively adult
   * @param collection_time when was the data collected
   * @param expiration_time when does the data expire
   * @param enc_attributes_size number of bytes in @a enc_attributes
   * @param enc_attributes encrypted attribute data
   * @param require_aml true to trigger AML
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*insert_kyc_attributes)(
    void *cls,
    uint64_t process_row,
    const struct TALER_PaytoHashP *h_payto,
    const struct GNUNET_ShortHashCode *kyc_prox,
    const char *provider_section,
    unsigned int num_checks,
    const char *satisfied_checks[static num_checks],
    uint32_t birthday,
    struct GNUNET_TIME_Timestamp collection_time,
    const char *provider_account_id,
    const char *provider_legitimization_id,
    struct GNUNET_TIME_Absolute expiration_time,
    size_t enc_attributes_size,
    const void *enc_attributes,
    bool require_aml);


  /**
   * Lookup similar KYC attribute data.
   *
   * @param cls closure
   * @param kyc_prox key for similarity search
   * @param cb callback to invoke on each match
   * @param cb_cls closure for @a cb
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*select_similar_kyc_attributes)(
    void *cls,
    const struct GNUNET_ShortHashCode *kyc_prox,
    TALER_EXCHANGEDB_AttributeCallback cb,
    void *cb_cls);


  /**
   * Lookup KYC attribute data for a specific account.
   *
   * @param cls closure
   * @param h_payto account for which the attribute data is stored
   * @param cb callback to invoke on each match
   * @param cb_cls closure for @a cb
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*select_kyc_attributes)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    TALER_EXCHANGEDB_AttributeCallback cb,
    void *cb_cls);


  /**
   * Insert AML staff record.
   *
   * @param cls closure
   * @param decider_pub public key of the staff member
   * @param master_sig offline signature affirming the AML officer
   * @param decider_name full name of the staff member
   * @param is_active true to enable, false to set as inactive
   * @param read_only true to set read-only access
   * @param last_change when was the change made effective
   * @param[out] previous_change when was the previous change made
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*insert_aml_officer)(
    void *cls,
    const struct TALER_AmlOfficerPublicKeyP *decider_pub,
    const struct TALER_MasterSignatureP *master_sig,
    const char *decider_name,
    bool is_active,
    bool read_only,
    struct GNUNET_TIME_Timestamp last_change,
    struct GNUNET_TIME_Timestamp *previous_change);


  /**
   * Test if the given AML staff member is active
   * (at least read-only).
   *
   * @param cls closure
   * @param decider_pub public key of the staff member
   * @return database transaction status, if member is unknown or not active, 1 if member is active
   */
  enum GNUNET_DB_QueryStatus
    (*test_aml_officer)(
    void *cls,
    const struct TALER_AmlOfficerPublicKeyP *decider_pub);


  /**
   * Fetch AML staff record.
   *
   * @param cls closure
   * @param decider_pub public key of the staff member
   * @param[out] master_sig offline signature affirming the AML officer
   * @param[out] decider_name full name of the staff member
   * @param[out] is_active true to enable, false to set as inactive
   * @param[out] read_only true to set read-only access
   * @param[out] last_change when was the change made effective
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*lookup_aml_officer)(
    void *cls,
    const struct TALER_AmlOfficerPublicKeyP *decider_pub,
    struct TALER_MasterSignatureP *master_sig,
    char **decider_name,
    bool *is_active,
    bool *read_only,
    struct GNUNET_TIME_Absolute *last_change);


  /**
   * Obtain the current AML threshold set for an account.
   *
   * @param cls closure
   * @param h_payto account for which the AML threshold is stored
   * @param[out] decision set to current AML decision
   * @param[out] threshold set to the existing threshold
   * @return database transaction status, 0 if no threshold was set
   */
  enum GNUNET_DB_QueryStatus
    (*select_aml_threshold)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    enum TALER_AmlDecisionState *decision,
    struct TALER_EXCHANGEDB_KycStatus *kyc,
    struct TALER_Amount *threshold);


  /**
   * Trigger AML process, an account has crossed the threshold. Inserts or
   * updates the AML status.
   *
   * @param cls closure
   * @param h_payto account for which the attribute data is stored
   * @param threshold_crossed existing threshold that was crossed
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*trigger_aml_process)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    const struct TALER_Amount *threshold_crossed);


  /**
   * Lookup AML decisions that have a particular state.
   *
   * @param cls closure
   * @param decision which decision states to filter by
   * @param row_off offset to start from
   * @param forward true to go forward in time, false to go backwards
   * @param cb callback to invoke on each match
   * @param cb_cls closure for @a cb
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*select_aml_process)(
    void *cls,
    enum TALER_AmlDecisionState decision,
    uint64_t row_off,
    uint64_t limit,
    bool forward,
    TALER_EXCHANGEDB_AmlStatusCallback cb,
    void *cb_cls);


  /**
   * Lookup AML decision history for a particular account.
   *
   * @param cls closure
   * @param h_payto which account should we return the AML decision history for
   * @param cb callback to invoke on each match
   * @param cb_cls closure for @a cb
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*select_aml_history)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    TALER_EXCHANGEDB_AmlHistoryCallback cb,
    void *cb_cls);


  /**
   * Insert an AML decision. Inserts into AML history and insert or updates AML
   * status.
   *
   * @param cls closure
   * @param h_payto account for which the attribute data is stored
   * @param new_threshold new monthly threshold that would trigger an AML check
   * @param new_status AML decision status
   * @param decision_time when was the decision made
   * @param justification human-readable text justifying the decision
   * @param kyc_requirements specific KYC requirements being imposed
   * @param requirements_row row in the KYC table for this process, 0 for none
   * @param decider_pub public key of the staff member
   * @param decider_sig signature of the staff member
   * @param[out] invalid_officer set to TRUE if @a decider_pub is not allowed to make decisions right now
   * @param[out] last_date set to the previous decision time;
   *   the INSERT is not performed if @a last_date is not before @a decision_time
   * @return database transaction status
   */
  enum GNUNET_DB_QueryStatus
    (*insert_aml_decision)(
    void *cls,
    const struct TALER_PaytoHashP *h_payto,
    const struct TALER_Amount *new_threshold,
    enum TALER_AmlDecisionState new_status,
    struct GNUNET_TIME_Timestamp decision_time,
    const char *justification,
    const json_t *kyc_requirements,
    uint64_t requirements_row,
    const struct TALER_AmlOfficerPublicKeyP *decider_pub,
    const struct TALER_AmlOfficerSignatureP *decider_sig,
    bool *invalid_officer,
    struct GNUNET_TIME_Timestamp *last_date);


};

#endif /* _TALER_EXCHANGE_DB_H */
