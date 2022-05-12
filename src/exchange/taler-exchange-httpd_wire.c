/*
  This file is part of TALER
  Copyright (C) 2015-2022 Taler Systems SA

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
#include "taler_dbevents.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_wire.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include <jansson.h>

/**
 * Information we track about wire fees.
 */
struct WireFeeSet
{

  /**
   * Kept in a DLL.
   */
  struct WireFeeSet *next;

  /**
   * Kept in a DLL.
   */
  struct WireFeeSet *prev;

  /**
   * Actual fees.
   */
  struct TALER_WireFeeSet fees;

  /**
   * Start date of fee validity (inclusive).
   */
  struct GNUNET_TIME_Timestamp start_date;

  /**
   * End date of fee validity (exclusive).
   */
  struct GNUNET_TIME_Timestamp end_date;

  /**
   * Wire method the fees apply to.
   */
  char *method;
};


/**
 * State we keep per thread to cache the /wire response.
 */
struct WireStateHandle
{
  /**
   * Cached reply for /wire response.
   */
  struct MHD_Response *wire_reply;

  /**
   * head of DLL of wire fees.
   */
  struct WireFeeSet *wfs_head;

  /**
   * Tail of DLL of wire fees.
   */
  struct WireFeeSet *wfs_tail;

  /**
   * For which (global) wire_generation was this data structure created?
   * Used to check when we are outdated and need to be re-generated.
   */
  uint64_t wire_generation;

  /**
   * HTTP status to return with this response.
   */
  unsigned int http_status;

};


/**
 * Stores the latest generation of our wire response.
 */
static struct WireStateHandle *wire_state;

/**
 * Handler listening for wire updates by other exchange
 * services.
 */
static struct GNUNET_DB_EventHandler *wire_eh;

/**
 * Counter incremented whenever we have a reason to re-build the #wire_state
 * because something external changed.
 */
static uint64_t wire_generation;


/**
 * Free memory associated with @a wsh
 *
 * @param[in] wsh wire state to destroy
 */
static void
destroy_wire_state (struct WireStateHandle *wsh)
{
  struct WireFeeSet *wfs;

  while (NULL != (wfs = wsh->wfs_head))
  {
    GNUNET_CONTAINER_DLL_remove (wsh->wfs_head,
                                 wsh->wfs_tail,
                                 wfs);
    GNUNET_free (wfs->method);
    GNUNET_free (wfs);
  }
  MHD_destroy_response (wsh->wire_reply);
  GNUNET_free (wsh);
}


/**
 * Function called whenever another exchange process has updated
 * the wire data in the database.
 *
 * @param cls NULL
 * @param extra unused
 * @param extra_size number of bytes in @a extra unused
 */
static void
wire_update_event_cb (void *cls,
                      const void *extra,
                      size_t extra_size)
{
  (void) cls;
  (void) extra;
  (void) extra_size;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received /wire update event\n");
  TEH_check_invariants ();
  wire_generation++;
}


enum GNUNET_GenericReturnValue
TEH_wire_init ()
{
  struct GNUNET_DB_EventHeaderP es = {
    .size = htons (sizeof (es)),
    .type = htons (TALER_DBEVENT_EXCHANGE_KEYS_UPDATED),
  };

  wire_eh = TEH_plugin->event_listen (TEH_plugin->cls,
                                      GNUNET_TIME_UNIT_FOREVER_REL,
                                      &es,
                                      &wire_update_event_cb,
                                      NULL);
  if (NULL == wire_eh)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


void
TEH_wire_done ()
{
  if (NULL != wire_state)
  {
    destroy_wire_state (wire_state);
    wire_state = NULL;
  }
  if (NULL != wire_eh)
  {
    TEH_plugin->event_listen_cancel (TEH_plugin->cls,
                                     wire_eh);
    wire_eh = NULL;
  }
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
        GNUNET_JSON_PACK (
          GNUNET_JSON_pack_string ("payto_uri",
                                   payto_uri),
          GNUNET_JSON_pack_data_auto ("master_sig",
                                      master_sig))))
  {
    GNUNET_break (0);   /* out of memory!? */
    return;
  }
}


/**
 * Closure for #add_wire_fee().
 */
struct AddContext
{
  /**
   * Wire method the fees are for.
   */
  char *wire_method;

  /**
   * Wire state we are building.
   */
  struct WireStateHandle *wsh;

  /**
   * Array to append the fee to.
   */
  json_t *a;

  /**
   * Context we hash "everything" we add into. This is used
   * to compute the etag. Technically, we only hash the
   * master_sigs, as they imply the rest.
   */
  struct GNUNET_HashContext *hc;

  /**
   * Set to the maximum end-date seen.
   */
  struct GNUNET_TIME_Absolute max_seen;
};


