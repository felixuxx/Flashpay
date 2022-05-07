/*
  This file is part of TALER
  Copyright (C) 2021, 2022 Taler Systems SA

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
 * @file exchange_signatures.c
 * @brief Utility functions for Taler security module signatures
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


GNUNET_NETWORK_STRUCT_BEGIN

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
  struct TALER_PrivateContractHashP h_contract_terms GNUNET_PACKED;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct TALER_MerchantWireHashP h_wire GNUNET_PACKED;

  /**
   * Hash over the extension options of the deposit, 0 if there
   * were not extension options.
   */
  struct TALER_ExtensionContractHashP h_extensions GNUNET_PACKED;

  /**
   * Time when this confirmation was generated / when the exchange received
   * the deposit request.
   */
  struct GNUNET_TIME_TimestampNBO exchange_timestamp;

  /**
   * By when does the exchange expect to pay the merchant
   * (as per the merchant's request).
   */
  struct GNUNET_TIME_TimestampNBO wire_deadline;

  /**
   * How much time does the @e merchant have to issue a refund
   * request?  Zero if refunds are not allowed.  After this time, the
   * coin cannot be refunded.  Note that the wire transfer will not be
   * performed by the exchange until the refund deadline.  This value
   * is taken from the original deposit request.
   */
  struct GNUNET_TIME_TimestampNBO refund_deadline;

  /**
   * Amount to be deposited, excluding fee.  Calculated from the
   * amount with fee and the fee from the deposit request.
   */
  struct TALER_AmountNBO amount_without_fee;

  /**
   * The public key of the coin that was deposited.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * The Merchant's public key.  Allows the merchant to later refund
   * the transaction or to inquire about the wire transfer identifier.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_deposit_confirmation_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_ExtensionContractHashP *h_extensions,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Timestamp wire_deadline,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_DepositConfirmationPS dcs = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT),
    .purpose.size = htonl (sizeof (struct TALER_DepositConfirmationPS)),
    .h_contract_terms = *h_contract_terms,
    .h_wire = *h_wire,
    .exchange_timestamp = GNUNET_TIME_timestamp_hton (exchange_timestamp),
    .wire_deadline = GNUNET_TIME_timestamp_hton (wire_deadline),
    .refund_deadline = GNUNET_TIME_timestamp_hton (refund_deadline),
    .coin_pub = *coin_pub,
    .merchant_pub = *merchant_pub
  };

  if (NULL != h_extensions)
    dcs.h_extensions = *h_extensions;
  TALER_amount_hton (&dcs.amount_without_fee,
                     amount_without_fee);
  return scb (&dcs.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_deposit_confirmation_verify (
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_ExtensionContractHashP *h_extensions,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Timestamp wire_deadline,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig)
{
  struct TALER_DepositConfirmationPS dcs = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT),
    .purpose.size = htonl (sizeof (struct TALER_DepositConfirmationPS)),
    .h_contract_terms = *h_contract_terms,
    .h_wire = *h_wire,
    .exchange_timestamp = GNUNET_TIME_timestamp_hton (exchange_timestamp),
    .wire_deadline = GNUNET_TIME_timestamp_hton (wire_deadline),
    .refund_deadline = GNUNET_TIME_timestamp_hton (refund_deadline),
    .coin_pub = *coin_pub,
    .merchant_pub = *merchant_pub
  };

  if (NULL != h_extensions)
    dcs.h_extensions = *h_extensions;
  TALER_amount_hton (&dcs.amount_without_fee,
                     amount_without_fee);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT,
                                  &dcs,
                                  &exchange_sig->eddsa_signature,
                                  &exchange_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


GNUNET_NETWORK_STRUCT_BEGIN

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
  struct TALER_PrivateContractHashP h_contract_terms GNUNET_PACKED;

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
};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_refund_confirmation_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant,
  uint64_t rtransaction_id,
  const struct TALER_Amount *refund_amount,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_RefundConfirmationPS rc = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND),
    .purpose.size = htonl (sizeof (rc)),
    .h_contract_terms = *h_contract_terms,
    .coin_pub = *coin_pub,
    .merchant = *merchant,
    .rtransaction_id = GNUNET_htonll (rtransaction_id)
  };

  TALER_amount_hton (&rc.refund_amount,
                     refund_amount);
  return scb (&rc.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_refund_confirmation_verify (
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant,
  uint64_t rtransaction_id,
  const struct TALER_Amount *refund_amount,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_RefundConfirmationPS rc = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND),
    .purpose.size = htonl (sizeof (rc)),
    .h_contract_terms = *h_contract_terms,
    .coin_pub = *coin_pub,
    .merchant = *merchant,
    .rtransaction_id = GNUNET_htonll (rtransaction_id)
  };

  TALER_amount_hton (&rc.refund_amount,
                     refund_amount);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND,
                                  &rc,
                                  &sig->eddsa_signature,
                                  &pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


GNUNET_NETWORK_STRUCT_BEGIN

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

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_melt_confirmation_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_RefreshCommitmentP *rc,
  uint32_t noreveal_index,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_RefreshMeltConfirmationPS confirm = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT),
    .purpose.size = htonl (sizeof (confirm)),
    .rc = *rc,
    .noreveal_index = htonl (noreveal_index)
  };

  return scb (&confirm.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_melt_confirmation_verify (
  const struct TALER_RefreshCommitmentP *rc,
  uint32_t noreveal_index,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig)
{
  struct TALER_RefreshMeltConfirmationPS confirm = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT),
    .purpose.size = htonl (sizeof (confirm)),
    .rc = *rc,
    .noreveal_index = htonl (noreveal_index)
  };

  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT,
                                &confirm,
                                &exchange_sig->eddsa_signature,
                                &exchange_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

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
  struct GNUNET_TIME_TimestampNBO list_issue_date;

  /**
   * Hash over the various denomination signing keys returned.
   */
  struct GNUNET_HashCode hc GNUNET_PACKED;
};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_key_set_sign (
  TALER_ExchangeSignCallback2 scb,
  void *cls,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct GNUNET_HashCode *hc,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_ExchangeKeySetPS ks = {
    .purpose.size = htonl (sizeof (ks)),
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_KEY_SET),
    .list_issue_date = GNUNET_TIME_timestamp_hton (timestamp),
    .hc = *hc
  };

  return scb (cls,
              &ks.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_key_set_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct GNUNET_HashCode *hc,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_ExchangeKeySetPS ks = {
    .purpose.size = htonl (sizeof (ks)),
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_KEY_SET),
    .list_issue_date = GNUNET_TIME_timestamp_hton (timestamp),
    .hc = *hc
  };

  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_KEY_SET,
                                &ks,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Signature by which an exchange affirms that an account
 * successfully passed the KYC checks.
 */
