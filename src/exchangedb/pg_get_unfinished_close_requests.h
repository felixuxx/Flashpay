/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */
/**
 * @file pg_get_unfinished_close_requests.h
 * @brief implementation of the get_unfinished_close_requests function
 * @author Christian Grothoff
 */
#ifndef PG_GET_UNFINISHED_CLOSE_REQUESTS_H
#define PG_GET_UNFINISHED_CLOSE_REQUESTS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Obtain information about force-closed reserves
 * where the close was not yet done (and their remaining
 * balances).  Updates the returned reserve's close
 * status to "done".
 *
 * @param cls closure of the plugin
 * @param rec function to call on expired reserves
 * @param rec_cls closure for @a rec
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_unfinished_close_requests (
  void *cls,
  TALER_EXCHANGEDB_ReserveExpiredCallback rec,
  void *rec_cls);

#endif
