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

CREATE OR REPLACE FUNCTION exchange_do_insert_or_update_policy_details(
  IN in_policy_hash_code BYTEA,
  IN in_policy_json TEXT,
  IN in_deadline INT8,
  IN in_commitment taler_amount,
  IN in_accumulated_total taler_amount,
  IN in_fee taler_amount,
  IN in_transferable taler_amount,
  IN in_fulfillment_state SMALLINT,
  OUT out_policy_details_serial_id INT8,
  OUT out_accumulated_total taler_amount,
  OUT out_fulfillment_state SMALLINT)
LANGUAGE plpgsql
AS $$
DECLARE
    cur_commitment taler_amount;
DECLARE
    cur_accumulated_total taler_amount;
DECLARE
    rval RECORD;
BEGIN
       -- First, try to create a new entry.
       INSERT INTO policy_details
               (policy_hash_code,
                policy_json,
                deadline,
                commitment,
                accumulated_total,
                fee,
                transferable,
                fulfillment_state)
       VALUES (in_policy_hash_code,
                in_policy_json,
                in_deadline,
                in_commitment,
                in_accumulated_total,
                in_fee,
                in_transferable,
                in_fulfillment_state)
       ON CONFLICT (policy_hash_code) DO NOTHING
       RETURNING policy_details_serial_id INTO out_policy_details_serial_id;

       -- If the insert was successful, return
       -- We assume that the fullfilment_state was correct in first place.
       IF FOUND THEN
               out_accumulated_total = in_accumulated_total;
               out_fulfillment_state = in_fulfillment_state;
               RETURN;
       END IF;

       -- We had a conflict, grab the parts we need to update.
       SELECT policy_details_serial_id
         ,commitment
         ,accumulated_total
       INTO rval
       FROM policy_details
       WHERE policy_hash_code = in_policy_hash_code;

       -- We use rval as workaround as we cannot select
       -- directly into the amount due to Postgres limitations.
       out_policy_details_serial_id := rval.policy_details_serial_id;
       cur_commitment := rval.commitment;
       cur_accumulated_total := rval.accumulated_total;

       -- calculate the new values (overflows throws exception)
       out_accumulated_total.val  = cur_accumulated_total.val  + in_accumulated_total.val;
       out_accumulated_total.frac = cur_accumulated_total.frac + in_accumulated_total.frac;
       -- normalize
       out_accumulated_total.val = out_accumulated_total.val + out_accumulated_total.frac / 100000000;
       out_accumulated_total.frac = out_accumulated_total.frac % 100000000;

       IF (out_accumulated_total.val > (1 << 52))
       THEN
               RAISE EXCEPTION 'accumulation overflow';
       END IF;


       -- Set the fulfillment_state according to the values.
       -- For now, we only update the state when it was INSUFFICIENT.
       -- FIXME: What to do in case of Failure or other state?
       IF (out_fullfillment_state = 1) -- INSUFFICIENT
       THEN
               IF (out_accumulated_total.val >= cur_commitment.val OR
                       (out_accumulated_total.val = cur_commitment.val AND
                               out_accumulated_total.frac >= cur_commitment.frac))
               THEN
                       out_fulfillment_state = 2; -- READY
               END IF;
       END IF;

       -- Now, update the record
       UPDATE exchange.policy_details
       SET
               accumulated  = out_accumulated_total,
               fulfillment_state = out_fulfillment_state
       WHERE
               policy_details_serial_id = out_policy_details_serial_id;
END $$;
