/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file taler-exchange-httpd_management_post_keys.c
 * @brief Handle request to POST /management/keys
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
#include "taler_signatures.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_management.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Denomination signature provided.
 */
struct DenomSig
{
  /**
   * Hash of a denomination public key.
   */
  struct GNUNET_HashCode h_denom_pub;

  /**
   * Master signature for the @e h_denom_pub.
   */
  struct TALER_MasterSignatureP master_sig;

};


/**
 * Signkey signature provided.
 */
struct SigningSig
{
  /**
   * Online signing key of the exchange.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Master signature for the @e exchange_pub.
   */
  struct TALER_MasterSignatureP master_sig;

};


/**
 * Closure for the #add_keys transaction.
 */
struct AddKeysContext
{

  /**
   * Array of @e nd_sigs denomination signatures.
   */
  struct DenomSig *d_sigs;

  /**
   * Array of @e ns_sigs signkey signatures.
   */
  struct SigningSig *s_sigs;

  /**
   * Length of the d_sigs array.
   */
  unsigned int nd_sigs;

  /**
   * Length of the n_sigs array.
   */
  unsigned int ns_sigs;

};


/**
 * Function implementing database transaction to add offline signing keys.
 * Runs the transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct AddKeysContext`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
add_keys (void *cls,
          struct MHD_Connection *connection,
          struct TALER_EXCHANGEDB_Session *session,
          MHD_RESULT *mhd_ret)
{
  struct AddKeysContext *akc = cls;

  /* activate all denomination keys */
  for (unsigned int i = 0; i<akc->nd_sigs; i++)
  {
    enum GNUNET_DB_QueryStatus qs;
    bool is_active = false;
    struct TALER_EXCHANGEDB_DenominationKeyMetaData meta;
    struct TALER_DenominationPublicKey denom_pub;

    /* For idempotency, check if the key is already active */
    qs = TEH_plugin->lookup_denomination_key (
      TEH_plugin->cls,
      session,
      &akc->d_sigs[i].h_denom_pub,
      &meta);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "lookup denomination key");
      return qs;
    }
    if (0 == qs)
    {
      if (GNUNET_OK !=
          TEH_keys_load_fees (&akc->d_sigs[i].h_denom_pub,
                              &denom_pub,
                              &meta))
      {
        *mhd_ret = TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_NOT_FOUND,
          TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN,
          GNUNET_h2s (&akc->d_sigs[i].h_denom_pub));
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
    }
    else
    {
      is_active = true;
    }

    /* check signature is valid */
    {
      if (GNUNET_OK !=
          TALER_exchange_offline_denom_validity_verify (
            &akc->d_sigs[i].h_denom_pub,
            meta.start,
            meta.expire_withdraw,
            meta.expire_deposit,
            meta.expire_legal,
            &meta.value,
            &meta.fee_withdraw,
            &meta.fee_deposit,
            &meta.fee_refresh,
            &meta.fee_refund,
            &TEH_master_public_key,
            &akc->d_sigs[i].master_sig))
      {
        GNUNET_break_op (0);
        *mhd_ret = TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_FORBIDDEN,
          TALER_EC_EXCHANGE_MANAGEMENT_KEYS_DENOMKEY_ADD_SIGNATURE_INVALID,
          GNUNET_h2s (&akc->d_sigs[i].h_denom_pub));
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
    }
    if (is_active)
      continue; /* skip, already known */
    qs = TEH_plugin->add_denomination_key (
      TEH_plugin->cls,
      session,
      &akc->d_sigs[i].h_denom_pub,
      &denom_pub,
      &meta,
      &akc->d_sigs[i].master_sig);
    GNUNET_CRYPTO_rsa_public_key_free (denom_pub.rsa_public_key);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "activate denomination key");
      return qs;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Added offline signature for denomination `%s'\n",
                GNUNET_h2s (&akc->d_sigs[i].h_denom_pub));
    GNUNET_assert (0 != qs);
  }


  for (unsigned int i = 0; i<akc->ns_sigs; i++)
  {
    enum GNUNET_DB_QueryStatus qs;
    bool is_active = false;
    struct TALER_EXCHANGEDB_SignkeyMetaData meta;

    qs = TEH_plugin->lookup_signing_key (
      TEH_plugin->cls,
      session,
      &akc->s_sigs[i].exchange_pub,
      &meta);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "lookup signing key");
      return qs;
    }
    if (0 == qs)
    {
      if (GNUNET_OK !=
          TEH_keys_get_timing (&akc->s_sigs[i].exchange_pub,
                               &meta))
      {
        /* For idempotency, check if the key is already active */
        *mhd_ret = TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_NOT_FOUND,
          TALER_EC_EXCHANGE_MANAGEMENT_KEYS_SIGNKEY_UNKNOWN,
          TALER_B2S (&akc->s_sigs[i].exchange_pub));
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
    }
    else
    {
      is_active = true; /* if we pass, it's active! */
    }

    /* check signature is valid */
    {
      if (GNUNET_OK !=
          TALER_exchange_offline_signkey_validity_verify (
            &akc->s_sigs[i].exchange_pub,
            meta.start,
            meta.expire_sign,
            meta.expire_legal,
            &TEH_master_public_key,
            &akc->s_sigs[i].master_sig))
      {
        GNUNET_break_op (0);
        *mhd_ret = TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_FORBIDDEN,
          TALER_EC_EXCHANGE_MANAGEMENT_KEYS_SIGNKEY_ADD_SIGNATURE_INVALID,
          GNUNET_h2s (&akc->d_sigs[i].h_denom_pub));
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
    }
    if (is_active)
      continue; /* skip, already known */
    qs = TEH_plugin->activate_signing_key (
      TEH_plugin->cls,
      session,
      &akc->s_sigs[i].exchange_pub,
      &meta,
      &akc->s_sigs[i].master_sig);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "activate signing key");
      return qs;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Added offline signature for signing key `%s'\n",
                TALER_B2S (&akc->s_sigs[i].exchange_pub));
    GNUNET_assert (0 != qs);
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT; /* only 'success', so >=0, matters here */
}


