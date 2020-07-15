/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file json/json_wire.c
 * @brief helper functions to generate or check /wire replies
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


/* Taken from GNU gettext */

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
 * @return #GNUNET_YES if correctly formatted; #GNUNET_NO if not
 */
static int
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
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "IBAN number too long to be valid\n");
    return GNUNET_NO;
  }
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
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Country code `%c%c' not supported\n",
                cc[0],
                cc[1]);
    return GNUNET_NO;
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
        GNUNET_free (nbuf);
        return GNUNET_NO;
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
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "IBAN `%s' didn't convert to numeric format\n",
                  iban);
      return GNUNET_NO;
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
      GNUNET_free (nbuf);
      GNUNET_break_op (0);
      return GNUNET_NO;
    }
    if (0 != remainder)
      dividend += remainder * (pow (10, nread));
    remainder = dividend % 97;
  }
  GNUNET_free (nbuf);
  if (1 != remainder)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "IBAN `%s' has the wrong checksum\n",
                iban);
    return GNUNET_NO;
  }
  return GNUNET_YES;
}


/**
 * Validate payto://iban/ account URL (only account information,
 * wire subject and amount are ignored).
 *
 * @param account_url URL to parse
 * @return #GNUNET_YES if @a account_url is a valid payto://iban URI,
 *         #GNUNET_NO if @a account_url is a payto URI of a different type,
 *         #GNUNET_SYSERR if the IBAN (checksum) is incorrect or this is not a payto://-URI
 */
static int
validate_payto_iban (const char *account_url)
{
  const char *iban;
  const char *q;
  char *result;

#define IBAN_PREFIX "payto://iban/"
  if (0 != strncasecmp (account_url,
                        IBAN_PREFIX,
                        strlen (IBAN_PREFIX)))
    return GNUNET_NO;

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
  if (GNUNET_OK !=
      validate_iban (result))
  {
    GNUNET_free (result);
    return GNUNET_SYSERR;
  }
  GNUNET_free (result);
  return GNUNET_YES;
}


/**
 * Validate payto:// account URL (only account information,
 * wire subject and amount are ignored).
 *
 * @param account_url URL to parse
 * @return #GNUNET_YES if @a account_url is a valid payto://iban URI
 *         #GNUNET_NO if @a account_url  is a payto URI of an unsupported type (but may be valid)
 *         #GNUNET_SYSERR if the account incorrect or this is not a payto://-URI at all
 */
static int
validate_payto (const char *account_url)
{
  int ret;

#define PAYTO_PREFIX "payto://"
  if (0 != strncasecmp (account_url,
                        PAYTO_PREFIX,
                        strlen (PAYTO_PREFIX)))
    return GNUNET_SYSERR; /* not payto */
#undef PAYTO_PREFIX
  if (GNUNET_NO != (ret = validate_payto_iban (account_url)))
  {
    GNUNET_break_op (GNUNET_SYSERR != ret);
    return ret; /* got a definitive answer */
  }
  /* Insert other bank account validation methods here later! */
  return GNUNET_NO;
}


/**
 * Compute the hash of the given wire details.   The resulting
 * hash is what is put into the contract.
 *
 * @param wire_s wire details to hash
 * @param[out] hc set to the hash
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if @a wire_s is malformed
 */
int
TALER_JSON_merchant_wire_signature_hash (const json_t *wire_s,
                                         struct GNUNET_HashCode *hc)
{
  const char *payto_uri;
  const char *salt; /* Current merchant backend will always make the salt
                       a `struct GNUNET_HashCode`, but *we* do not insist
                       on that. */
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri", &payto_uri),
    GNUNET_JSON_spec_string ("salt", &salt),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (wire_s,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Validating `%s'\n",
              payto_uri);
  if (GNUNET_SYSERR == validate_payto (payto_uri))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  TALER_merchant_wire_signature_hash (payto_uri,
                                      salt,
                                      hc);
  return GNUNET_OK;
}


/**
 * Check the signature in @a wire_s.  Also performs rudimentary
 * checks on the account data *if* supported.
 *
 * @param wire_s signed wire information of an exchange
 * @param master_pub master public key of the exchange
 * @return #GNUNET_OK if signature is valid
 */
int
TALER_JSON_exchange_wire_signature_check (
  const json_t *wire_s,
  const struct TALER_MasterPublicKeyP *master_pub)
{
  const char *payto_uri;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri", &payto_uri),
    GNUNET_JSON_spec_fixed_auto ("master_sig", &master_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (wire_s,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  if (GNUNET_SYSERR == validate_payto (payto_uri))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  return TALER_exchange_wire_signature_check (payto_uri,
                                              master_pub,
                                              &master_sig);
}


/**
 * Create a signed wire statement for the given account.
 *
 * @param payto_uri account specification
 * @param master_priv private key to sign with
 * @return NULL if @a payto_uri is malformed
 */
json_t *
TALER_JSON_exchange_wire_signature_make (
  const char *payto_uri,
  const struct TALER_MasterPrivateKeyP *master_priv)
{
  struct TALER_MasterSignatureP master_sig;

  if (GNUNET_SYSERR == validate_payto (payto_uri))
  {
    GNUNET_break_op (0);
    return NULL;
  }

  TALER_exchange_wire_signature_make (payto_uri,
                                      master_priv,
                                      &master_sig);
  return json_pack ("{s:s, s:o}",
                    "payto_uri", payto_uri,
                    "master_sig", GNUNET_JSON_from_data_auto (&master_sig));
}


/**
 * Obtain the wire method associated with the given
 * wire account details.  @a wire_s must contain a payto://-URL
 * under 'payto_uri'.
 *
 * @return NULL on error
 */
char *
TALER_JSON_wire_to_payto (const json_t *wire_s)
{
  json_t *payto_o;
  const char *payto_str;

  payto_o = json_object_get (wire_s,
                             "payto_uri");
  if ( (NULL == payto_o) ||
       (NULL == (payto_str = json_string_value (payto_o))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Malformed wire record encountered: lacks payto://-url\n");
    return NULL;
  }
  if (GNUNET_SYSERR == validate_payto (payto_str))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Malformed wire record encountered: payto URI `%s' invalid\n",
                payto_str);
    return NULL;
  }
  return GNUNET_strdup (payto_str);
}


/**
 * Obtain the wire method associated with the given
 * wire account details.  @a wire_s must contain a payto://-URL
 * under 'url'.
 *
 * @return NULL on error
 */
char *
TALER_JSON_wire_to_method (const json_t *wire_s)
{
  json_t *payto_o;
  const char *payto_str;

  payto_o = json_object_get (wire_s,
                             "payto_uri");
  if ( (NULL == payto_o) ||
       (NULL == (payto_str = json_string_value (payto_o))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Fatally malformed wire record encountered: lacks payto://-url\n");
    return NULL;
  }
  return TALER_payto_get_method (payto_str);
}


/* end of json_wire.c */
