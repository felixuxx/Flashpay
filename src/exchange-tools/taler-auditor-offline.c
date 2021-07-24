/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-auditor-offline.c
 * @brief Support for operations involving the auditor's (offline) key.
 * @author Christian Grothoff
 */
#include <platform.h>
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"

/**
 * Name of the input of a denomination key signature for the 'upload' operation.
 * The "auditor-" prefix ensures that there is no ambiguity between
 * taler-exchange-offline and taler-auditor-offline JSON formats.
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_SIGN_DENOMINATION "auditor-sign-denomination-0"

/**
 * Name of the input for the 'sign' and 'show' operations.
 * The "auditor-" prefix ensures that there is no ambiguity between
 * taler-exchange-offline and taler-auditor-offline JSON formats.
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_INPUT_KEYS "auditor-keys-0"

/**
 * Show the offline signing key.
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_SETUP "auditor-setup-0"

/**
 * Our private key, initialized in #load_offline_key().
 */
static struct TALER_AuditorPrivateKeyP auditor_priv;

/**
 * Our private key, initialized in #load_offline_key().
 */
static struct TALER_AuditorPublicKeyP auditor_pub;

/**
 * Base URL of this auditor's REST endpoint.
 */
static char *auditor_url;

/**
 * Exchange's master public key.
 */
static struct TALER_MasterPublicKeyP master_pub;

/**
 * Our context for making HTTP requests.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Reschedule context for #ctx.
 */
static struct GNUNET_CURL_RescheduleContext *rc;

/**
 * Handle to the exchange's configuration
 */
static const struct GNUNET_CONFIGURATION_Handle *kcfg;

/**
 * Return value from main().
 */
static int global_ret;

/**
 * Input to consume.
 */
static json_t *in;

/**
 * Array of actions to perform.
 */
static json_t *out;

/**
 * Currency supported by this auditor.
 */
static char *currency;


/**
 * A subcommand supported by this program.
 */
struct SubCommand
{
  /**
   * Name of the command.
   */
  const char *name;

  /**
   * Help text for the command.
   */
  const char *help;

  /**
   * Function implementing the command.
   *
   * @param args subsequent command line arguments (char **)
   */
  void (*cb)(char *const *args);
};


/**
 * Data structure for wire add requests.
 */
struct DenominationAddRequest
{

  /**
   * Kept in a DLL.
   */
  struct DenominationAddRequest *next;

  /**
   * Kept in a DLL.
   */
  struct DenominationAddRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_AuditorAddDenominationHandle *h;

  /**
   * Array index of the associated command.
   */
  size_t idx;
};


/**
 * Next work item to perform.
 */
static struct GNUNET_SCHEDULER_Task *nxt;

/**
 * Active denomination add requests.
 */
static struct DenominationAddRequest *dar_head;

/**
 * Active denomination add requests.
 */
static struct DenominationAddRequest *dar_tail;

/**
 * Handle to the exchange, used to request /keys.
 */
static struct TALER_EXCHANGE_Handle *exchange;


/**
 * Shutdown task. Invoked when the application is being terminated.
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  (void) cls;

  {
    struct DenominationAddRequest *dar;

    while (NULL != (dar = dar_head))
    {
      fprintf (stderr,
               "Aborting incomplete wire add #%u\n",
               (unsigned int) dar->idx);
      TALER_EXCHANGE_add_auditor_denomination_cancel (dar->h);
      GNUNET_CONTAINER_DLL_remove (dar_head,
                                   dar_tail,
                                   dar);
      GNUNET_free (dar);
    }
  }
  if (NULL != out)
  {
    json_dumpf (out,
                stdout,
                JSON_INDENT (2));
    json_decref (out);
    out = NULL;
  }
  if (NULL != in)
  {
    fprintf (stderr,
             "Darning: input not consumed!\n");
    json_decref (in);
    in = NULL;
  }
  if (NULL != exchange)
  {
    TALER_EXCHANGE_disconnect (exchange);
    exchange = NULL;
  }
  if (NULL != nxt)
  {
    GNUNET_SCHEDULER_cancel (nxt);
    nxt = NULL;
  }
  if (NULL != ctx)
  {
    GNUNET_CURL_fini (ctx);
    ctx = NULL;
  }
  if (NULL != rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (rc);
    rc = NULL;
  }
}


/**
 * Test if we should shut down because all tasks are done.
 */
