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
 * @file mint/mint_db.h
 * @brief Mint-specific database access
 * @author Florian Dold
 */

#ifndef _NEURO_MINT_DB_H
#define _NEURO_MINT_DB_H

#include <libpq-fe.h>
#include <microhttpd.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler-mint-httpd_db.h"
#include "mint.h"


int
TALER_MINT_DB_prepare (PGconn *db_conn);


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
                                         struct CollectableBlindcoin *collectable);


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
                                            const struct CollectableBlindcoin *collectable);


int
TALER_MINT_DB_rollback (PGconn *db_conn);


int
TALER_MINT_DB_transaction (PGconn *db_conn);


int
TALER_MINT_DB_commit (PGconn *db_conn);


int
TALER_MINT_DB_get_reserve (PGconn *db_conn,
                           const struct GNUNET_CRYPTO_EddsaPublicKey *reserve_pub,
                           struct Reserve *reserve_res);


/**
 * Update information about a reserve.
 *
 * @param db_conn
 * @param reserve current reserve status
 * @param fresh FIXME
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_DB_update_reserve (PGconn *db_conn,
                              const struct Reserve *reserve,
                              int fresh);


int
TALER_MINT_DB_insert_refresh_order (PGconn *db_conn,
                                    uint16_t newcoin_index,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                    const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub);

int
TALER_MINT_DB_get_refresh_session (PGconn *db_conn,
                                   const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                   struct RefreshSession *r_session);


int
TALER_MINT_DB_get_known_coin (PGconn *db_conn,
                              const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                              struct KnownCoin *known_coin);


int
TALER_MINT_DB_upsert_known_coin (PGconn *db_conn,
                                 struct KnownCoin *known_coin);




int
TALER_MINT_DB_create_refresh_session (PGconn *db_conn,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub);


/**
 * Store the commitment to the given (encrypted) refresh link data
 * for the given refresh session.
 *
 * @param db_conn database connection to use
 * @param refresh_session_pub public key of the refresh session this
 *        commitment belongs with
 * @param i
 * @param j
 * @param commit_link link information to store
 * @return #GNUNET_SYSERR on internal error, #GNUNET_OK on success
 */
int
TALER_MINT_DB_insert_refresh_commit_link (PGconn *db_conn,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                          int i, int j,
                                          const struct RefreshCommitLink *commit_link);


int
TALER_MINT_DB_get_refresh_commit_link (PGconn *db_conn,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                       int i, int j,
                                       struct RefreshCommitLink *cc);


int
TALER_MINT_DB_insert_refresh_commit_coin (PGconn *db_conn,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                          int i,
                                          int j,
                                          const struct RefreshCommitCoin *commit_coin);


int
TALER_MINT_DB_get_refresh_commit_coin (PGconn *db_conn,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                       int i, int j,
                                       struct RefreshCommitCoin *commit_coin);


struct GNUNET_CRYPTO_rsa_PublicKey *
TALER_MINT_DB_get_refresh_order (PGconn *db_conn,
                                 uint16_t newcoin_index,
                                 const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub);


int
TALER_MINT_DB_insert_refresh_collectable (PGconn *db_conn,
                                          uint16_t newcoin_index,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                          const struct GNUNET_CRYPTO_rsa_Signature *ev_sig);


struct GNUNET_CRYPTO_rsa_Signature *
TALER_MINT_DB_get_refresh_collectable (PGconn *db_conn,
                                       uint16_t newcoin_index,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub);



int
TALER_MINT_DB_set_reveal_ok (PGconn *db_conn,
                             const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub);


int
TALER_MINT_DB_insert_refresh_melt (PGconn *db_conn,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                    uint16_t oldcoin_index,
                                    const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                                    const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub);


int
TALER_MINT_DB_get_refresh_melt (PGconn *db_conn,
                                const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                uint16_t oldcoin_index,
                                struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub);


/**
 * FIXME: doc, name is bad, too.
 */
typedef int
(*LinkIterator) (void *cls,
                 const struct TALER_RefreshLinkEncrypted *link_data_enc,
                 const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub,
                 const struct GNUNET_CRYPTO_rsa_Signature *ev_sig);


int
TALER_db_get_link (PGconn *db_conn,
                   const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                   LinkIterator link_iter,
                   void *cls);


/**
 * Obtain shared secret from the transfer public key (?).
 *
 * @param shared_secret_enc[out] set to shared secret; FIXME: use other type
 *               to indicate this is the encrypted secret
 */
int
TALER_db_get_transfer (PGconn *db_conn,
                       const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                       struct GNUNET_CRYPTO_EcdsaPublicKey *transfer_pub,
                       struct GNUNET_HashCode *shared_secret_enc);

int
TALER_MINT_DB_init_deposits (PGconn *db_conn, int temporary);


int
TALER_MINT_DB_prepare_deposits (PGconn *db_conn);


int
TALER_MINT_DB_insert_deposit (PGconn *db_conn,
                              const struct Deposit *deposit);


int
TALER_MINT_DB_get_deposit (PGconn *db_conn,
                           const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                           struct Deposit *r_deposit);


int
TALER_MINT_DB_insert_known_coin (PGconn *db_conn,
                                 const struct KnownCoin *known_coin);


/**
 * Get the thread-local database-handle.
 * Connect to the db if the connection does not exist yet.
 *
 * @param the database connection, or NULL on error
 */
PGconn *
TALER_MINT_DB_get_connection (void);


int
TALER_MINT_DB_init (const char *connection_cfg);



#endif /* _NEURO_MINT_DB_H */
