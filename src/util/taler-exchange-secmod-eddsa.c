/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file util/taler-exchange-secmod-eddsa.c
 * @brief Standalone process to perform private key EDDSA operations
 * @author Christian Grothoff
 *
 * Key design points:
 * - EVERY thread of the exchange will have its own pair of connections to the
 *   crypto helpers.  This way, every threat will also have its own /keys state
 *   and avoid the need to synchronize on those.
 * - auditor signatures and master signatures are to be kept in the exchange DB,
 *   and merged with the public keys of the helper by the exchange HTTPD!
 * - the main loop of the helper is SINGLE-THREADED, but there are
 *   threads for crypto-workers which (only) do the signing in parallel,
 *   one per client.
 * - thread-safety: signing happens in parallel, thus when REMOVING private keys,
 *   we must ensure that all signers are done before we fully free() the
 *   private key. This is done by reference counting (as work is always
 *   assigned and collected by the main thread).
 */
#include "platform.h"
#include "taler_util.h"
#include "taler-exchange-secmod-eddsa.h"
#include <gcrypt.h>
#include <pthread.h>
#include <sys/eventfd.h>
#include "taler_error_codes.h"
#include "taler_signatures.h"
#include "secmod_common.h"
#include <poll.h>


/**
 * One particular key.
 */
struct Key
{

  /**
   * Kept in a DLL. Sorted by anchor time.
   */
  struct Key *next;

  /**
   * Kept in a DLL. Sorted by anchor time.
   */
  struct Key *prev;

  /**
   * Name of the file this key is stored under.
   */
  char *filename;

  /**
   * The private key.
   */
  struct TALER_ExchangePrivateKeyP exchange_priv;

  /**
   * The public key.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Time at which this key is supposed to become valid.
   */
  struct GNUNET_TIME_Absolute anchor;

  /**
   * Generation when this key was created or revoked.
   */
  uint64_t key_gen;

  /**
   * Reference counter. Counts the number of threads that are
   * using this key at this time.
   */
  unsigned int rc;

  /**
   * Flag set to true if this key has been purged and the memory
   * must be freed as soon as @e rc hits zero.
   */
  bool purge;

};


/**
 * Head of DLL of actual keys, sorted by anchor.
 */
static struct Key *keys_head;

/**
 * Tail of DLL of actual keys.
 */
static struct Key *keys_tail;

/**
 * How long can a key be used?
 */
static struct GNUNET_TIME_Relative duration;

/**
 * Return value from main().
 */
static int global_ret;

/**
 * Time when the key update is executed.
 * Either the actual current time, or a pretended time.
 */
static struct GNUNET_TIME_Absolute now;

/**
 * The time for the key update, as passed by the user
 * on the command line.
 */
static struct GNUNET_TIME_Absolute now_tmp;

/**
 * Where do we store the keys?
 */
static char *keydir;

/**
 * How much should coin creation duration overlap
 * with the next key?  Basically, the starting time of two
 * keys is always #duration - #overlap_duration apart.
 */
static struct GNUNET_TIME_Relative overlap_duration;

/**
 * How long into the future do we pre-generate keys?
 */
static struct GNUNET_TIME_Relative lookahead_sign;

/**
 * Task run to generate new keys.
 */
static struct GNUNET_SCHEDULER_Task *keygen_task;

/**
 * Lock for the keys queue.
 */
static pthread_mutex_t keys_lock;

/**
 * Current key generation.
 */
static uint64_t key_gen;


