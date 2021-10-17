/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-proof.h
 * @brief Handle /kyc-proof requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_KYC_PROOF_H
#define TALER_EXCHANGE_HTTPD_KYC_PROOF_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a "/kyc-proof" request.
 *
 * @param connection request to handle
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_kyc_proof (
  struct MHD_Connection *connection,
  ...);


#endif
