/*
  This file is part of TALER
  Copyright (C) 2014--2019 Taler Systems SA

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
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_plugin.h"


/**
 * Taler protocol version in the format CURRENT:REVISION:AGE
 * as used by GNU libtool.  See
 * https://www.gnu.org/software/libtool/manual/html_node/Libtool-versioning.html
 *
 * Please be very careful when updating and follow
 * https://www.gnu.org/software/libtool/manual/html_node/Updating-version-info.html#Updating-version-info
 * precisely.  Note that this version has NOTHING to do with the
 * release version, and the format is NOT the same that semantic
 * versioning uses either.
 *
 * When changing this version, you likely want to also update
 * #TALER_PROTOCOL_CURRENT and #TALER_PROTOCOL_AGE in
 * exchange_api_handle.c!
 */
#define TALER_PROTOCOL_VERSION "6:0:0"


/**
 * Signatures of an auditor over a denomination key of this exchange.
 */
struct AuditorSignature
{
  /**
   * We store the signatures in a DLL.
   */
  struct AuditorSignature *prev;

  /**
   * We store the signatures in a DLL.
   */
  struct AuditorSignature *next;

  /**
   * A signature from the auditor.
   */
  struct TALER_AuditorSignatureP asig;

  /**
   * Public key of the auditor.
   */
  struct TALER_AuditorPublicKeyP apub;

  /**
   * URL of the auditor. Allocated at the end of this struct.
   */
  const char *auditor_url;

};


/**
 * Entry in sorted array of denomination keys.  Sorted by starting
 * "start" time (validity period) of the `struct
 * TALER_DenominationKeyValidityPS`.
 */
struct DenominationKeyEntry
{

  /**
   * Reference to the public key.
   * (Must also be in the `denomkey_map`).
   */
  const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;

  /**
   * Head of DLL of signatures for this @e dki.
   */
  struct AuditorSignature *as_head;

  /**
   * Tail of DLL of signatures for this @e dki.
   */
  struct AuditorSignature *as_tail;

  /**
   * Hash of the public denomination key.
   */
  struct GNUNET_HashCode denom_key_hash;

#ifdef OPTIMIZE_5777_AUDITOR_BY_COUNT_REALTIME_DETECTION

  /**
   * Mutex that must be held before threads may access or update
   * @e known_coin_counter or @e known_coin_counter_db.
   */
  pthread_mutex_t known_coin_counter_mutex;

  /**
   * Mutex that must be held before threads may access or update
   * @e issued_coin_counter or @e issued_coin_counter_db.
   */
  pthread_mutex_t issued_coin_counter_mutex;

  /**
   * How many coins of this denomination have been redeemed so far (according
   * to only this process)?
   */
  uint64_t known_coin_counter;

  /**
   * How many coins of this denomination have been redeemed so far (based on
   * the last time we synchronized the value with our database).
   */
  uint64_t known_coin_counter_db;

  /**
   * How many coins of this denomination have been issued so far (according
   * to only this process)?
   */
  uint64_t issued_coin_counter;

  /**
   * How many coins of this denomination have been issued so far (based on the
   * last time we synchronized the value with our database)?
   */
  uint64_t issued_coin_counter_db;

#endif

};


/**
 * Entry in (sorted) array with possible pre-build responses for /keys.
 * We keep pre-build responses for the various (valid) cherry-picking
 * values around.
 */
struct KeysResponseData
{

  /**
   * Response to return if the client supports (gzip) compression.
   */
  struct MHD_Response *response_compressed;

  /**
   * Response to return if the client does not support compression.
   */
  struct MHD_Response *response_uncompressed;

  /**
   * Cherry-picking timestamp the client must have set for this
   * response to be valid.  0 if this is the "full" response.
   * The client's request must include this date or a higher one
   * for this response to be applicable.
   */
  struct GNUNET_TIME_Absolute cherry_pick_date;

};


/**
 * State we keep around while building an individual entry in the
 * `struct KeysResponseData` array, i.e. the global state for ONE of
 * the responses.
 */
struct ResponseBuilderContext
{

  /**
   * Hash context we used to combine the hashes of all denomination
   * keys into one big hash for signing.
   */
  struct GNUNET_HashContext *hash_context;

  /**
   * JSON array with denomination key information.
   */
  json_t *denom_keys_array;

  /**
   * JSON array with auditor information.
   */
  json_t *auditors_array;

  /**
   * Keys after what issue date do we care about?
   */
  struct GNUNET_TIME_Absolute last_issue_date;

  /**
   * Flag set to #GNUNET_SYSERR on internal errors
   */
  int error;

};


/**
 * State we keep around while building the `struct KeysResponseData`
 * array, i.e. the global state for all of the responses.
 */
struct ResponseFactoryContext
{

  /**
   * JSON array with revoked denomination keys.  Every response
   * always returns the full list (cherry picking does not apply
   * for key revocations, as we cannot sort those by issue date).
   */
  json_t *recoup_array;

  /**
   * JSON array with signing keys.  Every response includes the full
   * list, as it should be quite short anyway, and for simplicity the
   * client only communicates the one time stamp of the last
   * denomination key it knows when cherry picking.
   */
  json_t *sign_keys_array;

  /**
   * Sorted array of denomination keys.  Length is @e denomkey_array_length.
   * Entries are sorted by the validity period's starting time.
   */
  struct DenominationKeyEntry *denomkey_array;

  /**
   * The main key state we are building everything for.
   */
  struct TEH_KS_StateHandle *key_state;

  /**
   * Length of the @e denomkey_array.
   */
  unsigned int denomkey_array_length;

  /**
   * Time stamp used as "now".
   */
  struct GNUNET_TIME_Absolute now;
};


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
   * Sorted array of responses to /keys (sorted by cherry-picking date) of
   * length @e krd_array_length;
   */
  struct KeysResponseData *krd_array;

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
   * Reference count.  The struct is released when the RC hits zero.  Once
   * this object is aliased, the reference counter must only be changed while
   * holding the #internal_key_state_mutex.
   */
  unsigned int refcnt;

  /**
   * Length of the @e krd_array.
   */
  unsigned int krd_array_length;
};


/**
 * Exchange key state.  This is the long-term, read-only internal global state,
 * which the various threads "lock" to use in read-only ways.  We eventually
 * create a completely new object "on the side" and then start to return
 * the new read-only object to threads that ask. Once none of the threads
 * use the previous object (RC drops to zero), we discard it.
 *
 * Thus, this instance should never be used directly, instead reserve
 * access via #TEH_KS_acquire() and release it via #TEH_KS_release().
 *
 * As long as MHD threads are running, access to this field requires
 * locking the #internal_key_state_mutex.
 */
static struct TEH_KS_StateHandle *internal_key_state;

/**
 * Mutex protecting access to #internal_key_state.
 */
static pthread_mutex_t internal_key_state_mutex = PTHREAD_MUTEX_INITIALIZER;


/* ************************** Clean up logic *********************** */


/**
 * Release memory used by @a rfc.
 *
 * @param rfc factory to release (but do not #GNUNET_free() rfc itself!)
 */
static void
destroy_response_factory (struct ResponseFactoryContext *rfc)
{
  if (NULL != rfc->recoup_array)
  {
    json_decref (rfc->recoup_array);
    rfc->recoup_array = NULL;
  }
  if (NULL != rfc->sign_keys_array)
  {
    json_decref (rfc->sign_keys_array);
    rfc->sign_keys_array = NULL;
  }
  for (unsigned int i = 0; i<rfc->denomkey_array_length; i++)
  {
    struct DenominationKeyEntry *dke = &rfc->denomkey_array[i];
    struct AuditorSignature *as;

    while (NULL != (as = dke->as_head))
    {
      GNUNET_CONTAINER_DLL_remove (dke->as_head,
                                   dke->as_tail,
                                   as);
      GNUNET_free (as);
    }
  }
  GNUNET_array_grow (rfc->denomkey_array,
                     rfc->denomkey_array_length,
                     0);
}


