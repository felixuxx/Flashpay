/*
  This file is part of TALER
  (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file include/taler_testing_auditor_lib.h
 * @brief API for writing an interpreter to test Taler components
 * @author Christian Grothoff <christian@grothoff.org>
 * @author Marcello Stanisci
 */
#ifndef TALER_TESTING_AUDITOR_LIB_H
#define TALER_TESTING_AUDITOR_LIB_H

#include "taler_util.h"
#include "taler_exchange_service.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include <microhttpd.h>


/* ********************* Helper functions ********************* */


/**
 * Wait for the auditor to have started. Waits for at
 * most 10s, after that returns 77 to indicate an error.
 *
 * @param base_url what URL should we expect the exchange
 *        to be running at
 * @return 0 on success
 */
int
TALER_TESTING_AUDITOR_wait_auditor_ready (const char *base_url);


/**
 * Remove files from previous runs
 */
void
TALER_TESTING_AUDITOR_cleanup_files (const char *config_name);


/**
 * Initialize scheduler loop and curl context for the testcase
 * including starting and stopping the auditor and exchange using the
 * given configuration file.
 *
 * @param main_cb routine containing all the commands to run.
 * @param main_cb_cls closure for @a main_cb, typically NULL.
 * @param config_file configuration file for the test-suite.
 *
 * @return #GNUNET_OK if all is okay, != #GNUNET_OK otherwise.
 *         non-#GNUNET_OK codes are #GNUNET_SYSERR most of the
 *         time.
 */
int
TALER_TESTING_AUDITOR_setup_with_auditor (TALER_TESTING_Main main_cb,
					  void *main_cb_cls,
					  const char *config_filename);


#endif
