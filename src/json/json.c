/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016, 2020, 2021 Taler Systems SA

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
 * @file json/json.c
 * @brief helper functions for JSON processing using libjansson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


/**
 * Check if @a json contains a 'real' value anywhere.
 *
 * @param json json to check
 * @return true if a real is in it somewhere
 */
static bool
contains_real (const json_t *json)
{
  if (json_is_real (json))
    return true;
  if (json_is_object (json))
  {
    json_t *member;
    const char *name;

    json_object_foreach ((json_t *) json, name, member)
    if (contains_real (member))
      return true;
    return false;
  }
  if (json_is_array (json))
  {
    json_t *member;
    size_t index;

    json_array_foreach ((json_t *) json, index, member)
    if (contains_real (member))
      return true;
    return false;
  }
  return false;
}


/**
 * Dump the @a json to a string and hash it.
 *
 * @param json value to hash
 * @param salt salt value to include when using HKDF,
 *        NULL to not use any salt and to use SHA512
 * @param[out] hc where to store the hash
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if @a json was not hash-able
 *         #GNUNET_SYSERR on failure
 */
static enum GNUNET_GenericReturnValue
dump_and_hash (const json_t *json,
               const char *salt,
               struct GNUNET_HashCode *hc)
{
  char *wire_enc;
  size_t len;

