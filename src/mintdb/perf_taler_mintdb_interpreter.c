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


#define FIND_TEST(cmd, string, arg) \

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
 * Free the memory of @a data
 */
static void
data_free (struct PERF_TALER_MINTDB_Data *data)
{
  switch (data->type)
  {
    case PERF_TALER_MINTDB_TIME:
      if (NULL == data->data.time)
        return;
    GNUNET_free (data->data.time);
    data->data.time = NULL;
    return;

    case PERF_TALER_MINTDB_DEPOSIT:
      if (NULL == data->data.deposit)
        return;
      PERF_TALER_MINTDB_deposit_free (data->data.deposit);
      GNUNET_free (data->data.deposit);
      data->data.deposit = NULL;
      return;

    case PERF_TALER_MINTDB_COIN:
      if (NULL == data->data.coin)
        return;
      PERF_TALER_MINTDB_coin_free (data->data.coin);
      GNUNET_free (data->data.coin);
      data->data.coin = NULL;
      return;

    case PERF_TALER_MINTDB_RESERVE:
      if (NULL == data->data.reserve)
        return;
      PERF_TALER_MINTDB_reserve_free (data->data.reserve);
      GNUNET_free (data->data.reserve);
      data->data.reserve = NULL;
      return;

    case PERF_TALER_MINTDB_DENOMINATION_INFO:
      if (NULL == data->data.dki)
        return;
      PERF_TALER_MINTDB_denomination_free (data->data.dki);
      GNUNET_free (data->data.dki);
      data->data.dki = NULL;
      return;

    default:
      return;
  }
}


/**
 * Copies @a data into @a copy
 *
 * @param data the data to be copied
 * @param[out] copy the copy made
 */
static void
data_copy (const struct PERF_TALER_MINTDB_Data *data, struct PERF_TALER_MINTDB_Data *copy)
{
  copy->type = data->type;
  switch (data->type)
  {
    case PERF_TALER_MINTDB_TIME:
      copy->data.time = GNUNET_new (struct GNUNET_TIME_Absolute);
      *copy->data.time = *data->data.time;
      return;

    case PERF_TALER_MINTDB_DEPOSIT:
      copy->data.deposit =
      PERF_TALER_MINTDB_deposit_copy (data->data.deposit);
      return;

    case PERF_TALER_MINTDB_COIN:
      copy->data.coin =
      PERF_TALER_MINTDB_coin_copy (data->data.coin);
      return;

    case PERF_TALER_MINTDB_RESERVE:
      copy->data.reserve =
      PERF_TALER_MINTDB_reserve_copy (data->data.reserve);
      return;

    case PERF_TALER_MINTDB_DENOMINATION_INFO:
      copy->data.dki =
      PERF_TALER_MINTDB_denomination_copy (data->data.dki);
      return;

    default:
      return;
  }
}


/**
 * Finds the first command in cmd with the name search
 *
 * @return the index of the first command with name search
 * #GNUNET_SYSERR if none found
 */
static int
cmd_find (const struct PERF_TALER_MINTDB_Cmd *cmd, const char *search)
{
  unsigned int i;

  for (i=0; PERF_TALER_MINTDB_CMD_END != cmd[i].command; i++)
    if (0 == strcmp (cmd[i].label, search))
      return i;
  return GNUNET_SYSERR;
}


/**
 * Initialization of a command array
 * 
 * @param cmd the comand array initialized
 */
