/*
  This file is part of TALER
  Copyright (C) 2014-2017 GNUnet e.V.

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
 * @file taler-exchange-httpd_keystate.c
 * @brief management of our coin signing keys
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_plugin.h"


/**
 * Snapshot of the (coin and signing) keys (including private keys) of
 * the exchange.  There can be multiple instances of this struct, as it is
 * reference counted and only destroyed once the last user is done
 * with it.  The current instance is acquired using
 * #TEH_KS_acquire().  Using this function increases the
 * reference count.  The contents of this structure (except for the
 * reference counter) should be considered READ-ONLY until it is
 * ultimately destroyed (as there can be many concurrent users).
 */
struct TEH_KS_StateHandle
{
  /**
   * JSON array with denomination keys.  (Currently not really used
   * after initialization.)
   */
  json_t *denom_keys_array;

  /**
   * JSON array with signing keys. (Currently not really used
   * after initialization.)
   */
  json_t *sign_keys_array;

  /**
   * JSON array with auditor information. (Currently not really used
   * after initialization.)
   */
  json_t *auditors_array;

  /**
   * JSON array with revoked denomination keys. (Currently not really used
   * after initialization).
   */
  json_t *payback_array;

  /**
   * Cached JSON text that the exchange will send for a "/keys" request.
   * Includes our @e TEH_master_public_key public key, the signing and
   * denomination keys as well as the @e reload_time.
   */
  char *keys_json;

  /**
   * Mapping from denomination keys to denomination key issue struct.
   * Used to lookup the key by hash.
   */
  struct GNUNET_CONTAINER_MultiHashMap *denomkey_map;

  /**
   * Mapping from revoked denomination keys to denomination key issue struct.
   * Used to lookup the key by hash.
   */
  struct GNUNET_CONTAINER_MultiHashMap *revoked_map;

  /**
   * Hash context we used to combine the hashes of all denomination
   * keys into one big hash.
   */
  struct GNUNET_HashContext *hash_context;

  /**
   * When did we initiate the key reloading?
   */
  struct GNUNET_TIME_Absolute reload_time;

  /**
   * When is the next key invalid and we have to reload? (We also
   * reload on SIGUSR1.)
   */
  struct GNUNET_TIME_Absolute next_reload;

  /**
   * When does the first active denomination key expire (for deposit)?
   */
  struct GNUNET_TIME_Absolute min_dk_expire;

  /**
   * Exchange signing key that should be used currently.
   */
  struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP current_sign_key_issue;

  /**
   * Reference count.  The struct is released when the RC hits zero.
   */
  unsigned int refcnt;
};


/**
 * Exchange key state.  Never use directly, instead access via
 * #TEH_KS_acquire() and #TEH_KS_release().
 */
static struct TEH_KS_StateHandle *internal_key_state;

/**
 * Mutex protecting access to #internal_key_state.
 */
static pthread_mutex_t internal_key_state_mutex = PTHREAD_MUTEX_INITIALIZER;

/**
 * Pipe used for signaling reloading of our key state.
 */
static int reload_pipe[2];


/**
 * Convert the public part of a denomination key issue to a JSON
 * object.
 *
 * @param pk public key of the denomination key
 * @param dki the denomination key issue
 * @return a JSON object describing the denomination key isue (public part)
 */
static json_t *
denom_key_issue_to_json (const struct TALER_DenominationPublicKey *pk,
                         const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki)
{
  struct TALER_Amount value;
  struct TALER_Amount fee_withdraw;
  struct TALER_Amount fee_deposit;
  struct TALER_Amount fee_refresh;
  struct TALER_Amount fee_refund;

  TALER_amount_ntoh (&value,
                     &dki->properties.value);
  TALER_amount_ntoh (&fee_withdraw,
                     &dki->properties.fee_withdraw);
  TALER_amount_ntoh (&fee_deposit,
                     &dki->properties.fee_deposit);
  TALER_amount_ntoh (&fee_refresh,
                     &dki->properties.fee_refresh);
  TALER_amount_ntoh (&fee_refund,
                     &dki->properties.fee_refund);
  return
    json_pack ("{s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o}",
               "master_sig",
               GNUNET_JSON_from_data_auto (&dki->signature),
               "stamp_start",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (dki->properties.start)),
               "stamp_expire_withdraw",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (dki->properties.expire_withdraw)),
               "stamp_expire_deposit",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (dki->properties.expire_deposit)),
               "stamp_expire_legal",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (dki->properties.expire_legal)),
               "denom_pub",
               GNUNET_JSON_from_rsa_public_key (pk->rsa_public_key),
               "value",
               TALER_JSON_from_amount (&value),
               "fee_withdraw",
               TALER_JSON_from_amount (&fee_withdraw),
               "fee_deposit",
               TALER_JSON_from_amount (&fee_deposit),
               "fee_refresh",
               TALER_JSON_from_amount (&fee_refresh),
               "fee_refund",
               TALER_JSON_from_amount (&fee_refund));
}


