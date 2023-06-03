/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_nexus_fetch_transactions.c
 * @brief run a nft command
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "nft" CMD.
 */
struct NftState
{
  /**
   * Process for the nfter.
   */
  struct GNUNET_OS_Process *nft_proc;

  const char *username;
  const char *password;
  const char *bank_base_url;
  const char *account_id;
};


/**
 * Run the command; use the `nft' program.
 *
 * @param cls closure.
 * @param cmd command currently being executed.
 * @param is interpreter state.
 */
static void
nft_run (void *cls,
         const struct TALER_TESTING_Command *cmd,
         struct TALER_TESTING_Interpreter *is)
{
  struct NftState *ws = cls;
  char *url;
  char *user;
  char *pass;

  (void) cmd;
  GNUNET_asprintf (&url,
                   "%s/bank-accounts/%s/fetch-transactions",
                   ws->bank_base_url,
                   ws->account_id);
  GNUNET_asprintf (&user,
                   "--user=%s",
                   ws->username);
  GNUNET_asprintf (&pass,
                   "--password=%s",
                   ws->password);
  ws->nft_proc
    = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                               NULL, NULL, NULL,
                               "wget",
                               "wget",
                               "--header=Content-Type:application/json",
                               "--auth-no-challenge",
                               "--output-file=/dev/null",
                               "--output-document=/dev/null",
                               "--post-data={\"level\":\"all\",\"rangeType\":\"latest\"}",
                               user,
                               pass,
                               url,
                               NULL);
  GNUNET_free (url);
  GNUNET_free (user);
  GNUNET_free (pass);
  if (NULL == ws->nft_proc)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_wait_for_sigchld (is);
}


/**
 * Free the state of a "nft" CMD, and possibly
 * kills its process if it did not terminate regularly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
nft_cleanup (void *cls,
             const struct TALER_TESTING_Command *cmd)
{
  struct NftState *ws = cls;

  (void) cmd;
  if (NULL != ws->nft_proc)
  {
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (ws->nft_proc,
                                          SIGKILL));
    GNUNET_OS_process_wait (ws->nft_proc);
    GNUNET_OS_process_destroy (ws->nft_proc);
    ws->nft_proc = NULL;
  }
  GNUNET_free (ws);
}


/**
 * Offer "nft" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
nft_traits (void *cls,
            const void **ret,
            const char *trait,
            unsigned int index)
{
  struct NftState *ws = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_process (&ws->nft_proc),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_nexus_fetch_transactions (
  const char *label,
  const char *username,
  const char *password,
  const char *bank_base_url,
  const char *account_id)
{
  struct NftState *ws;

  ws = GNUNET_new (struct NftState);
  ws->username = username;
  ws->password = password;
  ws->bank_base_url = bank_base_url;
  ws->account_id = account_id;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &nft_run,
      .cleanup = &nft_cleanup,
      .traits = &nft_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_nexus_fetch_transactions.c */
