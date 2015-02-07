/*
  This file is part of TALER
  Copyright (C) 2014 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file mint/mint_api.c
 * @brief Implementation of the client interface to mint's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_mint_service.h"
#include "taler_signatures.h"


#define CURL_STRERROR(TYPE, FUNCTION, CODE)      \
 GNUNET_log (TYPE, "cURL function `%s' has failed at `%s:%d' with error: %s", \
             FUNCTION, __FILE__, __LINE__, curl_easy_strerror (CODE));



/**
 * Print JSON parsing related error information
 */
#define JSON_WARN(error)                                                \
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,                              \
                "JSON parsing failed at %s:%u: %s (%s)",                \
                __FILE__, __LINE__, error.text, error.source)

/**
 * Failsafe flag
 */
static int fail;

/**
 * Context
 */
struct TALER_MINT_Context
{
  /**
   * CURL multi handle
   */
  CURLM *multi;

  /**
   * CURL share handle
   */
  CURLSH *share;

  /**
   * Perform task handle
   */
  struct GNUNET_SCHEDULER_Task *perform_task;
};

/**
 * Type of requests we currently have
 */
enum RequestType
{
  /**
   * No request
   */
  REQUEST_TYPE_NONE,

  /**
   * Current request is to receive mint's keys
   */
  REQUEST_TYPE_KEYSGET,

  /**
   * Current request is to submit a deposit permission and get its status
   */
  REQUEST_TYPE_DEPOSIT
};


/**
 * Handle to the mint
 */
struct TALER_MINT_Handle
{
  /**
   * The context of this handle
   */
  struct TALER_MINT_Context *ctx;

  /**
   * The hostname of the mint
   */
  char *hostname;

  /**
   * The CURL handle
   */
  CURL *curl;

  /**
   * Error buffer for CURL
   */
  char emsg[CURL_ERROR_SIZE];

  /**
   * Download buffer
   */
  void *buf;

  /**
   * The currently active request
   */
  union {
    /**
     * Used to denote no request if set to NULL
     */
    void *none;

    /**
     * Denom keys get request if REQUEST_TYPE_KEYSGET
     */
    struct TALER_MINT_KeysGetHandle *keys_get;

    /**
     * Deposit request if REQUEST_TYPE_DEPOSIT
     */
    struct TALER_MINT_DepositHandle *deposit;
  } req;

  /**
   * The size of the download buffer
   */
  size_t buf_size;

  /**
   * Active request type
   */
  enum RequestType req_type;

  /**
   * The service port of the mint
   */
  uint16_t port;

  /**
   * Are we connected to the mint?
   */
  uint8_t connected;

};


/**
 * A handle to get the keys of a mint
 */
struct TALER_MINT_KeysGetHandle
{
  /**
   * The connection to mint this request handle will use
   */
  struct TALER_MINT_Handle *mint;

  /**
   * The url for this handle
   */
  char *url;

  TALER_MINT_KeysGetCallback cb;
  void *cls;

  TALER_MINT_ContinuationCallback cont_cb;
  void *cont_cls;
};


/**
 * A handle to submit a deposit permission and get its status
 */
struct TALER_MINT_DepositHandle
{
  /**
   *The connection to mint this request handle will use
   */
  struct TALER_MINT_Handle *mint;

  /**
   * The url for this handle
   */
  char *url;

  TALER_MINT_DepositResultCallback cb;
  void *cls;

  char *json_enc;

  struct curl_slist *headers;

};


