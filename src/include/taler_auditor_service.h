/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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


/* *********************  /version *********************** */

/**
 * @brief Information we get from the auditor about auditors.
 */
struct TALER_AUDITOR_VersionInformation
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
  char *version;

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
 * Function called with information about the auditor.
 *
 * @param cls closure
 * @param vi basic information about the auditor
 * @param compat protocol compatibility information
 */
typedef void
(*TALER_AUDITOR_VersionCallback) (void *cls,
                                  const struct
                                  TALER_AUDITOR_VersionInformation *vi,
                                  enum TALER_AUDITOR_VersionCompatibility
                                  compat);


/**
 * @brief Handle to the auditor.  This is where we interact with
 * a particular auditor and keep the per-auditor information.
 */
struct TALER_AUDITOR_Handle;


/**
 * Initialise a connection to the auditor. Will connect to the
 * auditor and obtain information about the auditor's master public
 * key and the auditor's auditor.  The respective information will
 * be passed to the @a version_cb once available, and all future
 * interactions with the auditor will be checked to be signed
 * (where appropriate) by the respective master key.
 *
 * @param ctx the context
 * @param url HTTP base URL for the auditor
 * @param version_cb function to call with the auditor's version information
 * @param version_cb_cls closure for @a version_cb
 * @return the auditor handle; NULL upon error
 */
struct TALER_AUDITOR_Handle *
TALER_AUDITOR_connect (struct GNUNET_CURL_Context *ctx,
                       const char *url,
                       TALER_AUDITOR_VersionCallback version_cb,
                       void *version_cb_cls);


/**
 * Disconnect from the auditor.
 *
 * @param auditor the auditor handle
 */
void
TALER_AUDITOR_disconnect (struct TALER_AUDITOR_Handle *auditor);


/**
 * @brief A DepositConfirmation Handle
 */
struct TALER_AUDITOR_DepositConfirmationHandle;


/**
 * Signature of functions called with the result from our call to the
 * auditor's /deposit-confirmation handler.
 *
 * @param cls closure
 * @param http_status HTTP status code, 200 on success
 * @param ec taler protocol error status code, 0 on success
 * @param json raw json response
 */
typedef void
(*TALER_AUDITOR_DepositConfirmationResultCallback)(void *cls,
                                                   unsigned int http_status,
                                                   enum TALER_ErrorCode ec,
                                                   const json_t *json);


/**
 * Submit a deposit-confirmation permission to the auditor and get the
 * auditor's response.  Note that while we return the response
 * verbatim to the caller for further processing, we do already verify
 * that the response is well-formed.  If the auditor's reply is not
 * well-formed, we return an HTTP status code of zero to @a cb.
 *
 * We also verify that the @a exchange_sig is valid for this deposit-confirmation
 * request, and that the @a master_sig is a valid signature for @a
 * exchange_pub.  Also, the @a auditor must be ready to operate (i.e.  have
 * finished processing the /version reply).  If either check fails, we do
 * NOT initiate the transaction with the auditor and instead return NULL.
 *
 * @param auditor the auditor handle; the auditor must be ready to operate
 * @param h_wire hash of merchant wire details
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the auditor)
 * @param timestamp timestamp when the contract was finalized, must not be too far in the future
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the auditor (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param amount_without_fee the amount confirmed to be wired by the exchange to the merchant
 * @param coin_pub coin’s public key
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param exchange_sig the signature made with purpose #TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT
 * @param exchange_pub the public key of the exchange that matches @a exchange_sig
 * @param master_pub master public key of the exchange
 * @param ep_start when does @a exchange_pub validity start
 * @param ep_expire when does @a exchange_pub usage end
 * @param ep_legal_end when does @a exchange_pub legal validity end
 * @param master_sig master signature affirming validity of @a exchange_pub
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_AUDITOR_DepositConfirmationHandle *
TALER_AUDITOR_deposit_confirmation (struct TALER_AUDITOR_Handle *auditor,
                                    const struct GNUNET_HashCode *h_wire,
                                    const struct
                                    GNUNET_HashCode *h_contract_terms,
                                    struct GNUNET_TIME_Absolute timestamp,
                                    struct GNUNET_TIME_Absolute refund_deadline,
                                    const struct
                                    TALER_Amount *amount_without_fee,
                                    const struct
                                    TALER_CoinSpendPublicKeyP *coin_pub,
                                    const struct
                                    TALER_MerchantPublicKeyP *merchant_pub,
                                    const struct
                                    TALER_ExchangePublicKeyP *exchange_pub,
                                    const struct
                                    TALER_ExchangeSignatureP *exchange_sig,
                                    const struct
                                    TALER_MasterPublicKeyP *master_pub,
                                    struct GNUNET_TIME_Absolute ep_start,
                                    struct GNUNET_TIME_Absolute ep_expire,
                                    struct GNUNET_TIME_Absolute ep_legal_end,
                                    const struct
                                    TALER_MasterSignatureP *master_sig,
                                    TALER_AUDITOR_DepositConfirmationResultCallback
                                    cb,
                                    void *cb_cls);


/**
 * Cancel a deposit-confirmation permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param deposit-confirmation the deposit-confirmation permission request handle
 */
void
TALER_AUDITOR_deposit_confirmation_cancel (struct
                                           TALER_AUDITOR_DepositConfirmationHandle
                                           *deposit_confirmation);


/**
 * Handle for /exchanges API returned by
 * #TALER_AUDITOR_list_exchanges() so that the operation can be
 * cancelled with #TALER_AUDITOR_list_exchanges_cancel()
 */
struct TALER_AUDITOR_ListExchangesHandle;


/**
 * Information about an exchange kept by the auditor.
 */
struct TALER_AUDITOR_ExchangeInfo
{
  /**
   * Master public key of the exchange.
   */
  struct TALER_MasterPublicKeyP master_pub;

  /**
   * Base URL of the exchange's API.
   */
  const char *exchange_url;
};


/**
 * Function called with the result from /exchagnes.
 *
 * @param cls closure
 * @param http_status the HTTP status code, 200 on success
 * @param ec detailed Taler error status code, #TALER_EC_NONE on success
 * @param num_exchanges length of array at @a ei
 * @param ei information about exchanges returned by the auditor
 * @param raw_response raw JSON response
 */
typedef void
(*TALER_AUDITOR_ListExchangesResultCallback)(void *cls,
                                             unsigned int http_status,
                                             enum TALER_ErrorCode ec,
                                             unsigned int num_exchanges,
                                             const struct
                                             TALER_AUDITOR_ExchangeInfo *ei,
                                             const json_t *raw_response);

/**
 * Submit an /exchanges request to the auditor and get the
 * auditor's response.  If the auditor's reply is not
 * well-formed, we return an HTTP status code of zero to @a cb.
 *
 * @param auditor the auditor handle; the auditor must be ready to operate
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_AUDITOR_ListExchangesHandle *
TALER_AUDITOR_list_exchanges (struct TALER_AUDITOR_Handle *auditor,
                              TALER_AUDITOR_ListExchangesResultCallback cb,
                              void *cb_cls);


/**
 * Cancel a deposit-confirmation permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param deposit-confirmation the deposit-confirmation permission request handle
 */
void
TALER_AUDITOR_list_exchanges_cancel (struct
                                     TALER_AUDITOR_ListExchangesHandle *leh);


#endif  /* _TALER_AUDITOR_SERVICE_H */
