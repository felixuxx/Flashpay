/*
   This file is part of TALER
   Copyright (C) 2014-2023 Taler Systems SA

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
 * @file taler-exchange-httpd.c
 * @brief Serve the HTTP interface of the exchange
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <sched.h>
#include <sys/resource.h>
#include <limits.h>
#include "taler_kyclogic_lib.h"
#include "taler_templating_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_aml-decision.h"
#include "taler-exchange-httpd_auditors.h"
#include "taler-exchange-httpd_batch-deposit.h"
#include "taler-exchange-httpd_batch-withdraw.h"
#include "taler-exchange-httpd_config.h"
#include "taler-exchange-httpd_contract.h"
#include "taler-exchange-httpd_csr.h"
#include "taler-exchange-httpd_deposit.h"
#include "taler-exchange-httpd_deposits_get.h"
#include "taler-exchange-httpd_extensions.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_kyc-check.h"
#include "taler-exchange-httpd_kyc-proof.h"
#include "taler-exchange-httpd_kyc-wallet.h"
#include "taler-exchange-httpd_link.h"
#include "taler-exchange-httpd_management.h"
#include "taler-exchange-httpd_melt.h"
#include "taler-exchange-httpd_metrics.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_purses_create.h"
#include "taler-exchange-httpd_purses_deposit.h"
#include "taler-exchange-httpd_purses_get.h"
#include "taler-exchange-httpd_purses_delete.h"
#include "taler-exchange-httpd_purses_merge.h"
#include "taler-exchange-httpd_recoup.h"
#include "taler-exchange-httpd_recoup-refresh.h"
#include "taler-exchange-httpd_refreshes_reveal.h"
#include "taler-exchange-httpd_refund.h"
#include "taler-exchange-httpd_reserves_attest.h"
#include "taler-exchange-httpd_reserves_close.h"
#include "taler-exchange-httpd_reserves_get.h"
#include "taler-exchange-httpd_reserves_get_attest.h"
#include "taler-exchange-httpd_reserves_history.h"
#include "taler-exchange-httpd_reserves_open.h"
#include "taler-exchange-httpd_reserves_purse.h"
#include "taler-exchange-httpd_reserves_status.h"
#include "taler-exchange-httpd_terms.h"
#include "taler-exchange-httpd_transfers_get.h"
#include "taler-exchange-httpd_wire.h"
#include "taler-exchange-httpd_withdraw.h"
#include "taler_exchangedb_lib.h"
#include "taler_exchangedb_plugin.h"
#include "taler_extensions.h"
#include <gnunet/gnunet_mhd_compat.h>

/**
 * Backlog for listen operation on unix domain sockets.
 */
#define UNIX_BACKLOG 50

/**
 * How often will we try to connect to the database before giving up?
 */
#define MAX_DB_RETRIES 5

/**
 * Above what request latency do we start to log?
 */
#define WARN_LATENCY GNUNET_TIME_relative_multiply ( \
    GNUNET_TIME_UNIT_MILLISECONDS, 500)

/**
 * Are clients allowed to request /keys for times other than the
 * current time? Allowing this could be abused in a DoS-attack
 * as building new /keys responses is expensive. Should only be
 * enabled for testcases, development and test systems.
 */
int TEH_allow_keys_timetravel;

/**
 * Should we allow two HTTPDs to bind to the same port?
 */
static int allow_address_reuse;

/**
 * The exchange's configuration (global)
 */
const struct GNUNET_CONFIGURATION_Handle *TEH_cfg;

/**
 * Configuration of age restriction
 *
 * Set after loading the library, enabled in database event handler.
 */
bool TEH_age_restriction_enabled = false;
struct TALER_AgeRestrictionConfig TEH_age_restriction_config = {0};

/**
 * Handle to the HTTP server.
 */
static struct MHD_Daemon *mhd;

/**
 * How long is caching /keys allowed at most? (global)
 */
struct GNUNET_TIME_Relative TEH_max_keys_caching;

/**
 * How long is the delay before we close reserves?
 */
struct GNUNET_TIME_Relative TEH_reserve_closing_delay;

/**
 * Master public key (according to the
 * configuration in the exchange directory).  (global)
 */
struct TALER_MasterPublicKeyP TEH_master_public_key;

/**
 * Key used to encrypt KYC attribute data in our database.
 */
struct TALER_AttributeEncryptionKeyP TEH_attribute_key;

/**
 * Our DB plugin.  (global)
 */
struct TALER_EXCHANGEDB_Plugin *TEH_plugin;

/**
 * Our currency.
 */
char *TEH_currency;

/**
 * Name of the KYC-AML-trigger evaluation binary.
 */
char *TEH_kyc_aml_trigger;

/**
 * Option set to #GNUNET_YES if tipping is enabled.
 */
int TEH_enable_tipping;

/**
 * What is the largest amount we allow a peer to
 * merge into a reserve before always triggering
 * an AML check?
 */
struct TALER_Amount TEH_aml_threshold;

/**
 * Our base URL.
 */
char *TEH_base_url;

/**
 * Default timeout in seconds for HTTP requests.
 */
static unsigned int connection_timeout = 30;

/**
 * -C command-line flag given?
 */
static int connection_close;

/**
 * -I command-line flag given?
 */
int TEH_check_invariants_flag;

/**
 * True if we should commit suicide once all active
 * connections are finished.
 */
bool TEH_suicide;

/**
 * Signature of the configuration of all enabled extensions,
 * signed by the exchange's offline master key with purpose
 * TALER_SIGNATURE_MASTER_EXTENSION.
 */
struct TALER_MasterSignatureP TEH_extensions_sig;
bool TEH_extensions_signed = false;

/**
 * Value to return from main()
 */
static int global_ret;

/**
 * Port to run the daemon on.
 */
static uint16_t serve_port;

/**
 * Counter for the number of requests this HTTP has processed so far.
 */
static unsigned long long req_count;

/**
 * Counter for the number of open connections.
 */
static unsigned long long active_connections;

/**
 * Limit for the number of requests this HTTP may process before restarting.
 * (This was added as one way of dealing with unavoidable memory fragmentation
 * happening slowly over time.)
 */
static unsigned long long req_max;

/**
 * Context for all CURL operations (useful to the event loop)
 */
struct GNUNET_CURL_Context *TEH_curl_ctx;

/**
 * Context for integrating #TEH_curl_ctx with the
 * GNUnet event loop.
 */
static struct GNUNET_CURL_RescheduleContext *exchange_curl_rc;

/**
 * Signature of functions that handle operations on coins.
 *
 * @param connection the MHD connection to handle
 * @param coin_pub the public key of the coin
 * @param root uploaded JSON data
 * @return MHD result code
 */
typedef MHD_RESULT
(*CoinOpHandler)(struct MHD_Connection *connection,
                 const struct TALER_CoinSpendPublicKeyP *coin_pub,
                 const json_t *root);


