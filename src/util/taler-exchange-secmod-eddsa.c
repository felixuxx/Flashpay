/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 *   working of a work-queue.
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
 * Information we keep for a client connected to us.
 */
struct Client
{

  /**
   * Kept in a DLL.
   */
  struct Client *next;

  /**
   * Kept in a DLL.
   */
  struct Client *prev;

  /**
   * Client address.
   */
  struct sockaddr_un addr;

  /**
   * Number of bytes used in @e addr.
   */
  socklen_t addr_size;

};


struct WorkItem
{

  /**
   * Kept in a DLL.
   */
  struct WorkItem *next;

  /**
   * Kept in a DLL.
   */
  struct WorkItem *prev;

  /**
   * Key to be used for this operation.
   */
  struct Key *key;

  /**
   * EDDSA signature over @e msg using @e key. Result of doing the work.
   */
  struct TALER_ExchangeSignatureP signature;

  /**
   * Message to sign.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose *purpose;

  /**
   * Client address.
   */
  struct sockaddr_un addr;

  /**
   * Number of bytes used in @e addr.
   */
  socklen_t addr_size;

  /**
   * Operation status code.
   */
  enum TALER_ErrorCode ec;

};


/**
 * Private key of this security module. Used to sign denomination key
 * announcements.
 */
static struct TALER_SecurityModulePrivateKeyP smpriv;

/**
 * Public key of this security module.
 */
static struct TALER_SecurityModulePublicKeyP smpub;

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
 * Number of worker threads to use. Default (0) is to use one per CPU core
 * available.
 * Length of the #workers array.
 */
static unsigned int num_workers;

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
 * Handle to the exchange's configuration
 */
static const struct GNUNET_CONFIGURATION_Handle *kcfg;

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
 * Our listen socket.
 */
static struct GNUNET_NETWORK_Handle *unix_sock;

/**
 * Path where we are listening.
 */
static char *unixpath;

/**
 * Task run to accept new inbound connections.
 */
static struct GNUNET_SCHEDULER_Task *read_task;

/**
 * Task run to generate new keys.
 */
static struct GNUNET_SCHEDULER_Task *keygen_task;

/**
 * Head of DLL of clients connected to us.
 */
static struct Client *clients_head;

/**
 * Tail of DLL of clients connected to us.
 */
static struct Client *clients_tail;

/**
 * Head of DLL with pending signing operations.
 */
static struct WorkItem *work_head;

/**
 * Tail of DLL with pending signing operations.
 */
static struct WorkItem *work_tail;

/**
 * Lock for the work queue.
 */
static pthread_mutex_t work_lock;

/**
 * Condition variable for the semaphore of the work queue.
 */
static pthread_cond_t work_cond = PTHREAD_COND_INITIALIZER;

/**
 * Number of items in the work queue. Also used as the semaphore counter.
 */
static unsigned long long work_counter;

/**
 * Head of DLL with completed signing operations.
 */
static struct WorkItem *done_head;

/**
 * Tail of DLL with completed signing operations.
 */
static struct WorkItem *done_tail;

/**
 * Lock for the done queue.
 */
static pthread_mutex_t done_lock;

/**
 * Task waiting for work to be done.
 */
static struct GNUNET_SCHEDULER_Task *done_task;

/**
 * Signal used by threads to notify the #done_task that they
 * completed work that is now in the done queue.
 */
static struct GNUNET_NETWORK_Handle *done_signal;

/**
 * Set once we are in shutdown and workers should terminate.
 */
static volatile bool in_shutdown;

/**
 * Array of #num_workers sign_worker() threads.
 */
static pthread_t *workers;


/**
 * Main function of a worker thread that signs.
 *
 * @param cls NULL
 * @return NULL
 */
