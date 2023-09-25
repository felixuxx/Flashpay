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

CREATE TABLE IF NOT EXISTS auditor_balance_summary
    ,denom_balance_val INT8 NOT NULL
    ,denom_balance_frac INT4 NOT NULL
    ,deposit_fee_balance_val INT8 NOT NULL
    ,deposit_fee_balance_frac INT4 NOT NULL
    ,melt_fee_balance_val INT8 NOT NULL
    ,melt_fee_balance_frac INT4 NOT NULL
    ,refund_fee_balance_val INT8 NOT NULL
    ,refund_fee_balance_frac INT4 NOT NULL
    ,purse_fee_balance_val INT8 NOT NULL
    ,purse_fee_balance_frac INT4 NOT NULL
    ,open_deposit_fee_balance_val INT8 NOT NULL
    ,open_deposit_fee_balance_frac INT4 NOT NULL
    ,risk_val INT8 NOT NULL
    ,risk_frac INT4 NOT NULL
    ,loss_val INT8 NOT NULL
    ,loss_frac INT4 NOT NULL
    ,irregular_loss_val INT8 NOT NULL
    ,irregular_loss_frac INT4 NOT NULL
    );
COMMENT ON TABLE auditor_balance_summary
  IS 'the sum of the outstanding coins from auditor_denomination_pending (denom_pubs must belong to the respectives exchange master public key); it represents the auditor_balance_summary of the exchange at this point (modulo unexpected historic_loss-style events where denomination keys are compromised)';
COMMENT ON COLUMN auditor_balance_summary.denom_balance_frac
 IS 'total amount we should have in escrow for all denominations';