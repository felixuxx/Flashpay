/*
  This file is part of TALER
  (C) 2018-2023 Taler Systems SA

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
#include <microhttpd.h>
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include "taler_auditor_service.h"
#include "taler_bank_service.h"
#include "taler_exchange_service.h"
#include "taler_fakebank_lib.h"


/* ********************* Helper functions ********************* */

/**
 * Print failing line number and trigger shutdown.  Useful
 * quite any time after the command "run" method has been called.
 */
#define TALER_TESTING_FAIL(is) \
  do \
  { \
    GNUNET_break (0); \
    TALER_TESTING_interpreter_fail (is); \
    return; \
  } while (0)


/**
 * Log an error message about us receiving an unexpected HTTP
 * status code at the current command and fail the test.
 *
 * @param is interpreter to fail
 * @param status unexpected HTTP status code received
 * @param expected expected HTTP status code
 */
#define TALER_TESTING_unexpected_status(is,status,expected)             \
  do {                                                                  \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,                                \
                "Unexpected response code %u (expected: %u) to command %s in %s:%u\n", \
                status,                                                 \
                expected,                                               \
                TALER_TESTING_interpreter_get_current_label (is),       \
                __FILE__,                                               \
                __LINE__);                                              \
    TALER_TESTING_interpreter_fail (is);                                \
  } while (0)

/**
 * Log an error message about us receiving an unexpected HTTP
 * status code at the current command and fail the test and print the response
 * body (expected as json).
 *
 * @param is interpreter to fail
 * @param status unexpected HTTP status code received
 * @param expected expected HTTP status code
 * @param body received JSON-reply
 */
#define TALER_TESTING_unexpected_status_with_body(is,status,expected,body) \
  do {                                                                  \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,                                \
                "Unexpected response code %u (expected: %u) to "        \
                "command %s in %s:%u\nwith body:\n>>%s<<\n",            \
                status,                                                 \
                expected,                                               \
                TALER_TESTING_interpreter_get_current_label (is),       \
                __FILE__,                                               \
                __LINE__,                                               \
                json_dumps (body, JSON_INDENT (2)));                    \
    TALER_TESTING_interpreter_fail (is);                                \
  } while (0)


/**
 * Log an error message about a command not having
 * run to completion.
 *
 * @param is interpreter
 * @param label command label of the incomplete command
 */
#define TALER_TESTING_command_incomplete(is,label)                      \
  do {                                                                  \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,                                \
                "Command %s (%s:%u) did not complete (at %s)\n",        \
                label,                                                  \
                __FILE__,                                               \
                __LINE__,                                               \
                TALER_TESTING_interpreter_get_current_label (is));      \
  } while (0)


/**
 * Common credentials used in a test.
 */
struct TALER_TESTING_Credentials
{
  /**
   * Bank authentication details for the exchange bank
   * account.
   */
  struct TALER_BANK_AuthenticationData ba;

  /**
   * Configuration file data.
   */
  struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Base URL of the exchange.
   */
  char *exchange_url;

  /**
   * Base URL of the auditor.
   */
  char *auditor_url;

  /**
   * RFC 8905 URI of the exchange.
   */
  char *exchange_payto;

  /**
   * RFC 8905 URI of a user.
   */
  char *user42_payto;

  /**
   * RFC 8905 URI of a user.
   */
  char *user43_payto;
};


/**
 * What type of bank are we using?
 */
enum TALER_TESTING_BankSystem
{
  TALER_TESTING_BS_FAKEBANK = 1,
  TALER_TESTING_BS_IBAN = 2
};


/**
 * Obtain bank credentials for a given @a cfg_file using
 * @a exchange_account_section as the basis for the
 * exchange account.
 *
 * @param cfg_file name of configuration to parse
 * @param exchange_account_section configuration section name for the exchange account to use
 * @param bs type of bank to use
 * @param[out] ua where to write user account details
 *         and other credentials
 */
enum GNUNET_GenericReturnValue
TALER_TESTING_get_credentials (
  const char *cfg_file,
  const char *exchange_account_section,
  enum TALER_TESTING_BankSystem bs,
  struct TALER_TESTING_Credentials *ua);


/**
 * Allocate and return a piece of wire-details.  Combines
 * a @a payto -URL and adds some salt to create the JSON.
 *
 * @param payto payto://-URL to encapsulate
 * @return JSON describing the account, including the
 *         payto://-URL of the account, must be manually decref'd
 */
json_t *
TALER_TESTING_make_wire_details (const char *payto);


/**
 * Remove files from previous runs
 *
 * @param cls NULL
 * @param cfg configuration
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_TESTING_cleanup_files_cfg (void *cls,
                                 const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Find denomination key matching the given amount.
 *
 * @param keys array of keys to search
 * @param amount coin value to look for
 * @param age_restricted must the denomination be age restricted?
 * @return NULL if no matching key was found
 */
const struct TALER_EXCHANGE_DenomPublicKey *
TALER_TESTING_find_pk (const struct TALER_EXCHANGE_Keys *keys,
                       const struct TALER_Amount *amount,
                       bool age_restricted);


/**
 * Test port in URL string for availability.
 *
 * @param url URL to extract port from, 80 is default
 * @return #GNUNET_OK if the port is free
 */
enum GNUNET_GenericReturnValue
TALER_TESTING_url_port_free (const char *url);


/* ******************* Generic interpreter logic ************ */

/**
 * Global state of the interpreter, used by a command
 * to access information about other commands.
 */
struct TALER_TESTING_Interpreter;


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
   * Variable name for the command, NULL for none.
   */
  const char *name;

  /**
   * Runs the command.  Note that upon return, the interpreter
   * will not automatically run the next command, as the command
   * may continue asynchronously in other scheduler tasks.  Thus,
   * the command must ensure to eventually call
   * #TALER_TESTING_interpreter_next() or
   * #TALER_TESTING_interpreter_fail().
   *
   * @param cls closure
   * @param cmd command being run
   * @param is interpreter state
   */
  void
  (*run)(void *cls,
         const struct TALER_TESTING_Command *cmd,
         struct TALER_TESTING_Interpreter *is);


  /**
   * Clean up after the command.  Run during forced termination
   * (CTRL-C) or test failure or test success.
   *
   * @param cls closure
   * @param cmd command being cleaned up
   */
  void
  (*cleanup)(void *cls,
             const struct TALER_TESTING_Command *cmd);

  /**
   * Extract information from a command that is useful for other
   * commands.
   *
   * @param cls closure
   * @param[out] ret result (could be anything)
   * @param trait name of the trait
   * @param index index number of the object to extract.
   * @return #GNUNET_OK on success
   */
  enum GNUNET_GenericReturnValue
  (*traits)(void *cls,
            const void **ret,
            const char *trait,
            unsigned int index);

  /**
   * When did the execution of this command start?
   */
  struct GNUNET_TIME_Absolute start_time;

  /**
   * When did the execution of this command finish?
   */
  struct GNUNET_TIME_Absolute finish_time;

  /**
   * When did we start the last request of this command?
   * Delta to @e finish_time gives the latency for the last
   * successful request.
   */
  struct GNUNET_TIME_Absolute last_req_time;

  /**
   * How often did we try to execute this command? (In case
   * it is a request that is repated.)
   */
  unsigned int num_tries;

};


/**
 * Lookup command by label.
 *
 * @param is interpreter state.
 * @param label label of the command to lookup.
 * @return the command, if it is found, or NULL.
 */
const struct TALER_TESTING_Command *
TALER_TESTING_interpreter_lookup_command (struct TALER_TESTING_Interpreter *is,
                                          const char *label);


/**
 * Get command from hash map by variable name.
 *
 * @param is interpreter state.
 * @param name name of the variable to get command by
 * @return the command, if it is found, or NULL.
 */
const struct TALER_TESTING_Command *
TALER_TESTING_interpreter_get_command (struct TALER_TESTING_Interpreter *is,
                                       const char *name);


/**
 * Update the last request time of the current command
 * to the current time.
 *
 * @param[in,out] is interpreter state where to show
 *       that we are doing something
 */
void
TALER_TESTING_touch_cmd (struct TALER_TESTING_Interpreter *is);


/**
 * Increment the 'num_tries' counter for the current
 * command.
 *
 * @param[in,out] is interpreter state where to
 *   increment the counter
 */
void
TALER_TESTING_inc_tries (struct TALER_TESTING_Interpreter *is);