/**
 * Parses the timestamp encoded as ASCII string as UNIX timstamp.
 *
 * @param abs successfully parsed timestamp will be returned thru this parameter
 * @param tstamp_enc the ASCII encoding of the timestamp
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static int
parse_timestamp (struct GNUNET_TIME_Absolute *abs, const char *tstamp_enc)
{
  unsigned long tstamp;

  if (1 != sscanf (tstamp_enc, "%lu", &tstamp))
    return GNUNET_SYSERR;
  *abs = GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get_zero_ (),
                                   GNUNET_TIME_relative_multiply
                                   (GNUNET_TIME_UNIT_SECONDS, tstamp));
  return GNUNET_OK;
}


#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)



static int
parse_json_signkey (struct TALER_MINT_SigningPublicKey **_sign_key,
                    json_t *sign_key_obj,
                    struct GNUNET_CRYPTO_EddsaPublicKey *master_key)
{
  json_t *valid_from_obj;
  json_t *valid_until_obj;
  json_t *key_obj;
  json_t *sig_obj;
  const char *valid_from_enc;
  const char *valid_until_enc;
  const char *key_enc;
  const char *sig_enc;
  struct TALER_MINT_SigningPublicKey *sign_key;
  struct TALER_MINT_SignKeyIssue sign_key_issue;
  struct GNUNET_CRYPTO_EddsaSignature sig;
  struct GNUNET_TIME_Absolute valid_from;
  struct GNUNET_TIME_Absolute valid_until;

  EXITIF (JSON_OBJECT != json_typeof (sign_key_obj));
  EXITIF (NULL == (valid_from_obj = json_object_get (sign_key_obj,
                                                     "stamp_start")));
  EXITIF (NULL == (valid_until_obj = json_object_get (sign_key_obj,
                                                     "stamp_expire")));
  EXITIF (NULL == (key_obj = json_object_get (sign_key_obj, "key")));
  EXITIF (NULL == (sig_obj = json_object_get (sign_key_obj, "master_sig")));
  EXITIF (NULL == (valid_from_enc = json_string_value (valid_from_obj)));
  EXITIF (NULL == (valid_until_enc = json_string_value (valid_until_obj)));
  EXITIF (NULL == (key_enc = json_string_value (key_obj)));
  EXITIF (NULL == (sig_enc = json_string_value (sig_obj)));
  EXITIF (GNUNET_SYSERR == parse_timestamp (&valid_from,
                                            valid_from_enc));
  EXITIF (GNUNET_SYSERR == parse_timestamp (&valid_until,
                                            valid_until_enc));
  EXITIF (52 != strlen (key_enc));  /* strlen(base32(char[32])) = 52 */
  EXITIF (103 != strlen (sig_enc)); /* strlen(base32(char[64])) = 103 */
  EXITIF (GNUNET_OK != GNUNET_STRINGS_string_to_data (sig_enc, 103,
                                                      &sig, sizeof (sig)));
  (void) memset (&sign_key_issue, 0, sizeof (sign_key_issue));
  EXITIF (GNUNET_SYSERR ==
          GNUNET_CRYPTO_eddsa_public_key_from_string (key_enc,
                                                      52,
                                                      &sign_key_issue.signkey_pub));
  sign_key_issue.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNKEY);
  sign_key_issue.purpose.size =
      htonl (sizeof (sign_key_issue)
             - offsetof (struct TALER_MINT_SignKeyIssue, purpose));
  sign_key_issue.master_pub = *master_key;
  sign_key_issue.start = GNUNET_TIME_absolute_hton (valid_from);
  sign_key_issue.expire = GNUNET_TIME_absolute_hton (valid_until);
  EXITIF (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_SIGNKEY,
                                      &sign_key_issue.purpose,
                                      &sig,
                                      master_key));
  sign_key = GNUNET_new (struct TALER_MINT_SigningPublicKey);
  sign_key->valid_from = valid_from;
  sign_key->valid_until = valid_until;
  sign_key->key = sign_key_issue.signkey_pub;
  *_sign_key = sign_key;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
}


static int
parse_json_amount (json_t *amount_obj, struct TALER_Amount *amt)
{
  json_t *obj;
  const char *currency_str;
  int value;
  int fraction;

  EXITIF (NULL == (obj = json_object_get (amount_obj, "currency")));
  EXITIF (NULL == (currency_str = json_string_value (obj)));
  EXITIF (NULL == (obj = json_object_get (amount_obj, "value")));
  EXITIF (JSON_INTEGER != json_typeof (obj));
  EXITIF (0 > (value = json_integer_value (obj)));
  EXITIF (NULL == (obj = json_object_get (amount_obj, "fraction")));
  EXITIF (JSON_INTEGER != json_typeof (obj));
  EXITIF (0 > (fraction = json_integer_value (obj)));
  (void) memset (amt->currency, 0, sizeof (amt->currency));
  (void) strncpy (amt->currency, currency_str, sizeof (amt->currency) - 1);
  amt->value = (uint32_t) value;
  amt->fraction = (uint32_t) fraction;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
}

static int
parse_json_denomkey (struct TALER_MINT_DenomPublicKey **_denom_key,
                     json_t *denom_key_obj,
                     struct GNUNET_CRYPTO_EddsaPublicKey *master_key)
{
  json_t *obj;
  const char *sig_enc;
  const char *deposit_valid_until_enc;
  const char *withdraw_valid_until_enc;
  const char *valid_from_enc;
  const char *key_enc;
  char *buf;
  size_t buf_size;
  struct TALER_MINT_DenomPublicKey *denom_key;
  struct GNUNET_TIME_Absolute valid_from;
  struct GNUNET_TIME_Absolute withdraw_valid_until;
  struct GNUNET_TIME_Absolute deposit_valid_until;
  struct TALER_Amount value;
  struct TALER_Amount fee_withdraw;
  struct TALER_Amount fee_deposit;
  struct TALER_Amount fee_refresh;
  struct TALER_MINT_DenomKeyIssue denom_key_issue;
  struct GNUNET_CRYPTO_EddsaSignature sig;

