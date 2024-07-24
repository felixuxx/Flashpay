/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file conversion.c
 * @brief helper routines to run some external JSON-to-JSON converter
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_util_lib.h>


struct TALER_JSON_ExternalConversion
{
  /**
   * Callback to call with the result.
   */
  TALER_JSON_JsonCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Handle to the helper process.
   */
  struct GNUNET_OS_Process *helper;

  /**
   * Pipe for the stdin of the @e helper.
   */
  struct GNUNET_DISK_FileHandle *chld_stdin;

  /**
   * Pipe for the stdout of the @e helper.
   */
  struct GNUNET_DISK_FileHandle *chld_stdout;

  /**
   * Handle to wait on the child to terminate.
   */
  struct GNUNET_ChildWaitHandle *cwh;

  /**
   * Task to read JSON output from the child.
   */
  struct GNUNET_SCHEDULER_Task *read_task;

  /**
   * Task to send JSON input to the child.
   */
  struct GNUNET_SCHEDULER_Task *write_task;

  /**
   * Buffer with data we need to send to the helper.
   */
  void *write_buf;

  /**
   * Buffer for reading data from the helper.
   */
  void *read_buf;

  /**
   * Total length of @e write_buf.
   */
  size_t write_size;

  /**
   * Current write position in @e write_buf.
   */
  size_t write_pos;

  /**
   * Current size of @a read_buf.
   */
  size_t read_size;

  /**
   * Current offset in @a read_buf.
   */
  size_t read_pos;

};


/**
 * Function called when we can read more data from
 * the child process.
 *
 * @param cls our `struct TALER_JSON_ExternalConversion *`
 */
static void
read_cb (void *cls)
{
  struct TALER_JSON_ExternalConversion *ec = cls;

  ec->read_task = NULL;
  while (1)
  {
    ssize_t ret;

    if (ec->read_size == ec->read_pos)
    {
      /* Grow input buffer */
      size_t ns;
      void *tmp;

      ns = GNUNET_MAX (2 * ec->read_size,
                       1024);
      if (ns > GNUNET_MAX_MALLOC_CHECKED)
        ns = GNUNET_MAX_MALLOC_CHECKED;
      if (ec->read_size == ns)
      {
        /* Helper returned more than 40 MB of data! Stop reading! */
        GNUNET_break (0);
        GNUNET_break (GNUNET_OK ==
                      GNUNET_DISK_file_close (ec->chld_stdin));
        return;
      }
      tmp = GNUNET_malloc_large (ns);
      if (NULL == tmp)
      {
        /* out of memory, also stop reading */
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                             "malloc");
        GNUNET_break (GNUNET_OK ==
                      GNUNET_DISK_file_close (ec->chld_stdin));
        return;
      }
      GNUNET_memcpy (tmp,
                     ec->read_buf,
                     ec->read_pos);
      GNUNET_free (ec->read_buf);
      ec->read_buf = tmp;
      ec->read_size = ns;
    }
    ret = GNUNET_DISK_file_read (ec->chld_stdout,
                                 ec->read_buf + ec->read_pos,
                                 ec->read_size - ec->read_pos);
    if (ret < 0)
    {
      if ( (EAGAIN != errno) &&
           (EWOULDBLOCK != errno) &&
           (EINTR != errno) )
      {
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                             "read");
        return;
      }
      break;
    }
    if (0 == ret)
    {
      /* regular end of stream, good! */
      return;
    }
    GNUNET_assert (ec->read_size >= ec->read_pos + ret);
    ec->read_pos += ret;
  }
  ec->read_task
    = GNUNET_SCHEDULER_add_read_file (
        GNUNET_TIME_UNIT_FOREVER_REL,
        ec->chld_stdout,
        &read_cb,
        ec);
}


/**
 * Function called when we can write more data to
 * the child process.
 *
 * @param cls our `struct TALER_JSON_ExternalConversion *`
 */
static void
write_cb (void *cls)
{
  struct TALER_JSON_ExternalConversion *ec = cls;
  ssize_t ret;

  ec->write_task = NULL;
  while (ec->write_size > ec->write_pos)
  {
    ret = GNUNET_DISK_file_write (ec->chld_stdin,
                                  ec->write_buf + ec->write_pos,
                                  ec->write_size - ec->write_pos);
    if (ret < 0)
    {
      if ( (EAGAIN != errno) &&
           (EINTR != errno) )
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                             "write");
      break;
    }
    if (0 == ret)
    {
      GNUNET_break (0);
      break;
    }
    GNUNET_assert (ec->write_size >= ec->write_pos + ret);
    ec->write_pos += ret;
  }
  if ( (ec->write_size > ec->write_pos) &&
       ( (EAGAIN == errno) ||
         (EWOULDBLOCK == errno) ||
         (EINTR == errno) ) )
  {
    ec->write_task
      = GNUNET_SCHEDULER_add_write_file (
          GNUNET_TIME_UNIT_FOREVER_REL,
          ec->chld_stdin,
          &write_cb,
          ec);
  }
  else
  {
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_file_close (ec->chld_stdin));
    ec->chld_stdin = NULL;
  }
}


