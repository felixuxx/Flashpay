/*
  This file is part of TALER
  (C) 2016-2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file bank-lib/fakebank_common_parser.c
 * @brief functions to help parse REST requests
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"


enum GNUNET_GenericReturnValue
TALER_FAKEBANK_common_parse_history_args (
  const struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  struct HistoryArgs *ha)
{
  const char *start;
  const char *delta;
  const char *long_poll_ms;
  unsigned long long lp_timeout;
  unsigned long long sval;
  long long d;
  char dummy;

  start = MHD_lookup_connection_value (connection,
                                       MHD_GET_ARGUMENT_KIND,
                                       "start");
  ha->have_start = (NULL != start);
  delta = MHD_lookup_connection_value (connection,
                                       MHD_GET_ARGUMENT_KIND,
                                       "delta");
  long_poll_ms = MHD_lookup_connection_value (connection,
                                              MHD_GET_ARGUMENT_KIND,
                                              "long_poll_ms");
  lp_timeout = 0;
  if ( (NULL == delta) ||
       (1 != sscanf (delta,
                     "%lld%c",
                     &d,
                     &dummy)) )
  {
    /* Fail if one of the above failed.  */
    /* Invalid request, given that this is fakebank we impolitely
     * just kill the connection instead of returning a nice error.
     */
    GNUNET_break_op (0);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                        "delta"))
           ? GNUNET_NO
           : GNUNET_SYSERR;
  }
  if ( (NULL != long_poll_ms) &&
       (1 != sscanf (long_poll_ms,
                     "%llu%c",
                     &lp_timeout,
                     &dummy)) )
  {
    /* Fail if one of the above failed.  */
    /* Invalid request, given that this is fakebank we impolitely
     * just kill the connection instead of returning a nice error.
     */
    GNUNET_break_op (0);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                        "long_poll_ms"))
           ? GNUNET_NO
           : GNUNET_SYSERR;
  }
  if ( (NULL != start) &&
       (1 != sscanf (start,
                     "%llu%c",
                     &sval,
                     &dummy)) )
  {
    /* Fail if one of the above failed.  */
    /* Invalid request, given that this is fakebank we impolitely
     * just kill the connection instead of returning a nice error.
     */
    GNUNET_break_op (0);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                        "start"))
           ? GNUNET_NO
           : GNUNET_SYSERR;
  }
  if (NULL == start)
    ha->start_idx = (d > 0) ? 0 : h->serial_counter;
  else
    ha->start_idx = (uint64_t) sval;
  ha->delta = (int64_t) d;
  if (0 == ha->delta)
  {
    GNUNET_break_op (0);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                        "delta"))
           ? GNUNET_NO
           : GNUNET_SYSERR;
  }
  ha->lp_timeout
    = GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS,
                                     lp_timeout);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Request for %lld records from %llu\n",
              (long long) ha->delta,
              (unsigned long long) ha->start_idx);
  return GNUNET_OK;
}
