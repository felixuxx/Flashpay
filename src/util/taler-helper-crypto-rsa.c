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
 * @file util/taler-helper-crypto-rsa.c
 * @brief Standalone process to perform private key RSA operations
 * @author Christian Grothoff
 *
 * NOTES:
 * - Option 'DURATION_OVERLAP' renamed to 'OVERLAP_DURATION' for consistency;
 *   => need to update in deployment scripts and default configuration!
 * - option 'KEYDIR' moved from section 'exchange' to 'taler-helper-crypto-rsa'!
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
 *
 * TODO:
 * - actual networking
 * - actual signing
 */
#include "platform.h"
#include "taler_util.h"
#include "taler-helper-crypto-rsa.h"
#include <gcrypt.h>


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
   * The private key of the denomination.  Will be NULL if the private
   * key is not available (this is the case after the key has expired
   * for signing coins, but is still valid for depositing coins).
   */
  struct TALER_DenominationPrivateKey denom_priv;

  /**
   * The public key of the denomination.
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * Hash of this denomination's public key.
   */
  struct GNUNET_HashCode h_pub;

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
   * Client socket.
   */
  struct GNUNET_NETWORK_Handle *sock;

  /**
   * Client task to read from @e sock. NULL if we are working.
   */
  struct GNUNET_SCHEDULER_Task *task;

};


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
 * denominations is always @e duration_withdraw - #duration_overlap apart.
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
static struct GNUNET_NETWORK_Handle *lsock;

/**
 * Task run to accept new inbound connections.
 */
static struct GNUNET_SCHEDULER_Task *accept_task;

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
 * Function run to read incoming requests from a client.
 *
 * @param cls the `struct Client`
 */
static void
read_job (void *cls)
{
  struct Client *client = cls;

  // FIXME: DO WORK!
  // check for:
  // - sign requests
  // - revocation requests!?
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
  struct TALER_CRYPTO_RsaKeyAvailableNotification *an;
  struct Denomination *denom = dk->denom;
  size_t nlen = strlen (denom->section) + 1;
  size_t buf_len;
  void *buf;
  void *p;
  ssize_t ret;
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
  p = (void *) &an[1];
  memcpy (p,
          buf,
          buf_len);
  GNUNET_free (buf);
  memcpy (p + buf_len,
          denom->section,
          nlen);
  ret = send (GNUNET_NETWORK_get_fd (client->sock),
              an,
              tlen,
              0);
  if (tlen != ret)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "send");
    GNUNET_free (an);
    GNUNET_NETWORK_socket_close (client->sock);
    GNUNET_CONTAINER_DLL_remove (clients_head,
                                 clients_tail,
                                 client);
    GNUNET_free (client);
    return GNUNET_SYSERR;
  }
  GNUNET_free (an);
  return GNUNET_OK;
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
    .h_denom_pub = dk->h_pub
  };
  ssize_t ret;

  ret = send (GNUNET_NETWORK_get_fd (client->sock),
              &pn,
              sizeof (pn),
              0);
  if (sizeof (pn) != ret)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "send");
    GNUNET_NETWORK_socket_close (client->sock);
    GNUNET_CONTAINER_DLL_remove (clients_head,
                                 clients_tail,
                                 client);
    GNUNET_free (client);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function run to accept incoming connections on #sock.
 *
 * @param cls NULL
 */
static void
accept_job (void *cls)
{
  struct GNUNET_NETWORK_Handle *sock;
  struct sockaddr_storage addr;
  socklen_t alen;

  accept_task = NULL;
  alen = sizeof (addr);
  sock = GNUNET_NETWORK_socket_accept (lsock,
                                       (struct sockaddr *) &addr,
                                       &alen);
  if (NULL != sock)
  {
    struct Client *client;

    client = GNUNET_new (struct Client);
    client->sock = sock;
    GNUNET_CONTAINER_DLL_insert (clients_head,
                                 clients_tail,
                                 client);
    client->task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                                  sock,
                                                  &read_job,
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
  }
  accept_task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                               lsock,
                                               &accept_job,
                                               NULL);
}


