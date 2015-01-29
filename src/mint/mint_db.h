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
 * @brief Low-level (statement-level) database access for the mint
 * @author Florian Dold
 * @author Christian Grothoff
 */

#ifndef _NEURO_MINT_DB_H
#define _NEURO_MINT_DB_H

#include <libpq-fe.h>
#include <microhttpd.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"


/**
 * FIXME.
 */
int
TALER_MINT_DB_prepare (PGconn *db_conn);


int
TALER_MINT_DB_insert_refresh_order (PGconn *db_conn,
                                    uint16_t newcoin_index,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                    const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub);



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
TALER_TALER_DB_extract_amount (PGresult *result,
                               unsigned int row,
                               int indices[3],
                               struct TALER_Amount *denom);

int
TALER_TALER_DB_extract_amount_nbo (PGresult *result,
                                   unsigned int row,
                                   int indices[3],
                                   struct TALER_AmountNBO *denom_nbo);





// Chaos
////////////////////////////////////////////////////////////////
// Order



/**
 * Initialize database subsystem.
 */
int
TALER_MINT_DB_init (const char *connection_cfg);


/**
 * Get the thread-local database-handle.
 * Connect to the db if the connection does not exist yet.
 *
 * @param the database connection, or NULL on error
 */
PGconn *
TALER_MINT_DB_get_connection (void);


/**
 * Start a transaction.
 *
 * @param db_conn connection to use
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_DB_transaction (PGconn *db_conn);


/**
 * Commit a transaction.
 *
 * @param db_conn connection to use
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_DB_commit (PGconn *db_conn);


/**
 * Abort/rollback a transaction.
 *
 * @param db_conn connection to use
 */
void
TALER_MINT_DB_rollback (PGconn *db_conn);


/**
 * Information we keep on a bank transfer that
 * established a reserve.
 */
struct BankTransfer
{

  /**
   * Public key of the reserve that was filled.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;

  /**
   * Amount that was transferred to the mint.
   */
  struct TALER_Amount amount;

  /**
   * Detailed wire information about the transaction.
   */
  const json_t *wire;

};


/* FIXME: add functions to add bank transfers to our DB
   (and to test if we already did add one) (#3633) */


/**
 * Information we keep for a withdrawn coin to reproduce
 * the /withdraw operation if needed, and to have proof
 * that a reserve was drained by this amount.
 */
struct CollectableBlindcoin
{

  /**
   * Our signature over the (blinded) coin.
   */
  struct GNUNET_CRYPTO_rsa_Signature *sig;

  /**
   * Denomination key (which coin was generated).
   */
  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;

  /**
   * Public key of the reserve that was drained.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;

  /**
   * Signature confirming the withdrawl, matching @e reserve_pub,
   * @e denom_pub and @e h_blind.
   */
  struct GNUNET_CRYPTO_EddsaSignature reserve_sig;
};


/* FIXME: need call to convert CollectableBlindcoin to JSON (#3527) */


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



/**
 * Types of operations on a reserved.
 */
enum TALER_MINT_DB_ReserveOperation
{
  /**
   * Money was deposited into the reserve via a bank transfer.
   */
  TALER_MINT_DB_RO_BANK_TO_MINT = 0,

  /**
   * A Coin was withdrawn from the reserve using /withdraw.
   */
  TALER_MINT_DB_RO_WITHDRAW_COIN = 1
};


/**
 * Reserve history as a linked list.  Lists all of the transactions
 * associated with this reserve (such as the bank transfers that
 * established the reserve and all /withdraw operations we have done
 * since).
 */
struct ReserveHistory
{

  /**
   * Next entry in the reserve history.
   */
  struct ReserveHistory *next;

  /**
   * Type of the event, determins @e details.
   */
  enum TALER_MINT_DB_ReserveOperation type;

  /**
   * Details of the operation, depending on @e type.
   */
  union
  {

    /**
     * Details about a bank transfer to the mint.
     */
    struct BankTransfer *bank;

    /**
     * Details about a /withdraw operation.
     */
    struct CollectableBlindcoin *withdraw;

  } details;

};


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
                                   const struct GNUNET_CRYPTO_EddsaPublicKey *reserve_pub);


