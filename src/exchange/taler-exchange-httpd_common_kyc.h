/*
  This file is part of TALER
  Copyright (C) 2023, 2024 Taler Systems SA

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
 * @file taler-exchange-httpd_common_kyc.h
 * @brief shared logic for finishing a KYC process
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_COMMON_KYC_H
#define TALER_EXCHANGE_HTTPD_COMMON_KYC_H

#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd.h"


/**
 * Function called after a measure has been run.
 *
 * @param cls closure
 * @param ec error code or 0 on success
 * @param detail error message or NULL on success / no info
 */
typedef void
(*TEH_KycMeasureRunContextCallback) (
  void *cls,
  enum TALER_ErrorCode ec,
  const char *detail);


/**
 * Handle for an asynchronous operation to finish
 * a KYC process after running the AML trigger.
 */
struct TEH_KycMeasureRunContext;


/**
 * Store attributes from the given KYC provider.
 *
 * FIXME: Isn't the account_id redundant via the process_row?
 *
 * @param process_row legitimization process the data provided is about
 * @param account_id account the the data provided is about
 * @param provider_name name of the provider that provided the attributes
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param expiration until when is the KYC check valid
 * @param new_attributes user attributes returned by the provider
 * @return handle to cancel the operation
 */
enum GNUNET_DB_QueryStatus
TEH_kyc_store_attributes (
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *account_id,
  const char *provider_name,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Absolute expiration,
  const json_t *new_attributes);


/**
 * Run measure after storing attributes from the given
 * provider.
 *
 * Only works when a process is active.
 *
 * @param scope the HTTP request logging scope
 * @param process_row legitimization process the data provided is about
 * @param account_id account the the data provided is about
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel the operation
 */
// FIXME: function should probably be renamed...
struct TEH_KycMeasureRunContext *
TEH_kyc_run_measure_for_attributes (
  const struct GNUNET_AsyncScopeId *scope,
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *account_id,
  TEH_KycMeasureRunContextCallback cb,
  void *cb_cls);


/**
 * Run an measure directly.
 *
 * Inserts a legitimization process and measure
 * into the database before running the measure program.
 *
 * After running the measure program, the result is stored
 * in the DB.
 *
 * @param scope the HTTP request logging scope
 * @param instant_ms instant measure to run
 * @param account_id account affected by the measure
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel the operation
 */
struct TEH_KycMeasureRunContext *
TEH_kyc_run_measure_directly (
  const struct GNUNET_AsyncScopeId *scope,
  const struct TALER_KYCLOGIC_Measure *instant_ms,
  const struct TALER_NormalizedPaytoHashP *account_id,
  TEH_KycMeasureRunContextCallback cb,
  void *cb_cls);


/**
 * Cancel running KYC measure.
 *
 * @param[in] kat operation to abort
 */
void
TEH_kyc_run_measure_cancel (struct TEH_KycMeasureRunContext *kat);


/**
 * Handle for an asynchronous operation to run some
 * fallback measure.
 */
struct TEH_KycAmlFallback;


/**
 * Function called after the KYC-AML fallback
 * processing is done.
 *
 * @param cls closure
 * @param result true if fallback handling was OK
 * @param requirement_row row of
 *    new KYC requirement that was created, 0 for none
 */
typedef void
(*TEH_KycAmlFallbackCallback) (
  void *cls,
  bool result,
  uint64_t requirement_row);


/**
 * Activate fallback measure for the given account.
 *
 * @param scope the HTTP request logging scope
 * @param account_id account to activate fallback for
 * @param orig_requirement_row original requirement
 *    row that now triggered the fallback
 * @param fallback_measure fallback to activate
 * @param cb callback to call with result
 * @param cb_cls closure for @a cb
 * @return handle for fallback operation, NULL
 *    if @a fallback_measure is unknown
 */
struct TEH_KycAmlFallback *
TEH_kyc_fallback (
  const struct GNUNET_AsyncScopeId *scope,
  const struct TALER_NormalizedPaytoHashP *account_id,
  uint64_t orig_requirement_row,
  const char *fallback_measure,
  TEH_KycAmlFallbackCallback cb,
  void *cb_cls);


/**
 * Cancel fallback operation.
 *
 * @param[in] fb operation to cancel
 */