  EXITIF (JSON_OBJECT != json_typeof (denom_key_obj));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "master_sig")));
  EXITIF (NULL == (sig_enc = json_string_value (obj)));
  EXITIF (103 != strlen (sig_enc));
  EXITIF (GNUNET_OK != GNUNET_STRINGS_string_to_data (sig_enc, 103,
                                                      &sig, sizeof (sig)));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "stamp_expire_deposit")));
  EXITIF (NULL == (deposit_valid_until_enc = json_string_value (obj)));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "stamp_expire_withdraw")));
  EXITIF (NULL == (withdraw_valid_until_enc = json_string_value (obj)));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "stamp_start")));
  EXITIF (NULL == (valid_from_enc = json_string_value (obj)));

  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "denom_pub")));
  EXITIF (NULL == (key_enc = json_string_value (obj)));

  EXITIF (GNUNET_SYSERR == parse_timestamp (&valid_from, valid_from_enc));
  EXITIF (GNUNET_SYSERR == parse_timestamp (&withdraw_valid_until,
                                            withdraw_valid_until_enc));
  EXITIF (GNUNET_SYSERR == parse_timestamp (&deposit_valid_until,
                                            deposit_valid_until_enc));

  memset (&denom_key_issue, 0, sizeof (denom_key_issue));

  buf_size = (strlen (key_enc) * 5) / 8;
  buf = GNUNET_malloc (buf_size);

  EXITIF (GNUNET_OK !=
          GNUNET_STRINGS_string_to_data (key_enc, strlen (key_enc),
                                         buf,
                                         buf_size));
  denom_key_issue.denom_pub = GNUNET_CRYPTO_rsa_public_key_decode (buf, buf_size);
  GNUNET_free (buf);
  EXITIF (NULL == denom_key_issue.denom_pub);

  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "value")));
  EXITIF (GNUNET_SYSERR == parse_json_amount (obj, &value));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "fee_withdraw")));
  EXITIF (GNUNET_SYSERR == parse_json_amount (obj, &fee_withdraw));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "fee_deposit")));
  EXITIF (GNUNET_SYSERR == parse_json_amount (obj, &fee_deposit));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "fee_refresh")));
  EXITIF (GNUNET_SYSERR == parse_json_amount (obj, &fee_refresh));
  denom_key_issue.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOM);
  denom_key_issue.purpose.size = htonl
      (sizeof (struct TALER_MINT_DenomKeyIssue) -
       offsetof (struct TALER_MINT_DenomKeyIssue, purpose));
  denom_key_issue.master = *master_key;
  denom_key_issue.start = GNUNET_TIME_absolute_hton (valid_from);
  denom_key_issue.expire_withdraw = GNUNET_TIME_absolute_hton (withdraw_valid_until);
  denom_key_issue.expire_spend = GNUNET_TIME_absolute_hton (deposit_valid_until);
  denom_key_issue.value = TALER_amount_hton (value);
  denom_key_issue.fee_withdraw = TALER_amount_hton (fee_withdraw);
  denom_key_issue.fee_deposit = TALER_amount_hton (fee_deposit);
  denom_key_issue.fee_refresh = TALER_amount_hton (fee_refresh);
  EXITIF (GNUNET_SYSERR ==
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_DENOM,
                                      &denom_key_issue.purpose,
                                      &sig,
                                      master_key));
  denom_key = GNUNET_new (struct TALER_MINT_DenomPublicKey);
  denom_key->key = denom_key_issue.denom_pub;
  denom_key->valid_from = valid_from;
  denom_key->withdraw_valid_until = withdraw_valid_until;
  denom_key->deposit_valid_until = deposit_valid_until;
  denom_key->value = value;
  denom_key->fee_withdraw = fee_withdraw;
  denom_key->fee_deposit = fee_deposit;
  denom_key->fee_refresh = fee_refresh;
  *_denom_key = denom_key;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
}


