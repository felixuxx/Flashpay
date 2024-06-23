/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */


#ifndef SRC_PG_UPDATE_PROGRESS_H
#define SRC_PG_UPDATE_PROGRESS_H

#include "taler_util.h"
#include "taler_auditordb_plugin.h"

enum GNUNET_DB_QueryStatus
TAH_PG_update_progress (
  void *cls,
  const struct TALER_AUDITORDB_Generic_Update *dc);

#endif // SRC_PG_UPDATE_PROGRESS_H
