/*
  This file is part of TALER
  Copyright (C) 2016, 2017 Inria

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
 * @file auditor/taler-auditor.c
 * @brief audits an exchange database.
 * @author Christian Grothoff
 *
 * NOTE:
 * - This auditor does not verify that 'reserves_in' actually matches
 *   the wire transfers from the bank. This needs to be checked separately!
 * - Similarly, we do not check that the outgoing wire transfers match those
 *   given in the XXX table. This needs to be checked separately!
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_plugin.h"
#include "taler_signatures.h"


/**
 * Return value from main().
 */
static int global_ret;

/**
 * Handle to access the exchange's database.
 */
static struct TALER_EXCHANGEDB_Plugin *edb;

/**
 * Our session with the #edb.
 */
static struct TALER_EXCHANGEDB_Session *esession;

/**
 * Handle to access the auditor's database.
 */
static struct TALER_AUDITORDB_Plugin *adb;

/**
 * Our session with the #adb.
 */
static struct TALER_AUDITORDB_Session *asession;

/**
 * Master public key of the exchange to audit.
 */
static struct TALER_MasterPublicKeyP master_pub;

/**
 * Last reserve_in serial ID seen.
 */
static uint64_t reserve_in_serial_id;

/**
 * Last reserve_out serial ID seen.
 */
static uint64_t reserve_out_serial_id;

/**
 * Last deposit serial ID seen.
 */
static uint64_t deposit_serial_id;

/**
 * Last melt serial ID seen.
 */
static uint64_t melt_serial_id;

/**
 * Last deposit refund ID seen.
 */
static uint64_t refund_serial_id;

/**
 * Last prewire serial ID seen.
 */
static uint64_t prewire_serial_id;


/* ***************************** Report logic **************************** */

/**
 * Report a (serious) inconsistency in the exchange's database.
 *
 * @param table affected table
 * @param rowid affected row, UINT64_MAX if row is missing
 * @param diagnostic message explaining the problem
 */
static void
report_row_inconsistency (const char *table,
                          uint64_t rowid,
                          const char *diagnostic)
{
  // TODO: implement proper reporting logic writing to file.
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Database inconsistency detected in table %s at row %llu: %s\n",
              table,
              (unsigned long long) rowid,
              diagnostic);
}


/**
 * Report a global inconsistency with respect to a reserve.
 *
 * @param reserve_pub the affected reserve
 * @param expected expected amount
 * @param observed observed amount
 * @param diagnostic message explaining what @a expected and @a observed refer to
 */
static void
report_reserve_inconsistency (const struct TALER_ReservePublicKeyP *reserve_pub,
                              const struct TALER_Amount *expected,
                              const struct TALER_Amount *observed,
                              const char *diagnostic)
{
  // TODO: implement proper reporting logic writing to file, include amounts.
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Reserve inconsistency detected affecting reserve %s: %s\n",
              TALER_B2S (reserve_pub),
              diagnostic);
}


/* ************************* Transaction-global state ************************ */

/**
 * Results about denominations, cached per-transaction.
 */
static struct GNUNET_CONTAINER_MultiHashMap *denominations;


/**
 * Obtain information about a @a denom_pub.
 *
 * @param denom_pub key to look up
 * @param[out] set to the hash of @a denom_pub, may be NULL
 * @param[out] dki set to detailed information about @a denom_pub, NULL if not found, must
 *                 NOT be freed by caller
 * @return #GNUNET_OK on success, #GNUNET_NO for not found, #GNUNET_SYSERR for DB error
 */
static int
get_denomination_info (const struct TALER_DenominationPublicKey *denom_pub,
                       const struct TALER_EXCHANGEDB_DenominationKeyInformationP **dki,
                       struct GNUNET_HashCode *dh)
{
  struct GNUNET_HashCode hc;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP *dkip;
  int ret;

