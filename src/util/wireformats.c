/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file util/wireformats.c
 * @brief helper functions for JSON processing using libjansson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"

/* Taken from GNU gettext */
struct table_entry
{
  const char *code;
  const char *english;
};
/* Keep the following table in sync with gettext.
   WARNING: the entries should stay sorted according to the code */
static const struct table_entry country_table[] =
  {
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

static int
cmp_country_code (const void *ptr1, const void *ptr2)
{
  const struct table_entry *cc1 = ptr1;
  const struct table_entry *cc2 = ptr2;

  return strncmp (cc1->code, cc2->code, 2);
}

/**
 * Validates given IBAN according to the European Banking Standards.  See:
 * http://www.europeanpaymentscouncil.eu/documents/ECBS%20IBAN%20standard%20EBS204_V3.2.pdf
 *
 * @param iban the IBAN number to validate
 * @return 1 is validated successfully; 0 if not.
 */
static int
validate_iban (const char *iban)
{
  char cc[2];
  char ibancpy[35];
  struct table_entry cc_entry;
  unsigned int len;
  char *nbuf;
  int i,j;

  len = strlen(iban);
  if (len > 34)
    return 0;
  (void) strncpy (cc, iban, 2);
  (void) strncpy (ibancpy, iban+4, len - 4);
  (void) strncpy (ibancpy + len - 4, iban, 4);
  ibancpy[len] = '\0';
  cc_entry.code = cc;
  cc_entry.english = NULL;
  if (NULL ==
      bsearch (&cc_entry, country_table,
               sizeof(country_table)/sizeof(struct table_entry),
               sizeof (struct table_entry),
               &cmp_country_code))
    return 0;
  nbuf = GNUNET_malloc((len * 2) + 1);
  for (i=0, j=0; i < len; i++)
  {
    if(isalpha(ibancpy[i]))
    {
      EXITIF(2 != snprintf(&nbuf[j], 3, "%2u", (ibancpy[i] - 'A' + 10)));
      j+=2;
      continue;
    }
    nbuf[j] = ibancpy[i];
    j++;
  }
  for (j=0; ;j++)
  {
    if ('\0' == nbuf[j])
      break;
    GNUNET_assert (isdigit(nbuf[j]));
  }
  unsigned long long dividend;
  unsigned long long remainder = 0;
  int nread;
  int ret;
  GNUNET_assert (sizeof(dividend) >= 8);
  for (i=0; i<j; i+=16)
  {
    EXITIF (1 != (ret = sscanf(&nbuf[i], "%16llu %n", &dividend, &nread)));
    if (0 != remainder)
      dividend += remainder * (pow (10, nread));
    remainder = dividend % 97;
  }
  EXITIF (1 != remainder);
  GNUNET_free (nbuf);
  return 1;

 EXITIF_exit:
  GNUNET_free (nbuf);
  return 0;
}

/**
 * Check if the given wire format JSON object is correctly formatted
 *
 * @param type the type of the wire format
 * @param wire the JSON wire format object
 * @return #GNUNET_YES if correctly formatted; #GNUNET_NO if not
 */
int
TALER_json_validate_wireformat (const char *type,
				const json_t *wire)
{
  json_error_t error;

  if (0 == strcasecmp ("SEPA", type))
  {
    const char *type;
    const char *iban;
    const char *name;
    const char *bic;
    const char *edate;
    uint64_t r;
    const char *address;
    UNPACK_EXITIF (0 != json_unpack_ex
                   ((json_t *) wire,
		    &error, JSON_STRICT,
                    "{"
                    "s:s " /* type: "SEPA" */
                    "s:s " /* IBAN: iban */
                    "s:s " /* name: beneficiary name */
                    "s:s " /* BIC: beneficiary bank's BIC */
                    "s:s " /* edate: transfer execution date */
                    "s:i " /* r: random 64-bit integer nounce */
                    "s?s " /* address: address of the beneficiary */
                    "}",
                    "type", &type,
                    "IBAN", &iban,
                    "name", &name,
                    "bic", &bic,
                    "edate", &edate,
                    "r", &r,
                    "address", &address));
    EXITIF (0 != strcmp (type, "SEPA"));
    EXITIF (1 != validate_iban (iban));
    return GNUNET_YES;
  }

 EXITIF_exit:
  return GNUNET_NO;
}

/* end of wireformats.c */