static void
test_shutdown (void)
{
  if ( (NULL == dar_head) &&
       (NULL == exchange) &&
       (NULL == nxt) )
    GNUNET_SCHEDULER_shutdown ();
}


/**
 * Function to continue processing the next command.
 *
 * @param cls must be a `char *const*` with the array of
 *        command-line arguments to process next
 */
static void
work (void *cls);


/**
 * Function to schedule job to process the next command.
 *
 * @param args the array of command-line arguments to process next
 */
static void
next (char *const *args)
{
  GNUNET_assert (NULL == nxt);
  if (NULL == args[0])
  {
    test_shutdown ();
    return;
  }
  nxt = GNUNET_SCHEDULER_add_now (&work,
                                  (void *) args);
}


/**
 * Add an operation to the #out JSON array for processing later.
 *
 * @param op_name name of the operation
 * @param op_value values for the operation (consumed)
 */
static void
output_operation (const char *op_name,
                  json_t *op_value)
{
  json_t *action;

  GNUNET_assert (NULL != out);
  action = json_pack ("{ s:s, s:o }",
                      "operation",
                      op_name,
                      "arguments",
                      op_value);
  GNUNET_break (0 ==
                json_array_append_new (out,
                                       action));
}


/**
 * Information about a subroutine for an upload.
 */
struct UploadHandler
{
  /**
   * Key to trigger this subroutine.
   */
  const char *key;

  /**
   * Function implementing an upload.
   *
   * @param exchange_url URL of the exchange
   * @param idx index of the operation we are performing
   * @param value arguments to drive the upload.
   */
  void (*cb)(const char *exchange_url,
             size_t idx,
             const json_t *value);

};


/**
 * Load the offline key (if not yet done). Triggers shutdown on failure.
 *
 * @param do_create #GNUNET_YES if the key may be created
 * @return #GNUNET_OK on success
 */
static int
load_offline_key (int do_create)
{
  static bool done;
  int ret;
  char *fn;

  if (done)
    return GNUNET_OK;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "auditor",
                                               "AUDITOR_PRIV_FILE",
                                               &fn))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "AUDITOR_PRIV_FILE");
    test_shutdown ();
    return GNUNET_SYSERR;
  }
  if (GNUNET_YES !=
      GNUNET_DISK_file_test (fn))
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Auditor private key `%s' does not exist yet, creating it!\n",
                fn);
  ret = GNUNET_CRYPTO_eddsa_key_from_file (fn,
                                           do_create,
                                           &auditor_priv.eddsa_priv);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize auditor key from file `%s': %s\n",
                fn,
                "could not create file");
    GNUNET_free (fn);
    test_shutdown ();
    return GNUNET_SYSERR;
  }
  GNUNET_free (fn);
  GNUNET_CRYPTO_eddsa_key_get_public (&auditor_priv.eddsa_priv,
                                      &auditor_pub.eddsa_pub);
  done = true;
  return GNUNET_OK;
}


/**
 * Function called with information about the post denomination (signature)
 * add operation result.
 *
 * @param cls closure with a `struct DenominationAddRequest`
 * @param hr HTTP response data
 */
static void
denomination_add_cb (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct DenominationAddRequest *dar = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    fprintf (stderr,
             "Upload failed for command #%u with status %u: %s (%s)\n",
             (unsigned int) dar->idx,
             hr->http_status,
             TALER_ErrorCode_get_hint (hr->ec),
             NULL != hr->hint
             ? hr->hint
             : "no hint provided");
    global_ret = 42;
  }
  GNUNET_CONTAINER_DLL_remove (dar_head,
                               dar_tail,
                               dar);
  GNUNET_free (dar);
  test_shutdown ();
}


/**
 * Upload denomination add data.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value arguments for denomination revocation
 */
