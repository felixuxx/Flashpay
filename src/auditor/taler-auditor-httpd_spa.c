/*
  This file is part of TALER
  Copyright (C) 2020, 2023, 2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of EXCHANGEABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-auditor-httpd_spa.c
 * @brief logic to load single page app (/spa)
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "taler-auditor-httpd_spa.h"


/**
 * Resources of the auditor SPA.
 */
static struct TALER_MHD_Spa *spa;


MHD_RESULT
TAH_spa_handler (
  /* const */ struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[])
{
  const char *path = args[1];

  GNUNET_assert (0 == strcmp (args[0],
                              "spa"));
  if (NULL == path)
    path = "index.html";
  return TALER_MHD_spa_handler (spa,
                                connection,
                                path);
}


enum GNUNET_GenericReturnValue
TAH_spa_init ()
{
  spa = TALER_MHD_spa_load ("auditor/spa/");
  if (NULL == spa)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Nicely shut down.
 */
void __attribute__ ((destructor))
get_spa_fini (void);

/* declaration to suppress compiler warning */
void __attribute__ ((destructor))
get_spa_fini ()
{
  if (NULL != spa)
  {
    TALER_MHD_spa_free (spa);
    spa = NULL;
  }
}
