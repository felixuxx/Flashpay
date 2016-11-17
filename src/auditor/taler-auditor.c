/*
  This file is part of TALER
  Copyright (C) 2016 Inria

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
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_plugin.h"


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
 * Last reserve_in serial ID seen.
 */
static uint64_t reserve_in_serial_id;

/**
 * Last reserve_out serial ID seen.
 */
static uint64_t reserve_out_serial_id;


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

};


/**
 * Map from hash of reserve's public key to a `struct ReserveSummary`.
 */
static struct GNUNET_CONTAINER_MultiHashMap *reserves;


/**
 * Function called with details about incoming wire transfers.
 *
 * @param cls NULL
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
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;

  /* TODO: somewhere we need to check that 'reserve_in' data actually
     matches wire transfers from the bank. Not sure if this should be
     done within the core auditor logic though... */

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
 * @param cls closure
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
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;

  /* TODO: check signatures, in particluar the reserve_sig! */
  GNUNET_assert (rowid >= reserve_out_serial_id); /* should be monotonically increasing */
  reserve_out_serial_id = rowid + 1;
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
 * @param cls NULL
 * @param key hash of the reserve public key
 * @param value a `struct ReserveSummary`
 * @return #GNUNET_OK to process more entries
 */
static int
verify_reserve_balance (void *cls,
                        const struct GNUNET_HashCode *key,
                        void *value)
{
  struct ReserveSummary *rs = value;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct TALER_Amount balance;

  if (GNUNET_OK !=
      edb->reserve_get (edb->cls,
                        esession,
                        &reserve))
  {
    GNUNET_break (0);
    return GNUNET_OK;
  }
  /* TODO: check reserve.expiry? */
  /* FIXME: get previous reserve state from auditor DB */

  /* FIXME: simplified computation as we have no previous reserve state yet */
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&balance,
                             &rs->total_in,
                             &rs->total_out))
  {
    GNUNET_break (0);
    return GNUNET_OK;
  }
  if (0 != TALER_amount_cmp (&balance,
                             &reserve.balance))
  {
    GNUNET_break (0);
    return GNUNET_OK;
  }

  /* FIXME: commit new reserve state from auditor DB */

  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (reserves,
                                                       key,
                                                       rs));
  GNUNET_free (rs);
  return GNUNET_OK;
}


/**
 * Analyze reserves for being well-formed.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on invariant violation
 */
static int
analyze_reserves ()
{
  reserves = GNUNET_CONTAINER_multihashmap_create (512,
                                                   GNUNET_NO);

  /* FIXME: check return values... */
  edb->select_reserves_in_above_serial_id (edb->cls,
                                           esession,
                                           reserve_in_serial_id,
                                           &handle_reserve_in,
                                           NULL);
  edb->select_reserves_out_above_serial_id (edb->cls,
                                            esession,
                                            reserve_out_serial_id,
                                            &handle_reserve_out,
                                            NULL);
  GNUNET_CONTAINER_multihashmap_iterate (reserves,
                                         &verify_reserve_balance,
                                         NULL);
  /* FIXME: any values left in #reserves indicate errors! */
  GNUNET_CONTAINER_multihashmap_destroy (reserves);

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
  esession = edb->get_session (edb->cls);
  if (NULL == esession)
  {
    fprintf (stderr,
             "Failed to initialize exchange session.\n");
    global_ret = 1;
    TALER_AUDITORDB_plugin_unload (adb);
    TALER_EXCHANGEDB_plugin_unload (edb);
    return;
  }

  /* FIXME: init these from auditordb */
  reserve_in_serial_id = 1;
  reserve_out_serial_id = 1;

  analyze_reserves ();

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
