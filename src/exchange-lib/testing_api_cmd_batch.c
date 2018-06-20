/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
 * @file exchange/testing_api_cmd_batch.c
 * @brief Implement batch-execution of CMDs.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_testing_lib.h"


/**
 * State for a "batch" CMD.
 */
struct BatchState
{
  /* CMDs batch.  */
  const struct TALER_TESTING_Command *batch;

  /* Internal comand pointer.  */
  unsigned int batch_ip;
};


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command being executed.
 * @param is the interpreter state.
 */
static void
batch_run (void *cls,
           const struct TALER_TESTING_Command *cmd,
           struct TALER_TESTING_Interpreter *is)
{
  struct BatchState *bs = cls;

  /* hit end command, leap to next top-level command.  */
  if (NULL == bs->batch[bs->batch_ip].label)
    TALER_TESTING_interpreter_next (is);

  bs->batch[bs->batch_ip].run (bs->batch[bs->batch_ip].cls,
                               &bs->batch[bs->batch_ip],
                               is);
  bs->batch_ip++;
}


/**
 * Cleanup the state from a "reserve status" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
batch_cleanup (void *cls,
               const struct TALER_TESTING_Command *cmd)
{
  struct BatchState *bs = cls;

  for (unsigned int i=0;
       NULL != bs->batch[i].label;
       i++)
    bs->batch[i].cleanup (bs->batch[i].cls,
                          &bs->batch[i]);
}


/**
 * Create a "batch" command.  Such command takes a
 * end_CMD-terminated array of CMDs and executed them.
 * Once it hits the end CMD, it passes the control
 * to the next top-level CMD, regardless of it being
 * another batch or ordinary CMD.
 *
 * @param label the command label.
 * @param batch array of CMDs to execute.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_batch (const char *label,
                         struct TALER_TESTING_Command *batch)
{
  struct TALER_TESTING_Command cmd;
  struct BatchState *bs;

  bs = GNUNET_new (struct BatchState);
  bs->batch = batch;

  cmd.cls = bs;
  cmd.label = label;
  cmd.run = &batch_run;
  cmd.cleanup = &batch_cleanup;

  return cmd;
}
