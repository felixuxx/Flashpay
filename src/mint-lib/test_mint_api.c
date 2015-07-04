/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_mint_service.h"

/**
 * Main execution context for the main loop.
 */
static struct TALER_MINT_Context *ctx;

/**
 * Handle to access the mint.
 */
static struct TALER_MINT_Handle *mint;

/**
 * Task run on shutdown.
 */
static struct GNUNET_SCHEDULER_Task *shutdown_task;

/**
 * Task that runs the main event loop.
 */
static struct GNUNET_SCHEDULER_Task *ctx_task;

/**
 * Result of the testcases, #GNUNET_OK on success
 */
static int result;


/**
 * Opcodes for the interpreter.
 */
enum OpCode
{
  /**
   * Termination code, stops the interpreter loop (with success).
   */
  OC_END = 0,

  /**
   * Add funds to a reserve by (faking) incoming wire transfer.
   */
  OC_ADMIN_ADD_INCOMING,

  /**
   * Withdraw a coin from a reserve.
   */
  OC_WITHDRAW_SIGN,

  /**
   * Deposit a coin (pay with it).
   */
  OC_DEPOSIT

};


/**
 * Details for a mint operation to execute.
 */
struct Command
{
  /**
   * Opcode of the command.
   */
  enum OpCode oc;

  /**
   * Label for the command, can be NULL.
   */
  const char *label;

  /**
   * Details about the command.
   */
  union
  {

    struct
    {

      /**
       * Label to another admin_add_incoming command if we
       * should deposit into an existing reserve, NULL if
       * a fresh reserve should be created.
       */
      const char *reserve_reference;

      /**
       * String describing the amount to add to the reserve.
       */
      const char *amount;

      /**
       * Set (by the interpreter) to the reserve's private key
       * we used to fill the reserve.
       */
      struct TALER_ReservePrivateKeyP reserve_priv;

    } admin_add_incoming;

    struct
    {
      /**
       * Which reserve should we withdraw from?
       */
      const char *reserve_reference;

      /**
       * String describing the denomination value we should withdraw.
       * A corresponding denomination key must exist in the mint's
       * offerings.  Can be NULL if @e pk is set instead.
       */
      const char *amount;

      /**
       * If @e amount is NULL, this specifies the denomination key to
       * use.  Otherwise, this will be set (by the interpreter) to the
       * denomination PK matching @e amount.
       */
      const struct TALER_MINT_DenomPublicKey *pk;

      /**
       * Set (by the interpreter) to the mint's signature over the
       * coin's public key.
       */
      struct TALER_DenominationSignature sig;

      /**
       * Set (by the interpreter) to the coin's private key.
       */
      struct TALER_CoinSpendPrivateKeyP coin_priv;

    } withdraw_sign;

    struct
    {

      /**
       * Amount to deposit.
       */
      const char *amount;

      /**
       * Reference to a withdraw_sign operation for a coin to
       * be used for the /deposit operation.
       */
      const char *coin_ref;

      /**
       * JSON string describing the merchant's "wire details".
       */
      const char *wire_details;

      /**
       * JSON string describing the contract between the two parties.
       */
      const char *contract;

      /**
       * Transaction ID to use.
       */
      uint64_t transaction_id;

      /**
       * Relative time (to add to 'now') to compute the refund deadline.
       * Zero for no refunds.
       */
      struct GNUNET_TIME_Relative refund_deadline;

      /**
       * Set (by the interpreter) to a fresh private key of the merchant,
       * if @e refund_deadline is non-zero.
       */
      struct TALER_MerchantPublicKeyP merchant_priv;

    } deposit;

  } details;

};


/**
 * State of the interpreter loop.
 */
struct InterpreterState
{
  /**
   * Keys from the mint.
   */
  const struct TALER_MINT_Keys *keys;

  /**
   * Commands the interpreter will run.
   */
  struct Command *commands;

  /**
   * Instruction pointer.  Tells #interpreter_run() which
   * instruction to run next.
   */
  unsigned int ip;

};


