/*
  This file is part of TALER
  Copyright (C) 2015, 2016 Taler Systems SA

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
 * @file auditordb/auditordb_plugin.c
 * @brief Logic to load database plugin
 * @author Christian Grothoff
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include "taler_auditordb_plugin.h"
#include <ltdl.h>
#include "pg_helper.h"


const char *
TAH_PG_get_table_name (enum TALER_AUDITORDB_SuppressableTables table)
{
  const char *tables[] = {
    "auditor_amount_arithmetic_inconsistency",
    NULL,
  };

  if ( (table < 0) ||
       (table >= TALER_AUDITORDB_SUPPRESSABLE_TABLES_MAX))
  {
    GNUNET_break (0);
    return NULL;
  }
  return tables[table];
}
