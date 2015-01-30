/*
  This file is part of TALER
  (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @brief Low-level (statement-level) database access for the mint
 * @author Florian Dold
 * @author Christian Grothoff
 *
 * TODO:
 * - The mint_db.h-API should ideally be what we need to port
 *   when using other databases; so here we should enable
 *   alternative implementations by returning
 *   a more opaque DB handle.
 */
#include "platform.h"
#include "db_pq.h"
#include "taler_signatures.h"
#include "taler-mint-httpd_responses.h"
#include "mint_db.h"
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
TALER_MINT_DB_insert_refresh_collectable (PGconn *db_conn,
                                          uint16_t newcoin_index,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                          const struct GNUNET_CRYPTO_rsa_Signature *ev_sig)
{
  uint16_t newcoin_index_nbo = htons (newcoin_index);
  char *buf;
  size_t buf_size;
  PGresult *result;

  buf_size = GNUNET_CRYPTO_rsa_signature_encode (ev_sig,
                                                 &buf);
  {
    struct TALER_DB_QueryParam params[] = {
      TALER_DB_QUERY_PARAM_PTR(session_pub),
      TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
      TALER_DB_QUERY_PARAM_PTR_SIZED(buf, buf_size),
      TALER_DB_QUERY_PARAM_END
    };
    result = TALER_DB_exec_prepared (db_conn,
                                     "insert_refresh_collectable",
                                     params);
  }
  GNUNET_free (buf);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


struct GNUNET_CRYPTO_rsa_Signature *
TALER_MINT_DB_get_refresh_collectable (PGconn *db_conn,
                                       uint16_t newcoin_index,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub)
{
  struct GNUNET_CRYPTO_rsa_Signature *ev_sig;
  char *buf;
  size_t buf_size;
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
    return NULL;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    /* FIXME: may want to distinguish between different error cases! */
    return NULL;
  }

  GNUNET_assert (1 == PQntuples (result));

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC_VAR("ev_sig", &buf, &buf_size),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_OK != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_break (0);
    return NULL;
  }

  PQclear (result);
  ev_sig = GNUNET_CRYPTO_rsa_signature_decode (buf,
                                               buf_size);
  GNUNET_free (buf);
  return ev_sig;
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
    struct TALER_RefreshLinkEncrypted *link_enc;
    struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
    struct GNUNET_CRYPTO_rsa_Signature *sig;
    char *ld_buf;
    size_t ld_buf_size;
    char *pk_buf;
    size_t pk_buf_size;
    char *sig_buf;
    size_t sig_buf_size;
    struct TALER_DB_ResultSpec rs[] = {
      TALER_DB_RESULT_SPEC_VAR("link_vector_enc", &ld_buf, &ld_buf_size),
      TALER_DB_RESULT_SPEC_VAR("denom_pub", &pk_buf, &pk_buf_size),
      TALER_DB_RESULT_SPEC_VAR("ev_sig", &sig_buf, &sig_buf_size),
      TALER_DB_RESULT_SPEC_END
    };

    if (GNUNET_OK != TALER_DB_extract_result (result, rs, i))
    {
      PQclear (result);
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    if (ld_buf_size < sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey))
    {
      PQclear (result);
      GNUNET_free (pk_buf);
      GNUNET_free (sig_buf);
      GNUNET_free (ld_buf);
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    link_enc = GNUNET_malloc (sizeof (struct TALER_RefreshLinkEncrypted) +
                              ld_buf_size - sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey));
    link_enc->blinding_key_enc = (const char *) &link_enc[1];
    link_enc->blinding_key_enc_size = ld_buf_size - sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey);
    memcpy (link_enc->coin_priv_enc,
            ld_buf,
            ld_buf_size);

    sig = GNUNET_CRYPTO_rsa_signature_decode (sig_buf,
                                              sig_buf_size);
    denom_pub = GNUNET_CRYPTO_rsa_public_key_decode (pk_buf,
                                                     pk_buf_size);
    GNUNET_free (pk_buf);
    GNUNET_free (sig_buf);
    GNUNET_free (ld_buf);
    if ( (NULL == sig) ||
         (NULL == denom_pub) )
    {
      if (NULL != denom_pub)
        GNUNET_CRYPTO_rsa_public_key_free (denom_pub);
      if (NULL != sig)
        GNUNET_CRYPTO_rsa_signature_free (sig);
      GNUNET_free (link_enc);
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK != (res = link_iter (cls,
                                       link_enc,
                                       denom_pub,
                                       sig)))
    {
      GNUNET_assert (GNUNET_SYSERR != res);
      GNUNET_CRYPTO_rsa_signature_free (sig);
      GNUNET_CRYPTO_rsa_public_key_free (denom_pub);
      GNUNET_free (link_enc);
      PQclear (result);
      return res;
    }
    GNUNET_CRYPTO_rsa_signature_free (sig);
    GNUNET_CRYPTO_rsa_public_key_free (denom_pub);
    GNUNET_free (link_enc);
  }

  return GNUNET_OK;
}


