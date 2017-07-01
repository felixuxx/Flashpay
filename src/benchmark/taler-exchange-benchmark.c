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
  TALER; see the file COPYING.LGPL.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file src/benchmark/taler-exchange-benchmark.c
 * @brief exchange's benchmark
 * @author Marcello Stanisci
 * @author Christian Grothoff
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

/**
 * How much slack do we leave in terms of coins that are invalid (and
 * thus available for refresh)?  Should be significantly larger
 * than #REFRESH_SLOTS_NEEDED, and must be below #pool_size.
 */
#define INVALID_COIN_SLACK 20

/**
 * How much slack must we have to do a refresh? Should be the
 * maximum number of coins a refresh can generate, and thus
 * larger than log(base 2) of #COIN_VALUE.  Must also be
 * smaller than #INVALID_COIN_SLACK and smaller than 64.
 */
#define REFRESH_SLOTS_NEEDED 5

/**
 * The benchmark withdraws always the same denomination, since the
 * calculation for refreshing is statically done (at least in this
 * first version).  In the future, this will be the largest value
 * we ever withdraw.
 */
#define COIN_VALUE 8

/**
 * Probability a coin can be refreshed.
 * This probability multiplied by the number of coins
 * generated during the average refresh must be smaller
 * than one.  The variance must be covered by the
 * #INVALID_COIN_SLACK.
 */
#define REFRESH_PROBABILITY 0.1

/**
 * What is the amount we deposit into a reserve each time.
 * We keep it simple and always deposit the same amount for now.
 */
#define RESERVE_VALUE 1000

/**
 * What should be the ratio of coins withdrawn per reserve?
 * We roughly match #RESERVE_VALUE / #COIN_VALUE, as that
 * matches draining the reserve.
 */
#define COINS_PER_RESERVE 12

/**
 * How many times must #benchmark_run() execute before we
 * consider ourselves warm?
 */
#define WARM_THRESHOLD 1000LL

/**
 * List of coins to get in return to a melt operation, in order
 * of preference. The values from this structure are converted
 * to the #refresh_pk array.  Must be NULL-terminated.  The
 * currency is omitted as we get that from /keys.
 */
static const char *refresh_denoms[] = {
  "4.00",
  "2.00",
  "1.00",
  NULL
};


/**
 * Needed information for a reserve. Other values are the same for all reserves, therefore defined in global variables
 */
struct Reserve
{
  /**
   * DLL of reserves to fill.
   */
  struct Reserve *next;

  /**
   * DLL of reserves to fill.
   */
  struct Reserve *prev;

  /**
   * Set (by the interpreter) to the reserve's private key
   * we used to fill the reserve.
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

  /**
   * Set to the API's handle during the operation.
   */
  struct TALER_EXCHANGE_AdminAddIncomingHandle *aih;

  /**
   * How much is left in this reserve.
   */
  struct TALER_Amount left;

  /**
   * Index of this reserve in the #reserves array.
   */
  unsigned int reserve_index;

};


/**
 * Information regarding a coin
 */
struct Coin
{

  /**
   * DLL of coins to withdraw.
   */
  struct Coin *next;

  /**
   * DLL of coins to withdraw.
   */
  struct Coin *prev;

  /**
   * Set (by the interpreter) to the exchange's signature over the
   * coin's public key.
   */
  struct TALER_DenominationSignature sig;

  /**
   * Set to the coin's private key.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * This specifies the denomination key to use.
   */
  const struct TALER_EXCHANGE_DenomPublicKey *pk;

  /**
   * Withdraw handle (while operation is running).
   */
  struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh;

  /**
   * Refresh melt handle
   */
  struct TALER_EXCHANGE_RefreshMeltHandle *rmh;

  /**
   * Refresh reveal handle
   */
  struct TALER_EXCHANGE_RefreshRevealHandle *rrh;

  /**
   * Deposit handle (while operation is running).
   */
  struct TALER_EXCHANGE_DepositHandle *dh;

  /**
   * Array of denominations we expect to get from melt.
   */
  struct TALER_Amount *denoms;

  /**
   * The result of a #TALER_EXCHANGE_refresh_prepare() call
   */
  char *blob;

  /**
   * Size of @e blob
   */
  size_t blob_size;

  /**
   * Flag indicating if the coin is going to be refreshed
   */
  unsigned int refresh;

  /**
   * #GNUNET_YES if this coin is in the #invalid_coins_head DLL.
   */
  int invalid;

  /**
   * Index in the reserve's global array indicating which
   * reserve this coin is to be retrieved. If the coin comes
   * from a refresh, then this value is set to the melted coin's
   * reserve index
   */
  unsigned int reserve_index;

  /**
   * Index of this coin in the #coins array.
   */
  unsigned int coin_index;

  /**
   * If the coin has to be refreshed, this value indicates
   * how much is left on this coin
   */
  struct TALER_Amount left;

};


/**
 * DLL of reserves to fill.
 */
static struct Reserve *empty_reserve_head;

/**
 * DLL of reserves to fill.
 */
static struct Reserve *empty_reserve_tail;

/**
 * DLL of coins to withdraw.
 */
