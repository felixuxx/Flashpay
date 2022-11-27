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


-- ------------------------------ aggregation_transient ----------------------------------------

SELECT create_table_aggregation_transient();

COMMENT ON TABLE aggregation_transient
  IS 'aggregations currently happening (lacking wire_out, usually because the amount is too low); this table is not replicated';
COMMENT ON COLUMN aggregation_transient.amount_val
  IS 'Sum of all of the aggregated deposits (without deposit fees)';
COMMENT ON COLUMN aggregation_transient.wtid_raw
  IS 'identifier of the wire transfer';

-- ------------------------------ aggregation_tracking ----------------------------------------

SELECT create_table_aggregation_tracking();

COMMENT ON TABLE aggregation_tracking
  IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';
COMMENT ON COLUMN aggregation_tracking.wtid_raw
  IS 'identifier of the wire transfer';

SELECT add_constraints_to_aggregation_tracking_partition('default');


-- ------------------------------ recoup ----------------------------------------

SELECT create_table_recoup();

COMMENT ON TABLE recoup
  IS 'Information about recoups that were executed between a coin and a reserve. In this type of recoup, the amount is credited back to the reserve from which the coin originated.';
COMMENT ON COLUMN recoup.coin_pub
  IS 'Coin that is being debited in the recoup. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';
COMMENT ON COLUMN recoup.reserve_out_serial_id
  IS 'Identifies the h_blind_ev of the recouped coin and provides the link to the credited reserve.';
COMMENT ON COLUMN recoup.coin_sig
  IS 'Signature by the coin affirming the recoup, of type TALER_SIGNATURE_WALLET_COIN_RECOUP';
COMMENT ON COLUMN recoup.coin_blind
  IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the withdraw operation.';

SELECT add_constraints_to_recoup_partition('default');


SELECT create_table_recoup_by_reserve();

COMMENT ON TABLE recoup_by_reserve
  IS 'Information in this table is strictly redundant with that of recoup, but saved by a different primary key for fast lookups by reserve_out_serial_id.';

CREATE OR REPLACE FUNCTION recoup_insert_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  INSERT INTO exchange.recoup_by_reserve
    (reserve_out_serial_id
    ,coin_pub)
  VALUES
    (NEW.reserve_out_serial_id
    ,NEW.coin_pub);
  RETURN NEW;
END $$;
COMMENT ON FUNCTION recoup_insert_trigger()
  IS 'Replicate recoup inserts into recoup_by_reserve table.';

CREATE TRIGGER recoup_on_insert
  AFTER INSERT
   ON recoup
   FOR EACH ROW EXECUTE FUNCTION recoup_insert_trigger();

CREATE OR REPLACE FUNCTION recoup_delete_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  DELETE FROM exchange.recoup_by_reserve
   WHERE reserve_out_serial_id = OLD.reserve_out_serial_id
     AND coin_pub = OLD.coin_pub;
  RETURN OLD;
END $$;
COMMENT ON FUNCTION recoup_delete_trigger()
  IS 'Replicate recoup deletions into recoup_by_reserve table.';

CREATE TRIGGER recoup_on_delete
  AFTER DELETE
    ON recoup
   FOR EACH ROW EXECUTE FUNCTION recoup_delete_trigger();


-- ------------------------------ recoup_refresh ----------------------------------------

SELECT create_table_recoup_refresh();

COMMENT ON TABLE recoup_refresh
  IS 'Table of coins that originated from a refresh operation and that were recouped. Links the (fresh) coin to the melted operation (and thus the old coin). A recoup on a refreshed coin credits the old coin and debits the fresh coin.';
COMMENT ON COLUMN recoup_refresh.coin_pub
  IS 'Refreshed coin of a revoked denomination where the residual value is credited to the old coin. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';
COMMENT ON COLUMN recoup_refresh.known_coin_id
  IS 'FIXME: (To be) used for garbage collection (in the future)';
COMMENT ON COLUMN recoup_refresh.rrc_serial
  IS 'Link to the refresh operation. Also identifies the h_blind_ev of the recouped coin (as h_coin_ev).';
COMMENT ON COLUMN recoup_refresh.coin_blind
  IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the refresh operation.';

