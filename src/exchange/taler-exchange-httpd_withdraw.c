/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU Affero General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty
  of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General
  Public License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-exchange-httpd_withdraw.c
 * @brief Common code to handle /reserves/$RESERVE_PUB/{age,batch}-withdraw requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 * @author Ozgur Kesim
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler-exchange-httpd.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_withdraw.h"
#include "taler-exchange-httpd_common_kyc.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"
#include "taler_util.h"

/**
 * Context for both types of requests
 *  1.) #batch-withdraw
 *  2.) #age-withdraw
 */
struct WithdrawContext
{

  /**
   * This struct is kept in a DLL.
   */
  struct WithdrawContext *prev;
  struct WithdrawContext *next;

  /**
   * What type of withdraw is represented here.
   * See union #.typ for type-specific data.
   */
  enum WithdrawType
  {
    WITHDRAW_TYPE_BATCH,
    WITHDRAW_TYPE_AGE
  } withdraw_type;

  /**
     * Processing phase we are in for any of the withdraw types.
     * The ordering here partially matters, as we progress through
     * them by incrementing the phase in the happy path.
     */
  enum
  {
    PHASE_CHECK_KEYS,
    PHASE_CHECK_RESERVE_SIGNATURE,
    PHASE_RUN_LEGI_CHECK,
    PHASE_SUSPENDED,
    PHASE_CHECK_KYC_RESULT,
    PHASE_PREPARE_TRANSACTION,
    PHASE_RUN_TRANSACTION,
    PHASE_GENERATE_REPLY_SUCCESS,
    PHASE_GENERATE_REPLY_ERROR,
    PHASE_RETURN_NO,
    PHASE_RETURN_YES,
  } phase;


  /**
   * Handle for the legitimization check.
   */
  struct TEH_LegitimizationCheckHandle *lch;

  /**
   * Request context
   */
  const struct TEH_RequestContext *rc;

  /**
   * Public key of the reserve.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * KYC status for the operation.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Current time for the DB transaction.
   */
  struct GNUNET_TIME_Timestamp now;

  /**
   * Set to the hash of the normalized payto URI that established
   * the reserve.
   */
  struct TALER_NormalizedPaytoHashP h_normalized_payto;

  /**
     * Number of coins, depending on the @e withdraw_type:
     *  1) WITHDRAW_TYPE_BATCH: #elements in the @e typ.batch.planchets array.
     *  2) WITHDRAW_TYPE_AGE: #elements in the @e typ.age.planchets array
     */
  unsigned int num_coins;

  /**
   * Depending on @e withdraw_type, this union
   * contains the details of a withdraw operation:
   *   1.) WITHDRAW_TYPE_BATCH: see @e typ.batch
   *   2.) WITHDRAW_TYPE_AGE: see @e typ.age
   */
  union
  {
    /**
     * Data specific to batch_withdraw
     */
    struct
    {
      /**
       * Array of @e num_coins planchets we are processing,
       * containing the information per planchet in a batch withdraw.
       */
      struct PlanchetContext
      {

        /**
         * Value of the coin being exchanged (matching the denomination key)
         * plus the transaction fee.  We include this in what is being
         * signed so that we can verify a reserve's remaining total balance
         * without needing to access the respective denomination key
         * information each time.
         */
        struct TALER_Amount amount_with_fee;

        /**
         * Blinded planchet.
         */
        struct TALER_BlindedPlanchet blinded_planchet;

        /**
         * Set to the resulting signed coin data to be returned to the client.
         */
        struct TALER_EXCHANGEDB_CollectableBlindcoin collectable;

      }  *planchets;

      /**
       * Total amount from all coins with fees.
       */
      struct TALER_Amount batch_total;

    } batch;

    /**
     * Data specific to age_withdraw
     */
    struct
    {
      /**
       * value the client committed to
       */
      struct TALER_AgeWithdrawCommitmentHashP ach;

      /**
     * The data from the age-withdraw request, as we persist it
     */
      struct TALER_EXCHANGEDB_AgeWithdraw commitment;

      /**
       * # @e num_coins * TALER_CNC_KAPPA hashes of blinded coin planchets.
       */
      struct TALER_BlindedPlanchet (*planchets) [ TALER_CNC_KAPPA];

      /**
       * #num_coins hashes of the denominations from which the coins are withdrawn.
       * Those must support age restriction.
       */
      struct TALER_DenominationHashP *denom_hs;
    } age;

  }  typ;

  /**
   * Errors occuring during evaluation of the request are captured in this struct.
   * In phase PHASE_GENERATE_REPLY_ERROR an appropriate error message is prepared
   * and sent to the client.
   */
  struct
  {
    /**
     * The different type of errors that might occur, sorted by name.
     * Some of them require idempotency checks, which are marked
     * in array @a needs_idempotency_check_error below.
     */
    enum
    {
      ERROR_NONE,

      ERROR_AGE_AMOUNT_OVERFLOW,
      ERROR_AGE_INSUFFICIENT_FUNDS,
      ERROR_AGE_MAXIMUM_AGE_TOO_LARGE,
      ERROR_AGE_RESTRICTION_NOT_SUPPORTED_BY_DENOMINATION,
      ERROR_AGE_RESTRICTION_REQUIRED,
      ERROR_AGE_CONFIRMATION_SIGN,
      ERROR_BATCH_AMOUNT_FEE_OVERFLOW,
      ERROR_BATCH_IDEMPOTENT_PLANCHET,
      ERROR_BATCH_INSUFFICIENT_FUNDS,
      ERROR_BATCH_NONCE_RESUSE,
      ERROR_CIPHER_MISMATCH,
      ERROR_DB_FETCH_FAILED,
      ERROR_DB_INVARIANT_FAILURE,
      ERROR_DENOMINATION_BATCH_SIGN,
      ERROR_DENOMINATION_EXPIRED,
      ERROR_DENOMINATION_KEY_UNKNOWN,
      ERROR_DENOMINATION_REVOKED,
      ERROR_DENOMINATION_VALIDITY_IN_FUTURE,
      ERROR_INTERNAL_INVARIANT_FAILURE,
      ERROR_KEYS_MISSING,
      ERROR_KYC_REQUIRED,
      ERROR_LEGITIMIZATION_RESULT,
      ERROR_RESERVE_SIGNATURE_INVALID,
      ERROR_RESERVE_UNKNOWN,
      ERROR_REQUEST_PARAMETER_MALFORMED,

      ERROR_MAX
    } code;

    /**
     * Some errors require details to be sent to the client.
     * These are captured in this union.
     * Each field is marked with a comment, referring to the error(s)
     * that is/are using it.
     */
    union
    {
      /* ERROR_REQUEST_PARAMETER_MALFORMED */
      const char *hint;

      /* ERROR_AGE_AMOUNT_OVERFLOW */
      const char *which;

      /* ERROR_DENOMINATION_KEY_UNKNOWN */
      const struct TALER_DenominationHashP *denom_h;

      /* ERROR_DB_FETCH_FAILED */
      const char *db_fetch_context;

      /* ERROR_AGE_WITHDRAW_MAXIMUM_AGE_TOO_LARGE */
      struct
      {
        uint16_t max;
        uint32_t birthday;
      } age;

      /* ERROR_AGE_RESTRICTION_REQUIRED */
      uint16_t lowest_age;

      /* ERROR_AGE_INSUFFICIENT_FUNDS */
      /* ERROR_BATCH_INSUFFICIENT_FUNDS */
      struct TALER_Amount reserve_balance;

      /* ERROR_AGE_CONFIRMATION_SIGN  */
      /* ERROR_DENOMINATION_BATCH_SIGN */
      enum TALER_ErrorCode ec;

      /* ERROR_LEGITIMIZATION_RESULT */
      struct
      {
        struct MHD_Response *response;
        unsigned int http_status;
      } legi;

    } details;
  } error;
};

/**
 * This table marks which @a WithdrawContext.error.code
 * needs a idempotency check prior to actually sending an error message.
 */
