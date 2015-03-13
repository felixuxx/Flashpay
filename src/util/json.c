/*
  This file is part of TALER
  Copyright (C) 2014 Christian Grothoff (and other contributing authors)

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
 * @file util/json.c
 * @brief helper functions for JSON processing using libjansson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"

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
    if (cond) { TALER_JSON_warn (error); goto EXITIF_exit; }            \
  } while (0)


/**
 * Convert a TALER amount to a JSON
 * object.
 *
 * @param amount the amount
 * @return a json object describing the amount
 */
json_t *
TALER_JSON_from_amount (struct TALER_Amount amount)
{
  json_t *j;

  j = json_pack ("{s: s, s:I, s:I}",
                 "currency", amount.currency,
                 "value", (json_int_t) amount.value,
                 "fraction", (json_int_t) amount.fraction);
  GNUNET_assert (NULL != j);
  return j;
}


/**
 * Convert absolute timestamp to a json string.
 *
 * @param the time stamp
 * @return a json string with the timestamp in @a stamp
 */
json_t *
TALER_JSON_from_abs (struct GNUNET_TIME_Absolute stamp)
{
  json_t *j;
  char *mystr;
  int ret;
  ret = GNUNET_asprintf (&mystr, "%llu",
                         (long long) (stamp.abs_value_us / (1000 * 1000)));
  GNUNET_assert (ret > 0);
  j = json_string (mystr);
  GNUNET_free (mystr);
  return j;
}


/**
 * Convert a signature (with purpose) to a JSON object representation.
 *
 * @param purpose purpose of the signature
 * @param signature the signature
 * @return the JSON reporesentation of the signature with purpose
 */
json_t *
TALER_JSON_from_eddsa_sig (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
                           const struct GNUNET_CRYPTO_EddsaSignature *signature)
{
  json_t *root;
  json_t *el;

  root = json_object ();

  el = json_integer ((json_int_t) ntohl (purpose->size));
  json_object_set_new (root, "size", el);

  el = json_integer ((json_int_t) ntohl (purpose->purpose));
  json_object_set_new (root, "purpose", el);

  el = TALER_JSON_from_data (purpose,
                             ntohl (purpose->size));
  json_object_set_new (root, "eddsa-val", el);

  el = TALER_JSON_from_data (signature,
                             sizeof (struct GNUNET_CRYPTO_EddsaSignature));
  json_object_set_new (root, "eddsa-sig", el);

  return root;
}


/**
 * Convert a signature (with purpose) to a JSON object representation.
 *
 * @param purpose purpose of the signature
 * @param signature the signature
 * @return the JSON reporesentation of the signature with purpose
 */
json_t *
TALER_JSON_from_ecdsa_sig (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
                           const struct GNUNET_CRYPTO_EcdsaSignature *signature)
{
  json_t *root;
  json_t *el;

  root = json_object ();

  el = json_integer ((json_int_t) ntohl (purpose->size));
  json_object_set_new (root, "size", el);

  el = json_integer ((json_int_t) ntohl (purpose->purpose));
  json_object_set_new (root, "purpose", el);

  el = TALER_JSON_from_data (purpose,
                             ntohl (purpose->size));
  json_object_set_new (root, "ecdsa-val", el);

  el = TALER_JSON_from_data (signature,
                             sizeof (struct GNUNET_CRYPTO_EddsaSignature));
  json_object_set_new (root, "ecdsa-sig", el);

  return root;
}


/**
 * Convert binary data to a JSON string
 * with the base32crockford encoding.
 *
 * @param data binary data
 * @param size size of @a data in bytes
 * @return json string that encodes @a data
 */
json_t *
TALER_JSON_from_data (const void *data, size_t size)
{
  char *buf;
  json_t *json;

  buf = GNUNET_STRINGS_data_to_string_alloc (data, size);
  json = json_string (buf);
  GNUNET_free (buf);
  return json;
}


/**
 * Convert binary hash to a JSON string with the base32crockford
 * encoding.
 *
 * @param hc binary data
 * @return json string that encodes @a hc
 */
json_t *
TALER_JSON_from_hash (const struct GNUNET_HashCode *hc)
{
  return TALER_JSON_from_data (hc, sizeof (struct GNUNET_HashCode));
}


/**
 * Parse given JSON object to Amount
 *
 * @param json the json object representing Amount
 * @param r_amount where the amount has to be written
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
int
TALER_JSON_to_amount (json_t *json,
                      struct TALER_Amount *r_amount)
{
  char *currency;
  json_int_t value;
  json_int_t fraction;
  json_error_t error;

  UNPACK_EXITIF (0 != json_unpack_ex (json, &error, JSON_STRICT,
                                      "{s:s, s:I, s:I}",
                                      "curreny", &currency,
                                      "value", &value,
                                      "fraction", &fraction));
  EXITIF (3 < strlen (currency));
  r_amount->value = (uint32_t) value;
  r_amount->fraction = (uint32_t) fraction;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
}


/**
 * Parse given JSON object to Amount
 *
 * @param json the json object representing Amount
 * @param r_amount where the amount has to be written
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
int
TALER_JSON_to_abs (json_t *json,
                   struct GNUNET_TIME_Absolute *abs)
{
  const char *str;
  unsigned long long abs_value_s;

  GNUNET_assert (NULL != abs);
  EXITIF (NULL == (str = json_string_value (json)));
  EXITIF (1 > sscanf (str, "%llu", &abs_value_s));
  abs->abs_value_us = abs_value_s * 1000 * 1000;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
}

/**
 * Parse given JSON object to data
 *
 * @param json the json object representing data
 * @param out the pointer to hold the parsed data.
 * @param out_size the size of @a out
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
int
TALER_JSON_to_data (json_t *json,
                    void *out,
                    size_t out_size)
{
  const char *enc;
  unsigned int len;

  EXITIF (NULL == (enc = json_string_value (json)));
  len = strlen (enc);
  EXITIF ((((len * 5) / 8) + ((((len * 5) % 8) == 0) ? 0 : 1)) == out_size);
  EXITIF (GNUNET_OK != GNUNET_STRINGS_string_to_data (enc, len, out, out_size));
  return GNUNET_OK;
 EXITIF_exit:
  return GNUNET_SYSERR;
}

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
TALER_JSON_validate_wireformat (const char *type,
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

/* End of util/json.c */
