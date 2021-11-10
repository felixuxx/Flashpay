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

/**
 *
 * @param cfg
 * @param[out] mask for age restriction
 * @return Error if extension for age restriction was set but age groups were
 *         invalid, OK otherwise.
 */
enum GNUNET_GenericReturnValue
TALER_get_age_mask (const struct GNUNET_CONFIGURATION_Handle *cfg, struct
                    TALER_AgeMask *mask);

#endif
