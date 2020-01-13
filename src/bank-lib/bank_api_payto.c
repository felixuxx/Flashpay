/*
  This file is part of TALER
  (C) 2015--2020 Taler Systems SA

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
 * @file bank-lib/bank_api_payto.c
 * @brief Functions for parsing payto:// URIs
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_bank_service.h"

/**
 * Maximum legal 'value' for an account number, based on IEEE double (for JavaScript compatibility).
 */
#define MAX_ACCOUNT_NO (1LLU << 52)


/**
 * Release memory allocated in @a acc.
 *
 * @param acc account to free, the pointer itself is NOT free'd.
 */
void
TALER_BANK_account_free (struct TALER_Account *acc)
{
  switch (acc->type)
  {
  case TALER_PAC_NONE:
    return;
  case TALER_PAC_X_TALER_BANK:
    GNUNET_free (acc->details.x_taler_bank.hostname);
    acc->details.x_taler_bank.hostname = NULL;
    GNUNET_free (acc->details.x_taler_bank.account_base_url);
    acc->details.x_taler_bank.account_base_url = NULL;
    break;
  case TALER_PAC_IBAN:
    GNUNET_free (acc->details.iban.number);
    acc->details.iban.number = NULL;
    break;
  }
  acc->type = TALER_PAC_NONE;
}


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
 * @return result of strncmp()'ing the 2-digit country codes of the entries
 */
static int
cmp_country_code (const void *ptr1,
                  const void *ptr2)
{
  const struct CountryTableEntry *cc1 = ptr1;
  const struct CountryTableEntry *cc2 = ptr2;

  return strncmp (cc1->code,
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
  int nread;
  int ret;
  unsigned int i;
  unsigned int j;

  len = strlen (iban);
  if (len > 34)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "IBAN number too long to be valid\n");
    return GNUNET_NO;
  }
  strncpy (cc, iban, 2);
  strncpy (ibancpy, iban + 4, len - 4);
  strncpy (ibancpy + len - 4, iban, 4);
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
    GNUNET_assert (isdigit ( (unsigned char) nbuf[j]));
  GNUNET_assert (sizeof(dividend) >= 8);
  remainder = 0;
  for (unsigned int i = 0; i<j; i += 16)
  {
    if (1 !=
        (ret = sscanf (&nbuf[i],
                       "%16llu %n",
                       &dividend,
                       &nread)))
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
  if (1 == remainder)
    return GNUNET_YES;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "IBAN checksum wrong\n");
  return GNUNET_NO;
}


/**
 * Parse payto://iban/ account URL (only account information,
 * wire subject and amount are ignored).
 *
 * @param account_url URL to parse
 * @param account[out] set to information, can be NULL
 * @return #TALER_EC_NONE if @a account_url is well-formed
 */
static enum TALER_ErrorCode
parse_payto_iban (const char *account_url,
                  struct TALER_Account *account)
{
  const char *iban;
  const char *q;
  char *result;

#define PREFIX "payto://iban/"
  if (0 != strncasecmp (account_url,
                        PREFIX,
                        strlen (PREFIX)))
    return TALER_EC_PAYTO_WRONG_METHOD;
  iban = &account_url[strlen (PREFIX)];
#undef PREFIX
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
    return TALER_EC_PAYTO_MALFORMED;
  }
  if (NULL != account)
  {
    account->type = TALER_PAC_IBAN;
    account->details.iban.number = result;
  }
  else
  {
    GNUNET_free (result);
  }
  return TALER_EC_NONE;
}


/**
 * Parse payto://x-taler-bank/ account URL (only account information,
 * wire subject and amount are ignored).
 *
 * @param account_url URL to parse
 * @param account[out] set to information, can be NULL
 * @return #TALER_EC_NONE if @a account_url is well-formed
 */
static enum TALER_ErrorCode
parse_payto_x_taler_bank (const char *account_url,
                          struct TALER_Account *r_account)
{
  const char *hostname;
  const char *account;
  const char *q;
  unsigned int port;
  char *p;

#define PREFIX "payto://x-taler-bank/"
  if (0 != strncasecmp (account_url,
                        PREFIX,
                        strlen (PREFIX)))
    return TALER_EC_PAYTO_WRONG_METHOD;
  hostname = &account_url[strlen (PREFIX)];
  if (NULL == (account = strchr (hostname,
                                 (unsigned char) '/')))
    return TALER_EC_PAYTO_MALFORMED;
  account++;
  if (NULL == r_account)
    return TALER_EC_NONE;
  q = strchr (account,
              (unsigned char) '?');
  if (0 == q)
    q = account + strlen (account);
  r_account->details.x_taler_bank.hostname
    = GNUNET_strndup (hostname,
                      account - hostname);
  port = 443; /* if non given, equals 443.  */
  if (NULL != (p = strchr (r_account->details.x_taler_bank.hostname,
                           (unsigned char) ':')))
  {
    p++;
    if (1 != sscanf (p,
                     "%u",
                     &port))
    {
      GNUNET_break (0);
      TALER_LOG_ERROR ("Malformed host from payto:// URI\n");
      GNUNET_free (r_account->details.x_taler_bank.hostname);
      r_account->details.x_taler_bank.hostname = NULL;
      return TALER_EC_PAYTO_MALFORMED;
    }
  }
  if (443 != port)
  {
    GNUNET_assert
      (GNUNET_SYSERR != GNUNET_asprintf
        (&r_account->details.x_taler_bank.account_base_url,
        "http://%s/%.*s",
        r_account->details.x_taler_bank.hostname,
        (int) (q - account),
        account));
  }
  else
  {
    GNUNET_assert
      (GNUNET_SYSERR != GNUNET_asprintf
        (&r_account->details.x_taler_bank.account_base_url,
        "https://%s/%.*s",
        r_account->details.x_taler_bank.hostname,
        (int) (q - account),
        account));
  }
  r_account->type = TALER_PAC_X_TALER_BANK;
  return TALER_EC_NONE;
}


typedef enum TALER_ErrorCode
(*Parser)(const char *account_url,
          struct TALER_Account *r_account);

/**
 * Parse @a payto_url and store the result in @a acc
 *
 * @param payto_url URL to parse
 * @param acc[in,out] account to initialize, free using #TALER_BANK_account_free() later
 * @return #TALER_EC_NONE if @a payto_url is well-formed
 */
enum TALER_ErrorCode
TALER_BANK_payto_to_account (const char *payto_url,
                             struct TALER_Account *acc)
{
  Parser parsers[] = {
    &parse_payto_x_taler_bank,
    &parse_payto_iban,
    NULL
  };

  for (unsigned int i = 0; NULL != parsers[i]; i++)
  {
    enum TALER_ErrorCode ec = parsers[i](payto_url,
                                         acc);
    if (TALER_EC_PAYTO_WRONG_METHOD == ec)
      continue;
    return ec;
  }
  return TALER_EC_PAYTO_WRONG_METHOD;
}


/* end of payto.c */
