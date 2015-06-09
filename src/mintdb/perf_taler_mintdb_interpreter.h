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
#include <gnunet/platform.h>
#include "taler_mintdb_lib.h"
#include "taler_mintdb_plugin.h"

/**
 * Marks the end of the command chain
 * @param _label
 */
#define INIT_CMD_END(label) {.command = PERF_TALER_MINTDB_CMD_END, .label = _label}

/**
 * The begining of a loop
 * @param _label the name of the loop
 * @param _iter the number of iteration of the loop
 */
#define INIT_CMD_LOOP(_label, _iter) \
  { \
    .command = PERF_TALER_MINTDB_CMD_LOOP, \
    .label = _label, \
    .exposed_type = PERF_TALER_MINTDB_NONE, \
    .details.loop = { \
       .max_iterations = _iter, \
       .curr_iteration = -1} \
  }

/**
 * Marks the end of the loop @_label_loop
 */
#define INIT_CMD_END_LOOP(_label, _label_loop) \
  {\
    .command = PERF_TALER_MINTDB_CMD_END_LOOP,\
    .label = _label,\
    .exposed_type = PERF_TALER_MINTDB_NONE, \
    .details.end_loop.label_loop = _label_loop \
  }

/**
 * Saves the time of execution to use for logging with gauger
 */
#define INIT_CMD_GET_TIME(_label) \
  { \
    .command = PERF_TALER_MINTDB_CMD_GET_TIME, \
    .label = _label \
    .exposed_type = PERF_TALER_MINTDB_NONE, \
  }

/**
 * Commits the duration between @a _label_start and @a _label_stop
 * to Gauger with @a _description explaining
 */
#define INIT_CMD_GAUGER(_label, _start_time, _stop_time, _description) \
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
#define INIT_CMD_START_TRANSACTION(_label) \
  { \
    .command = PERF_TALER_MINTDB_CMD_START_TRANSACTION, \
    .label = _label \
    .exposed_type = PERF_TALER_MINTDB_NONE, \
  }

/**
 * Commits a database connection
 */
#define INIT_CMD_COMMIT_TRANSACTION(_label) \
  { \
    .command = PERF_TALER_MINTDB_CMD_COMMIT_TRANSACTION, \
    .label = _label \
    .exposed_type = PERF_TALER_MINTDB_NONE, \
  }

/**
 * Insert a deposit into the database
 */
#define INIT_CMD_INSERT_DEPOSIT(_label) \
  { \
    .command = PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT,\
    .label = label \
    .exposed_type = PERF_TALER_MINTDB_NONE, \
  }

/**
 * Check if a deposit is in the database
 * @param _label_deposit Label of the deposit to use
 */
#define INIT_CMD_GET_DEPOSIT(_label, _label_deposit) \
  { \
    .command = PERF_TALER_MINTDB_CMD_GET_DEPOSIT, \
    .label = _label, \
    .exposed_type = PERF_TALER_MINTDB_NONE, \
    .details.label_deposit.saved = _label_deposit \
  }

/**
 * Extracts @a _nb_saved items of type @a _save_type 
 * from the command @a _label_save during the loop @a _label_loop
 */
#define INIT_CMD_SAMPLE_ARRAY(_label, _label_loop, _label_save, _nb_saved, _save_type) \
  { \
    .command = PERF_TALER_MINTDB_CMD_SAVE_ARRAY, \
    .label = _label, \
    .exposed_type = PERF_TALER_MINTDB_NONE, \
    .details.save_array = { \
        .label_loop = _label_loop, \
        .label_save = _label_save, \
        .nb_saved = _nb_saved, \
        .save_type = _save_type \
      } \
  }

/**
 * Loads @a _nb_saved previously sampled data of type @a _saved_type
 * from @a _label_save during the loop @a _label_loop 
 */
#define INIT_CMD_LOAD_ARRAY(_label, _label_loop, _label_save, _nb_saved, _save_type) \
  { \
    .command = PERF_TALER_MINTDB_CMD_LOAD_ARRAY, \
    .label = _label, \
    .exposed_type = _saved_type_, \
    .details.load_array = { \
      .label_loop = _label_loop, \
      .label_save = _label_save \
      .nb_saved = _nb_saved, \
     } \
  }



