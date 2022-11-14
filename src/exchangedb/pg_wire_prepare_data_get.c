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
 * @file exchangedb/pg_wire_prepare_data_get.c
 * @brief Implementation of the wire_prepare_data_get function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_wire_prepare_data_get.h"
#include "pg_helper.h"

/**
 * Closure for #prewire_cb().
 */
struct PrewireContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_WirePreparationIterator cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * #GNUNET_OK if everything went fine.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Invoke the callback for each result.
 *
 * @param cls a `struct MissingWireContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
prewire_cb (void *cls,
            PGresult *result,
            unsigned int num_results)
{
  struct PrewireContext *pc = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    uint64_t prewire_uuid;
    char *wire_method;
    void *buf = NULL;
    size_t buf_size;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("prewire_uuid",
                                    &prewire_uuid),
      GNUNET_PQ_result_spec_string ("wire_method",
                                    &wire_method),
      GNUNET_PQ_result_spec_variable_size ("buf",
                                           &buf,
                                           &buf_size),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      pc->status = GNUNET_SYSERR;
      return;
    }
    pc->cb (pc->cb_cls,
            prewire_uuid,
            wire_method,
            buf,
            buf_size);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_wire_prepare_data_get (void *cls,
                                uint64_t start_row,
                                uint64_t limit,
                                TALER_EXCHANGEDB_WirePreparationIterator cb,
                                void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&start_row),
    GNUNET_PQ_query_param_uint64 (&limit),
    GNUNET_PQ_query_param_end
  };
  struct PrewireContext pc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;


      /* Used in #postgres_wire_prepare_data_get() */
  PREPARE (pg,
           "wire_prepare_data_get",
           "SELECT"
           " prewire_uuid"
           ",wire_method"
           ",buf"
           " FROM prewire"
           " WHERE prewire_uuid >= $1"
           "   AND finished=FALSE"
           "   AND failed=FALSE"
           " ORDER BY prewire_uuid ASC"
           " LIMIT $2;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "wire_prepare_data_get",
                                             params,
                                             &prewire_cb,
                                             &pc);
  if (GNUNET_OK != pc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
