/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V. and INRIA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Lesser General Public License as published by the Free Software
  Foundation; either version 2.1, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public License along with
  TALER; see the file COPYING.LGPL.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file src/benchmark/taler-exchange-benchmark.c
 * @brief exchange's benchmark
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include <microhttpd.h>
#include <jansson.h>

#define RUNXCG

/**
 * How many coins the benchmark should operate on
 */
static unsigned int pool_size = 100;

/**
 * Configuration file path
 */
static char *config_file;

/**
 * Configuation object (used to get BANK_URI)
 */
struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * How many reserves ought to be created given the pool size
 */
static unsigned int nreserves;

/**
 * How many coins are in `coins` array. This is needed
 * as the number of coins is not always nreserves * COINS_PER_RESERVE 
 * due to refresh operations
 */
unsigned int ncoins;


/**
 * Bank details of who creates reserves
 */
json_t *sender_details;

/**
 * Bank details of who deposits coins
 */
json_t *merchant_details;

/**
 * Information needed by the /refresh/melt's callback
 */
struct RefreshRevealCls {

  /**
   * The result of a `TALER_EXCHANGE_refresh_prepare()` call
   */
  const char *blob;

  /**
   * Size of `blob`
   */
  size_t blob_size;

  /**
   * Which coin in the list are we melting
   */
  unsigned int coin_index;
};

/**
 * Needed information for a reserve. Other values are the same for all reserves, therefore defined in global variables
 */
struct Reserve {
   /**
   * Set (by the interpreter) to the reserve's private key
   * we used to fill the reserve.
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

  /**
   * Set to the API's handle during the operation.
   */
  struct TALER_EXCHANGE_AdminAddIncomingHandle *aih;

};

/**
 * Array of denomination keys needed to perform the 4 KUDOS
 * refresh operation
 */
struct TALER_EXCHANGE_DenomPublicKey *refresh_pk;

/**
 * Size of `refresh_pk`
 */
unsigned int refresh_pk_len;

/**
 * Same blinding key for all coins
 */
struct TALER_DenominationBlindingKeyP blinding_key;

/**
 * Information regarding a coin
 */
struct Coin {
  /**
   * Index in the reserve's global array indicating which
   * reserve this coin is to be retrieved. If the coin comes
   * from a refresh, then this value is set to the melted coin's
   * reserve index
   */
  unsigned int reserve_index;

  /**
   * If @e amount is NULL, this specifies the denomination key to
   * use.  Otherwise, this will be set (by the interpreter) to the
   * denomination PK matching @e amount.
   */
  const struct TALER_EXCHANGE_DenomPublicKey *pk;

  /**
   * Set (by the interpreter) to the exchange's signature over the
   * coin's public key.
   */
  struct TALER_DenominationSignature sig;

  /**
   * Set (by the interpreter) to the coin's private key.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Withdraw handle (while operation is running).
   */
  struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh;

  /**
   * Deposit handle (while operation is running).
   */
  struct TALER_EXCHANGE_DepositHandle *dh;

  /**
   * Flag indicating if the coin is going to be refreshed
   */
  unsigned int refresh;

  /**
   * Refresh melt handle
   */
  struct TALER_EXCHANGE_RefreshMeltHandle *rmh;

  /**
   * Refresh reveal handle
   */
  struct TALER_EXCHANGE_RefreshRevealHandle *rrh;

};


/**
 * Handle to the exchange's process
 */
static struct GNUNET_OS_Process *exchanged;

/**
 * Context for running the #ctx's event loop.
 */
static struct GNUNET_CURL_RescheduleContext *rc;

/**
 * Benchmark's task
 */
struct GNUNET_SCHEDULER_Task *benchmark_task;

/**
 * Main execution context for the main loop of the exchange.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Handle to access the exchange.
 */
static struct TALER_EXCHANGE_Handle *exchange;

/**
 * The array of all reserves
 */
static struct Reserve *reserves;

/**
 * The array of all coins
 */
static struct Coin *coins;

/**
 * Indices of spent coins
 */
static unsigned int *spent_coins;

/**
 * Current number of spent coins
 */
static unsigned int spent_coins_size = 0;

