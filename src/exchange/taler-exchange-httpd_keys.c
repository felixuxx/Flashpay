/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file taler-exchange-httpd_keys.c
 * @brief management of our various keys
 * @author Christian Grothoff
 */
#include "platform.h"
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd.h"
#include "taler-exchange-httpd_keys.h"
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
#define EXCHANGE_PROTOCOL_VERSION "9:0:0"


/**
 * Information about a denomination on offer by the denomination helper.
 */
struct HelperDenomination
{

  /**
   * When will the helper start to use this key for signing?
   */
  struct GNUNET_TIME_Absolute start_time;

  /**
   * For how long will the helper allow signing? 0 if
   * the key was revoked or purged.
   */
  struct GNUNET_TIME_Relative validity_duration;

  /**
   * Hash of the denomination key.
   */
  struct GNUNET_HashCode h_denom_pub;

  /**
   * Signature over this key from the security module's key.
   */
  struct TALER_SecurityModuleSignatureP sm_sig;

  /**
   * The (full) public key.
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * Name in configuration section for this denomination type.
   */
  char *section_name;

};


/**
 * Signatures of an auditor over a denomination key of this exchange.
 */
struct TEH_AuditorSignature
{
  /**
   * We store the signatures in a DLL.
   */
  struct TEH_AuditorSignature *prev;

  /**
   * We store the signatures in a DLL.
   */
  struct TEH_AuditorSignature *next;

  /**
   * A signature from the auditor.
   */
  struct TALER_AuditorSignatureP asig;

  /**
   * Public key of the auditor.
   */
  struct TALER_AuditorPublicKeyP apub;

};


/**
 * Information about a signing key on offer by the esign helper.
 */
struct HelperSignkey
{
  /**
   * When will the helper start to use this key for signing?
   */
  struct GNUNET_TIME_Absolute start_time;

  /**
   * For how long will the helper allow signing? 0 if
   * the key was revoked or purged.
   */
  struct GNUNET_TIME_Relative validity_duration;

  /**
   * The public key.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Signature over this key from the security module's key.
   */
  struct TALER_SecurityModuleSignatureP sm_sig;

};


/**
 * State associated with the crypto helpers / security modules.
 * Created per-thread, but NOT updated when the #key_generation
 * is updated (instead constantly kept in sync whenever
 * #TEH_keys_get_state() is called).
 */
struct HelperState
{

  /**
   * Handle for the esign/EdDSA helper.
   */
  struct TALER_CRYPTO_ExchangeSignHelper *esh;

  /**
   * Handle for the denom/RSA helper.
   */
  struct TALER_CRYPTO_DenominationHelper *dh;

  /**
   * Map from H(denom_pub) to `struct HelperDenomination` entries.
   */
  struct GNUNET_CONTAINER_MultiHashMap *denom_keys;

  /**
   * Map from `struct TALER_ExchangePublicKey` to `struct HelperSignkey`
   * entries.  Based on the fact that a `struct GNUNET_PeerIdentity` is also
   * an EdDSA public key.
   */
  struct GNUNET_CONTAINER_MultiPeerMap *esign_keys;

};


/**
 * Entry in (sorted) array with possible pre-build responses for /keys.
 * We keep pre-build responses for the various (valid) cherry-picking
 * values around.
 */
struct KeysResponseData
{

  /**
   * Response to return if the client supports (deflate) compression.
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
 * @brief All information about an exchange online signing key (which is used to
 * sign messages from the exchange).
 */
struct SigningKey
{

  /**
   * The exchange's (online signing) public key.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Meta data about the signing key, such as validity periods.
   */
  struct TALER_EXCHANGEDB_SignkeyMetaData meta;

  /**
   * The long-term offline master key's signature for this signing key.
   * Signs over @e exchange_pub and @e meta.
   */
  struct TALER_MasterSignatureP master_sig;

};


struct TEH_KeyStateHandle
{

  /**
   * Mapping from denomination keys to denomination key issue struct.
   * Used to lookup the key by hash.
   */
  struct GNUNET_CONTAINER_MultiHashMap *denomkey_map;

  /**
   * Map from `struct TALER_ExchangePublicKey` to `struct SigningKey`
   * entries.  Based on the fact that a `struct GNUNET_PeerIdentity` is also
   * an EdDSA public key.
   */
  struct GNUNET_CONTAINER_MultiPeerMap *signkey_map;

  /**
   * json array with the auditors of this exchange. Contains exactly
   * the information needed for the "auditors" field of the /keys response.
   */
  json_t *auditors;

  /**
   * Cached reply for a GET /management/keys request.  Used so we do not
   * re-create the reply every time.
   */
  json_t *management_keys_reply;

  /**
   * Sorted array of responses to /keys (MUST be sorted by cherry-picking date) of
   * length @e krd_array_length;
   */
  struct KeysResponseData *krd_array;

  /**
   * Length of the @e krd_array.
   */
  unsigned int krd_array_length;

  /**
   * Information we track for thecrypto helpers.  Preserved
   * when the @e key_generation changes, thus kept separate.
   */
  struct HelperState helpers;

  /**
   * For which (global) key_generation was this data structure created?
   * Used to check when we are outdated and need to be re-generated.
   */
  uint64_t key_generation;

  /**
   * When did we initiate the key reloading?
   */
  struct GNUNET_TIME_Absolute reload_time;

  /**
   * When is the next key invalid and we expect to have a different reply?
   */
  struct GNUNET_TIME_Absolute next_reload;

  /**
   * True if #finish_keys_response() was not yet run and this key state
   * is only suitable for the /management/keys API.
   */
  bool management_only;

};


/**
 * Entry of /keys requests that are currently suspended because we are
 * waiting for /keys to become ready.
 */
struct SuspendedKeysRequests
{
  /**
   * Kept in a DLL.
   */
  struct SuspendedKeysRequests *next;

  /**
   * Kept in a DLL.
   */
  struct SuspendedKeysRequests *prev;

  /**
   * The suspended connection.
   */
  struct MHD_Connection *connection;
};


/**
 * Thread-local.  Contains a pointer to `struct TEH_KeyStateHandle` or NULL.
 * Stores the per-thread latest generation of our key state.
 */
static pthread_key_t key_state;

/**
 * Counter incremented whenever we have a reason to re-build the keys because
 * something external changed (in another thread).  The counter is manipulated
 * using an atomic update, and thus to ensure that threads notice when it
 * changes, the variable MUST be volatile.  See #TEH_keys_get_state() and
 * #TEH_keys_update_states() for uses of this variable.
 */
static volatile uint64_t key_generation;

/**
 * Head of DLL of suspended /keys requests.
 */
static struct SuspendedKeysRequests *skr_head;

/**
 * Tail of DLL of suspended /keys requests.
 */
static struct SuspendedKeysRequests *skr_tail;

/**
 * For how long should a signing key be legally retained?
 * Configuration value.
 */
static struct GNUNET_TIME_Relative signkey_legal_duration;

/**
 * RSA security module public key, all zero if not known.
 */
static struct TALER_SecurityModulePublicKeyP denom_sm_pub;

/**
 * EdDSA security module public key, all zero if not known.
 */
static struct TALER_SecurityModulePublicKeyP esign_sm_pub;

/**
 * Mutex protecting access to #denom_sm_pub and #esign_sm_pub.
 * (Could be split into two locks if ever needed.)
 */
static pthread_mutex_t sm_pub_mutex = PTHREAD_MUTEX_INITIALIZER;

/**
 * Mutex protecting access to #skr_head and #skr_tail.
 * (Could be split into two locks if ever needed.)
 */
static pthread_mutex_t skr_mutex = PTHREAD_MUTEX_INITIALIZER;

/**
 * Are we shutting down?
 */
static bool terminating;

/**
 * Did we ever initialize #key_state?
 */
static bool key_state_available;


/**
 * Suspend /keys request while we (hopefully) are waiting to be
 * provisioned with key material.
 *
 * @param[in] connection to suspend
 */
static MHD_RESULT
suspend_request (struct MHD_Connection *connection)
{
  struct SuspendedKeysRequests *skr;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Suspending /keys request until key material changes\n");
  GNUNET_assert (0 == pthread_mutex_lock (&skr_mutex));
  if (terminating)
  {
    GNUNET_assert (0 == pthread_mutex_unlock (&skr_mutex));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                       "Exchange terminating");
  }
  skr = GNUNET_new (struct SuspendedKeysRequests);
  skr->connection = connection;
  MHD_suspend_connection (connection);
  GNUNET_CONTAINER_DLL_insert (skr_head,
                               skr_tail,
                               skr);
  GNUNET_assert (0 == pthread_mutex_unlock (&skr_mutex));
  return MHD_YES;
}


