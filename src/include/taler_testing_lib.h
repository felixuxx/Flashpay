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
#include "taler_bank_service.h"
#include <microhttpd.h>


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
 * Configuration data for an exchange.
 */
struct TALER_TESTING_ExchangeConfiguration
{
  /**
   * Exchange base URL as it appears in the configuration.  Note
   * that it might differ from the one where the exchange actually
   * listens from.
   */
  char *exchange_url;

  /**
   * Auditor base URL as it appears in the configuration.  Note
   * that it might differ from the one where the auditor actually
   * listens from.
   */
  char *auditor_url;

};

/**
 * Connection to the database: aggregates
 * plugin and session handles.
 */
struct TALER_TESTING_DatabaseConnection
{
  /**
   * Database plugin.
   */
  struct TALER_EXCHANGEDB_Plugin *plugin;

  /**
   * Session with the database.
   */
  struct TALER_EXCHANGEDB_Session *session;
};

struct TALER_TESTING_LibeufinServices
{
  /**
   * Nexus
   */
  struct GNUNET_OS_Process *nexus;

  /**
   * Sandbox
   */
  struct GNUNET_OS_Process *sandbox;

};

/**
 * Prepare launching an exchange.  Checks that the configured
 * port is available, runs taler-exchange-keyup,
 * taler-auditor-sign and taler-exchange-dbinit.  Does not
 * launch the exchange process itself.
 *
 * @param config_filename configuration file to use
 * @param reset_db should we reset the database
 * @param[out] ec will be set to the exchange configuration data
 * @return #GNUNET_OK on success, #GNUNET_NO if test should be
 *         skipped, #GNUNET_SYSERR on test failure
 */
int
TALER_TESTING_prepare_exchange (const char *config_filename,
                                int reset_db,
                                struct TALER_TESTING_ExchangeConfiguration *ec);


/**
 * "Canonical" cert_cb used when we are connecting to the
 * Exchange.
 *
 * @param cls closure, typically, the "run" method containing
 *        all the commands to be run, and a closure for it.
 * @param hr http response details
 * @param keys the exchange's keys.
 * @param compat protocol compatibility information.
 */
void
TALER_TESTING_cert_cb (void *cls,
                       const struct TALER_EXCHANGE_HttpResponse *hr,
                       const struct TALER_EXCHANGE_Keys *keys,
                       enum TALER_EXCHANGE_VersionCompatibility compat);


/**
 * Wait for the exchange to have started. Waits for at
 * most 10s, after that returns 77 to indicate an error.
 *
 * @param base_url what URL should we expect the exchange
 *        to be running at
 * @return 0 on success
 */
int
TALER_TESTING_wait_exchange_ready (const char *base_url);


/**
 * Wait for the auditor to have started. Waits for at
 * most 10s, after that returns 77 to indicate an error.
 *
 * @param base_url what URL should we expect the auditor
 *        to be running at
 * @return 0 on success
 */
int
TALER_TESTING_wait_auditor_ready (const char *base_url);


/**
 * Remove files from previous runs
 *
 * @param config_name configuration file to use+
 */
void
TALER_TESTING_cleanup_files (const char *config_name);


/**
 * Remove files from previous runs
 *
 * @param cls NULL
 * @param cfg configuration
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_cleanup_files_cfg (void *cls,
                                 const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Run `taler-exchange-keyup`.
 *
 * @param config_filename configuration file to use
 * @param output_filename where to write the output for the auditor
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_run_keyup (const char *config_filename,
                         const char *output_filename);


/**
 * Run `taler-auditor-dbinit -r` (reset auditor database).
 *
 * @param config_filename configuration file to use
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_auditor_db_reset (const char *config_filename);


/**
 * Run `taler-exchange-dbinit -r` (reset exchange database).
 *
 * @param config_filename configuration file to use
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_exchange_db_reset (const char *config_filename);


/**
 * Run `taler-auditor-sign`.
 *
 * @param config_filename configuration file to use
 * @param exchange_master_pub master public key of the exchange
 * @param auditor_base_url what is the base URL of the auditor
 * @param signdata_in where is the information from taler-exchange-keyup
 * @param signdata_out where to write the output for the exchange
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_run_auditor_sign (const char *config_filename,
                                const char *exchange_master_pub,
                                const char *auditor_base_url,
                                const char *signdata_in,
                                const char *signdata_out);


/**
 * Run `taler-auditor-exchange`.
 *
 * @param config_filename configuration file to use
 * @param exchange_master_pub master public key of the exchange
 * @param exchange_base_url what is the base URL of the exchange
 * @param do_remove #GNUNET_NO to add exchange, #GNUNET_YES to remove
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_run_auditor_exchange (const char *config_filename,
                                    const char *exchange_master_pub,
                                    const char *exchange_base_url,
                                    int do_remove);


/**
 * Test port in URL string for availability.
 *
 * @param url URL to extract port from, 80 is default
 * @return #GNUNET_OK if the port is free
 */
int
TALER_TESTING_url_port_free (const char *url);


/**
 * Configuration data for a bank.
 */
struct TALER_TESTING_BankConfiguration
{

  /**
   * Authentication data for the exchange user at the bank.
   */
  struct TALER_BANK_AuthenticationData exchange_auth;

  /**
   * Payto URL of the exchange's account ("2")
   */
  char *exchange_payto;

  /**
   * Payto URL of a user account ("42")
   */
  char *user42_payto;

  /**
   * Payto URL of another user's account ("43")
   */
  char *user43_payto;

};