static void
upload_denomination_add (const char *exchange_url,
                         size_t idx,
                         const json_t *value)
{
  struct TALER_AuditorSignatureP auditor_sig;
  struct GNUNET_HashCode h_denom_pub;
  struct DenominationAddRequest *dar;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                 &h_denom_pub),
    GNUNET_JSON_spec_fixed_auto ("auditor_sig",
                                 &auditor_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    fprintf (stderr,
             "Invalid input for adding denomination: %s#%u at %u (skipping)\n",
             err_name,
             err_line,
             (unsigned int) idx);
    global_ret = 7;
    test_shutdown ();
    return;
  }
  dar = GNUNET_new (struct DenominationAddRequest);
  dar->idx = idx;
  dar->h =
    TALER_EXCHANGE_add_auditor_denomination (ctx,
                                             exchange_url,
                                             &h_denom_pub,
                                             &auditor_pub,
                                             &auditor_sig,
                                             &denomination_add_cb,
                                             dar);
  GNUNET_CONTAINER_DLL_insert (dar_head,
                               dar_tail,
                               dar);
}


/**
 * Perform uploads based on the JSON in #out.
 *
 * @param exchange_url base URL of the exchange to use
 */
static void
trigger_upload (const char *exchange_url)
{
  struct UploadHandler uhs[] = {
    {
      .key = OP_SIGN_DENOMINATION,
      .cb = &upload_denomination_add
    },
    /* array termination */
    {
      .key = NULL
    }
  };
  size_t index;
  json_t *obj;

  json_array_foreach (out, index, obj) {
    bool found = false;
    const char *key;
    const json_t *value;

    key = json_string_value (json_object_get (obj, "operation"));
    value = json_object_get (obj, "arguments");
    if (NULL == key)
    {
      fprintf (stderr,
               "Malformed JSON input\n");
      global_ret = 3;
      test_shutdown ();
      return;
    }
    /* block of code that uses key and value */
    for (unsigned int i = 0; NULL != uhs[i].key; i++)
    {
      if (0 == strcasecmp (key,
                           uhs[i].key))
      {
        found = true;
        uhs[i].cb (exchange_url,
                   index,
                   value);
        break;
      }
    }
    if (! found)
    {
      fprintf (stderr,
               "Upload does not know how to handle `%s'\n",
               key);
      global_ret = 3;
      test_shutdown ();
      return;
    }
  }
  /* test here, in case no upload was triggered (i.e. empty input) */
  test_shutdown ();
}


/**
 * Upload operation result (signatures) to exchange.
 *
 * @param args the array of command-line arguments to process next
 */
static void
do_upload (char *const *args)
{
  char *exchange_url;

  if (GNUNET_YES == GNUNET_is_zero (&auditor_pub))
  {
    /* private key not available, try configuration for public key */
    char *auditor_public_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (kcfg,
                                               "auditor",
                                               "PUBLIC_KEY",
                                               &auditor_public_key_str))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "auditor",
                                 "PUBLIC_KEY");
      global_ret = 4;
      test_shutdown ();
      return;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_public_key_from_string (
          auditor_public_key_str,
          strlen (auditor_public_key_str),
          &auditor_pub.eddsa_pub))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "auditor",
                                 "PUBLIC_KEY",
                                 "invalid key");
      GNUNET_free (auditor_public_key_str);
      global_ret = 4;
      test_shutdown ();
      return;
    }
    GNUNET_free (auditor_public_key_str);
  }
  if (NULL != in)
  {
    fprintf (stderr,
             "Downloaded data was not consumed, refusing upload\n");
    test_shutdown ();
    global_ret = 4;
    return;
  }
  if (NULL == out)
  {
    json_error_t err;

    out = json_loadf (stdin,
                      JSON_REJECT_DUPLICATES,
                      &err);
    if (NULL == out)
    {
      fprintf (stderr,
               "Failed to read JSON input: %s at %d:%s (offset: %d)\n",
               err.text,
               err.line,
               err.source,
               err.position);
      test_shutdown ();
      global_ret = 2;
      return;
    }
  }
  if (! json_is_array (out))
  {
    fprintf (stderr,
             "Error: expected JSON array for `upload` command\n");
    test_shutdown ();
    global_ret = 2;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (kcfg,
                                             "exchange",
                                             "BASE_URL",
                                             &exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    global_ret = 1;
    test_shutdown ();
    return;
  }
  trigger_upload (exchange_url);
  json_decref (out);
  out = NULL;
  GNUNET_free (exchange_url);
}


