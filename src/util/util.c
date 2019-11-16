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

  (void) ctx;
  if (GNUNET_OK !=
      TALER_string_to_amount (value,
                              amount))
  {
    fprintf (stderr,
             _ ("Failed to parse amount in option `%s'\n"),
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
is_reserved (char c)
{
  switch (c)
  {
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
 * Get the length of a string after it has been
 * urlencoded.
 *
 * @param s the string
 * @returns the size of the urlencoded @a s
 */
static size_t
urlencode_len (const char *s)
{
  size_t len = 0;
  for (; *s != '\0'; len++, s++)
    if (GNUNET_YES == is_reserved (*s))
      len += 2;
  return len;
}


/**
 * URL-encode a string according to rfc3986.
 *
 * @param buf buffer to write the result to
 * @param s string to encode
 */
static void
buffer_write_urlencode (struct TALER_Buffer *buf, const char *s)
{
  TALER_buffer_ensure_remaining (buf, urlencode_len (s) + 1);

  for (size_t i = 0; i < strlen (s); i++)
  {
    if (GNUNET_YES == is_reserved (s[i]))
      TALER_buffer_write_fstr (buf, "%%%02X", s[i]);
    else
      buf->mem[buf->position++] = s[i];
  }
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
  struct TALER_Buffer buf = { 0 };

  buffer_write_urlencode (&buf, s);
  return TALER_buffer_reap_str (&buf);
}


/**
 * Make an absolute URL with query parameters.
 *
 * @param base_url absolute base URL to use
 * @param path path of the url
 * @param ... NULL-terminated key-value pairs (char *) for query parameters,
 *        the value will be url-encoded
 * @returns the URL (must be freed with #GNUNET_free) or
 *          NULL if an error occured.
 */
char *
TALER_url_join (const char *base_url,
                const char *path,
                ...)
{
  unsigned int iparam = 0;
  va_list args;
  struct TALER_Buffer buf = { 0 };
  size_t len = 0;

  GNUNET_assert (NULL != base_url);
  GNUNET_assert (NULL != path);

  if (0 == strlen (base_url))
  {
    /* base URL can't be empty */
    GNUNET_break (0);
    return NULL;
  }

  if ('/' != base_url[strlen (base_url) - 1])
  {
    /* Must be an actual base URL! */
    GNUNET_break (0);
    return NULL;
  }

  if ('/' == path[0])
  {
    /* The path must be relative. */
    GNUNET_break (0);
    return NULL;
  }

  // Path should be relative to existing path of base URL
  GNUNET_break ('/' != path[0]);

  if ('/' == path[0])
    GNUNET_break (0);

  /* 1st pass: compute length */
  len += strlen (base_url) + strlen (path);

  va_start (args, path);
  while (1)
  {
    char *key;
    char *value;
    key = va_arg (args, char *);
    if (NULL == key)
      break;
    value = va_arg (args, char *);
    if (NULL == value)
      continue;
    len += urlencode_len (value) + strlen (key) + 2;
  }
  va_end (args);

  TALER_buffer_prealloc (&buf, len);

  TALER_buffer_write_str (&buf, base_url);
  TALER_buffer_write_str (&buf, path);

  va_start (args, path);
  while (1)
  {
    char *key;
    char *value;
    key = va_arg (args, char *);
    if (NULL == key)
      break;
    value = va_arg (args, char *);
    if (NULL == value)
      continue;
    TALER_buffer_write_str (&buf, (0 == iparam) ? "?" : "&");
    iparam++;
    TALER_buffer_write_str (&buf, key);
    TALER_buffer_write_str (&buf, "=");
    buffer_write_urlencode (&buf, value);
  }
  va_end (args);

  return TALER_buffer_reap_str (&buf);
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
TALER_url_absolute_raw_va (const char *proto,
                           const char *host,
                           const char *prefix,
                           const char *path,
                           va_list args)
{
  struct TALER_Buffer buf = { 0 };
  unsigned int iparam = 0;
  size_t len = 0;
  va_list args2;

  len += strlen (proto) + strlen ("://") + strlen (host);
  len += strlen (prefix) + strlen (path);

  va_copy (args2, args);
  while (1)
  {
    char *key;
    char *value;
    key = va_arg (args2, char *);
    if (NULL == key)
      break;
    value = va_arg (args2, char *);
    if (NULL == value)
      continue;
    len += urlencode_len (value) + strlen (key) + 2;
  }
  va_end (args2);

  TALER_buffer_prealloc (&buf, len);

  TALER_buffer_write_str (&buf, proto);
  TALER_buffer_write_str (&buf, "://");
  TALER_buffer_write_str (&buf, host);

  TALER_buffer_write_path (&buf, prefix);
  TALER_buffer_write_path (&buf, path);

  va_copy (args2, args);
  while (1)
  {
    char *key;
    char *value;
    key = va_arg (args, char *);
    if (NULL == key)
      break;
    value = va_arg (args, char *);
    if (NULL == value)
      continue;
    TALER_buffer_write_str (&buf, (0 == iparam) ? "?" : "&");
    iparam++;
    TALER_buffer_write_str (&buf, key);
    TALER_buffer_write_str (&buf, "=");
    buffer_write_urlencode (&buf, value);
  }
  va_end (args2);

  return TALER_buffer_reap_str (&buf);
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
  result = TALER_url_absolute_raw_va (proto, host, prefix, path, args);
  va_end (args);
  return result;
}


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
TALER_mhd_is_https (struct MHD_Connection *connection)
{
  const union MHD_ConnectionInfo *ci;
  const union MHD_DaemonInfo *di;
  const char *forwarded_proto = MHD_lookup_connection_value (connection,
                                                             MHD_HEADER_KIND,
                                                             "X-Forwarded-Proto");

  if (NULL != forwarded_proto)
  {
    if (0 == strcmp (forwarded_proto, "https"))
      return GNUNET_YES;
    if (0 == strcmp (forwarded_proto, "http"))
      return GNUNET_NO;
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* likely not reverse proxy, figure out if we are
     http by asking MHD */
  ci = MHD_get_connection_info (connection, MHD_CONNECTION_INFO_DAEMON);
  if (NULL == ci)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  di = MHD_get_daemon_info (ci->daemon, MHD_DAEMON_INFO_FLAGS);
  if (NULL == di)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 != (di->flags & MHD_USE_TLS))
    return GNUNET_YES;
  return GNUNET_NO;
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
  const char *proto;
  const char *host;
  const char *forwarded_host;
  const char *prefix;
  va_list args;
  char *result;

  if (GNUNET_YES == TALER_mhd_is_https (connection))
    proto = "https";
  else
    proto = "http";

  host = MHD_lookup_connection_value (connection, MHD_HEADER_KIND, "Host");
  forwarded_host = MHD_lookup_connection_value (connection, MHD_HEADER_KIND,
                                                "X-Forwarded-Host");

  prefix = MHD_lookup_connection_value (connection, MHD_HEADER_KIND,
                                        "X-Forwarded-Prefix");
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
  result = TALER_url_absolute_raw_va (proto, host, prefix, path, args);
  va_end (args);
  return result;
}


/**
 * Initialize a buffer with the given capacity.
 *
 * When a buffer is allocated with this function, a warning is logged
 * when the buffer exceeds the initial capacity.
 *
 * @param buf the buffer to initialize
 * @param capacity the capacity (in bytes) to allocate for @a buf
 */
void
TALER_buffer_prealloc (struct TALER_Buffer *buf, size_t capacity)
{
  /* Buffer should be zero-initialized */
  GNUNET_assert (0 == buf->mem);
  GNUNET_assert (0 == buf->capacity);
  GNUNET_assert (0 == buf->position);
  buf->mem = GNUNET_malloc (capacity);
  buf->capacity = capacity;
  buf->warn_grow = GNUNET_YES;
}


/**
 * Make sure that at least @a n bytes remaining in the buffer.
 *
 * @param buf buffer to potentially grow
 * @param n number of bytes that should be available to write
 */
void
TALER_buffer_ensure_remaining (struct TALER_Buffer *buf, size_t n)
{
  size_t new_capacity = buf->position + n;

  if (new_capacity <= buf->capacity)
    return;
  /* warn if calculation of expected size was wrong */
  GNUNET_break (GNUNET_YES != buf->warn_grow);
  if (new_capacity < buf->capacity * 2)
    new_capacity = buf->capacity * 2;
  buf->capacity = new_capacity;
  if (NULL != buf->mem)
    buf->mem = GNUNET_realloc (buf->mem, new_capacity);
  else
    buf->mem = GNUNET_malloc (new_capacity);
}


/**
 * Write bytes to the buffer.
 *
 * Grows the buffer if necessary.
 *
 * @param buf buffer to write to
 * @param data data to read from
 * @param len number of bytes to copy from @a data to @a buf
 *
 */
void
TALER_buffer_write (struct TALER_Buffer *buf, const char *data, size_t len)
{
  TALER_buffer_ensure_remaining (buf, len);
  memcpy (buf->mem + buf->position, data, len);
  buf->position += len;
}


/**
 * Write a 0-terminated string to a buffer, excluding the 0-terminator.
 *
 * @param buf the buffer to write to
 * @param str the string to write to @a buf
 */
void
TALER_buffer_write_str (struct TALER_Buffer *buf, const char *str)
{
  size_t len = strlen (str);

  TALER_buffer_write (buf, str, len);
}


/**
 * Clear the buffer and return the string it contained.
 * The caller is responsible to eventually #GNUNET_free
 * the returned string.
 *
 * The returned string is always 0-terminated.
 *
 * @param buf the buffer to reap the string from
 * @returns the buffer contained in the string
 */
char *
TALER_buffer_reap_str (struct TALER_Buffer *buf)
{
  char *res;

  /* ensure 0-termination */
  if ( (0 == buf->position) || ('\0' != buf->mem[buf->position - 1]))
  {
    TALER_buffer_ensure_remaining (buf, 1);
    buf->mem[buf->position++] = '\0';
  }
  res = buf->mem;
  *buf = (struct TALER_Buffer) { 0 };
  return res;
}


/**
 * Free the backing memory of the given buffer.
 * Does not free the memory of the buffer control structure,
 * which is typically stack-allocated.
 */
void
TALER_buffer_clear (struct TALER_Buffer *buf)
{
  GNUNET_free_non_null (buf->mem);
  *buf = (struct TALER_Buffer) { 0 };
}


/**
 * Write a path component to a buffer, ensuring that
 * there is exactly one slash between the previous contents
 * of the buffer and the new string.
 *
 * @param buf buffer to write to
 * @param str string containing the new path component
 */
void
TALER_buffer_write_path (struct TALER_Buffer *buf, const char *str)
{
  size_t len = strlen (str);

  while ( (0 != len) && ('/' == str[0]) )
  {
    str++;
    len--;
  }
  if ( (0 == buf->position) || ('/' != buf->mem[buf->position - 1]) )
  {
    TALER_buffer_ensure_remaining (buf, 1);
    buf->mem[buf->position++] = '/';
  }
  TALER_buffer_write (buf, str, len);
}


/**
 * Write a 0-terminated formatted string to a buffer, excluding the
 * 0-terminator.
 *
 * Grows the buffer if necessary.
 *
 * @param buf the buffer to write to
 * @param fmt format string
 * @param ... format arguments
 */
void
TALER_buffer_write_fstr (struct TALER_Buffer *buf, const char *fmt, ...)
{
  va_list args;

  va_start (args, fmt);
  TALER_buffer_write_vfstr (buf, fmt, args);
  va_end (args);
}


/**
 * Write a 0-terminated formatted string to a buffer, excluding the
 * 0-terminator.
 *
 * Grows the buffer if necessary.
 *
 * @param buf the buffer to write to
 * @param fmt format string
 * @param args format argument list
 */
void
TALER_buffer_write_vfstr (struct TALER_Buffer *buf,
                          const char *fmt,
                          va_list args)
{
  int res;
  va_list args2;

  va_copy (args2, args);
  res = vsnprintf (NULL, 0, fmt, args2);
  va_end (args2);

  GNUNET_assert (res >= 0);
  TALER_buffer_ensure_remaining (buf, res + 1);

  va_copy (args2, args);
  res = vsnprintf (buf->mem + buf->position, res + 1, fmt, args2);
  va_end (args2);

  GNUNET_assert (res >= 0);
  buf->position += res;
  GNUNET_assert (buf->position <= buf->capacity);
}


/* end of util.c */