static struct Coin *invalid_coins_head;

/**
 * DLL of coins to withdraw.
 */
static struct Coin *invalid_coins_tail;

/**
 * How many coins are in the #invalid_coins_head DLL?
 */
static unsigned int num_invalid_coins;

/**
 * Should we initialize and start the exchange, if #GNUNET_NO,
 * we expect one to be already up and running.
 */
static int run_exchange;

/**
 * Enables printing of "C" and "W" to indicate progress (warm/cold)
 * every 50 iterations. Also includes how long the iteration took,
 * so we can see if it is stable.
 */
static unsigned int be_verbose;

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
static struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * How many reserves ought to be created given the pool size
 */
static unsigned int nreserves;

/**
 * How many coins are in the #coins array. This is needed
 * as the number of coins is not always #nreserves * #COINS_PER_RESERVE
 * due to refresh operations
 */
static unsigned int ncoins;

/**
 * Bank details of who creates reserves
 */
static json_t *bank_details;

/**
 * Bank details of who deposits coins
 */
static json_t *merchant_details;

/**
 * Array of denomination keys needed to perform the refresh operation
 */
static struct TALER_EXCHANGE_DenomPublicKey *refresh_pk;

/**
 * Size of #refresh_pk
 */
static unsigned int refresh_pk_len;

/**
 * Same blinding key for all coins
 */
static struct TALER_DenominationBlindingKeyP blinding_key;

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
static struct GNUNET_SCHEDULER_Task *benchmark_task;

/**
 * Main execution context for the main loop of the exchange.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Handle to access the exchange.
 */
static struct TALER_EXCHANGE_Handle *exchange;

/**
 * The array of all reserves, of length #nreserves.
 */
static struct Reserve *reserves;

/**
 * The array of all coins, of length #ncoins.
 */
static struct Coin *coins;

/**
 * Transfer UUID counter, used in /admin/add/incoming
 */
static unsigned int transfer_uuid;

/**
 * This key (usually provided by merchants) is needed when depositing coins,
 * even though there is no merchant acting in the benchmark
 */
static struct TALER_MerchantPrivateKeyP merchant_priv;

/**
 * URI under which the exchange is reachable during the benchmark.
 */
static char *exchange_uri;

/**
 * URI under which the administrative exchange is reachable during the
 * benchmark.
 */
static char *exchange_admin_uri;

/**
 * Used currency (read from /keys' output)
 */
static char *currency;

/**
 * What time did we start to really measure performance?
 */
static struct GNUNET_TIME_Absolute start_time;

/**
 * Number of times #benchmark_run has executed. Used
 * to indicate when we consider us warm.
 */
static unsigned long long warm;

/**
 * Number of times #benchmark_run should execute
 * before we shut down.
 */
static unsigned int num_iterations;

/**
 * Number of /deposit operations we have executed since #start_time.
 */
static unsigned long long num_deposit;

/**
 * Number of /withdraw operations we have executed since #start_time.
 */
static unsigned long long num_withdraw;

/**
 * Number of /refresh operations we have executed since #start_time.
 */
static unsigned long long num_refresh;

/**
 * Number of /admin operations we have executed since #start_time.
 */
static unsigned long long num_admin;


/**
 * Throw a weighted coin with @a probability.
 *
 * @return #GNUNET_OK with @a probability, #GNUNET_NO with 1 - @a probability
 */
static unsigned int
eval_probability (float probability)
{
  uint64_t random;
  float random_01;

  random = GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK,
				     UINT64_MAX);
  random_01 = (double) random / UINT64_MAX;
  return (random_01 <= probability) ? GNUNET_OK : GNUNET_NO;
}


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
}


/**
 * Main task for the benchmark.
 *
 * @param cls NULL
 */
static void
benchmark_run (void *cls);


/**
 * Run the main task for the benchmark.
 */
static void
continue_master_task ()
{
  benchmark_task = GNUNET_SCHEDULER_add_now (&benchmark_run,
                                             NULL);
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
 * @param cls closure with the `struct Coin *`
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param num_coins number of fresh coins created, length of the @a sigs and @a coin_privs arrays, 0 if the operation failed
 * @param coin_privs array of @a num_coins private keys for the coins that were created, NULL on error
 * @param sigs array of signature over @a num_coins coins, NULL on error
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
static void
reveal_cb (void *cls,
           unsigned int http_status,
	   enum TALER_ErrorCode ec,
           unsigned int num_coins,
           const struct TALER_CoinSpendPrivateKeyP *coin_privs,
           const struct TALER_DenominationSignature *sigs,
           const json_t *full_response)
{
  struct Coin *coin = cls;
  unsigned int i;
  const struct TALER_EXCHANGE_Keys *keys;

  coin->rrh = NULL;
  if (MHD_HTTP_OK != http_status)
  {
    json_dumpf (full_response, stderr, 0);
    fail ("Not all coins correctly revealed");
    return;
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Coin #%d revealed!\n",
                coin->coin_index);
    coin->left.value = 0;
  }

  keys = TALER_EXCHANGE_get_keys (exchange);
  for (i=0; i<num_coins; i++)
  {
    struct Coin *fresh_coin;
    char *revealed_str;

    revealed_str = TALER_amount_to_string (&coin->denoms[i]);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "revealing %s # of coins after refresh: %d\n",
                revealed_str,
                ncoins);
    GNUNET_free (revealed_str);

    fresh_coin = invalid_coins_head;
    if (NULL == fresh_coin)
    {
      /* #REFRESH_SLOTS_NEEDED too low? */
      GNUNET_break (0);
      continue;
    }
    GNUNET_CONTAINER_DLL_remove (invalid_coins_head,
				 invalid_coins_tail,
				 fresh_coin);
    num_invalid_coins--;
    fresh_coin->invalid = GNUNET_NO;
    fresh_coin->pk = find_pk (keys, &coin->denoms[i]);
    GNUNET_assert (NULL == fresh_coin->sig.rsa_signature);
    fresh_coin->sig.rsa_signature =
      GNUNET_CRYPTO_rsa_signature_dup (sigs[i].rsa_signature);
    fresh_coin->coin_priv = coin_privs[i];
    fresh_coin->left = coin->denoms[i];
  }
  GNUNET_free (coin->denoms);
  coin->denoms = NULL;
  continue_master_task ();
}