/**
 * Get the relative time value that describes how
 * far in the future do we want to provide coin keys.
 *
 * @return the provide duration
 */
static struct GNUNET_TIME_Relative
TALER_EXCHANGE_conf_duration_provide ()
{
  struct GNUNET_TIME_Relative rel;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchange_keys",
                                           "lookahead_provide",
                                           &rel))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange_keys",
                               "lookahead_provide",
                               "time value required");
    GNUNET_assert (0);
  }
  return rel;
}


/**
 * Store a copy of @a dki in @a map.
 *
 * @param map hash map to store @a dki in
 * @param dki information to store in @a map
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if such an entry already exists
 */
static int
store_in_map (struct GNUNET_CONTAINER_MultiHashMap *map,
              const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki)
{
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *d2;
  int res;

  d2 = GNUNET_new (struct TALER_EXCHANGEDB_DenominationKeyIssueInformation);
  d2->issue = dki->issue;
  d2->denom_priv.rsa_private_key
    = GNUNET_CRYPTO_rsa_private_key_dup (dki->denom_priv.rsa_private_key);
  d2->denom_pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_public_key_dup (dki->denom_pub.rsa_public_key);
  res = GNUNET_CONTAINER_multihashmap_put (map,
                                           &d2->issue.properties.denom_hash,
                                           d2,
                                           GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY);
  if (GNUNET_OK != res)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Duplicate denomination key `%s'\n",
                GNUNET_h2s (&d2->issue.properties.denom_hash));
    GNUNET_CRYPTO_rsa_private_key_free (d2->denom_priv.rsa_private_key);
    GNUNET_CRYPTO_rsa_public_key_free (d2->denom_pub.rsa_public_key);
    GNUNET_free (d2);
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


/**
 * Iterator for (re)loading/initializing denomination keys.
 *
 * @param cls closure
 * @param dki the denomination key issue
 * @param alias coin alias
 * @param was_revoked #GNUNET_YES if @a dki has been revoked
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
reload_keys_denom_iter (void *cls,
                        const char *alias,
                        const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki,
                        int was_revoked)
{
  struct TEH_KS_StateHandle *ctx = cls;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute horizon;
  struct GNUNET_TIME_Absolute expire_deposit;
  struct GNUNET_HashCode denom_key_hash;
  struct TALER_EXCHANGEDB_Session *session;
  int res;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Loading denomination key `%s'\n",
              alias);
  now = GNUNET_TIME_absolute_get ();
  expire_deposit = GNUNET_TIME_absolute_ntoh (dki->issue.properties.expire_deposit);
  if (expire_deposit.abs_value_us < now.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping expired denomination key `%s'\n",
                alias);
    return GNUNET_OK;
  }
  if (GNUNET_YES == was_revoked)
  {
    res = store_in_map (ctx->revoked_map,
                        dki);
    if (GNUNET_NO == res)
      return GNUNET_OK;
    GNUNET_assert (0 ==
                   json_array_append_new (ctx->payback_array,
                                          GNUNET_JSON_from_data_auto (&dki->issue.properties.denom_hash)));
    return GNUNET_OK;
  }
  horizon = GNUNET_TIME_relative_to_absolute (TALER_EXCHANGE_conf_duration_provide ());
  if (GNUNET_TIME_absolute_ntoh (dki->issue.properties.start).abs_value_us >
      horizon.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping future denomination key `%s'\n",
                alias);
    return GNUNET_OK;
  }

  GNUNET_CRYPTO_rsa_public_key_hash (dki->denom_pub.rsa_public_key,
                                     &denom_key_hash);
  GNUNET_CRYPTO_hash_context_read (ctx->hash_context,
                                   &denom_key_hash,
                                   sizeof (struct GNUNET_HashCode));

  if (0 != memcmp (&dki->issue.properties.master,
                   &TEH_master_public_key,
                   sizeof (struct TALER_MasterPublicKeyP)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Master key in denomination key file `%s' does not match! Skipping it.\n",
                alias);
    return GNUNET_OK;
  }


  session = TEH_plugin->get_session (TEH_plugin->cls);
  if (NULL == session)
    return GNUNET_SYSERR;
  /* Try to insert DKI into DB until we succeed; note that if the DB
     failure is persistent, this code may loop forever (as there is no
     sane alternative, we cannot continue without the DKI being in the
     DB). */
  res = GNUNET_SYSERR;
  while (GNUNET_OK != res)
  {
    res = TEH_plugin->start (TEH_plugin->cls,
                             session);
    if (GNUNET_OK != res)
    {
      /* Transaction start failed!? Very bad error, log and retry */
      GNUNET_break (0);
      continue;
    }
    res = TEH_plugin->get_denomination_info (TEH_plugin->cls,
                                             session,
                                             &dki->denom_pub,
                                             NULL);
    if (GNUNET_SYSERR == res)
    {
      /* Fetch failed!? Very bad error, log and retry */
      GNUNET_break (0);
      TEH_plugin->rollback (TEH_plugin->cls,
                            session);
      continue;
    }
    if (GNUNET_OK == res)
    {
      /* Record exists, we're good, just exit */
      TEH_plugin->rollback (TEH_plugin->cls,
                            session);
      break;
    }
    res = TEH_plugin->insert_denomination_info (TEH_plugin->cls,
                                                session,
                                                &dki->denom_pub,
                                                &dki->issue);
    if (GNUNET_OK != res)
    {
      /* Insert failed!? Very bad error, log and retry */
      GNUNET_break (0);
      TEH_plugin->rollback (TEH_plugin->cls,
                            session);
      continue;
    }
    res = TEH_plugin->commit (TEH_plugin->cls,
                              session);
    /* If commit succeeded, we're done, otherwise we retry; this
       time without logging, as theroetically commits can fail
       in a transactional DB due to concurrent activities that
       cannot be reconciled. This should be rare for DKIs, but
       as it is possible we just retry until we succeed. */
  }

  res = store_in_map (ctx->denomkey_map,
                      dki);
  if (GNUNET_NO == res)
    return GNUNET_OK;
  ctx->min_dk_expire = GNUNET_TIME_absolute_min (ctx->min_dk_expire,
                                                 expire_deposit);
  GNUNET_assert (0 ==
                 json_array_append_new (ctx->denom_keys_array,
                                        denom_key_issue_to_json (&dki->denom_pub,
                                                                 &dki->issue)));
  return GNUNET_OK;
}


/**
 * Convert the public part of a sign key issue to a JSON object.
 *
 * @param ski the sign key issue
 * @return a JSON object describing the sign key issue (public part)
 */
static json_t *
sign_key_issue_to_json (const struct TALER_ExchangeSigningKeyValidityPS *ski)
{
  return
    json_pack ("{s:o, s:o, s:o, s:o, s:o}",
               "stamp_start",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (ski->start)),
               "stamp_expire",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (ski->expire)),
               "stamp_end",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (ski->end)),
               "master_sig",
               GNUNET_JSON_from_data_auto (&ski->signature),
               "key",
               GNUNET_JSON_from_data_auto (&ski->signkey_pub));
}


/**
 * Iterator for sign keys.
 *
 * @param cls closure with the `struct TEH_KS_StateHandle *`
 * @param filename name of the file the key came from
 * @param ski the sign key issue
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
reload_keys_sign_iter (void *cls,
                       const char *filename,
                       const struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP *ski)
{
  struct TEH_KS_StateHandle *ctx = cls;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute horizon;

  horizon = GNUNET_TIME_relative_to_absolute (TALER_EXCHANGE_conf_duration_provide ());
  if (GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us >
      horizon.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping future signing key `%s'\n",
                filename);
    return GNUNET_OK;
  }
  now = GNUNET_TIME_absolute_get ();
  if (GNUNET_TIME_absolute_ntoh (ski->issue.expire).abs_value_us <
      now.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Skipping expired signing key `%s'\n",
                filename);
    return GNUNET_OK;
  }

  if (0 != memcmp (&ski->issue.master_public_key,
                   &TEH_master_public_key,
                   sizeof (struct TALER_MasterPublicKeyP)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Master key in signing key file `%s' does not match! Skipping it.\n",
                filename);
    return GNUNET_OK;
  }

  /* The signkey is valid at this time, check if it's more recent than
     what we have so far! */
  if ( (GNUNET_TIME_absolute_ntoh (ctx->current_sign_key_issue.issue.start).abs_value_us <
        GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us) &&
       (GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us <
        now.abs_value_us) )
  {
    /* We use the most recent one, if it is valid now (not just in the near future) */
    ctx->current_sign_key_issue = *ski;
  }
  GNUNET_assert (0 ==
                 json_array_append_new (ctx->sign_keys_array,
                                        sign_key_issue_to_json (&ski->issue)));

  return GNUNET_OK;
}