static int
parse_response_keys_get (const char *in, size_t size,
                         struct TALER_MINT_SigningPublicKey ***_sign_keys,
                         unsigned int *_n_sign_keys,
                         struct TALER_MINT_DenomPublicKey ***_denom_keys,
                         unsigned int *_n_denom_keys)
{
  json_t *resp_obj;
  struct TALER_MINT_DenomPublicKey **denom_keys;
  struct GNUNET_CRYPTO_EddsaPublicKey master_key;
  struct GNUNET_TIME_Absolute list_issue_date;
  struct TALER_MINT_SigningPublicKey **sign_keys;
  unsigned int n_denom_keys;
  unsigned int n_sign_keys;
  json_error_t error;
  unsigned int index;
  int OK;

  denom_keys = NULL;
  n_denom_keys = 0;
  sign_keys = NULL;
  n_sign_keys = 0;
  OK = 0;
  resp_obj = json_loadb (in, size,
                      JSON_REJECT_DUPLICATES | JSON_DISABLE_EOF_CHECK,
                      &error);
  if (NULL == resp_obj)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unable to parse received data as JSON object\n");
    return GNUNET_SYSERR;
  }

  EXITIF (JSON_OBJECT != json_typeof (resp_obj));
  {
    /* parse the master public key */
    json_t *master_key_obj;
    const char *master_key_enc;

    EXITIF (NULL == (master_key_obj = json_object_get (resp_obj, "master_pub")));
    EXITIF (NULL == (master_key_enc = json_string_value (master_key_obj)));
    EXITIF (52 != strlen (master_key_enc)); /* strlen(base32(char[32])) = 52 */
    EXITIF (GNUNET_OK !=
              GNUNET_CRYPTO_eddsa_public_key_from_string (master_key_enc,
                                                          52,
                                                          &master_key));
  }
  {
    /* parse the issue date of the response */
    json_t *list_issue_date_obj;
    const char  *tstamp_enc;

    EXITIF (NULL == (list_issue_date_obj =
                     json_object_get(resp_obj, "list_issue_date")));
    EXITIF (NULL == (tstamp_enc = json_string_value (list_issue_date_obj)));
    EXITIF (GNUNET_SYSERR == parse_timestamp (&list_issue_date, tstamp_enc));
  }
  {
    /* parse the signing keys */
    json_t *sign_keys_array;
    json_t *sign_key_obj;

    EXITIF (NULL == (sign_keys_array =
                     json_object_get (resp_obj, "signkeys")));
    EXITIF (JSON_ARRAY != json_typeof (sign_keys_array));
    EXITIF (0 == (n_sign_keys = json_array_size (sign_keys_array)));
    sign_keys = GNUNET_malloc (sizeof (struct TALER_MINT_SigningPublicKey *)
                               * (n_sign_keys + 1));
    index = 0;
    json_array_foreach (sign_keys_array, index, sign_key_obj) {
      EXITIF (GNUNET_SYSERR == parse_json_signkey (&sign_keys[index],
                                                   sign_key_obj,
                                                   &master_key));
    }
  }
  {
    /* parse the denomination keys */
    json_t *denom_keys_array;
    json_t *denom_key_obj;

    EXITIF (NULL == (denom_keys_array = json_object_get (resp_obj, "denoms")));
    EXITIF (JSON_ARRAY != json_typeof (denom_keys_array));
    EXITIF (0 == (n_denom_keys = json_array_size (denom_keys_array)));
    denom_keys = GNUNET_malloc (sizeof (struct TALER_MINT_DenomPublicKey *)
                                * (n_denom_keys + 1));
    index = 0;
    json_array_foreach (denom_keys_array, index, denom_key_obj) {
      EXITIF (GNUNET_SYSERR == parse_json_denomkey (&denom_keys[index],
                                                    denom_key_obj,
                                                    &master_key));
    }
  }
  OK = 1;

 EXITIF_exit:
  json_decref (resp_obj);
  if (!OK)
  {
    if (NULL != sign_keys)
    {
      for (index=0; NULL != sign_keys[index]; index++)
        GNUNET_free_non_null (sign_keys[index]);
      GNUNET_free (sign_keys);
    }
    if (NULL != denom_keys)
    {
      for (index=0; NULL != denom_keys[index]; index++)
        GNUNET_free_non_null (denom_keys[index]);
      GNUNET_free (denom_keys);
    }
    return GNUNET_SYSERR;
  }

  *_sign_keys = sign_keys;
  *_n_sign_keys = n_sign_keys;
  *_denom_keys = denom_keys;
  *_n_denom_keys = n_denom_keys;
  return GNUNET_OK;
}


int
parse_deposit_response (void *buf, size_t size, int *r_status, json_t **r_obj)
{
  json_t *obj;
  const char *status_str;
  json_error_t error;

  status_str = NULL;
  obj = NULL;
  obj = json_loadb (buf, size,
                    JSON_REJECT_DUPLICATES | JSON_DISABLE_EOF_CHECK, &error);
  if (NULL == obj)
  {
    JSON_WARN (error);
    return GNUNET_SYSERR;
  }
  EXITIF (-1 == json_unpack (obj, "{s:s}", "status", &status_str));
  LOG_DEBUG ("Received deposit response: %s from mint\n", status_str);
  if (0 == strcmp ("DEPOSIT_OK", status_str))
    *r_status = 1;
  else if (0 == strcmp ("DEPOSIT_QUEUED", status_str))
    *r_status = 2;
  else
    *r_status = 0;
  *r_obj = obj;

  return GNUNET_OK;
 EXITIF_exit:
  json_decref (obj);
  return GNUNET_SYSERR;
}

