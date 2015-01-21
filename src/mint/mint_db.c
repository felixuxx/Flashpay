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
 * @file mint_db.c
 * @brief Database access for the mint
 * @author Florian Dold
 */
#include "platform.h"
#include "taler_db_lib.h"
#include "taler_signatures.h"
#include "taler-mint-httpd_responses.h"
#include "mint_db.h"
#include "mint.h"
#include <pthread.h>

/**
 * Thread-local database connection.
 * Contains a pointer to PGconn or NULL.
 */
static pthread_key_t db_conn_threadlocal;


/**
 * Database connection string, as read from
 * the configuration.
 */
static char *TALER_MINT_db_connection_cfg_str;


#define break_db_err(result) do { \
    GNUNET_break(0); \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Database failure: %s\n", PQresultErrorMessage (result)); \
  } while (0)

/**
 * Shorthand for exit jumps.
 */
#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)

int
TALER_MINT_DB_get_collectable_blindcoin (PGconn *db_conn,
                                         struct TALER_RSA_BlindedSignaturePurpose *blind_ev,
                                         struct CollectableBlindcoin *collectable)
{
  PGresult *result;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (blind_ev),
    TALER_DB_QUERY_PARAM_END
  };
  result = TALER_DB_exec_prepared (db_conn, "get_collectable_blindcoins", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Query failed: %s\n", PQresultErrorMessage (result));
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("blind_ev_sig", &collectable->ev_sig),
    TALER_DB_RESULT_SPEC("denom_pub", &collectable->denom_pub),
    TALER_DB_RESULT_SPEC("reserve_sig", &collectable->reserve_sig),
    TALER_DB_RESULT_SPEC("reserve_pub", &collectable->reserve_pub),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_OK != TALER_DB_extract_result (result, rs, 0))
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  (void) memcpy (&collectable->ev, blind_ev, sizeof (struct TALER_RSA_BlindedSignaturePurpose));
  PQclear (result);
  return GNUNET_OK;
}


int
TALER_MINT_DB_insert_collectable_blindcoin (PGconn *db_conn,
                                            const struct CollectableBlindcoin *collectable)
{
  PGresult *result;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (&collectable->ev),
    TALER_DB_QUERY_PARAM_PTR (&collectable->ev_sig),
    TALER_DB_QUERY_PARAM_PTR (&collectable->denom_pub),
    TALER_DB_QUERY_PARAM_PTR (&collectable->reserve_pub),
    TALER_DB_QUERY_PARAM_PTR (&collectable->reserve_sig),
    TALER_DB_QUERY_PARAM_END
  };
  result = TALER_DB_exec_prepared (db_conn, "insert_collectable_blindcoins", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Query failed: %s\n", PQresultErrorMessage (result));
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 != strcmp ("1", PQcmdTuples (result)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Insert failed (updated '%s' tupes instead of '1')\n",
             PQcmdTuples (result));
    PQclear (result);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_MINT_DB_get_reserve (PGconn *db_conn,
                           const struct GNUNET_CRYPTO_EddsaPublicKey *reserve_pub,
                           struct Reserve *reserve)
{
  PGresult *result;
  int res;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (reserve_pub),
    TALER_DB_QUERY_PARAM_END
  };

  result = TALER_DB_exec_prepared (db_conn, "get_reserve", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Query failed: %s\n", PQresultErrorMessage (result));
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  reserve->reserve_pub = *reserve_pub;

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("status_sig", &reserve->status_sig),
    TALER_DB_RESULT_SPEC("status_sign_pub", &reserve->status_sign_pub),
    TALER_DB_RESULT_SPEC_END
  };

  res = TALER_DB_extract_result (result, rs, 0);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  {
    int fnums[] = {
      PQfnumber (result, "balance_value"),
      PQfnumber (result, "balance_fraction"),
      PQfnumber (result, "balance_currency"),
    };
    if (GNUNET_OK != TALER_TALER_DB_extract_amount_nbo (result, 0, fnums, &reserve->balance))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
  }

  /* FIXME: Add expiration?? */

  PQclear (result);
  return GNUNET_OK;
}