/**
 * Obtain CURL context for the main loop.
 *
 * @param is interpreter state.
 * @return CURL execution context.
 */
struct GNUNET_CURL_Context *
TALER_TESTING_interpreter_get_context (struct TALER_TESTING_Interpreter *is);


/**
 * Obtain label of the command being now run.
 *
 * @param is interpreter state.
 * @return the label.
 */
const char *
TALER_TESTING_interpreter_get_current_label (
  struct TALER_TESTING_Interpreter *is);


/**
 * Current command is done, run the next one.
 *
 * @param is interpreter state.
 */
void
TALER_TESTING_interpreter_next (struct TALER_TESTING_Interpreter *is);

/**
 * Current command failed, clean up and fail the test case.
 *
 * @param is interpreter state.
 */
void
TALER_TESTING_interpreter_fail (struct TALER_TESTING_Interpreter *is);


/**
 * Make the instruction pointer point to @a target_label
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
                             unsigned int counter);


/**
 * Wait until we receive SIGCHLD signal.
 * Then obtain the process trait of the current
 * command, wait on the the zombie and continue
 * with the next command.
 *
 * @param is interpreter state.
 */
void
TALER_TESTING_wait_for_sigchld (struct TALER_TESTING_Interpreter *is);


/**
 * Schedule the first CMD in the CMDs array.
 *
 * @param is interpreter state.
 * @param commands array of all the commands to execute.
 */
void
TALER_TESTING_run (struct TALER_TESTING_Interpreter *is,
                   struct TALER_TESTING_Command *commands);


/**
 * Run the testsuite.  Note, CMDs are copied into
 * the interpreter state because they are _usually_
 * defined into the "run" method that returns after
 * having scheduled the test interpreter.
 *
 * @param is the interpreter state
 * @param commands the list of command to execute
 * @param timeout how long to wait
 */
void
TALER_TESTING_run2 (struct TALER_TESTING_Interpreter *is,
                    struct TALER_TESTING_Command *commands,
                    struct GNUNET_TIME_Relative timeout);


/**
 * The function that contains the array of all the CMDs to run,
 * which is then on charge to call some fashion of
 * TALER_TESTING_run*.  In all the test cases, this function is
 * always the GNUnet-ish "run" method.
 *
 * @param cls closure.
 * @param is interpreter state.
 */
typedef void
(*TALER_TESTING_Main)(void *cls,
                      struct TALER_TESTING_Interpreter *is);


/**
 * Run Taler testing loop.  Starts the GNUnet SCHEDULER (event loop).
 *
 * @param main_cb main function to run
 * @param main_cb_cls closure for @a main_cb
 */
enum GNUNET_GenericReturnValue
TALER_TESTING_loop (TALER_TESTING_Main main_cb,
                    void *main_cb_cls);


/**
 * Convenience function to run a test.
 *
 * @param argv command-line arguments given
 * @param loglevel log level to use
 * @param cfg_file configuration file to use
 * @param exchange_account_section configuration section
 *   with exchange bank account to use
 * @param bs bank system to use
 * @param[in,out] cred global credentials to initialize
 * @param main_cb main test function to run
 * @param main_cb_cls closure for @a main_cb
 * @return 0 on success, 77 on setup trouble, non-zero process status code otherwise
 */
int
TALER_TESTING_main (char *const *argv,
                    const char *loglevel,
                    const char *cfg_file,
                    const char *exchange_account_section,
                    enum TALER_TESTING_BankSystem bs,
                    struct TALER_TESTING_Credentials *cred,
                    TALER_TESTING_Main main_cb,
                    void *main_cb_cls);


/**
 * Callback over commands of an interpreter.
 *
 * @param cls closure
 * @param cmd a command to process
 */
typedef void
(*TALER_TESTING_CommandIterator)(
  void *cls,
  const struct TALER_TESTING_Command *cmd);


/**
 * Iterates over all of the top-level commands of an
 * interpreter.
 *
 * @param[in] is interpreter to iterate over
 * @param asc true in execution order, false for reverse execution order
 * @param cb function to call on each command
 * @param cb_cls closure for cb
 */
void
TALER_TESTING_iterate (struct TALER_TESTING_Interpreter *is,
                       bool asc,
                       TALER_TESTING_CommandIterator cb,
                       void *cb_cls);


/**
 * Look for substring in a programs' name.
 *
 * @param prog program's name to look into
 * @param marker chunk to find in @a prog
 * @return true if @a marker is in @a prog
 */
bool
TALER_TESTING_has_in_name (const char *prog,
                           const char *marker);


/**
 * Wait for an HTTPD service to have started. Waits for at
 * most 10s, after that returns 77 to indicate an error.
 *
 * @param base_url what URL should we expect the exchange
 *        to be running at
 * @return 0 on success
 */
int
TALER_TESTING_wait_httpd_ready (const char *base_url);


/**
 * Parse reference to a coin.
 *
 * @param coin_reference of format $LABEL['#' $INDEX]?
 * @param[out] cref where we return a copy of $LABEL
 * @param[out] idx where we set $INDEX
 * @return #GNUNET_SYSERR if $INDEX is present but not numeric
 */
enum GNUNET_GenericReturnValue
TALER_TESTING_parse_coin_reference (
  const char *coin_reference,
  char **cref,
  unsigned int *idx);


/**
 * Compare @a h1 and @a h2.
 *
 * @param h1 a history entry
 * @param h2 a history entry
 * @return 0 if @a h1 and @a h2 are equal
 */
int
TALER_TESTING_history_entry_cmp (
  const struct TALER_EXCHANGE_ReserveHistoryEntry *h1,
  const struct TALER_EXCHANGE_ReserveHistoryEntry *h2);


/* ************** Specific interpreter commands ************ */