static const bool
  needs_idempotency_check[] = {
  [ERROR_NONE] = false,

  [ERROR_AGE_AMOUNT_OVERFLOW] = false,
  [ERROR_AGE_CONFIRMATION_SIGN] = false,
  [ERROR_AGE_MAXIMUM_AGE_TOO_LARGE] = false,
  [ERROR_AGE_RESTRICTION_NOT_SUPPORTED_BY_DENOMINATION] = false,
  [ERROR_AGE_RESTRICTION_REQUIRED] = false,
  [ERROR_BATCH_AMOUNT_FEE_OVERFLOW] = false,
  [ERROR_BATCH_NONCE_RESUSE] = false,
  [ERROR_CIPHER_MISMATCH] = false,
  [ERROR_DB_FETCH_FAILED] = false,
  [ERROR_DB_INVARIANT_FAILURE] = false,
  [ERROR_DENOMINATION_BATCH_SIGN] = false,
  [ERROR_DENOMINATION_VALIDITY_IN_FUTURE] = false,
  [ERROR_INTERNAL_INVARIANT_FAILURE] = false,
  [ERROR_LEGITIMIZATION_RESULT] = false,
  [ERROR_REQUEST_PARAMETER_MALFORMED] = false,
  [ERROR_RESERVE_SIGNATURE_INVALID] = false,
  [ERROR_RESERVE_UNKNOWN] = false,

  /* These require idempotency checks */
  [ERROR_AGE_INSUFFICIENT_FUNDS] = true,
  [ERROR_BATCH_IDEMPOTENT_PLANCHET] = true,
  [ERROR_BATCH_INSUFFICIENT_FUNDS] = true,
  [ERROR_DENOMINATION_EXPIRED] = true,
  [ERROR_DENOMINATION_KEY_UNKNOWN] = true,
  [ERROR_DENOMINATION_REVOKED] = true,
  [ERROR_KEYS_MISSING] = true,
  [ERROR_KYC_REQUIRED] = true,
};

_Static_assert (
  (sizeof (needs_idempotency_check) ==
   ERROR_MAX),
  "needs_idempotency_check size mismatch with enum WithdrawErrorCode");

/**
 * The following macros set the given error code,
 * set the phase to PHASE_GENERATE_REPLY_ERROR,
 * and optionally set the given field (with an optionally given value).
 */
#define SET_ERROR(wc, ec) \
        do \
        { (wc)->error.code = (ec); \
          (wc)->phase = PHASE_GENERATE_REPLY_ERROR; } while (0)

#define SET_ERROR_WITH_FIELD(wc, ec, field) \
        do \
        { (wc)->error.code = (ec); \
          (wc)->error.details.field = (field); \
          (wc)->phase = PHASE_GENERATE_REPLY_ERROR; } while (0)

#define SET_ERROR_WITH_DETAIL(wc, ec, field, value) \
        do \
        { (wc)->error.code = (ec); \
          (wc)->error.details.field = (value); \
          (wc)->phase = PHASE_GENERATE_REPLY_ERROR; } while (0)


/**
 * All withdraw context is kept in a DLL.
 */
static struct WithdrawContext *wc_head;
static struct WithdrawContext *wc_tail;

void
TEH_withdraw_cleanup ()
{
  struct WithdrawContext *wc;

  while (NULL != (wc = wc_head))
  {
    GNUNET_CONTAINER_DLL_remove (wc_head,
                                 wc_tail,
                                 wc);
    MHD_resume_connection (wc->rc->connection);
  }
}


/**
 * Terminate the main loop by returning the final
 * result.
 *
 * @param[in,out] wc context to update phase for
 * @param mres MHD status to return
 */
static void
finish_loop (struct WithdrawContext *wc,
             MHD_RESULT mres)
{
  wc->phase = (MHD_YES == mres)
    ? PHASE_RETURN_YES
    : PHASE_RETURN_NO;
}


/**
 * Generates our final (successful) response to a batch withdraw request.
 *
 * @param wc operation context
 */
static void
batch_withdraw_phase_generate_reply_success (struct WithdrawContext *wc)
{
  const struct TEH_RequestContext *rc = wc->rc;
  json_t *sigs;

  sigs = json_array ();
  GNUNET_assert (NULL != sigs);
  for (unsigned int i = 0; i<wc->num_coins; i++)
  {
    struct PlanchetContext *pc = &wc->typ.batch.planchets[i];

    GNUNET_assert (
      0 ==
      json_array_append_new (
        sigs,
        GNUNET_JSON_PACK (
          TALER_JSON_pack_blinded_denom_sig (
            "ev_sig",
            &pc->collectable.sig))));
  }
  TEH_METRICS_batch_withdraw_num_coins += wc->num_coins;
  finish_loop (wc,
               TALER_MHD_REPLY_JSON_PACK (
                 rc->connection,
                 MHD_HTTP_OK,
                 GNUNET_JSON_pack_array_steal ("ev_sigs",
                                               sigs)));
}


/**
 * Check if the batch withdraw in @a wc is replayed
 * and we already have an answer.
 * If so, replay the existing answer and return the HTTP response.
 *
 * @param wc parsed request data
 * @return true if the request is idempotent with an existing request
 *    false if we did not find the request in the DB and did not set @a mret
 */
static bool
batch_withdraw_check_idempotency (
  struct WithdrawContext *wc)
{
  GNUNET_assert (wc->withdraw_type == WITHDRAW_TYPE_BATCH);

  for (unsigned int i = 0; i<wc->num_coins; i++)
  {
    struct PlanchetContext *pc = &wc->typ.batch.planchets[i];
    enum GNUNET_DB_QueryStatus qs;
    struct TALER_EXCHANGEDB_CollectableBlindcoin collectable;

    qs = TEH_plugin->get_withdraw_info (
      TEH_plugin->cls,
      &pc->collectable.h_coin_envelope,
      &collectable);
    if (0 > qs)
    {
      /* FIXME: soft error not handled correctly! */
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      SET_ERROR_WITH_DETAIL (wc,
                             ERROR_DB_FETCH_FAILED,
                             db_fetch_context,
                             "get_withdraw_info");
      return true; /* Well, kind-of. */
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      return false;
    pc->collectable = collectable;
  }

  /* generate idempotent reply */
  TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_BATCH_WITHDRAW]++;
  wc->phase = PHASE_GENERATE_REPLY_SUCCESS;
  return true;
}


/**
 * Check if the age-withdraw request is replayed
 * and we already have an answer.
 * If so, replay the existing answer and return the HTTP response.
 *
 * @param[in,out] wc parsed request data
 * @return true if the request is idempotent with an existing request
 *    false if we did not find the request in the DB and did not set @a mret
 */
static bool
age_withdraw_check_idempotency (
  struct WithdrawContext *wc)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_EXCHANGEDB_AgeWithdraw commitment;
  GNUNET_assert (wc->withdraw_type == WITHDRAW_TYPE_AGE);

  qs = TEH_plugin->get_age_withdraw (
    TEH_plugin->cls,
    &wc->typ.age.commitment.reserve_pub,
    &wc->typ.age.commitment.h_commitment,
    &commitment);
  if (0 > qs)
  {
    /* FIXME: soft error not handled correctly! */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      SET_ERROR_WITH_DETAIL (wc,
                             ERROR_DB_FETCH_FAILED,
                             db_fetch_context,
                             "get_age_withdraw");
    return true; /* Well, kind-of. */
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return false;

  /* Generate idempotent reply */
  TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_AGE_WITHDRAW]++;
  wc->phase = PHASE_GENERATE_REPLY_SUCCESS;
  return true;
}


/**
 * Check if the @a wc is replayed and we already have an
 * answer. If so, replay the existing answer and return the
 * HTTP response.
 *
 * @param wc parsed request data
 * @return true if the request is idempotent with an existing request
 *    false if we did not find the request in the DB and did not set @a mret
 */
static bool
check_idempotency (
  struct WithdrawContext *wc)
{
  switch (wc->withdraw_type)
  {
  case WITHDRAW_TYPE_BATCH:
    return batch_withdraw_check_idempotency (wc);
    break;
  case WITHDRAW_TYPE_AGE:
    return age_withdraw_check_idempotency (wc);
    break;
  default:
    GNUNET_break (0);
  }
  return false;
}


/**
 * Function implementing age withdraw transaction.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * @param cls a `struct WithdrawContext *`, with @e withdraw_type == WITHDRAW_TYPE_AGE
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
age_withdraw_transaction (
  void *cls,
  struct MHD_Connection *connection,
  MHD_RESULT *mhd_ret)
{
  struct WithdrawContext *wc = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool found = false;
  bool balance_ok = false;
  bool age_ok = false;
  bool conflict = false;
  uint16_t allowed_maximum_age = 0;
  uint32_t reserve_birthday = 0;
  struct TALER_Amount reserve_balance;

  qs = TEH_plugin->do_age_withdraw (
    TEH_plugin->cls,
    &wc->typ.age.commitment,
    wc->now,
    &found,
    &balance_ok,
    &reserve_balance,
    &age_ok,
    &allowed_maximum_age,
    &reserve_birthday,
    &conflict);
  if (0 > qs)

  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      SET_ERROR_WITH_DETAIL (wc,
                             ERROR_DB_FETCH_FAILED,
                             db_fetch_context,
                             "do_age_withdraw");
    return qs;
  }

  if (! found)
  {
    SET_ERROR (wc,
               ERROR_RESERVE_UNKNOWN);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (! age_ok)
  {
    wc->error.details.age.max = allowed_maximum_age;
    wc->error.details.age.birthday = reserve_birthday;
    SET_ERROR (wc,
               ERROR_AGE_MAXIMUM_AGE_TOO_LARGE);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (! balance_ok)
  {
    TEH_plugin->rollback (TEH_plugin->cls);

    SET_ERROR_WITH_FIELD (wc,
                          ERROR_AGE_INSUFFICIENT_FUNDS,
                          reserve_balance);

    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (conflict)
  {
    /* do_age_withdraw signaled a conflict, so there MUST be an entry
     * in the DB.  Put that into the response */
    if (check_idempotency (wc))
      return GNUNET_DB_STATUS_HARD_ERROR;
    GNUNET_break (0);
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    TEH_METRICS_num_success[TEH_MT_SUCCESS_AGE_WITHDRAW]++;
  return qs;
}