static int
cmd_init (struct PERF_TALER_MINTDB_Cmd cmd[])
{
  unsigned int i;

  for (i=0; PERF_TALER_MINTDB_CMD_END != cmd[i].command; i++)
  {
    switch (cmd[i].command)
    {
      case PERF_TALER_MINTDB_CMD_SAVE_ARRAY:
        {
          int save_label;

          GNUNET_assert (GNUNET_SYSERR !=
                         (save_label = cmd_find (cmd,
                                                 cmd[i].details.save_array.label_save)));
          /* Allocation of memory for saving data */
          cmd[i].details.save_array.data_saved =
            GNUNET_new_array (cmd[i].details.save_array.nb_saved,
                              struct PERF_TALER_MINTDB_Data);
        }
        break;

      case PERF_TALER_MINTDB_CMD_LOAD_ARRAY:
        /* Creating the permutation array to randomize the data order */
        {
          int save_index;

          GNUNET_assert (GNUNET_SYSERR !=
                         (save_index = cmd_find (
                             cmd,
                             cmd[i].details.load_array.label_save)));
          GNUNET_assert (NULL !=
                         (cmd[i].details.load_array.permutation =
                          GNUNET_CRYPTO_random_permute (
                            GNUNET_CRYPTO_QUALITY_WEAK,
                            cmd[save_index].details.save_array.nb_saved)));
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
  unsigned int i;

  for (i=0; PERF_TALER_MINTDB_CMD_END != cmd[i].command; i++)
  {
    switch (cmd[i].command)
    {
      case PERF_TALER_MINTDB_CMD_SAVE_ARRAY:
        {
          unsigned int j;

          for (j = 0; j < cmd[i].details.save_array.nb_saved; j++)
          {
            data_free (&cmd[i].details.save_array.data_saved[j]);
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
        data_free (&cmd[i].exposed);
        break;

    }
  }
  return GNUNET_OK;
}


/**
 * Handles the command #PERF_TALER_MINTDB_CMD_END_LOOP for the interpreter
 * Cleans the memory at the end of the loop
 */
static void
interpret_end_loop (struct PERF_TALER_MINTDB_interpreter_state *state)
{
  unsigned int i;
  int jump;

  GNUNET_assert (GNUNET_SYSERR !=
                 (jump = cmd_find (state->cmd,
                                   state->cmd[state->i]
                                   .details.end_loop.label_loop)));
  // Cleaning up the memory in the loop
  for (i = jump; i < state->i; i++)
  {
    data_free (&state->cmd[i].exposed);
  }

  state->cmd[jump].details.loop.curr_iteration++;
  /* If the loop is not finished */
  if (state->cmd[jump].details.loop.max_iterations >
      state->cmd[jump].details.loop.curr_iteration)
  {
    /* jump back to the start */
    state->i = jump;
  }
  else
  {
    /* Reset the loop counter and continue running */
    state->cmd[jump].details.loop.curr_iteration = 0;
  }
}


/**
 * Part of the interpreter specific to 
 * #PERF_TALER_MINTDB_CMD_SAVE_ARRAY
 * Saves the data exposed by another command into
 * an array in the command specific struct.
 */
static void
interpret_save_array (struct PERF_TALER_MINTDB_interpreter_state *state)
{
  struct PERF_TALER_MINTDB_Cmd *cmd = &state->cmd[state->i];
  struct PERF_TALER_MINTDB_Cmd *save_ref;
  struct PERF_TALER_MINTDB_Cmd *loop_ref;
  int loop_index;
  int save_index;
  unsigned int selection_chance;

  GNUNET_assert (GNUNET_SYSERR !=
                 (loop_index = cmd_find (state->cmd,
                                         cmd->details.save_array.label_loop)));
  loop_ref = &state->cmd[loop_index];
  GNUNET_assert (GNUNET_SYSERR !=
                 (save_index = cmd_find (state->cmd,
                                         cmd->details.save_array.label_save)));
  save_ref = &state->cmd[save_index];
  /* Array initialization on first loop iteration
     Alows for nested loops */
  if (0 == cmd->details.loop.curr_iteration)
  {
    cmd->details.save_array.index = 0;
  }
  /* The probobility distribution of the saved items will be a little biased
     against the few last items but it should not be a big problem. */
  selection_chance = loop_ref->details.loop.max_iterations /
    cmd->details.save_array.nb_saved;
  /*
   * If the remaining space is equal to the remaining number of
   * iterations, the item is automaticly saved.
   *
   * Else it is saved only if the random numbre generated is 0
   */
  if ( (0 < (cmd->details.save_array.nb_saved -
             cmd->details.save_array.index) ) &&
       ( ((loop_ref->details.loop.max_iterations -
           loop_ref->details.loop.curr_iteration) ==
          (cmd->details.save_array.nb_saved -
           cmd->details.save_array.index)) ||
         (0 == GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                         selection_chance)) ) )
  {
    struct PERF_TALER_MINTDB_Data *save_location;
    struct PERF_TALER_MINTDB_Data *item_saved;

    save_location = &cmd->details.save_array.data_saved[cmd->details.save_array.index];
    item_saved = &save_ref->exposed;
    data_copy (item_saved, save_location);
    cmd->details.save_array.index++;
  }
}


/**
 * Part of the interpreter specific to
 * #PERF_TALER_MINTDB_CMD_LOAD_ARRAY 
 * Gets data from a #PERF_TALER_MINTDB_CMD_SAVE_ARRAY and exposes a copy
 */
static void
interpret_load_array (struct PERF_TALER_MINTDB_interpreter_state *state)
{
  unsigned int loop_iter;
  int loop_index;
  int save_index;
  struct PERF_TALER_MINTDB_Data *loaded_data;

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

    /* In case the iteration number is higher than the amount saved,
     * the number is run several times in the permutation array */
    quotient = loop_iter / state->cmd[save_index].details.save_array.nb_saved;
    loop_iter = loop_iter % state->cmd[save_index].details.save_array.nb_saved;
    for (i=0; i<=quotient; i++)
      loop_iter = state->cmd[state->i].details.load_array.permutation[loop_iter];
  }
  /* Extracting the data from the loop_indexth indice in save_index
   * array.
   */
  loaded_data = &state->cmd[save_index].details.save_array.data_saved[loop_iter];
  data_copy (loaded_data, &state->cmd[state->i].exposed);
}


/**
 * Part of the interpreter specific to 
 * #PERF_TALER_MINTDB_CMD_LOAD_RANDOM
 * Get a random element from a #PERF_TALER_MINTDB_CMD_SAVE_ARRAY and exposes it
 */
static void
interprete_load_random (struct PERF_TALER_MINTDB_interpreter_state *state)
{
  unsigned int index;
  int save_index;

  GNUNET_assert (0 <=
    (save_index  = cmd_find (state->cmd,
                             state->cmd[state->i].details.load_random.label_save)));
   index = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                     state->cmd[save_index].details.save_array.nb_saved);
     data_copy (&state->cmd[save_index].details.save_array.data_saved[index],
                &state->cmd[state->i].exposed);
}

/**
 * Iterate over the commands, acting accordingly at each step
 *
 * @param state the current state of the interpreter
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
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "%s\n",
                    state->cmd[state->i].label);
        break;

      case PERF_TALER_MINTDB_CMD_LOOP:
        break;

      case PERF_TALER_MINTDB_CMD_END_LOOP:
        interpret_end_loop (state);
        break;

      case PERF_TALER_MINTDB_CMD_GET_TIME:
        state->cmd[state->i].exposed.data.time = 
          GNUNET_new (struct GNUNET_TIME_Absolute);
        *state->cmd[state->i].exposed.data.time = 
          GNUNET_TIME_absolute_get ();
        break;

      case PERF_TALER_MINTDB_CMD_GAUGER:
        {
          int start_index, stop_index;
          float ips;
          struct GNUNET_TIME_Absolute start, stop;
          struct GNUNET_TIME_Relative elapsed;
          GNUNET_assert (GNUNET_SYSERR !=
                         (start_index  = cmd_find (state->cmd,
                                                   state->cmd[state->i]
                                                   .details.gauger.label_start)));
          GNUNET_assert (GNUNET_SYSERR !=
                         (stop_index  = cmd_find (state->cmd,
                                                  state->cmd[state->i]
                                                  .details.gauger.label_stop)));
          start = *state->cmd[start_index].exposed.data.time;
          stop = *state->cmd[stop_index].exposed.data.time;
          elapsed = GNUNET_TIME_absolute_get_difference (start,
                                                         stop); 
          ips = (1.0 * state->cmd[state->i].details.gauger.divide) / (elapsed.rel_value_us/1000000.0);
          GAUGER ("MINTDB",
                  state->cmd[state->i].details.gauger.description,
                  ips, 
                  state->cmd[state->i].details.gauger.unit);
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
        state->plugin->rollback (state->plugin->cls,
                                 state->session);
        break;

      case PERF_TALER_MINTDB_CMD_SAVE_ARRAY:
        interpret_save_array (state);
        break;

      case PERF_TALER_MINTDB_CMD_LOAD_ARRAY:
        interpret_load_array (state);
        break;

      case PERF_TALER_MINTDB_CMD_LOAD_RANDOM:
        interprete_load_random (state);
        break;

      case PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT:
        {
          int coin_index;
          struct TALER_MINTDB_Deposit *deposit;

          GNUNET_assert (GNUNET_SYSERR !=
                         (coin_index = cmd_find (state->cmd,
                                               state->cmd[state->i].details.insert_deposit.label_coin)));
          GNUNET_assert (NULL !=
                         (deposit = PERF_TALER_MINTDB_deposit_init (state->cmd[coin_index].exposed.data.coin)));

          GNUNET_assert (GNUNET_OK ==
            state->plugin->insert_deposit (state->plugin->cls,
                                           state->session,
                                           deposit));
          state->cmd[state->i].exposed.data.deposit = deposit;
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_DEPOSIT:
        {
          int source_index;
          struct PERF_TALER_MINTDB_Data data;

          source_index =  cmd_find (state->cmd,
                                    state->cmd[state->i].details.get_deposit.label_deposit);
          GNUNET_assert (GNUNET_SYSERR != source_index);
          data = state->cmd[source_index].exposed;
          state->plugin->have_deposit (state->plugin->cls,
                                       state->session,
                                       data.data.deposit);
        }
        break;

      case PERF_TALER_MINTDB_CMD_INSERT_RESERVE:
        {
          struct PERF_TALER_MINTDB_Reserve *reserve;
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
            &reserve->reserve.pub,
            &reserve->reserve.balance,
            GNUNET_TIME_absolute_get (),
            details
            );
          json_decref (details);
          state->cmd[state->i].exposed.data.reserve = reserve;
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_RESERVE:
        {
          int reserve_index;
          struct PERF_TALER_MINTDB_Data data;

          GNUNET_assert (GNUNET_SYSERR !=
                         (reserve_index = cmd_find (state->cmd,
                                                   state->cmd[state->i]
                                                   .details.get_reserve.label_reserve)));
          data_copy (&state->cmd[reserve_index].exposed,
                     &data);
          GNUNET_assert (GNUNET_OK ==
                         (state->plugin->reserve_get (state->plugin->cls,
                                                      state->session,
                                                      &data.data.reserve->reserve)));
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_RESERVE_HISTORY:
        {
         int reserve_index;
         struct TALER_MINTDB_ReserveHistory *history; 
         struct PERF_TALER_MINTDB_Data data;

         GNUNET_assert (GNUNET_SYSERR !=
                        (reserve_index = cmd_find (state->cmd,
                                                   state->cmd[state->i]
                                                   .details.get_reserve_history.label_reserve)));
         data_copy (&state->cmd[reserve_index].exposed,
                    &data);
         GNUNET_assert (NULL !=
                        (history = state->plugin->get_reserve_history (state->plugin->cls,
                                                                       state->session,
                                                                       &data.data.reserve->reserve.pub)));
         state->plugin->free_reserve_history (state->plugin->cls,
                                              history);
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
          state->cmd[state->i].exposed.data.dki = dki;
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_DENOMINATION:
        {
          int source_index;
          struct PERF_TALER_MINTDB_Data data;

          GNUNET_assert (GNUNET_SYSERR !=
                         (source_index =  cmd_find (state->cmd,
                                                    state->cmd[state->i]
                                                    .details.get_denomination.label_denom)));
          data_copy (&state->cmd[source_index].exposed,
                     &data);
          state->plugin->get_denomination_info (state->plugin->cls,
                                                state->session,
                                                &data.data.dki->denom_pub,
                                                &data.data.dki->issue);
        }
        break;

      case PERF_TALER_MINTDB_CMD_INSERT_WITHDRAW:
        {
          int dki_index, reserve_index;
          struct PERF_TALER_MINTDB_Coin *coin ;

          GNUNET_assert (GNUNET_SYSERR !=
                         (dki_index = cmd_find (
                             state->cmd,
                             state->cmd[state->i].details.insert_withdraw.label_dki)));
          GNUNET_assert (GNUNET_SYSERR !=
                         (reserve_index = cmd_find (
                             state->cmd,
                             state->cmd[state->i].details.insert_withdraw.label_reserve)));
          GNUNET_assert (NULL !=
                         (coin =
                          PERF_TALER_MINTDB_coin_init (
                            state->cmd[dki_index].exposed.data.dki,
                            state->cmd[reserve_index].exposed.data.reserve)));

          state->plugin->insert_withdraw_info (state->plugin->cls,
                                               state->session,
                                               &coin->blind);
          state->cmd[state->i].exposed.data.coin = coin;
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_WITHDRAW:
        {
          int source_index;
          struct PERF_TALER_MINTDB_Data data;

          GNUNET_assert (GNUNET_SYSERR !=
                         (source_index = cmd_find (state->cmd,
                                                   state->cmd[state->i]
                                                   .details.get_denomination.label_denom)));
          data_copy (&state->cmd[source_index].exposed,
                     &data);
          state->plugin->get_withdraw_info (state->plugin->cls,
                                            state->session,
                                            &data.data.coin->blind.h_coin_envelope,
                                            &data.data.coin->blind);
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_COIN_TRANSACTION:
        {
          int coin_index;
          struct PERF_TALER_MINTDB_Coin *coin;
          struct TALER_MINTDB_TransactionList *transactions;
          
          coin_index = cmd_find (state->cmd,
                                 state->cmd[state->i].details.get_coin_transaction.label_coin);
          GNUNET_assert (GNUNET_SYSERR != coin_index);
          coin = state->cmd[coin_index].exposed.data.coin;
          transactions = state->plugin->get_coin_transactions (state->plugin->cls,
                                                               state->session,
                                                               &coin->public_info.coin_pub);
          state->plugin->free_coin_transaction_list (state->plugin->cls,
                                                     transactions);
        }
        break;

      case PERF_TALER_MINTDB_CMD_CREATE_REFRESH_SESSION:
        {
          struct GNUNET_HashCode hash;
          struct TALER_MINTDB_RefreshSession *refresh_session;

          refresh_session = PERF_TALER_MINTDB_refresh_session_init ();
          GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
                                            &hash);
          state->plugin->create_refresh_session (state->session,
                                                 state->session,
                                                 &hash,
                                                 refresh_session);
          state->cmd[state->i].exposed.data.session_hash = hash;
          PERF_TALER_MINTDB_refresh_session_free (refresh_session);
          GNUNET_free (refresh_session);
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_REFRESH_SESSION:
        {
          int hash_index;
          struct GNUNET_HashCode hash;
          struct TALER_MINTDB_RefreshSession refresh;

          hash_index = cmd_find (state->cmd,
                                 state->cmd[state->i].details.get_refresh_session.label_hash);
          hash = state->cmd[hash_index].exposed.data.session_hash;
          state->plugin->get_refresh_session (state->session,
                                              state->session,
                                              &hash,
                                              &refresh);
        }
        break;

      case PERF_TALER_MINTDB_CMD_INSERT_REFRESH_MELT:
        {
          int hash_index;
          int coin_index;
          struct GNUNET_HashCode hash;
          struct TALER_MINTDB_RefreshMelt *melt;
          struct PERF_TALER_MINTDB_Coin *coin;

          hash_index = cmd_find (state->cmd,
                                 state->cmd[state->i].details.insert_refresh_melt.label_hash);
          coin_index = cmd_find (state->cmd,
                                 state->cmd[state->i].details.insert_refresh_melt.label_coin);
          hash = state->cmd[hash_index].exposed.data.session_hash;
          coin = state->cmd[coin_index].exposed.data.coin;
          melt = PERF_TALER_MINTDB_refresh_melt_init (&hash,
                                                      coin);
          state->plugin->insert_refresh_melt (state->plugin->cls,
                                              state->session,
                                              1,
                                              melt);
          state->cmd[state->i].exposed.data.session_hash = hash;
        }
        break;

      case PERF_TALER_MINTDB_CMD_GET_REFRESH_MELT:
        {
          int hash_index;
          struct GNUNET_HashCode hash;
          struct TALER_MINTDB_RefreshMelt melt;
          
          hash_index = cmd_find (state->cmd,
                                 state->cmd[state->i].details.get_refresh_melt.label_hash);
          hash = state->cmd[hash_index].exposed.data.session_hash;
          state->plugin->get_refresh_melt (state->plugin->cls,
                                           state->session,
                                           &hash,
                                           1,
                                           &melt);
        }
        break;

      default:
        break;
    }
  }
  return GNUNET_OK;
}


/**
 * Runs the commands given in @a cmd, working with
 * the database referenced by @a db_plugin
 * 
 * @param db_plugin the connection to the database
 * @param cmd the commands to run
 */
int
PERF_TALER_MINTDB_interpret (struct TALER_MINTDB_Plugin *db_plugin,
                             struct PERF_TALER_MINTDB_Cmd cmd[])
{
  struct PERF_TALER_MINTDB_interpreter_state state =
  {.i = 0, .cmd = cmd, .plugin = db_plugin};

  cmd_init (state.cmd);
  GNUNET_assert (NULL !=
                 (state.session = db_plugin->get_session (db_plugin->cls,
                                                          GNUNET_YES)));
  interpret (&state);
  cmd_clean (cmd);
  return GNUNET_OK;
}


/**
 * Initialize the database and run the benchmark
 *
 * @param benchmark_name the name of the benchmark, displayed in the logs
 * @param configuration_file path to the taler configuration file to use
 * @param init the commands to use for the database initialisation, 
 * if #NULL the standard initialization is used
 * @param benchmark the commands for the benchmark
 * @return #GNUNET_OK upon success; GNUNET_SYSERR upon failure
 */
int
PERF_TALER_MINTDB_run_benchmark (const char *benchmark_name,
                                 const char *configuration_file,
                                 struct PERF_TALER_MINTDB_Cmd *init,
                                 struct PERF_TALER_MINTDB_Cmd *benchmark)
{
  struct TALER_MINTDB_Plugin *plugin;
  struct GNUNET_CONFIGURATION_Handle *config;
  int ret = 0;
  struct PERF_TALER_MINTDB_Cmd init_def[] = 
  {
    // Denomination used to create coins
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("00 - Start of interpreter"),

    PERF_TALER_MINTDB_INIT_CMD_LOOP ("01 - denomination loop",
                                     PERF_TALER_MINTDB_NB_DENOMINATION_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_DENOMINATION ("01 - denomination"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("01 - save denomination",
                                           "01 - denomination loop",
                                           "01 - denomination",
                                           PERF_TALER_MINTDB_NB_DENOMINATION_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "01 - denomination loop"),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("01 - init denomination complete"),
    // End of initialization
    // Reserve initialization
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("02 - init reserve loop",
                                     PERF_TALER_MINTDB_NB_RESERVE_INIT),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_RESERVE ("02 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("02 - save reserve",
                                           "02 - init reserve loop",
                                           "02 - reserve",
                                           PERF_TALER_MINTDB_NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "02 - init reserve loop"),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("02 - reserve init complete"),
    // End reserve init
    // Withdrawal initialization
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("03 - init withdraw loop",
                                     PERF_TALER_MINTDB_NB_WITHDRAW_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("03 - denomination load",
                                           "03 - init withdraw loop",
                                           "01 - save denomination"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("03 - reserve load",
                                           "03 - init withdraw loop",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_WITHDRAW ("03 - withdraw",
                                                "03 - denomination load",
                                                "03 - reserve load"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("03 - save coin",
                                           "03 - init withdraw loop",
                                           "03 - withdraw",
                                           PERF_TALER_MINTDB_NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "03 - init withdraw loop"),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("03 - withdraw init complete"),
    //End of withdrawal initialization
    //Deposit initialization
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("04 - deposit init loop",
                                     PERF_TALER_MINTDB_NB_DEPOSIT_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION ("04 - start transaction"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("04 - denomination load",
                                           "04 - deposit init loop",
                                           "03 - save coin"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_DEPOSIT ("04 - deposit",
                                               "04 - denomination load"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION ("04 - commit transaction"),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("04 - deposit array",
                                           "04 - deposit init loop",
                                           "04 - deposit",
                                           PERF_TALER_MINTDB_NB_DEPOSIT_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("04 - deposit init loop end",
                                         "04 - deposit init loop"),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("04 - deposit init complete"),
    // End of deposit initialization
    PERF_TALER_MINTDB_INIT_CMD_END ("end")
  };

  GNUNET_log_setup (benchmark_name,
                    "INFO",
                    NULL);
  config = GNUNET_CONFIGURATION_create ();

  ret = GNUNET_CONFIGURATION_load (config, 
                                   configuration_file);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error parsing configuration file");
    return GNUNET_SYSERR;
  }
  plugin = TALER_MINTDB_plugin_load (config);
  if (NULL == plugin)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error connectiong to the database");
    return ret;
  }
  ret = plugin->create_tables (plugin->cls, 
                               GNUNET_YES);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error while creating the database architecture");
    return ret;
  }
  /* 
   * Running the initialization
   */
  if (NULL == init)
  {
    init = init_def;   
  }
  if (GNUNET_SYSERR == PERF_TALER_MINTDB_check (init))
    return GNUNET_SYSERR;

  ret = PERF_TALER_MINTDB_interpret (plugin, 
                                     init);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error during database initialization");
    return ret;
  }
  /*
   * Running the benchmark
   */
  if (GNUNET_SYSERR == PERF_TALER_MINTDB_check (benchmark))
    return GNUNET_SYSERR;
  ret = PERF_TALER_MINTDB_interpret (plugin, 
                                     benchmark);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error while runing the benchmark");
    return ret;
  }
  /* Drop tables */
  {
    struct TALER_MINTDB_Session *session;

    session = plugin->get_session (plugin->cls, 
                                   GNUNET_YES);
    ret = plugin->drop_temporary (plugin->cls, 
                                  session);
    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Error removing cleaning the database");
      return ret;
    }
  }
  TALER_MINTDB_plugin_unload (plugin);
  GNUNET_CONFIGURATION_destroy (config);

  return ret;
}


/**
 * Tests if @a label is reference to a command of @a cmd
 * Prints an error containing @a desc if a problem occurs 
 * 
 * @param cmd the cmd array checked
 * @param label the label checked 
 * @param i the index of the command beeing checked (used for error reporting
 * @param desc a description of the label checked 
 */
static int
find_test (const struct PERF_TALER_MINTDB_Cmd *cmd,
           const char *label,
           const unsigned int i,
           const char *desc)
{
    int ret;

    ret = cmd_find (cmd, label);
    if (GNUNET_SYSERR == ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Error at %s:index %d wrong label for %s",
                  cmd[i].label,
                  i,
                  desc);
    }
    return ret;
}


/**
 * Check if the given command array is syntaxicly correct
 * This will check if the label are corrects but will not check if
 * they are pointing to an apropriate command.
 *
 * @param cmd the command array to check
 * @return #GNUNET_OK is @a cmd is correct; #GNUNET_SYSERR if it is'nt
 */
int
PERF_TALER_MINTDB_check (const struct PERF_TALER_MINTDB_Cmd *cmd)
{
  unsigned int i;
  int ret = GNUNET_OK;

  for (i = 0; PERF_TALER_MINTDB_CMD_END != cmd[i].command; i++)
  {
    int ret_loc = GNUNET_OK;
    switch (cmd[i].command)
    {
      case PERF_TALER_MINTDB_CMD_END_LOOP:
        ret_loc = find_test (cmd,
                   cmd[i].details.end_loop.label_loop,
                   i,
                   "label_loop");
        break;

      case PERF_TALER_MINTDB_CMD_GAUGER:
        ret_loc = find_test (cmd,
                   cmd[i].details.gauger.label_start,
                   i,
                   "label_start");
        break;

      case PERF_TALER_MINTDB_CMD_SAVE_ARRAY:
        ret_loc = find_test (cmd,
                   cmd[i].details.save_array.label_loop,
                   i,
                   "label_loop");
        ret_loc = find_test (cmd,
                   cmd[i].details.save_array.label_save,
                   i,
                   "label_save");
        break;

      case PERF_TALER_MINTDB_CMD_LOAD_ARRAY:
        ret_loc = find_test (cmd,
                   cmd[i].details.load_array.label_loop,
                   i,
                   "label_loop");
        ret_loc = find_test (cmd,
                   cmd[i].details.load_array.label_save,
                   i,
                   "label_save");  
        break;

      case PERF_TALER_MINTDB_CMD_GET_DENOMINATION:
        ret_loc = find_test (cmd,
                   cmd[i].details.get_denomination.label_denom,
                   i,
                   "label_denom");
        break;

      case PERF_TALER_MINTDB_CMD_GET_RESERVE:
        ret_loc = find_test (cmd,
                   cmd[i].details.get_reserve.label_reserve,
                   i,
                   "label_reserve");
        break;

      case PERF_TALER_MINTDB_CMD_INSERT_DEPOSIT:
        ret_loc = find_test (cmd,
                   cmd[i].details.insert_deposit.label_coin,
                   i,
                   "label_dki");
        break;
      
      case PERF_TALER_MINTDB_CMD_GET_DEPOSIT:
        ret_loc = find_test (cmd,
                   cmd[i].details.get_deposit.label_deposit,
                   i,
                   "label_deposit");
        break;

      case PERF_TALER_MINTDB_CMD_INSERT_WITHDRAW:
        ret_loc = find_test (cmd,
                   cmd[i].details.insert_withdraw.label_dki,
                   i,
                   "label_dki");
        break;

      case PERF_TALER_MINTDB_CMD_GET_WITHDRAW:
        ret_loc = find_test (cmd,
                   cmd[i].details.get_withdraw.label_coin,
                   i,
                   "label_coin");
        break;

      default :
        break;
    }
    if (GNUNET_OK == ret)
      ret = (GNUNET_SYSERR == ret_loc)?GNUNET_SYSERR:GNUNET_OK;
  }
  return ret;
}
