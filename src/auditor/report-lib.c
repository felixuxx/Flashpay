/*
  This file is part of TALER
  Copyright (C) 2016-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero Public License for more details.

  You should have received a copy of the GNU Affero Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file auditor/report-lib.c
 * @brief helper library to facilitate generation of audit reports
 * @author Christian Grothoff
 */
#include "platform.h"
#include "report-lib.h"

/**
 * Handle to access the exchange's database.
 */
struct TALER_EXCHANGEDB_Plugin *TALER_ARL_edb;

/**
 * Which currency are we doing the audit for?
 */
char *TALER_ARL_currency;

/**
 * How many fractional digits does the currency use?
 */
struct TALER_Amount TALER_ARL_currency_round_unit;

/**
 * Our configuration.
 */
const struct GNUNET_CONFIGURATION_Handle *TALER_ARL_cfg;

/**
 * Handle to access the auditor's database.
 */
struct TALER_AUDITORDB_Plugin *TALER_ARL_adb;

/**
 * Master public key of the exchange to audit.
 */
struct TALER_MasterPublicKeyP TALER_ARL_master_pub;

/**
 * Public key of the auditor.
 */
struct TALER_AuditorPublicKeyP TALER_ARL_auditor_pub;

/**
 * REST API endpoint of the auditor.
 */
char *TALER_ARL_auditor_url;

/**
 * REST API endpoint of the exchange.
 */
char *TALER_ARL_exchange_url;

/**
 * At what time did the auditor process start?
 */
struct GNUNET_TIME_Absolute start_time;

/**
 * Results about denominations, cached per-transaction, maps denomination pub hashes
 * to `const struct TALER_EXCHANGEDB_DenominationKeyInformation`.
 */
static struct GNUNET_CONTAINER_MultiHashMap *denominations;

/**
 * Flag that is raised to 'true' if the user
 * presses CTRL-C to abort the audit.
 */
static volatile bool abort_flag;

/**
 * Context for the SIG-INT (ctrl-C) handler.
 */
static struct GNUNET_SIGNAL_Context *sig_int;

/**
 * Context for the SIGTERM handler.
 */
static struct GNUNET_SIGNAL_Context *sig_term;


bool
TALER_ARL_do_abort (void)
{
  return abort_flag;
}


void
TALER_ARL_report (json_t *array,
                  json_t *object)
{
  GNUNET_assert (NULL != object);
  GNUNET_assert (0 ==
                 json_array_append_new (array,
                                        object));
}


/**
 * Function called with the results of iterate_denomination_info(),
 * or directly (!).  Used to check and add the respective denomination
 * to our hash table.
 *
 * @param cls closure, NULL
 * @param denom_pub public key, sometimes NULL (!)
 * @param issue issuing information with value, fees and other info about the denomination.
 */
