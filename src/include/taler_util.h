/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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

/**
 * Version of the Taler API, in hex.
 * Thus 0.8.4-1 = 0x00080401.
 */
#define TALER_API_VERSION 0x00080401

/**
 * Stringify operator.
 *
 * @param a some expression to stringify. Must NOT be a macro.
 * @return same expression as a constant string.
 */
#define TALER_S(a) #a

/**
 * Stringify operator.
 *
 * @param a some expression to stringify. Can be a macro.
 * @return macro-expanded expression as a constant string.
 */
#define TALER_QUOTE(a) TALER_S (a)


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
#define TALER_B2S(obj) TALER_b2s ((obj), sizeof (*(obj)))


/**
 * Obtain denomination amount from configuration file.
 *
 * @param cfg configuration to extract data from
 * @param section section of the configuration to access
 * @param option option of the configuration to access
 * @param[out] denom set to the amount found in configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
enum GNUNET_GenericReturnValue
TALER_config_get_amount (const struct GNUNET_CONFIGURATION_Handle *cfg,
                         const char *section,
                         const char *option,
                         struct TALER_Amount *denom);


/**
 * Obtain denomination fee structure of a
 * denomination from configuration file.  All
 * fee options must start with "fee_" and have
 * names typical for the respective fees.
 *
 * @param cfg configuration to extract data from
 * @param currency expected currency
 * @param section section of the configuration to access
 * @param[out] fees set to the denomination fees
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
enum GNUNET_GenericReturnValue
TALER_config_get_denom_fees (const struct GNUNET_CONFIGURATION_Handle *cfg,
                             const char *currency,
                             const char *section,
                             struct TALER_DenomFeeSet *fees);


/**
 * Check that all denominations in @a fees use
 * @a currency
 *
 * @param currency desired currency
 * @param fees fee set to check
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_denom_fee_check_currency (
  const char *currency,
  const struct TALER_DenomFeeSet *fees);


/**
 * Load our currency from the @a cfg (in section [taler]
 * the option "CURRENCY").
 *
 * @param cfg configuration to use
 * @param[out] currency where to write the result
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
enum GNUNET_GenericReturnValue
TALER_config_get_currency (const struct GNUNET_CONFIGURATION_Handle *cfg,
                           char **currency);


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
 * Initialize libtalerutil.
 */
void
TALER_OS_init (void);


/**
 * URL-encode a string according to rfc3986.
 *
 * @param s string to encode
 * @returns the urlencoded string, the caller must free it with GNUNET_free()
 */
char *
TALER_urlencode (const char *s);


/**
 * Test if all characters in @a url are valid for
 * a URL.
 *
 * @param url URL to sanity-check
 * @return true if @a url only contains valid characters
 */
bool
TALER_url_valid_charset (const char *url);


/**
 * Check if @a lang matches the @a language_pattern, and if so with
 * which preference.
 * See also: https://tools.ietf.org/html/rfc7231#section-5.3.1
 *
 * @param language_pattern a language preferences string
 *        like "fr-CH, fr;q=0.9, en;q=0.8, *;q=0.1"
 * @param lang the 2-digit language to match
 * @return q-weight given for @a lang in @a language_pattern, 1.0 if no weights are given;
 *         0 if @a lang is not in @a language_pattern
 */
double
TALER_language_matches (const char *language_pattern,
                        const char *lang);


/**
 * Find out if an MHD connection is using HTTPS (either
 * directly or via proxy).
 *
 * @param connection MHD connection
 * @returns #GNUNET_YES if the MHD connection is using https,
 *          #GNUNET_NO if the MHD connection is using http,
 *          #GNUNET_SYSERR if the connection type couldn't be determined
 */
enum GNUNET_GenericReturnValue
TALER_mhd_is_https (struct MHD_Connection *connection);


/**
 * Make an absolute URL with query parameters.
 *
 * If a 'value' is given as NULL, both the key and the value are skipped. Note
 * that a NULL value does not terminate the list, only a NULL key signals the
 * end of the list of arguments.
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
 * If a 'value' is given as NULL, both the key and the value are skipped. Note
 * that a NULL value does not terminate the list, only a NULL key signals the
 * end of the list of arguments.
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
 * If a 'value' is given as NULL, both the key and the value are skipped. Note
 * that a NULL value does not terminate the list, only a NULL key signals the
 * end of the list of arguments.
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
 * @param connection the connection to get the URL for
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
 * Obtain the payment method from a @a payto_uri
 *
 * @param payto_uri the URL to parse
 * @return NULL on error (malformed @a payto_uri)
 */
