/*
   This file is part of TALER
   Copyright (C) 2020-2023 Taler Systems SA

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
#include <gnunet/gnunet_util_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "taler_extensions.h"

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
 * Name of the operation to set a 'global-fee'
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_SET_GLOBAL_FEE "exchange-set-global-fee-0"

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
 * Show the offline signing key.
 * The last component --by convention-- identifies the protocol version
 * and should be incremented whenever the JSON format of the 'argument' changes.
 */
#define OP_SETUP "exchange-setup-0"

/**
 * sign the enabled and configured extensions.
 */
#define OP_EXTENSIONS "exchange-extensions-0"

/**
 * Generate message to drain profits.
 */
#define OP_DRAIN_PROFITS "exchange-drain-profits-0"

/**
 * Setup AML staff.
 */
#define OP_UPDATE_AML_STAFF "exchange-add-aml-staff-0"

/**
 * Setup partner exchange for wad transfers.
 */
#define OP_ADD_PARTNER "exchange-add-partner-0"

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
 * Age restriction configuration
 */
static bool ar_enabled = false;
static struct TALER_AgeRestrictionConfig ar_config = {0};

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
 * Currency we have configured.
 */
static char *currency;

/**
 * URL of the exchange we are interacting with
 * as per our configuration.
 */
static char *CFG_exchange_url;

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
 * Data structure for draining profits.
 */
struct DrainProfitsRequest
{

  /**
   * Kept in a DLL.
   */
  struct DrainProfitsRequest *next;

  /**
   * Kept in a DLL.
   */
  struct DrainProfitsRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementDrainProfitsHandle *h;

  /**
   * Array index of the associated command.
   */
  size_t idx;
};


/**
 * Data structure for announcing global fees.
 */
struct GlobalFeeRequest
{

  /**
   * Kept in a DLL.
   */
  struct GlobalFeeRequest *next;

  /**
   * Kept in a DLL.
   */
  struct GlobalFeeRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementSetGlobalFeeHandle *h;

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
 * Ongoing /management/extensions request.
 */
struct UploadExtensionsRequest
{
  /**
   * Kept in a DLL.
   */
  struct UploadExtensionsRequest *next;

  /**
   * Kept in a DLL.
   */
  struct UploadExtensionsRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementPostExtensionsHandle *h;

  /**
   * Operation index.
   */
  size_t idx;
};


/**
 * Data structure for AML staff requests.
 */
struct AmlStaffRequest
{

  /**
   * Kept in a DLL.
   */
  struct AmlStaffRequest *next;

  /**
   * Kept in a DLL.
   */
  struct AmlStaffRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementUpdateAmlOfficer *h;

  /**
   * Array index of the associated command.
   */
  size_t idx;
};


/**
 * Data structure for partner add requests.
 */
struct PartnerAddRequest
{

  /**
   * Kept in a DLL.
   */
  struct PartnerAddRequest *next;

  /**
   * Kept in a DLL.
   */
  struct PartnerAddRequest *prev;

  /**
   * Operation handle.
   */
  struct TALER_EXCHANGE_ManagementAddPartner *h;

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
 * Handle for #do_download.
 */
static struct TALER_EXCHANGE_ManagementGetKeysHandle *mgkh;


/**
 * Active AML staff change requests.
 */
static struct AmlStaffRequest *asr_head;

/**
 * Active AML staff change requests.
 */
static struct AmlStaffRequest *asr_tail;

/**
 * Active partner add requests.
 */
static struct PartnerAddRequest *par_head;

/**
 * Active partner add requests.
 */
static struct PartnerAddRequest *par_tail;

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
 * Active global fee requests.
 */
static struct GlobalFeeRequest *gfr_head;

/**
 * Active global fee requests.
 */
static struct GlobalFeeRequest *gfr_tail;

/**
 * Active keys upload requests.
 */
static struct UploadKeysRequest *ukr_head;

/**
 * Active keys upload requests.
 */
static struct UploadKeysRequest *ukr_tail;

/**
 * Active extensions upload requests.
 */
static struct UploadExtensionsRequest *uer_head;

/**
 * Active extensions upload requests.
 */
static struct UploadExtensionsRequest *uer_tail;

/**
 * Active drain profits requests.
 */
struct DrainProfitsRequest *dpr_head;

/**
 * Active drain profits requests.
 */
static struct DrainProfitsRequest *dpr_tail;


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
    struct AmlStaffRequest *asr;

    while (NULL != (asr = asr_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete AML staff update #%u\n",
                  (unsigned int) asr->idx);
      TALER_EXCHANGE_management_update_aml_officer_cancel (asr->h);
      GNUNET_CONTAINER_DLL_remove (asr_head,
                                   asr_tail,
                                   asr);
      GNUNET_free (asr);
    }
  }
  {
    struct PartnerAddRequest *par;

    while (NULL != (par = par_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete partner add request #%u\n",
                  (unsigned int) par->idx);
      TALER_EXCHANGE_management_add_partner_cancel (par->h);
      GNUNET_CONTAINER_DLL_remove (par_head,
                                   par_tail,
                                   par);
      GNUNET_free (par);
    }
  }
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
    struct GlobalFeeRequest *gfr;

    while (NULL != (gfr = gfr_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete global fee #%u\n",
                  (unsigned int) gfr->idx);
      TALER_EXCHANGE_management_set_global_fees_cancel (gfr->h);
      GNUNET_CONTAINER_DLL_remove (gfr_head,
                                   gfr_tail,
                                   gfr);
      GNUNET_free (gfr);
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
  {
    struct UploadExtensionsRequest *uer;

    while (NULL != (uer = uer_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete extensions signature upload #%u\n",
                  (unsigned int) uer->idx);
      TALER_EXCHANGE_management_post_extensions_cancel (uer->h);
      GNUNET_CONTAINER_DLL_remove (uer_head,
                                   uer_tail,
                                   uer);
      GNUNET_free (uer);
    }
  }

  {
    struct DrainProfitsRequest *dpr;

    while (NULL != (dpr = dpr_head))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Aborting incomplete drain profits request #%u\n",
                  (unsigned int) dpr->idx);
      TALER_EXCHANGE_management_drain_profits_cancel (dpr->h);
      GNUNET_CONTAINER_DLL_remove (dpr_head,
                                   dpr_tail,
                                   dpr);
      GNUNET_free (dpr);
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
       (NULL == par_head) &&
       (NULL == asr_head) &&
       (NULL == srr_head) &&
       (NULL == aar_head) &&
       (NULL == adr_head) &&
       (NULL == war_head) &&
       (NULL == wdr_head) &&
       (NULL == wfr_head) &&
       (NULL == gfr_head) &&
       (NULL == ukr_head) &&
       (NULL == uer_head) &&
       (NULL == dpr_head) &&
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
  {
    out = json_array ();
    GNUNET_assert (NULL != out);
  }
  action = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("operation",
                             op_name),
    GNUNET_JSON_pack_object_steal ("arguments",
                                   op_value));
  GNUNET_assert (0 ==
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
static enum GNUNET_GenericReturnValue
load_offline_key (int do_create)
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
                                           do_create,
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
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Using master public key %s\n",
              TALER_B2S (&master_pub));
  done = true;
  return GNUNET_OK;
}


/**
 * Function called with information about the post revocation operation result.
 *
 * @param cls closure with a `struct DenomRevocationRequest`
 * @param dr response data
 */
static void
denom_revocation_cb (
  void *cls,
  const struct TALER_EXCHANGE_ManagementRevokeDenominationResponse *dr)
{
  struct DenomRevocationRequest *drr = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &dr->hr;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) drr->idx,
                hr->http_status,
                hr->hint,
                TALER_JSON_get_error_hint (hr->reply));
    global_ret = EXIT_FAILURE;
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
 * @param value arguments for denomination revocation
 */
static void
upload_denom_revocation (const char *exchange_url,
                         size_t idx,
                         const json_t *value)
{
  struct TALER_MasterSignatureP master_sig;
  struct TALER_DenominationHashP h_denom_pub;
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
    global_ret = EXIT_FAILURE;
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
 * @param sr response data
 */
static void
signkey_revocation_cb (
  void *cls,
  const struct TALER_EXCHANGE_ManagementRevokeSigningKeyResponse *sr)
{
  struct SignkeyRevocationRequest *srr = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &sr->hr;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) srr->idx,
                hr->http_status,
                hr->hint,
                TALER_JSON_get_error_hint (hr->reply));
    global_ret = EXIT_FAILURE;
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
 * @param value arguments for denomination revocation
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
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_FAILURE;
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
 * @param value arguments for denomination revocation
 */