/**
 * Generate a 404 "not found" reply on @a connection with
 * the hint @a details.
 *
 * @param connection where to send the reply on
 * @param details details for the error message, can be NULL
 */
static MHD_RESULT
r404 (struct MHD_Connection *connection,
      const char *details)
{
  return TALER_MHD_reply_with_error (connection,
                                     MHD_HTTP_NOT_FOUND,
                                     TALER_EC_EXCHANGE_GENERIC_OPERATION_UNKNOWN,
                                     details);
}


/**
 * Handle a "/coins/$COIN_PUB/$OP" POST request.  Parses the "coin_pub"
 * EdDSA key of the coin and demultiplexes based on $OP.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param args array of additional options
 * @return MHD result code
 */
static MHD_RESULT
handle_post_coins (struct TEH_RequestContext *rc,
                   const json_t *root,
                   const char *const args[2])
{
  struct TALER_CoinSpendPublicKeyP coin_pub;
  static const struct
  {
    /**
     * Name of the operation (args[1])
     */
    const char *op;

    /**
     * Function to call to perform the operation.
     */
    CoinOpHandler handler;

  } h[] = {
    {
      .op = "deposit",
      .handler = &TEH_handler_deposit
    },
    {
      .op = "melt",
      .handler = &TEH_handler_melt
    },
    {
      .op = "recoup",
      .handler = &TEH_handler_recoup
    },
    {
      .op = "recoup-refresh",
      .handler = &TEH_handler_recoup_refresh
    },
    {
      .op = "refund",
      .handler = &TEH_handler_refund
    },
    {
      .op = NULL,
      .handler = NULL
    },
  };

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &coin_pub,
                                     sizeof (coin_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_GENERIC_COINS_INVALID_COIN_PUB,
                                       args[0]);
  }
  for (unsigned int i = 0; NULL != h[i].op; i++)
    if (0 == strcmp (h[i].op,
                     args[1]))
      return h[i].handler (rc->connection,
                           &coin_pub,
                           root);
  return r404 (rc->connection,
               args[1]);
}


/**
 * Signature of functions that handle operations
 * authorized by AML officers.
 *
 * @param rc request context
 * @param officer_pub the public key of the AML officer
 * @param root uploaded JSON data
 * @return MHD result code
 */
typedef MHD_RESULT
(*AmlOpPostHandler)(struct TEH_RequestContext *rc,
                    const struct TALER_AmlOfficerPublicKeyP *officer_pub,
                    const json_t *root);


/**
 * Handle a "/aml/$OFFICER_PUB/$OP" POST request.  Parses the "officer_pub"
 * EdDSA key of the officer and demultiplexes based on $OP.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param args array of additional options
 * @return MHD result code
 */
static MHD_RESULT
handle_post_aml (struct TEH_RequestContext *rc,
                 const json_t *root,
                 const char *const args[2])
{
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  static const struct
  {
    /**
     * Name of the operation (args[1])
     */
    const char *op;

    /**
     * Function to call to perform the operation.
     */
    AmlOpPostHandler handler;

  } h[] = {
    {
      .op = "decision",
      .handler = &TEH_handler_post_aml_decision
    },
    {
      .op = NULL,
      .handler = NULL
    },
  };

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &officer_pub,
                                     sizeof (officer_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_GENERIC_AML_OFFICER_PUB_MALFORMED,
                                       args[0]);
  }
  for (unsigned int i = 0; NULL != h[i].op; i++)
    if (0 == strcmp (h[i].op,
                     args[1]))
      return h[i].handler (rc,
                           &officer_pub,
                           root);
  return r404 (rc->connection,
               args[1]);
}


/**
 * Signature of functions that handle operations
 * authorized by AML officers.
 *
 * @param rc request context
 * @param officer_pub the public key of the AML officer
 * @param args remaining arguments
 * @return MHD result code
 */
typedef MHD_RESULT
(*AmlOpGetHandler)(struct TEH_RequestContext *rc,
                   const struct TALER_AmlOfficerPublicKeyP *officer_pub,
                   const char *const args[]);


/**
 * Handle a "/aml/$OFFICER_PUB/$OP" GET request.  Parses the "officer_pub"
 * EdDSA key of the officer, checks the authentication signature, and
 * demultiplexes based on $OP.
 *
 * @param rc request context
 * @param args array of additional options
 * @return MHD result code
 */
static MHD_RESULT
handle_get_aml (struct TEH_RequestContext *rc,
                const char *const args[])
{
  struct TALER_AmlOfficerPublicKeyP officer_pub;
  static const struct
  {
    /**
     * Name of the operation (args[1])
     */
    const char *op;

    /**
     * Function to call to perform the operation.
     */
    AmlOpGetHandler handler;

  } h[] = {
    {
      .op = "decisions",
      .handler = &TEH_handler_aml_decisions_get
    },
    {
      .op = "decision",
      .handler = &TEH_handler_aml_decision_get
    },
    {
      .op = NULL,
      .handler = NULL
    },
  };

  if (NULL == args[0])
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_GENERIC_AML_OFFICER_PUB_MALFORMED,
                                       "argument missing");
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &officer_pub,
                                     sizeof (officer_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_GENERIC_AML_OFFICER_PUB_MALFORMED,
                                       args[0]);
  }
  if (NULL == args[1])
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_GENERIC_WRONG_NUMBER_OF_SEGMENTS,
                                       "AML GET operations must specify an operation identifier");
  }
  {
    const char *sig_hdr;
    struct TALER_AmlOfficerSignatureP officer_sig;

    sig_hdr = MHD_lookup_connection_value (rc->connection,
                                           MHD_HEADER_KIND,
                                           TALER_AML_OFFICER_SIGNATURE_HEADER);
    if ( (NULL == sig_hdr) ||
         (GNUNET_OK !=
          GNUNET_STRINGS_string_to_data (sig_hdr,
                                         strlen (sig_hdr),
                                         &officer_sig,
                                         sizeof (officer_sig))) ||
         (GNUNET_OK !=
          TALER_officer_aml_query_verify (&officer_pub,
                                          &officer_sig)) )
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_GENERIC_AML_OFFICER_GET_SIGNATURE_INVALID,
                                         sig_hdr);
    }
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  }

  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->test_aml_officer (TEH_plugin->cls,
                                       &officer_pub);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         NULL);
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_EXCHANGE_GENERIC_AML_OFFICER_ACCESS_DENIED,
                                         NULL);
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      break;
    }
  }
  for (unsigned int i = 0; NULL != h[i].op; i++)
    if (0 == strcmp (h[i].op,
                     args[1]))
      return h[i].handler (rc,
                           &officer_pub,
                           &args[2]);
  return r404 (rc->connection,
               args[1]);
}


/**
 * Signature of functions that handle operations on reserves.
 *
 * @param rc request context
 * @param reserve_pub the public key of the reserve
 * @param root uploaded JSON data
 * @return MHD result code
 */