/**
 * Create command array terminator.
 *
 * @return a end-command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_end (void);


/**
 * Set variable to command as side-effect of
 * running a command.
 *
 * @param name name of the variable to set
 * @param cmd command to set to variable when run
 * @return modified command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_set_var (const char *name,
                           struct TALER_TESTING_Command cmd);


/**
 * Launch GNU Taler setup.
 *
 * @param label command label.
 * @param config_file configuration file to use
 * @param ... NULL-terminated (const char *) arguments to pass to taler-benchmark-setup.sh
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_system_start (
  const char *label,
  const char *config_file,
  ...);


/**
 * Connects to the exchange.
 *
 * @param label command label
 * @param cfg configuration to use
 * @param last_keys_ref reference to command with prior /keys response, NULL for none
 * @param wait_for_keys block until we got /keys
 * @param load_private_key obtain private key from file indicated in @a cfg
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_get_exchange (
  const char *label,
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  const char *last_keys_ref,
  bool wait_for_keys,
  bool load_private_key);


/**
 * Connects to the auditor.
 *
 * @param label command label
 * @param cfg configuration to use
 * @param load_auditor_keys obtain auditor keys from file indicated in @a cfg
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_get_auditor (
  const char *label,
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  bool load_auditor_keys);


/**
 * Runs the Fakebank in-process by guessing / extracting the portnumber
 * from the base URL.
 *
 * @param label command label
 * @param cfg configuration to use
 * @param exchange_account_section configuration section
 *   to use to determine bank account of the exchange
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_run_fakebank (
  const char *label,
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  const char *exchange_account_section);


/**
 * Command to modify authorization header used in the CURL context.
 * This will destroy the existing CURL context and create a fresh
 * one. The command will fail (badly) if the existing CURL context
 * still has active HTTP requests associated with it.
 *
 * @param label command label.
 * @param auth_token auth token to use henceforth, can be NULL
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_set_authorization (const char *label,
                                     const char *auth_token);


/**
 * Make a credit "history" CMD.
 *
 * @param label command label.
 * @param auth login data to use
 * @param start_row_reference reference to a command that can
 *        offer a row identifier, to be used as the starting row
 *        to accept in the result.
 * @param num_results how many rows we want in the result,
 *        and ascending/descending call
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_credits (
  const char *label,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *start_row_reference,
  long long num_results);


/**
 * Make a debit "history" CMD.
 *
 * @param label command label.
 * @param auth authentication data
 * @param start_row_reference reference to a command that can
 *        offer a row identifier, to be used as the starting row
 *        to accept in the result.
 * @param num_results how many rows we want in the result.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_debits (const char *label,
                               const struct TALER_BANK_AuthenticationData *auth,
                               const char *start_row_reference,
                               long long num_results);


/**
 * Create transfer command.
 *
 * @param label command label
 * @param amount amount to transfer
 * @param auth authentication data to use
 * @param payto_debit_account which account to withdraw money from
 * @param payto_credit_account which account receives money
 * @param wtid wire transfer identifier to use
 * @param exchange_base_url exchange URL to use
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_transfer (const char *label,
                            const char *amount,
                            const struct TALER_BANK_AuthenticationData *auth,
                            const char *payto_debit_account,
                            const char *payto_credit_account,
                            const struct TALER_WireTransferIdentifierRawP *wtid,
                            const char *exchange_base_url);


/**
 * Modify a transfer command to enable retries when the reserve is not yet
 * full or we get other transient errors from the bank.
 *
 * @param cmd a fakebank transfer command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_transfer_retry (struct TALER_TESTING_Command cmd);


/**
 * Make the "exec-auditor" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_auditor (const char *label,
                                const char *config_filename);


/**
 * Make the "exec-auditor-dbinit" CMD. Always run with the "-r" option.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_auditor_dbinit (const char *label,
                                       const char *config_filename);


/**
 * Create a "deposit-confirmation" command.
 *
 * @param label command label.
 * @param deposit_reference reference to any operation that can
 *        provide a coin.
 * @param num_coins number of coins expected in the batch deposit
 * @param amount_without_fee deposited amount without the fee
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_confirmation (
  const char *label,
  const char *deposit_reference,
  unsigned int num_coins,
  const char *amount_without_fee,
  unsigned int expected_response_code);


/**
 * Modify a deposit confirmation command to enable retries when we get
 * transient errors from the auditor.
 *
 * @param cmd a deposit confirmation command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_confirmation_with_retry (
  struct TALER_TESTING_Command cmd);


/**
 * Create a "list exchanges" command.
 *
 * @param label command label.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exchanges (const char *label,
                             unsigned int expected_response_code);


/**
 * Create a "list exchanges" command and check whether
 * a particular exchange belongs to the returned bundle.
 *
 * @param label command label.
 * @param expected_response_code expected HTTP response code.
 * @param exchange_url URL of the exchange supposed to
 *  be included in the response.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exchanges_with_url (const char *label,
                                      unsigned int expected_response_code,
                                      const char *exchange_url);

/**
 * Modify an exchanges command to enable retries when we get
 * transient errors from the auditor.
 *
 * @param cmd a deposit confirmation command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exchanges_with_retry (struct TALER_TESTING_Command cmd);


/**
 * Create /admin/add-incoming command.
 *
 * @param label command label.
 * @param amount amount to transfer.
 * @param payto_debit_account which account sends money.
 * @param auth authentication data
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming (
  const char *label,
  const char *amount,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *payto_debit_account);


/**
 * Create "fakebank transfer" CMD, letting the caller specify
 * a reference to a command that can offer a reserve private key.
 * This private key will then be used to construct the subject line
 * of the wire transfer.
 *
 * @param label command label.
 * @param amount the amount to transfer.
 * @param payto_debit_account which account sends money.
 * @param auth authentication data
 * @param ref reference to a command that can offer a reserve
 *        private key or public key.
 * @param http_status expected HTTP status
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming_with_ref (
  const char *label,
  const char *amount,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *payto_debit_account,
  const char *ref,
  unsigned int http_status);


/**
 * Modify a fakebank transfer command to enable retries when the
 * reserve is not yet full or we get other transient errors from
 * the fakebank.
 *
 * @param cmd a fakebank transfer command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming_retry (struct TALER_TESTING_Command cmd);


/**
 * Make a "wirewatch" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_wirewatch (const char *label,
                                  const char *config_filename);


/**
 * Make a "wirewatch" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @param account_section section to run wirewatch against
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_wirewatch2 (const char *label,
                                   const char *config_filename,
                                   const char *account_section);


/**
 * Request URL via "wget".
 *
 * @param label command label.
 * @param url URL to fetch
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_wget (const char *label,
                             const char *url);


/**
 * Request fetch-transactions via "wget".
 *
 * @param label command label.
 * @param username username to use
 * @param password password to use
 * @param bank_base_url base URL of the nexus
 * @param account_id account to fetch transactions for
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_nexus_fetch_transactions (const char *label,
                                            const char *username,
                                            const char *password,
                                            const char *bank_base_url,
                                            const char *account_id);


/**
 * Make a "expire" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_expire (const char *label,
                               const char *config_filename);


/**
 * Make a "router" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_router (const char *label,
                               const char *config_filename);


/**
 * Run a "taler-exchange-aggregator" CMD.
 *
 * @param label command label.
 * @param config_filename configuration file for the
 *                        aggregator to use.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_aggregator (const char *label,
                                   const char *config_filename);


/**
 * Run a "taler-auditor-offline" CMD.
 *
 * @param label command label.
 * @param config_filename configuration file for the
 *                        aggregator to use.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_auditor_offline (const char *label,
                                        const char *config_filename);


/**
 * Make a "aggregator" CMD and do not disable KYC checks.
 *
 * @param label command label.
 * @param config_filename configuration file for the
 *                        aggregator to use.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_aggregator_with_kyc (const char *label,
                                            const char *config_filename);


/**
 * Make a "closer" CMD.  Note that it is right now not supported to run the
 * closer to close multiple reserves in combination with a subsequent reserve
 * status call, as we cannot generate the traits necessary for multiple closed
 * reserves.  You can work around this by using multiple closer commands, one
 * per reserve that is being closed.
 *
 * @param label command label.
 * @param config_filename configuration file for the
 *                        closer to use.
 * @param expected_amount amount we expect to see wired from a @a expected_reserve_ref
 * @param expected_fee closing fee we expect to see
 * @param expected_reserve_ref reference to a reserve we expect the closer to drain;
 *          NULL if we do not expect the closer to do anything
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_closer (const char *label,
                               const char *config_filename,
                               const char *expected_amount,
                               const char *expected_fee,
                               const char *expected_reserve_ref);


/**
 * Make a "transfer" CMD.
 *
 * @param label command label.
 * @param config_filename configuration file for the
 *                        transfer to use.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_transfer (const char *label,
                                 const char *config_filename);


/**
 * Create a withdraw command, letting the caller specify
 * the desired amount as string.
 *
 * @param label command label.
 * @param reserve_reference command providing us with a reserve to withdraw from
 * @param amount how much we withdraw.
 * @param age if > 0, age restriction applies
 * @param expected_response_code which HTTP response code
 *        we expect from the exchange.
 * @return the withdraw command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount (const char *label,
                                   const char *reserve_reference,
                                   const char *amount,
                                   uint8_t age,
                                   unsigned int expected_response_code);


/**
 * Create a batch withdraw command, letting the caller specify
 * the desired amounts as string.  Takes a variable, non-empty
 * list of the denomination amounts via VARARGS, similar to
 * #TALER_TESTING_cmd_withdraw_amount(), just using a batch withdraw.
 *
 * @param label command label.
 * @param reserve_reference command providing us with a reserve to withdraw from
 * @param age if > 0, age restriction applies (same for all coins)
 * @param expected_response_code which HTTP response code
 *        we expect from the exchange.
 * @param amount how much we withdraw for the first coin
 * @param ... NULL-terminated list of additional amounts to withdraw (one per coin)
 * @return the withdraw command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_batch_withdraw (const char *label,
                                  const char *reserve_reference,
                                  uint8_t age,
                                  unsigned int expected_response_code,
                                  const char *amount,
                                  ...);

/**
 * Create an age-withdraw command, letting the caller specify
 * the maximum agend and desired amounts as string.  Takes a variable,
 * non-empty list of the denomination amounts via VARARGS, similar to
 * #TALER_TESTING_cmd_withdraw_amount(), just using a batch withdraw.
 *
 * @param label command label.
 * @param reserve_reference command providing us with a reserve to withdraw from
 * @param max_age maximum allowed age, same for each coin
 * @param expected_response_code which HTTP response code
 *        we expect from the exchange.
 * @param amount how much we withdraw for the first coin
 * @param ... NULL-terminated list of additional amounts to withdraw (one per coin)
 * @return the withdraw command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_age_withdraw (const char *label,
                                const char *reserve_reference,
                                uint8_t max_age,
                                unsigned int expected_response_code,
                                const char *amount,
                                ...);

/**
 * Create a "age-withdraw reveal" command.
 *
 * @param label command label.
 * @param age_withdraw_reference reference to a "age-withdraw" command.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_age_withdraw_reveal (
  const char *label,
  const char *age_withdraw_reference,
  unsigned int expected_response_code);

/**
 * Create a withdraw command, letting the caller specify
 * the desired amount as string and also re-using an existing
 * coin private key in the process (violating the specification,
 * which will result in an error when spending the coin!).
 *
 * @param label command label.
 * @param reserve_reference command providing us with a reserve to withdraw from
 * @param amount how much we withdraw.
 * @param age if > 0, age restriction applies.
 * @param coin_ref reference to (withdraw/reveal) command of a coin
 *        from which we should re-use the private key
 * @param expected_response_code which HTTP response code
 *        we expect from the exchange.
 * @return the withdraw command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount_reuse_key (
  const char *label,
  const char *reserve_reference,
  const char *amount,
  uint8_t age,
  const char *coin_ref,
  unsigned int expected_response_code);


/**
 * Create withdraw command, letting the caller specify the
 * amount by a denomination key.
 *
 * @param label command label.
 * @param reserve_reference reference to the reserve to withdraw
 *        from; will provide reserve priv to sign the request.
 * @param dk denomination public key.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_denomination (
  const char *label,
  const char *reserve_reference,
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  unsigned int expected_response_code);


/**
 * Modify a withdraw command to enable retries when the
 * reserve is not yet full or we get other transient
 * errors from the exchange.
 *
 * @param cmd a withdraw command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_with_retry (struct TALER_TESTING_Command cmd);


/**
 * Create a GET "reserves" command.
 *
 * @param label the command label.
 * @param reserve_reference reference to the reserve to check.
 * @param expected_balance expected balance for the reserve.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_status (const char *label,
                          const char *reserve_reference,
                          const char *expected_balance,
                          unsigned int expected_response_code);


/**
 * Create a GET "reserves" command with a @a timeout.
 *
 * @param label the command label.
 * @param reserve_reference reference to the reserve to check.
 * @param expected_balance expected balance for the reserve.
 * @param timeout how long to long-poll for the reserve to exist.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_poll (const char *label,
                                const char *reserve_reference,
                                const char *expected_balance,
                                struct GNUNET_TIME_Relative timeout,
                                unsigned int expected_response_code);


/**
 * Wait for #TALER_TESTING_cmd_reserve_poll() to finish.
 * Fail if it did not conclude by the timeout.
 *
 * @param label our label
 * @param timeout how long to give the long poll to finish
 * @param poll_reference reference to a #TALER_TESTING_cmd_reserve_poll() command
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_poll_finish (const char *label,
                                       struct GNUNET_TIME_Relative timeout,
                                       const char *poll_reference);


/**
 * Create a GET "/reserves/$RID/history" command.
 *
 * @param label the command label.
 * @param reserve_reference reference to the reserve to check.
 * @param expected_balance expected balance for the reserve.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_history (const char *label,
                                   const char *reserve_reference,
                                   const char *expected_balance,
                                   unsigned int expected_response_code);


/**
 * Create a GET "/coins/$COIN_PUB/history" command.
 *
 * @param label the command label.
 * @param coin_reference reference to the coin to check.
 * @param expected_balance expected balance for the coin.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_coin_history (const char *label,
                                const char *coin_reference,
                                const char *expected_balance,
                                unsigned int expected_response_code);


/**
 * Create a POST "/reserves/$RID/open" command.
 *
 * @param label the command label.
 * @param reserve_reference reference to the reserve to open.
 * @param reserve_pay amount to pay from the reserve balance
 * @param expiration_time how long into the future should the reserve remain open
 * @param min_purses minimum number of purses to allow
 * @param expected_response_code expected HTTP response code.
 * @param ... NULL terminated list of pairs of coin references and amounts
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_open (const char *label,
                                const char *reserve_reference,
                                const char *reserve_pay,
                                struct GNUNET_TIME_Relative expiration_time,
                                uint32_t min_purses,
                                unsigned int expected_response_code,
                                ...);


/**
 * Create a GET "/reserves/$RID/attest" command.
 *
 * @param label the command label.
 * @param reserve_reference reference to the reserve to get attestable attributes of.
 * @param expected_response_code expected HTTP response code.
 * @param ... NULL-terminated list of attributes expected
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_get_attestable (const char *label,
                                          const char *reserve_reference,
                                          unsigned int expected_response_code,
                                          ...);


/**
 * Create a POST "/reserves/$RID/attest" command.
 *
 * @param label the command label.
 * @param reserve_reference reference to the reserve to get attests for
 * @param expected_response_code expected HTTP response code.
 * @param ... NULL-terminated list of attributes that should be attested
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_attest (const char *label,
                                  const char *reserve_reference,
                                  unsigned int expected_response_code,
                                  ...);


/**
 * Create a POST "/reserves/$RID/close" command.
 *
 * @param label the command label.
 * @param reserve_reference reference to the reserve to close.
 * @param target_account where to wire funds remaining, can be NULL
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_close (const char *label,
                                 const char *reserve_reference,
                                 const char *target_account,
                                 unsigned int expected_response_code);


/**
 * Create a "deposit" command.
 *
 * @param label command label.
 * @param coin_reference reference to any operation that can
 *        provide a coin.
 * @param coin_index if @a withdraw_reference offers an array of
 *        coins, this parameter selects which one in that array.
 *        This value is currently ignored, as only one-coin
 *        withdrawals are implemented.
 * @param target_account_payto target account for the "deposit"
 *        request.
 * @param contract_terms contract terms to be signed over by the
 *        coin.
 * @param refund_deadline refund deadline, zero means 'no refunds'.
 * @param amount how much is going to be deposited.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit (const char *label,
                           const char *coin_reference,
                           unsigned int coin_index,
                           const char *target_account_payto,
                           const char *contract_terms,
                           struct GNUNET_TIME_Relative refund_deadline,
                           const char *amount,
                           unsigned int expected_response_code);

/**
 * Create a "deposit" command that references an existing merchant key.
 *
 * @param label command label.
 * @param coin_reference reference to any operation that can
 *        provide a coin.
 * @param coin_index if @a withdraw_reference offers an array of
 *        coins, this parameter selects which one in that array.
 *        This value is currently ignored, as only one-coin
 *        withdrawals are implemented.
 * @param target_account_payto target account for the "deposit"
 *        request.
 * @param contract_terms contract terms to be signed over by the
 *        coin.
 * @param refund_deadline refund deadline, zero means 'no refunds'.
 *        Note, if time were absolute, then it would have come
 *        one day and disrupt tests meaning.
 * @param amount how much is going to be deposited.
 * @param expected_response_code expected HTTP response code.
 * @param merchant_priv_reference reference to another operation
 *        that has a merchant private key trait
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_with_ref (const char *label,
                                    const char *coin_reference,
                                    unsigned int coin_index,
                                    const char *target_account_payto,
                                    const char *contract_terms,
                                    struct GNUNET_TIME_Relative refund_deadline,
                                    const char *amount,
                                    unsigned int expected_response_code,
                                    const char *merchant_priv_reference);

/**
 * Modify a deposit command to enable retries when we get transient
 * errors from the exchange.
 *
 * @param cmd a deposit command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_with_retry (struct TALER_TESTING_Command cmd);


/**
 * Create a "deposit" command that repeats an existing
 * deposit command.
 *
 * @param label command label.
 * @param deposit_reference which deposit command should we repeat
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_replay (const char *label,
                                  const char *deposit_reference,
                                  unsigned int expected_response_code);


/**
 * Create a "batch deposit" command.
 *
 * @param label command label.
 * @param target_account_payto target account for the "deposit"
 *        request.
 * @param contract_terms contract terms to be signed over by the
 *        coin.
 * @param refund_deadline refund deadline, zero means 'no refunds'.
 * @param expected_response_code expected HTTP response code.
 * @param ... NULL-terminated list with an even number of
 *            strings that alternate referring to coins
 *            (possibly with index using label#index notation)
 *            and the amount of that coin to deposit
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_batch_deposit (const char *label,
                                 const char *target_account_payto,
                                 const char *contract_terms,
                                 struct GNUNET_TIME_Relative refund_deadline,
                                 unsigned int expected_response_code,
                                 ...);


/**
 * Create a "refresh melt" command.
 *
 * @param label command label.
 * @param coin_reference reference to a command
 *        that will provide a coin to refresh.
 * @param expected_response_code expected HTTP code.
 * @param ... NULL-terminated list of amounts to be melted
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_melt (const char *label,
                        const char *coin_reference,
                        unsigned int expected_response_code,
                        ...);


/**
 * Create a "refresh melt" CMD that does TWO /refresh/melt
 * requests.  This was needed to test the replay of a valid melt
 * request, see #5312.
 *
 * @param label command label
 * @param coin_reference reference to a command that will provide
 *        a coin to refresh
 * @param expected_response_code expected HTTP code
 * @param ... NULL-terminated list of amounts to be melted
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_melt_double (const char *label,
                               const char *coin_reference,
                               unsigned int expected_response_code,
                               ...);


/**
 * Modify a "refresh melt" command to enable retries.
 *
 * @param cmd command
 * @return modified command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_melt_with_retry (struct TALER_TESTING_Command cmd);


/**
 * Create a "refresh reveal" command.
 *
 * @param label command label.
 * @param melt_reference reference to a "refresh melt" command.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_reveal (const char *label,
                                  const char *melt_reference,
                                  unsigned int expected_response_code);


/**
 * Modify a "refresh reveal" command to enable retries.
 *
 * @param cmd command
 * @return modified command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_reveal_with_retry (struct TALER_TESTING_Command cmd);


/**
 * Create a "refresh link" command.
 *
 * @param label command label.
 * @param reveal_reference reference to a "refresh reveal" CMD.
 * @param expected_response_code expected HTTP response code
 * @return the "refresh link" command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_link (const char *label,
                                const char *reveal_reference,
                                unsigned int expected_response_code);


/**
 * Modify a "refresh link" command to enable retries.
 *
 * @param cmd command
 * @return modified command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_link_with_retry (struct TALER_TESTING_Command cmd);


/**
 * Create a "track transaction" command.
 *
 * @param label the command label.
 * @param transaction_reference reference to a deposit operation,
 *        will be used to get the input data for the track.
 * @param coin_index index of the coin involved in the transaction.
 * @param expected_response_code expected HTTP response code.
 * @param bank_transfer_reference reference to a command that
 *        can offer a WTID so as to check that against what WTID
 *        the tracked operation has.  Set as NULL if not needed.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transaction (const char *label,
                                     const char *transaction_reference,
                                     unsigned int coin_index,
                                     unsigned int expected_response_code,
                                     const char *bank_transfer_reference);

/**
 * Make a "track transfer" CMD where no "expected"-arguments,
 * except the HTTP response code, are given.  The best use case
 * is when what matters to check is the HTTP response code, e.g.
 * when a bogus WTID was passed.
 *
 * @param label the command label
 * @param wtid_reference reference to any command which can provide
 *        a wtid.  If NULL is given, then a all zeroed WTID is
 *        used that will at 99.9999% probability NOT match any
 *        existing WTID known to the exchange.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transfer_empty (const char *label,
                                        const char *wtid_reference,
                                        unsigned int expected_response_code);


/**
 * Make a "track transfer" command, specifying which amount and
 * wire fee are expected.
 *
 * @param label the command label.
 * @param wtid_reference reference to any command which can provide
 *        a wtid.  Will be the one tracked.
 * @param expected_response_code expected HTTP response code.
 * @param expected_total_amount how much money we expect being moved
 *        with this wire-transfer.
 * @param expected_wire_fee expected wire fee.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transfer (const char *label,
                                  const char *wtid_reference,
                                  unsigned int expected_response_code,
                                  const char *expected_total_amount,
                                  const char *expected_wire_fee);


/**
 * Make a "bank check" CMD.  It checks whether a particular wire transfer from
 * the exchange (debit) has been made or not.
 *
 * @param label the command label.
 * @param exchange_base_url base url of the exchange involved in
 *        the wire transfer.
 * @param amount the amount expected to be transferred.
 * @param debit_payto the account that gave money.
 * @param credit_payto the account that received money.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_transfer (const char *label,
                                       const char *exchange_base_url,
                                       const char *amount,
                                       const char *debit_payto,
                                       const char *credit_payto);


/**
 * Make a "bank check" CMD.  It checks whether a particular wire transfer to
 * the exchange (credit) has been made or not.
 *
 * @param label the command label.
 * @param amount the amount expected to be transferred.
 * @param debit_payto the account that gave money.
 * @param credit_payto the account that received money.
 * @param reserve_pub_ref command that provides the reserve public key to expect
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_admin_transfer (const char *label,
                                             const char *amount,
                                             const char *debit_payto,
                                             const char *credit_payto,
                                             const char *reserve_pub_ref);


/**
 * Define a "bank check" CMD that takes the input
 * data from another CMD that offers it.
 *
 * @param label command label.
 * @param deposit_reference reference to a CMD that is
 *        able to provide the "check bank transfer" operation
 *        input data.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_transfer_with_ref (const char *label,
                                                const char *deposit_reference);


/**
 * Checks whether all the wire transfers got "checked"
 * by the "bank check" CMD.
 *
 * @param label command label.
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_empty (const char *label);


/**
 * Create a "refund" command, allow to specify refund transaction
 * id.  Mainly used to create conflicting requests.
 *
 * @param label command label.
 * @param expected_response_code expected HTTP status code.
 * @param refund_amount the amount to ask a refund for.
 * @param coin_reference reference to a command that can
 *        provide a coin to be refunded.
 * @param refund_transaction_id transaction id to use
 *        in the request.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refund_with_id (const char *label,
                                  unsigned int expected_response_code,
                                  const char *refund_amount,
                                  const char *coin_reference,
                                  uint64_t refund_transaction_id);


/**
 * Create a "refund" command.
 *
 * @param label command label.
 * @param expected_response_code expected HTTP status code.
 * @param refund_amount the amount to ask a refund for.
 * @param coin_reference reference to a command that can
 *        provide a coin to be refunded.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refund (const char *label,
                          unsigned int expected_response_code,
                          const char *refund_amount,
                          const char *coin_reference);


/**
 * Make a "recoup" command.
 *
 * @param label the command label
 * @param expected_response_code expected HTTP status code
 * @param coin_reference reference to any command which
 *        offers a coin and reserve private key.  May specify
 *        the index of the coin using "$LABEL#$INDEX" syntax.
 *        Here, $INDEX must be a non-negative number.
 * @param amount how much do we expect to recoup, NULL for nothing
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_recoup (const char *label,
                          unsigned int expected_response_code,
                          const char *coin_reference,
                          const char *amount);


/**
 * Make a "recoup-refresh" command.
 *
 * @param label the command label
 * @param expected_response_code expected HTTP status code
 * @param coin_reference reference to any command which
 *        offers a coin and reserve private key.  May specify
 *        the index of the coin using "$LABEL#$INDEX" syntax.
 *        Here, $INDEX must be a non-negative number.
 * @param melt_reference label of the melt operation
 * @param amount how much do we expect to recoup, NULL for nothing
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_recoup_refresh (const char *label,
                                  unsigned int expected_response_code,
                                  const char *coin_reference,
                                  const char *melt_reference,
                                  const char *amount);


/**
 * Make a "revoke" command.
 *
 * @param label the command label.
 * @param expected_response_code expected HTTP status code.
 * @param coin_reference reference to a CMD that will offer the
 *        denomination to revoke.
 * @param config_filename configuration file name.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_revoke (const char *label,
                          unsigned int expected_response_code,
                          const char *coin_reference,
                          const char *config_filename);


/**
 * Create a "signal" CMD.
 *
 * @param label command label.
 * @param process handle to the process to signal.
 * @param signal signal to send.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_signal (const char *label,
                          struct GNUNET_OS_Process *process,
                          int signal);


/**
 * Sleep for @a duration_s seconds.
 *
 * @param label command label.
 * @param duration_s number of seconds to sleep
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_sleep (const char *label,
                         unsigned int duration_s);


/**
 * This CMD simply tries to connect via HTTP to the
 * service addressed by @a url.  It attempts 10 times
 * before giving up and make the test fail.
 *
 * @param label label for the command.
 * @param url complete URL to connect to.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wait_service (const char *label,
                                const char *url);

/**
 * Create a "batch" command.  Such command takes a
 * end_CMD-terminated array of CMDs and executed them.
 * Once it hits the end CMD, it passes the control
 * to the next top-level CMD, regardless of it being
 * another batch or ordinary CMD.
 *
 * @param label the command label.
 * @param batch array of CMDs to execute.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_batch (const char *label,
                         struct TALER_TESTING_Command *batch);


/**
 * Test if this command is a batch command.
 *
 * @return false if not, true if it is a batch command
 */