static void
upload_auditor_add (const char *exchange_url,
                    size_t idx,
                    const json_t *value)
{
  struct TALER_MasterSignatureP master_sig;
  const char *auditor_url;
  const char *auditor_name;
  struct GNUNET_TIME_Timestamp start_time;
  struct TALER_AuditorPublicKeyP auditor_pub;
  struct AuditorAddRequest *aar;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("auditor_url",
                             &auditor_url),
    GNUNET_JSON_spec_string ("auditor_name",
                             &auditor_name),
    GNUNET_JSON_spec_timestamp ("validity_start",
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
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_FAILURE;
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
 * @param value arguments for denomination revocation
 */
static void
upload_auditor_del (const char *exchange_url,
                    size_t idx,
                    const json_t *value)
{
  struct TALER_AuditorPublicKeyP auditor_pub;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Timestamp end_time;
  struct AuditorDelRequest *adr;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("auditor_pub",
                                 &auditor_pub),
    GNUNET_JSON_spec_timestamp ("validity_end",
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
    global_ret = EXIT_FAILURE;
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
 * @param wer response data
 */
static void
wire_add_cb (void *cls,
             const struct TALER_EXCHANGE_ManagementWireEnableResponse *wer)
{
  struct WireAddRequest *war = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &wer->hr;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) war->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = EXIT_FAILURE;
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
 * @param value arguments for denomination revocation
 */
static void
upload_wire_add (const char *exchange_url,
                 size_t idx,
                 const json_t *value)
{
  struct TALER_MasterSignatureP master_sig_add;
  struct TALER_MasterSignatureP master_sig_wire;
  const char *payto_uri;
  struct GNUNET_TIME_Timestamp start_time;
  struct WireAddRequest *war;
  const char *err_name;
  const char *conversion_url = NULL;
  json_t *debit_restrictions;
  json_t *credit_restrictions;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri",
                             &payto_uri),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_string ("conversion_url",
                               &conversion_url),
      NULL),
    GNUNET_JSON_spec_json ("debit_restrictions",
                           &debit_restrictions),
    GNUNET_JSON_spec_json ("credit_restrictions",
                           &credit_restrictions),
    GNUNET_JSON_spec_timestamp ("validity_start",
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
    global_ret = EXIT_FAILURE;
    GNUNET_JSON_parse_free (spec);
    test_shutdown ();
    return;
  }
  {
    char *wire_method;

    wire_method = TALER_payto_get_method (payto_uri);
    if (NULL == wire_method)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "payto:// URI `%s' is malformed\n",
                  payto_uri);
      global_ret = EXIT_FAILURE;
      GNUNET_JSON_parse_free (spec);
      test_shutdown ();
      return;
    }
    GNUNET_free (wire_method);
  }
  {
    char *msg = TALER_payto_validate (payto_uri);

    if (NULL != msg)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "payto URI is malformed: %s\n",
                  msg);
      GNUNET_free (msg);
      GNUNET_JSON_parse_free (spec);
      test_shutdown ();
      global_ret = EXIT_INVALIDARGUMENT;
      return;
    }
  }
  war = GNUNET_new (struct WireAddRequest);
  war->idx = idx;
  war->h =
    TALER_EXCHANGE_management_enable_wire (ctx,
                                           exchange_url,
                                           payto_uri,
                                           conversion_url,
                                           debit_restrictions,
                                           credit_restrictions,
                                           start_time,
                                           &master_sig_add,
                                           &master_sig_wire,
                                           &wire_add_cb,
                                           war);
  GNUNET_CONTAINER_DLL_insert (war_head,
                               war_tail,
                               war);
  GNUNET_JSON_parse_free (spec);
}


/**
 * Function called with information about the post wire del operation result.
 *
 * @param cls closure with a `struct WireDelRequest`
 * @param wdres response data
 */
static void
wire_del_cb (void *cls,
             const struct TALER_EXCHANGE_ManagementWireDisableResponse *wdres)
{
  struct WireDelRequest *wdr = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &wdres->hr;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) wdr->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = EXIT_FAILURE;
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
 * @param value arguments for denomination revocation
 */
static void
upload_wire_del (const char *exchange_url,
                 size_t idx,
                 const json_t *value)
{
  struct TALER_MasterSignatureP master_sig;
  const char *payto_uri;
  struct GNUNET_TIME_Timestamp end_time;
  struct WireDelRequest *wdr;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri",
                             &payto_uri),
    GNUNET_JSON_spec_timestamp ("validity_end",
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
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_FAILURE;
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
 * @param value arguments for denomination revocation
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
  struct TALER_WireFeeSet fees;
  struct GNUNET_TIME_Timestamp start_time;
  struct GNUNET_TIME_Timestamp end_time;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("wire_method",
                             &wire_method),
    TALER_JSON_spec_amount ("wire_fee",
                            currency,
                            &fees.wire),
    TALER_JSON_spec_amount ("closing_fee",
                            currency,
                            &fees.closing),
    GNUNET_JSON_spec_timestamp ("start_time",
                                &start_time),
    GNUNET_JSON_spec_timestamp ("end_time",
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
    global_ret = EXIT_FAILURE;
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
                                             &fees,
                                             &master_sig,
                                             &wire_fee_cb,
                                             wfr);
  GNUNET_CONTAINER_DLL_insert (wfr_head,
                               wfr_tail,
                               wfr);
}


/**
 * Function called with information about the post global fee operation result.
 *
 * @param cls closure with a `struct WireFeeRequest`
 * @param hr HTTP response data
 */
static void
global_fee_cb (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct GlobalFeeRequest *gfr = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) gfr->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = EXIT_FAILURE;
  }
  GNUNET_CONTAINER_DLL_remove (gfr_head,
                               gfr_tail,
                               gfr);
  GNUNET_free (gfr);
  test_shutdown ();
}


/**
 * Upload global fee.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value arguments for denomination revocation
 */
static void
upload_global_fee (const char *exchange_url,
                   size_t idx,
                   const json_t *value)
{
  struct TALER_MasterSignatureP master_sig;
  struct GlobalFeeRequest *gfr;
  const char *err_name;
  unsigned int err_line;
  struct TALER_GlobalFeeSet fees;
  struct GNUNET_TIME_Timestamp start_time;
  struct GNUNET_TIME_Timestamp end_time;
  struct GNUNET_TIME_Relative purse_timeout;
  struct GNUNET_TIME_Relative history_expiration;
  uint32_t purse_account_limit;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("history_fee",
                            currency,
                            &fees.history),
    TALER_JSON_spec_amount ("account_fee",
                            currency,
                            &fees.account),
    TALER_JSON_spec_amount ("purse_fee",
                            currency,
                            &fees.purse),
    GNUNET_JSON_spec_relative_time ("purse_timeout",
                                    &purse_timeout),
    GNUNET_JSON_spec_relative_time ("history_expiration",
                                    &history_expiration),
    GNUNET_JSON_spec_uint32 ("purse_account_limit",
                             &purse_account_limit),
    GNUNET_JSON_spec_timestamp ("start_time",
                                &start_time),
    GNUNET_JSON_spec_timestamp ("end_time",
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
    global_ret = EXIT_FAILURE;
    test_shutdown ();
    return;
  }
  gfr = GNUNET_new (struct GlobalFeeRequest);
  gfr->idx = idx;
  gfr->h =
    TALER_EXCHANGE_management_set_global_fees (ctx,
                                               exchange_url,
                                               start_time,
                                               end_time,
                                               &fees,
                                               purse_timeout,
                                               history_expiration,
                                               purse_account_limit,
                                               &master_sig,
                                               &global_fee_cb,
                                               gfr);
  GNUNET_CONTAINER_DLL_insert (gfr_head,
                               gfr_tail,
                               gfr);
}


/**
 * Function called with information about the drain profits operation.
 *
 * @param cls closure with a `struct DrainProfitsRequest`
 * @param mdr response data
 */
static void
drain_profits_cb (
  void *cls,
  const struct TALER_EXCHANGE_ManagementDrainResponse *mdr)
{
  struct DrainProfitsRequest *dpr = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &mdr->hr;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) dpr->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = EXIT_FAILURE;
  }
  GNUNET_CONTAINER_DLL_remove (dpr_head,
                               dpr_tail,
                               dpr);
  GNUNET_free (dpr);
  test_shutdown ();
}


/**
 * Upload drain profit action.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value arguments for drain profits
 */
static void
upload_drain (const char *exchange_url,
              size_t idx,
              const json_t *value)
{
  struct TALER_WireTransferIdentifierRawP wtid;
  struct TALER_MasterSignatureP master_sig;
  const char *err_name;
  unsigned int err_line;
  struct TALER_Amount amount;
  struct GNUNET_TIME_Timestamp date;
  const char *payto_uri;
  const char *account_section;
  struct DrainProfitsRequest *dpr;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("wtid",
                                 &wtid),
    TALER_JSON_spec_amount ("amount",
                            currency,
                            &amount),
    GNUNET_JSON_spec_timestamp ("date",
                                &date),
    GNUNET_JSON_spec_string ("account_section",
                             &account_section),
    GNUNET_JSON_spec_string ("payto_uri",
                             &payto_uri),
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
                "Invalid input to drain profits: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = EXIT_FAILURE;
    test_shutdown ();
    return;
  }
  dpr = GNUNET_new (struct DrainProfitsRequest);
  dpr->idx = idx;
  dpr->h =
    TALER_EXCHANGE_management_drain_profits (ctx,
                                             exchange_url,
                                             &wtid,
                                             &amount,
                                             date,
                                             account_section,
                                             payto_uri,
                                             &master_sig,
                                             &drain_profits_cb,
                                             dpr);
  GNUNET_CONTAINER_DLL_insert (dpr_head,
                               dpr_tail,
                               dpr);
}


