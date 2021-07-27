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
 * @file util/taler-exchange-secmod-rsa.c
 * @brief Standalone process to perform private key RSA operations
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
#include "taler-exchange-secmod-rsa.h"
#include <gcrypt.h>
#include <pthread.h>
#include <sys/eventfd.h>
#include "taler_error_codes.h"
#include "taler_signatures.h"
#include "secmod_common.h"


/**
 * Information we keep per denomination.
 */
struct Denomination;


/**
 * One particular denomination key.
 */
struct DenominationKey
{

  /**
   * Kept in a DLL of the respective denomination. Sorted by anchor time.
   */
  struct DenominationKey *next;

  /**
   * Kept in a DLL of the respective denomination. Sorted by anchor time.
   */
  struct DenominationKey *prev;

  /**
   * Denomination this key belongs to.
   */
  struct Denomination *denom;

  /**
   * Name of the file this key is stored under.
   */
  char *filename;

  /**
   * The private key of the denomination.
   */
  struct TALER_DenominationPrivateKey denom_priv;

  /**
   * The public key of the denomination.
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * Hash of this denomination's public key.
   */
  struct GNUNET_HashCode h_denom_pub;

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


struct Denomination
{

  /**
   * Kept in a DLL. Sorted by #denomination_action_time().
   */
  struct Denomination *next;

  /**
   * Kept in a DLL. Sorted by #denomination_action_time().
   */
  struct Denomination *prev;

  /**
   * Head of DLL of actual keys of this denomination.
   */
  struct DenominationKey *keys_head;

  /**
   * Tail of DLL of actual keys of this denomination.
   */
  struct DenominationKey *keys_tail;

  /**
   * How long can coins be withdrawn (generated)?  Should be small
   * enough to limit how many coins will be signed into existence with
   * the same key, but large enough to still provide a reasonable
   * anonymity set.
   */
  struct GNUNET_TIME_Relative duration_withdraw;

  /**
   * What is the configuration section of this denomination type?  Also used
   * for the directory name where the denomination keys are stored.
   */
  char *section;

  /**
   * Length of (new) RSA keys (in bits).
   */
  uint32_t rsa_keysize;
};


/**
 * Actively worked on client request.
 */
struct WorkItem;


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
  struct DenominationKey *dk;

  /**
   * RSA signature over @e blinded_msg using @e dk. Result of doing the
   * work. Initially NULL.
   */
  struct GNUNET_CRYPTO_RsaSignature *rsa_signature;

  /**
   * Coin_ev value to sign.
   */
  void *blinded_msg;

  /**
   * Number of bytes in #blinded_msg.
   */
  size_t blinded_msg_size;

  /**
   * Client address.
   */
  struct sockaddr_un addr;

  /**
   * Number of bytes used in @e addr.
   */
  socklen_t addr_size;

};


/**
 * Return value from main().
 */
static int global_ret;

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
 * How much should coin creation (@e duration_withdraw) duration overlap
 * with the next denomination?  Basically, the starting time of two
 * denominations is always @e duration_withdraw - #overlap_duration apart.
 */
static struct GNUNET_TIME_Relative overlap_duration;

/**
 * How long into the future do we pre-generate keys?
 */
static struct GNUNET_TIME_Relative lookahead_sign;

/**
 * All of our denominations, in a DLL. Sorted?
 */
static struct Denomination *denom_head;

/**
 * All of our denominations, in a DLL. Sorted?
 */
static struct Denomination *denom_tail;

/**
 * Map of hashes of public (RSA) keys to `struct DenominationKey *`
 * with the respective private keys.
 */
static struct GNUNET_CONTAINER_MultiHashMap *keys;

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
      wi->rsa_signature
        = GNUNET_CRYPTO_rsa_sign_blinded (wi->dk->denom_priv.rsa_private_key,
                                          wi->blinded_msg,
                                          wi->blinded_msg_size);
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
 * Free @a dk. It must already have been removed from #keys and the
 * denomination's DLL.
 *
 * @param[in] dk key to free
 */
