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
  struct TALER_TESTING_Command *batch;

  /* Internal comand pointer.  */
  int batch_ip;
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

  bs->batch_ip++;

  TALER_LOG_DEBUG ("Running batched command: %s\n",
                   bs->batch[bs->batch_ip].label);

  /* hit end command, leap to next top-level command.  */
  if (NULL == bs->batch[bs->batch_ip].label)
  {
    TALER_LOG_INFO ("Exiting from batch: %s\n",
                    cmd->label);
    TALER_TESTING_interpreter_next (is);
    return;
  }

  bs->batch[bs->batch_ip].run (bs->batch[bs->batch_ip].cls,
                               &bs->batch[bs->batch_ip],
                               is);
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
  GNUNET_free_non_null (bs->batch);
}


/**
 * Offer internal data from a "batch" CMD, to other commands.
 *
 * @param cls closure.
 * @param ret[out] result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 *
 * @return #GNUNET_OK on success.
 */
static int
batch_traits (void *cls,
              void **ret,
              const char *trait,
              unsigned int index)
{
  #define CURRENT_CMD_INDEX 0
  #define BATCH_INDEX 1

  struct BatchState *bs = cls;

  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_cmd
      (CURRENT_CMD_INDEX, &bs->batch[bs->batch_ip]),
    TALER_TESTING_make_trait_cmd
      (BATCH_INDEX, bs->batch),
    TALER_TESTING_trait_end ()
  };

  /* Always return current command.  */
  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
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
  unsigned int i;

  cmd.meta = GNUNET_YES;
  bs = GNUNET_new (struct BatchState);
  bs->batch_ip = -1;

  /* Get number of commands.  */
  for (i=0;NULL != batch[i].label;i++)
    /* noop */
    ;

  bs->batch = GNUNET_new_array (i + 1,
                                struct TALER_TESTING_Command);
  memcpy (bs->batch,
          batch,
          sizeof (struct TALER_TESTING_Command) * i);

  cmd.cls = bs;
  cmd.label = label;
  cmd.run = &batch_run;
  cmd.cleanup = &batch_cleanup;
  cmd.traits = &batch_traits;

  return cmd;
}