char *
TALER_payto_get_method (const char *payto_uri);


/**
 * Construct a payto://-URI from a Taler @a reserve_pub at
 * @a exchange_base_url
 *
 * @param exchange_base_url the URL of the exchange
 * @param reserve_pub public key of the reserve
 * @return payto:// URI encoding the reserve's address
 */
char *
TALER_payto_from_reserve (const char *exchange_base_url,
                          const struct TALER_ReservePublicKeyP *reserve_pub);


/**
 * Obtain the account name from a payto URL.
 *
 * @param payto an x-taler-bank payto URL
 * @return only the account name from the @a payto URL, NULL if not an x-taler-bank
 *   payto URL
 */
char *
TALER_xtalerbank_account_from_payto (const char *payto);


/**
 * Obtain the receiver name from a payto URL.
 *
 * @param payto an x-taler-bank payto URL
 * @return only the receiver name from the @a payto URL, NULL if not an x-taler-bank payto URL
 */
char *
TALER_payto_get_receiver_name (const char *payto);


/**
 * Extract the subject value from the URI parameters.
 *
 * @param payto_uri the URL to parse
 * @return NULL if the subject parameter is not found.
 *         The caller should free the returned value.
 */
char *
TALER_payto_get_subject (const char *payto_uri);


/**
 * Check that a payto:// URI is well-formed.
 *
 * @param payto_uri the URL to check
 * @return NULL on success, otherwise an error
 *         message to be freed by the caller!
 */
char *
TALER_payto_validate (const char *payto_uri);


/**
 * Create payto://-URI for a given exchange base URL
 * and a @a reserve_pub.
 *
 * @param exchange_url the base URL of the exchange
 * @param reserve_pub the public key of the reserve
 * @return payto://-URI for the reserve (without receiver-name!)
 */
char *
TALER_reserve_make_payto (const char *exchange_url,
                          const struct TALER_ReservePublicKeyP *reserve_pub);


/**
 * Check that an IBAN number is well-formed.
 *
 * Validates given IBAN according to the European Banking Standards.  See:
 * http://www.europeanpaymentscouncil.eu/documents/ECBS%20IBAN%20standard%20EBS204_V3.2.pdf
 *
 * @param iban the IBAN to check
 * @return NULL on success, otherwise an error
 *         message to be freed by the caller!
 */
char *
TALER_iban_validate (const char *iban);


/**
 * Possible values for a binary filter.
 */
enum TALER_EXCHANGE_YesNoAll
{
  /**
   * If condition is yes.
   */
  TALER_EXCHANGE_YNA_YES = 1,

  /**
  * If condition is no.
  */
  TALER_EXCHANGE_YNA_NO = 2,

  /**
   * Condition disabled.
   */
  TALER_EXCHANGE_YNA_ALL = 3
};


/**
 * Convert query argument to @a yna value.
 *
 * @param connection connection to take query argument from
 * @param arg argument to try for
 * @param default_val value to assign if the argument is not present
 * @param[out] yna value to set
 * @return true on success, false if the parameter was malformed
 */
bool
TALER_arg_to_yna (struct MHD_Connection *connection,
                  const char *arg,
                  enum TALER_EXCHANGE_YesNoAll default_val,
                  enum TALER_EXCHANGE_YesNoAll *yna);


/**
 * Convert YNA value to a string.
 *
 * @param yna value to convert
 * @return string representation ("yes"/"no"/"all").
 */
const char *
TALER_yna_to_string (enum TALER_EXCHANGE_YesNoAll yna);


#ifdef __APPLE__
/**
 * Returns the first occurrence of `c` in `s`, or returns the null-byte
 * terminating the string if it does not occur.
 *
 * @param s the string to search in
 * @param c the character to search for
 * @return char* the first occurrence of `c` in `s`
 */
char *strchrnul (const char *s, int c);

#endif


#endif
