/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_refund.c
 * @brief Handle refund requests; parses the POST and JSON and
 *        verifies the coin signature before handing things off
 *        to the database.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_refund.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Generate successful refund confirmation message.
 *
 * @param connection connection to the client
 * @param coin_pub public key of the coin
 * @param refund details about the successful refund
 * @return MHD result code
 */
static MHD_RESULT
reply_refund_success (struct MHD_Connection *connection,
                      const struct TALER_CoinSpendPublicKeyP *coin_pub,
                      const struct TALER_EXCHANGEDB_RefundListEntry *refund)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  struct TALER_RefundConfirmationPS rc = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND),
    .purpose.size = htonl (sizeof (rc)),
    .h_contract_terms = refund->h_contract_terms,
    .coin_pub = *coin_pub,
    .merchant = refund->merchant_pub,
    .rtransaction_id = GNUNET_htonll (refund->rtransaction_id)
  };
  enum TALER_ErrorCode ec;

  TALER_amount_hton (&rc.refund_amount,
                     &refund->refund_amount);
  if (TALER_EC_NONE !=
      (ec = TEH_keys_exchange_sign (&rc,
                                    &pub,
                                    &sig)))
  {
    return TALER_MHD_reply_with_ec (connection,
                                    ec,
                                    NULL);
  }
  return TALER_MHD_reply_json_pack (
    connection,
    MHD_HTTP_OK,
    "{s:o, s:o}",
    "exchange_sig", GNUNET_JSON_from_data_auto (&sig),
    "exchange_pub", GNUNET_JSON_from_data_auto (&pub));
}


