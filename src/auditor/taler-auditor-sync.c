/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file taler-auditor-sync.c
 * @brief Tool used by the auditor to make a 'safe' copy of the exchanges' database.
 * @author Christian Grothoff
 */
#include <platform.h>
#include "taler_exchangedb_lib.h"


/**
 * Handle to access the exchange's source database.
 */
static struct TALER_EXCHANGEDB_Plugin *src;

/**
 * Handle to access the exchange's destination database.
 */
static struct TALER_EXCHANGEDB_Plugin *dst;

/**
 * Return value from #main().
 */
static int global_ret;

/**
 * Main task to do synchronization.
 */
static struct GNUNET_SCHEDULER_Task *sync_task;

/**
 * What is our target transaction size (number of records)?
 */
static unsigned int transaction_size = 512;

/**
 * Number of records copied in this transaction.
 */
static unsigned long long actual_size;

/**
 * Terminate once synchronization is achieved.
 */
static int exit_if_synced;


/**
 * Information we track per replicated table.
 */
struct Table
{
  /**
   * Which table is this record about?
   */
  enum TALER_EXCHANGEDB_ReplicatedTable rt;

  /**
   * Up to which record is the destination table synchronized.
   */
  uint64_t start_serial;

  /**
   * Highest serial in the source table.
   */
  uint64_t end_serial;

  /**
   * Marker for the end of the list of #tables.
   */
  bool end;
};


/**
 * Information about replicated tables.
 */
static struct Table tables[] = {
  { .rt = TALER_EXCHANGEDB_RT_DENOMINATIONS},
  { .rt = TALER_EXCHANGEDB_RT_DENOMINATION_REVOCATIONS},
  { .rt = TALER_EXCHANGEDB_RT_RESERVES},
  { .rt = TALER_EXCHANGEDB_RT_RESERVES_IN},
  { .rt = TALER_EXCHANGEDB_RT_RESERVES_CLOSE},
  { .rt = TALER_EXCHANGEDB_RT_RESERVES_OUT},
  { .rt = TALER_EXCHANGEDB_RT_AUDITORS},
  { .rt = TALER_EXCHANGEDB_RT_AUDITOR_DENOM_SIGS},
  { .rt = TALER_EXCHANGEDB_RT_EXCHANGE_SIGN_KEYS},
  { .rt = TALER_EXCHANGEDB_RT_SIGNKEY_REVOCATIONS},
  { .rt = TALER_EXCHANGEDB_RT_KNOWN_COINS},
  { .rt = TALER_EXCHANGEDB_RT_REFRESH_COMMITMENTS},
  { .rt = TALER_EXCHANGEDB_RT_REFRESH_REVEALED_COINS},
  { .rt = TALER_EXCHANGEDB_RT_REFRESH_TRANSFER_KEYS},
  { .rt = TALER_EXCHANGEDB_RT_DEPOSITS},
  { .rt = TALER_EXCHANGEDB_RT_REFUNDS},
  { .rt = TALER_EXCHANGEDB_RT_WIRE_OUT},
  { .rt = TALER_EXCHANGEDB_RT_AGGREGATION_TRACKING},
  { .rt = TALER_EXCHANGEDB_RT_WIRE_FEE},
  { .rt = TALER_EXCHANGEDB_RT_RECOUP},
  { .rt = TALER_EXCHANGEDB_RT_RECOUP_REFRESH },
  { .end = true }
};


/**
 * Closure for #do_insert.
 */
struct InsertContext
{
  /**
   * Database session to use.
   */
  struct TALER_EXCHANGEDB_Session *ds;

  /**
   * Table we are replicating.
   */
  struct Table *table;

