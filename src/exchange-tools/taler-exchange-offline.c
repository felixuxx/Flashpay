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
 * @file taler-exchange-offline.c
 * @brief Support for operations involving the exchange's offline master key.
 * @author Christian Grothoff
 */
#include <platform.h>
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"

/**
 * Name of the input for the 'sign' and 'show' operation.
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_INPUT_KEYS "exchange-input-keys-0"

/**
 * Name of the operation to 'disable auditor'
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_DISABLE_AUDITOR "exchange-disable-auditor-0"

/**
 * Name of the operation to 'enable auditor'
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_ENABLE_AUDITOR "exchange-enable-auditor-0"

/**
 * Name of the operation to 'enable wire'
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_ENABLE_WIRE "exchange-enable-wire-0"

/**
 * Name of the operation to 'disable wire'
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_DISABLE_WIRE "exchange-disable-wire-0"

/**
 * Name of the operation to set a 'wire-fee'
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_SET_WIRE_FEE "exchange-set-wire-fee-0"

/**
 * Name of the operation to 'upload' key signatures
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_UPLOAD_SIGS "exchange-upload-sigs-0"

/**
 * Name of the operation to 'revoke-denomination' key
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_REVOKE_DENOMINATION "exchange-revoke-denomination-0"

/**
 * Name of the operation to 'revoke-signkey'
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_REVOKE_SIGNKEY "exchange-revoke-signkey-0"


/**
 * Our private key, initialized in #load_offline_key().
 */
static struct TALER_MasterPrivateKeyP master_priv;

/**
 * Our private key, initialized in #load_offline_key().
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
 * Data structure for denomination revocation requests.
 */
struct DenomRevocationRequest
{

  /**
   * Kept in a DLL.
   */
  struct DenomRevocationRequest *next;

  /**
   * Kept in a DLL.
   */
  struct DenomRevocationRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *h;

  /**
   * Array index of the associated command.
   */
  size_t idx;
};


/**
 * Data structure for signkey revocation requests.
 */
struct SignkeyRevocationRequest
{

  /**
   * Kept in a DLL.
   */
  struct SignkeyRevocationRequest *next;

  /**
   * Kept in a DLL.
   */
  struct SignkeyRevocationRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementRevokeSigningKeyHandle *h;

  /**
   * Array index of the associated command.
   */
  size_t idx;
};


/**
 * Data structure for auditor add requests.
 */
struct AuditorAddRequest
{

  /**
   * Kept in a DLL.
   */
  struct AuditorAddRequest *next;

  /**
   * Kept in a DLL.
   */
  struct AuditorAddRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementAuditorEnableHandle *h;

  /**
   * Array index of the associated command.
   */
  size_t idx;
};


/**
 * Data structure for auditor del requests.
 */
struct AuditorDelRequest
{

  /**
   * Kept in a DLL.
   */
  struct AuditorDelRequest *next;

  /**
   * Kept in a DLL.
   */
  struct AuditorDelRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementAuditorDisableHandle *h;

  /**
   * Array index of the associated command.
   */
  size_t idx;
};


/**
 * Data structure for wire add requests.
 */
struct WireAddRequest
{

  /**
   * Kept in a DLL.
   */
  struct WireAddRequest *next;

  /**
   * Kept in a DLL.
   */
  struct WireAddRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementWireEnableHandle *h;

  /**
   * Array index of the associated command.
   */
  size_t idx;
};


/**
 * Data structure for wire del requests.
 */
struct WireDelRequest
{

  /**
   * Kept in a DLL.
   */
  struct WireDelRequest *next;

  /**
   * Kept in a DLL.
   */
  struct WireDelRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementWireDisableHandle *h;

  /**
   * Array index of the associated command.
   */
  size_t idx;
};


/**
 * Data structure for announcing wire fees.
 */
struct WireFeeRequest
{

  /**
   * Kept in a DLL.
   */
  struct WireFeeRequest *next;

  /**
   * Kept in a DLL.
   */
  struct WireFeeRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementSetWireFeeHandle *h;

  /**
   * Array index of the associated command.
   */
  size_t idx;
};


/**
 * Ongoing /keys request.
 */
struct UploadKeysRequest
{
  /**
   * Kept in a DLL.
   */
  struct UploadKeysRequest *next;

  /**
   * Kept in a DLL.
   */
  struct UploadKeysRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementPostKeysHandle *h;

  /**
   * Operation index.
   */
  size_t idx;
};


/**
 * Next work item to perform.
 */
static struct GNUNET_SCHEDULER_Task *nxt;

/**
 * Handle for #do_download.
 */
static struct TALER_EXCHANGE_ManagementGetKeysHandle *mgkh;

/**
 * Active denomiantion revocation requests.
 */
static struct DenomRevocationRequest *drr_head;

/**
 * Active denomiantion revocation requests.
 */
static struct DenomRevocationRequest *drr_tail;

/**
 * Active signkey revocation requests.
 */
static struct SignkeyRevocationRequest *srr_head;

/**
 * Active signkey revocation requests.
 */
static struct SignkeyRevocationRequest *srr_tail;

/**
 * Active auditor add requests.
 */
static struct AuditorAddRequest *aar_head;

/**
 * Active auditor add requests.
 */
static struct AuditorAddRequest *aar_tail;

/**
 * Active auditor del requests.
 */
static struct AuditorDelRequest *adr_head;

/**
 * Active auditor del requests.
 */
static struct AuditorDelRequest *adr_tail;

/**
 * Active wire add requests.
 */
static struct WireAddRequest *war_head;

/**
 * Active wire add requests.
 */
static struct WireAddRequest *war_tail;

/**
 * Active wire del requests.
 */
static struct WireDelRequest *wdr_head;

/**
 * Active wire del requests.
 */
static struct WireDelRequest *wdr_tail;

/**
 * Active wire fee requests.
 */
static struct WireFeeRequest *wfr_head;

/**
 * Active wire fee requests.
 */
static struct WireFeeRequest *wfr_tail;

/**
 * Active keys upload requests.
 */
static struct UploadKeysRequest *ukr_head;

/**
 * Active keys upload requests.
 */