/**
 * Function called with information about the post upload keys operation result.
 *
 * @param cls closure with a `struct UploadKeysRequest`
 * @param mr response data
 */
static void
keys_cb (
  void *cls,
  const struct TALER_EXCHANGE_ManagementPostKeysResponse *mr)
{
  struct UploadKeysRequest *ukr = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &mr->hr;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) ukr->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_FAILURE;
    test_shutdown ();
  }
  GNUNET_free (pkd.sign_sigs);
  GNUNET_free (pkd.denom_sigs);
  GNUNET_JSON_parse_free (spec);
}


/**
 * Function called with information about the post upload extensions operation result.
 *
 * @param cls closure with a `struct UploadExtensionsRequest`
 * @param er response data
 */
static void
extensions_cb (
  void *cls,
  const struct TALER_EXCHANGE_ManagementPostExtensionsResponse *er)
{
  struct UploadExtensionsRequest *uer = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &er->hr;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) uer->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = EXIT_FAILURE;
  }
  GNUNET_CONTAINER_DLL_remove (uer_head,
                               uer_tail,
                               uer);
  GNUNET_free (uer);
  test_shutdown ();
}


/**
 * Upload extension configuration
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value arguments for POSTing configurations of extensions
 */
static void
upload_extensions (const char *exchange_url,
                   size_t idx,
                   const json_t *value)
{
  json_t *extensions;
  struct TALER_MasterSignatureP sig;
  const char *err_name;
  unsigned int err_line;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("extensions",
                           &extensions),
    GNUNET_JSON_spec_fixed_auto ("extensions_sig",
                                 &sig),
    GNUNET_JSON_spec_end ()
  };

  /* 1. Parse the signed extensions */
  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to set extensions: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = EXIT_FAILURE;
    test_shutdown ();
    return;
  }

  /* 2. Verify the signature */
  {
    struct TALER_ExtensionManifestsHashP h_manifests;

    if (GNUNET_OK !=
        TALER_JSON_extensions_manifests_hash (extensions, &h_manifests))
    {
      GNUNET_JSON_parse_free (spec);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "couldn't hash extensions' manifests\n");
      global_ret = EXIT_FAILURE;
      test_shutdown ();
      return;
    }

    if (GNUNET_OK !=
        load_offline_key (GNUNET_NO))
      return;

    if (GNUNET_OK != TALER_exchange_offline_extension_manifests_hash_verify (
          &h_manifests,
          &master_pub,
          &sig))
    {
      GNUNET_JSON_parse_free (spec);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "invalid signature for extensions\n");
      global_ret = EXIT_FAILURE;
      test_shutdown ();
      return;
    }
  }

  /* 3. Upload the extensions */
  {
    struct TALER_EXCHANGE_ManagementPostExtensionsData ped = {
      .extensions = extensions,
      .extensions_sig = sig,
    };
    struct UploadExtensionsRequest *uer = GNUNET_new (struct
                                                      UploadExtensionsRequest);
    uer->idx = idx;
    uer->h = TALER_EXCHANGE_management_post_extensions (
      ctx,
      exchange_url,
      &ped,
      &extensions_cb,
      uer);
    GNUNET_CONTAINER_DLL_insert (uer_head,
                                 uer_tail,
                                 uer);
  }
  GNUNET_JSON_parse_free (spec);
}


/**
 * Function called with information about the add partner operation.
 *
 * @param cls closure with a `struct PartnerAddRequest`
 * @param hr HTTP response data
 */
static void
add_partner_cb (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct PartnerAddRequest *par = cls;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) par->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = EXIT_FAILURE;
  }
  GNUNET_CONTAINER_DLL_remove (par_head,
                               par_tail,
                               par);
  GNUNET_free (par);
  test_shutdown ();
}


/**
 * Add partner action.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value arguments for add partner
 */
static void
add_partner (const char *exchange_url,
             size_t idx,
             const json_t *value)
{
  struct TALER_MasterPublicKeyP partner_pub;
  struct GNUNET_TIME_Timestamp start_date;
  struct GNUNET_TIME_Timestamp end_date;
  struct GNUNET_TIME_Relative wad_frequency;
  struct TALER_Amount wad_fee;
  const char *partner_base_url;
  struct TALER_MasterSignatureP master_sig;
  struct PartnerAddRequest *par;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("partner_pub",
                                 &partner_pub),
    TALER_JSON_spec_amount ("wad_fee",
                            currency,
                            &wad_fee),
    GNUNET_JSON_spec_relative_time ("wad_frequency",
                                    &wad_frequency),
    GNUNET_JSON_spec_timestamp ("start_date",
                                &start_date),
    GNUNET_JSON_spec_timestamp ("end_date",
                                &end_date),
    GNUNET_JSON_spec_string ("partner_base_url",
                             &partner_base_url),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    GNUNET_JSON_spec_end ()
  };
  const char *err_name;
  unsigned int err_line;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to add partner: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = EXIT_FAILURE;
    test_shutdown ();
    return;
  }
  par = GNUNET_new (struct PartnerAddRequest);
  par->idx = idx;
  par->h =
    TALER_EXCHANGE_management_add_partner (ctx,
                                           exchange_url,
                                           &partner_pub,
                                           start_date,
                                           end_date,
                                           wad_frequency,
                                           &wad_fee,
                                           partner_base_url,
                                           &master_sig,
                                           &add_partner_cb,
                                           par);
  GNUNET_CONTAINER_DLL_insert (par_head,
                               par_tail,
                               par);
}


/**
 * Function called with information about the AML officer update operation.
 *
 * @param cls closure with a `struct AmlStaffRequest`
 * @param ar response data
 */
static void
update_aml_officer_cb (
  void *cls,
  const struct TALER_EXCHANGE_ManagementUpdateAmlOfficerResponse *ar)
{
  struct AmlStaffRequest *asr = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &ar->hr;

  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Upload failed for command %u with status %u: %s (%s)\n",
                (unsigned int) asr->idx,
                hr->http_status,
                TALER_ErrorCode_get_hint (hr->ec),
                hr->hint);
    global_ret = EXIT_FAILURE;
  }
  GNUNET_CONTAINER_DLL_remove (asr_head,
                               asr_tail,
                               asr);
  GNUNET_free (asr);
  test_shutdown ();
}


/**
 * Upload AML staff action.
 *
 * @param exchange_url base URL of the exchange
 * @param idx index of the operation we are performing (for logging)
 * @param value arguments for AML staff change
 */