/**
 * Notify @a client about @a key becoming available.
 *
 * @param[in,out] client the client to notify; possible freed if transmission fails
 * @param key the key to notify @a client about
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
notify_client_key_add (struct TES_Client *client,
                       const struct Key *key)
{
  struct TALER_CRYPTO_EddsaKeyAvailableNotification an = {
    .header.size = htons (sizeof (an)),
    .header.type = htons (TALER_HELPER_EDDSA_MT_AVAIL),
    .anchor_time = GNUNET_TIME_absolute_hton (key->anchor),
    .duration = GNUNET_TIME_relative_hton (duration),
    .exchange_pub = key->exchange_pub,
    .secm_pub = TES_smpub
  };

  TALER_exchange_secmod_eddsa_sign (&key->exchange_pub,
                                    key->anchor,
                                    duration,
                                    &TES_smpriv,
                                    &an.secm_sig);
  if (GNUNET_OK !=
      TES_transmit (client->csock,
                    &an.header))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Client %p must have disconnected\n",
                client);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Notify @a client about @a key being purged.
 *
 * @param[in,out] client the client to notify; possible freed if transmission fails
 * @param key the key to notify @a client about
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
notify_client_key_del (struct TES_Client *client,
                       const struct Key *key)
{
  struct TALER_CRYPTO_EddsaKeyPurgeNotification pn = {
    .header.type = htons (TALER_HELPER_EDDSA_MT_PURGE),
    .header.size = htons (sizeof (pn)),
    .exchange_pub = key->exchange_pub
  };

  if (GNUNET_OK !=
      TES_transmit (client->csock,
                    &pn.header))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Client %p must have disconnected\n",
                client);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Handle @a client request @a sr to create signature. Create the
 * signature using the respective key and return the result to
 * the client.
 *
 * @param client the client making the request
 * @param sr the request details
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_sign_request (struct TES_Client *client,
                     const struct TALER_CRYPTO_EddsaSignRequest *sr)
{
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose = &sr->purpose;
  size_t purpose_size = ntohs (sr->header.size) - sizeof (*sr)
                        + sizeof (*purpose);
  struct Key *key;
  struct TALER_CRYPTO_EddsaSignResponse sres = {
    .header.size = htons (sizeof (sres)),
    .header.type = htons (TALER_HELPER_EDDSA_MT_RES_SIGNATURE)
  };
  enum TALER_ErrorCode ec;

  if (purpose_size != htonl (purpose->size))
  {
    struct TALER_CRYPTO_EddsaSignFailure sf = {
      .header.size = htons (sizeof (sr)),
      .header.type = htons (TALER_HELPER_EDDSA_MT_RES_SIGN_FAILURE),
      .ec = htonl (TALER_EC_GENERIC_PARAMETER_MALFORMED)
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Signing request failed, request malformed\n");
    return TES_transmit (client->csock,
                         &sf.header);
  }

  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  key = keys_head;
  while ( (NULL != key) &&
          (GNUNET_TIME_absolute_is_past (
             GNUNET_TIME_absolute_add (key->anchor,
                                       duration))) )
  {
    struct Key *nxt = key->next;

    if (0 != key->rc)
      break; /* do later */
    GNUNET_CONTAINER_DLL_remove (keys_head,
                                 keys_tail,
                                 key);
    if ( (! key->purge) &&
         (0 != unlink (key->filename)) )
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                "unlink",
                                key->filename);
    GNUNET_free (key->filename);
    GNUNET_free (key);
    key = nxt;
  }
  if (NULL == key)
  {
    GNUNET_break (0);
    ec = TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING;
  }
  else
  {
    GNUNET_assert (key->rc < UINT_MAX);
    key->rc++;
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));

    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_sign_ (&key->exchange_priv.eddsa_priv,
                                   purpose,
                                   &sres.exchange_sig.eddsa_signature))
      ec = TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE;
    else
      ec = TALER_EC_NONE;
    sres.exchange_pub = key->exchange_pub;
    GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
    GNUNET_assert (key->rc > 0);
    key->rc--;
  }
  GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
  if (TALER_EC_NONE != ec)
  {
    struct TALER_CRYPTO_EddsaSignFailure sf = {
      .header.size = htons (sizeof (sf)),
      .header.type = htons (TALER_HELPER_EDDSA_MT_RES_SIGN_FAILURE),
      .ec = htonl ((uint32_t) ec)
    };

    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Signing request %p failed, worker failed to produce signature\n",
                client);
    return TES_transmit (client->csock,
                         &sf.header);
  }
  return TES_transmit (client->csock,
                       &sres.header);
}


