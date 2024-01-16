/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_HashCode h;
  const char *cached;
  struct ExchangeSigningKeyDataP skv = {
    .start = GNUNET_TIME_timestamp_hton (es->ep_start),
    .expire = GNUNET_TIME_timestamp_hton (es->ep_expire),
    .end = GNUNET_TIME_timestamp_hton (es->ep_end),
    .signkey_pub = es->exchange_pub
  };
  const struct TALER_CoinSpendSignatureP *coin_sigps[
    GNUNET_NZL (dc->num_coins)];

  for (unsigned int i = 0; i < dc->num_coins; i++)
    coin_sigps[i] = &dc->coin_sigs[i];

  if (GNUNET_TIME_absolute_is_future (es->ep_start.abs_time) ||
      GNUNET_TIME_absolute_is_past (es->ep_expire.abs_time))
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
                      sizeof(skv),
                      &h);
  GNUNET_assert (0 == pthread_mutex_lock (&lock));
  cached = GNUNET_CONTAINER_multihashmap_get (cache,
                                              &h);
  GNUNET_assert (0 == pthread_mutex_unlock (&lock));
  if (GNUNET_SYSERR ==
      TAH_plugin->preflight (TAH_plugin->cls))
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
  if (GNUNET_OK !=
      TALER_exchange_online_deposit_confirmation_verify (
        &dc->h_contract_terms,
        &dc->h_wire,
        &dc->h_policy,
        dc->exchange_timestamp,
        dc->wire_deadline,
        dc->refund_deadline,
        &dc->total_without_fee,
        dc->num_coins,
        coin_sigps,
        &dc->merchant,
        &dc->exchange_pub,
        &dc->exchange_sig))
  {
    TALER_LOG_WARNING (
      "Invalid signature on /deposit-confirmation request\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_AUDITOR_DEPOSIT_CONFIRMATION_SIGNATURE_INVALID,
                                       "exchange signature invalid");
  }

  /* execute transaction */
  qs = TAH_plugin->insert_deposit_confirmation (TAH_plugin->cls,
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
  return TALER_MHD_REPLY_JSON_PACK (connection,
                                    MHD_HTTP_OK,
                                    GNUNET_JSON_pack_string ("status",
                                                             "DEPOSIT_CONFIRMATION_OK"));
}


MHD_RESULT
TAH_DEPOSIT_CONFIRMATION_handler (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size)
{
  struct TALER_AUDITORDB_DepositConfirmation dc = {
    .refund_deadline = GNUNET_TIME_UNIT_ZERO_TS
  };
  struct TALER_AUDITORDB_ExchangeSigningKey es;
  const json_t *jcoin_sigs;
  const json_t *jcoin_pubs;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &dc.h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("h_policy",
                                 &dc.h_policy),
    GNUNET_JSON_spec_fixed_auto ("h_wire",
                                 &dc.h_wire),
    GNUNET_JSON_spec_timestamp ("exchange_timestamp",
                                &dc.exchange_timestamp),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_timestamp ("refund_deadline",
                                  &dc.refund_deadline),
      NULL),
    GNUNET_JSON_spec_timestamp ("wire_deadline",
                                &dc.wire_deadline),
    TALER_JSON_spec_amount ("total_without_fee",
                            TAH_currency,
                            &dc.total_without_fee),
    GNUNET_JSON_spec_array_const ("coin_pubs",
                                  &jcoin_pubs),
    GNUNET_JSON_spec_array_const ("coin_sigs",
                                  &jcoin_sigs),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &dc.merchant),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &dc.exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &dc.exchange_pub),
    GNUNET_JSON_spec_fixed_auto ("master_pub",
                                 &es.master_public_key),
    GNUNET_JSON_spec_timestamp ("ep_start",
                                &es.ep_start),
    GNUNET_JSON_spec_timestamp ("ep_expire",
                                &es.ep_expire),
    GNUNET_JSON_spec_timestamp ("ep_end",
                                &es.ep_end),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &es.master_sig),
    GNUNET_JSON_spec_end ()
  };
  unsigned int num_coins;
  json_t *json;

  (void) rh;
  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_post_json (connection,
                                     connection_cls,
                                     upload_data,
                                     upload_data_size,
                                     &json);
    if (GNUNET_SYSERR == res)
      return MHD_NO;
    if ((GNUNET_NO == res) ||
        (NULL == json))
      return MHD_YES;
    res = TALER_MHD_parse_json_data (connection,
                                     json,
                                     spec);
    if (GNUNET_SYSERR == res)
    {
      json_decref (json);
      return MHD_NO;       /* hard failure */
    }
    if (GNUNET_NO == res)
    {
      json_decref (json);
      return MHD_YES;       /* failure */
    }
  }
  num_coins = json_array_size (jcoin_sigs);
  if (num_coins != json_array_size (jcoin_pubs))
  {
    GNUNET_break_op (0);
    json_decref (json);
    return TALER_MHD_reply_with_ec (
      connection,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "coin_pubs.length != coin_sigs.length");
  }
  if (0 == num_coins)
  {
    GNUNET_break_op (0);
    json_decref (json);
    return TALER_MHD_reply_with_ec (
      connection,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "coin_pubs array is empty");
  }
  {
    struct TALER_CoinSpendPublicKeyP coin_pubs[num_coins];
    struct TALER_CoinSpendSignatureP coin_sigs[num_coins];
    MHD_RESULT res;

    for (unsigned int i = 0; i < num_coins; i++)
    {
      json_t *jpub = json_array_get (jcoin_pubs,
                                     i);
      json_t *jsig = json_array_get (jcoin_sigs,
                                     i);
      const char *ps = json_string_value (jpub);
      const char *ss = json_string_value (jsig);

      if ((NULL == ps) ||
          (GNUNET_OK !=
           GNUNET_STRINGS_string_to_data (ps,
                                          strlen (ps),
                                          &coin_pubs[i],
                                          sizeof(coin_pubs[i]))))
      {
        GNUNET_break_op (0);
        json_decref (json);
        return TALER_MHD_reply_with_ec (
          connection,
          TALER_EC_GENERIC_PARAMETER_MALFORMED,
          "coin_pub[] malformed");
      }
      if ((NULL == ss) ||
          (GNUNET_OK !=
           GNUNET_STRINGS_string_to_data (ss,
                                          strlen (ss),
                                          &coin_sigs[i],
                                          sizeof(coin_sigs[i]))))
      {
        GNUNET_break_op (0);
        json_decref (json);
        return TALER_MHD_reply_with_ec (
          connection,
          TALER_EC_GENERIC_PARAMETER_MALFORMED,
          "coin_sig[] malformed");
      }
    }
    dc.num_coins = num_coins;
    dc.coin_pubs = coin_pubs;
    dc.coin_sigs = coin_sigs;
    es.exchange_pub = dc.exchange_pub;     /* used twice! */
    dc.master_public_key = es.master_public_key;
    res = verify_and_execute_deposit_confirmation (connection,
                                                   &dc,
                                                   &es);
    GNUNET_JSON_parse_free (spec);
    json_decref (json);
    return res;
  }
}


void
TEAH_DEPOSIT_CONFIRMATION_init (void)
{
  cache = GNUNET_CONTAINER_multihashmap_create (32,
                                                GNUNET_NO);
  GNUNET_assert (0 == pthread_mutex_init (&lock, NULL));
}


void
TEAH_DEPOSIT_CONFIRMATION_done (void)
{
  if (NULL != cache)
  {
    GNUNET_CONTAINER_multihashmap_destroy (cache);
    cache = NULL;
    GNUNET_assert (0 == pthread_mutex_destroy (&lock));
  }
}
