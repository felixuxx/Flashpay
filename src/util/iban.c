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
 * @file iban.c
 * @brief Common utility function for dealing with IBAN numbers
 * @author Florian Dold
 */
#include "platform.h"
#include "taler_util.h"


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


char *
TALER_iban_validate (const char *iban)
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

  if (NULL == iban)
    return GNUNET_strdup ("(null) is not a valid IBAN");
  len = strlen (iban);
  if (len < 4)
    return GNUNET_strdup ("IBAN number too short to be valid");
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