static void
update_aml_staff (const char *exchange_url,
                  size_t idx,
                  const json_t *value)
{
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  const char *officer_name;
  struct GNUNET_TIME_Timestamp change_date;
  bool is_active;
  bool read_only;
  struct TALER_MasterSignatureP master_sig;
  struct AmlStaffRequest *asr;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("officer_pub",
                                 &officer_pub),
    GNUNET_JSON_spec_timestamp ("change_date",
                                &change_date),
    GNUNET_JSON_spec_bool ("is_active",
                           &is_active),
    GNUNET_JSON_spec_bool ("read_only",
                           &read_only),
    GNUNET_JSON_spec_string ("officer_name",
                             &officer_name),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    GNUNET_JSON_spec_end ()
  };
  const char *err_name;
  unsigned int err_line;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (value,
                         spec,
                         &err_name,
                         &err_line))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to AML staff update: %s#%u at %u (skipping)\n",
                err_name,
                err_line,
                (unsigned int) idx);
    json_dumpf (value,
                stderr,
                JSON_INDENT (2));
    global_ret = EXIT_FAILURE;
    test_shutdown ();
    return;
  }
  asr = GNUNET_new (struct AmlStaffRequest);
  asr->idx = idx;
  asr->h =
    TALER_EXCHANGE_management_update_aml_officer (ctx,
                                                  exchange_url,
                                                  &officer_pub,
                                                  officer_name,
                                                  change_date,
                                                  is_active,
                                                  read_only,
                                                  &master_sig,
                                                  &update_aml_officer_cb,
                                                  asr);
  GNUNET_CONTAINER_DLL_insert (asr_head,
                               asr_tail,
                               asr);
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
      .key = OP_SET_GLOBAL_FEE,
      .cb = &upload_global_fee
    },
    {
      .key = OP_UPLOAD_SIGS,
      .cb = &upload_keys
    },
    {
      .key = OP_DRAIN_PROFITS,
      .cb = &upload_drain
    },
    {
      .key = OP_EXTENSIONS,
      .cb = &upload_extensions
    },
    {
      .key = OP_UPDATE_AML_STAFF,
      .cb = &update_aml_staff
    },
    {
      .key = OP_ADD_PARTNER,
      .cb = &add_partner
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
      global_ret = EXIT_FAILURE;
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
      global_ret = EXIT_FAILURE;
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
  (void) args;
  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, refusing upload\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
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
      global_ret = EXIT_FAILURE;
      return;
    }
  }
  if (! json_is_array (out))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Error: expected JSON array for `upload` command\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
  if ( (NULL == CFG_exchange_url) &&
       (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (kcfg,
                                               "exchange",
                                               "BASE_URL",
                                               &CFG_exchange_url)) )
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    global_ret = EXIT_NOTCONFIGURED;
    test_shutdown ();
    return;
  }
  trigger_upload (CFG_exchange_url);
  json_decref (out);
  out = NULL;
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
  struct TALER_DenominationHashP h_denom_pub;
  struct TALER_MasterSignatureP master_sig;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, refusing revocation\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  TALER_exchange_offline_denomination_revoke_sign (&h_denom_pub,
                                                   &master_priv,
                                                   &master_sig);
  output_operation (OP_REVOKE_DENOMINATION,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                                  &h_denom_pub),
                      GNUNET_JSON_pack_data_auto ("master_sig",
                                                  &master_sig)));
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
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  TALER_exchange_offline_signkey_revoke_sign (&exchange_pub,
                                              &master_priv,
                                              &master_sig);
  output_operation (OP_REVOKE_SIGNKEY,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_data_auto ("exchange_pub",
                                                  &exchange_pub),
                      GNUNET_JSON_pack_data_auto ("master_sig",
                                                  &master_sig)));
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
  struct GNUNET_TIME_Timestamp now;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not adding auditor\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_INVALIDARGUMENT;
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
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  now = GNUNET_TIME_timestamp_get ();
  TALER_exchange_offline_auditor_add_sign (&auditor_pub,
                                           args[1],
                                           now,
                                           &master_priv,
                                           &master_sig);
  output_operation (OP_ENABLE_AUDITOR,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_string ("auditor_url",
                                               args[1]),
                      GNUNET_JSON_pack_string ("auditor_name",
                                               args[2]),
                      GNUNET_JSON_pack_timestamp ("validity_start",
                                                  now),
                      GNUNET_JSON_pack_data_auto ("auditor_pub",
                                                  &auditor_pub),
                      GNUNET_JSON_pack_data_auto ("master_sig",
                                                  &master_sig)));
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
  struct GNUNET_TIME_Timestamp now;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not deleting auditor account\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  now = GNUNET_TIME_timestamp_get ();
  TALER_exchange_offline_auditor_del_sign (&auditor_pub,
                                           now,
                                           &master_priv,
                                           &master_sig);
  output_operation (OP_DISABLE_AUDITOR,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_data_auto ("auditor_pub",
                                                  &auditor_pub),
                      GNUNET_JSON_pack_timestamp ("validity_end",
                                                  now),
                      GNUNET_JSON_pack_data_auto ("master_sig",
                                                  &master_sig)));
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
  struct GNUNET_TIME_Timestamp now;
  const char *conversion_url = NULL;
  json_t *debit_restrictions;
  json_t *credit_restrictions;
  unsigned int num_args = 1;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not adding wire account\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
  if (NULL == args[0])
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify a payto://-URI with this subcommand\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  {
    char *msg = TALER_payto_validate (args[0]);

    if (NULL != msg)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "payto URI is malformed: %s\n",
                  msg);
      GNUNET_free (msg);
      test_shutdown ();
      global_ret = EXIT_INVALIDARGUMENT;
      return;
    }
  }
  now = GNUNET_TIME_timestamp_get ();
  {
    char *wire_method;

    wire_method = TALER_payto_get_method (args[0]);
    if (NULL == wire_method)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "payto:// URI `%s' is malformed\n",
                  args[0]);
      global_ret = EXIT_INVALIDARGUMENT;
      test_shutdown ();
      return;
    }
    GNUNET_free (wire_method);
  }
  // FIXME: init new args properly!
  debit_restrictions = json_array ();
  GNUNET_assert (NULL != debit_restrictions);
  credit_restrictions = json_array ();
  GNUNET_assert (NULL != credit_restrictions);

  TALER_exchange_offline_wire_add_sign (args[0],
                                        conversion_url,
                                        debit_restrictions,
                                        credit_restrictions,
                                        now,
                                        &master_priv,
                                        &master_sig_add);
  TALER_exchange_wire_signature_make (args[0],
                                      conversion_url,
                                      debit_restrictions,
                                      credit_restrictions,
                                      &master_priv,
                                      &master_sig_wire);
  output_operation (OP_ENABLE_WIRE,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_string ("payto_uri",
                                               args[0]),
                      GNUNET_JSON_pack_array_steal ("debit_restrictions",
                                                    debit_restrictions),
                      GNUNET_JSON_pack_array_steal ("credit_restrictions",
                                                    credit_restrictions),
                      GNUNET_JSON_pack_allow_null (
                        GNUNET_JSON_pack_string ("conversion_url",
                                                 conversion_url)),
                      GNUNET_JSON_pack_timestamp ("validity_start",
                                                  now),
                      GNUNET_JSON_pack_data_auto ("master_sig_add",
                                                  &master_sig_add),
                      GNUNET_JSON_pack_data_auto ("master_sig_wire",
                                                  &master_sig_wire)));
  next (args + num_args);
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
  struct GNUNET_TIME_Timestamp now;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not deleting wire account\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
  if (NULL == args[0])
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify a payto://-URI with this subcommand\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  now = GNUNET_TIME_timestamp_get ();
  TALER_exchange_offline_wire_del_sign (args[0],
                                        now,
                                        &master_priv,
                                        &master_sig);
  output_operation (OP_DISABLE_WIRE,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_string ("payto_uri",
                                               args[0]),
                      GNUNET_JSON_pack_timestamp ("validity_end",
                                                  now),
                      GNUNET_JSON_pack_data_auto ("master_sig",
                                                  &master_sig)));
  next (args + 1);
}


/**
 * Set wire fees for the given year.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the year, args[1] the wire method, args[2] the wire fee and args[3]
 *        the closing fee.
 */
static void
do_set_wire_fee (char *const *args)
{
  struct TALER_MasterSignatureP master_sig;
  char dummy;
  unsigned int year;
  struct TALER_WireFeeSet fees;
  struct GNUNET_TIME_Timestamp start_time;
  struct GNUNET_TIME_Timestamp end_time;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not setting wire fee\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
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
                                &fees.wire)) ||
       (GNUNET_OK !=
        TALER_string_to_amount (args[3],
                                &fees.closing)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must use YEAR, METHOD, WIRE-FEE, and CLOSING-FEE as arguments for this subcommand\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (0 == strcasecmp ("now",
                       args[0]))
    year = GNUNET_TIME_get_current_year ();
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  start_time = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_year_to_time (year));
  end_time = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_year_to_time (year + 1));

  TALER_exchange_offline_wire_fee_sign (args[1],
                                        start_time,
                                        end_time,
                                        &fees,
                                        &master_priv,
                                        &master_sig);
  output_operation (OP_SET_WIRE_FEE,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_string ("wire_method",
                                               args[1]),
                      GNUNET_JSON_pack_timestamp ("start_time",
                                                  start_time),
                      GNUNET_JSON_pack_timestamp ("end_time",
                                                  end_time),
                      TALER_JSON_pack_amount ("wire_fee",
                                              &fees.wire),
                      TALER_JSON_pack_amount ("closing_fee",
                                              &fees.closing),
                      GNUNET_JSON_pack_data_auto ("master_sig",
                                                  &master_sig)));
  next (args + 4);
}


/**
 * Set global fees for the given year.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the year, args[1] the history fee, args[2]
 *        the account fee and args[3] the purse fee. These are followed by args[4] purse timeout,
 *        args[5] history expiration. Last is args[6] the (free) purse account limit.
 */
static void
do_set_global_fee (char *const *args)
{
  struct TALER_MasterSignatureP master_sig;
  char dummy;
  unsigned int year;
  struct TALER_GlobalFeeSet fees;
  struct GNUNET_TIME_Relative purse_timeout;
  struct GNUNET_TIME_Relative history_expiration;
  unsigned int purse_account_limit;
  struct GNUNET_TIME_Timestamp start_time;
  struct GNUNET_TIME_Timestamp end_time;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not setting global fee\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
  if ( (NULL == args[0]) ||
       (NULL == args[1]) ||
       (NULL == args[2]) ||
       (NULL == args[3]) ||
       (NULL == args[4]) ||
       (NULL == args[5]) ||
       (NULL == args[6]) ||
       ( (1 != sscanf (args[0],
                       "%u%c",
                       &year,
                       &dummy)) &&
         (0 != strcasecmp ("now",
                           args[0])) ) ||
       (GNUNET_OK !=
        TALER_string_to_amount (args[1],
                                &fees.history)) ||
       (GNUNET_OK !=
        TALER_string_to_amount (args[2],
                                &fees.account)) ||
       (GNUNET_OK !=
        TALER_string_to_amount (args[3],
                                &fees.purse)) ||
       (GNUNET_OK !=
        GNUNET_STRINGS_fancy_time_to_relative (args[4],
                                               &purse_timeout)) ||
       (GNUNET_OK !=
        GNUNET_STRINGS_fancy_time_to_relative (args[5],
                                               &history_expiration)) ||
       (1 != sscanf (args[6],
                     "%u%c",
                     &purse_account_limit,
                     &dummy)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must use YEAR, HISTORY-FEE, ACCOUNT-FEE, PURSE-FEE, PURSE-TIMEOUT, HISTORY-EXPIRATION and PURSE-ACCOUNT-LIMIT as arguments for this subcommand\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (0 == strcasecmp ("now",
                       args[0]))
    year = GNUNET_TIME_get_current_year ();
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  start_time = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_year_to_time (year));
  end_time = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_year_to_time (year + 1));

  TALER_exchange_offline_global_fee_sign (start_time,
                                          end_time,
                                          &fees,
                                          purse_timeout,
                                          history_expiration,
                                          (uint32_t) purse_account_limit,
                                          &master_priv,
                                          &master_sig);
  output_operation (OP_SET_GLOBAL_FEE,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_timestamp ("start_time",
                                                  start_time),
                      GNUNET_JSON_pack_timestamp ("end_time",
                                                  end_time),
                      TALER_JSON_pack_amount ("history_fee",
                                              &fees.history),
                      TALER_JSON_pack_amount ("account_fee",
                                              &fees.account),
                      TALER_JSON_pack_amount ("purse_fee",
                                              &fees.purse),
                      GNUNET_JSON_pack_time_rel ("purse_timeout",
                                                 purse_timeout),
                      GNUNET_JSON_pack_time_rel ("history_expiration",
                                                 history_expiration),
                      GNUNET_JSON_pack_uint64 ("purse_account_limit",
                                               (uint32_t) purse_account_limit),
                      GNUNET_JSON_pack_data_auto ("master_sig",
                                                  &master_sig)));
  next (args + 7);
}


