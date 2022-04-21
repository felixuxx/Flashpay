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
 * @file include/taler_extensions.h
 * @brief Interface for extensions
 * @author Özgür Kesim
 */
#ifndef TALER_EXTENSIONS_H
#define TALER_EXTENSIONS_H

#include <gnunet/gnunet_util_lib.h>
#include "taler_crypto_lib.h"
#include "taler_json_lib.h"


#define TALER_EXTENSION_SECTION_PREFIX "exchange-extension-"

enum TALER_Extension_Type
{
  TALER_Extension_AgeRestriction = 0,
  TALER_Extension_MaxPredefined = 1 // Must be last of the predefined
};

/*
 * Represents the implementation of an extension.
 * TODO: add documentation
 */
struct TALER_Extension
{
  /* simple linked list */
  struct TALER_Extension *next;

  enum TALER_Extension_Type type;
  char *name;
  bool critical;
  char *version;
  void *config;
  json_t *config_json;

  void (*disable)(struct TALER_Extension *this);

  enum GNUNET_GenericReturnValue (*test_json_config)(
    const json_t *config);

  enum GNUNET_GenericReturnValue (*load_json_config)(
    struct TALER_Extension *this,
    json_t *config);

  json_t *(*config_to_json)(
    const struct TALER_Extension *this);

  enum GNUNET_GenericReturnValue (*load_taler_config)(
    struct TALER_Extension *this,
    const struct GNUNET_CONFIGURATION_Handle *cfg);
};

/**
 * Generic functions for extensions
 */

/*
 * Sets the configuration of the extensions from the given TALER configuration
 *
 * @param cfg Handle to the TALER configuration
 * @return GNUNET_OK on success, GNUNET_SYSERR if unknown extensions were found
 *         or any particular configuration couldn't be parsed.
 */
enum GNUNET_GenericReturnValue
TALER_extensions_load_taler_config (
  const struct GNUNET_CONFIGURATION_Handle *cfg);

/*
 * Check the given obj to be a valid extension object and fill the fields
 * accordingly.
 */
enum GNUNET_GenericReturnValue
TALER_extensions_is_json_config (
  json_t *obj,
  int *critical,
  const char **version,
  json_t **config);

/*
 * Sets the configuration of the extensions from a given JSON object.
 *
 * he JSON object must be of type ExchangeKeysResponse as described in
 * https://docs.taler.net/design-documents/006-extensions.html#exchange
 *
 * @param cfg JSON object containting the configuration for all extensions
 * @return GNUNET_OK on success, GNUNET_SYSERR if unknown extensions were found
 *         or any particular configuration couldn't be parsed.
 */
enum GNUNET_GenericReturnValue
TALER_extensions_load_json_config (
  json_t *cfg);

/*
 * Returns the head of the linked list of extensions
 */
const struct TALER_Extension *
TALER_extensions_get_head ();

/*
 * Adds an extension to the linked list of extensions
 *
 * @param new_extension the new extension to be added
 * @return GNUNET_OK on success, GNUNET_SYSERR if the extension is invalid
 * (missing fields), GNUNET_NO if there is already an extension with that name
 * or type.
 */
enum GNUNET_GenericReturnValue
TALER_extensions_add (
  const struct TALER_Extension *new_extension);

/**
 * Finds and returns a supported extension by a given type.
 *
 * @param type type of the extension to lookup
 * @return extension found, or NULL (should not happen!)
 */
const struct TALER_Extension *
TALER_extensions_get_by_type (
  enum TALER_Extension_Type type);


/**
 * Finds and returns a supported extension by a given name.
 *
 * @param name name of the extension to lookup
 * @return the extension, if found, NULL otherwise
 */
const struct TALER_Extension *
TALER_extensions_get_by_name (
  const char *name);

#define TALER_extensions_is_enabled(ext) (NULL != (ext)->config)

/**
 * Check if a given type of an extension is enabled
 *
 * @param type type of to check
 * @return true enabled, false if not enabled, will assert if type is not found.
 */
bool
TALER_extensions_is_enabled_type (
  enum TALER_Extension_Type type);