static void *
sign_worker (void *cls)
{
  (void) cls;
  GNUNET_assert (0 == pthread_mutex_lock (&work_lock));
  while (! in_shutdown)
  {
    struct WorkItem *wi;

    while (NULL != (wi = work_head))
    {
      /* take work from queue */
      GNUNET_CONTAINER_DLL_remove (work_head,
                                   work_tail,
                                   wi);
      work_counter--;
      GNUNET_assert (0 == pthread_mutex_unlock (&work_lock));
      {
        if (GNUNET_OK !=
            GNUNET_CRYPTO_eddsa_sign_ (&wi->key->exchange_priv.eddsa_priv,
                                       wi->purpose,
                                       &wi->signature.eddsa_signature))
          wi->ec = TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE;
        else
          wi->ec = TALER_EC_NONE;
      }
      /* put completed work into done queue */
      GNUNET_assert (0 == pthread_mutex_lock (&done_lock));
      GNUNET_CONTAINER_DLL_insert (done_head,
                                   done_tail,
                                   wi);
      GNUNET_assert (0 == pthread_mutex_unlock (&done_lock));
      {
        uint64_t val = GNUNET_htonll (1);

        /* raise #done_signal */
        if (sizeof(val) !=
            write (GNUNET_NETWORK_get_fd (done_signal),
                   &val,
                   sizeof (val)))
          GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                               "write(eventfd)");
      }
      GNUNET_assert (0 == pthread_mutex_lock (&work_lock));
    }
    if (in_shutdown)
      break;
    /* queue is empty, wait for work */
    GNUNET_assert (0 ==
                   pthread_cond_wait (&work_cond,
                                      &work_lock));
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&work_lock));
  return NULL;
}


/**
 * Free @a client, releasing all (remaining) state.
 *
 * @param[in] client data to free
 */
static void
free_client (struct Client *client)
{
  GNUNET_CONTAINER_DLL_remove (clients_head,
                               clients_tail,
                               client);
  GNUNET_free (client);
}


/**
 * Function run to read incoming requests from a client.
 *
 * @param cls the `struct Client`
 */
static void
read_job (void *cls);


/**
 * Free @a key. It must already have been removed from the DLL.
 *
 * @param[in] key the key to free
 */
static void
free_key (struct Key *key)
{
  GNUNET_free (key->filename);
  GNUNET_free (key);
}


/**
 * Send a message starting with @a hdr to @a client.  We expect that
 * the client is mostly able to handle everything at whatever speed
 * we have (after all, the crypto should be the slow part). However,
 * especially on startup when we send all of our keys, it is possible
 * that the client cannot keep up. In that case, we throttle when
 * sending fails. This does not work with poll() as we cannot specify
 * the sendto() target address with poll(). So we nanosleep() instead.
 *
 * @param addr address where to send the message
 * @param addr_size number of bytes in @a addr
 * @param hdr beginning of the message, length indicated in size field
 * @return #GNUNET_OK on success
 */
static int
transmit (const struct sockaddr_un *addr,
          socklen_t addr_size,
          const struct GNUNET_MessageHeader *hdr)
{
  for (unsigned int i = 0; i<100; i++)
  {
    ssize_t ret = sendto (GNUNET_NETWORK_get_fd (unix_sock),
                          hdr,
                          ntohs (hdr->size),
                          0 /* no flags => blocking! */,
                          (const struct sockaddr *) addr,
                          addr_size);
    if ( (-1 == ret) &&
         (EAGAIN == errno) )
    {
      /* _Maybe_ with blocking sendto(), this should no
         longer be needed; still keeping it just in case. */
      /* Wait a bit, in case client is just too slow */
      struct timespec req = {
        .tv_sec = 0,
        .tv_nsec = 1000
      };
      nanosleep (&req, NULL);
      continue;
    }
    if (ret == ntohs (hdr->size))
      return GNUNET_OK;
    if (ret != ntohs (hdr->size))
      break;
  }
  GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                       "sendto");
  return GNUNET_SYSERR;
}


/**
 * Process completed tasks that are in the #done_head queue, sending
 * the result back to the client (and resuming the client).
 *
 * @param cls NULL
 */
