/*
   This file is part of TALER
   Copyright (C) 2014-2017 GNUnet e.V.

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
   */
/**
 * @file exchangedb/perf_taler_exchangedb_interpreter.c
 * @brief Interpreter library for exchange database performance analysis
 * @author Nicolas Fournier
 */
#include "platform.h"
#include "perf_taler_exchangedb_interpreter.h"
#include "perf_taler_exchangedb_init.h"
#include "gauger.h"


/**
 * Represents the state of the interpreter
 */
struct PERF_TALER_EXCHANGEDB_interpreter_state
{
  /**
   * State of the commands
   */
  struct PERF_TALER_EXCHANGEDB_Cmd *cmd;

  /**
   * Database plugin
   */
  struct TALER_EXCHANGEDB_Plugin *plugin;

  /**
   * Current database session
   */
  struct TALER_EXCHANGEDB_Session *session;

  /**
   * The current index of the interpreter
   */
  unsigned int i;
};


/**
 * Free the memory of @a data
 */
static void
data_free (struct PERF_TALER_EXCHANGEDB_Data *data)
{
  switch (data->type)
  {
    case PERF_TALER_EXCHANGEDB_TIME:
      if (NULL == data->data.time)
        break;
      GNUNET_free (data->data.time);
      data->data.time = NULL;
      break;

    case PERF_TALER_EXCHANGEDB_DEPOSIT:
      if (NULL == data->data.deposit)
        break;
      PERF_TALER_EXCHANGEDB_deposit_free (data->data.deposit);
      data->data.deposit = NULL;
      break;

    case PERF_TALER_EXCHANGEDB_COIN:
      if (NULL == data->data.coin)
        break;
      PERF_TALER_EXCHANGEDB_coin_free (data->data.coin);
      data->data.coin = NULL;
      break;

    case PERF_TALER_EXCHANGEDB_RESERVE:
      if (NULL == data->data.reserve)
        break;
      PERF_TALER_EXCHANGEDB_reserve_free (data->data.reserve);
      data->data.reserve = NULL;
      break;

    case PERF_TALER_EXCHANGEDB_DENOMINATION_INFO:
      if (NULL == data->data.dki)
        break;
      PERF_TALER_EXCHANGEDB_denomination_free (data->data.dki);
      data->data.dki = NULL;
      break;

    case PERF_TALER_EXCHANGEDB_REFRESH_HASH:
      if (NULL == data->data.session_hash)
        break;
      GNUNET_free (data->data.session_hash);
      data->data.session_hash = NULL;
      break;

    case PERF_TALER_EXCHANGEDB_NONE:
      break;
  }
}


/**
 * Copies @a data into @a copy
 *
 * @param data the data to be copied
 * @param[out] copy the copy made
 */
static void
data_copy (const struct PERF_TALER_EXCHANGEDB_Data *data,
           struct PERF_TALER_EXCHANGEDB_Data *copy)
{
  copy->type = data->type;
  switch (data->type)
  {
    case PERF_TALER_EXCHANGEDB_TIME:
      copy->data.time = GNUNET_new (struct GNUNET_TIME_Absolute);
      *copy->data.time = *data->data.time;
      return;

    case PERF_TALER_EXCHANGEDB_DEPOSIT:
      copy->data.deposit
        = PERF_TALER_EXCHANGEDB_deposit_copy (data->data.deposit);
      return;

    case PERF_TALER_EXCHANGEDB_COIN:
      copy->data.coin
        = PERF_TALER_EXCHANGEDB_coin_copy (data->data.coin);
      return;

    case PERF_TALER_EXCHANGEDB_RESERVE:
      copy->data.reserve
        = PERF_TALER_EXCHANGEDB_reserve_copy (data->data.reserve);
      return;

    case PERF_TALER_EXCHANGEDB_DENOMINATION_INFO:
      copy->data.dki
        = PERF_TALER_EXCHANGEDB_denomination_copy (data->data.dki);
      return;

    case PERF_TALER_EXCHANGEDB_REFRESH_HASH:
      copy-> data.session_hash = GNUNET_new (struct GNUNET_HashCode);
      *copy->data.session_hash
        = *data->data.session_hash;
      break;

    case PERF_TALER_EXCHANGEDB_NONE:
      break;
  }
}


/**
 * Finds the first command in cmd with the name search
 *
 * @return the index of the first command with name search
 * #GNUNET_SYSERR if none found
 */
static int
cmd_find (const struct PERF_TALER_EXCHANGEDB_Cmd *cmd,
          const char *search)
{
  unsigned int i;

  for (i=0; PERF_TALER_EXCHANGEDB_CMD_END != cmd[i].command; i++)
    if (0 == strcmp (cmd[i].label, search))
      return i;
  return GNUNET_SYSERR;
}


/**
 * Initialization of a command array
 * and check for the type of the label
 *
 * @param cmd the comand array initialized
 * @return #GNUNET_OK if the initialization was sucessful
 * #GNUNET_SYSERR if there was a probleb. See the log for details
 */