typedef MHD_RESULT
(*ReserveOpHandler)(struct TEH_RequestContext *rc,
                    const struct TALER_ReservePublicKeyP *reserve_pub,
                    const json_t *root);


/**
 * Handle a "/reserves/$RESERVE_PUB/$OP" POST request.  Parses the "reserve_pub"
 * EdDSA key of the reserve and demultiplexes based on $OP.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param args array of additional options
 * @return MHD result code
 */
static MHD_RESULT
handle_post_reserves (struct TEH_RequestContext *rc,
                      const json_t *root,
                      const char *const args[2])
{
  struct TALER_ReservePublicKeyP reserve_pub;
  static const struct
  {
    /**
     * Name of the operation (args[1])
     */
    const char *op;

    /**
     * Function to call to perform the operation.
     */
    ReserveOpHandler handler;

  } h[] = {
    {
      .op = "batch-withdraw",
      .handler = &TEH_handler_batch_withdraw
    },
    {
      .op = "withdraw",
      .handler = &TEH_handler_withdraw
    },
    {
      .op = "status",
      .handler = &TEH_handler_reserves_status
    },
    {
      .op = "history",
      .handler = &TEH_handler_reserves_history
    },
    {
      .op = "purse",
      .handler = &TEH_handler_reserves_purse
    },
    {
      .op = "open",
      .handler = &TEH_handler_reserves_open
    },
    {
      .op = "close",
      .handler = &TEH_handler_reserves_close
    },
    {
      .op = NULL,
      .handler = NULL
    },
  };

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &reserve_pub,
                                     sizeof (reserve_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_RESERVE_PUB_MALFORMED,
                                       args[0]);
  }
  for (unsigned int i = 0; NULL != h[i].op; i++)
    if (0 == strcmp (h[i].op,
                     args[1]))
      return h[i].handler (rc,
                           &reserve_pub,
                           root);
  return r404 (rc->connection,
               args[1]);
}


/**
 * Signature of functions that handle operations on purses.
 *
 * @param connection HTTP request handle
 * @param purse_pub the public key of the purse
 * @param root uploaded JSON data
 * @return MHD result code
 */
typedef MHD_RESULT
(*PurseOpHandler)(struct MHD_Connection *connection,
                  const struct TALER_PurseContractPublicKeyP *purse_pub,
                  const json_t *root);


/**
 * Handle a "/purses/$RESERVE_PUB/$OP" POST request.  Parses the "purse_pub"
 * EdDSA key of the purse and demultiplexes based on $OP.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param args array of additional options
 * @return MHD result code
 */
static MHD_RESULT
handle_post_purses (struct TEH_RequestContext *rc,
                    const json_t *root,
                    const char *const args[2])
{
  struct TALER_PurseContractPublicKeyP purse_pub;
  static const struct
  {
    /**
     * Name of the operation (args[1])
     */
    const char *op;

    /**
     * Function to call to perform the operation.
     */
    PurseOpHandler handler;

  } h[] = {
    {
      .op = "create",
      .handler = &TEH_handler_purses_create
    },
    {
      .op = "deposit",
      .handler = &TEH_handler_purses_deposit
    },
    {
      .op = "merge",
      .handler = &TEH_handler_purses_merge
    },
    {
      .op = NULL,
      .handler = NULL
    },
  };

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &purse_pub,
                                     sizeof (purse_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_GENERIC_PURSE_PUB_MALFORMED,
                                       args[0]);
  }
  for (unsigned int i = 0; NULL != h[i].op; i++)
    if (0 == strcmp (h[i].op,
                     args[1]))
      return h[i].handler (rc->connection,
                           &purse_pub,
                           root);
  return r404 (rc->connection,
               args[1]);
}


/**
 * Increments our request counter and checks if this
 * process should commit suicide.
 */
static void
check_suicide (void)
{
  int fd;
  pid_t chld;
  unsigned long long cnt;

  cnt = req_count++;
  if (req_max != cnt)
    return;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Restarting exchange service after %llu requests\n",
              cnt);
  /* Stop accepting new connections */
  fd = MHD_quiesce_daemon (mhd);
  GNUNET_break (0 == close (fd));
  /* Continue handling existing connections in child,
     so that this process can die and be replaced by
     systemd with a fresh one */
  chld = fork ();
  if (-1 == chld)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "fork");
    _exit (1);
  }
  if (0 != chld)
  {
    /* We are the parent, instant-suicide! */
    _exit (0);
  }
  TEH_suicide = true;
}


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
  struct TEH_RequestContext *rc = *con_cls;
  struct GNUNET_AsyncScopeSave old_scope;

  (void) cls;
  if (NULL == rc)
    return;
  GNUNET_async_scope_enter (&rc->async_scope_id,
                            &old_scope);
  check_suicide ();
  TEH_check_invariants ();
  if (NULL != rc->rh_cleaner)
    rc->rh_cleaner (rc);
  TEH_check_invariants ();
  {
#if MHD_VERSION >= 0x00097304
    const union MHD_ConnectionInfo *ci;
    unsigned int http_status = 0;

    ci = MHD_get_connection_info (connection,
                                  MHD_CONNECTION_INFO_HTTP_STATUS);
    if (NULL != ci)
      http_status = ci->http_status;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Request for `%s' completed with HTTP status %u (%d)\n",
                rc->url,
                http_status,
                toe);
#else
    (void) connection;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Request for `%s' completed (%d)\n",
                rc->url,
                toe);