static struct UploadKeysRequest *ukr_tail;


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
    struct DenomRevocationRequest *drr;

    while (NULL != (drr = drr_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete denomination revocation #%u\n",
                  (unsigned int) drr->idx);
      TALER_EXCHANGE_management_revoke_denomination_key_cancel (drr->h);
      GNUNET_CONTAINER_DLL_remove (drr_head,
                                   drr_tail,
                                   drr);
      GNUNET_free (drr);
    }
  }
  {
    struct SignkeyRevocationRequest *srr;

    while (NULL != (srr = srr_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete signkey revocation #%u\n",
                  (unsigned int) srr->idx);
      TALER_EXCHANGE_management_revoke_signing_key_cancel (srr->h);
      GNUNET_CONTAINER_DLL_remove (srr_head,
                                   srr_tail,
                                   srr);
      GNUNET_free (srr);
    }
  }

  {
    struct AuditorAddRequest *aar;

    while (NULL != (aar = aar_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete auditor add #%u\n",
                  (unsigned int) aar->idx);
      TALER_EXCHANGE_management_enable_auditor_cancel (aar->h);
      GNUNET_CONTAINER_DLL_remove (aar_head,
                                   aar_tail,
                                   aar);
      GNUNET_free (aar);
    }
  }
  {
    struct AuditorDelRequest *adr;

    while (NULL != (adr = adr_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete auditor del #%u\n",
                  (unsigned int) adr->idx);
      TALER_EXCHANGE_management_disable_auditor_cancel (adr->h);
      GNUNET_CONTAINER_DLL_remove (adr_head,
                                   adr_tail,
                                   adr);
      GNUNET_free (adr);
    }
  }
  {
    struct WireAddRequest *war;

    while (NULL != (war = war_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete wire add #%u\n",
                  (unsigned int) war->idx);
      TALER_EXCHANGE_management_enable_wire_cancel (war->h);
      GNUNET_CONTAINER_DLL_remove (war_head,
                                   war_tail,
                                   war);
      GNUNET_free (war);
    }
  }
  {
    struct WireDelRequest *wdr;

    while (NULL != (wdr = wdr_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete wire del #%u\n",
                  (unsigned int) wdr->idx);
      TALER_EXCHANGE_management_disable_wire_cancel (wdr->h);
      GNUNET_CONTAINER_DLL_remove (wdr_head,
                                   wdr_tail,
                                   wdr);
      GNUNET_free (wdr);
    }
  }
  {
    struct WireFeeRequest *wfr;

    while (NULL != (wfr = wfr_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete wire fee #%u\n",
                  (unsigned int) wfr->idx);
      TALER_EXCHANGE_management_set_wire_fees_cancel (wfr->h);
      GNUNET_CONTAINER_DLL_remove (wfr_head,
                                   wfr_tail,
                                   wfr);
      GNUNET_free (wfr);
    }
  }
  {
    struct UploadKeysRequest *ukr;

    while (NULL != (ukr = ukr_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete key signature upload #%u\n",
                  (unsigned int) ukr->idx);
      TALER_EXCHANGE_post_management_keys_cancel (ukr->h);
      GNUNET_CONTAINER_DLL_remove (ukr_head,
                                   ukr_tail,
                                   ukr);
      GNUNET_free (ukr);
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
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Input not consumed!\n");
    json_decref (in);
    in = NULL;
  }
  if (NULL != nxt)
  {
    GNUNET_SCHEDULER_cancel (nxt);
    nxt = NULL;
  }
  if (NULL != mgkh)
  {
    TALER_EXCHANGE_get_management_keys_cancel (mgkh);
    mgkh = NULL;
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
  if ( (NULL == drr_head) &&
       (NULL == srr_head) &&
       (NULL == aar_head) &&
       (NULL == adr_head) &&
       (NULL == war_head) &&
       (NULL == wdr_head) &&
       (NULL == wfr_head) &&
       (NULL == ukr_head) &&
       (NULL == mgkh) &&
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

  GNUNET_break (NULL != op_value);
  if (NULL == out)
    out = json_array ();
  action = json_pack ("{ s:s, s:o }",
                      "operation",
                      op_name,
                      "arguments",
                      op_value);
  GNUNET_break (NULL != action);
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
 * @return #GNUNET_OK on success
 */
static int
load_offline_key (void)
{
  static bool done;
  int ret;
  char *fn;

  if (done)
    return GNUNET_OK;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "exchange-offline",
                                               "MASTER_PRIV_FILE",
                                               &fn))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange-offline",
                               "MASTER_PRIV_FILE");
    test_shutdown ();
    return GNUNET_SYSERR;
  }
  if (GNUNET_YES !=
      GNUNET_DISK_file_test (fn))
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Exchange master private key `%s' does not exist yet, creating it!\n",
                fn);
  ret = GNUNET_CRYPTO_eddsa_key_from_file (fn,
                                           GNUNET_YES,
                                           &master_priv.eddsa_priv);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize master key from file `%s': %s\n",
                fn,
                "could not create file");
    GNUNET_free (fn);
    test_shutdown ();
    return GNUNET_SYSERR;
  }
  GNUNET_free (fn);
  GNUNET_CRYPTO_eddsa_key_get_public (&master_priv.eddsa_priv,
                                      &master_pub.eddsa_pub);
  done = true;
  return GNUNET_OK;
}


/**
 * Function called with information about the post revocation operation result.
 *
 * @param cls closure with a `struct DenomRevocationRequest`
 * @param hr HTTP response data
 */
static void
denom_revocation_cb (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct DenomRevocationRequest *drr = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) drr->idx,
                hr->http_status,
                hr->hint,
                TALER_JSON_get_error_hint (hr->reply));
    global_ret = 10;
  }
  GNUNET_CONTAINER_DLL_remove (drr_head,
                               drr_tail,
                               drr);
  GNUNET_free (drr);
  test_shutdown ();
}


/**
 * Upload denomination revocation request data.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value argumets for denomination revocation
 */
static void
upload_denom_revocation (const char *exchange_url,
                         size_t idx,
                         const json_t *value)
{
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_HashCode h_denom_pub;
  struct DenomRevocationRequest *drr;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                 &h_denom_pub),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input for denomination revocation: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    return;
  }
  drr = GNUNET_new (struct DenomRevocationRequest);
  drr->idx = idx;
  drr->h =
    TALER_EXCHANGE_management_revoke_denomination_key (ctx,
                                                       exchange_url,
                                                       &h_denom_pub,
                                                       &master_sig,
                                                       &denom_revocation_cb,
                                                       drr);
  GNUNET_CONTAINER_DLL_insert (drr_head,
                               drr_tail,
                               drr);
}


/**
 * Function called with information about the post revocation operation result.
 *
 * @param cls closure with a `struct SignkeyRevocationRequest`
 * @param hr HTTP response data
 */
static void
signkey_revocation_cb (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct SignkeyRevocationRequest *srr = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) srr->idx,
                hr->http_status,
                hr->hint,
                TALER_JSON_get_error_hint (hr->reply));
    global_ret = 10;
  }
  GNUNET_CONTAINER_DLL_remove (srr_head,
                               srr_tail,
                               srr);
  GNUNET_free (srr);
  test_shutdown ();
}


/**
 * Upload signkey revocation request data.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value argumets for denomination revocation
 */
static void
upload_signkey_revocation (const char *exchange_url,
                           size_t idx,
                           const json_t *value)
{
  struct TALER_MasterSignatureP master_sig;
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct SignkeyRevocationRequest *srr;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &exchange_pub),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input for signkey revocation: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    return;
  }
  srr = GNUNET_new (struct SignkeyRevocationRequest);
  srr->idx = idx;
  srr->h =
    TALER_EXCHANGE_management_revoke_signing_key (ctx,
                                                  exchange_url,
                                                  &exchange_pub,
                                                  &master_sig,
                                                  &signkey_revocation_cb,
                                                  srr);
  GNUNET_CONTAINER_DLL_insert (srr_head,
                               srr_tail,
                               srr);
}


/**
 * Function called with information about the post auditor add operation result.
 *
 * @param cls closure with a `struct AuditorAddRequest`
 * @param hr HTTP response data
 */
static void
auditor_add_cb (void *cls,
                const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct AuditorAddRequest *aar = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) aar->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = 10;
  }
  GNUNET_CONTAINER_DLL_remove (aar_head,
                               aar_tail,
                               aar);
  GNUNET_free (aar);
  test_shutdown ();
}


/**
 * Upload auditor add data.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value argumets for denomination revocation
 */
