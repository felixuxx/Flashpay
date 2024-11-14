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
#include "taler_extensions_policy.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_extensions.h"
#include "stdint.h"

/* head of the list of all registered extensions */
static struct TALER_Extensions TE_extensions = {
  .next = NULL,
  .extension = NULL,
};

const struct TALER_Extensions *
TALER_extensions_get_head ()
{
  return &TE_extensions;
}


static enum GNUNET_GenericReturnValue
add_extension (
  const struct TALER_Extension *extension)
{
  /* Sanity checks */
  if ((NULL == extension) ||
      (NULL == extension->name) ||
      (NULL == extension->version) ||
      (NULL == extension->disable) ||
      (NULL == extension->load_config) ||
      (NULL == extension->manifest))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "invalid extension\n");
    return GNUNET_SYSERR;
  }

  if (NULL == TE_extensions.extension) /* first extension ?*/
    TE_extensions.extension = extension;
  else
  {
    struct TALER_Extensions *iter;
    struct TALER_Extensions *last;

    /* Check for collisions */
    for (iter = &TE_extensions;
         NULL != iter && NULL != iter->extension;
         iter = iter->next)
    {
      const struct TALER_Extension *ext = iter->extension;
      last = iter;
      if (extension->type == ext->type ||
          0 == strcasecmp (extension->name,
                           ext->name))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "extension collision for `%s'\n",
                    extension->name);
        return GNUNET_NO;
      }
    }

    /* No collisions found, so add this extension to the list */
    {
      struct TALER_Extensions *extn = GNUNET_new (struct TALER_Extensions);
      extn->extension = extension;
      last->next = extn;
    }
  }

  return GNUNET_OK;
}


const struct TALER_Extension *
TALER_extensions_get_by_type (
  enum TALER_Extension_Type type)
{
  for (const struct TALER_Extensions *it = &TE_extensions;
       NULL != it && NULL != it->extension;
       it = it->next)
  {
    if (it->extension->type == type)
      return it->extension;
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

  return (NULL != ext && ext->enabled);
}


const struct TALER_Extension *
TALER_extensions_get_by_name (
  const char *name)
{
  for (const struct TALER_Extensions *it = &TE_extensions;
       NULL != it;
       it = it->next)
  {
    if (0 == strcasecmp (name, it->extension->name))
      return it->extension;
  }
  /* No extension found, try to load it. */

  return NULL;
}


enum GNUNET_GenericReturnValue
TALER_extensions_verify_manifests_signature (
  const json_t *manifests,
  struct TALER_MasterSignatureP *extensions_sig,
  struct TALER_MasterPublicKeyP *master_pub)
{
  struct TALER_ExtensionManifestsHashP h_manifests;

  if (GNUNET_OK !=
      TALER_JSON_extensions_manifests_hash (manifests,
                                            &h_manifests))
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      TALER_exchange_offline_extension_manifests_hash_verify (
        &h_manifests,
        master_pub,
        extensions_sig))
    return GNUNET_NO;
  return GNUNET_OK;
}


/**
 * Closure used in TALER_extensions_load_taler_config during call to
 * GNUNET_CONFIGURATION_iterate_sections with configure_extension.
 */
struct LoadConfClosure
{
  const struct GNUNET_CONFIGURATION_Handle *cfg;
  enum GNUNET_GenericReturnValue error;
};


/**
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
  char lib_name[1024] = {0};
  struct TALER_Extension *extension;

  if (GNUNET_OK != col->error)
    return;

  if (0 != strncasecmp (section,
                        TALER_EXTENSION_SECTION_PREFIX,
                        sizeof(TALER_EXTENSION_SECTION_PREFIX) - 1))
    return;

  name = section + sizeof(TALER_EXTENSION_SECTION_PREFIX) - 1;


  /* Load the extension library */
  GNUNET_snprintf (lib_name,
                   sizeof(lib_name),
                   "libtaler_extension_%s",
                   name);
  /* Lower-case extension name, config is case-insensitive */
  for (unsigned int i = 0; i < strlen (lib_name); i++)
    lib_name[i] = tolower (lib_name[i]);

  extension = GNUNET_PLUGIN_load (TALER_EXCHANGE_project_data (),
                                  lib_name,
                                  (void *) col->cfg);
  if (NULL == extension)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Couldn't load extension library to `%s` (section [%s]).\n",
                name,
                section);
    col->error = GNUNET_SYSERR;
    return;
  }


  if (GNUNET_OK != add_extension (extension))
  {
    /* TODO: Ignoring return values here */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Couldn't add extension `%s` (section [%s]).\n",
                name,
                section);
    col->error = GNUNET_SYSERR;
    GNUNET_PLUGIN_unload (
      lib_name,
      (void *) col->cfg);
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "extension library '%s' loaded\n",
              lib_name);
}


static bool extensions_loaded = false;