#undef EXITIF

static void
mint_connect (struct TALER_MINT_Handle *mint)
{
  struct TALER_MINT_Context *ctx = mint->ctx;

  GNUNET_assert (0 == mint->connected);
  GNUNET_assert (CURLM_OK == curl_multi_add_handle (ctx->multi, mint->curl));
  mint->connected = GNUNET_YES;
}

static void
mint_disconnect (struct TALER_MINT_Handle *mint)
{
  struct TALER_MINT_Context *ctx = mint->ctx;

  GNUNET_assert (GNUNET_YES == mint->connected);
  GNUNET_break (CURLM_OK == curl_multi_remove_handle (ctx->multi,
                                                      mint->curl));
  mint->connected = GNUNET_NO;
  GNUNET_free_non_null (mint->buf);
  mint->buf = NULL;
  mint->buf_size = 0;
  mint->req_type = REQUEST_TYPE_NONE;
  mint->req.none = NULL;
}

static void
cleanup_keys_get (struct TALER_MINT_KeysGetHandle *gh)
{
  GNUNET_free (gh->url);
  GNUNET_free (gh);
}

static void
cleanup_deposit (struct TALER_MINT_DepositHandle *dh)
{
  curl_slist_free_all (dh->headers);
  GNUNET_free_non_null (dh->json_enc);
  GNUNET_free (dh->url);
  GNUNET_free (dh);
}

static void
request_failed (struct TALER_MINT_Handle *mint, long resp_code)
{
  switch (mint->req_type)
  {
  case REQUEST_TYPE_NONE:
    GNUNET_assert (0);
    break;
  case REQUEST_TYPE_KEYSGET:
    {
      struct TALER_MINT_KeysGetHandle *gh = mint->req.keys_get;
      TALER_MINT_ContinuationCallback cont_cb;
      void *cont_cls;
      GNUNET_assert (NULL != gh);
      cont_cb = gh->cont_cb;
      cont_cls = gh->cont_cls;
      cleanup_keys_get (gh);
      mint_disconnect (mint);
      cont_cb (cont_cls, mint->emsg);
    }
    break;
  case REQUEST_TYPE_DEPOSIT:
    {
      struct TALER_MINT_DepositHandle *dh = mint->req.deposit;
      TALER_MINT_DepositResultCallback cb = dh->cb;
      void *cls = dh->cls;
      GNUNET_assert (NULL != dh);
      cleanup_deposit (dh);
      mint_disconnect (mint);
      cb (cls, 0, NULL, mint->emsg);
    }
    break;
  }
}

static void
request_succeeded (struct TALER_MINT_Handle *mint, long resp_code)
{
  char *emsg;

  emsg = NULL;
  switch (mint->req_type)
  {
  case REQUEST_TYPE_NONE:
    GNUNET_assert (0);
    break;
  case REQUEST_TYPE_KEYSGET:
    {
      struct TALER_MINT_KeysGetHandle *gh = mint->req.keys_get;
      TALER_MINT_ContinuationCallback cont_cb;
      void *cont_cls;
      struct TALER_MINT_SigningPublicKey **sign_keys;
      struct TALER_MINT_DenomPublicKey **denom_keys;
      unsigned int n_sign_keys;
      unsigned int n_denom_keys;

      GNUNET_assert (NULL != gh);
      cont_cb = gh->cont_cb;
      cont_cls = gh->cont_cls;
      if (200 == resp_code)
      {
        /* parse JSON object from the mint->buf which is of size mint->buf_size */
        if (GNUNET_OK ==
            parse_response_keys_get (mint->buf, mint->buf_size,
                                     &sign_keys, &n_sign_keys,
                                     &denom_keys, &n_denom_keys))
          gh->cb (gh->cls, sign_keys, denom_keys);
        else
          emsg = GNUNET_strdup ("Error parsing response");
      }
      else
        GNUNET_asprintf (&emsg, "Failed with response code: %ld", resp_code);
      cleanup_keys_get (gh);
      mint_disconnect (mint);
      cont_cb (cont_cls, emsg);
    }
    break;
  case REQUEST_TYPE_DEPOSIT:
    {
      struct TALER_MINT_DepositHandle *dh = mint->req.deposit;
      TALER_MINT_DepositResultCallback cb;
      void *cls;
      int status;
      json_t *obj;

      GNUNET_assert (NULL != dh);
      obj = NULL;
      cb = dh->cb;
      cls = dh->cls;
      status = 0;
      if (200 == resp_code)
      {
        /* parse JSON object from the mint->buf which is of size mint->buf_size */
        if (GNUNET_OK !=
            parse_deposit_response (mint->buf, mint->buf_size,
                                    &status, &obj))
          emsg = GNUNET_strdup ("Error parsing response");
      }
      else
        GNUNET_asprintf (&emsg, "Failed with response code: %ld", resp_code);
      cleanup_deposit (dh);
      mint_disconnect (mint);
      cb (cls, status, obj, emsg);
    }
    break;
  }
  GNUNET_free_non_null (emsg);
}