SELECT add_constraints_to_recoup_refresh_partition('default');


-- ------------------------------ prewire ----------------------------------------

SELECT create_table_prewire();

COMMENT ON TABLE prewire
  IS 'pre-commit data for wire transfers we are about to execute';
COMMENT ON COLUMN prewire.failed
  IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';
COMMENT ON COLUMN prewire.finished
  IS 'set to TRUE once bank confirmed receiving the wire transfer request';
COMMENT ON COLUMN prewire.buf
  IS 'serialized data to send to the bank to execute the wire transfer';

-- ------------------------------ cs_nonce_locks ----------------------------------------

SELECT create_table_cs_nonce_locks();

COMMENT ON TABLE cs_nonce_locks
  IS 'ensures a Clause Schnorr client nonce is locked for use with an operation identified by a hash';
COMMENT ON COLUMN cs_nonce_locks.nonce
  IS 'actual nonce submitted by the client';
COMMENT ON COLUMN cs_nonce_locks.op_hash
  IS 'hash (RC for refresh, blind coin hash for withdraw) the nonce may be used with';
COMMENT ON COLUMN cs_nonce_locks.max_denomination_serial
  IS 'Maximum number of a CS denomination serial the nonce could be used with, for GC';

SELECT add_constraints_to_cs_nonce_locks_partition('default');


-- ------------------------------ purse_requests ----------------------------------------

SELECT create_table_purse_requests();

COMMENT ON TABLE purse_requests
  IS 'Requests establishing purses, associating them with a contract but without a target reserve';
COMMENT ON COLUMN purse_requests.purse_pub
  IS 'Public key of the purse';
COMMENT ON COLUMN purse_requests.purse_creation
  IS 'Local time when the purse was created. Determines applicable purse fees.';
COMMENT ON COLUMN purse_requests.purse_expiration
  IS 'When the purse is set to expire';
COMMENT ON COLUMN purse_requests.h_contract_terms
  IS 'Hash of the contract the parties are to agree to';
COMMENT ON COLUMN purse_requests.flags
  IS 'see the enum TALER_WalletAccountMergeFlags';
COMMENT ON COLUMN purse_requests.in_reserve_quota
  IS 'set to TRUE if this purse currently counts against the number of free purses in the respective reserve';
COMMENT ON COLUMN purse_requests.amount_with_fee_val
  IS 'Total amount expected to be in the purse';
COMMENT ON COLUMN purse_requests.purse_fee_val
  IS 'Purse fee the client agreed to pay from the reserve (accepted by the exchange at the time the purse was created). Zero if in_reserve_quota is TRUE.';
COMMENT ON COLUMN purse_requests.balance_val
  IS 'Total amount actually in the purse';
COMMENT ON COLUMN purse_requests.purse_sig
  IS 'Signature of the purse affirming the purse parameters, of type TALER_SIGNATURE_PURSE_REQUEST';

SELECT add_constraints_to_purse_requests_partition('default');


-- ------------------------------ purse_decisions ----------------------------------------

SELECT create_table_purse_decision();

COMMENT ON TABLE purse_decision
  IS 'Purses that were decided upon (refund or merge)';
COMMENT ON COLUMN purse_decision.purse_pub
  IS 'Public key of the purse';

SELECT add_constraints_to_purse_decision_partition('default');


-- ------------------------------ purse_merges ----------------------------------------

SELECT create_table_purse_merges();

COMMENT ON TABLE purse_merges
  IS 'Merge requests where a purse-owner requested merging the purse into the account';
COMMENT ON COLUMN purse_merges.partner_serial_id
  IS 'identifies the partner exchange, NULL in case the target reserve lives at this exchange';
COMMENT ON COLUMN purse_merges.reserve_pub
  IS 'public key of the target reserve';
COMMENT ON COLUMN purse_merges.purse_pub
  IS 'public key of the purse';
COMMENT ON COLUMN purse_merges.merge_sig
  IS 'signature by the purse private key affirming the merge, of type TALER_SIGNATURE_WALLET_PURSE_MERGE';
COMMENT ON COLUMN purse_merges.merge_timestamp
  IS 'when was the merge message signed';

