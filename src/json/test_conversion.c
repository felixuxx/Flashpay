/*
  This file is part of TALER
  (C) 2023 Taler Systems SA

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
 * @file util/test_conversion.c
 * @brief Tests for conversion logic
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"

/**
 * Return value from main().
 */
static int global_ret;

/**
 * Handle to our helper.
 */
static struct TALER_JSON_ExternalConversion *ec;


/**
 * Type of a callback that receives a JSON @a result.
 *
 * @param cls closure
 * @param status_type how did the process die
 * @apram code termination status code from the process
 * @param result some JSON result, NULL if we failed to get an JSON output
 */
static void
conv_cb (void *cls,
         enum GNUNET_OS_ProcessStatusType status_type,
         unsigned long code,
         const json_t *result)
{
  json_t *expect;

  (void) cls;
  (void) status_type;
  ec = NULL;
  global_ret = 3;
  if (42 != code)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected return value from helper: %u\n",
                (unsigned int) code);
    return;
  }
  expect = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("foo",
                             "arg")
    );
  GNUNET_assert (NULL != expect);
  if (1 == json_equal (expect,
                       result))
  {
    global_ret = 0;
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected JSON result\n");
    json_dumpf (result,
                stderr,
                JSON_INDENT (2));
    global_ret = 4;
  }
  json_decref (expect);
}


/**
 * Function called on shutdown/CTRL-C.
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  (void) cls;
  if (NULL != ec)
  {
    GNUNET_break (0);
    global_ret = 2;
    TALER_JSON_external_conversion_stop (ec);
    ec = NULL;
  }
}


/**
 * Main test function.
 *
 * @param cls NULL
 */
static void
run (void *cls)
{
  json_t *input;
  const char *argv[] = {
    "test_conversion.sh",
    "arg",
    NULL
  };

  (void) cls;
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  input = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("key",
                             "foo")
    );
  GNUNET_assert (NULL != input);
  ec = TALER_JSON_external_conversion_start (input,
                                             &conv_cb,
                                             NULL,
                                             "./test_conversion.sh",
                                             argv);
  json_decref (input);
  GNUNET_assert (NULL != ec);
}


int
main (int argc,
      const char *const argv[])
{
  (void) argc;
  (void) argv;
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-conversion",
                    "INFO",
                    NULL);
  GNUNET_OS_init (TALER_project_data_default ());
  global_ret = 1;
  GNUNET_SCHEDULER_run (&run,
                        NULL);
  return global_ret;
}
