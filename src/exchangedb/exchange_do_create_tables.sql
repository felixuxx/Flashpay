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

---------------------------------------------------------------------------
--                   Main DB setup loop
---------------------------------------------------------------------------


CREATE OR REPLACE FUNCTION do_create_tables(
  num_partitions INTEGER
-- NULL: no partitions, add foreign constraints
-- 0: no partitions, no foreign constraints
-- 1: only 1 default partition
-- > 1: normal partitions
)
  RETURNS VOID
  LANGUAGE plpgsql
AS $$
DECLARE
  tc CURSOR FOR
    SELECT table_serial_id
          ,name
          ,action
          ,partitioned
          ,by_range
      FROM exchange.exchange_tables
     WHERE NOT finished
     ORDER BY table_serial_id ASC;
BEGIN
  FOR rec IN tc
  LOOP
    CASE rec.action
    -- "create" actions apply to master and partitions
    WHEN 'create'
    THEN
      IF (rec.partitioned AND
          (num_partitions IS NOT NULL))
      THEN
        -- Create master table with partitioning.
        EXECUTE FORMAT(
          'SELECT exchange.create_table_%s (%s)'::text
          ,rec.name
          ,quote_literal('0')
        );
        IF (rec.by_range OR
            (num_partitions = 0))
        THEN
          -- Create default partition.
          IF (rec.by_range)
          THEN
            -- Range partition
            EXECUTE FORMAT(
              'CREATE TABLE exchange.%s_default'
              ' PARTITION OF %s'
              ' DEFAULT'
             ,rec.name
             ,rec.name
            );
          ELSE
            -- Hash partition
            EXECUTE FORMAT(
              'CREATE TABLE exchange.%s_default'
              ' PARTITION OF %s'
              ' FOR VALUES WITH (MODULUS 1, REMAINDER 0)'
             ,rec.name
             ,rec.name
            );
          END IF;
        ELSE
          FOR i IN 1..num_partitions LOOP
            -- Create num_partitions
            EXECUTE FORMAT(
               'CREATE TABLE exchange.%I'
               ' PARTITION OF %I'
               ' FOR VALUES WITH (MODULUS %s, REMAINDER %s)'
              ,rec.name || '_' || i
              ,rec.name
              ,num_partitions
              ,i-1
            );
          END LOOP;
        END IF;
      ELSE
        -- Only create master table. No partitions.
        EXECUTE FORMAT(
          'SELECT exchange.create_table_%s ()'::text
          ,rec.name
        );
      END IF;
      EXECUTE FORMAT(
        'DROP FUNCTION exchange.create_table_%s'::text
          ,rec.name
        );
    -- "alter" actions apply to master and partitions
    WHEN 'alter'
    THEN
      -- Alter master table.
      EXECUTE FORMAT(
        'SELECT exchange.alter_table_%s ()'::text
        ,rec.name
      );
      EXECUTE FORMAT(
        'DROP FUNCTION exchange.alter_table_%s'::text
          ,rec.name
        );
    -- Constrain action apply to master OR each partition
    WHEN 'constrain'
    THEN
      ASSERT rec.partitioned, 'constrain action only applies to partitioned tables';
      IF (num_partitions IS NULL)
      THEN
        -- Constrain master table
        EXECUTE FORMAT(
           'SELECT exchange.constrain_table_%s (NULL)'::text
          ,rec.name
        );
      ELSE
        IF ( (num_partitions = 0) OR
             (rec.by_range) )
        THEN
          -- Constrain default table
          EXECUTE FORMAT(
             'SELECT exchange.constrain_table_%s (%s)'::text
            ,rec.name
            ,quote_literal('default')
          );
        ELSE
          -- Constrain each partition
          FOR i IN 1..num_partitions LOOP
            EXECUTE FORMAT(
              'SELECT exchange.constrain_table_%s (%s)'::text
              ,rec.name
              ,quote_literal(i)
            );
          END LOOP;
        END IF;
      END IF;
      EXECUTE FORMAT(
        'DROP FUNCTION exchange.constrain_table_%s'::text
          ,rec.name
        );
    -- Foreign actions only apply if partitioning is off
    WHEN 'foreign'
    THEN
      IF (num_partitions IS NULL)
      THEN
        -- Add foreign constraints
        EXECUTE FORMAT(
          'SELECT exchange.foreign_table_%s (%s)'::text
          ,rec.name
          ,NULL
        );
      END IF;
      EXECUTE FORMAT(
        'DROP FUNCTION exchange.foreign_table_%s'::text
          ,rec.name
        );
    WHEN 'master'
    THEN
      EXECUTE FORMAT(
        'SELECT exchange.master_table_%s ()'::text
        ,rec.name
      );
      EXECUTE FORMAT(
        'DROP FUNCTION exchange.master_table_%s'::text
          ,rec.name
        );
    ELSE
      ASSERT FALSE, 'unsupported action type: ' || rec.action;
    END CASE;  -- END CASE (rec.action)
    -- Mark as finished
    UPDATE exchange.exchange_tables
       SET finished=TRUE
     WHERE table_serial_id=rec.table_serial_id;
  END LOOP; -- create/alter/drop actions
END $$;

COMMENT ON FUNCTION do_create_tables
  IS 'Creates all tables for the given number of partitions that need creating. Does NOT support sharding.';