/**
 * Release memory used by @a rbc.
 */
static void
destroy_response_builder (struct ResponseBuilderContext *rbc)
{
  if (NULL != rbc->denom_keys_array)
  {
    json_decref (rbc->denom_keys_array);
    rbc->denom_keys_array = NULL;
  }
  if (NULL != rbc->auditors_array)
  {
    json_decref (rbc->auditors_array);
    rbc->auditors_array = NULL;
  }
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

  (void) cls;
  (void) key;
  if (NULL != dki->denom_priv.rsa_private_key)
    GNUNET_CRYPTO_rsa_private_key_free (dki->denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_free (dki->denom_pub.rsa_public_key);
  GNUNET_free (dki);
  return GNUNET_OK;
}


/**
 * Internal function to free key state. Reference count must be at zero.
 *
 * @param key_state the key state to free
 */
static void
ks_free (struct TEH_KS_StateHandle *key_state)
{
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "KS release called (%p)\n",
              key_state);
  GNUNET_assert (0 == key_state->refcnt);
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
  for (unsigned int i = 0; i<key_state->krd_array_length; i++)
  {
    struct KeysResponseData *krd = &key_state->krd_array[i];

    if (NULL != krd->response_compressed)
      MHD_destroy_response (krd->response_compressed);
    if (NULL != krd->response_uncompressed)
      MHD_destroy_response (krd->response_uncompressed);
  }
  GNUNET_array_grow (key_state->krd_array,
                     key_state->krd_array_length,
                     0);
  GNUNET_free (key_state);
}


/* ************************* Signal logic ************************** */

/**
 * Pipe used for signaling reloading of our key state.
 */
static int reload_pipe[2];


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


/* ************************** State builder ************************ */


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
                         const struct
                         TALER_EXCHANGEDB_DenominationKeyInformationP *dki)
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
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (
                                            dki->properties.start)),
               "stamp_expire_withdraw",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (
                                            dki->properties.expire_withdraw)),
               "stamp_expire_deposit",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (
                                            dki->properties.expire_deposit)),
               "stamp_expire_legal",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (
                                            dki->properties.expire_legal)),
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
 * Store a copy of @a dki in @a map.
 *
 * @param map hash map to store @a dki in
 * @param dki information to store in @a map
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if such an entry already exists
 */
static int
store_in_map (struct GNUNET_CONTAINER_MultiHashMap *map,
              const struct
              TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki)
{
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *d2;
  int res;

  {
    const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dkip;
    struct TALER_DenominationKeyValidityPS denom_key_issue;

    dkip = &dki->issue;
    denom_key_issue = dkip->properties;
    denom_key_issue.purpose.purpose
      = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
    denom_key_issue.purpose.size
      = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
    denom_key_issue.master = TEH_master_public_key;
    if (GNUNET_SYSERR ==
        GNUNET_CRYPTO_eddsa_verify (
          TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY,
          &denom_key_issue.purpose,
          &dkip->signature.eddsa_signature,
          &TEH_master_public_key.eddsa_pub))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid signature on denomination key `%s'\n",
                  GNUNET_h2s (&dkip->properties.denom_hash));
      return GNUNET_SYSERR;
    }
  }

  d2 = GNUNET_new (struct TALER_EXCHANGEDB_DenominationKeyIssueInformation);
  d2->issue = dki->issue;
  if (NULL != dki->denom_priv.rsa_private_key)
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
    if (NULL != d2->denom_priv.rsa_private_key)
      GNUNET_CRYPTO_rsa_private_key_free (d2->denom_priv.rsa_private_key);
    GNUNET_CRYPTO_rsa_public_key_free (d2->denom_pub.rsa_public_key);
    GNUNET_free (d2);
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


/**
 * Closure for #add_revocations_transaction().
 */
struct AddRevocationContext
{
  /**
   * Denomination key that is revoked.
   */
  const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;

  /**
   * Signature affirming the revocation.
   */
  const struct TALER_MasterSignatureP *revocation_master_sig;
};


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
                                           "exchange",
                                           "LOOKAHEAD_PROVIDE",
                                           &rel))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "LOOKAHEAD_PROVIDE",
                               "time value required");
    GNUNET_assert (0);
  }
  return rel;
}


/**
 * Execute transaction to add revocations.
 *
 * @param cls closure with the `struct AddRevocationContext *`
 * @param connection NULL
 * @param session database session to use
 * @param[out] mhd_ret not used
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
add_revocations_transaction (void *cls,
                             struct MHD_Connection *connection,
                             struct TALER_EXCHANGEDB_Session *session,
                             int *mhd_ret)
{
  struct AddRevocationContext *arc = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_MasterSignatureP master_sig;
  uint64_t rowid;

  (void) connection;
  (void) mhd_ret;
  qs = TEH_plugin->get_denomination_revocation (TEH_plugin->cls,
                                                session,
                                                &arc->dki->issue.properties.
                                                denom_hash,
                                                &master_sig,
                                                &rowid);
  if (0 > qs)
    return qs; /* failure */
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    return qs; /* already exists == success */
  return TEH_plugin->insert_denomination_revocation (TEH_plugin->cls,
                                                     session,
                                                     &arc->dki->issue.properties
                                                     .denom_hash,
                                                     arc->revocation_master_sig);
}


/**
 * Execute transaction to add a denomination to the DB.
 *
 * @param cls closure with the `const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *`
 * @param connection NULL
 * @param session database session to use
 * @param[out] mhd_ret not used
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
add_denomination_transaction (void *cls,
                              struct MHD_Connection *connection,
                              struct TALER_EXCHANGEDB_Session *session,
                              int *mhd_ret)
{
  const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP issue_exists;

  (void) connection;
  (void) mhd_ret;
  qs = TEH_plugin->get_denomination_info (TEH_plugin->cls,
                                          session,
                                          &dki->issue.properties.denom_hash,
                                          &issue_exists);
  if (0 > qs)
    return qs;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    return qs;
  return TEH_plugin->insert_denomination_info (TEH_plugin->cls,
                                               session,
                                               &dki->denom_pub,
                                               &dki->issue);
}


/**
 * Iterator for (re)loading/initializing denomination keys.
 *
 * @param cls closure with a `struct ResponseFactoryContext *`
 * @param dki the denomination key issue
 * @param alias coin alias
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
reload_keys_denom_iter (void *cls,
                        const char *alias,
                        const struct
                        TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki)
{
  struct ResponseFactoryContext *rfc = cls;
  struct TEH_KS_StateHandle *key_state = rfc->key_state;
  struct GNUNET_TIME_Absolute start;
  struct GNUNET_TIME_Absolute horizon;
  struct GNUNET_TIME_Absolute expire_deposit;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Loading denomination key `%s' (%s)\n",
              alias,
              GNUNET_h2s (&dki->issue.properties.denom_hash));
  expire_deposit = GNUNET_TIME_absolute_ntoh (
    dki->issue.properties.expire_deposit);
  if (expire_deposit.abs_value_us < rfc->now.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Skipping expired denomination key `%s'\n",
                alias);
    return GNUNET_OK;
  }
  if (0 != GNUNET_memcmp (&dki->issue.properties.master,
                          &TEH_master_public_key))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Master key in denomination key file `%s' does not match! Skipping it.\n",
                alias);
    return GNUNET_OK;
  }

  horizon = GNUNET_TIME_absolute_add (rfc->now,
                                      TALER_EXCHANGE_conf_duration_provide ());
  start = GNUNET_TIME_absolute_ntoh (dki->issue.properties.start);
  if (start.abs_value_us > horizon.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Skipping future denomination key `%s' (%s), validity starts at %s\n",
                alias,
                GNUNET_h2s (&dki->issue.properties.denom_hash),
                GNUNET_STRINGS_absolute_time_to_string (start));
    return GNUNET_OK;
  }

  if (GNUNET_OK !=
      TEH_DB_run_transaction (NULL,
                              "add denomination key",
                              NULL,
                              &add_denomination_transaction,
                              (void *) dki))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not persist denomination key %s in DB. Committing suicide via SIGTERM.\n",
                GNUNET_h2s (&dki->issue.properties.denom_hash));
    handle_signal (SIGTERM);
    return GNUNET_SYSERR;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Adding denomination key `%s' (%s) to active set\n",
              alias,
              GNUNET_h2s (&dki->issue.properties.denom_hash));
  if (GNUNET_NO /* entry already exists */ ==
      store_in_map (key_state->denomkey_map,
                    dki))
    return GNUNET_OK; /* do not update expiration if entry exists */
  key_state->min_dk_expire = GNUNET_TIME_absolute_min (key_state->min_dk_expire,
                                                       expire_deposit);
  return GNUNET_OK;
}


