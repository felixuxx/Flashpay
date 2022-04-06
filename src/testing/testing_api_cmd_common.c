/*
  This file is part of TALER
  Copyright (C) 2018-2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_common.c
 * @brief common functions for commands
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_testing_lib.h"


enum GNUNET_GenericReturnValue
TALER_TESTING_parse_coin_reference (
  const char *coin_reference,
  char **cref,
  unsigned int *idx)
{
  const char *index;
  char dummy;

  /* We allow command references of the form "$LABEL#$INDEX" or
     just "$LABEL", which implies the index is 0. Figure out
     which one it is. */
  index = strchr (coin_reference, '#');
  if (NULL == index)
  {
    *idx = 0;
    *cref = GNUNET_strdup (coin_reference);
    return GNUNET_OK;
  }
  *cref = GNUNET_strndup (coin_reference,
                          index - coin_reference);
  if (1 != sscanf (index + 1,
                   "%u%c",
                   idx,
                   &dummy))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Numeric index (not `%s') required after `#' in command reference of command in %s:%u\n",
                index,
                __FILE__,
                __LINE__);
    GNUNET_free (*cref);
    *cref = NULL;
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}
