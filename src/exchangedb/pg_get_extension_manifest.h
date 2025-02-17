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
 * @file exchangedb/pg_get_extension_manifest.h
 * @brief implementation of the get_extension_manifest function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_EXTENSION_MANIFEST_H
#define PG_GET_EXTENSION_MANIFEST_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to get the manifest of an extension
 * (age-restriction, policy_extension_...)
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param extension_name the name of the extension
 * @param[out] manifest JSON object of the manifest as string
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_extension_manifest (void *cls,
                               const char *extension_name,
                               char **manifest);

#endif
