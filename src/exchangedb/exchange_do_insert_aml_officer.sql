--
-- This file is part of TALER
-- Copyright (C) 2023 Taler Systems SA
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

CREATE OR REPLACE FUNCTION exchange_do_insert_aml_officer(
  IN in_decider_pub BYTEA,
  IN in_master_sig BYTEA,
  IN in_decider_name VARCHAR,
  IN in_is_active BOOLEAN,
  IN in_read_only BOOLEAN,
  IN in_last_change INT8,
  OUT out_last_change INT8)
LANGUAGE plpgsql
AS $$
BEGIN
INSERT INTO exchange.aml_staff
  (decider_pub
  ,master_sig
  ,decider_name
  ,is_active
  ,read_only
  ,last_change
  ) VALUES
  (in_decider_pub
  ,in_master_sig
  ,in_decider_name
  ,in_is_active
  ,in_read_only
  ,in_last_change)
 ON CONFLICT DO NOTHING;
IF FOUND
THEN
  out_last_change=0;
  RETURN;
END IF;

-- Check update is most recent...
SELECT last_change
  INTO out_last_change
  FROM exchange.aml_staff
  WHERE decider_pub=in_decider_pub;
ASSERT FOUND, 'cannot have INSERT conflict but no AML staff record';

IF out_last_change >= in_last_change
THEN
  -- Refuse to insert older status
 RETURN;
END IF;

-- We are more recent, update existing record.
UPDATE exchange.aml_staff
  SET master_sig=in_master_sig
     ,decider_name=in_decider_name
     ,is_active=in_is_active
     ,read_only=in_read_only
     ,last_change=in_last_change
  WHERE decider_pub=in_decider_pub;
END $$;


COMMENT ON FUNCTION exchange_do_insert_aml_officer(BYTEA, BYTEA, VARCHAR, BOOL, BOOL, INT8)
  IS 'Inserts or updates AML staff record, making sure the update is more recent than the previous change';
