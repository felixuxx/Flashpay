/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

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
 * @file taler-exchange-httpd_wire.c
 * @brief Handle /wire requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_wire.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include <jansson.h>


/**
 * Thread-local.  Contains a pointer to `struct WireStateHandle` or NULL.
 * Stores the per-thread latest generation of our wire response.
 */
static pthread_key_t wire_state;

/**
 * Counter incremented whenever we have a reason to re-build the #wire_state
 * because something external changed (in another thread).  The counter is
 * manipulated using an atomic update, and thus to ensure that threads notice
 * when it changes, the variable MUST be volatile.  See #get_wire_state()
 * and #TEH_wire_update_state() for uses of this variable.
 */
static volatile uint64_t wire_generation;


/**
 * State we keep per thread to cache the /wire response.
 */
struct WireStateHandle
{
  /**
   * Cached JSON for /wire response.
   */
  json_t *wire_reply;

  /**
   * For which (global) wire_generation was this data structure created?
   * Used to check when we are outdated and need to be re-generated.
   */
  uint64_t wire_generation;

};


/**
 * Free memory associated with @a wsh
 *
 * @param[in] wsh wire state to destroy
 */
static void
destroy_wire_state (struct WireStateHandle *wsh)
{
  json_decref (wsh->wire_reply);
  GNUNET_free (wsh);
}


/**
 * Free memory associated with wire state. Signature
 * suitable for pthread_key_create().
 *
 * @param[in] cls the `struct WireStateHandle` to destroy
 */static void
destroy_wire_state_cb (void *cls)
{
  struct WireStateHandle *wsh = cls;

  destroy_wire_state (wsh);
}


/**
 * Initialize WIRE submodule.
 *
 * @return #GNUNET_OK on success
 */