bool
TALER_TESTING_cmd_is_batch (const struct TALER_TESTING_Command *cmd);


/**
 * Advance internal pointer to next command.
 *
 * @param is interpreter state.
 * @param[in,out] cls closure of the batch
 * @return true to advance IP in parent
 */
bool
TALER_TESTING_cmd_batch_next (struct TALER_TESTING_Interpreter *is,
                              void *cls);


/**
 * Obtain what command the batch is at.
 *
 * @return cmd current batch command
 */
struct TALER_TESTING_Command *
TALER_TESTING_cmd_batch_get_current (const struct TALER_TESTING_Command *cmd);


/**
 * Set what command the batch should be at.
 *
 * @param cmd current batch command
 * @param new_ip where to move the IP
 */
void
TALER_TESTING_cmd_batch_set_current (const struct TALER_TESTING_Command *cmd,
                                     unsigned int new_ip);


/**
 * Make the "insert-deposit" CMD.
 *
 * @param label command label.
 * @param db_cfg configuration to talk to the DB
 * @param merchant_name Human-readable name of the merchant.
 * @param merchant_account merchant's account name (NOT a payto:// URI)
 * @param exchange_timestamp when did the exchange receive the deposit
 * @param wire_deadline point in time where the aggregator should have
 *        wired money to the merchant.
 * @param amount_with_fee amount to deposit (inclusive of deposit fee)
 * @param deposit_fee deposit fee
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_insert_deposit (
  const char *label,
  const struct GNUNET_CONFIGURATION_Handle *db_cfg,
  const char *merchant_name,
  const char *merchant_account,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Relative wire_deadline,
  const char *amount_with_fee,
  const char *deposit_fee);


/**
 * Performance counter.
 */
