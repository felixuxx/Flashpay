/*
  This file is part of TALER
  Copyright (C) 2016-2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-exchange-aggregator.c
 * @brief Process that aggregates outgoing transactions and prepares their execution
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <pthread.h>
#include "taler_exchangedb_lib.h"
#include "taler_exchangedb_plugin.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_bank_service.h"
#include "taler_dbevents.h"

/**
 * How often do we retry after serialization failures?
 */
#define MAX_RETRIES 5

/**
 * Information about one aggregation process to be executed.  There is
 * at most one of these around at any given point in time.
 * Note that this limits parallelism, and we might want
 * to revise this decision at a later point.
 */
struct AggregationUnit
{
  /**
   * Public key of the merchant.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Transient amount already found aggregated,
   * set only if @e have_transient is true.
   */
  struct TALER_Amount trans;

  /**
   * Total amount to be transferred, before subtraction of @e fees.wire and rounding down.
   */
  struct TALER_Amount total_amount;

  /**
   * Final amount to be transferred (after fee and rounding down).
   */
  struct TALER_Amount final_amount;

  /**
   * Wire fee we charge for @e wp at @e execution_time.
   */
  struct TALER_WireFeeSet fees;

  /**
   * Wire transfer identifier we use.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * The current time (which triggered the aggregation and
   * defines the wire fee).
   */
  struct GNUNET_TIME_Timestamp execution_time;

  /**
   * Wire details of the merchant.
   */
  struct TALER_FullPayto payto_uri;

  /**
   * Selected wire target for the aggregation.
   */
  struct TALER_FullPaytoHashP h_full_payto;

  /**
   * Selected wire target for KYC checks.
   */
  struct TALER_NormalizedPaytoHashP h_normalized_payto;

  /**
   * Exchange wire account to be used for the preparation and
   * eventual execution of the aggregate wire transfer.
   */
  const struct TALER_EXCHANGEDB_AccountInfo *wa;

  /**
   * Handle for asynchronously running AML program.
   */
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *amlh;

  /**
   * Shard this aggregation unit is part of.
   */
  struct Shard *shard;

  /**
   * Handle to async process to obtain the legitimization rules.
   */
  struct TALER_EXCHANGEDB_RuleUpdater *ru;

  /**
   * Row in KYC table for legitimization requirements
   * that are pending for this aggregation, or 0 if none.
   */
  uint64_t requirement_row;

  /**
   * How often did we retry the transaction?
   */
  unsigned int retries;

  /**
   * Should we run a follow-up transaction with a legitimization
   * check?
   */
  bool legi_check;

  /**
   * Do we have an entry in the transient table for
   * this aggregation?
   */
  bool have_transient;

  /**
   * Is the wrong merchant public key associated with
   * the KYC data?
   */
  bool bad_kyc_auth;

};


/**
 * Work shard we are processing.
 */
struct Shard
{

  /**
   * When did we start processing the shard?
   */
  struct GNUNET_TIME_Timestamp start_time;

  /**
   * Starting row of the shard.
   */
  uint32_t shard_start;

  /**
   * Inclusive end row of the shard.
   */
  uint32_t shard_end;

  /**
   * Number of starting points found in the shard.
   */
  uint64_t work_counter;

};


/**
 * What is the smallest unit we support for wire transfers?
 * We will need to round down to a multiple of this amount.
 */
static struct TALER_Amount currency_round_unit;

/**
 * What is the base URL of this exchange?  Used in the
 * wire transfer subjects so that merchants and governments
 * can ask for the list of aggregated deposits.
 */
static char *exchange_base_url;

/**
 * Set to #GNUNET_YES if this exchange does not support KYC checks
 * and thus deposits are to be aggregated regardless of the
 * KYC status of the target account.
 */
static int kyc_off;

/**
 * The exchange's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Key used to encrypt KYC attribute data in our database.
 */
static struct TALER_AttributeEncryptionKeyP attribute_key;

/**
 * Our database plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *db_plugin;

/**
 * Next task to run, if any.
 */
static struct GNUNET_SCHEDULER_Task *task;

/**
 * How long should we sleep when idle before trying to find more work?
 */