  if (NULL == dh)
    dh = &hc;
  GNUNET_CRYPTO_rsa_public_key_hash (denom_pub->rsa_public_key,
                                     dh);
  dkip = GNUNET_CONTAINER_multihashmap_get (denominations,
                                            dh);
  if (NULL != dkip)
    {
      /* cache hit */
      *dki = dkip;
      return GNUNET_OK;
    }
  dkip = GNUNET_new (struct TALER_EXCHANGEDB_DenominationKeyInformationP);
  ret = edb->get_denomination_info (edb->cls,
                                    esession,
                                    denom_pub,
                                    dkip);
  if (GNUNET_OK != ret)
  {
    GNUNET_free (dkip);
    GNUNET_break (GNUNET_NO == ret);
    *dki = NULL;
    return ret;
  }
  *dki = dkip;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (denominations,
                                                    dh,
                                                    dkip,
                                                    GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  return GNUNET_OK;
}


/**
 * Free denomination key information.
 *
 * @param cls NULL
 * @param key unused
 * @param value the `struct TALER_EXCHANGEDB_DenominationKeyInformationP *` to free
 * @return #GNUNET_OK (continue to iterate)
 */
static int
free_dk_info (void *cls,
              const struct GNUNET_HashCode *key,
              void *value)
{
  struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki = value;

  GNUNET_free (dki);
  return GNUNET_OK;
}


/**
 * Purge transaction global state cache, the transaction is
 * done and we do not want to have the state cross over to
 * the next transaction.
 */
static void
clear_transaction_state_cache ()
{
  if (NULL == denominations)
    return;
  GNUNET_CONTAINER_multihashmap_iterate (denominations,
                                         &free_dk_info,
                                         NULL);
  GNUNET_CONTAINER_multihashmap_destroy (denominations);
  denominations = NULL;
}


/* ***************************** Analyze reserves ************************ */

/**
 * Summary data we keep per reserve.
 */
struct ReserveSummary
{
  /**
   * Public key of the reserve.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Sum of all incoming transfers.
   */
  struct TALER_Amount total_in;

  /**
   * Sum of all outgoing transfers.
   */
  struct TALER_Amount total_out;

  /**
   * Previous balance of the reserve as remembered by the auditor.
   */
  struct TALER_Amount a_balance;

  /**
   * Previous withdraw fee balance of the reserve, as remembered by the auditor.
   */
  struct TALER_Amount a_withdraw_fee_balance;

  /**
   * Previous reserve expiration data, as remembered by the auditor.
   */
  struct GNUNET_TIME_Absolute a_expiration_date;

  /**
   * Previous last processed reserve_in serial ID, as remembered by the auditor.
   */
  uint64_t a_last_reserve_in_serial_id;

  /**
   * Previous last processed reserve_out serial ID, as remembered by the auditor.
   */
  uint64_t a_last_reserve_out_serial_id;

  /**
   * Did we have a previous reserve info?
   */
  int had_ri;

};


/**
 * Load the auditor's remembered state about the reserve into @a rs.
 *
 * @param[in|out] rs reserve summary to (fully) initialize
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on DB errors
 */
static int
load_auditor_reserve_summary (struct ReserveSummary *rs)
{
  int ret;

  ret = adb->get_reserve_info (adb->cls,
                               asession,
                               &rs->reserve_pub,
                               &master_pub,
                               &rs->a_balance,
                               &rs->a_withdraw_fee_balance,
                               &rs->a_expiration_date,
                               &rs->a_last_reserve_in_serial_id,
                               &rs->a_last_reserve_out_serial_id);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == ret)
  {
    rs->had_ri = GNUNET_NO;
    // FIXME: set rs->a-values to sane defaults!
    return GNUNET_OK;
  }
  rs->had_ri = GNUNET_YES;
  /* TODO: check values we got are sane? */
  return GNUNET_OK;
}


/**
 * Function called with details about incoming wire transfers.
 *
 * @param cls our `struct GNUNET_CONTAINER_MultiHashMap` with the reserves
 * @param rowid unique serial ID for the refresh session in our DB
 * @param reserve_pub public key of the reserve (also the WTID)
 * @param credit amount that was received
 * @param sender_account_details information about the sender's bank account
 * @param transfer_details information that uniquely identifies the wire transfer
 * @param execution_date when did we receive the funds
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
handle_reserve_in (void *cls,
                   uint64_t rowid,
                   const struct TALER_ReservePublicKeyP *reserve_pub,
                   const struct TALER_Amount *credit,
                   const json_t *sender_account_details,
                   const json_t *transfer_details,
                   struct GNUNET_TIME_Absolute execution_date)
{
  struct GNUNET_CONTAINER_MultiHashMap *reserves = cls;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;

  GNUNET_assert (rowid >= reserve_in_serial_id); /* should be monotonically increasing */
  reserve_in_serial_id = rowid + 1;
  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->reserve_pub = *reserve_pub;
    rs->total_in = *credit;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (credit->currency,
                                          &rs->total_out));
    if (GNUNET_OK !=
        load_auditor_reserve_summary (rs))
    {
      GNUNET_break (0);
      GNUNET_free (rs);
      return GNUNET_SYSERR;
    }
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (reserves,
                                                      &key,
                                                      rs,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  else
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&rs->total_in,
                                     &rs->total_in,
                                     credit));
  }
  return GNUNET_OK;
}


