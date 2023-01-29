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


struct RequestCtx
{
  struct MHD_PostProcessor *pp;
  char *code;
  char *client_id;
  char *redirect_uri;
  char *client_secret;
};


static void
append (char **target,
        const char *data,
        size_t size)
{
  char *tmp;

  if (NULL == *target)
  {
    *target = GNUNET_strndup (data,
                              size);
    return;
  }
  GNUNET_asprintf (&tmp,
                   "%s%.*s",
                   *target,
                   (int) size,
                   data);
  GNUNET_free (*target);
  *target = tmp;
}


static MHD_RESULT
handle_post (void *cls,
             enum MHD_ValueKind kind,
             const char *key,
             const char *filename,
             const char *content_type,
             const char *transfer_encoding,
             const char *data,
             uint64_t off,
             size_t size)
{
  struct RequestCtx *rc = cls;

  (void) kind;
  (void) filename;
  (void) content_type;
  (void) transfer_encoding;
  (void) off;
  if (0 == strcmp (key,
                   "code"))
    append (&rc->code,
            data,
            size);
  if (0 == strcmp (key,
                   "client_id"))
    append (&rc->client_id,
            data,
            size);
  if (0 == strcmp (key,
                   "redirect_uri"))
    append (&rc->redirect_uri,
            data,
            size);
  if (0 == strcmp (key,
                   "client_secret"))
    append (&rc->client_secret,
            data,
            size);
  return MHD_YES;
}


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
 * @param connection the connection being handled
 * @param url the requested url
 * @param method the HTTP method used (#MHD_HTTP_METHOD_GET,
 *        #MHD_HTTP_METHOD_PUT, etc.)
 * @param version the HTTP version string (i.e.
 *        MHD_HTTP_VERSION_1_1)
 * @param upload_data the data being uploaded (excluding HEADERS,
 *        for a POST that fits into memory and that is encoded
 *        with a supported encoding, the POST data will NOT be
 *        given in upload_data and is instead available as
 *        part of MHD_get_connection_values(); very large POST
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
 *        global MHD_RequestCompletedCallback (which
 *        can be set with the #MHD_OPTION_NOTIFY_COMPLETED).
 *        Initially, `*con_cls` will be NULL.
 * @return #MHD_YES if the connection was handled successfully,
 *         #MHD_NO if the socket must be closed due to a serious
 *         error while handling the request
 */
static MHD_RESULT
handler_cb (void *cls,
            struct MHD_Connection *connection,
            const char *url,
            const char *method,
            const char *version,
            const char *upload_data,
            size_t *upload_data_size,
            void **con_cls)
{
  struct RequestCtx *rc = *con_cls;
  unsigned int hc;
  json_t *body;

  (void) cls;
  (void) version;
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_GET))
  {
    body = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string (
        "status",
        "success"),
      GNUNET_JSON_pack_object_steal (
        "data",
        GNUNET_JSON_PACK (
          GNUNET_JSON_pack_string ("id",
                                   "XXXID12345678"),
          GNUNET_JSON_pack_string ("first_name",
                                   "Bob"),
          GNUNET_JSON_pack_string ("last_name",
                                   "Builder")
          )));
    return TALER_MHD_reply_json_steal (connection,
                                       body,
                                       MHD_HTTP_OK);
  }
  if (0 != strcasecmp (method,
                       MHD_HTTP_METHOD_POST))
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  if (NULL == rc)
  {
    rc = GNUNET_new (struct RequestCtx);
    *con_cls = rc;
    rc->pp = MHD_create_post_processor (connection,
                                        4092,
                                        &handle_post,
                                        rc);
    return MHD_YES;
  }
  if (0 != *upload_data_size)
  {
    MHD_RESULT ret;

    ret = MHD_post_process (rc->pp,
                            upload_data,
                            *upload_data_size);
    *upload_data_size = 0;
    return ret;
  }


  /* NOTE: In the future, we MAY want to distinguish between
     the different URLs and possibly return more information.
     For now, just do the minimum: implement the main handler
     that checks the code. */
  if ( (NULL == rc->code) ||
       (NULL == rc->client_id) ||
       (NULL == rc->redirect_uri) ||
       (NULL == rc->client_secret) )
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Bad request to Oauth faker: `%s' with %s/%s/%s/%s\n",
                url,
                rc->code,
                rc->client_id,
                rc->redirect_uri,
                rc->client_secret);
    return MHD_NO;
  }
  if (0 != strcmp (rc->client_id,
                   "taler-exchange"))
  {
    body = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("error",
                               "unknown_client"),
      GNUNET_JSON_pack_string ("error_description",
                               "only 'taler-exchange' is allowed"));
    hc = MHD_HTTP_NOT_FOUND;
  }
  else if (0 != strcmp (rc->client_secret,
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
    if (0 != strcmp (rc->code,
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


static void
cleanup (void *cls,
         struct MHD_Connection *connection,
         void **con_cls,
         enum MHD_RequestTerminationCode toe)
{
  struct RequestCtx *rc = *con_cls;

  (void) cls;
  (void) connection;
  (void) toe;
  if (NULL == rc)
    return;
  GNUNET_free (rc->code);
  GNUNET_free (rc->client_id);
  GNUNET_free (rc->redirect_uri);
  GNUNET_free (rc->client_secret);
  GNUNET_free (rc);
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
  oas->mhd = MHD_start_daemon (MHD_USE_AUTO_INTERNAL_THREAD,
                               oas->port,
                               NULL, NULL,
                               &handler_cb, oas,
                               MHD_OPTION_NOTIFY_COMPLETED, &cleanup, NULL,
                               NULL);
  TALER_TESTING_interpreter_next (is);
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

  (void) cmd;
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


/* end of testing_api_cmd_oauth.c */
