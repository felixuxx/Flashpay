/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file exchange-tools/taler-exchange-dbinit.c
 * @brief Create tables for the exchange database.
 * @author Florian Dold
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_exchangedb_lib.h"


/**
 * Return value from main().
 */
static int global_ret;

/**
 * -r option: do full DB reset
 */
static int reset_db;

/**
 * -s option: clear revolving shard locks
 */
static int clear_shards;

/**
 * -g option: garbage collect DB reset
 */
static int gc_db;

/**
 * -P option: setup a partitioned database
 */
static uint32_t num_partitions;

/**
 * -F option: setup a sharded database, i.e. create foreign tables/server
 */
static int shard_db;

/**
 * -f option: force partitions to be created when there is only one
 */
static int force_create_partitions;

/**
 * -S option: setup a database on a shard server, creates tables with suffix shard_idx
 */
static uint32_t shard_idx;

/**
 * Main function that will be run.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct TALER_EXCHANGEDB_Plugin *plugin;

  (void) cls;
  (void) args;
  (void) cfgfile;
  if (NULL ==
      (plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize database plugin.\n");
    global_ret = EXIT_NOTINSTALLED;
    return;
  }
  if (reset_db)
  {
    if (GNUNET_OK !=
        plugin->drop_tables (plugin->cls))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Could not drop tables as requested. Either database was not yet initialized, or permission denied. Consult the logs. Will still try to create new tables.\n");
    }
  }
  if (0 < shard_idx)
  {
    if (GNUNET_OK !=
        plugin->create_shard_tables (plugin->cls,
                                     shard_idx))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Could not create shard database\n");
      global_ret = EXIT_NOTINSTALLED;
    }
    /* We do not want to continue if we are on a shard */
    TALER_EXCHANGEDB_plugin_unload (plugin);
    plugin = NULL;
    return;
  }
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls))
  {
    fprintf (stderr,
             "Failed to initialize database.\n");
    TALER_EXCHANGEDB_plugin_unload (plugin);
    plugin = NULL;
    global_ret = EXIT_NOPERMISSION;
    return;
  }
  if (1 <
      num_partitions
      || (
        1 == num_partitions
        && force_create_partitions))
  {
    enum GNUNET_GenericReturnValue r = GNUNET_OK;
    if (shard_db)
    {
      r = plugin->setup_foreign_servers (plugin->cls,
                                         num_partitions);
    }
    else
    {
      r = plugin->setup_partitions (plugin->cls,
                                    num_partitions);
    }
    if (GNUNET_OK != r)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Could not setup partitions. Dropping default ones again\n");
      if (GNUNET_OK != plugin->drop_tables (plugin->cls))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Could not drop tables after failed partitioning, please delete the DB manually\n");
      }
      TALER_EXCHANGEDB_plugin_unload (plugin);
      plugin = NULL;
      global_ret = EXIT_NOTINSTALLED;
      return;
    }
  }
  if (gc_db || clear_shards)
  {
    if (GNUNET_OK !=
        plugin->preflight (plugin->cls))
    {
      fprintf (stderr,
               "Failed to prepare database.\n");
      TALER_EXCHANGEDB_plugin_unload (plugin);
      plugin = NULL;
      global_ret = EXIT_NOPERMISSION;
      return;
    }
    if (clear_shards)
    {
      if (0 >
          plugin->delete_shard_locks (plugin->cls))
      {
        fprintf (stderr,
                 "Clearing revolving shards failed!\n");
      }
    }
    if (gc_db)
    {
      if (GNUNET_SYSERR == plugin->gc (plugin->cls))
      {
        fprintf (stderr,
                 "Garbage collection failed!\n");
      }
    }
  }
  TALER_EXCHANGEDB_plugin_unload (plugin);
  plugin = NULL;
}


/**
 * The main function of the database initialization tool.
 * Used to initialize the Taler Exchange's database.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, non-zero on error
 */
int
main (int argc,
      char *const *argv)
{
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_flag ('g',
                               "gc",
                               "garbage collect database",
                               &gc_db),
    GNUNET_GETOPT_option_flag ('r',
                               "reset",
                               "reset database (DANGEROUS: all existing data is lost!)",
                               &reset_db),
    GNUNET_GETOPT_option_flag ('s',
                               "shardunlock",
                               "unlock all revolving shard locks (use after system crash or shard size change while services are not running)",
                               &clear_shards),
    GNUNET_GETOPT_option_uint ('P',
                               "partition",
                               "NUMBER",
                               "Setup a partitioned database where each table which can be partitioned holds NUMBER partitions on a single DB node (NOTE: sharding add -F for sharding)",
                               &num_partitions),
    GNUNET_GETOPT_option_flag ('F',
                               "foreign",
                               "Setup a sharded database with foreign servers (shards) / tables rather than a partitioned one, must be called as DB superuser.",
                               &shard_db),
    GNUNET_GETOPT_option_uint ('S',
                               "shard",
                               "INDEX",
                               "Setup a shard server, creates tables with INDEX as suffix",
                               &shard_idx),
    GNUNET_GETOPT_option_flag ('f',
                               "force",
                               "Force partitions to be created if there is only one partition",
                               &force_create_partitions),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return EXIT_INVALIDARGUMENT;
  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-exchange-dbinit",
    gettext_noop ("Initialize Taler exchange database"),
    options,
    &run, NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-dbinit.c */