/**
 * Function implementing withdraw transaction.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * Note that "wc->collectable.sig" is set before entering this function as we
 * signed before entering the transaction.
 *
 * @param cls a `struct WithdrawContext *`, with @e withdraw_type set to WITHDRAW_TYPE_BATCH
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
batch_withdraw_transaction (
  void *cls,
  struct MHD_Connection *connection,
  MHD_RESULT *mhd_ret)
{
  struct WithdrawContext *wc = cls;
  uint64_t ruuid;
  enum GNUNET_DB_QueryStatus qs;
  bool found = false;
  bool balance_ok = false;
  bool age_ok = false;
  uint16_t allowed_maximum_age = 0;
  struct TALER_Amount reserve_balance;

  qs = TEH_plugin->do_batch_withdraw (
    TEH_plugin->cls,
    wc->now,
    &wc->reserve_pub,
    &wc->typ.batch.batch_total,
    TEH_age_restriction_enabled,
    &found,
    &balance_ok,
    &reserve_balance,
    &age_ok,
    &allowed_maximum_age,
    &ruuid);

  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      SET_ERROR_WITH_DETAIL (wc,
                             ERROR_DB_FETCH_FAILED,
                             db_fetch_context,
                             "update_reserve_batch_withdraw");
    }
    return qs;
  }

  if (! found)
  {
    GNUNET_break_op (0);
    SET_ERROR (wc,
               ERROR_RESERVE_UNKNOWN);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (! age_ok)
  {
    /* We respond with the lowest age in the corresponding age group
     * of the required age */
    uint16_t lowest_age = TALER_get_lowest_age (
      &TEH_age_restriction_config.mask,
      allowed_maximum_age);
    SET_ERROR_WITH_FIELD (wc,
                          ERROR_AGE_RESTRICTION_REQUIRED,
                          lowest_age);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (! balance_ok)
  {
    GNUNET_break_op (0);
    SET_ERROR_WITH_FIELD (wc,
                          ERROR_BATCH_INSUFFICIENT_FUNDS,
                          reserve_balance);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Add information about each planchet in the batch */
  for (unsigned int i = 0; i<wc->num_coins; i++)
  {
    struct PlanchetContext *pc = &wc->typ.batch.planchets[i];
    const struct TALER_BlindedPlanchet *bp = &pc->blinded_planchet;
    const union GNUNET_CRYPTO_BlindSessionNonce *nonce = NULL;
    bool denom_unknown = true;
    bool conflict = true;
    bool nonce_reuse = true;

    switch (bp->blinded_message->cipher)
    {
    case GNUNET_CRYPTO_BSA_INVALID:
      break;
    case GNUNET_CRYPTO_BSA_RSA:
      break;
    case GNUNET_CRYPTO_BSA_CS:
      nonce = (const union GNUNET_CRYPTO_BlindSessionNonce *)
              &bp->blinded_message->details.cs_blinded_message.nonce;
      break;
    }

    qs = TEH_plugin->do_batch_withdraw_insert (
      TEH_plugin->cls,
      nonce,
      &pc->collectable,
      wc->now,
      ruuid,
      &denom_unknown,
      &conflict,
      &nonce_reuse);

    if (0 > qs)
    {
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
        SET_ERROR_WITH_DETAIL (wc,
                               ERROR_DB_FETCH_FAILED,
                               db_fetch_context,
                               "do_batch_withdraw_insert");
      return qs;
    }

    if (denom_unknown)
    {
      GNUNET_break (0);
      SET_ERROR (wc,
                 ERROR_DB_INVARIANT_FAILURE);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

    if ( (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs) ||
         (conflict) )
    {
      SET_ERROR (wc,
                 ERROR_BATCH_IDEMPOTENT_PLANCHET);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

    if (nonce_reuse)
    {
      GNUNET_break_op (0);
      SET_ERROR (wc,
                 ERROR_BATCH_NONCE_RESUSE);

      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  TEH_METRICS_num_success[TEH_MT_SUCCESS_BATCH_WITHDRAW]++;
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * The request was prepared successfully.
 * Run the main DB transaction.
 *
 * @param wc The context for the current withdraw request
 */
static void
phase_run_transaction (
  struct WithdrawContext *wc)
{
  MHD_RESULT mhd_ret;
  enum GNUNET_GenericReturnValue qs;

  GNUNET_assert (PHASE_RUN_TRANSACTION ==
                 wc->phase);

  switch (wc->withdraw_type)
  {
  case WITHDRAW_TYPE_AGE:
    qs = TEH_DB_run_transaction (wc->rc->connection,
                                 "run age withdraw",
                                 TEH_MT_REQUEST_AGE_WITHDRAW,
                                 &mhd_ret,
                                 &age_withdraw_transaction,
                                 wc);
    break;
  case WITHDRAW_TYPE_BATCH:
    qs = TEH_DB_run_transaction (wc->rc->connection,
                                 "run batch withdraw",
                                 TEH_MT_REQUEST_WITHDRAW,
                                 &mhd_ret,
                                 &batch_withdraw_transaction,
                                 wc);
    break;
  default:
    GNUNET_break (0);
    qs = GNUNET_SYSERR;
  }

  if (GNUNET_OK != qs)
  {
    /* TODO[oec]: Logic still ok with new error handling? */
    if (PHASE_RUN_TRANSACTION ==  wc->phase)
      finish_loop (wc,
                   mhd_ret);
    return;
  }
  wc->phase++;
}


/**
 * The request for batch withdraw was parsed successfully.
 * Prepare our side for the main DB transaction.
 *
 * @param wc context for request processing, with @e withdraw_type set to WITHDRAW_TYPE_BATCH
 * @return GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
batch_withdraw_phase_prepare_transaction (struct WithdrawContext *wc)
{
  struct TALER_BlindedDenominationSignature bss[wc->num_coins];
  struct TEH_CoinSignData csds[wc->num_coins];

  for (unsigned int i = 0; i<wc->num_coins; i++)
  {
    struct PlanchetContext *pc = &wc->typ.batch.planchets[i];
    struct TEH_CoinSignData *csdsi = &csds[i];

    csdsi->h_denom_pub = &pc->collectable.denom_pub_hash;
    csdsi->bp = &pc->blinded_planchet;
  }
  {
    enum TALER_ErrorCode ec;

    ec = TEH_keys_denomination_batch_sign (
      wc->num_coins,
      csds,
      false,
      bss);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      SET_ERROR_WITH_FIELD (wc,
                            ERROR_DENOMINATION_BATCH_SIGN,
                            ec);
      return GNUNET_SYSERR;
    }
  }

  for (unsigned int i = 0; i<wc->num_coins; i++)
  {
    struct PlanchetContext *pc = &wc->typ.batch.planchets[i];

    pc->collectable.sig = bss[i];
  }

  return GNUNET_OK;
}


/**
 * The request for age-withdraw was parsed successfully.
 * Sign and persist the chosen blinded coins for the reveal step.
 *
 * @param wc The context for the current withdraw request, with @e withdraw_type set to WITHDRAW_TYPE_AGE
 * @return GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
age_withdraw_phase_prepare_transaction (
  struct WithdrawContext *wc)
{
  uint8_t noreveal_index;

  wc->typ.age.commitment.denom_sigs
    = GNUNET_new_array (
        wc->num_coins,
        struct TALER_BlindedDenominationSignature);
  wc->typ.age.commitment.h_coin_evs
    = GNUNET_new_array (
        wc->num_coins,
        struct TALER_BlindedCoinHashP);
  /* Pick the challenge */
  noreveal_index =
    GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_STRONG,
                              TALER_CNC_KAPPA);
  wc->typ.age.commitment.noreveal_index = noreveal_index;

  /* Choose and sign the coins */
  {
    struct TEH_CoinSignData csds[wc->num_coins];
    enum TALER_ErrorCode ec;

    /* Pick the chosen blinded coins */
    for (uint32_t i = 0; i<wc->num_coins; i++)
    {
      struct TEH_CoinSignData *csdsi = &csds[i];

      csdsi->bp = &wc->typ.age.planchets[i][noreveal_index];
      csdsi->h_denom_pub = &wc->typ.age.denom_hs[i];
    }

    ec = TEH_keys_denomination_batch_sign (
      wc->num_coins,
      csds,
      false,
      wc->typ.age.commitment.denom_sigs);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      SET_ERROR_WITH_FIELD (wc,
                            ERROR_DENOMINATION_BATCH_SIGN,
                            ec);
      return GNUNET_SYSERR;
    }
  }

  /* Prepare the hashes of the coins for insertion */
  for (uint32_t i = 0; i<wc->num_coins; i++)
  {
    TALER_coin_ev_hash (&wc->typ.age.planchets[i][noreveal_index],
                        &wc->typ.age.denom_hs[i],
                        &wc->typ.age.commitment.h_coin_evs[i]);
  }
  return GNUNET_OK;
}


/**
 * The request for withdraw was parsed successfully.
 * Choose the appropriate preparation step depending on @e withdraw_type
 */
static void
phase_prepare_transaction (
  struct WithdrawContext *wc)
{
  enum GNUNET_GenericReturnValue r;
  switch (wc->withdraw_type)
  {
  case WITHDRAW_TYPE_BATCH:
    r = batch_withdraw_phase_prepare_transaction (wc);
    break;
  case WITHDRAW_TYPE_AGE:
    r = age_withdraw_phase_prepare_transaction (wc);
    break;
  default:
    GNUNET_break (0);
    return;
  }
  if (GNUNET_OK != r)
    return;
  wc->phase++;
}


/**
 * Check the KYC result.
 *
 * @param wc context for request processing
 */
static void
phase_check_kyc_result (struct WithdrawContext *wc)
{
  /* return final positive response */
  if (! wc->kyc.ok)
  {
    SET_ERROR (wc,
               ERROR_KYC_REQUIRED);
    return;
  }
  wc->phase++;
}


/**
 * Function called with the result of a legitimization
 * check.
 *
 * @param cls closure
 * @param lcr legitimization check result
 */
static void
withdraw_legi_cb (
  void *cls,
  const struct TEH_LegitimizationCheckResult *lcr)
{
  struct WithdrawContext *wc = cls;

  wc->lch = NULL;
  GNUNET_assert (PHASE_SUSPENDED ==
                 wc->phase);
  MHD_resume_connection (wc->rc->connection);
  GNUNET_CONTAINER_DLL_remove (wc_head,
                               wc_tail,
                               wc);
  TALER_MHD_daemon_trigger ();
  if (NULL != lcr->response)
  {
    wc->error.details.legi.response = lcr->response;
    wc->error.details.legi.http_status = lcr->http_status;
    SET_ERROR (wc,
               ERROR_LEGITIMIZATION_RESULT);
    return;
  }
  wc->kyc = lcr->kyc;
  wc->phase = PHASE_CHECK_KYC_RESULT;
}


/**
 * Helper function to return a string representing the type of withdraw (age or batch).
 *
 * @param wc withdraw context
 */
static const char *
typ2str (
  const struct WithdrawContext *wc)
{
  switch (wc->withdraw_type)
  {
  case WITHDRAW_TYPE_BATCH:
    return "batch-withdraw";
  case WITHDRAW_TYPE_AGE:
    return "age-withdraw";
  default:
    GNUNET_break (0);
    return "unknown";
  }
}


/**
 * Return the total amount including fees to be withdrawn
 *
 * @param wc withdraw context
 * @return total amount including fees
 */
static struct TALER_Amount *
withdraw_amount_with_fee (
  struct WithdrawContext *wc)
{
  switch (wc->withdraw_type)
  {
  case WITHDRAW_TYPE_BATCH:
    return &wc->typ.batch.batch_total;
  case WITHDRAW_TYPE_AGE:
    return &wc->typ.age.commitment.amount_with_fee;
  default:
    GNUNET_break (0);
    return NULL;
  }
}


/**
 * Function called to iterate over KYC-relevant transaction amounts for a
 * particular time range. Called within a database transaction, so must
 * not start a new one.
 *
 * @param cls closure, identifies the event type and account to iterate
 *        over events for
 * @param limit maximum time-range for which events should be fetched
 *        (timestamp in the past)
 * @param cb function to call on each event found, events must be returned
 *        in reverse chronological order
 * @param cb_cls closure for @a cb, of type struct WithdrawContext
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
withdraw_amount_cb (
  void *cls,
  struct GNUNET_TIME_Absolute limit,
  TALER_EXCHANGEDB_KycAmountCallback cb,
  void *cb_cls)
{
  struct WithdrawContext *wc = cls;
  enum GNUNET_GenericReturnValue ret;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Signaling amount %s for KYC check during %sal\n",
              TALER_amount2s (withdraw_amount_with_fee (wc)),
              typ2str (wc));

  ret = cb (cb_cls,
            withdraw_amount_with_fee (wc),
            wc->now.abs_time);

  GNUNET_break (GNUNET_SYSERR != ret);

  if (GNUNET_OK != ret)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;

  qs = TEH_plugin->select_withdraw_amounts_for_kyc_check (
    TEH_plugin->cls,
    &wc->h_normalized_payto,
    limit,
    cb,
    cb_cls);

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Got %d additional transactions for this %sal and limit %llu\n",
              qs,
              typ2str (wc),
              (unsigned long long) limit.abs_value_us);

  GNUNET_break (qs >= 0);

  return qs;
}


/**
 * Do legitimization check.
 *
 * @param wc operation context
 */
static void
phase_run_legi_check (struct WithdrawContext *wc)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_FullPayto payto_uri;
  struct TALER_FullPaytoHashP h_full_payto;

  /* Check if the money came from a wire transfer */
  qs = TEH_plugin->reserves_get_origin (
    TEH_plugin->cls,
    &wc->reserve_pub,
    &h_full_payto,
    &payto_uri);
  if (qs < 0)
  {
    SET_ERROR_WITH_DETAIL (wc,
                           ERROR_DB_FETCH_FAILED,
                           db_fetch_context,
                           "reserves_get_origin");
    return;
  }
  /* If _no_ results, reserve was created by merge,
     in which case no KYC check is required as the
     merge already did that. */
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    wc->phase = PHASE_PREPARE_TRANSACTION;
    return;
  }
  TALER_full_payto_normalize_and_hash (payto_uri,
                                       &wc->h_normalized_payto);
  wc->lch = TEH_legitimization_check (
    &wc->rc->async_scope_id,
    TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW,
    payto_uri,
    &wc->h_normalized_payto,
    NULL, /* no account pub: this is about the origin account */
    &withdraw_amount_cb,
    wc,
    &withdraw_legi_cb,
    wc);
  GNUNET_assert (NULL != wc->lch);
  GNUNET_free (payto_uri.full_payto);
  GNUNET_CONTAINER_DLL_insert (wc_head,
                               wc_tail,
                               wc);
  MHD_suspend_connection (wc->rc->connection);
  wc->phase = PHASE_SUSPENDED;
}


