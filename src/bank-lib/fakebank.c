/*
  This file is part of TALER
  (C) 2016-2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file bank-lib/fakebank.c
 * @brief library that fakes being a Taler bank for testcases
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include <pthread.h>
#include <poll.h>
#ifdef __linux__
#include <sys/eventfd.h>
#endif
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_bank.h"
#include "fakebank_common_lp.h"
#include "fakebank_tbi.h"


/**
 * Function called whenever MHD is done with a request.  If the
 * request was a POST, we may have stored a `struct Buffer *` in the
 * @a con_cls that might still need to be cleaned up.  Call the
 * respective function to free the memory.
 *
 * @param cls a `struct TALER_FAKEBANK_Handle *`
 * @param connection connection handle
 * @param con_cls a `struct ConnectionContext *`
 *        the #MHD_AccessHandlerCallback
 * @param toe reason for request termination
 * @see #MHD_OPTION_NOTIFY_COMPLETED
 * @ingroup request
 */
static void
handle_mhd_completion_callback (void *cls,
                                struct MHD_Connection *connection,
                                void **con_cls,
                                enum MHD_RequestTerminationCode toe)
{
  struct TALER_FAKEBANK_Handle *h = cls;
  struct ConnectionContext *cc = *con_cls;

  (void) h;
  (void) connection;
  (void) toe;
  if (NULL == cc)
    return;
  cc->ctx_cleaner (cc->ctx);
  GNUNET_free (cc);
}


/**
 * Handle incoming HTTP request.
 *
 * @param cls a `struct TALER_FAKEBANK_Handle`
 * @param connection the connection
 * @param url the requested url
 * @param method the method (POST, GET, ...)
 * @param version HTTP version (ignored)
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request
 * @return MHD result code
 */
static MHD_RESULT
handle_mhd_request (void *cls,
                    struct MHD_Connection *connection,
                    const char *url,
                    const char *method,
                    const char *version,
                    const char *upload_data,
                    size_t *upload_data_size,
                    void **con_cls)
{
  struct TALER_FAKEBANK_Handle *h = cls;

  (void) version;
  if (0 == strncmp (url,
                    "/taler-integration/",
                    strlen ("/taler-integration/")))
  {
    url += strlen ("/taler-integration");
    return TALER_FAKEBANK_tbi_main_ (h,
                                     connection,
                                     url,
                                     method,
                                     upload_data,
                                     upload_data_size,
                                     con_cls);
  }
  return TALER_FAKEBANK_bank_main_ (h,
                                    connection,
                                    url,
                                    method,
                                    upload_data,
                                    upload_data_size,
                                    con_cls);
}


#if EPOLL_SUPPORT
/**
 * Schedule MHD.  This function should be called initially when an
 * MHD is first getting its client socket, and will then automatically
 * always be called later whenever there is work to be done.
 *
 * @param h fakebank handle to schedule MHD for
 */
static void
schedule_httpd (struct TALER_FAKEBANK_Handle *h)
{
  int haveto;
  MHD_UNSIGNED_LONG_LONG timeout;
  struct GNUNET_TIME_Relative tv;

  GNUNET_assert (-1 != h->mhd_fd);
  haveto = MHD_get_timeout (h->mhd_bank,
                            &timeout);
  if (MHD_YES == haveto)
    tv.rel_value_us = (uint64_t) timeout * 1000LL;
  else
    tv = GNUNET_TIME_UNIT_FOREVER_REL;
  if (NULL != h->mhd_task)
    GNUNET_SCHEDULER_cancel (h->mhd_task);
  h->mhd_task =
    GNUNET_SCHEDULER_add_read_net (tv,
                                   h->mhd_rfd,
                                   &TALER_FAKEBANK_run_mhd_,
                                   h);
}


#else
/**
 * Schedule MHD.  This function should be called initially when an
 * MHD is first getting its client socket, and will then automatically
 * always be called later whenever there is work to be done.
 *
 * @param h fakebank handle to schedule MHD for
 */
