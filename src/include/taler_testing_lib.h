/*
  This file is part of TALER
  (C) 2018 Taler Systems SA

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
 * @file include/taler_testing_lib.h
 * @brief API for writing an interpreter to test Taler components
 * @author Christian Grothoff <christian@grothoff.org>
 * @author Marcello Stanisci
 */
#ifndef TALER_TESTING_LIB_H
#define TALER_TESTING_LIB_H

#include "taler_util.h"
#include "taler_exchange_service.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include <microhttpd.h>


/* ********************* Helper functions ********************* */

/**
 * Print failing line number and trigger shutdown.  Useful
 * quite any time after the command "run" method has been called.
 */
#define TALER_TESTING_FAIL(is) \
  do \
  {\
    GNUNET_break (0); \
    TALER_TESTING_interpreter_fail (is); \
    return; \
  } while (0)


#define TALER_TESTING_GET_TRAIT_CREDIT_ACCOUNT(cmd,out) \
  TALER_TESTING_get_trait_uint64 (cmd, 0, out)

#define TALER_TESTING_MAKE_TRAIT_CREDIT_ACCOUNT(data) \
  TALER_TESTING_make_trait_uint64 (0, data)

#define TALER_TESTING_GET_TRAIT_DEBIT_ACCOUNT(cmd,out) \
  TALER_TESTING_get_trait_uint64 (cmd, 1, out)

#define TALER_TESTING_MAKE_TRAIT_DEBIT_ACCOUNT(data) \
  TALER_TESTING_make_trait_uint64 (1, data)

#define TALER_TESTING_GET_TRAIT_ROW_ID(cmd,out) \
  TALER_TESTING_get_trait_uint64 (cmd, 3, out)

#define TALER_TESTING_MAKE_TRAIT_ROW_ID(data) \
  TALER_TESTING_make_trait_uint64 (3, data)

/**
 * Allocate and return a piece of wire-details.  Mostly, it adds
 * the bank_url to the JSON.
 *
 * @param template the wire-details template.
 * @param bank_url the bank_url
 *
 * @return the filled out and stringified wire-details.  To
 *         be manually free'd.
 */
char *
TALER_TESTING_make_wire_details (const char *template,
                                 const char *bank_url);

/**
 * Find denomination key matching the given amount.
 *
 * @param keys array of keys to search
 * @param amount coin value to look for
 * @return NULL if no matching key was found
 */
const struct TALER_EXCHANGE_DenomPublicKey *
TALER_TESTING_find_pk (const struct TALER_EXCHANGE_Keys *keys,
                       const struct TALER_Amount *amount);


/**
 * Prepare launching an exchange.  Checks that the configured
 * port is available, runs taler-exchange-keyup,
 * taler-auditor-sign and taler-exchange-dbinit.  Does not
 * launch the exchange process itself.
 *
 * @param config_filename configuration file to use
 * @return #GNUNET_OK on success, #GNUNET_NO if test should be
 *         skipped, #GNUNET_SYSERR on test failure
 */
int
TALER_TESTING_prepare_exchange (const char *config_filename);


/**
 * Remove files from previous runs
 */
void
TALER_TESTING_cleanup_files (const char *config_name);


/**
 * Test port in URL string for availability.
 */
int
TALER_TESTING_url_port_free (const char *url);


/**
 * Prepare launching a fakebank.  Check that the configuration
 * file has the right option, and that the port is avaiable.
 * If everything is OK, return the configured URL of the fakebank.
 *
 * @param config_filename configuration file to use
 * @return NULL on error, fakebank URL otherwise
 */
char *
TALER_TESTING_prepare_fakebank (const char *config_filename);


/* ******************* Generic interpreter logic ************ */

/**
 * Global state of the interpreter, used by a command
 * to access information about other commands.
 */
struct TALER_TESTING_Interpreter
{

  /**
   * Commands the interpreter will run.
   */
  struct TALER_TESTING_Command *commands;

  /**
   * Interpreter task (if one is scheduled).
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * ID of task called whenever we get a SIGCHILD.
   * Used for #TALER_TESTING_wait_for_sigchld().
   */
  struct GNUNET_SCHEDULER_Task *child_death_task;

  /**
   * Main execution context for the main loop.
   */
  struct GNUNET_CURL_Context *ctx;

