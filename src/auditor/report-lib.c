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
 * Command-line option "-r": restart audit from scratch
 */
int restart;

/**
 * Handle to access the exchange's database.
 */
struct TALER_EXCHANGEDB_Plugin *edb;

/**
 * Which currency are we doing the audit for?
 */
char *currency;

/**
 * How many fractional digits does the currency use?
 */
struct TALER_Amount currency_round_unit;

/**
 * Our configuration.
 */
const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our session with the #edb.
 */
struct TALER_EXCHANGEDB_Session *esession;

/**
 * Handle to access the auditor's database.
 */
struct TALER_AUDITORDB_Plugin *adb;

/**
 * Our session with the #adb.
 */
struct TALER_AUDITORDB_Session *asession;

/**
 * Master public key of the exchange to audit.
 */
struct TALER_MasterPublicKeyP master_pub;

/**
 * At what time did the auditor process start?
 */
struct GNUNET_TIME_Absolute start_time;

/**
 * Results about denominations, cached per-transaction, maps denomination pub hashes
 * to `struct TALER_DenominationKeyValidityPS`.
 */
static struct GNUNET_CONTAINER_MultiHashMap *denominations;


/**
 * Convert absolute time to human-readable JSON string.
 *
 * @param at time to convert
 * @return human-readable string representing the time
 */
json_t *
json_from_time_abs_nbo (struct GNUNET_TIME_AbsoluteNBO at)
{
  return json_string
           (GNUNET_STRINGS_absolute_time_to_string
             (GNUNET_TIME_absolute_ntoh (at)));
}


/**
 * Convert absolute time to human-readable JSON string.
 *
 * @param at time to convert
 * @return human-readable string representing the time
 */
json_t *
json_from_time_abs (struct GNUNET_TIME_Absolute at)
{
  return json_string
           (GNUNET_STRINGS_absolute_time_to_string (at));
}


/**
 * Add @a object to the report @a array.  Fail hard if this fails.
 *
 * @param array report array to append @a object to
 * @param object object to append, should be check that it is not NULL
 */
void
report (json_t *array,
        json_t *object)
{
  GNUNET_assert (NULL != object);
  GNUNET_assert (0 ==
                 json_array_append_new (array,
                                        object));
}


/**
 * Function called with the results of select_denomination_info()
 *
 * @param cls closure, NULL
 * @param issue issuing information with value, fees and other info about the denomination.
 * @return #GNUNET_OK (to continue)
 */