void
TEH_resume_keys_requests (bool do_shutdown)
{
  struct SuspendedKeysRequests *skr;

  GNUNET_assert (0 == pthread_mutex_lock (&skr_mutex));
  if (do_shutdown)
    terminating = true;
  while (NULL != (skr = skr_head))
  {
    GNUNET_CONTAINER_DLL_remove (skr_head,
                                 skr_tail,
                                 skr);
    MHD_resume_connection (skr->connection);
    GNUNET_free (skr);
  }
  GNUNET_assert (0 == pthread_mutex_unlock (&skr_mutex));
}


/**
 * Clear memory for responses to "/keys" in @a ksh.
 *
 * @param[in,out] ksh key state to update
 */
static void
clear_response_cache (struct TEH_KeyStateHandle *ksh)
{
  for (unsigned int i = 0; i<ksh->krd_array_length; i++)
  {
    struct KeysResponseData *krd = &ksh->krd_array[i];

    MHD_destroy_response (krd->response_compressed);
    MHD_destroy_response (krd->response_uncompressed);
  }
  GNUNET_array_grow (ksh->krd_array,
                     ksh->krd_array_length,
                     0);
}


/**
 * Check that the given RSA security module's public key is the one
 * we have pinned.  If it does not match, we die hard.
 *
 * @param sm_pub RSA security module public key to check
 */
static void
check_denom_sm_pub (const struct TALER_SecurityModulePublicKeyP *sm_pub)
{
  GNUNET_assert (0 == pthread_mutex_lock (&sm_pub_mutex));
  if (0 !=
      GNUNET_memcmp (sm_pub,
                     &denom_sm_pub))
  {
    if (! GNUNET_is_zero (&denom_sm_pub))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Our RSA security module changed its key. This must not happen.\n");
      GNUNET_assert (0);
    }
    denom_sm_pub = *sm_pub; /* TOFU ;-) */
  }
  GNUNET_assert (0 == pthread_mutex_unlock (&sm_pub_mutex));
}


/**
 * Check that the given EdDSA security module's public key is the one
 * we have pinned.  If it does not match, we die hard.
 *
 * @param sm_pub EdDSA security module public key to check
 */
static void
check_esign_sm_pub (const struct TALER_SecurityModulePublicKeyP *sm_pub)
{
  GNUNET_assert (0 == pthread_mutex_lock (&sm_pub_mutex));
  if (0 !=
      GNUNET_memcmp (sm_pub,
                     &esign_sm_pub))
  {
    if (! GNUNET_is_zero (&esign_sm_pub))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Our EdDSA security module changed its key. This must not happen.\n");
      GNUNET_assert (0);
    }
    esign_sm_pub = *sm_pub; /* TOFU ;-) */
  }
  GNUNET_assert (0 == pthread_mutex_unlock (&sm_pub_mutex));
}


/**
 * Helper function for #destroy_key_helpers to free all entries
 * in the `denom_keys` map.
 *
 * @param cls the `struct HelperState`
 * @param h_denom_pub hash of the denomination public key
 * @param value the `struct HelperDenomination` to release
 * @return #GNUNET_OK (continue to iterate)
 */
static int
free_denom_cb (void *cls,
               const struct GNUNET_HashCode *h_denom_pub,
               void *value)
{
  struct HelperDenomination *hd = value;

  (void) cls;
  (void) h_denom_pub;
  GNUNET_CRYPTO_rsa_public_key_free (hd->denom_pub.rsa_public_key);
  GNUNET_free (hd->section_name);
  GNUNET_free (hd);
  return GNUNET_OK;
}


/**
 * Helper function for #destroy_key_helpers to free all entries
 * in the `esign_keys` map.
 *
 * @param cls the `struct HelperState`
 * @param pid unused, matches the exchange public key
 * @param value the `struct HelperSignkey` to release
 * @return #GNUNET_OK (continue to iterate)
 */
static int
free_esign_cb (void *cls,
               const struct GNUNET_PeerIdentity *pid,
               void *value)
{
  struct HelperSignkey *hsk = value;

  (void) cls;
  (void) pid;
  GNUNET_free (hsk);
  return GNUNET_OK;
}


/**
 * Destroy helper state. Does NOT call free() on @a hs, as that
 * state is not separately allocated!  Dual to #setup_key_helpers().
 *
 * @param[in] hs helper state to free, but NOT the @a hs pointer itself!
 */
static void
destroy_key_helpers (struct HelperState *hs)
{
  GNUNET_CONTAINER_multihashmap_iterate (hs->denom_keys,
                                         &free_denom_cb,
                                         hs);
  GNUNET_CONTAINER_multihashmap_destroy (hs->denom_keys);
  hs->denom_keys = NULL;
  GNUNET_CONTAINER_multipeermap_iterate (hs->esign_keys,
                                         &free_esign_cb,
                                         hs);
  GNUNET_CONTAINER_multipeermap_destroy (hs->esign_keys);
  hs->esign_keys = NULL;
  if (NULL != hs->dh)
  {
    TALER_CRYPTO_helper_denom_disconnect (hs->dh);
    hs->dh = NULL;
  }
  if (NULL != hs->esh)
  {
    TALER_CRYPTO_helper_esign_disconnect (hs->esh);
    hs->esh = NULL;
  }
}


/**
 * Function called with information about available keys for signing.  Usually
 * only called once per key upon connect. Also called again in case a key is
 * being revoked, in that case with an @a end_time of zero.
 *
 * @param cls closure with the `struct HelperState *`
 * @param section_name name of the denomination type in the configuration;
 *                 NULL if the key has been revoked or purged
 * @param start_time when does the key become available for signing;
 *                 zero if the key has been revoked or purged
 * @param validity_duration how long does the key remain available for signing;
 *                 zero if the key has been revoked or purged
 * @param h_denom_pub hash of the @a denom_pub that is available (or was purged)
 * @param denom_pub the public key itself, NULL if the key was revoked or purged
 * @param sm_pub public key of the security module, NULL if the key was revoked or purged
 * @param sm_sig signature from the security module, NULL if the key was revoked or purged
 *               The signature was already verified against @a sm_pub.
 */
