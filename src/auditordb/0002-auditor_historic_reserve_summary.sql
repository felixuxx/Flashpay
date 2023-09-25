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

CREATE TABLE IF NOT EXISTS auditor_historic_reserve_summary
    ,start_date INT8 NOT NULL
    ,end_date INT8 NOT NULL
    ,reserve_profits_val INT8 NOT NULL
    ,reserve_profits_frac INT4 NOT NULL
    );
COMMENT ON TABLE auditor_historic_reserve_summary
  IS 'historic profits from reserves; we eventually GC auditor_historic_reserve_revenue, and then store the totals in here (by time intervals).';

CREATE INDEX IF NOT EXISTS auditor_historic_reserve_summary_by_master_pub_start_date
    ON auditor_historic_reserve_summary
    (start_date);