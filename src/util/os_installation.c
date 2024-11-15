/*
     This file is part of GNU Taler.
     Copyright (C) 2016, 2024 Taler Systems SA

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
#include "taler_util.h"

/**
 * Default project data used for installation path detection
 * for GNU Taler exchange.
 */
static const struct GNUNET_OS_ProjectData exchange_pd = {
  .libname = "libtalerutil",
  .project_dirname = "taler-exchange",
  .binary_name = "taler-exchange-httpd",
  .env_varname = "TALER_PREFIX",
  .base_config_varname = "TALER_BASE_CONFIG",
  .bug_email = "taler@gnu.org",
  .homepage = "http://www.gnu.org/s/taler/",
  .config_file = "taler-exchange.conf",
  .user_config_file = "~/.config/taler-exchange.conf",
  .version = PACKAGE_VERSION "-" VCS_VERSION,
  .is_gnu = 1,
  .gettext_domain = "taler",
  .gettext_path = NULL,
  .agpl_url = "https://git.taler.net/"
};


const struct GNUNET_OS_ProjectData *
TALER_EXCHANGE_project_data (void)
{
  return &exchange_pd;
}


/**
 * Default project data used for installation path detection
 * for GNU Taler auditor.
 */
static const struct GNUNET_OS_ProjectData auditor_pd = {
  .libname = "libtalerutil",
  .project_dirname = "taler-auditor",
  .binary_name = "taler-auditor-httpd",
  .env_varname = "TALER_PREFIX",
  .base_config_varname = "TALER_BASE_CONFIG",
  .bug_email = "taler@gnu.org",
  .homepage = "http://www.gnu.org/s/taler/",
  .config_file = "taler-auditor.conf",
  .user_config_file = "~/.config/taler-auditor.conf",
  .version = PACKAGE_VERSION "-" VCS_VERSION,
  .is_gnu = 1,
  .gettext_domain = "taler",
  .gettext_path = NULL,
  .agpl_url = "https://git.taler.net/"
};


const struct GNUNET_OS_ProjectData *
TALER_AUDITOR_project_data (void)
{
  return &auditor_pd;
}


/**
 * Default project data used for installation path detection
 * for GNU Taler fakebank.
 */
static const struct GNUNET_OS_ProjectData fakebank_pd = {
  .libname = "libtalerutil",
  .project_dirname = "taler-fakebank",
  .binary_name = "taler-fakebank-run",
  .env_varname = "TALER_PREFIX",
  .base_config_varname = "TALER_BASE_CONFIG",
  .bug_email = "taler@gnu.org",
  .homepage = "http://www.gnu.org/s/taler/",
  .config_file = "taler-fakebank.conf",
  .user_config_file = "~/.config/taler-fakebank.conf",
  .version = PACKAGE_VERSION "-" VCS_VERSION,
  .is_gnu = 1,
  .gettext_domain = "taler",
  .gettext_path = NULL,
  .agpl_url = "https://git.taler.net/"
};


const struct GNUNET_OS_ProjectData *
TALER_FAKEBANK_project_data (void)
{
  return &fakebank_pd;
}


/* end of os_installation.c */