enum GNUNET_GenericReturnValue
TALER_extensions_init (
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct LoadConfClosure col = {
    .cfg = cfg,
    .error = GNUNET_OK,
  };

  if (extensions_loaded)
    return GNUNET_OK;

  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &configure_extension,
                                         &col);

  if (GNUNET_OK == col.error)
    extensions_loaded = true;

  return col.error;
}


enum GNUNET_GenericReturnValue
TALER_extensions_parse_manifest (
  json_t *obj,
  int *critical,
  const char **version,
  json_t **config)
{
  enum GNUNET_GenericReturnValue ret;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_boolean ("critical",
                              critical),
    GNUNET_JSON_spec_string ("version",
                             version),
    GNUNET_JSON_spec_json ("config",
                           config),
    GNUNET_JSON_spec_end ()
  };

  *config = NULL;
  if (GNUNET_OK !=
      (ret = GNUNET_JSON_parse (obj,
                                spec,
                                NULL,
                                NULL)))
    return ret;
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_extensions_load_manifests (
  const json_t *extensions)
{
  const char *name;
  json_t *manifest;

  GNUNET_assert (NULL != extensions);
  GNUNET_assert (json_is_object (extensions));

  json_object_foreach ((json_t *) extensions, name, manifest)
  {
    int critical;
    const char *version;
    json_t *config;
    struct TALER_Extension *extension
      = (struct TALER_Extension *)
        TALER_extensions_get_by_name (name);

    if (NULL == extension)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "no such extension: %s\n",
                  name);
      return GNUNET_SYSERR;
    }

    /* load and verify criticality, version, etc. */
    if (GNUNET_OK !=
        TALER_extensions_parse_manifest (
          manifest,
          &critical,
          &version,
          &config))
      return GNUNET_SYSERR;

    if (critical != extension->critical
        || 0 != strcmp (version,
                        extension->version) // TODO: libtool compare?
        || NULL == config
        || (GNUNET_OK !=
            extension->load_config (config,
                                    NULL)) )
      return GNUNET_SYSERR;

    /* This _should_ work now */
    if (GNUNET_OK !=
        extension->load_config (config,
                                extension))
      return GNUNET_SYSERR;

    extension->enabled = true;
  }

  /* make sure to disable all extensions that weren't mentioned in the json */
  for (const struct TALER_Extensions *it = TALER_extensions_get_head ();
       NULL != it;
       it = it->next)
  {
    if (NULL == json_object_get (extensions, it->extension->name))
      it->extension->disable ((struct TALER_Extension *) it);
  }

  return GNUNET_OK;
}


/**
 * Policy related
 */
static const char *fulfillment2str[] =  {
  [TALER_PolicyFulfillmentInitial]      = "<init>",
  [TALER_PolicyFulfillmentReady]        = "Ready",
  [TALER_PolicyFulfillmentSuccess]      = "Success",
  [TALER_PolicyFulfillmentFailure]      = "Failure",
  [TALER_PolicyFulfillmentTimeout]      = "Timeout",
  [TALER_PolicyFulfillmentInsufficient] = "Insufficient",
};

const char *
TALER_policy_fulfillment_state_str (
  enum TALER_PolicyFulfillmentState state)
{
  GNUNET_assert (TALER_PolicyFulfillmentStateCount > state);
  return fulfillment2str[state];
}


enum GNUNET_GenericReturnValue
TALER_extensions_create_policy_details (
  const char *currency,
  const json_t *policy_options,
  struct TALER_PolicyDetails *details,
  const char **error_hint)
{
  enum GNUNET_GenericReturnValue ret;
  const struct TALER_Extension *extension;
  const json_t *jtype;
  const char *type;

  *error_hint = NULL;

  if ((NULL == policy_options) ||
      (! json_is_object (policy_options)))
  {
    *error_hint = "invalid policy object";
    return GNUNET_SYSERR;
  }

  jtype = json_object_get (policy_options, "type");
  if (NULL == jtype)
  {
    *error_hint = "no type in policy object";
    return GNUNET_SYSERR;
  }

  type = json_string_value (jtype);
  if (NULL == type)
  {
    *error_hint = "invalid type in policy object";
    return GNUNET_SYSERR;
  }

  extension = TALER_extensions_get_by_name (type);
  if ((NULL == extension) ||
      (NULL == extension->create_policy_details))
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Unsupported extension policy '%s' requested\n",
                type);
    return GNUNET_NO;
  }

  /* Set state fields in the policy details to initial values. */
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        &details->accumulated_total));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        &details->policy_fee));
  details->deadline = GNUNET_TIME_UNIT_FOREVER_TS;
  details->fulfillment_state = TALER_PolicyFulfillmentInitial;
  details->no_policy_fulfillment_id = true;
  ret = extension->create_policy_details (currency,
                                          policy_options,
                                          details,
                                          error_hint);
  return ret;

}


/* end of extensions.c */
