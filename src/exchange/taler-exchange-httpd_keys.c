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
#define EXCHANGE_PROTOCOL_VERSION "8:0:0"


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
 * #TEH_get_key_state() is called).
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
 * Snapshot of the (coin and signing) keys (including private keys) of
 * the exchange.  There can be multiple instances of this struct, as it is
 * reference counted and only destroyed once the last user is done
 * with it.  The current instance is acquired using
 * #TEH_KS_acquire().  Using this function increases the
 * reference count.  The contents of this structure (except for the
 * reference counter) should be considered READ-ONLY until it is
 * ultimately destroyed (as there can be many concurrent users).
 */
struct TEH_KeyStateHandle
{

  /**
   * Mapping from denomination keys to denomination key issue struct.
   * Used to lookup the key by hash.
   */
  struct GNUNET_CONTAINER_MultiHashMap *denomkey_map;

  /**
   * Map from `struct TALER_ExchangePublicKey` to `TBD`
   * entries.  Based on the fact that a `struct GNUNET_PeerIdentity` is also
   * an EdDSA public key.
   */
  // FIXME: never initialized, never cleaned up!
  struct GNUNET_CONTAINER_MultiPeerMap *signkey_map;

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
 * changes, the variable MUST be volatile.  See #TEH_get_key_state() and
 * #TEH_update_key_state() for uses of this variable.
 */
static volatile uint64_t key_generation;

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

