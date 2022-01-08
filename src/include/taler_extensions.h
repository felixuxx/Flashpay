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

enum TALER_Extension_ReturnValue
{
  TALER_Extension_OK = 0,
  TALER_Extension_ERROR_PARSING = 1,
  TALER_Extension_ERROR_INVALID = 2,
  TALER_Extension_ERROR_SYS = 3
};

enum TALER_Extension_Type
{
  TALER_Extension_AgeRestriction = 0,
  TALER_Extension_Peer2Peer = 1,
  TALER_Extension_Max = 2 // Must be last
};

/*
 * TODO oec: documentation
 */
struct TALER_Extension
{
  enum TALER_Extension_Type type;
  char *name;
  bool critical;
  void *config;

  enum GNUNET_GenericReturnValue (*test_config)(const json_t *config);
  enum GNUNET_GenericReturnValue (*parse_and_set_config)(struct
                                                         TALER_Extension *this,
                                                         const json_t *config);
  json_t *(*config_to_json)(const struct TALER_Extension *this);
};

/**
 * Generic functions for extensions
 */

/**
 * Finds and returns a supported extension by a given name.
 *
 * @param name name of the extension to lookup
 * @param extensions list of TALER_Extensions as haystack, terminated by an entry of type TALER_Extension_Max
 * @param[out] ext set to the extension, if found, NULL otherwise
 * @return GNUNET_OK if extension was found, GNUNET_NO otherwise
 */
enum GNUNET_GenericReturnValue
TALER_extension_get_by_name (const char *name,
                             const struct TALER_Extension **extensions,
                             const struct TALER_Extension **ext);

/*
 * TALER Age Restriction Extension
 */

#define TALER_EXTENSION_SECTION_AGE_RESTRICTION (TALER_EXTENSION_SECTION_PREFIX  \
                                                 "age_restriction")

/**
 * The default age mask represents the age groups
 * 0-7, 8-9, 10-11, 12-13, 14-15, 16-17, 18-20, 21-...
 */
#define TALER_EXTENSION_DEFAULT_AGE_MASK (1 | 1 << 8 | 1 << 10 | 1 << 12 | 1    \
                                                << 14 | 1 << 16 | 1 << 18 | 1 \
                                                << 21)

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
enum TALER_Extension_ReturnValue
TALER_parse_age_group_string (char *groups,
                              struct TALER_AgeMask *mask);

/**
 * Encodes the age mask into a string, like "8:10:12:14:16:18:21"
 *
 * @param mask Age mask
 * @return String representation of the age mask, allocated by GNUNET_malloc.
 *         Can be used as value in the TALER config.
 */
char *
TALER_age_mask_to_string (const struct TALER_AgeMask *mask);


/**
 * @brief Reads the age groups from the configuration and sets the
 * corresponding age mask.
 *
 * @param cfg
 * @param[out] mask for age restriction, will be set to 0 if age restriction is disabled.
 * @return Error if extension for age restriction was set but age groups were
 *         invalid, OK otherwise.
 */
enum TALER_Extension_ReturnValue
TALER_get_age_mask (const struct GNUNET_CONFIGURATION_Handle *cfg,
                    struct TALER_AgeMask *mask);


/*
 * TALER Peer2Peer Extension
 * TODO oec
 */

#endif
