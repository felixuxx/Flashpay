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
#include "platform.h"
#include "perf_taler_mintdb_interpreter.h"
#include "perf_taler_mintdb_init.h"
#include "gauger.h"


/**
 * Represents the state of the interpreter
 */
struct PERF_TALER_MINTDB_interpreter_state
{
  /**
   * State of the commands
   */
  struct PERF_TALER_MINTDB_Cmd *cmd;

  /**
   * Database plugin
   */
  struct TALER_MINTDB_Plugin *plugin;

  /**
   * Current database session
   */
  struct TALER_MINTDB_Session *session;

  /**
   * The current index of the interpreter
   */
  unsigned int i;
};

/**
 * Free the memory of @a data, with data of type @a type
 */
static void
data_free (union PERF_TALER_MINTDB_Data *data, enum PERF_TALER_MINTDB_Type type)
{
  switch (type)
  {
    case PERF_TALER_MINTDB_DEPOSIT:
      PERF_TALER_MINTDB_deposit_free (data->deposit);
      data->deposit = NULL;
      return;

    case PERF_TALER_MINTDB_BLINDCOIN:
      PERF_TALER_MINTDB_collectable_blindcoin_free (data->blindcoin);
      data->blindcoin = NULL;
      return;

    case PERF_TALER_MINTDB_RESERVE:
      PERF_TALER_MINTDB_reserve_free (data->reserve);
      data->reserve = NULL;
      return;

    case PERF_TALER_MINTDB_DENOMINATION_INFO:
      PERF_TALER_MINTDB_denomination_free (data->dki);
      data->dki = NULL;
      return;

    case PERF_TALER_MINTDB_COIN_INFO:
      PERF_TALER_MINTDB_coin_public_info_free (data->cpi);
      data->cpi = NULL;
      return;

    default:
      return;
  }
}



/**
 * Finds the first command in cmd with the name search
 *
 * @return the index of the first command with name search
 * GNUNET_SYSERR if none found
 */
static int
cmd_find (const struct  PERF_TALER_MINTDB_Cmd *cmd, const char *search)
{
  unsigned int i;

  for (i=0; PERF_TALER_MINTDB_CMD_END != cmd[i].command; i++)
    if (0 == strcmp (cmd[i].label, search))
      return i;
  return GNUNET_SYSERR;
}


/**
 * Initialization of a command array
 */
static int
cmd_init (struct PERF_TALER_MINTDB_Cmd cmd[])
{
  unsigned int i = 0;

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
        {
          int save_index ;

          GNUNET_assert (GNUNET_SYSERR !=
                         (save_index = cmd_find (
                             cmd,
                             cmd[i].details.load_array.label_save)));
          GNUNET_assert (NULL !=
                         (cmd[i].details.load_array.permutation =
                          GNUNET_CRYPTO_random_permute (
                            GNUNET_CRYPTO_QUALITY_WEAK,
                            cmd[save_index].details.save_array.nb_saved)));
          // Initializing the type based on the type of the saved array
          cmd[i].exposed_type = cmd[save_index].details.save_array.type_saved;
        }
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
  unsigned int i = 0;

  for (i = 0; PERF_TALER_MINTDB_CMD_END != cmd[i].command; i++)
  {
    switch (cmd[i].command)
    {
      case PERF_TALER_MINTDB_CMD_SAVE_ARRAY:
        {
          unsigned int j;
          for (j = 0; j < cmd[i].details.save_array.nb_saved; j++)
          {
            data_free (&cmd[i].details.save_array.data_saved[j],
                       cmd[i].details.save_array.type_saved);
          }
          GNUNET_free (cmd[i].details.save_array.data_saved);
          cmd[i].details.save_array.data_saved = NULL;
        }
        break;

      case PERF_TALER_MINTDB_CMD_LOAD_ARRAY:
        GNUNET_free (cmd[i].details.load_array.permutation);
        cmd[i].details.load_array.permutation = NULL;
        break;

      default:
        data_free (&cmd[i].exposed, cmd[i].exposed_type);
        break;

    }
  }
  return GNUNET_OK;
};


/**
 * Handles the command END_LOOP for the interpreter
 */
static void
interpret_end_loop (struct PERF_TALER_MINTDB_interpreter_state *state)
{
  unsigned int i;
  union PERF_TALER_MINTDB_Data zero = {0};
  int jump;
   GNUNET_assert (GNUNET_SYSERR != 
                  (jump = cmd_find (state->cmd,
                                    state->cmd[state->i]
                                    .details.end_loop.label_loop)));
  // Cleaning up the memory in the loop
  for (i = jump; i < state->i; i++)
  {
    data_free (&state->cmd[i].exposed, state->cmd[i].exposed_type);
    state->cmd[i].exposed = zero;
  }

  state->cmd[jump].details.loop.curr_iteration++;
  // If the loop is not finished
  if (state->cmd[jump].details.loop.max_iterations >
      state->cmd[jump].details.loop.curr_iteration)
  {
    // jump back to the start
    state->i = jump;
  }else{
    // Reset the loop counter and continue running
    state->cmd[jump].details.loop.curr_iteration = 0;
  }
}


