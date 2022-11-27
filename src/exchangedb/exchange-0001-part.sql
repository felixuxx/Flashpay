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

-- ------------------------------ legitimization_processes ----------------------------------------

SELECT create_table_legitimization_processes();

COMMENT ON TABLE legitimization_processes
  IS 'List of legitimization processes (ongoing and completed) by account and provider';
COMMENT ON COLUMN legitimization_processes.legitimization_process_serial_id
  IS 'unique ID for this legitimization process at the exchange';
COMMENT ON COLUMN legitimization_processes.h_payto
  IS 'foreign key linking the entry to the wire_targets table, NOT a primary key (multiple legitimizations are possible per wire target)';
COMMENT ON COLUMN legitimization_processes.expiration_time
  IS 'in the future if the respective KYC check was passed successfully';
COMMENT ON COLUMN legitimization_processes.provider_section
  IS 'Configuration file section with details about this provider';
COMMENT ON COLUMN legitimization_processes.provider_user_id
  IS 'Identifier for the user at the provider that was used for the legitimization. NULL if provider is unaware.';
COMMENT ON COLUMN legitimization_processes.provider_legitimization_id
  IS 'Identifier for the specific legitimization process at the provider. NULL if legitimization was not started.';

SELECT add_constraints_to_legitimization_processes_partition('default');


-- ------------------------------ legitimization_requirements_ ----------------------------------------

SELECT create_table_legitimization_requirements();

COMMENT ON TABLE legitimization_requirements
  IS 'List of required legitimization by account';
COMMENT ON COLUMN legitimization_requirements.legitimization_requirement_serial_id
  IS 'unique ID for this legitimization requirement at the exchange';
COMMENT ON COLUMN legitimization_requirements.h_payto
  IS 'foreign key linking the entry to the wire_targets table, NOT a primary key (multiple legitimizations are possible per wire target)';
COMMENT ON COLUMN legitimization_requirements.required_checks
  IS 'space-separated list of required checks';

SELECT add_constraints_to_legitimization_requirements_partition('default');



-- ------------------------------ reserves ----------------------------------------

SELECT create_table_reserves();

COMMENT ON TABLE reserves
  IS 'Summarizes the balance of a reserve. Updated when new funds are added or withdrawn.';
COMMENT ON COLUMN reserves.reserve_pub
  IS 'EdDSA public key of the reserve. Knowledge of the private key implies ownership over the balance.';
COMMENT ON COLUMN reserves.current_balance_val
  IS 'Current balance remaining with the reserve.';
COMMENT ON COLUMN reserves.purses_active
  IS 'Number of purses that were created by this reserve that are not expired and not fully paid.';
COMMENT ON COLUMN reserves.purses_allowed
  IS 'Number of purses that this reserve is allowed to have active at most.';
COMMENT ON COLUMN reserves.expiration_date
  IS 'Used to trigger closing of reserves that have not been drained after some time';
COMMENT ON COLUMN reserves.gc_date
  IS 'Used to forget all information about a reserve during garbage collection';

-- ------------------------------ reserves_in ----------------------------------------

SELECT create_table_reserves_in();

COMMENT ON TABLE reserves_in
  IS 'list of transfers of funds into the reserves, one per incoming wire transfer';
COMMENT ON COLUMN reserves_in.wire_source_h_payto
  IS 'Identifies the debited bank account and KYC status';
COMMENT ON COLUMN reserves_in.reserve_pub
  IS 'Public key of the reserve. Private key signifies ownership of the remaining balance.';
COMMENT ON COLUMN reserves_in.credit_val
  IS 'Amount that was transferred into the reserve';


SELECT add_constraints_to_reserves_in_partition('default');

-- ------------------------------ reserves_close ----------------------------------------

SELECT create_table_reserves_close();

COMMENT ON TABLE reserves_close
  IS 'wire transfers executed by the reserve to close reserves';
COMMENT ON COLUMN reserves_close.wire_target_h_payto
  IS 'Identifies the credited bank account (and KYC status). Note that closing does not depend on KYC.';


SELECT add_constraints_to_reserves_close_partition('default');






-- ------------------------------ reserves_open_requests ----------------------------------------

SELECT create_table_reserves_open_requests();

COMMENT ON TABLE reserves_open_requests
  IS 'requests to keep a reserve open';