/**
 * Drain profits from exchange's escrow account to
 * regular exchange account.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the amount,
 *        args[1] must be the section of the escrow account to drain
 *        args[2] must be the payto://-URI of the target account
 */
static void
do_drain (char *const *args)
{
  struct TALER_WireTransferIdentifierRawP wtid;
  struct GNUNET_TIME_Timestamp date;
  struct TALER_Amount amount;
  const char *account_section;
  const char *payto_uri;
  struct TALER_MasterSignatureP master_sig;
  char *err;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, refusing drain\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
  if ( (NULL == args[0]) ||
       (NULL == args[1]) ||
       (NULL == args[2]) ||
       (GNUNET_OK !=
        TALER_string_to_amount (args[0],
                                &amount)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Drain requires an amount, section name and target payto://-URI as arguments\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if ( (NULL == args[0]) ||
       (NULL == args[1]) ||
       (NULL == args[2]) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Drain requires an amount, section name and target payto://-URI as arguments\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (GNUNET_OK !=
      TALER_string_to_amount (args[0],
                              &amount))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid amount `%s' specified for drain\n",
                args[0]);
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  account_section = args[1];
  payto_uri = args[2];
  err = TALER_payto_validate (payto_uri);
  if (NULL != err)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid payto://-URI `%s' specified for drain: %s\n",
                payto_uri,
                err);
    GNUNET_free (err);
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                              &wtid,
                              sizeof (wtid));
  date = GNUNET_TIME_timestamp_get ();
  TALER_exchange_offline_profit_drain_sign (&wtid,
                                            date,
                                            &amount,
                                            account_section,
                                            payto_uri,
                                            &master_priv,
                                            &master_sig);
  output_operation (OP_DRAIN_PROFITS,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_data_auto ("wtid",
                                                  &wtid),
                      GNUNET_JSON_pack_string ("account_section",
                                               account_section),
                      GNUNET_JSON_pack_string ("payto_uri",
                                               payto_uri),
                      TALER_JSON_pack_amount ("amount",
                                              &amount),
                      GNUNET_JSON_pack_timestamp ("date",
                                                  date),
                      GNUNET_JSON_pack_data_auto ("master_sig",
                                                  &master_sig)));
  next (args + 3);
}


/**
 * Add partner.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the partner's master public key, args[1] the partner's
 *        API base URL, args[2] the wad fee, args[3] the wad frequency, and
 *        args[4] the year (including possibly 'now')
 */
static void
do_add_partner (char *const *args)
{
  struct TALER_MasterPublicKeyP partner_pub;
  struct GNUNET_TIME_Timestamp start_date;
  struct GNUNET_TIME_Timestamp end_date;
  struct GNUNET_TIME_Relative wad_frequency;
  struct TALER_Amount wad_fee;
  const char *partner_base_url;
  struct TALER_MasterSignatureP master_sig;
  char dummy;
  unsigned int year;

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not adding partner\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
  if ( (NULL == args[0]) ||
       (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &partner_pub,
                                       sizeof (partner_pub))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify the partner master public key as first argument for this subcommand\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if ( (NULL == args[1]) ||
       (0 != strncmp ("http",
                      args[1],
                      strlen ("http"))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify the partner's base URL as the 2nd argument to this subcommand\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  partner_base_url = args[1];
  if ( (NULL == args[2]) ||
       (GNUNET_OK !=
        TALER_string_to_amount (args[2],
                                &wad_fee)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid amount `%s' specified for wad fee of partner\n",
                args[2]);
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if ( (NULL == args[3]) ||
       (GNUNET_OK !=
        GNUNET_STRINGS_fancy_time_to_relative (args[3],
                                               &wad_frequency)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid wad frequency `%s' specified for add partner\n",
                args[3]);
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if ( (NULL == args[4]) ||
       ( (1 != sscanf (args[4],
                       "%u%c",
                       &year,
                       &dummy)) &&
         (0 != strcasecmp ("now",
                           args[4])) ) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid year `%s' specified for add partner\n",
                args[4]);
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (0 == strcasecmp ("now",
                       args[4]))
    year = GNUNET_TIME_get_current_year ();
  start_date = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_year_to_time (year));
  end_date = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_year_to_time (year + 1));

  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  TALER_exchange_offline_partner_details_sign (&partner_pub,
                                               start_date,
                                               end_date,
                                               wad_frequency,
                                               &wad_fee,
                                               partner_base_url,
                                               &master_priv,
                                               &master_sig);
  output_operation (OP_ADD_PARTNER,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_string ("partner_base_url",
                                               partner_base_url),
                      GNUNET_JSON_pack_time_rel ("wad_frequency",
                                                 wad_frequency),
                      GNUNET_JSON_pack_timestamp ("start_date",
                                                  start_date),
                      GNUNET_JSON_pack_timestamp ("end_date",
                                                  end_date),
                      GNUNET_JSON_pack_data_auto ("partner_pub",
                                                  &partner_pub),
                      GNUNET_JSON_pack_data_auto ("master_sig",
                                                  &master_sig)));
  next (args + 5);
}


/**
 * Enable or disable AML staff.
 *
 * @param is_active true to enable, false to disable
 * @param args the array of command-line arguments to process next; args[0] must be the AML staff's public key, args[1] the AML staff's legal name, and if @a is_active then args[2] rw (read write) or ro (read only)
 */
static void
do_set_aml_staff (bool is_active,
                  char *const *args)
{
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  const char *officer_name;
  bool read_only;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Timestamp now
    = GNUNET_TIME_timestamp_get ();

  if (NULL != in)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Downloaded data was not consumed, not updating AML staff status\n");
    test_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
  if ( (NULL == args[0]) ||
       (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &officer_pub,
                                       sizeof (officer_pub))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify the AML officer's public key as first argument for this subcommand\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  if (NULL == args[1])
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must specify the officer's legal name as the 2nd argument to this subcommand\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }
  officer_name = args[1];
  if (is_active)
  {
    if ( (NULL == args[2]) ||
         ( (0 != strcmp (args[2],
                         "ro")) &&
           (0 != strcmp (args[2],
                         "rw")) ) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "You must specify 'ro' or 'rw' (and not `%s') for the access level\n",
                  args[2]);
      test_shutdown ();
      global_ret = EXIT_INVALIDARGUMENT;
      return;
    }
    read_only = (0 == strcmp (args[2],
                              "ro"));
  }
  else
  {
    read_only = true;
  }
  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
    return;
  TALER_exchange_offline_aml_officer_status_sign (&officer_pub,
                                                  officer_name,
                                                  now,
                                                  is_active,
                                                  read_only,
                                                  &master_priv,
                                                  &master_sig);
  output_operation (OP_UPDATE_AML_STAFF,
                    GNUNET_JSON_PACK (
                      GNUNET_JSON_pack_string ("officer_name",
                                               officer_name),
                      GNUNET_JSON_pack_timestamp ("change_date",
                                                  now),
                      GNUNET_JSON_pack_bool ("is_active",
                                             is_active),
                      GNUNET_JSON_pack_bool ("read_only",
                                             read_only),
                      GNUNET_JSON_pack_data_auto ("officer_pub",
                                                  &officer_pub),
                      GNUNET_JSON_pack_data_auto ("master_sig",
                                                  &master_sig)));
  next (args + (is_active ? 3 : 2));
}


/**
 * Disable AML staff.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the AML staff's public key, args[1] the AML staff's legal name, args[2] rw (read write) or ro (read only)
 */
static void
disable_aml_staff (char *const *args)
{
  do_set_aml_staff (false,
                    args);
}


/**
 * Enable AML staff.
 *
 * @param args the array of command-line arguments to process next;
 *        args[0] must be the AML staff's public key, args[1] the AML staff's legal name, args[2] rw (read write) or ro (read only)
 */
static void
enable_aml_staff (char *const *args)
{
  do_set_aml_staff (true,
                    args);
}


/**
 * Function called with information about future keys.  Dumps the JSON output
 * (on success), either into an internal buffer or to stdout (depending on
 * whether there are subsequent commands).
 *
 * @param cls closure with the `char **` remaining args
 * @param mgr response data
 */
static void
download_cb (void *cls,
             const struct TALER_EXCHANGE_ManagementGetKeysResponse *mgr)
{
  char *const *args = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &mgr->hr;

  mgkh = NULL;
  switch (hr->http_status)
  {
  case MHD_HTTP_OK:
    break;
  default:
    if (0 != hr->http_status)
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to download keys from `%s': %s (HTTP status: %u/%u)\n",
                  CFG_exchange_url,
                  hr->hint,
                  hr->http_status,
                  (unsigned int) hr->ec);
    else
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to download keys from `%s' (no HTTP response)\n",
                  CFG_exchange_url);
    test_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
  in = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("operation",
                             OP_INPUT_KEYS),
    GNUNET_JSON_pack_object_incref ("arguments",
                                    (json_t *) hr->reply));
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
  if ( (NULL == CFG_exchange_url) &&
       (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (kcfg,
                                               "exchange",
                                               "BASE_URL",
                                               &CFG_exchange_url)) )
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    test_shutdown ();
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  mgkh = TALER_EXCHANGE_get_management_keys (ctx,
                                             CFG_exchange_url,
                                             &download_cb,
                                             (void *) args);
}


/**
 * Check that the security module keys are the same as before.  If we had no
 * keys in store before, remember them (Trust On First Use).
 *
 * @param secmset security module keys
 * @return #GNUNET_OK if keys match with what we have in store
 *         #GNUNET_NO if we had nothing in store but now do
 *         #GNUNET_SYSERR if keys changed from what we remember or other error
 */
static enum GNUNET_GenericReturnValue
tofu_check (const struct TALER_SecurityModulePublicKeySetP *secmset)
{
  char *fn;
  struct TALER_SecurityModulePublicKeySetP oldset;
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
  if (GNUNET_OK ==
      GNUNET_DISK_file_test (fn))
  {
    ret = GNUNET_DISK_fn_read (fn,
                               &oldset,
                               sizeof (oldset));
    if (GNUNET_SYSERR != ret)
    {
      if (ret != sizeof (oldset))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "File `%s' corrupt\n",
                    fn);
        GNUNET_free (fn);
        return GNUNET_SYSERR;
      }
      /* TOFU check */
      if (0 != memcmp (&oldset,
                       secmset,
                       sizeof (*secmset)))
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
  }

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
        GNUNET_free (fn);
        return GNUNET_SYSERR;
      }
      GNUNET_free (key);
      if (0 !=
          GNUNET_memcmp (&k,
                         &secmset->eddsa))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "ESIGN security module key does not match SECM_ESIGN_PUBKEY in configuration\n");
        GNUNET_free (fn);
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
        GNUNET_free (fn);
        return GNUNET_SYSERR;
      }
      GNUNET_free (key);
      if (0 !=
          GNUNET_memcmp (&k,
                         &secmset->rsa))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "DENOM security module key does not match SECM_DENOM_PUBKEY in configuration\n");
        GNUNET_free (fn);
        return GNUNET_SYSERR;
      }
    }
    if (GNUNET_OK ==
        GNUNET_CONFIGURATION_get_value_string (kcfg,
                                               "exchange-offline",
                                               "SECM_DENOM_CS_PUBKEY",
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
                                   "SECM_DENOM_CS_PUBKEY",
                                   "key malformed");
        GNUNET_free (key);
        GNUNET_free (fn);
        return GNUNET_SYSERR;
      }
      GNUNET_free (key);
      if (0 !=
          GNUNET_memcmp (&k,
                         &secmset->cs))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "DENOM security module key does not match SECM_DENOM_CS_PUBKEY in configuration\n");
        GNUNET_free (fn);
        return GNUNET_SYSERR;
      }
    }
  }
  if (GNUNET_OK !=
      GNUNET_DISK_directory_create_for_file (fn))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed create directory to store key material in file `%s'\n",
                fn);
    GNUNET_free (fn);
    return GNUNET_SYSERR;
  }
  /* persist keys for future runs */
  if (GNUNET_OK !=
      GNUNET_DISK_fn_write (fn,
                            secmset,
                            sizeof (oldset),
                            GNUNET_DISK_PERM_USER_READ))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to store key material in file `%s'\n",
                fn);
    GNUNET_free (fn);
    return GNUNET_SYSERR;
  }
  GNUNET_free (fn);
  return GNUNET_NO;
}