struct TALER_TESTING_Timer
{
  /**
   * For which type of commands.
   */
  const char *prefix;

  /**
   * Total time spend in all commands of this type.
   */
  struct GNUNET_TIME_Relative total_duration;

  /**
   * Total time spend waiting for the *successful* exeuction
   * in all commands of this type.
   */
  struct GNUNET_TIME_Relative success_latency;

  /**
   * Number of commands summed up.
   */
  unsigned int num_commands;

  /**
   * Number of retries summed up.
   */
  unsigned int num_retries;
};


/**
 * Obtain performance data from the interpreter.
 *
 * @param timers what commands (by label) to obtain runtimes for
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_stat (struct TALER_TESTING_Timer *timers);


/**
 * Add the auditor to the exchange's list of auditors.
 * The information about the auditor is taken from the
 * "[auditor]" section in the configuration file.
 *
 * @param label command label.
 * @param expected_http_status expected HTTP status from exchange
 * @param bad_sig should we use a bogus signature?
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_auditor_add (const char *label,
                               unsigned int expected_http_status,
                               bool bad_sig);


/**
 * Remove the auditor from the exchange's list of auditors.
 * The information about the auditor is taken from the
 * "[auditor]" section in the configuration file.
 *
 * @param label command label.
 * @param expected_http_status expected HTTP status from exchange
 * @param bad_sig should we use a bogus signature?
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_auditor_del (const char *label,
                               unsigned int expected_http_status,
                               bool bad_sig);


/**
 * Add affirmation that the auditor is auditing the given
 * denomination.
 * The information about the auditor is taken from the
 * "[auditor]" section in the configuration file.
 *
 * @param label command label.
 * @param expected_http_status expected HTTP status from exchange
 * @param denom_ref reference to a command identifying a denomination key
 * @param bad_sig should we use a bogus signature?
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_auditor_add_denom_sig (const char *label,
                                         unsigned int expected_http_status,
                                         const char *denom_ref,
                                         bool bad_sig);


/**
 * Add statement about wire fees of the exchange. This is always
 * done for a few hours around the current time (for the test).
 *
 * @param label command label.
 * @param wire_method wire method to set wire fees for
 * @param wire_fee the wire fee to affirm
 * @param closing_fee the closing fee to affirm
 * @param expected_http_status expected HTTP status from exchange
 * @param bad_sig should we use a bogus signature?
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_set_wire_fee (const char *label,
                                const char *wire_method,
                                const char *wire_fee,
                                const char *closing_fee,
                                unsigned int expected_http_status,
                                bool bad_sig);


/**
 * Add the given payto-URI bank account to the list of bank
 * accounts used by the exchange.
 *
 * @param label command label.
 * @param payto_uri URI identifying the bank account
 * @param expected_http_status expected HTTP status from exchange
 * @param bad_sig should we use a bogus signature?
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wire_add (const char *label,
                            const char *payto_uri,
                            unsigned int expected_http_status,
                            bool bad_sig);


/**
 * Remove the given payto-URI bank account from the list of bank
 * accounts used by the exchange.
 *
 * @param label command label.
 * @param payto_uri URI identifying the bank account
 * @param expected_http_status expected HTTP status from exchange
 * @param bad_sig should we use a bogus signature?
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wire_del (const char *label,
                            const char *payto_uri,
                            unsigned int expected_http_status,
                            bool bad_sig);

/**
 * Sign all extensions that the exchange has to offer, f. e. the extension for
 * age restriction.  This has to be run before any withdrawal of age restricted
 * can be performed.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_offline_sign_extensions (const char *label,
                                                const char *config_filename);


/**
 * Sign all exchange denomination and online signing keys
 * with the "offline" key and provide those signatures to
 * the exchange. (Downloads the keys, makes the signature
 * and uploads the result, all in one.)
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_offline_sign_keys (const char *label,
                                          const char *config_filename);


/**
 * Sign a wire fee structure.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @param wire_fee the wire fee to affirm (for the current year)
 * @param closing_fee the closing fee to affirm (for the current year)
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_offline_sign_fees (const char *label,
                                          const char *config_filename,
                                          const char *wire_fee,
                                          const char *closing_fee);


/**
 * Sign global fee structure.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @param history_fee the history fee to charge (for the current year)
 * @param account_fee the account fee to charge (for the current year)
 * @param purse_fee the purse fee to charge (for the current year)
 * @param purse_timeout when do purses time out
 * @param history_expiration when does an account history expire
 * @param num_purses number of (free) active purses per account
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_offline_sign_global_fees (
  const char *label,
  const char *config_filename,
  const char *history_fee,
  const char *account_fee,
  const char *purse_fee,
  struct GNUNET_TIME_Relative purse_timeout,
  struct GNUNET_TIME_Relative history_expiration,
  unsigned int num_purses);


/**
 * Revoke an exchange denomination key.
 *
 * @param label command label.
 * @param expected_response_code expected HTTP status from exchange
 * @param bad_sig should we use a bogus signature?
 * @param denom_ref reference to a command that identifies
 *        a denomination key (i.e. because it was used to
 *        withdraw a coin).
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_revoke_denom_key (
  const char *label,
  unsigned int expected_response_code,
  bool bad_sig,
  const char *denom_ref);


/**
 * Revoke an exchange online signing key.
 *
 * @param label command label.
 * @param expected_response_code expected HTTP status from exchange
 * @param bad_sig should we use a bogus signature?
 * @param signkey_ref reference to a command that identifies
 *        a signing key (i.e. because it was used to
 *        sign a deposit confirmation).
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_revoke_sign_key (
  const char *label,
  unsigned int expected_response_code,
  bool bad_sig,
  const char *signkey_ref);


/**
 * Create a request for a wallet's KYC UUID.
 *
 * @param label command label.
 * @param reserve_reference command with reserve private key to use (or NULL to create a fresh reserve key).
 * @param threshold_balance balance amount to pass to the exchange
 * @param expected_response_code expected HTTP status
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wallet_kyc_get (const char *label,
                                  const char *reserve_reference,
                                  const char *threshold_balance,
                                  unsigned int expected_response_code);


/**
 * Create a request for an account's KYC status.
 *
 * @param label command label.
 * @param payment_target_reference command with a payment target to query
 * @param expected_response_code expected HTTP status
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_kyc_get (const char *label,
                                 const char *payment_target_reference,
                                 unsigned int expected_response_code);


/**
 * Create a KYC proof request. Only useful in conjunction with the OAuth2.0
 * logic, as it generates an OAuth2.0-specific request.
 *
 * @param label command label.
 * @param payment_target_reference command with a payment target to query
 * @param logic_section name of the KYC provider section
 *         in the exchange configuration for this proof
 * @param code OAuth 2.0 code to use
 * @param expected_response_code expected HTTP status
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_proof_kyc_oauth2 (
  const char *label,
  const char *payment_target_reference,
  const char *logic_section,
  const char *code,
  unsigned int expected_response_code);


/**
 * Starts a fake OAuth 2.0 service on @a port for testing
 * KYC processes which also provides a @a birthdate in a response
 *
 * @param label command label
 * @param birthdate fixed birthdate, such as "2022-03-04", "2022-03-00", "2022-00-00"
 * @param port the TCP port to listen on
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_oauth_with_birthdate (const char *label,
                                        const char *birthdate,
                                        uint16_t port);

/**
 * Starts a fake OAuth 2.0 service on @a port for testing
 * KYC processes.
 *
 * @param label command label
 * @param port the TCP port to listen on
 */