/*
 * Verify the signature of a given JSON object for extensions with the master
 * key of the exchange.
 *
 * The JSON object must be of type ExchangeKeysResponse as described in
 * https://docs.taler.net/design-documents/006-extensions.html#exchange
 *
 * @param extensions JSON object with the extension configuration
 * @param extensions_sig signature of the hash of the JSON object
 * @param master_pub public key to verify the signature
 * @return GNUNET_OK on success, GNUNET_SYSERR when hashing of the JSON fails
 * and GNUNET_NO if the signature couldn't be verified.
 */
enum GNUNET_GenericReturnValue
TALER_extensions_verify_json_config_signature (
  json_t *extensions,
  struct TALER_MasterSignatureP *extensions_sig,
  struct TALER_MasterPublicKeyP *master_pub);


/*
 * TALER Age Restriction Extension
 */

#define TALER_EXTENSION_SECTION_AGE_RESTRICTION (TALER_EXTENSION_SECTION_PREFIX  \
                                                 "age_restriction")

/**
 * The default age mask represents the age groups
 * 0-7, 8-9, 10-11, 12-13, 14-15, 16-17, 18-20, 21-...
 */
#define TALER_EXTENSION_AGE_RESTRICTION_DEFAULT_AGE_MASK (1 | 1 << 8 | 1 << 10 \
                                                          | 1 << 12 | 1 << 14 \
                                                          | 1 << 16 | 1 << 18 \
                                                          | 1 << 21)
#define TALER_EXTENSION_AGE_RESTRICTION_DEFAULT_AGE_GROUPS "8:10:12:14:16:18:21"

/**
 * @brief Registers the extension for age restriction to the list extensions
 */
enum GNUNET_GenericReturnValue
TALER_extension_age_restriction_register ();

/**
 * @brief Parses a string as a list of age groups.
 *
 * The string must consist of a colon-separated list of increasing integers
 * between 0 and 31.  Each entry represents the beginning of a new age group.
 * F.e. the string "8:10:12:14:16:18:21" parses into the following list of age
 * groups
 *   0-7, 8-9, 10-11, 12-13, 14-15, 16-17, 18-20, 21-...
 * which then is represented as bit mask with the corresponding bits set:
 *   31     24        16        8         0
 *   |      |         |         |         |
 *   oooooooo  oo1oo1o1  o1o1o1o1  ooooooo1
 *
 * @param groups String representation of age groups
 * @param[out] mask Mask representation for age restriction.
 * @return Error, if age groups were invalid, OK otherwise.
 */
enum GNUNET_GenericReturnValue
TALER_parse_age_group_string (
  const char *groups,
  struct TALER_AgeMask *mask);

/**
 * Encodes the age mask into a string, like "8:10:12:14:16:18:21"
 *
 * @param mask Age mask
 * @return String representation of the age mask, allocated by GNUNET_malloc.
 *         Can be used as value in the TALER config.
 */
char *
TALER_age_mask_to_string (
  const struct TALER_AgeMask *mask);

/**
 * Returns true when age restriction is configured and enabled.
 */
bool
TALER_extensions_age_restriction_is_enabled ();

/**
 * Returns true when age restriction is configured (might not be _enabled_,
 * though).
 */
bool
TALER_extensions_age_restriction_is_configured ();

/**
 * Returns the currently set age mask.  Note that even if age restriction is
 * not enabled, the age mask might be have a non-zero value.
 */
struct TALER_AgeMask
TALER_extensions_age_restriction_ageMask ();


/**
 * Returns the amount of age groups defined.  0 means no age restriction
 * enabled.
 */
size_t
TALER_extensions_age_restriction_num_groups ();

/**
 * Parses a JSON object { "age_groups": "a:b:...y:z" }.
 *
 * @param root is the json object
 * @param[out] mask on succes, will contain the age mask
 * @return #GNUNET_OK on success and #GNUNET_SYSERR on failure.
 */
enum GNUNET_GenericReturnValue
TALER_JSON_parse_age_groups (const json_t *root,
                             struct TALER_AgeMask *mask);


/*
 * TODO: Add Peer2Peer Extension
 */

#endif
