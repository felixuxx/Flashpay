/*
  This file is part of TALER
  Copyright (C) 2020-2023 Taler Systems SA

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
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * Master signature for the @e h_denom_pub.
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * Fee structure for this key, as per our configuration.
   */
  struct TALER_EXCHANGEDB_DenominationKeyMetaData meta;

  /**
   * The full public key.
   */
  struct TALER_DenominationPublicKey denom_pub;

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

  /**
   * Our meta data on this key.
   */
  struct TALER_EXCHANGEDB_SignkeyMetaData meta;

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
   * Our key state.
   */
  struct TEH_KeyStateHandle *ksh;

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
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
add_keys (void *cls,
          struct MHD_Connection *connection,
          MHD_RESULT *mhd_ret)
{
  struct AddKeysContext *akc = cls;

  /* activate all denomination keys */
  for (unsigned int i = 0; i<akc->nd_sigs; i++)
  {
    struct DenomSig *d = &akc->d_sigs[i];
    enum GNUNET_DB_QueryStatus qs;
    struct TALER_EXCHANGEDB_DenominationKeyMetaData meta;

    /* For idempotency, check if the key is already active */
    qs = TEH_plugin->lookup_denomination_key (
      TEH_plugin->cls,
      &d->h_denom_pub,
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
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    {
      /* FIXME: assert meta === d->meta might be good */
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Denomination key %s already active, skipping\n",
                  GNUNET_h2s (&d->h_denom_pub.hash));
      continue; /* skip, already known */
    }

    qs = TEH_plugin->add_denomination_key (
      TEH_plugin->cls,
      &d->h_denom_pub,
      &d->denom_pub,
      &d->meta,
      &d->master_sig);
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
                GNUNET_h2s (&d->h_denom_pub.hash));
    GNUNET_assert (0 != qs);
  }

  for (unsigned int i = 0; i<akc->ns_sigs; i++)
  {
    struct SigningSig *s = &akc->s_sigs[i];
    enum GNUNET_DB_QueryStatus qs;
    struct TALER_EXCHANGEDB_SignkeyMetaData meta;

    qs = TEH_plugin->lookup_signing_key (
      TEH_plugin->cls,
      &s->exchange_pub,
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
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    {
      /* FIXME: assert meta === d->meta might be good */
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Signing key %s already active, skipping\n",
                  TALER_B2S (&s->exchange_pub));
      continue;   /* skip, already known */
    }
    qs = TEH_plugin->activate_signing_key (
      TEH_plugin->cls,
      &s->exchange_pub,
      &s->meta,
      &s->master_sig);
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
                TALER_B2S (&s->exchange_pub));
    GNUNET_assert (0 != qs);
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT; /* only 'success', so >=0, matters here */
}


/**
 * Clean up state in @a akc, but do not free @a akc itself
 *
 * @param[in,out] akc state to clean up
 */
static void
cleanup_akc (struct AddKeysContext *akc)
{
  for (unsigned int i = 0; i<akc->nd_sigs; i++)
  {
    struct DenomSig *d = &akc->d_sigs[i];

    TALER_denom_pub_free (&d->denom_pub);
  }
  GNUNET_free (akc->d_sigs);
  GNUNET_free (akc->s_sigs);
}


MHD_RESULT
TEH_handler_management_post_keys (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct AddKeysContext akc = { 0 };
  const json_t *denom_sigs;
  const json_t *signkey_sigs;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("denom_sigs",
                                  &denom_sigs),
    GNUNET_JSON_spec_array_const ("signkey_sigs",
                                  &signkey_sigs),
    GNUNET_JSON_spec_end ()
  };
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
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received POST /management/keys request\n");

  akc.ksh = TEH_keys_get_state_for_management_only (); /* may start its own transaction, thus must be done here, before we run ours! */
  if (NULL == akc.ksh)
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
      "no key state (not even for management)");
  }

  akc.nd_sigs = json_array_size (denom_sigs);
  akc.d_sigs = GNUNET_new_array (akc.nd_sigs,
                                 struct DenomSig);
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
    if (GNUNET_OK != res)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failure to handle /management/keys\n");
      cleanup_akc (&akc);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }

    res = TEH_keys_load_fees (akc.ksh,
                              &d->h_denom_pub,
                              &d->denom_pub,
                              &d->meta);
    switch (res)
    {
    case GNUNET_SYSERR:
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_EXCHANGE_GENERIC_BAD_CONFIGURATION,
        GNUNET_h2s (&d->h_denom_pub.hash));
      cleanup_akc (&akc);
      return ret;
    case GNUNET_NO:
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_NOT_FOUND,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN,
        GNUNET_h2s (&d->h_denom_pub.hash));
      cleanup_akc (&akc);
      return ret;
    case GNUNET_OK:
      break;
    }
    /* check signature is valid */
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
    if (GNUNET_OK !=
        TALER_exchange_offline_denom_validity_verify (
          &d->h_denom_pub,
          d->meta.start,
          d->meta.expire_withdraw,
          d->meta.expire_deposit,
          d->meta.expire_legal,
          &d->meta.value,
          &d->meta.fees,
          &TEH_master_public_key,
          &d->master_sig))
    {
      GNUNET_break_op (0);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_MANAGEMENT_KEYS_DENOMKEY_ADD_SIGNATURE_INVALID,
        GNUNET_h2s (&d->h_denom_pub.hash));
      cleanup_akc (&akc);
      return ret;
    }
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
    if (GNUNET_OK != res)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failure to handle /management/keys\n");
      cleanup_akc (&akc);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
    res = TEH_keys_get_timing (&s->exchange_pub,
                               &s->meta);
    switch (res)
    {
    case GNUNET_SYSERR:
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_EXCHANGE_GENERIC_BAD_CONFIGURATION,
        TALER_B2S (&s->exchange_pub));
      cleanup_akc (&akc);
      return ret;
    case GNUNET_NO:
      /* For idempotency, check if the key is already active */
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_NOT_FOUND,
        TALER_EC_EXCHANGE_MANAGEMENT_KEYS_SIGNKEY_UNKNOWN,
        TALER_B2S (&s->exchange_pub));
      cleanup_akc (&akc);
      return ret;
    case GNUNET_OK:
      break;
    }

    /* check signature is valid */
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
    if (GNUNET_OK !=
        TALER_exchange_offline_signkey_validity_verify (
          &s->exchange_pub,
          s->meta.start,
          s->meta.expire_sign,
          s->meta.expire_legal,
          &TEH_master_public_key,
          &s->master_sig))
    {
      GNUNET_break_op (0);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_MANAGEMENT_KEYS_SIGNKEY_ADD_SIGNATURE_INVALID,
        TALER_B2S (&s->exchange_pub));
      cleanup_akc (&akc);
      return ret;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received %u denomination and %u signing key signatures\n",
              akc.nd_sigs,
              akc.ns_sigs);
  {
    enum GNUNET_GenericReturnValue res;

    res = TEH_DB_run_transaction (connection,
                                  "add keys",
                                  TEH_MT_REQUEST_OTHER,
                                  &ret,
                                  &add_keys,
                                  &akc);
    cleanup_akc (&akc);
    if (GNUNET_SYSERR == res)
      return ret;
  }
  TEH_keys_update_states ();
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_management_management_post_keys.c */
