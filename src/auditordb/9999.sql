--
-- This file is part of TALER
-- Copyright (C) 2014--2020 Taler Systems SA
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

-- Everything in one big transaction
BEGIN;

NOTE: This code is not yet ready / in use. It was archived here
as we might want this kind of table in the future. It is NOT
to be installed in a production system (hence in EXTRA_DIST and
not in the SQL target!)

-- Check patch versioning is in place.
SELECT _v.register_patch('auditor-9999', NULL, NULL);


-- Table with historic business ledger; basically, when the exchange
-- operator decides to use operating costs for anything but wire
-- transfers to merchants, it goes in here.  This happens when the
-- operator users transaction fees for business expenses. purpose
-- is free-form but should be a human-readable wire transfer
-- identifier.   This is NOT yet used and outside of the scope of
-- the core auditing logic. However, once we do take fees to use
-- operating costs, and if we still want auditor_predicted_result to match
-- the tables overall, we'll need a command-line tool to insert rows
-- into this table and update auditor_predicted_result accordingly.
-- (So this table for now just exists as a reminder of what we'll
-- need in the long term.)
CREATE TABLE IF NOT EXISTS auditor_historic_ledger
  (master_pub BYTEA CONSTRAINT master_pub_ref REFERENCES auditor_exchanges(master_pub) ON DELETE CASCADE
  ,purpose VARCHAR NOT NULL
  ,timestamp INT8 NOT NULL
  ,balance_val INT8 NOT NULL
  ,balance_frac INT4 NOT NULL
  );
CREATE INDEX history_ledger_by_master_pub_and_time
  ON auditor_historic_ledger
  (master_pub
  ,timestamp);

COMMIT;