/**
 * The testcase failed, return with an error code.
 *
 * @param is interpreter state to clean up
 */
static void
fail (struct InterpreterState *is)
{
  result = GNUNET_SYSERR;
  GNUNET_free (is);
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Run the main interpreter loop that performs mint operations.
 *
 * @param cls contains the `struct InterpreterState`
 * @param tc scheduler context
 */
static void
interpreter_run (void *cls,
                 const struct GNUNET_SCHEDULER_TaskContext *tc)
{
  struct InterpreterState *is = cls;
  struct Command *cmd = &is->commands[is->ip++];

  if (0 != (tc->reason & GNUNET_SCHEDULER_REASON_SHUTDOWN))
  {
    fprintf (stderr,
             "Test aborted by shutdown request\n");
    fail (is);
    return;
  }
  switch (cmd->oc)
  {
  case OC_END:
    result = GNUNET_OK;
    GNUNET_free (is);
    GNUNET_SCHEDULER_shutdown ();
    return;
  case OC_ADMIN_ADD_INCOMING:
    GNUNET_break (0); // to be implemented!
    break;
  case OC_WITHDRAW_SIGN:
    GNUNET_break (0); // to be implemented!
    break;
  case OC_DEPOSIT:
    GNUNET_break (0); // to be implemented!
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unknown instruction %d at %u (%s)\n",
                cmd->oc,
                is->ip - 1,
                cmd->label);
    fail (is);
    return;
  }
  GNUNET_SCHEDULER_add_now (&interpreter_run,
                            is);
}


/**
 * Function run when the test terminates (good or bad).
 * Cleans up our state.
 *
 * @param cls NULL
 * @param tc unused
 */
static void
do_shutdown (void *cls,
             const struct GNUNET_SCHEDULER_TaskContext *tc)
{
  shutdown_task = NULL;
  if (NULL != ctx_task)
  {
    GNUNET_SCHEDULER_cancel (ctx_task);
    ctx_task = NULL;
  }
  if (NULL != mint)
  {
    TALER_MINT_disconnect (mint);
    mint = NULL;
  }
  if (NULL != ctx)
  {
    TALER_MINT_fini (ctx);
    ctx = NULL;
  }
}


/**
 * Functions of this type are called to provide the retrieved signing and
 * denomination keys of the mint.  No TALER_MINT_*() functions should be called
 * in this callback.
 *
 * @param cls closure
 * @param keys information about keys of the mint
 */
static void
cert_cb (void *cls,
         const struct TALER_MINT_Keys *keys)
{
  struct InterpreterState *is;
  static struct Command commands[] =
  {
    { .oc = OC_ADMIN_ADD_INCOMING,
      .label = "create-reserve-1",
      .details.admin_add_incoming.amount = "EUR:5" },
    { .oc = OC_WITHDRAW_SIGN,
      .label = "withdraw-coin-1",
      .details.withdraw_sign.reserve_reference = "create-reserve-1",
      .details.withdraw_sign.amount = "EUR:5" },
    { .oc = OC_DEPOSIT,
      .label = "deposit-simple",
      .details.deposit.amount = "EUR:5",
      .details.deposit.coin_ref = "withdraw-coin-1",
      .details.deposit.wire_details = "{ bank=\"my bank\", account=\"42\" }",
      .details.deposit.contract = "{ items={ name=\"ice cream\", value=1 } }",
      .details.deposit.transaction_id = 1 },
    { .oc = OC_END }
  };

  GNUNET_assert (NULL == cls);
#define ERR(cond) do { if(!(cond)) break; GNUNET_break (0); GNUNET_SCHEDULER_shutdown(); return; } while (0)
  ERR (NULL == keys);
  ERR (0 == keys->num_sign_keys);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Read %u signing keys\n",
              keys->num_sign_keys);
  ERR (0 == keys->num_denom_keys);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Read %u denomination keys\n",
              keys->num_denom_keys);