static void
helper_denom_cb (
  void *cls,
  const char *section_name,
  struct GNUNET_TIME_Absolute start_time,
  struct GNUNET_TIME_Relative validity_duration,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_SecurityModulePublicKeyP *sm_pub,
  const struct TALER_SecurityModuleSignatureP *sm_sig)
{
  struct HelperState *hs = cls;
  struct HelperDenomination *hd;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "RSA helper announces key %s for denomination type %s with validity %s\n",
              GNUNET_h2s (h_denom_pub),
              section_name,
              GNUNET_STRINGS_relative_time_to_string (validity_duration,
                                                      GNUNET_NO));
  hd = GNUNET_CONTAINER_multihashmap_get (hs->denom_keys,
                                          h_denom_pub);
  if (NULL != hd)
  {
    /* should be just an update (revocation!), so update existing entry */
    hd->validity_duration = validity_duration;
    return;
  }
  GNUNET_assert (NULL != sm_pub);
  check_denom_sm_pub (sm_pub);
  hd = GNUNET_new (struct HelperDenomination);
  hd->start_time = start_time;
  hd->validity_duration = validity_duration;
  hd->h_denom_pub = *h_denom_pub;
  hd->sm_sig = *sm_sig;
  hd->denom_pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_public_key_dup (denom_pub->rsa_public_key);
  hd->section_name = GNUNET_strdup (section_name);
  GNUNET_assert (
    GNUNET_OK ==
    GNUNET_CONTAINER_multihashmap_put (
      hs->denom_keys,
      &hd->h_denom_pub,
      hd,
      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
}


/**
 * Function called with information about available keys for signing.  Usually
 * only called once per key upon connect. Also called again in case a key is
 * being revoked, in that case with an @a end_time of zero.
 *
 * @param cls closure with the `struct HelperState *`
 * @param start_time when does the key become available for signing;
 *                 zero if the key has been revoked or purged
 * @param validity_duration how long does the key remain available for signing;
 *                 zero if the key has been revoked or purged
 * @param exchange_pub the public key itself, NULL if the key was revoked or purged
 * @param sm_pub public key of the security module, NULL if the key was revoked or purged
 * @param sm_sig signature from the security module, NULL if the key was revoked or purged
 *               The signature was already verified against @a sm_pub.
 */
static void
helper_esign_cb (
  void *cls,
  struct GNUNET_TIME_Absolute start_time,
  struct GNUNET_TIME_Relative validity_duration,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_SecurityModulePublicKeyP *sm_pub,
  const struct TALER_SecurityModuleSignatureP *sm_sig)
{
  struct HelperState *hs = cls;
  struct HelperSignkey *hsk;
  struct GNUNET_PeerIdentity pid;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "EdDSA helper announces signing key %s with validity %s\n",
              TALER_B2S (exchange_pub),
              GNUNET_STRINGS_relative_time_to_string (validity_duration,
                                                      GNUNET_NO));
  pid.public_key = exchange_pub->eddsa_pub;
  hsk = GNUNET_CONTAINER_multipeermap_get (hs->esign_keys,
                                           &pid);
  if (NULL != hsk)
  {
    /* should be just an update (revocation!), so update existing entry */
    hsk->validity_duration = validity_duration;
    GNUNET_break (start_time.abs_value_us ==
                  hsk->start_time.abs_value_us);
    return;
  }
  GNUNET_assert (NULL != sm_pub);
  check_esign_sm_pub (sm_pub);
  hsk = GNUNET_new (struct HelperSignkey);
  hsk->start_time = start_time;
  hsk->validity_duration = validity_duration;
  hsk->exchange_pub = *exchange_pub;
  hsk->sm_sig = *sm_sig;
  GNUNET_assert (
    GNUNET_OK ==
    GNUNET_CONTAINER_multipeermap_put (
      hs->esign_keys,
      &pid,
      hsk,
      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
}


/**
 * Setup helper state.
 *
 * @param[out] hs helper state to initialize
 * @return #GNUNET_OK on success
 */
static int
setup_key_helpers (struct HelperState *hs)
{
  hs->denom_keys
    = GNUNET_CONTAINER_multihashmap_create (1024,
                                            GNUNET_YES);
  hs->esign_keys
    = GNUNET_CONTAINER_multipeermap_create (32,
                                            GNUNET_NO /* MUST BE NO! */);
  hs->dh = TALER_CRYPTO_helper_denom_connect (TEH_cfg,
                                              &helper_denom_cb,
                                              hs);
  if (NULL == hs->dh)
  {
    destroy_key_helpers (hs);
    return GNUNET_SYSERR;
  }
  hs->esh = TALER_CRYPTO_helper_esign_connect (TEH_cfg,
                                               &helper_esign_cb,
                                               hs);
  if (NULL == hs->esh)
  {
    destroy_key_helpers (hs);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Synchronize helper state. Polls the key helper for updates.
 *
 * @param[in,out] hs helper state to synchronize
 */
static void
sync_key_helpers (struct HelperState *hs)
{
  TALER_CRYPTO_helper_denom_poll (hs->dh);
  TALER_CRYPTO_helper_esign_poll (hs->esh);
}


/**
 * Free denomination key data.
 *
 * @param cls a `struct TEH_KeyStateHandle`, unused
 * @param h_denom_pub hash of the denomination public key, unused
 * @param value a `struct TEH_DenominationKey` to free
 * @return #GNUNET_OK (continue to iterate)
 */
static int
clear_denomination_cb (void *cls,
                       const struct GNUNET_HashCode *h_denom_pub,
                       void *value)
{
  struct TEH_DenominationKey *dk = value;
  struct TEH_AuditorSignature *as;

  (void) cls;
  (void) h_denom_pub;
  GNUNET_CRYPTO_rsa_public_key_free (dk->denom_pub.rsa_public_key);
  while (NULL != (as = dk->as_head))
  {
    GNUNET_CONTAINER_DLL_remove (dk->as_head,
                                 dk->as_tail,
                                 as);
    GNUNET_free (as);
  }
  GNUNET_free (dk);
  return GNUNET_OK;
}


/**
 * Free denomination key data.
 *
 * @param cls a `struct TEH_KeyStateHandle`, unused
 * @param pid the online signing key (type-disguised), unused
 * @param value a `struct SigningKey` to free
 * @return #GNUNET_OK (continue to iterate)
 */
static int
clear_signkey_cb (void *cls,
                  const struct GNUNET_PeerIdentity *pid,
                  void *value)
{
  struct SigningKey *sk = value;

  (void) cls;
  (void) pid;
  GNUNET_free (sk);
  return GNUNET_OK;
}


/**
 * Free resources associated with @a cls, possibly excluding
 * the helper data.
 *
 * @param[in] ksh key state to release
 * @param free_helper true to also release the helper state
 */
static void
destroy_key_state (struct TEH_KeyStateHandle *ksh,
                   bool free_helper)
{
  clear_response_cache (ksh);
  GNUNET_CONTAINER_multihashmap_iterate (ksh->denomkey_map,
                                         &clear_denomination_cb,
                                         ksh);
  GNUNET_CONTAINER_multihashmap_destroy (ksh->denomkey_map);
  GNUNET_CONTAINER_multipeermap_iterate (ksh->signkey_map,
                                         &clear_signkey_cb,
                                         ksh);
  GNUNET_CONTAINER_multipeermap_destroy (ksh->signkey_map);
  json_decref (ksh->auditors);
  ksh->auditors = NULL;
  if (NULL != ksh->management_keys_reply)
  {
    json_decref (ksh->management_keys_reply);
    ksh->management_keys_reply = NULL;
  }
  if (free_helper)
    destroy_key_helpers (&ksh->helpers);
  GNUNET_free (ksh);
}


/**
 * Free all resources associated with @a cls.  Called when
 * the respective pthread is destroyed.
 *
 * @param[in] cls a `struct TEH_KeyStateHandle`.
 */
static void
destroy_key_state_cb (void *cls)
{
  struct TEH_KeyStateHandle *ksh = cls;

  destroy_key_state (ksh,
                     true);
}


/**
 * Initialize keys submodule.
 *
 * @return #GNUNET_OK on success
 */
int
TEH_keys_init ()
{
  if (0 !=
      pthread_key_create (&key_state,
                          &destroy_key_state_cb))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  key_state_available = true;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (TEH_cfg,
                                           "exchange",
                                           "SIGNKEY_LEGAL_DURATION",
                                           &signkey_legal_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "SIGNKEY_LEGAL_DURATION");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Fully clean up our state.
 */
void __attribute__ ((destructor))
TEH_keys_finished ()
{
  if (key_state_available)
  {
    GNUNET_assert (0 ==
                   pthread_key_delete (key_state));
  }
}


/**
 * Function called with information about the exchange's denomination keys.
 *
 * @param cls closure with a `struct TEH_KeyStateHandle *`
 * @param denom_pub public key of the denomination
 * @param h_denom_pub hash of @a denom_pub
 * @param meta meta data information about the denomination type (value, expirations, fees)
 * @param master_sig master signature affirming the validity of this denomination
 * @param recoup_possible true if the key was revoked and clients can currently recoup
 *        coins of this denomination
 */
static void
denomination_info_cb (
  void *cls,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta,
  const struct TALER_MasterSignatureP *master_sig,
  bool recoup_possible)
{
  struct TEH_KeyStateHandle *ksh = cls;
  struct TEH_DenominationKey *dk;

  dk = GNUNET_new (struct TEH_DenominationKey);
  dk->denom_pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_public_key_dup (denom_pub->rsa_public_key);
  dk->h_denom_pub = *h_denom_pub;
  dk->meta = *meta;
  dk->master_sig = *master_sig;
  dk->recoup_possible = recoup_possible;
  GNUNET_assert (
    GNUNET_OK ==
    GNUNET_CONTAINER_multihashmap_put (ksh->denomkey_map,
                                       &dk->h_denom_pub,
                                       dk,
                                       GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
}


/**
 * Function called with information about the exchange's online signing keys.
 *
 * @param cls closure with a `struct TEH_KeyStateHandle *`
 * @param exchange_pub the public key
 * @param meta meta data information about the denomination type (expirations)
 * @param master_sig master signature affirming the validity of this denomination
 */
static void
signkey_info_cb (
  void *cls,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_EXCHANGEDB_SignkeyMetaData *meta,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TEH_KeyStateHandle *ksh = cls;
  struct SigningKey *sk;
  struct GNUNET_PeerIdentity pid;

  sk = GNUNET_new (struct SigningKey);
  sk->exchange_pub = *exchange_pub;
  sk->meta = *meta;
  sk->master_sig = *master_sig;
  pid.public_key = exchange_pub->eddsa_pub;
  GNUNET_assert (
    GNUNET_OK ==
    GNUNET_CONTAINER_multipeermap_put (ksh->signkey_map,
                                       &pid,
                                       sk,
                                       GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
}


/**
 * Closure for #get_auditor_sigs.
 */
struct GetAuditorSigsContext
{
  /**
   * Where to store the matching signatures.
   */
  json_t *denom_keys;

  /**
   * Public key of the auditor to match against.
   */
  const struct TALER_AuditorPublicKeyP *auditor_pub;
};


/**
 * Extract the auditor signatures matching the auditor's public
 * key from the @a value and generate the respective JSON.
 *
 * @param cls a `struct GetAuditorSigsContext`
 * @param h_denom_pub hash of the denomination public key
 * @param value a `struct TEH_DenominationKey`
 * @return #GNUNET_OK (continue to iterate)
 */
static int
get_auditor_sigs (void *cls,
                  const struct GNUNET_HashCode *h_denom_pub,
                  void *value)
{
  struct GetAuditorSigsContext *ctx = cls;
  struct TEH_DenominationKey *dk = value;

  for (struct TEH_AuditorSignature *as = dk->as_head;
       NULL != as;
       as = as->next)
  {
    if (0 !=
        GNUNET_memcmp (ctx->auditor_pub,
                       &as->apub))
      continue;
    GNUNET_break (0 ==
                  json_array_append_new (
                    ctx->denom_keys,
                    json_pack (
                      "{s:o, s:o}",
                      "denom_pub_h",
                      GNUNET_JSON_from_data_auto (h_denom_pub),
                      "auditor_sig",
                      GNUNET_JSON_from_data_auto (&as->asig))));
  }
  return GNUNET_OK;
}


/**
 * Function called with information about the exchange's auditors.
 *
 * @param cls closure with a `struct TEH_KeyStateHandle *`
 * @param auditor_pub the public key of the auditor
 * @param auditor_url URL of the REST API of the auditor
 * @param auditor_name human readable official name of the auditor
 */
static void
auditor_info_cb (
  void *cls,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const char *auditor_url,
  const char *auditor_name)
{
  struct TEH_KeyStateHandle *ksh = cls;
  struct GetAuditorSigsContext ctx;

  ctx.denom_keys = json_array ();
  ctx.auditor_pub = auditor_pub;
  GNUNET_CONTAINER_multihashmap_iterate (ksh->denomkey_map,
                                         &get_auditor_sigs,
                                         &ctx);
  GNUNET_break (0 ==
                json_array_append_new (
                  ksh->auditors,
                  json_pack ("{s:s, s:o, s:s, s:o}",
                             "auditor_name",
                             auditor_name,
                             "auditor_pub",
                             GNUNET_JSON_from_data_auto (auditor_pub),
                             "auditor_url",
                             auditor_url,
                             "denomination_keys",
                             ctx.denom_keys)));
}


/**
 * Function called with information about the denominations
 * audited by the exchange's auditors.
 *
 * @param cls closure with a `struct TEH_KeyStateHandle *`
 * @param auditor_pub the public key of an auditor
 * @param h_denom_pub hash of a denomination key audited by this auditor
 * @param auditor_sig signature from the auditor affirming this
 */
static void
auditor_denom_cb (
  void *cls,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_AuditorSignatureP *auditor_sig)
{
  struct TEH_KeyStateHandle *ksh = cls;
  struct TEH_DenominationKey *dk;
  struct TEH_AuditorSignature *as;

  dk = GNUNET_CONTAINER_multihashmap_get (ksh->denomkey_map,
                                          h_denom_pub);
  if (NULL == dk)
  {
    /* Odd, this should be impossible as per foreign key
       constraint on 'auditor_denom_sigs'! Well, we can
       safely continue anyway, so let's just log it. */
    GNUNET_break (0);
    return;
  }
  as = GNUNET_new (struct TEH_AuditorSignature);
  as->asig = *auditor_sig;
  as->apub = *auditor_pub;
  GNUNET_CONTAINER_DLL_insert (dk->as_head,
                               dk->as_tail,
                               as);
}


/**
 * Closure for #add_sign_key_cb.
 */
struct SignKeyCtx
{
  /**
   * When does the next signing key expire. Updated.
   */
  struct GNUNET_TIME_Absolute next_sk_expire;

  /**
   * JSON array of signing keys (being created).
   */
  json_t *signkeys;
};


/**
 * Function called for all signing keys, used to build up the
 * respective JSON response.
 *
 * @param cls a `struct SignKeyCtx *` with the array to append keys to
 * @param pid the exchange public key (in type disguise)
 * @param value a `struct SigningKey`
 * @return #GNUNET_OK (continue to iterate)
 */
static int
add_sign_key_cb (void *cls,
                 const struct GNUNET_PeerIdentity *pid,
                 void *value)
{
  struct SignKeyCtx *ctx = cls;
  struct SigningKey *sk = value;

  ctx->next_sk_expire =
    GNUNET_TIME_absolute_min (ctx->next_sk_expire,
                              sk->meta.expire_sign);

  GNUNET_assert (
    0 ==
    json_array_append_new (
      ctx->signkeys,
      json_pack ("{s:o, s:o, s:o, s:o, s:o}",
                 "stamp_start",
                 GNUNET_JSON_from_time_abs (sk->meta.start),
                 "stamp_expire",
                 GNUNET_JSON_from_time_abs (sk->meta.expire_sign),
                 "stamp_end",
                 GNUNET_JSON_from_time_abs (sk->meta.expire_legal),
                 "master_sig",
                 GNUNET_JSON_from_data_auto (&sk->master_sig),
                 "key",
                 GNUNET_JSON_from_data_auto (&sk->exchange_pub))));
  return GNUNET_OK;
}


/**
 * Closure for #add_denom_key_cb.
 */
struct DenomKeyCtx
{
  /**
   * Heap for sorting active denomination keys by start time.
   */
  struct GNUNET_CONTAINER_Heap *heap;

  /**
   * JSON array of revoked denomination keys.
   */
  json_t *recoup;

  /**
   * When does the next denomination key expire. Updated.
   */
  struct GNUNET_TIME_Absolute next_dk_expire;

};


/**
 * Function called for all denomination keys, used to build up the
 * JSON list of *revoked* denomination keys and the
 * heap of non-revoked denomination keys by timeout.
 *
 * @param cls a `struct DenomKeyCtx`
 * @param h_denom_pub hash of the denomination key
 * @param value a `struct TEH_DenominationKey`
 * @return #GNUNET_OK (continue to iterate)
 */
static int
add_denom_key_cb (void *cls,
                  const struct GNUNET_HashCode *h_denom_pub,
                  void *value)
{
  struct DenomKeyCtx *dkc = cls;
  struct TEH_DenominationKey *dk = value;

  if (dk->recoup_possible)
  {
    GNUNET_assert (
      0 ==
      json_array_append_new (
        dkc->recoup,
        json_pack ("{s:o}",
                   "h_denom_pub",
                   GNUNET_JSON_from_data_auto (h_denom_pub))));
  }
  else
  {
    dkc->next_dk_expire =
      GNUNET_TIME_absolute_min (dkc->next_dk_expire,
                                dk->meta.expire_withdraw);
    (void) GNUNET_CONTAINER_heap_insert (dkc->heap,
                                         dk,
                                         dk->meta.start.abs_value_us);
  }
  return GNUNET_OK;
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
                 char date[128])
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
 * @param ksh the key state to use
 * @param[in,out] response the response to modify
 * @return #GNUNET_OK on success
 */
static int
setup_general_response_headers (const struct TEH_KeyStateHandle *ksh,
                                struct MHD_Response *response)
{
  char dat[128];

  TALER_MHD_add_global_headers (response);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_CONTENT_TYPE,
                                         "application/json"));
  get_date_string (ksh->reload_time,
                   dat);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_LAST_MODIFIED,
                                         dat));
  if (0 != ksh->next_reload.abs_value_us)
  {
    struct GNUNET_TIME_Absolute m;

    m = GNUNET_TIME_relative_to_absolute (TEH_max_keys_caching);
    m = GNUNET_TIME_absolute_min (m,
                                  ksh->next_reload);
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
 * Initialize @a krd using the given values for @a signkeys,
 * @a recoup and @a denoms.
 *
 * @param[in,out] ksh key state handle we build @a krd for
 * @param[in] denom_keys_hash hash over all the denominatoin keys in @a denoms
 * @param last_cpd timestamp to use
 * @param signkeys list of sign keys to return
 * @param recoup list of revoked keys to return
 * @param denoms list of denominations to return
 * @return #GNUNET_OK on success
 */
static int
create_krd (struct TEH_KeyStateHandle *ksh,
            const struct GNUNET_HashCode *denom_keys_hash,
            struct GNUNET_TIME_Absolute last_cpd,
            json_t *signkeys,
            json_t *recoup,
            json_t *denoms)
{
  struct KeysResponseData krd;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeSignatureP exchange_sig;
  json_t *keys;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Creating /keys at cherry pick date %s\n",
              GNUNET_STRINGS_absolute_time_to_string (last_cpd));
  /* Sign hash over denomination keys */
  {
    struct TALER_ExchangeKeySetPS ks = {
      .purpose.size = htonl (sizeof (ks)),
      .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_KEY_SET),
      .list_issue_date = GNUNET_TIME_absolute_hton (last_cpd),
      .hc = *denom_keys_hash
    };
    enum TALER_ErrorCode ec;

    if (TALER_EC_NONE !=
        (ec = TEH_keys_exchange_sign2 (ksh,
                                       &ks,
                                       &exchange_pub,
                                       &exchange_sig)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Could not create key response data: cannot sign (%s)\n",
                  TALER_ErrorCode_get_hint (ec));
      return GNUNET_SYSERR;
    }
  }

  keys = json_pack (
    "{s:s, s:o, s:o, s:O, s:O,"
    " s:O, s:O, s:o, s:o, s:o}",
    /* 1-5 */
    "version", EXCHANGE_PROTOCOL_VERSION,
    "master_public_key", GNUNET_JSON_from_data_auto (&TEH_master_public_key),
    "reserve_closing_delay", GNUNET_JSON_from_time_rel (
      TEH_reserve_closing_delay),
    "signkeys", signkeys,
    "recoup", recoup,
    /* 6-10 */
    "denoms", denoms,
    "auditors", ksh->auditors,
    "list_issue_date", GNUNET_JSON_from_time_abs (last_cpd),
    "eddsa_pub", GNUNET_JSON_from_data_auto (&exchange_pub),
    "eddsa_sig", GNUNET_JSON_from_data_auto (&exchange_sig));
  GNUNET_assert (NULL != keys);

  {
    char *keys_json;
    void *keys_jsonz;
    size_t keys_jsonz_size;
    int comp;

    /* Convert /keys response to UTF8-String */
    keys_json = json_dumps (keys,
                            JSON_INDENT (2));
    json_decref (keys);
    GNUNET_assert (NULL != keys_json);

    /* Keep copy for later compression... */
    keys_jsonz = GNUNET_strdup (keys_json);
    keys_jsonz_size = strlen (keys_json);

    /* Create uncompressed response */
    krd.response_uncompressed
      = MHD_create_response_from_buffer (keys_jsonz_size,
                                         keys_json,
                                         MHD_RESPMEM_MUST_FREE);
    GNUNET_assert (NULL != krd.response_uncompressed);
    GNUNET_assert (GNUNET_OK ==
                   setup_general_response_headers (ksh,
                                                   krd.response_uncompressed));
    /* Also compute compressed version of /keys response */
    comp = TALER_MHD_body_compress (&keys_jsonz,
                                    &keys_jsonz_size);
    krd.response_compressed
      = MHD_create_response_from_buffer (keys_jsonz_size,
                                         keys_jsonz,
                                         MHD_RESPMEM_MUST_FREE);
    GNUNET_assert (NULL != krd.response_compressed);
    /* If the response is actually compressed, set the
       respective header. */
    GNUNET_assert ( (MHD_YES != comp) ||
                    (MHD_YES ==
                     MHD_add_response_header (krd.response_compressed,
                                              MHD_HTTP_HEADER_CONTENT_ENCODING,
                                              "deflate")) );
    GNUNET_assert (GNUNET_OK ==
                   setup_general_response_headers (ksh,
                                                   krd.response_compressed));
  }
  krd.cherry_pick_date = last_cpd;
  GNUNET_array_append (ksh->krd_array,
                       ksh->krd_array_length,
                       krd);
  return GNUNET_OK;
}


/**
 * Update the "/keys" responses in @a ksh, computing the detailed replies.
 *
 * This function is to recompute all (including cherry-picked) responses we
 * might want to return, based on the state already in @a ksh.
 *
 * @param[in,out] ksh state handle to update
 * @return #GNUNET_OK on success
 */
static int
finish_keys_response (struct TEH_KeyStateHandle *ksh)
{
  json_t *recoup;
  struct SignKeyCtx sctx;
  json_t *denoms;
  struct GNUNET_TIME_Absolute last_cpd;
  struct GNUNET_CONTAINER_Heap *heap;
  struct GNUNET_HashContext *hash_context;

  sctx.signkeys = json_array ();
  sctx.next_sk_expire = GNUNET_TIME_UNIT_FOREVER_ABS;
  GNUNET_assert (NULL != sctx.signkeys);
  GNUNET_CONTAINER_multipeermap_iterate (ksh->signkey_map,
                                         &add_sign_key_cb,
                                         &sctx);
  recoup = json_array ();
  GNUNET_assert (NULL != recoup);
  heap = GNUNET_CONTAINER_heap_create (GNUNET_CONTAINER_HEAP_ORDER_MIN);
  {
    struct DenomKeyCtx dkc = {
      .recoup = recoup,
      .heap = heap,
      .next_dk_expire = GNUNET_TIME_UNIT_FOREVER_ABS,
    };

    GNUNET_CONTAINER_multihashmap_iterate (ksh->denomkey_map,
                                           &add_denom_key_cb,
                                           &dkc);
    ksh->next_reload
      = GNUNET_TIME_absolute_min (dkc.next_dk_expire,
                                  sctx.next_sk_expire);
  }
  denoms = json_array ();
  GNUNET_assert (NULL != denoms);
  last_cpd = GNUNET_TIME_UNIT_ZERO_ABS;
  hash_context = GNUNET_CRYPTO_hash_context_start ();
  {
    struct TEH_DenominationKey *dk;

    while (NULL != (dk = GNUNET_CONTAINER_heap_remove_root (heap)))
    {
      if ( (last_cpd.abs_value_us != dk->meta.start.abs_value_us) &&
           (0 != last_cpd.abs_value_us) )
      {
        struct GNUNET_HashCode hc;

        GNUNET_CRYPTO_hash_context_finish (
          GNUNET_CRYPTO_hash_context_copy (hash_context),
          &hc);
        if (GNUNET_OK !=
            create_krd (ksh,
                        &hc,
                        last_cpd,
                        sctx.signkeys,
                        recoup,
                        denoms))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                      "Failed to generate key response data for %s\n",
                      GNUNET_STRINGS_absolute_time_to_string (last_cpd));
          GNUNET_CRYPTO_hash_context_abort (hash_context);
          GNUNET_CONTAINER_heap_destroy (heap);
          json_decref (denoms);
          json_decref (sctx.signkeys);
          json_decref (recoup);
          return GNUNET_SYSERR;
        }
        last_cpd = dk->meta.start;
      }
      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       &dk->h_denom_pub,
                                       sizeof (struct GNUNET_HashCode));
      GNUNET_assert (
        0 ==
        json_array_append_new (
          denoms,
          json_pack ("{s:o, s:o, s:o, s:o, s:o,"
                     " s:o, s:o, s:o, s:o, s:o,"
                     " s:o}",
                     "master_sig",
                     GNUNET_JSON_from_data_auto (&dk->master_sig),
                     "stamp_start",
                     GNUNET_JSON_from_time_abs (dk->meta.start),
                     "stamp_expire_withdraw",
                     GNUNET_JSON_from_time_abs (dk->meta.expire_withdraw),
                     "stamp_expire_deposit",
                     GNUNET_JSON_from_time_abs (dk->meta.expire_deposit),
                     "stamp_expire_legal",
                     GNUNET_JSON_from_time_abs (dk->meta.expire_legal),
                     /* 5 entries until here */
                     "denom_pub",
                     GNUNET_JSON_from_rsa_public_key (
                       dk->denom_pub.rsa_public_key),
                     "value",
                     TALER_JSON_from_amount (&dk->meta.value),
                     "fee_withdraw",
                     TALER_JSON_from_amount (&dk->meta.fee_withdraw),
                     "fee_deposit",
                     TALER_JSON_from_amount (&dk->meta.fee_deposit),
                     "fee_refresh",
                     TALER_JSON_from_amount (&dk->meta.fee_refresh),
                     /* 10 entries until here */
                     "fee_refund",
                     TALER_JSON_from_amount (&dk->meta.fee_refund))));
    }
  }
  GNUNET_CONTAINER_heap_destroy (heap);
  {
    struct GNUNET_HashCode hc;

    GNUNET_CRYPTO_hash_context_finish (hash_context,
                                       &hc);
    if (GNUNET_OK !=
        create_krd (ksh,
                    &hc,
                    last_cpd,
                    sctx.signkeys,
                    recoup,
                    denoms))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to generate key response data for %s\n",
                  GNUNET_STRINGS_absolute_time_to_string (last_cpd));
      json_decref (denoms);
      json_decref (sctx.signkeys);
      json_decref (recoup);
      return GNUNET_SYSERR;
    }

  }
  json_decref (sctx.signkeys);
  json_decref (recoup);
  json_decref (denoms);
  ksh->management_only = false;
  return GNUNET_OK;
}