/**
 * Convert information from an auditor to a JSON object.
 *
 * @param apub the auditor's public key
 * @param auditor_url URL of the auditor
 * @param dki_len length of @a dki and @a asigs arrays
 * @param asigs the auditor's signatures
 * @param dki array of denomination coin data signed by the auditor
 * @return a JSON object describing the auditor information and signature
 */
static json_t *
auditor_to_json (const struct TALER_AuditorPublicKeyP *apub,
                 const char *auditor_url,
                 unsigned int dki_len,
                 const struct TALER_AuditorSignatureP **asigs,
                 const struct TALER_DenominationKeyValidityPS **dki)
{
  unsigned int i;
  json_t *ja;

  ja = json_array ();
  for (i=0;i<dki_len;i++)
    GNUNET_assert (0 ==
                   json_array_append_new (ja,
                                          json_pack ("{s:o, s:o}",
                                                     "denom_pub_h",
                                                     GNUNET_JSON_from_data_auto (&dki[i]->denom_hash),
                                                     "auditor_sig",
                                                     GNUNET_JSON_from_data_auto (asigs[i]))));
  return
    json_pack ("{s:o, s:s, s:o}",
               "denomination_keys", ja,
               "auditor_url", auditor_url,
               "auditor_pub",
               GNUNET_JSON_from_data_auto (apub));
}


