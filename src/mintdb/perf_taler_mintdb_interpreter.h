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
 * @file mintdb/perf_taler_mintdb_interpreter.h
 * @brief Library for performance analysis of the Taler database
 * @author Nicolas Fournier
 *
 * This library contains functions and macro alowing Taler performance analysis 
 * to be written with ease. 
 * To do so, create a #PERF_TALER_MINTDB_Cmd array and fill it with the commands
 * to execute in chronological order. Some command have an exposed variable wich
 * can be reused in other commands.
 * Macros are available to make the use much easier so feel free to use them 
 * to initialize your own command array.
 */

#ifndef __PERF_TALER_MINTDB_INTERPRETER_H__
#define __PERF_TALER_MINTDB_INTERPRETER_H__

#include <sys/time.h>
#include "taler_mintdb_plugin.h"


#define PERF_TALER_MINTDB_NB_DENOMINATION_INIT  10
#define PERF_TALER_MINTDB_NB_DENOMINATION_SAVE  10

#define PERF_TALER_MINTDB_NB_RESERVE_INIT   100
#define PERF_TALER_MINTDB_NB_RESERVE_SAVE   10

#define PERF_TALER_MINTDB_NB_DEPOSIT_INIT   100
#define PERF_TALER_MINTDB_NB_DEPOSIT_SAVE   10

#define PERF_TALER_MINTDB_NB_WITHDRAW_INIT  100
#define PERF_TALER_MINTDB_NB_WITHDRAW_SAVE  10


/**
 * Marks the end of the command chain
 *
 * @param _label The label of the command
 */
#define PERF_TALER_MINTDB_INIT_CMD_END(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_END, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE \
}


/**
 * Prints @ _label to stdout
 * 
 * @param _label The label of the command,
 *  will be logged each time the command runs
 */
#define PERF_TALER_MINTDB_INIT_CMD_DEBUG(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_DEBUG, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE \
}

/**
 * The begining of a loop
 * 
 * @param _label the label of the loop
 * @param _iter the number of iterations of the loop
 */
#define PERF_TALER_MINTDB_INIT_CMD_LOOP(_label, _iter) \
{ \
  .command = PERF_TALER_MINTDB_CMD_LOOP , \
  .label = _label , \
  .exposed.type = PERF_TALER_MINTDB_NONE , \
  .details.loop = { \
    .max_iterations = _iter , \
    .curr_iteration = 0 } \
}

/**
 * Marks the end of the loop @_label_loop
 * 
 * @param _label the label of the command
 * @param _label_loop the label of the loop closed by this command 
 */
#define PERF_TALER_MINTDB_INIT_CMD_END_LOOP(_label, _label_loop) \
{\
  .command = PERF_TALER_MINTDB_CMD_END_LOOP , \
  .label = _label , \
  .exposed.type = PERF_TALER_MINTDB_NONE , \
  .details.end_loop.label_loop = _label_loop \
}

/**
 * Saves the time of execution to use for logging with Gauger
 *
 * @param _label the label of the command
 */
#define PERF_TALER_MINTDB_INIT_CMD_GET_TIME(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GET_TIME, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE \
}

/**
 * Commits the duration between @a _label_start and @a _label_stop
 * to Gauger with @a _description explaining what was measured.
 *
 * @param _label the label of this command
 * @param _label_start label of the start of the measurment
 * @param _label_stop label of the end of the measurment
 * @param _description description of the measure displayed in Gauger
 * @param _unit the unit of the data measured, typicly something/sec
 * @param _divide number of measurments in the interval 
 */
#define PERF_TALER_MINTDB_INIT_CMD_GAUGER(_label, _label_start, _label_stop, _category, _description, _unit, _divide) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GAUGER, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
  .details.gauger = { \
    .label_start = _label_start, \
    .label_stop = _label_stop, \
    .category = _category, \
    .description = _description, \
    .unit = _unit, \
    .divide = _divide, \
  } \
}

/**
 * Initiate a database transaction
 * 
 * @param _label the label of the command
 */
#define PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_START_TRANSACTION, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
}

/**
 * Commits a database transaction
 * 
 * @param _label the label of the command
 */
#define PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_COMMIT_TRANSACTION, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
}