static void
upload_auditor_add (const char *exchange_url,
                    size_t idx,
                    const json_t *value)
{
  struct TALER_MasterSignatureP master_sig;
  const char *auditor_url;
  const char *auditor_name;
  struct GNUNET_TIME_Absolute start_time;
  struct TALER_AuditorPublicKeyP auditor_pub;
  struct AuditorAddRequest *aar;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("auditor_url",
                             &auditor_url),
    GNUNET_JSON_spec_string ("auditor_name",
                             &auditor_name),
    GNUNET_JSON_spec_absolute_time ("validity_start",
                                    &start_time),
    GNUNET_JSON_spec_fixed_auto ("auditor_pub",
                                 &auditor_pub),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input for adding auditor: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    return;
  }
  aar = GNUNET_new (struct AuditorAddRequest);
  aar->idx = idx;
  aar->h =
    TALER_EXCHANGE_management_enable_auditor (ctx,
                                              exchange_url,
                                              &auditor_pub,
                                              auditor_url,
                                              auditor_name,
                                              start_time,
                                              &master_sig,
                                              &auditor_add_cb,
                                              aar);
  GNUNET_CONTAINER_DLL_insert (aar_head,
                               aar_tail,
                               aar);
}


/**
 * Function called with information about the post auditor del operation result.
 *
 * @param cls closure with a `struct AuditorDelRequest`
 * @param hr HTTP response data
 */
static void
auditor_del_cb (void *cls,
                const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct AuditorDelRequest *adr = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) adr->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = 10;
  }
  GNUNET_CONTAINER_DLL_remove (adr_head,
                               adr_tail,
                               adr);
  GNUNET_free (adr);
  test_shutdown ();
}


/**
 * Upload auditor del data.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value argumets for denomination revocation
 */
static void
upload_auditor_del (const char *exchange_url,
                    size_t idx,
                    const json_t *value)
{
  struct TALER_AuditorPublicKeyP auditor_pub;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Absolute end_time;
  struct AuditorDelRequest *adr;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("auditor_pub",
                                 &auditor_pub),
    GNUNET_JSON_spec_absolute_time ("validity_end",
                                    &end_time),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to disable auditor: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    return;
  }
  adr = GNUNET_new (struct AuditorDelRequest);
  adr->idx = idx;
  adr->h =
    TALER_EXCHANGE_management_disable_auditor (ctx,
                                               exchange_url,
                                               &auditor_pub,
                                               end_time,
                                               &master_sig,
                                               &auditor_del_cb,
                                               adr);
  GNUNET_CONTAINER_DLL_insert (adr_head,
                               adr_tail,
                               adr);
}


/**
 * Function called with information about the post wire add operation result.
 *
 * @param cls closure with a `struct WireAddRequest`
 * @param hr HTTP response data
 */
static void
wire_add_cb (void *cls,
             const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct WireAddRequest *war = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) war->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = 10;
  }
  GNUNET_CONTAINER_DLL_remove (war_head,
                               war_tail,
                               war);
  GNUNET_free (war);
  test_shutdown ();
}


/**
 * Upload wire add data.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value argumets for denomination revocation
 */
static void
upload_wire_add (const char *exchange_url,
                 size_t idx,
                 const json_t *value)
{
  struct TALER_MasterSignatureP master_sig_add;
  struct TALER_MasterSignatureP master_sig_wire;
  const char *payto_uri;
  struct GNUNET_TIME_Absolute start_time;
  struct WireAddRequest *war;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri",
                             &payto_uri),
    GNUNET_JSON_spec_absolute_time ("validity_start",
                                    &start_time),
    GNUNET_JSON_spec_fixed_auto ("master_sig_add",
                                 &master_sig_add),
    GNUNET_JSON_spec_fixed_auto ("master_sig_wire",
                                 &master_sig_wire),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input for adding wire account: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    return;
  }
  war = GNUNET_new (struct WireAddRequest);
  war->idx = idx;
  war->h =
    TALER_EXCHANGE_management_enable_wire (ctx,
                                           exchange_url,
                                           payto_uri,
                                           start_time,
                                           &master_sig_add,
                                           &master_sig_wire,
                                           &wire_add_cb,
                                           war);
  GNUNET_CONTAINER_DLL_insert (war_head,
                               war_tail,
                               war);
}


/**
 * Function called with information about the post wire del operation result.
 *
 * @param cls closure with a `struct WireDelRequest`
 * @param hr HTTP response data
 */
static void
wire_del_cb (void *cls,
             const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct WireDelRequest *wdr = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) wdr->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = 10;
  }
  GNUNET_CONTAINER_DLL_remove (wdr_head,
                               wdr_tail,
                               wdr);
  GNUNET_free (wdr);
  test_shutdown ();
}


/**
 * Upload wire del data.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value argumets for denomination revocation
 */
static void
upload_wire_del (const char *exchange_url,
                 size_t idx,
                 const json_t *value)
{
  struct TALER_MasterSignatureP master_sig;
  const char *payto_uri;
  struct GNUNET_TIME_Absolute end_time;
  struct WireDelRequest *wdr;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri",
                             &payto_uri),
    GNUNET_JSON_spec_absolute_time ("validity_end",
                                    &end_time),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to disable wire account: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    return;
  }
  wdr = GNUNET_new (struct WireDelRequest);
  wdr->idx = idx;
  wdr->h =
    TALER_EXCHANGE_management_disable_wire (ctx,
                                            exchange_url,
                                            payto_uri,
                                            end_time,
                                            &master_sig,
                                            &wire_del_cb,
                                            wdr);
  GNUNET_CONTAINER_DLL_insert (wdr_head,
                               wdr_tail,
                               wdr);
}


/**
 * Function called with information about the post wire fee operation result.
 *
 * @param cls closure with a `struct WireFeeRequest`
 * @param hr HTTP response data
 */
static void
wire_fee_cb (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct WireFeeRequest *wfr = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) wfr->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = 10;
  }
  GNUNET_CONTAINER_DLL_remove (wfr_head,
                               wfr_tail,
                               wfr);
  GNUNET_free (wfr);
  test_shutdown ();
}


/**
 * Upload wire fee.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value argumets for denomination revocation
 */
static void
upload_wire_fee (const char *exchange_url,
                 size_t idx,
                 const json_t *value)
{
  struct TALER_MasterSignatureP master_sig;
  const char *wire_method;
  struct WireFeeRequest *wfr;
  const char *err_name;
  unsigned int err_line;
  struct TALER_Amount wire_fee;
  struct TALER_Amount closing_fee;
  struct GNUNET_TIME_Absolute start_time;
  struct GNUNET_TIME_Absolute end_time;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("wire_method",
                             &wire_method),
    TALER_JSON_spec_amount ("wire_fee",
                            &wire_fee),
    TALER_JSON_spec_amount ("closing_fee",
                            &closing_fee),
    GNUNET_JSON_spec_absolute_time ("start_time",
                                    &start_time),
    GNUNET_JSON_spec_absolute_time ("end_time",
                                    &end_time),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to set wire fee: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    return;
  }
  wfr = GNUNET_new (struct WireFeeRequest);
  wfr->idx = idx;
  wfr->h =
    TALER_EXCHANGE_management_set_wire_fees (ctx,
                                             exchange_url,
                                             wire_method,
                                             start_time,
                                             end_time,
                                             &wire_fee,
                                             &closing_fee,
                                             &master_sig,
                                             &wire_fee_cb,
                                             wfr);
  GNUNET_CONTAINER_DLL_insert (wfr_head,
                               wfr_tail,
                               wfr);
}


/**
 * Function called with information about the post upload keys operation result.
 *
 * @param cls closure with a `struct UploadKeysRequest`
 * @param hr HTTP response data
 */
