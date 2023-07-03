/*
  This file is part of TALER
  Copyright (C) 2015-2022 Taler Systems SA

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
 * @file lib/exchange_api_common.c
 * @brief common functions for the exchange API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_common.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"


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
 * Parse "history" reserve history entry.
 *
 * @param[in,out] rh entry to parse
 * @param uc our context
 * @param transaction the transaction to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_history (struct TALER_EXCHANGE_ReserveHistoryEntry *rh,
               struct HistoryParseContext *uc,
               const json_t *transaction)
{
  struct GNUNET_JSON_Specification history_spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &rh->details.history_details.reserve_sig),
    GNUNET_JSON_spec_timestamp ("request_timestamp",
                                &rh->details.history_details.request_timestamp),
    GNUNET_JSON_spec_end ()
  };

  rh->type = TALER_EXCHANGE_RTT_HISTORY;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         history_spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_reserve_history_verify (
        rh->details.history_details.request_timestamp,
        &rh->amount,
        uc->reserve_pub,
        &rh->details.history_details.reserve_sig))
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


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_parse_reserve_history (
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
    { "HISTORY", &parse_history },
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


void
TALER_EXCHANGE_free_reserve_history (
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
    case TALER_EXCHANGE_RTT_RECOUP:
      break;
    case TALER_EXCHANGE_RTT_CLOSING:
      break;
    case TALER_EXCHANGE_RTT_HISTORY:
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
 * Context for coin helpers.
 */
struct CoinHistoryParseContext
{

  /**
   * Denomination of the coin.
   */
  const struct TALER_EXCHANGE_DenomPublicKey *dk;

  /**
   * Our coin public key.
   */
  const struct TALER_CoinSpendPublicKeyP *coin_pub;

  /**
   * Where to sum up total refunds.
   */
  struct TALER_Amount rtotal;

  /**
   * Total amount encountered.
   */
  struct TALER_Amount *total;

};


/**
 * Signature of functions that operate on one of
 * the coin's history entries.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
typedef enum GNUNET_GenericReturnValue
(*CoinCheckHelper)(struct CoinHistoryParseContext *pc,
                   const struct TALER_Amount *amount,
                   json_t *transaction);


/**
 * Handle deposit entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_deposit (struct CoinHistoryParseContext *pc,
              const struct TALER_Amount *amount,
              json_t *transaction)
{
  struct TALER_MerchantWireHashP h_wire;
  struct TALER_PrivateContractHashP h_contract_terms;
  struct TALER_ExtensionPolicyHashP h_policy;
  bool no_h_policy;
  struct GNUNET_TIME_Timestamp wallet_timestamp;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct GNUNET_TIME_Timestamp refund_deadline = {0};
  struct TALER_CoinSpendSignatureP sig;
  struct TALER_AgeCommitmentHash hac;
  bool no_hac;
  struct TALER_Amount deposit_fee;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &sig),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("h_wire",
                                 &h_wire),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &hac),
      &no_hac),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_policy",
                                   &h_policy),
      &no_h_policy),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &wallet_timestamp),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_timestamp ("refund_deadline",
                                  &refund_deadline),
      NULL),
    TALER_JSON_spec_amount_any ("deposit_fee",
                                &deposit_fee),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &merchant_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_deposit_verify (
        amount,
        &deposit_fee,
        &h_wire,
        &h_contract_terms,
        no_hac ? NULL : &hac,
        no_h_policy ? NULL : &h_policy,
        &pc->dk->h_key,
        wallet_timestamp,
        &merchant_pub,
        refund_deadline,
        pc->coin_pub,
        &sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* check that deposit fee matches our expectations from /keys! */
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&deposit_fee,
                                   &pc->dk->fees.deposit)) ||
       (0 !=
        TALER_amount_cmp (&deposit_fee,
                          &pc->dk->fees.deposit)) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_YES;
}


