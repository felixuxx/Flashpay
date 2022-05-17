/*
   This file is part of TALER
   Copyright (C) 2020-2022 Taler Systems SA

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
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_plugin.h"
#include "taler_extensions.h"


/**
 * How many /keys request do we hold in suspension at
 * most at any time?
 */
#define SKR_LIMIT 32


/**
 * When do we forcefully timeout a /keys request?
 */
#define KEYS_TIMEOUT GNUNET_TIME_UNIT_MINUTES


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
#define EXCHANGE_PROTOCOL_VERSION "13:0:1"


/**
 * Information about a denomination on offer by the denomination helper.
 */
struct HelperDenomination
{

  /**
   * When will the helper start to use this key for signing?
   */
  struct GNUNET_TIME_Timestamp start_time;

  /**
   * For how long will the helper allow signing? 0 if
   * the key was revoked or purged.
   */
  struct GNUNET_TIME_Relative validity_duration;

  /**
   * Hash of the full denomination key.
   */
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * Signature over this key from the security module's key.
   */
  struct TALER_SecurityModuleSignatureP sm_sig;

  /**
   * The (full) public key.
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * Details depend on the @e denom_pub.cipher type.
   */
  union
  {

    /**
     * Hash of the RSA key.
     */
    struct TALER_RsaPubHashP h_rsa;

    /**
     * Hash of the CS key.
     */
    struct TALER_CsPubHashP h_cs;

  } h_details;

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
  struct GNUNET_TIME_Timestamp start_time;

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
  struct TALER_CRYPTO_RsaDenominationHelper *rsadh;

  /**
   * Handle for the denom/CS helper.
   */
  struct TALER_CRYPTO_CsDenominationHelper *csdh;

  /**
   * Map from H(denom_pub) to `struct HelperDenomination` entries.
   */
  struct GNUNET_CONTAINER_MultiHashMap *denom_keys;

  /**
   * Map from H(rsa_pub) to `struct HelperDenomination` entries.
   */
  struct GNUNET_CONTAINER_MultiHashMap *rsa_keys;

  /**
   * Map from H(cs_pub) to `struct HelperDenomination` entries.
   */
  struct GNUNET_CONTAINER_MultiHashMap *cs_keys;

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
   * ETag for these responses.
   */
  char *etag;

  /**
   * Cherry-picking timestamp the client must have set for this
   * response to be valid.  0 if this is the "full" response.
   * The client's request must include this date or a higher one
   * for this response to be applicable.
   */
  struct GNUNET_TIME_Timestamp cherry_pick_date;

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
   * Head of DLL of our global fees.
   */
  struct TEH_GlobalFee *gf_head;

  /**
   * Tail of DLL of our global fees.
   */
  struct TEH_GlobalFee *gf_tail;

  /**
   * json array with the auditors of this exchange. Contains exactly
   * the information needed for the "auditors" field of the /keys response.
   */
  json_t *auditors;

  /**
   * json array with the global fees of this exchange. Contains exactly
   * the information needed for the "global_fees" field of the /keys response.
   */
  json_t *global_fees;

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
  struct HelperState *helpers;

  /**
   * Cached reply for a GET /management/keys request.  Used so we do not
   * re-create the reply every time.
   */
  json_t *management_keys_reply;

  /**
   * For which (global) key_generation was this data structure created?
   * Used to check when we are outdated and need to be re-generated.
   */
  uint64_t key_generation;

  /**
   * When did we initiate the key reloading?
   */
  struct GNUNET_TIME_Timestamp reload_time;

  /**
   * What is the period at which we rotate keys
   * (signing or denomination keys)?
   */
  struct GNUNET_TIME_Relative rekey_frequency;

  /**
   * When does our online signing key expire and we
   * thus need to re-generate this response?
   */
  struct GNUNET_TIME_Timestamp signature_expires;

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

  /**
   * When does this request timeout?
   */
  struct GNUNET_TIME_Absolute timeout;
};


/**
 * Stores the latest generation of our key state.
 */
static struct TEH_KeyStateHandle *key_state;

/**
 * Counter incremented whenever we have a reason to re-build the keys because
 * something external changed (in another thread).  See #TEH_keys_get_state() and
 * #TEH_keys_update_states() for uses of this variable.
 */
static uint64_t key_generation;

/**
 * Handler listening for wire updates by other exchange
 * services.
 */
static struct GNUNET_DB_EventHandler *keys_eh;

/**
 * Head of DLL of suspended /keys requests.
 */
static struct SuspendedKeysRequests *skr_head;

/**
 * Tail of DLL of suspended /keys requests.
 */
static struct SuspendedKeysRequests *skr_tail;

/**
 * Number of entries in the @e skr_head DLL.
 */
static unsigned int skr_size;

/**
 * Handle to a connection that should be force-resumed
 * with a hard error due to @a skr_size hitting
 * #SKR_LIMIT.
 */
static struct MHD_Connection *skr_connection;

/**
 * Task to force timeouts on /keys requests.
 */
static struct GNUNET_SCHEDULER_Task *keys_tt;

/**
 * For how long should a signing key be legally retained?
 * Configuration value.
 */
static struct GNUNET_TIME_Relative signkey_legal_duration;

/**
 * RSA security module public key, all zero if not known.
 */
static struct TALER_SecurityModulePublicKeyP denom_rsa_sm_pub;

/**
 * CS security module public key, all zero if not known.
 */
static struct TALER_SecurityModulePublicKeyP denom_cs_sm_pub;

/**
 * EdDSA security module public key, all zero if not known.
 */
static struct TALER_SecurityModulePublicKeyP esign_sm_pub;

/**
 * Are we shutting down?
 */
static bool terminating;


/**
 * Function called to forcefully resume suspended keys requests.
 *
 * @param cls unused, NULL
 */
static void
keys_timeout_cb (void *cls)
{
  struct SuspendedKeysRequests *skr;

  (void) cls;
  keys_tt = NULL;
  while (NULL != (skr = skr_head))
  {
    if (GNUNET_TIME_absolute_is_future (skr->timeout))
      break;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming /keys request due to timeout\n");
    GNUNET_CONTAINER_DLL_remove (skr_head,
                                 skr_tail,
                                 skr);
    MHD_resume_connection (skr->connection);
    TALER_MHD_daemon_trigger ();
    GNUNET_free (skr);
  }
  if (NULL == skr)
    return;
  keys_tt = GNUNET_SCHEDULER_add_at (skr->timeout,
                                     &keys_timeout_cb,
                                     NULL);
}


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
  if (terminating)
  {
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
  skr->timeout = GNUNET_TIME_relative_to_absolute (KEYS_TIMEOUT);
  if (NULL == keys_tt)
  {
    keys_tt = GNUNET_SCHEDULER_add_at (skr->timeout,
                                       &keys_timeout_cb,
                                       NULL);
  }
  skr_size++;
  if (skr_size > SKR_LIMIT)
  {
    skr = skr_tail;
    GNUNET_CONTAINER_DLL_remove (skr_head,
                                 skr_tail,
                                 skr);
    skr_size--;
    skr_connection = skr->connection;
    MHD_resume_connection (skr->connection);
    TALER_MHD_daemon_trigger ();
    GNUNET_free (skr);
  }
  return MHD_YES;
}


/**
 * Called on each denomination key. Checks that the key still works.
 *
 * @param cls NULL
 * @param hc denomination hash (unused)
 * @param value a `struct TEH_DenominationKey`
 * @return #GNUNET_OK
 */
static enum GNUNET_GenericReturnValue
check_dk (void *cls,
          const struct GNUNET_HashCode *hc,
          void *value)
{
  struct TEH_DenominationKey *dk = value;

  (void) cls;
  (void) hc;
  GNUNET_assert (TALER_DENOMINATION_INVALID != dk->denom_pub.cipher);
  if (TALER_DENOMINATION_RSA == dk->denom_pub.cipher)
    GNUNET_assert (GNUNET_CRYPTO_rsa_public_key_check (
                     dk->denom_pub.details.rsa_public_key));
  // nothing to do for TALER_DENOMINATION_CS
  return GNUNET_OK;
}


void
TEH_check_invariants ()
{
  struct TEH_KeyStateHandle *ksh;

  if (0 == TEH_check_invariants_flag)
    return;
  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
    return;
  GNUNET_CONTAINER_multihashmap_iterate (ksh->denomkey_map,
                                         &check_dk,
                                         NULL);
}


