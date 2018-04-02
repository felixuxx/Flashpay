/*
  This file is part of TALER
  Copyright (C) 2016, 2017, 2018 Taler Systems SA

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
 * @file plugin_wire_ebics.c
 * @brief wire plugin for transfers using SEPA/EBICS
 * @author Florian Dold
 * @author Christian Grothoff
 * @author Sree Harsha Totakura
 */
#include "platform.h"
#include "taler_wire_plugin.h"
#include "taler_signatures.h"
#include <gnunet/gnunet_json_lib.h>


/**
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct EbicsClosure
{

  /**
   * Which currency do we support?
   */
  char *currency;

  /**
   * Configuration we use to lookup account information.
   */
  struct GNUNET_CONFIGURATION_Handle *cfg;

};


/**
 * Round amount DOWN to the amount that can be transferred via the wire
 * method.  For example, Taler may support 0.000001 EUR as a unit of
 * payment, but SEPA only supports 0.01 EUR.  This function would
 * round 0.125 EUR to 0.12 EUR in this case.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param[in,out] amount amount to round down
 * @return #GNUNET_OK on success, #GNUNET_NO if rounding was unnecessary,
 *         #GNUNET_SYSERR if the amount or currency was invalid
 */
static int
ebics_amount_round (void *cls,
                    struct TALER_Amount *amount)
{
  struct EbicsClosure *sc = cls;
  uint32_t delta;