/**
 * @brief Iterator called with auditor information.
 * Check that the @a mpub actually matches this exchange, and then
 * add the auditor information to our /keys response (if it is
 * (still) applicable).
 *
 * @param cls closure with the `struct TEH_KS_StateHandle *`
 * @param apub the auditor's public key
 * @param auditor_url URL of the auditor
 * @param mpub the exchange's public key (as expected by the auditor)
 * @param dki_len length of @a dki and @a asigs
 * @param asigs array with the auditor's signatures, of length @a dki_len
 * @param dki array of denomination coin data signed by the auditor
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
reload_auditor_iter (void *cls,
                     const struct TALER_AuditorPublicKeyP *apub,
                     const char *auditor_url,
                     const struct TALER_MasterPublicKeyP *mpub,
                     unsigned int dki_len,
                     const struct TALER_AuditorSignatureP *asigs,
                     const struct TALER_DenominationKeyValidityPS *dki)
{
  struct TEH_KS_StateHandle *ctx = cls;
  unsigned int i;
  unsigned int keep;
  const struct TALER_AuditorSignatureP *kept_asigs[dki_len];
  const struct TALER_DenominationKeyValidityPS *kept_dkis[dki_len];

  /* Check if the signature is at least for this exchange. */
  if (0 != memcmp (&mpub->eddsa_pub,
                   &TEH_master_public_key,
                   sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Auditing information provided for a different exchange, ignored\n");
    return GNUNET_OK;
  }
  /* Filter the auditor information for those for which the
     keys actually match the denomination keys that are active right now */
  keep = 0;
  for (i=0;i<dki_len;i++)
  {
    if (GNUNET_YES ==
        GNUNET_CONTAINER_multihashmap_contains (ctx->denomkey_map,
                                                &dki[i].denom_hash))
    {
      kept_asigs[keep] = &asigs[i];
      kept_dkis[keep] = &dki[i];
      keep++;
    }
  }
  /* add auditor information to our /keys response */
  GNUNET_assert (0 ==
                 json_array_append_new (ctx->auditors_array,
                                        auditor_to_json (apub,
                                                         auditor_url,
                                                         keep,
                                                         kept_asigs,
                                                         kept_dkis)));
  return GNUNET_OK;
}