static void
do_perform (void *cls, const struct GNUNET_SCHEDULER_TaskContext *tc);

static void
perform (struct TALER_MINT_Context *ctx)
{
  fd_set fd_rs;
  fd_set fd_ws;
  struct GNUNET_NETWORK_FDSet rs;
  struct GNUNET_NETWORK_FDSet ws;
  CURLMsg *cmsg;
  struct TALER_MINT_Handle *mint;
  long timeout;
  long resp_code;
  static unsigned int n_old;
  int n_running;
  int n_completed;
  int max_fd;

  n_completed = 0;
  curl_multi_perform (ctx->multi, &n_running);
  GNUNET_assert (0 <= n_running);
  if ((0 == n_running) || (n_running < n_old))
  {
    /* some requests were completed -- handle them */
    while (NULL != (cmsg = curl_multi_info_read (ctx->multi, &n_completed)))
    {
      GNUNET_break (CURLMSG_DONE == cmsg->msg); /* curl only has CURLMSG_DONE */
      GNUNET_assert (CURLE_OK == curl_easy_getinfo (cmsg->easy_handle,
                                                    CURLINFO_PRIVATE,
                                                    (char *) &mint));
      GNUNET_assert (CURLE_OK == curl_easy_getinfo (cmsg->easy_handle,
                                                    CURLINFO_RESPONSE_CODE,
                                                    &resp_code));
      GNUNET_assert (ctx == mint->ctx); /* did we get the correct one? */
      if (CURLE_OK == cmsg->data.result)
        request_succeeded (mint, resp_code);
      else
        request_failed (mint, resp_code);
    }
  }
  n_old = n_running;
  /* reschedule perform() */
  if (0 != n_old)
  {
    FD_ZERO (&fd_rs);
    FD_ZERO (&fd_ws);
    GNUNET_assert (CURLM_OK == curl_multi_fdset (ctx->multi,
                                                 &fd_rs,
                                                 &fd_ws,
                                                 NULL,
                                                 &max_fd));
    if (-1 == max_fd)
    {
      ctx->perform_task = GNUNET_SCHEDULER_add_delayed
          (GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS, 100),
           &do_perform, ctx);
      return;
    }
    GNUNET_assert (CURLM_OK == curl_multi_timeout (ctx->multi, &timeout));
    if (-1 == timeout)
    {
      timeout = 1000 * 60 * 5;
    }
    GNUNET_NETWORK_fdset_zero (&rs);
    GNUNET_NETWORK_fdset_zero (&ws);
    GNUNET_NETWORK_fdset_copy_native (&rs, &fd_rs, max_fd + 1);
    GNUNET_NETWORK_fdset_copy_native (&ws, &fd_ws, max_fd + 1);
    ctx->perform_task = GNUNET_SCHEDULER_add_select
        (GNUNET_SCHEDULER_PRIORITY_KEEP,
         GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS, timeout),
         &rs, &ws,
         &do_perform, ctx);
  }
}


static void
do_perform (void *cls, const struct GNUNET_SCHEDULER_TaskContext *tc)
{
  struct TALER_MINT_Context *ctx = cls;

  GNUNET_assert (NULL != ctx->perform_task);
  ctx->perform_task = NULL;
  perform (ctx);
}

static void
perform_now (struct TALER_MINT_Context *ctx)
{
  if (NULL != ctx->perform_task)
  {
    GNUNET_SCHEDULER_cancel (ctx->perform_task);
    ctx->perform_task = NULL;
  }
  ctx->perform_task = GNUNET_SCHEDULER_add_now (&do_perform, ctx);
}


/* This function gets called by libcurl as soon as there is data received that */
/* needs to be saved. The size of the data pointed to by ptr is size */
/* multiplied with nmemb, it will not be zero terminated. Return the number */
/* of bytes actually taken care of. If that amount differs from the amount passed */
/* to your function, it'll signal an error to the library. This will abort the */
/* transfer and return CURLE_WRITE_ERROR. */