static void
free_dk (struct DenominationKey *dk)
{
  GNUNET_free (dk->filename);
  GNUNET_CRYPTO_rsa_private_key_free (dk->denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_free (dk->denom_pub.rsa_public_key);
  GNUNET_free (dk);
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
    if (NULL == wi->rsa_signature)
    {
      struct TALER_CRYPTO_SignFailure sf = {
        .header.size = htons (sizeof (sf)),
        .header.type = htons (TALER_HELPER_RSA_MT_RES_SIGN_FAILURE),
        .ec = htonl (TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE)
      };

      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Signing request failed, worker failed to produce signature\n");
      (void) transmit (&wi->addr,
                       wi->addr_size,
                       &sf.header);
    }
    else
    {
      struct TALER_CRYPTO_SignResponse *sr;
      void *buf;
      size_t buf_size;
      size_t tsize;

      buf_size = GNUNET_CRYPTO_rsa_signature_encode (wi->rsa_signature,
                                                     &buf);
      GNUNET_CRYPTO_rsa_signature_free (wi->rsa_signature);
      wi->rsa_signature = NULL;
      tsize = sizeof (*sr) + buf_size;
      GNUNET_assert (tsize < UINT16_MAX);
      sr = GNUNET_malloc (tsize);
      sr->header.size = htons (tsize);
      sr->header.type = htons (TALER_HELPER_RSA_MT_RES_SIGNATURE);
      memcpy (&sr[1],
              buf,
              buf_size);
      GNUNET_free (buf);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Sending RSA signature\n");
      (void) transmit (&wi->addr,
                       wi->addr_size,
                       &sr->header);
      GNUNET_free (sr);
    }
    {
      struct DenominationKey *dk = wi->dk;

      dk->rc--;
      if ( (0 == dk->rc) &&
           (dk->purge) )
        free_dk (dk);
    }
    GNUNET_free (wi->blinded_msg);
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
                     const struct TALER_CRYPTO_SignRequest *sr)
{
  struct DenominationKey *dk;
  struct WorkItem *wi;
  const void *blinded_msg = &sr[1];
  size_t blinded_msg_size = ntohs (sr->header.size) - sizeof (*sr);

  dk = GNUNET_CONTAINER_multihashmap_get (keys,
                                          &sr->h_denom_pub);
  if (NULL == dk)
  {
    struct TALER_CRYPTO_SignFailure sf = {
      .header.size = htons (sizeof (sr)),
      .header.type = htons (TALER_HELPER_RSA_MT_RES_SIGN_FAILURE),
      .ec = htonl (TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN)
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Signing request failed, denomination key %s unknown\n",
                GNUNET_h2s (&sr->h_denom_pub));
    (void) transmit (addr,
                     addr_size,
                     &sf.header);
    return;
  }
  if (0 !=
      GNUNET_TIME_absolute_get_remaining (dk->anchor).rel_value_us)
  {
    /* it is too early */
    struct TALER_CRYPTO_SignFailure sf = {
      .header.size = htons (sizeof (sr)),
      .header.type = htons (TALER_HELPER_RSA_MT_RES_SIGN_FAILURE),
      .ec = htonl (TALER_EC_EXCHANGE_DENOMINATION_HELPER_TOO_EARLY)
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Signing request failed, denomination key %s is not yet valid\n",
                GNUNET_h2s (&sr->h_denom_pub));
    (void) transmit (addr,
                     addr_size,
                     &sf.header);
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received request to sign over %u bytes with key %s\n",
              (unsigned int) blinded_msg_size,
              GNUNET_h2s (&sr->h_denom_pub));
  wi = GNUNET_new (struct WorkItem);
  wi->addr = *addr;
  wi->addr_size = addr_size;
  wi->dk = dk;
  dk->rc++;
  wi->blinded_msg = GNUNET_memdup (blinded_msg,
                                   blinded_msg_size);
  wi->blinded_msg_size = blinded_msg_size;
  GNUNET_assert (0 == pthread_mutex_lock (&work_lock));
  work_counter++;
  GNUNET_CONTAINER_DLL_insert (work_head,
                               work_tail,
                               wi);
  GNUNET_assert (0 == pthread_cond_signal (&work_cond));
  GNUNET_assert (0 == pthread_mutex_unlock (&work_lock));
}


/**
 * Notify @a client about @a dk becoming available.
 *
 * @param[in,out] client the client to notify; possible freed if transmission fails
 * @param dk the key to notify @a client about
 * @return #GNUNET_OK on success
 */
static int
notify_client_dk_add (struct Client *client,
                      const struct DenominationKey *dk)
{
  struct Denomination *denom = dk->denom;
  size_t nlen = strlen (denom->section) + 1;
  struct TALER_CRYPTO_RsaKeyAvailableNotification *an;
  size_t buf_len;
  void *buf;
  void *p;
  size_t tlen;

  buf_len = GNUNET_CRYPTO_rsa_public_key_encode (dk->denom_pub.rsa_public_key,
                                                 &buf);
  GNUNET_assert (buf_len < UINT16_MAX);
  GNUNET_assert (nlen < UINT16_MAX);
  tlen = buf_len + nlen + sizeof (*an);
  GNUNET_assert (tlen < UINT16_MAX);
  an = GNUNET_malloc (tlen);
  an->header.size = htons ((uint16_t) tlen);
  an->header.type = htons (TALER_HELPER_RSA_MT_AVAIL);
  an->pub_size = htons ((uint16_t) buf_len);
  an->section_name_len = htons ((uint16_t) nlen);
  an->anchor_time = GNUNET_TIME_absolute_hton (dk->anchor);
  an->duration_withdraw = GNUNET_TIME_relative_hton (denom->duration_withdraw);
  TALER_exchange_secmod_rsa_sign (&dk->h_denom_pub,
                                  denom->section,
                                  dk->anchor,
                                  denom->duration_withdraw,
                                  &smpriv,
                                  &an->secm_sig);
  an->secm_pub = smpub;
  p = (void *) &an[1];
  memcpy (p,
          buf,
          buf_len);
  GNUNET_free (buf);
  memcpy (p + buf_len,
          denom->section,
          nlen);
  {
    int ret = GNUNET_OK;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Sending RSA denomination key %s (%s)\n",
                GNUNET_h2s (&dk->h_denom_pub),
                denom->section);
    if (GNUNET_OK !=
        transmit (&client->addr,
                  client->addr_size,
                  &an->header))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Client %s must have disconnected\n",
                  client->addr.sun_path);
      free_client (client);
      ret = GNUNET_SYSERR;
    }
    GNUNET_free (an);
    return ret;
  }
}


