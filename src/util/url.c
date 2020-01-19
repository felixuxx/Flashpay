/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file url.c
 * @brief URL handling utility functions
 * @author Florian Dold
 */
#include "platform.h"
#include "taler_util.h"


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
buffer_write_urlencode (struct GNUNET_Buffer *buf,
                        const char *s)
{
  GNUNET_buffer_ensure_remaining (buf, urlencode_len (s) + 1);

  for (size_t i = 0; i < strlen (s); i++)
  {
    if (GNUNET_YES == is_reserved (s[i]))
      GNUNET_buffer_write_fstr (buf, "%%%02X", s[i]);
    else
      buf->mem[buf->position++] = s[i];
  }
}


/**
 * URL-encode a string according to rfc3986.
 *
 * @param s string to encode
 * @returns the urlencoded string, the caller must free it with #GNUNET_free()
 */
char *
TALER_urlencode (const char *s)
{
  struct GNUNET_Buffer buf = { 0 };

  buffer_write_urlencode (&buf, s);
  return GNUNET_buffer_reap_str (&buf);
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
  struct GNUNET_Buffer buf = { 0 };
  size_t len;

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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Base URL `%s' does not end with '/'\n",
                base_url);
    return NULL;
  }
  if ('/' == path[0])
  {
    /* The path must be relative. */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Path `%s' is not relative\n",
                path);
    return NULL;
  }

  /* 1st pass: compute length */
  len = strlen (base_url) + strlen (path) + 1;

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

  GNUNET_buffer_prealloc (&buf, len);
  GNUNET_buffer_write_str (&buf, base_url);
  GNUNET_buffer_write_str (&buf, path);

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
    GNUNET_buffer_write_str (&buf, (0 == iparam) ? "?" : "&");
    iparam++;
    GNUNET_buffer_write_str (&buf, key);
    GNUNET_buffer_write_str (&buf, "=");
    buffer_write_urlencode (&buf, value);
  }
  va_end (args);

  return GNUNET_buffer_reap_str (&buf);
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
  struct GNUNET_Buffer buf = { 0 };
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

  GNUNET_buffer_prealloc (&buf, len);

  GNUNET_buffer_write_str (&buf, proto);
  GNUNET_buffer_write_str (&buf, "://");
  GNUNET_buffer_write_str (&buf, host);

  GNUNET_buffer_write_path (&buf, prefix);
  GNUNET_buffer_write_path (&buf, path);

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
    GNUNET_buffer_write_str (&buf, (0 == iparam) ? "?" : "&");
    iparam++;
    GNUNET_buffer_write_str (&buf, key);
    GNUNET_buffer_write_str (&buf, "=");
    buffer_write_urlencode (&buf, value);
  }
  va_end (args2);

  return GNUNET_buffer_reap_str (&buf);
}


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
                        ...)
{
  char *result;
  va_list args;

  va_start (args, path);
  result = TALER_url_absolute_raw_va (proto, host, prefix, path, args);
  va_end (args);
  return result;
}


/* end of url.c */