static struct GNUNET_TIME_Relative aggregator_idle_sleep_interval;

/**
 * How big are the shards we are processing? Is an inclusive offset, so every
 * shard ranges from [X,X+shard_size) exclusive.  So a shard covers
 * shard_size slots.  The maximum value for shard_size is INT32_MAX+1.
 */
static uint32_t shard_size;

/**
 * Value to return from main(). 0 on success, non-zero on errors.
 */
static int global_ret;

/**
 * #GNUNET_YES if we are in test mode and should exit when idle.
 */
static int test_mode;


/**
 * Main work function that queries the DB and aggregates transactions
 * into larger wire transfers.
 *
 * @param cls a `struct Shard *`
 */
static void
run_aggregation (void *cls);


/**
 * Work on transactions unlocked by KYC.
 *
 * @param cls NULL
 */
static void
drain_kyc_alerts (void *cls);


/**
 * Free data stored in @a au, including @a au itself.
 *
 * @param[in] au aggregation unit to clean up
 */
static void
cleanup_au (struct AggregationUnit *au)
{
  GNUNET_assert (NULL != au);
  if (NULL != au->amlh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Aborting AML program during aggregation cleanup\n");
    TALER_KYCLOGIC_run_aml_program_cancel (au->amlh);
    au->amlh = NULL;
  }
  if (NULL != au->ru)
  {
    GNUNET_break (0);
    TALER_EXCHANGEDB_update_rules_cancel (au->ru);
    au->ru = NULL;
  }
  GNUNET_free (au->payto_uri.full_payto);
  GNUNET_free (au);
}


/**
 * Perform a database commit. If it fails, print a warning.
 *
 * @return status of commit
 */
static enum GNUNET_DB_QueryStatus
commit_or_warn (void)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = db_plugin->commit (db_plugin->cls);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return qs;
  GNUNET_log ((GNUNET_DB_STATUS_SOFT_ERROR == qs)
              ? GNUNET_ERROR_TYPE_INFO
              : GNUNET_ERROR_TYPE_ERROR,
              "Failed to commit database transaction!\n");
  return qs;
}


/**
 * Release lock on shard @a s in the database.
 * On error, terminates this process.
 *
 * @param[in] s shard to free (and memory to release)
 */
static void
release_shard (struct Shard *s)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = db_plugin->release_revolving_shard (
    db_plugin->cls,
    "aggregator",
    s->shard_start,
    s->shard_end);
  GNUNET_free (s);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* Strange, but let's just continue */
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* normal case */
    break;
  }
}


/**
 * Schedule the next major task, or exit depending on mode.
 */
static void
next_task (uint64_t counter)
{
  if ( (GNUNET_YES == test_mode) &&
       (0 == counter) )
  {
    /* in test mode, shutdown after a shard is done with 0 work */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "No work done and in test mode, shutting down\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_assert (NULL == task);
  /* If we ended up doing zero work, sleep a bit */
  if (0 == counter)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Going to sleep for %s before trying again\n",
                GNUNET_TIME_relative2s (aggregator_idle_sleep_interval,
                                        true));
    task = GNUNET_SCHEDULER_add_delayed (aggregator_idle_sleep_interval,
                                         &drain_kyc_alerts,
                                         NULL);
  }
  else
  {
    task = GNUNET_SCHEDULER_add_now (&drain_kyc_alerts,
                                     NULL);
  }
}


/**
 * Rollback the current transaction (if any),
 * then free data stored in @a au, including @a au itself, and then
 * run the next aggregation task.
 *
 * @param[in] au aggregation unit to clean up
 */
static void
cleanup_and_next (struct AggregationUnit *au)
{
  struct Shard *s = au->shard;
  uint64_t counter = (NULL == s) ? 0 : s->work_counter;

  /* just in case, often no transaction is running here anymore */
  db_plugin->rollback (db_plugin->cls);
  cleanup_au (au);
  if (NULL != s)
    release_shard (s);
  if (EXIT_SUCCESS == global_ret)
    next_task (counter);
}


/**
 * We're being aborted with CTRL-C (or SIGTERM). Shut down.
 *
 * @param cls closure
 */