/**
 * Function called with information about who is auditing
 * a particular exchange and what keys the exchange is using.
 *
 * @param cls closure with the `char **` remaining args
 * @param hr HTTP response data
 * @param keys information about the various keys used
 *        by the exchange, NULL if /keys failed
 * @param compat protocol compatibility information
 */
static void
keys_cb (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct TALER_EXCHANGE_Keys *keys,
  enum TALER_EXCHANGE_VersionCompatibility compat)
{
  char *const *args = cls;

  switch (hr->http_status)
  {
  case MHD_HTTP_OK:
    break;
  default:
    fprintf (stderr,
             "Failed to download keys: %s (HTTP status: %u/%u)\n",
             hr->hint,
             hr->http_status,
             (unsigned int) hr->ec);
    TALER_EXCHANGE_disconnect (exchange);
    exchange = NULL;
    test_shutdown ();
    global_ret = 4;
    return;
  }
  in = json_pack ("{s:s,s:O}",
                  "operation",
                  OP_INPUT_KEYS,
                  "arguments",
                  hr->reply);
  if (NULL == args[0])
  {
    json_dumpf (in,
                stdout,
                JSON_INDENT (2));
    json_decref (in);
    in = NULL;
  }
  TALER_EXCHANGE_disconnect (exchange);
  exchange = NULL;
  next (args);
}


/**
 * Download future keys.
 *
 * @param args the array of command-line arguments to process next
 */
static void
do_download (char *const *args)
{
  char *exchange_url;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (kcfg,
                                             "exchange",
                                             "BASE_URL",
                                             &exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    test_shutdown ();
    global_ret = 1;
    return;
  }
  exchange = TALER_EXCHANGE_connect (ctx,
                                     exchange_url,
                                     &keys_cb,
                                     (void *) args,
                                     TALER_EXCHANGE_OPTION_END);
  GNUNET_free (exchange_url);
}


/**
 * Output @a denomkeys for human consumption.
 *
 * @param denomkeys keys to output
 * @return #GNUNET_OK on success
 */