/**
 * Handle melt entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_melt (struct CoinHistoryParseContext *pc,
           const struct TALER_Amount *amount,
           json_t *transaction)
{
  struct TALER_CoinSpendSignatureP sig;
  struct TALER_RefreshCommitmentP rc;
  struct TALER_AgeCommitmentHash h_age_commitment;
  bool no_hac;
  struct TALER_Amount melt_fee;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &sig),
    GNUNET_JSON_spec_fixed_auto ("rc",
                                 &rc),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &h_age_commitment),
      &no_hac),
    TALER_JSON_spec_amount_any ("melt_fee",
                                &melt_fee),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* check that melt fee matches our expectations from /keys! */
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&melt_fee,
                                   &pc->dk->fees.refresh)) ||
       (0 !=
        TALER_amount_cmp (&melt_fee,
                          &pc->dk->fees.refresh)) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_melt_verify (
        amount,
        &melt_fee,
        &rc,
        &pc->dk->h_key,
        no_hac
        ? NULL
        : &h_age_commitment,
        pc->coin_pub,
        &sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_YES;
}


/**
 * Handle refund entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_refund (struct CoinHistoryParseContext *pc,
             const struct TALER_Amount *amount,
             json_t *transaction)
{
  struct TALER_PrivateContractHashP h_contract_terms;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct TALER_MerchantSignatureP sig;
  struct TALER_Amount refund_fee;
  struct TALER_Amount sig_amount;
  uint64_t rtransaction_id;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("refund_fee",
                                &refund_fee),
    GNUNET_JSON_spec_fixed_auto ("merchant_sig",
                                 &sig),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &merchant_pub),
    GNUNET_JSON_spec_uint64 ("rtransaction_id",
                             &rtransaction_id),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 >
      TALER_amount_add (&sig_amount,
                        &refund_fee,
                        amount))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_merchant_refund_verify (pc->coin_pub,
                                    &h_contract_terms,
                                    rtransaction_id,
                                    &sig_amount,
                                    &merchant_pub,
                                    &sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* NOTE: theoretically, we could also check that the given
     merchant_pub and h_contract_terms appear in the
     history under deposits.  However, there is really no benefit
     for the exchange to lie here, so not checking is probably OK
     (an auditor ought to check, though). Then again, we similarly
     had no reason to check the merchant's signature (other than a
     well-formendess check). */

  /* check that refund fee matches our expectations from /keys! */
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&refund_fee,
                                   &pc->dk->fees.refund)) ||
       (0 !=
        TALER_amount_cmp (&refund_fee,
                          &pc->dk->fees.refund)) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_NO;
}


/**
 * Handle recoup entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_recoup (struct CoinHistoryParseContext *pc,
             const struct TALER_Amount *amount,
             json_t *transaction)
{
  struct TALER_ReservePublicKeyP reserve_pub;
  struct GNUNET_TIME_Timestamp timestamp;
  union TALER_DenominationBlindingKeyP coin_bks;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &exchange_pub),
    GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                 &reserve_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_blind",
                                 &coin_bks),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &timestamp),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_online_confirm_recoup_verify (
        timestamp,
        amount,
        pc->coin_pub,
        &reserve_pub,
        &exchange_pub,
        &exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_recoup_verify (&pc->dk->h_key,
                                  &coin_bks,
                                  pc->coin_pub,
                                  &coin_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_YES;
}


/**
 * Handle recoup-refresh entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_recoup_refresh (struct CoinHistoryParseContext *pc,
                     const struct TALER_Amount *amount,
                     json_t *transaction)
{
  /* This is the coin that was subjected to a recoup,
       the value being credited to the old coin. */
  struct TALER_CoinSpendPublicKeyP old_coin_pub;
  union TALER_DenominationBlindingKeyP coin_bks;
  struct GNUNET_TIME_Timestamp timestamp;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &exchange_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_fixed_auto ("old_coin_pub",
                                 &old_coin_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_blind",
                                 &coin_bks),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &timestamp),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_online_confirm_recoup_refresh_verify (
        timestamp,
        amount,
        pc->coin_pub,
        &old_coin_pub,
        &exchange_pub,
        &exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_recoup_verify (&pc->dk->h_key,
                                  &coin_bks,
                                  pc->coin_pub,
                                  &coin_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_YES;
}


/**
 * Handle old coin recoup entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_old_coin_recoup (struct CoinHistoryParseContext *pc,
                      const struct TALER_Amount *amount,
                      json_t *transaction)
{
  /* This is the coin that was credited in a recoup,
       the value being credited to the this coin. */
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_CoinSpendPublicKeyP new_coin_pub;
  struct GNUNET_TIME_Timestamp timestamp;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &exchange_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &new_coin_pub),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &timestamp),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_online_confirm_recoup_refresh_verify (
        timestamp,
        amount,
        &new_coin_pub,
        pc->coin_pub,
        &exchange_pub,
        &exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_NO;
}


