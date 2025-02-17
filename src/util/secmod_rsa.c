/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
 * @file util/secmod_rsa.c
 * @brief Standalone process to perform private key RSA operations
 * @author Christian Grothoff
 *
 * Key design points:
 * - EVERY thread of the exchange will have its own pair of connections to the
 *   crypto helpers.  This way, every thread will also have its own /keys state
 *   and avoid the need to synchronize on those.
 * - auditor signatures and master signatures are to be kept in the exchange DB,
 *   and merged with the public keys of the helper by the exchange HTTPD!
 * - the main loop of the helper is SINGLE-THREADED, but there are
 *   threads for crypto-workers which do the signing in parallel, one per client.
 * - thread-safety: signing happens in parallel, thus when REMOVING private keys,
 *   we must ensure that all signers are done before we fully free() the
 *   private key. This is done by reference counting (as work is always
 *   assigned and collected by the main thread).
 */
#include "platform.h"
#include "taler_util.h"
#include "secmod_rsa.h"
#include <gcrypt.h>
#include <pthread.h>
#include "taler_error_codes.h"
#include "taler_signatures.h"
#include "secmod_common.h"
#include <poll.h>


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
  struct GNUNET_CRYPTO_RsaPrivateKey *denom_priv;

  /**
   * The public key of the denomination.
   */
  struct GNUNET_CRYPTO_RsaPublicKey *denom_pub;

  /**
   * Message to transmit to clients to introduce this public key.
   */
  struct TALER_CRYPTO_RsaKeyAvailableNotification *an;

  /**
   * Hash of this denomination's public key.
   */
  struct TALER_RsaPubHashP h_rsa;

  /**
   * Time at which this key is supposed to become valid.
   */
  struct GNUNET_TIME_Timestamp anchor;

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
 * A semaphore.
 */
struct Semaphore
{
  /**
   * Mutex for the semaphore.
   */
  pthread_mutex_t mutex;

  /**
   * Condition variable for the semaphore.
   */
  pthread_cond_t cv;

  /**
   * Counter of the semaphore.
   */
  unsigned int ctr;
};


/**
 * Job in a batch sign request.
 */
struct BatchJob;

/**
 * Handle for a thread that does work in batch signing.
 */
struct Worker
{
  /**
   * Kept in a DLL.
   */
  struct Worker *prev;

  /**
   * Kept in a DLL.
   */
  struct Worker *next;

  /**
   * Job this worker should do next.
   */
  struct BatchJob *job;

  /**
   * Semaphore to signal the worker that a job is available.
   */
  struct Semaphore sem;

  /**
   * Handle for this thread.
   */
  pthread_t pt;

  /**
   * Set to true if the worker should terminate.
   */
  bool do_shutdown;
};


/**
 * Job in a batch sign request.
 */
struct BatchJob
{
  /**
   * Request we are working on.
   */
  const struct TALER_CRYPTO_SignRequest *sr;

  /**
   * Thread doing the work.
   */
  struct Worker *worker;

  /**
   * Result with the signature.
   */
  struct GNUNET_CRYPTO_RsaSignature *rsa_signature;

  /**
   * Semaphore to signal that the job is finished.
   */
  struct Semaphore sem;

  /**
   * Computation status.
   */
  enum TALER_ErrorCode ec;

};


/**
 * Head of DLL of workers ready for more work.
 */
static struct Worker *worker_head;

/**
 * Tail of DLL of workers ready for more work.
 */
static struct Worker *worker_tail;

/**
 * Lock for manipulating the worker DLL.
 */
static pthread_mutex_t worker_lock;

/**
 * Total number of workers that were started.
 */
static unsigned int workers;

/**
 * Semaphore used to grab a worker.
 */
static struct Semaphore worker_sem;

/**
 * Command-line options for various TALER_SECMOD_XXX_run() functions.
 */
static struct TALER_SECMOD_Options *globals;

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
 * Generate the announcement message for @a dk.
 *
 * @param[in,out] dk denomination key to generate the announcement for
 */