/**
 * Defines a GNUNET_ChildCompletedCallback which is sent back
 * upon death or completion of a child process.
 *
 * @param cls handle for the callback
 * @param type type of the process
 * @param exit_code status code of the process
 *
 */
static void
child_done_cb (void *cls,
               enum GNUNET_OS_ProcessStatusType type,
               long unsigned int exit_code)
{
  struct TALER_JSON_ExternalConversion *ec = cls;
  json_t *j = NULL;
  json_error_t err;

  ec->cwh = NULL;
  if (NULL != ec->read_task)
  {
    GNUNET_SCHEDULER_cancel (ec->read_task);
    /* We could get the process termination notification before having drained
       the read buffer. So drain it now, just in case. */
    read_cb (ec);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Conversion helper exited with status %d and code %llu after outputting %llu bytes of data\n",
              (int) type,
              (unsigned long long) exit_code,
              (unsigned long long) ec->read_pos);
  GNUNET_OS_process_destroy (ec->helper);
  ec->helper = NULL;
  if (0 != ec->read_pos)
  {
    j = json_loadb (ec->read_buf,
                    ec->read_pos,
                    JSON_REJECT_DUPLICATES,
                    &err);
    if (NULL == j)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to parse JSON from helper at %d: %s\n",
                  err.position,
                  err.text);
    }
  }
  ec->cb (ec->cb_cls,
          type,
          exit_code,
          j);
  json_decref (j);
  TALER_JSON_external_conversion_stop (ec);
}


struct TALER_JSON_ExternalConversion *
TALER_JSON_external_conversion_start (const json_t *input,
                                      TALER_JSON_JsonCallback cb,
                                      void *cb_cls,
                                      const char *binary,
                                      ...)
{
  struct TALER_JSON_ExternalConversion *ec;
  struct GNUNET_DISK_PipeHandle *pipe_stdin;
  struct GNUNET_DISK_PipeHandle *pipe_stdout;
  va_list ap;

  ec = GNUNET_new (struct TALER_JSON_ExternalConversion);
  ec->cb = cb;
  ec->cb_cls = cb_cls;
  pipe_stdin = GNUNET_DISK_pipe (GNUNET_DISK_PF_BLOCKING_READ);
  GNUNET_assert (NULL != pipe_stdin);
  pipe_stdout = GNUNET_DISK_pipe (GNUNET_DISK_PF_BLOCKING_WRITE);
  GNUNET_assert (NULL != pipe_stdout);
  va_start (ap,
            binary);
  ec->helper = GNUNET_OS_start_process_va (GNUNET_OS_INHERIT_STD_ERR,
                                           pipe_stdin,
                                           pipe_stdout,
                                           NULL,
                                           binary,
                                           ap);
  va_end (ap);
  if (NULL == ec->helper)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to run conversion helper `%s'\n",
                binary);
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_pipe_close (pipe_stdin));
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_pipe_close (pipe_stdout));
    GNUNET_free (ec);
    return NULL;
  }
  ec->chld_stdin =
    GNUNET_DISK_pipe_detach_end (pipe_stdin,
                                 GNUNET_DISK_PIPE_END_WRITE);
  ec->chld_stdout =
    GNUNET_DISK_pipe_detach_end (pipe_stdout,
                                 GNUNET_DISK_PIPE_END_READ);
  GNUNET_break (GNUNET_OK ==
                GNUNET_DISK_pipe_close (pipe_stdin));
  GNUNET_break (GNUNET_OK ==
                GNUNET_DISK_pipe_close (pipe_stdout));
  ec->write_buf = json_dumps (input, JSON_COMPACT);
  ec->write_size = strlen (ec->write_buf);
  ec->read_task
    = GNUNET_SCHEDULER_add_read_file (GNUNET_TIME_UNIT_FOREVER_REL,
                                      ec->chld_stdout,
                                      &read_cb,
                                      ec);
  ec->write_task
    = GNUNET_SCHEDULER_add_write_file (GNUNET_TIME_UNIT_FOREVER_REL,
                                       ec->chld_stdin,
                                       &write_cb,
                                       ec);
  ec->cwh = GNUNET_wait_child (ec->helper,
                               &child_done_cb,
                               ec);
  return ec;
}


void
TALER_JSON_external_conversion_stop (
  struct TALER_JSON_ExternalConversion *ec)
{
  if (NULL != ec->cwh)
  {
    GNUNET_wait_child_cancel (ec->cwh);
    ec->cwh = NULL;
  }
  if (NULL != ec->helper)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (ec->helper,
                                          SIGKILL));
    GNUNET_OS_process_destroy (ec->helper);
  }
  if (NULL != ec->read_task)
  {
    GNUNET_SCHEDULER_cancel (ec->read_task);
    ec->read_task = NULL;
  }
  if (NULL != ec->write_task)
  {
    GNUNET_SCHEDULER_cancel (ec->write_task);
    ec->write_task = NULL;
  }
  if (NULL != ec->chld_stdin)
  {
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_file_close (ec->chld_stdin));
    ec->chld_stdin = NULL;
  }
  if (NULL != ec->chld_stdout)
  {
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_file_close (ec->chld_stdout));
    ec->chld_stdout = NULL;
  }
  GNUNET_free (ec->read_buf);
  free (ec->write_buf);
  GNUNET_free (ec);
}
