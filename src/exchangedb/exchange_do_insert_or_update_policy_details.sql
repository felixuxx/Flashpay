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
  IN in_policy_json VARCHAR,
  IN in_deadline INT8,
  IN in_commitment_val INT8,
  IN in_commitment_frac INT4,
  IN in_accumulated_total_val INT8,
  IN in_accumulated_total_frac INT4,
  IN in_fee_val INT8,
  IN in_fee_frac INT4,
  IN in_transferable_val INT8,
  IN in_transferable_frac INT4,
  IN in_fulfillment_state SMALLINT,
  OUT out_policy_details_serial_id INT8,
  OUT out_accumulated_total_val INT8,
  OUT out_accumulated_total_frac INT4,
  OUT out_fulfillment_state SMALLINT)
LANGUAGE plpgsql
AS $$
DECLARE
       cur_commitment_val INT8;
       cur_commitment_frac INT4;
       cur_accumulated_total_val INT8;
       cur_accumulated_total_frac INT4;
BEGIN
       -- First, try to create a new entry.
       INSERT INTO policy_details
               (policy_hash_code,
                policy_json,
                deadline,
                commitment_val,
                commitment_frac,
                accumulated_total_val,
                accumulated_total_frac,
                fee_val,
                fee_frac,
                transferable_val,
                transferable_frac,
                fulfillment_state)
       VALUES (in_policy_hash_code,
                in_policy_json,
                in_deadline,
                in_commitment_val,
                in_commitment_frac,
                in_accumulated_total_val,
                in_accumulated_total_frac,
                in_fee_val,
                in_fee_frac,
                in_transferable_val,
                in_transferable_frac,
                in_fulfillment_state)
       ON CONFLICT (policy_hash_code) DO NOTHING
       RETURNING policy_details_serial_id INTO out_policy_details_serial_id;

       -- If the insert was successful, return
       -- We assume that the fullfilment_state was correct in first place.
       IF FOUND THEN
               out_accumulated_total_val  = in_accumulated_total_val;
               out_accumulated_total_frac = in_accumulated_total_frac;
               out_fulfillment_state      = in_fulfillment_state;
               RETURN;
       END IF;

       -- We had a conflict, grab the parts we need to update.
       SELECT policy_details_serial_id,
               commitment_val,
               commitment_frac,
               accumulated_total_val,
               accumulated_total_frac
       INTO out_policy_details_serial_id,
               cur_commitment_val,
               cur_commitment_frac,
               cur_accumulated_total_val,
               cur_accumulated_total_frac
       FROM policy_details
       WHERE policy_hash_code = in_policy_hash_code;

       -- calculate the new values (overflows throws exception)
       out_accumulated_total_val  = cur_accumulated_total_val  + in_accumulated_total_val;
       out_accumulated_total_frac = cur_accumulated_total_frac + in_accumulated_total_frac;
       -- normalize
       out_accumulated_total_val = out_accumulated_total_val + out_accumulated_total_frac / 100000000;
       out_accumulated_total_frac = out_accumulated_total_frac % 100000000;

       IF (out_accumulated_total_val > (1 << 52))
       THEN
               RAISE EXCEPTION 'accumulation overflow';
       END IF;


       -- Set the fulfillment_state according to the values.
       -- For now, we only update the state when it was INSUFFICIENT.
       -- FIXME: What to do in case of Failure or other state?
       IF (out_fullfillment_state = 1) -- INSUFFICIENT
       THEN
               IF (out_accumulated_total_val >= cur_commitment_val OR
                       (out_accumulated_total_val = cur_commitment_val AND
                               out_accumulated_total_frac >= cur_commitment_frac))
               THEN
                       out_fulfillment_state = 2; -- READY
               END IF;
       END IF;

       -- Now, update the record
       UPDATE exchange.policy_details
       SET
               accumulated_val  = out_accumulated_total_val,
               accumulated_frac = out_accumulated_total_frac,
               fulfillment_state = out_fulfillment_state
       WHERE
               policy_details_serial_id = out_policy_details_serial_id;
END $$;