  /**
   * Set to error if insertion created an error.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Function called on data to replicate in the auditor's database.
 *
 * @param cls closure, a `struct InsertContext`
 * @param td record from an exchange table
 * @return #GNUNET_OK to continue to iterate,
 *         #GNUNET_SYSERR to fail with an error
 */
static int
do_insert (void *cls,
           const struct TALER_EXCHANGEDB_TableData *td)
{
  struct InsertContext *ctx = cls;
  enum GNUNET_DB_QueryStatus qs;

  if (0 >= ctx->qs)
    return GNUNET_SYSERR;
  qs = dst->insert_records_by_table (dst->cls,
                                     ctx->ds,
                                     td);
  if (0 >= qs)
  {
    switch (qs)
    {
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      GNUNET_assert (0);
      break;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to insert record into table %d: no change\n",
                  td->table);
      break;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Serialization error inserting record into table %d (will retry)\n",
                  td->table);
      break;
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to insert record into table %d: hard error\n",
                  td->table);
      break;
    }
    ctx->qs = qs;
    return GNUNET_SYSERR;
  }
  actual_size++;
  ctx->table->start_serial = td->serial;
  return GNUNET_OK;
}


/**
 * Run one replication transaction.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR to rollback
 */
static int
transact (struct TALER_EXCHANGEDB_Session *ss,
          struct TALER_EXCHANGEDB_Session *ds)
{
  struct InsertContext ctx = {
    .ds = ds,
    .qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
  };

  if (0 >
      src->start (src->cls,
                  ss,
                  "lookup src serials"))
    return GNUNET_SYSERR;
  for (unsigned int i = 0; ! tables[i].end; i++)
    src->lookup_serial_by_table (src->cls,
                                 ss,
                                 tables[i].rt,
                                 &tables[i].end_serial);
  if (0 >
      src->commit (src->cls,
                   ss))
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      dst->start (src->cls,
                  ds,
                  "lookup dst serials"))
    return GNUNET_SYSERR;
  for (unsigned int i = 0; ! tables[i].end; i++)
    dst->lookup_serial_by_table (dst->cls,
                                 ds,
                                 tables[i].rt,
                                 &tables[i].start_serial);
  if (0 >
      dst->commit (dst->cls,
                   ds))
    return GNUNET_SYSERR;
  for (unsigned int i = 0; ! tables[i].end; i++)
  {
    struct Table *table = &tables[i];

    if (table->start_serial == table->end_serial)
      continue;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Replicating table %d from %llu to %llu\n",
                i,
                (unsigned long long) table->start_serial,
                (unsigned long long) table->end_serial);
    ctx.table = table;
    while (table->start_serial < table->end_serial)
    {
      enum GNUNET_DB_QueryStatus qs;

      if (GNUNET_OK !=
          src->start (src->cls,
                      ss,
                      "copy table (src)"))
        return GNUNET_SYSERR;
      if (GNUNET_OK !=
          dst->start (dst->cls,
                      ds,
                      "copy table (dst)"))
        return GNUNET_SYSERR;
      qs = src->lookup_records_by_table (src->cls,
                                         ss,
                                         table->rt,
                                         table->start_serial,
                                         &do_insert,
                                         &ctx);
      if (ctx.qs < 0)
        qs = ctx.qs;
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Failed to lookup records from table %d: hard error\n",
                    i);
        global_ret = 3;
        return GNUNET_SYSERR;
      }
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Serialization error looking up records from table %d (will retry)\n",
                    i);
        return GNUNET_SYSERR; /* will retry */
      }
      if (0 == qs)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Failed to lookup records from table %d: no results\n",
                    i);
        GNUNET_break (0); /* should be impossible */
        global_ret = 4;
        return GNUNET_SYSERR;
      }
      if (0 == ctx.qs)
        return GNUNET_SYSERR; /* insertion failed, maybe record existed? try again */
      src->rollback (src->cls,
                     ss);
      qs = dst->commit (dst->cls,
                        ds);
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Serialization error committing transaction on table %d (will retry)\n",
                    i);
        continue;
      }
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Hard error committing transaction on table %d\n",
                    i);
        global_ret = 5;
        return GNUNET_SYSERR;
      }
    }
  }
  /* we do not care about conflicting UPDATEs to src table, so safe to just rollback */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Sync pass completed successfully with %llu updates\n",
              actual_size);
  return GNUNET_OK;
}


/**
 * Task to do the actual synchronization work.
 *
 * @param cls NULL, unused
 */