  if (NULL == json)
  {
    GNUNET_break_op (0);
    return GNUNET_NO;
  }
  if (contains_real (json))
  {
    GNUNET_break_op (0);
    return GNUNET_NO;
  }
  if (NULL == (wire_enc = json_dumps (json,
                                      JSON_ENCODE_ANY
                                      | JSON_COMPACT
                                      | JSON_SORT_KEYS)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  len = strlen (wire_enc) + 1;
  if (NULL == salt)
  {
    GNUNET_CRYPTO_hash (wire_enc,
                        len,
                        hc);
  }
  else
  {
    if (GNUNET_YES !=
        GNUNET_CRYPTO_kdf (hc,
                           sizeof (*hc),
                           salt,
                           strlen (salt) + 1,
                           wire_enc,
                           len,
                           NULL,
                           0))
    {
      GNUNET_break (0);
      free (wire_enc);
      return GNUNET_SYSERR;
    }
  }
  free (wire_enc);
  return GNUNET_OK;
}


/**
 * Replace "forgettable" parts of a JSON object with their salted hash.
 *
 * @param[in] in some JSON value
 * @param[out] out resulting JSON value
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if @a json was not hash-able
 *         #GNUNET_SYSERR on failure
 */
static enum GNUNET_GenericReturnValue
forget (const json_t *in,
        json_t **out)
{
  if (json_is_real (in))
  {
    /* floating point is not allowed! */
    GNUNET_break_op (0);
    return GNUNET_NO;
  }
  if (json_is_array (in))
  {
    /* array is a JSON array */
    size_t index;
    json_t *value;
    json_t *ret;

    ret = json_array ();
    if (NULL == ret)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    json_array_foreach (in, index, value) {
      enum GNUNET_GenericReturnValue iret;
      json_t *t;

      iret = forget (value,
                     &t);
      if (GNUNET_OK != iret)
      {
        json_decref (ret);
        return iret;
      }
      if (0 != json_array_append_new (ret,
                                      t))
      {
        GNUNET_break (0);
        json_decref (ret);
        return GNUNET_SYSERR;
      }
    }
    *out = ret;
    return GNUNET_OK;
  }
  if (json_is_object (in))
  {
    json_t *ret;
    const char *key;
    json_t *value;
    json_t *fg;
    json_t *rx;

    fg = json_object_get (in,
                          "$forgettable");
    rx = json_object_get (in,
                          "$forgotten");
    if (NULL != rx)
    {
      rx = json_deep_copy (rx); /* should be shallow
                                   by structure, but
                                   deep copy is safer */
      if (NULL == rx)
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
    }
    ret = json_object ();
    if (NULL == ret)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    json_object_foreach ((json_t*) in, key, value) {
      json_t *t;
      json_t *salt;
      enum GNUNET_GenericReturnValue iret;

      if (fg == value)
        continue; /* skip! */
      if (rx == value)
        continue; /* skip! */
      if ( (NULL != rx) &&
           (NULL !=
            json_object_get (rx,
                             key)) )
      {
        (void) json_object_del (ret,
                                key);
        continue; /* already forgotten earlier */
      }
      iret = forget (value,
                     &t);
      if (GNUNET_OK != iret)
      {
        json_decref (ret);
        json_decref (rx);
        return iret;
      }
      if ( (NULL != fg) &&
           (NULL != (salt = json_object_get (fg,
                                             key))) )
      {
        /* 't' is to be forgotten! */
        struct GNUNET_HashCode hc;

        if (! json_is_string (salt))
        {
          GNUNET_break_op (0);
          json_decref (ret);
          json_decref (rx);
          json_decref (t);
          return GNUNET_NO;
        }
        iret = dump_and_hash (t,
                              json_string_value (salt),
                              &hc);
        if (GNUNET_OK != iret)
        {
          json_decref (ret);
          json_decref (rx);
          json_decref (t);
          return iret;
        }
        json_decref (t);
        /* scrub salt */
        if (0 !=
            json_object_del (fg,
                             key))
        {
          GNUNET_break_op (0);
          json_decref (ret);
          json_decref (rx);
          return GNUNET_NO;
        }
        if (NULL == rx)
          rx = json_object ();
        if (NULL == rx)
        {
          GNUNET_break (0);
          json_decref (ret);
          return GNUNET_SYSERR;
        }
        if (0 !=
            json_object_set_new (rx,
                                 key,
                                 GNUNET_JSON_from_data_auto (&hc)))
        {
          GNUNET_break (0);
          json_decref (ret);
          json_decref (rx);
          return GNUNET_SYSERR;
        }
      }
      else
      {
        /* 't' to be used without 'forgetting' */
        if (0 !=
            json_object_set_new (ret,
                                 key,
                                 t))
        {
          GNUNET_break (0);
          json_decref (ret);
          json_decref (rx);
          return GNUNET_SYSERR;
        }
      }
    } /* json_object_foreach */
    if ( (NULL != rx) &&
         (0 !=
          json_object_set_new (ret,
                               "$forgotten",
                               rx)) )
    {
      GNUNET_break (0);
      json_decref (ret);
      return GNUNET_SYSERR;
    }
    *out = ret;
    return GNUNET_OK;
  }
  *out = json_incref ((json_t *) in);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_JSON_contract_hash (const json_t *json,
                          struct GNUNET_HashCode *hc)
{
  enum GNUNET_GenericReturnValue ret;
  json_t *cjson;
  json_t *dc;

  dc = json_deep_copy (json);
  ret = forget (dc,
                &cjson);
  json_decref (dc);
  if (GNUNET_OK != ret)
    return ret;
  ret = dump_and_hash (cjson,
                       NULL,
                       hc);
  json_decref (cjson);
  return ret;
}


enum GNUNET_GenericReturnValue
TALER_JSON_contract_mark_forgettable (json_t *json,
                                      const char *field)
{
  json_t *fg;
  struct GNUNET_ShortHashCode salt;

  if (! json_is_object (json))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* check field name is legal for forgettable field */
  for (const char *f = field; '\0' != *f; f++)
  {
    char c = *f;

    if ( (c >= 'a') && (c <= 'z') )
      continue;
    if ( (c >= 'A') && (c <= 'Z') )
      continue;
    if ( (c >= '0') && (c <= '9') )
      continue;
    if ('_' == c)
      continue;
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (NULL == json_object_get (json,
                               field))
  {
    /* field must exist */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  fg = json_object_get (json,
                        "$forgettable");
  if (NULL == fg)
  {
    fg = json_object ();
    if (0 !=
        json_object_set_new (json,
                             "$forgettable",
                             fg))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                              &salt,
                              sizeof (salt));
  if (0 !=
      json_object_set_new (fg,
                           field,
                           GNUNET_JSON_from_data_auto (&salt)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_JSON_contract_part_forget (json_t *json,
                                 const char *field)
{
  json_t *fg;
  const json_t *part;
  json_t *fp;
  json_t *rx;
  struct GNUNET_HashCode hc;
  const char *salt;
  enum GNUNET_GenericReturnValue ret;

  if (! json_is_object (json))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (NULL == (part = json_object_get (json,
                                       field)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Did not find field `%s' we were asked to forget\n",
                field);
    return GNUNET_SYSERR;
  }
  fg = json_object_get (json,
                        "$forgettable");
  if (NULL == fg)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Did not find '$forgettable' attribute trying to forget field `%s'\n",
                field);
    return GNUNET_SYSERR;
  }
  rx = json_object_get (json,
                        "$forgotten");
  if (NULL == rx)
  {
    rx = json_object ();
    if (0 !=
        json_object_set_new (json,
                             "$forgotten",
                             rx))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }
  if (NULL !=
      json_object_get (rx,
                       field))
  {
    if (! json_is_null (json_object_get (json,
                                         field)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Field `%s' market as forgotten, but still exists!\n",
                  field);
      return GNUNET_SYSERR;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Already forgot field `%s'\n",
                field);
    return GNUNET_NO;
  }
  salt = json_string_value (json_object_get (fg,
                                             field));
  if (NULL == salt)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Did not find required salt to forget field `%s'\n",
                field);
    return GNUNET_SYSERR;
  }

  /* need to recursively forget to compute 'hc' */
  ret = forget (part,
                &fp);
  if (GNUNET_OK != ret)
    return ret;
  if (GNUNET_OK !=
      dump_and_hash (fp,
                     salt,
                     &hc))
  {
    json_decref (fp);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  json_decref (fp);
  /* drop salt */
  if (0 !=
      json_object_del (fg,
                       field))
  {
    json_decref (fp);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* remember field as 'forgotten' */
  if (0 !=
      json_object_set_new (rx,
                           field,
                           GNUNET_JSON_from_data_auto (&hc)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* finally, set 'forgotten' field to null */
  if (0 !=
      json_object_del (json,
                       field))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Look over all of the values of a '$forgettable' object.  Replace 'True'
 * values with proper random salts.  Fails if any forgettable values are
 * neither 'True' nor valid salts (strings).
 *
 * @param[in,out] f JSON to transform
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
seed_forgettable (json_t *f)
{
  const char *key;
  json_t *val;

  json_object_foreach (f,
                       key,
                       val)
  {
    if (json_is_string (val))
      continue;
    if (json_is_true (val))
    {
      struct GNUNET_ShortHashCode sh;

      GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                                  &sh,
                                  sizeof (sh));
      json_object_set_new (f,
                           key,
                           GNUNET_JSON_from_data_auto (&sh));
      continue;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Forgettable field `%s' has invalid value\n",
                key);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Take a given contract with "forgettable" fields marked
 * but with 'True' instead of a real salt. Replaces all
 * 'True' values with proper random salts.  Fails if any
 * forgettable markers are neither 'True' nor valid salts.
 *
 * @param[in,out] json JSON to transform
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_JSON_contract_seed_forgettable (json_t *json)
{
  if (json_is_object (json))
  {
    const char *key;
    json_t *val;

    json_object_foreach (json,
                         key,
                         val)
    {
      if (0 == strcmp ("$forgettable",
                       key))
      {
        if (GNUNET_OK !=
            seed_forgettable (val))
          return GNUNET_SYSERR;
        continue;
      }
      if (GNUNET_OK !=
          TALER_JSON_contract_seed_forgettable (val))
        return GNUNET_SYSERR;
    }
  }
  if (json_is_array (json))
  {
    size_t index;
    json_t *val;

    json_array_foreach (json,
                        index,
                        val)
    {
      if (GNUNET_OK !=
          TALER_JSON_contract_seed_forgettable (val))
        return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


/**
 * Parse a json path.
 *
 * @param obj the object that the path is relative to.
 * @param prev the parent of @e obj.
 * @param path the path to parse.
 * @param cb the callback to call, if we get to the end of @e path.
 * @param cb_cls the closure for the callback.
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if @e path is malformed.
 */
static enum GNUNET_GenericReturnValue
parse_path (json_t *obj,
            json_t *prev,
            const char *path,
            TALER_JSON_ExpandPathCallback cb,
            void *cb_cls)
{
  char *id = GNUNET_strdup (path);
  char *next_id = strchr (id,
                          '.');
  char *next_path;
  char *bracket;
  json_t *next_obj = NULL;
  char *next_dot;

  if (NULL == next_id)
  {
    cb (cb_cls,
        id,
        prev);
    GNUNET_free (id);
    return GNUNET_OK;
  }
  bracket = strchr (next_id,
                    '[');
  *next_id = '\0';
  next_id++;
  next_path = GNUNET_strdup (next_id);
  next_dot = strchr (next_id,
                     '.');
  if (NULL != next_dot)
    *next_dot = '\0';
  /* If this is the first time this is called, make sure id is "$" */
  if ( (NULL == prev) &&
       (0 != strcmp (id,
                     "$")))
  {
    GNUNET_free (id);
    GNUNET_free (next_path);
    return GNUNET_SYSERR;
  }

  /* Check for bracketed indices */
  if (NULL != bracket)
  {
    char *end_bracket = strchr (bracket,
                                ']');
    if (NULL == end_bracket)
    {
      GNUNET_free (id);
      GNUNET_free (next_path);
      return GNUNET_SYSERR;
    }
    *end_bracket = '\0';

    *bracket = '\0';
    bracket++;

    json_t *array = json_object_get (obj,
                                     next_id);
    if (0 == strcmp (bracket,
                     "*"))
    {
      size_t index;
      json_t *value;
      int ret = GNUNET_OK;

      json_array_foreach (array, index, value) {
        ret = parse_path (value,
                          obj,
                          next_path,
                          cb,
                          cb_cls);
        if (GNUNET_OK != ret)
        {
          GNUNET_free (id);
          GNUNET_free (next_path);
          return ret;
        }
      }
    }
    else
    {
      unsigned int index;
      char dummy;

      if (1 != sscanf (bracket,
                       "%u%c",
                       &index,
                       &dummy))
      {
        GNUNET_free (id);
        GNUNET_free (next_path);
        return GNUNET_SYSERR;
      }
      next_obj = json_array_get (array,
                                 index);
    }
  }
  else
  {
    /* No brackets, so just fetch the object by name */
    next_obj = json_object_get (obj,
                                next_id);
  }

  if (NULL != next_obj)
  {
    int ret = parse_path (next_obj,
                          obj,
                          next_path,
                          cb,
                          cb_cls);
    GNUNET_free (id);
    GNUNET_free (next_path);
    return ret;
  }
  GNUNET_free (id);
  GNUNET_free (next_path);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_JSON_expand_path (json_t *json,
                        const char *path,
                        TALER_JSON_ExpandPathCallback cb,
                        void *cb_cls)
{
  return parse_path (json,
                     NULL,
                     path,
                     cb,
                     cb_cls);
}


enum TALER_ErrorCode
TALER_JSON_get_error_code (const json_t *json)
{
  const json_t *jc;

  if (NULL == json)
    return TALER_EC_GENERIC_INVALID_RESPONSE;
  jc = json_object_get (json, "code");
  /* The caller already knows that the JSON represents an error,
     so we are dealing with a missing error code here.  */
  if (NULL == jc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Expected Taler error code `code' in JSON, but field does not exist!\n");
    return TALER_EC_INVALID;
  }
  if (json_is_integer (jc))
    return (enum TALER_ErrorCode) json_integer_value (jc);
  GNUNET_break_op (0);
  return TALER_EC_INVALID;
}


const char *
TALER_JSON_get_error_hint (const json_t *json)
{
  const json_t *jc;

  if (NULL == json)
    return NULL;
  jc = json_object_get (json,
                        "hint");
  if (NULL == jc)
    return NULL; /* no hint, is allowed */
  if (! json_is_string (jc))
  {
    /* Hints must be strings */
    GNUNET_break_op (0);
    return NULL;
  }
  return json_string_value (jc);
}


enum TALER_ErrorCode
TALER_JSON_get_error_code2 (const void *data,
                            size_t data_size)
{
  json_t *json;
  enum TALER_ErrorCode ec;
  json_error_t err;

  json = json_loadb (data,
                     data_size,
                     JSON_REJECT_DUPLICATES,
                     &err);
  if (NULL == json)
    return TALER_EC_INVALID;
  ec = TALER_JSON_get_error_code (json);
  json_decref (json);
  if (ec == TALER_EC_NONE)
    return TALER_EC_INVALID;
  return ec;
}


/* End of json/json.c */