static void
shutdown_task (void *cls)
{
  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Running shutdown\n");
  if (NULL != task)
  {
    GNUNET_SCHEDULER_cancel (task);
    task = NULL;
  }
  TALER_KYCLOGIC_kyc_done ();
  TALER_EXCHANGEDB_plugin_unload (db_plugin);
  db_plugin = NULL;
  TALER_EXCHANGEDB_unload_accounts ();
  cfg = NULL;
}


/**
 * Parse the configuration for aggregator.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_aggregator_config (void)
{
  enum GNUNET_GenericReturnValue enable_kyc;

  enable_kyc
    = GNUNET_CONFIGURATION_get_value_yesno (
        cfg,
        "exchange",
        "ENABLE_KYC");
  if (GNUNET_SYSERR == enable_kyc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Need YES or NO in section `exchange' under `ENABLE_KYC'\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == enable_kyc)
  {
    kyc_off = true;
  }
  else
  {
    char *attr_enc_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange",
                                               "ATTRIBUTE_ENCRYPTION_KEY",
                                               &attr_enc_key_str))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "ATTRIBUTE_ENCRYPTION_KEY");
      return GNUNET_SYSERR;
    }
    GNUNET_CRYPTO_hash (attr_enc_key_str,
                        strlen (attr_enc_key_str),
                        &attribute_key.hash);
    GNUNET_free (attr_enc_key_str);
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &exchange_base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchange",
                                           "AGGREGATOR_IDLE_SLEEP_INTERVAL",
                                           &aggregator_idle_sleep_interval))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "AGGREGATOR_IDLE_SLEEP_INTERVAL");
    return GNUNET_SYSERR;
  }
  if ( (GNUNET_OK !=
        TALER_config_get_amount (cfg,
                                 "exchange",
                                 "CURRENCY_ROUND_UNIT",
                                 &currency_round_unit)) ||
       (TALER_amount_is_zero (&currency_round_unit)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Need non-zero amount in section `exchange' under `CURRENCY_ROUND_UNIT'\n");
    return GNUNET_SYSERR;
  }

  if (NULL ==
      (db_plugin = TALER_EXCHANGEDB_plugin_load (cfg,
                                                 false)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_load_accounts (cfg,
                                      TALER_EXCHANGEDB_ALO_DEBIT))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No wire accounts configured for debit!\n");
    TALER_EXCHANGEDB_plugin_unload (db_plugin);
    db_plugin = NULL;
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Callback to return all applicable amounts for the KYC
 * decision to @ a cb.
 *
 * @param cls a `struct AggregationUnit *`
 * @param limit time limit for the iteration
 * @param cb function to call with the amounts
 * @param cb_cls closure for @a cb
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
return_relevant_amounts (void *cls,
                         struct GNUNET_TIME_Absolute limit,
                         TALER_EXCHANGEDB_KycAmountCallback cb,
                         void *cb_cls)
{
  const struct AggregationUnit *au = cls;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Returning amount %s in KYC check\n",
              TALER_amount2s (&au->total_amount));
  if (GNUNET_OK !=
      cb (cb_cls,
          &au->total_amount,
          GNUNET_TIME_absolute_get ()))
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  qs = db_plugin->select_aggregation_amounts_for_kyc_check (
    db_plugin->cls,
    &au->h_normalized_payto,
    limit,
    cb,
    cb_cls);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to select aggregation amounts for KYC limit check!\n");
  }
  return qs;
}


/**
 * The aggregation process failed hard, shut down the program.
 *
 * @param[in] au aggregation that failed hard
 */
static void
fail_aggregation (struct AggregationUnit *au)
{
  struct Shard *s = au->shard;

  cleanup_au (au);
  global_ret = EXIT_FAILURE;
  GNUNET_SCHEDULER_shutdown ();
  db_plugin->rollback (db_plugin->cls);
  release_shard (s);
}


/**
 * Run the next task with the given shard @a s.
 *
 * @param s shard to run, NULL to run more drain jobs
 */
