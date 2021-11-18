/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file util/secmod_common.c
 * @brief Common functions for the exchange security modules
 * @author Florian Dold <dold@taler.net>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "secmod_common.h"
#include <poll.h>
#include <sys/eventfd.h>


/**
 * Head of DLL of clients connected to us.
 */
struct TES_Client *TES_clients_head;

/**
 * Tail of DLL of clients connected to us.
 */
struct TES_Client *TES_clients_tail;

/**
 * Lock for the client queue.
 */
pthread_mutex_t TES_clients_lock;

/**
 * Private key of this security module. Used to sign denomination key
 * announcements.
 */
struct TALER_SecurityModulePrivateKeyP TES_smpriv;

/**
 * Public key of this security module.
 */
struct TALER_SecurityModulePublicKeyP TES_smpub;

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
static struct GNUNET_SCHEDULER_Task *listen_task;

/**
 * Set once we are in shutdown and workers should terminate.
 */
static volatile bool in_shutdown;


enum GNUNET_GenericReturnValue
TES_transmit (int sock,
              const struct GNUNET_MessageHeader *hdr)
{
  ssize_t off = 0;
  const void *pos = hdr;
  uint16_t end = ntohs (hdr->size);

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Sending message of type %u and length %u\n",
              (unsigned int) ntohs (hdr->type),
              (unsigned int) ntohs (hdr->size));
  while (off < end)
  {
    ssize_t ret = send (sock,
                        pos,
                        end - off,
                        0 /* no flags => blocking! */);
    if ( (-1 == ret) &&
         ( (EAGAIN == errno) ||
           (EINTR == errno) ) )
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_DEBUG,
                           "send");
      continue;
    }
    if (-1 == ret)
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "send");
      return GNUNET_SYSERR;
    }
    if (0 == ret)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    off += ret;
    pos += ret;
  }
  return GNUNET_OK;
}


struct GNUNET_NETWORK_Handle *
TES_open_socket (const char *unixpath)
{
  int sock;
  mode_t old_umask;
  struct GNUNET_NETWORK_Handle *ret = NULL;

  /* Change permissions so that group read/writes are allowed.
   * We need this for multi-user exchange deployment with privilege
   * separation, where taler-exchange-httpd is part of a group
   * that allows it to talk to secmod.
   */
  old_umask = umask (S_IROTH | S_IWOTH | S_IXOTH);

  sock = socket (PF_UNIX,
                 SOCK_STREAM,
                 0);
  if (-1 == sock)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "socket");
    goto cleanup;
  }
  {
    struct sockaddr_un un;

    if (GNUNET_OK !=
        GNUNET_DISK_directory_create_for_file (unixpath))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "mkdir(dirname)",
                                unixpath);
    }
    if (0 != unlink (unixpath))
    {
      if (ENOENT != errno)
        GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                  "unlink",
                                  unixpath);
    }
    memset (&un,
            0,
            sizeof (un));
    un.sun_family = AF_UNIX;
    strncpy (un.sun_path,
             unixpath,
             sizeof (un.sun_path) - 1);
    if (0 != bind (sock,
                   (const struct sockaddr *) &un,
                   sizeof (un)))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                "bind",
                                unixpath);
      GNUNET_break (0 == close (sock));
      goto cleanup;
    }
    ret = GNUNET_NETWORK_socket_box_native (sock);
    if (GNUNET_OK !=
        GNUNET_NETWORK_socket_listen (ret,
                                      512))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                "listen",
                                unixpath);
      GNUNET_break (GNUNET_OK ==
                    GNUNET_NETWORK_socket_close (ret));
      ret = NULL;
    }
  }
cleanup:
  (void) umask (old_umask);
  return ret;
}


/**
 * Send a signal to all clients to notify them about a key generation change.
 */
void
TES_wake_clients (void)
{
  uint64_t num = 1;

  GNUNET_assert (0 == pthread_mutex_lock (&TES_clients_lock));
  for (struct TES_Client *client = TES_clients_head;
       NULL != client;
       client = client->next)
  {
    GNUNET_assert (sizeof (num) ==
                   write (client->esock,
                          &num,
                          sizeof (num)));
  }
  GNUNET_assert (0 == pthread_mutex_unlock (&TES_clients_lock));
}


/**
 * Read work request from the client.
 *
 * @param cls a `struct TES_Client *`
 * @param dispatch function to call with work requests received
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TES_read_work (void *cls,
               TES_MessageDispatch dispatch)
{
  struct TES_Client *client = cls;
  char *buf = client->iobuf;
  ssize_t buf_size;
  size_t off = 0;
  uint16_t msize;
  const struct GNUNET_MessageHeader *hdr;

  do
  {
    buf_size = recv (client->csock,
                     &buf[off],
                     sizeof (client->iobuf) - off,
                     0);
    if (-1 == buf_size)
    {
      if ( (0 == off) &&
           (EAGAIN == errno) )
        return GNUNET_NO;
      if ( (EINTR == errno) ||
           (EAGAIN == errno) )
      {
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_DEBUG,
                             "recv");
        continue;
      }
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "recv");
      return GNUNET_SYSERR;
    }
    if (0 == buf_size)
    {
      /* regular disconnect? */
      GNUNET_break_op (0 == off);
      return GNUNET_SYSERR;
    }
    off += buf_size;
    if (off < sizeof (struct GNUNET_MessageHeader))
      continue;
    hdr = (const struct GNUNET_MessageHeader *) buf;
    msize = ntohs (hdr->size);
  } while (off < msize);

  if (off > msize)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return dispatch (client,
                   hdr);
}


