/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file util.c
 * @brief Common utility functions; we might choose to move those to GNUnet at some point
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Benedikt Mueller
 */

#include "platform.h"
#include "taler_util.h"
#include <gnunet/gnunet_common.h>
#include <gnunet/gnunet_util_lib.h>
#include <gcrypt.h>



/**
 * Load configuration by parsing all configuration
 * files in the given directory.
 *
 * @param base_dir directory with the configuration files
 * @return NULL on error, otherwise configuration
 */
struct GNUNET_CONFIGURATION_Handle *
TALER_config_load (const char *base_dir)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  char *cfg_dir;
  int res;

  res = GNUNET_asprintf (&cfg_dir,
                         "%s" DIR_SEPARATOR_STR "config",
                         base_dir);
  GNUNET_assert (res > 0);
  cfg = GNUNET_CONFIGURATION_create ();
  res = GNUNET_CONFIGURATION_load_from (cfg, cfg_dir);
  GNUNET_free (cfg_dir);
  if (GNUNET_OK != res)
   return NULL;
  return cfg;
}




/* end of util.c */
