/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/testing_api_cmd_auditor_exchanges.c
 * @brief command for testing /exchanges of the auditor
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_auditor_service.h"
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "deposit confirmation" CMD.
 */
struct ExchangesState
{

  /**
   * Exchanges handle while operation is running.
   */
  struct TALER_AUDITOR_ListExchangesHandle *leh;

  /**
   * Auditor connection.
   */
  struct TALER_AUDITOR_Handle *auditor;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Task scheduled to try later.
   */
  struct GNUNET_SCHEDULER_Task *retry_task;

  /**
   * How long do we wait until we retry?
   */
  struct GNUNET_TIME_Relative backoff;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * URL of the exchange expected to be included in the response.
   */
  const char *exchange_url;

  /**
   * Should we retry on (transient) failures?
   */
  int do_retry;

};


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
exchanges_run (void *cls,
               const struct TALER_TESTING_Command *cmd,
               struct TALER_TESTING_Interpreter *is);


/**
 * Task scheduled to re-try #exchanges_run.
 *
 * @param cls a `struct ExchangesState`
 */
static void
do_retry (void *cls)
{
  struct ExchangesState *es = cls;

  es->retry_task = NULL;
  exchanges_run (es,
                 NULL,
                 es->is);
}


/**
 * Callback to analyze the /exchanges response.
 *
 * @param cls closure.
 * @param http_status HTTP response code.
 * @param ec taler-specific error code.
 * @param obj raw response from the auditor.
 */
static void
exchanges_cb (void *cls,
              unsigned int http_status,
              enum TALER_ErrorCode ec,
              unsigned int num_exchanges,
              const struct TALER_AUDITOR_ExchangeInfo *ei,
              const json_t *raw_response)
{
  struct ExchangesState *es = cls;

  es->leh = NULL;
  if (es->expected_response_code != http_status)
  {
    if (GNUNET_YES == es->do_retry)
    {
      if ( (0 == http_status) ||
           (TALER_EC_DB_COMMIT_FAILED_ON_RETRY == ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == http_status) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Retrying list exchanges failed with %u/%d\n",
                    http_status,
                    (int) ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_DB_COMMIT_FAILED_ON_RETRY == ec)
          es->backoff = GNUNET_TIME_UNIT_ZERO;
        else
          es->backoff = EXCHANGE_LIB_BACKOFF (es->backoff);
        es->retry_task = GNUNET_SCHEDULER_add_delayed (es->backoff,
                                                       &do_retry,
                                                       es);
        return;
      }
    }
    GNUNET_log
      (GNUNET_ERROR_TYPE_ERROR,
      "Unexpected response code %u to command %s in %s:%u\n",
      http_status,
      es->is->commands[es->is->ip].label,
      __FILE__,
      __LINE__);
    json_dumpf (raw_response, stderr, 0);
    TALER_TESTING_interpreter_fail (es->is);
    return;
  }
  if (NULL != es->exchange_url)
  {
    unsigned int found = GNUNET_NO;

    for (unsigned int i = 0;
         i<num_exchanges;
         i++)
      if (0 == strcmp (es->exchange_url,
                       ei[i].exchange_url))
        found = GNUNET_YES;
    if (GNUNET_NO == found)
    {
      TALER_LOG_ERROR
        ("Exchange '%s' doesn't exist at this auditor\n",
        es->exchange_url);
      TALER_TESTING_interpreter_fail (es->is);
      return;
    }

    TALER_LOG_DEBUG ("Exchange '%s' exists at this auditor!\n",
                     es->exchange_url);
  }
  TALER_TESTING_interpreter_next (es->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
exchanges_run (void *cls,
               const struct TALER_TESTING_Command *cmd,
               struct TALER_TESTING_Interpreter *is)
{
  struct ExchangesState *es = cls;

  es->is = is;
  es->leh = TALER_AUDITOR_list_exchanges
              (is->auditor,
              &exchanges_cb,
              es);

  if (NULL == es->leh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  return;
}


/**
 * Free the state of a "exchanges" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, a `struct ExchangesState`
 * @param cmd the command which is being cleaned up.
 */
static void
exchanges_cleanup (void *cls,
                   const struct TALER_TESTING_Command *cmd)
{
  struct ExchangesState *es = cls;

  if (NULL != es->leh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                es->is->ip,
                cmd->label);
    TALER_AUDITOR_list_exchanges_cancel (es->leh);
    es->leh = NULL;
  }
  if (NULL != es->retry_task)
  {
    GNUNET_SCHEDULER_cancel (es->retry_task);
    es->retry_task = NULL;
  }
  GNUNET_free (es);
}


/**
 * Offer internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret set to the wanted data.
 * @param trait name of the trait.
 * @param index index number of the traits to be returned.
 * @return #GNUNET_OK on success
 */
static int
exchanges_traits (void *cls,
                  const void **ret,
                  const char *trait,
                  unsigned int index)
{
  /* Must define this function because some callbacks
   * look for certain traits on _all_ the commands. */
  return GNUNET_SYSERR;
}


/**
 * Create a "list exchanges" command.
 *
 * @param label command label.
 * @param auditor auditor connection.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exchanges (const char *label,
                             struct TALER_AUDITOR_Handle *auditor,
                             unsigned int expected_response_code)
{
  struct ExchangesState *es;

  es = GNUNET_new (struct ExchangesState);
  es->auditor = auditor;
  es->expected_response_code = expected_response_code;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = es,
      .label = label,
      .run = &exchanges_run,
      .cleanup = &exchanges_cleanup,
      .traits = &exchanges_traits
    };

    return cmd;
  }
}


/**
 * Create a "list exchanges" command and check whether
 * a particular exchange belongs to the returned bundle.
 *
 * @param label command label.
 * @param auditor auditor connection.
 * @param expected_response_code expected HTTP response code.
 * @param exchange_url URL of the exchange supposed to
 *  be included in the response.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exchanges_with_url (const char *label,
                                      unsigned int expected_response_code,
                                      const char *exchange_url)
{
  struct ExchangesState *es;

  es = GNUNET_new (struct ExchangesState);
  es->expected_response_code = expected_response_code;
  es->exchange_url = exchange_url;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = es,
      .label = label,
      .run = &exchanges_run,
      .cleanup = &exchanges_cleanup,
      .traits = &exchanges_traits
    };

    return cmd;
  }
}


/**
 * Modify an exchanges command to enable retries when we get
 * transient errors from the auditor.
 *
 * @param cmd a deposit confirmation command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exchanges_with_retry (struct TALER_TESTING_Command cmd)
{
  struct ExchangesState *es;

  GNUNET_assert (&exchanges_run == cmd.run);
  es = cmd.cls;
  es->do_retry = GNUNET_YES;
  return cmd;
}


/* end of testing_auditor_api_cmd_exchanges.c */
