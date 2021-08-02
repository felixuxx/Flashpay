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


/* Country table taken from GNU gettext */

/**
 * Entry in the country table.
 */
struct CountryTableEntry
{
  /**
   * 2-Character international country code.
   */
  const char *code;

  /**
   * Long English name of the country.
   */
  const char *english;
};


/* Keep the following table in sync with gettext.
   WARNING: the entries should stay sorted according to the code */
/**
 * List of country codes.
 */
static const struct CountryTableEntry country_table[] = {
  { "AE", "U.A.E." },
  { "AF", "Afghanistan" },
  { "AL", "Albania" },
  { "AM", "Armenia" },
  { "AN", "Netherlands Antilles" },
  { "AR", "Argentina" },
  { "AT", "Austria" },
  { "AU", "Australia" },
  { "AZ", "Azerbaijan" },
  { "BA", "Bosnia and Herzegovina" },
  { "BD", "Bangladesh" },
  { "BE", "Belgium" },
  { "BG", "Bulgaria" },
  { "BH", "Bahrain" },
  { "BN", "Brunei Darussalam" },
  { "BO", "Bolivia" },
  { "BR", "Brazil" },
  { "BT", "Bhutan" },
  { "BY", "Belarus" },
  { "BZ", "Belize" },
  { "CA", "Canada" },
  { "CG", "Congo" },
  { "CH", "Switzerland" },
  { "CI", "Cote d'Ivoire" },
  { "CL", "Chile" },
  { "CM", "Cameroon" },
  { "CN", "People's Republic of China" },
  { "CO", "Colombia" },
  { "CR", "Costa Rica" },
  { "CS", "Serbia and Montenegro" },
  { "CZ", "Czech Republic" },
  { "DE", "Germany" },
  { "DK", "Denmark" },
  { "DO", "Dominican Republic" },
  { "DZ", "Algeria" },
  { "EC", "Ecuador" },
  { "EE", "Estonia" },
  { "EG", "Egypt" },
  { "ER", "Eritrea" },
  { "ES", "Spain" },
  { "ET", "Ethiopia" },
  { "FI", "Finland" },
  { "FO", "Faroe Islands" },
  { "FR", "France" },
  { "GB", "United Kingdom" },
  { "GD", "Caribbean" },
  { "GE", "Georgia" },
  { "GL", "Greenland" },
  { "GR", "Greece" },
  { "GT", "Guatemala" },
  { "HK", "Hong Kong" },
  { "HK", "Hong Kong S.A.R." },
  { "HN", "Honduras" },
  { "HR", "Croatia" },
  { "HT", "Haiti" },
  { "HU", "Hungary" },
  { "ID", "Indonesia" },
  { "IE", "Ireland" },
  { "IL", "Israel" },
  { "IN", "India" },
  { "IQ", "Iraq" },
  { "IR", "Iran" },
  { "IS", "Iceland" },
  { "IT", "Italy" },
  { "JM", "Jamaica" },
  { "JO", "Jordan" },
  { "JP", "Japan" },
  { "KE", "Kenya" },
  { "KG", "Kyrgyzstan" },
  { "KH", "Cambodia" },
  { "KR", "South Korea" },
  { "KW", "Kuwait" },
  { "KZ", "Kazakhstan" },
  { "LA", "Laos" },
  { "LB", "Lebanon" },
  { "LI", "Liechtenstein" },
  { "LK", "Sri Lanka" },
  { "LT", "Lithuania" },
  { "LU", "Luxembourg" },
  { "LV", "Latvia" },
  { "LY", "Libya" },
  { "MA", "Morocco" },
  { "MC", "Principality of Monaco" },
  { "MD", "Moldava" },
  { "MD", "Moldova" },
  { "ME", "Montenegro" },
  { "MK", "Former Yugoslav Republic of Macedonia" },
  { "ML", "Mali" },
  { "MM", "Myanmar" },
  { "MN", "Mongolia" },
  { "MO", "Macau S.A.R." },
  { "MT", "Malta" },
  { "MV", "Maldives" },
  { "MX", "Mexico" },
  { "MY", "Malaysia" },
  { "NG", "Nigeria" },
  { "NI", "Nicaragua" },
  { "NL", "Netherlands" },
  { "NO", "Norway" },
  { "NP", "Nepal" },
  { "NZ", "New Zealand" },
  { "OM", "Oman" },
  { "PA", "Panama" },
  { "PE", "Peru" },
  { "PH", "Philippines" },
  { "PK", "Islamic Republic of Pakistan" },
  { "PL", "Poland" },
  { "PR", "Puerto Rico" },
  { "PT", "Portugal" },
  { "PY", "Paraguay" },
  { "QA", "Qatar" },
  { "RE", "Reunion" },
  { "RO", "Romania" },
  { "RS", "Serbia" },
  { "RU", "Russia" },
  { "RW", "Rwanda" },
  { "SA", "Saudi Arabia" },
  { "SE", "Sweden" },
  { "SG", "Singapore" },
  { "SI", "Slovenia" },
  { "SK", "Slovak" },
  { "SN", "Senegal" },
  { "SO", "Somalia" },
  { "SR", "Suriname" },
  { "SV", "El Salvador" },
  { "SY", "Syria" },
  { "TH", "Thailand" },
  { "TJ", "Tajikistan" },
  { "TM", "Turkmenistan" },
  { "TN", "Tunisia" },
  { "TR", "Turkey" },
  { "TT", "Trinidad and Tobago" },
  { "TW", "Taiwan" },
  { "TZ", "Tanzania" },
  { "UA", "Ukraine" },
  { "US", "United States" },
  { "UY", "Uruguay" },
  { "VA", "Vatican" },
  { "VE", "Venezuela" },
  { "VN", "Viet Nam" },
  { "YE", "Yemen" },
  { "ZA", "South Africa" },
  { "ZW", "Zimbabwe" }
};


