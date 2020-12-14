/*
  This file is part of TALER
  Copyright (C) 2014--2020 Taler Systems SA

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
 * @file taler-exchange-httpd_loop.c
 * @brief management of our main loop
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <pthread.h>
#include "taler-exchange-httpd_loop.h"


/* ************************* Signal logic ************************** */

/**
 * Pipe used for signaling reloading of our key state.
 */
static int reload_pipe[2] = { -1, -1 };


/**
 * Handle a signal, writing relevant signal numbers to the pipe.
 *
 * @param signal_number the signal number
 */
static void
handle_signal (int signal_number)
{
  char c = (char) signal_number; /* never seen a signal_number > 127 on any platform */

  (void) ! write (reload_pipe[1],
                  &c,
                  1);
  /* While one might like to "handle errors" here, even logging via fprintf()
     isn't safe inside of a signal handler. So there is nothing we safely CAN
     do. OTOH, also very little that can go wrong in practice. Calling _exit()
     on errors might be a possibility, but that might do more harm than good. *///
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sigint (void)
{
  handle_signal (SIGINT);
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sigterm (void)
{
  handle_signal (SIGTERM);
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sighup (void)
{
  handle_signal (SIGHUP);
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sigchld (void)
{
  handle_signal (SIGCHLD);
}


int
TEH_loop_run (void)
{
  int ret;

  ret = 2;
  while (2 == ret)
  {
    char c;
    ssize_t res;

    errno = 0;
    res = read (reload_pipe[0],
                &c,
                1);
    if ((res < 0) && (EINTR != errno))
    {
      GNUNET_break (0);
      ret = GNUNET_SYSERR;
      break;
    }
    if (EINTR == errno)
      continue;
    switch (c)
    {
    case SIGTERM:
    case SIGINT:
      /* terminate */
      ret = GNUNET_OK;
      break;
    case SIGHUP:
      /* restart updated binary */
      ret = GNUNET_NO;
      break;
#if HAVE_DEVELOPER
    case SIGCHLD:
      /* running in test-mode, test finished, terminate */
      ret = GNUNET_OK;
      break;
#endif
    default:
      /* unexpected character */
      GNUNET_break (0);
      break;
    }
  }
  return ret;
}


static struct GNUNET_SIGNAL_Context *sigterm;
static struct GNUNET_SIGNAL_Context *sigint;
static struct GNUNET_SIGNAL_Context *sighup;
static struct GNUNET_SIGNAL_Context *sigchld;


int
TEH_loop_init (void)
{
  if (0 != pipe (reload_pipe))
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "pipe");
    return GNUNET_SYSERR;
  }
  sigterm = GNUNET_SIGNAL_handler_install (SIGTERM,
                                           &handle_sigterm);
  sigint = GNUNET_SIGNAL_handler_install (SIGINT,
                                          &handle_sigint);
  sighup = GNUNET_SIGNAL_handler_install (SIGHUP,
                                          &handle_sighup);
  sigchld = GNUNET_SIGNAL_handler_install (SIGCHLD,
                                           &handle_sigchld);
  return GNUNET_OK;
}


void
TEH_loop_done (void)
{
  if (NULL != sigterm)
  {
    GNUNET_SIGNAL_handler_uninstall (sigterm);
    sigterm = NULL;
  }
  if (NULL != sigint)
  {
    GNUNET_SIGNAL_handler_uninstall (sigint);
    sigint = NULL;
  }
  if (NULL != sighup)
  {
    GNUNET_SIGNAL_handler_uninstall (sighup);
    sighup = NULL;
  }
  if (NULL != sigchld)
  {
    GNUNET_SIGNAL_handler_uninstall (sigchld);
    sigchld = NULL;
  }
  if (-1 != reload_pipe[0])
  {
    GNUNET_break (0 == close (reload_pipe[0]));
    GNUNET_break (0 == close (reload_pipe[1]));
    reload_pipe[0] = reload_pipe[1] = -1;
  }
}


/* end of taler-exchange-httpd_loop.c */
