/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file exchangedb/spi/perf_own_test.c
 * @brief benchmark for 'own_test'
 * @author Joseph Xu
 */
#include "exchangedb/platform.h"
#include "exchangedb/taler_exchangedb_lib.h"
#include "exchangedb/taler_json_lib.h"
#include "exchangedb/taler_exchangedb_plugin.h"
#include "own_test.sql"