static void
keys_cb (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct UploadKeysRequest *ukr = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) ukr->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = 10;
  }
  GNUNET_CONTAINER_DLL_remove (ukr_head,
                               ukr_tail,
                               ukr);
  GNUNET_free (ukr);
  test_shutdown ();
}


/**
 * Upload (denomination and signing) key master signatures.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value arguments for POSTing keys
 */
static void
upload_keys (const char *exchange_url,
             size_t idx,
             const json_t *value)
{
  struct TALER_EXCHANGE_ManagementPostKeysData pkd;
  struct UploadKeysRequest *ukr;
  const char *err_name;
  unsigned int err_line;
  json_t *denom_sigs;
  json_t *signkey_sigs;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("denom_sigs",
                           &denom_sigs),
    GNUNET_JSON_spec_json ("signkey_sigs",
                           &signkey_sigs),
    GNUNET_JSON_spec_end ()
  };
  bool ok = true;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to 'upload': %s#%u (skipping)\n",
                err_name,
                err_line);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    return;
  }
  pkd.num_sign_sigs = json_array_size (signkey_sigs);
  pkd.num_denom_sigs = json_array_size (denom_sigs);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Uploading %u denomination and %u signing key signatures\n",
              pkd.num_denom_sigs,
              pkd.num_sign_sigs);
  pkd.sign_sigs = GNUNET_new_array (
    pkd.num_sign_sigs,
    struct TALER_EXCHANGE_SigningKeySignature);
  pkd.denom_sigs = GNUNET_new_array (
    pkd.num_denom_sigs,
    struct TALER_EXCHANGE_DenominationKeySignature);
  for (unsigned int i = 0; i<pkd.num_sign_sigs; i++)
  {
    struct TALER_EXCHANGE_SigningKeySignature *ss = &pkd.sign_sigs[i];
    json_t *val = json_array_get (signkey_sigs,
                                  i);
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                   &ss->exchange_pub),
      GNUNET_JSON_spec_fixed_auto ("master_sig",
                                   &ss->master_sig),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (val,
                           spec,
                           &err_name,
                           &err_line))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid input for signkey validity: %s#%u at %u (aborting)\n",
                  err_name,
                  err_line,
                  i);
      json_dumpf (val,
                  stderr,
                  JSON_INDENT (2));
      ok = false;
    }
  }
  for (unsigned int i = 0; i<pkd.num_denom_sigs; i++)
  {
    struct TALER_EXCHANGE_DenominationKeySignature *ds = &pkd.denom_sigs[i];
    json_t *val = json_array_get (denom_sigs,
                                  i);
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                   &ds->h_denom_pub),
      GNUNET_JSON_spec_fixed_auto ("master_sig",
                                   &ds->master_sig),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (val,
                           spec,
                           &err_name,
                           &err_line))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid input for denomination validity: %s#%u at %u (aborting)\n",
                  err_name,
                  err_line,
                  i);
      json_dumpf (val,
                  stderr,
                  JSON_INDENT (2));
      ok = false;
    }
  }

  if (ok)
  {
    ukr = GNUNET_new (struct UploadKeysRequest);
    ukr->idx = idx;
    ukr->h =
      TALER_EXCHANGE_post_management_keys (ctx,
                                           exchange_url,
                                           &pkd,
                                           &keys_cb,
                                           ukr);
    GNUNET_CONTAINER_DLL_insert (ukr_head,
                                 ukr_tail,
                                 ukr);
  }
  else
  {
    global_ret = 7;
    test_shutdown ();
  }
  GNUNET_free (pkd.sign_sigs);
  GNUNET_free (pkd.denom_sigs);
  GNUNET_JSON_parse_free (spec);
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
      .key = OP_REVOKE_DENOMINATION,
      .cb = &upload_denom_revocation
    },
    {
      .key = OP_REVOKE_SIGNKEY,
      .cb = &upload_signkey_revocation
    },
    {
      .key = OP_ENABLE_AUDITOR,
      .cb = &upload_auditor_add
    },
    {
      .key = OP_DISABLE_AUDITOR,
      .cb = &upload_auditor_del
    },
    {
      .key = OP_ENABLE_WIRE,
      .cb = &upload_wire_add
    },
    {
      .key = OP_DISABLE_WIRE,
      .cb = &upload_wire_del
    },
    {
      .key = OP_SET_WIRE_FEE,
      .cb = &upload_wire_fee
    },
    {
      .key = OP_UPLOAD_SIGS,
      .cb = &upload_keys
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
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
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
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Upload does not know how to handle `%s'\n",
                  key);
      global_ret = 3;
      test_shutdown ();
      return;
    }
  }
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

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
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
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
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
 * Revoke denomination key.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the hash of the denomination key to revoke
 */
static void
do_revoke_denomination_key (char *const *args)
{
  struct GNUNET_HashCode h_denom_pub;
  struct TALER_MasterSignatureP master_sig;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, refusing revocation\n");
    test_shutdown ();
    global_ret = 4;
    return;
  }
  if ( (NULL == args[0]) ||
       (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &h_denom_pub,
                                       sizeof (h_denom_pub))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify a denomination key with this subcommand\n");
    test_shutdown ();
    global_ret = 5;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key ())
    return;
  TALER_exchange_offline_denomination_revoke_sign (&h_denom_pub,
                                                   &master_priv,
                                                   &master_sig);
  output_operation (OP_REVOKE_DENOMINATION,
                    json_pack ("{s:o, s:o}",
                               "h_denom_pub",
                               GNUNET_JSON_from_data_auto (&h_denom_pub),
                               "master_sig",
                               GNUNET_JSON_from_data_auto (&master_sig)));
  next (args + 1);
}


/**
 * Revoke signkey.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the hash of the denomination key to revoke
 */
static void
do_revoke_signkey (char *const *args)
{
  struct TALER_ExchangePublicKeyP exchange_pub;
  struct TALER_MasterSignatureP master_sig;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, refusing revocation\n");
    test_shutdown ();
    global_ret = 4;
    return;
  }
  if ( (NULL == args[0]) ||
       (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &exchange_pub,
                                       sizeof (exchange_pub))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify an exchange signing key with this subcommand\n");
    test_shutdown ();
    global_ret = 5;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key ())
    return;
  TALER_exchange_offline_signkey_revoke_sign (&exchange_pub,
                                              &master_priv,
                                              &master_sig);
  output_operation (OP_REVOKE_SIGNKEY,
                    json_pack ("{s:o, s:o}",
                               "exchange_pub",
                               GNUNET_JSON_from_data_auto (&exchange_pub),
                               "master_sig",
                               GNUNET_JSON_from_data_auto (&master_sig)));
  next (args + 1);
}


/**
 * Add auditor.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the auditor's public key, args[1] the auditor's
 *        API base URL, and args[2] the auditor's name.
 */
static void
do_add_auditor (char *const *args)
{
  struct TALER_MasterSignatureP master_sig;
  struct TALER_AuditorPublicKeyP auditor_pub;
  struct GNUNET_TIME_Absolute now;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not adding auditor\n");
    test_shutdown ();
    global_ret = 4;
    return;
  }
  if ( (NULL == args[0]) ||
       (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &auditor_pub,
                                       sizeof (auditor_pub))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify an auditor public key as first argument for this subcommand\n");
    test_shutdown ();
    global_ret = 5;
    return;
  }

  if ( (NULL == args[1]) ||
       (0 != strncmp ("http",
                      args[1],
                      strlen ("http"))) ||
       (NULL == args[2]) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify an auditor URI and auditor name as 2nd and 3rd arguments to this subcommand\n");
    test_shutdown ();
    global_ret = 5;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key ())
    return;
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);

  TALER_exchange_offline_auditor_add_sign (&auditor_pub,
                                           args[1],
                                           now,
                                           &master_priv,
                                           &master_sig);
  output_operation (OP_ENABLE_AUDITOR,
                    json_pack ("{s:s, s:s, s:o, s:o, s:o}",
                               "auditor_url",
                               args[1],
                               "auditor_name",
                               args[2],
                               "validity_start",
                               GNUNET_JSON_from_time_abs (now),
                               "auditor_pub",
                               GNUNET_JSON_from_data_auto (&auditor_pub),
                               "master_sig",
                               GNUNET_JSON_from_data_auto (&master_sig)));
  next (args + 3);
}


/**
 * Disable auditor account.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the hash of the denomination key to revoke
 */
static void
do_del_auditor (char *const *args)
{
  struct TALER_MasterSignatureP master_sig;
  struct TALER_AuditorPublicKeyP auditor_pub;
  struct GNUNET_TIME_Absolute now;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not deleting auditor account\n");
    test_shutdown ();
    global_ret = 4;
    return;
  }
  if ( (NULL == args[0]) ||
       (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &auditor_pub,
                                       sizeof (auditor_pub))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify an auditor public key as first argument for this subcommand\n");
    test_shutdown ();
    global_ret = 5;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key ())
    return;
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);

  TALER_exchange_offline_auditor_del_sign (&auditor_pub,
                                           now,
                                           &master_priv,
                                           &master_sig);
  output_operation (OP_DISABLE_AUDITOR,
                    json_pack ("{s:o, s:o, s:o}",
                               "auditor_pub",
                               GNUNET_JSON_from_data_auto (&auditor_pub),
                               "validity_end",
                               GNUNET_JSON_from_time_abs (now),
                               "master_sig",
                               GNUNET_JSON_from_data_auto (&master_sig)));
  next (args + 1);
}


/**
 * Add wire account.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the hash of the denomination key to revoke
 */
static void
do_add_wire (char *const *args)
{
  struct TALER_MasterSignatureP master_sig_add;
  struct TALER_MasterSignatureP master_sig_wire;
  struct GNUNET_TIME_Absolute now;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not adding wire account\n");
    test_shutdown ();
    global_ret = 4;
    return;
  }
  if (NULL == args[0])
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify a payto://-URI with this subcommand\n");
    test_shutdown ();
    global_ret = 5;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key ())
    return;
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);

  TALER_exchange_offline_wire_add_sign (args[0],
                                        now,
                                        &master_priv,
                                        &master_sig_add);
  TALER_exchange_wire_signature_make (args[0],
                                      &master_priv,
                                      &master_sig_wire);
  output_operation (OP_ENABLE_WIRE,
                    json_pack ("{s:s, s:o, s:o, s:o}",
                               "payto_uri",
                               args[0],
                               "validity_start",
                               GNUNET_JSON_from_time_abs (now),
                               "master_sig_add",
                               GNUNET_JSON_from_data_auto (&master_sig_add),
                               "master_sig_wire",
                               GNUNET_JSON_from_data_auto (&master_sig_wire)));
  next (args + 1);
}


/**
 * Disable wire account.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the hash of the denomination key to revoke
 */
static void
do_del_wire (char *const *args)
{
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Absolute now;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not deleting wire account\n");
    test_shutdown ();
    global_ret = 4;
    return;
  }
  if (NULL == args[0])
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify a payto://-URI with this subcommand\n");
    test_shutdown ();
    global_ret = 5;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key ())
    return;
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);

  TALER_exchange_offline_wire_del_sign (args[0],
                                        now,
                                        &master_priv,
                                        &master_sig);
  output_operation (OP_DISABLE_WIRE,
                    json_pack ("{s:s, s:o, s:o}",
                               "payto_uri",
                               args[0],
                               "validity_end",
                               GNUNET_JSON_from_time_abs (now),
                               "master_sig",
                               GNUNET_JSON_from_data_auto (&master_sig)));
  next (args + 1);
}


/**
 * Set wire fees for the given year.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the year, args[1] the wire fee and args[2]
 *        the closing fee.
 */
static void
do_set_wire_fee (char *const *args)
{
  struct TALER_MasterSignatureP master_sig;
  char dummy;
  unsigned int year;
  struct TALER_Amount wire_fee;
  struct TALER_Amount closing_fee;
  struct GNUNET_TIME_Absolute start_time;
  struct GNUNET_TIME_Absolute end_time;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not setting wire fee\n");
    test_shutdown ();
    global_ret = 4;
    return;
  }
  if ( (NULL == args[0]) ||
       (NULL == args[1]) ||
       (NULL == args[2]) ||
       (NULL == args[3]) ||
       ( (1 != sscanf (args[0],
                       "%u%c",
                       &year,
                       &dummy)) &&
         (0 != strcasecmp ("now",
                           args[0])) ) ||
       (GNUNET_OK !=
        TALER_string_to_amount (args[2],
                                &wire_fee)) ||
       (GNUNET_OK !=
        TALER_string_to_amount (args[3],
                                &closing_fee)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must use YEAR, METHOD, WIRE-FEE and CLOSING-FEE as arguments for this subcommand\n");
    test_shutdown ();
    global_ret = 5;
    return;
  }
  if (0 == strcasecmp ("now",
                       args[0]))
    year = GNUNET_TIME_get_current_year ();
  if (GNUNET_OK !=
      load_offline_key ())
    return;
  start_time = GNUNET_TIME_year_to_time (year);
  end_time = GNUNET_TIME_year_to_time (year + 1);

  TALER_exchange_offline_wire_fee_sign (args[1],
                                        start_time,
                                        end_time,
                                        &wire_fee,
                                        &closing_fee,
                                        &master_priv,
                                        &master_sig);
  output_operation (OP_SET_WIRE_FEE,
                    json_pack ("{s:s, s:o, s:o, s:o, s:o, s:o}",
                               "wire_method",
                               args[1],
                               "start_time",
                               GNUNET_JSON_from_time_abs (start_time),
                               "end_time",
                               GNUNET_JSON_from_time_abs (end_time),
                               "wire_fee",
                               TALER_JSON_from_amount (&wire_fee),
                               "closing_fee",
                               TALER_JSON_from_amount (&closing_fee),
                               "master_sig",
                               GNUNET_JSON_from_data_auto (&master_sig)));
  next (args + 4);
}


/**
 * Function called with information about future keys.  Dumps the JSON output
 * (on success), either into an internal buffer or to stdout (depending on
 * whether there are subsequent commands).
 *
 * @param cls closure with the `char **` remaining args
 * @param hr HTTP response data
 * @param keys information about the various keys used
 *        by the exchange, NULL if /management/keys failed
 */
static void
download_cb (void *cls,
             const struct TALER_EXCHANGE_HttpResponse *hr,
             const struct TALER_EXCHANGE_FutureKeys *keys)
{
  char *const *args = cls;

  mgkh = NULL;
  switch (hr->http_status)
  {
  case MHD_HTTP_OK:
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to download keys: %s (HTTP status: %u/%u)\n",
                hr->hint,
                hr->http_status,
                (unsigned int) hr->ec);
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
  mgkh = TALER_EXCHANGE_get_management_keys (ctx,
                                             exchange_url,
                                             &download_cb,
                                             (void *) args);
  GNUNET_free (exchange_url);
}


/**
 * Check that the security module keys are the same as before.  If we had no
 * keys in store before, remember them (Trust On First Use).
 *
 * @param secm security module keys, must be an array of length 2
 * @return #GNUNET_OK if keys match with what we have in store
 *         #GNUNET_NO if we had nothing in store but now do
 *         #GNUNET_SYSERR if keys changed from what we remember or other error
 */
static int
tofu_check (const struct TALER_SecurityModulePublicKeyP secm[2])
{
  char *fn;
  struct TALER_SecurityModulePublicKeyP old[2];
  ssize_t ret;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "exchange-offline",
                                               "SECM_TOFU_FILE",
                                               &fn))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange-offline",
                               "SECM_TOFU_FILE");
    return GNUNET_SYSERR;
  }
  ret = GNUNET_DISK_fn_read (fn,
                             &old,
                             sizeof (old));
  if (GNUNET_SYSERR != ret)
  {
    if (ret != sizeof (old))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "File `%s' corrupt\n",
                  fn);
      GNUNET_free (fn);
      return GNUNET_SYSERR;
    }
    /* TOFU check */
    if (0 != memcmp (old,
                     secm,
                     sizeof (old)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Fatal: security module keys changed (file `%s')!\n",
                  fn);
      GNUNET_free (fn);
      return GNUNET_SYSERR;
    }
    GNUNET_free (fn);
    return GNUNET_OK;
  }
  else
  {
    char *key;

    /* check against SECMOD-keys pinned in configuration */
    if (GNUNET_OK ==
        GNUNET_CONFIGURATION_get_value_string (kcfg,
                                               "exchange-offline",
                                               "SECM_ESIGN_PUBKEY",
                                               &key))
    {
      struct TALER_SecurityModulePublicKeyP k;

      if (GNUNET_OK !=
          GNUNET_STRINGS_string_to_data (key,
                                         strlen (key),
                                         &k,
                                         sizeof (k)))
      {
        GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                   "exchange-offline",
                                   "SECM_ESIGN_PUBKEY",
                                   "key malformed");
        GNUNET_free (key);
        return GNUNET_SYSERR;
      }
      GNUNET_free (key);
      if (0 !=
          GNUNET_memcmp (&k,
                         &secm[1]))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "ESIGN security module key does not match SECM_ESIGN_PUBKEY in configuration\n");
        return GNUNET_SYSERR;
      }
    }
    if (GNUNET_OK ==
        GNUNET_CONFIGURATION_get_value_string (kcfg,
                                               "exchange-offline",
                                               "SECM_DENOM_PUBKEY",
                                               &key))
    {
      struct TALER_SecurityModulePublicKeyP k;

      if (GNUNET_OK !=
          GNUNET_STRINGS_string_to_data (key,
                                         strlen (key),
                                         &k,
                                         sizeof (k)))
      {
        GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                   "exchange-offline",
                                   "SECM_DENOM_PUBKEY",
                                   "key malformed");
        GNUNET_free (key);
        return GNUNET_SYSERR;
      }
      GNUNET_free (key);
      if (0 !=
          GNUNET_memcmp (&k,
                         &secm[0]))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "DENOM security module key does not match SECM_DENOM_PUBKEY in configuration\n");
        return GNUNET_SYSERR;
      }
    }
  }
  /* persist keys for future runs */
  if (GNUNET_OK !=
      GNUNET_DISK_fn_write (fn,
                            secm,
                            sizeof (old),
                            GNUNET_DISK_PERM_USER_READ))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to store key material in file `%s'\n",
                fn);
    GNUNET_free (fn);
    return GNUNET_SYSERR;
  }
  return GNUNET_NO;
}


