/*
  This file is part of TALER
  Copyright (C) 2018-2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_misc.c
 * @brief non-command functions useful for writing tests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_testing_lib.h"
#include "taler_fakebank_lib.h"


bool
TALER_TESTING_has_in_name (const char *prog,
                           const char *marker)
{
  size_t name_pos;
  size_t pos;

  if (! prog || ! marker)
    return false;

  pos = 0;
  name_pos = 0;
  while (prog[pos])
  {
    if ('/' == prog[pos])
      name_pos = pos + 1;
    pos++;
  }
  if (name_pos == pos)
    return true;
  return (NULL != strstr (prog + name_pos,
                          marker));
}


enum GNUNET_GenericReturnValue
TALER_TESTING_get_credentials (
  const char *cfg_file,
  const char *exchange_account_section,
  enum TALER_TESTING_BankSystem bs,
  struct TALER_TESTING_Credentials *ua)
{
  unsigned long long port;
  char *exchange_payto_uri;

  ua->cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (ua->cfg,
                                 cfg_file))
  {
    GNUNET_break (0);
    GNUNET_CONFIGURATION_destroy (ua->cfg);
    return GNUNET_SYSERR;
  }
  if (0 !=
      strncasecmp (exchange_account_section,
                   "exchange-account-",
                   strlen ("exchange-account-")))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ua->cfg,
                                             exchange_account_section,
                                             "PAYTO_URI",
                                             &exchange_payto_uri))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               exchange_account_section,
                               "PAYTO_URI");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (ua->cfg,
                                             "bank",
                                             "HTTP_PORT",
                                             &port))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "bank",
                               "HTTP_PORT");
    return GNUNET_SYSERR;
  }
  {
    char *csn;

    GNUNET_asprintf (&csn,
                     "exchange-accountcredentials-%s",
                     &exchange_account_section[strlen ("exchange-account-")]);
    if (GNUNET_OK !=
        TALER_BANK_auth_parse_cfg (ua->cfg,
                                   csn,
                                   &ua->ba))
    {
      GNUNET_break (0);
      GNUNET_free (csn);
      return GNUNET_SYSERR;
    }
    GNUNET_free (csn);
  }
  {
    char *csn;

    GNUNET_asprintf (&csn,
                     "admin-accountcredentials-%s",
                     &exchange_account_section[strlen ("exchange-account-")]);
    if (GNUNET_OK !=
        TALER_BANK_auth_parse_cfg (ua->cfg,
                                   csn,
                                   &ua->ba_admin))
    {
      GNUNET_break (0);
      GNUNET_free (csn);
      return GNUNET_SYSERR;
    }
    GNUNET_free (csn);
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ua->cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &ua->exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ua->cfg,
                                             "auditor",
                                             "BASE_URL",
                                             &ua->auditor_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "BASE_URL");
    return GNUNET_SYSERR;
  }

  switch (bs)
  {
  case TALER_TESTING_BS_FAKEBANK:
    ua->exchange_payto
      = exchange_payto_uri;
    ua->user42_payto
      = GNUNET_strdup ("payto://x-taler-bank/localhost/42?receiver-name=42");
    ua->user43_payto
      = GNUNET_strdup ("payto://x-taler-bank/localhost/43?receiver-name=43");
    break;
  case TALER_TESTING_BS_IBAN:
    ua->exchange_payto
      = exchange_payto_uri;
    ua->user42_payto
      = GNUNET_strdup (
          "payto://iban/SANDBOXX/FR7630006000011234567890189?receiver-name=User42");
    ua->user43_payto
      = GNUNET_strdup (
          "payto://iban/SANDBOXX/GB33BUKB20201555555555?receiver-name=User43");
    break;
  }
  return GNUNET_OK;
}


json_t *
TALER_TESTING_make_wire_details (const char *payto)
{
  struct TALER_WireSaltP salt;

  /* salt must be constant for aggregation tests! */
  memset (&salt,
          47,
          sizeof (salt));
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("payto_uri",
                             payto),
    GNUNET_JSON_pack_data_auto ("salt",
                                &salt));
}


