/*
  This file is part of TALER
  Copyright (C) 2019-2024 Taler Systems SA

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
 * @file payto.c
 * @brief Common utility functions for dealing with payto://-URIs
 * @author Florian Dold
 */
#include "platform.h"
#include "taler_util.h"


/**
 * Prefix of PAYTO URLs.
 */
#define PAYTO "payto://"


int
TALER_full_payto_cmp (const struct TALER_FullPayto a,
                      const struct TALER_FullPayto b)
{
  if ( (NULL == a.full_payto) &&
       (NULL == b.full_payto) )
    return 0;
  if (NULL == a.full_payto)
    return -1;
  if (NULL == b.full_payto)
    return 1;
  return strcmp (a.full_payto,
                 b.full_payto);
}


/**
 * Extract the value under @a key from the URI parameters.
 *
 * @param fpayto_uri the full payto URL to parse
 * @param search_key key to look for, including "="
 * @return NULL if the @a key parameter is not found.
 *         The caller should free the returned value.
 */
static char *
payto_get_key (const struct TALER_FullPayto fpayto_uri,
               const char *search_key)
{
  const char *payto_uri = fpayto_uri.full_payto;
  const char *key;
  const char *value_start;
  const char *value_end;

  key = strchr (payto_uri,
                (unsigned char) '?');
  if (NULL == key)
    return NULL;

  do {
    if (0 == strncasecmp (++key,
                          search_key,
                          strlen (search_key)))
    {
      value_start = strchr (key,
                            (unsigned char) '=');
      if (NULL == value_start)
        return NULL;
      value_end = strchrnul (value_start,
                             (unsigned char) '&');

      return GNUNET_strndup (value_start + 1,
                             value_end - value_start - 1);
    }
  } while ( (key = strchr (key,
                           (unsigned char) '&')) );
  return NULL;
}


char *
TALER_payto_get_subject (const struct TALER_FullPayto payto_uri)
{
  return payto_get_key (payto_uri,
                        "subject=");
}


char *
TALER_payto_get_method (const char *payto_uri)
{
  const char *start;
  const char *end;

  if (0 != strncasecmp (payto_uri,
                        PAYTO,
                        strlen (PAYTO)))
    return NULL;
  start = &payto_uri[strlen (PAYTO)];
  end = strchr (start,
                (unsigned char) '/');
  if (NULL == end)
    return NULL;
  return GNUNET_strndup (start,
                         end - start);
}


char *
TALER_xtalerbank_account_from_payto (const char *payto)
{
  const char *host;
  const char *beg;
  const char *nxt;
  const char *end;

  if (0 != strncasecmp (payto,
                        PAYTO "x-taler-bank/",
                        strlen (PAYTO "x-taler-bank/")))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  host = &payto[strlen (PAYTO "x-taler-bank/")];
  beg = strchr (host,
                '/');
  if (NULL == beg)
  {
    GNUNET_break_op (0);
    return NULL;
  }
  beg++; /* now points to $ACCOUNT or $PATH */
  nxt = strchr (beg,
                '/');
  end = strchr (beg,
                '?');
  if (NULL == end)
    end = &beg[strlen (beg)];
  while ( (NULL != nxt) &&
          (end - nxt > 0) )
  {
    beg = nxt + 1;
    nxt = strchr (beg,
                  '/');
  }
  return GNUNET_strndup (beg,
                         end - beg);
}


/**
 * Validate payto://iban/ account URL (only account information,
 * wire subject and amount are ignored).
 *
 * @param account_url payto URL to parse
 * @return NULL on success, otherwise an error message
 *      to be freed by the caller
 */
static char *
validate_payto_iban (struct TALER_FullPayto account_url)
{
  const char *iban;
  const char *q;
  char *result;
  char *err;

#define IBAN_PREFIX "payto://iban/"
  if (0 != strncasecmp (account_url.full_payto,
                        IBAN_PREFIX,
                        strlen (IBAN_PREFIX)))
    return NULL; /* not an IBAN */
  iban = strrchr (account_url.full_payto,
                  '/') + 1;
#undef IBAN_PREFIX
  q = strchr (iban,
              '?');
  if (NULL != q)
  {
    result = GNUNET_strndup (iban,
                             q - iban);
  }
  else
  {
    result = GNUNET_strdup (iban);
  }
  if (NULL !=
      (err = TALER_iban_validate (result)))
  {
    GNUNET_free (result);
    return err;
  }
  GNUNET_free (result);
  {
    char *target;

    target = payto_get_key (account_url,
                            "receiver-name=");
    if (NULL == target)
      return GNUNET_strdup ("'receiver-name' parameter missing");
    GNUNET_free (target);
  }
  return NULL;
}


