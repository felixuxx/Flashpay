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
 * @file testing/testing_api_cmd_batch.c
 * @brief Implement batch-execution of CMDs.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "batch" CMD.
 */
struct BatchState
{
  /**
   * CMDs batch.
   */
  struct TALER_TESTING_Command *batch;

  /**
   * Internal command pointer.
   */
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

  if (NULL != bs->batch[bs->batch_ip].label)
    TALER_LOG_INFO ("Running batched command: %s\n",
                    bs->batch[bs->batch_ip].label);

  /* hit end command, leap to next top-level command.  */
  if (NULL == bs->batch[bs->batch_ip].label)
  {
    TALER_LOG_INFO ("Exiting from batch: %s\n",
                    cmd->label);
    TALER_TESTING_interpreter_next (is);
    return;
  }
  bs->batch[bs->batch_ip].start_time
    = bs->batch[bs->batch_ip].last_req_time
      = GNUNET_TIME_absolute_get ();
  bs->batch[bs->batch_ip].num_tries = 1;
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

  (void) cmd;
  for (unsigned int i = 0;
       NULL != bs->batch[i].label;
       i++)
    bs->batch[i].cleanup (bs->batch[i].cls,
                          &bs->batch[i]);
  GNUNET_free (bs->batch);
  GNUNET_free (bs);
}


/**
 * Offer internal data from a "batch" CMD, to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static int
batch_traits (void *cls,
              const void **ret,
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
  struct BatchState *bs;
  unsigned int i;

  bs = GNUNET_new (struct BatchState);

  /* Get number of commands.  */
  for (i = 0; NULL != batch[i].label; i++)
    /* noop */
    ;

  bs->batch = GNUNET_new_array (i + 1,
                                struct TALER_TESTING_Command);
  memcpy (bs->batch,
          batch,
          sizeof (struct TALER_TESTING_Command) * i);
  {
    struct TALER_TESTING_Command cmd = {
      .cls = bs,
      .label = label,
      .run = &batch_run,
      .cleanup = &batch_cleanup,
      .traits = &batch_traits
    };

    return cmd;
  }
}


/**
 * Advance internal pointer to next command.
 *
 * @param is interpreter state.
 */
void
TALER_TESTING_cmd_batch_next (struct TALER_TESTING_Interpreter *is)
{
  struct BatchState *bs = is->commands[is->ip].cls;

  if (NULL == bs->batch[bs->batch_ip].label)
  {
    is->commands[is->ip].finish_time = GNUNET_TIME_absolute_get ();
    is->ip++;
    return;
  }
  bs->batch[bs->batch_ip].finish_time = GNUNET_TIME_absolute_get ();
  bs->batch_ip++;
}


/**
 * Test if this command is a batch command.
 *
 * @return false if not, true if it is a batch command
 */
int
TALER_TESTING_cmd_is_batch (const struct TALER_TESTING_Command *cmd)
{
  return cmd->run == &batch_run;
}


/**
 * Obtain what command the batch is at.
 *
 * @return cmd current batch command
 */
struct TALER_TESTING_Command *
TALER_TESTING_cmd_batch_get_current (const struct TALER_TESTING_Command *cmd)
{
  struct BatchState *bs = cmd->cls;

  GNUNET_assert (cmd->run == &batch_run);
  return &bs->batch[bs->batch_ip];
}


/**
 * Set what command the batch should be at.
 *
 * @param cmd current batch command
 * @param new_ip where to move the IP
 */
void
TALER_TESTING_cmd_batch_set_current (const struct TALER_TESTING_Command *cmd,
                                     unsigned int new_ip)
{
  struct BatchState *bs = cmd->cls;

  /* sanity checks */
  GNUNET_assert (cmd->run == &batch_run);
  for (unsigned int i = 0; i < new_ip; i++)
    GNUNET_assert (NULL != bs->batch[i].label);
  /* actual logic */
  bs->batch_ip = new_ip;
}