static void
handle_done (void *cls)
{
  uint64_t data;
  (void) cls;

  /* consume #done_signal */
  if (sizeof (data) !=
      read (GNUNET_NETWORK_get_fd (done_signal),
            &data,
            sizeof (data)))
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "read(eventfd)");
  done_task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                             done_signal,
                                             &handle_done,
                                             NULL);
  GNUNET_assert (0 == pthread_mutex_lock (&done_lock));
  while (NULL != done_head)
  {
    struct WorkItem *wi = done_head;

    GNUNET_CONTAINER_DLL_remove (done_head,
                                 done_tail,
                                 wi);
    GNUNET_assert (0 == pthread_mutex_unlock (&done_lock));
    if (TALER_EC_NONE != wi->ec)
    {
      struct TALER_CRYPTO_EddsaSignFailure sf = {
        .header.size = htons (sizeof (sf)),
        .header.type = htons (TALER_HELPER_EDDSA_MT_RES_SIGN_FAILURE),
        .ec = htonl (wi->ec)
      };

      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Signing request %p failed, worker failed to produce signature\n",
                  wi);
      (void) transmit (&wi->addr,
                       wi->addr_size,
                       &sf.header);
    }
    else
    {
      struct TALER_CRYPTO_EddsaSignResponse sr = {
        .header.size = htons (sizeof (sr)),
        .header.type = htons (TALER_HELPER_EDDSA_MT_RES_SIGNATURE),
        .exchange_pub = wi->key->exchange_pub,
        .exchange_sig = wi->signature
      };

      (void) transmit (&wi->addr,
                       wi->addr_size,
                       &sr.header);
    }
    {
      struct Key *key = wi->key;

      key->rc--;
      if ( (0 == key->rc) &&
           (key->purge) )
        free_key (key);
    }
    GNUNET_free (wi->purpose);
    GNUNET_free (wi);
    GNUNET_assert (0 == pthread_mutex_lock (&done_lock));
  }
  GNUNET_assert (0 == pthread_mutex_unlock (&done_lock));

}


/**
 * Handle @a client request @a sr to create signature. Create the
 * signature using the respective key and return the result to
 * the client.
 *
 * @param addr address of the client making the request
 * @param addr_size number of bytes in @a addr
 * @param sr the request details
 */
static void
handle_sign_request (const struct sockaddr_un *addr,
                     socklen_t addr_size,
                     const struct TALER_CRYPTO_EddsaSignRequest *sr)
{
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose = &sr->purpose;
  struct WorkItem *wi;
  size_t purpose_size = ntohs (sr->header.size) - sizeof (*sr)
                        + sizeof (*purpose);

  if (purpose_size != htonl (purpose->size))
  {
    struct TALER_CRYPTO_EddsaSignFailure sf = {
      .header.size = htons (sizeof (sr)),
      .header.type = htons (TALER_HELPER_EDDSA_MT_RES_SIGN_FAILURE),
      .ec = htonl (TALER_EC_GENERIC_PARAMETER_MALFORMED)
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Signing request failed, request malformed\n");
    (void) transmit (addr,
                     addr_size,
                     &sf.header);
    return;
  }
  {
    struct GNUNET_TIME_Absolute now;

    now = GNUNET_TIME_absolute_get ();
    if ( (now.abs_value_us >= keys_head->anchor.abs_value_us) &&
         (now.abs_value_us < keys_head->anchor.abs_value_us
          + duration.rel_value_us) )
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Signing at %llu with key valid from %llu to %llu\n",
                  (unsigned long long) now.abs_value_us,
                  (unsigned long long) keys_head->anchor.abs_value_us,
                  (unsigned long long) keys_head->anchor.abs_value_us
                  + duration.rel_value_us);
    else
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Signing at %llu with key valid from %llu to %llu\n",
                  (unsigned long long) now.abs_value_us,
                  (unsigned long long) keys_head->anchor.abs_value_us,
                  (unsigned long long) keys_head->anchor.abs_value_us
                  + duration.rel_value_us);
  }
  wi = GNUNET_new (struct WorkItem);
  wi->addr = *addr;
  wi->addr_size = addr_size;
  wi->key = keys_head;
  keys_head->rc++;
  wi->purpose = GNUNET_memdup (purpose,
                               purpose_size);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received request to sign over %u bytes, queueing as %p\n",
              (unsigned int) purpose_size,
              wi);
  GNUNET_assert (0 == pthread_mutex_lock (&work_lock));
  work_counter++;
  GNUNET_CONTAINER_DLL_insert (work_head,
                               work_tail,
                               wi);
  GNUNET_assert (0 == pthread_cond_signal (&work_cond));
  GNUNET_assert (0 == pthread_mutex_unlock (&work_lock));
}


/**
 * Notify @a client about @a key becoming available.
 *
 * @param[in,out] client the client to notify; possible freed if transmission fails
 * @param key the key to notify @a client about
 * @return #GNUNET_OK on success
 */