/**
 * Function called with the result of the /refresh/melt operation.
 *
 * @param cls closure with the `struct Coin *`
 * @param http_status HTTP response code, never #MHD_HTTP_OK (200) as for successful intermediate response this callback is skipped.
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param noreveal_index choice by the exchange in the cut-and-choose protocol,
 *                    UINT16_MAX on error
 * @param exchange_pub public key the exchange used for signing
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
static void
melt_cb (void *cls,
         unsigned int http_status,
	 enum TALER_ErrorCode ec,
         uint16_t noreveal_index,
         const struct TALER_ExchangePublicKeyP *exchange_pub,
         const json_t *full_response)
{
  struct Coin *coin = cls;

  coin->rmh = NULL;
  if (MHD_HTTP_OK != http_status)
  {
    json_dumpf (full_response, stderr, 0);
    fail ("Coin not correctly melted!");
    return;
  }

  coin->rrh
    = TALER_EXCHANGE_refresh_reveal (exchange,
                                     coin->blob_size,
                                     coin->blob,
                                     noreveal_index,
                                     &reveal_cb,
                                     coin);
  GNUNET_free (coin->blob);
  coin->blob = NULL;
  if (NULL == coin->rrh)
  {
    fail ("Failed on reveal during refresh!");
    return;
  }
}


/**
 * Mark coin as invalid.
 *
 * @param coin coin to mark invalid
 */
static void
invalidate_coin (struct Coin *coin)
{
  GNUNET_CONTAINER_DLL_insert (invalid_coins_head,
			       invalid_coins_tail,
			       coin);
  num_invalid_coins++;
  coin->invalid = GNUNET_YES;
  if (NULL != coin->sig.rsa_signature)
  {
    GNUNET_CRYPTO_rsa_signature_free (coin->sig.rsa_signature);
    coin->sig.rsa_signature = NULL;
  }
}


/**
 * Refresh the given @a coin
 *
 * @param coin coin to refresh
 */
static void
refresh_coin (struct Coin *coin)
{
  char *blob;
  size_t blob_size;
  struct TALER_Amount *denoms = NULL;
  struct TALER_EXCHANGE_DenomPublicKey *dpks = NULL;
  const struct TALER_EXCHANGE_DenomPublicKey *curr_dpk;
  struct TALER_Amount curr;
  struct TALER_Amount left;
  unsigned int ndenoms = 0;
  unsigned int ndenoms2 = 0;
  unsigned int off;

  GNUNET_break (NULL == coin->denoms);
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency, &curr));
  left = coin->left;
  off = 0;
  while (0 != TALER_amount_cmp (&curr,
				&left))
  {
    if (off >= refresh_pk_len)
    {
      /* refresh currency choices do not add up! */
      GNUNET_break (0);
      break;
    }
    curr_dpk = &refresh_pk[off];
    while (-1 != TALER_amount_cmp (&left,
				   &curr_dpk->value))
    {
      GNUNET_array_append (denoms,
			   ndenoms,
			   curr_dpk->value);
      GNUNET_array_append (dpks,
			   ndenoms2,
			   *curr_dpk);
      GNUNET_assert (GNUNET_SYSERR !=
		     TALER_amount_subtract (&left,
					    &left,
					    &curr_dpk->value));
    }
    off++;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
	      "# of coins to get in melt: %d\n",
	      ndenoms2);
  GNUNET_break (ndenoms2 <= REFRESH_SLOTS_NEEDED);
  blob = TALER_EXCHANGE_refresh_prepare (&coin->coin_priv,
					 &coin->left,
					 &coin->sig,
					 coin->pk,
					 GNUNET_YES,
					 ndenoms2,
					 dpks,
					 &blob_size);
  invalidate_coin (coin);
  GNUNET_array_grow (dpks,
		     ndenoms2,
		     0);
  if (NULL == blob)
  {
    fail ("Failed to prepare refresh");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
	      "Prepared blob of size %d for refresh\n",
	      (unsigned int) blob_size);

  coin->blob = blob;
  coin->blob_size = blob_size;
  coin->denoms = denoms;
  if (warm >= WARM_THRESHOLD)
    num_refresh++;
  coin->rmh = TALER_EXCHANGE_refresh_melt (exchange,
					   blob_size,
					   blob,
					   &melt_cb,
					   coin);
  if (NULL == coin->rmh)
  {
    fail ("Impossible to issue a melt request to the exchange");
    return;
  }
}