static void
run_task_with_shard (struct Shard *s)
{
  GNUNET_assert (NULL == task);
  if (NULL == s)
    task = GNUNET_SCHEDULER_add_now (&drain_kyc_alerts,
                                     NULL);
  else
    task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                     s);
}


/**
 * The aggregation process failed with a serialization
 * issue.  Rollback the transaction and try again.
 *
 * @param[in] au aggregation that needs to be rolled back
 */
static void
rollback_aggregation (struct AggregationUnit *au)
{
  struct Shard *s = au->shard;

  cleanup_au (au);
  db_plugin->rollback (db_plugin->cls);
  run_task_with_shard (s);
}


/**
 * Function called with legitimization rule set. Check
 * how that affects the aggregation process.
 *
 * @param[in] cls a `struct AggregationUnit *`
 * @param[in] rur new legitimization rule set to evaluate
 */
static void
evaluate_rules (
  void *cls,
  struct TALER_EXCHANGEDB_RuleUpdaterResult *rur);


/**
 * The aggregation process succeeded and should be finally committed.
 *
 * @param[in] au aggregation that needs to be committed
 */
static void
commit_aggregation (struct AggregationUnit *au)
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Committing aggregation result over %s to %s\n",
              TALER_amount2s (&au->final_amount),
              au->payto_uri.full_payto);
  /* Now we can finally commit the overall transaction, as we are
     again consistent if all of this passes. */
  switch (commit_or_warn ())
  {
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* try again */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Serialization issue on commit; trying again later!\n");
    cleanup_and_next (au);
    return;
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    cleanup_and_next (au);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Commit complete, going again\n");
    if (au->legi_check)
    {
      au->legi_check = false;
      au->ru = TALER_EXCHANGEDB_update_rules (
        db_plugin,
        &attribute_key,
        &au->h_normalized_payto,
        &evaluate_rules,
        au);
      if (NULL != au->ru)
        return;
    }
    cleanup_and_next (au);
    return;
  default:
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    cleanup_and_next (au);
    return;
  }
}


/**
 * Trigger the wire transfer for the @a au
 * and delete the record of the aggregation.
 *
 * @param[in] au information about the aggregation
 */
static void
trigger_wire_transfer (struct AggregationUnit *au)
{
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Preparing wire transfer of %s to %s\n",
              TALER_amount2s (&au->final_amount),
              TALER_B2S (&au->merchant_pub));
  {
    void *buf;
    size_t buf_size;

    TALER_BANK_prepare_transfer (au->payto_uri,
                                 &au->final_amount,
                                 exchange_base_url,
                                 &au->wtid,
                                 &buf,
                                 &buf_size);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Storing %u bytes of wire prepare data\n",
                (unsigned int) buf_size);
    /* Commit our intention to execute the wire transfer! */
    qs = db_plugin->wire_prepare_data_insert (db_plugin->cls,
                                              au->wa->method,
                                              buf,
                                              buf_size);
    GNUNET_log (qs >= 0
                ? GNUNET_ERROR_TYPE_DEBUG
                : GNUNET_ERROR_TYPE_WARNING,
                "wire_prepare_data_insert returned %d\n",
                (int) qs);
    GNUNET_free (buf);
  }
  /* Commit the WTID data to 'wire_out'  */
  if (qs >= 0)
  {
    qs = db_plugin->store_wire_transfer_out (
      db_plugin->cls,
      au->execution_time,
      &au->wtid,
      &au->h_full_payto,
      au->wa->section_name,
      &au->final_amount);
    GNUNET_log (qs >= 0
                ? GNUNET_ERROR_TYPE_DEBUG
                : GNUNET_ERROR_TYPE_WARNING,
                "store_wire_transfer_out returned %d\n",
                (int) qs);
  }
  if ( (qs >= 0) &&
       au->have_transient)
    qs = db_plugin->delete_aggregation_transient (
      db_plugin->cls,
      &au->h_full_payto,
      &au->wtid);

  switch (qs)
  {
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_log (
      GNUNET_ERROR_TYPE_INFO,
      "Serialization issue during aggregation; trying again later!\n");
    rollback_aggregation (au);
    return;
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    fail_aggregation (au);
    return;
  default:
    break;
  }
  {
    struct TALER_CoinDepositEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_DEPOSIT_STATUS_CHANGED),
      .merchant_pub = au->merchant_pub
    };

    db_plugin->event_notify (db_plugin->cls,
                             &rep.header,
                             NULL,
                             0);
  }
  commit_aggregation (au);
}