#undef ERR
  /* TODO: start running rest of test suite here! */

  is = GNUNET_new (struct InterpreterState);
  is->keys = keys;
  is->commands = commands;
  GNUNET_SCHEDULER_add_now (&interpreter_run,
                            is);
}


/**
 * Task that runs the context's event loop with the GNUnet scheduler.
 *
 * @param cls unused
 * @param tc scheduler context (unused)
 */
static void
context_task (void *cls,
              const struct GNUNET_SCHEDULER_TaskContext *tc)
{
  long timeout;
  int max_fd;
  fd_set read_fd_set;
  fd_set write_fd_set;
  fd_set except_fd_set;
  struct GNUNET_NETWORK_FDSet *rs;
  struct GNUNET_NETWORK_FDSet *ws;
  struct GNUNET_TIME_Relative delay;

  ctx_task = NULL;
  TALER_MINT_perform (ctx);
  max_fd = -1;
  timeout = -1;
  FD_ZERO (&read_fd_set);
  FD_ZERO (&write_fd_set);
  FD_ZERO (&except_fd_set);
  TALER_MINT_get_select_info (ctx,
                              &read_fd_set,
                              &write_fd_set,
                              &except_fd_set,
                              &max_fd,
                              &timeout);
  if (timeout >= 0)
    delay = GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS,
                                           timeout);
  else
    delay = GNUNET_TIME_UNIT_FOREVER_REL;
  rs = GNUNET_NETWORK_fdset_create ();
  GNUNET_NETWORK_fdset_copy_native (rs,
                                    &read_fd_set,
                                    max_fd);
  ws = GNUNET_NETWORK_fdset_create ();
  GNUNET_NETWORK_fdset_copy_native (ws,
                                    &write_fd_set,
                                    max_fd + 1);
  ctx_task = GNUNET_SCHEDULER_add_select (GNUNET_SCHEDULER_PRIORITY_DEFAULT,
                                          delay,
                                          rs,
                                          ws,
                                          &context_task,
                                          cls);
  GNUNET_NETWORK_fdset_destroy (rs);
  GNUNET_NETWORK_fdset_destroy (ws);
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
run (void *cls,
     const struct GNUNET_SCHEDULER_TaskContext *tc)
{
  ctx = TALER_MINT_init ();
  GNUNET_assert (NULL != ctx);
  ctx_task = GNUNET_SCHEDULER_add_now (&context_task,
                                       ctx);
  mint = TALER_MINT_connect (ctx,
                             "http://localhost:8081",
                             &cert_cb, NULL,
                             TALER_MINT_OPTION_END);
  GNUNET_assert (NULL != mint);
  shutdown_task =
      GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_relative_multiply
                                    (GNUNET_TIME_UNIT_SECONDS, 5),
                                    &do_shutdown, NULL);
}


/**
 * Main function for the testcase for the mint API.
 *
 * @param argc expected to be 1
 * @param argv expected to only contain the program name
 */
int
main (int argc,
      char * const *argv)
{
  struct GNUNET_OS_Process *proc;
  struct GNUNET_OS_Process *mintd;

  GNUNET_log_setup ("test-mint-api",
                    "WARNING",
                    NULL);
  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-mint-keyup",
                                  "taler-mint-keyup",
                                  "-d", "test-mint-home",
                                  "-m", "test-mint-home/master.priv",
                                  NULL);
  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);
  mintd = GNUNET_OS_start_process (GNUNET_NO,
                                   GNUNET_OS_INHERIT_STD_ALL,
                                   NULL, NULL, NULL,
                                   "taler-mint-httpd",
                                   "taler-mint-httpd",
                                   "-d", "test-mint-home",
                                   NULL);
  /* give child time to start and bind against the socket */
  sleep (1);
  result = GNUNET_SYSERR;
  GNUNET_SCHEDULER_run (&run, NULL);
  GNUNET_OS_process_kill (mintd,
                          SIGTERM);
  GNUNET_OS_process_wait (mintd);
  GNUNET_OS_process_destroy (mintd);
  return (GNUNET_OK == result) ? 0 : 1;
}

/* end of test_mint_api.c */
