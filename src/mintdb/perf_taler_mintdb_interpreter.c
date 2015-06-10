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
 * @file mintdb/perf_taler_mintdb_interpreter.c
 * @brief Interpreter library for mint database performance analysis
 * @author Nicolas Fournier
 */
#include "perf_taler_mintdb_interpreter.h"
#include "perf_taler_mintdb_init.h"
#include "../include/gauger.h"


/**
 * Finds the first command in cmd with the name search
 *
 * @return the index of the first command with name search
 * GNUNET_SYSERR if none found
 */
static int
cmd_find(const struct  PERF_TALER_MINTDB_Cmd *cmd, const char *search)
{
  int i;

  for (i=0; PERF_TALER_MINTDB_CMD_END != cmd[i].command; i++)
    if (0 == strcmp (cmd[i].label, search))
      return i;
  return GNUNET_SYSERR;
}


// Initialization of a command array
static int
cmd_init(struct PERF_TALER_MINTDB_Cmd cmd[])
{
  int i = 0;
  for (i=0; PERF_TALER_MINTDB_CMD_END != cmd[i].command; i++)
  {
    switch (cmd[i].command)
    {
      case PERF_TALER_MINTDB_CMD_SAVE_ARRAY:
        // Allocation of memory for saving data
        cmd[i].details.save_array.data_saved = 
          GNUNET_new_array (cmd[i].details.save_array.nb_saved, 
                            union PERF_TALER_MINTDB_Data);
        break;

      case PERF_TALER_MINTDB_CMD_LOAD_ARRAY:
        // Creating the permutation array to randomize the data order
        cmd[i].details.load_array.permutation =
          GNUNET_CRYPTO_random_permute (
                                        GNUNET_CRYPTO_QUALITY_WEAK,
                                        cmd[i].details.load_array.nb);

        // Initializing the type based on the type of the saved array
        cmd[i].exposed_type = cmd[
          cmd_find (cmd, cmd[i].details.load_array.label_save)
        ].details.save_array.type_saved;
        break;

      default:
        break;
    }
  }
  return GNUNET_OK;
}


/**
 * Free the memory of the command chain
 */
static int
cmd_clean (struct PERF_TALER_MINTDB_Cmd cmd[])
{
  int i = 0;
  for(i=0; PERF_TALER_MINTDB_CMD_END != cmd[i].command; i++)
  {
    switch (cmd[i].command)
    {
      case PERF_TALER_MINTDB_CMD_SAVE_ARRAY:
        {
          int j;
          switch (cmd[i].details.save_array.type_saved)
          {
            case PERF_TALER_MINTDB_DEPOSIT:
              for (j = 0; j < cmd[i].details.save_array.nb_saved; j++)
              {
                deposit_free (cmd[i].details.save_array.data_saved[j].deposit);
                cmd[i].details.save_array.data_saved[j].deposit = NULL;
              }
              GNUNET_free (cmd[i].details.save_array.data_saved);
              break;

            default:
              break;
          }
          cmd[i].details.save_array.data_saved = NULL;
        }

      case PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT:
        deposit_free (cmd[i].exposed.deposit);
        break;

      case PERF_TALER_MINTDB_CMD_LOAD_ARRAY:
        GNUNET_free (cmd[i].details.load_array.permutation);
        break;

      default:
        break;

    }
    i++;
  }
  return GNUNET_OK;
};


/**
 * /TODO cut it into pieces
 */