/**
 * Output @a signkeys for human consumption.
 *
 * @param secm_pub security module public key used to sign the denominations
 * @param signkeys keys to output
 * @return #GNUNET_OK on success
 */
static int
show_signkeys (const struct TALER_SecurityModulePublicKeyP *secm_pub,
               const json_t *signkeys)
{
  size_t index;
  json_t *value;

  json_array_foreach (signkeys, index, value) {
    const char *err_name;
    unsigned int err_line;
    struct TALER_ExchangePublicKeyP exchange_pub;
    struct TALER_SecurityModuleSignatureP secm_sig;
    struct GNUNET_TIME_Absolute start_time;
    struct GNUNET_TIME_Absolute sign_end;
    struct GNUNET_TIME_Absolute legal_end;
    struct GNUNET_TIME_Relative duration;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_absolute_time ("stamp_start",
                                      &start_time),
      GNUNET_JSON_spec_absolute_time ("stamp_expire",
                                      &sign_end),
      GNUNET_JSON_spec_absolute_time ("stamp_end",
                                      &legal_end),
      GNUNET_JSON_spec_fixed_auto ("key",
                                   &exchange_pub),
      GNUNET_JSON_spec_fixed_auto ("signkey_secmod_sig",
                                   &secm_sig),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (value,
                           spec,
                           &err_name,
                           &err_line))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid input for signing key to 'show': %s#%u at %u (skipping)\n",
                  err_name,
                  err_line,
                  (unsigned int) index);
      json_dumpf (value,
                  stderr,
                  JSON_INDENT (2));
      global_ret = 7;
      test_shutdown ();
      return GNUNET_SYSERR;
    }
    duration = GNUNET_TIME_absolute_get_difference (start_time,
                                                    sign_end);
    if (GNUNET_OK !=
        TALER_exchange_secmod_eddsa_verify (&exchange_pub,
                                            start_time,
                                            duration,
                                            secm_pub,
                                            &secm_sig))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid security module signature for signing key %s (aborting)\n",
                  TALER_B2S (&exchange_pub));
      global_ret = 9;
      test_shutdown ();
      return GNUNET_SYSERR;
    }
    {
      char *legal_end_s;

      legal_end_s = GNUNET_strdup (
        GNUNET_STRINGS_absolute_time_to_string (legal_end));
      printf ("EXCHANGE-KEY %s starting at %s (used for: %s, legal end: %s)\n",
              TALER_B2S (&exchange_pub),
              GNUNET_STRINGS_absolute_time_to_string (start_time),
              GNUNET_STRINGS_relative_time_to_string (duration,
                                                      GNUNET_NO),
              legal_end_s);
      GNUNET_free (legal_end_s);
    }
  }
  return GNUNET_OK;
}