/**
 * Notify @a client about @a dk being purged.
 *
 * @param[in,out] client the client to notify; possible freed if transmission fails
 * @param dk the key to notify @a client about
 * @return #GNUNET_OK on success
 */
static int
notify_client_dk_del (struct Client *client,
                      const struct DenominationKey *dk)
{
  struct TALER_CRYPTO_RsaKeyPurgeNotification pn = {
    .header.type = htons (TALER_HELPER_RSA_MT_PURGE),
    .header.size = htons (sizeof (pn)),
    .h_denom_pub = dk->h_denom_pub
  };

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Sending RSA denomination expiration %s\n",
              GNUNET_h2s (&dk->h_denom_pub));
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
 * Initialize key material for denomination key @a dk (also on disk).
 *
 * @param[in,out] dk denomination key to compute key material for
 * @param position where in the DLL will the @a dk go
 * @return #GNUNET_OK on success
 */
static int
setup_key (struct DenominationKey *dk,
           struct DenominationKey *position)
{
  struct Denomination *denom = dk->denom;
  struct GNUNET_CRYPTO_RsaPrivateKey *priv;
  struct GNUNET_CRYPTO_RsaPublicKey *pub;
  size_t buf_size;
  void *buf;

  priv = GNUNET_CRYPTO_rsa_private_key_create (denom->rsa_keysize);
  if (NULL == priv)
  {
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = 40;
    return GNUNET_SYSERR;
  }
  pub = GNUNET_CRYPTO_rsa_private_key_get_public (priv);
  if (NULL == pub)
  {
    GNUNET_break (0);
    GNUNET_CRYPTO_rsa_private_key_free (priv);
    return GNUNET_SYSERR;
  }
  buf_size = GNUNET_CRYPTO_rsa_private_key_encode (priv,
                                                   &buf);
  GNUNET_CRYPTO_rsa_public_key_hash (pub,
                                     &dk->h_denom_pub);
  GNUNET_asprintf (&dk->filename,
                   "%s/%s/%llu",
                   keydir,
                   denom->section,
                   (unsigned long long) (dk->anchor.abs_value_us
                                         / GNUNET_TIME_UNIT_SECONDS.rel_value_us));
  if (GNUNET_OK !=
      GNUNET_DISK_fn_write (dk->filename,
                            buf,
                            buf_size,
                            GNUNET_DISK_PERM_USER_READ))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "write",
                              dk->filename);
    GNUNET_free (buf);
    GNUNET_CRYPTO_rsa_private_key_free (priv);
    GNUNET_CRYPTO_rsa_public_key_free (pub);
    return GNUNET_SYSERR;
  }
  GNUNET_free (buf);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Setup fresh private key %s in `%s'\n",
              GNUNET_h2s (&dk->h_denom_pub),
              dk->filename);
  dk->denom_priv.rsa_private_key = priv;
  dk->denom_pub.rsa_public_key = pub;

  if (GNUNET_OK !=
      GNUNET_CONTAINER_multihashmap_put (
        keys,
        &dk->h_denom_pub,
        dk,
        GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Duplicate private key created! Terminating.\n");
    GNUNET_CRYPTO_rsa_private_key_free (dk->denom_priv.rsa_private_key);
    GNUNET_CRYPTO_rsa_public_key_free (dk->denom_pub.rsa_public_key);
    GNUNET_free (dk->filename);
    GNUNET_free (dk);
    return GNUNET_SYSERR;
  }
  GNUNET_CONTAINER_DLL_insert_after (denom->keys_head,
                                     denom->keys_tail,
                                     position,
                                     dk);

  /* tell clients about new key */
  {
    struct Client *nxt;

    for (struct Client *client = clients_head;
         NULL != client;
         client = nxt)
    {
      nxt = client->next;
      if (GNUNET_OK !=
          notify_client_dk_add (client,
                                dk))
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
                       const struct TALER_CRYPTO_RevokeRequest *rr)
{
  struct DenominationKey *dk;
  struct DenominationKey *ndk;
  struct Denomination *denom;

  dk = GNUNET_CONTAINER_multihashmap_get (keys,
                                          &rr->h_denom_pub);
  if (NULL == dk)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Revocation request ignored, denomination key %s unknown\n",
                GNUNET_h2s (&rr->h_denom_pub));
    return;
  }

  /* kill existing key, done first to ensure this always happens */
  if (0 != unlink (dk->filename))
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "unlink",
                              dk->filename);
  /* Setup replacement key */
  denom = dk->denom;
  ndk = GNUNET_new (struct DenominationKey);
  ndk->denom = denom;
  ndk->anchor = dk->anchor;
  if (GNUNET_OK !=
      setup_key (ndk,
                 dk))
  {
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = 44;
    return;
  }

  /* get rid of the old key */
  dk->purge = true;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_remove (
                   keys,
                   &dk->h_denom_pub,
                   dk));
  GNUNET_CONTAINER_DLL_remove (denom->keys_head,
                               denom->keys_tail,
                               dk);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Revocation of denomination key %s complete\n",
              GNUNET_h2s (&rr->h_denom_pub));

  /* Tell clients this key is gone */
  {
    struct Client *nxt;

    for (struct Client *client = clients_head;
         NULL != client;
         client = nxt)
    {
      nxt = client->next;
      if (GNUNET_OK !=
          notify_client_dk_del (client,
                                dk))
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Failed to notify client about revoked key, client dropped\n");
    }
  }
  if (0 == dk->rc)
    free_dk (dk);
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
  case TALER_HELPER_RSA_MT_REQ_INIT:
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
      for (struct Denomination *denom = denom_head;
           NULL != denom;
           denom = denom->next)
      {
        for (struct DenominationKey *dk = denom->keys_head;
             NULL != dk;
             dk = dk->next)
        {
          if (GNUNET_OK !=
              notify_client_dk_add (client,
                                    dk))
          {
            /* client died, skip the rest */
            client = NULL;
            break;
          }
        }
        if (NULL == client)
          break;
      }
      if (NULL != client)
      {
        struct GNUNET_MessageHeader synced = {
          .type = htons (TALER_HELPER_RSA_SYNCED),
          .size = htons (sizeof (synced))
        };

        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Sending RSA SYNCED message\n");
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
  case TALER_HELPER_RSA_MT_REQ_SIGN:
    if (ntohs (hdr->size) <= sizeof (struct TALER_CRYPTO_SignRequest))
    {
      GNUNET_break_op (0);
      return;
    }
    handle_sign_request (&addr,
                         addr_size,
                         (const struct TALER_CRYPTO_SignRequest *) buf);
    break;
  case TALER_HELPER_RSA_MT_REQ_REVOKE:
    if (ntohs (hdr->size) != sizeof (struct TALER_CRYPTO_RevokeRequest))
    {
      GNUNET_break_op (0);
      return;
    }
    handle_revoke_request (&addr,
                           addr_size,
                           (const struct TALER_CRYPTO_RevokeRequest *) buf);
    break;
  default:
    GNUNET_break_op (0);
    return;
  }
}


/**
 * Create a new denomination key (we do not have enough).
 *
 * @param denom denomination key to create
 * @param now current time to use (to get many keys to use the exact same time)
 * @return #GNUNET_OK on success
 */
static int
create_key (struct Denomination *denom,
            struct GNUNET_TIME_Absolute now)
{
  struct DenominationKey *dk;
  struct GNUNET_TIME_Absolute anchor;

  if (NULL == denom->keys_tail)
  {
    anchor = now;
  }
  else
  {
    anchor = GNUNET_TIME_absolute_add (denom->keys_tail->anchor,
                                       GNUNET_TIME_relative_subtract (
                                         denom->duration_withdraw,
                                         overlap_duration));
    if (now.abs_value_us > anchor.abs_value_us)
      anchor = now;
  }
  dk = GNUNET_new (struct DenominationKey);
  dk->denom = denom;
  dk->anchor = anchor;
  if (GNUNET_OK !=
      setup_key (dk,
                 denom->keys_tail))
  {
    GNUNET_free (dk);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = 42;
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * At what time does this denomination require its next action?
 * Basically, the minimum of the withdraw expiration time of the
 * oldest denomination key, and the withdraw expiration time of
 * the newest denomination key minus the #lookahead_sign time.
 *
 * @param denom denomination to compute action time for
 */
static struct GNUNET_TIME_Absolute
denomination_action_time (const struct Denomination *denom)
{
  if (NULL == denom->keys_head)
    return GNUNET_TIME_UNIT_ZERO_ABS;
  return GNUNET_TIME_absolute_min (
    GNUNET_TIME_absolute_add (denom->keys_head->anchor,
                              denom->duration_withdraw),
    GNUNET_TIME_absolute_subtract (
      GNUNET_TIME_absolute_subtract (
        GNUNET_TIME_absolute_add (denom->keys_tail->anchor,
                                  denom->duration_withdraw),
        lookahead_sign),
      overlap_duration));
}


/**
 * The withdraw period of a key @a dk has expired. Purge it.
 *
 * @param[in] dk expired denomination key to purge and free
 */
static void
purge_key (struct DenominationKey *dk)
{
  struct Denomination *denom = dk->denom;
  struct Client *nxt;

  for (struct Client *client = clients_head;
       NULL != client;
       client = nxt)
  {
    nxt = client->next;
    if (GNUNET_OK !=
        notify_client_dk_del (client,
                              dk))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Failed to notify client about purged key, client dropped\n");
    }
  }
  GNUNET_CONTAINER_DLL_remove (denom->keys_head,
                               denom->keys_tail,
                               dk);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_remove (keys,
                                                       &dk->h_denom_pub,
                                                       dk));
  if (0 != unlink (dk->filename))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "unlink",
                              dk->filename);
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Purged expired private key `%s'\n",
                dk->filename);
  }
  GNUNET_free (dk->filename);
  if (0 != dk->rc)
  {
    /* delay until all signing threads are done with this key */
    dk->purge = true;
    return;
  }
  GNUNET_CRYPTO_rsa_private_key_free (dk->denom_priv.rsa_private_key);
  GNUNET_free (dk);
}


