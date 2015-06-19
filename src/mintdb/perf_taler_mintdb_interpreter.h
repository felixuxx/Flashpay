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
 * @brief Library for performance analysis of taler database
 * @author Nicolas Fournier
 */

#ifndef __PERF_TALER_MINTDB_INTERPRETER_H__
#define __PERF_TALER_MINTDB_INTERPRETER_H__

#include <sys/time.h>
#include "taler_mintdb_plugin.h"

/**
 * Marks the end of the command chain
 * @param _label
 */
#define PERF_TALER_MINTDB_INIT_CMD_END(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_END, \
  .label = _label, \
  .exposed_type = PERF_TALER_MINTDB_NONE \
}


/**
 *
 */
#define PERF_TALER_MINTDB_INIT_CMD_DEBUG(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_DEBUG, \
  .label = _label, \
  .exposed_type = PERF_TALER_MINTDB_NONE \
}
/**
 * The begining of a loop
 * @param _label the name of the loop
 * @param _iter the number of iteration of the loop
 */
#define PERF_TALER_MINTDB_INIT_CMD_LOOP(_label, _iter) \
{ \
  .command = PERF_TALER_MINTDB_CMD_LOOP , \
  .label = _label , \
  .exposed_type = PERF_TALER_MINTDB_NONE , \
  .details.loop = { \
    .max_iterations = _iter , \
    .curr_iteration = 0} \
}

/**
 * Marks the end of the loop @_label_loop
 */
#define PERF_TALER_MINTDB_INIT_CMD_END_LOOP(_label, _label_loop) \
{\
  .command = PERF_TALER_MINTDB_CMD_END_LOOP , \
  .label = _label , \
  .exposed_type = PERF_TALER_MINTDB_NONE , \
  .details.end_loop.label_loop = _label_loop \
}

/**
 * Saves the time of execution to use for logging with gauger
 */
#define PERF_TALER_MINTDB_INIT_CMD_GET_TIME(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GET_TIME, \
  .label = _label, \
  .exposed_type = PERF_TALER_MINTDB_NONE, \
}

/**
 * Commits the duration between @a _label_start and @a _label_stop
 * to Gauger with @a _description explaining
 */
#define PERF_TALER_MINTDB_INIT_CMD_GAUGER(_label, _start_time, _stop_time, _description) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GAUGER, \
  .label = _label, \
  .exposed_type = PERF_TALER_MINTDB_NONE, \
  .details.gauger = { \
    .label_start = _label_start, \
    .label_end = _label_end, \
    .description = _description \
  } \
}

/**
 * Initiate a database transaction
 */
#define PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_START_TRANSACTION, \
  .label = _label, \
  .exposed_type = PERF_TALER_MINTDB_NONE, \
}

/**
 * Commits a database connection
 */
#define PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_COMMIT_TRANSACTION, \
  .label = _label, \
  .exposed_type = PERF_TALER_MINTDB_NONE, \
}

/**
 * Insert a deposit into the database
 */
#define PERF_TALER_MINTDB_INIT_CMD_INSERT_DEPOSIT(_label) \
{ \
  .command = PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT,\
  .label = _label, \
  .exposed_type = PERF_TALER_MINTDB_DEPOSIT, \
}

/**
 * Check if a deposit is in the database
 * @param _label_deposit Label of the deposit to use
 */
#define PERF_TALER_MINTDB_INIT_CMD_GET_DEPOSIT(_label, _label_deposit) \
{ \
  .command = PERF_TALER_MINTDB_CMD_GET_DEPOSIT, \
  .label = _label, \
  .exposed_type = PERF_TALER_MINTDB_NONE, \
  .details.get_deposit.label_source = _label_deposit \
}

/**
 * Extracts @a _nb_saved items of type @a _save_type 
 * from the command @a _label_save during the loop @a _label_loop
 */
#define PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY(_label, _label_loop, _label_save, _nb_saved, _save_type) \
{ \
  .command = PERF_TALER_MINTDB_CMD_SAVE_ARRAY, \
  .label = _label, \
  .exposed_type = PERF_TALER_MINTDB_NONE, \
  .details.save_array = { \
    .label_loop = _label_loop, \
    .label_save = _label_save, \
    .nb_saved = _nb_saved, \
    .type_saved = _save_type \
  } \
}

/**
 * Loads @a _nb_saved previously sampled data of type @a _saved_type
 * from @a _label_save during the loop @a _label_loop 
 */
#define PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY(_label, _label_loop, _label_save) \
{ \
  .command = PERF_TALER_MINTDB_CMD_LOAD_ARRAY, \
  .label = _label, \
  .exposed_type = PERF_TALER_MINTDB_NONE, \
  .details.load_array = { \
    .label_loop = _label_loop, \
    .label_save = _label_save \
  } \
}



/**
 * The type of data stored
 * in a PERF_TALER_MINTDB_Type
 */
