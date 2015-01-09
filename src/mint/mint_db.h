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
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_rsa.h"


/**
 * Public information about a coin.
 */
struct TALER_CoinPublicInfo
{
  /**
   * The coin's public key.
   */
  struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;

  /*
   * The public key signifying the coin's denomination.
   */
  struct TALER_RSA_PublicKeyBinaryEncoded denom_pub;

  /**
   * Signature over coin_pub by denom_pub.
   */
  struct TALER_RSA_Signature denom_sig;
};






/**
 * Reserve row.  Corresponds to table 'reserves' in
 * the mint's database.
 */
struct Reserve
{
  /**
   * Signature over the purse.
   * Only valid if (blind_session_missing==GNUNET_YES).
   */
  struct GNUNET_CRYPTO_EddsaSignature status_sig;
  /**
   * Signature with purpose TALER_SIGNATURE_PURSE.
   * Only valid if (blind_session_missing==GNUNET_YES).
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose status_sig_purpose;
  /**
   * Signing key used to sign the purse.
   * Only valid if (blind_session_missing==GNUNET_YES).
   */
  struct GNUNET_CRYPTO_EddsaPublicKey status_sign_pub;
  /**
   * Withdraw public key, identifies the purse.
   * Only the customer knows the corresponding private key.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;
  /**
   * Remaining balance in the purse.
   */
  struct TALER_AmountNBO balance;

  /**
   * Expiration date for the purse.
   */
  struct GNUNET_TIME_AbsoluteNBO expiration;
};


struct CollectableBlindcoin
{
  struct TALER_RSA_BlindedSignaturePurpose ev;
  struct TALER_RSA_Signature ev_sig;
  struct TALER_RSA_PublicKeyBinaryEncoded denom_pub;
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;
  struct GNUNET_CRYPTO_EddsaSignature reserve_sig;
};


struct RefreshSession
{
  int has_commit_sig;
  struct GNUNET_CRYPTO_EddsaSignature commit_sig;
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;
  uint16_t num_oldcoins;
  uint16_t num_newcoins;
  uint16_t kappa;
  uint16_t noreveal_index;
  uint8_t reveal_ok;
};


#define TALER_REFRESH_SHARED_SECRET_LENGTH (sizeof (struct GNUNET_HashCode))
#define TALER_REFRESH_LINK_LENGTH (sizeof (struct LinkData))

struct RefreshCommitLink
{
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;
  struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub;
  uint16_t cnc_index;
  uint16_t oldcoin_index;
  char shared_secret_enc[sizeof (struct GNUNET_HashCode)];
};

struct LinkData
{
  struct GNUNET_CRYPTO_EcdsaPrivateKey coin_priv;
  struct TALER_RSA_BlindingKeyBinaryEncoded bkey_enc;
};


GNUNET_NETWORK_STRUCT_BEGIN

struct SharedSecretEnc
{
  char data[TALER_REFRESH_SHARED_SECRET_LENGTH];
};


struct LinkDataEnc
{
  char data[sizeof (struct LinkData)];
};

GNUNET_NETWORK_STRUCT_END

struct RefreshCommitCoin
{
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;
  struct TALER_RSA_BlindedSignaturePurpose coin_ev;
  uint16_t cnc_index;
  uint16_t newcoin_index;
  char link_enc[sizeof (struct LinkData)];
};


struct KnownCoin
{
  struct TALER_CoinPublicInfo public_info;
  struct TALER_Amount expended_balance;
  int is_refreshed;
  /**
   * Refreshing session, only valid if
   * is_refreshed==1.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey refresh_session_pub;
};

GNUNET_NETWORK_STRUCT_BEGIN

struct Deposit
{
  /* FIXME: should be TALER_CoinPublicInfo */
  struct GNUNET_CRYPTO_EddsaPublicKey coin_pub;
  struct TALER_RSA_PublicKeyBinaryEncoded denom_pub;
  struct TALER_RSA_Signature coin_sig;
  struct TALER_RSA_SignaturePurpose purpose;
  uint64_t transaction_id;
  struct TALER_AmountNBO amount;
  struct GNUNET_CRYPTO_EddsaPublicKey merchant_pub;
  struct GNUNET_HashCode h_contract;
  struct GNUNET_HashCode h_wire;
  /* TODO: uint16_t wire_size */
  char wire[];                  /* string encoded wire JSON object */
};