/**
 * Execute a "/refund" transaction.  Returns a confirmation that the
 * refund was successful, or a failure if we are not aware of a
 * matching /deposit or if it is too late to do the refund.
 *
 * IF it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls closure with a `const struct TALER_EXCHANGEDB_Refund *`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
refund_transaction (void *cls,
                    struct MHD_Connection *connection,
                    struct TALER_EXCHANGEDB_Session *session,
                    MHD_RESULT *mhd_ret)
{
  const struct TALER_EXCHANGEDB_Refund *refund = cls;
  struct TALER_EXCHANGEDB_TransactionList *tl; /* head of original list */
  struct TALER_EXCHANGEDB_TransactionList *tlx; /* head of sublist that applies to merchant and contract */
  struct TALER_EXCHANGEDB_TransactionList *tln; /* next element, during iteration */
  struct TALER_EXCHANGEDB_TransactionList *tlp; /* previous element in 'tl' list, during iteration */
  enum GNUNET_DB_QueryStatus qs;
  bool deposit_found; /* deposit_total initialized? */
  bool refund_found; /* refund_total initialized? */
  struct TALER_Amount deposit_total;
  struct TALER_Amount refund_total;

  tl = NULL;
  qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                          session,
                                          &refund->coin.coin_pub,
                                          GNUNET_NO,
                                          &tl);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "coin transactions");
    return qs;
  }
  deposit_found = false;
  refund_found = false;
  tlx = NULL; /* relevant subset of transactions */
  tln = NULL;
  tlp = NULL;
  for (struct TALER_EXCHANGEDB_TransactionList *tli = tl;
       NULL != tli;
       tli = tln)
  {
    tln = tli->next;
    switch (tli->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      {
        const struct TALER_EXCHANGEDB_DepositListEntry *dep;

        dep = tli->details.deposit;
        if ( (0 == GNUNET_memcmp (&dep->merchant_pub,
                                  &refund->details.merchant_pub)) &&
             (0 == GNUNET_memcmp (&dep->h_contract_terms,
                                  &refund->details.h_contract_terms)) )
        {
          /* check if we already send the money for this /deposit */
          if (dep->done)
          {
            TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                                    tlx);
            TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                                    tln);
            /* money was already transferred to merchant, can no longer refund */
            *mhd_ret = TALER_MHD_reply_with_error (connection,
                                                   MHD_HTTP_GONE,
                                                   TALER_EC_EXCHANGE_REFUND_MERCHANT_ALREADY_PAID,
                                                   NULL);
            return GNUNET_DB_STATUS_HARD_ERROR;
          }

          /* deposit applies and was not yet wired; add to total (it is NOT
             the case that multiple deposits of the same coin for the same
             contract are really allowed (see UNIQUE constraint on 'deposits'
             table), but in case this changes we tolerate it with this code
             anyway). *///
          if (deposit_found)
          {
            GNUNET_assert (0 <=
                           TALER_amount_add (&deposit_total,
                                             &deposit_total,
                                             &dep->amount_with_fee));
          }
          else
          {
            deposit_total = dep->amount_with_fee;
            deposit_found = true;
          }
          /* move 'tli' from 'tl' to 'tlx' list */
          if (NULL == tlp)
            tl = tln;
          else
            tlp->next = tln;
          tli->next = tlx;
          tlx = tli;
          break;
        }
        else
        {
          tlp = tli;
        }
        break;
      }
    case TALER_EXCHANGEDB_TT_MELT:
      /* Melts cannot be refunded, ignore here */
      break;
    case TALER_EXCHANGEDB_TT_REFUND:
      {
        const struct TALER_EXCHANGEDB_RefundListEntry *ref;

        ref = tli->details.refund;
        if ( (0 != GNUNET_memcmp (&ref->merchant_pub,
                                  &refund->details.merchant_pub)) ||
             (0 != GNUNET_memcmp (&ref->h_contract_terms,
                                  &refund->details.h_contract_terms)) )
        {
          tlp = tli;
          break; /* refund does not apply to our transaction */
        }
        /* Check if existing refund request matches in everything but the amount */
        if ( (ref->rtransaction_id ==
              refund->details.rtransaction_id) &&
             (0 != TALER_amount_cmp (&ref->refund_amount,
                                     &refund->details.refund_amount)) )
        {
          /* Generate precondition failed response, with ONLY the conflicting entry */
          TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                                  tlx);
          TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                                  tln);
          tli->next = NULL;
          *mhd_ret = TALER_MHD_reply_json_pack (
            connection,
            MHD_HTTP_PRECONDITION_FAILED,
            "{s:o, s:s, s:I, s:o}",
            "detail",
            TALER_JSON_from_amount (&ref->refund_amount),
            "hint", TALER_ErrorCode_get_hint (
              TALER_EC_EXCHANGE_REFUND_INCONSISTENT_AMOUNT),
            "code", (json_int_t) TALER_EC_EXCHANGE_REFUND_INCONSISTENT_AMOUNT,
            "history", TEH_RESPONSE_compile_transaction_history (
              &refund->coin.coin_pub,
              tli));
          TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                                  tli);
          return GNUNET_DB_STATUS_HARD_ERROR;
        }
        /* Check if existing refund request matches in everything including the amount */
        if ( (ref->rtransaction_id ==
              refund->details.rtransaction_id) &&
             (0 == TALER_amount_cmp (&ref->refund_amount,
                                     &refund->details.refund_amount)) )
        {
          /* we can blanketly approve, as this request is identical to one
             we saw before */
          *mhd_ret = reply_refund_success (connection,
                                           &refund->coin.coin_pub,
                                           ref);
          TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                                  tlx);
          TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                                  tl);
          /* we still abort the transaction, as there is nothing to be
             committed! */
          return GNUNET_DB_STATUS_HARD_ERROR;
        }

        /* We have another refund, that relates, add to total */
        if (refund_found)
        {
          GNUNET_assert (0 <=
                         TALER_amount_add (&refund_total,
                                           &refund_total,
                                           &ref->refund_amount));
        }
        else
        {
          refund_total = ref->refund_amount;
          refund_found = true;
        }
        /* move 'tli' from 'tl' to 'tlx' list */
        if (NULL == tlp)
          tl = tln;
        else
          tlp->next = tln;
        tli->next = tlx;
        tlx = tli;
        break;
      }
    case TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP:
      /* Recoups cannot be refunded, ignore here */
      break;
    case TALER_EXCHANGEDB_TT_RECOUP:
      /* Recoups cannot be refunded, ignore here */
      break;
    case TALER_EXCHANGEDB_TT_RECOUP_REFRESH:
      /* Recoups cannot be refunded, ignore here */
      break;
    }
  }
  /* no need for 'tl' anymore, everything we may still care about is in tlx now */
  TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                          tl);
  /* handle if deposit was NOT found */
  if (! deposit_found)
  {
    TALER_LOG_WARNING ("Deposit to /refund was not found\n");
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tlx);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_REFUND_DEPOSIT_NOT_FOUND,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* check currency is compatible */
  if (GNUNET_YES !=
      TALER_amount_cmp_currency (&refund->details.refund_amount,
                                 &deposit_total))
  {
    GNUNET_break_op (0); /* currency mismatch */
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tlx);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_CURRENCY_MISMATCH,
                                           deposit_total.currency);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* check total refund amount is sufficiently low */
  if (refund_found)
    GNUNET_break (0 <=
                  TALER_amount_add (&refund_total,
                                    &refund_total,
                                    &refund->details.refund_amount));
  else
    refund_total = refund->details.refund_amount;

  if (1 == TALER_amount_cmp (&refund_total,
                             &deposit_total) )
  {
    *mhd_ret = TALER_MHD_reply_json_pack (
      connection,
      MHD_HTTP_CONFLICT,
      "{s:s, s:s, s:I, s:o}",
      "detail",
      "total amount refunded exceeds total amount deposited for this coin",
      "hint",
      TALER_ErrorCode_get_hint (
        TALER_EC_EXCHANGE_REFUND_CONFLICT_DEPOSIT_INSUFFICIENT),
      "code",
      (json_int_t) TALER_EC_EXCHANGE_REFUND_CONFLICT_DEPOSIT_INSUFFICIENT,
      "history",
      TEH_RESPONSE_compile_transaction_history (&refund->coin.coin_pub,
                                                tlx));
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tlx);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                          tlx);


  /* Finally, store new refund data */
  qs = TEH_plugin->insert_refund (TEH_plugin->cls,
                                  session,
                                  refund);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    TALER_LOG_WARNING ("Failed to store /refund information in database\n");
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "refund");
    return qs;
  }
  /* Success or soft failure */
  return qs;
}