MHD_RESULT
TEH_handler_management_post_keys (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct AddKeysContext akc;
  json_t *denom_sigs;
  json_t *signkey_sigs;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("denom_sigs",
                           &denom_sigs),
    GNUNET_JSON_spec_json ("signkey_sigs",
                           &signkey_sigs),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_DB_QueryStatus qs;
  bool ok;
  MHD_RESULT ret;

  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
      return MHD_NO; /* hard failure */
    if (GNUNET_NO == res)
      return MHD_YES; /* failure */
  }
  if (! (json_is_array (denom_sigs) &&
         json_is_array (signkey_sigs)) )
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "array expected for denom_sigs and signkey_sigs");
  }
  akc.nd_sigs = json_array_size (denom_sigs);
  akc.d_sigs = GNUNET_new_array (akc.nd_sigs,
                                 struct DenomSig);
  ok = true;
  for (unsigned int i = 0; i<akc.nd_sigs; i++)
  {
    struct DenomSig *d = &akc.d_sigs[i];
    struct GNUNET_JSON_Specification ispec[] = {
      GNUNET_JSON_spec_fixed_auto ("master_sig",
                                   &d->master_sig),
      GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                   &d->h_denom_pub),
      GNUNET_JSON_spec_end ()
    };
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     json_array_get (denom_sigs,
                                                     i),
                                     ispec);
    if (GNUNET_SYSERR == res)
    {
      ret = MHD_NO; /* hard failure */
      ok = false;
      break;
    }
    if (GNUNET_NO == res)
    {
      ret = MHD_YES;
      ok = false;
      break;
    }
  }
  if (! ok)
  {
    GNUNET_free (akc.d_sigs);
    return ret;
  }
  akc.ns_sigs = json_array_size (signkey_sigs);
  akc.s_sigs = GNUNET_new_array (akc.ns_sigs,
                                 struct SigningSig);
  for (unsigned int i = 0; i<akc.ns_sigs; i++)
  {
    struct SigningSig *s = &akc.s_sigs[i];
    struct GNUNET_JSON_Specification ispec[] = {
      GNUNET_JSON_spec_fixed_auto ("master_sig",
                                   &s->master_sig),
      GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                   &s->exchange_pub),
      GNUNET_JSON_spec_end ()
    };
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     json_array_get (signkey_sigs,
                                                     i),
                                     ispec);
    if (GNUNET_SYSERR == res)
    {
      ret = MHD_NO; /* hard failure */
      ok = false;
      break;
    }
    if (GNUNET_NO == res)
    {
      ret = MHD_YES;
      ok = false;
      break;
    }
  }
  if (! ok)
  {
    GNUNET_free (akc.d_sigs);
    GNUNET_free (akc.s_sigs);
    return ret;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received %u denomination and %u signing key signatures\n",
              akc.nd_sigs,
              akc.ns_sigs);
  qs = TEH_DB_run_transaction (connection,
                               "add keys",
                               &ret,
                               &add_keys,
                               &akc);
  GNUNET_free (akc.d_sigs);
  GNUNET_free (akc.s_sigs);
  if (qs < 0)
    return ret;
  TEH_keys_update_states ();
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_management_management_post_keys.c */
