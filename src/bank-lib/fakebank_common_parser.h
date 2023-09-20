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
 * @file bank-lib/fakebank_common_parser.h
 * @brief functions to help parse REST requests
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_COMMON_PARSER_H
#define FAKEBANK_COMMON_PARSER_H

#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"

/**
 * Parse URL history arguments, of _both_ APIs:
 * /history/incoming and /history/outgoing.
 *
 * @param h bank handle to work on
 * @param connection MHD connection.
 * @param[out] ha will contain the parsed values.
 * @return #GNUNET_OK only if the parsing succeeds,
 *         #GNUNET_SYSERR if it failed,
 *         #GNUNET_NO if it failed and an error was returned
 */
enum GNUNET_GenericReturnValue
TALER_FAKEBANK_common_parse_history_args (
  const struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  struct HistoryArgs *ha);

#endif
