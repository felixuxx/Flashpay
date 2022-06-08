/*
  This file is part of TALER
  Copyright (C) 2015-2021 Taler Systems SA

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
 * @file taler-exchange-httpd_metrics.c
 * @brief Handle /metrics requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_dbevents.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_metrics.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include <jansson.h>


unsigned long long TEH_METRICS_num_requests[TEH_MT_REQUEST_COUNT];

unsigned long long TEH_METRICS_batch_withdraw_num_coins;

unsigned long long TEH_METRICS_num_conflict[TEH_MT_REQUEST_COUNT];

unsigned long long TEH_METRICS_num_signatures[TEH_MT_SIGNATURE_COUNT];

unsigned long long TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_COUNT];

unsigned long long TEH_METRICS_num_keyexchanges[TEH_MT_KEYX_COUNT];

unsigned long long TEH_METRICS_num_success[TEH_MT_SUCCESS_COUNT];


MHD_RESULT
TEH_handler_metrics (struct TEH_RequestContext *rc,
                     const char *const args[])
{
  char *reply;
  struct MHD_Response *resp;
  MHD_RESULT ret;

  (void) args;
  GNUNET_asprintf (&reply,
                   "taler_exchange_success_transactions{type=\"%s\"} %llu\n"
                   "taler_exchange_success_transactions{type=\"%s\"} %llu\n"
                   "taler_exchange_success_transactions{type=\"%s\"} %llu\n"
                   "taler_exchange_success_transactions{type=\"%s\"} %llu\n"
                   "taler_exchange_success_transactions{type=\"%s\"} %llu\n"
                   "# HELP taler_exchange_serialization_failures "
                   " number of database serialization errors by type\n"
                   "# TYPE taler_exchange_serialization_failures counter\n"
                   "taler_exchange_serialization_failures{type=\"%s\"} %llu\n"
                   "taler_exchange_serialization_failures{type=\"%s\"} %llu\n"
                   "taler_exchange_serialization_failures{type=\"%s\"} %llu\n"
                   "taler_exchange_serialization_failures{type=\"%s\"} %llu\n"
                   "# HELP taler_exchange_received_requests "
                   " number of received requests by type\n"
                   "# TYPE taler_exchange_received_requests counter\n"
                   "taler_exchange_received_requests{type=\"%s\"} %llu\n"
                   "taler_exchange_received_requests{type=\"%s\"} %llu\n"
                   "taler_exchange_received_requests{type=\"%s\"} %llu\n"
                   "taler_exchange_received_requests{type=\"%s\"} %llu\n"
                   "taler_exchange_idempotent_requests{type=\"%s\"} %llu\n"
#if NOT_YET_IMPLEMENTED
                   "taler_exchange_idempotent_requests{type=\"%s\"} %llu\n"
                   "taler_exchange_idempotent_requests{type=\"%s\"} %llu\n"
#endif
                   "taler_exchange_idempotent_requests{type=\"%s\"} %llu\n"
                   "# HELP taler_exchange_num_signatures "
                   " number of signatures created by cipher\n"
                   "# TYPE taler_exchange_num_signatures counter\n"
                   "taler_exchange_num_signatures{type=\"%s\"} %llu\n"
                   "taler_exchange_num_signatures{type=\"%s\"} %llu\n"
                   "taler_exchange_num_signatures{type=\"%s\"} %llu\n"
                   "# HELP taler_exchange_num_signature_verifications "
                   " number of signatures verified by cipher\n"
                   "# TYPE taler_exchange_num_signature_verifications counter\n"
                   "taler_exchange_num_signature_verifications{type=\"%s\"} %llu\n"
                   "taler_exchange_num_signature_verifications{type=\"%s\"} %llu\n"
                   "taler_exchange_num_signature_verifications{type=\"%s\"} %llu\n"
                   "# HELP taler_exchange_num_keyexchanges "
                   " number of key exchanges done by cipher\n"
                   "# TYPE taler_exchange_num_keyexchanges counter\n"
                   "taler_exchange_num_keyexchanges{type=\"%s\"} %llu\n"
                   "# HELP taler_exchange_batch_withdraw_num_coins "
                   " number of coins withdrawn in a batch-withdraw request\n"
                   "# TYPE taler_exchange_batch_withdraw_num_coins counter\n"
                   "taler_exchange_batch_withdraw_num_coins{} %llu\n",
                   "deposit",
                   TEH_METRICS_num_success[TEH_MT_SUCCESS_DEPOSIT],
                   "withdraw",
                   TEH_METRICS_num_success[TEH_MT_SUCCESS_WITHDRAW],
                   "batch-withdraw",
                   TEH_METRICS_num_success[TEH_MT_SUCCESS_BATCH_WITHDRAW],
                   "melt",
                   TEH_METRICS_num_success[TEH_MT_SUCCESS_MELT],
                   "refresh-reveal",
                   TEH_METRICS_num_success[TEH_MT_SUCCESS_REFRESH_REVEAL],
                   "other",
                   TEH_METRICS_num_conflict[TEH_MT_REQUEST_OTHER],
                   "deposit",
                   TEH_METRICS_num_conflict[TEH_MT_REQUEST_DEPOSIT],
                   "withdraw",
                   TEH_METRICS_num_conflict[TEH_MT_REQUEST_WITHDRAW],
                   "melt",
                   TEH_METRICS_num_conflict[TEH_MT_REQUEST_MELT],
                   "other",
                   TEH_METRICS_num_requests[TEH_MT_REQUEST_OTHER],
                   "deposit",
                   TEH_METRICS_num_requests[TEH_MT_REQUEST_DEPOSIT],
                   "withdraw",
                   TEH_METRICS_num_requests[TEH_MT_REQUEST_WITHDRAW],
                   "melt",
                   TEH_METRICS_num_requests[TEH_MT_REQUEST_MELT],
                   "withdraw",
                   TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_WITHDRAW],
#if NOT_YET_IMPLEMENTED
                   "deposit",
                   TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_DEPOSIT],
                   "melt",
                   TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_MELT],
#endif
                   "batch-withdraw",
                   TEH_METRICS_num_requests[
                     TEH_MT_REQUEST_IDEMPOTENT_BATCH_WITHDRAW],
                   "rsa",
                   TEH_METRICS_num_signatures[TEH_MT_SIGNATURE_RSA],
                   "cs",
                   TEH_METRICS_num_signatures[TEH_MT_SIGNATURE_CS],
                   "eddsa",
                   TEH_METRICS_num_signatures[TEH_MT_SIGNATURE_EDDSA],
                   "rsa",
                   TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_RSA],
                   "cs",
                   TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_CS],
                   "eddsa",
                   TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA],
                   "ecdh",
                   TEH_METRICS_num_keyexchanges[TEH_MT_KEYX_ECDH],
                   TEH_METRICS_batch_withdraw_num_coins);
  resp = MHD_create_response_from_buffer (strlen (reply),
                                          reply,
                                          MHD_RESPMEM_MUST_FREE);
  ret = MHD_queue_response (rc->connection,
                            MHD_HTTP_OK,
                            resp);
  MHD_destroy_response (resp);
  return ret;
}


/* end of taler-exchange-httpd_metrics.c */
