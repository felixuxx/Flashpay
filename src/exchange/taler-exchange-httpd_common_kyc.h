/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * Function called after the KYC-AML trigger is done.
 *
 * @param cls closure
 * @param http_status final HTTP status to return
 * @param[in] response final HTTP ro return
 */
typedef void
(*TEH_KycAmlTriggerCallback) (
  void *cls,
  unsigned int http_status,
  struct MHD_Response *response);


/**
 * Handle for an asynchronous operation to finish
 * a KYC process after running the AML trigger.
 */
struct TEH_KycAmlTrigger;


/**
 * We have finished a KYC process and obtained new
 * @a attributes for a given @a account_id.
 * Check with the KYC-AML trigger to see if we need
 * to initiate an AML process, and store the attributes
 * in the database. Then call @a cb.
 *
 * @param scope the HTTP request logging scope
 * @param process_row legitimization process the data provided is about
 * @param account_id account the webhook was about
 * @param provider_name name of the provider with the logic that was run
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param expiration until when is the KYC check valid
 * @param attributes user attributes returned by the provider
 * @param http_status HTTP status code of @a response
 * @param[in] response to return to the HTTP client
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel the operation
 */
struct TEH_KycAmlTrigger *
TEH_kyc_finished (
  const struct GNUNET_AsyncScopeId *scope,
  uint64_t process_row,
  const struct TALER_PaytoHashP *account_id,
  const char *provider_name,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Absolute expiration,
  const json_t *attributes,
  unsigned int http_status,
  struct MHD_Response *response,
  TEH_KycAmlTriggerCallback cb,
  void *cb_cls);


/**
 * Cancel KYC finish operation.
 *
 * @param[in] kat operation to abort
 */
void
TEH_kyc_finished_cancel (struct TEH_KycAmlTrigger *kat);


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
 * @param attributes attributes to run with
 * @param aml_history AML history of the account
 * @param kyc_history KYC history of the account
 * @param fallback_measure fallback to activate
 * @param cb callback to call with result
 * @param cb_cls closure for @a cb
 * @return handle for fallback operation, NULL
 *    if @a fallback_measure is unknown
 */
struct TEH_KycAmlFallback *
TEH_kyc_fallback (
  const struct GNUNET_AsyncScopeId *scope,
  const struct TALER_PaytoHashP *
  account_id,
  uint64_t orig_requirement_row,
  const json_t *attributes,
  const json_t *aml_history,
  const json_t *kyc_history,
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
  const struct TALER_PaytoHashP *account_id,
  const char *provider_name,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  const char *error_message,
  enum TALER_ErrorCode ec);

#endif