/**
 * Output @a signkeys for human consumption.
 *
 * @param secm_pub security module public key used to sign the denominations
 * @param signkeys keys to output
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
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
    struct GNUNET_TIME_Timestamp start_time;
    struct GNUNET_TIME_Timestamp sign_end;
    struct GNUNET_TIME_Timestamp legal_end;
    struct GNUNET_TIME_Relative duration;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_timestamp ("stamp_start",
                                  &start_time),
      GNUNET_JSON_spec_timestamp ("stamp_expire",
                                  &sign_end),
      GNUNET_JSON_spec_timestamp ("stamp_end",
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
      global_ret = EXIT_FAILURE;
      test_shutdown ();
      return GNUNET_SYSERR;
    }
    duration = GNUNET_TIME_absolute_get_difference (start_time.abs_time,
                                                    sign_end.abs_time);
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
      global_ret = EXIT_FAILURE;
      test_shutdown ();
      return GNUNET_SYSERR;
    }
    {
      char *legal_end_s;

      legal_end_s = GNUNET_strdup (
        GNUNET_TIME_timestamp2s (legal_end));
      printf ("EXCHANGE-KEY %s starting at %s (used for: %s, legal end: %s)\n",
              TALER_B2S (&exchange_pub),
              GNUNET_TIME_timestamp2s (start_time),
              GNUNET_TIME_relative2s (duration,
                                      false),
              legal_end_s);
      GNUNET_free (legal_end_s);
    }
  }
  return GNUNET_OK;
}


/**
 * Output @a denomkeys for human consumption.
 *
 * @param secm_pub_rsa security module public key used to sign the RSA denominations
 * @param secm_pub_cs security module public key used to sign the CS denominations
 * @param denomkeys keys to output
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
show_denomkeys (const struct TALER_SecurityModulePublicKeyP *secm_pub_rsa,
                const struct TALER_SecurityModulePublicKeyP *secm_pub_cs,
                const json_t *denomkeys)
{
  size_t index;
  json_t *value;

  json_array_foreach (denomkeys, index, value) {
    const char *err_name;
    unsigned int err_line;
    const char *section_name;
    struct TALER_DenominationPublicKey denom_pub;
    struct GNUNET_TIME_Timestamp stamp_start;
    struct GNUNET_TIME_Timestamp stamp_expire_withdraw;
    struct GNUNET_TIME_Timestamp stamp_expire_deposit;
    struct GNUNET_TIME_Timestamp stamp_expire_legal;
    struct TALER_Amount coin_value;
    struct TALER_DenomFeeSet fees;
    struct TALER_SecurityModuleSignatureP secm_sig;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("section_name",
                               &section_name),
      TALER_JSON_spec_denom_pub ("denom_pub",
                                 &denom_pub),
      TALER_JSON_spec_amount ("value",
                              currency,
                              &coin_value),
      TALER_JSON_SPEC_DENOM_FEES ("fee",
                                  currency,
                                  &fees),
      GNUNET_JSON_spec_timestamp ("stamp_start",
                                  &stamp_start),
      GNUNET_JSON_spec_timestamp ("stamp_expire_withdraw",
                                  &stamp_expire_withdraw),
      GNUNET_JSON_spec_timestamp ("stamp_expire_deposit",
                                  &stamp_expire_deposit),
      GNUNET_JSON_spec_timestamp ("stamp_expire_legal",
                                  &stamp_expire_legal),
      GNUNET_JSON_spec_fixed_auto ("denom_secmod_sig",
                                   &secm_sig),
      GNUNET_JSON_spec_end ()
    };
    struct GNUNET_TIME_Relative duration;
    struct TALER_DenominationHashP h_denom_pub;
    enum GNUNET_GenericReturnValue ok;

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
      global_ret = EXIT_FAILURE;
      test_shutdown ();
      return GNUNET_SYSERR;
    }
    duration = GNUNET_TIME_absolute_get_difference (
      stamp_start.abs_time,
      stamp_expire_withdraw.abs_time);
    TALER_denom_pub_hash (&denom_pub,
                          &h_denom_pub);
    switch (denom_pub.cipher)
    {
    case TALER_DENOMINATION_RSA:
      {
        struct TALER_RsaPubHashP h_rsa;

        TALER_rsa_pub_hash (denom_pub.details.rsa_public_key,
                            &h_rsa);
        ok = TALER_exchange_secmod_rsa_verify (&h_rsa,
                                               section_name,
                                               stamp_start,
                                               duration,
                                               secm_pub_rsa,
                                               &secm_sig);
      }
      break;
    case TALER_DENOMINATION_CS:
      {
        struct TALER_CsPubHashP h_cs;

        TALER_cs_pub_hash (&denom_pub.details.cs_public_key,
                           &h_cs);
        ok = TALER_exchange_secmod_cs_verify (&h_cs,
                                              section_name,
                                              stamp_start,
                                              duration,
                                              secm_pub_cs,
                                              &secm_sig);
      }
      break;
    default:
      GNUNET_break (0);
      ok = GNUNET_SYSERR;
      break;
    }
    if (GNUNET_OK != ok)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid security module signature for denomination key %s (aborting)\n",
                  GNUNET_h2s (&h_denom_pub.hash));
      global_ret = EXIT_FAILURE;
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

      withdraw_fee_s = TALER_amount_to_string (&fees.withdraw);
      deposit_fee_s = TALER_amount_to_string (&fees.deposit);
      refresh_fee_s = TALER_amount_to_string (&fees.refresh);
      refund_fee_s = TALER_amount_to_string (&fees.refund);
      deposit_s = GNUNET_strdup (
        GNUNET_TIME_timestamp2s (stamp_expire_deposit));
      legal_s = GNUNET_strdup (
        GNUNET_TIME_timestamp2s (stamp_expire_legal));

      printf (
        "DENOMINATION-KEY(%s) %s of value %s starting at %s "
        "(used for: %s, deposit until: %s legal end: %s) with fees %s/%s/%s/%s\n",
        section_name,
        TALER_B2S (&h_denom_pub),
        TALER_amount2s (&coin_value),
        GNUNET_TIME_timestamp2s (stamp_start),
        GNUNET_TIME_relative2s (duration,
                                false),
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
      global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_FAILURE;
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
  struct TALER_SecurityModulePublicKeySetP secmset;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("future_denoms",
                           &denomkeys),
    GNUNET_JSON_spec_json ("future_signkeys",
                           &signkeys),
    GNUNET_JSON_spec_fixed_auto ("master_pub",
                                 &mpub),
    GNUNET_JSON_spec_fixed_auto ("denom_secmod_public_key",
                                 &secmset.rsa),
    GNUNET_JSON_spec_fixed_auto ("denom_secmod_cs_public_key",
                                 &secmset.cs),
    GNUNET_JSON_spec_fixed_auto ("signkey_secmod_public_key",
                                 &secmset.eddsa),
    GNUNET_JSON_spec_end ()
  };

  keys = parse_keys_input ("show");
  if (NULL == keys)
    return;

  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
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
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_FAILURE;
    test_shutdown ();
    GNUNET_JSON_parse_free (spec);
    json_decref (keys);
    return;
  }
  if (GNUNET_SYSERR ==
      tofu_check (&secmset))
  {
    global_ret = EXIT_FAILURE;
    test_shutdown ();
    GNUNET_JSON_parse_free (spec);
    json_decref (keys);
    return;
  }
  if ( (GNUNET_OK !=
        show_signkeys (&secmset.eddsa,
                       signkeys)) ||
       (GNUNET_OK !=
        show_denomkeys (&secmset.rsa,
                        &secmset.cs,
                        denomkeys)) )
  {
    global_ret = EXIT_FAILURE;
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
static enum GNUNET_GenericReturnValue
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
    struct GNUNET_TIME_Timestamp start_time;
    struct GNUNET_TIME_Timestamp sign_end;
    struct GNUNET_TIME_Timestamp legal_end;
    struct GNUNET_TIME_Relative duration;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_timestamp ("stamp_start",
                                  &start_time),
      GNUNET_JSON_spec_timestamp ("stamp_expire",
                                  &sign_end),
      GNUNET_JSON_spec_timestamp ("stamp_end",
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
      global_ret = EXIT_FAILURE;
      test_shutdown ();
      return GNUNET_SYSERR;
    }

    duration = GNUNET_TIME_absolute_get_difference (start_time.abs_time,
                                                    sign_end.abs_time);
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
      global_ret = EXIT_FAILURE;
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
                       GNUNET_JSON_PACK (
                         GNUNET_JSON_pack_data_auto ("exchange_pub",
                                                     &exchange_pub),
                         GNUNET_JSON_pack_data_auto ("master_sig",
                                                     &master_sig))));
    }
    GNUNET_JSON_parse_free (spec);
  }
  return GNUNET_OK;
}


/**
 * Looks up the AGE_RESTRICTED setting for a denomination in the config and
 * returns the age restriction (mask) accordingly.
 *
 * @param section_name Section in the configuration for the particular
 *    denomination.
 */