/**
 * Iterator for revocation of denomination keys.
 *
 * @param cls closure with a `struct ResponseFactoryContext *`
 * @param denom_hash hash of revoked denomination public key
 * @param revocation_master_sig signature showing @a denom_hash was revoked
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
revocations_iter (void *cls,
                  const struct GNUNET_HashCode *denom_hash,
                  const struct TALER_MasterSignatureP *revocation_master_sig)
{
  struct ResponseFactoryContext *rfc = cls;
  struct TEH_KS_StateHandle *key_state = rfc->key_state;
  struct AddRevocationContext arc;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;

  dki = GNUNET_CONTAINER_multihashmap_get (key_state->denomkey_map,
                                           denom_hash);
  if (NULL == dki)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Revoked denomination `%s' unknown (or duplicate file), ignoring revocation\n",
                GNUNET_h2s (denom_hash));
    return GNUNET_OK;

  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Adding denomination key `%s' to revocation set\n",
              GNUNET_h2s (denom_hash));
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (key_state->denomkey_map,
                                                       denom_hash,
                                                       dki));
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_put (key_state->revoked_map,
                                                    &dki->issue.properties.
                                                    denom_hash,
                                                    dki,
                                                    GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  /* Try to insert revocation into DB */
  arc.dki = dki;
  arc.revocation_master_sig = revocation_master_sig;
  if (GNUNET_OK !=
      TEH_DB_run_transaction (NULL,
                              "add denomination key revocation",
                              NULL,
                              &add_revocations_transaction,
                              &arc))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to add revocation to database. This is fatal. Committing suicide via SIGTERM.\n");
    handle_signal (SIGTERM);
    return GNUNET_SYSERR;
  }
  GNUNET_assert (0 ==
                 json_array_append_new (rfc->recoup_array,
                                        GNUNET_JSON_from_data_auto (
                                          denom_hash)));
  return GNUNET_OK;
}


/**
 * Convert the public part of a sign key issue to a JSON object.
 *
 * @param ski the sign key issue
 * @param ski_sig signature over @a ski
 * @return a JSON object describing the sign key issue (public part)
 */
static json_t *
sign_key_issue_to_json (const struct TALER_ExchangeSigningKeyValidityPS *ski,
                        const struct TALER_MasterSignatureP *ski_sig)
{
  return
    json_pack ("{s:o, s:o, s:o, s:o, s:o}",
               "stamp_start",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (
                                            ski->start)),
               "stamp_expire",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (
                                            ski->expire)),
               "stamp_end",
               GNUNET_JSON_from_time_abs (GNUNET_TIME_absolute_ntoh (ski->end)),
               "master_sig",
               GNUNET_JSON_from_data_auto (ski_sig),
               "key",
               GNUNET_JSON_from_data_auto (&ski->signkey_pub));
}


/**
 * Iterator for sign keys.  Adds current and near-future signing keys
 * to the `sign_keys_array` and stores the current one in the
 * `key_state`.
 *
 * @param cls closure with the `struct ResponseFactoryContext *`
 * @param filename name of the file the key came from
 * @param ski the sign key issue
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
reload_keys_sign_iter (void *cls,
                       const char *filename,
                       const struct
                       TALER_EXCHANGEDB_PrivateSigningKeyInformationP *ski)
{
  struct ResponseFactoryContext *rfc = cls;
  struct TEH_KS_StateHandle *key_state = rfc->key_state;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute horizon;

  horizon = GNUNET_TIME_relative_to_absolute (
    TALER_EXCHANGE_conf_duration_provide ());
  if (GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us >
      horizon.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Skipping future signing key `%s'\n",
                filename);
    return GNUNET_OK;
  }
  now = GNUNET_TIME_absolute_get ();
  if (GNUNET_TIME_absolute_ntoh (ski->issue.expire).abs_value_us <
      now.abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Skipping expired signing key `%s'\n",
                filename);
    return GNUNET_OK;
  }

  if (0 != GNUNET_memcmp (&ski->issue.master_public_key,
                          &TEH_master_public_key))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Master key in signing key file `%s' does not match! Skipping it.\n",
                filename);
    return GNUNET_OK;
  }

  /* The signkey is valid at this time, check if it's more recent than
     what we have so far! */
  if ( (GNUNET_TIME_absolute_ntoh (
          key_state->current_sign_key_issue.issue.start).abs_value_us <
        GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us) &&
       (GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us <
        now.abs_value_us) )
  {
    /* We use the most recent one, if it is valid now (not just in the near future) */
    key_state->current_sign_key_issue = *ski;
  }
  GNUNET_assert (0 ==
                 json_array_append_new (rfc->sign_keys_array,
                                        sign_key_issue_to_json (&ski->issue,
                                                                &ski->master_sig)));

  return GNUNET_OK;
}


/**
 * @brief Iterator called with auditor information.
 * Check that the @a mpub actually matches this exchange, and then
 * add the auditor information to our /keys response (if it is
 * (still) applicable).
 *
 * @param cls closure with the `struct ResponseFactoryContext *`
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
  struct ResponseFactoryContext *rfc = cls;
  struct TEH_KS_StateHandle *key_state = rfc->key_state;

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
  for (unsigned int i = 0; i<dki_len; i++)
  {
    int matched;

    if (GNUNET_YES !=
        GNUNET_CONTAINER_multihashmap_contains (key_state->denomkey_map,
                                                &dki[i].denom_hash))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Found auditor signature for DK `%s', but key is not in active map\n",
                  GNUNET_h2s (&dki[i].denom_hash));
      continue;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Found auditor signature for DK `%s'\n",
                GNUNET_h2s (&dki[i].denom_hash));
    /* Note: the array is sorted, we could theoretically
       speed this up using a binary search. */
    matched = GNUNET_NO;
    for (unsigned int j = 0; j<rfc->denomkey_array_length; j++)
    {
      struct DenominationKeyEntry *dke = &rfc->denomkey_array[j];
      struct AuditorSignature *as;

      if (0 !=
          memcmp (&dki[i].denom_hash,
                  &dke->dki->issue.properties.denom_hash,
                  sizeof (struct GNUNET_HashCode)))
        continue;
      if (0 !=
          memcmp (&dki[i],
                  &dke->dki->issue.properties,
                  sizeof (struct TALER_DenominationKeyValidityPS)))
      {
        /* if the hash is the same, the properties should also match! */
        GNUNET_break (0);
        continue;
      }
      as = GNUNET_malloc (sizeof (struct AuditorSignature)
                          + strlen (auditor_url) + 1);
      as->asig = asigs[i];
      as->apub = *apub;
      as->auditor_url = (const char *) &as[1];
      memcpy (&as[1],
              auditor_url,
              strlen (auditor_url) + 1);
      GNUNET_CONTAINER_DLL_insert (dke->as_head,
                                   dke->as_tail,
                                   as);
      matched = GNUNET_YES;
      break;
    }
    if (GNUNET_NO == matched)
    {
      GNUNET_break (0);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "DK `%s' is in active map, but not in array!?\n",
                  GNUNET_h2s (&dki[i].denom_hash));
    }
  }
  return GNUNET_OK;
}


