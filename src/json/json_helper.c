/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file json/json_helper.c
 * @brief helper functions to generate specifications to parse
 *        Taler-specific JSON objects with libgnunetjson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


json_t *
TALER_JSON_from_amount (const struct TALER_Amount *amount)
{
  char *amount_str = TALER_amount_to_string (amount);

  GNUNET_assert (NULL != amount_str);
  {
    json_t *j = json_string (amount_str);

    GNUNET_free (amount_str);
    return j;
  }
}


json_t *
TALER_JSON_from_amount_nbo (const struct TALER_AmountNBO *amount)
{
  struct TALER_Amount a;

  TALER_amount_ntoh (&a,
                     amount);
  return TALER_JSON_from_amount (&a);
}


/**
 * Parse given JSON object to Amount
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static int
parse_amount (void *cls,
              json_t *root,
              struct GNUNET_JSON_Specification *spec)
{
  struct TALER_Amount *r_amount = spec->ptr;

  (void) cls;
  if (! json_is_string (root))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_string_to_amount (json_string_value (root),
                              r_amount))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_amount (const char *name,
                        struct TALER_Amount *r_amount)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_amount,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_amount,
    .ptr_size = 0,
    .size_ptr = NULL
  };
  return ret;
}


/**
 * Parse given JSON object to Amount in NBO.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static int
parse_amount_nbo (void *cls,
                  json_t *root,
                  struct GNUNET_JSON_Specification *spec)
{
  struct TALER_AmountNBO *r_amount = spec->ptr;

  (void) cls;
  if (! json_is_string (root))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_string_to_amount_nbo (json_string_value (root),
                                  r_amount))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_amount_nbo (const char *name,
                            struct TALER_AmountNBO *r_amount)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_amount_nbo,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_amount,
    .ptr_size = 0,
    .size_ptr = NULL
  };
  return ret;
}


/**
 * Parse given JSON object to *rounded* absolute time.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static int
parse_abs_time (void *cls,
                json_t *root,
                struct GNUNET_JSON_Specification *spec)
{
  struct GNUNET_TIME_Absolute *abs = spec->ptr;
  json_t *json_t_ms;
  unsigned long long int tval;

  if (! json_is_object (root))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  json_t_ms = json_object_get (root, "t_ms");
  if (json_is_integer (json_t_ms))
  {
    tval = json_integer_value (json_t_ms);
    /* Time is in milliseconds in JSON, but in microseconds in GNUNET_TIME_Absolute */
    abs->abs_value_us = tval * 1000LL;
    if ((abs->abs_value_us) / 1000LL != tval)
    {
      /* Integer overflow */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_TIME_round_abs (abs))
    {
      /* time not rounded */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  }
  if (json_is_string (json_t_ms))
  {
    const char *val;
    val = json_string_value (json_t_ms);
    if ((0 == strcasecmp (val, "never")))
    {
      *abs = GNUNET_TIME_UNIT_FOREVER_ABS;
      return GNUNET_OK;
    }
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_break_op (0);
  return GNUNET_SYSERR;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_absolute_time (const char *name,
                               struct GNUNET_TIME_Absolute *r_time)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_abs_time,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_time,
    .ptr_size = sizeof(struct GNUNET_TIME_Absolute),
    .size_ptr = NULL
  };

  return ret;
}