static int
show_denomkeys (const json_t *denomkeys)
{
  size_t index;
  json_t *value;

  json_array_foreach (denomkeys, index, value) {
    const char *err_name;
    unsigned int err_line;
    struct TALER_DenominationPublicKey denom_pub;
    struct GNUNET_TIME_Absolute stamp_start;
    struct GNUNET_TIME_Absolute stamp_expire_withdraw;
    struct GNUNET_TIME_Absolute stamp_expire_deposit;
    struct GNUNET_TIME_Absolute stamp_expire_legal;
    struct TALER_Amount coin_value;
    struct TALER_Amount fee_withdraw;
    struct TALER_Amount fee_deposit;
    struct TALER_Amount fee_refresh;
    struct TALER_Amount fee_refund;
    struct TALER_MasterSignatureP master_sig;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_rsa_public_key ("denom_pub",
                                       &denom_pub.rsa_public_key),
      TALER_JSON_spec_amount ("value",
                              currency,
                              &coin_value),
      TALER_JSON_spec_amount ("fee_withdraw",
                              currency,
                              &fee_withdraw),
      TALER_JSON_spec_amount ("fee_deposit",
                              currency,
                              &fee_deposit),
      TALER_JSON_spec_amount ("fee_refresh",
                              currency,
                              &fee_refresh),
      TALER_JSON_spec_amount ("fee_refund",
                              currency,
                              &fee_refund),
      GNUNET_JSON_spec_absolute_time ("stamp_start",
                                      &stamp_start),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_withdraw",
                                      &stamp_expire_withdraw),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_deposit",
                                      &stamp_expire_deposit),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_legal",
                                      &stamp_expire_legal),
      GNUNET_JSON_spec_fixed_auto ("master_sig",
                                   &master_sig),
      GNUNET_JSON_spec_end ()
    };
    struct GNUNET_TIME_Relative duration;
    struct GNUNET_HashCode h_denom_pub;

    if (GNUNET_OK !=
        GNUNET_JSON_parse (value,
                           spec,
                           &err_name,
                           &err_line))
    {
      fprintf (stderr,
               "Invalid input for denomination key to 'show': %s#%u at %u (skipping)\n",
               err_name,
               err_line,
               (unsigned int) index);
      GNUNET_JSON_parse_free (spec);
      global_ret = 7;
      test_shutdown ();
      return GNUNET_SYSERR;
    }
    duration = GNUNET_TIME_absolute_get_difference (stamp_start,
                                                    stamp_expire_withdraw);
    GNUNET_CRYPTO_rsa_public_key_hash (denom_pub.rsa_public_key,
                                       &h_denom_pub);
    if (GNUNET_OK !=
        TALER_exchange_offline_denom_validity_verify (
          &h_denom_pub,
          stamp_start,
          stamp_expire_withdraw,
          stamp_expire_deposit,
          stamp_expire_legal,
          &coin_value,
          &fee_withdraw,
          &fee_deposit,
          &fee_refresh,
          &fee_refund,
          &master_pub,
          &master_sig))
    {
      fprintf (stderr,
               "Invalid master signature for key %s (aborting)\n",
               TALER_B2S (&h_denom_pub));
      global_ret = 9;
      test_shutdown ();
      return GNUNET_SYSERR;
    }

    {
      char *withdraw_fee_s;
      char *deposit_fee_s;
      char *refresh_fee_s;
      char *refund_fee_s;
      char *deposit_s;
      char *legal_s;

      withdraw_fee_s = TALER_amount_to_string (&fee_withdraw);
      deposit_fee_s = TALER_amount_to_string (&fee_deposit);
      refresh_fee_s = TALER_amount_to_string (&fee_refresh);
      refund_fee_s = TALER_amount_to_string (&fee_refund);
      deposit_s = GNUNET_strdup (
        GNUNET_STRINGS_absolute_time_to_string (stamp_expire_deposit));
      legal_s = GNUNET_strdup (
        GNUNET_STRINGS_absolute_time_to_string (stamp_expire_legal));

      printf (
        "DENOMINATION-KEY %s of value %s starting at %s "
        "(used for: %s, deposit until: %s legal end: %s) with fees %s/%s/%s/%s\n",
        TALER_B2S (&h_denom_pub),
        TALER_amount2s (&coin_value),
        GNUNET_STRINGS_absolute_time_to_string (stamp_start),
        GNUNET_STRINGS_relative_time_to_string (duration,
                                                GNUNET_NO),
        deposit_s,
        legal_s,
        withdraw_fee_s,
        deposit_fee_s,
        refresh_fee_s,
        refund_fee_s);
      GNUNET_free (withdraw_fee_s);
      GNUNET_free (deposit_fee_s);
      GNUNET_free (refresh_fee_s);
      GNUNET_free (refund_fee_s);
      GNUNET_free (deposit_s);
      GNUNET_free (legal_s);
    }

    GNUNET_JSON_parse_free (spec);
  }
  return GNUNET_OK;
}


/**
 * Parse the '/keys' input for operation called @a command_name.
 *
 * @param command_name name of the command, for logging errors
 * @return NULL if the input is malformed
 */
