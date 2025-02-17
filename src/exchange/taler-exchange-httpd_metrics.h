/*
  This file is part of TALER
  Copyright (C) 2014--2021 Taler Systems SA

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
 * @file taler-exchange-httpd_metrics.h
 * @brief Handle /metrics requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_METRICS_H
#define TALER_EXCHANGE_HTTPD_METRICS_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Request types for which we collect metrics.
 */
enum TEH_MetricTypeRequest
{
  TEH_MT_REQUEST_OTHER = 0,
  TEH_MT_REQUEST_DEPOSIT = 1,
  TEH_MT_REQUEST_WITHDRAW = 2,
  TEH_MT_REQUEST_AGE_WITHDRAW = 3,
  TEH_MT_REQUEST_MELT = 4,
  TEH_MT_REQUEST_PURSE_CREATE = 5,
  TEH_MT_REQUEST_PURSE_MERGE = 6,
  TEH_MT_REQUEST_RESERVE_PURSE = 7,
  TEH_MT_REQUEST_PURSE_DEPOSIT = 8,
  TEH_MT_REQUEST_IDEMPOTENT_DEPOSIT = 9,
  TEH_MT_REQUEST_IDEMPOTENT_WITHDRAW = 10,
  TEH_MT_REQUEST_IDEMPOTENT_AGE_WITHDRAW = 11,
  TEH_MT_REQUEST_IDEMPOTENT_MELT = 12,
  TEH_MT_REQUEST_IDEMPOTENT_BATCH_WITHDRAW = 13,
  TEH_MT_REQUEST_BATCH_DEPOSIT = 14,
  TEH_MT_REQUEST_POLICY_FULFILLMENT = 15,
  TEH_MT_REQUEST_COUNT = 16 /* MUST BE LAST! */
};

/**
 * Success types for which we collect metrics.
 */
enum TEH_MetricTypeSuccess
{
  TEH_MT_SUCCESS_DEPOSIT = 0,
  TEH_MT_SUCCESS_WITHDRAW = 1,
  TEH_MT_SUCCESS_AGE_WITHDRAW = 2,
  TEH_MT_SUCCESS_BATCH_WITHDRAW = 3,
  TEH_MT_SUCCESS_MELT = 4,
  TEH_MT_SUCCESS_REFRESH_REVEAL = 5,
  TEH_MT_SUCCESS_AGE_WITHDRAW_REVEAL = 6,
  TEH_MT_SUCCESS_COUNT = 7 /* MUST BE LAST! */
};

/**
 * Cipher types for which we collect signature metrics.
 */
enum TEH_MetricTypeSignature
{
  TEH_MT_SIGNATURE_RSA = 0,
  TEH_MT_SIGNATURE_CS = 1,
  TEH_MT_SIGNATURE_EDDSA = 2,
  TEH_MT_SIGNATURE_COUNT = 3
};

/**
 * Cipher types for which we collect key exchange metrics.
 */
enum TEH_MetricTypeKeyX
{
  TEH_MT_KEYX_ECDH = 0,
  TEH_MT_KEYX_COUNT = 1
};

/**
 * Number of requests handled of the respective type.
 */
extern unsigned long long TEH_METRICS_num_requests[TEH_MT_REQUEST_COUNT];

/**
 * Number of successful requests handled of the respective type.
 */
extern unsigned long long TEH_METRICS_num_success[TEH_MT_SUCCESS_COUNT];

/**
 * Number of coins withdrawn in a batch-withdraw request
 */
extern unsigned long long TEH_METRICS_batch_withdraw_num_coins;

/**
 * Number of serialization errors encountered when
 * handling requests of the respective type.
 */
extern unsigned long long TEH_METRICS_num_conflict[TEH_MT_REQUEST_COUNT];

/**
 * Number of signatures created by the respective cipher.
 */
extern unsigned long long TEH_METRICS_num_signatures[TEH_MT_SIGNATURE_COUNT];

/**
 * Number of signatures verified by the respective cipher.
 */
extern unsigned long long TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_COUNT];

/**
 * Number of key exchanges done with the respective cipher.
 */
extern unsigned long long TEH_METRICS_num_keyexchanges[TEH_MT_KEYX_COUNT];

/**
 * Handle a "/metrics" request.
 *
 * @param rc request context
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_metrics (struct TEH_RequestContext *rc,
                     const char *const args[]);


#endif
