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

CREATE TABLE IF NOT EXISTS auditor_historic_denomination_revenue
    ,denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)
    ,revenue_timestamp INT8 NOT NULL
    ,revenue_balance_val INT8 NOT NULL
    ,revenue_balance_frac INT4 NOT NULL
    ,loss_balance_val INT8 NOT NULL
    ,loss_balance_frac INT4 NOT NULL
    );
COMMENT ON TABLE auditor_historic_denomination_revenue
  IS 'Table with historic profits; basically, when a denom_pub has expired and everything associated with it is garbage collected, the final profits end up in here; note that the denom_pub here is not a foreign key, we just keep it as a reference point.';
COMMENT ON COLUMN auditor_historic_denomination_revenue.revenue_balance_val
  IS 'the sum of all of the profits we made on the coin except for withdraw fees (which are in historic_reserve_revenue); so this includes the deposit, melt and refund fees';
