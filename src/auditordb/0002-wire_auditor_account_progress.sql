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

CREATE TABLE IF NOT EXISTS wire_auditor_account_progress
    ,account_name TEXT NOT NULL
    ,last_wire_reserve_in_serial_id INT8 NOT NULL DEFAULT 0
    ,last_wire_wire_out_serial_id INT8 NOT NULL DEFAULT 0
    ,wire_in_off INT8 NOT NULL
    ,wire_out_off INT8 NOT NULL
    ,PRIMARY KEY (account_name)
    );
COMMENT ON TABLE wire_auditor_account_progress
  IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';
