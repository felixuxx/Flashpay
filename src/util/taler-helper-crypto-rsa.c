/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file util/taler-helper-crypto-rsa.c
 * @brief Standalone process to perform private key RSA operations
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include <gcrypt.h>


/**
 * Information we keep per denomination.
 */
struct Denomination;


/**
 * One particular denomination key.
 */
struct DenominationKey
{

  /**
   * Kept in a DLL of the respective denomination.
   */
  struct DenominationKey *next;

  /**
   * Kept in a DLL of the respective denomination.
   */
  struct DenominationKey *prev;

  /**
   * Denomination this key belongs to.
   */
  struct Denomination *denom;

  /**
   * Denomination key details.  Note that the "dki.issue.signature"
   * IS ALWAYS uninitialized (all zeros).  The private key is in
   * 'dki.denom_priv.rsa_private_key' and must be free'd explicitly
   * (as it is a pointer to a variable-size data structure).
   */
  struct TALER_EXCHANGEDB_DenominationKey dki;

  /**
   * Time at which this key is supposed to become valid.
   */
  struct GNUNET_TIME_Absolute anchor;

};


struct Denomination
{

  /**
   * Kept in a DLL. Sorted?
   */
  struct Denomination *next;

  /**
   * Kept in a DLL. Sorted?
   */
  struct Denomination *prev;

  /**
   * Head of DLL of actual keys of this denomination.
   */
  struct DenominationKey *keys_head;

  /**
   * Tail of DLL of actual keys of this denomination.
   */
  struct DenominationKey *keys_tail;

  /**
   * How long are the signatures legally valid?  Should be
   * significantly larger than @e duration_spend (i.e. years).
   */
  struct GNUNET_TIME_Relative duration_legal;

  /**
   * How long can the coins be spend?  Should be significantly
   * larger than @e duration_withdraw (i.e. years).
   */
  struct GNUNET_TIME_Relative duration_spend;

  /**
   * How long can coins be withdrawn (generated)?  Should be small
   * enough to limit how many coins will be signed into existence with
   * the same key, but large enough to still provide a reasonable
   * anonymity set.
   */
  struct GNUNET_TIME_Relative duration_withdraw;

  /**
   * What is the value of each coin?
   */
  struct TALER_Amount value;

  /**
   * What is the fee charged for withdrawal?
   */
  struct TALER_Amount fee_withdraw;

  /**
   * What is the fee charged for deposits?
   */
  struct TALER_Amount fee_deposit;

  /**
   * What is the fee charged for melting?
   */
  struct TALER_Amount fee_refresh;

  /**
   * What is the fee charged for refunds?
   */
  struct TALER_Amount fee_refund;

  /**
   * Length of (new) RSA keys (in bits).
   */
  uint32_t rsa_keysize;
};


/**
 * Return value from main().
 */
static int global_ret;

/**
 * Time when the key update is executed.
 * Either the actual current time, or a pretended time.
 */
static struct GNUNET_TIME_Absolute now;

/**
 * The time for the key update, as passed by the user
 * on the command line.
 */
static struct GNUNET_TIME_Absolute now_tmp;

/**
 * Handle to the exchange's configuration
 */
static const struct GNUNET_CONFIGURATION_Handle *kcfg;

/**
 * The configured currency.
 */
static char *currency;

/**
 * How much should coin creation (@e duration_withdraw) duration overlap
 * with the next denomination?  Basically, the starting time of two
 * denominations is always @e duration_withdraw - #duration_overlap apart.
 */
static struct GNUNET_TIME_Relative overlap_duration;

/**
 * How long should keys be legally valid?
 */
static struct GNUNET_TIME_Relative legal_duration;

/**
 * How long into the future do we pre-generate keys?
 */
static struct GNUNET_TIME_Relative lookahead_sign;

/**
 * Largest duration for spending of any key.
 */
static struct GNUNET_TIME_Relative max_duration_spend;

/**
 * Until what time do we provide keys?
 */
static struct GNUNET_TIME_Absolute lookahead_sign_stamp;

/**
 * All of our denominations, in a DLL. Sorted?
 */
static struct Denomination *denom_head;

/**
 * All of our denominations, in a DLL. Sorted?
 */
static struct Denomination *denom_tail;

/**
 * Map of hashes of public (RSA) keys to `struct DenominationKey *`
 * with the respective private keys.
 */
static struct GNUNET_CONTAINER_MultiHashMap *keys;

/**
 * Our listen socket.
 */
