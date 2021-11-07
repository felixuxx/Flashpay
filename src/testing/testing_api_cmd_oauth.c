/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file testing/testing_api_cmd_oauth.c
 * @brief Implement a CMD to run an OAuth service for faking the legitimation service
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_mhd_lib.h"

/**
 * State for the oauth CMD.
 */
struct OAuthState
{

  /**
   * Handle to the "oauth" service.
   */
  struct MHD_Daemon *mhd;

  /**
   * Port to listen on.
   */
  uint16_t port;
};


/**
 * A client has requested the given url using the given method
 * (#MHD_HTTP_METHOD_GET, #MHD_HTTP_METHOD_PUT,
 * #MHD_HTTP_METHOD_DELETE, #MHD_HTTP_METHOD_POST, etc).  The callback
 * must call MHD callbacks to provide content to give back to the
 * client and return an HTTP status code (i.e. #MHD_HTTP_OK,
 * #MHD_HTTP_NOT_FOUND, etc.).
 *
 * @param cls argument given together with the function
 *        pointer when the handler was registered with MHD
 * @param url the requested url
 * @param method the HTTP method used (#MHD_HTTP_METHOD_GET,
 *        #MHD_HTTP_METHOD_PUT, etc.)
 * @param version the HTTP version string (i.e.
 *        #MHD_HTTP_VERSION_1_1)
 * @param upload_data the data being uploaded (excluding HEADERS,
 *        for a POST that fits into memory and that is encoded
 *        with a supported encoding, the POST data will NOT be
 *        given in upload_data and is instead available as
 *        part of #MHD_get_connection_values; very large POST
 *        data *will* be made available incrementally in
 *        @a upload_data)
 * @param[in,out] upload_data_size set initially to the size of the
 *        @a upload_data provided; the method must update this
 *        value to the number of bytes NOT processed;
 * @param[in,out] con_cls pointer that the callback can set to some
 *        address and that will be preserved by MHD for future
 *        calls for this request; since the access handler may
 *        be called many times (i.e., for a PUT/POST operation
 *        with plenty of upload data) this allows the application
 *        to easily associate some request-specific state.
 *        If necessary, this state can be cleaned up in the
 *        global #MHD_RequestCompletedCallback (which
 *        can be set with the #MHD_OPTION_NOTIFY_COMPLETED).
 *        Initially, `*con_cls` will be NULL.
 * @return #MHD_YES if the connection was handled successfully,
 *         #MHD_NO if the socket must be closed due to a serious
 *         error while handling the request
 */
static enum MHD_Result
handler_cb (void *cls,
            struct MHD_Connection *connection,
            const char *url,
            const char *method,
            const char *version,
            const char *upload_data,
            size_t *upload_data_size,
            void **con_cls)
{
  const char *code;
  const char *client_id;
  const char *redirect_uri;
  const char *client_secret;
  unsigned int hc;
  json_t *body;

  /* NOTE: In the future, we MAY want to distinguish between
     the different URLs and possibly return more information.
     For now, just do the minimum: implement the main handler
     that checks the code. */
  code = MHD_lookup_connection_value (connection,
                                      MHD_GET_ARGUMENT_KIND,
                                      "code");
  client_id = MHD_lookup_connection_value (connection,
                                           MHD_GET_ARGUMENT_KIND,
                                           "client_id");
  redirect_uri = MHD_lookup_connection_value (connection,
                                              MHD_GET_ARGUMENT_KIND,
                                              "redirect_uri");
  client_secret = MHD_lookup_connection_value (connection,
                                               MHD_GET_ARGUMENT_KIND,
                                               "client_secret");
  if ( (NULL == code) ||
       (NULL == client_id) ||
       (NULL == redirect_uri) ||
       (NULL == client_secret) )
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  if (0 != strcmp (client_id,
                   "taler-exchange"))
  {
    body = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("error",
                               "unknown_client"),
      GNUNET_JSON_pack_string ("error_description",
                               "only 'taler-exchange' is allowed"));
    hc = MHD_HTTP_NOT_FOUND;
  }
  else if (0 != strcmp (client_secret,
                        "exchange-secret"))
  {
    body = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("error",
                               "invalid_client_secret"),
      GNUNET_JSON_pack_string ("error_description",
                               "only 'exchange-secret' is valid"));
    hc = MHD_HTTP_FORBIDDEN;
  }
  else
  {
    if (0 != strcmp (code,
                     "pass"))
    {
      body = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_string ("error",
                                 "invalid_grant"),
        GNUNET_JSON_pack_string ("error_description",
                                 "only 'pass' shall pass"));
      hc = MHD_HTTP_FORBIDDEN;
    }
    else
    {
      body = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_string ("access_token",
                                 "good"),
        GNUNET_JSON_pack_string ("token_type",
                                 "bearer"),
        GNUNET_JSON_pack_uint64 ("expires_in",
                                 3600),
        GNUNET_JSON_pack_string ("refresh_token",
                                 "better"));
      hc = MHD_HTTP_OK;
    }
  }
  return TALER_MHD_reply_json_steal (connection,
                                     body,
                                     hc);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
oauth_run (void *cls,
           const struct TALER_TESTING_Command *cmd,
           struct TALER_TESTING_Interpreter *is)
{
  struct OAuthState *oas = cls;

  (void) cmd;
  (void) is;
  oas->mhd = MHD_start_daemon (MHD_USE_AUTO_INTERNAL_THREAD,
                               oas->port,
                               NULL, NULL,
                               &handler_cb, oas,
                               NULL);
}


/**
 * Cleanup the state from a "oauth" CMD, and possibly cancel a operation
 * thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
oauth_cleanup (void *cls,
               const struct TALER_TESTING_Command *cmd)
{
  struct OAuthState *oas = cls;

  if (NULL != oas->mhd)
  {
    MHD_stop_daemon (oas->mhd);
    oas->mhd = NULL;
  }
  GNUNET_free (oas);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_oauth (const char *label,
                         uint16_t port)
{
  struct OAuthState *oas;

  oas = GNUNET_new (struct OAuthState);
  oas->port = port;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = oas,
      .label = label,
      .run = &oauth_run,
      .cleanup = &oauth_cleanup,
    };

    return cmd;
  }
}


/* end of testing_api_cmd_kyc_proof.c */