/**
 * Output @a denomkeys for human consumption.
 *
 * @param secm_pub security module public key used to sign the denominations
 * @param denomkeys keys to output
 * @return #GNUNET_OK on success
 */
static int
show_denomkeys (const struct TALER_SecurityModulePublicKeyP *secm_pub,
                const json_t *denomkeys)
{
  size_t index;
  json_t *value;

  json_array_foreach (denomkeys, index, value) {
    const char *err_name;
    unsigned int err_line;
    const char *section_name;
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
    struct TALER_SecurityModuleSignatureP secm_sig;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("section_name",
                               &section_name),
      GNUNET_JSON_spec_rsa_public_key ("denom_pub",
                                       &denom_pub.rsa_public_key),
      TALER_JSON_spec_amount ("value",
                              &coin_value),
      TALER_JSON_spec_amount ("fee_withdraw",
                              &fee_withdraw),
      TALER_JSON_spec_amount ("fee_deposit",
                              &fee_deposit),
      TALER_JSON_spec_amount ("fee_refresh",
                              &fee_refresh),
      TALER_JSON_spec_amount ("fee_refund",
                              &fee_refund),
      GNUNET_JSON_spec_absolute_time ("stamp_start",
                                      &stamp_start),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_withdraw",
                                      &stamp_expire_withdraw),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_deposit",
                                      &stamp_expire_deposit),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_legal",
                                      &stamp_expire_legal),
      GNUNET_JSON_spec_fixed_auto ("denom_secmod_sig",
                                   &secm_sig),
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
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid input for denomination key to 'show': %s#%u at %u (skipping)\n",
                  err_name,
                  err_line,
                  (unsigned int) index);
      json_dumpf (value,
                  stderr,
                  JSON_INDENT (2));
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
        TALER_exchange_secmod_rsa_verify (&h_denom_pub,
                                          section_name,
                                          stamp_start,
                                          duration,
                                          secm_pub,
                                          &secm_sig))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid security module signature for denomination key %s (aborting)\n",
                  GNUNET_h2s (&h_denom_pub));
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
        "DENOMINATION-KEY(%s) %s of value %s starting at %s "
        "(used for: %s, deposit until: %s legal end: %s) with fees %s/%s/%s/%s\n",
        section_name,
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
 * Parse the input of exchange keys for the 'show' and 'sign' commands.
 *
 * @param command_name name of the command, for logging
 * @return NULL on error, otherwise the keys details to be free'd by caller
 */