static void
evaluate_rules (
  void *cls,
  struct TALER_EXCHANGEDB_RuleUpdaterResult *rur)
{
  struct AggregationUnit *au = cls;
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs = rur->lrs;
  enum GNUNET_DB_QueryStatus qs;
  const struct TALER_KYCLOGIC_KycRule *requirement;

  au->ru = NULL;
  if (TALER_EC_NONE != rur->ec)
  {
    if (NULL != lrs)
    {
      /* strange, but whatever */
      TALER_KYCLOGIC_rules_free (lrs);
    }
    /* Rollback just in case, should have already been done
       before by the TALER_EXCHANGEDB_update_rules() logic. */
    db_plugin->rollback (db_plugin->cls);
    if ( (TALER_EC_GENERIC_DB_SOFT_FAILURE == rur->ec) &&
         (au->retries++ < MAX_RETRIES) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Serialization failure, trying again!\n");
      au->ru = TALER_EXCHANGEDB_update_rules (
        db_plugin,
        &attribute_key,
        &au->h_normalized_payto,
        &evaluate_rules,
        au);
      if (NULL != au->ru)
        return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "KYC rule evaluation failed hard: %s (%d, %s)\n",
                TALER_ErrorCode_get_hint (rur->ec),
                (int) rur->ec,
                rur->hint);
    cleanup_and_next (au);
    return;
  }

