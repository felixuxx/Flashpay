/*
   This file is part of TALER
   Copyright (C) 2022- Taler Systems SA

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
 * @file age_restriction_helper.c
 * @brief Helper functions for age restriction
 * @author Özgür Kesim
 */

#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_extensions.h"
#include "stdint.h"


const struct TALER_AgeRestrictionConfig *
TALER_extensions_get_age_restriction_config ()
{
  const struct TALER_Extension *ext;

  ext = TALER_extensions_get_by_type (TALER_Extension_AgeRestriction);
  if (NULL == ext)
    return NULL;

  return ext->config;
}


bool
TALER_extensions_is_age_restriction_enabled ()
{
  const struct TALER_Extension *ext;

  ext = TALER_extensions_get_by_type (TALER_Extension_AgeRestriction);
  if (NULL == ext)
    return false;

  return ext->enabled;
}


struct TALER_AgeMask
TALER_extensions_get_age_restriction_mask ()
{
  const struct TALER_Extension *ext;
  const struct TALER_AgeRestrictionConfig *conf;

  ext = TALER_extensions_get_by_type (TALER_Extension_AgeRestriction);

  if ((NULL == ext) ||
      (NULL == ext->config))
    return (struct TALER_AgeMask) {0}
  ;

  conf = ext->config;
  return conf->mask;
}


/* end age_restriction_helper.c */