#endif
  }

  TALER_MHD_parse_post_cleanup_callback (rc->opaque_post_parsing_context);
  /* Sanity-check that we didn't leave any transactions hanging */
  GNUNET_break (GNUNET_OK ==
                TEH_plugin->preflight (TEH_plugin->cls));
  {
    struct GNUNET_TIME_Relative latency;

    latency = GNUNET_TIME_absolute_get_duration (rc->start_time);
    if (latency.rel_value_us >
        WARN_LATENCY.rel_value_us)
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Request for `%s' took %s\n",
                  rc->url,
                  GNUNET_STRINGS_relative_time_to_string (latency,
                                                          GNUNET_YES));
  }
  GNUNET_free (rc);
  *con_cls = NULL;
  GNUNET_async_scope_restore (&old_scope);
}


/**
 * We found a request handler responsible for handling a request. Parse the
 * @a upload_data (if applicable) and the @a url and call the
 * handler.
 *
 * @param rc request context
 * @param url rest of the URL to parse
 * @param upload_data upload data to parse (if available)
 * @param[in,out] upload_data_size number of bytes in @a upload_data
 * @return MHD result code
 */
static MHD_RESULT
proceed_with_handler (struct TEH_RequestContext *rc,
                      const char *url,
                      const char *upload_data,
                      size_t *upload_data_size)
{
  const struct TEH_RequestHandler *rh = rc->rh;
  const char *args[rh->nargs + 2];
  size_t ulen = strlen (url) + 1;
  json_t *root = NULL;
  MHD_RESULT ret;

  /* We do check for "ulen" here, because we'll later stack-allocate a buffer
     of that size and don't want to enable malicious clients to cause us
     huge stack allocations. */
  if (ulen > 512)
  {
    /* 512 is simply "big enough", as it is bigger than "6 * 54",
       which is the longest URL format we ever get (for
       /deposits/).  The value should be adjusted if we ever define protocol
       endpoints with plausibly longer inputs.  */
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_URI_TOO_LONG,
                                       TALER_EC_GENERIC_URI_TOO_LONG,
                                       url);
  }

  /* All POST endpoints come with a body in JSON format. So we parse
     the JSON here. */
  if (0 == strcasecmp (rh->method,
                       MHD_HTTP_METHOD_POST))
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_post_json (rc->connection,
                                     &rc->opaque_post_parsing_context,
                                     upload_data,
                                     upload_data_size,
                                     &root);
    if (GNUNET_SYSERR == res)
    {
      GNUNET_assert (NULL == root);
      return MHD_NO; /* bad upload, could not even generate error */
    }
    if ( (GNUNET_NO == res) ||
         (NULL == root) )
    {
      GNUNET_assert (NULL == root);
      return MHD_YES; /* so far incomplete upload or parser error */
    }
  }

  {
    char d[ulen];
    unsigned int i;
    char *sp;

    /* Parse command-line arguments */
    /* make a copy of 'url' because 'strtok_r()' will modify */
    GNUNET_memcpy (d,
                   url,
                   ulen);
    i = 0;
    args[i++] = strtok_r (d, "/", &sp);
    while ( (NULL != args[i - 1]) &&
            (i <= rh->nargs + 1) )
      args[i++] = strtok_r (NULL, "/", &sp);
    /* make sure above loop ran nicely until completion, and also
       that there is no excess data in 'd' afterwards */
    if ( ( (rh->nargs_is_upper_bound) &&
           (i - 1 > rh->nargs) ) ||
         ( (! rh->nargs_is_upper_bound) &&
           (i - 1 != rh->nargs) ) )
    {
      char emsg[128 + 512];

      GNUNET_snprintf (emsg,
                       sizeof (emsg),
                       "Got %u+/%u segments for `%s' request (`%s')",
                       i - 1,
                       rh->nargs,
                       rh->url,
                       url);
      GNUNET_break_op (0);
      json_decref (root);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_GENERIC_WRONG_NUMBER_OF_SEGMENTS,
                                         emsg);
    }
    GNUNET_assert (NULL == args[i - 1]);

    /* Above logic ensures that 'root' is exactly non-NULL for POST operations,
       so we test for 'root' to decide which handler to invoke. */
    if (0 == strcasecmp (rh->method,
                         MHD_HTTP_METHOD_POST))
      ret = rh->handler.post (rc,
                              root,
                              args);
    else if (0 == strcasecmp (rh->method,
                              MHD_HTTP_METHOD_DELETE))
      ret = rh->handler.delete (rc,
                                args);
    else /* Only GET left */
      ret = rh->handler.get (rc,
                             args);
  }
  json_decref (root);
  return ret;
}


/**
 * Handle a "/seed" request.
 *
 * @param rc request context
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
 */
static MHD_RESULT
handler_seed (struct TEH_RequestContext *rc,
              const char *const args[])
{
#define SEED_SIZE 32
  char *body;
  MHD_RESULT ret;
  struct MHD_Response *resp;

  (void) args;
  body = malloc (SEED_SIZE); /* must use malloc(), because MHD will use free() */
  if (NULL == body)
    return MHD_NO;
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                              body,
                              SEED_SIZE);
  resp = MHD_create_response_from_buffer (SEED_SIZE,
                                          body,
                                          MHD_RESPMEM_MUST_FREE);
  TALER_MHD_add_global_headers (resp);
  ret = MHD_queue_response (rc->connection,
                            MHD_HTTP_OK,
                            resp);
  GNUNET_break (MHD_YES == ret);
  MHD_destroy_response (resp);
  return ret;
#undef SEED_SIZE
}


/**
 * Handle POST "/management/..." requests.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param args array of additional options
 * @return MHD result code
 */
static MHD_RESULT
handle_post_management (struct TEH_RequestContext *rc,
                        const json_t *root,
                        const char *const args[])
{
  if (NULL == args[0])
  {
    GNUNET_break_op (0);
    return r404 (rc->connection,
                 "/management");
  }
  if (0 == strcmp (args[0],
                   "auditors"))
  {
    struct TALER_AuditorPublicKeyP auditor_pub;

    if (NULL == args[1])
      return TEH_handler_management_auditors (rc->connection,
                                              root);
    if ( (NULL == args[1]) ||
         (NULL == args[2]) ||
         (0 != strcmp (args[2],
                       "disable")) ||
         (NULL != args[3]) )
      return r404 (rc->connection,
                   "/management/auditors/$AUDITOR_PUB/disable");
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[1],
                                       strlen (args[1]),
                                       &auditor_pub,
                                       sizeof (auditor_pub)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                         args[1]);
    }
    return TEH_handler_management_auditors_AP_disable (rc->connection,
                                                       &auditor_pub,
                                                       root);
  }
  if (0 == strcmp (args[0],
                   "denominations"))
  {
    struct TALER_DenominationHashP h_denom_pub;

    if ( (NULL == args[0]) ||
         (NULL == args[1]) ||
         (NULL == args[2]) ||
         (0 != strcmp (args[2],
                       "revoke")) ||
         (NULL != args[3]) )
      return r404 (rc->connection,
                   "/management/denominations/$HDP/revoke");
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[1],
                                       strlen (args[1]),
                                       &h_denom_pub,
                                       sizeof (h_denom_pub)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                         args[1]);
    }
    return TEH_handler_management_denominations_HDP_revoke (rc->connection,
                                                            &h_denom_pub,
                                                            root);
  }
  if (0 == strcmp (args[0],
                   "signkeys"))
  {
    struct TALER_ExchangePublicKeyP exchange_pub;

    if ( (NULL == args[0]) ||
         (NULL == args[1]) ||
         (NULL == args[2]) ||
         (0 != strcmp (args[2],
                       "revoke")) ||
         (NULL != args[3]) )
      return r404 (rc->connection,
                   "/management/signkeys/$HDP/revoke");
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[1],
                                       strlen (args[1]),
                                       &exchange_pub,
                                       sizeof (exchange_pub)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                         args[1]);
    }
    return TEH_handler_management_signkeys_EP_revoke (rc->connection,
                                                      &exchange_pub,
                                                      root);
  }
  /* FIXME-STYLE: all of the following can likely be nicely combined
     into an array-based dispatcher to deduplicate the logic... */
  if (0 == strcmp (args[0],
                   "keys"))
  {
    if (NULL != args[1])
    {
      GNUNET_break_op (0);
      return r404 (rc->connection,
                   "/management/keys/*");
    }
    return TEH_handler_management_post_keys (rc->connection,
                                             root);
  }
  if (0 == strcmp (args[0],
                   "wire"))
  {
    if (NULL == args[1])
      return TEH_handler_management_post_wire (rc->connection,
                                               root);
    if ( (0 != strcmp (args[1],
                       "disable")) ||
         (NULL != args[2]) )
    {
      GNUNET_break_op (0);
      return r404 (rc->connection,
                   "/management/wire/disable");
    }
    return TEH_handler_management_post_wire_disable (rc->connection,
                                                     root);
  }
  if (0 == strcmp (args[0],
                   "wire-fee"))
  {
    if (NULL != args[1])
    {
      GNUNET_break_op (0);
      return r404 (rc->connection,
                   "/management/wire-fee/*");
    }
    return TEH_handler_management_post_wire_fees (rc->connection,
                                                  root);
  }
  if (0 == strcmp (args[0],
                   "global-fee"))
  {
    if (NULL != args[1])
    {
      GNUNET_break_op (0);
      return r404 (rc->connection,
                   "/management/global-fee/*");
    }
    return TEH_handler_management_post_global_fees (rc->connection,
                                                    root);
  }
  if (0 == strcmp (args[0],
                   "extensions"))
  {
    if (NULL != args[1])
    {
      GNUNET_break_op (0);
      return r404 (rc->connection,
                   "/management/extensions/*");
    }
    return TEH_handler_management_post_extensions (rc->connection,
                                                   root);
  }
  if (0 == strcmp (args[0],
                   "drain"))
  {
    if (NULL != args[1])
    {
      GNUNET_break_op (0);
      return r404 (rc->connection,
                   "/management/drain/*");
    }
    return TEH_handler_management_post_drain (rc->connection,
                                              root);
  }
  if (0 == strcmp (args[0],
                   "aml-officers"))
  {
    if (NULL != args[1])
    {
      GNUNET_break_op (0);
      return r404 (rc->connection,
                   "/management/aml-officers/*");
    }
    return TEH_handler_management_aml_officers (rc->connection,
                                                root);
  }
  if (0 == strcmp (args[0],
                   "partners"))
  {
    if (NULL != args[1])
    {
      GNUNET_break_op (0);
      return r404 (rc->connection,
                   "/management/partners/*");
    }
    return TEH_handler_management_partners (rc->connection,
                                            root);
  }
  GNUNET_break_op (0);
  return r404 (rc->connection,
               "/management/*");
}