COMMENT ON COLUMN reserves_open_requests.reserve_payment_val
  IS 'Funding to pay for the request from the reserve balance itself.';

SELECT add_constraints_to_reserves_open_request_partition('default');


-- ------------------------------ reserves_open_deposits ----------------------------------------

SELECT create_table_reserves_open_deposits();

COMMENT ON TABLE reserves_open_deposits
  IS 'coin contributions paying for a reserve to remain open';
COMMENT ON COLUMN reserves_open_deposits.reserve_pub
  IS 'Identifies the specific reserve being paid for (possibly together with reserve_sig).';


SELECT add_constraints_to_reserves_open_deposits_partition('default');


-- ------------------------------ reserves_out ----------------------------------------

SELECT create_table_reserves_out();

COMMENT ON TABLE reserves_out
  IS 'Withdraw operations performed on reserves.';
COMMENT ON COLUMN reserves_out.h_blind_ev
  IS 'Hash of the blinded coin, used as primary key here so that broken clients that use a non-random coin or blinding factor fail to withdraw (otherwise they would fail on deposit when the coin is not unique there).';
COMMENT ON COLUMN reserves_out.denominations_serial
  IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';

SELECT add_constraints_to_reserves_out_partition('default');


SELECT create_table_reserves_out_by_reserve();

COMMENT ON TABLE reserves_out_by_reserve
  IS 'Information in this table is strictly redundant with that of reserves_out, but saved by a different primary key for fast lookups by reserve public key/uuid.';

CREATE OR REPLACE FUNCTION reserves_out_by_reserve_insert_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  INSERT INTO exchange.reserves_out_by_reserve
    (reserve_uuid
    ,h_blind_ev)
  VALUES
    (NEW.reserve_uuid
    ,NEW.h_blind_ev);
  RETURN NEW;
END $$;
COMMENT ON FUNCTION reserves_out_by_reserve_insert_trigger()
  IS 'Replicate reserve_out inserts into reserve_out_by_reserve table.';

CREATE TRIGGER reserves_out_on_insert
  AFTER INSERT
   ON reserves_out
   FOR EACH ROW EXECUTE FUNCTION reserves_out_by_reserve_insert_trigger();

CREATE OR REPLACE FUNCTION reserves_out_by_reserve_delete_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  DELETE FROM exchange.reserves_out_by_reserve
   WHERE reserve_uuid = OLD.reserve_uuid;
  RETURN OLD;
END $$;
COMMENT ON FUNCTION reserves_out_by_reserve_delete_trigger()
  IS 'Replicate reserve_out deletions into reserve_out_by_reserve table.';

CREATE TRIGGER reserves_out_on_delete
  AFTER DELETE
    ON reserves_out
   FOR EACH ROW EXECUTE FUNCTION reserves_out_by_reserve_delete_trigger();


-- ------------------------------ known_coins ----------------------------------------

SELECT create_table_known_coins();

COMMENT ON TABLE known_coins
  IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';
COMMENT ON COLUMN known_coins.denominations_serial
  IS 'Denomination of the coin, determines the value of the original coin and applicable fees for coin-specific operations.';
COMMENT ON COLUMN known_coins.coin_pub
  IS 'EdDSA public key of the coin';
COMMENT ON COLUMN known_coins.remaining_val
  IS 'Value of the coin that remains to be spent';
COMMENT ON COLUMN known_coins.age_commitment_hash
  IS 'Optional hash of the age commitment for age restrictions as per DD 24 (active if denom_type has the respective bit set)';
COMMENT ON COLUMN known_coins.denom_sig
  IS 'This is the signature of the exchange that affirms that the coin is a valid coin. The specific signature type depends on denom_type of the denomination.';

SELECT add_constraints_to_known_coins_partition('default');


-- ------------------------------ refresh_commitments ----------------------------------------

SELECT create_table_refresh_commitments();

COMMENT ON TABLE refresh_commitments
  IS 'Commitments made when melting coins and the gamma value chosen by the exchange.';
COMMENT ON COLUMN refresh_commitments.noreveal_index
  IS 'The gamma value chosen by the exchange in the cut-and-choose protocol';
COMMENT ON COLUMN refresh_commitments.rc
  IS 'Commitment made by the client, hash over the various client inputs in the cut-and-choose protocol';
COMMENT ON COLUMN refresh_commitments.old_coin_pub
  IS 'Coin being melted in the refresh process.';

