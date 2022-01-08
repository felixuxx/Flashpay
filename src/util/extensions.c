/*
   This file is part of TALER
   Copyright (C) 2014-2021 Taler Systems SA

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
 * @file extensions.c
 * @brief Utility functions for extensions
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_extensions.h"
#include "stdint.h"

enum GNUNET_GenericReturnValue
TALER_extension_get_by_name (const char *name,
                             const struct TALER_Extension **extensions,
                             const struct TALER_Extension **ext)
{

  const struct TALER_Extension *it = *extensions;

  for (; NULL != it; it++)
  {
    if (0 == strncmp (name,
                      it->name,
                      strlen (it->name)))
    {
      *ext = it;
      return GNUNET_OK;
    }
  }

  return GNUNET_NO;
}


/* end of extensions.c */