static void
generate_response (struct DenominationKey *dk)
{
  struct Denomination *denom = dk->denom;
  size_t nlen = strlen (denom->section) + 1;
  struct TALER_CRYPTO_RsaKeyAvailableNotification *an;
  size_t buf_len;
  void *buf;
  void *p;
  size_t tlen;

  buf_len = GNUNET_CRYPTO_rsa_public_key_encode (dk->denom_pub,
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
  an->anchor_time = GNUNET_TIME_timestamp_hton (dk->anchor);
  an->duration_withdraw = GNUNET_TIME_relative_hton (denom->duration_withdraw);
  TALER_exchange_secmod_rsa_sign (&dk->h_rsa,
                                  denom->section,
                                  dk->anchor,
                                  denom->duration_withdraw,
                                  &TES_smpriv,
                                  &an->secm_sig);
  an->secm_pub = TES_smpub;
  p = (void *) &an[1];
  GNUNET_memcpy (p,
                 buf,
                 buf_len);
  GNUNET_free (buf);
  GNUNET_memcpy (p + buf_len,
                 denom->section,
                 nlen);
  dk->an = an;
}


/**
 * Do the actual signing work.
 *
 * @param h_rsa key to sign with
 * @param bm blinded message to sign
 * @param[out] rsa_signaturep set to the RSA signature
 * @return #TALER_EC_NONE on success
 */
static enum TALER_ErrorCode
do_sign (const struct TALER_RsaPubHashP *h_rsa,
         const struct GNUNET_CRYPTO_RsaBlindedMessage *bm,
         struct GNUNET_CRYPTO_RsaSignature **rsa_signaturep)
{
  struct DenominationKey *dk;
  struct GNUNET_CRYPTO_RsaSignature *rsa_signature;
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();

  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  dk = GNUNET_CONTAINER_multihashmap_get (keys,
                                          &h_rsa->hash);
  if (NULL == dk)
  {
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Signing request failed, denomination key %s unknown\n",
                GNUNET_h2s (&h_rsa->hash));
    return TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN;
  }
  if (GNUNET_TIME_absolute_is_future (dk->anchor.abs_time))
  {
    /* it is too early */
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Signing request failed, denomination key %s is not yet valid\n",
                GNUNET_h2s (&h_rsa->hash));
    return TALER_EC_EXCHANGE_DENOMINATION_HELPER_TOO_EARLY;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received request to sign over %u bytes with key %s\n",
              (unsigned int) bm->blinded_msg_size,
              GNUNET_h2s (&h_rsa->hash));
  GNUNET_assert (dk->rc < UINT_MAX);
  dk->rc++;
  GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
  rsa_signature
    = GNUNET_CRYPTO_rsa_sign_blinded (dk->denom_priv,
                                      bm);
  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  GNUNET_assert (dk->rc > 0);
  dk->rc--;
  GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
  if (NULL == rsa_signature)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Signing request failed, worker failed to produce signature\n");
    return TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Sending RSA signature after %s\n",
              GNUNET_TIME_relative2s (
                GNUNET_TIME_absolute_get_duration (now),
                GNUNET_YES));
  *rsa_signaturep = rsa_signature;
  return TALER_EC_NONE;
}


/**
 * Generate error response that signing failed.
 *
 * @param client client to send response to
 * @param ec error code to include
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
fail_sign (struct TES_Client *client,
           enum TALER_ErrorCode ec)
{
  struct TALER_CRYPTO_SignFailure sf = {
    .header.size = htons (sizeof (sf)),
    .header.type = htons (TALER_HELPER_RSA_MT_RES_SIGN_FAILURE),
    .ec = htonl (ec)
  };

  return TES_transmit (client->csock,
                       &sf.header);
}


/**
 * Generate signature response.
 *
 * @param client client to send response to
 * @param[in] rsa_signature signature to send, freed by this function
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
send_signature (struct TES_Client *client,
                struct GNUNET_CRYPTO_RsaSignature *rsa_signature)
{
  struct TALER_CRYPTO_SignResponse *sr;
  void *buf;
  size_t buf_size;
  size_t tsize;
  enum GNUNET_GenericReturnValue ret;

  buf_size = GNUNET_CRYPTO_rsa_signature_encode (rsa_signature,
                                                 &buf);
  GNUNET_CRYPTO_rsa_signature_free (rsa_signature);
  tsize = sizeof (*sr) + buf_size;
  GNUNET_assert (tsize < UINT16_MAX);
  sr = GNUNET_malloc (tsize);
  sr->header.size = htons (tsize);
  sr->header.type = htons (TALER_HELPER_RSA_MT_RES_SIGNATURE);
  GNUNET_memcpy (&sr[1],
                 buf,
                 buf_size);
  GNUNET_free (buf);
  ret = TES_transmit (client->csock,
                      &sr->header);
  GNUNET_free (sr);
  return ret;
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
                     const struct TALER_CRYPTO_SignRequest *sr)
{
  struct GNUNET_CRYPTO_RsaBlindedMessage bm = {
    .blinded_msg = (void *) &sr[1],
    .blinded_msg_size = ntohs (sr->header.size) - sizeof (*sr)
  };
  struct GNUNET_CRYPTO_RsaSignature *rsa_signature;
  enum TALER_ErrorCode ec;

  ec = do_sign (&sr->h_rsa,
                &bm,
                &rsa_signature);
  if (TALER_EC_NONE != ec)
  {
    return fail_sign (client,
                      ec);
  }
  return send_signature (client,
                         rsa_signature);
}


/**
 * Initialize a semaphore @a sem with a value of @a val.
 *
 * @param[out] sem semaphore to initialize
 * @param val initial value of the semaphore
 */
static void
sem_init (struct Semaphore *sem,
          unsigned int val)
{
  GNUNET_assert (0 ==
                 pthread_mutex_init (&sem->mutex,
                                     NULL));
  GNUNET_assert (0 ==
                 pthread_cond_init (&sem->cv,
                                    NULL));
  sem->ctr = val;
}