  /**
   * Context for running the CURL event loop.
   */
  struct GNUNET_CURL_RescheduleContext *rc;

  /**
   * Handle to our fakebank, if #TALER_TESTING_run_with_fakebank() was used.
   * Otherwise NULL.
   */
  struct TALER_FAKEBANK_Handle *fakebank;

  /**
   * Task run on timeout.
   */
  struct GNUNET_SCHEDULER_Task *timeout_task;

  /**
   * Instruction pointer.  Tells #interpreter_run() which
   * instruction to run next.
   */
  unsigned int ip;

  /**
   * Result of the testcases, #GNUNET_OK on success
   */
  int result;

  /**
   * Handle to the exchange.
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * Handle to exchange process; some commands need it
   * to send signals.  E.g. to trigger the key state reload.
   */
  struct GNUNET_OS_Process *exchanged;

  /**
   * GNUNET_OK if key state should be reloaded.  NOTE: this
   * field can be removed because a new "send signal" command
   * has been introduced.
   */
  int reload_keys;

  /**
   * Is the interpreter running (#GNUNET_YES) or waiting
   * for /keys (#GNUNET_NO)?
   */
  int working;

  /**
   * How often have we gotten a /keys response so far?
   */
  unsigned int key_generation;

  /**
   * Exchange keys from last download.
   */
  const struct TALER_EXCHANGE_Keys *keys;

};




/**
 * A command to be run by the interpreter.
 */
struct TALER_TESTING_Command
{

  /**
   * Closure for all commands with command-specific context
   * information.
   */
  void *cls;

  /**
   * Label for the command.
   */
  const char *label;

  /**
   * Runs the command.  Note that upon return, the interpreter
   * will not automatically run the next command, as the command
   * may continue asynchronously in other scheduler tasks.  Thus,
   * the command must ensure to eventually call
   * #TALER_TESTING_interpreter_next() or
   * #TALER_TESTING_interpreter_fail().
   *
   * @param i interpreter state
   */
  void
  (*run)(void *cls,
         const struct TALER_TESTING_Command *cmd,
         struct TALER_TESTING_Interpreter *i);


  /**
   * Clean up after the command.  Run during forced termination
   * (CTRL-C) or test failure or test success.
   *
   * @param cls closure
   */
  void
  (*cleanup)(void *cls,
             const struct TALER_TESTING_Command *cmd);

  /**
   * Extract information from a command that is useful for other
   * commands.
   *
   * @param cls closure
   * @param ret[out] result (could be anything)
   * @param trait name of the trait
   * @param selector more detailed information about which object
   *                 to return in case there were multiple
   *                 generated by the command
   * @return #GNUNET_OK on success
   */
  int
  (*traits)(void *cls,
            void **ret,
            const char *trait,
            unsigned int index);

};

/**
 * Lookup command by label.
 */
const struct TALER_TESTING_Command *
TALER_TESTING_interpreter_lookup_command
  (struct TALER_TESTING_Interpreter *i,
   const char *label);

/**
 * Obtain main execution context for the main loop.
 */
struct GNUNET_CURL_Context *
TALER_TESTING_interpreter_get_context
  (struct TALER_TESTING_Interpreter *is);

/**
 * Obtain current label.
 */
const char *
TALER_TESTING_interpreter_get_current_label
  (struct TALER_TESTING_Interpreter *is);

/**
 * Obtain main execution context for the main loop.
 */
struct GNUNET_CURL_Context *
TALER_TESTING_interpreter_get_context
  (struct TALER_TESTING_Interpreter *is);


struct TALER_FAKEBANK_Handle *
TALER_TESTING_interpreter_get_fakebank
  (struct TALER_TESTING_Interpreter *is);

/**
 * Current command is done, run the next one.
 */
void
TALER_TESTING_interpreter_next
  (struct TALER_TESTING_Interpreter *is);

/**
 * Current command failed, clean up and fail the test case.
 */
void
TALER_TESTING_interpreter_fail
  (struct TALER_TESTING_Interpreter *is);

/**
 * Create command array terminator.
 *
 * @return a end-command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_end ();


/**
 * Wait until we receive SIGCHLD signal.
 * Then obtain the process trait of the current
 * command, wait on the the zombie and continue
 * with the next command.
 */