/**
 * Transaction id counter, used in /deposit's
 */
static unsigned int transaction_id = 0;

/**
 * This key (usually provided by merchants) is needed when depositing coins,
 * even though there is no merchant acting in the benchmark
 */
static struct TALER_MerchantPrivateKeyP merchant_priv;

/**
 * URI under which the exchange is reachable during the benchmark.
 */
#define EXCHANGE_URI "http://localhost:8081/"

/**
 * How many coins (AKA withdraw operations) per reserve should be withdrawn
 */
#define COINS_PER_RESERVE 12

/**
 * Used currency (read from /keys' output)
 */
static char *currency;

/**
 * Large enough value to allow having 12 coins per reserve without parsing
 * /keys in the first place
 */
#define RESERVE_VALUE 1000

/**
 * The benchmark withdraws always the same denomination, since the calculation
 * for refreshing is statically done (at least in its very first version).
 */
#define COIN_VALUE 8

/**
 * Probability a coin can be spent
 */
#define SPEND_PROBABILITY 0.1

/**
 * Probability a coin can be refreshed
 */
#define REFRESH_PROBABILITY 0.4

/**
 * Refreshed once. For each batch of deposits, only one
 * coin will be refreshed, according to #REFRESH_PROBABILITY
 */
static unsigned int refreshed_once = GNUNET_NO;

/**
 * List of coins to get in return to a melt operation. Just a
 * static list for now as every melt operation is carried out
 * on a 8 KUDOS coin whose only 1 KUDOS has been spent, thus
 * 7 KUDOS melted. This structure must be changed with one holding
 * TALER_Amount structs, as every time it's needed it requires
 * too many operations before getting the desired TALER_Amount.
 */
static char *refresh_denoms[] = {
  "4",
  "2",
  "1",
  NULL
};

static unsigned int
eval_probability (float probability)
{
  unsigned int random;
  float random_01;

  random = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK, UINT32_MAX);
  random_01 = (float) random / UINT32_MAX;
  return random_01 <= probability ? GNUNET_OK : GNUNET_NO;
}


static void
do_shutdown (void *cls);


/**
 * Shutdown benchmark in case of errors
 *
 * @param msg error message to print in logs
 */
static void
fail (const char *msg)
{
  if (NULL != msg)
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "%s\n",
                msg);
  GNUNET_SCHEDULER_shutdown ();
  return;
}


/**
 * Find denomination key matching the given amount.
 *
 * @param keys array of keys to search
 * @param amount coin value to look for
 * @return NULL if no matching key was found
 */
