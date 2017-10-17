/*
  This file is part of TALER
  Copyright (C) 2017 Taler Systems SA

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
 * @file auditor/taler-wire-auditor.c
 * @brief audits that wire transfers match those from an exchange database.
 * @author Christian Grothoff
 *
 * - First, this auditor verifies that 'reserves_in' actually matches
 *   the incoming wire transfers from the bank.
 * - Second, we check that the outgoing wire transfers match those
 *   given in the 'wire_out' table
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_plugin.h"
#include "taler_json_lib.h"
#include "taler_wire_lib.h"
#include "taler_signatures.h"


/**
 * Return value from main().
 */
static int global_ret;

/**
 * Command-line option "-r": restart audit from scratch
 */
static int restart;

/**
 * Name of the wire plugin to load to access the exchange's bank account.
 */
static char *wire_plugin;

/**
 * Handle to access the exchange's database.
 */
static struct TALER_EXCHANGEDB_Plugin *edb;

/**
 * Which currency are we doing the audit for?
 */
static char *currency;

/**
 * Our configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Map with information about incoming wire transfers.
 * Maps hashes of the wire offsets to `struct ReserveInInfo`s.
 */
static struct GNUNET_CONTAINER_MultiHashMap *in_map;

/**
 * Map with information about outgoing wire transfers.
 * Maps hashes of the wire offsets to `struct ReserveOutInfo`s.
 */
static struct GNUNET_CONTAINER_MultiHashMap *out_map;

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
 * Handle to the wire plugin for wire operations.
 */
static struct TALER_WIRE_Plugin *wp;

/**
 * Active wire request for the transaction history.
 */
static struct TALER_WIRE_HistoryHandle *hh;

/**
 * Query status for the incremental processing status in the auditordb.
 */
static enum GNUNET_DB_QueryStatus qsx;

/**
 * Last reserve_in / wire_out serial IDs seen.
 */
static struct TALER_AUDITORDB_WireProgressPoint pp;

/**
 * Where we are in the inbound (CREDIT) transaction history.
 */
static void *in_wire_off;

/**
 * Where we are in the inbound (DEBIT) transaction history.
 */
static void *out_wire_off;

/**
 * Number of bytes in #in_wire_off and #out_wire_off.
 */
static size_t wire_off_size;

/**
 * Array of reports about row inconsitencies.
 */
static json_t *report_row_inconsistencies;

/**
 * Array of reports about minor row inconcistencies.
 */
static json_t *report_row_minor_inconsistencies;


/* *****************************   Shutdown   **************************** */

/** 
 * Entry in map with wire information we expect to obtain from the
 * bank later.
 */
struct ReserveInInfo
{

  /** 
   * Hash of expected row offset.
   */
  struct GNUNET_HashCode row_off_hash;

  /**
   * Number of bytes in @e row_off.
   */
  size_t row_off_size;

  /**
   * Expected details about the wire transfer.
   */
  struct TALER_WIRE_TransferDetails details;

  /**
   * RowID in reserves_in table.
   */
  uint64_t rowid;
  
};


/** 
 * Entry in map with wire information we expect to obtain from the
 * #edb later.
 */
struct ReserveOutInfo
{

  /** 
   * Hash of the wire transfer subject.
   */
  struct GNUNET_HashCode subject_hash;

  /**
   * Expected details about the wire transfer.
   */
  struct TALER_WIRE_TransferDetails details;
  
};


/**
 * Free entry in #in_map.
 *
 * @param cls NULL
 * @param key unused key
 * @param value the `struct ReserveInInfo` to free
 * @return #GNUNET_OK
 */
static int
free_rii (void *cls,
	  const struct GNUNET_HashCode *key,
	  void *value)
{
  struct ReserveInInfo *rii = value;

  GNUNET_assert (GNUNET_YES ==
		 GNUNET_CONTAINER_multihashmap_remove (in_map,
						       key,
						       rii));
  json_decref (rii->details.account_details);
  GNUNET_free (rii);
  return GNUNET_OK;
}


/**
 * Free entry in #out_map.
 *
 * @param cls NULL
 * @param key unused key
 * @param value the `struct ReserveOutInfo` to free
 * @return #GNUNET_OK
 */