/**
 * Iterator for freeing denomination keys.
 *
 * @param cls closure with the `struct TEH_KS_StateHandle`
 * @param key key for the denomination key
 * @param value coin details
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
free_denom_key (void *cls,
                const struct GNUNET_HashCode *key,
                void *value)
{
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki = value;

  GNUNET_CRYPTO_rsa_private_key_free (dki->denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_free (dki->denom_pub.rsa_public_key);
  GNUNET_free (dki);
  return GNUNET_OK;
}


/**
 * Release key state, free if necessary (if reference count gets to zero).
 * Internal method used when the mutex is already held.
 *
 * @param key_state the key state to release
 */
static void
ks_release_ (struct TEH_KS_StateHandle *key_state)
{
  GNUNET_assert (0 < key_state->refcnt);
  key_state->refcnt--;
  if (0 == key_state->refcnt)
  {
    if (NULL != key_state->denom_keys_array)
    {
      json_decref (key_state->denom_keys_array);
      key_state->denom_keys_array = NULL;
    }
    if (NULL != key_state->payback_array)
    {
      json_decref (key_state->payback_array);
      key_state->payback_array = NULL;
    }
    if (NULL != key_state->sign_keys_array)
    {
      json_decref (key_state->sign_keys_array);
      key_state->sign_keys_array = NULL;
    }
    if (NULL != key_state->denomkey_map)
    {
      GNUNET_CONTAINER_multihashmap_iterate (key_state->denomkey_map,
                                             &free_denom_key,
                                             key_state);
      GNUNET_CONTAINER_multihashmap_destroy (key_state->denomkey_map);
      key_state->denomkey_map = NULL;
    }
    if (NULL != key_state->revoked_map)
    {
      GNUNET_CONTAINER_multihashmap_iterate (key_state->revoked_map,
                                             &free_denom_key,
                                             key_state);
      GNUNET_CONTAINER_multihashmap_destroy (key_state->revoked_map);
      key_state->revoked_map = NULL;
    }
    GNUNET_free_non_null (key_state->keys_json);
    GNUNET_free (key_state);
  }
}


/**
 * Release key state, free if necessary (if reference count gets to zero).
 *
 * @param location name of the function in which the lock is acquired
 * @param key_state the key state to release
 */
void
TEH_KS_release_ (const char *location,
                 struct TEH_KS_StateHandle *key_state)
{
  GNUNET_assert (0 == pthread_mutex_lock (&internal_key_state_mutex));
  ks_release_ (key_state);
  GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
}


/**
 * Acquire the key state of the exchange.  Updates keys if necessary.
 * For every call to #TEH_KS_acquire(), a matching call
 * to #TEH_KS_release() must be made.
 *
 * @param location name of the function in which the lock is acquired
 * @return the key state
 */
