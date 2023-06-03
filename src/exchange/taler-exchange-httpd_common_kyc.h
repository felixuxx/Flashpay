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

// FIXME: also pass async log context and set it!
/**
 * We have finished a KYC process and obtained new
 * @a attributes for a given @a account_id.
 * Check with the KYC-AML trigger to see if we need
 * to initiate an AML process, and store the attributes
 * in the database. Then call @a cb.
 *
 * @param scope the HTTP request logging scope
 * @param process_row legitimization process the webhook was about
 * @param account_id account the webhook was about
 * @param provider_section name of the configuration section of the logic that was run
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
TEH_kyc_finished (const struct GNUNET_AsyncScopeId *scope,
                  uint64_t process_row,
                  const struct TALER_PaytoHashP *account_id,
                  const char *provider_section,
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


#endif
