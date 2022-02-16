/*
   This file is part of TALER
   Copyright (C) 2021-2022 Taler Systems SA

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
 * @file extension_age_restriction.c
 * @brief Utility functions regarding age restriction
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_extensions.h"
#include "stdint.h"

/**
 * Carries all the information we need for age restriction
 */
struct age_restriction_config
{
  struct TALER_AgeMask mask;
  size_t num_groups;
};

/**
 * Global config for this extension
 */
static struct age_restriction_config _config = {0};

/**
 * @param groups String representation of the age groups. Must be of the form
 *  a:b:...:n:m
 * with
 *  0 < a < b <...< n < m < 32
 * @param[out] mask Bit representation of the age groups.
 * @return Error if string was invalid, OK otherwise.
 */
enum GNUNET_GenericReturnValue
TALER_parse_age_group_string (
  const char *groups,
  struct TALER_AgeMask *mask)
{

  const char *pos = groups;
  unsigned int prev = 0;
  unsigned int val = 0;
  char c;

  while (*pos)
  {
    c = *pos++;
    if (':' == c)
    {
      if (prev >= val)
        return GNUNET_SYSERR;

      mask->mask |= 1 << val;
      prev = val;
      val = 0;
      continue;
    }

    if ('0'>c || '9'<c)
      return GNUNET_SYSERR;

    val = 10 * val + c - '0';

    if (0>=val || 32<=val)
      return GNUNET_SYSERR;
  }

  if (0>val || 32<=val || prev>=val)
    return GNUNET_SYSERR;

  mask->mask |= (1 << val);
  mask->mask |= 1; // mark zeroth group, too

  return GNUNET_OK;
}


/**
 * Encodes the age mask into a string, like "8:10:12:14:16:18:21"
 *
 * @param mask Age mask
 * @return String representation of the age mask, allocated by GNUNET_malloc.
 *         Can be used as value in the TALER config.
 */
char *
TALER_age_mask_to_string (
  const struct TALER_AgeMask *m)
{
  uint32_t mask = m->mask;
  unsigned int n = 0;
  char *buf = GNUNET_malloc (32 * 3); // max characters possible
  char *pos = buf;

  if (NULL == buf)
  {
    return buf;
  }

  while (mask != 0)
  {
    mask >>= 1;
    n++;
    if (0 == (mask & 1))
    {
      continue;
    }

    if (n > 9)
    {
      *(pos++) = '0' + n / 10;
    }
    *(pos++) = '0' + n % 10;

    if (0 != (mask >> 1))
    {
      *(pos++) = ':';
    }
  }
  return buf;
}


/* ==================================================
 *
 * Age Restriction  TALER_Extension imlementation
 *
 * ==================================================
 */


/**
 * @brief implements the TALER_Extension.disable interface.
 */
void
age_restriction_disable (
  struct TALER_Extension *this)
{
  if (NULL == this)
    return;

  this->config = NULL;

  if (NULL != this->config_json)
  {
    json_decref (this->config_json);
    this->config_json = NULL;
  }

  _config.mask.mask = 0;
  _config.num_groups = 0;
}


/**
 * @brief implements the TALER_Extension.load_taler_config interface.
 * @param cfg Handle to the GNUNET configuration
 * @param[out] enabled Set to true if age restriction is enabled in the config, false otherwise.
 * @param[out] mask Mask for age restriction. Will be 0 if age restriction was not enabled in the config.
 * @return Error if extension for age restriction was set, but age groups were
 *         invalid, OK otherwise.
 */
static enum GNUNET_GenericReturnValue
age_restriction_load_taler_config (
  struct TALER_Extension *this,
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  char *groups = NULL;
  enum GNUNET_GenericReturnValue ret = GNUNET_SYSERR;
  struct TALER_AgeMask mask = {0};

  if ((GNUNET_YES !=
       GNUNET_CONFIGURATION_have_value (cfg,
                                        TALER_EXTENSION_SECTION_AGE_RESTRICTION,
                                        "ENABLED"))
      ||
      (GNUNET_YES !=
       GNUNET_CONFIGURATION_get_value_yesno (cfg,
                                             TALER_EXTENSION_SECTION_AGE_RESTRICTION,
                                             "ENABLED")))
  {
    /* Age restriction is not enabled */
    this->config = NULL;
    this->config_json = NULL;
    return GNUNET_OK;
  }

  /* Age restriction is enabled, extract age groups */
  if ((GNUNET_YES ==
       GNUNET_CONFIGURATION_have_value (cfg,
                                        TALER_EXTENSION_SECTION_AGE_RESTRICTION,
                                        "AGE_GROUPS"))
      &&
      (GNUNET_YES !=
       GNUNET_CONFIGURATION_get_value_string (cfg,
                                              TALER_EXTENSION_SECTION_AGE_RESTRICTION,
                                              "AGE_GROUPS",
                                              &groups)))
    return GNUNET_SYSERR;


  mask.mask = TALER_EXTENSION_AGE_RESTRICTION_DEFAULT_AGE_MASK;
  ret = GNUNET_OK;

  if (groups != NULL)
  {
    ret = TALER_parse_age_group_string (groups, &mask);
    if (GNUNET_OK != ret)
      mask.mask = TALER_EXTENSION_AGE_RESTRICTION_DEFAULT_AGE_MASK;
  }

  if (GNUNET_OK == ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "setting age mask to %x with #groups: %d\n", mask.mask,
                __builtin_popcount (mask.mask) - 1);
    _config.mask.mask = mask.mask;
    _config.num_groups = __builtin_popcount (mask.mask) - 1; /* no underflow, first bit always set */
    this->config = &_config;

    /* Note: we do now have _config set, however this->config_json is NOT set,
     * i.e. the extension is not yet active! For age restriction to become
     * active, load_json_config must have been called. */
  }


  GNUNET_free (groups);
  return ret;
}


