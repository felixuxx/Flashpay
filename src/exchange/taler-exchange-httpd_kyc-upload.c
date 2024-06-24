/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-upload.c
 * @brief Handle /kyc-upload/$ID request
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler-exchange-httpd_kyc-upload.h"


/**
 * Context used for processing the KYC upload req
 */
struct UploadContext
{
  struct MHD_PostProcessor *pp;
};


/**
 * Function called to clean up upload context.
 */
static void
upload_cleaner (struct TEH_RequestContext *rc)
{
  struct UploadContext *uc = rc->rh_ctx;

  GNUNET_free (uc);
}


MHD_RESULT
TEH_handler_kyc_upload (struct TEH_RequestContext *rc,
                        const char *id,
                        size_t *upload_data_size,
                        const char *upload_data)
{
  struct UploadContext *uc = rc->rh_ctx;

  if (NULL == uc)
  {
    uc = GNUNET_new (struct UploadContext);
    rc->rh_ctx = uc;
    rc->rh_cleaner = &upload_cleaner;
  }
  return MHD_NO;
}
