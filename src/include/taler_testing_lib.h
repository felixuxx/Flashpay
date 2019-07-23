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
 * Allocate and return a piece of wire-details.  Combines
 * the @a account_no and the @a bank_url to a
 * @a payto://-URL and adds some salt to create the JSON.
 *
 * @param account_no account number
 * @param bank_url the bank_url
 *
 * @return JSON describing the account, including the
 *         payto://-URL of the account, must be manually decref'd
 */
json_t *
TALER_TESTING_make_wire_details (unsigned long long account_no,
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
 * @param auditor_base_url[out] will be set to the auditor base url,
 *        if the config has any; otherwise it will be set to
 *        NULL.
 * @param exchange_base_url[out] will be set to the exchange base url,
 *        if the config has any; otherwise it will be set to
 *        NULL.
 * @return #GNUNET_OK on success, #GNUNET_NO if test should be
 *         skipped, #GNUNET_SYSERR on test failure
 */
int
TALER_TESTING_prepare_exchange (const char *config_filename,
				char **auditor_base_url,
				char **exchange_base_url);

/**
 * "Canonical" cert_cb used when we are connecting to the
 * Exchange.
 *
 * @param cls closure, typically, the "run" method containing
 *        all the commands to be run, and a closure for it.
 * @param keys the exchange's keys.
 * @param compat protocol compatibility information.
 */
void
TALER_TESTING_cert_cb
  (void *cls,
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
 */
int
TALER_TESTING_url_port_free (const char *url);


/**
 * Prepare launching a fakebank.  Check that the configuration
 * file has the right option, and that the port is avaiable.
 * If everything is OK, return the configured URL of the fakebank.
 *
 * @param config_filename configuration file to use
 * @param config_section which account to use
 *                       (must match x-taler-bank)
 * @return NULL on error, fakebank URL otherwise
 */
char *
TALER_TESTING_prepare_fakebank (const char *config_filename,
                                const char *config_section);


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
   * Instruction pointer.  Tells #interpreter_run() which
   * instruction to run next.  Need (signed) int because
   * it gets -1 when rewinding the interpreter to the first
   * CMD.
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
   * as part of libtalertestingauditor's
   * #TALER_TESTING_AUDITOR_main_wrapper().
   */
  struct TALER_AUDITOR_Handle *auditor;

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
   * @param ret[out] result (could be anything)
   * @param trait name of the trait
   * @param index index number of the object to extract.
   * @return #GNUNET_OK on success
   */
  int
  (*traits)(void *cls,
            const void **ret,
            const char *trait,
            unsigned int index);

};


/**
 * Lookup command by label.
 *
 * @param i interpreter state.
 * @param label label of the command to lookup.
 * @return the command, if it is found, or NULL.
 */
const struct TALER_TESTING_Command *
TALER_TESTING_interpreter_lookup_command
  (struct TALER_TESTING_Interpreter *i,
   const char *label);

/**
 * Obtain main execution context for the main loop.
 *
 * @param is interpreter state.
 * @return CURL execution context.
 */
struct GNUNET_CURL_Context *
TALER_TESTING_interpreter_get_context
  (struct TALER_TESTING_Interpreter *is);

/**
 * Obtain label of the command being now run.
 *
 * @param is interpreter state.
 * @return the label.
 */
const char *
TALER_TESTING_interpreter_get_current_label
  (struct TALER_TESTING_Interpreter *is);



/**
 * Get connection handle to the fakebank.
 *
 * @param is interpreter state.
 * @return the handle.
 */
struct TALER_FAKEBANK_Handle *
TALER_TESTING_interpreter_get_fakebank
  (struct TALER_TESTING_Interpreter *is);

/**
 * Current command is done, run the next one.
 *
 * @param is interpreter state.
 */
void
TALER_TESTING_interpreter_next
  (struct TALER_TESTING_Interpreter *is);

/**
 * Current command failed, clean up and fail the test case.
 *
 * @param is interpreter state.
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
 *
 * @param is interpreter state.
 */
void
TALER_TESTING_wait_for_sigchld
  (struct TALER_TESTING_Interpreter *is);


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
TALER_TESTING_run_with_fakebank
  (struct TALER_TESTING_Interpreter *is,
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
 * @param config_filename configuration filename.
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
                     const char *config_filename,
                     struct GNUNET_OS_Process *exchanged,
                     int exchange_connect);


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
TALER_TESTING_setup_with_exchange_cfg
  (void *cls,
   const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Initialize scheduler loop and curl context for the test case
 * including starting and stopping the exchange using the given
 * configuration file.
 *
 * @param main_cb main method.
 * @param main_cb_cls main method closure.
 * @param config_filename configuration file name.  Is is used
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
TALER_TESTING_setup_with_auditor_and_exchange_cfg
  (void *cls,
   const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Initialize scheduler loop and curl context for the test case
 * including starting and stopping the auditor and exchange using
 * the given configuration file.
 *
 * @param main_cb main method.
 * @param main_cb_cls main method closure.
 * @param config_filename configuration file name.  Is is used
 *        by both this function and the exchange itself.  In the
 *        first case it gives out the exchange port number and
 *        the exchange base URL so as to check whether the port
 *        is available and the exchange responds when requested
 *        at its base URL.
 * @return #GNUNET_OK if no errors occurred.
 */
int
TALER_TESTING_setup_with_auditor_and_exchange
  (TALER_TESTING_Main main_cb,
   void *main_cb_cls,
   const char *config_file);

/* ************** Specific interpreter commands ************ */

/**
 * Create fakebank_transfer command, the subject line will be
 * derived from a randomly created reserve priv.  Note that that
 * reserve priv will then be offered as trait.
 *
 * @param label command label.
 * @param amount amount to transfer.
 * @param bank_url base URL of the bank that implements this
 *        wire transer.  For simplicity, both credit and debit
 *        bank account exist at the same bank.
 * @param debit_account_no which account (expressed as a number)
 *        gives money.
 * @param credit_account_no which account (expressed as a number)
 *        receives money.
 * @param auth_username username identifying the @a
 *        debit_account_no at the bank.
 * @param auth_password password for @a auth_username.
 * @param exchange_url which exchange is involved in this transfer.
 *        This data is used for tracking purposes (FIXME: explain
 *        _how_).
 *
 * @return the command.
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
 * Create "fakebank transfer" CMD, letting the caller specifying
 * the subject line.
 *
 * @param label command label.
 * @param amount amount to transfer.
 * @param bank_url base URL of the bank that implements this
 *        wire transer.  For simplicity, both credit and debit
 *        bank account exist at the same bank.
 * @param debit_account_no which account (expressed as a number)
 *        gives money.
 * @param credit_account_no which account (expressed as a number)
 *        receives money.
 *
 * @param auth_username username identifying the @a
 *        debit_account_no at the bank.
 * @param auth_password password for @a auth_username.
 * @param subject wire transfer's subject line.
 * @param exchange_url which exchange is involved in this transfer.
 *        This data is used for tracking purposes (FIXME: explain
 *        _how_).
 *
 * @return the command.
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
 * Create "fakebank transfer" CMD, letting the caller specify
 * a reference to a command that can offer a reserve private key.
 * This private key will then be used to construct the subject line
 * of the wire transfer.
 *
 * @param label command label.
 * @param amount the amount to transfer.
 * @param bank_url base URL of the bank running the transfer.
 * @param debit_account_no which account (expressed as a number)
 *        gives money.
 * @param credit_account_no which account (expressed as a number)
 *        receives money.
 * @param auth_username username identifying the @a
 *        debit_account_no at the bank.
 * @param auth_password password for @a auth_username.
 * @param ref reference to a command that can offer a reserve
 *        private key.
 * @param exchange_url the exchage involved in the transfer,
 *        tipically receiving the money in order to fuel a reserve.
 *
 * @return the command.
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
 * Create "fakebank transfer" CMD, letting the caller specifying
 * the merchant instance.  This version is useful when a tip
 * reserve should be topped up, in fact the interpreter will need
 * the "tipping instance" in order to get the instance public key
 * and make a wire transfer subject out of it.
 *
 * @param label command label.
 * @param amount amount to transfer.
 * @param bank_url base URL of the bank that implements this
 *        wire transer.  For simplicity, both credit and debit
 *        bank account exist at the same bank.
 * @param debit_account_no which account (expressed as a number)
 *        gives money.
 * @param credit_account_no which account (expressed as a number)
 *        receives money.
 *
 * @param auth_username username identifying the @a
 *        debit_account_no at the bank.
 * @param auth_password password for @a auth_username.
 * @param instance the instance that runs the tipping.  Under this
 *        instance, the configuration file will provide the private
 *        key of the tipping reserve.  This data will then used to
 *        construct the wire transfer subject line.
 * @param exchange_url which exchange is involved in this transfer.
 *        This data is used for tracking purposes (FIXME: explain
 *        _how_).
 * @param config_filename configuration file to use.
 *
 * @return the command.
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
 * Modify a fakebank transfer command to enable retries when the
 * reserve is not yet full or we get other transient errors from
 * the fakebank.
 *
 * @param cmd a fakebank transfer command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer_retry
  (struct TALER_TESTING_Command cmd);


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
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_aggregator (const char *label,
                                   const char *config_filename);

/**
 * Make the "keyup" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 *
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
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_keyup_with_now
  (const char *label,
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
 * @param exchange connection handle to the exchange to test.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_with_now
  (const char *label,
   unsigned int generation,
   unsigned int num_denom_keys,
   struct GNUNET_TIME_Absolute now);


/**
 * Make a "auditor sign" CMD.
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
 * Create a withdraw command, letting the caller specify
 * the desired amount as string.
 *
 * @param label command label.
 * @param amount how much we withdraw.
 * @param expected_response_code which HTTP response code
 *        we expect from the exchange.
 *
 * @return the withdraw command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount
  (const char *label,
   const char *reserve_reference,
   const char *amount,
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
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_denomination
  (const char *label,
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
TALER_TESTING_cmd_withdraw_with_retry
  (struct TALER_TESTING_Command cmd);


/**
 * Create a "wire" command.
 *
 * @param label the command label.
 * @param expected_method which wire-transfer method is expected
 *        to be offered by the exchange.
 * @param expected_fee the fee the exchange should charge.
 * @param expected_response_code the HTTP response the exchange
 *        should return.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_wire (const char *label,
                        const char *expected_method,
                        const char *expected_fee,
                        unsigned int expected_response_code);


/**
 * Create a "reserve status" command.
 *
 * @param label the command label.
 * @param reserve_reference reference to the reserve to check.
 * @param expected_balance expected balance for the reserve.
 * @param expected_response_code expected HTTP response code.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_status (const char *label,
                          const char *reserve_reference,
                          const char *expected_balance,
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
 * @param wire_details wire details associated with the "deposit"
 *        request.
 * @param contract_terms contract terms to be signed over by the
 *        coin.
 * @param refund_deadline refund deadline, zero means 'no refunds'.
 * @param amount how much is going to be deposited.
 * @param expected_response_code expected HTTP response code.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit
  (const char *label,
   const char *coin_reference,
   unsigned int coin_index,
   json_t *wire_details,
   const char *contract_terms,
   struct GNUNET_TIME_Relative refund_deadline,
   const char *amount,
   unsigned int expected_response_code);


/**
 * Modify a deposit command to enable retries when we get transient
 * errors from the exchange.
 *
 * @param cmd a deposit command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_with_retry
  (struct TALER_TESTING_Command cmd);


/**
 * Create a "refresh melt" command.
 *
 * @param label command label.
 * @param amount amount to be melted.
 * @param coin_reference reference to a command
 *        that will provide a coin to refresh.
 * @param expected_response_code expected HTTP code.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_melt
  (const char *label,
   const char *amount,
   const char *coin_reference,
   unsigned int expected_response_code);


/**
 * Create a "refresh melt" CMD that does TWO /refresh/melt
 * requests.  This was needed to test the replay of a valid melt
 * request, see #5312.
 *
 * @param label command label
 * @param amount FIXME not used.
 * @param coin_reference reference to a command that will provide
 *        a coin to refresh
 * @param expected_response_code expected HTTP code
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_melt_double
  (const char *label,
   const char *amount,
   const char *coin_reference,
   unsigned int expected_response_code);


/**
 * Modify a "refresh melt" command to enable retries.
 *
 * @param cmd command
 * @return modified command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_melt_with_retry
  (struct TALER_TESTING_Command cmd);


/**
 * Create a "refresh reveal" command.
 *
 * @param label command label.
 * @param exchange connection to the exchange.
 * @param melt_reference reference to a "refresh melt" command.
 * @param expected_response_code expected HTTP response code.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_reveal
  (const char *label,
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
 * @param exchange connection to the exchange.
 * @param reveal_reference reference to a "refresh reveal" CMD.
 * @param expected_response_code expected HTTP response code
 *
 * @return the "refresh link" command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refresh_link
  (const char *label,
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
TALER_TESTING_cmd_track_transaction
  (const char *label,
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
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transfer_empty
  (const char *label,
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
 * @param expected_amount how much money we expect being moved
 *        with this wire-transfer.
 * @param expected_wire_fee expected wire fee.
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transfer
  (const char *label,
   const char *wtid_reference,
   unsigned int index,
   unsigned int expected_response_code,
   const char *expected_total_amount,
   const char *expected_wire_fee);

/**
 * Make a "bank check" CMD.  It checks whether a
 * particular wire transfer has been made or not.
 *
 * @param label the command label.
 * @param exchange_base_url base url of the exchange involved in
 *        the wire transfer.
 * @param amount the amount expected to be transferred.
 * @param debit_account the account that gave money.
 * @param credit_account the account that received money.
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
TALER_TESTING_cmd_check_bank_transfer_with_ref
  (const char *label,
   const char *deposit_reference);


/**
 * Checks wheter all the wire transfers got "checked"
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
 * @param refund_fee expected refund fee.
 * @param coin_reference reference to a command that can
 *        provide a coin to be refunded.
 * @param refund_transaction_id transaction id to use
 *        in the request.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refund_with_id
  (const char *label,
   unsigned int expected_response_code,
   const char *refund_amount,
   const char *refund_fee,
   const char *deposit_reference,
   uint64_t refund_transaction_id);


/**
 * Create a "refund" command.
 *
 * @param label command label.
 * @param expected_response_code expected HTTP status code.
 * @param refund_amount the amount to ask a refund for.
 * @param refund_fee expected refund fee.
 * @param coin_reference reference to a command that can
 *        provide a coin to be refunded.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refund (const char *label,
                          unsigned int expected_response_code,
                          const char *refund_amount,
                          const char *refund_fee,
                          const char *deposit_reference);


/**
 * Make a "payback" command.
 *
 * @param label the command label
 * @param expected_response_code expected HTTP status code
 * @param coin_reference reference to any command which
 *        offers a coin and reserve private key.  May specify
 *        the index of the coin using "$LABEL#$INDEX" syntax.
 *        Here, $INDEX must be a non-negative number.
 * @param amount denomination to pay back.
 * @param NULL if coin was not refreshed, otherwise label of the melt operation
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_payback (const char *label,
                           unsigned int expected_response_code,
                           const char *coin_reference,
                           const char *amount,
                           const char *melt_reference);


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
 * service addressed by @a url.  It attemps 10 times
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
TALER_TESTING_cmd_check_keys
  (const char *label,
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
 * @param exchange connection handle to the exchange to test.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_pull_all_keys
  (const char *label,
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
 * @param exchange connection handle to the exchange to test.
 * @param last_denom_date date to be set in the "last_denom_issue"
 *        URL parameter of /keys.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_keys_with_last_denom
  (const char *label,
   unsigned int generation,
   unsigned int num_denom_keys,
   struct GNUNET_TIME_Absolute last_denom_date);


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
TALER_TESTING_cmd_batch_next
  (struct TALER_TESTING_Interpreter *is);

/**
 * Obtain what command the batch is at.
 *
 * @return cmd current batch command
 */
struct TALER_TESTING_Command *
TALER_TESTING_cmd_batch_get_current (const struct TALER_TESTING_Command *cmd);

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
 * @param ret[out] where to store the result.
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
 * Offer a reserve private key.
 *
 * @param index reserve priv's index number.
 * @param reserve_priv reserve private key to offer.
 *
 * @return the trait.
 */

struct TALER_TESTING_Trait
TALER_TESTING_make_trait_reserve_priv
  (unsigned int index,
   const struct TALER_ReservePrivateKeyP *reserve_priv);


/**
 * Obtain a reserve private key from a @a cmd.
 *
 * @param cmd command to extract the reserve priv from.
 * @param index reserve priv's index number.
 * @param reserve_priv[out] set to the reserve priv.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_reserve_priv
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct TALER_ReservePrivateKeyP **reserve_priv);


/**
 * Make a trait for a exchange signature.
 *
 * @param index index number to associate to the offered exchange pub.
 * @param exchange_sig exchange signature to offer with this trait.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_exchange_sig
  (unsigned int index,
   const struct TALER_ExchangeSignatureP *exchange_sig);


/**
 * Obtain a exchange signature (online sig) from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index index number of the exchange to obtain.
 * @param exchange_sig[out] set to the offered exchange signature.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_exchange_sig
  (const struct TALER_TESTING_Command *cmd,
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
TALER_TESTING_make_trait_exchange_pub
  (unsigned int index,
   const struct TALER_ExchangePublicKeyP *exchange_pub);


/**
 * Obtain a exchange public key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index index number of the exchange to obtain.
 * @param exchange_pub[out] set to the offered exchange pub.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_exchange_pub
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct TALER_ExchangePublicKeyP **exchange_pub);


/**
 * Obtain location where a command stores a pointer to a process.
 *
 * @param cmd command to extract trait from.
 * @param index which process to pick if @a cmd
 *        has multiple on offer.
 * @param processp[out] set to the address of the pointer to the
 *        process.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_process
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct GNUNET_OS_Process ***processp); // FIXME: why is this a ***!? ** should do!


/**
 * Offer location where a command stores a pointer to a process.
 *
 * @param index offered location index number, in case there are
 *        multiple on offer.
 * @param processp process location to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_process
  (unsigned int index,
   struct GNUNET_OS_Process **processp); // FIXME: why is this a "**"? * should do!


/**
 * Offer coin private key.
 *
 * @param index index number to associate with offered coin priv.
 * @param coin_priv coin private key to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_coin_priv
  (unsigned int index,
   const struct TALER_CoinSpendPrivateKeyP *coin_priv);

/**
 * Obtain a coin private key from a @a cmd.
 *
 * @param cmd command to extract trait from.
 * @param index index of the coin priv to obtain.
 * @param coin_priv[out] set to the private key of the coin.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_coin_priv
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct TALER_CoinSpendPrivateKeyP **coin_priv);


/**
 * Offer blinding key.
 *
 * @param index index number to associate to the offered key.
 * @param blinding_key blinding key to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_blinding_key
  (unsigned int index,
   const struct TALER_DenominationBlindingKeyP *blinding_key);


/**
 * Obtain a blinding key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which coin to pick if @a cmd has multiple on offer.
 * @param blinding_key[out] set to the offered blinding key.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_blinding_key
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct TALER_DenominationBlindingKeyP **blinding_key);


/**
 * Make a trait for a denomination public key.
 *
 * @param index index number to associate to the offered denom pub.
 * @param denom_pub denom pub to offer with this trait.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_denom_pub
  (unsigned int index,
   const struct TALER_EXCHANGE_DenomPublicKey *dpk);


/**
 * Obtain a denomination public key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index index number of the denom to obtain.
 * @param denom_pub[out] set to the offered denom pub.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_denom_pub
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct TALER_EXCHANGE_DenomPublicKey **dpk);


/**
 * Obtain a denomination signature from a @a cmd.
 *
 * @param cmd command to extract the denom sig from.
 * @param index index number associated with the denom sig.
 * @param denom_sig[out] set to the offered signature.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_denom_sig
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct TALER_DenominationSignature **dpk);


/**
 * Offer denom sig.
 *
 * @param index index number to associate to the signature on
 *        offer.
 * @param denom_sig the denom sig on offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_denom_sig
  (unsigned int index,
   const struct TALER_DenominationSignature *sig);


/**
 * Offer number trait, 64-bit version.
 *
 * @param index the number's index number.
 * @param n number to offer.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_uint64
  (unsigned int index,
   const uint64_t *n);


/**
 * Obtain a "number" value from @a cmd, 64-bit version.
 *
 * @param cmd command to extract the number from.
 * @param index the number's index number.
 * @param n[out] set to the number coming from @a cmd.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_uint64
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const uint64_t **n);


/**
 * Offer a number.
 *
 * @param index the number's index number.
 * @param n the number to offer.
 *
 * @return #GNUNET_OK on success.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_uint
  (unsigned int index,
   const unsigned int *i);


/**
 * Obtain a number from @a cmd.
 *
 * @param cmd command to extract the number from.
 * @param index the number's index number.
 * @param n[out] set to the number coming from @a cmd.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_uint
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const unsigned int **n);


/**
 * Information about a fresh coin generated by the refresh
 * operation. FIXME: should go away from here!
 */
struct TALER_TESTING_FreshCoinData
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

  /**
   * The blinding key (needed for payback operations).
   */
  struct TALER_DenominationBlindingKeyP blinding_key;

};


/**
 * Offer a _array_ of fresh coins.
 *
 * @param index which array of fresh coins to offer,
 *        if there are multiple on offer.  Tipically passed as
 *        zero.
 * @param fresh_coins the array of fresh coins to offer
 *
 * @return the trait,
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_fresh_coins
  (unsigned int index,
   struct TALER_TESTING_FreshCoinData *fresh_coins);


/**
 * Get a array of fresh coins.
 *
 * @param cmd command to extract the fresh coin from.
 * @param index which array to pick if @a cmd has multiple
 *        on offer.
 * @param fresh_coins[out] will point to the offered array.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_fresh_coins
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct TALER_TESTING_FreshCoinData **fresh_coins);


/**
 * Obtain contract terms from @a cmd.
 *
 * @param cmd command to extract the contract terms from.
 * @param index contract terms index number.
 * @param contract_terms[out] where to write the contract
 *        terms.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_contract_terms
  (const struct TALER_TESTING_Command *cmd,
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
TALER_TESTING_make_trait_contract_terms
  (unsigned int index,
   const json_t *contract_terms);


/**
 * Obtain wire details from @a cmd.
 *
 * @param cmd command to extract the wire details from.
 * @param index index number associate with the wire details
 *        on offer; usually zero, as one command sticks to
 *        one bank account.
 * @param wire_details[out] where to write the wire details.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_wire_details
  (const struct TALER_TESTING_Command *cmd,
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
TALER_TESTING_make_trait_wire_details
  (unsigned int index,
   const json_t *wire_details);


/**
 * Obtain serialized exchange keys from @a cmd.
 *
 * @param cmd command to extract the keys from.
 * @param index index number associate with the keys on offer.
 * @param keys[out] where to write the serialized keys.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_exchange_keys
  (const struct TALER_TESTING_Command *cmd,
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
TALER_TESTING_make_trait_exchange_keys
  (unsigned int index,
   const json_t *keys);


/**
 * Obtain a private key from a "peer".  Used e.g. to obtain
 * a merchant's priv to sign a /track request.
 *
 * @param cmd command that is offering the key.
 * @param index (tipically zero) which key to return if there
 *        are multiple on offer.
 * @param priv[out] set to the key coming from @a cmd.
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_peer_key
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct GNUNET_CRYPTO_EddsaPrivateKey **priv);
// FIXME: private get_trait_merchant_priv instead, rather have
// more traits with precise types than this!


/**
 * Offer private key, typically done when CMD_1 needs it to
 * sign a request.
 *
 * @param index (tipically zero) which key to return if there are
 *        multiple on offer.
 * @param priv which object should be offered.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_peer_key
  (unsigned int index,
   const struct GNUNET_CRYPTO_EddsaPrivateKey *priv);
// FIXME: private get_trait_merchant_priv instead, rather have
// more traits with precise types than this!


/**
 * Obtain a public key from a "peer".  Used e.g. to obtain
 * a merchant's public key to use backend's API.
 *
 * @param cmd command offering the key.
 * @param index (tipically zero) which key to return if there
 *        are multiple on offer.
 * @param pub[out] set to the key coming from @a cmd.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_peer_key_pub
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const struct GNUNET_CRYPTO_EddsaPublicKey **pub);


/**
 * Offer public key.
 *
 * @param index (tipically zero) which key to return if there
 *        are multiple on offer.  NOTE: if one key is offered, it
 *        is mandatory to set this as zero.
 * @param pub which object should be returned.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_peer_key_pub
  (unsigned int index,
   struct GNUNET_CRYPTO_EddsaPublicKey *pub);


/**
 * Obtain a transfer subject from @a cmd.
 *
 * @param cmd command to extract the subject from.
 * @param index index number associated with the transfer
 *        subject to offer.
 * @param transfer_subject[out] where to write the offered
 *        transfer subject.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_transfer_subject
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **transfer_subject);


/**
 * Offer transfer subject.
 *
 * @param index index number associated with the transfer
 *        subject being offered.
 * @param transfer_subject transfer subject to offer.
 * @return the trait.
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
   const struct TALER_WireTransferIdentifierRawP **wtid);


/**
 * Offer a WTID.
 *
 * @param index associate the WTID with this index.
 * @param wtid pointer to the WTID to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_wtid
  (unsigned int index,
   const struct TALER_WireTransferIdentifierRawP *wtid);


/**
 * Offer amount in a trait.
 *
 * @param index which amount is to be offered,
 *        in case multiple are offered.
 * @param amount the amount to offer.
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_amount
  (unsigned int index,
   const char *amount);


/**
 * Obtain an amount from @a cmd.
 *
 * @param cmd command to extract the amount from.
 * @param index which amount is to be picked, in case
 *        multiple are offered.
 * @param amount[out] where to write the wire details.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_amount
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **amount);


/**
 * Offer url in a trait.
 *
 * @param index which url is to be picked,
 *        in case multiple are offered.
 * @param url the url to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_url
  (unsigned int index,
   const char *url);


/**
 * Obtain a url from @a cmd.
 *
 * @param cmd command to extract the url from.
 * @param index which url is to be picked, in case
 *        multiple are offered.
 * @param url[out] where to write the url.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_url
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **url);


/**
 * Obtain a order id from @a cmd.
 *
 * @param cmd command to extract the order id from.
 * @param index which order id is to be picked, in case
 *        multiple are offered.
 * @param order_id[out] where to write the order id.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_order_id
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **order_id);


/**
 * Offer order id in a trait.
 *
 * @param index which order id is to be offered,
 *        in case multiple are offered.
 * @param order_id the order id to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_order_id
  (unsigned int index,
   const char *order_id);


/**
 * Obtain an amount from a @a cmd.
 *
 * @param cmd command to extract the amount from.
 * @param index which amount to pick if @a cmd has multiple
 *        on offer
 * @param amount[out] set to the amount.
 *
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_amount_obj
  (const struct TALER_TESTING_Command *cmd,
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
TALER_TESTING_make_trait_amount_obj
  (unsigned int index,
   const struct TALER_Amount *amount);


/**
 * Offer a "reject" CMD reference.
 *
 * @param index which reference is to be offered,
 *        in case multiple are offered.
 * @param rejected_reference the reference to offer.
 *
 * @return the trait.
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_rejected
  (unsigned int index,
   const char *rejected);


/**
 * Obtain the reference to a "reject" CMD.  Usually offered
 * by _rejected_ bank transfers.
 *
 * @param cmd command to extract the reference from.
 * @param index which reference is to be picked, in case
 *        multiple are offered.
 * @param rejected_reference[out] where to write the reference.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_rejected
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   const char **rejected_reference);


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
TALER_TESTING_make_trait_cmd
  (unsigned int index,
   const struct TALER_TESTING_Command *cmd);


/**
 * Obtain a command from @a cmd.
 *
 * @param cmd command to extract the command from.
 * @param index always zero.  Commands offering this
 *        kind of traits do not need this index.  For
 *        example, a "meta" CMD returns always the
 *        CMD currently being executed.
 * @param _cmd[out] where to write the wire details.
 *
 * @return #GNUNET_OK on success.
 */
int
TALER_TESTING_get_trait_cmd
  (const struct TALER_TESTING_Command *cmd,
   unsigned int index,
   struct TALER_TESTING_Command **_cmd);


/**
 * Obtain a absolute time from @a cmd.
 *
 * @param cmd command to extract trait from
 * @param index which time stamp to pick if
 *        @a cmd has multiple on offer.
 * @param time[out] set to the wanted WTID.
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_absolute_time
  (const struct TALER_TESTING_Command *cmd,
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
TALER_TESTING_make_trait_absolute_time
  (unsigned int index,
   const struct GNUNET_TIME_Absolute *time);

#endif