/**
 * Handle a GET "/management" request.
 *
 * @param rc request context
 * @param args array of additional options (must be [0] == "keys")
 * @return MHD result code
 */
static MHD_RESULT
handle_get_management (struct TEH_RequestContext *rc,
                       const char *const args[2])
{
  if ( (NULL != args[0]) &&
       (0 == strcmp (args[0],
                     "keys")) &&
       (NULL == args[1]) )
  {
    return TEH_keys_management_get_keys_handler (rc->rh,
                                                 rc->connection);
  }
  GNUNET_break_op (0);
  return r404 (rc->connection,
               "/management/*");
}


/**
 * Handle POST "/auditors/..." requests.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param args array of additional options
 * @return MHD result code
 */
static MHD_RESULT
handle_post_auditors (struct TEH_RequestContext *rc,
                      const json_t *root,
                      const char *const args[])
{
  struct TALER_AuditorPublicKeyP auditor_pub;
  struct TALER_DenominationHashP h_denom_pub;

  if ( (NULL == args[0]) ||
       (NULL == args[1]) ||
       (NULL != args[2]) )
  {
    GNUNET_break_op (0);
    return r404 (rc->connection,
                 "/auditors/$AUDITOR_PUB/$H_DENOM_PUB");
  }

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &auditor_pub,
                                     sizeof (auditor_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       args[0]);
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[1],
                                     strlen (args[1]),
                                     &h_denom_pub,
                                     sizeof (h_denom_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       args[1]);
  }
  return TEH_handler_auditors (rc->connection,
                               &auditor_pub,
                               &h_denom_pub,
                               root);
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
 * @param con_cls closure for request (a `struct TEH_RequestContext *`)
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
  static struct TEH_RequestHandler handlers[] = {
    /* /robots.txt: disallow everything */
    {
      .url = "robots.txt",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_static_response,
      .mime_type = "text/plain",
      .data = "User-agent: *\nDisallow: /\n",
      .response_code = MHD_HTTP_OK
    },
    /* Landing page, tell humans to go away. */
    {
      .url = "",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = TEH_handler_static_response,
      .mime_type = "text/plain",
      .data =
        "Hello, I'm the Taler exchange. This HTTP server is not for humans.\n",
      .response_code = MHD_HTTP_OK
    },
    /* AGPL licensing page, redirect to source. As per the AGPL-license, every
       deployment is required to offer the user a download of the source of
       the actual deployment. We make this easy by including a redirect to the
       source here. */
    {
      .url = "agpl",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_agpl_redirect
    },
    {
      .url = "seed",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &handler_seed
    },
    /* Configuration */
    {
      .url = "config",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_config
    },
    /* Performance metrics */
    {
      .url = "metrics",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_metrics
    },
    /* Terms of service */
    {
      .url = "terms",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_terms
    },
    /* Privacy policy */
    {
      .url = "privacy",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_privacy
    },
    /* Return key material and fundamental properties for this exchange */
    {
      .url = "keys",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_keys_get_handler,
    },
    /* Requests for wiring information */
    {
      .url = "wire",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_wire
    },
    {
      .url = "batch-deposit",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &TEH_handler_batch_deposit,
      .nargs = 0
    },
    /* request R, used in clause schnorr withdraw and refresh */
    {
      .url = "csr-melt",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &TEH_handler_csr_melt,
      .nargs = 0
    },
    {
      .url = "csr-withdraw",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &TEH_handler_csr_withdraw,
      .nargs = 0
    },
    /* Withdrawing coins / interaction with reserves */
    {
      .url = "reserves",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_reserves_get,
      .nargs = 1
    },
    {
      .url = "reserves",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &handle_post_reserves,
      .nargs = 2
    },
    {
      .url = "reserves-attest",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_reserves_get_attest,
      .nargs = 1
    },
    {
      .url = "reserves-attest",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &TEH_handler_reserves_attest,
      .nargs = 1
    },
    /* coins */
    {
      .url = "coins",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &handle_post_coins,
      .nargs = 2
    },
    {
      .url = "coins",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = TEH_handler_link,
      .nargs = 2,
    },
    /* refreshes/$RCH/reveal */
    {
      .url = "refreshes",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &TEH_handler_reveal,
      .nargs = 2
    },
    /* tracking transfers */
    {
      .url = "transfers",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_transfers_get,
      .nargs = 1
    },
    /* tracking deposits */
    {
      .url = "deposits",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_deposits_get,
      .nargs = 4
    },
    /* Operating on purses */
    {
      .url = "purses",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &handle_post_purses,
      .nargs = 2
    },
    /* Getting purse status */
    {
      .url = "purses",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_purses_get,
      .nargs = 2
    },
    /* Deleting purse */
    {
      .url = "purses",
      .method = MHD_HTTP_METHOD_DELETE,
      .handler.delete = &TEH_handler_purses_delete,
      .nargs = 1
    },
    /* Getting contracts */
    {
      .url = "contracts",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_contracts_get,
      .nargs = 1
    },
    /* KYC endpoints */
    {
      .url = "kyc-check",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_kyc_check,
      .nargs = 3
    },
    {
      .url = "kyc-proof",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_kyc_proof,
      .nargs = 1
    },
    {
      .url = "kyc-wallet",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &TEH_handler_kyc_wallet,
      .nargs = 0
    },
    /* POST management endpoints */
    {
      .url = "management",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &handle_post_management,
      .nargs = 4,
      .nargs_is_upper_bound = true
    },
    /* GET management endpoints (we only really have "/management/keys") */
    {
      .url = "management",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &handle_get_management,
      .nargs = 1
    },
    /* auditor endpoints */
    {
      .url = "auditors",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &handle_post_auditors,
      .nargs = 4,
      .nargs_is_upper_bound = true
    },
    /* AML endpoints */
    {
      .url = "aml",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &handle_get_aml,
      .nargs = 4,
      .nargs_is_upper_bound = true
    },
    {
      .url = "aml",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &handle_post_aml,
      .nargs = 2
    },


    /* mark end of list */
    {
      .url = NULL
    }
  };
  struct TEH_RequestContext *rc = *con_cls;
  struct GNUNET_AsyncScopeSave old_scope;
  const char *correlation_id = NULL;

  (void) cls;
  (void) version;
  if (NULL == rc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Handling new request\n");

    /* We're in a new async scope! */
    rc = *con_cls = GNUNET_new (struct TEH_RequestContext);
    rc->start_time = GNUNET_TIME_absolute_get ();
    GNUNET_async_scope_fresh (&rc->async_scope_id);
    TEH_check_invariants ();
    rc->url = url;
    rc->connection = connection;
    /* We only read the correlation ID on the first callback for every client */
    correlation_id = MHD_lookup_connection_value (connection,
                                                  MHD_HEADER_KIND,
                                                  "Taler-Correlation-Id");
    if ( (NULL != correlation_id) &&
         (GNUNET_YES !=
          GNUNET_CURL_is_valid_scope_id (correlation_id)) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "illegal incoming correlation ID\n");
      correlation_id = NULL;
    }

    /* Check if upload is in bounds */
    if (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_POST))
    {
      TALER_MHD_check_content_length (connection,
                                      TALER_MHD_REQUEST_BUFFER_MAX);
    }
  }

  GNUNET_async_scope_enter (&rc->async_scope_id,
                            &old_scope);
  TEH_check_invariants ();
  if (NULL != correlation_id)
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Handling request (%s) for URL '%s', correlation_id=%s\n",
                method,
                url,
                correlation_id);
  else
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Handling request (%s) for URL '%s'\n",
                method,
                url);
  /* on repeated requests, check our cache first */
  if (NULL != rc->rh)
  {
    MHD_RESULT ret;
    const char *start;

    if ('\0' == url[0])
      /* strange, should start with '/', treat as just "/" */
      url = "/";
    start = strchr (url + 1, '/');
    if (NULL == start)
      start = "";
    ret = proceed_with_handler (rc,
                                start,
                                upload_data,
                                upload_data_size);
    GNUNET_async_scope_restore (&old_scope);
    return ret;
  }

  if ( (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_OPTIONS)) &&
       (0 == strcmp ("*",
                     url)) )
    return TALER_MHD_reply_cors_preflight (connection);

  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_HEAD))
    method = MHD_HTTP_METHOD_GET; /* treat HEAD as GET here, MHD will do the rest */

  /* parse first part of URL */
  {
    bool found = false;
    size_t tok_size;
    const char *tok;
    const char *rest;

    if ('\0' == url[0])
      /* strange, should start with '/', treat as just "/" */
      url = "/";
    tok = url + 1;
    rest = strchr (tok, '/');
    if (NULL == rest)
    {
      tok_size = strlen (tok);
    }
    else
    {
      tok_size = rest - tok;
      rest++; /* skip over '/' */
    }
    for (unsigned int i = 0; NULL != handlers[i].url; i++)
    {
      struct TEH_RequestHandler *rh = &handlers[i];

      if ( (0 != strncmp (tok,
                          rh->url,
                          tok_size)) ||
           (tok_size != strlen (rh->url) ) )
        continue;
      found = true;
      /* The URL is a match!  What we now do depends on the method. */
      if (0 == strcasecmp (method,
                           MHD_HTTP_METHOD_OPTIONS))
      {
        GNUNET_async_scope_restore (&old_scope);
        return TALER_MHD_reply_cors_preflight (connection);
      }
      GNUNET_assert (NULL != rh->method);
      if (0 == strcasecmp (method,
                           rh->method))
      {
        MHD_RESULT ret;

        /* cache to avoid the loop next time */
        rc->rh = rh;
        /* run handler */
        ret = proceed_with_handler (rc,
                                    url + tok_size + 1,
                                    upload_data,
                                    upload_data_size);
        GNUNET_async_scope_restore (&old_scope);
        return ret;
      }
    }

    if (found)
    {
      /* we found a matching address, but the method is wrong */
      struct MHD_Response *reply;
      MHD_RESULT ret;
      char *allowed = NULL;

      GNUNET_break_op (0);
      for (unsigned int i = 0; NULL != handlers[i].url; i++)
      {
        struct TEH_RequestHandler *rh = &handlers[i];

        if ( (0 != strncmp (tok,
                            rh->url,
                            tok_size)) ||
             (tok_size != strlen (rh->url) ) )
          continue;
        if (NULL == allowed)
        {
          allowed = GNUNET_strdup (rh->method);
        }
        else
        {
          char *tmp;

          GNUNET_asprintf (&tmp,
                           "%s, %s",
                           allowed,
                           rh->method);
          GNUNET_free (allowed);
          allowed = tmp;
        }
        if (0 == strcasecmp (rh->method,
                             MHD_HTTP_METHOD_GET))
        {
          char *tmp;

          GNUNET_asprintf (&tmp,
                           "%s, %s",
                           allowed,
                           MHD_HTTP_METHOD_HEAD);
          GNUNET_free (allowed);
          allowed = tmp;
        }
      }
      reply = TALER_MHD_make_error (TALER_EC_GENERIC_METHOD_INVALID,
                                    method);
      GNUNET_break (MHD_YES ==
                    MHD_add_response_header (reply,
                                             MHD_HTTP_HEADER_ALLOW,
                                             allowed));
      GNUNET_free (allowed);
      ret = MHD_queue_response (connection,
                                MHD_HTTP_METHOD_NOT_ALLOWED,
                                reply);
      MHD_destroy_response (reply);
      return ret;
    }
  }

  /* No handler matches, generate not found */
  {
    MHD_RESULT ret;

    ret = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_NOT_FOUND,
                                      TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                      url);
    GNUNET_async_scope_restore (&old_scope);
    return ret;
  }
}


