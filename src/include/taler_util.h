/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
 *        This library is not thread-safe, all APIs must only be used from a single thread.
 *        This library calls abort() if it runs out of memory. Be aware of these limitations.
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#ifndef TALER_UTIL_H
#define TALER_UTIL_H

#include <gnunet/gnunet_common.h>
#define __TALER_UTIL_LIB_H_INSIDE__

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler_amount_lib.h"
#include "taler_crypto_lib.h"

#if MHD_VERSION < 0x00097701
#define MHD_create_response_from_buffer_static(s, b)            \
        MHD_create_response_from_buffer (s,                     \
                                         (const char *) b,      \
                                         MHD_RESPMEM_PERSISTENT)
#endif

/**
 * Version of the Taler API, in hex.
 * Thus 0.8.4-1 = 0x00080401.
 */
#define TALER_API_VERSION 0x000D0000

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
 * HTTP header with an AML officer signature to approve the inquiry.
 * Used only in GET Requests.
 */
#define TALER_AML_OFFICER_SIGNATURE_HEADER "Taler-AML-Officer-Signature"

/**
 * Header with signature for reserve history requests.
 */
#define TALER_RESERVE_HISTORY_SIGNATURE_HEADER "Taler-Reserve-History-Signature"

/**
 * Header with signature for coin history requests.
 */
#define TALER_COIN_HISTORY_SIGNATURE_HEADER "Taler-Coin-History-Signature"

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
                             __LINE__, gcry_strerror (rc)); abort (); } while (0 \
                                                                               )


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
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if not found,
 *         #GNUNET_SYSERR on error
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
 * Details about how to render a currency.
 */
struct TALER_CurrencySpecification
{
  /**
   * Currency code of the currency.
   */
  char currency[TALER_CURRENCY_LEN];

  /**
   * Human-readable long name of the currency, e.g.
   * "Japanese Yen".
   */
  char *name;

  /**
   * how many digits the user may enter at most after the @e decimal_separator
   */
  unsigned int num_fractional_input_digits;

  /**
   * how many digits we render in normal scale after the @e decimal_separator
   */
  unsigned int num_fractional_normal_digits;

  /**
   * how many digits we render in after the @e decimal_separator even if all
   * remaining digits are zero.
   */
  unsigned int num_fractional_trailing_zero_digits;

  /**
   * Mapping of powers of 10 to alternative currency names or symbols.
   * Keys are the decimal powers, values the currency symbol to use.
   * Map MUST contain an entry for "0" to the default currency symbol.
   */
  json_t *map_alt_unit_names;

};


/**
 * Parse information about supported currencies from
 * our configuration.
 *
 * @param cfg configuration to parse
 * @param main_currency main currency of the component
 * @param[out] num_currencies set to number of enabled currencies, length of @e cspecs
 * @param[out] cspecs set to currency specification array
 * @return #GNUNET_OK on success, #GNUNET_NO if zero
 *  currency specifications were enabled,
 *  #GNUNET_SYSERR if the configuration was malformed
 */
enum GNUNET_GenericReturnValue
TALER_CONFIG_parse_currencies (const struct GNUNET_CONFIGURATION_Handle *cfg,
                               const char *main_currency,
                               unsigned int *num_currencies,
                               struct TALER_CurrencySpecification **cspecs);


/**
 * Free @a cspecs array.
 *
 * @param num_currencies length of @a cspecs array
 * @param[in] cspecs array to free
 */
void
TALER_CONFIG_free_currencies (
  unsigned int num_currencies,
  struct TALER_CurrencySpecification cspecs[static num_currencies]);


/**
 * Convert a currency specification to the
 * respective JSON object.
 *
 * @param cspec currency specification
 * @return JSON object encoding @a cspec for `/config`.
 */
json_t *
TALER_CONFIG_currency_specs_to_json (
  const struct TALER_CurrencySpecification *cspec);


/**
 * Check that @a map contains a valid currency scale
 * map that maps integers from [-12,24] to currency
 * symbols given as strings.
 *
 * @param map map to check
 * @return #GNUNET_OK if @a map is valid
 */
enum GNUNET_GenericReturnValue
TALER_check_currency_scale_map (const json_t *map);


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
 * Return default project data used by Taler exchange.
 */
const struct GNUNET_OS_ProjectData *
TALER_EXCHANGE_project_data (void);


/**
 * Re-encode string at @a inp to match RFC 8785 (section 3.2.2.2).
 *
 * @param[in,out] inp pointer to string to re-encode
 * @return number of bytes in resulting @a inp
 */