/**
 * Handle purse deposit entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_purse_deposit (struct CoinHistoryParseContext *pc,
                    const struct TALER_Amount *amount,
                    json_t *transaction)
{
  struct TALER_PurseContractPublicKeyP purse_pub;
  struct TALER_CoinSpendSignatureP coin_sig;
  const char *exchange_base_url;
  bool refunded;
  struct TALER_AgeCommitmentHash phac = { 0 };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("purse_pub",
                                 &purse_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &coin_sig),
      NULL),
    GNUNET_JSON_spec_string ("exchange_base_url",
                             &exchange_base_url),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &phac),
      NULL),
    GNUNET_JSON_spec_bool ("refunded",
                           &refunded),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_purse_deposit_verify (
        exchange_base_url,
        &purse_pub,
        amount,
        &pc->dk->h_key,
        &phac,
        pc->coin_pub,
        &coin_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (refunded)
  {
    /* We wave the deposit fee. */
    if (0 >
        TALER_amount_add (&pc->rtotal,
                          &pc->rtotal,
                          &pc->dk->fees.deposit))
    {
      /* overflow in refund history? inconceivable! Bad exchange! */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_YES;
}


/**
 * Handle purse refund entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_purse_refund (struct CoinHistoryParseContext *pc,
                   const struct TALER_Amount *amount,
                   json_t *transaction)
{
  struct TALER_PurseContractPublicKeyP purse_pub;
  struct TALER_Amount refund_fee;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_ExchangeSignatureP exchange_sig;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("refund_fee",
                                &refund_fee),
    GNUNET_JSON_spec_fixed_auto ("purse_pub",
                                 &purse_pub),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &exchange_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_exchange_online_purse_refund_verify (
        amount,
        &refund_fee,
        pc->coin_pub,
        &purse_pub,
        &exchange_pub,
        &exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&refund_fee,
                                   &pc->dk->fees.refund)) ||
       (0 !=
        TALER_amount_cmp (&refund_fee,
                          &pc->dk->fees.refund)) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_NO;
}


/**
 * Handle reserve deposit entry in the coin's history.
 *
 * @param[in,out] pc overall context
 * @param amount main amount of this operation
 * @param transaction JSON details for the operation
 * @return #GNUNET_SYSERR on error,
 *         #GNUNET_OK to add, #GNUNET_NO to subtract
 */
