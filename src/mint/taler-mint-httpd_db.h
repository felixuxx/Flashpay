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
 * @file mint/taler-mint_httpd_db.h
 * @brief Mint-specific database access
 * @author Chrisitan Grothoff
 */
#ifndef TALER_MINT_HTTPD_DB_H
#define TALER_MINT_HTTPD_DB_H

#include <libpq-fe.h>
#include <microhttpd.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler-mint-httpd_keys.h"
#include "mint.h"



/**
 * Execute a /deposit.  The validity of the coin and signature
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
                               const struct Deposit *deposit);


/**
 * Execute a /withdraw/status.
 *
 * @param connection the MHD connection to handle
 * @param reserve_pub public key of the reserve to check
 * @return MHD result code
 */
int
TALER_MINT_db_execute_withdraw_status (struct MHD_Connection *connection,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *reserve_pub);


/**
 * Execute a /withdraw/sign.
 *
 * @param connection the MHD connection to handle
 * @param reserve public key of the reserve
 * @param denomination_pub public key of the denomination requested
 * @param blinded_msg blinded message to be signed
 * @param blinded_msg_len number of bytes in @a blinded_msg
 * @param signature signature over the withdraw request, to be stored in DB
 * @return MHD result code
 */
int
TALER_MINT_db_execute_withdraw_sign (struct MHD_Connection *connection,
                                     const struct GNUNET_CRYPTO_EddsaPublicKey *reserve,
                                     const struct GNUNET_CRYPTO_rsa_PublicKey *denomination_pub,
                                     const char *blinded_msg,
                                     size_t blinded_msg_len,
                                     const struct GNUNET_CRYPTO_EddsaSignature *signature);



/**
 * Execute a /refresh/melt.
 *
 * @param connection the MHD connection to handle
 * @param refresh_session_pub public key of the refresh session
 * @param num_new_denoms number of entries in @a denom_pubs
 * @param denum_pubs array of public denomination keys for the refresh (?)
 * @param coin_count number of entries in @a coin_public_infos
 * @param coin_public_infos information about the coins to melt
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_melt (struct MHD_Connection *connection,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                    unsigned int num_new_denoms,
                                    const struct GNUNET_CRYPTO_rsa_PublicKey **denom_pubs,
                                    unsigned int coin_count,
                                    const struct TALER_CoinPublicInfo *coin_public_infos);


/**
 * Execute a /refresh/commit.
 *
 * @param connection the MHD connection to handle
 * @param kappa size of x-dimension of @commit_coin and @commit_link arrays
 * @param num_oldcoins size of y-dimension of @commit_coin array
 * @param num_newcoins size of y-dimension of @commit_link array
 * @param commit_coin
 * @param commit_link
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_commit (struct MHD_Connection *connection,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                      unsigned int kappa,
                                      unsigned int num_oldcoins,
                                      unsigned int num_newcoins,
                                      struct RefreshCommitCoin *const* commit_coin,
                                      struct RefreshCommitLink *const* commit_link);


/**
 * Execute a /refresh/reveal.
 *
 * @param connection the MHD connection to handle
 * @param refresh_session_pub public key of the refresh session
 * @param kappa size of x-dimension of @transfer_privs array plus one (!)
 * @param num_oldcoins size of y-dimension of @transfer_privs array
 * @param transfer_pubs array with the revealed transfer keys
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_reveal (struct MHD_Connection *connection,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                      unsigned int kappa,
                                      unsigned int num_oldcoins,
                                      struct GNUNET_CRYPTO_EcdsaPrivateKey *const*transfer_privs);


/**
 * Execute a /refresh/link.
 *
 * @param connection the MHD connection to handle
 * @param coin_pub public key of the coin to link
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_link (struct MHD_Connection *connection,
                                    const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub);


#endif /* _NEURO_MINT_DB_H */