bool
TES_await_ready (struct TES_Client *client)
{
  /* wait for reply with 1s timeout */
  struct pollfd pfds[] = {
    {
      .fd = client->csock,
      .events = POLLIN
    },
    {
      .fd = client->esock,
      .events = POLLIN
    },
  };
  int ret;

  ret = poll (pfds,
              2,
              -1);
  if ( (-1 == ret) &&
       (EINTR != errno) )
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "poll");
  for (int i = 0; i<2; i++)
  {
    if ( (pfds[i].fd == client->esock) &&
         (POLLIN == pfds[i].revents) )
    {
      uint64_t num;

      GNUNET_assert (sizeof (num) ==
                     read (client->esock,
                           &num,
                           sizeof (num)));
      return true;
    }
  }
  return false;
}


void
TES_free_client (struct TES_Client *client)
{
  GNUNET_assert (0 == pthread_mutex_lock (&TES_clients_lock));
  GNUNET_CONTAINER_DLL_remove (TES_clients_head,
                               TES_clients_tail,
                               client);
  GNUNET_assert (0 == pthread_mutex_unlock (&TES_clients_lock));
  GNUNET_break (0 == close (client->csock));
  GNUNET_break (0 == close (client->esock));
  pthread_detach (client->worker);
  GNUNET_free (client);
}


/**
 * Main function of a worker thread that signs.
 *
 * @param cls the client we are working on
 * @return NULL
 */
static void *
sign_worker (void *cls)
{
  struct TES_Client *client = cls;

  if (GNUNET_OK !=
      client->cb.init (client))
  {
    GNUNET_break (0);
    TES_free_client (client);
    return NULL;
  }
  while (! in_shutdown)
  {
    if (TES_await_ready (client))
    {
      if (GNUNET_OK !=
          client->cb.updater (client))
        break;
    }
    if (GNUNET_SYSERR ==
        TES_read_work (client,
                       client->cb.dispatch))
      break;
  }
  TES_free_client (client);
  return NULL;
}


/**
 * Task that listens for incoming clients.
 *
 * @param cls a `struct TES_Callbacks`
 */
static void
listen_job (void *cls)
{
  const struct TES_Callbacks *cb = cls;
  int s;
  int e;
  struct sockaddr_storage sa;
  socklen_t sa_len = sizeof (sa);

  listen_task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                               unix_sock,
                                               &listen_job,
                                               cls);
  s = accept (GNUNET_NETWORK_get_fd (unix_sock),
              (struct sockaddr *) &sa,
              &sa_len);
  if (-1 == s)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "accept");
    return;
  }
  e = eventfd (0,
               EFD_CLOEXEC);
  if (-1 == e)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                         "eventfd");
    GNUNET_break (0 == close (s));
    return;
  }
  {
    struct TES_Client *client;

    client = GNUNET_new (struct TES_Client);
    client->cb = *cb;
    client->csock = s;
    client->esock = e;
    GNUNET_assert (0 == pthread_mutex_lock (&TES_clients_lock));
    GNUNET_CONTAINER_DLL_insert (TES_clients_head,
                                 TES_clients_tail,
                                 client);
    GNUNET_assert (0 == pthread_mutex_unlock (&TES_clients_lock));
    if (0 !=
        pthread_create (&client->worker,
                        NULL,
                        &sign_worker,
                        client))
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "pthread_create");
      TES_free_client (client);
    }
  }
}


int
TES_listen_start (const struct GNUNET_CONFIGURATION_Handle *cfg,
                  const char *section,
                  const struct TES_Callbacks *cb)
{
  {
    char *pfn;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 section,
                                                 "SM_PRIV_KEY",
                                                 &pfn))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "SM_PRIV_KEY");
      return EXIT_NOTCONFIGURED;
    }
    if (GNUNET_SYSERR ==
        GNUNET_CRYPTO_eddsa_key_from_file (pfn,
                                           GNUNET_YES,
                                           &TES_smpriv.eddsa_priv))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "SM_PRIV_KEY",
                                 "Could not use file to persist private key");
      GNUNET_free (pfn);
      return EXIT_NOPERMISSION;
    }
    GNUNET_free (pfn);
    GNUNET_CRYPTO_eddsa_key_get_public (&TES_smpriv.eddsa_priv,
                                        &TES_smpub.eddsa_pub);
  }


  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               section,
                                               "UNIXPATH",
                                               &unixpath))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "UNIXPATH");
    return EXIT_NOTCONFIGURED;
  }
  GNUNET_assert (NULL != unixpath);
  unix_sock = TES_open_socket (unixpath);
  if (NULL == unix_sock)
  {
    GNUNET_free (unixpath);
    GNUNET_break (0);
    return EXIT_NOPERMISSION;
  }
  /* start job to accept incoming requests on 'sock' */
  listen_task = GNUNET_SCHEDULER_add_read_net (GNUNET_TIME_UNIT_FOREVER_REL,
                                               unix_sock,
                                               &listen_job,
                                               (void *) cb);
  return 0;
}


void
TES_listen_stop (void)
{
  if (NULL != listen_task)
  {
    GNUNET_SCHEDULER_cancel (listen_task);
    listen_task = NULL;
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
  in_shutdown = true;
  TES_wake_clients ();
}