/**
 * Add information about a wire account to @a cls.
 *
 * @param cls a `struct AddContext`
 * @param fees the wire fees we charge
 * @param start_date from when are these fees valid (start date)
 * @param end_date until when are these fees valid (end date, exclusive)
 * @param master_sig master key signature affirming that this is the correct
 *                   fee (of purpose #TALER_SIGNATURE_MASTER_WIRE_FEES)
 */
static void
add_wire_fee (void *cls,
              const struct TALER_WireFeeSet *fees,
              struct GNUNET_TIME_Timestamp start_date,
              struct GNUNET_TIME_Timestamp end_date,
              const struct TALER_MasterSignatureP *master_sig)
{
  struct AddContext *ac = cls;
  struct WireFeeSet *wfs;

  GNUNET_CRYPTO_hash_context_read (ac->hc,
                                   master_sig,
                                   sizeof (*master_sig));
  ac->max_seen = GNUNET_TIME_absolute_max (ac->max_seen,
                                           end_date.abs_time);
  wfs = GNUNET_new (struct WireFeeSet);
  wfs->start_date = start_date;
  wfs->end_date = end_date;
  wfs->fees = *fees;
  wfs->method = GNUNET_strdup (ac->wire_method);
  GNUNET_CONTAINER_DLL_insert (ac->wsh->wfs_head,
                               ac->wsh->wfs_tail,
                               wfs);
  if (0 !=
      json_array_append_new (
        ac->a,
        GNUNET_JSON_PACK (
          TALER_JSON_pack_amount ("wire_fee",
                                  &fees->wire),
          TALER_JSON_pack_amount ("wad_fee",
                                  &fees->wad),
          TALER_JSON_pack_amount ("closing_fee",
                                  &fees->closing),
          GNUNET_JSON_pack_timestamp ("start_date",
                                      start_date),
          GNUNET_JSON_pack_timestamp ("end_date",
                                      end_date),
          GNUNET_JSON_pack_data_auto ("sig",
                                      master_sig))))
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
  uint64_t wg = wire_generation; /* must be obtained FIRST */
  enum GNUNET_DB_QueryStatus qs;
  struct WireStateHandle *wsh;
  struct GNUNET_TIME_Absolute cache_expiration;
  struct GNUNET_HashContext *hc;

  wsh = GNUNET_new (struct WireStateHandle);
  wsh->wire_generation = wg;
  wire_accounts_array = json_array ();
  GNUNET_assert (NULL != wire_accounts_array);
  qs = TEH_plugin->get_wire_accounts (TEH_plugin->cls,
                                      &add_wire_account,
                                      wire_accounts_array);
  if (0 > qs)
  {
    GNUNET_break (0);
    json_decref (wire_accounts_array);
    wsh->http_status = MHD_HTTP_INTERNAL_SERVER_ERROR;
    wsh->wire_reply
      = TALER_MHD_make_error (TALER_EC_GENERIC_DB_FETCH_FAILED,
                              "get_wire_accounts");
    return wsh;
  }
  if (0 == json_array_size (wire_accounts_array))
  {
    json_decref (wire_accounts_array);
    wsh->http_status = MHD_HTTP_INTERNAL_SERVER_ERROR;
    wsh->wire_reply
      = TALER_MHD_make_error (TALER_EC_EXCHANGE_WIRE_NO_ACCOUNTS_CONFIGURED,
                              NULL);
    return wsh;
  }
  wire_fee_object = json_object ();
  GNUNET_assert (NULL != wire_fee_object);
  cache_expiration = GNUNET_TIME_UNIT_ZERO_ABS;
  hc = GNUNET_CRYPTO_hash_context_start ();
  {
    json_t *account;
    size_t index;

    json_array_foreach (wire_accounts_array, index, account) {
      char *wire_method;
      const char *payto_uri = json_string_value (json_object_get (account,
                                                                  "payto_uri"));

      GNUNET_assert (NULL != payto_uri);
      wire_method = TALER_payto_get_method (payto_uri);
      if (NULL == wire_method)
      {
        wsh->http_status = MHD_HTTP_INTERNAL_SERVER_ERROR;
        wsh->wire_reply
          = TALER_MHD_make_error (
              TALER_EC_EXCHANGE_WIRE_INVALID_PAYTO_CONFIGURED,
              payto_uri);
        json_decref (wire_accounts_array);
        json_decref (wire_fee_object);
        GNUNET_CRYPTO_hash_context_abort (hc);
        return wsh;
      }
      if (NULL == json_object_get (wire_fee_object,
                                   wire_method))
      {
        struct AddContext ac = {
          .wire_method = wire_method,
          .wsh = wsh,
          .a = json_array (),
          .hc = hc
        };

        GNUNET_assert (NULL != ac.a);
        qs = TEH_plugin->get_wire_fees (TEH_plugin->cls,
                                        wire_method,
                                        &add_wire_fee,
                                        &ac);
        if (0 > qs)
        {
          GNUNET_break (0);
          json_decref (ac.a);
          json_decref (wire_fee_object);
          json_decref (wire_accounts_array);
          GNUNET_free (wire_method);
          wsh->http_status = MHD_HTTP_INTERNAL_SERVER_ERROR;
          wsh->wire_reply
            = TALER_MHD_make_error (TALER_EC_GENERIC_DB_FETCH_FAILED,
                                    "get_wire_fees");
          GNUNET_CRYPTO_hash_context_abort (hc);
          return wsh;
        }
        if (0 == json_array_size (ac.a))
        {
          json_decref (ac.a);
          json_decref (wire_accounts_array);
          json_decref (wire_fee_object);
          wsh->http_status = MHD_HTTP_INTERNAL_SERVER_ERROR;
          wsh->wire_reply
            = TALER_MHD_make_error (TALER_EC_EXCHANGE_WIRE_FEES_NOT_CONFIGURED,
                                    wire_method);
          GNUNET_free (wire_method);
          GNUNET_CRYPTO_hash_context_abort (hc);
          return wsh;
        }
        cache_expiration = GNUNET_TIME_absolute_min (ac.max_seen,
                                                     cache_expiration);
        GNUNET_assert (0 ==
                       json_object_set_new (wire_fee_object,
                                            wire_method,
                                            ac.a));
      }
      GNUNET_free (wire_method);
    }
  }


  wsh->wire_reply = TALER_MHD_MAKE_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("accounts",
                                  wire_accounts_array),
    GNUNET_JSON_pack_object_steal ("fees",
                                   wire_fee_object),
    GNUNET_JSON_pack_data_auto ("master_public_key",
                                &TEH_master_public_key));
  {
    char dat[128];
    struct GNUNET_TIME_Timestamp m;

    m = GNUNET_TIME_absolute_to_timestamp (cache_expiration);
    TALER_MHD_get_date_string (m.abs_time,
                               dat);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Setting 'Expires' header for '/wire' to '%s'\n",
                dat);
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (wsh->wire_reply,
                                           MHD_HTTP_HEADER_EXPIRES,
                                           dat));
  }
  TALER_MHD_add_global_headers (wsh->wire_reply);
  {
    struct GNUNET_HashCode h;
    char etag[sizeof (h) * 2];
    char *end;

    GNUNET_CRYPTO_hash_context_finish (hc,
                                       &h);
    end = GNUNET_STRINGS_data_to_string (&h,
                                         sizeof (h),
                                         etag,
                                         sizeof (etag));
    *end = '\0';
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (wsh->wire_reply,
                                           MHD_HTTP_HEADER_ETAG,
                                           etag));
  }
  wsh->http_status = MHD_HTTP_OK;
  return wsh;
}


