/*
  This file is part of TALER
  Copyright (C) 2016 Inria

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
 * @file taler_error_codes.h
 * @brief error codes returned by GNU Taler
 *
 * This file should defines constants for error codes returned
 * in Taler APIs.  We use codes above 1000 to avoid any
 * confusing with HTTP status codes.  All constants have the
 * shared prefix "TALER_EC_" to indicate that they are error
 * codes.
 */
#ifndef TALER_ERROR_CODES_H
#define TALER_ERROR_CODES_H

/**
 * Enumeration with all possible Taler error codes.
 */
enum TALER_ErrorCode
{

  /**
   * Special code to indicate no error.
   */
  TALER_EC_NONE = 0



};


#endif