#define TALER_TESTING_cmd_oauth(label, port) \
  TALER_TESTING_cmd_oauth_with_birthdate ((label), NULL, (port))


/* ****************** P2P payment commands ****************** */


/**
 * Creates a purse with deposits.
 *
 * @param label command label
 * @param expected_http_status what HTTP status do we expect to get returned from the exchange
 * @param contract_terms contract, JSON string
 * @param upload_contract should we upload the contract
 * @param purse_expiration how long until the purse expires
 * @param ... NULL-terminated list of references to coins to be deposited
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_create_with_deposit (
  const char *label,
  unsigned int expected_http_status,
  const char *contract_terms,
  bool upload_contract,
  struct GNUNET_TIME_Relative purse_expiration,
  ...);


/**
 * Deletes a purse.
 *
 * @param label command label
 * @param expected_http_status what HTTP status do we expect to get returned from the exchange
 * @param purse_cmd command that created the purse
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_delete (
  const char *label,
  unsigned int expected_http_status,
  const char *purse_cmd);


/**
 * Retrieve contract (also checks that the contract matches
 * the upload command).
 *
 * @param label command label
 * @param expected_http_status what HTTP status do we expect to get returned from the exchange
 * @param for_merge true if for merge, false if for deposit
 * @param contract_ref reference to a command providing us with the contract private key
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_contract_get (
  const char *label,
  unsigned int expected_http_status,
  bool for_merge,
  const char *contract_ref);


/**
 * Retrieve purse state by merge private key.
 *
 * @param label command label
 * @param expected_http_status what HTTP status do we expect to get returned from the exchange
 * @param merge_ref reference to a command providing us with the merge private key
 * @param reserve_ref reference to a command providing us with a reserve private key; if NULL, we create a fresh reserve
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_merge (
  const char *label,
  unsigned int expected_http_status,
  const char *merge_ref,
  const char *reserve_ref);


/**
 * Retrieve purse state.
 *
 * @param label command label
 * @param expected_http_status what HTTP status do we expect to get returned from the exchange
 * @param purse_ref reference to a command providing us with the purse private key
 * @param expected_balance how much should be in the purse
 * @param wait_for_merge true to wait for a merge event, otherwise wait for a deposit event
 * @param timeout how long to wait
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_poll (
  const char *label,
  unsigned int expected_http_status,
  const char *purse_ref,
  const char *expected_balance,
  bool wait_for_merge,
  struct GNUNET_TIME_Relative timeout);


/**
 * Wait for the poll command to complete.
 *
 * @param label command label
 * @param timeout how long to wait at most
 * @param poll_reference which poll command to wait for
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_poll_finish (const char *label,
                                     struct GNUNET_TIME_Relative timeout,
                                     const char *poll_reference);


/**
 * Creates a purse with reserve.
 *
 * @param label command label
 * @param expected_http_status what HTTP status do we expect to get returned from the exchange
 * @param contract_terms contract, JSON string
 * @param upload_contract should we upload the contract
 * @param pay_purse_fee should we pay a fee to create the purse
 * @param expiration when should the purse expire
 * @param reserve_ref reference to reserve key, or NULL to create a new reserve
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_create_with_reserve (
  const char *label,
  unsigned int expected_http_status,
  const char *contract_terms,
  bool upload_contract,
  bool pay_purse_fee,
  struct GNUNET_TIME_Relative expiration,
  const char *reserve_ref);


/**
 * Deposit coins into a purse.
 *
 * @param label command label
 * @param expected_http_status what HTTP status do we expect to get returned from the exchange
 * @param min_age age restriction of the purse
 * @param purse_ref reference to the purse
 * @param ... NULL-terminated list of references to coins to be deposited
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_deposit_coins (
  const char *label,
  unsigned int expected_http_status,
  uint8_t min_age,
  const char *purse_ref,
  ...);


/**
 * Setup AML officer.
 *
 * @param label command label
 * @param ref_cmd command that previously created the
 *       officer, NULL to create one this time
 * @param name full legal name of the officer to use
 * @param is_active true to set the officer to active
 * @param read_only true to restrict the officer to read-only
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_set_officer (
  const char *label,
  const char *ref_cmd,
  const char *name,
  bool is_active,
  bool read_only);


/**
 * Make AML decision.
 *
 * @param label command label
 * @param ref_officer command that previously created an
 *       officer
 * @param ref_operation command that previously created an
 *       h_payto which to make an AML decision about
 * @param new_threshold new threshold to set
 * @param justification justification given for the decision
 * @param new_state new AML state for the account
 * @param kyc_requirement KYC requirement to impose
 * @param expected_response expected HTTP return status
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_take_aml_decision (
  const char *label,
  const char *ref_officer,
  const char *ref_operation,
  const char *new_threshold,
  const char *justification,
  enum TALER_AmlDecisionState new_state,
  const char *kyc_requirement,
  unsigned int expected_response);


/**
 * Fetch AML decision.
 *
 * @param label command label
 * @param ref_officer command that previously created an
 *       officer
 * @param ref_operation command that previously created an
 *       h_payto which to make an AML decision about
 * @param expected_http_status expected HTTP response status
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_aml_decision (
  const char *label,
  const char *ref_officer,
  const char *ref_operation,
  unsigned int expected_http_status);


/**
 * Fetch AML decisions.
 *
 * @param label command label
 * @param ref_officer command that previously created an
 *       officer
 * @param filter AML state to filter by
 * @param expected_http_status expected HTTP response status
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_aml_decisions (
  const char *label,
  const char *ref_officer,
  enum TALER_AmlDecisionState filter,
  unsigned int expected_http_status);


/* ****************** convenience functions ************** */