void
TEH_resume_keys_requests (bool do_shutdown)
{
  struct SuspendedKeysRequests *skr;

  if (do_shutdown)
    terminating = true;
  while (NULL != (skr = skr_head))
  {
    GNUNET_CONTAINER_DLL_remove (skr_head,
                                 skr_tail,
                                 skr);
    skr_size--;
    MHD_resume_connection (skr->connection);
    TALER_MHD_daemon_trigger ();
    GNUNET_free (skr);
  }
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
    GNUNET_free (krd->etag);
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
check_denom_rsa_sm_pub (const struct TALER_SecurityModulePublicKeyP *sm_pub)
{
  if (0 !=
      GNUNET_memcmp (sm_pub,
                     &denom_rsa_sm_pub))
  {
    if (! GNUNET_is_zero (&denom_rsa_sm_pub))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Our RSA security module changed its key. This must not happen.\n");
      GNUNET_assert (0);
    }
    denom_rsa_sm_pub = *sm_pub; /* TOFU ;-) */
  }
}


/**
 * Check that the given CS security module's public key is the one
 * we have pinned.  If it does not match, we die hard.
 *
 * @param sm_pub RSA security module public key to check
 */
static void
check_denom_cs_sm_pub (const struct TALER_SecurityModulePublicKeyP *sm_pub)
{
  if (0 !=
      GNUNET_memcmp (sm_pub,
                     &denom_cs_sm_pub))
  {
    if (! GNUNET_is_zero (&denom_cs_sm_pub))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Our CS security module changed its key. This must not happen.\n");
      GNUNET_assert (0);
    }
    denom_cs_sm_pub = *sm_pub; /* TOFU ;-) */
  }
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
}


/**
 * Helper function for #destroy_key_helpers to free all entries
 * in the `denom_keys` map.
 *
 * @param cls the `struct HelperDenomination`
 * @param h_denom_pub hash of the denomination public key
 * @param value the `struct HelperDenomination` to release
 * @return #GNUNET_OK (continue to iterate)
 */
static enum GNUNET_GenericReturnValue
free_denom_cb (void *cls,
               const struct GNUNET_HashCode *h_denom_pub,
               void *value)
{
  struct HelperDenomination *hd = value;

  (void) cls;
  (void) h_denom_pub;
  TALER_denom_pub_free (&hd->denom_pub);
  GNUNET_free (hd->section_name);
  GNUNET_free (hd);
  return GNUNET_OK;
}


/**
 * Helper function for #destroy_key_helpers to free all entries
 * in the `esign_keys` map.
 *
 * @param cls the `struct HelperSignkey`
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
  GNUNET_CONTAINER_multihashmap_destroy (hs->rsa_keys);
  hs->rsa_keys = NULL;
  GNUNET_CONTAINER_multihashmap_destroy (hs->cs_keys);
  hs->cs_keys = NULL;
  GNUNET_CONTAINER_multihashmap_destroy (hs->denom_keys);
  hs->denom_keys = NULL;
  GNUNET_CONTAINER_multipeermap_iterate (hs->esign_keys,
                                         &free_esign_cb,
                                         hs);
  GNUNET_CONTAINER_multipeermap_destroy (hs->esign_keys);
  hs->esign_keys = NULL;
  if (NULL != hs->rsadh)
  {
    TALER_CRYPTO_helper_rsa_disconnect (hs->rsadh);
    hs->rsadh = NULL;
  }
  if (NULL != hs->csdh)
  {
    TALER_CRYPTO_helper_cs_disconnect (hs->csdh);
    hs->csdh = NULL;
  }
  if (NULL != hs->esh)
  {
    TALER_CRYPTO_helper_esign_disconnect (hs->esh);
    hs->esh = NULL;
  }
}


/**
 * Looks up the AGE_RESTRICTED setting for a denomination in the config and
 * returns the age restriction (mask) accordingly.
 *
 * @param section_name Section in the configuration for the particular
 *    denomination.
 */
static struct TALER_AgeMask
load_age_mask (const char*section_name)
{
  static const struct TALER_AgeMask null_mask = {0};
  struct TALER_AgeMask age_mask = TALER_extensions_age_restriction_ageMask ();

  if (age_mask.bits == 0)
    return null_mask;

  if (GNUNET_OK != (GNUNET_CONFIGURATION_have_value (
                      TEH_cfg,
                      section_name,
                      "AGE_RESTRICTED")))
    return null_mask;

  {
    enum GNUNET_GenericReturnValue ret;

    if (GNUNET_SYSERR ==
        (ret = GNUNET_CONFIGURATION_get_value_yesno (TEH_cfg,
                                                     section_name,
                                                     "AGE_RESTRICTED")))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section_name,
                                 "AGE_RESTRICTED",
                                 "Value must be YES or NO\n");
      return null_mask;
    }
  }
  return age_mask;
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
 * @param h_rsa hash of the @a denom_pub that is available (or was purged)
 * @param denom_pub the public key itself, NULL if the key was revoked or purged
 * @param sm_pub public key of the security module, NULL if the key was revoked or purged
 * @param sm_sig signature from the security module, NULL if the key was revoked or purged
 *               The signature was already verified against @a sm_pub.
 */