  /* Note that here we are in an open transaction that fetched
     (or updated) the current set of legitimization rules. So
     we must properly commit at the end! */
  {
    struct TALER_Amount next_threshold;

    qs = TALER_KYCLOGIC_kyc_test_required (
      TALER_KYCLOGIC_KYC_TRIGGER_AGGREGATE,
      lrs,
      &return_relevant_amounts,
      (void *) au,
      &requirement,
      &next_threshold);
  }
  if (qs < 0)
  {
    TALER_KYCLOGIC_rules_free (lrs);
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cleanup_and_next (au);
    return;
  }
  if (NULL == requirement)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC check clear, proceeding with wire transfer\n");
    TALER_KYCLOGIC_rules_free (lrs);
    trigger_wire_transfer (au);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC requirement for %s is %s\n",
              TALER_amount2s (&au->total_amount),
              TALER_KYCLOGIC_rule2s (requirement));
  {
    json_t *jrule;

    jrule = TALER_KYCLOGIC_rule_to_measures (requirement);
    qs = db_plugin->trigger_kyc_rule_for_account (
      db_plugin->cls,
      au->payto_uri,
      &au->h_normalized_payto,
      NULL,
      &au->merchant_pub,
      jrule,
      TALER_KYCLOGIC_rule2priority (requirement),
      &au->requirement_row,
      &au->bad_kyc_auth);
    json_decref (jrule);
  }
  if (qs < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to persist KYC requirement `%s' in DB!\n",
                TALER_KYCLOGIC_rule2s (requirement));
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      global_ret = EXIT_FAILURE;
    cleanup_and_next (au);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Legitimization process %llu started\n",
              (unsigned long long) au->requirement_row);
  TALER_KYCLOGIC_rules_free (lrs);

  qs = db_plugin->update_aggregation_transient (db_plugin->cls,
                                                &au->h_full_payto,
                                                &au->wtid,
                                                au->requirement_row,
                                                &au->total_amount);


  if (qs < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to persist updated transient in in DB!\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      global_ret = EXIT_FAILURE;
    cleanup_and_next (au);
    return;
  }

  {
    struct TALER_CoinDepositEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_DEPOSIT_STATUS_CHANGED),
      .merchant_pub = au->merchant_pub
    };

    db_plugin->event_notify (db_plugin->cls,
                             &rep.header,
                             NULL,
                             0);
  }

  /* First commit, turns the rollback in cleanup into a NOP! */
  commit_or_warn ();
  cleanup_and_next (au);
}


/**
 * The aggregation process could not be concluded and its progress state
 * should be remembered in a transient aggregation.
 *
 * @param[in] au aggregation that needs to be committed
 *     into a transient aggregation
 */
static void
commit_to_transient (struct AggregationUnit *au)
{
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Not ready for wire transfer (%s)\n",
              TALER_amount2s (&au->final_amount));
  if (au->have_transient)
    qs = db_plugin->update_aggregation_transient (db_plugin->cls,
                                                  &au->h_full_payto,
                                                  &au->wtid,
                                                  au->requirement_row,
                                                  &au->total_amount);
  else
    qs = db_plugin->create_aggregation_transient (db_plugin->cls,
                                                  &au->h_full_payto,
                                                  au->wa->section_name,
                                                  &au->merchant_pub,
                                                  &au->wtid,
                                                  au->requirement_row,
                                                  &au->total_amount);
  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Serialization issue, trying again later!\n");
    rollback_aggregation (au);
    return;
  }
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    fail_aggregation (au);
    return;
  }
  au->have_transient = true;
  /* commit */
  commit_aggregation (au);
}


/**
 * Test if legitimization rules are satisfied for a transfer to @a h_payto.
 *
 * @param[in] au aggregation unit to check for
 */
static void
check_legitimization_satisfied (struct AggregationUnit *au)
{
  if (kyc_off)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC checks are off, legitimization satisfied\n");
    trigger_wire_transfer (au);
    return;
  }
  /* get legi rules *after* committing, as the legi check
     should run in a separate transaction! */
  au->legi_check = true;
  commit_to_transient (au);
}


/**
 * Perform the main aggregation work for @a au.  Expects to be in
 * a working transaction, which the caller must also ultimately commit
 * (or rollback) depending on our return value.
 *
 * @param[in,out] au aggregation unit to work on
 */
static void
do_aggregate (struct AggregationUnit *au)
{
  enum GNUNET_DB_QueryStatus qs;

  au->wa = TALER_EXCHANGEDB_find_account_by_payto_uri (
    au->payto_uri);
  if (NULL == au->wa)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No exchange account configured for `%s', please fix your setup to continue!\n",
                au->payto_uri.full_payto);
    global_ret = EXIT_FAILURE;
    fail_aggregation (au);
    return;
  }

  {
    struct GNUNET_TIME_Timestamp start_date;
    struct GNUNET_TIME_Timestamp end_date;
    struct TALER_MasterSignatureP master_sig;

    qs = db_plugin->get_wire_fee (db_plugin->cls,
                                  au->wa->method,
                                  au->execution_time,
                                  &start_date,
                                  &end_date,
                                  &au->fees,
                                  &master_sig);
    if (0 >= qs)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Could not get wire fees for %s at %s. Aborting run.\n",
                  au->wa->method,
                  GNUNET_TIME_timestamp2s (au->execution_time));
      fail_aggregation (au);
      return;
    }
  }

  /* Now try to find other deposits to aggregate */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Found ready deposit for %s, aggregating by target %s\n",
              TALER_B2S (&au->merchant_pub),
              au->payto_uri.full_payto);
  qs = db_plugin->select_aggregation_transient (db_plugin->cls,
                                                &au->h_full_payto,
                                                &au->merchant_pub,
                                                au->wa->section_name,
                                                &au->wtid,
                                                &au->trans);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to lookup transient aggregates!\n");
    fail_aggregation (au);
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    /* serializiability issue, try again */
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Serialization issue, trying again later!\n");
    rollback_aggregation (au);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                                &au->wtid,
                                sizeof (au->wtid));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "No transient aggregation found, starting %s\n",
                TALER_B2S (&au->wtid));
    au->have_transient = false;
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    au->have_transient = true;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Transient aggregation found, resuming %s\n",
                TALER_B2S (&au->wtid));
    break;
  }
  qs = db_plugin->aggregate (db_plugin->cls,
                             &au->h_full_payto,
                             &au->merchant_pub,
                             &au->wtid,
                             &au->total_amount);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to execute aggregation!\n");
    fail_aggregation (au);
    return;
  }
  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
  {
    /* serializiability issue, try again */
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Serialization issue, trying again later!\n");
    rollback_aggregation (au);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Aggregation total is %s.\n",
              TALER_amount2s (&au->total_amount));
  /* Subtract wire transfer fee and round to the unit supported by the
     wire transfer method; Check if after rounding down, we still have
     an amount to transfer, and if not mark as 'tiny'. */
  if (au->have_transient)
    GNUNET_assert (0 <=
                   TALER_amount_add (&au->total_amount,
                                     &au->total_amount,
                                     &au->trans));


  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Rounding aggregate of %s\n",
              TALER_amount2s (&au->total_amount));
  if ( (0 >=
        TALER_amount_subtract (&au->final_amount,
                               &au->total_amount,
                               &au->fees.wire)) ||
       (GNUNET_SYSERR ==
        TALER_amount_round_down (&au->final_amount,
                                 &currency_round_unit)) ||
       (TALER_amount_is_zero (&au->final_amount)) )
  {
    commit_to_transient (au);
    return;
  }
  check_legitimization_satisfied (au);
}