struct TALER_ExchangeAccountSetupSuccessPS
{
  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_ACCOUNT_SETUP_SUCCESS.  Signed by a
   * `struct TALER_ExchangePublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the payto for which the signature was
   * made.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * When was the signature made.
   */
  struct GNUNET_TIME_TimestampNBO timestamp;
};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_account_setup_success_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp timestamp,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_ExchangeAccountSetupSuccessPS kyc_purpose = {
    .purpose.size = htonl (sizeof (kyc_purpose)),
    .purpose.purpose = htonl (
      TALER_SIGNATURE_EXCHANGE_ACCOUNT_SETUP_SUCCESS),
    .h_payto = *h_payto,
    .timestamp = GNUNET_TIME_timestamp_hton (
      timestamp)
  };

  return scb (&kyc_purpose.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_account_setup_success_verify (
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_ExchangeAccountSetupSuccessPS kyc_purpose = {
    .purpose.size = htonl (sizeof (kyc_purpose)),
    .purpose.purpose = htonl (
      TALER_SIGNATURE_EXCHANGE_ACCOUNT_SETUP_SUCCESS),
    .h_payto = *h_payto,
    .timestamp = GNUNET_TIME_timestamp_hton (
      timestamp)
  };

  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_ACCOUNT_SETUP_SUCCESS,
                                &kyc_purpose,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Format internally used for packing the detailed information
 * to generate the signature for /track/transfer signatures.
 */
struct TALER_WireDepositDetailP
{

  /**
   * Hash of the contract
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Time when the wire transfer was performed by the exchange.
   */
  struct GNUNET_TIME_TimestampNBO execution_time;

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

GNUNET_NETWORK_STRUCT_END


void
TALER_exchange_online_wire_deposit_append (
  struct GNUNET_HashContext *hash_context,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp execution_time,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *deposit_value,
  const struct TALER_Amount *deposit_fee)
{
  struct TALER_WireDepositDetailP dd = {
    .h_contract_terms = *h_contract_terms,
    .execution_time = GNUNET_TIME_timestamp_hton (execution_time),
    .coin_pub = *coin_pub
  };
  TALER_amount_hton (&dd.deposit_value,
                     deposit_value);
  TALER_amount_hton (&dd.deposit_fee,
                     deposit_fee);
  GNUNET_CRYPTO_hash_context_read (hash_context,
                                   &dd,
                                   sizeof (dd));
}


GNUNET_NETWORK_STRUCT_BEGIN

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
   * Hash of bank account of the merchant.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Hash of the individual deposits that were aggregated,
   * each in the format of a `struct TALER_WireDepositDetailP`.
   */
  struct GNUNET_HashCode h_details;

};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_wire_deposit_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_Amount *total,
  const struct TALER_Amount *wire_fee,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const char *payto,
  const struct GNUNET_HashCode *h_details,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_WireDepositDataPS wdp = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE_DEPOSIT),
    .purpose.size = htonl (sizeof (wdp)),
    .merchant_pub = *merchant_pub,
    .h_details = *h_details
  };

  TALER_amount_hton (&wdp.total,
                     total);
  TALER_amount_hton (&wdp.wire_fee,
                     wire_fee);
  TALER_payto_hash (payto,
                    &wdp.h_payto);
  return scb (&wdp.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_wire_deposit_verify (
  const struct TALER_Amount *total,
  const struct TALER_Amount *wire_fee,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_PaytoHashP *h_payto,
  const struct GNUNET_HashCode *h_details,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_WireDepositDataPS wdp = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE_DEPOSIT),
    .purpose.size = htonl (sizeof (wdp)),
    .merchant_pub = *merchant_pub,
    .h_details = *h_details,
    .h_payto = *h_payto
  };

  TALER_amount_hton (&wdp.total,
                     total);
  TALER_amount_hton (&wdp.wire_fee,
                     wire_fee);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE_DEPOSIT,
                                &wdp,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

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
  struct TALER_MerchantWireHashP h_wire GNUNET_PACKED;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct TALER_PrivateContractHashP h_contract_terms GNUNET_PACKED;

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
  struct GNUNET_TIME_TimestampNBO execution_time;

  /**
   * The contribution of @e coin_pub to the total transfer volume.
   * This is the value of the deposit minus the fee.
   */
  struct TALER_AmountNBO coin_contribution;

};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_confirm_wire_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct GNUNET_TIME_Timestamp execution_time,
  const struct TALER_Amount *coin_contribution,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)

{
  struct TALER_ConfirmWirePS cw = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE),
    .purpose.size = htonl (sizeof (cw)),
    .h_wire = *h_wire,
    .h_contract_terms = *h_contract_terms,
    .wtid = *wtid,
    .coin_pub = *coin_pub,
    .execution_time = GNUNET_TIME_timestamp_hton (execution_time)
  };

  TALER_amount_hton (&cw.coin_contribution,
                     coin_contribution);
  return scb (&cw.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_confirm_wire_verify (
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct GNUNET_TIME_Timestamp execution_time,
  const struct TALER_Amount *coin_contribution,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_ConfirmWirePS cw = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE),
    .purpose.size = htonl (sizeof (cw)),
    .h_wire = *h_wire,
    .h_contract_terms = *h_contract_terms,
    .wtid = *wtid,
    .coin_pub = *coin_pub,
    .execution_time = GNUNET_TIME_timestamp_hton (execution_time)
  };

  TALER_amount_hton (&cw.coin_contribution,
                     coin_contribution);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE,
                                &cw,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Response by which the exchange affirms that it will
 * refund a coin as part of the emergency /recoup
 * protocol.  The recoup will go back to the bank
 * account that created the reserve.
 */
struct TALER_RecoupConfirmationPS
{

  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When did the exchange receive the recoup request?
   * Indirectly determines when the wire transfer is (likely)
   * to happen.
   */
  struct GNUNET_TIME_TimestampNBO timestamp;

  /**
   * How much of the coin's value will the exchange transfer?
   * (Needed in case the coin was partially spent.)
   */
  struct TALER_AmountNBO recoup_amount;

  /**
   * Public key of the coin.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Public key of the reserve that will receive the recoup.
   */
  struct TALER_ReservePublicKeyP reserve_pub;
};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_confirm_recoup_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *recoup_amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_RecoupConfirmationPS pc = {
    .purpose.size = htonl (sizeof (pc)),
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP),
    .reserve_pub = *reserve_pub,
    .coin_pub = *coin_pub
  };

  TALER_amount_hton (&pc.recoup_amount,
                     recoup_amount);
  return scb (&pc.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_confirm_recoup_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *recoup_amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_RecoupConfirmationPS pc = {
    .purpose.size = htonl (sizeof (pc)),
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP),
    .reserve_pub = *reserve_pub,
    .coin_pub = *coin_pub
  };

  TALER_amount_hton (&pc.recoup_amount,
                     recoup_amount);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP,
                                &pc,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Response by which the exchange affirms that it will refund a refreshed coin
 * as part of the emergency /recoup protocol.  The recoup will go back to the
 * old coin's balance.
 */
struct TALER_RecoupRefreshConfirmationPS
{

  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When did the exchange receive the recoup request?
   * Indirectly determines when the wire transfer is (likely)
   * to happen.
   */
  struct GNUNET_TIME_TimestampNBO timestamp;

  /**
   * How much of the coin's value will the exchange transfer?
   * (Needed in case the coin was partially spent.)
   */
  struct TALER_AmountNBO recoup_amount;

  /**
   * Public key of the refreshed coin.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Public key of the old coin that will receive the recoup.
   */
  struct TALER_CoinSpendPublicKeyP old_coin_pub;
};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_confirm_recoup_refresh_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *recoup_amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_RecoupRefreshConfirmationPS pc = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH),
    .purpose.size = htonl (sizeof (pc)),
    .timestamp = GNUNET_TIME_timestamp_hton (timestamp),
    .coin_pub = *coin_pub,
    .old_coin_pub = *old_coin_pub
  };

  TALER_amount_hton (&pc.recoup_amount,
                     recoup_amount);
  return scb (&pc.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_confirm_recoup_refresh_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *recoup_amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_RecoupRefreshConfirmationPS pc = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH),
    .purpose.size = htonl (sizeof (pc)),
    .timestamp = GNUNET_TIME_timestamp_hton (timestamp),
    .coin_pub = *coin_pub,
    .old_coin_pub = *old_coin_pub
  };

  TALER_amount_hton (&pc.recoup_amount,
                     recoup_amount);

  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH,
                                &pc,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Response by which the exchange affirms that it does not
 * currently know a denomination by the given hash.
 */
struct TALER_DenominationUnknownAffirmationPS
{

  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_UNKNOWN
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When did the exchange sign this message.
   */
  struct GNUNET_TIME_TimestampNBO timestamp;

  /**
   * Hash of the public denomination key we do not know.
   */
  struct TALER_DenominationHashP h_denom_pub;
};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_denomination_unknown_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_DenominationUnknownAffirmationPS dua = {
    .purpose.size = htonl (sizeof (dua)),
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_UNKNOWN),
    .timestamp = GNUNET_TIME_timestamp_hton (timestamp),
    .h_denom_pub = *h_denom_pub,
  };

  return scb (&dua.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_denomination_unknown_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_DenominationUnknownAffirmationPS dua = {
    .purpose.size = htonl (sizeof (dua)),
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_UNKNOWN),
    .timestamp = GNUNET_TIME_timestamp_hton (timestamp),
    .h_denom_pub = *h_denom_pub,
  };

  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_UNKNOWN,
                                &dua,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Response by which the exchange affirms that it does not
 * currently consider the given denomination to be valid
 * for the requested operation.
 */
struct TALER_DenominationExpiredAffirmationPS
{

  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_EXPIRED
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When did the exchange sign this message.
   */
  struct GNUNET_TIME_TimestampNBO timestamp;

  /**
   * Name of the operation that is not allowed at this time.  Might NOT be 0-terminated, but is padded with 0s.
   */
  char operation[8];

  /**
   * Hash of the public denomination key we do not know.
   */
  struct TALER_DenominationHashP h_denom_pub;

};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_denomination_expired_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_DenominationHashP *h_denom_pub,
  const char *op,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_DenominationExpiredAffirmationPS dua = {
    .purpose.size = htonl (sizeof (dua)),
    .purpose.purpose = htonl (
      TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_EXPIRED),
    .timestamp = GNUNET_TIME_timestamp_hton (timestamp),
    .h_denom_pub = *h_denom_pub,
  };

  /* strncpy would create a compiler warning */
  memcpy (dua.operation,
          op,
          GNUNET_MIN (sizeof (dua.operation),
                      strlen (op)));
  return scb (&dua.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_denomination_expired_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_DenominationHashP *h_denom_pub,
  const char *op,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_DenominationExpiredAffirmationPS dua = {
    .purpose.size = htonl (sizeof (dua)),
    .purpose.purpose = htonl (
      TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_EXPIRED),
    .timestamp = GNUNET_TIME_timestamp_hton (timestamp),
    .h_denom_pub = *h_denom_pub,
  };

  /* strncpy would create a compiler warning */
  memcpy (dua.operation,
          op,
          GNUNET_MIN (sizeof (dua.operation),
                      strlen (op)));
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_EXPIRED,
                                &dua,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

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
  struct GNUNET_TIME_TimestampNBO timestamp;

  /**
   * How much did the exchange send?
   */
  struct TALER_AmountNBO closing_amount;

  /**
   * How much did the exchange charge for closing the reserve?
   */
  struct TALER_AmountNBO closing_fee;

  /**
   * Public key of the reserve that was closed.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Hash of the receiver's bank account.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Wire transfer subject.
   */
  struct TALER_WireTransferIdentifierRawP wtid;
};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_reserve_closed_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *closing_amount,
  const struct TALER_Amount *closing_fee,
  const char *payto,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_ReserveCloseConfirmationPS rcc = {
    .purpose.size = htonl (sizeof (rcc)),
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED),
    .wtid = *wtid,
    .reserve_pub = *reserve_pub,
    .timestamp = GNUNET_TIME_timestamp_hton (timestamp)
  };

  TALER_amount_hton (&rcc.closing_amount,
                     closing_amount);
  TALER_amount_hton (&rcc.closing_fee,
                     closing_fee);
  TALER_payto_hash (payto,
                    &rcc.h_payto);
  return scb (&rcc.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_reserve_closed_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *closing_amount,
  const struct TALER_Amount *closing_fee,
  const char *payto,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_ReserveCloseConfirmationPS rcc = {
    .purpose.size = htonl (sizeof (rcc)),
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED),
    .wtid = *wtid,
    .reserve_pub = *reserve_pub,
    .timestamp = GNUNET_TIME_timestamp_hton (timestamp)
  };

  TALER_amount_hton (&rcc.closing_amount,
                     closing_amount);
  TALER_amount_hton (&rcc.closing_fee,
                     closing_fee);
  TALER_payto_hash (payto,
                    &rcc.h_payto);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED,
                                &rcc,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Response by which the exchange affirms that it has
 * received funds deposited into a purse.
 */
struct TALER_PurseCreateDepositConfirmationPS
{

  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_CONFIRM_PURSE_CREATION
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When did the exchange receive the deposits.
   */
  struct GNUNET_TIME_TimestampNBO exchange_time;

  /**
   * When will the purse expire?
   */
  struct GNUNET_TIME_TimestampNBO purse_expiration;

  /**
   * How much should the purse ultimately contain.
   */
  struct TALER_AmountNBO amount_without_fee;

  /**
   * How much was deposited so far.
   */
  struct TALER_AmountNBO total_deposited;

  /**
   * Public key of the purse.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Public key of the merge capability.
   */
  struct TALER_PurseMergePublicKeyP merge_pub;

  /**
   * Hash of the contract of the purse.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_purse_created_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp exchange_time,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_Amount *total_deposited,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_PurseCreateDepositConfirmationPS dc = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PURSE_CREATION),
    .purpose.size = htonl (sizeof (dc)),
    .h_contract_terms = *h_contract_terms,
    .purse_pub = *purse_pub,
    .merge_pub = *merge_pub,
    .purse_expiration = GNUNET_TIME_timestamp_hton (purse_expiration),
    .exchange_time = GNUNET_TIME_timestamp_hton (exchange_time)
  };

  TALER_amount_hton (&dc.amount_without_fee,
                     amount_without_fee);
  TALER_amount_hton (&dc.total_deposited,
                     total_deposited);
  return scb (&dc.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_purse_created_verify (
  struct GNUNET_TIME_Timestamp exchange_time,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_Amount *total_deposited,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_PurseCreateDepositConfirmationPS dc = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PURSE_CREATION),
    .purpose.size = htonl (sizeof (dc)),
    .h_contract_terms = *h_contract_terms,
    .purse_pub = *purse_pub,
    .merge_pub = *merge_pub,
    .purse_expiration = GNUNET_TIME_timestamp_hton (purse_expiration),
    .exchange_time = GNUNET_TIME_timestamp_hton (exchange_time)
  };

  TALER_amount_hton (&dc.amount_without_fee,
                     amount_without_fee);
  TALER_amount_hton (&dc.total_deposited,
                     total_deposited);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_PURSE_CREATION,
                                &dc,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Response by which the exchange affirms that it has
 * merged a purse into a reserve.
 */
struct TALER_PurseMergedConfirmationPS
{

  /**
   * Purpose is #TALER_SIGNATURE_EXCHANGE_CONFIRM_PURSE_MERGED
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When did the exchange receive the deposits.
   */
  struct GNUNET_TIME_TimestampNBO exchange_time;

  /**
   * When will the purse expire?
   */
  struct GNUNET_TIME_TimestampNBO purse_expiration;

  /**
   * How much should the purse ultimately contain.
   */
  struct TALER_AmountNBO amount_without_fee;

  /**
   * Public key of the purse.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Public key of the reserve.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Hash of the contract of the purse.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Hash of the provider URL hosting the reserve.
   */
  struct GNUNET_HashCode h_provider_url;

};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_purse_merged_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp exchange_time,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *exchange_url,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_PurseMergedConfirmationPS dc = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PURSE_MERGED),
    .purpose.size = htonl (sizeof (dc)),
    .h_contract_terms = *h_contract_terms,
    .purse_pub = *purse_pub,
    .reserve_pub = *reserve_pub,
    .purse_expiration = GNUNET_TIME_timestamp_hton (purse_expiration),
    .exchange_time = GNUNET_TIME_timestamp_hton (exchange_time)
  };

  TALER_amount_hton (&dc.amount_without_fee,
                     amount_without_fee);
  GNUNET_CRYPTO_hash (exchange_url,
                      strlen (exchange_url) + 1,
                      &dc.h_provider_url);
  return scb (&dc.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_purse_merged_verify (
  struct GNUNET_TIME_Timestamp exchange_time,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *exchange_url,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_PurseMergedConfirmationPS dc = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PURSE_MERGED),
    .purpose.size = htonl (sizeof (dc)),
    .h_contract_terms = *h_contract_terms,
    .purse_pub = *purse_pub,
    .reserve_pub = *reserve_pub,
    .purse_expiration = GNUNET_TIME_timestamp_hton (purse_expiration),
    .exchange_time = GNUNET_TIME_timestamp_hton (exchange_time)
  };

  TALER_amount_hton (&dc.amount_without_fee,
                     amount_without_fee);
  GNUNET_CRYPTO_hash (exchange_url,
                      strlen (exchange_url) + 1,
                      &dc.h_provider_url);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_PURSE_MERGED,
                                &dc,
                                &sig->eddsa_signature,
                                &pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Format used to generate the signature on a purse status
 * from the exchange.
 */
struct TALER_PurseStatusPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_EXCHANGE_PURSE_STATUS.  Signed
   * by a `struct TALER_ExchangePublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Time when the purse was merged, possibly 'never'.
   */
  struct GNUNET_TIME_TimestampNBO merge_timestamp;

