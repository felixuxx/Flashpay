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
 * @file pq/pq_composite_types.c
 * @brief helper functions for Taler-specific libpq (PostGres) interactions with composite types
 * @author Özgür Kesim
 */
#include "platform.h"
#include <gnunet/gnunet_common.h>
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_pq_lib.h>
#include "taler_pq_lib.h"
#include "pq_common.h"

Oid TALER_PQ_CompositeOIDs[TALER_PQ_CompositeMAX] = {0};

enum GNUNET_GenericReturnValue
TALER_PQ_load_oids_for_composite_types (
  struct GNUNET_PQ_Context *db)
{
  static char *names[] = {
    [TALER_PQ_CompositeAmount] = "taler_amount"
  };
  size_t num = sizeof(names) / sizeof(names[0]);

  GNUNET_static_assert (num == TALER_PQ_CompositeMAX);

  for (size_t i = 0; i < num; i++)
  {
    enum GNUNET_GenericReturnValue ret;
    enum TALER_PQ_CompositeType typ = i;
    ret = GNUNET_PQ_get_oid_by_name (db,
                                     names[i],
                                     &TALER_PQ_CompositeOIDs[typ]);
    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to load OID for type %s\n",
                  names[i]);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}