static json_t *
parse_keys (const char *command_name)
{
  json_t *keys;
  const char *op_str;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("arguments",
                           &keys),
    GNUNET_JSON_spec_string ("operation",
                             &op_str),
    GNUNET_JSON_spec_end ()
  };
  const char *err_name;
  unsigned int err_line;

  if (NULL == in)
  {
    json_error_t err;

    in = json_loadf (stdin,
                     JSON_REJECT_DUPLICATES,
                     &err);
    if (NULL == in)
    {
      fprintf (stderr,
               "Failed to read JSON input: %s at %d:%s (offset: %d)\n",
               err.text,
               err.line,
               err.source,
               err.position);
      global_ret = 2;
      test_shutdown ();
      return NULL;
    }
  }
  if (GNUNET_OK !=
      GNUNET_JSON_parse (in,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to '%s': %s#%u (skipping)\n",
                command_name,
                err_name,
                err_line);
    json_dumpf (in,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    return NULL;
  }
  if (0 != strcmp (op_str,
                   OP_INPUT_KEYS))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to '%s' : operation is `%s', expected `%s'\n",
                command_name,
                op_str,
                OP_INPUT_KEYS);
    GNUNET_JSON_parse_free (spec);
    return NULL;
  }
  json_decref (in);
  in = NULL;
  return keys;
}


/**
 * Show exchange denomination keys.
 *
 * @param args the array of command-line arguments to process next
 */
static void
do_show (char *const *args)
{
  json_t *keys;
  const char *err_name;
  unsigned int err_line;
  json_t *denomkeys;
  struct TALER_MasterPublicKeyP mpub;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("denoms",
                           &denomkeys),
    GNUNET_JSON_spec_fixed_auto ("master_public_key",
                                 &mpub),
    GNUNET_JSON_spec_end ()
  };

  keys = parse_keys ("show");
  if (NULL == keys)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Showing failed: no valid input\n");
    return;
  }
  if (GNUNET_OK !=
      GNUNET_JSON_parse (keys,
                         spec,
                         &err_name,
                         &err_line))
  {
    fprintf (stderr,
             "Invalid input to 'show': %s#%u (skipping)\n",
             err_name,
             err_line);
    global_ret = 7;
    test_shutdown ();
    json_decref (keys);
    return;
  }
  if (0 !=
      GNUNET_memcmp (&mpub,
                     &master_pub))
  {
    fprintf (stderr,
             "Exchange master public key does not match key we have configured (aborting)\n");
    global_ret = 7;
    test_shutdown ();
    json_decref (keys);
    return;
  }
  if (GNUNET_OK !=
      show_denomkeys (denomkeys))
  {
    global_ret = 8;
    test_shutdown ();
    GNUNET_JSON_parse_free (spec);
    json_decref (keys);
    return;
  }
  GNUNET_JSON_parse_free (spec);
  json_decref (keys);
  /* do NOT consume input if next argument is '-' */
  if ( (NULL != args[0]) &&
       (0 == strcmp ("-",
                     args[0])) )
  {
    next (args + 1);
    return;
  }
  next (args);
}


/**
 * Sign @a denomkeys with offline key.
 *
 * @param denomkeys keys to output
 * @return #GNUNET_OK on success
 */