enum PERF_TALER_MINTDB_Type 
{
  PERF_TALER_MINTDB_NONE,
  PERF_TALER_MINTDB_TIME,
  PERF_TALER_MINTDB_DEPOSIT,
  PERF_TALER_MINTDB_BLINDCOIN,
  PERF_TALER_MINTDB_RESERVE,
  PERF_TALER_MINTDB_DENOMINATION_INFO,
  PERF_TALER_MINTDB_COIN_INFO,
};


/**
 * Storage for a variety of data type
 */
union PERF_TALER_MINTDB_Data 
{
  struct TALER_MINTDB_Deposit *deposit;
  struct timespec time; 
  struct TALER_MINTDB_CollectableBlindcoin *blindcoin;
  struct TALER_MINTDB_Reserve *reserve;
  struct TALER_MINTDB_DenominationKeyIssueInformation *dki;
  struct TALER_CoinPublicInfo *cpi;
};


/**
 * Name of the command
 */
enum PERF_TALER_MINTDB_CMD_Name
{
  // All comand chain must hace this as their last command
  PERF_TALER_MINTDB_CMD_END,
  
  // Prints it's label
  PERF_TALER_MINTDB_CMD_DEBUG,

  // Define the start of al command chain loop
  PERF_TALER_MINTDB_CMD_LOOP,
  
  // Define the end of a command chain loop
  PERF_TALER_MINTDB_CMD_END_LOOP,

  // Save the time at which the command was executed
  PERF_TALER_MINTDB_CMD_GET_TIME,

  // Upload performance to Gauger
  PERF_TALER_MINTDB_CMD_GAUGER,

  // Start a new session
  PERF_TALER_MINTDB_CMD_NEW_SESSION,

  // Start a database transaction
  PERF_TALER_MINTDB_CMD_START_TRANSACTION,

  // End a database transaction
  PERF_TALER_MINTDB_CMD_COMMIT_TRANSACTION,

  // Abort a transaction
  PERF_TALER_MINTDB_CMD_ABORT_TRANSACTION,

  // Insert a deposit into the database
  PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT,

  // Check if a deposit is in the database
  PERF_TALER_MINTDB_CMD_GET_DEPOSIT,

  // Saves random deposits from a loop
  PERF_TALER_MINTDB_CMD_SAVE_ARRAY,

  // Load deposits saved earlier
  PERF_TALER_MINTDB_CMD_LOAD_ARRAY,

} command;


/**
 * Extra data requiered for the LOOP command
 */
struct PERF_TALER_MINTDB_CMD_loop_details
{
  // Maximum number of iteration in the loop
  const unsigned int max_iterations;
  int curr_iteration;
};


/**
 * Extra data requiered by the LOOP_END command
 */
struct PERF_TALER_MINTDB_CMD_loop_end_details  
{
  /**
   * Label of the loop closed by the command
   */
  const char *label_loop;
};


/**
 * Details about the GAUGER command
 */
struct PERF_TALER_MINTDB_CMD_gauger_details
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
   * Description of the metric, used in GAUGER
   */
  const char *description;
};


/**
 * Contains extra data requiered by the SAVE_ARRAY command
 */
struct PERF_TALER_MINTDB_CMD_save_array_details
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
   * Type of data saved
   */
  enum PERF_TALER_MINTDB_Type type_saved;
  /**
   * Array of data saved
   */
  union PERF_TALER_MINTDB_Data *data_saved;
};


/**
 * Extra data required for the LOAD_ARRAY command
 */
struct PERF_TALER_MINTDB_CMD_load_array_details
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
  unsigned int *permutation; // A permutation array to randomize the order the deposits are loaded in
};


/**
 * Extra data requiered for the GET_DEPOSIT command
 */
struct PERF_TALER_MINTDB_CMD_get_deposit_details
{
  /**
   * The label of the source of the deposit to check
   */
  const char *label_source;
};


/**
 * Contains extra data required for any command
 */
union PERF_TALER_MINTDB_CMD_Details
{
  struct PERF_TALER_MINTDB_CMD_loop_details loop;
  struct PERF_TALER_MINTDB_CMD_loop_end_details end_loop;
  struct PERF_TALER_MINTDB_CMD_gauger_details gauger;
  struct PERF_TALER_MINTDB_CMD_save_array_details save_array;
  struct PERF_TALER_MINTDB_CMD_load_array_details load_array;
  struct PERF_TALER_MINTDB_CMD_get_deposit_details get_deposit;
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
   * Type of the data exposed
   */
  enum PERF_TALER_MINTDB_Type exposed_type;

  /**
   * Data easily accessible
   */
  union PERF_TALER_MINTDB_Data exposed;

  /**
   * GNUNET_YES if the exposed value hav been saved during last loop iteration
   * GNUNET_NO if it hasn't
   */
  int exposed_saved;
};


/**
 * Runs the command array @a cmd
 * using @a db_plugin to connect to the database
 */
int
PERF_TALER_MINTDB_interpret(
  struct TALER_MINTDB_Plugin *db_plugin,
  struct PERF_TALER_MINTDB_Cmd cmd[]);


#endif