/**
 * Decrement semaphore, blocks until this is possible.
 *
 * @param[in,out] sem semaphore to decrement
 */
static void
sem_down (struct Semaphore *sem)
{
  GNUNET_assert (0 == pthread_mutex_lock (&sem->mutex));
  while (0 == sem->ctr)
  {
    pthread_cond_wait (&sem->cv,
                       &sem->mutex);
  }
  sem->ctr--;
  GNUNET_assert (0 == pthread_mutex_unlock (&sem->mutex));
}


/**
 * Increment semaphore, blocks until this is possible.
 *
 * @param[in,out] sem semaphore to decrement
 */
static void
sem_up (struct Semaphore *sem)
{
  GNUNET_assert (0 == pthread_mutex_lock (&sem->mutex));
  sem->ctr++;
  GNUNET_assert (0 == pthread_mutex_unlock (&sem->mutex));
  pthread_cond_signal (&sem->cv);
}


/**
 * Release resources used by @a sem.
 *
 * @param[in] sem semaphore to release (except the memory itself)
 */
static void
sem_done (struct Semaphore *sem)
{
  GNUNET_break (0 == pthread_cond_destroy (&sem->cv));
  GNUNET_break (0 == pthread_mutex_destroy (&sem->mutex));
}


/**
 * Main logic of a worker thread. Grabs work, does it,
 * grabs more work.
 *
 * @param cls a `struct Worker *`
 * @returns cls
 */
static void *
worker (void *cls)
{
  struct Worker *w = cls;

  while (true)
  {
    GNUNET_assert (0 == pthread_mutex_lock (&worker_lock));
    GNUNET_CONTAINER_DLL_insert (worker_head,
                                 worker_tail,
                                 w);
    GNUNET_assert (0 == pthread_mutex_unlock (&worker_lock));
    sem_up (&worker_sem);
    sem_down (&w->sem);
    if (w->do_shutdown)
      break;
    {
      struct BatchJob *bj = w->job;
      const struct TALER_CRYPTO_SignRequest *sr = bj->sr;
      struct GNUNET_CRYPTO_RsaBlindedMessage bm = {
        .blinded_msg = (void *) &sr[1],
        .blinded_msg_size = ntohs (sr->header.size) - sizeof (*sr)
      };

      bj->ec = do_sign (&sr->h_rsa,
                        &bm,
                        &bj->rsa_signature);
      sem_up (&bj->sem);
      w->job = NULL;
    }
  }
  return w;
}


/**
 * Start batch job @a bj to sign @a sr.
 *
 * @param sr signature request to answer
 * @param[out] bj job data structure
 */
static void
start_job (const struct TALER_CRYPTO_SignRequest *sr,
           struct BatchJob *bj)
{
  sem_init (&bj->sem,
            0);
  bj->sr = sr;
  sem_down (&worker_sem);
  GNUNET_assert (0 == pthread_mutex_lock (&worker_lock));
  bj->worker = worker_head;
  GNUNET_CONTAINER_DLL_remove (worker_head,
                               worker_tail,
                               bj->worker);
  GNUNET_assert (0 == pthread_mutex_unlock (&worker_lock));
  bj->worker->job = bj;
  sem_up (&bj->worker->sem);
}


/**
 * Finish a job @a bj for a @a client.
 *
 * @param client who made the request
 * @param[in,out] bj job to finish
 */
static void
finish_job (struct TES_Client *client,
            struct BatchJob *bj)
{
  sem_down (&bj->sem);
  sem_done (&bj->sem);
  if (TALER_EC_NONE != bj->ec)
  {
    fail_sign (client,
               bj->ec);
    return;
  }
  GNUNET_assert (NULL != bj->rsa_signature);
  send_signature (client,
                  bj->rsa_signature);
  bj->rsa_signature = NULL; /* freed in send_signature */
}


