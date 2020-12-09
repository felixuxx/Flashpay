/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file testing/testing_api_cmd_rewind.c
 * @brief command to rewind the instruction pointer.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_exchange_service.h"
#include "taler_testing_lib.h"


/**
 * State for a "rewind" CMD.
 */
struct RewindIpState
{
  /**
   * Instruction pointer to set into the interpreter.
   */
  const char *target_label;

  /**
   * How many times this set should take place.  However, this value lives at
   * the calling process, and this CMD is only in charge of checking and
   * decremeting it.
   */
  unsigned int counter;
};


/**
 * Only defined to respect the API.
 */
static void
rewind_ip_cleanup (void *cls,
                   const struct TALER_TESTING_Command *cmd)
{
  (void) cls;
  (void) cmd;
}


/**
 * Seek for the @a target command in @a batch (and rewind to it
 * if successful).
 *
 * @param is the interpreter state (for failures)
 * @param cmd batch to search for @a target
 * @param target command to search for
 * @return #GNUNET_OK on success, #GNUNET_NO if target was not found,
 *         #GNUNET_SYSERR if target is in the future and we failed
 */
static int
seek_batch (struct TALER_TESTING_Interpreter *is,
            const struct TALER_TESTING_Command *cmd,
            const struct TALER_TESTING_Command *target)
{
  unsigned int new_ip;
#define BATCH_INDEX 1
  struct TALER_TESTING_Command *batch;
  struct TALER_TESTING_Command *current;
  struct TALER_TESTING_Command *icmd;
  const struct TALER_TESTING_Command *match;

  current = TALER_TESTING_cmd_batch_get_current (cmd);
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_cmd (cmd,
                                              BATCH_INDEX,
                                              &batch));
  match = NULL;
  for (new_ip = 0;
       NULL != (icmd = &batch[new_ip]);
       new_ip++)
  {
    if (current == target)
      current = NULL;
    if (icmd == target)
    {
      match = icmd;
      break;
    }
    if (TALER_TESTING_cmd_is_batch (icmd))
    {
      int ret = seek_batch (is,
                            icmd,
                            target);
      if (GNUNET_SYSERR == ret)
        return GNUNET_SYSERR; /* failure! */
      if (GNUNET_OK == ret)
      {
        match = icmd;
        break;
      }
    }
  }
  if (NULL == current)
  {
    /* refuse to jump forward */
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return GNUNET_SYSERR;
  }
  if (NULL == match)
    return GNUNET_NO; /* not found */
  TALER_TESTING_cmd_batch_set_current (cmd,
                                       new_ip);
  return GNUNET_OK;
}


/**
 * Run the "rewind" CMD.
 *
 * @param cls closure.
 * @param cmd command being executed now.
 * @param is the interpreter state.
 */
static void
rewind_ip_run (void *cls,
               const struct TALER_TESTING_Command *cmd,
               struct TALER_TESTING_Interpreter *is)
{
  struct RewindIpState *ris = cls;
  const struct TALER_TESTING_Command *target;
  unsigned int new_ip;

  (void) cmd;
  if (0 == ris->counter)
  {
    TALER_TESTING_interpreter_next (is);
    return;
  }
  target
    = TALER_TESTING_interpreter_lookup_command (is,
                                                ris->target_label);
  if (NULL == target)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  ris->counter--;
  for (new_ip = 0;
       NULL != is->commands[new_ip].label;
       new_ip++)
  {
    const struct TALER_TESTING_Command *cmd = &is->commands[new_ip];

    if (cmd == target)
      break;
    if (TALER_TESTING_cmd_is_batch (cmd))
    {
      int ret = seek_batch (is,
                            cmd,
                            target);
      if (GNUNET_SYSERR == ret)
        return;   /* failure! */
      if (GNUNET_OK == ret)
        break;
    }
  }
  if (new_ip > is->ip)
  {
    /* refuse to jump forward */
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  is->ip = new_ip - 1; /* -1 because the next function will advance by one */
  TALER_TESTING_interpreter_next (is);
}


/**
 * Make the instruction pointer point to @a new_ip
 * only if @a counter is greater than zero.
 *
 * @param label command label
 * @param target_label label of the new instruction pointer's destination after the jump;
 *                     must be before the current instruction
 * @param counter counts how many times the rewinding is to happen.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_rewind_ip (const char *label,
                             const char *target_label,
                             unsigned int counter)
{
  struct RewindIpState *ris;

  ris = GNUNET_new (struct RewindIpState);
  ris->target_label = target_label;
  ris->counter = counter;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ris,
      .label = label,
      .run = &rewind_ip_run,
      .cleanup = &rewind_ip_cleanup
    };

    return cmd;
  }
}