static int
free_roi (void *cls,
	  const struct GNUNET_HashCode *key,
	  void *value)
{
  struct ReserveOutInfo *roi = value;

  GNUNET_assert (GNUNET_YES ==
		 GNUNET_CONTAINER_multihashmap_remove (out_map,
						       key,
						       roi));
  json_decref (roi->details.account_details);
  GNUNET_free (roi);
  return GNUNET_OK;
}


/**
 * Task run on shutdown.
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  if (NULL != report_row_inconsistencies)
  {
    json_t *report;
    
    GNUNET_assert (NULL != report_row_minor_inconsistencies);
    report = json_pack ("{s:o, s:o}",
			"row-inconsistencies", report_row_inconsistencies,
			"row-minor-inconsistencies", report_row_minor_inconsistencies);
    json_dumpf (report,
		stdout,
		JSON_INDENT (2));
    json_decref (report);
    report_row_inconsistencies = NULL;
    report_row_minor_inconsistencies = NULL;
  }
  if (NULL != hh)
  {
    wp->get_history_cancel (wp->cls,
                            hh);
    hh = NULL;
  }
  if (NULL != in_map)
  {
    GNUNET_CONTAINER_multihashmap_iterate (in_map,
					   &free_rii,
					   NULL);
    GNUNET_CONTAINER_multihashmap_destroy (in_map);
    in_map = NULL;
  }
  if (NULL != out_map)
  {
    GNUNET_CONTAINER_multihashmap_iterate (out_map,
					   &free_roi,
					   NULL);
    GNUNET_CONTAINER_multihashmap_destroy (out_map);
    out_map = NULL;
  }
  if (NULL != wp)
  {
    TALER_WIRE_plugin_unload (wp);
    wp = NULL;
  }
  if (NULL != adb)
  {
    TALER_AUDITORDB_plugin_unload (adb);
    adb = NULL;
  }
  if (NULL != edb)
  {
    TALER_EXCHANGEDB_plugin_unload (edb);
    edb = NULL;
  }
}


/* ***************************** Report logic **************************** */


/**
 * Add @a object to the report @a array.  Fail hard if this fails.
 *
 * @param array report array to append @a object to
 * @param object object to append, should be check that it is not NULL
 */ 
static void
report (json_t *array,
	json_t *object)
{
  GNUNET_assert (NULL != object);
  GNUNET_assert (0 ==
		 json_array_append_new (array,
					object));
}


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
  report (report_row_inconsistencies,
	  json_pack ("{s:s, s:I, s:s}",
		     "table", table,
		     "row", (json_int_t) rowid,
		     "diagnostic", diagnostic));
}


/**
 * Report a minor inconsistency in the exchange's database (i.e. something
 * relating to timestamps that should have no financial implications).
 *
 * @param table affected table
 * @param rowid affected row, UINT64_MAX if row is missing
 * @param diagnostic message explaining the problem
 */
static void
report_row_minor_inconsistency (const char *table,
                                uint64_t rowid,
                                const char *diagnostic)
{
  report (report_row_minor_inconsistencies,
	  json_pack ("{s:s, s:I, s:s}",
		     "table", table,
		     "row", (json_int_t) rowid,
		     "diagnostic", diagnostic));
}


/* *************************** General transaction logic ****************** */

/**
 * Commit the transaction, checkpointing our progress in the auditor
 * DB.
 *
 * @param qs transaction status so far
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
commit (enum GNUNET_DB_QueryStatus qs)
{
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		  "Serialization issue, not recording progress\n");
    else
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		  "Hard error, not recording progress\n");
    adb->rollback (adb->cls,
                   asession);
    edb->rollback (edb->cls,
                   esession);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsx)
    qs = adb->update_wire_auditor_progress (adb->cls,
                                            asession,
                                            &master_pub,
                                            &pp,
                                            in_wire_off,
                                            out_wire_off,
                                            wire_off_size);
  else
    qs = adb->insert_wire_auditor_progress (adb->cls,
                                            asession,
                                            &master_pub,
                                            &pp,
                                            in_wire_off,
                                            out_wire_off,
                                            wire_off_size);

  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		"Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              _("Concluded audit step at %llu/%llu\n"),
              (unsigned long long) pp.last_reserve_in_serial_id,
              (unsigned long long) pp.last_wire_out_serial_id);

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
                "Processing failed, rolling back transaction\n");
    adb->rollback (adb->cls,
                   asession);
    edb->rollback (edb->cls,
                   esession);
  }
  return qs;
}


/* ***************************** Analyze reserves_out ************************ */


