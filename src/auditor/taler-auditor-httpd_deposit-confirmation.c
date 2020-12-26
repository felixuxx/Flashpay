/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file taler-auditor-httpd_deposit-confirmation.c
 * @brief Handle /deposit-confirmation requests; parses the POST and JSON and
 *        verifies the coin signature before handing things off
 *        to the database.
 * @author Christian Grothoff
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
#include "taler-auditor-httpd_deposit-confirmation.h"


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
 * We have parsed the JSON information about the deposit, do some
 * basic sanity checks (especially that the signature on the coin is
 * valid, and that this type of coin exists) and then execute the
 * deposit.
 *
 * @param connection the MHD connection to handle
 * @param dc information about the deposit confirmation
 * @param es information about the exchange's signing key
 * @return MHD result code
 */
static MHD_RESULT
verify_and_execute_deposit_confirmation (
  struct MHD_Connection *connection,
  const struct TALER_AUDITORDB_DepositConfirmation *dc,
  const struct TALER_AUDITORDB_ExchangeSigningKey *es)
{
  struct TALER_AUDITORDB_Session *session;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_HashCode h;
  const char *cached;
  struct TALER_ExchangeSigningKeyValidityPS skv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY),
    .purpose.size = htonl (sizeof (struct TALER_ExchangeSigningKeyValidityPS)),
    .master_public_key = es->master_public_key,
    .start = GNUNET_TIME_absolute_hton (es->ep_start),
    .expire = GNUNET_TIME_absolute_hton (es->ep_expire),
    .end = GNUNET_TIME_absolute_hton (es->ep_end),
    .signkey_pub = es->exchange_pub
  };

  now = GNUNET_TIME_absolute_get ();
  if ( (es->ep_start.abs_value_us > now.abs_value_us) ||
       (es->ep_expire.abs_value_us < now.abs_value_us) )
  {
    /* Signing key expired */
    TALER_LOG_WARNING ("Expired exchange signing key\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_AUDITOR_DEPOSIT_CONFIRMATION_SIGNATURE_INVALID,
                                       "master signature expired");
  }

  /* check our cache */
  GNUNET_CRYPTO_hash (&skv,
                      sizeof (skv),
                      &h);
  GNUNET_assert (0 == pthread_mutex_lock (&lock));
  cached = GNUNET_CONTAINER_multihashmap_get (cache,
                                              &h);
  GNUNET_assert (0 == pthread_mutex_unlock (&lock));
  session = TAH_plugin->get_session (TAH_plugin->cls);
  if (NULL == session)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_SETUP_FAILED,
                                       NULL);
  }
  if (NULL == cached)
  {
    /* Not in cache, need to verify the signature, persist it, and possibly cache it */
    if (GNUNET_OK !=
        TALER_exchange_offline_signkey_validity_verify (
          &es->exchange_pub,
          es->ep_start,
          es->ep_expire,
          es->ep_end,
          &es->master_public_key,
          &es->master_sig))
    {
      TALER_LOG_WARNING ("Invalid signature on exchange signing key\n");
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_AUDITOR_DEPOSIT_CONFIRMATION_SIGNATURE_INVALID,
                                         "master signature invalid");
    }

    /* execute transaction */
    qs = TAH_plugin->insert_exchange_signkey (TAH_plugin->cls,
                                              session,
                                              es);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
      TALER_LOG_WARNING ("Failed to store exchange signing key in database\n");
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_STORE_FAILED,
                                         "exchange signing key");
    }
    cached = "verified";
  }

  if (0 == strcmp (cached,
                   "verified"))
  {
    struct TALER_MasterSignatureP master_sig;

    /* check for revocation */
    qs = TAH_eplugin->lookup_signkey_revocation (TAH_eplugin->cls,
                                                 NULL,
                                                 &es->exchange_pub,
                                                 &master_sig);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
      TALER_LOG_WARNING (
        "Failed to check for signing key revocation in database\n");
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "exchange signing key revocation");
    }
    if (0 < qs)
      cached = "revoked";
  }

  /* Cache it, due to concurreny it might already be in the cache,
     so we do not cache it twice but also don't insist on the 'put' to
     succeed. */
  GNUNET_assert (0 == pthread_mutex_lock (&lock));
  (void) GNUNET_CONTAINER_multihashmap_put (cache,
                                            &h,
                                            (void *) cached,
                                            GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY);
  GNUNET_assert (0 == pthread_mutex_unlock (&lock));

  if (0 == strcmp (cached,
                   "revoked"))
  {
    TALER_LOG_WARNING (
      "Invalid signature on /deposit-confirmation request: key was revoked\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_GONE,
                                       TALER_EC_AUDITOR_EXCHANGE_SIGNING_KEY_REVOKED,
                                       "exchange signing key was revoked");
  }

  /* check deposit confirmation signature */
  {
    struct TALER_DepositConfirmationPS dcs = {
      .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT),
      .purpose.size = htonl (sizeof (struct TALER_DepositConfirmationPS)),
      .h_contract_terms = dc->h_contract_terms,
      .h_wire = dc->h_wire,
      .exchange_timestamp = GNUNET_TIME_absolute_hton (dc->exchange_timestamp),
      .refund_deadline = GNUNET_TIME_absolute_hton (dc->refund_deadline),
      .coin_pub = dc->coin_pub,
      .merchant = dc->merchant
    };

    TALER_amount_hton (&dcs.amount_without_fee,
                       &dc->amount_without_fee);
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT,
                                    &dcs,
                                    &dc->exchange_sig.eddsa_signature,
                                    &dc->exchange_pub.eddsa_pub))
    {
      TALER_LOG_WARNING (
        "Invalid signature on /deposit-confirmation request\n");
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_AUDITOR_DEPOSIT_CONFIRMATION_SIGNATURE_INVALID,
                                         "exchange signature invalid");
    }
  }

  /* execute transaction */
  qs = TAH_plugin->insert_deposit_confirmation (TAH_plugin->cls,
                                                session,
                                                dc);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    TALER_LOG_WARNING ("Failed to store /deposit-confirmation in database\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_STORE_FAILED,
                                       "deposit confirmation");
  }
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:s}",
                                    "status", "DEPOSIT_CONFIRMATION_OK");
}