static int
sign_denomkeys (const json_t *denomkeys)
{
  size_t index;
  json_t *value;

  json_array_foreach (denomkeys, index, value) {
    const char *err_name;
    unsigned int err_line;
    struct TALER_DenominationPublicKey denom_pub;
    struct GNUNET_TIME_Absolute stamp_start;
    struct GNUNET_TIME_Absolute stamp_expire_withdraw;
    struct GNUNET_TIME_Absolute stamp_expire_deposit;
    struct GNUNET_TIME_Absolute stamp_expire_legal;
    struct TALER_Amount coin_value;
    struct TALER_Amount fee_withdraw;
    struct TALER_Amount fee_deposit;
    struct TALER_Amount fee_refresh;
    struct TALER_Amount fee_refund;
    struct TALER_MasterSignatureP master_sig;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_rsa_public_key ("denom_pub",
                                       &denom_pub.rsa_public_key),
      TALER_JSON_spec_amount ("value",
                              currency,
                              &coin_value),
      TALER_JSON_spec_amount ("fee_withdraw",
                              currency,
                              &fee_withdraw),
      TALER_JSON_spec_amount ("fee_deposit",
                              currency,
                              &fee_deposit),
      TALER_JSON_spec_amount ("fee_refresh",
                              currency,
                              &fee_refresh),
      TALER_JSON_spec_amount ("fee_refund",
                              currency,
                              &fee_refund),
      GNUNET_JSON_spec_absolute_time ("stamp_start",
                                      &stamp_start),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_withdraw",
                                      &stamp_expire_withdraw),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_deposit",
                                      &stamp_expire_deposit),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_legal",
                                      &stamp_expire_legal),
      GNUNET_JSON_spec_fixed_auto ("master_sig",
                                   &master_sig),
      GNUNET_JSON_spec_end ()
    };
    struct GNUNET_HashCode h_denom_pub;

    if (GNUNET_OK !=
        GNUNET_JSON_parse (value,
                           spec,
                           &err_name,
                           &err_line))
    {
      fprintf (stderr,
               "Invalid input for denomination key to 'sign': %s#%u at %u (skipping)\n",
               err_name,
               err_line,
               (unsigned int) index);
      GNUNET_JSON_parse_free (spec);
      global_ret = 7;
      test_shutdown ();
      return GNUNET_SYSERR;
    }
    GNUNET_CRYPTO_rsa_public_key_hash (denom_pub.rsa_public_key,
                                       &h_denom_pub);
    if (GNUNET_OK !=
        TALER_exchange_offline_denom_validity_verify (
          &h_denom_pub,
          stamp_start,
          stamp_expire_withdraw,
          stamp_expire_deposit,
          stamp_expire_legal,
          &coin_value,
          &fee_withdraw,
          &fee_deposit,
          &fee_refresh,
          &fee_refund,
          &master_pub,
          &master_sig))
    {
      fprintf (stderr,
               "Invalid master signature for key %s (aborting)\n",
               TALER_B2S (&h_denom_pub));
      global_ret = 9;
      test_shutdown ();
      return GNUNET_SYSERR;
    }

    {
      struct TALER_AuditorSignatureP auditor_sig;

      TALER_auditor_denom_validity_sign (auditor_url,
                                         &h_denom_pub,
                                         &master_pub,
                                         stamp_start,
                                         stamp_expire_withdraw,
                                         stamp_expire_deposit,
                                         stamp_expire_legal,
                                         &coin_value,
                                         &fee_withdraw,
                                         &fee_deposit,
                                         &fee_refresh,
                                         &fee_refund,
                                         &auditor_priv,
                                         &auditor_sig);
      output_operation (OP_SIGN_DENOMINATION,
                        json_pack ("{s:o, s:o}",
                                   "h_denom_pub",
                                   GNUNET_JSON_from_data_auto (&h_denom_pub),
                                   "auditor_sig",
                                   GNUNET_JSON_from_data_auto (&auditor_sig)));
    }
    GNUNET_JSON_parse_free (spec);
  }
  return GNUNET_OK;
}


/**
 * Sign denomination keys.
 *
 * @param args the array of command-line arguments to process next
 */
static void
do_sign (char *const *args)
{
  json_t *keys;
  const char *err_name;
  unsigned int err_line;
  struct TALER_MasterPublicKeyP mpub;
  json_t *denomkeys;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("denoms",
                           &denomkeys),
    GNUNET_JSON_spec_fixed_auto ("master_public_key",
                                 &mpub),
    GNUNET_JSON_spec_end ()
  };

  keys = parse_keys ("sign");
  if (NULL == keys)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Signing failed: no valid input\n");
    return;
  }
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
  {
    json_decref (keys);
    return;
  }
  if (GNUNET_OK !=
      GNUNET_JSON_parse (keys,
                         spec,
                         &err_name,
                         &err_line))
  {
    fprintf (stderr,
             "Invalid input to 'sign': %s#%u (skipping)\n",
             err_name,
             err_line);
    global_ret = 7;
    test_shutdown ();
    json_decref (keys);
    return;
  }
  if (0 !=
      GNUNET_memcmp (&mpub,
                     &master_pub))
  {
    fprintf (stderr,
             "Exchange master public key does not match key we have configured (aborting)\n");
    global_ret = 7;
    test_shutdown ();
    json_decref (keys);
    return;
  }
  if (NULL == out)
    out = json_array ();
  if (GNUNET_OK !=
      sign_denomkeys (denomkeys))
  {
    global_ret = 8;
    test_shutdown ();
    GNUNET_JSON_parse_free (spec);
    json_decref (keys);
    return;
  }
  GNUNET_JSON_parse_free (spec);
  json_decref (keys);
  next (args);
}


