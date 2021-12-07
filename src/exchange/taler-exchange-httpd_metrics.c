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


unsigned long long TEH_METRICS_num_requests[TEH_MT_COUNT];

unsigned long long TEH_METRICS_num_conflict[TEH_MT_COUNT];


MHD_RESULT
TEH_handler_metrics (struct TEH_RequestContext *rc,
                     const char *const args[])
{
  char *reply;
  struct MHD_Response *resp;
  MHD_RESULT ret;

  (void) args;
  GNUNET_asprintf (&reply,
                   "received_requests(type='%s') %llu\n"
                   "serialization_failures(type='%s') %llu\n"
                   "received_requests(type='%s') %llu\n"
                   "serialization_failures(type='%s') %llu\n"
                   "received_requests(type='%s') %llu\n"
                   "serialization_failures(type='%s') %llu\n"
                   "received_requests(type='%s') %llu\n"
                   "serialization_failures(type='%s') %llu\n"
                   "received_requests(type='%s') %llu\n"
                   "serialization_failures(type='%s') %llu\n"
                   "received_requests(type='%s') %llu\n"
                   "serialization_failures(type='%s') %llu\n"
                   "received_requests(type='%s') %llu\n"
                   "serialization_failures(type='%s') %llu\n",
                   "other",
                   TEH_METRICS_num_requests[TEH_MT_OTHER],
                   "other",
                   TEH_METRICS_num_conflict[TEH_MT_OTHER],
                   "deposit",
                   TEH_METRICS_num_requests[TEH_MT_DEPOSIT],
                   "deposit",
                   TEH_METRICS_num_conflict[TEH_MT_DEPOSIT],
                   "withdraw",
                   TEH_METRICS_num_requests[TEH_MT_WITHDRAW],
                   "withdraw",
                   TEH_METRICS_num_conflict[TEH_MT_WITHDRAW],
                   "melt",
                   TEH_METRICS_num_requests[TEH_MT_MELT],
                   "melt",
                   TEH_METRICS_num_conflict[TEH_MT_MELT],
                   "reveal-precheck",
                   TEH_METRICS_num_requests[TEH_MT_REVEAL_PRECHECK],
                   "reveal-precheck",
                   TEH_METRICS_num_conflict[TEH_MT_REVEAL_PRECHECK],
                   "reveal",
                   TEH_METRICS_num_requests[TEH_MT_REVEAL],
                   "reveal",
                   TEH_METRICS_num_conflict[TEH_MT_REVEAL],
                   "reveal-persist",
                   TEH_METRICS_num_requests[TEH_MT_REVEAL_PERSIST],
                   "reveal-persist",
                   TEH_METRICS_num_conflict[TEH_MT_REVEAL_PERSIST]);
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