  if (NULL == sc->currency)
    return GNUNET_SYSERR;
  if (0 != strcasecmp (amount->currency,
                       sc->currency))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  delta = amount->fraction % (TALER_AMOUNT_FRAC_BASE / 100);
  if (0 == delta)
    return GNUNET_NO;
  amount->fraction -= delta;
  return GNUNET_OK;
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
static const struct CountryTableEntry country_table[] =
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
  for (i=0, j=0; i < len; i++)
  {
    if (isalpha ((unsigned char) ibancpy[i]))
    {
      if (2 != snprintf(&nbuf[j],
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
  for (j=0;'\0' != nbuf[j];j++)
    GNUNET_assert (isdigit( (unsigned char) nbuf[j]));
  GNUNET_assert (sizeof(dividend) >= 8);
  remainder = 0;
  for (i=0; i<j; i+=16)
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
 * Information about an account extracted from a payto://-URL.
 */
struct Account
{
  /**
   * The IBAN number.
   */
  char *iban;

};


/**
 * Parse payto:// account URL (only account information,
 * wire subject and amount are ignored).
 *
 * @param account_url URL to parse
 * @param account[out] set to information, can be NULL
 * @return #TALER_EC_NONE if @a account_url is well-formed
 */
static enum TALER_ErrorCode
parse_payto (const char *account_url,
             struct Account *account)
{
  const char *iban;
  const char *q;
  char *result;

#define PREFIX "payto://sepa/"
  if (0 != strncasecmp (account_url,
                        PREFIX,
                        strlen (PREFIX)))
    return TALER_EC_PAYTO_WRONG_METHOD;
  iban = &account_url[strlen (PREFIX)];
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
    account->iban = result;
  }
  else
  {
    GNUNET_free (result);
  }
  return TALER_EC_NONE;
}


/**
 * Check if the given payto:// URL is correctly formatted for this plugin
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param account_url the payto:// URL
 * @return #TALER_EC_NONE if correctly formatted
 */
static enum TALER_ErrorCode
ebics_wire_validate (void *cls,
                     const char *account_url)
{
  return parse_payto (account_url,
                      NULL);
}


/**
 * Prepare for exeuction of a wire transfer.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param wire valid wire account information
 * @param amount amount to transfer, already rounded
 * @param exchange_base_url base URL of the exchange (for tracking)
 * @param wtid wire transfer identifier to use
 * @param psc function to call with the prepared data to persist
 * @param psc_cls closure for @a psc
 * @return NULL on failure
 */
static struct TALER_WIRE_PrepareHandle *
ebics_prepare_wire_transfer (void *cls,
                             const char *origin_account_section,
                             const char *destination_account_url,
                             const struct TALER_Amount *amount,
                             const char *exchange_base_url,
                             const struct TALER_WireTransferIdentifierRawP *wtid,
                             TALER_WIRE_PrepareTransactionCallback psc,
                             void *psc_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return NULL;
}


/**
 * Abort preparation of a wire transfer. For example,
 * because we are shutting down.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param pth preparation to cancel
 */
static void
ebics_prepare_wire_transfer_cancel (void *cls,
                                   struct TALER_WIRE_PrepareHandle *pth)
{
  GNUNET_break (0); // FIXME: not implemented
}


/**
 * Execute a wire transfer.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param buf buffer with the prepared execution details
 * @param buf_size number of bytes in @a buf
 * @param cc function to call upon success
 * @param cc_cls closure for @a cc
 * @return NULL on error
 */
static struct TALER_WIRE_ExecuteHandle *
ebics_execute_wire_transfer (void *cls,
                             const char *buf,
                             size_t buf_size,
                             TALER_WIRE_ConfirmationCallback cc,
                             void *cc_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return NULL;
}


/**
 * Abort execution of a wire transfer. For example, because we are
 * shutting down.  Note that if an execution is aborted, it may or
 * may not still succeed. The caller MUST run @e
 * execute_wire_transfer again for the same request as soon as
 * possilbe, to ensure that the request either ultimately succeeds
 * or ultimately fails. Until this has been done, the transaction is
 * in limbo (i.e. may or may not have been committed).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param eh execution to cancel
 */
static void
ebics_execute_wire_transfer_cancel (void *cls,
                                    struct TALER_WIRE_ExecuteHandle *eh)
{
  GNUNET_break (0); // FIXME: not implemented
}


/**
 * Query transfer history of an account.  We use the variable-size
 * @a start_off to indicate which transfers we are interested in as
 * different banking systems may have different ways to identify
 * transfers.  The @a start_off value must thus match the value of
 * a `row_off` argument previously given to the @a hres_cb.  Use
 * NULL to query transfers from the beginning of time (with
 * positive @a num_results) or from the latest committed transfers
 * (with negative @a num_results).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param account_section specifies the configuration section which
 *        identifies the account for which we should get the history
 * @param direction what kinds of wire transfers should be returned
 * @param start_off from which row on do we want to get results, use NULL for the latest; exclusive
 * @param start_off_len number of bytes in @a start_off; must be `sizeof(uint64_t)`.
 * @param num_results how many results do we want; negative numbers to go into the past,
 *                    positive numbers to go into the future starting at @a start_row;
 *                    must not be zero.
 * @param hres_cb the callback to call with the transaction history
 * @param hres_cb_cls closure for the above callback
 */
static struct TALER_WIRE_HistoryHandle *
ebics_get_history (void *cls,
                   const char *account_section,
                   enum TALER_BANK_Direction direction,
                   const void *start_off,
                   size_t start_off_len,
                   int64_t num_results,
                   TALER_WIRE_HistoryResultCallback hres_cb,
                   void *hres_cb_cls)
{
  GNUNET_break (0);
  return NULL;
}


/**
 * Cancel going over the account's history.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param whh operation to cancel
 */
static void
ebics_get_history_cancel (void *cls,
                          struct TALER_WIRE_HistoryHandle *whh)
{
  GNUNET_break (0);
}



/**
 * Context for a rejection operation.
 */
struct TALER_WIRE_RejectHandle
{
  /**
   * Function to call with the result.
   */
  TALER_WIRE_RejectTransferCallback rej_cb;

  /**
   * Closure for @e rej_cb.
   */
  void *rej_cb_cls;

  /**
   * Handle to task for timeout of operation.
   */
  struct GNUNET_SCHEDULER_Task *timeout_task;
};


/**
 * Rejection operation failed with timeout, notify callback
 * and clean up.
 *
 * @param cls closure with `struct TALER_WIRE_RejectHandle`
 */
static void
timeout_reject (void *cls)
{
  struct TALER_WIRE_RejectHandle *rh = cls;

  rh->timeout_task = NULL;
  rh->rej_cb (rh->rej_cb_cls,
              TALER_EC_NOT_IMPLEMENTED /* in the future: TALER_EC_TIMEOUT */);
  GNUNET_free (rh);
}


/**
 * Reject an incoming wire transfer that was obtained from the
 * history. This function can be used to transfer funds back to
 * the sender if the WTID was malformed (i.e. due to a typo).
 *
 * Calling `reject_transfer` twice on the same wire transfer should
 * be idempotent, i.e. not cause the funds to be wired back twice.
 * Furthermore, the transfer should henceforth be removed from the
 * results returned by @e get_history.
 *
 * @param cls plugin's closure
 * @param account_section specifies the configuration section which
 *        identifies the account to use to reject the transfer
 * @param start_off offset of the wire transfer in plugin-specific format
 * @param start_off_len number of bytes in @a start_off
 * @param rej_cb function to call with the result of the operation
 * @param rej_cb_cls closure for @a rej_cb
 * @return handle to cancel the operation
 */
static struct TALER_WIRE_RejectHandle *
ebics_reject_transfer (void *cls,
                       const char *account_section,
                       const void *start_off,
                       size_t start_off_len,
                       TALER_WIRE_RejectTransferCallback rej_cb,
                       void *rej_cb_cls)
{
  struct TALER_WIRE_RejectHandle *rh;

  GNUNET_break (0); /* not implemented, just a stub! */
  rh = GNUNET_new (struct TALER_WIRE_RejectHandle);
  rh->rej_cb = rej_cb;
  rh->rej_cb_cls = rej_cb_cls;
  rh->timeout_task = GNUNET_SCHEDULER_add_now (&timeout_reject,
                                               rh);
  return rh;
}


/**
 * Cancel ongoing reject operation.  Note that the rejection may still
 * proceed. Basically, if this function is called, the rejection may
 * have happened or not.  This function is usually used during shutdown
 * or system upgrades.  At a later point, the application must call
 * @e reject_transfer again for this wire transfer, unless the
 * @e get_history shows that the wire transfer no longer exists.
 *
 * @param cls plugins' closure
 * @param rh operation to cancel
 * @return closure of the callback of the operation
 */
static void *
ebics_reject_transfer_cancel (void *cls,
                              struct TALER_WIRE_RejectHandle *rh)
{
  void *ret = rh->rej_cb_cls;

  GNUNET_SCHEDULER_cancel (rh->timeout_task);
  GNUNET_free (rh);
  return ret;
}


/**
 * Initialize ebics-wire subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_WIRE_Plugin`
 */
void *
libtaler_plugin_wire_ebics_init (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct EbicsClosure *sc;
  struct TALER_WIRE_Plugin *plugin;

  sc = GNUNET_new (struct EbicsClosure);
  sc->cfg = cfg;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "taler",
                                             "CURRENCY",
                                             &sc->currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    GNUNET_free (sc);
    return NULL;
  }
  plugin = GNUNET_new (struct TALER_WIRE_Plugin);
  plugin->cls = sc;
  plugin->method = "sepa";
  plugin->amount_round = &ebics_amount_round;
  plugin->wire_validate = &ebics_wire_validate;
  plugin->prepare_wire_transfer = &ebics_prepare_wire_transfer;
  plugin->prepare_wire_transfer_cancel = &ebics_prepare_wire_transfer_cancel;
  plugin->execute_wire_transfer = &ebics_execute_wire_transfer;
  plugin->execute_wire_transfer_cancel = &ebics_execute_wire_transfer_cancel;
  plugin->get_history = &ebics_get_history;
  plugin->get_history_cancel = &ebics_get_history_cancel;
  plugin->reject_transfer = &ebics_reject_transfer;
  plugin->reject_transfer_cancel = &ebics_reject_transfer_cancel;
  return plugin;
}


/**
 * Shutdown Ebics wire subsystem.
 *
 * @param cls a `struct TALER_WIRE_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_wire_ebics_done (void *cls)
{
  struct TALER_WIRE_Plugin *plugin = cls;
  struct EbicsClosure *sc = plugin->cls;

  GNUNET_free_non_null (sc->currency);
  GNUNET_free (sc);
  GNUNET_free (plugin);
  return NULL;
}

/* end of plugin_wire_ebics.c */
