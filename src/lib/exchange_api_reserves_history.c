/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_reserves_history.c
 * @brief Implementation of the POST /reserves/$RESERVE_PUB/history requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP history codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A /reserves/$RID/history Handle
 */
struct TALER_EXCHANGE_ReservesHistoryHandle
{

  /**
   * The keys of the exchange this request handle will use
   */
  struct TALER_EXCHANGE_Keys *keys;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext post_ctx;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_ReservesHistoryCallback cb;

  /**
   * Public key of the reserve we are querying.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Context for history entry helpers.
 */
struct HistoryParseContext
{

  /**
   * Keys of the exchange we use.
   */
  const struct TALER_EXCHANGE_Keys *keys;

  /**
   * Our reserve public key.
   */
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /**
   * Array of UUIDs.
   */
  struct GNUNET_HashCode *uuids;

  /**
   * Where to sum up total inbound amounts.
   */
  struct TALER_Amount *total_in;

  /**
   * Where to sum up total outbound amounts.
   */
  struct TALER_Amount *total_out;

  /**
   * Number of entries already used in @e uuids.
   */
  unsigned int uuid_off;
};


/**
 * Type of a function called to parse a reserve history
 * entry @a rh.
 *
 * @param[in,out] rh where to write the result
 * @param[in,out] uc UUID context for duplicate detection
 * @param transaction the transaction to parse
 * @return #GNUNET_OK on success
 */
typedef enum GNUNET_GenericReturnValue
(*ParseHelper)(struct TALER_EXCHANGE_ReserveHistoryEntry *rh,
               struct HistoryParseContext *uc,
               const json_t *transaction);


/**
 * Parse "credit" reserve history entry.
 *
 * @param[in,out] rh entry to parse
 * @param uc our context
 * @param transaction the transaction to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_credit (struct TALER_EXCHANGE_ReserveHistoryEntry *rh,
              struct HistoryParseContext *uc,
              const json_t *transaction)
{
  const char *wire_url;
  uint64_t wire_reference;
  struct GNUNET_TIME_Timestamp timestamp;
  struct GNUNET_JSON_Specification withdraw_spec[] = {
    GNUNET_JSON_spec_uint64 ("wire_reference",
                             &wire_reference),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &timestamp),
    GNUNET_JSON_spec_string ("sender_account_url",
                             &wire_url),
    GNUNET_JSON_spec_end ()
  };

  rh->type = TALER_EXCHANGE_RTT_CREDIT;
  if (0 >
      TALER_amount_add (uc->total_in,
                        uc->total_in,
                        &rh->amount))
  {
    /* overflow in history already!? inconceivable! Bad exchange! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         withdraw_spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  rh->details.in_details.sender_url = GNUNET_strdup (wire_url);
  rh->details.in_details.wire_reference = wire_reference;
  rh->details.in_details.timestamp = timestamp;
  return GNUNET_OK;
}


/**
 * Parse "credit" reserve history entry.
 *
 * @param[in,out] rh entry to parse
 * @param uc our context
 * @param transaction the transaction to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_withdraw (struct TALER_EXCHANGE_ReserveHistoryEntry *rh,
                struct HistoryParseContext *uc,
                const json_t *transaction)
{
  struct TALER_ReserveSignatureP sig;
  struct TALER_DenominationHashP h_denom_pub;
  struct TALER_BlindedCoinHashP bch;
  struct TALER_Amount withdraw_fee;
  struct GNUNET_JSON_Specification withdraw_spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &sig),
    TALER_JSON_spec_amount_any ("withdraw_fee",
                                &withdraw_fee),
    GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                 &h_denom_pub),
    GNUNET_JSON_spec_fixed_auto ("h_coin_envelope",
                                 &bch),
    GNUNET_JSON_spec_end ()
  };

  rh->type = TALER_EXCHANGE_RTT_WITHDRAWAL;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         withdraw_spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* Check that the signature is a valid withdraw request */
  if (GNUNET_OK !=
      TALER_wallet_withdraw_verify (&h_denom_pub,
                                    &rh->amount,
                                    &bch,
                                    uc->reserve_pub,
                                    &sig))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (withdraw_spec);
    return GNUNET_SYSERR;
  }
  /* check that withdraw fee matches expectations! */
  {
    const struct TALER_EXCHANGE_Keys *key_state;
    const struct TALER_EXCHANGE_DenomPublicKey *dki;

    key_state = uc->keys;
    dki = TALER_EXCHANGE_get_denomination_key_by_hash (key_state,
                                                       &h_denom_pub);
    if ( (GNUNET_YES !=
          TALER_amount_cmp_currency (&withdraw_fee,
                                     &dki->fees.withdraw)) ||
         (0 !=
          TALER_amount_cmp (&withdraw_fee,
                            &dki->fees.withdraw)) )
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (withdraw_spec);
      return GNUNET_SYSERR;
    }
    rh->details.withdraw.fee = withdraw_fee;
  }
  rh->details.withdraw.out_authorization_sig
    = json_object_get (transaction,
                       "signature");
  /* Check check that the same withdraw transaction
       isn't listed twice by the exchange. We use the
       "uuid" array to remember the hashes of all
       signatures, and compare the hashes to find
       duplicates. */
  GNUNET_CRYPTO_hash (&sig,
                      sizeof (sig),
                      &uc->uuids[uc->uuid_off]);
  for (unsigned int i = 0; i<uc->uuid_off; i++)
  {
    if (0 == GNUNET_memcmp (&uc->uuids[uc->uuid_off],
                            &uc->uuids[i]))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (withdraw_spec);
      return GNUNET_SYSERR;
    }
  }
  uc->uuid_off++;

  if (0 >
      TALER_amount_add (uc->total_out,
                        uc->total_out,
                        &rh->amount))
  {
    /* overflow in history already!? inconceivable! Bad exchange! */
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (withdraw_spec);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Parse "recoup" reserve history entry.
 *
 * @param[in,out] rh entry to parse
 * @param uc our context
 * @param transaction the transaction to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_recoup (struct TALER_EXCHANGE_ReserveHistoryEntry *rh,
              struct HistoryParseContext *uc,
              const json_t *transaction)
{
  const struct TALER_EXCHANGE_Keys *key_state;
  struct GNUNET_JSON_Specification recoup_spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &rh->details.recoup_details.coin_pub),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &rh->details.recoup_details.exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &rh->details.recoup_details.exchange_pub),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &rh->details.recoup_details.timestamp),
    GNUNET_JSON_spec_end ()
  };

  rh->type = TALER_EXCHANGE_RTT_RECOUP;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         recoup_spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  key_state = uc->keys;
  if (GNUNET_OK !=
      TALER_EXCHANGE_test_signing_key (key_state,
                                       &rh->details.
                                       recoup_details.exchange_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_online_confirm_recoup_verify (
        rh->details.recoup_details.timestamp,
        &rh->amount,
        &rh->details.recoup_details.coin_pub,
        uc->reserve_pub,
        &rh->details.recoup_details.exchange_pub,
        &rh->details.recoup_details.exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 >
      TALER_amount_add (uc->total_in,
                        uc->total_in,
                        &rh->amount))
  {
    /* overflow in history already!? inconceivable! Bad exchange! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Parse "closing" reserve history entry.
 *
 * @param[in,out] rh entry to parse
 * @param uc our context
 * @param transaction the transaction to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_closing (struct TALER_EXCHANGE_ReserveHistoryEntry *rh,
               struct HistoryParseContext *uc,
               const json_t *transaction)
{
  const struct TALER_EXCHANGE_Keys *key_state;
  struct GNUNET_JSON_Specification closing_spec[] = {
    GNUNET_JSON_spec_string (
      "receiver_account_details",
      &rh->details.close_details.receiver_account_details),
    GNUNET_JSON_spec_fixed_auto ("wtid",
                                 &rh->details.close_details.wtid),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &rh->details.close_details.exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &rh->details.close_details.exchange_pub),
    TALER_JSON_spec_amount_any ("closing_fee",
                                &rh->details.close_details.fee),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &rh->details.close_details.timestamp),
    GNUNET_JSON_spec_end ()
  };

  rh->type = TALER_EXCHANGE_RTT_CLOSING;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         closing_spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  key_state = uc->keys;
  if (GNUNET_OK !=
      TALER_EXCHANGE_test_signing_key (
        key_state,
        &rh->details.close_details.exchange_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_online_reserve_closed_verify (
        rh->details.close_details.timestamp,
        &rh->amount,
        &rh->details.close_details.fee,
        rh->details.close_details.receiver_account_details,
        &rh->details.close_details.wtid,
        uc->reserve_pub,
        &rh->details.close_details.exchange_pub,
        &rh->details.close_details.exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 >
      TALER_amount_add (uc->total_out,
                        uc->total_out,
                        &rh->amount))
  {
    /* overflow in history already!? inconceivable! Bad exchange! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Parse "merge" reserve history entry.
 *
 * @param[in,out] rh entry to parse
 * @param uc our context
 * @param transaction the transaction to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_merge (struct TALER_EXCHANGE_ReserveHistoryEntry *rh,
             struct HistoryParseContext *uc,
             const json_t *transaction)
{
  uint32_t flags32;
  struct GNUNET_JSON_Specification merge_spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &rh->details.merge_details.h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("merge_pub",
                                 &rh->details.merge_details.merge_pub),
    GNUNET_JSON_spec_fixed_auto ("purse_pub",
                                 &rh->details.merge_details.purse_pub),
    GNUNET_JSON_spec_uint32 ("min_age",
                             &rh->details.merge_details.min_age),
    GNUNET_JSON_spec_uint32 ("flags",
                             &flags32),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &rh->details.merge_details.reserve_sig),
    TALER_JSON_spec_amount_any ("purse_fee",
                                &rh->details.merge_details.purse_fee),
    GNUNET_JSON_spec_timestamp ("merge_timestamp",
                                &rh->details.merge_details.merge_timestamp),
    GNUNET_JSON_spec_timestamp ("purse_expiration",
                                &rh->details.merge_details.purse_expiration),
    GNUNET_JSON_spec_bool ("merged",
                           &rh->details.merge_details.merged),
    GNUNET_JSON_spec_end ()
  };

  rh->type = TALER_EXCHANGE_RTT_MERGE;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         merge_spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  rh->details.merge_details.flags =
    (enum TALER_WalletAccountMergeFlags) flags32;
  if (GNUNET_OK !=
      TALER_wallet_account_merge_verify (
        rh->details.merge_details.merge_timestamp,
        &rh->details.merge_details.purse_pub,
        rh->details.merge_details.purse_expiration,
        &rh->details.merge_details.h_contract_terms,
        &rh->amount,
        &rh->details.merge_details.purse_fee,
        rh->details.merge_details.min_age,
        rh->details.merge_details.flags,
        uc->reserve_pub,
        &rh->details.merge_details.reserve_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (rh->details.merge_details.merged)
  {
    if (0 >
        TALER_amount_add (uc->total_in,
                          uc->total_in,
                          &rh->amount))
    {
      /* overflow in history already!? inconceivable! Bad exchange! */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  else
  {
    if (0 >
        TALER_amount_add (uc->total_out,
                          uc->total_out,
                          &rh->details.merge_details.purse_fee))
    {
      /* overflow in history already!? inconceivable! Bad exchange! */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


/**
 * Parse "open" reserve open entry.
 *
 * @param[in,out] rh entry to parse
 * @param uc our context
 * @param transaction the transaction to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_open (struct TALER_EXCHANGE_ReserveHistoryEntry *rh,
            struct HistoryParseContext *uc,
            const json_t *transaction)
{
  struct GNUNET_JSON_Specification open_spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &rh->details.open_request.reserve_sig),
    TALER_JSON_spec_amount_any ("open_payment",
                                &rh->details.open_request.reserve_payment),
    GNUNET_JSON_spec_uint32 ("requested_min_purses",
                             &rh->details.open_request.purse_limit),
    GNUNET_JSON_spec_timestamp ("request_timestamp",
                                &rh->details.open_request.request_timestamp),
    GNUNET_JSON_spec_timestamp ("requested_expiration",
                                &rh->details.open_request.reserve_expiration),
    GNUNET_JSON_spec_end ()
  };

  rh->type = TALER_EXCHANGE_RTT_OPEN;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         open_spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_reserve_open_verify (
        &rh->amount,
        rh->details.open_request.request_timestamp,
        rh->details.open_request.reserve_expiration,
        rh->details.open_request.purse_limit,
        uc->reserve_pub,
        &rh->details.open_request.reserve_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 >
      TALER_amount_add (uc->total_out,
                        uc->total_out,
                        &rh->amount))
  {
    /* overflow in history already!? inconceivable! Bad exchange! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Parse "close" reserve close entry.
 *
 * @param[in,out] rh entry to parse
 * @param uc our context
 * @param transaction the transaction to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_close (struct TALER_EXCHANGE_ReserveHistoryEntry *rh,
             struct HistoryParseContext *uc,
             const json_t *transaction)
{
  struct GNUNET_JSON_Specification close_spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &rh->details.close_request.reserve_sig),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_payto",
                                   &rh->details.close_request.
                                   target_account_h_payto),
      NULL),
    GNUNET_JSON_spec_timestamp ("request_timestamp",
                                &rh->details.close_request.request_timestamp),
    GNUNET_JSON_spec_end ()
  };

  rh->type = TALER_EXCHANGE_RTT_CLOSE;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         close_spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* force amount to invalid */
  memset (&rh->amount,
          0,
          sizeof (rh->amount));
  if (GNUNET_OK !=
      TALER_wallet_reserve_close_verify (
        rh->details.close_request.request_timestamp,
        &rh->details.close_request.target_account_h_payto,
        uc->reserve_pub,
        &rh->details.close_request.reserve_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


static void
free_reserve_history (
  unsigned int len,
  struct TALER_EXCHANGE_ReserveHistoryEntry rhistory[static len])
{
  for (unsigned int i = 0; i<len; i++)
  {
    switch (rhistory[i].type)
    {
    case TALER_EXCHANGE_RTT_CREDIT:
      GNUNET_free (rhistory[i].details.in_details.sender_url);
      break;
    case TALER_EXCHANGE_RTT_WITHDRAWAL:
      break;
    case TALER_EXCHANGE_RTT_AGEWITHDRAWAL:
      break;
    case TALER_EXCHANGE_RTT_RECOUP:
      break;
    case TALER_EXCHANGE_RTT_CLOSING:
      break;
    case TALER_EXCHANGE_RTT_MERGE:
      break;
    case TALER_EXCHANGE_RTT_OPEN:
      break;
    case TALER_EXCHANGE_RTT_CLOSE:
      break;
    }
  }
  GNUNET_free (rhistory);
}


/**
 * Parse history given in JSON format and return it in binary
 * format.
 *
 * @param keys exchange keys
 * @param history JSON array with the history
 * @param reserve_pub public key of the reserve to inspect
 * @param currency currency we expect the balance to be in
 * @param[out] total_in set to value of credits to reserve
 * @param[out] total_out set to value of debits from reserve
 * @param history_length number of entries in @a history
 * @param[out] rhistory array of length @a history_length, set to the
 *             parsed history entries
 * @return #GNUNET_OK if history was valid and @a rhistory and @a balance
 *         were set,
 *         #GNUNET_SYSERR if there was a protocol violation in @a history
 */
static enum GNUNET_GenericReturnValue
parse_reserve_history (
  const struct TALER_EXCHANGE_Keys *keys,
  const json_t *history,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *currency,
  struct TALER_Amount *total_in,
  struct TALER_Amount *total_out,
  unsigned int history_length,
  struct TALER_EXCHANGE_ReserveHistoryEntry rhistory[static history_length])
{
  const struct
  {
    const char *type;
    ParseHelper helper;
  } map[] = {
    { "CREDIT", &parse_credit },
    { "WITHDRAW", &parse_withdraw },
    { "RECOUP", &parse_recoup },
    { "MERGE", &parse_merge },
    { "CLOSING", &parse_closing },
    { "OPEN", &parse_open },
    { "CLOSE", &parse_close },
    { NULL, NULL }
  };
  struct GNUNET_HashCode uuid[history_length];
  struct HistoryParseContext uc = {
    .keys = keys,
    .reserve_pub = reserve_pub,
    .uuids = uuid,
    .total_in = total_in,
    .total_out = total_out
  };

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        total_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        total_out));
  for (unsigned int off = 0; off<history_length; off++)
  {
    struct TALER_EXCHANGE_ReserveHistoryEntry *rh = &rhistory[off];
    json_t *transaction;
    struct TALER_Amount amount;
    const char *type;
    struct GNUNET_JSON_Specification hist_spec[] = {
      GNUNET_JSON_spec_string ("type",
                               &type),
      TALER_JSON_spec_amount_any ("amount",
                                  &amount),
      /* 'wire' and 'signature' are optional depending on 'type'! */
      GNUNET_JSON_spec_end ()
    };
    bool found = false;

    transaction = json_array_get (history,
                                  off);
    if (GNUNET_OK !=
        GNUNET_JSON_parse (transaction,
                           hist_spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      json_dumpf (transaction,
                  stderr,
                  JSON_INDENT (2));
      return GNUNET_SYSERR;
    }
    rh->amount = amount;
    if (GNUNET_YES !=
        TALER_amount_cmp_currency (&amount,
                                   total_in))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    for (unsigned int i = 0; NULL != map[i].type; i++)
    {
      if (0 == strcasecmp (map[i].type,
                           type))
      {
        found = true;
        if (GNUNET_OK !=
            map[i].helper (rh,
                           &uc,
                           transaction))
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
        break;
      }
    }
    if (! found)
    {
      /* unexpected 'type', protocol incompatibility, complain! */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


/**
 * We received an #MHD_HTTP_OK history code. Handle the JSON
 * response.
 *
 * @param rsh handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_reserves_history_ok (struct TALER_EXCHANGE_ReservesHistoryHandle *rsh,
                            const json_t *j)
{
  const json_t *history;
  unsigned int len;
  struct TALER_EXCHANGE_ReserveHistory rs = {
    .hr.reply = j,
    .hr.http_status = MHD_HTTP_OK
  };
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("balance",
                                &rs.details.ok.balance),
    GNUNET_JSON_spec_array_const ("history",
                                  &history),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (j,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  len = json_array_size (history);
  {
    struct TALER_EXCHANGE_ReserveHistoryEntry *rhistory;

    rhistory = GNUNET_new_array (len,
                                 struct TALER_EXCHANGE_ReserveHistoryEntry);
    if (GNUNET_OK !=
        parse_reserve_history (rsh->keys,
                               history,
                               &rsh->reserve_pub,
                               rs.details.ok.balance.currency,
                               &rs.details.ok.total_in,
                               &rs.details.ok.total_out,
                               len,
                               rhistory))
    {
      GNUNET_break_op (0);
      free_reserve_history (len,
                            rhistory);
      GNUNET_JSON_parse_free (spec);
      return GNUNET_SYSERR;
    }
    if (NULL != rsh->cb)
    {
      rs.details.ok.history = rhistory;
      rs.details.ok.history_len = len;
      rsh->cb (rsh->cb_cls,
               &rs);
      rsh->cb = NULL;
    }
    free_reserve_history (len,
                          rhistory);
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserves/$RID/history request.
 *
 * @param cls the `struct TALER_EXCHANGE_ReservesHistoryHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserves_history_finished (void *cls,
                                  long response_code,
                                  const void *response)
{
  struct TALER_EXCHANGE_ReservesHistoryHandle *rsh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_ReserveHistory rs = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  rsh->job = NULL;
  switch (response_code)
  {
  case 0:
    rs.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        handle_reserves_history_ok (rsh,
                                    j))
    {
      rs.hr.http_status = 0;
      rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for reserves history\n",
                (unsigned int) response_code,
                (int) rs.hr.ec);
    break;
  }
  if (NULL != rsh->cb)
  {
    rsh->cb (rsh->cb_cls,
             &rs);
    rsh->cb = NULL;
  }
  TALER_EXCHANGE_reserves_history_cancel (rsh);
}


struct TALER_EXCHANGE_ReservesHistoryHandle *
TALER_EXCHANGE_reserves_history (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  uint64_t start_off,
  TALER_EXCHANGE_ReservesHistoryCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ReservesHistoryHandle *rsh;
  CURL *eh;
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 64];
  struct curl_slist *job_headers;

  rsh = GNUNET_new (struct TALER_EXCHANGE_ReservesHistoryHandle);
  rsh->cb = cb;
  rsh->cb_cls = cb_cls;
  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &rsh->reserve_pub.eddsa_pub);
  {
    char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &rsh->reserve_pub,
      sizeof (rsh->reserve_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    if (0 != start_off)
      GNUNET_snprintf (arg_str,
                       sizeof (arg_str),
                       "reserves/%s/history?start=%llu",
                       pub_str,
                       (unsigned long long) start_off);
    else
      GNUNET_snprintf (arg_str,
                       sizeof (arg_str),
                       "reserves/%s/history",
                       pub_str);
  }
  rsh->url = TALER_url_join (url,
                             arg_str,
                             NULL);
  if (NULL == rsh->url)
  {
    GNUNET_free (rsh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (rsh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (rsh->url);
    GNUNET_free (rsh);
    return NULL;
  }

  {
    struct TALER_ReserveSignatureP reserve_sig;
    char *sig_hdr;
    char *hdr;

    TALER_wallet_reserve_history_sign (start_off,
                                       reserve_priv,
                                       &reserve_sig);

    sig_hdr = GNUNET_STRINGS_data_to_string_alloc (
      &reserve_sig,
      sizeof (reserve_sig));
    GNUNET_asprintf (&hdr,
                     "%s: %s",
                     TALER_RESERVE_HISTORY_SIGNATURE_HEADER,
                     sig_hdr);
    GNUNET_free (sig_hdr);
    job_headers = curl_slist_append (NULL,
                                     hdr);
    GNUNET_free (hdr);
    if (NULL == job_headers)
    {
      GNUNET_break (0);
      return NULL;
    }
  }

  rsh->keys = TALER_EXCHANGE_keys_incref (keys);
  rsh->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   job_headers,
                                   &handle_reserves_history_finished,
                                   rsh);
  curl_slist_free_all (job_headers);
  return rsh;
}


void
TALER_EXCHANGE_reserves_history_cancel (
  struct TALER_EXCHANGE_ReservesHistoryHandle *rsh)
{
  if (NULL != rsh->job)
  {
    GNUNET_CURL_job_cancel (rsh->job);
    rsh->job = NULL;
  }
  TALER_curl_easy_post_finished (&rsh->post_ctx);
  GNUNET_free (rsh->url);
  TALER_EXCHANGE_keys_decref (rsh->keys);
  GNUNET_free (rsh);
}


/* end of exchange_api_reserves_history.c */