static void
helper_rsa_cb (
  void *cls,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Relative validity_duration,
  const struct TALER_RsaPubHashP *h_rsa,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_SecurityModulePublicKeyP *sm_pub,
  const struct TALER_SecurityModuleSignatureP *sm_sig)
{
  struct HelperState *hs = cls;
  struct HelperDenomination *hd;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "RSA helper announces key %s for denomination type %s with validity %s\n",
              GNUNET_h2s (&h_rsa->hash),
              section_name,
              GNUNET_STRINGS_relative_time_to_string (validity_duration,
                                                      GNUNET_NO));
  key_generation++;
  TEH_resume_keys_requests (false);
  hd = GNUNET_CONTAINER_multihashmap_get (hs->rsa_keys,
                                          &h_rsa->hash);
  if (NULL != hd)
  {
    /* should be just an update (revocation!), so update existing entry */
    hd->validity_duration = validity_duration;
    return;
  }
  GNUNET_assert (NULL != sm_pub);
  check_denom_rsa_sm_pub (sm_pub);
  hd = GNUNET_new (struct HelperDenomination);
  hd->start_time = start_time;
  hd->validity_duration = validity_duration;
  hd->h_details.h_rsa = *h_rsa;
  hd->sm_sig = *sm_sig;
  GNUNET_assert (TALER_DENOMINATION_RSA == denom_pub->cipher);
  TALER_denom_pub_deep_copy (&hd->denom_pub,
                             denom_pub);
  GNUNET_assert (TALER_DENOMINATION_RSA == hd->denom_pub.cipher);
  /* load the age mask for the denomination, if applicable */
  hd->denom_pub.age_mask = load_age_mask (section_name);
  TALER_denom_pub_hash (&hd->denom_pub,
                        &hd->h_denom_pub);
  hd->section_name = GNUNET_strdup (section_name);
  GNUNET_assert (
    GNUNET_OK ==
    GNUNET_CONTAINER_multihashmap_put (
      hs->denom_keys,
      &hd->h_denom_pub.hash,
      hd,
      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  GNUNET_assert (
    GNUNET_OK ==
    GNUNET_CONTAINER_multihashmap_put (
      hs->rsa_keys,
      &hd->h_details.h_rsa.hash,
      hd,
      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
}


/**
 * Function called with information about available CS keys for signing. Usually
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
 * @param h_cs hash of the @a denom_pub that is available (or was purged)
 * @param denom_pub the public key itself, NULL if the key was revoked or purged
 * @param sm_pub public key of the security module, NULL if the key was revoked or purged
 * @param sm_sig signature from the security module, NULL if the key was revoked or purged
 *               The signature was already verified against @a sm_pub.
 */
static void
helper_cs_cb (
  void *cls,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Relative validity_duration,
  const struct TALER_CsPubHashP *h_cs,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_SecurityModulePublicKeyP *sm_pub,
  const struct TALER_SecurityModuleSignatureP *sm_sig)
{
  struct HelperState *hs = cls;
  struct HelperDenomination *hd;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "CS helper announces key %s for denomination type %s with validity %s\n",
              GNUNET_h2s (&h_cs->hash),
              section_name,
              GNUNET_STRINGS_relative_time_to_string (validity_duration,
                                                      GNUNET_NO));
  key_generation++;
  TEH_resume_keys_requests (false);
  hd = GNUNET_CONTAINER_multihashmap_get (hs->cs_keys,
                                          &h_cs->hash);
  if (NULL != hd)
  {
    /* should be just an update (revocation!), so update existing entry */
    hd->validity_duration = validity_duration;
    return;
  }
  GNUNET_assert (NULL != sm_pub);
  check_denom_cs_sm_pub (sm_pub);
  hd = GNUNET_new (struct HelperDenomination);
  hd->start_time = start_time;
  hd->validity_duration = validity_duration;
  hd->h_details.h_cs = *h_cs;
  hd->sm_sig = *sm_sig;
  GNUNET_assert (TALER_DENOMINATION_CS == denom_pub->cipher);
  TALER_denom_pub_deep_copy (&hd->denom_pub,
                             denom_pub);
  /* load the age mask for the denomination, if applicable */
  hd->denom_pub.age_mask = load_age_mask (section_name);
  TALER_denom_pub_hash (&hd->denom_pub,
                        &hd->h_denom_pub);
  hd->section_name = GNUNET_strdup (section_name);
  GNUNET_assert (
    GNUNET_OK ==
    GNUNET_CONTAINER_multihashmap_put (
      hs->denom_keys,
      &hd->h_denom_pub.hash,
      hd,
      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  GNUNET_assert (
    GNUNET_OK ==
    GNUNET_CONTAINER_multihashmap_put (
      hs->cs_keys,
      &hd->h_details.h_cs.hash,
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
  struct GNUNET_TIME_Timestamp start_time,
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
  key_generation++;
  TEH_resume_keys_requests (false);
  pid.public_key = exchange_pub->eddsa_pub;
  hsk = GNUNET_CONTAINER_multipeermap_get (hs->esign_keys,
                                           &pid);
  if (NULL != hsk)
  {
    /* should be just an update (revocation!), so update existing entry */
    hsk->validity_duration = validity_duration;
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
static enum GNUNET_GenericReturnValue
setup_key_helpers (struct HelperState *hs)
{
  hs->denom_keys
    = GNUNET_CONTAINER_multihashmap_create (1024,
                                            GNUNET_YES);
  hs->rsa_keys
    = GNUNET_CONTAINER_multihashmap_create (1024,
                                            GNUNET_YES);
  hs->cs_keys
    = GNUNET_CONTAINER_multihashmap_create (1024,
                                            GNUNET_YES);
  hs->esign_keys
    = GNUNET_CONTAINER_multipeermap_create (32,
                                            GNUNET_NO /* MUST BE NO! */);
  hs->rsadh = TALER_CRYPTO_helper_rsa_connect (TEH_cfg,
                                               &helper_rsa_cb,
                                               hs);
  if (NULL == hs->rsadh)
  {
    destroy_key_helpers (hs);
    return GNUNET_SYSERR;
  }
  hs->csdh = TALER_CRYPTO_helper_cs_connect (TEH_cfg,
                                             &helper_cs_cb,
                                             hs);
  if (NULL == hs->csdh)
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
  TALER_CRYPTO_helper_rsa_poll (hs->rsadh);
  TALER_CRYPTO_helper_cs_poll (hs->csdh);
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
static enum GNUNET_GenericReturnValue
clear_denomination_cb (void *cls,
                       const struct GNUNET_HashCode *h_denom_pub,
                       void *value)
{
  struct TEH_DenominationKey *dk = value;
  struct TEH_AuditorSignature *as;

  (void) cls;
  (void) h_denom_pub;
  TALER_denom_pub_free (&dk->denom_pub);
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
static enum GNUNET_GenericReturnValue
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
  struct TEH_GlobalFee *gf;

  clear_response_cache (ksh);
  while (NULL != (gf = ksh->gf_head))
  {
    GNUNET_CONTAINER_DLL_remove (ksh->gf_head,
                                 ksh->gf_tail,
                                 gf);
    GNUNET_free (gf);
  }
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
  json_decref (ksh->global_fees);
  ksh->global_fees = NULL;
  if (free_helper)
  {
    destroy_key_helpers (ksh->helpers);
    GNUNET_free (ksh->helpers);
  }
  if (NULL != ksh->management_keys_reply)
  {
    json_decref (ksh->management_keys_reply);
    ksh->management_keys_reply = NULL;
  }
  GNUNET_free (ksh);
}


/**
 * Function called whenever another exchange process has updated
 * the keys data in the database.
 *
 * @param cls NULL
 * @param extra unused
 * @param extra_size number of bytes in @a extra unused
 */
static void
keys_update_event_cb (void *cls,
                      const void *extra,
                      size_t extra_size)
{
  (void) cls;
  (void) extra;
  (void) extra_size;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received /keys update event\n");
  TEH_check_invariants ();
  key_generation++;
  TEH_resume_keys_requests (false);
  TEH_check_invariants ();
}


enum GNUNET_GenericReturnValue
TEH_keys_init ()
{
  struct GNUNET_DB_EventHeaderP es = {
    .size = htons (sizeof (es)),
    .type = htons (TALER_DBEVENT_EXCHANGE_KEYS_UPDATED),
  };

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
  keys_eh = TEH_plugin->event_listen (TEH_plugin->cls,
                                      GNUNET_TIME_UNIT_FOREVER_REL,
                                      &es,
                                      &keys_update_event_cb,
                                      NULL);
  if (NULL == keys_eh)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Fully clean up our state.
 */
void
TEH_keys_finished ()
{
  if (NULL != keys_tt)
  {
    GNUNET_SCHEDULER_cancel (keys_tt);
    keys_tt = NULL;
  }
  if (NULL != key_state)
    destroy_key_state (key_state,
                       true);
  if (NULL != keys_eh)
  {
    TEH_plugin->event_listen_cancel (TEH_plugin->cls,
                                     keys_eh);
    keys_eh = NULL;
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
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta,
  const struct TALER_MasterSignatureP *master_sig,
  bool recoup_possible)
{
  struct TEH_KeyStateHandle *ksh = cls;
  struct TEH_DenominationKey *dk;

  GNUNET_assert (TALER_DENOMINATION_INVALID != denom_pub->cipher);
  if (GNUNET_TIME_absolute_is_zero (meta->start.abs_time) ||
      GNUNET_TIME_absolute_is_zero (meta->expire_withdraw.abs_time) ||
      GNUNET_TIME_absolute_is_zero (meta->expire_deposit.abs_time) ||
      GNUNET_TIME_absolute_is_zero (meta->expire_legal.abs_time) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Database contains invalid denomination key %s\n",
                GNUNET_h2s (&h_denom_pub->hash));
    return;
  }
  dk = GNUNET_new (struct TEH_DenominationKey);
  TALER_denom_pub_deep_copy (&dk->denom_pub,
                             denom_pub);
  dk->h_denom_pub = *h_denom_pub;
  dk->meta = *meta;
  dk->master_sig = *master_sig;
  dk->recoup_possible = recoup_possible;
  dk->denom_pub.age_mask = meta->age_mask;

  GNUNET_assert (
    GNUNET_OK ==
    GNUNET_CONTAINER_multihashmap_put (ksh->denomkey_map,
                                       &dk->h_denom_pub.hash,
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
static enum GNUNET_GenericReturnValue
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
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_data_auto ("denom_pub_h",
                                                  h_denom_pub),
                      GNUNET_JSON_pack_data_auto ("auditor_sig",
                                                  &as->asig))));
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
  GNUNET_assert (NULL != ctx.denom_keys);
  ctx.auditor_pub = auditor_pub;
  GNUNET_CONTAINER_multihashmap_iterate (ksh->denomkey_map,
                                         &get_auditor_sigs,
                                         &ctx);
  GNUNET_break (0 ==
                json_array_append_new (
                  ksh->auditors,
                  GNUNET_JSON_PACK (
                    GNUNET_JSON_pack_string ("auditor_name",
                                             auditor_name),
                    GNUNET_JSON_pack_data_auto ("auditor_pub",
                                                auditor_pub),
                    GNUNET_JSON_pack_string ("auditor_url",
                                             auditor_url),
                    GNUNET_JSON_pack_array_steal ("denomination_keys",
                                                  ctx.denom_keys))));
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
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AuditorSignatureP *auditor_sig)
{
  struct TEH_KeyStateHandle *ksh = cls;
  struct TEH_DenominationKey *dk;
  struct TEH_AuditorSignature *as;

  dk = GNUNET_CONTAINER_multihashmap_get (ksh->denomkey_map,
                                          &h_denom_pub->hash);
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
   * What is the current rotation frequency for signing keys. Updated.
   */
  struct GNUNET_TIME_Relative min_sk_frequency;

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
static enum GNUNET_GenericReturnValue
add_sign_key_cb (void *cls,
                 const struct GNUNET_PeerIdentity *pid,
                 void *value)
{
  struct SignKeyCtx *ctx = cls;
  struct SigningKey *sk = value;

  (void) pid;
  if (GNUNET_TIME_absolute_is_future (sk->meta.expire_sign.abs_time))
  {
    ctx->min_sk_frequency =
      GNUNET_TIME_relative_min (ctx->min_sk_frequency,
                                GNUNET_TIME_absolute_get_difference (
                                  sk->meta.start.abs_time,
                                  sk->meta.expire_sign.abs_time));
  }
  GNUNET_assert (
    0 ==
    json_array_append_new (
      ctx->signkeys,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_timestamp ("stamp_start",
                                    sk->meta.start),
        GNUNET_JSON_pack_timestamp ("stamp_expire",
                                    sk->meta.expire_sign),
        GNUNET_JSON_pack_timestamp ("stamp_end",
                                    sk->meta.expire_legal),
        GNUNET_JSON_pack_data_auto ("master_sig",
                                    &sk->master_sig),
        GNUNET_JSON_pack_data_auto ("key",
                                    &sk->exchange_pub))));
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
   * What is the minimum key rotation frequency of
   * valid denomination keys?
   */
  struct GNUNET_TIME_Relative min_dk_frequency;
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
static enum GNUNET_GenericReturnValue
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
        GNUNET_JSON_PACK (
          GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                      h_denom_pub))));
  }
  else
  {
    if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
    {
      dkc->min_dk_frequency =
        GNUNET_TIME_relative_min (dkc->min_dk_frequency,
                                  GNUNET_TIME_absolute_get_difference (
                                    dk->meta.start.abs_time,
                                    dk->meta.expire_withdraw.abs_time));
    }
    (void) GNUNET_CONTAINER_heap_insert (dkc->heap,
                                         dk,
                                         dk->meta.start.abs_time.abs_value_us);
  }
  return GNUNET_OK;
}


/**
 * Add the headers we want to set for every /keys response.
 *
 * @param ksh the key state to use
 * @param[in,out] response the response to modify
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
setup_general_response_headers (struct TEH_KeyStateHandle *ksh,
                                struct MHD_Response *response)
{
  char dat[128];

  TALER_MHD_add_global_headers (response);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_CONTENT_TYPE,
                                         "application/json"));
  TALER_MHD_get_date_string (ksh->reload_time.abs_time,
                             dat);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_LAST_MODIFIED,
                                         dat));
  if (! GNUNET_TIME_relative_is_zero (ksh->rekey_frequency))
  {
    struct GNUNET_TIME_Relative r;
    struct GNUNET_TIME_Absolute a;
    struct GNUNET_TIME_Timestamp m;

    r = GNUNET_TIME_relative_min (TEH_max_keys_caching,
                                  ksh->rekey_frequency);
    a = GNUNET_TIME_relative_to_absolute (r);
    m = GNUNET_TIME_absolute_to_timestamp (a);
    TALER_MHD_get_date_string (m.abs_time,
                               dat);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Setting /keys 'Expires' header to '%s'\n",
                dat);
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (response,
                                           MHD_HTTP_HEADER_EXPIRES,
                                           dat));
    ksh->signature_expires
      = GNUNET_TIME_timestamp_min (m,
                                   ksh->signature_expires);
  }
  /* Set cache control headers: our response varies depending on these headers */
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_VARY,
                                         MHD_HTTP_HEADER_ACCEPT_ENCODING));
  /* Information is always public, revalidate after 1 hour */
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_CACHE_CONTROL,
                                         "public,max-age=3600"));
  return GNUNET_OK;
}