/**
 * Check if the given denomination is still or already valid, has not been
 * revoked and potentically supports age restriction.
 *
 * @param[in,out] wc context for the withdraw operation
 * @param ksh The handle to the current state of (denomination) keys in the exchange
 * @param denom_h Hash of the denomination key to check
 * @param[out] pdk denomination key found, might be NULL
 * @return GNUNET_OK when denomation was found and valid,
 *              GNUNET_NO when denomination was not valid but request was idempotent,
 *              GNUNET_SYSERR otherwise (denomination invalid), with finish_loop called.
 */
static enum GNUNET_GenericReturnValue
find_denomination (
  struct WithdrawContext *wc,
  struct TEH_KeyStateHandle *ksh,
  const struct TALER_DenominationHashP *denom_h,
  struct TEH_DenominationKey **pdk)
{
  struct TEH_DenominationKey *dk;

  *pdk = NULL;

  dk = TEH_keys_denomination_by_hash_from_state (
    ksh,
    denom_h,
    NULL,
    NULL);

  if (NULL == dk)
  {
    SET_ERROR_WITH_FIELD (wc,
                          ERROR_DENOMINATION_KEY_UNKNOWN,
                          denom_h);
    return GNUNET_NO;
  }

  if (GNUNET_TIME_absolute_is_past (
        dk->meta.expire_withdraw.abs_time))
  {
    SET_ERROR_WITH_FIELD (wc,
                          ERROR_DENOMINATION_EXPIRED,
                          denom_h);
    return GNUNET_SYSERR;
  }

  if (GNUNET_TIME_absolute_is_future (
        dk->meta.start.abs_time))
  {
    GNUNET_break_op (0);
    SET_ERROR_WITH_FIELD (wc,
                          ERROR_DENOMINATION_VALIDITY_IN_FUTURE,
                          denom_h);
    return GNUNET_SYSERR;
  }

  if (dk->recoup_possible)
  {
    SET_ERROR (wc,
               ERROR_DENOMINATION_REVOKED);
    return GNUNET_SYSERR;
  }

