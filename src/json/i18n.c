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
 * @file json/i18n.c
 * @brief helper functions for i18n in JSON processing
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


/**
 * Extract a string from @a object under the field @a field, but respecting
 * the Taler i18n rules and the language preferences expressed in @a
 * language_pattern.
 *
 * Basically, the @a object may optionally contain a sub-object
 * "${field}_i18n" with a map from IETF BCP 47 language tags to a localized
 * version of the string. If this map exists and contains an entry that
 * matches the @a language pattern, that object (usually a string) is
 * returned. If the @a language_pattern does not match any entry, or if the
 * i18n sub-object does not exist, we simply return @a field of @a object
 * (also usually a string).
 *
 * If @a object does not have a member @a field we return NULL (error).
 *
 * @param object the object to extract internationalized
 *        content from
 * @param language_pattern a language preferences string
 *        like "fr-CH, fr;q=0.9, en;q=0.8, *;q=0.1", following
 *        https://tools.ietf.org/html/rfc7231#section-5.3.1
 * @param field name of the field to extract
 * @return NULL on error, otherwise the member from
 *        @a object. Note that the reference counter is
 *        NOT incremented.
 */
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


/* end of i18n.c */
