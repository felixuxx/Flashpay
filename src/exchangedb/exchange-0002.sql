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

-- Need 'failed' bit to prevent hanging transfer tool in case
-- bank API fails.
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


-- need serial IDs on various tables for exchange-auditor replication
ALTER TABLE denominations
  ADD COLUMN denominations_serial BIGSERIAL UNIQUE;
COMMENT ON COLUMN denominations.denominations_serial
  IS 'needed for exchange-auditor replication logic';
ALTER TABLE refresh_revealed_coins
  ADD COLUMN rrc_serial BIGSERIAL UNIQUE;
COMMENT ON COLUMN refresh_revealed_coins.rrc_serial
  IS 'needed for exchange-auditor replication logic';
ALTER TABLE refresh_transfer_keys
  ADD COLUMN rtc_serial BIGSERIAL UNIQUE;
COMMENT ON COLUMN refresh_transfer_keys.rtc_serial
  IS 'needed for exchange-auditor replication logic';
ALTER TABLE wire_fee
  ADD COLUMN wire_fee_serial BIGSERIAL UNIQUE;
COMMENT ON COLUMN wire_fee.wire_fee_serial
  IS 'needed for exchange-auditor replication logic';

-- for the reserves, we add the new reserve_uuid, and also
-- change the foreign keys to use the new BIGSERIAL instead
-- of the public key to reference the entry
ALTER TABLE reserves
  ADD COLUMN reserve_uuid BIGSERIAL UNIQUE;
ALTER TABLE reserves_in
  ADD COLUMN reserve_uuid INT8 REFERENCES reserves (reserve_uuid) ON DELETE CASCADE;
UPDATE reserves_in
  SET reserve_uuid=r.reserve_uuid
  FROM reserves_in rin
  INNER JOIN reserves r USING(reserve_pub);
ALTER TABLE reserves_in
  ALTER COLUMN reserve_uuid SET NOT NULL;
ALTER TABLE reserves_in
  DROP COLUMN reserve_pub;
ALTER TABLE reserves_out
  ADD COLUMN reserve_uuid INT8 REFERENCES reserves (reserve_uuid) ON DELETE CASCADE;
UPDATE reserves_out
  SET reserve_uuid=r.reserve_uuid
  FROM reserves_out rout
  INNER JOIN reserves r USING(reserve_pub);
ALTER TABLE reserves_out
  ALTER COLUMN reserve_uuid SET NOT NULL;
ALTER TABLE reserves_out
  DROP COLUMN reserve_pub;
ALTER TABLE reserves_close
  ADD COLUMN reserve_uuid INT8 REFERENCES reserves (reserve_uuid) ON DELETE CASCADE;
UPDATE reserves_close
  SET reserve_uuid=r.reserve_uuid
  FROM reserves_close rclose
  INNER JOIN reserves r USING(reserve_pub);
ALTER TABLE reserves_close
  ALTER COLUMN reserve_uuid SET NOT NULL;
ALTER TABLE reserves_close
  DROP COLUMN reserve_pub;

-- change all foreign keys using 'denom_pub_hash' to using 'denominations_serial' instead
ALTER TABLE reserves_out
  ADD COLUMN denominations_serial INT8 REFERENCES denominations (denominations_serial) ON DELETE CASCADE;
UPDATE reserves_out
  SET denominations_serial=d.denominations_serial
  FROM reserves_out o
  INNER JOIN denominations d USING(denom_pub_hash);
ALTER TABLE reserves_out
  ALTER COLUMN denominations_serial SET NOT NULL;
ALTER TABLE reserves_out
  DROP COLUMN denom_pub_hash;

ALTER TABLE known_coins
  ADD COLUMN denominations_serial INT8 REFERENCES denominations (denominations_serial) ON DELETE CASCADE;
UPDATE known_coins
  SET denominations_serial=d.denominations_serial
  FROM known_coins o
  INNER JOIN denominations d USING(denom_pub_hash);
ALTER TABLE known_coins
  ALTER COLUMN denominations_serial SET NOT NULL;
ALTER TABLE known_coins
  DROP COLUMN denom_pub_hash;

ALTER TABLE denomination_revocations
  ADD COLUMN denominations_serial INT8 REFERENCES denominations (denominations_serial) ON DELETE CASCADE;