SELECT add_constraints_to_purse_merges_partition('default');


-- ------------------------------ account_merges ----------------------------------------

SELECT create_table_account_merges();

COMMENT ON TABLE account_merges
  IS 'Merge requests where a purse- and account-owner requested merging the purse into the account';
COMMENT ON COLUMN account_merges.reserve_pub
  IS 'public key of the target reserve';
COMMENT ON COLUMN account_merges.purse_pub
  IS 'public key of the purse';
COMMENT ON COLUMN account_merges.reserve_sig
  IS 'signature by the reserve private key affirming the merge, of type TALER_SIGNATURE_WALLET_ACCOUNT_MERGE';

SELECT add_constraints_to_account_merges_partition('default');


-- ------------------------------ contracts ----------------------------------------

SELECT create_table_contracts();

COMMENT ON TABLE contracts
  IS 'encrypted contracts associated with purses';
COMMENT ON COLUMN contracts.purse_pub
  IS 'public key of the purse that the contract is associated with';
COMMENT ON COLUMN contracts.contract_sig
  IS 'signature over the encrypted contract by the purse contract key';
COMMENT ON COLUMN contracts.pub_ckey
  IS 'Public ECDH key used to encrypt the contract, to be used with the purse private key for decryption';
COMMENT ON COLUMN contracts.e_contract
  IS 'AES-GCM encrypted contract terms (contains gzip compressed JSON after decryption)';

SELECT add_constraints_to_contracts_partition('default');


-- ------------------------------ history_requests ----------------------------------------

SELECT create_table_history_requests();

COMMENT ON TABLE history_requests
  IS 'Paid history requests issued by a client against a reserve';
COMMENT ON COLUMN history_requests.request_timestamp
  IS 'When was the history request made';
COMMENT ON COLUMN history_requests.reserve_sig
  IS 'Signature approving payment for the history request';
COMMENT ON COLUMN history_requests.history_fee_val
  IS 'History fee approved by the signature';

-- ------------------------------ close_requests ----------------------------------------

SELECT create_table_close_requests();

COMMENT ON TABLE close_requests
  IS 'Explicit requests by a reserve owner to close a reserve immediately';
COMMENT ON COLUMN close_requests.close_timestamp
  IS 'When the request was created by the client';
COMMENT ON COLUMN close_requests.reserve_sig
  IS 'Signature affirming that the reserve is to be closed';
COMMENT ON COLUMN close_requests.close_val
  IS 'Balance of the reserve at the time of closing, to be wired to the associated bank account (minus the closing fee)';
COMMENT ON COLUMN close_requests.payto_uri
  IS 'Identifies the credited bank account. Optional.';

SELECT add_constraints_to_close_requests_partition('default');

-- ------------------------------ purse_deposits ----------------------------------------

SELECT create_table_purse_deposits();

COMMENT ON TABLE purse_deposits
  IS 'Requests depositing coins into a purse';
COMMENT ON COLUMN purse_deposits.partner_serial_id
  IS 'identifies the partner exchange, NULL in case the target purse lives at this exchange';
COMMENT ON COLUMN purse_deposits.purse_pub
  IS 'Public key of the purse';
COMMENT ON COLUMN purse_deposits.coin_pub
  IS 'Public key of the coin being deposited';
COMMENT ON COLUMN purse_deposits.amount_with_fee_val
  IS 'Total amount being deposited';
COMMENT ON COLUMN purse_deposits.coin_sig
  IS 'Signature of the coin affirming the deposit into the purse, of type TALER_SIGNATURE_PURSE_DEPOSIT';

SELECT add_constraints_to_purse_deposits_partition('default');


-- ------------------------------ wads_out ----------------------------------------

SELECT create_table_wads_out();

COMMENT ON TABLE wads_out
  IS 'Wire transfers made to another exchange to transfer purse funds';
COMMENT ON COLUMN wads_out.wad_id
  IS 'Unique identifier of the wad, part of the wire transfer subject';
COMMENT ON COLUMN wads_out.partner_serial_id
  IS 'target exchange of the wad';
COMMENT ON COLUMN wads_out.amount_val
  IS 'Amount that was wired';
