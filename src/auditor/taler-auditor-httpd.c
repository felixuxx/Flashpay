/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
 * @file taler-auditor-httpd.c
 * @brief Serve the HTTP interface of the auditor
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include <sys/resource.h>
#include "taler_mhd_lib.h"
#include "taler_auditordb_lib.h"
#include "taler_exchangedb_lib.h"
#include "taler-auditor-httpd_spa.h"
#include "taler-auditor-httpd_deposit-confirmation.h"
#include "taler-auditor-httpd_deposit-confirmation-get.h"
#include "taler-auditor-httpd_amount-arithmetic-inconsistency-get.h"
#include "taler-auditor-httpd_amount-arithmetic-inconsistency-upd.h"
#include "taler-auditor-httpd_coin-inconsistency-get.h"
#include "taler-auditor-httpd_row-inconsistency-get.h"

#include "taler-auditor-httpd_emergency-get.h"

#include "taler-auditor-httpd_emergency-by-count-get.h"

#include \
  "taler-auditor-httpd_denomination-key-validity-withdraw-inconsistency-get.h"

#include "taler-auditor-httpd_purse-not-closed-inconsistencies-get.h"

#include "taler-auditor-httpd_reserve-balance-insufficient-inconsistency-get.h"

#include "taler-auditor-httpd_bad-sig-losses-get.h"
#include "taler-auditor-httpd_bad-sig-losses-upd.h"

#include "taler-auditor-httpd_closure-lags-get.h"

#include "taler-auditor-httpd_refreshes-hanging-get.h"

#include "taler-auditor-httpd_mhd.h"
#include "taler-auditor-httpd.h"

#include "taler-auditor-httpd_delete_generic.h"
#include "taler-auditor-httpd_patch_generic_suppressed.h"
#include "taler-auditor-httpd_emergency-by-count-upd.h"
#include "taler-auditor-httpd_row-inconsistency-upd.h"
#include "taler-auditor-httpd_purse-not-closed-inconsistencies-upd.h"
#include "taler-auditor-httpd_reserve-balance-insufficient-inconsistency-upd.h"
#include "taler-auditor-httpd_coin-inconsistency-upd.h"
#include \
  "taler-auditor-httpd_denomination-key-validity-withdraw-inconsistency-upd.h"
#include "taler-auditor-httpd_refreshes-hanging-upd.h"
#include "taler-auditor-httpd_emergency-upd.h"
#include "taler-auditor-httpd_closure-lags-upd.h"
#include "taler-auditor-httpd_row-minor-inconsistencies-upd.h"

#include "taler-auditor-httpd_reserve-in-inconsistency-get.h"
#include "taler-auditor-httpd_reserve-in-inconsistency-upd.h"

#include "taler-auditor-httpd_reserve-not-closed-inconsistency-get.h"
#include "taler-auditor-httpd_reserve-not-closed-inconsistency-upd.h"

#include "taler-auditor-httpd_denominations-without-sigs-get.h"
#include "taler-auditor-httpd_denominations-without-sigs-upd.h"

#include "taler-auditor-httpd_misattribution-in-inconsistency-get.h"
#include "taler-auditor-httpd_misattribution-in-inconsistency-upd.h"

#include "taler-auditor-httpd_reserves-get.h"
#include "taler-auditor-httpd_purses-get.h"

#include "taler-auditor-httpd_historic-denomination-revenue-get.h"
#include "taler-auditor-httpd_historic-reserve-summary-get.h"

#include "taler-auditor-httpd_denomination-pending-get.h"
#include "taler-auditor-httpd_denomination-pending-upd.h"

#include "taler-auditor-httpd_wire-format-inconsistency-get.h"
#include "taler-auditor-httpd_wire-format-inconsistency-upd.h"

#include "taler-auditor-httpd_wire-out-inconsistency-get.h"
#include "taler-auditor-httpd_wire-out-inconsistency-upd.h"

#include "taler-auditor-httpd_reserve-balance-summary-wrong-inconsistency-get.h"
#include "taler-auditor-httpd_reserve-balance-summary-wrong-inconsistency-upd.h"

#include "taler-auditor-httpd_row-minor-inconsistencies-get.h"
#include "taler-auditor-httpd_row-minor-inconsistencies-upd.h"