/**
 * Load configuration parameters for the exchange
 * server into the corresponding global variables.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
exchange_serve_process_config (void)
{
  if (GNUNET_OK !=
      TALER_KYCLOGIC_kyc_init (TEH_cfg))
  {
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (TEH_cfg,
                                             "exchange",
                                             "MAX_REQUESTS",
                                             &req_max))
  {
    req_max = ULLONG_MAX;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (TEH_cfg,
                                           "exchangedb",
                                           "IDLE_RESERVE_EXPIRATION_TIME",
                                           &TEH_reserve_closing_delay))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "IDLE_RESERVE_EXPIRATION_TIME");
    /* use default */
    TEH_reserve_closing_delay
      = GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_WEEKS,
                                       4);
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (TEH_cfg,
                                           "exchange",
                                           "MAX_KEYS_CACHING",
                                           &TEH_max_keys_caching))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "MAX_KEYS_CACHING",
                               "valid relative time expected");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (TEH_cfg,
                                             "exchange",
                                             "KYC_AML_TRIGGER",
                                             &TEH_kyc_aml_trigger))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "KYC_AML_TRIGGER");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_currency (TEH_cfg,
                                 &TEH_currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (TEH_cfg,
                               "exchange",
                               "AML_THRESHOLD",
                               &TEH_aml_threshold))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Need amount in section `exchange' under `AML_THRESHOLD'\n");
    return GNUNET_SYSERR;
  }
  if (0 != strcmp (TEH_currency,
                   TEH_aml_threshold.currency))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Amount in section `exchange' under `AML_THRESHOLD' uses the wrong currency!\n");
    return GNUNET_SYSERR;
  }
  TEH_enable_tipping
    = GNUNET_CONFIGURATION_get_value_yesno (
        TEH_cfg,
        "exchange",
        "ENABLE_TIPPING");
  if (GNUNET_SYSERR == TEH_enable_tipping)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Need YES or NO in section `exchange' under `ENABLE_TIPPING'\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (TEH_cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &TEH_base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    return GNUNET_SYSERR;
  }
  if (! TALER_url_valid_charset (TEH_base_url))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL",
                               "invalid URL");
    return GNUNET_SYSERR;
  }

  {
    char *master_public_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (TEH_cfg,
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
        GNUNET_CRYPTO_eddsa_public_key_from_string (master_public_key_str,
                                                    strlen (
                                                      master_public_key_str),
                                                    &TEH_master_public_key.
                                                    eddsa_pub))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "MASTER_PUBLIC_KEY",
                                 "invalid base32 encoding for a master public key");
      GNUNET_free (master_public_key_str);
      return GNUNET_SYSERR;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Launching exchange with public key `%s'...\n",
                master_public_key_str);
    GNUNET_free (master_public_key_str);
  }

  {
    char *attr_enc_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (TEH_cfg,
                                               "exchange",
                                               "ATTRIBUTE_ENCRYPTION_KEY",
                                               &attr_enc_key_str))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "ATTRIBUTE_ENCRYPTION_KEY");
      return GNUNET_SYSERR;
    }
    GNUNET_CRYPTO_hash (attr_enc_key_str,
                        strlen (attr_enc_key_str),
                        &TEH_attribute_key.hash);
    GNUNET_free (attr_enc_key_str);
  }

  for (unsigned int i = 0; i<MAX_DB_RETRIES; i++)
  {
    TEH_plugin = TALER_EXCHANGEDB_plugin_load (TEH_cfg);
    if (NULL != TEH_plugin)
      break;
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to connect to DB, will try again %u times\n",
                MAX_DB_RETRIES - i);
    sleep (1);
  }
  if (NULL == TEH_plugin)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem. Giving up.\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Called when the main thread exits, writes out performance
 * stats if requested.
 */
static void
write_stats (void)
{
  struct GNUNET_DISK_FileHandle *fh;
  pid_t pid = getpid ();
  char *benchmark_dir;
  char *s;
  struct rusage usage;

  benchmark_dir = getenv ("GNUNET_BENCHMARK_DIR");
  if (NULL == benchmark_dir)
    return;
  GNUNET_asprintf (&s,
                   "%s/taler-exchange-%llu.txt",
                   benchmark_dir,
                   (unsigned long long) pid);
  fh = GNUNET_DISK_file_open (s,
                              (GNUNET_DISK_OPEN_WRITE
                               | GNUNET_DISK_OPEN_TRUNCATE
                               | GNUNET_DISK_OPEN_CREATE),
                              (GNUNET_DISK_PERM_USER_READ
                               | GNUNET_DISK_PERM_USER_WRITE));
  GNUNET_free (s);
  if (NULL == fh)
    return; /* permission denied? */

  /* Collect stats, summed up for all threads */
  GNUNET_assert (0 ==
                 getrusage (RUSAGE_SELF,
                            &usage));
  GNUNET_asprintf (&s,
                   "time_exchange sys %llu user %llu\n",
                   (unsigned long long) (usage.ru_stime.tv_sec * 1000 * 1000
                                         + usage.ru_stime.tv_usec),
                   (unsigned long long) (usage.ru_utime.tv_sec * 1000 * 1000
                                         + usage.ru_utime.tv_usec));
  GNUNET_assert (GNUNET_SYSERR !=
                 GNUNET_DISK_file_write_blocking (fh,
                                                  s,
                                                  strlen (s)));
  GNUNET_free (s);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_DISK_file_close (fh));
}


/* Developer logic for supporting the `-f' option. */
#if HAVE_DEVELOPER