static void
run_aggregation (void *cls)
{
  struct Shard *s = cls;
  struct AggregationUnit *au;
  enum GNUNET_DB_QueryStatus qs;

  task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking for ready deposits to aggregate\n");
  /* make sure we have current fees */
  au = GNUNET_new (struct AggregationUnit);
  au->execution_time = GNUNET_TIME_timestamp_get ();
  au->shard = s;
  if (GNUNET_OK !=
      db_plugin->start_deferred_wire_out (db_plugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    release_shard (s);
    return;
  }
  qs = db_plugin->get_ready_deposit (
    db_plugin->cls,
    s->shard_start,
    s->shard_end,
    &au->merchant_pub,
    &au->payto_uri);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to begin deposit iteration!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    cleanup_and_next (au);
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    cleanup_au (au);
    db_plugin->rollback (db_plugin->cls);
    run_task_with_shard (s);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    {
      struct GNUNET_TIME_Relative duration
        = GNUNET_TIME_absolute_get_duration (s->start_time.abs_time);

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Completed shard [%u,%u] after %s with %llu deposits\n",
                  (unsigned int) s->shard_start,
                  (unsigned int) s->shard_end,
                  GNUNET_TIME_relative2s (duration,
                                          true),
                  (unsigned long long) s->work_counter);
      cleanup_and_next (au);
      return;
    }
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    s->work_counter++;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Found ready deposit!\n");
    /* continued below */
    break;
  }

  TALER_full_payto_hash (au->payto_uri,
                         &au->h_full_payto);
  TALER_full_payto_normalize_and_hash (au->payto_uri,
                                       &au->h_normalized_payto);
  do_aggregate (au);
}


/**
 * Select a shard to work on.
 *
 * @param cls NULL
 */
static void
run_shard (void *cls)
{
  struct Shard *s;
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Running aggregation shard\n");
  if (GNUNET_SYSERR ==
      db_plugin->preflight (db_plugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database connection!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  s = GNUNET_new (struct Shard);
  s->start_time = GNUNET_TIME_timestamp_get ();
  qs = db_plugin->begin_revolving_shard (db_plugin->cls,
                                         "aggregator",
                                         shard_size,
                                         1U + INT32_MAX,
                                         &s->shard_start,
                                         &s->shard_end);
  if (0 >= qs)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      static struct GNUNET_TIME_Relative delay;

      GNUNET_free (s);
      delay = GNUNET_TIME_randomized_backoff (delay,
                                              GNUNET_TIME_UNIT_SECONDS);
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_delayed (delay,
                                           &run_shard,
                                           NULL);
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to begin shard (%d)!\n",
                qs);
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting shard [%u:%u]!\n",
              (unsigned int) s->shard_start,
              (unsigned int) s->shard_end);
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&run_aggregation,
                                   s);
}


/**
 * Function called on transient aggregations matching
 * a particular hash of a payto URI.
 *
 * @param cls
 * @param payto_uri corresponding payto URI
 * @param wtid wire transfer identifier of transient aggregation
 * @param merchant_pub public key of the merchant
 * @param total amount aggregated so far
 * @return true to continue to iterate
 */