/* If fresh is GNUNET_YES, set some fields to NULL as they are not actually valid */
int
TALER_MINT_DB_update_reserve (PGconn *db_conn,
                              const struct Reserve *reserve,
                              int fresh)
{
  PGresult *result;
  uint64_t stamp_sec;

  stamp_sec = GNUNET_ntohll (GNUNET_TIME_absolute_ntoh (reserve->expiration).abs_value_us / 1000000);

  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (&reserve->reserve_pub),
    TALER_DB_QUERY_PARAM_PTR (&reserve->balance.value),
    TALER_DB_QUERY_PARAM_PTR (&reserve->balance.fraction),
    TALER_DB_QUERY_PARAM_PTR_SIZED (&reserve->balance.currency,
                           strlen (reserve->balance.currency)),
    TALER_DB_QUERY_PARAM_PTR (&reserve->status_sig),
    TALER_DB_QUERY_PARAM_PTR (&reserve->status_sign_pub),
    TALER_DB_QUERY_PARAM_PTR (&stamp_sec),
    TALER_DB_QUERY_PARAM_END
  };

  /* set some fields to NULL if they are not actually valid */

  if (GNUNET_YES == fresh)
  {
    unsigned i;
    for (i = 4; i <= 7; i += 1)
    {
     params[i].data = NULL;
     params[i].size = 0;
    }
  }

  result = TALER_DB_exec_prepared (db_conn, "update_reserve", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Query failed: %s\n", PQresultErrorMessage (result));
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 != strcmp ("1", PQcmdTuples (result)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Update failed (updated '%s' tupes instead of '1')\n",
             PQcmdTuples (result));
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}



