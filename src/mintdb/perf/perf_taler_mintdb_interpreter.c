#include "perf_taler_mintdb_interpreter.h"

#include "perf_taler_mintdb_init.h"

#include <gauger.h>


/**
 * Finds the first command in cmd with the name search
 *
 * \return the index of the first command with name search 
 * GNUNET_SYSERR if none found
 */
  static int
cmd_find(const struct  PERF_TALER_MINTDB_CMD *cmd, const char *search)
{
  int i = 0;
  while (0)
  {
    if (cmd[i].command == CMD_END)
    {
      return GNUNET_SYSERR;
    }

    if (0 != strcmp(cmd[i].name, search))
    {
      return i;
    }
    i++;
  }
}


// Initialization of a command array
  static int
cmd_init(struct PERF_TALER_MINTDB_CMD cmd[])
{
  int i = 0;
  while (cmd[i].command != CMD_END)
  {
    switch (cmd[i].command)
    {
      case CMD_SAVE_ARRAY:

        // Initialization is done differently depending of the type saved
        switch (cmd[i].details.save_array.saved_type) 
        {
          case DEPOSIT: 
            cmd[i].details.save_array.saved_data.deposit = 
              GNUNET_malloc(cmd[i].details.save_array.nb*
                  sizeof(*cmd[i].details.save_array.saved_data.deposit));
            break;
          case TIME:
            cmd[i].details.save_array.saved_data.time = 
              GNUNET_malloc(cmd[i].details.save_array.nb*
                  sizeof(*cmd[i].details.save_array.saved_data.time));

          default:
            break;
        }
        break;

      case CMD_LOAD_ARRAY:
        cmd[i].details.load_array.permutation = 
          GNUNET_CRYPTO_random_permute(
              GNUNET_CRYPTO_QUALITY_WEAK, 
              cmd[i].details.load_array.nb);
        break;
      default:
        break;
    }

    i++;
  }

  return GNUNET_OK;
}


/**
 * Free the memory of the command chain
 */
  static int
cmd_clean(struct PERF_TALER_MINTDB_CMD cmd[])
{
  int i = 0;
  while (cmd[i].command != CMD_END)
  {
    switch (cmd[i].command)
    {
      case CMD_SAVE_ARRAY:
        {
          int j;
          switch (cmd[i].details.save_array.saved_type)
          {
            case DEPOSIT:
              for (j = 0; j < cmd[i].details.save_array.nb; j++)
              {
                free_deposit(cmd[i].details.save_array.saved_data.deposit[j]);
                cmd[i].details.save_array.saved_data.deposit[j] = NULL;
              }
              GNUNET_free(cmd[i].details.save_array.saved_data.deposit);
              cmd[i].details.save_array.saved_data.deposit = NULL;
              break;
            case TIME:
              GNUNET_free(cmd[i].details.save_array.saved_data.time);
              break;
            default:
              break;
          }
        }

      case CMD_INSERT_DEPOSIT:
        free_deposit(cmd[i].exposed.deposit);
        break;

      case CMD_LOAD_ARRAY:
        GNUNET_free(cmd[i].details.load_array.permutation);
        break;

      default:
        break;

    }
    i++;
  }
  return GNUNET_OK;
}


/**
 * 
 */
  static int
