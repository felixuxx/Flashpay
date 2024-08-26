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
 * @file bank-lib/fakebank_twg_get_root.c
 * @brief return the "/" page for the taler wire gateway
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_twg_get_root.h"


/**
 * Handle incoming HTTP request for "/" (home page).
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @return MHD result code
 */
MHD_RESULT
TALER_FAKEBANK_twg_get_root_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection)
{
  MHD_RESULT ret;
  struct MHD_Response *resp;
#define HELLOMSG "Hello, Fakebank (Taler Wire Gateway)!"

  (void) h;
  resp = MHD_create_response_from_buffer_static (
    strlen (HELLOMSG),
    HELLOMSG);
  ret = MHD_queue_response (connection,
                            MHD_HTTP_OK,
                            resp);
  MHD_destroy_response (resp);
  return ret;
}