/**
 * Initialize key material for key @a key (also on disk).
 *
 * @param[in,out] key to compute key material for
 * @param position where in the DLL will the @a key go
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
setup_key (struct Key *key,
           struct Key *position)
{
  struct GNUNET_CRYPTO_EddsaPrivateKey priv;
  struct GNUNET_CRYPTO_EddsaPublicKey pub;

  GNUNET_CRYPTO_eddsa_key_create (&priv);
  GNUNET_CRYPTO_eddsa_key_get_public (&priv,
                                      &pub);
  GNUNET_asprintf (&key->filename,
                   "%s/%llu",
                   keydir,
                   (unsigned long long) (key->anchor.abs_value_us
                                         / GNUNET_TIME_UNIT_SECONDS.rel_value_us));
  if (GNUNET_OK !=
      GNUNET_DISK_fn_write (key->filename,
                            &priv,
                            sizeof (priv),
                            GNUNET_DISK_PERM_USER_READ))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "write",
                              key->filename);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Setup fresh private key in `%s'\n",
              key->filename);
  key->key_gen = key_gen;
  key->exchange_priv.eddsa_priv = priv;
  key->exchange_pub.eddsa_pub = pub;
  GNUNET_CONTAINER_DLL_insert_after (keys_head,
                                     keys_tail,
                                     position,
                                     key);
  return GNUNET_OK;
}


/**
 * The validity period of a key @a key has expired. Purge it.
 *
 * @param[in] key expired or revoked key to purge
 */
static void
purge_key (struct Key *key)
{
  if (key->purge)
    return;
  if (0 != unlink (key->filename))
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "unlink",
                              key->filename);
  key->purge = true;
  key->key_gen = key_gen;
  GNUNET_free (key->filename);
}


/**
 * A @a client informs us that a key has been revoked.
 * Check if the key is still in use, and if so replace (!)
 * it with a fresh key.
 *
 * @param client the client making the request
 * @param rr the revocation request
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_revoke_request (struct TES_Client *client,
                       const struct TALER_CRYPTO_EddsaRevokeRequest *rr)
{
  struct Key *key;
  struct Key *nkey;

  (void) client;
  key = NULL;
  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  for (struct Key *pos = keys_head;
       NULL != pos;
       pos = pos->next)
    if (0 == GNUNET_memcmp (&pos->exchange_pub,
                            &rr->exchange_pub))
    {
      key = pos;
      break;
    }
  if (NULL == key)
  {
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Revocation request ignored, key unknown\n");
    return GNUNET_OK;
  }

  key_gen++;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Revoking key %p, bumping generation to %llu\n",
              key,
              (unsigned long long) key_gen);
  purge_key (key);

  /* Setup replacement key */
  nkey = GNUNET_new (struct Key);
  nkey->anchor = key->anchor;
  if (GNUNET_OK !=
      setup_key (nkey,
                 key))
  {
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = EXIT_FAILURE;
    return GNUNET_SYSERR;
  }
  GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
  TES_wake_clients ();
  return GNUNET_OK;
}