/**
 * We have parsed the JSON information about the refund, do some basic
 * sanity checks (especially that the signature on the coin is valid)
 * and then execute the refund.  Note that we need the DB to check
 * the fee structure, so this is not done here.
 *
 * @param connection the MHD connection to handle
 * @param[in,out] refund information about the refund
 * @return MHD result code
 */
static MHD_RESULT
verify_and_execute_refund (struct MHD_Connection *connection,
                           struct TALER_EXCHANGEDB_Refund *refund)
{
  struct GNUNET_HashCode denom_hash;

  {
    struct TALER_RefundRequestPS rr = {
      .purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND),
      .purpose.size = htonl (sizeof (rr)),
      .h_contract_terms = refund->details.h_contract_terms,
      .coin_pub = refund->coin.coin_pub,
      .merchant = refund->details.merchant_pub,
      .rtransaction_id = GNUNET_htonll (refund->details.rtransaction_id)
    };

    TALER_amount_hton (&rr.refund_amount,
                       &refund->details.refund_amount);
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                    &rr,
                                    &refund->details.merchant_sig.eddsa_sig,
                                    &refund->details.merchant_pub.eddsa_pub))
    {
      TALER_LOG_WARNING ("Invalid signature on refund request\n");
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_EXCHANGE_REFUND_MERCHANT_SIGNATURE_INVALID,
                                         NULL);
    }
  }

  /* Fetch the coin's denomination (hash) */
  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->get_coin_denomination (TEH_plugin->cls,
                                            NULL,
                                            &refund->coin.coin_pub,
                                            &denom_hash);
    if (0 > qs)
    {
      MHD_RESULT res;
      char *dhs;

      GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
      dhs = GNUNET_STRINGS_data_to_string_alloc (&denom_hash,
                                                 sizeof (denom_hash));
      res = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_NOT_FOUND,
                                        TALER_EC_EXCHANGE_REFUND_COIN_NOT_FOUND,
                                        dhs);
      GNUNET_free (dhs);
      return res;
    }
  }

  {
    /* Obtain information about the coin's denomination! */
    struct TEH_DenominationKey *dk;
    unsigned int hc;
    enum TALER_ErrorCode ec;

    dk = TEH_keys_denomination_by_hash (&denom_hash,
                                        &ec,
                                        &hc);
    if (NULL == dk)
    {
      /* DKI not found, but we do have a coin with this DK in our database;
         not good... */
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (connection,
                                         hc,
                                         ec,
                                         NULL);
    }

    if (GNUNET_TIME_absolute_get ().abs_value_us >=
        dk->meta.expire_deposit.abs_value_us)
    {
      /* This denomination is past the expiration time for deposits, and thus refunds */
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_GONE,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
        NULL);
    }
    refund->details.refund_fee = dk->meta.fee_refund;
  }

  /* Finally run the actual transaction logic */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "run refund",
                                &mhd_ret,
                                &refund_transaction,
                                (void *) refund))
    {
      return mhd_ret;
    }
  }
  return reply_refund_success (connection,
                               &refund->coin.coin_pub,
                               &refund->details);
}


/**
 * Handle a "/coins/$COIN_PUB/refund" request.  Parses the JSON, and, if
 * successful, passes the JSON data to #verify_and_execute_refund() to further
 * check the details of the operation specified.  If everything checks out,
 * this will ultimately lead to the refund being executed, or rejected.
 *
 * @param connection the MHD connection to handle
 * @param coin_pub public key of the coin
 * @param root uploaded JSON data
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_refund (struct MHD_Connection *connection,
                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                    const json_t *root)
{
  struct TALER_EXCHANGEDB_Refund refund = {
    .details.refund_fee.currency = {0}                                        /* set to invalid, just to be sure */
  };
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("refund_amount",
                            &refund.details.refund_amount),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &refund.details.h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &refund.details.merchant_pub),
    GNUNET_JSON_spec_uint64 ("rtransaction_id",
                             &refund.details.rtransaction_id),
    GNUNET_JSON_spec_fixed_auto ("merchant_sig",
                                 &refund.details.merchant_sig),
    GNUNET_JSON_spec_end ()
  };

  refund.coin.coin_pub = *coin_pub;
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
      return MHD_NO; /* hard failure */
    if (GNUNET_NO == res)
      return MHD_YES; /* failure */
  }
  {
    MHD_RESULT res;

    res = verify_and_execute_refund (connection,
                                     &refund);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_refund.c */