COMMENT ON COLUMN wads_out.execution_time
  IS 'Time when the wire transfer was scheduled';

SELECT add_constraints_to_wads_out_partition('default');


-- ------------------------------ wads_out_entries ----------------------------------------

SELECT create_table_wad_out_entries();

COMMENT ON TABLE wad_out_entries
  IS 'Purses combined into a wad';
COMMENT ON COLUMN wad_out_entries.wad_out_serial_id
  IS 'Wad the purse was part of';
COMMENT ON COLUMN wad_out_entries.reserve_pub
  IS 'Target reserve for the purse';
COMMENT ON COLUMN wad_out_entries.purse_pub
  IS 'Public key of the purse';
COMMENT ON COLUMN wad_out_entries.h_contract
  IS 'Hash of the contract associated with the purse';
COMMENT ON COLUMN wad_out_entries.purse_expiration
  IS 'Time when the purse expires';
COMMENT ON COLUMN wad_out_entries.merge_timestamp
  IS 'Time when the merge was approved';
COMMENT ON COLUMN wad_out_entries.amount_with_fee_val
  IS 'Total amount in the purse';
COMMENT ON COLUMN wad_out_entries.wad_fee_val
  IS 'Wat fee charged to the purse';
COMMENT ON COLUMN wad_out_entries.deposit_fees_val
  IS 'Total deposit fees charged to the purse';
COMMENT ON COLUMN wad_out_entries.reserve_sig
  IS 'Signature by the receiving reserve, of purpose TALER_SIGNATURE_ACCOUNT_MERGE';
COMMENT ON COLUMN wad_out_entries.purse_sig
  IS 'Signature by the purse of purpose TALER_SIGNATURE_PURSE_MERGE';

SELECT add_constraints_to_wad_out_entries_partition('default');

-- ------------------------------ wads_in ----------------------------------------

SELECT create_table_wads_in();

COMMENT ON TABLE wads_in
  IS 'Incoming exchange-to-exchange wad wire transfers';
COMMENT ON COLUMN wads_in.wad_id
  IS 'Unique identifier of the wad, part of the wire transfer subject';
COMMENT ON COLUMN wads_in.origin_exchange_url
  IS 'Base URL of the originating URL, also part of the wire transfer subject';
COMMENT ON COLUMN wads_in.amount_val
  IS 'Actual amount that was received by our exchange';
COMMENT ON COLUMN wads_in.arrival_time
  IS 'Time when the wad was received';

SELECT add_constraints_to_wads_in_partition('default');


-- ------------------------------ wads_in_entries ----------------------------------------

SELECT create_table_wad_in_entries();

COMMENT ON TABLE wad_in_entries
  IS 'list of purses aggregated in a wad according to the sending exchange';
COMMENT ON COLUMN wad_in_entries.wad_in_serial_id
  IS 'wad for which the given purse was included in the aggregation';
COMMENT ON COLUMN wad_in_entries.reserve_pub
  IS 'target account of the purse (must be at the local exchange)';
COMMENT ON COLUMN wad_in_entries.purse_pub
  IS 'public key of the purse that was merged';
COMMENT ON COLUMN wad_in_entries.h_contract
  IS 'hash of the contract terms of the purse';
COMMENT ON COLUMN wad_in_entries.purse_expiration
  IS 'Time when the purse was set to expire';
COMMENT ON COLUMN wad_in_entries.merge_timestamp
  IS 'Time when the merge was approved';
COMMENT ON COLUMN wad_in_entries.amount_with_fee_val
  IS 'Total amount in the purse';
COMMENT ON COLUMN wad_in_entries.wad_fee_val
  IS 'Total wad fees paid by the purse';
COMMENT ON COLUMN wad_in_entries.deposit_fees_val
  IS 'Total deposit fees paid when depositing coins into the purse';
COMMENT ON COLUMN wad_in_entries.reserve_sig
  IS 'Signature by the receiving reserve, of purpose TALER_SIGNATURE_ACCOUNT_MERGE';
COMMENT ON COLUMN wad_in_entries.purse_sig
  IS 'Signature by the purse of purpose TALER_SIGNATURE_PURSE_MERGE';

SELECT add_constraints_to_wad_in_entries_partition('default');