static void
schedule_httpd (struct TALER_FAKEBANK_Handle *h)
{
  fd_set rs;
  fd_set ws;
  fd_set es;
  struct GNUNET_NETWORK_FDSet *wrs;
  struct GNUNET_NETWORK_FDSet *wws;
  int max;
  int haveto;
  MHD_UNSIGNED_LONG_LONG timeout;
  struct GNUNET_TIME_Relative tv;

#ifdef __linux__
  GNUNET_assert (-1 == h->lp_event);
#else
  GNUNET_assert (-1 == h->lp_event_in);
  GNUNET_assert (-1 == h->lp_event_out);
#endif
  FD_ZERO (&rs);
  FD_ZERO (&ws);
  FD_ZERO (&es);
  max = -1;
  if (MHD_YES != MHD_get_fdset (h->mhd_bank,
                                &rs,
                                &ws,
                                &es,
                                &max))
  {
    GNUNET_assert (0);
    return;
  }
  haveto = MHD_get_timeout (h->mhd_bank,
                            &timeout);
  if (MHD_YES == haveto)
    tv.rel_value_us = (uint64_t) timeout * 1000LL;
  else
    tv = GNUNET_TIME_UNIT_FOREVER_REL;
  if (-1 != max)
  {
    wrs = GNUNET_NETWORK_fdset_create ();
    wws = GNUNET_NETWORK_fdset_create ();
    GNUNET_NETWORK_fdset_copy_native (wrs,
                                      &rs,
                                      max + 1);
    GNUNET_NETWORK_fdset_copy_native (wws,
                                      &ws,
                                      max + 1);
  }
  else
  {
    wrs = NULL;
    wws = NULL;
  }
  if (NULL != h->mhd_task)
    GNUNET_SCHEDULER_cancel (h->mhd_task);
  h->mhd_task =
    GNUNET_SCHEDULER_add_select (GNUNET_SCHEDULER_PRIORITY_DEFAULT,
                                 tv,
                                 wrs,
                                 wws,
                                 &TALER_FAKEBANK_run_mhd_,
                                 h);
  if (NULL != wrs)
    GNUNET_NETWORK_fdset_destroy (wrs);
  if (NULL != wws)
    GNUNET_NETWORK_fdset_destroy (wws);
}


#endif


/**
 * Task run whenever HTTP server operations are pending.
 *
 * @param cls the `struct TALER_FAKEBANK_Handle`
 */
void
TALER_FAKEBANK_run_mhd_ (void *cls)
{
  struct TALER_FAKEBANK_Handle *h = cls;

  h->mhd_task = NULL;
  h->mhd_again = true;
  while (h->mhd_again)
  {
    h->mhd_again = false;
    MHD_run (h->mhd_bank);
  }
#ifdef __linux__
  GNUNET_assert (-1 == h->lp_event);
#else
  GNUNET_assert (-1 == h->lp_event_in);
  GNUNET_assert (-1 == h->lp_event_out);
#endif
  schedule_httpd (h);
}


struct TALER_FAKEBANK_Handle *
TALER_FAKEBANK_start (uint16_t port,
                      const char *currency)
{
  return TALER_FAKEBANK_start2 (port,
                                currency,
                                65536, /* RAM limit */
                                1);
}


struct TALER_FAKEBANK_Handle *
TALER_FAKEBANK_start2 (uint16_t port,
                       const char *currency,
                       uint64_t ram_limit,
                       unsigned int num_threads)
{
  struct TALER_Amount zero;

  if (GNUNET_OK !=
      TALER_amount_set_zero (currency,
                             &zero))
  {
    GNUNET_break (0);
    return NULL;
  }
  return TALER_FAKEBANK_start3 ("localhost",
                                port,
                                NULL,
                                currency,
                                ram_limit,
                                num_threads,
                                &zero);
}


struct TALER_FAKEBANK_Handle *
TALER_FAKEBANK_start3 (const char *hostname,
                       uint16_t port,
                       const char *exchange_url,
                       const char *currency,
                       uint64_t ram_limit,
                       unsigned int num_threads,
                       const struct TALER_Amount *signup_bonus)
{
  struct TALER_FAKEBANK_Handle *h;

  if (SIZE_MAX / sizeof (struct Transaction *) < ram_limit)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "This CPU architecture does not support keeping %llu transactions in RAM\n",
                (unsigned long long) ram_limit);
    return NULL;
  }
  GNUNET_assert (strlen (currency) < TALER_CURRENCY_LEN);
  if (0 != strcmp (signup_bonus->currency,
                   currency))
  {
    GNUNET_break (0);
    return NULL;
  }
  h = GNUNET_new (struct TALER_FAKEBANK_Handle);
  h->signup_bonus = *signup_bonus;
  if (NULL != exchange_url)
    h->exchange_url = GNUNET_strdup (exchange_url);
#ifdef __linux__
  h->lp_event = -1;
#else
  h->lp_event_in = -1;
  h->lp_event_out = -1;
#endif
#if EPOLL_SUPPORT
  h->mhd_fd = -1;
