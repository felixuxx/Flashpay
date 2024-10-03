/*
  This file is part of TALER
  (C) 2016-2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file bank-lib/fakebank.h
 * @brief general state of the fakebank
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_H
#define FAKEBANK_H

#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>


/**
 * How long are exchange base URLs allowed to be at most?
 * Set to a relatively low number as this does contribute
 * significantly to our RAM consumption.
 */
#define MAX_URL_LEN 64


/**
 * Maximum POST request size.
 */
#define REQUEST_BUFFER_MAX (4 * 1024)


/**
 * Per account information.
 */
struct Account;


/**
 * Types of long polling activities.
 */
enum LongPollType
{
  /**
   * Transfer TO the exchange.
   */
  LP_CREDIT,

  /**
   * Transfer FROM the exchange.
   */
  LP_DEBIT,

  /**
   * Withdraw operation completion/abort.
   */
  LP_WITHDRAW

};

/**
 * Client waiting for activity on this account.
 */
struct LongPoller
{

  /**
   * Kept in a DLL.
   */
  struct LongPoller *next;

  /**
   * Kept in a DLL.
   */
  struct LongPoller *prev;

  /**
   * Fakebank this long poller belongs with.
   */
  struct TALER_FAKEBANK_Handle *h;

  /**
   * Account this long poller is waiting on.
   */
  struct Account *account;

  /**
   * Withdraw operation we are waiting on,
   * only if @e type is #LP_WITHDRAW, otherwise NULL.
   */
  const struct WithdrawalOperation *wo;

  /**
   * Entry in the heap for this long poller.
   */
  struct GNUNET_CONTAINER_HeapNode *hn;

  /**
   * Client that is waiting for transactions.
   */
  struct MHD_Connection *conn;

  /**
   * When will this long poller time out?
   */
  struct GNUNET_TIME_Absolute timeout;

  /**
   * What does the @e connection wait for?
   */
  enum LongPollType type;

};


/**
 * Details about a transcation we (as the simulated bank) received.
 */
struct Transaction;


/**
 * Information we keep per withdraw operation.
 */
struct WithdrawalOperation
{
  /**
   * Unique (random) operation ID.
   */
  struct GNUNET_ShortHashCode wopid;

  /**
   * Debited account.
   */
  struct Account *debit_account;

  /**
   * Target exchange account, or NULL if unknown.
   */
  const struct Account *exchange_account;

  /**
   * RowID of the resulting transaction, if any. Otherwise 0.
   */
  uint64_t row_id;

  /**
   * Amount transferred, NULL if still unknown.
   */
  struct TALER_Amount *amount;

  /**
   * Public key of the reserve, wire transfer subject.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * When was the transaction made? 0 if not yet.
   */
  struct GNUNET_TIME_Timestamp timestamp;

  /**
   * Was the withdrawal aborted?
   */
  bool aborted;

  /**
   * Did the bank confirm the withdrawal?
   */
  bool confirmation_done;

  /**
   * Is @e reserve_pub initialized?
   */
  bool selection_done;

};


/**
 * Per account information.
 */
struct Account
{

  /**
   * Inbound transactions for this account in a MDLL.
   */
  struct Transaction *in_head;

  /**
   * Inbound transactions for this account in a MDLL.
   */
  struct Transaction *in_tail;

  /**
   * Outbound transactions for this account in a MDLL.
   */
  struct Transaction *out_head;

  /**
   * Outbound transactions for this account in a MDLL.
   */
  struct Transaction *out_tail;

  /**
   * Kept in a DLL.
   */
  struct LongPoller *lp_head;

  /**
   * Kept in a DLL.
   */
  struct LongPoller *lp_tail;

  /**
   * Account name (string, not payto!)
   */
  char *account_name;

  /**
   * Receiver name for payto:// URIs.
   */
  char *receiver_name;

  /**
   * Payto URI for this account.
   */
  char *payto_uri;

  /**
   * Password set for the account (if any).
   */
  char *password;

  /**
   * Current account balance.
   */
  struct TALER_Amount balance;

  /**
   * true if the balance is negative.
   */
  bool is_negative;

};


/**
 * Details about a transcation we (as the simulated bank) received.
 */
