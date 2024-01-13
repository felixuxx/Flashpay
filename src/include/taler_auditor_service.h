/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file include/taler_auditor_service.h
 * @brief C interface of libtalerauditor, a C library to use auditor's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#ifndef _TALER_AUDITOR_SERVICE_H
#define _TALER_AUDITOR_SERVICE_H

#include <jansson.h>
#include "taler_util.h"
#include "taler_error_codes.h"
#include <gnunet/gnunet_curl_lib.h>


/* *********************  /config *********************** */

/**
 * @brief Information we get from the auditor about itself.
 */
struct TALER_AUDITOR_ConfigInformation
{
  /**
   * Public key of the auditing institution.  Wallets and merchants
   * are expected to be configured with a set of public keys of
   * auditors that they deem acceptable.  These public keys are
   * the roots of the Taler PKI.
   */
  struct TALER_AuditorPublicKeyP auditor_pub;

  /**
   * Supported Taler protocol version by the auditor.
   * String in the format current:revision:age using the
   * semantics of GNU libtool.  See
   * https://www.gnu.org/software/libtool/manual/html_node/Versioning.html#Versioning
   */
  const char *version;

};


/**
 * How compatible are the protocol version of the auditor and this
 * client?  The bits (1,2,4) can be used to test if the auditor's
 * version is incompatible, older or newer respectively.
 */
enum TALER_AUDITOR_VersionCompatibility
{

  /**
   * The auditor runs exactly the same protocol version.
   */
  TALER_AUDITOR_VC_MATCH = 0,

  /**
   * The auditor is too old or too new to be compatible with this
   * implementation (bit)
   */
  TALER_AUDITOR_VC_INCOMPATIBLE = 1,

  /**
   * The auditor is older than this implementation (bit)
   */
  TALER_AUDITOR_VC_OLDER = 2,

  /**
   * The auditor is too old to be compatible with
   * this implementation.
   */
  TALER_AUDITOR_VC_INCOMPATIBLE_OUTDATED
    = TALER_AUDITOR_VC_INCOMPATIBLE
      | TALER_AUDITOR_VC_OLDER,

  /**
   * The auditor is more recent than this implementation (bit).
   */
  TALER_AUDITOR_VC_NEWER = 4,

  /**
   * The auditor is too recent for this implementation.
   */
  TALER_AUDITOR_VC_INCOMPATIBLE_NEWER
    = TALER_AUDITOR_VC_INCOMPATIBLE
      | TALER_AUDITOR_VC_NEWER,

  /**
   * We could not even parse the version data.
   */
  TALER_AUDITOR_VC_PROTOCOL_ERROR = 8

};


/**
 * General information about the HTTP response we obtained
 * from the auditor for a request.
 */
struct TALER_AUDITOR_HttpResponse
{

  /**
   * The complete JSON reply. NULL if we failed to parse the
   * reply (too big, invalid JSON).
   */
  const json_t *reply;

  /**
   * Set to the human-readable 'hint' that is optionally
   * provided by the exchange together with errors. NULL
   * if no hint was provided or if there was no error.
   */
  const char *hint;

  /**
   * HTTP status code for the response.  0 if the
   * HTTP request failed and we did not get any answer, or
   * if the answer was invalid and we set @a ec to a
   * client-side error code.
   */
  unsigned int http_status;

  /**
   * Taler error code.  #TALER_EC_NONE if everything was
   * OK.  Usually set to the "code" field of an error
   * response, but may be set to values created at the
   * client side, for example when the response was
   * not in JSON format or was otherwise ill-formed.
   */
  enum TALER_ErrorCode ec;

};


/**
 * Response to /config request.
 */
struct TALER_AUDITOR_ConfigResponse
{
  /**
   * HTTP response.
   */
  struct TALER_AUDITOR_HttpResponse hr;

  /**
   * Details depending on HTTP status.
   */
  union
  {

    /**
     * Details for #MHD_HTTP_OK.
     */
    struct
    {

      /**
       * Protocol compatibility evaluation.
       */
      enum TALER_AUDITOR_VersionCompatibility compat;

      /**
       * Config data returned by /config.
       */
      struct TALER_AUDITOR_ConfigInformation vi;

    } ok;

  } details;

};


/**
 * Function called with information about the auditor.
 *
 * @param cls closure
 * @param vr response data
 */
typedef void
(*TALER_AUDITOR_ConfigCallback) (
  void *cls,
  const struct TALER_AUDITOR_ConfigResponse *vr);


