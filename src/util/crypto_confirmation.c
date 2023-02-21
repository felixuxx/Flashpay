/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file util/crypto_confirmation.c
 * @brief confirmation computation
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include <gcrypt.h>


char *
TALER_build_pos_confirmation (const char *pos_key,
                              enum TALER_MerchantConfirmationAlgorithm pos_alg,
                              const struct TALER_Amount *total,
                              struct GNUNET_TIME_Timestamp ts)
{
  switch (pos_alg)
  {
  case TALER_MCA_NONE:
    return NULL;
  }
  GNUNET_break (0); // FIXME: not implemented
  return NULL;
}
