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


CREATE TABLE IF NOT EXISTS purse_actions
  (purse_pub BYTEA NOT NULL PRIMARY KEY CHECK(LENGTH(purse_pub)=32)
  ,action_date INT8 NOT NULL
  ,partner_serial_id INT8
  );
COMMENT ON TABLE purse_actions
  IS 'purses awaiting some action by the router';
COMMENT ON COLUMN purse_actions.purse_pub
  IS 'public (contract) key of the purse';
COMMENT ON COLUMN purse_actions.action_date
  IS 'when is the purse ready for action';
COMMENT ON COLUMN purse_actions.partner_serial_id
  IS 'wad target of an outgoing wire transfer, 0 for local, NULL if the purse is unmerged and thus the target is still unknown';

CREATE INDEX IF NOT EXISTS purse_action_by_target
  ON purse_actions
  (partner_serial_id,action_date);


CREATE OR REPLACE FUNCTION purse_requests_insert_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  INSERT INTO
    purse_actions
    (purse_pub
    ,action_date)
  VALUES
    (NEW.purse_pub
    ,NEW.purse_expiration);
  RETURN NEW;
END $$;
COMMENT ON FUNCTION purse_requests_insert_trigger()
  IS 'When a purse is created, insert it into the purse_action table to take action when the purse expires.';

CREATE TRIGGER purse_requests_on_insert
  AFTER INSERT
   ON purse_requests
   FOR EACH ROW EXECUTE FUNCTION purse_requests_insert_trigger();
COMMENT ON TRIGGER purse_requests_on_insert
        ON purse_requests
  IS 'Here we install an entry for the purse expiration.';