/**
 * Initialize @a krd using the given values for @a signkeys,
 * @a recoup and @a denoms.
 *
 * @param[in,out] ksh key state handle we build @a krd for
 * @param[in] denom_keys_hash hash over all the denominatoin keys in @a denoms and age_restricted_denoms
 * @param last_cpd timestamp to use
 * @param signkeys list of sign keys to return
 * @param recoup list of revoked keys to return
 * @param denoms list of denominations to return
 * @param age_restricted_denoms list of age restricted denominations to return, can be NULL
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
create_krd (struct TEH_KeyStateHandle *ksh,
            const struct GNUNET_HashCode *denom_keys_hash,
            struct GNUNET_TIME_Timestamp last_cpd,
            json_t *signkeys,
            json_t *recoup,
            json_t *denoms,
            json_t *age_restricted_denoms)
{
  struct KeysResponseData krd;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeSignatureP exchange_sig;
  json_t *keys;

  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (last_cpd.abs_time));
  GNUNET_assert (NULL != signkeys);
  GNUNET_assert (NULL != recoup);
  GNUNET_assert (NULL != denoms);
  GNUNET_assert (NULL != ksh->auditors);
  GNUNET_assert (NULL != TEH_currency);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Creating /keys at cherry pick date %s\n",
              GNUNET_TIME_timestamp2s (last_cpd));
  /* Sign hash over denomination keys */
  {
    enum TALER_ErrorCode ec;

    if (TALER_EC_NONE !=
        (ec =
           TALER_exchange_online_key_set_sign (
             &TEH_keys_exchange_sign2_,
             ksh,
             last_cpd,
             denom_keys_hash,
             &exchange_pub,
             &exchange_sig)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Could not create key response data: cannot sign (%s)\n",
                  TALER_ErrorCode_get_hint (ec));
      return GNUNET_SYSERR;
    }
  }
  {
    const struct SigningKey *sk;

    sk = GNUNET_CONTAINER_multipeermap_get (
      ksh->signkey_map,
      (const struct GNUNET_PeerIdentity *) &exchange_pub);
    ksh->signature_expires = GNUNET_TIME_timestamp_min (sk->meta.expire_sign,
                                                        ksh->signature_expires);
  }

  keys = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("version",
                             EXCHANGE_PROTOCOL_VERSION),
    GNUNET_JSON_pack_string ("currency",
                             TEH_currency),
    GNUNET_JSON_pack_data_auto ("master_public_key",
                                &TEH_master_public_key),
    GNUNET_JSON_pack_time_rel ("reserve_closing_delay",
                               TEH_reserve_closing_delay),
    GNUNET_JSON_pack_array_incref ("signkeys",
                                   signkeys),
    GNUNET_JSON_pack_array_incref ("recoup",
                                   recoup),
    GNUNET_JSON_pack_array_incref ("denoms",
                                   denoms),
    GNUNET_JSON_pack_array_incref ("auditors",
                                   ksh->auditors),
    GNUNET_JSON_pack_array_incref ("global_fees",
                                   ksh->global_fees),
    GNUNET_JSON_pack_timestamp ("list_issue_date",
                                last_cpd),
    GNUNET_JSON_pack_data_auto ("eddsa_pub",
                                &exchange_pub),
    GNUNET_JSON_pack_data_auto ("eddsa_sig",
                                &exchange_sig));
  GNUNET_assert (NULL != keys);

  /* Set wallet limit if KYC is configured */
  if ( (TEH_KYC_NONE != TEH_kyc_config.mode) &&
       (GNUNET_OK ==
        TALER_amount_is_valid (&TEH_kyc_config.wallet_balance_limit)) )
  {
    GNUNET_assert (
      0 ==
      json_object_set_new (
        keys,
        "wallet_balance_limit_without_kyc",
        TALER_JSON_from_amount (
          &TEH_kyc_config.wallet_balance_limit)));
  }

  /* Signal support for the configured, enabled extensions. */
  {
    json_t *extensions = json_object ();
    bool has_extensions = false;
    bool age_restriction_enabled = false;

    /* Fill in the configurations of the enabled extensions */
    for (const struct TALER_Extension *extension = TALER_extensions_get_head ();
         NULL != extension;
         extension = extension->next)
    {
      json_t *ext;
      json_t *config_json;
      int r;

      /* skip if not configured == disabled */
      if (NULL == extension->config ||
          NULL == extension->config_json)
        continue;

      /* flag our findings so far */
      has_extensions = true;
      age_restriction_enabled = (extension->type ==
                                 TALER_Extension_AgeRestriction);

      GNUNET_assert (NULL != extension->config_json);

      config_json = json_copy (extension->config_json);
      GNUNET_assert (NULL != config_json);

      ext = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_bool ("critical",
                               extension->critical),
        GNUNET_JSON_pack_string ("version",
                                 extension->version),
        GNUNET_JSON_pack_object_steal ("config",
                                       config_json)
        );
      GNUNET_assert (NULL != ext);

      r = json_object_set_new (
        extensions,
        extension->name,
        ext);
      GNUNET_assert (0 == r);
    }

    /* Update the keys object with the extensions */
    if (has_extensions)
    {
      json_t *sig;
      int r;

      r = json_object_set (
        keys,
        "extensions",
        extensions);
      GNUNET_assert (0 == r);

      /* add extensions_sig */
      sig = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("extensions_sig",
                                    &TEH_extensions_sig));

      /* update the keys object with extensions_sig */
      r = json_object_update (keys, sig);
      GNUNET_assert (0 == r);
    }
    else
    {
      json_decref (extensions);
    }

    // Special case for age restrictions: if enabled, provide the list of
    // age-restricted denominations.
    if (age_restriction_enabled &&
        NULL != age_restricted_denoms)
    {
      GNUNET_assert (
        0 ==
        json_object_set (
          keys,
          "age_restricted_denoms",
          age_restricted_denoms));
    }

  }


  {
    char *keys_json;
    void *keys_jsonz;
    size_t keys_jsonz_size;
    int comp;
    char etag[sizeof (struct GNUNET_HashCode) * 2];

    /* Convert /keys response to UTF8-String */
    keys_json = json_dumps (keys,
                            JSON_INDENT (2));
    json_decref (keys);
    GNUNET_assert (NULL != keys_json);

    /* Keep copy for later compression... */
    keys_jsonz = GNUNET_strdup (keys_json);
    keys_jsonz_size = strlen (keys_json);

    /* hash to compute etag */
    {
      struct GNUNET_HashCode ehash;
      char *end;

      GNUNET_CRYPTO_hash (keys_jsonz,
                          keys_jsonz_size,
                          &ehash);
      end = GNUNET_STRINGS_data_to_string (&ehash,
                                           sizeof (ehash),
                                           etag,
                                           sizeof (etag));
      *end = '\0';
    }

    /* Create uncompressed response */
    krd.response_uncompressed
      = MHD_create_response_from_buffer (keys_jsonz_size,
                                         keys_json,
                                         MHD_RESPMEM_MUST_FREE);
    GNUNET_assert (NULL != krd.response_uncompressed);
    GNUNET_assert (GNUNET_OK ==
                   setup_general_response_headers (ksh,
                                                   krd.response_uncompressed));
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (krd.response_uncompressed,
                                           MHD_HTTP_HEADER_ETAG,
                                           etag));
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
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (krd.response_compressed,
                                           MHD_HTTP_HEADER_ETAG,
                                           etag));
    krd.etag = GNUNET_strdup (etag);
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
static enum GNUNET_GenericReturnValue
finish_keys_response (struct TEH_KeyStateHandle *ksh)
{
  json_t *recoup;
  struct SignKeyCtx sctx;
  json_t *denoms = NULL;
  json_t *age_restricted_denoms = NULL;
  struct GNUNET_TIME_Timestamp last_cpd;
  struct GNUNET_CONTAINER_Heap *heap;
  struct GNUNET_HashContext *hash_context = NULL;
  struct GNUNET_HashContext *hash_context_restricted = NULL;
  bool have_age_restricted_denoms = false;

  sctx.signkeys = json_array ();
  GNUNET_assert (NULL != sctx.signkeys);
  sctx.min_sk_frequency = GNUNET_TIME_UNIT_FOREVER_REL;
  GNUNET_CONTAINER_multipeermap_iterate (ksh->signkey_map,
                                         &add_sign_key_cb,
                                         &sctx);
  recoup = json_array ();
  GNUNET_assert (NULL != recoup);
  heap = GNUNET_CONTAINER_heap_create (GNUNET_CONTAINER_HEAP_ORDER_MAX);
  {
    struct DenomKeyCtx dkc = {
      .recoup = recoup,
      .heap = heap,
      .min_dk_frequency = GNUNET_TIME_UNIT_FOREVER_REL,
    };

    GNUNET_CONTAINER_multihashmap_iterate (ksh->denomkey_map,
                                           &add_denom_key_cb,
                                           &dkc);
    ksh->rekey_frequency
      = GNUNET_TIME_relative_min (dkc.min_dk_frequency,
                                  sctx.min_sk_frequency);
  }

  denoms = json_array ();
  GNUNET_assert (NULL != denoms);
  hash_context = GNUNET_CRYPTO_hash_context_start ();

  /* If age restriction is enabled, initialize the array of age restricted
   denoms  and prepare a hash for them, separate from the others.  We will join
   those hashes afterwards.*/
  if (0)
  {
    age_restricted_denoms = json_array ();
    GNUNET_assert (NULL != age_restricted_denoms);
    hash_context_restricted = GNUNET_CRYPTO_hash_context_start ();
  }

  last_cpd = GNUNET_TIME_UNIT_ZERO_TS;

  {
    struct TEH_DenominationKey *dk;

    /* heap = min heap, sorted by start time */
    while (NULL != (dk = GNUNET_CONTAINER_heap_remove_root (heap)))
    {
      if (GNUNET_TIME_timestamp_cmp (last_cpd,
                                     !=,
                                     dk->meta.start) &&
          (! GNUNET_TIME_absolute_is_zero (last_cpd.abs_time)) )
      {
        struct GNUNET_HashCode hc;

        /* FIXME-oec: Do we need to take hash_context_restricted into account
         * in this if-branch!?  Current tests suggests: no, (they don't fail).
         * But something seems to be odd about only finishing hash_context.
         */

        GNUNET_CRYPTO_hash_context_finish (
          GNUNET_CRYPTO_hash_context_copy (hash_context),
          &hc);
        if (GNUNET_OK !=
            create_krd (ksh,
                        &hc,
                        last_cpd,
                        sctx.signkeys,
                        recoup,
                        denoms,
                        age_restricted_denoms))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                      "Failed to generate key response data for %s\n",
                      GNUNET_TIME_timestamp2s (last_cpd));
          GNUNET_CRYPTO_hash_context_abort (hash_context);
          /* drain heap before destroying it */
          while (NULL != (dk = GNUNET_CONTAINER_heap_remove_root (heap)))
            /* intentionally empty */;
          GNUNET_CONTAINER_heap_destroy (heap);
          json_decref (denoms);
          if (NULL != age_restricted_denoms)
            json_decref (age_restricted_denoms);
          json_decref (sctx.signkeys);
          json_decref (recoup);
          return GNUNET_SYSERR;
        }
      }

      last_cpd = dk->meta.start;

      {
        json_t *denom;
        json_t *array;
        struct GNUNET_HashContext *hc;


        denom =
          GNUNET_JSON_PACK (
            GNUNET_JSON_pack_data_auto ("master_sig",
                                        &dk->master_sig),
            GNUNET_JSON_pack_timestamp ("stamp_start",
                                        dk->meta.start),
            GNUNET_JSON_pack_timestamp ("stamp_expire_withdraw",
                                        dk->meta.expire_withdraw),
            GNUNET_JSON_pack_timestamp ("stamp_expire_deposit",
                                        dk->meta.expire_deposit),
            GNUNET_JSON_pack_timestamp ("stamp_expire_legal",
                                        dk->meta.expire_legal),
            TALER_JSON_pack_denom_pub ("denom_pub",
                                       &dk->denom_pub),
            TALER_JSON_pack_amount ("value",
                                    &dk->meta.value),
            TALER_JSON_PACK_DENOM_FEES ("fee",
                                        &dk->meta.fees));

        /* Put the denom into the correct array depending on the settings and
         * the properties of the denomination.  Also, we build up the right
         * hash for the corresponding array. */
        if (0 &&
            (0 != dk->denom_pub.age_mask.bits))
        {
          have_age_restricted_denoms = true;
          array = age_restricted_denoms;
          hc = hash_context_restricted;
        }
        else
        {
          array = denoms;
          hc = hash_context;
        }

        GNUNET_CRYPTO_hash_context_read (hc,
                                         &dk->h_denom_pub,
                                         sizeof (struct GNUNET_HashCode));

        GNUNET_assert (
          0 ==
          json_array_append_new (
            array,
            denom));
      }
    }
  }

  GNUNET_CONTAINER_heap_destroy (heap);
  if (! GNUNET_TIME_absolute_is_zero (last_cpd.abs_time))
  {
    struct GNUNET_HashCode hc;

    /* If age restriction is active and we had at least one denomination of
     * that sort, we simply add the hash of all age restricted denominations at
     * the end of the others. */
    if (0 && have_age_restricted_denoms)
    {
      struct GNUNET_HashCode hcr;
      GNUNET_CRYPTO_hash_context_finish (hash_context_restricted, &hcr);
      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       &hcr,
                                       sizeof (struct GNUNET_HashCode));
    }

    GNUNET_CRYPTO_hash_context_finish (hash_context,
                                       &hc);

    if (GNUNET_OK !=
        create_krd (ksh,
                    &hc,
                    last_cpd,
                    sctx.signkeys,
                    recoup,
                    denoms,
                    age_restricted_denoms))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to generate key response data for %s\n",
                  GNUNET_TIME_timestamp2s (last_cpd));
      json_decref (denoms);
      if (0 && NULL != age_restricted_denoms)
        json_decref (age_restricted_denoms);
      json_decref (sctx.signkeys);
      json_decref (recoup);
      return GNUNET_SYSERR;
    }
    ksh->management_only = false;
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "No denomination keys available. Refusing to generate /keys response.\n");
    GNUNET_CRYPTO_hash_context_abort (hash_context);
  }
  json_decref (sctx.signkeys);
  json_decref (recoup);
  json_decref (denoms);
  if (NULL != age_restricted_denoms)
    json_decref (age_restricted_denoms);
  return GNUNET_OK;
}


