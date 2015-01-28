/*
  This file is part of TALER
  (C) 2014 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-mint-httpd.c
 * @brief Serve the HTTP interface of the mint
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <libpq-fe.h>
#include <pthread.h>
#include "mint.h"
#include "taler_signatures.h"
#include "taler_json_lib.h"
#include "taler-mint-httpd_parsing.h"
#include "taler-mint-httpd_mhd.h"
#include "taler-mint-httpd_keys.h"
#include "taler-mint-httpd_deposit.h"
#include "taler-mint-httpd_withdraw.h"
#include "taler-mint-httpd_refresh.h"
#include "mint_db.h"


/**
 * Base directory of the mint (global)
 */
char *mintdir;

/**
 * The mint's configuration (global)
 */
struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Master public key (according to the
 * configuration in the mint directory).
 */
struct GNUNET_CRYPTO_EddsaPublicKey master_pub;

/**
 * Private key of the mint we use to sign messages.
 */
struct GNUNET_CRYPTO_EddsaPrivateKey mint_priv;

/**
 * The HTTP Daemon.
 */
static struct MHD_Daemon *mydaemon;

/**
 * The kappa value for refreshing.
 */
static unsigned int refresh_security_parameter;

/**
 * Port to run the daemon on.
 */
static uint16_t serve_port;


/**
 * Function called whenever MHD is done with a request.  If the
 * request was a POST, we may have stored a `struct Buffer *` in the
 * @a con_cls that might still need to be cleaned up.  Call the
 * respective function to free the memory.
 *
 * @param cls client-defined closure
 * @param connection connection handle
 * @param con_cls value as set by the last call to
 *        the #MHD_AccessHandlerCallback
 * @param toe reason for request termination
 * @see #MHD_OPTION_NOTIFY_COMPLETED
 * @ingroup request
 */
static void
handle_mhd_completion_callback (void *cls,
                                struct MHD_Connection *connection,
                                void **con_cls,
                                enum MHD_RequestTerminationCode toe)
{
  if (NULL == *con_cls)
    return;
  TALER_MINT_parse_post_cleanup_callback (*con_cls);
  *con_cls = NULL;
}


/**
 * Handle a request coming from libmicrohttpd.
 *
 * @param cls closure for MHD daemon (unused)
 * @param connection the connection
 * @param url the requested url
 * @param method the method (POST, GET, ...)
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request (a `struct Buffer *`)
 * @return MHD result code
 */
static int
handle_mhd_request (void *cls,
                    struct MHD_Connection *connection,
                    const char *url,
                    const char *method,
                    const char *version,
                    const char *upload_data,
                    size_t *upload_data_size,
                    void **con_cls)
{
  static struct RequestHandler handlers[] =
    {
      { "/", MHD_HTTP_METHOD_GET, "text/plain",
        "Hello, I'm the mint\n", 0,
        &TALER_MINT_handler_static_response, MHD_HTTP_OK },
      { "/agpl", MHD_HTTP_METHOD_GET, "text/plain",
        NULL, 0,
        &TALER_MINT_handler_agpl_redirect, MHD_HTTP_FOUND },
      { "/keys", MHD_HTTP_METHOD_GET, "application/json",
        NULL, 0,
        &TALER_MINT_handler_keys, MHD_HTTP_OK },
      { "/keys", NULL, "text/plain",
        "Only GET is allowed", 0,
        &TALER_MINT_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },
      { "/withdraw/status", MHD_HTTP_METHOD_GET, "application/json",
        NULL, 0,
        &TALER_MINT_handler_withdraw_status, MHD_HTTP_OK },
      { "/withdraw/status", NULL, "text/plain",
        "Only GET is allowed", 0,
        &TALER_MINT_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },
      { "/withdraw/sign", MHD_HTTP_METHOD_GET, "application/json",
        NULL, 0,
        &TALER_MINT_handler_withdraw_sign, MHD_HTTP_OK },
      { "/withdraw/sign", NULL, "text/plain",
        "Only GET is allowed", 0,
        &TALER_MINT_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },
      { "/refresh/melt", MHD_HTTP_METHOD_POST, "application/json",
        NULL, 0,
        &TALER_MINT_handler_refresh_melt, MHD_HTTP_OK },
      { "/refresh/melt", NULL, "text/plain",
        "Only POST is allowed", 0,
        &TALER_MINT_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },
      { "/refresh/commit", MHD_HTTP_METHOD_POST, "application/json",
        NULL, 0,
        &TALER_MINT_handler_refresh_commit, MHD_HTTP_OK },
      { "/refresh/commit", NULL, "text/plain",
        "Only POST is allowed", 0,
        &TALER_MINT_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },
      { "/refresh/reveal", MHD_HTTP_METHOD_POST, "application/json",
        NULL, 0,
        &TALER_MINT_handler_refresh_melt, MHD_HTTP_OK },
      { "/refresh/reveal", NULL, "text/plain",
        "Only POST is allowed", 0,
        &TALER_MINT_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },
      { "/refresh/link", MHD_HTTP_METHOD_GET, "application/json",
        NULL, 0,
        &TALER_MINT_handler_refresh_link, MHD_HTTP_OK },
      { "/refresh/link", NULL, "text/plain",
        "Only GET is allowed", 0,
        &TALER_MINT_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },
      { "/refresh/reveal", MHD_HTTP_METHOD_GET, "application/json",
        NULL, 0,
        &TALER_MINT_handler_refresh_reveal, MHD_HTTP_OK },
      { "/refresh/reveal", NULL, "text/plain",
        "Only GET is allowed", 0,
        &TALER_MINT_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },
      { "/deposit", MHD_HTTP_METHOD_POST, "application/json",
        NULL, 0,
        &TALER_MINT_handler_deposit, MHD_HTTP_OK },
      { "/deposit", NULL, "text/plain",
        "Only POST is allowed", 0,
        &TALER_MINT_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },
      { NULL, NULL, NULL, NULL, 0, 0 }
    };
  static struct RequestHandler h404 =
    {
      "", NULL, "text/html",
      "<html><title>404: not found</title></html>", 0,
      &TALER_MINT_handler_static_response, MHD_HTTP_NOT_FOUND
    };
  struct RequestHandler *rh;
  unsigned int i;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling request for URL '%s'\n",
              url);
  for (i=0;NULL != handlers[i].url;i++)
  {
    rh = &handlers[i];
    if ( (0 == strcasecmp (url,
                           rh->url)) &&
         ( (NULL == rh->method) ||
           (0 == strcasecmp (method,
                             rh->method)) ) )
      return rh->handler (rh,
                          connection,
                          con_cls,
                          upload_data,
                          upload_data_size);
  }
  return TALER_MINT_handler_static_response (&h404,
                                             connection,
                                             con_cls,
                                             upload_data,
                                             upload_data_size);
}