/* From 7.18.0, the function can return CURL_WRITEFUNC_PAUSE which then will */
/* cause writing to this connection to become paused. See */
/* curl_easy_pause(3) for further details. */

/* This function may be called with zero bytes data if the transferred file is */
/* empty. */

/* Set this option to NULL to get the internal default function. The internal */
/* default function will write the data to the FILE * given with */
/* CURLOPT_WRITEDATA. */

/* Set the userdata argument with the CURLOPT_WRITEDATA option. */

/* The callback function will be passed as much data as possible in all invokes, */
/* but you cannot possibly make any assumptions. It may be one byte, it may be */
/* thousands. The maximum amount of body data that can be passed to the write */
/* callback is defined in the curl.h header file: CURL_MAX_WRITE_SIZE (the usual */
/* default is 16K). If you however have CURLOPT_HEADER set, which sends */
/* header data to the write callback, you can get up to */
/* CURL_MAX_HTTP_HEADER bytes of header data passed into it. This usually */
/* means 100K. */
static size_t
download (char *bufptr, size_t size, size_t nitems, void *cls)
{
  struct TALER_MINT_Handle *mint = cls;
  size_t msize;
  void *buf;

  if (0 == size * nitems)
  {
    /* file is empty */
    return 0;
  }
  msize = size * nitems;
  mint->buf = GNUNET_realloc (mint->buf, mint->buf_size + msize);
  buf = mint->buf + mint->buf_size;
  memcpy (buf, bufptr, msize);
  mint->buf_size += msize;
  return msize;
}


/**
 * Initialise a connection to the mint.
 *
 * @param ctx the context
 * @param hostname the hostname of the mint
 * @param port the point where the mint's HTTP service is running.
 * @param mint_key the public key of the mint.  This is used to verify the
 *                 responses of the mint.
 * @return the mint handle; NULL upon error
 */
struct TALER_MINT_Handle *
TALER_MINT_connect (struct TALER_MINT_Context *ctx,
                    const char *hostname,
                    uint16_t port,
                    struct GNUNET_CRYPTO_EddsaPublicKey *mint_key)
{
  struct TALER_MINT_Handle *mint;

  mint = GNUNET_new (struct TALER_MINT_Handle);
  mint->ctx = ctx;
  mint->hostname = GNUNET_strdup (hostname);
  mint->port = (0 != port) ? port : 80;
  mint->curl = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_SHARE, ctx->share));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_ERRORBUFFER, mint->emsg));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_WRITEFUNCTION, &download));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_WRITEDATA, mint));
  GNUNET_assert (CURLE_OK == curl_easy_setopt (mint->curl, CURLOPT_PRIVATE, mint));
  return mint;
}

/**
 * Disconnect from the mint
 *
 * @param mint the mint handle
 */
void
TALER_MINT_disconnect (struct TALER_MINT_Handle *mint)
{
  if (GNUNET_YES == mint->connected)
    mint_disconnect (mint);
  curl_easy_cleanup (mint->curl);
  GNUNET_free (mint->hostname);
  GNUNET_free (mint);
}

/**
 * Get the signing and denomination key of the mint.
 *
 * @param mint handle to the mint
 * @param cb the callback to call with each retrieved denomination key
 * @param cls closure for the above callback
 * @param cont_cb the callback to call after completing this asynchronous call
 * @param cont_cls the closure for the continuation callback
 * @return a handle to this asynchronous call; NULL upon eror
 */
struct TALER_MINT_KeysGetHandle *
TALER_MINT_keys_get (struct TALER_MINT_Handle *mint,
                           TALER_MINT_KeysGetCallback cb, void *cls,
                           TALER_MINT_ContinuationCallback cont_cb, void *cont_cls)
{
  struct TALER_MINT_KeysGetHandle *gh;

  GNUNET_assert (REQUEST_TYPE_NONE == mint->req_type);
  gh = GNUNET_new (struct TALER_MINT_KeysGetHandle);
  gh->mint = mint;
  mint->req_type = REQUEST_TYPE_KEYSGET;
  mint->req.keys_get = gh;
  gh->cb = cb;
  gh->cls = cls;
  gh->cont_cb = cont_cb;
  gh->cont_cls = cont_cls;
  GNUNET_asprintf (&gh->url, "http://%s:%hu/keys", mint->hostname, mint->port);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_URL, gh->url));
  if (GNUNET_NO == mint->connected)
    mint_connect (mint);
  perform_now (mint->ctx);
  return gh;
}


