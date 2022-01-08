/*
   This file is part of TALER
   Copyright (C) 2014-2020 Taler Systems SA

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
 *
 * @param cfg Handle to the GNUNET configuration
 * @param[out] Mask for age restriction. Will be 0 if age restriction was not enabled in the config.
 * @return Error if extension for age restriction was set, but age groups were
 *         invalid, OK otherwise.
 */
enum TALER_Extension_ReturnValue
TALER_get_age_mask (const struct GNUNET_CONFIGURATION_Handle *cfg,
                    struct TALER_AgeMask *mask)
{
  char *groups;
  enum TALER_Extension_ReturnValue ret = TALER_Extension_ERROR_SYS;

  if ((GNUNET_YES != GNUNET_CONFIGURATION_have_value (cfg,
                                                      TALER_EXTENSION_SECTION_AGE_RESTRICTION,
                                                      "ENABLED")) ||
      (GNUNET_YES != GNUNET_CONFIGURATION_get_value_yesno (cfg,
                                                           TALER_EXTENSION_SECTION_AGE_RESTRICTION,
                                                           "ENABLED")))
  {
    /* Age restriction is not enabled */
    mask->mask = 0;
    return TALER_Extension_OK;
  }

  /* Age restriction is enabled, extract age groups */
  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_string (cfg,
                                                          TALER_EXTENSION_SECTION_AGE_RESTRICTION,
                                                          "AGE_GROUPS",
                                                          &groups))
  {
    /* FIXME: log error? */
    return TALER_Extension_ERROR_SYS;
  }
  if (groups == NULL)
  {
    /* No groups defined in config, return default_age_mask */
    mask->mask = TALER_EXTENSION_DEFAULT_AGE_MASK;
    return TALER_Extension_OK;
  }

  ret = TALER_parse_age_group_string (groups, mask);
  GNUNET_free (groups);
  return ret;
}


/**
 * @param groups String representation of the age groups. Must be of the form
 *  a:b:...:n:m
 * with
 *  0 < a < b <...< n < m < 32
 * @param[out] mask Bit representation of the age groups.
 * @return Error if string was invalid, OK otherwise.
 */
enum TALER_Extension_ReturnValue
TALER_parse_age_group_string (char *groups,
                              struct TALER_AgeMask *mask)
{
  enum TALER_Extension_ReturnValue ret = TALER_Extension_ERROR_SYS;
  char *pos;
  unsigned int prev = 0;
  unsigned int val;
  char dummy;

  while (1)
  {
    pos = strchr (groups, ':');
    if (NULL != pos)
    {
      *pos = 0;
    }

    if (1 != sscanf (groups,
                     "%u%c",
                     &val,
                     &dummy))
    {
      /* Invalid input */
      mask->mask = 0;
      ret = TALER_Extension_ERROR_PARSING;
      break;
    }
    else if ((0 >= val) || (32 <= val) || (prev >= val))
    {
      /* Invalid value */
      mask->mask = 0;
      ret = TALER_Extension_ERROR_INVALID;
      break;
    }

    /* Set the corresponding bit in the mask */
    mask->mask |= 1 << val;

    if (NULL == pos)
    {
      /* We reached the end. Mark zeroth age-group and exit. */
      mask->mask |= 1;
      ret = TALER_Extension_OK;
      break;
    }

    prev = val;
    *pos = ':';
    groups = pos + 1;
  }

  return ret;
}


/**
 * Encodes the age mask into a string, like "8:10:12:14:16:18:21"
 *
 * @param mask Age mask
 * @return String representation of the age mask, allocated by GNUNET_malloc.
 *         Can be used as value in the TALER config.
 */
char *
TALER_age_mask_to_string (const struct TALER_AgeMask *m)
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


/* end of extension_age_restriction.c */
