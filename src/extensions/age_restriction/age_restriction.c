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
 * @file age_restriction.c
 * @brief Utility functions regarding age restriction
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_extensions.h"
#include "stdint.h"

/* ==================================================
 *
 * Age Restriction  TALER_Extension implementation
 *
 * ==================================================
 */

/**
 * @brief local configuration
 */

static struct TALER_AgeRestrictionConfig AR_config = {0};

/**
 * @brief implements the TALER_Extension.disable interface.
 *
 * @param ext Pointer to the current extension
 */
static void
age_restriction_disable (
  struct TALER_Extension *ext)
{
  if (NULL == ext)
    return;

  ext->enabled = false;
  ext->config = NULL;

  AR_config.mask.bits = 0;
  AR_config.num_groups = 0;
}


/**
 * @brief implements the TALER_Extension.load_config interface.
 *
 * @param ext if NULL, only tests the configuration
 * @param jconfig the configuration as json
 */
static enum GNUNET_GenericReturnValue
age_restriction_load_config (
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

  if (mask.bits > 0)
  {
    /* if the mask is not zero, the first bit MUST be set */
    if (0 == (mask.bits & 1))
      return GNUNET_SYSERR;

    AR_config.mask.bits = mask.bits;
    AR_config.num_groups = __builtin_popcount (mask.bits) - 1;
  }

  ext->config = &AR_config;
  ext->enabled = true;
  json_decref (jconfig);

  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "loaded new age restriction config with age groups: %s\n",
              TALER_age_mask_to_string (&mask));

  return GNUNET_OK;
}


/**
 * @brief implements the TALER_Extension.manifest interface.
 *
 * @param ext if NULL, only tests the configuration
 * @return configuration as json_t* object, maybe NULL
 */
static json_t *
age_restriction_manifest (
  const struct TALER_Extension *ext)
{
  char *mask_str;
  json_t *conf;

  GNUNET_assert (NULL != ext);

  if (NULL == ext->config)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "age restriction not configured");
    return json_null ();
  }

  mask_str = TALER_age_mask_to_string (&AR_config.mask);
  conf = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("age_groups", mask_str)
    );

  free (mask_str);

  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_bool ("critical", ext->critical),
    GNUNET_JSON_pack_string ("version", ext->version),
    GNUNET_JSON_pack_object_steal ("config", conf)
    );
}


/* The extension for age restriction */
struct TALER_Extension TE_age_restriction = {
  .type = TALER_Extension_AgeRestriction,
  .name = "age_restriction",
  .critical = false,
  .version = "1",
  .enabled = false, /* disabled per default */
  .config = NULL,
  .disable = &age_restriction_disable,
  .load_config = &age_restriction_load_config,
  .manifest = &age_restriction_manifest,

  /* This extension is not a policy extension */
  .create_policy_details = NULL,
  .policy_get_handler = NULL,
  .policy_post_handler = NULL,
};


/**
 * @brief implements the init() function for GNUNET_PLUGIN_load
 *
 * @param arg Pointer to the GNUNET_CONFIGURATION_Handle
 * @return pointer to TALER_Extension on success or NULL otherwise.
 */
void *
libtaler_extension_age_restriction_init (void *arg)
{
  const struct GNUNET_CONFIGURATION_Handle *cfg = arg;
  char *groups = NULL;
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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "[age restriction] no section %s found in configuration\n",
                TALER_EXTENSION_SECTION_AGE_RESTRICTION);

    return NULL;
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
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "[age restriction] AGE_GROUPS in %s is not a string\n",
                TALER_EXTENSION_SECTION_AGE_RESTRICTION);

    return NULL;
  }

  mask.bits = TALER_EXTENSION_AGE_RESTRICTION_DEFAULT_AGE_MASK;

  if ((groups != NULL) &&
      (GNUNET_OK != TALER_parse_age_group_string (groups, &mask)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "[age restriction] couldn't parse age groups: '%s'\n",
                groups);
    return NULL;
  }

  AR_config.mask = mask;
  AR_config.num_groups = __builtin_popcount (mask.bits) - 1;   /* no underflow, first bit always set */

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "[age restriction] setting age mask to %s with #groups: %d\n",
              TALER_age_mask_to_string (&AR_config.mask),
              __builtin_popcount (AR_config.mask.bits) - 1);

  TE_age_restriction.config = &AR_config;

  /* Note: we do now have TE_age_restriction_config set, however the extension
   * is not yet enabled! For age restriction to become active, load_config must
   * have been called. */

  GNUNET_free (groups);
  return &TE_age_restriction;
}


/**
 * @brief implements the done() function for GNUNET_PLUGIN_load
 *
 * @param arg unsued
 * @return pointer to TALER_Extension on success or NULL otherwise.
 */
void *
libtaler_extension_age_restriction_done (void *arg)
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "[age restriction] disabling and unloading");
  AR_config.mask.bits = 0;
  AR_config.num_groups = 0;
  return NULL;
}


/* end of age_restriction.c */