/**
 * Cancel the asynchronous call initiated by TALER_MINT_keys_get().  This
 * should not be called if either of the @a TALER_MINT_KeysGetCallback or
 * @a TALER_MINT_ContinuationCallback passed to TALER_MINT_keys_get() have
 * been called.
 *
 * @param get the handle for retrieving the keys
 */
void
TALER_MINT_keys_get_cancel (struct TALER_MINT_KeysGetHandle *get)
{
  struct TALER_MINT_Handle *mint = get->mint;

  mint_disconnect (mint);
  cleanup_keys_get (get);
}

/**
 * Submit a deposit permission to the mint and get the mint's response
 *
 * @param mint the mint handle
 * @param cb the callback to call when a reply for this request is available
 * @param cls closure for the above callback
 * @param deposit_obj the deposit permission received from the customer along
 *         with the wireformat JSON object
 * @return a handle for this request; NULL if the JSON object could not be
 *         parsed or is of incorrect format or any other error.  In this case,
 *         the callback is not called.
 */
struct TALER_MINT_DepositHandle *
TALER_MINT_deposit_submit_json (struct TALER_MINT_Handle *mint,
                                TALER_MINT_DepositResultCallback cb,
                                void *cls,
                                json_t *deposit_obj)
{
  struct TALER_MINT_DepositHandle *dh;

  GNUNET_assert (REQUEST_TYPE_NONE == mint->req_type);
  dh = GNUNET_new (struct TALER_MINT_DepositHandle);
  dh->mint = mint;
  mint->req_type = REQUEST_TYPE_DEPOSIT;
  mint->req.deposit = dh;
  dh->cb = cb;
  dh->cls = cls;
  GNUNET_asprintf (&dh->url, "http://%s:%hu/deposit", mint->hostname, mint->port);
  GNUNET_assert (NULL != (dh->json_enc = json_dumps (deposit_obj, JSON_COMPACT)));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_URL, dh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_POSTFIELDS,
                                   dh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_POSTFIELDSIZE,
                                   strlen (dh->json_enc)));
  GNUNET_assert (NULL != (dh->headers =
                          curl_slist_append (dh->headers, "Content-Type: application/json")));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (mint->curl, CURLOPT_HTTPHEADER, dh->headers));
  if (GNUNET_NO == mint->connected)
    mint_connect (mint);
  perform_now (mint->ctx);
  return dh;
}


/**
 * Cancel a deposit permission request.  This function cannot be used on a
 * request handle if a response is already served for it.
 *
 * @param the deposit permission request handle
 */
void
TALER_MINT_deposit_submit_cancel (struct TALER_MINT_DepositHandle *deposit)
{
  struct TALER_MINT_Handle *mint = deposit->mint;

  mint_disconnect (mint);
  cleanup_deposit (deposit);
}


/**
 * Initialise this library.  This function should be called before using any of
 * the following functions.
 *
 * @return library context
 */
struct TALER_MINT_Context *
TALER_MINT_init ()
{
  struct TALER_MINT_Context *ctx;
  CURLM *multi;
  CURLSH *share;

  if (fail)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "cURL was not initialised properly\n");
    return NULL;
  }
  if (NULL == (multi = curl_multi_init ()))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Cannot create a cURL multi handle\n");
    return NULL;
  }
  if (NULL == (share = curl_share_init ()))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Cannot create a cURL share handle\n");
    return NULL;
  }
  ctx = GNUNET_new (struct TALER_MINT_Context);
  ctx->multi = multi;
  ctx->share = share;
  return ctx;
}


/**
 * Cleanup library initialisation resources.  This function should be called
 * after using this library to cleanup the resources occupied during library's
 * initialisation.
 *
 * @param ctx the library context
 */
void
TALER_MINT_cleanup (struct TALER_MINT_Context *ctx)
{
  curl_share_cleanup (ctx->share);
  curl_multi_cleanup (ctx->multi);
  if (NULL != ctx->perform_task)
  {
    GNUNET_break (0);           /* investigate why this happens */
    GNUNET_SCHEDULER_cancel (ctx->perform_task);
  }
  GNUNET_free (ctx);
}


__attribute__ ((constructor))
void
TALER_MINT_constructor__ (void)
{
  CURLcode ret;
  if (CURLE_OK != (ret = curl_global_init (CURL_GLOBAL_DEFAULT)))
  {
    CURL_STRERROR (GNUNET_ERROR_TYPE_ERROR, "curl_global_init", ret);
    fail = 1;
  }
}

__attribute__ ((destructor))
void
TALER_MINT_destructor__ (void)
{
  if (fail)
    return;
  curl_global_cleanup ();
}