void
TEH_kyc_fallback_cancel (
  struct TEH_KycAmlFallback *fb);


/**
 * Update state of a legitmization process to 'finished'
 * (and failed, no attributes were obtained).
 *
 * @param process_row legitimization process the webhook was about
 * @param account_id account the webhook was about
 * @param provider_name name KYC provider with the logic that was run
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param error_message error message to log
 * @param ec error code to log
 * @return true if the error was handled successfully
 */
bool
TEH_kyc_failed (
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *account_id,
  const char *provider_name,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  const char *error_message,
  enum TALER_ErrorCode ec);


/**
 * Result from a legitimization check.
 */
struct TEH_LegitimizationCheckResult
{
  /**
   * KYC status for the account
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Last reserve public key of a wire transfer from
   * the account to the exchange.
   */
  union TALER_AccountPublicKeyP reserve_pub;

  /**
   * Smallest amount (over any timeframe) that may
   * require additional KYC checks (if @a kyc.ok).
   */
  struct TALER_Amount next_threshold;

  /**
   * When do the current KYC rules possibly expire.
   * Only valid if @a kyc.ok.
   */
  struct GNUNET_TIME_Timestamp expiration_date;

  /**
   * Response to return. Note that the response must
   * be queued or destroyed by the callee.  NULL
   * if the legitimization check was successful and the handler should return
   * a handler-specific result.
   */
  struct MHD_Response *response;

  /**
   * HTTP status code for @a response, or 0
   */
  unsigned int http_status;

  /**
   * True if @e reserve_pub is set.
   */
  bool have_reserve_pub;

  /**
   * Set to true if the merchant public key does not
   * match the public key we have on file for this
   * target account (and thus a new KYC AUTH is
   * required).
   */
  bool bad_kyc_auth;
};


/**
 * Function called with the result of a legitimization
 * check.
 *
 * @param cls closure
 * @param lcr legitimization check result
 */
typedef void
(*TEH_LegitimizationCheckCallback)(
  void *cls,
  const struct TEH_LegitimizationCheckResult *lcr);

/**
 * Handle for a legitimization check.
 */
struct TEH_LegitimizationCheckHandle;


/* FIXME: add another variation of this API with a
   NormalizedPayto payto_uri, as we currently 'fake'
   a full payto in 3 places related to wallets! */
/**
 * Do legitimization check.
 *
 * @param scope scope for logging
 * @param et type of event we are checking
 * @param payto_uri account we are checking for
 * @param h_payto hash of @a payto_uri
 * @param account_pub public key to enable for the
 *    KYC authorization, NULL if not known
 * @param ai callback to get amounts involved historically
 * @param ai_cls closure for @a ai
 * @param result_cb function to call with the result
 * @param result_cb_cls closure for @a result_cb
 * @return handle for the operation
 */
struct TEH_LegitimizationCheckHandle *
TEH_legitimization_check (
  const struct GNUNET_AsyncScopeId *scope,
  enum TALER_KYCLOGIC_KycTriggerEvent et,
  const struct TALER_FullPayto payto_uri,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const union TALER_AccountPublicKeyP *account_pub,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  TEH_LegitimizationCheckCallback result_cb,
  void *result_cb_cls);


/**
 * Do legitimization check and enforce that the current
 * public key associated with the account is the given
 * merchant public key.
 *
 * @param scope scope for logging
 * @param et type of event we are checking
 * @param payto_uri account we are checking for
 * @param h_payto hash of @a payto_uri
 * @param merchant_pub public key that must match the
 *    KYC authorization
 * @param ai callback to get amounts involved historically
 * @param ai_cls closure for @a ai
 * @param result_cb function to call with the result
 * @param result_cb_cls closure for @a result_cb
 * @return handle for the operation
 */
struct TEH_LegitimizationCheckHandle *
TEH_legitimization_check2 (
  const struct GNUNET_AsyncScopeId *scope,
  enum TALER_KYCLOGIC_KycTriggerEvent et,
  const struct TALER_FullPayto payto_uri,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  TEH_LegitimizationCheckCallback result_cb,
  void *result_cb_cls);


/**
 * Cancel legitimization check.
 *
 * @param[in] lch handle of the check to cancel
 */
void
TEH_legitimization_check_cancel (
  struct TEH_LegitimizationCheckHandle *lch);

#endif
