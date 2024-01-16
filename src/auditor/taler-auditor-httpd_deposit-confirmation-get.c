/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
 * @file taler-auditor-httpd_deposit-confirmation-get.c
 * @brief Handle /deposit-confirmation requests; return list of deposit confirmations from merchant
 * that were not received from the exchange, by auditor.
 * @author Nic Eigel
 */

#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-auditor-httpd.h"
#include "taler-auditor-httpd_deposit-confirmation-get.h"

GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Information about a signing key of the exchange.  Signing keys are used
 * to sign exchange messages other than coins, i.e. to confirm that a
 * deposit was successful or that a refresh was accepted.
 */
struct ExchangeSigningKeyDataP
{

  /**
   * When does this signing key begin to be valid?
   */
  struct GNUNET_TIME_TimestampNBO start;

  /**
   * When does this signing key expire? Note: This is currently when
   * the Exchange will definitively stop using it.  Signatures made with
   * the key remain valid until @e end.  When checking validity periods,
   * clients should allow for some overlap between keys and tolerate
   * the use of either key during the overlap time (due to the
   * possibility of clock skew).
   */
  struct GNUNET_TIME_TimestampNBO expire;

  /**
   * When do signatures with this signing key become invalid?  After
   * this point, these signatures cannot be used in (legal) disputes
   * anymore, as the Exchange is then allowed to destroy its side of the
   * evidence.  @e end is expected to be significantly larger than @e
   * expire (by a year or more).
   */
  struct GNUNET_TIME_TimestampNBO end;

  /**
   * The public online signing key that the exchange will use
   * between @e start and @e expire.
   */
  struct TALER_ExchangePublicKeyP signkey_pub;
};

GNUNET_NETWORK_STRUCT_END

/**
 * Cache of already verified exchange signing keys.  Maps the hash of the
 * `struct TALER_ExchangeSigningKeyValidityPS` to the (static) string
 * "verified" or "revoked".  Access to this map is guarded by the #lock.
 */
static struct GNUNET_CONTAINER_MultiHashMap *cache;

/**
 * Lock for operations on #cache.
 */
static pthread_mutex_t lock;


/**
 * Add deposit confirmation to the list.
 *
 * @param[in,out] cls a `json_t *` array to extend
 * @param serial_id location of the @a dc in the database
 * @param dc struct of deposit confirmation
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop iterating
 */
static enum GNUNET_GenericReturnValue
add_deposit_confirmation (void *cls,
                          uint64_t serial_id,
                          const struct TALER_AUDITORDB_DepositConfirmation *dc)
{
  json_t *list = cls;
  json_t *obj;

  obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("dc",
                                dc));
  GNUNET_break (0 ==
                json_array_append_new (list,
                                       obj));
  return GNUNET_OK;
}


/**
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
MHD_RESULT
TAH_DEPOSIT_CONFIRMATION_handler_get (struct TAH_RequestHandler *rh,
                                      struct MHD_Connection *connection,
                                      void **connection_cls,
                                      const char *upload_data,
                                      size_t *upload_data_size)
{
  json_t *ja;
  enum GNUNET_DB_QueryStatus qs;

  (void) rh;
  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  if (GNUNET_SYSERR ==
      TAH_plugin->preflight (TAH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_SETUP_FAILED,
                                       NULL);
  }
  ja = json_array ();
  GNUNET_break (NULL != ja);
  // TODO correct below
  struct TALER_AUDITORDB_ProgressPointDepositConfirmation ppdc = { 0 };   // FIXME: initialize...

  qs = TAH_plugin->get_deposit_confirmations (
    TAH_plugin->cls,
    ppdc.last_deposit_confirmation_serial_id,
    &add_deposit_confirmation,
    ja);

  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    json_decref (ja);
    TALER_LOG_WARNING (
      "Failed to handle GET /deposit-confirmation in database\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                                       "deposit-confirmation");
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_array_steal ("deposit-confirmation",
                                  ja));
}


void
TEAH_DEPOSIT_CONFIRMATION_GET_init (void)
{
  cache = GNUNET_CONTAINER_multihashmap_create (32,
                                                GNUNET_NO);
  GNUNET_assert (0 == pthread_mutex_init (&lock, NULL));
}


void
TEAH_DEPOSIT_CONFIRMATION_GET_done (void)
{
  if (NULL != cache)
  {
    GNUNET_CONTAINER_multihashmap_destroy (cache);
    cache = NULL;
    GNUNET_assert (0 == pthread_mutex_destroy (&lock));
  }
}


/*MHD_RESULT
TAH_DEPOSIT_CONFIRMATION_delete(struct TEH_RequestContext *rc,
                                const char *const args[1]) {
}*/


/* end of taler-auditor-httpd_deposit-confirmation.c */