/**
 * Free memory associated with the given reserve history.
 *
 * @param rh history to free.
 */
void
TALER_MINT_DB_free_reserve_history (struct ReserveHistory *rh);


/**
 * Specification for a /deposit operation.
 */
struct Deposit
{
  /**
   * Information about the coin that is being deposited.
   */
  struct TALER_CoinPublicInfo coin;

  /**
   * ECDSA signature affirming that the customer intends
   * this coin to be deposited at the merchant identified
   * by @e h_wire in relation to the contract identified
   * by @e h_contract.
   */
  struct GNUNET_CRYPTO_EcdsaSignature csig;

  /**
   * Public key of the merchant.  Enables later identification
   * of the merchant in case of a need to rollback transactions.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey merchant_pub;

  /**
   * Hash over the contract between merchant and customer
   * (remains unknown to the Mint).
   */
  struct GNUNET_HashCode h_contract;

  /**
   * Hash of the (canonical) representation of @e wire, used
   * to check the signature on the request.  Generated by
   * the mint from the detailed wire data provided by the
   * merchant.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Detailed wire information for executing the transaction.
   */
  const json_t *wire;

  /**
   * Merchant-generated transaction ID to detect duplicate
   * transactions.
   */
  uint64_t transaction_id;

  /**
   * Fraction of the coin's remaining value to be deposited.
   * The coin is identified by @e coin_pub.
   */
  struct TALER_Amount amount;

};


/**
 * Check if we have the specified deposit already in the database.
 *
 * @param db_conn database connection
 * @param deposit deposit to search for
 * @return #GNUNET_YES if we know this operation,
 *         #GNUNET_NO if this deposit is unknown to us,
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_have_deposit (PGconn *db_conn,
                            const struct Deposit *deposit);


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
                              const struct Deposit *deposit);



/**
 * Global information for a refreshing session.  Includes
 * dimensions of the operation, security parameters and
 * client signatures from "/refresh/melt" and "/refresh/commit".
 */
struct RefreshSession
{
  /**
   * Signature over the commitments by the client,
   * only valid if @e has_commit_sig is set.
   */
  struct GNUNET_CRYPTO_EddsaSignature commit_sig;

    /**
   * Signature over the melt by the client.
   */
  struct GNUNET_CRYPTO_EddsaSignature melt_sig;

  /**
   * Number of coins we are melting.
   */
  uint16_t num_oldcoins;

  /**
   * Number of new coins we are creating.
   */
  uint16_t num_newcoins;

  /**
   * Number of parallel operations we perform for the cut and choose.
   * (must be greater or equal to three for security).  0 if not yet
   * known.
   */
  uint16_t kappa;

  /**
   * Index (smaller @e kappa) which the mint has chosen to not
   * have revealed during cut and choose.  Only valid if
   * @e has_commit_sig is set to #GNUNET_YES.
   */
  uint16_t noreveal_index;

  /**
   * #GNUNET_YES if we have accepted the /refresh/commit and
   * thus the @e commit_sig is valid.
   */
  int has_commit_sig;

};


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
                                   struct RefreshSession *session);


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
                                      const struct RefreshSession *session);


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
                                      const struct GNUNET_CRYPTO_EddsaSignature *commit_client_sig);


/**
 * Specification for coin in a /refresh/melt operation.
 */
struct RefreshMelt /* FIXME: name to make it clearer this is about ONE coin! */
{
  /**
   * Information about the coin that is being melted.
   */
  struct TALER_CoinPublicInfo coin;

  /**
   * Public key of the melting session.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey session_pub;

  /**
   * Signature over the melting operation.
   */
  struct GNUNET_CRYPTO_EcdsaSignature coin_sig;

  /**
   * How much value is being melted?
   */
  struct TALER_Amount amount;

  /**
   * What is the index of this coin in the melting session?
   */
  uint16_t oldcoin_index;

};