static void
do_sync (void *cls)
{
  struct GNUNET_TIME_Relative delay;
  struct TALER_EXCHANGEDB_Session *ss;
  struct TALER_EXCHANGEDB_Session *ds;

  sync_task = NULL;
  actual_size = 0;
  ss = src->get_session (src->cls);
  if (NULL == ss)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to begin transaction with data source. Exiting\n");
    return;
  }
  ds = dst->get_session (dst->cls);
  if (NULL == ds)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to begin transaction with data destination. Exiting\n");
    return;
  }
  if (GNUNET_OK !=
      transact (ss,
                ds))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Transaction failed, rolling back\n");
    src->rollback (src->cls,
                   ss);
    dst->rollback (dst->cls,
                   ds);
  }
  if (0 != global_ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Transaction failed permanently, exiting\n");
    return;
  }
  if ( (0 == actual_size) &&
       (exit_if_synced) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Databases are synchronized. Exiting\n");
    return;
  }
  if (actual_size < transaction_size / 2)
  {
    delay = GNUNET_TIME_STD_BACKOFF (delay);
  }
  else if (actual_size >= transaction_size)
  {
    delay = GNUNET_TIME_UNIT_ZERO;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Next sync pass in %s\n",
              GNUNET_STRINGS_relative_time_to_string (delay,
                                                      GNUNET_YES));
  sync_task = GNUNET_SCHEDULER_add_delayed (delay,
                                            &do_sync,
                                            NULL);
}


/**
 * Set an option of type 'char *' from the command line with
 * filename expansion a la #GNUNET_STRINGS_filename_expand().
 *
 * @param ctx command line processing context
 * @param scls additional closure (will point to the `char *`,
 *             which will be allocated)
 * @param option name of the option
 * @param value actual value of the option (a string)
 * @return #GNUNET_OK
 */
static int
set_filename (struct GNUNET_GETOPT_CommandLineProcessorContext *ctx,
              void *scls,
              const char *option,
              const char *value)
{
  char **val = scls;

  (void) ctx;
  (void) option;
  GNUNET_assert (NULL != value);
  GNUNET_free (*val);
  *val = GNUNET_STRINGS_filename_expand (value);
  return GNUNET_OK;
}


/**
 * Allow user to specify configuration file name (-s option)
 *
 * @param[out] fn set to the name of the configuration file
 */
static struct GNUNET_GETOPT_CommandLineOption
option_cfgfile_src (char **fn)
{
  struct GNUNET_GETOPT_CommandLineOption clo = {
    .shortName = 's',
    .name = "source-configuration",
    .argumentHelp = "FILENAME",
    .description = gettext_noop (
      "use configuration file FILENAME for the SOURCE database"),
    .require_argument = 1,
    .processor = &set_filename,
    .scls = (void *) fn
  };

  return clo;
}


/**
 * Allow user to specify configuration file name (-d option)
 *
 * @param[out] fn set to the name of the configuration file
 */
static struct GNUNET_GETOPT_CommandLineOption
option_cfgfile_dst (char **fn)
{
  struct GNUNET_GETOPT_CommandLineOption clo = {
    .shortName = 'd',
    .name = "destination-configuration",
    .argumentHelp = "FILENAME",
    .description = gettext_noop (
      "use configuration file FILENAME for the DESTINATION database"),
    .require_argument = 1,
    .processor = &set_filename,
    .scls = (void *) fn
  };

  return clo;
}