  /* In case of age withdraw, make sure that the denomitation supports age restriction */
  if (WITHDRAW_TYPE_AGE == wc->withdraw_type)
  {
    if (0 == dk->denom_pub.age_mask.bits)
    {
      GNUNET_break_op (0);
      SET_ERROR_WITH_FIELD (wc,
                            ERROR_AGE_RESTRICTION_NOT_SUPPORTED_BY_DENOMINATION,
                            denom_h);
      return GNUNET_SYSERR;
    }
  }

  *pdk = dk;
  return GNUNET_OK;
}


/**
 * Check if the given array of hashes of denomination_keys a) belong
 * to valid denominations and b) those are marked as age restricted.
 * Also, calculate the total amount of the denominations including fees
 * for withdraw.
 *
 * @param wc context of the age withdrawal to check keys for
 * @param ksh key state handle
 * @return GNUNET_OK on success,
 *			GNUNET_NO on error (and response being sent)
 */
static enum GNUNET_GenericReturnValue
age_withdraw_phase_check_keys (
  struct WithdrawContext *wc,
  struct TEH_KeyStateHandle *ksh)
{
  unsigned int len = wc->num_coins;
  struct TALER_Amount total_amount;
  struct TALER_Amount total_fee;

  wc->typ.age.commitment.denom_serials
    = GNUNET_new_array (len,
                        uint64_t);
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &total_amount));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &total_fee));

  for (unsigned int i = 0; i < len; i++)
  {
    struct TEH_DenominationKey *dk;
    enum GNUNET_GenericReturnValue r;

    r = find_denomination (wc,
                           ksh,
                           &wc->typ.age.denom_hs[i],
                           &dk);

    if (GNUNET_OK != r)
      return GNUNET_NO;

    /* Ensure the ciphers from the planchets match the denominations' */
    for (uint8_t k = 0; k < TALER_CNC_KAPPA; k++)
    {
      if (dk->denom_pub.bsign_pub_key->cipher !=
          wc->typ.age.planchets[i][k].blinded_message->cipher)
      {
        GNUNET_break_op (0);
        SET_ERROR (wc,
                   ERROR_CIPHER_MISMATCH);
        return GNUNET_NO;
      }
    }

    /* Accumulate the values */
    if (0 > TALER_amount_add (&total_amount,
                              &total_amount,
                              &dk->meta.value))
    {
      GNUNET_break_op (0);
      SET_ERROR_WITH_DETAIL (wc,
                             ERROR_AGE_AMOUNT_OVERFLOW,
                             which,
                             "amount");
      return GNUNET_NO;
    }

    /* Accumulate the withdraw fees */
    if (0 > TALER_amount_add (&total_fee,
                              &total_fee,
                              &dk->meta.fees.withdraw))
    {
      GNUNET_break_op (0);
      SET_ERROR_WITH_DETAIL (wc,
                             ERROR_AGE_AMOUNT_OVERFLOW,
                             which,
                             "fee");
      return GNUNET_NO;
    }
    wc->typ.age.commitment.denom_serials[i] = dk->meta.serial;
  }

  /* Save the total amount including fees */
  GNUNET_assert (0 <
                 TALER_amount_add (
                   &wc->typ.age.commitment.amount_with_fee,
                   &total_amount,
                   &total_fee));

  /* Check that the client signature authorizing the withdrawal is valid. */
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_wallet_age_withdraw_verify (
        &wc->typ.age.commitment.h_commitment,
        &wc->typ.age.commitment.amount_with_fee,
        &TEH_age_restriction_config.mask,
        wc->typ.age.commitment.max_age,
        &wc->typ.age.commitment.reserve_pub,
        &wc->typ.age.commitment.reserve_sig))
  {
    GNUNET_break_op (0);
    SET_ERROR (wc,
               ERROR_RESERVE_SIGNATURE_INVALID);
    return GNUNET_NO;
  }

  return GNUNET_OK;
}


/**
 * Check if the keys in the request are valid for batch withdrawal.
 *
 * @param[in,out] wc context for the batch withdraw request processing
 * @param ksh key state handle
 * @return GNUNET_OK on success,
 *			GNUNET_NO on error (and response being sent)
 */
static enum GNUNET_GenericReturnValue
batch_withdraw_phase_check_keys (
  struct WithdrawContext *wc,
  struct TEH_KeyStateHandle *ksh)
{
  for (unsigned int i = 0; i<wc->num_coins; i++)
  {
    struct PlanchetContext *pc = &wc->typ.batch.planchets[i];
    struct TEH_DenominationKey *dk;
    enum GNUNET_GenericReturnValue r;

    r = find_denomination (wc,
                           ksh,
                           &pc->collectable.denom_pub_hash,
                           &dk);

    if (GNUNET_OK != r)
      return GNUNET_NO;

    GNUNET_assert (NULL != dk);

    if (dk->denom_pub.bsign_pub_key->cipher !=
        pc->blinded_planchet.blinded_message->cipher)
    {
      /* denomination cipher and blinded planchet cipher not the same */
      GNUNET_break_op (0);
      SET_ERROR (wc,
                 ERROR_CIPHER_MISMATCH);
      return GNUNET_NO;
    }

    if (0 >
        TALER_amount_add (&pc->collectable.amount_with_fee,
                          &dk->meta.value,
                          &dk->meta.fees.withdraw))
    {
      GNUNET_break (0);
      SET_ERROR (wc,
                 ERROR_BATCH_AMOUNT_FEE_OVERFLOW);
      return GNUNET_NO;
    }

    if (0 >
        TALER_amount_add (&wc->typ.batch.batch_total,
                          &wc->typ.batch.batch_total,
                          &pc->collectable.amount_with_fee))
    {
      GNUNET_break (0);
      SET_ERROR (wc,
                 ERROR_BATCH_AMOUNT_FEE_OVERFLOW);
      return GNUNET_NO;
    }

    TALER_coin_ev_hash (&pc->blinded_planchet,
                        &pc->collectable.denom_pub_hash,
                        &pc->collectable.h_coin_envelope);

    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
    if (GNUNET_OK !=
        TALER_wallet_withdraw_verify (
          &pc->collectable.denom_pub_hash,
          &pc->collectable.amount_with_fee,
          &pc->collectable.h_coin_envelope,
          &pc->collectable.reserve_pub,
          &pc->collectable.reserve_sig))
    {
      GNUNET_break_op (0);
      SET_ERROR (wc,
                 ERROR_RESERVE_SIGNATURE_INVALID);
      return GNUNET_NO;
    }
  }
  /* everything parsed */

  return GNUNET_OK;
}


/**
 * Check if the keys in the request are valid for withdrawing.
 *
 * @param[in,out] wc context for request processing
 */
static void
phase_check_keys (struct WithdrawContext *wc)
{
  struct TEH_KeyStateHandle *ksh;
  enum GNUNET_GenericReturnValue r;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    GNUNET_break (0);
    SET_ERROR (wc,
               ERROR_KEYS_MISSING);
    return;
  }

  switch (wc->withdraw_type)
  {
  case WITHDRAW_TYPE_BATCH:
    r = batch_withdraw_phase_check_keys (wc, ksh);
    break;
  case WITHDRAW_TYPE_AGE:
    r = age_withdraw_phase_check_keys (wc, ksh);
    break;
  default:
    GNUNET_break (0);
    r = GNUNET_SYSERR;
  }

  switch (r)
  {
  case GNUNET_OK:
    wc->phase++;
    break;
  case GNUNET_NO:
    /* error generated by function, simply return*/
    break;
  case GNUNET_SYSERR:
    GNUNET_break (0);
    SET_ERROR (wc,
               ERROR_KEYS_MISSING);
    break;
  default:
    GNUNET_break (0);
  }
}


/**
 * Check that the client signature authorizing the withdrawal is valid.
 * NOTE: this is only applicable to age-withdraw; the existing
 * batch-withdraw REST-API signs each planchet and they have to be
 * checked during the call to phase_check_keys.
 *
 * @param[in,out] wc request context to check
 */
static void
phase_check_reserve_signature (
  struct WithdrawContext *wc)
{
  switch (wc->withdraw_type)
  {
  case WITHDRAW_TYPE_BATCH:
    /* signature checks has occurred in batch_withdraw_phase_check_keys */
    break;
  case WITHDRAW_TYPE_AGE:
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
    if (GNUNET_OK !=
        TALER_wallet_age_withdraw_verify (
          &wc->typ.age.commitment.h_commitment,
          &wc->typ.age.commitment.amount_with_fee,
          &TEH_age_restriction_config.mask,
          wc->typ.age.commitment.max_age,
          &wc->typ.age.commitment.reserve_pub,
          &wc->typ.age.commitment.reserve_sig))
    {
      GNUNET_break_op (0);
      SET_ERROR (wc,
                 ERROR_RESERVE_SIGNATURE_INVALID);
      return;
    }
    break;
  default:
    GNUNET_break (0);
    return;
  }

