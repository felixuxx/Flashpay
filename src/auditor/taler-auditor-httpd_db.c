/*
  This file is part of TALER
  Copyright (C) 2014-2018 GNUnet e.V.

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
 * @file taler-auditor-httpd_db.c
 * @brief Generic database operations for the auditor.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <pthread.h>
#include <jansson.h>
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include "taler-auditor-httpd_db.h"
#include "taler-auditor-httpd_responses.h"


/**
 * How often should we retry a transaction before giving up
 * (for transactions resulting in serialization/dead locks only).
 */
#define MAX_TRANSACTION_COMMIT_RETRIES 100


/**
 * Run a database transaction for @a connection.
 * Starts a transaction and calls @a cb.  Upon success,
 * attempts to commit the transaction.  Upon soft failures,
 * retries @a cb a few times.  Upon hard or persistent soft
 * errors, generates an error message for @a connection.
 *
 * @param connection MHD connection to run @a cb for
 * @param name name of the transaction (for debugging)
 * @param[out] set to MHD response code, if transaction failed
 * @param cb callback implementing transaction logic
 * @param cb_cls closure for @a cb, must be read-only!
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
int
TAH_DB_run_transaction (struct MHD_Connection *connection,
                        const char *name,
                        int *mhd_ret,
                        TAH_DB_TransactionCallback cb,
                        void *cb_cls)
{
  struct TALER_AUDITORDB_Session *session;

  if (NULL != mhd_ret)
    *mhd_ret = -1; /* invalid value */
  if (NULL == (session = TAH_plugin->get_session (TAH_plugin->cls)))
  {
    GNUNET_break (0);
    if (NULL != mhd_ret)
      *mhd_ret = TAH_RESPONSE_reply_internal_db_error (connection,
                                                       TALER_EC_DB_SETUP_FAILED);
    return GNUNET_SYSERR;
  }
  //  TAH_plugin->preflight (TAH_plugin->cls, session); // FIXME: needed?
  for (unsigned int retries = 0; retries < MAX_TRANSACTION_COMMIT_RETRIES;
       retries++)
  {
    enum GNUNET_DB_QueryStatus qs;

    if (GNUNET_OK !=
        TAH_plugin->start (TAH_plugin->cls,
                           session))
    {
      GNUNET_break (0);
      if (NULL != mhd_ret)
        *mhd_ret = TAH_RESPONSE_reply_internal_db_error (connection,
                                                         TALER_EC_DB_START_FAILED);
      return GNUNET_SYSERR;
    }
    qs = cb (cb_cls,
             connection,
             session,
             mhd_ret);
    if (0 > qs)
      TAH_plugin->rollback (TAH_plugin->cls,
                            session);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      return GNUNET_SYSERR;
    if (0 <= qs)
      qs = TAH_plugin->commit (TAH_plugin->cls,
                               session);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      if (NULL != mhd_ret)
        *mhd_ret = TAH_RESPONSE_reply_commit_error (connection,
                                                    TALER_EC_DB_COMMIT_FAILED_HARD);
      return GNUNET_SYSERR;
    }
    /* make sure callback did not violate invariants! */
    GNUNET_assert ( (NULL == mhd_ret) ||
                    (-1 == *mhd_ret) );
    if (0 <= qs)
      return GNUNET_OK;
  }
  TALER_LOG_ERROR ("Transaction `%s' commit failed %u times\n",
                   name,
                   MAX_TRANSACTION_COMMIT_RETRIES);
  if (NULL != mhd_ret)
    *mhd_ret = TAH_RESPONSE_reply_commit_error (connection,
                                                TALER_EC_DB_COMMIT_FAILED_ON_RETRY);
  return GNUNET_SYSERR;
}


/* end of taler-auditor-httpd_db.c */