    MHD_destroy_response (kdr->response_compressed);
    MHD_destroy_response (kdr->response_uncompressed);
  }
  GNUNET_array_grow (ksh->krd_array,
                     ksh->krd_array_length);
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
  struct HelperSignkey *sk = value;

  (void) cls;
  (void) pid;
  GNUNET_free (sk);
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
  GNUNET_CONTIANER_multihashmap_iterate (hs->denom_keys,
                                         &free_denom_cb,
                                         hs);
  GNUNET_CONTAINER_multihashmap_destroy (hs->denom_keys);
  hs->denom_keys = NULL;
  GNUNET_CONTIANER_multipeermap_iterate (hs->denom_keys,
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

  check_denom_sm_pub (sm_pub);
  hd = GNUNET_CONTAINER_multihashmap_get (hs->denom_keys,
                                          h_denom_pub);
  if (NULL != hd)
  {
    /* should be just an update (revocation!), so update existing entry */
    hd->validity_duration = validity_duration;
    GNUNET_break (0 ==
                  GNUNET_memcmp (sm_sig,
                                 &hd->sm_sig));
    GNUNET_break (start_time.abs_value_us ==
                  hd->start_time.abs_value_us);
    GNUNET_break (0 ==
                  strcasecmp (section_name,
                              hd->section_name));
    return;
  }

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
  struct HelperSignkey *sk;
  struct GNUNET_PeerIdentity pid;

  check_esign_sm_pub (sm_pub);
  pid.public_key = exchange_pub->eddsa_pub;
  sk = GNUNET_CONTAINER_multipeermap_get (hs->denom_keys,
                                          &pid);
  if (NULL != sk)
  {
    /* should be just an update (revocation!), so update existing entry */
    sk->validity_duration = validity_duration;
    GNUNET_break (0 ==
                  GNUNET_memcmp (sm_sig,
                                 &sk->sm_sig));
    GNUNET_break (start_time.abs_value_us ==
                  sk->start_time.abs_value_us);
    return;
  }

  sk = GNUNET_new (struct HelperSignkey);
  sk->start_time = start_time;
  sk->validity_duration = validity_duration;
  sk->exchange_pub = *exchange_pub;
  sk->sm_sig = *sm_sig;
  GNUNET_assert (
    GNUNET_OK ==
    GNUNET_CONTAINER_multihashmap_put (
      hs->esign_keys,
      &pid,
      sk,
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
  hs->dh = TALER_CRYPTO_helper_denom_connect (cfg,
                                              &helper_denom_cb,
                                              hs);
  if (NULL == hs->dh)
  {
    destroy_key_helpers (hs);
    return GNUNET_SYSERR;
  }
  hs->esh = TALER_CRYPTO_helper_esign_connect (cfg,
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

  (void) cls;
  (void) h_denom_pub;
  GNUNET_CRYPTO_rsa_public_key_free (dk->denom_pub.rsa_public_key);
  GNUNET_free (dk);
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
 * Function called with information about the exchange's denomination keys.
 *
 * @param cls closure with a `struct TEH_KeyStateHandle *`
 * @param denom_pub public key of the denomination
 * @param issue detailed information about the denomination (value, expiration times, fees)
 */
// FIXME: want a different function with
// + revocation data
// - private key data
static void
denomination_info_cb (
  void *cls,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  struct TEH_KeyStateHandle *ksh = cls;

  // FIXME: check with helper to see if denomination is OK
  //        for use with signing!
}


/**
 * Create a key state.
 *
 * @param[in] hs helper state to (re)use, NULL if not available
 * @return NULL on error (i.e. failed to access database)
 */
static struct TEH_KeyStateHandle *
build_key_state (struct HelperState *hs)
{
  struct TEH_KeyStateHandle *ksh;
  enum GNUNET_DB_QueryStatus qs;

  ksh = GNUNET_new (struct TEH_KeyStateHandle);
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
  // FIXME: should _also_ fetch revocation status here!
  qs = TEH_plugin->iterate_denomination_info (TEH_plugin->cls,
                                              &denomination_info_cb,
                                              ksh);
  if (qs < 0)
  {
    // now what!?
  }

#if TBD
  qs = TEH_plugin->iterate_auditor_info (TEH_plugin->cls,
                                         &auditor_info_cb,
                                         ksh);
  if (qs < 0)
  {
    // now what!?
  }
#endif
  // FIXME: initialize more: fetch everything we care about from DB/CFG!
  // STILL NEEDED:
  // - revocation signatures (if any)
  // - auditor signatures
  // - master signatures???

  // FIXME: should _also_ fetch master signatures and revocation status on signing keys!


  return ksh;
}


/**
 * Update the "/keys" responses in @a ksh up to @a now into the future.
 *
 * @param[in,out] ksh state handle to update
 * @param now timestamp for when to compute the replies.
 */
static void
update_keys_response (struct TEH_KeyStateHandle *ksh,
                      struct GNUNET_TIME_Absolute now)
{
  // FIXME: update 'krd_array' here!
}


/**
 * Something changed in the database. Rebuild all key states.  This function
 * should be called if the exchange learns about a new signature from an
 * auditor or our master key.
 *
 * (We do not do so immediately, but merely signal to all threads that they
 * need to rebuild their key state upon the next call to
 * #TEH_get_key_state()).
 */
void
TEH_keys_update_states ()
{
  __sync_fetch_and_add (&key_generation,
                        1);
}


/**
 * Return the current key state for this thread.  Possibly
 * re-builds the key state if we have reason to believe
 * that something changed.
 *
 * @return NULL on error
 */
struct TEH_KeyStateHandle *
TEH_keys_get_state (void)
{
  struct TEH_KeyStateHandle *old_ksh;
  struct TEH_KeyStateHandle *ksh;

  old_ksh = pthread_getspecific (key_state);
  if (NULL == old_ksh)
  {
    ksh = build_key_state (NULL);
    if (NULL == ksh)
      return NULL;
    if (0 != pthread_setspecific (key_state,
                                  ksh))
    {
      GNUNET_break (0);
      destroy_key_state_cb (ksh,
                            true);
      return NULL;
    }
    return ksh;
  }
  if (old_ksh->key_generation < key_generation)
  {
    ksh = build_key_state (key_generation,
                           &old_ksh->helpers);
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


struct TEH_DenominationKey *
TEH_keys_denomination_by_hash (
  const struct GNUNET_HashCode *h_denom_pub,
  enum TALER_ErrorCode *ec,
  unsigned int *hc)
{
  struct TEH_KeyStateHandle *ksh;
  struct TEH_DenominationKey *dk;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    *hc = MHD_HTTP_INTERNAL_SERVER_ERROR;
    *ec = TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
    return NULL;
  }
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
TEH_keys_denomination_sign (
  const struct GNUNET_HashCode *h_denom_pub,
  const void *msg,
  size_t msg_size,
  enum TALER_ErrorCode *ec)
{
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    *ec = TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
    return;
  }
  return TALER_CRYPTO_helper_denom_sign (ksh->dh,
                                         h_denom_pub,
                                         msg,
                                         msg_size,
                                         ec);
}


void
TEH_keys_denomination_revoke (
  const struct GNUNET_HashCode *h_denom_pub)
{
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    GNUNET_break (0);
    return;
  }
  TALER_CRYPTO_helper_denom_revoke (ksh->dh,
                                    h_denom_pub);
  TEH_keys_update_states ();
}


enum TALER_ErrorCode
TEH_keys_exchange_sign_ (const struct
                         GNUNET_CRYPTO_EccSignaturePurpose *purpose,
                         struct TALER_ExchangePublicKeyP *pub,
                         struct TALER_ExchangeSignatureP *sig)
{
  struct TEH_KeyStateHandle *ksh;
  enum TALER_ErrorCode ec;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    /* This *can* happen if the exchange's crypto helper is not running
       or had some bad error. */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Cannot sign request, no valid signing keys available.\n");
    return TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
  }
  ec = TALER_CRYPTO_helper_esign_sign_ (ksh->esh,
                                        purpose,
                                        pub,
                                        sig);
  if (TALER_EC_NONE != ec)
    return ec;
  /* FIXME: check here that 'pub' is set to an exchange public
     key that is actually signed by the master key! Otherwise, we
     happily continue to use key material even if the offline
     signatures have not been made yet! */

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
  TALER_CRYPTO_helper_esign_revoke (ksh->esh,
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
TEH_handler_keys (const struct TEH_RequestHandler *rh,
                  struct MHD_Connection *connection,
                  const char *const args[])
{
  struct GNUNET_TIME_Absolute last_issue_date;
  struct GNUNET_TIME_Absolute now;

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

  now = GNUNET_TIME_absolute_get ();
  {
    const char *have_fakenow;

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
                                           MHD_HTTP_FORBIDDEN,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           have_fakenow);
      }
      if (TEH_allow_keys_timetravel)
      {
        /* The following multiplication may overflow; but this should not really
           be a problem, as giving back 'older' data than what the client asks for
           (given that the client asks for data in the distant future) is not
           problematic */
        now.abs_value_us = (uint64_t) fakenown * 1000000LLU;
      }
      else
      {
        /* Option not allowed by configuration */
        return TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_FORBIDDEN,
                                           TALER_EC_EXCHANGE_KEYS_TIMETRAVEL_FORBIDDEN,
                                           NULL);
      }
    }
  }

  {
    struct TEH_KeyStateHandle *ksh;
    const struct KeysResponseData *krd;

    ksh = TEH_keys_get_state ();
    if (NULL == ksh)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                         "no key state");
    }
    update_keys_response (ksh,
                          now);
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
      /* Maybe client picked time stamp too far in the future?  In that case,
         "INTERNAL_SERVER_ERROR" might be misleading, could be more like a
         NOT_FOUND situation. But, OTOH, for 'sane' clients it is more likely
         to be our fault, so let's speculatively assume we are to blame ;-) *///
      GNUNET_break (0);
      TEH_KS_release (key_state);
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
 * Function to call to handle requests to "/management/keys" by sending
 * back our future key material.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
 */
MHD_RESULT
TEH_keys_management_get_handler (const struct TEH_RequestHandler *rh,
                                 struct MHD_Connection *connection,
                                 const char *const args[])
{
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                       "no key state");
  }
  // FIXME: iterate over both denomination and signing keys from the helpers;
  // filter by those that are already master-signed (and thus in the 'main'
  // key state).  COMBINE *here* with 'cfg' information about the
  // value/fees/etc. of the future denomination!  => return the rest!
  return MHD_NO;
}


/* end of taler-exchange-httpd_keystate.c */
