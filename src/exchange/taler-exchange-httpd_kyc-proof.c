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
 * @file taler-exchange-httpd_kyc-proof.c
 * @brief Handle request for proof for KYC check.
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
#include "taler-exchange-httpd_kyc-proof.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Context for the proof.
 */
struct KycProofContext
{

};


/**
 * Function implementing database transaction to check proof's KYC status.
 * Runs the transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct KycProofContext *`
 * @param connection MHD proof which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
proof_kyc_check (void *cls,
                 struct MHD_Connection *connection,
                 MHD_RESULT *mhd_ret)
{
  struct KycProofContext *kpc = cls;

  (void) kpc; // FIXME: do work here!
  return -2;
}


MHD_RESULT
TEH_handler_kyc_proof (
  struct TEH_RequestContext *rc,
  const char *const args[])
{
  struct KycProofContext kpc;
  MHD_RESULT res;
  enum GNUNET_GenericReturnValue ret;
  unsigned long long payment_target_uuid;
  char dummy;

  if (1 !=
      sscanf (args[0],
              "%llu%c",
              &payment_target_uuid,
              &dummy))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "payment_target_uuid");
  }

  if (1 || (TEH_KYC_NONE == TEH_kyc_config.mode))
    return TALER_MHD_reply_static (
      rc->connection,
      MHD_HTTP_NO_CONTENT,
      NULL,
      NULL,
      0);
  ret = TEH_DB_run_transaction (rc->connection,
                                "check proof kyc",
                                &res,
                                &proof_kyc_check,
                                &kpc);
  if (GNUNET_SYSERR == ret)
    return res;
  return TALER_MHD_REPLY_JSON_PACK (
    rc->connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_uint64 ("42",
                             42));
}


/* end of taler-exchange-httpd_kyc-proof.c */