UPDATE denomination_revocations
  SET denominations_serial=d.denominations_serial
  FROM denomination_revocations o
  INNER JOIN denominations d USING(denom_pub_hash);
ALTER TABLE denomination_revocations
  ALTER COLUMN denominations_serial SET NOT NULL;
ALTER TABLE denomination_revocations
  DROP COLUMN denom_pub_hash;
ALTER TABLE denomination_revocations
  ADD CONSTRAINT denominations_serial_pk PRIMARY KEY (denominations_serial);

ALTER TABLE refresh_revealed_coins
  ADD COLUMN denominations_serial INT8 REFERENCES denominations (denominations_serial) ON DELETE CASCADE;
UPDATE refresh_revealed_coins
  SET denominations_serial=d.denominations_serial
  FROM refresh_revealed_coins o
  INNER JOIN denominations d USING(denom_pub_hash);
ALTER TABLE refresh_revealed_coins
  ALTER COLUMN denominations_serial SET NOT NULL;
ALTER TABLE refresh_revealed_coins
  DROP COLUMN denom_pub_hash;

-- Change all foreign keys involving 'coin_pub' to use known_coin_id instead.
ALTER TABLE recoup_refresh
  ADD COLUMN known_coin_id INT8 REFERENCES known_coins (known_coin_id) ON DELETE CASCADE;
UPDATE recoup_refresh
  SET known_coin_id=d.known_coin_id
  FROM recoup_refresh o
  INNER JOIN known_coins d USING(coin_pub);
ALTER TABLE recoup_refresh
  ALTER COLUMN known_coin_id SET NOT NULL;
ALTER TABLE recoup_refresh
  DROP COLUMN coin_pub;

ALTER TABLE recoup
  ADD COLUMN known_coin_id INT8 REFERENCES known_coins (known_coin_id) ON DELETE CASCADE;
UPDATE recoup
  SET known_coin_id=d.known_coin_id
  FROM recoup o
  INNER JOIN known_coins d USING(coin_pub);
ALTER TABLE recoup
  ALTER COLUMN known_coin_id SET NOT NULL;
ALTER TABLE recoup
  DROP COLUMN coin_pub;

ALTER TABLE refresh_commitments
  ADD COLUMN old_known_coin_id INT8 REFERENCES known_coins (known_coin_id) ON DELETE CASCADE;
UPDATE refresh_commitments
  SET old_known_coin_id=d.known_coin_id
  FROM refresh_commitments o
  INNER JOIN known_coins d ON(o.old_coin_pub=d.coin_pub);
ALTER TABLE refresh_commitments
  ALTER COLUMN old_known_coin_id SET NOT NULL;
ALTER TABLE refresh_commitments
  DROP COLUMN old_coin_pub;

ALTER TABLE deposits
  ADD COLUMN known_coin_id INT8 REFERENCES known_coins (known_coin_id) ON DELETE CASCADE;
UPDATE deposits
  SET known_coin_id=d.known_coin_id
  FROM deposits o
  INNER JOIN known_coins d USING(coin_pub);
ALTER TABLE deposits
  ALTER COLUMN known_coin_id SET NOT NULL;
ALTER TABLE deposits
  DROP COLUMN coin_pub;

ALTER TABLE refunds
  ADD COLUMN known_coin_id INT8 REFERENCES known_coins (known_coin_id) ON DELETE CASCADE;
UPDATE refunds
  SET known_coin_id=d.known_coin_id
  FROM refunds o
  INNER JOIN known_coins d USING(coin_pub);
ALTER TABLE refunds
  ALTER COLUMN known_coin_id SET NOT NULL;
ALTER TABLE refunds
  DROP COLUMN coin_pub;

-- Change 'h_blind_ev' in recoup table to 'reserve_out_serial_id'
ALTER TABLE recoup
  ADD COLUMN reserve_out_serial_id INT8 REFERENCES reserves_out (reserve_out_serial_id) ON DELETE CASCADE;
UPDATE recoup
  SET reserve_out_serial_id=d.reserve_out_serial_id
  FROM recoup o
  INNER JOIN reserves_out d USING(h_blind_ev);