static json_t *
parse_keys_input (const char *command_name)
{
  const char *op_str;
  json_t *keys;
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
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
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
 * Show future keys.
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
  json_t *signkeys;
  struct TALER_MasterPublicKeyP mpub;
  struct TALER_SecurityModulePublicKeyP secm[2];
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("future_denoms",
                           &denomkeys),
    GNUNET_JSON_spec_json ("future_signkeys",
                           &signkeys),
    GNUNET_JSON_spec_fixed_auto ("master_pub",
                                 &mpub),
    GNUNET_JSON_spec_fixed_auto ("denom_secmod_public_key",
                                 &secm[0]),
    GNUNET_JSON_spec_fixed_auto ("signkey_secmod_public_key",
                                 &secm[1]),
    GNUNET_JSON_spec_end ()
  };

  keys = parse_keys_input ("show");
  if (NULL == keys)
    return;
  if (GNUNET_OK !=
      load_offline_key ())
    return;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (keys,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to 'show': %s #%u (skipping)\n",
                err_name,
                err_line);
    json_dumpf (in,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    json_decref (keys);
    return;
  }
  if (0 !=
      GNUNET_memcmp (&master_pub,
                     &mpub))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Fatal: exchange uses different master key!\n");
    global_ret = 6;
    test_shutdown ();
    GNUNET_JSON_parse_free (spec);
    json_decref (keys);
    return;
  }
  if (GNUNET_SYSERR ==
      tofu_check (secm))
  {
    global_ret = 8;
    test_shutdown ();
    GNUNET_JSON_parse_free (spec);
    json_decref (keys);
    return;
  }
  if ( (GNUNET_OK !=
        show_signkeys (&secm[1],
                       signkeys)) ||
       (GNUNET_OK !=
        show_denomkeys (&secm[0],
                        denomkeys)) )
  {
    global_ret = 8;
    test_shutdown ();
    GNUNET_JSON_parse_free (spec);
    json_decref (keys);
    return;
  }
  json_decref (keys);
  GNUNET_JSON_parse_free (spec);
  next (args);
}


/**
 * Sign @a signkeys with offline key.
 *
 * @param secm_pub security module public key used to sign the denominations
 * @param signkeys keys to output
 * @param[in,out] result array where to output the signatures
 * @return #GNUNET_OK on success
 */
static int
sign_signkeys (const struct TALER_SecurityModulePublicKeyP *secm_pub,
               const json_t *signkeys,
               json_t *result)
{
  size_t index;
  json_t *value;

  json_array_foreach (signkeys, index, value) {
    const char *err_name;
    unsigned int err_line;
    struct TALER_ExchangePublicKeyP exchange_pub;
    struct TALER_SecurityModuleSignatureP secm_sig;
    struct GNUNET_TIME_Absolute start_time;
    struct GNUNET_TIME_Absolute sign_end;
    struct GNUNET_TIME_Absolute legal_end;
    struct GNUNET_TIME_Relative duration;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_absolute_time ("stamp_start",
                                      &start_time),
      GNUNET_JSON_spec_absolute_time ("stamp_expire",
                                      &sign_end),
      GNUNET_JSON_spec_absolute_time ("stamp_end",
                                      &legal_end),
      GNUNET_JSON_spec_fixed_auto ("key",
                                   &exchange_pub),
      GNUNET_JSON_spec_fixed_auto ("signkey_secmod_sig",
                                   &secm_sig),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (value,
                           spec,
                           &err_name,
                           &err_line))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid input for signing key to 'show': %s #%u at %u (skipping)\n",
                  err_name,
                  err_line,
                  (unsigned int) index);
      json_dumpf (value,
                  stderr,
                  JSON_INDENT (2));
      global_ret = 7;
      test_shutdown ();
      return GNUNET_SYSERR;
    }

    duration = GNUNET_TIME_absolute_get_difference (start_time,
                                                    sign_end);
    if (GNUNET_OK !=
        TALER_exchange_secmod_eddsa_verify (&exchange_pub,
                                            start_time,
                                            duration,
                                            secm_pub,
                                            &secm_sig))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid security module signature for signing key %s (aborting)\n",
                  TALER_B2S (&exchange_pub));
      global_ret = 9;
      test_shutdown ();
      GNUNET_JSON_parse_free (spec);
      return GNUNET_SYSERR;
    }
    {
      struct TALER_MasterSignatureP master_sig;

      TALER_exchange_offline_signkey_validity_sign (&exchange_pub,
                                                    start_time,
                                                    sign_end,
                                                    legal_end,
                                                    &master_priv,
                                                    &master_sig);
      GNUNET_assert (0 ==
                     json_array_append_new (
                       result,
                       json_pack ("{s:o,s:o}",
                                  "exchange_pub",
                                  GNUNET_JSON_from_data_auto (&exchange_pub),
                                  "master_sig",
                                  GNUNET_JSON_from_data_auto (&master_sig))));
    }
    GNUNET_JSON_parse_free (spec);
  }
  return GNUNET_OK;
}


/**
 * Sign @a denomkeys with offline key.
 *
 * @param secm_pub security module public key used to sign the denominations
 * @param denomkeys keys to output
 * @param[in,out] result array where to output the signatures
 * @return #GNUNET_OK on success
 */
