/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

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
 * @file taler-mint-httpd_db.c
 * @brief Database access abstraction for the mint.
 * @author Christian Grothoff
 *
 * TODO:
 * - actually abstract DB implementation (i.e. via plugin logic)
 * - /deposit: properly check existing deposits
 * - /deposit: properly perform commit (check return value)
 * - /deposit: check for leaks
 */
#include "platform.h"
#include "taler-mint-httpd_db.h"
#include "taler_signatures.h"
#include "taler-mint-httpd_responses.h"
#include "mint_db.h"
#include "mint.h"
#include <pthread.h>


/**
 * Execute a deposit.  The validity of the coin and signature
 * have already been checked.  The database must now check that
 * the coin is not (double or over) spent, and execute the
 * transaction (record details, generate success or failure response).
 *
 * @param connection the MHD connection to handle
 * @param deposit information about the deposit
 * @return MHD result code
 */
int
TALER_MINT_db_execute_deposit (struct MHD_Connection *connection,
                               const struct Deposit *deposit)
{
  PGconn *db_conn;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_error (connection,
                                            "Failed to connect to database\n");
  }

  {
    struct Deposit *existing_deposit;
    int res;

    res = TALER_MINT_DB_get_deposit (db_conn,
                                     &deposit->coin_pub,
                                     &existing_deposit);
    if (GNUNET_YES == res)
    {
      // FIXME: memory leak
      // FIXME: memcmp will not actually work here
      if (0 == memcmp (existing_deposit, deposit, sizeof (struct Deposit)))
        return TALER_MINT_reply_deposit_success (connection, deposit);
      // FIXME: in the future, check if there's enough credits
      // left on the coin. For now: refuse
      // FIXME: return more information here
      return TALER_MINT_reply_json_pack (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         "{s:s}",
                                         "error",
                                         "double spending");
    }

    if (GNUNET_SYSERR == res)
    {
      GNUNET_break (0);
    /* FIXME: return error message to client via MHD! */
      return MHD_NO;
    }
  }

  {
    struct KnownCoin known_coin;
    int res;
    struct TALER_CoinPublicInfo coin_info;

    res = TALER_MINT_DB_get_known_coin (db_conn, &coin_info.coin_pub, &known_coin);
    if (GNUNET_YES == res)
    {
      // coin must have been refreshed
      // FIXME: check
      // FIXME: return more information here
      return TALER_MINT_reply_json_pack (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         "{s:s}",
                                         "error", "coin was refreshed");
    }
    if (GNUNET_SYSERR == res)
    {
      GNUNET_break (0);
    /* FIXME: return error message to client via MHD! */
      return MHD_NO;
    }

    /* coin valid but not known => insert into DB */
    known_coin.is_refreshed = GNUNET_NO;
    known_coin.expended_balance = TALER_amount_ntoh (deposit->amount);
    known_coin.public_info = coin_info;

    if (GNUNET_OK != TALER_MINT_DB_insert_known_coin (db_conn, &known_coin))
    {
      GNUNET_break (0);
    /* FIXME: return error message to client via MHD! */
      return MHD_NO;
    }
  }

  if (GNUNET_OK != TALER_MINT_DB_insert_deposit (db_conn, deposit))
  {
    GNUNET_break (0);
    /* FIXME: return error message to client via MHD! */
    return MHD_NO;
  }
  // FIXME: check commit return value!
  TALER_MINT_DB_commit (db_conn);
  return TALER_MINT_reply_deposit_success (connection, deposit);
}