int
TALER_db_get_transfer (PGconn *db_conn,
                       const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                       struct GNUNET_CRYPTO_EcdsaPublicKey *transfer_pub,
                       struct GNUNET_HashCode *shared_secret_enc)
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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "got %d tuples for get_transfer\n",
                PQntuples (result));
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





// Chaos
////////////////////////////////////////////////////////////////
// Order



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
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_DB_init (const char *connection_cfg)
{
  if (0 != pthread_key_create (&db_conn_threadlocal,
                               &db_conn_destroy))
  {
    LOG_ERROR ("Cannnot create pthread key.\n");
    return GNUNET_SYSERR;
  }
  TALER_MINT_db_connection_cfg_str = GNUNET_strdup (connection_cfg);
  return GNUNET_OK;
}


/**
 * Get the thread-local database-handle.
 * Connect to the db if the connection does not exist yet.
 *
 * @return the database connection, or NULL on error
 */
PGconn *
TALER_MINT_DB_get_connection (void)
{
  PGconn *db_conn;

  if (NULL != (db_conn = pthread_getspecific (db_conn_threadlocal)))
    return db_conn;

  db_conn = PQconnectdb (TALER_MINT_db_connection_cfg_str);

  if (CONNECTION_OK !=
      PQstatus (db_conn))
  {
    LOG_ERROR ("Database connection failed: %s\n",
               PQerrorMessage (db_conn));
    GNUNET_break (0);
    return NULL;
  }

  if (GNUNET_OK !=
      TALER_MINT_DB_prepare (db_conn))
  {
    GNUNET_break (0);
    return NULL;
  }
  if (0 != pthread_setspecific (db_conn_threadlocal,
                                db_conn))
  {
    GNUNET_break (0);
    return NULL;
  }
  return db_conn;
}


/**
 * Start a transaction.
 *
 * @param db_conn the database connection
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_DB_transaction (PGconn *db_conn)
{
  PGresult *result;

  result = PQexec (db_conn,
                   "BEGIN");
  if (PGRES_COMMAND_OK !=
      PQresultStatus (result))
  {
    LOG_ERROR ("Failed to start transaction: %s\n",
               PQresultErrorMessage (result));
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


/**
 * Roll back the current transaction of a database connection.
 *
 * @param db_conn the database connection
 * @return #GNUNET_OK on success
 */
void
TALER_MINT_DB_rollback (PGconn *db_conn)
{
  PGresult *result;

  result = PQexec (db_conn,
                   "ROLLBACK");
  GNUNET_break (PGRES_COMMAND_OK ==
                PQresultStatus (result));
  PQclear (result);
}


/**
 * Commit the current transaction of a database connection.
 *
 * @param db_conn the database connection
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_DB_commit (PGconn *db_conn)
{
  PGresult *result;

  result = PQexec (db_conn,
                   "COMMIT");
  if (PGRES_COMMAND_OK !=
      PQresultStatus (result))
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}






/**
 * Locate the response for a /withdraw request under the
 * key of the hash of the blinded message.
 *
 * @param db_conn database connection to use
 * @param h_blind hash of the blinded message
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return #GNUNET_SYSERR on internal error
 *         #GNUNET_NO if the collectable was not found
 *         #GNUNET_YES on success
 */
int
TALER_MINT_DB_get_collectable_blindcoin (PGconn *db_conn,
                                         const struct GNUNET_HashCode *h_blind,
                                         struct CollectableBlindcoin *collectable)
{
  // FIXME: check logic!
  PGresult *result;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (h_blind),
    TALER_DB_QUERY_PARAM_END
  };
  char *sig_buf;
  size_t sig_buf_size;

  result = TALER_DB_exec_prepared (db_conn,
                                   "get_collectable_blindcoins",
                                   params);

  if (PGRES_TUPLES_OK !=
      PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Query failed: %s\n",
                PQresultErrorMessage (result));
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC_VAR("blind_sig", &sig_buf, &sig_buf_size),
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
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Store collectable bit coin under the corresponding
 * hash of the blinded message.
 *
 * @param db_conn database connection to use
 * @param h_blind hash of the blinded message
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return #GNUNET_SYSERR on internal error
 *         #GNUNET_NO if the collectable was not found
 *         #GNUNET_YES on success
 */
