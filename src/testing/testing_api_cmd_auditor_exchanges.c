/*
  This file is part of TALER
  Copyright (C) 2018-2023 Taler Systems SA

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
 * @file testing/testing_api_cmd_auditor_exchanges.c
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
 * How long do we wait AT MOST when retrying?
 */
#define MAX_BACKOFF GNUNET_TIME_relative_multiply ( \
    GNUNET_TIME_UNIT_MILLISECONDS, 100)


/**
 * How often do we retry before giving up?
 */
#define NUM_RETRIES 5


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
   * How often should we retry on (transient) failures?
   */
  unsigned int do_retry;

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
  TALER_TESTING_touch_cmd (es->is);
  exchanges_run (es,
                 NULL,
                 es->is);
}


/**
 * Callback to analyze the /exchanges response.
 *
 * @param cls closure.
 * @param hr HTTP response details
 * @param num_exchanges length of the @a ei array
 * @param ei array with information about the exchanges
 */
static void
exchanges_cb (void *cls,
              const struct TALER_AUDITOR_ListExchangesResponse *ler)
{
  struct ExchangesState *es = cls;
  const struct TALER_AUDITOR_HttpResponse *hr = &ler->hr;

  es->leh = NULL;
  if (es->expected_response_code != hr->http_status)
  {
    if (0 != es->do_retry)
    {
      es->do_retry--;
      if ( (0 == hr->http_status) ||
           (TALER_EC_GENERIC_DB_SOFT_FAILURE == hr->ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == hr->http_status) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Retrying list exchanges failed with %u/%d\n",
                    hr->http_status,
                    (int) hr->ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_GENERIC_DB_SOFT_FAILURE == hr->ec)
          es->backoff = GNUNET_TIME_UNIT_ZERO;
        else
          es->backoff = GNUNET_TIME_randomized_backoff (es->backoff,
                                                        MAX_BACKOFF);
        TALER_TESTING_inc_tries (es->is);
        es->retry_task = GNUNET_SCHEDULER_add_delayed (es->backoff,
                                                       &do_retry,
                                                       es);
        return;
      }
    }
    TALER_TESTING_unexpected_status (es->is,
                                     hr->http_status);
    return;
  }
  if (MHD_HTTP_OK != hr->http_status)
  {
    TALER_TESTING_interpreter_next (es->is);
    return;
  }
  if (NULL != es->exchange_url)
  {
    bool found = false;
    unsigned int num_exchanges = ler->details.ok.num_exchanges;
    const struct TALER_AUDITOR_ExchangeInfo *ei = ler->details.ok.ei;

    for (unsigned int i = 0;
         i<num_exchanges;
         i++)
      if (0 == strcmp (es->exchange_url,
                       ei[i].exchange_url))
        found = true;
    if (! found)
    {
      TALER_LOG_ERROR ("Exchange '%s' doesn't exist at this auditor\n",
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
  const struct TALER_TESTING_Command *auditor_cmd;
  struct TALER_AUDITOR_Handle *auditor;

  (void) cmd;
  auditor_cmd = TALER_TESTING_interpreter_get_command (is,
                                                       "auditor");
  if (NULL == auditor_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_auditor (auditor_cmd,
                                                  &auditor));

  es->is = is;
  es->leh = TALER_AUDITOR_list_exchanges (auditor,
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
    TALER_TESTING_command_incomplete (es->is,
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
static enum GNUNET_GenericReturnValue
exchanges_traits (void *cls,
                  const void **ret,
                  const char *trait,
                  unsigned int index)
{
  (void) cls;
  (void) ret;
  (void) trait;
  (void) index;
  /* Must define this function because some callbacks
   * look for certain traits on _all_ the commands. */
  return GNUNET_SYSERR;
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_exchanges (const char *label,
                             unsigned int expected_response_code)
{
  struct ExchangesState *es;

  es = GNUNET_new (struct ExchangesState);
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
  es->do_retry = NUM_RETRIES;
  return cmd;
}


/* end of testing_auditor_api_cmd_exchanges.c */
