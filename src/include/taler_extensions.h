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
  TALER_Extension_Peer2Peer = 0,
  TALER_Extension_AgeRestriction = 1,
  TALER_Extension_Max = 2
};

struct TALER_Extension
{
  enum TALER_Extension_Type type;
  char *name;
  bool critical;
  void *config;
  size_t config_size;
};

struct TALER_Peer2Peer_Config
{
  // FIXME
};

/**
 * TEH_extensions is the global manifest with the list supported extensions,
 * sorted by TALER_Extension_Type.
 *
 * TODO: Mutex?
 *
 **/
struct TALER_Extension TEH_extensions[TALER_Extension_Max] = {
  [TALER_Extension_Peer2Peer] = {
    .type = TALER_Extension_Peer2Peer,
    .name = "peer2peer",
    .critical = false,
    .config_size = sizeof(struct TALER_Peer2Peer_Config),
  },
  [TALER_Extension_AgeRestriction] = {
    .type = TALER_Extension_AgeRestriction,
    .name = "age_restriction",
    .critical = false,
    .config_size = sizeof(struct TALER_AgeMask),
  },
};


/*
 * TALER Peer2Peer Extension
 * FIXME
 */


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
 * @param groups String representation of age groups, like: "8:10:12:14:16:18:21"
 * @param[out] mask Mask representation for age restriction.
 * @return Error, if age groups were invalid, OK otherwise.
 */
enum TALER_Extension_ReturnValue
TALER_parse_age_group_string (char *groups,
                              struct TALER_AgeMask *mask);

/**
 *
 * @param cfg
 * @param[out] mask for age restriction, will be set to 0 if age restriction is disabled.
 * @return Error if extension for age restriction was set but age groups were
 *         invalid, OK otherwise.
 */
enum TALER_Extension_ReturnValue
TALER_get_age_mask (const struct GNUNET_CONFIGURATION_Handle *cfg,
                    struct TALER_AgeMask *mask);
#endif