/**
 * Create new keys and expire ancient keys of the given denomination @a denom.
 * Removes the @a denom from the #denom_head DLL and re-insert its at the
 * correct location sorted by next maintenance activity.
 *
 * @param[in,out] denom denomination to update material for
 * @param now current time to use (to get many keys to use the exact same time)
 */
static void
update_keys (struct Denomination *denom,
             struct GNUNET_TIME_Absolute now)
{
  /* create new denomination keys */
  while ( (NULL == denom->keys_tail) ||
          (0 ==
           GNUNET_TIME_absolute_get_remaining (
             GNUNET_TIME_absolute_subtract (
               GNUNET_TIME_absolute_subtract (
                 GNUNET_TIME_absolute_add (denom->keys_tail->anchor,
                                           denom->duration_withdraw),
                 lookahead_sign),
               overlap_duration)).rel_value_us) )
    if (GNUNET_OK !=
        create_key (denom,
                    now))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to create keys for `%s'\n",
                  denom->section);
      return;
    }
  /* remove expired denomination keys */
  while ( (NULL != denom->keys_head) &&
          (0 ==
           GNUNET_TIME_absolute_get_remaining
             (GNUNET_TIME_absolute_add (denom->keys_head->anchor,
                                        denom->duration_withdraw)).rel_value_us) )
    purge_key (denom->keys_head);

  /* Update position of 'denom' in #denom_head DLL: sort by action time */
  {
    struct Denomination *before;
    struct GNUNET_TIME_Absolute at;

    at = denomination_action_time (denom);
    GNUNET_CONTAINER_DLL_remove (denom_head,
                                 denom_tail,
                                 denom);
    before = NULL;
    for (struct Denomination *pos = denom_head;
         NULL != pos;
         pos = pos->next)
    {
      if (denomination_action_time (pos).abs_value_us >= at.abs_value_us)
        break;
      before = pos;
    }

    GNUNET_CONTAINER_DLL_insert_after (denom_head,
                                       denom_tail,
                                       before,
                                       denom);
  }
}


/**
 * Task run periodically to expire keys and/or generate fresh ones.
 *
 * @param cls NULL
 */
static void
update_denominations (void *cls)
{
  struct Denomination *denom;
  struct GNUNET_TIME_Absolute now;

  (void) cls;
  keygen_task = NULL;
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  do {
    denom = denom_head;
    update_keys (denom,
                 now);
  } while (denom != denom_head);
  keygen_task = GNUNET_SCHEDULER_add_at (denomination_action_time (denom),
                                         &update_denominations,
                                         NULL);
}


/**
 * Parse private key of denomination @a denom in @a buf.
 *
 * @param[out] denom denomination of the key
 * @param filename name of the file we are parsing, for logging
 * @param buf key material
 * @param buf_size number of bytes in @a buf
 */
static void
parse_key (struct Denomination *denom,
           const char *filename,
           const void *buf,
           size_t buf_size)
{
  struct GNUNET_CRYPTO_RsaPrivateKey *priv;
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
  priv = GNUNET_CRYPTO_rsa_private_key_decode (buf,
                                               buf_size);
  if (NULL == priv)
  {
    /* Parser failure. */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "File `%s' is malformed, skipping\n",
                filename);
    return;
  }

  {
    struct GNUNET_CRYPTO_RsaPublicKey *pub;
    struct DenominationKey *dk;
    struct DenominationKey *before;

    pub = GNUNET_CRYPTO_rsa_private_key_get_public (priv);
    if (NULL == pub)
    {
      GNUNET_break (0);
      GNUNET_CRYPTO_rsa_private_key_free (priv);
      return;
    }
    dk = GNUNET_new (struct DenominationKey);
    dk->denom_priv.rsa_private_key = priv;
    dk->denom = denom;
    dk->anchor = anchor;
    dk->filename = GNUNET_strdup (filename);
    GNUNET_CRYPTO_rsa_public_key_hash (pub,
                                       &dk->h_denom_pub);
    dk->denom_pub.rsa_public_key = pub;
    if (GNUNET_OK !=
        GNUNET_CONTAINER_multihashmap_put (
          keys,
          &dk->h_denom_pub,
          dk,
          GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Duplicate private key %s detected in file `%s'. Skipping.\n",
                  GNUNET_h2s (&dk->h_denom_pub),
                  filename);
      GNUNET_CRYPTO_rsa_private_key_free (priv);
      GNUNET_CRYPTO_rsa_public_key_free (pub);
      GNUNET_free (dk);
      return;
    }
    before = NULL;
    for (struct DenominationKey *pos = denom->keys_head;
         NULL != pos;
         pos = pos->next)
    {
      if (pos->anchor.abs_value_us > anchor.abs_value_us)
        break;
      before = pos;
    }
    GNUNET_CONTAINER_DLL_insert_after (denom->keys_head,
                                       denom->keys_tail,
                                       before,
                                       dk);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Imported key %s from `%s'\n",
                GNUNET_h2s (&dk->h_denom_pub),
                filename);
  }
}


