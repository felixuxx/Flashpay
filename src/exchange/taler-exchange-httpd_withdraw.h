/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file taler-exchange-httpd_withdraw.h
 * @brief common code for withdraw requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_WITHDRAW_H
#define TALER_EXCHANGE_HTTPD_WITHDRAW_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Do legitimization check.
 *
 * @param[out] kyc set to kyc status
 * @param[in,out] connection used to return hard errors
 * @param[out] mhd_ret set if errors were returned
 *     (only on hard error)
 * @param et type of event we are checking
 * @param ai callback to get amounts involved historically
 * @param ai_cls closure for @a ai
 * @return transaction status, error will have been
 *   queued if transaction status is set to hard error
 */
enum GNUNET_DB_QueryStatus
TEH_legitimization_check (
  struct TALER_EXCHANGEDB_KycStatus *kyc,
  struct MHD_Connection *connection,
  MHD_RESULT *mhd_ret,
  enum TALER_KYCLOGIC_KycTriggerEvent et,
  const struct TALER_PaytoHashP *h_payto,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls);


/**
 * Do legitimization check for withdrawing @a withdraw_total
 * from @a reserve_pub at time @a now.
 *
 * @param[out] kyc set to kyc status
 * @param[in,out] connection used to return hard errors
 * @param[out] mhd_ret set if errors were returned
 *     (only on hard error)
 * @param reserve_pub reserve from which we withdraw
 * @param withdraw_total how much are being withdrawn
 * @param now current time
 * @return transaction status, error will have been
 *   queued if transaction status is set to hard error
 */
enum GNUNET_DB_QueryStatus
TEH_withdraw_kyc_check (
  struct TALER_EXCHANGEDB_KycStatus *kyc,
  struct MHD_Connection *connection,
  MHD_RESULT *mhd_ret,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *withdraw_total,
  struct GNUNET_TIME_Timestamp now);

#endif