/**
 * Create a key state.
 *
 * @param[in] hs helper state to (re)use, NULL if not available
 * @param management_only if we should NOT run 'finish_keys_response()'
 *                  because we only need the state for the /management/keys API
 * @return NULL on error (i.e. failed to access database)
 */
static struct TEH_KeyStateHandle *
build_key_state (struct HelperState *hs,
                 bool management_only)
{
  struct TEH_KeyStateHandle *ksh;
  enum GNUNET_DB_QueryStatus qs;

  ksh = GNUNET_new (struct TEH_KeyStateHandle);
  ksh->reload_time = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&ksh->reload_time);
  /* We must use the key_generation from when we STARTED the process! */
  ksh->key_generation = key_generation;
  if (NULL == hs)
  {
    if (GNUNET_OK !=
        setup_key_helpers (&ksh->helpers))
    {
      GNUNET_free (ksh);
      return NULL;
    }
  }
  else
  {
    ksh->helpers = *hs;
  }
  ksh->denomkey_map = GNUNET_CONTAINER_multihashmap_create (1024,
                                                            GNUNET_YES);
  ksh->signkey_map = GNUNET_CONTAINER_multipeermap_create (32,
                                                           GNUNET_NO /* MUST be NO! */);
  ksh->auditors = json_array ();
  /* NOTE: fetches master-signed signkeys, but ALSO those that were revoked! */
  qs = TEH_plugin->iterate_denominations (TEH_plugin->cls,
                                          &denomination_info_cb,
                                          ksh);
  if (qs < 0)
  {
    GNUNET_break (0);
    destroy_key_state (ksh,
                       true);
    return NULL;
  }
  /* NOTE: ONLY fetches non-revoked AND master-signed signkeys! */
  qs = TEH_plugin->iterate_active_signkeys (TEH_plugin->cls,
                                            &signkey_info_cb,
                                            ksh);
  if (qs < 0)
  {
    GNUNET_break (0);
    destroy_key_state (ksh,
                       true);
    return NULL;
  }
  qs = TEH_plugin->iterate_active_auditors (TEH_plugin->cls,
                                            &auditor_info_cb,
                                            ksh);
  if (qs < 0)
  {
    GNUNET_break (0);
    destroy_key_state (ksh,
                       true);
    return NULL;
  }
  qs = TEH_plugin->iterate_auditor_denominations (TEH_plugin->cls,
                                                  &auditor_denom_cb,
                                                  ksh);
  if (qs < 0)
  {
    GNUNET_break (0);
    destroy_key_state (ksh,
                       true);
    return NULL;
  }
  if (management_only)
  {
    ksh->management_only = true;
    return ksh;
  }
  if (GNUNET_OK !=
      finish_keys_response (ksh))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Could not finish /keys response (likely no signing keys available yet)\n");
    destroy_key_state (ksh,
                       true);
    return NULL;
  }
  return ksh;
}