/**
 * Called with information about global fees.
 *
 * @param cls `struct TEH_KeyStateHandle *` we are building
 * @param fees the global fees we charge
 * @param purse_timeout when do purses time out
 * @param kyc_timeout when do reserves without KYC time out
 * @param history_expiration how long are account histories preserved
 * @param purse_account_limit how many purses are free per account
 * @param start_date from when are these fees valid (start date)
 * @param end_date until when are these fees valid (end date, exclusive)
 * @param master_sig master key signature affirming that this is the correct
 *                   fee (of purpose #TALER_SIGNATURE_MASTER_GLOBAL_FEES)
 */
static void
global_fee_info_cb (
  void *cls,
  const struct TALER_GlobalFeeSet *fees,
  struct GNUNET_TIME_Relative purse_timeout,
  struct GNUNET_TIME_Relative kyc_timeout,
  struct GNUNET_TIME_Relative history_expiration,
  uint32_t purse_account_limit,
  struct GNUNET_TIME_Timestamp start_date,
  struct GNUNET_TIME_Timestamp end_date,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TEH_KeyStateHandle *ksh = cls;
  struct TEH_GlobalFee *gf;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Found global fees with %u purses\n",
              purse_account_limit);
  gf = GNUNET_new (struct TEH_GlobalFee);
  gf->start_date = start_date;
  gf->end_date = end_date;
  gf->fees = *fees;
  gf->purse_timeout = purse_timeout;
  gf->kyc_timeout = kyc_timeout;
  gf->history_expiration = history_expiration;
  gf->purse_account_limit = purse_account_limit;
  gf->master_sig = *master_sig;
  GNUNET_CONTAINER_DLL_insert (ksh->gf_head,
                               ksh->gf_tail,
                               gf);
  GNUNET_assert (
    0 ==
    json_array_append_new (
      ksh->global_fees,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_timestamp ("start_date",
                                    start_date),
        GNUNET_JSON_pack_timestamp ("end_date",
                                    end_date),
        TALER_JSON_PACK_GLOBAL_FEES (fees),
        GNUNET_JSON_pack_time_rel ("history_expiration",
                                   history_expiration),
        GNUNET_JSON_pack_time_rel ("account_kyc_timeout",
                                   kyc_timeout),
        GNUNET_JSON_pack_time_rel ("purse_timeout",
                                   purse_timeout),
        GNUNET_JSON_pack_uint64 ("purse_account_limit",
                                 purse_account_limit),
        GNUNET_JSON_pack_data_auto ("master_sig",
                                    master_sig))));
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
  ksh->signature_expires = GNUNET_TIME_UNIT_FOREVER_TS;
  ksh->reload_time = GNUNET_TIME_timestamp_get ();
  /* We must use the key_generation from when we STARTED the process! */
  ksh->key_generation = key_generation;
  if (NULL == hs)
  {
    ksh->helpers = GNUNET_new (struct HelperState);
    if (GNUNET_OK !=
        setup_key_helpers (ksh->helpers))
    {
      GNUNET_free (ksh->helpers);
      GNUNET_assert (NULL == ksh->management_keys_reply);
      GNUNET_free (ksh);
      return NULL;
    }
  }
  else
  {
    ksh->helpers = hs;
  }
  ksh->denomkey_map = GNUNET_CONTAINER_multihashmap_create (1024,
                                                            GNUNET_YES);
  ksh->signkey_map = GNUNET_CONTAINER_multipeermap_create (32,
                                                           GNUNET_NO /* MUST be NO! */);
  ksh->auditors = json_array ();
  GNUNET_assert (NULL != ksh->auditors);
  /* NOTE: fetches master-signed signkeys, but ALSO those that were revoked! */
  GNUNET_break (GNUNET_OK ==
                TEH_plugin->preflight (TEH_plugin->cls));
  if (NULL != ksh->global_fees)
    json_decref (ksh->global_fees);
  ksh->global_fees = json_array ();
  qs = TEH_plugin->get_global_fees (TEH_plugin->cls,
                                    &global_fee_info_cb,
                                    ksh);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Loading global fees from DB: %d\n",
              qs);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
    destroy_key_state (ksh,
                       true);
    return NULL;
  }
  qs = TEH_plugin->iterate_denominations (TEH_plugin->cls,
                                          &denomination_info_cb,
                                          ksh);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
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
  struct GNUNET_DB_EventHeaderP es = {
    .size = htons (sizeof (es)),
    .type = htons (TALER_DBEVENT_EXCHANGE_KEYS_UPDATED),
  };

  TEH_plugin->event_notify (TEH_plugin->cls,
                            &es,
                            NULL,
                            0);
  key_generation++;
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

  old_ksh = key_state;
  if (NULL == old_ksh)
  {
    ksh = build_key_state (NULL,
                           management_only);
    if (NULL == ksh)
      return NULL;
    key_state = ksh;
    return ksh;
  }
  if ( (old_ksh->key_generation < key_generation) ||
       (GNUNET_TIME_absolute_is_past (old_ksh->signature_expires.abs_time)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Rebuilding /keys, generation upgrade from %llu to %llu\n",
                (unsigned long long) old_ksh->key_generation,
                (unsigned long long) key_generation);
    ksh = build_key_state (old_ksh->helpers,
                           management_only);
    key_state = ksh;
    old_ksh->helpers = NULL;
    destroy_key_state (old_ksh,
                       false);
    return ksh;
  }
  sync_key_helpers (old_ksh->helpers);
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


