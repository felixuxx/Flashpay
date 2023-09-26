--
-- This file is part of TALER
-- Copyright (C) 2014--2022 Taler Systems SA
--
-- TALER is free software; you can redistribute it and/or modify it under the
-- terms of the GNU General Public License as published by the Free Software
-- Foundation; either version 3, or (at your option) any later version.
--
-- TALER is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
-- A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along with
-- TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
--

CREATE TABLE IF NOT EXISTS auditor_reserve_balance
    ,reserve_balance taler_amount NOT NULL
    ,reserve_loss taler_amount NOT NULL
    ,withdraw_fee_balance taler_amount NOT NULL
    ,close_fee_balance taler_amount NOT NULL
    ,purse_fee_balance taler_amount NOT NULL
    ,open_fee_balance taler_amount NOT NULL
    ,history_fee_balance taler_amount NOT NULL
    );
COMMENT ON TABLE auditor_reserve_balance
  IS 'sum of the balances of all customer reserves';