  wc->phase++;
}


/**
 * Cleanup routine for withdraw reqwuest.
 * The function is called upon completion of the request
 * that should clean up @a rh_ctx. Can be NULL.
 *
 * @param rc request context to clean up
 */
static void
clean_withdraw_rc (struct TEH_RequestContext *rc)
{
  struct WithdrawContext *wc = rc->rh_ctx;

  if (NULL != wc->lch)
  {
    TEH_legitimization_check_cancel (wc->lch);
    wc->lch = NULL;
  }

  switch (wc->withdraw_type)
  {
  case WITHDRAW_TYPE_BATCH:
    for (unsigned int i = 0; i<wc->num_coins; i++)
    {
      struct PlanchetContext *pc = &wc->typ.batch.planchets[i];

      TALER_blinded_planchet_free (&pc->blinded_planchet);
      TALER_blinded_denom_sig_free (&pc->collectable.sig);
    }
    GNUNET_free (wc->typ.batch.planchets);
    break;

  case WITHDRAW_TYPE_AGE:
    for (unsigned int i = 0; i<wc->num_coins; i++)
    {
      for (unsigned int kappa = 0; kappa<TALER_CNC_KAPPA; kappa++)
      {
        TALER_blinded_planchet_free (&wc->typ.age.planchets[i][kappa]);
      }
    }
    for (unsigned int i = 0; i<wc->num_coins; i++)
    {
      TALER_blinded_denom_sig_free (&wc->typ.age.commitment.denom_sigs[i]);
    }
    GNUNET_free (wc->typ.age.commitment.h_coin_evs);
    GNUNET_free (wc->typ.age.commitment.denom_sigs);
    GNUNET_free (wc->typ.age.denom_hs);
    GNUNET_free (wc->typ.age.planchets);
    GNUNET_free (wc->typ.age.commitment.denom_serials);
    break;

  default:
    GNUNET_break (0);
  }

  if (ERROR_LEGITIMIZATION_RESULT == wc->error.code &&
      NULL != wc->error.details.legi.response)
  {
    MHD_destroy_response (wc->error.details.legi.response);
    wc->error.details.legi.response = NULL;
  }

  GNUNET_free (wc);
}


/**
 * Send a response to a "age-withdraw" request.
 *
 * @param[in,out] wc context for the operation
 */
static void
age_withdraw_phase_generate_reply_success (
  struct WithdrawContext *wc)
{
  struct MHD_Connection *connection
    = wc->rc->connection;
  const struct TALER_AgeWithdrawCommitmentHashP *ach
    = &wc->typ.age.commitment.h_commitment;
  uint32_t noreveal_index
    = wc->typ.age.commitment.noreveal_index;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  enum TALER_ErrorCode ec;

  ec = TALER_exchange_online_age_withdraw_confirmation_sign (
    &TEH_keys_exchange_sign_,
    ach,
    noreveal_index,
    &pub,
    &sig);
  if (TALER_EC_NONE != ec)
  {
    SET_ERROR_WITH_FIELD (wc,
                          ERROR_AGE_CONFIRMATION_SIGN,
                          ec);
    return;
  }

  finish_loop (wc,
               TALER_MHD_REPLY_JSON_PACK (
                 connection,
                 MHD_HTTP_OK,
                 GNUNET_JSON_pack_uint64 ("noreveal_index",
                                          noreveal_index),
                 GNUNET_JSON_pack_data_auto ("exchange_sig",
                                             &sig),
                 GNUNET_JSON_pack_data_auto ("exchange_pub",
                                             &pub)));
}


/**
 * Generates response for the batch- or age-withdraw request.
 *
 * @param wc withdraw operation context
 */
static void
phase_generate_reply_success (struct WithdrawContext *wc)
{
  switch (wc->withdraw_type)
  {
  case WITHDRAW_TYPE_BATCH:
    batch_withdraw_phase_generate_reply_success (wc);
    break;
  case WITHDRAW_TYPE_AGE:
    age_withdraw_phase_generate_reply_success (wc);
    break;
  default:
    GNUNET_break (0);
  }
}


/**
 * Reports an error, potentially with details.
 * That is, it puts a error-type specific repsonse into the MHD queue.
 * It will do a idempotency check first, if needed for the error type.
 *
 * @param wc withdraw context
 */
static void
phase_generate_reply_error (
  struct WithdrawContext *wc)
{
  GNUNET_assert (PHASE_GENERATE_REPLY_ERROR == wc->phase);
  GNUNET_assert (ERROR_NONE != wc->error.code);
  GNUNET_assert (ERROR_MAX != wc->error.code);