/**
 * Function called with the result of a /deposit operation.
 *
 * @param cls closure with the `struct Coin` that we are processing
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful deposit;
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param exchange_pub public key used by the exchange for signing
 * @param obj the received JSON reply, should be kept as proof (and, in case of errors,
 *            be forwarded to the customer)
 */
static void
deposit_cb (void *cls,
            unsigned int http_status,
	    enum TALER_ErrorCode ec,
            const struct TALER_ExchangePublicKeyP *exchange_pub,
            const json_t *obj)
{
  struct Coin *coin = cls;

  coin->dh = NULL;
  if (MHD_HTTP_OK != http_status)
  {
    json_dumpf (obj, stderr, 0);
    fail ("At least one coin has not been deposited, status: %d");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Coin #%d correctly spent!\n",
              coin->coin_index);
  if (GNUNET_YES == coin->refresh)
  {
    refresh_coin (coin);
  }
  else
  {
    invalidate_coin (coin);
    continue_master_task ();
  }
}


/**
 * Spend the given coin.  Also triggers refresh
 * with a certain probability.
 *
 * @param coin coin to spend
 * @param do_refresh should we also do the refresh?
 */
static void
spend_coin (struct Coin *coin,
	    int do_refresh)
{
  struct TALER_Amount amount;
  struct GNUNET_TIME_Absolute wire_deadline;
  struct GNUNET_TIME_Absolute timestamp;
  struct GNUNET_TIME_Absolute refund_deadline;
  struct GNUNET_HashCode h_contract_terms;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct TALER_DepositRequestPS dr;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct TALER_CoinSpendSignatureP coin_sig;

  GNUNET_CRYPTO_eddsa_key_get_public (&coin->coin_priv.eddsa_priv,
				      &coin_pub.eddsa_pub);
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
			      &h_contract_terms,
			      sizeof (h_contract_terms));
  timestamp = GNUNET_TIME_absolute_get ();
  wire_deadline = GNUNET_TIME_absolute_add (timestamp,
					    GNUNET_TIME_UNIT_WEEKS);
  refund_deadline = GNUNET_TIME_absolute_add (timestamp,
					      GNUNET_TIME_UNIT_DAYS);
  GNUNET_TIME_round_abs (&timestamp);
  GNUNET_TIME_round_abs (&wire_deadline);
  GNUNET_TIME_round_abs (&refund_deadline);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
	      "Spending %d-th coin\n",
	      coin->coin_index);

  if (do_refresh)
  {
    /**
     * Always spending 1 out of 8 KUDOS. To be improved by randomly
     * picking the spent amount
     */
    struct TALER_Amount one;

    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (currency, &one));
    one.value = 1;

    GNUNET_assert (GNUNET_SYSERR !=
                   TALER_amount_subtract (&amount,
                                          &one,
                                          &coin->pk->fee_deposit));
    GNUNET_assert (GNUNET_SYSERR !=
                   TALER_amount_subtract (&coin->left,
                                          &coin->pk->value,
                                          &one));
    coin->refresh = GNUNET_YES;
  }
  else
  {
    GNUNET_assert (GNUNET_SYSERR !=
                   TALER_amount_subtract (&amount,
                                          &coin->pk->value,
                                          &coin->pk->fee_deposit));
    coin->refresh = GNUNET_NO;
  }
  memset (&dr, 0, sizeof (dr));
  dr.purpose.size = htonl (sizeof (struct TALER_DepositRequestPS));
  dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT);
  dr.h_contract_terms = h_contract_terms;
  TALER_JSON_hash (merchant_details,
		   &dr.h_wire);

  dr.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  dr.refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline);

  TALER_amount_hton (&dr.amount_with_fee,
		     &amount);
  TALER_amount_hton (&dr.deposit_fee,
		     &coin->pk->fee_deposit);

  GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv.eddsa_priv,
				      &merchant_pub.eddsa_pub);
  dr.merchant = merchant_pub;
  dr.coin_pub = coin_pub;
  GNUNET_assert (GNUNET_OK ==
		 GNUNET_CRYPTO_eddsa_sign (&coin->coin_priv.eddsa_priv,
					   &dr.purpose,
					   &coin_sig.eddsa_signature));
  if (warm >= WARM_THRESHOLD)
    num_deposit++;
  coin->dh = TALER_EXCHANGE_deposit (exchange,
				     &amount,
				     wire_deadline,
				     merchant_details,
				     &h_contract_terms,
				     &coin_pub,
				     &coin->sig,
				     &coin->pk->key,
				     timestamp,
				     &merchant_pub,
				     refund_deadline,
				     &coin_sig,
				     &deposit_cb,
				     coin);
  if (NULL == coin->dh)
  {
    fail ("An error occurred while calling deposit API");
    return;
  }
}