static int
notify_client_key_add (struct Client *client,
                       const struct Key *key)
{
  struct TALER_CRYPTO_EddsaKeyAvailableNotification an = {
    .header.size = htons (sizeof (an)),
    .header.type = htons (TALER_HELPER_EDDSA_MT_AVAIL),
    .anchor_time = GNUNET_TIME_absolute_hton (key->anchor),
    .duration = GNUNET_TIME_relative_hton (duration),
    .exchange_pub = key->exchange_pub,
    .secm_pub = smpub
  };

  TALER_exchange_secmod_eddsa_sign (&key->exchange_pub,
                                    key->anchor,
                                    duration,
                                    &smpriv,
                                    &an.secm_sig);
  if (GNUNET_OK !=
      transmit (&client->addr,
                client->addr_size,
                &an.header))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Client %s must have disconnected\n",
                client->addr.sun_path);
    free_client (client);
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
static int
notify_client_key_del (struct Client *client,
                       const struct Key *key)
{
  struct TALER_CRYPTO_EddsaKeyPurgeNotification pn = {
    .header.type = htons (TALER_HELPER_EDDSA_MT_PURGE),
    .header.size = htons (sizeof (pn)),
    .exchange_pub = key->exchange_pub
  };

  if (GNUNET_OK !=
      transmit (&client->addr,
                client->addr_size,
                &pn.header))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Client %s must have disconnected\n",
                client->addr.sun_path);
    free_client (client);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Initialize key material for key @a key (also on disk).
 *
 * @param[in,out] key to compute key material for
 * @param position where in the DLL will the @a key go
 * @return #GNUNET_OK on success
 */
static int
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
  key->exchange_priv.eddsa_priv = priv;
  key->exchange_pub.eddsa_pub = pub;
  GNUNET_CONTAINER_DLL_insert_after (keys_head,
                                     keys_tail,
                                     position,
                                     key);

  /* tell clients about new key */
  {
    struct Client *nxt;

    for (struct Client *client = clients_head;
         NULL != client;
         client = nxt)
    {
      nxt = client->next;
      if (GNUNET_OK !=
          notify_client_key_add (client,
                                 key))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Failed to notify client about new key, client dropped\n");
      }
    }
  }
  return GNUNET_OK;
}


/**
 * A client informs us that a key has been revoked.
 * Check if the key is still in use, and if so replace (!)
 * it with a fresh key.
 *
 * @param addr address of the client making the request
 * @param addr_size number of bytes in @a addr
 * @param rr the revocation request
 */
static void
handle_revoke_request (const struct sockaddr_un *addr,
                       socklen_t addr_size,
                       const struct TALER_CRYPTO_EddsaRevokeRequest *rr)
{
  struct Key *key;
  struct Key *nkey;

  key = NULL;
  for (struct Key *pos = keys_head; NULL != pos; pos = pos->next)
    if (0 == GNUNET_memcmp (&pos->exchange_pub,
                            &rr->exchange_pub))
    {
      key = pos;
      break;
    }
  if (NULL == key)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Revocation request ignored, key unknown\n");
    return;
  }

  /* kill existing key, done first to ensure this always happens */
  if (0 != unlink (key->filename))
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "unlink",
                              key->filename);

  /* Setup replacement key */
  nkey = GNUNET_new (struct Key);
  nkey->anchor = key->anchor;
  if (GNUNET_OK !=
      setup_key (nkey,
                 key))
  {
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = 44;
    return;
  }

  /* get rid of the old key */
  key->purge = true;
  GNUNET_CONTAINER_DLL_remove (keys_head,
                               keys_tail,
                               key);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Revocation complete\n");

  /* Tell clients this key is gone */
  {
    struct Client *nxt;

    for (struct Client *client = clients_head;
         NULL != client;
         client = nxt)
    {
      nxt = client->next;
      if (GNUNET_OK !=
          notify_client_key_del (client,
                                 key))
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Failed to notify client about revoked key, client dropped\n");
    }
  }
  if (0 == key->rc)
    free_key (key);
}