/**
 * Handle @a hdr message received from @a client.
 *
 * @param client the client that received the message
 * @param hdr message that was received
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
eddsa_work_dispatch (struct TES_Client *client,
                     const struct GNUNET_MessageHeader *hdr)
{
  uint16_t msize = ntohs (hdr->size);

  switch (ntohs (hdr->type))
  {
  case TALER_HELPER_EDDSA_MT_REQ_SIGN:
    if (msize < sizeof (struct TALER_CRYPTO_EddsaSignRequest))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    return handle_sign_request (
      client,
      (const struct TALER_CRYPTO_EddsaSignRequest *) hdr);
  case TALER_HELPER_EDDSA_MT_REQ_REVOKE:
    if (msize != sizeof (struct TALER_CRYPTO_EddsaRevokeRequest))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    return handle_revoke_request (
      client,
      (const struct TALER_CRYPTO_EddsaRevokeRequest *) hdr);
  default:
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
}


/**
 * Send our initial key set to @a client together with the
 * "sync" terminator.
 *
 * @param client the client to inform
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
eddsa_client_init (struct TES_Client *client)
{
  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  for (struct Key *key = keys_head;
       NULL != key;
       key = key->next)
  {
    if (GNUNET_OK !=
        notify_client_key_add (client,
                               key))
    {
      GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }
  client->key_gen = key_gen;
  GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
  {
    struct GNUNET_MessageHeader synced = {
      .type = htons (TALER_HELPER_EDDSA_SYNCED),
      .size = htons (sizeof (synced))
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Client %p synced\n",
                client);
    if (GNUNET_OK !=
        TES_transmit (client->csock,
                      &synced))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


/**
 * Notify @a client about all changes to the keys since
 * the last generation known to the @a client.
 *
 * @param client the client to notify
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
eddsa_update_client_keys (struct TES_Client *client)
{
  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  for (struct Key *key = keys_head;
       NULL != key;
       key = key->next)
  {
    if (key->key_gen <= client->key_gen)
      continue;
    if (key->purge)
    {
      if (GNUNET_OK !=
          notify_client_key_del (client,
                                 key))
      {
        GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
        return GNUNET_SYSERR;
      }
    }
    else
    {
      if (GNUNET_OK !=
          notify_client_key_add (client,
                                 key))
      {
        GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
        return GNUNET_SYSERR;
      }
    }
  }
  client->key_gen = key_gen;
  GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
  return GNUNET_OK;
}


/**
 * Create a new key (we do not have enough).
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
create_key (void)
{
  struct Key *key;
  struct GNUNET_TIME_Absolute anchor;
  struct GNUNET_TIME_Absolute now;

  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  if (NULL == keys_tail)
  {
    anchor = now;
  }
  else
  {
    anchor = GNUNET_TIME_absolute_add (keys_tail->anchor,
                                       GNUNET_TIME_relative_subtract (
                                         duration,
                                         overlap_duration));
    if (now.abs_value_us > anchor.abs_value_us)
      anchor = now;
  }
  key = GNUNET_new (struct Key);
  key->anchor = anchor;
  if (GNUNET_OK !=
      setup_key (key,
                 keys_tail))
  {
    GNUNET_break (0);
    GNUNET_free (key);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = EXIT_FAILURE;
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * At what time does the current key set require its next action?  Basically,
 * the minimum of the expiration time of the oldest key, and the expiration
 * time of the newest key minus the #lookahead_sign time.
 */
static struct GNUNET_TIME_Absolute
key_action_time (void)
{
  if (NULL == keys_head)
    return GNUNET_TIME_UNIT_ZERO_ABS;
  return GNUNET_TIME_absolute_min (
    GNUNET_TIME_absolute_add (keys_head->anchor,
                              duration),
    GNUNET_TIME_absolute_subtract (
      GNUNET_TIME_absolute_subtract (
        GNUNET_TIME_absolute_add (keys_tail->anchor,
                                  duration),
        lookahead_sign),
      overlap_duration));
}


/**
 * Create new keys and expire ancient keys.
 *
 * @param cls NULL
 */
