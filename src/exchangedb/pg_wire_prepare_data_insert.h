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
 * @file exchangedb/pg_wire_prepare_data_insert.h
 * @brief implementation of the wire_prepare_data_insert function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_WIRE_PREPARE_DATA_INSERT_H
#define PG_WIRE_PREPARE_DATA_INSERT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to insert wire transfer commit data into the DB.
 *
 * @param cls closure
 * @param type type of the wire transfer (i.e. "iban")
 * @param buf buffer with wire transfer preparation data
 * @param buf_size number of bytes in @a buf
 * @return query status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_wire_prepare_data_insert (void *cls,
                                 const char *type,
                                 const char *buf,
                                 size_t buf_size);

#endif
