/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

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
 * @file include/taler_util.h
 * @brief Interface for common utility functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#ifndef TALER_UTIL_H
#define TALER_UTIL_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler_amount_lib.h"
#include "taler_crypto_lib.h"


/* Define logging functions */
#define TALER_LOG_DEBUG(...)                                  \
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG, __VA_ARGS__)

#define TALER_LOG_INFO(...)                                  \
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, __VA_ARGS__)

#define TALER_LOG_WARNING(...)                                \
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING, __VA_ARGS__)

#define TALER_LOG_ERROR(...)                                  \
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR, __VA_ARGS__)


/**
 * Tests a given as assertion and if failed prints it as a warning with the
 * given reason
 *
 * @param EXP the expression to test as assertion
 * @param reason string to print as warning
 */
#define TALER_assert_as(EXP, reason)                           \
  do {                                                          \
    if (EXP) break;                                             \
    TALER_LOG_ERROR ("%s at %s:%d\n", reason, __FILE__, __LINE__);       \
    abort ();                                                    \
  } while (0)


/**
 * Log an error message at log-level 'level' that indicates
 * a failure of the command 'cmd' with the message given
 * by gcry_strerror(rc).
 */
#define TALER_LOG_GCRY_ERROR(cmd, rc) do { TALER_LOG_ERROR ( \
                                             "`%s' failed at %s:%d with error: %s\n", \
                                             cmd, __FILE__, __LINE__, \
                                             gcry_strerror (rc)); } while (0)


#define TALER_gcry_ok(cmd) \
  do {int rc; rc = cmd; if (! rc) break; \
      TALER_LOG_ERROR ("A Gcrypt call failed at %s:%d with error: %s\n", \
                       __FILE__, \
                       __LINE__, gcry_strerror (rc)); abort (); } while (0)


/**
 * Initialize Gcrypt library.
 */
void
TALER_gcrypt_init (void);


/**
 * Convert a buffer to an 8-character string
 * representative of the contents. This is used
 * for logging binary data when debugging.
 *
 * @param buf buffer to log
 * @param buf_size number of bytes in @a buf
 * @return text representation of buf, valid until next
 *         call to this function
 */
const char *
TALER_b2s (const void *buf,
           size_t buf_size);


/**
 * Convert a fixed-sized object to a string using
 * #TALER_b2s().
 *
 * @param obj address of object to convert
 * @return string representing the binary obj buffer
 */
#define TALER_B2S(obj) TALER_b2s (obj, sizeof (*obj))


/**
 * Obtain denomination amount from configuration file.
 *
 * @param section section of the configuration to access
 * @param option option of the configuration to access
 * @param[out] denom set to the amount found in configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_config_get_denom (const struct GNUNET_CONFIGURATION_Handle *cfg,
                        const char *section,
                        const char *option,
                        struct TALER_Amount *denom);


/**
 * Allow user to specify an amount on the command line.
 *
 * @param shortName short name of the option
 * @param name long name of the option
 * @param argumentHelp help text for the option argument
 * @param description long help text for the option
 * @param[out] amount set to the amount specified at the command line
 */
struct GNUNET_GETOPT_CommandLineOption
TALER_getopt_get_amount (char shortName,
                         const char *name,
                         const char *argumentHelp,
                         const char *description,
                         struct TALER_Amount *amount);


/**
 * Return default project data used by Taler.
 */
const struct GNUNET_OS_ProjectData *
TALER_project_data_default (void);


/**
 * URL-encode a string according to rfc3986.
 *
 * @param s string to encode
 * @returns the urlencoded string, the caller must free it with GNUNET_free
 */
char *
TALER_urlencode (const char *s);


/**
 * Find out if an MHD connection is using HTTPS (either
 * directly or via proxy).
 *
 * @param connection MHD connection
 * @returns GNUNET_YES if the MHD connection is using https,
 *          GNUNET_NO if the MHD connection is using http,
 *          GNUNET_SYSERR if the connection type couldn't be determined
 */
int
TALER_mhd_is_https (struct MHD_Connection *connection);


/**
 * Make an absolute URL with query parameters.
 *
 * @param base_url absolute base URL to use
 * @param path path of the url
 * @param ... NULL-terminated key-value pairs (char *) for query parameters,
 *        only the value will be url-encoded
 * @returns the URL, must be freed with #GNUNET_free
 */
char *
TALER_url_join (const char *base_url,
                const char *path,
                ...);


/**
 * Make an absolute URL for the given parameters.
 *
 * @param proto protocol for the URL (typically https)
 * @param host hostname for the URL
 * @param prefix prefix for the URL
 * @param path path for the URL
 * @param ... NULL-terminated key-value pairs (char *) for query parameters,
 *        the value will be url-encoded
 * @returns the URL, must be freed with #GNUNET_free
 */
char *
TALER_url_absolute_raw (const char *proto,
                        const char *host,
                        const char *prefix,
                        const char *path,
                        ...);


/**
 * Make an absolute URL for the given parameters.
 *
 * @param proto protocol for the URL (typically https)
 * @param host hostname for the URL
 * @param prefix prefix for the URL
 * @param path path for the URL
 * @param args NULL-terminated key-value pairs (char *) for query parameters,
 *        the value will be url-encoded
 * @returns the URL, must be freed with #GNUNET_free
 */
char *
TALER_url_absolute_raw_va (const char *proto,
                           const char *host,
                           const char *prefix,
                           const char *path,
                           va_list args);


/**
 * Make an absolute URL for a given MHD connection.
 *
 * @param path path of the url
 * @param ... NULL-terminated key-value pairs (char *) for query parameters,
 *        the value will be url-encoded
 * @returns the URL, must be freed with #GNUNET_free
 */
char *
TALER_url_absolute_mhd (struct MHD_Connection *connection,
                        const char *path,
                        ...);


/**
 * Obtain the payment method from a @a payto_url
 *
 * @param payto_url the URL to parse
 * @return NULL on error (malformed @a payto_url)
 */
char *
TALER_payto_get_method (const char *payto_url);


/**
 * Create an x-taler-bank payto:// URL from a @a bank_url
 * and an @a account_name.
 *
 * @param bank_url the bank URL
 * @param account_name the account name
 * @return payto:// URL
 */
char *
TALER_payto_xtalerbank_make (const char *bank_url,
                             const char *account_name);


/**
 * Create an x-taler-bank payto:// URL from an @a account_url.
 *
 * @param account_url the bank URL
 * @param account_name the account name
 * @return payto:// URL
 */
char *
TALER_payto_xtalerbank_make2 (const char *account_url);


/**
 * Given an x-taler-bank payto:// URL, compute
 * the HTTP(S) base URL of the account.
 *
 * @param payto the payto URL
 * @return bank URL of the account, NULL if not x-taler-bak payto URL
 */
char *
TALER_xtalerbank_base_url_from_payto (const char *payto);


/**
 * Given an x-taler-bank payto:// URL, compute
 * the HTTP(S) base URL of the account.
 *
 * @param payto the payto URL
 * @return bank URL of the account, NULL if not x-taler-bak payto URL
 */
char *
TALER_xtalerbank_account_url_from_payto (const char *payto);


/**
 * Obtain the account name from a payto URL.
 *
 * @param payto an x-taler-bank payto URL
 * @return only the account name from the @a payto URL, NULL if not an x-taler-bank
 *   payto URL
 */
char *
TALER_xtalerbank_account_from_payto (const char *payto);


#endif