/**
 * Function called with details about withdraw operations.
 *
 * @param cls our `struct GNUNET_CONTAINER_MultiHashMap` with the reserves
 * @param rowid unique serial ID for the refresh session in our DB
 * @param h_blind_ev blinded hash of the coin's public key
 * @param denom_pub public denomination key of the deposited coin
 * @param denom_sig signature over the deposited coin
 * @param reserve_pub public key of the reserve
 * @param reserve_sig signature over the withdraw operation
 * @param execution_date when did the wallet withdraw the coin
 * @param amount_with_fee amount that was withdrawn
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
handle_reserve_out (void *cls,
                    uint64_t rowid,
                    const struct GNUNET_HashCode *h_blind_ev,
                    const struct TALER_DenominationPublicKey *denom_pub,
                    const struct TALER_DenominationSignature *denom_sig,
                    const struct TALER_ReservePublicKeyP *reserve_pub,
                    const struct TALER_ReserveSignatureP *reserve_sig,
                    struct GNUNET_TIME_Absolute execution_date,
                    const struct TALER_Amount *amount_with_fee)
{
  struct GNUNET_CONTAINER_MultiHashMap *reserves = cls;
  struct TALER_WithdrawRequestPS wsrd;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  int ret;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= reserve_out_serial_id);
  reserve_out_serial_id = rowid + 1;

  /* lookup denomination pub data (make sure denom_pub is valid, establish fees) */
  ret = get_denomination_info (denom_pub,
                               &dki,
                               &wsrd.h_denomination_pub);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == ret)
  {
    report_row_inconsistency ("reserve_out",
                              rowid,
                              "denomination key not found (foreign key constraint violated)");
    return GNUNET_OK;
  }

  /* check that execution date is within withdraw range for denom_pub (?) */

  /* check reserve_sig */
  wsrd.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);
  wsrd.purpose.size = htonl (sizeof (wsrd));
  TALER_amount_hton (&wsrd.amount_with_fee,
                     amount_with_fee);
  wsrd.withdraw_fee = dki->properties.fee_withdraw;
  wsrd.h_coin_envelope = *h_blind_ev;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
                                  &wsrd.purpose,
                                  &reserve_sig->eddsa_signature,
                                  &reserve_pub->eddsa_pub))
  {
    report_row_inconsistency ("reserve_out",
                              rowid,
                              "invalid signature for reserve withdrawal");
    return GNUNET_OK;
  }

  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->reserve_pub = *reserve_pub;
    rs->total_out = *amount_with_fee;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &rs->total_in));
    if (GNUNET_OK !=
        load_auditor_reserve_summary (rs))
    {
      GNUNET_break (0);
      GNUNET_free (rs);
      return GNUNET_SYSERR;
    }
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (reserves,
                                                      &key,
                                                      rs,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  else
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&rs->total_out,
                                     &rs->total_out,
                                     amount_with_fee));
  }
  return GNUNET_OK;
}


/**
 * Check that the reserve summary matches what the exchange database
 * thinks about the reserve, and update our own state of the reserve.
 *
 * Remove all reserves that we are happy with from the DB.
 *
 * @param cls our `struct GNUNET_CONTAINER_MultiHashMap` with the reserves
 * @param key hash of the reserve public key
 * @param value a `struct ReserveSummary`
 * @return #GNUNET_OK to process more entries
 */
