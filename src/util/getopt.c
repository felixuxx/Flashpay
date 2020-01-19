/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file getopt.c
 * @brief Helper functions for parsing Taler-specific command-line arguments
 * @author Florian Dold
 */
#include "platform.h"
#include "taler_util.h"


/**
 * Set an option with an amount from the command line.  A pointer to
 * this function should be passed as part of the 'struct
 * GNUNET_GETOPT_CommandLineOption' array to initialize options of
 * this type.
 *
 * @param ctx command line processing context
 * @param scls additional closure (will point to the `struct TALER_Amount`)
 * @param option name of the option
 * @param value actual value of the option as a string.
 * @return #GNUNET_OK if parsing the value worked
 */
static int
set_amount (struct GNUNET_GETOPT_CommandLineProcessorContext *ctx,
            void *scls,
            const char *option,
            const char *value)
{
  struct TALER_Amount *amount = scls;

  (void) ctx;
  if (GNUNET_OK !=
      TALER_string_to_amount (value,
                              amount))
  {
    fprintf (stderr,
             _ ("Failed to parse amount in option `%s'\n"),
             option);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * Allow user to specify an amount on the command line.
 *
 * @param shortName short name of the option
 * @param name long name of the option
 * @param argumentHelp help text for the option argument
 * @param description long help text for the option
 * @param[out] amount set to the amount specified at the command line
 */
struct GNUNET_GETOPT_CommandLineOption
TALER_getopt_get_amount (char shortName,
                         const char *name,
                         const char *argumentHelp,
                         const char *description,
                         struct TALER_Amount *amount)
{
  struct GNUNET_GETOPT_CommandLineOption clo = {
    .shortName =  shortName,
    .name = name,
    .argumentHelp = argumentHelp,
    .description = description,
    .require_argument = 1,
    .processor = &set_amount,
    .scls = (void *) amount
  };

  return clo;
}