/**
 * Function called upon completion of our /reserve/withdraw request.
 * This is merely the function which spends withdrawn coins. For each
 * spent coin, it either refresh it or re-withdraw it.
 *
 * @param cls closure with our `struct Coin`
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param sig signature over the coin, NULL on error
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
static void
reserve_withdraw_cb (void *cls,
                     unsigned int http_status,
		     enum TALER_ErrorCode ec,
                     const struct TALER_DenominationSignature *sig,
                     const json_t *full_response)
{
  struct Coin *coin = cls;

  coin->wsh = NULL;
  if (MHD_HTTP_OK != http_status)
  {
    json_dumpf (full_response, stderr, 0);
    fail ("At least one coin has not correctly been withdrawn");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "%d-th coin withdrawn\n",
              coin->coin_index);
  coin->sig.rsa_signature =
    GNUNET_CRYPTO_rsa_signature_dup (sig->rsa_signature);
  GNUNET_CONTAINER_DLL_remove (invalid_coins_head,
			       invalid_coins_tail,
			       coin);
  num_invalid_coins--;
  coin->invalid = GNUNET_NO;
  continue_master_task ();
}


/**
 * Withdraw the given coin from the respective reserve.
 *
 * @param coin coin to withdraw
 */
static void
withdraw_coin (struct Coin *coin)
{
  struct GNUNET_CRYPTO_EddsaPrivateKey *coin_priv;
  struct TALER_Amount amount;
  struct TALER_Amount left;
  const struct TALER_EXCHANGE_Keys *keys;
  struct Reserve *r;

  keys = TALER_EXCHANGE_get_keys (exchange);
  r = &reserves[coin->reserve_index];
  coin_priv = GNUNET_CRYPTO_eddsa_key_create ();
  coin->coin_priv.eddsa_priv = *coin_priv;
  GNUNET_free (coin_priv);
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &amount));
  amount.value = COIN_VALUE;
  GNUNET_assert (-1 != TALER_amount_cmp (&r->left,
					 &amount));
  GNUNET_assert (NULL != (coin->pk = find_pk (keys, &amount)));
  if (warm >= WARM_THRESHOLD)
    num_withdraw++;
  coin->wsh =
    TALER_EXCHANGE_reserve_withdraw (exchange,
				     coin->pk,
				     &r->reserve_priv,
				     &coin->coin_priv,
				     &blinding_key,
				     &reserve_withdraw_cb,
				     coin);
  GNUNET_assert (GNUNET_SYSERR !=
		 TALER_amount_subtract (&left,
					&r->left,
					&amount));
  r->left = left;
  if (-1 == TALER_amount_cmp (&left,
			      &amount))
  {
    /* not enough left in the reserve for future withdrawals,
       create a new reserve! */
    GNUNET_CONTAINER_DLL_insert (empty_reserve_head,
				 empty_reserve_tail,
				 r);
  }
}


/**
 * Function called upon completion of our /admin/add/incoming request.
 * Its duty is withdrawing coins on the freshly created reserve.
 *
 * @param cls closure with the `struct Reserve *`
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param full_response full response from the exchange (for logging, in case of errors)
 */
static void
add_incoming_cb (void *cls,
                 unsigned int http_status,
		 enum TALER_ErrorCode ec,
                 const json_t *full_response)
{
  struct Reserve *r = cls;

  r->aih = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "/admin/add/incoming callback called on %d-th reserve\n",
              r->reserve_index);
  if (MHD_HTTP_OK != http_status)
  {
    json_dumpf (full_response, stderr, 0);
    fail ("At least one reserve failed in being created");
    return;
  }
  GNUNET_CONTAINER_DLL_remove (empty_reserve_head,
			       empty_reserve_tail,
			       r);
  continue_master_task ();
}


/**
 * Fill a reserve using /admin/add/incoming
 *
 * @param r reserve to fill
 */
static void
fill_reserve (struct Reserve *r)
{
  struct GNUNET_CRYPTO_EddsaPrivateKey *priv;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct GNUNET_TIME_Absolute execution_date;
  struct TALER_Amount reserve_amount;
  json_t *transfer_details;

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &reserve_amount));
  reserve_amount.value = RESERVE_VALUE;
  execution_date = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&execution_date);

  priv = GNUNET_CRYPTO_eddsa_key_create ();
  r->reserve_priv.eddsa_priv = *priv;
  GNUNET_free (priv);
  transfer_details = json_pack ("{s:I}",
				"uuid", (json_int_t) transfer_uuid++);
  GNUNET_assert (NULL != transfer_details);
  GNUNET_CRYPTO_eddsa_key_get_public (&r->reserve_priv.eddsa_priv,
				      &reserve_pub.eddsa_pub);
  r->left = reserve_amount;
  if (warm >= WARM_THRESHOLD)
    num_admin++;
  r->aih = TALER_EXCHANGE_admin_add_incoming (exchange,
					      exchange_admin_uri,
					      &reserve_pub,
					      &reserve_amount,
					      execution_date,
					      bank_details,
					      transfer_details,
					      &add_incoming_cb,
					      r);
  GNUNET_assert (NULL != r->aih);
  json_decref (transfer_details);
}


