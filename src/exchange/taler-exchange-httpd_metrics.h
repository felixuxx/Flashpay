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
enum TEH_MetricType
{
  TEH_MT_OTHER = 0,
  TEH_MT_DEPOSIT = 1,
  TEH_MT_WITHDRAW = 2,
  TEH_MT_MELT = 3,
  TEH_MT_REVEAL_PRECHECK = 4,
  TEH_MT_REVEAL = 5,
  TEH_MT_REVEAL_PERSIST = 6,
  TEH_MT_COUNT = 7 /* MUST BE LAST! */
};


/**
 * Number of requests handled of the respective type.
 */
extern unsigned long long TEH_METRICS_num_requests[TEH_MT_COUNT];

/**
 * Number of serialization errors encountered when
 * handling requests of the respective type.
 */
extern unsigned long long TEH_METRICS_num_conflict[TEH_MT_COUNT];


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