void
TALER_TESTING_wait_for_sigchld
  (struct TALER_TESTING_Interpreter *is);


void
TALER_TESTING_run (struct TALER_TESTING_Interpreter *is,
                   struct TALER_TESTING_Command *commands);



void
TALER_TESTING_run_with_fakebank
  (struct TALER_TESTING_Interpreter *is,
   struct TALER_TESTING_Command *commands,
   const char *bank_url);


/**
 * FIXME
 */
typedef void
(*TALER_TESTING_Main)(void *cls,
                      struct TALER_TESTING_Interpreter *is);

/**
 * Install signal handlers plus schedules the main wrapper
 * around the "run" method.
 *
 * @param main_cb the "run" method which coontains all the
 *        commands.
 * @param main_cb_cls a closure for "run", typically NULL.
 * @param config_filename configuration filename.
 * @param exchanged exchange process handle: will be put in the
 *        state as some commands - e.g. revoke - need to send
 *        signal to it, for example to let it know to reload the
 *        key state..
 *
 * @return FIXME: not sure what 'is.result' is at this stage.
 */
int
TALER_TESTING_setup (TALER_TESTING_Main main_cb,
                     void *main_cb_cls,
                     const char *config_filename,
                     struct GNUNET_OS_Process *exchanged);


/**
 * Initialize scheduler loop and curl context for the testcase
 * including starting and stopping the exchange using the given
 * configuration file.
 */
int
TALER_TESTING_setup_with_exchange (TALER_TESTING_Main main_cb,
                                   void *main_cb_cls,
                                   const char *config_file);




/* ************** Specific interpreter commands ************ */

/**
 * Perform a wire transfer (formerly Admin-add-incoming)
 *
 * @return NULL on failure
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer (const char *label,
                                     const char *amount,
                                     const char *bank_url,
                                     uint64_t debit_account_no,
                                     uint64_t credit_account_no,
                                     const char *auth_username,
                                     const char *auth_password,
                                     const char *exchange_url);


/**
 * Create fakebank_transfer command with custom subject.
 *
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer_with_subject
  (const char *label,
   const char *amount,
   const char *bank_url,
   uint64_t debit_account_no,
   uint64_t credit_account_no,
   const char *auth_username,
   const char *auth_password,
   const char *subject,
   const char *exchange_url);


/**
 * Create fakebank_transfer command with custom subject.
 *
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer_with_ref
  (const char *label,
   const char *amount,
   const char *bank_url,
   uint64_t debit_account_no,
   uint64_t credit_account_no,
   const char *auth_username,
   const char *auth_password,
   const char *ref,
   const char *exchange_url);

/**
 * Create fakebank_transfer command with custom subject.
 *
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer_with_instance
  (const char *label,
   const char *amount,
   const char *bank_url,
   uint64_t debit_account_no,
   uint64_t credit_account_no,
   const char *auth_username,
   const char *auth_password,
   const char *instance,
   const char *exchange_url,
   const char *config_filename);

/**
 * Execute taler-exchange-wirewatch process.
 *
 * @param label command label
 * @param config_filanem configuration filename.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_wirewatch (const char *label,
                                  const char *config_filename);

/**
 * Execute taler-exchange-aggregator process.
 *
 * @param label command label
 * @param config_filename configuration filename
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_aggregator (const char *label,
                                   const char *config_filename);

/**
 * Execute taler-exchange-keyup process.
 *
 * @param label command label
 * @param config_filename configuration filename
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_keyup (const char *label,
                              const char *config_filename);

/**
 * Execute taler-auditor-sign process.
 *
 * @param label command label
 * @param config_filename configuration filename
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_auditor_sign (const char *label,
                                     const char *config_filename);


/**
 * Create withdraw command.
 *
 * @return NULL on failure
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount
  (const char *label,
   struct TALER_EXCHANGE_Handle *exchange,
   const char *reserve_reference,
   const char *amount,
   unsigned int expected_response_code);


/**
 * Create withdraw command.
 *
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_denomination
  (const char *label,
   struct TALER_EXCHANGE_Handle *exchange,
   const char *reserve_reference,
   const struct TALER_EXCHANGE_DenomPublicKey *dk,
   unsigned int expected_response_code);


/**
 * Create a /wire command.
 *
 * @param label the command label.
 * @param exchange the exchange to connect to.
 * @param expected_method which wire-transfer method is expected
 *        to be offered by the exchange.
 * @param expected_fee the fee the exchange should charge.
 * @param expected_response_code the HTTP response the exchange
 *        should return.
 *
 * @return the command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wire (const char *label,
                        struct TALER_EXCHANGE_Handle *exchange,
                        const char *expected_method,
                        const char *expected_fee,
                        unsigned int expected_response_code);


/**
 * Create a /reserve/status command.
 *
 * @param label the command label.
 * @param exchange the exchange to connect to.
 * @param reserve_reference reference to the reserve to check.
 * @param expected_balance balance expected to be at the
 * referenced reserve.
 * @param expected_response_code expected HTTP response code.
 *
 * @return the command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_status (const char *label,
                          struct TALER_EXCHANGE_Handle *exchange,
                          const char *reserve_reference,
                          const char *expected_balance,
                          unsigned int expected_response_code);

/**
 * Create a deposit command.
 *
 * @param label command label
 * @param exchange exchange connection
 * @param coin_reference reference to any operation that can
 *        provide a coin
 * @param coin_index if @a withdraw_reference offers an array of
 *        coins, this parameter selects which one in that array
 *        This value is currently ignored, as only one-coin
 *        withdrawals are implemented.
 * @param wire_details bank details of the merchant performing the
 *        deposit
 * @param contract_terms contract terms to be signed over by the
 *        coin
 * @param refund_deadline refund deadline
 * @param amount how much is going to be deposited
 * @param expected_response_code which HTTP status code we expect
 *        in the response
 *
 * @return the deposit command to be run by the interpreter
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit 
  (const char *label,
   struct TALER_EXCHANGE_Handle *exchange,
   const char *coin_reference,
   unsigned int coin_index,
   char *wire_details,
   const char *contract_terms,
   struct GNUNET_TIME_Relative refund_deadline,
   const char *amount,
   unsigned int expected_response_code);


/**
 * Create a "refresh melt" command.
 *
 * @param label command label
 * @param exchange connection to the exchange
 * @param amount Fixme
 * @param coin_reference reference to a command that will provide
 *        a coin to refresh
 * @param expected_response_code expected HTTP code
 */

struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_melt
  (const char *label,
   struct TALER_EXCHANGE_Handle *exchange,
   const char *amount,
   const char *coin_reference,
   unsigned int expected_response_code);


/**
 * Create a "refresh reveal" command.
 *
 * @param label command label
 * @param exchange connection to the exchange
 * @param melt_reference reference to a "refresh melt" command
 * @param expected_response_code expected HTTP response code
 *
 * @return the "refresh reveal" command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_reveal
  (const char *label,
   struct TALER_EXCHANGE_Handle *exchange,
   const char *melt_reference,
   unsigned int expected_response_code);


/**
 * Create a "refresh link" command.
 *
 * @param label command label
 * @param exchange connection to the exchange
 * @param melt_reference reference to a "refresh melt" command
 * @param expected_response_code expected HTTP response code
 *
 * @return the "refresh link" command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_link
  (const char *label,
   struct TALER_EXCHANGE_Handle *exchange,
   const char *reveal_reference,
   unsigned int expected_response_code);


/**
 * Create a /track/transaction command.
 *
 * @param label the command label.
 * @param exchange the exchange to connect to.
 * @param transaction_reference reference to a deposit operation.
 * @param coin_index index of the coin involved in the transaction
 * @param expected_response_code expected HTTP response code.
 * @param bank_transfer_reference which #OC_CHECK_BANK_TRANSFER
 *        wtid should this match? NULL
   * for none
 *
 * @return the command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transaction
  (const char *label,
   struct TALER_EXCHANGE_Handle *exchange,
   const char *transaction_reference,
   unsigned int coin_index,
   unsigned int expected_response_code,
   const char *bank_transfer_reference);

/**
 * Make a /track/transfer command, expecting the transfer
 * not being done (yet).
 *
 * @param label the command label
 * @param exchange connection to the exchange
 * @param wtid_reference reference to any command which can provide
 *        a wtid
 * @param index in case there are multiple wtid offered, this
 *        parameter selects a particular one
 * @param expected_response_code expected HTTP response code
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transfer_empty
  (const char *label,
   struct TALER_EXCHANGE_Handle *exchange,
   const char *wtid_reference,
   unsigned int index,
   unsigned int expected_response_code);


/**
 * Make a /track/transfer command, specifying which amount and
 * wire fee are expected.
 *
 * @param label the command label
 * @param exchange connection to the exchange
 * @param wtid_reference reference to any command which can provide
 *        a wtid
 * @param index in case there are multiple wtid offered, this
 *        parameter selects a particular one
 * @param expected_response_code expected HTTP response code
 * @param expected_amount how much money we expect being
 *        moved with this wire-transfer.
 * @param expected_wire_fee expected wire fee.
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transfer
  (const char *label,
   struct TALER_EXCHANGE_Handle *exchange,
   const char *wtid_reference,
   unsigned int index,
   unsigned int expected_response_code,
   const char *expected_total_amount,
   const char *expected_wire_fee);

/**
 * Command to check whether a particular wire transfer has been
 * made or not.
 *
 * @param label the command label
 * @param exchange_base_url base url of the exchange (Fixme: why?)
 * @param amount the amount expected to be transferred
 * @param debit_account the account that gave money
 * @param credit_account the account that received money
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_transfer
  (const char *label,
   const char *exchange_base_url,
   const char *amount,
   uint64_t debit_account,
   uint64_t credit_account);

/**
 * FIXME.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_transfer_with_ref
  (const char *label,
   const char *deposit_reference);

/**
 * Check bank's balance is zero.
 *
 * @param credit_account the account that received money
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_empty (const char *label);

/**
 * Create a /refund test command.
 *
 * @param label command label
 * @param expected_response_code expected HTTP status code
 * @param refund_amount the amount to ask a refund for
 * @param refund_fee expected refund fee
 * @param coin_reference reference to a command that can
 *        provide a coin to be refunded.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refund (const char *label,
                          unsigned int expected_response_code,
                          const char *refund_amount,
                          const char *refund_fee,
                          const char *deposit_reference);


/**
 * Make a /payback command.
 *
 * @param label the command label
 * @param expected_response_code expected HTTP status code
 * @param coin_reference reference to any command which offers
 *        a reserve private key plus a coin to be paid back.
 * @param amount denomination to pay back.
 *
 * @return a /revoke command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_payback (const char *label,
                           unsigned int expected_response_code,
                           const char *coin_reference,
                           const char *amount);


/**
 * Make a /revoke command.
 *
 * @param label the command label
 * @param expected_response_code expected HTTP status code
 * @param coin_reference reference to any command which offers
 *        a coin trait
 * @param config_filename configuration file name.
 *
 * @return a /revoke command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_revoke (const char *label,
                          unsigned int expected_response_code,
                          const char *coin_reference,
                          const char *config_filename);

/**
 * Send a signal to a process.
 *
 * @param label command label
 * @param process handle to the process
 * @param signal signal to send
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_signal (const char *label,
                          struct GNUNET_OS_Process *process,
                          int signal);

/**
 * Make a "check keys" command.
 *
 * @param label command label
 * @param generation FIXME
 * @param num_denom_keys FIXME
 * @param exchange connection to the exchange
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys
  (const char *label,
   unsigned int generation,
   unsigned int num_denom_keys,
   struct TALER_EXCHANGE_Handle *exchange);

/* *** Generic trait logic for implementing traits ********* */