static void
add_denomination (
  void *cls,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue)
{
  (void) cls;
  (void) denom_pub;
  if (NULL !=
      GNUNET_CONTAINER_multihashmap_get (denominations,
                                         &issue->denom_hash.hash))
    return; /* value already known */
#if GNUNET_EXTRA_LOGGING >= 1
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Tracking denomination `%s' (%s)\n",
                GNUNET_h2s (&issue->denom_hash.hash),
                TALER_amount2s (&issue->value));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Withdraw fee is %s\n",
                TALER_amount2s (&issue->fees.withdraw));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Start time is %s\n",
                GNUNET_TIME_timestamp2s (issue->start));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Expire deposit time is %s\n",
                GNUNET_TIME_timestamp2s (issue->expire_deposit));
  }
#endif
  {
    struct TALER_EXCHANGEDB_DenominationKeyInformation *i;

    i = GNUNET_new (struct TALER_EXCHANGEDB_DenominationKeyInformation);
    *i = *issue;
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (denominations,
                                                      &issue->denom_hash.hash,
                                                      i,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
}


enum GNUNET_DB_QueryStatus
TALER_ARL_get_denomination_info_by_hash (
  const struct TALER_DenominationHashP *dh,
  const struct TALER_EXCHANGEDB_DenominationKeyInformation **issue)
{
  enum GNUNET_DB_QueryStatus qs;

  if (NULL == denominations)
  {
    denominations = GNUNET_CONTAINER_multihashmap_create (256,
                                                          GNUNET_NO);
    qs = TALER_ARL_edb->iterate_denomination_info (TALER_ARL_edb->cls,
                                                   &add_denomination,
                                                   NULL);
    if (0 > qs)
    {
      GNUNET_break (0);
      *issue = NULL;
      return qs;
    }
  }
  {
    const struct TALER_EXCHANGEDB_DenominationKeyInformation *i;

    i = GNUNET_CONTAINER_multihashmap_get (denominations,
                                           &dh->hash);
    if (NULL != i)
    {
      /* cache hit */
      *issue = i;
      return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
    }
  }
  /* maybe database changed since we last iterated, give it one more shot */
  {
    struct TALER_EXCHANGEDB_DenominationKeyInformation issue;

    qs = TALER_ARL_edb->get_denomination_info (TALER_ARL_edb->cls,
                                               dh,
                                               &issue);
    if (qs <= 0)
    {
      GNUNET_break (qs >= 0);
      if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Denomination %s not found\n",
                    TALER_B2S (dh));
      return qs;
    }
    add_denomination (NULL,
                      NULL,
                      &issue);
  }
  {
    const struct TALER_EXCHANGEDB_DenominationKeyInformation *i;

    i = GNUNET_CONTAINER_multihashmap_get (denominations,
                                           &dh->hash);
    if (NULL != i)
    {
      /* cache hit */
      *issue = i;
      return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
    }
  }
  /* We found more keys, but not the denomination we are looking for :-( */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Denomination %s not found\n",
              TALER_B2S (dh));
  return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
}


enum GNUNET_DB_QueryStatus
TALER_ARL_get_denomination_info (
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyInformation **issue,
  struct TALER_DenominationHashP *dh)
{
  struct TALER_DenominationHashP hc;

  if (NULL == dh)
    dh = &hc;
  TALER_denom_pub_hash (denom_pub,
                        dh);
  return TALER_ARL_get_denomination_info_by_hash (dh,
                                                  issue);
}


/**
 * Perform the given @a analysis within a transaction scope.
 * Commit on success.
 *
 * @param analysis analysis to run
 * @param analysis_cls closure for @a analysis
 * @return #GNUNET_OK if @a analysis successfully committed,
 *         #GNUNET_NO if we had an error on commit (retry may help)
 *         #GNUNET_SYSERR on hard errors
 */
static enum GNUNET_GenericReturnValue
transact (TALER_ARL_Analysis analysis,
          void *analysis_cls)
{
  int ret;
  enum GNUNET_DB_QueryStatus qs;

  ret = TALER_ARL_adb->start (TALER_ARL_adb->cls);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_ARL_edb->preflight (TALER_ARL_edb->cls))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  ret = TALER_ARL_edb->start (TALER_ARL_edb->cls,
                              "auditor");
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    TALER_ARL_edb->rollback (TALER_ARL_edb->cls);
    return GNUNET_SYSERR;
  }
  qs = analysis (analysis_cls);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    qs = TALER_ARL_edb->commit (TALER_ARL_edb->cls);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Exchange DB commit failed, rolling back transaction\n");
      TALER_ARL_adb->rollback (TALER_ARL_adb->cls);
    }
    else
    {
      qs = TALER_ARL_adb->commit (TALER_ARL_adb->cls);
      if (0 > qs)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Auditor DB commit failed!\n");
      }
    }
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Processing failed (or no changes), rolling back transaction\n");
    TALER_ARL_adb->rollback (TALER_ARL_adb->cls);
    TALER_ARL_edb->rollback (TALER_ARL_edb->cls);
  }
  switch (qs)
  {
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    return GNUNET_OK;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    return GNUNET_OK;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return GNUNET_NO;
  case GNUNET_DB_STATUS_HARD_ERROR:
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_ARL_setup_sessions_and_run (TALER_ARL_Analysis ana,
                                  void *ana_cls)
{
  if (GNUNET_SYSERR ==
      TALER_ARL_edb->preflight (TALER_ARL_edb->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize exchange connection.\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_SYSERR ==
      TALER_ARL_adb->preflight (TALER_ARL_adb->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize auditor session.\n");
    return GNUNET_SYSERR;
  }

  if (0 > transact (ana,
                    ana_cls))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Test if the given @a mpub matches the #TALER_ARL_master_pub.
 * If so, set "found" to GNUNET_YES.
 *
 * @param cls a `int *` pointing to "found"
 * @param mpub exchange master public key to compare
 * @param exchange_url URL of the exchange (ignored)
 */
static void
test_master_present (void *cls,
                     const struct TALER_MasterPublicKeyP *mpub,
                     const char *exchange_url)
{
  int *found = cls;

  if (0 == GNUNET_memcmp (mpub,
                          &TALER_ARL_master_pub))
  {
    *found = GNUNET_YES;
    GNUNET_free (TALER_ARL_exchange_url);
    TALER_ARL_exchange_url = GNUNET_strdup (exchange_url);
  }
}


void
TALER_ARL_amount_add_ (struct TALER_Amount *sum,
                       const struct TALER_Amount *a1,
                       const struct TALER_Amount *a2,
                       const char *filename,
                       const char *functionname,
                       unsigned int line)
{
  enum TALER_AmountArithmeticResult aar;
  const char *msg;
  char *a2s;

  aar = TALER_amount_add (sum,
                          a1,
                          a2);
  if (aar >= 0)
    return;
  switch (aar)
  {
  case TALER_AAR_INVALID_RESULT_OVERFLOW:
    msg =
      "arithmetic overflow in amount addition (likely the database is corrupt, see manual)";
    break;
  case TALER_AAR_INVALID_NORMALIZATION_FAILED:
    msg =
      "normalization failed in amount addition (likely the database is corrupt, see manual)";
    break;
  case TALER_AAR_INVALID_CURRENCIES_INCOMPATIBLE:
    msg =
      "incompatible currencies in amount addition (likely bad configuration and auditor code missing a sanity check, see manual)";
    break;
  default:
    GNUNET_assert (0); /* should be impossible */
  }
  a2s = TALER_amount_to_string (a2);
  fprintf (stderr,
           "Aborting audit due to fatal error in function %s at %s:%d trying to add %s to %s: %s\n",
           functionname,
           filename,
           line,
           TALER_amount2s (a1),
           a2s,
           msg);
  GNUNET_free (a2s);
  exit (42);
}


void
TALER_ARL_amount_subtract_ (struct TALER_Amount *diff,
                            const struct TALER_Amount *a1,
                            const struct TALER_Amount *a2,
                            const char *filename,
                            const char *functionname,
                            unsigned int line)
{
  enum TALER_AmountArithmeticResult aar;
  const char *msg;
  char *a2s;

  aar = TALER_amount_subtract (diff,
                               a1,
                               a2);
  if (aar >= 0)
    return;
  switch (aar)
  {
  case TALER_AAR_INVALID_NEGATIVE_RESULT:
    msg =
      "negative result in amount subtraction (likely the database is corrupt, see manual)";
    break;
  case TALER_AAR_INVALID_NORMALIZATION_FAILED:
    msg =
      "normalization failed in amount subtraction (likely the database is corrupt, see manual)";
    break;
  case TALER_AAR_INVALID_CURRENCIES_INCOMPATIBLE:
    msg =
      "currencies incompatible in amount subtraction (likely bad configuration and auditor code missing a sanity check, see manual)";
    break;
  default:
    GNUNET_assert (0); /* should be impossible */
  }
  a2s = TALER_amount_to_string (a2);
  fprintf (stderr,
           "Aborting audit due to fatal error in function %s at %s:%d trying to subtract %s from %s: %s\n",
           functionname,
           filename,
           line,
           a2s,
           TALER_amount2s (a1),
           msg);
  GNUNET_free (a2s);
  exit (42);
}


enum TALER_ARL_SubtractionResult
TALER_ARL_amount_subtract_neg_ (struct TALER_Amount *diff,
                                const struct TALER_Amount *a1,
                                const struct TALER_Amount *a2,
                                const char *filename,
                                const char *functionname,
                                unsigned int line)
{
  enum TALER_AmountArithmeticResult aar;
  const char *msg;
  char *a2s;

  aar = TALER_amount_subtract (diff,
                               a1,
                               a2);
  switch (aar)
  {
  case TALER_AAR_RESULT_POSITIVE:
    return TALER_ARL_SR_POSITIVE;
  case TALER_AAR_RESULT_ZERO:
    return TALER_ARL_SR_ZERO;
  case TALER_AAR_INVALID_NEGATIVE_RESULT:
    return TALER_ARL_SR_INVALID_NEGATIVE;
  case TALER_AAR_INVALID_NORMALIZATION_FAILED:
    msg =
      "normalization failed in amount subtraction (likely the database is corrupt, see manual)";
    break;
  case TALER_AAR_INVALID_CURRENCIES_INCOMPATIBLE:
    msg =
      "currencies incompatible in amount subtraction (likely bad configuration and auditor code missing a sanity check, see manual)";
    break;
  default:
    GNUNET_assert (0); /* should be impossible */
  }
  a2s = TALER_amount_to_string (a2);
  fprintf (stderr,
           "Aborting audit due to fatal error in function %s at %s:%d trying to subtract %s from %s: %s\n",
           functionname,
           filename,
           line,
           a2s,
           TALER_amount2s (a1),
           msg);
  GNUNET_free (a2s);
  exit (42);
}


/**
 * Signal handler called for signals that should cause us to shutdown.
 */
static void
handle_sigint (void)
{
  abort_flag = true;
}


enum GNUNET_GenericReturnValue
TALER_ARL_init (const struct GNUNET_CONFIGURATION_Handle *c)
{
  TALER_ARL_cfg = c;
  start_time = GNUNET_TIME_absolute_get ();

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (TALER_ARL_cfg,
                                             "auditor",
                                             "BASE_URL",
                                             &TALER_ARL_auditor_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "BASE_URL");
    return GNUNET_SYSERR;
  }
  if (GNUNET_is_zero (&TALER_ARL_master_pub))
  {
    /* -m option not given, try configuration */
    char *master_public_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (TALER_ARL_cfg,
                                               "exchange",
                                               "MASTER_PUBLIC_KEY",
                                               &master_public_key_str))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Pass option -m or set MASTER_PUBLIC_KEY in the configuration!\n");
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "MASTER_PUBLIC_KEY");
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_public_key_from_string (
          master_public_key_str,
          strlen (master_public_key_str),
          &TALER_ARL_master_pub.eddsa_pub))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "MASTER_PUBLIC_KEY",
                                 "invalid key");
      GNUNET_free (master_public_key_str);
      return GNUNET_SYSERR;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Running auditor against exchange master public key `%s'\n",
                master_public_key_str);
    GNUNET_free (master_public_key_str);
  } /* end of -m not given */

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Taler auditor running for exchange master public key %s\n",
              TALER_B2S (&TALER_ARL_master_pub));

  if (GNUNET_is_zero (&TALER_ARL_auditor_pub))
  {
    char *auditor_public_key_str;

    if (GNUNET_OK ==
        GNUNET_CONFIGURATION_get_value_string (c,
                                               "auditor",
                                               "PUBLIC_KEY",
                                               &auditor_public_key_str))
    {
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_public_key_from_string (
            auditor_public_key_str,
            strlen (auditor_public_key_str),
            &TALER_ARL_auditor_pub.eddsa_pub))
      {
        GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                   "auditor",
                                   "PUBLIC_KEY",
                                   "invalid key");
        GNUNET_free (auditor_public_key_str);
        return GNUNET_SYSERR;
      }
      GNUNET_free (auditor_public_key_str);
    }
  }

  if (GNUNET_is_zero (&TALER_ARL_auditor_pub))
  {
    /* public key not configured */
    /* try loading private key and deriving public key */
    char *fn;

    if (GNUNET_OK ==
        GNUNET_CONFIGURATION_get_value_filename (c,
                                                 "auditor",
                                                 "AUDITOR_PRIV_FILE",
                                                 &fn))
    {
      struct TALER_AuditorPrivateKeyP auditor_priv;

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Loading offline private key from `%s' to get auditor public key\n",
                  fn);
      if (GNUNET_OK ==
          GNUNET_CRYPTO_eddsa_key_from_file (fn,
                                             GNUNET_NO, /* do NOT create it! */
                                             &auditor_priv.eddsa_priv))
      {
        GNUNET_CRYPTO_eddsa_key_get_public (&auditor_priv.eddsa_priv,
                                            &TALER_ARL_auditor_pub.eddsa_pub);
      }
      GNUNET_free (fn);
    }
  }

  if (GNUNET_is_zero (&TALER_ARL_auditor_pub))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_INFO,
                               "auditor",
                               "PUBLIC_KEY/AUDITOR_PRIV_FILE");
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      TALER_config_get_currency (TALER_ARL_cfg,
                                 &TALER_ARL_currency))
  {
    return GNUNET_SYSERR;
  }
  {
    if ( (GNUNET_OK !=
          TALER_config_get_amount (TALER_ARL_cfg,
                                   "taler",
                                   "CURRENCY_ROUND_UNIT",
                                   &TALER_ARL_currency_round_unit)) ||
         ( (0 != TALER_ARL_currency_round_unit.fraction) &&
           (0 != TALER_ARL_currency_round_unit.value) ) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Need non-zero value in section `TALER' under `CURRENCY_ROUND_UNIT'\n");
      return GNUNET_SYSERR;
    }
  }
  sig_int = GNUNET_SIGNAL_handler_install (SIGINT,
                                           &handle_sigint);
  if (NULL == sig_int)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "signal");
    TALER_ARL_done (NULL);
    return GNUNET_SYSERR;
  }
  sig_term = GNUNET_SIGNAL_handler_install (SIGTERM,
                                            &handle_sigint);
  if (NULL == sig_term)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "signal");
    TALER_ARL_done (NULL);
    return GNUNET_SYSERR;
  }
  if (NULL ==
      (TALER_ARL_edb = TALER_EXCHANGEDB_plugin_load (TALER_ARL_cfg)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize exchange database plugin.\n");
    TALER_ARL_done (NULL);
    return GNUNET_SYSERR;
  }
  if (NULL ==
      (TALER_ARL_adb = TALER_AUDITORDB_plugin_load (TALER_ARL_cfg)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize auditor database plugin.\n");
    TALER_ARL_done (NULL);
    return GNUNET_SYSERR;
  }
  {
    int found;

    if (GNUNET_SYSERR ==
        TALER_ARL_adb->preflight (TALER_ARL_adb->cls))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to start session with auditor database.\n");
      TALER_ARL_done (NULL);
      return GNUNET_SYSERR;
    }
    found = GNUNET_NO;
    (void) TALER_ARL_adb->list_exchanges (TALER_ARL_adb->cls,
                                          &test_master_present,
                                          &found);
    if (GNUNET_NO == found)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Exchange's master public key `%s' not known to auditor DB. Did you forget to run `taler-auditor-exchange`?\n",
                  GNUNET_p2s (&TALER_ARL_master_pub.eddsa_pub));
      TALER_ARL_done (NULL);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


void
TALER_ARL_done (json_t *report)
{
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Audit complete\n");
  if (NULL != sig_int)
  {
    GNUNET_SIGNAL_handler_uninstall (sig_int);
    sig_int = NULL;
  }
  if (NULL != sig_term)
  {
    GNUNET_SIGNAL_handler_uninstall (sig_term);
    sig_term = NULL;
  }
  if (NULL != TALER_ARL_adb)
  {
    TALER_AUDITORDB_plugin_unload (TALER_ARL_adb);
    TALER_ARL_adb = NULL;
  }
  if (NULL != TALER_ARL_edb)
  {
    TALER_EXCHANGEDB_plugin_unload (TALER_ARL_edb);
    TALER_ARL_edb = NULL;
  }
  if (NULL != report)
  {
    json_dumpf (report,
                stdout,
                JSON_INDENT (2));
    json_decref (report);
  }
  GNUNET_free (TALER_ARL_exchange_url);
  GNUNET_free (TALER_ARL_auditor_url);
}


/* end of report-lib.c */
