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