/**
 * Validate payto://x-taler-bank/ account URL (only account information,
 * wire subject and amount are ignored).
 *
 * @param account_url payto URL to parse
 * @return NULL on success, otherwise an error message
 *      to be freed by the caller
 */
static char *
validate_payto_xtalerbank (const struct TALER_FullPayto account_url)
{
  const char *user;
  const char *nxt;
  const char *beg;
  const char *end;
  const char *host;
  bool dot_ok;
  bool post_colon;
  bool port_ok;

#define XTALERBANK_PREFIX PAYTO "x-taler-bank/"
  if (0 != strncasecmp (account_url.full_payto,
                        XTALERBANK_PREFIX,
                        strlen (XTALERBANK_PREFIX)))
    return NULL; /* not an IBAN */
  host = &account_url.full_payto[strlen (XTALERBANK_PREFIX)];
#undef XTALERBANK_PREFIX
  beg = strchr (host,
                '/');
  if (NULL == beg)
  {
    return GNUNET_strdup ("account name missing");
  }
  beg++; /* now points to $ACCOUNT or $PATH */
  nxt = strchr (beg,
                '/');
  end = strchr (beg,
                '?');
  if (NULL == end)
  {
    return GNUNET_strdup ("'receiver-name' parameter missing");
  }
  while ( (NULL != nxt) &&
          (end - nxt > 0) )
  {
    beg = nxt + 1;
    nxt = strchr (beg,
                  '/');
  }
  user = beg;
  if (user == host + 1)
  {
    return GNUNET_strdup ("domain name missing");
  }
  if ('-' == host[0])
    return GNUNET_strdup ("invalid character '-' at start of domain name");
  dot_ok = false;
  post_colon = false;
  port_ok = false;
  while (host != user)
  {
    char c = host[0];

    if ('/' == c)
    {
      /* path started, do not care about characters
         in the path */
      break;
    }
    if (':' == c)
    {
      post_colon = true;
      host++;
      continue;
    }
    if (post_colon)
    {
      if (! ( ('0' <= c) && ('9' >= c) ) )
      {
        char *err;

        GNUNET_asprintf (&err,
                         "invalid character '%c' in port",
                         c);
        return err;
      }
      port_ok = true;
    }
    else
    {
      if ('.' == c)
      {
        if (! dot_ok)
          return GNUNET_strdup ("invalid domain name (misplaced '.')");
        dot_ok = false;
      }
      else
      {
        if (! ( ('-' == c) ||
                ('_' == c) ||
                ( ('0' <= c) && ('9' >= c) ) ||
                ( ('a' <= c) && ('z' >= c) ) ||
                ( ('A' <= c) && ('Z' >= c) ) ) )
        {
          char *err;

          GNUNET_asprintf (&err,
                           "invalid character '%c' in domain name",
                           c);
          return err;
        }
        dot_ok = true;
      }
    }
    host++;
  }
  if (post_colon && (! port_ok) )
  {
    return GNUNET_strdup ("port missing after ':'");
  }
  {
    char *target;

    target = payto_get_key (account_url,
                            "receiver-name=");
    if (NULL == target)
      return GNUNET_strdup ("'receiver-name' parameter missing");
    GNUNET_free (target);
  }
  return NULL;
}


char *
TALER_payto_validate (const struct TALER_FullPayto fpayto_uri)
{
  const char *payto_uri = fpayto_uri.full_payto;
  char *ret;
  const char *start;
  const char *end;

  if (0 != strncasecmp (payto_uri,
                        PAYTO,
                        strlen (PAYTO)))
    return GNUNET_strdup ("invalid prefix");
  for (unsigned int i = 0; '\0' != payto_uri[i]; i++)
  {
    /* This is more strict than RFC 8905, alas we do not need to support messages/instructions/etc.,
       and it is generally better to start with a narrow whitelist; we can be more permissive later ...*/
#define ALLOWED_CHARACTERS \
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/:$&?!-_.,;=*+%~@()[]"
    if (NULL == strchr (ALLOWED_CHARACTERS,
                        (int) payto_uri[i]))
    {
      GNUNET_asprintf (&ret,
                       "Encountered invalid character `%c' at offset %u in payto URI `%s'",
                       payto_uri[i],
                       i,
                       payto_uri);
      return ret;
    }
#undef ALLOWED_CHARACTERS
  }

  start = &payto_uri[strlen (PAYTO)];
  end = strchr (start,
                (unsigned char) '/');
  if (NULL == end)
    return GNUNET_strdup ("missing '/' in payload");

  if (NULL != (ret = validate_payto_iban (fpayto_uri)))
    return ret; /* got a definitive answer */
  if (NULL != (ret = validate_payto_xtalerbank (fpayto_uri)))
    return ret; /* got a definitive answer */

  /* Insert other bank account validation methods here later! */

  return NULL;
}