/**
 * Prepare launching a fakebank.  Check that the configuration
 * file has the right option, and that the port is available.
 * If everything is OK, return the configuration data of the fakebank.
 *
 * @param config_filename configuration file to use
 * @param config_section which account to use
 *                       (must match x-taler-bank)
 * @param[out] bc set to the bank's configuration data
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_prepare_fakebank (const char *config_filename,
                                const char *config_section,
                                struct TALER_TESTING_BankConfiguration *bc);


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
   * Our configuration.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Context for running the CURL event loop.
   */
  struct GNUNET_CURL_RescheduleContext *rc;

  /**
   * Handle to our fakebank, if #TALER_TESTING_run_with_fakebank()
   * was used.  Otherwise NULL.
   */
  struct TALER_FAKEBANK_Handle *fakebank;

  /**
   * Task run on timeout.
   */
  struct GNUNET_SCHEDULER_Task *timeout_task;

  /**
   * Function to call for cleanup at the end. Can be NULL.
   */
  GNUNET_SCHEDULER_TaskCallback final_cleanup_cb;

  /**
   * Closure for #final_cleanup_cb().
   */
  void *final_cleanup_cb_cls;

  /**
   * Instruction pointer.  Tells #interpreter_run() which instruction to run
   * next.  Need (signed) int because it gets -1 when rewinding the
   * interpreter to the first CMD.
   */
  int ip;

  /**
   * Result of the testcases, #GNUNET_OK on success
   */
  int result;

  /**
   * Handle to the exchange.
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * Handle to the auditor.  NULL unless specifically initialized
   * as part of #TALER_TESTING_auditor_setup().
   */
  struct TALER_AUDITOR_Handle *auditor;

  /**
   * Handle to exchange process; some commands need it
   * to send signals.  E.g. to trigger the key state reload.
   */
  struct GNUNET_OS_Process *exchanged;

  /**
   * #GNUNET_OK if key state should be reloaded.  NOTE: this
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
   * Is the auditor running (#GNUNET_YES) or waiting
   * for /version (#GNUNET_NO)?
   */
  int auditor_working;

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
   * @param cls closure
   * @param cmd command being run
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
  int
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
 * Obtain main execution context for the main loop.
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
 * Get connection handle to the fakebank.
 *
 * @param is interpreter state.
 * @return the handle.
 */
struct TALER_FAKEBANK_Handle *
TALER_TESTING_interpreter_get_fakebank (struct TALER_TESTING_Interpreter *is);

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
 * Create command array terminator.
 *
 * @return a end-command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_end (void);


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
 * First launch the fakebank, then schedule the first CMD
 * in the array of all the CMDs to execute.
 *
 * @param is interpreter state.
 * @param commands array of all the commands to execute.
 * @param bank_url base URL of the fake bank.
 */
void
TALER_TESTING_run_with_fakebank (struct TALER_TESTING_Interpreter *is,
                                 struct TALER_TESTING_Command *commands,
                                 const char *bank_url);


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
 * Install signal handlers plus schedules the main wrapper
 * around the "run" method.
 *
 * @param main_cb the "run" method which coontains all the
 *        commands.
 * @param main_cb_cls a closure for "run", typically NULL.
 * @param cfg configuration to use
 * @param exchanged exchange process handle: will be put in the
 *        state as some commands - e.g. revoke - need to send
 *        signal to it, for example to let it know to reload the
 *        key state.. if NULL, the interpreter will run without
 *        trying to connect to the exchange first.
 * @param exchange_connect GNUNET_YES if the test should connect
 *        to the exchange, GNUNET_NO otherwise
 * @return #GNUNET_OK if all is okay, != #GNUNET_OK otherwise.
 *         non-GNUNET_OK codes are #GNUNET_SYSERR most of the
 *         times.
 */
int
TALER_TESTING_setup (TALER_TESTING_Main main_cb,
                     void *main_cb_cls,
                     const struct GNUNET_CONFIGURATION_Handle *cfg,
                     struct GNUNET_OS_Process *exchanged,
                     int exchange_connect);


/**
 * Install signal handlers plus schedules the main wrapper
 * around the "run" method.
 *
 * @param main_cb the "run" method which contains all the
 *        commands.
 * @param main_cb_cls a closure for "run", typically NULL.
 * @param config_filename configuration filename.
 * @return #GNUNET_OK if all is okay, != #GNUNET_OK otherwise.
 *         non-GNUNET_OK codes are #GNUNET_SYSERR most of the
 *         times.
 */
int
TALER_TESTING_auditor_setup (TALER_TESTING_Main main_cb,
                             void *main_cb_cls,
                             const char *config_filename);


/**
 * Closure for #TALER_TESTING_setup_with_exchange_cfg().
 */
struct TALER_TESTING_SetupContext
{
  /**
   * Main function of the test to run.
   */
  TALER_TESTING_Main main_cb;

  /**
   * Closure for @e main_cb.
   */
  void *main_cb_cls;

  /**
   * Name of the configuration file.
   */
  const char *config_filename;
};


/**
 * Initialize scheduler loop and curl context for the test case
 * including starting and stopping the exchange using the given
 * configuration file.
 *
 * @param cls must be a `struct TALER_TESTING_SetupContext *`
 * @param cfg configuration to use.
 * @return #GNUNET_OK if no errors occurred.
 */