/**
 * Abort the current transaction
 *
 * @param _label the label of the command
 */
#define PERF_TALER_MINTDB_INIT_CMD_ABORT_TRANSACTION(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_ABORT_TRANSACTION, \
  .label = _label,

/**
 * Saves randomly selected items from @a _label_save 
 * Saved items can latter be access using #PERF_TALER_MINTDB_CMD_LOAD_ARRAY
 * 
 * @param _label the label of the command, used by other commands to reference it
 * @param _label_loop the label of the loop the array iterates over
 * @param _label_save the label of the command which outout is saved by this command
 * @param _nb_saved the total number of items to be saved
 */
#define PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY(_label, _label_loop, _label_save, _nb_saved) \
{ \
  .command = PERF_TALER_MINTDB_CMD_SAVE_ARRAY, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
  .details.save_array = { \
    .label_loop = _label_loop, \
    .label_save = _label_save, \
    .nb_saved = _nb_saved, \
  } \
}

/**
 * Loads data from a #PERF_TALER_MINTDB_CMD_SAVE_ARRAY to allow other
 * commands to access it
 * 
 * @param _label the label of this command, referenced by commands to access it's outpout
 * @param _label_loop the label of the loop to iterate over
 * @param _label_save the label of the #PERF_TALER_MINTDB_CMD_SAVE_ARRAY providing data
 */
#define PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY(_label, _label_loop, _label_save) \
{ \
  .command = PERF_TALER_MINTDB_CMD_LOAD_ARRAY, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
  .details.load_array = { \
    .label_loop = _label_loop, \
    .label_save = _label_save \
  } \
}

/**
 * Inserts informations about a denomination key in the database
 * Exposes a #PERF_TALER_MINTDB_DENOMINATION_INFO to be used by other commands
 * @exposed #PERF_TALER_MINTDB_DENOMINATION_INFO
 * 
 * @param _label the label of this command
 */
#define PERF_TALER_MINTDB_INIT_CMD_INSERT_DENOMINATION(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_INSERT_DENOMINATION, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_DENOMINATION_INFO, \
}

/**
 * Polls the database about informations regarding a specific denomination key
 * 
 * @param _label the label of this command
 * @param _label_denom the label of the command providing information about the denomination key
 */
#define PERF_TALER_MINTDB_INIT_CMD_GET_DENOMINATION(_label, _label_denom) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GET_DENOMINATION, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
  .details.get_denomination.label_denom = _label_denom, \
}

/**
 * Creates a new reserve in the database containing 1000 Euros 
 * Exposes a #PERF_TALER_MINTDB_RESERVE
 * 
 * @exposed #PERF_TALER_MINTDB_RESERVE
 * 
 * @param _label the name of this command
 */
#define PERF_TALER_MINTDB_INIT_CMD_INSERT_RESERVE(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_INSERT_RESERVE, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_RESERVE \
}


/**
 * Polls the database for a secific reserve's details
 * 
 * @param _label the label of this command
 * @param _label_reserve the reserve to poll
 */
#define PERF_TALER_MINTDB_INIT_CMD_GET_RESERVE(_label, _label_reserve) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GET_RESERVE, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
  .details.get_reserve.label_reserve = _label_reserve \
}


/**
 * Polls the database for the history of a reserve
 *
 * @param _label the label of the command
 * @param _label_reserve the reserve to examine
 */
#define PERF_TALER_MINTDB_INIT_CMD_GET_RESERVE_HISTORY(_label, _label_reserve) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GET_RESERVE_HISTORY, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
  .details.get_reserve_history.label_reserve = _label_reserve \
}


/**
 * Insert a deposit into the database
 *
 * @exposes #PERF_TALER_MINTDB_DEPOSIT
 *
 * @param _label the label of this command
 * @param _label_coin the coin used to pay
 */
#define PERF_TALER_MINTDB_INIT_CMD_INSERT_DEPOSIT(_label, _label_coin) \
{ \
  .command = PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT,\
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_DEPOSIT, \
  .details.insert_deposit.label_coin = _label_coin, \
}


/**
 * Check if a deposit is in the database
 *
 * @param _label the label of this command
 * @param _label_deposit the deposit to use
 */