/**
 * Setup and output offline signing key.
 *
 * @param args the array of command-line arguments to process next
 */
static void
do_setup (char *const *args)
{
  if (GNUNET_OK !=
      load_offline_key (GNUNET_YES))
  {
    global_ret = 1;
    return;
  }
  if (NULL != *args)
  {
    if (NULL == out)
      out = json_array ();
    output_operation (OP_SETUP,
                      json_pack ("{s:o}",
                                 "auditor_pub",
                                 GNUNET_JSON_from_data_auto (&auditor_pub)));
  }

  else
  {
    char *pub_s;

    pub_s = GNUNET_STRINGS_data_to_string_alloc (&auditor_pub,
                                                 sizeof (auditor_pub));
    fprintf (stdout,
             "%s\n",
             pub_s);
    GNUNET_free (pub_s);
  }
  if ( (NULL != *args) &&
       (0 == strcmp (*args,
                     "-")) )
    args++;
  next (args);
}


static void
work (void *cls)
{
  char *const *args = cls;
  struct SubCommand cmds[] = {
    {
      .name = "setup",
      .help =
        "setup auditor offline private key and show the public key",
      .cb = &do_setup
    },
    {
      .name = "download",
      .help =
        "obtain keys from exchange (to be performed online!)",
      .cb = &do_download
    },
    {
      .name = "show",
      .help =
        "display keys from exchange for human review (pass '-' as argument to disable consuming input)",
      .cb = &do_show
    },
    {
      .name = "sign",
      .help =
        "sing all denomination keys from the input",
      .cb = &do_sign
    },
    {
      .name = "upload",
      .help =
        "upload operation result to exchange (to be performed online!)",
      .cb = &do_upload
    },
    /* list terminator */
    {
      .name = NULL,
    }
  };
  (void) cls;

  nxt = NULL;
  for (unsigned int i = 0; NULL != cmds[i].name; i++)
  {
    if (0 == strcasecmp (cmds[i].name,
                         args[0]))
    {
      cmds[i].cb (&args[1]);
      return;
    }
  }

  if (0 != strcasecmp ("help",
                       args[0]))
  {
    fprintf (stderr,
             "Unexpected command `%s'\n",
             args[0]);
    global_ret = 3;
  }
  fprintf (stderr,
           "Supported subcommands:\n");
  for (unsigned int i = 0; NULL != cmds[i].name; i++)
  {
    fprintf (stderr,
             "\t%s - %s\n",
             cmds[i].name,
             cmds[i].help);
  }
}


/**
 * Main function that will be run.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  kcfg = cfg;
  if (GNUNET_OK !=
      TALER_config_get_currency (kcfg,
                                 &currency))
  {
    global_ret = 1;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (kcfg,
                                             "auditor",
                                             "BASE_URL",
                                             &auditor_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "BASE_URL");
    global_ret = 1;
    return;
  }
  {
    char *master_public_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange",
                                               "MASTER_PUBLIC_KEY",
                                               &master_public_key_str))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "MASTER_PUBLIC_KEY");
      global_ret = 1;
      return;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_public_key_from_string (
          master_public_key_str,
          strlen (master_public_key_str),
          &master_pub.eddsa_pub))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid master public key given in exchange configuration.");
      GNUNET_free (master_public_key_str);
      global_ret = 1;
      return;
    }
    GNUNET_free (master_public_key_str);
  }
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  next (args);
}


/**
 * The main function of the taler-auditor-offline tool.  This tool is used to
 * sign denomination keys with the auditor's key.  It uses the long-term
 * offline private key of the auditor and generates signatures with it. It
 * also supports online operations with the exchange to download its input
 * data and to upload its results. Those online operations should be performed
 * on another machine in production!
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return 4;
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-auditor-offline",
    gettext_noop ("Operations for offline signing for a Taler exchange"),
    options,
    &run, NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return 3;
  if (GNUNET_NO == ret)
    return 0;
  return global_ret;
}


/* end of taler-auditor-offline.c */
