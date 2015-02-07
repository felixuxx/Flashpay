/*
  This file is part of TALER
  Copyright (C) 2014 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file mint/test_mint_api.c
 * @brief testcase to test mint's HTTP API interface
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */

#include "platform.h"
#include "taler_util.h"
#include "taler_mint_service.h"

struct TALER_MINT_Context *ctx;

struct TALER_MINT_Handle *mint;

struct TALER_MINT_KeysGetHandle *dkey_get;

struct TALER_MINT_DepositHandle *dh;

static struct GNUNET_SCHEDULER_Task *shutdown_task;

static int result;


static void
do_shutdown (void *cls, const struct GNUNET_SCHEDULER_TaskContext *tc)
{
  shutdown_task = NULL;
  if (NULL != dkey_get)
    TALER_MINT_keys_get_cancel (dkey_get);
  dkey_get = NULL;
  if (NULL != dh)
    TALER_MINT_deposit_submit_cancel (dh);
  dh = NULL;
  TALER_MINT_disconnect (mint);
  mint = NULL;
  TALER_MINT_cleanup (ctx);
  ctx = NULL;
}


/**
 * Callbacks of this type are used to serve the result of submitting a deposit
 * permission object to a mint
 *
 * @param cls closure
 * @param status 1 for successful deposit, 2 for retry, 0 for failure
 * @param obj the received JSON object; can be NULL if it cannot be constructed
 *        from the reply
 * @param emsg in case of unsuccessful deposit, this contains a human readable
 *        explanation.
 */
static void
deposit_status (void *cls,
                int status,
                json_t *obj,
                char *emsg)
{
  char *json_enc;

  dh = NULL;
  json_enc = NULL;
  if (NULL != obj)
  {
    json_enc = json_dumps (obj, JSON_INDENT(2));
    fprintf (stderr, "%s", json_enc);
  }
  if (1 == status)
    result = GNUNET_OK;
  else
    GNUNET_break (0);
  if (NULL != emsg)
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Deposit failed: %s\n", emsg);
  GNUNET_SCHEDULER_shutdown ();
}
/**
 * Functions of this type are called to signal completion of an asynchronous call.
 *
 * @param cls closure
 * @param emsg if the asynchronous call could not be completed due to an error,
 *        this parameter contains a human readable error message
 */
static void
cont (void *cls, const char *emsg)
{
  json_t *dp;
  char rnd_32[32];
  char rnd_64[64];
  char *enc_32;
  char *enc_64;

  GNUNET_assert (NULL == cls);
  dkey_get = NULL;
  if (NULL != emsg)
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "%s\n", emsg);

  enc_32 = GNUNET_STRINGS_data_to_string_alloc (rnd_32, sizeof (rnd_32));
  enc_64 = GNUNET_STRINGS_data_to_string_alloc (rnd_64, sizeof (rnd_64));
  dp = json_pack ("{s:s s:o s:s s:s s:s s:s s:s s:s s:s s:s}",
                  "type", "DIRECT_DEPOSIT",
                  "wire", json_pack ("{s:s}", "type", "SEPA"),
                  "C", enc_32,
                  "K", enc_32,
                  "ubsig", enc_64,
                  "M", enc_32,
                  "H_a", enc_64,
                  "H_wire", enc_64,
                  "csig", enc_64,
                  "m", "B1C5GP2RB1C5G");
  GNUNET_free (enc_32);
  GNUNET_free (enc_64);
  dh = TALER_MINT_deposit_submit_json (mint,
                                       deposit_status,
                                       NULL,
                                       dp);
  json_decref (dp);
}


/**
 * Functions of this type are called to provide the retrieved signing and
 * denomination keys of the mint.  No TALER_MINT_*() functions should be called
 * in this callback.
 *
 * @param cls closure passed to TALER_MINT_keys_get()
 * @param sign_keys NULL-terminated array of pointers to the mint's signing
 *          keys.  NULL if no signing keys are retrieved.
 * @param denom_keys NULL-terminated array of pointers to the mint's
 *          denomination keys; will be NULL if no signing keys are retrieved.
 */
static void
read_denom_key (void *cls,
                struct TALER_MINT_SigningPublicKey **sign_keys,
                struct TALER_MINT_DenomPublicKey **denom_keys)
{
  unsigned int cnt;
  GNUNET_assert (NULL == cls);
#define ERR(cond) do { if(!(cond)) break; GNUNET_break (0); return; } while (0)
  ERR (NULL == sign_keys);
  ERR (NULL == denom_keys);
  for (cnt = 0; NULL != sign_keys[cnt]; cnt++)
    GNUNET_free (sign_keys[cnt]);
  ERR (0 == cnt);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG, "Read %u signing keys\n", cnt);
  GNUNET_free (sign_keys);
  for (cnt = 0; NULL != denom_keys[cnt]; cnt++)
    GNUNET_free (denom_keys[cnt]);
  ERR (0 == cnt);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG, "Read %u denomination keys\n", cnt);
  GNUNET_free (denom_keys);
#undef ERR
  return;
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param config configuration
 */
static void
run (void *cls, char *const *args, const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *config)
{
  ctx = TALER_MINT_init ();
  mint = TALER_MINT_connect (ctx, "localhost", 4241, NULL);
  GNUNET_assert (NULL != mint);
  dkey_get = TALER_MINT_keys_get (mint,
                                  &read_denom_key, NULL,
                                  &cont, NULL);
  GNUNET_assert (NULL != dkey_get);
  shutdown_task =
      GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_relative_multiply
                                    (GNUNET_TIME_UNIT_SECONDS, 5),
                                    &do_shutdown, NULL);
}

int
main (int argc, char * const *argv)
{
  static struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_END
  };

  result = GNUNET_SYSERR;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv, "test-mint-api",
                          gettext_noop
                          ("Testcase to test mint's HTTP API interface"),
                          options, &run, NULL))
    return 3;
  return (GNUNET_OK == result) ? 0 : 1;
}