/**
 * Handle @a client request @a sr to create a batch of signature. Creates the
 * signatures using the respective key and return the results to the client.
 *
 * @param client the client making the request
 * @param bsr the request details
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_batch_sign_request (struct TES_Client *client,
                           const struct TALER_CRYPTO_BatchSignRequest *bsr)
{
  uint32_t bs = ntohl (bsr->batch_size);
  uint16_t size = ntohs (bsr->header.size) - sizeof (*bsr);
  const void *off = (const void *) &bsr[1];
  unsigned int idx = 0;
  struct BatchJob jobs[bs];
  bool failure = false;

  if (bs > TALER_MAX_FRESH_COINS)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  while ( (bs > 0) &&
          (size > sizeof (struct TALER_CRYPTO_SignRequest)) )
  {
    const struct TALER_CRYPTO_SignRequest *sr = off;
    uint16_t s = ntohs (sr->header.size);

    if (s > size)
    {
      failure = true;
      bs = idx;
      break;
    }
    start_job (sr,
               &jobs[idx++]);
    off += s;
    size -= s;
  }
  GNUNET_break_op (0 == size);
  bs = GNUNET_MIN (bs,
                   idx);
  for (unsigned int i = 0; i<bs; i++)
    finish_job (client,
                &jobs[i]);
  if (failure)
  {
    struct TALER_CRYPTO_SignFailure sf = {
      .header.size = htons (sizeof (sf)),
      .header.type = htons (TALER_HELPER_RSA_MT_RES_BATCH_FAILURE),
      .ec = htonl (TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE)
    };

    GNUNET_break (0);
    return TES_transmit (client->csock,
                         &sf.header);
  }
  return GNUNET_OK;
}


/**
 * Start worker thread for batch processing.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
start_worker (void)
{
  struct Worker *w;

  w = GNUNET_new (struct Worker);
  sem_init (&w->sem,
            0);
  if (0 != pthread_create (&w->pt,
                           NULL,
                           &worker,
                           w))
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "pthread_create");
    GNUNET_free (w);
    return GNUNET_SYSERR;
  }
  workers++;
  return GNUNET_OK;
}


/**
 * Stop all worker threads.
 */
static void
stop_workers (void)
{
  while (workers > 0)
  {
    struct Worker *w;
    void *result;

    sem_down (&worker_sem);
    GNUNET_assert (0 == pthread_mutex_lock (&worker_lock));
    w = worker_head;
    GNUNET_CONTAINER_DLL_remove (worker_head,
                                 worker_tail,
                                 w);
    GNUNET_assert (0 == pthread_mutex_unlock (&worker_lock));
    w->do_shutdown = true;
    sem_up (&w->sem);
    pthread_join (w->pt,
                  &result);
    GNUNET_assert (result == w);
    sem_done (&w->sem);
    GNUNET_free (w);
    workers--;
  }
}


/**
 * Initialize key material for denomination key @a dk (also on disk).
 *
 * @param[in,out] dk denomination key to compute key material for
 * @param position where in the DLL will the @a dk go
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
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
    globals->global_ret = EXIT_FAILURE;
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
                                     &dk->h_rsa.hash);
  GNUNET_asprintf (&dk->filename,
                   "%s/%s/%llu",
                   keydir,
                   denom->section,
                   (unsigned long long) (dk->anchor.abs_time.abs_value_us
                                         / GNUNET_TIME_UNIT_SECONDS.rel_value_us
                                         ));
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
              "Setup fresh private key %s at %s in `%s' (generation #%llu)\n",
              GNUNET_h2s (&dk->h_rsa.hash),
              GNUNET_TIME_timestamp2s (dk->anchor),
              dk->filename,
              (unsigned long long) key_gen);
  dk->denom_priv = priv;
  dk->denom_pub = pub;
  dk->key_gen = key_gen;
  generate_response (dk);
  if (GNUNET_OK !=
      GNUNET_CONTAINER_multihashmap_put (
        keys,
        &dk->h_rsa.hash,
        dk,
        GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Duplicate private key created! Terminating.\n");
    GNUNET_CRYPTO_rsa_private_key_free (dk->denom_priv);
    GNUNET_CRYPTO_rsa_public_key_free (dk->denom_pub);
    GNUNET_free (dk->filename);
    GNUNET_free (dk->an);
    GNUNET_free (dk);
    return GNUNET_SYSERR;
  }
  GNUNET_CONTAINER_DLL_insert_after (denom->keys_head,
                                     denom->keys_tail,
                                     position,
                                     dk);
  return GNUNET_OK;
}


/**
 * The withdraw period of a key @a dk has expired. Purge it.
 *
 * @param[in] dk expired denomination key to purge
 */
static void
purge_key (struct DenominationKey *dk)
{
  if (dk->purge)
    return;
  if (0 != unlink (dk->filename))
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "unlink",
                              dk->filename);
  GNUNET_free (dk->filename);
  dk->purge = true;
  dk->key_gen = key_gen;
}


/**
 * A @a client informs us that a key has been revoked.
 * Check if the key is still in use, and if so replace (!)
 * it with a fresh key.
 *
 * @param client the client making the request
 * @param rr the revocation request
 */
