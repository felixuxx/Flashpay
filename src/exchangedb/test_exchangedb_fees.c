/*
  This file is part of TALER
  Copyright (C) 2017 Inria & GNUnet e. V.

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
 * @file exchangedb/test_exchangedb_fees.c
 * @brief test cases for functions in exchangedb/exchangedb_fees.c
 * @author Christian Grothoff
 */
#include "platform.h"
#include "gnunet/gnunet_util_lib.h"
#include "taler_signatures.h"
#include "taler_exchangedb_lib.h"


int
main (int argc,
      const char *const argv[])
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  int ret;

  ret = 1;
  GNUNET_log_setup ("test-exchangedb-fees",
                    "WARNING",
                    NULL);
  cfg = GNUNET_CONFIGURATION_create ();

  GNUNET_CONFIGURATION_set_value_string (cfg,
                                         "exchangedb",
                                         "AUDITOR_BASE_DIR",
                                         tmpdir);
  ret = 0;
  return ret;
}