size_t
TALER_rfc8785encode (char **inp);


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
 * Compare two full payto URIs for equality.
 *
 * @param a a full payto URI, NULL is permitted
 * @param b a full payto URI, NULL is permitted
 * @return 0 if both are equal, otherwise -1 or 1
 */
int
TALER_full_payto_cmp (const struct TALER_FullPayto a,
                      const struct TALER_FullPayto b);

/**
 * Compare two full payto URIs for equality in their normalized form.
 *
 * @param a a full payto URI, NULL is permitted
 * @param b a full payto URI, NULL is permitted
 * @return 0 if both are equal, otherwise -1 or 1
 */
int
TALER_full_payto_normalize_and_cmp (const struct TALER_FullPayto a,
                                    const struct TALER_FullPayto b);


/**
 * Compare two normalized payto URIs for equality.
 *
 * @param a a full payto URI, NULL is permitted
 * @param b a full payto URI, NULL is permitted
 * @return 0 if both are equal, otherwise -1 or 1
 */
int
TALER_normalized_payto_cmp (const struct TALER_NormalizedPayto a,
                            const struct TALER_NormalizedPayto b);


/**
 * Test if the URL is a valid "http" (or "https")
 * URL (includes test for #TALER_url_valid_charset()).
 *
 * @param url a string to test if it could be a valid URL
 * @return true if @a url is well-formed
 */
bool
TALER_is_web_url (const char *url);


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
 * @param base_url absolute base URL to use, must either
 *          end with '/' *or* @a path must be the empty string
 * @param path path of the url to append to the @a base_url
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
 * Normalize payto://-URI to make "strcmp()" sufficient
 * to check if two payto-URIs refer to the same bank
 * account. Removes optional arguments (everything after
 * "?") and applies method-specific normalizations to
 * the main part of the URI.
 *
 * @param input a payto://-URI
 * @return normalized URI, or NULL if @a input was not well-formed
 */
struct TALER_NormalizedPayto
TALER_payto_normalize (const struct TALER_FullPayto input);


/**
 * Normalize the given full payto URI and hash it.
 *
 * @param in full payto URI
 * @param[out] out hash of the normalized payto URI
 */
void
TALER_full_payto_normalize_and_hash (
  const struct TALER_FullPayto in,
  struct TALER_NormalizedPaytoHashP *out);


/**
 * Obtain the account name from a payto URL.
 *
 * @param payto an x-taler-bank payto URL
 * @return only the account name from the @a payto URL, NULL if not an x-taler-bank
 *   payto URL
 */
char *
TALER_xtalerbank_account_from_payto (const struct TALER_FullPayto payto);


/**
 * Obtain the receiver name from a payto URL.
 *
 * @param fpayto a full payto URL
 * @return only the receiver name from the @a payto URL, NULL if not a full payto URL
 */
char *
TALER_payto_get_receiver_name (const struct TALER_FullPayto fpayto);


/**
 * Extract the subject value from the URI parameters.
 *
 * @param payto_uri the full URL to parse
 * @return NULL if the subject parameter is not found.
 *         The caller should free the returned value.
 */
char *
TALER_payto_get_subject (const struct TALER_FullPayto payto_uri);


/**
 * Check that a full payto:// URI is well-formed.
 *
 * @param fpayto_uri the full URL to check
 * @return NULL on success, otherwise an error
 *         message to be freed by the caller!
 */
char *
TALER_payto_validate (const struct TALER_FullPayto fpayto_uri);


/**
 * Create payto://-URI for a given exchange base URL
 * and a @a reserve_pub.
 *
 * @param exchange_url the base URL of the exchange
 * @param reserve_pub the public key of the reserve
 * @return payto://-URI for the reserve (without receiver-name!)
 */
struct TALER_NormalizedPayto
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
 * Possible choices for long-polling for the deposit status.
 */
enum TALER_DepositGetLongPollTarget
{
  /**
   * No long-polling.
   */
  TALER_DGLPT_NONE = 0,

  /**
   * Wait for KYC required/ACCEPTED state *or* for
   * OK state.
   */
  TALER_DGLPT_KYC_REQUIRED_OR_OK = 1,

  /**
   * Wait for the OK-state only.
   */
  TALER_DGLPT_OK = 2,

  /**
   * Maximum allowed value.
   */
  TALER_DGLPT_MAX = 2
};


/**
 * Possible choices for long-polling for the KYC status.
 */
enum TALER_EXCHANGE_KycLongPollTarget
{
  /**
   * No long polling.
   */
  TALER_EXCHANGE_KLPT_NONE = 0,