const struct TEH_GlobalFee *
TEH_keys_global_fee_by_time (
  struct TEH_KeyStateHandle *ksh,
  struct GNUNET_TIME_Timestamp ts)
{
  for (const struct TEH_GlobalFee *gf = ksh->gf_head;
       NULL != gf;
       gf = gf->next)
  {
    if (GNUNET_TIME_timestamp_cmp (ts,
                                   >=,
                                   gf->start_date) &&
        GNUNET_TIME_timestamp_cmp (ts,
                                   <,
                                   gf->end_date))
      return gf;
  }
  return NULL;
}


struct TEH_DenominationKey *
TEH_keys_denomination_by_hash (
  const struct TALER_DenominationHashP *h_denom_pub,
  struct MHD_Connection *conn,
  MHD_RESULT *mret)
{
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    *mret = TALER_MHD_reply_with_error (conn,
                                        MHD_HTTP_INTERNAL_SERVER_ERROR,
                                        TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                        NULL);
    return NULL;
  }
  return TEH_keys_denomination_by_hash2 (ksh,
                                         h_denom_pub,
                                         conn,
                                         mret);
}


struct TEH_DenominationKey *
TEH_keys_denomination_by_hash2 (
  struct TEH_KeyStateHandle *ksh,
  const struct TALER_DenominationHashP *h_denom_pub,
  struct MHD_Connection *conn,
  MHD_RESULT *mret)
{
  struct TEH_DenominationKey *dk;

  dk = GNUNET_CONTAINER_multihashmap_get (ksh->denomkey_map,
                                          &h_denom_pub->hash);
  if (NULL == dk)
  {
    if (NULL == conn)
      return NULL;
    *mret = TEH_RESPONSE_reply_unknown_denom_pub_hash (conn,
                                                       h_denom_pub);
    return NULL;
  }
  return dk;
}


enum TALER_ErrorCode
TEH_keys_denomination_sign_withdraw (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_BlindedPlanchet *bp,
  struct TALER_BlindedDenominationSignature *bs)
{
  struct TEH_KeyStateHandle *ksh;
  struct HelperDenomination *hd;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
    return TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
  hd = GNUNET_CONTAINER_multihashmap_get (ksh->helpers->denom_keys,
                                          &h_denom_pub->hash);
  if (NULL == hd)
    return TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN;
  if (bp->cipher != hd->denom_pub.cipher)
    return TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE;
  switch (hd->denom_pub.cipher)
  {
  case TALER_DENOMINATION_RSA:
    TEH_METRICS_num_signatures[TEH_MT_SIGNATURE_RSA]++;
    return TALER_CRYPTO_helper_rsa_sign (
      ksh->helpers->rsadh,
      &hd->h_details.h_rsa,
      bp->details.rsa_blinded_planchet.blinded_msg,
      bp->details.rsa_blinded_planchet.blinded_msg_size,
      bs);
  case TALER_DENOMINATION_CS:
    TEH_METRICS_num_signatures[TEH_MT_SIGNATURE_CS]++;
    return TALER_CRYPTO_helper_cs_sign_withdraw (
      ksh->helpers->csdh,
      &hd->h_details.h_cs,
      &bp->details.cs_blinded_planchet,
      bs);
  default:
    return TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE;
  }
}