static struct GNUNET_CONFIGURATION_Handle *
load_config (const char *cfgfile)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;

  cfg = GNUNET_CONFIGURATION_create ();
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Loading config file: %s\n",
              cfgfile);
  if (GNUNET_SYSERR ==
      GNUNET_CONFIGURATION_load (cfg,
                                 cfgfile))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Malformed configuration file `%s', exit ...\n",
                cfgfile);
    GNUNET_CONFIGURATION_destroy (cfg);
    return NULL;
  }
  return cfg;
}


/**
 * Shutdown task.
 *
 * @param cls NULL, unused
 */
static void
do_shutdown (void *cls)
{
  if (NULL != sync_task)
  {
    GNUNET_SCHEDULER_cancel (sync_task);
    sync_task = NULL;
  }
}


/**
 * Initial task.
 *
 * @param cls NULL, unused
 */
static void
run (void *cls)
{
  (void) cls;

  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  sync_task = GNUNET_SCHEDULER_add_now (&do_sync,
                                        NULL);
}


/**
 * Setup plugins in #src and #dst and #run() the main
 * logic with those plugins.
 */
static void
setup (struct GNUNET_CONFIGURATION_Handle *src_cfg,
       struct GNUNET_CONFIGURATION_Handle *dst_cfg)
{
  src = TALER_EXCHANGEDB_plugin_load (src_cfg);
  if (NULL == src)
  {
    global_ret = 3;
    return;
  }
  dst = TALER_EXCHANGEDB_plugin_load (dst_cfg);
  if (NULL == dst)
  {
    global_ret = 3;
    TALER_EXCHANGEDB_plugin_unload (src);
    src = NULL;
    return;
  }
  GNUNET_SCHEDULER_run (&run,
                        NULL);
  TALER_EXCHANGEDB_plugin_unload (src);
  src = NULL;
  TALER_EXCHANGEDB_plugin_unload (dst);
  dst = NULL;
}


/**
 * The main function of the taler-auditor-exchange tool.  This tool is used
 * to add (or remove) an exchange's master key and base URL to the auditor's
 * database.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, non-zero on error
 */
int
main (int argc,
      char *const *argv)
{
  char *src_cfgfile = NULL;
  char *dst_cfgfile = NULL;
  char *level = GNUNET_strdup ("WARNING");
  struct GNUNET_CONFIGURATION_Handle *src_cfg;
  struct GNUNET_CONFIGURATION_Handle *dst_cfg;
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_mandatory (
      option_cfgfile_src (&src_cfgfile)),
    GNUNET_GETOPT_option_mandatory (
      option_cfgfile_dst (&dst_cfgfile)),
    GNUNET_GETOPT_option_help (
      gettext_noop ("Make a safe copy of an exchange database")),
    GNUNET_GETOPT_option_uint (
      'b',
      "batch",
      "SIZE",
      gettext_noop (
        "target SIZE for a the number of records to copy in one transaction"),
      &transaction_size),
    GNUNET_GETOPT_option_flag (
      't',
      "terminate-when-synchronized",
      gettext_noop (
        "terminate as soon as the databases are synchronized"),
      &exit_if_synced),
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_option_loglevel (&level),
    GNUNET_GETOPT_OPTION_END
  };

  TALER_gcrypt_init (); /* must trigger initialization manually at this point! */
  {
    int ret;

    ret = GNUNET_GETOPT_run ("taler-auditor-sync",
                             options,
                             argc, argv);
    if (GNUNET_NO == ret)
      return 0;
    if (GNUNET_SYSERR == ret)
      return 1;
  }
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-auditor-sync",
                                   level,
                                   NULL));
  GNUNET_free (level);
  if (0 == strcmp (src_cfgfile,
                   dst_cfgfile))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Source and destination configuration files must differ!\n");
    return 1;
  }
  src_cfg = load_config (src_cfgfile);
  if (NULL == src_cfg)
  {
    GNUNET_free (src_cfgfile);
    GNUNET_free (dst_cfgfile);
    return 1;
  }
  dst_cfg = load_config (dst_cfgfile);
  if (NULL == dst_cfg)
  {
    GNUNET_CONFIGURATION_destroy (src_cfg);
    GNUNET_free (src_cfgfile);
    GNUNET_free (dst_cfgfile);
    return 1;
  }
  setup (src_cfg,
         dst_cfg);
  GNUNET_CONFIGURATION_destroy (src_cfg);
  GNUNET_CONFIGURATION_destroy (dst_cfg);
  GNUNET_free (src_cfgfile);
  GNUNET_free (dst_cfgfile);

  return global_ret;
}


/* end of taler-auditor-sync.c */