/**
 * Saves the data exposed by another command into
 * an array in the command specific struct.
 */
static void
interpret_save_array (struct PERF_TALER_MINTDB_interpreter_state *state)
{
  int loop_index, save_index;
  unsigned int selection_chance;

  // Array initialization on first loop iteration
  // Alows for nested loops
  GNUNET_assert (GNUNET_SYSERR != 
                 (loop_index = cmd_find (state->cmd,
                                         state->cmd[state->i]
                                         .details.save_array.label_loop)));
  GNUNET_assert (GNUNET_SYSERR != 
                 (save_index = cmd_find (state->cmd,
                                         state->cmd[state->i]
                                         .details.save_array.label_save)));
   if (0 == state->cmd[loop_index].details.loop.curr_iteration)
  {
    state->cmd[state->i].details.save_array.index = 0;
  }
  // The probobility distribution of the saved items will be a little biased
  // against the few last items but it should not be a big problem.
  selection_chance = state->cmd[loop_index].details.loop.max_iterations /
    state->cmd[state->i].details.save_array.nb_saved;
  /*
   * If the remaining sapce is equal to the remaining number of
   * iterations, the item is automaticly saved.
   *
   * Else it is saved only if rdn is 0
   */
  if ((0 < (state->cmd[state->i].details.save_array.nb_saved -
            state->cmd[state->i].details.save_array.index)) &&
      (((state->cmd[loop_index].details.loop.max_iterations -
         state->cmd[loop_index].details.loop.curr_iteration) ==
        (state->cmd[state->i].details.save_array.nb_saved -
         state->cmd[state->i].details.save_array.index))
       || (0 == GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                          selection_chance))))
  {
    union PERF_TALER_MINTDB_Data *save_location;
    union PERF_TALER_MINTDB_Data *item_saved;

    save_location = &state->cmd[state->i].details.save_array
      .data_saved[state->cmd[state->i].details.save_array.index];
    item_saved = &state->cmd[save_index].exposed;
    switch (state->cmd[state->i].details.save_array.type_saved)
    {
      case PERF_TALER_MINTDB_TIME:
        save_location->time = item_saved->time;
        break;

      case PERF_TALER_MINTDB_DEPOSIT:
        save_location->deposit = PERF_TALER_MINTDB_deposit_copy (item_saved->deposit);
        break;

      case PERF_TALER_MINTDB_BLINDCOIN:
        save_location->blindcoin = PERF_TALER_MINTDB_collectable_blindcoin_copy (item_saved->blindcoin);
        break;

      case PERF_TALER_MINTDB_RESERVE:
        save_location->reserve = PERF_TALER_MINTDB_reserve_copy (item_saved->reserve);
        break;

      case PERF_TALER_MINTDB_DENOMINATION_INFO:
        save_location->dki = PERF_TALER_MINTDB_denomination_copy (item_saved->dki);
        break;

      case PERF_TALER_MINTDB_COIN_INFO:
        save_location->cpi = item_saved->cpi;
        break;

      default:
        break;
    }
    state->cmd[state->i].details.save_array.index++;
  }
}


static void
interpret_load_array (struct PERF_TALER_MINTDB_interpreter_state *state)
{
  unsigned int loop_iter;
  int loop_index, save_index;
  union PERF_TALER_MINTDB_Data zero = {0};
  union PERF_TALER_MINTDB_Data *loaded_data;
  
  GNUNET_assert (GNUNET_SYSERR !=
                 (loop_index = cmd_find (state->cmd,
                                         state->cmd[state->i]
                                         .details.load_array.label_loop)));
  GNUNET_assert (GNUNET_SYSERR !=
                 (save_index = cmd_find (state->cmd,
                                         state->cmd[state->i]
                                         .details.load_array.label_save)));
  loop_iter = state->cmd[loop_index].details.loop.curr_iteration;
  {
    int i, quotient;
    quotient = loop_iter / state->cmd[save_index].details.save_array.nb_saved;
    loop_iter = loop_iter % state->cmd[save_index].details.save_array.nb_saved;
    for (i=0; i<=quotient; i++){
      loop_iter = state->cmd[state->i].details.load_array.permutation[loop_iter];
    }
  }
  /* Extracting the data from the loop_indexth indice in save_index
   * array.
   */
  loaded_data = &state->cmd[save_index].details.save_array.data_saved[loop_index];
  switch (state->cmd[state->i].exposed_type)
  {
    case PERF_TALER_MINTDB_TIME:
      state->cmd[state->i].exposed.time = loaded_data->time;
      break;

    case PERF_TALER_MINTDB_DEPOSIT:
      state->cmd[state->i].exposed.deposit = loaded_data->deposit;
      break;

    case PERF_TALER_MINTDB_BLINDCOIN:
      state->cmd[state->i].exposed.blindcoin = loaded_data->blindcoin;
      break;

    case PERF_TALER_MINTDB_RESERVE:
      state->cmd[state->i].exposed.reserve = loaded_data->reserve;
      break;

    case PERF_TALER_MINTDB_DENOMINATION_INFO:
      state->cmd[state->i].exposed.dki = loaded_data->dki;

    case PERF_TALER_MINTDB_COIN_INFO:
      state->cmd[state->i].exposed.cpi = loaded_data->cpi;
    default:
      break;
  }
  *loaded_data = zero;
}