/**
 * Load configuration parameters for the mint
 * server into the corresponding global variables.
 *
 * @param param mint_directory the mint's directory
 * @return #GNUNET_OK on success
 */
static int
mint_serve_process_config (const char *mint_directory)
{
  unsigned long long port;
  unsigned long long kappa;
  char *master_pub_str;
  char *mint_priv_str;
  char *db_cfg;

  cfg = TALER_config_load (mint_directory);
  if (NULL == cfg)
  {
    fprintf (stderr,
             "can't load mint configuration\n");
    return 1;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "mint", "master_pub",
                                             &master_pub_str))
  {
    fprintf (stderr,
             "No master public key given in mint configuration.");
    return GNUNET_NO;
  }
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_public_key_from_string (master_pub_str,
                                                  strlen (master_pub_str),
                                                  &master_pub))
  {
    fprintf (stderr,
             "Invalid master public key given in mint configuration.");
    GNUNET_free (master_pub_str);
    return GNUNET_NO;
  }
  GNUNET_free (master_pub_str);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "mint", "mint_priv",
                                             &mint_priv_str))
  {
    fprintf (stderr,
             "No master public key given in mint configuration.");
    return GNUNET_NO;
  }
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_private_key_from_string (mint_priv_str,
                                                   strlen (mint_priv_str),
                                                   &mint_priv))
  {
    fprintf (stderr,
             "Invalid mint private key given in mint configuration.");
    GNUNET_free (mint_priv_str);
    return GNUNET_NO;
  }
  GNUNET_free (mint_priv_str);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "mint", "db",
                                             &db_cfg))
  {
    fprintf (stderr,
             "invalid configuration: mint.db\n");
    return GNUNET_NO;
  }
  if (GNUNET_OK !=
      TALER_MINT_DB_init (db_cfg))
  {
    fprintf (stderr,
             "failed to initialize DB subsystem\n");
    return GNUNET_NO;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "mint", "port",
                                             &port))
  {
    fprintf (stderr,
             "invalid configuration: mint.port\n");
    return GNUNET_NO;
  }

  if ((port == 0) || (port > UINT16_MAX))
  {
    fprintf (stderr,
             "invalid configuration (value out of range): mint.port\n");
    return GNUNET_NO;
  }
  serve_port = port;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "mint", "refresh_security_parameter",
                                             &kappa))
  {
    fprintf (stderr,
             "invalid configuration: mint.refresh_security_parameter\n");
    return GNUNET_NO;
  }
  refresh_security_parameter = kappa;

  return GNUNET_OK;
}


/**
 * The main function of the serve tool
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc, char *const *argv)
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_HELP ("gnunet-mint-keyup OPTIONS"),
    {'d', "mint-dir", "DIR",
     "mint directory", 1,
     &GNUNET_GETOPT_set_filename, &mintdir},
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-mint-serve",
                                   "INFO",
                                   NULL));
  if (GNUNET_GETOPT_run ("taler-mint-serve",
                         options,
                         argc, argv) < 0)
    return 1;
  if (NULL == mintdir)
  {
    fprintf (stderr,
             "no mint dir given\n");
    return 1;
  }

  if (GNUNET_OK != mint_serve_process_config (mintdir))
    return 1;


  mydaemon = MHD_start_daemon (MHD_USE_SELECT_INTERNALLY | MHD_USE_DEBUG,
                               serve_port,
                               NULL, NULL,
                               &handle_mhd_request, NULL,
                               MHD_OPTION_NOTIFY_COMPLETED, &handle_mhd_completion_callback,
                               MHD_OPTION_END);

  if (NULL == mydaemon)
  {
    fprintf (stderr,
             "Failed to start MHD.\n");
    return 1;
  }

  ret = TALER_MINT_key_reload_loop ();
  MHD_stop_daemon (mydaemon);
  return (GNUNET_OK == ret) ? 0 : 1;
}
