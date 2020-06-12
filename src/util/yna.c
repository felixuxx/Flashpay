/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file yna.c
 * @brief Utility functions for yes/no/all filters
 * @author Jonathan Buchanan
 */
#include "platform.h"
#include "taler_util.h"


/**
 * Convert query argument to @a yna value.
 *
 * @param connection connection to take query argument from
 * @param arg argument to try for
 * @param default_val value to assign if the argument is not present
 * @param[out] value to set
 * @return true on success, false if the parameter was malformed
 */
bool
TALER_arg_to_yna (struct MHD_Connection *connection,
                  const char *arg,
                  enum TALER_EXCHANGE_YesNoAll default_val,
                  enum TALER_EXCHANGE_YesNoAll *yna)
{
  const char *str;

  str = MHD_lookup_connection_value (connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     arg);
  if (NULL == str)
  {
    *yna = default_val;
    return true;
  }
  if (0 == strcasecmp (str, "yes"))
  {
    *yna = TALER_EXCHANGE_YNA_YES;
    return true;
  }
  if (0 == strcasecmp (str, "no"))
  {
    *yna = TALER_EXCHANGE_YNA_NO;
    return true;
  }
  if (0 == strcasecmp (str, "all"))
  {
    *yna = TALER_EXCHANGE_YNA_ALL;
    return true;
  }
  return false;
}