/**
 * Initialize the `denomkey_array`.  We are called once per
 * array index, which is tracked in `denomkey_array_length` (the
 * array will be of sufficient size).  Set the pointer to the
 * denomination key and increment the `denomkey_array_length`.
 *
 * @param cls a `struct ResponseFactoryContext`
 * @param denom_hash hash of a denomination key
 * @param value a `struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *`
 * @return #GNUNET_OK
 */
static int
initialize_denomkey_array (void *cls,
                           const struct GNUNET_HashCode *denom_hash,
                           void *value)
{
  struct ResponseFactoryContext *rfc = cls;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki = value;

  rfc->denomkey_array[rfc->denomkey_array_length].denom_key_hash = *denom_hash;
  rfc->denomkey_array[rfc->denomkey_array_length++].dki = dki;
  return GNUNET_OK;
}


/**
 * Comparator used to sort the `struct DenominationKeyEntry` array
 * by the validity period's starting time of the keys.
 *
 * @param k1 a `struct DenominationKeyEntry *`
 * @param k2 a `struct DenominationKeyEntry *`
 * @return -1 if k1 starts before k2,
 *          1 if k2 starts before k1,
 *          0 if they start at the same time
 */
static int
denomkey_array_sort_comparator (const void *k1,
                                const void *k2)
{
  const struct DenominationKeyEntry *dke1 = k1;
  const struct DenominationKeyEntry *dke2 = k2;
  struct GNUNET_TIME_Absolute d1
    = GNUNET_TIME_absolute_ntoh (dke1->dki->issue.properties.start);
  struct GNUNET_TIME_Absolute d2
    = GNUNET_TIME_absolute_ntoh (dke2->dki->issue.properties.start);

  if (d1.abs_value_us < d2.abs_value_us)
    return -1;
  if (d1.abs_value_us > d2.abs_value_us)
    return 1;
  return 0;
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
    "Nov", "Dec"};
  struct tm now;
  time_t t;
#if ! defined(HAVE_C11_GMTIME_S) && ! defined(HAVE_W32_GMTIME_S) && \
  ! defined(HAVE_GMTIME_R)
  struct tm*pNow;
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
  if (NULL == gmtime_r (&t, &now))
    return;
#else
  pNow = gmtime (&t);
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
 * Add the headers we want to set for every /keys response.
 *
 * @param key_state the key state to use
 * @param[in,out] response the response to modify
 * @return #GNUNET_OK on success
 */
static int
setup_general_response_headers (const struct TEH_KS_StateHandle *key_state,
                                struct MHD_Response *response)
{
  char dat[128];

  TALER_MHD_add_global_headers (response);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_CONTENT_TYPE,
                                         "application/json"));
  get_date_string (key_state->reload_time,
                   dat);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_LAST_MODIFIED,
                                         dat));
  if (0 != key_state->next_reload.abs_value_us)
  {
    struct GNUNET_TIME_Absolute m;

    m = GNUNET_TIME_relative_to_absolute (TEH_max_keys_caching);
    m = GNUNET_TIME_absolute_min (m,
                                  key_state->next_reload);
    get_date_string (m,
                     dat);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Setting /keys 'Expires' header to '%s'\n",
                dat);
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (response,
                                           MHD_HTTP_HEADER_EXPIRES,
                                           dat));
  }
  return GNUNET_OK;
}


/**
 * Information about an auditor to be added.
 */
struct AuditorEntry
{
  /**
   * URL of the auditor (allocated still as part of a
   * `struct AuditorSignature`, do not free!).
   */
  const char *auditor_url;

  /**
   * Public key of the auditor (allocated still as part of a
   * `struct AuditorSignature`, do not free!).
   */
  const struct TALER_AuditorPublicKeyP *apub;

  /**
   * Array of denomination keys and auditor signatures.
   */
  json_t *ar;

};


/**
 * Convert auditor entries from the hash map to entries
 * in the auditor array, free the auditor entry as well.
 *
 * @param cls a `struct ResponseBuilderContext *`
 * @param key unused
 * @param value a `struct AuditorEntry` to add to the `auditors_array`
 * @return #GNUNET_OK (to continue to iterate)
 */
static int
add_auditor_entry (void *cls,
                   const struct GNUNET_HashCode *key,
                   void *value)
{
  struct ResponseBuilderContext *rbc = cls;
  struct AuditorEntry *ae = value;
  json_t *ao;

  (void) key;
  ao = json_pack ("{s:o, s:s, s:o}",
                  "denomination_keys", ae->ar,
                  "auditor_url", ae->auditor_url,
                  "auditor_pub", GNUNET_JSON_from_data_auto (ae->apub));
  GNUNET_assert (NULL != ao);
  GNUNET_assert (0 ==
                 json_array_append_new (rbc->auditors_array,
                                        ao));
  GNUNET_free (ae);
  return GNUNET_OK;
}


