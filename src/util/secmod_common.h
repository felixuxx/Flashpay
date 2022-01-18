/*
  This file is part of GNU Taler
  Copyright (C) 2021 Taler Systems SA

  GNU Taler is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  GNU Taler is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file util/secmod_common.h
 * @brief Common functions for the exchange security modules
 * @author Florian Dold <dold@taler.net>
 */
#ifndef SECMOD_COMMON_H
#define SECMOD_COMMON_H

#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_network_lib.h>
#include <pthread.h>


/**
 * Create the listen socket for a secmod daemon.
 *
 * This function is not thread-safe, as it changes and
 * restores the process umask.
 *
 * @param unixpath socket path
 */
struct GNUNET_NETWORK_Handle *
TES_open_socket (const char *unixpath);


/**
 * Send a message starting with @a hdr to @a sock.
 *
 * @param sock where to send the message
 * @param hdr beginning of the message, length indicated in size field
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TES_transmit (int sock,
              const struct GNUNET_MessageHeader *hdr);


/**
 * Transmit @a end bytes from @a pos on @a sock.
 *
 * @param sock where to send the data
 * @param end how many bytes to send
 * @param pos first address with data
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TES_transmit_raw (int sock,
                  size_t end,
                  const void *pos);

/**
 * Information we keep for a client connected to us.
 */
struct TES_Client;

/**
 * Function that handles message @a hdr from @a client.
 *
 * @param client sender of the message
 * @param hdr message we received
 * @return #GNUNET_OK on success
 */
typedef enum GNUNET_GenericReturnValue
(*TES_MessageDispatch)(struct TES_Client *client,
                       const struct GNUNET_MessageHeader *hdr);


/**
 * Function that updates the keys for @a client.
 *
 * @param client sender of the message
 * @return #GNUNET_OK on success
 */
typedef enum GNUNET_GenericReturnValue
(*TES_KeyUpdater)(struct TES_Client *client);


/**
 * Module-specific functions to be used.
 */
struct TES_Callbacks
{
  /**
   * Function to handle inbound messages.
   */
  TES_MessageDispatch dispatch;

  /**
   * Function to update key material initially.
   */
  TES_KeyUpdater init;

  /**
   * Function to update key material.
   */
  TES_KeyUpdater updater;

};


/**
 * Information we keep for a client connected to us.
 */
struct TES_Client
{

  /**
   * Kept in a DLL.
   */
  struct TES_Client *next;

  /**
   * Kept in a DLL.
   */
  struct TES_Client *prev;

  /**
   * Callbacks to use for work.
   */
  struct TES_Callbacks cb;

  /**
   * Worker thread for this client.
   */
  pthread_t worker;

  /**
   * Key generation this client is on.
   */
  uint64_t key_gen;

  /**
   * IO-buffer used by @a purpose.
   */
  char iobuf[65536];

  /**
   * Client socket.
   */
  int csock;

#ifdef __linux__
  /**
   * Event socket.
   */
  int esock;
#else
  /**
   * Input end of the event pipe.
   */
  int esock_in;

  /**
   * Output end of the event pipe.
   */
  int esock_out;
#endif
};


/**
 * Head of DLL of clients connected to us.
 */
extern struct TES_Client *TES_clients_head;

/**
 * Tail of DLL of clients connected to us.
 */
extern struct TES_Client *TES_clients_tail;

/**
 * Lock for the client queue.
 */
extern pthread_mutex_t TES_clients_lock;

/**
 * Private key of this security module. Used to sign denomination key
 * announcements.
 */
extern struct TALER_SecurityModulePrivateKeyP TES_smpriv;

/**
 * Public key of this security module.
 */
extern struct TALER_SecurityModulePublicKeyP TES_smpub;


/**
 * Send a signal to all clients to notify them about a key generation change.
 */
void
TES_wake_clients (void);


/**
 * Read work request from the client.
 *
 * @param cls a `struct TES_Client *`
 * @param dispatch function to call with work requests received
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TES_read_work (void *cls,
               TES_MessageDispatch dispatch);


/**
 * Wait until the socket is ready to read.
 *
 * @param client the client to wait for
 * @return true if we received an event
 */
bool
TES_await_ready (struct TES_Client *client);


/**
 * Free resources occupied by @a client.
 *
 * @param[in] client resources to release
 */
void
TES_free_client (struct TES_Client *client);


/**
 * Start listen task.
 *
 * @param cfg configuration to use
 * @param section configuration section to use
 * @param cb callback functions to use
 * @return 0 on success, otherwise return value to return from main()
 */
int
TES_listen_start (const struct GNUNET_CONFIGURATION_Handle *cfg,
                  const char *section,
                  const struct TES_Callbacks *cb);


/**
 * Stop listen task.
 */
void
TES_listen_stop (void);


#endif
