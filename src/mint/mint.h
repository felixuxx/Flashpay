/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file mint.h
 * @brief Common structs passed all over the mint logic
 * @author Florian Dold
 * @author Benedikt Mueller
 */
#ifndef _MINT_H
#define _MINT_H

#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_util.h"

/**
 * For now, we just do EUR.  Should become configurable
 * in the future!
 */
#define MINT_CURRENCY "EUR"


#endif /* _MINT_H */