/**
 * Function called with details about outgoing wire transfers
 * as claimed by the exchange DB.
 *
 * @param cls NULL
 * @param rowid unique serial ID for the refresh session in our DB
 * @param date timestamp of the wire transfer (roughly)
 * @param wtid wire transfer subject
 * @param wire wire transfer details of the receiver
 * @param amount amount that was wired
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
wire_out_cb (void *cls,
		uint64_t rowid,
		struct GNUNET_TIME_Absolute date,
		const struct TALER_WireTransferIdentifierRawP *wtid,
		const json_t *wire,
		const struct TALER_Amount *amount)
{
  struct GNUNET_HashCode key;
  struct ReserveOutInfo *roi;
  
  GNUNET_CRYPTO_hash (wtid,
		      sizeof (struct TALER_WireTransferIdentifierRawP),
		      &key);
  roi = GNUNET_CONTAINER_multihashmap_get (in_map,
					   &key);
  if (NULL == roi)
  {
    /* FIXME (#4963): do proper logging! */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"Failed to find wire transfer `%s' over %s at `%s' in exchange database!\n",
		TALER_B2S (wtid),
		TALER_amount2s (amount),
		GNUNET_STRINGS_absolute_time_to_string (date));
    return GNUNET_OK;
  }
  if (0 != TALER_amount_cmp (&roi->details.amount,
			     amount))
  {
    report_row_inconsistency ("reserves_out",
			      rowid,
			      "wire amount missmatch");
    return GNUNET_OK;
  }
  if (roi->details.execution_date.abs_value_us !=
      date.abs_value_us)
  {
    report_row_minor_inconsistency ("reserves_out",
				    rowid,
				    "execution date missmatch");
  }
  if (! json_equal ((json_t *) wire,
		    roi->details.account_details))
  {
    report_row_inconsistency ("reserves_out",
			      rowid,
			      "receiver account missmatch");
    return GNUNET_OK;
  }
  GNUNET_assert (GNUNET_OK ==
		 GNUNET_CONTAINER_multihashmap_remove (out_map,
						       &key,
						       roi));
  GNUNET_assert (GNUNET_OK ==
		 free_roi (NULL,
			   &key,
			   roi));
  return GNUNET_OK;
}


/**
 * Complain that we failed to match an entry from #out_map.
 *
 * @param cls NULL
 * @param key unused key
 * @param value the `struct ReserveOutInfo` to free
 * @return #GNUNET_OK
 */
static int
complain_out_not_found (void *cls,
			const struct GNUNET_HashCode *key,
			void *value)
{
  struct ReserveOutInfo *roi = value;

  (void) roi;
  /* FIXME (#4963): log more precisely which wire transfer (and amount)
     is bogus. */
  report_row_inconsistency ("reserves_out",
			    UINT64_MAX,
			    "matching wire transfer not found");
  return GNUNET_OK;
}


/**
 * Go over the "wire_out" table of the exchange and
 * verify that all wire outs are in that table.
 */