SELECT add_constraints_to_refresh_commitments_partition('default');


-- ------------------------------ refresh_revealed_coins ----------------------------------------

SELECT create_table_refresh_revealed_coins();

COMMENT ON TABLE refresh_revealed_coins
  IS 'Revelations about the new coins that are to be created during a melting session.';
COMMENT ON COLUMN refresh_revealed_coins.rrc_serial
  IS 'needed for exchange-auditor replication logic';
COMMENT ON COLUMN refresh_revealed_coins.melt_serial_id
  IS 'Identifies the refresh commitment (rc) of the melt operation.';
COMMENT ON COLUMN refresh_revealed_coins.freshcoin_index
  IS 'index of the fresh coin being created (one melt operation may result in multiple fresh coins)';
COMMENT ON COLUMN refresh_revealed_coins.coin_ev
  IS 'envelope of the new coin to be signed';
COMMENT ON COLUMN refresh_revealed_coins.ewv
  IS 'exchange contributed values in the creation of the fresh coin (see /csr)';
COMMENT ON COLUMN refresh_revealed_coins.h_coin_ev
  IS 'hash of the envelope of the new coin to be signed (for lookups)';
COMMENT ON COLUMN refresh_revealed_coins.ev_sig
  IS 'exchange signature over the envelope';

SELECT add_constraints_to_refresh_revealed_coins_partition('default');


-- ------------------------------ refresh_transfer_keys ----------------------------------------

SELECT create_table_refresh_transfer_keys();

COMMENT ON TABLE refresh_transfer_keys
  IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';
COMMENT ON COLUMN refresh_transfer_keys.rtc_serial
  IS 'needed for exchange-auditor replication logic';
COMMENT ON COLUMN refresh_transfer_keys.melt_serial_id
  IS 'Identifies the refresh commitment (rc) of the operation.';
COMMENT ON COLUMN refresh_transfer_keys.transfer_pub
  IS 'transfer public key for the gamma index';
COMMENT ON COLUMN refresh_transfer_keys.transfer_privs
  IS 'array of TALER_CNC_KAPPA - 1 transfer private keys that have been revealed, with the gamma entry being skipped';

SELECT add_constraints_to_refresh_transfer_keys_partition('default');


-- ------------------------------ deposits ----------------------------------------

SELECT create_table_deposits();

COMMENT ON TABLE deposits
  IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';
COMMENT ON COLUMN deposits.shard
  IS 'Used for load sharding in the materialized indices. Should be set based on merchant_pub. 64-bit value because we need an *unsigned* 32-bit value.';
COMMENT ON COLUMN deposits.known_coin_id
  IS 'Used for garbage collection';
COMMENT ON COLUMN deposits.wire_target_h_payto
  IS 'Identifies the target bank account and KYC status';
COMMENT ON COLUMN deposits.wire_salt
  IS 'Salt used when hashing the payto://-URI to get the h_wire';
COMMENT ON COLUMN deposits.done
  IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';
COMMENT ON COLUMN deposits.policy_blocked
  IS 'True if the aggregation of the deposit is currently blocked by some policy extension mechanism. Used to filter out deposits that must not be processed by the canonical deposit logic.';
COMMENT ON COLUMN deposits.policy_details_serial_id
  IS 'References policy extensions table, NULL if extensions are not used';

SELECT add_constraints_to_deposits_partition('default');


SELECT create_table_deposits_by_ready();

COMMENT ON TABLE deposits_by_ready
  IS 'Enables fast lookups for deposits_get_ready, auto-populated via TRIGGER below';


SELECT create_table_deposits_for_matching();

COMMENT ON TABLE deposits_for_matching
  IS 'Enables fast lookups for deposits_iterate_matching, auto-populated via TRIGGER below';