/**
 * Import a private key from @a filename for the denomination
 * given in @a cls.
 *
 * @param[in,out] cls a `struct Denomiantion`
 * @param filename name of a file in the directory
 */
static int
import_key (void *cls,
            const char *filename)
{
  struct Denomination *denom = cls;
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
  parse_key (denom,
             filename,
             ptr,
             (size_t) sbuf.st_size);
  GNUNET_DISK_file_unmap (map);
  GNUNET_DISK_file_close (fh);
  return GNUNET_OK;
}


/**
 * Parse configuration for denomination type parameters.  Also determines
 * our anchor by looking at the existing denominations of the same type.
 *
 * @param ct section in the configuration file giving the denomination type parameters
 * @param[out] denom set to the denomination parameters from the configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if the configuration is invalid
 */
static int
parse_denomination_cfg (const char *ct,
                        struct Denomination *denom)
{
  unsigned long long rsa_keysize;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           ct,
                                           "DURATION_WITHDRAW",
                                           &denom->duration_withdraw))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "DURATION_WITHDRAW");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&denom->duration_withdraw);
  if (overlap_duration.rel_value_us >=
      denom->duration_withdraw.rel_value_us)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-rsa",
                               "OVERLAP_DURATION",
                               "Value given must be smaller than value for DURATION_WITHDRAW!");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (kcfg,
                                             ct,
                                             "RSA_KEYSIZE",
                                             &rsa_keysize))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "RSA_KEYSIZE");
    return GNUNET_SYSERR;
  }
  if ( (rsa_keysize > 4 * 2048) ||
       (rsa_keysize < 1024) )
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "RSA_KEYSIZE",
                               "Given RSA keysize outside of permitted range [1024,8192]\n");
    return GNUNET_SYSERR;
  }
  denom->rsa_keysize = (unsigned int) rsa_keysize;
  denom->section = GNUNET_strdup (ct);
  return GNUNET_OK;
}


