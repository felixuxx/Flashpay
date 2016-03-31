/*
     This file is part of GNU Taler.
     Copyright (C) 2016 Inria

     Taler is free software; you can redistribute it and/or modify
     it under the terms of the GNU General Public License as published
     by the Free Software Foundation; either version 3, or (at your
     option) any later version.

     Taler is distributed in the hope that it will be useful, but
     WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
     General Public License for more details.

     You should have received a copy of the GNU General Public License
     along with Taler; see the file COPYING.  If not, write to the
     Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
     Boston, MA 02110-1301, USA.
*/

/**
 * @file os_installation.c
 * @brief initialize libgnunet OS subsystem for Taler.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>


/**
 * Default project data used for installation path detection
 * for GNU Taler.
 */
static const struct GNUNET_OS_ProjectData taler_pd = {
  .libname = "libtalerutil",
  .project_dirname = "taler",
  .binary_name = "taler-exchange-httpd",
  .env_varname = "TALER_PREFIX"
};


/**
 * Return default project data used by gnunet-gtk.
 */
const struct GNUNET_OS_ProjectData *
TALER_project_data_default (void)
{
  return &taler_pd;
}


/**
 * Initialize libtalerutil.
 */
void __attribute__ ((constructor))
TALER_OS_init ()
{
  GNUNET_OS_init (&taler_pd);
}


/* end of os_installation.c */
