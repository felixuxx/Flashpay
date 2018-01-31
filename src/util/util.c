/*
  This file is part of TALER
  Copyright (C) 2014 GNUnet e.V.

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
 * @file util.c
 * @brief Common utility functions; we might choose to move those to GNUnet at some point
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Benedikt Mueller
 */

#include "platform.h"
#include "taler_util.h"
#include <gcrypt.h>


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
	   size_t buf_size)
{
  static char ret[9];
  struct GNUNET_HashCode hc;
  char *tmp;

  GNUNET_CRYPTO_hash (buf,
		      buf_size,
		      &hc);
  tmp = GNUNET_STRINGS_data_to_string_alloc (&hc,
					     sizeof (hc));
  memcpy (ret,
	  tmp,
	  8);
  GNUNET_free (tmp);
  ret[8] = '\0';
  return ret;
}


/**
 * Obtain denomination amount from configuration file.
 *
 * @param cfg configuration to use
 * @param section section of the configuration to access
 * @param option option of the configuration to access
 * @param[out] denom set to the amount found in configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_config_get_denom (const struct GNUNET_CONFIGURATION_Handle *cfg,
                        const char *section,
                        const char *option,
                        struct TALER_Amount *denom)
{
  char *str;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             option,
                                             &str))
    return GNUNET_NO;
  if (GNUNET_OK != TALER_string_to_amount (str,
                                           denom))
  {
    GNUNET_free (str);
    return GNUNET_SYSERR;
  }
  GNUNET_free (str);
  return GNUNET_OK;
}




/**
 * Set an option with an amount from the command line.  A pointer to
 * this function should be passed as part of the 'struct
 * GNUNET_GETOPT_CommandLineOption' array to initialize options of
 * this type.
 *
 * @param ctx command line processing context
 * @param scls additional closure (will point to the `struct TALER_Amount`)
 * @param option name of the option
 * @param value actual value of the option as a string.
 * @return #GNUNET_OK if parsing the value worked
 */
