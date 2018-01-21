/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file exchange-lib/testing_api_traits.c
 * @brief loop for trait resolution
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"


struct TALER_TESTING_Trait
TALER_TESTING_trait_end ()
{
  struct TALER_TESTING_Trait end = {
    .selector = NULL,
    .trait_name = NULL,
    .ptr = NULL
  };

  return end;
}


int
TALER_TESTING_get_trait (const struct TALER_TESTING_Trait *traits,
                         void **ret,
                         const char *trait,
                         const char *selector)
{
  for (unsigned int i=0;
       NULL != traits[i].trait_name;
       i++)
  {
    if ( (0 == strcmp (trait,
                       traits[i].trait_name)) &&
         ( (NULL == selector) ||
           (0 == strcasecmp (selector,
                             traits[i].selector) ) ) )
    {
      *ret = (void *) traits[i].ptr;
      return GNUNET_OK;
    }
  }
  /* FIXME: log */
  return GNUNET_SYSERR;
}



/* end of testing_api_traits.c */