static enum GNUNET_GenericReturnValue
handle_revoke_request (struct TES_Client *client,
                       const struct TALER_CRYPTO_RevokeRequest *rr)
{
  struct DenominationKey *dk;
  struct DenominationKey *ndk;
  struct Denomination *denom;

  (void) client;
  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  dk = GNUNET_CONTAINER_multihashmap_get (keys,
                                          &rr->h_rsa.hash);
  if (NULL == dk)
  {
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Revocation request ignored, denomination key %s unknown\n",
                GNUNET_h2s (&rr->h_rsa.hash));
    return GNUNET_OK;
  }
  if (dk->purge)
  {
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Revocation request ignored, denomination key %s already revoked\n",
                GNUNET_h2s (&rr->h_rsa.hash));
    return GNUNET_OK;
  }

  key_gen++;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Revoking key %s, bumping generation to %llu\n",
              GNUNET_h2s (&rr->h_rsa.hash),
              (unsigned long long) key_gen);
  purge_key (dk);

  /* Setup replacement key */
  denom = dk->denom;
  ndk = GNUNET_new (struct DenominationKey);
  ndk->denom = denom;
  ndk->anchor = dk->anchor;
  if (GNUNET_OK !=
      setup_key (ndk,
                 dk))
  {
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    globals->global_ret = EXIT_FAILURE;
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
rsa_work_dispatch (struct TES_Client *client,
                   const struct GNUNET_MessageHeader *hdr)
{
  uint16_t msize = ntohs (hdr->size);

  switch (ntohs (hdr->type))
  {
  case TALER_HELPER_RSA_MT_REQ_SIGN:
    if (msize <= sizeof (struct TALER_CRYPTO_SignRequest))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    return handle_sign_request (
      client,
      (const struct TALER_CRYPTO_SignRequest *) hdr);
  case TALER_HELPER_RSA_MT_REQ_REVOKE:
    if (msize != sizeof (struct TALER_CRYPTO_RevokeRequest))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    return handle_revoke_request (
      client,
      (const struct TALER_CRYPTO_RevokeRequest *) hdr);
  case TALER_HELPER_RSA_MT_REQ_BATCH_SIGN:
    if (msize <= sizeof (struct TALER_CRYPTO_BatchSignRequest))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    return handle_batch_sign_request (
      client,
      (const struct TALER_CRYPTO_BatchSignRequest *) hdr);
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
rsa_client_init (struct TES_Client *client)
{
  size_t obs = 0;
  char *buf;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Initializing new client %p\n",
              client);
  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  for (struct Denomination *denom = denom_head;
       NULL != denom;
       denom = denom->next)
  {
    for (struct DenominationKey *dk = denom->keys_head;
         NULL != dk;
         dk = dk->next)
    {
      GNUNET_assert (obs + ntohs (dk->an->header.size)
                     > obs);
      obs += ntohs (dk->an->header.size);
    }
  }
  buf = GNUNET_malloc (obs);
  obs = 0;
  for (struct Denomination *denom = denom_head;
       NULL != denom;
       denom = denom->next)
  {
    for (struct DenominationKey *dk = denom->keys_head;
         NULL != dk;
         dk = dk->next)
    {
      GNUNET_memcpy (&buf[obs],
                     dk->an,
                     ntohs (dk->an->header.size));
      GNUNET_assert (obs + ntohs (dk->an->header.size)
                     > obs);
      obs += ntohs (dk->an->header.size);
    }
  }
  client->key_gen = key_gen;
  GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
  if (GNUNET_OK !=
      TES_transmit_raw (client->csock,
                        obs,
                        buf))
  {
    GNUNET_free (buf);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Client %p must have disconnected\n",
                client);
    return GNUNET_SYSERR;
  }
  GNUNET_free (buf);
  {
    struct GNUNET_MessageHeader synced = {
      .type = htons (TALER_HELPER_RSA_SYNCED),
      .size = htons (sizeof (synced))
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Sending RSA SYNCED message to %p\n",
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
rsa_update_client_keys (struct TES_Client *client)
{
  size_t obs = 0;
  char *buf;
  enum GNUNET_GenericReturnValue ret;

  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  for (struct Denomination *denom = denom_head;
       NULL != denom;
       denom = denom->next)
  {
    for (struct DenominationKey *key = denom->keys_head;
         NULL != key;
         key = key->next)
    {
      if (key->key_gen <= client->key_gen)
        continue;
      if (key->purge)
        obs += sizeof (struct TALER_CRYPTO_RsaKeyPurgeNotification);
      else
        obs += ntohs (key->an->header.size);
    }
  }
  if (0 == obs)
  {
    /* nothing to do */
    client->key_gen = key_gen;
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
    return GNUNET_OK;
  }
  buf = GNUNET_malloc (obs);
  obs = 0;
  for (struct Denomination *denom = denom_head;
       NULL != denom;
       denom = denom->next)
  {
    for (struct DenominationKey *key = denom->keys_head;
         NULL != key;
         key = key->next)
    {
      if (key->key_gen <= client->key_gen)
        continue;
      if (key->purge)
      {
        struct TALER_CRYPTO_RsaKeyPurgeNotification pn = {
          .header.type = htons (TALER_HELPER_RSA_MT_PURGE),
          .header.size = htons (sizeof (pn)),
          .h_rsa = key->h_rsa
        };

        GNUNET_memcpy (&buf[obs],
                       &pn,
                       sizeof (pn));
        GNUNET_assert (obs + sizeof (pn)
                       > obs);
        obs += sizeof (pn);
      }
      else
      {
        GNUNET_memcpy (&buf[obs],
                       key->an,
                       ntohs (key->an->header.size));
        GNUNET_assert (obs + ntohs (key->an->header.size)
                       > obs);
        obs += ntohs (key->an->header.size);
      }
    }
  }
  client->key_gen = key_gen;
  GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
  ret = TES_transmit_raw (client->csock,
                          obs,
                          buf);
  GNUNET_free (buf);
  return ret;
}


/**
 * Create a new denomination key (we do not have enough).
 *
 * @param denom denomination key to create
 * @param now current time to use (to get many keys to use the exact same time)
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
create_key (struct Denomination *denom,
            struct GNUNET_TIME_Timestamp now)
{
  struct DenominationKey *dk;
  struct GNUNET_TIME_Timestamp anchor;

  anchor = now;
  // FIXME: round down to multiple of 'anchor_round' value from configuration
  if (NULL != denom->keys_tail)
  {
    struct GNUNET_TIME_Absolute abs;

    abs = GNUNET_TIME_absolute_add (denom->keys_tail->anchor.abs_time,
                                    GNUNET_TIME_relative_subtract (
                                      denom->duration_withdraw,
                                      overlap_duration));
    if (GNUNET_TIME_absolute_cmp (now.abs_time, <, abs))
      anchor = GNUNET_TIME_absolute_to_timestamp (abs);
  }
  dk = GNUNET_new (struct DenominationKey);
  dk->denom = denom;
  dk->anchor = anchor;
  if (GNUNET_OK !=
      setup_key (dk,
                 denom->keys_tail))
  {
    GNUNET_break (0);
    GNUNET_free (dk);
    GNUNET_SCHEDULER_shutdown ();
    globals->global_ret = EXIT_FAILURE;
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
  struct DenominationKey *head = denom->keys_head;
  struct DenominationKey *tail = denom->keys_tail;
  struct GNUNET_TIME_Absolute tt;

  if (NULL == head)
    return GNUNET_TIME_UNIT_ZERO_ABS;
  tt = GNUNET_TIME_absolute_subtract (
    GNUNET_TIME_absolute_subtract (
      GNUNET_TIME_absolute_add (tail->anchor.abs_time,
                                denom->duration_withdraw),
      lookahead_sign),
    overlap_duration);
  if (head->rc > 0)
    return tt; /* head expiration does not count due to rc > 0 */
  return GNUNET_TIME_absolute_min (
    GNUNET_TIME_absolute_add (head->anchor.abs_time,
                              denom->duration_withdraw),
    tt);
}


/**
 * Create new keys and expire ancient keys of the given denomination @a denom.
 * Removes the @a denom from the #denom_head DLL and re-insert its at the
 * correct location sorted by next maintenance activity.
 *
 * @param[in,out] denom denomination to update material for
 * @param now current time to use (to get many keys to use the exact same time)
 * @param[in,out] wake set to true if we should wake the clients
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
update_keys (struct Denomination *denom,
             struct GNUNET_TIME_Timestamp now,
             bool *wake)
{
  /* create new denomination keys */
  if (NULL != denom->keys_tail)
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Updating keys of denomination `%s', last key %s valid for another %s\n",
                denom->section,
                GNUNET_h2s (&denom->keys_tail->h_rsa.hash),
                GNUNET_TIME_relative2s (
                  GNUNET_TIME_absolute_get_remaining (
                    GNUNET_TIME_absolute_subtract (
                      GNUNET_TIME_absolute_add (
                        denom->keys_tail->anchor.abs_time,
                        denom->duration_withdraw),
                      overlap_duration)),
                  GNUNET_YES));
  while ( (NULL == denom->keys_tail) ||
          GNUNET_TIME_absolute_is_past (
            GNUNET_TIME_absolute_subtract (
              GNUNET_TIME_absolute_subtract (
                GNUNET_TIME_absolute_add (denom->keys_tail->anchor.abs_time,
                                          denom->duration_withdraw),
                lookahead_sign),
              overlap_duration)) )
  {
    if (! *wake)
    {
      key_gen++;
      *wake = true;
    }
    if (GNUNET_OK !=
        create_key (denom,
                    now))
    {
      GNUNET_break (0);
      globals->global_ret = EXIT_FAILURE;
      GNUNET_SCHEDULER_shutdown ();
      return GNUNET_SYSERR;
    }
  }
  /* remove expired denomination keys */
  while ( (NULL != denom->keys_head) &&
          GNUNET_TIME_absolute_is_past
            (GNUNET_TIME_absolute_add (denom->keys_head->anchor.abs_time,
                                       denom->duration_withdraw)) )
  {
    struct DenominationKey *key = denom->keys_head;
    struct DenominationKey *nxt = key->next;

    if (0 != key->rc)
      break; /* later */
    GNUNET_CONTAINER_DLL_remove (denom->keys_head,
                                 denom->keys_tail,
                                 key);
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_remove (
                     keys,
                     &key->h_rsa.hash,
                     key));
    if ( (! key->purge) &&
         (0 != unlink (key->filename)) )
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                "unlink",
                                key->filename);
    GNUNET_free (key->filename);
    GNUNET_CRYPTO_rsa_private_key_free (key->denom_priv);
    GNUNET_CRYPTO_rsa_public_key_free (key->denom_pub);
    GNUNET_free (key->an);
    GNUNET_free (key);
    key = nxt;
  }

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
      if (GNUNET_TIME_absolute_cmp (denomination_action_time (pos), >=, at))
        break;
      before = pos;
    }
    GNUNET_CONTAINER_DLL_insert_after (denom_head,
                                       denom_tail,
                                       before,
                                       denom);
  }
  return GNUNET_OK;
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
  struct GNUNET_TIME_Timestamp t;
  bool wake = false;

  (void) cls;
  keygen_task = NULL;
  now = GNUNET_TIME_absolute_get ();
  t = GNUNET_TIME_absolute_to_timestamp (now);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Updating denominations ...\n");
  GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
  do {
    denom = denom_head;
    if (GNUNET_OK !=
        update_keys (denom,
                     t,
                     &wake))
      return;
  } while (denom != denom_head);
  GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Updating denominations finished ...\n");
  if (wake)
    TES_wake_clients ();
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
  struct GNUNET_TIME_Timestamp anchor;

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
  anchor.abs_time.abs_value_us
    = anchor_ll * GNUNET_TIME_UNIT_SECONDS.rel_value_us;
  if (anchor_ll != anchor.abs_time.abs_value_us
      / GNUNET_TIME_UNIT_SECONDS.rel_value_us)
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
    dk->denom_priv = priv;
    dk->denom = denom;
    dk->anchor = anchor;
    dk->filename = GNUNET_strdup (filename);
    GNUNET_CRYPTO_rsa_public_key_hash (pub,
                                       &dk->h_rsa.hash);
    dk->denom_pub = pub;
    generate_response (dk);
    if (GNUNET_OK !=
        GNUNET_CONTAINER_multihashmap_put (
          keys,
          &dk->h_rsa.hash,
          dk,
          GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Duplicate private key %s detected in file `%s'. Skipping.\n",
                  GNUNET_h2s (&dk->h_rsa.hash),
                  filename);
      GNUNET_CRYPTO_rsa_private_key_free (priv);
      GNUNET_CRYPTO_rsa_public_key_free (pub);
      GNUNET_free (dk->an);
      GNUNET_free (dk);
      return;
    }
    before = NULL;
    for (struct DenominationKey *pos = denom->keys_head;
         NULL != pos;
         pos = pos->next)
    {
      if (GNUNET_TIME_timestamp_cmp (pos->anchor,
                                     >,
                                     anchor))
        break;
      before = pos;
    }
    GNUNET_CONTAINER_DLL_insert_after (denom->keys_head,
                                       denom->keys_tail,
                                       before,
                                       dk);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Imported key %s from `%s'\n",
                GNUNET_h2s (&dk->h_rsa.hash),
                filename);
  }
}


/**
 * Import a private key from @a filename for the denomination
 * given in @a cls.
 *
 * @param[in,out] cls a `struct Denomiantion`
 * @param filename name of a file in the directory
 * @return #GNUNET_OK (always, continue to iterate)
 */
static enum GNUNET_GenericReturnValue
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
             O_RDONLY | O_CLOEXEC);
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
    GNUNET_break (0 == close (fd));
    return GNUNET_OK;
  }
  if (! S_ISREG (sbuf.st_mode))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "File `%s' is not a regular file, which is not allowed for private keys!\n",
                filename);
    GNUNET_break (0 == close (fd));
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
  if (sbuf.st_size > 16 * 1024)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "File `%s' too big to be a private key\n",
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
 * @param cfg configuration to use
 * @param ct section in the configuration file giving the denomination type parameters
 * @param[out] denom set to the denomination parameters from the configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if the configuration is invalid
 */