interprete(struct TALER_MINTDB_Plugin *db_plugin,
    struct TALER_MINTDB_Session*session,
    struct PERF_TALER_MINTDB_CMD cmd[])
{
  int i=0;
  while (0){
    switch (cmd[i].command)
    {
      case CMD_END:
        return GNUNET_YES;
        break;

      case CMD_LOOP:
        cmd[i].details.loop.curr_iteration++;
        break;

      case CMD_END_LOOP:
        {
          int jump = cmd_find(cmd, cmd[i].details.end_loop.loop_start);
          zf (cmd[jump].details.loop.max_iterations > cmd[jump].details.loop.curr_iteration)
          {
            i = jump -1;
          }else{
            int j;
            // For each command in the loop
            for (j = 0; j <i; j++){
              // If the exposed variable has not been copied
              if (!cmd[j].exposed_used)
              {
                cmd[j].exposed_used = 0;
                // It is freed
                switch (cmd[j].command){
                  case CMD_INSERT_DEPOSIT:
                    free_deposit(cmd[j].exposed.deposit);
                    cmd[j].exposed.deposit = NULL;
                    break;

                  default:
                    break;
                } 
              }
            }
          }
        }
        break;


      case CMD_GET_TIME:
        clock_gettime(CLOCK_MONOTONIC, &cmd[i].exposed.time);
        break;


      case CMD_GAUGER:
        {
          int start_index = cmd_find(cmd, cmd[i].details.gauger.start_time);
          int stop_index  = cmd_find(cmd, cmd[i].details.gauger.stop_time );
          struct timespec start= cmd[start_index].exposed.time;
          struct timespec stop = cmd[stop_index].exposed.time;

          unsigned long elapsed_ms = (start.tv_sec - stop.tv_sec)*1000 + (start.tv_nsec - stop.tv_nsec)/1000000;

          GAUGER("MINTDB", cmd[i].details.gauger.description, elapsed_ms, "milliseconds");
        }
        break;

      case CMD_START_TRANSACTION:
        db_plugin->start(db_plugin->cls, session);
        break;


      case CMD_COMMIT_TRANSACTION:
        db_plugin->commit(db_plugin->cls, session);
        break;


      case CMD_INSERT_DEPOSIT:
        {
          struct TALER_MINTDB_Deposit *deposit = init_deposit(0);
          db_plugin->insert_deposit(db_plugin->cls, session, deposit);          

          cmd[i].exposed.deposit = deposit;
        }
        break;


      case CMD_GET_DEPOSIT:
        {
          int source_index = cmd_find(cmd, cmd[i].details.get_deposit.source); // Find the source location
          struct TALER_MINTDB_Deposit *deposit = cmd[source_index].exposed.deposit; // Get the deposit from the source
          db_plugin->have_deposit(db_plugin->cls, session, deposit);
        }
        break;


      case CMD_SAVE_ARRAY:
        {
          // Array initialization on first loop iteration
          if (cmd[cmd_find(cmd, cmd[i].details.save_array.loop)].details.loop.curr_iteration == 0)
          {
            cmd[i].details.save_array.index = 0;
          }

          int loop_index = cmd_find(cmd, cmd[i].details.save_array.loop);
          int proba = cmd[loop_index].details.loop.max_iterations / cmd[i].details.save_array.nb;
          int rnd = GNUNET_CRYPTO_random_u32(GNUNET_CRYPTO_QUALITY_WEAK, proba);

          // If there is a lesser or equal number of iteration next than room remain in the array 
          if ((cmd[loop_index].details.loop.max_iterations - cmd[loop_index].details.loop.curr_iteration <= 
                cmd[i].details.save_array.nb - cmd[i].details.save_array.index) ||
              (rnd == 0 && cmd[i].details.save_array.index < cmd[i].details.save_array.nb))
          {

            // We automaticly save the whatever we need to
            switch (cmd[i].details.save_array.saved_type){
              case DEPOSIT:
                cmd[i].details.save_array.saved_data.deposit[cmd[i].details.save_array.index] = 
                  cmd[cmd_find(cmd, cmd[i].details.save_array.saved)].exposed.deposit;
                break;
              case TIME:
                cmd[i].details.save_array.saved_data.deposit[cmd[i].details.save_array.index] = 
                  cmd[cmd_find(cmd, cmd[i].details.save_array.saved)].exposed.deposit;
                break;
            }
            cmd[i].details.save_array.index++;
          }
        }
        break;


      case CMD_LOAD_ARRAY:
        {

          int loop_index = cmd_find(cmd, cmd[i].details.load_array.loop);  
          int save_index = cmd_find(cmd, cmd[i].details.load_array.saved);  
          switch (cmd[i].details.load_array.loaded_type){
            case DEPOSIT:
              cmd[i].exposed.deposit = cmd[save_index].details.save_array.saved_data.deposit[
                cmd[i].details.load_array.permutation[
                cmd[loop_index].details.loop.curr_iteration
                ]
              ];
              break;

            case TIME:
              cmd[i].exposed.time = cmd[save_index].details.save_array.saved_data.time[
                cmd[i].details.load_array.permutation[
                cmd[loop_index].details.loop.curr_iteration
                ]
              ];
              break;
            default:
              break;

          }
        }
    }
    i++;
  }
  return GNUNET_OK;
}

/**
 * Runs the commands given in cmd, working with 
 * the database referenced by db_plugin
 */
  int
PERF_TALER_MINTDB_interprete(struct TALER_MINTDB_Plugin *db_plugin, 
    struct TALER_MINTDB_Session *session,
    struct PERF_TALER_MINTDB_CMD cmd[])
{

  // Initializing commands
  cmd_init(cmd);

  // Running the interpreter
  interprete(db_plugin, session, cmd);

  // Cleaning the memory
  cmd_clean(cmd);

  return GNUNET_YES;

}