struct Transaction
{
  /**
   * We store inbound transactions in a MDLL.
   */
  struct Transaction *next_in;

  /**
   * We store inbound transactions in a MDLL.
   */
  struct Transaction *prev_in;

  /**
   * We store outbound transactions in a MDLL.
   */
  struct Transaction *next_out;

  /**
   * We store outbound transactions in a MDLL.
   */
  struct Transaction *prev_out;

  /**
   * Amount to be transferred.
   */
  struct TALER_Amount amount;

  /**
   * Account to debit.
   */
  struct Account *debit_account;

  /**
   * Account to credit.
   */
  struct Account *credit_account;

  /**
   * Random unique identifier for the request.
   * Used to detect idempotent requests.
   */
  struct GNUNET_HashCode request_uid;

  /**
   * When did the transaction happen?
   */
  struct GNUNET_TIME_Timestamp date;

  /**
   * Number of this transaction.
   */
  uint64_t row_id;

  /**
   * What does the @e subject contain?
   */
  enum
  {
    /**
     * Transfer TO the exchange.
     */
    T_CREDIT,

    /**
     * Transfer FROM the exchange.
     */
    T_DEBIT,

    /**
     * Transfer TO the exchange for KYCAUTH.
     */
    T_AUTH,

    /**
     * Exchange-to-exchange WAD transfer.
     */
    T_WAD,
  } type;

  /**
   * Wire transfer subject.
   */
  union
  {

    /**
     * Used if @e type is T_DEBIT.
     */
    struct
    {

      /**
       * Subject of the transfer.
       */
      struct TALER_WireTransferIdentifierRawP wtid;

      /**
       * Base URL of the exchange.
       */
      char exchange_base_url[MAX_URL_LEN];

    } debit;

    /**
     * Used if @e type is T_CREDIT.
     */
    struct
    {

      /**
       * Reserve public key of the credit operation.
       */
      struct TALER_ReservePublicKeyP reserve_pub;

    } credit;

    /**
     * Used if @e type is T_AUTH.
     */
    struct
    {

      /**
       * Account public key of the credit operation.
       */
      union TALER_AccountPublicKeyP account_pub;

    } auth;

    /**
     * Used if @e type is T_WAD.
     */
    struct
    {

      /**
       * Subject of the transfer.
       */
      struct TALER_WadIdentifierP wad_id;

      /**
       * Base URL of the originating exchange.
       */
      char origin_base_url[MAX_URL_LEN];

    } wad;

  } subject;

  /**
   * Has this transaction not yet been subjected to
   * #TALER_FAKEBANK_check_credit() or #TALER_FAKEBANK_check_debit() and
   * should thus be counted in #TALER_FAKEBANK_check_empty()?
   */
  bool unchecked;
};


/**
 * Function called to clean up context of a connection.
 *
 * @param ctx context to clean up
 */
typedef void
(*ConnectionCleaner)(void *ctx);

/**
 * Universal context we keep per connection.
 */
struct ConnectionContext
{
  /**
   * Function we call upon completion to clean up.
   */
  ConnectionCleaner ctx_cleaner;

  /**
   * Request-handler specific context.
   */
  void *ctx;
};


/**
 * This is the "base" structure for both the /history and the
 * /history-range API calls.
 */
struct HistoryArgs
{

  /**
   * Bank account number of the requesting client.
   */
  uint64_t account_number;

  /**
   * Index of the starting transaction, exclusive (!).
   */
  uint64_t start_idx;

  /**
   * Requested number of results and order
   * (positive: ascending, negative: descending)
   */
  int64_t delta;

  /**
   * Timeout for long polling.
   */
  struct GNUNET_TIME_Relative lp_timeout;

  /**
   * true if starting point was given.
   */
  bool have_start;

};


/**
 * Context we keep per history request.
 */
struct HistoryContext
{
  /**
   * When does this request time out.
   */
  struct GNUNET_TIME_Absolute timeout;

  /**
   * Client arguments for this request.
   */
  struct HistoryArgs ha;

  /**
   * Account the request is about.
   */
  struct Account *acc;

  /**
   * JSON object we are building to return.
   */
  json_t *history;

};


/**
 * Context we keep per get withdrawal operation request.
 */
