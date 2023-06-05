/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_system_start.c
 * @brief run taler-benchmark-setup.sh command
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "system" CMD.
 */
struct SystemState
{

  /**
   * System process.
   */
  struct GNUNET_OS_Process *system_proc;

  /**
   * Input pipe to @e system_proc, used to keep the
   * process alive until we are done.
   */
  struct GNUNET_DISK_PipeHandle *pipe_in;

  /**
   * Output pipe to @e system_proc, used to find out
   * when the services are ready.
   */
  struct GNUNET_DISK_PipeHandle *pipe_out;

  /**
   * Task reading from @e pipe_in.
   */
  struct GNUNET_SCHEDULER_Task *reader;

  /**
   * Waiting for child to die.
   */
  struct GNUNET_ChildWaitHandle *cwh;

  /**
   * Our interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * NULL-terminated array of command-line arguments.
   */
  char **args;

  /**
   * Current input buffer, 0-terminated.  Contains the last 15 bytes of input
   * so we can search them again for the "<<READY>>" tag.
   */
  char ibuf[16];

  /**
   * Did we find the ready tag?
   */
  bool ready;

  /**
   * Is the child process still running?
   */
  bool active;
};


/**
 * Defines a GNUNET_ChildCompletedCallback which is sent back
 * upon death or completion of a child process.
 *
 * @param cls our `struct SystemState *`
 * @param type type of the process
 * @param exit_code status code of the process
 */
static void
setup_terminated (void *cls,
                  enum GNUNET_OS_ProcessStatusType type,
                  long unsigned int exit_code)
{
  struct SystemState *as = cls;

  as->cwh = NULL;
  as->active = false;
  if (NULL != as->reader)
  {
    GNUNET_SCHEDULER_cancel (as->reader);
    as->reader = NULL;
  }
  if (! as->ready)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Launching Taler system failed: %d/%llu\n",
                (int) type,
                (unsigned long long) exit_code);
    TALER_TESTING_interpreter_fail (as->is);
    return;
  }
}


/**
 * Start helper to read from stdout of child.
 *
 * @param as our system state
 */
static void
start_reader (struct SystemState *as);


static void
read_stdout (void *cls)
{
  struct SystemState *as = cls;
  const struct GNUNET_DISK_FileHandle *fh;
  char buf[1024 * 10];
  ssize_t ret;
  size_t off = 0;

  as->reader = NULL;
  strcpy (buf,
          as->ibuf);
  off = strlen (buf);
  fh = GNUNET_DISK_pipe_handle (as->pipe_out,
                                GNUNET_DISK_PIPE_END_READ);
  ret = GNUNET_DISK_file_read (fh,
                               &buf[off],
                               sizeof (buf) - off);
  if (-1 == ret)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "read");
    TALER_TESTING_interpreter_fail (as->is);
    return;
  }
  if (0 == ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Child closed stdout\n");
    return;
  }
  start_reader (as);
  off += ret;
  if (as->ready)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Taler system UP\n");
    TALER_TESTING_interpreter_next (as->is);
    return; /* done */
  }
  if (NULL !=
      memmem (buf,
              off,
              "\n<<READY>>\n",
              strlen ("\n<<READY>>\n")))
  {
    as->ready = true;
    return;
  }

  {
    size_t mcpy;

    mcpy = GNUNET_MIN (off,
                       sizeof (as->ibuf) - 1);
    memcpy (as->ibuf,
            &buf[off - mcpy],
            mcpy);
    as->ibuf[mcpy] = '\0';
  }
}


static void
start_reader (struct SystemState *as)
{
  const struct GNUNET_DISK_FileHandle *fh;

  GNUNET_assert (NULL == as->reader);
  fh = GNUNET_DISK_pipe_handle (as->pipe_out,
                                GNUNET_DISK_PIPE_END_READ);
  as->reader = GNUNET_SCHEDULER_add_read_file (GNUNET_TIME_UNIT_FOREVER_REL,
                                               fh,
                                               &read_stdout,
                                               as);
}


/**
 * Run the command.  Use the `taler-exchange-system' program.
 *
 * @param cls closure.
 * @param cmd command being run.
 * @param is interpreter state.
 */
static void
system_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct SystemState *as = cls;

  (void) cmd;
  as->is = is;
  as->pipe_in = GNUNET_DISK_pipe (GNUNET_DISK_PF_NONE);
  GNUNET_assert (NULL != as->pipe_in);
  as->pipe_out = GNUNET_DISK_pipe (GNUNET_DISK_PF_NONE);
  GNUNET_assert (NULL != as->pipe_out);
  as->system_proc
    = GNUNET_OS_start_process_vap (
        GNUNET_OS_INHERIT_STD_ERR,
        as->pipe_in, as->pipe_out, NULL,
        "taler-benchmark-setup.sh",
        as->args);
  if (NULL == as->system_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  as->active = true;
  start_reader (as);
  as->cwh = GNUNET_wait_child (as->system_proc,
                               &setup_terminated,
                               as);
}


/**
 * Free the state of a "system" CMD, and possibly kill its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
system_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct SystemState *as = cls;

  (void) cmd;
  if (NULL != as->cwh)
  {
    GNUNET_wait_child_cancel (as->cwh);
    as->cwh = NULL;
  }
  if (NULL != as->reader)
  {
    GNUNET_SCHEDULER_cancel (as->reader);
    as->reader = NULL;
  }
  if (NULL != as->pipe_in)
  {
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_pipe_close (as->pipe_in));
    as->pipe_in = NULL;
  }
  if (NULL != as->pipe_out)
  {
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_pipe_close (as->pipe_out));
    as->pipe_out = NULL;
  }
  if (NULL != as->system_proc)
  {
    if (as->active)
    {
      GNUNET_break (0 ==
                    GNUNET_OS_process_kill (as->system_proc,
                                            SIGTERM));
      GNUNET_OS_process_wait (as->system_proc);
    }
    GNUNET_OS_process_destroy (as->system_proc);
    as->system_proc = NULL;
  }

  for (unsigned int i = 0; NULL != as->args[i]; i++)
    GNUNET_free (as->args[i]);
  GNUNET_free (as->args);
  GNUNET_free (as);
}


/**
 * Offer "system" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
system_traits (void *cls,
               const void **ret,
               const char *trait,
               unsigned int index)
{
  struct SystemState *as = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (&as->system_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_system_start (
  const char *label,
  const char *config_file,
  ...)
{
  struct SystemState *as;
  va_list ap;
  const char *arg;
  unsigned int cnt;

  as = GNUNET_new (struct SystemState);
  cnt = 4; /* 0-2 reserved, +1 for NULL termination */
  va_start (ap,
            config_file);
  while (NULL != (arg = va_arg (ap,
                                const char *)))
  {
    cnt++;
  }
  va_end (ap);
  as->args = GNUNET_new_array (cnt,
                               char *);
  as->args[0] = GNUNET_strdup ("taler-benchmark-setup");
  as->args[1] = GNUNET_strdup ("-c");
  as->args[2] = GNUNET_strdup (config_file);
  cnt = 3;
  va_start (ap,
            config_file);
  while (NULL != (arg = va_arg (ap,
                                const char *)))
  {
    as->args[cnt++] = GNUNET_strdup (arg);
  }
  va_end (ap);

  {
    struct TALER_TESTING_Command cmd = {
      .cls = as,
      .label = label,
      .run = &system_run,
      .cleanup = &system_cleanup,
      .traits = &system_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_system_start.c */
