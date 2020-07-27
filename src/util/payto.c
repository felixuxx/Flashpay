/*
  This file is part of TALER
  Copyright (C) 2019-2020 Taler Systems SA

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
 * Extract the subject value from the URI parameters.
 *
 * @param payto_uri the URL to parse
 * @return NULL if the subject parameter is not found.
 *         The caller should free the returned value.
 */
char *
TALER_payto_get_subject (const char *payto_uri)
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
			  "subject",
			  strlen ("subject")))
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
