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
#include "taler_exchange_service.h"


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
      fprintf (stderr,
               "Aborting incomplete denomination revocation #%u\n",
               (unsigned int) drr->idx);
      TALER_EXCHANGE_management_revoke_denomination_key_cancel (drr->h);
      GNUNET_CONTAINER_DLL_remove (drr_head,
                                   drr_tail,
                                   drr);
      GNUNET_free (drr);
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
             "Warning: input not consumed!\n");
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
    GNUNET_SCHEDULER_shutdown ();
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

  if (NULL == out)
    out = json_array ();
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
                                               "exchange",
                                               "MASTER_PRIV_FILE",
                                               &fn))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "MASTER_PRIV_FILE");
    GNUNET_SCHEDULER_shutdown ();
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
    GNUNET_SCHEDULER_shutdown ();
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
    fprintf (stderr,
             "Upload failed for command %u with status %u (%s)\n",
             (unsigned int) drr->idx,
             hr->http_status,
             hr->hint);
  }
  GNUNET_CONTAINER_DLL_remove (drr_head,
                               drr_tail,
                               drr);
  GNUNET_free (drr);
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
    fprintf (stderr,
             "Invalid input for denomination revocation: %s#%u at %u (skipping)\n",
             err_name,
             err_line,
             (unsigned int) idx);
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
 * Perform uploads based on the JSON in #io.
 *
 * @param exchange_url base URL of the exchange to use
 */
static void
trigger_upload (const char *exchange_url)
{
  struct UploadHandler uhs[] = {
    {
      .key = "revoke-denomination",
      .cb = &upload_denom_revocation
    },
    // FIXME: many more handlers here!
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
      GNUNET_SCHEDULER_shutdown ();
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
      GNUNET_SCHEDULER_shutdown ();
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
    fprintf (stderr,
             "Downloaded data was not consumed, refusing upload\n");
    GNUNET_SCHEDULER_shutdown ();
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
      GNUNET_SCHEDULER_shutdown ();
      global_ret = 2;
      return;
    }
  }
  if (! json_is_array (out))
  {
    fprintf (stderr,
             "Error: expected JSON array for `upload` command\n");
    GNUNET_SCHEDULER_shutdown ();
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
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  trigger_upload (exchange_url);
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
    fprintf (stderr,
             "Downloaded data was not consumed, refusing revocation\n");
    GNUNET_SCHEDULER_shutdown ();
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
    fprintf (stderr,
             "You must specify a denomination key with this subcommand\n");
    GNUNET_SCHEDULER_shutdown ();
    global_ret = 5;
    return;
  }
  if (GNUNET_OK !=
      load_offline_key ())
    return;
  TALER_exchange_offline_denomination_revoke_sign (&h_denom_pub,
                                                   &master_priv,
                                                   &master_sig);
  output_operation ("revoke-denomination",
                    json_pack ("{s:o, s:o}",
                               "h_denom_pub",
                               GNUNET_JSON_from_data_auto (&h_denom_pub),
                               "master_sig",
                               GNUNET_JSON_from_data_auto (&master_sig)));
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
    fprintf (stderr,
             "Failed to download keys: %s (HTTP status: %u/%u)\n",
             hr->hint,
             hr->http_status,
             (unsigned int) hr->ec);
    GNUNET_SCHEDULER_shutdown ();
    global_ret = 4;
    return;
  }
  if (NULL == args[0])
  {
    json_dumpf (hr->reply,
                stdout,
                JSON_INDENT (2));
  }
  else
  {
    in = json_incref ((json_t*) hr->reply);
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
    GNUNET_SCHEDULER_shutdown ();
    global_ret = 1;
    return;
  }
  mgkh = TALER_EXCHANGE_get_management_keys (ctx,
                                             exchange_url,
                                             &download_cb,
                                             (void *) args);
  GNUNET_free (exchange_url);
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
      .name = "revoke-denomination",
      .help =
        "revoke denomination key (hash of public key must be given as argument)",
      .cb = &do_revoke_denomination_key
    },
    {
      .name = "upload",
      .help =
        "upload operation result to exchange (to be performed online!)",
      .cb = &do_upload
    },
    // FIXME: many more handlers here!
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
           "Supported subcommands:");
  for (unsigned int i = 0; NULL != cmds[i].name; i++)
  {
    fprintf (stderr,
             "%s - %s\n",
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
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-exchange-offline",
                                   "WARNING",
                                   NULL));
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
