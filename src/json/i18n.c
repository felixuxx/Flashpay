/*
  This file is part of TALER
  Copyright (C) 2020, 2021 Taler Systems SA

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
 * @file json/i18n.c
 * @brief helper functions for i18n in JSON processing
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


const json_t *
TALER_JSON_extract_i18n (const json_t *object,
                         const char *language_pattern,
                         const char *field)
{
  const json_t *ret;
  json_t *i18n;
  double quality = -1;

  ret = json_object_get (object,
                         field);
  if (NULL == ret)
    return NULL; /* field MUST exist in object */
  {
    char *name;

    GNUNET_asprintf (&name,
                     "%s_i18n",
                     field);
    i18n = json_object_get (object,
                            name);
    GNUNET_free (name);
  }
  if (NULL == i18n)
    return ret;
  {
    const char *key;
    json_t *value;

    json_object_foreach (i18n, key, value) {
      double q = TALER_language_matches (language_pattern,
                                         key);
      if (q > quality)
      {
        quality = q;
        ret = value;
      }
    }
  }
  return ret;
}


bool
TALER_JSON_check_i18n (const json_t *i18n)
{
  const char *field;
  json_t *member;

  if (! json_is_object (i18n))
    return false;
  json_object_foreach ((json_t *) i18n, field, member)
  {
    if (! json_is_string (member))
      return false;
    /* Field name must be either of format "en_UK"
       or just "en"; we do not care about capitalization;
       for syntax, see GNU Gettext manual, including
       appendix A for rare language codes. */
    switch (strlen (field))
    {
    case 0:
    case 1:
      return false;
    case 2:
      if (! isalpha (field[0]))
        return false;
      if (! isalpha (field[1]))
        return false;
      break;
    case 3:
    case 4:
      return false;
    case 5:
      if (! isalpha (field[0]))
        return false;
      if (! isalpha (field[1]))
        return false;
      if ('_' != field[2])
        return false;
      if (! isalpha (field[3]))
        return false;
      if (! isalpha (field[4]))
        return false;
      break;
    case 6:
      if (! isalpha (field[0]))
        return false;
      if (! isalpha (field[1]))
        return false;
      if ('_' != field[2])
        return false;
      if (! isalpha (field[3]))
        return false;
      if (! isalpha (field[4]))
        return false;
      if (! isalpha (field[5]))
        return false;
      break;
    default:
      return false;
    }
  }
  return true;
}


/* end of i18n.c */
