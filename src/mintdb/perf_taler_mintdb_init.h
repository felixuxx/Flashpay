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
 * @file mintdb/perf_taler_mintdb_init.h
 * @brief Heler function for creating dummy inpus for the mint database
 * @author Nicolas Fournier
 */
#ifndef __PERF_TALER_MINTDB_INIT_H___
#define __PERF_TALER_MINTDB_INIT_H___


#include <gnunet/platform.h>
#include "taler_mintdb_lib.h"
#include "taler_mintdb_plugin.h"


#define CURRENCY "EUR"


struct TALER_MINTDB_CollectableBlindcoin *
init_collectable_blindcoin(void);

struct TALER_MINTDB_RefreshSession *
init_refresh_session(void);

struct TALER_MINTDB_Deposit *
init_deposit(int transaction_id);

struct TALER_MINTDB_DenominationKeyIssueInformation *
init_denomination(void);



int
free_deposit(struct TALER_MINTDB_Deposit *deposit);

int
free_collectable_blindcoin(struct TALER_MINTDB_CollectableBlindcoin *NAME);

int
free_denomination(struct TALER_MINTDB_DenominationKeyIssueInformation *dki);


#endif
