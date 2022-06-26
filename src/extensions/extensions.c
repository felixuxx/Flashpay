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
 * @file extensions.c
 * @brief Utility functions for extensions
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_extensions.h"
#include "stdint.h"


/* head of the list of all registered extensions */
static struct TALER_Extension *TE_extensions = NULL;


const struct TALER_Extension *
TALER_extensions_get_head ()
{
  return TE_extensions;
}


enum GNUNET_GenericReturnValue
TALER_extensions_add (
  struct TALER_Extension *extension)
{
  /* Sanity checks */
  if ((NULL == extension) ||
      (NULL == extension->name) ||
      (NULL == extension->version) ||
      (NULL == extension->disable) ||
      (NULL == extension->test_json_config) ||
      (NULL == extension->load_json_config) ||
      (NULL == extension->config_to_json) ||
      (NULL == extension->load_taler_config))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "invalid extension\n");
    return GNUNET_SYSERR;
  }

  if (NULL == TE_extensions) /* first extension ?*/
    TE_extensions = (struct TALER_Extension *) extension;
  else
  {
    struct TALER_Extension *iter;
    struct TALER_Extension *last;

    /* Check for collisions */
    for (iter = TE_extensions; NULL != iter; iter = iter->next)
    {
      last = iter;
      if (extension->type == iter->type ||
          0 == strcasecmp (extension->name,
                           iter->name))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "extension collision for `%s'\n",
                    extension->name);
        return GNUNET_NO;
      }
    }

    /* No collisions found, so add this extension to the list */
    last->next = extension;
  }

  return GNUNET_OK;
}


const struct TALER_Extension *
TALER_extensions_get_by_type (
  enum TALER_Extension_Type type)
{
  for (const struct TALER_Extension *it = TE_extensions;
       NULL != it;
       it = it->next)
  {
    if (it->type == type)
      return it;
  }

  /* No extension found. */
  return NULL;
}


bool
TALER_extensions_is_enabled_type (
  enum TALER_Extension_Type type)
{
  const struct TALER_Extension *ext =
    TALER_extensions_get_by_type (type);

  return (NULL != ext &&
          TALER_extensions_is_enabled (ext));
}


const struct TALER_Extension *
TALER_extensions_get_by_name (
  const char *name)
{
  for (const struct TALER_Extension *it = TE_extensions;
       NULL != it;
       it = it->next)
  {
    if (0 == strcasecmp (name, it->name))
      return it;
  }
  /* No extension found. */
  return NULL;
}


enum GNUNET_GenericReturnValue
TALER_extensions_verify_json_config_signature (
  json_t *extensions,
  struct TALER_MasterSignatureP *extensions_sig,
  struct TALER_MasterPublicKeyP *master_pub)
{
  struct TALER_ExtensionConfigHashP h_config;

  if (GNUNET_OK !=
      TALER_JSON_extensions_config_hash (extensions,
                                         &h_config))
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      TALER_exchange_offline_extension_config_hash_verify (
        &h_config,
        master_pub,
        extensions_sig))
    return GNUNET_NO;
  return GNUNET_OK;
}


/*
 * Closure used in TALER_extensions_load_taler_config during call to
 * GNUNET_CONFIGURATION_iterate_sections with configure_extension.
 */
struct LoadConfClosure
{
  const struct GNUNET_CONFIGURATION_Handle *cfg;
  enum GNUNET_GenericReturnValue error;
};


/*
 * Used in TALER_extensions_load_taler_config during call to
 * GNUNET_CONFIGURATION_iterate_sections to load the configuration
 * of supported extensions.
 *
 * @param cls Closure of type LoadConfClosure
 * @param section name of the current section
 */
static void
configure_extension (
  void *cls,
  const char *section)
{
  struct LoadConfClosure *col = cls;
  const char *name;
  const struct TALER_Extension *extension;

  if (GNUNET_OK != col->error)
    return;

  if (0 != strncasecmp (section,
                        TALER_EXTENSION_SECTION_PREFIX,
                        sizeof(TALER_EXTENSION_SECTION_PREFIX) - 1))
    return;

  name = section + sizeof(TALER_EXTENSION_SECTION_PREFIX) - 1;

  if (NULL ==
      (extension = TALER_extensions_get_by_name (name)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unsupported extension `%s` (section [%s]).\n", name,
                section);
    col->error = GNUNET_SYSERR;
    return;
  }

  if (GNUNET_OK !=
      extension->load_taler_config (
        (struct TALER_Extension *) extension,
        col->cfg))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Couldn't parse configuration for extension `%s` (section [%s]).\n",
                name,
                section);
    col->error = GNUNET_SYSERR;
    return;
  }
}


enum GNUNET_GenericReturnValue
TALER_extensions_load_taler_config (
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct LoadConfClosure col = {
    .cfg = cfg,
    .error = GNUNET_OK,
  };

  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &configure_extension,
                                         &col);
  return col.error;
}


enum GNUNET_GenericReturnValue
TALER_extensions_is_json_config (
  json_t *obj,
  int *critical,
  const char **version,
  json_t **config)
{
  enum GNUNET_GenericReturnValue ret;
  json_t *cfg;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_boolean ("critical",
                              critical),
    GNUNET_JSON_spec_string ("version",
                             version),
    GNUNET_JSON_spec_json ("config",
                           &cfg),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      (ret = GNUNET_JSON_parse (obj,
                                spec,
                                NULL,
                                NULL)))
    return ret;

  *config = json_copy (cfg);
  GNUNET_JSON_parse_free (spec);

  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_extensions_load_json_config (
  json_t *extensions)
{
  const char*name;
  json_t *blob;

  GNUNET_assert (NULL != extensions);
  GNUNET_assert (json_is_object (extensions));

  json_object_foreach (extensions, name, blob)
  {
    int critical;
    const char *version;
    json_t *config;
    const struct TALER_Extension *extension =
      TALER_extensions_get_by_name (name);

    if (NULL == extension)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "no such extension: %s\n", name);
      return GNUNET_SYSERR;
    }

    /* load and verify criticality, version, etc. */
    if (GNUNET_OK !=
        TALER_extensions_is_json_config (
          blob, &critical, &version, &config))
      return GNUNET_SYSERR;

    if (critical != extension->critical
        || 0 != strcmp (version, extension->version) // TODO: libtool compare?
        || NULL == config
        || GNUNET_OK != extension->test_json_config (config))
      return GNUNET_SYSERR;

    /* This _should_ work now */
    if (GNUNET_OK !=
        extension->load_json_config ((struct TALER_Extension *) extension,
                                     config))
      return GNUNET_SYSERR;
  }

  /* make sure to disable all extensions that weren't mentioned in the json */
  for (const struct TALER_Extension *it = TALER_extensions_get_head ();
       NULL != it;
       it = it->next)
  {
    if (NULL == json_object_get (extensions, it->name))
      it->disable ((struct TALER_Extension *) it);
  }

  return GNUNET_OK;
}


bool
TALER_extensions_age_restriction_is_enabled ()
{
  const struct TALER_Extension *age =
    TALER_extensions_get_by_type (TALER_Extension_AgeRestriction);

  return (NULL != age &&
          NULL != age->config_json &&
          TALER_extensions_age_restriction_is_configured ());
}


/* end of extensions.c */