/**
 * Handle a "/deposit-confirmation" request.  Parses the JSON, and, if
 * successful, passes the JSON data to #verify_and_execute_deposit_confirmation()
 * to further check the details of the operation specified.  If
 * everything checks out, this will ultimately lead to the "/deposit-confirmation"
 * being stored in the database.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
MHD_RESULT
TAH_DEPOSIT_CONFIRMATION_handler (struct TAH_RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  void **connection_cls,
                                  const char *upload_data,
                                  size_t *upload_data_size)
{
  struct TALER_AUDITORDB_DepositConfirmation dc;
  struct TALER_AUDITORDB_ExchangeSigningKey es;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms", &dc.h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("h_wire", &dc.h_wire),
    TALER_JSON_spec_absolute_time ("exchange_timestamp",
                                   &dc.exchange_timestamp),
    TALER_JSON_spec_absolute_time ("refund_deadline", &dc.refund_deadline),
    TALER_JSON_spec_amount ("amount_without_fee", &dc.amount_without_fee),
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &dc.coin_pub),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub", &dc.merchant),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",  &dc.exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",  &dc.exchange_pub),
    GNUNET_JSON_spec_fixed_auto ("master_pub",  &es.master_public_key),
    TALER_JSON_spec_absolute_time ("ep_start",  &es.ep_start),
    TALER_JSON_spec_absolute_time ("ep_expire",  &es.ep_expire),
    TALER_JSON_spec_absolute_time ("ep_end",  &es.ep_end),
    GNUNET_JSON_spec_fixed_auto ("master_sig",  &es.master_sig),
    GNUNET_JSON_spec_end ()
  };

  (void) rh;
  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  {
    json_t *json;
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_post_json (connection,
                                     connection_cls,
                                     upload_data,
                                     upload_data_size,
                                     &json);
    if (GNUNET_SYSERR == res)
      return MHD_NO;
    if ( (GNUNET_NO == res) ||
         (NULL == json) )
      return MHD_YES;
    res = TALER_MHD_parse_json_data (connection,
                                     json,
                                     spec);
    json_decref (json);
    if (GNUNET_SYSERR == res)
      return MHD_NO; /* hard failure */
    if (GNUNET_NO == res)
      return MHD_YES; /* failure */
  }

  es.exchange_pub = dc.exchange_pub; /* used twice! */
  dc.master_public_key = es.master_public_key;
  {
    MHD_RESULT res;

    res = verify_and_execute_deposit_confirmation (connection,
                                                   &dc,
                                                   &es);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/**
 * Initialize subsystem.
 */
void
TEAH_DEPOSIT_CONFIRMATION_init (void)
{
  cache = GNUNET_CONTAINER_multihashmap_create (32,
                                                GNUNET_NO);
  GNUNET_assert (0 == pthread_mutex_init (&lock, NULL));
}


/**
 * Shut down subsystem.
 */
void
TEAH_DEPOSIT_CONFIRMATION_done (void)
{
  GNUNET_CONTAINER_multihashmap_destroy (cache);
  cache = NULL;
  GNUNET_assert (0 == pthread_mutex_destroy (&lock));
}


/* end of taler-auditor-httpd_deposit-confirmation.c */
