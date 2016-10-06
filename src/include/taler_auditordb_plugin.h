/*
  This file is part of TALER
  Copyright (C) 2014-2016 GNUnet e.V.

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
 * @file include/taler_auditordb_plugin.h
 * @brief Low-level (statement-level) database access for the auditor
 * @author Florian Dold
 * @author Christian Grothoff
 */
#ifndef TALER_AUDITORDB_PLUGIN_H
#define TALER_AUDITORDB_PLUGIN_H

#include <jansson.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_lib.h"


/**
 * Handle for one session with the database.
 */
struct TALER_AUDITORDB_Session;


/**
 * @brief The plugin API, returned from the plugin's "init" function.
 * The argument given to "init" is simply a configuration handle.
 */
struct TALER_AUDITORDB_Plugin
{

  /**
   * Closure for all callbacks.
   */
  void *cls;

  /**
   * Name of the library which generated this plugin.  Set by the
   * plugin loader.
   */
  char *library_name;

  /**
   * Get the thread-local database-handle.
   * Connect to the db if the connection does not exist yet.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param the database connection, or NULL on error
   */
  struct TALER_AUDITORDB_Session *
  (*get_session) (void *cls);


  /**
   * Drop the Taler tables.  This should only be used in testcases.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
   */
  int
  (*drop_tables) (void *cls);


  /**
   * Create the necessary tables if they are not present
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
   */
  int
  (*create_tables) (void *cls);


  /**
   * Start a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @return #GNUNET_OK on success
   */
  int
  (*start) (void *cls,
            struct TALER_AUDITORDB_Session *session);


  /**
   * Commit a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @return #GNUNET_OK on success, #GNUNET_NO if the transaction
   *         can be retried, #GNUNET_SYSERR on hard failures
   */
  int
  (*commit) (void *cls,
             struct TALER_AUDITORDB_Session *session);


  /**
   * Abort/rollback a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   */
  void
  (*rollback) (void *cls,
               struct TALER_AUDITORDB_Session *session);

  
  /**
   * Function called to perform "garbage collection" on the
   * database, expiring records we no longer require.
   *
   * @param cls closure
   * @return #GNUNET_OK on success,
   *         #GNUNET_SYSERR on DB errors
   */
  int
  (*gc) (void *cls);

};


#endif /* _TALER_AUDITOR_DB_H */