#include "taler-auditor-httpd_fee-time-inconsistency-get.h"
#include "taler-auditor-httpd_fee-time-inconsistency-upd.h"

#include "taler-auditor-httpd_balances-get.h"
#include "taler-auditor-httpd_progress-get.h"


/**
 * Auditor protocol version string.
 *
 * Taler protocol version in the format CURRENT:REVISION:AGE
 * as used by GNU libtool.  See
 * https://www.gnu.org/software/libtool/manual/html_node/Libtool-versioning.html
 *
 * Please be very careful when updating and follow
 * https://www.gnu.org/software/libtool/manual/html_node/Updating-version-info.html#Updating-version-info
 * precisely.  Note that this version has NOTHING to do with the
 * release version, and the format is NOT the same that semantic
 * versioning uses either.
 */
#define AUDITOR_PROTOCOL_VERSION "1:0:1"

/**
 * Salt we use when doing the KDF for access.
 */
#define KDF_SALT "auditor-standard-auth"

/**
 * Backlog for listen operation on unix domain sockets.
 */
#define UNIX_BACKLOG 500

/**
 * Should we return "Connection: close" in each response?
 */
static int auditor_connection_close;

/**
 * The auditor's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our DB plugin.
 */
struct TALER_AUDITORDB_Plugin *TAH_plugin;

/**
 * Our DB plugin to talk to the *exchange* database.
 */
struct TALER_EXCHANGEDB_Plugin *TAH_eplugin;

/**
 * Public key of this auditor.
 */
static struct TALER_AuditorPublicKeyP auditor_pub;

/**
 * Exchange master public key (according to the
 * configuration).  (global)
 */
struct TALER_MasterPublicKeyP TAH_master_public_key;

/**
 * Default timeout in seconds for HTTP requests.
 */
static unsigned int connection_timeout = 30;

/**
 * Return value from main()
 */
static int global_ret;

/**
 * Disables authentication checks.
 */
static int disable_auth;

/**
 * Port to run the daemon on.
 */
static uint16_t serve_port;

/**
 * Our currency.
 */
char *TAH_currency;

/**
 * Authorization code to use.
 */
static struct GNUNET_HashCode TAH_auth;

/**
 * Prefix required for the access token.
 */
#define RFC_8959_PREFIX "secret-token:"


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
  (void) cls;
  (void) connection;
  (void) toe;
  if (NULL == *con_cls)
    return;
  TALER_MHD_parse_post_cleanup_callback (*con_cls);
  *con_cls = NULL;
}


/**
 * Handle a "/config" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @param args NULL-terminated array of remaining parts of the URI broken up at '/'
 * @return MHD result code
 */
static MHD_RESULT
handle_config (struct TAH_RequestHandler *rh,
               struct MHD_Connection *connection,
               void **connection_cls,
               const char *upload_data,
               size_t *upload_data_size,
               const char *const args[])
{
  static json_t *ver; /* we build the response only once, keep around for next query! */

  (void) rh;
  (void) upload_data;
  (void) upload_data_size;
  (void) connection_cls;
  if (NULL == ver)
  {
    ver = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("name",
                               "taler-auditor"),
      GNUNET_JSON_pack_string ("version",
                               AUDITOR_PROTOCOL_VERSION),
      GNUNET_JSON_pack_string ("implementation",
                               "urn:net:taler:specs:taler-auditor:c-reference"),
      GNUNET_JSON_pack_string ("currency",
                               TAH_currency),
      GNUNET_JSON_pack_data_auto ("auditor_public_key",
                                  &auditor_pub),
      GNUNET_JSON_pack_data_auto ("exchange_master_public_key",
                                  &TAH_master_public_key));
  }
  if (NULL == ver)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  return TALER_MHD_reply_json (connection,
                               ver,
                               MHD_HTTP_OK);
}


/**
 * Extract the token from authorization header value @a auth.
 *
 * @param auth pointer to authorization header value,
 *        will be updated to point to the start of the token
 *        or set to NULL if header value is invalid
 */