static struct GNUNET_NETWORK_Handle *lsock;

/**
 * Task run to accept new inbound connections.
 */
static struct GNUNET_SCHEDULER_Task *accept_task;

/**
 * Task run to generate new keys.
 */
static struct GNUNET_SCHEDULER_Task *keygen_task;


/**
 * Load the various duration values from #kcfg.
 *
 * @return #GNUNET_OK on success
 */
static int
load_durations (void)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchange",
                                           "LEGAL_DURATION",
                                           &legal_duration))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "LEGAL_DURATION",
                               "fails to specify valid timeframe");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&legal_duration);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchangedb",
                                           "OVERLAP_DURATION",
                                           &overlap_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "OVERLAP_DURATION");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&overlap_duration);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchange",
                                           "LOOKAHEAD_SIGN",
                                           &lookahead_sign))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "LOOKAHEAD_SIGN");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&lookahead_sign);

  return GNUNET_OK;
}


/**
 * Parse configuration for denomination type parameters.  Also determines
 * our anchor by looking at the existing denominations of the same type.
 *
 * @param ct section in the configuration file giving the denomination type parameters
 * @param[out] denom set to the denomination parameters from the configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if the configuration is invalid
 */
static int
parse_denomination_cfg (const char *ct,
                        struct Denomination *denom)
{
  const char *dir;
  unsigned long long rsa_keysize;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "DURATION_WITHDRAW",
                                           &denom->duration_withdraw))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "DURATION_WITHDRAW");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&denom->duration_withdraw);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "DURATION_SPEND",
                                           &denom->duration_spend))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "DURATION_SPEND");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&denom->duration_spend);
  max_duration_spend = GNUNET_TIME_relative_max (max_duration_spend,
                                                 denom->duration_spend);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "DURATION_LEGAL",
                                           &denom->duration_legal))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "DURATION_LEGAL");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&denom->duration_legal);
  if (duration_overlap.rel_value_us >=
      denom->duration_withdraw.rel_value_us)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "DURATION_OVERLAP",
                               "Value given for DURATION_OVERLAP must be smaller than value for DURATION_WITHDRAW!");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (kcfg,
                                             ct,
                                             "RSA_KEYSIZE",
                                             &rsa_keysize))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "RSA_KEYSIZE");
    return GNUNET_SYSERR;
  }
  if ( (rsa_keysize > 4 * 2048) ||
       (rsa_keysize < 1024) )
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "RSA_KEYSIZE",
                               "Given RSA keysize outside of permitted range [1024,8192]\n");
    return GNUNET_SYSERR;
  }
  denom->rsa_keysize = (unsigned int) rsa_keysize;
  if (GNUNET_OK !=
      TALER_config_get_amount (kcfg,
                               ct,
                               "VALUE",
                               &denom->value))
  {
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (kcfg,
                               ct,
                               "FEE_WITHDRAW",
                               &denom->fee_withdraw))
  {
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (kcfg,
                               ct,
                               "FEE_DEPOSIT",
                               &denom->fee_deposit))
  {
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (kcfg,
                               ct,
                               "FEE_REFRESH",
                               &denom->fee_refresh))
  {
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (kcfg,
                               ct,
                               "fee_refund",
                               &denom->fee_refund))
  {
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Generate new denomination signing keys for the denomination type of the given @a
 * denomination_alias.
 *
 * @param cls a `int *`, to be set to #GNUNET_SYSERR on failure
 * @param denomination_alias name of the denomination's section in the configuration
 */
static void
load_denominations (void *cls,
                    const char *denomination_alias)
{
  int *ret = cls;
  struct Denomination *denom;

  if (0 != strncasecmp (denomination_alias,
                        "coin_",
                        strlen ("coin_")))
    return; /* not a denomination type definition */
  denom = GNUNET_new (struct Denomination);
  if (GNUNET_OK !=
      parse_denomination_cfg (denomination_alias,
                              denom))
  {
    *ret = GNUNET_SYSERR;
    GNUNET_free (denom);
    return;
  }
  GNUNET_CONTAINER_DLL_insert (denom_head,
                               denom_tail,
                               denom);
  // FIXME: load all existing denomination keys for this denom from disk!
}


/**
 * Function run to accept incoming connections on #sock.
 *
 * @param cls NULL
 */
static void
accept_job (void *cls)
{
  struct GNUNET_NETWORK_Handle *sock;
  struct sockaddr_storage addr;
  socklen_t alen;

  accept_task = NULL;
  alen = sizeof (addr);
  sock = GNUNET_NETWORK_socket_accept (lsock,
                                       (struct sockaddr *) &addr,
                                       &alen);
  // FIXME: add to list of managed connections;
  // then send all known keys;
  // start to listen for incoming requests;

  accept_task = GNUNET_SCHEDULER_add_read (GNUNET_TIME_UNIT_FOREVER_REL,
                                           lsock,
                                           &accept_job,
                                           NULL);
}


/**
 * Function run on shutdown. Stops the various jobs (nicely).
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  (void) cls;
  if (NULL != accept_task)
  {
    GNUNET_SCHEDULER_cancel (accept_task);
    accept_task = NULL;
  }
  if (NULL != lsock)
  {
    GNUNET_break (0 ==
                  GNUNET_NETWORK_socket_close (lsock));
    lsock = NULL;
  }
  if (NULL != keygen_task)
  {
    GNUNET_SCHEDULER_cancel (keygen_task);
    keygen_task = NULL;
  }
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
  (void) args;
  (void) cfgfile;
  kcfg = cfg;
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &currency))
  {
    global_ret = 1;
    return;
  }
  if (now.abs_value_us != now_tmp.abs_value_us)
  {
    /* The user gave "--now", use it! */
    now = now_tmp;
  }
  else
  {
    /* get current time again, we may be timetraveling! */
    now = GNUNET_TIME_absolute_get ();
  }
  GNUNET_TIME_round_abs (&now);
  if (GNUNET_OK !=
      load_durations ())
  {
    global_ret = 1;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "exchange",
                                               "KEYDIR",
                                               &exchange_directory))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "KEYDIR");
    global_ret = 1;
    return;
  }

  /* open socket */
  {
    int sock;

    sock = socket (PF_UNIX,
                   SOCK_DGRAM,
                   0);
    if (-1 == sock)
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                           "socket");
      global_ret = 2;
      return;
    }
    {
      struct sockaddr_un un;
      char *unixpath;

      if (GNUNET_OK !=
          GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                                   "exchange-helper-crypto-rsa",
                                                   "UNIXPATH",
                                                   &unixpath))
      {
        GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                   "exchange-helper-crypto-rsa",
                                   "UNIXPATH");
        global_ret = 3;
        return;
      }
      memset (&un,
              0,
              sizeof (un));
      un.sun_family = AF_UNIX;
      strncpy (un.sun_path,
               unixpath,
               sizeof (un.sun_path));
      if (0 != bind (sock,
                     (const struct sockaddr *) &un,
                     sizeof (un)))
      {
        GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                  "bind",
                                  unixpath);
        global_ret = 3;
        GNUNET_break (0 == close (sock));
        return;
      }
    }
    lsock = GNUNET_NETWORK_socket_box_native (sock);
  }

  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  /* FIXME: start job to accept incoming requests on 'sock' */
  accept_task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                               lsock,
                                               &accept_job,
                                               NULL);

  /* Load denominations */
  keys = GNUNET_CONTAINER_multihashmap_create (65536,
                                               GNUNET_NO);
  {
    int ok;

    ok = GNUNET_OK;
    GNUNET_CONFIGURATION_iterate_sections (kcfg,
                                           &load_denominations,
                                           &ok);
    if (GNUNET_OK != ok)
    {
      global_ret = 4;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
  }
  if (NULL == denom_head)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No denominations configured\n");
    global_ret = 5;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  // FIXME: begin job to create additional denomination keys based on
  // next needs!
  // FIXME: same job or extra job for private key expiration/purge?
}


int
main (int argc,
      char **argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_option_absolute_time ('t',
                                        "time",
                                        "TIMESTAMP",
                                        "pretend it is a different time for the update",
                                        &now_tmp),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  umask (S_IWGRP | S_IROTH | S_IWOTH | S_IXOTH);
  /* force linker to link against libtalerutil; if we do
   not do this, the linker may "optimize" libtalerutil
   away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-helper-crypto-rsa",
                                   "WARNING",
                                   NULL));
  now = now_tmp = GNUNET_TIME_absolute_get ();
  ret = GNUNET_PROGRAM_run (argc, argv,
                            "taler-helper-crypto-rsa",
                            "Handle private RSA key operations for a Taler exchange",
                            options,
                            &run,
                            NULL);
  if (GNUNET_NO == ret)
    return 0;
  if (GNUNET_SYSERR == ret)
    return 1;
  return global_ret;
}