int
TALER_MINT_DB_prepare (PGconn *db_conn)
{
  PGresult *result;

  result = PQprepare (db_conn, "get_reserve",
                      "SELECT "
                      " balance_value, balance_fraction, balance_currency "
                      ",expiration_date, blind_session_pub, blind_session_priv"
                      ",status_sig, status_sign_pub "
                      "FROM reserves "
                      "WHERE reserve_pub=$1 "
                      "LIMIT 1; ",
                      1, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "update_reserve",
                      "UPDATE reserves "
                      "SET"
                      " balance_value=$2 "
                      ",balance_fraction=$3 "
                      ",balance_currency=$4 "
                      ",status_sig=$5 "
                      ",status_sign_pub=$6 "
                      ",expiration_date=$7 "
                      "WHERE reserve_pub=$1 ",
                      9, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  result = PQprepare (db_conn, "insert_collectable_blindcoins",
                      "INSERT INTO collectable_blindcoins ( "
                      " blind_ev, blind_ev_sig "
                      ",denom_pub, reserve_pub, reserve_sig) "
                      "VALUES ($1, $2, $3, $4, $5)",
                      6, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "get_collectable_blindcoins",
                      "SELECT "
                      "blind_ev_sig, denom_pub, reserve_sig, reserve_pub "
                      "FROM collectable_blindcoins "
                      "WHERE blind_ev = $1",
                      1, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "insert_reserve_order",
                      "SELECT "
                      " blind_ev, blind_ev_sig, denom_pub, reserve_sig, reserve_pub "
                      "FROM collectable_blindcoins "
                      "WHERE blind_session_pub = $1",
                      1, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  /* FIXME: does it make sense to store these computed values in the DB? */
  result = PQprepare (db_conn, "get_refresh_session",
                      "SELECT "
                      " (SELECT count(*) FROM refresh_melt WHERE session_pub = $1)::INT2 as num_oldcoins "
                      ",(SELECT count(*) FROM refresh_blind_session_keys "
                      "  WHERE session_pub = $1 and cnc_index = 0)::INT2 as num_newcoins "
                      ",(SELECT count(*) FROM refresh_blind_session_keys "
                      "  WHERE session_pub = $1 and newcoin_index = 0)::INT2 as kappa "
                      ",noreveal_index"
                      ",session_commit_sig "
                      ",reveal_ok "
                      "FROM refresh_sessions "
                      "WHERE session_pub = $1",
                      1, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "get_known_coin",
                      "SELECT "
                      " coin_pub, denom_pub, denom_sig "
                      ",expended_value, expended_fraction, expended_currency "
                      ",refresh_session_pub "
                      "FROM known_coins "
                      "WHERE coin_pub = $1",
                      1, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "update_known_coin",
                      "UPDATE known_coins "
                      "SET "
                      " denom_pub = $2 "
                      ",denom_sig = $3 "
                      ",expended_value = $4 "
                      ",expended_fraction = $5 "
                      ",expended_currency = $6 "
                      ",refresh_session_pub = $7 "
                      "WHERE "
                      " coin_pub = $1 ",
                      7, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "insert_known_coin",
                      "INSERT INTO known_coins ("
                      " coin_pub"
                      ",denom_pub"
                      ",denom_sig"
                      ",expended_value"
                      ",expended_fraction"
                      ",expended_currency"
                      ",refresh_session_pub"
                      ")"
                      "VALUES ($1,$2,$3,$4,$5,$6,$7)",
                      7, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "get_refresh_commit_link",
                      "SELECT "
                      " transfer_pub "
                      ",link_secret_enc "
                      "FROM refresh_commit_link "
                      "WHERE session_pub = $1 AND cnc_index = $2 AND oldcoin_index = $3",
                      3, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "get_refresh_commit_coin",
                      "SELECT "
                      " link_vector_enc "
                      ",coin_ev "
                      "FROM refresh_commit_coin "
                      "WHERE session_pub = $1 AND cnc_index = $2 AND newcoin_index = $3",
                      3, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "insert_refresh_order",
                      "INSERT INTO refresh_order ( "
                      " newcoin_index "
                      ",session_pub "
                      ",denom_pub "
                      ") "
                      "VALUES ($1, $2, $3) ",
                      3, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "insert_refresh_melt",
                      "INSERT INTO refresh_melt ( "
                      " session_pub "
                      ",oldcoin_index "
                      ",coin_pub "
                      ",denom_pub "
                      ") "
                      "VALUES ($1, $2, $3, $4) ",
                      3, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "get_refresh_order",
                      "SELECT denom_pub "
                      "FROM refresh_order "
                      "WHERE session_pub = $1 AND newcoin_index = $2",
                      2, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "get_refresh_collectable",
                      "SELECT ev_sig "
                      "FROM refresh_collectable "
                      "WHERE session_pub = $1 AND newcoin_index = $2",
                      2, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "get_refresh_melt",
                      "SELECT coin_pub "
                      "FROM refresh_melt "
                      "WHERE session_pub = $1 AND oldcoin_index = $2",
                      2, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "insert_refresh_session",
                      "INSERT INTO refresh_sessions ( "
                      " session_pub "
                      ",noreveal_index "
                      ") "
                      "VALUES ($1, $2) ",
                      2, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "insert_refresh_commit_link",
                      "INSERT INTO refresh_commit_link ( "
                      " session_pub "
                      ",transfer_pub "
                      ",cnc_index "
                      ",oldcoin_index "
                      ",link_secret_enc "
                      ") "
                      "VALUES ($1, $2, $3, $4, $5) ",
                      5, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "insert_refresh_commit_coin",
                      "INSERT INTO refresh_commit_coin ( "
                      " session_pub "
                      ",coin_ev "
                      ",cnc_index "
                      ",newcoin_index "
                      ",link_vector_enc "
                      ") "
                      "VALUES ($1, $2, $3, $4, $5) ",
                      5, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "insert_refresh_collectable",
                      "INSERT INTO refresh_collectable ( "
                      " session_pub "
                      ",newcoin_index "
                      ",ev_sig "
                      ") "
                      "VALUES ($1, $2, $3) ",
                      3, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "set_reveal_ok",
                      "UPDATE refresh_sessions "
                      "SET reveal_ok = TRUE "
                      "WHERE session_pub = $1 ",
                      1, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "get_link",
                      "SELECT link_vector_enc, ro.denom_pub, ev_sig "
                      "FROM refresh_melt rm "
                      "     JOIN refresh_order ro USING (session_pub) "
                      "     JOIN refresh_commit_coin rcc USING (session_pub) "
                      "     JOIN refresh_sessions rs USING (session_pub) "
                      "     JOIN refresh_collectable rc USING (session_pub) "
                      "WHERE rm.coin_pub = $1 "
                      "AND ro.newcoin_index = rcc.newcoin_index "
                      "AND ro.newcoin_index = rc.newcoin_index "
                      "AND  rcc.cnc_index = rs.noreveal_index % ( "
                      "         SELECT count(*) FROM refresh_commit_coin rcc2 "
                      "         WHERE rcc2.newcoin_index = 0 AND rcc2.session_pub = rs.session_pub "
                      "     ) ",
                      1, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQprepare (db_conn, "get_transfer",
                      "SELECT transfer_pub, link_secret_enc "
                      "FROM refresh_melt rm "
                      "     JOIN refresh_commit_link rcl USING (session_pub) "
                      "     JOIN refresh_sessions rs USING (session_pub) "
                      "WHERE rm.coin_pub = $1 "
                      "AND  rm.oldcoin_index = rcl.oldcoin_index "
                      "AND  rcl.cnc_index = rs.noreveal_index % ( "
                      "         SELECT count(*) FROM refresh_commit_coin rcc2 "
                      "         WHERE newcoin_index = 0 AND rcc2.session_pub = rm.session_pub "
                      "     ) ",
                      1, NULL);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  if (GNUNET_OK != TALER_MINT_DB_prepare_deposits (db_conn))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * Roll back the current transaction of a database connection.
 *
 * @param db_conn the database connection
 * @return GNUNET_OK on success
 */
int
TALER_MINT_DB_rollback (PGconn *db_conn)
{
  PGresult *result;

  result = PQexec(db_conn, "ROLLBACK");
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    PQclear (result);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


/**
 * Roll back the current transaction of a database connection.
 *
 * @param db_conn the database connection
 * @return GNUNET_OK on success
 */
int
TALER_MINT_DB_commit (PGconn *db_conn)
{
  PGresult *result;

  result = PQexec(db_conn, "COMMIT");
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    PQclear (result);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


/**
 * Start a transaction.
 *
 * @param db_conn the database connection
 * @return GNUNET_OK on success
 */
int
TALER_MINT_DB_transaction (PGconn *db_conn)
{
  PGresult *result;

  result = PQexec(db_conn, "BEGIN");
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Can't start transaction: %s\n", PQresultErrorMessage (result));
    PQclear (result);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


/**
 * Insert a refresh order into the database.
 */
int
TALER_MINT_DB_insert_refresh_order (PGconn *db_conn,
                                    uint16_t newcoin_index,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                    const struct TALER_RSA_PublicKeyBinaryEncoded *denom_pub)
{
  uint16_t newcoin_index_nbo = htons (newcoin_index);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(session_pub),
    TALER_DB_QUERY_PARAM_PTR(denom_pub),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "insert_refresh_order", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 != strcmp ("1", PQcmdTuples (result)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_MINT_DB_get_refresh_session (PGconn *db_conn,
                                   const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                   struct RefreshSession *session)
{
  int res;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_refresh_session", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Query failed: %s\n", PQresultErrorMessage (result));
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
    return GNUNET_NO;

  GNUNET_assert (1 == PQntuples (result));

  /* We're done if the caller is only interested in
   * whether the session exists or not */

  if (NULL == session)
    return GNUNET_YES;

  memset (session, 0, sizeof (struct RefreshSession));

  session->session_pub = *refresh_session_pub;

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("num_oldcoins", &session->num_oldcoins),
    TALER_DB_RESULT_SPEC("num_newcoins", &session->num_newcoins),
    TALER_DB_RESULT_SPEC("kappa", &session->kappa),
    TALER_DB_RESULT_SPEC("noreveal_index", &session->noreveal_index),
    TALER_DB_RESULT_SPEC("reveal_ok", &session->reveal_ok),
    TALER_DB_RESULT_SPEC_END
  };

  res = TALER_DB_extract_result (result, rs, 0);

  if (GNUNET_OK != res)
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (TALER_DB_field_isnull (result, 0, "session_commit_sig"))
    session->has_commit_sig = GNUNET_NO;
  else
    session->has_commit_sig = GNUNET_YES;

  session->num_oldcoins = ntohs (session->num_oldcoins);
  session->num_newcoins = ntohs (session->num_newcoins);
  session->kappa = ntohs (session->kappa);
  session->noreveal_index = ntohs (session->noreveal_index);

  PQclear (result);
  return GNUNET_YES;
}


int
TALER_MINT_DB_get_known_coin (PGconn *db_conn,
                              const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                              struct KnownCoin *known_coin)
{
  int res;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(coin_pub),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_known_coin", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Query failed: %s\n", PQresultErrorMessage (result));
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
    return GNUNET_NO;

  GNUNET_assert (1 == PQntuples (result));

  /* extract basic information about the known coin */

  {
    struct TALER_DB_ResultSpec rs[] = {
      TALER_DB_RESULT_SPEC("coin_pub", &known_coin->public_info.coin_pub),
      TALER_DB_RESULT_SPEC("denom_pub", &known_coin->public_info.denom_pub),
      TALER_DB_RESULT_SPEC("denom_sig", &known_coin->public_info.denom_sig),
      TALER_DB_RESULT_SPEC_END
    };

    if (GNUNET_OK != (res = TALER_DB_extract_result (result, rs, 0)))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
  }

  /* extract the expended amount of the coin */

  if (GNUNET_OK != TALER_DB_extract_amount (result, 0,
                                      "expended_value",
                                      "expended_fraction",
                                      "expended_currency",
                                      &known_coin->expended_balance))
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  /* extract the refresh session of the coin or mark it as missing */

  {
    struct TALER_DB_ResultSpec rs[] = {
      TALER_DB_RESULT_SPEC("refresh_session_pub", &known_coin->refresh_session_pub),
      TALER_DB_RESULT_SPEC_END
    };

    if (GNUNET_SYSERR == (res = TALER_DB_extract_result (result, rs, 0)))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    if (GNUNET_NO == res)
    {
      known_coin->is_refreshed = GNUNET_NO;
      memset (&known_coin->refresh_session_pub, 0, sizeof (struct GNUNET_CRYPTO_EddsaPublicKey));
    }
    else
    {
      known_coin->is_refreshed = GNUNET_YES;
    }
  }

  PQclear (result);
  return GNUNET_YES;
}


int
TALER_MINT_DB_create_refresh_session (PGconn *db_conn,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub)
{
  uint16_t noreveal_index;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(session_pub),
    TALER_DB_QUERY_PARAM_PTR(&noreveal_index),
    TALER_DB_QUERY_PARAM_END
  };

  noreveal_index = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK, 1<<15);
  noreveal_index = htonl (noreveal_index);

  PGresult *result = TALER_DB_exec_prepared (db_conn, "insert_refresh_session", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_MINT_DB_set_commit_signature (PGconn *db_conn,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                    const struct GNUNET_CRYPTO_EddsaSignature *commit_sig)
{
  GNUNET_break (0);
  return GNUNET_SYSERR;
}


int
TALER_MINT_DB_set_reveal_ok (PGconn *db_conn,
                             const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub)
{
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(session_pub),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "set_reveal_ok", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 != strcmp ("1", PQcmdTuples (result)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_MINT_DB_update_known_coin (PGconn *db_conn,
                                 const struct KnownCoin *known_coin)
{
  struct TALER_AmountNBO expended_nbo = TALER_amount_hton (known_coin->expended_balance);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(&known_coin->public_info.coin_pub),
    TALER_DB_QUERY_PARAM_PTR(&known_coin->public_info.denom_pub),
    TALER_DB_QUERY_PARAM_PTR(&known_coin->public_info.denom_sig),
    TALER_DB_QUERY_PARAM_PTR(&expended_nbo.value),
    TALER_DB_QUERY_PARAM_PTR(&expended_nbo.fraction),
    TALER_DB_QUERY_PARAM_PTR_SIZED(expended_nbo.currency, strlen (expended_nbo.currency)),
    TALER_DB_QUERY_PARAM_PTR(&known_coin->refresh_session_pub),
    TALER_DB_QUERY_PARAM_END
  };

  if (GNUNET_NO == known_coin->is_refreshed)
  {
    // Mind the magic index!
    params[6].data = NULL;
    params[6].size = 0;
  }

  PGresult *result = TALER_DB_exec_prepared (db_conn, "update_known_coin", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 != strcmp ("1", PQcmdTuples (result)))
  {
    PQclear (result);
    // return 'no' here (don't fail) so that we can
    // insert if update fails (=> "upsert")
    return GNUNET_NO;
  }

  PQclear (result);
  return GNUNET_YES;
}

int
TALER_MINT_DB_insert_known_coin (PGconn *db_conn,
                                 const struct KnownCoin *known_coin)
{
  struct TALER_AmountNBO expended_nbo = TALER_amount_hton (known_coin->expended_balance);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(&known_coin->public_info.coin_pub),
    TALER_DB_QUERY_PARAM_PTR(&known_coin->public_info.denom_pub),
    TALER_DB_QUERY_PARAM_PTR(&known_coin->public_info.denom_sig),
    TALER_DB_QUERY_PARAM_PTR(&expended_nbo.value),
    TALER_DB_QUERY_PARAM_PTR(&expended_nbo.fraction),
    TALER_DB_QUERY_PARAM_PTR_SIZED(&expended_nbo.currency, strlen (expended_nbo.currency)),
    TALER_DB_QUERY_PARAM_PTR(&known_coin->refresh_session_pub),
    TALER_DB_QUERY_PARAM_END
  };

  if (GNUNET_NO == known_coin->is_refreshed)
  {
    // Mind the magic index!
    params[6].data = NULL;
    params[6].size = 0;
  }

  PGresult *result = TALER_DB_exec_prepared (db_conn, "insert_known_coin", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 != strcmp ("1", PQcmdTuples (result)))
  {
    PQclear (result);
    // return 'no' here (don't fail) so that we can
    // update if insert fails (=> "upsert")
    return GNUNET_NO;
  }

  PQclear (result);
  return GNUNET_YES;
}


int
TALER_MINT_DB_upsert_known_coin (PGconn *db_conn, struct KnownCoin *known_coin)
{
  int ret;
  ret = TALER_MINT_DB_update_known_coin (db_conn, known_coin);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_YES == ret)
    return GNUNET_YES;
  return TALER_MINT_DB_insert_known_coin (db_conn, known_coin);
}


int
TALER_MINT_DB_insert_refresh_commit_link (PGconn *db_conn,
                                          const struct RefreshCommitLink *commit_link)
{
  uint16_t cnc_index_nbo = htons (commit_link->cnc_index);
  uint16_t oldcoin_index_nbo = htons (commit_link->oldcoin_index);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(&commit_link->session_pub),
    TALER_DB_QUERY_PARAM_PTR(&commit_link->transfer_pub),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&oldcoin_index_nbo),
    TALER_DB_QUERY_PARAM_PTR_SIZED(&commit_link->shared_secret_enc, sizeof (struct GNUNET_HashCode)),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "insert_refresh_commit_link", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 != strcmp ("1", PQcmdTuples (result)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_MINT_DB_insert_refresh_commit_coin (PGconn *db_conn,
                                          const struct RefreshCommitCoin *commit_coin)
{
  uint16_t cnc_index_nbo = htons (commit_coin->cnc_index);
  uint16_t newcoin_index_nbo = htons (commit_coin->newcoin_index);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(&commit_coin->session_pub),
    TALER_DB_QUERY_PARAM_PTR(&commit_coin->coin_ev),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_PTR_SIZED(&commit_coin->link_enc, sizeof (struct LinkData)),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "insert_refresh_commit_coin", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 != strcmp ("1", PQcmdTuples (result)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_MINT_DB_get_refresh_commit_link (PGconn *db_conn,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                       int cnc_index, int oldcoin_index,
                                       struct RefreshCommitLink *cc)
{
  uint16_t cnc_index_nbo = htons (cnc_index);
  uint16_t oldcoin_index_nbo = htons (oldcoin_index);

  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&oldcoin_index_nbo),
    TALER_DB_QUERY_PARAM_END
  };

  cc->cnc_index = cnc_index;
  cc->oldcoin_index = oldcoin_index;
  cc->session_pub = *refresh_session_pub;

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_refresh_commit_link", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("transfer_pub", &cc->transfer_pub),
    TALER_DB_RESULT_SPEC_SIZED("link_secret_enc", &cc->shared_secret_enc,
                      TALER_REFRESH_SHARED_SECRET_LENGTH),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_YES != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_free (cc);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_YES;
}


int
TALER_MINT_DB_get_refresh_commit_coin (PGconn *db_conn,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                       int cnc_index, int newcoin_index,
                                       struct RefreshCommitCoin *cc)
{
  uint16_t cnc_index_nbo = htons (cnc_index);
  uint16_t newcoin_index_nbo = htons (newcoin_index);

  cc->cnc_index = cnc_index;
  cc->newcoin_index = newcoin_index;
  cc->session_pub = *refresh_session_pub;

  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_refresh_commit_coin", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("coin_ev", &cc->coin_ev),
    TALER_DB_RESULT_SPEC_SIZED("link_vector_enc", &cc->link_enc,
                      TALER_REFRESH_LINK_LENGTH),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_YES != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_YES;
}


int
TALER_MINT_DB_get_refresh_order (PGconn *db_conn,
                                 uint16_t newcoin_index,
                                 const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                 struct TALER_RSA_PublicKeyBinaryEncoded *denom_pub)
{
  uint16_t newcoin_index_nbo = htons (newcoin_index);

  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(session_pub),
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_refresh_order", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  GNUNET_assert (1 == PQntuples (result));

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("denom_pub", denom_pub),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_OK != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_MINT_DB_insert_refresh_collectable (PGconn *db_conn,
                                          uint16_t newcoin_index,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                          const struct TALER_RSA_Signature *ev_sig)
{
  uint16_t newcoin_index_nbo = htons (newcoin_index);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(session_pub),
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(ev_sig),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "insert_refresh_collectable", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_MINT_DB_get_refresh_collectable (PGconn *db_conn,
                                       uint16_t newcoin_index,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                       struct TALER_RSA_Signature *ev_sig)
{

  uint16_t newcoin_index_nbo = htons (newcoin_index);

  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(session_pub),
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_refresh_collectable", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  GNUNET_assert (1 == PQntuples (result));

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("ev_sig", ev_sig),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_OK != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}



int
TALER_MINT_DB_insert_refresh_melt (PGconn *db_conn,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                    uint16_t oldcoin_index,
                                    const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                                    const struct TALER_RSA_PublicKeyBinaryEncoded *denom_pub)
{
  uint16_t oldcoin_index_nbo = htons (oldcoin_index);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(session_pub),
    TALER_DB_QUERY_PARAM_PTR(&oldcoin_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(coin_pub),
    TALER_DB_QUERY_PARAM_PTR(denom_pub),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "insert_refresh_melt", params);

  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}



int
TALER_MINT_DB_get_refresh_melt (PGconn *db_conn,
                                const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                uint16_t oldcoin_index,
                                struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub)
{
  uint16_t oldcoin_index_nbo = htons (oldcoin_index);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(session_pub),
    TALER_DB_QUERY_PARAM_PTR(&oldcoin_index_nbo),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_refresh_melt", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  GNUNET_assert (1 == PQntuples (result));

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("coin_pub", coin_pub),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_OK != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_db_get_link (PGconn *db_conn,
                   const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                   LinkIterator link_iter,
                   void *cls)
{
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(coin_pub),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_link", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }


  int i = 0;
  int res;

  for (i = 0; i < PQntuples (result); i++)
  {
    struct LinkDataEnc link_data_enc;
    struct TALER_RSA_PublicKeyBinaryEncoded denom_pub;
    struct TALER_RSA_Signature ev_sig;
    struct TALER_DB_ResultSpec rs[] = {
      TALER_DB_RESULT_SPEC("link_vector_enc", &link_data_enc),
      TALER_DB_RESULT_SPEC("denom_pub", &denom_pub),
      TALER_DB_RESULT_SPEC("ev_sig", &ev_sig),
      TALER_DB_RESULT_SPEC_END
    };

    if (GNUNET_OK != TALER_DB_extract_result (result, rs, i))
    {
      PQclear (result);
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }

    if (GNUNET_OK != (res = link_iter (cls, &link_data_enc, &denom_pub, &ev_sig)))
    {
      GNUNET_assert (GNUNET_SYSERR != res);
      PQclear (result);
      return res;
    }
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_db_get_transfer (PGconn *db_conn,
                       const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                       struct GNUNET_CRYPTO_EcdsaPublicKey *transfer_pub,
                       struct SharedSecretEnc *shared_secret_enc)
{
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(coin_pub),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_transfer", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  if (1 != PQntuples (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "got %d tuples for get_transfer\n", PQntuples (result));
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("transfer_pub", transfer_pub),
    TALER_DB_RESULT_SPEC("link_secret_enc", shared_secret_enc),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_OK != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


int
TALER_MINT_DB_init_deposits (PGconn *conn, int tmp)
{
  const char *tmp_str = (1 == tmp) ? "TEMPORARY" : "";
  char *sql;
  PGresult *res;
  int ret;

  res = NULL;
  (void) GNUNET_asprintf (&sql,
                          "CREATE %1$s TABLE IF NOT EXISTS deposits ("
                          " coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (length(coin_pub)=32)"
                          ",denom_pub BYTEA NOT NULL CHECK (length(denom_pub)=32)"
                          ",transaction_id INT8 NOT NULL"
                          ",amount_value INT4 NOT NULL"
                          ",amount_fraction INT4 NOT NULL"
                          ",amount_currency VARCHAR(4) NOT NULL"
                          ",merchant_pub BYTEA NOT NULL"
                          ",h_contract BYTEA NOT NULL CHECK (length(h_contract)=64)"
                          ",h_wire BYTEA NOT NULL CHECK (length(h_wire)=64)"
                          ",coin_sig BYTEA NOT NULL CHECK (length(coin_sig)=64)"
                          ",wire TEXT NOT NULL"
                          ")",
                          tmp_str);
  res = PQexec (conn, sql);
  GNUNET_free (sql);
  if (PGRES_COMMAND_OK != PQresultStatus (res))
  {
    break_db_err (res);
    ret = GNUNET_SYSERR;
  }
  else
    ret = GNUNET_OK;
  PQclear (res);
  return ret;
}

int
TALER_MINT_DB_prepare_deposits (PGconn *db_conn)
{
  PGresult *result;

  result = PQprepare (db_conn, "insert_deposit",
                      "INSERT INTO deposits ("
                      "coin_pub,"
                      "denom_pub,"
                      "transaction_id,"
                      "amount_value,"
                      "amount_fraction,"
                      "amount_currency,"
                      "merchant_pub,"
                      "h_contract,"
                      "h_wire,"
                      "coin_sig,"
                      "wire"
                      ") VALUES ("
                      "$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11"
                      ")",
                      11, NULL);
  EXITIF (PGRES_COMMAND_OK != PQresultStatus(result));
  PQclear (result);

  result = PQprepare (db_conn, "get_deposit",
                      "SELECT "
                      "coin_pub,"
                      "denom_pub,"
                      "transaction_id,"
                      "amount_value,"
                      "amount_fraction,"
                      "amount_currency,"
                      "merchant_pub,"
                      "h_contract,"
                      "h_wire,"
                      "coin_sig"
                      " FROM deposits WHERE ("
                      "coin_pub = $1"
                      ")",
                      1, NULL);
  EXITIF (PGRES_COMMAND_OK != PQresultStatus(result));
  PQclear (result);

  return GNUNET_OK;

 EXITIF_exit:
  break_db_err (result);
  PQclear (result);
  return GNUNET_SYSERR;
}


int
TALER_MINT_DB_insert_deposit (PGconn *db_conn,
                              const struct Deposit *deposit)
{
  struct TALER_DB_QueryParam params[]= {
    TALER_DB_QUERY_PARAM_PTR (&deposit->coin_pub),
    TALER_DB_QUERY_PARAM_PTR (&deposit->denom_pub),
    TALER_DB_QUERY_PARAM_PTR (&deposit->transaction_id),
    TALER_DB_QUERY_PARAM_PTR (&deposit->amount.value),
    TALER_DB_QUERY_PARAM_PTR (&deposit->amount.fraction),
    TALER_DB_QUERY_PARAM_PTR_SIZED (deposit->amount.currency, strlen (deposit->amount.currency)),
    TALER_DB_QUERY_PARAM_PTR (&deposit->merchant_pub),
    TALER_DB_QUERY_PARAM_PTR (&deposit->h_contract),
    TALER_DB_QUERY_PARAM_PTR (&deposit->h_wire),
    TALER_DB_QUERY_PARAM_PTR (&deposit->coin_sig),
    TALER_DB_QUERY_PARAM_PTR_SIZED (deposit->wire, strlen(deposit->wire)),
    TALER_DB_QUERY_PARAM_END
  };
  PGresult *result;

  result = TALER_DB_exec_prepared (db_conn, "insert_deposit", params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}

int
TALER_MINT_DB_get_deposit (PGconn *db_conn,
                           const struct GNUNET_CRYPTO_EddsaPublicKey *coin_pub,
                           struct Deposit **r_deposit)
{
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (coin_pub),
    TALER_DB_QUERY_PARAM_END
  };
  PGresult *result;
  struct Deposit *deposit;

  deposit = NULL;
  result = TALER_DB_exec_prepared (db_conn, "get_deposit", params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    break_db_err (result);
    goto EXITIF_exit;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  if (1 != PQntuples (result))
  {
    GNUNET_break (0);
    goto EXITIF_exit;
  }

  {
    deposit = GNUNET_malloc (sizeof (struct Deposit)); /* Without wire data */
    struct TALER_DB_ResultSpec rs[] = {
      TALER_DB_RESULT_SPEC ("coin_pub", &deposit->coin_pub),
      TALER_DB_RESULT_SPEC ("denom_pub", &deposit->denom_pub),
      TALER_DB_RESULT_SPEC ("coin_sig", &deposit->coin_sig),
      TALER_DB_RESULT_SPEC ("transaction_id", &deposit->transaction_id),
      TALER_DB_RESULT_SPEC ("merchant_pub", &deposit->merchant_pub),
      TALER_DB_RESULT_SPEC ("h_contract", &deposit->h_contract),
      TALER_DB_RESULT_SPEC ("h_wire", &deposit->h_wire),
      TALER_DB_RESULT_SPEC_END
    };
    EXITIF (GNUNET_OK != TALER_DB_extract_result (result, rs, 0));
    EXITIF (GNUNET_OK != TALER_DB_extract_amount_nbo (result, 0,
                                                      "amount_value",
                                                      "amount_fraction",
                                                      "amount_currency",
                                                      &deposit->amount));
    deposit->purpose.purpose = htonl (TALER_SIGNATURE_DEPOSIT);
    deposit->purpose.size = htonl (sizeof (struct Deposit)
                                   - offsetof (struct Deposit, purpose));
  }

  PQclear (result);
  *r_deposit = deposit;
  return GNUNET_OK;

EXITIF_exit:
  PQclear (result);
  GNUNET_free_non_null (deposit);
  deposit = NULL;
  return GNUNET_SYSERR;
}



/**
 * Get the thread-local database-handle.
 * Connect to the db if the connection does not exist yet.
 *
 * @param the database connection, or NULL on error
 */
PGconn *
TALER_MINT_DB_get_connection (void)
{
  PGconn *db_conn;

  if (NULL != (db_conn = pthread_getspecific (db_conn_threadlocal)))
    return db_conn;

  db_conn = PQconnectdb (TALER_MINT_db_connection_cfg_str);

  if (CONNECTION_OK != PQstatus (db_conn))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "db connection failed: %s\n",
                PQerrorMessage (db_conn));
    GNUNET_break (0);
    return NULL;
  }

  if (GNUNET_OK != TALER_MINT_DB_prepare (db_conn))
  {
    GNUNET_break (0);
    return NULL;
  }
  if (0 != pthread_setspecific (db_conn_threadlocal, db_conn))
  {
    GNUNET_break (0);
    return NULL;
  }
  return db_conn;
}


/**
 * Close thread-local database connection when a thread is destroyed.
 *
 * @param closure we get from pthreads (the db handle)
 */
static void
db_conn_destroy (void *cls)
{
  PGconn *db_conn = cls;
  if (NULL != db_conn)
    PQfinish (db_conn);
}


/**
 * Initialize database subsystem.
 *
 * @param connection_cfg configuration to use to talk to DB
 * @return GNUNET_OK on success
 */
int
TALER_MINT_DB_init (const char *connection_cfg)
{

  if (0 != pthread_key_create (&db_conn_threadlocal, &db_conn_destroy))
  {
    fprintf (stderr,
             "Can't create pthread key.\n");
    return GNUNET_SYSERR;
  }
  TALER_MINT_db_connection_cfg_str = GNUNET_strdup (connection_cfg);
  return GNUNET_OK;
}