static enum GNUNET_GenericReturnValue
help_reserve_open_deposit (struct CoinHistoryParseContext *pc,
                           const struct TALER_Amount *amount,
                           json_t *transaction)
{
  struct TALER_ReserveSignatureP reserve_sig;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &reserve_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (transaction,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_reserve_open_deposit_verify (
        amount,
        &reserve_sig,
        pc->coin_pub,
        &coin_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_YES;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_verify_coin_history (
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const json_t *history,
  struct TALER_Amount *total)
{
  const char *currency = dk->value.currency;
  const struct
  {
    const char *type;
    CoinCheckHelper helper;
  } map[] = {
    { "DEPOSIT", &help_deposit },
    { "MELT", &help_melt },
    { "REFUND", &help_refund },
    { "RECOUP", &help_recoup },
    { "RECOUP-REFRESH", &help_recoup_refresh },
    { "OLD-COIN-RECOUP", &help_old_coin_recoup },
    { "PURSE-DEPOSIT", &help_purse_deposit },
    { "PURSE-REFUND", &help_purse_refund },
    { "RESERVE-OPEN-DEPOSIT", &help_reserve_open_deposit },
    { NULL, NULL }
  };
  struct CoinHistoryParseContext pc = {
    .dk = dk,
    .coin_pub = coin_pub,
    .total = total
  };
  size_t len;

  if (NULL == history)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  len = json_array_size (history);
  if (0 == len)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        total));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        &pc.rtotal));
  for (size_t off = 0; off<len; off++)
  {
    enum GNUNET_GenericReturnValue add;
    json_t *transaction;
    struct TALER_Amount amount;
    const char *type;
    struct GNUNET_JSON_Specification spec_glob[] = {
      TALER_JSON_spec_amount_any ("amount",
                                  &amount),
      GNUNET_JSON_spec_string ("type",
                               &type),
      GNUNET_JSON_spec_end ()
    };

    transaction = json_array_get (history,
                                  off);
    if (GNUNET_OK !=
        GNUNET_JSON_parse (transaction,
                           spec_glob,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if (GNUNET_YES !=
        TALER_amount_cmp_currency (&amount,
                                   &pc.rtotal))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Operation of type %s with amount %s\n",
                type,
                TALER_amount2s (&amount));
    add = GNUNET_SYSERR;
    for (unsigned int i = 0; NULL != map[i].type; i++)
    {
      if (0 == strcasecmp (type,
                           map[i].type))
      {
        add = map[i].helper (&pc,
                             &amount,
                             transaction);
        break;
      }
    }
    switch (add)
    {
    case GNUNET_SYSERR:
      /* entry type not supported, new version on server? */
      GNUNET_break_op (0);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unexpected type `%s' in response\n",
                  type);
      return GNUNET_SYSERR;
    case GNUNET_YES:
      /* This amount should be added to the total */
      if (0 >
          TALER_amount_add (total,
                            total,
                            &amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      break;
    case GNUNET_NO:
      /* This amount should be subtracted from the total.

         However, for the implementation, we first *add* up all of
         these negative amounts, as we might get refunds before
         deposits from a semi-evil exchange.  Then, at the end, we do
         the subtraction by calculating "total = total - rtotal" */
      if (0 >
          TALER_amount_add (&pc.rtotal,
                            &pc.rtotal,
                            &amount))
      {
        /* overflow in refund history? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      break;
    } /* end of switch(add) */
  }
  /* Finally, subtract 'rtotal' from total to handle the subtractions */
  if (0 >
      TALER_amount_subtract (total,
                             total,
                             &pc.rtotal))
  {
    /* underflow in history? inconceivable! Bad exchange! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


const struct TALER_EXCHANGE_SigningPublicKey *
TALER_EXCHANGE_get_signing_key_info (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ExchangePublicKeyP *exchange_pub)
{
  for (unsigned int i = 0; i<keys->num_sign_keys; i++)
  {
    const struct TALER_EXCHANGE_SigningPublicKey *spk
      = &keys->sign_keys[i];

    if (0 == GNUNET_memcmp (exchange_pub,
                            &spk->key))
      return spk;
  }
  return NULL;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_create_conflict_ (
  const struct TALER_PurseContractSignatureP *cpurse_sig,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *proof)
{
  struct TALER_Amount amount;
  uint32_t min_age;
  struct GNUNET_TIME_Timestamp purse_expiration;
  struct TALER_PurseContractSignatureP purse_sig;
  struct TALER_PrivateContractHashP h_contract_terms;
  struct TALER_PurseMergePublicKeyP merge_pub;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("amount",
                                &amount),
    GNUNET_JSON_spec_uint32 ("min_age",
                             &min_age),
    GNUNET_JSON_spec_timestamp ("purse_expiration",
                                &purse_expiration),
    GNUNET_JSON_spec_fixed_auto ("purse_sig",
                                 &purse_sig),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("merge_pub",
                                 &merge_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_purse_create_verify (purse_expiration,
                                        &h_contract_terms,
                                        &merge_pub,
                                        min_age,
                                        &amount,
                                        purse_pub,
                                        &purse_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 ==
      GNUNET_memcmp (&purse_sig,
                     cpurse_sig))
  {
    /* Must be the SAME data, not a conflict! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_merge_conflict_ (
  const struct TALER_PurseMergeSignatureP *cmerge_sig,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const char *exchange_url,
  const json_t *proof)
{
  struct TALER_PurseMergeSignatureP merge_sig;
  struct GNUNET_TIME_Timestamp merge_timestamp;
  const char *partner_url = NULL;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_string ("partner_url",
                               &partner_url),
      NULL),
    GNUNET_JSON_spec_timestamp ("merge_timestamp",
                                &merge_timestamp),
    GNUNET_JSON_spec_fixed_auto ("merge_sig",
                                 &merge_sig),
    GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                 &reserve_pub),
    GNUNET_JSON_spec_end ()
  };
  char *payto_uri;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (NULL == partner_url)
    partner_url = exchange_url;
  payto_uri = TALER_reserve_make_payto (partner_url,
                                        &reserve_pub);
  if (GNUNET_OK !=
      TALER_wallet_purse_merge_verify (
        payto_uri,
        merge_timestamp,
        purse_pub,
        merge_pub,
        &merge_sig))
  {
    GNUNET_break_op (0);
    GNUNET_free (payto_uri);
    return GNUNET_SYSERR;
  }
  GNUNET_free (payto_uri);
  if (0 ==
      GNUNET_memcmp (&merge_sig,
                     cmerge_sig))
  {
    /* Must be the SAME data, not a conflict! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_coin_conflict_ (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const char *exchange_url,
  const json_t *proof,
  struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_AgeCommitmentHash *phac,
  struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  const char *partner_url = NULL;
  struct TALER_Amount amount;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                 h_denom_pub),
    GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                 phac),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 coin_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 coin_pub),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_string ("partner_url",
                               &partner_url),
      NULL),
    TALER_JSON_spec_amount_any ("amount",
                                &amount),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (NULL == partner_url)
    partner_url = exchange_url;
  if (GNUNET_OK !=
      TALER_wallet_purse_deposit_verify (
        partner_url,
        purse_pub,
        &amount,
        h_denom_pub,
        phac,
        coin_pub,
        coin_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_purse_econtract_conflict_ (
  const struct TALER_PurseContractSignatureP *ccontract_sig,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *proof)
{
  struct TALER_ContractDiffiePublicP contract_pub;
  struct TALER_PurseContractSignatureP contract_sig;
  struct GNUNET_HashCode h_econtract;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_econtract",
                                 &h_econtract),
    GNUNET_JSON_spec_fixed_auto ("econtract_sig",
                                 &contract_sig),
    GNUNET_JSON_spec_fixed_auto ("contract_pub",
                                 &contract_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_wallet_econtract_upload_verify2 (
        &h_econtract,
        &contract_pub,
        purse_pub,
        &contract_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 ==
      GNUNET_memcmp (&contract_sig,
                     ccontract_sig))
  {
    /* Must be the SAME data, not a conflict! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_coin_amount_conflict_ (
  const struct TALER_EXCHANGE_Keys *keys,
  const json_t *proof,
  struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_Amount *remaining)
{
  const json_t *history;
  struct TALER_Amount total;
  struct TALER_DenominationHashP h_denom_pub;
  const struct TALER_EXCHANGE_DenomPublicKey *dki;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 coin_pub),
    GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                 &h_denom_pub),
    GNUNET_JSON_spec_array_const ("history",
                                  &history),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  dki = TALER_EXCHANGE_get_denomination_key_by_hash (
    keys,
    &h_denom_pub);
  if (NULL == dki)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_EXCHANGE_verify_coin_history (dki,
                                          coin_pub,
                                          history,
                                          &total))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 >
      TALER_amount_subtract (remaining,
                             &dki->value,
                             &total))
  {
    /* Strange 'proof': coin was double-spent
       before our transaction?! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Verify that @a coin_sig does NOT appear in
 * the history of @a proof and thus whatever transaction
 * is authorized by @a coin_sig is a conflict with
 * @a proof.
 *
 * @param proof a proof to check
 * @param coin_sig signature that must not be in @a proof
 * @return #GNUNET_OK if @a coin_sig is not in @a proof
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_coin_signature_conflict_ (
  const json_t *proof,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  json_t *history;
  size_t off;
  json_t *entry;

  history = json_object_get (proof,
                             "history");
  if (NULL == history)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  json_array_foreach (history, off, entry)
  {
    struct TALER_CoinSpendSignatureP cs;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                   &cs),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (entry,
                           spec,
                           NULL, NULL))
      continue; /* entry without coin signature */
    if (0 ==
        GNUNET_memcmp (&cs,
                       coin_sig))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_coin_denomination_conflict_ (
  const json_t *proof,
  const struct TALER_DenominationHashP *ch_denom_pub)
{
  struct TALER_DenominationHashP h_denom_pub;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                 &h_denom_pub),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (proof,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 ==
      GNUNET_memcmp (ch_denom_pub,
                     &h_denom_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_OK;
  }
  /* indeed, proof with different denomination key provided */
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_check_coin_conflict_ (
  const struct TALER_EXCHANGE_Keys *keys,
  const json_t *proof,
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_Amount *required)
{
  enum TALER_ErrorCode ec;

  ec = TALER_JSON_get_error_code (proof);
  switch (ec)
  {
  case TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS:
    {
      struct TALER_Amount left;
      struct TALER_CoinSpendPublicKeyP pcoin_pub;

      if (GNUNET_OK !=
          TALER_EXCHANGE_check_coin_amount_conflict_ (
            keys,
            proof,
            &pcoin_pub,
            &left))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (0 !=
          GNUNET_memcmp (&pcoin_pub,
                         coin_pub))
      {
        /* conflict is for a different coin! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (-1 !=
          TALER_amount_cmp (&left,
                            required))
      {
        /* Balance was sufficient after all; recoup MAY have still been possible */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_EXCHANGE_check_coin_signature_conflict_ (
            proof,
            coin_sig))
      {
        /* Not a conflicting transaction: ours is included! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      break;
    }
  case TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_DENOMINATION_KEY:
    {
      struct TALER_Amount left;
      struct TALER_CoinSpendPublicKeyP pcoin_pub;

      if (GNUNET_OK !=
          TALER_EXCHANGE_check_coin_amount_conflict_ (
            keys,
            proof,
            &pcoin_pub,
            &left))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (0 !=
          GNUNET_memcmp (&pcoin_pub,
                         coin_pub))
      {
        /* conflict is for a different coin! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_EXCHANGE_check_coin_denomination_conflict_ (
            proof,
            &dk->h_key))
      {
        /* Eh, same denomination, hence no conflict */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      break;
    }
  default:
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_get_min_denomination_ (
  const struct TALER_EXCHANGE_Keys *keys,
  struct TALER_Amount *min)
{
  bool have_min = false;
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
  {
    const struct TALER_EXCHANGE_DenomPublicKey *dk = &keys->denom_keys[i];

    if (! have_min)
    {
      *min = dk->value;
      have_min = true;
      continue;
    }
    if (1 != TALER_amount_cmp (min,
                               &dk->value))
      continue;
    *min = dk->value;
  }
  if (! have_min)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_verify_deposit_signature_ (
  const struct TALER_EXCHANGE_DepositContractDetail *dcd,
  const struct TALER_ExtensionPolicyHashP *ech,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_EXCHANGE_CoinDepositDetail *cdd,
  const struct TALER_EXCHANGE_DenomPublicKey *dki)
{
  if (GNUNET_OK !=
      TALER_wallet_deposit_verify (&cdd->amount,
                                   &dki->fees.deposit,
                                   h_wire,
                                   &dcd->h_contract_terms,
                                   &cdd->h_age_commitment,
                                   ech,
                                   &cdd->h_denom_pub,
                                   dcd->timestamp,
                                   &dcd->merchant_pub,
                                   dcd->refund_deadline,
                                   &cdd->coin_pub,
                                   &cdd->coin_sig))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING ("Invalid coin signature on /deposit request!\n");
    TALER_LOG_DEBUG ("... amount_with_fee was %s\n",
                     TALER_amount2s (&cdd->amount));
    TALER_LOG_DEBUG ("... deposit_fee was %s\n",
                     TALER_amount2s (&dki->fees.deposit));
    return GNUNET_SYSERR;
  }

  /* check coin signature */
  {
    struct TALER_CoinPublicInfo coin_info = {
      .coin_pub = cdd->coin_pub,
      .denom_pub_hash = cdd->h_denom_pub,
      .denom_sig = cdd->denom_sig,
      .h_age_commitment = cdd->h_age_commitment,
    };

    if (GNUNET_YES !=
        TALER_test_coin_valid (&coin_info,
                               &dki->key))
    {
      GNUNET_break_op (0);
      TALER_LOG_WARNING ("Invalid coin passed for /deposit\n");
      return GNUNET_SYSERR;
    }
  }

  /* Check coin does make a contribution */
  if (0 < TALER_amount_cmp (&dki->fees.deposit,
                            &cdd->amount))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING ("Deposit amount smaller than fee\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Parse account restriction in @a jrest into @a rest.
 *
 * @param jresta array of account restrictions in JSON
 * @param[out] resta_len set to length of @a resta
 * @param[out] resta account restriction array to set
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_restrictions (const json_t *jresta,
                    unsigned int *resta_len,
                    struct TALER_EXCHANGE_AccountRestriction **resta)
{
  if (! json_is_array (jresta))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  *resta_len = json_array_size (jresta);
  if (0 == *resta_len)
  {
    /* no restrictions, perfectly OK */
    *resta = NULL;
    return GNUNET_OK;
  }
  *resta = GNUNET_new_array (*resta_len,
                             struct TALER_EXCHANGE_AccountRestriction);
  for (unsigned int i = 0; i<*resta_len; i++)
  {
    const json_t *jr = json_array_get (jresta,
                                       i);
    struct TALER_EXCHANGE_AccountRestriction *ar = &(*resta)[i];
    const char *type = json_string_value (json_object_get (jr,
                                                           "type"));

    if (NULL == type)
    {
      GNUNET_break (0);
      goto fail;
    }
    if (0 == strcmp (type,
                     "deny"))
    {
      ar->type = TALER_EXCHANGE_AR_DENY;
      continue;
    }
    if (0 == strcmp (type,
                     "regex"))
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string (
          "payto_regex",
          &ar->details.regex.posix_egrep),
        GNUNET_JSON_spec_string (
          "human_hint",
          &ar->details.regex.human_hint),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_object_const (
            "human_hint_i18n",
            &ar->details.regex.human_hint_i18n),
          NULL),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (jr,
                             spec,
                             NULL, NULL))
      {
        /* bogus reply */
        GNUNET_break_op (0);
        goto fail;
      }
      ar->type = TALER_EXCHANGE_AR_REGEX;
      continue;
    }
    /* unsupported type */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
fail:
  GNUNET_free (*resta);
  *resta_len = 0;
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_parse_accounts (
  const struct TALER_MasterPublicKeyP *master_pub,
  const json_t *accounts,
  unsigned int was_length,
  struct TALER_EXCHANGE_WireAccount was[static was_length])
{
  memset (was,
          0,
          sizeof (struct TALER_EXCHANGE_WireAccount) * was_length);
  GNUNET_assert (was_length ==
                 json_array_size (accounts));
  for (unsigned int i = 0;
       i<was_length;
       i++)
  {
    struct TALER_EXCHANGE_WireAccount *wa = &was[i];
    const json_t *credit_restrictions;
    const json_t *debit_restrictions;
    struct GNUNET_JSON_Specification spec_account[] = {
      GNUNET_JSON_spec_string ("payto_uri",
                               &wa->payto_uri),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_string ("conversion_url",
                                 &wa->conversion_url),
        NULL),
      GNUNET_JSON_spec_array_const ("credit_restrictions",
                                    &credit_restrictions),
      GNUNET_JSON_spec_array_const ("debit_restrictions",
                                    &debit_restrictions),
      GNUNET_JSON_spec_fixed_auto ("master_sig",
                                   &wa->master_sig),
      GNUNET_JSON_spec_end ()
    };
    json_t *account;

    account = json_array_get (accounts,
                              i);
    if (GNUNET_OK !=
        GNUNET_JSON_parse (account,
                           spec_account,
                           NULL, NULL))
    {
      /* bogus reply */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    {
      char *err;

      err = TALER_payto_validate (wa->payto_uri);
      if (NULL != err)
      {
        GNUNET_break_op (0);
        GNUNET_free (err);
        return GNUNET_SYSERR;
      }
    }

    if ( (NULL != master_pub) &&
         (GNUNET_OK !=
          TALER_exchange_wire_signature_check (wa->payto_uri,
                                               wa->conversion_url,
                                               debit_restrictions,
                                               credit_restrictions,
                                               master_pub,
                                               &wa->master_sig)) )
    {
      /* bogus reply */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if ( (GNUNET_OK !=
          parse_restrictions (credit_restrictions,
                              &wa->credit_restrictions_length,
                              &wa->credit_restrictions)) ||
         (GNUNET_OK !=
          parse_restrictions (debit_restrictions,
                              &wa->debit_restrictions_length,
                              &wa->debit_restrictions)) )
    {
      /* bogus reply */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }       /* end 'for all accounts */
  return GNUNET_OK;
}


void
TALER_EXCHANGE_free_accounts (
  unsigned int was_len,
  struct TALER_EXCHANGE_WireAccount was[static was_len])
{
  for (unsigned int i = 0; i<was_len; i++)
  {
    struct TALER_EXCHANGE_WireAccount *wa = &was[i];

    GNUNET_free (wa->credit_restrictions);
    GNUNET_free (wa->debit_restrictions);
  }
}


/* end of exchange_api_common.c */