static int
verify_reserve_balance (void *cls,
                        const struct GNUNET_HashCode *key,
                        void *value)
{
  struct GNUNET_CONTAINER_MultiHashMap *reserves = cls;
  struct ReserveSummary *rs = value;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct TALER_Amount balance;
  int ret;

  ret = GNUNET_OK;
  reserve.pub = rs->reserve_pub;
  if (GNUNET_OK !=
      edb->reserve_get (edb->cls,
                        esession,
                        &reserve))
  {
    char *diag;

    GNUNET_asprintf (&diag,
                     "Failed to find summary for reserve `%s'\n",
                     TALER_B2S (&rs->reserve_pub));
    report_row_inconsistency ("reserve-summary",
                              UINT64_MAX,
                              diag);
    GNUNET_free (diag);
    return GNUNET_OK;
  }
  /* TODO: check reserve.expiry */

  /* FIXME: simplified computation as we have no previous reserve state yet */
  /* FIXME: actually update withdraw fee balance, expiration data and serial IDs! */
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&balance,
                             &rs->total_in,
                             &rs->total_out))
  {
    report_reserve_inconsistency (&rs->reserve_pub,
                                  &rs->total_in,
                                  &rs->total_out,
                                  "available balance insufficient to cover transfers");
    goto cleanup;
  }
  if (0 != TALER_amount_cmp (&balance,
                             &reserve.balance))
  {
    report_reserve_inconsistency (&rs->reserve_pub,
                                  &balance,
                                  &reserve.balance,
                                  "computed balance does not match stored balance");
    goto cleanup;
  }

  /* FIXME: if balance is zero, create reserve summary and drop reserve details! */

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Reserve balance `%s' OK\n",
              TALER_B2S (&rs->reserve_pub));

  if (rs->had_ri)
    ret = adb->update_reserve_info (adb->cls,
                                    asession,
                                    &rs->reserve_pub,
                                    &master_pub,
                                    &balance,
                                    &rs->a_withdraw_fee_balance,
                                    rs->a_expiration_date,
                                    rs->a_last_reserve_in_serial_id,
                                    rs->a_last_reserve_out_serial_id);
  else
    ret = adb->insert_reserve_info (adb->cls,
                                    asession,
                                    &rs->reserve_pub,
                                    &master_pub,
                                    &balance,
                                    &rs->a_withdraw_fee_balance,
                                    rs->a_expiration_date,
                                    rs->a_last_reserve_in_serial_id,
                                    rs->a_last_reserve_out_serial_id);


 cleanup:
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (reserves,
                                                       key,
                                                       rs));
  GNUNET_free (rs);
  return ret;
}


/**
 * Analyze reserves for being well-formed.
 *
 * @param cls NULL
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on invariant violation
 */
static int
analyze_reserves (void *cls)
{
  /* Map from hash of reserve's public key to a `struct ReserveSummary`. */
  struct GNUNET_CONTAINER_MultiHashMap *reserves;

  reserves = GNUNET_CONTAINER_multihashmap_create (512,
                                                   GNUNET_NO);

  if (GNUNET_OK !=
      edb->select_reserves_in_above_serial_id (edb->cls,
                                               esession,
                                               reserve_in_serial_id,
                                               &handle_reserve_in,
                                               reserves))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  if (GNUNET_OK !=
      edb->select_reserves_out_above_serial_id (edb->cls,
                                                esession,
                                                reserve_out_serial_id,
                                                &handle_reserve_out,
                                                reserves))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  GNUNET_CONTAINER_multihashmap_iterate (reserves,
                                         &verify_reserve_balance,
                                         reserves);
  GNUNET_break (0 ==
                GNUNET_CONTAINER_multihashmap_size (reserves));
  GNUNET_CONTAINER_multihashmap_destroy (reserves);

  return GNUNET_OK;
}


/* *************************** General transaction logic ****************** */

/**
 * Type of an analysis function.  Each analysis function runs in
 * its own transaction scope and must thus be internally consistent.
 *
 * @param cls closure
 * @param int #GNUNET_OK on success, #GNUNET_SYSERR on hard errors
 */
typedef int
(*Analysis)(void *cls);


/**
 * Perform the given @a analysis incrementally, checkpointing our
 * progress in the auditor DB.
 *
 * @param analysis analysis to run
 * @param analysis_cls closure for @a analysis
 * @return #GNUNET_OK if @a analysis succeessfully committed,
 *         #GNUNET_SYSERR on hard errors
 */
static int
incremental_processing (Analysis analysis,
                        void *analysis_cls)
{
  int ret;

  ret = adb->get_auditor_progress (adb->cls,
                                   asession,
                                   &master_pub,
                                   &reserve_in_serial_id,
                                   &reserve_out_serial_id,
                                   &deposit_serial_id,
                                   &melt_serial_id,
                                   &refund_serial_id,
                                   &prewire_serial_id);
  if (GNUNET_SYSERR == ret)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  if (GNUNET_NO == ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                  _("First analysis using this auditor, starting audit from scratch\n"));
    }
  else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                  _("Resuming audit at %llu/%llu/%llu/%llu/%llu/%llu\n\n"),
                  (unsigned long long) reserve_in_serial_id,
                  (unsigned long long) reserve_out_serial_id,
                  (unsigned long long) deposit_serial_id,
                  (unsigned long long) melt_serial_id,
                  (unsigned long long) refund_serial_id,
                  (unsigned long long) prewire_serial_id);
    }
  ret = analysis (analysis_cls);
  if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Analysis phase failed, not recording progress\n");
      return GNUNET_SYSERR;
    }
  ret = adb->update_auditor_progress (adb->cls,
                                      asession,
                                      &master_pub,
                                      reserve_in_serial_id,
                                      reserve_out_serial_id,
                                      deposit_serial_id,
                                      melt_serial_id,
                                      refund_serial_id,
                                      prewire_serial_id);
  if (GNUNET_OK != ret)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              _("Resuming audit at %llu/%llu/%llu/%llu/%llu/%llu\n\n"),
              (unsigned long long) reserve_in_serial_id,
              (unsigned long long) reserve_out_serial_id,
              (unsigned long long) deposit_serial_id,
              (unsigned long long) melt_serial_id,
              (unsigned long long) refund_serial_id,
              (unsigned long long) prewire_serial_id);
  return GNUNET_OK;
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
static int
transact (Analysis analysis,
          void *analysis_cls)
{
  int ret;

  ret = adb->start (adb->cls,
                    asession);
  if (GNUNET_OK != ret)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  ret = edb->start (edb->cls,
                    esession);
  if (GNUNET_OK != ret)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  ret = incremental_processing (analysis,
                                analysis_cls);
  if (GNUNET_OK == ret)
    {
      ret = edb->commit (edb->cls,
                         esession);
      if (GNUNET_OK != ret)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                      "Exchange DB commit failed, rolling back transaction\n");
          adb->rollback (adb->cls,
                         asession);
        }
      else
        {
          ret = adb->commit (adb->cls,
                             asession);
          if (GNUNET_OK != ret)
            {
              GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                          "Auditor DB commit failed!\n");
            }
        }
    }
  else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Processing failed, rolling back transaction\n");
      adb->rollback (adb->cls,
                     asession);
      edb->rollback (edb->cls,
                     esession);
    }
  clear_transaction_state_cache ();
  return ret;
}


/**
 * Initialize DB sessions and run the analysis.
 */
static void
setup_sessions_and_run ()
{
  esession = edb->get_session (edb->cls);
  if (NULL == esession)
  {
    fprintf (stderr,
             "Failed to initialize exchange session.\n");
    global_ret = 1;
    return;
  }
  asession = adb->get_session (adb->cls);
  if (NULL == asession)
  {
    fprintf (stderr,
             "Failed to initialize auditor session.\n");
    global_ret = 1;
    return;
  }

  transact (&analyze_reserves,
            NULL);
  // NOTE: add other 'transact (&analyze_*)'-calls here as they are implemented.
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
  if (NULL ==
      (edb = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize exchange database plugin.\n");
    global_ret = 1;
    return;
  }
  if (NULL ==
      (adb = TALER_AUDITORDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize auditor database plugin.\n");
    global_ret = 1;
    TALER_EXCHANGEDB_plugin_unload (edb);
    return;
  }
  setup_sessions_and_run ();
  TALER_AUDITORDB_plugin_unload (adb);
  TALER_EXCHANGEDB_plugin_unload (edb);
}


/**
 * The main function of the database initialization tool.
 * Used to initialize the Taler Exchange's database.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_END
  };

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-auditor",
                                   "INFO",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc,
			  argv,
                          "taler-auditor",
			  "Audit Taler exchange database",
			  options,
			  &run,
			  NULL))
    return 1;
  return global_ret;
}


/* end of taler-auditor.c */