/**
 * Initialize @a krd for the given @a cherry_pick_date using
 * the key data in @a rfc.  This function actually builds the
 * respective JSON replies (compressed and uncompressed).
 *
 * @param rfc factory with key material
 * @param[out] krd response object to initialize
 * @param denom_off offset in the @a rfc's `denomkey_array` at which
 *        keys beyond the @a cherry_pick_date are stored
 * @param cherry_pick_date cut-off date to use
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
build_keys_response (const struct ResponseFactoryContext *rfc,
                     struct KeysResponseData *krd,
                     unsigned int denom_off,
                     struct GNUNET_TIME_Absolute cherry_pick_date)
{
  struct ResponseBuilderContext rbc;
  json_t *keys;
  struct TALER_ExchangeKeySetPS ks;
  struct TALER_ExchangeSignatureP sig;
  char *keys_json;
  struct GNUNET_TIME_Relative reserve_closing_delay;
  void *keys_jsonz;
  size_t keys_jsonz_size;
  int comp;

  krd->cherry_pick_date = cherry_pick_date;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Creating /keys for cherry pick date %s\n",
              GNUNET_STRINGS_absolute_time_to_string (cherry_pick_date));

  /* Initialize `rbc` */
  memset (&rbc,
          0,
          sizeof (rbc));
  rbc.denom_keys_array = json_array ();
  if (NULL == rbc.denom_keys_array)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  rbc.auditors_array = json_array ();
  if (NULL == rbc.auditors_array)
  {
    destroy_response_builder (&rbc);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  rbc.hash_context = GNUNET_CRYPTO_hash_context_start ();

  /* Go over relevant denomination keys. */
  {
    struct GNUNET_CONTAINER_MultiHashMap *auditors;

    auditors = GNUNET_CONTAINER_multihashmap_create (4,
                                                     GNUNET_NO);
    for (unsigned int i = denom_off; i<rfc->denomkey_array_length; i++)
    {
      /* Add denomination key to the response */
      const struct DenominationKeyEntry *dke
        = &rfc->denomkey_array[i];
      const struct GNUNET_HashCode *denom_key_hash
        = &dke->denom_key_hash;

      GNUNET_CRYPTO_hash_context_read (rbc.hash_context,
                                       denom_key_hash,
                                       sizeof (struct GNUNET_HashCode));
      if (0 !=
          json_array_append_new (rbc.denom_keys_array,
                                 denom_key_issue_to_json (&dke->dki->denom_pub,
                                                          &dke->dki->issue)))
      {
        GNUNET_break (0);
        destroy_response_builder (&rbc);
        return GNUNET_SYSERR;
      }

      /* Add auditor data */
      for (const struct AuditorSignature *as = dke->as_head;
           NULL != as;
           as = as->next)
      {
        struct GNUNET_HashCode ahash;
        struct AuditorEntry *ae;

        GNUNET_CRYPTO_hash (&as->apub,
                            sizeof (as->apub),
                            &ahash);
        ae = GNUNET_CONTAINER_multihashmap_get (auditors,
                                                &ahash);
        if (NULL == ae)
        {
          ae = GNUNET_new (struct AuditorEntry);
          ae->auditor_url = as->auditor_url;
          ae->ar = json_array ();
          ae->apub = &as->apub;
          GNUNET_assert (GNUNET_YES ==
                         GNUNET_CONTAINER_multihashmap_put (auditors,
                                                            &ahash,
                                                            ae,
                                                            GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
        }
        GNUNET_assert (0 ==
                       json_array_append_new (ae->ar,
                                              json_pack ("{s:o, s:o}",
                                                         "denom_pub_h",
                                                         GNUNET_JSON_from_data_auto (
                                                           denom_key_hash),
                                                         "auditor_sig",
                                                         GNUNET_JSON_from_data_auto (
                                                           &as->asig))));
      }
    }

    GNUNET_CONTAINER_multihashmap_iterate (auditors,
                                           &add_auditor_entry,
                                           &rbc);
    GNUNET_CONTAINER_multihashmap_destroy (auditors);
  }

  /* Sign hash over denomination keys */
  ks.purpose.size = htonl (sizeof (ks));
  ks.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_KEY_SET);
  ks.list_issue_date = GNUNET_TIME_absolute_hton (rfc->key_state->reload_time);
  GNUNET_CRYPTO_hash_context_finish (rbc.hash_context,
                                     &ks.hc);
  rbc.hash_context = NULL;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (
                   &rfc->key_state->current_sign_key_issue.signkey_priv.
                   eddsa_priv,
                   &ks.purpose,
                   &sig.eddsa_signature));
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchangedb",
                                           "IDLE_RESERVE_EXPIRATION_TIME",
                                           &reserve_closing_delay))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "IDLE_RESERVE_EXPIRATION_TIME");
    /* use default */
    reserve_closing_delay = GNUNET_TIME_relative_multiply (
      GNUNET_TIME_UNIT_WEEKS,
      4);
  }
  /* Build /keys response */
  keys = json_pack ("{s:s, s:o, s:o, s:O, s:O,"
                    " s:o, s:o, s:o, s:o, s:o}",
                    /* 1-5 */
                    "version", TALER_PROTOCOL_VERSION,
                    "master_public_key", GNUNET_JSON_from_data_auto (
                      &TEH_master_public_key),
                    "reserve_closing_delay", GNUNET_JSON_from_time_rel (
                      reserve_closing_delay),
                    "signkeys", rfc->sign_keys_array,
                    "recoup", rfc->recoup_array,
                    /* 6-10 */
                    "denoms", rbc.denom_keys_array,
                    "auditors", rbc.auditors_array,
                    "list_issue_date", GNUNET_JSON_from_time_abs (
                      rfc->key_state->reload_time),
                    "eddsa_pub", GNUNET_JSON_from_data_auto (
                      &rfc->key_state->current_sign_key_issue.issue.signkey_pub),
                    "eddsa_sig", GNUNET_JSON_from_data_auto (&sig));
  if (NULL == keys)
  {
    destroy_response_builder (&rbc);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  rbc.denom_keys_array = NULL;
  rbc.auditors_array = NULL;
  destroy_response_builder (&rbc);

  /* Convert /keys response to UTF8-String */
  keys_json = json_dumps (keys,
                          JSON_INDENT (2));
  json_decref (keys);
  if (NULL == keys_json)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* Keep copy for later compression... */
  keys_jsonz = GNUNET_strdup (keys_json);
  keys_jsonz_size = strlen (keys_json);

  /* Create uncompressed response */
  krd->response_uncompressed
    = MHD_create_response_from_buffer (keys_jsonz_size,
                                       keys_json,
                                       MHD_RESPMEM_MUST_FREE);
  if (NULL == krd->response_uncompressed)
  {
    GNUNET_break (0);
    GNUNET_free (keys_json);
    GNUNET_free (keys_jsonz);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      setup_general_response_headers (rfc->key_state,
                                      krd->response_uncompressed))
  {
    GNUNET_break (0);
    GNUNET_free (keys_jsonz);
    return GNUNET_SYSERR;
  }

  /* Also compute compressed version of /keys response */
  comp = TALER_MHD_body_compress (&keys_jsonz,
                                  &keys_jsonz_size);
  krd->response_compressed
    = MHD_create_response_from_buffer (keys_jsonz_size,
                                       keys_jsonz,
                                       MHD_RESPMEM_MUST_FREE);
  if (NULL == krd->response_compressed)
  {
    GNUNET_break (0);
    GNUNET_free (keys_jsonz);
    return GNUNET_SYSERR;
  }
  /* If the response is actually compressed, set the
     respective header. */
  if ( (MHD_YES == comp) &&
       (MHD_YES !=
        MHD_add_response_header (krd->response_compressed,
                                 MHD_HTTP_HEADER_CONTENT_ENCODING,
                                 "deflate")) )
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      setup_general_response_headers (rfc->key_state,
                                      krd->response_compressed))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called with information about the exchange's denomination
 * keys based on what is known in the database. Used to learn our
 * public keys (after the private keys are deleted, we still need to
 * have the public keys around for a while to verify signatures).
 *
 * This function checks if the @a denom_pub is already known to us,
 * and if not adds it to our set.
 *
 * @param cls closure, a `struct ResponseFactoryContext *`
 * @param denom_pub public key of the denomination
 * @param issue detailed information about the denomination (value, expiration times, fees)
 */