static void
update_keys (void *cls)
{
  bool wake = false;

  (void) cls;
  keygen_task = NULL;
  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  /* create new keys */
  while ( (NULL == keys_tail) ||
          GNUNET_TIME_absolute_is_past (
            GNUNET_TIME_absolute_subtract (
              GNUNET_TIME_absolute_subtract (
                GNUNET_TIME_absolute_add (keys_tail->anchor,
                                          duration),
                lookahead_sign),
              overlap_duration)) )
  {
    if (! wake)
    {
      key_gen++;
      wake = true;
    }
    if (GNUNET_OK !=
        create_key ())
    {
      GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
      GNUNET_break (0);
      global_ret = EXIT_FAILURE;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
  }
  /* remove expired keys */
  while ( (NULL != keys_head) &&
          GNUNET_TIME_absolute_is_past (
            GNUNET_TIME_absolute_add (keys_head->anchor,
                                      duration)))
  {
    if (! wake)
    {
      key_gen++;
      wake = true;
    }
    purge_key (keys_head);
  }
  GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
  if (wake)
    TES_wake_clients ();
  keygen_task = GNUNET_SCHEDULER_add_at (key_action_time (),
                                         &update_keys,
                                         NULL);
}


/**
 * Parse private key from @a filename in @a buf.
 *
 * @param filename name of the file we are parsing, for logging
 * @param buf key material
 * @param buf_size number of bytes in @a buf
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_key (const char *filename,
           const void *buf,
           size_t buf_size)
{
  struct GNUNET_CRYPTO_EddsaPrivateKey priv;
  char *anchor_s;
  char dummy;
  unsigned long long anchor_ll;
  struct GNUNET_TIME_Absolute anchor;

  anchor_s = strrchr (filename,
                      '/');
  if (NULL == anchor_s)
  {
    /* File in a directory without '/' in the name, this makes no sense. */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  anchor_s++;
  if (1 != sscanf (anchor_s,
                   "%llu%c",
                   &anchor_ll,
                   &dummy))
  {
    /* Filenames in KEYDIR must ONLY be the anchor time in seconds! */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Filename `%s' invalid for key file, skipping\n",
                filename);
    return GNUNET_SYSERR;
  }
  anchor.abs_value_us = anchor_ll * GNUNET_TIME_UNIT_SECONDS.rel_value_us;
  if (anchor_ll != anchor.abs_value_us / GNUNET_TIME_UNIT_SECONDS.rel_value_us)
  {
    /* Integer overflow. Bad, invalid filename. */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Filename `%s' invalid for key file, skipping\n",
                filename);
    return GNUNET_SYSERR;
  }
  if (buf_size != sizeof (priv))
  {
    /* Parser failure. */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "File `%s' is malformed, skipping\n",
                filename);
    return GNUNET_SYSERR;
  }
  memcpy (&priv,
          buf,
          buf_size);

  {
    struct GNUNET_CRYPTO_EddsaPublicKey pub;
    struct Key *key;
    struct Key *before;

    GNUNET_CRYPTO_eddsa_key_get_public (&priv,
                                        &pub);
    GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
    key = GNUNET_new (struct Key);
    key->exchange_priv.eddsa_priv = priv;
    key->exchange_pub.eddsa_pub = pub;
    key->anchor = anchor;
    key->filename = GNUNET_strdup (filename);
    key->key_gen = key_gen;
    before = NULL;
    for (struct Key *pos = keys_head;
         NULL != pos;
         pos = pos->next)
    {
      if (pos->anchor.abs_value_us > anchor.abs_value_us)
        break;
      before = pos;
    }
    GNUNET_CONTAINER_DLL_insert_after (keys_head,
                                       keys_tail,
                                       before,
                                       key);
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Imported key from `%s'\n",
                filename);
  }
  return GNUNET_OK;
}


/**
 * Import a private key from @a filename.
 *
 * @param cls NULL
 * @param filename name of a file in the directory
 */
static enum GNUNET_GenericReturnValue
import_key (void *cls,
            const char *filename)
{
  struct GNUNET_DISK_FileHandle *fh;
  struct GNUNET_DISK_MapHandle *map;
  void *ptr;
  int fd;
  struct stat sbuf;

  (void) cls;
  {
    struct stat lsbuf;

    if (0 != lstat (filename,
                    &lsbuf))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "lstat",
                                filename);
      return GNUNET_OK;
    }
    if (! S_ISREG (lsbuf.st_mode))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "File `%s' is not a regular file, which is not allowed for private keys!\n",
                  filename);
      return GNUNET_OK;
    }
  }

  fd = open (filename,
             O_CLOEXEC);
  if (-1 == fd)
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "open",
                              filename);
    return GNUNET_OK;
  }
  if (0 != fstat (fd,
                  &sbuf))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "stat",
                              filename);
    return GNUNET_OK;
  }
  if (! S_ISREG (sbuf.st_mode))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "File `%s' is not a regular file, which is not allowed for private keys!\n",
                filename);
    return GNUNET_OK;
  }
  if (0 != (sbuf.st_mode & (S_IWUSR | S_IRWXG | S_IRWXO)))
  {
    /* permission are NOT tight, try to patch them up! */
    if (0 !=
        fchmod (fd,
                S_IRUSR))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "fchmod",
                                filename);
      /* refuse to use key if file has wrong permissions */
      GNUNET_break (0 == close (fd));
      return GNUNET_OK;
    }
  }
  fh = GNUNET_DISK_get_handle_from_int_fd (fd);
  if (NULL == fh)
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "open",
                              filename);
    GNUNET_break (0 == close (fd));
    return GNUNET_OK;
  }
  if (sbuf.st_size > 2048)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "File `%s' to big to be a private key\n",
                filename);
    GNUNET_DISK_file_close (fh);
    return GNUNET_OK;
  }
  ptr = GNUNET_DISK_file_map (fh,
                              &map,
                              GNUNET_DISK_MAP_TYPE_READ,
                              (size_t) sbuf.st_size);
  if (NULL == ptr)
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "mmap",
                              filename);
    GNUNET_DISK_file_close (fh);
    return GNUNET_OK;
  }
  (void) parse_key (filename,
                    ptr,
                    (size_t) sbuf.st_size);
  GNUNET_DISK_file_unmap (map);
  GNUNET_DISK_file_close (fh);
  return GNUNET_OK;
}


