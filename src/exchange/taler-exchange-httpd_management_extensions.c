/*
   This file is part of TALER
   Copyright (C) 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_management_extensions.c
 * @brief Handle request to POST /management/extensions
 * @author Özgür Kesim
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd_management.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_extensions.h"


struct Extension
{
  enum TALER_Extension_Type type;
  json_t *config_json;

  // This union contains the parsed configuration for each extension.
  union
  {
    // configuration for the age restriction
    struct TALER_AgeMask mask;

    /* TODO oec - peer2peer config */
  };
};

/**
 * Closure for the #set_extensions transaction
 */
struct SetExtensionsContext
{
  uint32_t num_extensions;
  struct Extension *extensions;
  struct TALER_MasterSignatureP *extensions_sigs;
};

/**
 * Function implementing database transaction to set the configuration of
 * extensions.  It runs the transaction logic.
 *  - IF it returns a non-error code, the transaction logic MUST NOT queue a
 *    MHD response.
 *  - IF it returns an hard error, the transaction logic MUST queue a MHD
 *    response and set @a mhd_ret.
 *  - IF it returns the soft error code, the function MAY be called again to
 *    retry and MUST not queue a MHD response.
 *
 * @param cls closure with a `struct SetExtensionsContext`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
set_extensions (void *cls,
                struct MHD_Connection *connection,
                MHD_RESULT *mhd_ret)
{
  // struct SetExtensionContext *sec = cls;

  // TODO oec
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT; /* only 'success', so >=0, matters here */
}


MHD_RESULT
TEH_handler_management_post_extensions (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct SetExtensionsContext sec = {0};
  json_t *extensions;
  json_t *extensions_sigs;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("extensions",
                           &extensions),
    GNUNET_JSON_spec_json ("extensions_sigs",
                           &extensions_sigs),
    GNUNET_JSON_spec_end ()
  };
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

  if (! (json_is_array (extensions) &&
         json_is_array (extensions_sigs)) )
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "array expected for extensions and extensions_sig");
  }

  sec.num_extensions = json_array_size (extensions_sigs);
  if (json_array_size (extensions) != sec.num_extensions)
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "arrays extensions and extensions_sig are not of equal size");
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received /management/extensions\n");

  sec.extensions = GNUNET_new_array (sec.num_extensions,
                                     struct Extension);
  sec.extensions_sigs = GNUNET_new_array (sec.num_extensions,
                                          struct TALER_MasterSignatureP);
  ok = true;

  for (unsigned int i = 0; i<sec.num_extensions; i++)
  {

    // 1. parse the extension
    {
      enum GNUNET_GenericReturnValue res;
      const char *name;
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_string ("extension",
                                 &name),
        GNUNET_JSON_spec_json ("config",
                               &sec.extensions[i].config_json),
        GNUNET_JSON_spec_end ()
      };

      res = TALER_MHD_parse_json_array (connection,
                                        extensions,
                                        ispec,
                                        i,
                                        -1);
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

      // Make sure name refers to a supported extension
      {
        bool found = false;
        for (unsigned int k = 0; k < TALER_Extension_Max; k++)
        {
          if (0 == strncmp (name,
                            TEH_extensions[k].name,
                            strlen (TEH_extensions[k].name)))
          {
            sec.extensions[i].type = TEH_extensions[k].type;
            found = true;
            break;
          }
        }

        if (! found)
        {
          GNUNET_free (sec.extensions);
          GNUNET_free (sec.extensions_sigs);
          GNUNET_JSON_parse_free (spec);
          GNUNET_JSON_parse_free (ispec);
          return TALER_MHD_reply_with_error (
            connection,
            MHD_HTTP_BAD_REQUEST,
            TALER_EC_GENERIC_PARAMETER_MALFORMED,
            "invalid extension type");
        }
      }

      // We have a JSON object for the extension.  Increment its refcount and
      // free the parser.
      // TODO: is this correct?
      json_incref (sec.extensions[i].config_json);
      GNUNET_JSON_parse_free (ispec);

      // Make sure the config is sound
      {
        switch (sec.extensions[i].type)
        {
        case TALER_Extension_AgeRestriction:
          if (GNUNET_OK != TALER_agemask_parse_json (
                sec.extensions[i].config_json,
                &sec.extensions[i].mask))
          {
            GNUNET_free (sec.extensions);
            GNUNET_free (sec.extensions_sigs);
            GNUNET_JSON_parse_free (spec);
            return TALER_MHD_reply_with_error (
              connection,
              MHD_HTTP_BAD_REQUEST,
              TALER_EC_GENERIC_PARAMETER_MALFORMED,
              "invalid mask for age restriction");
          }
          break;

        case TALER_Extension_Peer2Peer:   /* TODO */
          ok = false;
          ret = MHD_NO;
          goto BREAK;

        default:
          /* not reachable */
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "shouldn't be reached in handler for /management/extensions\n");
          ok = false;
          ret = MHD_NO;
          goto BREAK;
        }
      }
    }

    // 2. parse the signature
    {
      enum GNUNET_GenericReturnValue res;
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL,
                                     &sec.extensions_sigs[i]),
        GNUNET_JSON_spec_end ()
      };

      res = TALER_MHD_parse_json_array (connection,
                                        extensions_sigs,
                                        ispec,
                                        i,
                                        -1);
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

    // 3. verify the signature
    {
      enum GNUNET_GenericReturnValue res;

      switch (sec.extensions[i].type)
      {
      case TALER_Extension_AgeRestriction:
        res = TALER_exchange_offline_extension_agemask_verify (
          sec.extensions[i].mask,
          &TEH_master_public_key,
          &sec.extensions_sigs[i]);
        if (GNUNET_OK != res)
        {
          GNUNET_free (sec.extensions);
          GNUNET_free (sec.extensions_sigs);
          GNUNET_JSON_parse_free (spec);
          return TALER_MHD_reply_with_error (
            connection,
            MHD_HTTP_BAD_REQUEST,
            TALER_EC_GENERIC_PARAMETER_MALFORMED,
            "invalid signature for age mask");
        }
        break;

      case TALER_Extension_Peer2Peer:   /* TODO */
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Peer2peer not yet supported in handler for /management/extensions\n");
        ok = false;
        ret = MHD_NO;
        goto BREAK;

      default:
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "shouldn't be reached in handler for /management/extensions\n");
        ok = false;
        ret = MHD_NO;
        /* not reachable */
        goto BREAK;
      }
    }
  }

BREAK:
  if (! ok)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failure to handle /management/extensions\n");
    GNUNET_free (sec.extensions);
    GNUNET_free (sec.extensions_sigs);
    GNUNET_JSON_parse_free (spec);
    return ret;
  }


  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received %u extensions\n",
              sec.num_extensions);

  {
    enum GNUNET_GenericReturnValue res;

    res = TEH_DB_run_transaction (connection,
                                  "set extensions",
                                  TEH_MT_OTHER,
                                  &ret,
                                  &set_extensions,
                                  &sec);

    GNUNET_free (sec.extensions);
    GNUNET_free (sec.extensions_sigs);
    GNUNET_JSON_parse_free (spec);
    if (GNUNET_SYSERR == res)
      return ret;
  }

  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_management_management_post_extensions.c */