static int
add_denomination (void *cls,
                  const struct TALER_DenominationKeyValidityPS *issue)
{
  struct TALER_DenominationKeyValidityPS *i;

  (void) cls;
  if (NULL !=
      GNUNET_CONTAINER_multihashmap_get (denominations,
                                         &issue->denom_hash))
    return GNUNET_OK; /* value already known */
  {
    struct TALER_Amount value;

    TALER_amount_ntoh (&value,
                       &issue->value);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Tracking denomination `%s' (%s)\n",
                GNUNET_h2s (&issue->denom_hash),
                TALER_amount2s (&value));
    TALER_amount_ntoh (&value,
                       &issue->fee_withdraw);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Withdraw fee is %s\n",
                TALER_amount2s (&value));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Start time is %s\n",
                GNUNET_STRINGS_absolute_time_to_string
                  (GNUNET_TIME_absolute_ntoh (issue->start)));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Expire deposit time is %s\n",
                GNUNET_STRINGS_absolute_time_to_string
                  (GNUNET_TIME_absolute_ntoh (issue->expire_deposit)));
  }
  i = GNUNET_new (struct TALER_DenominationKeyValidityPS);
  *i = *issue;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (denominations,
                                                    &issue->denom_hash,
                                                    i,
                                                    GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  return GNUNET_OK;
}


/**
 * Obtain information about a @a denom_pub.
 *
 * @param dh hash of the denomination public key to look up
 * @param[out] issue set to detailed information about @a denom_pub, NULL if not found, must
 *                 NOT be freed by caller
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
get_denomination_info_by_hash (const struct GNUNET_HashCode *dh,
                               const struct
                               TALER_DenominationKeyValidityPS **issue)
{
  const struct TALER_DenominationKeyValidityPS *i;
  enum GNUNET_DB_QueryStatus qs;

  if (NULL == denominations)
  {
    denominations = GNUNET_CONTAINER_multihashmap_create (256,
                                                          GNUNET_NO);
    qs = adb->select_denomination_info (adb->cls,
                                        asession,
                                        &master_pub,
                                        &add_denomination,
                                        NULL);
    if (0 > qs)
    {
      *issue = NULL;
      return qs;
    }
  }
  i = GNUNET_CONTAINER_multihashmap_get (denominations,
                                         dh);
  if (NULL != i)
  {
    /* cache hit */
    *issue = i;
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
  /* maybe database changed since we last iterated, give it one more shot */
  qs = adb->select_denomination_info (adb->cls,
                                      asession,
                                      &master_pub,
                                      &add_denomination,
                                      NULL);
  if (qs <= 0)
  {
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Denomination %s not found\n",
                  TALER_B2S (dh));
    return qs;
  }
  i = GNUNET_CONTAINER_multihashmap_get (denominations,
                                         dh);
  if (NULL != i)
  {
    /* cache hit */
    *issue = i;
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
  /* We found more keys, but not the denomination we are looking for :-( */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Denomination %s not found\n",
              TALER_B2S (dh));
  return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
}


/**
 * Obtain information about a @a denom_pub.
 *
 * @param denom_pub key to look up
 * @param[out] issue set to detailed information about @a denom_pub, NULL if not found, must
 *                 NOT be freed by caller
 * @param[out] dh set to the hash of @a denom_pub, may be NULL
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
get_denomination_info (const struct TALER_DenominationPublicKey *denom_pub,
                       const struct
                       TALER_DenominationKeyValidityPS **issue,
                       struct GNUNET_HashCode *dh)
{
  struct GNUNET_HashCode hc;

  if (NULL == dh)
    dh = &hc;
  GNUNET_CRYPTO_rsa_public_key_hash (denom_pub->rsa_public_key,
                                     dh);
  return get_denomination_info_by_hash (dh,
                                        issue);
}


/**
 * Perform the given @a analysis within a transaction scope.
 * Commit on success.
 *
 * @param analysis analysis to run
 * @param analysis_cls closure for @a analysis
 * @return #GNUNET_OK if @a analysis succeessfully committed,
 *         #GNUNET_NO if we had an error on commit (retry may help)
 *         #GNUNET_SYSERR on hard errors
 */
int
transact (Analysis analysis,
          void *analysis_cls)
{
  int ret;
  enum GNUNET_DB_QueryStatus qs;

  ret = adb->start (adb->cls,
                    asession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  edb->preflight (edb->cls,
                  esession);
  ret = edb->start (edb->cls,
                    esession,
                    "auditor");
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  qs = analysis (analysis_cls);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    qs = edb->commit (edb->cls,
                      esession);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Exchange DB commit failed, rolling back transaction\n");
      adb->rollback (adb->cls,
                     asession);
    }
    else
    {
      qs = adb->commit (adb->cls,
                        asession);
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
    adb->rollback (adb->cls,
                   asession);
    edb->rollback (edb->cls,
                   esession);
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


/**
 * Initialize DB sessions and run the analysis.
 *
 * @param ana analysis to run
 * @param ana_cls closure for @ana
 * @return #GNUNET_OK on success
 */
int
setup_sessions_and_run (Analysis ana,
                        void *ana_cls)
{
  esession = edb->get_session (edb->cls);
  if (NULL == esession)
  {
    fprintf (stderr,
             "Failed to initialize exchange session.\n");
    return GNUNET_SYSERR;
  }
  asession = adb->get_session (adb->cls);
  if (NULL == asession)
  {
    fprintf (stderr,
             "Failed to initialize auditor session.\n");
    return GNUNET_SYSERR;
  }

  GNUNET_break (GNUNET_SYSERR !=
                transact (ana,
                          ana_cls));
  return GNUNET_OK;
}


/**
 * Test if the given @a mpub matches the #master_pub.
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

  (void) exchange_url;
  if (0 == GNUNET_memcmp (mpub,
                          &master_pub))
    *found = GNUNET_YES;
}


int
setup_globals (const struct GNUNET_CONFIGURATION_Handle *c)
{
  int found;
  struct TALER_AUDITORDB_Session *as;

  cfg = c;
  start_time = GNUNET_TIME_absolute_get ();
  if (0 == GNUNET_is_zero (&master_pub))
  {
    /* -m option not given, try configuration */
    char *master_public_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange",
                                               "MASTER_PUBLIC_KEY",
                                               &master_public_key_str))
    {
      fprintf (stderr,
               "Pass option -m or set it in the configuration!\n");
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "MASTER_PUBLIC_KEY");
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_public_key_from_string (master_public_key_str,
                                                    strlen (
                                                      master_public_key_str),
                                                    &master_pub.eddsa_pub))
    {
      fprintf (stderr,
               "Invalid master public key given in configuration file.");
      GNUNET_free (master_public_key_str);
      return GNUNET_SYSERR;
    }
    GNUNET_free (master_public_key_str);
  } /* end of -m not given */

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Taler auditor running for exchange master public key %s\n",
              TALER_B2S (&master_pub));

  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &currency))
  {
    return GNUNET_SYSERR;
  }
  {
    if (GNUNET_OK !=
        TALER_config_get_amount (cfg,
                                 "taler",
                                 "CURRENCY_ROUND_UNIT",
                                 &currency_round_unit))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid or missing amount in `TALER' under `CURRENCY_ROUND_UNIT'\n");
      return GNUNET_SYSERR;
    }
  }
  if (NULL ==
      (edb = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize exchange database plugin.\n");
    return GNUNET_SYSERR;
  }
  if (NULL ==
      (adb = TALER_AUDITORDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize auditor database plugin.\n");
    TALER_EXCHANGEDB_plugin_unload (edb);
    return GNUNET_SYSERR;
  }
  found = GNUNET_NO;
  as = adb->get_session (adb->cls);
  if (NULL == as)
  {
    fprintf (stderr,
             "Failed to start session with auditor database.\n");
    TALER_AUDITORDB_plugin_unload (adb);
    TALER_EXCHANGEDB_plugin_unload (edb);
    return GNUNET_SYSERR;
  }
  (void) adb->list_exchanges (adb->cls,
                              as,
                              &test_master_present,
                              &found);
  if (GNUNET_NO == found)
  {
    fprintf (stderr,
             "Exchange's master public key `%s' not known to auditor DB. Did you forget to run `taler-auditor-exchange`?\n",
             GNUNET_p2s (&master_pub.eddsa_pub));
    TALER_AUDITORDB_plugin_unload (adb);
    TALER_EXCHANGEDB_plugin_unload (edb);
    return GNUNET_SYSERR;
  }
  if (restart)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Full audit restart requested, dropping old audit data.\n");
    GNUNET_break (GNUNET_OK ==
                  adb->drop_tables (adb->cls,
                                    GNUNET_NO));
    TALER_AUDITORDB_plugin_unload (adb);
    if (NULL ==
        (adb = TALER_AUDITORDB_plugin_load (cfg)))
    {
      fprintf (stderr,
               "Failed to initialize auditor database plugin after drop.\n");
      TALER_EXCHANGEDB_plugin_unload (edb);
      return GNUNET_SYSERR;
    }
    GNUNET_break (GNUNET_OK ==
                  adb->create_tables (adb->cls));
  }

  return GNUNET_OK;
}


void
finish_report (json_t *report)
{
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Audit complete\n");
  TALER_AUDITORDB_plugin_unload (adb);
  adb = NULL;
  TALER_EXCHANGEDB_plugin_unload (edb);
  edb = NULL;
  json_dumpf (report,
              stdout,
              JSON_INDENT (2));
  json_decref (report);
}
