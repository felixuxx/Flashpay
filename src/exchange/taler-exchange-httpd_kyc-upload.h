/*
  This file is part of TALER
  Copyright (C) 2019, 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-upload.h
 * @brief Handle /kyc-upload/$ID requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_KYC_UPLOAD_H
#define TALER_EXCHANGE_HTTPD_KYC_UPLOAD_H

#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Resume suspended connections, called on shutdown.
 */
void
TEH_kyc_upload_cleanup (void);


/**
 * Handle a "/kyc-upload/$ID" request.
 *
 * @param rc request context
 * @param id the ID from the URL (without "/")
 * @param[in,out] upload_data_size length of @a upload_data,
 *    to be update to reflect number of bytes remaining
 * @param upload_data upload data of the POST, if any
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_kyc_upload (struct TEH_RequestContext *rc,
                        const char *id,
                        size_t *upload_data_size,
                        const char *upload_data);


#endif