  if (needs_idempotency_check[wc->error.code] &&
      check_idempotency (wc))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "request is idempotent\n");
    return;
  }

  switch (wc->error.code)
  {
  case ERROR_MAX:
  case ERROR_NONE:
    {
      GNUNET_break (0);
      wc->phase = PHASE_RETURN_YES;
      return;
    }

  case ERROR_REQUEST_PARAMETER_MALFORMED:
    TALER_MHD_reply_with_error (
      wc->rc->connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      wc->error.details.hint);
    break;

  case ERROR_KEYS_MISSING:
    finish_loop (wc,
                 TALER_MHD_reply_with_error (
                   wc->rc->connection,
                   MHD_HTTP_INTERNAL_SERVER_ERROR,
                   TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                   NULL));
    break;

  case ERROR_DB_FETCH_FAILED:
    finish_loop (wc,
                 TALER_MHD_reply_with_error (
                   wc->rc->connection,
                   MHD_HTTP_INTERNAL_SERVER_ERROR,
                   TALER_EC_GENERIC_DB_FETCH_FAILED,
                   wc->error.details.db_fetch_context));
    break;

  case ERROR_DB_INVARIANT_FAILURE:
    finish_loop (wc,
                 TALER_MHD_reply_with_error (
                   wc->rc->connection,
                   MHD_HTTP_INTERNAL_SERVER_ERROR,
                   TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
                   NULL));
    break;

  case ERROR_INTERNAL_INVARIANT_FAILURE:
    finish_loop (wc,
                 TALER_MHD_reply_with_error (
                   wc->rc->connection,
                   MHD_HTTP_INTERNAL_SERVER_ERROR,
                   TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                   NULL));
    break;

  case ERROR_RESERVE_UNKNOWN:
    finish_loop (wc,
                 TALER_MHD_reply_with_ec (
                   wc->rc->connection,
                   TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                   NULL));
    break;

  case ERROR_DENOMINATION_BATCH_SIGN:
    finish_loop (wc,
                 TALER_MHD_reply_with_ec (
                   wc->rc->connection,
                   wc->error.details.ec,
                   NULL));
    break;

  case ERROR_KYC_REQUIRED:
    finish_loop (wc,
                 TEH_RESPONSE_reply_kyc_required (
                   wc->rc->connection,
                   &wc->h_normalized_payto,
                   &wc->kyc,
                   false));
    break;

  case ERROR_DENOMINATION_KEY_UNKNOWN:
    {
      GNUNET_break_op (0);
      finish_loop (wc,
                   TEH_RESPONSE_reply_unknown_denom_pub_hash (
                     wc->rc->connection,
                     wc->error.details.denom_h));
      break;
    }

  case ERROR_DENOMINATION_EXPIRED:
    GNUNET_break_op (0);
    finish_loop (wc,
                 TEH_RESPONSE_reply_expired_denom_pub_hash (
                   wc->rc->connection,
                   wc->error.details.denom_h,
                   TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
                   typ2str (wc)));
    break;

  case ERROR_DENOMINATION_VALIDITY_IN_FUTURE:
    finish_loop (wc,
                 TEH_RESPONSE_reply_expired_denom_pub_hash (
                   wc->rc->connection,
                   wc->error.details.denom_h,
                   TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
                   typ2str (wc)));
    break;

  case ERROR_DENOMINATION_REVOKED:
    GNUNET_break_op (0);
    finish_loop (wc,
                 TALER_MHD_reply_with_ec (
                   wc->rc->connection,
                   TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
                   typ2str (wc)));
    break;

  case ERROR_CIPHER_MISMATCH:
    finish_loop (wc,
                 TALER_MHD_reply_with_ec (
                   wc->rc->connection,
                   TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                   NULL));
    break;

  case ERROR_AGE_RESTRICTION_NOT_SUPPORTED_BY_DENOMINATION:
    {
      char msg[256];
      GNUNET_snprintf (msg,
                       sizeof(msg),
                       "denomination %s does not support age restriction",
                       GNUNET_h2s (&wc->error.details.denom_h->hash));
      finish_loop (wc,
                   TALER_MHD_reply_with_ec (
                     wc->rc->connection,
                     TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN,
                     msg));
      break;
    }

  case ERROR_AGE_MAXIMUM_AGE_TOO_LARGE:
    finish_loop (wc,
                 TALER_MHD_REPLY_JSON_PACK (
                   wc->rc->connection,
                   MHD_HTTP_CONFLICT,
                   TALER_MHD_PACK_EC (
                     TALER_EC_EXCHANGE_AGE_WITHDRAW_MAXIMUM_AGE_TOO_LARGE),
                   GNUNET_JSON_pack_uint64 (
                     "allowed_maximum_age",
                     wc->error.details.age.max),
                   GNUNET_JSON_pack_uint64 (
                     "reserve_birthday",
                     wc->error.details.age.birthday)));
    break;

  case ERROR_AGE_RESTRICTION_REQUIRED:
    finish_loop (wc,
                 TEH_RESPONSE_reply_reserve_age_restriction_required (
                   wc->rc->connection,
                   wc->error.details.lowest_age));
    break;

  case ERROR_AGE_INSUFFICIENT_FUNDS:
    finish_loop (wc,
                 TEH_RESPONSE_reply_reserve_insufficient_balance (
                   wc->rc->connection,
                   TALER_EC_EXCHANGE_AGE_WITHDRAW_INSUFFICIENT_FUNDS,
                   &wc->error.details.reserve_balance,
                   &wc->typ.age.commitment.amount_with_fee,
                   &wc->reserve_pub));
    break;

  case ERROR_AGE_AMOUNT_OVERFLOW:
    finish_loop (wc,
                 TALER_MHD_reply_with_error (
                   wc->rc->connection,
                   MHD_HTTP_BAD_REQUEST,
                   TALER_EC_EXCHANGE_AGE_WITHDRAW_AMOUNT_OVERFLOW,
                   wc->error.details.which));
    break;

  case ERROR_AGE_CONFIRMATION_SIGN:
    finish_loop (wc,
                 TALER_MHD_reply_with_ec (
                   wc->rc->connection,
                   wc->error.details.ec,
                   NULL));
    break;

  case ERROR_BATCH_INSUFFICIENT_FUNDS:
    finish_loop (wc,
                 TEH_RESPONSE_reply_reserve_insufficient_balance (
                   wc->rc->connection,
                   TALER_EC_EXCHANGE_WITHDRAW_INSUFFICIENT_FUNDS,
                   &wc->error.details.reserve_balance,
                   &wc->typ.batch.batch_total,
                   &wc->reserve_pub));
    break;

  case ERROR_BATCH_IDEMPOTENT_PLANCHET:
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Idempotent coin in batch, not allowed. Aborting.\n");
      finish_loop (wc,
                   TALER_MHD_reply_with_error (
                     wc->rc->connection,
                     MHD_HTTP_CONFLICT,
                     TALER_EC_EXCHANGE_WITHDRAW_BATCH_IDEMPOTENT_PLANCHET,
                     NULL));
      break;
    }

  case ERROR_BATCH_NONCE_RESUSE:
    finish_loop (wc,
                 TALER_MHD_reply_with_error (
                   wc->rc->connection,
                   MHD_HTTP_BAD_REQUEST,
                   TALER_EC_EXCHANGE_WITHDRAW_NONCE_REUSE,
                   NULL));
    break;

  case ERROR_BATCH_AMOUNT_FEE_OVERFLOW:
    finish_loop (wc,
                 TALER_MHD_reply_with_error (
                   wc->rc->connection,
                   MHD_HTTP_INTERNAL_SERVER_ERROR,
                   TALER_EC_EXCHANGE_WITHDRAW_AMOUNT_FEE_OVERFLOW,
                   NULL));
    break;

  case ERROR_RESERVE_SIGNATURE_INVALID:
    finish_loop (wc,
                 TALER_MHD_reply_with_ec (
                   wc->rc->connection,
                   TALER_EC_EXCHANGE_WITHDRAW_RESERVE_SIGNATURE_INVALID,
                   NULL));
    break;

  case ERROR_LEGITIMIZATION_RESULT: {
      finish_loop (wc,
                   MHD_queue_response (wc->rc->connection,
                                       wc->error.details.legi.http_status,
                                       wc->error.details.legi.response));
      break;
    }
  }
}


/**
 * Creates a new context for the incoming batch-withdraw request
 *
 * @param[in,out] wc context of the batch-witrhdraw, to be filled
 * @param root json body of the request
 * @return GNUNET_OK on success, GNUNET_SYSERR otherwise (response sent)
 */
static enum GNUNET_GenericReturnValue
batch_withdraw_new_request (
  struct WithdrawContext *wc,
  const json_t *root)
{
  const json_t *planchets;

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &wc->typ.batch.batch_total));

  {
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_array_const ("planchets",
                                    &planchets),
      GNUNET_JSON_spec_end ()
    };

    {
      enum GNUNET_GenericReturnValue res;

      res = TALER_MHD_parse_json_data (wc->rc->connection,
                                       root,
                                       spec);
      if (GNUNET_OK != res)
        return res;
    }
  }

  wc->num_coins = json_array_size (planchets);
  if (0 == wc->num_coins)
  {
    GNUNET_break_op (0);
    SET_ERROR_WITH_DETAIL (wc,
                           ERROR_REQUEST_PARAMETER_MALFORMED,
                           hint,
                           "planchets");
    return GNUNET_SYSERR;
  }

  if (wc->num_coins > TALER_MAX_FRESH_COINS)
  {
    GNUNET_break_op (0);
    SET_ERROR_WITH_DETAIL (wc,
                           ERROR_REQUEST_PARAMETER_MALFORMED,
                           hint,
                           "too many planchets");
    return GNUNET_SYSERR;
  }

  wc->typ.batch.planchets
    = GNUNET_new_array (wc->num_coins,
                        struct PlanchetContext);

  for (unsigned int i = 0; i<wc->num_coins; i++)
  {
    struct PlanchetContext *pc = &wc->typ.batch.planchets[i];
    struct GNUNET_JSON_Specification ispec[] = {
      GNUNET_JSON_spec_fixed_auto (
        "reserve_sig",
        &pc->collectable.reserve_sig),
      GNUNET_JSON_spec_fixed_auto (
        "denom_pub_hash",
        &pc->collectable.denom_pub_hash),
      TALER_JSON_spec_blinded_planchet (
        "coin_ev",
        &pc->blinded_planchet),
      GNUNET_JSON_spec_end ()
    };

    {
      enum GNUNET_GenericReturnValue res;

      res = TALER_MHD_parse_json_data (
        wc->rc->connection,
        json_array_get (planchets, i),
        ispec);
      if (GNUNET_OK != res)
        return res;
    }

    pc->collectable.reserve_pub = wc->reserve_pub;
    for (unsigned int k = 0; k<i; k++)
    {
      const struct PlanchetContext *kpc = &wc->typ.batch.planchets[k];

      if (0 ==
          TALER_blinded_planchet_cmp (
            &kpc->blinded_planchet,
            &pc->blinded_planchet))
      {
        GNUNET_break_op (0);
        SET_ERROR_WITH_DETAIL (wc,
                               ERROR_REQUEST_PARAMETER_MALFORMED,
                               hint,
                               "duplicate planchet");
        return GNUNET_SYSERR;
      }
    }
  }
  return GNUNET_OK;
}


/**
 * Creates a new context for the incoming age-withdraw request
 *
 * @param wc withdraw request context
 * @param root json body of the request
 * @return GNUNET_OK on success, GNUNET_SYSERR otherwise (response sent)
 */
