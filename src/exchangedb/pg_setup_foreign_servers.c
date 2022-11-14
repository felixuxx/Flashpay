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
 * @file exchangedb/pg_setup_foreign_servers.c
 * @brief Implementation of the setup_foreign_servers function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_setup_foreign_servers.h"
#include "pg_helper.h"



enum GNUNET_GenericReturnValue
TEH_PG_setup_foreign_servers (void *cls,
                                uint32_t num)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret = GNUNET_OK;
  char *shard_domain = NULL;
  char *remote_user = NULL;
  char *remote_user_pw = NULL;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (pg->cfg,
                                             "exchange",
                                             "SHARD_DOMAIN",
                                             &shard_domain))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "SHARD_DOMAIN");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (pg->cfg,
                                             "exchangedb-postgres",
                                             "SHARD_REMOTE_USER",
                                             &remote_user))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb-postgres",
                               "SHARD_REMOTE_USER");
    GNUNET_free (shard_domain);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (pg->cfg,
                                             "exchangedb-postgres",
                                             "SHARD_REMOTE_USER_PW",
                                             &remote_user_pw))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb-postgres",
                               "SHARD_REMOTE_USER_PW");
    GNUNET_free (shard_domain);
    GNUNET_free (remote_user);
    return GNUNET_SYSERR;
  }

  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint32 (&num),
    GNUNET_PQ_query_param_string (shard_domain),
    GNUNET_PQ_query_param_string (remote_user),
    GNUNET_PQ_query_param_string (remote_user_pw),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };
  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare ("create_foreign_servers",
                            "SELECT"
                            " create_foreign_servers"
                            " ($1, $2, $3, $4);"),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     NULL,
                                     es,
                                     ps);
  if (NULL == conn)
  {
    ret = GNUNET_SYSERR;
  }
  else if (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                                   "create_foreign_servers",
                                                   params))
  {
    ret = GNUNET_SYSERR;
  }
  GNUNET_free (shard_domain);
  GNUNET_free (remote_user);
  GNUNET_free (remote_user_pw);
  GNUNET_PQ_disconnect (conn);
  return ret;
}

