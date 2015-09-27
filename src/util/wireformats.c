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
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"

/**
 * Shorthand for exit jumps.
 */
#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)

/**
 * Shorthand for JSON parsing related exit jumps.
 */
#define UNPACK_EXITIF(cond)                                             \
  do {                                                                  \
    if (cond) { TALER_json_warn (error); goto EXITIF_exit; }            \
  } while (0)


/* Taken from GNU gettext */

/**
 * Entry in the country table.
 */
struct table_entry
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


/**
 * Country code comparator function, for binary search with bsearch().
 *
 * @param ptr1 pointer to a `struct table_entry`
 * @param ptr2 pointer to a `struct table_entry`
 * @return result of strncmp()'ing the 2-digit country codes of the entries
 */
static int
cmp_country_code (const void *ptr1,
                  const void *ptr2)
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
 * @return #GNUNET_YES if correctly formatted; #GNUNET_NO if not
 */
static int
validate_iban (const char *iban)
{
  char cc[2];
  char ibancpy[35];
  struct table_entry cc_entry;
  unsigned int len;
  char *nbuf;
  unsigned int i;
  unsigned int j;
  unsigned long long dividend;
  unsigned long long remainder;
  int nread;
  int ret;

  len = strlen (iban);
  if (len > 34)
    return GNUNET_NO;
  strncpy (cc, iban, 2);
  strncpy (ibancpy, iban + 4, len - 4);
  strncpy (ibancpy + len - 4, iban, 4);
  ibancpy[len] = '\0';
  cc_entry.code = cc;
  cc_entry.english = NULL;
  if (NULL ==
      bsearch (&cc_entry,
               country_table,
               sizeof (country_table) / sizeof (struct table_entry),
               sizeof (struct table_entry),
               &cmp_country_code))
    return GNUNET_NO;
  nbuf = GNUNET_malloc ((len * 2) + 1);
  for (i=0, j=0; i < len; i++)
  {
    if (isalpha ((int) ibancpy[i]))
    {
      EXITIF(2 != snprintf(&nbuf[j],
                           3,
                           "%2u",
                           (ibancpy[i] - 'A' + 10)));
      j += 2;
      continue;
    }
    nbuf[j] = ibancpy[i];
    j++;
  }
  for (j=0;'\0' != nbuf[j];j++)
    GNUNET_assert (isdigit(nbuf[j]));
  GNUNET_assert (sizeof(dividend) >= 8);
  remainder = 0;
  for (i=0; i<j; i+=16)
  {
    EXITIF (1 !=
            (ret = sscanf (&nbuf[i],
                           "%16llu %n",
                           &dividend,
                           &nread)));
    if (0 != remainder)
      dividend += remainder * (pow (10, nread));
    remainder = dividend % 97;
  }
  if (1 == remainder)
  {
    GNUNET_free (nbuf);
    return GNUNET_YES;
  }
 EXITIF_exit:
  GNUNET_free (nbuf);
  return GNUNET_NO;
}


/**
 * Validate SEPA account details.
 *
 * @param wire JSON with the SEPA details
 * @return  #GNUNET_YES if correctly formatted; #GNUNET_NO if not
 */
static int
validate_sepa (const json_t *wire)
{
  json_error_t error;
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
                  "s:s " /* TYPE: sepa */
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
  if (1 != validate_iban (iban))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		"IBAN `%s' invalid\n",
		iban);
    return GNUNET_NO;
  }
  return GNUNET_YES;
 EXITIF_exit:
  return GNUNET_NO;
}


/**
 * Validate TEST account details.  The "test" format is used
 * for testing, so this validator does nothing.
 *
 * @param wire JSON with the TEST details
 * @return  #GNUNET_YES if correctly formatted; #GNUNET_NO if not
 */
static int
validate_test (const json_t *wire)
{
  return GNUNET_YES;
}


/**
 * Handler for a wire format.
 */
struct FormatHandler
{
  /**
   * Type handled by this format handler.
   */
  const char *type;

  /**
   * Function to call to evaluate the format.
   *
   * @param wire the JSON to evaluate
   * @return #GNUNET_YES if correctly formatted; #GNUNET_NO if not
   */
  int (*handler)(const json_t *wire);
};


/**
 * Check if the given wire format JSON object is correctly formatted
 *
 * @param allowed NULL-terminated array of allowed wire format types
 * @param wire the JSON wire format object
 * @return #GNUNET_YES if correctly formatted; #GNUNET_NO if not
 */
int
TALER_json_validate_wireformat (const char **allowed,
				const json_t *wire)
{
  static const struct FormatHandler format_handlers[] = {
    { "SEPA", &validate_sepa },
    { "TEST", &validate_test },
    { NULL, NULL}
  };
  unsigned int i;
  const char *stype;
  json_error_t error;

  UNPACK_EXITIF (0 != json_unpack_ex
                 ((json_t *) wire,
                  &error, 0,
                  "{s:s}",
                  "type", &stype));
  for (i=0;NULL != allowed[i];i++)
    if (0 == strcasecmp (allowed[i],
                         stype))
      break;
  if (NULL == allowed[i])
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Wireformat `%s' does not match mint's allowed formats\n",
                stype);
    return GNUNET_NO;
  }

  for (i=0;NULL != format_handlers[i].type;i++)
    if (0 == strcasecmp (format_handlers[i].type,
                         stype))
      return format_handlers[i].handler (wire);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Wireformat `%s' not supported\n",
              stype);
  return GNUNET_NO;
 EXITIF_exit:
  return GNUNET_NO;
}

/* end of wireformats.c */