/**
 * Closure for #load_denominations.
 */
struct LoadContext
{
  /**
   * Current time to use.
   */
  struct GNUNET_TIME_Absolute now;

  /**
   * Status, to be set to #GNUNET_SYSERR on failure
   */
  int ret;
};


/**
 * Generate new denomination signing keys for the denomination type of the given @a
 * denomination_alias.
 *
 * @param cls a `struct LoadContext`, with 'ret' to be set to #GNUNET_SYSERR on failure
 * @param denomination_alias name of the denomination's section in the configuration
 */
static void
load_denominations (void *cls,
                    const char *denomination_alias)
{
  struct LoadContext *ctx = cls;
  struct Denomination *denom;

  if (0 != strncasecmp (denomination_alias,
                        "coin_",
                        strlen ("coin_")))
    return; /* not a denomination type definition */
  denom = GNUNET_new (struct Denomination);
  if (GNUNET_OK !=
      parse_denomination_cfg (denomination_alias,
                              denom))
  {
    ctx->ret = GNUNET_SYSERR;
    GNUNET_free (denom);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Loading keys for denomination %s\n",
              denom->section);
  {
    char *dname;

    GNUNET_asprintf (&dname,
                     "%s/%s",
                     keydir,
                     denom->section);
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_directory_create (dname));
    GNUNET_DISK_directory_scan (dname,
                                &import_key,
                                denom);
    GNUNET_free (dname);
  }
  GNUNET_CONTAINER_DLL_insert (denom_head,
                               denom_tail,
                               denom);
  update_keys (denom,
               ctx->now);
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
                                           "taler-exchange-secmod-rsa",
                                           "OVERLAP_DURATION",
                                           &overlap_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-rsa",
                               "OVERLAP_DURATION");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&overlap_duration);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "taler-exchange-secmod-rsa",
                                           "LOOKAHEAD_SIGN",
                                           &lookahead_sign))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-rsa",
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
                                                 "taler-exchange-secmod-rsa",
                                                 "SM_PRIV_KEY",
                                                 &pfn))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "taler-exchange-secmod-rsa",
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
                                               "taler-exchange-secmod-rsa",
                                               "KEY_DIR",
                                               &keydir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-rsa",
                               "KEY_DIR");
    global_ret = 1;
    return;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "taler-exchange-secmod-rsa",
                                               "UNIXPATH",
                                               &unixpath))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler-exchange-secmod-rsa",
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

  /* Load denominations */
  keys = GNUNET_CONTAINER_multihashmap_create (65536,
                                               GNUNET_YES);
  {
    struct LoadContext lc = {
      .ret = GNUNET_OK,
      .now = GNUNET_TIME_absolute_get ()
    };

    (void) GNUNET_TIME_round_abs (&lc.now);
    GNUNET_CONFIGURATION_iterate_sections (kcfg,
                                           &load_denominations,
                                           &lc);
    if (GNUNET_OK != lc.ret)
    {
      global_ret = 4;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
  }
  if (NULL == denom_head)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No denominations configured\n");
    global_ret = 5;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  /* start job to accept incoming requests on 'sock' */
  read_task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                             unix_sock,
                                             &read_job,
                                             NULL);
  /* start job to keep keys up-to-date; MUST be run before the #read_task,
     hence with priority. */
  keygen_task = GNUNET_SCHEDULER_add_with_priority (
    GNUNET_SCHEDULER_PRIORITY_URGENT,
    &update_denominations,
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

  (void) umask (S_IWGRP | S_IROTH | S_IWOTH | S_IXOTH);
  /* force linker to link against libtalerutil; if we do
   not do this, the linker may "optimize" libtalerutil
   away and skip #TALER_OS_init(), which we do need */
  GNUNET_OS_init (TALER_project_data_default ());
  now = now_tmp = GNUNET_TIME_absolute_get ();
  ret = GNUNET_PROGRAM_run (argc, argv,
                            "taler-exchange-secmod-rsa",
                            "Handle private RSA key operations for a Taler exchange",
                            options,
                            &run,
                            NULL);
  if (GNUNET_NO == ret)
    return 0;
  if (GNUNET_SYSERR == ret)
    return 1;
  return global_ret;
}