int
TALER_MINT_DB_insert_collectable_blindcoin (PGconn *db_conn,
                                            const struct GNUNET_HashCode *h_blind,
                                            const struct CollectableBlindcoin *collectable)
{
  // FIXME: check logic!
  PGresult *result;
  char *sig_buf;
  size_t sig_buf_size;

  sig_buf_size = GNUNET_CRYPTO_rsa_signature_encode (collectable->sig,
                                                     &sig_buf);
  {
    struct TALER_DB_QueryParam params[] = {
      TALER_DB_QUERY_PARAM_PTR (&h_blind),
      TALER_DB_QUERY_PARAM_PTR_SIZED (sig_buf, sig_buf_size),
      TALER_DB_QUERY_PARAM_PTR (&collectable->denom_pub),
      TALER_DB_QUERY_PARAM_PTR (&collectable->reserve_pub),
      TALER_DB_QUERY_PARAM_PTR (&collectable->reserve_sig),
      TALER_DB_QUERY_PARAM_END
    };

    result = TALER_DB_exec_prepared (db_conn,
                                     "insert_collectable_blindcoins",
                                     params);
    if (PGRES_COMMAND_OK != PQresultStatus (result))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Query failed: %s\n",
                  PQresultErrorMessage (result));
      PQclear (result);
      return GNUNET_SYSERR;
    }

    if (0 != strcmp ("1", PQcmdTuples (result)))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Insert failed (updated '%s' tupes instead of '1')\n",
                    PQcmdTuples (result));
        PQclear (result);
        return GNUNET_SYSERR;
      }
    PQclear (result);
  }
  return GNUNET_OK;
}


/**
 * Get all of the transaction history associated with the specified
 * reserve.
 *
 * @param db_conn connection to use
 * @param reserve_pub public key of the reserve
 * @return known transaction history (NULL if reserve is unknown)
 */
struct ReserveHistory *
TALER_MINT_DB_get_reserve_history (PGconn *db_conn,
                                   const struct GNUNET_CRYPTO_EddsaPublicKey *reserve_pub)
{
  // FIXME: implement logic!
  PGresult *result;
  // int res;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (reserve_pub),
    TALER_DB_QUERY_PARAM_END
  };

  result = TALER_DB_exec_prepared (db_conn, "get_reserve", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Query failed: %s\n",
                PQresultErrorMessage (result));
    PQclear (result);
    return NULL;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return NULL;
  }
#if 0
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
    if (GNUNET_OK !=
        TALER_DB_extract_amount_nbo (result, 0,
                                     "balance_value",
                                     "balance_fraction",
                                     "balance_currency",
                                     &reserve->balance))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
  }

  /* FIXME: Add expiration?? */

  PQclear (result);
  return GNUNET_OK;
#endif
  return NULL;
}


/**
 * Free memory associated with the given reserve history.
 *
 * @param rh history to free.
 */
void
TALER_MINT_DB_free_reserve_history (struct ReserveHistory *rh)
{
  // FIXME: implement
  GNUNET_assert (0);
}


/**
 * Check if we have the specified deposit already in the database.
 *
 * @param db_conn database connection
 * @param deposit deposit to search for
 * @return #GNUNET_YES if we know this operation,
 *         #GNUNET_NO if this deposit is unknown to us
 */
int
TALER_MINT_DB_have_deposit (PGconn *db_conn,
                            const struct Deposit *deposit)
{
  // FIXME: check logic!
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (&deposit->coin.coin_pub), // FIXME
    TALER_DB_QUERY_PARAM_END
  };
  PGresult *result;

  result = TALER_DB_exec_prepared (db_conn,
                                   "get_deposit",
                                   params);
  if (PGRES_TUPLES_OK !=
      PQresultStatus (result))
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
  return GNUNET_YES;
}