char *
TALER_payto_get_receiver_name (const struct TALER_FullPayto fpayto)
{
  char *err;

  err = TALER_payto_validate (fpayto);
  if (NULL != err)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Invalid payto://-URI `%s': %s\n",
                fpayto.full_payto,
                err);
    GNUNET_free (err);
    return NULL;
  }
  return payto_get_key (fpayto,
                        "receiver-name=");
}


/**
 * Normalize "payto://x-taler-bank/$HOSTNAME/[$PATH/]$USERNAME"
 * URI in @a input.
 *
 * Converts to lower-case, except for [$PATH/]$USERNAME which
 * is case-sensitive.
 *
 * @param len number of bytes in @a input
 * @param input input URL
 * @return NULL on error, otherwise 0-terminated canonicalized URI.
 */
static char *
normalize_payto_x_taler_bank (size_t len,
                              const char input[static len])
{
  char *res = GNUNET_malloc (len + 1);
  unsigned int sc = 0;

  for (unsigned int i = 0; i<len; i++)
  {
    char c = input[i];

    if ('/' == c)
      sc++;
    if (sc < 4)
      res[i] = (char) tolower ((int) c);
    else
      res[i] = c;
  }
  return res;
}


/**
 * Normalize "payto://iban[/$BIC]/$IBAN"
 * URI in @a input.
 *
 * Removes $BIC (if present) and converts $IBAN to upper-case and prefix to
 * lower-case.
 *
 * @param len number of bytes in @a input
 * @param input input URL
 * @return NULL on error, otherwise 0-terminated canonicalized URI.
 */
static char *
normalize_payto_iban (size_t len,
                      const char input[static len])
{
  char *res;
  size_t pos = 0;
  unsigned int sc = 0;
  bool have_bic;

  for (unsigned int i = 0; i<len; i++)
    if ('/' == input[i])
      sc++;
  if ( (sc > 4) ||
       (sc < 3) )
  {
    GNUNET_break (0);
    return NULL;
  }
  have_bic = (4 == sc);
  res = GNUNET_malloc (len + 1);
  sc = 0;
  for (unsigned int i = 0; i<len; i++)
  {
    char c = input[i];

    if ('/' == c)
      sc++;
    switch (sc)
    {
    case 0: /* payto: */
    case 1: /* / */
    case 2: /* /iban */
      res[pos++] = (char) tolower ((int) c);
      break;
    case 3: /* /$BIC or /$IBAN */
      if (have_bic)
        continue;
      res[pos++] = (char) toupper ((int) c);
      break;
    case 4: /* /$IBAN */
      res[pos++] = (char) toupper ((int) c);
      break;
    }
  }
  GNUNET_assert (pos <= len);
  return res;
}


/**
 * Normalize "payto://upi/$EMAIL"
 * URI in @a input.
 *
 * Converts to lower-case.
 *
 * @param len number of bytes in @a input
 * @param input input URL
 * @return NULL on error, otherwise 0-terminated canonicalized URI.
 */
static char *
normalize_payto_upi (size_t len,
                     const char input[static len])
{
  char *res = GNUNET_malloc (len + 1);

  for (unsigned int i = 0; i<len; i++)
  {
    char c = input[i];

    res[i] = (char) tolower ((int) c);
  }
  return res;
}


/**
 * Normalize "payto://bitcoin/$ADDRESS"
 * URI in @a input.
 *
 * Converts to lower-case, except for $ADDRESS which
 * is case-sensitive.
 *
 * @param len number of bytes in @a input
 * @param input input URL
 * @return NULL on error, otherwise 0-terminated canonicalized URI.
 */
static char *
normalize_payto_bitcoin (size_t len,
                         const char input[static len])
{
  char *res = GNUNET_malloc (len + 1);
  unsigned int sc = 0;

  for (unsigned int i = 0; i<len; i++)
  {
    char c = input[i];

    if ('/' == c)
      sc++;
    if (sc < 3)
      res[i] = (char) tolower ((int) c);
    else
      res[i] = c;
  }
  return res;
}


/**
 * Normalize "payto://ilp/$NAME"
 * URI in @a input.
 *
 * Converts to lower-case.
 *
 * @param len number of bytes in @a input
 * @param input input URL
 * @return NULL on error, otherwise 0-terminated canonicalized URI.
 */