struct WithdrawContext
{
  /**
   * When does this request time out.
   */
  struct GNUNET_TIME_Absolute timeout;

  /**
   * The withdrawal operation this is about.
   */
  struct WithdrawalOperation *wo;

};


/**
 * Handle for the fake bank.
 */
struct TALER_FAKEBANK_Handle
{
  /**
   * We store transactions in a revolving array.
   */
  struct Transaction **transactions;

  /**
   * HTTP server we run to pretend to be the "test" bank.
   */
  struct MHD_Daemon *mhd_bank;

  /**
   * Task running HTTP server for the "test" bank,
   * unless we are using a thread pool (then NULL).
   */
  struct GNUNET_SCHEDULER_Task *mhd_task;

  /**
   * Task for expiring long-polling connections,
   * unless we are using a thread pool (then NULL).
   */
  struct GNUNET_SCHEDULER_Task *lp_task;

  /**
   * Task for expiring long-polling connections, unless we are using the
   * GNUnet scheduler (then NULL).
   */
  pthread_t lp_thread;

  /**
   * MIN-heap of long pollers, sorted by timeout.
   */
  struct GNUNET_CONTAINER_Heap *lp_heap;

  /**
   * Hashmap of reserve public keys to
   * `struct Transaction` with that reserve public
   * key. Used to prevent public-key reuse.
   */
  struct GNUNET_CONTAINER_MultiPeerMap *rpubs;

  /**
   * Hashmap of short hashes (wopids) to
   * `struct WithdrawalOperation`.
   * Used to lookup withdrawal operations.
   */
  struct GNUNET_CONTAINER_MultiShortmap *wops;

  /**
   * (Base) URL to suggest for the exchange.  Can
   * be NULL if there is no suggestion to be made.
   */
  char *exchange_url;

  /**
   * Lock for accessing @a rpubs map.
   */
  pthread_mutex_t rpubs_lock;

  /**
   * Hashmap of hashes of account names to `struct Account`.
   */
  struct GNUNET_CONTAINER_MultiHashMap *accounts;

  /**
   * Lock for accessing @a accounts hash map.
   */
  pthread_mutex_t accounts_lock;

  /**
   * Hashmap of hashes of transaction request_uids to `struct Transaction`.
   */
  struct GNUNET_CONTAINER_MultiHashMap *uuid_map;

  /**
   * Lock for accessing @a uuid_map.
   */
  pthread_mutex_t uuid_map_lock;

  /**
   * Lock for accessing the internals of
   * accounts and transaction array entries.
   */
  pthread_mutex_t big_lock;

  /**
   * How much money should be put into new accounts
   * on /register.
   */
  struct TALER_Amount signup_bonus;

  /**
   * Current transaction counter.
   */
  uint64_t serial_counter;

  /**
   * Number of transactions we keep in memory (at most).
   */
  uint64_t ram_limit;

  /**
   * Currency used by the fakebank.
   */
  char *currency;

  /**
   * Hostname of the fakebank.
   */
  char *hostname;

  /**
   * BaseURL of the fakebank.
   */
  char *my_baseurl;

  /**
   * Our port number.
   */
  uint16_t port;

#ifdef __linux__
  /**
   * Event FD to signal @a lp_thread a change in
   * @a lp_heap.
   */
  int lp_event;
#else
  /**
   * Pipe input to signal @a lp_thread a change in
   * @a lp_heap.
   */
  int lp_event_in;

  /**
   * Pipe output to signal @a lp_thread a change in
   * @a lp_heap.
   */
  int lp_event_out;
#endif

  /**
   * Set to true once we are shutting down.
   */
  bool in_shutdown;

  /**
   * Should we run MHD immediately again?
   */
  bool mhd_again;

#if EPOLL_SUPPORT
  /**
   * Boxed @e mhd_fd.
   */
  struct GNUNET_NETWORK_Handle *mhd_rfd;

  /**
   * File descriptor to use to wait for MHD.
   */
  int mhd_fd;
#endif
};


/**
 * Task run whenever HTTP server operations are pending.
 *
 * @param cls the `struct TALER_FAKEBANK_Handle`
 */
void
TALER_FAKEBANK_run_mhd_ (void *cls);


#endif
