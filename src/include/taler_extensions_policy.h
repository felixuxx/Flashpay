/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */
/**
 * @file include/taler_extensions_policy.h
 * @brief Interface for policy extensions
 * @author Özgür Kesim
 */
#ifndef TALER_EXTENSIONS_POLICY_H
#define TALER_EXTENSIONS_POLICY_H

#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"

/*
 * @brief Describes the states of fulfillment of a policy bound to a deposit
 */
enum TALER_PolicyFulfillmentState
{
  /* General error state of an fulfillment. */
  TALER_PolicyFulfillmentFailure = 0,

  /* The policy is not yet ready due to insufficient funding. More deposits are
   * necessary for it to become ready . */
  TALER_PolicyFulfillmentInsufficient = 1,

  /* The policy is funded and ready, pending */
  TALER_PolicyFulfillmentReady = 2,

  /* Policy is provably fulfilled. */
  TALER_PolicyFulfillmentSuccess = 3,

  /* Policy fulfillment has timed out */
  TALER_PolicyFulfillmentTimeout = 4,

  TALER_PolicyFulfillmentStateCount = TALER_PolicyFulfillmentTimeout + 1
};


/*
 * @brief Returns a string representation of the state of a policy fulfillment
 */
const char *
TALER_policy_fulfillment_state_str (enum TALER_PolicyFulfillmentState state);


/* @brief Details of a policy for a deposit request */
struct TALER_PolicyDetails
{
  /* Hash code that should be used for the .policy_hash_code field when
   * this policy is saved in the policy_details table. */
  struct GNUNET_HashCode hash_code;

  /* Content of the policy in its original JSON form */
  json_t *policy_json;

  /* When the deadline is met and the policy is still in "Ready" state,
   * a timeout-handler will transfer the amount
   *    (total_amount - policy_fee - refreshable_amount)
   * to the payto-URI from the corresponding deposit.  The value
   * amount_refreshable will be refreshable by the owner of the
   * associated deposits's coins */
  struct GNUNET_TIME_Timestamp deadline;

  /* The amount to which this policy commits to. It must be at least as
   * large as @e policy_fee. */
  struct TALER_Amount commitment;

  /* The total sum of contributions from coins so far to fund this
   * policy.  It must be at least as large as @commitment in order to be
   * sufficiently funded. */
  struct TALER_Amount accumulated_total;

  /* The fee from the exchange for handling the policy. It is due when
   * the state changes to Timeout or Success. */
  struct TALER_Amount policy_fee;

  /* The amount that will be transferred to the payto-URIs from the
   * corresponding deposits when the fulfillment state changes to Timeout
   * or Success.  Note that a fulfillment handler can alter this upon
   * arrival of a proof of fulfillment. The remaining amount
   * (accumulated_amount - policy_amount - transferable_amount) */
  struct TALER_Amount transferable_amount;

  /* The state of fulfillment of a policy.
   * - If the state is Insufficient, the client is required to call
   *   /deposit -maybe multiple times- with enough coins and the same
   *   policy details in order to reach the required amount. The state is
   *   then changed to Ready.
   * - If the state changes to Timeout or Success, a handler will transfer
   *   the amount (total_amount - policy_fee - refreshable_amount) to the
   *   payto-URI from the corresponding deposit.  The value
   *   amount_refreshable will be refreshable by the owner of the
   *   associated deposits's coins.  */
  enum TALER_PolicyFulfillmentState fulfillment_state;

  /* If there is a proof of fulfillment, the row ID from the
   * policy_fulfillment table */
  uint64_t policy_fulfillment_id;
  bool no_policy_fulfillment_id;
};

/*
 * @brief All information required for the database transaction when handling a
 * proof of fulfillment request.
 */
struct TALER_PolicyFulfillmentTransactionData
{
  /* The incoming proof, provided by a client */
  const json_t *proof;

  /* The Hash of the proof */
  struct GNUNET_HashCode h_proof;

  /* The timestamp of retrieval of the proof */
  struct GNUNET_TIME_Timestamp timestamp;

  /* The ID of the proof in the policy_fulfillment table.  Will be set
   * during the transaction.  Needed to fill the table
   * policy_details_fulfillments. */
  uint64_t fulfillment_id;

  /* The list of policy details.  Will be updated by the policy handler */
  struct TALER_PolicyDetails *details;
  size_t details_count;
};


/*
 * @brief Extracts policy details from the deposit's policy options and the policy extensions
 *
 * @param[in]  policy_options JSON of the policy options from a deposit request
 * @param[out] details On GNUNET_OK, the parsed details
 * @param[out] error_hint On GNUNET_SYSERR, will contain a hint for the reason why it failed
 * @return GNUNET_OK on success, GNUNET_NO, when no extension was found. GNUNET_SYSERR when the JSON was
 * invalid, with *error_hint maybe non-NULL.
 */
enum GNUNET_GenericReturnValue
TALER_extensions_create_policy_details (
  const json_t *policy_options,
  struct TALER_PolicyDetails *details,
  const char **error_hint);


/*
 * ================================
 * Merchant refund policy
 * ================================
 */
struct TALER_ExtensionPolicyMerchantRefundPolicyConfig
{
  struct GNUNET_TIME_Relative max_timeout;
};

/*
 * ================================
 * Brandt-Vickrey Auctions policy
 * ================================
 */
/*
 * @brief Configuration for Brandt-Vickrey auctions policy
 */
struct TALER_ExtensionPolicyBrandtVickreyAuctionConfig
{
  uint16_t max_bidders;
  uint16_t max_prices;
  struct TALER_Amount auction_fee;
};


/*
 * ================================
 * Escrowed Payments policy
 * ================================
 */
/*
 * @brief Configuration for escrowed payments policy
 */
struct TALER_ExtensionPolicyEscrowedPaymentsConfig
{
  struct GNUNET_TIME_Relative max_timeout;
};

#endif
