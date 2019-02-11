/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-wire.c
 * @brief Utility performing wire transfers.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */

#include <platform.h>
#include <gnunet/gnunet_util_lib.h>
#include <taler/taler_util.h>
#include <taler/taler_wire_lib.h>

/**
 * If set to GNUNET_YES, then we'll ask the bank for a list
 * of transactions from the account mentioned in the config
 * section.
 */
int history;

/**
 * If set to GNUNET_YES, then we'll ask the bank to execute a
 * wire transfer.
 */
int transfer;

/**
 * Name of the wire plugin to use with the bank.
 */
char *plugin_name;

/**
 * Global return code.
 */
unsigned int global_ret = 0;

/**
 * Base32 encoding of a transaction ID.  When asking the
 * bank for a transaction history, all the results will
 * have a transaction ID settled *after* this one.
 */
char *since_when;

/**
 * Which config section has the credentials to access the bank.
 */
char *account_section; 

/**
 * Binary version of the 'since-when' CLI option.
 */
void *since_when_bin;

/**
 * Wire plugin handle.
 */
struct TALER_WIRE_Plugin *plugin_handle;


/**
 * Callback used to process ONE entry in the transaction
 * history returned by the bank.
 * @param cls closure
 * @param ec taler error code
 * @param dir direction of the transfer
 * @param row_off identification of the position at
 *        which we are querying
 * @param row_off_size number of bytes in @a row_off
 * @param details details about the wire transfer
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to
 *         abort iteration
 */
int
cb (void *cls,
    enum TALER_ErrorCode ec,
    enum TALER_BANK_Direction dir,
    const void *row_off,
    size_t row_off_size,
    const struct TALER_WIRE_TransferDetails *details)
{
  char *row_off_enc;

  row_off_enc = GNUNET_STRINGS_data_to_string_alloc (row_off,
                                                     row_off_size);

  fprintf (stdout,
           "History of transactions:\n");

  /* Give more details on screen (??) */
  fprintf (stdout,
           "%s\n",
           row_off_enc);

  GNUNET_free (row_off_enc);

  return GNUNET_SYSERR;
}

/**
 * Ask the bank to execute a wire transfer.
 */
void
execute_wire_transfer ()
{}

/**
 * Ask the bank the list of transactions for the bank account
 * mentioned in the config section given by the user.
 */
void
execute_history ()
{
  size_t bin_len = (strlen (since_when) * 5) / 8;

  if (NULL == since_when)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Missing since-when option\n");
    global_ret = 1;
    return;
  }

  since_when_bin = GNUNET_malloc (bin_len);
    GNUNET_assert
      (GNUNET_OK == GNUNET_STRINGS_string_to_data
        (since_when,
         strlen (since_when),
         since_when_bin,
         bin_len));

  if (NULL == plugin_handle->get_history
      (plugin_handle->cls,
       account_section,
       TALER_BANK_DIRECTION_BOTH,
       since_when_bin,
       bin_len,
       10,
       cb,
       NULL));
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not request the transaction history.\n");
    global_ret = 1;
    return;
  }
    
}

/**
 * Main function that will be run.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used
 *        (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  if (NULL == account_section)
  {
    global_ret = 1;
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "The ACCOUNT-SECTION is mandatory.\n");
    return;
  }

  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_string
      (cfg,
       account_section,
       "plugin",
       &plugin_name))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not find the 'plugin' value under %s\n",
                account_section);
    global_ret = 1;
    return;
  }

  plugin_handle = TALER_WIRE_plugin_load (cfg,
                                          plugin_name);
  if (NULL == plugin_handle)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not load the wire plugin\n");
    global_ret = 1;
    return;
  }

  if (GNUNET_YES == history)
    execute_history ();
  else
    execute_wire_transfer ();
}

/**
 * Main function of taler-wire.  This tool is used to command the
 * execution of wire transfers from the command line.  Its main
 * purpose is to test whether the bank and exchange can speak the
 * same protocol of a certain wire plugin.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {

    GNUNET_GETOPT_option_flag ('h',
                               "history",
                               "Wire plugin to use",
                               &history),

    GNUNET_GETOPT_option_flag ('t',
                               "transfer",
                               "Execute a wire transfer.",
                               &transfer),

    GNUNET_GETOPT_option_string ('w',
                                 "since-when",
                                 "SW",
                                 "When asking the bank for"
                                 " transactions history, this"
                                 " option commands that all the"
                                 " results should have IDs settled"
                                 " after SW",
                                 &since_when),

    GNUNET_GETOPT_option_string ('s',
                                 "section",
                                 "ACCOUNT-SECTION",
                                 "Which config section has the"
                                 " credentials to access the"
                                 " bank.\n",
                                 &account_section),

    GNUNET_GETOPT_OPTION_END
  };

  GNUNET_assert
    (GNUNET_OK == GNUNET_log_setup ("taler-wire",
                                    NULL,
                                    NULL)); /* filename */

  if (GNUNET_OK != GNUNET_PROGRAM_run
      (argc,
       argv,
       "taler-wire",
       "Perform wire transfers using plugin PLUGIN",
       options,
       &run,
       NULL))
    return 1;

  return global_ret;
}
