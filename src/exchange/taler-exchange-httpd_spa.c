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
 * @file taler-exchange-httpd_spa.c
 * @brief logic to load single page apps (/)
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "taler-exchange-httpd.h"


/**
 * Resources of the AML SPA.
 */
static struct TALER_MHD_Spa *aml_spa;

/**
 * Resources of the KYC SPA.
 */
static struct TALER_MHD_Spa *kyc_spa;


MHD_RESULT
TEH_handler_aml_spa (struct TEH_RequestContext *rc,
                     const char *const args[])
{
  const char *path = args[0];
  struct TALER_AccountAccessTokenP tok;

  if (GNUNET_OK ==
      GNUNET_STRINGS_string_to_data (path,
                                     strlen (path),
                                     &tok,
                                     sizeof (tok)))
  {
    /* The access token is used internally by the SPA,
       we simply map all access tokens to "index.html" */
    path = "index.html";
  }
  return TALER_MHD_spa_handler (aml_spa,
                                rc->connection,
                                path);
}


MHD_RESULT
TEH_handler_kyc_spa (struct TEH_RequestContext *rc,
                     const char *const args[])
{
  const char *path = args[0];

  return TALER_MHD_spa_handler (kyc_spa,
                                rc->connection,
                                path);
}


enum GNUNET_GenericReturnValue
TEH_spa_init ()
{
  aml_spa = TALER_MHD_spa_load ("exchange/aml-spa/");
  if (NULL == aml_spa)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  kyc_spa = TALER_MHD_spa_load ("exchange/kyc-spa/");
  if (NULL == kyc_spa)
  {
    GNUNET_break (0);
    TALER_MHD_spa_free (aml_spa);
    aml_spa = NULL;
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Nicely shut down.
 */
void __attribute__ ((destructor))
get_spa_fini ()
{
  if (NULL != kyc_spa)
  {
    TALER_MHD_spa_free (kyc_spa);
    kyc_spa = NULL;
  }
  if (NULL != aml_spa)
  {
    TALER_MHD_spa_free (aml_spa);
    aml_spa = NULL;
  }
}