static int
cmd_init (struct PERF_TALER_EXCHANGEDB_Cmd cmd[])
{
  unsigned int i;

  for (i=0; PERF_TALER_EXCHANGEDB_CMD_END != cmd[i].command; i++)
  {
    switch (cmd[i].command)
    {
      case PERF_TALER_EXCHANGEDB_CMD_END_LOOP:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.end_loop.label_loop);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.end_loop.label_loop);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_CMD_LOOP != cmd[ret].command)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.end_loop.label_loop);
            return GNUNET_SYSERR;
          }
          cmd[i].details.end_loop.index_loop = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_SAVE_ARRAY:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.save_array.label_save);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.save_array.label_save);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_NONE == cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.save_array.label_save);
            return GNUNET_SYSERR;
          }
          cmd[i].details.save_array.index_save = ret;

          ret = cmd_find (cmd,
                          cmd[i].details.save_array.label_loop);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.save_array.label_loop);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_CMD_LOOP != cmd[ret].command)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.save_array.label_loop);
            return GNUNET_SYSERR;
          }
          cmd[i].details.save_array.index_loop = ret;

          GNUNET_assert (NULL == cmd[i].details.save_array.data_saved);
          cmd[i].details.save_array.data_saved =
            GNUNET_new_array (cmd[i].details.save_array.nb_saved,
                              struct PERF_TALER_EXCHANGEDB_Data);
          cmd[i].details.save_array.type_saved =
            cmd[cmd[i].details.save_array.index_save].exposed.type;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_LOAD_ARRAY:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.load_array.label_save);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.load_array.label_save);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_CMD_SAVE_ARRAY != cmd[ret].command)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.load_array.label_save);
            return GNUNET_SYSERR;
          }
          cmd[i].details.load_array.index_save = ret;

          ret = cmd_find (cmd,
                          cmd[i].details.load_array.label_loop);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.load_array.label_loop);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_CMD_LOOP != cmd[ret].command)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.load_array.label_loop);
            return GNUNET_SYSERR;
          }
          cmd[i].details.load_array.index_loop = ret;

          cmd[i].details.load_array.permutation =
            GNUNET_CRYPTO_random_permute (
              GNUNET_CRYPTO_QUALITY_WEAK,
              cmd[cmd[i].details.load_array.index_save].details.save_array.nb_saved);
          GNUNET_assert (NULL != cmd[i].details.load_array.permutation);

          cmd[i].exposed.type = cmd[cmd[i].details.load_array.index_save].details.save_array.type_saved;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_LOAD_RANDOM:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.load_random.label_save);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.load_random.label_save);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_CMD_SAVE_ARRAY != cmd[ret].command)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.load_random.label_save);
            return GNUNET_SYSERR;
          }
          cmd[i].details.load_random.index_save = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GAUGER:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.gauger.label_start);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.gauger.label_start);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_TIME != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.gauger.label_start);
            return GNUNET_SYSERR;
          }
          cmd[i].details.gauger.index_start = ret;

          ret = cmd_find (cmd,
                          cmd[i].details.gauger.label_stop);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.gauger.label_stop);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_TIME != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.gauger.label_stop);
            return GNUNET_SYSERR;
          }
          cmd[i].details.gauger.index_stop = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_DENOMINATION:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.insert_denomination.label_denom);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.insert_denomination.label_denom);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_DENOMINATION_INFO != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.insert_denomination.label_denom);
            return GNUNET_SYSERR;
          }
          cmd[i].details.insert_denomination.index_denom = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_DENOMINATION:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.get_denomination.label_denom);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_denomination.label_denom);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_DENOMINATION_INFO != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_denomination.label_denom);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_denomination.index_denom = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_RESERVE:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.insert_reserve.label_reserve);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.insert_reserve.label_reserve);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_RESERVE != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.insert_reserve.label_reserve);
            return GNUNET_SYSERR;
          }
          cmd[i].details.insert_reserve.index_reserve = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_RESERVE:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.get_reserve.label_reserve);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_reserve.label_reserve);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_RESERVE != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_reserve.label_reserve);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_reserve.index_reserve = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_RESERVE_HISTORY:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.get_reserve_history.label_reserve);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_reserve_history.label_reserve);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_RESERVE != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_reserve_history.label_reserve);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_reserve_history.index_reserve = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_CREATE_WITHDRAW:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.create_withdraw.label_dki);
          {
            if (GNUNET_SYSERR == ret)
            {
              GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                          "%d:Undefined reference to %s\n",
                          i,
                          cmd[i].details.create_withdraw.label_dki);
              return GNUNET_SYSERR;
            }
            if (PERF_TALER_EXCHANGEDB_DENOMINATION_INFO != cmd[ret].exposed.type)
            {
              GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                          "%d:Wrong type reference to %s\n",
                          i,
                          cmd[i].details.create_withdraw.label_dki);
              return GNUNET_SYSERR;
            }
          }
          cmd[i].details.create_withdraw.index_dki = ret;
          ret = cmd_find (cmd,
                          cmd[i].details.create_withdraw.label_reserve);
          {
            if (GNUNET_SYSERR == ret)
            {
              GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                          "%d:Undefined reference to %s\n",
                          i,
                          cmd[i].details.create_withdraw.label_reserve);
              return GNUNET_SYSERR;
            }
            if (PERF_TALER_EXCHANGEDB_RESERVE != cmd[ret].exposed.type)
            {
              GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                          "%d:Wrong type reference to %s\n",
                          i,
                          cmd[i].details.create_withdraw.label_reserve);
              return GNUNET_SYSERR;
            }
          }
          cmd[i].details.create_withdraw.index_reserve = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_WITHDRAW:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.insert_withdraw.label_coin);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.insert_withdraw.label_coin);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_COIN != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.insert_withdraw.label_coin);
            return GNUNET_SYSERR;
          }
          cmd[i].details.insert_withdraw.index_coin = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_WITHDRAW:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.get_withdraw.label_coin);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_withdraw.label_coin);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_COIN != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_withdraw.label_coin);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_withdraw.index_coin = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_COIN_TRANSACTION:
        {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.get_coin_transaction.label_coin);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_coin_transaction.label_coin);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_COIN != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_coin_transaction.label_coin);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_coin_transaction.index_coin = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_CREATE_DEPOSIT:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.create_deposit.label_coin);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.create_deposit.label_coin);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_COIN != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.create_deposit.label_coin);
            return GNUNET_SYSERR;
          }
          cmd[i].details.create_deposit.index_coin = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_DEPOSIT:
        {
          int ret;

          ret = cmd_find( cmd,
                          cmd[i].details.insert_deposit.label_deposit);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.insert_deposit.label_deposit);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_DEPOSIT != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.insert_deposit.label_deposit);
            return GNUNET_SYSERR;
          }
          cmd[i].details.insert_deposit.index_deposit = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_DEPOSIT:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.get_deposit.label_deposit);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_deposit.label_deposit);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_DEPOSIT != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_deposit.label_deposit);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_deposit.index_deposit = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_REFRESH_SESSION:
        {
          int ret;

          ret = cmd_find (cmd,
                          cmd[i].details.get_refresh_session.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_refresh_session.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_refresh_session.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_refresh_session.index_hash = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_REFRESH_ORDER:
        {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.insert_refresh_order.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.insert_refresh_order.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.insert_refresh_order.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.insert_refresh_order.index_hash = ret;

          ret = cmd_find (cmd,
                          cmd[i].details.insert_refresh_order.label_denom);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.insert_refresh_order.label_denom);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_DENOMINATION_INFO != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.insert_refresh_order.label_denom);
            return GNUNET_SYSERR;
          }
          cmd[i].details.insert_refresh_order.index_denom = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_REFRESH_ORDER:
        {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.get_refresh_order.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_refresh_order.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_refresh_order.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_refresh_order.index_hash = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_REFRESH_COMMIT_COIN:
       {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.insert_refresh_commit_coin.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.insert_refresh_commit_coin.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.insert_refresh_commit_coin.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.insert_refresh_commit_coin.index_hash = ret;
        }
       break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_REFRESH_COMMIT_COIN:
       {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.get_refresh_commit_coin.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_refresh_commit_coin.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_refresh_commit_coin.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_refresh_commit_coin.index_hash = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_REFRESH_COMMIT_LINK:
       {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.insert_refresh_commit_link.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.insert_refresh_commit_link.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.insert_refresh_commit_link.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.insert_refresh_commit_link.index_hash = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_REFRESH_COMMIT_LINK:
       {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.get_refresh_commit_link.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_refresh_commit_link.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_refresh_commit_link.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_refresh_commit_link.index_hash = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_MELT_COMMITMENT:
       {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.get_melt_commitment.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_melt_commitment.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_melt_commitment.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_melt_commitment.index_hash = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_REFRESH_OUT:
       {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.insert_refresh_out.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.insert_refresh_out.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.insert_refresh_out.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.insert_refresh_out.index_hash = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_LINK_DATA_LIST:
       {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.get_link_data_list.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_link_data_list.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_link_data_list.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_link_data_list.index_hash = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_TRANSFER:
       {
          int ret;
          ret = cmd_find (cmd,
                          cmd[i].details.get_transfer.label_hash);
          if (GNUNET_SYSERR == ret)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Undefined reference to %s\n",
                        i,
                        cmd[i].details.get_transfer.label_hash);
            return GNUNET_SYSERR;
          }
          if (PERF_TALER_EXCHANGEDB_REFRESH_HASH != cmd[ret].exposed.type)
          {
            GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                        "%d:Wrong type reference to %s\n",
                        i,
                        cmd[i].details.get_transfer.label_hash);
            return GNUNET_SYSERR;
          }
          cmd[i].details.get_transfer.index_hash = ret;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_END:
      case PERF_TALER_EXCHANGEDB_CMD_DEBUG:
      case PERF_TALER_EXCHANGEDB_CMD_LOOP:
      case PERF_TALER_EXCHANGEDB_CMD_NEW_SESSION:
      case PERF_TALER_EXCHANGEDB_CMD_START_TRANSACTION:
      case PERF_TALER_EXCHANGEDB_CMD_COMMIT_TRANSACTION:
      case PERF_TALER_EXCHANGEDB_CMD_ABORT_TRANSACTION:
      case PERF_TALER_EXCHANGEDB_CMD_GET_TIME:
      case PERF_TALER_EXCHANGEDB_CMD_CREATE_DENOMINATION:
      case PERF_TALER_EXCHANGEDB_CMD_CREATE_RESERVE:
      case PERF_TALER_EXCHANGEDB_CMD_CREATE_REFRESH_SESSION:
        break;
    }
  }
  return GNUNET_OK;
}


/**
 * Free the memory of the command chain
 */
static int
cmd_clean (struct PERF_TALER_EXCHANGEDB_Cmd cmd[])
{
  unsigned int i;

  for (i=0; PERF_TALER_EXCHANGEDB_CMD_END != cmd[i].command; i++)
  {
    switch (cmd[i].command)
    {
      case PERF_TALER_EXCHANGEDB_CMD_SAVE_ARRAY:
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

      case PERF_TALER_EXCHANGEDB_CMD_LOAD_ARRAY:
        GNUNET_free (cmd[i].details.load_array.permutation);
        cmd[i].details.load_array.permutation = NULL;
        break;

      default:
        break;
    }
    data_free (&cmd[i].exposed);
  }
  return GNUNET_OK;
}


/**
 * Handles the command #PERF_TALER_EXCHANGEDB_CMD_END_LOOP for the interpreter
 * Cleans the memory at the end of the loop
 */
static void
interpret_end_loop (struct PERF_TALER_EXCHANGEDB_interpreter_state *state)
{
  unsigned int i;
  int jump;

  jump = state->cmd[state->i].details.end_loop.index_loop;
  // Cleaning up the memory in the loop
  for (i = jump; i < state->i; i++)
    data_free (&state->cmd[i].exposed);

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
 * #PERF_TALER_EXCHANGEDB_CMD_SAVE_ARRAY
 * Saves the data exposed by another command into
 * an array in the command specific struct.
 */
static void
interpret_save_array (struct PERF_TALER_EXCHANGEDB_interpreter_state *state)
{
  struct PERF_TALER_EXCHANGEDB_Cmd *cmd = &state->cmd[state->i];
  struct PERF_TALER_EXCHANGEDB_Cmd *save_ref;
  struct PERF_TALER_EXCHANGEDB_Cmd *loop_ref;
  int loop_index;
  int save_index;
  unsigned int selection_chance;

  loop_index = cmd->details.save_array.index_loop;
  save_index = cmd->details.save_array.index_save;
  loop_ref = &state->cmd[loop_index];
  save_ref = &state->cmd[save_index];
  /* Array initialization on first loop iteration
     Alows for nested loops */
  if (0 == cmd->details.loop.curr_iteration)
  {
    cmd->details.save_array.index = 0;
  }
  /* The probability distribution of the saved items will be a little biased
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
    struct PERF_TALER_EXCHANGEDB_Data *save_location;
    struct PERF_TALER_EXCHANGEDB_Data *item_saved;

    save_location = &cmd->details.save_array.data_saved[cmd->details.save_array.index];
    item_saved = &save_ref->exposed;
    data_copy (item_saved, save_location);
    cmd->details.save_array.index++;
  }
}


/**
 * Part of the interpreter specific to
 * #PERF_TALER_EXCHANGEDB_CMD_LOAD_ARRAY
 * Gets data from a #PERF_TALER_EXCHANGEDB_CMD_SAVE_ARRAY and exposes a copy
 */
static void
interpret_load_array (struct PERF_TALER_EXCHANGEDB_interpreter_state *state)
{
  struct PERF_TALER_EXCHANGEDB_Cmd *cmd = &state->cmd[state->i];
  unsigned int loop_iter;
  int loop_index;
  int save_index;
  struct PERF_TALER_EXCHANGEDB_Data *loaded_data;

  loop_index = cmd->details.load_array.index_loop;
  save_index = cmd->details.load_array.index_save;
  loop_iter = state->cmd[loop_index].details.loop.curr_iteration;
  {
    unsigned int i;
    unsigned int quotient;

    /* In case the iteration number is higher than the amount saved,
     * the number is run several times in the permutation array */
    quotient = loop_iter / state->cmd[save_index].details.save_array.nb_saved;
    loop_iter = loop_iter % state->cmd[save_index].details.save_array.nb_saved;
    for (i=0; i<=quotient; i++)
      loop_iter = cmd->details.load_array.permutation[loop_iter];
  }
  /* Extracting the data from the loop_indexth indice in save_index
   * array.
   */
  loaded_data = &state->cmd[save_index].details.save_array.data_saved[loop_iter];
  data_copy (loaded_data,
             &cmd->exposed);
}


/**
 * Part of the interpreter specific to
 * #PERF_TALER_EXCHANGEDB_CMD_LOAD_RANDOM
 * Get a random element from a #PERF_TALER_EXCHANGEDB_CMD_SAVE_ARRAY and exposes it
 */
static void
interprete_load_random (struct PERF_TALER_EXCHANGEDB_interpreter_state *state)
{
  struct PERF_TALER_EXCHANGEDB_Cmd *cmd = &state->cmd[state->i];
  unsigned int index;
  int save_index;

  save_index = cmd->details.load_random.index_save;
  index = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                    state->cmd[save_index].details.save_array.nb_saved);
  data_copy (&state->cmd[save_index].details.save_array.data_saved[index],
             &cmd->exposed);
}


/**
 * Iterate over the commands, acting accordingly at each step
 *
 * @param state the current state of the interpreter
 */
static int
interpret (struct PERF_TALER_EXCHANGEDB_interpreter_state *state)
{
  for (state->i=0; PERF_TALER_EXCHANGEDB_CMD_END != state->cmd[state->i].command; state->i++)
  {
    switch (state->cmd[state->i].command)
    {
      case PERF_TALER_EXCHANGEDB_CMD_END:
        return GNUNET_YES;

      case PERF_TALER_EXCHANGEDB_CMD_DEBUG:
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "%s\n",
                    state->cmd[state->i].label);
        break;

      case PERF_TALER_EXCHANGEDB_CMD_LOOP:
        break;

      case PERF_TALER_EXCHANGEDB_CMD_END_LOOP:
        interpret_end_loop (state);
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_TIME:
        state->cmd[state->i].exposed.data.time =
          GNUNET_new (struct GNUNET_TIME_Absolute);
        *state->cmd[state->i].exposed.data.time =
          GNUNET_TIME_absolute_get ();
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GAUGER:
        {
          unsigned int start_index;
          unsigned int stop_index;
          float ips;
          struct GNUNET_TIME_Absolute start;
          struct GNUNET_TIME_Absolute stop;
          struct GNUNET_TIME_Relative elapsed;

          start_index = state->cmd[state->i].details.gauger.index_start;
          stop_index = state->cmd[state->i].details.gauger.index_stop;
          start = *state->cmd[start_index].exposed.data.time;
          stop = *state->cmd[stop_index].exposed.data.time;
          elapsed = GNUNET_TIME_absolute_get_difference (start,
                                                         stop);
          ips = (1.0 * state->cmd[state->i].details.gauger.divide) / (elapsed.rel_value_us/1000000.0);
          GAUGER (state->cmd[state->i].details.gauger.category,
                  state->cmd[state->i].details.gauger.description,
                  ips,
                  state->cmd[state->i].details.gauger.unit);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_NEW_SESSION:
        state->session = state->plugin->get_session (state->plugin->cls);
        break;

      case PERF_TALER_EXCHANGEDB_CMD_START_TRANSACTION:
        GNUNET_break (GNUNET_OK ==
                      state->plugin->start (state->plugin->cls,
                                            state->session));
        break;

      case PERF_TALER_EXCHANGEDB_CMD_COMMIT_TRANSACTION:
        GNUNET_break (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS ==
                      state->plugin->commit (state->plugin->cls,
                                             state->session));
        break;
      case PERF_TALER_EXCHANGEDB_CMD_ABORT_TRANSACTION:
        state->plugin->rollback (state->plugin->cls,
                                 state->session);
        break;

      case PERF_TALER_EXCHANGEDB_CMD_SAVE_ARRAY:
        interpret_save_array (state);
        break;

      case PERF_TALER_EXCHANGEDB_CMD_LOAD_ARRAY:
        interpret_load_array (state);
        break;

      case PERF_TALER_EXCHANGEDB_CMD_LOAD_RANDOM:
        interprete_load_random (state);
        break;

      case PERF_TALER_EXCHANGEDB_CMD_CREATE_DEPOSIT:
        {
          int coin_index;
          struct TALER_EXCHANGEDB_Deposit *deposit;

          coin_index = state->cmd[state->i].details.create_deposit.index_coin;
          deposit = PERF_TALER_EXCHANGEDB_deposit_init (state->cmd[coin_index].exposed.data.coin);
          GNUNET_assert (NULL != deposit);
          state->cmd[state->i].exposed.data.deposit = deposit;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_DEPOSIT:
        {
          int deposit_index;
          enum GNUNET_DB_QueryStatus qs;
          struct TALER_EXCHANGEDB_Deposit *deposit;

          deposit_index = state->cmd[state->i].details.insert_deposit.index_deposit;
          deposit = state->cmd[deposit_index].exposed.data.deposit;
          qs = state->plugin->insert_deposit (state->plugin->cls,
                                                        state->session,
                                                        deposit);
          GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
          state->cmd[state->i].exposed.data.deposit = deposit;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_DEPOSIT:
        {
          unsigned int source_index;
          enum GNUNET_DB_QueryStatus ret;
          struct PERF_TALER_EXCHANGEDB_Data *data;

          source_index = state->cmd[state->i].details.get_deposit.index_deposit;
          data = &state->cmd[source_index].exposed;
          ret = state->plugin->have_deposit (state->plugin->cls,
                                             state->session,
                                             data->data.deposit);
          GNUNET_assert (0 >= ret);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_CREATE_RESERVE:
        {
          struct PERF_TALER_EXCHANGEDB_Reserve *reserve;

          reserve = PERF_TALER_EXCHANGEDB_reserve_init ();
          state->cmd[state->i].exposed.data.reserve = reserve;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_RESERVE:
        {
          unsigned int reserve_index;
          int ret;
          struct PERF_TALER_EXCHANGEDB_Reserve *reserve;
          json_t *sndr;
          uint32_t uid;

          reserve_index = state->cmd[state->i].details.insert_reserve.index_reserve;
          reserve = state->cmd[reserve_index].exposed.data.reserve;
          sndr = json_pack ("{s:i}",
                            "account",
                            (int) GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                                            UINT32_MAX));
          uid = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                          UINT32_MAX);
          GNUNET_assert (NULL != sndr);
          ret = state->plugin->reserves_in_insert (state->plugin->cls,
                                                   state->session,
                                                   &reserve->reserve.pub,
                                                   &reserve->reserve.balance,
                                                   GNUNET_TIME_absolute_get (),
                                                   sndr,
                                                   &uid,
                                                   sizeof (uid));
          GNUNET_assert (GNUNET_SYSERR != ret);
          json_decref (sndr);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_RESERVE:
        {
          unsigned int reserve_index;
          int ret;
          struct PERF_TALER_EXCHANGEDB_Data *data;


          reserve_index = state->cmd[state->i].details.get_reserve.index_reserve;
          data = &state->cmd[reserve_index].exposed;
          ret = state->plugin->reserve_get (state->plugin->cls,
                                            state->session,
                                            &data->data.reserve->reserve);
          GNUNET_assert (GNUNET_OK == ret);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_RESERVE_HISTORY:
        {
          unsigned int reserve_index;
          struct TALER_EXCHANGEDB_ReserveHistory *history;
          struct PERF_TALER_EXCHANGEDB_Data *data;
	  enum GNUNET_DB_QueryStatus qs;

          reserve_index = state->cmd[state->i].details.get_reserve_history.index_reserve;
          data = &state->cmd[reserve_index].exposed;
          qs = state->plugin->get_reserve_history (state->plugin->cls,
						   state->session,
						   &data->data.reserve->reserve.pub,
						   &history);
	  GNUNET_assert (0 >= qs);
          GNUNET_assert (NULL != history);
          state->plugin->free_reserve_history (state->plugin->cls,
                                               history);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_CREATE_DENOMINATION:
        {
          struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki =
            PERF_TALER_EXCHANGEDB_denomination_init ();
          GNUNET_assert (NULL != dki);
          state->cmd[state->i].exposed.data.dki = dki;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_DENOMINATION:
        {
          unsigned int denom_index;
          enum GNUNET_DB_QueryStatus ret;
          struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki ;

          denom_index = state->cmd[state->i].details.insert_denomination.index_denom;
          dki = state->cmd[denom_index].exposed.data.dki;
          ret = state->plugin->insert_denomination_info (state->plugin->cls,
                                                         state->session,
                                                         &dki->denom_pub,
                                                         &dki->issue);
          GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == ret);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_DENOMINATION:
        {
          unsigned int denom_index;
          int ret;
          struct PERF_TALER_EXCHANGEDB_Data *data;

          denom_index = state->cmd[state->i].details.get_denomination.index_denom;
          data = &state->cmd[denom_index].exposed;
          ret = state->plugin->get_denomination_info (state->plugin->cls,
                                                      state->session,
                                                      &data->data.dki->denom_pub,
                                                      &data->data.dki->issue);
          GNUNET_assert (GNUNET_SYSERR != ret);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_CREATE_WITHDRAW:
        {
          unsigned int dki_index;
          unsigned int reserve_index;
          struct PERF_TALER_EXCHANGEDB_Coin *coin;

          dki_index     = state->cmd[state->i].details.create_withdraw.index_dki;
          reserve_index = state->cmd[state->i].details.create_withdraw.index_reserve;
          coin = PERF_TALER_EXCHANGEDB_coin_init (state->cmd[dki_index].exposed.data.dki,
                                                  state->cmd[reserve_index].exposed.data.reserve);
          GNUNET_assert (NULL != coin);
          state->cmd[state->i].exposed.data.coin = coin;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_WITHDRAW:
        {
          unsigned int coin_index;
          enum GNUNET_DB_QueryStatus qs;
          struct PERF_TALER_EXCHANGEDB_Coin *coin;

          coin_index = state->cmd[state->i].details.insert_withdraw.index_coin;
          coin = state->cmd[coin_index].exposed.data.coin;
          qs = state->plugin->insert_withdraw_info (state->plugin->cls,
                                                     state->session,
                                                     &coin->blind);
          GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_WITHDRAW:
        {
          unsigned int source_index;
          enum GNUNET_DB_QueryStatus qs;
          struct PERF_TALER_EXCHANGEDB_Data *data;

          source_index = state->cmd[state->i].details.get_denomination.index_denom;
          data = &state->cmd[source_index].exposed;
          qs = state->plugin->get_withdraw_info (state->plugin->cls,
						 state->session,
						 &data->data.coin->blind.h_coin_envelope,
						 &data->data.coin->blind);
          GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_COIN_TRANSACTION:
        {
          unsigned int coin_index;
          struct PERF_TALER_EXCHANGEDB_Coin *coin;
          struct TALER_EXCHANGEDB_TransactionList *transactions;
	  enum GNUNET_DB_QueryStatus qs;

          coin_index = state->cmd[state->i].details.get_coin_transaction.index_coin;
          coin = state->cmd[coin_index].exposed.data.coin;
          qs = state->plugin->get_coin_transactions (state->plugin->cls,
						     state->session,
						     &coin->public_info.coin_pub,
						     &transactions);
	  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
	  GNUNET_assert (transactions != NULL);
          state->plugin->free_coin_transaction_list (state->plugin->cls,
                                                     transactions);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_CREATE_REFRESH_SESSION:
        {
          struct GNUNET_HashCode *hash;
          struct TALER_EXCHANGEDB_RefreshSession *refresh_session;

          hash = GNUNET_new (struct GNUNET_HashCode);
          refresh_session = PERF_TALER_EXCHANGEDB_refresh_session_init ();
          GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
                                            hash);
          state->plugin->create_refresh_session (state->session,
                                                 state->session,
                                                 hash,
                                                 refresh_session);
          state->cmd[state->i].exposed.data.session_hash = hash;
          PERF_TALER_EXCHANGEDB_refresh_session_free (refresh_session);
          GNUNET_free (refresh_session);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_REFRESH_SESSION:
        {
          unsigned int hash_index;
          struct GNUNET_HashCode *hash;
          struct TALER_EXCHANGEDB_RefreshSession refresh;

          hash_index = state->cmd[state->i].details.get_refresh_session.index_hash;
          hash = state->cmd[hash_index].exposed.data.session_hash;
          state->plugin->get_refresh_session (state->session,
                                              state->session,
                                              hash,
                                              &refresh);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_REFRESH_ORDER:
        {
          unsigned int hash_index;
          unsigned int denom_index;
          struct GNUNET_HashCode *session_hash;
          struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *denom;

          hash_index = state->cmd[state->i].details.insert_refresh_order.index_hash;
          denom_index = state->cmd[state->i].details.insert_refresh_order.index_denom;
          session_hash = state->cmd[hash_index].exposed.data.session_hash;
          denom = state->cmd[denom_index].exposed.data.dki;
          state->plugin->insert_refresh_order (state->plugin->cls,
                                               state->session,
                                               session_hash,
                                               1,
                                               &denom->denom_pub);

        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_REFRESH_ORDER:
        {
          int hash_index;
          struct GNUNET_HashCode *hash;
          struct TALER_DenominationPublicKey denom_pub;

          hash_index = state->cmd[state->i].details.get_refresh_order.index_hash;
          hash = state->cmd[hash_index].exposed.data.session_hash;
          state->plugin->get_refresh_order (state->plugin->cls,
                                            state->session,
                                            hash,
                                            1,
                                            &denom_pub);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_REFRESH_COMMIT_COIN:
        {
          int ret;
          unsigned int hash_index;
          struct TALER_EXCHANGEDB_RefreshCommitCoin *refresh_commit;

          hash_index = state->cmd[state->i].details.insert_refresh_commit_coin.index_hash;
          refresh_commit = PERF_TALER_EXCHANGEDB_refresh_commit_coin_init ();
          ret = state->plugin->insert_refresh_commit_coins (state->plugin->cls,
                                                            state->session,
                                                            state->cmd[hash_index].exposed.data.session_hash,
                                                            1,
                                                            refresh_commit);
          GNUNET_assert (GNUNET_OK == ret);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_REFRESH_COMMIT_COIN:
        {
          unsigned int hash_index;
          struct TALER_EXCHANGEDB_RefreshCommitCoin refresh_commit;

          hash_index = state->cmd[state->i].details.insert_refresh_commit_coin.index_hash;
          state->plugin->get_refresh_commit_coins (state->plugin->cls,
                                                   state->session,
                                                   state->cmd[hash_index].exposed.data.session_hash,
                                                   1,
                                                   &refresh_commit);

        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_REFRESH_COMMIT_LINK:
        {
//          unsigned int hash_index;
//
//          hash_index = state->cmd[state->i].details.insert_refresh_commit_link.index_hash;
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_REFRESH_COMMIT_LINK:
        {
          int ret;
          unsigned int hash_index;
          struct TALER_EXCHANGEDB_RefreshCommitCoin commit_coin;

          // FIXME: this should go after the public key!
          hash_index = state->cmd[state->i].details.get_refresh_commit_link.index_hash;
          ret = state->plugin->get_refresh_commit_coins(state->plugin->cls,
                                                        state->session,
                                                        state->cmd[hash_index].exposed.data.session_hash,
                                                        1,
                                                        &commit_coin);
          GNUNET_assert (GNUNET_SYSERR != ret);
        }
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_MELT_COMMITMENT:
        break;

      case PERF_TALER_EXCHANGEDB_CMD_INSERT_REFRESH_OUT:
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_LINK_DATA_LIST:
        break;

      case PERF_TALER_EXCHANGEDB_CMD_GET_TRANSFER:
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
PERF_TALER_EXCHANGEDB_interpret (struct TALER_EXCHANGEDB_Plugin *db_plugin,
                                 struct PERF_TALER_EXCHANGEDB_Cmd cmd[])
{
  int ret;
  struct PERF_TALER_EXCHANGEDB_interpreter_state state =
  {.i = 0, .cmd = cmd, .plugin = db_plugin};

  ret = cmd_init (cmd);
  if (GNUNET_SYSERR == ret)
    return ret;
  state.session = db_plugin->get_session (db_plugin->cls);
  if (NULL == state.session)
    return GNUNET_SYSERR;
  GNUNET_assert (NULL != state.session);
  ret = interpret (&state);
  cmd_clean (cmd);
  return ret;
}


/**
 * Initialize the database and run the benchmark
 *
 * @param benchmark_name the name of the benchmark, displayed in the logs
 * @param configuration_file path to the taler configuration file to use
 * @param init the commands to use for the database initialisation,
 * if #NULL the standard initialization is used
 * @param benchmark the commands for the benchmark
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure, #GNUNET_NO
 *        if we failed to init the database
 */
int
PERF_TALER_EXCHANGEDB_run_benchmark (const char *benchmark_name,
                                     const char *configuration_file,
                                     struct PERF_TALER_EXCHANGEDB_Cmd *init,
                                     struct PERF_TALER_EXCHANGEDB_Cmd *benchmark)
{
  struct TALER_EXCHANGEDB_Plugin *plugin;
  struct GNUNET_CONFIGURATION_Handle *config;
  int ret = 0;
  struct PERF_TALER_EXCHANGEDB_Cmd init_def[] =
  {
    // Denomination used to create coins
    PERF_TALER_EXCHANGEDB_INIT_CMD_DEBUG ("00 - Start of interpreter"),

    PERF_TALER_EXCHANGEDB_INIT_CMD_LOOP ("01 - denomination loop",
                                     PERF_TALER_EXCHANGEDB_NB_DENOMINATION_INIT),
    PERF_TALER_EXCHANGEDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_EXCHANGEDB_INIT_CMD_CREATE_DENOMINATION ("01 - denomination"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_INSERT_DENOMINATION ("01 - insert",
                                                    "01 - denomination"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_EXCHANGEDB_INIT_CMD_SAVE_ARRAY ("01 - save denomination",
                                           "01 - denomination loop",
                                           "01 - denomination",
                                           PERF_TALER_EXCHANGEDB_NB_DENOMINATION_SAVE),
    PERF_TALER_EXCHANGEDB_INIT_CMD_END_LOOP ("",
                                         "01 - denomination loop"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_DEBUG ("01 - init denomination complete"),
    // End of initialization
    // Reserve initialization
    PERF_TALER_EXCHANGEDB_INIT_CMD_LOOP ("02 - init reserve loop",
                                     PERF_TALER_EXCHANGEDB_NB_RESERVE_INIT),
    PERF_TALER_EXCHANGEDB_INIT_CMD_CREATE_RESERVE ("02 - reserve"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_INSERT_RESERVE ("02 - insert",
                                               "02 - reserve"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_SAVE_ARRAY ("02 - save reserve",
                                           "02 - init reserve loop",
                                           "02 - reserve",
                                           PERF_TALER_EXCHANGEDB_NB_RESERVE_SAVE),
    PERF_TALER_EXCHANGEDB_INIT_CMD_END_LOOP ("",
                                         "02 - init reserve loop"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_DEBUG ("02 - reserve init complete"),
    // End reserve init
    // Withdrawal initialization
    PERF_TALER_EXCHANGEDB_INIT_CMD_LOOP ("03 - init withdraw loop",
                                     PERF_TALER_EXCHANGEDB_NB_WITHDRAW_INIT),
    PERF_TALER_EXCHANGEDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_EXCHANGEDB_INIT_CMD_LOAD_ARRAY ("03 - denomination load",
                                           "03 - init withdraw loop",
                                           "01 - save denomination"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_LOAD_ARRAY ("03 - reserve load",
                                           "03 - init withdraw loop",
                                           "02 - save reserve"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_CREATE_WITHDRAW ("03 - withdraw",
                                                "03 - denomination load",
                                                "03 - reserve load"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_INSERT_WITHDRAW ("03 - insert",
                                                "03 - withdraw"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_EXCHANGEDB_INIT_CMD_SAVE_ARRAY ("03 - save coin",
                                           "03 - init withdraw loop",
                                           "03 - withdraw",
                                           PERF_TALER_EXCHANGEDB_NB_WITHDRAW_SAVE),
    PERF_TALER_EXCHANGEDB_INIT_CMD_END_LOOP ("",
                                         "03 - init withdraw loop"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_DEBUG ("03 - withdraw init complete"),
    //End of withdrawal initialization
    //Deposit initialization
    PERF_TALER_EXCHANGEDB_INIT_CMD_LOOP ("04 - deposit init loop",
                                     PERF_TALER_EXCHANGEDB_NB_DEPOSIT_INIT),
    PERF_TALER_EXCHANGEDB_INIT_CMD_START_TRANSACTION ("04 - start transaction"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_LOAD_ARRAY ("04 - denomination load",
                                           "04 - deposit init loop",
                                           "03 - save coin"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_INSERT_DEPOSIT ("04 - deposit",
                                               "04 - denomination load"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_COMMIT_TRANSACTION ("04 - commit transaction"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_SAVE_ARRAY ("04 - deposit array",
                                           "04 - deposit init loop",
                                           "04 - deposit",
                                           PERF_TALER_EXCHANGEDB_NB_DEPOSIT_SAVE),
    PERF_TALER_EXCHANGEDB_INIT_CMD_END_LOOP ("04 - deposit init loop end",
                                         "04 - deposit init loop"),
    PERF_TALER_EXCHANGEDB_INIT_CMD_DEBUG ("04 - deposit init complete"),
    // End of deposit initialization
    PERF_TALER_EXCHANGEDB_INIT_CMD_END ("end")
  };

  GNUNET_log_setup (benchmark_name,
                    "INFO",
                    NULL);
  config = GNUNET_CONFIGURATION_create ();
  ret = GNUNET_CONFIGURATION_parse (config,
                                    configuration_file);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error parsing configuration file\n");
    return GNUNET_SYSERR;
  }
  plugin = TALER_EXCHANGEDB_plugin_load (config);
  if (NULL == plugin)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error connectiong to the database\n");
    return GNUNET_NO;
  }
  ret = plugin->create_tables (plugin->cls);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error while creating the database architecture\n");
    return GNUNET_NO;
  }
  /*
   * Running the initialization
   */
  if (NULL == init)
  {
    init = init_def;
  }
  ret = PERF_TALER_EXCHANGEDB_interpret (plugin,
                                         init);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error during database initialization\n");
    return ret;
  }
  /*
   * Running the benchmark
   */
  ret = PERF_TALER_EXCHANGEDB_interpret (plugin,
                                     benchmark);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error while runing the benchmark\n");
    return ret;
  }
  /* Drop tables */
  {
    ret = plugin->drop_tables (plugin->cls);
    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Error cleaning the database\n");
      return ret;
    }
  }
  TALER_EXCHANGEDB_plugin_unload (plugin);
  GNUNET_CONFIGURATION_destroy (config);
  return ret;
}