#endif
  h->port = port;
  h->ram_limit = ram_limit;
  h->serial_counter = 0;
  GNUNET_assert (0 ==
                 pthread_mutex_init (&h->accounts_lock,
                                     NULL));
  GNUNET_assert (0 ==
                 pthread_mutex_init (&h->rpubs_lock,
                                     NULL));
  GNUNET_assert (0 ==
                 pthread_mutex_init (&h->uuid_map_lock,
                                     NULL));
  GNUNET_assert (0 ==
                 pthread_mutex_init (&h->big_lock,
                                     NULL));
  h->transactions
    = GNUNET_malloc_large (sizeof (struct Transaction *)
                           * ram_limit);
  if (NULL == h->transactions)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "malloc");
    TALER_FAKEBANK_stop (h);
    return NULL;
  }
  h->accounts = GNUNET_CONTAINER_multihashmap_create (128,
                                                      GNUNET_NO);
  h->uuid_map = GNUNET_CONTAINER_multihashmap_create (ram_limit * 4 / 3,
                                                      GNUNET_YES);
  if (NULL == h->uuid_map)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "malloc");
    TALER_FAKEBANK_stop (h);
    return NULL;
  }
  h->rpubs = GNUNET_CONTAINER_multipeermap_create (ram_limit * 4 / 3,
                                                   GNUNET_NO);
  if (NULL == h->rpubs)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "malloc");
    TALER_FAKEBANK_stop (h);
    return NULL;
  }
  h->lp_heap = GNUNET_CONTAINER_heap_create (GNUNET_CONTAINER_HEAP_ORDER_MIN);
  h->currency = GNUNET_strdup (currency);
  h->hostname = GNUNET_strdup (hostname);
  GNUNET_asprintf (&h->my_baseurl,
                   "http://%s:%u/",
                   h->hostname,
                   (unsigned int) port);
  if (0 == num_threads)
  {
    h->mhd_bank = MHD_start_daemon (
      MHD_USE_DEBUG
#if EPOLL_SUPPORT
      | MHD_USE_EPOLL
#endif
      | MHD_USE_DUAL_STACK
      | MHD_ALLOW_SUSPEND_RESUME,
      port,
      NULL, NULL,
      &handle_mhd_request, h,
      MHD_OPTION_NOTIFY_COMPLETED,
      &handle_mhd_completion_callback, h,
      MHD_OPTION_LISTEN_BACKLOG_SIZE,
      (unsigned int) 1024,
      MHD_OPTION_CONNECTION_LIMIT,
      (unsigned int) 65536,
      MHD_OPTION_END);
    if (NULL == h->mhd_bank)
    {
      TALER_FAKEBANK_stop (h);
      return NULL;
    }
#if EPOLL_SUPPORT
    h->mhd_fd = MHD_get_daemon_info (h->mhd_bank,
                                     MHD_DAEMON_INFO_EPOLL_FD)->epoll_fd;
    h->mhd_rfd = GNUNET_NETWORK_socket_box_native (h->mhd_fd);
#endif
    schedule_httpd (h);
  }
  else
  {
#ifdef __linux__
    h->lp_event = eventfd (0,
                           EFD_CLOEXEC);
    if (-1 == h->lp_event)
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                           "eventfd");
      TALER_FAKEBANK_stop (h);
      return NULL;
    }
#else
    {
      int pipefd[2];

      if (0 != pipe (pipefd))
      {
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                             "pipe");
        TALER_FAKEBANK_stop (h);
        return NULL;
      }
      h->lp_event_out = pipefd[0];
      h->lp_event_in = pipefd[1];
    }
#endif
    if (0 !=
        pthread_create (&h->lp_thread,
                        NULL,
                        &TALER_FAKEBANK_lp_expiration_thread_,
                        h))
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                           "pthread_create");
#ifdef __linux__
      GNUNET_break (0 == close (h->lp_event));
      h->lp_event = -1;
#else
      GNUNET_break (0 == close (h->lp_event_in));
      GNUNET_break (0 == close (h->lp_event_out));
      h->lp_event_in = -1;
      h->lp_event_out = -1;
#endif
      TALER_FAKEBANK_stop (h);
      return NULL;
    }
    h->mhd_bank = MHD_start_daemon (
      MHD_USE_DEBUG
      | MHD_USE_AUTO_INTERNAL_THREAD
      | MHD_ALLOW_SUSPEND_RESUME
      | MHD_USE_TURBO
      | MHD_USE_TCP_FASTOPEN
      | MHD_USE_DUAL_STACK,
      port,
      NULL, NULL,
      &handle_mhd_request, h,
      MHD_OPTION_NOTIFY_COMPLETED,
      &handle_mhd_completion_callback, h,
      MHD_OPTION_LISTEN_BACKLOG_SIZE,
      (unsigned int) 1024,
      MHD_OPTION_CONNECTION_LIMIT,
      (unsigned int) 65536,
      MHD_OPTION_THREAD_POOL_SIZE,
      num_threads,
      MHD_OPTION_END);
    if (NULL == h->mhd_bank)
    {
      GNUNET_break (0);
      TALER_FAKEBANK_stop (h);
      return NULL;
    }
  }
  return h;
}


/* end of fakebank.c */