enum TALER_ErrorCode
TEH_keys_denomination_sign_melt (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_BlindedPlanchet *bp,
  struct TALER_BlindedDenominationSignature *bs)
{
  struct TEH_KeyStateHandle *ksh;
  struct HelperDenomination *hd;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
    return TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
  hd = GNUNET_CONTAINER_multihashmap_get (ksh->helpers->denom_keys,
                                          &h_denom_pub->hash);
  if (NULL == hd)
    return TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN;
  if (bp->cipher != hd->denom_pub.cipher)
    return TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE;
  switch (hd->denom_pub.cipher)
  {
  case TALER_DENOMINATION_RSA:
    TEH_METRICS_num_signatures[TEH_MT_SIGNATURE_RSA]++;
    return TALER_CRYPTO_helper_rsa_sign (
      ksh->helpers->rsadh,
      &hd->h_details.h_rsa,
      bp->details.rsa_blinded_planchet.blinded_msg,
      bp->details.rsa_blinded_planchet.blinded_msg_size,
      bs);
  case TALER_DENOMINATION_CS:
    TEH_METRICS_num_signatures[TEH_MT_SIGNATURE_CS]++;
    return TALER_CRYPTO_helper_cs_sign_melt (
      ksh->helpers->csdh,
      &hd->h_details.h_cs,
      &bp->details.cs_blinded_planchet,
      bs);
  default:
    return TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE;
  }
}


enum TALER_ErrorCode
TEH_keys_denomination_cs_r_pub_melt (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_CsNonce *nonce,
  struct TALER_DenominationCSPublicRPairP *r_pub)
{
  struct TEH_KeyStateHandle *ksh;
  struct HelperDenomination *hd;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    return TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
  }
  hd = GNUNET_CONTAINER_multihashmap_get (ksh->helpers->denom_keys,
                                          &h_denom_pub->hash);
  if (NULL == hd)
  {
    return TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN;
  }
  if (TALER_DENOMINATION_CS != hd->denom_pub.cipher)
  {
    return TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE;
  }

  return TALER_CRYPTO_helper_cs_r_derive_melt (ksh->helpers->csdh,
                                               &hd->h_details.h_cs,
                                               nonce,
                                               r_pub);
}


enum TALER_ErrorCode
TEH_keys_denomination_cs_r_pub_withdraw (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_CsNonce *nonce,
  struct TALER_DenominationCSPublicRPairP *r_pub)
{
  struct TEH_KeyStateHandle *ksh;
  struct HelperDenomination *hd;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    return TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
  }
  hd = GNUNET_CONTAINER_multihashmap_get (ksh->helpers->denom_keys,
                                          &h_denom_pub->hash);
  if (NULL == hd)
  {
    return TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN;
  }
  if (TALER_DENOMINATION_CS != hd->denom_pub.cipher)
  {
    return TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE;
  }

  return TALER_CRYPTO_helper_cs_r_derive_withdraw (ksh->helpers->csdh,
                                                   &hd->h_details.h_cs,
                                                   nonce,
                                                   r_pub);
}


void
TEH_keys_denomination_revoke (const struct TALER_DenominationHashP *h_denom_pub)
{
  struct TEH_KeyStateHandle *ksh;
  struct HelperDenomination *hd;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    GNUNET_break (0);
    return;
  }
  hd = GNUNET_CONTAINER_multihashmap_get (ksh->helpers->denom_keys,
                                          &h_denom_pub->hash);
  if (NULL == hd)
  {
    GNUNET_break (0);
    return;
  }
  switch (hd->denom_pub.cipher)
  {
  case TALER_DENOMINATION_RSA:
    TALER_CRYPTO_helper_rsa_revoke (ksh->helpers->rsadh,
                                    &hd->h_details.h_rsa);
    TEH_keys_update_states ();
    return;
  case TALER_DENOMINATION_CS:
    TALER_CRYPTO_helper_cs_revoke (ksh->helpers->csdh,
                                   &hd->h_details.h_cs);
    TEH_keys_update_states ();
    return;
  default:
    GNUNET_break (0);
    return;
  }
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
  void *cls,
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig)
{
  struct TEH_KeyStateHandle *ksh = cls;
  enum TALER_ErrorCode ec;

  TEH_METRICS_num_signatures[TEH_MT_SIGNATURE_EDDSA]++;
  ec = TALER_CRYPTO_helper_esign_sign_ (ksh->helpers->esh,
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
  TALER_CRYPTO_helper_esign_revoke (ksh->helpers->esh,
                                    exchange_pub);
  TEH_keys_update_states ();
}


/**
 * Comparator used for a binary search by cherry_pick_date for @a key in the
 * `struct KeysResponseData` array. See libc's qsort() and bsearch() functions.
 *
 * @param key pointer to a `struct GNUNET_TIME_Timestamp`
 * @param value pointer to a `struct KeysResponseData` array entry
 * @return 0 if time matches, -1 if key is smaller, 1 if key is larger
 */
static int
krd_search_comparator (const void *key,
                       const void *value)
{
  const struct GNUNET_TIME_Timestamp *kd = key;
  const struct KeysResponseData *krd = value;

  if (GNUNET_TIME_timestamp_cmp (*kd,
                                 >,
                                 krd->cherry_pick_date))
    return -1;
  if (GNUNET_TIME_timestamp_cmp (*kd,
                                 <,
                                 krd->cherry_pick_date))
    return 1;
  return 0;
}


MHD_RESULT
TEH_keys_get_handler (struct TEH_RequestContext *rc,
                      const char *const args[])
{
  struct GNUNET_TIME_Timestamp last_issue_date;
  const char *etag;

  etag = MHD_lookup_connection_value (rc->connection,
                                      MHD_HEADER_KIND,
                                      MHD_HTTP_HEADER_IF_NONE_MATCH);
  (void) args;
  {
    const char *have_cherrypick;

    have_cherrypick = MHD_lookup_connection_value (rc->connection,
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
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           have_cherrypick);
      }
      /* The following multiplication may overflow; but this should not really
         be a problem, as giving back 'older' data than what the client asks for
         (given that the client asks for data in the distant future) is not
         problematic */
      last_issue_date = GNUNET_TIME_timestamp_from_s (cherrypickn);
    }
    else
    {
      last_issue_date = GNUNET_TIME_UNIT_ZERO_TS;
    }
  }

  {
    struct TEH_KeyStateHandle *ksh;
    const struct KeysResponseData *krd;

    ksh = TEH_keys_get_state ();
    if (NULL == ksh)
    {
      if ( ( (SKR_LIMIT == skr_size) &&
             (rc->connection == skr_connection) ) ||
           TEH_suicide)
      {
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_SERVICE_UNAVAILABLE,
          TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
          TEH_suicide
          ? "server terminating"
          : "too many connections suspended waiting on /keys");
      }
      return suspend_request (rc->connection);
    }
    krd = bsearch (&last_issue_date,
                   ksh->krd_array,
                   ksh->krd_array_length,
                   sizeof (struct KeysResponseData),
                   &krd_search_comparator);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Filtering /keys by cherry pick date %s found entry %u/%u\n",
                GNUNET_TIME_timestamp2s (last_issue_date),
                (unsigned int) (krd - ksh->krd_array),
                ksh->krd_array_length);
    if ( (NULL == krd) &&
         (ksh->krd_array_length > 0) )
    {
      if (! GNUNET_TIME_absolute_is_zero (last_issue_date.abs_time))
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Client provided invalid cherry picking timestamp %s, returning full response\n",
                    GNUNET_TIME_timestamp2s (last_issue_date));
      krd = &ksh->krd_array[ksh->krd_array_length - 1];
    }
    if (NULL == krd)
    {
      /* Likely keys not ready *yet*.
         Wait until they are. */
      return suspend_request (rc->connection);
    }
    if ( (NULL != etag) &&
         (0 == strcmp (etag,
                       krd->etag)) )
    {
      MHD_RESULT ret;
      struct MHD_Response *resp;

      resp = MHD_create_response_from_buffer (0,
                                              NULL,
                                              MHD_RESPMEM_PERSISTENT);
      TALER_MHD_add_global_headers (resp);
      GNUNET_break (GNUNET_OK ==
                    setup_general_response_headers (ksh,
                                                    resp));
      GNUNET_break (MHD_YES ==
                    MHD_add_response_header (resp,
                                             MHD_HTTP_HEADER_ETAG,
                                             krd->etag));
      ret = MHD_queue_response (rc->connection,
                                MHD_HTTP_NOT_MODIFIED,
                                resp);
      GNUNET_break (MHD_YES == ret);
      MHD_destroy_response (resp);
      return ret;
    }
    return MHD_queue_response (rc->connection,
                               MHD_HTTP_OK,
                               (MHD_YES ==
                                TALER_MHD_can_compress (rc->connection))
                               ? krd->response_compressed
                               : krd->response_uncompressed);
  }
}


