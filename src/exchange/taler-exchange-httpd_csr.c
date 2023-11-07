/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @author Christian Grothoff
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
TEH_handler_csr_melt (struct TEH_RequestContext *rc,
                      const json_t *root,
                      const char *const args[])
{
  struct TALER_RefreshMasterSecretP rms;
  unsigned int csr_requests_num;
  const json_t *csr_requests;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("rms",
                                 &rms),
    GNUNET_JSON_spec_array_const ("nks",
                                  &csr_requests),
    GNUNET_JSON_spec_end ()
  };
  enum TALER_ErrorCode ec;
  struct TEH_DenominationKey *dk;

  (void) args;
  /* parse input */
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (rc->connection,
                                     root,
                                     spec);
    if (GNUNET_OK != res)
      return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  csr_requests_num = json_array_size (csr_requests);
  if ( (TALER_MAX_FRESH_COINS <= csr_requests_num) ||
       (0 == csr_requests_num) )
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      rc->connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_EXCHANGE_GENERIC_NEW_DENOMS_ARRAY_SIZE_EXCESSIVE,
      NULL);
  }

  {
    struct GNUNET_CRYPTO_BlindingInputValues ewvs[csr_requests_num];
    {
      struct GNUNET_CRYPTO_CsSessionNonce nonces[csr_requests_num];
      struct TALER_DenominationHashP denom_pub_hashes[csr_requests_num];
      struct TEH_CsDeriveData cdds[csr_requests_num];
      struct GNUNET_CRYPTO_CSPublicRPairP r_pubs[csr_requests_num];

      for (unsigned int i = 0; i < csr_requests_num; i++)
      {
        uint32_t coin_off;
        struct TALER_DenominationHashP *denom_pub_hash = &denom_pub_hashes[i];
        struct GNUNET_JSON_Specification csr_spec[] = {
          GNUNET_JSON_spec_uint32 ("coin_offset",
                                   &coin_off),
          GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                       denom_pub_hash),
          GNUNET_JSON_spec_end ()
        };
        enum GNUNET_GenericReturnValue res;

        res = TALER_MHD_parse_json_array (rc->connection,
                                          csr_requests,
                                          csr_spec,
                                          i,
                                          -1);
        if (GNUNET_OK != res)
        {
          return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
        }
        TALER_cs_refresh_nonce_derive (&rms,
                                       coin_off,
                                       &nonces[i]);
      }

      for (unsigned int i = 0; i < csr_requests_num; i++)
      {
        const struct GNUNET_CRYPTO_CsSessionNonce *nonce = &nonces[i];
        const struct TALER_DenominationHashP *denom_pub_hash =
          &denom_pub_hashes[i];

        ewvs[i].cipher = GNUNET_CRYPTO_BSA_CS;
        /* check denomination referenced by denom_pub_hash */
        {
          struct TEH_KeyStateHandle *ksh;

          ksh = TEH_keys_get_state ();
          if (NULL == ksh)
          {
            return TALER_MHD_reply_with_error (rc->connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                               NULL);
          }
          dk = TEH_keys_denomination_by_hash_from_state (ksh,
                                                         denom_pub_hash,
                                                         NULL,
                                                         NULL);
          if (NULL == dk)
          {
            return TEH_RESPONSE_reply_unknown_denom_pub_hash (
              rc->connection,
              &denom_pub_hash[i]);
          }
          if (GNUNET_TIME_absolute_is_past (dk->meta.expire_withdraw.abs_time))
          {
            /* This denomination is past the expiration time for withdraws/refreshes*/
            return TEH_RESPONSE_reply_expired_denom_pub_hash (
              rc->connection,
              denom_pub_hash,
              TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
              "csr-melt");
          }
          if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
          {
            /* This denomination is not yet valid, no need to check
               for idempotency! */
            return TEH_RESPONSE_reply_expired_denom_pub_hash (
              rc->connection,
              denom_pub_hash,
              TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
              "csr-melt");
          }
          if (dk->recoup_possible)
          {
            /* This denomination has been revoked */
            return TEH_RESPONSE_reply_expired_denom_pub_hash (
              rc->connection,
              denom_pub_hash,
              TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
              "csr-melt");
          }
          if (GNUNET_CRYPTO_BSA_CS !=
              dk->denom_pub.bsign_pub_key->cipher)
          {
            /* denomination is valid but not for CS */
            return TEH_RESPONSE_reply_invalid_denom_cipher_for_operation (
              rc->connection,
              denom_pub_hash);
          }
        }
        cdds[i].h_denom_pub = denom_pub_hash;
        cdds[i].nonce = nonce;
      } /* for (i) */
      ec = TEH_keys_denomination_cs_batch_r_pub (csr_requests_num,
                                                 cdds,
                                                 true,
                                                 r_pubs);
      if (TALER_EC_NONE != ec)
      {
        GNUNET_break (0);
        return TALER_MHD_reply_with_ec (rc->connection,
                                        ec,
                                        NULL);
      }
      for (unsigned int i = 0; i < csr_requests_num; i++)
        ewvs[i].details.cs_values = r_pubs[i];
    } /* end scope */

    /* send response */
    {
      json_t *csr_response_ewvs;
      json_t *csr_response;

      csr_response_ewvs = json_array ();
      for (unsigned int i = 0; i < csr_requests_num; i++)
      {
        json_t *csr_obj;
        struct TALER_ExchangeWithdrawValues exw = {
          .blinding_inputs = &ewvs[i]
        };

        csr_obj = GNUNET_JSON_PACK (
          TALER_JSON_pack_exchange_withdraw_values ("ewv",
                                                    &exw));
        GNUNET_assert (NULL != csr_obj);
        GNUNET_assert (0 ==
                       json_array_append_new (csr_response_ewvs,
                                              csr_obj));
      }
      csr_response = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_array_steal ("ewvs",
                                      csr_response_ewvs));
      GNUNET_assert (NULL != csr_response);
      return TALER_MHD_reply_json_steal (rc->connection,
                                         csr_response,
                                         MHD_HTTP_OK);
    }
  }
}