static enum GNUNET_GenericReturnValue
parse_denomination_cfg (const struct GNUNET_CONFIGURATION_Handle *cfg,
                        const char *ct,
                        struct Denomination *denom)
{
  unsigned long long rsa_keysize;
  char *secname;

  GNUNET_asprintf (&secname,
                   "%s-secmod-rsa",
                   globals->section);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           ct,
                                           "DURATION_WITHDRAW",
                                           &denom->duration_withdraw))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "DURATION_WITHDRAW");
    GNUNET_free (secname);
    return GNUNET_SYSERR;
  }
  if (GNUNET_TIME_relative_cmp (overlap_duration,
                                >=,
                                denom->duration_withdraw))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               secname,
                               "OVERLAP_DURATION",
                               "Value given must be smaller than value for DURATION_WITHDRAW!");
    GNUNET_free (secname);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             ct,
                                             "RSA_KEYSIZE",
                                             &rsa_keysize))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "RSA_KEYSIZE");
    GNUNET_free (secname);
    return GNUNET_SYSERR;
  }
  if ( (rsa_keysize > 4 * 2048) ||
       (rsa_keysize < 1024) )
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               ct,
                               "RSA_KEYSIZE",
                               "Given RSA keysize outside of permitted range [1024,8192]\n");
    GNUNET_free (secname);
    return GNUNET_SYSERR;
  }
  GNUNET_free (secname);
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
   * Configuration to use.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Current time to use.
   */
  struct GNUNET_TIME_Timestamp t;

  /**
   * Status, to be set to #GNUNET_SYSERR on failure
   */
  enum GNUNET_GenericReturnValue ret;
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
  bool wake = true;
  char *cipher;

  if ( (0 != strncasecmp (denomination_alias,
                          "coin_",
                          strlen ("coin_"))) &&
       (0 != strncasecmp (denomination_alias,
                          "coin-",
                          strlen ("coin-"))) )
    return; /* not a denomination type definition */
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ctx->cfg,
                                             denomination_alias,
                                             "CIPHER",
                                             &cipher))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               denomination_alias,
                               "CIPHER");
    return;
  }
  if (0 != strcmp (cipher, "RSA"))
  {
    GNUNET_free (cipher);
    return; /* Ignore denominations of other types than CS */
  }
  GNUNET_free (cipher);
  denom = GNUNET_new (struct Denomination);
  if (GNUNET_OK !=
      parse_denomination_cfg (ctx->cfg,
                              denomination_alias,
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
               ctx->t,
               &wake);
}