/**
 * Remove @a option directory from @a section in @a cfg.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
remove_dir (const struct GNUNET_CONFIGURATION_Handle *cfg,
            const char *section,
            const char *option)
{
  char *dir;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               section,
                                               option,
                                               &dir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               option);
    return GNUNET_SYSERR;
  }
  if (GNUNET_YES ==
      GNUNET_DISK_directory_test (dir,
                                  GNUNET_NO))
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_directory_remove (dir));
  GNUNET_free (dir);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_cleanup_files_cfg (
  void *cls,
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  char *dir;

  (void) cls;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "exchange-offline",
                                               "SECM_TOFU_FILE",
                                               &dir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange-offline",
                               "SECM_TOFU_FILE");
    return GNUNET_SYSERR;
  }
  if ( (0 != unlink (dir)) &&
       (ENOENT != errno) )
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "unlink",
                              dir);
    GNUNET_free (dir);
    return GNUNET_SYSERR;
  }
  GNUNET_free (dir);
  if (GNUNET_OK !=
      remove_dir (cfg,
                  "taler-exchange-secmod-eddsa",
                  "KEY_DIR"))
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      remove_dir (cfg,
                  "taler-exchange-secmod-rsa",
                  "KEY_DIR"))
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


const struct TALER_EXCHANGE_DenomPublicKey *
TALER_TESTING_find_pk (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_Amount *amount,
  bool age_restricted)
{
  struct GNUNET_TIME_Timestamp now;
  struct TALER_EXCHANGE_DenomPublicKey *pk;
  char *str;

  now = GNUNET_TIME_timestamp_get ();
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
  {
    pk = &keys->denom_keys[i];
    if ( (0 == TALER_amount_cmp (amount,
                                 &pk->value)) &&
         (GNUNET_TIME_timestamp_cmp (now,
                                     >=,
                                     pk->valid_from)) &&
         (GNUNET_TIME_timestamp_cmp (now,
                                     <,
                                     pk->withdraw_valid_until)) &&
         (age_restricted == (0 != pk->key.age_mask.bits)) )
      return pk;
  }
  /* do 2nd pass to check if expiration times are to blame for
   * failure */
  str = TALER_amount_to_string (amount);
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
  {
    pk = &keys->denom_keys[i];
    if ( (0 == TALER_amount_cmp (amount,
                                 &pk->value)) &&
         (GNUNET_TIME_timestamp_cmp (now,
                                     <,
                                     pk->valid_from) ||
          GNUNET_TIME_timestamp_cmp (now,
                                     >,
                                     pk->withdraw_valid_until) ) &&
         (age_restricted == (0 != pk->key.age_mask.bits)) )
    {
      GNUNET_log
        (GNUNET_ERROR_TYPE_WARNING,
        "Have denomination key for `%s', but with wrong"
        " expiration range %llu vs [%llu,%llu)\n",
        str,
        (unsigned long long) now.abs_time.abs_value_us,
        (unsigned long long) pk->valid_from.abs_time.abs_value_us,
        (unsigned long long) pk->withdraw_valid_until.abs_time.abs_value_us);
      GNUNET_free (str);
      return NULL;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "No denomination key for amount %s found\n",
              str);
  GNUNET_free (str);
  return NULL;
}


int
TALER_TESTING_wait_httpd_ready (const char *base_url)
{
  char *wget_cmd;
  unsigned int iter;

  GNUNET_asprintf (&wget_cmd,
                   "wget -q -t 1 -T 1 %s -o /dev/null -O /dev/null",
                   base_url); // make sure ends with '/'
  /* give child time to start and bind against the socket */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Waiting for HTTP service to be ready (check with: %s)\n",
              wget_cmd);
  iter = 0;
  do
  {
    if (10 == iter)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to launch HTTP service (or `wget')\n");
      GNUNET_free (wget_cmd);
      return 77;
    }
    sleep (1);
    iter++;
  }
  while (0 != system (wget_cmd));
  GNUNET_free (wget_cmd);
  return 0;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_url_port_free (const char *url)
{
  const char *port;
  long pnum;

  port = strrchr (url,
                  (unsigned char) ':');
  if (NULL == port)
    pnum = 80;
  else
    pnum = strtol (port + 1, NULL, 10);
  if (GNUNET_OK !=
      GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
                                     pnum))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Port %u not available.\n",
                (unsigned int) pnum);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}