/**
 * Get exchange URL from interpreter. Convenience function.
 *
 * @param is interpreter state.
 * @return the exchange URL, or NULL on error
 */
const char *
TALER_TESTING_get_exchange_url (
  struct TALER_TESTING_Interpreter *is);


/**
 * Get exchange keys from interpreter. Convenience function.
 *
 * @param is interpreter state.
 * @return the exchange keys, or NULL on error
 */
struct TALER_EXCHANGE_Keys *
TALER_TESTING_get_keys (
  struct TALER_TESTING_Interpreter *is);


/* *** Generic trait logic for implementing traits ********* */


/**
 * Opaque handle to fresh coins generated during refresh.
 * Details are internal to the refresh logic.
 */
struct TALER_TESTING_FreshCoinData;


/**
 * A trait.
 */
struct TALER_TESTING_Trait
{
  /**
   * Index number associated with the trait.  This gives the
   * possibility to have _multiple_ traits on offer under the
   * same name.
   */
  unsigned int index;

  /**
   * Trait type, for example "reserve-pub" or "coin-priv".
   */
  const char *trait_name;

  /**
   * Pointer to the piece of data to offer.
   */
  const void *ptr;
};


/**
 * "end" trait.  Because traits are offered into arrays,
 * this type of trait is used to mark the end of such arrays;
 * useful when iterating over those.
 */
struct TALER_TESTING_Trait
TALER_TESTING_trait_end (void);


/**
 * Extract a trait.
 *
 * @param traits the array of all the traits.
 * @param[out] ret where to store the result.
 * @param trait type of the trait to extract.
 * @param index index number of the trait to extract.
 * @return #GNUNET_OK when the trait is found.
 */
enum GNUNET_GenericReturnValue
TALER_TESTING_get_trait (const struct TALER_TESTING_Trait *traits,
                         const void **ret,
                         const char *trait,
                         unsigned int index);


/* ****** Specific traits supported by this component ******* */


/**
 * Create headers for a trait with name @a name for
 * statically allocated data of type @a type.
 */