static void
reload_public_denoms_cb (void *cls,
                         const struct TALER_DenominationPublicKey *denom_pub,
                         const struct
                         TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  struct ResponseFactoryContext *rfc = cls;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation dki;
  int ret;

  if (rfc->now.abs_value_us > GNUNET_TIME_absolute_ntoh
        (issue->properties.expire_legal).abs_value_us)
  {
    /* Expired key, discard.  */
    return;
  }

  if (NULL !=
      GNUNET_CONTAINER_multihashmap_get (rfc->key_state->denomkey_map,
                                         &issue->properties.denom_hash))
    return; /* exists / known */
  if (NULL !=
      GNUNET_CONTAINER_multihashmap_get (rfc->key_state->revoked_map,
                                         &issue->properties.denom_hash))
    return; /* exists / known */
  /* zero-out, just for future-proofing */
  memset (&dki,
          0,
          sizeof (dki));
  dki.denom_priv.rsa_private_key = NULL; /* not available! */
  dki.denom_pub.rsa_public_key   = denom_pub->rsa_public_key;
  dki.issue = *issue;
  ret = store_in_map (rfc->key_state->denomkey_map,
                      &dki /* makes a deep copy of dki */);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Signature wrong on denomination key `%s' (skipping)!\n",
                GNUNET_h2s (&issue->properties.denom_hash));
    return;
  }
  /* we can assert here as we checked for duplicates just above */
  GNUNET_assert (GNUNET_OK == ret);
}


/**
 * Actual "main" logic that builds the state which this module
 * evolves around.  This function will import the key data from
 * the exchangedb module and convert it into (1) internally used
 * lookup tables, and (2) HTTP responses to be returned from
 * /keys.
 *
 * State returned is to be freed with #ks_free() -- but only
 * once the reference counter has again hit zero.
 *
 * @return NULL on error (usually pretty fatal...)
 */
static struct TEH_KS_StateHandle *
make_fresh_key_state (struct GNUNET_TIME_Absolute now)
{
  struct TEH_KS_StateHandle *key_state;
  struct ResponseFactoryContext rfc;
  struct GNUNET_TIME_Absolute last;
  unsigned int off;
  enum GNUNET_DB_QueryStatus qs;

  memset (&rfc,
          0,
          sizeof (rfc));
  rfc.recoup_array = json_array ();
  if (NULL == rfc.recoup_array)
  {
    GNUNET_break (0);
    return NULL;
  }
  rfc.sign_keys_array = json_array ();
  if (NULL == rfc.sign_keys_array)
  {
    GNUNET_break (0);
    json_decref (rfc.recoup_array);
    return NULL;
  }

  key_state = GNUNET_new (struct TEH_KS_StateHandle);
  rfc.key_state = key_state;
  rfc.now = now;
  key_state->min_dk_expire = GNUNET_TIME_UNIT_FOREVER_ABS;
  key_state->denomkey_map = GNUNET_CONTAINER_multihashmap_create (32,
                                                                  GNUNET_NO);
  key_state->revoked_map = GNUNET_CONTAINER_multihashmap_create (4,
                                                                 GNUNET_NO);
  key_state->reload_time = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&key_state->reload_time);

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Loading keys from `%s'\n",
              TEH_exchange_directory);
  /* Initialize the 'denomkey_map' and the 'revoked_map' and
     'rfc.recoup_array' */
  if (-1 ==
      TALER_EXCHANGEDB_denomination_keys_iterate (TEH_exchange_directory,
                                                  &reload_keys_denom_iter,
                                                  &rfc))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to load denomination keys from `%s'.\n",
                TEH_exchange_directory);
    ks_free (key_state);
    json_decref (rfc.recoup_array);
    json_decref (rfc.sign_keys_array);
    return NULL;
  }

  /* We do not get expired DKIs from
     TALER_EXCHANGEDB_denomination_keys_iterate(), so we must fetch
     the old keys (where we only have the public keys) from the
     database! */
  qs = TEH_plugin->iterate_denomination_info (TEH_plugin->cls,
                                              &reload_public_denoms_cb,
                                              &rfc);
  GNUNET_break (0 <= qs); /* warn, but continue, fingers crossed */

  /* process revocations */
  if (-1 ==
      TALER_EXCHANGEDB_revocations_iterate (TEH_revocation_directory,
                                            &TEH_master_public_key,
                                            &revocations_iter,
                                            &rfc))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to load denomination keys from `%s'.\n",
                TEH_exchange_directory);
    ks_free (key_state);
    json_decref (rfc.recoup_array);
    json_decref (rfc.sign_keys_array);
    return NULL;
  }

  /* Initialize `current_sign_key_issue` and `rfc.sign_keys_array` */
  TALER_EXCHANGEDB_signing_keys_iterate (TEH_exchange_directory,
                                         &reload_keys_sign_iter,
                                         &rfc);
  if (0 !=
      memcmp (&key_state->current_sign_key_issue.issue.master_public_key,
              &TEH_master_public_key,
              sizeof (struct TALER_MasterPublicKeyP)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Have no signing key. Bad configuration.\n");
    ks_free (key_state);
    destroy_response_factory (&rfc);
    return NULL;
  }

  /* sanity check */
  if (0 == GNUNET_CONTAINER_multihashmap_size (key_state->denomkey_map))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Have no denomination keys. Bad configuration.\n");
    ks_free (key_state);
    destroy_response_factory (&rfc);
    return NULL;
  }

  /* Initialize and sort the `denomkey_array` */
  rfc.denomkey_array
    = GNUNET_new_array (GNUNET_CONTAINER_multihashmap_size (
                          key_state->denomkey_map),
                        struct DenominationKeyEntry);
  GNUNET_CONTAINER_multihashmap_iterate (key_state->denomkey_map,
                                         &initialize_denomkey_array,
                                         &rfc);
  GNUNET_assert (rfc.denomkey_array_length ==
                 GNUNET_CONTAINER_multihashmap_size (key_state->denomkey_map));
  qsort (rfc.denomkey_array,
         rfc.denomkey_array_length,
         sizeof (struct DenominationKeyEntry),
         &denomkey_array_sort_comparator);

  /* Complete `denomkey_array` by adding auditor signature data */
  TALER_EXCHANGEDB_auditor_iterate (cfg,
                                    &reload_auditor_iter,
                                    &rfc);
  /* Sanity check: do we have auditors for all denomination keys? */
  for (unsigned int i = 0; i<rfc.denomkey_array_length; i++)
  {
    const struct DenominationKeyEntry *dke
      = &rfc.denomkey_array[i];

    if (NULL == dke->as_head)
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Denomination key `%s' at %p not signed by any auditor!\n",
                  GNUNET_h2s (&dke->denom_key_hash),
                  dke);
  }

  /* Determine size of `krd_array` by counting number of discrete
     denomination key starting times. */
  last = GNUNET_TIME_UNIT_ZERO_ABS;
  key_state->krd_array_length = 0;
  off = 1; /* reserve one slot for the "no keys" response */
  for (unsigned int i = 0; i<rfc.denomkey_array_length; i++)
  {
    const struct DenominationKeyEntry *dke
      = &rfc.denomkey_array[i];
    struct GNUNET_TIME_Absolute d
      = GNUNET_TIME_absolute_ntoh (dke->dki->issue.properties.start);

    if (last.abs_value_us == d.abs_value_us)
      continue;
    last = d;
    off++;
  }

  /* Compute next automatic reload time */
  key_state->next_reload =
    GNUNET_TIME_absolute_min (GNUNET_TIME_absolute_ntoh (
                                key_state->current_sign_key_issue.issue.expire),
                              key_state->min_dk_expire);
  GNUNET_assert (0 != key_state->next_reload.abs_value_us);


  /* Initialize `krd_array` */
  key_state->krd_array_length = off;
  key_state->krd_array
    = GNUNET_new_array (key_state->krd_array_length,
                        struct KeysResponseData);
  off = 0;
  last = GNUNET_TIME_UNIT_ZERO_ABS;
  for (unsigned int i = 0; i<rfc.denomkey_array_length; i++)
  {
    const struct DenominationKeyEntry *dke
      = &rfc.denomkey_array[i];
    struct GNUNET_TIME_Absolute d
      = GNUNET_TIME_absolute_ntoh (dke->dki->issue.properties.start);

    if (last.abs_value_us == d.abs_value_us)
      continue;
    if (GNUNET_OK !=
        build_keys_response (&rfc,
                             &key_state->krd_array[off++],
                             i,
                             last))
    {
      /* Fail hard, will be caught via test on `off` below */
      GNUNET_break (0);
      off = key_state->krd_array_length; /* flag as 'invalid' */
      break;
    }
    last = d;
  }

  /* Finally, build an `empty` response without denomination keys
     for requests past the last known denomination key start date */
  if ( (off + 1 < key_state->krd_array_length) ||
       (GNUNET_OK !=
        build_keys_response (&rfc,
                             &key_state->krd_array[off++],
                             rfc.denomkey_array_length,
                             last)) )
  {
    GNUNET_break (0);
    ks_free (key_state);
    destroy_response_factory (&rfc);
    return NULL;
  }

  /* Clean up intermediary state we don't need anymore and return
     new key_state! */
  destroy_response_factory (&rfc);
  return key_state;
}


/* ************************** Persistent part ********************** */

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
  int do_free;

  GNUNET_assert (0 == pthread_mutex_lock (&internal_key_state_mutex));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "KS released at %s (%p/%d)\n",
              location,
              key_state,
              key_state->refcnt);
  GNUNET_assert (0 < key_state->refcnt);
  key_state->refcnt--;
  do_free = (0 == key_state->refcnt);
  GNUNET_assert ( (! do_free) ||
                  (key_state != internal_key_state) );
  GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
  if (do_free)
    ks_free (key_state);
}


/**
 * Acquire the key state of the exchange.  Updates keys if necessary.
 * For every call to #TEH_KS_acquire(), a matching call
 * to #TEH_KS_release() must be made.
 *
 * @param now for what timestamp should we acquire the key state
 * @param location name of the function in which the lock is acquired
 * @return the key state, NULL on error (usually pretty fatal)
 */
struct TEH_KS_StateHandle *
TEH_KS_acquire_ (struct GNUNET_TIME_Absolute now,
                 const char *location)
{
  struct TEH_KS_StateHandle *key_state;
  struct TEH_KS_StateHandle *os;

  os = NULL;
  GNUNET_assert (0 == pthread_mutex_lock (&internal_key_state_mutex));
  /* If the current internal key state is missing (failed to load one on
     startup?) or expired, we try to setup a fresh one even without having
     gotten SIGUSR1 */
  if ( ( (NULL != internal_key_state) &&
         (internal_key_state->next_reload.abs_value_us <= now.abs_value_us) ) ||
       (NULL == internal_key_state) )
  {
    struct TEH_KS_StateHandle *os = internal_key_state;

    internal_key_state = make_fresh_key_state (now);
    internal_key_state->refcnt = 1; /* alias from #internal_key_state */
    if (NULL != os)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "KS released in acquire due to expiration\n");
      GNUNET_assert (0 < os->refcnt);
      os->refcnt--; /* #internal_key_state alias dropped */
      if (0 != os->refcnt)
        os = NULL; /* do NOT release yet, otherwise release after unlocking */
    }
  }
  if (NULL == internal_key_state)
  {
    /* We tried and failed (again) to setup #internal_key_state */
    GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize key state\n");
    return NULL;
  }
  key_state = internal_key_state;
  key_state->refcnt++; /* returning an alias, increment RC */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "KS acquired at %s (%p/%d)\n",
              location,
              key_state,
              key_state->refcnt);
  GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
  if (NULL != os)
    ks_free (os);
  return key_state;
}


/**
 * Look up the issue for a denom public key.  Note that the result
 * is only valid while the @a key_state is not released!
 *
 * @param key_state state to look in
 * @param denom_pub_hash hash of denomination public key
 * @param use purpose for which the key is being located
 * @param[out] ec set to the error code, in case the operation failed
 * @param[out] hc set to the HTTP status code to use
 * @return the denomination key issue,
 *         or NULL if denom_pub could not be found (or is not valid at this time for the given @a use)
 */
struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *
TEH_KS_denomination_key_lookup_by_hash (const struct
                                        TEH_KS_StateHandle *key_state,
                                        const struct
                                        GNUNET_HashCode *denom_pub_hash,
                                        enum TEH_KS_DenominationKeyUse use,
                                        enum TALER_ErrorCode *ec,
                                        unsigned int *hc)
{
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;
  struct GNUNET_TIME_Absolute now;
  const struct GNUNET_CONTAINER_MultiHashMap *map;

  map = (TEH_KS_DKU_RECOUP == use) ? key_state->revoked_map :
        key_state->denomkey_map;
  dki = GNUNET_CONTAINER_multihashmap_get (map,
                                           denom_pub_hash);
  if ( (NULL == dki) && (TEH_KS_DKU_ZOMBIE == use))
    dki = GNUNET_CONTAINER_multihashmap_get (key_state->revoked_map,
                                             denom_pub_hash);
  if (NULL == dki)
  {
    *hc = MHD_HTTP_NOT_FOUND;
    switch (use)
    {
    case TEH_KS_DKU_RECOUP:
      *ec = TALER_EC_RECOUP_DENOMINATION_KEY_UNKNOWN;
      break;
    case TEH_KS_DKU_ZOMBIE:
      *ec = TALER_EC_REFRESH_RECOUP_DENOMINATION_KEY_NOT_FOUND;
      break;
    case TEH_KS_DKU_WITHDRAW:
      *ec = TALER_EC_WITHDRAW_DENOMINATION_KEY_NOT_FOUND;
      break;
    case TEH_KS_DKU_DEPOSIT:
      *ec = TALER_EC_DEPOSIT_DENOMINATION_KEY_UNKNOWN;
      break;
    }
    return NULL;
  }
  now = GNUNET_TIME_absolute_get ();
  if (now.abs_value_us <
      GNUNET_TIME_absolute_ntoh (dki->issue.properties.start).abs_value_us)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Not returning DKI for %s, as start time is in the future\n",
                GNUNET_h2s (denom_pub_hash));
    *hc = MHD_HTTP_PRECONDITION_FAILED;
    switch (use)
    {
    case TEH_KS_DKU_RECOUP:
      *ec = TALER_EC_RECOUP_DENOMINATION_VALIDITY_IN_FUTURE;
      break;
    case TEH_KS_DKU_ZOMBIE:
      *ec = TALER_EC_REFRESH_RECOUP_DENOMINATION_VALIDITY_IN_FUTURE;
      break;
    case TEH_KS_DKU_WITHDRAW:
      *ec = TALER_EC_WITHDRAW_VALIDITY_IN_FUTURE;
      break;
    case TEH_KS_DKU_DEPOSIT:
      *ec = TALER_EC_DEPOSIT_DENOMINATION_VALIDITY_IN_FUTURE;
      break;
    }
    return NULL;
  }
  now = GNUNET_TIME_absolute_get ();
  switch (use)
  {
  case TEH_KS_DKU_WITHDRAW:
    if (now.abs_value_us >
        GNUNET_TIME_absolute_ntoh (
          dki->issue.properties.expire_withdraw).abs_value_us)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Not returning DKI for %s, as time to create coins has passed\n",
                  GNUNET_h2s (denom_pub_hash));
      *ec = TALER_EC_WITHDRAW_VALIDITY_IN_PAST;
      *hc = MHD_HTTP_GONE;
      return NULL;
    }
    if (NULL == dki->denom_priv.rsa_private_key)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Not returning DKI of %s for WITHDRAW operation as we lack the private key, even though the withdraw period did not yet expire!\n",
                  GNUNET_h2s (denom_pub_hash));
      *ec = TALER_EC_DENOMINATION_KEY_LOST;
      *hc = MHD_HTTP_SERVICE_UNAVAILABLE;
      return NULL;
    }
    break;
  case TEH_KS_DKU_DEPOSIT:
    if (now.abs_value_us >
        GNUNET_TIME_absolute_ntoh (
          dki->issue.properties.expire_deposit).abs_value_us)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Not returning DKI for %s, as time to spend coin has passed\n",
                  GNUNET_h2s (denom_pub_hash));
      *ec = TALER_EC_DEPOSIT_DENOMINATION_EXPIRED;
      *hc = MHD_HTTP_GONE;
      return NULL;
    }
    break;
  case TEH_KS_DKU_RECOUP:
    if (now.abs_value_us >
        GNUNET_TIME_absolute_ntoh (
          dki->issue.properties.expire_deposit).abs_value_us)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Not returning DKI for %s, as time to recoup coin has passed\n",
                  GNUNET_h2s (denom_pub_hash));
      *ec = TALER_EC_REFRESH_RECOUP_DENOMINATION_EXPIRED;
      *hc = MHD_HTTP_GONE;
      return NULL;
    }
    break;
  case TEH_KS_DKU_ZOMBIE:
    if (now.abs_value_us >
        GNUNET_TIME_absolute_ntoh (
          dki->issue.properties.expire_legal).abs_value_us)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Not returning DKI for %s, as legal expiration of coin has passed\n",
                  GNUNET_h2s (denom_pub_hash));
      *ec = TALER_EC_REFRESH_ZOMBIE_DENOMINATION_EXPIRED;
      *hc = MHD_HTTP_GONE;
      return NULL;
    }
    break;
  }
  return dki;
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
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "pipe");
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
      {
        struct TEH_KS_StateHandle *fs;
        struct TEH_KS_StateHandle *os;

        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "(re-)loading keys\n");
        /* Create fresh key state before critical region */
        fs = make_fresh_key_state (GNUNET_TIME_absolute_get ());
        if (NULL == fs)
        {
          /* Ok, that went badly, terminate process */
          ret = GNUNET_SYSERR;
          break;
        }
        fs->refcnt = 1; /* we'll alias from #internal_key_state soon */
        /* swap active key state in critical region */
        GNUNET_assert (0 == pthread_mutex_lock (&internal_key_state_mutex));
        os = internal_key_state;
        internal_key_state = fs;
        if (NULL != os)
        {
          GNUNET_assert (0 < os->refcnt);
          os->refcnt--; /* removed #internal_key_state reference */
        }
        if (0 != os->refcnt)
          os = NULL; /* other aliases are still active, do not yet free */
        GNUNET_assert (0 == pthread_mutex_unlock (&internal_key_state_mutex));
        if (NULL != os)
          ks_free (os); /* RC did hit zero, free */
      }
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
  GNUNET_SIGNAL_handler_uninstall (sigusr1);
  GNUNET_SIGNAL_handler_uninstall (sigterm);
  GNUNET_SIGNAL_handler_uninstall (sigint);
  GNUNET_SIGNAL_handler_uninstall (sighup);
  GNUNET_SIGNAL_handler_uninstall (sigchld);
  GNUNET_break (0 == close (reload_pipe[0]));
  GNUNET_break (0 == close (reload_pipe[1]));
  return ret;
}


/**
 * Setup initial #internal_key_state.
 */
void
TEH_KS_init (void)
{
  /* no need to lock here, as we are still single-threaded */
  internal_key_state = make_fresh_key_state (GNUNET_TIME_absolute_get ());
  if (NULL == internal_key_state)
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to setup initial key state. This exchange cannot work.\n");
  internal_key_state->refcnt = 1;
}


/**
 * Finally release #internal_key_state.
 */
void
TEH_KS_free ()
{
  struct TEH_KS_StateHandle *ks;

  /* Note: locking is no longer be required, as we are again
     single-threaded. */
  ks = internal_key_state;
  if (NULL == ks)
    return;
  GNUNET_assert (1 == ks->refcnt);
  ks->refcnt--;
  ks_free (ks);
}


/**
 * Sign the message in @a purpose with the exchange's signing key.
 *
 * @param purpose the message to sign
 * @param[out] pub set to the current public signing key of the exchange
 * @param[out] sig signature over purpose using current signing key
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if we lack key material
 */
int
TEH_KS_sign (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
             struct TALER_ExchangePublicKeyP *pub,
             struct TALER_ExchangeSignatureP *sig)

{
  struct TEH_KS_StateHandle *key_state;

  key_state = TEH_KS_acquire (GNUNET_TIME_absolute_get ());
  if (NULL == key_state)
  {
    /* This *can* happen if the exchange's keys are
       not properly maintained. */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                _ ("Cannot sign request, no valid keys available\n"));
    return GNUNET_SYSERR;
  }
  *pub = key_state->current_sign_key_issue.issue.signkey_pub;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (
                   &key_state->current_sign_key_issue.signkey_priv.eddsa_priv,
                   purpose,
                   &sig->eddsa_signature));
  TEH_KS_release (key_state);
  return GNUNET_OK;
}


/**
 * Comparator used for a binary search for @a key in the
 * `struct KeysResponseData` array.
 *
 * @param key pointer to a `struct GNUNET_TIME_Absolute`
 * @param value pointer to a `struct KeysResponseData` array entry
 * @return 0 if time matches, -1 if key is smaller, 1 if key is larger
 */
static int
krd_search_comparator (const void *key,
                       const void *value)
{
  const struct GNUNET_TIME_Absolute *kd = key;
  const struct KeysResponseData *krd = value;

  if (kd->abs_value_us > krd->cherry_pick_date.abs_value_us)
    return 1;
  if (kd->abs_value_us < krd->cherry_pick_date.abs_value_us)
    return -1;
  return 0;
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
  int ret;
  const char *have_cherrypick;
  const char *have_fakenow;
  struct GNUNET_TIME_Absolute last_issue_date;
  struct GNUNET_TIME_Absolute now;
  const struct KeysResponseData *krd;

  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  have_cherrypick = MHD_lookup_connection_value (connection,
                                                 MHD_GET_ARGUMENT_KIND,
                                                 "last_issue_date");
  if (NULL != have_cherrypick)
  {
    unsigned long long cherrypickn;

    if (1 !=
        sscanf (have_cherrypick,
                "%llu",
                &cherrypickn))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_KEYS_HAVE_NOT_NUMERIC,
                                         "last_issue_date");
    }
    last_issue_date.abs_value_us = (uint64_t) cherrypickn * 1000000LLU;
  }
  else
  {
    last_issue_date.abs_value_us = 0LLU;
  }
  now = GNUNET_TIME_absolute_get ();
  have_fakenow = MHD_lookup_connection_value (connection,
                                              MHD_GET_ARGUMENT_KIND,
                                              "now");
  if (NULL != have_fakenow)
  {
    unsigned long long fakenown;

    if (1 !=
        sscanf (have_fakenow,
                "%llu",
                &fakenown))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_KEYS_HAVE_NOT_NUMERIC,
                                         "now");
    }
    now.abs_value_us = (uint64_t) fakenown * 1000000LLU;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling request for /keys (%s/%s)\n",
              have_cherrypick,
              have_fakenow);
  {
    struct TEH_KS_StateHandle *key_state;

    key_state = TEH_KS_acquire (now);
    if (NULL == key_state)
    {
      TALER_LOG_ERROR ("Lacking keys to operate\n");
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                         "no keys");
    }
    krd = bsearch (&last_issue_date,
                   key_state->krd_array,
                   key_state->krd_array_length,
                   sizeof (struct KeysResponseData),
                   &krd_search_comparator);

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Filtering /keys by cherry pick date %s found entry %u/%u\n",
                GNUNET_STRINGS_absolute_time_to_string (last_issue_date),
                (unsigned int) (krd - key_state->krd_array),
                key_state->krd_array_length);
    if ( (NULL == krd) &&
         (key_state->krd_array_length > 0) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Client provided invalid cherry picking timestamp %s, returning full response\n",
                  GNUNET_STRINGS_absolute_time_to_string (last_issue_date));
      krd = &key_state->krd_array[0];
    }
    if (NULL == krd)
    {
      GNUNET_break (0);
      TEH_KS_release (key_state);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_KEYS_MISSING,
                                         "no key response found");
    }
    ret = MHD_queue_response (connection,
                              rh->response_code,
                              (MHD_YES == TALER_MHD_can_compress (connection))
                              ? krd->response_compressed
                              : krd->response_uncompressed);
    TEH_KS_release (key_state);
  }
  return ret;
}


/* end of taler-exchange-httpd_keystate.c */