struct TEH_KS_StateHandle *
TEH_KS_acquire_ (const char *location)
{
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();
  struct TEH_KS_StateHandle *key_state;
  json_t *keys;
  struct TALER_ExchangeKeySetPS ks;
  struct TALER_ExchangeSignatureP sig;

  GNUNET_assert (0 == pthread_mutex_lock (&internal_key_state_mutex));
  if ( (NULL != internal_key_state) &&
       (internal_key_state->next_reload.abs_value_us <= now.abs_value_us) )
  {
    ks_release_ (internal_key_state);
    internal_key_state = NULL;
  }
  if (NULL == internal_key_state)
  {
    key_state = GNUNET_new (struct TEH_KS_StateHandle);
    key_state->hash_context = GNUNET_CRYPTO_hash_context_start ();
    key_state->min_dk_expire = GNUNET_TIME_UNIT_FOREVER_ABS;

    key_state->denom_keys_array = json_array ();
    GNUNET_assert (NULL != key_state->denom_keys_array);

    key_state->payback_array = json_array ();
    GNUNET_assert (NULL != key_state->payback_array);

    key_state->sign_keys_array = json_array ();
    GNUNET_assert (NULL != key_state->sign_keys_array);

    key_state->auditors_array = json_array ();
    GNUNET_assert (NULL != key_state->auditors_array);

    key_state->denomkey_map = GNUNET_CONTAINER_multihashmap_create (32,
                                                                    GNUNET_NO);
    key_state->revoked_map = GNUNET_CONTAINER_multihashmap_create (4,
                                                                   GNUNET_NO);
    key_state->reload_time = GNUNET_TIME_absolute_get ();
    GNUNET_TIME_round_abs (&key_state->reload_time);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Loading keys from `%s'\n",
                TEH_exchange_directory);
    if (-1 == TALER_EXCHANGEDB_denomination_keys_iterate (TEH_exchange_directory,
                                                          &TEH_master_public_key,
                                                          &reload_keys_denom_iter,
                                                          key_state))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Can't load denomination keys.\n");
      GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
      return NULL;
    }
    TALER_EXCHANGEDB_signing_keys_iterate (TEH_exchange_directory,
                                           &reload_keys_sign_iter,
                                           key_state);
    TALER_EXCHANGEDB_auditor_iterate (cfg,
                                      &reload_auditor_iter,
                                      key_state);

    if (0 != memcmp (&key_state->current_sign_key_issue.issue.master_public_key,
                     &TEH_master_public_key,
                     sizeof (struct TALER_MasterPublicKeyP)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Have no signing key. Bad configuration.\n");
      GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
      return NULL;
    }

    if (0 == GNUNET_CONTAINER_multihashmap_size (key_state->denomkey_map))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Have no denomination keys. Bad configuration.\n");
      GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
      return NULL;
    }

    ks.purpose.size = htonl (sizeof (ks));
    ks.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_KEY_SET);
    ks.list_issue_date = GNUNET_TIME_absolute_hton (key_state->reload_time);
    GNUNET_CRYPTO_hash_context_finish (key_state->hash_context,
                                       &ks.hc);
    key_state->hash_context = NULL;
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CRYPTO_eddsa_sign (&key_state->current_sign_key_issue.signkey_priv.eddsa_priv,
                                             &ks.purpose,
                                             &sig.eddsa_signature));
    key_state->next_reload =
      GNUNET_TIME_absolute_min (GNUNET_TIME_absolute_ntoh (key_state->current_sign_key_issue.issue.expire),
                                key_state->min_dk_expire);
    if (0 == key_state->next_reload.abs_value_us)
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "No valid signing key found!\n");

    keys = json_pack ("{s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o}",
                      "master_public_key",
                      GNUNET_JSON_from_data_auto (&TEH_master_public_key),
                      "signkeys", key_state->sign_keys_array,
                      "denoms", key_state->denom_keys_array,
                      "payback", key_state->payback_array,
                      "auditors", key_state->auditors_array,
                      "list_issue_date", GNUNET_JSON_from_time_abs (key_state->reload_time),
                      "eddsa_pub", GNUNET_JSON_from_data_auto (&key_state->current_sign_key_issue.issue.signkey_pub),
                      "eddsa_sig", GNUNET_JSON_from_data_auto (&sig));
    GNUNET_assert (NULL != keys);
    key_state->auditors_array = NULL;
    key_state->sign_keys_array = NULL;
    key_state->denom_keys_array = NULL;
    key_state->payback_array = NULL;
    key_state->keys_json = json_dumps (keys,
                                       JSON_INDENT (2));
    GNUNET_assert (NULL != key_state->keys_json);
    json_decref (keys);
    internal_key_state = key_state;
  }
  key_state = internal_key_state;
  key_state->refcnt++;
  GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));

  return key_state;
}


/**
 * Look up the issue for a denom public key.
 *
 * @param key_state state to look in
 * @param denom_pub denomination public key
 * @param use purpose for which the key is being located
 * @return the denomination key issue,
 *         or NULL if denom_pub could not be found
 */
struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *
TEH_KS_denomination_key_lookup (const struct TEH_KS_StateHandle *key_state,
                                const struct TALER_DenominationPublicKey *denom_pub,
				enum TEH_KS_DenominationKeyUse use)
{
  struct GNUNET_HashCode hc;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;
  struct GNUNET_TIME_Absolute now;
  const struct GNUNET_CONTAINER_MultiHashMap *map;

  GNUNET_CRYPTO_rsa_public_key_hash (denom_pub->rsa_public_key,
                                     &hc);
  map = (TEH_KS_DKU_PAYBACK == use) ? key_state->revoked_map : key_state->denomkey_map;
  dki = GNUNET_CONTAINER_multihashmap_get (map,
					   &hc);
  if (NULL == dki)
    return NULL;
  now = GNUNET_TIME_absolute_get ();
  if (now.abs_value_us <
      GNUNET_TIME_absolute_ntoh (dki->issue.properties.start).abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		"Not returning DKI for %s, as start time is in the future\n",
		GNUNET_h2s (&hc));
    return NULL;
  }
  now = GNUNET_TIME_absolute_get ();
  switch (use)
  {
  case TEH_KS_DKU_WITHDRAW:
    if (now.abs_value_us >
	GNUNET_TIME_absolute_ntoh (dki->issue.properties.expire_withdraw).abs_value_us)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		  "Not returning DKI for %s, as time to create coins has passed\n",
		  GNUNET_h2s (&hc));
      return NULL;
    }
    break;
  case TEH_KS_DKU_DEPOSIT:
    if (now.abs_value_us >
	GNUNET_TIME_absolute_ntoh (dki->issue.properties.expire_deposit).abs_value_us)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		  "Not returning DKI for %s, as time to spend coin has passed\n",
		  GNUNET_h2s (&hc));
      return NULL;
    }
    break;
  case TEH_KS_DKU_PAYBACK:
    if (now.abs_value_us >
	GNUNET_TIME_absolute_ntoh (dki->issue.properties.expire_deposit).abs_value_us)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		  "Not returning DKI for %s, as time to payback coin has passed\n",
		  GNUNET_h2s (&hc));
      return NULL;
    }
    break;
  }
  return dki;
}


/**
 * Handle a signal, writing relevant signal numbers to the pipe.
 *
 * @param signal_number the signal number
 */
static void
handle_signal (int signal_number)
{
  ssize_t res;
  char c = signal_number;

  res = write (reload_pipe[1],
               &c,
               1);
  if ( (res < 0) &&
       (EINTR != errno) )
  {
    GNUNET_break (0);
    return;
  }
  if (0 == res)
  {
    GNUNET_break (0);
    return;
  }
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sigusr1 ()
{
  handle_signal (SIGUSR1);
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sigint ()
{
  handle_signal (SIGINT);
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sigterm ()
{
  handle_signal (SIGTERM);
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sighup ()
{
  handle_signal (SIGHUP);
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sigchld ()
{
  handle_signal (SIGCHLD);
}


/**
 * Read signals from a pipe in a loop, and reload keys from disk if
 * SIGUSR1 is received, terminate if SIGTERM/SIGINT is received, and
 * restart if SIGHUP is received.
 *
 * @return #GNUNET_SYSERR on errors,
 *         #GNUNET_OK to terminate normally
 *         #GNUNET_NO to restart an update version of the binary
 */
int
TEH_KS_loop (void)
{
  struct GNUNET_SIGNAL_Context *sigusr1;
  struct GNUNET_SIGNAL_Context *sigterm;
  struct GNUNET_SIGNAL_Context *sigint;
  struct GNUNET_SIGNAL_Context *sighup;
  struct GNUNET_SIGNAL_Context *sigchld;
  int ret;

  if (0 != pipe (reload_pipe))
  {
    fprintf (stderr,
             "Failed to create pipe.\n");
    return GNUNET_SYSERR;
  }
  sigusr1 = GNUNET_SIGNAL_handler_install (SIGUSR1,
                                           &handle_sigusr1);
  sigterm = GNUNET_SIGNAL_handler_install (SIGTERM,
                                           &handle_sigterm);
  sigint = GNUNET_SIGNAL_handler_install (SIGINT,
                                          &handle_sigint);
  sighup = GNUNET_SIGNAL_handler_install (SIGHUP,
                                          &handle_sighup);
  sigchld = GNUNET_SIGNAL_handler_install (SIGCHLD,
                                           &handle_sigchld);

  ret = 2;
  while (2 == ret)
  {
    char c;
    ssize_t res;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "(re-)loading keys\n");
    if (NULL != internal_key_state)
    {
      TEH_KS_release (internal_key_state);
      internal_key_state = NULL;
    }
    /* This will re-initialize 'internal_key_state' with
       an initial refcnt of 1 */
    if (NULL == TEH_KS_acquire ())
    {
      ret = GNUNET_SYSERR;
      break;
    }
read_again:
    errno = 0;
    res = read (reload_pipe[0],
                &c,
                1);
    if ((res < 0) && (EINTR != errno))
    {
      GNUNET_break (0);
      ret = GNUNET_SYSERR;
      break;
    }
    if (EINTR == errno)
      goto read_again;
    switch (c)
    {
    case SIGUSR1:
      /* reload internal key state, we do this in the loop */
      break;
    case SIGTERM:
    case SIGINT:
      /* terminate */
      ret = GNUNET_OK;
      break;
    case SIGHUP:
      /* restart updated binary */
      ret = GNUNET_NO;
      break;
#if HAVE_DEVELOPER
    case SIGCHLD:
      /* running in test-mode, test finished, terminate */
      ret = GNUNET_OK;
      break;
#endif
    default:
      /* unexpected character */
      GNUNET_break (0);
      break;
    }
  }
  if (NULL != internal_key_state)
  {
    TEH_KS_release (internal_key_state);
    internal_key_state = NULL;
  }
  GNUNET_SIGNAL_handler_uninstall (sigusr1);
  GNUNET_SIGNAL_handler_uninstall (sigterm);
  GNUNET_SIGNAL_handler_uninstall (sigint);
  GNUNET_SIGNAL_handler_uninstall (sighup);
  GNUNET_SIGNAL_handler_uninstall (sigchld);
  return ret;
}


/**
 * Sign the message in @a purpose with the exchange's signing key.
 *
 * @param purpose the message to sign
 * @param[out] pub set to the current public signing key of the exchange
 * @param[out] sig signature over purpose using current signing key
 */
void
TEH_KS_sign (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
             struct TALER_ExchangePublicKeyP *pub,
             struct TALER_ExchangeSignatureP *sig)

{
  struct TEH_KS_StateHandle *key_state;

  key_state = TEH_KS_acquire ();
  *pub = key_state->current_sign_key_issue.issue.signkey_pub;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&key_state->current_sign_key_issue.signkey_priv.eddsa_priv,
                                           purpose,
                                           &sig->eddsa_signature));
  TEH_KS_release (key_state);
}


/**
 * Produce HTTP "Date:" header.
 *
 * @param at time to write to @a date
 * @param[out] date where to write the header, with
 *        at least 128 bytes available space.
 */
static void
get_date_string (struct GNUNET_TIME_Absolute at,
                 char *date)
{
  static const char *const days[] =
    { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
  static const char *const mons[] =
    { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
    "Nov", "Dec"
  };
  struct tm now;
  time_t t;
#if !defined(HAVE_C11_GMTIME_S) && !defined(HAVE_W32_GMTIME_S) && !defined(HAVE_GMTIME_R)
  struct tm* pNow;
#endif

  date[0] = 0;
  t = (time_t) (at.abs_value_us / 1000LL / 1000LL);
#if defined(HAVE_C11_GMTIME_S)
  if (NULL == gmtime_s (&t, &now))
    return;
#elif defined(HAVE_W32_GMTIME_S)
  if (0 != gmtime_s (&now, &t))
    return;
#elif defined(HAVE_GMTIME_R)
  if (NULL == gmtime_r(&t, &now))
    return;
#else
  pNow = gmtime(&t);
  if (NULL == pNow)
    return;
  now = *pNow;
#endif
  sprintf (date,
           "%3s, %02u %3s %04u %02u:%02u:%02u GMT",
           days[now.tm_wday % 7],
           (unsigned int) now.tm_mday,
           mons[now.tm_mon % 12],
           (unsigned int) (1900 + now.tm_year),
           (unsigned int) now.tm_hour,
           (unsigned int) now.tm_min,
           (unsigned int) now.tm_sec);
}


/**
 * Function to call to handle the request by sending
 * back static data from the @a rh.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TEH_KS_handler_keys (struct TEH_RequestHandler *rh,
                     struct MHD_Connection *connection,
                     void **connection_cls,
                     const char *upload_data,
                     size_t *upload_data_size)
{
  struct TEH_KS_StateHandle *key_state;
  struct MHD_Response *response;
  int ret;
  char dat[128];

  key_state = TEH_KS_acquire ();
  response = MHD_create_response_from_buffer (strlen (key_state->keys_json),
                                              key_state->keys_json,
                                              MHD_RESPMEM_MUST_COPY);
  TEH_KS_release (key_state);
  if (NULL == response)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  TEH_RESPONSE_add_global_headers (response);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_CONTENT_TYPE,
                                         rh->mime_type));
  get_date_string (key_state->reload_time,
                   dat);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_LAST_MODIFIED,
                                         dat));
  get_date_string (key_state->next_reload,
                   dat);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_EXPIRES,
                                         dat));
  ret = MHD_queue_response (connection,
                            rh->response_code,
                            response);
  MHD_destroy_response (response);
  return ret;
}


/* end of taler-exchange-httpd_keystate.c */