int
TEH_WIRE_init ()
{
  if (0 !=
      pthread_key_create (&wire_state,
                          &destroy_wire_state_cb))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Fully clean up our state.
 */
void
TEH_WIRE_done ()
{
  GNUNET_assert (0 ==
                 pthread_key_delete (wire_state));
}


/**
 * Add information about a wire account to @a cls.
 *
 * @param cls a `json_t *` object to expand with wire account details
 * @param payto_uri the exchange bank account URI to add
 * @param master_sig master key signature affirming that this is a bank
 *                   account of the exchange (of purpose #TALER_SIGNATURE_MASTER_WIRE_DETAILS)
 */
static void
add_wire_account (void *cls,
                  const char *payto_uri,
                  const struct TALER_MasterSignatureP *master_sig)
{
  json_t *a = cls;

  if (0 !=
      json_array_append_new (
        a,
        json_pack ("{s:s, s:o}",
                   "payto_uri",
                   payto_uri,
                   "master_sig",
                   GNUNET_JSON_from_data_auto (master_sig))))
  {
    GNUNET_break (0);   /* out of memory!? */
    return;
  }
}


/**
 * Add information about a wire account to @a cls.
 *
 * @param cls a `json_t *` array to expand with wire account details
 * @param wire_fee the wire fee we charge
 * @param closing_fee the closing fee we charge
 * @param start_date from when are these fees valid (start date)
 * @param end_date until when are these fees valid (end date, exclusive)
 * @param master_sig master key signature affirming that this is the correct
 *                   fee (of purpose #TALER_SIGNATURE_MASTER_WIRE_FEES)
 */
static void
add_wire_fee (void *cls,
              const struct TALER_Amount *wire_fee,
              const struct TALER_Amount *closing_fee,
              struct GNUNET_TIME_Absolute start_date,
              struct GNUNET_TIME_Absolute end_date,
              const struct TALER_MasterSignatureP *master_sig)
{
  json_t *a = cls;

  if (0 !=
      json_array_append_new (
        a,
        json_pack ("{s:o, s:o, s:o, s:o, s:o}",
                   "wire_fee",
                   TALER_JSON_from_amount (wire_fee),
                   "closing_fee",
                   TALER_JSON_from_amount (closing_fee),
                   "start_date",
                   GNUNET_JSON_from_time_abs (start_date),
                   "end_date",
                   GNUNET_JSON_from_time_abs (end_date),
                   "sig",
                   GNUNET_JSON_from_data_auto (master_sig))))
  {
    GNUNET_break (0);   /* out of memory!? */
    return;
  }
}


/**
 * Create the /wire response from our database state.
 *
 * @return NULL on error
 */
static struct WireStateHandle *
build_wire_state (void)
{
  json_t *wire_accounts_array;
  json_t *wire_fee_object;
  json_t *wire_reply;
  uint64_t wg = wire_generation; /* must be obtained FIRST */
  enum GNUNET_DB_QueryStatus qs;

  wire_accounts_array = json_array ();
  GNUNET_assert (NULL != wire_accounts_array);
  qs = TEH_plugin->get_wire_accounts (TEH_plugin->cls,
                                      &add_wire_account,
                                      wire_accounts_array);
  if (0 > qs)
  {
    GNUNET_break (0);
    json_decref (wire_accounts_array);
    return NULL;
  }
  if (0 == json_array_size (wire_accounts_array))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No bank accounts for the exchange configured. Administrator must `enable-account` with taler-exchange-offline!\n");
    json_decref (wire_accounts_array);
    return NULL;
  }
  wire_fee_object = json_object ();
  GNUNET_assert (NULL != wire_fee_object);
  {
    json_t *account;
    size_t index;

    json_array_foreach (wire_accounts_array, index, account) {
      char *wire_method;
      const char *payto_uri = json_string_value (json_object_get (account,
                                                                  "payto_uri"));
      GNUNET_assert (NULL != payto_uri);
      wire_method = TALER_payto_get_method (payto_uri);
      if (NULL == json_object_get (wire_fee_object,
                                   wire_method))
      {
        json_t *a = json_array ();

        GNUNET_assert (NULL != a);
        qs = TEH_plugin->get_wire_fees (TEH_plugin->cls,
                                        wire_method,
                                        &add_wire_fee,
                                        a);
        if (0 > qs)
        {
          GNUNET_break (0);
          json_decref (a);
          json_decref (wire_fee_object);
          json_decref (wire_accounts_array);
          return NULL;
        }
        if (0 == json_array_size (a))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "No wire fees for `%s' configured. Administrator must set `wire-fee` with taler-exchange-offline!\n",
                      wire_method);
          json_decref (wire_accounts_array);
          json_decref (wire_fee_object);
          return NULL;
        }
        GNUNET_assert (0 ==
                       json_object_set_new (wire_fee_object,
                                            wire_method,
                                            a));
      }
      GNUNET_free (wire_method);

    }
  }
  wire_reply = json_pack (
    "{s:O, s:O, s:o}",
    "accounts", wire_accounts_array,
    "fees", wire_fee_object,
    "master_public_key",
    GNUNET_JSON_from_data_auto (&TEH_master_public_key));
  GNUNET_assert (NULL != wire_reply);
  {
    struct WireStateHandle *wsh;

    wsh = GNUNET_new (struct WireStateHandle);
    wsh->wire_reply = wire_reply;
    wsh->wire_generation = wg;
    return wsh;
  }
}


void
TEH_wire_update_state (void)
{
  __sync_fetch_and_add (&wire_generation,
                        1);
}


/**
 * Return the current key state for this thread.  Possibly
 * re-builds the key state if we have reason to believe
 * that something changed.
 *
 * @return NULL on error
 */
struct WireStateHandle *
get_wire_state (void)
{
  struct WireStateHandle *old_wsh;
  struct WireStateHandle *wsh;

  old_wsh = pthread_getspecific (wire_state);
  if ( (NULL == old_wsh) ||
       (old_wsh->wire_generation < wire_generation) )
  {
    wsh = build_wire_state ();
    if (NULL == wsh)
      return NULL;
    if (0 != pthread_setspecific (wire_state,
                                  wsh))
    {
      GNUNET_break (0);
      destroy_wire_state (wsh);
      return NULL;
    }
    if (NULL != old_wsh)
      destroy_wire_state (old_wsh);
    return wsh;
  }
  return old_wsh;
}


/**
 * Handle a "/wire" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_wire (const struct TEH_RequestHandler *rh,
                  struct MHD_Connection *connection,
                  const char *const args[])
{
  struct WireStateHandle *wsh;

  (void) rh;
  (void) args;
  wsh = get_wire_state ();
  if (NULL == wsh)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_BAD_CONFIGURATION,
                                       NULL);
  return TALER_MHD_reply_json (connection,
                               json_incref (wsh->wire_reply),
                               MHD_HTTP_OK);
}


/* end of taler-exchange-httpd_wire.c */