void
TEH_keys_update_states ()
{
  __sync_fetch_and_add (&key_generation,
                        1);
  TEH_resume_keys_requests (false);
}


/**
 * Obtain the key state for the current thread. Should ONLY be used
 * directly if @a management_only is true. Otherwise use #TEH_keys_get_state().
 *
 * @param management_only if we should NOT run 'finish_keys_response()'
 *                  because we only need the state for the /management/keys API
 * @return NULL on error
 */
static struct TEH_KeyStateHandle *
get_key_state (bool management_only)
{
  struct TEH_KeyStateHandle *old_ksh;
  struct TEH_KeyStateHandle *ksh;

  GNUNET_assert (key_state_available);
  old_ksh = pthread_getspecific (key_state);
  if (NULL == old_ksh)
  {
    ksh = build_key_state (NULL,
                           management_only);
    if (NULL == ksh)
      return NULL;
    if (0 != pthread_setspecific (key_state,
                                  ksh))
    {
      GNUNET_break (0);
      destroy_key_state (ksh,
                         true);
      return NULL;
    }
    return ksh;
  }
  if (old_ksh->key_generation < key_generation)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Rebuilding /keys, generation upgrade from %llu to %llu\n",
                (unsigned long long) old_ksh->key_generation,
                (unsigned long long) key_generation);
    ksh = build_key_state (&old_ksh->helpers,
                           management_only);
    if (0 != pthread_setspecific (key_state,
                                  ksh))
    {
      GNUNET_break (0);
      if (NULL != ksh)
        destroy_key_state (ksh,
                           false);
      return NULL;
    }
    if (NULL != old_ksh)
      destroy_key_state (old_ksh,
                         false);
    return ksh;
  }
  sync_key_helpers (&old_ksh->helpers);
  return old_ksh;
}