/**
 * Main task for the benchmark.
 *
 * @param cls NULL
 */
static void
benchmark_run (void *cls)
{
  unsigned int i;
  int refresh;
  struct Coin *coin;

  benchmark_task = NULL;
  /* First, always make sure all reserves are full */
  if (NULL != empty_reserve_head)
  {
    fill_reserve (empty_reserve_head);
    return;
  }
  /* Second, withdraw until #num_invalid_coins is less than
     #INVALID_COIN_SLACK */
  if (num_invalid_coins > INVALID_COIN_SLACK)
  {
    withdraw_coin (invalid_coins_head);
    return;
  }
  warm++;
  if ( be_verbose &&
       (0 == (warm % 50)) )
  {
    static struct GNUNET_TIME_Absolute last;
    struct GNUNET_TIME_Relative duration;

    if (0 != last.abs_value_us)
      duration = GNUNET_TIME_absolute_get_duration (last);
    else
      duration = GNUNET_TIME_UNIT_FOREVER_REL;
    last = GNUNET_TIME_absolute_get ();
    fprintf (stderr,
	     "%s - %s\n",
	     WARM_THRESHOLD < warm ? "WARM" : "COLD",
	     GNUNET_STRINGS_relative_time_to_string (duration,
						     GNUNET_YES));
  }
  if (WARM_THRESHOLD == warm)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		"Benchmark warm.\n");
    start_time = GNUNET_TIME_absolute_get ();
  }
  if ( (warm > num_iterations) &&
       (0 != num_iterations) )
  {
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  /* By default, pick a random valid coin to spend */
  for (i=0;i<1000;i++)
  {
    coin = &coins[GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
					    ncoins)];
    if (GNUNET_YES == coin->invalid)
      continue; /* unlucky draw, try again */
    if (1 == coin->left.value)
      refresh = GNUNET_NO; /* cannot refresh, coin is already at unit */
    else
      refresh = eval_probability (REFRESH_PROBABILITY);
    if (num_invalid_coins < REFRESH_SLOTS_NEEDED)
      refresh = GNUNET_NO;
    spend_coin (coin,
		refresh);
    return;
  }
  fail ("Too many invalid coins, is your INVALID_COIN_SLACK too high?");
}


/**
 * Populates the global array of denominations which will
 * be withdrawn in a refresh operation. It sums up 4 #currency units,
 * since that is the only amount refreshed so far by the benchmark
 *
 * @return #GNUNET_OK if the array is correctly built, #GNUNET_SYSERR
 * otherwise
 */
static unsigned int
build_refresh ()
{
  char *amount_str;
  struct TALER_Amount amount;
  unsigned int i;
  const struct TALER_EXCHANGE_DenomPublicKey *picked_denom;
  const struct TALER_EXCHANGE_Keys *keys;

  GNUNET_array_grow (refresh_pk,
		     refresh_pk_len,
		     0);
  keys = TALER_EXCHANGE_get_keys (exchange);
  for (i=0; NULL != refresh_denoms[i]; i++)
  {
    GNUNET_asprintf (&amount_str,
		     "%s:%s",
		     currency,
		     refresh_denoms[i]);
    GNUNET_assert (GNUNET_OK ==
		   TALER_string_to_amount (amount_str,
					   &amount));
    picked_denom = find_pk (keys,
			    &amount);
    if (NULL == picked_denom)
    {
      GNUNET_break (0);
      GNUNET_free (amount_str);
      return GNUNET_SYSERR;
    }
    GNUNET_array_append (refresh_pk,
			 refresh_pk_len,
			 *picked_denom);
    GNUNET_free (amount_str);
  }
  return GNUNET_OK;
}


/**
 * Functions of this type are called to provide the retrieved signing and
 * denomination keys of the exchange.  No TALER_EXCHANGE_*() functions should be called
 * in this callback.
 *
 * @param cls closure
 * @param _keys information about keys of the exchange
 * @param vc compatibility information
 */
static void
cert_cb (void *cls,
         const struct TALER_EXCHANGE_Keys *_keys,
	 enum TALER_EXCHANGE_VersionCompatibility vc)
{
  /* check that keys is OK */
  if (NULL == _keys)
  {
    fail ("Exchange returned no keys!");
    return;
  }
  if ( (0 == _keys->num_sign_keys) ||
       (0 == _keys->num_denom_keys) )
  {
    GNUNET_break (0);
    fail ("Bad /keys response");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Read %u signing keys and %u denomination keys\n",
              _keys->num_sign_keys,
              _keys->num_denom_keys);
  if (NULL != currency)
  {
    /* we've been here before, still need to update refresh_denoms */
    if (GNUNET_SYSERR ==
	build_refresh ())
    {
      fail ("Initializing denominations failed");
      return;
    }
    return;
  }
  currency = GNUNET_strdup (_keys->denom_keys[0].value.currency);
  if (GNUNET_SYSERR ==
      build_refresh ())
  {
    fail ("Initializing denominations failed");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
	      "Using currency: %s\n",
	      currency);
  continue_master_task ();
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
  struct GNUNET_TIME_Relative duration;