/**
 * Load extension data, like fees, expiration times (!) and age restriction
 * flags for the denomination type configured in section @a section_name.
 * Before calling this function, the `start` and `validity_duration` times must
 * already be initialized in @a meta.
 *
 * @param section_name section in the configuration to use
 * @param[in,out] meta denomination type data to complete
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
load_extension_data (const char *section_name,
                     struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta)
{
  struct GNUNET_TIME_Relative deposit_duration;
  struct GNUNET_TIME_Relative legal_duration;

  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (meta->start.abs_time)); /* caller bug */
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
  meta->expire_deposit
    = GNUNET_TIME_absolute_to_timestamp (
        GNUNET_TIME_absolute_add (meta->expire_withdraw.abs_time,
                                  deposit_duration));
  meta->expire_legal = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (meta->expire_deposit.abs_time,
                              legal_duration));
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
  if (0 != strcasecmp (TEH_currency,
                       meta->value.currency))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Need denomination value in section `%s' to use currency `%s'\n",
                section_name,
                TEH_currency);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_denom_fees (TEH_cfg,
                                   TEH_currency,
                                   section_name,
                                   &meta->fees))
    return GNUNET_SYSERR;
  meta->age_mask = load_age_mask (section_name);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TEH_keys_load_fees (const struct TALER_DenominationHashP *h_denom_pub,
                    struct TALER_DenominationPublicKey *denom_pub,
                    struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta)
{
  struct TEH_KeyStateHandle *ksh;
  struct HelperDenomination *hd;
  enum GNUNET_GenericReturnValue ok;

  ksh = get_key_state (true);
  if (NULL == ksh)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  hd = GNUNET_CONTAINER_multihashmap_get (ksh->helpers->denom_keys,
                                          &h_denom_pub->hash);
  if (NULL == hd)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Denomination %s not known\n",
                GNUNET_h2s (&h_denom_pub->hash));
    return GNUNET_NO;
  }
  meta->start = hd->start_time;
  meta->expire_withdraw = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (meta->start.abs_time,
                              hd->validity_duration));
  ok = load_extension_data (hd->section_name,
                            meta);
  if (GNUNET_OK == ok)
  {
    GNUNET_assert (TALER_DENOMINATION_INVALID != hd->denom_pub.cipher);
    TALER_denom_pub_deep_copy (denom_pub,
                               &hd->denom_pub);
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "No fees for `%s', voiding key\n",
                hd->section_name);
    memset (denom_pub,
            0,
            sizeof (*denom_pub));
  }
  return ok;
}


enum GNUNET_GenericReturnValue
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
  hsk = GNUNET_CONTAINER_multipeermap_get (ksh->helpers->esign_keys,
                                           &pid);
  meta->start = hsk->start_time;

  meta->expire_sign = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (meta->start.abs_time,
                              hsk->validity_duration));
  meta->expire_legal = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (meta->expire_sign.abs_time,
                              signkey_legal_duration));
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
static enum GNUNET_GenericReturnValue
add_future_denomkey_cb (void *cls,
                        const struct GNUNET_HashCode *h_denom_pub,
                        void *value)
{
  struct FutureBuilderContext *fbc = cls;
  struct HelperDenomination *hd = value;
  struct TEH_DenominationKey *dk;
  struct TALER_EXCHANGEDB_DenominationKeyMetaData meta = {0};

  dk = GNUNET_CONTAINER_multihashmap_get (fbc->ksh->denomkey_map,
                                          h_denom_pub);
  if (NULL != dk)
    return GNUNET_OK; /* skip: this key is already active! */
  if (GNUNET_TIME_relative_is_zero (hd->validity_duration))
    return GNUNET_OK; /* this key already expired! */
  meta.start = hd->start_time;
  meta.expire_withdraw = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (meta.start.abs_time,
                              hd->validity_duration));
  if (GNUNET_OK !=
      load_extension_data (hd->section_name,
                           &meta))
  {
    /* Woops, couldn't determine fee structure!? */
    return GNUNET_OK;
  }
  GNUNET_assert (
    0 ==
    json_array_append_new (
      fbc->denoms,
      GNUNET_JSON_PACK (
        TALER_JSON_pack_amount ("value",
                                &meta.value),
        GNUNET_JSON_pack_timestamp ("stamp_start",
                                    meta.start),
        GNUNET_JSON_pack_timestamp ("stamp_expire_withdraw",
                                    meta.expire_withdraw),
        GNUNET_JSON_pack_timestamp ("stamp_expire_deposit",
                                    meta.expire_deposit),
        GNUNET_JSON_pack_timestamp ("stamp_expire_legal",
                                    meta.expire_legal),
        TALER_JSON_pack_denom_pub ("denom_pub",
                                   &hd->denom_pub),
        TALER_JSON_PACK_DENOM_FEES ("fee",
                                    &meta.fees),
        GNUNET_JSON_pack_data_auto ("denom_secmod_sig",
                                    &hd->sm_sig),
        GNUNET_JSON_pack_string ("section_name",
                                 hd->section_name))));
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
static enum GNUNET_GenericReturnValue
add_future_signkey_cb (void *cls,
                       const struct GNUNET_PeerIdentity *pid,
                       void *value)
{
  struct FutureBuilderContext *fbc = cls;
  struct HelperSignkey *hsk = value;
  struct SigningKey *sk;
  struct GNUNET_TIME_Timestamp stamp_expire;
  struct GNUNET_TIME_Timestamp legal_end;

  sk = GNUNET_CONTAINER_multipeermap_get (fbc->ksh->signkey_map,
                                          pid);
  if (NULL != sk)
    return GNUNET_OK; /* skip: this key is already active */
  if (GNUNET_TIME_relative_is_zero (hsk->validity_duration))
    return GNUNET_OK; /* this key already expired! */
  stamp_expire = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (hsk->start_time.abs_time,
                              hsk->validity_duration));
  legal_end = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (stamp_expire.abs_time,
                              signkey_legal_duration));
  GNUNET_assert (0 ==
                 json_array_append_new (
                   fbc->signkeys,
                   GNUNET_JSON_PACK (
                     GNUNET_JSON_pack_data_auto ("key",
                                                 &hsk->exchange_pub),
                     GNUNET_JSON_pack_timestamp ("stamp_start",
                                                 hsk->start_time),
                     GNUNET_JSON_pack_timestamp ("stamp_expire",
                                                 stamp_expire),
                     GNUNET_JSON_pack_timestamp ("stamp_end",
                                                 legal_end),
                     GNUNET_JSON_pack_data_auto ("signkey_secmod_sig",
                                                 &hsk->sm_sig))));
  return GNUNET_OK;
}


MHD_RESULT
TEH_keys_management_get_keys_handler (const struct TEH_RequestHandler *rh,
                                      struct MHD_Connection *connection)
{
  struct TEH_KeyStateHandle *ksh;
  json_t *reply;

  (void) rh;
  ksh = get_key_state (true);
  if (NULL == ksh)
  {
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_SERVICE_UNAVAILABLE,
                                       TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                       "no key state");
  }
  sync_key_helpers (ksh->helpers);
  if (NULL == ksh->management_keys_reply)
  {
    struct FutureBuilderContext fbc = {
      .ksh = ksh,
      .denoms = json_array (),
      .signkeys = json_array ()
    };

    if ( (GNUNET_is_zero (&denom_rsa_sm_pub)) &&
         (GNUNET_is_zero (&denom_cs_sm_pub)) )
    {
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_GATEWAY,
                                         TALER_EC_EXCHANGE_DENOMINATION_HELPER_UNAVAILABLE,
                                         NULL);
    }
    if (GNUNET_is_zero (&esign_sm_pub))
    {
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_GATEWAY,
                                         TALER_EC_EXCHANGE_SIGNKEY_HELPER_UNAVAILABLE,
                                         NULL);
    }
    // then a secmod helper is not yet running and we should return an MHD_HTTP_BAD_GATEWAY!
    GNUNET_assert (NULL != fbc.denoms);
    GNUNET_assert (NULL != fbc.signkeys);
    GNUNET_CONTAINER_multihashmap_iterate (ksh->helpers->denom_keys,
                                           &add_future_denomkey_cb,
                                           &fbc);
    GNUNET_CONTAINER_multipeermap_iterate (ksh->helpers->esign_keys,
                                           &add_future_signkey_cb,
                                           &fbc);
    reply = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_array_steal ("future_denoms",
                                    fbc.denoms),
      GNUNET_JSON_pack_array_steal ("future_signkeys",
                                    fbc.signkeys),
      GNUNET_JSON_pack_data_auto ("master_pub",
                                  &TEH_master_public_key),
      GNUNET_JSON_pack_data_auto ("denom_secmod_public_key",
                                  &denom_rsa_sm_pub),
      GNUNET_JSON_pack_data_auto ("denom_secmod_cs_public_key",
                                  &denom_cs_sm_pub),
      GNUNET_JSON_pack_data_auto ("signkey_secmod_public_key",
                                  &esign_sm_pub));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Returning GET /management/keys response:\n");
    if (NULL == reply)
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                         NULL);
    GNUNET_assert (NULL == ksh->management_keys_reply);
    ksh->management_keys_reply = reply;
  }
  else
  {
    reply = ksh->management_keys_reply;
  }
  return TALER_MHD_reply_json (connection,
                               reply,
                               MHD_HTTP_OK);
}


/* end of taler-exchange-httpd_keys.c */
