/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file taler-exchange-httpd_csr.c
 * @brief Handle /csr requests
 * @author Lucien Heuzeveldt
 * @author Gian Demarmles
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_csr.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"


MHD_RESULT
TEH_handler_csr (struct TEH_RequestContext *rc,
                 const json_t *root,
                 const char *const args[])
{
  // TODO: should we have something similar to struct WithdrawContext?
  // as far as I can tell this isn't necessary because we don't have
  // other functions that the context should be passed to
  // struct CsRContext csrc;
  struct TALER_WithdrawNonce nonce;
  struct TALER_DenominationHash denom_pub_hash;
  struct TALER_DenominationCsPublicR r_pub;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed ("nonce",
                            &nonce,
                            sizeof (struct TALER_WithdrawNonce)),
    GNUNET_JSON_spec_fixed ("denom_pub_hash",
                            &denom_pub_hash,
                            sizeof (struct TALER_DenominationHash)),
    GNUNET_JSON_spec_end ()
  };
  enum TALER_ErrorCode ec;
  struct TEH_DenominationKey *dk;

  (void) args;

  memset (&nonce,
          0,
          sizeof (nonce));
  memset (&denom_pub_hash,
          0,
          sizeof (denom_pub_hash));
  memset (&r_pub,
          0,
          sizeof (r_pub));

  // parse input
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (rc->connection,
                                     root,
                                     spec);
    GNUNET_JSON_parse_free (spec);
    if (GNUNET_OK != res)
      return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }

  // check denomination referenced by denom_pub_hash
  {
    MHD_RESULT mret;
    struct TEH_KeyStateHandle *ksh;

    ksh = TEH_keys_get_state ();
    if (NULL == ksh)
    {
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                         NULL);
      return mret;
    }
    dk = TEH_keys_denomination_by_hash2 (ksh,
                                         &denom_pub_hash,
                                         NULL,
                                         NULL);
    if (NULL == dk)
    {
      return TEH_RESPONSE_reply_unknown_denom_pub_hash (
        rc->connection,
        &denom_pub_hash);
    }
    if (GNUNET_TIME_absolute_is_past (dk->meta.expire_withdraw.abs_time))
    {
      /* This denomination is past the expiration time for withdraws/refreshes*/
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        rc->connection,
        &denom_pub_hash,
        GNUNET_TIME_timestamp_get (),
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
        "CSR");
    }
    if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
    {
      /* This denomination is not yet valid, no need to check
         for idempotency! */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        rc->connection,
        &denom_pub_hash,
        GNUNET_TIME_timestamp_get (),
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
        "CSR");
    }
    if (dk->recoup_possible)
    {
      /* This denomination has been revoked */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        rc->connection,
        &denom_pub_hash,
        GNUNET_TIME_timestamp_get (),
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
        "CSR");
    }
    if (TALER_DENOMINATION_CS != dk->denom_pub.cipher)
    {
      // denomination is valid but not CS
      return TEH_RESPONSE_reply_unknown_denom_pub_hash (
        rc->connection,
        &denom_pub_hash);
    }
  }

  // derive r_pub
  ec = TALER_EC_NONE;
  r_pub = TEH_keys_denomination_cs_r_pub (&denom_pub_hash,
                                          &nonce,
                                          &ec);
  if (TALER_EC_NONE != ec)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_ec (rc->connection,
                                    ec,
                                    NULL);
  }

  // send response
  {
    MHD_RESULT ret;

    ret = TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_data_varsize ("r_pub_0",
                                     &r_pub.r_pub[0],
                                     sizeof(struct GNUNET_CRYPTO_CsRPublic)),
      GNUNET_JSON_pack_data_varsize ("r_pub_1",
                                     &r_pub.r_pub[1],
                                     sizeof(struct GNUNET_CRYPTO_CsRPublic)));
    return ret;
  }
}


/* end of taler-exchange-httpd_csr.c */