  /**
   * Wait for KYC auth transfer to be complete.
   */
  TALER_EXCHANGE_KLPT_KYC_AUTH_TRANSFER = 1,

  /**
   * Wait for AML investigation to be complete.
   */
  TALER_EXCHANGE_KLPT_INVESTIGATION_DONE = 2,

  /**
   * Wait for KYC status to be OK.
   */
  TALER_EXCHANGE_KLPT_KYC_OK = 3,

  /**
   * Maximum legal value in this enumeration.
   */
  TALER_EXCHANGE_KLPT_MAX = 3
};


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

/**
 * @brief Parses a date information into days after 1970-01-01 (or 0)
 *
 * The input MUST be of the form
 *
 *   1) YYYY-MM-DD, representing a valid date
 *   2) YYYY-MM-00, representing a valid month in a particular year
 *   3) YYYY-00-00, representing a valid year.
 *
 * In the cases 2) and 3) the out parameter is set to the beginning of the
 * time, f.e. 1950-00-00 == 1950-01-01 and 1888-03-00 == 1888-03-01
 *
 * The output will set to the number of days after 1970-01-01 or 0, if the input
 * represents a date belonging to the largest allowed age group.
 *
 * @param in Input string representation of the date
 * @param mask Age mask
 * @param[out] out Where to write the result
 * @return #GNUNET_OK on success, #GNUNET_SYSERR otherwise
 */
enum GNUNET_GenericReturnValue
TALER_parse_coarse_date (
  const char *in,
  const struct TALER_AgeMask *mask,
  uint32_t *out);


/**
 * @brief Parses a string as a list of age groups.
 *
 * The string must consist of a colon-separated list of increasing integers
 * between 0 and 31.  Each entry represents the beginning of a new age group.
 * F.e. the string
 *
 *  "8:10:12:14:16:18:21"
 *
 * represents the following list of eight age groups:
 *
 * | Group |    Ages       |
 * | -----:|:------------- |
 * |    0  |  0, 1, ..., 7 |
 * |    1  |  8, 9         |
 * |    2  | 10, 11        |
 * |    3  | 12, 13        |
 * |    4  | 14, 15        |
 * |    5  | 16, 17        |
 * |    6  | 18, 19, 20    |
 * |    7  | 21, ...       |
 *
 * which is then encoded as a bit mask with the corresponding bits set:
 *
 *  31     24        16        8         0
 *  |      |         |         |         |
 *  oooooooo  oo1oo1o1  o1o1o1o1  ooooooo1
 *
 * @param groups String representation of age groups
 * @param[out] mask Mask representation for age restriction.
 * @return Error, if age groups were invalid, OK otherwise.
 */
enum GNUNET_GenericReturnValue
TALER_parse_age_group_string (
  const char *groups,
  struct TALER_AgeMask *mask);


/**
 * @brief Encodes the age mask into a string, like "8:10:12:14:16:18:21"
 *
 * NOTE: This function uses a static buffer.  It is not safe to call this
 * function concurrently.
 *
 * @param mask Age mask
 * @return String representation of the age mask.
 *         Can be used as value in the TALER config.
 */
const char *
TALER_age_mask_to_string (
  const struct TALER_AgeMask *mask);


/**
 * @brief returns the age group of a given age for a given age mask
 *
 * @param mask Age mask
 * @param age The given age
 * @return age group
 */
uint8_t
TALER_get_age_group (
  const struct TALER_AgeMask *mask,
  uint8_t age);


/**
 * @brief Parses a JSON object { "age_groups": "a:b:...y:z" }.
 *
 * @param root is the json object
 * @param[out] mask on success, will contain the age mask
 * @return #GNUNET_OK on success and #GNUNET_SYSERR on failure.
 */
enum GNUNET_GenericReturnValue
TALER_JSON_parse_age_groups (const json_t *root,
                             struct TALER_AgeMask *mask);


/**
 * @brief Return the lowest age in the corresponding group for a given age
 * according the given age mask.
 *
 * @param mask age mask
 * @param age age to check
 * @return lowest age in corresponding age group
 */
uint8_t
TALER_get_lowest_age (
  const struct TALER_AgeMask *mask,
  uint8_t age);


/**
 * @brief Get the lowest age for the largest age group
 *
 * @param mask the age mask
 * @return lowest age for the largest age group
 */
#define TALER_adult_age(mask) \
        sizeof((mask)->bits) * 8 - __builtin_clz ((mask)->bits) - 1


#undef __TALER_UTIL_LIB_H_INSIDE__

#endif
