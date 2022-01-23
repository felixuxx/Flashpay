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
    this->config = (void *) (size_t) mask.mask;

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
  json_t *config)
{
  struct TALER_AgeMask mask = {0};
  enum GNUNET_GenericReturnValue ret;

  ret = TALER_JSON_parse_agemask (config, &mask);
  if (GNUNET_OK != ret)
    return ret;

  /* only testing the parser */
  if (this == NULL)
    return GNUNET_OK;

  if (TALER_Extension_AgeRestriction != this->type)
    return GNUNET_SYSERR;

  if (NULL != this->config)
    GNUNET_free (this->config);

  this->config = GNUNET_malloc (sizeof(struct TALER_AgeMask));
  GNUNET_memcpy (this->config, &mask, sizeof(struct TALER_AgeMask));

  if (NULL != this->config_json)
    json_decref (this->config_json);

  this->config_json = config;

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
  struct TALER_AgeMask mask;
  char *mask_str;
  json_t *conf;

  GNUNET_assert (NULL != this);
  GNUNET_assert (NULL != this->config);

  if (NULL != this->config_json)
  {
    return json_copy (this->config_json);
  }

  mask.mask = (uint32_t) (size_t) this->config;
  mask_str = TALER_age_mask_to_string (&mask);
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

  return TALER_JSON_parse_agemask (config, &mask);
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

/* end of extension_age_restriction.c */