#define TALER_TESTING_MAKE_DECL_SIMPLE_TRAIT(name,type)   \
  enum GNUNET_GenericReturnValue                          \
    TALER_TESTING_get_trait_ ## name (                    \
    const struct TALER_TESTING_Command *cmd,              \
    type **ret);                                          \
  struct TALER_TESTING_Trait                              \
    TALER_TESTING_make_trait_ ## name (                   \
    type * value);


/**
 * Create C implementation for a trait with name @a name for statically
 * allocated data of type @a type.
 */
#define TALER_TESTING_MAKE_IMPL_SIMPLE_TRAIT(name,type)  \
  enum GNUNET_GenericReturnValue                         \
    TALER_TESTING_get_trait_ ## name (                   \
    const struct TALER_TESTING_Command *cmd,             \
    type **ret)                                          \
  {                                                      \
    if (NULL == cmd->traits) return GNUNET_SYSERR;       \
    return cmd->traits (cmd->cls,                        \
                        (const void **) ret,             \
                        TALER_S (name),                  \
                        0);                              \
  }                                                      \
  struct TALER_TESTING_Trait                             \
    TALER_TESTING_make_trait_ ## name (                  \
    type * value)                                        \
  {                                                      \
    struct TALER_TESTING_Trait ret = {                   \
      .trait_name = TALER_S (name),                      \
      .ptr = (const void *) value                        \
    };                                                   \
    return ret;                                          \
  }


/**
 * Create headers for a trait with name @a name for
 * statically allocated data of type @a type.
 */
#define TALER_TESTING_MAKE_DECL_INDEXED_TRAIT(name,type)  \
  enum GNUNET_GenericReturnValue                          \
    TALER_TESTING_get_trait_ ## name (                    \
    const struct TALER_TESTING_Command *cmd,              \
    unsigned int index,                                   \
    type **ret);                                          \
  struct TALER_TESTING_Trait                              \
    TALER_TESTING_make_trait_ ## name (                   \
    unsigned int index,                                   \
    type * value);


/**
 * Create C implementation for a trait with name @a name for statically
 * allocated data of type @a type.
 */
#define TALER_TESTING_MAKE_IMPL_INDEXED_TRAIT(name,type) \
  enum GNUNET_GenericReturnValue                         \
    TALER_TESTING_get_trait_ ## name (                   \
    const struct TALER_TESTING_Command *cmd,             \
    unsigned int index,                                  \
    type **ret)                                          \
  {                                                      \
    if (NULL == cmd->traits) return GNUNET_SYSERR;       \
    return cmd->traits (cmd->cls,                        \
                        (const void **) ret,             \
                        TALER_S (name),                  \
                        index);                          \
  }                                                      \
  struct TALER_TESTING_Trait                             \
    TALER_TESTING_make_trait_ ## name (                  \
    unsigned int index,                                  \
    type * value)                                        \
  {                                                      \
    struct TALER_TESTING_Trait ret = {                   \
      .index = index,                                    \
      .trait_name = TALER_S (name),                      \
      .ptr = (const void *) value                        \
    };                                                   \
    return ret;                                          \
  }


/**
 * Call #op on all simple traits.
 */
#define TALER_TESTING_SIMPLE_TRAITS(op) \
  op (bank_row, const uint64_t)                                    \
  op (officer_pub, const struct TALER_AmlOfficerPublicKeyP)        \
  op (officer_priv, const struct TALER_AmlOfficerPrivateKeyP)      \
  op (officer_name, const char)                                    \
  op (aml_decision, enum TALER_AmlDecisionState)                   \
  op (aml_justification, const char)                               \
  op (auditor_priv, const struct TALER_AuditorPrivateKeyP)         \
  op (auditor_pub, const struct TALER_AuditorPublicKeyP)           \
  op (master_priv, const struct TALER_MasterPrivateKeyP)           \
  op (master_pub, const struct TALER_MasterPublicKeyP)             \
  op (purse_priv, const struct TALER_PurseContractPrivateKeyP)     \
  op (purse_pub, const struct TALER_PurseContractPublicKeyP)       \
  op (merge_priv, const struct TALER_PurseMergePrivateKeyP)        \
  op (merge_pub, const struct TALER_PurseMergePublicKeyP)          \
  op (contract_priv, const struct TALER_ContractDiffiePrivateP)    \
  op (reserve_priv, const struct TALER_ReservePrivateKeyP)         \
  op (reserve_sig, const struct TALER_ReserveSignatureP)           \
  op (h_payto, const struct TALER_PaytoHashP)                      \
  op (planchet_secret, const struct TALER_PlanchetMasterSecretP)   \
  op (refresh_secret, const struct TALER_RefreshMasterSecretP)     \
  op (reserve_pub, const struct TALER_ReservePublicKeyP)           \
  op (merchant_priv, const struct TALER_MerchantPrivateKeyP)       \
  op (merchant_pub, const struct TALER_MerchantPublicKeyP)         \
  op (merchant_sig, const struct TALER_MerchantSignatureP)         \
  op (wtid, const struct TALER_WireTransferIdentifierRawP)         \
  op (bank_auth_data, const struct TALER_BANK_AuthenticationData)  \
  op (contract_terms, const json_t)                                \
  op (wire_details, const json_t)                                  \
  op (exchange_url, const char)                                    \
  op (auditor_url, const char)                                     \
  op (exchange_bank_account_url, const char)                       \
  op (taler_uri, const char)                                       \
  op (payto_uri, const char)                                       \
  op (kyc_url, const char)                                         \
  op (web_url, const char)                                         \
  op (row, const uint64_t)                                         \
  op (legi_requirement_row, const uint64_t)                        \
  op (array_length, const unsigned int)                            \
  op (credit_payto_uri, const char)                                \
  op (debit_payto_uri, const char)                                 \
  op (order_id, const char)                                        \
  op (amount, const struct TALER_Amount)                           \
  op (amount_with_fee, const struct TALER_Amount)                  \
  op (batch_cmds, struct TALER_TESTING_Command)                    \
  op (uuid, const struct GNUNET_Uuid)                              \
  op (fresh_coins, const struct TALER_TESTING_FreshCoinData *)     \
  op (claim_token, const struct TALER_ClaimTokenP)                 \
  op (relative_time, const struct GNUNET_TIME_Relative)            \
  op (fakebank, struct TALER_FAKEBANK_Handle)                      \
  op (keys, struct TALER_EXCHANGE_Keys)                            \
  op (process, struct GNUNET_OS_Process *)


/**
 * Call #op on all indexed traits.
 */
#define TALER_TESTING_INDEXED_TRAITS(op)                                \
  op (denom_pub, const struct TALER_EXCHANGE_DenomPublicKey)            \
  op (denom_sig, const struct TALER_DenominationSignature)              \
  op (amounts, const struct TALER_Amount)                               \
  op (deposit_amount, const struct TALER_Amount)                        \
  op (deposit_fee_amount, const struct TALER_Amount)                    \
  op (age_commitment, const struct TALER_AgeCommitment)                 \
  op (age_commitment_proof, const struct TALER_AgeCommitmentProof)      \
  op (h_age_commitment, const struct TALER_AgeCommitmentHash)           \
  op (reserve_history, const struct TALER_EXCHANGE_ReserveHistoryEntry) \
  op (planchet_secrets, const struct TALER_PlanchetMasterSecretP)       \
  op (exchange_wd_value, const struct TALER_ExchangeWithdrawValues)     \
  op (coin_priv, const struct TALER_CoinSpendPrivateKeyP)               \
  op (coin_pub, const struct TALER_CoinSpendPublicKeyP)                 \
  op (coin_sig, const struct TALER_CoinSpendSignatureP)                 \
  op (absolute_time, const struct GNUNET_TIME_Absolute)                 \
  op (timestamp, const struct GNUNET_TIME_Timestamp)                    \
  op (wire_deadline, const struct GNUNET_TIME_Timestamp)                \
  op (refund_deadline, const struct GNUNET_TIME_Timestamp)              \
  op (exchange_pub, const struct TALER_ExchangePublicKeyP)              \
  op (exchange_sig, const struct TALER_ExchangeSignatureP)              \
  op (blinding_key, const union TALER_DenominationBlindingKeyP)         \
  op (h_blinded_coin, const struct TALER_BlindedCoinHashP)

TALER_TESTING_SIMPLE_TRAITS (TALER_TESTING_MAKE_DECL_SIMPLE_TRAIT)

TALER_TESTING_INDEXED_TRAITS (TALER_TESTING_MAKE_DECL_INDEXED_TRAIT)


#endif
