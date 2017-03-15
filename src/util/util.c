/*
  This file is part of TALER
  Copyright (C) 2014 GNUnet e.V.

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
 * @file util.c
 * @brief Common utility functions; we might choose to move those to GNUnet at some point
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Benedikt Mueller
 */

#include "platform.h"
#include "taler_util.h"
#include <gcrypt.h>


/**
 * Convert a buffer to an 8-character string
 * representative of the contents. This is used
 * for logging binary data when debugging.
 *
 * @param buf buffer to log
 * @param buf_size number of bytes in @a buf
 * @return text representation of buf, valid until next
 *         call to this function
 */
const char *
TALER_b2s (const void *buf,
	   size_t buf_size)
{
  static char ret[9];
  struct GNUNET_HashCode hc;
  char *tmp;

  GNUNET_CRYPTO_hash (buf,
		      buf_size,
		      &hc);
  tmp = GNUNET_STRINGS_data_to_string_alloc (&hc,
					     sizeof (hc));
  memcpy (ret,
	  tmp,
	  8);
  GNUNET_free (tmp);
  ret[8] = '\0';
  return ret;
}


/**
 * Obtain denomination amount from configuration file.
 *
 * @param cfg configuration to use
 * @param section section of the configuration to access
 * @param option option of the configuration to access
 * @param[out] denom set to the amount found in configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_config_get_denom (const struct GNUNET_CONFIGURATION_Handle *cfg,
                        const char *section,
                        const char *option,
                        struct TALER_Amount *denom)
{
  char *str;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             option,
                                             &str))
    return GNUNET_NO;
  if (GNUNET_OK != TALER_string_to_amount (str,
                                           denom))
  {
    GNUNET_free (str);
    return GNUNET_SYSERR;
  }
  GNUNET_free (str);
  return GNUNET_OK;
}




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

  if (GNUNET_OK !=
      TALER_string_to_amount (value,
                              amount))
  {
    FPRINTF (stderr,
             _("Failed to parse amount in option `%s'\n"),
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


/* end of util.c */