/**
 * Load the various duration values from @a kcfg.
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
load_durations (const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "taler-exchange-secmod-eddsa",
                                           "OVERLAP_DURATION",
                                           &overlap_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-eddsa",
                               "OVERLAP_DURATION");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "taler-exchange-secmod-eddsa",
                                           "DURATION",
                                           &duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-eddsa",
                               "DURATION");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&overlap_duration);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "taler-exchange-secmod-eddsa",
                                           "LOOKAHEAD_SIGN",
                                           &lookahead_sign))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-eddsa",
                               "LOOKAHEAD_SIGN");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&lookahead_sign);
  return GNUNET_OK;
}


/**
 * Function run on shutdown. Stops the various jobs (nicely).
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  (void) cls;
  TES_listen_stop ();
  if (NULL != keygen_task)
  {
    GNUNET_SCHEDULER_cancel (keygen_task);
    keygen_task = NULL;
  }
}


/**
 * Main function that will be run under the GNUnet scheduler.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  static struct TES_Callbacks cb = {
    .dispatch = eddsa_work_dispatch,
    .updater = eddsa_update_client_keys,
    .init = eddsa_client_init
  };

  (void) cls;
  (void) args;
  (void) cfgfile;
  if (now.abs_value_us != now_tmp.abs_value_us)
  {
    /* The user gave "--now", use it! */
    now = now_tmp;
  }
  else
  {
    /* get current time again, we may be timetraveling! */
    now = GNUNET_TIME_absolute_get ();
  }
  GNUNET_TIME_round_abs (&now);
  if (GNUNET_OK !=
      load_durations (cfg))
  {
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "taler-exchange-secmod-eddsa",
                                               "KEY_DIR",
                                               &keydir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-eddsa",
                               "KEY_DIR");
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  global_ret = TES_listen_start (cfg,
                                 "taler-exchange-secmod-eddsa",
                                 &cb);
  if (0 != global_ret)
    return;
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  /* Load keys */
  GNUNET_break (GNUNET_OK ==
                GNUNET_DISK_directory_create (keydir));
  GNUNET_DISK_directory_scan (keydir,
                              &import_key,
                              NULL);

  /* start job to keep keys up-to-date; MUST be run before the #listen_task,
     hence with priority. */
  keygen_task = GNUNET_SCHEDULER_add_with_priority (
    GNUNET_SCHEDULER_PRIORITY_URGENT,
    &update_keys,
    NULL);
}


/**
 * The entry point.
 *
 * @param argc number of arguments in @a argv
 * @param argv command-line arguments
 * @return 0 on normal termination
 */
int
main (int argc,
      char **argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_option_absolute_time ('t',
                                        "time",
                                        "TIMESTAMP",
                                        "pretend it is a different time for the update",
                                        &now_tmp),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  /* Restrict permissions for the key files that we create. */
  (void) umask (S_IWGRP | S_IROTH | S_IWOTH | S_IXOTH);

  /* force linker to link against libtalerutil; if we do
   not do this, the linker may "optimize" libtalerutil
   away and skip #TALER_OS_init(), which we do need */
  TALER_OS_init ();
  now = now_tmp = GNUNET_TIME_absolute_get ();
  ret = GNUNET_PROGRAM_run (argc, argv,
                            "taler-exchange-secmod-eddsa",
                            "Handle private EDDSA key operations for a Taler exchange",
                            options,
                            &run,
                            NULL);
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  return global_ret;
}