/**
 * Country code comparator function, for binary search with bsearch().
 *
 * @param ptr1 pointer to a `struct table_entry`
 * @param ptr2 pointer to a `struct table_entry`
 * @return result of memcmp()'ing the 2-digit country codes of the entries
 */
static int
cmp_country_code (const void *ptr1,
                  const void *ptr2)
{
  const struct CountryTableEntry *cc1 = ptr1;
  const struct CountryTableEntry *cc2 = ptr2;

  return memcmp (cc1->code,
                 cc2->code,
                 2);
}


/**
 * Validates given IBAN according to the European Banking Standards.  See:
 * http://www.europeanpaymentscouncil.eu/documents/ECBS%20IBAN%20standard%20EBS204_V3.2.pdf
 *
 * @param iban the IBAN number to validate
 * @return NULL if correctly formatted; error message if not
 */
static char *
validate_iban (const char *iban)
{
  char cc[2];
  char ibancpy[35];
  struct CountryTableEntry cc_entry;
  unsigned int len;
  char *nbuf;
  unsigned long long dividend;
  unsigned long long remainder;
  unsigned int i;
  unsigned int j;

  len = strlen (iban);
  if (len > 34)
    return GNUNET_strdup ("IBAN number too long to be valid");
  memcpy (cc, iban, 2);
  memcpy (ibancpy, iban + 4, len - 4);
  memcpy (ibancpy + len - 4, iban, 4);
  ibancpy[len] = '\0';
  cc_entry.code = cc;
  cc_entry.english = NULL;
  if (NULL ==
      bsearch (&cc_entry,
               country_table,
               sizeof (country_table) / sizeof (struct CountryTableEntry),
               sizeof (struct CountryTableEntry),
               &cmp_country_code))
  {
    char *msg;

    GNUNET_asprintf (&msg,
                     "Country code `%c%c' not supported\n",
                     cc[0],
                     cc[1]);
    return msg;
  }
  nbuf = GNUNET_malloc ((len * 2) + 1);
  for (i = 0, j = 0; i < len; i++)
  {
    if (isalpha ((unsigned char) ibancpy[i]))
    {
      if (2 != snprintf (&nbuf[j],
                         3,
                         "%2u",
                         (ibancpy[i] - 'A' + 10)))
      {
        GNUNET_break (0);
        return GNUNET_strdup ("internal invariant violation");
      }
      j += 2;
      continue;
    }
    nbuf[j] = ibancpy[i];
    j++;
  }
  for (j = 0; '\0' != nbuf[j]; j++)
  {
    if (! isdigit ( (unsigned char) nbuf[j]))
    {
      char *msg;

      GNUNET_asprintf (&msg,
                       "digit expected at `%s'",
                       &nbuf[j]);
      GNUNET_free (nbuf);
      return msg;
    }
  }
  GNUNET_assert (sizeof(dividend) >= 8);
  remainder = 0;
  for (unsigned int i = 0; i<j; i += 16)
  {
    int nread;

    if (1 !=
        sscanf (&nbuf[i],
                "%16llu %n",
                &dividend,
                &nread))
    {
      char *msg;

      GNUNET_asprintf (&msg,
                       "wrong input for checksum calculation at `%s'",
                       &nbuf[i]);
      GNUNET_free (nbuf);
      return msg;
    }
    if (0 != remainder)
      dividend += remainder * (pow (10, nread));
    remainder = dividend % 97;
  }
  GNUNET_free (nbuf);
  if (1 != remainder)
    return GNUNET_strdup ("IBAN checksum is wrong");
  return NULL;
}


/**
 * Validate payto://iban/ account URL (only account information,
 * wire subject and amount are ignored).
 *
 * @param account_url URL to parse
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
      (err = validate_iban (result)))
  {
    GNUNET_free (result);
    return err;
  }
  GNUNET_free (result);
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