void
TEH_wire_update_state (void)
{
  struct GNUNET_DB_EventHeaderP es = {
    .size = htons (sizeof (es)),
    .type = htons (TALER_DBEVENT_EXCHANGE_WIRE_UPDATED),
  };

  TEH_plugin->event_notify (TEH_plugin->cls,
                            &es,
                            NULL,
                            0);
  wire_generation++;
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

  old_wsh = wire_state;
  if ( (NULL == old_wsh) ||
       (old_wsh->wire_generation < wire_generation) )
  {
    struct WireStateHandle *wsh;

    TEH_check_invariants ();
    wsh = build_wire_state ();
    wire_state = wsh;
    if (NULL != old_wsh)
      destroy_wire_state (old_wsh);
    TEH_check_invariants ();
    return wsh;
  }
  return old_wsh;
}


MHD_RESULT
TEH_handler_wire (struct TEH_RequestContext *rc,
                  const char *const args[])
{
  struct WireStateHandle *wsh;

  (void) args;
  wsh = get_wire_state ();
  if (NULL == wsh)
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_BAD_CONFIGURATION,
                                       NULL);
  return MHD_queue_response (rc->connection,
                             wsh->http_status,
                             wsh->wire_reply);
}


const struct TALER_WireFeeSet *
TEH_wire_fees_by_time (
  struct GNUNET_TIME_Timestamp ts,
  const char *method)
{
  struct WireStateHandle *wsh = get_wire_state ();

  for (struct WireFeeSet *wfs = wsh->wfs_head;
       NULL != wfs;
       wfs = wfs->next)
  {
    if (0 != strcmp (method,
                     wfs->method))
      continue;
    if ( (GNUNET_TIME_timestamp_cmp (wfs->start_date,
                                     >,
                                     ts)) ||
         (GNUNET_TIME_timestamp_cmp (ts,
                                     >=,
                                     wfs->end_date)) )
      continue;
    return &wfs->fees;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "No wire fees for method `%s' at %s configured\n",
              method,
              GNUNET_TIME_timestamp2s (ts));
  return NULL;
}


/* end of taler-exchange-httpd_wire.c */