#define PERF_TALER_MINTDB_INIT_CMD_GET_DEPOSIT(_label, _label_deposit) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GET_DEPOSIT, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
  .details.get_deposit.label_deposit = _label_deposit \
}


/**
 * Access the transactioj history of a coin
 *
 * @param _label the label of the command
 * @param _label_coin the coin which history is checked
 */
#define PERF_TALER_MINTDB_INIT_CMD_GET_COIN_TRANSACTION(_label, _label_coin) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GET_COIN_TRANSACTION, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
  .details.get_coin_trancaction.label_coin = _label_coin \
}


/**
 * Inserts informations about a withdrawal in the database
 * 
 * @exposes #PERF_TALER_MINTDB_COIN
 *
 * @param _label the label of this command
 * @param _label_dki denomination key used to sign the coin
 * @param _label_reserve reserve used to emmit the coin
 */
#define PERF_TALER_MINTDB_INIT_CMD_INSERT_WITHDRAW(_label, _label_dki, _label_reserve) \
{ \
  .command = PERF_TALER_MINTDB_CMD_INSERT_WITHDRAW, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_COIN, \
  .details.insert_withdraw = {\
    .label_dki = _label_dki, \
    .label_reserve = _label_reserve, \
  } \
}


/**
 * Polls the database about informations regarding a specific withdrawal
 * 
 * @param _label the label of this command
 * @param _label_coin the coin to check
 */
#define PERF_TALER_MINTDB_INIT_CMD_GET_WITHDRAW(_label, _label_coin) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GET_WITHDRAW, \
  .label = _label, \
  .exposed.type = PERF_TALER_MINTDB_NONE, \
  .details.get_withdraw.label_coin = _label_coin, \
}


/**
 * The /withdraw/sign api call
 * 
 * Exposes #PERF_TALER_MINTDB_COIN
 *
 * @param _label the label of this command
 * @param _label_dki the denomination of the created coin
 * @param _label_reserve the reserve used to provide currency
 */
#define PERF_TALER_MINTDB_INIT_CMD_WITHDRAW_SIGN(_label, _label_dki, _label_reserve) \
  PERF_TALER_MINTDB_INIT_CMD_GET_RESERVE_HISTORY(_label "reserve_history", \
                                                 _label_reserve), \
  PERF_TALER_MINTDB_INIT_CMD_INSERT_WITHDRAW(_label "insert withdraw", \
                                             _label_dki, \
                                             _label_reserve),
  

/**
 * The /deposit api call
 * 
 * @param _label the label of the command
 * @param _label_coin the coin used for the deposit
 */
#define PERF_TALER_MINTDB_INIT_CMD_deposit(_label, _label_coin) \
  PERF_TALER_MINTDB_INIT_CMD_GET_COIN_TRANSACTION (_label "coin history", \
                                                   _label_coin), \
  PERF_TALER_MINTDB_INIT_CMD_INSERT_DEPOSIT (_label "deposit", \
                                             _label_coin),


/**
 * The type of data stored in #PERF_TALER_MINTDB_Memory
 */
enum PERF_TALER_MINTDB_Type
{
  PERF_TALER_MINTDB_NONE,
  PERF_TALER_MINTDB_TIME,
  PERF_TALER_MINTDB_DEPOSIT,
  PERF_TALER_MINTDB_COIN,
  PERF_TALER_MINTDB_RESERVE,
  PERF_TALER_MINTDB_DENOMINATION_INFO,
  PERF_TALER_MINTDB_REFRESH_HASH
};


/**
 * Structure used to handle several data type
 */
struct PERF_TALER_MINTDB_Data
{
  enum PERF_TALER_MINTDB_Type type;

  /**
   * Storage for a variety of data type
   * The data saved should match #type
   */
  union PERF_TALER_MINTDB_Memory
  {
    /** #PERF_TALER_MINTDB_TIME */
    struct GNUNET_TIME_Absolute *time;
    /** #PERF_TALER_MINTDB_DEPOSIT */
    struct TALER_MINTDB_Deposit *deposit;
    /** #PERF_TALER_MINTDB_COIN */ 
    struct PERF_TALER_MINTDB_Coin *coin;
    /** #PERF_TALER_MINTDB_RESERVE */
    struct PERF_TALER_MINTDB_Reserve *reserve;
    /** #PERF_TALER_MINTDB_DENOMINATION_INFO */
    struct TALER_MINTDB_DenominationKeyIssueInformation *dki;
    /** #PERF_TALER_MINTDB_REFRESH_HASH */
    struct GNUNET_HashCode session_hash;
  } data;
};