MHD_RESULT
TEH_handler_csr_withdraw (struct TEH_RequestContext *rc,
                          const json_t *root,
                          const char *const args[])
{
  struct GNUNET_CRYPTO_CsSessionNonce nonce;
  struct TALER_DenominationHashP denom_pub_hash;
  struct GNUNET_CRYPTO_BlindingInputValues ewv = {
    .cipher = GNUNET_CRYPTO_BSA_CS
  };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("nonce",
                                 &nonce),
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &denom_pub_hash),
    GNUNET_JSON_spec_end ()
  };
  struct TEH_DenominationKey *dk;

  (void) args;
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (rc->connection,
                                     root,
                                     spec);
    if (GNUNET_OK != res)
      return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }

  {
    struct TEH_KeyStateHandle *ksh;

    ksh = TEH_keys_get_state ();
    if (NULL == ksh)
    {
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                         NULL);
    }
    dk = TEH_keys_denomination_by_hash_from_state (ksh,
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
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
        "csr-withdraw");
    }
    if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
    {
      /* This denomination is not yet valid, no need to check
         for idempotency! */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        rc->connection,
        &denom_pub_hash,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
        "csr-withdraw");
    }
    if (dk->recoup_possible)
    {
      /* This denomination has been revoked */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        rc->connection,
        &denom_pub_hash,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
        "csr-withdraw");
    }
    if (GNUNET_CRYPTO_BSA_CS !=
        dk->denom_pub.bsign_pub_key->cipher)
    {
      /* denomination is valid but not for CS */
      return TEH_RESPONSE_reply_invalid_denom_cipher_for_operation (
        rc->connection,
        &denom_pub_hash);
    }
  }

  /* derive r_pub */
  {
    enum TALER_ErrorCode ec;
    const struct TEH_CsDeriveData cdd = {
      .h_denom_pub = &denom_pub_hash,
      .nonce = &nonce
    };

    ec = TEH_keys_denomination_cs_r_pub (&cdd,
                                         false,
                                         &ewv.details.cs_values);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_ec (rc->connection,
                                      ec,
                                      NULL);
    }
  }
  {
    struct TALER_ExchangeWithdrawValues exw = {
      .blinding_inputs = &ewv
    };

    return TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_OK,
      TALER_JSON_pack_exchange_withdraw_values ("ewv",
                                                &exw));
  }
}


/* end of taler-exchange-httpd_csr.c */