/**
 * Main interpreter loop.
 *
 */
static int
interpret (struct PERF_TALER_MINTDB_interpreter_state *state)
{

  for (state->i=0; PERF_TALER_MINTDB_CMD_END != state->cmd[state->i].command; state->i++)
  {
    switch (state->cmd[state->i].command)
    {
      case PERF_TALER_MINTDB_CMD_END:
        return GNUNET_YES;

      case PERF_TALER_MINTDB_CMD_DEBUG:
        GNUNET_log (GNUNET_ERROR_TYPE_INFO, "%s\n", state->cmd[state->i].label);
        break;

      case PERF_TALER_MINTDB_CMD_LOOP:
        break;

      case PERF_TALER_MINTDB_CMD_END_LOOP:
        interpret_end_loop (state);
        break;

      case PERF_TALER_MINTDB_CMD_GET_TIME:
        clock_gettime (CLOCK_MONOTONIC, &state->cmd[state->i].exposed.time);
        break;

      case PERF_TALER_MINTDB_CMD_GAUGER:
        {
          int start_index, stop_index;
          struct timespec start, stop;
          unsigned long elapsed_ms;

          GNUNET_assert (GNUNET_SYSERR !=
                         (start_index  = cmd_find (state->cmd,
                                                   state->cmd[state->i]
                                                   .details.gauger.label_start)));
          GNUNET_assert (GNUNET_SYSERR !=
                         (stop_index  = cmd_find (state->cmd,
                                                  state->cmd[state->i]
                                                  .details.gauger.label_stop)));
          start = state->cmd[start_index].exposed.time;
          stop = state->cmd[stop_index].exposed.time;
          elapsed_ms = (start.tv_sec - stop.tv_sec) * 1000 +
            (start.tv_nsec - stop.tv_nsec) / 1000000;

          GAUGER ("MINTDB",
                  state->cmd[state->i].details.gauger.description,
                  elapsed_ms / state->cmd[state->i].details.gauger.divide,
                  "milliseconds");
        }
        break;

      case PERF_TALER_MINTDB_CMD_NEW_SESSION:
        state->session = state->plugin->get_session (state->plugin->cls, GNUNET_YES);
        break;

      case PERF_TALER_MINTDB_CMD_START_TRANSACTION:
        state->plugin->start (state->plugin->cls, state->session);
        break;

      case PERF_TALER_MINTDB_CMD_COMMIT_TRANSACTION:
        state->plugin->commit (state->plugin->cls, state->session);
        break;

      case PERF_TALER_MINTDB_CMD_ABORT_TRANSACTION:
        state->plugin->rollback (state->plugin->cls, state->session);

      case PERF_TALER_MINTDB_CMD_SAVE_ARRAY:
        interpret_save_array (state);
        break;

      case PERF_TALER_MINTDB_CMD_LOAD_ARRAY:
        interpret_load_array (state);
        break;

      case PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT:
        {
          int dki_index;
          struct TALER_MINTDB_Deposit *deposit;
          GNUNET_assert (GNUNET_SYSERR !=
                         (dki_index = cmd_find(state->cmd,
                                               state->cmd[state->i]
                                               .details.insert_deposit.label_dki)));
          GNUNET_assert (NULL !=
                         (deposit = PERF_TALER_MINTDB_deposit_init (
                             state->cmd[dki_index].exposed.dki)));

          GNUNET_assert (
            state->plugin->insert_deposit (state->plugin->cls,
                                           state->session,
                                           deposit));
          state->cmd[state->i].exposed.deposit = deposit;
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_DEPOSIT:
        {
          int source_index;
          struct TALER_MINTDB_Deposit *deposit; 
          
          GNUNET_assert (GNUNET_SYSERR !=
                         (source_index =  cmd_find (state->cmd,
                                                    state->cmd[state->i]
                                                    .details.get_deposit.label_source)));
          GNUNET_assert (NULL != 
                         (deposit = state->cmd[source_index].exposed.deposit));
          state->plugin->have_deposit (state->plugin->cls,
                                       state->session,
                                       deposit);
        }
        break;

      case PERF_TALER_MINTDB_CMD_INSERT_RESERVE:
        {
          struct TALER_MINTDB_Reserve *reserve;
          json_t *details = NULL;
          GNUNET_assert (NULL !=
                         (details = json_pack ("{s:i}","justification",
                                               GNUNET_CRYPTO_random_u32 (
                                                 GNUNET_CRYPTO_QUALITY_WEAK,
                                                 UINT32_MAX))));
          reserve = PERF_TALER_MINTDB_reserve_init ();
          state->plugin->reserves_in_insert (
            state->plugin->cls,
            state->session,
            &reserve->pub,
            &reserve->balance,
            details
            );
          json_decref (details);
          state->cmd[state->i].exposed.reserve = reserve;
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_RESERVE:
        {
          int source_index;
          struct TALER_MINTDB_Reserve *reserve;
         
          GNUNET_assert (GNUNET_SYSERR !=
                         (source_index = cmd_find (state->cmd,
                                                   state->cmd[state->i]
                                                   .details.get_reserve.label_source)));
          GNUNET_assert (NULL !=
                         (reserve = state->cmd[source_index].exposed.reserve));
          GNUNET_assert (GNUNET_OK ==
                         (state->plugin->reserve_get (state->plugin->cls,
                                                      state->session,
                                                      reserve)));
        }
        break;

      case PERF_TALER_MINTDB_CMD_INSERT_DENOMINATION:
        {
          struct TALER_MINTDB_DenominationKeyIssueInformation *dki =
            PERF_TALER_MINTDB_denomination_init ();

          state->plugin->insert_denomination_info (state->plugin->cls,
                                                   state->session,
                                                   &dki->denom_pub,
                                                   &dki->issue);
          state->cmd[state->i].exposed.dki = dki;
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_DENOMINATION:
        {
          int source_index;
          struct TALER_MINTDB_DenominationKeyIssueInformation *dki; 

          GNUNET_assert (GNUNET_SYSERR !=
                         (source_index =  cmd_find (state->cmd,
                                                    state->cmd[state->i]
                                                    .details.get_denomination.label_source)));
          GNUNET_assert (NULL !=
                         (dki = state->cmd[source_index].exposed.dki));
          state->plugin->get_denomination_info (state->plugin->cls,
                                                state->session,
                                                &dki->denom_pub,
                                                &dki->issue);
        }
        break;

      case PERF_TALER_MINTDB_CMD_INSERT_WITHDRAW:
        {
          int dki_index, reserve_index;
          struct TALER_MINTDB_CollectableBlindcoin *blindcoin ;
          
          GNUNET_assert (GNUNET_SYSERR !=
                         (dki_index = cmd_find (
                             state->cmd,
                             state->cmd[state->i].details.insert_withdraw.label_dki)));
          GNUNET_assert (GNUNET_SYSERR !=
                         (reserve_index = cmd_find (
                             state->cmd,
                             state->cmd[state->i].details.insert_withdraw.label_reserve)));
          GNUNET_assert (NULL != 
                         (blindcoin = 
                          PERF_TALER_MINTDB_collectable_blindcoin_init (
                            state->cmd[dki_index].exposed.dki,
                            state->cmd[reserve_index].exposed.reserve)));

          state->plugin->insert_withdraw_info (state->plugin->cls,
                                               state->session,
                                               blindcoin);
          state->cmd[state->i].exposed.blindcoin = blindcoin;
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_WITHDRAW:
        {
          int source_index;
          struct TALER_MINTDB_CollectableBlindcoin *blindcoin ;

          GNUNET_assert (GNUNET_SYSERR !=
                         (source_index = cmd_find (state->cmd,
                                                   state->cmd[state->i]
                                                   .details.get_denomination.label_source)));
          GNUNET_assert (NULL !=
                         (blindcoin = state->cmd[source_index].exposed.blindcoin));
          state->plugin->get_withdraw_info (state->plugin->cls,
                                            state->session,
                                            &blindcoin->h_coin_envelope,
                                            blindcoin);
        }
        break;

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
PERF_TALER_MINTDB_interpret (struct TALER_MINTDB_Plugin *db_plugin,
                             struct PERF_TALER_MINTDB_Cmd cmd[])
{
  struct PERF_TALER_MINTDB_interpreter_state state =
  {.i = 0, .cmd = cmd, .plugin = db_plugin};

  // Initializing commands
  cmd_init (state.cmd);
  // Running the interpreter
  GNUNET_assert (NULL !=
                 (state.session = db_plugin->get_session (db_plugin->cls, GNUNET_YES)));
  interpret (&state);
  // Cleaning the memory
  cmd_clean (cmd);
  return GNUNET_YES;
}
