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
static unsigned int actual_size;


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
 * Task to do the actual synchronization work.
 *
 * @param cls NULL, unused
 */
static void
do_sync (void *cls)
{
  struct GNUNET_TIME_Relative delay;

  sync_task = NULL;
  actual_size = 0;
  // FIXME: do real work here!
  if (actual_size < transaction_size / 2)
  {
    delay = GNUNET_TIME_STD_BACKOFF (delay);
  }
  else if (actual_size >= transaction_size)
  {
    delay = GNUNET_TIME_UNIT_ZERO;
  }
  sync_task = GNUNET_SCHEDULER_add_delayed (delay,
                                            &do_sync,
                                            NULL);
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
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };

  TALER_gcrypt_init (); /* must trigger initialization manually at this point! */
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-auditor-sync",
                                   "WARNING",
                                   NULL));
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