static struct TALER_AgeMask
load_age_mask (const char*section_name)
{
  static const struct TALER_AgeMask null_mask = {0};
  enum GNUNET_GenericReturnValue ret;

  if (! ar_enabled)
    return null_mask;

  if (GNUNET_OK != (GNUNET_CONFIGURATION_have_value (
                      kcfg,
                      section_name,
                      "AGE_RESTRICTED")))
    return null_mask;

  ret = GNUNET_CONFIGURATION_get_value_yesno (kcfg,
                                              section_name,
                                              "AGE_RESTRICTED");
  if (GNUNET_SYSERR == ret)
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section_name,
                               "AGE_RESTRICTED",
                               "Value must be YES or NO\n");
  if (GNUNET_YES == ret)
    return ar_config.mask;

  return null_mask;
}


/**
 * Sign @a denomkeys with offline key.
 *
 * @param secm_pub_rsa security module public key used to sign the RSA denominations
 * @param secm_pub_cs security module public key used to sign the CS denominations
 * @param denomkeys keys to output
 * @param[in,out] result array where to output the signatures
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
sign_denomkeys (const struct TALER_SecurityModulePublicKeyP *secm_pub_rsa,
                const struct TALER_SecurityModulePublicKeyP *secm_pub_cs,
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
    struct GNUNET_TIME_Timestamp stamp_start;
    struct GNUNET_TIME_Timestamp stamp_expire_withdraw;
    struct GNUNET_TIME_Timestamp stamp_expire_deposit;
    struct GNUNET_TIME_Timestamp stamp_expire_legal;
    struct TALER_Amount coin_value;
    struct TALER_DenomFeeSet fees;
    struct TALER_SecurityModuleSignatureP secm_sig;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("section_name",
                               &section_name),
      TALER_JSON_spec_denom_pub ("denom_pub",
                                 &denom_pub),
      TALER_JSON_spec_amount ("value",
                              currency,
                              &coin_value),
      TALER_JSON_SPEC_DENOM_FEES ("fee",
                                  currency,
                                  &fees),
      GNUNET_JSON_spec_timestamp ("stamp_start",
                                  &stamp_start),
      GNUNET_JSON_spec_timestamp ("stamp_expire_withdraw",
                                  &stamp_expire_withdraw),
      GNUNET_JSON_spec_timestamp ("stamp_expire_deposit",
                                  &stamp_expire_deposit),
      GNUNET_JSON_spec_timestamp ("stamp_expire_legal",
                                  &stamp_expire_legal),
      GNUNET_JSON_spec_fixed_auto ("denom_secmod_sig",
                                   &secm_sig),
      GNUNET_JSON_spec_end ()
    };
    struct GNUNET_TIME_Relative duration;
    struct TALER_DenominationHashP h_denom_pub;

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
      global_ret = EXIT_FAILURE;
      test_shutdown ();
      return GNUNET_SYSERR;
    }
    duration = GNUNET_TIME_absolute_get_difference (
      stamp_start.abs_time,
      stamp_expire_withdraw.abs_time);

    /* Load the age mask, if applicable to this denomination */
    denom_pub.age_mask = load_age_mask (section_name);

    TALER_denom_pub_hash (&denom_pub,
                          &h_denom_pub);
    switch (denom_pub.cipher)
    {
    case TALER_DENOMINATION_RSA:
      {
        struct TALER_RsaPubHashP h_rsa;

        TALER_rsa_pub_hash (denom_pub.details.rsa_public_key,
                            &h_rsa);
        if (GNUNET_OK !=
            TALER_exchange_secmod_rsa_verify (&h_rsa,
                                              section_name,
                                              stamp_start,
                                              duration,
                                              secm_pub_rsa,
                                              &secm_sig))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Invalid security module signature for denomination key %s (aborting)\n",
                      GNUNET_h2s (&h_denom_pub.hash));
          global_ret = EXIT_FAILURE;
          test_shutdown ();
          GNUNET_JSON_parse_free (spec);
          return GNUNET_SYSERR;
        }
      }
      break;
    case TALER_DENOMINATION_CS:
      {
        struct TALER_CsPubHashP h_cs;

        TALER_cs_pub_hash (&denom_pub.details.cs_public_key,
                           &h_cs);
        if (GNUNET_OK !=
            TALER_exchange_secmod_cs_verify (&h_cs,
                                             section_name,
                                             stamp_start,
                                             duration,
                                             secm_pub_cs,
                                             &secm_sig))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Invalid security module signature for denomination key %s (aborting)\n",
                      GNUNET_h2s (&h_denom_pub.hash));
          global_ret = EXIT_FAILURE;
          test_shutdown ();
          GNUNET_JSON_parse_free (spec);
          return GNUNET_SYSERR;
        }
      }
      break;
    default:
      global_ret = EXIT_FAILURE;
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
                                                  &fees,
                                                  &master_priv,
                                                  &master_sig);
      GNUNET_assert (0 ==
                     json_array_append_new (
                       result,
                       GNUNET_JSON_PACK (
                         GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                                     &h_denom_pub),
                         GNUNET_JSON_pack_data_auto ("master_sig",
                                                     &master_sig))));
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
  struct TALER_SecurityModulePublicKeySetP secmset;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("future_denoms",
                           &denomkeys),
    GNUNET_JSON_spec_json ("future_signkeys",
                           &signkeys),
    GNUNET_JSON_spec_fixed_auto ("master_pub",
                                 &mpub),
    GNUNET_JSON_spec_fixed_auto ("denom_secmod_public_key",
                                 &secmset.rsa),
    GNUNET_JSON_spec_fixed_auto ("denom_secmod_cs_public_key",
                                 &secmset.cs),
    GNUNET_JSON_spec_fixed_auto ("signkey_secmod_public_key",
                                 &secmset.eddsa),
    GNUNET_JSON_spec_end ()
  };

  keys = parse_keys_input ("sign");
  if (NULL == keys)
    return;
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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid input to 'sign' : %s #%u (skipping)\n",
                err_name,
                err_line);
    json_dumpf (in,
                stderr,
                JSON_INDENT (2));
    global_ret = EXIT_FAILURE;
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
    global_ret = EXIT_FAILURE;
    test_shutdown ();
    GNUNET_JSON_parse_free (spec);
    json_decref (keys);
    return;
  }
  if (GNUNET_SYSERR ==
      tofu_check (&secmset))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Fatal: security module keys changed!\n");
    global_ret = EXIT_FAILURE;
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
          sign_signkeys (&secmset.eddsa,
                         signkeys,
                         signkey_sig_array)) ||
         (GNUNET_OK !=
          sign_denomkeys (&secmset.rsa,
                          &secmset.cs,
                          denomkeys,
                          denomkey_sig_array)) )
    {
      global_ret = EXIT_FAILURE;
      test_shutdown ();
      json_decref (signkey_sig_array);
      json_decref (denomkey_sig_array);
      GNUNET_JSON_parse_free (spec);
      json_decref (keys);
      return;
    }

    output_operation (OP_UPLOAD_SIGS,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_array_steal ("denom_sigs",
                                                      denomkey_sig_array),
                        GNUNET_JSON_pack_array_steal ("signkey_sigs",
                                                      signkey_sig_array)));
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
    global_ret = EXIT_NOPERMISSION;
    return;
  }
  if (NULL != *args)
  {
    output_operation (OP_SETUP,
                      GNUNET_JSON_PACK (
                        GNUNET_JSON_pack_data_auto ("exchange_offline_pub",
                                                    &master_pub)));
  }

  else
  {
    char *pub_s;

    pub_s = GNUNET_STRINGS_data_to_string_alloc (&master_pub,
                                                 sizeof (master_pub));
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


/**
 * Print the current extensions as configured
 *
 * @param args the array of command-line arguments to process next
 */
static void
do_extensions_show (char *const *args)
{
  const struct TALER_Extensions *it;
  json_t *exts = json_object ();
  json_t *obj;

  GNUNET_assert (NULL != exts);
  for (it = TALER_extensions_get_head ();
       NULL != it && NULL != it->extension;
       it = it->next)
  {
    const struct TALER_Extension *extension = it->extension;
    int ret;

    ret = json_object_set_new (exts,
                               extension->name,
                               extension->manifest (extension));
    GNUNET_assert (-1 != ret);
  }

  obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_object_steal ("extensions",
                                   exts));
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "%s\n",
              json_dumps (obj,
                          JSON_INDENT (2)));
  json_decref (obj);
  next (args);
}