/**
 * The type of data stored
 */
enum PERF_TALER_MINTDB_Type 
{
  PERF_TALER_MINTDB_NONE,
  PERF_TALER_MINTDB_DEPOSIT,
  PERF_TALER_MINTDB_TIME,
};

/**
 * Storage for a variety of data type
 */
union PERF_TALER_MINTDB_Data 
{
  struct TALER_MINTDB_Deposit *deposit;
  struct timespec time; 
};

/**
 * Name of the command
 */
enum PERF_TALER_MINTDB_CMD_Name
{
  // All comand chain must hace this as their last command
  PERF_TALER_MINTDB_CMD_END,

  // Define the start of al command chain loop
  PERF_TALER_MINTDB_CMD_LOOP,
  //
  // Define the end of a command chain loop
  PERF_TALER_MINTDB_CMD_END_LOOP,

  // Save the time at which the command was executed
  PERF_TALER_MINTDB_CMD_GET_TIME,

  // Upload performance to Gauger
  PERF_TALER_MINTDB_CMD_GAUGER,

  // Start a database transaction
  PERF_TALER_MINTDB_CMD_START_TRANSACTION,

  // End a database transaction
  PERF_TALER_MINTDB_CMD_COMMIT_TRANSACTION,

  // Insert a deposit into the database
  PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT,

  // Check if a deposit is in the database
  PERF_TALER_MINTDB_CMD_GET_DEPOSIT,

  // Saves random deposits from a loop
  PERF_TALER_MINTDB_CMD_SAVE_ARRAY,

  // Load deposits saved earlier
  PERF_TALER_MINTDB_CMD_LOAD_ARRAY,

} command;


struct PERF_TALER_MINTDB_loop_details
{
  // Maximum number of iteration in the loop
  const unsigned int max_iterations;
  int curr_iteration;
};

struct PERF_TALER_MINTDB_loop_end_details  
{
  /**
   * Label of the loop closed by the command
   */
  const char *label_loop;
};

/**
 * Details about the GAUGER command
 */
struct PERF_TALER_MINTDB_gauger_details
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
 * Contains details about a command
 */
struct PERF_TALER_MINTDB_save_array_details
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
  enum PERF_TALER_MINTDB_TYPE type_saved;
  /**
   * Array of data saved
   */
  union PERF_TALER_MINTDB_Data *data_saved;
};

struct PERF_TALER_MINTDB_load_array_details
{
  /**
   * TODO Remove references to nb and use the link to the loop to initialize
   */
  int nb;
  /**
   * The loop in which the comand is located
   */
  const char *label_loop;
  /**
   * Label of the command where the items were saved
   */
  const char *label_saved;
  /**
   * A permutation array used to randomize the order the items are loaded in
   */
  unsigned int *permutation; // A permutation array to randomize the order the deposits are loaded in
};

struct PERF_TALER_MINTDB_get_deposit_details
{
  const char *source;
};

union PERF_TALER_MINTDB_Details
{
  struct PERF_TALER_MINTDB_LOOP_DETAILS loop,
  struct PERF_TALER_MINTDB_LOOP_END_DETAILS end_loop,
  struct PERF_TALER_MINTDB_GAUGER_DETAILS gauger,
  struct PERF_TALER_MINTDB_SAVE_ARRAY save_array,
  struct PERF_TALER_MINTDB_LOAD_ARRAY_DETAILS load_array,
};


/**
 * Command to be interpreted.
 */
struct PERF_TALER_MINTDB_Cmd
{
  enum PERF_TALER_MINTDB_CMD_Name command;

  /**
   * Label to refer to the command
   */
  const char *label;

  /**
   * Command specific data
   */
  union PERF_TALER_MINTDB_Details details;

  /**
   * Type of the data exposed
   */
  enum PERF_TALER_MINTDB_Type exposed_type;

  /**
   * Data easily accessible
   */
  union PERF_TALER_MINTDB_Data exposed;

  int exposed_saved;
};


int
PERF_TALER_MINTDB_interpret(
    struct TALER_MINTDB_Plugin *db_plugin,
    struct TALER_MINTDB_Session *session, // add START_SESSION CMD
    struct PERF_TALER_MINTDB_CMD cmd[]);


#endif