static void
check_exchange_wire_out ()
{
  enum GNUNET_DB_QueryStatus qs;
    
  qs = edb->select_wire_out_above_serial_id (edb->cls,
					     esession,
					     pp.last_wire_out_serial_id,
					     &wire_out_cb,
					     NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_CONTAINER_multihashmap_iterate (out_map,
					 &complain_out_not_found,
					 NULL); 
  /* clean up (technically redundant, but nicer) */
  GNUNET_CONTAINER_multihashmap_iterate (out_map,
					 &free_roi,
					 NULL);
  GNUNET_CONTAINER_multihashmap_destroy (out_map);
  out_map = NULL;
 
  /* conclude with: */
  commit (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT);
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * This function is called for all transactions that
 * are credited to the exchange's account (incoming
 * transactions).
 *
 * @param cls closure
 * @param dir direction of the transfer
 * @param row_off identification of the position at which we are querying
 * @param row_off_size number of bytes in @a row_off
 * @param details details about the wire transfer
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
static int
history_debit_cb (void *cls,
		  enum TALER_BANK_Direction dir,
		  const void *row_off,
		  size_t row_off_size,
		  const struct TALER_WIRE_TransferDetails *details)
{
  struct ReserveOutInfo *roi;
  
  if (TALER_BANK_DIRECTION_NONE == dir)
  {
    /* end of iteration, now check wire_out to see
       if it matches #out_map */
    hh = NULL;
    check_exchange_wire_out ();
    return GNUNET_OK;
  }
  roi = GNUNET_new (struct ReserveOutInfo);
  GNUNET_CRYPTO_hash (&details->reserve_pub, /* FIXME (#5077): missnomer */
		      sizeof (details->reserve_pub),
		      &roi->subject_hash);
  roi->details.amount = details->amount;
  roi->details.execution_date = details->execution_date;
  roi->details.reserve_pub = details->reserve_pub; /* FIXME (#5077): missnomer & redundant */
  roi->details.account_details = json_incref ((json_t *) details->account_details);
  if (GNUNET_OK !=
      GNUNET_CONTAINER_multihashmap_put (out_map,
					 &roi->subject_hash,
					 roi,
					 GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
  {
    GNUNET_break_op (0); /* duplicate wire offset is not allowed! */
    report_row_inconsistency ("bank wire log",
			      UINT64_MAX,
			      "duplicate wire offset");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Main functin for processing 'reserves_out' data.
 * We start by going over the DEBIT transactions this
 * time, and then verify that all of them are justified
 * by 'reserves_out'.
 */
static void
process_debits ()
{
  GNUNET_assert (NULL == hh);
  out_map = GNUNET_CONTAINER_multihashmap_create (1024,
						  GNUNET_YES);
  hh = wp->get_history (wp->cls,
                        TALER_BANK_DIRECTION_DEBIT,
                        out_wire_off,
                        wire_off_size,
                        INT64_MAX,
                        &history_debit_cb,
                        NULL);
  if (NULL == hh)
  {
    fprintf (stderr,
             "Failed to obtain bank transaction history\n");
    commit (GNUNET_DB_STATUS_HARD_ERROR);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/* ***************************** Analyze reserves_in ************************ */


/**
 * Function called with details about incoming wire transfers
 * as claimed by the exchange DB.
 *
 * @param cls NULL
 * @param rowid unique serial ID for the refresh session in our DB
 * @param reserve_pub public key of the reserve (also the WTID)
 * @param credit amount that was received
 * @param sender_account_details information about the sender's bank account
 * @param wire_reference unique identifier for the wire transfer (plugin-specific format)
 * @param wire_reference_size number of bytes in @a wire_reference
 * @param execution_date when did we receive the funds
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
reserve_in_cb (void *cls,
	       uint64_t rowid,
	       const struct TALER_ReservePublicKeyP *reserve_pub,
	       const struct TALER_Amount *credit,
	       const json_t *sender_account_details,
	       const void *wire_reference,
	       size_t wire_reference_size,
	       struct GNUNET_TIME_Absolute execution_date)

{
  struct ReserveInInfo *rii;

  rii = GNUNET_new (struct ReserveInInfo);
  GNUNET_CRYPTO_hash (wire_reference,
		      wire_reference_size,
		      &rii->row_off_hash);
  rii->row_off_size = wire_reference_size;
  rii->details.amount = *credit;
  rii->details.execution_date = execution_date;
  rii->details.reserve_pub = *reserve_pub;
  rii->details.account_details = json_incref ((json_t *) sender_account_details);
  rii->rowid = rowid;
  if (GNUNET_OK !=
      GNUNET_CONTAINER_multihashmap_put (in_map,
					 &rii->row_off_hash,
					 rii,
					 GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
  {
    GNUNET_break_op (0); /* duplicate wire offset is not allowed! */
    report_row_inconsistency ("reserves_in",
			      rowid,
			      "duplicate wire offset");
    return GNUNET_SYSERR;
  }
  pp.last_reserve_in_serial_id = rowid + 1;
  return GNUNET_OK;
}


/**
 * Complain that we failed to match an entry from #in_map.
 *
 * @param cls NULL
 * @param key unused key
 * @param value the `struct ReserveInInfo` to free
 * @return #GNUNET_OK
 */
static int
complain_in_not_found (void *cls,
		       const struct GNUNET_HashCode *key,
		       void *value)
{
  struct ReserveInInfo *rii = value;

  report_row_inconsistency ("reserves_in",
			    rii->rowid,
			    "matching wire transfer not found");
  return GNUNET_OK;
}


/**
 * This function is called for all transactions that
 * are credited to the exchange's account (incoming
 * transactions).
 *
 * @param cls closure
 * @param dir direction of the transfer
 * @param row_off identification of the position at which we are querying
 * @param row_off_size number of bytes in @a row_off
 * @param details details about the wire transfer
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
static int
history_credit_cb (void *cls,
                   enum TALER_BANK_Direction dir,
                   const void *row_off,
                   size_t row_off_size,
                   const struct TALER_WIRE_TransferDetails *details)
{
  struct ReserveInInfo *rii;
  struct GNUNET_HashCode key;
  
  if (TALER_BANK_DIRECTION_NONE == dir)
  {
    /* end of operation */
    hh = NULL;
    GNUNET_CONTAINER_multihashmap_iterate (in_map,
					   &complain_in_not_found,
					   NULL);
    /* clean up before 2nd phase */
    GNUNET_CONTAINER_multihashmap_iterate (in_map,
					   &free_rii,
					   NULL);
    GNUNET_CONTAINER_multihashmap_destroy (in_map);
    in_map = NULL;
    process_debits ();
    return GNUNET_SYSERR;
  }
  GNUNET_CRYPTO_hash (row_off,
		      row_off_size,
		      &key);
  rii = GNUNET_CONTAINER_multihashmap_get (in_map,
					   &key);
  if (NULL == rii)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		"Failed to find wire transfer at `%s' in exchange database. Audit ends at this point in time.\n",
		GNUNET_STRINGS_absolute_time_to_string (details->execution_date));
    return GNUNET_SYSERR;
  }

  /* Update offset */
  if (NULL == in_wire_off)
  {
    wire_off_size = row_off_size;
    in_wire_off = GNUNET_malloc (row_off_size);
  }
  if (wire_off_size != row_off_size)
  {
    GNUNET_break (0);
    commit (GNUNET_DB_STATUS_HARD_ERROR);
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_SYSERR;
  }
  memcpy (in_wire_off,
	  row_off,
	  row_off_size);

  /* compare records with expected data */
  if (row_off_size != rii->row_off_size)
  {
    GNUNET_break (0);
    report_row_inconsistency ("reserves_in",
			      rii->rowid,
			      "wire reference size missmatch");
    return GNUNET_OK;
  }
  if (0 != TALER_amount_cmp (&rii->details.amount,
			     &details->amount))
  {
    report_row_inconsistency ("reserves_in",
			      rii->rowid,
			      "wire amount missmatch");
    return GNUNET_OK;
  }
  if (details->execution_date.abs_value_us !=
      rii->details.execution_date.abs_value_us)
  {
    report_row_minor_inconsistency ("reserves_in",
				    rii->rowid,
				    "execution date missmatch");
  }
  if (0 != memcmp (&details->reserve_pub,
		   &rii->details.reserve_pub,
		   sizeof (struct TALER_ReservePublicKeyP)))
  {
    report_row_inconsistency ("reserves_in",
			      rii->rowid,
			      "reserve public key / wire subject missmatch");
    return GNUNET_OK;
  }
  if (! json_equal (details->account_details,
		    rii->details.account_details))
  {
    report_row_minor_inconsistency ("reserves_in",
				    rii->rowid,
				    "sender account missmatch");
  }
  GNUNET_assert (GNUNET_OK ==
		 GNUNET_CONTAINER_multihashmap_remove (in_map,
						       &key,
						       rii));
  GNUNET_assert (GNUNET_OK ==
		 free_rii (NULL,
			   &key,
			   rii));
  return GNUNET_OK;
}


/* ***************************** Setup logic    ************************ */


/**
 * Main function that will be run.
 *
 * @param cls closure
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
  enum GNUNET_DB_QueryStatus qs;
  int ret;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching auditor\n");
  cfg = c;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "taler",
                                             "CURRENCY",
                                             &currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    global_ret = 1;
    return;
  }
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
  if (restart)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Full audit restart requested, dropping old audit data.\n");
    GNUNET_break (GNUNET_OK ==
                  adb->drop_tables (adb->cls));
    TALER_AUDITORDB_plugin_unload (adb);
    if (NULL ==
        (adb = TALER_AUDITORDB_plugin_load (cfg)))
    {
      fprintf (stderr,
               "Failed to initialize auditor database plugin after drop.\n");
      global_ret = 1;
      TALER_EXCHANGEDB_plugin_unload (edb);
      return;
    }
    GNUNET_break (GNUNET_OK ==
                  adb->create_tables (adb->cls));
  }
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  esession = edb->get_session (edb->cls);
  if (NULL == esession)
  {
    fprintf (stderr,
             "Failed to initialize exchange session.\n");
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  asession = adb->get_session (adb->cls);
  if (NULL == asession)
  {
    fprintf (stderr,
             "Failed to initialize auditor session.\n");
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  wp = TALER_WIRE_plugin_load (cfg,
                               wire_plugin);
  if (NULL == wp)
  {
    fprintf (stderr,
             "Failed to load wire plugin `%s'\n",
             wire_plugin);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting audit\n");
  ret = adb->start (adb->cls,
                    asession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  ret = edb->start (edb->cls,
                    esession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_assert (NULL !=
		 (report_row_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
		 (report_row_minor_inconsistencies = json_array ()));
  qsx = adb->get_wire_auditor_progress (adb->cls,
                                        asession,
                                        &master_pub,
                                        &pp,
                                        &in_wire_off,
                                        &out_wire_off,
                                        &wire_off_size);
  if (0 > qsx)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsx)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                _("First analysis using this auditor, starting audit from scratch\n"));
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                _("Resuming audit at %llu/%llu\n"),
                (unsigned long long) pp.last_reserve_in_serial_id,
                (unsigned long long) pp.last_wire_out_serial_id);
  }

  in_map = GNUNET_CONTAINER_multihashmap_create (1024,
						 GNUNET_YES);
  qs = edb->select_reserves_in_above_serial_id (edb->cls,
						esession,
						pp.last_reserve_in_serial_id,
						&reserve_in_cb,
						NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "No new incoming transactions available, skipping CREDIT phase\n");
    process_debits ();
    return;
  }
  hh = wp->get_history (wp->cls,
                        TALER_BANK_DIRECTION_CREDIT,
                        in_wire_off,
                        wire_off_size,
                        INT64_MAX,
                        &history_credit_cb,
                        NULL);
  if (NULL == hh)
  {
    fprintf (stderr,
             "Failed to obtain bank transaction history\n");
    commit (GNUNET_DB_STATUS_HARD_ERROR);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
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
    GNUNET_GETOPT_option_mandatory
    (GNUNET_GETOPT_option_base32_auto ('m',
                                       "exchange-key",
                                       "KEY",
                                       "public key of the exchange (Crockford base32 encoded)",
                                       &master_pub)),
    GNUNET_GETOPT_option_flag ('r',
                               "restart",
                               "restart audit from the beginning (required on first run)",
                               &restart),
    GNUNET_GETOPT_option_mandatory
    (GNUNET_GETOPT_option_string ('w',
				  "wire",
				  "PLUGINNAME",
				  "name of the wire plugin to use",
				  &wire_plugin)),
    GNUNET_GETOPT_OPTION_END
  };

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-wire-auditor",
                                   "MESSAGE",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc,
			  argv,
                          "taler-wire-auditor",
			  "Audit exchange database for consistency with the bank's wire transfers",
			  options,
			  &run,
			  NULL))
    return 1;
  return global_ret;
}


/* end of taler-wire-auditor.c */
