/*
  This file is part of TALER
  Copyright (C) 2014-2018 GNUnet e.V.

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
 * @file exchange-lib/backoff.h
 * @brief backoff computation for the exchange lib
 * @author Florian Dold
 */


#ifndef _TALER_BACKOFF_H
#define _TALER_BACKOFF_H

#include "platform.h"
#include <gnunet/gnunet_time_lib.h>

/**
 * Random exponential backoff used in the exchange lib.
 */
#define EXCHANGE_LIB_BACKOFF(r) GNUNET_TIME_randomized_backoff ( \
    (r), \
    GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_SECONDS, 2));

#endif