/**
 * Name of the command
 */
enum PERF_TALER_MINTDB_CMD_Name
{
  /**
   * All comand chain must hace this as their last command
   */
  PERF_TALER_MINTDB_CMD_END,

  /**
   * Prints it's label
   */
  PERF_TALER_MINTDB_CMD_DEBUG,

  /** 
   * Define the start of al command chain loop
   */ 
  PERF_TALER_MINTDB_CMD_LOOP,

  /**
   * Define the end of a command chain loop
   */
  PERF_TALER_MINTDB_CMD_END_LOOP,

  /**
   * Save the time at which the command was executed
   */
  PERF_TALER_MINTDB_CMD_GET_TIME,

  /**
   * Upload performance to Gauger
   */
  PERF_TALER_MINTDB_CMD_GAUGER,

  /**
   * Start a new session
   */
  PERF_TALER_MINTDB_CMD_NEW_SESSION,

  /**
   * Start a database transaction
   */
  PERF_TALER_MINTDB_CMD_START_TRANSACTION,

  /**
   * End a database transaction
   */
  PERF_TALER_MINTDB_CMD_COMMIT_TRANSACTION,

  /**
   * Abort a transaction started with #PERF_TALER_MINTDB_CMD_START_TRANSACTION
   */
  PERF_TALER_MINTDB_CMD_ABORT_TRANSACTION,

  /**
   * Saves random deposits from a loop
   */
  PERF_TALER_MINTDB_CMD_SAVE_ARRAY,

  /**
   * Load items saved earlier in a #PERF_TALER_MINTDB_CMD_SAVE_ARRAY
   * The items are loaded in a random order, but all of them will be loaded
   */
  PERF_TALER_MINTDB_CMD_LOAD_ARRAY,

  /**
   * Loads a random item from a #PERF_TALER_MINTDB_CMD_SAVE_ARRAY
   * A random item is loaded each time the command is run
   */
  PERF_TALER_MINTDB_CMD_LOAD_RANDOM,

  /**
   * Insert a deposit into the database
   */
  PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT,

  /**
   * Check if a deposit is in the database
   */
  PERF_TALER_MINTDB_CMD_GET_DEPOSIT,

  /**
   * Insert currency in a reserve / Create a reserve
   */
  PERF_TALER_MINTDB_CMD_INSERT_RESERVE,

  /**
   * Get Informations about a reserve
   */
  PERF_TALER_MINTDB_CMD_GET_RESERVE,

  /**
   * Get the history of a reserve
   */
  PERF_TALER_MINTDB_CMD_GET_RESERVE_HISTORY,

  /**
   * Insert informations about a withdrawal in the database
   */
  PERF_TALER_MINTDB_CMD_INSERT_WITHDRAW,

  /**
   * Pulls informations about a withdrawal from the database
   */
  PERF_TALER_MINTDB_CMD_GET_WITHDRAW,

  /**
   * Insert informations about a denomination key in the database
   */
  PERF_TALER_MINTDB_CMD_INSERT_DENOMINATION,

  /**
   * Polls the database for informations about a specific denomination key
   */
  PERF_TALER_MINTDB_CMD_GET_DENOMINATION,

  /**
   * Get the list of all transactions the coin has been in
   */
  PERF_TALER_MINTDB_CMD_GET_COIN_TRANSACTION,

  /**
   * Create a refresh session
   */
  PERF_TALER_MINTDB_CMD_CREATE_REFRESH_SESSION,

  /**
   * Get a refresh session informations
   */
  PERF_TALER_MINTDB_CMD_GET_REFRESH_SESSION,

  /**
   * Insert a refresh melt
   */
  PERF_TALER_MINTDB_CMD_INSERT_REFRESH_MELT,

  /**
   * Get informations about a refresh melt operation
   */
  PERF_TALER_MINTDB_CMD_GET_REFRESH_MELT,

  /**
   * Insert a melt refresh order
   */
  PERF_TALER_MINTDB_CMD_INSERT_REFRESH_ORDER,