/**
 * A trait.
 */
struct TALER_TESTING_Trait
{
  unsigned int index;

  const char *trait_name;

  const void *ptr;
};



struct TALER_TESTING_Trait
TALER_TESTING_trait_end (void);


int
TALER_TESTING_get_trait (const struct TALER_TESTING_Trait *traits,
                         void **ret,
                         const char *trait,
                         unsigned int index);


/* ****** Specific traits supported by this component ******* */

struct TALER_TESTING_Trait
TALER_TESTING_make_trait_reserve_priv
  (unsigned int index,
   const struct TALER_ReservePrivateKeyP *reserve_priv);


/**
 * Obtain a reserve private key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on
 * offer
 * @param reserve_priv[out] set to the private key of the reserve
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_reserve_priv
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct TALER_ReservePrivateKeyP **reserve_priv);


/**
 * Obtain location where a command stores a pointer to a process
 *
 * @param cmd command to extract trait from
 * @param selector which process to pick if @a cmd has multiple
 * on offer
 * @param processp[out] set to address of the pointer to the
 * process
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_process
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct GNUNET_OS_Process ***processp);


struct TALER_TESTING_Trait
TALER_TESTING_make_trait_process
  (unsigned int index,
   struct GNUNET_OS_Process **processp);


/**
 * @param selector FIXME
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_coin_priv
  (unsigned int index,
   const struct TALER_CoinSpendPrivateKeyP *coin_priv);

/**
 * Obtain a coin private key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on
 * offer
 * @param coin_priv[out] set to the private key of the coin
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_coin_priv
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct TALER_CoinSpendPrivateKeyP **coin_priv);

/**
 * @param selector a "tag" to associate the object with
 * @param blinding_key which object should be returned
 *
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_blinding_key
  (unsigned int index,
   const struct TALER_DenominationBlindingKeyP *blinding_key);

/**
 * Obtain a coin's blinding key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on
 * offer
 * @param blinding_key[out] set to the blinding key of the coin
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_blinding_key
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct TALER_DenominationBlindingKeyP **blinding_key);

/**
 * @param selector a "tag" to associate the object with
 * @param pdk which object should be returned
 *
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_denom_pub
  (unsigned int index,
   const struct TALER_EXCHANGE_DenomPublicKey *dpk);

/**
 * Obtain a coin private key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on
 *        offer
 * @param dpk[out] set to a denomination key of the coin
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_denom_pub
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct TALER_EXCHANGE_DenomPublicKey **dpk);


/**
 * Obtain a coin denomination signature from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on
 * offer
 * @param sig[out] set to a denomination signature over the coin
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_denom_sig
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct TALER_DenominationSignature **dpk);

/**
 * @param selector
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_denom_sig
  (unsigned int index,
   const struct TALER_DenominationSignature *sig);


/**
 * @param selector associate the object with this "tag"
 * @param i which object should be returned
 *
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_uint64
  (unsigned int index,
   const uint64_t *i);

/**
 * Obtain a "number" value from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on
 * offer
 * @param n[out] set to the number coming from @a cmd.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_uint64
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const uint64_t **n);

/**
 * @param selector associate the object with this "tag"
 * @param i which object should be returned
 *
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_uint
  (unsigned int index,
   const unsigned int *i);

/**
 * Obtain a "number" value from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on
 * offer
 * @param n[out] set to the number coming from @a cmd.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_uint
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   unsigned int **n);

/**
 * Information about a fresh coin generated by the refresh
 * operation. FIXME: should go away from here!
 */