static int
set_amount (struct GNUNET_GETOPT_CommandLineProcessorContext *ctx,
            void *scls,
            const char *option,
            const char *value)
{
  struct TALER_Amount *amount = scls;

  if (GNUNET_OK !=
      TALER_string_to_amount (value,
                              amount))
  {
    FPRINTF (stderr,
             _("Failed to parse amount in option `%s'\n"),
             option);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


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
                         struct TALER_Amount *amount)
{
  struct GNUNET_GETOPT_CommandLineOption clo = {
    .shortName =  shortName,
    .name = name,
    .argumentHelp = argumentHelp,
    .description = description,
    .require_argument = 1,
    .processor = &set_amount,
    .scls = (void *) amount
  };

  return clo;
}


/**
 * Check if a character is reserved and should
 * be urlencoded.
 *
 * @param c character to look at
 * @return #GNUNET_YES if @a c needs to be urlencoded,
 *         #GNUNET_NO otherwise
 */
static bool
is_reserved(char c)
{
  switch (c) {
    case '0': case '1': case '2': case '3': case '4':
    case '5': case '6': case '7': case '8': case '9':
    case 'a': case 'b': case 'c': case 'd': case 'e':
    case 'f': case 'g': case 'h': case 'i': case 'j':
    case 'k': case 'l': case 'm': case 'n': case 'o':
    case 'p': case 'q': case 'r': case 's': case 't':
    case 'u': case 'v': case 'w': case 'x': case 'y': case 'z':
    case 'A': case 'B': case 'C': case 'D': case 'E':
    case 'F': case 'G': case 'H': case 'I': case 'J':
    case 'K': case 'L': case 'M': case 'N': case 'O':
    case 'P': case 'Q': case 'R': case 'S': case 'T':
    case 'U': case 'V': case 'W': case 'X': case 'Y': case 'Z':
    case '-': case '.': case '_': case '~':
      return GNUNET_NO;
    default:
      break;
  }
  return GNUNET_YES;
}


/**
 * URL-encode a string according to rfc3986.
 *
 * @param s string to encode
 * @returns the urlencoded string, the caller must free it with GNUNET_free
 */
char *
TALER_urlencode (const char *s)
{
  unsigned int new_size;
  unsigned int i;
  unsigned int t;
  char *out;

  new_size = strlen (s);
  for (i = 0; i < strlen (s); i++)
    if (GNUNET_YES == is_reserved (s[i]))
      new_size += 2;
  out = GNUNET_malloc (new_size + 1);
  for (i = 0, t = 0; i < strlen (s); i++, t++)
  {
    if (GNUNET_YES == is_reserved (s[i]))
    {
      snprintf(&out[t], 4, "%%%02X", s[i]);
      t += 2;
      continue;
    }
    out[t] = s[i];
  }
  return out;
}


/**
 * Grow a string in a buffer with the given size.
 * The buffer is re-allocated if necessary.
 *
 * @param s pointer to string buffer
 * @param p the string to append
 * @param n pointer to the allocated size of n
 * @returns pointer to the resulting buffer,
 *          might differ from @a s (!!)
 */
static char *
grow_string (char **s, const char *p, size_t *n)
{
  for (; strlen (*s) + strlen (p) >= *n; *n *= 2);
  *s = GNUNET_realloc (*s, *n);
  GNUNET_assert (NULL != s);
  strncat (*s, p, *n);
  return *s;
}


/**
 * Grow a string in a buffer with the given size.
 * The buffer is re-allocated if necessary.
 *
 * Ensures that slashes are removed or added when joining paths.
 *
 * @param s pointer to string buffer
 * @param p the string to append
 * @param n pointer to the allocated size of n
 * @returns pointer to the resulting buffer,
 *          might differ from @a s (!!)
 */
static char *
grow_string_path (char **s, const char *p, size_t *n)
{
  char a = (0 == strlen (*s)) ? '\0' : (*s)[strlen (*s) - 1];
  char b = (0 == strlen (p)) ? '\0' : p[0];

  if ( (a == '/') && (b == '/'))
  {
    p++;
  }
  else if ( (a != '/') && (b != '/'))
  {
    if (NULL == (*s = grow_string (s, "/", n)))
      return NULL;
  }
  return grow_string (s, p, n);
}


/**
 * Make an absolute URL with query parameters.
 *
 * @param base_url absolute base URL to use
 * @param path path of the url
 * @param ... NULL-terminated key-value pairs (char *) for query parameters,
 *        the value will be url-encoded
 * @returns the URL, must be freed with #GNUNET_free
 */
char *
TALER_url_join (const char *base_url,
                const char *path,
                ...)
{
  size_t n = 256;
  char *res = GNUNET_malloc (n);
  unsigned int iparam = 0;
  char *enc;
  va_list args;

  GNUNET_assert (NULL != res);

  grow_string (&res, base_url, &n);

  grow_string_path (&res, path, &n);

  va_start (args, path);

  while (1) {
    char *key;
    char *value;
    key = va_arg (args, char *);
    if (NULL == key)
      break;
    value = va_arg (args, char *);
    if (NULL == value)
      continue;
    grow_string (&res, (0 == iparam) ? "?" : "&", &n);
    iparam++;
    grow_string (&res, key, &n);
    grow_string (&res, "=", &n);
    enc = TALER_urlencode (value);
    grow_string (&res, enc, &n);
    GNUNET_free (enc);
  }

  va_end (args);

  return res;
}


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
url_absolute_raw_va (const char *proto,
                     const char *host,
                     const char *prefix,
                     const char *path,
                     va_list args)
{
  size_t n = 256;
  char *res = GNUNET_malloc (n);
  char *enc;
  unsigned int iparam = 0;

  grow_string (&res, proto, &n);
  grow_string (&res, "://", &n);
  grow_string (&res, host, &n);

  grow_string_path (&res, prefix, &n);

  grow_string_path (&res, path, &n);

  while (1) {
    char *key;
    char *value;
    key = va_arg (args, char *);
    if (NULL == key)
      break;
    value = va_arg (args, char *);
    if (NULL == value)
      continue;
    grow_string (&res, (0 == iparam) ? "?" : "&", &n);
    iparam++;
    grow_string (&res, key, &n);
    grow_string (&res, "=", &n);
    enc = TALER_urlencode (value);
    grow_string (&res, enc, &n);
    GNUNET_free (enc);
  }

  return res;
}


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
TALER_url_absolute_raw (const char *proto,
                        const char *host,
                        const char *prefix,
                        const char *path,
                        ...)
{
  char *result;
  va_list args;

  va_start (args, path);
  result = url_absolute_raw_va (proto, host, prefix, path, args);
  va_end (args);
  return result;
}


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
                        ...)
{
  /* By default we assume we're running under HTTPS */
  const char *proto = "https";
  const char *forwarded_proto = MHD_lookup_connection_value (connection, MHD_HEADER_KIND, "X-Forwarded-Proto");
  const char *host;
  const char *forwarded_host;
  const char *prefix;
  va_list args;
  char *result;

  if (NULL != forwarded_proto)
    proto = forwarded_proto;

  host = MHD_lookup_connection_value (connection, MHD_HEADER_KIND, "Host");
  forwarded_host = MHD_lookup_connection_value (connection, MHD_HEADER_KIND, "X-Forwarded-Host");

  prefix = MHD_lookup_connection_value (connection, MHD_HEADER_KIND, "X-Forwarded-Prefix");
  if (NULL == prefix)
    prefix = "";

  if (NULL != forwarded_host)
    host = forwarded_host;

  if (NULL == host)
  {
    /* Should never happen, at last the host header should be defined */
    GNUNET_break (0);
    return NULL;
  }

  va_start (args, path);
  result = url_absolute_raw_va (proto, host, prefix, path, args);
  va_end (args);
  return result;
}


/* end of util.c */