  /**
   * Get informations about a refresh order
   */
  PERF_TALER_MINTDB_CMD_GET_REFRESH_ORDER,

  /**
   * Insert refresh commit coin
   */
  PERF_TALER_MINTDB_CMD_INSERT_REFRESH_COMMIT_COIN,

  /**
   * Get refresh commit coin
   */
  PERF_TALER_MINTDB_CMD_GET_REFRESH_COMMIT_COIN,

  /**
   * Insert refresh commit link
   */
  PERF_TALER_MINTDB_CMD_INSERT_REFRESH_COMMIT_LINK,

  /**
   * Get refresh commit link
   */
  PERF_TALER_MINTDB_CMD_GET_REFRESH_COMMIT_LINK,

  /**
   * Get information avout the melt commit
   */
  PERF_TALER_MINTDB_CMD_GET_MELT_COMMITMENT,

  /**
   * Insert a new coin into the database after a melt operation
   */
  PERF_TALER_MINTDB_CMD_INSERT_REFRESH_OUT,

  /**
   * Get the link data list of a coin
   */
  PERF_TALER_MINTDB_CMD_GET_LINK_DATA_LIST,

  /**
   * Get the shared secret and the transfere public key
   */
  PERF_TALER_MINTDB_CMD_GET_TRANSFER

};


/**
 * Contains extra data required for any command
 */
union PERF_TALER_MINTDB_CMD_Details
{
  /**
   * Extra data requiered for the #PERF_TALER_MINTDB_CMD_LOOP command
   */
  struct PERF_TALER_MINTDB_CMD_loopDetails
  {
    /**
     * Maximum number of iteration in the loop 
     */
    const unsigned int max_iterations;
    /**
     * The current iteration of the loop
     */
    unsigned int curr_iteration;
  } loop;


  /**
   * Extra data requiered by the #PERF_TALER_MINTDB_CMD_END_LOOP command
   */
  struct PERF_TALER_MINTDB_CMD_endLoopDetails
  {
    /**
     * Label of the loop closed by the command
     */
    const char *label_loop;
  } end_loop;


  /**
   * Details about the #PERF_TALER_MINTDB_CMD_GAUGER  command
   */
  struct PERF_TALER_MINTDB_CMD_gaugerDetails
  {
    /**
     * Label of the starting timestamp
     */
    const char *label_start;

    /**
     * Label of the ending timestamp
     */
    const char *label_stop;

    /**
     * The category of the measurment
     */
    const char *category;

    /**
     * Description of the metric, used in Gauger
     */
    const char *description;

    /**
     * The name of the metric beeing used
     */
    const char *unit;

    /**
     * Constant the result needs to be divided by
     * to get the result per unit
     */
    float divide;
  } gauger;


  /**
   * Contains extra data requiered by the #PERF_TALER_MINTDB_CMD_SAVE_ARRAY command
   */
  struct PERF_TALER_MINTDB_CMD_saveArrayDetails
  {
    /**
     * Number of items to save
     */
    unsigned int nb_saved;
    /**
     * Number of items already saved
     */
    unsigned int index;
    /**
     * Label of the loop it is attached to
     */
    const char *label_loop;
    /**
     * Label of the command exposing the item
     */
    const char *label_save;
    /**
     * Array of data saved
     */
    struct PERF_TALER_MINTDB_Data *data_saved;
  } save_array;


  /**
   * Extra data required for the #PERF_TALER_MINTDB_CMD_LOAD_ARRAY command
   */
  struct PERF_TALER_MINTDB_CMD_loadArrayDetails
  {
    /**
     * The loop in which the command is located
     */
    const char *label_loop;

    /**
     * Label of the command where the items were saved
     */
    const char *label_save;

    /**
     * A permutation array used to randomize the order the items are loaded in
     */
    unsigned int *permutation;
  } load_array;


  /**
   * Contains data for the #PERF_TALER_MINTDB_CMD_LOAD_RANDOM command
   */
  struct PERF_TALER_MINTDB_CMD_loadRandomDetails
  {
    /**
     * The label of the #PERF_TALER_MINTDB_CMD_SAVE_ARRAY the items will be extracted from
     */
    const char *label_save;
  } load_random;