/**
 * Insert information about deposited coin into the
 * database.
 *
 * @param db_conn connection to the database
 * @param deposit deposit information to store
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_MINT_DB_insert_deposit (PGconn *db_conn,
                              const struct Deposit *deposit)
{
  // FIXME: check logic!
  struct TALER_DB_QueryParam params[]= {
    TALER_DB_QUERY_PARAM_PTR (&deposit->coin.coin_pub),
    TALER_DB_QUERY_PARAM_PTR (&deposit->coin.denom_pub), // FIXME!
    TALER_DB_QUERY_PARAM_PTR (&deposit->coin.denom_sig), // FIXME!
    TALER_DB_QUERY_PARAM_PTR (&deposit->transaction_id),
    TALER_DB_QUERY_PARAM_PTR (&deposit->amount.value),
    TALER_DB_QUERY_PARAM_PTR (&deposit->amount.fraction),
    TALER_DB_QUERY_PARAM_PTR_SIZED (deposit->amount.currency,
                                    strlen (deposit->amount.currency)),
    TALER_DB_QUERY_PARAM_PTR (&deposit->merchant_pub),
    TALER_DB_QUERY_PARAM_PTR (&deposit->h_contract),
    TALER_DB_QUERY_PARAM_PTR (&deposit->h_wire),
    TALER_DB_QUERY_PARAM_PTR (&deposit->csig),
    TALER_DB_QUERY_PARAM_PTR_SIZED (deposit->wire,
                                    strlen ("FIXME")), // FIXME! json!
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


/**
 * Lookup refresh session data under the given public key.
 *
 * @param db_conn database handle to use
 * @param refresh_session_pub public key to use for the lookup
 * @param session[OUT] where to store the result
 * @return #GNUNET_YES on success,
 *         #GNUNET_NO if not found,
 *         #GNUNET_SYSERR on DB failure
 */
int
TALER_MINT_DB_get_refresh_session (PGconn *db_conn,
                                   const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                   struct RefreshSession *session)
{
  // FIXME: check logic!
  int res;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_refresh_session", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Query failed: %s\n",
                PQresultErrorMessage (result));
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

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("num_oldcoins", &session->num_oldcoins),
    TALER_DB_RESULT_SPEC("num_newcoins", &session->num_newcoins),
    TALER_DB_RESULT_SPEC("kappa", &session->kappa),
    TALER_DB_RESULT_SPEC("noreveal_index", &session->noreveal_index),
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


/**
 * Store new refresh session data under the given public key.
 *
 * @param db_conn database handle to use
 * @param refresh_session_pub public key to use to locate the session
 * @param session session data to store
 * @return #GNUNET_YES on success,
 *         #GNUNET_SYSERR on DB failure
 */