/**
 * Test if the given /refresh/melt request is known to us.
 *
 * @param db_conn database connection
 * @param melt melt operation
 * @return #GNUNET_YES if known,
 *         #GNUENT_NO if not,
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_have_refresh_melt (PGconn *db_conn,
                                 const struct RefreshMelt *melt);


/**
 * Store the given /refresh/melt request in the database.
 *
 * @param db_conn database connection
 * @param melt melt operation
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_insert_refresh_melt (PGconn *db_conn,
                                   const struct RefreshMelt *melt);


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
                                struct RefreshMelt *melt);


/**
 * We have as many `struct RefreshCommitCoin` as there are new
 * coins being created by the refresh (for each of the kappa
 * sets).  These are the coins we ask the mint to sign if the
 * respective set is selected.
 */
struct RefreshCommitCoin
{

  /**
   * Encrypted data allowing those able to decrypt it to derive
   * the private keys of the new coins created by the refresh.
   */
  struct TALER_RefreshLinkEncrypted *refresh_link;

  /**
   * Blinded message to be signed (in envelope), with @e coin_env_size bytes.
   */
  char *coin_ev;

  /**
   * Number of bytes in @e coin_ev.
   */
  size_t coin_ev_size;

};


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
                                          const struct RefreshCommitCoin *commit_coin);


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
                                       unsigned int i,
                                       unsigned int j,
                                       struct RefreshCommitCoin *commit_coin);


/**
 * For each (old) coin being melted, we have a `struct
 * RefreshCommitLink` that allows the user to find the shared secret
 * to decrypt the respective refresh links for the new coins in the
 * `struct RefreshCommitCoin`.
 */
struct RefreshCommitLink
{
  /**
   * Transfer public key (FIXME: explain!)
   */
  struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub;

  /**
   * Encrypted shared secret to decrypt the link.
   */
  struct TALER_EncryptedLinkSecret shared_secret_enc;
};


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
                                          const struct RefreshCommitLink *commit_link);

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
                                       unsigned int i,
                                       unsigned int j,
                                       struct RefreshCommitLink *cc);


/**
 * Specification for a /lock operation.
 */
struct Lock
{
  /**
   * Information about the coin that is being melted.
   */
  struct TALER_CoinPublicInfo coin;

  /**
   * Signature over the melting operation.
   */
  const struct GNUNET_CRYPTO_EcdsaSignature coin_sig;

  /**
   * How much value is being melted?
   */
  struct TALER_Amount amount;

  // FIXME: more needed...
};


/**
 * Test if the given /lock request is known to us.
 *
 * @param db_conn database connection
 * @param lock lock operation
 * @return #GNUNET_YES if known,
 *         #GNUENT_NO if not,
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_have_lock (PGconn *db_conn,
                         const struct Lock *lock);


/**
 * Store the given /lock request in the database.
 *
 * @param db_conn database connection
 * @param lock lock operation
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_insert_lock (PGconn *db_conn,
                           const struct Lock *lock);


/**
 * Enumeration to classify the different types of transactions
 * that can be done with a coin.
 */
enum TALER_MINT_DB_TransactionType
{
  /**
   * /deposit operation.
   */
  TALER_MINT_DB_TT_DEPOSIT = 0,

  /**
   * /refresh/melt operation.
   */
  TALER_MINT_DB_TT_REFRESH_MELT = 1,

  /**
   * /lock operation.
   */
  TALER_MINT_DB_TT_LOCK = 2
};


/**
 * List of transactions we performed for a particular coin.
 */
struct TALER_MINT_DB_TransactionList
{

  /**
   * Next pointer in the NULL-terminated linked list.
   */
  struct TALER_MINT_DB_TransactionList *next;

  /**
   * Type of the transaction, determines what is stored in @e details.
   */
  enum TALER_MINT_DB_TransactionType type;

  /**
   * Details about the transaction, depending on @e type.
   */
  union
  {

    /**
     * Details if transaction was a /deposit operation.
     */
    struct Deposit *deposit;

    /**
     * Details if transaction was a /refresh/melt operation.
     */
    struct RefreshMelt *melt;

    /**
     * Details if transaction was a /lock operation.
     */
    struct Lock *lock;

  } details;

};


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
                                     const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub);


/**
 * Free linked list of transactions.
 *
 * @param list list to free
 */
void
TALER_MINT_DB_free_coin_transaction_list (struct TALER_MINT_DB_TransactionList *list);



#endif /* _NEURO_MINT_DB_H */