  if (warm >= WARM_THRESHOLD)
    duration = GNUNET_TIME_absolute_get_duration (start_time);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
	      "Shutting down...\n");
  if (NULL != benchmark_task)
  {
    GNUNET_SCHEDULER_cancel (benchmark_task);
    benchmark_task = NULL;
  }
  for (i=0; i<nreserves; i++)
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
  for (i=0; i<COINS_PER_RESERVE * nreserves; i++)
  {
    struct Coin *coin = &coins[i];

    if (NULL != coin->wsh)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Cancelling %d-th coin withdraw handle\n",
                  i);
      TALER_EXCHANGE_reserve_withdraw_cancel (coin->wsh);
      coin->wsh = NULL;
    }
    if (NULL != coin->dh)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Cancelling %d-th coin deposit handle\n",
                  i);
      TALER_EXCHANGE_deposit_cancel(coin->dh);
      coin->dh = NULL;
    }
    if (NULL != coin->rmh)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Cancelling %d-th coin melt handle\n",
                  i);
      TALER_EXCHANGE_refresh_melt_cancel (coin->rmh);
      coin->rmh = NULL;
    }
    if (NULL != coin->rrh)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Cancelling %d-th coin reveal handle\n",
                  i);
      TALER_EXCHANGE_refresh_reveal_cancel (coin->rrh);
      coin->rmh = NULL;
    }
    if (NULL != coin->blob)
    {
      GNUNET_free (coin->blob);
      coin->blob = NULL;
    }
    if (NULL != coin->sig.rsa_signature)
    {
      GNUNET_CRYPTO_rsa_signature_free (coin->sig.rsa_signature);
      coin->sig.rsa_signature = NULL;
    }
    if (NULL != coin->denoms)
    {
      GNUNET_free (coin->denoms);
      coin->denoms = NULL;
    }
  }
  if (NULL != bank_details)
  {
    json_decref (bank_details);
    bank_details = NULL;
  }
  if (NULL != merchant_details)
  {
    json_decref (merchant_details);
    merchant_details = NULL;
  }
  GNUNET_free_non_null (reserves);
  reserves = NULL;
  GNUNET_free_non_null (coins);
  coins = NULL;
  GNUNET_free_non_null (currency);
  currency = NULL;

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
  GNUNET_CONFIGURATION_destroy (cfg);
  cfg = NULL;
  if (warm >= WARM_THRESHOLD)
  {
    fprintf (stderr,
	     "Executed A=%llu/W=%llu/D=%llu/R=%llu operations in %s\n",
	     num_admin,
	     num_withdraw,
	     num_deposit,
	     num_refresh,
	     GNUNET_STRINGS_relative_time_to_string (duration,
						     GNUNET_YES));
  }
  else
  {
    fprintf (stdout,
	     "Sorry, no results, benchmark did not get warm!\n");
  }
}


/**
 * Main function that will be run by the scheduler.
 * Prepares everything for the benchmark.
 *
 * @param cls closure
 */
static void
run (void *cls)
{
  char *bank_details_filename;
  char *merchant_details_filename;
  struct GNUNET_CRYPTO_EddsaPrivateKey *priv;
  unsigned int i;
  unsigned int j;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "gotten pool_size of %d\n",
              pool_size);
  cfg = GNUNET_CONFIGURATION_create ();
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
				 NULL);
  if (GNUNET_SYSERR ==
      GNUNET_CONFIGURATION_parse (cfg,
                                  config_file))
  {
    fail ("Failed to parse configuration file");
    return;
  }
  if (pool_size < INVALID_COIN_SLACK)
  {
    fail ("Pool size given too small.");
    return;
  }
  if (GNUNET_SYSERR ==
      GNUNET_CONFIGURATION_get_value_filename (cfg,
					       "benchmark",
					       "bank_details",
					       &bank_details_filename))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
			       "benchmark",
			       "bank_details");
    fail ("Failed to get BANK_DETAILS value");
    return;
  }

  bank_details = json_load_file (bank_details_filename,
				 JSON_REJECT_DUPLICATES,
				 NULL);
  GNUNET_free (bank_details_filename);
  if (NULL == bank_details)
  {
    fail ("Failed to parse file with BANK_DETAILS");
    return;
  }
  if (GNUNET_SYSERR ==
      GNUNET_CONFIGURATION_get_value_filename (cfg,
					       "benchmark",
					       "merchant_details",
					       &merchant_details_filename))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
			       "benchmark",
			       "merchant_details");
    fail ("Failed to get MERCHANT_DETAILS value");
    return;
  }
  merchant_details = json_load_file (merchant_details_filename,
                                     JSON_REJECT_DUPLICATES,
                                     NULL);
  GNUNET_free (merchant_details_filename);
  if (NULL == merchant_details)
  {
    fail ("Failed to parse file with MERCHANT_DETAILS");
    return;
  }

  priv = GNUNET_CRYPTO_eddsa_key_create ();
  merchant_priv.eddsa_priv = *priv;
  GNUNET_free (priv);

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &blinding_key,
                              sizeof (blinding_key));

  nreserves = pool_size / COINS_PER_RESERVE;
  if (COINS_PER_RESERVE * nreserves < pool_size)
    nreserves++;
  reserves = GNUNET_new_array (nreserves,
                               struct Reserve);
  ncoins = COINS_PER_RESERVE * nreserves;
  coins = GNUNET_new_array (ncoins,
                            struct Coin);
  for (i=0;i < nreserves;i++)
  {
    struct Reserve *r = &reserves[i];

    r->reserve_index = i;
    GNUNET_CONTAINER_DLL_insert (empty_reserve_head,
				 empty_reserve_tail,
				 r);
    for (j=0; j < COINS_PER_RESERVE; j++)
    {
      struct Coin *coin;
      unsigned int coin_index;

      coin_index = i * COINS_PER_RESERVE + j;
      coin = &coins[coin_index];
      coin->coin_index = coin_index;
      coin->reserve_index = i;
      invalidate_coin (coin);
    }
  }

  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  GNUNET_assert (NULL != ctx);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  GNUNET_assert (NULL != rc);
  exchange = TALER_EXCHANGE_connect (ctx,
                                     exchange_uri,
                                     &cert_cb, NULL,
                                     TALER_EXCHANGE_OPTION_END);
  if (NULL == exchange)
  {
    fail ("Failed to connect to the exchange!");
    return;
  }
}


