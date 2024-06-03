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

CREATE OR REPLACE FUNCTION comment_partitioned_table(
   IN table_comment TEXT
  ,IN table_name TEXT
  ,IN partition_suffix TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF ( (partition_suffix IS NOT NULL) AND
       (partition_suffix::int > 0) )
  THEN
    -- sharding, add shard name
    table_name=table_name || '_' || partition_suffix;
  END IF;
  EXECUTE FORMAT(
     'COMMENT ON TABLE %s IS %s'
    ,table_name
    ,quote_literal(table_comment)
  );
END $$;

COMMENT ON FUNCTION comment_partitioned_table
  IS 'Generic function to create a comment on table that is partitioned.';
