/*
  This file is part of TALER
  Copyright (C) 2016,2018 Taler Systems SA

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
 * @file include/taler_wire_lib.h
 * @brief Interface for loading and unloading wire plugins
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef TALER_WIRE_H
#define TALER_WIRE_H

#include <gnunet/gnunet_util_lib.h>


/**
 * Different account types supported by payto://.
 */
enum TALER_PaytoAccountType
{

  /**
   * Used to indicate an uninitialized struct.
   */
  TALER_PAC_NONE = 0,

  /**
   * Account type of a bank running the x-taler-bank protocol.
   */
  TALER_PAC_X_TALER_BANK,

  /**
   * Account identified by IBAN number.
   */
  TALER_PAC_IBAN
};


/**
 * Information about an account extracted from a payto://-URL.
 */
struct TALER_Account
{

  /**
   * How this the account represented.
   */
  enum TALER_PaytoAccountType type;

  /**
   * Internals depending on @e type.
   */
  union
  {

    /**
     * Taler bank address from x-taler-bank.  Set if
     * @e type is #TALER_AC_X_TALER_BANK.
     */
    struct
    {

      /**
       * Bank account base URL.
       */
      char *account_base_url;

      /**
       * Only the hostname of the bank.
       */
      char *hostname;

    } x_taler_bank;

    /**
     * Taler bank address from iban.  Set if
     * @e type is #TALER_AC_IBAN.
     */
    struct
    {

      /**
       * IBAN number.
       */
      char *number;

    } iban;

  } details;
};


/**
 * Release memory allocated in @a acc.
 *
 * @param acc account to free, the pointer itself is NOT free'd.
 */
void
TALER_WIRE_account_free (struct TALER_Account *acc);


/**
 * Round the amount to something that can be
 * transferred on the wire.
 *
 * @param[in,out] amount amount to round down
 * @return #GNUNET_OK on success, #GNUNET_NO if rounding was unnecessary,
 *         #GNUNET_SYSERR if the amount or currency was invalid
 */
int
TALER_WIRE_amount_round (struct TALER_Amount *amount);


/**
 * Parse @a payto_url and store the result in @a acc
 *
 * @param payto_url URL to parse
 * @param acc[in,out] account to initialize, free using #TALER_WIRE_account_free() later
 * @return #TALER_EC_NONE if @a payto_url is well-formed
 */
enum TALER_ErrorCode
TALER_WIRE_payto_to_account (const char *payto_url,
                             struct TALER_Account *acc);


/**
 * Obtain the payment method from a @a payto_url
 *
 * @param payto_url the URL to parse
 * @return NULL on error (malformed @a payto_url)
 */
char *
TALER_WIRE_payto_get_method (const char *payto_url);


#endif