static void
read_job (void *cls)
{
  struct Client *client = cls;
  char buf[65536];
  ssize_t buf_size;
  const struct GNUNET_MessageHeader *hdr;
  struct sockaddr_un addr;
  socklen_t addr_size = sizeof (addr);

  read_task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                             unix_sock,
                                             &read_job,
                                             NULL);
  buf_size = GNUNET_NETWORK_socket_recvfrom (unix_sock,
                                             buf,
                                             sizeof (buf),
                                             (struct sockaddr *) &addr,
                                             &addr_size);
  if (-1 == buf_size)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "recv");
    return;
  }
  if (0 == buf_size)
  {
    return;
  }
  if (buf_size < sizeof (struct GNUNET_MessageHeader))
  {
    GNUNET_break_op (0);
    return;
  }
  hdr = (const struct GNUNET_MessageHeader *) buf;
  if (ntohs (hdr->size) != buf_size)
  {
    GNUNET_break_op (0);
    free_client (client);
    return;
  }
  switch (ntohs (hdr->type))
  {
  case TALER_HELPER_EDDSA_MT_REQ_INIT:
    if (ntohs (hdr->size) != sizeof (struct GNUNET_MessageHeader))
    {
      GNUNET_break_op (0);
      return;
    }
    {
      struct Client *client;

      client = GNUNET_new (struct Client);
      client->addr = addr;
      client->addr_size = addr_size;
      GNUNET_CONTAINER_DLL_insert (clients_head,
                                   clients_tail,
                                   client);
      for (struct Key *key = keys_head;
           NULL != key;
           key = key->next)
      {
        if (GNUNET_OK !=
            notify_client_key_add (client,
                                   key))
        {
          /* client died, skip the rest */
          client = NULL;
          break;
        }
      }
      if (NULL != client)
      {
        struct GNUNET_MessageHeader synced = {
          .type = htons (TALER_HELPER_EDDSA_SYNCED),
          .size = htons (sizeof (synced))
        };

        if (GNUNET_OK !=
            transmit (&client->addr,
                      client->addr_size,
                      &synced))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                      "Client %s must have disconnected\n",
                      client->addr.sun_path);
          free_client (client);
        }
      }
    }
    break;
  case TALER_HELPER_EDDSA_MT_REQ_SIGN:
    if (ntohs (hdr->size) < sizeof (struct TALER_CRYPTO_EddsaSignRequest))
    {
      GNUNET_break_op (0);
      return;
    }
    handle_sign_request (&addr,
                         addr_size,
                         (const struct TALER_CRYPTO_EddsaSignRequest *) buf);
    break;
  case TALER_HELPER_EDDSA_MT_REQ_REVOKE:
    if (ntohs (hdr->size) != sizeof (struct TALER_CRYPTO_EddsaRevokeRequest))
    {
      GNUNET_break_op (0);
      return;
    }
    handle_revoke_request (&addr,
                           addr_size,
                           (const struct
                            TALER_CRYPTO_EddsaRevokeRequest *) buf);
    break;
  default:
    GNUNET_break_op (0);
    return;
  }
}


/**
 * Create a new key (we do not have enough).
 *
 * @return #GNUNET_OK on success
 */
static int
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
    global_ret = 42;
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
 * The validity period of a key @a key has expired. Purge it.
 *
 * @param[in] key expired key to purge and free
 */
