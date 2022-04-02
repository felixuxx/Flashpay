/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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

#include <gnunet/gnunet_util_lib.h>
#include "taler_amount_lib.h"
#include "taler_crypto_lib.h"

/*********************************************/
/* Exchange offline signatures (with master key) */
/*********************************************/

/**
 * The given revocation key was revoked and must no longer be used.
 */
#define TALER_SIGNATURE_MASTER_SIGNING_KEY_REVOKED 1020

/**
 * Add payto URI to the list of our wire methods.
 */
#define TALER_SIGNATURE_MASTER_ADD_WIRE 1021

/**
 * Signature over global set of fees charged by the
 * exchange.
 */
#define TALER_SIGNATURE_MASTER_GLOBAL_FEES 1022

/**
 * Remove payto URI from the list of our wire methods.
 */
#define TALER_SIGNATURE_MASTER_DEL_WIRE 1023

/**
 * Purpose for signing public keys signed by the exchange master key.
 */
#define TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY 1024

/**
 * Purpose for denomination keys signed by the exchange master key.
 */
#define TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY 1025

/**
 * Add an auditor to the list of our auditors.
 */
#define TALER_SIGNATURE_MASTER_ADD_AUDITOR 1026

/**
 * Remove an auditor from the list of our auditors.
 */
#define TALER_SIGNATURE_MASTER_DEL_AUDITOR 1027

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

/**
 * Set the configuration of an extension (age-restriction or peer2peer)
 */
#define TALER_SIGNATURE_MASTER_EXTENSION 1031

/**
 * Signature affirming a partner configuration for wads.
 */
#define TALER_SIGNATURE_MASTER_PARTNER_DETAILS 1032

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
 * Signature where the Exchange confirms a recoup.
 */
#define TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP 1039

/**
 * Signature where the Exchange confirms it closed a reserve.
 */
#define TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED 1040

/**
 * Signature where the Exchange confirms a recoup-refresh operation.
 */
#define TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH 1041

/**
 * Signature where the Exchange confirms that it does not know a denomination (hash).
 */
#define TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_UNKNOWN 1042

/**
 * Signature where the Exchange confirms that it does not consider a denomination valid for the given operation
 * at this time.
 */
#define TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_EXPIRED 1043

/**
 * Signature by which an exchange affirms that an account
 * successfully passed the KYC checks.
 */
#define TALER_SIGNATURE_EXCHANGE_ACCOUNT_SETUP_SUCCESS 1044

/**
 * Signature by which the exchange affirms that a purse
 * was created with a certain amount deposited into it.
 */
#define TALER_SIGNATURE_EXCHANGE_CONFIRM_PURSE_CREATION 1045

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
 * Signature using a coin key requesting recoup.
 */
#define TALER_SIGNATURE_WALLET_COIN_RECOUP 1203

/**
 * Signature using a coin key authenticating link data.
 */
#define TALER_SIGNATURE_WALLET_COIN_LINK 1204

/**
 * Signature using a reserve key by which a wallet
 * requests a payment target UUID for itself.
 * Signs over just a purpose (no body), as the
 * signature only serves to demonstrate that the request
 * comes from the wallet controlling the private key,
 * and not some third party.
 */
#define TALER_SIGNATURE_WALLET_ACCOUNT_SETUP 1205

/**
 * Signature using a coin key requesting recoup-refresh.
 */
#define TALER_SIGNATURE_WALLET_COIN_RECOUP_REFRESH 1206

/**
 * Signature using a age restriction key for attestation of a particular
 * age/age-group.
 */
#define TALER_SIGNATURE_WALLET_AGE_ATTESTATION 1207

/**
 * Request full reserve history and pay for it.
 */
#define TALER_SIGNATURE_WALLET_RESERVE_HISTORY 1208

/**
 * Request detailed account status (for free).
 */
#define TALER_SIGNATURE_WALLET_RESERVE_STATUS 1209

/**
 * Request purse creation (without reserve).
 */
#define TALER_SIGNATURE_WALLET_PURSE_CREATE 1210

/**
 * Request coin to be deposited into a purse.
 */
#define TALER_SIGNATURE_WALLET_PURSE_DEPOSIT 1211

/**
 * Request purse status.
 */
#define TALER_SIGNATURE_WALLET_PURSE_STATUS 1212

/**
 * Request purse to be merged with a reserve (by purse).
 */
#define TALER_SIGNATURE_WALLET_PURSE_MERGE 1213

/**
 * Request purse to be merged with a reserve (by account).
 */
#define TALER_SIGNATURE_WALLET_ACCOUNT_MERGE 1214

/**
 * Request account to be closed.
 */
#define TALER_SIGNATURE_WALLET_RESERVE_CLOSE 1215

/**
 * Associates encrypted contract with a purse.
 */
#define TALER_SIGNATURE_WALLET_PURSE_ECONTRACT 1216

/******************************/
/* Security module signatures */
/******************************/

/**
 * Signature on a denomination key announcement.
 */
#define TALER_SIGNATURE_SM_RSA_DENOMINATION_KEY 1250

/**
 * Signature on an exchange message signing key announcement.
 */
#define TALER_SIGNATURE_SM_SIGNING_KEY 1251

/**
 * Signature on a denomination key announcement.
 */
#define TALER_SIGNATURE_SM_CS_DENOMINATION_KEY 1252

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


/************************/
/* Anastasis signatures */
/************************/

/**
 * EdDSA signature for a policy upload.
 */
#define TALER_SIGNATURE_ANASTASIS_POLICY_UPLOAD 1400


/*******************/
/* Sync signatures */
/*******************/


/**
 * EdDSA signature for a backup upload.
 */
#define TALER_SIGNATURE_SYNC_BACKUP_UPLOAD 1450


GNUNET_NETWORK_STRUCT_BEGIN


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
  struct TALER_PrivateContractHashP h_contract_terms GNUNET_PACKED;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct TALER_MerchantWireHashP h_wire GNUNET_PACKED;

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
  struct TALER_PrivateContractHashP hash;
};

/**
 * Used by merchants to return signed responses to /pay requests.
 * Currently only used to return 200 OK signed responses.
 */
struct TALER_PaymentResponsePS
{
  /**
   * Set to #TALER_SIGNATURE_MERCHANT_PAYMENT_OK. Note that
   * unsuccessful payments are usually proven by some exchange's signature.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the proposal data associated with this confirmation
   */
  struct TALER_PrivateContractHashP h_contract_terms;
};


GNUNET_NETWORK_STRUCT_END

#endif