static int
interpret(struct TALER_MINTDB_Plugin *db_plugin,
          struct TALER_MINTDB_Session*session,
          struct PERF_TALER_MINTDB_Cmd cmd[])
{
  int i=0;
  for(i=0; PERF_TALER_MINTDB_CMD_END == cmd[i].command; i++)
  {
    switch (cmd[i].command)
    {
      case PERF_TALER_MINTDB_CMD_END:
        return GNUNET_YES;

      case PERF_TALER_MINTDB_CMD_LOOP:
        cmd[i].details.loop.curr_iteration++;
        break;

      case PERF_TALER_MINTDB_CMD_END_LOOP:
        {
          int jump = cmd_find(cmd, cmd[i].details.end_loop.label_loop);
          if (cmd[jump].details.loop.max_iterations > cmd[jump].details.loop.curr_iteration)
          {
            i = jump -1;
          }else{
            // Reseting loop counter
            cmd[jump].details.loop.curr_iteration = -1;
          }
          // Cleaning up the memory in the loop
          int j;
          // For each command in the loop
          for (j = jump; j < i; j++)
          {
            // If the exposed variable has not been copied
            if ( 0 == cmd[j].exposed_saved)
            {
              // It is freed
              switch (cmd[j].exposed_type)
              {
                case PERF_TALER_MINTDB_DEPOSIT:
                  deposit_free (cmd[j].exposed.deposit);
                  cmd[j].exposed.deposit = NULL;
                  break;

                default:
                  break;
              }
            }
            cmd[j].exposed_saved = 0;
          }
        }
        break;


      case PERF_TALER_MINTDB_CMD_GET_TIME:
        clock_gettime(CLOCK_MONOTONIC, &cmd[i].exposed.time);
        break;


      case PERF_TALER_MINTDB_CMD_GAUGER:
        {
          int start_index = cmd_find (cmd, cmd[i].details.gauger.label_start);
          int stop_index  = cmd_find (cmd, cmd[i].details.gauger.label_stop);
          struct timespec start = cmd [start_index].exposed.time;
          struct timespec stop = cmd [stop_index].exposed.time;

          unsigned long elapsed_ms = (start.tv_sec - stop.tv_sec) * 1000 + (start.tv_nsec - stop.tv_nsec) / 1000000;

          GAUGER ("MINTDB", cmd[i].details.gauger.description, elapsed_ms, "milliseconds");
        }
        break;

      case PERF_TALER_MINTDB_CMD_START_TRANSACTION:
        db_plugin->start(db_plugin->cls, session);
        break;


      case PERF_TALER_MINTDB_CMD_COMMIT_TRANSACTION:
        db_plugin->commit(db_plugin->cls, session);
        break;


      case PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT:
        {
          struct TALER_MINTDB_Deposit *deposit = deposit_init (-1);
          db_plugin->insert_deposit(db_plugin->cls, session, deposit);

          cmd[i].exposed.deposit = deposit;
        }
        break;


      case PERF_TALER_MINTDB_CMD_GET_DEPOSIT:
        {
          int source_index = cmd_find(cmd, cmd[i].details.get_deposit.source); // Find the source location
          struct TALER_MINTDB_Deposit *deposit = cmd[source_index].exposed.deposit; // Get the deposit from the source
          db_plugin->have_deposit(db_plugin->cls, session, deposit);
        }
        break;


      case PERF_TALER_MINTDB_CMD_SAVE_ARRAY:
        {
          // Array initialization on first loop iteration
          // Alows for nested loops
          if (cmd[cmd_find(cmd, cmd[i].details.save_array.label_loop)].details.loop.curr_iteration == 0)
          {
            cmd[i].details.save_array.index = 0;
          }

          int loop_index = cmd_find(cmd, cmd[i].details.save_array.label_loop);
          int proba = cmd[loop_index].details.loop.max_iterations / cmd[i].details.save_array.nb_saved;
          int rnd = GNUNET_CRYPTO_random_u32(GNUNET_CRYPTO_QUALITY_WEAK, proba);

          // If there is a lesser or equal number of iteration next than room remain in the array
          if ((cmd[loop_index].details.loop.max_iterations - cmd[loop_index].details.loop.curr_iteration <=
               cmd[i].details.save_array.nb_saved - cmd[i].details.save_array.index) ||
              (rnd == 0 && cmd[i].details.save_array.index < cmd[i].details.save_array.nb_saved))
          {
            // We automaticly save the whatever we need to
            switch (cmd[i].details.save_array.type_saved)
            {
              case PERF_TALER_MINTDB_DEPOSIT:
                cmd[i].details.save_array.data_saved[cmd[i].details.save_array.index].deposit =
                  cmd[cmd_find (cmd, cmd[i].details.save_array.label_save)].exposed.deposit;
                break;

              case PERF_TALER_MINTDB_TIME:
                cmd[i].details.save_array.data_saved[cmd[i].details.save_array.index].time =
                  cmd[cmd_find (cmd, cmd[i].details.save_array.label_save)].exposed.time;
                break;

              default:
                break;
            }
            cmd[cmd_find (cmd, cmd[i].details.save_array.label_save)].exposed_saved = 1;
            cmd[i].details.save_array.index++;
          }
        }
        break;


      case PERF_TALER_MINTDB_CMD_LOAD_ARRAY:
        {

          int loop_index = cmd_find(cmd, cmd[i].details.load_array.label_loop);
          int save_index = cmd_find(cmd, cmd[i].details.load_array.label_save);
          switch (cmd[i].exposed_type){
            case PERF_TALER_MINTDB_DEPOSIT:
              cmd[i].exposed.deposit = cmd[save_index].details.save_array.data_saved[
                cmd[i].details.load_array.permutation[
                  cmd[loop_index].details.loop.curr_iteration
                ]
              ].deposit;
                break;

            case PERF_TALER_MINTDB_TIME:
                cmd[i].exposed.time = cmd[save_index].details.save_array.data_saved[
                  cmd[i].details.load_array.permutation[
                    cmd[loop_index].details.loop.curr_iteration
                  ]
                ].time;
                  break;

            default:
                  break;
          }
        }
      default :
        break;
    }
  }
  return GNUNET_OK;
}

/**
 * Runs the commands given in @a cmd, working with
 * the database referenced by @a db_plugin
 */
int
PERF_TALER_MINTDB_interpret(struct TALER_MINTDB_Plugin *db_plugin,
                            struct TALER_MINTDB_Session *session,
                            struct PERF_TALER_MINTDB_Cmd cmd[])
{
  // Initializing commands
  cmd_init(cmd);

  // Running the interpreter
  interpret(db_plugin, session, cmd);

  // Cleaning the memory
  cmd_clean(cmd);

  return GNUNET_YES;
}
