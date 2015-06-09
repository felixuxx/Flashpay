/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file mintdb/perf_taler_mintdb_values.h
 * @brief Values for tweaking the performance analysis
 * @author Nicolas Fournier
 */
#ifndef __PERF_TALER_MINTDB__VALUES_H__
#define __PERF_TALER_MINTDB__VALUES_H__



#define NB_DEPOSIT_INIT   100000
#define NB_DEPOSIT_GET    1000
#define NB_DEPOSIT_MARGIN 10000

#define NB_BLINDCOIN_INIT 100000


// Temporary macro to compile
#define GAUGER(a,b,c,d)


#endif
