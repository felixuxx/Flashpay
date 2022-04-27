/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_contracts_get.c
 * @brief Implementation of the /contracts/ GET request
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A Contract Get Handle
 */
struct TALER_EXCHANGE_ContractsGetHandle
{

  /**
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_ContractGetCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Private key needed to decrypt the contract.
   */
  struct TALER_ContractDiffiePrivateP contract_priv;

  /**
   * Public key matching @e contract_priv.
   */
  struct TALER_ContractDiffiePublicP cpub;

};


/**
 * Function called when we're done processing the
 * HTTP /track/transaction request.
 *
 * @param cls the `struct TALER_EXCHANGE_ContractsGetHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_contract_get_finished (void *cls,
                              long response_code,
                              const void *response)
{
  struct TALER_EXCHANGE_ContractsGetHandle *cgh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_ContractGetResponse dr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  cgh->job = NULL;
  switch (response_code)
  {
  case 0:
    dr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      void *econtract;
      size_t econtract_size;
      struct TALER_PurseContractSignatureP econtract_sig;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("purse_pub",
                                     &dr.details.success.purse_pub),
        GNUNET_JSON_spec_fixed_auto ("econtract_sig",
                                     &econtract_sig),
        GNUNET_JSON_spec_varsize ("econtract",
                                  &econtract,
                                  &econtract_size),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      if (GNUNET_OK !=
          TALER_wallet_econtract_upload_verify (
            econtract,
            econtract_size,
            &cgh->cpub,
            &dr.details.success.purse_pub,
            &econtract_sig))
      {
        GNUNET_break (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_CONTRACTS_SIGNATURE_INVALID;
        GNUNET_JSON_parse_free (spec);
        break;
      }
      dr.details.success.econtract = econtract;
      dr.details.success.econtract_size = econtract_size;
      cgh->cb (cgh->cb_cls,
               &dr);
      GNUNET_JSON_parse_free (spec);
      TALER_EXCHANGE_contract_get_cancel (cgh);
      return;
    }
  case MHD_HTTP_BAD_REQUEST:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Exchange does not know about transaction;
       we should pass the reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange GET contracts\n",
                (unsigned int) response_code,
                (int) dr.hr.ec);
    GNUNET_break_op (0);
    break;
  }
  cgh->cb (cgh->cb_cls,
           &dr);
  TALER_EXCHANGE_contract_get_cancel (cgh);
}


struct TALER_EXCHANGE_ContractsGetHandle *
TALER_EXCHANGE_contract_get (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  TALER_EXCHANGE_ContractGetCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ContractsGetHandle *cgh;
  CURL *eh;
  char arg_str[sizeof (cgh->cpub) * 2 + 48];

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  cgh = GNUNET_new (struct TALER_EXCHANGE_ContractsGetHandle);
  cgh->exchange = exchange;
  cgh->cb = cb;
  cgh->cb_cls = cb_cls;
  GNUNET_CRYPTO_ecdhe_key_get_public (&contract_priv->ecdhe_priv,
                                      &cgh->cpub.ecdhe_pub);
  {
    char cpub_str[sizeof (cgh->cpub) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (&cgh->cpub,
                                         sizeof (cgh->cpub),
                                         cpub_str,
                                         sizeof (cpub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/contracts/%s",
                     cpub_str);
  }

  cgh->url = TEAH_path_to_url (exchange,
                               arg_str);
  if (NULL == cgh->url)
  {
    GNUNET_free (cgh);
    return NULL;
  }
  cgh->contract_priv = *contract_priv;

  eh = TALER_EXCHANGE_curl_easy_get_ (cgh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (cgh->url);
    GNUNET_free (cgh);
    return NULL;
  }
  cgh->job = GNUNET_CURL_job_add (TEAH_handle_to_context (exchange),
                                  eh,
                                  &handle_contract_get_finished,
                                  cgh);
  return cgh;
}


void
TALER_EXCHANGE_contract_get_cancel (
  struct TALER_EXCHANGE_ContractsGetHandle *cgh)
{
  if (NULL != cgh->job)
  {
    GNUNET_CURL_job_cancel (cgh->job);
    cgh->job = NULL;
  }
  GNUNET_free (cgh->url);
  GNUNET_free (cgh);
}


/* end of exchange_api_contracts_get.c */