CREATE OR REPLACE FUNCTION deposits_insert_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  is_ready BOOLEAN;
BEGIN
  is_ready  = NOT (NEW.done OR NEW.policy_blocked);

  IF (is_ready)
  THEN
    INSERT INTO exchange.deposits_by_ready
      (wire_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.wire_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
    INSERT INTO exchange.deposits_for_matching
      (refund_deadline
      ,merchant_pub
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.refund_deadline
      ,NEW.merchant_pub
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
  END IF;
  RETURN NEW;
END $$;
COMMENT ON FUNCTION deposits_insert_trigger()
  IS 'Replicate deposit inserts into materialized indices.';

CREATE TRIGGER deposits_on_insert
  AFTER INSERT
   ON deposits
   FOR EACH ROW EXECUTE FUNCTION deposits_insert_trigger();

CREATE OR REPLACE FUNCTION deposits_update_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  was_ready BOOLEAN;
DECLARE
  is_ready BOOLEAN;
BEGIN
  was_ready = NOT (OLD.done OR OLD.policy_blocked);
  is_ready  = NOT (NEW.done OR NEW.policy_blocked);
  IF (was_ready AND NOT is_ready)
  THEN
    DELETE FROM exchange.deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
    DELETE FROM exchange.deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND merchant_pub = OLD.merchant_pub
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  IF (is_ready AND NOT was_ready)
  THEN
    INSERT INTO exchange.deposits_by_ready
      (wire_deadline
      ,shard
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.wire_deadline
      ,NEW.shard
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
    INSERT INTO exchange.deposits_for_matching
      (refund_deadline
      ,merchant_pub
      ,coin_pub
      ,deposit_serial_id)
    VALUES
      (NEW.refund_deadline
      ,NEW.merchant_pub
      ,NEW.coin_pub
      ,NEW.deposit_serial_id);
  END IF;
  RETURN NEW;
END $$;
COMMENT ON FUNCTION deposits_update_trigger()
  IS 'Replicate deposits changes into materialized indices.';

CREATE TRIGGER deposits_on_update
  AFTER UPDATE
    ON deposits
   FOR EACH ROW EXECUTE FUNCTION deposits_update_trigger();

CREATE OR REPLACE FUNCTION deposits_delete_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  was_ready BOOLEAN;
BEGIN
  was_ready  = NOT (OLD.done OR OLD.policy_blocked);

  IF (was_ready)
  THEN
    DELETE FROM exchange.deposits_by_ready
     WHERE wire_deadline = OLD.wire_deadline
       AND shard = OLD.shard
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
    DELETE FROM exchange.deposits_for_matching
     WHERE refund_deadline = OLD.refund_deadline
       AND merchant_pub = OLD.merchant_pub
       AND coin_pub = OLD.coin_pub
       AND deposit_serial_id = OLD.deposit_serial_id;
  END IF;
  RETURN NEW;
END $$;
COMMENT ON FUNCTION deposits_delete_trigger()
  IS 'Replicate deposit deletions into materialized indices.';

CREATE TRIGGER deposits_on_delete
  AFTER DELETE
   ON deposits
   FOR EACH ROW EXECUTE FUNCTION deposits_delete_trigger();


-- ------------------------------ refunds ----------------------------------------

SELECT create_table_refunds();

COMMENT ON TABLE refunds
  IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';
COMMENT ON COLUMN refunds.deposit_serial_id
  IS 'Identifies ONLY the merchant_pub, h_contract_terms and coin_pub. Multiple deposits may match a refund, this only identifies one of them.';
COMMENT ON COLUMN refunds.rtransaction_id
  IS 'used by the merchant to make refunds unique in case the same coin for the same deposit gets a subsequent (higher) refund';

SELECT add_constraints_to_refunds_partition('default');


-- ------------------------------ wire_out ----------------------------------------

SELECT create_table_wire_out();

COMMENT ON TABLE wire_out
  IS 'wire transfers the exchange has executed';
COMMENT ON COLUMN wire_out.exchange_account_section
  IS 'identifies the configuration section with the debit account of this payment';
COMMENT ON COLUMN wire_out.wire_target_h_payto
  IS 'Identifies the credited bank account and KYC status';

SELECT add_constraints_to_wire_out_partition('default');

CREATE OR REPLACE FUNCTION wire_out_delete_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  DELETE FROM exchange.aggregation_tracking
   WHERE wtid_raw = OLD.wtid_raw;
  RETURN OLD;
END $$;
COMMENT ON FUNCTION wire_out_delete_trigger()
  IS 'Replicate reserve_out deletions into aggregation_tracking. This replaces an earlier use of an ON DELETE CASCADE that required a DEFERRABLE constraint and conflicted with nice partitioning.';

CREATE TRIGGER wire_out_on_delete
  AFTER DELETE
    ON wire_out
   FOR EACH ROW EXECUTE FUNCTION wire_out_delete_trigger();



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