/**
 * @brief Handle to the auditor.  This is where we interact with
 * a particular auditor and keep the per-auditor information.
 */
struct TALER_AUDITOR_GetConfigHandle;


/**
 * Obtain meta data about an auditor. Will connect to the
 * auditor and obtain information about the auditor's master public
 * key and the auditor's auditor.  The respective information will
 * be passed to the @a config_cb once available.
 *
 * @param ctx the context for CURL requests
 * @param url HTTP base URL for the auditor
 * @param config_cb function to call with the auditor's config information
 * @param config_cb_cls closure for @a config_cb
 * @return the auditor handle; NULL upon error
 */
struct TALER_AUDITOR_GetConfigHandle *
TALER_AUDITOR_get_config (struct GNUNET_CURL_Context *ctx,
                          const char *url,
                          TALER_AUDITOR_ConfigCallback config_cb,
                          void *config_cb_cls);


/**
 * Cancel auditor config request.
 *
 * @param[in] auditor the auditor handle
 */
void
TALER_AUDITOR_get_config_cancel (
  struct TALER_AUDITOR_GetConfigHandle *auditor);


/**
 * @brief A DepositConfirmation Handle
 */
struct TALER_AUDITOR_DepositConfirmationHandle;


/**
 * Response to /deposit-confirmation request.
 */
struct TALER_AUDITOR_DepositConfirmationResponse
{
  /**
   * HTTP response.
   */
  struct TALER_AUDITOR_HttpResponse hr;
};


/**
 * Signature of functions called with the result from our call to the
 * auditor's /deposit-confirmation handler.
 *
 * @param cls closure
 * @param dcr response data
 */
typedef void
(*TALER_AUDITOR_DepositConfirmationResultCallback)(
  void *cls,
  const struct TALER_AUDITOR_DepositConfirmationResponse *dcr);


/**
 * Submit a deposit-confirmation permission to the auditor and get the
 * auditor's response.  Note that while we return the response
 * verbatim to the caller for further processing, we do already verify
 * that the response is well-formed.  If the auditor's reply is not
 * well-formed, we return an HTTP status code of zero to @a cb.
 *
 * We also verify that the @a exchange_sig is valid for this
 * deposit-confirmation request, and that the @a master_sig is a valid
 * signature for @a exchange_pub.  If the check fails, we do NOT initiate the
 * transaction with the auditor and instead return NULL.
 *
 * @param ctx the context for CURL requests
 * @param url HTTP base URL for the auditor
 * @param h_wire hash of merchant wire details
 * @param h_policy hash over the policy, if any
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the auditor)
 * @param exchange_timestamp timestamp when the contract was finalized, must not be too far in the future
 * @param wire_deadline date until which the exchange should wire the funds
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the auditor (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param total_without_fee the amount confirmed to be wired by the exchange to the merchant
 * @param num_coins number of coins involved in the batch deposit
 * @param coin_pubs array of the coin’s public keys
 * @param coin_sigs array of the original deposit signatures of the coins in the batch
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param exchange_sig the signature made with purpose #TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT
 * @param exchange_pub the public key of the exchange that matches @a exchange_sig
 * @param master_pub master public key of the exchange
 * @param ep_start when does @a exchange_pub validity start
 * @param ep_expire when does @a exchange_pub usage end
 * @param ep_end when does @a exchange_pub legal validity end
 * @param master_sig master signature affirming validity of @a exchange_pub
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_AUDITOR_DepositConfirmationHandle *
TALER_AUDITOR_deposit_confirmation (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_ExtensionPolicyHashP *h_policy,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Timestamp wire_deadline,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_Amount *total_without_fee,
  unsigned int num_coins,
  const struct TALER_CoinSpendPublicKeyP *coin_pubs[static num_coins],
  const struct TALER_CoinSpendSignatureP *coin_sigs[static num_coins],
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Timestamp ep_start,
  struct GNUNET_TIME_Timestamp ep_expire,
  struct GNUNET_TIME_Timestamp ep_end,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_AUDITOR_DepositConfirmationResultCallback cb,
  void *cb_cls);


/**
 * Cancel a deposit-confirmation permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param deposit_confirmation the deposit-confirmation permission request handle
 */
void
TALER_AUDITOR_deposit_confirmation_cancel (
  struct TALER_AUDITOR_DepositConfirmationHandle *deposit_confirmation);


#endif  /* _TALER_AUDITOR_SERVICE_H */
