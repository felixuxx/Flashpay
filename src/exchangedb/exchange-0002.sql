--
-- This file is part of TALER
-- Copyright (C) 2020 Taler Systems SA
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

-- Check patch versioning is in place.
SELECT _v.register_patch('exchange-0002', NULL, NULL);

ALTER TABLE prewire
  ADD failed BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN prewire.failed
  IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';
COMMENT ON COLUMN prewire.finished
  IS 'set to TRUE once bank confirmed receiving the wire transfer request';
COMMENT ON COLUMN prewire.buf
  IS 'serialized data to send to the bank to execute the wire transfer';

-- change comment, existing index is still useful, but only for gc_prewire.
COMMENT ON INDEX prepare_iteration_index
  IS 'for gc_prewire';

-- need a new index for updated wire_prepare_data_get statement:
CREATE INDEX IF NOT EXISTS prepare_get_index
  ON prewire
  (failed,finished);
COMMENT ON INDEX prepare_get_index
  IS 'for wire_prepare_data_get';




-- Complete transaction
COMMIT;