  /**
   * Data used by the #PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT command 
   */
  struct PERF_TALER_MINTDB_CMD_insertDepositDetails
  {
    /**
     * Label of the source where the reserve used to create the coin is
     */
    const char *label_coin;
  } insert_deposit;


  /**
   * Extra data requiered for the #PERF_TALER_MINTDB_CMD_GET_DEPOSIT command
   */
  struct PERF_TALER_MINTDB_CMD_getDepositDetails
  {
    /**
     * The label of the source of the deposit to check
     */
    const char *label_deposit;
  } get_deposit;


  /**
   * Extra data requiered for the #PERF_TALER_MINTDB_CMD_GET_RESERVE command
   */
  struct PERF_TALER_MINTDB_CMD_getReserveDetails
  {
    /**
     * The label of the source of the reserve to check
     */
    const char *label_reserve;
  } get_reserve;


  /**
   * Extra data requiered for the #PERF_TALER_MINTDB_CMD_GET_RESERVE command
   */
  struct PERF_TALER_MINTDB_CMD_getReserveHistoryDetails
  {
    /**
     * The label of the source of the reserve to check
     */
    const char *label_reserve;
  } get_reserve_history;


  /**
   * Extra data requiered by the #PERF_TALER_MINTDB_CMD_GET_DENOMINATION command
   */
  struct PERF_TALER_MINTDB_CMD_getDenominationDetails
  {
    /**
     * The label of the source of the denomination to check
     */
    const char *label_denom;
  } get_denomination;


  /**
   * Extra data related to the #PERF_TALER_MINTDB_CMD_GET_WITHDRAW command
   */
  struct PERF_TALER_MINTDB_CMD_insertWithdrawDetails
  {
    /**
     * label of the denomination key used to sign the coin
     */
    const char *label_dki;

    /**
     * label of the reserve the money to mint the coin comes from
     */
    const char *label_reserve;
  } insert_withdraw;

  /**
   * data requiered for the #PERF_TALER_MINTDB_CMD_GET_WITHDRAW
   */
  struct PERF_TALER_MINTDB_CMD_getWithdraw
  {
    /**
     * label of the source for the coin information
     */
    const char *label_coin;
  } get_withdraw;

  /**
   * Data requiered for the #PERF_TALER_MINTDB_CMD_GET_COIN_TRANSACTION command
   */ 
  struct PERF_TALER_MINTDB_CMD_getCoinTransactionDetails
  {
    /**
     * The coin which history is checked
     */
    const char *label_coin;
  } get_coin_transaction;

  /**
   * Data requiered for the #PERF_TALER_MINTDB_CMD_GET_REFRESH_SESSION command
   */
  struct PERF_TALER_MINTDB_CMD_getRefreshSessionDetails
  {
    /**
     * label of the source of the hash of the session
     */
    const char *label_hash;
  } get_refresh_session;

  /**
   * Data requiered for the #PERF_TALER_MINTDB_CMD_INSERT_REFRESH_MELT command
   */
  struct PERF_TALER_MINTDB_CMD_insertRefreshMeltDetails
  {
    /**
     * The label of the hash of the refresh session
     */
    const char *label_hash;

    /**
     * The label of the coin to melt
     */
    const char *label_coin;
  } insert_refresh_melt;

  /**
   * Data requiered for the #PERF_TALER_MINTDB_CMD_GET_REFRESH_MELT command
   */
  struct PERF_TALER_MINTDB_CMD_getRefreshMeltDetails
  {
    /**
     * The label of the hash of the session
     */
    const char *label_hash;
  } get_refresh_melt;

  /**
   * Data requiered for the #PERF_TALER_MINTDB_CMD_INSERT_REFRESH_ORDER command
   */
  struct PERF_TALER_MINTDB_CMD_insertRefreshOrderDetails
  {
   /**
    * The refresh session hash
    */
   const char *label_hash; 

   /**
    * The new coin denomination
    */
   const char *label_denom;
  } insert_refresh_order;

  /**
   * Data requiered for the #PERF_TALER_MINTDB_CMD_GET_REFRESH_ORDER command
   */
  struct PERF_TALER_MINTDB_CMD_getRefreshOrderDetails
  {
    /**
     * The session hash
     */
    const char *label_hash;

  } get_refresh_order;

