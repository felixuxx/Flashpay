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

CREATE TABLE IF NOT EXISTS auditor_denomination_pending
(denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)
    ,denom_balance_val INT8 NOT NULL
    ,denom_balance_frac INT4 NOT NULL
    ,denom_loss_val INT8 NOT NULL
    ,denom_loss_frac INT4 NOT NULL
    ,num_issued INT8 NOT NULL
    ,denom_risk_val INT8 NOT NULL
    ,denom_risk_frac INT4 NOT NULL
    ,recoup_loss_val INT8 NOT NULL
    ,recoup_loss_frac INT4 NOT NULL
    );
COMMENT ON TABLE auditor_denomination_pending
  IS 'outstanding denomination coins that the exchange is aware of and what the respective balances are (outstanding as well as issued overall which implies the maximum value at risk).';
COMMENT ON COLUMN auditor_denomination_pending.num_issued
  IS 'counts the number of coins issued (withdraw, refresh) of this denomination';
COMMENT ON COLUMN auditor_denomination_pending.denom_risk_val
  IS 'amount that could theoretically be lost in the future due to recoup operations';
COMMENT ON COLUMN auditor_denomination_pending.denom_loss_val
  IS 'amount that was lost due to failures by the exchange';
COMMENT ON COLUMN auditor_denomination_pending.recoup_loss_val
  IS 'amount actually lost due to recoup operations after a revocation';