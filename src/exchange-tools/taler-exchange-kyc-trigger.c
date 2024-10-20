/*
   This file is part of TALER
   Copyright (C) 2020-2024 Taler Systems SA

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
 * @file taler-exchange-kyc-trigger.c
 * @brief Support for manually triggering KYC/AML processes for testing
 * @author Christian Grothoff
 */
#include <platform.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"


/**
 * Our private key.
 */
static union TALER_AccountPrivateKeyP account_priv;

/**
 * Our public key.
 */
static union TALER_AccountPublicKeyP account_pub;

/**
 * Our context for making HTTP requests.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Reschedule context for #ctx.
 */
static struct GNUNET_CURL_RescheduleContext *rc;

/**
 * Handle to the exchange's configuration
 */
static const struct GNUNET_CONFIGURATION_Handle *kcfg;

/**
 * Handle for exchange interaction.
 * FIXME: wrong type...
 */
static struct TALER_EXCHANGE_ManagementGetKeysHandle *mgkh;

/**
 * Return value from main().
 */
static int global_ret;

/**
 * Currency we have configured.
 */
static char *currency;

/**
 * URL of the exchange we are interacting with
 * as per our configuration.
 */
static char *CFG_exchange_url;

/**
 * Shutdown task. Invoked when the application is being terminated.
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  (void) cls;
  if (NULL != mgkh)
  {
    TALER_EXCHANGE_get_management_keys_cancel (mgkh);
    mgkh = NULL;
  }
  if (NULL != ctx)
  {
    GNUNET_CURL_fini (ctx);
    ctx = NULL;
  }
  if (NULL != rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (rc);
    rc = NULL;
  }
}


/**
 * Load the account key.
 *
 * @param do_create #GNUNET_YES if the key may be created
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
load_account_key (int do_create)
{
  int ret;
  char *fn;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "exchange-testing",
                                               "ACCOUNT_PRIV_FILE",
                                               &fn))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange-testing",
                               "ACCOUNT_PRIV_FILE");
    return GNUNET_SYSERR;
  }
  if (GNUNET_YES !=
      GNUNET_DISK_file_test (fn))
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Account private key `%s' does not exist yet, creating it!\n",
                fn);
  ret = GNUNET_CRYPTO_eddsa_key_from_file (fn,
                                           do_create,
                                           &account_priv.reserve_priv.eddsa_priv
                                           );
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize master key from file `%s': %s\n",
                fn,
                "could not create file");
    GNUNET_free (fn);
    return GNUNET_SYSERR;
  }
  GNUNET_free (fn);
  GNUNET_CRYPTO_eddsa_key_get_public (&account_priv.reserve_priv.eddsa_priv,
                                      &account_pub.reserve_pub.eddsa_pub);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Using account public key %s\n",
              TALER_B2S (&account_pub));
  return GNUNET_OK;
}


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
  (void) cls;
  (void) cfgfile;
  kcfg = cfg;

  if (GNUNET_OK !=
      load_account_key (GNUNET_YES))
  {
    global_ret = EXIT_FAILURE;
    return;
  }
  if (GNUNET_OK !=
      TALER_config_get_currency (kcfg,
                                 &currency))
  {
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if ( (NULL == CFG_exchange_url) &&
       (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (kcfg,
                                               "exchange",
                                               "BASE_URL",
                                               &CFG_exchange_url)) )
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  mgkh = NULL; // FIXME: start exchange interaction!
}


/**
 * The main function of the taler-exchange-kyc-trigger tool.
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
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return EXIT_INVALIDARGUMENT;
  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-exchange-kyc-trigger",
    gettext_noop (
      "Trigger KYC/AML measures based on high wallet balance for testing"),
    options,
    &run, NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-kyc-trigger.c */
