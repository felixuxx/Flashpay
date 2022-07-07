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
static struct age_restriction_config TE_age_restriction_config = {0};

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

      mask->bits |= 1 << val;
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

  if (32<=val || prev>=val)
    return GNUNET_SYSERR;

  mask->bits |= (1 << val);
  mask->bits |= 1; // mark zeroth group, too

  return GNUNET_OK;
}


char *
TALER_age_mask_to_string (
  const struct TALER_AgeMask *m)
{
  uint32_t bits = m->bits;
  unsigned int n = 0;
  char *buf = GNUNET_malloc (32 * 3); // max characters possible
  char *pos = buf;

  if (NULL == buf)
  {
    return buf;
  }

  while (bits != 0)
  {
    bits >>= 1;
    n++;
    if (0 == (bits & 1))
    {
      continue;
    }

    if (n > 9)
    {
      *(pos++) = '0' + n / 10;
    }
    *(pos++) = '0' + n % 10;

    if (0 != (bits >> 1))
    {
      *(pos++) = ':';
    }
  }
  return buf;
}


/* ==================================================
 *
 * Age Restriction  TALER_Extension implementation
 *
 * ==================================================
 */

/**
 * @brief implements the TALER_Extension.disable interface.
 *
 * @param ext Pointer to the current extension
 */
void
age_restriction_disable (
  struct TALER_Extension *ext)
{
  if (NULL == ext)
    return;

  ext->config = NULL;

  if (NULL != ext->config_json)
  {
    json_decref (ext->config_json);
    ext->config_json = NULL;
  }

  TE_age_restriction_config.mask.bits = 0;
  TE_age_restriction_config.num_groups = 0;
}


/**
 * @brief implements the TALER_Extension.load_taler_config interface.
 *
 * @param ext Pointer to the current extension
 * @param cfg Handle to the GNUNET configuration
 * @return Error if extension for age restriction was set, but age groups were
 *         invalid, OK otherwise.
 */
static enum GNUNET_GenericReturnValue
age_restriction_load_taler_config (
  struct TALER_Extension *ext,
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
    ext->config = NULL;
    ext->config_json = NULL;
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


  mask.bits = TALER_EXTENSION_AGE_RESTRICTION_DEFAULT_AGE_MASK;
  ret = GNUNET_OK;

  if (groups != NULL)
  {
    ret = TALER_parse_age_group_string (groups, &mask);
    if (GNUNET_OK != ret)
      mask.bits = TALER_EXTENSION_AGE_RESTRICTION_DEFAULT_AGE_MASK;
  }

  if (GNUNET_OK == ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "setting age mask to %x with #groups: %d\n", mask.bits,
                __builtin_popcount (mask.bits) - 1);
    TE_age_restriction_config.mask.bits = mask.bits;
    TE_age_restriction_config.num_groups = __builtin_popcount (mask.bits) - 1; /* no underflow, first bit always set */
    ext->config = &TE_age_restriction_config;

    /* Note: we do now have TE_age_restriction_config set, however
     * ext->config_json is NOT set, i.e. the extension is not yet active! For
     * age restriction to become active, load_json_config must have been
     * called. */
  }


  GNUNET_free (groups);
  return ret;
}


/**
 * @brief implements the TALER_Extension.load_json_config interface.
 *
 * @param ext if NULL, only tests the configuration
 * @param jconfig the configuration as json
 */
static enum GNUNET_GenericReturnValue
age_restriction_load_json_config (
  struct TALER_Extension *ext,
  json_t *jconfig)
{
  struct TALER_AgeMask mask = {0};
  enum GNUNET_GenericReturnValue ret;

  ret = TALER_JSON_parse_age_groups (jconfig, &mask);
  if (GNUNET_OK != ret)
    return ret;

  /* only testing the parser */
  if (ext == NULL)
    return GNUNET_OK;

  if (TALER_Extension_AgeRestriction != ext->type)
    return GNUNET_SYSERR;

  TE_age_restriction_config.mask.bits = mask.bits;
  TE_age_restriction_config.num_groups = 0;

  if (mask.bits > 0)
  {
    /* if the mask is not zero, the first bit MUST be set */
    if (0 == (mask.bits & 1))
      return GNUNET_SYSERR;

    TE_age_restriction_config.num_groups = __builtin_popcount (mask.bits) - 1;
  }

  ext->config = &TE_age_restriction_config;

  if (NULL != ext->config_json)
    json_decref (ext->config_json);

  ext->config_json = jconfig;

  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "loaded new age restriction config with age groups: %s\n",
              TALER_age_mask_to_string (&mask));

  return GNUNET_OK;
}


/**
 * @brief implements the TALER_Extension.load_json_config interface.
 *
 * @param ext if NULL, only tests the configuration
 * @return configuration as json_t* object
 */
json_t *
age_restriction_config_to_json (
  const struct TALER_Extension *ext)
{
  char *mask_str;
  json_t *conf;

  GNUNET_assert (NULL != ext);
  GNUNET_assert (NULL != ext->config);

  if (NULL != ext->config_json)
  {
    return json_copy (ext->config_json);
  }

  mask_str = TALER_age_mask_to_string (&TE_age_restriction_config.mask);
  conf = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("age_groups", mask_str)
    );

  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_bool ("critical", ext->critical),
    GNUNET_JSON_pack_string ("version", ext->version),
    GNUNET_JSON_pack_object_steal ("config", conf)
    );
}


/**
 * @brief implements the TALER_Extension.test_json_config interface.
 *
 * @param config configuration as json_t* to test
 * @return #GNUNET_OK on success, #GNUNET_SYSERR otherwise.
 */
static enum GNUNET_GenericReturnValue
age_restriction_test_json_config (
  const json_t *config)
{
  struct TALER_AgeMask mask = {0};

  return TALER_JSON_parse_age_groups (config, &mask);
}


/* The extension for age restriction */
struct TALER_Extension TE_age_restriction = {
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

enum GNUNET_GenericReturnValue
TALER_extension_age_restriction_register ()
{
  return TALER_extensions_add (&TE_age_restriction);
}


bool
TALER_extensions_age_restriction_is_configured ()
{
  return (0 != TE_age_restriction_config.mask.bits);
}


struct TALER_AgeMask
TALER_extensions_age_restriction_ageMask ()
{
  return TE_age_restriction_config.mask;
}


size_t
TALER_extensions_age_restriction_num_groups ()
{
  return TE_age_restriction_config.num_groups;
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
