/*
  This file is part of TALER
  Copyright (C) 2018-2020 Taler Systems SA

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
 * @file testing/testing_api_cmd_bank_check_empty.c
 * @brief command to check if a particular wire transfer took
 *        place.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_fakebank_lib.h"


/**
 * Cleanup the state, only defined to respect the API.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
check_bank_empty_cleanup
  (void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  (void) cls;
  (void) cmd;
  return;
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
check_bank_empty_run (void *cls,
                      const struct TALER_TESTING_Command *cmd,
                      struct TALER_TESTING_Interpreter *is)
{
  (void) cls;
  (void) cmd;
  if (GNUNET_OK != TALER_FAKEBANK_check_empty (is->fakebank))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Some commands (notably "bank history") could randomly
 * look for traits; this way makes sure we don't segfault.
 */
static int
check_bank_empty_traits (void *cls,
                         const void **ret,
                         const char *trait,
                         unsigned int index)
{
  (void) cls;
  (void) ret;
  (void) trait;
  (void) index;
  return GNUNET_SYSERR;
}


/**
 * Checks whether all the wire transfers got "checked"
 * by the "bank check" CMD.
 *
 * @param label command label.
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_empty (const char *label)
{
  struct TALER_TESTING_Command cmd = {
    .label = label,
    .run = &check_bank_empty_run,
    .cleanup = &check_bank_empty_cleanup,
    .traits = &check_bank_empty_traits
  };

  return cmd;
}
