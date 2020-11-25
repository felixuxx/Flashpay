/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_management_auditor_disable.c
 * @brief functions to disable an auditor
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_signatures.h"

/**
 * @brief Handle for a POST /management/auditors/disable request.
 */
struct TALER_EXCHANGE_ManagementAuditorDisableHandle
{

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_ManagementAuditorDisableCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Reference to the execution context.
   */
  struct GNUNET_CURL_Context *ctx;
};


/**
 * Inform the exchange that an auditor should be disabled.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param auditor_pub the public signing key of the auditor
 * @param auditor_url base URL of the auditor
 * @param validity_start when was this decided?
 * @param master_sig signature affirming the auditor addition
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementAuditorDisableHandle *
TALER_EXCHANGE_management_disable_auditor (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const char *auditor_url,
  struct GNUNET_TIME_Absolute validity_start,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementAuditorDisableCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_disable_auditor() operation.
 *
 * @param ah handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_disable_auditor_cancel (
  struct TALER_EXCHANGE_ManagementAuditorDisableHandle *ah)
{
  if (NULL != ah->job)
  {
    GNUNET_CURL_job_cancel (ah->job);
    ah->job = NULL;
  }
  GNUNET_free (ah->url);
  GNUNET_free (ah);
}
