/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_restrictions.c
 * @brief convenience functions related to account restrictions
a * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_exchange_service.h"
#include <regex.h>


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_test_account_allowed (
  const struct TALER_EXCHANGE_WireAccount *account,
  bool check_credit,
  const char *payto_uri)
{
  unsigned int limit
    = check_credit
    ? account->credit_restrictions_length
    : account->debit_restrictions_length;

  /* check wire method matches */
  {
    char *wm1;
    char *wm2;
    bool ok;

    wm1 = TALER_payto_get_method (payto_uri);
    wm2 = TALER_payto_get_method (account->payto_uri);
    ok = (0 == strcmp (wm1,
                       wm2));
    GNUNET_free (wm1);
    GNUNET_free (wm2);
    if (! ok)
      return GNUNET_NO;
  }

  for (unsigned int i = 0; i<limit; i++)
  {
    const struct TALER_EXCHANGE_AccountRestriction *ar
      = check_credit
      ? &account->credit_restrictions[i]
      : &account->debit_restrictions[i];

    switch (ar->type)
    {
    case TALER_EXCHANGE_AR_INVALID:
      GNUNET_break (0);
      return GNUNET_SYSERR;
    case TALER_EXCHANGE_AR_DENY:
      return GNUNET_NO;
    case TALER_EXCHANGE_AR_REGEX:
      {
        regex_t ex;
        bool allowed = false;

        if (0 != regcomp (&ex,
                          ar->details.regex.posix_egrep,
                          REG_NOSUB | REG_EXTENDED))
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
        if (regexec (&ex,
                     payto_uri,
                     0, NULL,
                     REG_STARTEND))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                      "Account `%s' allowed by regex\n",
                      payto_uri);
          allowed = true;
        }
        regfree (&ex);
        if (! allowed)
          return GNUNET_NO;
        break;
      }
    }     /* end switch */
  }     /* end loop over restrictions */
  return GNUNET_YES;
}


void
TALER_EXCHANGE_keys_evaluate_hard_limits (
  const struct TALER_EXCHANGE_Keys *keys,
  enum TALER_KYCLOGIC_KycTriggerEvent event,
  struct TALER_Amount *limit)
{
  for (unsigned int i = 0; i<keys->hard_limits_length; i++)
  {
    const struct TALER_EXCHANGE_AccountLimit *al
      = &keys->hard_limits[i];

    if (event != al->operation_type)
      continue;
    if (al->soft_limit)
      continue;
    if (! TALER_amount_cmp_currency (limit,
                                     &al->threshold))
      continue;
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_min (limit,
                                    limit,
                                    &al->threshold));
  }
}


bool
TALER_EXCHANGE_keys_evaluate_zero_limits (
  const struct TALER_EXCHANGE_Keys *keys,
  enum TALER_KYCLOGIC_KycTriggerEvent event)
{
  for (unsigned int i = 0; i<keys->zero_limits_length; i++)
  {
    const struct TALER_EXCHANGE_ZeroLimitedOperation *zlo
      = &keys->zero_limits[i];

    if (event == zlo->operation_type)
      return true;
  }
  return false;
}
