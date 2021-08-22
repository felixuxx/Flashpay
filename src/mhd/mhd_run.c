/*
  This file is part of TALER
  Copyright (C) 2019-2021 Taler Systems SA

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
 * @file mhd_run.c
 * @brief API for running an MHD daemon with the
 *        GNUnet scheduler
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_util.h"
#include "taler_mhd_lib.h"


/**
 * Set if we should immediately MHD_run() again.
 */
static int triggered;

/**
 * Task running the HTTP server.
 */
static struct GNUNET_SCHEDULER_Task *mhd_task;

/**
 * The MHD daemon we are running.
 */
static struct MHD_Daemon *mhd;


/**
 * Function that queries MHD's select sets and
 * starts the task waiting for them.
 */
static struct GNUNET_SCHEDULER_Task *
prepare_daemon (void);


/**
 * Call MHD to process pending requests and then go back
 * and schedule the next run.
 *
 * @param cls NULL
 */
static void
run_daemon (void *cls)
{
  mhd_task = NULL;
  do {
    triggered = 0;
    GNUNET_assert (MHD_YES ==
                   MHD_run (mhd));
  } while (0 != triggered);
  mhd_task = prepare_daemon ();
}


/**
 * Function that queries MHD's select sets and starts the task waiting for
 * them.
 *
 * @return task handle for the MHD task.
 */
static struct GNUNET_SCHEDULER_Task *
prepare_daemon (void)
{
  struct GNUNET_SCHEDULER_Task *ret;
  fd_set rs;
  fd_set ws;
  fd_set es;
  struct GNUNET_NETWORK_FDSet *wrs;
  struct GNUNET_NETWORK_FDSet *wws;
  int max;
  MHD_UNSIGNED_LONG_LONG timeout;
  int haveto;
  struct GNUNET_TIME_Relative tv;

  FD_ZERO (&rs);
  FD_ZERO (&ws);
  FD_ZERO (&es);
  wrs = GNUNET_NETWORK_fdset_create ();
  wws = GNUNET_NETWORK_fdset_create ();
  max = -1;
  GNUNET_assert (MHD_YES ==
                 MHD_get_fdset (mhd,
                                &rs,
                                &ws,
                                &es,
                                &max));
  haveto = MHD_get_timeout (mhd,
                            &timeout);
  if (haveto == MHD_YES)
    tv = GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS,
                                        timeout);
  else
    tv = GNUNET_TIME_UNIT_FOREVER_REL;
  GNUNET_NETWORK_fdset_copy_native (wrs,
                                    &rs,
                                    max + 1);
  GNUNET_NETWORK_fdset_copy_native (wws,
                                    &ws,
                                    max + 1);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Adding run_daemon select task\n");
  ret = GNUNET_SCHEDULER_add_select (GNUNET_SCHEDULER_PRIORITY_HIGH,
                                     tv,
                                     wrs,
                                     wws,
                                     &run_daemon,
                                     NULL);
  GNUNET_NETWORK_fdset_destroy (wrs);
  GNUNET_NETWORK_fdset_destroy (wws);
  return ret;
}


void
TALER_MHD_daemon_start (struct MHD_Daemon *daemon)
{
  GNUNET_assert (NULL == mhd);
  mhd = daemon;
  mhd_task = prepare_daemon ();
}


struct MHD_Daemon *
TALER_MHD_daemon_stop (void)
{
  struct MHD_Daemon *ret;

  if (NULL != mhd_task)
  {
    GNUNET_SCHEDULER_cancel (mhd_task);
    mhd_task = NULL;
  }
  ret = mhd;
  mhd = NULL;
  return ret;
}


void
TALER_MHD_daemon_trigger (void)
{
  if (NULL != mhd_task)
  {
    GNUNET_SCHEDULER_cancel (mhd_task);
    mhd_task = NULL;
    run_daemon (NULL);
  }
  else
  {
    triggered = 1;
  }
}


/* end of mhd_run.c */