/**
 * Option `-f' (specifies an input file to give to the HTTP server).
 */
static char *input_filename;


/**
 * Run 'nc' or 'ncat' as a fake HTTP client using #input_filename
 * as the input for the request.  If launching the client worked,
 * run the #TEH_KS_loop() event loop as usual.
 *
 * @return child pid
 */
static pid_t
run_fake_client (void)
{
  pid_t cld;
  char ports[6];
  int fd;

  if (0 == strcmp (input_filename,
                   "-"))
    fd = STDIN_FILENO;
  else
    fd = open (input_filename,
               O_RDONLY);
  if (-1 == fd)
  {
    fprintf (stderr,
             "Failed to open `%s': %s\n",
             input_filename,
             strerror (errno));
    return -1;
  }
  /* Fake HTTP client request with #input_filename as input.
     We do this using the nc tool. */
  GNUNET_snprintf (ports,
                   sizeof (ports),
                   "%u",
                   serve_port);
  if (0 == (cld = fork ()))
  {
    GNUNET_break (0 == close (0));
    GNUNET_break (0 == dup2 (fd, 0));
    GNUNET_break (0 == close (fd));
    if ( (0 != execlp ("nc",
                       "nc",
                       "localhost",
                       ports,
                       "-w", "30",
                       NULL)) &&
         (0 != execlp ("ncat",
                       "ncat",
                       "localhost",
                       ports,
                       "-i", "30",
                       NULL)) )
    {
      fprintf (stderr,
               "Failed to run both `nc' and `ncat': %s\n",
               strerror (errno));
    }
    _exit (1);
  }
  /* parent process */
  if (0 != strcmp (input_filename,
                   "-"))
    GNUNET_break (0 == close (fd));
  return cld;
}