int
TALER_TESTING_setup_with_exchange_cfg (
  void *cls,
  const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Initialize scheduler loop and curl context for the test case
 * including starting and stopping the exchange using the given
 * configuration file.
 *
 * @param main_cb main method.
 * @param main_cb_cls main method closure.
 * @param config_file configuration file name.  Is is used
 *        by both this function and the exchange itself.  In the
 *        first case it gives out the exchange port number and
 *        the exchange base URL so as to check whether the port
 *        is available and the exchange responds when requested
 *        at its base URL.
 * @return #GNUNET_OK if no errors occurred.
 */
int
TALER_TESTING_setup_with_exchange (TALER_TESTING_Main main_cb,
                                   void *main_cb_cls,
                                   const char *config_file);


/**
 * Initialize scheduler loop and curl context for the test case
 * including starting and stopping the auditor and exchange using
 * the given configuration file.
 *
 * @param cls must be a `struct TALER_TESTING_SetupContext *`
 * @param cfg configuration to use.
 * @return #GNUNET_OK if no errors occurred.
 */
int
TALER_TESTING_setup_with_auditor_and_exchange_cfg (
  void *cls,
  const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Initialize scheduler loop and curl context for the test case
 * including starting and stopping the auditor and exchange using
 * the given configuration file.
 *
 * @param main_cb main method.
 * @param main_cb_cls main method closure.
 * @param config_file configuration file name.  Is is used
 *        by both this function and the exchange itself.  In the
 *        first case it gives out the exchange port number and
 *        the exchange base URL so as to check whether the port
 *        is available and the exchange responds when requested
 *        at its base URL.
 * @return #GNUNET_OK if no errors occurred.
 */
int
TALER_TESTING_setup_with_auditor_and_exchange (TALER_TESTING_Main main_cb,
                                               void *main_cb_cls,
                                               const char *config_file);


/**
 * Start the (Python) bank process.  Assume the port
 * is available and the database is clean.  Use the "prepare
 * bank" function to do such tasks.
 *
 * @param config_filename configuration filename.
 * @param bank_url base URL of the bank, used by `wget' to check
 *        that the bank was started right.
 * @return the process, or NULL if the process could not
 *         be started.
 */
struct GNUNET_OS_Process *
TALER_TESTING_run_bank (const char *config_filename,
                        const char *bank_url);

/**
 * Start the (nexus) bank process.  Assume the port
 * is available and the database is clean.  Use the "prepare
 * bank" function to do such tasks.  This function is also
 * responsible to create the exchange EBICS subscriber at
 * the nexus.
 *
 * @param bc bank configuration of the bank
 * @return the process, or NULL if the process could not
 *         be started.
 */
struct TALER_TESTING_LibeufinServices
TALER_TESTING_run_libeufin (const struct TALER_TESTING_BankConfiguration *bc);


/**
 * Runs the Fakebank by guessing / extracting the portnumber
 * from the base URL.
 *
 * @param bank_url bank's base URL.
 * @param currency currency the bank uses
 * @return the fakebank process handle, or NULL if any
 *         error occurs.
 */
struct TALER_FAKEBANK_Handle *
TALER_TESTING_run_fakebank (const char *bank_url,
                            const char *currency);


/**
 * Prepare the bank execution.  Check if the port is available
 * and reset database.
 *
 * @param config_filename configuration file name.
 * @param reset_db should we reset the bank's database
 * @param[out] bc set to the bank's configuration data
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_prepare_bank (const char *config_filename,
                            int reset_db,
                            const char *config_section,
                            struct TALER_TESTING_BankConfiguration *bc);

/**
 * Prepare the Nexus execution.  Check if the port is available
 * and delete old database.
 *
 * @param config_filename configuration file name.
 * @param reset_db should we reset the bank's database
 * @param config_section section of the configuration with the exchange's account
 * @param[out] bc set to the bank's configuration data
 * @return the base url, or NULL upon errors.  Must be freed
 *         by the caller.
 */
int
TALER_TESTING_prepare_nexus (const char *config_filename,
                             int reset_db,
                             const char *config_section,
                             struct TALER_TESTING_BankConfiguration *bc);

/**
 * Look for substring in a programs' name.
 *
 * @param prog program's name to look into
 * @param marker chunk to find in @a prog
 */
int
TALER_TESTING_has_in_name (const char *prog,
                           const char *marker);


/* ************** Specific interpreter commands ************ */


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
 * @param label command label.
 * @param amount amount to transfer.
 * @param auth authentication data to use
 * @param payto_credit_account which account receives money.
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
 * @param auditor auditor connection.
 * @param deposit_reference reference to any operation that can
 *        provide a coin.
 * @param coin_index if @a deposit_reference offers an array of
 *        coins, this parameter selects which one in that array.
 *        This value is currently ignored, as only one-coin
 *        deposits are implemented.
 * @param amount_without_fee deposited amount without the fee
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_confirmation (const char *label,
                                        struct TALER_AUDITOR_Handle *auditor,
                                        const char *deposit_reference,
                                        unsigned int coin_index,
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
  struct TALER_TESTING_Command
  cmd);


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
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming_with_ref (
  const char *label,
  const char *amount,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *payto_debit_account,
  const char *ref);


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
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_wirewatch (const char *label,
                                  const char *config_filename);

/**
 * Make a "aggregator" CMD.
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
 * Make the "keyup" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_keyup (const char *label,
                              const char *config_filename);


/**
 * Make the "keyup" CMD, with "--timestamp" option.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @param now Unix timestamp representing the fake "now".
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_keyup_with_now (const char *label,
                                       const char *config_filename,
                                       struct GNUNET_TIME_Absolute now);


/**
 * Make a "check keys" command.  This type of command
 * checks whether the number of denomination keys from
 * @a exchange matches @a num_denom_keys.
 *
 * @param label command label
 * @param generation when this command is run, exactly @a
 *        generation /keys downloads took place.  If the number
 *        of downloads is less than @a generation, the logic will
 *        first make sure that @a generation downloads are done,
 *        and _then_ execute the rest of the command.
 * @param num_denom_keys expected number of denomination keys.
 * @param now timestamp to use when fetching keys
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_with_now (const char *label,
                                       unsigned int generation,
                                       unsigned int num_denom_keys,
                                       struct GNUNET_TIME_Absolute now);


/**
 * Make a "auditor sign" CMD.
 *
 * @param label command label
 * @param config_filename configuration filename
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_auditor_sign (const char *label,
                                     const char *config_filename);


/**
 * Create a withdraw command, letting the caller specify
 * the desired amount as string.
 *
 * @param label command label.
 * @param reserve_reference command providing us with a reserve to withdraw from
 * @param amount how much we withdraw.
 * @param expected_response_code which HTTP response code
 *        we expect from the exchange.
 * @return the withdraw command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount (const char *label,
                                   const char *reserve_reference,
                                   const char *amount,
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
 * Create a "wire" command.
 *
 * @param label the command label.
 * @param expected_method which wire-transfer method is expected
 *        to be offered by the exchange.
 * @param expected_fee the fee the exchange should charge.
 * @param expected_response_code the HTTP response the exchange
 *        should return.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wire (const char *label,
                        const char *expected_method,
                        const char *expected_fee,
                        unsigned int expected_response_code);


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
 * Index of the deposit value trait of a deposit command.
 */
#define TALER_TESTING_CMD_DEPOSIT_TRAIT_IDX_DEPOSIT_VALUE 0

/**
 * Index of the deposit fee trait of a deposit command.
 */
#define TALER_TESTING_CMD_DEPOSIT_TRAIT_IDX_DEPOSIT_FEE 1

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
 *
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
 * @param index index number of the WTID to track, in case there
 *        are multiple on offer.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transfer_empty (const char *label,
                                        const char *wtid_reference,
                                        unsigned int index,
                                        unsigned int expected_response_code);


/**
 * Make a "track transfer" command, specifying which amount and
 * wire fee are expected.
 *
 * @param label the command label.
 * @param wtid_reference reference to any command which can provide
 *        a wtid.  Will be the one tracked.
 * @param index in case there are multiple WTID offered, this
 *        parameter selects a particular one.
 * @param expected_response_code expected HTTP response code.
 * @param expected_total_amount how much money we expect being moved
 *        with this wire-transfer.
 * @param expected_wire_fee expected wire fee.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transfer (const char *label,
                                  const char *wtid_reference,
                                  unsigned int index,
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
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refund_with_id (const char *label,
                                  unsigned int expected_response_code,
                                  const char *refund_amount,
                                  const char *deposit_reference,
                                  uint64_t refund_transaction_id);


/**
 * Create a "refund" command.
 *
 * @param label command label.
 * @param expected_response_code expected HTTP status code.
 * @param refund_amount the amount to ask a refund for.
 * @param coin_reference reference to a command that can
 *        provide a coin to be refunded.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refund (const char *label,
                          unsigned int expected_response_code,
                          const char *refund_amount,
                          const char *deposit_reference);


/**
 * Make a "recoup" command.
 *
 * @param label the command label
 * @param expected_response_code expected HTTP status code
 * @param coin_reference reference to any command which
 *        offers a coin and reserve private key.  May specify
 *        the index of the coin using "$LABEL#$INDEX" syntax.
 *        Here, $INDEX must be a non-negative number.
 * @param melt_reference NULL if coin was not refreshed, otherwise label of the melt operation
 * @param amount how much do we expect to recoup, NULL for nothing
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_recoup (const char *label,
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
 * Make a "check keys" command.  This type of command
 * checks whether the number of denomination keys from
 * @a exchange matches @a num_denom_keys.
 *
 * @param label command label
 * @param generation how many /keys responses are expected to
 *        have been returned when this CMD will be run.
 * @param num_denom_keys expected number of denomination keys.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys (const char *label,
                              unsigned int generation,
                              unsigned int num_denom_keys);


/**
 * Make a "check keys" command that forcedly does NOT cherry pick;
 * just redownload the whole /keys.  Then checks whether the number
 * of denomination keys from @a exchange matches @a num_denom_keys.
 *
 * @param label command label
 * @param generation when this command is run, exactly @a
 *        generation /keys downloads took place.  If the number
 *        of downloads is less than @a generation, the logic will
 *        first make sure that @a generation downloads are done,
 *        and _then_ execute the rest of the command.
 * @param num_denom_keys expected number of denomination keys.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_pull_all_keys (const char *label,
                                            unsigned int generation,
                                            unsigned int num_denom_keys);


/**
 * Make a "check keys" command.  This type of command
 * checks whether the number of denomination keys from
 * @a exchange matches @a num_denom_keys.  Additionally,
 * it lets the user set a last denom issue date to be
 * used in the request for /keys.
 *
 * @param label command label
 * @param generation when this command is run, exactly @a
 *        generation /keys downloads took place.  If the number
 *        of downloads is less than @a generation, the logic will
 *        first make sure that @a generation downloads are done,
 *        and _then_ execute the rest of the command.
 * @param num_denom_keys expected number of denomination keys.
 * @param last_denom_date date to be set in the "last_denom_issue"
 *        URL parameter of /keys.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_with_last_denom (const char *label,
                                              unsigned int generation,
                                              unsigned int num_denom_keys,
                                              struct GNUNET_TIME_Absolute
                                              last_denom_date);


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
int
TALER_TESTING_cmd_is_batch (const struct TALER_TESTING_Command *cmd);

/**
 * Advance internal pointer to next command.
 *
 * @param is interpreter state.
 */
void
TALER_TESTING_cmd_batch_next (struct TALER_TESTING_Interpreter *is);

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
 * Make a serialize-keys CMD.
 *
 * @param label CMD label
 * @return the CMD.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_serialize_keys (const char *label);


/**
 * Make a connect-with-state CMD.  This command
 * will use a serialized key state to reconnect
 * to the exchange.
 *
 * @param label command label
 * @param state_reference label of a CMD offering
 *        a serialized key state.
 * @return the CMD.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_connect_with_state (const char *label,
                                      const char *state_reference);

/**
 * Make the "insert-deposit" CMD.
 *
 * @param label command label.
 * @param dbc collects plugin and session handles
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
  const struct TALER_TESTING_DatabaseConnection *dbc,
  const char *merchant_name,
  const char *merchant_account,
  struct GNUNET_TIME_Absolute exchange_timestamp,
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
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_auditor_del (const char *label);


/**
 * Add the given payto-URI bank account to the list of bank
 * accounts used by the exchange.
 *
 * @param label command label.
 * @param payto_uri URI identifying the bank account
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wire_add (const char *label,
                            const char *payto_uri);


/**
 * Remove the given payto-URI bank account from the list of bank
 * accounts used by the exchange.
 *
 * @param label command label.
 * @param payto_uri URI identifying the bank account
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wire_del (const char *label,
                            const char *payto_uri);


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
TALER_TESTING_cmd_offline_sign_keys (const char *label,
                                     const char *config_filename);


/**
 * Revoke an exchange denomination key.
 *
 * @param label command label.
 * @param denom_ref reference to a command that identifies
 *        a denomination key (i.e. because it was used to
 *        withdraw a coin).
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_revoke_denom_key (const char *label,
                                    const char *denom_ref);


/**
 * Have the auditor affirm that it is auditing the given
 * denomination key and upload the auditor's signature to
 * the exchange.
 *
 * @param label command label.
 * @param denom_ref reference to a command that identifies
 *        a denomination key (i.e. because it was used to
 *        withdraw a coin).
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_auditor_add_denom_key (const char *denom_ref);


/**
 * Revoke an exchange signing key.
 *
 * @param label command label.
 * @param denom_ref reference to a command that identifies
 *        a signing key (i.e. because it was used to
 *        sign a deposit confirmation).
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_revoke_denom_key (const char *label,
                                    const char *signkey_ref);


/* *** Generic trait logic for implementing traits ********* */

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
int
TALER_TESTING_get_trait (const struct TALER_TESTING_Trait *traits,
                         const void **ret,
                         const char *trait,
                         unsigned int index);


/* ****** Specific traits supported by this component ******* */


/**
 * Obtain a bank transaction row value from @a cmd.
 *
 * @param cmd command to extract the number from.
 * @param[out] row set to the number coming from @a cmd.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_bank_row (const struct TALER_TESTING_Command *cmd,
                                  const uint64_t **row);


/**
 * Offer bank transaction row trait.
 *
 * @param row number to offer.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_bank_row (const uint64_t *row);


/**
 * Offer a reserve private key.
 *
 * @param index reserve priv's index number.
 * @param reserve_priv reserve private key to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_reserve_priv (
  unsigned int index,
  const struct TALER_ReservePrivateKeyP *reserve_priv);


/**
 * Obtain a reserve private key from a @a cmd.
 *
 * @param cmd command to extract the reserve priv from.
 * @param index reserve priv's index number.
 * @param[out] reserve_priv set to the reserve priv.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_reserve_priv (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_ReservePrivateKeyP **reserve_priv);


/**
 * Offer a reserve public key.
 *
 * @param index reserve pubs's index number.
 * @param reserve_pub reserve public key to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_reserve_pub (
  unsigned int index,
  const struct TALER_ReservePublicKeyP *reserve_pub);


/**
 * Obtain a reserve public key from a @a cmd.
 *
 * @param cmd command to extract the reserve pub from.
 * @param index reserve pub's index number.
 * @param[out] reserve_pub set to the reserve pub.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_reserve_pub (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_ReservePublicKeyP **reserve_pub);


/**
 * Offer a reserve history entry.
 *
 * @param index reserve pubs's index number.
 * @param rh reserve history entry to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_reserve_history (
  unsigned int index,
  const struct TALER_EXCHANGE_ReserveHistory *rh);


/**
 * Obtain a reserve history entry from a @a cmd.
 *
 * @param cmd command to extract the reserve history from.
 * @param index reserve history's index number.
 * @param[out] rhp set to the reserve history.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_reserve_history (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_EXCHANGE_ReserveHistory **rhp);


/**
 * Make a trait for a exchange signature.
 *
 * @param index index number to associate to the offered exchange pub.
 * @param exchange_sig exchange signature to offer with this trait.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_exchange_sig (
  unsigned int index,
  const struct TALER_ExchangeSignatureP *exchange_sig);


/**
 * Obtain a exchange signature (online sig) from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index index number of the exchange to obtain.
 * @param[out] exchange_sig set to the offered exchange signature.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_exchange_sig (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_ExchangeSignatureP **exchange_sig);


/**
 * Make a trait for a exchange public key.
 *
 * @param index index number to associate to the offered exchange pub.
 * @param exchange_pub exchange pub to offer with this trait.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_exchange_pub (
  unsigned int index,
  const struct TALER_ExchangePublicKeyP *exchange_pub);


/**
 * Obtain a exchange public key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index index number of the exchange to obtain.
 * @param[out] exchange_pub set to the offered exchange pub.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_exchange_pub (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_ExchangePublicKeyP **exchange_pub);


/**
 * Obtain location where a command stores a pointer to a process.
 *
 * @param cmd command to extract trait from.
 * @param index which process to pick if @a cmd
 *        has multiple on offer.
 * @param[out] processp set to the address of the pointer to the
 *        process.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_process (const struct TALER_TESTING_Command *cmd,
                                 unsigned int index,
                                 struct GNUNET_OS_Process ***processp);


/**
 * Offer location where a command stores a pointer to a process.
 *
 * @param index offered location index number, in case there are
 *        multiple on offer.
 * @param processp process location to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_process (unsigned int index,
                                  struct GNUNET_OS_Process **processp);


/**
 * Offer coin private key.
 *
 * @param index index number to associate with offered coin priv.
 * @param coin_priv coin private key to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_coin_priv (
  unsigned int index,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv);

/**
 * Obtain a coin private key from a @a cmd.
 *
 * @param cmd command to extract trait from.
 * @param index index of the coin priv to obtain.
 * @param[out] coin_priv set to the private key of the coin.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_coin_priv (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_CoinSpendPrivateKeyP **coin_priv);


/**
 * Offer blinding key.
 *
 * @param index index number to associate to the offered key.
 * @param blinding_key blinding key to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_blinding_key (
  unsigned int index,
  const struct TALER_DenominationBlindingKeyP *blinding_key);


/**
 * Obtain a blinding key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which coin to pick if @a cmd has multiple on offer.
 * @param[out] blinding_key set to the offered blinding key.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_blinding_key (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_DenominationBlindingKeyP **blinding_key);


/**
 * Make a trait for a denomination public key.
 *
 * @param index index number to associate to the offered denom pub.
 * @param denom_pub denom pub to offer with this trait.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_denom_pub (
  unsigned int index,
  const struct TALER_EXCHANGE_DenomPublicKey *dpk);


/**
 * Obtain a denomination public key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index index number of the denom to obtain.
 * @param[out] denom_pub set to the offered denom pub.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_denom_pub (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_EXCHANGE_DenomPublicKey **dpk);


/**
 * Obtain a denomination signature from a @a cmd.
 *
 * @param cmd command to extract the denom sig from.
 * @param index index number associated with the denom sig.
 * @param[out] denom_sig set to the offered signature.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_denom_sig (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_DenominationSignature **dpk);


/**
 * Offer denom sig.
 *
 * @param index index number to associate to the signature on
 *        offer.
 * @param denom_sig the denom sig on offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_denom_sig (
  unsigned int index,
  const struct TALER_DenominationSignature *sig);


/**
 * Offer number trait, 32-bit version.
 *
 * @param index the number's index number.
 * @param n number to offer.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_uint32 (unsigned int index,
                                 const uint32_t *n);


/**
 * Obtain a "number" value from @a cmd, 32-bit version.
 *
 * @param cmd command to extract the number from.
 * @param index the number's index number.
 * @param[out] n set to the number coming from @a cmd.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_uint32 (const struct TALER_TESTING_Command *cmd,
                                unsigned int index,
                                const uint32_t **n);


/**
 * Offer number trait, 64-bit version.
 *
 * @param index the number's index number.
 * @param n number to offer.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_uint64 (unsigned int index,
                                 const uint64_t *n);


/**
 * Obtain a "number" value from @a cmd, 64-bit version.
 *
 * @param cmd command to extract the number from.
 * @param index the number's index number.
 * @param[out] n set to the number coming from @a cmd.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_uint64 (const struct TALER_TESTING_Command *cmd,
                                unsigned int index,
                                const uint64_t **n);


/**
 * Offer number trait, 64-bit signed version.
 *
 * @param index the number's index number.
 * @param n number to offer.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_int64 (unsigned int index,
                                const int64_t *n);


/**
 * Obtain a "number" value from @a cmd, 64-bit signed version.
 *
 * @param cmd command to extract the number from.
 * @param index the number's index number.
 * @param[out] n set to the number coming from @a cmd.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_int64 (const struct TALER_TESTING_Command *cmd,
                               unsigned int index,
                               const int64_t **n);


/**
 * Offer a number.
 *
 * @param index the number's index number.
 * @param n the number to offer.
 * @return #GNUNET_OK on success.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_uint (unsigned int index,
                               const unsigned int *i);


/**
 * Obtain a number from @a cmd.
 *
 * @param cmd command to extract the number from.
 * @param index the number's index number.
 * @param[out] n set to the number coming from @a cmd.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_uint (const struct TALER_TESTING_Command *cmd,
                              unsigned int index,
                              const unsigned int **n);


/**
 * Opaque handle to fresh coins generated during refresh.
 * Details are internal to the refresh logic.
 */
struct TALER_TESTING_FreshCoinData;


/**
 * Offer a _array_ of fresh coins.
 *
 * @param index which array of fresh coins to offer,
 *        if there are multiple on offer.  Typically passed as
 *        zero.
 * @param fresh_coins the array of fresh coins to offer
 * @return the trait,
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_fresh_coins (
  unsigned int index,
  const struct TALER_TESTING_FreshCoinData *fresh_coins);


/**
 * Get a array of fresh coins.
 *
 * @param cmd command to extract the fresh coin from.
 * @param index which array to pick if @a cmd has multiple
 *        on offer.
 * @param[out] fresh_coins will point to the offered array.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_fresh_coins (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_TESTING_FreshCoinData **fresh_coins);


/**
 * Obtain contract terms from @a cmd.
 *
 * @param cmd command to extract the contract terms from.
 * @param index contract terms index number.
 * @param[out] contract_terms where to write the contract
 *        terms.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_contract_terms (const struct TALER_TESTING_Command *cmd,
                                        unsigned int index,
                                        const json_t **contract_terms);


/**
 * Offer contract terms.
 *
 * @param index contract terms index number.
 * @param contract_terms contract terms to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_contract_terms (unsigned int index,
                                         const json_t *contract_terms);


/**
 * Obtain wire details from @a cmd.
 *
 * @param cmd command to extract the wire details from.
 * @param index index number associate with the wire details
 *        on offer; usually zero, as one command sticks to
 *        one bank account.
 * @param[out] wire_details where to write the wire details.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_wire_details (const struct TALER_TESTING_Command *cmd,
                                      unsigned int index,
                                      const json_t **wire_details);


/**
 * Offer wire details in a trait.
 *
 * @param index index number associate with the wire details
 *        on offer; usually zero, as one command sticks to
 *        one bank account.
 * @param wire_details wire details to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_wire_details (unsigned int index,
                                       const json_t *wire_details);


/**
 * Obtain serialized exchange keys from @a cmd.
 *
 * @param cmd command to extract the keys from.
 * @param index index number associate with the keys on offer.
 * @param[out] keys where to write the serialized keys.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_exchange_keys (const struct TALER_TESTING_Command *cmd,
                                       unsigned int index,
                                       const json_t **keys);


/**
 * Offer serialized keys in a trait.
 *
 * @param index index number associate with the serial keys
 *        on offer.
 * @param keys serialized keys to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_exchange_keys (unsigned int index,
                                        const json_t *keys);


/**
 * Obtain json from @a cmd.
 *
 * @param cmd command to extract the json from.
 * @param index index number associate with the json on offer.
 * @param[out] json where to write the json.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_json (const struct TALER_TESTING_Command *cmd,
                              unsigned int index,
                              const json_t **json);


/**
 * Offer json in a trait.
 *
 * @param index index number associate with the json
 *        on offer.
 * @param json json to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_json (unsigned int index,
                               const json_t *json);


/**
 * Obtain a private key from a "merchant".  Used e.g. to obtain
 * a merchant's priv to sign a /track request.
 *
 * @param cmd command that is offering the key.
 * @param index (typically zero) which key to return if there
 *        are multiple on offer.
 * @param[out] priv set to the key coming from @a cmd.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_merchant_priv (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_MerchantPrivateKeyP **priv);


/**
 * Offer private key of a merchant, typically done when CMD_1 needs it to
 * sign a request.
 *
 * @param index (typically zero) which key to return if there are
 *        multiple on offer.
 * @param priv which object should be offered.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_merchant_priv (
  unsigned int index,
  const struct TALER_MerchantPrivateKeyP *priv);


/**
 * Obtain a public key from a "merchant".  Used e.g. to obtain
 * a merchant's public key to use backend's API.
 *
 * @param cmd command offering the key.
 * @param index (typically zero) which key to return if there
 *        are multiple on offer.
 * @param[out] pub set to the key coming from @a cmd.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_merchant_pub (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_MerchantPublicKeyP **pub);


/**
 * Offer public key.
 *
 * @param index (typically zero) which key to return if there
 *        are multiple on offer.  NOTE: if one key is offered, it
 *        is mandatory to set this as zero.
 * @param pub which object should be returned.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_merchant_pub (
  unsigned int index,
  const struct TALER_MerchantPublicKeyP *pub);


/**
 * Obtain a string from @a cmd.
 *
 * @param cmd command to extract the subject from.
 * @param index index number associated with the transfer
 *        subject to offer.
 * @param[out] s where to write the offered
 *        string.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_string (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const char **s);


/**
 * Offer string subject.
 *
 * @param index index number associated with the transfer
 *        subject being offered.
 * @param s string to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_string (unsigned int index,
                                 const char *s);


/**
 * Obtain a WTID value from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which WTID to pick if @a cmd has multiple on
 *        offer
 * @param[out] wtid set to the wanted WTID.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_wtid (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct TALER_WireTransferIdentifierRawP **wtid);


/**
 * Offer a WTID.
 *
 * @param index associate the WTID with this index.
 * @param wtid pointer to the WTID to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_wtid (
  unsigned int index,
  const struct TALER_WireTransferIdentifierRawP *wtid);


/**
 * Different types of URLs that appear in traits.
 */
enum TALER_TESTING_URL_Type
{
  /**
   * Category of last resort. Should not be used.
   */
  TALER_TESTING_UT_UNDEFINED = 0,

  /**
   * HTTP base URL of an exchange (API), as for example
   * given in wire transfers subjects made by the aggregator.
   */
  TALER_TESTING_UT_EXCHANGE_BASE_URL = 1,

  /**
   * HTTP URL of the exchange's bank account at the bank.
   */
  TALER_TESTING_UT_EXCHANGE_BANK_ACCOUNT_URL = 2
};


/**
 * Offer HTTP url in a trait.
 *
 * @param index which url is to be picked,
 *        in case multiple are offered.
 * @param url the url to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_url (enum TALER_TESTING_URL_Type index,
                              const char *url);


/**
 * Obtain a HTTP url from @a cmd.
 *
 * @param cmd command to extract the url from.
 * @param index which url is to be picked, in case
 *        multiple are offered.
 * @param[out] url where to write the url.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_url (const struct TALER_TESTING_Command *cmd,
                             enum TALER_TESTING_URL_Type index,
                             const char **url);


/**
 * Used as the "index" in payto traits, to identify what kind of
 * payto URL we are returning.
 */
enum TALER_TESTING_PaytoType
{
  /**
   * We don't know / not credit or debit.
   */
  TALER_TESTING_PT_NEUTRAL,
  /**
   * Credit side of a transaction.
   */
  TALER_TESTING_PT_CREDIT,
  /**
   * Debit side of a transaction.
   */
  TALER_TESTING_PT_DEBIT
};


/**
 * Offer a payto uri in a trait.
 *
 * @param pt which url is to be picked,
 *        in case multiple are offered.
 * @param payto_uri the uri to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_payto (enum TALER_TESTING_PaytoType pt,
                                const char *payto_uri);


/**
 * Obtain a PAYTO url from @a cmd.
 *
 * @param cmd command to extract the url from.
 * @param pt which url is to be picked, in case
 *        multiple are offered.
 * @param[out] url where to write the url.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_payto (const struct TALER_TESTING_Command *cmd,
                               enum TALER_TESTING_PaytoType pt,
                               const char **url);


/**
 * Obtain a order id from @a cmd.
 *
 * @param cmd command to extract the order id from.
 * @param index which order id is to be picked, in case
 *        multiple are offered.
 * @param[out] order_id where to write the order id.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_order_id (const struct TALER_TESTING_Command *cmd,
                                  unsigned int index,
                                  const char **order_id);


/**
 * Offer order id in a trait.
 *
 * @param index which order id is to be offered,
 *        in case multiple are offered.
 * @param order_id the order id to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_order_id (unsigned int index,
                                   const char *order_id);


/**
 * Obtain an amount from a @a cmd.
 *
 * @param cmd command to extract the amount from.
 * @param index which amount to pick if @a cmd has multiple
 *        on offer
 * @param[out] amount set to the amount.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_amount_obj (const struct TALER_TESTING_Command *cmd,
                                    unsigned int index,
                                    const struct TALER_Amount **amount);


/**
 * Offer amount.
 *
 * @param index which amount to offer, in case there are
 *        multiple available.
 * @param amount the amount to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_amount_obj (unsigned int index,
                                     const struct TALER_Amount *amount);


/**
 * Offer a command in a trait.
 *
 * @param index always zero.  Commands offering this
 *        kind of traits do not need this index.  For
 *        example, a "meta" CMD returns always the
 *        CMD currently being executed.
 * @param cmd wire details to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_cmd (unsigned int index,
                              const struct TALER_TESTING_Command *cmd);


/**
 * Obtain a command from @a cmd.
 *
 * @param cmd command to extract the command from.
 * @param index always zero.  Commands offering this
 *        kind of traits do not need this index.  For
 *        example, a "meta" CMD returns always the
 *        CMD currently being executed.
 * @param[out] _cmd where to write the wire details.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_cmd (const struct TALER_TESTING_Command *cmd,
                             unsigned int index,
                             struct TALER_TESTING_Command **_cmd);


/**
 * Obtain a uuid from @a cmd.
 *
 * @param cmd command to extract the uuid from.
 * @param index which amount to pick if @a cmd has multiple
 *        on offer
 * @param[out] uuid where to write the uuid.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_uuid (const struct TALER_TESTING_Command *cmd,
                              unsigned int index,
                              struct GNUNET_Uuid **uuid);


/**
 * Offer a uuid in a trait.
 *
 * @param index which uuid to offer, in case there are
 *        multiple available.
 * @param uuid the uuid to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_uuid (unsigned int index,
                               const struct GNUNET_Uuid *uuid);


/**
 * Obtain a claim token from @a cmd.
 *
 * @param cmd command to extract the token from.
 * @param index which amount to pick if @a cmd has multiple
 *        on offer
 * @param[out] ct where to write the token.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_claim_token (const struct TALER_TESTING_Command *cmd,
                                     unsigned int index,
                                     const struct TALER_ClaimTokenP **ct);


/**
 * Offer a claim token in a trait.
 *
 * @param index which token to offer, in case there are
 *        multiple available.
 * @param ct the token to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_claim_token (unsigned int index,
                                      const struct TALER_ClaimTokenP *ct);


/**
 * Obtain a absolute time from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which time stamp to pick if
 *        @a cmd has multiple on offer.
 * @param[out] time set to the wanted WTID.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_absolute_time (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct GNUNET_TIME_Absolute **time);


/**
 * Offer a absolute time.
 *
 * @param index associate the object with this index
 * @param time which object should be returned
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_absolute_time (
  unsigned int index,
  const struct GNUNET_TIME_Absolute *time);


/**
 * Obtain a relative time from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which time to pick if
 *        @a cmd has multiple on offer.
 * @param[out] time set to the wanted WTID.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_relative_time (
  const struct TALER_TESTING_Command *cmd,
  unsigned int index,
  const struct GNUNET_TIME_Relative **time);


/**
 * Offer a relative time.
 *
 * @param index associate the object with this index
 * @param time which object should be returned
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_relative_time (
  unsigned int index,
  const struct GNUNET_TIME_Relative *time);

#endif