static void
purge_key (struct Key *key)
{
  struct Client *nxt;

  for (struct Client *client = clients_head;
       NULL != client;
       client = nxt)
  {
    nxt = client->next;
    if (GNUNET_OK !=
        notify_client_key_del (client,
                               key))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Failed to notify client about purged key, client dropped\n");
    }
  }
  GNUNET_CONTAINER_DLL_remove (keys_head,
                               keys_tail,
                               key);
  if (0 != unlink (key->filename))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "unlink",
                              key->filename);
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Purged expired private key `%s'\n",
                key->filename);
  }
  GNUNET_free (key->filename);
  if (0 != key->rc)
  {
    /* delay until all signing threads are done with this key */
    key->purge = true;
    return;
  }
  GNUNET_free (key);
}


/**
 * Create new keys and expire ancient keys.
 *
 * @param cls NULL
 */
static void
update_keys (void *cls)
{
  (void) cls;

  keygen_task = NULL;
  /* create new keys */
  while ( (NULL == keys_tail) ||
          (0 ==
           GNUNET_TIME_absolute_get_remaining (
             GNUNET_TIME_absolute_subtract (
               GNUNET_TIME_absolute_subtract (
                 GNUNET_TIME_absolute_add (keys_tail->anchor,
                                           duration),
                 lookahead_sign),
               overlap_duration)).rel_value_us) )
  {
    if (GNUNET_OK !=
        create_key ())
    {
      GNUNET_break (0);
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
  }
  /* remove expired keys */
  while ( (NULL != keys_head) &&
          (0 ==
           GNUNET_TIME_absolute_get_remaining
             (GNUNET_TIME_absolute_add (keys_head->anchor,
                                        duration)).rel_value_us) )
    purge_key (keys_head);
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
 */
static void
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
    return;
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
    return;
  }
  anchor.abs_value_us = anchor_ll * GNUNET_TIME_UNIT_SECONDS.rel_value_us;
  if (anchor_ll != anchor.abs_value_us / GNUNET_TIME_UNIT_SECONDS.rel_value_us)
  {
    /* Integer overflow. Bad, invalid filename. */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Filename `%s' invalid for key file, skipping\n",
                filename);
    return;
  }
  if (buf_size != sizeof (priv))
  {
    /* Parser failure. */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "File `%s' is malformed, skipping\n",
                filename);
    return;
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
    key = GNUNET_new (struct Key);
    key->exchange_priv.eddsa_priv = priv;
    key->exchange_pub.eddsa_pub = pub;
    key->anchor = anchor;
    key->filename = GNUNET_strdup (filename);
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
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Imported key from `%s'\n",
                filename);
  }
}


/**
 * Import a private key from @a filename.
 *
 * @param cls NULL
 * @param filename name of a file in the directory
 */
static int
import_key (void *cls,
            const char *filename)
{
  struct GNUNET_DISK_FileHandle *fh;
  struct GNUNET_DISK_MapHandle *map;
  void *ptr;
  int fd;
  struct stat sbuf;

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
  parse_key (filename,
             ptr,
             (size_t) sbuf.st_size);
  GNUNET_DISK_file_unmap (map);
  GNUNET_DISK_file_close (fh);
  return GNUNET_OK;
}


/**
 * Load the various duration values from #kcfg.
 *
 * @return #GNUNET_OK on success
 */
static int
load_durations (void)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
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
      GNUNET_CONFIGURATION_get_value_time (kcfg,
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
      GNUNET_CONFIGURATION_get_value_time (kcfg,
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
  if (NULL != read_task)
  {
    GNUNET_SCHEDULER_cancel (read_task);
    read_task = NULL;
  }
  if (NULL != unix_sock)
  {
    GNUNET_break (GNUNET_OK ==
                  GNUNET_NETWORK_socket_close (unix_sock));
    unix_sock = NULL;
  }
  if (0 != unlink (unixpath))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                              "unlink",
                              unixpath);
  }
  GNUNET_free (unixpath);
  if (NULL != keygen_task)
  {
    GNUNET_SCHEDULER_cancel (keygen_task);
    keygen_task = NULL;
  }
  if (NULL != done_task)
  {
    GNUNET_SCHEDULER_cancel (done_task);
    done_task = NULL;
  }
  /* shut down worker threads */
  if (NULL != workers)
  {
    GNUNET_assert (0 == pthread_mutex_lock (&work_lock));
    in_shutdown = true;
    GNUNET_assert (0 == pthread_cond_broadcast (&work_cond));
    GNUNET_assert (0 == pthread_mutex_unlock (&work_lock));
    for (unsigned int i = 0; i<num_workers; i++)
      GNUNET_assert (0 == pthread_join (workers[i],
                                        NULL));
  }
  if (NULL != done_signal)
  {
    GNUNET_break (GNUNET_OK ==
                  GNUNET_NETWORK_socket_close (done_signal));
    done_signal = NULL;
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
  (void) cls;
  (void) args;
  (void) cfgfile;
  kcfg = cfg;
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

  {
    char *pfn;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                                 "taler-exchange-secmod-eddsa",
                                                 "SM_PRIV_KEY",
                                                 &pfn))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "taler-exchange-secmod-eddsa",
                                 "SM_PRIV_KEY");
      global_ret = 1;
      return;
    }
    if (GNUNET_SYSERR ==
        GNUNET_CRYPTO_eddsa_key_from_file (pfn,
                                           GNUNET_YES,
                                           &smpriv.eddsa_priv))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "taler-exchange-secmod-rsa",
                                 "SM_PRIV_KEY",
                                 "Could not use file to persist private key");
      GNUNET_free (pfn);
      global_ret = 1;
      return;
    }
    GNUNET_free (pfn);
    GNUNET_CRYPTO_eddsa_key_get_public (&smpriv.eddsa_priv,
                                        &smpub.eddsa_pub);
  }

  if (GNUNET_OK !=
      load_durations ())
  {
    global_ret = 1;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "taler-exchange-secmod-eddsa",
                                               "KEY_DIR",
                                               &keydir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-eddsa",
                               "KEY_DIR");
    global_ret = 1;
    return;
  }

  /* Create client directory and set permissions. */
  {
    char *client_dir;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                                 "taler-exchange-secmod-eddsa",
                                                 "CLIENT_DIR",
                                                 &client_dir))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "taler-exchange-secmod-eddsa",
                                 "CLIENT_DIR");
      global_ret = 3;
      return;
    }

    if (GNUNET_OK != GNUNET_DISK_directory_create (client_dir))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Can't create client directory (%s)\n",
                  client_dir);
      global_ret = 3;
      return;
    }
    /* Set sticky group bit, so that clients will be writeable by the current service. */
    if (0 != chmod (client_dir,
                    S_IRUSR | S_IWUSR | S_IXUSR | S_IRGRP | S_IXGRP | S_ISGID))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Can't set permissions for client directory (%s)\n",
                  client_dir);
      global_ret = 3;
      return;
    }

    GNUNET_free (client_dir);
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "taler-exchange-secmod-eddsa",
                                               "UNIXPATH",
                                               &unixpath))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-eddsa",
                               "UNIXPATH");
    global_ret = 3;
    return;
  }

  GNUNET_assert (NULL != unixpath);
  unix_sock = TES_open_socket (unixpath);

  if (NULL == unix_sock)
  {
    GNUNET_free (unixpath);
    global_ret = 2;
    return;
  }

  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);

  /* Load keys */
  GNUNET_break (GNUNET_OK ==
                GNUNET_DISK_directory_create (keydir));
  GNUNET_DISK_directory_scan (keydir,
                              &import_key,
                              NULL);
  /* start job to accept incoming requests on 'sock' */
  read_task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                             unix_sock,
                                             &read_job,
                                             NULL);
  /* start job to keep keys up-to-date; MUST be run before the #read_task,
     hence with priority. */
  keygen_task = GNUNET_SCHEDULER_add_with_priority (
    GNUNET_SCHEDULER_PRIORITY_URGENT,
    &update_keys,
    NULL);

  /* start job to handle completed work */
  {
    int fd;

    fd = eventfd (0,
                  EFD_NONBLOCK | EFD_CLOEXEC);
    if (-1 == fd)
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                           "eventfd");
      global_ret = 6;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    done_signal = GNUNET_NETWORK_socket_box_native (fd);
  }
  done_task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                             done_signal,
                                             &handle_done,
                                             NULL);

  /* start crypto workers */
  if (0 == num_workers)
    num_workers = sysconf (_SC_NPROCESSORS_CONF);
  if (0 == num_workers)
    num_workers = 1;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting %u crypto workers\n",
              num_workers);
  workers = GNUNET_new_array (num_workers,
                              pthread_t);
  for (unsigned int i = 0; i<num_workers; i++)
    GNUNET_assert (0 ==
                   pthread_create (&workers[i],
                                   NULL,
                                   &sign_worker,
                                   NULL));
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
    GNUNET_GETOPT_option_uint ('p',
                               "parallelism",
                               "NUM_WORKERS",
                               "number of worker threads to use",
                               &num_workers),
    GNUNET_GETOPT_option_absolute_time ('t',
                                        "time",
                                        "TIMESTAMP",
                                        "pretend it is a different time for the update",
                                        &now_tmp),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  /* Restrict permissions for the key files that we create. */
  (void) umask (S_IWGRP | S_IROTH | S_IWOTH | S_IXOTH);

  /* force linker to link against libtalerutil; if we do
   not do this, the linker may "optimize" libtalerutil
   away and skip #TALER_OS_init(), which we do need */
  GNUNET_OS_init (TALER_project_data_default ());
  now = now_tmp = GNUNET_TIME_absolute_get ();
  ret = GNUNET_PROGRAM_run (argc, argv,
                            "taler-exchange-secmod-eddsa",
                            "Handle private EDDSA key operations for a Taler exchange",
                            options,
                            &run,
                            NULL);
  if (GNUNET_NO == ret)
    return 0;
  if (GNUNET_SYSERR == ret)
    return 1;
  return global_ret;
}