/**
 * Sign the configurations of the enabled extensions
 */
static void
do_extensions_sign (char *const *args)
{
  json_t *extensions = json_object ();
  struct TALER_ExtensionManifestsHashP h_manifests;
  struct TALER_MasterSignatureP sig;
  const struct TALER_Extensions *it;
  bool found = false;
  json_t *obj;

  GNUNET_assert (NULL != extensions);
  for (it = TALER_extensions_get_head ();
       NULL != it && NULL != it->extension;
       it = it->next)
  {
    const struct TALER_Extension *ext = it->extension;
    GNUNET_assert (ext);

    found = true;

    GNUNET_assert (0 ==
                   json_object_set_new (extensions,
                                        ext->name,
                                        ext->manifest (ext)));
  }

  if (! found)
    return;

  if (GNUNET_OK !=
      TALER_JSON_extensions_manifests_hash (extensions,
                                            &h_manifests))
  {
    json_decref (extensions);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "error while hashing manifest for extensions\n");
    return;
  }

  if (GNUNET_OK !=
      load_offline_key (GNUNET_NO))
  {
    json_decref (extensions);
    return;
  }

  TALER_exchange_offline_extension_manifests_hash_sign (&h_manifests,
                                                        &master_priv,
                                                        &sig);
  obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_object_steal ("extensions",
                                   extensions),
    GNUNET_JSON_pack_data_auto (
      "extensions_sig",
      &sig));

  output_operation (OP_EXTENSIONS,
                    obj);
  next (args);
}


/**
 * Dispatch @a args in the @a cmds array.
 *
 * @param args arguments with subcommand to dispatch
 * @param cmds array of possible subcommands to call
 */
static void
cmd_handler (char *const *args,
             const struct SubCommand *cmds)
{
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
    global_ret = EXIT_INVALIDARGUMENT;
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
  json_decref (out);
  out = NULL;
  GNUNET_SCHEDULER_shutdown ();
}


static void
do_work_extensions (char *const *args)
{
  struct SubCommand cmds[] = {
    {
      .name = "show",
      .help =
        "show the extensions in the Taler-config and their configured parameters",
      .cb = &do_extensions_show
    },
    {
      .name = "sign",
      .help =
        "sign the configuration of the extensions and publish it with the exchange",
      .cb = &do_extensions_sign
    },
    {
      .name = NULL,
    }
  };

  if (NULL == args[0])
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "You must provide a subcommand: `show` or `sign`.\n");
    test_shutdown ();
    global_ret = EXIT_INVALIDARGUMENT;
    return;
  }

  cmd_handler (args, cmds);
}


static void
work (void *cls)
{
  char *const *args = cls;
  struct SubCommand cmds[] = {
    {
      .name = "setup",
      .help =
        "initialize offline key signing material and display public offline key",
      .cb = &do_setup
    },
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
        "sign wire fees for the given year (year, wire method, wire fee, and closing fee must be given as arguments)",
      .cb = &do_set_wire_fee
    },
    {
      .name = "global-fee",
      .help =
        "sign global fees for the given year (year, history fee, account fee, purse fee, purse timeout, history expiration and the maximum number of free purses per account must be given as arguments)",
      .cb = &do_set_global_fee
    },
    {
      .name = "drain",
      .help =
        "drain profits from exchange escrow account to regular exchange operator account (amount, debit account configuration section and credit account payto://-URI must be given as arguments)",
      .cb = &do_drain
    },
    {
      .name = "add-partner",
      .help =
        "add partner exchange for P2P wad transfers (partner master public key, partner base URL, wad fee, wad frequency and validity year must be given as arguments)",
      .cb = &do_add_partner
    },
    {
      .name = "aml-enable",
      .help =
        "enable AML staff member (staff member public key, legal name and rw (read write) or ro (read only) must be given as arguments)",
      .cb = &enable_aml_staff
    },
    {
      .name = "aml-disable",
      .help =
        "disable AML staff member (staff member public key and legal name must be given as arguments)",
      .cb = &disable_aml_staff
    },
    {
      .name = "upload",
      .help =
        "upload operation result to exchange (to be performed online!)",
      .cb = &do_upload
    },
    {
      .name = "extensions",
      .help = "subcommands for extension handling",
      .cb = &do_work_extensions
    },
    /* list terminator */
    {
      .name = NULL,
    }
  };
  (void) cls;

  cmd_handler (args, cmds);
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
  (void) cls;
  (void) cfgfile;
  kcfg = cfg;

  /* load extensions */
  GNUNET_assert (GNUNET_OK ==
                 TALER_extensions_init (kcfg));

  /* setup age restriction, if applicable */
  {
    const struct TALER_AgeRestrictionConfig *arc;

    if (NULL !=
        (arc = TALER_extensions_get_age_restriction_config ()))
    {
      ar_config  = *arc;
      ar_enabled = true;
    }
  }


  if (GNUNET_OK !=
      TALER_config_get_currency (kcfg,
                                 &currency))
  {
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }

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
  enum GNUNET_GenericReturnValue ret;

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return EXIT_INVALIDARGUMENT;
  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-exchange-offline",
    gettext_noop ("Operations for offline signing for a Taler exchange"),
    options,
    &run, NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-offline.c */