/**
 * Parse given JSON object to absolute time.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static int
parse_abs_time_nbo (void *cls,
                    json_t *root,
                    struct GNUNET_JSON_Specification *spec)
{
  struct GNUNET_TIME_AbsoluteNBO *abs = spec->ptr;
  struct GNUNET_TIME_Absolute a;
  struct GNUNET_JSON_Specification ispec;

  ispec = *spec;
  ispec.parser = &parse_abs_time;
  ispec.ptr = &a;
  if (GNUNET_OK !=
      parse_abs_time (NULL,
                      root,
                      &ispec))
    return GNUNET_SYSERR;
  *abs = GNUNET_TIME_absolute_hton (a);
  return GNUNET_OK;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_absolute_time_nbo (const char *name,
                                   struct GNUNET_TIME_AbsoluteNBO *r_time)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_abs_time_nbo,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_time,
    .ptr_size = sizeof(struct GNUNET_TIME_AbsoluteNBO),
    .size_ptr = NULL
  };

  return ret;
}


/**
 * Parse given JSON object to relative time.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static int
parse_rel_time (void *cls,
                json_t *root,
                struct GNUNET_JSON_Specification *spec)
{
  struct GNUNET_TIME_Relative *rel = spec->ptr;
  json_t *json_d_ms;
  unsigned long long int tval;

  if (! json_is_object (root))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  json_d_ms = json_object_get (root, "d_ms");
  if (json_is_integer (json_d_ms))
  {
    tval = json_integer_value (json_d_ms);
    /* Time is in milliseconds in JSON, but in microseconds in GNUNET_TIME_Absolute */
    rel->rel_value_us = tval * 1000LL;
    if ((rel->rel_value_us) / 1000LL != tval)
    {
      /* Integer overflow */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_TIME_round_rel (rel))
    {
      /* time not rounded */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  }
  if (json_is_string (json_d_ms))
  {
    const char *val;
    val = json_string_value (json_d_ms);
    if ((0 == strcasecmp (val, "forever")))
    {
      *rel = GNUNET_TIME_UNIT_FOREVER_REL;
      return GNUNET_OK;
    }
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_break_op (0);
  return GNUNET_SYSERR;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_relative_time (const char *name,
                               struct GNUNET_TIME_Relative *r_time)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_rel_time,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_time,
    .ptr_size = sizeof(struct GNUNET_TIME_Relative),
    .size_ptr = NULL
  };

  return ret;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_denomination_public_key (const char *field,
                                         struct TALER_DenominationPublicKey *pk)
{
  return GNUNET_JSON_spec_rsa_public_key (field,
                                          &pk->rsa_public_key);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_denomination_signature (const char *field,
                                        struct TALER_DenominationSignature *sig)
{
  return GNUNET_JSON_spec_rsa_signature (field,
                                         &sig->rsa_signature);
}


/**
 * Closure for #parse_i18n_string.
 */
struct I18nContext
{
  /**
   * Language pattern to match.
   */
  char *lp;

  /**
   * Name of the field to match.
   */
  const char *field;
};


/**
 * Parse given JSON object to internationalized string.
 *
 * @param cls closure, our `struct I18nContext *`
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static int
parse_i18n_string (void *cls,
                   json_t *root,
                   struct GNUNET_JSON_Specification *spec)
{
  struct I18nContext *ctx = cls;
  json_t *i18n;
  json_t *val;

  {
    char *i18nf;

    GNUNET_asprintf (&i18nf,
                     "%s_i18n",
                     ctx->field);
    i18n = json_object_get (root,
                            i18nf);
    GNUNET_free (i18nf);
  }

  val = json_object_get (root,
                         ctx->field);
  if ( (NULL != i18n) &&
       (NULL != ctx->lp) )
  {
    double best = 0.0;
    json_t *pos;
    const char *lang;

    json_object_foreach (i18n, lang, pos)
    {
      double score;

      score = TALER_language_matches (ctx->lp,
                                      lang);
      if (score > best)
      {
        best = score;
        val = pos;
      }
    }
  }

  {
    const char *str;

    str = json_string_value (val);
    if (NULL == str)
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    *(const char **) spec->ptr = str;
  }
  return GNUNET_OK;
}


/**
 * Function called to clean up data from earlier parsing.
 *
 * @param cls closure
 * @param spec our specification entry with data to clean.
 */
static void
i18n_cleaner (void *cls,
              struct GNUNET_JSON_Specification *spec)
{
  struct I18nContext *ctx = cls;

  GNUNET_free (ctx->lp);
  GNUNET_free (ctx);
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_i18n_string (const char *name,
                             const char *language_pattern,
                             const char **strptr)
{
  struct I18nContext *ctx = GNUNET_new (struct I18nContext);
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_i18n_string,
    .cleaner = &i18n_cleaner,
    .cls = ctx,
    .field = NULL, /* we want the main object */
    .ptr = strptr,
    .ptr_size = 0,
    .size_ptr = NULL
  };

  ctx->lp = (NULL != language_pattern) ? GNUNET_strdup (language_pattern) :
            NULL;
  ctx->field = name;
  *strptr = NULL;
  return ret;
}


struct GNUNET_JSON_Specification
TALER_JSON_spec_i18n_str (const char *name,
                          const char **strptr)
{
  const char *lang = getenv ("LANG");
  char *dot;
  char *l;
  struct GNUNET_JSON_Specification ret;

  if (NULL != lang)
  {
    dot = strchr (lang,
                  '.');
    if (NULL == dot)
      l = GNUNET_strdup (lang);
    else
      l = GNUNET_strndup (lang,
                          dot - lang);
  }
  else
  {
    l = NULL;
  }
  ret = TALER_JSON_spec_i18n_string (name,
                                     l,
                                     strptr);
  GNUNET_free (l);
  return ret;
}


/* end of json/json_helper.c */
