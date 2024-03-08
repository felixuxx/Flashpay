--
-- This file is part of TALER
-- Copyright (C) 2024 Taler Systems SA
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

SELECT _v.register_patch('auditor-triggers-0001');

SET search_path TO exchange;

CREATE OR REPLACE FUNCTION auditor_new_deposits_trigger()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    NOTIFY XFIXME;
    RETURN NEW;
END $$;
COMMENT ON FUNCTION auditor_new_deposits_trigger()
    IS 'Call XXX on new entry';

CREATE TRIGGER auditor_notify_helper_insert_deposits
    AFTER INSERT
    ON exchange.batch_deposits
EXECUTE PROCEDURE auditor_new_deposits_trigger();


COMMIT;