/**
 * Create a new denomination key (we do not have enough).
 *
 * @param denom denomination key to create
 * @return #GNUNET_OK on success
 */
static int
create_key (struct Denomination *denom)
{
  struct DenominationKey *dk;
  struct GNUNET_TIME_Absolute anchor;
  struct GNUNET_CRYPTO_RsaPrivateKey *priv;
  struct GNUNET_CRYPTO_RsaPublicKey *pub;
  size_t buf_size;
  void *buf;

  if (NULL == denom->keys_tail)
  {
    anchor = GNUNET_TIME_absolute_get ();
    (void) GNUNET_TIME_round_abs (&anchor);
  }
  else
  {
    anchor = GNUNET_TIME_absolute_add (denom->keys_tail->anchor,
                                       GNUNET_TIME_relative_subtract (
                                         denom->duration_withdraw,
                                         overlap_duration));
  }
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
    GNUNET_SCHEDULER_shutdown ();
    global_ret = 41;
    return GNUNET_SYSERR;
  }
  buf_size = GNUNET_CRYPTO_rsa_private_key_encode (priv,
                                                   &buf);
  dk = GNUNET_new (struct DenominationKey);
  dk->denom = denom;
  dk->anchor = anchor;
  dk->denom_priv.rsa_private_key = priv;
  GNUNET_CRYPTO_rsa_public_key_hash (pub,
                                     &dk->h_pub);
  dk->denom_pub.rsa_public_key = pub;
  GNUNET_asprintf (&dk->filename,
                   "%s/%s/%llu",
                   keydir,
                   denom->section,
                   (unsigned long long) (anchor.abs_value_us
                                         / GNUNET_TIME_UNIT_SECONDS.rel_value_us));
  if (buf_size !=
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
    GNUNET_free (dk);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = 42;
    return GNUNET_SYSERR;
  }
  GNUNET_free (buf);

  if (GNUNET_OK !=
      GNUNET_CONTAINER_multihashmap_put (
        keys,
        &dk->h_pub,
        dk,
        GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Duplicate private key created! Terminating.\n");
    GNUNET_CRYPTO_rsa_private_key_free (priv);
    GNUNET_CRYPTO_rsa_public_key_free (pub);
    GNUNET_free (dk);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = 43;
    return GNUNET_SYSERR;
  }
  GNUNET_CONTAINER_DLL_insert_tail (denom->keys_head,
                                    denom->keys_tail,
                                    dk);
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
 * At what time does this denomination require its next action?
 * Basically, the minimum of the withdraw expiration time of the
 * oldest denomination key, and the withdraw expiration time of
 * the newest denomination key minus the #lookahead_sign time.
 *
 * @param denon denomination to compute action time for
 */
static struct GNUNET_TIME_Absolute
denomination_action_time (const struct Denomination *denom)
{
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
                                                       &dk->h_pub,
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
 */
static void
update_keys (struct Denomination *denom)
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
        create_key (denom))
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
    before = NULL;
    GNUNET_CONTAINER_DLL_remove (denom_head,
                                 denom_tail,
                                 denom);
    for (struct Denomination *pos = denom_head;
         NULL != pos;
         pos = pos->next)
    {
      if (denomination_action_time (pos).abs_value_us > at.abs_value_us)
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

  (void) cls;
  keygen_task = NULL;
  do {
    denom = denom_head;
    update_keys (denom);
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
                                       &dk->h_pub);
    dk->denom_pub.rsa_public_key = pub;
    if (GNUNET_OK !=
        GNUNET_CONTAINER_multihashmap_put (
          keys,
          &dk->h_pub,
          dk,
          GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Duplicate private key detected in file `%s'. Skipping.\n",
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
                               "exchangedb",
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
                               "exchangedb",
                               "RSA_KEYSIZE",
                               "Given RSA keysize outside of permitted range [1024,8192]\n");
    return GNUNET_SYSERR;
  }
  denom->rsa_keysize = (unsigned int) rsa_keysize;
  denom->section = GNUNET_strdup (ct);
  return GNUNET_OK;
}


/**
 * Generate new denomination signing keys for the denomination type of the given @a
 * denomination_alias.
 *
 * @param cls a `int *`, to be set to #GNUNET_SYSERR on failure
 * @param denomination_alias name of the denomination's section in the configuration
 */
static void
load_denominations (void *cls,
                    const char *denomination_alias)
{
  int *ret = cls;
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
    *ret = GNUNET_SYSERR;
    GNUNET_free (denom);
    return;
  }
  {
    char *dname;

    GNUNET_asprintf (&dname,
                     "%s/%s",
                     keydir,
                     denom->section);
    GNUNET_DISK_directory_scan (dname,
                                &import_key,
                                denom);
    GNUNET_free (dname);
  }
  GNUNET_CONTAINER_DLL_insert (denom_head,
                               denom_tail,
                               denom);
  update_keys (denom);
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
                                           "exchangedb",
                                           "OVERLAP_DURATION",
                                           &overlap_duration))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "OVERLAP_DURATION");
    return GNUNET_SYSERR;
  }
  GNUNET_TIME_round_rel (&overlap_duration);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (kcfg,
                                           "exchange",
                                           "LOOKAHEAD_SIGN",
                                           &lookahead_sign))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
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
  if (NULL != accept_task)
  {
    GNUNET_SCHEDULER_cancel (accept_task);
    accept_task = NULL;
  }
  if (NULL != lsock)
  {
    GNUNET_break (0 ==
                  GNUNET_NETWORK_socket_close (lsock));
    lsock = NULL;
  }
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
  if (GNUNET_OK !=
      load_durations ())
  {
    global_ret = 1;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "taler-helper-crypto-rsa",
                                               "KEYDIR",
                                               &keydir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "KEYDIR");
    global_ret = 1;
    return;
  }

  /* open socket */
  {
    int sock;

    sock = socket (PF_UNIX,
                   SOCK_DGRAM,
                   0);
    if (-1 == sock)
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                           "socket");
      global_ret = 2;
      return;
    }
    {
      struct sockaddr_un un;
      char *unixpath;

      if (GNUNET_OK !=
          GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                                   "exchange-helper-crypto-rsa",
                                                   "UNIXPATH",
                                                   &unixpath))
      {
        GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                   "exchange-helper-crypto-rsa",
                                   "UNIXPATH");
        global_ret = 3;
        return;
      }
      memset (&un,
              0,
              sizeof (un));
      un.sun_family = AF_UNIX;
      strncpy (un.sun_path,
               unixpath,
               sizeof (un.sun_path));
      if (0 != bind (sock,
                     (const struct sockaddr *) &un,
                     sizeof (un)))
      {
        GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                  "bind",
                                  unixpath);
        global_ret = 3;
        GNUNET_break (0 == close (sock));
        return;
      }
    }
    lsock = GNUNET_NETWORK_socket_box_native (sock);
  }

  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);

  /* Load denominations */
  keys = GNUNET_CONTAINER_multihashmap_create (65536,
                                               GNUNET_YES);
  {
    int ok;

    ok = GNUNET_OK;
    GNUNET_CONFIGURATION_iterate_sections (kcfg,
                                           &load_denominations,
                                           &ok);
    if (GNUNET_OK != ok)
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
  accept_task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                               lsock,
                                               &accept_job,
                                               NULL);

  /* start job to keep keys up-to-date */
  keygen_task = GNUNET_SCHEDULER_add_now (&update_denominations,
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
  int ret;

  (void) umask (S_IWGRP | S_IROTH | S_IWOTH | S_IXOTH);
  /* force linker to link against libtalerutil; if we do
   not do this, the linker may "optimize" libtalerutil
   away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-helper-crypto-rsa",
                                   "WARNING",
                                   NULL));
  now = now_tmp = GNUNET_TIME_absolute_get ();
  ret = GNUNET_PROGRAM_run (argc, argv,
                            "taler-helper-crypto-rsa",
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
