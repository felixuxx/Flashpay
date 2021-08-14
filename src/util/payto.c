/*
  This file is part of TALER
  Copyright (C) 2019-2021 Taler Systems SA

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


/**
 * Extract the value under @a key from the URI parameters.
 *
 * @param payto_uri the URL to parse
 * @param search_key key to look for, including "="
 * @return NULL if the @a key parameter is not found.
 *         The caller should free the returned value.
 */
static char *
payto_get_key (const char *payto_uri,
               const char *search_key)
{
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


/**
 * Extract the subject value from the URI parameters.
 *
 * @param payto_uri the URL to parse
 * @return NULL if the subject parameter is not found.
 *         The caller should free the returned value.
 */
char *
TALER_payto_get_subject (const char *payto_uri)
{
  return payto_get_key (payto_uri,
                        "subject=");
}


/**
 * Obtain the payment method from a @a payto_uri. The
 * format of a payto URI is 'payto://$METHOD/$SOMETHING'.
 * We return $METHOD.
 *
 * @param payto_uri the URL to parse
 * @return NULL on error (malformed @a payto_uri)
 */
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


/**
 * Obtain the account name from a payto URL.  The format
 * of the @a payto URL is 'payto://x-taler-bank/$HOSTNAME/$ACCOUNT[?PARAMS]'.
 * We check the first part matches, skip over the $HOSTNAME
 * and return the $ACCOUNT portion.
 *
 * @param payto an x-taler-bank payto URL
 * @return only the account name from the @a payto URL, NULL if not an x-taler-bank
 *   payto URL
 */
char *
TALER_xtalerbank_account_from_payto (const char *payto)
{
  const char *beg;
  const char *end;

  if (0 != strncasecmp (payto,
                        PAYTO "x-taler-bank/",
                        strlen (PAYTO "x-taler-bank/")))
    return NULL;
  beg = strchr (&payto[strlen (PAYTO "x-taler-bank/")],
                '/');
  if (NULL == beg)
    return NULL;
  beg++; /* now points to $ACCOUNT */
  end = strchr (beg,
                '?');
  if (NULL == end)
    return GNUNET_strdup (beg); /* optional part is missing */
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
validate_payto_iban (const char *account_url)
{
  const char *iban;
  const char *q;
  char *result;
  char *err;

#define IBAN_PREFIX "payto://iban/"
  if (0 != strncasecmp (account_url,
                        IBAN_PREFIX,
                        strlen (IBAN_PREFIX)))
    return NULL; /* not an IBAN */

  iban = strrchr (account_url, '/') + 1;
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
 * Check that a payto:// URI is well-formed.
 *
 * @param payto_uri the URL to check
 * @return NULL on success, otherwise an error
 *         message to be freed by the caller!
 */
char *
TALER_payto_validate (const char *payto_uri)
{
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
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/:&?-.,="
    if (NULL == strchr (ALLOWED_CHARACTERS,
                        (int) payto_uri[i]))
    {
      char *ret;

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

  if (NULL != (ret = validate_payto_iban (payto_uri)))
    return ret; /* got a definitive answer */

  /* Insert other bank account validation methods here later! */

  return NULL;
}