GNUNET_NETWORK_STRUCT_END

int
TALER_MINT_DB_prepare (PGconn *db_conn);

int
TALER_MINT_DB_get_collectable_blindcoin (PGconn *db_conn,
                                         struct TALER_RSA_BlindedSignaturePurpose *blind_ev,
                                         struct CollectableBlindcoin *collectable);

int
TALER_MINT_DB_insert_collectable_blindcoin (PGconn *db_conn,
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

int
TALER_MINT_DB_update_reserve (PGconn *db_conn,
                              const struct Reserve *reserve,
                              int fresh);


int
TALER_MINT_DB_insert_refresh_order (PGconn *db_conn,
                                    uint16_t newcoin_index,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                    const struct TALER_RSA_PublicKeyBinaryEncoded *denom_pub);

int
TALER_MINT_DB_get_refresh_session (PGconn *db_conn,
                                   const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                   struct RefreshSession *r_session);


int
TALER_MINT_DB_get_known_coin (PGconn *db_conn, struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                              struct KnownCoin *known_coin);


int
TALER_MINT_DB_upsert_known_coin (PGconn *db_conn, struct KnownCoin *known_coin);


int
TALER_MINT_DB_insert_refresh_commit_link (PGconn *db_conn, struct RefreshCommitLink *commit_link);

int
TALER_MINT_DB_insert_refresh_commit_coin (PGconn *db_conn, struct RefreshCommitCoin *commit_coin);


int
TALER_MINT_DB_get_refresh_commit_link (PGconn *db_conn,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                       int i, int j,
                                       struct RefreshCommitLink *commit_link);


int
TALER_MINT_DB_get_refresh_commit_coin (PGconn *db_conn,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                       int i, int j,
                                       struct RefreshCommitCoin *commit_coin);


int
TALER_MINT_DB_create_refresh_session (PGconn *db_conn,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey
                                      *session_pub);


int
TALER_MINT_DB_get_refresh_order (PGconn *db_conn,
                                 uint16_t newcoin_index,
                                 const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                 struct TALER_RSA_PublicKeyBinaryEncoded *denom_pub);


int
TALER_MINT_DB_insert_refresh_collectable (PGconn *db_conn,
                                          uint16_t newcoin_index,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                          const struct TALER_RSA_Signature *ev_sig);
int
TALER_MINT_DB_get_refresh_collectable (PGconn *db_conn,
                                       uint16_t newcoin_index,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                       struct TALER_RSA_Signature *ev_sig);
int
TALER_MINT_DB_set_reveal_ok (PGconn *db_conn,
                             const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub);

int
TALER_MINT_DB_insert_refresh_melt (PGconn *db_conn,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                    uint16_t oldcoin_index,
                                    const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                                    const struct TALER_RSA_PublicKeyBinaryEncoded *denom_pub);


int
TALER_MINT_DB_get_refresh_melt (PGconn *db_conn,
                                const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                uint16_t oldcoin_index,
                                struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub);


typedef
int (*LinkIterator) (void *cls,
                     const struct LinkDataEnc *link_data_enc,
                     const struct TALER_RSA_PublicKeyBinaryEncoded *denom_pub,
                     const struct TALER_RSA_Signature *ev_sig);

int
TALER_db_get_link (PGconn *db_conn,
                   const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                   LinkIterator link_iter,
                   void *cls);


int
TALER_db_get_transfer (PGconn *db_conn,
                       const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                       struct GNUNET_CRYPTO_EcdsaPublicKey *transfer_pub,
                       struct SharedSecretEnc *shared_secret_enc);

int
TALER_MINT_DB_init_deposits (PGconn *db_conn, int temporary);

int
TALER_MINT_DB_prepare_deposits (PGconn *db_conn);

int
TALER_MINT_DB_insert_deposit (PGconn *db_conn,
                              const struct Deposit *deposit);

int
TALER_MINT_DB_get_deposit (PGconn *db_conn,
                           const struct GNUNET_CRYPTO_EddsaPublicKey *coin_pub,
                           struct Deposit **r_deposit);
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