static enum GNUNET_GenericReturnValue
age_withdraw_new_request (
  struct WithdrawContext *wc,
  const json_t *root)
{

  wc->typ.age.commitment.reserve_pub = wc->reserve_pub;

  /* parse the json body */
  {
    const json_t *j_denom_hs;
    const json_t *j_blinded_planchets;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_array_const ("denom_hs",
                                    &j_denom_hs),
      GNUNET_JSON_spec_array_const ("blinded_planchets",
                                    &j_blinded_planchets),
      GNUNET_JSON_spec_uint16 ("max_age",
                               &wc->typ.age.commitment.max_age),
      GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                   &wc->typ.age.commitment.reserve_sig),
      GNUNET_JSON_spec_end ()
    };
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (wc->rc->connection,
                                     root,
                                     spec);
    if (GNUNET_OK != res)
      return res;

    /* The age value MUST be on the beginning of an age group */
    if (wc->typ.age.commitment.max_age !=
        TALER_get_lowest_age (&TEH_age_restriction_config.mask,
                              wc->typ.age.commitment.max_age))
    {
      GNUNET_break_op (0);
      SET_ERROR_WITH_DETAIL (
        wc,
        ERROR_REQUEST_PARAMETER_MALFORMED,
        hint,
        "max_age must be the lower edge of an age group");
      return GNUNET_SYSERR;
    }

    /* validate array size */
    {
      size_t num_coins = json_array_size (j_denom_hs);
      const char *error = NULL;

      _Static_assert ((TALER_MAX_FRESH_COINS < INT_MAX / TALER_CNC_KAPPA),
                      "TALER_MAX_FRESH_COINS too large");
      if (0 == num_coins)
        error = "denoms_h must not be empty";
      else if (num_coins != json_array_size (j_blinded_planchets))
        error = "denoms_h and coins_evs must be arrays of the same size";
      else if (num_coins > TALER_MAX_FRESH_COINS)
        /**
         * The wallet had committed to more than the maximum coins allowed, the
         * reserve has been charged, but now the user can not withdraw any money
         * from it.  Note that the user can't get their money back in this case!
         */
        error =
          "maximum number of coins that can be withdrawn has been exceeded";

      if (NULL != error)
      {
        GNUNET_break_op (0);
        SET_ERROR_WITH_DETAIL (wc,
                               ERROR_REQUEST_PARAMETER_MALFORMED,
                               hint,
                               error);
        return GNUNET_SYSERR;
      }
      wc->num_coins = (unsigned int) num_coins;
      wc->typ.age.commitment.num_coins = (unsigned int) num_coins;
    }

    wc->typ.age.denom_hs
      = GNUNET_new_array (wc->num_coins,
                          struct TALER_DenominationHashP);
    {
      size_t idx;
      json_t *value;

      json_array_foreach (j_denom_hs, idx, value) {
        struct GNUNET_JSON_Specification ispec[] = {
          GNUNET_JSON_spec_fixed_auto (NULL,
                                       &wc->typ.age.denom_hs[idx]),
          GNUNET_JSON_spec_end ()
        };

        res = TALER_MHD_parse_json_data (wc->rc->connection,
                                         value,
                                         ispec);
        if (GNUNET_OK != res)
          return res;
      }
    }

    {
      typedef struct TALER_BlindedPlanchet
        _array_of_kappa_planchets[TALER_CNC_KAPPA];

      wc->typ.age.planchets = GNUNET_new_array (wc->num_coins,
                                                _array_of_kappa_planchets);
    }

    /* calculate the hash over the data */
    {
      struct GNUNET_HashContext *hash_context;

      hash_context = GNUNET_CRYPTO_hash_context_start ();
      GNUNET_assert (NULL != hash_context);

      /* Parse blinded envelopes. */
      {
        json_t *j_kappa_planchets;
        size_t idx;

        json_array_foreach (j_blinded_planchets, idx, j_kappa_planchets) {
          if (! json_is_array (j_kappa_planchets))
          {
            GNUNET_break_op (0);
            SET_ERROR_WITH_DETAIL (wc,
                                   ERROR_REQUEST_PARAMETER_MALFORMED,
                                   hint,
                                   "all entries in array blinded_planchets must be arrays");
            return GNUNET_SYSERR;
          }
          if (TALER_CNC_KAPPA != json_array_size (j_kappa_planchets))
          {
            GNUNET_break_op (0);
            SET_ERROR_WITH_DETAIL (wc,
                                   ERROR_REQUEST_PARAMETER_MALFORMED,
                                   hint,
                                   "all entries in array blinded_planchets must be arrays of size "
                                   TALER_CNC_KAPPA_STR);
            return GNUNET_SYSERR;
          }

          /* Now parse the individual kappa envelopes and calculate the hash of
           * the commitment along the way. */
          {
            size_t kappa;
            json_t *kvalue;

            json_array_foreach (j_kappa_planchets, kappa, kvalue) {
              struct GNUNET_JSON_Specification kspec[] = {
                TALER_JSON_spec_blinded_planchet (NULL,
                                                  &wc->typ.age.planchets[idx][
                                                    kappa]),
                GNUNET_JSON_spec_end ()
              };

              res = TALER_MHD_parse_json_data (wc->rc->connection,
                                               kvalue,
                                               kspec);
              if (GNUNET_OK != res)
                return res;

              /* Continue to hash of the coin candidates */
              {
                struct TALER_BlindedCoinHashP bch;

                TALER_coin_ev_hash (&wc->typ.age.planchets[idx][kappa],
                                    &wc->typ.age.denom_hs[idx],
                                    &bch);
                GNUNET_CRYPTO_hash_context_read (hash_context,
                                                 &bch,
                                                 sizeof(bch));
              }

              /* Check for duplicate planchets. Technically a bug on
               * the client side that is harmless for us, but still
               * not allowed per protocol */
              for (unsigned int i = 0; i < idx; i++)
              {
                if (0 ==
                    TALER_blinded_planchet_cmp (
                      &wc->typ.age.planchets[idx][kappa],
                      &wc->typ.age.planchets[i][kappa]))
                {
                  GNUNET_break_op (0);
                  SET_ERROR_WITH_DETAIL (wc,
                                         ERROR_REQUEST_PARAMETER_MALFORMED,
                                         hint,
                                         "duplicate planchet");
                  return GNUNET_SYSERR;
                }
              }   /* end duplicate check */
            }   /* json_array_foreach over j_kappa_planchets */
          }   /* scope of kappa/kvalue */
        }   /* json_array_foreach over j_blinded_planchets */
      }   /* scope of j_kappa_planchets, idx */

      /* Finally, calculate the h_commitment from all blinded envelopes */
      GNUNET_CRYPTO_hash_context_finish (hash_context,
                                         &wc->typ.age.commitment.h_commitment.
                                         hash);

    }   /* scope of hash_context */
  }   /* scope of j_denom_hs, j_blinded_planchets */

  return GNUNET_OK;
}


/**
 * Handle a "/reserves/$RESERVE_PUB/{age,batch}-withdraw" request.
 *
 * @param rc request context
 * @param typ withdraw type
 * @param root uploaded JSON data
 * @param reserve_pub public key of the reserve
 * @return MHD result code
 */
static MHD_RESULT
handler_withdraw (
  struct TEH_RequestContext *rc,
  enum WithdrawType typ,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root)
{
  struct WithdrawContext *wc = rc->rh_ctx;
  enum GNUNET_GenericReturnValue r;

  if (NULL == wc)
  {
    wc = GNUNET_new (struct WithdrawContext);
    rc->rh_ctx = wc;
    rc->rh_cleaner = &clean_withdraw_rc;
    wc->rc = rc;
    wc->now = GNUNET_TIME_timestamp_get ();
    wc->withdraw_type = typ;
    wc->reserve_pub = *reserve_pub;

    switch (typ)
    {
    case WITHDRAW_TYPE_BATCH:
      r = batch_withdraw_new_request (wc, root);
      break;
    case WITHDRAW_TYPE_AGE:
      r = age_withdraw_new_request (wc, root);
      break;
    default:
      GNUNET_break (0);
      r = GNUNET_SYSERR;
      /* TODO: find better error code here:? */
      SET_ERROR (wc,
                 ERROR_INTERNAL_INVARIANT_FAILURE);
    }

    if (GNUNET_OK != r)
      return (GNUNET_SYSERR == r) ? MHD_NO : MHD_YES;

    wc->phase = PHASE_CHECK_KEYS;
  }

  while (true)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "%s processing in phase %d\n",
                typ2str (wc),
                wc->phase);

    switch (wc->phase)
    {
    case PHASE_CHECK_KEYS:
      phase_check_keys (wc);
      break;
    case PHASE_CHECK_RESERVE_SIGNATURE:
      phase_check_reserve_signature (wc);
      break;
    case PHASE_RUN_LEGI_CHECK:
      phase_run_legi_check (wc);
      break;
    case PHASE_SUSPENDED:
      return MHD_YES;
    case PHASE_CHECK_KYC_RESULT:
      phase_check_kyc_result (wc);
      break;
    case PHASE_PREPARE_TRANSACTION:
      phase_prepare_transaction (wc);
      break;
    case PHASE_RUN_TRANSACTION:
      phase_run_transaction (wc);
      break;
    case PHASE_GENERATE_REPLY_SUCCESS:
      phase_generate_reply_success (wc);
      break;
    case PHASE_GENERATE_REPLY_ERROR:
      phase_generate_reply_error (wc);
      break;
    case PHASE_RETURN_YES:
      return MHD_YES;
    case PHASE_RETURN_NO:
      return MHD_NO;
    }
  }
}


MHD_RESULT
TEH_handler_batch_withdraw (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root)
{
  return handler_withdraw (rc,
                           WITHDRAW_TYPE_BATCH,
                           reserve_pub,
                           root);
}


MHD_RESULT
TEH_handler_age_withdraw (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root)
{
  return handler_withdraw (rc,
                           WITHDRAW_TYPE_AGE,
                           reserve_pub,
                           root);
}


/* end of taler-exchange-httpd_withdraw.c */
