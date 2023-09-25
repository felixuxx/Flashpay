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

CREATE TABLE IF NOT EXISTS auditor_progress_coin
    ,last_withdraw_serial_id INT8 NOT NULL DEFAULT 0
    ,last_deposit_serial_id INT8 NOT NULL DEFAULT 0
    ,last_melt_serial_id INT8 NOT NULL DEFAULT 0
    ,last_refund_serial_id INT8 NOT NULL DEFAULT 0
    ,last_recoup_serial_id INT8 NOT NULL DEFAULT 0
    ,last_recoup_refresh_serial_id INT8 NOT NULL DEFAULT 0
    ,last_open_deposits_serial_id INT8 NOT NULL DEFAULT 0
    ,last_purse_deposits_serial_id INT8 NOT NULL DEFAULT 0
    ,last_purse_decision_serial_id INT8 NOT NULL DEFAULT 0
    -- ,PRIMARY KEY (master_pub)
    );
COMMENT ON TABLE auditor_progress_coin
  IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';
