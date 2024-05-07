/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
 * @file taler-exchange-httpd_batch-withdraw.c
 * @brief Handle /reserves/$RESERVE_PUB/batch-withdraw requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler-exchange-httpd.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_withdraw.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_util.h"


enum GNUNET_DB_QueryStatus
TEH_legitimization_check (
  struct TALER_EXCHANGEDB_KycStatus *kyc,
  struct MHD_Connection *connection,
  MHD_RESULT *mhd_ret,
  enum TALER_KYCLOGIC_KycTriggerEvent et,
  const struct TALER_PaytoHashP *h_payto,
  const union TALER_AccountPublicKeyP *account_pub,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls)
{
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs = NULL;
  struct TALER_KYCLOGIC_KycRule *requirement;
  enum GNUNET_DB_QueryStatus qs;

  {
    json_t *jrules;

    qs = TEH_plugin->get_kyc_rules (TEH_plugin->cls,
                                    h_payto,
                                    &jrules);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      {
        GNUNET_break (0);
        *mhd_ret = TALER_MHD_reply_with_ec (connection,
                                            TALER_EC_GENERIC_DB_FETCH_FAILED,
                                            "get_kyc_rules");
      }
      return qs;
    }
    if (qs > 0)
    {
      lrs = TALER_KYCLOGIC_rules_parse (jrules);
      GNUNET_break (NULL != lrs);
      /* Fall back to default rules on parse error! */
      json_decref (jrules);
    }
  }

  qs = TALER_KYCLOGIC_kyc_test_required (
    et,
    h_payto,
    lrs,
    ai,
    ai_cls,
    &requirement);
  if (qs < 0)
  {
    TALER_KYCLOGIC_rules_free (lrs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_ec (connection,
                                          TALER_EC_GENERIC_DB_FETCH_FAILED,
                                          "kyc_test_required");
    }
    return qs;
  }

  if (NULL == requirement)
  {
    TALER_KYCLOGIC_rules_free (lrs);
    kyc->ok = true;
    return qs;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC requirement is %s\n",
              TALER_KYCLOGIC_rule2s (requirement));
  kyc->ok = false;
  {
    json_t *jrule;

    jrule = TALER_KYCLOGIC_rule2j (requirement);
    qs = TEH_plugin->trigger_kyc_rule_for_account (
      TEH_plugin->cls,
      h_payto,
      account_pub,
      jrule,
      TALER_KYCLOGIC_rule2priority (requirement),
      &kyc->requirement_row);
    json_decref (jrule);
  }
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_ec (connection,
                                        TALER_EC_GENERIC_DB_STORE_FAILED,
                                        "trigger_kyc_rule_for_account");
  }
  TALER_KYCLOGIC_rules_free (lrs);
  return qs;
}


/**
 * Closure for #withdraw_amount_cb().
 */
struct WithdrawContext
{
  /**
   * Total amount being withdrawn now.
   */
  const struct TALER_Amount *withdraw_total;

  /**
   * Current time.
   */
  struct GNUNET_TIME_Timestamp now;

  /**
   * Account we are checking against.
   */
  struct TALER_PaytoHashP h_payto;
};


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
 * @param cb_cls closure for @a cb, of type struct AgeWithdrawContext
 */
static void
withdraw_amount_cb (
  void *cls,
  struct GNUNET_TIME_Absolute limit,
  TALER_EXCHANGEDB_KycAmountCallback cb,
  void *cb_cls)
{
  struct WithdrawContext *wc = cls;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Signaling amount %s for KYC check during age-withdrawal\n",
              TALER_amount2s (wc->withdraw_total));
  if (GNUNET_OK !=
      cb (cb_cls,
          wc->withdraw_total,
          wc->now.abs_time))
    return;
  qs = TEH_plugin->select_withdraw_amounts_for_kyc_check (
    TEH_plugin->cls,
    &wc->h_payto,
    limit,
    cb,
    cb_cls);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Got %d additional transactions for this age-withdrawal and limit %llu\n",
              qs,
              (unsigned long long) limit.abs_value_us);
  GNUNET_break (qs >= 0);
}


enum GNUNET_DB_QueryStatus
TEH_withdraw_kyc_check (
  struct TALER_EXCHANGEDB_KycStatus *kyc,
  struct MHD_Connection *connection,
  MHD_RESULT *mhd_ret,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *withdraw_total,
  struct GNUNET_TIME_Timestamp now
  )
{
  enum GNUNET_DB_QueryStatus qs;
  struct WithdrawContext wc = {
    .withdraw_total = withdraw_total,
    .now = now
  };
  union TALER_AccountPublicKeyP account_pub = {
    .reserve_pub = *reserve_pub
  };

  /* Check if the money came from a wire transfer */
  qs = TEH_plugin->reserves_get_origin (
    TEH_plugin->cls,
    reserve_pub,
    &wc.h_payto);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "reserves_get_origin");
    return qs;
  }
  /* If _no_ results, reserve was created by merge,
     in which case no KYC check is required as the
     merge already did that. */
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return qs;
  return TEH_legitimization_check (
    kyc,
    connection,
    mhd_ret,
    TALER_KYCLOGIC_KYC_TRIGGER_AGE_WITHDRAW,
    &wc.h_payto,
    &account_pub,
    &withdraw_amount_cb,
    &wc);
}