struct TEH_KeyStateHandle *
TEH_keys_get_state (void)
{
  struct TEH_KeyStateHandle *ksh;

  ksh = get_key_state (false);
  if (NULL == ksh)
    return NULL;
  if (ksh->management_only)
  {
    if (GNUNET_OK !=
        finish_keys_response (ksh))
      return NULL;
  }
  return ksh;
}


struct TEH_DenominationKey *
TEH_keys_denomination_by_hash (const struct GNUNET_HashCode *h_denom_pub,
                               enum TALER_ErrorCode *ec,
                               unsigned int *hc)
{
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    *hc = MHD_HTTP_INTERNAL_SERVER_ERROR;
    *ec = TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
    return NULL;
  }
  return TEH_keys_denomination_by_hash2 (ksh,
                                         h_denom_pub,
                                         ec,
                                         hc);
}


struct TEH_DenominationKey *
TEH_keys_denomination_by_hash2 (struct TEH_KeyStateHandle *ksh,
                                const struct GNUNET_HashCode *h_denom_pub,
                                enum TALER_ErrorCode *ec,
                                unsigned int *hc)
{
  struct TEH_DenominationKey *dk;

  dk = GNUNET_CONTAINER_multihashmap_get (ksh->denomkey_map,
                                          h_denom_pub);
  if (NULL == dk)
  {
    *hc = MHD_HTTP_NOT_FOUND;
    *ec = TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN;
    return NULL;
  }
  return dk;
}


struct TALER_DenominationSignature
TEH_keys_denomination_sign (const struct GNUNET_HashCode *h_denom_pub,
                            const void *msg,
                            size_t msg_size,
                            enum TALER_ErrorCode *ec)
{
  struct TEH_KeyStateHandle *ksh;
  struct TALER_DenominationSignature none = { NULL };

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    *ec = TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
    return none;
  }
  return TALER_CRYPTO_helper_denom_sign (ksh->helpers.dh,
                                         h_denom_pub,
                                         msg,
                                         msg_size,
                                         ec);
}