ALTER TABLE recoup
  ALTER COLUMN reserve_out_serial_id SET NOT NULL;
ALTER TABLE recoup
  DROP COLUMN h_blind_ev;
COMMENT ON COLUMN recoup.reserve_out_serial_id
  IS 'Identifies the h_blind_ev of the recouped coin.';


-- Change 'h_blind_ev' in recoup_refresh table to 'rrc_serial'
ALTER TABLE recoup_refresh
  ADD COLUMN rrc_serial INT8 REFERENCES refresh_revealed_coins (rrc_serial) ON DELETE CASCADE;
UPDATE recoup_refresh
  SET rrc_serial=d.rrc_serial
  FROM recoup_refresh o
  INNER JOIN refresh_revealed_coins d ON (d.h_coin_ev = o.h_blind_ev);
ALTER TABLE recoup_refresh
  ALTER COLUMN rrc_serial SET NOT NULL;
ALTER TABLE recoup_refresh
  DROP COLUMN h_blind_ev;
COMMENT ON COLUMN recoup_refresh.rrc_serial
  IS 'Identifies the h_blind_ev of the recouped coin (as h_coin_ev).';


-- Change 'rc' in refresh_transfer_keys and refresh_revealed_coins tables to 'melt_serial_id'
ALTER TABLE refresh_transfer_keys
  ADD COLUMN melt_serial_id INT8 REFERENCES refresh_commitments (melt_serial_id) ON DELETE CASCADE;
UPDATE refresh_transfer_keys
  SET melt_serial_id=d.melt_serial_id
  FROM refresh_transfer_keys o
  INNER JOIN refresh_commitments d ON (d.rc = o.rc);
ALTER TABLE refresh_transfer_keys
  ALTER COLUMN melt_serial_id SET NOT NULL;
ALTER TABLE refresh_transfer_keys
  DROP COLUMN rc;
COMMENT ON COLUMN refresh_transfer_keys.melt_serial_id
  IS 'Identifies the refresh commitment (rc) of the operation.';

ALTER TABLE refresh_revealed_coins
  ADD COLUMN melt_serial_id INT8 REFERENCES refresh_commitments (melt_serial_id) ON DELETE CASCADE;
UPDATE refresh_revealed_coins
  SET melt_serial_id=d.melt_serial_id
  FROM refresh_revealed_coins o
  INNER JOIN refresh_commitments d ON (d.rc = o.rc);
ALTER TABLE refresh_revealed_coins
  ALTER COLUMN melt_serial_id SET NOT NULL;
ALTER TABLE refresh_revealed_coins
  DROP COLUMN rc;
COMMENT ON COLUMN refresh_revealed_coins.melt_serial_id
  IS 'Identifies the refresh commitment (rc) of the operation.';


-- Change 'merchant_pub' and 'h_contract_terms' and 'known_coin_id' in 'refunds' table
-- to 'deposit_serial_id' instead!
ALTER TABLE refunds
  ADD COLUMN deposit_serial_id INT8 REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE;
UPDATE refunds
  SET deposit_serial_id=d.deposit_serial_id
  FROM refunds o
  INNER JOIN deposits d
    ON ( (d.known_coin_id = o.known_coin_id) AND
         (d.h_contract_terms = o.h_contract_terms) AND
         (d.merchant_pub = o.merchant_pub) );
ALTER TABLE refunds
  ALTER COLUMN deposit_serial_id SET NOT NULL;
ALTER TABLE refunds
  DROP COLUMN merchant_pub,
  DROP COLUMN h_contract_terms,
  DROP COLUMN known_coin_id;
COMMENT ON COLUMN refunds.deposit_serial_id
  IS 'Identifies ONLY the merchant_pub, h_contract_terms and known_coin_id. Multiple deposits may match a refund, this only identifies one of them.';


-- Create additional tables...

CREATE TABLE IF NOT EXISTS auditors
  (auditor_uuid BIGSERIAL UNIQUE
  ,auditor_pub BYTEA PRIMARY KEY CHECK (LENGTH(auditor_pub)=32)
  ,auditor_name VARCHAR NOT NULL
  ,auditor_url VARCHAR NOT NULL
  ,is_active BOOLEAN NOT NULL
  ,last_change INT8 NOT NULL
  );
