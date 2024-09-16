/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file pg_delete_generic.h
 * @brief implementation of the delete_generic function
 * @author Nic Eigel
 */
#ifndef PG_DELETE_GENERIC_H
#define PG_DELETE_GENERIC_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"

/**
   // FIXME: add comments
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_delete_generic (
  void *cls,
  enum TALER_AUDITORDB_DeletableSuppressableTables table,
  uint64_t row_id);

#endif