struct FreshCoin
{

  /**
   * If @e amount is NULL, this specifies the denomination key to
   * use.  Otherwise, this will be set (by the interpreter) to the
   * denomination PK matching @e amount.
   */
  const struct TALER_EXCHANGE_DenomPublicKey *pk;

  /**
   * Set (by the interpreter) to the exchange's signature over the
   * coin's public key.
   */
  struct TALER_DenominationSignature sig;

  /**
   * Set (by the interpreter) to the coin's private key.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;
};

/**
 * @param selector associate the object with this "tag"
 * @param fresh_coins array of fresh coins to return
 *
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_fresh_coins
  (unsigned int index,
   struct FreshCoin *fresh_coins);

/**
 * Obtain a "number" value from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on
 * offer
 * @param fresh_coins[out] will point to array of fresh coins
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_fresh_coins
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct FreshCoin **fresh_coins);



/**
 * Obtain contract terms from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index always (?) zero, as one command sticks
 *        to one bank account
 * @param contract_terms[out] where to write the contract
 *        terms.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_contract_terms
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **contract_terms);

/**
 * @param index always (?) zero, as one command sticks
 *        to one bank account
 * @param contract_terms contract terms to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_contract_terms
  (unsigned int index,
   const char *contract_terms);


/**
 * Obtain wire details from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index always (?) zero, as one command sticks
 *        to one bank account
 * @param wire_details[out] where to write the wire details.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_wire_details
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **wire_details);


/**
 * Offer wire details in a trait.
 *
 * @param index always (?) zero, as one command sticks
 *        to one bank account
 * @param wire_details wire details to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_wire_details
  (unsigned int index,
   const char *wire_details);

/**
 * Obtain a private key from a "peer".  Used e.g. to obtain
 * a merchant's priv to sign a /track request.
 *
 * @param index (tipically zero) which key to return if they
 *        exist in an array.
 * @param selector which coin to pick if @a cmd has multiple on
 * offer
 * @param priv[out] set to the key coming from @a cmd.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_peer_key
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct GNUNET_CRYPTO_EddsaPrivateKey **priv);


/**
 * @param index (tipically zero) which key to return if they
 *        exist in an array.
 * @param priv which object should be returned
 *
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_peer_key
  (unsigned int index,
   struct GNUNET_CRYPTO_EddsaPrivateKey *priv);


/**
 * Obtain a public key from a "peer".  Used e.g. to obtain
 * a merchant's public key to use backend's API.
 *
 * @param index (tipically zero) which key to return if they
 *        exist in an array.
 * @param pub[out] set to the key coming from @a cmd.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_peer_key_pub
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct GNUNET_CRYPTO_EddsaPublicKey **pub);

/**
 * @param index (tipically zero) which key to return if they
 *        exist in an array.
 * @param pub which object should be returned
 *
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_peer_key_pub
  (unsigned int index,
   struct GNUNET_CRYPTO_EddsaPublicKey *pub);

/**
 * Obtain a transfer subject from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index always (?) zero, as one command sticks
 *        to one bank transfer
 * @param transfer_subject[out] where to write the wire details.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_transfer_subject
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **transfer_subject);


/**
 * Offer wire details in a trait.
 *
 * @param index always (?) zero, as one command sticks
 *        to one bank account
 * @param wire_details wire details to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_transfer_subject
  (unsigned int index,
   const char *transfer_subject);


/**
 * Obtain a WTID value from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which WTID to pick if @a cmd has multiple on
 *        offer
 * @param wtid[out] set to the wanted WTID.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_wtid
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct TALER_WireTransferIdentifierRawP **wtid);

/**
 * @param index associate the object with this index
 * @param wtid which object should be returned
 *
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_wtid
  (unsigned int index,
   struct TALER_WireTransferIdentifierRawP *wtid);


/**
 * Offer amount in a trait.
 *
 * @param index which amount is to be picked, in case
 *        multiple are offered.
 * @param amount the amount to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_amount
  (unsigned int index,
   const char *amount);

/**
 * Obtain an amount from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which amount is to be picked, in case
 *        multiple are offered.
 * @param amount[out] where to write the wire details.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_amount
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **amount);


/**
 * Offer url in a trait.
 *
 * @param index which url is to be picked, in case
 *        multiple are offered.
 * @param url the url to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_url
  (unsigned int index,
   const char *url);

/**
 * Obtain a url from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which url is to be picked, in case
 *        multiple are offered.
 * @param amount[out] where to write the url.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_url
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **url);


/**
 * Obtain a order id from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which order id is to be picked, in case
 *        multiple are offered.
 * @param order_id[out] where to write the order id.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_order_id
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **order_id);

/**
 * Offer order id in a trait.
 *
 * @param index which order id is to be picked, in case
 *        multiple are offered.
 * @param order_id the url to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_order_id
  (unsigned int index,
   const char *order_id);


/**
 * Obtain an amount from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which amount to pick if @a cmd has multiple
 *        on offer
 * @param amount[out] set to the amount
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_amount_obj (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_Amount **amount);


struct TALER_TESTING_Trait
TALER_TESTING_make_trait_amount_obj (
  unsigned int index,
  const struct TALER_Amount *amount);

/**
 * Offer reference to a bank transfer which has been
 * rejected.
 *
 * @param index which reference is to be picked, in case
 *        multiple are offered.
 * @param rejected_reference the url to offer
 * @return the trait, to be put in the traits array of the command
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_rejected
  (unsigned int index,
   const char *rejected);

/**
 * Obtain the reference from a bank transfer which has
 * been rejected.
 *
 * @param cmd command to extract trait from
 * @param index which reference is to be picked, in case
 *        multiple are offered.
 * @param rejected_reference[out] where to write the order id.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_rejected
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **rejected_reference);

#endif
