/*
  This file is part of TALER
  Copyright (C) 2015 Christian Grothoff (and other contributing authors)

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
 * @file mint/plugin.c
 * @brief Logic to load database plugin
 * @author Christian Grothoff
 */
#include "platform.h"
#include "plugin.h"
#include <ltdl.h>


/**
 * Global variable with the plugin (once loaded).
 */
struct TALER_MINTDB_Plugin *plugin;

/**
 * Libtool search path before we started.
 */
static char *old_dlsearchpath;


/**
 * Initialize the plugin.
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  return GNUNET_SYSERR;
}


/**
 * Shutdown the plugin.
 */
void
TALER_MINT_plugin_unload ()
{
  if (NULL == plugin)
    return;
}


/**
 * Setup libtool paths.
 */
void __attribute__ ((constructor))
plugin_init ()
{
  int err;
  const char *opath;
  char *path;
  char *cpath;

  err = lt_dlinit ();
  if (err > 0)
  {
    FPRINTF (stderr,
             _("Initialization of plugin mechanism failed: %s!\n"),
             lt_dlerror ());
    return;
  }
  opath = lt_dlgetsearchpath ();
  if (NULL != opath)
    old_dlsearchpath = GNUNET_strdup (opath);
  path = TALER_OS_installation_get_path (GNUNET_OS_IPK_LIBDIR);
  if (NULL != path)
  {
    if (NULL != opath)
    {
      GNUNET_asprintf (&cpath, "%s:%s", opath, path);
      lt_dlsetsearchpath (cpath);
      GNUNET_free (path);
      GNUNET_free (cpath);
    }
    else
    {
      lt_dlsetsearchpath (path);
      GNUNET_free (path);
    }
  }
}


/**
 * Shutdown libtool.
 */
void __attribute__ ((destructor))
plugin_fini ()
{
  lt_dlsetsearchpath (old_dlsearchpath);
  if (NULL != old_dlsearchpath)
  {
    GNUNET_free (old_dlsearchpath);
    old_dlsearchpath = NULL;
  }
  lt_dlexit ();
}


/* end of plugin.c */