static void
extract_token (const char **auth)
{
  const char *bearer = "Bearer ";
  const char *tok = *auth;

  if (0 != strncmp (tok,
                    bearer,
                    strlen (bearer)))
  {
    *auth = NULL;
    return;
  }
  tok += strlen (bearer);
  while (' ' == *tok)
    tok++;
  if (0 != strncasecmp (tok,
                        RFC_8959_PREFIX,
                        strlen (RFC_8959_PREFIX)))
  {
    *auth = NULL;
    return;
  }
  *auth = tok;
}


static enum GNUNET_GenericReturnValue
check_auth (const char *token)
{
  struct GNUNET_HashCode val;

  if (NULL == token)
    return GNUNET_SYSERR;
  token += strlen (RFC_8959_PREFIX);
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (&val,
                                    sizeof (val),
                                    KDF_SALT,
                                    strlen (KDF_SALT),
                                    token,
                                    strlen (token),
                                    NULL,
                                    0));
  /* We compare hashes instead of directly comparing
     tokens to minimize side-channel attacks on token length */
  return (0 ==
          GNUNET_memcmp_priv (&val,
                              &TAH_auth))
           ? GNUNET_OK
           : GNUNET_SYSERR;
}


/**
 * Handle incoming HTTP request.
 *
 * @param cls closure for MHD daemon (unused)
 * @param connection the connection
 * @param url the requested url
 * @param method the method (POST, GET, ...)
 * @param version HTTP version (ignored)
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request (a `struct Buffer *`)
 * @return MHD result code
 */