void
TEH_keys_denomination_revoke (const struct GNUNET_HashCode *h_denom_pub)
{
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    GNUNET_break (0);
    return;
  }
  TALER_CRYPTO_helper_denom_revoke (ksh->helpers.dh,
                                    h_denom_pub);
  TEH_keys_update_states ();
}


enum TALER_ErrorCode
TEH_keys_exchange_sign_ (
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    /* This *can* happen if the exchange's crypto helper is not running
       or had some bad error. */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Cannot sign request, no valid signing keys available.\n");
    return TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
  }
  return TEH_keys_exchange_sign2_ (ksh,
                                   purpose,
                                   pub,
                                   sig);
}


enum TALER_ErrorCode
TEH_keys_exchange_sign2_ (
  struct TEH_KeyStateHandle *ksh,
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  enum TALER_ErrorCode ec;

  ec = TALER_CRYPTO_helper_esign_sign_ (ksh->helpers.esh,
                                        purpose,
                                        pub,
                                        sig);
  if (TALER_EC_NONE != ec)
    return ec;
  {
    /* Here we check here that 'pub' is set to an exchange public key that is
       actually signed by the master key! Otherwise, we happily continue to
       use key material even if the offline signatures have not been made
       yet! */
    struct GNUNET_PeerIdentity pid;
    struct SigningKey *sk;

    pid.public_key = pub->eddsa_pub;
    sk = GNUNET_CONTAINER_multipeermap_get (ksh->signkey_map,
                                            &pid);
    if (NULL == sk)
    {
      /* just to be safe, zero out the (valid) signature, as the key
         should not or no longer be used */
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Cannot sign, offline key signatures are missing!\n");
      memset (sig,
              0,
              sizeof (*sig));
      return TALER_EC_EXCHANGE_SIGNKEY_HELPER_BUG;
    }
  }
  return ec;
}


void
TEH_keys_exchange_revoke (const struct TALER_ExchangePublicKeyP *exchange_pub)
{
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    GNUNET_break (0);
    return;
  }
  TALER_CRYPTO_helper_esign_revoke (ksh->helpers.esh,
                                    exchange_pub);
  TEH_keys_update_states ();
}


/**
 * Comparator used for a binary search by cherry_pick_date for @a key in the
 * `struct KeysResponseData` array. See libc's qsort() and bsearch() functions.
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


MHD_RESULT
TEH_keys_get_handler (const struct TEH_RequestHandler *rh,
                      struct MHD_Connection *connection,
                      const char *const args[])
{
  struct GNUNET_TIME_Absolute last_issue_date;

  (void) rh;
  (void) args;
  {
    const char *have_cherrypick;

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
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           have_cherrypick);
      }
      /* The following multiplication may overflow; but this should not really
         be a problem, as giving back 'older' data than what the client asks for
         (given that the client asks for data in the distant future) is not
         problematic */
      last_issue_date.abs_value_us = (uint64_t) cherrypickn * 1000000LLU;
    }
    else
    {
      last_issue_date.abs_value_us = 0LLU;
    }
  }

  {
    struct TEH_KeyStateHandle *ksh;
    const struct KeysResponseData *krd;

    ksh = TEH_keys_get_state ();
    if (NULL == ksh)
    {
      return suspend_request (connection);
    }
    krd = bsearch (&last_issue_date,
                   ksh->krd_array,
                   ksh->krd_array_length,
                   sizeof (struct KeysResponseData),
                   &krd_search_comparator);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Filtering /keys by cherry pick date %s found entry %u/%u\n",
                GNUNET_STRINGS_absolute_time_to_string (last_issue_date),
                (unsigned int) (krd - ksh->krd_array),
                ksh->krd_array_length);
    if ( (NULL == krd) &&
         (ksh->krd_array_length > 0) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Client provided invalid cherry picking timestamp %s, returning full response\n",
                  GNUNET_STRINGS_absolute_time_to_string (last_issue_date));
      krd = &ksh->krd_array[0];
    }
    if (NULL == krd)
    {
      /* Maybe client picked time stamp too far in the future?  In that case,
         "INTERNAL_SERVER_ERROR" might be misleading, could be more like a
         NOT_FOUND situation. But, OTOH, for 'sane' clients it is more likely
         to be our fault, so let's speculatively assume we are to blame ;-) *///
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                         "no key data for given timestamp");
    }
    return MHD_queue_response (connection,
                               MHD_HTTP_OK,
                               (MHD_YES == TALER_MHD_can_compress (connection))
                               ? krd->response_compressed
                               : krd->response_uncompressed);
  }
}


/**
 * Load fees and expiration times (!) for the denomination type configured in
 * section @a section_name.  Before calling this function, the `start` and
 * `validity_duration` times must already be initialized in @a meta.
 *
 * @param section_name section in the configuration to use
 * @param[in,out] meta denomination type data to complete
 * @return #GNUNET_OK on success
 */
static int
load_fees (const char *section_name,
           struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta)
{
  struct GNUNET_TIME_Relative deposit_duration;
  struct GNUNET_TIME_Relative legal_duration;

  GNUNET_assert (0 != meta->start.abs_value_us); /* caller bug */
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (TEH_cfg,
                                           section_name,
                                           "DURATION_SPEND",
                                           &deposit_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section_name,
                               "DURATION_SPEND");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (TEH_cfg,
                                           section_name,
                                           "DURATION_LEGAL",
                                           &legal_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section_name,
                               "DURATION_LEGAL");
    return GNUNET_SYSERR;
  }
  /* NOTE: this is a change from the 0.8 semantics of the configuration:
     before duration_spend was relative to 'start', not to 'expire_withdraw'.
     But doing it this way avoids the error case where previously
     duration_spend < duration_withdraw was not allowed. */
  meta->expire_deposit = GNUNET_TIME_absolute_add (meta->expire_withdraw,
                                                   deposit_duration);
  meta->expire_legal = GNUNET_TIME_absolute_add (meta->expire_deposit,
                                                 legal_duration);
  if (GNUNET_OK !=
      TALER_config_get_amount (TEH_cfg,
                               section_name,
                               "VALUE",
                               &meta->value))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "Need amount for option `%s' in section `%s'\n",
                               "VALUE",
                               section_name);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (TEH_cfg,
                               section_name,
                               "FEE_WITHDRAW",
                               &meta->fee_withdraw))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "Need amount for option `%s' in section `%s'\n",
                               "FEE_WITHDRAW",
                               section_name);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (TEH_cfg,
                               section_name,
                               "FEE_DEPOSIT",
                               &meta->fee_deposit))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "Need amount for option `%s' in section `%s'\n",
                               "FEE_DEPOSIT",
                               section_name);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (TEH_cfg,
                               section_name,
                               "FEE_REFRESH",
                               &meta->fee_refresh))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "Need amount for option `%s' in section `%s'\n",
                               "FEE_REFRESH",
                               section_name);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (TEH_cfg,
                               section_name,
                               "FEE_REFUND",
                               &meta->fee_refund))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "Need amount for option `%s' in section `%s'\n",
                               "FEE_REFUND",
                               section_name);
    return GNUNET_SYSERR;
  }
  if ( (0 != strcasecmp (TEH_currency,
                         meta->value.currency)) ||
       (0 != strcasecmp (TEH_currency,
                         meta->fee_withdraw.currency)) ||
       (0 != strcasecmp (TEH_currency,
                         meta->fee_deposit.currency)) ||
       (0 != strcasecmp (TEH_currency,
                         meta->fee_refresh.currency)) ||
       (0 != strcasecmp (TEH_currency,
                         meta->fee_refund.currency)) )
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "Need amounts in section `%s' to use currency `%s'\n",
                               section_name,
                               TEH_currency);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


int
TEH_keys_load_fees (const struct GNUNET_HashCode *h_denom_pub,
                    struct TALER_DenominationPublicKey *denom_pub,
                    struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta)
{
  struct TEH_KeyStateHandle *ksh;
  struct HelperDenomination *hd;
  int ok;

  ksh = get_key_state (true);
  if (NULL == ksh)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  hd = GNUNET_CONTAINER_multihashmap_get (ksh->helpers.denom_keys,
                                          h_denom_pub);
  meta->start = hd->start_time;
  meta->expire_withdraw = GNUNET_TIME_absolute_add (meta->start,
                                                    hd->validity_duration);
  ok = load_fees (hd->section_name,
                  meta);
  if (GNUNET_OK == ok)
    denom_pub->rsa_public_key
      = GNUNET_CRYPTO_rsa_public_key_dup (hd->denom_pub.rsa_public_key);
  else
    denom_pub->rsa_public_key
      = NULL;
  return ok;
}