int
main (int argc,
      char * const *argv)
{
  struct GNUNET_OS_Process *proc;
  unsigned int cnt;
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_flag ('a',
                               "automate",
                               "Initialize and start the bank and exchange",
                               &run_exchange),
    GNUNET_GETOPT_option_mandatory
    (GNUNET_GETOPT_option_cfgfile (&config_file)),
    GNUNET_GETOPT_option_string ('e',
                                 "exchange-uri",
                                 "URI",
                                 "URI of the exchange",
                                 &exchange_uri),
    GNUNET_GETOPT_option_string ('E',
                                 "exchange-admin-uri",
                                 "URI",
                                 "URI of the administrative interface of the exchange",
                                 &exchange_admin_uri),
    GNUNET_GETOPT_option_help ("tool to benchmark the Taler exchange"),
    GNUNET_GETOPT_option_uint ('s',
                               "pool-size",
                               "SIZE",
                               "How many coins this benchmark should instantiate",
                               &pool_size),
    GNUNET_GETOPT_option_uint ('l',
                               "limit",
                               "LIMIT",
                               "Terminate the benchmark after LIMIT operations",
                               &num_iterations),
    GNUNET_GETOPT_option_verbose (&be_verbose),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  GNUNET_log_setup ("taler-exchange-benchmark",
                    "WARNING",
                    NULL);
  GNUNET_assert (INVALID_COIN_SLACK >= REFRESH_SLOTS_NEEDED);
  GNUNET_assert (COIN_VALUE <= (1LL << REFRESH_SLOTS_NEEDED));
  ret = GNUNET_GETOPT_run ("taler-exchange-benchmark",
			   options, argc, argv);
  GNUNET_assert (GNUNET_SYSERR != ret);
  if (GNUNET_NO == ret)
    return 0;
  if ( (0 != num_iterations) &&
       (WARM_THRESHOLD >= num_iterations) )
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
		"Number of iterations below WARM_THRESHOLD of %llu\n",
		WARM_THRESHOLD);
  if ( (NULL == exchange_uri) ||
       (0 == strlen (exchange_uri) ))
  {
    GNUNET_free_non_null (exchange_uri);
    exchange_uri = GNUNET_strdup ("http://localhost:8081/");
  }
  if (NULL == exchange_admin_uri)
    exchange_admin_uri = GNUNET_strdup ("http://localhost:18080/");
  if (run_exchange)
  {
    char *wget;

    proc = GNUNET_OS_start_process (GNUNET_NO,
				    GNUNET_OS_INHERIT_STD_ALL,
				    NULL, NULL, NULL,
				    "taler-exchange-keyup",
				    "taler-exchange-keyup",
				    "-c", config_file,
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
				    "-c", config_file,
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
					 "-c", config_file,
					 NULL);
    if (NULL == exchanged)
    {
      fprintf (stderr,
	       "Failed to run taler-exchange-httpd. Check your PATH.\n");
      return 77;
    }

    GNUNET_asprintf (&wget,
		     "wget -q -t 1 -T 1 %s%skeys -o /dev/null -O /dev/null",
		     exchange_uri,
		     (exchange_uri[strlen (exchange_uri)-1] == '/') ? "" : "/");
    cnt = 0;
    do {
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
    while (0 != system (wget));
    GNUNET_free (wget);
    fprintf (stderr, "\n");
  }
  GNUNET_SCHEDULER_run (&run,
                        NULL);
  if (run_exchange)
  {
    GNUNET_OS_process_kill (exchanged,
                            SIGTERM);
    GNUNET_OS_process_wait (exchanged);
    GNUNET_OS_process_destroy (exchanged);
  }
  return 0;
}

/* end of taler-exchange-benchmark.c */