int
TALER_MINT_DB_create_refresh_session (PGconn *db_conn,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                      const struct RefreshSession *session)
{
  // FIXME: actually store session data!
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


/**
 * Update new refresh session with the new state after the
 * /refresh/commit operation.
 *
 * @param db_conn database handle to use
 * @param refresh_session_pub public key to use to locate the session
 * @param noreveal_index index chosen for the client to not reveal
 * @param commit_client_sig signature of the client over its commitment
 * @return #GNUNET_YES on success,
 *         #GNUNET_SYSERR on DB failure
 */
int
TALER_MINT_DB_update_refresh_session (PGconn *db_conn,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                      uint16_t noreveal_index,
                                      const struct GNUNET_CRYPTO_EddsaSignature *commit_client_sig)
{
  // FIXME: implement!
  return GNUNET_SYSERR;
}


/**
 * Store the given /refresh/melt request in the database.
 *
 * @param db_conn database connection
 * @param session session key of the melt operation
 * @param oldcoin_index index of the coin to store
 * @param melt melt operation
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_insert_refresh_melt (PGconn *db_conn,
                                   const struct GNUNET_CRYPTO_EddsaPublicKey *session,
                                   uint16_t oldcoin_index,
                                   const struct RefreshMelt *melt)
{
  // FIXME: check logic!
  uint16_t oldcoin_index_nbo = htons (oldcoin_index);
  char *buf;
  size_t buf_size;
  PGresult *result;

  buf_size = GNUNET_CRYPTO_rsa_public_key_encode (melt->coin.denom_pub,
                                                  &buf);
  {
    struct TALER_DB_QueryParam params[] = {
      TALER_DB_QUERY_PARAM_PTR(session),
      TALER_DB_QUERY_PARAM_PTR(&oldcoin_index_nbo),
      TALER_DB_QUERY_PARAM_PTR(&melt->coin.coin_pub),
      TALER_DB_QUERY_PARAM_PTR_SIZED(buf, buf_size),
      TALER_DB_QUERY_PARAM_END
    };
    result = TALER_DB_exec_prepared (db_conn, "insert_refresh_melt", params);
  }
  GNUNET_free (buf);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    break_db_err (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Get information about melted coin details from the database.
 *
 * @param db_conn database connection
 * @param session session key of the melt operation
 * @param oldcoin_index index of the coin to retrieve
 * @param melt melt data to fill in
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_get_refresh_melt (PGconn *db_conn,
                                const struct GNUNET_CRYPTO_EddsaPublicKey *session,
                                uint16_t oldcoin_index,
                                struct RefreshMelt *melt)
{
  // FIXME: check logic!
  GNUNET_break (0);
  return GNUNET_SYSERR;
}


/**
 * Store in the database which coin(s) we want to create
 * in a given refresh operation.
 *
 * @param db_conn database connection
 * @param session_pub refresh session key
 * @param newcoin_index index of the coin to generate
 * @param denom_pub denomination of the coin to create
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_insert_refresh_order (PGconn *db_conn,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                    uint16_t newcoin_index,
                                    const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub)
{
  // FIXME: check logic
  uint16_t newcoin_index_nbo = htons (newcoin_index);
  char *buf;
  size_t buf_size;
  PGresult *result;

  buf_size = GNUNET_CRYPTO_rsa_public_key_encode (denom_pub,
                                                  &buf);

  {
    struct TALER_DB_QueryParam params[] = {
      TALER_DB_QUERY_PARAM_PTR (&newcoin_index_nbo),
      TALER_DB_QUERY_PARAM_PTR (session_pub),
      TALER_DB_QUERY_PARAM_PTR_SIZED (buf, buf_size),
      TALER_DB_QUERY_PARAM_END
    };
    result = TALER_DB_exec_prepared (db_conn,
                                     "insert_refresh_order",
                                     params);
  }
  GNUNET_free (buf);
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


/**
 * Lookup in the database the @a newcoin_index coin that we want to
 * create in the given refresh operation.
 *
 * @param db_conn database connection
 * @param session_pub refresh session key
 * @param newcoin_index index of the coin to generate
 * @param denom_pub denomination of the coin to create
 * @return NULL on error (not found or internal error)
 */
struct GNUNET_CRYPTO_rsa_PublicKey *
TALER_MINT_DB_get_refresh_order (PGconn *db_conn,
                                 const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                 uint16_t newcoin_index)
{
  // FIXME: check logic
  char *buf;
  size_t buf_size;
  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
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
    return NULL;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    /* FIXME: may want to distinguish between different error cases! */
    return NULL;
  }
  GNUNET_assert (1 == PQntuples (result));
  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC_VAR ("denom_pub", &buf, &buf_size),
    TALER_DB_RESULT_SPEC_END
  };
  if (GNUNET_OK != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_break (0);
    return NULL;
  }
  PQclear (result);
  denom_pub = GNUNET_CRYPTO_rsa_public_key_decode (buf, buf_size);
  GNUNET_free (buf);
  return denom_pub;
}



/**
 * Store information about the commitment of the
 * given coin for the given refresh session in the database.
 *
 * @param db_conn database connection to use
 * @param refresh_session_pub refresh session this commitment belongs to
 * @param i set index (1st dimension)
 * @param j coin index (2nd dimension), corresponds to refreshed (new) coins
 * @param commit_coin coin commitment to store
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on error
 */
int
TALER_MINT_DB_insert_refresh_commit_coin (PGconn *db_conn,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                          unsigned int i,
                                          unsigned int j,
                                          const struct RefreshCommitCoin *commit_coin)
{
  // FIXME: check logic!
  uint16_t cnc_index_nbo = htons (i);
  uint16_t newcoin_index_nbo = htons (j);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_PTR_SIZED(commit_coin->coin_ev, commit_coin->coin_ev_size),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_PTR_SIZED(commit_coin->refresh_link->coin_priv_enc,
                                   commit_coin->refresh_link->blinding_key_enc_size +
                                   sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey)),
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


/**
 * Obtain information about the commitment of the
 * given coin of the given refresh session from the database.
 *
 * @param db_conn database connection to use
 * @param refresh_session_pub refresh session the commitment belongs to
 * @param i set index (1st dimension)
 * @param j coin index (2nd dimension), corresponds to refreshed (new) coins
 * @param commit_coin[OUT] coin commitment to return
 * @return #GNUNET_OK on success
 *         #GNUNET_NO if not found
 *         #GNUNET_SYSERR on error
 */