  /**
   * Data requiered for the #PERF_TALER_MINTDB_CMD_INSERT_REFRESH_COMMIT_COIN command
   */
  struct PERF_TALER_MINTDB_CMD_insertRefreshCommitCoinDetails
  {
    /**
     * The refresh session hash
     */
    const char *label_hash;
  } insert_refresh_commit_coin;

  /**
   * Data requiered for the #PERF_TALER_MINTDB_CMD_INSERT_REFRESH_COMMIT_LINK command
   */
  struct PERF_TALER_MINTDB_CMD_insertRefreshCommitLinkDetails
  {
    /**
     * The refresh session hash
     */
    const char *label_hash;

  } insert_refresh_commit_link;

  /**
   * Data requiered by the #PERF_TALER_MINTDB_CMD_GET_REFRESH_COMMIT_LINK command
   */
  struct PERF_TALER_MINTB_CMD_getRefreshCommitLinkDetails
  {
    /**
     * The refresh session hash
     */
    const char *label_hash;
  } get_refresh_commit_link;

  /**
   * Data requiered for the #PERF_TALER_MINTDB_CMD_GET_MELT_COMMITMENT command
   */
  struct PERF_TALER_MINTDB_CMD_getMeltCommitmentDaetails
  {
    /**
     * The refresh session hash
     */
    const char *label_hash;
  } get_melt_commitment;

  /**
   * Data requiered by the #PERF_TALER_MINTDB_CMD_INSERT_REFRESH_OUT command
   */
  struct PERF_TALER_MINTDB_CMD_insertRefreshOutDetails
  {
    /**
     * The refresh session hash
     */
    const char *label_hash;
  } insert_refresh_out;

  /**
   * Data requiered by the #PERF_TALER_MINTDB_CMD_GET_LINK_DATA_LIST command
   */
  struct PERF_TALER_MINTDB_CMD_getLinkDataListDetails
  {
    /**
     * The refresh session hash
     */
    const char *label_hash;
  } get_link_datat_list;

  /**
   * Data requiered by the #PERF_TALER_MINTDB_CMD_GET_TRANSFER command
   */
  struct PERF_TALER_MINTDB_CMD_getTransferDetails
  {
    /**
     * The refresh session hash
     */
    const char *label_hash;
  } get_transfer;

};


/**
 * Command to be interpreted.
 */
struct PERF_TALER_MINTDB_Cmd
{
  /**
   *  Type of the command
   */
  enum PERF_TALER_MINTDB_CMD_Name command;

  /**
   * Label to refer to the command
   */
  const char *label;

  /**
   * Command specific data
   */
  union PERF_TALER_MINTDB_CMD_Details details;

  /**
   * Data easily accessible
   */
  struct PERF_TALER_MINTDB_Data exposed;
};


/**
 * Run a benchmark
 *
 * @param benchmark_name the name of the benchmark, displayed in the logs
 * @param configuration_file path to the taler configuration file to use
 * @param init the commands to use for the database initialisation, 
 * if #NULL the standard initialization is used
 * @param benchmark the commands for the benchmark
 * @return GNUNET_OK upon success; GNUNET_SYSERR upon failure
 */
int
PERF_TALER_MINTDB_run_benchmark (const char *benchmark_name,
                                 const char *configuration_file,
                                 struct PERF_TALER_MINTDB_Cmd *init,
                                 struct PERF_TALER_MINTDB_Cmd *benchmark);


/**
 * Runs the command array @a cmd
 * using @a db_plugin to connect to the database
 * 
 * @param db_plugin the connection to the database
 * @param cmd the commands to run
 */
int
PERF_TALER_MINTDB_interpret(
  struct TALER_MINTDB_Plugin *db_plugin,
  struct PERF_TALER_MINTDB_Cmd cmd[]);


/**
 * Check if the given command array is syntaxicly correct
 * This will check if the label are corrects but will not check if
 * they are pointing to an apropriate command.
 *
 * @param cmd the command array to check
 * @return #GNUNET_OK is @a cmd is correct; #GNUNET_SYSERR if it is'nt
 */
int
PERF_TALER_MINTDB_check (const struct PERF_TALER_MINTDB_Cmd *cmd);

#endif