int
TEH_keys_get_timing (const struct TALER_ExchangePublicKeyP *exchange_pub,
                     struct TALER_EXCHANGEDB_SignkeyMetaData *meta)
{
  struct TEH_KeyStateHandle *ksh;
  struct HelperSignkey *hsk;
  struct GNUNET_PeerIdentity pid;

  ksh = get_key_state (true);
  if (NULL == ksh)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  pid.public_key = exchange_pub->eddsa_pub;
  hsk = GNUNET_CONTAINER_multipeermap_get (ksh->helpers.esign_keys,
                                           &pid);
  meta->start = hsk->start_time;
  meta->expire_sign = GNUNET_TIME_absolute_add (meta->start,
                                                hsk->validity_duration);
  meta->expire_legal = GNUNET_TIME_absolute_add (meta->expire_sign,
                                                 signkey_legal_duration);
  return GNUNET_OK;
}


/**
 * Closure for #add_future_denomkey_cb and #add_future_signkey_cb.
 */
struct FutureBuilderContext
{
  /**
   * Our key state.
   */
  struct TEH_KeyStateHandle *ksh;

  /**
   * Array of denomination keys.
   */
  json_t *denoms;

  /**
   * Array of signing keys.
   */
  json_t *signkeys;

};


/**
 * Function called on all of our current and future denomination keys
 * known to the helper process. Filters out those that are current
 * and adds the remaining denomination keys (with their configuration
 * data) to the JSON array.
 *
 * @param cls the `struct FutureBuilderContext *`
 * @param h_denom_pub hash of the denomination public key
 * @param value a `struct HelperDenomination`
 * @return #GNUNET_OK (continue to iterate)
 */
static int
add_future_denomkey_cb (void *cls,
                        const struct GNUNET_HashCode *h_denom_pub,
                        void *value)
{
  struct FutureBuilderContext *fbc = cls;
  struct HelperDenomination *hd = value;
  struct TEH_DenominationKey *dk;
  struct TALER_EXCHANGEDB_DenominationKeyMetaData meta;

  dk = GNUNET_CONTAINER_multihashmap_get (fbc->ksh->denomkey_map,
                                          h_denom_pub);
  if (NULL != dk)
    return GNUNET_OK; /* skip: this key is already active! */
  meta.start = hd->start_time;
  meta.expire_withdraw = GNUNET_TIME_absolute_add (meta.start,
                                                   hd->validity_duration);
  if (GNUNET_OK !=
      load_fees (hd->section_name,
                 &meta))
  {
    /* Woops, couldn't determine fee structure!? */
    return GNUNET_OK;
  }
  GNUNET_assert (
    0 ==
    json_array_append_new (
      fbc->denoms,
      json_pack ("{s:o, s:o, s:o, s:o, s:o,"
                 " s:o, s:o, s:o, s:o, s:o,"
                 " s:o, s:s}",
                 /* 1-5 */
                 "value",
                 TALER_JSON_from_amount (&meta.value),
                 "stamp_start",
                 GNUNET_JSON_from_time_abs (meta.start),
                 "stamp_expire_withdraw",
                 GNUNET_JSON_from_time_abs (meta.expire_withdraw),
                 "stamp_expire_deposit",
                 GNUNET_JSON_from_time_abs (meta.expire_deposit),
                 "stamp_expire_legal",
                 GNUNET_JSON_from_time_abs (meta.expire_legal),
                 /* 6-10 */
                 "denom_pub",
                 GNUNET_JSON_from_rsa_public_key (hd->denom_pub.rsa_public_key),
                 "fee_withdraw",
                 TALER_JSON_from_amount (&meta.fee_withdraw),
                 "fee_deposit",
                 TALER_JSON_from_amount (&meta.fee_deposit),
                 "fee_refresh",
                 TALER_JSON_from_amount (&meta.fee_refresh),
                 "fee_refund",
                 TALER_JSON_from_amount (&meta.fee_refund),
                 /* 11- */
                 "denom_secmod_sig",
                 GNUNET_JSON_from_data_auto (&hd->sm_sig),
                 "section_name",
                 hd->section_name)));
  return GNUNET_OK;
}


/**
 * Function called on all of our current and future exchange signing keys
 * known to the helper process. Filters out those that are current
 * and adds the remaining signing keys (with their configuration
 * data) to the JSON array.
 *
 * @param cls the `struct FutureBuilderContext *`
 * @param pid actually the exchange public key (type disguised)
 * @param value a `struct HelperDenomination`
 * @return #GNUNET_OK (continue to iterate)
 */
static int
add_future_signkey_cb (void *cls,
                       const struct GNUNET_PeerIdentity *pid,
                       void *value)
{
  struct FutureBuilderContext *fbc = cls;
  struct HelperSignkey *hsk = value;
  struct SigningKey *sk;
  struct GNUNET_TIME_Absolute stamp_expire;
  struct GNUNET_TIME_Absolute legal_end;

  sk = GNUNET_CONTAINER_multipeermap_get (fbc->ksh->signkey_map,
                                          pid);
  if (NULL != sk)
    return GNUNET_OK; /* skip: this key is already active */
  stamp_expire = GNUNET_TIME_absolute_add (hsk->start_time,
                                           hsk->validity_duration);
  legal_end = GNUNET_TIME_absolute_add (stamp_expire,
                                        signkey_legal_duration);
  GNUNET_assert (0 ==
                 json_array_append_new (
                   fbc->signkeys,
                   json_pack ("{s:o, s:o, s:o, s:o, s:o}",
                              "key",
                              GNUNET_JSON_from_data_auto (&hsk->exchange_pub),
                              "stamp_start",
                              GNUNET_JSON_from_time_abs (hsk->start_time),
                              "stamp_expire",
                              GNUNET_JSON_from_time_abs (stamp_expire),
                              "stamp_end",
                              GNUNET_JSON_from_time_abs (legal_end),
                              "signkey_secmod_sig",
                              GNUNET_JSON_from_data_auto (&hsk->sm_sig))));
  return GNUNET_OK;
}


MHD_RESULT
TEH_keys_management_get_handler (const struct TEH_RequestHandler *rh,
                                 struct MHD_Connection *connection)
{
  struct TEH_KeyStateHandle *ksh;
  json_t *reply;

  ksh = get_key_state (true);
  if (NULL == ksh)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                       "no key state");
  }
  if (NULL == ksh->management_keys_reply)
  {
    struct FutureBuilderContext fbc = {
      .ksh = ksh,
      .denoms = json_array (),
      .signkeys = json_array ()
    };

    GNUNET_assert (NULL != fbc.denoms);
    GNUNET_assert (NULL != fbc.signkeys);
    GNUNET_CONTAINER_multihashmap_iterate (ksh->helpers.denom_keys,
                                           &add_future_denomkey_cb,
                                           &fbc);
    GNUNET_CONTAINER_multipeermap_iterate (ksh->helpers.esign_keys,
                                           &add_future_signkey_cb,
                                           &fbc);
    reply = json_pack (
      "{s:o, s:o, s:o, s:o, s:o}",
      "future_denoms",
      fbc.denoms,
      "future_signkeys",
      fbc.signkeys,
      "master_pub",
      GNUNET_JSON_from_data_auto (&TEH_master_public_key),
      "denom_secmod_public_key",
      GNUNET_JSON_from_data_auto (&denom_sm_pub),
      "signkey_secmod_public_key",
      GNUNET_JSON_from_data_auto (&esign_sm_pub));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Returning GET /management/keys response:\n");
    json_dumpf (reply,
                stderr,
                JSON_INDENT (2));
    if (NULL == reply)
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                         NULL);
    ksh->management_keys_reply = json_incref (reply);
  }
  else
  {
    reply = json_incref (ksh->management_keys_reply);
  }
  return TALER_MHD_reply_json (connection,
                               reply,
                               MHD_HTTP_OK);
}


/* end of taler-exchange-httpd_keys.c */
