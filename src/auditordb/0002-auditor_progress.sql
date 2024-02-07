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

CREATE TABLE IF NOT EXISTS auditor_progress
  (progress_key TEXT PRIMARY KEY NOT NULL
  ,progress_offset INT8 NOT NULL
  );
COMMENT ON TABLE auditor_progress
  IS 'Information about to the point until which the audit has progressed.  Used for SELECTing the statements to process.';
COMMENT ON COLUMN auditor_progress.progress_key
  IS 'Name of the progress indicator';
COMMENT ON COLUMN auditor_progress.progress_offset
  IS 'Table offset or timestamp or counter until which the audit has progressed';