COMMENT ON TABLE auditors
  IS 'Table with auditors the exchange uses or has used in the past. Entries never expire as we need to remember the last_change column indefinitely.';
COMMENT ON COLUMN auditors.auditor_pub
  IS 'Public key of the auditor.';
COMMENT ON COLUMN auditors.auditor_url
  IS 'The base URL of the auditor.';
COMMENT ON COLUMN auditors.is_active
  IS 'true if we are currently supporting the use of this auditor.';
COMMENT ON COLUMN auditors.last_change
  IS 'Latest time when active status changed. Used to detect replays of old messages.';


CREATE TABLE IF NOT EXISTS auditor_denom_sigs
  (auditor_denom_serial BIGSERIAL UNIQUE
  ,auditor_uuid INT8 NOT NULL REFERENCES auditors (auditor_uuid) ON DELETE CASCADE
  ,denominations_serial INT8 NOT NULL REFERENCES denominations (denominations_serial) ON DELETE CASCADE
  ,auditor_sig BYTEA CHECK (LENGTH(auditor_sig)=64)
  ,PRIMARY KEY (denominations_serial, auditor_uuid)
  );
COMMENT ON TABLE auditor_denom_sigs
  IS 'Table with auditor signatures on exchange denomination keys.';
COMMENT ON COLUMN auditor_denom_sigs.auditor_uuid
  IS 'Identifies the auditor.';
COMMENT ON COLUMN auditor_denom_sigs.denominations_serial
  IS 'Denomination the signature is for.';
COMMENT ON COLUMN auditor_denom_sigs.auditor_sig
  IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';


CREATE TABLE IF NOT EXISTS exchange_sign_keys
  (esk_serial BIGSERIAL UNIQUE
  ,exchange_pub BYTEA PRIMARY KEY CHECK (LENGTH(exchange_pub)=32)
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  ,valid_from INT8 NOT NULL
  ,expire_sign INT8 NOT NULL
  ,expire_legal INT8 NOT NULL
  );
COMMENT ON TABLE exchange_sign_keys
  IS 'Table with master public key signatures on exchange online signing keys.';
COMMENT ON COLUMN exchange_sign_keys.exchange_pub
  IS 'Public online signing key of the exchange.';
COMMENT ON COLUMN exchange_sign_keys.master_sig
  IS 'Signature affirming the validity of the signing key of purpose TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.';
COMMENT ON COLUMN exchange_sign_keys.valid_from
  IS 'Time when this online signing key will first be used to sign messages.';
COMMENT ON COLUMN exchange_sign_keys.expire_sign
  IS 'Time when this online signing key will no longer be used to sign.';
COMMENT ON COLUMN exchange_sign_keys.expire_legal
  IS 'Time when this online signing key legally expires.';


CREATE TABLE IF NOT EXISTS wire_accounts
  (payto_uri VARCHAR PRIMARY KEY
  ,master_sig BYTEA CHECK (LENGTH(master_sig)=64)
  ,is_active BOOLEAN NOT NULL
  ,last_change INT8 NOT NULL
  );
COMMENT ON TABLE wire_accounts
  IS 'Table with current and historic bank accounts of the exchange. Entries never expire as we need to remember the last_change column indefinitely.';
COMMENT ON COLUMN wire_accounts.payto_uri
  IS 'payto URI (RFC 8905) with the bank account of the exchange.';
COMMENT ON COLUMN wire_accounts.master_sig
  IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS';
COMMENT ON COLUMN wire_accounts.is_active
  IS 'true if we are currently supporting the use of this account.';
COMMENT ON COLUMN wire_accounts.last_change
  IS 'Latest time when active status changed. Used to detect replays of old messages.';
-- "wire_accounts" has no BIGSERIAL because it is a 'mutable' table
--            and is of no concern to the auditor


CREATE TABLE IF NOT EXISTS signkey_revocations
  (signkey_revocations_serial_id BIGSERIAL UNIQUE
  ,esk_serial INT8 PRIMARY KEY REFERENCES exchange_sign_keys (esk_serial) ON DELETE CASCADE
  ,master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)
  );
COMMENT ON TABLE signkey_revocations
  IS 'remembering which online signing keys have been revoked';


-- Complete transaction
COMMIT;