static const struct TALER_EXCHANGE_DenomPublicKey *
find_pk (const struct TALER_EXCHANGE_Keys *keys,
         const struct TALER_Amount *amount)
{
  unsigned int i;
  struct GNUNET_TIME_Absolute now;
  struct TALER_EXCHANGE_DenomPublicKey *pk;
  char *str;

  now = GNUNET_TIME_absolute_get ();
  for (i=0;i<keys->num_denom_keys;i++)
  {
    pk = &keys->denom_keys[i];
    if ( (0 == TALER_amount_cmp (amount,
                                 &pk->value)) &&
         (now.abs_value_us >= pk->valid_from.abs_value_us) &&
         (now.abs_value_us < pk->withdraw_valid_until.abs_value_us) )
      return pk;
  }
  /* do 2nd pass to check if expiration times are to blame for failure */
  str = TALER_amount_to_string (amount);
  for (i=0;i<keys->num_denom_keys;i++)
  {
    pk = &keys->denom_keys[i];
    if ( (0 == TALER_amount_cmp (amount,
                                 &pk->value)) &&
         ( (now.abs_value_us < pk->valid_from.abs_value_us) ||
           (now.abs_value_us > pk->withdraw_valid_until.abs_value_us) ) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Have denomination key for `%s', but with wrong expiration range %llu vs [%llu,%llu)\n",
                  str,
                  (unsigned long long) now.abs_value_us,
                  (unsigned long long) pk->valid_from.abs_value_us,
                  (unsigned long long) pk->withdraw_valid_until.abs_value_us);
      GNUNET_free (str);
      return NULL;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "No denomination key for amount %s found\n",
              str);
  GNUNET_free (str);
  return NULL;
}

/**
 * Function called with the result of the /refresh/reveal operation.
 *
 * @param cls closure with the interpreter state
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param num_coins number of fresh coins created, length of the @a sigs and @a coin_privs arrays, 0 if the operation failed
 * @param coin_privs array of @a num_coins private keys for the coins that were created, NULL on error
 * @param sigs array of signature over @a num_coins coins, NULL on error
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
static void
reveal_cb (void *cls,
           unsigned int http_status,
           unsigned int num_coins,
           const struct TALER_CoinSpendPrivateKeyP *coin_privs,
           const struct TALER_DenominationSignature *sigs,
           const json_t *full_response)
{
  struct RefreshRevealCls *rrcls = cls;
  unsigned int i;
  const struct TALER_EXCHANGE_Keys *keys;

  coins[rrcls->coin_index].rrh = NULL;
  if (MHD_HTTP_OK != http_status)
  {
    GNUNET_free (rrcls);
    json_dumpf (full_response, stderr, 0);
    fail ("Not all coins correctly revealed\n");
    return;
  }
  else
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Coin #%d revealed!\n",
                rrcls->coin_index);
  keys = TALER_EXCHANGE_get_keys (exchange);
  for (i=0; i<num_coins; i++)
  {
    struct Coin fresh_coin;
    struct TALER_Amount amount;
    char *refresh_denom;
    
    GNUNET_asprintf (&refresh_denom,
                     "%s:%s",
                     currency,
                     refresh_denoms[i]);
    fresh_coin.reserve_index = coins[rrcls->coin_index].reserve_index;
    TALER_string_to_amount (refresh_denom, &amount);
    GNUNET_free (refresh_denom);
    fresh_coin.pk = find_pk (keys, &amount);
    fresh_coin.sig = sigs[i];
    GNUNET_array_append (coins, ncoins, fresh_coin);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "# of coins after refresh: %d\n",
                ncoins);
  }
  GNUNET_free (rrcls);
}

/**
 * Function called with the result of the /refresh/melt operation.
 *
 * @param cls closure with the interpreter state
 * @param http_status HTTP response code, never #MHD_HTTP_OK (200) as for successful intermediate response this callback is skipped.
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param noreveal_index choice by the exchange in the cut-and-choose protocol,
 *                    UINT16_MAX on error
 * @param exchange_pub public key the exchange used for signing
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
static void
melt_cb (void *cls,
         unsigned int http_status,
         uint16_t noreveal_index,
         const struct TALER_ExchangePublicKeyP *exchange_pub,
         const json_t *full_response)
{
  struct RefreshRevealCls *rrcls = cls;
  /* FIXME to be freed */

  coins[rrcls->coin_index].rmh = NULL;
  if (MHD_HTTP_OK != http_status)
  {
    json_dumpf (full_response, stderr, 0);
    fail ("Coin not correctly melted!\n");
    return;
  }
  coins[rrcls->coin_index].rrh
    = TALER_EXCHANGE_refresh_reveal (exchange,
                                     rrcls->blob_size,
                                     rrcls->blob,
                                     noreveal_index,
                                     reveal_cb,
                                     rrcls);
}


/**
 * Function called upon completion of our /reserve/withdraw request.
 * This is merely the function which spends withdrawn coins
 *
 * @param cls closure with the interpreter state
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param sig signature over the coin, NULL on error
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
static void
reserve_withdraw_cb (void *cls,
                     unsigned int http_status,
                     const struct TALER_DenominationSignature *sig,
                     const json_t *full_response);


/**
 * Function called with the result of a /deposit operation.
 *
 * @param cls closure with the interpreter state
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful deposit;
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param exchange_pub public key used by the exchange for signing
 * @param obj the received JSON reply, should be kept as proof (and, in case of errors,
 *            be forwarded to the customer)
 */
static void
deposit_cb (void *cls,
            unsigned int http_status,
            const struct TALER_ExchangePublicKeyP *exchange_pub,
            const json_t *obj)
{
  unsigned int coin_index = (unsigned int) (long) cls;

  coins[coin_index].dh = NULL;
  if (MHD_HTTP_OK != http_status)
  {
    json_dumpf (obj, stderr, 0);
    fail ("At least one coin has not been deposited, status: %d\n");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "Coin #%d correctly spent!\n", coin_index);
  GNUNET_array_append (spent_coins, spent_coins_size, coin_index);
  spent_coins_size++;
  if (GNUNET_YES == coins[coin_index].refresh)
  {
    struct TALER_Amount melt_amount;
    struct RefreshRevealCls *rrcls;

    TALER_amount_get_zero (currency, &melt_amount);
    melt_amount.value = 7;
    char *blob;
    size_t blob_size;

    blob = TALER_EXCHANGE_refresh_prepare (&coins[coin_index].coin_priv,
                                           &melt_amount,
                                           &coins[coin_index].sig,
                                           coins[coin_index].pk,
                                           GNUNET_YES,
                                           refresh_pk_len,
                                           refresh_pk,
                                           &blob_size);
    if (NULL == blob)
    {
      fail ("Failed to prepare refresh");
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "prepared blob %d\n",
                (unsigned int) blob_size);
    refreshed_once = GNUNET_YES;

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "# of coins to get in melt: %d\n",
                refresh_pk_len);
    rrcls = GNUNET_new (struct RefreshRevealCls);
    rrcls->blob = blob;
    rrcls->blob_size = blob_size;
    rrcls->coin_index = coin_index;

    coins[coin_index].rmh = TALER_EXCHANGE_refresh_melt (exchange,
                                                         blob_size,
                                                         blob,
                                                         &melt_cb,
                                                         rrcls);
    if (NULL == coins[coin_index].rmh)
    {
      fail ("Impossible to issue a melt request to the exchange\n");
      return;
    }
  }
  else
  { /* re-withdraw */
    struct GNUNET_CRYPTO_EddsaPrivateKey *coin_priv;
    coin_priv = GNUNET_CRYPTO_eddsa_key_create ();
    coins[coin_index].coin_priv.eddsa_priv = *coin_priv;
    GNUNET_free (coin_priv);
    coins[coin_index].wsh =
      TALER_EXCHANGE_reserve_withdraw (exchange,
                                       coins[coin_index].pk,
                                       &reserves[coins[coin_index].reserve_index].reserve_priv,
                                       &coins[coin_index].coin_priv,
                                       &blinding_key,
                                       reserve_withdraw_cb,
                                       (void *) (long) coin_index);
  }
}


/**
 * Function called upon completion of our /reserve/withdraw request.
 * This is merely the function which spends withdrawn coins
 *
 * @param cls closure with the interpreter state
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param sig signature over the coin, NULL on error
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
static void
reserve_withdraw_cb (void *cls,
                     unsigned int http_status,
                     const struct TALER_DenominationSignature *sig,
                     const json_t *full_response)
{

  unsigned int coin_index = (unsigned int) (long) cls;

  coins[coin_index].wsh = NULL;
  if (MHD_HTTP_OK != http_status)
  {
    json_dumpf (full_response, stderr, 0);
    fail ("At least one coin has not correctly been withdrawn\n");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "%d-th coin withdrawn\n",
              coin_index);
  coins[coin_index].sig.rsa_signature =
    GNUNET_CRYPTO_rsa_signature_dup (sig->rsa_signature);
  if (GNUNET_OK == eval_probability (SPEND_PROBABILITY))
  {
    struct TALER_Amount amount;
    struct GNUNET_TIME_Absolute wire_deadline;
    struct GNUNET_TIME_Absolute timestamp;
    struct GNUNET_TIME_Absolute refund_deadline;
    struct GNUNET_HashCode h_contract;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_DepositRequestPS dr;
    struct TALER_MerchantPublicKeyP merchant_pub;
    struct TALER_CoinSpendSignatureP coin_sig;

    GNUNET_CRYPTO_eddsa_key_get_public (&coins[coin_index].coin_priv.eddsa_priv,
                                        &coin_pub.eddsa_pub);
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &h_contract,
                                sizeof (h_contract));
    timestamp = GNUNET_TIME_absolute_get ();
    wire_deadline = GNUNET_TIME_absolute_add (timestamp, GNUNET_TIME_UNIT_WEEKS);
    refund_deadline = GNUNET_TIME_absolute_add (timestamp, GNUNET_TIME_UNIT_DAYS);
    GNUNET_TIME_round_abs (&timestamp);
    GNUNET_TIME_round_abs (&wire_deadline);
    GNUNET_TIME_round_abs (&refund_deadline);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG, "Spending %d-th coin\n", coin_index);

    if (GNUNET_YES == eval_probability (REFRESH_PROBABILITY)
        && GNUNET_NO == refreshed_once)
    {
      struct TALER_Amount one;
      TALER_amount_get_zero (currency, &one);
      one.value = 1;

      /**
       * If the coin is going to be refreshed, only 1 unit
       * of currency will be spent, since 4 units are going
       * to be refreshed
       */
      TALER_amount_subtract (&amount,
                             &one,
                             &coins[coin_index].pk->fee_deposit);
      coins[coin_index].refresh = GNUNET_YES;
      refreshed_once = GNUNET_YES;
    }
    else
    {
      TALER_amount_subtract (&amount,
                             &coins[coin_index].pk->value,
                             &coins[coin_index].pk->fee_deposit);
    }
    memset (&dr, 0, sizeof (dr));
    dr.purpose.size = htonl (sizeof (struct TALER_DepositRequestPS));
    dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT);
    dr.h_contract = h_contract;
    TALER_JSON_hash (merchant_details,
                     &dr.h_wire);

    dr.timestamp = GNUNET_TIME_absolute_hton (timestamp);
    dr.refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline);
    dr.transaction_id = GNUNET_htonll (transaction_id);

    TALER_amount_hton (&dr.amount_with_fee,
                       &amount);
    TALER_amount_hton (&dr.deposit_fee,
                       &coins[coin_index].pk->fee_deposit);

    GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv.eddsa_priv,
                                        &merchant_pub.eddsa_pub);
    dr.merchant = merchant_pub;
    dr.coin_pub = coin_pub;
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CRYPTO_eddsa_sign (&coins[coin_index].coin_priv.eddsa_priv,
                                             &dr.purpose,
                                             &coin_sig.eddsa_signature));

    coins[coin_index].dh = TALER_EXCHANGE_deposit (exchange,
                                                   &amount,
                                                   wire_deadline,
                                                   merchant_details,
                                                   &h_contract,
                                                   &coin_pub,
                                                   &coins[coin_index].sig,
                                                   &coins[coin_index].pk->key,
                                                   timestamp,
                                                   transaction_id,
                                                   &merchant_pub,
                                                   refund_deadline,
                                                   &coin_sig,
                                                   &deposit_cb,
                                                   (void *) (long) coin_index);
    if (NULL == coins[coin_index].dh)
    {
      json_decref (merchant_details);
      fail ("An error occurred while calling deposit API\n");
      return;
    }
    transaction_id++;
  }
}



/**
 * Function called upon completion of our /admin/add/incoming request.
 * Its duty is withdrawing coins on the freshly created reserve.
 *
 * @param cls closure with the interpreter state
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
static void
add_incoming_cb (void *cls,
                 unsigned int http_status,
                 const json_t *full_response)
{
  unsigned int reserve_index = (unsigned int) (long) cls;
  struct GNUNET_CRYPTO_EddsaPrivateKey *coin_priv;
  unsigned int i;
  unsigned int coin_index;
  struct TALER_Amount amount;
  const struct TALER_EXCHANGE_Keys *keys;

  keys = TALER_EXCHANGE_get_keys (exchange);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "/admin/add/incoming callback called on %d-th reserve\n",
              reserve_index);
  reserves[reserve_index].aih = NULL;
  if (MHD_HTTP_OK != http_status)
  {
    json_dumpf (full_response, stderr, 0);
    fail ("At least one reserve failed in being created\n");
  }

  for (i=0; i < COINS_PER_RESERVE; i++)
  {
    coin_priv = GNUNET_CRYPTO_eddsa_key_create ();
    coin_index = reserve_index * COINS_PER_RESERVE + i;
    coins[coin_index].coin_priv.eddsa_priv = *coin_priv;
    coins[coin_index].reserve_index = reserve_index;
    TALER_amount_get_zero (currency, &amount);
    amount.value = COIN_VALUE;
    GNUNET_assert (NULL != (coins[coin_index].pk = find_pk (keys, &amount)));
    GNUNET_free (coin_priv);
    coins[coin_index].wsh =
      TALER_EXCHANGE_reserve_withdraw (exchange,
                                       coins[coin_index].pk,
                                       &reserves[reserve_index].reserve_priv,
                                       &coins[coin_index].coin_priv,
                                       &blinding_key,
                                       reserve_withdraw_cb,
                                       (void *) (long) coin_index);
  }
}


/**
 * Benchmark runner.
 *
 * @param cls closure for benchmark_run()
 */
static void
benchmark_run (void *cls)
{
  unsigned int i;
  struct GNUNET_CRYPTO_EddsaPrivateKey *priv;
  json_t *transfer_details;
  char *uuid;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct GNUNET_TIME_Absolute execution_date;
  struct TALER_Amount reserve_amount;

  priv = GNUNET_CRYPTO_eddsa_key_create ();
  merchant_priv.eddsa_priv = *priv;
  GNUNET_free (priv);

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &blinding_key,
                              sizeof (blinding_key));
  TALER_amount_get_zero (currency, &reserve_amount);
  reserve_amount.value = RESERVE_VALUE;
  execution_date = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&execution_date);

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "benchmark_run() invoked\n");
  nreserves = pool_size / COINS_PER_RESERVE;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "creating %d reserves\n",
              nreserves);

  reserves = GNUNET_new_array (nreserves,
                               struct Reserve);
  ncoins = COINS_PER_RESERVE * nreserves;
  coins = GNUNET_new_array (ncoins,
                            struct Coin);

  for (i=0;i < nreserves && 0 < nreserves;i++)
  {
    priv = GNUNET_CRYPTO_eddsa_key_create ();
    reserves[i].reserve_priv.eddsa_priv = *priv;
    GNUNET_free (priv);
    GNUNET_asprintf (&uuid, "{ \"uuid\":%d}", i);
    transfer_details = json_loads (uuid, JSON_REJECT_DUPLICATES, NULL);
    GNUNET_free (uuid);
    GNUNET_CRYPTO_eddsa_key_get_public (&reserves[i].reserve_priv.eddsa_priv,
                                        &reserve_pub.eddsa_pub);

    reserves[i].aih = TALER_EXCHANGE_admin_add_incoming (exchange,
                                                         &reserve_pub,
                                                         &reserve_amount,
                                                         execution_date,
                                                         sender_details,
                                                         transfer_details,
                                                         &add_incoming_cb,
                                                         (void *) (long) i);
    GNUNET_assert (NULL != reserves[i].aih);
    json_decref (transfer_details);
  }
  json_decref (sender_details);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "benchmark_run() returns\n");
}

/**
 * Populates the global array of denominations which will
 * be withdrawn in a refresh operation. It sums up 4 KUDOS,
 * since that is the only amount refreshed so far by the benchmark
 *
 * @param NULL-terminated array of value.fraction pairs
 * @return GNUNET_OK if the array is correctly built, GNUNET_SYSERR
 * otherwise
 */
static unsigned int
build_refresh (char **list)
{
  char *amount_str;
  struct TALER_Amount amount;
  unsigned int i;
  const struct TALER_EXCHANGE_DenomPublicKey *picked_denom;
  const struct TALER_EXCHANGE_Keys *keys;

  keys = TALER_EXCHANGE_get_keys (exchange);
  for (i=0; list[i] != NULL; i++)
  {
    unsigned int size;
    GNUNET_asprintf (&amount_str, "%s:%s", currency, list[i]);
    TALER_string_to_amount (amount_str, &amount);
    picked_denom = find_pk (keys, &amount);
    if (NULL == picked_denom)
    {
      return GNUNET_SYSERR;
    }
    size = i;
    GNUNET_array_append (refresh_pk, size, *picked_denom);
    GNUNET_free (amount_str);
  }
  refresh_pk_len = i;
  return GNUNET_OK;
}


/**
 * Functions of this type are called to provide the retrieved signing and
 * denomination keys of the exchange.  No TALER_EXCHANGE_*() functions should be called
 * in this callback.
 *
 * @param cls closure
 * @param _keys information about keys of the exchange
 */
static void
cert_cb (void *cls,
         const struct TALER_EXCHANGE_Keys *_keys)
{
  /* check that keys is OK */
#define ERR(cond) do { if(!(cond)) break; GNUNET_break (0); GNUNET_SCHEDULER_shutdown(); return; } while (0)
  ERR (NULL == _keys);
  ERR (0 == _keys->num_sign_keys);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Read %u signing keys\n",
              _keys->num_sign_keys);
  ERR (0 == _keys->num_denom_keys);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Read %u denomination keys\n",
              _keys->num_denom_keys);
#undef ERR

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
	      "Certificate callback invoked, invoking benchmark_run()\n");
  currency = GNUNET_strdup (_keys->denom_keys[0].value.currency);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
	      "Using currency: %s\n", currency);

  if (GNUNET_SYSERR == build_refresh (refresh_denoms))
  {
    fail(NULL);
    return;
  }

  benchmark_task = GNUNET_SCHEDULER_add_now (&benchmark_run,
                                             NULL);
}


/**
 * Function run when the benchmark terminates (good or bad).
 * Cleans up our state.
 *
 * @param cls the interpreter state.
 */
static void
do_shutdown (void *cls)
{
  unsigned int i;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "shutting down..\n");

  /**
   * WARNING: all the non NULL handles must correspond to non completed
   * calls (AKA calls for which the callback function has not been called).
   * If not, it segfaults
   */
  for (i=0; i<nreserves && 0<nreserves; i++)
  {
    if (NULL != reserves[i].aih)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Cancelling %d-th reserve\n",
                  i);
      TALER_EXCHANGE_admin_add_incoming_cancel(reserves[i].aih);
      reserves[i].aih = NULL;
    }
  }

  for (i=0; i<COINS_PER_RESERVE * nreserves && 0<nreserves; i++)
  {
    if (NULL != coins[i].wsh)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Cancelling %d-th coin withdraw handle\n",
                  i);
      TALER_EXCHANGE_reserve_withdraw_cancel(coins[i].wsh);
      coins[i].wsh = NULL;
    }
    if (NULL != coins[i].dh)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Cancelling %d-th coin deposit handle\n",
                  i);
      TALER_EXCHANGE_deposit_cancel(coins[i].dh);
      coins[i].dh = NULL;
    }
    if (NULL != coins[i].rmh)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Cancelling %d-th coin melt handle\n",
                  i);
      TALER_EXCHANGE_refresh_melt_cancel(coins[i].rmh);
      coins[i].rmh = NULL;
    }
    if (NULL != coins[i].rrh)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Cancelling %d-th coin reveal handle\n",
                  i);
      TALER_EXCHANGE_refresh_reveal_cancel(coins[i].rrh);
      coins[i].rmh = NULL;
    }
  }

  if (NULL != sender_details)
    json_decref (sender_details);
  if (NULL != merchant_details)
    json_decref (merchant_details);

  GNUNET_free_non_null (reserves);
  GNUNET_free_non_null (coins);
  GNUNET_free_non_null (spent_coins);
  GNUNET_free_non_null (currency);

  if (NULL != exchange)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Disconnecting from exchange\n");
    TALER_EXCHANGE_disconnect (exchange);
    exchange = NULL;
  }
  if (NULL != ctx)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Invoking GNUNET_CURL_fini()\n");
    GNUNET_CURL_fini (ctx);
    ctx = NULL;
  }
  if (NULL != rc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Invoking GNUNET_CURL_gnunet_rc_destroy()\n");
    GNUNET_CURL_gnunet_rc_destroy (rc);
    rc = NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "All (?) tasks shut down\n");
  GNUNET_OS_process_kill (exchanged, SIGTERM);
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure
 */
static void
run (void *cls)
{
  char *sender_details_filename;
  char *merchant_details_filename;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "running run()\n");
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "gotten pool_size of %d\n",
              pool_size);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "config file: %s\n",
              config_file);

  if (NULL == config_file)
  {
    fail ("-c option is mandatory\n");
    return;
  }

  /**
   * Read sender_details.json here
   */
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_SYSERR == GNUNET_CONFIGURATION_parse (cfg, config_file))
  {
    fail ("failed to parse configuration file\n");
    return;
  }
  if (GNUNET_SYSERR == GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                                "benchmark",
                                                                "sender_details",
                                                                &sender_details_filename))
  {
    fail ("failed to get SENDER_DETAILS value\n");
    return;
  }

  sender_details = json_load_file (sender_details_filename,
                                   JSON_REJECT_DUPLICATES,
                                   NULL);

  if (GNUNET_SYSERR == GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                                "benchmark",
                                                                "merchant_details",
                                                                &merchant_details_filename))
  {
    fail ("failed to get MERCHANT_DETAILS value\n");
    return;
  }
  merchant_details = json_load_file (merchant_details_filename,
                                     JSON_REJECT_DUPLICATES,
                                     NULL);

  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_array_append (spent_coins,
                       spent_coins_size,
                       1);
  spent_coins_size++;
  reserves = NULL;
  coins = NULL;
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  GNUNET_assert (NULL != ctx);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  exchange = TALER_EXCHANGE_connect (ctx,
                                     EXCHANGE_URI,
                                     &cert_cb, NULL,
                                     TALER_EXCHANGE_OPTION_END);
  GNUNET_assert (NULL != exchange);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG, "connected to exchange\n");
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown, NULL);
}


int
main (int argc,
      char * const *argv)
{

  #ifdef RUNXCG
  struct GNUNET_OS_Process *proc;
  unsigned int cnt;
  #endif

  GNUNET_log_setup ("taler-exchange-benchmark",
                    "WARNING",
                    NULL);
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    {'s', "pool-size", NULL,
     "How many coins this benchmark should instantiate", GNUNET_YES,
     &GNUNET_GETOPT_set_uint, &pool_size},
    {'c', "config", NULL,
     "Configuration file", GNUNET_YES,
     &GNUNET_GETOPT_set_string, &config_file}
    };

  GNUNET_assert (GNUNET_SYSERR !=
                   GNUNET_GETOPT_run ("taler-exchange-benchmark",
                                      options, argc, argv));
  #ifdef RUNXCG
  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-exchange-keyup",
                                  "taler-exchange-keyup",
                                  NULL);
  if (NULL == proc)
  {
    fprintf (stderr,
             "Failed to run taler-exchange-keyup. Check your PATH.\n");
    return 77;
  }

  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);

  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-exchange-dbinit",
                                  "taler-exchange-dbinit",
                                  "-r",
                                  NULL);


  if (NULL == proc)
  {
    fprintf (stderr,
             "Failed to run taler-exchange-dbinit. Check your PATH.\n");
    return 77;
  }
  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);

  exchanged = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-exchange-httpd",
                                       "taler-exchange-httpd",
                                       NULL);
  if (NULL == exchanged)
  {
    fprintf (stderr,
             "Failed to run taler-exchange-httpd. Check your PATH.\n");
    return 77;
  }

  cnt = 0;
  do
    {
      fprintf (stderr, ".");
      sleep (1);
      cnt++;
      if (cnt > 60)
      {
        fprintf (stderr,
                 "\nFailed to start taler-exchange-httpd\n");
        GNUNET_OS_process_kill (exchanged,
                                SIGKILL);
        GNUNET_OS_process_wait (exchanged);
        GNUNET_OS_process_destroy (exchanged);
        return 77;
      }
    }
  while (0 != system ("wget -q -t 1 -T 1 " EXCHANGE_URI "keys -o /dev/null -O /dev/null"));
  fprintf (stderr, "\n");
  #endif

  GNUNET_SCHEDULER_run (&run, NULL);
  #ifdef RUNXCG
  GNUNET_OS_process_wait (exchanged);
  GNUNET_OS_process_destroy (exchanged);
  #endif

  return GNUNET_OK;
}