int
TALER_MINT_DB_get_refresh_commit_coin (PGconn *db_conn,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                       unsigned int cnc_index,
                                       unsigned int newcoin_index,
                                       struct RefreshCommitCoin *cc)
{
  // FIXME: check logic!
  uint16_t cnc_index_nbo = htons (cnc_index);
  uint16_t newcoin_index_nbo = htons (newcoin_index);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_END
  };
  char *c_buf;
  size_t c_buf_size;
  char *rl_buf;
  size_t rl_buf_size;
  struct TALER_RefreshLinkEncrypted *rl;

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
    TALER_DB_RESULT_SPEC_VAR("coin_ev", &c_buf, &c_buf_size),
    TALER_DB_RESULT_SPEC_VAR("link_vector_enc", &rl_buf, &rl_buf_size),
    TALER_DB_RESULT_SPEC_END
  };
  if (GNUNET_YES != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  if (rl_buf_size < sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey))
  {
    GNUNET_free (c_buf);
    GNUNET_free (rl_buf);
    return GNUNET_SYSERR;
  }
  rl = TALER_refresh_link_encrypted_decode (rl_buf,
                                            rl_buf_size);
  GNUNET_free (rl_buf);
  cc->refresh_link = rl;
  cc->coin_ev = c_buf;
  cc->coin_ev_size = c_buf_size;
  return GNUNET_YES;
}


/**
 * Store the commitment to the given (encrypted) refresh link data
 * for the given refresh session.
 *
 * @param db_conn database connection to use
 * @param refresh_session_pub public key of the refresh session this
 *        commitment belongs with
 * @param i set index (1st dimension)
 * @param j coin index (2nd dimension), corresponds to melted (old) coins
 * @param commit_link link information to store
 * @return #GNUNET_SYSERR on internal error, #GNUNET_OK on success
 */
int
TALER_MINT_DB_insert_refresh_commit_link (PGconn *db_conn,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                          unsigned int i,
                                          unsigned int j,
                                          const struct RefreshCommitLink *commit_link)
{
  // FIXME: check logic!
  uint16_t cnc_index_nbo = htons (i);
  uint16_t oldcoin_index_nbo = htons (j);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_PTR(&commit_link->transfer_pub),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&oldcoin_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&commit_link->shared_secret_enc),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn,
                                             "insert_refresh_commit_link",
                                             params);
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


/**
 * Obtain the commited (encrypted) refresh link data
 * for the given refresh session.
 *
 * @param db_conn database connection to use
 * @param refresh_session_pub public key of the refresh session this
 *        commitment belongs with
 * @param i set index (1st dimension)
 * @param j coin index (2nd dimension), corresponds to melted (old) coins
 * @param cc[OUT] link information to return
 * @return #GNUNET_SYSERR on internal error,
 *         #GNUNET_NO if commitment was not found
 *         #GNUNET_OK on success
 */
int
TALER_MINT_DB_get_refresh_commit_link (PGconn *db_conn,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                       unsigned int cnc_index,
                                       unsigned int oldcoin_index,
                                       struct RefreshCommitLink *cc)
{
  // FIXME: check logic!
  uint16_t cnc_index_nbo = htons (cnc_index);
  uint16_t oldcoin_index_nbo = htons (oldcoin_index);

  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&oldcoin_index_nbo),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn,
                                             "get_refresh_commit_link",
                                             params);
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
    TALER_DB_RESULT_SPEC("link_secret_enc", &cc->shared_secret_enc),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_YES != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_free (cc);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}





/**
 * Compile a list of all (historic) transactions performed
 * with the given coin (/refresh/melt and /deposit operations).
 *
 * @param db_conn database connection
 * @param coin_pub coin to investigate
 * @return list of transactions, NULL if coin is fresh
 */
struct TALER_MINT_DB_TransactionList *
TALER_MINT_DB_get_coin_transactions (PGconn *db_conn,
                                     const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub)
{
  // FIXME: check logic!
  GNUNET_break (0); // FIXME: implement!
  return NULL;
}


/**
 * Free linked list of transactions.
 *
 * @param list list to free
 */
void
TALER_MINT_DB_free_coin_transaction_list (struct TALER_MINT_DB_TransactionList *list)
{
  // FIXME: check logic!
  GNUNET_break (0);
}


/* end of mint_db.c */