static int
sign_denomkeys (const struct TALER_SecurityModulePublicKeyP *secm_pub,
                const json_t *denomkeys,
                json_t *result)
{
  size_t index;
  json_t *value;

  json_array_foreach (denomkeys, index, value) {
    const char *err_name;
    unsigned int err_line;
    const char *section_name;
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
    struct TALER_SecurityModuleSignatureP secm_sig;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("section_name",
                               &section_name),
      GNUNET_JSON_spec_rsa_public_key ("denom_pub",
                                       &denom_pub.rsa_public_key),
      TALER_JSON_spec_amount ("value",
                              &coin_value),
      TALER_JSON_spec_amount ("fee_withdraw",
                              &fee_withdraw),
      TALER_JSON_spec_amount ("fee_deposit",
                              &fee_deposit),
      TALER_JSON_spec_amount ("fee_refresh",
                              &fee_refresh),
      TALER_JSON_spec_amount ("fee_refund",
                              &fee_refund),
      GNUNET_JSON_spec_absolute_time ("stamp_start",
                                      &stamp_start),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_withdraw",
                                      &stamp_expire_withdraw),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_deposit",
                                      &stamp_expire_deposit),
      GNUNET_JSON_spec_absolute_time ("stamp_expire_legal",
                                      &stamp_expire_legal),
      GNUNET_JSON_spec_fixed_auto ("denom_secmod_sig",
                                   &secm_sig),
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
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid input for denomination key to 'sign': %s #%u at %u (skipping)\n",
                  err_name,
                  err_line,
                  (unsigned int) index);
      json_dumpf (value,
                  stderr,
                  JSON_INDENT (2));
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
        TALER_exchange_secmod_rsa_verify (&h_denom_pub,
                                          section_name,
                                          stamp_start,
                                          duration,
                                          secm_pub,
                                          &secm_sig))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid security module signature for denomination key %s (aborting)\n",
                  GNUNET_h2s (&h_denom_pub));
      global_ret = 9;
      test_shutdown ();
      GNUNET_JSON_parse_free (spec);
      return GNUNET_SYSERR;
    }

    {
      struct TALER_MasterSignatureP master_sig;

      TALER_exchange_offline_denom_validity_sign (&h_denom_pub,
                                                  stamp_start,
                                                  stamp_expire_withdraw,
                                                  stamp_expire_deposit,
                                                  stamp_expire_legal,
                                                  &coin_value,
                                                  &fee_withdraw,
                                                  &fee_deposit,
                                                  &fee_refresh,
                                                  &fee_refund,
                                                  &master_priv,
                                                  &master_sig);
      GNUNET_assert (0 ==
                     json_array_append_new (
                       result,
                       json_pack (
                         "{s:o,s:o}",
                         "h_denom_pub",
                         GNUNET_JSON_from_data_auto (&h_denom_pub),
                         "master_sig",
                         GNUNET_JSON_from_data_auto (&master_sig))));
    }
    GNUNET_JSON_parse_free (spec);
  }
  return GNUNET_OK;
}


/**
 * Sign future keys.
 *
 * @param args the array of command-line arguments to process next
 */
static void
do_sign (char *const *args)
{
  json_t *keys;
  const char *err_name;
  unsigned int err_line;
  json_t *denomkeys;
  json_t *signkeys;
  struct TALER_MasterPublicKeyP mpub;
  struct TALER_SecurityModulePublicKeyP secm[2];
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("future_denoms",
                           &denomkeys),
    GNUNET_JSON_spec_json ("future_signkeys",
                           &signkeys),
    GNUNET_JSON_spec_fixed_auto ("master_pub",
                                 &mpub),
    GNUNET_JSON_spec_fixed_auto ("denom_secmod_public_key",
                                 &secm[0]),
    GNUNET_JSON_spec_fixed_auto ("signkey_secmod_public_key",
                                 &secm[1]),
    GNUNET_JSON_spec_end ()
  };

  keys = parse_keys_input ("sign");
  if (NULL == keys)
    return;
  if (GNUNET_OK !=
      load_offline_key ())
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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to 'sign' : %s #%u (skipping)\n",
                err_name,
                err_line);
    json_dumpf (in,
                stderr,
                JSON_INDENT (2));
    global_ret = 7;
    test_shutdown ();
    json_decref (keys);
    return;
  }
  if (0 !=
      GNUNET_memcmp (&master_pub,
                     &mpub))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Fatal: exchange uses different master key!\n");
    global_ret = 6;
    test_shutdown ();
    GNUNET_JSON_parse_free (spec);
    json_decref (keys);
    return;
  }
  if (GNUNET_SYSERR ==
      tofu_check (secm))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Fatal: security module keys changed!\n");
    global_ret = 8;
    test_shutdown ();
    GNUNET_JSON_parse_free (spec);
    json_decref (keys);
    return;
  }
  {
    json_t *signkey_sig_array = json_array ();
    json_t *denomkey_sig_array = json_array ();

    GNUNET_assert (NULL != signkey_sig_array);
    GNUNET_assert (NULL != denomkey_sig_array);
    if ( (GNUNET_OK !=
          sign_signkeys (&secm[1],
                         signkeys,
                         signkey_sig_array)) ||
         (GNUNET_OK !=
          sign_denomkeys (&secm[0],
                          denomkeys,
                          denomkey_sig_array)) )
    {
      global_ret = 8;
      test_shutdown ();
      json_decref (signkey_sig_array);
      json_decref (denomkey_sig_array);
      GNUNET_JSON_parse_free (spec);
      json_decref (keys);
      return;
    }

    output_operation (OP_UPLOAD_SIGS,
                      json_pack ("{s:o,s:o}",
                                 "denom_sigs",
                                 denomkey_sig_array,
                                 "signkey_sigs",
                                 signkey_sig_array));
  }
  GNUNET_JSON_parse_free (spec);
  json_decref (keys);
  next (args);
}


static void
work (void *cls)
{
  char *const *args = cls;
  struct SubCommand cmds[] = {
    {
      .name = "download",
      .help =
        "obtain future public keys from exchange (to be performed online!)",
      .cb = &do_download
    },
    {
      .name = "show",
      .help =
        "display future public keys from exchange for human review (pass '-' as argument to disable consuming input)",
      .cb = &do_show
    },
    {
      .name = "sign",
      .help = "sign all future public keys from the input",
      .cb = &do_sign
    },
    {
      .name = "revoke-denomination",
      .help =
        "revoke denomination key (hash of public key must be given as argument)",
      .cb = &do_revoke_denomination_key
    },
    {
      .name = "revoke-signkey",
      .help =
        "revoke exchange online signing key (public key must be given as argument)",
      .cb = &do_revoke_signkey
    },
    {
      .name = "enable-auditor",
      .help =
        "enable auditor for the exchange (auditor-public key, auditor-URI and auditor-name must be given as arguments)",
      .cb = &do_add_auditor
    },
    {
      .name = "disable-auditor",
      .help =
        "disable auditor at the exchange (auditor-public key must be given as argument)",
      .cb = &do_del_auditor
    },
    {
      .name = "enable-account",
      .help =
        "enable wire account of the exchange (payto-URI must be given as argument)",
      .cb = &do_add_wire
    },
    {
      .name = "disable-account",
      .help =
        "disable wire account of the exchange (payto-URI must be given as argument)",
      .cb = &do_del_wire
    },
    {
      .name = "wire-fee",
      .help =
        "sign wire fees for the given year (year, wire method, wire fee and closing fee must be given as arguments)",
      .cb = &do_set_wire_fee
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
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "Unexpected command `%s'\n",
                args[0]);
    global_ret = 3;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Supported subcommands:\n");
  for (unsigned int i = 0; NULL != cmds[i].name; i++)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "- %s: %s\n",
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
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  next (args);
}


/**
 * The main function of the taler-exchange-offline tool.  This tool is used to
 * create the signing and denomination keys for the exchange.  It uses the
 * long-term offline private key and generates signatures with it. It also
 * supports online operations with the exchange to download its input data and
 * to upload its results. Those online operations should be performed on
 * another machine in production!
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

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "taler-exchange-offline",
                          "Operations for offline signing for a Taler exchange",
                          options,
                          &run, NULL))
    return 1;
  return global_ret;
}


/* end of taler-exchange-offline.c */