/**
 * Load the various duration values from @a cfg
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
load_durations (const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  char *secname;

  GNUNET_asprintf (&secname,
                   "%s-secmod-rsa",
                   globals->section);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           secname,
                                           "OVERLAP_DURATION",
                                           &overlap_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               secname,
                               "OVERLAP_DURATION");
    GNUNET_free (secname);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           secname,
                                           "LOOKAHEAD_SIGN",
                                           &lookahead_sign))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               secname,
                               "LOOKAHEAD_SIGN");
    GNUNET_free (secname);
    return GNUNET_SYSERR;
  }
  GNUNET_free (secname);
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
  stop_workers ();
  sem_done (&worker_sem);
}


void
TALER_SECMOD_rsa_run (void *cls,
                      char *const *args,
                      const char *cfgfile,
                      const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  static struct TES_Callbacks cb = {
    .dispatch = rsa_work_dispatch,
    .updater = rsa_update_client_keys,
    .init = rsa_client_init
  };
  struct TALER_SECMOD_Options *opt = cls;
  char *secname;

  (void) args;
  (void) cfgfile;
  globals = opt;
  if (GNUNET_TIME_timestamp_cmp (opt->global_now,
                                 !=,
                                 opt->global_now_tmp))
  {
    /* The user gave "--now", use it! */
    opt->global_now = opt->global_now_tmp;
  }
  else
  {
    /* get current time again, we may be timetraveling! */
    opt->global_now = GNUNET_TIME_timestamp_get ();
  }
  GNUNET_asprintf (&secname,
                   "%s-secmod-rsa",
                   opt->section);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               secname,
                                               "KEY_DIR",
                                               &keydir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               secname,
                               "KEY_DIR");
    GNUNET_free (secname);
    opt->global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if (GNUNET_OK !=
      load_durations (cfg))
  {
    opt->global_ret = EXIT_NOTCONFIGURED;
    GNUNET_free (secname);
    return;
  }
  GNUNET_asprintf (&secname,
                   "%s-secmod-rsa",
                   opt->section);
  opt->global_ret = TES_listen_start (cfg,
                                      secname,
                                      &cb);
  GNUNET_free (secname);
  if (0 != opt->global_ret)
    return;
  sem_init (&worker_sem,
            0);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  if (0 == opt->max_workers)
  {
    long lret;

    lret = sysconf (_SC_NPROCESSORS_CONF);
    if (lret <= 0)
      lret = 1;
    opt->max_workers = (unsigned int) lret;
  }

  for (unsigned int i = 0; i<opt->max_workers; i++)
    if (GNUNET_OK !=
        start_worker ())
    {
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
  /* Load denominations */
  keys = GNUNET_CONTAINER_multihashmap_create (65536,
                                               true);
  {
    struct LoadContext lc = {
      .cfg = cfg,
      .ret = GNUNET_OK,
      .t = opt->global_now
    };

    GNUNET_assert (0 == pthread_mutex_lock (&keys_lock));
    GNUNET_CONFIGURATION_iterate_sections (cfg,
                                           &load_denominations,
                                           &lc);
    GNUNET_assert (0 == pthread_mutex_unlock (&keys_lock));
    if (GNUNET_OK != lc.ret)
    {
      opt->global_ret = EXIT_FAILURE;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
  }
  if (NULL == denom_head)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "No RSA denominations configured\n");
    TES_wake_clients ();
    return;
  }
  /* start job to keep keys up-to-date; MUST be run before the #listen_task,
     hence with priority. */
  keygen_task = GNUNET_SCHEDULER_add_with_priority (
    GNUNET_SCHEDULER_PRIORITY_URGENT,
    &update_denominations,
    NULL);
}