static MHD_RESULT
handle_mhd_request (void *cls,
                    struct MHD_Connection *connection,
                    const char *url,
                    const char *method,
                    const char *version,
                    const char *upload_data,
                    size_t *upload_data_size,
                    void **con_cls)
{
  static struct TAH_RequestHandler handlers[] = {
    /* Our most popular handler (thus first!), used by merchants to
       probabilistically report us their deposit confirmations. */
    {
      .url = "/deposit-confirmation",
      .method = MHD_HTTP_METHOD_PUT,
      .mime_type = "application/json",
      .handler = &TAH_DEPOSIT_CONFIRMATION_handler,
      .response_code = MHD_HTTP_OK
    },
    {
      .url = "/spa",
      .method = MHD_HTTP_METHOD_GET,
      .handler = &TAH_spa_handler
    },
    {
      "/monitoring/deposit-confirmation",
      MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_DEPOSIT_CONFIRMATION_handler_get,
      MHD_HTTP_OK,
      true
    },
    { "/monitoring/deposit-confirmation", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic, MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_DEPOSIT_CONFIRMATION },
    { "/monitoring/amount-arithmetic-inconsistency", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_AMOUNT_ARITHMETIC_INCONSISTENCY_handler_get, MHD_HTTP_OK, true },
    { "/monitoring/amount-arithmetic-inconsistency", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic, MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_AMOUNT_ARITHMETIC_INCONSISTENCY },
    {
      "/monitoring/amount-arithmetic-inconsistency",
      MHD_HTTP_METHOD_PATCH,
      .mime_type = "application/json",
      .data = NULL,
      .data_size = 0,
      &TAH_patch_handler_generic_suppressed,
      MHD_HTTP_OK,
      true,
      .table = TALER_AUDITORDB_AMOUNT_ARITHMETIC_INCONSISTENCY
    },
    { "/monitoring/coin-inconsistency", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_COIN_INCONSISTENCY_handler_get, MHD_HTTP_OK, true },
    { "/monitoring/coin-inconsistency", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic, MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_COIN_INCONSISTENCY },
    { "/monitoring/coin-inconsistency", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_COIN_INCONSISTENCY_handler_update, MHD_HTTP_OK, true },
    { "/monitoring/row-inconsistency", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_ROW_INCONSISTENCY_handler_get, MHD_HTTP_OK, true },
    { "/monitoring/row-inconsistency", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic, MHD_HTTP_OK, true,
      .table = TALER_AUDITORDB_ROW_INCONSISTENCY},
    { "/monitoring/row-inconsistency", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_ROW_INCONSISTENCY_handler_update, MHD_HTTP_OK, true },
    { "/monitoring/bad-sig-losses", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_BAD_SIG_LOSSES_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/bad-sig-losses", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
      .table = TALER_AUDITORDB_BAD_SIG_LOSSES},
    { "/monitoring/bad-sig-losses", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_BAD_SIG_LOSSES_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/closure-lags", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_CLOSURE_LAGS_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/closure-lags", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_CLOSURE_LAGS },
    { "/monitoring/closure-lags", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_CLOSURE_LAGS_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/emergency", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_EMERGENCY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/emergency", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_EMERGENCY },
    { "/monitoring/emergency", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_EMERGENCY_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/refreshes-hanging", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_REFRESHES_HANGING_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/refreshes-hanging", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_REFRESHES_HANGING },
    { "/monitoring/refreshes-hanging", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_REFRESHES_HANGING_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/denomination-key-validity-withdraw-inconsistency",
      MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_DENOMINATION_KEY_VALIDITY_WITHDRAW_INCONSISTENCY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/denomination-key-validity-withdraw-inconsistency",
      MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_DENOMINATION_KEY_VALIDITY_WITHDRAW_INCONSISTENCY },
    { "/monitoring/denomination-key-validity-withdraw-inconsistency",
      MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_DENOMINATION_KEY_VALIDITY_WITHDRAW_INCONSISTENCY_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/reserve-balance-insufficient-inconsistency",
      MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_RESERVE_BALANCE_INSUFFICIENT_INCONSISTENCY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/reserve-balance-insufficient-inconsistency",
      MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_RESERVE_BALANCE_INSUFFICIENT_INCONSISTENCY },
    { "/monitoring/reserve-balance-insufficient-inconsistency",
      MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_RESERVE_BALANCE_INSUFFICIENT_INCONSISTENCY_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/purse-not-closed-inconsistencies", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_PURSE_NOT_CLOSED_INCONSISTENCIES_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/purse-not-closed-inconsistencies", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_PURSE_NOT_CLOSED_INCONSISTENCY },
    { "/monitoring/purse-not-closed-inconsistencies", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_PURSE_NOT_CLOSED_INCONSISTENCIES_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/emergency-by-count", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_EMERGENCY_BY_COUNT_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/emergency-by-count", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_EMERGENCY_BY_COUNT },
    { "/monitoring/emergency-by-count", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_EMERGENCY_BY_COUNT_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/reserve-in-inconsistency", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_RESERVE_IN_INCONSISTENCY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/reserve-in-inconsistency", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_RESERVE_IN_INCONSISTENCY },
    { "/monitoring/reserve-in-inconsistency", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_RESERVE_IN_INCONSISTENCY_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/reserve-not-closed-inconsistency", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_RESERVE_NOT_CLOSED_INCONSISTENCY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/reserve-not-closed-inconsistency", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_RESERVE_NOT_CLOSED_INCONSISTENCY },
    { "/monitoring/reserve-not-closed-inconsistency", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_RESERVE_NOT_CLOSED_INCONSISTENCY_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/denominations-without-sigs", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_DENOMINATIONS_WITHOUT_SIGS_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/denominations-without-sigs", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_DENOMINATIONS_WITHOUT_SIG },
    { "/monitoring/denominations-without-sigs", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_DENOMINATIONS_WITHOUT_SIGS_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/misattribution-in-inconsistency", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_MISATTRIBUTION_IN_INCONSISTENCY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/misattribution-in-inconsistency", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_MISATTRIBUTION_IN_INCONSISTENCY },
    { "/monitoring/misattribution-in-inconsistency", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_MISATTRIBUTION_IN_INCONSISTENCY_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/reserves", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_RESERVES_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/purses", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_PURSES_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/historic-denomination-revenue", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_HISTORIC_DENOMINATION_REVENUE_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/denomination-pending", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_DENOMINATION_PENDING_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/denomination-pending", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_DENOMINATION_PENDING },
    { "/monitoring/historic-reserve-summary", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_HISTORIC_RESERVE_SUMMARY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/wire-format-inconsistency", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_WIRE_FORMAT_INCONSISTENCY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/wire-format-inconsistency", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_WIRE_FORMAT_INCONSISTENCY },
    { "/monitoring/wire-format-inconsistency", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_WIRE_FORMAT_INCONSISTENCY_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/wire-out-inconsistency", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_WIRE_OUT_INCONSISTENCY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/wire-out-inconsistency", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_WIRE_OUT_INCONSISTENCY },
    { "/monitoring/wire-out-inconsistency", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_WIRE_OUT_INCONSISTENCY_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/reserve-balance-summary-wrong-inconsistency",
      MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_RESERVE_BALANCE_SUMMARY_WRONG_INCONSISTENCY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/reserve-balance-summary-wrong-inconsistency",
      MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_RESERVE_BALANCE_SUMMARY_WRONG_INCONSISTENCY },
    { "/monitoring/reserve-balance-summary-wrong-inconsistency",
      MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_RESERVE_BALANCE_SUMMARY_WRONG_INCONSISTENCY_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/row-minor-inconsistencies", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_ROW_MINOR_INCONSISTENCIES_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/row-minor-inconsistencies", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_ROW_MINOR_INCONSISTENCY },
    { "/monitoring/row-minor-inconsistencies", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_ROW_MINOR_INCONSISTENCIES_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/fee-time-inconsistency", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_FEE_TIME_INCONSISTENCY_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/fee-time-inconsistency", MHD_HTTP_METHOD_DELETE,
      "application/json",
      NULL, 0,
      &TAH_delete_handler_generic,
      MHD_HTTP_OK, true,
            .table = TALER_AUDITORDB_FEE_TIME_INCONSISTENCY },
    { "/monitoring/fee-time-inconsistency", MHD_HTTP_METHOD_PATCH,
      "application/json",
      NULL, 0,
      &TAH_FEE_TIME_INCONSISTENCY_handler_update,
      MHD_HTTP_OK, true },
    { "/monitoring/balances", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_BALANCES_handler_get,
      MHD_HTTP_OK, true },
    { "/monitoring/progress", MHD_HTTP_METHOD_GET,
      "application/json",
      NULL, 0,
      &TAH_PROGRESS_handler_get,
      MHD_HTTP_OK, true },
    { "/config", MHD_HTTP_METHOD_GET, "application/json",
      NULL, 0,
      &handle_config, MHD_HTTP_OK, false },
    /* /robots.txt: disallow everything */
    { "/robots.txt", MHD_HTTP_METHOD_GET, "text/plain",
      "User-agent: *\nDisallow: /\n", 0,
      &TAH_MHD_handler_static_response, MHD_HTTP_OK, false },
    /* AGPL licensing page, redirect to source. As per the AGPL-license,
       every deployment is required to offer the user a download of the
       source. We make this easy by including a redirect t the source
       here. */
    { "/agpl", MHD_HTTP_METHOD_GET, "text/plain",
      NULL, 0,
      &TAH_MHD_handler_agpl_redirect, MHD_HTTP_FOUND, false },
    /* Landing page, for now tells humans to go away
     * (NOTE: ideally, the reverse proxy will respond with a nicer page) */
    { "/", MHD_HTTP_METHOD_GET, "text/plain",
      "Hello, I'm the Taler auditor. This HTTP server is not for humans.\n", 0,
      &TAH_MHD_handler_static_response, MHD_HTTP_OK, false },
    { NULL, NULL, NULL, NULL, 0, NULL, 0, 0 }
  };
  unsigned int args_max = 3;
  const char *args[args_max + 1];
  size_t ulen = strlen (url) + 1;
  char d[ulen];
  /* const */ struct TAH_RequestHandler *match = NULL;
  bool url_match = false;

  (void) cls;
  (void) version;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling request for URL '%s'\n",
              url);
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_HEAD))
    method = MHD_HTTP_METHOD_GET; /* treat HEAD as GET here, MHD will do the rest */
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_OPTIONS) )
    return TALER_MHD_reply_cors_preflight (connection);

  memset (&args,
          0,
          sizeof (args));
  GNUNET_memcpy (d,
                 url,
                 ulen);
  {
    unsigned int i = 0;

    for (args[i] = strtok (d,
                           "/");
         NULL != args[i];
         args[i] = strtok (NULL,
                           "/"))
    {
      i++;
      if (i >= args_max)
      {
        GNUNET_break_op (0);
        goto not_found;
      }
    }
  }

  for (unsigned int i = 0; NULL != handlers[i].url; i++)
  {
    /* const */ struct TAH_RequestHandler *rh = &handlers[i];

    if ( (0 == strcmp (url,
                       rh->url)) ||
         ( (0 == strncmp (url,
                          rh->url,
                          strlen (rh->url))) &&
           ('/' == url[strlen (rh->url)]) ) )
    {
      url_match = true;
      if ( (NULL == rh->method) ||
           (0 == strcasecmp (method,
                             rh->method)) )
      {
        match = rh;
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Matched %s\n",
                    rh->url);
        break;
      }
    }
  }
  if (NULL == match)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Could not find handler for `%s'\n",
                url);
    goto not_found;
  }
  if (match->requires_auth &&
      (0 == disable_auth) )
  {
    const char *auth;

    auth = MHD_lookup_connection_value (connection,
                                        MHD_HEADER_KIND,
                                        MHD_HTTP_HEADER_AUTHORIZATION);
    if (NULL == auth)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_UNAUTHORIZED,
        TALER_EC_AUDITOR_GENERIC_UNAUTHORIZED,
        "Check 'Authorization' header");
    }
    extract_token (&auth);
    if (NULL == auth)
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_UNAUTHORIZED,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "'" RFC_8959_PREFIX
        "' prefix or 'Bearer' missing in 'Authorization' header");

    if (GNUNET_OK !=
        check_auth (auth))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_UNAUTHORIZED,
        TALER_EC_AUDITOR_GENERIC_UNAUTHORIZED,
        "Check 'Authorization' header");
    }
  }

  return match->handler (match,
                         connection,
                         con_cls,
                         upload_data,
                         upload_data_size,
                         args);
not_found:
  if (url_match)
  {
    /* FIXME: return list of allowed methods... */
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_METHOD_NOT_ALLOWED,
      TALER_EC_AUDITOR_GENERIC_METHOD_NOT_ALLOWED,
      "This method is currently disabled.");
  }

#define NOT_FOUND \
  "<html><title>404: not found</title><body>auditor endpoints have been moved to /monitoring/...</body></html>"
  return TALER_MHD_reply_static (connection,
                                 MHD_HTTP_NOT_FOUND,
                                 "text/html",
                                 NOT_FOUND,
                                 strlen (NOT_FOUND));
#undef NOT_FOUND
}


/**
 * Load configuration parameters for the auditor
 * server into the corresponding global variables.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
auditor_serve_process_config (void)
{
  if (NULL ==
      (TAH_plugin = TALER_AUDITORDB_plugin_load (cfg)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem to interact with auditor database\n");
    return GNUNET_SYSERR;
  }
  if (NULL ==
      (TAH_eplugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem to query exchange database\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_SYSERR ==
      TAH_eplugin->preflight (TAH_eplugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem to query exchange database\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &TAH_currency))
  {
    return GNUNET_SYSERR;
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
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_public_key_from_string (
          master_public_key_str,
          strlen (master_public_key_str),
          &TAH_master_public_key.eddsa_pub))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "MASTER_PUBLIC_KEY",
                                 "invalid base32 encoding for a master public key");
      GNUNET_free (master_public_key_str);
      return GNUNET_SYSERR;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Launching auditor for exchange `%s'...\n",
                master_public_key_str);
    GNUNET_free (master_public_key_str);
  }

  {
    char *pub;

    if (GNUNET_OK ==
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "AUDITOR",
                                               "PUBLIC_KEY",
                                               &pub))
    {
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_public_key_from_string (pub,
                                                      strlen (pub),
                                                      &auditor_pub.eddsa_pub))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Invalid public key given in auditor configuration.");
        GNUNET_free (pub);
        return GNUNET_SYSERR;
      }
      GNUNET_free (pub);
      return GNUNET_OK;
    }
  }

  {
    /* Fall back to trying to read private key */
    char *auditor_key_file;
    struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 "auditor",
                                                 "AUDITOR_PRIV_FILE",
                                                 &auditor_key_file))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "AUDITOR",
                                 "PUBLIC_KEY");
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "AUDITOR",
                                 "AUDITOR_PRIV_FILE");
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_key_from_file (auditor_key_file,
                                           GNUNET_NO,
                                           &eddsa_priv))
    {
      /* Both failed, complain! */
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "AUDITOR",
                                 "PUBLIC_KEY");
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to initialize auditor key from file `%s'\n",
                  auditor_key_file);
      GNUNET_free (auditor_key_file);
      return 1;
    }
    GNUNET_free (auditor_key_file);
    GNUNET_CRYPTO_eddsa_key_get_public (&eddsa_priv,
                                        &auditor_pub.eddsa_pub);
  }
  return GNUNET_OK;
}


/**
 * Function run on shutdown.
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  struct MHD_Daemon *mhd;
  (void) cls;

  mhd = TALER_MHD_daemon_stop ();
  TEAH_DEPOSIT_CONFIRMATION_done ();
  if (NULL != mhd)
    MHD_stop_daemon (mhd);
  if (NULL != TAH_plugin)
  {
    TALER_AUDITORDB_plugin_unload (TAH_plugin);
    TAH_plugin = NULL;
  }
  if (NULL != TAH_eplugin)
  {
    TALER_EXCHANGEDB_plugin_unload (TAH_eplugin);
    TAH_eplugin = NULL;
  }
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be
 *        NULL!)
 * @param config configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *config)
{
  enum TALER_MHD_GlobalOptions go;
  int fh;

  (void) cls;
  (void) args;
  (void) cfgfile;
  if (0 == disable_auth)
  {
    const char *tok;

    tok = getenv ("TALER_AUDITOR_ACCESS_TOKEN");
    if (NULL == tok)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "TALER_AUDITOR_ACCESS_TOKEN environment variable not set. Disabling authentication\n");
      disable_auth = 1;
    }
    else
    {
      GNUNET_assert (GNUNET_YES ==
                     GNUNET_CRYPTO_kdf (&TAH_auth,
                                        sizeof (TAH_auth),
                                        KDF_SALT,
                                        strlen (KDF_SALT),
                                        tok,
                                        strlen (tok),
                                        NULL,
                                        0));
    }
  }

  go = TALER_MHD_GO_NONE;
  if (auditor_connection_close)
    go |= TALER_MHD_GO_FORCE_CONNECTION_CLOSE;
  TALER_MHD_setup (go);
  cfg = config;

  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  if (GNUNET_OK !=
      auditor_serve_process_config ())
  {
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK !=
      TAH_spa_init ())
  {
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  TEAH_DEPOSIT_CONFIRMATION_init ();
  fh = TALER_MHD_bind (cfg,
                       "auditor",
                       &serve_port);
  if ( (0 == serve_port) &&
       (-1 == fh) )
  {
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  {
    struct MHD_Daemon *mhd;

    mhd = MHD_start_daemon (MHD_USE_SUSPEND_RESUME
                            | MHD_USE_PIPE_FOR_SHUTDOWN
                            | MHD_USE_DEBUG | MHD_USE_DUAL_STACK
                            | MHD_USE_TCP_FASTOPEN,
                            (-1 == fh) ? serve_port : 0,
                            NULL, NULL,
                            &handle_mhd_request, NULL,
                            MHD_OPTION_LISTEN_BACKLOG_SIZE,
                            (unsigned int) 1024,
                            MHD_OPTION_LISTEN_SOCKET,
                            fh,
                            MHD_OPTION_EXTERNAL_LOGGER,
                            &TALER_MHD_handle_logs,
                            NULL,
                            MHD_OPTION_NOTIFY_COMPLETED,
                            &handle_mhd_completion_callback,
                            NULL,
                            MHD_OPTION_CONNECTION_TIMEOUT,
                            connection_timeout,
                            MHD_OPTION_END);
    if (NULL == mhd)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to launch HTTP service. Is the port in use?\n");
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    global_ret = EXIT_SUCCESS;
    TALER_MHD_daemon_start (mhd);
  }
}


/**
 * The main function of the taler-auditor-httpd server ("the auditor").
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_flag ('C',
                               "connection-close",
                               "force HTTP connections to be closed after each request",
                               &auditor_connection_close),
    GNUNET_GETOPT_option_flag ('n',
                               "no-authentication",
                               "disable authentication checks",
                               &disable_auth),
    GNUNET_GETOPT_option_uint ('t',
                               "timeout",
                               "SECONDS",
                               "after how long do connections timeout by default (in seconds)",
                               &connection_timeout),
    GNUNET_GETOPT_option_help (
      "HTTP server providing a RESTful API to access a Taler auditor"),
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (argc, argv,
                            "taler-auditor-httpd",
                            "Taler auditor HTTP service",
                            options,
                            &run, NULL);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-auditor-httpd.c */