/**
 * Run the exchange to serve a single request only, without threads.
 *
 * @return #GNUNET_OK on success
 */
static void
run_single_request (void)
{
  pid_t xfork;

  xfork = fork ();
  if (-1 == xfork)
  {
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (0 == xfork)
  {
    pid_t cld;

    cld = run_fake_client ();
    if (-1 == cld)
      _exit (EXIT_FAILURE);
    _exit (EXIT_SUCCESS);
  }

  {
    int status;

    if (xfork != waitpid (xfork,
                          &status,
                          0))
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Waiting for `nc' child failed: %s\n",
                  strerror (errno));
  }
}


/* end of HAVE_DEVELOPER */
#endif


/**
 * Signature of the callback used by MHD to notify the application
 * about completed connections.  If we are running in test-mode with
 * an input_filename, this function is used to terminate the HTTPD
 * after the first request has been processed.
 *
 * @param cls client-defined closure, NULL
 * @param connection connection handle (ignored)
 * @param socket_context socket-specific pointer (ignored)
 * @param toe reason for connection notification
 */
static void
connection_done (void *cls,
                 struct MHD_Connection *connection,
                 void **socket_context,
                 enum MHD_ConnectionNotificationCode toe)
{
  (void) cls;
  (void) connection;
  (void) socket_context;

  switch (toe)
  {
  case MHD_CONNECTION_NOTIFY_STARTED:
    active_connections++;
    break;
  case MHD_CONNECTION_NOTIFY_CLOSED:
    active_connections--;
    if (TEH_suicide &&
        (0 == active_connections) )
      GNUNET_SCHEDULER_shutdown ();
    break;
  }
#if HAVE_DEVELOPER
  /* We only act if the connection is closed. */
  if (MHD_CONNECTION_NOTIFY_CLOSED != toe)
    return;
  if (NULL != input_filename)
    GNUNET_SCHEDULER_shutdown ();
#endif
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
  TEH_resume_keys_requests (true);
  TEH_deposits_get_cleanup ();
  TEH_reserves_get_cleanup ();
  TEH_purses_get_cleanup ();
  TEH_kyc_check_cleanup ();
  TEH_kyc_proof_cleanup ();
  TALER_KYCLOGIC_kyc_done ();
  if (NULL != mhd)
  {
    MHD_stop_daemon (mhd);
    mhd = NULL;
  }
  TEH_wire_done ();
  TEH_extensions_done ();
  TEH_keys_finished ();
  if (NULL != TEH_plugin)
  {
    TALER_EXCHANGEDB_plugin_unload (TEH_plugin);
    TEH_plugin = NULL;
  }
  if (NULL != TEH_curl_ctx)
  {
    GNUNET_CURL_fini (TEH_curl_ctx);
    TEH_curl_ctx = NULL;
  }
  if (NULL != exchange_curl_rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (exchange_curl_rc);
    exchange_curl_rc = NULL;
  }
  TALER_TEMPLATING_done ();
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
  (void ) cfgfile;
  go = TALER_MHD_GO_NONE;
  if (connection_close)
    go |= TALER_MHD_GO_FORCE_CONNECTION_CLOSE;
  TALER_MHD_setup (go);
  TEH_cfg = config;

  if (GNUNET_OK !=
      exchange_serve_process_config ())
  {
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK !=
      TALER_TEMPLATING_init ("exchange"))
  {
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_SYSERR ==
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK !=
      TEH_extensions_init ())
  {
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK !=
      TEH_keys_init ())
  {
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK !=
      TEH_wire_init ())
  {
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  TEH_load_terms (TEH_cfg);
  TEH_curl_ctx
    = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                        &exchange_curl_rc);
  if (NULL == TEH_curl_ctx)
  {
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  exchange_curl_rc = GNUNET_CURL_gnunet_rc_create (TEH_curl_ctx);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  fh = TALER_MHD_bind (TEH_cfg,
                       "exchange",
                       &serve_port);
  if ( (0 == serve_port) &&
       (-1 == fh) )
  {
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
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
                          MHD_OPTION_NOTIFY_CONNECTION,
                          &connection_done,
                          NULL,
                          MHD_OPTION_CONNECTION_TIMEOUT,
                          connection_timeout,
                          (0 == allow_address_reuse)
                          ? MHD_OPTION_END
                          : MHD_OPTION_LISTENING_ADDRESS_REUSE,
                          (unsigned int) allow_address_reuse,
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
  atexit (&write_stats);

#if HAVE_DEVELOPER
  if (NULL != input_filename)
    run_single_request ();
#endif
}


/**
 * The main function of the taler-exchange-httpd server ("the exchange").
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
    GNUNET_GETOPT_option_flag ('a',
                               "allow-timetravel",
                               "allow clients to request /keys for arbitrary timestamps (for testing and development only)",
                               &TEH_allow_keys_timetravel),
    GNUNET_GETOPT_option_flag ('C',
                               "connection-close",
                               "force HTTP connections to be closed after each request",
                               &connection_close),
    GNUNET_GETOPT_option_flag ('I',
                               "check-invariants",
                               "enable expensive invariant checks",
                               &TEH_check_invariants_flag),
    GNUNET_GETOPT_option_flag ('r',
                               "allow-reuse-address",
                               "allow multiple HTTPDs to listen to the same port",
                               &allow_address_reuse),
    GNUNET_GETOPT_option_uint ('t',
                               "timeout",
                               "SECONDS",
                               "after how long do connections timeout by default (in seconds)",
                               &connection_timeout),
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
#if HAVE_DEVELOPER
    GNUNET_GETOPT_option_filename ('f',
                                   "file-input",
                                   "FILENAME",
                                   "run in test-mode using FILENAME as the HTTP request to process, use '-' to read from stdin",
                                   &input_filename),
#endif
    GNUNET_GETOPT_option_help (
      "HTTP server providing a RESTful API to access a Taler exchange"),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (argc, argv,
                            "taler-exchange-httpd",
                            "Taler exchange HTTP service",
                            options,
                            &run, NULL);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-httpd.c */