/**
 * @brief implements the TALER_Extension.load_json_config interface.
 * @param this if NULL, only tests the configuration
 * @param config the configuration as json
 */
static enum GNUNET_GenericReturnValue
age_restriction_load_json_config (
  struct TALER_Extension *this,
  json_t *jconfig)
{
  struct TALER_AgeMask mask = {0};
  enum GNUNET_GenericReturnValue ret;

  ret = TALER_JSON_parse_age_groups (jconfig, &mask);
  if (GNUNET_OK != ret)
    return ret;

  /* only testing the parser */
  if (this == NULL)
    return GNUNET_OK;

  if (TALER_Extension_AgeRestriction != this->type)
    return GNUNET_SYSERR;

  _config.mask.mask = mask.mask;
  _config.num_groups = 0;

  if (mask.mask > 0)
  {
    /* if the mask is not zero, the first bit MUST be set */
    if (0 == (mask.mask & 1))
      return GNUNET_SYSERR;

    _config.num_groups = __builtin_popcount (mask.mask) - 1;
  }

  this->config = &_config;

  if (NULL != this->config_json)
    json_decref (this->config_json);

  this->config_json = jconfig;

  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "loaded new age restriction config with age groups: %s\n",
              TALER_age_mask_to_string (&mask));

  return GNUNET_OK;
}


/**
 * @brief implements the TALER_Extension.load_json_config interface.
 * @param this if NULL, only tests the configuration
 * @param config the configuration as json
 */
json_t *
age_restriction_config_to_json (
  const struct TALER_Extension *this)
{
  char *mask_str;
  json_t *conf;

  GNUNET_assert (NULL != this);
  GNUNET_assert (NULL != this->config);

  if (NULL != this->config_json)
  {
    return json_copy (this->config_json);
  }

  mask_str = TALER_age_mask_to_string (&_config.mask);
  conf = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("age_groups", mask_str)
    );

  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_bool ("critical", this->critical),
    GNUNET_JSON_pack_string ("version", this->version),
    GNUNET_JSON_pack_object_steal ("config", conf)
    );
}


/**
 * @brief implements the TALER_Extension.test_json_config interface.
 */
static enum GNUNET_GenericReturnValue
age_restriction_test_json_config (
  const json_t *config)
{
  struct TALER_AgeMask mask = {0};

  return TALER_JSON_parse_age_groups (config, &mask);
}


/* The extension for age restriction */
struct TALER_Extension _extension_age_restriction = {
  .next = NULL,
  .type = TALER_Extension_AgeRestriction,
  .name = "age_restriction",
  .critical = false,
  .version = "1",
  .config = NULL,   // disabled per default
  .config_json = NULL,
  .disable = &age_restriction_disable,
  .test_json_config = &age_restriction_test_json_config,
  .load_json_config = &age_restriction_load_json_config,
  .config_to_json = &age_restriction_config_to_json,
  .load_taler_config = &age_restriction_load_taler_config,
};

bool
TALER_extensions_age_restriction_is_configured ()
{
  return (0 != _config.mask.mask);
}


struct TALER_AgeMask
TALER_extensions_age_restriction_ageMask ()
{
  return _config.mask;
}


size_t
TALER_extensions_age_restriction_num_groups ()
{
  return _config.num_groups;
}


enum GNUNET_GenericReturnValue
TALER_JSON_parse_age_groups (const json_t *root,
                             struct TALER_AgeMask *mask)
{
  enum GNUNET_GenericReturnValue ret;
  const char *str;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("age_groups",
                             &str),
    GNUNET_JSON_spec_end ()
  };

  ret = GNUNET_JSON_parse (root,
                           spec,
                           NULL,
                           NULL);
  if (GNUNET_OK == ret)
    TALER_parse_age_group_string (str, mask);

  GNUNET_JSON_parse_free (spec);

  return ret;
}


/* end of extension_age_restriction.c */