  /**
   * Time when the purse was deposited last, possibly 'never'.
   */
  struct GNUNET_TIME_TimestampNBO deposit_timestamp;

  /**
   * Amount deposited in total in the purse without fees.
   * May be possibly less than the target amount.
   */
  struct TALER_AmountNBO balance;

};

GNUNET_NETWORK_STRUCT_END


enum TALER_ErrorCode
TALER_exchange_online_purse_status_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  struct GNUNET_TIME_Timestamp deposit_timestamp,
  const struct TALER_Amount *balance,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TALER_PurseStatusPS dcs = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_PURSE_STATUS),
    .purpose.size = htonl (sizeof (dcs)),
    .merge_timestamp = GNUNET_TIME_timestamp_hton (merge_timestamp),
    .deposit_timestamp = GNUNET_TIME_timestamp_hton (deposit_timestamp)
  };

  TALER_amount_hton (&dcs.balance,
                     balance);
  return scb (&dcs.purpose,
              pub,
              sig);
}


enum GNUNET_GenericReturnValue
TALER_exchange_online_purse_status_verify (
  struct GNUNET_TIME_Timestamp merge_timestamp,
  struct GNUNET_TIME_Timestamp deposit_timestamp,
  const struct TALER_Amount *balance,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig)
{
  struct TALER_PurseStatusPS dcs = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_PURSE_STATUS),
    .purpose.size = htonl (sizeof (dcs)),
    .merge_timestamp = GNUNET_TIME_timestamp_hton (merge_timestamp),
    .deposit_timestamp = GNUNET_TIME_timestamp_hton (deposit_timestamp)
  };

  TALER_amount_hton (&dcs.balance,
                     balance);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_PURSE_STATUS,
                                  &dcs,
                                  &exchange_sig->eddsa_signature,
                                  &exchange_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/* end of exchange_signatures.c */