static bool
handle_transient_cb (
  void *cls,
  const struct TALER_FullPayto payto_uri,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_Amount *total)
{
  struct AggregationUnit *au = cls;

  au->payto_uri.full_payto
    = GNUNET_strdup (payto_uri.full_payto);
  TALER_full_payto_hash (payto_uri,
                         &au->h_full_payto);
  au->wtid = *wtid;
  au->merchant_pub = *merchant_pub;
  au->trans = *total;
  au->have_transient = true;
  do_aggregate (au);
  return false;
}


static void
drain_kyc_alerts (void *cls)
{
  enum GNUNET_DB_QueryStatus qs;
  struct AggregationUnit *au;

  (void) cls;
  task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Draining KYC alerts\n");
  au = GNUNET_new (struct AggregationUnit);
  au->execution_time = GNUNET_TIME_timestamp_get ();
  if (GNUNET_SYSERR ==
      db_plugin->preflight (db_plugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database connection!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK !=
      db_plugin->start (db_plugin->cls,
                        "handle kyc alerts"))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  while (1)
  {
    qs = db_plugin->drain_kyc_alert (db_plugin->cls,
                                     1,
                                     &au->h_normalized_payto);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Found %d KYC alerts\n",
                (int) qs);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      db_plugin->rollback (db_plugin->cls);
      GNUNET_free (au);
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&drain_kyc_alerts,
                                       NULL);
      return;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      db_plugin->rollback (db_plugin->cls);
      GNUNET_assert (NULL == task);
      GNUNET_free (au);
      task = GNUNET_SCHEDULER_add_now (&drain_kyc_alerts,
                                       NULL);
      return;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      GNUNET_free (au);
      qs = db_plugin->commit (db_plugin->cls);
      if (qs < 0)
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to commit KYC drain\n");
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&run_shard,
                                       NULL);
      return;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      /* handled below */
      break;
    }

    /* FIXME: should be replaced with a query that has a LIMIT 1... */
    qs = db_plugin->find_aggregation_transient (db_plugin->cls,
                                                &au->h_normalized_payto,
                                                &handle_transient_cb,
                                                au);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to lookup transient aggregates!\n");
      db_plugin->rollback (db_plugin->cls);
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&drain_kyc_alerts,
                                       NULL);
      return;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      /* serializiability issue, try again */
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Serialization issue, trying again later!\n");
      db_plugin->rollback (db_plugin->cls);
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&drain_kyc_alerts,
                                       NULL);
      return;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      continue; /* while (1) */
    default:
      /* handle_transient_cb has various continuations... */
      return;
    }
    GNUNET_assert (0);
  } /* while(1) */
}


/**
 * First task.
 *
 * @param cls closure, NULL
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param c configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *c)
{
  unsigned long long ass;
  (void) cls;
  (void) args;
  (void) cfgfile;

  cfg = c;
  if (GNUNET_OK !=
      parse_aggregator_config ())
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "exchange",
                                             "AGGREGATOR_SHARD_SIZE",
                                             &ass))
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if ( (0 == ass) ||
       (ass > INT32_MAX) )
    shard_size = 1U + INT32_MAX;
  else
    shard_size = (uint32_t) ass;
  if (GNUNET_OK !=
      TALER_KYCLOGIC_kyc_init (cfg,
                               cfgfile))
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 NULL);
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&drain_kyc_alerts,
                                   NULL);
}


/**
 * The main function of the taler-exchange-aggregator.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, non-zero on error, see #global_ret
 */
int
main (int argc,
      char *const *argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_option_flag ('t',
                               "test",
                               "run in test mode and exit when idle",
                               &test_mode),
    GNUNET_GETOPT_option_flag ('y',
                               "kyc-off",
                               "perform wire transfers without KYC checks",
                               &kyc_off),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  ret = GNUNET_PROGRAM_run (
    TALER_EXCHANGE_project_data (),
    argc, argv,
    "taler-exchange-aggregator",
    gettext_noop (
      "background process that aggregates and executes wire transfers"),
    options,
    &run, NULL);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-aggregator.c */