static char *
normalize_payto_ilp (size_t len,
                     const char input[static len])
{
  char *res = GNUNET_malloc (len + 1);

  for (unsigned int i = 0; i<len; i++)
  {
    char c = input[i];

    res[i] = (char) tolower ((int) c);
  }
  return res;
}


struct TALER_NormalizedPayto
TALER_payto_normalize (const struct TALER_FullPayto input)
{
  struct TALER_NormalizedPayto npto = {
    .normalized_payto = NULL
  };
  char *method;
  const char *end;
  char *ret;

  {
    char *err;

    err = TALER_payto_validate (input);
    if (NULL != err)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Malformed payto://-URI `%s': %s\n",
                  input.full_payto,
                  err);
      GNUNET_free (err);
      return npto;
    }
  }
  method = TALER_payto_get_method (input.full_payto);
  if (NULL == method)
  {
    GNUNET_break (0);
    return npto;
  }
  end = strchr (input.full_payto,
                '?');
  if (NULL == end)
    end = &input.full_payto[strlen (input.full_payto)];
  if (0 == strcasecmp (method,
                       "x-taler-bank"))
    ret = normalize_payto_x_taler_bank (end - input.full_payto,
                                        input.full_payto);
  else if (0 == strcasecmp (method,
                            "iban"))
    ret = normalize_payto_iban (end - input.full_payto,
                                input.full_payto);
  else if (0 == strcasecmp (method,
                            "upi"))
    ret = normalize_payto_upi (end - input.full_payto,
                               input.full_payto);
  else if (0 == strcasecmp (method,
                            "bitcoin"))
    ret = normalize_payto_bitcoin (end - input.full_payto,
                                   input.full_payto);
  else if (0 == strcasecmp (method,
                            "ilp"))
    ret = normalize_payto_ilp (end - input.full_payto,
                               input.full_payto);
  else
    ret = GNUNET_strndup (input.full_payto,
                          end - input.full_payto);
  GNUNET_free (method);
  npto.normalized_payto = ret;
  return npto;
}


void
TALER_normalized_payto_hash (const struct TALER_NormalizedPayto npayto,
                             struct TALER_NormalizedPaytoHashP *h_npayto)
{
  struct GNUNET_HashCode sha512;

  GNUNET_CRYPTO_hash (npayto.normalized_payto,
                      strlen (npayto.normalized_payto) + 1,
                      &sha512);
  GNUNET_static_assert (sizeof (sha512) > sizeof (*h_npayto));
  /* truncate */
  GNUNET_memcpy (h_npayto,
                 &sha512,
                 sizeof (*h_npayto));
}


void
TALER_full_payto_hash (const struct TALER_FullPayto fpayto,
                       struct TALER_FullPaytoHashP *h_fpayto)
{
  struct GNUNET_HashCode sha512;

  GNUNET_CRYPTO_hash (fpayto.full_payto,
                      strlen (fpayto.full_payto) + 1,
                      &sha512);
  GNUNET_static_assert (sizeof (sha512) > sizeof (*h_fpayto));
  /* truncate */
  GNUNET_memcpy (h_fpayto,
                 &sha512,
                 sizeof (*h_fpayto));
}


struct TALER_NormalizedPayto
TALER_reserve_make_payto (const char *exchange_url,
                          const struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct TALER_NormalizedPayto npto = {
    .normalized_payto = NULL
  };
  char pub_str[sizeof (*reserve_pub) * 2];
  char *end;
  bool is_http;
  char *reserve_url;

  end = GNUNET_STRINGS_data_to_string (
    reserve_pub,
    sizeof (*reserve_pub),
    pub_str,
    sizeof (pub_str));
  *end = '\0';
  if (0 == strncmp (exchange_url,
                    "http://",
                    strlen ("http://")))
  {
    is_http = true;
    exchange_url = &exchange_url[strlen ("http://")];
  }
  else if (0 == strncmp (exchange_url,
                         "https://",
                         strlen ("https://")))
  {
    is_http = false;
    exchange_url = &exchange_url[strlen ("https://")];
  }
  else
  {
    GNUNET_break (0);
    return npto;
  }
  /* exchange_url includes trailing '/' */
  GNUNET_asprintf (&reserve_url,
                   "payto://%s/%s%s",
                   is_http ? "taler-reserve-http" : "taler-reserve",
                   exchange_url,
                   pub_str);
  npto.normalized_payto = reserve_url;
  return npto;
}


/* end of payto.c */
