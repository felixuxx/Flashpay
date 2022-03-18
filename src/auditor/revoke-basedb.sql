--
-- PostgreSQL database dump
--

-- Dumped from database version 12.9 (Ubuntu 12.9-0ubuntu0.20.04.1)
-- Dumped by pg_dump version 12.9 (Ubuntu 12.9-0ubuntu0.20.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: _v; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA _v;


--
-- Name: SCHEMA _v; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA _v IS 'Schema for versioning data and functionality.';


--
-- Name: assert_patch_is_applied(text); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.assert_patch_is_applied(in_patch_name text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    t_text TEXT;
BEGIN
    SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_patch_name;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Patch % is not applied!', in_patch_name;
    END IF;
    RETURN format('Patch %s is applied.', in_patch_name);
END;
$$;


--
-- Name: FUNCTION assert_patch_is_applied(in_patch_name text); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.assert_patch_is_applied(in_patch_name text) IS 'Function that can be used to make sure that patch has been applied.';


--
-- Name: assert_user_is_not_superuser(); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.assert_user_is_not_superuser() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_super bool;
BEGIN
    SELECT usesuper INTO v_super FROM pg_user WHERE usename = current_user;
    IF v_super THEN
        RAISE EXCEPTION 'Current user is superuser - cannot continue.';
    END IF;
    RETURN 'assert_user_is_not_superuser: OK';
END;
$$;


--
-- Name: FUNCTION assert_user_is_not_superuser(); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.assert_user_is_not_superuser() IS 'Function that can be used to make sure that patch is being applied using normal (not superuser) account.';


--
-- Name: assert_user_is_one_of(text[]); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.assert_user_is_one_of(VARIADIC p_acceptable_users text[]) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    IF current_user = any( p_acceptable_users ) THEN
        RETURN 'assert_user_is_one_of: OK';
    END IF;
    RAISE EXCEPTION 'User is not one of: % - cannot continue.', p_acceptable_users;
END;
$$;


--
-- Name: FUNCTION assert_user_is_one_of(VARIADIC p_acceptable_users text[]); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.assert_user_is_one_of(VARIADIC p_acceptable_users text[]) IS 'Function that can be used to make sure that patch is being applied by one of defined users.';


--
-- Name: assert_user_is_superuser(); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.assert_user_is_superuser() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_super bool;
BEGIN
    SELECT usesuper INTO v_super FROM pg_user WHERE usename = current_user;
    IF v_super THEN
        RETURN 'assert_user_is_superuser: OK';
    END IF;
    RAISE EXCEPTION 'Current user is not superuser - cannot continue.';
END;
$$;


--
-- Name: FUNCTION assert_user_is_superuser(); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.assert_user_is_superuser() IS 'Function that can be used to make sure that patch is being applied using superuser account.';


--
-- Name: register_patch(text); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.register_patch(text) RETURNS SETOF integer
    LANGUAGE sql
    AS $_$
    SELECT _v.register_patch( $1, NULL, NULL );
$_$;


--
-- Name: FUNCTION register_patch(text); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.register_patch(text) IS 'Wrapper to allow registration of patches without requirements and conflicts.';


--
-- Name: register_patch(text, text[]); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.register_patch(text, text[]) RETURNS SETOF integer
    LANGUAGE sql
    AS $_$
    SELECT _v.register_patch( $1, $2, NULL );
$_$;


--
-- Name: FUNCTION register_patch(text, text[]); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.register_patch(text, text[]) IS 'Wrapper to allow registration of patches without conflicts.';


--
-- Name: register_patch(text, text[], text[]); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.register_patch(in_patch_name text, in_requirements text[], in_conflicts text[], OUT versioning integer) RETURNS SETOF integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    t_text   TEXT;
    t_text_a TEXT[];
    i INT4;
BEGIN
    -- Thanks to this we know only one patch will be applied at a time
    LOCK TABLE _v.patches IN EXCLUSIVE MODE;

    SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_patch_name;
    IF FOUND THEN
        RAISE EXCEPTION 'Patch % is already applied!', in_patch_name;
    END IF;

    t_text_a := ARRAY( SELECT patch_name FROM _v.patches WHERE patch_name = any( in_conflicts ) );
    IF array_upper( t_text_a, 1 ) IS NOT NULL THEN
        RAISE EXCEPTION 'Versioning patches conflict. Conflicting patche(s) installed: %.', array_to_string( t_text_a, ', ' );
    END IF;

    IF array_upper( in_requirements, 1 ) IS NOT NULL THEN
        t_text_a := '{}';
        FOR i IN array_lower( in_requirements, 1 ) .. array_upper( in_requirements, 1 ) LOOP
            SELECT patch_name INTO t_text FROM _v.patches WHERE patch_name = in_requirements[i];
            IF NOT FOUND THEN
                t_text_a := t_text_a || in_requirements[i];
            END IF;
        END LOOP;
        IF array_upper( t_text_a, 1 ) IS NOT NULL THEN
            RAISE EXCEPTION 'Missing prerequisite(s): %.', array_to_string( t_text_a, ', ' );
        END IF;
    END IF;

    INSERT INTO _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts ) VALUES ( in_patch_name, now(), current_user, coalesce( in_requirements, '{}' ), coalesce( in_conflicts, '{}' ) );
    RETURN;
END;
$$;


--
-- Name: FUNCTION register_patch(in_patch_name text, in_requirements text[], in_conflicts text[], OUT versioning integer); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.register_patch(in_patch_name text, in_requirements text[], in_conflicts text[], OUT versioning integer) IS 'Function to register patches in database. Raises exception if there are conflicts, prerequisites are not installed or the migration has already been installed.';


--
-- Name: unregister_patch(text); Type: FUNCTION; Schema: _v; Owner: -
--

CREATE FUNCTION _v.unregister_patch(in_patch_name text, OUT versioning integer) RETURNS SETOF integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    i        INT4;
    t_text_a TEXT[];
BEGIN
    -- Thanks to this we know only one patch will be applied at a time
    LOCK TABLE _v.patches IN EXCLUSIVE MODE;

    t_text_a := ARRAY( SELECT patch_name FROM _v.patches WHERE in_patch_name = ANY( requires ) );
    IF array_upper( t_text_a, 1 ) IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot uninstall %, as it is required by: %.', in_patch_name, array_to_string( t_text_a, ', ' );
    END IF;

    DELETE FROM _v.patches WHERE patch_name = in_patch_name;
    GET DIAGNOSTICS i = ROW_COUNT;
    IF i < 1 THEN
        RAISE EXCEPTION 'Patch % is not installed, so it can''t be uninstalled!', in_patch_name;
    END IF;

    RETURN;
END;
$$;


--
-- Name: FUNCTION unregister_patch(in_patch_name text, OUT versioning integer); Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON FUNCTION _v.unregister_patch(in_patch_name text, OUT versioning integer) IS 'Function to unregister patches in database. Dies if the patch is not registered, or if unregistering it would break dependencies.';


--
-- Name: add_constraints_to_aggregation_tracking_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_aggregation_tracking_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE aggregation_tracking_' || partition_suffix || ' '
      'ADD CONSTRAINT aggregation_tracking_' || partition_suffix || '_aggregation_serial_id_key '
        'UNIQUE (aggregation_serial_id) '
  );
END
$$;


--
-- Name: add_constraints_to_cs_nonce_locks_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_cs_nonce_locks_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE cs_nonce_locks_' || partition_suffix || ' '
      'ADD CONSTRAINT cs_nonce_locks_' || partition_suffix || '_cs_nonce_lock_serial_id_key '
        'UNIQUE (cs_nonce_lock_serial_id)'
  );
END
$$;


--
-- Name: add_constraints_to_deposits_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_deposits_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE deposits_' || partition_suffix || ' '
      'ADD CONSTRAINT deposits_' || partition_suffix || '_deposit_serial_id_pkey '
        'PRIMARY KEY (deposit_serial_id)'
  );
END
$$;


--
-- Name: add_constraints_to_known_coins_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_known_coins_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE known_coins_' || partition_suffix || ' '
      'ADD CONSTRAINT known_coins_' || partition_suffix || 'k_nown_coin_id_key '
        'UNIQUE (known_coin_id)'
  );
END
$$;


--
-- Name: add_constraints_to_recoup_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_recoup_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE recoup_' || partition_suffix || ' '
      'ADD CONSTRAINT recoup_' || partition_suffix || '_recoup_uuid_key '
        'UNIQUE (recoup_uuid) '
  );
END
$$;


--
-- Name: add_constraints_to_recoup_refresh_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_recoup_refresh_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE recoup_refresh_' || partition_suffix || ' '
      'ADD CONSTRAINT recoup_refresh_' || partition_suffix || '_recoup_refresh_uuid_key '
        'UNIQUE (recoup_refresh_uuid) '
  );
END
$$;


--
-- Name: add_constraints_to_refresh_commitments_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_refresh_commitments_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE refresh_commitments_' || partition_suffix || ' '
      'ADD CONSTRAINT refresh_commitments_' || partition_suffix || '_melt_serial_id_key '
        'UNIQUE (melt_serial_id)'
  );
END
$$;


--
-- Name: add_constraints_to_refresh_revealed_coins_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_refresh_revealed_coins_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE refresh_revealed_coins_' || partition_suffix || ' '
      'ADD CONSTRAINT refresh_revealed_coins_' || partition_suffix || '_rrc_serial_key '
        'UNIQUE (rrc_serial) '
      ',ADD CONSTRAINT refresh_revealed_coins_' || partition_suffix || '_coin_ev_key '
        'UNIQUE (coin_ev) '
      ',ADD CONSTRAINT refresh_revealed_coins_' || partition_suffix || '_h_coin_ev_key '
        'UNIQUE (h_coin_ev) '
      ',ADD PRIMARY KEY (melt_serial_id, freshcoin_index) '
  );
END
$$;


--
-- Name: add_constraints_to_refresh_transfer_keys_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_refresh_transfer_keys_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE refresh_transfer_keys_' || partition_suffix || ' '
      'ADD CONSTRAINT refresh_transfer_keys_' || partition_suffix || '_rtc_serial_key '
        'UNIQUE (rtc_serial)'
  );
END
$$;


--
-- Name: add_constraints_to_refunds_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_refunds_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE refunds_' || partition_suffix || ' '
      'ADD CONSTRAINT refunds_' || partition_suffix || '_refund_serial_id_key '
        'UNIQUE (refund_serial_id) '
      ',ADD PRIMARY KEY (deposit_serial_id, rtransaction_id) '
  );
END
$$;


--
-- Name: add_constraints_to_reserves_close_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_reserves_close_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE reserves_close_' || partition_suffix || ' '
      'ADD CONSTRAINT reserves_close_' || partition_suffix || '_close_uuid_pkey '
        'PRIMARY KEY (close_uuid)'
  );
END
$$;


--
-- Name: add_constraints_to_reserves_in_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_reserves_in_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE reserves_in_' || partition_suffix || ' '
      'ADD CONSTRAINT reserves_in_' || partition_suffix || '_reserve_in_serial_id_key '
        'UNIQUE (reserve_in_serial_id)'
  );
END
$$;


--
-- Name: add_constraints_to_reserves_out_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_reserves_out_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE reserves_out_' || partition_suffix || ' '
      'ADD CONSTRAINT reserves_out_' || partition_suffix || '_reserve_out_serial_id_key '
        'UNIQUE (reserve_out_serial_id)'
  );
END
$$;


--
-- Name: add_constraints_to_wire_out_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wire_out_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wire_out_' || partition_suffix || ' '
      'ADD CONSTRAINT wire_out_' || partition_suffix || '_wireout_uuid_pkey '
        'PRIMARY KEY (wireout_uuid)'
  );
END
$$;


--
-- Name: add_constraints_to_wire_targets_partition(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_constraints_to_wire_targets_partition(partition_suffix character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wire_targets_' || partition_suffix || ' '
      'ADD CONSTRAINT wire_targets_' || partition_suffix || '_wire_target_serial_id_key '
        'UNIQUE (wire_target_serial_id)'
  );
END
$$;


--
-- Name: defer_wire_out(); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.defer_wire_out()
    LANGUAGE plpgsql
    AS $$
BEGIN

IF EXISTS (
  SELECT 1
    FROM information_Schema.constraint_column_usage
   WHERE table_name='wire_out'
     AND constraint_name='wire_out_ref')
THEN
  SET CONSTRAINTS wire_out_ref DEFERRED;
END IF;

END $$;


--
-- Name: deposit_by_coin_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposit_by_coin_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM deposit_by_coin
   WHERE coin_pub = OLD.reserve_uuid
     AND shard = OLD.shard
     AND deposit_serial_id = OLD.deposit_serial_id;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION deposit_by_coin_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposit_by_coin_delete_trigger() IS 'Replicate deposits deletions into deposit_by_coin table.';


--
-- Name: deposit_by_coin_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposit_by_coin_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO deposits_by_coin
    (deposit_serial_id
    ,shard
    ,coin_pub)
  VALUES
    (NEW.deposit_serial_id
    ,NEW.shard
    ,NEW.coin_pub);
  RETURN NEW;
END $$;


--
-- Name: FUNCTION deposit_by_coin_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposit_by_coin_insert_trigger() IS 'Replicate deposit inserts into deposit_by_coin table.';


--
-- Name: exchange_do_deposit(bigint, integer, bytea, bytea, bigint, bigint, bigint, bigint, bytea, character varying, bytea, bigint, bytea, bytea, bigint, boolean, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_deposit(in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_h_contract_terms bytea, in_wire_salt bytea, in_wallet_timestamp bigint, in_exchange_timestamp bigint, in_refund_deadline bigint, in_wire_deadline bigint, in_merchant_pub bytea, in_receiver_wire_account character varying, in_h_payto bytea, in_known_coin_id bigint, in_coin_pub bytea, in_coin_sig bytea, in_shard bigint, in_extension_blocked boolean, in_extension_details character varying, OUT out_exchange_timestamp bigint, OUT out_balance_ok boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  wtsi INT8; -- wire target serial id
DECLARE
  xdi INT8; -- eXstension details serial id
BEGIN
-- Shards: INSERT extension_details (by extension_details_serial_id)
--         INSERT wire_targets (by h_payto), on CONFLICT DO NOTHING;
--         INSERT deposits (by shard + merchant_pub + h_payto), ON CONFLICT DO NOTHING;
--         UPDATE known_coins (by coin_pub)

IF NOT NULL in_extension_details
THEN
  INSERT INTO extension_details
  (extension_options)
  VALUES
    (in_extension_details)
  RETURNING extension_details_serial_id INTO xdi;
ELSE
  xdi=NULL;
END IF;


INSERT INTO wire_targets
  (wire_target_h_payto
  ,payto_uri)
  VALUES
  (in_h_payto
  ,in_receiver_wire_account)
ON CONFLICT DO NOTHING -- for CONFLICT ON (wire_target_h_payto)
  RETURNING wire_target_serial_id INTO wtsi;

IF NOT FOUND
THEN
  SELECT wire_target_serial_id
  INTO wtsi
  FROM wire_targets
  WHERE wire_target_h_payto=in_h_payto;
END IF;


INSERT INTO deposits
  (shard
  ,coin_pub
  ,known_coin_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,wallet_timestamp
  ,exchange_timestamp
  ,refund_deadline
  ,wire_deadline
  ,merchant_pub
  ,h_contract_terms
  ,coin_sig
  ,wire_salt
  ,wire_target_h_payto
  ,extension_blocked
  ,extension_details_serial_id
  )
  VALUES
  (in_shard
  ,in_coin_pub
  ,in_known_coin_id
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
  ,in_wallet_timestamp
  ,in_exchange_timestamp
  ,in_refund_deadline
  ,in_wire_deadline
  ,in_merchant_pub
  ,in_h_contract_terms
  ,in_coin_sig
  ,in_wire_salt
  ,in_h_payto
  ,in_extension_blocked
  ,xdi)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'coin_sig', we implicitly check
  -- identity over everything that the signature covers.
  -- We do select over merchant_pub and wire_target_h_payto
  -- primarily here to maximally use the existing index.
  SELECT
     exchange_timestamp
   INTO
     out_exchange_timestamp
   FROM deposits
   WHERE shard=in_shard
     AND merchant_pub=in_merchant_pub
     AND wire_target_h_payto=in_h_payto
     AND coin_pub=in_coin_pub
     AND coin_sig=in_coin_sig;

  IF NOT FOUND
  THEN
    -- Deposit exists, but with differences. Not allowed.
    out_balance_ok=FALSE;
    out_conflict=TRUE;
    RETURN;
  END IF;

  -- Idempotent request known, return success.
  out_balance_ok=TRUE;
  out_conflict=FALSE;

  RETURN;
END IF;


out_exchange_timestamp=in_exchange_timestamp;

-- Check and update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac-in_amount_with_fee_frac
       + CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_amount_with_fee_val
       - CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub
    AND ( (remaining_val > in_amount_with_fee_val) OR
          ( (remaining_frac >= in_amount_with_fee_frac) AND
            (remaining_val >= in_amount_with_fee_val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_balance_ok=FALSE;
  out_conflict=FALSE;
  RETURN;
END IF;

-- Everything fine, return success!
out_balance_ok=TRUE;
out_conflict=FALSE;

END $$;


--
-- Name: exchange_do_gc(bigint, bigint); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.exchange_do_gc(in_ancient_date bigint, in_now bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
  reserve_uuid_min INT8; -- minimum reserve UUID still alive
DECLARE
  melt_min INT8; -- minimum melt still alive
DECLARE
  coin_min INT8; -- minimum known_coin still alive
DECLARE
  deposit_min INT8; -- minimum deposit still alive
DECLARE
  reserve_out_min INT8; -- minimum reserve_out still alive
DECLARE
  denom_min INT8; -- minimum denomination still alive
BEGIN

DELETE FROM prewire
  WHERE finished=TRUE;

DELETE FROM wire_fee
  WHERE end_date < in_ancient_date;

-- TODO: use closing fee as threshold?
DELETE FROM reserves
  WHERE gc_date < in_now
    AND current_balance_val = 0
    AND current_balance_frac = 0;

SELECT
     reserve_out_serial_id
  INTO
     reserve_out_min
  FROM reserves_out
  ORDER BY reserve_out_serial_id ASC
  LIMIT 1;

DELETE FROM recoup
  WHERE reserve_out_serial_id < reserve_out_min;
-- FIXME: recoup_refresh lacks GC!

SELECT
     reserve_uuid
  INTO
     reserve_uuid_min
  FROM reserves
  ORDER BY reserve_uuid ASC
  LIMIT 1;

DELETE FROM reserves_out
  WHERE reserve_uuid < reserve_uuid_min;

-- FIXME: this query will be horribly slow;
-- need to find another way to formulate it...
DELETE FROM denominations
  WHERE expire_legal < in_now
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM reserves_out)
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM recoup))
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM known_coins
        WHERE coin_pub IN
          (SELECT DISTINCT coin_pub
             FROM recoup_refresh));

SELECT
     melt_serial_id
  INTO
     melt_min
  FROM refresh_commitments
  ORDER BY melt_serial_id ASC
  LIMIT 1;

DELETE FROM refresh_revealed_coins
  WHERE melt_serial_id < melt_min;

DELETE FROM refresh_transfer_keys
  WHERE melt_serial_id < melt_min;

SELECT
     known_coin_id
  INTO
     coin_min
  FROM known_coins
  ORDER BY known_coin_id ASC
  LIMIT 1;

DELETE FROM deposits
  WHERE known_coin_id < coin_min;

SELECT
     deposit_serial_id
  INTO
     deposit_min
  FROM deposits
  ORDER BY deposit_serial_id ASC
  LIMIT 1;

DELETE FROM refunds
  WHERE deposit_serial_id < deposit_min;

DELETE FROM aggregation_tracking
  WHERE deposit_serial_id < deposit_min;

SELECT
     denominations_serial
  INTO
     denom_min
  FROM denominations
  ORDER BY denominations_serial ASC
  LIMIT 1;

DELETE FROM cs_nonce_locks
  WHERE max_denomination_serial <= denom_min;

END $$;


--
-- Name: exchange_do_melt(bytea, bigint, integer, bytea, bytea, bytea, bigint, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_melt(in_cs_rms bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_rc bytea, in_old_coin_pub bytea, in_old_coin_sig bytea, in_known_coin_id bigint, in_noreveal_index integer, in_zombie_required boolean, OUT out_balance_ok boolean, OUT out_zombie_bad boolean, OUT out_noreveal_index integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  denom_max INT8;
BEGIN
-- Shards: INSERT refresh_commitments (by rc)
-- (rare:) SELECT refresh_commitments (by old_coin_pub) -- crosses shards!
-- (rare:) SEELCT refresh_revealed_coins (by melt_serial_id)
-- (rare:) PERFORM recoup_refresh (by rrc_serial) -- crosses shards!
--         UPDATE known_coins (by coin_pub)

INSERT INTO refresh_commitments
  (rc
  ,old_coin_pub
  ,old_coin_sig
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,noreveal_index
  )
  VALUES
  (in_rc
  ,in_old_coin_pub
  ,in_old_coin_sig
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
  ,in_noreveal_index)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  out_noreveal_index=-1;
  SELECT
     noreveal_index
    INTO
     out_noreveal_index
    FROM refresh_commitments
   WHERE rc=in_rc;
  out_balance_ok=FOUND;
  out_zombie_bad=FALSE; -- zombie is OK
  RETURN;
END IF;


IF in_zombie_required
THEN
  -- Check if this coin was part of a refresh
  -- operation that was subsequently involved
  -- in a recoup operation.  We begin by all
  -- refresh operations our coin was involved
  -- with, then find all associated reveal
  -- operations, and then see if any of these
  -- reveal operations was involved in a recoup.
  PERFORM
    FROM recoup_refresh
   WHERE rrc_serial IN
    (SELECT rrc_serial
       FROM refresh_revealed_coins
      WHERE melt_serial_id IN
      (SELECT melt_serial_id
         FROM refresh_commitments
        WHERE old_coin_pub=in_old_coin_pub));
  IF NOT FOUND
  THEN
    out_zombie_bad=TRUE;
    out_balance_ok=FALSE;
    RETURN;
  END IF;
END IF;

out_zombie_bad=FALSE; -- zombie is OK


-- Check and update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac-in_amount_with_fee_frac
       + CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_amount_with_fee_val
       - CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_old_coin_pub
    AND ( (remaining_val > in_amount_with_fee_val) OR
          ( (remaining_frac >= in_amount_with_fee_frac) AND
            (remaining_val >= in_amount_with_fee_val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_noreveal_index=-1;
  out_balance_ok=FALSE;
  RETURN;
END IF;



-- Special actions needed for a CS melt?
IF NOT NULL in_cs_rms
THEN
  -- Get maximum denominations serial value in
  -- existence, this will determine how long the
  -- nonce will be locked.
  SELECT
      denominations_serial
    INTO
      denom_max
    FROM denominations
      ORDER BY denominations_serial DESC
      LIMIT 1;

  -- Cache CS signature to prevent replays in the future
  -- (and check if cached signature exists at the same time).
  INSERT INTO cs_nonce_locks
    (nonce
    ,max_denomination_serial
    ,op_hash)
  VALUES
    (cs_rms
    ,denom_serial
    ,in_rc)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- Record exists, make sure it is the same
    SELECT 1
      FROM cs_nonce_locks
     WHERE nonce=cs_rms
       AND op_hash=in_rc;

    IF NOT FOUND
    THEN
       -- Nonce reuse detected
       out_balance_ok=FALSE;
       out_zombie_bad=FALSE;
       out_noreveal_index=42; -- FIXME: return error message more nicely!
       ASSERT false, 'nonce reuse attempted by client';
    END IF;
  END IF;
END IF;




-- Everything fine, return success!
out_balance_ok=TRUE;
out_noreveal_index=in_noreveal_index;

END $$;


--
-- Name: exchange_do_recoup_to_coin(bytea, bigint, bytea, bytea, bigint, bytea, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_recoup_to_coin(in_old_coin_pub bytea, in_rrc_serial bigint, in_coin_blind bytea, in_coin_pub bytea, in_known_coin_id bigint, in_coin_sig bytea, in_recoup_timestamp bigint, OUT out_recoup_ok boolean, OUT out_internal_failure boolean, OUT out_recoup_timestamp bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  tmp_val INT8; -- amount recouped
DECLARE
  tmp_frac INT8; -- amount recouped
BEGIN

-- Shards: UPDATE known_coins (by coin_pub)
--         SELECT recoup_refresh (by coin_pub)
--         UPDATE known_coins (by coin_pub)
--         INSERT recoup_refresh (by coin_pub)


out_internal_failure=FALSE;


-- Check remaining balance of the coin.
SELECT
   remaining_frac
  ,remaining_val
 INTO
   tmp_frac
  ,tmp_val
FROM known_coins
  WHERE coin_pub=in_coin_pub;

IF NOT FOUND
THEN
  out_internal_failure=TRUE;
  out_recoup_ok=FALSE;
  RETURN;
END IF;

IF tmp_val + tmp_frac = 0
THEN
  -- Check for idempotency
  SELECT
      recoup_timestamp
    INTO
      out_recoup_timestamp
    FROM recoup_refresh
    WHERE coin_pub=in_coin_pub;
  out_recoup_ok=FOUND;
  RETURN;
END IF;

-- Update balance of the coin.
UPDATE known_coins
  SET
     remaining_frac=0
    ,remaining_val=0
  WHERE coin_pub=in_coin_pub;


-- Credit the old coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac+tmp_frac
       - CASE
         WHEN remaining_frac+tmp_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val+tmp_val
       + CASE
         WHEN remaining_frac+tmp_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_old_coin_pub;


IF NOT FOUND
THEN
  RAISE NOTICE 'failed to increase old coin balance from recoup';
  out_recoup_ok=TRUE;
  out_internal_failure=TRUE;
  RETURN;
END IF;


INSERT INTO recoup_refresh
  (coin_pub
  ,known_coin_id
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,rrc_serial
  )
VALUES
  (in_coin_pub
  ,in_known_coin_id
  ,in_coin_sig
  ,in_coin_blind
  ,tmp_val
  ,tmp_frac
  ,in_recoup_timestamp
  ,in_rrc_serial);

-- Normal end, everything is fine.
out_recoup_ok=TRUE;
out_recoup_timestamp=in_recoup_timestamp;

END $$;


--
-- Name: exchange_do_recoup_to_reserve(bytea, bigint, bytea, bytea, bigint, bytea, bigint, bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_recoup_to_reserve(in_reserve_pub bytea, in_reserve_out_serial_id bigint, in_coin_blind bytea, in_coin_pub bytea, in_known_coin_id bigint, in_coin_sig bytea, in_reserve_gc bigint, in_reserve_expiration bigint, in_recoup_timestamp bigint, OUT out_recoup_ok boolean, OUT out_internal_failure boolean, OUT out_recoup_timestamp bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  tmp_val INT8; -- amount recouped
DECLARE
  tmp_frac INT8; -- amount recouped
BEGIN
-- Shards: SELECT known_coins (by coin_pub)
--         SELECT recoup      (by coin_pub)
--         UPDATE known_coins (by coin_pub)
--         UPDATE reserves (by reserve_pub)
--         INSERT recoup      (by coin_pub)

out_internal_failure=FALSE;


-- Check remaining balance of the coin.
SELECT
   remaining_frac
  ,remaining_val
 INTO
   tmp_frac
  ,tmp_val
FROM known_coins
  WHERE coin_pub=in_coin_pub;

IF NOT FOUND
THEN
  out_internal_failure=TRUE;
  out_recoup_ok=FALSE;
  RETURN;
END IF;

IF tmp_val + tmp_frac = 0
THEN
  -- Check for idempotency
  SELECT
    recoup_timestamp
  INTO
    out_recoup_timestamp
    FROM recoup
    WHERE coin_pub=in_coin_pub;

  out_recoup_ok=FOUND;
  RETURN;
END IF;


-- Update balance of the coin.
UPDATE known_coins
  SET
     remaining_frac=0
    ,remaining_val=0
  WHERE coin_pub=in_coin_pub;


-- Credit the reserve and update reserve timers.
UPDATE reserves
  SET
    current_balance_frac=current_balance_frac+tmp_frac
       - CASE
         WHEN current_balance_frac+tmp_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val+tmp_val
       + CASE
         WHEN current_balance_frac+tmp_frac >= 100000000
         THEN 1
         ELSE 0
         END,
    gc_date=GREATEST(gc_date, in_reserve_gc),
    expiration_date=GREATEST(expiration_date, in_reserve_expiration)
  WHERE reserve_pub=in_reserve_pub;


IF NOT FOUND
THEN
  RAISE NOTICE 'failed to increase reserve balance from recoup';
  out_recoup_ok=TRUE;
  out_internal_failure=TRUE;
  RETURN;
END IF;


INSERT INTO recoup
  (coin_pub
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,reserve_out_serial_id
  )
VALUES
  (in_coin_pub
  ,in_coin_sig
  ,in_coin_blind
  ,tmp_val
  ,tmp_frac
  ,in_recoup_timestamp
  ,in_reserve_out_serial_id);

-- Normal end, everything is fine.
out_recoup_ok=TRUE;
out_recoup_timestamp=in_recoup_timestamp;

END $$;


--
-- Name: exchange_do_refund(bigint, integer, bigint, integer, bigint, integer, bytea, bigint, bigint, bigint, bytea, bytea, bytea); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_refund(in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_amount_val bigint, in_amount_frac integer, in_deposit_fee_val bigint, in_deposit_fee_frac integer, in_h_contract_terms bytea, in_rtransaction_id bigint, in_deposit_shard bigint, in_known_coin_id bigint, in_coin_pub bytea, in_merchant_pub bytea, in_merchant_sig bytea, OUT out_not_found boolean, OUT out_refund_ok boolean, OUT out_gone boolean, OUT out_conflict boolean) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  dsi INT8; -- ID of deposit being refunded
DECLARE
  tmp_val INT8; -- total amount refunded
DECLARE
  tmp_frac INT8; -- total amount refunded
DECLARE
  deposit_val INT8; -- amount that was originally deposited
DECLARE
  deposit_frac INT8; -- amount that was originally deposited
BEGIN
-- Shards: SELECT deposits (by shard, coin_pub, h_contract_terms, merchant_pub)
--         INSERT refunds (by deposit_serial_id, rtransaction_id) ON CONFLICT DO NOTHING
--         SELECT refunds (by deposit_serial_id)
--         UPDATE known_coins (by coin_pub)

SELECT
   dep.deposit_serial_id
  ,dep.amount_with_fee_val
  ,dep.amount_with_fee_frac
  ,dep.done
INTO
   dsi
  ,deposit_val
  ,deposit_frac
  ,out_gone
FROM deposits_by_coin dbc
  JOIN deposits dep USING (shard,deposit_serial_id)
 WHERE dbc.coin_pub=in_coin_pub
  AND dep.shard=in_deposit_shard
  AND dep.merchant_pub=in_merchant_pub
  AND dep.h_contract_terms=in_h_contract_terms;

IF NOT FOUND
THEN
  -- No matching deposit found!
  out_refund_ok=FALSE;
  out_conflict=FALSE;
  out_not_found=TRUE;
  out_gone=FALSE;
  RETURN;
END IF;


INSERT INTO refunds
  (deposit_serial_id
  ,shard
  ,merchant_sig
  ,rtransaction_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  )
  VALUES
  (dsi
  ,in_deposit_shard
  ,in_merchant_sig
  ,in_rtransaction_id
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'coin_sig', we implicitly check
  -- identity over everything that the signature covers.
  -- We do select over merchant_pub and h_contract_terms
  -- primarily here to maximally use the existing index.
   PERFORM
   FROM refunds
   WHERE shard=in_deposit_shard
     AND deposit_serial_id=dsi
     AND rtransaction_id=in_rtransaction_id
     AND amount_with_fee_val=in_amount_with_fee_val
     AND amount_with_fee_frac=in_amount_with_fee_frac;

  IF NOT FOUND
  THEN
    -- Deposit exists, but have conflicting refund.
    out_refund_ok=FALSE;
    out_conflict=TRUE;
    out_not_found=FALSE;
    RETURN;
  END IF;

  -- Idempotent request known, return success.
  out_refund_ok=TRUE;
  out_conflict=FALSE;
  out_not_found=FALSE;
  out_gone=FALSE;
  RETURN;
END IF;


IF out_gone
THEN
  -- money already sent to the merchant. Tough luck.
  out_refund_ok=FALSE;
  out_conflict=FALSE;
  out_not_found=FALSE;
  RETURN;
END IF;



-- Check refund balance invariant.
SELECT
   SUM(amount_with_fee_val) -- overflow here is not plausible
  ,SUM(CAST(amount_with_fee_frac AS INT8)) -- compute using 64 bits
  INTO
   tmp_val
  ,tmp_frac
  FROM refunds
  WHERE shard=in_deposit_shard
    AND deposit_serial_id=dsi;
IF tmp_val IS NULL
THEN
  RAISE NOTICE 'failed to sum up existing refunds';
  out_refund_ok=FALSE;
  out_conflict=FALSE;
  out_not_found=FALSE;
  RETURN;
END IF;

-- Normalize result before continuing
tmp_val = tmp_val + tmp_frac / 100000000;
tmp_frac = tmp_frac % 100000000;

-- Actually check if the deposits are sufficient for the refund. Verbosely. ;-)
IF (tmp_val < deposit_val)
THEN
  out_refund_ok=TRUE;
ELSE
  IF (tmp_val = deposit_val) AND (tmp_frac <= deposit_frac)
  THEN
    out_refund_ok=TRUE;
  ELSE
    out_refund_ok=FALSE;
  END IF;
END IF;

IF (tmp_val = deposit_val) AND (tmp_frac = deposit_frac)
THEN
  -- Refunds have reached the full value of the original
  -- deposit. Also refund the deposit fee.
  in_amount_frac = in_amount_frac + in_deposit_fee_frac;
  in_amount_val = in_amount_val + in_deposit_fee_val;

  -- Normalize result before continuing
  in_amount_val = in_amount_val + in_amount_frac / 100000000;
  in_amount_frac = in_amount_frac % 100000000;
END IF;

-- Update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac+in_amount_frac
       - CASE
         WHEN remaining_frac+in_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val+in_amount_val
       + CASE
         WHEN remaining_frac+in_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub;


out_conflict=FALSE;
out_not_found=FALSE;

END $$;


--
-- Name: exchange_do_withdraw(bigint, integer, bytea, bytea, bytea, bytea, bytea, bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_withdraw(amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT ruuid bigint, OUT account_uuid bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  reserve_gc INT8;
DECLARE
  denom_serial INT8;
DECLARE
  reserve_val INT8;
DECLARE
  reserve_frac INT4;
BEGIN


SELECT denominations_serial INTO denom_serial
  FROM denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  reserve_found=FALSE;
  balance_ok=FALSE;
  kycok=FALSE;
  ruuid=0;
  account_uuid=0;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;


UPDATE reserves SET
   gc_date=GREATEST(gc_date, min_reserve_gc)
  ,current_balance_val=current_balance_val - amount_val
     - CASE WHEN (current_balance_frac < amount_frac)
         THEN 1
         ELSE 0
       END
  ,current_balance_frac=current_balance_frac - amount_frac
     + CASE WHEN (current_balance_frac < amount_frac)
         THEN 100000000
         ELSE 0
       END
 WHERE reserves.reserve_pub=rpub
   AND ( (current_balance_val > amount_val) OR
         ( (current_balance_val = amount_val) AND
           (current_balance_frac >= amount_frac) ) );

balance_ok=FOUND;

-- Obtain KYC status based on the last wire transfer into
-- this reserve. FIXME: likely not adequate for reserves that got P2P transfers!
SELECT
   kyc_ok
  ,wire_source_serial_id
  ,reserve_uuid
  INTO
   kycok
  ,account_uuid
  ,ruuid
  FROM reserves 
  JOIN reserves_in USING (reserve_uuid)
  JOIN wire_targets ON (wire_source_serial_id = wire_target_serial_id)
 WHERE reserves.reserve_pub=rpub
 LIMIT 1; -- limit 1 should not be required (without p2p transfers)

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  kycok=FALSE;
  account_uuid=0;
  RETURN;
END IF;

reserve_found=TRUE;


-- We optimistically insert, and then on conflict declare
-- the query successful due to idempotency.
INSERT INTO reserves_out
  (h_blind_ev
  ,denominations_serial
  ,denom_sig
  ,reserve_uuid
  ,reserve_sig
  ,execution_date
  ,amount_with_fee_val
  ,amount_with_fee_frac)
VALUES
  (h_coin_envelope
  ,denom_serial
  ,denom_sig
  ,ruuid
  ,reserve_sig
  ,now
  ,amount_val
  ,amount_frac)
ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- idempotent query, all constraints must be satisfied
  balance_ok=TRUE;
  -- rollback any potential balance update we may have made
  ROLLBACK;
  START TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  RETURN;
END IF;

END $$;


--
-- Name: FUNCTION exchange_do_withdraw(amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT ruuid bigint, OUT account_uuid bigint); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_withdraw(amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT ruuid bigint, OUT account_uuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result';


--
-- Name: exchange_do_withdraw(bytea, bigint, integer, bytea, bytea, bytea, bytea, bytea, bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
  reserve_gc INT8;
DECLARE
  denom_serial INT8;
DECLARE
  reserve_val INT8;
DECLARE
  reserve_frac INT4;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto

SELECT denominations_serial
  INTO denom_serial
  FROM denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  reserve_found=FALSE;
  balance_ok=FALSE;
  kycok=FALSE;
  account_uuid=0;
  ruuid=0;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;


SELECT
   current_balance_val
  ,current_balance_frac
  ,gc_date
  ,reserve_uuid
 INTO
   reserve_val
  ,reserve_frac
  ,reserve_gc
  ,ruuid
  FROM reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  kycok=FALSE;
  account_uuid=0;
  ruuid=2;
  RETURN;
END IF;

-- We optimistically insert, and then on conflict declare
-- the query successful due to idempotency.
INSERT INTO reserves_out
  (h_blind_ev
  ,denominations_serial
  ,denom_sig
  ,reserve_uuid
  ,reserve_sig
  ,execution_date
  ,amount_with_fee_val
  ,amount_with_fee_frac)
VALUES
  (h_coin_envelope
  ,denom_serial
  ,denom_sig
  ,ruuid
  ,reserve_sig
  ,now
  ,amount_val
  ,amount_frac)
ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- idempotent query, all constraints must be satisfied
  reserve_found=TRUE;
  balance_ok=TRUE;
  kycok=TRUE;
  account_uuid=0;
  RETURN;
END IF;

-- Check reserve balance is sufficient.
IF (reserve_val > amount_val)
THEN
  IF (reserve_frac >= amount_frac)
  THEN
    reserve_val=reserve_val - amount_val;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_val=reserve_val - amount_val - 1;
    reserve_frac=reserve_frac + 100000000 - amount_frac;
  END IF;
ELSE
  IF (reserve_val = amount_val) AND (reserve_frac >= amount_frac)
  THEN
    reserve_val=0;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_found=TRUE;
    balance_ok=FALSE;
    kycok=FALSE; -- we do not really know or care
    account_uuid=0;
    RETURN;
  END IF;
END IF;

-- Calculate new expiration dates.
min_reserve_gc=GREATEST(min_reserve_gc,reserve_gc);

-- Update reserve balance.
UPDATE reserves SET
  gc_date=min_reserve_gc
 ,current_balance_val=reserve_val
 ,current_balance_frac=reserve_frac
WHERE
  reserves.reserve_pub=rpub;

reserve_found=TRUE;
balance_ok=TRUE;



-- Special actions needed for a CS withdraw?
IF NOT NULL cs_nonce
THEN
  -- Cache CS signature to prevent replays in the future
  -- (and check if cached signature exists at the same time).
  INSERT INTO cs_nonce_locks
    (nonce
    ,max_denomination_serial
    ,op_hash)
  VALUES
    (cs_nonce
    ,denom_serial
    ,h_coin_envelope)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- See if the existing entry is identical.
    SELECT 1
      FROM cs_nonce_locks
     WHERE nonce=cs_nonce
       AND op_hash=h_coin_envelope;
    IF NOT FOUND
    THEN
      reserve_found=FALSE;
      balance_ok=FALSE;
      kycok=FALSE;
      account_uuid=0;
      ruuid=1; -- FIXME: return error message more nicely!
      ASSERT false, 'nonce reuse attempted by client';
    END IF;
  END IF;
END IF;



-- Obtain KYC status based on the last wire transfer into
-- this reserve. FIXME: likely not adequate for reserves that got P2P transfers!
SELECT
   kyc_ok
  ,wire_target_serial_id
  INTO
   kycok
  ,account_uuid
  FROM reserves_in
  JOIN wire_targets ON (wire_source_h_payto = wire_target_h_payto)
 WHERE reserve_pub=rpub
 LIMIT 1; -- limit 1 should not be required (without p2p transfers)


END $$;


--
-- Name: FUNCTION exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_withdraw(cs_nonce bytea, amount_val bigint, amount_frac integer, h_denom_pub bytea, rpub bytea, reserve_sig bytea, h_coin_envelope bytea, denom_sig bytea, now bigint, min_reserve_gc bigint, OUT reserve_found boolean, OUT balance_ok boolean, OUT kycok boolean, OUT account_uuid bigint, OUT ruuid bigint) IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if so updates the database with the result';


--
-- Name: exchange_do_withdraw_limit_check(bigint, bigint, bigint, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  total_val INT8;
DECLARE
  total_frac INT8; -- INT4 could overflow during accumulation!
BEGIN
-- NOTE: Read-only, but crosses shards.
-- Shards: reserves by reserve_pub
--         reserves_out by reserve_uuid -- crosses shards!!


SELECT
   SUM(amount_with_fee_val) -- overflow here is not plausible
  ,SUM(CAST(amount_with_fee_frac AS INT8)) -- compute using 64 bits
  INTO
   total_val
  ,total_frac
  FROM reserves_out
 WHERE reserve_uuid=ruuid
   AND execution_date > start_time;

-- normalize result
total_val = total_val + total_frac / 100000000;
total_frac = total_frac % 100000000;

-- compare to threshold
below_limit = (total_val < upper_limit_val) OR
            ( (total_val = upper_limit_val) AND
              (total_frac <= upper_limit_frac) );
END $$;


--
-- Name: FUNCTION exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.exchange_do_withdraw_limit_check(ruuid bigint, start_time bigint, upper_limit_val bigint, upper_limit_frac integer, OUT below_limit boolean) IS 'Check whether the withdrawals from the given reserve since the given time are below the given threshold';


--
-- Name: reserves_out_by_reserve_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reserves_out_by_reserve_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM reserves_out_by_reserve
   WHERE reserve_uuid = OLD.reserve_uuid;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION reserves_out_by_reserve_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.reserves_out_by_reserve_delete_trigger() IS 'Replicate reserve_out deletions into reserve_out_by_reserve table.';


--
-- Name: reserves_out_by_reserve_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reserves_out_by_reserve_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO reserves_out_by_reserve
    (reserve_uuid
    ,h_blind_ev)
  VALUES
    (NEW.reserve_uuid
    ,NEW.h_blind_ev);
  RETURN NEW;
END $$;


--
-- Name: FUNCTION reserves_out_by_reserve_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.reserves_out_by_reserve_insert_trigger() IS 'Replicate reserve_out inserts into reserve_out_by_reserve table.';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: patches; Type: TABLE; Schema: _v; Owner: -
--

CREATE TABLE _v.patches (
    patch_name text NOT NULL,
    applied_tsz timestamp with time zone DEFAULT now() NOT NULL,
    applied_by text NOT NULL,
    requires text[],
    conflicts text[]
);


--
-- Name: TABLE patches; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON TABLE _v.patches IS 'Contains information about what patches are currently applied on database.';


--
-- Name: COLUMN patches.patch_name; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON COLUMN _v.patches.patch_name IS 'Name of patch, has to be unique for every patch.';


--
-- Name: COLUMN patches.applied_tsz; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON COLUMN _v.patches.applied_tsz IS 'When the patch was applied.';


--
-- Name: COLUMN patches.applied_by; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON COLUMN _v.patches.applied_by IS 'Who applied this patch (PostgreSQL username)';


--
-- Name: COLUMN patches.requires; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON COLUMN _v.patches.requires IS 'List of patches that are required for given patch.';


--
-- Name: COLUMN patches.conflicts; Type: COMMENT; Schema: _v; Owner: -
--

COMMENT ON COLUMN _v.patches.conflicts IS 'List of patches that conflict with given patch.';


--
-- Name: aggregation_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_tracking (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea NOT NULL
)
PARTITION BY HASH (deposit_serial_id);


--
-- Name: TABLE aggregation_tracking; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.aggregation_tracking IS 'mapping from wire transfer identifiers (WTID) to deposits (and back)';


--
-- Name: COLUMN aggregation_tracking.wtid_raw; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.aggregation_tracking.wtid_raw IS 'We first create entries in the aggregation_tracking table and then finally the wire_out entry once we know the total amount. Hence the constraint must be deferrable and we cannot use a wireout_uuid here, because we do not have it when these rows are created. Changing the logic to first INSERT a dummy row into wire_out and then UPDATEing that row in the same transaction would theoretically reduce per-deposit storage costs by 5 percent (24/~460 bytes).';


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.aggregation_tracking ALTER COLUMN aggregation_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.aggregation_tracking_aggregation_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: aggregation_tracking_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aggregation_tracking_default (
    aggregation_serial_id bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    wtid_raw bytea NOT NULL
);
ALTER TABLE ONLY public.aggregation_tracking ATTACH PARTITION public.aggregation_tracking_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: app_bankaccount; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_bankaccount (
    is_public boolean NOT NULL,
    account_no integer NOT NULL,
    balance character varying NOT NULL,
    user_id integer NOT NULL
);


--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.app_bankaccount_account_no_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.app_bankaccount_account_no_seq OWNED BY public.app_bankaccount.account_no;


--
-- Name: app_banktransaction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_banktransaction (
    id bigint NOT NULL,
    amount character varying NOT NULL,
    subject character varying(200) NOT NULL,
    date timestamp with time zone NOT NULL,
    cancelled boolean NOT NULL,
    request_uid character varying(128) NOT NULL,
    credit_account_id integer NOT NULL,
    debit_account_id integer NOT NULL
);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.app_banktransaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.app_banktransaction_id_seq OWNED BY public.app_banktransaction.id;


--
-- Name: app_talerwithdrawoperation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_talerwithdrawoperation (
    withdraw_id uuid NOT NULL,
    amount character varying NOT NULL,
    selection_done boolean NOT NULL,
    confirmation_done boolean NOT NULL,
    aborted boolean NOT NULL,
    selected_reserve_pub text,
    selected_exchange_account_id integer,
    withdraw_account_id integer NOT NULL
);


--
-- Name: auditor_balance_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_balance_summary (
    master_pub bytea NOT NULL,
    denom_balance_val bigint NOT NULL,
    denom_balance_frac integer NOT NULL,
    deposit_fee_balance_val bigint NOT NULL,
    deposit_fee_balance_frac integer NOT NULL,
    melt_fee_balance_val bigint NOT NULL,
    melt_fee_balance_frac integer NOT NULL,
    refund_fee_balance_val bigint NOT NULL,
    refund_fee_balance_frac integer NOT NULL,
    risk_val bigint NOT NULL,
    risk_frac integer NOT NULL,
    loss_val bigint NOT NULL,
    loss_frac integer NOT NULL,
    irregular_recoup_val bigint NOT NULL,
    irregular_recoup_frac integer NOT NULL
);


--
-- Name: TABLE auditor_balance_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_balance_summary IS 'the sum of the outstanding coins from auditor_denomination_pending (denom_pubs must belong to the respectives exchange master public key); it represents the auditor_balance_summary of the exchange at this point (modulo unexpected historic_loss-style events where denomination keys are compromised)';


--
-- Name: auditor_denom_sigs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_denom_sigs (
    auditor_denom_serial bigint NOT NULL,
    auditor_uuid bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    auditor_sig bytea,
    CONSTRAINT auditor_denom_sigs_auditor_sig_check CHECK ((length(auditor_sig) = 64))
);


--
-- Name: TABLE auditor_denom_sigs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denom_sigs IS 'Table with auditor signatures on exchange denomination keys.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_uuid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_uuid IS 'Identifies the auditor.';


--
-- Name: COLUMN auditor_denom_sigs.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.denominations_serial IS 'Denomination the signature is for.';


--
-- Name: COLUMN auditor_denom_sigs.auditor_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denom_sigs.auditor_sig IS 'Signature of the auditor, of purpose TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS.';


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auditor_denom_sigs ALTER COLUMN auditor_denom_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auditor_denom_sigs_auditor_denom_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auditor_denomination_pending; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_denomination_pending (
    denom_pub_hash bytea NOT NULL,
    denom_balance_val bigint NOT NULL,
    denom_balance_frac integer NOT NULL,
    denom_loss_val bigint NOT NULL,
    denom_loss_frac integer NOT NULL,
    num_issued bigint NOT NULL,
    denom_risk_val bigint NOT NULL,
    denom_risk_frac integer NOT NULL,
    recoup_loss_val bigint NOT NULL,
    recoup_loss_frac integer NOT NULL,
    CONSTRAINT auditor_denomination_pending_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
);


--
-- Name: TABLE auditor_denomination_pending; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_denomination_pending IS 'outstanding denomination coins that the exchange is aware of and what the respective balances are (outstanding as well as issued overall which implies the maximum value at risk).';


--
-- Name: COLUMN auditor_denomination_pending.num_issued; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.num_issued IS 'counts the number of coins issued (withdraw, refresh) of this denomination';


--
-- Name: COLUMN auditor_denomination_pending.denom_risk_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.denom_risk_val IS 'amount that could theoretically be lost in the future due to recoup operations';


--
-- Name: COLUMN auditor_denomination_pending.recoup_loss_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_denomination_pending.recoup_loss_val IS 'amount actually lost due to recoup operations past revocation';


--
-- Name: auditor_exchange_signkeys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchange_signkeys (
    master_pub bytea NOT NULL,
    ep_start bigint NOT NULL,
    ep_expire bigint NOT NULL,
    ep_end bigint NOT NULL,
    exchange_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT auditor_exchange_signkeys_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT auditor_exchange_signkeys_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE auditor_exchange_signkeys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_exchange_signkeys IS 'list of the online signing keys of exchanges we are auditing';


--
-- Name: auditor_exchanges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_exchanges (
    master_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT auditor_exchanges_master_pub_check CHECK ((length(master_pub) = 32))
);


--
-- Name: TABLE auditor_exchanges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_exchanges IS 'list of the exchanges we are auditing';


--
-- Name: auditor_historic_denomination_revenue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_historic_denomination_revenue (
    master_pub bytea NOT NULL,
    denom_pub_hash bytea NOT NULL,
    revenue_timestamp bigint NOT NULL,
    revenue_balance_val bigint NOT NULL,
    revenue_balance_frac integer NOT NULL,
    loss_balance_val bigint NOT NULL,
    loss_balance_frac integer NOT NULL,
    CONSTRAINT auditor_historic_denomination_revenue_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64))
);


--
-- Name: TABLE auditor_historic_denomination_revenue; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_historic_denomination_revenue IS 'Table with historic profits; basically, when a denom_pub has expired and everything associated with it is garbage collected, the final profits end up in here; note that the denom_pub here is not a foreign key, we just keep it as a reference point.';


--
-- Name: COLUMN auditor_historic_denomination_revenue.revenue_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditor_historic_denomination_revenue.revenue_balance_val IS 'the sum of all of the profits we made on the coin except for withdraw fees (which are in historic_reserve_revenue); so this includes the deposit, melt and refund fees';


--
-- Name: auditor_historic_reserve_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_historic_reserve_summary (
    master_pub bytea NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    reserve_profits_val bigint NOT NULL,
    reserve_profits_frac integer NOT NULL
);


--
-- Name: TABLE auditor_historic_reserve_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_historic_reserve_summary IS 'historic profits from reserves; we eventually GC auditor_historic_reserve_revenue, and then store the totals in here (by time intervals).';


--
-- Name: auditor_predicted_result; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_predicted_result (
    master_pub bytea NOT NULL,
    balance_val bigint NOT NULL,
    balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_predicted_result; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_predicted_result IS 'Table with the sum of the ledger, auditor_historic_revenue and the auditor_reserve_balance.  This is the final amount that the exchange should have in its bank account right now.';


--
-- Name: auditor_progress_aggregation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_aggregation (
    master_pub bytea NOT NULL,
    last_wire_out_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_aggregation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_aggregation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_coin (
    master_pub bytea NOT NULL,
    last_withdraw_serial_id bigint DEFAULT 0 NOT NULL,
    last_deposit_serial_id bigint DEFAULT 0 NOT NULL,
    last_melt_serial_id bigint DEFAULT 0 NOT NULL,
    last_refund_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_recoup_refresh_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_coin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_coin IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_deposit_confirmation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_deposit_confirmation (
    master_pub bytea NOT NULL,
    last_deposit_confirmation_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_deposit_confirmation; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_deposit_confirmation IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_progress_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_progress_reserve (
    master_pub bytea NOT NULL,
    last_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_out_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_recoup_serial_id bigint DEFAULT 0 NOT NULL,
    last_reserve_close_serial_id bigint DEFAULT 0 NOT NULL
);


--
-- Name: TABLE auditor_progress_reserve; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_progress_reserve IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: auditor_reserve_balance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_reserve_balance (
    master_pub bytea NOT NULL,
    reserve_balance_val bigint NOT NULL,
    reserve_balance_frac integer NOT NULL,
    withdraw_fee_balance_val bigint NOT NULL,
    withdraw_fee_balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_reserve_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_reserve_balance IS 'sum of the balances of all customer reserves (by exchange master public key)';


--
-- Name: auditor_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_reserves (
    reserve_pub bytea NOT NULL,
    master_pub bytea NOT NULL,
    reserve_balance_val bigint NOT NULL,
    reserve_balance_frac integer NOT NULL,
    withdraw_fee_balance_val bigint NOT NULL,
    withdraw_fee_balance_frac integer NOT NULL,
    expiration_date bigint NOT NULL,
    auditor_reserves_rowid bigint NOT NULL,
    origin_account text,
    CONSTRAINT auditor_reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


--
-- Name: TABLE auditor_reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_reserves IS 'all of the customer reserves and their respective balances that the auditor is aware of';


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auditor_reserves_auditor_reserves_rowid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auditor_reserves_auditor_reserves_rowid_seq OWNED BY public.auditor_reserves.auditor_reserves_rowid;


--
-- Name: auditor_wire_fee_balance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditor_wire_fee_balance (
    master_pub bytea NOT NULL,
    wire_fee_balance_val bigint NOT NULL,
    wire_fee_balance_frac integer NOT NULL
);


--
-- Name: TABLE auditor_wire_fee_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditor_wire_fee_balance IS 'sum of the balances of all wire fees (by exchange master public key)';


--
-- Name: auditors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auditors (
    auditor_uuid bigint NOT NULL,
    auditor_pub bytea NOT NULL,
    auditor_name character varying NOT NULL,
    auditor_url character varying NOT NULL,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT auditors_auditor_pub_check CHECK ((length(auditor_pub) = 32))
);


--
-- Name: TABLE auditors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.auditors IS 'Table with auditors the exchange uses or has used in the past. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN auditors.auditor_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.auditor_pub IS 'Public key of the auditor.';


--
-- Name: COLUMN auditors.auditor_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.auditor_url IS 'The base URL of the auditor.';


--
-- Name: COLUMN auditors.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.is_active IS 'true if we are currently supporting the use of this auditor.';


--
-- Name: COLUMN auditors.last_change; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.auditors.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.auditors ALTER COLUMN auditor_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auditors_auditor_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_group (
    id integer NOT NULL,
    name character varying(150) NOT NULL
);


--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_group_id_seq OWNED BY public.auth_group.id;


--
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_group_permissions (
    id bigint NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_group_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_group_permissions_id_seq OWNED BY public.auth_group_permissions.id;


--
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_permission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_permission_id_seq OWNED BY public.auth_permission.id;


--
-- Name: auth_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_user (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone,
    is_superuser boolean NOT NULL,
    username character varying(150) NOT NULL,
    first_name character varying(150) NOT NULL,
    last_name character varying(150) NOT NULL,
    email character varying(254) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL
);


--
-- Name: auth_user_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_user_groups (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    group_id integer NOT NULL
);


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_user_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_user_groups_id_seq OWNED BY public.auth_user_groups.id;


--
-- Name: auth_user_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_user_id_seq OWNED BY public.auth_user.id;


--
-- Name: auth_user_user_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_user_user_permissions (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    permission_id integer NOT NULL
);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_user_user_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_user_user_permissions_id_seq OWNED BY public.auth_user_user_permissions.id;


--
-- Name: cs_nonce_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cs_nonce_locks (
    cs_nonce_lock_serial_id bigint NOT NULL,
    nonce bytea NOT NULL,
    op_hash bytea NOT NULL,
    max_denomination_serial bigint NOT NULL,
    CONSTRAINT cs_nonce_locks_nonce_check CHECK ((length(nonce) = 32)),
    CONSTRAINT cs_nonce_locks_op_hash_check CHECK ((length(op_hash) = 64))
)
PARTITION BY HASH (nonce);


--
-- Name: TABLE cs_nonce_locks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.cs_nonce_locks IS 'ensures a Clause Schnorr client nonce is locked for use with an operation identified by a hash';


--
-- Name: COLUMN cs_nonce_locks.nonce; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cs_nonce_locks.nonce IS 'actual nonce submitted by the client';


--
-- Name: COLUMN cs_nonce_locks.op_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cs_nonce_locks.op_hash IS 'hash (RC for refresh, blind coin hash for withdraw) the nonce may be used with';


--
-- Name: COLUMN cs_nonce_locks.max_denomination_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.cs_nonce_locks.max_denomination_serial IS 'Maximum number of a CS denomination serial the nonce could be used with, for GC';


--
-- Name: cs_nonce_locks_cs_nonce_lock_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.cs_nonce_locks ALTER COLUMN cs_nonce_lock_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.cs_nonce_locks_cs_nonce_lock_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cs_nonce_locks_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cs_nonce_locks_default (
    cs_nonce_lock_serial_id bigint NOT NULL,
    nonce bytea NOT NULL,
    op_hash bytea NOT NULL,
    max_denomination_serial bigint NOT NULL,
    CONSTRAINT cs_nonce_locks_nonce_check CHECK ((length(nonce) = 32)),
    CONSTRAINT cs_nonce_locks_op_hash_check CHECK ((length(op_hash) = 64))
);
ALTER TABLE ONLY public.cs_nonce_locks ATTACH PARTITION public.cs_nonce_locks_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: denomination_revocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.denomination_revocations (
    denom_revocations_serial_id bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT denomination_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE denomination_revocations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.denomination_revocations IS 'remembering which denomination keys have been revoked';


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.denomination_revocations ALTER COLUMN denom_revocations_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.denomination_revocations_denom_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: denominations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.denominations (
    denominations_serial bigint NOT NULL,
    denom_pub_hash bytea NOT NULL,
    denom_type integer DEFAULT 1 NOT NULL,
    age_mask integer DEFAULT 0 NOT NULL,
    denom_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    valid_from bigint NOT NULL,
    expire_withdraw bigint NOT NULL,
    expire_deposit bigint NOT NULL,
    expire_legal bigint NOT NULL,
    coin_val bigint NOT NULL,
    coin_frac integer NOT NULL,
    fee_withdraw_val bigint NOT NULL,
    fee_withdraw_frac integer NOT NULL,
    fee_deposit_val bigint NOT NULL,
    fee_deposit_frac integer NOT NULL,
    fee_refresh_val bigint NOT NULL,
    fee_refresh_frac integer NOT NULL,
    fee_refund_val bigint NOT NULL,
    fee_refund_frac integer NOT NULL,
    CONSTRAINT denominations_denom_pub_hash_check CHECK ((length(denom_pub_hash) = 64)),
    CONSTRAINT denominations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE denominations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.denominations IS 'Main denominations table. All the valid denominations the exchange knows about.';


--
-- Name: COLUMN denominations.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.denominations.denominations_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN denominations.denom_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.denominations.denom_type IS 'determines cipher type for blind signatures used with this denomination; 0 is for RSA';


--
-- Name: COLUMN denominations.age_mask; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.denominations.age_mask IS 'bitmask with the age restrictions that are being used for this denomination; 0 if denomination does not support the use of age restrictions';


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.denominations ALTER COLUMN denominations_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.denominations_denominations_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: deposit_confirmations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_confirmations (
    master_pub bytea NOT NULL,
    serial_id bigint NOT NULL,
    h_contract_terms bytea NOT NULL,
    h_extensions bytea NOT NULL,
    h_wire bytea NOT NULL,
    exchange_timestamp bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    wire_deadline bigint NOT NULL,
    amount_without_fee_val bigint NOT NULL,
    amount_without_fee_frac integer NOT NULL,
    coin_pub bytea NOT NULL,
    merchant_pub bytea NOT NULL,
    exchange_sig bytea NOT NULL,
    exchange_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT deposit_confirmations_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposit_confirmations_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT deposit_confirmations_exchange_sig_check CHECK ((length(exchange_sig) = 64)),
    CONSTRAINT deposit_confirmations_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposit_confirmations_h_contract_terms_check1 CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposit_confirmations_h_wire_check CHECK ((length(h_wire) = 64)),
    CONSTRAINT deposit_confirmations_master_sig_check CHECK ((length(master_sig) = 64)),
    CONSTRAINT deposit_confirmations_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: TABLE deposit_confirmations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposit_confirmations IS 'deposit confirmation sent to us by merchants; we must check that the exchange reported these properly.';


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deposit_confirmations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deposit_confirmations_serial_id_seq OWNED BY public.deposit_confirmations.serial_id;


--
-- Name: deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits (
    deposit_serial_id bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    known_coin_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wallet_timestamp bigint NOT NULL,
    exchange_timestamp bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    wire_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    coin_sig bytea NOT NULL,
    wire_salt bytea NOT NULL,
    wire_target_h_payto bytea,
    tiny boolean DEFAULT false NOT NULL,
    done boolean DEFAULT false NOT NULL,
    extension_blocked boolean DEFAULT false NOT NULL,
    extension_details_serial_id bigint,
    CONSTRAINT deposits_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT deposits_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT deposits_wire_salt_check CHECK ((length(wire_salt) = 16)),
    CONSTRAINT deposits_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
)
PARTITION BY HASH (shard);


--
-- Name: TABLE deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits IS 'Deposits we have received and for which we need to make (aggregate) wire transfers (and manage refunds).';


--
-- Name: COLUMN deposits.shard; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.shard IS 'Used for load sharding. Should be set based on merchant_pub. 64-bit value because we need an *unsigned* 32-bit value.';


--
-- Name: COLUMN deposits.known_coin_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.known_coin_id IS 'Used for garbage collection';


--
-- Name: COLUMN deposits.wire_salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.wire_salt IS 'Salt used when hashing the payto://-URI to get the h_wire';


--
-- Name: COLUMN deposits.wire_target_h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.wire_target_h_payto IS 'Identifies the target bank account and KYC status';


--
-- Name: COLUMN deposits.tiny; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.tiny IS 'Set to TRUE if we decided that the amount is too small to ever trigger a wire transfer by itself (requires real aggregation)';


--
-- Name: COLUMN deposits.done; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.done IS 'Set to TRUE once we have included this deposit in some aggregate wire transfer to the merchant';


--
-- Name: COLUMN deposits.extension_blocked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.extension_blocked IS 'True if the aggregation of the deposit is currently blocked by some extension mechanism. Used to filter out deposits that must not be processed by the canonical deposit logic.';


--
-- Name: COLUMN deposits.extension_details_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.extension_details_serial_id IS 'References extensions table, NULL if extensions are not used';


--
-- Name: deposits_by_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_by_coin (
    deposit_serial_id bigint,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    CONSTRAINT deposits_by_coin_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY HASH (coin_pub);


--
-- Name: TABLE deposits_by_coin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deposits_by_coin IS 'Enables fast lookups of deposit by coin_pub, auto-populated via TRIGGER below';


--
-- Name: deposits_by_coin_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_by_coin_default (
    deposit_serial_id bigint,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    CONSTRAINT deposits_by_coin_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY public.deposits_by_coin ATTACH PARTITION public.deposits_by_coin_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: deposits_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposits_default (
    deposit_serial_id bigint NOT NULL,
    shard bigint NOT NULL,
    coin_pub bytea NOT NULL,
    known_coin_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    wallet_timestamp bigint NOT NULL,
    exchange_timestamp bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    wire_deadline bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    coin_sig bytea NOT NULL,
    wire_salt bytea NOT NULL,
    wire_target_h_payto bytea,
    tiny boolean DEFAULT false NOT NULL,
    done boolean DEFAULT false NOT NULL,
    extension_blocked boolean DEFAULT false NOT NULL,
    extension_details_serial_id bigint,
    CONSTRAINT deposits_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT deposits_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT deposits_wire_salt_check CHECK ((length(wire_salt) = 16)),
    CONSTRAINT deposits_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
);
ALTER TABLE ONLY public.deposits ATTACH PARTITION public.deposits_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.deposits ALTER COLUMN deposit_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.deposits_deposit_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.django_content_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_content_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.django_content_type_id_seq OWNED BY public.django_content_type.id;


--
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.django_migrations (
    id bigint NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.django_migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: django_migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.django_migrations_id_seq OWNED BY public.django_migrations.id;


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


--
-- Name: exchange_sign_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_sign_keys (
    esk_serial bigint NOT NULL,
    exchange_pub bytea NOT NULL,
    master_sig bytea NOT NULL,
    valid_from bigint NOT NULL,
    expire_sign bigint NOT NULL,
    expire_legal bigint NOT NULL,
    CONSTRAINT exchange_sign_keys_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT exchange_sign_keys_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE exchange_sign_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.exchange_sign_keys IS 'Table with master public key signatures on exchange online signing keys.';


--
-- Name: COLUMN exchange_sign_keys.exchange_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.exchange_pub IS 'Public online signing key of the exchange.';


--
-- Name: COLUMN exchange_sign_keys.master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.master_sig IS 'Signature affirming the validity of the signing key of purpose TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY.';


--
-- Name: COLUMN exchange_sign_keys.valid_from; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.valid_from IS 'Time when this online signing key will first be used to sign messages.';


--
-- Name: COLUMN exchange_sign_keys.expire_sign; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.expire_sign IS 'Time when this online signing key will no longer be used to sign.';


--
-- Name: COLUMN exchange_sign_keys.expire_legal; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_sign_keys.expire_legal IS 'Time when this online signing key legally expires.';


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.exchange_sign_keys ALTER COLUMN esk_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.exchange_sign_keys_esk_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: extension_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.extension_details (
    extension_details_serial_id bigint NOT NULL,
    extension_options character varying
);


--
-- Name: TABLE extension_details; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.extension_details IS 'Extensions that were provided with deposits (not yet used).';


--
-- Name: COLUMN extension_details.extension_options; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extension_details.extension_options IS 'JSON object with options set that the exchange needs to consider when executing a deposit. Supported details depend on the extensions supported by the exchange.';


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.extension_details ALTER COLUMN extension_details_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.extension_details_extension_details_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: extensions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.extensions (
    extension_id bigint NOT NULL,
    name character varying NOT NULL,
    config bytea
);


--
-- Name: TABLE extensions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.extensions IS 'Configurations of the activated extensions';


--
-- Name: COLUMN extensions.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extensions.name IS 'Name of the extension';


--
-- Name: COLUMN extensions.config; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.extensions.config IS 'Configuration of the extension as JSON-blob, maybe NULL';


--
-- Name: extensions_extension_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.extensions ALTER COLUMN extension_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.extensions_extension_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: global_fee; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.global_fee (
    global_fee_serial bigint NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    history_fee_val bigint NOT NULL,
    history_fee_frac integer NOT NULL,
    kyc_fee_val bigint NOT NULL,
    kyc_fee_frac integer NOT NULL,
    account_fee_val bigint NOT NULL,
    account_fee_frac integer NOT NULL,
    purse_fee_val bigint NOT NULL,
    purse_fee_frac integer NOT NULL,
    purse_timeout bigint NOT NULL,
    kyc_timeout bigint NOT NULL,
    history_expiration bigint NOT NULL,
    purse_account_limit integer NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT global_fee_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE global_fee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.global_fee IS 'list of the global fees of this exchange, by date';


--
-- Name: COLUMN global_fee.global_fee_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.global_fee.global_fee_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: global_fee_global_fee_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.global_fee ALTER COLUMN global_fee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.global_fee_global_fee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: known_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins (
    known_coin_id bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    coin_pub bytea NOT NULL,
    age_commitment_hash bytea,
    denom_sig bytea NOT NULL,
    remaining_val bigint NOT NULL,
    remaining_frac integer NOT NULL,
    CONSTRAINT known_coins_age_commitment_hash_check CHECK ((length(age_commitment_hash) = 32)),
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY HASH (coin_pub);


--
-- Name: TABLE known_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.known_coins IS 'information about coins and their signatures, so we do not have to store the signatures more than once if a coin is involved in multiple operations';


--
-- Name: COLUMN known_coins.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.denominations_serial IS 'Denomination of the coin, determines the value of the original coin and applicable fees for coin-specific operations.';


--
-- Name: COLUMN known_coins.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.coin_pub IS 'EdDSA public key of the coin';


--
-- Name: COLUMN known_coins.age_commitment_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.age_commitment_hash IS 'Optional hash of the age commitment for age restrictions as per DD 24 (active if denom_type has the respective bit set)';


--
-- Name: COLUMN known_coins.denom_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.denom_sig IS 'This is the signature of the exchange that affirms that the coin is a valid coin. The specific signature type depends on denom_type of the denomination.';


--
-- Name: COLUMN known_coins.remaining_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.known_coins.remaining_val IS 'Value of the coin that remains to be spent';


--
-- Name: known_coins_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_coins_default (
    known_coin_id bigint NOT NULL,
    denominations_serial bigint NOT NULL,
    coin_pub bytea NOT NULL,
    age_commitment_hash bytea,
    denom_sig bytea NOT NULL,
    remaining_val bigint NOT NULL,
    remaining_frac integer NOT NULL,
    CONSTRAINT known_coins_age_commitment_hash_check CHECK ((length(age_commitment_hash) = 32)),
    CONSTRAINT known_coins_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY public.known_coins ATTACH PARTITION public.known_coins_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.known_coins ALTER COLUMN known_coin_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.known_coins_known_coin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_accounts (
    account_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    h_wire bytea NOT NULL,
    salt bytea NOT NULL,
    payto_uri character varying NOT NULL,
    active boolean NOT NULL,
    CONSTRAINT merchant_accounts_h_wire_check CHECK ((length(h_wire) = 64)),
    CONSTRAINT merchant_accounts_salt_check CHECK ((length(salt) = 16))
);


--
-- Name: TABLE merchant_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_accounts IS 'bank accounts of the instances';


--
-- Name: COLUMN merchant_accounts.h_wire; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.h_wire IS 'salted hash of payto_uri';


--
-- Name: COLUMN merchant_accounts.salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.salt IS 'salt used when hashing payto_uri into h_wire';


--
-- Name: COLUMN merchant_accounts.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.payto_uri IS 'payto URI of a merchant bank account';


--
-- Name: COLUMN merchant_accounts.active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_accounts.active IS 'true if we actively use this bank account, false if it is just kept around for older contracts to refer to';


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_accounts ALTER COLUMN account_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_accounts_account_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_contract_terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_contract_terms (
    order_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    order_id character varying NOT NULL,
    contract_terms bytea NOT NULL,
    h_contract_terms bytea NOT NULL,
    creation_time bigint NOT NULL,
    pay_deadline bigint NOT NULL,
    refund_deadline bigint NOT NULL,
    paid boolean DEFAULT false NOT NULL,
    wired boolean DEFAULT false NOT NULL,
    fulfillment_url character varying,
    session_id character varying DEFAULT ''::character varying NOT NULL,
    claim_token bytea NOT NULL,
    CONSTRAINT merchant_contract_terms_claim_token_check CHECK ((length(claim_token) = 16)),
    CONSTRAINT merchant_contract_terms_h_contract_terms_check CHECK ((length(h_contract_terms) = 64))
);


--
-- Name: TABLE merchant_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_contract_terms IS 'Contracts are orders that have been claimed by a wallet';


--
-- Name: COLUMN merchant_contract_terms.merchant_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_contract_terms.order_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.order_id IS 'Not a foreign key into merchant_orders because paid contracts persist after expiration';


--
-- Name: COLUMN merchant_contract_terms.contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.contract_terms IS 'These contract terms include the wallet nonce';


--
-- Name: COLUMN merchant_contract_terms.h_contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.h_contract_terms IS 'Hash over contract_terms';


--
-- Name: COLUMN merchant_contract_terms.pay_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_contract_terms.refund_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.refund_deadline IS 'By what times do refunds have to be approved (useful to reject refund requests)';


--
-- Name: COLUMN merchant_contract_terms.paid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.paid IS 'true implies the customer paid for this contract; order should be DELETEd from merchant_orders once paid is set to release merchant_order_locks; paid remains true even if the payment was later refunded';


--
-- Name: COLUMN merchant_contract_terms.wired; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.wired IS 'true implies the exchange wired us the full amount for all non-refunded payments under this contract';


--
-- Name: COLUMN merchant_contract_terms.fulfillment_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.fulfillment_url IS 'also included in contract_terms, but we need it here to SELECT on it during repurchase detection; can be NULL if the contract has no fulfillment URL';


--
-- Name: COLUMN merchant_contract_terms.session_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.session_id IS 'last session_id from we confirmed the paying client to use, empty string for none';


--
-- Name: COLUMN merchant_contract_terms.claim_token; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_contract_terms.claim_token IS 'Token optionally used to access the status of the order. All zeros (not NULL) if not used';


--
-- Name: merchant_deposit_to_transfer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_deposit_to_transfer (
    deposit_serial bigint NOT NULL,
    coin_contribution_value_val bigint NOT NULL,
    coin_contribution_value_frac integer NOT NULL,
    credit_serial bigint NOT NULL,
    execution_time bigint NOT NULL,
    signkey_serial bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    CONSTRAINT merchant_deposit_to_transfer_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_deposit_to_transfer; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_deposit_to_transfer IS 'Mapping of deposits to (possibly unconfirmed) wire transfers; NOTE: not used yet';


--
-- Name: COLUMN merchant_deposit_to_transfer.execution_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposit_to_transfer.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_deposits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_deposits (
    deposit_serial bigint NOT NULL,
    order_serial bigint,
    deposit_timestamp bigint NOT NULL,
    coin_pub bytea NOT NULL,
    exchange_url character varying NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    deposit_fee_val bigint NOT NULL,
    deposit_fee_frac integer NOT NULL,
    refund_fee_val bigint NOT NULL,
    refund_fee_frac integer NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    signkey_serial bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    account_serial bigint NOT NULL,
    CONSTRAINT merchant_deposits_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT merchant_deposits_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_deposits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_deposits IS 'Refunds approved by the merchant (backoffice) logic, excludes abort refunds';


--
-- Name: COLUMN merchant_deposits.deposit_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.deposit_timestamp IS 'Time when the exchange generated the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.wire_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.wire_fee_val IS 'We MAY want to see if we should try to get this via merchant_exchange_wire_fees (not sure, may be too complicated with the date range, etc.)';


--
-- Name: COLUMN merchant_deposits.signkey_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.signkey_serial IS 'Online signing key of the exchange on the deposit confirmation';


--
-- Name: COLUMN merchant_deposits.exchange_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_deposits.exchange_sig IS 'Signature of the exchange over the deposit confirmation';


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_deposits ALTER COLUMN deposit_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_deposits_deposit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_exchange_signing_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_exchange_signing_keys (
    signkey_serial bigint NOT NULL,
    master_pub bytea NOT NULL,
    exchange_pub bytea NOT NULL,
    start_date bigint NOT NULL,
    expire_date bigint NOT NULL,
    end_date bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT merchant_exchange_signing_keys_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT merchant_exchange_signing_keys_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT merchant_exchange_signing_keys_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE merchant_exchange_signing_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_exchange_signing_keys IS 'Here we store proofs of the exchange online signing keys being signed by the exchange master key';


--
-- Name: COLUMN merchant_exchange_signing_keys.master_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_exchange_signing_keys.master_pub IS 'Master public key of the exchange with these online signing keys';


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_exchange_signing_keys ALTER COLUMN signkey_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_exchange_signing_keys_signkey_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_exchange_wire_fees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_exchange_wire_fees (
    wirefee_serial bigint NOT NULL,
    master_pub bytea NOT NULL,
    h_wire_method bytea NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT merchant_exchange_wire_fees_h_wire_method_check CHECK ((length(h_wire_method) = 64)),
    CONSTRAINT merchant_exchange_wire_fees_master_pub_check CHECK ((length(master_pub) = 32)),
    CONSTRAINT merchant_exchange_wire_fees_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE merchant_exchange_wire_fees; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_exchange_wire_fees IS 'Here we store proofs of the wire fee structure of the various exchanges';


--
-- Name: COLUMN merchant_exchange_wire_fees.master_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_exchange_wire_fees.master_pub IS 'Master public key of the exchange with these wire fees';


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_exchange_wire_fees ALTER COLUMN wirefee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_exchange_wire_fees_wirefee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_instances (
    merchant_serial bigint NOT NULL,
    merchant_pub bytea NOT NULL,
    auth_hash bytea,
    auth_salt bytea,
    merchant_id character varying NOT NULL,
    merchant_name character varying NOT NULL,
    address bytea NOT NULL,
    jurisdiction bytea NOT NULL,
    default_max_deposit_fee_val bigint NOT NULL,
    default_max_deposit_fee_frac integer NOT NULL,
    default_max_wire_fee_val bigint NOT NULL,
    default_max_wire_fee_frac integer NOT NULL,
    default_wire_fee_amortization integer NOT NULL,
    default_wire_transfer_delay bigint NOT NULL,
    default_pay_delay bigint NOT NULL,
    CONSTRAINT merchant_instances_auth_hash_check CHECK ((length(auth_hash) = 64)),
    CONSTRAINT merchant_instances_auth_salt_check CHECK ((length(auth_salt) = 32)),
    CONSTRAINT merchant_instances_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: TABLE merchant_instances; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_instances IS 'all the instances supported by this backend';


--
-- Name: COLUMN merchant_instances.auth_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.auth_hash IS 'hash used for merchant back office Authorization, NULL for no check';


--
-- Name: COLUMN merchant_instances.auth_salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.auth_salt IS 'salt to use when hashing Authorization header before comparing with auth_hash';


--
-- Name: COLUMN merchant_instances.merchant_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.merchant_id IS 'identifier of the merchant as used in the base URL (required)';


--
-- Name: COLUMN merchant_instances.merchant_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.merchant_name IS 'legal name of the merchant as a simple string (required)';


--
-- Name: COLUMN merchant_instances.address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.address IS 'physical address of the merchant as a Location in JSON format (required)';


--
-- Name: COLUMN merchant_instances.jurisdiction; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.jurisdiction IS 'jurisdiction of the merchant as a Location in JSON format (required)';


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_instances ALTER COLUMN merchant_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_instances_merchant_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_inventory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_inventory (
    product_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    product_id character varying NOT NULL,
    description character varying NOT NULL,
    description_i18n bytea NOT NULL,
    unit character varying NOT NULL,
    image bytea NOT NULL,
    taxes bytea NOT NULL,
    price_val bigint NOT NULL,
    price_frac integer NOT NULL,
    total_stock bigint NOT NULL,
    total_sold bigint DEFAULT 0 NOT NULL,
    total_lost bigint DEFAULT 0 NOT NULL,
    address bytea NOT NULL,
    next_restock bigint NOT NULL,
    minimum_age integer DEFAULT 0 NOT NULL
);


--
-- Name: TABLE merchant_inventory; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_inventory IS 'products offered by the merchant (may be incomplete, frontend can override)';


--
-- Name: COLUMN merchant_inventory.description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.description IS 'Human-readable product description';


--
-- Name: COLUMN merchant_inventory.description_i18n; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.description_i18n IS 'JSON map from IETF BCP 47 language tags to localized descriptions';


--
-- Name: COLUMN merchant_inventory.unit; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.unit IS 'Unit of sale for the product (liters, kilograms, packages)';


--
-- Name: COLUMN merchant_inventory.image; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.image IS 'NOT NULL, but can be 0 bytes; must contain an ImageDataUrl';


--
-- Name: COLUMN merchant_inventory.taxes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.taxes IS 'JSON array containing taxes the merchant pays, must be JSON, but can be just "[]"';


--
-- Name: COLUMN merchant_inventory.price_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.price_val IS 'Current price of one unit of the product';


--
-- Name: COLUMN merchant_inventory.total_stock; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_stock IS 'A value of -1 is used for unlimited (electronic good), may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_sold; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_sold IS 'Number of products sold, must be below total_stock, non-negative, may never be lowered';


--
-- Name: COLUMN merchant_inventory.total_lost; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.total_lost IS 'Number of products that used to be in stock but were lost (spoiled, damaged), may never be lowered; total_stock >= total_sold + total_lost must always hold';


--
-- Name: COLUMN merchant_inventory.address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.address IS 'JSON formatted Location of where the product is stocked';


--
-- Name: COLUMN merchant_inventory.next_restock; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.next_restock IS 'GNUnet absolute time indicating when the next restock is expected. 0 for unknown.';


--
-- Name: COLUMN merchant_inventory.minimum_age; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory.minimum_age IS 'Minimum age of the customer in years, to be used if an exchange supports the age restriction extension.';


--
-- Name: merchant_inventory_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_inventory_locks (
    product_serial bigint NOT NULL,
    lock_uuid bytea NOT NULL,
    total_locked bigint NOT NULL,
    expiration bigint NOT NULL,
    CONSTRAINT merchant_inventory_locks_lock_uuid_check CHECK ((length(lock_uuid) = 16))
);


--
-- Name: TABLE merchant_inventory_locks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_inventory_locks IS 'locks on inventory helt by shopping carts; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_inventory_locks.total_locked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: COLUMN merchant_inventory_locks.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_inventory_locks.expiration IS 'when does this lock automatically expire (if no order is created)';


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_inventory ALTER COLUMN product_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_inventory_product_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_keys (
    merchant_priv bytea NOT NULL,
    merchant_serial bigint NOT NULL,
    CONSTRAINT merchant_keys_merchant_priv_check CHECK ((length(merchant_priv) = 32))
);


--
-- Name: TABLE merchant_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_keys IS 'private keys of instances that have not been deleted';


--
-- Name: merchant_kyc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_kyc (
    kyc_serial_id bigint NOT NULL,
    kyc_timestamp bigint NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    exchange_sig bytea,
    exchange_pub bytea,
    exchange_kyc_serial bigint DEFAULT 0 NOT NULL,
    account_serial bigint NOT NULL,
    exchange_url character varying NOT NULL,
    CONSTRAINT merchant_kyc_exchange_pub_check CHECK ((length(exchange_pub) = 32)),
    CONSTRAINT merchant_kyc_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_kyc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_kyc IS 'Status of the KYC process of a merchant account at an exchange';


--
-- Name: COLUMN merchant_kyc.kyc_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.kyc_timestamp IS 'Last time we checked our KYC status at the exchange. Useful to re-check if the status is very stale. Also the timestamp used for the exchange signature (if present).';


--
-- Name: COLUMN merchant_kyc.kyc_ok; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.kyc_ok IS 'true if the KYC check was passed successfully';


--
-- Name: COLUMN merchant_kyc.exchange_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_sig IS 'signature of the exchange affirming the KYC passed (or NULL if exchange does not require KYC or not kyc_ok)';


--
-- Name: COLUMN merchant_kyc.exchange_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_pub IS 'public key used with exchange_sig (or NULL if exchange_sig is NULL)';


--
-- Name: COLUMN merchant_kyc.exchange_kyc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_kyc_serial IS 'Number to use in the KYC-endpoints of the exchange to check the KYC status or begin the KYC process. 0 if we do not know it yet.';


--
-- Name: COLUMN merchant_kyc.account_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.account_serial IS 'Which bank account of the merchant is the KYC status for';


--
-- Name: COLUMN merchant_kyc.exchange_url; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_kyc.exchange_url IS 'Which exchange base URL is this KYC status valid for';


--
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_kyc ALTER COLUMN kyc_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_kyc_kyc_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_order_locks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_order_locks (
    product_serial bigint NOT NULL,
    total_locked bigint NOT NULL,
    order_serial bigint NOT NULL
);


--
-- Name: TABLE merchant_order_locks; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_order_locks IS 'locks on orders awaiting claim and payment; note that locks MAY not be honored if merchants increase total_lost for inventory';


--
-- Name: COLUMN merchant_order_locks.total_locked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_order_locks.total_locked IS 'how many units of the product does this lock reserve';


--
-- Name: merchant_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_orders (
    order_serial bigint NOT NULL,
    merchant_serial bigint NOT NULL,
    order_id character varying NOT NULL,
    claim_token bytea NOT NULL,
    h_post_data bytea NOT NULL,
    pay_deadline bigint NOT NULL,
    creation_time bigint NOT NULL,
    contract_terms bytea NOT NULL,
    CONSTRAINT merchant_orders_claim_token_check CHECK ((length(claim_token) = 16)),
    CONSTRAINT merchant_orders_h_post_data_check CHECK ((length(h_post_data) = 64))
);


--
-- Name: TABLE merchant_orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_orders IS 'Orders we offered to a customer, but that have not yet been claimed';


--
-- Name: COLUMN merchant_orders.merchant_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.merchant_serial IS 'Identifies the instance offering the contract';


--
-- Name: COLUMN merchant_orders.claim_token; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.claim_token IS 'Token optionally used to authorize the wallet to claim the order. All zeros (not NULL) if not used';


--
-- Name: COLUMN merchant_orders.h_post_data; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.h_post_data IS 'Hash of the POST request that created this order, for idempotency checks';


--
-- Name: COLUMN merchant_orders.pay_deadline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.pay_deadline IS 'How long is the offer valid. After this time, the order can be garbage collected';


--
-- Name: COLUMN merchant_orders.contract_terms; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_orders.contract_terms IS 'Claiming changes the contract_terms, hence we have no hash of the terms in this table';


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_orders ALTER COLUMN order_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_orders_order_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_refund_proofs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_refund_proofs (
    refund_serial bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    signkey_serial bigint NOT NULL,
    CONSTRAINT merchant_refund_proofs_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_refund_proofs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_refund_proofs IS 'Refunds confirmed by the exchange (not all approved refunds are grabbed by the wallet)';


--
-- Name: merchant_refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_refunds (
    refund_serial bigint NOT NULL,
    order_serial bigint NOT NULL,
    rtransaction_id bigint NOT NULL,
    refund_timestamp bigint NOT NULL,
    coin_pub bytea NOT NULL,
    reason character varying NOT NULL,
    refund_amount_val bigint NOT NULL,
    refund_amount_frac integer NOT NULL
);


--
-- Name: COLUMN merchant_refunds.rtransaction_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_refunds.rtransaction_id IS 'Needed for uniqueness in case a refund is increased for the same order';


--
-- Name: COLUMN merchant_refunds.refund_timestamp; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_refunds.refund_timestamp IS 'Needed for grouping of refunds in the wallet UI; has no semantics in the protocol (only for UX), but should be from the time when the merchant internally approved the refund';


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_refunds ALTER COLUMN refund_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_refunds_refund_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tip_pickup_signatures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickup_signatures (
    pickup_serial bigint NOT NULL,
    coin_offset integer NOT NULL,
    blind_sig bytea NOT NULL
);


--
-- Name: TABLE merchant_tip_pickup_signatures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_pickup_signatures IS 'blind signatures we got from the exchange during the tip pickup';


--
-- Name: merchant_tip_pickups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_pickups (
    pickup_serial bigint NOT NULL,
    tip_serial bigint NOT NULL,
    pickup_id bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT merchant_tip_pickups_pickup_id_check CHECK ((length(pickup_id) = 64))
);


--
-- Name: TABLE merchant_tip_pickups; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_pickups IS 'tips that have been picked up';


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_tip_pickups ALTER COLUMN pickup_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_tip_pickups_pickup_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tip_reserve_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserve_keys (
    reserve_serial bigint NOT NULL,
    reserve_priv bytea NOT NULL,
    exchange_url character varying NOT NULL,
    payto_uri character varying,
    CONSTRAINT merchant_tip_reserve_keys_reserve_priv_check CHECK ((length(reserve_priv) = 32))
);


--
-- Name: COLUMN merchant_tip_reserve_keys.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserve_keys.payto_uri IS 'payto:// URI used to fund the reserve, may be NULL once reserve is funded';


--
-- Name: merchant_tip_reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tip_reserves (
    reserve_serial bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    merchant_serial bigint NOT NULL,
    creation_time bigint NOT NULL,
    expiration bigint NOT NULL,
    merchant_initial_balance_val bigint NOT NULL,
    merchant_initial_balance_frac integer NOT NULL,
    exchange_initial_balance_val bigint DEFAULT 0 NOT NULL,
    exchange_initial_balance_frac integer DEFAULT 0 NOT NULL,
    tips_committed_val bigint DEFAULT 0 NOT NULL,
    tips_committed_frac integer DEFAULT 0 NOT NULL,
    tips_picked_up_val bigint DEFAULT 0 NOT NULL,
    tips_picked_up_frac integer DEFAULT 0 NOT NULL,
    CONSTRAINT merchant_tip_reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);


--
-- Name: TABLE merchant_tip_reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tip_reserves IS 'private keys of reserves that have not been deleted';


--
-- Name: COLUMN merchant_tip_reserves.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.expiration IS 'FIXME: EXCHANGE API needs to tell us when reserves close if we are to compute this';


--
-- Name: COLUMN merchant_tip_reserves.merchant_initial_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.merchant_initial_balance_val IS 'Set to the initial balance the merchant told us when creating the reserve';


--
-- Name: COLUMN merchant_tip_reserves.exchange_initial_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.exchange_initial_balance_val IS 'Set to the initial balance the exchange told us when we queried the reserve status';


--
-- Name: COLUMN merchant_tip_reserves.tips_committed_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.tips_committed_val IS 'Amount of outstanding approved tips that have not been picked up';


--
-- Name: COLUMN merchant_tip_reserves.tips_picked_up_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tip_reserves.tips_picked_up_val IS 'Total amount tips that have been picked up from this reserve';


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_tip_reserves ALTER COLUMN reserve_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_tip_reserves_reserve_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_tips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_tips (
    tip_serial bigint NOT NULL,
    reserve_serial bigint NOT NULL,
    tip_id bytea NOT NULL,
    justification character varying NOT NULL,
    next_url character varying NOT NULL,
    expiration bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    picked_up_val bigint DEFAULT 0 NOT NULL,
    picked_up_frac integer DEFAULT 0 NOT NULL,
    was_picked_up boolean DEFAULT false NOT NULL,
    CONSTRAINT merchant_tips_tip_id_check CHECK ((length(tip_id) = 64))
);


--
-- Name: TABLE merchant_tips; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_tips IS 'tips that have been authorized';


--
-- Name: COLUMN merchant_tips.reserve_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.reserve_serial IS 'Reserve from which this tip is funded';


--
-- Name: COLUMN merchant_tips.expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.expiration IS 'by when does the client have to pick up the tip';


--
-- Name: COLUMN merchant_tips.amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.amount_val IS 'total transaction cost for all coins including withdraw fees';


--
-- Name: COLUMN merchant_tips.picked_up_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_tips.picked_up_val IS 'Tip amount left to be picked up';


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_tips ALTER COLUMN tip_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_tips_tip_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: merchant_transfer_signatures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfer_signatures (
    credit_serial bigint NOT NULL,
    signkey_serial bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    credit_amount_val bigint NOT NULL,
    credit_amount_frac integer NOT NULL,
    execution_time bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    CONSTRAINT merchant_transfer_signatures_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_transfer_signatures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfer_signatures IS 'table represents the main information returned from the /transfer request to the exchange.';


--
-- Name: COLUMN merchant_transfer_signatures.credit_amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_signatures.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee, according to the exchange';


--
-- Name: COLUMN merchant_transfer_signatures.execution_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_signatures.execution_time IS 'Execution time as claimed by the exchange, roughly matches time seen by merchant';


--
-- Name: merchant_transfer_to_coin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfer_to_coin (
    deposit_serial bigint NOT NULL,
    credit_serial bigint NOT NULL,
    offset_in_exchange_list bigint NOT NULL,
    exchange_deposit_value_val bigint NOT NULL,
    exchange_deposit_value_frac integer NOT NULL,
    exchange_deposit_fee_val bigint NOT NULL,
    exchange_deposit_fee_frac integer NOT NULL
);


--
-- Name: TABLE merchant_transfer_to_coin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfer_to_coin IS 'Mapping of (credit) transfers to (deposited) coins';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_value_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_to_coin.exchange_deposit_value_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits minus refunds';


--
-- Name: COLUMN merchant_transfer_to_coin.exchange_deposit_fee_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfer_to_coin.exchange_deposit_fee_val IS 'Deposit value as claimed by the exchange, should match our values in merchant_deposits';


--
-- Name: merchant_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.merchant_transfers (
    credit_serial bigint NOT NULL,
    exchange_url character varying NOT NULL,
    wtid bytea,
    credit_amount_val bigint NOT NULL,
    credit_amount_frac integer NOT NULL,
    account_serial bigint NOT NULL,
    verified boolean DEFAULT false NOT NULL,
    confirmed boolean DEFAULT false NOT NULL,
    CONSTRAINT merchant_transfers_wtid_check CHECK ((length(wtid) = 32))
);


--
-- Name: TABLE merchant_transfers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfers IS 'table represents the information provided by the (trusted) merchant about incoming wire transfers';


--
-- Name: COLUMN merchant_transfers.credit_amount_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee, according to the merchant';


--
-- Name: COLUMN merchant_transfers.verified; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.verified IS 'true once we got an acceptable response from the exchange for this transfer';


--
-- Name: COLUMN merchant_transfers.confirmed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_transfers.confirmed IS 'true once the merchant confirmed that this transfer was received';


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.merchant_transfers ALTER COLUMN credit_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.merchant_transfers_credit_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: prewire; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prewire (
    prewire_uuid bigint NOT NULL,
    wire_method text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    failed boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
)
PARTITION BY HASH (prewire_uuid);


--
-- Name: TABLE prewire; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.prewire IS 'pre-commit data for wire transfers we are about to execute';


--
-- Name: COLUMN prewire.finished; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.finished IS 'set to TRUE once bank confirmed receiving the wire transfer request';


--
-- Name: COLUMN prewire.failed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.failed IS 'set to TRUE if the bank responded with a non-transient failure to our transfer request';


--
-- Name: COLUMN prewire.buf; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.prewire.buf IS 'serialized data to send to the bank to execute the wire transfer';


--
-- Name: prewire_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prewire_default (
    prewire_uuid bigint NOT NULL,
    wire_method text NOT NULL,
    finished boolean DEFAULT false NOT NULL,
    failed boolean DEFAULT false NOT NULL,
    buf bytea NOT NULL
);
ALTER TABLE ONLY public.prewire ATTACH PARTITION public.prewire_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.prewire ALTER COLUMN prewire_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.prewire_prewire_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recoup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup (
    recoup_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    reserve_out_serial_id bigint NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT recoup_coin_sig_check CHECK ((length(coin_sig) = 64))
)
PARTITION BY HASH (coin_pub);


--
-- Name: TABLE recoup; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup IS 'Information about recoups that were executed between a coin and a reserve. In this type of recoup, the amount is credited back to the reserve from which the coin originated.';


--
-- Name: COLUMN recoup.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.coin_pub IS 'Coin that is being debited in the recoup. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


--
-- Name: COLUMN recoup.coin_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.coin_sig IS 'Signature by the coin affirming the recoup, of type TALER_SIGNATURE_WALLET_COIN_RECOUP';


--
-- Name: COLUMN recoup.coin_blind; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.coin_blind IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the withdraw operation.';


--
-- Name: COLUMN recoup.reserve_out_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.reserve_out_serial_id IS 'Identifies the h_blind_ev of the recouped coin and provides the link to the credited reserve.';


--
-- Name: recoup_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_default (
    recoup_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    reserve_out_serial_id bigint NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT recoup_coin_sig_check CHECK ((length(coin_sig) = 64))
);
ALTER TABLE ONLY public.recoup ATTACH PARTITION public.recoup_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recoup ALTER COLUMN recoup_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.recoup_recoup_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: recoup_refresh; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_refresh (
    recoup_refresh_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    known_coin_id bigint NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    rrc_serial bigint NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_refresh_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT recoup_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
)
PARTITION BY HASH (coin_pub);


--
-- Name: TABLE recoup_refresh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup_refresh IS 'Table of coins that originated from a refresh operation and that were recouped. Links the (fresh) coin to the melted operation (and thus the old coin). A recoup on a refreshed coin credits the old coin and debits the fresh coin.';


--
-- Name: COLUMN recoup_refresh.coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.coin_pub IS 'Refreshed coin of a revoked denomination where the residual value is credited to the old coin. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


--
-- Name: COLUMN recoup_refresh.known_coin_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.known_coin_id IS 'FIXME: (To be) used for garbage collection (in the future)';


--
-- Name: COLUMN recoup_refresh.coin_blind; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.coin_blind IS 'Denomination blinding key used when creating the blinded coin from the planchet. Secret revealed during the recoup to provide the linkage between the coin and the refresh operation.';


--
-- Name: COLUMN recoup_refresh.rrc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.rrc_serial IS 'Link to the refresh operation. Also identifies the h_blind_ev of the recouped coin (as h_coin_ev).';


--
-- Name: recoup_refresh_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_refresh_default (
    recoup_refresh_uuid bigint NOT NULL,
    coin_pub bytea NOT NULL,
    known_coin_id bigint NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    rrc_serial bigint NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_refresh_coin_pub_check CHECK ((length(coin_pub) = 32)),
    CONSTRAINT recoup_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
);
ALTER TABLE ONLY public.recoup_refresh ATTACH PARTITION public.recoup_refresh_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recoup_refresh ALTER COLUMN recoup_refresh_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.recoup_refresh_recoup_refresh_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_commitments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_commitments (
    melt_serial_id bigint NOT NULL,
    rc bytea NOT NULL,
    old_coin_pub bytea NOT NULL,
    old_coin_sig bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    noreveal_index integer NOT NULL,
    CONSTRAINT refresh_commitments_old_coin_sig_check CHECK ((length(old_coin_sig) = 64)),
    CONSTRAINT refresh_commitments_rc_check CHECK ((length(rc) = 64))
)
PARTITION BY HASH (rc);


--
-- Name: TABLE refresh_commitments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_commitments IS 'Commitments made when melting coins and the gamma value chosen by the exchange.';


--
-- Name: COLUMN refresh_commitments.rc; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_commitments.rc IS 'Commitment made by the client, hash over the various client inputs in the cut-and-choose protocol';


--
-- Name: COLUMN refresh_commitments.old_coin_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_commitments.old_coin_pub IS 'Coin being melted in the refresh process.';


--
-- Name: COLUMN refresh_commitments.noreveal_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_commitments.noreveal_index IS 'The gamma value chosen by the exchange in the cut-and-choose protocol';


--
-- Name: refresh_commitments_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_commitments_default (
    melt_serial_id bigint NOT NULL,
    rc bytea NOT NULL,
    old_coin_pub bytea NOT NULL,
    old_coin_sig bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    noreveal_index integer NOT NULL,
    CONSTRAINT refresh_commitments_old_coin_sig_check CHECK ((length(old_coin_sig) = 64)),
    CONSTRAINT refresh_commitments_rc_check CHECK ((length(rc) = 64))
);
ALTER TABLE ONLY public.refresh_commitments ATTACH PARTITION public.refresh_commitments_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.refresh_commitments ALTER COLUMN melt_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.refresh_commitments_melt_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_revealed_coins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_revealed_coins (
    rrc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    freshcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denominations_serial bigint NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    ewv bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
)
PARTITION BY HASH (melt_serial_id);


--
-- Name: TABLE refresh_revealed_coins; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_revealed_coins IS 'Revelations about the new coins that are to be created during a melting session.';


--
-- Name: COLUMN refresh_revealed_coins.rrc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.rrc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN refresh_revealed_coins.melt_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.melt_serial_id IS 'Identifies the refresh commitment (rc) of the melt operation.';


--
-- Name: COLUMN refresh_revealed_coins.freshcoin_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.freshcoin_index IS 'index of the fresh coin being created (one melt operation may result in multiple fresh coins)';


--
-- Name: COLUMN refresh_revealed_coins.coin_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.coin_ev IS 'envelope of the new coin to be signed';


--
-- Name: COLUMN refresh_revealed_coins.h_coin_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.h_coin_ev IS 'hash of the envelope of the new coin to be signed (for lookups)';


--
-- Name: COLUMN refresh_revealed_coins.ev_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.ev_sig IS 'exchange signature over the envelope';


--
-- Name: COLUMN refresh_revealed_coins.ewv; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_revealed_coins.ewv IS 'exchange contributed values in the creation of the fresh coin (see /csr)';


--
-- Name: refresh_revealed_coins_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_revealed_coins_default (
    rrc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    freshcoin_index integer NOT NULL,
    link_sig bytea NOT NULL,
    denominations_serial bigint NOT NULL,
    coin_ev bytea NOT NULL,
    h_coin_ev bytea NOT NULL,
    ev_sig bytea NOT NULL,
    ewv bytea NOT NULL,
    CONSTRAINT refresh_revealed_coins_h_coin_ev_check CHECK ((length(h_coin_ev) = 64)),
    CONSTRAINT refresh_revealed_coins_link_sig_check CHECK ((length(link_sig) = 64))
);
ALTER TABLE ONLY public.refresh_revealed_coins ATTACH PARTITION public.refresh_revealed_coins_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.refresh_revealed_coins ALTER COLUMN rrc_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.refresh_revealed_coins_rrc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refresh_transfer_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_transfer_keys (
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
)
PARTITION BY HASH (melt_serial_id);


--
-- Name: TABLE refresh_transfer_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refresh_transfer_keys IS 'Transfer keys of a refresh operation (the data revealed to the exchange).';


--
-- Name: COLUMN refresh_transfer_keys.rtc_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.rtc_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: COLUMN refresh_transfer_keys.melt_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.melt_serial_id IS 'Identifies the refresh commitment (rc) of the operation.';


--
-- Name: COLUMN refresh_transfer_keys.transfer_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.transfer_pub IS 'transfer public key for the gamma index';


--
-- Name: COLUMN refresh_transfer_keys.transfer_privs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_transfer_keys.transfer_privs IS 'array of TALER_CNC_KAPPA - 1 transfer private keys that have been revealed, with the gamma entry being skipped';


--
-- Name: refresh_transfer_keys_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_transfer_keys_default (
    rtc_serial bigint NOT NULL,
    melt_serial_id bigint NOT NULL,
    transfer_pub bytea NOT NULL,
    transfer_privs bytea NOT NULL,
    CONSTRAINT refresh_transfer_keys_transfer_pub_check CHECK ((length(transfer_pub) = 32))
);
ALTER TABLE ONLY public.refresh_transfer_keys ATTACH PARTITION public.refresh_transfer_keys_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.refresh_transfer_keys ALTER COLUMN rtc_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.refresh_transfer_keys_rtc_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refunds (
    refund_serial_id bigint NOT NULL,
    shard bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_merchant_sig_check CHECK ((length(merchant_sig) = 64))
)
PARTITION BY HASH (shard);


--
-- Name: TABLE refunds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.refunds IS 'Data on coins that were refunded. Technically, refunds always apply against specific deposit operations involving a coin. The combination of coin_pub, merchant_pub, h_contract_terms and rtransaction_id MUST be unique, and we usually select by coin_pub so that one goes first.';


--
-- Name: COLUMN refunds.deposit_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refunds.deposit_serial_id IS 'Identifies ONLY the merchant_pub, h_contract_terms and coin_pub. Multiple deposits may match a refund, this only identifies one of them.';


--
-- Name: COLUMN refunds.rtransaction_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refunds.rtransaction_id IS 'used by the merchant to make refunds unique in case the same coin for the same deposit gets a subsequent (higher) refund';


--
-- Name: refunds_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refunds_default (
    refund_serial_id bigint NOT NULL,
    shard bigint NOT NULL,
    deposit_serial_id bigint NOT NULL,
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_merchant_sig_check CHECK ((length(merchant_sig) = 64))
);
ALTER TABLE ONLY public.refunds ATTACH PARTITION public.refunds_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.refunds ALTER COLUMN refund_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.refunds_refund_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves (
    reserve_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    current_balance_val bigint NOT NULL,
    current_balance_frac integer NOT NULL,
    expiration_date bigint NOT NULL,
    gc_date bigint NOT NULL,
    CONSTRAINT reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
)
PARTITION BY HASH (reserve_pub);


--
-- Name: TABLE reserves; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves IS 'Summarizes the balance of a reserve. Updated when new funds are added or withdrawn.';


--
-- Name: COLUMN reserves.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.reserve_pub IS 'EdDSA public key of the reserve. Knowledge of the private key implies ownership over the balance.';


--
-- Name: COLUMN reserves.current_balance_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.current_balance_val IS 'Current balance remaining with the reserve';


--
-- Name: COLUMN reserves.expiration_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.expiration_date IS 'Used to trigger closing of reserves that have not been drained after some time';


--
-- Name: COLUMN reserves.gc_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves.gc_date IS 'Used to forget all information about a reserve during garbage collection';


--
-- Name: reserves_close; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_close (
    close_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    execution_date bigint NOT NULL,
    wtid bytea NOT NULL,
    wire_target_h_payto bytea,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    CONSTRAINT reserves_close_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT reserves_close_wtid_check CHECK ((length(wtid) = 32))
)
PARTITION BY HASH (reserve_pub);


--
-- Name: TABLE reserves_close; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_close IS 'wire transfers executed by the reserve to close reserves';


--
-- Name: COLUMN reserves_close.wire_target_h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_close.wire_target_h_payto IS 'Identifies the credited bank account (and KYC status). Note that closing does not depend on KYC.';


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reserves_close ALTER COLUMN close_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reserves_close_close_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_close_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_close_default (
    close_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    execution_date bigint NOT NULL,
    wtid bytea NOT NULL,
    wire_target_h_payto bytea,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    CONSTRAINT reserves_close_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT reserves_close_wtid_check CHECK ((length(wtid) = 32))
);
ALTER TABLE ONLY public.reserves_close ATTACH PARTITION public.reserves_close_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_default (
    reserve_uuid bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    current_balance_val bigint NOT NULL,
    current_balance_frac integer NOT NULL,
    expiration_date bigint NOT NULL,
    gc_date bigint NOT NULL,
    CONSTRAINT reserves_reserve_pub_check CHECK ((length(reserve_pub) = 32))
);
ALTER TABLE ONLY public.reserves ATTACH PARTITION public.reserves_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_in; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_in (
    reserve_in_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    wire_reference bigint NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    wire_source_h_payto bytea,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL,
    CONSTRAINT reserves_in_wire_source_h_payto_check CHECK ((length(wire_source_h_payto) = 32))
)
PARTITION BY HASH (reserve_pub);


--
-- Name: TABLE reserves_in; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_in IS 'list of transfers of funds into the reserves, one per incoming wire transfer';


--
-- Name: COLUMN reserves_in.reserve_pub; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_in.reserve_pub IS 'Public key of the reserve. Private key signifies ownership of the remaining balance.';


--
-- Name: COLUMN reserves_in.credit_val; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_in.credit_val IS 'Amount that was transferred into the reserve';


--
-- Name: COLUMN reserves_in.wire_source_h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_in.wire_source_h_payto IS 'Identifies the debited bank account and KYC status';


--
-- Name: reserves_in_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_in_default (
    reserve_in_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    wire_reference bigint NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    wire_source_h_payto bytea,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL,
    CONSTRAINT reserves_in_wire_source_h_payto_check CHECK ((length(wire_source_h_payto) = 32))
);
ALTER TABLE ONLY public.reserves_in ATTACH PARTITION public.reserves_in_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reserves_in ALTER COLUMN reserve_in_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reserves_in_reserve_in_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_out (
    reserve_out_serial_id bigint NOT NULL,
    h_blind_ev bytea,
    denominations_serial bigint NOT NULL,
    denom_sig bytea NOT NULL,
    reserve_uuid bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT reserves_out_h_blind_ev_check CHECK ((length(h_blind_ev) = 64)),
    CONSTRAINT reserves_out_reserve_sig_check CHECK ((length(reserve_sig) = 64))
)
PARTITION BY HASH (h_blind_ev);


--
-- Name: TABLE reserves_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_out IS 'Withdraw operations performed on reserves.';


--
-- Name: COLUMN reserves_out.h_blind_ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_out.h_blind_ev IS 'Hash of the blinded coin, used as primary key here so that broken clients that use a non-random coin or blinding factor fail to withdraw (otherwise they would fail on deposit when the coin is not unique there).';


--
-- Name: COLUMN reserves_out.denominations_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_out.denominations_serial IS 'We do not CASCADE ON DELETE here, we may keep the denomination data alive';


--
-- Name: reserves_out_by_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_out_by_reserve (
    reserve_uuid bigint NOT NULL,
    h_blind_ev bytea,
    CONSTRAINT reserves_out_by_reserve_h_blind_ev_check CHECK ((length(h_blind_ev) = 64))
)
PARTITION BY HASH (reserve_uuid);


--
-- Name: TABLE reserves_out_by_reserve; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_out_by_reserve IS 'Information in this table is strictly redundant with that of reserves_out, but saved by a different primary key for fast lookups by reserve public key/uuid.';


--
-- Name: reserves_out_by_reserve_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_out_by_reserve_default (
    reserve_uuid bigint NOT NULL,
    h_blind_ev bytea,
    CONSTRAINT reserves_out_by_reserve_h_blind_ev_check CHECK ((length(h_blind_ev) = 64))
);
ALTER TABLE ONLY public.reserves_out_by_reserve ATTACH PARTITION public.reserves_out_by_reserve_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_out_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_out_default (
    reserve_out_serial_id bigint NOT NULL,
    h_blind_ev bytea,
    denominations_serial bigint NOT NULL,
    denom_sig bytea NOT NULL,
    reserve_uuid bigint NOT NULL,
    reserve_sig bytea NOT NULL,
    execution_date bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT reserves_out_h_blind_ev_check CHECK ((length(h_blind_ev) = 64)),
    CONSTRAINT reserves_out_reserve_sig_check CHECK ((length(reserve_sig) = 64))
);
ALTER TABLE ONLY public.reserves_out ATTACH PARTITION public.reserves_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reserves_out ALTER COLUMN reserve_out_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reserves_out_reserve_out_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.reserves ALTER COLUMN reserve_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.reserves_reserve_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: revolving_work_shards; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.revolving_work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row integer NOT NULL,
    end_row integer NOT NULL,
    active boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE revolving_work_shards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.revolving_work_shards IS 'coordinates work between multiple processes working on the same job with partitions that need to be repeatedly processed; unlogged because on system crashes the locks represented by this table will have to be cleared anyway, typically using "taler-exchange-dbinit -s"';


--
-- Name: COLUMN revolving_work_shards.shard_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN revolving_work_shards.last_attempt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN revolving_work_shards.start_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN revolving_work_shards.end_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN revolving_work_shards.active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.active IS 'set to TRUE when a worker is active on the shard';


--
-- Name: COLUMN revolving_work_shards.job_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revolving_work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.revolving_work_shards ALTER COLUMN shard_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.revolving_work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: signkey_revocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.signkey_revocations (
    signkey_revocations_serial_id bigint NOT NULL,
    esk_serial bigint NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT signkey_revocations_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE signkey_revocations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.signkey_revocations IS 'Table storing which online signing keys have been revoked';


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.signkey_revocations ALTER COLUMN signkey_revocations_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.signkey_revocations_signkey_revocations_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_accounts (
    payto_uri character varying NOT NULL,
    master_sig bytea,
    is_active boolean NOT NULL,
    last_change bigint NOT NULL,
    CONSTRAINT wire_accounts_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE wire_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_accounts IS 'Table with current and historic bank accounts of the exchange. Entries never expire as we need to remember the last_change column indefinitely.';


--
-- Name: COLUMN wire_accounts.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.payto_uri IS 'payto URI (RFC 8905) with the bank account of the exchange.';


--
-- Name: COLUMN wire_accounts.master_sig; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.master_sig IS 'Signature of purpose TALER_SIGNATURE_MASTER_WIRE_DETAILS';


--
-- Name: COLUMN wire_accounts.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.is_active IS 'true if we are currently supporting the use of this account.';


--
-- Name: COLUMN wire_accounts.last_change; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_accounts.last_change IS 'Latest time when active status changed. Used to detect replays of old messages.';


--
-- Name: wire_auditor_account_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_account_progress (
    master_pub bytea NOT NULL,
    account_name text NOT NULL,
    last_wire_reserve_in_serial_id bigint DEFAULT 0 NOT NULL,
    last_wire_wire_out_serial_id bigint DEFAULT 0 NOT NULL,
    wire_in_off bigint NOT NULL,
    wire_out_off bigint NOT NULL
);


--
-- Name: TABLE wire_auditor_account_progress; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_auditor_account_progress IS 'information as to which transactions the auditor has processed in the exchange database.  Used for SELECTing the
 statements to process.  The indices include the last serial ID from the respective tables that we have processed. Thus, we need to select those table entries that are strictly larger (and process in monotonically increasing order).';


--
-- Name: wire_auditor_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_auditor_progress (
    master_pub bytea NOT NULL,
    last_timestamp bigint NOT NULL,
    last_reserve_close_uuid bigint NOT NULL
);


--
-- Name: wire_fee; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_fee (
    wire_fee_serial bigint NOT NULL,
    wire_method character varying NOT NULL,
    start_date bigint NOT NULL,
    end_date bigint NOT NULL,
    wire_fee_val bigint NOT NULL,
    wire_fee_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    wad_fee_val bigint NOT NULL,
    wad_fee_frac integer NOT NULL,
    master_sig bytea NOT NULL,
    CONSTRAINT wire_fee_master_sig_check CHECK ((length(master_sig) = 64))
);


--
-- Name: TABLE wire_fee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_fee IS 'list of the wire fees of this exchange, by date';


--
-- Name: COLUMN wire_fee.wire_fee_serial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_fee.wire_fee_serial IS 'needed for exchange-auditor replication logic';


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wire_fee ALTER COLUMN wire_fee_serial ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wire_fee_wire_fee_serial_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_out (
    wireout_uuid bigint NOT NULL,
    execution_date bigint NOT NULL,
    wtid_raw bytea NOT NULL,
    wire_target_h_payto bytea,
    exchange_account_section text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT wire_out_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT wire_out_wtid_raw_check CHECK ((length(wtid_raw) = 32))
)
PARTITION BY HASH (wtid_raw);


--
-- Name: TABLE wire_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_out IS 'wire transfers the exchange has executed';


--
-- Name: COLUMN wire_out.wire_target_h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_out.wire_target_h_payto IS 'Identifies the credited bank account and KYC status';


--
-- Name: COLUMN wire_out.exchange_account_section; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_out.exchange_account_section IS 'identifies the configuration section with the debit account of this payment';


--
-- Name: wire_out_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_out_default (
    wireout_uuid bigint NOT NULL,
    execution_date bigint NOT NULL,
    wtid_raw bytea NOT NULL,
    wire_target_h_payto bytea,
    exchange_account_section text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT wire_out_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32)),
    CONSTRAINT wire_out_wtid_raw_check CHECK ((length(wtid_raw) = 32))
);
ALTER TABLE ONLY public.wire_out ATTACH PARTITION public.wire_out_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wire_out ALTER COLUMN wireout_uuid ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wire_out_wireout_uuid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wire_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_targets (
    wire_target_serial_id bigint NOT NULL,
    wire_target_h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
    CONSTRAINT wire_targets_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
)
PARTITION BY HASH (wire_target_h_payto);


--
-- Name: TABLE wire_targets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_targets IS 'All senders and recipients of money via the exchange';


--
-- Name: COLUMN wire_targets.wire_target_h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.wire_target_h_payto IS 'Unsalted hash of payto_uri';


--
-- Name: COLUMN wire_targets.payto_uri; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.payto_uri IS 'Can be a regular bank account, or also be a URI identifying a reserve-account (for P2P payments)';


--
-- Name: COLUMN wire_targets.kyc_ok; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.kyc_ok IS 'true if the KYC check was passed successfully';


--
-- Name: COLUMN wire_targets.external_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.external_id IS 'Name of the user that was used for OAuth 2.0-based legitimization';


--
-- Name: wire_targets_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wire_targets_default (
    wire_target_serial_id bigint NOT NULL,
    wire_target_h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
    CONSTRAINT wire_targets_wire_target_h_payto_check CHECK ((length(wire_target_h_payto) = 32))
);
ALTER TABLE ONLY public.wire_targets ATTACH PARTITION public.wire_targets_default FOR VALUES WITH (modulus 1, remainder 0);


--
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.wire_targets ALTER COLUMN wire_target_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.wire_targets_wire_target_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: work_shards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_shards (
    shard_serial_id bigint NOT NULL,
    last_attempt bigint NOT NULL,
    start_row bigint NOT NULL,
    end_row bigint NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    job_name character varying NOT NULL
);


--
-- Name: TABLE work_shards; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.work_shards IS 'coordinates work between multiple processes working on the same job';


--
-- Name: COLUMN work_shards.shard_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.shard_serial_id IS 'unique serial number identifying the shard';


--
-- Name: COLUMN work_shards.last_attempt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.last_attempt IS 'last time a worker attempted to work on the shard';


--
-- Name: COLUMN work_shards.start_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.start_row IS 'row at which the shard scope starts, inclusive';


--
-- Name: COLUMN work_shards.end_row; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.end_row IS 'row at which the shard scope ends, exclusive';


--
-- Name: COLUMN work_shards.completed; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.completed IS 'set to TRUE once the shard is finished by a worker';


--
-- Name: COLUMN work_shards.job_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_shards.job_name IS 'unique name of the job the workers on this shard are performing';


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.work_shards ALTER COLUMN shard_serial_id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.work_shards_shard_serial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_bankaccount account_no; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_bankaccount ALTER COLUMN account_no SET DEFAULT nextval('public.app_bankaccount_account_no_seq'::regclass);


--
-- Name: app_banktransaction id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction ALTER COLUMN id SET DEFAULT nextval('public.app_banktransaction_id_seq'::regclass);


--
-- Name: auditor_reserves auditor_reserves_rowid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves ALTER COLUMN auditor_reserves_rowid SET DEFAULT nextval('public.auditor_reserves_auditor_reserves_rowid_seq'::regclass);


--
-- Name: auth_group id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group ALTER COLUMN id SET DEFAULT nextval('public.auth_group_id_seq'::regclass);


--
-- Name: auth_group_permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions ALTER COLUMN id SET DEFAULT nextval('public.auth_group_permissions_id_seq'::regclass);


--
-- Name: auth_permission id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission ALTER COLUMN id SET DEFAULT nextval('public.auth_permission_id_seq'::regclass);


--
-- Name: auth_user id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user ALTER COLUMN id SET DEFAULT nextval('public.auth_user_id_seq'::regclass);


--
-- Name: auth_user_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_groups ALTER COLUMN id SET DEFAULT nextval('public.auth_user_groups_id_seq'::regclass);


--
-- Name: auth_user_user_permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_user_permissions ALTER COLUMN id SET DEFAULT nextval('public.auth_user_user_permissions_id_seq'::regclass);


--
-- Name: deposit_confirmations serial_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_confirmations ALTER COLUMN serial_id SET DEFAULT nextval('public.deposit_confirmations_serial_id_seq'::regclass);


--
-- Name: django_content_type id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_content_type ALTER COLUMN id SET DEFAULT nextval('public.django_content_type_id_seq'::regclass);


--
-- Name: django_migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_migrations ALTER COLUMN id SET DEFAULT nextval('public.django_migrations_id_seq'::regclass);


--
-- Data for Name: patches; Type: TABLE DATA; Schema: _v; Owner: -
--

COPY _v.patches (patch_name, applied_tsz, applied_by, requires, conflicts) FROM stdin;
exchange-0001	2022-03-18 14:38:40.934718+01	grothoff	{}	{}
merchant-0001	2022-03-18 14:38:42.271142+01	grothoff	{}	{}
auditor-0001	2022-03-18 14:38:43.114756+01	grothoff	{}	{}
\.


--
-- Data for Name: aggregation_tracking_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.aggregation_tracking_default (aggregation_serial_id, deposit_serial_id, wtid_raw) FROM stdin;
\.


--
-- Data for Name: app_bankaccount; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_bankaccount (is_public, account_no, balance, user_id) FROM stdin;
t	3	+TESTKUDOS:0	3
t	4	+TESTKUDOS:0	4
t	5	+TESTKUDOS:0	5
t	6	+TESTKUDOS:0	6
t	7	+TESTKUDOS:0	7
t	8	+TESTKUDOS:0	8
t	9	+TESTKUDOS:0	9
f	10	+TESTKUDOS:0	10
f	11	+TESTKUDOS:0	11
t	1	-TESTKUDOS:100	1
f	12	+TESTKUDOS:92	12
t	2	+TESTKUDOS:8	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2022-03-18 14:38:53.857922+01	f	5728923f-57f8-4c18-bc40-c44eb0ef2ec9	12	1
2	TESTKUDOS:8	MYYRAPN6PXBYKKP7T307FMAEVY18Z01X5DYTV20RKBK6DN8SNQC0	2022-03-18 14:38:57.579249+01	f	8abf6449-48c1-4854-8292-d98fffde54f1	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
2ff8de13-55bc-456c-920c-f124da1462aa	TESTKUDOS:8	t	t	f	MYYRAPN6PXBYKKP7T307FMAEVY18Z01X5DYTV20RKBK6DN8SNQC0	2	12
\.


--
-- Data for Name: auditor_balance_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_balance_summary (master_pub, denom_balance_val, denom_balance_frac, deposit_fee_balance_val, deposit_fee_balance_frac, melt_fee_balance_val, melt_fee_balance_frac, refund_fee_balance_val, refund_fee_balance_frac, risk_val, risk_frac, loss_val, loss_frac, irregular_recoup_val, irregular_recoup_frac) FROM stdin;
\.


--
-- Data for Name: auditor_denom_sigs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denom_sigs (auditor_denom_serial, auditor_uuid, denominations_serial, auditor_sig) FROM stdin;
1	1	39	\\x3d8bec7986b4c08db6edeca03ec5734b11cd28291fa3483db2475465debe629e6f5643cd5af8a49b13617bcd942e1bb8ecfa5a81e88a3779a9916f5af9b1c603
2	1	98	\\x0db46cc389cfc5027b6235ebe0ee6e2846b4925f0f26db52c9222f932e1325eb57d7676ef31ec99a3155dd79281174b61633d6abcaed5bb674ece08544b65704
3	1	275	\\x613ad83dbaa52febcf28d9d5a6c1751fbfc31257e09895f9777d45c81139bebeacbd0ac2e045cfa8af1f0c752bef18b285d63d8d732dc61072b96d5b2261d40c
4	1	339	\\x53dab661996cce45d3260f88cb492cf669d08e58e80026077862cdf3c5a005c81322fc27722b46d61c1c9f6b81b91da75e8b8c29213132615938bec7ad9f940e
5	1	113	\\x0d95688cc794d44dbdcc64cdb61ffafb41be6e3649cd5f4c345fa06918a7d544875518bddd48f0e9f8cc13bb26596c746b5020473b804f5adfd578d015c88708
6	1	132	\\x8eee12f290ff73cf6ebaa9728a7cbc3ca3a7f72e4ea8c94291bc23f34485abca2db2f48d8e78f1243d701f5bc8c8b91bee6fa07787ee408bd014f2f76378550c
7	1	106	\\xcae25b7ffac8e67b271bfc0c86007566119f0dbb5da86c6b082c6ee9463e258ff6051a6f22aa237effbf059ba709d0f0fa2af8066ee0f49d18cdb0b5f48b4e05
8	1	154	\\x5de0cf6f21a55db1207b58fd5c7d34a90fe29cbaba1f2d0d4b6173e983988265ab37c807ee83ceae8e30e121c18b41248aaa3a19d462a4ff9ecb056ecb3e5403
9	1	208	\\xf1d37e6b9c7626fd15eb07ffec737e986b499667b18227b1f68c95986b7c74d3d6e37189ac42326a3e73641e45028fb86625e2aeed60965d4b1c4d85c3b3de07
10	1	159	\\xd0e05d59a40e53303c1bfa53de4a92748e0478e776a78d29b5b1c91cd48a9857dee83ed6565c3b731cf1aba8362f76f9520c3d389fbb924fd3162a05c833040f
11	1	245	\\xe240a3d3449af9b06d99af342a83f44905ebf21ea855d019147d5e46d1ea0189a09960d0ef51b63771b9d12f11d42398f41d0948b719e41187b13593211a9802
12	1	283	\\xaf217d544eee12721b0182a23317b4e07f5abc7ad144c5fd70bfea371ee21206a957479edae7ff704b3ff0fb2ffc1e299dbbd58c55bd1949f5ed796cd49c3808
13	1	203	\\xf9cd000885a4fb3174ffbfd6040dbb26b51e82b8f3c868f68ce355937f3b52c8d7c5410eca9d49d39c3f5a04d62b217597d1e3a9c431a72995cd6f31cf5bf20f
14	1	236	\\x39bb6f1d562fb5739687841b500b9a2153715f163ef1cbdb62c8df0fcc424156e5488961617da7a9590a1ce582d7fff1f34bb9ca4cbcdf6e0e54f02bcc94dd02
15	1	418	\\xfc784fb3ecf19d2d447360b203ea863e63a422177dfa41c970f550e43ac8c27dd0b44d4b2ede8ca8602a919f0236f55bcedca7e2c5e4fd4240e03937f481950a
16	1	248	\\x57b86174280f26b246df010179b40027ebdd5f74bcbaa93ee693730b61e32596b3a807784ea794fb95e01cf73d05e06b12d6940bf893c63cf189191e9a25c706
17	1	212	\\x6bf686484273bfc8576f9f5c037c98ca0ed8dbe19999a104db9b95218bfbd9a0ebde66ea9e352edf72abadf8c9c7717d5edcc13a6a687d8693a291d22e049503
18	1	324	\\xbbe75892057ffea660924c20b9bb410bcf4565b7f5462c39e9b25b401623e86b03f08b51d5c6c0e9c5bae83bcbf02159ea0d644e29c6d10950347340e245790c
19	1	314	\\x9eb3d3146fd7c6278664e3b2638618c4346a53a365945b7caaf9f17573455697939e76511fc3f56a1c20e1f594e17aca411dfb299cc01202636cac23e37c1506
20	1	44	\\x6c66b13ae9339f4a992b025df675daa8a479ea2d8c7b56808c0ec338a29dae8714c6750ae2322a47975d1406fd78122ea0a8b73373b9b16d749382be594dd202
21	1	155	\\x299e60bbf8395d33bd5be6a39af0e3c22f76bbc1d3fa36067506ef8a5d2383751213f5c31e3551f659465005c1307689ece49b8e50619915590d7af6d9e30306
22	1	10	\\x6956e10dda005596045e60c1a8849cc219a9a9738e8631f3faf3f162c43314b536922a2c95431e5b3806d0e2535ea5d3cdad78347445fec5d9f18252a2e4e50c
23	1	401	\\x0e09cfb46ad06e66dc65d6037322171f291b393c9e6bb7c58bb0c79fe7d50cf1c8a87eefb952d44a03e2b0e8ee618b7d2efc0d6e50f5172ccb18c906ef8dd903
24	1	96	\\x5929e25d584a7533c0160be0914676570aaa0adf01f6e979b82120ad96fc50b36cdf43ae6cfa07b630b94ba95606a53a5fd5d11a6d4f1173ce5972a1a2aa300f
25	1	47	\\x202c059c204235a29dba1cdb6803d0b1c2f64ca13fcf3bfec891b0017853130dd7301430ed098ade8621b2c0b684da59a5b2a6e10b89f56351792f05729cc10b
26	1	222	\\xa73a37cbe9d7a16fb0493e5fa961491ecb000676a805894429b58c65292556d07dfaf381ffda3ddef9a61ccecb9dd8d7ff605a2db8eab8fabbf77f843f1b9808
27	1	114	\\x74da817e97b65d3f6adee9169a163f1c83be07c3c8456f8a58a444d5a7d1cdcae1909d5dda5bdf6a37e9fa10a0a3a9e0494a736019191cdbbb26eaae61289d04
28	1	290	\\x1e4dc497fa21542878ad65d4ea3cdf51fecfb0cfad2021eb7ed18ae5f066048e484e8a2bff779ef4d5646a15a9b79ea20af217b966643c8cc2ac50c5a5209d01
29	1	287	\\xb8b7b40be2d2ddbf8b67e29188550cae9c60e82cefda3ef52d2cfd2ddd2cedf553e61553d5ca83b33df01a1dd03e392027b6015ccbb171ce63b72cb4d7d27c08
30	1	36	\\xb626e10adb620e3810ec04e66a65d931476298aad3bc66b743091622eb587219dbe057849051b9946e5cd80e450a8fbf7b3ec8153f55745a7046dbbf36ff9b02
31	1	140	\\x3f77ac0c86ae84a1de9900c014d70f1231bfd7926bb06138862c022d8f379fe692f3ac376bccfb15c3e460f09032143e78a250c926c2f7c8a3181d87224ad70a
32	1	205	\\xdad8fc86881e6124c25023fd3e86149aa1e56e32a54d4ec48b36c2ba7cec9235c254af3df056eef59c58279b977b11146c17faa40746746182b7c2d9e114e209
33	1	416	\\x9c378ce6ec0368f494525e3c42a7914f3c1ec806756803dd4ae9a54dffe2d7885e058cdfe390016b2f8a4878b46cc421e03abad0afde03800d8cf8c7e53ad909
34	1	61	\\xf89741068fbd75b49c13cd8526a75b4d30d209d4ab348b1d1e8ab950f3cb4d580374a1072da1c17114e7c1658ae010c92265ff3b25586ba1dda2d7ff9046d608
35	1	83	\\x2b02e83a6c162b31ee2cf778b23b27d23308e45c909eb1fdc7eb1ff7c686f440c18c426ef2487f2882ac4d8c61035a01ad149a8ee74ad0bad8c946f77fec9809
36	1	118	\\x0a33127c15b795484c4117486ed3da7027c1c5943c13542567c42cebec9eb3903992f64a2dd658fc9987e1bacf48d1f5a57e42c099d0d89052eee7904e105401
37	1	126	\\xd1b24bc7fd62b1bc04e291a96d7f4c095c07aa2b9fff82af7db2ea57424f16266457e468f00d6d21cc33325842abfecc81ccab6906bfb73b3c1258de2ad7160d
38	1	40	\\xa1209340f9c811379e55a8e67b2bdd1694283b29c1744dc5c7ad5f9d8f8844d4f0ee131b5679256a3b3ba0fe434f6ff0d730d6e3965eae90204bcc2c3a803a0e
39	1	86	\\x29195104e637afad48784ce50eab62ab00f0c9b7611d596d3908601e8d1dd360c853d99ffb91470f96f5206a12667e1a70822e056cb5b2d068c02232c35d970e
40	1	71	\\x6a78ce56f52ce903a87902011f01541a57177ae7349f7417ed451035c0480fa3ff902ae5cc3a1ca3dc32adcb4a2f89e86c2e7aca0fd221a3b26e71921bdf7108
41	1	215	\\x17afe3c92a489c749e81de89b5c7d041cac2cec89e11631dee499eb409188b8e15104e8bea00b0bfe56622619fe310d2f0ed8566cf1db72887d9ee4ddbd84b07
42	1	100	\\x639866d328860974e47aea9bb6423fa61a320a05a91fa3fa6406f8696e8f11b97e252406b68677fe69f6fd4532d772012e71c0d4e8de9ed73f8dbf06a945e60b
43	1	295	\\x83e96ad4ab6bc783abbde154598809c1221cc103d2eac1810d22a20491b53cc114c5dd6f4ceed6c35c05795984a2ba574f9c92ce844b889a564c6d4b38aefa0e
44	1	383	\\xef7456a932bddee066750123e5093ff53e423eee3ad270696a821909412ebf759c931d8b6f1d57812d3f87db8fb333b052dc9eb1ef0cabcfe86b423ae2f16906
45	1	317	\\x35f6e468746164264f5ab63f2709a965621cb429b6d2193fe52ddaf85041ab75755d8738046065f9eda84ac518eb278994e1462d87513a0ccafaf521cb1d7900
46	1	322	\\xc2554161eae1f42e8ef1d06785123c2efb50c6562fca1b6a785b356cd5571263b6c70de62dde4a79d6a1e838b75b87c60e49d0723c2a63c7d7f1bc88deac2f0a
47	1	278	\\xd38790f146cfa9658694b8427254ee11515e20f9266913579d768e1410bf3aacb743f797dfae338547ddaa84af1a03112f7828c7d70ed24733d08273b4eaef04
48	1	273	\\xb294db408b7ac5f445ff51832032e18ed33de8c0d0122345de0292fca748568fa395cde8379dbec1807805e71fa91fb105323495b4ba835f121748f84c02ee0e
49	1	30	\\xa15ebf59a89651de4c88d27285f2b418d78485e5c27a8d50dfaa3af1b4c2b7fb1f13c4e25a3d562776fa8d8da0468f26e028cb2de1239136be131c926fc9a80f
50	1	373	\\xa7b9e9140ccae8a18ae994066ce3f90c940ea9eef79e657d76252a8d2c2fac23aa4f04de0831f849189ce3bbbc4ed19af5a8ce9ea18b297fd06437b01a86c30a
51	1	111	\\x28542e0d31aef9116013e21f791d5bf7a1d243583ab5eeeb3c1ed9e03e18dbc01a6b22ebe60307a49ed81fcb51b7a47b7ce6e43dc97560cf9b2c2e6177ced105
52	1	119	\\x1d3b172747a254eb837fca2564718d55daa26d86be23c2e9eda40cc56cd19557b079423182067c43c5d0258a7a453d11adc2969f9ad175c97ed4c72634abbc0a
53	1	72	\\xe6194b3c95c2dd3a544a8acb622566108159d778ff69dff7fe55df6fedd23618e43de99672305b16b43ce7b85a828fb34f79915f618ba81b57464c0499faa10e
54	1	166	\\x117b2401c05e9609fc26890243a48afa9bdd3e8dcd35a4797a0dbc9aeae3b8f6981cea267cc60066c6799e9686ed907df7e68d4ae8e2ffb2eadcd4bb6d631901
55	1	337	\\x3720c566ec63bab351a096a756845279643991f0f763d63071b285353e76993a75ef19983173eec1a5d51ab01667c1d5d71c17d6400d99059b42b90b88a2690e
56	1	117	\\x46e1e19fce188220e5c207a9c20fbd4ffc6b07612ed51a4445788b8358041563e76fdf5247756b3024ab935cdd7a6e40271ba97a7808e47ab9f3ea56f575d507
57	1	364	\\x53ae0c576851a2a624ae2fbe0fb25fabd4a61bdfa5dc1de0321d5c073508656e42f9d70ccf9b3623bdedfc9556c1d7437c7504f1d06607fd421123ceaa682200
58	1	82	\\x7789f7291487ba2ec2cc0acb005340c2bb99507ae02394a94645d8a8c85d0d669d57f4e0c8f8840d842a1a677d9d602ead204b302135bdecf385d2658b77d50f
59	1	309	\\x3e5486efbef52b4ed7023aaef162e4fb8abdf88769d5d26293cf2a7520400fe1679e7a42783f0c462c4c6fba7dce73dea0f7bb89b44c0c8d76d9c5fd3c076104
60	1	4	\\x7b5f867e568f4acc12c03f7dc21060926ee2e90dee94bdb04099199a7e070e3936e8008bdee935c31074d4cc535937fbc07381e69df3e17b710ef810b8f46403
61	1	333	\\xc6af8f74fee022e01f41f2d1cafbe2b6c1f2d97f8e041a65dfd5e832b48f8ab76eb918a9830f244750d8ff8142c43008fd7908e09c3d2edcbdd75ca222261301
62	1	286	\\x57b68904a2bf968c7bcc0f2dc7e332b968c7c7ad0189cb73be790c4fb08b4c89c6e85a24e14be452c62aa22aae3d97ab01c0faea7aa2ff0391ecac76678b3200
63	1	294	\\xb1f9c61006041cc57ca5a05b14987f95a40b011dc2886d5e6ec8121c2307ba7faff515750871768250e3249cb33c959c84c8709fbfb3160987f08f574911fd03
64	1	320	\\x51a0db8a0430384e19f197ee50d49f21573c37fcab370ac35d5a70dbd800bc89281dc1c8debf17ae1986f572630baad031e27ad050e8abb941bd5301e5b9fe01
65	1	62	\\x2c0fab42db2538ed34e997121b4c6cd717cfe882a7530422d6ecf0031dd601cffd3f974030adeb3da03d85c75a07fee142b2f695083c026923b53b08963cf70e
66	1	252	\\xca9de5adf33b932f721115ba86b4d110ba912679d39c684d0b57595fa6be7cc2289851a2cd7d5b294a552c0fb45287838685e79be88e3b3626cf66ba4fc1cb0f
67	1	268	\\x31e396fba458aadb4e3b37a6bc690a6f60d6573fcad98d7db8cedb7b32190cc8a30fb744cf21617f89cfc4cc751834302cd49b14fcdc629b10cbc2da3a608d0d
68	1	49	\\x7cf8a1121d5bea5bbc843dba8df0574a77bcd48e1c8f06079f85203a30b52d2663c3ed5e2e4cb07fd4561f8d46117923c41c2cc6607b705bef4a50bf0f256c06
69	1	250	\\xb9a5a77d73649f32263b0dd38e633caebd67b2177e65f14f977a4624645e19a85590220e36555bb94233b7d8f2a445fd331392fea31417f92e3abf0f2e57520f
70	1	328	\\xeda267d22773228c2de77a37187b3a43bcdaf65e66eae88f19cd824d9fb2140264cffb27896f3367010893079b0e332a075fcb5dde415190c58f7a4275cacf06
71	1	311	\\x8fb595940e5dbe2c9e747cb601390073238083765cb137a06ad023d8685258f2c63a527be7a8ed0f33975fcccb652cf87e6f0751d8f62d148b23127361fb8208
72	1	3	\\xc4905bca2d4727a47ba3c9f0a4a51200b99989fdc7fc47e9902292bdf37aefc64433996267ee7888faafbac901bccffa7ffac0c560d3b0ad648cb302c1cd310a
73	1	239	\\x6eb1eea62b33848d125347cd5e04af61d701f419451c7eb79f10e52466775e747f7543f542e2e469d46ea9bbc9b8aeb80b0fe3ec7ecae7614c1c74345ef08c07
74	1	256	\\x605fd1d6ddddecd416160267fbabd524001546f0a7cda563f42851568cd8db038a691b0e13e042a7cefe9dbeafb91be0ec0ed65717cad6dcf6da052529f1e70a
75	1	338	\\x12fd8db7541785072102a1d60028f69dd6ee989b3046c1caf661e7fc2af5d7b088d19c9ddde79803c20575f12338177a7bff3352bf92cb90dcd9e9b8db366f04
76	1	346	\\xfbd0efa7d319dd3fc375071e86ade2b8a042bb688a7382c0296660f3c59e11c05f2c05f5ecc9d16af6859abd45780c63047bdfb880443287076f885a2ba94a00
77	1	165	\\x76f366f5cf12eab33ee87012dd6cfb6fa5be3c815c34a56e650520fc76c92ed2aa55ce6aaf7b88ffc53c0150923fc9299c33ee80bf6a3ecaf537118697632f0e
78	1	411	\\x2e583cfb3936465eec4d7cfec1a20442adaad4fa3fc379d537188b8923db8ed87c8481308cf76a6def1a474fd13714e62c632c2bcdfe53066c17d54768c7e90f
79	1	180	\\xa4cfa917a9cc62b4a6c53f2fcd0c0ec1a7c8e365f47eeb470abc060c4e65ce47ac9c2c4beadc94e67b22c690c1afe39a92f5ed0fed6fac2b81e99566f96dbe06
80	1	417	\\x4c23b56e133983fc5a0e7b1634b13656cfbe55cf0727f09ddd7e35346b3e4689f28f519c264334c4ba9f8d6132985e627445d19064713f99a3283ec59c99eb0e
81	1	421	\\xb6f1f7779b2898e42c71ce8b96c3c06cf83d46159d35255effb87413594334670debbab66d1c4c07852575f2dc1232f989f3339aad729785fc32eb0609931506
82	1	2	\\xd0f5deea4c5ceb67bb17be366cab8b083420a89b3554a396f8fd340caf57a0e484575285d73788453b4e2a8644290d6e1b0a0f60e663e88c4230efcd1335e90c
83	1	398	\\x3bf1b441ac03eb2bbb632ef81d4998388597b71a2b11fe1a5f51718681b8bb1efabf96dd24ef07c422e5a84a9830546a6d43c88890e4f55ae81513e6e7a2690b
84	1	177	\\xea7770c658b38f3f3d309ac6ab259fea5f9608d0a1f10bcf4c068de3e9d72f75cde8a5c417e4d084c36eba81552d0f11edd0a4a27296cc65bba3eb85d14fa30f
85	1	370	\\xe3bd2f2afe16dc8191596fbc4b40b9c038238e32ebc3864db41acc4e04b790b1b8ca633a60c2cac5a188154a996a3076b1544bb2819e7ed9bab616fbcc261b08
86	1	186	\\x19c4075c2c2eb12b2a098d1f54c4de23b70d32af92b98f731a3973edb602a4ce6b01f66c2716c3a122f3b01968d55a0bc57b1774635e203274167fe52587ad0c
87	1	404	\\xed54e99e3207064c6f0f725ed5d60be4da05a91e9ff95e9a2b81c6ad449c2058628a151b6d19204b1146b3a534e306863b80c44aaeac4a5dd5ce8c3676b06c00
88	1	138	\\xab21f95dee908c2658dd53ddd05c388a69156e14275fa1a7791ce9eaadcedc427e078dee643db19141564f1af138fccd302329c090c70ca1ee1fab489ead040b
89	1	189	\\x1745c2db098272ba7e6d610076cec4f1130fe6653b39254431bd6b3caee9f4ccc33f863032fe49abfec23a44065c8633f1c6a4aa9b5cfd8a7ffd676597a56001
90	1	29	\\x41f650d5d9d2c6057f20088a17653382e970f605347f57bf9ea99765857cebb9040308c20fdd755477693ea246485ce56841755299f90461f981f511567ff90a
91	1	259	\\xfbbacf3ee19625de8be40b342e8e7174fe24d5ce93e790e7fb5cc6224e8c0536bbc86e738dd25e2df3bf25e1ac6b73977b4f124426fcba01be2824a4cf7e120c
92	1	240	\\xcf137452ab7e1382ad683a96b24cce638c3b4ce1ee1c85a718f561a0de4334ffff443a5b59e39b44bb1aeb995304a2727393e1bdff88e626efcae979463dbd01
93	1	377	\\xd832fe1ce9f208a64de5de1bba4f20ba05d1af3f2a15abbe391c4b3c02bcdd578da3ad9ee8a79480c539e10e1a336d306dd90abd09515af171b05ad291d16309
94	1	329	\\x6d01eaee94eaa99d4c867ca782751d899611f41a521c593f21c648a48349993c61ffb00ea3a1594318c5b5cad9334db9281e10f4bfb85a154592241dc2a6fa0e
95	1	183	\\xa76f9ab85e48634c9ae2d07dd3afdc62930c4644ba7df3e749ca39b495274b9e81b6e41af340b578cd748e9db4686bca81069b7b71557c01db63a2b5ad614308
96	1	184	\\x97afe90eb5a03ff2a29a0d6f880f9312d545654abde94b528060bb095ade11480e698addc737b78fcdb891d0b42099394e83637459247e8084338569f105360b
97	1	355	\\x44a66903e24dc4a51c68e1523b9ddeda69e208ad68dd8b406afbdff5b7de9cdb9868e953483a921e5cca498107ff2ad6acb3fcb769810d1be65a450fe1f70303
98	1	68	\\xdc93fe945ed6b2ca46899ada15f0f31c7cb7c1a18934cece7bc3da13a97f3d05c2242cf182e5da18e56c6ae9c226ba76f8eaa731ebbb7b9133867fed748f2903
99	1	200	\\xd3c0217a339cc411056229932fac541a8b759e3bdd2b68e5feef058b2cfa48da9c8cca69a6ba4cad9ac3931e3f47cfbb5a7348937c7d08bb9fbf58f9a73eef09
100	1	218	\\x1faffac0a2507b01e35913580b9b5b25682c462c74208afcd02461b40c6d995316d701c7a915ccd845dbffbecc321b392b237bcaba692d0c0c44a3727300420b
101	1	56	\\xc0c196bb3abf500b76f45a60cc290739c7a881e9f34cedafc45726ab11710d68f6d86ca7dd253fdd2f0fe9a44734638432833c528d5df80803fbb99e6cec1f07
102	1	32	\\x06034eee5ad8c563e4f3f953324060b61fa66028ede30bfc8afcb2444adbd0f317488fd81da4ea089ea6062404491acac90bba7da965d1b1d82fdf9e9ef5e909
103	1	387	\\xe42dd51783b810848d3d689c7f93e7df9a61992415b5993bb8c2a4e68b7a7d160427b026f16de9db2dc136afc77e2c7db989f01d6a8515f81661e56cadee7102
104	1	251	\\x6e20c9e58939e6bbaa4bb5284566a59cc01610eefd3d7b2225aed99bf5cc5f618e160b2000f9883ceb491498a2be53668e27b97d64065d380002717639cc9a07
105	1	223	\\x91a0271476976342af3c8effaff6394388c8c4e8245a796c22e1a4d7e39731c3c43c1f036a17cac8c5c878f74b38d5716f2e9f5d0b5873927d2ab418eb549205
106	1	79	\\xd82a9206d8c86c540b83ca3476f7df4bf172a63aa6f7eb85478f56a7a7e78b599f77d4d39a86a4f62b682ad9404e34ee3bf1468fb1fce160be290a693d75260e
107	1	73	\\xc9484d58008a1cb3974032160bef9366a619282015c2bba3a1501ebfc968b8533d5111e97adafa520ae0eac67a38635ab924df216421f32c2169dbf04708d30b
108	1	281	\\x70e2ef3a838066fd680d63d3eaa8176460d4cc148261e0391603e3fb87c438785efd00434914ee661e1fae0ae35bbc1f69e0b662e98bb9da6bcf81f121a0b70f
109	1	52	\\xf3885e0593dfa8c0f7f2f2e1cc6ee3ef5d73dfe09d1c28c8030df11d08db54d4b758cd89b8719b084144b971ced596cecf526bf63b5c6abdb55f638db3c55a0b
110	1	380	\\x4c77624185d8f11ed51d4d63fcd876fe4c9945780b5fc7ace29e3319c346ca9021ef4c472f8c32d52fa2a83a406ffae8c634d83bdd587ab5ba94a3dd52aba100
111	1	37	\\xef8fff51d4c0b3ca92c2cfecc9a6041aaed585bcff8620b1dfe03afa9de9a129acb24d83816ef45e923430cd61229d213aac1f3aaec916184e8ff37acb76170b
112	1	149	\\x52d79f66e9d477cc494e3c190b35379b32e497afc2a9d6963e76f6e78a5b63e091f404e1f4752b25cd871af7fb82f8e07a830262d2ad79278ad52e5bb7384007
113	1	101	\\x2bfb939db83cd9a5b941ab959865d66e303e923ac4b2d5f1a81108e11e47fe1183b7f0b29c4a8783dbfcfb97fd1bb8575ff7834784bb786e5af257bce337a40d
114	1	89	\\x4521fa103c3edb16ede304380caa92f3158329c158e0cc76fa4a4a7a02339437675f66773266998d2ed0794ec232b3cc89b3dcbbe7dbef52b4d708f991961107
115	1	297	\\x95bc693f340d8af1504b2a0ab5fcf65263c9f4bdb06e30a6e32cef7b64c755667b367ce9a3d7f63afc264f98c69ff3b77501539e7bde2561558b751caa8be80c
116	1	48	\\xedf78b2accb3fe23e514f410823378c72f623fb7121a099ae67cd99e7e2e93382e7d380d82bb8bca05bd209e7338121a56350280a8f6d3e351898d4e591e4b0f
117	1	345	\\x7d019417a254a1b6edbe1c9bf738c67d573bff2f88ac10187956a45b6fa300e5b3bca8539f68f2bc67c526e83c5e3154627518e3f6535d8a449acb944d7a250e
118	1	88	\\x16be6d7a35f5a61ce82a9d3e570fb62e0e5c41842393f6ea022b36a6985a8853e4d93a7feaa2d5b5cdaaab367a3b4eb5a7e95ad2f7370495fe513ecfc6b5e90a
119	1	141	\\xb7334970aba54a4184c08f6facf25c1a13ffd1eebab855f1fa63d08c75ad72190613fdefd207ddf01fe1ec5ad4986e7dc91190062c30671d3fa165e4557c450a
120	1	171	\\x2d8c18edbc117ac2ae3795238a958332fb119e41bedeb830653d984cd9028b6adeb86cb9d3f843d53d5176c79e492b1e8addbe8a9a3cdd728ed87d74d854f203
121	1	354	\\x429aed4bfba1c99b5214f616076e3a2199f098644c5b2c55d0f7b07a205d0fc1f99c9dee42c783a9468904d6f8298258596669b00e5e8021dfa792682859d90d
122	1	35	\\xa6c27b91f565a07869598d5ab9514e0de089ea3e7f6553cc86cd9590c1e5d7cdd9ffc008dc498d8925179074ba39e6395745d8909361526b8a630554307c5f02
123	1	15	\\x49899c74832bab18c8fc0af0e3ed14d4ed63c4c8dbc97e93ba538eadad06208ed3a7b593f3849af4144c9a8303bd3134d9b878c1913e6c16e4519c5ed7707208
124	1	33	\\x65a9baf34d7a6f37cd9a232512e2e901622aacc094698228d97a7f0e16b7b30c8a5be5d913ade4d30c9afa3cb93360372846bf57dc5b6bf69bde5a0e9611260a
125	1	210	\\x849210152453373a13ce21b520b4d28acd49e90b37cc68883be97e9b153adc0cb23da137f5b9679f52dd5b5da48c476639c248af0cb768dd60a58b35d855870d
126	1	385	\\x7bf13c37714009184feade58552d4ca5d78f347d0a86b9de9db86a9d3b8d646b1cb3046659b85bfa8268f561a7ec31d9a68c0fa7a49c74d088035df142ff220f
127	1	371	\\xe41c0c4007953df5ede7ba751e42d5a9ad6555d7b7eaba48b76a7da4866cc9d2389176e2829176f879e35057958eaa9e5db89caf71fba862059f416602fe6d09
128	1	407	\\x6229bce7c96920c68ec7828f6d920cc863af9e72b6aa9a17f9e089592de15061ba984559953f0a6021839f3ba05962c2deef6a73c711c747fd2821a976fa4f03
129	1	276	\\xf94647223ae8d0b44c6a89dabd080287abcdc9091a008ee64dade8df19e94bb5371332e4f0b116c7df5be3d21f812fc4cdadd9d99e1c25e2cc306c5e2718a405
130	1	352	\\x9f16cf3c4b5eab19f7e720a17a2410c096f7a88d3338541c1c1c9fa8df6e82066e32d7af523aaf74edb920b904370893b2173ef1aa02171e3c033edc50f2810d
131	1	176	\\x2ac118cf608cea97e53eab697169a8cba1f5fa636575c42880878b0c288806d35b6607625904cae37967f1f28592c37c30e48d352a4af8c70f409a59fcef3300
132	1	105	\\x9ca9e72116e2ae15dbd307c47d5e94e94f9fdd972d32890e9653f59dda8875ee22e57004651cf77eba35e85c23b157d6489fce4f36816e907ced00687056fb08
133	1	303	\\x8b29cde6e08decf5f2501a9fcae42f92b084b3ce76aa27b19a2665f970173861a8c563e37a9c7b79a289c5f0223d3acb87ac42c0c5e81f77867968925de9340e
134	1	6	\\x65ea948942e519a0df13e9251d4aab4dbfe79d640af26529eafc685ca2f1fc5bd640be11003ba83484ed2085da1c2628cd3a15994a38ab5ad83201b567a65000
135	1	167	\\x26e3f92b9202c70883aaa6dd1d46e9cf3062814253c6371c437d636811c5e255e8b5cae5129d506fa4fa1ecaaa38e00bdd3e749df9bd03928eff29a9c6b6ff0c
136	1	109	\\x270b6f32cdf55024ba2f35c0b9ade2f451ec1ac2fbc7248ae15e12e95728d4bcd2c74acc31d1a5f278eac3fd4801305156c843abe31103b4f0baeec9d5fe620c
137	1	271	\\x65680c352ce2904eddb5c5634710e051dfb1f1a93f1ec1701905e941cccbca59e929425408f4d0f6f0f9edf40e973019afd1c3c1d7b2c61fb6b783db01cdeb04
138	1	272	\\x11d01d09c4cca3e64c0ca8b0a17d5f517c2028a7d2ea0f6e23f5457a0dec3e35c1a8a9df7613bcd23810f6988bc22400c935c0e295b5686004294070968eeb0e
139	1	162	\\x329bc835de3cd5600f9c113c112911ce4c43dbf20ef0a4fb8ba9710edc56f6cd595bdb3fa20a48a89a1ef518b5c02bc40f45f646a4df53ac266a61b5d5385601
140	1	313	\\x3985958d4a39856386411e3b071b3b7f5e32af811a9741415ccb6b4be262feb497b29320882d109f4bf37e355d5ec2c9a57016c9abc14bce234a65b68033920f
141	1	384	\\xfbc7da78c04086834ac5bc4bc4ccbac86cc34eb58ef1d60d8e93da2b2b5eb0e25a254af7c3894694256bb8ce3bb5fcaebeb2c1cdbfda8de892249524bbc45f06
142	1	125	\\xb94c51c6f14b8be2ff854812318c5baf9838192f5179c824ba2de2047a1c5dd6a77453291650eb1165aa3518683032510d079c68b55f158e25e7d3138517910c
143	1	306	\\x1aaff9ee8d108da88484ed0ccf7f9e4872a0feaacbcbd6d25d67b4f108091e2a6c30583f7557f04392a8f93b1702c2021cf43fd7e3af602baf64afbf3cf5ca04
144	1	120	\\xcd8ef82b8715f03b69ee00e5e5b8080d55cea0080443e5d6b84f03f28c336c76cec53d7c5f869b6ab990016c14359fb5bc14c698d736d48d7603716a2a8fb10b
145	1	292	\\x9f0f222d95e23f0962b185d1a8378432c260176bfd34a037fc85dcd530f1a26d0d0bc135b9cef705af30c87a52236b2503cf962d632dbe05dfc7478d2bbfff09
146	1	192	\\x8aabbabb69b72de2430e11619beab2e7df4d475d7ea976dcfbd180364ee127e74c444a057287f215e7f2cce26300188d1aa18605437e74b9866718eb2ca6b20e
147	1	164	\\xe0bdef818c9822a7e5435f265c6c58db63edb234abaa110071298d610b4b354b157c1c5234804b424dc4590fb0467a6f38c5d236f7fbca0672f21bd951599f0f
148	1	1	\\x36773fb488ca2d25883b9fbf0a79556b456949add0174f936105756d649faae6ab0bb924eb287e79da7816ebba2030e0a2d80ef24bc9a791c90b993c4538120c
149	1	142	\\xf901059d301a118a58db838d1edd4f063310a99e6be151b952f432b709de8e565304ad3ce7a9f734a5f097f9b8d9af8e35ead7031f6324f25eff32ba823d900c
150	1	386	\\xf1893c12066a5d924af5a02017b259335af98ab5745f2200cfd169e160be3b26b1345ae181b621fc185b34d9f1e3358afed5a4dcef6d3f3e09ac7aab81eaca04
151	1	226	\\xeab51f18d997253f68707de48618802be33cbf1a8d6e98b4e77478d97bbba2b40450a0e326f866ce2c7db304ed672043f9c58cb8fcead5f1ce9ec685d8f2fc01
152	1	199	\\xf5ba271c0b0533a5a1159b4040fc4e50e6eaef2c80dca53a3045ac292ebda70e449c9f5da1d804b234de3888fee31d2502d802ceedb8a208a9516c8c4f9f5400
153	1	414	\\xca5c5373a80ca579856e95e0092c46b837f52b189b7f18b2f7a95b31b365544ec6771c6472db30767c748c0f837a8379b0fce2d3a2950b5d2bff7fc1ede1cf08
154	1	219	\\x2a8ae30bfe6ffa1dd849870e231fc3a183be8551be32f65b51b16788e6a0ad9c3d1ab09d3c9f0827bb26decb2ddf8e361fda701561266cbeae29846da3aef401
155	1	388	\\xa631afa951b1be65df8b0709bc969f8ce8e44f1910bbd337ef4af2029ad295f65f5943c309bb332bab6ef890048fd1ebc0d8e640a5ef413db1de88fcc273f60d
156	1	325	\\xaed44ebc360e42b845f85cc97e0b3388a7fc62accf470162bc51e2544889238e02a616bfa24cb71edc2eea0ae2c7caefc910d4a48500008d71e7a05462f58200
157	1	85	\\x8168e8f174e41753d5d68e5198a4604f6a66ca063090dcbeee3d4de083c6a9f74894f3f196f0b3446e021108fce7ef41598afc55bd6ad08b81dc492d92fe070c
158	1	237	\\x7c50886e8833466efad41e98282715c0ebe49914fad9d081a27ed6e79098cecc828cb230f1c7c6ca7d12f9b2a0058d26ecc65c006a18f5ab92900d7a6d68cb0a
159	1	301	\\xa73c33da3c46dd49aea7bcc65740e4247175fcd8ef9d622fbe305fc59b267add5e8bb830c2f7e241457f5642b4e5f17473b6f1dd0b803dc3a3b453f3e150d908
160	1	54	\\x6a3f52df15db92159f0b8325c6e1216bda016164148f0c7e701e5e71cb6acb722c5be72a74ae11de21430fb313d30b24a9b8cae7c97fefbf5ef1af7ffab11304
161	1	379	\\x06965db6ebd5193018c24a464c7f8a34fd07e2cccb6aa7765193a8ef9f40a01c6ba790259df1300b33df78d10d171a27f0b0fdf6bc0a41758f3da4064c41fb09
162	1	46	\\x86c4a9282c9201c2501820a17b1b3af15ec52f052ba4473e6946eae54c8fc881203a6db73ce17933cf9bd903aabd00249a30b49057db6a833fd4104012c8d207
163	1	14	\\x01a7865a6b1b8fee12308f117f5d856727c8c41e7c62e9357b2e05eaea99fd0dd95f01229888394d29292d3b44764261ff5ed81351660a4c6c5080e45f829f0b
164	1	216	\\xefd8fb3d37ce9f6963b8fae014ab130b395f1357735ab1df349401978bf575368ede061ded845206579fdc659b46b122d0cdfa65fa886b6eaa5a25f08c441e08
165	1	362	\\x6399f26c46e726462c1cca3f2d7abbab3b25476102b3b4170db0b1f4c2df22ab7bad3f07cf33107e58ddf37515d42150eaba24920ff35161d006393a292e8706
166	1	178	\\xd75f6aa5ae79c7a6c40d59430db379cad645fbe88954c1f6a0054c791b9e99c7333fa725350b23d9d335037ac262abd8e01045db0960655896f03f38c08f180b
167	1	145	\\x387ab5a3d793ed578cd2d9cbfed52debdd02731dd710695ee270ec566db5299c7129e4e2b86be7c622df3378c0572d55152a1c9174e573c37484a667048bbc0f
168	1	194	\\x87032a7ccf954e08b5ecf747ce2a072ca1358c2d1013896c969b964700ab3d2f13681a03882e4a69e1d3562deccbacf8c2add70008da8a8ec2ebe52d9f4e8701
169	1	228	\\x102e7ab28ecd2fed98a8d07154662189b331151ba635452a13a566e8a5c216d25a6ffd0f11b864bfda6412a950c4654f7a1a6895d272640cd97291abdd94be06
170	1	331	\\xbb3f6447d905c8f870a363762082d7544083377b166cc816a1b3d26645782d255ffba4718846dc4a3ef3a7825b66ed92613c046afd98d222ca376bde5ad1e60e
171	1	300	\\x11934e5bfa4960908f3e04d5b42eddf6978ad3f1901101e07848d39451327afe743c1a85e835b76f6ec49a02b200f180a150295300db6cc142e3177c90255e08
172	1	410	\\xe33be639d309f325333b51c2a3f09cafec17a55b7bb57f02b3eea4480c8ef43aa4d076ed09571a4738f7a20ffb4f2733298074b40b4695d3ca64bcd089517102
173	1	419	\\x58917b5e6c783dc4268d9f435a5ab53971fbe0106ae9da579eac0ec05eb6b22b7e85e76d04fc45b17400b03388c1e203dd5b6752118561a5e1423fa77828fe05
174	1	128	\\x8e05009abe82d516000e35a2d563665588d813f09acbc876db8467b6f3cde46dcb944b1fcbf0c2e3e93937eaf3f205302e45765b5b2185ded96a546bf86d1b01
175	1	238	\\x7f3429fb730d35d336ca57ebfaaa278eb00ed201217f59dbf136b72d607eed3ec7340a78a36b472c88b0ea906654cec0d17b94b6b12bd76d0543506dbd1e0601
176	1	413	\\xbfd8628f8eb6f46799b506973bea017d6a83264b801737cde98dedd3e02aacb8178f98674f2df5c2ff147726583b3a97c52b5a25b91573b3c5a802550b3f590f
177	1	195	\\x35e5fa35392910f5e169ac1f66365b217bb5f9b85252fb30dc41db2418229e0dea36824dbf2854dd50e8300432aba88f489f4de5576348102037b3ef2d61d80c
178	1	232	\\xd849813e11399e18655df53f1574adeeafaff028374157398affc3ffbbe43a6a6815090f8d39ecfa762c24cfe5c1186ad3ac6c0fe2b407dbccfa54495346f805
179	1	124	\\xa6f57512c29010d16f31e7d5ff457e7959aab5017d7f84394def23137eda9a973fa299b0d6b2839c8240ca4daf30988ff72bdf433b2710147eb4d0e1dd85c10a
180	1	225	\\x95777b0d7bce44b5d8940d559bc58531b02313056091701b33824694786d5ed384f80ada32a910acd7e93d22394d552bc73ac2701dd85d6b1ce77cc78cd75808
181	1	254	\\xd6de33c1e17c93055eefc84e4a81adb6508142c841646b5f6ef69061acc44d34c1171e7eacbc61d9db5315b376f0afc12a2d198e7b4b88e0192a5e3a2ed14407
182	1	160	\\x2de4d3de08a38b07537d3c7370cbd240e5b4412b140463a2c59bc452e9e08200b71cf5bc92c4d2b60afcc9be872c61684cd5364edb1ac3aa2006995bf9d51f07
183	1	190	\\xa6d5931118f2b448fbe58c817e4fb86bfa5c5cb622ea03c07d1dda7bef13e2780e3d3f6ef230d541ff3a486b777184d1fd712a6716d6cdc5d120d73b26a29909
184	1	91	\\x607a4e8771a9968be8ae801d807b135d30b7693c8cb8fb1dfc701d84f04a40bb2bec39f02996a3ad7c3e881f550c099a6bd88e439314a664191c21ee1b583705
185	1	151	\\x1836924b754dc3fd68869eb64afef55d9ce8e89c1637b62cb304a7df499cef73172e1c5110fa1fa4392936fe8db5f299795fb45704717dda6d1a188cd945ae08
186	1	181	\\x887613a504b354dabf4f7620eef2d669b2914faf05ae4b82717ecac9b963cbfd3465a17795c0de40440f7e7fc8aee48d5c15fb909134b3bebbafb1f7d199c200
187	1	288	\\x3647e30533688038338e62ec30855cf311d9924f649bf62d27a38631fdaede964932a77643aa8e1a570911025e44228ee79525fb73062ee6fddc96d0c1bd4504
188	1	335	\\x56c2c2620d32002afd2874bac592a5eba68215c4c9768566a23bcf7db1983bc78136f1197173c8c4d2ed52045c738df6bc1d84f8b7fd86ef39e71f8f2026440e
189	1	75	\\x448f02de67c469fd2a253e4302f68e693fb02f0d56ad73b758af090b72713ad79a7ca3855a8a1ebd4999f25d82265caa7be3021e61727ed5e21b44a828b0be0d
190	1	17	\\x6199f696e7fe35577ef48e27d375ca14381067d14a76c23738fbc3725bdaf94504382d2bee2e49e9f84bb91bdcb50ff1e1800e9b3a4478c7b46d7488d8925e0f
191	1	412	\\x4fbff46fff6a98ff1c4b1097ad59cb998d59cb5430eb7c98184bfc1ddba2a05f1991287c7efc73e4366ecf7b991f0a0028528934db71cf566a3a48ab05413b00
192	1	332	\\x5197bb6e79ff7fa32d230b9670470090f87f247723e2caa90ea0ab3c7a25bcc52b884be53d2acee5f059ed1d9293740c7071fcd8cd538921bede78f43cfd1c0e
193	1	136	\\x8852717a17c4a12430da4c4c33768a781983ad40f5d9ca9442a21ee5b27209ebb8663469231bb008db5cf97fa996331fa0d1bede82fe1d5ad99d8512df877100
194	1	12	\\xeaa1aa15bf970fbb46f4fb9dccc105349db22295807e534b11a1f979d9c52bf80b6dc94c302142cceab82928ff6130966a90efd76e54d29ab14bc67567cf7b01
195	1	227	\\x92576c96c53ff49ad582079fae9c06bb3d954b051da7894254c557edd49a9ec73d3321970cb55e475eb6cb6d1e6475af7e4539baefed37634e50d72b51d60709
196	1	231	\\x39b450b2e73d6d29bae9c85b76f303526cfedfbbbec006075a85a99593a913d5bdbc6868ea4d5dc498660c2d532a9f4d3846fbe686ee1742fb45836a55af0a0d
197	1	207	\\x2f98eb963de6a313499f1dc0f73b0cf2ac6f845350497b6e183ff27f3fc3cab9e06630e35f26c5d3507cc3daebff9167da7b377707a922a85dc218923cf54605
198	1	365	\\x9b2b9652a8f6f8c5784e97dcb428d61ec0ecfcbd8fa6acdea18a2b9b79a03b6a1a2c67db0bbe80f17b1d7e7fe7b2b235debe7f171de09e18d2ee6de6d865c60f
199	1	182	\\x923205ffcb12539ba1cd4cd2295f2ea67704395179d8930245458f64a1e3328cd60c199b29c35e33d125ebe79b71c5df9b324686d8b34e54004206b7f9904508
200	1	92	\\x75fef4f1b1049b2932b096b25596e123f7d80eddce01e85dc1f4eb589df92462dd4f95b9b81fb52b2ebb7a7b9ea655f4cbdaf0796e75e05ea0d4f85fffa11803
201	1	423	\\x229bbcd65e7fa622e459109d9b238b8740fd7d9acd00722d8955e6ff47443eca738943e1052f812556976ce226122bd867cdcc815f2e40f2877285da1f28e90d
202	1	135	\\x374aaa71d750390567e3ba949c8c054eb7aea97ab8c263df8277bb49e89121101eff01f2484b4c1109c99b7204dff5b5f91a145018878063d3c8b58d9b76ce0a
203	1	282	\\xff9e384e067850e4c34c331340cffb56c59c87d6a509a6d4d8bcb6d66ae47a8e0d699b620663751969340c04c0f01007c222a95dcbd90ea643c14e01f59b7c01
204	1	347	\\xb4ae33008470ccb39cf15dc6e4e15c748e0e10f2a5e2a05150ebf7e3b80def7dc472b6dac5b846b9500deab972c50290263093abf83b1102d9714aef1fb36e04
205	1	104	\\xca4ded15cce636a14697fd077511f95e77e7e8c4cffecc723f0dbbbf7ac54cbeb0cd690028efb43166d31982be7ade89765a9524e26302affe7ef720d6ff460a
206	1	157	\\x389ec0a635e1aba7da626be286126979220d1256ad9f8b9557d91f1f5fb2ab038f854945de265ca56c561fe163b8f2ff37721079ada36203bffeeaab5c04ce08
207	1	197	\\xe2dd27cc4fc71e4da586407eb8220632ec92780b153417f9b1ee493aa2c59660d90af861eec395726446c34697040aad37a7da6b5e932636c839f7cb8d16f103
208	1	78	\\x1736894b80f0ffd1e3cacc5fbf5ae04b169c6b24159dd75d9d47f3d14ba9c0cb387a89f2c98b763452f2e6eb7494e5d562724c7b171827f5024c92130c8f6e07
209	1	361	\\xc247db66e9f061682dfe18d89f72c59beab70fad7c5978517d882b454ff35e9ab8a41c106b852d3e2a4f80172412f69c3bcb6260dc15edf792434102e7914b05
210	1	143	\\x01b234fa64615180163d5c98e66a647bc68b3675977b043037f0b4d92eec3c5d163e3c68ee524483ea4852a170fab95a8dae4d6da51a111f0241b43d37752905
211	1	312	\\xc5c88d1324242d9b1283dc6964c005148ae60c6861fea3fcd9e128442faa8813064a777a6637af49a851120c1a9dccefee4468c88b94c2c10955dd660e12ba0a
212	1	16	\\x3d637a692aa81f6f5327cadb7b0b20e58b20eed293422f88974c368dc21113df723f137bfaae89d375fa7d57e44e560816fa0010c57069be65c792aa6e357603
213	1	247	\\x10c82ec63fbf6d598f632da310d2fb087406edf67a33f91b38cddcff6f2f8c5bf48be62515074cc9c791b13ac59402bcd37d003f5e3458eb1f432425d111280b
214	1	127	\\x3298f34788ec43679405736ede9aa9d0df6e1131a29765ec90980b263a5efd2e7da42840507344274faf412045488a8571cf0ffd693f1c8610474632efed2900
215	1	123	\\x9863e2c5eb07a0cdbb14e0a1f0ef81e6c7e47614dba724c090155d06795f10551aae44ea331596100a2bc255016bd2957e54c635be03418421b27438c07c650d
216	1	41	\\x5104e3b3c6d98a79fb279d425d3f3bc648477bbd0b12fbad1cbfbe8e8f27abfd8af36baa70cf7cf2d32f0288dafac5e1aa38ecbc1615e2f1ef7e99d48f5f3106
217	1	121	\\xcc6b1c5f79a3d9bfaaa0007bbc48b9806d65ef009eb6c7213196c0297eadcaec31f7cb0b07b412e3cb4e5833d0fbd6a7f027ddfe93deea2abd2e8d1b780e280d
218	1	316	\\x90d68a2bef1c4ff2a6f965db00f328212324db3f194a97f51d0cbd8b615b43b46ccf88217cccdfeba0b839239f63ba51edb2b0ea89b6941c445b7db7f66abf04
219	1	369	\\x2d14da0d68500536fe47818c0524185b076f3104ef1711219540e79a2e727fd196de17e9f724666560337dac8aca1e7f4a85601f21c639e5fe76b86bc1344801
220	1	321	\\x8727f7092563f693f57461b594acec139be68d7fbfd36bbd0df0e83cd5a70a47c133c044f024908f44e2fb827717fe13eb35092b7f628f5993b6fcef7baa9e0a
221	1	27	\\x7f6c28599a7b9f340f60c62adb693fc473d6efb7f732470124d6912c81307ddf44f36a5cb78c9fd34482aa26e99c54800c64699fc9041e670055da917a172900
222	1	269	\\xa7769df6280555acd06fcd2df184a906837155819e032c4f1d972a9b98e346d9f76c6317d3f7e2435f40ad87125b2c3809560ba10cf7a7343d64a15fa7c5af03
223	1	193	\\x059d470bc32450264776db9d932a92aecb44651cd17fa39f952de4b4359832c8c47f2fc194040baa0cf0947714e295d7da68b3494c57c7514adac3050846d609
224	1	76	\\x7dc2a1380b048cf532a2e2fbc79962dafe6c2815c457864793a9dcdc4f9901008f4016ecdbb4118da5feefd901482e729ba742f20b054cbd1de7f7f55d18330e
225	1	204	\\xb348ac57daece5e967304c5577d321d5457c68f5dc51feef8d25f12c662b1fe85a0c7ddcba4f4d2ac2d2f35204ccba9e529f331a9adf64e7c7dd940551785a05
226	1	241	\\x6b3d6d31140aa2a1919e25e3de29c4cbbf35dd3edb033b6333668468971812a36870d2dd2fc8c0c9fce988704ad3c01d0265129d47b8804459a5bf034b792a08
227	1	267	\\x214d1239806f87440ffe7541200cfdf4986e50d71466da2c5eaa3fb857b4711ec82a2505267ce5f404c236b112535a12355a4d3abf3ed6a2942eb7820471f301
228	1	356	\\xad7374147cf681d3201faa5e9d691a00632d0edc7ea49f9bb6d40fcaddb2065302023d8304a67d942df88f7ab7e4ee250fa2d7f31204910f29603e5b2f534503
229	1	285	\\xbc38d0d0557126f9f5b3889a027c31c84a5933c0fc89e9b15eb3e37081d3683b8c77b7c0b00973da2e1720049657e2cf0593de62faed508ccc7d0f729e7a9800
230	1	95	\\x524babcfa5515b632cc03e17eafbef39b7c9422746ac0fba122a6b06b42d9df3d51dd53f57f6d0908b08de5b874b843ff43440340a4300694f02e77a26884309
231	1	279	\\x4eec10b736a103a67cbe6aa143409c66a2adeab1147a625b6e17a6c04ab37d77d170f4b1433b80c9bb963320a1e8dec6dbd0e7d41d39585d7b21d49e4b01fb0a
232	1	280	\\x4eb4c6292802a35ed65f37c65df6ac237b4deff4a6d5dd73f3b5bab46dfe0433dd80f61a8b17bc5482a489923e74cd4ab4e108d6981516702c7a9c9f87c6bd05
233	1	230	\\xd0308420be34f180be507e59d503bf48de5fc4458b4061836694f1352de99812d0d2c662b25ca91a40623711655d9d5510536f427f079691d98f167e906cea09
234	1	64	\\x242077c11b182531878b0ca7f4876b68369cb80edc6a74553c5ecad06d20aea35ee10eb7c2c9c338e42008a5ce18165e34ed1cd5e630bc82f02d8f78c2e20c0f
235	1	116	\\x79ad4be123a0dda04a79eda92468039ee2ad2fddfed3b55f104b59a65c95fe96430449827f8e758882209578b4e75cbcbd33b9da67ae45d4ce606fa367c95c07
236	1	221	\\x15363582f96753f34f693a4ae081073b5e1817d5cfc0579cc88d4c52ae0244e2e046d018929df98127ace55a7dd0583710a811ae0832baa88c0272570622c90d
237	1	53	\\x7733ab9fe4f48ea2aa62e0bd96c5911acf59c033bb2e2f3a388769e2437740e0f2e3ab00d5c524f6e0cde947570a5749dde936e5710e6d6b932162c0a6b5780c
238	1	99	\\xb472d277beff66f20f98225e6f69348a2615abe1ca39246256463ead93658a9aa5ac561fe547b07de9ad6b572779eff3adabfbc22d29d593c2d7a3dff4611504
239	1	336	\\x154e25b9aa02b1ead61ef7b083912890404954213400fdb7fea62b3d21069997fe2bd6a5bdce9da903222334dd3582ee6c72e9505eaea441ddf751a1b3e9160b
240	1	255	\\xde210acf60df0dfdb4df122236be810506910fc8b011e54999811519f6a0b1b9705689755d74eb90c7a6af1904bbbd9e68726f885f4c046a42e7e8e91eb2730a
241	1	152	\\xce02c86f1964f2e189b5b4a4e664660ac9e1906fb5128a42226ec5b4f961aa06b77b2fd2259a5b5d53e26de74691d173f981f8861da737b4cf8e16f9656a0109
242	1	319	\\x9feefdfaa1a3d2be5c4a274c31ad2c6c97512dd2d35a1e4b52f4c801ae127f7c3fbf4e2c848d56e6e64152d822c05723cd09ad966c7145a68b90744f48162802
243	1	173	\\x95e08c9c723d05a7d29f44ea3d5b2c200362815114061e47e3b1f471254916a2551a08fdb535ac01ae6ab441cb7bea5c83f7cc7f1333672b2e0dc52252bd9402
244	1	366	\\x904349769fba366dd44ff719eace4b054df5457a06fce5c969160eae1fd4b82fd20ea0c247c18342c0f0bbacdd631d35bb676ed987e24d22961c6cc568d8410d
245	1	422	\\xe276fa0d33b8d3faf75cb267ed3e47db358a69fadbecc03b87343e1d3368a1f67cb55a03b2ea93f993f004840d41e6255818b037e7281df8d5523b98cc107702
246	1	201	\\xcfe9b679a2aabd63895c2d09eed7082000769c8c3c6ad9a1044b9b17767212a6ec15facc4f8127ad7dec9618a6dbe2704fe62e5a3ee3a1bad7def91049fb9706
247	1	107	\\x7686131692ad3666ba363e46ab7cb7c5eb9d9160d8cd60f3459fc485135673fabc7b15fac52673587555750b4758261eeeb280d50055edb0d28c977f5ed8b708
248	1	69	\\xcdc35f2a3656b1d037de254bcac9b398452089b5d9bf4d10b99c66a5edf5fdfd60a6be495fcf6f90a62042cc72f2cc8c0726e999dbd09aa20efbbb5fa5119f0e
249	1	334	\\x4e21e35e4e15902fb34455cb0efee1b997f4b2f09e0107394f379aed5bc8af08faf115d74d9522631bab97f368621d401d32b3a5bd0b9719c72029d8e49da303
250	1	80	\\x8cc3ec7dd6382297e718fd2f44531ba14262893011f61809042f34fff445c34159ab8030bfb9ac480852ce9ba89c8ff4a5904378a2a231a0767e615478448407
251	1	359	\\xc97e4eabaa46c182ac8fa5b247815438a82bdcf1bb20bf3b2673f74ab99e20f90aa77f0acedb434f014c248800030e8f2eb1d73c3ac4d8baab86d49def8b500b
252	1	367	\\xbcbf9e7222f699e04862d4e88912ff5f74fdd6c247ff92b8bf4d617186dc947b41d3b990f5cd42444a772212f0fc0b4fbac55d7ac46b14fb39de30e30b5e1400
253	1	424	\\xe198b35565e394a8e119cae2ca93fdeaf550bf6805abef3f357b746fa88fc9615f3e4aaa6c4dd65d91fd1737f8cb7e84c9b811843d3c406b7a4b3a1edd365d0a
254	1	43	\\xcd4acca36b6338f5cfeba4251f1559bdd58aada8d925c9593c08ce017b5375e71c41290a4e271cca76676b019cfc8b38c68f7083639d876c807f440f404de709
255	1	168	\\x08e6b8761e6b12052006b26cecf65f89b5bf09913d2c3a05207e8a696f1ce8f527cd9233eefa2387928ff8421dd95ba2e02404925de8b30e054e48d26b6aa207
256	1	403	\\x3ac4304764b2be71d5bdba24a4daa58353b41b02848da0b42a96a23019c236f0706dbe9b17d0a53dff82dcf9f4e5a6fbe6a558ff9a314c2de87eaf102f26980a
257	1	24	\\x7856ed755bcb88b009ce4a607de03e107d089754f169a7267a5cecfb8129e482128b2c5d2ded21446eaecc8f46c2b5e9a06a080ea439a5b0f58dae0a0b2e600d
258	1	263	\\xbe80f17472ca1c49b5313dfdfe25ce52e74bd12889172badfcdeec96603f7328e6964cfcf70f8dcb88e5d7aeb944e4dd7c6e902d263af2ceb66e4167c0667307
259	1	343	\\x105aba15ddd3a268af13237f3be0c8b362e4e059ff35c60dd6220df75b840a890a8fcfe78091a9b9be590f3324892eb2ee0942e4a8e01ec6de352121e8208e0a
260	1	57	\\x176eb6dfa655c41d429719d8127fdf611e869c276debe6a8bc321a5befd67a72908435cc57723351eba74ff2b37e42819322c55ae0ac3d3720daa7e86d45cf09
261	1	357	\\xa0de7f25864aaee74a491cf9fb360cd97bf5c76087f0efd00a35d65c09ebbe36c4299e9a933ec037d5ab4b39d2b6ae7888bdece9b53ac4c4c990f4c341b10107
262	1	144	\\xe6001101f8127d20265c3288e0ca0069ab4aedfd1febce9f780b65ee2449b09e3ad1c8551ea1a830d4f5fb948cf898c6d8cd7f9c4cbacc0b2ed0ca645e06580f
263	1	406	\\xf5864a7aa6c0d6c6d003241cfcfdac00a3d67bbeb98bb16dfeffcd0e7034e869fb773b297a3920752e34370fc487d2a5351c5dec0b015e9021cf75d24cddcb0c
264	1	376	\\xf493cbd6c7a7ad54f9fda59a00061727acca60d3157cc37d8039853b03ca627154507ca574c6b89e8c13a10bb05b46a5a455db31c534211539c5c17024f27503
265	1	233	\\x58f445d8192d2c1f675abe81c97db0dc4a3abe02187cfe83ea4fbfdbea5350d59046f94e48b7114a9d41667ae5e0293a4f7107d2db70eae421cedb02860db70e
266	1	134	\\x01b1c638282c1d2772bb3bdeab5ae992d2b242b390d0aefd162e4806e15788ba48df909b36ab2fe0b573f2cc435b8df13ced9dce785a614e4156852042f40000
267	1	308	\\xbebd21953518fadd6756cf7b83dd6145835aa78e7a310d0cf6178a8d3c5159ec3b28ac83fd2d510a14b0619291c69a71e8b14a48c42e5e150c98d3d644f7a80a
268	1	378	\\x38573ad74de6d01713e3212b3cba7573ba545ae70f4c621e473a7c8507b1421fc0d3b9f8fbfc1eff58f71d51cf1bc1a6954a089d8e4100f7ed34a9ff3d15a402
269	1	415	\\x3414626abb7ca7cfa3db566f810538fda4b4532b6d471c265b49bd6a177931640b1acfe75118c2d74bf587ad36203f066650e455534412072a18f66094e4dd06
270	1	395	\\x8e7362d3e499764c269409ecaa82b4c055b9e69d42bab76331bb19151829529eb59c9673d26c05d67cb717eca5620873bed98fda17d9da9435c4471e498ad407
271	1	214	\\x4dffe18c59b41cb4f658ffb7b3137914fbb1cc27a28a30a1aeac5ba1c9f679212b71e9fa4f075cad0f1a34f63ea4abd4b7164178b6e6a282baa5814c7c079108
272	1	161	\\xa353c00857d56d2f04d9abe36f0a8b7380f9f9e3a8dba1ce77d1cd61fa9a700bf9192025c4257afaeb149963f5596da33800c2e58d974d97f28833f9a6c69b00
273	1	382	\\xf240ecb81247ccc102fc9f4fdcc84b808e2cf8235c955457e85a4fb36d17d029ee2241aa70be2fb3ace196e9377c6e18f9ed3ccbede0994953f805d4a9c0b405
274	1	179	\\x56eb4417678a5522eec83533dceb245f998ee47b3c835ba88c3898447a1f6380488e1e1ebd2d966363dfbb10c41d146698f0ca21b272eb3c0fb9aa9bd7b68908
275	1	31	\\xeffb46af0a067da9c4711b9b17aed69907c27b15445d64743ad0673b28003578a7e1f200282113bff7d56f15d956129472b3f846445e48f64466f209f6b0e209
276	1	34	\\xa2b1ad91d72e45958a9e709293c36a4649c40d97fb3534e0d4e655120e87ab2ea25d05bac87a5ac3d93389c3343483d1868ce8ee24a7eb1e0a344223e6eff502
277	1	394	\\xd2650ed381d9f9653c7f7b5363e64aa4888ed444f4fb0828e23ae0521015644a0e9713846c0c2dfaf74852067fefbebe1ac8640a5f3ce1bcef23e1fe2f57830d
278	1	133	\\x92432e33f01dc4d170e14780aa0f6dc6b746c8356e1583cbd847bf40b7c8da0a547462754ee5b33522c4415715623c3998c44496efb4b68068a54360d9d08f00
279	1	375	\\x12a497f947edfb032f6f24d6051c9ab2a221dbce7159a4a03a5c89245f292f53ad98cebfc1c9c19ad0f550a25f58e7e548afff0f0316fce27d87836d34ec5207
280	1	397	\\x6f632509906a39bcc96a9725f15f006e78f2ba098a8d21eb7ffe65e3efe0be0b16c898049a985146b63ab23b5975ed4bb95c0c2dd1f00979fba5530374ba0c03
281	1	137	\\xffdfa9772f08fec4f69d145240fca1ef1633b2f4136a4e11e51fc52047402c744ba5ffcdf2cc913794d533f89c4e3ceafe1ffcde949940e4fea52805c23b2102
282	1	206	\\x9abf4003cd127601cf1a09a139c23fbae15a2bb3c1ad0a1fd8e93b3ade460f073b7ad723c1f0d86446be6a36b56399c91dc78d5af2c11db16505d19311286800
283	1	28	\\x8221b1ba2e072e68d5fa1d233417ee5b0da13b530a7a2cebaaef6ca1a70d8829544af9ce2484b7fd20840cdd5385f462820d67c35041bea654827b3a7f3a4504
284	1	60	\\xf71c599071de7b12b9f8697f409e7911699ca0be9346db693dfc475223100af5c8c21b88235cbce5252c27cd359d826b04987e923ad7d9e6ae6ceffd87f48900
285	1	84	\\xe53abb4ef3cc2bd636663141f639a1c24052e4de2455f8b25895b65e7a38fadf97d14b828364fd7f1c32d43f5f20b0b5a6e105dea62cfcec97a673062c45ea04
286	1	400	\\x305cdf010afe2e35cba57efdde13ae8fb2225e6f6da6259c2e359216a32de20f6955ef2bd6454dfc2998399d6ddb3567d9805e7ea0e82e7f9700a6e37b9c2e0d
287	1	130	\\xcf3cfb9eb9279ac27028c5c0b497e510b84a052abedc9575f26b207bd145aee99185a2a25a78c40c56d0d83e90e952fb15324833ff6b31ceb9697d393220be0d
288	1	296	\\x887ecfbbd759eacb90ab4f4959a8326d3d25dc58f75493421f1effd5f40ffe353e700cc12e67ed80fd8b6ee829982dd8a11a0fbdca4724feb8179176bf9dc80f
289	1	408	\\xc51de22f2aab456a25d1f298c358f9e1dd023a7d5957ae2ec071f25eb204f6ad8e3d26a68a2bc7ea1fa010b398f13084ff90868651395bd6be17290ee35c400a
290	1	65	\\x9ea74c2a46132e2ee1160755d0f8ad4e1269c32ef70ee216656f11e8000eeabc1e00bc0db0484083c28ccbd921c6dcbc078e070607ca5d43dbd4acb65846bf00
291	1	122	\\xaeb9ec52188cc24c88a19ea78b75a1354469901083fdf089a15bddc571393762a6953340080d6d1373b99cdf7b58eff2455a1149b1d5220b5946f7caabacca0a
292	1	146	\\x595615de62d7f2d77d611142868cb28a57cf8f27973390419f96b5a5b01d0589adeea2f7c4ccf5314ebd4251dc14fd064dee88d20f84e2849d9f186eea8c3d07
293	1	381	\\x7a6276d2ba67b3ed3d86439cac9a36f62a142037465ecec000de6789c4fe51d6b026aae5ab7195da0aed322963ba977b1c75a3aad9424592c242ab53ef67900e
294	1	393	\\x065a4e5b05702431e5059995c405cf924c73cc4b34faee1a1cf81d14a9509de693392761fa46840c5d54606ec097a2987e094cc7f200eb0b2f2b047478eab900
295	1	399	\\x912f27da130e0f75fc66fa97a103a73393bcaf339938659516f7863395d9864edbffd2e5e66004949f55ba4406477ba07c354beb1ae70a1db087b70245de120e
296	1	188	\\x1b4e5fcd3e5cc9acc6c9a0e33d19bdff946697a75f776ea0244c185e44a1c7229ac3d45a1d97199c65362f22b049ac00188c67bb7bac3d589dd35ae864363b01
297	1	11	\\xc7245d12c812b83a8ca9d6dc4aef55fb2ca5c3f9511c03bf1e543c83f09672db89468060806d26b232c19a325d143ed4b990287bfef05a85adb9a755c47d7901
298	1	260	\\x0384b822450fb52d47742e4aa931bd4eea7f4d9da2dc7916e68d25f34a5ec6df9b5643ab251d00e131dd1a1ea870c1a0881c47f446afa4d012660b730a675a0a
299	1	175	\\x7de8926f25fef4a30100c4bf311148bf1fbdf8c63b327bd5cfc674f7c3bd4ee7b12e6817198260a513e888dc47b773f0531616dcd4e552ea79ba8c9791b4bb0b
300	1	351	\\x8406fce9e2477e4144113800163af4d64e285f61b9a7c7a4b355c1d87bb6151bb1800ef0d1ead2ef7b32e872754072a0db364b4906d9ed6f109e2d6f52acec04
301	1	26	\\xe6d9698e9881549b90e2d784d3256520735cad2839d8216140c766e13a81885e40a7530a5d619b0b9a5a1a17f203a6b840e249a1b59fb9c01faeab9b41c9340d
302	1	396	\\x4d561647a882f1b40d7bfdc81a66345c5fa0b2e1de083ea262cc850fd6eeb8b2f3baea1f59ac64f937bd4ad7f6f3e49ad2a1d4ba85c932d5610d4bbe42c49106
303	1	13	\\x186c307540bc5b181e094cf81d597c39bd43957e6d58873d1f4f2c91c7c5d60d8bb5b2be67c08db56b3cc9c763d6a6a318ffc0593252a17ca86cd494c2a66200
304	1	235	\\x59c7872a3081e047f2b1a4f93dfca29c425580894f7826f05291fb246ac12c811e85f478fd0aa7e01d84dd8892d53c615e622053702ecff6c151cdd5b581e308
305	1	261	\\x9030c1ea20719fcff34ef58071c35d6b30ca2fdc2800effa06488475e3efffd947dc6730b48b913b811064d7e6762ce964c50801006df7af64e026de36085d03
306	1	344	\\x762a253412fb45a28e2ca1184141a8f9fa0515aa82d3835b784d136481f8d18c326809466cd727d512f4a21f71f77f8414cbf8e686a0da98101eeca5a8c6bc02
307	1	50	\\xa7834bf3039d857a5233fbdd847a881238d906baa14cfe2e0b86a582e2ce5f6a9d7acc29b66530f28b56a4cf229a6026e446549a0c4629a89048eabfbafdb40b
308	1	58	\\x1d22e6e196146ea32b894a5b4fcacbd49edc7376ab3dbc6cd7cd5596fab68c5dbb3fe439db5481f06e0c7b2dadb71bcde71b3af3642d02e7dad4fa6a46cb7f01
309	1	405	\\xa8a33361ab3c09760e7219ea4e67f1a739aa3e518a19a84657acea937103e9f87baaf47462df4b997973a45ea6b0a2832fe4ddc25fe8e07545a584087b39800c
310	1	363	\\x110de3d901f9ac257cafc8c6437cf724e352ceaa23f7046fa42e0039423b294d0e3d8546868ad195faf046f50c12d6a7bc6bcb17e04fbe5879679e224a8d330e
311	1	147	\\x6faa053438d845435125a871d5aa54a822a19eb701b57847f2b09fb298add0beb366eafcc6bcf4aa2fd9cc862ce4aec6e92d4d5ea921443e52cb7d7b309bef09
312	1	244	\\xb33a6be786ff4a6891c3999d54bc92c0df1a536c3685aa8f973ddf797d55bb1d5458e5024d1f188b5440efed00671de241d8f35065f913045ddaa7e083566506
313	1	302	\\xf2eff7dca12fa3f2bfaab39a03662e956e9e4a542beb00ff87280e2f9b6c4eda23548009cb8b6c7f9d48ed6f5f9a16461e8a79c3c58bf25033f23ebee784020d
314	1	258	\\x7ee46446b4295f1c8abb3b7e538204662a72341f124908f7d303dff022e5817c27a3fda0309bc3be795b3de8683c831080db85057724d94aa3391760c6d7110c
315	1	257	\\x35c08fbf7ff65d959c233295474f53554b3621e31df065c0a5e2be663d60621cdeb52e4f14caaf1219777c048a80edd1f5480b0a1546142a2c41211a7bede902
316	1	289	\\x87acb7c4e6f2804d06d15c8ec401dc96c929dbaceeff094102c053c3ea1ad8011ed120e886558f7912fea1230b208735b09dbd29a02899c790907ce798dde005
317	1	420	\\x335eaf80e7e04839da1776d2e7d68f875aab8cb22af79f1ff79c9dfe917cdc2651dbb5d9ca4e5e33b7dd6021383047bfc9c6e99abcdd7df74ccb592a75233200
318	1	315	\\xfedb560f8933d795659a74c5db2672eb36fd1487c29c34eacfd5ae306a58e3bcc1de5ed571d52ddca911379bb14c10df76b4c8f6c4b9426447949c9b64452108
319	1	349	\\x490ff21e525435972feb3da0c7fbb5f666cbfac6463fc98f96a7fe531b864dd6f28480b29cfcdc28464f18acde0eff85fb2327e3e416ef680d32ffab723ae10c
320	1	38	\\x45d4bc0874aa8e92fce2962f9de425ab0fd754b1f5b1b7e6109535893798a8c52c6203f1d58671261e17127d65baa92c84bdd430988f9d7d6164deed7142790c
321	1	353	\\x16380b11e7fe0f423dde15f3fdc9a9204f7138ef5e8a180bd1e9e389d75a9276cf1bf410edc4a045526a59342f63b9a7567c295435c49b1aa6c23d8fb83b2b02
322	1	81	\\x92775c04cfd8103d07633a091261a22e6a15ae3f79aa83962e0f69475eeb07960ac637bf49f294acfdc73e478c4cf2156f7d1604fb17d59a6c72d1c8cb78170f
323	1	307	\\xb3523666cf1bb97843df243f86e9c109b2a5e6013abe6c29bd16edda1eae2f01498730f1cc958b1ac0af290a63b039b026dda2893a9ff3f96fe0537bb941df07
324	1	174	\\x14613927d5b82697e6eb391fffa31f70f1eaaba95cf48b1134b6ab651a452fe8851999efc575383d5d3397e61d2f674e944810f6bdec9000e398584a10ec8506
325	1	202	\\x6a9821432d02cf768414f43aaa444f9c797f0e3eecc6f1c672d9bc21fdabc1bad89ba3580c9d41eaabdb6e3289cb67e310768691fb3d7e068537694e71911004
326	1	249	\\xca54751745c318448fffc3c62f4cd3cf2690efbc0c7f2870e99ea5e2dbc0129d9b2876fe5908a80b7c5246c491f9c9e56e4644ab309b9d7a2d2863e614353600
327	1	291	\\xa697922dd1bcc39bd7b2b91ec8a7ca4ff2f5e34d5bcc563fa830a7321363b7d78f5946fa69ee98678d71b5a1c0826539ab12138cc9875e1c041dec484b702f01
328	1	112	\\x145221afd3055e3cc2b92630b3c9a58d3c0473402b8989b2887f686f816adf20b318a6b32dcd2f8c3fd262c6191cea1ac3b9c9da50f1a21a5534f86339649403
329	1	169	\\x33c3a9c8a8ed23a41e1af2843246201f21b2a9297cbbe5fcf5b5a18aef974705151fe202579540853e359113920c7eab549c772248656c300954496a091d4904
330	1	170	\\x131b8df0db98eba4361b5a1c1aeacc4c77fcef0331e701f64160c346ed86db01ac393501c31788e02ec48c51c1192f5e2f3e26613fc4abb294d4cb52ae664908
331	1	299	\\x69d2a68715f28c33fca703951919c6454ea568e32f5e829a0334aeda803f153b2a7a36dec4f81021d98caffc03f53d6ec1c818512203309641dd8df80a81ee0c
332	1	340	\\x61045e7c35b9c73c8eb0844e3f42f37a670c69a7e18e6df5e8c30913a832f117f07f03ee9e22ac4f834fde919bcee1aa668dc88525dfe3bb0dcce4598a333d0f
333	1	198	\\x26d6fcfd430ace2a8f5557b8d674947c48d3b2892dbb9d110e5948b84e57f8f80f7711f350b8be29c68b2694ad93971a80242fbd145eb155c05771aaf728b708
334	1	87	\\x873f68729c65542027c677a37aad78daa4938530b512516dede97468182499b45217f212cecc27b901c97b50f8840df60487ec138128542a4b08bcb975f0be03
335	1	360	\\x9be8c3aaa79481f769e69fed2fedb7e617e00d865932b6b99e14b8845877f9ce97fa1808ddddab37bc4b8c67741db51ca6b16c5f8c70792cb4d80b41bae64204
336	1	129	\\x0232bd628b75b41962b40660362bd02bd679195db399a081fdb6f09dddb1f1f7d0db728cbc5d4d656954b12bf01fae35e49362798d52e39399d1e43a82376b02
337	1	348	\\x117ad16c97e22f84ca0767df15370f0f6092b328cbb31fba2936b52342e992a51312157faba6228f4e32269586e31de14e2b55c67241d09bc14948bb9db5b707
338	1	45	\\xb3a60e1c59247e5870f8f945c21c6b7bb339a0f1737019b174fafb7036aa5ef4bf7ed9d1a0b340ee867eda0fd58a076081180d1ceff91c64e6183624ec2b6d0d
339	1	97	\\xc3be6a962c42cc9d72b988ed15ebc92c5d6190b6aa11a00eb6c74d35cc6e1d5c40048a06ee6e9e07367d4cd33b573585bb7da3366ea41073ebd5da49cffff808
340	1	94	\\xf4845d31cfe04af93f6fecc0a52a079d77c0b0257b84509544f9fe6cb9e602c41d29bc6352a51cebe4edaa687efbce2a5921614d013977f06fbb754475e6e50c
341	1	25	\\xec55185088d8db901bcb2807c679ef98b57d50ac1bcf1ff60e874706900cff6aefbf57dc5f9763f794ba3d771e0e55a90cff6b64cf44ee8975172ebd3caf9108
342	1	23	\\x5d0087313888ddc55a945daf0f51c6e03761d010ba9ed3edb6b7212bb2913b000775f697c48cd250ed722eedfbeee9e833302c7a4bb6626f685d3a2009b9d70d
343	1	392	\\x1fe3292b5d3072da2586da5dc5f4265d9361db85010e7d3bf960d6cac576fe254120ba4635771c736df7fcefbd77c3a22fccc621ae639b3b5c092b511600ba08
344	1	191	\\x6e77a129190a0e8e271e07ddb49d06de40336e595eeb96ec23b121a370f82aaa8285407d3abc3c8c663ec228d5c8c929299abed029a1e03ca3c8c221e03fe40b
345	1	139	\\xa6250ff31bd87f73592f5160f75fd0775654edf8ce6f84cfec6a523c90f9020cbfcc3b2f890a908958b78c6123663dd341a6f5ece18dfdef51ae29d87a6dfc0c
346	1	389	\\xc39e05718859b98c9b9e6294fc5098bb6985ec11e13c3b266526ca218506e738aff21d397ef8fdc570251b0dce10b997fa36070898025def16df5eb3f7ccbe06
347	1	327	\\x21923b1ba95f0ba72579e311b19f9f92d51e36ddf76ccbf829f477fae856152b5bf26c4e33497c02a94e2466a7b06bd3ddfd55dc70382edb053ba26f62392f09
348	1	8	\\x7bf789ff6fdb62f2d15b26fcee19f79212f0b9697e70c229734acf125234919309c5687f4c93a4264854b0e2dc43bd5cc6cb4398812755b95398cce6bfcd960d
349	1	266	\\xdfad57cb2278eb798e84539b1e3ff1a4d7d3424887638b544c300d811c1c9e81e3cbfcaa1425cedd97f9bede876bb83dce5fcf15eeed9b7db01ce9aaf7412d0f
350	1	51	\\x4f385d054453e94bc0381023edccbeb4bea5fc7655449cb2b1892eff2ab9007868d113e3b11b9c56d9173a53af8e0a44271d68ecadba444e1a65c3fc62df0a05
351	1	67	\\x5f6571105b96b12e7e690634a5acdf0175311567942ce94ca789e8773fa9810454e2ba1d82da98acd9a1f72b8745329089154c2a80ac418293955d8678b7ba0a
352	1	284	\\xade01a63ef806e86f884b93c8d417251173c55c90456cec984e012711abc69b8c7120e9d3ee5a9f96c98ead6ec4c06372f4614dc65793867b73fbbe38f61770a
353	1	277	\\x9df8c08b3a180e906f7d5687c05f548c4ecabe4af7cb2e1a4f27c651dee3d3b822d6a53a806f4d4677d99d168aa1cfc37740156a8b13917908c3b1d5d3df1803
354	1	234	\\x03dd696451cfc92e44bfdd10d981df47a57db4b42b916339a8fb998a56031b2b943b789087b89a18e1b837ff86825b9e04d2cbe5bd830a4f1daaaa3d691ff500
355	1	391	\\xe96a6726f6a8148516542d46ecafd0c98c9ba30d562148cda84f47bd7b691b636e9b72d1f8e438b9d6f4f5e213f5d11849bb01f40f36e7f3f0506aa306440008
356	1	270	\\x8f7b05e6db1c8df77ff70bb2090523665543f52c71b0104f3a02e6aa24ea77ac8ec87793743bb50ba206724d82f83478759947b80e9368d702554f287045ae0d
357	1	102	\\x103e4f2d2e506b32d6327a5640808019b43cee27202a0f271544efc6914dc8d903f92da2a8670bbacccaa404071252eeb704d9ad15182e8354986e7767c60105
358	1	326	\\x19357ec4d63458d990fe935ab886b3ee718e4cc014bb62be664e6dedc494bdb3b227b7f4d6e66b32e35c06b22f29957a43021f28d27ec18dff2cf9119a01f80a
359	1	150	\\x1453633a579c627371611f3d72cc94a9480f1998f587a150c1f5fc8bf563275518b0ff4ce8f3b7701024b394a7f99244ef7a9ad08b50b96e613333980909300b
360	1	9	\\x29c9cf8383d4806b27464f116458fca2f471af011b7462b9e0208a82dd666206fdea9a9cd16d1c2d440793f12422ee14c1d196b4302558a68eafd7da7ebb5701
361	1	368	\\x24ab7ed8e93a8a3f73c0854f99b2ed5a9bc65f78df785e70e604e38f39ef6ed69939dd3477a7d76a1be79dc7fabf5dcc1be794e5fd7cd515717f8981da601703
362	1	274	\\xce82041767171138d682a934da90f1f8858129e9f4b709bd9105d6e353b7c232ca451bee2b03107fc37156bef419d0e4f68d4dc1ea2c4286cbc8b96f7cbe6b03
363	1	409	\\x8c8e183ff33833f0e3e60ca1de5ebd4b1de0d8649df4fc20601a436241496def450ff412aafd871c19854ad28d4404f2e7b7d9e0492cf3641015d1e30a1cce00
364	1	187	\\xa0a953b3f51ba89af803bdeb1522bb3396a8b57e413c5cb9d28297912364134f40d105801a7cd6cdc8e40f205a4941d0d9a85c5cdcd0a957de7d860cb674cc09
365	1	172	\\xb088494219d400f21a8007eaeb3531373a3749762a690bfd2e8d14c67e7ac0988a9bcf39154f66ac248ff2798c27808485c36afc3fa4584f4372328a5e7f4108
366	1	253	\\xe16458649197305dbbf70d4efd7addf41297b785708405a46ad82a3e4fa56c2b0b57b3fe823d1d410f432c2c7da682c309875e2f1da79400532ace702960300f
367	1	209	\\x4576a33145e95f461eaeae6244aaa5081193e06f2ae1d7431791ff49abe244e6d45a485be237dc8bd420fcfaf6458c882d859c3f0d7d0548abc16de8e964600f
368	1	7	\\x24de7a9d3b9e90829e4a4d5de976a472f13c944875e1f8c5bab105f44b986f54ca1785d082a2569e50952396a4dcca006c960ff049ab7e408b52e46d5d06520a
369	1	5	\\xee5f8354ca42ec15267dabef31a85578351e81d82813da224eaaab8551bd13337b5d095a1432fadab6e449b01bbad9329f8fe99b1c248be2c6830763fa0dc704
370	1	211	\\xafb8f1ff08569fd2176c128bf49281729e21c8e62412b412ab5d937c193fb33c62e16be5d4d1e2a0b48b68995a5235f5a24e03776946636096e9bc09144f7100
371	1	293	\\x1df67d887c8cb5bd3f6e74eef9ba922a3a0700993ecb22488b7729f51af4ba976fb23c39769cae320e82873ca350c3d96a4fefb5aa05f69c4db3c82a95e3ce0d
372	1	74	\\xd9fc955bc044f897baf3e17348409f92745ea50ba908baf1f1ba1c90ab0983d3fb080388a0b16003d7963ce4a26b9960a9ae2b1279f7d95e3c4074f291039f05
373	1	390	\\x41adaf64d4b3fb8c38488437e57ec9e1b118b3a2ff62d202c87c5b4621f5f456a70e0206cfaab53a4801995f83fbf783f0af37c7815f51f737fe6c69905d390b
374	1	342	\\x95064b175aae528dcca3137d763299fd5757678d7ddc91a7291d26d9627fb60ccfb1449886e3cd3de12aec55710d9972989d09155de8d68d71dcc93b62147104
375	1	318	\\x423b4d5ded60ae0111c5945b6b2b889d1132f14f50d41202405d2a715ed4045db11269be669a64a714b1175d36a9b15f65960767ff49975f7fef929092762d02
376	1	262	\\x690bdf04d013e3f2da9a808590283eb7672a62f3c59d1c82c7b2ffe0f755421a1fb7cd672a2c15f0e6074ca630cdb76c4432d65c33a4647f0d31bee8620bb20d
377	1	70	\\x0268c61c37515bb049b868069eefa2f1f88212522e98aa12f86dab68451bd5145b644f9e5c70d45ad68fd2e07ec129c8b389460b52d00108b069415f8e3ca90a
378	1	103	\\x67eafb4acd0933141c4a901ac4cd9d3f14d900f2288b0750ad699bb1dfa4692c6cd1927a24380b900273f29c049e252116877512e41f6daf752d21d3a72ac003
379	1	341	\\xa6f50ebb73ee8be185331b06e73c4c54eb93eea42d3774061cea5cc3c609b0e2bebdbe437d81a5faece9723daae58912b6db2b047a03ea8e2d4c97a0ffce7a00
380	1	196	\\x186e1cfa2a1254c639874dfa72de7afaf7dc3fb154cd8404cf7fd6853805c3b09a02bba28a2a787d5eb2e0519370eefc2c38d2735d756e371a5b796418366d01
381	1	323	\\x77af3b8f5380302cab60a6e3b0ac601a909bdcae36f918ee1b653b8332858bbdf0b2f6960e1b153a97f6a8799f4003dcd31acec7059a1c47323e86667302f80e
382	1	19	\\x3d1d60cf9291ab55a8ad6c7b298b056d7ca52a417032657e95cba48cb75c779c87aa0572a1a370d910e24eb35d212e99e510034ff7c485a75124229fea2fbf01
383	1	163	\\x185e5e9a0fc2d148e400ec79665bb75ddd0d19c56ec4da14db3d9fd22bb89b7bedcf521e6f7d2e0709ff92367f66c921d6f3e79ae0d6b6035d85355d6cca9004
384	1	63	\\x9b5ec9017f233babe2f5ae179e5547b72ace58e9a284bf710a1b239facf82dbdc5f990d7101687334a3c984b8645abe7eaf12c4c4bccd4295ee024c465c45a04
385	1	310	\\x65345523d749ec10d37dc45fc1174d295074de7fbd560260c3698ac3c881893210ae1943ef06b3c25014ed9a31141517f0204c9683d256eacb619b2f5bc4c30d
386	1	18	\\x77263985f9d8f036d8a4e70ea4d0a3e73131ca16a5add3e9d43b76089bb76ae25aa00431e11aeb15a9aa5b20015eb2e5ed67f793276258da985edaf78c6def0d
387	1	374	\\x2a59dc99cd220166bd0d96fadfe92eee38903cec867e7f659e975882ba15b779d388e990099767202d973b9b01725cb42e71edea6b0391129fbce9f9d0503b04
388	1	148	\\x1c7ae2febcb56f8f746a6a5a2590ea93dfe08f4dd30cfd6c5e8e59952b457147047cbf1d0ccb695d04b485d4e6ce3dcd322836a26d9df194b8ba4c827f51b904
389	1	246	\\xdb23f50df2772eee4bbcfd48f884ae2ccbb6e45bfce9161450ad0b8c10574d4133065b5aba4fdc63c4cef3b883a91cef0e34599ce7577862158bb02ec867f50b
390	1	90	\\xb5b9dacb1d5fe02a5a08991c537d322f2087fb4130c0a7ac90bb3a5b9049c044bb042d199502d9329c52d2222530d794f2f1790b2a5cbb781a2eeeb75c007606
391	1	304	\\xa45b61f22f71367d32caf3284cde98a0832ca0496a2c9fb78104f8fbeb2b0e8977a6dd2ea3bdc42f99b82bfbeb5ee0fe0e36ea4f637bacf07a8adfcf24d0060e
392	1	350	\\x161accb589af65efb72a765be7a7ff8f715eba880e0af39a65b9ea7c5a61eb09e30f89b2c70e84b85651a7d23e5d104cbac413e3421122bb3378979167551102
393	1	213	\\x6b48c13abdd318e4383a4d3649eca0b50241046c09d0c699984fb3b1dbb1e6096fd32c0203f9691e7372ca7bd91dbbf7fe8307d605efc8346f030bec7369d001
394	1	93	\\xfd99613329c79dbbb9a4ff71407d25a6066e51bf219636f368e8c727f4724e0ce34423ec2fcd6ab0ef501e77cd0c1f2c3ddede71866620d44272c73c7ceeab02
395	1	59	\\xd78380db853a6697cabcab192578f1be528a9a118f56869e15c50b1d9821f72564847af2b4fec843151d892a67a83d7ddc7dd2f52398995fe84eae99a61b0d09
396	1	298	\\xfad0ef973c69a62d1b1d266d1cf3a0c37fa0ce754afc21c1ece56006b81ec8e476fcfec10002439c34b77353ff85f2964b7f3d39f1a7f7edc24c3f5739386d00
397	1	330	\\x100db10c624267357d8c1f9096f408ce41911c4e61073c0097c90a17936f5a15b92086e6bef06a168d6c57094bae7b141695f9882eaa87ff1511d74616435505
398	1	110	\\xd6aa68363633ed5b15844620c770aab09087ad452019f5643d6dcda91aa98275dafe64c7cfc81a2ad8dfe26c98c1ece74023cfe7b9ff2eec4e7220bfaa566700
399	1	224	\\x53ab24d1ce7f38b889dfeccfb1def78bcc271aca0eec4c5a6911ac63d4adb50bc3292602cc23122c2ebd45b8fa645184bdd00ad90207bad22e22430ca3de5107
400	1	242	\\xa98bd32af853bf4d7291534f7343537a763f7ca2183f11b6163737bd858eb5abaa9f0d23fbb883e6ff6b23394ad0186d64bac559c12d8b838726c98e53ca310b
401	1	42	\\x30d5b06c60e2c1fd5f47d7b01470212129b3c244d10a06fb423f2e022f73a3ad95311b2212eda2b163c4704e7d032ac15b2c34eb90798201cd7a0b4b5187fa04
402	1	358	\\xeb42c924493983d3b3fb6df6224008663b4d6f87f45a2ed8e98827302e028357173a9b61dfb55e1b9ef16315ccf39732b87a9d61d0d669f6e9643ceccff23a06
403	1	264	\\x60db85c8a32f717e956ffccb9185e5bfb303178ecc848dea3a20feece5ba75b36d0203aa27c7421886d549b2cda76e3f0d1aa571b763ecd12b3ea3aaceb1a90b
404	1	55	\\xab95acfb5a493437a062489a5c2d580efc0cc618f4357adbd7574f9d2c52c408ee1ae0370fa0f7db5ac39f989dd7f9a5fbcd62c64cf73dd132cc79b589ae9505
405	1	22	\\xfa572329f58a5ec213be67d9ce3f332be4c868f42de6668c761df1ca2e5aff8e639010c0ac87d6b3903134dcbcaec3f05126b29550d9e1837b3bed8d8e7b5f0f
406	1	243	\\x350f95327f014f85b6b49605e4391751a417dab208f8f6a7fa8c9e817925fcde28df66bf42d3f5b071a026431e5eb18c8b9c0473c8cd49b0279edc9c9e762004
407	1	20	\\x78094d67a99e96ac5c1c282571509d33eec95bc2523703fcaea7751b0be6ca983b078b5efad2f2e81a43d2f0681ddcb30f5f39c2c86c5452703dc86ca9270b01
408	1	66	\\x7bb7058d30942e4b7c237debac8a50cbbc0817c328ec90d6d4495966de0291e95f31172728557cdf21518bd60f77d93b73f8a07333cd09bd8179440acc04dd03
409	1	305	\\x4b2c61d6c7f710042653767ee866af43860bcae4d2b0b748c2112f678ea154d00b2dfd7bcb76fbfdc3aa88c8310da4fae3e704584ec82a6c06d3abfc56fcf806
410	1	21	\\xf401fa93b05a34bca003ad74928a279bef3033b9f36656ce0fb1c5602257322ab4417bffa99d398b046233ec7c14da850c15cca9a2af450b055511a60c08fd02
411	1	108	\\x3f1fe6779ea23162886f539f64807e3ec38dc0d3d585a7d4996514d12ec58250d050512b03ab15bfaf44ccc84fbb1c19d2859661fbe64c30ca46f3acbffa780a
412	1	372	\\x89d876bbe19cb3664ef2e4fbe4ea5d88768e6e2d6e2f7dd7e2ec86ec59f7a4d6e381f6b0a15f240eadcd3466fc6d81a216c8ff176b98c8b6c38f21521a8b4102
413	1	229	\\x003681d32e1d44a69ca62acd06353ea524aa8d4be3be35291a36757dd1d0e439e05e22c1d19b4f3c56234cf8fe16dd7cbe36ca8e695d137459015300afead104
414	1	156	\\x519464a00e50b22c6c1f65c3bcba7522b11d18f33c60188535528a00c3ff9e05db9dabfaf8fd6792759b35e5367ec83f2b1b239f75e03a6fa8cb9b086a8e8206
415	1	220	\\x46fb47edf1bd08fb3c2dc4c9a3be0330ed18e5b7839749ade1b0c9655f836b7360e61ead21c6e538aee2f9b1f75d336a252d80631e7734027830ea18b6e47c05
416	1	153	\\xaa17869818a2ad81cd1e5cd43e4218fb2aa72fa54e2080763ed77e78297017dbacfd91b2cf13d61e716f3ed9aa15d6dff7b5d33dbd78de2c1b0b87e35b6a5800
417	1	77	\\x57fbe7e9c92a15b297d7bc6c2290ec71f6861023de91f07f54bc3c7d6d0288fd0d5f81a74ee0fb38f7653a09caccb86b1714a6f211d8060d8c88253fefade80a
418	1	265	\\x47abadc31c3b7dabf92e5984ca689501d78686882d71caf9c5d3ae452c0aee376cd276fb53452029ed74e3433f80465194a70bd9d7d0547888c6b7d24501550e
419	1	158	\\x4c6ac2f4c63d5dfd310ddec5c38cea59e1a922185e88d3ba55e3bbdf04166a74827109f8effc034c07fec052b9dd791289e253f5c8af0dccf5b4d042e1bdb50b
420	1	131	\\x3ffc7e0c4cac4e44584a95ff27e6275870510a5bb0ad725b37341ae70f51bd3befa69070c3b45f1eb7809bc4e7527f80438c6b9b0ef9f6f934458fbb93c44e01
421	1	185	\\xaea883ffe6a149c505f990e6d06c869384e880dc706d4c084ee7357290a4b54bf1da1c3be7ba3fdc752b189315a8de969cb27dead44965b955bf2e5d7a9bc10f
422	1	217	\\x80d5bbf18f53b4de73d26b017ca0c28575c72848bd1608eb736f21330d9de90fbe5be42a0c4eac93893d090cda79a92fd176f6ba3005b5e571e47c302e0cef0a
423	1	402	\\xff572d8bb1e5be43c7dd01e74e367348192ba6bd93307c5f5dbe57796a5e8a8a05743ad2a43d183b85b882bdb6b025adb489496fdc9c60ea92511fc212ceda01
424	1	115	\\x606d465fdf51edd8bcdb039a757407f3ea14de57b4c040de5a0c07569ce2ede03ceb9fe07e4d09b14f1e712df940c85ebb98e6664eff616372c7a554d387ac08
\.


--
-- Data for Name: auditor_denomination_pending; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_denomination_pending (denom_pub_hash, denom_balance_val, denom_balance_frac, denom_loss_val, denom_loss_frac, num_issued, denom_risk_val, denom_risk_frac, recoup_loss_val, recoup_loss_frac) FROM stdin;
\.


--
-- Data for Name: auditor_exchange_signkeys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchange_signkeys (master_pub, ep_start, ep_expire, ep_end, exchange_pub, master_sig) FROM stdin;
\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	1647610723000000	1654868323000000	1657287523000000	\\x74d20b7427f6ddcc61f4a1e7e97fa864934caed33b59f5e89040df25ef1c7567	\\xf940deb8a5db102cc5e4d650248be1b6b271dda459b7b34882c1196d17e36aaa855fe5cbf40de75d60df23143b536e2e5b94f4518f18a36a2ff6e32595bc4a08
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	http://localhost:8081/
\.


--
-- Data for Name: auditor_historic_denomination_revenue; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_historic_denomination_revenue (master_pub, denom_pub_hash, revenue_timestamp, revenue_balance_val, revenue_balance_frac, loss_balance_val, loss_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_historic_reserve_summary; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_historic_reserve_summary (master_pub, start_date, end_date, reserve_profits_val, reserve_profits_frac) FROM stdin;
\.


--
-- Data for Name: auditor_predicted_result; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_predicted_result (master_pub, balance_val, balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_progress_aggregation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_aggregation (master_pub, last_wire_out_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_coin; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_coin (master_pub, last_withdraw_serial_id, last_deposit_serial_id, last_melt_serial_id, last_refund_serial_id, last_recoup_serial_id, last_recoup_refresh_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_deposit_confirmation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_deposit_confirmation (master_pub, last_deposit_confirmation_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_progress_reserve; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_progress_reserve (master_pub, last_reserve_in_serial_id, last_reserve_out_serial_id, last_reserve_recoup_serial_id, last_reserve_close_serial_id) FROM stdin;
\.


--
-- Data for Name: auditor_reserve_balance; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_reserve_balance (master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditor_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_reserves (reserve_pub, master_pub, reserve_balance_val, reserve_balance_frac, withdraw_fee_balance_val, withdraw_fee_balance_frac, expiration_date, auditor_reserves_rowid, origin_account) FROM stdin;
\.


--
-- Data for Name: auditor_wire_fee_balance; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_wire_fee_balance (master_pub, wire_fee_balance_val, wire_fee_balance_frac) FROM stdin;
\.


--
-- Data for Name: auditors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditors (auditor_uuid, auditor_pub, auditor_name, auditor_url, is_active, last_change) FROM stdin;
1	\\x9c20745189fff14816ce4c019d58f848f5b1f1a7dbe82fd8e764c1a04aeef1c1	TESTKUDOS Auditor	http://localhost:8083/	t	1647610731000000
\.


--
-- Data for Name: auth_group; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_group (id, name) FROM stdin;
\.


--
-- Data for Name: auth_group_permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_group_permissions (id, group_id, permission_id) FROM stdin;
\.


--
-- Data for Name: auth_permission; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_permission (id, name, content_type_id, codename) FROM stdin;
1	Can add permission	1	add_permission
2	Can change permission	1	change_permission
3	Can delete permission	1	delete_permission
4	Can view permission	1	view_permission
5	Can add group	2	add_group
6	Can change group	2	change_group
7	Can delete group	2	delete_group
8	Can view group	2	view_group
9	Can add user	3	add_user
10	Can change user	3	change_user
11	Can delete user	3	delete_user
12	Can view user	3	view_user
13	Can add content type	4	add_contenttype
14	Can change content type	4	change_contenttype
15	Can delete content type	4	delete_contenttype
16	Can view content type	4	view_contenttype
17	Can add session	5	add_session
18	Can change session	5	change_session
19	Can delete session	5	delete_session
20	Can view session	5	view_session
21	Can add bank account	6	add_bankaccount
22	Can change bank account	6	change_bankaccount
23	Can delete bank account	6	delete_bankaccount
24	Can view bank account	6	view_bankaccount
25	Can add taler withdraw operation	7	add_talerwithdrawoperation
26	Can change taler withdraw operation	7	change_talerwithdrawoperation
27	Can delete taler withdraw operation	7	delete_talerwithdrawoperation
28	Can view taler withdraw operation	7	view_talerwithdrawoperation
29	Can add bank transaction	8	add_banktransaction
30	Can change bank transaction	8	change_banktransaction
31	Can delete bank transaction	8	delete_banktransaction
32	Can view bank transaction	8	view_banktransaction
\.


--
-- Data for Name: auth_user; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_user (id, password, last_login, is_superuser, username, first_name, last_name, email, is_staff, is_active, date_joined) FROM stdin;
1	pbkdf2_sha256$260000$dDoZt0uBqLrc2OOB3xAcHE$JNgQzwBE4jO29ao1cdB8oTCegyKmit6j7eJBhzU2nTo=	\N	f	Bank				f	t	2022-03-18 14:38:44.356032+01
3	pbkdf2_sha256$260000$3njZru3cwNZPNR1y3kGG0m$3uvVFpP8li0BW0+VCcg4kKOb6GooXcGjqxlNOK47ZzI=	\N	f	blog				f	t	2022-03-18 14:38:44.643613+01
4	pbkdf2_sha256$260000$8j4MMhqOyIHLE3JXuzarIy$gXDi/2jeoABt9U7tm0NJBqEHlycFYi2MFlhy2HA4bW4=	\N	f	Tor				f	t	2022-03-18 14:38:44.789708+01
5	pbkdf2_sha256$260000$FNi7MAvBgAnHjg63MolDlj$yNrdyS+1KWU1NbeN9hyzJaYEmp/sRhZoY6gkf3UZiMQ=	\N	f	GNUnet				f	t	2022-03-18 14:38:44.933994+01
6	pbkdf2_sha256$260000$n2oofbGy4J4bJKPsMDMfnD$DP40HzxmiVurdlyUPO2/a+a/KBfrCUyQ6UfyLQrgLMk=	\N	f	Taler				f	t	2022-03-18 14:38:45.096795+01
7	pbkdf2_sha256$260000$1relacfkoV9UexypALCMQH$Xw3bcpwqksGA49u3d2hlnNFDd7Ai6haY/0bDT17PJoA=	\N	f	FSF				f	t	2022-03-18 14:38:45.242615+01
8	pbkdf2_sha256$260000$VbSKnwWwvDGVbewUBZytQl$V6DAxCsWIyf4ELnGQRkWaGfaqMgEWQKP3YvVjeurtAQ=	\N	f	Tutorial				f	t	2022-03-18 14:38:45.389758+01
9	pbkdf2_sha256$260000$mMiHojOmjqvLx6ANC5902C$Gkl0EGKVxWJJ9XNYbkAFxoFBdesV3EnipvZxQEaa7SY=	\N	f	Survey				f	t	2022-03-18 14:38:45.535785+01
10	pbkdf2_sha256$260000$4fbQK0G30mmP23wtZINjGh$r5FjDoN3jWo1x1HKMVD03/ZwTeRYgX+u/MAMU1hP7k4=	\N	f	42				f	t	2022-03-18 14:38:46.011465+01
11	pbkdf2_sha256$260000$DE6s2PSB3Qba8wNrTBQJM4$D0fEK/dvwx0bCEUo2O+5vmXwJiwH9oAnGKEVbbvFmXQ=	\N	f	43				f	t	2022-03-18 14:38:46.493509+01
2	pbkdf2_sha256$260000$ZX901EuAaVBT9igz7zoZgM$TbvQHryiwHgtmuOKlkMtyg9yB33sLlTGEB3jGPVt620=	\N	f	Exchange				f	t	2022-03-18 14:38:44.499321+01
12	pbkdf2_sha256$260000$cdq2BtV8hu7HOShAwrS1TQ$i+/DNt5tc61qepUukqAqarhQIGfXZOBOJHORh2X5ZBw=	\N	f	testuser-dv00rngs				f	t	2022-03-18 14:38:53.729516+01
\.


--
-- Data for Name: auth_user_groups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_user_groups (id, user_id, group_id) FROM stdin;
\.


--
-- Data for Name: auth_user_user_permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_user_user_permissions (id, user_id, permission_id) FROM stdin;
\.


--
-- Data for Name: cs_nonce_locks_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cs_nonce_locks_default (cs_nonce_lock_serial_id, nonce, op_hash, max_denomination_serial) FROM stdin;
\.


--
-- Data for Name: denomination_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denomination_revocations (denom_revocations_serial_id, denominations_serial, master_sig) FROM stdin;
1	402	\\x5c11a78318ae155b09c696ec7b6fd70437154c0e912143d4b15eef86cc8670e168c266762be9bd65951d25dfc7e3adb15f4e160019f60e8ceebc3086adce6b0e
2	305	\\x116a3745f9e798ee7bfeb3c5e4a0cd10922058ef0a39a9ccc676768d53edc28d1f2504784cda4e95b058f29c7b847615794e3e60535d708caea3c4951c7bc30c
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x028c3caec61fc0c4243733ac9c3b0e11b3e1484b36a4b2833c062e124aa1fa648370b8876b91c12c305481cbfc85e74d7d4b5cc1eada3e08756f6c2d494d8cf9	1	0	\\x000000010000000000800003abd1272fd407992dc6f7c02be5f71390d3a1aac14e9ca0187f043835d6706520c45e135f6f8eda958cca1ba56aa13285c3f8044ef04e179826f46f65e33607c4c5521da504aa520c52220dee26514cb81a615678323e3458598dfe3a77d0a0859a3e023ebb87b11ee584ba05a7bcb3c9e6b3c5e0b290b47ec654c91ecafa5711010001	\\x06fb41deab6a7045c4e57ecfb6af81dcdf98a473a82183b141b83ef0ff16d8eb354375a18c2820a6f40e335cd3ab79369faa165989e3afafa0fa4de13886940c	1668163723000000	1668768523000000	1731840523000000	1826448523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
2	\\x04b4f54c0a267aeb537ae557771b6c403649f68ab708fb2dd99089e8e3bfad6dec638e4a181a535c86fa91f7e55f289d6971f82fdd93591736e9ecda157bfa2b	1	0	\\x000000010000000000800003a148f1925944c222ead7e99526bbff67ca711242ed89b2bdacbe0bb0eb6dea2264237d88810064a0003ef5adcc9152157c6647c6b74131120067e0ed81e0eb0e176e65218fbe8cc1e3ce06267f42c02c3b225d11f9830232012340b577b7fab970d6ba1b0c414f7fc7b24a873244445524f0139f95a76b0026718c6dd4cdb0f7010001	\\xde037ad3690719270626dd6a5a4dd39720bce59215845f17ef564dfc53bb6c2da9bd7c4015d9edf44be0ba07c1b1ddbd42dd3c1770ff80120569307c34047700	1672999723000000	1673604523000000	1736676523000000	1831284523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x0444a488d1ca37acac2616b860518d49db75000b6a949d0ea8d70c27317801ce9e8e6a810a9c08bfc40fcd77ea802abedd971bb66db2a9963039469d8eb7e840	1	0	\\x000000010000000000800003baa8bdd945a2d5b4c95e62f095da7b3a9d8f75eca01d20f186857cf9da1febc051a5613be4f3c407dbdf81afcbdb049c47f26c9034e7b1bf90aafba26a710e32a6579da55976a78a78cd3072e51cacd21e04c90b60673f84088f86e30df989a47187d288b8bc40e66ef08911aed1c763c9c25597a736f28c8e075f1062fb268b010001	\\xfc8efe9e2ea8c8c5b69ba4ef4ec1de4ca0f04b457330624fe521087a668a12df671e2c0f02ebe1536479cd72f26e581b9bfe2287875a365968f6b5adf326db0c	1674208723000000	1674813523000000	1737885523000000	1832493523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x05887fe7bc12e863e76f16c27e91b35b94e79403c2226c16bfe831ea7c83bd07e90d3786012358f312944a44f5e5314804cf8daf3156474d702b37eaa8997bd7	1	0	\\x000000010000000000800003b6ca8d7abfe858210438b49411037047b371a8f1bdce5c56748d857f00ac6d2e6195b2275cd600ec6395a5b6de0ce736cdbcaef5c62732927f712bdfbd0d7de6f25ee01f8a460fc828d6647d1413749d414f02ad9f4ef80c3789d5ed6e999797eb67e4fdda811d81572e189cbb426df5cc789a971067fd492e2afe500930f379010001	\\x0d496801e37fd90f4fd505ace24bb1d37c99c082add8731becd40a0d46e7c7ce3695eedf80fc6215aa7aafb4a2151db7f3d70ec13b217bf09c0645ba096d4d00	1674813223000000	1675418023000000	1738490023000000	1833098023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0744356dbd11578713253f7b32eced403b1ad070c5bcd579e227b3e7c0937b3e2835a92692fd8701c74b90f7b96d4c4a2a1f133b8211eab9f1edc2bd79e336b4	1	0	\\x000000010000000000800003c320f9deda286a80c47aea177a031343a561bc2acd0bce9713283aa6a4fe72f751923b5f9d6a9816247a02bc1d892656b8610a285f63d81f6dc5200f9247924ec86c085714d2bc0bde06ce38cdecff3eba2ca6c59e19ebd078d063e9aa3735cdfc30265669053812d1f6e2fb497e45de6694f29aac85651ce9cd3317b19cc27d010001	\\x64d7b816700033a9ed1ad94a5e3a6ad103c8b6012029a2be0cd95730c6fe4b341b38074f49ed3995271bc5ca059cc843650942c5d2629c8426d3288c7b37cf0b	1651237723000000	1651842523000000	1714914523000000	1809522523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x09c043996518f76230d7b9b54b5da64e198beb441b748d3503809c08693da0a7a83e38b54fffa8bd892187d003a1ed4bbb1c21d8a184a6668dbe689cf55d65f9	1	0	\\x000000010000000000800003adf5e86de174bf89d44c090c8de5528932ce565e34901e2ad15ca61c3b81dbece1797bd114cc6dbf7d6b104c132d3f4dde7d6a16cac4ac5c06feebf7657a9cac93de7128b08d6f44cf291f776104c9e28e4670c0c78178ad4551ecded5537080d260ca0eaf8563850b3e9d00ca028a723d725579063565cce2d9dd2c08bd87cd010001	\\x12084da51a8ac0afde012ab9c4ca2a1365705eaeba5fa06b85ca211526eca6be68a4b0d97a194ab1e878bed97ab6ab9ae9592e0c0dba626344e6c09a8cbf9f05	1669372723000000	1669977523000000	1733049523000000	1827657523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x0970785904eb4b928e30ef9afe6185ba4b2cedbc5b2173f122dbee078f12db809e4218478a9bd61edcf917274dc8c9deb43ba89c909ddafcc46389c9edeab470	1	0	\\x000000010000000000800003b56f165493dad1de0f9347792d5cf0eef67c35b577fb906c33dd8be78492ba4fa4da8e20af170aa8a8021365422f69c417abb3d6d4b5ebd6cf40be10e18d3de14c6501ce5179e53cf8f64b655cc6bf3f3856a46384b38515914312525b3148c87fbb8c715c9ab6e55689839cbb74d32df46df13bbe4c9653886979c490314e5b010001	\\x8e71acea6c2bc92077a1292571a2cc8b6d9407e5611cf5d0d3f23e0e698b2b88ada1be794061706081a6ec52c5c843a1105b9c016b615bf0f55b13440fed520b	1651842223000000	1652447023000000	1715519023000000	1810127023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
8	\\x0a28ac979236d3cfb9c2f2fcb949f96fe0c0494a5b3c9b3f06bbc462b3759408d60ac83aa69c4a52e7fa5843249f465aef59c386edcd471ab2f6e352406d1be9	1	0	\\x000000010000000000800003a442bff33abfdd84c3e45b301b89b59555502523f7c5f9072b316cce88b90d9eb51a42166a1730a311f822c02e9a3f78953e6e10bfd18793250ad1db2c24097a969f38b4bbac099af2b9be25af8f0b06700e727b0884442ab2b5d70e8ef195d019f1403cca469736effde976e05f420a34f234d2838cdcda59f1e075d2183259010001	\\xaf1e4accd0bdbd85a74bdc5b09ed597ea5b4fcfbd9a461b146a15646b00085a480b7670e1b31bf76c7e51b6863f3bcfcb977afcd4542041c9f5a61bbf93fd80e	1653051223000000	1653656023000000	1716728023000000	1811336023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
9	\\x0ba8a258d5151f5fd88a2f33c089b60b1844b19a90a085a1aee6af6b43ace26dd7dc8602019af05160fb910ff043d28aa3676aa31d897de3df3e0239c27b2625	1	0	\\x000000010000000000800003c86ce60e221346ab89ae1b6288236dfe87eb1fa523e752d5d864231a5f674fc56d68ec0284d75396a000e39253956d1ad249d3073d7c525414e94f46aafa905373f63454c317ecc0b9db8f9df440c47c1b844b2f3359821075e4307b581caff0b4144d0f6a1d3d748032c8a42bc704955cc7ecfd341ce94b800fd38a242c5cf9010001	\\x622864e11a8fd4e8d4cd7261350bdcbb2f2227a669ddf05874482e3fe76216d561b46afe240a3f4ebdaec2b686b7b76397839a4d85f9c63d6c6d2457fe2bc606	1652446723000000	1653051523000000	1716123523000000	1810731523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x0b080eebbf547b66dd0a2faf32ca46ede9353bed44751639b69f5b76d53d6a29082f8e289be00ba7bff7fa6915426c97209ebf1f540bb72881416d8835ebd404	1	0	\\x000000010000000000800003dcef79c464c28a603a99e4789a867419ca4e1a96cbe60200704306d57667aac0172c51da4204cd86deab157ab2f808b14fc83750607fb08080564cd1d359110f9b2e7131489b98e8b3835e1b652b57b2a35227d847bcf7e27219d9c586bb7dc1500f8256af0b0930a1bc1dc397e10373b88736b05eea2ca7e6d954a20c03adcb010001	\\x46e1a5e274ca4a1c0493b04d7daa52dcdd3ef6ee3bf600eefce480848057cb15f3f420fe473bddb9a6d8a048ad95c00737e967a13ee0a447d0cc9cc1dfb63405	1677835723000000	1678440523000000	1741512523000000	1836120523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x0e64dd1fdbe591f41d031de7f6fc6e94fb9ce6beb37b0ff622fc9987370969b0c58a220067661cf6068bea6c39f1eee489d4b26f20d42ec935d462da332531d4	1	0	\\x000000010000000000800003cba1399d43db13558008eb77090a7df6ff216a981db08a2d127902608d5c1d78c12d9eaceb85195c7090b66b3612fd107fe1a6f757221c57f32746256066dc13e372cbbac7492cb731b7eefef7c522fafbabd3dc34a6815b51b45b7cba177725fabb04b492cf985b5fa8345f7fed407965339551a6bc1aba11391a532a59f4ef010001	\\x5da439244465e8f06a5783376043162535927d3e7226121c12cd9cf224b8f911682cd96af786b51f1015087b786eca12b82607add903515a19d66e80ccac0207	1656678223000000	1657283023000000	1720355023000000	1814963023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
12	\\x0fccf9f4d8da70bfc78465e1ac34372523672b7a5acd45d925254125eae5df22e67d4d81950f32010f20716c15a762e8788cd30b9c2eb797cfd1aa5c4809f5a1	1	0	\\x00000001000000000080000396cbb171545895f054f3bdf1ac3afb26fcec44c9d14ef126cc93d29bde955602f96b71d73ad8c84099b9f02b8ab9d844f0192b1e8ff8dff4e2b6a0a500d03f9487acdd35efd1b8e192d88e731a6c88e563b5e77d7aa52a194ae93fecbd126630cf0c68753419ef93d2d07f12f29bb36baf333a65204f51ed45d5ed35381ad55d010001	\\x716875e18d79848ebca4b60c4a3f142061f3a13b53f887eb027e41a5d2e6cc91b638cffa97b14a731ebfd84b659a2a24d182aa9a5b0d04ed8e86ce2bb8b5c30c	1664536723000000	1665141523000000	1728213523000000	1822821523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x11dc9ea28b2fd12c26d3b6e7e14d729538345a0dfd284bdee8b60cf8d0485918c15d8a2936ef0acf4c9a1fc61b7731ec902177c91f2a7cb96ff208361c315bcf	1	0	\\x000000010000000000800003bf6f39e722b7bc3fcfe5160159493b724d8d9e6cab6bf5a00fd559c7bc9b41a298ed1ee81730664cf93af861098737ac551ef2f1eab9414359b3ae274d1e00ce4b59c038e8787fe2d2c7251e3bbebe8068cc53eae028816f7220b74fd49d22510129d028ad2e59c238803a4d52a65b75749f49b57fec36afade02cd3a61238fb010001	\\xdf3c1705b1c5df26f6b6654f55e77e493b665a468b39332c0485d36476eb16b965e63face7c114a2f2a3e787ead3052194d01f765803a155319ecc54adb32901	1656678223000000	1657283023000000	1720355023000000	1814963023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x15980747aa409db69b7b10288f16c93f2c04e974a3e585a309e4b01713ebac575ff6a10596c376ce446784da739e5ede24caad753c9b17761bce56cc63f8b6c6	1	0	\\x000000010000000000800003bb208a48e9e9e0d6f56ab2a5477f8b7d46fc362d55022e62ca30ca49724b732c40399eb172ce448a9389614e2275589b37ca317ad208a61b59e327b722096f647f19f25a172dad9e917dab198510f2d26984d42800308186cfeabb2049fb4a28bc304f2f8ce80c41fa9ad768b22d5052467cdb057477b196cb0da25170ef7fa7010001	\\xc2b3fc705f8f97964553d74d5e026e0aa8d064d940e066124b912a0ac4729b74c1ff8a1872d9da8fcde1f636649e65ad6a2c6caf602517e50a5aa2991f758704	1666954723000000	1667559523000000	1730631523000000	1825239523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
15	\\x1ad80674255b4e664ccce64cd9d8abca69279c37b919d2803ad92a55c5ff1c96490002565d7e01df14570264497b5c562ecf7e4298827e2900beca790b30df58	1	0	\\x000000010000000000800003e59a3f305a239a806ef076aaf2a557b5687831ddead16e89a82c27ec541c17189eacd2084436767f8ea3a8c1ae6208885618c6f19ceae334c752e06aa37525bf54590821094aa1ede258ae0c63e99da72f956a6d1d580769dc19c8340f26cfc61f0efa77da0925d72e7d94f2659a648e83e0d449f98206c29463de0849cfd8ab010001	\\x86c9b252bda7eaa17bf28239d092e8898476d2fad247593d891101fedb7869b6b7d7ad810e330c583f440f0423f695114afb7bf0532e3c94b7b1c2bcea3c710c	1669977223000000	1670582023000000	1733654023000000	1828262023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
16	\\x1b3c692c6976e1db0538e000c4cb65655a0559e7384535d08553f42d362283b29d0b9ef606917ae2917474ab3fd5a84730ccae279081c1a719e75de51d813faf	1	0	\\x000000010000000000800003d6034a9921a8a43bd8460b77b0602863426dbfaa4a2f6677a7e6fcb64fde76a9f03430d94a82289d37901cbd589eb64494d7dd6c37e18c390eeb93d5eda86aa4a14cfd7c08c87789205aea64fc899ba3997ccd2ae6a677ad724d19e7013fbe4c8fb50985884de4bad212ec1d7208ebc73b1676654ea6b2592b8954d46f4f7b13010001	\\xd2b2225c8944df142a3c83e189450612110f2198ee42d59ac40ca613e940c6be460f183c375ce770114733afeb719f876aa65010af5d58ffa3bba8fe2a81f601	1663327723000000	1663932523000000	1727004523000000	1821612523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
17	\\x1d44af55f942180c9ee6a3a4c6091cfa9589ea3e0a340a2e1264ab0cce8c13dbc8a0ee859a01ce5a14e0a75e34f9964c39e7e327593857d693f6dd37f9751f50	1	0	\\x000000010000000000800003b9eeefaf6a8ac498a8a117d0de1309c5c4f56a1c48b92cd308c0fb9a24c02857f454fe6f333d6682e27318309e41b7de2576791139d9c1b9eeeadaaa4540c9720706b2ba02c100db33767a1dd22e41757049d24c6ef904c64531cc30e093835f78919a98894c1066e0e563b24e90bf109b9d648fbdc3a3ca70f97103dbd3c123010001	\\x758abc2b14423ff8ec99225793b08e8e429ecacc322429e91d96e3bdcc16e6fde8b581440156914280aab46f8bf648454890061b81c0718d68312348266e1401	1665141223000000	1665746023000000	1728818023000000	1823426023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x1eb893eae79beefd1379fcf762feb094fd9861c557ab57b7b238e595280739f9aadce36a1277bf51e9c0a57563d01c2529289d312b77ae26e5781b341e630365	1	0	\\x000000010000000000800003be05b0cad34ef3ae7b7a92a82d6f922182c275ecee02f31553ea0289a876e4ce9523cdbc5b9303ebd5d041386743707b99269a23c4cda293db44af2a160d773b285baef8cd7b6f6b4c883bc0ac3946aff36dcf5276c262982982bc26253ca28b220eed98aa6281779ed2c2f782d887a823933660e5ab1b34df711cb1cceb852f010001	\\xbb8559e95c4d8740dfefbf709763529f5733b370be020f10fbdbc400e080d1e3bb731936cdd810d0c354dd38097b8f568dc47f20b4bbd30826d95e6cd9de680f	1650028723000000	1650633523000000	1713705523000000	1808313523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x203c9bd7f001e4be4983566b50fec72f606cb281b71aa89987657d4db6fec21a340388a656bd4ff93584585a950395f93f668fc4bb7b5a54e4b1dcd42beb194f	1	0	\\x000000010000000000800003a59ddba867ab41c895bff84ab8736e1b724948a3332464647260c75a8dc09f7059b491cc8a74ee1faa42062cfd25037164f721b13a3d4bc2acc8d1a8b8bfa8881141c159b8c645e9875fd4b55d760fa2d4b25b70d7f02ab873c2d238303865a604c12ae0ec8d002c45492a21348d563cdd88c1a4a660ee6498a9d2625b0dff45010001	\\x8d8c44c1d52cf30032a6be559603b833cb93891c0b89804e2906c98fe79e3ef671ae8e38a51475d7190b3af601c12dd71be2e6c8630cffd214a86c90e9db9a04	1650633223000000	1651238023000000	1714310023000000	1808918023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
20	\\x26d83bec0cf1bf3f68977a293d83f0319bd1f7f8fd149d329c2a364ce8e670e79a8a93449b6de1648138e4c313f48481f36c0c931788b41c63ab0f0abd292fed	1	0	\\x000000010000000000800003c6ce2d462241f5db4761186709ee84175da0c9eb37b955f47dc60ea8915a416ab0ea1a1ef8a7d7555eeded1e75ff3895a2014ba33ae05d761cfd1d232612728089786aafd7f1d4e3ef6356a3d6ea84a7a625f75dd9fb7033442a859ad8cf8aa03bfb76d518c405601d83ed1edb0364dadb9fd33497143ccdbd6a43b24dfdb603010001	\\x10998860b00566cfe2185b88e9cc16444c7eeddabad3b113af43a5b7cf58d0b2be82c14dea214a51c519c030fa14e1bf1cb07cee0947ebd3b0485c74f14d5205	1648819723000000	1649424523000000	1712496523000000	1807104523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x2694dd477a6013f017aab8335514805436bca3af013bd80dc3a58a1f61dc80897874818bc8cf9a764bd7286bbbfff0eb25684812a259ab65dac142a97f0c387d	1	0	\\x000000010000000000800003e6f1dab9b6a253be1d0b5012d8521d95fdbcb59e3f0b196cea13717d202cfe5e1e38d498a0db0a4121d0f968f23a3841ae5ddec171e2cb1bbf4584248efc2b598e1ef30896ebf60caee6a74c1645e5fa55f8b307a61edb94e785f4d732660d418e8ce1de93950f5abbf5ce19799563c12188132ba003f7529ac23cc52a4e471f010001	\\x04c9b990895fffa50b1f074f4b0da3f6d7a340abcc6a9907096bea2d8377f12a8acd92d240d5193e4546b8f15476607dd4e6800dfab0236219cec23205b73a0d	1648215223000000	1648820023000000	1711892023000000	1806500023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x2abcd8a9ce1ce4f0cf59ede60fa2c1febe9157aaa40b9ba0a1ff6fedb1d2ce8ed6a52ebedd284c5a113f0307de009dd6b06a635e082fd4f2e58d3b1819220d5e	1	0	\\x000000010000000000800003e758196d1bb02ac3fd30b7b4dd320a9fee2f56942f8e103c63d0d74a140b97f1d8bf2b6da322bb41217c0e25b1243ec514075221360489e6cda02ea7e846d07a7183701c279da720d4fe7bbdeeb903e333718529b74e3d899b76188d51315718c4e9a68d71e88cdc00febb7d10edfef1c5188c781294c65bc002e754e084280f010001	\\xa03c060a2d9600f32ab72a5ef1d6eec5789bde60752e7121bdb4ea406296d573b90a39b50d931d864388791725f895a7b5f3ef7821e193d5f149d24559fe5e0b	1648819723000000	1649424523000000	1712496523000000	1807104523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
23	\\x2df80bdea4e223d11dd366524f8465c4ca70e74ebc7721e25a829d6aff98a41d3127ded5ea3b08d11e90cbec14512d4e6f7fdce2e2862eadb5b47d2e45c5ef10	1	0	\\x000000010000000000800003de5795394cd966977149548257e4cbe7499241a6757f3801077a6e5f44269241f012538bbaf1d058d51c61ccbdfa3e6528ae049201b63c7b0391bbdbef001acb80a4d89d84fcc904c757ee94ca4b7092896475765a7ff0e67c09123e4c2fd44fe98317a95402c9c6c56232441db3ef9066e9d4b8c8e30c74732df3ba52e123f9010001	\\xac006d61cedb8d6f541cd320dda71aa3854455b2fd74bf3e86f8a796f64850ad975aa1518de643782287d6e16eebcf9e8f9c5b8aa3b49ad985cd8a75c9b44d07	1653655723000000	1654260523000000	1717332523000000	1811940523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
24	\\x34ecb496ad42809017c25b367a6a20647b95ddc23be29b51a6e892e6a2b56b6bc2a08f695e7f9bbf3491def8ba0de021db09db7bc164fac5c494e30da2966850	1	0	\\x000000010000000000800003ae53cf3ac1a3b181fba659866be5ef1a65a45b00d531efaad36b4f13b2f764c4acc2db012880dc5ccf1b36e6871805c0ab71b8040b123d0005910112a113c53ac6d76534809c0aac1068e3067b7da42e1bccfbdb319852408b0a5f6b31b76325a8542abc2b192a403ce149b11e1c4a712ad28412bb0f808b00fa71e9b27fad49010001	\\x10fdbce8760a63d697517d9e7bc5b3a51bc6786c11e7d4d78145160dfe931981c2b23ebbf43dad6adf9d3fcfd42ee5afc714651d67eb17f983ffc82cb930f503	1659700723000000	1660305523000000	1723377523000000	1817985523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x35bc2bafd0c7801d53095ca511aaa72f7ffccfdb6ce715a27d01dc109b5d2b6710ca81422b43ccf444953de9f93e83bfad8aacfc5149e5304052e6202f61fd00	1	0	\\x000000010000000000800003e3eae13dfbc37c16459a0708c0105509aa803d49767610f2cffdc699f7ebc60cb67647c98232b5be8ca4c9b6968231424368f21201c09b3a2d906491f6eae17ba79379fd297a7a9d17aa504501417f3092288e6a164f98ec4bfb1601ce7ef049d7a488bf8c7e38a6953e4233b80148e7439027428329b7437d0b2294de5de525010001	\\x9be0da5c48d054efa7d2651c0c50603fd57db0c5ee99cff4ef903343877837613c1b35a44e084190cb15a852ee3da0bd207294be4b75fd449dea201118525a02	1653655723000000	1654260523000000	1717332523000000	1811940523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
26	\\x3eb4ccaab91990b0423626f471db466e29ebc5a58e4fa48cbbf6b7050c0ef684356ddb3a239544f8a4344eacc11f0f3367aa449a3077706eacd68743be8ba725	1	0	\\x000000010000000000800003b83c54e78d092ff547b470f4439c5804e62b001845774d08b56a4eb09d0da345832d45c63cc63d7b22a70c79ea794ad0be452f7e85b977ac569aa50dcc22e90a7f9f3b7a167d97122a1ddab04f49cfb68e5789119e84988282e343cc18a21cd03373d21b13df3fdac9ababefbfce007fb10cf00b43120780610d614893bd7fef010001	\\x838568a91145011128d76acd47ed30fad60fbfc273ea4dd845decc172ede2b8c1cfd0e01424fb2bcc37d24c0ad0aae554bb78a3f26012a2e02d72e1418540e01	1656678223000000	1657283023000000	1720355023000000	1814963023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
27	\\x4234ff6d365a173c7c6253bc22e54cacb06acb974a4cdd8d72bfce580dcf6563ed0c546073f786d349bce526794bbdd9851267fad3d5178da57087df2a6f9615	1	0	\\x000000010000000000800003cccdd2a9620ff792c45de56cc9b8a16b86d2c0bf4af4c99e8b443027ad7d10d1c1ff127db0ecadf761056beaf649301475dfe53d15c1f8682b9ab8115ba049afbc8e766c78d470502f2a580969bd26aca35f0ccc67c20121df713df69b3a057886501a9c8ed6b7f3289c3cfc4b55a83188808239fbf8cb295cbc16db43cbc585010001	\\x460929d2813fb097202fd90b6c458370bd846f958ea764ea36e1612df9b102d51b4d1a864e30e494320c40301d58d9735c45b83d31359f0e6baa03f0d6a1540c	1662723223000000	1663328023000000	1726400023000000	1821008023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
28	\\x436cf34b8931193956bbfcec2e6fb78b76b3610b2a6fd11d69c1becd725595d140e2c318960e44475adf64522a15e75be0a9f8a13b4abd0b04ec019b18a7a260	1	0	\\x000000010000000000800003ae832effe5c5cdac5e45e96ca5941f482ea9a6b116ad1c908385c1e2e1c4dfe2f344390acc137c8d32242d10caae22e3d3411fb60072d3a0a6a08ea395cecc89bb2acdfbf1c13d46a24fdd78e81dfded5a5bb1fcf169b252a16e50a15a58256ad037c9ad61f9781652fe74881f0431f5cf11baf83eaa9633ccd05e950efe7281010001	\\x44e340cad177648658b45323ea181eac10b3296240c3bae276352ccd326a4187dcde453e903f4a5af7c0ce0e77dc9747b67b19132b9e4459c3f7dd65f2da3f05	1657887223000000	1658492023000000	1721564023000000	1816172023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
29	\\x4464247d955b586d3b26904409c8f24d044e0863e75700a493f1688ae6e188c55707f0ed9abd210383bf18d5143c189f5013acea18f5ea686d0a305f36d38d38	1	0	\\x000000010000000000800003aa89b5e040899d36493ae5e15a9d7d9162ef0beabfb7af6f3b844d1b641dbacfda987159caa3add6ee1e82f665060745868a7a6de2d861107a1da463f129436e38d250c504d6fff0db7c97a2aa744e0b820eec1483cd8c5b368889318aaceef0225244f6939a4a6969c2e11382b545aa0142b3a8fa7e860afd5783ef9fc4e5c5010001	\\x8dc69805fd999c4c999d0910721211c00d03cb7f888436c5b32ed955044b9dcd3adde1ab46fd99a80f22205f00ed7b1c97dd3b2e415381fca12e9cfb0d54b10d	1672395223000000	1673000023000000	1736072023000000	1830680023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x46f85aa63f9578e5e0c55d3cf79419a638ad18b90e4a0b5cbe1e2b0957759fd5358847ccb6ffe7f3c9a241e809d94476a2f0d26ef4711fa1fe8cdb926d1970a9	1	0	\\x000000010000000000800003d3e96da71040c082062d9be1ccbd86fa51bbcaf8555343b3bf4c94863e9ffb5fab984c20e18f344dbbde985ee5e82dfccb7a1fa171306443d30bc2963a643e13d1d678acb564b819d4f5df05d27c836146a01dcc796e9537db29d8d40326f71e57c7ec99edc37e915462fc39252592734dfd10b5708f15e32008a7650d209fa3010001	\\x24e9bb93b7ebef6a4dc06f16fbc99ab12ecf99a321dba9bc4929acb313c8864fbb2cd91c7e6dc1e5498a0d111646a55480ac43f747dd74a3d5b009a3e05ac501	1675417723000000	1676022523000000	1739094523000000	1833702523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
31	\\x482cb5181d3a51f59aac3f7bdef7ed2b1772c2f217a703b0138d6f7e00b98f22253bbf09a2f8e2e80c264fed00a9ab929e28a5802dfeee48b948bbf03a02c8fa	1	0	\\x000000010000000000800003a72389d916b2c16bd08c5f876eb53d7ada2ef437822f4e70cda04b709e06d051387ec033174a5b52dc324f2f1dc12410d0811249b96df0d14ea19071ee43135e5740d911242065cd694a0765495e89f4c696d3e0779c751668860cd0da5848e387f3c009f17bd1829a274366c8544b07a4379b60cb692139de85fa1d879e1eb3010001	\\xdc6c6aa779c441b70bddc45bc39ac82ac89d964cd5f9f409668b3b20565f82b054689e45058d5bb4c8c2994c7c9105f0807765208b87612841cb96469fe5bf01	1658491723000000	1659096523000000	1722168523000000	1816776523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x485c74ea634b33746a725c4651526ad034264a376146f4d575f50e8100999149d813fce847bc5312ac6d53e86f7a5212ba3f141f5c49c75bbe0ff81e34aefefc	1	0	\\x000000010000000000800003e2bda5f31488b4ad3e08c98a0b645de059eb9c39857700569fed7dd1f508eb9ab5e03a27f66feb5b670cb3c0672ee1f41d703ef6112304f225885f8f58acd31470e6ae4f0ca4b686cce42d0a1a1a693ac3754677905f77a0f59e675b138c22c48a82670972eb5785ad343867e2fdb29fa3af1ab07419464dda3eb3bee762fee5010001	\\x4d572cf07c74e98c52fd32eb486355ae013633ecbf532b4bd10131fdae8519a0d876daf1fb70e7b5e2999f40b6ff2f230acd88e9dc18391857ffc2b1fab16204	1671790723000000	1672395523000000	1735467523000000	1830075523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
33	\\x4928d6b256c6557af19fe86508358924d53ee646c37dbf4a0cf4faa4915abeb14e8d525cd6771ac60a1ee1ebeebf5da94df2acb404ed37ab3461ab3c563ef57d	1	0	\\x000000010000000000800003c3d5b08b14b968cfcc7378bdec0cb53e83a7ccf2bbe9b939f17488beda71f9a6959899ef70317eb19aa9887c7fc5e73e5d4946450d722f6f688a22bd76ae521ff158335933e071daa3504202febe315526b1744631bf70b2208db6009bad05cd8d0ab467f55b4755d9410f663c0d7086975c6796d6dc3838c2e53bd53022cda7010001	\\x495f28de935bff7c9a1b1caacf78169e0eff802832f3c8805e6824c0bc062e99220a3b6e71f6335f5a62636fcf4c0a7c3bee30f6c1bfea7fa287d4efda914705	1669977223000000	1670582023000000	1733654023000000	1828262023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
34	\\x4958c0aaa0b84a2c40939cd0d1c3a14b0fb11235ee5a767762d8cb7132967574105d9cbe3f394a95590d847da03509b4567d6b4ab584290a7cfe43920a2c0816	1	0	\\x000000010000000000800003ca829bf1aba011a7943a233a918678255d381390edb862be852799c9b0c7d76e122d371482c47a0e12e7c72272fd6e84e3e27b4e2246f7660f428d6c54502997c3c39f2d30e0dc128e0e70dfffeb2916bbcf0d60a2737f1dc6b06b4f444f8217a1a7e10055ddf3fa9f5048a3ea477d9814b912772887e9b182e5d65d1ea4fd89010001	\\x2e6769983e56ae0b5436a76effa6fe4c82f8bdcf4d808b70e35f77092a8536aab0a5ca76cecb09165203e94253c6c4a94d6c56dc7c8007961f89c01ab7ca950f	1658491723000000	1659096523000000	1722168523000000	1816776523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x49acbb179c060371e22c268fec01e3e731124fe7419094dc85150908c9baddcc2d36bd7f6099397cfdd4f49e3ffbbb2da8412398d94dfde317b75335a6c6ef44	1	0	\\x000000010000000000800003d43d9a896d614fa8b1b484045a0498a75682fc47e69b405a8eaad246fdcb5b94140569f472dd42396adb5b3c9ceeec34e8a507c8b458a03f4aa5cc1e265cb6459ac464bb1023b29259d7805dd1d2664c7d14d338448c1439be714ed7884d304fc8e6269a12ef23650be6cc9fcf01a24928df4c62b413a7ce148a45febd6d56bf010001	\\xde73e179e71f0e1b88ce8d033079690696279f22e9361f22c29a9a7828cb7103f617f5222d1831af50a671bf2bd2a03ca86f3d3d7f1ed5c4e4525294eab49e0a	1669977223000000	1670582023000000	1733654023000000	1828262023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x4bf84e1a692d04a7ad9b7a508aa2f54963610fd4a274b6801f84eaa80dc0b61defa484ad0645328d6c2ff78734d2325e222b6aefab431d49b6ac6f0df77005f8	1	0	\\x000000010000000000800003b88d09b5e714934b44fae8f90ed807e69bc8f5b9c009e2efb0598cfed2d4b4a373ad8a7b4b9f44604de167d16c6b0901391492d73b191fb1cb395a64c257ad0f84265b2fbe6f5c2669997ac22fc3c84d6156e57771ac84ace31eadba6ebb1ddf82f5a01df72744d028d93bb7e965c7cd4798306e739fd5339cd5b2e133024b97010001	\\xc17fcfafd50178eada3d6c7eb9e3ec1d7e5635b7b3301145854bde30d534f0e34df2d912c2d97d1f22f6b1f0133e0c68e61add4fe3a4a8ca88729e9e2a4e4f04	1677231223000000	1677836023000000	1740908023000000	1835516023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
37	\\x520c564ea777215e1a721cfbbba3b0fd813b0a78bedec075ccda03efc6f06bec87f7ec62dc02774300bb5598162061834ada65bf42d88838b53f9c8d97b8e5f6	1	0	\\x000000010000000000800003d1c0c9b941e0e7fbf45fc8f9fae3964497f60754793701f0006f5da7e5fb5b95250144c98e611d01b0986e42dac7345e1df3e364954fec73f1454e5e745ae79c43760eb722bcc2838a3b86bf4dd538ec384462b5899eaa43ca25688aefbf14ebaa58acdc14ac0c924af8a6a30c8f2c574845797c1625cc9c217354d595c0b87d010001	\\xa2733052fbbcbad3bccd061e0c225031c3a119ec636702f4ec442a5a1659487c3027ee7514e223e05c70997470b3479536878a547a75f54d3e0813c3dbaf6300	1671186223000000	1671791023000000	1734863023000000	1829471023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
38	\\x59945a0bbeedd234392240b2f53d5ad56fe86c48f86a3574faca7256117a547993394006b942dca9cae43efd65bfbc880b7f62c040f79290835f9f525df11dae	1	0	\\x000000010000000000800003bbca2d19658544f46dddfb70cf4283b778e680bdfb210c03dbc1845702a2edb78919a30bc75f033e0aa3b48e25b710772e22114f2ef8427fec4b64c888868be4c385dedbaabb344eeaf9c1ab65ec2b95f0e41a156aad3b8210937c60d7eaba127f9b7630744a9526f02ced1d121564fe7d40e3c23c8ca4826b11e59b60a49307010001	\\xe8c4780f88677edefc5cbc9185d26ca3cbdf3fde42008ac780f8e53a76a14ab74c1976d304115c46e3b503a0baa8239cefbb65eb8906adc0a963dcd85e2af30f	1655469223000000	1656074023000000	1719146023000000	1813754023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x59ccbf68ca0202c4e3a189f4e9c9231356bfac69f61670b02247fa5f2dd2e66447c775c3616ba3c418beebbbd912b424bf466039f7e6ceb028b77ec8b62057f0	1	0	\\x000000010000000000800003ce81ce2607d88a9edd44bf0279ef4719c3abef870433991337345c99245a448b1780dc031613a4b09f0e7455adffed7de0090e2ef9fa3000f22126b38ab122d9d70b32bba9d3c69cf8d619d09a11dad7bfb659dd846c90ec9480fa29f0ecf4b1eee67813eb31423749c14a67331e51d8923d8f28bd869ebc6b06d047aa065551010001	\\x95e11f53afbfbae18c923581dbce90110bbed8a9087fa677ba5e1ba53e0fbe7858e78104ab25e48f8944f50fa38ea9d047c69720ab1c5b35b286261aeeb59d0a	1679044723000000	1679649523000000	1742721523000000	1837329523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
40	\\x5ad8bf3a833827def68cb3741b37c435d764957e21823e458d59a8110c0aa49e124d4eb15f28e23a288f68700f4b1fb72120fec7423dbe05c4da80cb760ec18d	1	0	\\x000000010000000000800003d8565f2698e9c21abae3defa816ed030421c7e27fb5d7664a61e67e4a7d9b65ff39eade9ee208132cce4939342dadf97d45391cf87b9f6e5887930d49f08c650bed424330e57f571cda1575b11173e832d55a63d4981590ac517aef5dec1e49302c58ad2d058ab24c5b7aac4d85420c28d458013a6f219bbed7fc1c3d91bc617010001	\\xdaf626ded6da66c719b9b1dc70044fbf1188d560ebeab939be4eae0473c7341c20a5c48a758ba81dbdfe285423f21f42c96bbdfc7d9f791e25c7637b1ff9670e	1676626723000000	1677231523000000	1740303523000000	1834911523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x5bc4f14eb334c1bc3bac57b8a08dd37462670bc3511892ea4bc771d64d09f2f501b277e5d2f75e6ec2a546c395eabb487126dc852e068b47a808a55608bf3172	1	0	\\x000000010000000000800003bffce9c35eddd746770cb8de14a79209ec25181f731aa7504bebbd5c961e2b2f8f191cb898569993d79056ef64b6141701b4cc0f293cf99ea07b6c0407ecde66b457ddf6aa455da08e7ceeb4e70b23f8e47da5be78a100ed8e4883971f18227fdb546800c11a9c8f68fc3c470f09984a0b2cdba538bf79704806c4dcb96747a3010001	\\xeb0774ad5276cbb10d16568732c3bd2d83be0d6436d97e3b8dbe49f7173d0509a98735dd31b02dfa91b9a238f67d97bc0060fa85f993758db978fec55ce56a09	1663327723000000	1663932523000000	1727004523000000	1821612523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x5c78d95460556dd022e8ff78c21d1a511c539599090b4d3a7e51bcfad5d1b3edb10669641acee0012b84ea774e936497568b2d735eb9a131bb9019bd1a3b7f39	1	0	\\x000000010000000000800003a87fa9fb168cf3f748de8b611e171e2fe2611363d671e3c8ab684797a5fc543ec79922df6c3442ecafde3d4c5914c078fabeeda299c74bf3ee08c7694be4a0aed2d342f2f64785375fb6bd1c59f9e2149c40ead857646fcd7d153e64a7f19110c1df6390852c9751aedbbfa6fab0142acc61bece50023773d70de83cd57a8b77010001	\\x29beab1b8e2f42a543517b84b60a9e86db28eb9128afbb588597c1deaa388dcd66415c39c5dece0ff0780e2f646845027090f8b5f17d8fe63ad84c994211200a	1648819723000000	1649424523000000	1712496523000000	1807104523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
43	\\x5d9ce37db67d1395a66f66f50dc80906109dbe837fa813388fe21b2b733adb6f3c182c7d034b084d0f5836c0fdbd8806e8a4b443cc0a449a1a7692d9fe1eba92	1	0	\\x000000010000000000800003d7612cf89cc8033f380a1dc4541d05960f88ce16581b7d3e6d403c1c9cd1b0f12b6cb0d71726a9509abb88ac0faf65a22969e861e6641bf6430fe60c8358f792cbe2aeec821972b4eb7b1f190caff39dc6172445aa7e98cb3ee7f65e7cc21e984afe965d1b39587d8f280782751f5dad23cf6653f8e5865676fc3b9f7a17efe9010001	\\x2bd57a6a4730dd86797d12ad467fe6338fb1812463ffeb2976325d09b03dfdae7a4c34fd6bafeff9b62c31ba4a2cbbe7770b8d56fec228032071c6c05a74c20a	1660305223000000	1660910023000000	1723982023000000	1818590023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x5de4831d3c36eafc44b6cd43c3526e8577dabdef3b99880607d10236f508b7480fac788b94fd1711f99da4595d94ed2d2896a997e2c3c797205389b98ad2d3d9	1	0	\\x000000010000000000800003c8163d77da2e91959b81a729a0ae4b2e0c908f56035e77840de8f443a0720a6d9b5ba2e0828cb70300042816bc1d3cdb3d1a66eae8af835500bb220ee939c7af62c24dad9423439d8ad1c26a6bfdbe4f0dc73d3a42f6f4cf497df62bd0914c24516180449c5cfcedd875b9a02b1b29e0aec022b78b67098b3c172399e1405e71010001	\\x10f701bd44c002bbb1c786b0740685fa3a4870a08a86436f17384b8cb44ec9b2beb945e75bdee284ce018ca6ec5919756aab2658a49e54dc3d0b12b95b83a603	1677835723000000	1678440523000000	1741512523000000	1836120523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
45	\\x5e1c2d9712d7155b7670922bb2efc526f6a61d03f9961be051434c0724345756eef18ce5a4684eb776b2faa2a8d3a9551fc91066b40a7b1f1c714083aa980202	1	0	\\x000000010000000000800003de83b8acb1a69fd22e98846b8bbfe40ea5207632a29584a31d93ff5ed312d611481aad1a29cf227f96cde2facab979f4d185891d709d7a872fbc8f5b5c6099dee8faf4bc62fc9e7b0d585748d74bbffebd7ca7f9524b4198a062699a67eee2e79d04b9d7b646c088a298c24d082dc9c53edad76fe20dc5f44262c2edd29b6317010001	\\x359190eabfdb4068e98f52f624eac94a5137a5715d4004ed1e2a639a6e4f45027beed6cc3b6b1118ec92108b5ea3232801536bc69d30c495ef5db92470cb8509	1653655723000000	1654260523000000	1717332523000000	1811940523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
46	\\x686848ba0a1ec692ff122f174a9e2c579033dd40b831d517141e0ef5408194ae88af091c6af38b7d075f948a7742cf976dfce602bd62fe727634948fe33708cf	1	0	\\x000000010000000000800003cfe87253b39b5f94d9d38a30d65f56acedef60b0e24d559abc74b78f0e28cab3f8f8b817c685f91b21bd062b18b260605137809074c86748b20466ae5689d6573e3c0341c4417396c0894c023de1e1ae51f5fc903359cda54389c28a540a5785925aa5ceabb987980af09aa658f7f367e9d8fc8be310aa1d504c0728847a7fed010001	\\xa69656b234a386e2999cf5c4a68cf5704f02de3bdb29d8d73a46ea1f2a8f228527bde78936da9d6a658767311db3a5785d16cd931df0417192ac608066192c0c	1666954723000000	1667559523000000	1730631523000000	1825239523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
47	\\x6b9c261e045001377a4299be3bf18c89a50c7c880bc23b414ab37ec0a34b766b64a6b954ab19ff0fc6339deef3e95f2aedfcc37f1a796e7dca3affaf760e06f7	1	0	\\x000000010000000000800003ad9166f6673ea872dbae1f7edca20f39bbedd0faa9a6ae3deeceb6f4a098c0081f423a258a152ddbb637faadc91b8c9effe1d69dd4fa972e8c1cf7bd55c97c82b328994f32f0ea0abc4d03f9b3bd3387ee658c52258a6db836eb5a876ff8c79019f97305bf694a9c1eb7a8ba1e549ecc4723cd5d7e52f6196e8af15e290cde03010001	\\x1cc171c338cdcf0664d1fab0701ac4a50e6a800dc506efe04d1be1cd825514d013fa22b67f08bfbdd5c66f602995c7f08e5f083d7c77086149d6b92839e42200	1677231223000000	1677836023000000	1740908023000000	1835516023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x6c606006c5ae7e1d51c58789f7460ee94c6e3a88d951d70820d7c7cd7b6e802509f2bd2ca4d44e792ff93191ca90b08ab846534fdf639570ddfb966347c6ba47	1	0	\\x000000010000000000800003c4d825560b335c0929d45259450ed0d7b144d875aa71ba75e026442e7bf49e37c8dc860b0e90f412a282271490cc4531d2d798d622348d54ec9a9fe3df9dc1836eb4d38db1e998ce4cab4e9994c8463aa51a6a334e2ce58205f16459b8060897e5324e25dd2b73cad0cd13959839d7d1b931703c8f8e3c57a72d54e81bcba98b010001	\\x21f9f5af7ae0ab9b1a123c1e70cbf56d4c88492374d1d18162aa93260a0b51a580c8a77823f4a7717e055fed6cc2cd73a1c589ace21d6f50ad8af0af88894202	1670581723000000	1671186523000000	1734258523000000	1828866523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
49	\\x6fe4307a4af01349f3df093f060b6b477f4b275113205f9308cce9bed5da7b5fe9de24b4c6d0aa303a5e0577b0f703519d6a48ebf3608ab57006976e5068d595	1	0	\\x000000010000000000800003c71f823c48365db2d0b183b03ffb745642a8648d2f407a0886a6c9941f44de1fd68fd631ad7984241b373c6f1cb6bea1daa7dfefd4e1bb33dd3ebc4126f674cb9f65926d8e2ecd940409f1264a75709fbaadaf7486b584faec87156064c47b386785778c73877985c87cfbc2de655ffb65b0cfa000f262bbd73506ba198e8cc1010001	\\xe9d2eac54725b0715c5d637e4eafd5b4590c31a9aed02bea7905631fa9eb384370ae3c31524ddf298f66cd7114457a2f7071452ababa12b0efd1e10d791cc301	1674208723000000	1674813523000000	1737885523000000	1832493523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
50	\\x72106111cf8c6c135ae6505c1cb4ab3c115b0f3f613c666291fc4bad1f464bfe2bed48bf8dbe691a474b16deb72c14b8e7d7787c7a1ac0ca31b0a8bcc853bc28	1	0	\\x0000000100000000008000039b3ad46c47f08169f805d5949fc919956975ff235f33030f221b756bf061a034f3de91c542d24b93bc72dae08232517e5473d229e01890e905ff35f1df34f4a3a85e5aeec058a8a480fd4d9ff654095b18b879b38db83d2b59348e82a4497f1fb683841c98fc86b9fc965908eb12ca58319380160d5827e1f81fbbf134fcab55010001	\\x193bb88fb7312199b101b1ccbedaa768353d147e4ebc1f1cb6bcc20327ffe4b0aadaaf5bdc16739da4b32a7ccf2bb60c95ad4e1028b1793d15608b39e9675e0b	1656073723000000	1656678523000000	1719750523000000	1814358523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
51	\\x73e8a4d19d0e67d47ef2319d62851aa7c45f005bd6a6ba910e9257d7c6d82d188ea9deab8df8e58c2785f1b590283c8b50059768efc147ced35f392b79f6e3df	1	0	\\x000000010000000000800003d2e134e598653aefd05cb2f8edbc34ded59ac5477b31f5c340f01eaef7aa13d23771ef3a06b732e952a04255fa5e072de5c371944c0ab6fbf6ef4aae2f82244b35766bdf83a79d8926c63a3452ca3aa7210687645d554fe0dd00c44707a89d0d10fbaef60b1ad7e64a94e8211e95a621f3ace60ddf4553cb976c7fb860011efd010001	\\x1bda68eccba106cf34d05455007708b9a603c8ec2fd4af8be1c9ba646cde0e365f30445c04876a4320e24b15abf4b998ad71ced2202b4a24b7c638a7dbfbac09	1653051223000000	1653656023000000	1716728023000000	1811336023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x73e41f0d5095ed2075ad83157c32f2be92840aaec507ef5918f808eeb05959b5baf4648cfec3c2157d7b09b7fa78aba98862de158ef3badcadc30bdebdb4446a	1	0	\\x000000010000000000800003cafc32502f06318c283538f7427510c99e132be34c5bdff390998fc005463df677f0ada66e88492a233747fa8d8303ec00bff14b190e2689a5c42a32b255e18a0b2063ca7471da230ba2f77bdbb7430044714282dab2df3b0fb8c470fd28dc948ca4983f7b5cff4bb30721334384422ed089dffd3c38c8080680be4e1f9b107d010001	\\x2b38fcbd92404a47e5b764ed64c470685e6b7fbae9ea2a77563d89e498251e0a7ed6cee30fda19a674dbd0757b28ec2031e0f971596d2d10e8e8a4ab70ea7a03	1671186223000000	1671791023000000	1734863023000000	1829471023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
53	\\x7fa4b5cf10bdd20cc279afedb184cf00e1b7ecee9fb75f71fa892fab397dbf1936a59672c1c75789d83b87de19a8a0c602f6bab4be18401b4c53868c07da9b5c	1	0	\\x000000010000000000800003d451af772227b24ce60f732fca5e1862876df6e9d1cc81e764c572a70f93b84eb54630793e67030aa10b1643fbf1b28f8ffd6c0c08c6bfe64ceb2e95767e3164c48257fcc0e3ed45656fe92bfa30879993a1497852b5f90541d2ce10e9c34054b9e58b46f086affd984bba74c5c976f10cc60f3dd852c316246af90d944a1eaf010001	\\x343560ddfb95fbb183ae1bc43e6ec1fd7009890ba3e7ad072d3d9c3aff64c5e05819f7e25ef4cd8bef222f3db5e27dde543abeb9769aec81e5aa09833e757502	1661514223000000	1662119023000000	1725191023000000	1819799023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x81884d20fff59797f732432c61fc21f48bb15148e15c23dc82996f8ecb1c5058d1944ca22820ac721b3a1ca59e17b67f941ba4c098a7e6779f50c1e79eff2aeb	1	0	\\x000000010000000000800003c0abb1b251a8f66e4fd4c24d262054753baa84897a06ffd2a3b9862743000c5ee6a8b0e092bb36de1b333c43b8818e4430fb49dbd009ac0736f73d8d193f4294e4a4e990626d73a787e4c9709ede8eb70f34ce5cb0aeee2717664b2d26bbce665ca614027087d1eb89195926e1bc90e8943ead2614ab751c10f6df4ecff70ea5010001	\\x577841647a573430d2e371e7538a17b88140ea8b2a071cfd36d05c649170a8b2cd142e2ec61973d61dbc2ee242825a67715acfe1a8862e80f26d415048ec040e	1667559223000000	1668164023000000	1731236023000000	1825844023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x89648a009b2b47bd0b9cbc0fbf28628332322e46373b097cd9560df24046b52a98951a53a84e6e01987ba63b52d432b42351a711a506bd7633078f78c09f572e	1	0	\\x000000010000000000800003b8fa44382107d2feba2ce041040205092f39c3d7863a879624f5e89b824fb493098343582ddc4c0ff6033d31a55dfb4aa2ee07d34c10da4c6e8760944d31a6ec7f767043507493ca2d06f537efcfc0448a80bcb33b098295b50e3d255825c11bf0d7bc5f2e0d1813ac10e37b4fbbac98a250d9fd152244d5855b9d2af81c6d4b010001	\\x4ee8a07637b9efdcec8fdce936ad8f2b4108da94c15fddf66d14946f49b6bcf937705b0d814385cc2ea08e7693186725a756f5cdebfb42a2f1717791eb9ac70e	1648819723000000	1649424523000000	1712496523000000	1807104523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x90d493ecfd2eb0cfcfff38e4390967706247db6f0c9f1aa5cea2b05ae6c5a315e2bb2be7e0c8047c9a5535ec26be6d57faebc041ceda72e0e25790348156f86e	1	0	\\x000000010000000000800003c800cd19232b68203ca1199d71658dd508880a1d0570e5bc65692bd584f481d682affeead5b4215c94ed69ccf8a06ff8566845eed5023f38c24fc31c127d80c052632cb53bb081c537dbdd373585d2835768f455675af9c58564462b50b1c38e8f3422f7d81754bf0322dd91e7bcc8525c5c61c08250c05407c251648a67ac25010001	\\x260a2a02327ce42937c0722f76453401e4ca36e0762facdc04424c66e474ace71a61536b95260b459398ffeb104de1d0128b6b73037250c5e6d6ef4968fc690f	1671790723000000	1672395523000000	1735467523000000	1830075523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x94086335db18b8b0758d2d67e7b01a7f64b9f8a7ecd3217921069c8d144c099c2c690e282bb2bc9b8afa262e9395d2fcaa7b0beeebe63a530b092513f1c6564c	1	0	\\x000000010000000000800003b0eec9650916162c170b467dcb6e5afb3860a09e15cf03261bb10fa6710e96ecb62d512c5f1239aeae75559a5df3921602f3c2d9aff42363f2af08ef3b5d2e1dcffbae4799c31f986f80d5e108dc2ee39560ccae42120292dbce41cb1b9df442664553fc99ac62e74bad28f63f22d9dc2413258a81fcbe161e7ab9400d0a8d15010001	\\x298960def9575fd09bf72665c44a7f3742e845bb796e380bed57be76f1f40ad85bf275dfb17392ae2a3d390392f8a7b1b382e7c3693aafd5dc8592a4316fd90c	1659700723000000	1660305523000000	1723377523000000	1817985523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x9424b66a913eb4f16a6ab3e6c8b2836a26d6df8409984add9ba7eb71a39c9a3acbdb138bd3f29f8de3bec2832582a855ba66cf44a215c46933879f79b331908d	1	0	\\x000000010000000000800003a00d029af6e399d02bbdbc9931db787cb4715fa9f8465b4efece9f72a5618d5157d2a2fabd8106064200f0c9243fa0b256adc3017e1b5be923d7974454e61a35bbcce4a558c80994d6aa8ec4d4d08a63c0a29c52c0de304042fbd497fdfb9de757cc08fe99f52dc51beb7fb0e17887789409750d4eee477bb8f3666280e23245010001	\\x6007b878dab02def2fcd635c608e7d552f9168f77e3dc00b3a7ce792e486cef4c514d53b441b18448e7faeb4b565afaf8b02a57901f670af8340573e58b88801	1656073723000000	1656678523000000	1719750523000000	1814358523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x94c4c3d572d82441a6e0966989b7b283896ec7776ce88a1eb9529939583cd55dda0de81146001a799125c550b73eed5e6f1c9a08aa6c179111b7784225e6b1f2	1	0	\\x0000000100000000008000039ae7f408851db5ac8f01f29e9720a20a4b47a26baff574ae846b1e67a05ca9427dc0d257668f319aae9b917f31ccee11ae0a2d3732d3a90cb966d96191f0422310bd225c09944c44c56615c4baa2fd0ad36dd4ae3345da088c63ea2c0437278a30d1fb826226f4323c62b6109514bbbb1ebf2e5947f61ac420f13ed81d219f6f010001	\\xcc822b1369ab5ce4191ec0aceb7094ffd2c7c062f5e8cec2253d391b0b3e58ebc1867349e43ab3097a4efcf78f05b35f917dc00c8a3754742426fe3627908a05	1649424223000000	1650029023000000	1713101023000000	1807709023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\x96341a464894bd8126f30b22e6c0cbd83853f8a70bec50a7c1eac1c5ac74b87271ceaa5de103f74491e77627a6306b15fa4cb2389e8cf6f18e1f7891a4522062	1	0	\\x000000010000000000800003d7cc971c7389d4279fefe62bf9301bda46dbe7ccc1047df07d150ebc02b5c37fc4a38a654b660ba4e264c31e744e39bf134aea2b0a3c6147710f37e8a4daf4f29ab0822c58a0eb0821eccd704276c2447ccc0f0fc23c09e96010caa895dcad2e4895506990928c0bf9a09543340424f692f402060b793b63a42f386e557037d5010001	\\x40bdd56470bc77ed1de44a2f338738012e94952c4d29de974159f81687f85ffe541443f1fba23294cadd777285509625e61a271129d85f6edc2c3a73d7991209	1657887223000000	1658492023000000	1721564023000000	1816172023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x9600e8f960643cb2cf666cdbc5a2a39ba4e4daea32c94a24738cb633e1e096ec670b258a04dabfb56d62e935d4c213b3cc620ea0c0838950ee74762aebf6cba7	1	0	\\x000000010000000000800003b5355027fac304b7259ba423fa0150b2f93e7f65022252d8784c6bb6ca3c1667c31f13ead9d6719404cfc967d9d98057e3909f5ae10606276e18f2c2db6a4a7297b3ef9986f948766f1f2e4c68090ad6d8755d7df0b3f34cbf471ac9522560d64393551c39f2f7e9652c7a5c81867b1850f25796a7c57825707673c429b0dcfb010001	\\x9f218726d8614e029d7703bb077fb6e5f4ad34e83120037e5e74c41b325f3338e937a2a834e90aff9068ae5b1eb4a3e96fd38a588e381f50dc760da1ba2e4409	1676626723000000	1677231523000000	1740303523000000	1834911523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
62	\\x9e283c7fac0dbb2554ebe8daf5ebd0fac71a68376ae1f07cf61a9cc3b18c7edcc1d787c19733b74ade061d49f74e8921a9c41f4f8e7a0cc040f4ff485196590d	1	0	\\x000000010000000000800003b571524078dfe6e091a196bc572fbd84cdfa2b5415f03a6c3bda631ba0e3a9277ace33dcd2381a510764b11db268bc8f45ce512222ccbeefe7ede5dfc2a14ebe6d07fb432d8d813bee6ed78f9e77f881b7ba9e9f62f497580222f0ed3e7ad275b8f3d9e7f5a84e5569917b3a51acd3770089f5a5ca8b6c92008787ed3b911ce9010001	\\x892fd0d3d7bf740449a2f5416bd7dce7d5aa65e3a622598c6f5fea240b671d3f7eb6c3bb8e591c30cbe9d9506785f177c837de29afdb8a33c8f42ce7df5df405	1674208723000000	1674813523000000	1737885523000000	1832493523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
63	\\xa000da378572072d274c2cc3b6c964e8a05194553ed48eb313c4d500b5deb669ff4e257dc71fd6c0ae14cd92ddf4db03e728bd37ad38686eff62d3197eba0720	1	0	\\x000000010000000000800003bc24f21e56346795075cc0f296da0cef554c08cb137bd2be9d025c84033fcddade3dff41b10567e93f3b5ab9cc382cef41538193faab52a7daef793edc5468ee9bdebf53c2618fba287cacf15ff722c1b9a400458d263338646b0378dacf035fb94bd37174a5f841299fe4f167df5829a4479e5c07ad6a56334a37c90e42c7c9010001	\\xf11f2fb8c8b95135095773f58669921d91a9203955919063170058da98364ca0c8a5c3835827f7d67dc6510368c290cbc3042759eed7b4e9293e5ac8d54fd80c	1650633223000000	1651238023000000	1714310023000000	1808918023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
64	\\xa1b8372c4c6d3a39ff374023e1800ecedb74c361bdc69c56f88eb1d0b432f30ab69c7359bda822798c20f583bfe0e4ffff3779d8d5f901e21572ca8e10725f59	1	0	\\x000000010000000000800003eb7caa9ea2cb4ad5947cc000603ed5ee4c200cd034024468b94d581a8686b23e3bf98637a42278cc6663f4ddc8d913631a6c25db70e90bd4c1b6b0629deb12b8f8f745fb64d41cb735dbbab538976d176dcf86ef7f8af0d35841ba5657ce94bff807f0910c1f6fd4997ee2e42284768bcfaadcafd6aeb279eb78979ee7b87971010001	\\xfa7584c74c3634f29d422bcd5fc7c825b26eaf886829475e5b2f103bd1a516daa57c92bcdf3ccf007f94d677294dd68647c566cd8f4d44fd98448f840dd9b904	1661514223000000	1662119023000000	1725191023000000	1819799023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\xa3e43bb97bfb1826ad16afd9ff48f6829d85fa75f2fb5b57efa8fae102c1b0f3acddeb18d361458343f096962192c8c785a579f35c4ef7711c067a99a0ea5d5e	1	0	\\x000000010000000000800003c573a1ffbe7040d14eee7481e6f7d233178b48a67dfa41e6213ae90ba0a4a12772dc51a707509ec8d47acfd2d6702687d8e1c03e0bd410db3384560d73dccedda6fc1d9b51a614a68b04a6ca06829586fdfc36de3cd12059336b6ff37722be7d44f1cef38118fbeb448fd4a672de80ab696276177a8a8c3ece1ade1ee2f49ea1010001	\\x9cc322e1d63b90edc4087cec54bc522cb32e83ea157d60250e2269ffa9531203a7081041879c379745143e086ace676e5ddea44c3678e80d6967c97154752204	1657282723000000	1657887523000000	1720959523000000	1815567523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\xa3e4e1806919fafc5280312c6eaa102d08ea8407c15d500e057815432b5f3c2d83c6d4c47fb570500646722174c02fad7812d9364dd9602481b9202bb88a65d1	1	0	\\x000000010000000000800003e965d20e171848d5e8e29f7593ef05953308a1151f0a0a19215befe305182c275c8f6bb6db1bcb25f32888f7afbc136bbacdd8e287ae41d5cd9bb124bb750bbc05c1e20d6ff0facef681a4a4f29e02edb88ec4c697d577c46cf2f3e67c166af6b22b9ef1b2b8fa2ff5570c85e84513ce3f1583cba90af716f0f481135f4f5ccd010001	\\x67b42a1563cfc2e07df9a8540b3c070eace89eea260c17646cb240f406b2fb645b03a530f519163f275352216f678d4958694eb627423d81950c462a7415fb09	1648819723000000	1649424523000000	1712496523000000	1807104523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
67	\\xa4ac97ec5fa811222e60fc1cb85862e2530ab4e4642c83f9cf2eb958c1284fc732ccb0c3d49a9c38a91a48a0c33bf4f9c37c91cc161beb8d907fe3c616623316	1	0	\\x000000010000000000800003b3bb6d7ea4c736509d455b6e14979d300ed1adbdef1fd30390e7dd124dbd47a8a3f1392566d7abc248ee0abfd88b1f24f32ac7e50651ea11246b5e8c294d73ede69e82e296f86c15f9f8b62521cf6f3aa33d988259755d786aefca65562665e6edacbfeea7a1c6fc7dc3cbcb23b2f96b8be511542e64355707d84aef8a8bedad010001	\\xec5245e432d25e6916b8cf0e90b5cb1dd76adfbc51526e4948ca78e935b86275b95b63fab65339bca950b15fa25637ade69be3d17efaf615d46ffe04360db50f	1653051223000000	1653656023000000	1716728023000000	1811336023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
68	\\xa6c4605ffddc055634459ad788a3698d8c54d6e2ff10c6df0d1ce23b6139d49f15dd4badba495f3070e11ac702349dd6e43baa720307cb7517f035110df81ceb	1	0	\\x000000010000000000800003ef4964216e5b7274059abc7a3bdde710a4b398eae43fa4cdad201c72fd83a208048b09d17535a3ea288c13acaf8b40f42f053f591f84a2fe36036bd9049bac04d3b1d0cbaba5172b754a8bffea60de3f60c910b4cd512f1d38c43e2c9c56f2c240b6ae4f3d2fb762db2d1c52ed31650ab854d8e7c71b9d5e1eb26fa6033d3579010001	\\x1158c4e67cc3b9c410450735a7750a5aa3f92275d4f0241d489ff3bc6d32b2d424fb1d4a7be8361204d2c461027fbc256a639d01e15f3a0d32cb3c1fa3c5eb03	1671790723000000	1672395523000000	1735467523000000	1830075523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\xa7d4ce125b266775df07463ae1a33f35564e0b72ed9210cadf7c58927a908be5ddd3070a5cc506e812b26a2a2768d2f8a64b6298911223c7e90c35d5039da7fb	1	0	\\x000000010000000000800003c5a57b39f27da66e7bbe32b56da52e1f40ceaa2f2cf8c03b4f178df19852426c855f4912983a97aa42060b3bdad7abad3f1559da4c82d9db318748a2223500846898c1f754d392550f453bc93fb003cd148d2a6188388bd85d569efd9e1ab414ca3a4739cadccdbee26094664c868adaa0527aa65e0d5e9b663c517f68b7be43010001	\\xf13f37cea41781f4560ded18257493153573e67e4a2418529b901bec0f20108bdd28c5b3cc9de9065284b24432e8ac89bdb1b4852130cc529e3794e8c3767008	1660909723000000	1661514523000000	1724586523000000	1819194523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
70	\\xa8346b706dfe2866f8bdde3195a19eeb069869cf83c6b25071ab14dc74ba807f82a29fdebdf99609d31a5f21db24b524fb28e90018501798263eb8a98889e080	1	0	\\x000000010000000000800003c9db7fc773371a9ef5b8fd12abb4c8e6f0a334fda4d597844737d9538df28ad8f3359bef60f8e819c897e36e50cfea25a3387397fd0423bb281191cbc884e99d7bf7941996f03557754d549fe21661323975159f9dd27f63f540f39b1d5c60846ce59bbb0ff6cc657bba0c473da2c1e091aea8b1d23d43d49f51465cb2cc5065010001	\\xad886aa73ba7b3076bd92b478242f3d0861d7f41b31ba1599fca1e419f23c05c4726e8f17de5ce3e3242c87ee9b23616ce943d09b84112d7f11ab033067ab907	1650633223000000	1651238023000000	1714310023000000	1808918023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
71	\\xaf1c8f595b74fea2411a0da131a24c11e0b5b75b8a04e52dc1a1181d40bb131085ab5838e0f55c2e10ba605e7f641fb7a839c129d15158d7b92ac7260fc69a75	1	0	\\x000000010000000000800003c62339f6250acf6676a5c2ba05987ab48e50951f385d7eb4080eaabffa52f6fdec8d98952d755f3b6342ca7aca3ff7ae7f2fcc9f5bf550ea35171b642747385a7d58060cbac67a87b1b261f0a26af3d236d134d58b09ad24ca416464b0f43d833ea70d1c1c195fcba693aa3dee78483ec51776fb02614c8304a7ef353a2cdba7010001	\\x998a84855d2f95a902c4bb8fcb3d79e3f90e355533937255bc36763e41038829c6bf6aeab609eeef8a8470e99322dbbd4b7a593395383a0bd2ad45dc9e78dc02	1676626723000000	1677231523000000	1740303523000000	1834911523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
72	\\xb5b407937b8a320e159cb98d10b4933f523d2a10062ae4a4ded0e9220f35b82c28df473a40a11b4a938e6c8546c2459eeba6f56e404f253fa47ca728a73545db	1	0	\\x000000010000000000800003c86bba2c3be91893e2da81ef9817203eb2e9d3d2d47d9a752dcd9ed99abdc13a8613ab754a75de2827dbe4c4de68016338112bea5b7ff4c4ae88bbf22f067cb081a358f9fb7b11a0a48cc95b32aaa032ea6dbcf354a60643b640fb28e6bc5a063fe4f8b7c506ccb2dfa286070af8e792faa00ce1c682d1b6f01537b33ce3fc7b010001	\\x9e656c31367e479e8dc174beb70b3c000b2c86b64abdd92c1ce6b4e0ce43786977fecafded100939b535906dace829909713bcdb274be18cc6eb3dda0f50bd07	1675417723000000	1676022523000000	1739094523000000	1833702523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xb7b08356249830a451bd062aee88d1d03d6658c23cc46e4c4150bb71989e481f3c8abbc568dc8214d609155d108c0f63a12b7177d4058b7a89b8fc652a2cf363	1	0	\\x000000010000000000800003b42bb505499c9b8e12eca863c7c861636c39fb8af0ea14b90ebb7ecbbc34284773361f777241a7d82ddc4deb2d9a41348db7b189ce86e0eb6d7ca9b8a75ae56c2aa0f849f59cde2576c8a6302b7ed1e67903483a2cbb9498481abc491619c5528baa837c7d354ffa580f1bcabb5d3304da3fb45876e4b954f6b5088d9834ab0b010001	\\xbcf45d75b26992686fa7996b7dd82c8f5751d982f52cbd7c4a9e512cc9a1a2ac8a8498d890b6dac2f659a1fbf6960a17345a03285d10ebf7194332021607b30a	1671186223000000	1671791023000000	1734863023000000	1829471023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xc868eb91f562b9723dd0cf1b2289ab3426b9da6cd0e8bf0b54ad2202ec2a70c48a63f63b46465cf7e5c334c84713864877516d0e7468e62df3496fda2411de91	1	0	\\x000000010000000000800003d9778568d17e00ab5f6289ca396e753071e3503c66b68f08658f34f1af76aba12855fde9d75df66628eaad7f084754e15524f66225cdb7600e40ee3c2580cc4afb4569fdd4abef2d312f4efdc989747ff7714fdd9668910435e2945266719d42be75c292c7c500f17ff5a54e7829346fb8d08ad18c51bd74f91c59ee911fa5dd010001	\\x2cabb59c054d143a98f7391e83dff9633b3743ecfd2ec533e5f5694f4779f987f3396dd89a9cfd23e010ed7736bb449932a3ede489b0cbf40735e0384f6cb504	1651237723000000	1651842523000000	1714914523000000	1809522523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xc8d8c183f33e0faf304a588ee3db8cb5840686cba015e10b141c28e4507bc55df008da9f536c07cb779fd39e1db38df4eccf9a5827319c4be190dc9a73e61647	1	0	\\x000000010000000000800003b41dce24773503f1fda7b648814329dde1a23ef0d44007a997988f1a29953964b5c45e5bae5c72c82035098184c1cd2aa3f610435c46dddf3faeafa751c3fe7484b0810efe40ccf623baa16b49dd37d9808fcdc36ca245eb496b86e52102ea399b98e08dee4a388924b0385f9af7501b7a20442b28da7650d6cbc6f20e027407010001	\\x885f3cf80506e82297eb8c1d6a0a565d153469193faec7938216c94595fb4ea7f151a264dc6f228c3832fd6f32d7ad21705e818b638d97d36cc50c225824b60e	1665141223000000	1665746023000000	1728818023000000	1823426023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xca8ca789ce75ade323701e360e09160ca09d3d062651314f595d6a066942834b9b9c0ef033b0883c9ec5d41cface2f818474d19a651eac7981d44bd754923769	1	0	\\x000000010000000000800003cc840ff2e8394a1c86e684e412608ce7cec35aa1bf484b2be4407a93dc110bf2984f6b1257b1826342bd2071227d445aba4b0629dbfd047fbd37358a68ae3231c903960b6e63478f29a1d32b8a1acb809c7489e2ecdbb6e495bcf29bd3f534fc29f1c5c40dae35e07644614631dcf65c12bb831f60b3175e7504b8f041368e4f010001	\\x34fa24e3ce7a5f5453c4389efa316ae3ccf8880c4a03c4c2a2d0a2261cca39114dca4de9bffb71318ab8af7a92402033d499ba52548a1cf3fa26f1d4cbf04905	1662723223000000	1663328023000000	1726400023000000	1821008023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xcb94df5677eadca3b5e2c0aa95c4ab75403696abd9b101f51afb7d62277a65ec2b9dc2a705f83f7d4df2f18d8636c69723b213c2941db89ff467286ba751f98c	1	0	\\x000000010000000000800003e5157e726a7827f3be8801483363870ec0aed29ceddd09880eb2c1b47b0df1ae82db1e15e1cf7396bcfd667251f7763f1de2f90f4fcf0781e69fa7131def53390faa9d878f9de6e06edb6c15e511bf19c9f7f397ef5ad9efa0bc5782ada66c8cb90f173f5e033b5f836539e8f76b532814b3e35132256b9998ea101e3f3c116f010001	\\xcef45c6753ae2344bb2fa1d1b3bc8ccfd988cb525b88c7f761a7c7fcf5a23cdf3d71703f5384c5d3385bf917226478852d881050dafa79a1df6dc1dd8ca57f06	1647610723000000	1648215523000000	1711287523000000	1805895523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xcfc84ff30e50b30ff1f4dd4073532ef068ead1bbd1645a43650b9169869477a0bcb5e9fe0f63584cdf8b1dc34d78c9f2acd8490b90bb6fefa0db85e7fd020c7b	1	0	\\x000000010000000000800003bf61a49aa4ff490f8969a4bc35a642bcd2e92da52f21081e7241f2591101fa2abad27c5056656bcd73017db593398e9fe0938b4b2aeaddefd4b754ba604bf09e9ac655d9d1eea6a0918ead30d5699a9e68f4c4593050480f5dd30da7cbef409cd0ab101ae4596e935e8b34f0034144dca87e035a85c9c2874b200673d8ef8a69010001	\\x5c5751ec28f8bffcc841d9f565295799a492cfab9f3f9325be0295a6855573dcbfab4032bf13cc43c3a5ad6a2832d646f6a56c913cd563086643b05514409f0e	1663932223000000	1664537023000000	1727609023000000	1822217023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
79	\\xd26453d4aa4e111782bd98a0a6b8baa18eefced1b19b4f4bbdb76620bf115f79cc1dd8e3d0aa74baf0729b180e989cf5d69b0395c844322b9c6c306569c87312	1	0	\\x000000010000000000800003be5ab7718b4d3e0867d041bb105a8143ddab25384954f82c26e355ba936c76dfca6d5db0507230f6bac5bcffcb2b99f634fb288b8812e8a98c37bc59d01c5504b3300ce7bb3425e021fc94f404b61d004e9807803b7de2cff36c9a92779b1c4276de6afaaae6ff3025d1fd2f8538eee9417c8d990737aad9934fed0b7c0c764f010001	\\xa6b95b09854fc1f2c4f6afbbfdb1a795775ba59186b7659e8eea55b92601e8badcd3744d4d5f48424286fd2dfb4e7fcc5836004435ea84c2d817d04059ffec04	1671186223000000	1671791023000000	1734863023000000	1829471023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xd37cbc4ed35cefc18399e792153b04c5a36b9a230e1ff7c5db75025e77abedf6091380cfe4cd773ecac974dc25351cedfababfd8980a74525211a7ed420f42f5	1	0	\\x000000010000000000800003db53c66a606c4899d4046248eed442f8a2e17a4bf7914482022857b2b15551f6bbb4ad965180d4ea72d77c586a034a92f7b5f5fa7e8a8dedfca4192c1e76752040906d188f2fb6c41763b660e889ad3a0fc7496c5df04e8c0206c7dad155c96ebd88eabb846a19617ba6b61d141b8e63f160d288d60dd109ad6a662115117619010001	\\xa5781eb4450c13074ed33f2506684620debeb4e4c44e74585427ecff38d884ffa9cfefb4268794a1baac38c752dd04c67af0d648e1becb234cbd586a63f7840a	1660305223000000	1660910023000000	1723982023000000	1818590023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xd31c7ea0ac1abb0db87d0cd6593701a2e941f0d05c49331eb292c1f9aa1594fec15b50645984f7ca233a4c5d79f7a9cac33743bcfc426169e8097ca10db11090	1	0	\\x000000010000000000800003a5f0dfe6850550f8d90e07034ab80eff83c8596e746a792ec8b2e8c86e2c4deb2fc907d1cd6a32c90b125ef0cf11dd8f4ded29541b021bc6d2e329a31cf70d2a9ea8a0b23fde9ae09b439d4c5eb73807c6866a108dd5300a84f7df5e43ce54c0e6b0978bedc98f7b2c4298afad97fe61d8771be7f7c1ff6a717f679451fc5a9d010001	\\xc3546f7de6caf6438775e0907db6a9cb226e7fc2392ead4a0bac90e6ab30226b9bb0c77f604a27c2c26744fca62d3b08e1f65c1c6fe2d51d7c15341b15a3a207	1654864723000000	1655469523000000	1718541523000000	1813149523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xd40ca723310565270c3228fd9f3fbda0efaf6b132d7776aa6c6a2c2976c6b3755a76cc0cba92e690660ee782f8c840f7637ab746e0d19ad81ea81c55f77704fd	1	0	\\x000000010000000000800003e009e26b13ed6690d7c9fc4bd56381536c1204f583db01fc7fa043218d6fd8cb20c1bd5fc6a1dc0ed1d0debb11e3f45f6813fb9bacb09c554c287f1151a399e018b6383a658e1630ead6758adca1484b36d4621798e1e4a540599ce0f058f78bf65e462c5e8d57899d7e79c023e9465b8aae5cda18a0a5b1c9395190ea75095f010001	\\x6cc0cb7b8190414694f21400a96c31576f3a9305dab061849be39a4f829209795281deec2ccc860a98f40a10ec690109233b50853d95cfcdce97482d7e73080b	1674813223000000	1675418023000000	1738490023000000	1833098023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xd8b89447b2b0a1686c1846d3a8049e568fc62e2bc408935b7062d15605d85d7b4eefa79876a3fb5f07ff30a21733464facfec7a28b6bcce06964a08f0dd28ded	1	0	\\x000000010000000000800003d99bc5ebcfc6d3660554ffc01e464ed5c2661f617a6f029102d54ecaebc23d98105451c963afed0a981b24e9cb6f72bb22b4c9e067f9daef20553fefbd113393b1d6d3bf4cc4661d8474d82f609f1cc56fcd1c28d0ff08eee34526d2d6ed884a391cc81b78cb2e10e4e9521926d2785d0a7410a06042c6d231805fd33cfc1ebd010001	\\xe8502e39a223161c57abf1750cf6cf16ccb212655855f9e32c045d0d7b328a48d47ecab3e0d93ead1a67ec99deaa4049f4540d6184b0e5c79faa1228d4714108	1676626723000000	1677231523000000	1740303523000000	1834911523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
84	\\xd8e0077f62928234b00175187bbdf1058e766348e76aea1b27126d3021bc0e170fd1a6b416734dae893c29a282216cd4c7bdbc8b2b46c2bccf111a3199500ff5	1	0	\\x000000010000000000800003983fce7f46b9917fb6bade43768429948938a3684a2fc340ec7cbdae87082f4cba4029f91f05537700bbf9b8d7b4f1af8fbf6eb58381b44cf5c19aafc15b810ebcb92e2af1207f6fecc27ee39a712913528cd34d739dd9457b47470aee464e4f189e01c220edcb7344b1bb87e9f95ca6ca3b6dc354a72f59560b62a64032c2df010001	\\x1b7e0f8f5b9427fe84f463c59c4e684827ef48cb588e7cb8d6b588e9f6270c3448315a993a04fe5e44fd5d4159b635c78868431667ef6c935d9602c450e95107	1657887223000000	1658492023000000	1721564023000000	1816172023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
85	\\xd99058dd9d8bddaaac4b134320ee8f09feb21a8a3f41ee573324c4559ed737c6a8ee7498ee4cae2f5c3fa2aafc9fa6800dc61eaa742d93baca2e0bcf09a54a03	1	0	\\x000000010000000000800003aba55550d20f88f06762e19e847687969e59067148b747a7a99c6e71db18ec50b24cd0f04bfcfc5022a2a6cdf7ec1b708352a3d5e5b7108982e7a514043704a6d1ae97b6cb415e57c1420f0788d0e85d20091abc7574d72c8f858f5ba80616b1a7c44217ae016498a510b1e89765b172db9676e35ec699ded8320c4f493b3a8d010001	\\x9fd4d238dc9ae5e5b2025c63a9772523a47b4c9ef9195d81a6f5808d656be217fbca4977c03f1cf391fe3bd98675b41ae0be83c7c1892bbf1aedb928f6cee901	1667559223000000	1668164023000000	1731236023000000	1825844023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
86	\\xdc2ceac1498c27938c0fc6befe76d5c3f892585924c3c23b313c34dd74dd2d82ffbeee2131d27576c8a30c3887cef2fc30f78d4b350d36472c40aded7341bf7c	1	0	\\x000000010000000000800003c521874a7dad9836ca4315d9eee5b1b3f23bdaaea2c52dbe0ebec1f901f1b4ed5a18912149507aeb34235ad06c5e9f4c016d5a50a34eed309ee06132dec411d896e431bf6e8eca7d9ec25c3eb3ef9fe0b0e88a34a61964250a3736d18d8004239c54501a6f74de1e9a03bf4362deb38295293b3a54db6479e0c85d79cd3c9603010001	\\x6c45e04bad46bf236df07cfafe1ca1b8cfe28727a5106f76250d7fff0ed04e1a24b52074cf9e28038d099a03e124df9e6c56dc82289b29d97a87f114b9c93101	1676626723000000	1677231523000000	1740303523000000	1834911523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
87	\\xe080176e80a1a6f7bc153c197f9eccd7087935cb22a1ed3f197711a3f2a6b69ea66a6cd877caf146acf9ed6869332ab1e95b808a2cd0eaf5d89d4e40a5e32ae8	1	0	\\x000000010000000000800003b6d38c3a90f90a49e1dc071ca846f902c581a78706c973cef853107fe47d2cf36d7f584b16058212d50c06fe116b9a6841f2b485e0ea11f19d8e57cfd26dafd3c9756c43fe7c4c3c13ee2cbf4740d49ac8edceeb5623f220e5163d63967c7cee6691466cfc66c564ac8c20d6c5f903275fdee269acd3b38df25ac689bb8f8bbb010001	\\x8c26705a6e3009e48c77b956a77f2fdfb922e05a3bd1105b8ccf7e71f7bbbffd5ef7c7cd1372e619e384a31f91f6eb15a9d8956c63f3150e82c19fe049740e01	1654260223000000	1654865023000000	1717937023000000	1812545023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
88	\\xe154e0ff693db047f8db719b9a7afc9c386cf9032bca30e6ccb646a9cad74e8d54571cb53dcf289821eb08b6da1aea0d75009f8d1ce629aec81f9e6aaa714a58	1	0	\\x000000010000000000800003c2ac516b56417a7d7b7a7a6cae11730e4384f9ed1d72f896225a97e089f571b444ed2f080c93aab85d011bf6442706f7236e01b0cc47165ebd5279b45f5a62b248a4257066437afd5cbe328fe9b79f5484f12bbf5bda8a7c3fab63448cdfe74546112203c3c1ed5d739567ffe12e6a92272ad2c7f799b7c51ed405a9f566574d010001	\\xe9e181494314713e36ba446b4eb90f426c8d7b830efe6b4fb632baf8b13b6f8aeedafeed6f5c7f13e6ee6a5359d9438d05f0498d74c241ddb579fd33c811d20f	1670581723000000	1671186523000000	1734258523000000	1828866523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xe4b06050d5d8639db8da7f77c74ba3a8051d69127f0a3310a2fab493332e3057867d077d353e6c15a284d9c50174dfb74e39fc01bd54cdf1151b83246859ee9e	1	0	\\x000000010000000000800003b551cc31f0989da0bf8a26e1a82015a6eb8c55ba6c7ec45836e4ee11d1db3b54f77153e033c36d8d6e2988303f359eb17b65fca450fcd86640600ce432124d1dfe5da0084fa530052568bc09cf619d762db9d84f39bda6d64288ca82b8e29aeb6d3f03cca46c48fa712284d51b8709c229f9b6acf2a379321f1746aacfd47075010001	\\x2bfb6f6fbcd9bc544d1f74b2ae9a715a9849262f8f15f59e861426ab3500b4e2afda3b5157e7e13d188f4dd20180239454493c571984a35ed7408cefd862700f	1670581723000000	1671186523000000	1734258523000000	1828866523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xe420290a5811029cbaaab84616854c05b0f4c663b51c643b322e14116d8840cd3eb84c7daa02e1b0c28192457a8bb06fbccbe81432331995691bd72ee2a0ac0e	1	0	\\x000000010000000000800003d2a7ebe365d8a0eb18ae6bf3fb31219c2ab88e34fc59b2b1a26825c67a15f597b95177ca7c7872cd4d33f26e56ce4c30e0b3d06e41622e1aebf9dffa941dc3f8d7bfc3e6ae6247085abe2c548f0ccdfe1a8dcaca6eb6ef30c2c31089f7a0a6edea65359fb9d46d7a170154d0cc3dc4f27fcd35deace72a8c033d7518aac48d97010001	\\x979431ee9460f518a9a9fa9f85f45b7d16659e27eaf1bc8cd149dce92fb2b3f5066787bdcb48bf3eb0a5881b51f2da0f816727670be9962d2e25d7f1d3ce1405	1650028723000000	1650633523000000	1713705523000000	1808313523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xe458f3b95ca8273d28dc3d747058539dcc7820d6cf5d8f02a761e28cfedcf93e26c304458fae8cbe383fa89feb526e4550eb81445732229546690903f39173dc	1	0	\\x000000010000000000800003cc7bf01add90a0eb042bc9842bd3372f6b634b7ccb8116247ae61302bf84b89f594523418071e6b9d32c14fff1bcf3da0578c3dac8fde363ca16e581a2a5f467de93d46da71a7e5c050351861f8e4c08fdc748e57855a8685a138f9cc6b0db693461bd4bc1a2ef0ba0473d617ce66c636f354b5f4857f4e6abd8a520a0b926a7010001	\\x7e0c7ffa9513f63fd59b03c46ba9cf30798fbb7bb959025f0a58724a07360da42e9bdcefbd24e0ac283aaedbad56662d4bac50adc0c4c92f0abf7fcbd91c510b	1665745723000000	1666350523000000	1729422523000000	1824030523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
92	\\xe5ccb6e41a359183b7959f781cf04f7e6750c75357be057e40bd9f80bfbe2653cd6ed20dbab7a943b1fc169afe90e03d1e3b2bd896c8882d75a99a2877fcd39d	1	0	\\x000000010000000000800003eb17e8c9d2766406ecb7a121ea32a3b2fb343a91955251b27d216d28eb25529074ec473ee163375e1872eb6085762ce2da627cb15017a26162cd428d6cf05930288beb6d732a2780730800808cd6657773d4a6a147b6ef8859e2812760fa5353dc2fca4132c10ed6c0adfcde25c681fc3f020280f8b7523c429809d509fa2969010001	\\xd12d19caf7d9bef5711a7798ccf14f0b1c8b5f429ff0ad3a799141d5924452a387bbd5d5d2187f49264fe227300838a2451ce032f3bbd370afe07e14b671e400	1664536723000000	1665141523000000	1728213523000000	1822821523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xe5881d74c2b6a30c1e38212550c6a467bf44606de14ea4566ebbf1d5f1639b50c02767fa671ca2bddd4886fe419b4aa0fa67dcff7024fc4168e62c348e94b05d	1	0	\\x000000010000000000800003cc9c7e79ace8cac7da14848e06311e10fe57a914cb201fae473ac3129637be89e3ae6b4daa36d0342812fec62ddfb5f784554c907669b6891936dac1223467c06660357c322e320b6a571a94dc0d9d146035b3c048b3e81202c74431fea44c663c92a3aac2f5279eaff0101b0eb4f7e75639547bc1c158803b3c8743b56c04b7010001	\\xdfbe119ccf31f3d460e15ca3992aab14076f9ff76fa6b07279226423ee983843b8899f94b0f703c766093c1c3e8af97f80c74cce483ae6db65f7ef79e873db0c	1649424223000000	1650029023000000	1713101023000000	1807709023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xe6681712d271bd0900685349512be9b92505c23a109647dcdce3b3d0a1fd4bb1d73589b24ad9503813fc475defd73ef606d1c30c88b5855ed071e9ffb0110c68	1	0	\\x000000010000000000800003c8d95e029a8d03193340dddc50790ffe0173c6860301c1b6df33bbd90b6e8117a6559970553fcffa3e4d580b9b834168b7c36ad58611cb3f04b73545d071eeb61ea49ba4ff22194c4077a4972227f820c40957109f4cc6001180b7acf02eb9992ae0c55a6cedf32aaa4c535ebbb5002ef7813f7b47ebecfd41aa0689d84fc98f010001	\\xbf7d7538c1057217986bea5eaa7f63d01714a7860b6729cb5e9fad2fb0d69a23b26279720247729c035751aa4d49ecdcfe9bbc1dfa52d93208a5611e85f0cd04	1653655723000000	1654260523000000	1717332523000000	1811940523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xeca40f70474b99a7299701140b8ef1fe4bcb46cf204141068278e4d8f7a74bdea6467f87ddb80b6ab7ab8984946cd2d2fef7b11e702e041af8dfe9cf97fd3421	1	0	\\x000000010000000000800003f18b61ba3a6379b8b0c2a459e0ee600929a36c2daffa0fcb5eee97c09f40f001a51e5b1227ad8641fa12dadb0aa938dffc57b7d0e7e7b8d7f5d53b7401d8bf9ce43af445415ad96f719ff4873c2e0468f3864e8fc14096a89827399581effc79a0af64b16bd8112a55fb4497638413762a8812b826b60f7fbde1f4aefaa037b9010001	\\x0506aa4daddb76cc99ecf8ccb1405df25b103347bbc78ee26817b3296931efe9d3ed5a606ca8b504dca530c9ea72fe4a5ecb99163deac490b2a3b50ef88fe40f	1662118723000000	1662723523000000	1725795523000000	1820403523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
96	\\xee54117dcee25567faf876c9b52c80055a39a7bafe1ee1815cae36355eaee06b21a5539777dbada73a7c9254ec1851fc0043bd78a5ed2c1592b700b88b4280c1	1	0	\\x000000010000000000800003c7a4781fa0d7e2e17cd69736c57075208383cf2b14bfec7bd0f8bc188a6bc69bf4bf4b886f79a4271aa35b9a963a0719e9d1113e43b710582d49fde2842e1181ddc9f2af284242e0371d3638000dab3570fcaf8123a8b5619b88c02543fdba91094bd5a19c5c9aad8a2a9199effbba0628e1b5c629829ca374b3c00a92860c33010001	\\x81e8b6c8f0f5fe332da87e17b8b50e55126629590ab890f2d72e15a459e49fd89768f26adb9fb8ca68cc22b345988bf10948c18f16e9cde65d3d442ccf00410b	1677835723000000	1678440523000000	1741512523000000	1836120523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xf05054489a65dd244d5277b0bfd11c0ac8828f799a5c39f64a3261356398d3987473b5634a0752f0cafa442c2f69afb7b78e43c1e2b603ddfbe6006d1c85f68a	1	0	\\x000000010000000000800003b64a0ab4fa72529e4328c088ba731afa683c951039e5a5ac663c60a73b788533d90822523b5bc0e9ee09e243bb29b39d658bb9286702b1c594389a0891726d75b7069eadfb96897d7a5508fb856c67a78ac7e63ae651ae1d7d0aaf4a8421e8023bf6bcaaf98bddb7734d5254ca71ac54ef653d7bb33afd95745730991259463b010001	\\xf335e1862afac4047b115d3e308c6b735971f83df4406675f459cf1d6a88566841aba342c033badedc66044f59efa3e0af1f5be7fc041c5b3783220069c2af0d	1653655723000000	1654260523000000	1717332523000000	1811940523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xf284517a441ad2ccf77b4d63247769c9f096ced05b47a4b57a279fb8bde982909931ccb28721111bf0aae4f2fef1709f977be6f161d7ff7232f425161e9792f6	1	0	\\x000000010000000000800003bc2bb9284df4d8f42495eac06fdcfc97c146d778823a9d9bd762d1a55b24f14b41cc48cf640d098020a5ddb351de27d4f31e9635f54f7c3dc10b3de507be24481cd15c12c722bb121dec9b28b4ef4eb4cb3976bd97f0395d2d465527b4f06baa44f6fb708314bddc41c0560e98e1dcea4d5845049689dd35e263f323f7e0792d010001	\\x291dc15d580f51ce94f39ab1dca7bf312ae27e93722c6bb2993e6e04fb6a88a51720725e331c5a0b38ec0dc28b0cd3138d0635b3e5bfc75f2a2db75b518b640a	1679044723000000	1679649523000000	1742721523000000	1837329523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xf2f0ccbdcda330bf144878606cd621f2a1e892d1e50023102de7d134fe0e9eb98df22cf8dfefde7f3fa39e6a58c033fd36dac055ac5511609659c01253c57c6b	1	0	\\x000000010000000000800003bcd47ea468e975c5a339926088d3d91a8db8a3d3ee0dd70ff391db46cf851c25033ce42c9071ad0722b5813d62100594e3ceded87cf9a559d758cc980ff85ac1fda9efbfa9d4e81354f90491ebad0243364f31a86a8c80ccec34a3ac0b9946b579ce63afad18587a09d655cc70856d09b7c6e706a2b81b13badb0261e475f439010001	\\x9756da7493f4713b89fbcce9b3cbcdecc02635b34abc5cba23b44b8992056118055b2a8e9665e36c97efed00aea5d60c26afbf4978ed07c44b28392192f02402	1661514223000000	1662119023000000	1725191023000000	1819799023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
100	\\xf5dc9d02a218bc8e4ddb8f967282359fdae50451a8cfc8fad2fbc968c7026952c4fed7bb1b93c098e79f93bda815547411880f1594f4c61cb98c87d5df64e116	1	0	\\x000000010000000000800003a9b016a741bfc3120d38c0ca9afde448db9cc5bb550de77e36c2578509ba70de7733282fa63916f63d9ae52f3a8351b01d8eeb71043e2224a8525f798a0fc7d90e115de120cb71d243e2a9178f4854e9abb7be18f475e9dd25a9c42765e79bd54c11b804b15c477c1421ca1afbbb1386aa452d825dbddbd32dfadde643187f59010001	\\xf306d1a4643ee96d9f48af53ff4324891f7664e2c9aa8823832331e2225f3045c7a2bebd4737530e52a05e41f5671475316d479b2b13b8dcf31cc43f7342a805	1676022223000000	1676627023000000	1739699023000000	1834307023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
101	\\xf8a8156cdfc1d62a2de101ba0e2c572ce9dff05b9fa3e360dc84b3dd47a2f841d04b6e0685c53ef533b5f22347910100d0f4a65bf82880644252c5bfe7cd485a	1	0	\\x000000010000000000800003c0e733a1f7eedfe270af74b2dc3069e2c6493ec44a854ff4a95b4ce11fb45ceafc41d7d8d40d50be023777ca840393a7fd89eb78744947860b7694adb3e888b9603a3b9d80ad956f237b0563e9f21b46c926506ce0cd0797fbac37e812695c621193b9aebfeffba3cb3f66ee122c1f4e91bbb70a58b0c2470682e4bbef2e273d010001	\\x633f89fc462ce3c3dc32e5b0301645307641cc9f6b162ba6d6b92c23195300aacbf51d7b4615acb81619d4155f84471a5e9aaf8dfbe9d2e9edb6abaac23bdd07	1670581723000000	1671186523000000	1734258523000000	1828866523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
102	\\x01d57f026ff1db2f7942e5edb0359ad4d363f8a29924a10e181589b659153bdaea137f133f77ca7bdb6e81c31b0910c685f56900ffd6bab9a596caf1d31009a2	1	0	\\x000000010000000000800003deb98fd384bfe8aa924cfa37e9110be3589776cea1060a66f4da6f5610a9a1cc7000c88a79fe627a7da43a7dce50d00afda36b58bd35f811c446f04174b1211b6badb3af34ce4867e90747b0ade82d485252bf70b5fab09b0f786f7b63bc54ce60ff39daa0358625af0c452fe26818e31a486f6e6f63ee28c711d125060a3b91010001	\\x9325d38737004b369f7ef5535c733b9a27f0e18e7e24f944db1c34626a8089306af003a04caf095eb89a4c787e66aea6c9a308be258bd95d490a5b49414dd709	1652446723000000	1653051523000000	1716123523000000	1810731523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
103	\\x0529d7f2bf16224972f438beb9cf933bba62f06b5a01c01e7e95d4e8f1d4e71dfa6bb14f074eb38ce328e3dee5263aad38b131ad34a1a18caf99b0445bad4ec3	1	0	\\x000000010000000000800003d1652c4d33456821ac9a579353a669e2bd2172314eefc4351f590f39a241be2fef0d0d3bb620e7c7e11eb636443a1ecfddd6f24f333ee4c84db079a0ad0699bb20dbae93387a48fad9d741a9530d5ee39879420fbc5575a35589afab4eabbf7b1aa8643a6f4119ac656077c2b94ce147f0e29fcb667a02812bbf2b5967b15b65010001	\\x8463b359ec4d0d806e4feeaaa2009e966388eeb8ed7a84087f8dee9f1722e4405f656067a06faade2383e0208bcf279229f03878442a86603c60a817c086c108	1650633223000000	1651238023000000	1714310023000000	1808918023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
104	\\x0dddd46a7439ff16b8ce7d3c9b84a4e36014107a2cdfe95bf772d9ad96b780a38c8135f670bf21c343a81a555a25f64e58105723e8f16daccc2501e550f0d1ed	1	0	\\x000000010000000000800003a20e658f948f48be68f681ca93a2bd7ed7e16221fb8ca4bac60ed0d884da4ca07f31e7911a375703fe4ad2be31f18543f5b6f7386bf35cc98321739c77c59b20867de00edcf33e780bad47b55078ce75598380b85d41b3260bacd259c560dba252384fd7395ec912f72c5539271417a259f12b0c88693854b10acad260e30581010001	\\x81b6cc48f85b90d97bc38c833059b02b581f5b62461694f95594f2bc966fa213e2c3ebc990c76a41041c2d54aa3ecb693fc9a52bf8f797ab3277170ec34eaa07	1663932223000000	1664537023000000	1727609023000000	1822217023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
105	\\x0f65eaa46ff4d99882a97701232f5289a43f93b99d82674248afaaa0822362fecff7f9695f47e98d4ea45b3267ed7c8a6dc2d7a497b03f1cb27338821c88d71f	1	0	\\x000000010000000000800003ac23f018436a555be205b7452c6a0a9d3631307c4bf58615323b7f58cba2292193852316314b93625976261da5d9616bd04adab0cf3726d7dd4d20771d96dd5786c10cd8c4c54774c201f632442bca9c856f02fbc91b70a205a94eb319e58435f863dd0a85000c925466524d71bb9d82ee1a989d5d55e7cbdd82a244e629294b010001	\\xc2dd9771a6695a809b982acf23bd8a76ae7c99fdded1338e6c616bb423cac0431e1cc29379579f7debfd7639c00a4baa2f1acf135f7765db4270aac95cadbd06	1669372723000000	1669977523000000	1733049523000000	1827657523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\x11519d2b0bcb5845bdb09bb92c035000ae5a8758caace3ae92f9775df8057a786757ca7b896a2fad81c84302f864afc5a1a495d94c08e4a2395b812845e9b59c	1	0	\\x000000010000000000800003d3e317cf34db72be000e8265f0253cead0a7da08e6f110efa65a93f4b85775fad4ae5b8c391682f4c7769e32ddc5360ac8e60f8396259ca4fab1fae4330b42d8dde3f9a654c2a6497c43ce9f5f5cd8bff4becf1c15e49efd237d01e40fa8ac6e00e81ad640cbf29c6d0e31651a7871d708ae67b15442498501c22d6608ace811010001	\\x73114afea48ee77ddda934978aebd9f89fe3d9c2bf66420591dfdde93f0896982a624e83d8a4e7ba7bdd3445b373cffb59aa08f1e6642aa184b14e518cde4c03	1679044723000000	1679649523000000	1742721523000000	1837329523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\x14f16e379184a27cf047efb959c0d5157730f3dc1d625dd5d5f682b86821ed097153f3155d890ae2d41b2e1cda77a69bd421f75e5100a21d9bf94fe05bcfaa2b	1	0	\\x000000010000000000800003c3738357063feff64d002b1abd190bfb201468473f12894c970f60a5d8549052fa121f628d1a6aad24c67e7734241b7db765b114ae76df8b61baef8544cf706ecbe8b73a76554961f9a6117772ac9526a6116878cdf550c246d4f1f8517a62e2813067310e684ef394939d1241073df550822fb504f0b8816f33b26abd730a77010001	\\x570e0ca83c49802dcca9275186c2b533057bb3163d17ce681d76102e49ad6b79b2aa7af1a1693f1daad43d8cce7bf78093f3a0fd00fe34d07dee98d93b28cb0c	1660909723000000	1661514523000000	1724586523000000	1819194523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x1969401320aef91d109a3933c64aaf8f747acc3c2d199ff9912329852bcd11757baf9786c0e8487bc29d9485db083a320890b2962e8fd4b45d525b92bb70bb8b	1	0	\\x000000010000000000800003c2f1a26bceda9bd38a3e027df4d4024f70cdaabc98932ac80f893dfc8142118674a7117ce9c92c051e432123c5b8f07a21e1dd1bd5adad4e43102c3faf99ad67a142e0a5a5e1c52c6c9ac9027d80a972953dbc58ed459151306a942ddbb0ab9d7e361ea94fd01e8015422117731055b0b3f6a40d3a0f8170202c9033c9405589010001	\\x1703a718d8f03d1a27814100d8b2c7e5f42180fde1d53bb51e95e9cce70abe3225eacf142724ddbafbbdc801c41256778cb2e6cdf791606ea4141b2757e20202	1648215223000000	1648820023000000	1711892023000000	1806500023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\x19c598310f0e53d14eba7ccddf6560505dd2eae44898b3f65761fc896c6f327f96da5ae6f41ea9fe9ff9ae5a1a859a8768e42d748b02121dc3cf3b40e48ac561	1	0	\\x000000010000000000800003db53446959b014809eb7fb61e41d7c903ab7efedb9ebba5de30a0826e13b24f19813b9015426b8a26effd00a2fb40dbc79c9918395be60d2586eebc7f1c33de6418017afb13afd5c68cb4c9d97e3e3cb2c961832f6f81c2865c3076b7caff9597d5779c1a38d3a7c836d3f935237300d2b62804d1540338769c2464b9e6ba89f010001	\\x6b3168327356e74c11337ca1e29292ce85eb036fd52e1ec882500155fd107731d3c94840b80c0b3b914ab510a8744424ccf44d479d83e238a5ffa6688134af00	1669372723000000	1669977523000000	1733049523000000	1827657523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
110	\\x1b51b43adf00628dce1d3d2d6b01647bce78da183eda7dd47e2c416a9521c1f25b5b4a4ba6af9a4bc2ebbea426cb70e51c6809a7f67ea38c17b933e7e4b40308	1	0	\\x000000010000000000800003ddbd9d083ff3e70646317072fb20b8136f868b5569e94a8fa5f3f7cf7e26de6791bb7bf576e6a0c961c21687a5c9fecac31b07f7d44705af6bdd111b7ee1d02c09c2e1d27a02a2efb80619c8e3d267df44bdcfc3a9251a7c1d785bffeaee7b1c75227262be491c8227d4a28a23125a292a1a885fdfecc7e2a5857e2fe8d02a37010001	\\x67eec0b768f469445d388cde66f6d45c0b5c53bf4be290fd63df031d8f44bd1db96f457784f7f8a4759b3206cc37238c310695e955af09bf85c6a4d71c4bcf05	1649424223000000	1650029023000000	1713101023000000	1807709023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
111	\\x268d1c4630c075e234f4c843fcf3f1ac4f06ec7284436317a99ccd81093352159f5a0b83ad262dd40aafbcc15a5a68e21e0d8a6d9d5edd51d8d81ee09c9ec67d	1	0	\\x0000000100000000008000039e23da2a709ff3ed3bd2d77e10dbea54ab813cf1886e9b6511c88c1bdce03e53cf423c011ad0b438696b8d8992d889324712d1b42d5c089d492de82f84a67ba2378e283c5d5519e5f2983efe4858eb2e9df53985ad5fec95198da9f8238e07fb134e0d8dc856acb6a80c290d43c44b421489e12186acd9fdee55b45572067c49010001	\\xbbd4755569f722da56667bdafdff5954c7cd160d17c1fec25a1cb8d799adfc3d30c00e00d0f9575b492bd1fa9b1ea10bda28842b45c7e65ba9ef6162622f1908	1675417723000000	1676022523000000	1739094523000000	1833702523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x2919580e9e1fcdb41643455a0da76b369d0bab040d5b8d6b41124b586f5774142e20a4df072a1f4e0dcdea1443817fa72c3374a8d72b8837420f0099acaef78c	1	0	\\x000000010000000000800003c8547e29c4657747e8c773c0a092d5e5d47548b894214d9986fc1539c9e502666da49818463a7b637f460b5ace587b58fdb9a1e65d9b4203840c1d3df547b0b16843eec4e5ad86bbf63173eecad2146ef9e688a422e999cfa6816ce73d9b1523cecb6450d31447917da954edfcfb1a41461d2e3194e4a2dab92fe4218302529b010001	\\xe7e9bc3cb1d413cb886cc8324ea9cfd956851ca29bd4621d2bf2c40028bd7da13f98032c0e062da707c109898246fd06c657644cb7ac573a547cf7f1151c8b00	1654864723000000	1655469523000000	1718541523000000	1813149523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
113	\\x2a51859ed989e0e0e4ea1c8299e089423104c19ce453fdff6fcb10d28b6c5bc6af16ca52b82c3e4977181bb59132a42c6e7bffcf852300d790df898c7bce11ed	1	0	\\x000000010000000000800003ddc78da09f8bf1e5601606382bd4190726e105962ed3e9d63d96e7c0ab626753331f4ccb6d4bd40f5a99858254299d1f64bd96605704edfdfce6b95a1870b807815061d428fbcc13b0b3b6b3adf84c8f2ffb3ae1db076169b64586da686378595bef6265c9cfeee7084928985b7d31e0f10d57246e5748ce85aaa89e54a5f0ef010001	\\x90485e480cf01d006b25e442ab076ffe29f762e3e92faf706b41af523c67522e6778901ebfa755fe39f56f101e773b2bf23814575fbcbc71a7fcbf3d2b5a770e	1679044723000000	1679649523000000	1742721523000000	1837329523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x2c61bba2d6c8e4d4a0460660ae64cd3edeab3783fb7d472ae111d72141e5be9108f6bb98467c2f2242741d1f745de56cc3a6d5b63a0112b666fdf86e909f984b	1	0	\\x000000010000000000800003f12c08ea845d0a6aec813b8e787168e9bf2be8bb19e0cf40566fab9ee97064d8481f452edb006d77213c5468a0a7489514fd7f2b9c4f09bc514b91962e40f3cf804631e3141cf455341dc53d264c1654e75ed9bfad887dcf700611402b9c14a2f977e33e827a445b6e54f681a44af762d1b40e4a9cdd41fce30becba0c0273d1010001	\\xf7a47467bf101bd98ee9f2e857eef8ed46e4fc3e3164ccfa512538c1fbd2e9d86ef0211318941bc6de1ae4221fd4979407e80e07375e777fc8a48ffd32976106	1677231223000000	1677836023000000	1740908023000000	1835516023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x2cf50308ec5553e6f16f8a626e1098fa6eba3fe1a55437b43427248400417456e1c5aca6ce11b4355392f3f435116801af93cece3149ca5040771cbcba78b898	1	0	\\x000000010000000000800003c7e5faf64c65951a1c3b1d911516a99600adaf5d151bcb49bfe4a72e27218eb3798de57591343c842200a4dc4691378e9e24fd5209d2667c37cc2d7bfc840e3b4809e7119049a428190e9d4bb5c76cde3577bcb025bfa83b748220e262cc51d180ca75ff65f76509caf2053a58bc834b32956c1b6161db3d2cf8f362057a5cf3010001	\\x729affda86288282cf4313af3c55bd4724deefba0835c300c6a2a722d0745d34d85e7d1fea7f6bb39c24d307a206ea66aeef68474ae60cc0fc912be97fcee608	1647610723000000	1648215523000000	1711287523000000	1805895523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
116	\\x2df54a50311bcdfb7970ef7ba3e94b8b75453fecff24e5120a6e823b3caefccbc6119bd1a33f2b3f835715ab5d37cbafb531bbc4964ab36f975141e1ff85d8ee	1	0	\\x000000010000000000800003be56b9980b2b01adb9156e5626eb515692e09fa335b1e07ed51a4531879d8af0bf5940a662e2a64efec4fa8be6b19395dfdb99cb5ef05360fdcea2365b2982c8069d6a64d55454d652328446c928a4a2bb9df6d554a35a49a48f56d92457f973fff0a2da33f57225c1213b58badf57f5799d3ee2ddba01b2e908fb95130fa2d5010001	\\x375365f28efdf6c27801ce9686c18dde6b50327622095d37701192f4429a51d0f16925196455647cb811d288d2f478a30493df2486e891f0a3048cfc186a760c	1661514223000000	1662119023000000	1725191023000000	1819799023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x2fd506f27142eb7bc3b8c29f50674002ea5ced9566a3c549f54db5640d2016d62400a33a9e2bb5576976e3906c36f1a286aa1937b97ce2114bb98bb83cb73790	1	0	\\x000000010000000000800003b64f01ad65df990aac854c1ee8586319fe1d4950bb1d985d7192c5da48f1577f82a442cd2f90ba18c0f36b4edd5e2fb146a3ecb689a211f72f569df4b4a48236576c48e602c050d1a042a9549a0141311e9570924ddad672b7ec7e5be2a9de00221a8428aeb8d99aa66f0904cb1939a17ce5a20b5cd5921252f6207c6bbb59dd010001	\\x29b2c9a66c272cf4b2e277e442521e2243b04f0decaeb43fc609cab2cfb9604694e946348fc50a3bee4755f4a737dd4e7d396f94692f2ea1e2c99c2c2f8df602	1675417723000000	1676022523000000	1739094523000000	1833702523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
118	\\x2f91e1250ba703dc47193aa40f7c76b48c2885b3e1cce2552c8b462ff6bfd1aa46887479ee9682795754e50b80a9fd8077cd1449e44906304568f2088bce7b92	1	0	\\x000000010000000000800003e6fbee0a464108f21dc11a58cc2ecf2ffc81d5d2d4c923571e739895b8b668255d9f5839150b37acaa449ed3c08b5dfb469c35a2144f978118c267412a5f7a306cd12af1c20e806241c6c36e5ea8cec10617c5b6f66c4ac04611e4b95f2526fdd2bbf0ee929f637d2342bab4b5e00025e64e076a620a4fd767b6986cf5c7d011010001	\\xf9d631b79be739ad8f1d405277d9814981de6064028a9cdaaee179f25eef2a56babe8ae951e530db9bbde955febfd7074c9898f266d7bb0b363a74e2a2e1860a	1676626723000000	1677231523000000	1740303523000000	1834911523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x3095648ab01756d1fb0f0036abaa42f049a87679b7b3b9ac5bd507bcbdb977d9b9c1d587e5db737eea191cf292c2c2360e54d3b16e97bc4fb244c2855f6bca50	1	0	\\x000000010000000000800003daf6c07123e98e48f7ab5f327461bad5f6cd6a50c3adc1b67a4b1c0cc3c638937a86a9690d60235dc5c1b29a17dd65842fe961e46a5eb6f916e20356d09ab356aa68f4bb2798d14e2757f357b1111466075f9d6c522c4d756abc0add2fe165d3ce3a1ba6f46f62eb634768888fb28b439a6e578b4da0572d16cdea64a105ffd9010001	\\x3c52d1e23f5fad3969e9751872fe9d7de2edfa459c7763402ac41bbe618cbb36a40905852a3c42cbcf00ffa17894f8bac30a4534b29e116217a473fe8aeb0f00	1675417723000000	1676022523000000	1739094523000000	1833702523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x363956144f8ba6ae7ac84a83789ab50cdf4c1a4faa6632177585974f51259c7d443ffaec3aed6102eee31f2667956e95d76c6b4648ddca730f7a16b586c2ef9d	1	0	\\x000000010000000000800003cf833e5a59c1ddd98015ffb745e6ac90bb93601cf3781d5afe93ba6df44ab690f01d3d83d4c32cb6eb3593b7d08ad320ef3507a7d5ec6604ace967c5c48cff078e40eeced06d62df846b7fcd445f6382028d6f25d614f20d313fe6e0b5a0f5fc6a9257e225ee85cbdb66164cade77bed516b056d11af02865eb5b5e8242b4771010001	\\xda3f739efb4f42325348454df2cd1f633f12a29bdc22986b8e0e5d6ef606e5e16332a6ab9fbc6229d857b3f5ab13efcc8ac19ebadf00b977ea158d929255e408	1668768223000000	1669373023000000	1732445023000000	1827053023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
121	\\x3665be40c9d4eac81b2a70e12c19849492e34cee43254f9eb183c42f5ab737edb0856de2fbecac6f6980201352a27f4426f546354ca0847acc42ee7007780578	1	0	\\x000000010000000000800003d094b9925159babc2d8efa65e036abdd585bfd772ecfcc7321f62767b0b1762bf7590f07bd5c4b9667b42a6d7d1fb6a2798d857c52cc0e0b8a36eb7f2e4e8065f11c26649bbc705dcd288f3538941b8c4dd71c877d0b48630ad30ddcadd61faff286071ebe5efafcc0e8d6908d49a01ba1a3089a8699b2d79ac5e8f40e838a2f010001	\\xea0f45fe4e10c25168b6b2abd5782cce48ed8fcf1e4230354213349e31212a548323baf6fd1a804946cb8ae64fc39f71106f5973e1a9ccb6f13fc5ee34a16f0e	1662723223000000	1663328023000000	1726400023000000	1821008023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
122	\\x3b790e2fdebe3b2bb00b106995d8437c46eae3e82d066158322371787326f957c19cf0aa50724415b4365b0474ceeca5f7b3870cc8c1f2bfdc886e2506cd586b	1	0	\\x000000010000000000800003c710477c287c0011c6541f43e1a954132e9d350f85aac7003c0d84ba7b90a269fb215d7a5f1c5846a7659507e50433a033c02583102fafd6ad6220f71f1f5b4522d3ab3b6a811c1ef782de1d6133a06a167656c2a2e075d57cbb6f133e9a9e046665f8ad273909befd5e0d3c91c626eac60041d1defe29697340d928f8bff5eb010001	\\xf41c2b3bf1529fad98edc7264365baba449d9dd4455ae6bf393394f82b9eb34813c2bc4a869318bab7e4f867c305cad8cb4b25867a3d4da90bd13bbf57f8e60e	1657282723000000	1657887523000000	1720959523000000	1815567523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x3dd50b8b28e41519d6fb54f3b31e77b49703d36d0d1659163073644785488303c4d1f50c74927abd936a682687ded6c52b8f0fac84d1c7035b3b6140e52ba067	1	0	\\x000000010000000000800003d1e4fc72b7e6d5b588b1ee2a68492369cb694837bad64953f93714fd6b4017e94263200c64853cfe05a179a01517064f22e4aae3c1291e5ff761e7f87e33d790952f16c35548910aa00495985b291e1208360709621aa58d664abe723b02c8a32c139718a24f0812325137297e85ac72e4517de7c26045f7e6b11291027f030d010001	\\x7f3c00bca385568af4be16ca38e86767d40f54a94925381d90277b43e3aad3927cc356e15822fef92c2b8c606d6e0ccda4bba7888acfd1aab4b6a0ef8c237701	1663327723000000	1663932523000000	1727004523000000	1821612523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x412d4f9c4f3674d4748b000d9668fa70b1737effcbc87275e4c00d157f6db716565ee159a337703c2d75b5610c66650f0a27ff90fbaddb95c928954c7b0420f5	1	0	\\x000000010000000000800003ce29101d110a5b10356378d0aa5b2f0920eee9f526b5f1341081b43f7728a90ba1eb927cb26eca6a660649e61a3e50c7fef10e996f66e6ceabcfaba73faf686883dc91aebab6752c0b9f564d7a21c0dc882322a2ace917948a33dc295b21e5ce38596f8beafbd4110f43092899e992bc7b276692af7831ce3defb755588b90e5010001	\\xff6b8340d2125c638dd0b44e15bf425a4c6d6fae769a9206de27d872bed64d9b291be9615841f7c73c5e51e2517aed623a8981052fbae842c80cde314c29610f	1665745723000000	1666350523000000	1729422523000000	1824030523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
125	\\x47bd0bfb079d8d2c2148d42e5236e18806b2eb5bd75429d3a9e7fcce76bb5d47bc82603056b23ce4444ac5e2a6dd6dafe588563bd1886184a5fbc1dff27e36cd	1	0	\\x000000010000000000800003edc9bba196e899b8955c9953a00f7a91c30200ff610db05b7d9fefcfa589abde5fadf07ec5cafab4b769c594ca72923bbc09a52f262261776adc349e7a582b79de5b6f73d2e4d0fc9b5206c12acd18e618d417e23a2b4ea7d2376d2a72e31fdbd09af5ae365d8dad58be173e97bfbdf425fedbdc290c9afd92e0fd61ccbacd71010001	\\x13149e9abb75cfeb92a23a32e1d74d94b68d442d748f6ecb9a34aec63174ac0bae1b66af0ae7b2a2d7dac9800de66756da04303c668afb8d45441280faf4e400	1668768223000000	1669373023000000	1732445023000000	1827053023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x4a51df3f70fd87da6b839b8db83c96396d6d0b4e25c76147ff4cadd27b562fcc0e443717f7d2326739a443b20ad5f6c3694c92c74afb0dfc3c39eef78821b7c8	1	0	\\x000000010000000000800003a486c02ecadc408aab76e6a288238ade7a365eba722c08054713c4468a24fd5e77ff89cf29f442ff423587599b62f3f6c3b641353018abedb6780a01d74bda5ebdace1a0704479a5d05c2f98c0d4182028b82ed24f5685edad7ec40bd6f7c2de38d726e98a43d9c30e746483a19f78b97718242db93ce09488705318c3cd4c39010001	\\xdcd02147fa52cb55f75b3a0d90d997763e4af7c4261aae69656b2a34efe13a44848ca24890c64c08c72dd29cfed2c9ffdfde09e2644bc7229332ac23596f8e05	1676626723000000	1677231523000000	1740303523000000	1834911523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x4a49e52408ee23b0014f27110afc432738e464cda30179a5be5d5274212b5feae669f1bce15dd070b0438e6fdc448cbbb164abe51792db57660296b0f0b65c26	1	0	\\x000000010000000000800003d46d603cfa0997757d697d04d0246e6dc1676b38425a82f75ca351354820bce3fd8525b3b7f4801fa97a04944f156f7eacc85debb0bf4b8cca18628854f4ce8f25d7ee945997b8a1273dfa0d0781dd73074558ae657b5391722e49f0ac9195ce71a28c20525f8f31cdc43426e35273e8bad9585673b008a97b24e0b018192bf7010001	\\x78ed155fae55039a6268128ec35a322770de47d0269c83a2e4fd265840be5a02ed80acf88467a665c6472a9dd83397aead8dd90c7df00ffe2b30afd551e0020e	1663327723000000	1663932523000000	1727004523000000	1821612523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x4eb596507e2015ca71dd713f0e8361972f2fa9d61c17b903c47cb70d876b416c48353b9f2c9455c001c5b7e0e92d1f4e92d60ebf541c547166fe26f3150ed01e	1	0	\\x000000010000000000800003c0ed323c33280875cdc48db11980654959f64116602ee9c33adf59b760242488e2e550b82b084311721f69b66d0ed0cbb15e56b2f2e69de543654007c7cd8f405bebebc865aed9dfd9b796dc353560dd2d9bb5cd5c5abc7e4d3aa90951309f3371a47324d6b0ae8c221ba00acade627b8e165168a03105a86a78792f9ed7d6e9010001	\\xc6b35e79b18d8ebf3ff782cf92bacd99aa53e8d0bfca37dfb4c265d948f5abae3901f66d3f8f31ead3bd06e6f4ac6962515f036640a6ea06028323960c0b540a	1666350223000000	1666955023000000	1730027023000000	1824635023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
129	\\x4f91af32efc3c4835e2407a1cf7ae6ae526c7c9d876bf3a853ca4418ab769c7a40012d2dfccba3fbd4836d5e874c7fa8a449a50f3f9acb0a1a9296962886d06d	1	0	\\x000000010000000000800003df7da6d2bb862e0921f7d306413226b3784bfd17dcf44a269176ae7e3836d4a5dc3c98d698d88b53c652f081ede6bf98789687ca1e0b9552cdcae2b838348f91b4868c0e5ca02c8dd71e18cd9a297559970411f3f4b162497e791241d932e1fa638464b1686a250477e1cf4d10373672cdab239957c91eb6c4ea19a4594f21b9010001	\\x75ab704d9a90aee6531b6bb214cd6fcbae13463c2cd03654a9a9fbe4f17968ecaa89a674fbf99ca887c2c374b19c4b8ebbe47372d2d94340ba643d1854d8bc0a	1654260223000000	1654865023000000	1717937023000000	1812545023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x52e551744cd2ef3763bab312aa15be1320850668ede4285a489735118386ae95423f78c61a50c60ad96213fd43e905f07119262c42fdb17df0a29c874ab05c67	1	0	\\x000000010000000000800003ce5fcd8ceeb807a1b88679ecd4d583d3e36afc92244bbea2825640352ac3a649cf0f66ad3c8f74bcf9886f020e1ac399ee7dd982c99b4243b5e4f46faf169c970fee59163aea231721a1c7f016a620a20ddc969bbc2bb17c0b1fe158c8a555534383e2bc3d0fdff29f72853710e6106e024ff5fa7d53e3d7e7747634d60a63b1010001	\\xe514d0024a54649379a4e1e19ac051619d7bf86a55acf70ac5db91565bf09f91de6ed465cc700c107f20c6c52e7a6f116d4e1988cb3feb86196f1b4d3e802708	1657887223000000	1658492023000000	1721564023000000	1816172023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
131	\\x56a124b51778be15beb0c82d9179dd3fd2a0efa2d46ea8a2859ba421c826cc9ef128d541ae1165f1df8657fd23c427c4e5c75cf2928b5059d8c7577479761f5c	1	0	\\x0000000100000000008000039c3b67ae87567aa9bc219709c00f90bd9d6f3a9932f47154c344819318918e523337242d371d9adb56c3dbe6d8ac6b64e8066ae8ba48fbebfe5ab3074eaff26336eaf96a11aa1be8275e19d4e9def29c7a51f5556216f0213f020fc7415bc7f17bb037745297980fed2f4f5c881dba9bb6780dc84cbf1b5348f7d50121a7480f010001	\\x6cfce89cc165606e37c7c5c5ce1970b721224558f3a896b9f2fa8d06f490cbef1a7362815c484b991d29b58c289de808d01215405911f64f9d8c726906b98006	1647610723000000	1648215523000000	1711287523000000	1805895523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
132	\\x56e17de57550b75756794ff6393bcc095ccce2ac3b2b21c9b1e0570dca369da66e56508d1a681fb3daab2d7de195e7f6de0321eb162a40a58dc40ab5fb216662	1	0	\\x000000010000000000800003fb263294b49c7c01461aed408941e7ab7c01c7c586e3f6d3f77749796dbb0cfbb9e65e9c27caf0ab387561dd8fc1867cecd8a6a52b9c5b1b378f4dfdad2e93b979dae40fec6c3d7f1ea457d3f6f0640f4bf576c285350aacc5f63ce914630e737dde9646d1800b7e7e8e5a7d79a0ff06163cf6a57325908e332acc3cb58edf55010001	\\x46d6ed584565f34db3b978312443cafaf5391d4918fa3ef227585c53223b93a48ab1cb47c03f7378048b3be1779643ff2ef5b40f9dca2ab23674c6a4c82a1109	1679044723000000	1679649523000000	1742721523000000	1837329523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
133	\\x5c451c408599e5f9f81fbd766d46122045a5774014014a75258b7138e357380828ab2a79c5c8b86f47c2b6384fc5aaee445bb0e4895d7f96a8a5ac7474763431	1	0	\\x000000010000000000800003c534617f93ec875bca6f18cace522fc5a98a8425a4e61d1a5a61c528ef75e74d38dce71725bbee03894f6f9a5dd677ad7a28f385ed8c52e43efd2a0d37bfd7b596eb47c47b81230e0bc580b0cf8863000be0f933de0d6533af7878cdac1511a726358cc08354b7e6365c86e016da01be45615a5cb3290377217522b9cbdd4527010001	\\x8094fbdc11abbd66ea9f49e7c305cc0d7e3053120cb1baf64bd7120510ca53609b653b6aa673727d95d7d3f5d013be2af97e7ebcdc658c92affe6c598d4de705	1658491723000000	1659096523000000	1722168523000000	1816776523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x61d1c1513d7fc0bb4c0114276a8ce64f2a49627717fa07ddfef36d60b6328631d8f242819ec7e158b93ff02040ec5057491b27bd157d86789c3e63e209f1fa8e	1	0	\\x000000010000000000800003e4c0f17a6372931fa5f66118b9eddc372f8e41252895b6c0ea41ee327d26841de8d294c1a0d77adbe5fe07d9a96b47ba2aaa02b215e93fb91ea660b9dba813b218706b1d46dbe0ad64d7ca4112dfba5696863254a55fe337b6b84542a5ac4125fc339e84cfcb05aa57c0327cd9c597e451e710c1c0139cea29db6aec7989c92d010001	\\xda187069b487f82dccdc42dc87f2975d065a9b982208788fb96f07d2b43c1a3614b5d48d6fc004edb31fd2598a51e8ff09b000835168341c4490603489d9ec0a	1659096223000000	1659701023000000	1722773023000000	1817381023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x671db08caf981ed5eb25d2ffae885c053650b2c7f2c88eb99473f499151b6ef9283b7e182a7832b1f245ef4d03b90348db5b2e5b5ce63d59777a9b065b15252d	1	0	\\x000000010000000000800003d1ed5c9e9c134c00030bce836798530a9f4169e693ea16130cab71f75750ca6e716a24cb09ac13f546f530f3da0f29220c71a0d5ee958b9762edc2c02465ea15f2da7dd0b61efbf4ee9765df1af8599e48c69c66924bfc72a6dc18d53f3abecfa3acfdf88aca2b6a900397020010c6f03319d747a70e4ab3bacec067045c311b010001	\\x04827cde6886c971f961b1fca72346c9b4980624c9f3b0ff672d98d4c2808ff1d5c8cdc5413711bba521fcac6e985fa97ea75fff921e43e2ce7510c075bbd006	1663932223000000	1664537023000000	1727609023000000	1822217023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
136	\\x68f9b7663a229b6072a82e688b49dab4f84878937cbf933a25e7e2918a75268d0f2bf4bc05dcebf9063cbfa7876ae9fc925ac5c0aa2b99ab446eeb9c5bf61947	1	0	\\x000000010000000000800003c337e38cbf1f7d45028b0b5619e72ea661d4c42ff69a691ae04724c0f2fb609f1d1a866910ab3034e7ef0b827318e213f78635923d4e25f3bdbe972153eb0d74a65628b9ddaa8de851a3f02255dae06bcf6a23435f3fbf5fc9ba2cead44f33772630548277fc8f35b211c30c54749ce1f8f71dfa7b90743b81a527beb2de9f21010001	\\xebda3cc627e648e331356e4b0aaac604367542b584235c2ffd7aa82e5eb76d4ef5fe7acc94809edd629edfb41a49a2615ab1231c9a3a0ec080e97b716916b908	1664536723000000	1665141523000000	1728213523000000	1822821523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x69f57be2e4d43825f752bed641b73140105332dc166affb8f4f4bcbc0f532675b0856b02a2d1e6e990d857c1e7f69535e50ac71f51c348d1c4afade2ad2a3f99	1	0	\\x000000010000000000800003c04904a7a981cc7574bea1695e90d554dc91fb7bbe0d2d61cb88ad636f6cc6fae80160ecd13f0c00a79c2e028b7fe940e5c4a4ebd2dcac9eb9b708527645b9969c09f965ec12b7d89c44eb8b4b4d38ad798c2f5c053faf714f7c56c2d08ec1be92d19fc681029b8fbfa1f90838e16896571fbddddbb8ff02847724dd60bc5937010001	\\xa04295dc527bc725ca55dd42c3e877f4a153d3063f2d0f09a921e86cdaf792bf5ae23c906b39f0fda063b2b9e3d37f862b98fdf34e1b696692c81f5528fa4e05	1657887223000000	1658492023000000	1721564023000000	1816172023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x6d45ee014cecd13af1aa0bca8ae6a4016b126fa883358d27e81cf26ac5ecb409892297f55313e6a872c8feacd7a1ddf0908d015eb0cc615d6fd37ed1558f74b3	1	0	\\x000000010000000000800003c47b496b3e3a2fff83ad101e5ddffb981da9d36714570c8d80e582cc81512e2f45bcbfd442515331dfe00df77597c4d2c8ba94f86d9e38028861f6a60ad95f6e5d6d16308591c49a90b0fa81569828cd1abb997b09442d7e68fd9f25f516c9cb082b4f03ad932e61a55f8cd09030d8bc7dd2b26effdf0be71fea319f4c259629010001	\\xbad3a43029c47f02eddd00d81f8ee702e376a48b67f5ac9a36d7ad49bb0ee2d5db0eccb5f08e42969603f1336bd932d3b7e9fb2bdd0d39f2438f44e86791ad00	1672999723000000	1673604523000000	1736676523000000	1831284523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x6e41804106e7a679bc4a49ac3a7d011ef5d5fc7b1342dcac5092f645833302d728282d368390b71a699968fc3ce0051231999de19cb8cef65c2d590f2b4d8671	1	0	\\x000000010000000000800003b67e48b42bc0dee89850b0e2a10714ea8541ec36a0d3934b63b9fd43ff1a67b70d55e9d919854751fcc1977623b161d641d4a94e997184edb8bed27c7bfc72b3dc825f20ba47d5115f0fc8bcec4bb2f8578fe356a1fcd14fa33a9c5ea5fffc277ae3e994a29c1fcc6f9f1fec3b9bac0912560c24f53df752338c2b38dd0cfb3f010001	\\x41b8e70a682d74c35f1683c48144d2d5eaeee70fcc2a69dc95a00ce82cfd69fd9531534ca20cdcd68105b239b1cdb30290bca5374b516f2564bbb06530c2da0a	1653051223000000	1653656023000000	1716728023000000	1811336023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x6ff11997b144de6028e9f5bbd22fd8fb4cee352bc121b41107f227fae96a217883c0a67a3919237656da6661225044f0e5ede31c48e30a193a226b890f5724ac	1	0	\\x000000010000000000800003ba8c8be0972b1f0a47c547cb52a1b5eba519fcdc73d1be9393fa40c3e036e6c07e75e60dad1bf6bbc3d15b08ca205d36ab0e547aa8af2102f596053ed2771e3454c0f44fdb95fc3c763ea30f2f27c4538ed0fd9f1390f379b6e7b26e493f26df4d0a0223d7cb18b766bff0e41de98462f899f2573ba3aafc18407257c6053323010001	\\x32db965802d4fb6f7161e17e5203ad817af5a9604dcab76757a3034d0fe3666cd5d7ac01641c108359570e7301a0c9539f6f16b82cfd5597efb60cba82fd4c01	1677231223000000	1677836023000000	1740908023000000	1835516023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
141	\\x6ff19cc6c7c9653b842e7ab6b718370da6ca0711ca7110783a027830c5f4ab0922cf82244c46ce75f67926852267c2f41c7a392537da03e9a68c2832557f6873	1	0	\\x000000010000000000800003bdfbd9ba37698a96126f83a4443df43dc4fe7082c5c8804716cf18bd808c627f35a114fbfffd1eb271c04b0c5190913d2ff366bcaf8d3c25cf27b9a5bc9c1bdb2e206cb944983a0b5c15b5a0063a333c4fb9f8b1250c6688904f6bdb89301834ffdd95b55488c8a8067328fd428ca0a80e3be9e2959474b86cf99e71b617d613010001	\\x8d017f3fb4f23fd9cf0d39063cde69961568b43144988447e1a8a59c9b77c7dff9e0b5d853ef24bd1e77746bcc2e9004bcff1ec8fc7e81ea9d781c7479918908	1670581723000000	1671186523000000	1734258523000000	1828866523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
142	\\x704d21a3fcde1133866c33717a65b083d856947baf2bc8c080b275a2b3c136f66a6bffaebaa32cb1a23a90be692afe0958326bc2a15b0525563ed8d03dfa32e3	1	0	\\x000000010000000000800003a787214588285cb8f67b76710bc50ced7b0501336814c26128601e4fbb4874e031f86fde6503894edd27725e8aa758ff22ad15ebba515f246e7914a0cb5544fb043e2db0f02dcbc29a38e2443e58cbc2cdb1b6f43d8cd13da7968b214b492df43bf58edf223c25618e8bfa997a111a500a7c00577895087ee140975cbbbbb305010001	\\xef356a374815df1d3e45877629480c9630a85e9a2c07a092b433229ab799a2721c84f774826c4a8b469fc0c2c6321d62cc17ea5e4c01150e9d47c7d731481f03	1668163723000000	1668768523000000	1731840523000000	1826448523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x72c57f09bb36075fc66875b38b402c43d8c5b370aba17b1b40ede328a5a6a5597b8b18f89e3cc1c5be0e57f971bd88c44a593220735f6c003af62e4c38501c42	1	0	\\x000000010000000000800003de21c1a1935a5a4e1474699c0ebb3ab69ca901e1b50558bddaae110b2ef238ffdee7a525de0579cf6312fcd765f448cd4e2c19656753768bb39f853690bd18b4eaa5e0f7d1aa8d394645acf8a9beee3d3ea418fae89c8aa552a1a2fcc609033cc7f9c53de7468f9c063fa25c5907f19617928f14cfad9f2c7a3d409bb4ad637b010001	\\x2bf1931cb22ea8e9a1b591a0e96055eb5915bee2a570a34b177b1af9c9a95cd9e8a0da721d78a6382c430be56b9af4b8c5a0e2113f3493552978706fdba88e05	1663327723000000	1663932523000000	1727004523000000	1821612523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
144	\\x727d508cee0f7865f05ed3fdeef0f61a07daf8fa8f71402e01ae0fb6f2f55c3e8f5c0544e4f6a46ca8441e3f1a42a5b13e8e33c878c6878dde2a93bda3d5c0f0	1	0	\\x000000010000000000800003961cfe33507467c078db79f9e47f2cac330c89f014a28631d80b7ae547269182570c103a97d131a4d1b9a058b2a87b504356b3fbbbbf6719f30933f2fea580a0936ffc0543c57f495c25ec57bf6cf721c342add96680903e86317ec46ff53a41674d638db7f6a49c2706e8c02dec5f0567bd38a9fe394c710733138e53cd9ac7010001	\\xeb7ec2661c814efc200adbb03c1928548bdf5528a8f78e035e7e9f9a405f73d17aa49bb565ef1eb5fca6ba2d3fa5899a6b05e222447f80a9ab5cacef8301350c	1659700723000000	1660305523000000	1723377523000000	1817985523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
145	\\x7579460325e76310d2bdf38e68db4be01eba50a4a96a54e11c17c1eeae70e8cdd370f1221f2bae458a743131a82d3be95a5bd14e17c9c91f3cf12a41a216925c	1	0	\\x000000010000000000800003bdf8e54adadd75abf22c41c8739e37023762d687e0dcc52053da752babce85bea67fbd4a7d5c7c43b5ef21f5c3f32616c870d87b407fc5b7b82c9d02ad88e4bd159bdf658a11a1b096a89ab3870fc7e2f0299a6bc1f2263d3011253b0412c0b1a1c7f344385ae0efb9251dbbff6e600f15db664640754d2293b224ef27da1cc3010001	\\x72c754bb6c463891306259c6ae745005dc56107e3c78260b81b675f91c524a88243de58de656e3aacdf6a3ed2c265ca932ab4576ae936dad273f62f2d9103b06	1666954723000000	1667559523000000	1730631523000000	1825239523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x7a1117cc8dd1082facdb57152c52001107db26b46f25964459ddca8a0e3ac83d2bef4d449ad0649c02b4601ceaa3e4210b1be1df7cbd05f6ed30629ed4375844	1	0	\\x000000010000000000800003ec8709a8d7de5ac04de384b73970073d71db66f95c86be54b6c506938455979ba35e618346944496f7a3dd9ef6868efea330aac180ce9cfb9792eafb7fa4c4d2423206688e852b9447af4f9f0b552d2130a7d2781630a56a22b41b3b8722ec8bba82183bc3986a2659870c591f412916849f1ef46b8a3d2ae12b767d37cd4ba7010001	\\xe00ac1448f3fec194560de5de6a01dbe73e60a140babc56e80de3e4fe3e995901cba34bbdcfbd3e0f65cd93eca90a5571189cfa9c9f608b25e242a64a4c07109	1657282723000000	1657887523000000	1720959523000000	1815567523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x7acd3bdf1727c4177d76e752545f3c84a47e84c2a618d00f0423399c9b28fd503d3f68219c8ca94e6269a970f28dc02c473592f6206576106a7c3efd7306c758	1	0	\\x000000010000000000800003dafcb734903899738f4d7f22d38e470e4c5a6d203364c95adb639a3839669f6d1c74088649709629eafc6d3c97e5f9cb0caf4136960d44b651c3a4fafaa179323cb161730ac8c03959dec880d118fd2f8ac6dbfdae63c33f21e8f9d4dbfebbded4cb888b954d55ae99e47308952465fabee0e1749acd8980767ac56236893651010001	\\x2bee06ec4a6635d4aae412a31072aa70f72deb68796bf5d3b2db61fd4007ad03429fa09200d22e266fe1dfcab8532968354b5f32a289b753b4a3cd67215bd70c	1656073723000000	1656678523000000	1719750523000000	1814358523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x7d19cd9fc5eb369de1e2e73e230532e6489d3c58069b8c1e99abdb9dabe21ada11409cf94539d267b7a7562d11191c6d1274181b70acce783472962da2757bd3	1	0	\\x000000010000000000800003caf313ce6d3540e6813ce968c47d827ec068403ec3eeb0565db36a9a7d48a53fece5db63c7fe1d81f6a80a29939b612ea4289e402e2a83dad226998877a0055d91baf5c5400ad6a154099da31495b7a89e4fb85ced7a71245e080fde95769e6a3d004d4469187f98fa81292a1bd6c44f8662a9cb79fc9686a10dba1a0d75e961010001	\\xe85260f7fc06005ac53e19e6e87ef743fd2664d8acfd21ae7219cf0386c3427e871ed8defb7357120718c9dd166bf863ee75a60a8568fa680ece86daf593a107	1650028723000000	1650633523000000	1713705523000000	1808313523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
149	\\x7e6980db8fb5e0462254d20589ad0dab73e29d77ab6cbf037a741a514999a1d461f4b7cd0183079b5f64f7ee7d66fd96f60d60eb92873d59eefbe7e93cd8e534	1	0	\\x000000010000000000800003bd75dcc7c82393595e997c549b48cedf894db408ec3b546313e6b2f0aaf2f5cfea2886c46ea6975e5c0873faa66be32b1dfe49065c778051b56bda58afef1c5ecc2768285ab5ca6bdb8765733ecff15b539e6f731a6bb61fec84daa319b1c210a617fbf71d26debe78eb92d7e4223c3383dfd6b9d4037aa0200967b5ea4d2369010001	\\xb896c71cbd406e9b60020fa4a18a81b37fe5c4c689cc9d032ba5263f12bc22ed05e4285ffb334f3643fac65252ec4c444f61948e8bf8317b45287859a8d93e03	1671186223000000	1671791023000000	1734863023000000	1829471023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x8369349c83ef60a04467e23722a9ef992b123e612546c516e5b3760880da2dc10d922f70f888fdcb95b0951770bf22142c493621e6cce2fe863d29723ad81e88	1	0	\\x000000010000000000800003b2d4102b1c4ddcb88385b15fe9bc7321520b83ec63e27647e7895a2e12dbbd376f3926391ec93b57a103995316595c3427da6d5582d8eb665ee77f4827139bc9a435b232c2c524d096362c744bf10351a454226c76f0a57e13a5340e9b653eb2c9e00ae190dd179af3916f817acb4b3e667107d78b6ce5d68ef23998106971d7010001	\\xabfe2717477280c7c24cd414ca2de32654d562a56c2e6af8687b44d249d3cba752e153d94808f4cd597ff454c0ee07da0777392c1a2e698386ebd1ead043a901	1652446723000000	1653051523000000	1716123523000000	1810731523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
151	\\x84691ae29fb7c36ee0fb5b83a909b9ab1da565d547a4d6caef1aa9fe43b34eccab143c3953cdcaf28db4c28f88b3cbd22d9b8ded924bbb130dfca9c187308a23	1	0	\\x000000010000000000800003a3f45384d97ec2d936d663db164f7e3e9e47c125b88c6a6e4f497e718fa1d53dc1e3cfa617f0a468b47a398f6116974c0e0ddb854aed199712e5f2aa18e957afb710b79270b4cced83e7d6ef4d653b7e013b3c4afa023c17f14bf94bf42697f8e91ffd6fc5cebb768e0e7cca9ec0077e0e177c6cf8f56a72648040f4a8717f6f010001	\\x5bbc22fc8b3e03722256c93804ef1c1663c989a4abc89111b077672e26526c081413c4a9db46544f995f211d5a0c34c87cea0bb2d970307770c7a63693942d05	1665141223000000	1665746023000000	1728818023000000	1823426023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x85856bd2d719cd593b695b5d1e70ace3032aec8c635f02eea3c27b928a9f678f712f9ac5cfd9429bc59a6320475e60d6f109aaafe3622398eb74198344167230	1	0	\\x000000010000000000800003c2dc3c277b7f6b087c26ba189a2bef9c1e38dbd34ae643cd8a5f0261ab6e405c5812071d319569df561f8621744e08a21f65eba7f7f84f79ea501804b11a06d3438cb920325080d9f7e15572c9a339bf42b38d0ff95a768e2203952772bd5d7ff25ec265f0aa566f9aeb11dd8fa560335f1b94e7da18ed3596af6fe948200f83010001	\\x316b3ace498c6864b351a446bb1647a5e7198d8d68c2802098b64103ead7d952ac44b3c2f802ad0346f958cbcc1f66eaf80e2e9bfee84d3531f963d02d4ae706	1660909723000000	1661514523000000	1724586523000000	1819194523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x858534863937517f82504d5c5f2e01371eb4d084c792e08426bf6b663409e9f24e0ef52c810dfb2253a394fb380645afe2ac9b281638d864f5d79b521b2f0dfc	1	0	\\x000000010000000000800003c53943177650ebd998785452bf2bcd26b141ef8056440c65bf4316c35fc2d99ca6ff21818289340a266efca298775abf84fdb916138feb477b80c65f4872b6eb079f5a9c1336d36f9513925bfc3d8a837339cab811098e55d810fbe3e83838382989fdeabae82cbd0c0d72c3197a8591f8976086db95e17b7533385579712be3010001	\\x113b45bf76f045b24ac30cb5783e5af950d1a422478b566257dfa86140a03a3ff6e7732144a1a185fabcaceee6b726b3b779b09abf70b67fcd101fb24a284d0a	1648215223000000	1648820023000000	1711892023000000	1806500023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
154	\\x89b9a414204b4a2e704d487c27ea780fb3e52248e38ba286cc5fcb077e6c528085d96d1d2f0c66639a13e8a2ebe6b068f3367eba4546082efc7102f07f684ed8	1	0	\\x000000010000000000800003e8a8ba4f69de8df0b3b968a10caf460af2c42e47aae9ca2c106a31cd49458c6b4eab257cf50a1f3e9a41390b26224beeaf71c63415536d4d487d0b8882c6410372bf312cc2f85669ab15c3da2980a35870b681b17265f1c45c3a831b9d44c124ce4f00f947300e3c154d5ef2fe264087b23e668543fe6da6866872dfd8b7a49b010001	\\x1c8ca7931206b57a00ecc086f17f4387690c09a44915d572ba24ba80bf1b11bd6bb655e4102443457438523391f6a7d8218d09e86db082b5bf82a17829e51c0c	1679044723000000	1679649523000000	1742721523000000	1837329523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
155	\\x8ab545f885eec51176f57ead6ad63304028fbb448beafd5a37913472a711499be544946cd08331cedae57a15e73a0d922f23d972a34bec72eaa2ca26ad88541c	1	0	\\x000000010000000000800003c6be2b10b2f92561d71480b980644d80b2fa6e8c1a019f3aa1f68bc167a10723596f3c54dc88193f5c4c59d5d964d5d4df7ee2f9dd80098b3426bc1e8ca02e7964f1340ca9c2a6a352e03d50131fe6816c8d6bc6434e91fe014ea3e26d860187c720b3ccba5e24b8f4ec142b9236d36dd2a65a235221886845b773af276cae79010001	\\xd6fe6b86a1b852ea35ad8dc1b206f2c6961ac294e90cbae0f4c6fc8c42c04dc6a6a9fab4c8d70daef24be6ead8dfdf3fb9cf3b34e84f05fc5205f6e613890507	1677835723000000	1678440523000000	1741512523000000	1836120523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x8acd895dd3af5811aef787888c136e59112bc01ac711025c5177fc28734f4223425c220baababd6b8798f46426854e5dacca1f1266e361d9c512b6d0cceba1bb	1	0	\\x000000010000000000800003c41e0db93402a35fcbcbd47d547123f128cbd18c07f206851125809f4267196668a603618a4db7427e1f7e82e904d45b50306011e07fdd37ba82b0f8ec72652986ecc441ce512b4a5a9f1aafad0382210f198be82a3d165a18d95fd889e986b219554f60fe938bd92a7adc19551dec86c696916a6cc8462b4d036b69a781101d010001	\\xe973636acc30201907a62002dd677c0358fd809cbb7593ff2c6f6d820374179d625ebd087a356808de2cd44721294ca612cf4c4f70d3a482ec803ec80d5c3b01	1648215223000000	1648820023000000	1711892023000000	1806500023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
157	\\x8d7933f585e2c370e0ca71b30797fa0aa6648fefce452556e9f90352de8b527d4b984a6e31ab4388d1f82e215a52e06504107c3aabc5d04435f18580f9dbaac4	1	0	\\x000000010000000000800003c79f93c18f2a48540df6bf32d69a50501314bb409419b35437fe98de96299aa3a56cc9f0aa746adba3cf172fc6fe4360e36f651ecdaaf7bd95f149b449ea0b95f85082276c1c67ce5f7fbf267b3b7e42a745d838eadc0debece8d2f0b59da9dfd05f432521eefd8a1c1f9ee8b0dd33145070855bac48f3399bf4c020c1d9e60f010001	\\x22794e452dc90a9c889245988744184eda093b9fcc21f7b4ab1f49188ac62f2d2f3e0a71abb0f752c9ce518e63c4f980381a489afa0a930b696f85a153226f02	1663932223000000	1664537023000000	1727609023000000	1822217023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
158	\\x90d16f1b75e8e1d1a8dc73fb203e97977a8fa77b566cc71f8371bda92cdc8454c0033390c0362593ac23f91922c1009c4572524f07b615dac59417fa858c46c9	1	0	\\x000000010000000000800003cc6e047d752c51508c6c2b363f443f4dbbab2804d88292852cfe119f21d2d4a48e58a6acc7eee7489eb099d06eeb849755a3b130ef3a17d14b64f34c16e0bee9b1a17b7f3cc74d64468a643442b60157e3fa87c3eb2ecd94e0c3d4dc931e02afcbd683f3bd967d42fbdc7fedfaaf1b5322deb0cbef00b782011c52f190b5d3ad010001	\\x6d5340c752ed8034fe502cbef9d94457537bf1bb339ea85230251a8ec382003aa982f5bc0ac479796a5f0e35a5d790956779441ed48657a7db0ce76ed877fd0c	1647610723000000	1648215523000000	1711287523000000	1805895523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x91895b67b458a9d2b55794f2be0d95bbf3f53f412820203866faebb03dc98863f774fd260bd0abd5d159e964e9ea9244e620758e326356cf64dbd2a35cfe0a07	1	0	\\x000000010000000000800003abfa0c691cb01e49bd2161c9013234f96681804fe0aa135c5502e838a01950d7e3a532d26838613ad7f4fdfdaa7ca4318b4e404b4ebb3d915f693285ef0c44e15b52a77248bb573c036108d7d3887663350ad898e671335e102f160a320a929affde15694dd2b323b14c20a0bb33712c4f87d1a56371478ab0f79e1e89c1e529010001	\\xe934cccae48e7c501d43045e538f14bc5cc9011b6c78308396138fcc66d66947f8d5a0e32786626636f1e2ad923b7cd21ee4351db552d62ecfd43b9f65547f00	1678440223000000	1679045023000000	1742117023000000	1836725023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
160	\\x93854cb6eac810e3fc18cc1875ade3a999ce4b227f001ef116ce938c8c920daed208970aa2c53d9676520e1e04b07fbc653fff9194f69dbec4d2a886cca1a0fa	1	0	\\x000000010000000000800003dba9fe511dcc2a5cd0b3ef2a4174136262e8cc838f1d54ef538b224f94fb523b849d6a0068fe1b4296302da52efda95b0865f41f92037483d3e7dfba06f79c8ad4495c2be588fa7c89ca8fe95fa8e956fceaaa3d839f64046ac32f273fe70c2cca77c8707f28ff67e151b75c4adea087c5824ff67a465340eb51447edf938fcb010001	\\x3f8e4670cc52eef48a72d772f6f6f272b09566646bfcb2fe657847828477ac6334ba55ed70d331cbd627c147db93c4a534e554e2186782de39c0ea9b04e7e400	1665745723000000	1666350523000000	1729422523000000	1824030523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
161	\\x9355445ddfce50b123d5b1880df1e76d2a1fdbde0953ad607cb196217a55f2261fd3da5ce98f77e65530ffdad279fc21cfdc1336c470b641ebcb146b00ccc9e9	1	0	\\x000000010000000000800003dd15929148a951eb9c62a1783bd2fe50c1471a9befd351017bcde8de0bca4984a009b06d45a9caae3d5a59a98f68ef6f2e7f043ef50e39a80c001990f4802800367f02542c60dcd74ab477e8a19c6372450a88f55ba2e2f115452597d12ca398dc634fcad09b89f404c8ca70d8d1f9a1dc65c40c834c85a3bb0fe70637c6f95d010001	\\x641e5be646da3df828770bc58b9ec5d027ffe760ac4626b297b67a9fcec3042ea3d4f3e151ff629e3fb9c6513b27a7d294357af28a9555f3afe3f7074ad9e004	1659096223000000	1659701023000000	1722773023000000	1817381023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\x9bc9d178aa4e9797d7e91ccbeddbd9de2ed39e6845554baae345daa8983d298d8044a2c9d87f67924c0a06268b4fbf58577c2e6b919e44e0a038e771e66a0fd0	1	0	\\x000000010000000000800003aab4e6a7e61d7c7baee3e8200ce631df6035f6acd58f88c5e85522242ad14b870de5b9ac2a3c4d9a15e9d8a10fbfcd27c3dd03dc439ee01426f03bfd69fbe759ed3bee3a109c03203f681b21967bb8559a97e418c89bde51eb9da360b72d8f2d7a3474d546cd1f48d56639092b29bab963fd7c3743b3b16547b72049e735d361010001	\\x315f69f4662b7d92bac947085ccdaa0b14cc8838f75476f7acd10a1579ad693f36576352a6ea8387c6a0649f63c404d4ef3b47ff4fab3bcd5c403c26b8aee102	1668768223000000	1669373023000000	1732445023000000	1827053023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x9cf5e410b5ab6b4908e1155b87d0f0161f215830234bcb574154fabbabd58492288f3d186015d81e6ecced4a6cb0d9c6c11d1051f34786f8c2262ae1165b714f	1	0	\\x000000010000000000800003b993d73e9e39a696b0496f6b1a4205d4eb3c0183db038cf18c237613195bad1843f90c8a2667b84e5051bef998258ecdaaf69bbc04ad770b04989b87077d6799c9ad7dc5468f57e7ad10c61cd1a6dd6968a21cfe83731bc6342b4e441f7d163dbb89bc411d830bb65ca66a13af575427f4ed4ec175bb69a645452c07e1cc3827010001	\\x89accc5e57aab5764ba43b1655a2a162d56def892aa6bab5b0ce14b5959339aaf2baad4d4cf9cfea8a60cbb55297f28eefc40471da65da77ca5297a07b89b30e	1650633223000000	1651238023000000	1714310023000000	1808918023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
164	\\xa21d12bd46d220f8ca80967f24385670ffc33276e2837604e27f965fdcb3ea7204f7943572af084f3ed1778ea23fd833fe4dfc18e3ee1671d38e2769b7824fe2	1	0	\\x000000010000000000800003adb14133bd4e5d6a8cae972b631bcef7eb8cdd2b72e8a6536ff3dcad76455a94490c5f4151a3585a7bc0212add49e4c2b25b7588af4d5ea3254c2c19f5df7db1be7c9de60fcafb697b7804b1c723e189f9b72d38907abb9e0aab3057317d479ae667534804b2befdb3e499585587dd14d430a0aacd9033d4b582429c90527aa9010001	\\xcce57fc3a1ec1356802def161abf9cd32e166028fabddf4c1e57d842b147b3d82921fbbabeefa96c364e0bbf73eccbeb40cc11b66672ec71798f355c3da04c0c	1668163723000000	1668768523000000	1731840523000000	1826448523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
165	\\xa6d16987b562deafeb803fe2c74e4ea381b4871a7440c825782f3a57d71da017bffc636e09ca9b50279ff0f78a3ab1016b467f9969bc9e1d66c685d477fd787a	1	0	\\x000000010000000000800003a5b24dccea11fcdf7538e347486e5f779b0dbc5302be1c9db8b9dc05651bc139a2d0e756952a7f396f0b7d51bd5e4ed20fc40f56eb9f764b103067a850f6ff5d71abdee775571c916764dbd771e8c348acec8289705c80b88378e3b589ee11918754060e2c98e57249cbcccb5ebb39035c715d22748aa7fe0be25f46a2020a9d010001	\\xa6994cac511bd550412f0d7088d60cafdc3782e197df6f5c3795dc9645de539d94972dd162bea671b6a198edd99b81f9ccf91d0d09a88151c124460c9611b209	1673604223000000	1674209023000000	1737281023000000	1831889023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
166	\\xab9926cb319437e11e4cf0be0544a5eaeb06c87d7aa21409c6522bb35418ce5e16ce9348383f20b82fcaa78df4156ee7de95df8aba597a2783066bfd7c9cb192	1	0	\\x0000000100000000008000039eb9514846c3f6a25e5dc3ba9f7e8e21ae0a0f071f5bb7722241ec97b6a6deade95f76a9bcd325671895c6b6597f5dd8fcf0ffcc2ac8dd7d9f5a329960f16a08907249bb917de880bc3663c527274c23ad45b3110db794449f6c9ca9f83b64a5c2072a1422cc82e9bb9082d6fb243682531ead96658e0235bd5d8bca322b57f7010001	\\x70b09e636354e1b9828f6eb22efde0f0a0ca20a65fe22da213f88133e8153e15d8b83cfbefbaba26229e17a518d524f9ea506848bffa5c597103942fc792cd05	1675417723000000	1676022523000000	1739094523000000	1833702523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\xab790bb98945f5a6b574a75f9c13cb6077dc7041b08d5eb93724595c041f51a1e80525bc4a0b91c0d6a8649c7132d74385ee0f6213d592ab7ef761e6eede20a1	1	0	\\x000000010000000000800003d759a600bb738509777359a718b249f382ace4684a170c21adbf4fc58df8edb4a561a9657531e1bd953e2c7a214437745f1b59a2ab0eb70eae64be7ad1f1db849520ea6f5c7b6023fbe59b98b7567a9c66a28843531a01577b7c089ebc0f53b0a22da0595eff7233823f8950eacd534032ba0ffb9a447b1a8297123af96eff27010001	\\x2fd4a5b613f6ce0f9ef3310aa3702cb85dd66d56849f1fd5bbc638b0fcc22b2d96fa2a1e7c11fe36593fae7b67e4ef51e1e68635a1151ae5519d44d3823f170e	1669372723000000	1669977523000000	1733049523000000	1827657523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
168	\\xb005f332bb9699aad713f4ff76a20c6a79c002ae388ba833a99636e843fe6bc27471caf3f89fdca5995049b59154d4060050b154bb8d4042aec6d81de779023f	1	0	\\x000000010000000000800003d2c77c137315a03f637c536d232fd7466e0e1e84544c186b23471eb347b2b86358f4277e1b2a7e52486eb051c410dbd4ce4cd4ae9af09f99194931d3ea66d3442abbe30cd5274f93ba6f64eb31c6640fad78a36ee26e7a995e928b3c1f13ba2f77371c805598272b06875d676279e8781afcdfbb88033d56f49e3eb365112f41010001	\\x2370b8d52d3e8f9d34a15ef362ca042d50b32f6f9e25f9cd5fc9647d46e50ce3e9869b9514d2f072a153eab35acc2a9b5bb780dc6cf86b275b32fdd2332b7406	1660305223000000	1660910023000000	1723982023000000	1818590023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
169	\\xb11ddde18874f41fc8ac6a958fd8543a61298e64c2274134e7ab7c42b48deaaaa1d8db314600a9cf75324846ba9295b395f2f63062145047a873bd97eabdc658	1	0	\\x000000010000000000800003bf0785d4d54dd1aec02be21a6bd128890d27bfce3931b6888e77c0bc4ef8b3716e822c75ea215fa040809c0c5ab19b2b7c46e43260cc95916df273fd12acd7823e0e0f3498fea3f9afd9d7b4e0c32253058678350c90c53ac6d336bab599220df02ceb4c7650f6abf6c76b7d59c5119586e88de1b3e4406074a94682f95df171010001	\\x97cbe97f70ba5aa0d65b77a1478cfd3aa6f62d395325a7aa1564c787f9ac1bdab35376937728f144c27a89de8e87c15bd5b485cec1e22c9300010a6f6db60102	1654260223000000	1654865023000000	1717937023000000	1812545023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
170	\\xb33d36b1f1020d77ac7d5a300c324f8372194a7b44e5fddef8c3c30cdca8536448c0a4afc103d487272b6f980e5f04a1744a5b1a60052fa9e6924c63c8a01a55	1	0	\\x000000010000000000800003bea4a1ce14b0efdb4b51db43ae5691c9bbe5f67546bf7acc56230640409a70ca5b6a4cf57310e6c00aca8b16807df814484e4903a70fbf614b332bfc17a0be78b649624dbb7c508a971f3e5066b425e86e5bbfed04e898619abf5541d15edc93130d3a33b33a5e961da74d8d9672a6e2980e99320aa1e175745878ac86f863a5010001	\\x5fbbc1a6dd6e9ea652761d9da46d67995e71a0b838b911b70c39d6f21c859a2c5c3cafe1f76bc31169938ffd1873f2c6167ac4ac804510f4b354a82623a4970b	1654260223000000	1654865023000000	1717937023000000	1812545023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
171	\\xb361fd78d6803e913eca7e45111fc5938c2127401b9505aa588db3906a412849f6adfaf0d07dd68cf520d2db50c9d7b37dfcf979c2b6d5fbca2af44b8857b4eb	1	0	\\x000000010000000000800003b8d4aeec61958016e489f682e5fd9a84f29aa9b488537eff5f7260514a41ce2dfafce40256d3c43df47a84b9fc33282215a876bb79bad0ab2178e99583ef59db103099c45a25ccc09b58f94d2ddbd39df2e143549fbf80a39aa79b2b1a073fb227baf5df22dc87f8d918501b3a0260a2864a1e219aa7d702e14d1019aba38559010001	\\x404c4d49bd54ab6fadfc975110ad0b47ed63eabdb2231f4dda76c82023e3978522f844d6214f2a2dfba6f948fd952bf44761943b7f7ceecc703bfbd0044ff60b	1670581723000000	1671186523000000	1734258523000000	1828866523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
172	\\xb619c43508003d94f31960043df2ba63ad295839a1e66adec3c80e9559ff8baddefd50aef54412a355a0e1d3b9447f1b6f29a2befd89bfeecef5933d2bab3597	1	0	\\x000000010000000000800003b2e8579246debfe994ce734cbbb027e0b6e7850a2b6b08ff0507dbf9b27c00952de19afc59564bddfe2f31b027bba5fc796db4989b79bea56444940855852ad259bebe54ecc26b57800adae1ff6412f793cceb841518cf633c17f671f4bcb71716783fcc79fbd94db75d1f574130432e404abf219156a48d99a3010366a7fe73010001	\\x0331b7b67e1b95f65110ecb91a6305d8d760f20e64010462df252ce48e003b764888f4fe7ca20472759ad34d6bb61e289af8a3a14a87637b88309c4be1f03d01	1651842223000000	1652447023000000	1715519023000000	1810127023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
173	\\xb88561ac335fd124336c108a5d0db0ebb1524c5015ff06bfcbb16a5b8d5d27df8ccec7c974c5e30725721dacdacb0c0f7062fcab6f8be3f269a3a9d8fc03e635	1	0	\\x000000010000000000800003c8cb3c0c531aca0551359cd5c372e807c4ad6e437b7c241d723037338e315387643581ed3efea6f327095d072e141514db29e552fb57a4025bcc3e6330205b056e29ded66430913a016c1440f494369352388f14e61463b10562268bc401053bd8d946baadc2ff51b5dc693068e50d2bd96990d44f0d7cf9f111f7869e163303010001	\\xfa9ac8ae0d5e2f052600192c93c7b24a309509b256bb5801ce3fb3fa65de649bb0ee0551ca9cbac8d36c6556254ce4459d7cbdafd139f0c66373c88a2fa30401	1660909723000000	1661514523000000	1724586523000000	1819194523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\xb9417d81a94bb72d9431b7e222197e912a38cfed4968ddb7bb88330849e2464f0dfbe73d8e115cda35944e1ee056e0795f1639e8d1e27b0549687dbb3533fdcb	1	0	\\x000000010000000000800003c40a821c1d332fa7bbfc5dad9d515fc6f37cb9a19ac17c401345e7dae584a2ddef95d30e0a754de89b38781b27f95161646be27c65251b49718fab9a812a8447e8e6445a4e1c6b28ce3a8ca6fd09043ea4de9839c0807482e96860e8cc1af50030639e6273ff44535ba29b94e608bfb10e0ec8ccbe698ae031eff932c701bd7f010001	\\x4cdec4c6eb628ff4a85863b4e94ca81105bd74054ce7a43483df8611a3afffbf7ec064ad8dcef6ea82a50a683cdde836508d41a024dd4893a41f84b4e80d200a	1654864723000000	1655469523000000	1718541523000000	1813149523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
175	\\xbb41ec2a375190bfb55bdf7a92a8c8e258e95a15c8da30815b143f62ca56955d808d946831d3bf8b511237f510499ac3762f2a7c006b1c183669fc8433478516	1	0	\\x000000010000000000800003c2ad0f4581c6130d87bcd90c8b4639257f19e2429c0245822a849dda24c9440fdb20f5d8d5b554a8a3ef4227df8163d849824d746a46210de2895ddd609af75f99f1fa2e7ddff26c9857c7dadea523271395e8225cbcff485509cf061911101510dc684afc78a729499b1afb426ae5cc0027bdbe0e82129ce8a07d44546b55cd010001	\\xd0ffca3306d3df149c24faf9dbe7b3293b6b67bf07e44649a6cc1dabc5c8924ef5864217aacadc25cb8a447826217aa92fe664d4a551930c34ed32cbb61c8f08	1656678223000000	1657283023000000	1720355023000000	1814963023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\xc0d9c7e4a67f3df5da4ba33efce5582138d7d3174a6207c4f83928cdd0ca0c3e707e1d92754ccdebcac8408765436f6204197e0fa43fd259df50366520a47b51	1	0	\\x000000010000000000800003a4a7b9a43bceac94144a8ba6a22e2a62ac641c31014f21ae0896e26fac6dcc120d10fa6b8eeef9c4a1176dd5993a2f82a9bd139a7a4768100608a6063564ea28743f29dd9cf5f9f30aa451ea87e0567e0169d07b9f4d0c6a1c8f3850a30c5c56fcf7b79ec64aa4613e77faaf72f6ff20e4f7fc7b4674df727741039a399bfbc9010001	\\x39048dc286e48d21dd42dc3e0493ed288d1a599746f395f91f4e7e32a4a5d6d3fd28955409b38b76a202d0407517bb8891be41fa57df2b4630b9cacad4887401	1669372723000000	1669977523000000	1733049523000000	1827657523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
177	\\xc239d7b0552cf8bbd9b26b28ebb5885537820c5c999360be45ef392587b54c19ef92a5516d953bc3995c65d4231b06d0e36fd404da8edcb6a21e23c106d8dc39	1	0	\\x000000010000000000800003eedeb3efca3d18d6a7088ebc7a9fd5eda4a2d3fefca3a7a6e492fd11bc5acd2d77aa3051e444f26d55592ee714294698a704af1322d2ab386167a94fef186c8edd9fefbde44235096f6a5f17965e0cd5449831f74a07799f0eb33043097e3f92799c4bb5b4481648f0a5279acefba65ff0a14c97a3bf56793543c106493cacf5010001	\\x94ea41433943fe51a52cec8b2199f55c83299b20421b9a5e8d332175930398da068e2bf2111558c5508435e5469fe9e8621e3e6d627236b318c3208fb14d6107	1672999723000000	1673604523000000	1736676523000000	1831284523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
178	\\xc41d1d85751bb3546aa58ea4b865cb241b3eac9ec613ba61fa4f524b727abfe2eb26db65375778d3be9162c61ec547a79278119bc46ad06122b0b6fdea124534	1	0	\\x000000010000000000800003cea6a17c3ec4fd895b0ace2b33a841c63e190b5e6d115aaf5712ef22bed6ca4ff115b95a69a1e85445caa9b5c73d2905a5b0ff1e83a24bfc242edc4ae19c3e680afedbd2759f795dcf68678a3e9d92cfbbf14900dfd61dca174ef90b1433f3c250f0e7f1c88c295a954cccc3329f967433073364208b33bc3bce1620eb150e7b010001	\\x5f03e67b396f402ee623fa1a1f9d60fee202e89109e4afbaf9eee2c8925f0d5880a6dd44a8d9a2e4100bae8f9b4507e2e4c0898582eb09f3af485a9a9b66db04	1666954723000000	1667559523000000	1730631523000000	1825239523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xc5417e973630162ed68f9acc9d397a3c160305d806806a85a5624f241d296021b6789c13b126ea6ed46bf38bd11dff81efbf42be6c7dfb625369739c65f7831c	1	0	\\x000000010000000000800003bb147a1c6d6826dad9389194d1841f34685fb370f219dd17e47357636ce79ecc16a6992869992f89a1fb0d7b07657c9b1e438ac5f085b59991694eba15d562aceb675df79619ce02ea127ee0cd2cba06e3c57cb26b6b7d5ee38f766315dec4d2f5b02c8940c4a701b68d41cef5f4670788e0a3329967a56b38022d3521a28b29010001	\\x92d22face87ae73260aff0b91b795a1c11baca4ffdcc1ea6ca9a9065862ada1d2a75c6738ee3d806ef09a6215f71497c6e43f7021e6ed5cddc587c7a033e990f	1658491723000000	1659096523000000	1722168523000000	1816776523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
180	\\xc88543f689eb89f858bc78a516e1e813d687e5b1b60fc56adcb2868ad19f29f60a10f32b26fd9474e52a966842e2e0af73405374d28cbbaa5c515343918ede18	1	0	\\x000000010000000000800003b17946156a745969e9462c4ec2073a0da1042ce256905b8704c818973bfa29d1f41c3a45e48fc8bf5d77cf16094b382187e2c1911f45c8dba75204e0ddcced278d9f3af9647a1e1699ad6377a1802924fb184538e7c626cb18ea471d14fbbaaabee4c1ebb12b01eb792ae39b2d716fe48cbf07faebdd16ef5f60aa2eb3cb79ed010001	\\x0f57ff8b8f828c13aa70e112043dd9f4463cf44d3db27bca04dcd6426c5d5cd471a10c88f9164d001fee3ece3050518dc617a2020507c6416f643d16ea6bcf0c	1673604223000000	1674209023000000	1737281023000000	1831889023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
181	\\xc81d72a96bb2afa439e176543436565e0766da51b22e0b636e148751a2efb3a3d3000086ac0f471ab0332f4f4caf114e0aa0cf8a4a0f81cfbdc1ab6780ffa15f	1	0	\\x000000010000000000800003c49b2621a07921660ee758576f4db83a53644cb7e8af473d786ab0996742facbd5c741b87ec7d78d44ee7fd273788e04202572ff9831c571c062da6921f1074fe0687644979ba401ed1ebde51d6cc0d98e00f633f8391e10780cf657e96b911e0db7ca223dca821e02c0cd2996e917f43714b7fbe23bbc08b6fd02ea4f58d8ed010001	\\xc941b69f5253cf7c447976f959512f8b459e5be43fbea9644c344f52872a406671b3eafde781f837d4f05bc6d8cbd6fa7b8e7de78a98208c3fca6c9b171e9702	1665141223000000	1665746023000000	1728818023000000	1823426023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
182	\\xc93da890133bf119783ea837eb1f36d55b42f8c5853561b8776bb6b822484bf0eddbcf372bdc2a60d75197f1f05b0e8f8a6b716f753fdbc5a867a183d43623a9	1	0	\\x000000010000000000800003e1369f97e2e1ff65486b2488d1a73611408f4d4db4307cc0248bc486c248171c80a02058dbf8f3fef645ca8e3132b9acbc3213e0b5724119842bf27d828b74f1a85e7be32104ff307bf7af292944299f32fd0de63e3e7e70bd4fa2fc238588febf030257fb1a30de20746cd7be548887703ab603eeb61c24821aaadb54737745010001	\\x5900053ab3e10b6bb187b848913a912c14b9473427378f2aa489458d34b1ffb183dbaa53645085a9a7231fc9c8454876764bf29fb415fdca3bd112d8c2a12b05	1664536723000000	1665141523000000	1728213523000000	1822821523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
183	\\xca096f675165bd09438c51302eb38865a0f22787b51e4312bbc2a09d4faa6b0e6f29dac8639b1e60526aaf871e0165d270d442c2544b67146bb8b46484cc7247	1	0	\\x000000010000000000800003c6e044a0961b08052a82130becfcd6d832ef7893e106c16656505114b2d23ffb81d4bbf030ad371151a8adc47628e24dde23a69f5cc35d0d083f7e59a2dee8724cfa21443859453504dab83d36629e19e86195145d8f731cecde207b9e7533e40879bd7c48f5b33b0cc0dadc34fc662ff820717bc278f7ce581fe8c7d7bf1f6b010001	\\xc0d397b30d5195f48e524c00abcfa6b35e116a19f28dd0a5f5e16050b7e4c6833e7ee060c1529ac53f2f8daf42611140394832aa4094260a74969eb37967a00b	1672395223000000	1673000023000000	1736072023000000	1830680023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xcbb1c75b2b3ef2a454cd04852767a881c6d8ac7b8568d43b100b92f995331b9efd97cc1e0350a004ecbf35374093454bf3aa36e9c7c5f6d2bc91797507ca8a75	1	0	\\x000000010000000000800003cd0872e5691a2777d4ffb2e0b11b4422f1a19b169a9a68362fbf7abeda5981a7423cf5c3cad9c851817fbb452295f9a331a1e534a6c5fbd7f0603197ee80446fda09b620b15be5a8daa34d4d46143b2fbd53978ad05639963250245dc1c8e9cce7b3a7c3d5c154f931bb357c7766c8b2eeee0ae00466b2726ad3b47ddc5c3b89010001	\\xd324ee658ce6a98fe870fc7c37c04a7e80b5cf8c84aa46c04d89b48323fe3ff15ad5687478c175fd66767227571f73accc2edda9017eeb35740694c84257f700	1672395223000000	1673000023000000	1736072023000000	1830680023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xcde1685a3579725e9a0bc25bf1727281ee0aa76fbaa9ba12913e3ec4b8da0c62f5ded470430da213506f622a9953a952f48133c87c3ea6f2034fe9cd98cb6511	1	0	\\x000000010000000000800003df540a8145f5f8359567262a801259247733aada8fd455a92678fdcc649e5051a5ef31a565a598165e09c2b23718f12179661aeb7a770aa9f735dd4e0ce9991c835efb803455f55306114ef366342cb84025e4dacf44e1b2491483f82581f2c59749e9c35b8d4b9197f985242b1cafdd4cdcc9952f83c92736a5dfd14af710c5010001	\\x38e4109764400058d1bdf926b260652227909fc6140ea8012846e7337eaa492e73f60c47e7ef0d54a414ef0c47154faeba6ecfb01848bbcbd6e2b63c85bbef0f	1647610723000000	1648215523000000	1711287523000000	1805895523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
186	\\xd0fd6812013736299e215b155b99c9f9e7ca7f3417cb399443f210b05517d938e7de12b0a6a981dc1a25ca00ad9b57cd46151c387aaa43bb14f877e4c8a169a4	1	0	\\x000000010000000000800003c25f1275efd9b59a52ac1cbbfbd08d542177c3f8368bced0e237971d6802582a4c419a6a27511857c21f3569601048dce215d25665b32a3c8bf6cae1abe78f4bad3e4d523ca843f5157d8513d5abfe9a7d61052d19a4edc0748876630eda6e82eb84c04bb14ce352f2345d37e2ad2ec2261b5c14f98bf0750d9ce893dca4addd010001	\\xe8fe44e719644e6ca185bdbf55bbad0c8110aea28369d9ac4c4c29e2ba262c582d99c5e4c90b07502eab73d3a9b86fde72837a294a85e22b1180400050f6e008	1672999723000000	1673604523000000	1736676523000000	1831284523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xd1152e3f5dff7a34c4d1c311ac51d32dd5575418e5f55b868fe1bcbfd46fadd105234ee34f1925c76d9f5d233fe8859cd49c34f2cf8313f23e48dc6f5239dec3	1	0	\\x000000010000000000800003ac91f7467b7a1b38fcb25d9c5345703dff84aec3945878d53e4c23947c8263855a857de23435e5854b3d8ee906a987aa873835987607b4010c083fa72eb88b97630c9c5dedced5e426f3d244ec90dc7e7d539f28029891f070e5cde7370b79a715daff02e4df6bfc6660cc0d0704e2a56ef470cebfb89d81b6fcc5bb8e2ace7f010001	\\x318bbd3a130659778757c2a116bddff0435173cc6b753d9a10b0bf4a79740ce3d56d2e594a4c57b72602f04ffc3815e94b89dd6a9183ff714885c3c6edb7c909	1651842223000000	1652447023000000	1715519023000000	1810127023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
188	\\xd405565847ca0d99b5305d36757ee9f975e221902606f860a755e9e1fad5bc6e6b82a30092e1fe63de4a29646b4ed1efe7949200bb3061a8e0053574c20d6232	1	0	\\x000000010000000000800003c50beaa791cbc98c29a07cb12c5e82f29c500ebaff4453b4c60277fa68d0ca5b27dfcef11f02362521fdce1441af435c18e7b8cced2021690a238afedb29601a8b455183db1bcdbd4e26dac77bd8fa01adcc429fa06ae6b3cc88b9578857f8edabaa59bf0eddc7b42c80fad05326418df5a49f5733c548d2e21da5151deffe7f010001	\\xf06c615360db99aed261ec1f2a14816605c39cd79339bd0eeadadcd6b5a6d235a8e4babafe977510372b7c8c2bebf44d8cfcfa88bfa40906ae79c3fb44f8350f	1657282723000000	1657887523000000	1720959523000000	1815567523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xd5418de2b471d0c3ef683a9ff4dcc96364c61e6fba00397aaddac59772a511f194cf61d48f5bb881fedf571d6aad2cf70e65f51f5cf20d499f49eb312f282000	1	0	\\x000000010000000000800003b084a98445131116507bef5a01e31907247ab8b46d48eb5ff43131ee12f4dc8a219819afb7a33edfc39c32b44efdfdc2d0a55875983c405fd0d274eb91e8b1c13c9ceeb0802a0f6b00646506b05fa32aabe1e4f3c63df15c8400620767e26152ba344da48aa52cdbfcb2050cb4b3dafea19f992a8c7ca6ddfd92e7922dcfb229010001	\\xfb9135202ae4f0a7c193bf43f346790078ad82bf9f4f55b968a67c8e80cd8f98f4ae5ef8b4cf766bfc86d9e519abb1005fe43c5ecf016a016a82e7af8cc76508	1672395223000000	1673000023000000	1736072023000000	1830680023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
190	\\xd7d9b1feceb78779c3b75bd09c39eb156cf3013dfa5efb16a51c633c35f2987203dff3458017ab8860c8d2ee53df74b27daeeda5fa72c3987c88ed8aaca97609	1	0	\\x000000010000000000800003ae92b39c112ad874df59e1c1f3848ab9e5fb0d8217b2c081f5a7bf6dab44d1da4f457527b9cd4441b53d309264ff6cbf496b5e22a9d49baafeb9c5b9ff77d30e4839837fdbe72af37ac7ab08b621ff410bb81ddbe23533b26282ad8260fbd3ed6682ddd2e1eb25acda0d48e1cfad88ad6781bec911e428cce752dc4086e44b73010001	\\x26e3c5ccf4443e6ddb1ac0e839d648753f552c4bc9312c39cd651393046ddbfaeadc1f9572d3a30a804d3af4036f2078b61d651917f85d3abeab79e955202209	1665745723000000	1666350523000000	1729422523000000	1824030523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xd8511b0d8dee17ab0ea1ed55e222b5b4d4f83b9ab8121494525e220afb8cb485c420ead402f0d1d35ce9f2a1b1521718c38156ba30d3a7a2489094c51f98b88c	1	0	\\x000000010000000000800003e7e27e707e16c602b1a59d0aeabed15382bfb61d75a3553395c8fd3d9a37cb2887bb904edd7ef5ef8b5a192e7d0dd351de198db3f2266a6b8ca0497327dfced02d3525c5a7fdd378d3a6cad60ae92474236b4f701eb3e198d57621610648a376d43b390f7a352825736a259d1c7f75c7c979f7638fa92c0ca6181e9b4839859b010001	\\x95c6f35ff214bce7f465248eb79b2587cf4a147c9329f37c2f1517463243f9bd112e10e47cc721025bf1f7af02b460dc68bb3b00adf129d82262a6757769700d	1653655723000000	1654260523000000	1717332523000000	1811940523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xda9d2f74ac193be19d411befe2387ac35b11f072c61d826ec0fb153590f019a2ed64269212d667845b4bf7b0ed312d933c896f65c94035ed403697b64a5544da	1	0	\\x000000010000000000800003dfefc4b4351edc1aa445c417ccbfd10854b337d6192ecf9900ca31b2a7e2174b97aa3452dc916fcfe165f48a9f1f373fae5f31268a80a8970729985e133af4025e6d86a4235f2cf3346746c8381ea0963ac20d4802b655fd4fb601de63665a44ceb33aa8cd7e3b0f8242b44a7f6780ee792c3d91b926bf964b6b3d4c7fb3a705010001	\\x97cd5f976ade30122f23e23f20b57cbab86ee313fd4b6b08f291ae20ae20a15a4c551610908d4debdcfda12ca400c13bf709891ca8b838d2b2748a6c83509c09	1668163723000000	1668768523000000	1731840523000000	1826448523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xdba531a950acdd5bf128db8bd7f53dd93bb6b8466d74e1749ed6ff0811bcb06ecc269d65e58ed03b52bf39544a91269ecc7837b554fd93a8bdeee498f279eec0	1	0	\\x000000010000000000800003f17598e04f84ad197fe27336375b584d3376780f404ca00749ba584e01e020cfb658a7cd8f77b5478050ce8f501eb1efd928a12e47fa77137eef5ede8bfc4c55a61f7cb6517aa273227af22b86242d282a53015ad9bbacccdb696c35b020c5c58896af6afe29cec89644f4449820d8aedace4c97af5c564ecb326b185f3f7b83010001	\\x4eedf96964d36fa898ad9940e294a85b3bb60ce79bb818c292fc41318246c2baea530b7c51b8d21af61e77098bc11485167f494ab7d54cea628192961273440c	1662723223000000	1663328023000000	1726400023000000	1821008023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xdc0944d63f6012e03048cbaff7333c3eb88f74cfd158dcfaafb2522a63c41318482fa00a6f3e98425120d1794473ce8915de72ef1032f39bd77861bca0c03930	1	0	\\x000000010000000000800003b7aa50bd30fbf3f9ec3589eee12acba7c50574b777bdf784d0a909bcc35846c03a06b0192e7fec403940900cb43f595b5805ba0c978bbed7fea02fda6cd0e1d0aba091573e15b719a6491089fa1211ce344abf055dd069659e46e00f188c6320ffccd8296c4f5e4daacc4ff51472f232fc7b701683403835bb43593752769a39010001	\\xb50d8da370609537a429d3e7b73de05f08d2367c7517dc9b931cf2b88c426ce3cd1d27180454a891cf614aacd8085a4205ef7ced55555a1c65e35832c5bf4c09	1666954723000000	1667559523000000	1730631523000000	1825239523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
195	\\xdd492ccce9852dc1af0c88b9099c2131a337131483ad481adabf665408ad8f54f28c0f8be50f01c130398bad4abaca809ba28d090700c427ea581d46282d71a1	1	0	\\x000000010000000000800003d8594b2b046b4ce750c9457303d523d6e491f4f8b3560520af6a24601514eed1eb285c8c46a6c44a773eb5058948dc746d67a416a84ec01a71ee41a025d9d4b300b54b3dd44ee73be031c4cf8b5a582502e7014ec00a1052fbcbd832e5b9a681da5d3e89a6a5c3aac196c3851c808f90e21f40ac8bf048ca785ff4fd05570471010001	\\xdd3c3495ce1ff61cd3d3b8f05ef0b7e89bbdb70da942c8f6f3542b7033fab3fcadcaf4610cb7c77a746cf6382dd6e0c1d7019054265ba9e7ac33c6608b43c403	1665745723000000	1666350523000000	1729422523000000	1824030523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xdd5d7b3ce5ae84bcba15c12bfeb8581d6e5b46996d6c146da9eabaa4f532d85827e26a62e79129550b97053a8d8032b3729e639b9008efaa3a9913e661d3698c	1	0	\\x000000010000000000800003ea837ac92f4a0b0551d4e68975afdfcdaa9ebe0e18accc3e716c68fc815a25962e9656252c10abc74a35a542d67b2e112c2b57f4697648183b8ade21b3edd965c90db84c117e99539ed66e6b27f2e4f03a05e440aa1e13f8698fea447584556a7a2c5f6ad65a6d735ae2918e5b19b9b63ce1bc0001d9a0f879bbf916bbad6957010001	\\xd93f20544b2b8c4e01b7f381b778d469d3e6417a1317413bd5703af8fd1150fe106656d566ec7388fe5a4746617c2f6a702a8f915a862875f817277c8d50bf0c	1650633223000000	1651238023000000	1714310023000000	1808918023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
197	\\xdf59beff49ca5730a46242534df8038e24265ecd0c1b7aaccf4b160fb07af54afbbee44ae3f19c1fc965e3a8a9299e1de0751cbd78bcb8ce536b5f7dacbd5d58	1	0	\\x000000010000000000800003d4458f6f2148f8e19fb26eab20d839eb394214b31ea410be1c00a524eb67918f502038207a828881ffb2d7c788be980b9f194179472d93ec1a61745b8867e61c35f0c1e61d949cae82e199db9309f245d538515a42c997ab45e5e038812764d061d9627461e42f831962ab25897061a472d1b331fd6e99ac46eb5d21f26f5679010001	\\x09873111519db81ca58b8d5fc26186e1c1197d0acd02946b50385ceccf66a688b6e8c169403f64a435fc49ec2fdcb54c63ff799b0f75fa7b4e34db4380ae7b02	1663932223000000	1664537023000000	1727609023000000	1822217023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xe1795823258598e111ac3bb4a3d74fc0f3409ad3054a0e391079335b221d341d8b185be85110673fda9271779abe6c37068153d58ddf60c68b8ea8ad79cb0fb4	1	0	\\x000000010000000000800003d95d37fd32fec67c7d9be5a33b62d577025bef0b5460975a4aeac95ebac3a1f5240d39324f5b29ecaef109d3fbec4ccb62f5d1517db92d98df675eb83451025a047d195f193d7cce051d6ee58076ff827753618c940b80e74b94c14d08b7c11c09ccd6b6348290b8e799892aa891e1a9b7d025fd68d93c08fd8586c9b55e74d1010001	\\xfdda445b56dc9a3ab3ba8f1a9f6cc9eb830f1c06a7008f97ecd41f512f6041001bf4f09704bee786904974bbc6e32d458ed48fad1a3ef4ef8c43f296a8577508	1654260223000000	1654865023000000	1717937023000000	1812545023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xe1a96cdd7c7d522aa27ffe11a1a0fcf6dfb96f37bd8524759a5920deaf3e14e8279011bad116b85f6056d67de9526451badcc0ab28d7c739433ea9e8663b891c	1	0	\\x000000010000000000800003d916848da0fd4aea3398d4050781841d0051e1ff14268f9748dfab698c0af56e1e43e04277769c73b62a1bbbf4b6d7cd9dd70639be37766374e3a84bb37b5bcdf30ebf1dadeefec43f135715ba1235cd36114ad0b95663d888cf2efbafa59705bbaca5eaba323c8af6094fab48d0afb21daea6b1902c9074043febc893639fe5010001	\\x6b490b4be14dbeed91903b81dbf116d3c00b1ca7b8796ac1c529b374419c22ec9151133c078fbdcf9b10f5bc14d10e35b8bfe5d6be0db696683f040135470d0c	1668163723000000	1668768523000000	1731840523000000	1826448523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
200	\\xe399ddd875bfa3569b4a6d5d1e6705719f8200ae6700962cc717bdfff8cf858868900aa44096d8e348e71fd7e06df742b695a93613184dcfe8247c3c50bbc437	1	0	\\x000000010000000000800003c4d559ceefa1bd7e64f3d2e40952ff66c23016e83d17efa7a9f171a0b1e852db37c9f6bc8040d8c0372bdc6a0f1df2f72d6625dad60f513604f554d188b30c2ce2c15856f52a08d31955f56176c84386fc554cb146ea8b793baa526f06bf6125c1a29114972760f66835cacbec92800d35c7bff38b0457e6514a9c12c8eda677010001	\\x4470bcd326182aa74d5e57600d18c58524d84d888e970b0514ed0399f4421a219fd3cba60d43ac8996151df0a11b0e7f77d73685cef41ee4827f2cec230f3400	1671790723000000	1672395523000000	1735467523000000	1830075523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xe4fde40da6889e9340efe3431978cca61105c561a87f7a29e44708cc74eac42a7130e873b9bc2e1049d1d6ddc5632e842f73e0534b1b50101a21d731a9c7a7aa	1	0	\\x000000010000000000800003af75f979244e81c06666394ed4b1ab19b899be5df7fd7bacea36f9d3cb60600a5965346b7e81525b24455d2b12a2ab59123fb2da045b1b0204d1e6ecef11f3d98efcf2f74252be8bb5ac9ba0931a3ab4c6c98332e0369674c79beaf7e69ae72765691fb14af543d443c7e2a65fd3752abd8435a543dc9bb355faf96c47f7b25b010001	\\x1e94cf1eb491ebf7ce3acd4fedcf686b5678b50c280bc69593a6de741d1dae092e305e1f60e1fef627ebf759eb60b1391a3c575ec4981db776bf5f86f7679e02	1660909723000000	1661514523000000	1724586523000000	1819194523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xe72996d425bc62f985577f4e2e0f735634c6e7def7fa9a230cd5a18e402f36e526bcd1a6861cf55abeeeee6a0a70e53a341570e5c39189420449c8683632019a	1	0	\\x000000010000000000800003d75d0775bf4f137b27e08a9e785429f8883eaaeee791fd56407614961550b49d59b82be74c583c3a2d55225ad139761a6484443aee1bb136b0459b3981a0726394c787848fbba99df234c5ce784fe1757c560dc3a8f51d07d8c8a08aa207d72ba43908a7aa8d4274b7f66889b12316ce307ff587db0d6d392c39fe6491a0e083010001	\\x923e8723a919d64644ecfbce2582a64f81ce688833129221a422a91d16de68ede7a7088f5f1b2269f84ed0ebf0905873aac66164d9d078e9070514c0f74d3901	1654864723000000	1655469523000000	1718541523000000	1813149523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xe98dad39c4f79806f3a8279631551eac36673a33a6c7421524792b256bd47206053ca45c633d952554ed3dcd766c11b2620db28d6029ca38385b003dd15673ca	1	0	\\x000000010000000000800003989123cb45d0b732608228d678b2137e2b7c9d7d2f589900c578424b04663471081e6b5e12609fbe026f00ab2925db9fd3dec007464210b4c15435076b8f8d812f3908a39aea9e16499dbd1c5e797a3fa3674eb796145c02c90aa8d62d8fae57526e5243a888b98b14ddd8a62837215383e24b530184821fa7c06c4601546f09010001	\\x08594c9b49d1b18c94753c6ce71cb2c195d78c282d7ad45b604f699fe62aa1df072e243c1816cc6a0bcbe94e82c8d7e12db906ea0d46d3575d9f0db718637009	1678440223000000	1679045023000000	1742117023000000	1836725023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
204	\\xea55b9174010def2ba7075edff6a4a41f9930e984abb1e78da8ff0b63e95950ff5a8320973083d770ec39f4e78d62f289a50fe63512d2fe3cc9407b03f3b1ced	1	0	\\x000000010000000000800003b0edf01cd8745d499d5a1d53f86610ddb8594069a8c5b79221dee4188c42e56a3e13ab41842f56e3842aa7e6d69708a93c14d315ec735547bdd5059541baee5dabf490cff36e3d81613599e73ab58e452ec5691e0714a8e487c533f99c32ff2779d89df143020191ec466e4cf4647ab4014878cce910754beb1ad718d1acf2c9010001	\\xc769eed320d7a4965c85f383789110b50d8e5347a57946de9024a8af71fdb2b5c1fb03c15ffb15c47fdeee9a6269046524bd8387fb904fb78437ae48bbf0f40e	1662118723000000	1662723523000000	1725795523000000	1820403523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\xed114e7a9a83108294c220e406e2324f958fe321120c602d30b3be0a1f1475e73276add5921bfb4c79bc3234c2bafe153baba0bd90ff4a4709bf53533261e8c1	1	0	\\x000000010000000000800003db516d78369bbff5c49145fa785e52f6a3eb962b76f3a764a1672c905f80ee85bd28658e60b933c5c442c0150ccbd7e30080f56d6af759ae6bc52ea91072954069137b69aeb2f7ed4b7aca45dbfc416f8d00b160cb303da5bc314ec83f6c072462fbc0bb69da2a65063edd7a6ffab2de06ad136e092aeb87490e8ce50b2c48fd010001	\\x49292da84baf9f460aa6b5d6da8e264b05d3d0606b3c332e68651a33f9ba9d9c4e2bb2d776aef45ce4c13317aae895263f3ad79db35db18d420be261671a430b	1677231223000000	1677836023000000	1740908023000000	1835516023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
206	\\xefcd1de4e440877fa519989eedaf003d890c899ea1a5e13f7f8c318657b6ae79456c599be4a2fadf36745e3acaafc5103e848df6a427b8c7c920f92375fe4563	1	0	\\x000000010000000000800003a319a160ea7a03a402d4a161b7202ade3c14936c77aa8a88a98b4faf3fe43cc1cd08882fc79a326ac31f4f33d0bdf592155a3219dd43cd6fe570ab9bc7ffe348067add9d67738e4b95ab41419cbcdce42fc7dbd03683eb71c2684abaeab88550872d9987e4a8ea986a63516f4d7340f312d4b093981f57c3168b452ce9a16fe7010001	\\x2787a825b36ea04a736bea20f5a93c1fb7ca34cb1a694efa7d7b55cea6ec1e9c76c1edc80ed790a94182183ef2c2e4af534441f9ef08fb1368cb889eaa18d90f	1657887223000000	1658492023000000	1721564023000000	1816172023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
207	\\xef497d558b61a6825d09f3e739d8fb909d20fe42939c06b22f5cdaafc535da69471063589108c0834353eb1a3b2765fe38f90fce3ae6dae8a0fe2e371f7e4bb3	1	0	\\x000000010000000000800003a1f8b3c3509bca5f65672eb26ecaa7cef4a4db8f2f966725d40d8527e31c013fdd751a744f526967cc8f74f85dae4f9d796799ac3614837ee8d4fe02015cf3dd3541606887fed8e44a243c79ae1faac57728ce2c5738cbcfcad04eb4fb96cd56b7d932223f926b4667376320c212a7a684dbbf2deaf418a3217c2f8cdd81d961010001	\\xa7b7bccf29a287b2ca84b7a752d149567b69e172a36b277fe5b9acbcba741f185f5e70c844e39342bd710dadc748e759811f10515e1316944458107e7e92f90f	1664536723000000	1665141523000000	1728213523000000	1822821523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\xf43d435e3ba8aae83e039c9c0926fcff285c9f1118c5b33120f248eca49f93df7a03d7407525ada6eea4005f996c4970379724856206da744371c48084d10480	1	0	\\x000000010000000000800003cbe16fd82b89ca36a222c0001106652b9f3e5af2f89c92893cdd614923b87dbec4243eb4ff98c6a61696c945e0332b7525847191c3eed59d9e3feb0efaf863a0dfb93acdcac32c44f5ea9c4644c0764ecfe4aa3372d39f912a26ca639cfd954039714e481fa3bf476a8a5e3f6081b52174791db902ae9a275773483c05292ccd010001	\\xafdc752c5817994565ca1cfce468ad699b11350b103506cd21b43732dff84c53ccbf4e315ada9b340a236c2488cf9fa8664d0f8a58045408ecc65e2aff641505	1678440223000000	1679045023000000	1742117023000000	1836725023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
209	\\xf825dd329159f67c1d6d4d521d6643903888f467c2bee23fb7c1ba5ce88bab2b6d48ef23015ce8ae607305ae7a69ca32c77985e7a2c0b81c38fa4ce253647b96	1	0	\\x000000010000000000800003f31509f9743af819e385cbc6712bcdb2419763ffed75edfbcc1b0b22eb5ead2d7f65b32b1070643c6bbf8bfc3610a0892390147b79b576022c57608a0c4d60fc12d2a361cb228783e41f9a06d1679bdd4f51cca84b0fd41499a34a8399d66ed1dccf8a771f195ceab70999bf098236a5e51d6c36fe22508baa0f064ede922e3b010001	\\xa1f3a929c66d3b7a05dafe9ed4261894d46d72f6e9ecf4a19a3886f3849bf6ab8a23fc6b92590e8421f4a0bf0683ccdd1fc390ec0ad2f3b76570e1016ecfc10c	1651842223000000	1652447023000000	1715519023000000	1810127023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xf871728b2346fb13cc44e45a975b11e7b5f7a7a9c50cdd8f480bea7da1049a69de324a0170f619273210eda260a389d7c84f7839543fdd2ce532622afbac30b8	1	0	\\x000000010000000000800003e633645a108d5a0610f4a4304aa7f6a927f57a190abf37e1a4540a643326cfb85ff30d311a95c6ba37226cb6f5d4d8531b0f4891c47775c55469c7687996f44f4abda783067d6f0c2b3868811e02e0dc089db291aa660da9e2c495f43f24067760841616c7e369c7fa6b98e21b193e69317dfec368bac44632a0e61c24457ca3010001	\\x09f1d88a0e3c0922e45e9320df5fd6c1f44ee3e2c9a2ce60c916bbbc3a6348b177922c0a17ec8c5ccf7fe7517dcd4e2013564e87da5227b00d4b61c31bdfbc06	1669977223000000	1670582023000000	1733654023000000	1828262023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xf82d6ba3c397d0a7d662d383e321fbdbd5b3109493ac17df5b7cc9e07f557918f4dcbaa83351b9220e45358301b20d3e3c06e533d3f8d3adffe371f05e97d00a	1	0	\\x000000010000000000800003b1ee976d200c02e763e736e452e25062aa57b6112c98f040399425db7b078a07e8c2484277cae101151d0453d64d17de427d0b860571b10e5bb3aafbdecce80322285fd6e3853ef5c85dfc7b56659bfeff5c8c1cf1c51be140f7844918f3d18707c65f7ac56ff4fba9a01ac3d48ac09dff4adfe9c758d0ca0a9ef31cef42c713010001	\\x429e0ce888e5b513e2bd13c5b3888df187ee6c7e1a44b55ddc5c020c77a6116d2e8d2bef4fb991b2dfc21898f24fc28e1412ac8d730f30de1a3162e4b9d3f409	1651237723000000	1651842523000000	1714914523000000	1809522523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
212	\\xfba132020a8d307c944019594d63f465310090f4819f9e21263a12cadb5d4ec14b13815af01eb326b69ab8412cd4adc880ac29e9864ad7c8c5b3c566d4d4293b	1	0	\\x000000010000000000800003d3242ebc043db7baa919644b1c0a59906bfcf4049c252e1841790a72fdca0b443cd413b588342ea0b409a75f0464e95fbca89f14e46fbbeb255d327516de91ea58960835b7ab3361d863de2e58d2bc03acdc2ae0fd4691b66033a63e2000e326e4d52d810dae6ff40c23cb6e271992cad81e70bc6cd9da42842a0cd995a39cf5010001	\\x4a1a84c9cf21856ae2eb140f36889fa910e3169c1dbaed10584184e6ca7041037ade63114e430dcfa2c9634e64a207d4ced4f5da0bdac358e88626b5616f8100	1677835723000000	1678440523000000	1741512523000000	1836120523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
213	\\xfc31eba02ea698cc61f5a39ccd542e477ff01a0777aa0c9ecc82e0f10e9e6b830093578530f7fa5f6e6a333cdaefa1f090d19c2eaf5be8b275090a5fe68ba655	1	0	\\x000000010000000000800003938a4edd8c35c742d31564430e5320e52caa30b04bc60961fd5aca227d76bc376a82fe62747e5754de04fefcf432ed5493c8ecee665219b0596ab51aa3ea48090061f940871c74f63eb0558fecf893eafac2f32ba89c3d2b677571725e58f43853d26f036901aa0730d4a5602a848597e23bb483925b67cf99357367231cb6e5010001	\\x2eb31a9cfbf2f9c0474e13b5699f00d027bd913b47a03f8595c9f16123bdf71de692b12cf21f1a469032bf74012a71c9e32d484999a9aaed2d0fe32b92b09b07	1649424223000000	1650029023000000	1713101023000000	1807709023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
214	\\x0116ebaed9c2154d43c90e8637e4d1ecefbc8446496563ffcd9c2be7c0a638e6e39529466321b490ea307b073d7d4a49eceabf2af40ea052c642214aca913cd4	1	0	\\x000000010000000000800003b02323649bf33f770b0b9c70b94eca3f27a102a3872ece97e51ee572fc47288257b002d306dc2a1f2316946fbb75c4eeb1aea9523e80092843a811972a82e999d7adae31476a4975ab87eba692d16efd05d536a9c4f4ec33bb51fbe6dc55ce7d1cc8ae45c998d2fe1c512b744128bafdecff6ddae262fb8ff1b95357952dbfc3010001	\\xbe597e011a0f976a6ff0f183d7c0660037160c72a309d00d343a62c189a07b05751b6c95ca7c1e139bb7e5bae75e5aa358fa896b57c7c815eb1fefc9c35e3900	1659096223000000	1659701023000000	1722773023000000	1817381023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\x027297ad5a733a1820dbd76189ade3d24f8dbb59aba690bc76a2a1cb6f2d0ff21925a6bf3aef76e7a37fc1268ec966e62f95457ae30ab1d298bf5e65cceea7b0	1	0	\\x000000010000000000800003b77050fa51ed70c66d8c68fd2b5f60640c83c253772c4236cbed3ded23f59a30f327530749f2a3cf30fa2c879d8470145cd6fa810c3e401247ff32b233e91467e259f09a360387202054cb1b32ed38310ae36e86a390a3e116772a0248678c893989dd4951c7498feb609ae1aeb3d85fe3f96d89e6eed402a76137ad334b647f010001	\\x276fa1e43a19f388cab6aab49e186d443c7699ed06db819386c1310f49b196f22f61628a2af3f2392d6981efc9a95293e597eac121290e87343706b69a057803	1676022223000000	1676627023000000	1739699023000000	1834307023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x03e6a62212ffa013088467b04d053736755f870c1c807d581128c0f8da3e90f674330d2b26bd9eef13b294e9caf2a3f9e3106067b103cca956db39c8a77502ab	1	0	\\x000000010000000000800003d7597347df70ac53d7ceaa21bf806289fc22296a55d8a29505ff937c53f4bfe278afeea05f67fde9701e2b02b98c4f78383c9b280507a4b4c99d49d982092c083eb7476d52383b1dcd457345326cc0fda0aa1c84bd55aee1f8748d750600e5e7a24d986128d718001921d1257c37353283f5338ad3d5a922b71384a712b92d35010001	\\x1288d7e816d49c2e1ae6fb5159025a5f77042e4ac4720802fc8274936595e009c6ed2e115b176aaef0b5d2ffcbd0e9ff8d4c2708f73c1a2c7dbacce6ccf9f80a	1666954723000000	1667559523000000	1730631523000000	1825239523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
217	\\x062aeac335721a0e62c34b290ba1ec4f59df0f5ba30ddcae80ebdb0d9555032a2ccd0c7f69379c3290e6d370575e3667201a31a0c94ea38c811a8ada9e7fc0b2	1	0	\\x000000010000000000800003eb58e42f91eec0f0d5c97d0f5a1787183dd9610bb074c61278c928c8b822f7ff4bb0dca38b9f134ebff1b7d0a77022b46a95008bcd659e3765d3bcc3fbd008af4e9aeebc3bd60acd7574cd849a6b1defbba3a3856de4a19488becf526a6d101b95bf12d52a986649ddadc70ccfa980ddf4d1ececbadb6ba7ada567faf7235d5d010001	\\xf5099e7f40cf60579364d87c5c6c4ace586d018e25a62344b1f4edfabe82abdc3c96eece9a4156007561e81e37f427ec37bc7ee7108aabc195ad435635bca906	1647610723000000	1648215523000000	1711287523000000	1805895523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x093aa3f30a0288ff2cecf7333eeeb81927c2ee84cdb45e920abd728cfb228bfa163897e75c950344d27f1da43ff4105f0de4ab10ebd6e57db096bb74e159e715	1	0	\\x000000010000000000800003acd35bd1b73c786dd8d7bcaef5bd598ffc7f023be44ad91be1e5bad4349a4cb545e187499de91e6ce46c3c44f3967c11387e39eb4dc83220c8c06e66dfc109591bed6b7d666b51f6828017e4d992631f6541e01f9f37f86910a4ce0f846c332ad62236d18f5c7a41e98f4a6cae908647468a2be1622eb442bde7c0f51b02bcb9010001	\\xe0a2e9dda77cd9689b68ecc7287e4f86b3b277ead0fcfd3d8a36a087314a08ec83ba27c9beb692894bc6fcc57a1afa825808564b20a1f2ccb1d8338a5c975f08	1671790723000000	1672395523000000	1735467523000000	1830075523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
219	\\x0c8e1a781e0b8edb50ec2e52069163fe92aa36eb69095725aa1a0ba20dc0d4ac5bbc07da6ad10ab3055c1fd659750f950f1ee25b51cd44d8068bcbf954f04e4b	1	0	\\x000000010000000000800003d820f3b68eb5db9516f063e8d9e36156088efe3a2288e14319f4844f21c5244f6d466729f6ed285e3b327bcc7e672fed5c4723ee9d641f44c3af002bef220c76a94874c8a215d88b61ca60952efcd4ea9f9cf63d7857a52881e243df0e957b34df641df4c00f8a9cd540171c921614f19089ff25db4bddfc0f6452fcb1743f77010001	\\x80aae7a570c210bcd0c8632a9c21743632b25a4735a0e54ed6b73db5e62bc197bd2c95a8dbf1a3521f2dd46d8f53dd9fccd3fe0e8391e187225473dda9419201	1667559223000000	1668164023000000	1731236023000000	1825844023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
220	\\x16ce218a6a324e2d4a6fbc5165eabaf10af75ed5ce5d78e7c0c9076d17b9b27dd72d779c29e2762f6490a40a0a635e58ff01b6261d8b55ee605621a15bfe3baf	1	0	\\x000000010000000000800003c053a4bf3bb066623bf2886464c43c8a354f5d068a52ef7f8babf492548029dbaca041331f4aece6e40b249f2d22d04561b6f9b23cbc97e321671fd09d5df0131445bdd9863c7da07c7177d669b60a6d8f43bf68b77c38d2a2e9fd98d31f90fe80705d5dba0631fbf0e24a621569df189fc52fded6541c5bef8bf710bf725139010001	\\x48006a60edfe536abceb783a5cf93fd1ad7297077108d64ad123e7e27b4a17a788718bf5553c9d05aaa15fb201d014233a1798cb0b9c2809fac0a5d1da86a104	1648215223000000	1648820023000000	1711892023000000	1806500023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
221	\\x16be8886682d7838c221bc4989ec1f4f5378ff034acb7c51695427db5823dde91a572aeef6bbbe01e1bde8d6a7d16f5f3461b92be74d928e7a0597fc304acd28	1	0	\\x000000010000000000800003bfa22440d817e823119bab00db69d1f34d54a9fb9be86cbd831bb5b9d072fcd14f6ed803cd87542ff0e8e053c16d33a86d57d785f4c4d3cb688d738b29e3a335bd724bbf37ad821712884ac393ddf7a5848f49862871ae61fa9b2d3f3d2ffff9aabd04168cdff7caf4f31fcd9b53c7445456276f967d66fd94bba6644af442af010001	\\x7d9b4d4f0b97236d1153fb0b13cdb879e92c8707ad3cee5aea10539bcf846d62f55cb724d41f9a6542cf45b6352fe7e7238395598fbe987ddebd8cd9eb415b05	1661514223000000	1662119023000000	1725191023000000	1819799023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
222	\\x17f290db496bc11040799086df32903ba0bacbdbad2d4864884b260916920fc9a7895ce0da373446f0db3cbf016e5c222b6b2b5bacca23becd66e8feb146bdaa	1	0	\\x000000010000000000800003a10eb11980cca27b44ed0196a60e8ab70ae75479e693a20bd8eab8ea47fbb91ebe6d078486f73611338ea17ac24c94365c29cf071c3cedc38cfcf23a8ca5b9942006f5beae42e70b12ccae5af73233ac29847584adbc737f2601d39361c5748ad8a8f66756296920c8d007219f8ff0a4c005bd4ccb49a4c435913019a53193f5010001	\\xdd08ed32d0c31464931d57e294cbb2212f4efd906d4f20aaae853fe342b090901a97dc943a0f10f7e58204dc94506222cbe1ad2958d94ea85208721a2a794b04	1677231223000000	1677836023000000	1740908023000000	1835516023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x185ac8c20dacdc640b60a94af5af0b3d5cc67a042fcc5962db9ec62de4d380fb5a0feea2f22e7fb190ae5a45e5ef8199b9eeb46643a21ea349512a1b0b9221f5	1	0	\\x0000000100000000008000039e5aeb8fca62a6ec19ee8a125ef080880e8fb84f253aec29151c9cc3ac9ffd410fb3ab14afd777cda7c527a22e4f1645c72d1d17022f418547e17c06dd94d4106911d3d3b97b037c0f8130d709871a3dd655243f7ff20a828979cca11707a63ab26a19abbb30b510afe4bfdd83522ce0d3b3efe0aba1eba457e29d4293a5e60d010001	\\xe8f40ecfa02709bfafe316196a1be06edb279d1d687e8a935656a6784687d8dee925da2c6999fbcefbfe33613035af5b43e0ed44f713be584acdca987fd56408	1671186223000000	1671791023000000	1734863023000000	1829471023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\x19da39157bc21acbb3348c4c8e2bbc0e16c607716c56933ed967e599a07a3cdc2671612466a9e2f2d513fef97f926c986e4ede5ae075145977161448c4ed8b63	1	0	\\x000000010000000000800003c52882ac5ef4e34faa2798c0c3797a24ce80dda1c03a542d1d77975955fc69ed256ad4ef637dae1116f7c152da2ad2bba6c9476ee655a35378b6c6b83b55b4d345b645157437a1d86931380a33cbe4eb0ccf5100323187ac1dc2f8f634023eaae92efd472a31daa27656d4c16d7dfe3ed41be753f16c2d43fa14d40bab4b9349010001	\\x13effea4fe3b2d0309cb94841a422db79fa0c430563a643e5599cd975b7d9dbd6c46672e67251f869f1177b0a344ef21eb4d73d563f93621824746d89c92db02	1649424223000000	1650029023000000	1713101023000000	1807709023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x1c1e2c173d43741cbb3f8d147eb289a44776d3a1c475e7ed6a9d6085ced85bf4880bb9b9028114f70f8ee674f45e2cbfff990d600cd16317ec702a80dd9f97e6	1	0	\\x000000010000000000800003d35e318799bbab022bd190c4a445b467e3b7d5dc948e39338baa4c5dbf56d7d09477e2ab8e76aa7cb2aed81858d104c625b0f5bdec21964dff7bda2140456f2474dd90f2eb9860e2eba7bf36fd326b5b304c2a3bcd2f9aa66a079ed420ff077e3394b2bb7ee55a2d4877ddede8b926a680d08848c184f69ac44b672184b11c9b010001	\\xb111217c272b7e6ea49359dfc11a18d0e9483d4229c221a78eeba390d2405ff83815d89885c37df7135ed3bf5e6265a016a49ffaf0596c4cb44716ffd7b8020f	1665745723000000	1666350523000000	1729422523000000	1824030523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\x2142aca6e0f1cf6fdcbb672c2a9b5b512148590c8b5d57fd05b6d247691e10eb99615fb7508a31b89bdcc3a42365646a542670bef30f7e03ba4a40804cd5c934	1	0	\\x000000010000000000800003b1c493d6b627da6227fc3989086ee80c6174392930c7651cb4229b9ffb3f155eb260194c54e04a5d0e40d6bd080895ade3485413b14c908a52af5202dfdcea8cfe7b5a17db1511b17ef14e8d0201c2372cebce9021c6a6b63be27c8ad9eda8e3fabc86bf398b2d6e7061e83b793cc825c7436142d3fae5cfaca0173c8a4173ef010001	\\x4a934cd661b9fe1c6387180889bfb3e2c83150751e9b153eead8ad0b4ea6355464916ebb6d9d011b939db594c53b98e2c3f0bf22a89fd7422d63d6b91e0e5000	1668163723000000	1668768523000000	1731840523000000	1826448523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x25e280d8f5d51bb6283357735233a7f574686315d98b91cf547d1c32f0b06d931380e5cc7aadf370b216d080b0eb476a2210d67338ab63f2a5264ed1a6e604a4	1	0	\\x0000000100000000008000039bac3820f4a4aa8b3373896a4ce85918f3caa75a4ed340669a7c0c10e128ef86f46ac489fa8196b3cac96ac361deecb8b92482738c71d19256ca2018316953836f75c0b5bb0cd104234a1a335533a9f9788025534e89080e98619373391a8519abd9086d964acc82b0b1fe3c2387eb16d41809affe59ba825d461f3a5279d155010001	\\xfc86d10b9c993585b10a6c54a68a75f3ee4deb3b3f931c91738c7183ff94265d384506eb04249ef6a80f418f2f2367ea3ffbabc07f5a1fb16d202a21a81ba302	1664536723000000	1665141523000000	1728213523000000	1822821523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x265e9b99f0502c0284442bee97ce581b9f4483534c1233933e41b4d828ec2ba9d52da990792b98dc2b146a7b9d14438416d59698ff3e6b95e6403e4c8f61c5bd	1	0	\\x000000010000000000800003c1077abb84d6b4cbbf949784c091786b56feb3cdaa7dde0037bcf4c170028e5ba1d9293556ce15d86a6c0ec220dda650837db9a18786a06927b8682d176aa950c68959cde7447036c6cb6731fee6d371235b391eb63e31cafa6417034db57defa8dd9757da6ec45be1ee16f5b6b2edf8371af268727e815efbe982d166800e15010001	\\xdf055c7a4c032e5fb8ed772ce6014c9a2b0b54fe13e83d46d6bbfe2ce71a8678b184f8398c21c17a64ea9fe066311d6a0d187188e136f0aeda50e5fcc07a5e0b	1666350223000000	1666955023000000	1730027023000000	1824635023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x2672973d8310aa150a989e2ba3be370d7161e1d83198e3b35ddef8837b0f65988ad474c26fc19c695ceb1c47e65213ef9eb51a88656e79db11b35c4ebe095f4b	1	0	\\x000000010000000000800003b5568cd578b405279160188358afe9567f1360d4a5d734c363d48bc74befc72351f90fd53bc38b5ac4170968f7f509a0b8c201e625741aed0a3710f21266cd93dcec7d4fb6439419891d94bf42bafc0a7af441e6c8866932681d37926547144d819afc39c7b89a5927c5606991c52eee6cc948789bb6473320d27812cd4b52a1010001	\\xa08eff6a60f73a5f9646765c3fc459d879699381c84f34eb7fbe23dab97f0a1b9931ff3da14b13e53660c4643dc34e756d6a74e78fabf685837b7165ac2b7709	1648215223000000	1648820023000000	1711892023000000	1806500023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x2d0ee3039c4bae3bc237953c8110d71c96d9b6cef9a6de7caed897a47cc06ce71e80264b2020387a21b95b8b1c5c22ede70f61f0d8b14fbf96556e96cb4fcee7	1	0	\\x000000010000000000800003c8d1f2d24e36b552c7986fca9e5e1a67e18236ac3983e534e59e4c9638b04c73563091efea2aec8a1e01ce18dc865ccc1b74cec1e22d7c96ab68e61b792a634dbedc5c9037b908f978b8907625282f5709351addf5f6455dc208cb8fa106b9347ba7537f3f9e41cdd1b978f74eac53e89c5e8bf2d8353c48c9c1c223b0bd6c4b010001	\\x16dab9bc7833154b64a620bb25d8b90cd4b4b5f15e021d1f215e42680a7d3b16de1a2e9c5fbc64538d234affca7737d4306c71c6f568d5e459412a2c2efd5101	1661514223000000	1662119023000000	1725191023000000	1819799023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x2eae2e6b2b497373cd041baca4391cd14b004d55e7adc5befcfaae9ef8c0dd40be3d89dd09faca847f2a175dc3cfd17d4dd271f7c73c04b565096f8fccfd521d	1	0	\\x000000010000000000800003dc89204aab235dc17cae8234d3b1c0587f0c8dce62f52a61063fdf3e7c5b0ee2f46e101ec201d47e6a0d64f223986b98951bb2b2b1c7b4c50dd8c1a673ef10c43ba572a23f89237d5b307e29561599b0323f0686afb2a91a238d97777c93078e4dbc2a7aed17be926932392ec3effdc9a35de6271eff24a8a317ceaa2597bb21010001	\\x6307d72e2938e12ac1c76b512c9acf762a60ec157b6ab77e4cac9d09db1e9af9df29416f2cfba615191fd3fda43f5dc38a7ebcac8de71ab98a2dbf530f3d7905	1664536723000000	1665141523000000	1728213523000000	1822821523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
232	\\x304a97d2318f845dc3b1a68be6419acc3419959fc6cb62c7843e1d6130869c067e0729f988de1f70de370f567eb0bcbd281155f6ae9a7ad9c9289b891d6ae20c	1	0	\\x000000010000000000800003c15619b3383438c58c84c479ab6f62d26a972af795ce9c5449a520d2a22448b3fab1e47f8a608a7d129877c7eb76ef83764224e2e9a701af3edc06fb5557881a948cb07d5f6937de214639d1adb51767669b18cf35f18727deb4db0401818810a45813c2374d479e3890c0533cf66450332390afdf4e26bf741e2fe693b417cd010001	\\x1e0036f1eade5c80f4db0004221c708ee919671cb511d470b20baf0648218d5bdcfaae9fb65998e4153e058432944e2b27e711bb59ab5bddf477630302b9f803	1665745723000000	1666350523000000	1729422523000000	1824030523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
233	\\x33caaf1b270ab71ba16228d9dfabae4ef13d0d5d8e8b0084c02aa0a09d6bd2b1acd94a40b1d68a1294e31d76fe3731a91c166d4b9f67879d007ade4f77e882c6	1	0	\\x000000010000000000800003c413ec7e94c07bed86320dcc1660e5a6c6e987147c426d29fe9a7017ec25013ea90483a31bd8b12d4b11077bae69aa636b8cf6514f577ee39b50d65980fe13fcca03abf960d6b6c1b1a5bd90565eece4f7f07100b4d17fad748fb80e45079c0d493ba6f73454717d2003abdcf50e9c986167f216a36df2f028d0b6fcdb4e4963010001	\\xf331886521a184758897662b60e750a23e7066b55438f427683cf282933222465e27d66d722448a4efe57fe49336b9e1768c685e9f7de8aeb0f1b7360b30cd01	1659096223000000	1659701023000000	1722773023000000	1817381023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
234	\\x3b3296e35fbb409d32cb35ad6073388d888ade1bf533462423797e5ce8232e10dd728c2cd5155c52193130f8c892f081f4ca50bc7719a4807d30b56cc0ae750a	1	0	\\x000000010000000000800003e89d5415e02aa5681b770776142afc6b979d3872b2617963c3ed41eacea376ff628092dc5ced51faa777e367838488a4f6671ba506a1af409bddc44e79dc49de9dc9b24af7ff34123d6b7d2aecdab60692c49a44cb63d9972046259f2a370921c67a41877419e3ee7fabcf8beece41a73bf7a8cb343571fa05b30f3663646f17010001	\\xe7143f383261e01dc2bd08402bc767c2a9c38b3ce483cb7910e46754a3ec152259c8ad3335741f43d027e2404c826b576ce5124d407f460e7fde41ef20c4c601	1652446723000000	1653051523000000	1716123523000000	1810731523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
235	\\x3c2e8a6fe8986306c8568edd2303ea94341073e1f0121016425aa1625c37f92354c5b4851d1ab1df21b9de67fff37d6056d24308c95d8f28390c447eb8ba4107	1	0	\\x000000010000000000800003a1961b62d5a5e5c311efb92daa9238541aa136d3f164dd9fa4184deb785619fc390fb74693fbd3467033e1b3f993161c19dc80b1dd111007f0d8ede7675fa45732e30b9dfebe8e722411ba54affd6fbeae5ee2065d03cb27ca68602f05874b439404cc2f09f310db467526aa57a87d7ee08f761d7091a08250bca77bf2d3fab9010001	\\x6b58c4f5a70a9391929ba61917cf67fefd0f653c1f35a2900279438b0835b473a73aca8e5a94491a2c12002913ffba818f476c45cb8766de22f397cb931f8901	1656678223000000	1657283023000000	1720355023000000	1814963023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
236	\\x3da6d8c24c7d6d25f179586a34723dd9495dad8a1f376e692924143869f6e9cc141888398c23966cb0addf01dfde0d8c5a5a63dd4e025c9dc4b4930eb4468233	1	0	\\x000000010000000000800003c363afc5a661ed0e0952514403b828781731763e958a4c03b0e4a6aebd4e91d52f1395b7b2f2e2eb7c2cf693e027fb4675b8919126ac86dd662582d0c21270f3314074875fad8bf012eadd927e583015ec7a2858c49910a98d4bca6c9b624dd343858191d2d9905715c1cc08a51d940295eb3029d9ace1a251197f24746aa8dd010001	\\x5b67f3d5c545feee6a39fe85b79b8c19bd374e47de120e3f3a57a0b4f54fd548a9d384a0c7351d2fc1ee31f94ab4d2c42a26ca52cc309292d8b581f1dff33609	1678440223000000	1679045023000000	1742117023000000	1836725023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x3ff2209164511e85c6185869f6739cafdbde2e464271a8bf66a6bdd6e0dbdd26fcb4804ef557c59ed225211ab6c1aebd52f2b1f41b5d26fd0de1ab6c235978f8	1	0	\\x000000010000000000800003aa1a26ae2c4c496105caaff420fffe569410df00254cc3c79c4f957d2fd31559f3ee5c6b066b5a0c4e775049e4d8e7e07a16643b6c07780d7a6aa3a685395423053c5427fe89fd6b5f84cf0584fd2bb60357435f2b7bb632c5140758a39cdf286e48e02a820fa50f3dafd26e19c6c7306e0d4777f16c8b4087fea0a07f2bc6d7010001	\\xae892d02683a507efc808285b6d9aeaf86b3d08a0fb35c351db464a3de8c6f890ded080fe7c9b5afca7b7d2e0e58a6678dd61ad516f8f6a49d6b782229b3fe0c	1667559223000000	1668164023000000	1731236023000000	1825844023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x41965645ac3983ea9f0843b1dddb4ac833f760de7121118c892e86e5395f7a165838e6e5843546e941ee482b6a2af3128a1d630bf9dc0130729427ae3a94ba1d	1	0	\\x000000010000000000800003d105681d4d83230d48ee37dc569c651435d4e52598ef400c74ad7bb3f29f75b8b0e129955f5fa681b69f913390aa6e1de388903597aaa47c81843e89cf2913757fd48dd18d93a1281b9a4c5cc82549e280e254709f074435ac6b101334fa23884d6594cd4e41f65cbbd8dcf0aa2455dc9f3c8d98ed1117d8df2de6537d6003c7010001	\\xe8913c7a873723e8512d1a7fd1d72b2b92adf36f390226eff69757ddd54ede3c00d37c902ff4c504187f98150dc2f722cc3cf9127684fec9bb76d229c3e39509	1666350223000000	1666955023000000	1730027023000000	1824635023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
239	\\x41b6b9c8849b58de07547693928a77d580191a3cca11bb36243e4fe908faa3e485cd02833b25a6ef750e935421b28fb0bfd7fdbb00bfef3093318e804cf3ee46	1	0	\\x000000010000000000800003d054b0fcc941d005551baf5bcc8831fa45b68ab78036dacf2d56d69226a64f199b66a170fb5aa6f3b89d91dcb174bf2456e783219e238f24d40cf6ba17406c02b3f2b63d986077e9759764d53700b63c2a846867a8f4cb2f0e8436d42202d5882d629d25ea0a77d00c29bfedc28326f345f246b1e8d30e7bc37b9b2621e4f4b5010001	\\xa481123a0626058e882116f0e5afcf2f397b6ff4752408bd5a69df8815c699d6c649b7c2c14e3825265df14d3ce292f0fd92b2c0720834177cc621946ae89404	1673604223000000	1674209023000000	1737281023000000	1831889023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
240	\\x481eabaca3dc3a316a70ce114dae7a600e0cfea5b2645312bf677fbd9e44e7c740f9d028d4c6dc5682476f61d21cd56ce6a5218d476c8bea5fa4283001695802	1	0	\\x000000010000000000800003bffc3b741448ee9c0b76425fccb4b911cdeb3ce0cffb5578e43ff1eb9ce6e4ae045bd1ca0133055fcc22a2238742d1d928495fa28c77362c1c54d3f9cb6b8b07301ad000446f7dd99d923da861455f747c698fe383a051d4c22e96feba2f07f61e497efd39739d944923894d5824bf9b3177abc3039195293ed3dfa20cc2a4dd010001	\\x78a5a93679183d3aa2a771f960be88b56852ccede056a12e62db2b5871022d88916641e50eecc06ea912cec81a2a164bf53adbfc1ef602ef20504dd028a1e807	1672395223000000	1673000023000000	1736072023000000	1830680023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x4af28c2c37f371bd4b8296791a8d504116c1903ec2782732263097c94bbc7ad67c414bb6e4a16d829861ef94693298f197e403fad93e30de023b7c4c7d9e8c4b	1	0	\\x000000010000000000800003c8607b7237a70e436f432cf29c661d6f16cd95841cae50a0dccf9129bb83a349095256deef9163fda278ecbae47c10fb1182c9738f6c9ccf225cb6850d975d096586806a23dbc182839392fe453599cb30381c297a1600d2e2d851b5a6cad591954f4517e0598cf78537687b48a7435a2424bdadca0311257dcb82f9a642ab67010001	\\x0b441a3d1cd60879e238483d6510e430486c29be692cb5f28f7d63ebc42f47584ad9cf05dd770a3644ba81c1f45f3bbf5347606b46cd7101645d48918183aa09	1662118723000000	1662723523000000	1725795523000000	1820403523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x4fb634177368e7bb4734ccc41128d8af7258c412bb3fc8e41ad742f1f6557329c78d1ee0e54e9b6a333d520ec5a9a4f4f23985816b61c99f125dcd1f785dae36	1	0	\\x000000010000000000800003b640057be5ac5515d9ebfea6fa161e9203f7bb3ebd976f6721c14f081d63fed6f560797c01f111a12493b6cbbeef57a5bad2ac8f4268bba0fc7dac847b7200fbaa9845fb1d03290959caa2aa7f925263d76912312d9814917d11c91dfd668834b988e6afcf3989e8b16d0882f167879af4d28adb5f19a043072024d2aecb0585010001	\\xd4f95da4589b56f26692328465d50d930f040f3d72bffa0e2be67553746a8c7623ff58bfd0fbc9a5562a6748f2ddafe216c9c16ff0b4c762e0681826d90c690b	1649424223000000	1650029023000000	1713101023000000	1807709023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x541a7e61829e89d927a7e51233e4855914d96f43895f6ec2eba0474fc4e42faf81cc5773a4e1dbe8ecba94259ff42d6823e567c2c6a815b6f68bce8f2f3ac55a	1	0	\\x000000010000000000800003b3012b4f3308b9034567fa29d38dde8da9eeeff5c6468dceb97296d667c2bed8cdedac6d0723d503d8fbf4382a5e76bcd1578b5536391a47220202ab634a97101b57e0d859e930a9294eee00dcc043e41b55f58cfea244bd5a8c15c4c9d569a97f1542a6ba26d826f26c3ad8e1ef3b805fa5c90cebd60c49239c5cdd4a8cb0ab010001	\\xb731c37f1714a323f9ef479abd3c224a8620ff8c585218e2daf3b5575f9ecf6869e9185916290a20e753bff46fbcf504fb6f40422851820af9128072e58de20f	1648819723000000	1649424523000000	1712496523000000	1807104523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x573aa4555c0ed7c25ccec24533d7886d2b93352a68884678315b1f781668aaf5a2e6c1f418aedfbe15183ca96c0f890d01779486b25f5e4f4b26a5490b6fc287	1	0	\\x000000010000000000800003e76829b791c8847a8c9e91e3e927c7553f20d167c30b6880bb11cb460839622c13c4fce78bd72785e4ae27fde19df7f693911a0129c0d69ca269409febee38604db0c17acc4545b402db99ea602da888c322135c747bc162ee208d766eac493bab7a4b46c517837ad227f1b0e7de97c9435239e592c9ba69eb9825be824d28fb010001	\\x15d5f772236423fcc5f5a72403b586face292f347101f0ecce9ee4c77610bcae75366452f831e49ea16ecd6396a0a573cc611db3394011aef27cb185d9e38207	1656073723000000	1656678523000000	1719750523000000	1814358523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x5a16b60dea8024b7be31eefadc195ecea386af6aa6f17a6dd86ecbbbc24af7bb9b6675a9e4050f9333f1c20bbdd1bc2059546c05c787bd77f3622cc731a98b86	1	0	\\x000000010000000000800003b13daddbef3aff454e4c54e9579a0238c88165f79709ada40b38446f56d8ef65a971f6ef0fff139d2622546b4f4e51e1408ec8f73b38f2b0c00dccbbff737eed7dfff68b88a82d6a0958710beaaa65763e87afefaa5dbf1946089bcdc9fc022ee16835539382839637261107b4daa11dc72a4158d5fbfb1015a32ec2740466db010001	\\x83e014b68c2622d7213491643fd620ac19f99b7ff085239471289e6b4452b85b6084d0f87422e856c74dbffeb886935b822cda8f786b30e3a2e05109c86e060a	1678440223000000	1679045023000000	1742117023000000	1836725023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x5c5e72618443559c9dc707121deb8b4cad68e802f3c91d889191e41fd88e7d07513548ea44b1a673f2f679a6debbf33be18ba358917fe2739d6818593584253d	1	0	\\x000000010000000000800003c98f1acd09bcb9823e8d99be1c0f828e3e955174ae1aa10f32953915d9e148e362d17f5e00ccee3a60a4ca43ef1c0724a99763ac5a18d30c0b8d74f359b87f9f7b8cb20bccf74ee91d08c9ba72e3669518a03e6dd81931800afc88ae7ac6696f15f09f3ebef45102c86d76dc272007b933c3d0ecfe1c1b39fd1342fbe6be38af010001	\\x831ffe79941b9b3326f7456519238389a2b07d119496f162561bd2fcaa3f975cfe597c8f5b97e22b736757edaccf4b9e40796abc659e3785702e8e74d0abfd0c	1650028723000000	1650633523000000	1713705523000000	1808313523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x5f0211f7c9a5edef980d8bf48cf0b85eeaf88a362698758ffa0f1cc37a1f4a11dad3a3c4bb698f27f4f5319b30698f06fb4a87c56c4e0611ca58d096d22fbe33	1	0	\\x000000010000000000800003baea34c8310753cbacb93183e3f52b2b822785a91e0cfe4eafc542869af32458a1f4c84d44a81a94937ca9e8e49e8be92ec94477051d343abfba8c31b76bf2a926b8122b61df8c170600cd84b60a5c21ceacc660e44a56a82bd288b69aa6fb01a5e85237da0b2ea4663dc720401e3a593404fac1a42e81df3ebe0de138578587010001	\\x38e17c2020efae4406c740ba42c87094dd6a8ac21f47355463750366883f592af99031ed3e5fabe3f455313cb3933ff0f48edbd3ca32a0d67f540c8f55cb0d06	1663327723000000	1663932523000000	1727004523000000	1821612523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x60ea234de525b63accd52914cb907ce845ca32e09fa6243f8f552ba152e2e0f072e5556b066f1ff57467220abb8f5c8a3d296f4c8234b76aa36684a1773ac162	1	0	\\x000000010000000000800003e796372027fdca39915f185e84b82cfbe1aebc1693dccd221ccb612187361b39b1c86696493e0dafaa2270ac55fbf8e152527389629ff36fd817732dd9bc2769aee65a89eed9d44f5c489ac29e3a4c68273e290455821ed5301822b5735ef688117470665a370d087396814e921f11db341e9eaa87cd7f8b8bc0ae0723dd772f010001	\\xd55fa14436406493e9d0db6dfc9da396ec82815a4e26baba84f31ed331a21d304ec73bae37953284b39b767b46841abb953088066a4a14c811d021003f103501	1678440223000000	1679045023000000	1742117023000000	1836725023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
249	\\x605a64767fcba3585d58590914308ba84090042ee8ff5578a35a9c190ee9986b8ac98d3e0545c93972046d9ea60453535239a62af779091ff1bedf2375a628b6	1	0	\\x000000010000000000800003d885f96d14e4733a435f2e29eed6c622927457adca19b594f726344d6a8bd45d17a5abe57c353fff782cdb64102db997a4ecb216f1ea7bf68500ffdd0065b6729d8a2d2298d513b6c1e7556712cbfd8de7506422a4f18a64ab51f0a6a8c37703bf85f65f1081207ff3b509da8c1038bc872d2d8295d8231cbea1fa557284ad73010001	\\xb958bccc74d704f475ead36fa9314ffe5ca4e04fe351ed184cac008a9395df965094db911c39832e6db4ebd855316f26b2131392d4034dd53700b8f1750d1503	1654864723000000	1655469523000000	1718541523000000	1813149523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
250	\\x65ea579afc1855135a10ac0e7565685c6e0987bd54e54e0a28f3b6d7f51c76974d79181feb4ab93677589e2e0e5d18bb352d02a80a66228edfb6cde3fda21f9a	1	0	\\x000000010000000000800003fd9452cb72faaa1a8d109cf510738125b595a3542e4017ea2db0cf4d3e94d165b2466f1e924ce88abdf539e1762deafe7b82ebaee18e4bf265e37f682e507112a3346722dafa5e3346e24c951372393434a6910848476291c4825b4c9971a718111194c87ada4c7e4ccf889fcc7ac467dfe86d155c16776ac6fb2046fca81109010001	\\xb8561ea815f5f6181a7b8376e9e13da83cb356967e62e342bc6c67cff94bcd3bef527c40860581f5fb6574a000b55fa65be72b31d082777cf0cc46de397f3f00	1674208723000000	1674813523000000	1737885523000000	1832493523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
251	\\x6c527cc12100a0db751f610196a38ba9e2c472536c9f85178577b6340b7cf45994455c87fc6c111a8093e53c12051c8bf0d1b92689bb3d3fd6b4b57395f8af20	1	0	\\x000000010000000000800003d3412101d608051b203d287d411283eef906806e29ec8083249b721ba8f07a89e532bfcfba1ee8cb023b26d45f1211faa9817f9f8d936c56bc0560ecca1f73b3d75d6cc438b6fea0711c0a32a8f1c8b8100d03056d9ac9a68cae1433d2f06d853d001c6aebde35af9af01ba6f3469a5b02a2f12e499982efc5e5271acf6d5d6f010001	\\x392884690a5af58e9595df517a80ec18b59d93949f68069bc9b9bb76ef94b0fec4f017468bdbaed48cfb9d3a645a655b0e4a7d730a62bfd0188732dc52361b07	1671790723000000	1672395523000000	1735467523000000	1830075523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x6dda869e1a41324912f748b7f3d33b7624c5044b6fcb8426cbbbb9df1d7cfef69f2abc2d47888a2bff4afadac5e75b1f994168ca14ffa4a662f5a26b72561b5e	1	0	\\x000000010000000000800003e003a3974a9be704d1d7a929fa1142a416e4e9edef047d07ff7f3ebdd35b2b947cb5d34fcacafd198457da779405189daa0623d7606364938aa4bd2f04249e2aba8b8620dfa6daae38f07212a1669617f5be1686b85686da293e64f0f109f087932ec1fd273fd751b300ee20ddaaff35b73f05a2ef2ba8a9a28daed70dbe6157010001	\\x1fc64609f1d67f4ee57ea9b87848fb409b48656794cde2fb2dfe4aa932f3af90257dcb4ec6cbe4966935cea9250a3978151482a372ea77a321031336974ef10b	1674208723000000	1674813523000000	1737885523000000	1832493523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
253	\\x721a2b48490f2f6433cab5776f603f78b9932524c76e411aa0d793f08646bd580e91cd703c12a1656865b55e04aa35ff4bf90f03391652ae94a582c9f98f4a18	1	0	\\x000000010000000000800003c2f880b27c3a1031d6818a7f10276538bc7b9c2b32fab83700e69f5355a4cc1438a6a0478d3af1bae4301884e95c79ac4d729f50e0cf71e54604c63177c2f76544043135c15edfe33294f9ca9207050af1e1d15dd877d98bb92d2d3986d7a462fedaa9d1007ea981f2fc33244c96561cfc673f5c06bdd893c89a933eec2655db010001	\\x3a1d0abc321b044d4b225ca7b423200d66fb6cb0fa0fe0caa597d5f57bf05b375c85dfa05a6cc72f3726ca4f77f8bcd6255cfb602b41f22b316e6aa1a079d70e	1651842223000000	1652447023000000	1715519023000000	1810127023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x75e27bbc7821faf7570c8932e2c45f90a4abafb43fa198f7402de41ea383dae632b2775a5d0e2afe1fe7eae8f06212dffc467a83219cb710449fe01900694315	1	0	\\x000000010000000000800003bf6a63c7652599f0e02703d4729598918d4a2591b6508b6482c02dc60db8bd159ac1d4fd64f7248af83cd9c970fdf2389c5a51d4a51ea108ee16c75cdde5a670a7d750b5a11caba0e4a5b22a197ac3375000468118cfd34a5b382aba9f0b06bd9557b5d57f6dac4668a4d5c16991c737a5c5db621a3f1d3fdc68cfdc8c25ec91010001	\\xfd47605d110f13c06b28d66b831b749e8835f61243422943d9dfd6ec9a4cbbd1534c1883010869c65c571f6557099d71c37f92b0b77a4474acc01eeba7b0a904	1665745723000000	1666350523000000	1729422523000000	1824030523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x750a16e44b9977521b1a0b4f13a3c245c4ebfe67840c80db2e93ab677e9d3237bab64bffb320f6237fcba5a79d7a0379095de35bd31957a53c693fd2db652863	1	0	\\x000000010000000000800003bd90573f18c03e853dbbbf6bae65f7d1c57defee0c0b6be04f3cf35778f3b823ab469e7deaa60a372fd3fff4e6740dde9e7218862c43fde4dff731b5ecd1c33ed82283e123bb8b6f940c9723765f68f01986c59f8b6b7a66985b2d192336d5342c1c3278e8470d6cd46b445977131a3a81e83808efd6f222e556cce9554cf65d010001	\\x88ff7d452455623b284ec8226ceebf42edb492e06ab44d84ffcfdadf0c054d03ec876a23906e41c09d496c52c1f754418ca883f1433b7122ada97798d682ca06	1661514223000000	1662119023000000	1725191023000000	1819799023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x768a3df9e2bb7089eb594315c68df50844f9d2bf504cdd208ba26d88995f8b8cae40986d771ccc38ba0dcacca85c612fb1443a0cc23ea445827dc1fc62a0bbb1	1	0	\\x000000010000000000800003bd8d612a7518e226849e3c34ce1dcf6dd447d9e161d92375645049f9a41c1f15754c72bcb486e616e01412c5f4b4097923ef3c3878cb0b3f255f4ace7586fa999e269766c9a9ca7ba2188fb3b208388115c4ffb4dbdac53574c6d50f5ef8a6aedc3432898e1b64900e92e630906bf1961292fc6ebba7b9aa2a28155146edb371010001	\\x21dc57455c41dd143e7afadefcd82f8b69f719af37741a9bd4408178f971f6dd7179629a3431c2a2df001c051d4f9c72cce1c27026d28f71d0ccc6bdda10a108	1673604223000000	1674209023000000	1737281023000000	1831889023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x782ae80ca85204f1583ea6dcd2e5cd753aa747ecb22a1b949a785a4e975473b5b635119992f4d1d53da707f1e8577ab903c845da4b0b6b6341727fae50ab6883	1	0	\\x000000010000000000800003ae65587ef9917f6a1b8060483fe61d109e95600875b2a95de608a8d14e4960d670fbd08fb8e6e5f4886c7ac8cc2a5fe713bf5742f00d2712e3b3cfd57c387ba5879afaa002983100c54f104f113b85b0b85f0f9132bacb0d88660982f736712638200ab741bab84e9fe9622f6fe647a8f5cd619b33811109303b2198849aee2f010001	\\xf3f32ad033b01b6f375dd755fa359d4dca1607f855d86fab0b8cd471bfa534a866aaa3622b60edc7832618ce2462fc3eec9bc2a893cbfbcd2b3add92044c990e	1655469223000000	1656074023000000	1719146023000000	1813754023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x7ee64a75abaa625561c326b35c135bbba70dd110c3dc2b7c10453a09702ff886c49bff11603d45bddc8855e717fb921bca18f055e06b4fb44712ed5a7f56758b	1	0	\\x000000010000000000800003a8d7b7cc7972f7e0fe0d2e4028886fa910f03d35961898b2029af6fa9e9b75021b6ef71c77d9d1bfc2a145b44688c7d2a685071cb84a850440496dd48872535974bfbb82bc74972ec4258411646e628dfa9aae564a310b7deb393b65e649d13d7a81544bc5525f2834edfa4afc75655be117d6ec570499cc2c3bebb10c9ccd89010001	\\xa0dae87dd9b0550417818a292f16e55866c6a9e08c1c05c81769c63da6cc62cec0ed98fb1bec2d0baa8ed0a3f5bc0d2895b8f0dda1658c460e58ede21f88b309	1655469223000000	1656074023000000	1719146023000000	1813754023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
259	\\x7f62e775f46bc66091239a0f944372c65a29dbeb1895d8cc7fc5217319af31e99abd0f4e414ddab002cbb34a31816c7d32ce0f034e3f3d96733d18274d8de1c4	1	0	\\x000000010000000000800003a05ca4b172563bb2754c92457d6f7f26e2213929572afe3dc7f27988752a162a80242e3dbee9fb2365dbb521d41d5149cc75080a1f8b26b161a7d9ac046e89875e308bd0d5f5f9fa9f87a4ea77ce95442f43552f0c82e93ab0df5d79e9e3fea7cc46584e776e7c550b665c67ded3f27ea8ab00db67def3dd33b2a3d2ccc4c2ab010001	\\xe816093647e0c7ba2fe6ed4f792f78347ce2a019c6462c853dd82d8c98aaef135396d2654bd747bf7a106c6965c02e0697f242b2447d87a6cff5f943acbe330b	1672395223000000	1673000023000000	1736072023000000	1830680023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x81a23fc79fd5619aa279825a3ea1421172040fcc35c3f997bbb43d27ca601b5503342ebc4b1c7011744eca2cf9c86c64eadebaefec74d5c01d29c17dad7b45df	1	0	\\x000000010000000000800003d875f81c150c48ce97d2dc7ccb7858f07a9a9ba8f48294ec8476826cec701e692380de091271a1e5058acc6fb09a223d3978d876004289ec9ab4b6e392dfce0c8426c36f679f8e1978e04158380d11868cb8ce8306be3d8cd6e346673e0f9e65c2fc474a01455a8c0a86a396e0923d773b41798c75383f0bc23894501a0edcf3010001	\\x3190ed0c554849531e4cc9f3b557f9b1991d5c1a6cc4d684e9903da5de1302858e41f4705e0e9e533e584ca666cea72c237ddc275388936fa1d57ea65029f80a	1656678223000000	1657283023000000	1720355023000000	1814963023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
261	\\x82669cc464a33dc1bdf0e478feae16618cebf111167949aa3d0b65a9ada2db4a31632d503e9672aa37756854cac71bb9906e3ce9e09d440a0f00cf33aa85a9a0	1	0	\\x000000010000000000800003d60b1b1ba269ab8bb6203a35ae6c3aec2c0be02101a008caf24ce31e7ea0c430de5a882e52865a987089e11b14a44225850fcabe58b33571db0d75ae5664c6b80c48510891ace32dd57b2d495e477ce3eaf4f1dcc1eca4793ed9c1773e0e4548ffd3c3e9393f8815c5dcd324ff6731dc028f37ccd356fef01447eea7977b4c7f010001	\\x8341342b61b0d680ff536e354a79e07532e81266773dbda268cedf914fd69b83378ab0f5054077acb2da3af67dd25af6c87762c4795bd3a8a54cc871e11bd308	1656073723000000	1656678523000000	1719750523000000	1814358523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
262	\\x865e647e1c0ff9660ce2013ebe3a3f7bb05690d6a88d199121c88b79e2946a163418438d643711a0fc07c0b15d324d51eaa28a98983c249e9a378164fb1582ec	1	0	\\x000000010000000000800003cbe8f96d90a8a4e3bea4f3f5af7feb3cf9967a4e4121042218b2e30bcd19e61a473a201b447a33adb3a6f5e191ea465597b3c18141a4856ec76ef050b51b28d9ba4b83e561191809fbf1774265c5fcc60d0da1642d879e9194383e4e095601ea4f74d0d95dbc6ae57d690ae15c8f8f35d33d87a5fdf0d68197516808b87adf71010001	\\x8d968c8814df55c28a064806e30a8397347ff6befe33fb422a2b1d458be5c7a6c96e8dc0d2b19fd34f934c58d5ebd55d34a684408efc0bcc89da8a5ac0cf5105	1651237723000000	1651842523000000	1714914523000000	1809522523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x880eaf2835f8526a30461ce19a1de02a265032a3dac223dbb71d2432d74c0b36b4dde753fd09372f5e820a87734be9c590fc30ab9cb38d3b7e02dee6c54739e2	1	0	\\x000000010000000000800003b1a157e34695b7b5bbb48a4ded663a5bad4faef83752000bb002eca1578017936257f2bcccff64b61f7327ed32067f9989bbe2bb3afd6b312839f6f8a3286d16a7e96e3e1abe1d1fd03c1f009898b892b8bb05b84644cb248670e757359849fbbe3e6c42bd133ae54db317a4e3250e2def146be19655bd63caf3edf94efa9f79010001	\\xbcee71accd81e2dddeadfd1ece90eb8eddb3012d9403a46ccfc6d8c37c354e255ead57f3fc4f9bb4315b1e1c03690996dc11b53abf169123037e568825386c06	1659700723000000	1660305523000000	1723377523000000	1817985523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x89fe6b256b13c7f189b6d6eb4757f10d6ca79b18e26a802470d3fc98b2b743f3b7963fb3be65231be5b5839cd40072cb4689f0ba08e3329e020d650a0e028ea0	1	0	\\x000000010000000000800003bdd4890bf73c55c97df198108f2aadff4e8395e3d82b94a0b54df7768fbc17ecfc59eb0d4331ab00fa28ce71773623b37e9eab8008d028cdefa7fb24b181cb655151781a989b0b56b9251845108707406362b565b148518d6439fa68ac84962c0fd78216718096169d8c6a6f3f20645c03de01bd186cab14aa98eedb163682ab010001	\\xc44eec679947831667d66045be8da9ea88e1c1bebec9e1f0f0655884d9a46b4ffd493c000365b437720cd6bc6933499c53859becaa509e4a74a03f1f40917303	1648819723000000	1649424523000000	1712496523000000	1807104523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x8ab210adf3bd022d393e806b126c0bfd78070c90212a8a2eb4711d49b94c4869c8afee3831ed243441ae3b498121e18cfb00bc5413fca56e53df5186c1dcde3a	1	0	\\x0000000100000000008000039b0bd2a928c28cab739487c2c2e6e882b54722530b42101165e97014e1eeb10663b811d0c221d8d2adce8b2b2a50757d8953d16718b1a157753cf7c8679756a3fc4e5f1ddf8f480f0c24dca513f8bb75bcb7f2a3e3f671f3a13cf66f89ccfe014a072772e1ac1ecceff6387b1de61a1926071a231227793b9b92132dc00d6639010001	\\x09c197aed39d3b9b60432ff1181e388e465f18699a5027832fd21abcc268ae2800e91a3d695d666d9145491a22e68db2dcba54155854b336e17dae579fb97f05	1647610723000000	1648215523000000	1711287523000000	1805895523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x8dc678f20a03e5b4f1acfc99ddc261fe4e59d701c75313b25c11fdf4f53652fe0d307f527fbd5c6af7f1e0ef380c7ce1ebb0e053b94e8e0adf86289b17122475	1	0	\\x000000010000000000800003bc1c0fdb28d13b97a4e81829483dd679fd5a4e1755b06bc027660dd191326335570214baa961d9eb4b2e4d713434da94b4b38ba6a6459e020b212690adffe018a8a545e25a55f70633c20765b1f638fd38d7900616124454aebd35c1feea6c3c635ffdfdf4c44744525e0c17cb9f9a6cc19d4353c3bee4b4fdef8417ffcbca93010001	\\x3038c3b4210335ee4ec113b1cc7f9214e6c8defdb8546fc34585af5be06f203a5d1052d4bc7ced48bdea5efcbdea792271b8cff25f5566b96f8d54f115c37203	1653051223000000	1653656023000000	1716728023000000	1811336023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
267	\\x90ba8975e81d4aef3d5accae89d4a37321058818f4028fa9adfba970fd94c7d0b915fef33eed44ac62743c58ee2d300d5f0a30323dd55f42a9b0f4b0324e8e5a	1	0	\\x000000010000000000800003e92782c8955e89b35e7c13826dcf1c6a5e680f9914cf71b3a49c44aa15885e18597c1a18a8edadb9c1d35c82a95efd491055eab2374079d046640b350748bc728aebb128619494f6a4adf00d5c1b23930cb715bfe2a1a11fea8b1d5043f77c2e55b1266e0748cc93d0a0fea2ed56ed400d132d73087d183b1a9889c780ce36bd010001	\\x0dde5309812ea8b6bb3ad88f7f06bf8f7c682ce721b28bb25ec480f8453f103363bea72fadd6a3d2ba551272aa835c5ffb2826e80c6197289aab42bc44484e0e	1662118723000000	1662723523000000	1725795523000000	1820403523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x91dec0ab11af471c9e6cd7aa89fa9432f400937c912926372d9ef1507350181971dce63f27acb3e40f2ea5f7c49c874d0ac687f5cd5c6ba6ece24178d20b6e5f	1	0	\\x000000010000000000800003bdb623431f18d8b07aba9a7b228657ba630e84a0d65588ddbc801b2b2a29c89dda0d713d68207259eb632f15f2a5ffef766483de141f6b6474430b1f678d4bcdb909d5707157748651996886f66a098fc0332002b7a2abd003212f4df25f80471326d6ad2bc9dab2288bbf680fbbc7eca203e18f0e2394b91032d6cfa269a41d010001	\\x404a36aebcaa25be72f17622d490d3273d8466295b3ef3c5df22214cebc8a59657e209acee73cffb31dfcf856f541f5a54626a1a0b6e58ae75835c6a622c5d03	1674208723000000	1674813523000000	1737885523000000	1832493523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x95267ca3faa03b8714606d12cdac5e90c246d05da168abdbadff93e562e0d44630a7c979cb8d531aec56a095baee0eac313afcec1c9b4928626b64f69ae41ec6	1	0	\\x000000010000000000800003a511e1ff5bf125a620ffed675fc2cacfd15455fcf85165af6b8591576cd9de1537e66cef33cf0abd7a99c807d3b919899f50a88d2d115fe7143e3e2812a10be1507a505069535162bc5dc404728f0d99dc7ff83177363f905b769e94869d8dbbc45549d356fefa5c11f6ef2841ee0322b0172577e56320cf0987233ceb0ce249010001	\\xc66a394ac0b45272eab082aef6f23bd4716153bc8a9cf06f1d536fbd06279330534e33cc6e439d760637e22ee9b89cdba3faabb6414f5a251d182ab44399db03	1662723223000000	1663328023000000	1726400023000000	1821008023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
270	\\x96365e0983d835081f66a29e0c2e577013932c2c42025f89291aea7ac126540feddd3d57aeea3e02df3a0b02e0d38cdad55005f06d460357dff3fee0801755b4	1	0	\\x000000010000000000800003c59f971fdda20d62c8dee6f97a2c8f9855154e57f342ea0718b5b1db70d6df1bfbe321a2c76df7a207b9ab65ffa71fe280148f55e108de01a6e6a74da06ba19b190cc238e306b1d2c656418e3fbc45db3d8b690d767d696b9e73c8c45252e9d4dab6f8ea55e0ebc9986c093ec898693b02db41b393152f07d91a726799c58dbd010001	\\xe2966ead7e50853a36e20496e1f5cbd277a001095435e9b9e7716179c53f40ece66dab2e21a1ce9a344d52fdca4cd20ff6d13d9d33e8e8ace34f1d602ea0bf0f	1652446723000000	1653051523000000	1716123523000000	1810731523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
271	\\x97d24e4986296fcfd29287d1cd0b9704faba576b2948681def945b3c1c66989474001e078a937dd8535b00481ff9f14839abd79e9539b90f03dac2a230300d52	1	0	\\x000000010000000000800003cc63cce6e2a2ab1c1004cccbe884f76b583a5eb05a9b613dd0312f46f2cb229004de063d77aa34bb5771869b82b4cde966a097d21c6f1c4c8422fd421506a3fcfa90f1cc4b5165addbd99844166930484ffbaa5d263dec9124cde506a37abf582a2984984d93f273f53b1d9c31570cefd64d4745acdfd6bd9c47c2ac7c067811010001	\\x07bc9e3a466907c1c9cd73ca926eba10cd1fe58b763e15d639e1fddb9a6ac1f3060072324cfa76da7c1a98596e695462c6b7fed41455c71703d3b2c8e5750808	1668768223000000	1669373023000000	1732445023000000	1827053023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x97924a6e8ba12aa83838668ac1c0ae48b62c34bc2f0701412fbd91ac3838434227b4d8909c1794e8fe6c6527381330100ccfb47de39e29494341058d756b1be8	1	0	\\x000000010000000000800003df30af705c31cfe65adaae34abf6c725b3595dbf83598146f14906f650061fbd68a84cfad1e7813a0c8757f548fc2e0750db7a22ca070029620a0be7250885f1d633b476e5cfcc5bd1dad4a33db99693045642375a1f2e07cef895d82f25f2b978b3c09a42483bcbebf0273c4d0755afe611287cc0247e775e69ff72e73cdb15010001	\\x85fe33421fba5c7867c3e53d823f21795fd9e20a3ff41199b5a8d3d4e3b3d97c7ea999dc0edb1ff3ebd60fd325b7c04da901c8f860829605f0c02e0ac44b6d07	1668768223000000	1669373023000000	1732445023000000	1827053023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\x986a4cce83b5f1efecfa4bf5ba5860774d6699dcd0f15164baf97b7a936524d3a609e256a07a583abd5de596cc15f54d420b79fbd0c9e2b92a1c0a060c606bbe	1	0	\\x000000010000000000800003b44ecde8d8d1c22af7e1475bf47aebf1186a2a2e18d024b85216a3dbb4785a8aab4457c5d6a678c882a2d038bcbc96323a961f0280783c5293d3679fa9752d963d893adb7097fb434d480ef02e9578913b5df284e2abb3b53f33de232650bff81b28b66eea5b5ee5e12b228f03b6a07bde4db418f0f5bd5f0cf6543516a97d91010001	\\xf823d561e6a050b41044e0a80413012ca36d1f1d76ad7c25c9e524c3917914269ae72fdbd6999f9a003c3913afe50eb45411e372c63316826931224c79b0e90c	1676022223000000	1676627023000000	1739699023000000	1834307023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x99b6257f8da6443b1bfed7a75d5d65d3a167b7526ce01cb17d09d7ee0eaf03259f561d97000d162c35b7a345f5237b2deeae7d14bf058e14ce83a6398a8e9083	1	0	\\x000000010000000000800003d9f77109dbe284669c59bb18343092af95ba9e8ed65667e5f1bdce030c99e5a58237766e544639cf96858843c1b4196e0ffdcdb3f23d6ce81d2d8a7c7a715c533814533da3c389805f46c2fcd6c1d191f8a751b900f9d4f8d3772398ecce11cad6e3eeac33e83f880fd53e4600e89b5597fdca344ddf559922f0059a4620a437010001	\\x08daddb010a1768eaf3751c9fe602835cf5cf2f5902cdb338cf032a37cf7c3ce873ff8f7f5b864e60ac28f9ed701b1b81def0c79c8fb444eb2371dd9326ee505	1651842223000000	1652447023000000	1715519023000000	1810127023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\x9c9a0b10ec6465f95d0450edb141e26ed336cd24f93540f54a2b88ae36c1609a1619b41e178da789e22e55d083ee63fbf8d2db1d48c55c99ae04dd25fd973332	1	0	\\x000000010000000000800003b0d3f3c7093683ef2e049f5fdd6b42bba0cf4f4a4b7359ab2baba242a01061e734aed77c44d81336b4140ea117a7baf23e3414bbbad30da02f1d792f47807b230209e05dc00a580dc71acdba74d5c8ac1606646956593ac95650b6b4d92def22ca5713ffa2d5ecc52c31ca63523d9090f3de95cd402ca575a3ed1af91e43cb91010001	\\x450094af3a341d32e61f762f3db612eaea5fe5704011dc96b58ab36cb28a9dafd57048859420d8132bcfd29abf1d686d4cddd2896a521d6fc00278450b2b7f00	1679044723000000	1679649523000000	1742721523000000	1837329523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x9ec2d0650870082977d7fc131eca2a28a5535984243ad38ab5d40112331d7de1482e54288b7b632cc59c4439271dbf94638850c234bd1bc2c121ac7a75da18e7	1	0	\\x000000010000000000800003a0212fe689aef2aab3971c61fbe0c951cf7724cf0badf7399258ebadd43b139148c81e78c375b6494ebb964a408c58e3294487dd54068d2a353827d4a12eb1ac62ad59748d32cf3f8f1fba12bdcd6b7d9cc4dc1c7f025607f0d1ead1a402d362c23a78b9d6d40b45531241c703a68f020dd640ad9412265a389397604d2a1763010001	\\x8a46856d72066e9561fe8e329c5ee694776fc66e953b9946457d94835a4f1ff826a75a74733e11bb3bb79563034d677f9d2bfca0f85cde30573cd20ca1d7b60c	1669372723000000	1669977523000000	1733049523000000	1827657523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
277	\\x9fca6fa7a0e63bb93643eacc9e786c8250882e7934c3056495df33dfd4b64e8e3fdfe9a3a76215efc8df0b37a26a43e4e34791b1c244a48a1d750a8895b948e4	1	0	\\x000000010000000000800003b89b9084e0edc256a99c7083293274eca574f4abb822fc82dca61eb1c90a9d92c27755086eb9b9134257ebc6fde1203e553511ab5727ab9202495041caae142437d26f01bdd411765feef8c410eae49d057d06a9cf2f71fbe0fadbb293b58f624c90ffe0b2d63609cd9191d0a7c469058c155844b556db79deaa9ab1fb419ad9010001	\\x3c466794e8e10939ea3de044fa60b119099e55d6fe4ce4958f0ecd010fb3e130e040b9bbabdae021d4023fc4c9f4f4090aef1881541fc21b1a865d893a547d0c	1652446723000000	1653051523000000	1716123523000000	1810731523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
278	\\xa2dafc0fcf638a1d53e0c10e6b1b63d16056f5ad034d81cc14321651e0d98aa7ddfc07adbe7674d18628a2e879aeafef93daf368b0a79b0ef90be0a2103c0b43	1	0	\\x000000010000000000800003a710fd43ba60257e46d3affaf2a7c53d4fba84f21b17249f0dbda2672860e63341b6034b56de383253cb23094dd16436798291d03ddeda608e0eb1b2405b814fdf4e3fa4058675f4c008c96f87d2e935f72150f2841558a58c8fd7bab8e6454ee35f1d98b215a1f323c0efceb630277364b624de2656f5509c463f3711fef4f5010001	\\xad0b965c30f1ed82df6f09f9d0f70d0716e35f938805db5678ba57fddab273835fc05b45f1b488e15ab63e4bc389b0c06ace736c2e2b20423cdb7cd369655100	1676022223000000	1676627023000000	1739699023000000	1834307023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
279	\\xa30604d22dbeee7ff0728b7226e13082b4c5fa29b554b6e2238ce76453adf89316be5b1013714aba6d043f6b26a6856c4b56c877e2d341ad12a3367e142fb963	1	0	\\x000000010000000000800003c9b003ca1357f7d4c2e7870b43d64821227e2643333838c85e1b5e19f1160ffaf74b81b50f572fb298f75df92433b1cea3619baf02f472df7bef4541e22f1be86f885ac094f5ff74b6b0c7be7639d9ad452d5b782341dff3c55def908a0e5f2de4372e06069e24b965516c7270dc1fc4f2848dec422d1b37916de0d01a584127010001	\\x5caa65c78674024b2ffa4e672330b06170d558b45c571dfd4fd93923d8cb6d73364b39a91acb2cb7c4cda5bfc80016a4ca6c539ee8df2a012e5edadf0acd8d05	1662118723000000	1662723523000000	1725795523000000	1820403523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\xa4ea17d550dfe777392f9e9a54107ff9a4cdbb219832865cdb0943e6aecf89d8265fec2f34bf299a2bb8acd0574691b0b3297f4151d8602ec60f27fb5d061ef9	1	0	\\x000000010000000000800003d0000ad8791cd415e575c3d54a1795450550bcf4661c8c87a4898a798911733641e3b3b07d2440fe2450ae38f74604c9f6764610d5fa90b1186a04cfca487d78ad922751eada154d208f91f3e93f15944cfe379e24721fa003a5ceedc6820a1c9ffd0ec8a5d4fdc330a80c5b23fa266057f9ce8244247a7835c9467c4c8b4c45010001	\\xa710544678b4f865a41b4c41bd44b077354df7e9abf877a46afcf48e283ac569927ba3d2152aa2bca7dc8cb1fb12b94bca0659923081afab1fdd660b383c7c08	1662118723000000	1662723523000000	1725795523000000	1820403523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
281	\\xa5a2d65e2e06d5bd82ad6767b2976edf2e548c798a5f71e04c31651354a44527577a695d91bef8e656bd0efff9428343f58a40207ff95bbc0d03fbdedc06890e	1	0	\\x000000010000000000800003bc1c3353fbabd227ceb6a301c5cad50142f9d35be45fd7a01de505f48bc746ea1a80182472ff21425d02f412e0a6b3584f7bfce344c1a230468ef72251d420246769154234d0f3d269227274f4b033f4821ae4a5a56a15f40fd5523cb002d4dd9ff7f978908cfc0607f4edd4b3ee6771858c53fe725a7f07bab217379dff0a81010001	\\x25783eb3e729434b4630b9a66e66ed3d99c3c4eb2766574ad42df184684d95f6046ae6bebac7e66a0ca317d36c106baf573d74d70a0e7d5d4d1362356d7cde01	1671186223000000	1671791023000000	1734863023000000	1829471023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xaa4a7e3ad38bf7360a3298e709bc8b17b488fe2817427f35a9b225c8798f62b9f77874193e354d55354b6fb069bc8f0464d760bc8478009caa1f253c2ff0b458	1	0	\\x000000010000000000800003db544943852440615797918d27108ac8212bc8e5ff183159bae106d9e08192071dc252c4a25e3c1329b4cea2ee0ad75d3473621fe4bbb3ab329f3debe7abc274185ed6cee82b402b4e2cc8ba499fdcccc4907ede18b467008840554b4027390c0c1a6b6b51bcacafd63b387d6facc430c3ce060a8026829860ea0b7f186ce67f010001	\\x82b677c1c8fbb5437ad1cd5bfa44cad971b6af3b4308bb9e413ffa12ca60a73a46235d6e6f6b79872af6dfb6dc9a2a2df65e79c3637311447dce7c2fe6c6d907	1663932223000000	1664537023000000	1727609023000000	1822217023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\xb1c603964a2eadc64c9dd511abf880a31ce4f945abb79f41cf4507a01ea16a80452c810f7532d390d11c862a2c26d6084e151d307d3c53a7a38cb3936ff776c8	1	0	\\x000000010000000000800003b3029f05d62bf2f2d12b63dd8603aca587c60088441f6b2b0eb1e88526e8626540f354c162ca201a4440e494b3b3d2bad9498a50a45a7c5b58ee7e950bdfd559aef0d752ddd2f0fe8f9308b2b91ee3a10d2b33c8629f530c64cb79c58b361188c01459111edc7e162b25363d058391b4484ff656cb0ec071494d8775442637ef010001	\\xe86c50eb4a79703126f84f21e0e4a3f4ab479c976e1907685471146fb8bd237691d242e27846f95854b24926737603458209e047a84a2715a282661ba3c7cd09	1678440223000000	1679045023000000	1742117023000000	1836725023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
284	\\xb28266008ac799a5c6f5d45658bc1cfb4cca75138f10fb73c371f33aa77d390dd919b902ddcd6fa3e14dbf74cbe910d299fd025d6880fdd5ec4798bced703c60	1	0	\\x000000010000000000800003cee673aa0c0d55700af419b6a0a6856c50b54ba480aea74a7f1c30d24bea89204f4ca95933584927011d99ba2a732350258a632620c7ac19f0a4e6292403a0a9f3a9b88ad58335581c459f522afd1e587e982c42bf1415b74b71fcc72d36a826160c3389a517f9d24eefa451235eabb35d433586f29924c6eddd4ae5d45d5787010001	\\x4c2cb1892cd418a79bc9cce2a54516d217c43d55439c4bb267524922ca454c93bf68e60f0fe1d2cc4be45b906188e19ce6345f7d79ba0934dbf5f99419e1c50f	1653051223000000	1653656023000000	1716728023000000	1811336023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xb2fa17c848c994df94f6e30499220feb6e8133979ab4c225dc427663b728d7c4c40641f6168ad3a439bc70ff5fb8847b7eeffaa894bd376c4fe931f1e9dc49d6	1	0	\\x000000010000000000800003d61681a1a60fc526ef58c7c04d542bb83dea30268118bc58bb3683f3ab123e88745f47a74f829aa5aa2a28d809f1f44928187b4c8b69dcea940563d797cb7fe76a52d4359a26fef539ca690b50c968e62ee2076c8f2e870a95272b267fde21dddd4c42b4330899c68454af90496a20e72197aaedb5c013a5616b33eb64afefcf010001	\\x08c3cdc4f3cd54c01bb2f611d77657f4b6228437a3fb56ddb2f1f1b17255cd19f232fb4cc45585d78486e6a2a1d6b3df45f1aa1f1da50f57265e12473cd6880b	1662118723000000	1662723523000000	1725795523000000	1820403523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
286	\\xb5027b961885a6ea817f99285eeeda2ae18862bfe4e77995bb1ff2fe1c8768370211777972bec3f79547e598234f073b99861a782c8bc99097bf2f5ccf3a06f8	1	0	\\x000000010000000000800003bafb3cda044d36b5ba7dde6f59dc87e3d77ea94fef1f94515a0da769445f43218b7b739d51eb2d87f1509ef1b5657bdddc7f394edf94bb46d26d442a0cd83c51d9620af0166d41b2a1d72e3b658de9744cb6d57c74cc7b62a80297452305210a7e03f3d123cddd9f21241f02b6250dbad9177a7af7b271aaa0f3e2ac8ddc0d41010001	\\x3f5899c1a954725eab0b4d827aada61002ac3e96e9080c51e4e750ce907e65c3103f95ee5ed737380b40dae88ce2b4e8660d32b8a688329aec218ea15de9720a	1674813223000000	1675418023000000	1738490023000000	1833098023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\xb936652ef9de0f60fa8d9f65459d76e945d51001cb4d11d106688dd1ca5d9e502b5a15afa6ce8f65b7eb9716de8a12d93aa954669340ae61b980e62b88a805ab	1	0	\\x000000010000000000800003de6a6fd6142e0f674c62d6b2feb9283cecdbf7d926bd16ac57480fee7e15f97accde335d7ac09ead3735496992715531f68a49bd88306ad6556d3204b5e21d2a83e1a517d3d2d0f52f07a37deea638122d2163972d5651866d4d04949ffe31099d0adef4fd32343e275ed780977df55e3807eae4312b2e96624e95911aa5b555010001	\\x7b6b6f4347079b8ad6a5679303521a54af73729cf3f76991f093d3b97fa4483b6928f684553959675320fe34d6e15ceff786edaa24c8ebbc7e8d5119b9d6e302	1677231223000000	1677836023000000	1740908023000000	1835516023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\xb9424572c721c8ad7d66619f2abf116ffee647c329bfecf8ea75925b40f18261c2ff5506f3d63b3d2534592b68941c35a7bea9e31efc406dcf5efa6845159a89	1	0	\\x00000001000000000080000396d37f775a67c702343698280b9a4b54525379166594f6f003dc50ee44cbfb9ff9821d1b8d6a0d71cab924bb9d66f42d8e12a14fecfad48dec811f5a0d23f62c9eee0c0bec68c5bb97a05001b1007887438f3d2768cedd0710c047a43561393d60cbc806d56728bbac74cbb972ed47e927b83d36abea80b0b3e84d1764f38459010001	\\xfb1cf72fe1b5e42a06ffbb89aa41c97f8ae3ca927613d39c80ad5889213fd9fdc5dc707fd332f8858b947a2af89da425b3bef19c98991809b076979229fd2f01	1665141223000000	1665746023000000	1728818023000000	1823426023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xbbd2c4067f6bc1f1dc2359e9482b4d87b00243656f28ddfafde4c00bca7b9425dcd5cb0b192a8a07533de569a097562664a9a41e2c81eea1e4914529b52379e3	1	0	\\x000000010000000000800003bf73c981629e3e1f8c54b43ccd16b3b6cbbb0085954a280ba8d83447c6f088ce0ff9bd359679480f5a1d1d720d174db6491abb96e8c265a731ad3efc92ca5e0cd8a3241e56fdf2230c1bfc5b9a8cb9e88a6c7062a3d78231150e5a551ee8d06cb962dace0049bf7d7a6032515f7f71a84ebbed01250e5ede136b06f221c91569010001	\\xaa33835ec947c21c988090b67bda8802e54ada130221562bcc1207c5ca528edd76b88a4e3aa21ff830dd9d3da347ba6ef08f8c1454e37e218b8dae7e8f1cc003	1655469223000000	1656074023000000	1719146023000000	1813754023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xbdf23ddc4bb6344b47cbce43be5f7ef55d081564f45d370e5e512c6761bb7cc14106d874763e481cc3c86badb598bd05b76b25affa62ec0c1335af6c214bd01c	1	0	\\x000000010000000000800003e6d3a9707d270a5c9139719a999077e8c27079b3d61d1436e48c1de4a078b338b9d266bf2b25cd3dfa0b7eaec596fc1670f30e00705ba922adac585de863e6a7ae456c95f37b4252e3120ebae7e39aac4e227e836ab7239a133dd10fea4552558149fd6f4583462c55f63e598b8b4d4b836bad4a88fe3ed4557d3c4f9856dce9010001	\\x01d4b010707b668a30faa9081e1fa523f79f2c8f26241f32627788729304a3baefe86f7580f02967c03899b8f5dbda7d285c6e83cf69fcab0b278fab892ed302	1677231223000000	1677836023000000	1740908023000000	1835516023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xbd924f7a449d1b5379c126da464354d6844b6a6b84a892c16388286b1db8298b72e9ff1e6e31d5ad71d3ab79ba118d9f52f7e5e231a5494fd51f407368a9e6b1	1	0	\\x000000010000000000800003abbadedadafa6dc0909cd7456364b83b49810331337625d0aac0154c9adf0c336560378af5b2150eab477bf993f50669167fcd56018ab482d8f0c9a6c56b2ec03514c638855e68368f9e1a9c4970aef1ecb7843f767fffefbdb74971a3b423d8a086a737da09419ba270b2a382fbea1542cca9a3ccc9653d9513015989405e8f010001	\\xcf356bd63d5637f17c342562c27442fb64f8c42ccf92c4d374e33c49442c4f5c5b764c9eda272dafc0d8ad0c11c6e6bb98cf53988f6409c6e59fb16c8c77050e	1654864723000000	1655469523000000	1718541523000000	1813149523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xbde2b9d46aa42d327bbaf3f3ec93d6af7414e92932ca82a8d510dc06340b85c2da9728101110ee969d54d5f914dd172380e2b8e760d241b5594d0b2acda71592	1	0	\\x000000010000000000800003c6695074bdf529f88eec6cd9a8e82407e81d953c3a00870efc34935d7388653aca465fed8adf7605cd33c0eb1240e6fe4347ad5d94eb2207f2bf95087e1675e0a4c9df617004554b82fcd499f6dd15046b88593cada67dd5cd5a51f4a639904d042014a370552358f63032a6c494ceb2369058cf9055edc0daae43ff820d4cb9010001	\\x91f7f4c395cb92ba1fe492484ba88b684ff59fa668ae973c705e6d26b401edbf37de34fd776699b1b95cb33c0b60f87aa201ad9b5b869808073aa04744419e09	1668163723000000	1668768523000000	1731840523000000	1826448523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xbf5ebea20043412156b453cc94a17b961acb18c406dacb833b0a8c38da2420dee3542c3a7f862405945dd4c9860513486c391f76938dec69559b471787b48763	1	0	\\x000000010000000000800003e017d73c0cbce0d97955673489bd7653cb142b8b1da803c9021dba9a0fc565ba08d82f026a0e7ae3147f1e1fb245e9477c2aad0e1fff6d74c175bde47782ea0447c096fd2bebe01dae939e70bc159e182115d001c4af1f6ac480af6520c52374264837578e877a0578815ed7e59addcb23b0661812f0e046f9167b6addc11bd1010001	\\x281a85fb61e42548d5a4deda429438a17b8f9e13744a07743e339ce862003ae6c07fdb8df502333335e8cb4e70684d249ad665421e7747170a51162cc47ddd0e	1651237723000000	1651842523000000	1714914523000000	1809522523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\xbf8ef5acadd6392ce0167a43f3bdfbf9c2ee1ae95f2e18aefd13b2aa98b1ffc4f41f18c65e2e2cc6e507f605444e86cbe4c123663f3413d49acc97de40617115	1	0	\\x000000010000000000800003c4359012eba4058d03b87b04361fda4e0ac21f14e3d28224b93ffdab08d9808a605be410fd72a7e0631080f2a340d0185af722bae4a25d31f0520972134f61cce1259684d62b4261b06d6219a7158ade4f13bce3c0ed59dab5cab83e803393977277dbfbcf448a01cb6a3c409913273aa786a750c5c5ca86fdabbb5f586fc019010001	\\xcc1a5a780383fd3aa96d8cc07667dd1790d23d0e9c5b946e85d35a08032cf07b1c105c9055addbb62694ad9a8d22ccc386da84cbe63fd049a7101a85d72a210c	1674813223000000	1675418023000000	1738490023000000	1833098023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
295	\\xbff2cc10f161f56a0484b9859795acf6277767783a0c95ffd5523186d1773c8e72f3956fbfdfc965a72f539d78944fdb780f0af2a018ace618479928b449a5b4	1	0	\\x000000010000000000800003dc8e2c6394a556e94ac56a39633afb3aeede9eb7aa6b37d7b0767ded7a4d4909c99588d63410ab78b6b61b7c4edd3c23c63872f8b623c3b32b7010eb3ecbea2ef29e28ac93e8bce01f062e1e6b4dfc628220de440323ffec27412dae42a045114a017a94a75d5364011be9386c5d92060f5a736ec91bf0f6d1d07a25c7b151df010001	\\xbb616fd7c014c0653b4e225fa10c3af083e82d283008ee74c7b947e4a0a72e45346ce6d2f61d5e6971bc96da2ab3089a177eb5e0b3995c91d37b4a4e693ca500	1676022223000000	1676627023000000	1739699023000000	1834307023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
296	\\xc1ea78789732b723af6bc25b622f1f733c55bd6e1b80a88b02a6bf57a93819ac618a4d2fab31d22d51c9e567f9e175e167622dbf569b10dff74a0c494d8228f2	1	0	\\x000000010000000000800003ae01f79415abbf30926c130f7cd785759af75977ab85ac96b16d6a64584b5c7d074628fa02cecfa070a3b68177f24f0280e5b0aa599af3a26eef1e3ef4ab37769624a79b6e4eccdae41b1b881511f2e59c55f684f48e3b6a20f0d44ce0c2ddc99f46d5f26f1b3583930f6efe6f254e154c10992d735bca5397fb6c2b84ed4669010001	\\x58945912accf30fa7938e1b914d0d40ab795081f27e12cd05b16ba560523e24aa716aa5b3d6a7eda574254c7e581668239a16cf2ef8cdf0db0e2ac54e34cf00f	1657887223000000	1658492023000000	1721564023000000	1816172023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
297	\\xc316a4c918c2826dd8448c0ba2a793f734341ca89962d691d4eb77e6053ec8be3a5c6b25e5d127a7130dedba9504fb431e591e7c20a342665ae46e1835370553	1	0	\\x000000010000000000800003d14eddcddedc11dd7be2cc51db9845c026a81a6e0e20160ec8017648dcc6d23c991875bdd851021c7f212e738ba999aa532d1602a716d076549f74361eb16356efeaf222cff1e27fdd930c704e84dd293871f2148e2efa6ffaee12c7ce30959a1faf147123260b34d596ca3c49be650a5e97afdf32e2df6e7723c9dbd8ff46a9010001	\\x328ac20d8ece6fcd3e148dda0fefeda604e18cfa3aaaed304cf7c3d29a1bdf8b87ea9cff3c4aa9106a6302d54b1a4c5044db574c04f6af43d58796748d09050f	1670581723000000	1671186523000000	1734258523000000	1828866523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\xc4220484ccade6912c0bef3fbab40930a19a5549812c42faf66b8de7672b09cc194675f190a5c30eaa02d34db3d1b9f6a3789401c05259dcbe3960df91c98531	1	0	\\x000000010000000000800003b3ccb51360ad23fb1a74234603a28e338e3e5bfff99eeed9c6f0242eea979a0aede463b42962dba1babd44bfca2e46bf57ab79bc706aedd24c9b5e2c30b242890e6a2da754ce64eb51a573640d971872912bcbdce9f7b6a78092c0d33b0baf96523a09a886fe11e5c07659aa93a806c0cae693ab60a61176ee82469fdc58185b010001	\\x56af4d77787c39bb6ccfc583c8eb6223310fc688315112499c4b3f3f28c84184afa3f83e14f48ac587d13bef851997577086fce7dc7c42afdfdf57c5b5324f04	1649424223000000	1650029023000000	1713101023000000	1807709023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
299	\\xc856f2a0b4bb0d01e2393ec003d932cc7ef1b0adb6b79ce92cdaf1b2d6c2be448fd2d8aebd2b3060dd1962a9ddd4f84450cff920932372a819c79bd338effa2c	1	0	\\x000000010000000000800003b91ecde5de44b21a73d47d6ac0b161f58c0d4f22df2169cafc4287136731e0eef29fc8c03b67a7c73fa9329cb1179d4cbac42e34c0c38d5e185c0959bc512d11f5495417d212a854fc09cc271c4ce00f0a3e971a17d007272c3dbe9799e209d2b1f8e6c1f9ae51cfa2d47dffc9e1c6384f67392021664d57782c703d06e0b1f7010001	\\xd8777958b4b400a687f864c5262079316ab9d5c4c277c6c9aa4266203cee98db0186e55be988b41e7c12bc168c7641577362962ca2516d32a00ee6a05b423806	1654260223000000	1654865023000000	1717937023000000	1812545023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
300	\\xca527e9525d8218d6a137cee4985af65cf1897b3fca9802204e5075541d36254c692c54439e8971c932a72d32297cc26b487083bf1e31412cee58c996a61167a	1	0	\\x000000010000000000800003a16fb1c1c0b95dc7e6e50b773c39c3810bb55df2a422e0fb48a9f8cee03dfe13717de81176794041bedeffd652620e64b3b4eeb9e1a291ab464bcb617d3119e3842dfc03d13c512c4511585c1bb606477ecb96166b47c9b26f361048c14860419cc6f082c8bc10b708c8851a01343213550a1a0765ba634f0e4ec45f4593a455010001	\\x782dfea55f786d5f261aaaf55793b4fa227258459d9c21c4a840366e469bbc4fb539c8bd5fc9b4ab4333b3eb3b941dcd618b72668e78aaa2238997527d60790d	1666350223000000	1666955023000000	1730027023000000	1824635023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
301	\\xccd660b29a2ec7544c758bcf8bfaaedcaf0b4f6f5cbdbc7c9b26cd1a03e1f4adfa07defc9a50b6725763971544e1e5440df6c180cfd80fa9355b0944da79bb42	1	0	\\x000000010000000000800003bd56dbd0e5b5801c0c209bacf39fd17608357435f67c78e73ef31964967eea4320aaca11e6acf7a6a147f2ba580bd89ae84116e960c8cc20a3d3f0be901d0d2aef0e89609120ea145d82449596a8da4d549cf4b96b0b83660d8f99fc218ab48cec63aa3fe3016c0ec1aa908c4aadae1992c86f9171475f82a5f952485735636f010001	\\x9fbf4d31d9c883da03e54ef2129759f864b16049bfcdc769fb078dbc365a463064a790332b677e7f629062740b0c32fe96efff558b82300e8a0b809c85e84700	1667559223000000	1668164023000000	1731236023000000	1825844023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xcda60bfa3e3d31768d4eaa9565648720d917717644cdc192c4eea99a2e5fe6d5281e5c616f1ef1a6abad3b3596be37a2db575b6c622214fe7b6974b7d2bd697e	1	0	\\x000000010000000000800003e94faadc241284a05e647b194b02fd82628fc5b1b1aa902f02e48d87c1c60a7f16b6120bd132a2258db11d35a19bc7db0cfb986bf3851590199a258c6a4f81873b0564fdd333710f309506f6456bbc6170d92aad11134faa3e64ff624e42d3e474e5658e221c74125353826d2f117ffeb4c84e35da082c0d0bd2245f97b3a39f010001	\\xc52bcdcd8bd6e01107ca3c640fc79938dc3ebe3663d021a2fe5b8052decdb0be06400468fab5145b6323aa71f74400c699dc09f4315f23aa0f3c79a39b714b0c	1655469223000000	1656074023000000	1719146023000000	1813754023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
303	\\xd992d4e1b091e300e435b213882c17360f96dcd93e1a537f297e76d4a0857951a5c509f0db6965d1852690bb58af10c1ae719addea598728cc139baff077ca93	1	0	\\x000000010000000000800003daae0555b32e07031d4de433e6e40c553b345ae76ab8304fcb4fb433932388dd191f79b0bded0aa580607483248dd89f4d8d80c4004d82e3d8eb2a4ccac44fe0f5190eea312a47dbf70356b29ee0af8a216e1cf95a94fd3104d861ce902752fd16f99dffa6afa9099f66b6744adda7095c6a5f338dd71b5c07228763e998c169010001	\\x7a9b7b580bf98cd94f1ddeb7141538fa597407e88f58b2b963b03597587e147e8d5d313d01ef6d1a27781ef73b7a13275366d17a24f379a0fce9f9908157b706	1669372723000000	1669977523000000	1733049523000000	1827657523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
304	\\xdbc62571acde194f1a51b73ad0225c9b21b62aef7415d625b55f60ebc7246137b3a5af946fac2001cbf37b85a8c09d08bf7364c11f17faa58dd16db8ec140022	1	0	\\x00000001000000000080000395552f42b8b90637cc5214b5d47374b23432e3d7dd20aa0fcc0aef974ed644918619f230a3efe8471029e3e0e449a77d385212fbb16a5d17bd069497dad05b6002b9fd7ebbb82dfcb9cdbbc9d18883de17ba6755f1e88918927285064535bf2dfc28a8d8e3ffa757dd9a6f433a8d95d33734adaee5b8f8b817ad5b4be2937ce3010001	\\xa1f9ede206d2278706db93fe19fb5b95c75bb15b78f180b65c15d84d566236a12e4b2d69368562fc4d930e7ed60c50e39c51354f57a058c797ff5dc5c3271b0d	1650028723000000	1650633523000000	1713705523000000	1808313523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
305	\\xdcde332256cf7d3785b3d304597f79bdd2611dc0bc82a8f54638ba187ad7b7903f977eb7e753f8c2724593b3eb6d1205f1a335b4239199ba800cd894aa293a84	1	0	\\x000000010000000000800003c3603615850094c6e0875f5ed44620fe560e4652dd87d5d1a5858826acc7ea24b6e2d5637651dab34c211d8d9625bcebd642b185bfdcc5564a84fb662968d4a1859a6fe1af2f99fdeacd7867a24efe0e29c83e0e8cb65ec5470f825a6d748ac9492add8e13371e2d371c65bbe394fbb7ceba5838508958da8a95dd89165054c9010001	\\x5690fb05557d31375ef6d98dde3e007bfeb071b624727a718a754046f66015b56427306fe10d6f1155655aff6d73e7f1d88d80c6fa0ea5e99d581218d8ffce04	1648215223000000	1648820023000000	1711892023000000	1806500023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xdd2a594a17c56eecaf4be442f8ff94284d0c1ae4d0e6a64e3b2c556aa19fe1c86972447cf288590aec8ecf2c0c91304ade752e25339f64070910a6c6cff811ef	1	0	\\x000000010000000000800003ea801ffd7e08881bc2b9464effe2e40363ee01f3161e5be97978d3ec8a4ec0c0bcd6d74d790b79e4ea9f2505d7aa2bfacb97f72ec534c03ad3657e4a99e95ddcba0bc3091770398b4bf2ca1b47a8834010e84288480aa1db97999d01253e3cf6856688ed1ce2dd420ee78d6a6089d4970ac774a825176cf20dd9c08933aa91c3010001	\\xcb1557250c24cff4e92aace30be51d84fa3f7ffdfaf319b7a75062375687a43e9c023087da35f7550e9de9ff648029c620129d591f75f751b39bab9ee8d7ef0c	1668768223000000	1669373023000000	1732445023000000	1827053023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
307	\\xdebe037da3d8dd5b8abfeae7c91422b0722833eaf66137b649a8052fddc2a4f3d57f9c892cda68970fc44a711d27cf0d50e68f02e7893c31b04ea762ed1f7616	1	0	\\x000000010000000000800003e5c04e605607431a5ea99061176abeeb75406402420c54467147d16d0be340b2fb999473c6323f6bb4c7bde23324eb78d4f9a5b105a86012b3e65a74cc3b4eedb7b0fee7b6b2fc36efc3c26255712d22786dae1f4002630fd68ea85c32c54437a2fa021ea003c32eaf0b69f7f0eb54ce19c1c4465fd2d4a084cbcdfba47b2e61010001	\\x478acf8833815c1932fe54886b25c8e699f657eab758a33d0deed1af2de0b0ccfd4d482b54f15ce7bddcd16934d0fa22d69ef6a7c20eaa160b24045658ca770f	1654864723000000	1655469523000000	1718541523000000	1813149523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
308	\\xe0f2739e322d98c7a17bffb086f68563afbebcc6f12ed71567375ab3b8cbaf8ab715ca19d4f16f72f1e37e2e4caf45e622d0608ac37f4c528751ba2f9f9ba497	1	0	\\x000000010000000000800003c101b49d666ad56b1bdb585ae38a4f9614e04b77c1c126ed9c296fb1efd9ccb31db29221a464e928130afa0bd584e0cff9e3d5178960b48803900188fa8efb9925ee88e7fc3d40b1cbf5a84ee215dcc782efbf6772c72afffdd530abb897975150745619b22d64b9a65158479639e676a8da74aeb3208fa0132df8e0132c0d0f010001	\\x20ee4ba40fdf998b26eb71d119cefaff40efc05099012f1560bf68b2b8db5d06b55212ea29ed088c1ddac166544c8e905a80728d735d8a695d48fd157434f30d	1659096223000000	1659701023000000	1722773023000000	1817381023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
309	\\xe1baa992b606dfba36d8b98e3d75e20dd4797b1a110e20e61247daee1724cd6fb4e2825d912c9e81b1cc119e79f2d9bf5af1c84af86d27c28ba271e32ad55ac1	1	0	\\x000000010000000000800003f49c990971f5d1dc3cc0c792edbf1b5b77db753669db52e555deb4e6b36100ed371330d636c207134574e50c95323a2ea9f6c5a0a518ffadd41d1c835b2c20fad790cf90db95f28030ac229a6213913043d4496f7c668a4a21c848f662029050ea6ae82a25fb4b6b413cdb70a88756cd69ec9c8730e2da32a14027474cca6c47010001	\\x623e1e3cb74afb63b94f7dade4682486d8f79273d455ecf571d8e9a106652561d1a5c6b35ccea729fb39c1a612dcadd088e1c3ef05fda3d3e391d92b79c04207	1674813223000000	1675418023000000	1738490023000000	1833098023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xe4e2216846dc05d073791a81b5f5c4987891326dde81ded03869e4792d4a80066cfb2602fff2246fc84a0d25da41707bd9cbddcf2bd7f95b36e94e7e77b814c3	1	0	\\x000000010000000000800003ab431e14c7347c93b367beeeedb1d9cd742a3bc05bff87ed0e33f87dca4bb255bbb0ec31be629725696a099ee07c87bcd00f4550db97bf05acc05e3c6622302062664ea5b60ffec646b9e42fc652f6b9554f3220632b38495b596447ef757cf4e2fda97b178810d49a294a3f7bf28dd0317f1f179eb4c3ef13bc8209c59fd1b7010001	\\x6117fe82d395901e27fab7738fad8c55e65a5084c6b936cc993240a37a46eaace3a51103ab5d3e43d6e3c49b2b2fa950732a74e4572025ab1181dc97443aa607	1650028723000000	1650633523000000	1713705523000000	1808313523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
311	\\xe9d6e4d0569a3e3490ab772d42f30c09eaa6d49a0008e5e0504431336f20ed3aa2c008277c20e3088be1f7b3cc8b7b43cb2caf7b4d5905d5e551d08e6bbc15a2	1	0	\\x000000010000000000800003c42be012251ebd001eba4085184866f6c5150365517beffc4658d8a89d4a5f2fa7c569e33fd04dc6e5a990d5cf462d7da03ab9c4d821ccb9fb2d62f9ee817ee97ac97b0fe6cdb0cdda38fb16bdae7eee9db5a3b78fdb0710875c8177e228d99e8dfeb25b7852f55382b72976fbc0116554088ed6bb69190f8387e5d5387f0419010001	\\xca12f81d8ff5dd663902f6797d9cc85e2c8a2628b0992b49850aafee5a259075572705e771b7d6047a166a43706d045dba9239ec3d79b00f57f1636856ab7808	1674208723000000	1674813523000000	1737885523000000	1832493523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xeadea38dfea5a98f7c380502975426a24b505917c8edaeb799919fdf49a16977a41166f476f09cd1c7a725c9642389c07a24eff02666c998b184e91989a68c67	1	0	\\x0000000100000000008000039bea12859f68bade80f1ebfcc0d154706994b72b8574d650b1ae4ed0b649e28cbba6faa748af061eed5bdc42b1df81dbe38c9913fb2cc87f993c6099a592aee6bae579a7307f9d647559d9dd6151c20cc0acc62535f69d1260cc76f40e0ac26452296ca662c167dca4ccfe329a8f3bb2e8946e17b08303d533da7bc7d8ab3d7b010001	\\x3ab3e93b4fbfac47374c34e4bb398f7081169e6a1e131845956dac42773f4a45e97df1cc52523b7c7df20250ee6d733386b23ab43a2b54db03d344dba24ae90e	1663327723000000	1663932523000000	1727004523000000	1821612523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\xebb6b50d794c9c47dc4eb082b222641f1ede7737376bdb05078287468c6248965c72ba9b9f016875ec1202b2cec0185cef5e988fe51256aa6ad6b5f57da25d7c	1	0	\\x000000010000000000800003c6f296773582ef74097cb7658452c1212eeabe980aff50506d826a4c6cfcc3ba86ec83caa16a30f72e7a8415ef458951ae92a128693e9983da7a4abaf69e3d4d8789a5faa52f595f5728d1e2387d144f16c7b0c516e756df787d11f9cc8c0138a2c325d29934c2a59200d492239d71286782e010ca14abc2d1cd2dd672c2f15d010001	\\x6e2590b0d036bfa4ea13ebbb920a360919cbd3bf09d30fdadd7ee9056a5f4a02f245144dd81f4d95ce1c597ef6b22f7ded958bde7e3c9378019bc81b99705305	1668768223000000	1669373023000000	1732445023000000	1827053023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
314	\\xebfa19a59e1d2443f005e01305f747a23d87fe80c7ba584a67499c75a65c9f41be2db0856d3176e1b4e93cc9222fc8419c605687bcfaf497d766072fb2c4df7e	1	0	\\x000000010000000000800003cf1fa9cb28a67f2878150404f018ab83dfa2671231fa98688993b0bebfa8b0cc0ef4ac7e440dedd0b349501a85441dd0347db81cd58d3914481339828f551f8e36d60db2169a2f57d94d9508945c48b810a4d16d572973875256e26b58e6cfabd0b8599b813b9cf152990a9e6757b4a0dda19742b43c05892bd88304a0571f93010001	\\x626ddd5ab6e9876eca8f530949cd822e5fee3ecfbf8c33062f2587b7591705433c9651d3d81f6d655b9d725119f38fb48379a059a8ed92390dcb43a50f74ef00	1677835723000000	1678440523000000	1741512523000000	1836120523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
315	\\xee5af0ccf3966a203715386458a5f017c28b99c790f6f3f767c049b69e17439a8c72f97fe9f896091e93a70228e102f2110acecda8e35b4259bc0c4c6189ae2b	1	0	\\x000000010000000000800003c0f0e986a3385f706eb70f990ac0ee963a88a544ba19d5ef39412faa094e1fa0476a37b7c3c92c0947a8f23ff1a5a7bac6fad34db8084fd0464052a090ce2c369101eca1f32661370778f6815faa0eeea50521531c3bfd7b16b5a89cf7fc7787aa40e0db6dfb078c0f7ead6a2ff1b8876e4c22a08337f65f094b0b11f5107047010001	\\x0be1933ed873f00d2cdbfdb382cc7e024f79b2bea3681c9806710174181eb0c30f7da4cfe4590c246fb2abf0e72307537eb613c70c3c2c8b949b89ec8f70080d	1655469223000000	1656074023000000	1719146023000000	1813754023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
316	\\xefba46cc1aaeb818f3fdf9e0779783d4d1874e4ee7091042f4a4e743201d4df0e00a34100e579ddd4f6a9add01e93d269205e6235d2431115fe9fc7e54cda57d	1	0	\\x000000010000000000800003c223e9044a55157f21fde326fcd2910338d4d03d97ae06d99731d7dc8b9a5d43c90d2aa71d1d522d0dd3197d5be998f34b94cf21c93f567b9abf13a288a3fca72960d400e16ee258d9736f04e0a6d82078656ea300f281a4097d1e9cf56cb98d01951555dad8babab13a08145b418ba967c022a82dd90a2bc0cdb93509ec6c31010001	\\x017f9f6bd9747078061a6e2c2e79435f55b6eed1d45220d46cf7eca553aafc66d9b83ce87e23fb8eab91e8bed4947165a6da682a54a49d8cced406fc93b4d00a	1662723223000000	1663328023000000	1726400023000000	1821008023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
317	\\xf04abe78cbd7a21826f311f0e94bf6d11cc30b3f9899fe7f85c6bb4b10291cb41dbad9c33660e4dbe5b78d22ff15199b7634b0aeb132eb43d9d4e28c2caf44e3	1	0	\\x0000000100000000008000039ca465941cef474191e5709991f4bf524c8967a63f9281f5667216c828222d7a9b4dcffc28e93d3e4382cfcc0e05ea075ccbc39f3998636e7da198cfe1eb1e5126a1c94e54d205b723595fdae9fdc32c571cd55746eb1dfacc40bf1446c91eba45b72971b76f719247c84abea66bfb3a308c4124dac700496a5218ff2dabbddf010001	\\x0bfd465ac04b45688b5e9d2daea0d2913e61c1240d81af7c89602ce016d2aea33f685d3d2e1115e2b3fef2414b3a71a0d356b9de734456f7d2c64f61ccb9bc0f	1676022223000000	1676627023000000	1739699023000000	1834307023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xf3c265bb18a8a15f656feb4e9145482a050b0a37512eaee743969da49301a7c2ef748b0f55f4d6584ae59742f34b58e08870438d13dd990da58f37c64abbb919	1	0	\\x0000000100000000008000039cab7e675c441646887d6c14e67e67dd0199486f380e0f717a09499ab940d07d8f13431aba795fdad18f9f77a2d9f253f8f797e4b99e0f433dc24e8b7c7a77bf206b19b9095b8da188b8fcda6ba74c1333eb33cb015b3b7feab50c2b4f2175b8cecbbaf8a6b8a0400c2cedc83ae778c3df7bee0bc70e61182b9d26a6d7b12341010001	\\x3efc077b16493e343778a4a84983231118227a8a9134c1d63d3e38df119fc2f1a4cae9389824ff54332f73f46d06ba623a3b1f60136c5423b7782f11ec654003	1651237723000000	1651842523000000	1714914523000000	1809522523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
319	\\xf56e784d47fe123b927148a8230d08c210f6a64ce599f65a464b34bfc2d9487f013234e1cdfc5b99604a01b0d575b701d18ce2fef4d59056e3680b900cc82624	1	0	\\x000000010000000000800003cbaa35d9911df17a9eb59d4b0c0d8a31e9a46ab67b8727f368a75881cd76eb36788dfee605b78dc9287482e7d7cd65d76d203274a3d1f5c848986cac8075c1cd424ccda918a2fb77fee24fb3e009feca519457cff23a2a427260d7d33c21bfb32ebc727c313a69b5c4cbb46258b41a5ed9fe1edd4e3aaad0a42fad2b28a648d3010001	\\x57c303472ebd6f8f1f63663bde816c3cce19adcb4a6b2b84a11f523207b100de1e45f4bb00c87710b128e3b0440ca11b08e9d538e3755fcebfd93ba50d10e709	1660909723000000	1661514523000000	1724586523000000	1819194523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\xf762e3e1e549bf12a189a105f9a388143d94ff609b2320019c11875c799fc11b7046ed1734d7cd6825f109bff0fe700edb52dc99ef1706e1c6bc317ea2d0cbc1	1	0	\\x000000010000000000800003b082ecc7283813cf2204df535d4602e1f5019bbdf357b2db60d2bb8ca55c3476171fa339569fea706eb1f1f661b571fb88ed92027e194de2504f9b87d3e0750699ce6a8e5d3013f6e8576fc78dac75d4325608d905c26573e4af7b1e57e8a7fee598794213007f07fda9401cbcd58369483dcb6ab2396493ad8c4210ce13c787010001	\\xf4bdc64577f15c8cabc589d255b29e06658b77aca259a9e81e069459b0dec55dc79356f3be8f1bdf71fe32276da407524123fed01cb49a922a255a839867c20e	1674813223000000	1675418023000000	1738490023000000	1833098023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\xf9aa3229667ec2d959238403e179ae7f869af32c8dadfcdde3950a392050966a07f5c906a5f50ed1ba23a96be42b2010c1e57c56bc1ba520f6af83327624ea57	1	0	\\x000000010000000000800003a913043632940f5e26024191b622b46c442102aeefcdb329b5e5952c08ee55a925583ef648c8c46bf4ca0bd2885d3cbf6c18f611b6330b506861825a97534ee6e77b6d7d12de441dfb589bac285bdf11d712d919f3176b12998495e87cd821fea33ada127f8f4c4ce13249f40c5f00802ea194ddd4cafd4a6ec7f6a31d7638e7010001	\\x651ef1e5525d774af292eb4dcff499d91807ceeb7f0e68c0b08c3b453d5ccabf2693908be1afb20c462a533ed2db92f0e805343df182312d0feaa02809669801	1662723223000000	1663328023000000	1726400023000000	1821008023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\xfacaee2648506f51155ced5fb30c9c30d005043e1df5f7e70997a21831c10392e86164546dde9e9c5bf690dcf745a0ea3b397cc70dd108ccd7eef605a5186cb7	1	0	\\x000000010000000000800003a676ec689b9f2ad7fa91004b490a40ba895fed32994d09e14c40c410ecdaf927e0d14adb2d63a8af0bdff9971ecd27d316d0f1e2f5b8437c516f890bc5223df62b63c75d1417619633be2836ca0f115e851ad52115de8b6ce74c782c935b32d8288e19a4ca0ec19c960b3ea516cd85c3f500930a5475029fe15d0d75c39a2bd3010001	\\x935013817a9eb50adf4d9522e1fca03a6d310cca3f2dc2390f826ce83430db1527701d45d86ea47460e92c748eef7cf5e19d01f2ee5879d6605e1b6a9a18b008	1676022223000000	1676627023000000	1739699023000000	1834307023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
323	\\xfc364ef3463e1c91de7398c44276d90df2e1f4f7c228766b2f514118541f85a4b3bb4b008f6a7a15ce180c166b7a49bfd1c385d4934ac303e950bdc4313d78f6	1	0	\\x000000010000000000800003eae4d8a24c9944a8ffca2326e5d25f9a763a518d7db73c931ad9934f01d6a9eb4ec4e5539283e48dce0cadcbbb3fff925573d0a32d6a18405f0da0adb55ee8e2e21f0956ffe6d3d694fc9f5727d1261ad672fc9ed8cb0d4b122b5b4111da4a162b14fa5612d7f54d271dc11607a882dc1861275a95c1723e860d571b756aeacd010001	\\x6f0a695d62c278b9b211357cf846d98082b1bfe6f26ab50fd4ae58fdb2f49951995ae7ad7d0ea613bde3ff3b89f4bd728abd8ebf4c861ebd9b1cdbc27790e10c	1650633223000000	1651238023000000	1714310023000000	1808918023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x018711a8240fc5978de82ee6ad577d09334cdbeaab7ed84d322c806eaf76a30080e63da99a92f1621b1b2a259605240e4674db7df8a8e9e5832f3bc9af08a086	1	0	\\x000000010000000000800003ae288ff8abb88fd76d83978066d526bf5370fb23239bd7a2f30a7f95e1947281b2b260718926b9c38a34f55f3a611b8711445285a60894d757f535324c7a2550a122bc28a6ca1a866abdaf4912b0b451aa9487c9040651e2f5901877623e1570217f1a942138b40e2951867ed4f6bb5c5ecb38298edb43f97a10cc3d73e234c5010001	\\x5ea745acc3a629a5d8d2b5626418dec9bb9bacd8fcaa219b0bd60973e5e79d79c4697251e5a34a1770adf716603b8c8abed911860b56311cbdf06b55d99ea304	1677835723000000	1678440523000000	1741512523000000	1836120523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
325	\\x02cba7f63d63e4707530095931b50238033463e9d02726791b5379aafd6d2054b97309940ddd4e165b4044e559f202bb391d8aade7d14905f527683085bbac7f	1	0	\\x000000010000000000800003f1ea4fc6656148b84fa8a26a43e462e0f35d60e736fa379094beadc2d77c09501ef7677bdb08b84dba67ffeb891199a0216e50f1b3ab6322206cd9879e89ca9e359d9d0210b47a35069cf54a4881ed1a4fb7c59994e18a852c682f66354c9105b3f0ddca4cf425daa39fed928fc4a8df6b215a6134eaa12542669d484cde1737010001	\\x7e50bafe66acd0b98d5fa24b29547a1a4bb4c14a523edea4ab4ebc7dd4a010b07eab48c625657c9a38034fdd572ace617990adbc78becbe0eb1dd6d43c7aa208	1667559223000000	1668164023000000	1731236023000000	1825844023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\x041f9593c9425ef1411bc96f16fa25e1ddde9cba4b66ed4e4500411eee4e4d37874d6952a83d795e6b928b96ff411ff8cb3f04d34805131d35c75e18c0234882	1	0	\\x000000010000000000800003dff3b2586e728332b7d4acc6b6b35feee81ef3f231692f02bd4b91796f83d3433f94ebcfacece800ee83fe5774e60e3a998ac1c63a9029b5dd5cf84139199a1de214f008f47680cad1e3bf58f2f35cc77b1883c83add7004760f9fb84e73ecab71ab2215a00fd09f38d778c9080cdadc48f4a44c3b1dfb0b2e8382e1f5b07285010001	\\x4bef1c933a5b90d54cffb68c8e90f51ead64937b814a6858723f9854741d59cba2cb52700b176cce213886ae60c1b49af7c5ac650ea89c2681aa5e82a4294801	1652446723000000	1653051523000000	1716123523000000	1810731523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x072b0946606d49431e352210ab399ef0d399591da942e19433769d1a326fce3d3452dae518ae62f72012c677c6240358252cecd8497b3fef31654709c9f12ce9	1	0	\\x00000001000000000080000397a6a355bb853746016c34d12eafc18bd5641c5f3f9f4596d76794a97492bbc377e6f45bcdd63294bdaafb02601bb3343c46fe0a8c57fdaa4fbee84f78e07994155ae357ae2c103702cbbb44ebb5a0321d7fb9cb03f30662c13abde625c040810715d55212524a821b6efbe67750dafbdf123fb0a11e2208ad41d5fab2822f47010001	\\x254cbfe0f8c1020848e11e0152529420c88c571af645e8206a56ea8027685ea011e6519203613688b15a3d9c38551b760f4cc623d524dbca911bcc79c57a1203	1653051223000000	1653656023000000	1716728023000000	1811336023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x098712d9ce3ae2542c5b70afebfe351b2dfe4720c6a4b33524f8f931019488f34312d312f13bef729b6feff92cd9286fd098e3a2949e11cc681d118409eca1ea	1	0	\\x000000010000000000800003d85d3f1552ea1fc2605752d7522b6f0449722eb88aa5a46c2ce09893573f9e2a9ee96e22e7e2a8a614f179493fedda10573385f2045a1f5920f4228c90d356374a0f8a39dcbe8f9f993105b2f821dfaa1dda73b56d758e2842033a179c3ee511b339aeb2d0b696d9bae0cbc5d10fe9e5223e51583169546be88ce43d1e1eefd7010001	\\xca9c42b9585b4e33a63c18f1276bbff373ab2be122f7cb6dc2163fd5c7dcf34a0cbc722e78ebf4a2d11f9a7e96cf03fd6e86ee32c4bdbb86d0f2ffa7f566aa0a	1674208723000000	1674813523000000	1737885523000000	1832493523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x12135cd60755284bf3e0dbd49b8afc09749b380a718153b6748d24a47665cd786a7c0d5960fb4e9f50492f7fef8a3f0c691730b53657e96d5cd7724fdf13109e	1	0	\\x000000010000000000800003dae503377f9f174ac2ab14e874162617edaacb804b3f3f7489f39c70c7eda0db49fb2e8513c45f966d84a56713793d03f5c1b8e40bdf1e5330db8d315588ae8d64529c675bfe30db3b140de0d61cdcdc3c54bc7d8e1aef755d33e4ae8f720f545c6140b3d9c75fd6d18519ef00a149b5578c6cd7bccfe1800346ccc1d6ed59a1010001	\\x1a3506d8225a408e82774fd3f87db4d9780a797cc4d5ada5c6c798dc4a7eddfd2c43fbf09e5878ed9fc32ea2930a850848d5acd37601610b39401f090315600b	1672395223000000	1673000023000000	1736072023000000	1830680023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
330	\\x1657f5c10ad0a5b0bd8d2946a576d858cd9771f3adbd167acc7718cd874cd1af07c901afd81048c6ea6321985d1b41adf4a5dbeaa3a3620faf8e0bd96c793a71	1	0	\\x000000010000000000800003e1b39182713edb7ae5a98e6d99c44425c778087d1b2852605e5015e1c1c6ce1ad9a01faef18bb92ceec570f5c983be8ab31a9c44aa78d4d689de3ba12267365ed1c0aa6d9eaebc9cbac5baef657c65de1177b60dfe27217e3a325af9c2d53aca4eea37c5a84d724eb89c20306bd379f5ddb6a5ef1bcb1cf926aa0b13cdcf05a1010001	\\xd8f28e36c8b6d4402ac71cbd8f0d3af34b079dfdb0c894d04ddafbd1965728e8d7e0c1084ab68d0ba5fd8ac388150982bdf7eb52d7b2c0f11e50a219c844af0e	1649424223000000	1650029023000000	1713101023000000	1807709023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
331	\\x1a2f4cead667fbcd8259a24351eab6428b82356ca44217b20ec06ddcc75093227eb0f89d98948dfbce7382d4098d7cd05b6cb030ccf2ace389149784b22f8219	1	0	\\x000000010000000000800003c1a8c7031a42df9f1de5d07f988e585ae32ba4166b36338023acedeea2e36db57461ac5315e48e3d1fb1cb93ef5e093e5c82e6ad6c4832c4b4f915418ea08655643fc10f588e724f56cf8a8a7614250f8afe5a9daeee520eb5e92c33db324c58cd0bd28d76e23c37ee7c006e799f940cfc8a09a8d05da94482047bc8d20181fb010001	\\x4a4c3bb1fbd1d023ef4d9c23f11b66dd36de168763b1f6b6cac67c6c66d25abecddb40269f5a72b00033f534b630969b74f35b8132fc4e645638b5944ef51003	1666350223000000	1666955023000000	1730027023000000	1824635023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
332	\\x1bd39b82fddebea88c2289217f2d70ce9620f49636efb306848c6655476b74e2347f3e818c5f1d421769626b69ab9cd470432c4ab564c4c5d385ed84e28c0981	1	0	\\x000000010000000000800003aa5d790347c4e17130d5938dd6368b50ad9f7c3fc5fbce120207fb20671abe963ebc29bde89cf508c23ac12521663ae50828881453683c1638eb92d49886503a737fbd6a1a842060e49356d5b133020aa30152e30c2092dede7d9c79bddd44c261a40cfe7db1a2e35c5a85b9ad8a7385017baac05dfc12be3f3d5117723065cb010001	\\x000d96c2112a0f7289567982d15acddd77f6c333e36b8ce64eea54ec2255778cb9181b22dddb434833e9fdf5bfe1960b505622b2dae4f4f2062b77e19e0b5502	1665141223000000	1665746023000000	1728818023000000	1823426023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
333	\\x232b5f7f1dee00b6a9fa78580702b93945c65f02e430ecb81068b5bf605b0d2f4b1fece5a8b0ca3146d8324ea0aaa0b4ef37fea8d415183978217f3b96804fcc	1	0	\\x000000010000000000800003d94440ecdcc89d6b084ef4f898dafee0a68b44453587da40813cbd2a50891f24cfd0a7de11bd10a590e1a87b2bdf06a211abdfef6ef1201b2849a7feb6d9c26ec97e3129f80f617245d895f9c5462eae6625415064535b43618fd4295f5d7aac1a8e1ba1bd6404dd14acb49ef0e54f9a94e693fa135f32a51351a35e70e09d89010001	\\x3a7930357eabf28b41536ab13d907f3713544aafb7034c4943606f86a42384ae22a86c2d24dda8396ed4f6f7696c45b3249d02f41d2ba77417fd0e2d91ee8809	1674813223000000	1675418023000000	1738490023000000	1833098023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
334	\\x275bb8bd651ee4390c41c6761c196108b350be5c63c5da0c658d759a841382a8ab6b8de9fb1b90b652dbfe49ffb30e639ec3fe5fd3eebef3165c2eb262f0e5e4	1	0	\\x000000010000000000800003d835952320a23eb36b4a9d5221b999e9695be07acfac7a3980f18e16571590b95674ef1c5fc39df06d5e07bd7791d9cf92d45e7dd9d01cba891669902a503f8dfdbb26823d8e82c3ac430823730ca44a2e72f344d824630769946e4b02520df99a965272a554701efe486cbaacd18cab8053b1ba8e030bc2c6a0b731903faa8d010001	\\xfd13a772d248e320fff28efc703e5b3c3f130566f04166abe845544ba010fbadbb35a14af8aebf293109d3514db87cb9c7ba8da360a33d6129d21c51ef999601	1660305223000000	1660910023000000	1723982023000000	1818590023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x28afb4938e3e403ac47a4b58f78e3ed587343a961b9e67def67b22915c5f3247d9cf5d594256e351587bc09c71fd9e791f7184b3e5390f8895f9fef4138770f3	1	0	\\x000000010000000000800003b6342367656d6842eadfd2cd85f755e9687b81337bb1e528211f21c1e45aa061b7d1f3d9e24f71dba81932bc3982934c11ee784dd49eac4258a5a33e6331101335ef94070ec770c37e536d59a4bb33f58b8eaeda9fbbf7f6a9415087a342f6821d896b5a4281800fb7e83b3eff34d3d59a5c210e90311317c14deab892c41599010001	\\x8ac9a27b8760aa66002b80e9a230d428ad386b1333cbc4317a991dca49f61eacd877cb26de1b69ddef00224562de9be2f5f8e748f9e5a5b53dc78a2851b37e0c	1665141223000000	1665746023000000	1728818023000000	1823426023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
336	\\x33bfe98d6759d476338b2ce6473b246dc1c2aec5815fe9e20e47b3b2d973965230f8264461587a206fa4e116ffe428d01868389e110b1af19be8e362196d0eb9	1	0	\\x000000010000000000800003f88b336e919d82b92ec70259b58203d483bf2d8209462bfef3e24dbfb3cd44370cd49a0e6f398dfc7fef1865270f7bf44a04f8d4036309629074e86348268dcc3b3bb2b5b62e08abfb6ea99e05f169c6dff9d197672007ebcfe399a687b13575ac720e624f8e34698958f4f1c4e933bb79d82f44851fca1d42ee9904c49c1eed010001	\\x5b3aa96fda02f88f4e03589c0a2583c69b6c17646959f354cce2f0baa1042ff976c39af1908e38a0707853abbe3de577c5e035863ca6c41a261d17b4fffb2708	1661514223000000	1662119023000000	1725191023000000	1819799023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
337	\\x37976180feb39a0865f7f80f213f49f10c0e80c5b07f801778f8d1b0afa3d39ea69cf0bae4f2a13498e7254567c3ecfee82aa275538a4916345a0a05cad9b805	1	0	\\x000000010000000000800003eb097768f7fc27dc087678f77803b1d73b726616c6030b338eb739967d79cb70ded3e6ac40480f551c810425085065567fe31e25be8f746a5c2c6554e3f0f886034c464d7647e44f8e745a40f33a29dbfed2d06881a252967e470c7510b4a255eb6f4b3c2d135abfdc6d98af0ac1b187eaf32d97d7bb2dd1e5713725c126ab05010001	\\x3272a897e40ad59156ef70129f6730ac595adc9141b10e01b6f5f3ed3d7a7707a960bfe383314fa1a241d85ea50557796f7b6001b78fd6a114cb9691bbc7fd0b	1675417723000000	1676022523000000	1739094523000000	1833702523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
338	\\x3773c035e580d555adfba48628e9a319a4f9a032a6776c327ab7aa8e72138da94c7dc64131a3b7cb99a9e5ce05575ff412ae112ad28c325364011b68aa0bf266	1	0	\\x000000010000000000800003bc4733c0b04c114b2a1bde8f29e8482361e607b7f4e8034698ffc7bcd2820b983091bac042e9b1b6eeb5b77df5b247c795294a417c4366a0bc8e43e656e28d7b1a9def3e7292c3988b95a2e718ecf5032d3288670a6564dd001aa940e817a298f6578ed40b26f7a79f607babcce929694206fe5729d805c3162dec360d7924f1010001	\\x82bae364e0d19e1c07d7c811e449f61d86f46cbfbe4e3c6d534e5f817e8478afdff830769b10c5f0d96215a97ba0e75dcda230c2d5325f777f15ea5f4696110a	1673604223000000	1674209023000000	1737281023000000	1831889023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
339	\\x3fe72fc8b3cebcfa08e21ed64fa0e6fce782e613f8c5d9ea2ab4cc6a121b9fd7b04a91ed4ed85628d544914de3a4dae2174636cd744c19940c0461cdb1e1bb0c	1	0	\\x000000010000000000800003e643de5737d731aacc9a621fd23c92c5a8b812ec71160ce39506d7bddd2aaae6d87226d08015e006fd5037d0df806786cc8ef96fa62dd8b87555d1605f4c3eb611969f490e859720349df2203bd3bac5a5fa92c80944337657d6da0566528d283c438c03bdb1a57c8948df277d98071d78c4969148b3f7b9502b44efe37f69f5010001	\\x9f829b5c848fca1e0197a1aa813ee83febb69d75a0cd7208d2d660c8cd7b6538f85e0881f1290e07807759e0503239b1e50214bde14512af673f14bfb5ee5603	1679044723000000	1679649523000000	1742721523000000	1837329523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
340	\\x40d30bd3ce994f9b42a80342245760eab4d8e7d18cd28a515415570c2b0e372064a27a7986d67f840f8106e4c27ca6966ae58c25ff1f6d057fead83dcccb8d53	1	0	\\x000000010000000000800003d7a1541d38594c0956ff25728ca443e5b0f985b90425d1ba04622088573fae9ace58a991b2c1ef61a18371e9721107aead1558973f94d254ea4a866abe67aae89c5b47beb6c647b76f20c94929ef1a64400fd727a8637deaf217f712123dca28295048b64d5b05209ab0312a8ab3c9b2c6c88604d65692ecab88bfc1d810c971010001	\\x407520e5f6dfa32e95a7ea331c74640e9d66fe5993baec410b598865a96d9d220f0e896221305d173e24546a4b1a29db6de1a7e2f9e736c22549be0ea8dfd10b	1654260223000000	1654865023000000	1717937023000000	1812545023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x40030400916634268e724161bd12c5b596a77bde2a6e02eb2b903256c325bc735b967f894bd4418bf75ab5d8eb796b95929c3c53361b09b10dc3cce8c1c4d84f	1	0	\\x000000010000000000800003b3bf5079c7e0893b0ba8f4ebfe0b3025102950b63d07c2463b48d0b3e44e4196b1d0b863c9ff9764f9f164b2b60fcfe61b92e87200cf524c30eb1153e66a746f835bdc4c9969325f69b35ea3e2fc354edf15d05ed49bf0e8279c04ec300a90dabf9b998df31a3e6755b53a643c3c093ecad26c014da80d9a1de0ec3375c28713010001	\\xdb35aa139916115bdb38a6bb0dd640c7242f28290120d4251a93fb817eeddc85d627f02974d301a7eaf08cf246426a9a4f84e1dd4d44e717bfdd8f9fad8e970b	1650633223000000	1651238023000000	1714310023000000	1808918023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x486fe596e0f7272076eaf29be1c99cd381b71ac7035f3c1685cd56bfcb92985082175090f51aaef6b8bea0cdff485c39ba4dc63337f130ad001c68f61828dacc	1	0	\\x000000010000000000800003cffdd6fdb957cfe93f59947d2b1f3e3f98b60c4cf6c6443bbe2392c59585d04b97aa0a6df7612ffc9d829dc658a969083ae8fa0d9579f35b7788a3205ded86e7c3f7008bf3727f60b5d3b365493ef7010c913b564c7edd74597eef903d886807139e023ce157df19491402c299b902869cca2feb3c980ea7143a339e09907785010001	\\x929f2fbf298db6f6e6e01d8085911279decd8d1529d1278d2cdc9ae4adaac5e55636941b0ef81a8c909d7d509416548e3621f7b805207e9f2abe5ee19ace0b0c	1651237723000000	1651842523000000	1714914523000000	1809522523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x4af380ab1b5a13669f7417e626e678229b44e5ee15ca1072289caaca847bce8092b9f12005f34b246a8afd43a7fad4a27e7d0f6ab8a23865aac06136a926b1b8	1	0	\\x000000010000000000800003a554369de25e566a5859219574b3167c4e0420b237aa40913568dab04862ad8b86860330b92f447d0aa37d4eada7faef22b8db008dd1e3e52b43897ae36ad86f8bc1f1381c97d5fbefe09677545640d9d7e3f656c0ba32de53f50700a0fbca3b3e4f2bd39d7693f86ab3464945d62bbb8c2fe2cb52220415650e16cfec4452a7010001	\\x012b4f6a01fdeebe8c7c952bce6ac3c0262ea50605e79b4287a21098a9a7dcbbebb668b8bf5c53ee08db3d05df6a46c87bce2d66577c2896df530ca705b0e702	1659700723000000	1660305523000000	1723377523000000	1817985523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
344	\\x4b4bd04c067a3b06e1000931d548f02d37da61c248687b1109f9149330d26eebba81fc26cd466f35360e79448ebe22d566055f7fd4ee711e82faef7c38772dc2	1	0	\\x000000010000000000800003eb67384d6806aa4605295199c5ce7a38786fdded7eb7acf000ebfe7b473bab112e9064ef357f41adbaaa799763bd66738f3159748b00cfe4829ccb58761c60d7a441421d045a90d9abe37cbf1973c38bfb60af94c604838847924b5caec43b5336edd00314bf587ff1ffe2a72fb3b46a8fa4c519d34a25e5685e021ee7ff4d63010001	\\x66a2021de421c78ac073984fb92c8146690560285794ff20542eee1fd3dd811fefdbc380a851c13221a13ece30ba15aae4688fb2edd91f12fd815adeb447cb09	1656073723000000	1656678523000000	1719750523000000	1814358523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
345	\\x4eb7f8682eead668bb4be2657ea1bdb123f0e5e7c353a719b88000f43f0351d62dba92a3bc9609360390d496bbfcceff5461a0b22a64d3ac245b51385465c9de	1	0	\\x000000010000000000800003be523ad25e16510c31733f364d45329d919fbc6fa7d7257c69e2e7e935060be899f9b309f9be2acf794d32e9c43d15b80444fe238ffbebd6b4ad8d2b09d274f7d99288d175da70f7f920b55f506907da3d52d2a21fbb3b0c1665e8e2b66eec2a4201ad67117c549b40b310f63cb30a52ba685db7dd237e23bd56883aea58710d010001	\\x4bf1b4cc382b44f22f4964f60100cdb774048fc5308265b2affa432dc9716503c8048e2a2dc4605c762a70a8e71bcf910d7fdece9637cb2747784263e3a59604	1670581723000000	1671186523000000	1734258523000000	1828866523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x4f6bccdb26761e684183fa8d0bb551c3f149df02e41f37c567cd94d68199b336fdc0a6a9892e09105ba8ac4b9353c93a6d3330090f6207a4ad31a31e595f7d2d	1	0	\\x0000000100000000008000039ed9e2383cef858db130cc60520f8f5574e81d910696d3771d379c57b6447f7f5759c6fbf02be39cba2fcb7a5a24a160f4aab69ecbaa1c6229fe1ad5cfe10d9832a2ef9c9adb9795a277467002348c8bb0028727d1306e7e16c323c8684fb0c3f5080e0ce96e1d83fc8f06ae28a3df797bac04179cec938172f34a03478d78a7010001	\\x8266d385351c32c33c22e68597f45d2f61999dab857a930dc052b78210fbbe2218e0352e8fa96e18812f61c3a5a86eecb97b992ce4bb0e98010dc13911e06b09	1673604223000000	1674209023000000	1737281023000000	1831889023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x50936104581b8a22e3c810a43074d5e7d27f91b3d6db9b1442ad7ba249f1d4fb943358dbf49211d8940449f9dfe1a53760d8ad97a7639723085835e57df70791	1	0	\\x000000010000000000800003c8351b9d9a148c82c3d22fa536a7603179288cf7411ef21e3ef96df2116481cfeace4ab8d11ca74d3ff2f935d2c47080bbff655e34aff7efbea5bc873f99f44f1a77b6c10a2534b77821b2bbbaedc7fb3a5afe3c2bbaa0091ef3d6e41f17d497a1d6ce938285ff5e10c9121c388a3f3df2dc66408e6e9bd09994e0776534809d010001	\\x2cfc965cbb04608a5b5ddedde7ecede954a4f47adea1e3c9c8b5a1184358e3f127dedf2cbdd8c2fcfdfed959b7d539dc03f37216bbfbdbc7d1acbf8c7a6b5b02	1663932223000000	1664537023000000	1727609023000000	1822217023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x51d39db696821e786762a7d67dbd771d6b3249c897ff201849d2bf95f96e2e092bfcebdd040abe26079a362644796f2f1c8d759b9941fb4df3d1ce1fb521b120	1	0	\\x000000010000000000800003ca7e002f4d6e946711c0563ffe5ea5cc36a13094ac8886e5144e42abdd43d62de593851f2c306f49d35d6a9d2333613dce01a13ee5b7431ebe8aa7ccd28cd4ca57e9b57d47157c75e5b5c685728904374ad51605c5ef18e14cb43e682bb28af72ce2f269fb6b855432b802de3bb15784777e4d44df3fbdbc2f4b126eb71cabb9010001	\\xe9d99b05f16000491ddc78e3c0d45d1ec2bc9e76265ddb4c5c80c100cc1c7ffaa8fce7150fe6a7e3979306e9e4c35f7879339a27c12aebad589ff4f856371307	1653655723000000	1654260523000000	1717332523000000	1811940523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x5987f67d706a501bfd5727f1c499ab1d102c1d1d6edc263ecb00aa85d96c9864396db1a456e5fcd9ed1ce53954a887d935a0c4e3ce3e968a4f216838dc032f3a	1	0	\\x000000010000000000800003d601c2fb8c61f97760ce2e16f3d73af9bd603ae6a4ab232f3659986c0db64f609d76f6179d621aca506e93d9e15c394c44dde1204d016b844f8ed79d628985ae634ac1cc19ad9d53e14afb743df29c213045232cf498ff48465ed403be9bca749d66b10c469fb8e3213b079156e8ddf726b3469e9c071c2df2f8de0be3bd1fff010001	\\x556174a7d5735dda0e404e655fd206a14544cfc1fd9413ff5d89f6916946e8f03996207fe5a267e4c6a2b2d0348f1d9c6d0148e06868c1f249136928aa686502	1655469223000000	1656074023000000	1719146023000000	1813754023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x5acf31da6e6cceed9f23356f6a5712222d49e60547fdd7a43177fad4e5fa5323199dbfcfe48fb0bcf314fc328af62c268c7ab8e2a289b542947013839a69270e	1	0	\\x000000010000000000800003bd2b596cf6be3fb2ba91096f953f76196c4de671c3d2c3674dfb846f0bb8c2206344b05b488bd91037434c1d345e4f504aacad877091315bce118017736ee98df6318fd0bd57dfe9e519faeb2fb6a99bd8b0665f0733acd7ec49e44df2dfc5d1f936f6ea5210b1820dde812d02ee85db700961641ea53349319c9afc8851f31b010001	\\x01173438d0fd4e7dee3bf9f4581c170ffca8a286f4223b0d490ffaf73b804cdc77d65384cf99511501de4df84b396db5e973fb06e6d5477617def37eedf3940f	1650028723000000	1650633523000000	1713705523000000	1808313523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
351	\\x5f3b8e52d6cf552e8bca8af91e7ef46559764e26030f5b9e00a0e40a384c1651d38d74acd26627061ee8a4d3b1fecbb6ef98b0275fa6280838c9eec923b1fafa	1	0	\\x000000010000000000800003bd3ff8724e7baab7eeea21593e20cc18f63598819d58736dc247ad4c486b71fc247538b14601fa136674e385de06eaf04daf023764d1adea7066cea3cccf608253d177e5a47937ebf6b27835ee7c6686e25c635da7ad4133fb282dafa827252ecf9d90b99e5f685b5e3d502bbbb158456610198174a00e33e38cb9c5a1cab711010001	\\xaa5f0c76fecf2f3a9e7aafaab2fe09d6f9a05268cbe48ac82e132907d74c2de42e3e1990fce0bf619391e18c5b0c79a86c541d75efcb987947f004218c466005	1656678223000000	1657283023000000	1720355023000000	1814963023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x63439dde682238ac84800e757eeb3203f6d43fe675c4a27d96afe7d7534a1cb6b58b421a627675bd01fb7cc5dece5195472c4bddf9d5a98bf1bd04f6b4fc57a2	1	0	\\x000000010000000000800003cbb3891451731834cea876253642f1c991ca456cd841d42c1df1839176aba2045d3dfb939b472c75e5758114cc2b694d7408e7a7f1ab45dc0a200b9bc85372800c5f4bb4ca79bdf3f0c428074f5b58761594fa494429a24c5e7db19a5119d1d0a35769a5502fd15065da99fb452919a81eb93a8d431fdd66abeecc7874810e07010001	\\x9555c3c307b121b1388bf12854289b34b9bae7bc3c5b7b1a1e86cea4809ba137f9ff25e337e6c828e8c2c7c84cb6c24177a0e6a5f05a1fce4fc48d425fb9550e	1669372723000000	1669977523000000	1733049523000000	1827657523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x648f020d6ec50a22b627269c174cbce9311ae2384bed5c54ce7cc1db4e077fa14b67e0a1d6ce677919e809c33be7761a8575fb1e8bc7815e47be29f5f20ad257	1	0	\\x000000010000000000800003b7eb721712f9140021bce5d238e2f1ee9e25fe86fc32263ec7327ed43a08d385b5f0aaec4126f54de4ff02dbb7151177f3b31a4749fc177df50f0aa158bb737ad7a92ab047214a9328e725a80874f9c4645447886194adce259e882972bcac36aa8ce70df20bfd762e6c4e71b0c4feb7ed5bf6cc6deaab1675db5d11ee24d227010001	\\x4d12b17ecd384265b294f50c9eb134b8e2ce4e111e4d5f567c01465256eccdedfde215ad36a289887c24f9723f7d366a49e60a9d326001b759e0fdf63426a60f	1654864723000000	1655469523000000	1718541523000000	1813149523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
354	\\x675339460d8ac20450660c003eeba8da0f67b1f5dff47c76491eb43b973acb694c6c7670a356a1f6fbb768f2bdff59c1359a1a4986f992ea318b2ba8f47b24d4	1	0	\\x000000010000000000800003b6738b28cfe2e141762e1189685886cb2b1a33140dc55b24087f03db8959f289daa3a9643255246ef268e919ef93724e74724987e2586176abe73e8e80ff83f243eccba1a25d40cc15f9f476cce783d59dfac0d48f6e180d0facb253caba3c718951cb1c337e5b176a97ae687ada3fec9c4fbaabe3c6bf6d5d14f59a50090b87010001	\\x0158b633e62c5df818afb9ed3dd3866b69413bc3c08291a44457cb069bf3b4756cefbd1c84f62a6ed7a22ddb637231ff2091b3e68942415654b8e083db555705	1669977223000000	1670582023000000	1733654023000000	1828262023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x6bf74812f5aff6b6c8cf98ce20cc548e32f81ae12ffbd0ba1b9d960c975d47cddf220eea4be3fc8552d38eceb709f49186d3277558c592bc430758bf0ef83cf4	1	0	\\x000000010000000000800003eba32fb0d970808d55abd7ccc9be45b9679e90c2d91c29ddd9d416c4aa2e66613de0ad133fa72588185aae3aa86f9396684eb51041111a69762949fbe71009ebb759f8731768689ab2260a11d84ba84caa688f6332c7fb02fd40846bed65d67ec78c13c0f0fd7228c7754f32f0a48f61e5d3dc68140e403cf2e885dbba5e1547010001	\\x514cffd51ba78f65bd06b796ee36660d38e0a677162336f2ae8fb58efbc3dcecf2f6dd1b24b0a32bfc42724c0acd6970278bbed1bdd4971b64ea8e44b91b8a01	1671790723000000	1672395523000000	1735467523000000	1830075523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
356	\\x6d5774aa44a01fe27edd2a3c8fa051d5ccdb99097bb88c48ca19570257c5ca898b3b63e793ce4db81c35110a0f77d38cc96557ee9c46c616190945a6c75289d5	1	0	\\x000000010000000000800003df7a069d10c0d966c87f065d3d70bbe1b2fc3990c3cdbbf5dbf2fb48ce9e6b5c2534ca5fcadc9f5c3027da73cd3ea8af3b25f669e68c9e37935f29d6e961b1a10d3b7fc65bb177afcba1827cfe170716db5584db41acd4561686bb6be003c7ce951ddd26aa7079d0eae0c69c76298522ce59fff9e014ccbb356b4c96ebd492f9010001	\\xc5ee80f24ceac301b61d118ad49e4476d2071e1c43edaa5590320c285e782f73f8cf6c04c69393ace87b907b919b9e1960321d2b5d03b921e6a244fb66ca2807	1662118723000000	1662723523000000	1725795523000000	1820403523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x702fbfa47198fa246a8d2384ba3316fd18ceb84fc2c1196f07fc04ade6f45276591fc4a0027c639fbefa5168ae27b097e4cb7a66b9714cdf9c9b86a3bd897066	1	0	\\x000000010000000000800003a5fbb3754af09b6c79668d68e5a57e9dd75e3e75c5a6cffe276211e8d92c86f2342c05c615a0aa70c139f982aad9240fec0c875462d2ba491632375db54d52e6ceb5c9f9c3433db0e7e27efe35911d686c056df3109ad49c1ccb195554887d1222f1ee8e24c528a743d62c71c587c7947b313474c5431a28d342d1218861ce71010001	\\x550512d88aa0b792d23f3ade7851fcde8817e5fd2e1fc7b7da67c4ba07c074c1c74c3f5f3e39a677962482e060c4243245a29ebf8fd700f935cb75f99f91fb0d	1659700723000000	1660305523000000	1723377523000000	1817985523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
358	\\x731f82d0019ab7b86f6ddfab4fea01e0ee0e0cce92b87ae31be0d6c2a0de392eb8c300097abb067390e0c25ba579bac0f4e5bddee87903904fb325053562e5eb	1	0	\\x000000010000000000800003f4c3da7db80c3675e7c3226a976db537b398e5b5594b94a45d19dccb90c5fe8810a95102069e257617ff32a042488828f4301619c3323a446e74db8efd9bb0f241bda0c2ac521f4c0d88087a9fe9b5e173459f9ddb6d381cf02afebd31187ef1f2aa5d2ab6171752f6805a73837fc1ce0678d5be8114ddd2da953c6b9ccca3b1010001	\\x0d7c2649a65380624b9c8881bd4a9459a16d3f50734e1859e533442e3bb4379d4f29a92e32c8cf291e15beab2bb2ca065f117c369f4e30254b2afbfdeec27a04	1648819723000000	1649424523000000	1712496523000000	1807104523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
359	\\x7317f7ff98a236896f8001a948c981f9248da34a9b2d3693b6682aa43ed65d3599f10927071c03e0eba137e1d7e3c42edab1b164252847d45a85a7d16052be73	1	0	\\x000000010000000000800003ab59d17f60c713ac2daffea4aa678f5b2e3887cc92c4c53dfaaf2720181d3150f5270599918d590fb584ee3677702cb716687aa025c83d367b145b1aeae0080bbfbd5dde37c4cd7388c26de8a438131ee6e0435c3e50afd07f4de0ab67af325463a446713328d1c8c447f1a28f0d9501076a323ea0cf911a9cdd1c1383a04b37010001	\\x7d9b267202fffb40ed782e77662c79036ab5cb740318094456ed84602d9887dbf2f963dc39941f62573c698c6e81802270760ce9e927ed69a1a79fb8dd053f0f	1660305223000000	1660910023000000	1723982023000000	1818590023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x769f0b0951151cf01b41589c7e5de3e9d8bdbe4b3402a9039000cca2e1882c9a9a1986ba7e42d6716a4228ce5187843a80b96418ae4fdd5a7d1b661bb55de10e	1	0	\\x000000010000000000800003d664b28bfe02dcff3cbf8223236d6ebb2c783ee1d2b6d9cccc7a9e2ad09d6857fd82091d9d5978213024781c2eea7745425c166f193082249304be16be47a27148fcdbf0f9b963b32037cd40742374bd18f928dadc51db396e1f08fd710b639fddbc5a03986d4bb460634418d9d36c5046db733cc7671c415f692e2fad2a131d010001	\\x683c9a6ee0bf173956f82deffea259b0c01d55686225082b8cb953b06dba1afbafcf0229afaa94c1f7c732624f4757ae4d07975cc696b99e8dcf3dbfb013c700	1654260223000000	1654865023000000	1717937023000000	1812545023000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x78832db9676efed731a47e1b09b10bbed920e39edecbd817c42c5cd9401e42752b9ac4ae8f1100e5ab2ec6932c32f5f82f044d498140f2b781ab7938953f9324	1	0	\\x000000010000000000800003dcf86ecb67cb9217df212c097c17acf248cee42f1cf5df80936fe85dd04475d846bf8a66401b2b7dff0730331f6285587360b3e88cb7599dca4c976f5753375a205ce5196d61e9d0872d92ff2a9b23b84736b5fad8efce337b932195ccfc8e0bf6aba1eae83e76aa70ac547fd4e8c84738f33fc3c0dfb14787203ede8ea7d65d010001	\\x9299b0658c9b992859ed3a26c60c5ad8bc8edd8b73a0fa73c240b446b06431fb791338984c8bbf99fd2fdb47e3e2a56e050bc0437cb601ff5f5199ea1324db09	1663327723000000	1663932523000000	1727004523000000	1821612523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x7ba7f57507155cadfae8454f23a737a04f68ba066e8d935fa232f71de7d618d1fadc8bb5ec9f70631836d1f49ecb32c33bc1e3de483a084cc0fd006346adc6c3	1	0	\\x000000010000000000800003d948baff0833d80341e3940d46311bb7bcc87969b6785e257ff3b2bd466c1ecd7636a4017b0e3a64712d29d47b0c73aac3ab478ea7bb1795d4b6a088d7df1764fce39fa397eaff29612069c14ec54c021603bb5ab5873723257e3b83a06c71bd87020b7197985d19e54005ede4a43fe8edbcca17d7f2fe29f569bb937a0dc2c3010001	\\x83bcc1c31aee416127da7e7dbde1f259a2fe74615668c87c86eb25a6c5ed0b350b379a43b8326671a4f0e44e4f20f8dd5f403d1c07ec8a7905259d24ed686108	1666954723000000	1667559523000000	1730631523000000	1825239523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
363	\\x7d17470f9301765317effed9b50adb491ddbfd07ef2ca07ee5acddc0f1172252ce73148c4dfefa80ea21b12133da8c5623ce259831f16584fa174a36d325f86f	1	0	\\x000000010000000000800003d5821f4695b9857b782551ceb33e1ce7e7b00c1b2d78f92d7588d8c8bb971f47f035cde28fc9b9d95e141443090896802667638520a97b986cf29b051c01160480d614daa52ade6b485a7c63c279cd606f9d078ebd627874d84530be07788b48fe8926f237c016ef2adbd2dec63fadb8a476a837289aac666eea4e503b4ee331010001	\\x6bc30d1a8465f90f7b09451ae8e056600f16698193f5d469c63ccf1404ed1564ab7f5291710217ece4c07e522dff1a76dd6a34d08a357903c600b3965144190f	1656073723000000	1656678523000000	1719750523000000	1814358523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
364	\\x802363573c3509b783a7d990ad908efe43095852e5411efd91ad8f624c3ea5141f5154b3eb7dc695525ac050f46bd2de61859fe18e5829d1bc61d2054ed04f18	1	0	\\x000000010000000000800003c56b083f483ca126579683a230561f28096ef9ba2049895e931f437d01cf4c41f4ab2fa23b30d8f38a6bf7fd1c0fdb78449148fe225eff06ceaf8afdf2222a2e74a4f98d134cca33506890c462673bcd6e0a4d30ae8f9d114607d9f791315e6acbe6f2efa6bbac069b7fca7215e5ad542ec6c0fb3a011022ab7b8e1ce212ca89010001	\\xf606de2f3f2df44499dab38b77d9d8ed7805b812461b595bf93234795c0670e105b1ca740896bf7cf8f03b7e83249e626809b6a32f6f1bc8c2a0ae7417ed2f00	1674813223000000	1675418023000000	1738490023000000	1833098023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
365	\\x8177ef7e4d24bd1d0086a454ab71a6379736e3c3cb785a4f4b07b7c99992dd291a227d704557e8dbe10478aa36092ee80dd8b51c7bd4261679b3fb6f25dfbacb	1	0	\\x000000010000000000800003ec7b91a3d666046003538f7833940667895d61d633f4f8d6b1cbd3de8687fc442c4cc891ce806953f2c3b84818de97c5bdc67244298de3d33cc675507d4e233570a70097fd0c1e25089babf818711a932e23dce3f148ce235af36cf385ae878221e6fd2b5776a6eece5075d3b87b1a5d4501b3e8dd111d7c52cf9056760300cf010001	\\xbd6ba7d0d0ecc35902caef7d60b0435b9ff1a98374c487b9b42ffaebfddc9d30913a5e87ae82b62ee3cd1ac44b7585c01217f132fb0c0716ddf1d8c8b42ec70e	1664536723000000	1665141523000000	1728213523000000	1822821523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x84ff3c861cb0b3696127fb36f9eb9e85dc6e29013b780dac48f11fd104c450853b7890e261089224966ae6993c2b43230aee5073d653204b2df8379bc37eb6bc	1	0	\\x000000010000000000800003cd031963adeadcf5acd4df743f4f9cf99c74fd114f2d4e3779e8949d3360572961b26b8546142e5e0dc4091f79bb7afee83f6fdb6f95ad5ba06449d8a8e5403595f56426751df481c5cfcd5b2f37edf0c993d2a2b2574ffa21254e0bf397f6cac1b91ff0af33c555f147d1a7b6dd2536fa5fca2c33cd367a7c0ea5a599a4cd83010001	\\xcecb252ddaac6a840a1904fe8d5aa45205cf17f25e3f82c271158041f61002be47bd99f94417615efd937d0c050b4d287e7ce8cef743d734dc00ab70c5dbdc02	1660909723000000	1661514523000000	1724586523000000	1819194523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
367	\\x871f90cb7a76109a956240a115b494b804b82070364b0d41d76b222582b249e049f7e5ef24377105851bdc0d9e05eb645811a4c344acbf1b2b5e6a55c86295cb	1	0	\\x000000010000000000800003da8c4d0f68ad57647d6375d332956a672b14a5ba747865a5c828a69f1942dacd2f675850c21247228efb3106cca8d41f1df79a714a12c845c7ceff36ba4a925e4094e00c63deffd450b635b1c5ecb20e6dfa5500bec2e96721830ea2ab349eb1aa0dfbc9b54e5055c62e6ad0441b0918733fa40a7501cb3f5423c070b0cbcfab010001	\\xa239af1ee2c5cf5c80e4154a1808816a7ccfd4d398596d785dcfb6ed3838fbea24d7bbe75cedab8a896a8684b3fc905010a50c91ebbea3d202afe4c268bb610c	1660305223000000	1660910023000000	1723982023000000	1818590023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
368	\\x88b3b56d2d40e8aea34e19175075eedbdecb8a50a4da1379feb2f32d0fe7179208292fa14825b153953857aaaadbc2d823c8c79cbbcba3f29dc283c96f4bac3f	1	0	\\x000000010000000000800003a9cb0eda429434939fef7ed2b69166c94ae70effbfa768e36d857cbacd00d5dcf4e8444a604b9cc456b431673ab01290e49211f7ea7c273288cc92d5b8557d46bb02cfe4420f07c8f63c6b490e44b1be8c39cd5e813bc276af8bbaf9736edff3bb8e5ef150a02df232155cffa1d42a26e7c061adac8e46896232eab762238a11010001	\\xad4b275aa2c6f62b10a381479e61dc1c5f64f996cb9c0c556d35e7dac8bde3ebd23eaeaa18b88aca834c62cae3d8c09b9ec154fbc80ea97d9e0cd462bdb05c00	1651842223000000	1652447023000000	1715519023000000	1810127023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
369	\\x89cb7f854ee4cf441029de73813f801389960d5e1522e1ca01b423df28703bd70dca1d3e240157cac366e6889c1ab733eafadd0b10816c9ee2ed6efc2782d7d6	1	0	\\x000000010000000000800003add5ee6aa381668eb7fe6d5b321626ffc46cee408ad78b737a718af2dd15ef40ef6ba0e5c9f1b75299f71e93b31c628838103c72ad86967755b8633d647556e8ac164861b52c4b81319abbb8d177c377ec7613d68a707a81e4ee75820b1f4827d72d4f3be02a754fb24abe7f9e7d32a760a0e90d9890a5216926650ba7c4a0c3010001	\\x3a4076b2c227eb0c8f66495cc6e9332863e2a5c58bef9b67aaf4743c6c54224ef58930cf791be21d94c224d171ccea8e782ba089bd5ab804faef762d52cc380c	1662723223000000	1663328023000000	1726400023000000	1821008023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x8a6388391cf971fdcc9c1702ce390c1b30267ee6647fce22fef16cfc4c9b25d7dff3bc9cfd5bce11af51ee4f91762e98cec65490bb6d14ece577128307a1d39a	1	0	\\x000000010000000000800003d59e2dbb0a60a3b43f73dc97d007eb3bac0d12b7cbf3166d6f612683fac1847c016d6c1e63e804ef917abc187ab1aad6fb37e5cea4e170146ce064adb906dbe8781db029f2bc92b083a95ba0c47304d855aedb7d6709c41d9e511dcb18a2d33ad291c92aadb8cefea30553202b83880f56d859fcae7b65d457c54ba9d719b81b010001	\\x566eb1e7a488c0b388b2f6ea83be79a4e59c733a76a5b45119be27abe7473342b179afac3ef955f8e21f9aab610f9ce55d122778f5d73fe81f398eaf869f620f	1672999723000000	1673604523000000	1736676523000000	1831284523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
371	\\x8dab3aeb31d83f3451c1b48871c7472a4293d700a5a04bf113fd3ec4050efa958d607fb090ad98188153230cc5273bb0c83960e77088ba44c261b4f56bb553df	1	0	\\x000000010000000000800003a77c1ec97c2d0b46bfc3c354a78c342f1d22df2f87b1ac31adcf3417cca1c1c4bcae09204ffb50e3c0075f0420fac0849a2cdf2976e3cfca2fb8e3edd8a071a79264ecb473d55e442b4c9bcfdb17ddb8e5ccb3d8dffd056579fa11ba1fa1fbcdaa8c0e3ce3ad601bfdf028c70519d2dabbeae339df80d705ab0540deddce1955010001	\\x554772b63801b10bb5d3834a451e338dcea504d66f640ca9230f1455f74675c8bb0a1ae91ab8ea36d17b0aac9e4e3181e98b7e0bdcaf14366b995009c84d7107	1669977223000000	1670582023000000	1733654023000000	1828262023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x8d07231efa30a0cd258c60165057ec6860ab8a8beee13042ed846757ccb5f0f65cf55c6daba94010e10c25499918458c8e678e2fbd5803412b7638521472e000	1	0	\\x000000010000000000800003b03e4147cf52d61496810eef887aba578ce66ed8a6e8f79573a2c846320d11ed1dd82f25beca55b1cf69b145f0578efd414e821ffa2345dabe80a24d70aa9cfecfbb016dc2811acd1bb632ed0b6b3e7d9cc6d6e3a75e8cebb184f2efe024e52bfea0776e788a1333a17cdc735b7134edbb9cf4bbcf30ef806ea77dc3da749c51010001	\\x0435f9aa274d883786c08cdeb8ec861444837b73f2d3050f2656e43847ed43c2ed7a107942bbbf3267455a359acc3872a6842b4d35092f2dfc4daae8570b300b	1648215223000000	1648820023000000	1711892023000000	1806500023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
373	\\x8f63eef713bad201ab4bcaddcbb3c4a8f84a1fdcd97eeb5eb8b84c6d845734710772a53a39e7f11c603ff30818eb81b9d5d76285ad5bcaaa218f0c0ca74eb4bf	1	0	\\x000000010000000000800003c4a6dd442d87cb5770c0572fad7561d44c3425b9e0337a8eeac0661e47785168376f8814fb076e7cbfd7fa3892b49def6b3450b6ae463d40fb7ed421356d0187f0e8c875049193d11e797d41bfe147e867665895a76aedef4fe10043ff8ccd943d86b6c425f6dd4bbdd58c8ae328b2fc522b2cfb8c84cc26a4db211fe8ff0b3f010001	\\xffead4a7fcc46c201a230e22dfcf0ef7170ef8eede691b9d689dabb100aa46814348c9051a5fc36fca8450e22ad6711b5c84931b9cea762deb2b1855aa623000	1675417723000000	1676022523000000	1739094523000000	1833702523000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x9607da2d0ead4f27f1a45c78c511703cddf7f4ac936c7e5fa0ad3944ef2504da78888733226a106000bcd8dc19acb4f388c899d2c4f8fa59d3294211ac0d793f	1	0	\\x000000010000000000800003c95f9fba42fe668befff30ee734fc694f10bde8ed5f1acdd7772074bdc55e4920273495c1511281ddd088c1cacb93d4bbc8094be2d1ff2239b8761b2b82d0923e6d3b4fb708dc6849b8c93a26819fe918c41a2465a6500c86edb20aac21778861f126ec4531f32ee859b3b26d68f38578e798fe8b20bb27202cf4faa9e1966eb010001	\\x91bc8a1644bc1eb6ffc4d5c8ab4c7520de19e37b92718e5a05a4fee2ac24d7435bacfe44c577bb8542e6ad5e3aa61838cf484a97cb81b5b80fca28ab5f05ba01	1650028723000000	1650633523000000	1713705523000000	1808313523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x975ba012a0da0ad00511806a13e31c11b9d1a6f94b801f4aeb942333dcd9f753af881c4bc2126b7b6d9e67fec5a7164853eb4fae4c01a09aeec430b184af5c45	1	0	\\x000000010000000000800003a0126a99000e5dbcc44d212891a9c5784fe5e83399248be6d8a429eda3b1a342a04c628bb6b219025f2c11e302b444cef0ccc981d903f931d8e96d650b09a1f781b47035c0538764ea5f5c70ddaee0b1a31c64515b13a0ee5d199cc4ba5ef431eebbbf7b399e05c089383228f9396ec30e8af4fe01eb9f45aa8521ceaddd626f010001	\\xf89c3e97a5a2cb9d0d8917cf1974fde54862d2cc50cc5b87e270fbb266a34e83ec8e3bc07f320df40fd711aada4da8437584ad2ca4fe9204473ab392cdb65601	1658491723000000	1659096523000000	1722168523000000	1816776523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x9a3fe39a7e6cc24430ea5373bb1033ca36cf2f1ec8fae754a9c2d87c4fd6fc9cf0178127581fd9616b2ecd14cc9b786bc2e098d7be77d7a454a36dc7a7fb3eab	1	0	\\x000000010000000000800003adc09ce72f7aeab3bc575e3370aabf54470326ba54154fb4ac7990d226ee4a818b5d5073dfff4c02818d6a8cea2f39128894abd5cf763116aa017c0cc844d02f88281791029102eff0dcb4035d98a0646114cbc8592531a7b558244bab7260eaf1f09a51abe9413cd28052f73594e83e5a18f7f32de8f0ffdab094797c7f0507010001	\\xcc1a019ad116affffec181a5d75cffe96c9076b7e58cfc28f5d8f82aff965f81abce357fc745efd7a83d002def34ae85609f368c0c1ca07e00841896b777b60d	1659700723000000	1660305523000000	1723377523000000	1817985523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x9a7b4b6451aeb972faa59c6ec3e67242085be1d657952207d138de5895dabb9ae5bac4a31db967551ba8a395f82f9f385842b202753dbf132968b599d7478bb2	1	0	\\x000000010000000000800003cfa1a5529b9d9bfb80f188365a25a9fa0e4ca5811232956c11ca97af6ff43db4fa7a9f38dd35b99906e0e3342c59db008dd304255652a52c06e54839b378936b8ed1e1181ee68670d29a50d211b369022231ac7285e2ef21bb7b83ab8907cda8a1b500e8c5dc03d140d01ed85f250b3ee9735aa0de364bc0e1beb57e9e691255010001	\\x9e6538123d37d23b74123a257087105422eca45fe6e5ee07ec5adfd6e4e48deed59f8cba4cab282e2c23bd035ae9735ce6f7261fd4080557b2a7e1f9ec08c007	1672395223000000	1673000023000000	1736072023000000	1830680023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
378	\\x9bdb80a7bf8317ba4ae8dc90fd157eecef511443e43f71e8aa886e74c66526e956e803420ccd4d41692f9e1ad61b669f44184c20a96bf9035a2ad0baf460870e	1	0	\\x000000010000000000800003c5cb275d6c626d83530ae782870ba265c83fe0075fdb7f23894b282beea6f7f8cc6dccb29663d28b003a797469b6fc09103c20f21f315bc80e6c41ac61140216ae769b09bfe4d2fe6b039da2e1c731454262b0d2bc2d5febe8190cfdad12c9f1e81060cd66d5703a41fac86438f363d3d606c8b4c0705886fe1617319b3e27d5010001	\\x285edb747b36ab068c839fb8e3e5661d05e70ddb15c83bfb58c63969f9292d1c5176c33779bd9c92244b0c3e17adfc3aaf5a6fe1d9de6cb5edacc73e1e1ddb02	1659096223000000	1659701023000000	1722773023000000	1817381023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
379	\\x9f13c72bd9ccf8b058534e73d86df25530cb7da97571e2767b35cf9b5ca4f34e0ba56decd4c21c8c68c7901a9d263caa35eb20b2deb9d5df705fffe1f252b886	1	0	\\x000000010000000000800003c921f555c1d4666297d046f9759083afda21a70d1ad40ce744c3553408aabcef3acd52ebe08a140a1205ac1f5131c126aaf9692ec6c61389294837857b587add9902be5bd43d60d5040ab45e804e18af78dfe66d9f3f819b0d4404ab72fb2a294f61dc26dd7ca9220fbe1380a1c1027f0a4aa4c6d835050fc4dd4f0c1b1c5d51010001	\\xc55560a414708bb82f9b59f007d3e7306cc312c95d083e2f7bbf6a8e060807b27ded0033570eb54d7df30dd897fcd62838830e3ee2f5d0eb6260eb46674c580c	1666954723000000	1667559523000000	1730631523000000	1825239523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
380	\\xa33b2a9087cd5338cd6ddad58bb86d15c97ccf4d5d0fefc76e77734df73c6623d6b657bc3a8db1ee84b855d81cd87f7f9c312dd7969e0c560de998350d893c49	1	0	\\x000000010000000000800003c71c4a477f49ba55dc3c053b2f95973d338b1bfd46356448147068bb7b708314fdb8ce2643e93042d322d7bcbb6ba4afc71e94f8cca8483cd1dfdd56e48b4db261c28016d79eca7d5802c7b9dca79a39de10c12d61ef75dff92bd3a10d2cd4b6ba2e680fbe7f13e89e0546386e49e18b15407a7b681d57077a9bcab7830f8783010001	\\x850c26e5a994b18c055beb7966ba6edf79881a9b00d579526267ba355436be27b9b10545c069f99f515780097b276587e4a7d398e26a153e4d7d32ebf770f406	1671186223000000	1671791023000000	1734863023000000	1829471023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
381	\\xa3cff51aca5d26dce1283e2bc538bbb26864cac2cf6ac7e83dd7fc5a573c45c4b3fcba17489230a19a039b952166d099c915a294f231a6c815f7e70d9da0afad	1	0	\\x000000010000000000800003b85c3a1e4963dd4d91b93acb50280bdbbb42018e2cf103c318976242ddbb7c72dd633bbebedb686822c874d04ba9b68122c265c0b696805708b49648fb7a8ab3dff09a136f1daac3e0f5fc1ddafcb3ef4d904da088338843158600604e37c23e3bfe35695388368b4fa428decce462ea1ab77da8b083eda52e2604e996979c89010001	\\x88a18732b9d99f6bdc503e49ed3bb6644ef631ba9c89a679f2fd343f6ed7da0d419badc74e1269a5e2caebd327695bf140d41f724dde6ecbf0b705f13d3d080f	1657282723000000	1657887523000000	1720959523000000	1815567523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
382	\\xa767c25f0cf42448b412a936866e365366fa4d56185c32fa6c424de43726352c1841ea0bc0ac4c63b2ebb83e3e0e6f3551c5c22f240a721a92f6355e2c2a1853	1	0	\\x000000010000000000800003bbcf5160065709a64bcaba064b905ab5a7db60faca90ae68c2416dc8cbccb5a37769077ec8d118bf2cdee62d80a05c08fe6c4ed26b4d3a1f64a6e7fe72ce609dab8a6560f005e3c0ebe93eed7ea8ad29d5ea7f14471126f58952256e44ab3b80f38d3ae2491b5939935eb11d8b41b396d4b376d13078dd61ff1b26e983acac83010001	\\x2b38b9fe3a3beec519e5cc7d111f16ddaa019dd6581d47dcfd323b9f889b31a9abf2cb09c154d2110b911f9d4625ebd250ae1114400607cadbdb722bb223b600	1658491723000000	1659096523000000	1722168523000000	1816776523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
383	\\xb007a7ce46d8ee94e7e195fa9044d3cf01e7f904c8ddbbe1818e2ad35a22870715cdd0f6541863b514ed1429b4b3dee2f28aef60e3022372553f202a9a8ab7ab	1	0	\\x000000010000000000800003cfb3e3999030d8dd72c64cca05847a2db2fcf03561222c193d376b6ba6e20f4fee0e456e7e4abf2a48f9097a7dcba3ce1ca0e34145fc913ccb690301380d3dd95ab9b388398a440b5d6dec194bdc25be6929da34acf8c589f56b9a896a899750d04eb7f29b8e8b85ef17eb924c148d27b0939798a981aca96c5edc2cc9b2c2f1010001	\\x9d6f5b5b68cddb7634695ad332082c7625ab7f8a5f2dc98626b89d980727e21e858c70ec35e48e1a88fedc652a1af1c42f06be63de4123e84a2aa63cbd549c08	1676022223000000	1676627023000000	1739699023000000	1834307023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
384	\\xb13f3878a4273ee1309a351ced74343763f5dbbd285b15e15d848a1ecfb20f278405cf61e4c16de3de008fec29f26a7d6e0edc2d3c749236b62b30005dcaf4f3	1	0	\\x000000010000000000800003b7ce7e7908594763536af3a970fc2b627f04104954d83158f6edf43670be2be20958d411e2ef19d0fc7b06c86bb9541ab3dcb5818f2fc0619b68fff3dea092127e02c5faa34cd728743a44b795aa05b89e3837733d2d052a4a855825351f175d2626d70450ce6ec748823d9b13d9a0aba3448db76c2830cd3cc3bf846b3c6bef010001	\\x42bbd642dba766045e1e8bec22c4507fb739c75a85b92bdcf2a3ce86389748f0d4ca67462e55724fb3feb7b6d0cfd19d23d54d2415a740291b4722c5d1761903	1668768223000000	1669373023000000	1732445023000000	1827053023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
385	\\xb2ff33b9e902fea73e7c64239c61c3616545b463f1d06ae525e9bc80ef809d7ae5f99f4703ba892d120af4626f898ac771a896834d83062edb5ed6845e07208e	1	0	\\x000000010000000000800003b751d5d9efe22911945d4048b73e64bb2056786a28538ce1316fa53e05f52f56594e7cd83ba179395085269088526efabe6a8b57f79a7c187d99d4581657483cbce8842c9c9394fda3de93a9cfd992f44b6aff6588b95a928732a6690bffa5719dbcbd97c6db12d38c9a5f44e649a0bcd87b83f8c267cbc4cffd21a289f08be3010001	\\xf76282bec21abe62cdde70164f05dce4a8c0f9661601f3095d199f7e1682a442277aba0deaf81fd9ffe7a05da56a788c3c6f0bf957b28686f9bce146bfb05e0a	1669977223000000	1670582023000000	1733654023000000	1828262023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xb253e93dbb69263dc9a71b59232e75c36619b39bb4a35e88db0ceba0aaada7c30c15e6cb8e6e97d083cbf7cde7468151bc85a47e86a759dde704a791c30e06c8	1	0	\\x000000010000000000800003d17ab18394a30820a74f7bfa1f590f25e8b32ac15b53ddbc81d9cf252e449539bb1d75010a9359da6485328426cdaa53e70c3617b731bb4905ec94b330a93c897d85ced2fbca87afa713666f64baade767a6f50e9ce348d611d23e870bcb9c32fbfb818060e2178f3519337dc6b3925cc76d40e95c4170ede75757ab0f28c243010001	\\xefbb7eebabcf254b88e33f932ae1541fe3346e00b52947a3b1c290240c5c136b5a725bdf41ce06e80c7133614b4b89c883c8303a70a493079cb263c0a36d3808	1668163723000000	1668768523000000	1731840523000000	1826448523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
387	\\xb49387045bf9f0442dfd318b9e9c22c3debc258307976b70d146c3584a7e9984e81101e0a42570ef7544ca8408841aebb33762a778d0360cfb24c5da45aa5b7f	1	0	\\x000000010000000000800003d904390b9f9c46823e765dfb895ed09886155f62abd1c59c3fae8aef23b089a2c52719c1c638af47ef8a9915a92cd670194444119cbb01cfc927704f7d45ac1536c55a953709b14944b2987d63d25d6dc7276e02bd492cfad247c0d447b2891e42c036d407fe0a8e8fd04b752db4bf7649aeda637bbb450e4885307126d33929010001	\\x802a6e94ad03d203254e562146377661a3c6aacabeb9da2573e1606ca13a231029d89e2e7bd2b03966758e5fff9c134ff69eb760a590265705da5e6331ca5b01	1671790723000000	1672395523000000	1735467523000000	1830075523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\xb647bf6ed818192bc7592bc745e5b12a2a52d293b612f026a5f47eff3885b6e1f9416832853a8797b303765ed414158fb0a5a3eab5294ada4643d940bb402893	1	0	\\x000000010000000000800003b5d7d59e091112fa951b434b585aec8d647380f10f541898186ba1436c2d45dc75baa055ff2cba51fe0356180760d359bcdd0555ce03a2697ea66fa6fe8976294dfac303759e5da9ca545284be444c305a62fe965b4ab227987f42dc43700a2826cea68a09a133a049c35bbd9e4c065d8a8ea48ce3dd4708c2d658b63783c3e9010001	\\x9b055e189120cd1484bcc06bcfb195e4266faf8a2732f2013ef5b2e2c2356c0436e447c1c83315b17b8dd8eac6ae841d9df108f98ff6f65a308a962ee326f500	1667559223000000	1668164023000000	1731236023000000	1825844023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
389	\\xbaaf99c3a4931a9761717b102c930469aac401860b525fc49771b4c9b027ec6a4761020e57bbd5c875621fa48755972fe98c97a39c8798c82d2a884f8f88420c	1	0	\\x000000010000000000800003ca06d391805fed69d0d6f81d55c6dfc6ebaee5478dd368081089eacca9bc72a899c3d351437dc6ff5d35c1a55e34af33fc1d822c546e349606482d706ed6ba973e1f22b04ec8de2d63605dcdf0dd39de5d43b717e2f8fe1adcecb4d566170787e9d5f3462e320e7fc4cc2f617e1203344af34655c188a3c98e91c886eb0fa273010001	\\x32646cce16c85c4c654a2271823a3212076e5b431ff74c2fdb1a2f5bf675293a3cf4783dda545343b39326cbcf14a162b1b9e9c15440a35aa34ac86217dc1d0a	1653051223000000	1653656023000000	1716728023000000	1811336023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xbe33788f9ebb26432d73249e4861304e147f44390cea04cc54746f212a6095483ba958ee82ca4a8a6379f5d04b1310b26366d54572b325f66cd9cdfb889a2356	1	0	\\x0000000100000000008000039cf0f44d0a5444b05e0cf59077ac0236a9c52dbea1ac1898975a9e222e533b5e5e060e4fbe9916c4a62cc6d989372811ba710d90d725c0a38be5f5b396866db5e2d5b95b74ec28ac683cf8ad9d02bce379d14e24298524cf862cf2d4eca5f73734ba0dd80a0b32ea611352426eaa80e51d92306cefefe6b5e7364e42e4c0a781010001	\\x0d3ca3b127b9bc8a2f20fef342d50ff560e0d2e08fa0035e60518465a7effb206fa670babeae2978f5277655d897d06f1290938b7e14893a3a37f3fd49011a0e	1651237723000000	1651842523000000	1714914523000000	1809522523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
391	\\xbeeb3135b335d412c60e667c369dee9cb6239659112239a3a6986813a6eb638d9244137ce9bfa375be41303b7f881fe3e9af6b47f3140c168120c3c439dbb447	1	0	\\x000000010000000000800003e1020b84f923419c0d046f7dfbd3764d104e35a08c42f194e3634b0d947ff55e9ca19717116a46810b52eb5ddc53c32ec896f951bb17240bc870515696c78be07fcdc26badfb14def6599f74fa28cb92143c9db5c46263471ab803299a2fee705b43017322d52eab306229f67b78ce83f687d5c356b9b7b58e4452cc8ac2f207010001	\\x157b1412f3194a636a2f119cd327dcf8b2d611987598d017184954c0903cd6a04330e3f1a04d379195202cc47c4586d4e2555ee1dc1b6ad6e2eeaa968b0abb0a	1652446723000000	1653051523000000	1716123523000000	1810731523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xc0771fa450ec5fb678ee31641730360978fa22def22ce9f22211e25b852c625161c817574ddafc799d8909a7f4dff41332906564e5ad915ab4a042ee6493e9f2	1	0	\\x000000010000000000800003e987cfe41494ab979580c08845f293001ef829121f040d6425db9a7fdac3841dd5b8037314c9986883dc072ad0e736da690ac0679986114217b5a86a498fd9e65dfdd390837d28be8d2a1b9730d9f441cdd13bf1f4c27f4835d453d2f84290c6364d9943443a9f722f3bb34516c5707b72c54ec14b61bb0be3cf0c08797126ed010001	\\xaeb8dc90a95740167c484586a98314cb81e38d9e5742044630a81bbf9611193b50ab84329f4e24becc4a1533c0da7055e502d7762cb3e70f9cb3b8aa4eea3e05	1653655723000000	1654260523000000	1717332523000000	1811940523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
393	\\xc1ebd32cf9377dbaaa167c255e62cb3c532bc7b2fa3135b1e712dda71bcd13a86996a7302839aae1d0627b11edb89368c91362936ebcadabb387c0dd671531c2	1	0	\\x000000010000000000800003a44184af1d68e67db08ab2fd2c943403060490c51b23b5109c2b42428c5eb0de52439434dae2b9cf717af1ca774b5e4685e4b0b0a86d562f604ba1abc2792c6e6cf48c55fa1fbb2f9e7d5f3865e8592c81a71e804d690b7822e5faa8cbd480ff665bfe638454eb3b5fccde0b5c19fcf828bcd3db2a08b67ef001bcf6d0dc8fbf010001	\\xe38f4a7fccfaaec8dabbc2f20c8dc269da1c587c61d58bc3eba7de4fb138e6b095129dbbcbb5401a19c2b547b03a99d22aedd08bd0bfe330420a4e3be03f8603	1657282723000000	1657887523000000	1720959523000000	1815567523000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xc187bf8f052ea2ae4df644afc6a3184a72a0e5faf6b06593ef9a86f4f5a918c58e6f44b714d5c7711424fba58d7c4f5e759a418133d2a066948fe0c445f6c1e2	1	0	\\x000000010000000000800003d42c2d8ae4cf66abfe405b2b86e86fc21d670586ae49100b2b08340252b927df5e2a141bcd86d6fc5fba4fb034408ba7ca8b58873703fd837e070ca55481651d7c3ff8503ed8fc06e894c1814247d567417a7e6048a6242718c3903631eca695013b07890b2e9f45f945cd22a325304f7da096ec16c8abf2057099ed3e51c953010001	\\x3ce7b55827a35d0f0e79f0052954bf784dba6853e68e77e2be49d56da91f914dbd90d177ca9c15b82fe698fbfb6d2d83d5ccd3195fb4fedca7dd09d7094bc10d	1658491723000000	1659096523000000	1722168523000000	1816776523000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
395	\\xc42f651ffb54ce22883b26f35fa87eba25a8aae684a0c7e3849cd329aab9b7f37278cc9326b2dd7cac43b7c997cae24ceec8f5fe07be74335cecf966d1df8a97	1	0	\\x000000010000000000800003b417688cc18467cf237bc010491b58e8fff1ebdea49b88323ff32fa6ca3a862d83cc7603322bdbe26ca48aa8b4f74f48af2e8441346c2efdb35c68e37079356dd0bb98db9d5690e59f9d751b3daa05ef2bcb7c6dd49c476c24613de70ef29633ad2057b555379fb19ce8fbd477849b86060a0bd267700b58012cdfc508c46b0b010001	\\x53ebcb1da24bb1e9271565c79d20bf283798fb485f9a0f818f386426b94ec092f550be7739aa53303a2a650d594663cc5d728d6f4270a1abbaa887c96b228e0e	1659096223000000	1659701023000000	1722773023000000	1817381023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xc8b7197c7afbbe0216ead96d2a96c215f3e3ffc8be8dbaa83781e132b5d58015897d84e98f34d3daa6d9737a160478ec1c299209dfced84799f51c8987c6b185	1	0	\\x000000010000000000800003bd1955f00b448f42063ac5fd53cdb5a9317fa4ca3c6405553a95c4b707e0e16b6107032f53657cd2f6a9e4aa7e8c511a13e9b7566a118e1bb33c6404fe201dd6542b7db80c243b10d27d0e6e7db096cb7e6b2cb0427b68e13f3be16c7f25727bc49b53be99690c69374e7fa28f97efcc70545e4741a49f091d7b6425686b220b010001	\\xd8e2fc63392a1e016157e01e4a71f6716c27b43576ae9f329aed6bab6dd315b6843a2afb4df7940bd8b3dc29aef306711b7811889a7617bda3228bb84701d303	1656678223000000	1657283023000000	1720355023000000	1814963023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xca0fe643da5737e15aa34e13e60331febe2476439b9dc25be2130bfb1964fa68ba91d5e40eeb7c33df19754d327e45a1b2e43c8e59ae39d5ff26749ff489dfaf	1	0	\\x000000010000000000800003c2c8335c2300f00f0d7897d6fec7a220ef89f5cf15c33e93b9e24031c73f0da37ddf96a05365801cc01124724a12df86001b6d4c5fd9db254332c05892d7dc7de208ea8b8d170364d1b4947615974a89066f8e9f13f61307c06ed4742e224018b7f0122b44fdbf4935920e40daedc68bfffe7686fa2f3e0e3f5fc87a89477f33010001	\\x025651d3f172a2483f794c04853be18b33e156e979c5b0b398bc47a14aa1b8d4f04ff325994b25c18116ebbf53e827a889f9f2b9a0a646900f6174e11fabfd0d	1658491723000000	1659096523000000	1722168523000000	1816776523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xcb43ff5429932d127d2e625a9ea0c7837d9965ad6e6cec76c71c6129bd2745125858dfa0c92dece9962276fb3cebbff67f5bd734a40add087cf5ac51742023f5	1	0	\\x000000010000000000800003cc4ea4add98eec0c14c9e6856295fcc6b4339cdec163c8cf9b1ec282e3a0d93b79248a3357d2f8f62080e3f2283a1198d3a2c60ed5b1a01525c8dd889f34d3b4142371227104d0df40fe1126d5694a6c1b95e2abd367b19a73ce52a904a573b07d5dc0b2c6c9903bcede870cb546d1def3266e4fa0ee4bb7b267329fdb3dcc93010001	\\xc8c1293037772dc4ca7de994841f32c6ebec00c796f64ba6970821cb4e43fd3fcf7dde4fac042400c26ab8a65f009ba556ab9db76db44d99a23c230098d2710e	1672999723000000	1673604523000000	1736676523000000	1831284523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xcfeff9068debdbb65258756005a49c951c68826ea38d77bbcf147a06a8eb524fcc7247b40ab783d81bf654e9b3d05a2ac5075e72c6de1d35f1a23c74cbcbd93b	1	0	\\x000000010000000000800003d45844bf3501fabb1f684e6e979b4cf7f8d4356475ff26865174c151d846a8d6772517ad2f8bb607c46198b184944bd62cbc77e79e9d6ac1cb27e9bb439da392d9b4b545ed5c3ed758ab5094352336391f008d20b120f256a47bd175f494aae039c2ec51cf659dbf09f2bae8c51f16d6b77e80f390ce47410c7ee51b25b9a867010001	\\xfc147601da9164af46a641dfe382946c5f820d72785b2ddc9ca66a4ed598db8bc9bd1cf10c26e95d450cc3d30ee75468ae2e6a8222f4988924d4e4eb55707901	1657282723000000	1657887523000000	1720959523000000	1815567523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xcf57fd6bdaf464e50ff6b05d9e1b5ed2d598dd6469903a994c390d5b1fd81ecf279ccc8d0d281ea94c382fa0fc46e6c247bdfc2e25b1efa2243a10fcaac19bab	1	0	\\x00000001000000000080000398d98f9f57a7698c0d619804213302bfaa7e4bf6be0926d710a657a86c7e8dcc9061906f7a77a5643ec7809b6382bfbf45711741cfc3e0b1e62291be1b872de57f3acb0d045c70445801e1f92eea585b4b981af2905cb6dd016febb2860408470f4297270e6bdf1a44f291e620cc31a89e57dcd0e388e5402012407cdf26491f010001	\\xb05bb22f3dbf9662b9d2abbe2204323f335edf342e15ea39975c6df623ce9732bf9fcea9addcfa7dc1ae3e3b61d1bee11dd1ad248b180d43b4c1c316659a9506	1657887223000000	1658492023000000	1721564023000000	1816172023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xcf6f28aa334e8f4980407efa6cffbca3cdf0301a65374dd7517a47b4e7d204b0e1b20dea63d8ca07e653aeaf619d2dc3e13f067087b732046019fe141b557a9b	1	0	\\x000000010000000000800003d0d72ab1622a47c66fd333e3ea85a93e75ca6a11479eff8663c2e47a2b67bba110c13394ce81398ae20c217440b9bf4e79a9553b640875deee3ce38ead9ae6cffd974bd966eab68a77d22840a355da541124b03ba54a9f83e53719320cbebcf5bd13ca3575c418b9425512aa8206ce0aab88d0858ca756a15724e9f8ee348c53010001	\\xf972fa4d0ae06c50080958416d0b4ac10368e132e0d866236858a7224e6b42605fbe8719165648717630f72ec59057bf001c7f3ad935049dac07244fa42c1004	1677835723000000	1678440523000000	1741512523000000	1836120523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
402	\\xcfc37c84fa90876ff1111fc1abb539e319075b83602e1167e0e04ae7407ace180681c1f0ad638615300975d89f94f8eb9a99ceba721ebd5b97c51560b67e45bd	1	0	\\x000000010000000000800003a2c243a7f32038b3c95319a66fed0388a36da714bc9514b4fb0f82ce5b421fdd1b9cd7dab1720c1e0922db9da72f502ceaf4d14ddcd4f864b05203534520409ffdfd92e2e8cc5361bc92fdef157a35ff935e701a4ae5fd7fa184b22593b3a517948b198d1354eaf8c6b727f2253a4b28c2323ade131ae42e26471c21958c3a11010001	\\xa17867cf83106d6a75938055678d833608fab2325ed396d2dc1f39b0e4eb1ccedc5fe03f3293031da731198e121ba7110807b6030aed15e0843fc4313793cf07	1647610723000000	1648215523000000	1711287523000000	1805895523000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
403	\\xd1d3a0a66867397504639d936279a743ba1ce3ac659c5b80c440e289852c67c057eec25d0c75229c73a7393c630f6eaa9d9b97c9196c31bc25fafe03426627ed	1	0	\\x000000010000000000800003b927ea573000572890e7ef7560dae9d5945e1738fa34681b58d43fd0b76a25a7442f25525295f5c9763259746248c994bfe1632ab7b1776194365bce8761b75ea63077203ae22bac732230b94bb7baec43493ef4b24ba61d8659c0d783c36357e2b9ebe29e2d3f97c2255833e2df71fa4705a99f93d8954f9631e0a30bdcf57d010001	\\x6a5baef1f0fad48452346db25c734c213b7fa76926b81d0357a3cb54fbf067d5a4e2305ac88ad72331659f56b7a6c71ddd4b6d07c8e2d17bff86046400356f0d	1660305223000000	1660910023000000	1723982023000000	1818590023000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
404	\\xd78bf928dc8fc281f04e024ee2d81c998c116aa5247d0211f1ee5aa7335f94d105f2d6cb902faeebea4c9bcc96654cdd1c1ef4e9439f60db133767e181256af3	1	0	\\x000000010000000000800003af105bc72c52696f65649d552b4b2a9f801bf60c8f9cfc2f13fb3ba1eaac206104cdc35cbb7219780a1a35cb51c3ece4eea0a4c3fc35177749f9493c7d80d2fa45e0644c5c21cfccfec0b2a08557c11e75d5d3f66537b9a18394191dff4d34ecd63a551c894f8fe204f9f767f23b7284d2554aea9e700d66b9ff607b6716d443010001	\\x33263c55a533748810dbb612a155e84b8c1ee08f60610aa3e9aa542ee0ffd437f9956518b086c095f9c353b1e3cbbbb29da8e44145c6159d8c89a28db377c60d	1672999723000000	1673604523000000	1736676523000000	1831284523000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xdc1fa90099a8e15ebd811b6fc152479f5f27eb53f967658492e6f82a26c4fe0fea6e6d5631300617069ce98404d853e9670fe7da5228095cf1c38f896c6e1db2	1	0	\\x000000010000000000800003e141b19d5a13940a7f659785c3a57aef60d8edd3a0ef15a9e13886ec37e4a1d521d3e111ed4816641c6fce11df96e3bcaeccd69018f07a1326dc512ac56c6c9516290948b7328ed7a4cd44eb2cf7416601f546cd95e93ba72e4d4586420a4980920adeaa94670593c63c4e14cbd7d7e0a6e26e1367a938f2904f46b783ddcc9d010001	\\xf112fed5c954bd61ff89d0b2ca4d6da2fe4574f687fac0521ff781c452cbca462e426bfc5f58bd1ce07c858f2139305597a79f3468f5369abbb05f69add27406	1656073723000000	1656678523000000	1719750523000000	1814358523000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xe05fe9e3cd228c9b3fc7e2deb6baf9256cfff60085b49a243f340ead95e32087e0bc77e4be4baa9bc4d35e9cec884e826c2255017aa27de0afbbc561ea466e27	1	0	\\x000000010000000000800003c9988adb9a1dc9b3d1e20e2032006be4722d46047b2d456d0ea09ffd9392e5dc75bc9790af22b6d481514a1db37f21a3062acd2d3c10f130caaf67187fb75dbb1cbfab8c9b9b6d4d99192e89f8628e5f271fa61260c858b2ea8bda7a70f5000e435b904ed1a88e18a39250a302d4e0d5409b0a799e05d5f420848106b5826e05010001	\\xd9430249be246ba59823db96b8615985b68b009cfffaa6e41eea18e79a250da0f996810374cf48dc195327e2e884cd8a057e38e6ee1eaa6767204c6021d06c0e	1659700723000000	1660305523000000	1723377523000000	1817985523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
407	\\xe1479c894cf578acdf56fbbf9afed4cbe9ee841e2d258520cc109fc099b6eb1884ae01a0ae22abd90f2aeea3a22c35fca2ccefa04cf36465d661b11293a234cd	1	0	\\x000000010000000000800003d54a04541e9cc2516fcc2299cc9cb058a57f763168d0eef78adbf0862e0486ea831b8c2be2e86f1c1b7c7dbd128ec6c7bca7a8b9bc497b25854de9a8260a0c27f201f8e647ec8fe8bd3cb8710f5a36850d20483b65347214158f3c0982221b518eccb8e283a03d25d00b9caa95e098fe3441ab7e163e7d7d29b89f13f53410f3010001	\\x0345e7e2afe658f37535deb51b9ba40fd71f5a231d89fc3b8e5c76511fddb192cc731eead4be89cad5cb7385a3ae6f8a0c90490058754adb9302d8bdffccf109	1669977223000000	1670582023000000	1733654023000000	1828262023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
408	\\xe58f8b6fbc47770ce8a16371fbb88174202bf71bb1e69a86538cb150b0c258d9a5cbadad7ecc2c9f62faf5a87030aaef8acbc5590defd50acdd5e807629bee81	1	0	\\x000000010000000000800003ca27f8b23d2797887f1324e73255623f49bc9e550a4856254300e7444c9b5544ea80af8c87903671d688800b7024fec127e128d50a54a819cc94393c08ad87d933bc2cf5c78bd556404ed758455c72b627fe9294d69b98e8129ee82590b653a8258d11542d3a2666dc8d6c45e4453637ab60f7e1c9d7534859d7bc24a8e7da79010001	\\x45d57a04c813509e24144a43f3e403c3c24740bd0933915d3252ab14bbd9c973fc9e35c745a6413dc173fcb25f19fa9f77735c4c411c364521e74cd4dfb6b603	1657282723000000	1657887523000000	1720959523000000	1815567523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
409	\\xec27cf48b8971d0875b7c69e8e0aa19efdf133f7b651cddcbfd2770d6e1c7d1cd33d14670c9e6ad2646c891c0501eb419a3c58576577d9a7d22a1d8f6173c2d7	1	0	\\x000000010000000000800003bdd0ad66af3727ba73cbed700c6b77c969e547c8ce42aae7ec773da37a36498857a27f01f5aae424cec5dc12026dfc311d5b4e4bcb73c0c1a23c1c61966558d6d2678302f9ce9bb12b97a5fe930ec117b0a34c574fc2cd014d27d3c8dc49fe5ae92f85de66c1bec2ac4ab625ff783ee76b887ac143995d0baa452967b70428f5010001	\\xc653abbd6f423bf8a38819e6ef065fa7a7f2f3e4a6727485f14a34a2ba50bcf738aeb201beedde8ad8111159ce336ea577b0ce44fc42437b904acdcfaec49b06	1651842223000000	1652447023000000	1715519023000000	1810127023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xef6b932bb8f15ab0b47cf3d403f9cfb1ca05a029016e0fa31afa8cd04d130b694ee6675622b245aa402810def8ef91933bf3500ebd20cc4a41ec812149b1e8f8	1	0	\\x000000010000000000800003a2fe4e859ee58fc27fd895a28b3bf6e3d8b26ae68bcaed3bd55bb93c5bd9cb00aa5feae7321282dc748c0f1f37b020f8ad31b7b4bacaf69281a5a31f46c32f5b45f2dfe03f84ed75ba0683f72b582334299b2286fb8c72d296c2a5347cc7cbb5563bda24280d6ca304994ec257da91acfaacba23292cdbdcaa69fe56f5905e11010001	\\xc8b4eb95d8d74f529121861b196c38968d11339edbab412d8a156a1c2cb2b6fcf06da7dded947c64be9904fe7c6d2bf4d91823b2963324c5087c56ff9b11620a	1666350223000000	1666955023000000	1730027023000000	1824635023000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xf15b6e74312ca7b2e37a84adf4483dd62f80e017ad0a023b79320b621f1e7f6bc9c86f2e822cd366d6cf0e4c508be967a2f5892b152c6de849f78922ad356df0	1	0	\\x0000000100000000008000039efe768a768dfc920fb6d83e3e90d48a37bd3092f52d3a94b87840e1874d6775344bca2345c66188c46a632e66ed67a065f0155fbc28aca0e987e9085e1108ba583a7c30d0fc2da3f142b20da6d28cf223f07f3eba78015a0400a58fcdb50874a37ec60caef080700d9ff1331fe03b5561268960949cecc25d5c89b61786da2d010001	\\x6cd2dc15cdb5bd6805e85ce0fee56fd47872c88930b3b6b4ea71af5b443a587ac7d6be5ea29a5175ed18c8a04190f61dce9a1be56c85623ac3b8d73a6e83b903	1673604223000000	1674209023000000	1737281023000000	1831889023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xf223bbee92329b7d24b5f619e3df495425707ef0dc6c3e59a3de17a57fdc589cde87f718ea21a8148dd147dd5abbdc91c4fc1fcf6fe56242657b8fdfbb9122fd	1	0	\\x000000010000000000800003e076a3dfd9b6a2d8e3d7233a0ee7a6ba23a1072cbeecc4d733b7852bf10d91b197bf6e70697a80960bd41904e271c74f22f08e5a365d3cc68c8f6ce215bd6f359999f7d48e3822abd6d9806528beaf103167436cfd7ebd381aaffb45d344c6a517156af1bed1e305a1498719479f7a6eae945f6bdfcb07850af1085c5dfdd253010001	\\xad7dc94a5f9abd5a24b90fd205280670605bf39fd2c482d8fd2a97f1f0466df9c37404895eed49843d71a32db04b7987766cc746b263976c134bbe9ccdae5d01	1665141223000000	1665746023000000	1728818023000000	1823426023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
413	\\xf4770ffb1995ff9002481981f8682f40d48557331eda64ebfb5c64f47c5471690f91f13df4d5b63476008a069b2788f3d1804caf3c54911610ab421d676073e3	1	0	\\x000000010000000000800003a3738345a763308aa23a1bb865314a6afa61ff454a446c1cc3b5cba6ac382b3bb3c05399b58750f768eb811b4c88c9099bd598eb6afdd5e2f88d01ef144a6f12f6dbaeee6467be31a5778d4bfd44b2a6eb922bf97c39b6d82fc4ac16f9c85e8f93c4bbf87724dfa6bc77d05878af56dea9a56d30067de93c93f53b0071a885bb010001	\\x02bb8c375bdc3634755795bd877490afba35287482710645ec8e3e7c455161d3388fbc9be43c3f89c9739842f02d2727289d08b978cd6ebb34fccd1a5cc71a08	1666350223000000	1666955023000000	1730027023000000	1824635023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
414	\\xf437e65045dd288adf9afffaccd98b436ef1bcd9487cf1542e79642915b36a17332e334564e9f0935d709675b360679f1ee0182fef53407578f551a8d17ccede	1	0	\\x000000010000000000800003db0d080b0be3d2f760fc2079338927222cfc0d9107e87eb24e951b8db89f01abb94e26f58e1c37ac9602494bf6e6a86074566f59047af6d83c5f2ef99395ea0f5bc27c97a554c2b4795d49c60f7ec7e8fbb08b2fb925124156fcddbf58789a7f0dfd3790ed2038b1a0df3fed4dd0549f0b7042a2c23d732398aeb6e8e13ed62f010001	\\x27398812395de9d7def8fedf68e0fd46ae1ba87078cb288ac23a86c709d4de4910fd8bcda73f158120f2f44e0b8f141ca4e6f252ccb01816656befa0d1ea1b0a	1667559223000000	1668164023000000	1731236023000000	1825844023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
415	\\xf6d7ff7aaf36530bfb8e0bdb032898bdc30f439bd8a7c4485c48862a52e9930e710d319825e574fe99a4797de80a96df4911b70413f08f517f913036932f3049	1	0	\\x000000010000000000800003d68a85b9693f98aeb4c4c486c92d4beb3dbba77a79ea7386b90b0ac203db506783fa9bccca9a1a2986f68e14ad1ddee05a24dee7a48a774dbf9ea61e66c886617d72c9b502d9c3b9b4a7ae1f5504bcf4944a6115e5dfe782ed92c817d184084295bcaabe578e5352ca76a1fa030faee13e78ba476f86bd797a002a6a118d3d1b010001	\\x7ea55148a8fd0ba9e7d8125fbe388f03c03a47c5b9ffdb19e6432c348ab1522b84c8db7e2ee02d8462c2f2ae6551d29eb96132bd93367010eca743ff0a4d6c05	1659096223000000	1659701023000000	1722773023000000	1817381023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
416	\\xf7475c510868b4885256e1e99808dddfe634974c578fb9c26189d034ef0a715319cf43bfd672a939b1e0342356c23e2c9af02c364265c5ecfdf60c6e47f4bb1e	1	0	\\x000000010000000000800003d5563010e39bf0023f83d19bb69879d70eb4e19cbe3b95ce729b1a1f4982e6d867f0bd9581cafafc3361163461f3bea10faa8ef95aed5f7bc048ad8511a0684789b67a1f7cfe36dee2a74793c5b076aa232a6547fcaa476ab2d75bee14b0c7e6b7628e74cbc7cf77f33625fda8beacbcc80cc297cb5799eb77ae19c0c4631aed010001	\\x6aaf1ca6364e1d453f84d6a52369af06b702e7ffa0e81529abc7670ec3c0fdcf58e21240ca4da84edc36fc45550fa916061c3c6ff713449dd9fc091475753404	1676626723000000	1677231523000000	1740303523000000	1834911523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
417	\\xf8630d31e50af5898d539885095c703898780e2f66c5b1c5576f1dd6ab0aa941a05035f3d090c39e9581421ab12df5d52e2a8b8f3014f4e9df45a270ae98be8a	1	0	\\x000000010000000000800003d30c181aada983319773c60e5f9b0805de8643ede65a10c6ef398342e940391773fbb323975ebb30b3cfc0214bc30bbbf4b0eda7d9c762d10a3ffae2d3e2975806ca1384bd2eaf592b1fb5ee569b0fb3dd8c51968bf0eeef424caab151eca27406613e6a76241db32b3cc753eaae8f82355232252d0132de81e95c3defee62bf010001	\\xcde9d478c0d54fc90ad4b7e6407915a27e84f132ac1df63db5b91ad54d02c890ac6975791b32efb73d3a979e3a9238373f08746d4cf6720dcb32797e6c956b02	1673604223000000	1674209023000000	1737281023000000	1831889023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xf8937c666a6d604108b53fd8273c530c7b46cae5ff596e2384297c9dda7d9f497a5265504cb850194de58fc8bee60081b4350a800f3b553cfb6f8667f3441d7d	1	0	\\x000000010000000000800003b83dad196e3bbbeb12d65177d61fe4ece49ffc237386e04c044a72471b58b031a2e86950f011f22af2b91d6046f5eeefc96e1e119eec8c93255cfca930aabd7f545a41d3cc509cf2d60d0def9eafda8a732b23629cbcd9f742316d49b91fce8a4c73f34017831a045d2f21358726780233d1231be43425a1036e5dde4b148e77010001	\\x6a3e84a666e62f62cf947684f495447ce892f128ab088d8cee535e3ca74d9e98dffaeda33d96aba5d5899edb7eef25034ebc9731f637e439fc332e28d64ae209	1678440223000000	1679045023000000	1742117023000000	1836725023000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xf8ff9b50d9e1dd8899316ac4086c9557f694c113ed050c2ee722dc101604776e4994e25171f137c4f22c80b9de4496ea64bbaa5da29856a5a0cf57c43e394d4f	1	0	\\x000000010000000000800003b770a007e0c07527475b2f4b2983f21ccb529f716f6e895057bfdc0807dbdfa3e43e62697402165334eb39cc77457f34bf987a1d3808ee970add8f3356d39be08fc77722c3b094abc1c039d495ca8b046b0da83d20611649fb12c0bf760c56a96c73e6138528baec75a1dd0f6e26afa714ad60a495cb0cfe75d9a94cf856ac4d010001	\\x66616f10af3590cb5ab523a4c63e5fc1285d95536e829e0e22f92f79dd4b2e51d666b9562a0a0a89c3e86108586b9ab3f95bd5aba4132a613de71554fff53f0a	1666350223000000	1666955023000000	1730027023000000	1824635023000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf93fb36ea1a9ab221842104ef82813b7d5e92c5f3d5a0abd402e74792e3a86454a4a98255fcd9b27b4e250334090e710d2fe5fa1666f494f7c7aede074e52a27	1	0	\\x000000010000000000800003ca7d66b0fad774295af1c84ae668579bb9e8ec04a7bca70d9b5a82cda4f811757bac9f8bcfc05c794eaea46010a09d09c98cad9e84de23e3de89ad11ce58e201ee468f34dc502050f8221c627a2caf8c2162ce4693243bf65e18aa00bfc95762642a45b23132eed34019457fd46e3848a3a1fb7505fb86c7a4f5fccd392d5ca3010001	\\x63e92fefafda5aefaa5e5a5b8323ee358eabf85d4fb2d58d23a88da99c68093ca28c30e9dd687ba81b0caf8415b3bc7e10571316390f6e8f28dbf58e55ed3007	1655469223000000	1656074023000000	1719146023000000	1813754023000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
421	\\xfaaf5533d1ac6c086697784a54995b6cfeab9fbaf341e29ba8c014d5740fee172476184461d8a8d37dbf84fec007a3c42892e4e1f6f784d92ff9a38e161be692	1	0	\\x0000000100000000008000039951abf896b746297b0cd7fe577b33f33ffbc3862ce5257b84c71912f833cb8301fa042a25153773450a4708181808035386f53c70a158358438784aa144cdc6068c4de9c5f52cc54e5d52c77e1ea6c846871683981e026f5ea5856e7177c8777f1e30a857b6b23bfaede0d81263d3bd6f5cc2c16a96b32ad0238356ef317fa9010001	\\x0107fcc17e41d6c4caf2ad53c6b64c898bb0c17a5cd05fa4f848b1e608a1a07ca7cf9e7cbe723284e1c15a2f6abbc8cd338970638883cbc26da56ff5ae01a200	1672999723000000	1673604523000000	1736676523000000	1831284523000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
422	\\xfcdf1ec6064c56929ceae9afea9819ed975e4245fdffc157abe99e35df8619144fcff993cfa01204367bbe1b50733b216d90941d96ea771ffbbc2c7c82a746b0	1	0	\\x000000010000000000800003b9e77f94bd6e1ef4f976f7c3c42a91422f363053bd6edeb48066ff4e2d7db876a1d075390eb649120cc092c3610e2a1695a02643002962f0467773a853fafd0a94c75e084786efb52be50c851f426bcc268d01cec86e10e3d8d607ce50838a758c01ba830ded4f6272a0a59055c8c4b26f35be196943c932cafb551b632ad985010001	\\x15524458a25e5d805a69698f3c23e2d66d828b23b8dec648db3d748bcbc8fa7e541cf6a7e52d76d5a9789a8d6afd209894f4bde8ed641412a32e22d941defe0f	1660909723000000	1661514523000000	1724586523000000	1819194523000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
423	\\xfdb763256c0e95a828d0118344ef69d8abfd0899c793f4922ecf6bbccbab4b31503504748f34398780e187d278f020fb7303c27d70cd63bf42a81ff5343caafd	1	0	\\x000000010000000000800003b5e04649484e4f4945e40f385b3c4443327f8fcb661fa6a75b46a567a937fcd54ee1ccba1fb88036a564f992fd3b580a0fcf71f5d0d0f51f58d5ff1d0f5161b0bc6231ebe0e1f274c8085f85827f75e849b016084307dc64b263bd326e9e660f77c862cd37a4854452ab09a21347c9d2d566883a80aa4536f949fd563d054c2b010001	\\x6e2ce519aeeaad8a56481a6dac0a055f512ec3f246cf1e30e6591700fdb3c7a5d5ad094cfb0dbdc263afc1c56f6328528715f40826ed2b626f48ee43cfb2a501	1663932223000000	1664537023000000	1727609023000000	1822217023000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xfe53c07cfd314bb8387e17d6161d8d8dfb653dbab0576c7aeb96c8e1d5392572848db56b99bccef8513e0d1c45f43f4e4bdccb41dc7d080e8052ad378ae69978	1	0	\\x0000000100000000008000039d5f5c4d83ad5275c22cd15cd8ed17d33530dda14e91042c78a3d6598afdf39ba81a63eae13f7d3568b2517a852d1350b58725a2e08c372981e6d3daaff0ce58d5336bf85b920a0203d61d3e88939fd0564d30e9efe7a09d2ba584879b4a15ca249b5194f8e3f834836489196e2bed2cd3c2fea5fa3e82c51a107fe3e1a91795010001	\\x577301344a3180f24ece141c2f87697204ca6ee2391d0216ea28f645f7fd4db08bc76b352af073dc5c5a790327e4d898c364eee4b8359e6b10c4e088b4746809	1660305223000000	1660910023000000	1723982023000000	1818590023000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	1	\\xf326b6816e11b4a27612034e0505cd502c85bb88588d9c792c879c5aba8950df4522514f19f494f1986b359b06c0e4320a872fca5fd6a49f0211c0bf621bfab4	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x19a8ac2636e17b9889e5a6a11b58a7a663dc4debf1865cc1a0b7ca81f383dd263d964faede6748265437285047c9093ec49e4c4b777189d8c8a63a7d2209f635	1647610756000000	1647611653000000	1647611653000000	0	98000000	\\xcafca108fd212721887b82a57fc2f8fca459f3da43494dc94c74860a0c9ea325	\\x0df669c2efc0ee16b62d7be4e73ef09f37f610ccb8e4dddedd9a1e2bbf065f1f	\\x51ede9a582b858a3133bc49d32976596b4abe241854ecae5176ae4fd9ad536bf4ed8cecb56f9f7c488b99aa2c7815b1a3e6b44ffb293a78060c8e5b00b46e707	\\x74d20b7427f6ddcc61f4a1e7e97fa864934caed33b59f5e89040df25ef1c7567	\\x00000000000000000000000000000000645bb09b307f0000000000000000000000000000000000002fb7c06dd2550000f02d8d73ff7f00004000000000000000
\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	2	\\x5f64643cb09fbed81c0e90495312a8077aee9f6f2fa9552a104e202ed532df021058c46737eb1a77f089a9328d039f4e9b13fdffe5d54e818549ffe19bf86743	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x19a8ac2636e17b9889e5a6a11b58a7a663dc4debf1865cc1a0b7ca81f383dd263d964faede6748265437285047c9093ec49e4c4b777189d8c8a63a7d2209f635	1648215592000000	1647611688000000	1647611688000000	0	0	\\x0323dce80753ee4f6bfb6dc822a27e39f5da7fdbdffe1e3969b43c67d79cf67d	\\x0df669c2efc0ee16b62d7be4e73ef09f37f610ccb8e4dddedd9a1e2bbf065f1f	\\x037766842fb971060fcd66063d83dcf4c526c0a9db15ab1fd2d04d6ff802a09cf9536eaa4376a57a4946ce3af75bcd7c8d425d54b1a4cc31d34dc3f4f385a40f	\\x74d20b7427f6ddcc61f4a1e7e97fa864934caed33b59f5e89040df25ef1c7567	\\xffffffffffffffff0000000000000000645bb09b307f0000000000000000000000000000000000002fb7c06dd2550000f02d8d73ff7f00004000000000000000
\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	3	\\x5f64643cb09fbed81c0e90495312a8077aee9f6f2fa9552a104e202ed532df021058c46737eb1a77f089a9328d039f4e9b13fdffe5d54e818549ffe19bf86743	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x19a8ac2636e17b9889e5a6a11b58a7a663dc4debf1865cc1a0b7ca81f383dd263d964faede6748265437285047c9093ec49e4c4b777189d8c8a63a7d2209f635	1648215592000000	1647611688000000	1647611688000000	0	0	\\x0821af579a9ad15e1469f41e44b6f745958f9a34c636a44d6e36e689e57eafa9	\\x0df669c2efc0ee16b62d7be4e73ef09f37f610ccb8e4dddedd9a1e2bbf065f1f	\\x147642c2b749038c2b97ffc65d038212dff30f3620075ad7207b488b2ecc9b5595b4bb2e24bbe2f63446d252dd2e9a0d7d27ad41ff40b7f11d2951a038552a00	\\x74d20b7427f6ddcc61f4a1e7e97fa864934caed33b59f5e89040df25ef1c7567	\\xffffffffffffffff0000000000000000645bb09b307f0000000000000000000000000000000000002fb7c06dd2550000f02d8d73ff7f00004000000000000000
\.


--
-- Data for Name: deposits_by_coin_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_coin_default (deposit_serial_id, shard, coin_pub) FROM stdin;
1	1877959228	\\xcafca108fd212721887b82a57fc2f8fca459f3da43494dc94c74860a0c9ea325
2	1877959228	\\x0323dce80753ee4f6bfb6dc822a27e39f5da7fdbdffe1e3969b43c67d79cf67d
3	1877959228	\\x0821af579a9ad15e1469f41e44b6f745958f9a34c636a44d6e36e689e57eafa9
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1877959228	\\xcafca108fd212721887b82a57fc2f8fca459f3da43494dc94c74860a0c9ea325	2	1	0	1647610753000000	1647610756000000	1647611653000000	1647611653000000	\\x0df669c2efc0ee16b62d7be4e73ef09f37f610ccb8e4dddedd9a1e2bbf065f1f	\\xf326b6816e11b4a27612034e0505cd502c85bb88588d9c792c879c5aba8950df4522514f19f494f1986b359b06c0e4320a872fca5fd6a49f0211c0bf621bfab4	\\xd7c1497756709a23e998267da14e209c9eb32806668222999b5e9533ed9d0b441e2b25d14d452615e1ef4f0d8b867793dc71bc6d416d6cfffe7e345df3e7880e	\\xf1161d928a47324cbad9fdba1891ffd7	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	1877959228	\\x0323dce80753ee4f6bfb6dc822a27e39f5da7fdbdffe1e3969b43c67d79cf67d	13	0	1000000	1647610788000000	1648215592000000	1647611688000000	1647611688000000	\\x0df669c2efc0ee16b62d7be4e73ef09f37f610ccb8e4dddedd9a1e2bbf065f1f	\\x5f64643cb09fbed81c0e90495312a8077aee9f6f2fa9552a104e202ed532df021058c46737eb1a77f089a9328d039f4e9b13fdffe5d54e818549ffe19bf86743	\\x0aad567ffd587f9b8b9ff050f59606eb07007aeb8825a4bdd0938bc1ae4a810e1e72289e909188292e345f3c2e91299b6bc70e549cb5af6c0d183838beb2cd02	\\xf1161d928a47324cbad9fdba1891ffd7	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	1877959228	\\x0821af579a9ad15e1469f41e44b6f745958f9a34c636a44d6e36e689e57eafa9	14	0	1000000	1647610788000000	1648215592000000	1647611688000000	1647611688000000	\\x0df669c2efc0ee16b62d7be4e73ef09f37f610ccb8e4dddedd9a1e2bbf065f1f	\\x5f64643cb09fbed81c0e90495312a8077aee9f6f2fa9552a104e202ed532df021058c46737eb1a77f089a9328d039f4e9b13fdffe5d54e818549ffe19bf86743	\\x81f67b303c45231e2b171cff55e49f59e52b666fb6b8ae357aabead6d2fe2f9f204bca853c592577b3121d37705ae3b4c2180df21c0444acfb14b9f37ce8a304	\\xf1161d928a47324cbad9fdba1891ffd7	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
\.


--
-- Data for Name: django_content_type; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_content_type (id, app_label, model) FROM stdin;
1	auth	permission
2	auth	group
3	auth	user
4	contenttypes	contenttype
5	sessions	session
6	app	bankaccount
7	app	talerwithdrawoperation
8	app	banktransaction
\.


--
-- Data for Name: django_migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_migrations (id, app, name, applied) FROM stdin;
1	contenttypes	0001_initial	2022-03-18 14:38:43.815329+01
2	auth	0001_initial	2022-03-18 14:38:43.991351+01
3	app	0001_initial	2022-03-18 14:38:44.133718+01
4	contenttypes	0002_remove_content_type_name	2022-03-18 14:38:44.147153+01
5	auth	0002_alter_permission_name_max_length	2022-03-18 14:38:44.156455+01
6	auth	0003_alter_user_email_max_length	2022-03-18 14:38:44.164333+01
7	auth	0004_alter_user_username_opts	2022-03-18 14:38:44.172687+01
8	auth	0005_alter_user_last_login_null	2022-03-18 14:38:44.180283+01
9	auth	0006_require_contenttypes_0002	2022-03-18 14:38:44.18335+01
10	auth	0007_alter_validators_add_error_messages	2022-03-18 14:38:44.190498+01
11	auth	0008_alter_user_username_max_length	2022-03-18 14:38:44.205362+01
12	auth	0009_alter_user_last_name_max_length	2022-03-18 14:38:44.212796+01
13	auth	0010_alter_group_name_max_length	2022-03-18 14:38:44.222171+01
14	auth	0011_update_proxy_permissions	2022-03-18 14:38:44.23049+01
15	auth	0012_alter_user_first_name_max_length	2022-03-18 14:38:44.237784+01
16	sessions	0001_initial	2022-03-18 14:38:44.271332+01
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
\.


--
-- Data for Name: exchange_sign_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.exchange_sign_keys (esk_serial, exchange_pub, master_sig, valid_from, expire_sign, expire_legal) FROM stdin;
1	\\x905806074d18f43f508978bfe311bdb569d236a7fbb36623f099a694dfe1bf6f	\\x05195dabb316a67eaf71ddb6f4226e860b4fba914e7f45687af6af1b9e3cdca9b7b8c7d804efbb57f42a197c12d400afaf3ed960fb660fd8471374d5147c5400	1676639923000000	1683897523000000	1686316723000000
2	\\x708d4d237f46e4d358d0e12a5164bde463275a433f0024adca63a5f46e9f3f2c	\\x6e645eb239b0a02349911fbfb0b0fbdfa33b83cfe3550abd29d893d6dacbacb51e3e6445985b801a2318e316c7f8144df29c6d443c77177f47cc51d26b8a6206	1654868023000000	1662125623000000	1664544823000000
3	\\xd36f4a65634d6bfcf344b6949ca0adb12b714e07b30962b1165dd2acbad7c2f6	\\x4c1bff1bbb11e64340b1a9da551fa31594095f91bd4cb679d6e520c53122654aced80a2aeeb9bd196664b68b58d9db933cb97f153c7f5c1ce21c6f8baed5f50f	1662125323000000	1669382923000000	1671802123000000
4	\\xd4640a267697d43b1f1471892326480bbce09852ece4dc54e50c12ecbe3425d5	\\xba2f685d3094836acfc8d47aa1f8a53ba1d51e80cf117eeba4e435dac83314b546efef87692331f6d3f7b0dd27b2148cdfe6d323573b3d67a9c64bdc4c92b10f	1669382623000000	1676640223000000	1679059423000000
5	\\x74d20b7427f6ddcc61f4a1e7e97fa864934caed33b59f5e89040df25ef1c7567	\\xf940deb8a5db102cc5e4d650248be1b6b271dda459b7b34882c1196d17e36aaa855fe5cbf40de75d60df23143b536e2e5b94f4518f18a36a2ff6e32595bc4a08	1647610723000000	1654868323000000	1657287523000000
\.


--
-- Data for Name: extension_details; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.extension_details (extension_details_serial_id, extension_options) FROM stdin;
\.


--
-- Data for Name: extensions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.extensions (extension_id, name, config) FROM stdin;
\.


--
-- Data for Name: global_fee; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.global_fee (global_fee_serial, start_date, end_date, history_fee_val, history_fee_frac, kyc_fee_val, kyc_fee_frac, account_fee_val, account_fee_frac, purse_fee_val, purse_fee_frac, purse_timeout, kyc_timeout, history_expiration, purse_account_limit, master_sig) FROM stdin;
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x00289933335ad80c3326d1ca95465c32f362b5286bbf4c52b9455b34230a090b681b8ad0267a2746c1e32767c09c06d9a6584bb13a162a3f28999856e09f3e0c
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	402	\\xa698b15bb5631f8e53111dee92a3a0547d4b6d6961b5d51c2a2cd683049e3f4c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000490eca807ca68d446ca5145b9c4397ce99061e8d489e4f14dacb319c54109508cfbd7d6d03925ce94f9db49fc2fa1551930ec90a1d1ef647e81233bc508403fe099c1bcca230de02f387724f2c076e42b9c79273e88ef20e0dedf8da671123d75abdd9bcc158079dee97443a7c8fc152ddfceceb94da7a4033edc58fb5ea5b70	0	0
2	185	\\xcafca108fd212721887b82a57fc2f8fca459f3da43494dc94c74860a0c9ea325	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000960f9047fafd38a9f9713f28a1eb911803f96118b308ce9068a6fb2e62c9b4310e3ca99897835fdcdfbe9f18ea8354583e152e904e6a0ab8e35efe69af4dfd9d6b46174e599e3b9f7bad4e8783b3174975106cbe93404a630ef4d7bd0bf38829e0429c1d04ccc01aa98ab2f312f139a1b80f6e81f5a64fd5c80bc562f92b3c29	0	0
11	305	\\x6947fb9cb94864067c01e460b342707755f909f7dba0ef5ac5d5583bc00fcc4b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000035feb7aa75c15f1be502a68eff3421c2a8a882ff84f0a812139f9c8f33a0dadf6374847dfb619dca20282d2a6e9a41de470d9af9f94a46c3bcaaab85d457a4fd205a6b47f66a7af3c11f6af8f493ef6b46f99771eef587b244d062eb7566daf2489a259efd182399fc9544933c499f9157f588291064ab4d24fda8048d1ef53a	0	0
4	305	\\x0f76d1a5d4f7b2473b1f66a07d2d6e3e8144d9789f6d82a542769b4c74612a31	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000032994ee0602a117dbab89bdcea0d27a7ed50ff87dae3374967cd5a9cf5500781f18a4147e495544c763fe2595ca86c2f9efa5f2b80db1cedc726e3aca49ba75c9cb6c00ce84edef7c137aa29c042f1c15c9c8da5ba7c540abd21b9f4d704e44b140cce5a6372da887e8086c3de71f16c48b37813e3f3050fdf89be424b91aee4	0	0
5	305	\\xfe82111726054fe5f358d3d6a18456419b062cb96ba7244ac778e1687b8851f2	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002080d5728cc5a2b9ad034039b0b4011b518cdeef700d81e20ae7dd86daa8c2923bc48b534bd2ecdead3b49eae0a84b9be9494c4d6b18a39a0fe87f5df3a26fdb8828c33a83b98a43e17935af716c17238e77164413d497ee74ab506d2280acff139187b5c8388d9f62d049b67d4fcb2c0a7152471d457c6178b804cab45aad5f	0	0
3	217	\\xf1a600d17024d2e4948be46efc0d1930a73ea6b5b8a2035638978d31d41ba0cd	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000007a0747e508436f4da8d2ccc8be35d4098e660ca080720c67a5005338f8f8aa15d14b12177a48bbaa83802b624687e6a89e2e1f92cb5217224998c1470084ac24603858ddea3ed5d8600161a93c7fbbd34e2e9cbebc31d5585c36b96fc0952b7d44f66ea4474f8e1f903642c8e17b7cb4e81ece50aae1d205b0ea9ef930d66213	0	1000000
6	305	\\x58ea2e56337f4ca5318958acb4b943b3a20de019116fda50472c46d21a5aa7c5	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000027f21505a7fe7401a9c6c9dd7fbdcf28f2e1f8ad540247c6f3c1c039c851c33e24bc6f20b022d5c5c8a8c3bd47fcad0ace66661a36a82f70e1499c772546e74b8ab2a29611dcc278cb2726d37218fabc3aadb0d2e833dcdaecc10f7de796b68d31fb143121636437c5f599a150a23147b556a9705aff9794233f6fe53b94ed3b	0	0
7	305	\\xd5c739c0eddeb986d379b75cb35107288bfd1a069acfc262a1467d1e7bfdcfc3	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000005cf71d6a7684383ee02e9b745cb88d7cce7ea22116124f1539b770e0ad28460b6cb364581e6f6567b913563639f9f6c23f0bf9001fe45834948f1420a922aa0bb1f275cefaba74c70ec4d3f91b4d80debb6bd06468851104e981cb3af22bde586cd60a5cf0bf4f90b6e776091c6c203fab42db5db0ae33a38ee305e75d8b34b2	0	0
13	153	\\x0323dce80753ee4f6bfb6dc822a27e39f5da7fdbdffe1e3969b43c67d79cf67d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000009da6a611b18d24fddb82653c0db2ce0f2d4618ba257eebe9d44aaa29517164ac769cc5836319fcaa0399ff6b1a3a31311c254f3a080f0c6be86fad2605741b54e273a005b9fa1296ef0b934e6a4669b1736250f0ae9ea550ed8c7f1a95f7ba2bbf0104738529d675abb8891d832d9435a4d740402662e98ec99a55f11918a0f	0	0
8	305	\\x64258c28fa5cf321519423d4ce84b9cbc913e8b9d6900c907425c6bbc4f8e329	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009398d4d59fe23375f33c1afd5141353d2799022a33ae84a052580159f0925a16592e206899f59ebd34df74a9b70fa46359cf885d3250545d0ec385432261eb557a05ce42b0567b4ddc16d867deabc8776bbb697b5d39c0f867bb15c82ced4ecb5a8ea01491213bf21847371422fd3ba4ca0a27ff51c7042275a22311ba387573	0	0
9	305	\\x968a7be53bbe15b73527a29e46af43d03bb66e81e36e5cf6b0477714cc6c9e30	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000bff03091fb98a070828facbced185f88f4b580322da54fd0857c0d1a30ab8c8f1e80d0fc95ff4573f56a62ec6682b1f3ef2643634fafe8a0691f337ab3ddf1f7a3784b256bad5ab00c1259c72615ee2a195fe8f1c419facb0c02b1fc1b01d455de36193b4399c02181e0da77916c476bb723de6e7fa6111ff631743d72b2778d	0	0
14	153	\\x0821af579a9ad15e1469f41e44b6f745958f9a34c636a44d6e36e689e57eafa9	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000084a3cf3936d92adad2e4b30a6dbfc524f82f7e7d6111b6f5e7280ed5acfbf91ea40f1c683bd937954166a3925ae476eb2e6825caebe74127a31d6b161ff434c8f1143985b7d0d8fac09c30a39678a4c626a02c59d11c94cde14d882f9cbf58cd6d6a6eeb28fc5616a0748df28dd3a054ee6afeadf3c8bdff87c29c31869ffce2	0	0
10	305	\\xd419aae514683a4444156be238d19abc255342ccbf6affaed950997a643edec4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000092b5e8e9e1365feb958638fa16d025e8b9ae470bf51ff959baa47f18129646344c386cdc8c2615785321f7a6e3409b287863a1f3dcd76512dadf574abefc05dd3e439d64c8e34eea091498bfef11820f388bfeaa51fb1d55fad8c44a9f95eeac23b1fd03daf30d25ff4b8323b2be8062227934b3c356c45b88fa469d654c62e9	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x19a8ac2636e17b9889e5a6a11b58a7a663dc4debf1865cc1a0b7ca81f383dd263d964faede6748265437285047c9093ec49e4c4b777189d8c8a63a7d2209f635	\\xf1161d928a47324cbad9fdba1891ffd7	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.077-020218WV7Y8D2	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373631313635333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373631313635333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2233364d415239485057355853483246354d544748505035374d534858524b46425936333553474430505a353833575733564d4b3356354a464e564636454a31364147564a474d32375334344b5848345939483551455743395633344143454b583438345a434438222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037372d30323032313857563759384432222c2274696d657374616d70223a7b22745f73223a313634373631303735332c22745f6d73223a313634373631303735333030307d2c227061795f646561646c696e65223a7b22745f73223a313634373631343335332c22745f6d73223a313634373631343335333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223932464a455648524538464a42374b5234584d534d4452324633545a5a524e484d5733383251483543353239374a564a33454347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22315156364b475146523351314444484446464a45454651474b57565a4334364351334a44565150584b3846325146523642574647222c226e6f6e6365223a224b5a584a513442433658594150334d5a58573756384e4e43583458574130335648304e48484e334359344d4359314b4146305730227d	\\xf326b6816e11b4a27612034e0505cd502c85bb88588d9c792c879c5aba8950df4522514f19f494f1986b359b06c0e4320a872fca5fd6a49f0211c0bf621bfab4	1647610753000000	1647614353000000	1647611653000000	t	f	taler://fulfillment-success/thank+you		\\xb07dd78a35364dbf8b05ca68e57b9bd1
2	1	2022.077-03GQR3KWE0Z0E	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373631313638383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373631313638383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2233364d415239485057355853483246354d544748505035374d534858524b46425936333553474430505a353833575733564d4b3356354a464e564636454a31364147564a474d32375334344b5848345939483551455743395633344143454b583438345a434438222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037372d3033475152334b5745305a3045222c2274696d657374616d70223a7b22745f73223a313634373631303738382c22745f6d73223a313634373631303738383030307d2c227061795f646561646c696e65223a7b22745f73223a313634373631343338382c22745f6d73223a313634373631343338383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a223932464a455648524538464a42374b5234584d534d4452324633545a5a524e484d5733383251483543353239374a564a33454347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22315156364b475146523351314444484446464a45454651474b57565a4334364351334a44565150584b3846325146523642574647222c226e6f6e6365223a2253564339434a504a42324a514d593251593643363050465853313744465a583835545a4754385442453945383748594348304b47227d	\\x5f64643cb09fbed81c0e90495312a8077aee9f6f2fa9552a104e202ed532df021058c46737eb1a77f089a9328d039f4e9b13fdffe5d54e818549ffe19bf86743	1647610788000000	1647614388000000	1647611688000000	t	f	taler://fulfillment-success/thank+you		\\xcf64fffd3859800595518fdd1ffcbfeb
\.


--
-- Data for Name: merchant_deposit_to_transfer; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposit_to_transfer (deposit_serial, coin_contribution_value_val, coin_contribution_value_frac, credit_serial, execution_time, signkey_serial, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_deposits; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_deposits (deposit_serial, order_serial, deposit_timestamp, coin_pub, exchange_url, amount_with_fee_val, amount_with_fee_frac, deposit_fee_val, deposit_fee_frac, refund_fee_val, refund_fee_frac, wire_fee_val, wire_fee_frac, signkey_serial, exchange_sig, account_serial) FROM stdin;
1	1	1647610756000000	\\xcafca108fd212721887b82a57fc2f8fca459f3da43494dc94c74860a0c9ea325	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	4	\\x51ede9a582b858a3133bc49d32976596b4abe241854ecae5176ae4fd9ad536bf4ed8cecb56f9f7c488b99aa2c7815b1a3e6b44ffb293a78060c8e5b00b46e707	1
2	2	1648215592000000	\\x0323dce80753ee4f6bfb6dc822a27e39f5da7fdbdffe1e3969b43c67d79cf67d	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\x037766842fb971060fcd66063d83dcf4c526c0a9db15ab1fd2d04d6ff802a09cf9536eaa4376a57a4946ce3af75bcd7c8d425d54b1a4cc31d34dc3f4f385a40f	1
3	2	1648215592000000	\\x0821af579a9ad15e1469f41e44b6f745958f9a34c636a44d6e36e689e57eafa9	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\x147642c2b749038c2b97ffc65d038212dff30f3620075ad7207b488b2ecc9b5595b4bb2e24bbe2f63446d252dd2e9a0d7d27ad41ff40b7f11d2951a038552a00	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	\\x708d4d237f46e4d358d0e12a5164bde463275a433f0024adca63a5f46e9f3f2c	1654868023000000	1662125623000000	1664544823000000	\\x6e645eb239b0a02349911fbfb0b0fbdfa33b83cfe3550abd29d893d6dacbacb51e3e6445985b801a2318e316c7f8144df29c6d443c77177f47cc51d26b8a6206
2	\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	\\x905806074d18f43f508978bfe311bdb569d236a7fbb36623f099a694dfe1bf6f	1676639923000000	1683897523000000	1686316723000000	\\x05195dabb316a67eaf71ddb6f4226e860b4fba914e7f45687af6af1b9e3cdca9b7b8c7d804efbb57f42a197c12d400afaf3ed960fb660fd8471374d5147c5400
3	\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	\\xd36f4a65634d6bfcf344b6949ca0adb12b714e07b30962b1165dd2acbad7c2f6	1662125323000000	1669382923000000	1671802123000000	\\x4c1bff1bbb11e64340b1a9da551fa31594095f91bd4cb679d6e520c53122654aced80a2aeeb9bd196664b68b58d9db933cb97f153c7f5c1ce21c6f8baed5f50f
4	\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	\\x74d20b7427f6ddcc61f4a1e7e97fa864934caed33b59f5e89040df25ef1c7567	1647610723000000	1654868323000000	1657287523000000	\\xf940deb8a5db102cc5e4d650248be1b6b271dda459b7b34882c1196d17e36aaa855fe5cbf40de75d60df23143b536e2e5b94f4518f18a36a2ff6e32595bc4a08
5	\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	\\xd4640a267697d43b1f1471892326480bbce09852ece4dc54e50c12ecbe3425d5	1669382623000000	1676640223000000	1679059423000000	\\xba2f685d3094836acfc8d47aa1f8a53ba1d51e80cf117eeba4e435dac83314b546efef87692331f6d3f7b0dd27b2148cdfe6d323573b3d67a9c64bdc4c92b10f
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x489f276e38721f259e7827699a370278f5ffe2b1a706815e25614493cb721b99	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xcbe1fcc586af7cf029aa75a06091e44ae55497510b6d8c1d41a8c6d26e48d7e7030e117bb1bd65d65abc34acd726af19d77daffaef7cd5290dc0bc5549fd5c01
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x0df669c2efc0ee16b62d7be4e73ef09f37f610ccb8e4dddedd9a1e2bbf065f1f	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
\.


--
-- Data for Name: merchant_inventory; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_inventory (product_serial, merchant_serial, product_id, description, description_i18n, unit, image, taxes, price_val, price_frac, total_stock, total_sold, total_lost, address, next_restock, minimum_age) FROM stdin;
\.


--
-- Data for Name: merchant_inventory_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_inventory_locks (product_serial, lock_uuid, total_locked, expiration) FROM stdin;
\.


--
-- Data for Name: merchant_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_keys (merchant_priv, merchant_serial) FROM stdin;
\\xa3a72c674503d48d97d321a2cdcbc8c4ec870d4456d67cf20d28eea4733efbf0	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647610757000000	f	\N	\N	2	1	http://localhost:8081/
\.


--
-- Data for Name: merchant_order_locks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_order_locks (product_serial, total_locked, order_serial) FROM stdin;
\.


--
-- Data for Name: merchant_orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_orders (order_serial, merchant_serial, order_id, claim_token, h_post_data, pay_deadline, creation_time, contract_terms) FROM stdin;
\.


--
-- Data for Name: merchant_refund_proofs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refund_proofs (refund_serial, exchange_sig, signkey_serial) FROM stdin;
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickup_signatures; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickup_signatures (pickup_serial, coin_offset, blind_sig) FROM stdin;
\.


--
-- Data for Name: merchant_tip_pickups; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_pickups (pickup_serial, tip_serial, pickup_id, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserve_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserve_keys (reserve_serial, reserve_priv, exchange_url, payto_uri) FROM stdin;
\.


--
-- Data for Name: merchant_tip_reserves; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tip_reserves (reserve_serial, reserve_pub, merchant_serial, creation_time, expiration, merchant_initial_balance_val, merchant_initial_balance_frac, exchange_initial_balance_val, exchange_initial_balance_frac, tips_committed_val, tips_committed_frac, tips_picked_up_val, tips_picked_up_frac) FROM stdin;
\.


--
-- Data for Name: merchant_tips; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_tips (tip_serial, reserve_serial, tip_id, justification, next_url, expiration, amount_val, amount_frac, picked_up_val, picked_up_frac, was_picked_up) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_signatures; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfer_signatures (credit_serial, signkey_serial, wire_fee_val, wire_fee_frac, credit_amount_val, credit_amount_frac, execution_time, exchange_sig) FROM stdin;
\.


--
-- Data for Name: merchant_transfer_to_coin; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfer_to_coin (deposit_serial, credit_serial, offset_in_exchange_list, exchange_deposit_value_val, exchange_deposit_value_frac, exchange_deposit_fee_val, exchange_deposit_fee_frac) FROM stdin;
\.


--
-- Data for Name: merchant_transfers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_transfers (credit_serial, exchange_url, wtid, credit_amount_val, credit_amount_frac, account_serial, verified, confirmed) FROM stdin;
\.


--
-- Data for Name: prewire_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.prewire_default (prewire_uuid, wire_method, finished, failed, buf) FROM stdin;
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\xa698b15bb5631f8e53111dee92a3a0547d4b6d6961b5d51c2a2cd683049e3f4c	\\xd8479ac4306f1b7f20cad1dec2b79ab20569a680970fc43de7d34be34669fa9642654d0b82bb3c692d5f0c314c45137187ecaf6eca823857a66c5dc65213af0a	\\xa3dd85a54f39ea860b8307157f259619b2bee1e30babbca233e4e98c999dc09c	2	0	1647610751000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x0f76d1a5d4f7b2473b1f66a07d2d6e3e8144d9789f6d82a542769b4c74612a31	4	\\xc979bd7103b754255ed43b005719633769975d47b9de854dbae7bcc70e5b49641bfc72f6a7e5b627a42a9e478dffeb83d9567012ee919f182146267992b6a905	\\x1278d8db990a2ef534753dd58cc99540c523bfe71c83b42137b5ea9bf43faaa0	0	10000000	1648215578000000	5
2	\\xfe82111726054fe5f358d3d6a18456419b062cb96ba7244ac778e1687b8851f2	5	\\x43d42aa4186d5115c9e7cad7ac26bfa2722ddd14aae2b42ceda5e5c186ec3f36b6d5fa29a22110ec1a54bca26e2e9aa8d2d819d2edd8a09ac87d7c65396d1a08	\\xe9d642e4df00d7fbce5970517b4637d19472f6f8b8f51cf50093451ebac39647	0	10000000	1648215578000000	6
3	\\x58ea2e56337f4ca5318958acb4b943b3a20de019116fda50472c46d21a5aa7c5	6	\\x66694b6297bcd7cecac3ff3b801afad2ab63d308b87c1e3239192927965ca6fa6d3d37e24022b61dcf67aafb441ee96249404e92a437467c29d0c06d89f1c20b	\\xf80a6641449a329266ebd25d9f9ed8c79723a4ec3c7dac907fb4de042e57d12c	0	10000000	1648215578000000	8
4	\\xd5c739c0eddeb986d379b75cb35107288bfd1a069acfc262a1467d1e7bfdcfc3	7	\\x28f69664e8d9013c05a46b922b7a610a5235f1840a776944527a1b7481d27dd3d080669ca0438a6aa68e8e328ae1aac04ae242d68d4490f167685f82e54c2f0d	\\xc0cc6ee792afb8233cb552f566b662c1e1ea2e537d9697a92cadb45adcdbd8a8	0	10000000	1648215578000000	4
5	\\x64258c28fa5cf321519423d4ce84b9cbc913e8b9d6900c907425c6bbc4f8e329	8	\\x7d6a23da1fa77720481f6698a3ef931d7b645348ddcde2ce07dcd0387262050a767df352df7ca06a9f630840de86e2ec7fed570741e41261936abbbd3d16060c	\\x89cca8f9f972ecd60419e110fc3e6ba9a48452814bf2592fe648d80b47abf97f	0	10000000	1648215578000000	3
6	\\x968a7be53bbe15b73527a29e46af43d03bb66e81e36e5cf6b0477714cc6c9e30	9	\\x45233c9f41259b003158924f9ca0cad7f1e21458f3173b4f0c665d877b425f282513e1d2b50efa1f6eb9129ec460571256d7bee0c167e699f87427d7aebe8602	\\x9d8546e66a503032492160550da28103531b47b2e83592cab887912c4fb95996	0	10000000	1648215578000000	2
7	\\xd419aae514683a4444156be238d19abc255342ccbf6affaed950997a643edec4	10	\\x841c26703cf691ae6b3e3d8984d1ccdfd9d5f9d055a27b815c757f408404e5ffb77fb26cae1c363139013fa2fc7067f8b3cfcecb9baa140922f00579dfeaba09	\\xfad69ce84aa97f89775a1e5735862ce1e4a3c4b2fcadf45ef37672940596d8b1	0	10000000	1648215578000000	7
8	\\x6947fb9cb94864067c01e460b342707755f909f7dba0ef5ac5d5583bc00fcc4b	11	\\x0eeed13f5148146be6f0be8556c11a3bce7782278098bd853179b969667ac7995eac2210417a1b0521f0df6cd2177ee73c136770f1ccf17e4f41d389229c9f0d	\\x6772e97cc9da31721208e4b5c6679b8c8a1c106c1e7963f28057ec6a3268d272	0	10000000	1648215578000000	9
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xa0105a807ffb23408c4148f6d561ddac4c46dcec236982c6d8045d18f1a544e8394eebbb536e6e80c74175d32d428b05952d120e097c08d461c24d69f009ffc5	\\xf1a600d17024d2e4948be46efc0d1930a73ea6b5b8a2035638978d31d41ba0cd	\\x03f0bc2ea6413d8e2a7ba5eb3df8a3ac4b9eadb6804e2b8b5b27e0c040b0e08619078b02052fc882eeec897105f6d4e1fe184d1211e76f54e14f3bd76d99bf0a	5	0	1
2	\\x7526e5d1cf48bcc0727310a6de96612efbb4bfcc722abea6b3f2616d0b2f1db5514c531cec51082e4816b5cd7670dd5f386c8c8a74248ee6da4874b59521b1bd	\\xf1a600d17024d2e4948be46efc0d1930a73ea6b5b8a2035638978d31d41ba0cd	\\x20776f960debfdd029116574eaac0d95a45871822f9adfc92c5f95aefcc9c15096a6a38c4b3435e5436124e6a29638eaae9bdbb86c7dcda3c495f4e81636580a	0	79000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x7d7c81af17ba030ed9dab7de2e0537041bb306879bbbb33acb77b9c468fc87e7fea06b816bcf8311eb29f2e474d75e05458347ce54aafbdf269d7b2848098100	220	\\x0000000100000100290a2567a6060eb00a2bf0ec69730bf440a9c3428a6e379ffd54fb15252bfda202cea4eaf62691c48b542f1f3097753b61e61ef1cca2656a1572484b5b3af55a813612f4c75118fa4fa11e750074b4a23c75cbe5507d473808af8590b27adecadae0fc313e4cc36d87f89d0daafbd0541e1882a9254712c5a0d89e56a66882bc	\\xb2c5542f37c43623cd66cc2cd7f2ecd88199cb08713cf0ff2015bcff1510831f83d4a1e6bf270c554426a49c581ad95f6fe068df84ed729cb35ea218e87105a7	\\x000000010000000135d27e4690947597ccfcd17bd981941c99e3f7dfb8510bf798e9102e5487b4bcf847fc283edd804df8a5bed090f7838e68fb5d2f27b6ca3bba48fe13d7306d91122189a0b884400caf45bf0f953a4d146720b6e0564237559fd5677f3e596cc177e4136f4ade651ad0dac7a03c42724193950edf43c5e148b8217fc64838f339	\\x0000000100010000
2	1	1	\\x7475186e097c8eb8f67b50f4a17e5e4b6f07b88dc9ec88749efc09978cf13551642b6caaa463f2b3ce872ca507d5eb7ac8a1902d6f06d93eb7917d0829fe830b	305	\\x000000010000010082dc0985d54c7d5bd9db5f35529b357fa70c294abfc6d4159a1658faf90bf9354a820aa3c50243b16ff90660d0ca360cd77a6003f2652b77920f454f6f799f494dcb82ead40a4a4a29e8ac448d25381ebcbd5d16eab86eefdc0e524aba81c9a6460ab202f5f64e3787e5f1cd6189009b441cc4d64ceeb4a8f1c35011c28334d3	\\x965a68995c2528d5e8d083f38422121f309316f1335af93f5ba9a2aee82ea7493ad5a7acdd0547262e3e21227547b26b1dfa3aa0d01320cfe8771da9fe053982	\\x0000000100000001272029a794fd326a142638a403ccbfeafb9d69d73a43cf6b0688178fde755f8c655a565f4b9afbab3d8f7e70c04e5c7013aefb63ee68080ba1618ba0219abd4a534773c18d5e3cc4b1b8dd5ea048da3801b2e776a001a5dbd7dc6097581f04ec46e18027b5779252d58aef29b4cb92473d31b8d6f1ed457ffc314eadebb0d99b	\\x0000000100010000
3	1	2	\\xa02cd1c05a6e81b1301ce52ec5adfee523a8874f244670e10f41213052a9bad6349fd554a8fe3eccbbc06f03d7814f1f374423238ddd0874303322c88556f30c	305	\\x000000010000010029bacaddd3208345ef09fe19dd2e7162cf0943f5842c91d09186dce347225aafb267baea07f0df9d4487e46c9d6ba679ff89cdffc2457e263e45cc1116f0f184a2ba898538bace6be1963ed55038e5f163a95965f9a2311b0e59d8789f96d691eff4e48a8e92d51da4d38591f3278026340dd49030c92ec771c3615984eeb71e	\\x959fa8bb9cdf90cb1e8cdec369b6e7a19a5fd22d1d28feb47c3d4131b18e6ac3270a9a4e92e61df2c3c97e66f37bd8b34f29b6eba39c523d0a2602d9c48156cf	\\x0000000100000001673939cc48799323586c6edf605b847f43984c41a3f6646b0d59e8bbda46c1822751293b163936e8894c6cfbc5e57fad485193d88f079c83d3588ef75c5e559fc17b5740e1767a39be89c36de73e99ea15db0d2ee5296defff077a33e51f4f9c8dd35624f2253ce120565f11abe38ecbb873f31d880942e6da421312f27f2070	\\x0000000100010000
4	1	3	\\x35aaabb5fe12034f5d5fcf5da19a524149c8d1b7ce84b11014ca6cf02c3c145cdbb6f9f2c910a83f48842bebc1a481fb665b3740508ac0ae3d10ada1f955090c	305	\\x0000000100000100b47c4f57f50422817781fc8232af26155136b53eb7f261d98f922233af3e9c0d7541495aa3825fdc4cb3440af765d245180348d155778b60ce4d5063c89dfe38102ab520597180cc5a3d998c63d14a164fb35726b37a5ba724f7790c9760e5da0904fd7a9768f5e1e06806e6a31beadb34ee59c6f0b8038155fa22d69c70b563	\\x3331295242eec7e77bf6fc58a4f995ac5694fd94ef83881d201b843ba9f28b91688c2589a1b031ee7c07b2c9f2a1ca83620e2c2b7f38c55dbff69b95067fc6d5	\\x00000001000000017cd0195a3c4cb891113ef50e7fcaa6520f2a51d86bff233e844b8edb328744d16f5eebc8eae00c5ba0f21bb69f94f9637e50169d2198c588fe83b9866f5131db7cffb3489da892c107b8c7fe2399abaf81eb3ef4a9d0e87f037db75a4eb2b30371e84e3dbc70f12745ea71d9e63fbad59fa2a08820e7a0840bdbe43c467f5967	\\x0000000100010000
5	1	4	\\xa47b3820453df30601d77596565e49952aa48aad1b92b4fa6744472fdfc2426b1fb9076515f3ec40274f423138b67e1561aa4b0a0ab29e8ab8e775f46b46d104	305	\\x000000010000010006e70ebd0c07cbd5af0ca2193bd18f582881c6ee3bdecd5345f4b5f2c24da435d121366347a8379652113dd5e6f0252e0c54a7925ce2347388429aaca36d09a5638e3a2ab559268a8dae3367d3eec30231e123c3f73bad768a2e0f78e75567b2e3b0a6763e0598208814cb0154db655d53a53e3d29fc758f1f8b80eaba77b4ff	\\xde6a22c9175c6c88aca7b8a3fbac32d57f224d4d94063f0d6ad40e67d62286bf52f3ae396a0d7c9872e68455eb5bf8c7a3438184a71385cce98168b933edf9ac	\\x0000000100000001803dd659b437842cd583f014ef7b708a6551afacca981d03a82996403b685c41ef9ef8e856b14034e4e0dc49cf17130ad38ab068e66b44682419174750d90ad9ed4eb9130fb2484b801083db9fc8dfe8772167c8e2dda1cfde7bf1f9ca52e018bd9673423d434ba54697588228f58e744a851cded86c4b89cb80c912d4742b9f	\\x0000000100010000
6	1	5	\\xf09eff924d5455fb56b49abddae901adeb0c71d98dd902f752c63239c00a9845a072922146e8dcf116db11a90fdb14919615a60791c18d66210f24c4a6608903	305	\\x000000010000010075f9fe17e5cfcd7fae0495b8079b938c61e9204146fc7b613722aa05c8a0fcee5a88e133f4e42c95a9f638b79c06cdc6619b584a205980c046432b3fc2a35373a8121a4b841d81f8de044288358abadbc1131f9e24eae4a62f66c317ff51b3bf9cdf87ff750c1cb0df2d84d4b83ff9de85aed27de983331780cced870fb25c11	\\x3b5b709071a65bcbd62c471ca9f7925d647c83440b1a072424391e1e1f33fe9e7c085e4e825f1a728841060a2e177136faab527d18a1dcbdd01fcf789a913dcf	\\x000000010000000106ac6302f6e5f66ee3693069afd6cd05ee08b6c55f0f12738ff9f8da6bd299123904b22677fe879315ba04ac7763dcbdbcc2ed26c0c3092a8708a1f81ddb5746d7cb8c3b24bf8a6d128484c92e69b81188a9b826c2bc7e738c4ad9c5983bbcb2cade164565624d3a635c0e365bae1ddb86d578c995a87929aeeb984f0eea17a6	\\x0000000100010000
7	1	6	\\x839fc66e89ce9516c70888aeb4b5a420464a1e85cc9be3c54e7205c345722c0854fa7e23ca268b86280582720abd785f851337ca0be4593b4d2c61a438e9070f	305	\\x000000010000010083690c764fc167f8239b0656c8e720de07b3c28dcafc4e310db4157ca06a506a8a29381d8f5045b787452236b6f71c46ab53b7baf6eebf1623d036beb6ff3070f7fe1a9b22d4290ac3ef3ea6955a3c1ed2398fa69d98dc74b6b2ca55bd711e0a6e80d3659fa07d1962f88ff514ff4747b966ee686b732bc77d4b0a3e26b2d9b3	\\xaa2299d3a3e422b5c9170edbecfe8219e2c5ae5fb226fd61a9d446ab7386dc4ad22beb22da18d283ca161b0638c632eeccb0dab485310b6a1fd59aa96a3d223a	\\x000000010000000181e77c15a442fa421f54b81aef870b5b67bfaa7cf54e6c6f019d305836919a2445c2171901ebd8e35eb1ed489b521b1b42317af0f301c06a7adfe48644d99b5c3f7651f42c428b7af8d9e3ead7bcd245417facd29340895573e2684b41b74195f69da5458d72d2754d3bd9f3926e3a581762b120ad906aa52a8aa3262155ee7a	\\x0000000100010000
8	1	7	\\x818942def66430355de818e1913d158e162ee864efc95937e6ae9df33e71a26f73d51cbce6416deeb342866aec71212e5eae1046093d8b425bb5c94a797c0c04	305	\\x0000000100000100a7b76817fb2e7effb58a4f2eceeee95a373c5e853f7c264b67e7c01cddfc9c14765eac1f2bbe11b9ab62b2fe31b8ecedea046e6da52a38a4d69a2d4191fe6a7214ec2d6154a7e56610b5965b65bea932d4d81b188c528df77b5ab44ea00527ec5b672e801eb98034d6447071430224369cf6e32d416f36d68d7ae0c8e3d1062c	\\xb62e665034d79f7ef16c7770e83ed7ae0c8cd880b5d2136a5b5dabcd2c599fe6c0d91b79dd1d53457ca4bb5eb15185a13050d4d46b5b334e51b7d120746d6ad9	\\x00000001000000017fc350428d75322d4a5f7a4dd8d073e02e00ed085919d8031e9456fd09bd70e08f52d7cefe43fbe93afe8e5c13512d1a39d30243295f9d57b772af90c016fb68857a12d08ea3b531ac5d9cc29c106494175061f9f56ab3694ca01f2b8bf8ff8f000c4e254b73410214f75d4924e11a001bc629f97cb3169e41b91ea4b6c99b8d	\\x0000000100010000
9	1	8	\\xb57cc87d34224c1eb4bfea11c94e974be1202ca5590a5a9ea7a08a960f9da84b39be5e7c5bd3cd095b78693a2080a1d37b56aba4d09e1f035cac21c9fd20710b	305	\\x00000001000001006a330e24e35f031acec4ce0a88cd40e4f4a11e715e37fceeedc826cab5c39d94b802fb56d4ffbd227ea607a771d0135d77fe4fcef2c5262a0bc0add00567a16ea28b4f73adc9e5380b0ea5f288af22b9db384f4b0e880d2594070d09565c5b31c0f24dcb2a67601209e709c4ad76cccdc641fd3100d4842068611c22b602e37d	\\x048e87f9116f3b4bd7a26763e88578e17d8da8eb69d076438722a5ad377de2a7c9e917a62a7de8d23f75b1ec15010440b2b081390a500e278fb31ec6ed5240dd	\\x0000000100000001357eaf32a971b26cd99dad3c520736ee6973cf9a8ad381ff016fc2180e8c23c6b03c0799c9462276633fbe2f7be962e6b2084ead5e7cdf6d488f890521796f03138940c3752e7b0fea7990a8bc9dc4373b4605ee21859a02772ff778e7055564b4378fafa8d31f27698fd03aeadf886efc391b0027e465a1eefd87aa2b0ce0ae	\\x0000000100010000
10	1	9	\\x856494e2d7d62c9f6cc1ffa07eec7e68e985b11b1830f4559f59ec3b973b5e768e8afc0085a8a1d10261d7026453f32f8a96b21296d83a3fb3fe70ec6ac6540d	153	\\x0000000100000100c4dd5728c399a553df58e9c8f61925a0e010708e89a190ba87db751c9625cfd77fec3c2a5aa0e8a04d85cfa68e4912962581eeb21345a03b5990e4ce4422d6c029707804e85abddc1d942510f8306fc658c7a5694dc5909a0b85c910d0505951ccfcd172fb8fa665ec1ebb1512ae9a159d9135c2333d6b55ae3193904f3a13f1	\\x64a74b560670f4c8d48e348613192408e023b7d32eec52e9ccade10b71b9dcbde732551bd7054ffb67c018a98fdd8c2eeb28bb4c0a837067b07c344432cea5e6	\\x0000000100000001234ed1f3955d9fa2b9263e4a7f4dab45df0c83744203b3c45dc9797c39859bf2e3ee923f7d7210314723bb47b0c91bfc66043b6a417b629ffb5d5f81c065932fbfac9e719897402778e19660a6275ed30eae3077c7b53729340df485cd8e7cd42a9884d8982b2fb5d83ebf368cd1541084f9118c928394ff89df835c6eaabf74	\\x0000000100010000
11	1	10	\\xb96d0b41682928e09f6bc67cd12e4c9131ceb426f95e5ee6dbbdf7beb758a3e98160f7d2582c265003656dda580820322b39f5e69bf626b38a2f7be5ee3d0e03	153	\\x0000000100000100950948d1b3aebd596b5f9d69e1a1b4a0f7f3954c844ff23beff4d3ad23f501d93ac958687092c33673107e468daf9d4fbc7ec6edca20f99280950ef8549715a21e09abfbd09bdba7a5801157f0378990c2ef2d65ce6ce0f2fd76ddfa0e6866c5051e15888bf776c97a64fc4b646bd2ef5f64781b1e8343601ac95885249cf1a1	\\x48402319504f07c30956e9583e9c8d382bdfd5c82341ca610f4eb5667aa9e634229be7ca2224480a47ca9e56f5029a1d43b5c14edc86fbb71a9ad3365de21205	\\x00000001000000014301acbc5065ba3fae0b0a9748a7acb78752fd7c0551386e47163776f94fbcf8e453b1d26818fd8cb440980d0bd8cafc21d10c87b3aefb5736cecf8cc38109279dba52130048c8714b585239052ee036c4e800f76692ffc3da281cb13af2b160af8c8f50f2f41666309b697c3e8e8982c4f7a711d91e812eaea1ee30e49e6913	\\x0000000100010000
12	1	11	\\xeeee63d4c424a7130f9cbee2cefea56c246d6bab601081291fd6332439e290ca59ea6a49b2993dbc222d6f2d67ede304e422f75203cde49a3a7b9ef32423c906	153	\\x0000000100000100afbafa3ff901556cedc46c74c4657ab8133edc649305f89403a7e002173d45f35f80991e5e8895e767ff3c68b07ad7456bb278396320956909bcb6b78cb9d7819fd04177543745d26d98e1bba6501e404a8dee87fd6e99c8889896f767b2049824aae1bff5f90ea5c65a246ae17209810ecaa94ae4b6aa877ebdc551d6c0a710	\\xef5d11fa8422d0c72826e20b2ff210ab2f81a170f29ae8dcac8c061c84b1588ea0d49cbf1275a8e5eaf020504c793b5b7311db0e43193b1c600d76a53940f9e8	\\x0000000100000001a5db4defc075be43d52d6d772c38e4698e9ea7d187a1f917d9ebcf138a537e053d0c0a811c4ea0daaea34406a7d76f3e23cd4cb73e5ef7c72f31115dbfadce2624556c8206d5a591146aaa92cd5ce280c7d14d190fbccfd86b927a1311b42955ac6b47f4f2f63234171b289dd806d5eeec4327b9b1639aab9610d9f2dae34c5a	\\x0000000100010000
13	2	0	\\xdf3e45387dc30e047062e6ef9fddd1891a781c1f05ad62ffacf2a697f742be297ee8a306465c345d60d61d3ad3fe12ed4379dd3793731959ded0b6990ba18a01	153	\\x00000001000001007e927e88322a0904fefad3d6101764a7111ef76da9dd75ee97a549ac89d408dc0c45134b24b68576aa933e334574bc2c0614d89d05b188843e00a214559d9fd43515c1a444e1b1ec0ff07c79056520d3251d8b821c4665b22dccd7b638e2c7ba94b14197e9402f3318864f258f0d2fd79d746e8f621f38e1a47e4b3816dd10b2	\\xf7ef71c57ee059a66f7cacafa17c3cb5e2c1e3863df0fb9858e302e9c4d33b313da3e8bb62be07a2d6ff321b4c12f52b0eb611177c5c80592e2f7144b89047d6	\\x00000001000000018810ddd63428cf61b91d555a3da5ff0eca23f7907b3ce74039634f89f167c4b900bc525ca2c350417750deeff30fba2bfeca9c673221c045f1b61ddabc48a60827629e07946dfa730cb9f5ff9df178a3cb4fa325817509f047743b3b71b5a3fafbf2b0cf8bbec6fe064bccfd4880ea01903a1f7f4b7fc6fa46896d53baa5e96e	\\x0000000100010000
14	2	1	\\xda0095a9f609f60fb7dcc8f6eaf2ffacf2b9e25e4b7244ffeb58bae0688e8071e1c563a7610f8b8432dd96fa9722258ec86d28af271887c461f7ee581ebc8506	153	\\x0000000100000100b870c2b2b4e305a72d1b47c2481d4e924a2b86d3edd541ae20ec40e1f580d8cc86d6380c0a22dd15c9950e4ad30f4a2f52c2a693276f7fb7ab6f8865e47a5956b343fa1bb609a5667beb94f3b94f7949dc8e899800de16129fc050e85b04c1317529f42fa0e34d3129536d6d26d6938ee17067b7805c82f717859d4b9b4a64fa	\\x47ab29d42093e044e9819644cbb0ee15ddba0776083b7317f629e2ff51b6acaca281150fe679b5b37be32da30e4c2849b3dccb6455550927c15313462f9079bd	\\x0000000100000001044cc9e25470a4f934cfbce37524c8c2ef4d42d2112898bdeff6fd2c6d46c391b679720888212438c56ba7073a0003d1d784bf5c3b1bce93c93e0a91221101d64382308aa75a8e9f7e5c8137a00b46bf5c68f234044140a2de2704cb71825c15991cf89ffcd2328dedfe293f86345fe7cdff3983967cfeeddf6d6eb6e1b557cf	\\x0000000100010000
15	2	2	\\x430f6a0124bd8f0f020a73f6b7ecfd08e57039a790963429ce4fca8b066f7e69022403773d6d43579f979dd938c00d8c512a60ef54637b1f39b3a4fe4adffc0c	153	\\x00000001000001000bf10d05add92800b6e4c729824fb7beba0958e8437d4769eb1c0fd00c31f4e7c0fc20d441d0126a5804c1856665277f909e9fc9cade11391d666b34cb04802cff1e3ea9a53edbd5379f9c2b6521e2762f78dd38c3d72185123a626bccdb381a115d7b39d6774e3008606ac2e7487fe87b050fad98acc192a3517564fafcb8d8	\\x1cc9dfebb88755133448dfbf9da3dec70c144b8b520710ccb60eaf755ef84a5ff94466ec7053ef6f2d23fcd5a4cf3d99f692e25ec690497cdcbb0d8dab4645c1	\\x00000001000000015165ff254431382a8c51ff77b2c9d143c539c32cfe6f471ee000766d947702cbd0b3f28201a32a97a3fab373943741a7a6487b6ddd0f6044e6605f0134d42798ad6841b4d391db7d5012dc68da2925c3d5e3bfec8d2e24cc6ac2a795e0cdc24996e244a5792888237322f1434fb19ee0ef7f61e82adcf09216094ee2d8775a5c	\\x0000000100010000
16	2	3	\\x5e848674a77714ce630db214a0bbedbf3ea28c9cd6f31af424e8dcae8fb46ef6126f59392aefe00cf8c0b5c0cf22277f2a20355d7afdc94deec418fc087a2305	153	\\x00000001000001003c867e197645d92b4c8891ed8c16032d048d225a9f9c04ec2e37f26556acc2546e9979292ad4b1dfe72cf7fb4e0ba4adf9425ff0f41cefc5587700cfd9e225c0bff26e640ddcaea03adfa57a288f6910f54f9f7d736d3f285c97b701335fcd9dc5e7d976444d8fb2ca6480406ec81fb2d83f4299a9f7b3cc10599bfa1726e0ea	\\xe5a07c0687fc3f5d8326ea0084de6f9e46f0f2879a6eec1e47fb04a54938a42a7745e1a0ad3680159afe3945766592e3cbcd7e7dae1fbeae85a0e1c1da8a41d3	\\x0000000100000001513362b2874f4f44d78f00aa387fc56c9cd6e3b86d0de0db2d8a187ffdfd28dcc567c489bc665a2cb674ab44094032e2047132cfa66b9872b64cd0a5aaf7636ecb0995004138c6db8695b8ea6e3ab50116aee9f98266c96b4e7e24f6c6cb89308e21019fe486aff06599d0e593cf2832ad1ac6cabee43ae5631478cbf1033084	\\x0000000100010000
17	2	4	\\x8491ae5870c9eea2f91e1fdedf63946af7aad000f91c0e7309967ab8791037dd8aa237654b57669eb8e9e275d88dd1ed5e6fed0e283593b57eb967064f7c7907	153	\\x00000001000001002dd46ebd8e7e1b6adccfd10731390276e8d0cd3374bfb09c60a545c916f4f15f3c3feeee8a1899e876769c841ecd20abb6eaff35f4312fcb706a7295768914af17d294d20803b779c2935e13b2115b8b5a7c0c22c6d00b03d7c11491cfd26e61b18d3c7ab78fd7b68258c649cfb0bd0ade16d3eb87f08d892d18367b40fc461e	\\xa9871be148d2b8e2937705b6972ff2655e6ad1f735195a4c995f46995fcd21e515f93a77d8332161ea8c011bcaac23d37275ed4cf17b34bd2ea89dd1f37068a2	\\x000000010000000117d3dd0e3aa45315f6bf1fbb22dcc636fad7ef66b2bcb41551e23342664d19c40f72c70597ad47e3a825e492f1767da632b0172a790fec88704f2da5e51f1f500681e748eeb15d047b1563cd020fc00fb91b7defb84257b975549913cc4cd3887ae6177501e96108c57a740ba7f7c952fe3097d1bd6e317638a82c0b47ac841c	\\x0000000100010000
18	2	5	\\xd03a04096b88640fa7db86e6b06691168bcfd4e947ffa4768897374aaaaccd56f981031ffddb79796bb2e88be74d45ca92bb7bad408ea07741467e7003d7e007	153	\\x0000000100000100a65787ceae9aa5ee4aa1bc6680029e3f27f273c6d4b67c07e79f81102fd2de3be4b44b3e087073bef4be3278a20efdd6863fad95b9254ab90cf27a7c06e827774efc2245c47d4f001d6458e5e80ce28865076caed25a510a2945151521e7d88d4de74f2988b790b4ea70a45a87d42e5b47d9036baa2782094677fc8aedaff8bb	\\x958f6a21109e138932ae5eaa9402a1bc8c2b134ccb638ac2be65620bb5fac2dd47aa4de1fd0817148acf58160a7de3a316025b0539b09214f04b83fc6abc2fb8	\\x000000010000000173984fe3bb8ddf04caa10da9036662ddbbd9d63742cfc92399cc2cad3aabc3f2af3d13f78de7fb0ab33a9a3de3ada3a2c1b5f5e2b8c9dec992e092aa85d324f97e4f3c6e0194051b26ae8f3ac57ae6dc7ac62a737d868431c7ecdbe450f470fd89dcc408c906af4dcf18b062f4b2a78573c375f955cd3f2cac0e209ef0195027	\\x0000000100010000
19	2	6	\\x65649adc0c34d3fc4461d4acb5e3ff1c92edecdafb6aa1c496e63a845f325114c4f86f20678bacd2302881e846a78bd896f1551abe19906fbc626dcba7690300	153	\\x000000010000010020041b2eb37a7a16969e6a0904ab7e6e2678f3708583b2440bb291c6fcabff24140e09c2e4b895434fda00fab33a18776ace28bbbe0f4e037f1b60e5430a4094cda08d0661b09c6a2930784998a4d0a841b04ab15cc83c60adc99990175ae0641f0efde9a5fdc4472d9aa86082edc3c2a8970659e448ccfa62aae050d60bff5f	\\xc8fdc83d51f20b25a1749a4523b7c9998170b640fc6ee5465b25cec959e2412dfc421769b9450efc121761f6f23f97882780bfb34a2c6807555d7e57813f4d6e	\\x00000001000000014141e26b2b228e10aaffd76405b136ae311cb2bb6d056e6fe911ef415e62c375079dd39e921cc3c136852064d5cc256763d9fd52a971329ad2c4334af6eefbc81cccfe7c864811d097821c517fa196607040d393e97d852da87c06cd836b3dfc5343d3c79304f7954a7e5e5978ae13c59d3f86d6defb5c6e2f3815b5d59e9a72	\\x0000000100010000
20	2	7	\\xfb5320cb0f48c6dfb4af0f3d0d2325abe9ccfaf915b7064ac45f159e911e671331336324048f3f9519515569310a74255f87b001b4fca7a954255c213e703108	153	\\x00000001000001001dc4388333a1ab0901746ecb552756bc9898e5d1d17dc3600ced661ebd8cf435b675fcaca036e2f1c4a23a2cc0cff731f8a236b8f371b5453ed23f28c2c6e0be0dbe2cd670aaac9e37c804b9be25dda3dec30ac2e98792435a34e19248dc44f994f0198e1785fe7ac345fa51d54a034438765976e68cf7bc9d058ac5584b968b	\\x89722022e39976477b9aae96a1e0107892b4a36ae18aad8f6538ae34e2087ebced26e898e20e378c342ce23090c7a2e089c0d72b073805ea9d6727591cc8e517	\\x00000001000000010dcf8299449b358e530d1ed4aefc99ecc4f43599518cd65f4b4a2e0877ff143d473d2644b48077a4171e03faf0d945a713acc2974aff2229d4d8de94327e78a927cbc9fa6ebc75ecb4ff26cea99ba8cfe27f0d5f56b9365622bf49853d368b78b0c1e29aa81be823f3070d0d6f7a23c1b4c13ba02f37f4c153912395401b4cb1	\\x0000000100010000
21	2	8	\\x40117d48f31beee5a72099585c31b61fc32728ee9fd52854e401bc491cc467b928aeff6cb1031653b9f61b4663673451f3df93b1328ee22112034b1392bc990f	153	\\x0000000100000100196ba8f641aea53ee5692e1bc4c7732f788ac55922a8372d22fcf938b05191a36f0a9f89f3d941b00de1865be36aa216eb44cb603f936c8ba62c70b9de7b7c08b19926cfb0e3767fe5802ecb727b827b2801499beb5f429751327306d9a4bf30b04a7321c0c6f18d7db61405070ffa1d2011e87e30dd18da2ab577211b9a2f14	\\xb59823dfaeec3144b6ec210b63ebb55244bc6df7988504b19b8392f6b48de2c49240de8023f035589b6aa53ce9066e19f39c30ab1520193707d91cc6b61ae8c7	\\x00000001000000010ab1abb49bc0c90058d5261985ebb147f6d9050b45ae05ef0a45e309bafe7dfd5e56a6b13ee87c50aea29ca548bbe22b46fa0be1b0cdc94fc33326d5be7e98b5e2a43ca6e40148cda4a556879f58117ceff9ce59670e4b54659c96bbbdc05cb6673304d6ff06f42002d6faebfd552fdc46513423c632711434e710373e0571c2	\\x0000000100010000
22	2	9	\\x1f6da1208d84adaf17e5b029f0b3a5f8e183db2805985671c8a33aab02b2efc9e6654eedd8e32c9fbc51bb58c834851c83661e6ef36b92fc9f9b92d869377500	153	\\x0000000100000100a826c21704a8230a8edfc63a9caa939985311b4b79f2a49f7064e983d5319dcf4e4e5e19f767869f428fb2fdc4492ff234b8abc7e79054ea67877c910150ac67901eb3b0311f83d46ffdb6b876b7e903c33e9d3a2d3e28ba2eebbbb143c9edb45a548605cae4210c3ba9628caa96cd4839b6063f8bcd87cfdbb11c21dfdf7bf6	\\xf4df333c71252a0415741ad6246806ef1958b00b414cfa4d04419c43409e16ec77c23c02db342e625fdcf4152b363a03d7b811920aec9c5ad78d5439a40c4eca	\\x000000010000000112511eabd5799b92fbaed1c5f107ff55cc23f8eab71c085994ab58fefa8827e55435d0eed3725b141a2e016e12cae94a525e15f520fef4ad4cdf380e794c57da558bbc822b231a8f89be1f0652a2fc88172407cb93b1f11e3964eea64b2893418bb20e576141087045a94362defeb3791f0c60656cfbc07dd305927570af9dd1	\\x0000000100010000
23	2	10	\\xf4c68c104e22186b48ba49990bd5e224f7d58a8aee17138df16dfb3928fb4964cfb7cd5ed5e7086a0f04b0c74745d0a681b0fd89d8ce5ac82fd21b4492aead09	153	\\x00000001000001007fdf34b8929f1f5a7ee689ed643d7f42f4e9a49cf695bb44f32565f148fcee84d47129c574eac4b71ccc0db9ab081e2b54d136e0887028c0b5181d4e4f079413a25fb3fe2da67de3e7be4e3cc6d6371089dacb6258bc02957148eb6e9fc7399f704de60a7d38ee2cbea90c319086e457bcf8ca1a24a2499c88ada8e05527252e	\\x8a6c554a3cd75230be0d51ddb0b6f01e4c9f1496243b8ed49a81add464428af95eed41ac13320cf5f007493aafe34a99db39d582779702adfdf4e72a1eb259f7	\\x0000000100000001725ea89847483dd16751cb19096657ffb1f4c69ccea43c7f0778b16afc7c8123b2ec24c15f103a80316f5fdcb1ea230b9b54567e91d0088b3ede3fd5517b857c2d0ec7373b390cb80e6e21c57ef8161a3d9a5b412d2b0e1364342fa6023165d4011cff38eba8eaff6c271646ca4bfaa4c8b89368769bf6304e0752b04827dfd6	\\x0000000100010000
24	2	11	\\x584d9c3526d001337018fb4f31420e5598e358766c2dc85f28cc24d8b3b2920f92109e6c8d241d146b42f71fd0f806ff17d1e586017bca7aa117a8fc6d1cb50b	153	\\x00000001000001005edb48bcbb10290dd6d4f102bd8b949fceccff9df1e5c94c4ff046a5843e5c523e2e83fc481b6a3da27248df73f544c0938e98eccd642560a8d0372e64cfdb2608d3024398d606261504a95856fa1480852a61005e09b7ce12d08ccb103622a94d53d344b2dc9417e6ea6c694fa39ac716bfa214ddd5455ddd0bd74e1e85e856	\\x6c1cea8e5ef10e0891542469d3a60177a8136f14db0b44fa20400ead991c5b7138cb1d765c951dfac484790781d49bf693036371aaaba9c790bea63242440d1c	\\x000000010000000104de93ee5552fbd00eeaf98d8392b827c8d851f88871e55016cfe3f5067ac0038681ec2ebd94c65891d1c1a15ca6f0bba382703e2f3a9bf78c19ff58dd3680022d76cacd731c9ef47685d766916df50b038426ab6e6d597be8065413ba230582543196ba51f93b5f872449d68610b6f9aebe88497cb3b719d709eb2f4c57a875	\\x0000000100010000
25	2	12	\\x96fde2c0c9a94b919fff8159a0bbb78d8a38b507ae70bcf61d91f3a8177db5af7a75b79493a9c69051708a7754ed7bee75b5daa2740c4ad2e6a2e7b7dd762e0b	153	\\x00000001000001003b96dda3d062892b0679be96a5de11e6e4c15a7a2b0b8018e6a8fd1f41fb5d3391dd44df794c15e49886d1931765a1eeb4a2e90e758f5695284479f56c63070fb1e4430ffda9ca25e8fb7ec55510d5e4f648ead1ccf5ee3de658f3bc0b938b5016e2051889449e4481b13189dc2060236cb3cd924562f87c1bb093b231fff8e2	\\xd25b1b56dc8522f7bd4ab9f3b9e963ed1a1169cc3b06c8e4a77743bd40d39b5a2d018ff74b8c35ad8481a6c8fec32d69eb9a529c3abfe65873b1438661a7441c	\\x00000001000000012ce982aee4e6aa9a3472fdcc94bcd14f2565d1287fdfdab1f9822fdd739d5b414a348ab11871b75cbab69cb46d8a44ab05faf5a5b1139bfb8e029e8bedfc6d581ed71c27a22b2ffafad98b5a4cace8316d0919e7c1c85fc4ed28806e1d0f16a1a39c8c783120c91f06c31e2ec8b964d83e1826b11444c5d096937c07af87dca0	\\x0000000100010000
26	2	13	\\xd30b07f4ca6dcd1cffbd05526095258bdfd583c85e1544c090f64ea5aef3d6cf66b2feb0e0d47ee3cce85d23c19b3c2c696ec6b317b1b16c441c54400702540b	153	\\x0000000100000100bba301e0008faf7ffd2cf70dd93e8b24eb817d8be796c609a190dfcabf5a89dce25202142652f448fb8c59f491797c080b9189e469fed35dd64b291460057759183b75cb2ddf20795cf465867057f45c0daa0455a9549e2d790a467dcdd81bea0a29afdb4ca78dc87bff67adfda74ca6a8772d260aa85b75d714696e54f5cb53	\\x82607220746338dc6734d60677771d2927b622881d3e0f15e1e8c6cbed32fce326cd0bb846402db9220ea014074837c3ca5444529dcbaf87318d53dbbeff9bfb	\\x0000000100000001585fe276fabe870ad30395a6fe4f33038f6662ae51f909a8c69714d5d792cdeae0114a104ff0163ed60134c326c1667fd0ac1b8531c239926552e59a67c7fb8fcdd5cbb0e21a4437ba049e2c0cd40f6f657fbcde30e54279167d1864949b21c32d4365fa80eef06d70900dc6356b0030daf6b04aeda4700800e52efd7eb449a7	\\x0000000100010000
27	2	14	\\x86d9a1a5154f7b19d43b2bdcfc7e4a5bb66e39402182b7c5a73be6da8f5095cf35814e8ccee678721d4b99b44c08c5f08165a0b1b83a54f81dd1214b9b083707	153	\\x000000010000010027830f8d049697207dc08992037e39bf275e21fcb0d2ed141eab775c600182f386d0f4cc70e447e939cd792f68b0526732f2452a047ad46bcedffa83ddd96e72bf32fbe2252d1329b20746dfb64214497111c42c1bf2d74219068b8a0607fa53c1c641abd60bdbdf04f54f4d2877f1ae204ebcdc14bdaaacaa53423519197df8	\\xf32430d15c889d5df643f94839aebd780c0543daf9c383bbc4ded52e43ded9e75e3c4bda66f28f5c8cf292fb3496e1d3787090840a3b9a546159b97023d6dbc2	\\x0000000100000001b958a3628ffe8797e075529d25ba12b3c2c23c71af902d3ca6f9be6a72873b22c7ea23c1b07a062af41840d84c0ffddaed68479a175a64acefd738322c1ae5e6c0ce24d53245a8a8b8a7997d0821c1b1991d3c896995afeca62cbd8d195ec1d268db17628c3bc406ed6ab5859b098b1f6769db8f3f3f27516fa02d17e33bb0f8	\\x0000000100010000
28	2	15	\\xdd58a4027f1d780dad23c0a2cab8231dadc6f1ffbe3462149691ca35f25aa846a4b260ea0c69c0ca4517f391f0eb7030ae9300ab94e8cfdcf7e4d1cfdd5bf70b	153	\\x0000000100000100117a2bb1c450a47501305b241ce8bf500ccef4d34eb650ec32cd94aa9aaca46de632426785f5d268554e7b90e04caa85bd0273a35fae273a614e6b9f9f83f84aac10f44c295598323edc669f98ae00660c8e78e93d9ad79ad13a4f02aaa14d973dec9879fa1adb1a876caf20c5a4456c4dcbe5b70760afd1afa28227b7e8f9fa	\\xd45092e8999f4b49ef5231bc7be65dc74c4fad1a188791783aaef1e67703b2e7b444e8be0d92c46e29add9eb3b024668f9cb3a1bd83e64af03716c2a9d871e01	\\x00000001000000019606f1f2bc9d6bf700e50a414170a2262ad8b9e1308348f2bdaf33bd76051d45ccdd5fcb85ecab4d523c38f9fb873b4d6d58a532c9cb23ca8b7d0df1ac24059bdcbb8848f5ef22950b6f20fa7d7bba9a5fbabd7a418eba576c4ba6b8ba31c41533d562eb25e46cd7e5dfc37df337e0e9bb9e7c9dbc3adea473e484a2a2fd2642	\\x0000000100010000
29	2	16	\\x3380a806a7b793de9c0d24a02271c42014f6828bbd9c25898db9c4ccf13a91782eda7ab8e3a1f2537ad106ae383f43e25bf933311a468668e743c0e1bceae103	153	\\x000000010000010024935c7e3bdeab975c8c85c935cca4c156cddbfb11aec5f4658aa306403d79d65ce63a50fa5d648bd8a80f13386cf2f4d5e668857786145a02c11ad9739568b279a330347e85218defb4f56f4074355180a5948f3f170e34b5f414213308f741454b06d593c179e0fffab94dc5778e021749c63724b231c6234d2aa6736e666d	\\x1baa9909f19e01671f6cd100fdc755258f03bd10fe8ec0df564941bd8707cae5271381ff15f8b48b6c7314ce4333f4a6dc8308c03c83beaa0a4ff5eaca7e29fc	\\x00000001000000016298179cc4ae1fd117a1b4907ec181947bf4a519465039b51a11a1cac1594a4fe223f521142c47b2e4d68ac3270d53d55537a2cf3e8255d85a56fefbae924e037d3ae249ab6c2a74dd69faada6e06c22e598e75165004c85a16d334f855f9d7e7268256e90f0f93756bc357a97b8ca1fc192ac64f687a2d0fa16dc14ae7863ed	\\x0000000100010000
30	2	17	\\xcc991d5e12ffc95e17b5d754da1516b2260c9fa8334a6b2a44f5a2107e1ab0d1829181670911623e166684ead789366e8725253725eedc104f1f8ee2d1e30c0b	153	\\x00000001000001004c57e1e3d57b056c4a9c43f9cfef701f0e76b864ab6e7667e4b4c97290e4b4995e148ab0488e2f1ae7402506e82f7ed3dc3857eae34b22939947678515d9be24f284bd53ca2d9c0a78f3312b42e23993c7b555770383d9aa7221d988b5f873ab91bc07b58b05fc3f8b39708f4316248c32bd186b284ffd370393be84470d5d8a	\\x332c2a9fc418e3ec8342a5bb299f658a20de6623a6f187c25ec4e13ac0618cef79ac95178bcf064708197f59d3940c377a08e4bbf363f830f08c5ade244c1b30	\\x000000010000000167eedb85800908e4af4df10fc91aa13d52227ba15b7ba4748912f7ad706256024b7380f1b6538e3bfeb9a21499813d82fe1bda3b7acfe9feb83e35f41c428e14d1ce59b3b169034f407d8af844d2e11f16dabb3394e19339ac44f47e91c161d03b77f722a20651599c17c7b6947a02a723d053bbdbe8d5165637bbb71e87be92	\\x0000000100010000
31	2	18	\\x2a042db523d62b3abd7ccaa215a6d3bc6036a82908389de4e5cc991121cecf22c4423afc85fad59b19c521f8524d104a91aeb7952482cf3aff6992ab51969b0e	153	\\x00000001000001009dd9fb9b634b33f87ee1b80f0ea25684585ae49452ece03bfce9a44240b63e05613b390676b5a511c4941927226bf8a5d5cdf8cbce97231c9c65461fb84fa88600fc24883b387c73580a7c9720df3398264318cda2d78607d3166eff6a66859e6128570d4ce6b96b56ad8516e6710f644fa53e9a09cbce230cdefee6307e2508	\\x3670333f8898066f1ae87315832768d53e5c2c0ab246034c7437b9cfdd8e70c47862bec3a03348162194242fb49cacfc6059900557c33d96dc55029440724316	\\x00000001000000013087786f9229c5685f34a484e9a2ed6c24ba3892e4cb2acd3a997cac7d196000752881fd2ed99e1af7b39d261c9bdb894ba336bdb41bb92b6b22f0195090901bfbd9aacb52391f450a574fb9ee876f4e30dc39213750f236737287f854d7ccd4d48521c432cd6f72f93580a73e93751f20350cca2b9a9f4880a8e17db7a58854	\\x0000000100010000
32	2	19	\\x903e4eecd93be5f983655ac406cd1627d27e2f26b1da8cf221b51b78284a14d6139b9573e2be0b9e04a94348413190bb254b48495788d14e13c035099545cf0f	153	\\x00000001000001004672100382d14db931217d7f4891d563da4f0d60b2380eddc8a5c6db7e491b1e940ed9b5780e7fc9508deefc7d28d7293475ae913e8424a91c89f95ea32a3ce914caf443d95140a250dab6a911e7cc0361ccdbca51e54a52600e127aa475c57e7335683181a10236be8b0ff4fb66c0c9d303d9e9406bf1acfd3ec789eedb7303	\\x6172a1ff82084d04e97cfa447582adb7cece55aa095d4dc481bcb4792131233f17cbe42642f4a1605e15e727b49cc217caaa6a840f2d3d986498d5986d425067	\\x0000000100000001c2844921ec1943b06caf2e504ef66ac1c5942975ffcbdfe8a9cab8434b062458669d708a7c2c44ebe110a7de32abffd10d470ad677b4ff1258aa7c8368d92b488878e8122fb7c194e6892335ecab48bab25c609492ce1f39b6b0c1865781f29991848e25cf659221f5111a9abb8867c9bd430fc807b74934f3bbcbe80456875c	\\x0000000100010000
33	2	20	\\x7f4ad2279422bef690c92e31d00a03d07a2e4769e58f64f174521601f43bf42a3b5c78e4a571073fe894dd11f92417d90847faaf104f410d83093a5341b4290a	153	\\x00000001000001009aca469906f23ac01357b304fda142a9e53286782cdfc33339ff1485c9d4470e450d13720c74f3cc0394e425c87e27f389dd14d883bd56bbc8a8108ed099b42b9b3bb7d14efb355d6d24449e11b1615bef9533c0800687627cad59dfd9ba1b33c46010943bc4efd7ea91812aeab62a22fec78a3d7815df2f19844b36d84f6e61	\\x46a17224a87503b27651eeb3b297682475a9c98a2e777de37a3d8982a956253380dfb0d64f185e55355b83e76f3640e264389926ded6360295c011e19858729b	\\x0000000100000001352ef16ff2c79acdf2af3f7983c01e4f6f1417004e26d36a5926911f247638d3ef131f7bc10d991b79c1b009a768ca47be5643a6a6bb712182b8706adb0050a8deb7254e674c9097250ff12a8e63d78aaecd3e981cf84691a8786327eaccddc65ba70e92246ee30c5e22eb4f953242b23a118fe86c45668dcf86fc7478811599	\\x0000000100010000
34	2	21	\\xfcef2d73eb9f922fc70bd1f6f3d8eac143aea924ae55dcf53d75e17397f547e3eef33c5d8e9b43752ac1c435eb9c84dd962c647d90e4a11e4dea9bd101cb080d	153	\\x0000000100000100c39ac177e6fa9dc420d535e322fea9f5ed5a8f0f3e1560ce3b73d23fada26a1b4fd973321957914ce0c8ee61bd33030fa80422b25b0bc91b4120fc498258824900e77d2ff86874d1571aff61f4f7767dc3b0d69ec37b483f138049aa6feb8f82142310a16aabcba04389e334e4cc4de48a24496189d86e7889420f2a0352f0ec	\\xc733f4410d5d6d76f2f951a9ba369abdf568e77089ab6e3fada20ece3e91478b5bea99be41495dd131292c1780942591b6b182a291ddc6bd7389ebca2416a57b	\\x00000001000000011be493e14c6cbd7ff57b3ff684bbec421b7f68b44597dc8c2f765b090b4176b404fa10a2f6901c0df8a05f806515e121984fb9e56ffff44dff1899ea59f3bcce4ea5ed63b16288ac34824ee23d85035e6d2955b6a79b3d4ee9963ae17371070dfd52ee53ffaf1810a57dcda97595441e1c4cf830ca71ab7245a6c755667ba484	\\x0000000100010000
35	2	22	\\x2adf576ea93d9d6025baff3b947a236342fc16415a4613d99d71f3ca432f29871c499ef362dad6a996f775cdbbcc24c9230dc3c288ce22964f46b5a165d39608	153	\\x000000010000010060c757d8752e8b2300679d85ddb7fc6aa6736b18db58f4afa47ad4450018127478967e0f38bc308c4127fa23348cba342ee258bb9eed354e2c59e4e06c5183e414d3ce8c0c444d265fc7b787abf9042569a1289ce87818f2aedaebfbea441d0a0ff6470f89f6b78aeef791e38d54fdee2dfb46e509b3aafd4daa1790529bdead	\\x74b0aa99e005ed688aed922f734f43a6dbce395e9b363a213c75acb35f119c66eb6ab62b5e4903d515325bb31ffcb059ed4e969905d6125ec3ea98a5aff776af	\\x0000000100000001316f436929c7e757af5e991d4a8cca62fea28834198cf33acb589277942ff93d8849181ba45976c9b0a6fceaa7e2cc3a5a4763473f619453962d097aebcf6c59232b36274ac70d99078bf40f7901137cacafb4b1b330b69c09bffb6995bcf6fb494bd2f7a33c550714204fd004d7428ed8203192a3b2f7bc211e0ab03db93d3e	\\x0000000100010000
36	2	23	\\x3e82d12cb35f642025aea82d2e72140c500f180f47cc7889fb17e20282705538ebb6bdd7e1a07e2250914f3ef5d6a2606060c195059decc6ee20856a9569e503	153	\\x00000001000001006ef47514376b1015eade3dc8a0fb134e419bb1413df68c034df1b92809fb5ceb83c2bc4bf31676e42219e9851993e9eea098a326be6464dc5f54730e3001f3af38c3a858ebd3628981e1a854f584414fbd660d3f355b42283c810ee26231f18c269c274de10702423b54a7889d5663554d1a1e5835e38aeaee5afe45b0592d72	\\xa5a7cbee102586fe4e6f9278b4587c52e23d6713111979ca9558b8a4eddf632354e9572e6571b9477d9eb919834dbffc49d972fc50d2532c0fad6e5df1dd0ac4	\\x00000001000000010473c5c8370dd8cd8fc2c7a925a462138dd0eed1bf20de1b44e15dc82dda3f04ae441c77f3151ac89e776e5c65862c8db7982610426a0f857bd60c67abd6a30ac1c728a8fbb6054d5b527524f7047f4fc3340ff0193065ba89be605cc12667dd679e5563877fa9c25da161806f99305bc53d42d3187548544cc187834a7cb842	\\x0000000100010000
37	2	24	\\x5f6232acd8c5351c651303bc676f69304da347ba71c076109e738bd5856cbd70dea7183fc5badb77912481ec81c81ecc2f422283efcdf0d95179429bda6e7a0f	153	\\x0000000100000100021d60519fc24a869d83c8882ff63301ef612e170ee63c52ea1cfba022a669b69f0a4ac21b339f72830a46582c37fb518401619ebf36c33977d03109002ccb51d90b8a96754a739176f3b4e8705befe29b6211d616e187a75a39b05d6e8a5fdee1d9602bcd7604527c8ac66f20a0891a720d80323753b208a0e7a79161314c9f	\\x05e21ad3ffab17ccbbe9fcc3c92072dc61d4f687fc080c6bb0a27474a29f5ee0d7ec7e58f56c823fd9a2941a69259da4c8e4a6e87195385030aca89a16307821	\\x00000001000000014d1fe9bc64028ed28e260640d246b73a99d9f33bd7ba25dd70979193f361d66583d932dba3b50e76c592a096bf88ca881b7cdc610dc3456ba77f5fc7689cc194031cfef9ad4d6ea5d22d6ad8b4652f07ff3ba22bd42267ed4ab0be0890cbebfb04a3544b8e925563881adf0f85c559e4568a89adbd0d01e00510678e81274602	\\x0000000100010000
38	2	25	\\xf0a8cad5ec4ab6bd3a1a2f658b70e7a0cb682d9405247f2fac27eba447ec5bb53c46de5345d8803b98e7a9c18f2664982586e1e86003d51127dbe8987f2f3e08	153	\\x0000000100000100b05561448179b589e1ff4421207223269fdbdfe9f3f669df336bc0e7d4ab14225d622dd7a6393dd781e9bdeb193d90bf72d50d0ebde6ae9ef3a52c7615f529db727a3413f7b6c8b55b88af9d7d9a2cc5b7305b72adfb4d98e69b567d8efe2a92ec98c6b66391d2733f57d4065d2b9ad2d65f2af2188e374318aee64d1b57b9ad	\\xafc5ae3cff34861bd2e0ab10ea87772d6c175aabf296a0ffceaf6c01c3743bbddcaf01cfab231160eceee71c65e3a52445f849ca201d68f53e4f8cc18a5a8bbd	\\x000000010000000146f55829cdebe4ce773155b79b6dbe5c14f408a8268f6a54a7c9a366b6fe7f321aa0e4775e4a4beaa94284490aa832df8b5aa32c8cd853dacca91b1c33d6206d85d643c374cfd3b40f6f2d39006648d504b2e8826019234cb15937549d5f90fc4836e655dde71ad1edefbad0123a758b40c5a6e0fdd0be5bd8881b3e8d0ef7c5	\\x0000000100010000
39	2	26	\\xd259e788250d7c43944425e2671c62d09bf9f59d23b9f9ad341eabc915d49a6627d44ff5e3d8a5b0e286b187e8d6b89837e00c3a229968fb550e784901148205	153	\\x000000010000010098c3d583d016971b7b54eb71a93f09b17e721694c9178d35e3effbb4f28759b7107b5c2ea990677e84fc5a08b563dee710cc6d876216370628f4bb302f75049edafe49072e5822d0eba7c5baa102fdf550a4d7af5bea935b9dcf69da16d48e9dadd6552b6942db77728581338cd98c115f6d37556377bce7e0fd9d0563a908af	\\xef58af9dd21a4a993911538bf87dc83fe9574819517f3741bae8391a790a386e750b8cb04044f6a32635b46c04a2f145d71511bbfad86813fb3547709def500f	\\x000000010000000123b13f5e6c0e988ffa277b57ab51940e916bfcb97fd5d7a3082c505c86c9139846e32902d40b02553a48234d34ca2e638ecf7afb611c2f46526cf24e9a7d579c0f806c4edeec9e5b7d85d5356bb7e240be5788be2bdbf25e9d8557f539939ce0a49111a3177920aa1113c311a3bca90b15b55a6a7f8b59a364807c8ae3de4ba1	\\x0000000100010000
40	2	27	\\x7d1b7c0c3c72784f81cd1dfa15e573108b1c5d3969c8a656e33a1b7fba6a6106ed9a98ebe16d1881b38f026f2008c3ae443a17025cbc9a4156203b64d73c3608	153	\\x00000001000001000acb99cbee24ee3ceef542ee3a4b6758632865de729e557afd4969d5fcb1519f74ebd9b474a634c6391f97b4173cc83fbea167611f40cd6451d7198bc2feedff98eee993dafacfb4f2c981ec3baf4a3131cb7804b0c9d6fd2ff1eb56c02f6dd5e62fa6ae063ab8d56ba2b4fcedeaca3a257698f3a54a1da4d620ca2cf6184367	\\x6e8aaad957f7ff11c6c123492195c6af98181f39f8b05bc1c7da67e5bd24b93167da0fa384fe56ff86faa92d36f9db73882095526a237a9bbd867ede20789275	\\x0000000100000001225c74b84e00ffbbd9da73b48ff154c6dd8f3199c1cdbca834c615e9c20e2e7c4fbfe0ffb1f9c79cf4bb7576dc92874931c4a7a62ad0a0a872196fbe70c95296905f948e06c306bc0706587d3ac6f5247e1b421684fa331a9af713e62137e3f3fb8d48ae31af95be3d721c9ef2d14034404f1a1a19af2fdcebcd461330c04719	\\x0000000100010000
41	2	28	\\x40fa774697c8b5ddd35efc4aa258ef12b73745e9f5ffe313dd3c17fb1b2d3ad1542f50067dbc696a396689cb8ce6a7353290933a39cf7ba503334556f7caaa01	153	\\x000000010000010066df96877954e85c552615b0dfa4d8f87ac54bab704561fc851b820ad852001124cd0ffb21a4eff4c3b81604f48078bc058f1d31c60114380a15d0275d8b0f2c28db9d54de63d78ec9a9f8207fe9ff4be4abfb9bd18e9ebf4eb81d3ea0b9caaa96d5a91d3fcd4b96e493cf7069de1b591a67d7ed16cd21c6e378a14fedcba6fe	\\x3adf5d1260a77abe34ad0aeeb2a0349020d230facc3bd8b8f426bf97b40cbe95f02fc4556500077a94f79fa23907f668e7797030703c9b973bd1670c0232c18c	\\x0000000100000001759b1ba7a3c4dd34f74962df979e672f8154513b13444021799a66247f6a3d109203985273e39abbb184d16c20dd6952d841b261158886597e666d83eaa0ca6565b31f96ec86f761ee13d1c957614576527176e0ef8ac919582184de594b21cca1ec5cf57439b1bd87f29902d8362cb6677297d2d98a6c331b5d7aeca086d1b6	\\x0000000100010000
42	2	29	\\xb9bed60d254d0a43524bedd7a615cf385435f34ba37a6be1baab2f907da9a376035c666202ef99bfd2173d4576cbd7c7a33d60ae698c1eeb2e8faa53188c9c0b	153	\\x00000001000001001c00aacde6288fb933b10284255c7a0ff10cdba9789bef51f7de978c2febaba80d7b342c625c86596c47dfcf5fbfb280b8afdc2129c92ecdde98e3ac563887f29db0d4ac7a8bb5a81acf88f57a525f3c71b3f2961a823acc98fda24ccc444b14f56ec7a2a2af0d60e44ed7206f57e88e54cec95a23e15c316f87c66ffeb2c8f1	\\xa8ac04d403a8150f280aba33889d632e3a1efa8d594d74f8c1c15991adf77e8bcad8149c80dfd75452c6e3e66f8cc14a7a5b3ce14f5f8fd5e908457aaa6dc1de	\\x0000000100000001b86c88b78e0840d64c01194e4a665e8d436168eebb385c57cea8cd10c41c70db077aafd9eb14de59b97ca6eee90ed790f2062557ab7bbca8933f71c344e90496288dcbaf7c7be46e4b3dcef1dac7c19643379130a0f77462d3fd3083b2c0467b6dcb6e19c57b2862f69bdce817f9a7a8ed767fd2166714883b50751d1b7d3cde	\\x0000000100010000
43	2	30	\\xbbe730de3cd2b5f23aa19a4998735f683cbd3cbe460353c3aa35931ac0da135b6b48a942b7c33b0cf320bd964886cf8eb4ff4a47fc028172272914bca0273302	153	\\x0000000100000100140fa6de44f801ad82cdd7c81d7977eba2e28d5a2ec5851f0c0b582cc3c5048bb86acb016ad0e536b574b510dfa2c15428d4a6f6ee13d0aa87db251fe0644d221e3eb648924c89cf1bf2438a8228604465409c9c38075382b5ce4cdda32636982f216f0e34675b358137a4c44b36fa576a95b20529ebc734bb42a0dc65a959ba	\\x00d67f0cba0c67cf55512ceb6cff3c9f481f2b0aac1ce548e1e1c9cb14e477194bdd101b234f6ed1b8517ebf89b1e99c9ec276b52dcdd300ed3d233c73dfcaec	\\x0000000100000001bcddbae71ada99f4d7451a91a60beb15a675abff7d073f04bee31aac1d1cfb2c87db26ccf9caa8677ee83cd2ffaf08da5b234d5fdad31920f7f997950bddd87896b02e419dbdf403b808f43549c8ece3ae9e7ef05ba8f5739439c9fb6cd9002536a5688f9702f7481829502e4fddb3cb4036dfc5231711dd7d3a70667e4f2f5a	\\x0000000100010000
44	2	31	\\xaa719499e765693818f21bd887187308a1c0c0b2aec79393cbfd3bb35f8fc687b722aa0750792667f4f969d89a640e63e30f44044176da16f0b14e6bce3a6b09	153	\\x00000001000001003ae05c61325637c3d88dbb0a64385a1fe7a57aa112d0eab362bcc63ab9f44e7cf1a2799861966ff8653fe03055ceb0a2ab81c8ffd8f4f589ae5918db15fec819bbab4df7c6b3d9c16f9c4c9560ae66d1d4b44648122affe9e14f303fc681c8347f530581de837eaf786af43140e6f61dec982f65a53280393a8cf8cb8fe6506e	\\x6e0294120c8ffa2c73015f856ece7ee2334c54ce02f7836a1aa5d84fb27c3664253096524746bfb3fd80d2121ab3012a6116eef3e66407b8a8a5ea077f4e6acf	\\x00000001000000017eae229da197cab44cfc1c1a69fc206cc23225b464b9bbcd131374e9fa6c89db38096ae753192f43cf4571a676378144f1ba8677ea87ee8c3d7a9a4f5210f5aefa444cf3be4c49f3880408bb60902c622230c6bef66374f8faad5ebaa1195423fda23026755bd7c326c9a3acd8a40bd93a49f6e50626a99f00d8f46c7c08b5c5	\\x0000000100010000
45	2	32	\\x37806c431476bc822e9bec120645e6f9fceaad23f1aca27b9f187a1b94310c81679e614be3d2fa32b5c3330724b232917c03fa5ac58d3f44806f647781d34000	153	\\x00000001000001000cf48483f314d80bfd584dccf9adba34d617b1349a5c89d1757de86be3ead49ffb5774e338192b8c36c32fd0244e6a637b0bd68389bd2612b4c67059fd0569d7861b42ad2152152037e18d646f54786b45a556be3c6cf8f81d22f5fc43c24910edd3d9b2c75280cac2a2264cc9d9c71614192297849c5442eb9e76b06f96f563	\\xab6dbd3810c782a8751521e6d8995b7f5556bf2cc25afebde07998437551e87df322932ff38c324db1bcc6ea2de379487bac2e8f39b4bfac04ea4fdcdb2b57f9	\\x000000010000000183759a6e67d32f3b32f8b1ffac84172e2dc7ec42e9721151e7376e95647732e285dae4b3d38d1664f7a7da9e3c83ffd9796ad51b1feec10209d598ac33f357b28977b9bb9e1096cf9707aa295cac6736558dde912515ba5b744238cbc9217c8df1d2c6d7357cfb54ccfc8ae2ba5ab955b105d0647069fd18aa0178f5aa511ff8	\\x0000000100010000
46	2	33	\\x6fe8700b3380ddc6d9e5a45b74b5904d790004ba2a4752ee561b1fd6cab614b439321a78cc778b36d98c0bd350e5a7dde991c1cee8bc8b16f84415b9f1d97b0f	153	\\x000000010000010039b15b1265e2c1872f75e85f8cbe08e84f4281522d902b9f93d83a2808f4f7542058bec993a8d4cdae075d14c4b94a31daa8b77f0f1e489b56c18ce44d508e3c0fbc0887d09bf5fcd3f8689212181a9c899738df5f9423715f8bc5c32c5eaf38717c208a5b40fa53fff43a2cee37336d5bf10e27468d210be079a9bb606bc03f	\\x7812ae5917f5def11274b2bff4559faafb8b829bbc653b19f1d8f1f1056e778dfd4b685aa5fda1eb00beb280de6b0e307a1700afb3a5041c9c5cf8a46b1adab8	\\x00000001000000017630ef7a75e63a8df33d27cb2f0ec6aebb5b007e3800ac6753d0f59a02fd20e0b1e30e5b72f21dc70f78c4edd52263e3899b5834dae7579c44c8ceefa6162fa6e0174d3d048708c39e81959e2db85c98e3206d484b24685894016884380c5388a005e5f88ce3dc4af961f4fe45e7aa055fb6b1ea4fb12130a70fd18c64e74e5e	\\x0000000100010000
47	2	34	\\x0998bedb935670b6743470889ce307f8f1d52b38795f20d59f45bd33b63a3f0d6c8b56e41c9f45e1769e310e828d99cdbadacf4a62cb6773f94c76bc401e0202	153	\\x0000000100000100527e52fd64230419902c3fb3ee79d7c0271d1fe1187afd5b0ac1e651243f1db1f988f4564416b62417a19530c2e3a93e6fa836dcfedd59783329e330515af0c94595ff9deea41dd45cd23a044eb454b7a75dbf7af5ff62303e167a7ee6e4e4d5f7b6245e76dbc7b7aaa37732179168b15f82dab90ec31d8c2091395324dd7b5f	\\xe3e538a447e4dba036f17d4c218cfe88ec0edf52a2d465ca40ac62b0e16ccda6b5da50e3c6443e4ec53e3a8a01bef45c91366a8aeac14c6e0608c363247bc6e0	\\x00000001000000011b95c5c81802872adbf9b19218651badcef69f163c237bd3270120d058a2a90d15886c805efe189082269fc1c14b0872b96e2b7a6083b4c89f8219e68e0642306ee06885b1b33677cfe912fe90fc803237069b91a5f360cdd03ef8e9d58a8a0f6994da2b05e038abff5b6ffb5503f2092544a3a4bfd7f337f9449cc2ab5e3b59	\\x0000000100010000
48	2	35	\\x84481ad9e7e175e2fd27321b99936c4d0816322ec5ef8219455704cad9900b495fbeb600b06b6d483f11898b2b19ccd8546790eb80e6f8965164c523b00a8a0c	153	\\x00000001000001006594f7fcfc56174479b5ac606c6235f81dd35797e77c784a67b6b0936c6784ab86bd7cf60f0b94525495851cb894481364082d43bab47a24e650d62badd7ee3365ef37f711f9035786c5e031de17f5ae2feef93a87139441b80ea45b695e290c88205818bbc50acd1507d6e75177d7a3beb2bb213943fc84d9c4cdb27f0d0a84	\\xa67daa248bcb0c03ab773b228ca5052977cf3e34c6555e3771f822ca26fac6be532c80b4ff68e475ebd168e93149cb38451154379e584a9127efd0a96457d198	\\x0000000100000001a5b533b6689aa024ee677a12c8b068c53fc206d42066094a064cf4fe220dee14dfc469db497461b19909d98e46beba8a6dbd22f07b4912d7acedfafec9d406844e0c5439ae31958b8f3cdfb77980a507c2d905145c0aa60f97d4193436f78a4edcdc5047bf73d65f2831b6cfde0d40eeca8dec4d54984f298d088af58ffdde2e	\\x0000000100010000
49	2	36	\\xfb6c1f8f240170e0b0dff0f00c5200ae02bb92f24f167fa0af45f511fa3048c727de1d42455f84e5909d711dc8f65f98fdd8d7f9fe7d7f59d5524669325b6c03	153	\\x00000001000001005ad922f9a43d30fe7e84546f203f20cc6970ecde2c187e0054c39da1115fa7b23826cc19c9fefbc53f1b6072dc8e21bb06e057ec784831d4077bd4449232700d5c8651fca9537b18b1fbe4f300f4407ba7baed36ee5bef71de549d2f649b5a27937257fe15d1a0e58e17981608e79c3bb59de50f68dfc9a13b53f55b844bf098	\\x1fb5256ae47d322e0ee28e135be03ad202f29762f6bade3f87e377eda8c4500cf988bfa56ea707b6ff1fbc174ef1c32b4d05366f665569b4843e328685643015	\\x00000001000000010455f26eee5c1881e56b60c1a298f917dc515c5755fda81404df4eaf586876c0ace88d666a40f4e90b1d205ae528e07edda2c0eb831d944be0a922d8aec6cffc4a7b9cf19c9c102e724c54d716d5c3d69032cfaa442f62588d1fea14405f4db8515da479d64d11b2a850632668fb655b0c8133f120d3de2b78564936e04fc53b	\\x0000000100010000
50	2	37	\\xc60a754a6df8059a786ed69a104dfa9481f81703f63c00b660d501328909e91155ee6c1a8d3887d81fb7efcb9d13dd08269fcf893545727f6e0a3cad22b1c60e	153	\\x00000001000001008376e18048e2df0ff1a3e6c38158bbba4dbca6215b5f8c37c584c1a5b93104916be078bad3c33377c772786909502bad075c62ba772a033fcf1ab7339cec216a0f334b4fa354e6c37c66e39697e77586df9a73c5cfc38795acb7bf3906aef3861efe7550223bf0f9f9f168d7544642d2c3a4d9feda903669d4bacb62e56aade8	\\xa7880c447a11e8202e9099b3559ab211097496abc9184bc74830814ea6d06160ec7824b48bdda146c093c0b14e9cd3779f42887fd1ce6917549deff858bd51f0	\\x000000010000000183447f975f4825f60166c0360a6c3b4614ea6ace78b67624490bb6624eedb381b3431bc1f7e6bbe666b9cbfe2408aaba4a6f6c42916ebcc6b7cc54ae47090ebf04f49c9c3d5183365d0e73f16b37156a6ffab9768f27238840a4327f896a9f196530c0c6777a0cab9e6b80eaa84188c62eb3bf3e2f93d81f30e1b44a4e063216	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x58bbc786408a024df65f05a50c28cfa3c0d25b7c0b1738757699a451e47f3a34	\\xffdc78ee159d5c74c67d375bca05971b49c7d9bf91409f75c6b7bfb8f898e26f625689b439b199a3895a0d5c720358f222b869a06dcf0e792fd6a3d1933074a2
2	2	\\x94eb6f4d138ba98e0121cab91a6413fa4fb070acad26cab8a9a00c5e59f4b22f	\\x45f04f292435bacbefc975e4d3f8b21e97d21e4c3a14f821724b5d50e761cc48632410bef8725ba7cf8d65185ca02adb591f5944e6a51053d0fda38cc3b159c9
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, shard, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_close_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close_default (close_uuid, reserve_pub, execution_date, wtid, wire_target_h_payto, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
1	\\xa7bd855aa6b757e9cec7d0c077d14edf828f803d2b7dad88189ae666d519add8	0	0	1650029951000000	1868362753000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xa7bd855aa6b757e9cec7d0c077d14edf828f803d2b7dad88189ae666d519add8	2	8	0	\\x6e61f9b6ae5d7ce6d98bbfa97af2f113a442426e3c8b6ba601dd0ef3f001f799	exchange-account-1	1647610737000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x41d237ad27d9ffd355071ca76a948e163eeb40771f59d7af3c899198784cd02d42379ba54d48228bc9bb7f1bbd9399ec1bb1c3c768b1e2a40b3351a3f35a14fc
1	\\x50531359f309cbc47c0193ce5944de7ef761b86001be4897e8c31698fc537ef05bfed3b2ad88988984547e03e27b9f1ba75d3acaea6cc2b69f412fd4769d60fc
1	\\x1307c8c8719336e38ff30435c28aec6cf5608b46dd5746a2d2ba3c47bfdfa456417fac3f785939227d4bdf1473715918064ef30cb8dd3fdc6dd59cc48c58d531
1	\\xef86f48a4890a3d0ede4356c6414816cfa948bd58e0507f5818b9c23749d2ff3474140c9e6dbc8a873d29d787d57615bd9b0ab19da8201a6570bd3fbe09b2713
1	\\x20e20a8fb8142b4532fa2363a1e0212f739363e6cd71b0f75123a765a565a016da18df206d31686d8db7e81627ed7aa1903c86a09248e4d555c65eb1cb128245
1	\\x67080576db273330542fa98dd88c85c3d64b87828f06e67937cb591517e49adecc98c58cf8f7f246f83064a83a28a05e672eaba8cb7834fa5a9405027b3c8ae7
1	\\x0022baf48fa3fddd6422f5dc2b3ee6abcdad76dce261ddd51692cdf920b497c91a418edf27c69d4dade54876a418c634db7a848378c1e96bb6d45d7498d66444
1	\\x5993715c96b70540b3c78e3b18c48bf5247c5fc04191517bf6b978473333c19b6aa7fe84b4acfa489e4aa2561c91d0bc71638a52d36f1e96553814505e61639d
1	\\x31518bc4f9eea0ca8bb8be33170683ae9cc165f90a25af7f15f7b9a360c83e6f20f53d19d5fde01c7b8dfaa24fe17bf0bc0ef52eb3f1d7111d80e82373fa7a1a
1	\\x618a6a588ecd6826aa4d0004524f1b9d98b85e7afc57685b1f5c8ce40c10100b1e971a5dc10bc538a8630d7cefa74f2200b5ff1bc4fe0ab4d1bdae92475677a2
1	\\x445200e156ecc16f25648618507c8459c0ea68086889631d9d5ec04d21f8ab4da6dbf13980033cc37efa2c81eb844486a9e6633255e486a94e5a34f9e5b659d0
1	\\x4213038babacb3669bc6ebe8ea2277a34c4ef0f4404d2174eb4d0b76da44dbcf6280e01895ab3ac693eadb69996268aee397b81aaf6e9355c8c4726814e5faf6
1	\\xc3d1240c04a9b5489c3e263267c450793bc4f8b93bef0dcbe5db3d6c6ab537817ab029820b247446d41a80738a4bdf7036dadfa210ca8be4f10f782d03c41c06
1	\\xc02764ddb84956463bd8d40d5ea416100e525b5fd5adb1c9913575c4736a9da72075c8aeb02f322cac5b8da35491552664c25023bc52285a3a20c9e8723f43f2
1	\\x82a40205d9668f8ba82bd56ae06ec78be77059ec2a9d52ac5582a3d91f3023bac51648a71f606e0da57a7dec1a4cbefc099328a81d352d457f5a2a5021befe6f
1	\\xaf84f9aa32a27c6e3bfe2b141ac2a5d32b38b324e8f9ae0a0473ffa17df262b5ad811f8b62ed20a248e0fa2b01f0facc0700902e5675590a86f22a28ee472780
1	\\x591e000eaa49dc00604f56c386d3783b85c645446f0fa05b7e0922b7ad91eb073fa8b2d891664a6a46b0afa83fc3294e735f000d760f6cfa94bf4ca2c9fdaec5
1	\\x010a3b76b8e16347b3f5b6e761d93a94ba771ebdef8dc8583513c82217a47041b145d9b1d9d53fbaf452708d4e10bfdd65791fe594942bbf0cb023731b45e19d
1	\\xff1c98d9e04ee5630c9d51de82b07573002edbb53b230da9e32a39775ce7b1227329f697d68fa3bed66c155d35d345cf5ead5eefb529447d72532872e40b4790
1	\\xc29ecae23e1a913a062fde335eacdc39f39e642ffff2d0c89fd4f7ba2de96d456daa10fd1b3bca7da8710a33882471fde2760f341eeed930f19e0331c43c4126
1	\\x4d4ea90120f27363cf6eb1990dd554e8b9b499b24cd78be51784f97f5ffb796e45cbde060a3a4fe06d4930297843738cc3d998f89ee083c16a07a121b3cd0c07
1	\\xef563021fc4588b2ffb73e58fd9e4dab95a348488c65b66925d894a2bf3b949e06eb0756d72254e64353247391b1f5fa11fb94f46c098beb010fa07d38ee5b34
1	\\xc4540a1501fa1b605a5d1948a0571da1949b01c6dec01c76d8ae80dda4f16fe427afae07293c08e8c0c46f5142f4a83cec86736d5724a590fc999480466c7dbd
1	\\x979abd4e307839bdf778adf9d2bdbb1d9e874647afc71daa9b330aecd10bd63fe59399a3dd5d4fe11866458381dcc13bf2e128a608c96e87239b2d8d45220667
1	\\xbe792782d5d39a3b5d75fa8f96b1618f94052b13b7ecbd3b3276271112249cd29dbfee6d5245d4c417fba6b5925b0c4ad6371396c09a46e3c5fa2f7e52091cc2
1	\\x291d6d25ae24afb9f83c23e304e95d6bfa8c93af3847142bb7258af11c4076de51d117729933428788c1eaa38dac069b1e64b642ba4a8c4171ebbef63bac551d
1	\\x980dec05a020824d8c46838341b2a34436f0a6dc618da272cb1c027daf3ea9eb959fc9b3c2f2ba984eff263039b7325a5f3d4c30aaf98942aaf8e03c1f6d0323
1	\\x5b9d6478d508afa9e6b84d192b808e1938af35cbaad9bdf0728f4e4b1e7b8825989eac858f048cf1ed16bc27fd613bbd6ab7c2a8982a5599dcb2ffef441d9b54
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x41d237ad27d9ffd355071ca76a948e163eeb40771f59d7af3c899198784cd02d42379ba54d48228bc9bb7f1bbd9399ec1bb1c3c768b1e2a40b3351a3f35a14fc	217	\\x0000000100000001cd56eac84ff719aba0904c6fdccfa48763c0e24484ffad39e596d68dcc8c75168481a6e5f14a5c5b27f961b1cd5c81ecfbb9d37d47df46d16833aad25d9ca7e3b6ff540f9fb6e26cd645b24420bf39b5768edce255a6d1a74d578ebdb3b5a194fbdef1db4fd9a1398856ae4f02efe8f07a853af9a2d171d6cc94232535d2a3f5	1	\\xca560d27632f8da079b2d1fc0260ba3f7d0e05f2ac1523f73bf609e3f56ce0eab429b28276faca355b6fe221a03cbc0d5162673d7ededa01400860487376940e	1647610741000000	5	1000000
2	\\x50531359f309cbc47c0193ce5944de7ef761b86001be4897e8c31698fc537ef05bfed3b2ad88988984547e03e27b9f1ba75d3acaea6cc2b69f412fd4769d60fc	402	\\x00000001000000011a85a57fa5f34ed436696323ca18d0ae6a21842551843ae50a8b2290ede70c51b31bc76cd13119badc37c0e56950e849237fffd786a559010597629416ef9ec53a2bf7ccb01aef8d903d4e91dbb26ba89b52a0c328908c194c73fa067e31c68924cacbe9777053d02737d62d932351e7dac641b821ede4d5c5c60c81a8b33fed	1	\\x6ecbf4dd6035f646004c657c4a67494396ffd2eaf360dbb94e0c59ff33bdab96b8cb7ed03d901a6e74b7713f20591876bebdc4c5563c9766a198826364f7a602	1647610741000000	2	3000000
3	\\x1307c8c8719336e38ff30435c28aec6cf5608b46dd5746a2d2ba3c47bfdfa456417fac3f785939227d4bdf1473715918064ef30cb8dd3fdc6dd59cc48c58d531	77	\\x00000001000000012823bd0036cceae6f860588e4280e8eb78dd36edfcc680edd4501be1a31a5e7dae2376b52c4ca3f133e6a12e4b250b495dd79132ed59c8354cafbb59196ac04ecf6777b5b3b6e03e78ff8da2887dc349c0e445bec0f0ce9185bce18a4deb1f450dbe8924409e49110b4581a320e7720647db14dd2eded75de10f123dba7e865d	1	\\x2aeb4b70ed8994e7e70e65e8cb3bf4dbb842da29216b04286a7993951b08b1c6985cae2186bf8b012c4d33b746537a3cf2867168fd66f9b1f5f4f2e7481a8c0e	1647610741000000	0	11000000
4	\\xef86f48a4890a3d0ede4356c6414816cfa948bd58e0507f5818b9c23749d2ff3474140c9e6dbc8a873d29d787d57615bd9b0ab19da8201a6570bd3fbe09b2713	77	\\x00000001000000014aae4363d7ae2610593e5d123b660a4b240e9ff1abecaa495d678cfa94cabffd7c1ef6e668915e64b6b9c1c34cb4a96b497937928bc5fe9ce787d2f8f85f0f747c6994d61656f0e2cbbf3f051109389ef8a02baf8c066d20744b170f1d233086d5bb801815b705d3b59c4d3f055d19ca914cbf25a25661f0fd7670babbf75079	1	\\x02347174769bb819c51a45dfe11d2c7d323158c9cbb7e9bb9e17dbd45c89d4f19a798d5beb07afc48817cc2937f5ff0f922385b83b423ca9a019628b71c7a105	1647610741000000	0	11000000
5	\\x20e20a8fb8142b4532fa2363a1e0212f739363e6cd71b0f75123a765a565a016da18df206d31686d8db7e81627ed7aa1903c86a09248e4d555c65eb1cb128245	77	\\x000000010000000132a7bd56144a394e41c5d8bd6492b0e8d56edf48d5e17be777be8e2b02e28610bca47f5c78a6ea718cd36eacd115ba0aeeedad8a43f4436ca50562493ae28bcffd7e588182fce3293ce9c401f2ffb83c844f4843119127e794791fba2cc566a06fec4d4faffee181a3800eb627eced64c124d98f5330332ebf89d223b7f66596	1	\\x8659008a3e03776ac86190d9cb2011c760389387a4715ee8a6a17ff2fb595b2d95e3b97d187e573f7bc00373a23db19bbcd78d56b2fed4140167999b69d2dd0a	1647610741000000	0	11000000
6	\\x67080576db273330542fa98dd88c85c3d64b87828f06e67937cb591517e49adecc98c58cf8f7f246f83064a83a28a05e672eaba8cb7834fa5a9405027b3c8ae7	77	\\x00000001000000019759e98258a0aad40fa55f80c2b30784ee4f164d8d2e1a155adaca3be9bc1a51a9ff33bc7c3c279472938d15ac67aa75865824f26e4dcc624f6b4597a23a731bebee0d703d8a88bd700b928e0ef31834eb4bfd326dfdd047dd88c755f25c727b1a8672b02b1f9c775290ab5d1eb9f31c231a4e1cee77e3a6006083f0b2ef8038	1	\\x8ee921e4f59a6ca16e95e292e82f0cfe7bcea38fcdf3a397770a1591a8b910f6de10618b165d64f448fe057497cf5875a7abe051a65d1407d7179caf35db7d0d	1647610741000000	0	11000000
7	\\x0022baf48fa3fddd6422f5dc2b3ee6abcdad76dce261ddd51692cdf920b497c91a418edf27c69d4dade54876a418c634db7a848378c1e96bb6d45d7498d66444	77	\\x00000001000000010aa51cda1d15b9b20514c6147eb99f97d282fb9a1933d70e00e20cdeb90f82f37a48624e72bf8dde18a57599446c120231424ed12720a3cbc93928a79bb0c5f04b71445e382109a225eb8b7fe1a73389899f6ceae5181b565ea39126aec3bc5ff157f405e1c04f25294e7a3feed7df4c624cc529a8bf66cffd58878b996b0100	1	\\x557a84ed86a48998b2a54ba14c3d1eac66b80433f3d8682ae505d521a6f49e593a9e3a474c24fa0f108d0974831647a4c0479d825fda5ec243e53fb9f9df7f09	1647610741000000	0	11000000
8	\\x5993715c96b70540b3c78e3b18c48bf5247c5fc04191517bf6b978473333c19b6aa7fe84b4acfa489e4aa2561c91d0bc71638a52d36f1e96553814505e61639d	77	\\x0000000100000001501bd6b40512f2d571835aa2e9b7154b5107a5459e314a12f7e71f9e1f23b9e0d943793539ffdeaa9bb7199943d6216c6f311072ce21a8cb710833395f5d652ea5478e66ff9af636dc6460a79f4d5fa23896925b3dfde4624a8e7ad2036a859ef317b45ad45929477046c3e84580ef957435f3ccb47ab1e3a04129ef2b1fb4e7	1	\\xe5a102318a6cd5049c238fe20d37f88294576b064608a050638be24ca9cd2f023347b97dcb063821ce252e5f04f881926e93b63c503e161198cf7aafcfb2f601	1647610741000000	0	11000000
9	\\x31518bc4f9eea0ca8bb8be33170683ae9cc165f90a25af7f15f7b9a360c83e6f20f53d19d5fde01c7b8dfaa24fe17bf0bc0ef52eb3f1d7111d80e82373fa7a1a	77	\\x0000000100000001dc79bbfa53fd4433e207403e7fad1fe9c2387440a72120c077bcd0c27500a29d762228ae40e8e8cdf7cda90326ebdb7b752f81eaa5bc11881bda77517d6422796194353f774a589dfe5999e5f597efc1fed5b1be69007aa74659438f4d47427ba618babfc8344925f772c61d601d589f9007365538652ee31e5d598fc78d1c89	1	\\xe188707750d29a5a77cead81a75c202147e6312437f2806c414146391fd855ba5c4f4d39e7458d0c6b62fb070ffc7ca1d550f2f3584c5cdec05033c73d515505	1647610741000000	0	11000000
10	\\x618a6a588ecd6826aa4d0004524f1b9d98b85e7afc57685b1f5c8ce40c10100b1e971a5dc10bc538a8630d7cefa74f2200b5ff1bc4fe0ab4d1bdae92475677a2	77	\\x0000000100000001e4b568a3d66f450b3cf1cba50524592a08580c7eca3898b1f77cb5df408818bcdc4667ec41f53d5a72e5303d517d9fe24a48b87cce8761243bf1a9e5c0f6233767f19bbfa418b1bea9025a13862519a73142efa58b336deff5f865c2e970541fcb230817206b1dce58ffa810d63f574269bce780fa8f3699932493ce1e1008a4	1	\\xb76ad55e427df11db37c6f7d94caebcbdef1066f6b7f70d131155029b5f0b49c8a2efc8f195cfcdbf62eb840294c958818cdcf210dba79ed5ca9d62a0e58f703	1647610741000000	0	11000000
11	\\x445200e156ecc16f25648618507c8459c0ea68086889631d9d5ec04d21f8ab4da6dbf13980033cc37efa2c81eb844486a9e6633255e486a94e5a34f9e5b659d0	115	\\x00000001000000018fffff6863c42a9f1a69cdc88f657b66d244ef598a0cf8ef279d53b2d1c7c0feafd72221d08fd84f58fa6d48b609a1afac2c923fe646b5dfe8c7c9fa4b07f7ea2fe4239ff37079e490b2f678b4bccbcea7179126ec2b70f6ade4eabc683f8f84583e0d6133124af55adf75519bb4e502af7d22f3a06154164265dc149c589f7c	1	\\xbd5dcf6a3ba9af5cf37a0b44997408c95e770a1e675c88fea43ddfc079ae25d955d03c1d0b7291b94d377d2937dfe3d68c4d9f835301d5b732c06790d8c9c900	1647610741000000	0	2000000
12	\\x4213038babacb3669bc6ebe8ea2277a34c4ef0f4404d2174eb4d0b76da44dbcf6280e01895ab3ac693eadb69996268aee397b81aaf6e9355c8c4726814e5faf6	115	\\x000000010000000129b4c27f7207fb448dd0d2b06d7279e253942ae2c507e1864e71cd771816a09cce6ae66a61701a94849f58f335a4066ea9f2bd9d54443c70ee54e86977d48498b3680c9eff7c730e0425e3865cd316e7a1a441aaa33063f57c5b796576d5b4157f471b552ecdb4af011f7de3afc6d432332d141ab0674429c70358187f74c29b	1	\\x35afe76695b0d1ce0cb59b7969c3b7290eb639def8ad512683b1f3d25457d71194dbd80ed4d461a1612af6d396723a1f1b2d0fc497c8e142e8b91fb324d3fc06	1647610741000000	0	2000000
13	\\xc3d1240c04a9b5489c3e263267c450793bc4f8b93bef0dcbe5db3d6c6ab537817ab029820b247446d41a80738a4bdf7036dadfa210ca8be4f10f782d03c41c06	115	\\x0000000100000001a85da29977152f631985cd02dac0b140272176137acddecd3778b23a4282dc6bc1d3fdf58f93b47364d4325965ee3de875ae1269529fd20f9f5d25fbd96b98839f9040364bd4b9220f60ccac3db65dc427fc4f35dbf76d70ccd126dc1b4d72f25f90ed2366ae1234b423eec596ed3ecdf8b26aea63ac854901742cdb3ff82aa9	1	\\x07c6406aa6ff90095c201ac18c0776addaabceac028bdeb3e43082c810055e177071bcb9b53a2612445a86bc900ebf5f91aee7af3bf0b115c210fb955c7d6503	1647610741000000	0	2000000
14	\\xc02764ddb84956463bd8d40d5ea416100e525b5fd5adb1c9913575c4736a9da72075c8aeb02f322cac5b8da35491552664c25023bc52285a3a20c9e8723f43f2	115	\\x0000000100000001627c6e201ed4e94edae5d22dbb2cd18202e1725926f722d012b726c60f3e1916c88a9c324c8877e11e2d998a30bab1aeb8520dd47ad16fce22a3b37568279458efc82af419579b755514c8750621cb14427f4d5c9bb1659b111a593de30096fa9480e829894300e6eba8602641a10b4d50c2f30a40481188ffa0635e1edb504d	1	\\xabed989b3631c27522bfd8405c9ec7038a7a35f89f770ebf708ac201e7c6af162f364d8078fd7849eb6c067ba1bcda1ce2e59656a2c3ac5a05f4deb35e89be06	1647610741000000	0	2000000
15	\\x82a40205d9668f8ba82bd56ae06ec78be77059ec2a9d52ac5582a3d91f3023bac51648a71f606e0da57a7dec1a4cbefc099328a81d352d457f5a2a5021befe6f	185	\\x00000001000000013d4aaf820148b4ebb72c8bdba95b342ba9f3c1ab69f86c3cf5f6eb8d5b3ac2e5fdab530418c62f36ab64409e4ad523854742c2c4ab7ebe529f428a583adabd71191b88eeae6f22ffd273cf292272dfef2010800b92fd48dbeea3cf46a104a9f8d35b264a0038309b7e4743d211e0ca40152ae7f670b75a3679dcde4ddc0e3d14	1	\\x53be2e8bf90d81713468cc38e5ef5146784da7dfaacbc7d7ef593387679c94722cd61292893eb7152d4d3332014b97e0c74a375f95494899356a6496f703370e	1647610752000000	1	2000000
16	\\xaf84f9aa32a27c6e3bfe2b141ac2a5d32b38b324e8f9ae0a0473ffa17df262b5ad811f8b62ed20a248e0fa2b01f0facc0700902e5675590a86f22a28ee472780	77	\\x0000000100000001a829ff1c6ef313e8cc2494facbfdfe962e122cbe8a7925cc2994bffcc3ee4f3b098fbc22df896dd438de283260e122fad2aa61814f5b51cfc88ea9184b177fb3fe2ba63eaa45dc847ff48b80af92b4327f46b54535e5944d580c8cbe7656e513e667348d059329a7374a0348ce9ed0e6284f6195ff8c477013d60f3face107da	1	\\xe5491d3c153ed61900e614b0abc8170a8ee522e00fbedb8f8d612e607380b24421b6b232ff4bd3e57fa198d5f06f66ca421f3bbd3e32991de3f0caadd7d8220b	1647610752000000	0	11000000
17	\\x591e000eaa49dc00604f56c386d3783b85c645446f0fa05b7e0922b7ad91eb073fa8b2d891664a6a46b0afa83fc3294e735f000d760f6cfa94bf4ca2c9fdaec5	77	\\x0000000100000001b4a15088570d3a6dae589e90e70afc45c954010a83284106cf7987d43d8624fc35cc78ce77ab9d0855b4eb0f34d75158c00382f4afd3268f035bd055f116c6a84f906917a7e6272853545f6d2514416e869d42e5ea1437744b9756d0e7205570c4dc9e9d85821629d823b660bfb09b4615a750db7d5d670136e95ab2aa4b2ee6	1	\\x575418c936c59535fb7781608dee10c6ffd2d43e33cb7036adf3231809c291eca0691e7c386e6b17fcf1b41a0e5010723c65ffbe1453bc14631ee342b6fd7c0a	1647610752000000	0	11000000
18	\\x010a3b76b8e16347b3f5b6e761d93a94ba771ebdef8dc8583513c82217a47041b145d9b1d9d53fbaf452708d4e10bfdd65791fe594942bbf0cb023731b45e19d	77	\\x000000010000000121b2534426e62a8a8c3f38bf3b89def4bd802317d791910063f694b0ccc5c66161ab60fbb335290c507bc9599d81c708b7399bfbbac667284bf4b4dad5a07e24bfaa11a73dea9e12c2ab61ff02ac37076c825d3a03622633f69bf35143c92de54200028d5fe7ab62389f3c509e416b8722acd857a25bdd59a611d11fb783b9b9	1	\\xff3798a6597e9b3c8cef9e59599f165ab46e6e7ac0cb02aa7fbdd618441455cea6ca40e35a7a13975cd8be1241fe0588b62ecd5a84b03a8b1e1901dbc691d70b	1647610752000000	0	11000000
19	\\xff1c98d9e04ee5630c9d51de82b07573002edbb53b230da9e32a39775ce7b1227329f697d68fa3bed66c155d35d345cf5ead5eefb529447d72532872e40b4790	77	\\x000000010000000196c22fc9f4e93d30cfeb9f3f4b455a6a2351fa1befa56b0e40b716d888e1f3fee94243fe6c831c2cb864061723d1fb4d81e8b9ce6ba3520db6b4301f523c744b1f15127eff9e30212642dbd56aa1ca33391dea884beba879c7b106f033dda1f6a1bf2ea304402e9f7695401760cf2454b373eb94c076b07eea4dd8b36107fc52	1	\\x2b97258c46b76f83d424cac3b65b54e7cbd15ed1f0f72b471076b184a321b0573aedb1bda83e14afd0b29db510ab6c4dbaf45c436aa7bba07557311ae1106c06	1647610753000000	0	11000000
20	\\xc29ecae23e1a913a062fde335eacdc39f39e642ffff2d0c89fd4f7ba2de96d456daa10fd1b3bca7da8710a33882471fde2760f341eeed930f19e0331c43c4126	77	\\x00000001000000016dd591d31c3dd132dcea812b0a3a6dd6252a033173788886e41c5502f1d72fb25647a03e6b91786f403a5f0a58e4d43c9d63bca1d984ef5e27f1bc005d867d64bd655b6f4869e161498324e0c37a2c4327738ff476ba28d4480aa408b89329d72ac53f0dddd67b50bc59ddc7fbd497e81d3af52615703c5d7fe5975eee74c56b	1	\\xfc05ba1ddbc69371625f732b4dab5c5a75b65dd8884c35d3f85174f7fc4d5daa334e48b226c9167680a314332fc7c34326745fb03818893f50e924ffa24e9a03	1647610753000000	0	11000000
21	\\x4d4ea90120f27363cf6eb1990dd554e8b9b499b24cd78be51784f97f5ffb796e45cbde060a3a4fe06d4930297843738cc3d998f89ee083c16a07a121b3cd0c07	77	\\x0000000100000001338d98b05e3f58ed6df7aa539ecf855db4440a69dcda9fcfc9d1fb6b987f0a475ded0ee402a9b25a9b3322cc5f5f0c930d69253c77d5611dcea1bac6119b6aa9a13029bb306aaed90f9f9556c3c35976fa54c6a1b53b520b4595e423c357f2fec483488b08e31582b6d8241a28ced1ba371c3e17d213a7ee271c824c0c9b8a7e	1	\\x4426d6e425948b7660373d5fdf153881f8ee93f76a2ebd24b2561e2d02efc4effeb193b26fc400e77e4d68eaa69c1e0f012d672c4a8eb877c4799e91f8e6be01	1647610753000000	0	11000000
22	\\xef563021fc4588b2ffb73e58fd9e4dab95a348488c65b66925d894a2bf3b949e06eb0756d72254e64353247391b1f5fa11fb94f46c098beb010fa07d38ee5b34	77	\\x0000000100000001ac5875a06b9b5d48fbdedfd81922d61bed7e2c17d875d57595c2ddadedeefdc1177786fb467af32a3ef8b26419d8b56c91ba98120c1573949d568fda634d73c6b139642fa4edc68b227714e3fc0c402c1d9de61df090e43ac94ec5ffb948d69772bcf5abe2ef01a9cbe46a3ba65d42fd75c471171957d95d03c013dae2989b9e	1	\\x9e2c2b095be9310156d3ae1466969bb986b3fb6524e350417443edefda810dd0d7dcf2a9f5fc919b7a87bb46a40bbf1bc57f98dd5638b0bfc4a7b28191d99104	1647610753000000	0	11000000
23	\\xc4540a1501fa1b605a5d1948a0571da1949b01c6dec01c76d8ae80dda4f16fe427afae07293c08e8c0c46f5142f4a83cec86736d5724a590fc999480466c7dbd	77	\\x0000000100000001055cfaa132ee0581014bcb54648c149e77b6b811033a8e17a0cabee8f85e446cbf6e4c043ab0c72f90db01572cbc0556669bbf87e798545090ec52062bb5706a59c3663638197bd19bb63814e7bbd03da834ac742f2cb5a5443616126867afb04ef5783d87bccdb0dd9ff1c9833d5ae1bc6b0bcfe98d1909837700b2d6dbd90c	1	\\x975d80e92c796e64f032a3b4372ecaabec3a19f828d77fbb4768697a061e7b64488907f873b03464c24179f7b3bcbb76f7cd0dc8cea6827ba05aedee87430f08	1647610753000000	0	11000000
24	\\x979abd4e307839bdf778adf9d2bdbb1d9e874647afc71daa9b330aecd10bd63fe59399a3dd5d4fe11866458381dcc13bf2e128a608c96e87239b2d8d45220667	115	\\x0000000100000001011a2c4c6bec26ad05e4e3e6bc91d3fefd461235762e53d4355b0f3b6f9507fc97fa9d655f116e53bcd5d8f5722d961cd4176e46ea3ff3e2a55484a3a3e93d2aa9961e3bc905bb42b79786dbbcddf747b7d8f884899d3c5c5fab25cb8b574e309d3f48decf8b938be2ddea31d0513d7bb7cc8c9b7f87d2d6716645453d4af075	1	\\x99d41441e908c3d54540bcd5c48ee9c8e10b4867e48ad3d4cf739d0986ae1f898d165d538bf9510bdcd8c80bce2e84ad6c6cad31305444a7923a138ac4b9d30d	1647610753000000	0	2000000
25	\\xbe792782d5d39a3b5d75fa8f96b1618f94052b13b7ecbd3b3276271112249cd29dbfee6d5245d4c417fba6b5925b0c4ad6371396c09a46e3c5fa2f7e52091cc2	115	\\x00000001000000014354deccd3bd530aa8a6069baeaff4700056fb9acf7dec028006bfa18c429cff719c55a3cadc5fec10df8f5e6215463e2a5177f1efd532470383768f027421b79485e4845de10394eddb77ab165eee6804f0fcd872ef94ea62f1a530cacfbfed69594892652a65fa75ac100961465664225af4b0019901a1290331039cf8c2c9	1	\\x8cb44cd0c9220da994b01d73a5b292cc5325126822990345c1ab289b1c9e45ce2f7a14c02b1b3b05c97a618d16cc0cfbe9f9e1cd9ea010a9247d92779e784306	1647610753000000	0	2000000
26	\\x291d6d25ae24afb9f83c23e304e95d6bfa8c93af3847142bb7258af11c4076de51d117729933428788c1eaa38dac069b1e64b642ba4a8c4171ebbef63bac551d	115	\\x0000000100000001b1c0134c04ddf993f4a3334a505c130823f47d68fba2d1e450f111da3e9f16e98c8131d430392420655ae238d7d833b35f0db1ec53a5065a29fc524c21afe0dfeaec514937762c4ffa974c3ff9ee2013b070fd16edd32a10e92275a4360603bbd5b07fbb9ceee7b6ea1c077897b39fdf12ec78fa6aced7d5c8de9c7d77f73032	1	\\x964ecb7d8db6dc0be2df348d54e2e67ce380e8600cf13e36c053769d9c2989ef9df09c98be7d5a4ab8e81a975c23da3d2ff454475da57fc54c71540c7b447a05	1647610753000000	0	2000000
27	\\x980dec05a020824d8c46838341b2a34436f0a6dc618da272cb1c027daf3ea9eb959fc9b3c2f2ba984eff263039b7325a5f3d4c30aaf98942aaf8e03c1f6d0323	115	\\x000000010000000178bb0a3c6d2c720eea693b97125346ab2a55b0e3b7f69dc3093a1934cc98133c8573ebf116dadf5434e58ff2aa3549e866dba3c8886165441009e177d83d747abf2ea404afef0136a48ff0aa1f5f233fd04f3eac98783d1e8cc1d33c9d9a771ec3930fe8cdff96fd7475efc9843dedb4acdd26d3a9496df8e8b64f5d93818dfd	1	\\xc6ca2a917d1ea50a52566a264c028dce47d6071ca4421d800daa5fbf5063d73a2b70ead408deef3d57a7a0e4158bdd06e61bd4d8c7f820922981f559f837b602	1647610753000000	0	2000000
28	\\x5b9d6478d508afa9e6b84d192b808e1938af35cbaad9bdf0728f4e4b1e7b8825989eac858f048cf1ed16bc27fd613bbd6ab7c2a8982a5599dcb2ffef441d9b54	115	\\x00000001000000018dffa7ab7dabe53c946dd79dc00cb3f1ff6ece16c2cedfcc9bb80cd6dbc67fb09bf67bc27e7bbde3b5961c450a75deb96a712ead0939236ea138d234745aa36d95a69a9596cc063e5a4b0ca92796d35e68d3f2eb23a3142b420a9d980bd7c02534564623d1012c09303e393b862e22479365cfa4d2faf0bb1511657c1b0925db	1	\\x9464d857ba42a359d1e95489a1588f5f5112ee4c7e6df860ffc7ee7b4f65fa6467eb7ce1b89693810f2ac09e4ff9d52ef1d8d129e13cfb9bf5f939086cc0d309	1647610753000000	0	2000000
\.


--
-- Data for Name: revolving_work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.revolving_work_shards (shard_serial_id, last_attempt, start_row, end_row, active, job_name) FROM stdin;
\.


--
-- Data for Name: signkey_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.signkey_revocations (signkey_revocations_serial_id, esk_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: wire_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_accounts (payto_uri, master_sig, is_active, last_change) FROM stdin;
payto://x-taler-bank/localhost/Exchange	\\x91b05c7942766b5b10725cf8334075e9689e810e3fbc5da90de54e37b35277b962f1704e579f7528a3dff8b3ce26ff5e966543802b6333294e6f68a4100f8b0f	t	1647610731000000
\.


--
-- Data for Name: wire_auditor_account_progress; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_auditor_account_progress (master_pub, account_name, last_wire_reserve_in_serial_id, last_wire_wire_out_serial_id, wire_in_off, wire_out_off) FROM stdin;
\.


--
-- Data for Name: wire_auditor_progress; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_auditor_progress (master_pub, last_timestamp, last_reserve_close_uuid) FROM stdin;
\.


--
-- Data for Name: wire_fee; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xcbe1fcc586af7cf029aa75a06091e44ae55497510b6d8c1d41a8c6d26e48d7e7030e117bb1bd65d65abc34acd726af19d77daffaef7cd5290dc0bc5549fd5c01
\.


--
-- Data for Name: wire_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_out_default (wireout_uuid, execution_date, wtid_raw, wire_target_h_payto, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: wire_targets_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_targets_default (wire_target_serial_id, wire_target_h_payto, payto_uri, kyc_ok, external_id) FROM stdin;
1	\\x6e61f9b6ae5d7ce6d98bbfa97af2f113a442426e3c8b6ba601dd0ef3f001f799	payto://x-taler-bank/localhost/testuser-dv00rngs	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647610723000000	0	1024	f	wirewatch-exchange-account-1
\.


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.aggregation_tracking_aggregation_serial_id_seq', 1, false);


--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 12, true);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 2, true);


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_denom_sigs_auditor_denom_serial_seq', 1269, true);


--
-- Name: auditor_reserves_auditor_reserves_rowid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_reserves_auditor_reserves_rowid_seq', 1, false);


--
-- Name: auditors_auditor_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditors_auditor_uuid_seq', 1, true);


--
-- Name: auth_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_group_id_seq', 1, false);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_group_permissions_id_seq', 1, false);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_permission_id_seq', 32, true);


--
-- Name: auth_user_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_user_groups_id_seq', 1, false);


--
-- Name: auth_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_user_id_seq', 12, true);


--
-- Name: auth_user_user_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auth_user_user_permissions_id_seq', 1, false);


--
-- Name: cs_nonce_locks_cs_nonce_lock_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.cs_nonce_locks_cs_nonce_lock_serial_id_seq', 1, false);


--
-- Name: denomination_revocations_denom_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 2, true);


--
-- Name: denominations_denominations_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.denominations_denominations_serial_seq', 424, true);


--
-- Name: deposit_confirmations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposit_confirmations_serial_id_seq', 3, true);


--
-- Name: deposits_deposit_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.deposits_deposit_serial_id_seq', 3, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 8, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 16, true);


--
-- Name: exchange_sign_keys_esk_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.exchange_sign_keys_esk_serial_seq', 5, true);


--
-- Name: extension_details_extension_details_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.extension_details_extension_details_serial_id_seq', 1, false);


--
-- Name: extensions_extension_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.extensions_extension_id_seq', 1, false);


--
-- Name: global_fee_global_fee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.global_fee_global_fee_serial_seq', 1, true);


--
-- Name: known_coins_known_coin_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 14, true);


--
-- Name: merchant_accounts_account_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_accounts_account_serial_seq', 1, true);


--
-- Name: merchant_deposits_deposit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_deposits_deposit_serial_seq', 3, true);


--
-- Name: merchant_exchange_signing_keys_signkey_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 10, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 2, true);


--
-- Name: merchant_instances_merchant_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_instances_merchant_serial_seq', 1, true);


--
-- Name: merchant_inventory_product_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_inventory_product_serial_seq', 1, false);


--
-- Name: merchant_kyc_kyc_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_kyc_kyc_serial_id_seq', 1, true);


--
-- Name: merchant_orders_order_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_orders_order_serial_seq', 2, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_refund_serial_seq', 1, false);


--
-- Name: merchant_tip_pickups_pickup_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tip_pickups_pickup_serial_seq', 1, false);


--
-- Name: merchant_tip_reserves_reserve_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tip_reserves_reserve_serial_seq', 1, false);


--
-- Name: merchant_tips_tip_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_tips_tip_serial_seq', 1, false);


--
-- Name: merchant_transfers_credit_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_transfers_credit_serial_seq', 1, false);


--
-- Name: prewire_prewire_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.prewire_prewire_uuid_seq', 1, false);


--
-- Name: recoup_recoup_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_recoup_uuid_seq', 1, true);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 8, true);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 2, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_revealed_coins_rrc_serial_seq', 50, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_transfer_keys_rtc_serial_seq', 2, true);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refunds_refund_serial_id_seq', 1, false);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 1, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 28, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 1, true);


--
-- Name: revolving_work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.revolving_work_shards_shard_serial_id_seq', 1, false);


--
-- Name: signkey_revocations_signkey_revocations_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.signkey_revocations_signkey_revocations_serial_id_seq', 1, false);


--
-- Name: wire_fee_wire_fee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_fee_wire_fee_serial_seq', 1, true);


--
-- Name: wire_out_wireout_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_out_wireout_uuid_seq', 1, false);


--
-- Name: wire_targets_wire_target_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.wire_targets_wire_target_serial_id_seq', 4, true);


--
-- Name: work_shards_shard_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.work_shards_shard_serial_id_seq', 1, true);


--
-- Name: patches patches_pkey; Type: CONSTRAINT; Schema: _v; Owner: -
--

ALTER TABLE ONLY _v.patches
    ADD CONSTRAINT patches_pkey PRIMARY KEY (patch_name);


--
-- Name: aggregation_tracking_default aggregation_tracking_default_aggregation_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking_default
    ADD CONSTRAINT aggregation_tracking_default_aggregation_serial_id_key UNIQUE (aggregation_serial_id);


--
-- Name: aggregation_tracking aggregation_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking
    ADD CONSTRAINT aggregation_tracking_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: aggregation_tracking_default aggregation_tracking_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aggregation_tracking_default
    ADD CONSTRAINT aggregation_tracking_default_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: app_bankaccount app_bankaccount_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_pkey PRIMARY KEY (account_no);


--
-- Name: app_bankaccount app_bankaccount_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_user_id_key UNIQUE (user_id);


--
-- Name: app_banktransaction app_banktransaction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_pkey PRIMARY KEY (id);


--
-- Name: app_banktransaction app_banktransaction_request_uid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_request_uid_key UNIQUE (request_uid);


--
-- Name: app_talerwithdrawoperation app_talerwithdrawoperation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawoperation_pkey PRIMARY KEY (withdraw_id);


--
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_denom_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_denom_serial_key UNIQUE (auditor_denom_serial);


--
-- Name: auditor_denom_sigs auditor_denom_sigs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_pkey PRIMARY KEY (denominations_serial, auditor_uuid);


--
-- Name: auditor_denomination_pending auditor_denomination_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denomination_pending
    ADD CONSTRAINT auditor_denomination_pending_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_exchanges auditor_exchanges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_exchanges
    ADD CONSTRAINT auditor_exchanges_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_historic_denomination_revenue auditor_historic_denomination_revenue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_historic_denomination_revenue
    ADD CONSTRAINT auditor_historic_denomination_revenue_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: auditor_progress_aggregation auditor_progress_aggregation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_aggregation
    ADD CONSTRAINT auditor_progress_aggregation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_coin auditor_progress_coin_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_coin
    ADD CONSTRAINT auditor_progress_coin_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_deposit_confirmation auditor_progress_deposit_confirmation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_deposit_confirmation
    ADD CONSTRAINT auditor_progress_deposit_confirmation_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_progress_reserve auditor_progress_reserve_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_reserve
    ADD CONSTRAINT auditor_progress_reserve_pkey PRIMARY KEY (master_pub);


--
-- Name: auditor_reserves auditor_reserves_auditor_reserves_rowid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT auditor_reserves_auditor_reserves_rowid_key UNIQUE (auditor_reserves_rowid);


--
-- Name: auditors auditors_auditor_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditors
    ADD CONSTRAINT auditors_auditor_uuid_key UNIQUE (auditor_uuid);


--
-- Name: auditors auditors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditors
    ADD CONSTRAINT auditors_pkey PRIMARY KEY (auditor_pub);


--
-- Name: auth_group auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions auth_group_permissions_group_id_permission_id_0cd325b0_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission auth_permission_content_type_id_codename_01ab375a_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq UNIQUE (content_type_id, codename);


--
-- Name: auth_permission auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_pkey PRIMARY KEY (id);


--
-- Name: auth_user_groups auth_user_groups_user_id_group_id_94350c0c_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_group_id_94350c0c_uniq UNIQUE (user_id, group_id);


--
-- Name: auth_user auth_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_permission_id_14a6b632_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_permission_id_14a6b632_uniq UNIQUE (user_id, permission_id);


--
-- Name: auth_user auth_user_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_username_key UNIQUE (username);


--
-- Name: cs_nonce_locks_default cs_nonce_locks_default_cs_nonce_lock_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cs_nonce_locks_default
    ADD CONSTRAINT cs_nonce_locks_default_cs_nonce_lock_serial_id_key UNIQUE (cs_nonce_lock_serial_id);


--
-- Name: cs_nonce_locks cs_nonce_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cs_nonce_locks
    ADD CONSTRAINT cs_nonce_locks_pkey PRIMARY KEY (nonce);


--
-- Name: cs_nonce_locks_default cs_nonce_locks_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cs_nonce_locks_default
    ADD CONSTRAINT cs_nonce_locks_default_pkey PRIMARY KEY (nonce);


--
-- Name: denomination_revocations denomination_revocations_denom_revocations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denom_revocations_serial_id_key UNIQUE (denom_revocations_serial_id);


--
-- Name: denomination_revocations denomination_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_pkey PRIMARY KEY (denominations_serial);


--
-- Name: denominations denominations_denominations_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denominations
    ADD CONSTRAINT denominations_denominations_serial_key UNIQUE (denominations_serial);


--
-- Name: denominations denominations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denominations
    ADD CONSTRAINT denominations_pkey PRIMARY KEY (denom_pub_hash);


--
-- Name: deposit_confirmations deposit_confirmations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_pkey PRIMARY KEY (h_contract_terms, h_wire, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig);


--
-- Name: deposit_confirmations deposit_confirmations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT deposit_confirmations_serial_id_key UNIQUE (serial_id);


--
-- Name: deposits_default deposits_default_deposit_serial_id_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits_default
    ADD CONSTRAINT deposits_default_deposit_serial_id_pkey PRIMARY KEY (deposit_serial_id);


--
-- Name: deposits deposits_shard_coin_pub_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_shard_coin_pub_merchant_pub_h_contract_terms_key UNIQUE (shard, coin_pub, merchant_pub, h_contract_terms);


--
-- Name: deposits_default deposits_default_shard_coin_pub_merchant_pub_h_contract_ter_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits_default
    ADD CONSTRAINT deposits_default_shard_coin_pub_merchant_pub_h_contract_ter_key UNIQUE (shard, coin_pub, merchant_pub, h_contract_terms);


--
-- Name: django_content_type django_content_type_app_label_model_76bd3d3b_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: exchange_sign_keys exchange_sign_keys_esk_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_esk_serial_key UNIQUE (esk_serial);


--
-- Name: exchange_sign_keys exchange_sign_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_sign_keys
    ADD CONSTRAINT exchange_sign_keys_pkey PRIMARY KEY (exchange_pub);


--
-- Name: extension_details extension_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extension_details
    ADD CONSTRAINT extension_details_pkey PRIMARY KEY (extension_details_serial_id);


--
-- Name: extensions extensions_extension_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extensions
    ADD CONSTRAINT extensions_extension_id_key UNIQUE (extension_id);


--
-- Name: extensions extensions_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extensions
    ADD CONSTRAINT extensions_name_key UNIQUE (name);


--
-- Name: global_fee global_fee_global_fee_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.global_fee
    ADD CONSTRAINT global_fee_global_fee_serial_key UNIQUE (global_fee_serial);


--
-- Name: global_fee global_fee_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.global_fee
    ADD CONSTRAINT global_fee_pkey PRIMARY KEY (start_date);


--
-- Name: known_coins known_coins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins
    ADD CONSTRAINT known_coins_pkey PRIMARY KEY (coin_pub);


--
-- Name: known_coins_default known_coins_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins_default
    ADD CONSTRAINT known_coins_default_pkey PRIMARY KEY (coin_pub);


--
-- Name: known_coins_default known_coins_defaultk_nown_coin_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins_default
    ADD CONSTRAINT known_coins_defaultk_nown_coin_id_key UNIQUE (known_coin_id);


--
-- Name: merchant_accounts merchant_accounts_h_wire_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_h_wire_key UNIQUE (h_wire);


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_payto_uri_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_payto_uri_key UNIQUE (merchant_serial, payto_uri);


--
-- Name: merchant_accounts merchant_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_pkey PRIMARY KEY (account_serial);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_h_contract_terms_key UNIQUE (merchant_serial, h_contract_terms);


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_contract_terms merchant_contract_terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_credit_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_credit_serial_key UNIQUE (deposit_serial, credit_serial);


--
-- Name: merchant_deposits merchant_deposits_order_serial_coin_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_coin_pub_key UNIQUE (order_serial, coin_pub);


--
-- Name: merchant_deposits merchant_deposits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_pkey PRIMARY KEY (deposit_serial);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_key_exchange_pub_start_date_maste_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_key_exchange_pub_start_date_maste_key UNIQUE (exchange_pub, start_date, master_pub);


--
-- Name: merchant_exchange_signing_keys merchant_exchange_signing_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_signing_keys
    ADD CONSTRAINT merchant_exchange_signing_keys_pkey PRIMARY KEY (signkey_serial);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_master_pub_h_wire_method_start__key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_master_pub_h_wire_method_start__key UNIQUE (master_pub, h_wire_method, start_date);


--
-- Name: merchant_exchange_wire_fees merchant_exchange_wire_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_exchange_wire_fees
    ADD CONSTRAINT merchant_exchange_wire_fees_pkey PRIMARY KEY (wirefee_serial);


--
-- Name: merchant_instances merchant_instances_merchant_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_id_key UNIQUE (merchant_id);


--
-- Name: merchant_instances merchant_instances_merchant_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_merchant_pub_key UNIQUE (merchant_pub);


--
-- Name: merchant_instances merchant_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_instances
    ADD CONSTRAINT merchant_instances_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_product_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_product_id_key UNIQUE (merchant_serial, product_id);


--
-- Name: merchant_inventory merchant_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_pkey PRIMARY KEY (product_serial);


--
-- Name: merchant_keys merchant_keys_merchant_priv_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_priv_key UNIQUE (merchant_priv);


--
-- Name: merchant_keys merchant_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_pkey PRIMARY KEY (merchant_serial);


--
-- Name: merchant_kyc merchant_kyc_kyc_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_kyc
    ADD CONSTRAINT merchant_kyc_kyc_serial_id_key UNIQUE (kyc_serial_id);


--
-- Name: merchant_kyc merchant_kyc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_kyc
    ADD CONSTRAINT merchant_kyc_pkey PRIMARY KEY (account_serial, exchange_url);


--
-- Name: merchant_orders merchant_orders_merchant_serial_order_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_order_id_key UNIQUE (merchant_serial, order_id);


--
-- Name: merchant_orders merchant_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_pkey PRIMARY KEY (order_serial);


--
-- Name: merchant_refund_proofs merchant_refund_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_refunds merchant_refunds_order_serial_coin_pub_rtransaction_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_coin_pub_rtransaction_id_key UNIQUE (order_serial, coin_pub, rtransaction_id);


--
-- Name: merchant_refunds merchant_refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_pkey PRIMARY KEY (refund_serial);


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pkey PRIMARY KEY (pickup_serial, coin_offset);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pickup_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pickup_id_key UNIQUE (pickup_id);


--
-- Name: merchant_tip_pickups merchant_tip_pickups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_pkey PRIMARY KEY (pickup_serial);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_priv_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_priv_key UNIQUE (reserve_priv);


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_key UNIQUE (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_pkey PRIMARY KEY (reserve_serial);


--
-- Name: merchant_tip_reserves merchant_tip_reserves_reserve_pub_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_reserve_pub_key UNIQUE (reserve_pub);


--
-- Name: merchant_tips merchant_tips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_pkey PRIMARY KEY (tip_serial);


--
-- Name: merchant_tips merchant_tips_tip_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_tip_id_key UNIQUE (tip_id);


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_key UNIQUE (deposit_serial);


--
-- Name: merchant_transfers merchant_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_pkey PRIMARY KEY (credit_serial);


--
-- Name: merchant_transfers merchant_transfers_wtid_exchange_url_account_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_wtid_exchange_url_account_serial_key UNIQUE (wtid, exchange_url, account_serial);


--
-- Name: prewire prewire_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire
    ADD CONSTRAINT prewire_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: prewire_default prewire_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prewire_default
    ADD CONSTRAINT prewire_default_pkey PRIMARY KEY (prewire_uuid);


--
-- Name: recoup_default recoup_default_recoup_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_default
    ADD CONSTRAINT recoup_default_recoup_uuid_key UNIQUE (recoup_uuid);


--
-- Name: recoup_refresh_default recoup_refresh_default_recoup_refresh_uuid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recoup_refresh_default
    ADD CONSTRAINT recoup_refresh_default_recoup_refresh_uuid_key UNIQUE (recoup_refresh_uuid);


--
-- Name: refresh_commitments_default refresh_commitments_default_melt_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments_default
    ADD CONSTRAINT refresh_commitments_default_melt_serial_id_key UNIQUE (melt_serial_id);


--
-- Name: refresh_commitments refresh_commitments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_pkey PRIMARY KEY (rc);


--
-- Name: refresh_commitments_default refresh_commitments_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_commitments_default
    ADD CONSTRAINT refresh_commitments_default_pkey PRIMARY KEY (rc);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_coin_ev_key UNIQUE (coin_ev);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_h_coin_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_h_coin_ev_key UNIQUE (h_coin_ev);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_pkey PRIMARY KEY (melt_serial_id, freshcoin_index);


--
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_rrc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_rrc_serial_key UNIQUE (rrc_serial);


--
-- Name: refresh_transfer_keys refresh_transfer_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys
    ADD CONSTRAINT refresh_transfer_keys_pkey PRIMARY KEY (melt_serial_id);


--
-- Name: refresh_transfer_keys_default refresh_transfer_keys_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys_default
    ADD CONSTRAINT refresh_transfer_keys_default_pkey PRIMARY KEY (melt_serial_id);


--
-- Name: refresh_transfer_keys_default refresh_transfer_keys_default_rtc_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_transfer_keys_default
    ADD CONSTRAINT refresh_transfer_keys_default_rtc_serial_key UNIQUE (rtc_serial);


--
-- Name: refunds_default refunds_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds_default
    ADD CONSTRAINT refunds_default_pkey PRIMARY KEY (deposit_serial_id, rtransaction_id);


--
-- Name: refunds_default refunds_default_refund_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds_default
    ADD CONSTRAINT refunds_default_refund_serial_id_key UNIQUE (refund_serial_id);


--
-- Name: reserves_close_default reserves_close_default_close_uuid_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_close_default
    ADD CONSTRAINT reserves_close_default_close_uuid_pkey PRIMARY KEY (close_uuid);


--
-- Name: reserves reserves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves
    ADD CONSTRAINT reserves_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_default reserves_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_default
    ADD CONSTRAINT reserves_default_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in reserves_in_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in
    ADD CONSTRAINT reserves_in_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in_default reserves_in_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in_default
    ADD CONSTRAINT reserves_in_default_pkey PRIMARY KEY (reserve_pub);


--
-- Name: reserves_in_default reserves_in_default_reserve_in_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_in_default
    ADD CONSTRAINT reserves_in_default_reserve_in_serial_id_key UNIQUE (reserve_in_serial_id);


--
-- Name: reserves_out reserves_out_h_blind_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out
    ADD CONSTRAINT reserves_out_h_blind_ev_key UNIQUE (h_blind_ev);


--
-- Name: reserves_out_default reserves_out_default_h_blind_ev_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out_default
    ADD CONSTRAINT reserves_out_default_h_blind_ev_key UNIQUE (h_blind_ev);


--
-- Name: reserves_out_default reserves_out_default_reserve_out_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reserves_out_default
    ADD CONSTRAINT reserves_out_default_reserve_out_serial_id_key UNIQUE (reserve_out_serial_id);


--
-- Name: revolving_work_shards revolving_work_shards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revolving_work_shards
    ADD CONSTRAINT revolving_work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: revolving_work_shards revolving_work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revolving_work_shards
    ADD CONSTRAINT revolving_work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


--
-- Name: signkey_revocations signkey_revocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_pkey PRIMARY KEY (esk_serial);


--
-- Name: signkey_revocations signkey_revocations_signkey_revocations_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_signkey_revocations_serial_id_key UNIQUE (signkey_revocations_serial_id);


--
-- Name: wire_accounts wire_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_accounts
    ADD CONSTRAINT wire_accounts_pkey PRIMARY KEY (payto_uri);


--
-- Name: wire_auditor_account_progress wire_auditor_account_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_account_progress
    ADD CONSTRAINT wire_auditor_account_progress_pkey PRIMARY KEY (master_pub, account_name);


--
-- Name: wire_auditor_progress wire_auditor_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_progress
    ADD CONSTRAINT wire_auditor_progress_pkey PRIMARY KEY (master_pub);


--
-- Name: wire_fee wire_fee_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_pkey PRIMARY KEY (wire_method, start_date);


--
-- Name: wire_fee wire_fee_wire_fee_serial_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_fee
    ADD CONSTRAINT wire_fee_wire_fee_serial_key UNIQUE (wire_fee_serial);


--
-- Name: wire_out_default wire_out_default_wireout_uuid_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out_default
    ADD CONSTRAINT wire_out_default_wireout_uuid_pkey PRIMARY KEY (wireout_uuid);


--
-- Name: wire_out wire_out_wtid_raw_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out
    ADD CONSTRAINT wire_out_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: wire_out_default wire_out_default_wtid_raw_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_out_default
    ADD CONSTRAINT wire_out_default_wtid_raw_key UNIQUE (wtid_raw);


--
-- Name: wire_targets wire_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_targets
    ADD CONSTRAINT wire_targets_pkey PRIMARY KEY (wire_target_h_payto);


--
-- Name: wire_targets_default wire_targets_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_targets_default
    ADD CONSTRAINT wire_targets_default_pkey PRIMARY KEY (wire_target_h_payto);


--
-- Name: wire_targets_default wire_targets_default_wire_target_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_targets_default
    ADD CONSTRAINT wire_targets_default_wire_target_serial_id_key UNIQUE (wire_target_serial_id);


--
-- Name: work_shards work_shards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards
    ADD CONSTRAINT work_shards_pkey PRIMARY KEY (job_name, start_row);


--
-- Name: work_shards work_shards_shard_serial_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_shards
    ADD CONSTRAINT work_shards_shard_serial_id_key UNIQUE (shard_serial_id);


--
-- Name: aggregation_tracking_by_aggregation_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_by_aggregation_serial_id_index ON ONLY public.aggregation_tracking USING btree (aggregation_serial_id);


--
-- Name: aggregation_tracking_by_wtid_raw_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_by_wtid_raw_index ON ONLY public.aggregation_tracking USING btree (wtid_raw);


--
-- Name: INDEX aggregation_tracking_by_wtid_raw_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.aggregation_tracking_by_wtid_raw_index IS 'for lookup_transactions';


--
-- Name: aggregation_tracking_default_aggregation_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_default_aggregation_serial_id_idx ON public.aggregation_tracking_default USING btree (aggregation_serial_id);


--
-- Name: aggregation_tracking_default_wtid_raw_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aggregation_tracking_default_wtid_raw_idx ON public.aggregation_tracking_default USING btree (wtid_raw);


--
-- Name: app_banktransaction_credit_account_id_a8ba05ac; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_banktransaction_credit_account_id_a8ba05ac ON public.app_banktransaction USING btree (credit_account_id);


--
-- Name: app_banktransaction_date_f72bcad6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_banktransaction_date_f72bcad6 ON public.app_banktransaction USING btree (date);


--
-- Name: app_banktransaction_debit_account_id_5b1f7528; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_banktransaction_debit_account_id_5b1f7528 ON public.app_banktransaction USING btree (debit_account_id);


--
-- Name: app_banktransaction_request_uid_b7d06af5_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_banktransaction_request_uid_b7d06af5_like ON public.app_banktransaction USING btree (request_uid varchar_pattern_ops);


--
-- Name: app_talerwithdrawoperation_selected_exchange_account__6c8b96cf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_talerwithdrawoperation_selected_exchange_account__6c8b96cf ON public.app_talerwithdrawoperation USING btree (selected_exchange_account_id);


--
-- Name: app_talerwithdrawoperation_withdraw_account_id_992dc5b3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX app_talerwithdrawoperation_withdraw_account_id_992dc5b3 ON public.app_talerwithdrawoperation USING btree (withdraw_account_id);


--
-- Name: auditor_historic_reserve_summary_by_master_pub_start_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditor_historic_reserve_summary_by_master_pub_start_date ON public.auditor_historic_reserve_summary USING btree (master_pub, start_date);


--
-- Name: auditor_reserves_by_reserve_pub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auditor_reserves_by_reserve_pub ON public.auditor_reserves USING btree (reserve_pub);


--
-- Name: auth_group_name_a6ea08ec_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_name_a6ea08ec_like ON public.auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_group_id_b120cbf9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_permissions_group_id_b120cbf9 ON public.auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_permission_id_84c5c92e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_group_permissions_permission_id_84c5c92e ON public.auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_content_type_id_2f476e4b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_permission_content_type_id_2f476e4b ON public.auth_permission USING btree (content_type_id);


--
-- Name: auth_user_groups_group_id_97559544; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_groups_group_id_97559544 ON public.auth_user_groups USING btree (group_id);


--
-- Name: auth_user_groups_user_id_6a12ed8b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_groups_user_id_6a12ed8b ON public.auth_user_groups USING btree (user_id);


--
-- Name: auth_user_user_permissions_permission_id_1fbb5f2c; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_user_permissions_permission_id_1fbb5f2c ON public.auth_user_user_permissions USING btree (permission_id);


--
-- Name: auth_user_user_permissions_user_id_a95ead1b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_user_permissions_user_id_a95ead1b ON public.auth_user_user_permissions USING btree (user_id);


--
-- Name: auth_user_username_6821ab7c_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_user_username_6821ab7c_like ON public.auth_user USING btree (username varchar_pattern_ops);


--
-- Name: denominations_by_expire_legal_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX denominations_by_expire_legal_index ON public.denominations USING btree (expire_legal);


--
-- Name: deposits_deposit_by_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_deposit_by_serial_id_index ON ONLY public.deposits USING btree (shard, deposit_serial_id);


--
-- Name: deposits_default_shard_deposit_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_shard_deposit_serial_id_idx ON public.deposits_default USING btree (shard, deposit_serial_id);


--
-- Name: deposits_for_get_ready_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_get_ready_index ON ONLY public.deposits USING btree (shard, done, extension_blocked, tiny, wire_deadline);


--
-- Name: INDEX deposits_for_get_ready_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_for_get_ready_index IS 'for deposits_get_ready';


--
-- Name: deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx ON public.deposits_default USING btree (shard, done, extension_blocked, tiny, wire_deadline);


--
-- Name: deposits_for_iterate_matching_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_iterate_matching_index ON ONLY public.deposits USING btree (shard, merchant_pub, wire_target_h_payto, done, extension_blocked, refund_deadline);


--
-- Name: INDEX deposits_for_iterate_matching_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_for_iterate_matching_index IS 'for deposits_iterate_matching';


--
-- Name: deposits_default_shard_merchant_pub_wire_target_h_payto_don_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_shard_merchant_pub_wire_target_h_payto_don_idx ON public.deposits_default USING btree (shard, merchant_pub, wire_target_h_payto, done, extension_blocked, refund_deadline);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: global_fee_by_end_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX global_fee_by_end_date_index ON public.global_fee USING btree (end_date);


--
-- Name: known_coins_by_known_coin_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX known_coins_by_known_coin_id_index ON ONLY public.known_coins USING btree (known_coin_id);


--
-- Name: known_coins_default_known_coin_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX known_coins_default_known_coin_id_idx ON public.known_coins_default USING btree (known_coin_id);


--
-- Name: merchant_contract_terms_by_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_expiration ON public.merchant_contract_terms USING btree (paid, pay_deadline);


--
-- Name: INDEX merchant_contract_terms_by_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.merchant_contract_terms_by_expiration IS 'for unlock_contracts';


--
-- Name: merchant_contract_terms_by_merchant_and_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_expiration ON public.merchant_contract_terms USING btree (merchant_serial, pay_deadline);


--
-- Name: INDEX merchant_contract_terms_by_merchant_and_expiration; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.merchant_contract_terms_by_merchant_and_expiration IS 'for delete_contract_terms';


--
-- Name: merchant_contract_terms_by_merchant_and_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_and_payment ON public.merchant_contract_terms USING btree (merchant_serial, paid);


--
-- Name: merchant_contract_terms_by_merchant_session_and_fulfillment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_contract_terms_by_merchant_session_and_fulfillment ON public.merchant_contract_terms USING btree (merchant_serial, fulfillment_url, session_id);


--
-- Name: merchant_inventory_locks_by_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_expiration ON public.merchant_inventory_locks USING btree (expiration);


--
-- Name: merchant_inventory_locks_by_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_inventory_locks_by_uuid ON public.merchant_inventory_locks USING btree (lock_uuid);


--
-- Name: merchant_orders_by_creation_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_by_creation_time ON public.merchant_orders USING btree (creation_time);


--
-- Name: merchant_orders_by_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_by_expiration ON public.merchant_orders USING btree (pay_deadline);


--
-- Name: merchant_orders_locks_by_order_and_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_orders_locks_by_order_and_product ON public.merchant_order_locks USING btree (order_serial, product_serial);


--
-- Name: merchant_refunds_by_coin_and_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_refunds_by_coin_and_order ON public.merchant_refunds USING btree (coin_pub, order_serial);


--
-- Name: merchant_tip_reserves_by_exchange_balance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_exchange_balance ON public.merchant_tip_reserves USING btree (exchange_initial_balance_val, exchange_initial_balance_frac);


--
-- Name: merchant_tip_reserves_by_merchant_serial_and_creation_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_merchant_serial_and_creation_time ON public.merchant_tip_reserves USING btree (merchant_serial, creation_time);


--
-- Name: merchant_tip_reserves_by_reserve_pub_and_merchant_serial; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tip_reserves_by_reserve_pub_and_merchant_serial ON public.merchant_tip_reserves USING btree (reserve_pub, merchant_serial, creation_time);


--
-- Name: merchant_tips_by_pickup_and_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_tips_by_pickup_and_expiration ON public.merchant_tips USING btree (was_picked_up, expiration);


--
-- Name: merchant_transfers_by_credit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX merchant_transfers_by_credit ON public.merchant_transfer_to_coin USING btree (credit_serial);


--
-- Name: prewire_by_failed_finished_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prewire_by_failed_finished_index ON ONLY public.prewire USING btree (failed, finished);


--
-- Name: INDEX prewire_by_failed_finished_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.prewire_by_failed_finished_index IS 'for wire_prepare_data_get';


--
-- Name: prewire_by_finished_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prewire_by_finished_index ON ONLY public.prewire USING btree (finished);


--
-- Name: INDEX prewire_by_finished_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.prewire_by_finished_index IS 'for gc_prewire';


--
-- Name: prewire_default_failed_finished_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prewire_default_failed_finished_idx ON public.prewire_default USING btree (failed, finished);


--
-- Name: prewire_default_finished_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX prewire_default_finished_idx ON public.prewire_default USING btree (finished);


--
-- Name: recoup_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_coin_pub_index ON ONLY public.recoup USING btree (coin_pub);


--
-- Name: recoup_by_recoup_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_recoup_uuid_index ON ONLY public.recoup USING btree (recoup_uuid);


--
-- Name: recoup_by_reserve_out_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_out_serial_id_index ON ONLY public.recoup USING btree (reserve_out_serial_id);


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_coin_pub_idx ON public.recoup_default USING btree (coin_pub);


--
-- Name: recoup_default_recoup_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_recoup_uuid_idx ON public.recoup_default USING btree (recoup_uuid);


--
-- Name: recoup_default_reserve_out_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_reserve_out_serial_id_idx ON public.recoup_default USING btree (reserve_out_serial_id);


--
-- Name: recoup_refresh_by_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_coin_pub_index ON ONLY public.recoup_refresh USING btree (coin_pub);


--
-- Name: recoup_refresh_by_recoup_refresh_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_recoup_refresh_uuid_index ON ONLY public.recoup_refresh USING btree (recoup_refresh_uuid);


--
-- Name: recoup_refresh_by_rrc_serial_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_rrc_serial_index ON ONLY public.recoup_refresh USING btree (rrc_serial);


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_coin_pub_idx ON public.recoup_refresh_default USING btree (coin_pub);


--
-- Name: recoup_refresh_default_recoup_refresh_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_recoup_refresh_uuid_idx ON public.recoup_refresh_default USING btree (recoup_refresh_uuid);


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_rrc_serial_idx ON public.recoup_refresh_default USING btree (rrc_serial);


--
-- Name: refresh_commitments_by_melt_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_by_melt_serial_id_index ON ONLY public.refresh_commitments USING btree (melt_serial_id);


--
-- Name: refresh_commitments_by_old_coin_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_by_old_coin_pub_index ON ONLY public.refresh_commitments USING btree (old_coin_pub);


--
-- Name: refresh_commitments_default_melt_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_default_melt_serial_id_idx ON public.refresh_commitments_default USING btree (melt_serial_id);


--
-- Name: refresh_commitments_default_old_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_commitments_default_old_coin_pub_idx ON public.refresh_commitments_default USING btree (old_coin_pub);


--
-- Name: refresh_revealed_coins_by_melt_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_by_melt_serial_id_index ON ONLY public.refresh_revealed_coins USING btree (melt_serial_id);


--
-- Name: refresh_revealed_coins_by_rrc_serial_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_by_rrc_serial_index ON ONLY public.refresh_revealed_coins USING btree (rrc_serial);


--
-- Name: refresh_revealed_coins_default_melt_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_default_melt_serial_id_idx ON public.refresh_revealed_coins_default USING btree (melt_serial_id);


--
-- Name: refresh_revealed_coins_default_rrc_serial_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_revealed_coins_default_rrc_serial_idx ON public.refresh_revealed_coins_default USING btree (rrc_serial);


--
-- Name: refresh_transfer_keys_by_rtc_serial_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_transfer_keys_by_rtc_serial_index ON ONLY public.refresh_transfer_keys USING btree (rtc_serial);


--
-- Name: refresh_transfer_keys_default_rtc_serial_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refresh_transfer_keys_default_rtc_serial_idx ON public.refresh_transfer_keys_default USING btree (rtc_serial);


--
-- Name: refunds_by_deposit_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_by_deposit_serial_id_index ON ONLY public.refunds USING btree (shard, deposit_serial_id);


--
-- Name: refunds_by_refund_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_by_refund_serial_id_index ON ONLY public.refunds USING btree (refund_serial_id);


--
-- Name: refunds_default_refund_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_default_refund_serial_id_idx ON public.refunds_default USING btree (refund_serial_id);


--
-- Name: refunds_default_shard_deposit_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_default_shard_deposit_serial_id_idx ON public.refunds_default USING btree (shard, deposit_serial_id);


--
-- Name: reserves_by_expiration_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_by_expiration_index ON ONLY public.reserves USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: INDEX reserves_by_expiration_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_by_expiration_index IS 'used in get_expired_reserves';


--
-- Name: reserves_by_gc_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_by_gc_date_index ON ONLY public.reserves USING btree (gc_date);


--
-- Name: INDEX reserves_by_gc_date_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_by_gc_date_index IS 'for reserve garbage collection';


--
-- Name: reserves_by_reserve_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_by_reserve_uuid_index ON ONLY public.reserves USING btree (reserve_uuid);


--
-- Name: reserves_close_by_close_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_by_close_uuid_index ON ONLY public.reserves_close USING btree (close_uuid);


--
-- Name: reserves_close_by_reserve_pub_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_by_reserve_pub_index ON ONLY public.reserves_close USING btree (reserve_pub);


--
-- Name: reserves_close_default_close_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_default_close_uuid_idx ON public.reserves_close_default USING btree (close_uuid);


--
-- Name: reserves_close_default_reserve_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_close_default_reserve_pub_idx ON public.reserves_close_default USING btree (reserve_pub);


--
-- Name: reserves_default_expiration_date_current_balance_val_curren_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_default_expiration_date_current_balance_val_curren_idx ON public.reserves_default USING btree (expiration_date, current_balance_val, current_balance_frac);


--
-- Name: reserves_default_gc_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_default_gc_date_idx ON public.reserves_default USING btree (gc_date);


--
-- Name: reserves_default_reserve_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_default_reserve_uuid_idx ON public.reserves_default USING btree (reserve_uuid);


--
-- Name: reserves_in_by_exchange_account_reserve_in_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_by_exchange_account_reserve_in_serial_id_index ON ONLY public.reserves_in USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_by_exchange_account_section_execution_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_by_exchange_account_section_execution_date_index ON ONLY public.reserves_in USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_by_reserve_in_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_by_reserve_in_serial_id_index ON ONLY public.reserves_in USING btree (reserve_in_serial_id);


--
-- Name: reserves_in_default_exchange_account_section_execution_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_default_exchange_account_section_execution_date_idx ON public.reserves_in_default USING btree (exchange_account_section, execution_date);


--
-- Name: reserves_in_default_exchange_account_section_reserve_in_ser_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_default_exchange_account_section_reserve_in_ser_idx ON public.reserves_in_default USING btree (exchange_account_section, reserve_in_serial_id DESC);


--
-- Name: reserves_in_default_reserve_in_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_in_default_reserve_in_serial_id_idx ON public.reserves_in_default USING btree (reserve_in_serial_id);


--
-- Name: reserves_out_by_reserve_out_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_by_reserve_out_serial_id_index ON ONLY public.reserves_out USING btree (reserve_out_serial_id);


--
-- Name: reserves_out_by_reserve_uuid_and_execution_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_by_reserve_uuid_and_execution_date_index ON ONLY public.reserves_out USING btree (reserve_uuid, execution_date);


--
-- Name: INDEX reserves_out_by_reserve_uuid_and_execution_date_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.reserves_out_by_reserve_uuid_and_execution_date_index IS 'for get_reserves_out and exchange_do_withdraw_limit_check';


--
-- Name: reserves_out_default_reserve_out_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_default_reserve_out_serial_id_idx ON public.reserves_out_default USING btree (reserve_out_serial_id);


--
-- Name: reserves_out_default_reserve_uuid_execution_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_default_reserve_uuid_execution_date_idx ON public.reserves_out_default USING btree (reserve_uuid, execution_date);


--
-- Name: revolving_work_shards_by_job_name_active_last_attempt_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX revolving_work_shards_by_job_name_active_last_attempt_index ON public.revolving_work_shards USING btree (job_name, active, last_attempt);


--
-- Name: wire_fee_by_end_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_fee_by_end_date_index ON public.wire_fee USING btree (end_date);


--
-- Name: wire_out_by_wire_target_h_payto_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_by_wire_target_h_payto_index ON ONLY public.wire_out USING btree (wire_target_h_payto);


--
-- Name: wire_out_by_wireout_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_by_wireout_uuid_index ON ONLY public.wire_out USING btree (wireout_uuid);


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_default_wire_target_h_payto_idx ON public.wire_out_default USING btree (wire_target_h_payto);


--
-- Name: wire_out_default_wireout_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_default_wireout_uuid_idx ON public.wire_out_default USING btree (wireout_uuid);


--
-- Name: wire_targets_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_targets_serial_id_index ON ONLY public.wire_targets USING btree (wire_target_serial_id);


--
-- Name: wire_targets_default_wire_target_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_targets_default_wire_target_serial_id_idx ON public.wire_targets_default USING btree (wire_target_serial_id);


--
-- Name: work_shards_by_job_name_completed_last_attempt_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX work_shards_by_job_name_completed_last_attempt_index ON public.work_shards USING btree (job_name, completed, last_attempt);


--
-- Name: aggregation_tracking_default_aggregation_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.aggregation_tracking_by_aggregation_serial_id_index ATTACH PARTITION public.aggregation_tracking_default_aggregation_serial_id_idx;


--
-- Name: aggregation_tracking_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.aggregation_tracking_pkey ATTACH PARTITION public.aggregation_tracking_default_pkey;


--
-- Name: aggregation_tracking_default_wtid_raw_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.aggregation_tracking_by_wtid_raw_index ATTACH PARTITION public.aggregation_tracking_default_wtid_raw_idx;


--
-- Name: cs_nonce_locks_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.cs_nonce_locks_pkey ATTACH PARTITION public.cs_nonce_locks_default_pkey;


--
-- Name: deposits_default_shard_coin_pub_merchant_pub_h_contract_ter_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_shard_coin_pub_merchant_pub_h_contract_terms_key ATTACH PARTITION public.deposits_default_shard_coin_pub_merchant_pub_h_contract_ter_key;


--
-- Name: deposits_default_shard_deposit_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_deposit_by_serial_id_index ATTACH PARTITION public.deposits_default_shard_deposit_serial_id_idx;


--
-- Name: deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_get_ready_index ATTACH PARTITION public.deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx;


--
-- Name: deposits_default_shard_merchant_pub_wire_target_h_payto_don_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_iterate_matching_index ATTACH PARTITION public.deposits_default_shard_merchant_pub_wire_target_h_payto_don_idx;


--
-- Name: known_coins_default_known_coin_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.known_coins_by_known_coin_id_index ATTACH PARTITION public.known_coins_default_known_coin_id_idx;


--
-- Name: known_coins_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.known_coins_pkey ATTACH PARTITION public.known_coins_default_pkey;


--
-- Name: prewire_default_failed_finished_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.prewire_by_failed_finished_index ATTACH PARTITION public.prewire_default_failed_finished_idx;


--
-- Name: prewire_default_finished_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.prewire_by_finished_index ATTACH PARTITION public.prewire_default_finished_idx;


--
-- Name: prewire_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.prewire_pkey ATTACH PARTITION public.prewire_default_pkey;


--
-- Name: recoup_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_coin_pub_index ATTACH PARTITION public.recoup_default_coin_pub_idx;


--
-- Name: recoup_default_recoup_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_recoup_uuid_index ATTACH PARTITION public.recoup_default_recoup_uuid_idx;


--
-- Name: recoup_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_reserve_out_serial_id_index ATTACH PARTITION public.recoup_default_reserve_out_serial_id_idx;


--
-- Name: recoup_refresh_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_coin_pub_index ATTACH PARTITION public.recoup_refresh_default_coin_pub_idx;


--
-- Name: recoup_refresh_default_recoup_refresh_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_recoup_refresh_uuid_index ATTACH PARTITION public.recoup_refresh_default_recoup_refresh_uuid_idx;


--
-- Name: recoup_refresh_default_rrc_serial_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_rrc_serial_index ATTACH PARTITION public.recoup_refresh_default_rrc_serial_idx;


--
-- Name: refresh_commitments_default_melt_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_commitments_by_melt_serial_id_index ATTACH PARTITION public.refresh_commitments_default_melt_serial_id_idx;


--
-- Name: refresh_commitments_default_old_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_commitments_by_old_coin_pub_index ATTACH PARTITION public.refresh_commitments_default_old_coin_pub_idx;


--
-- Name: refresh_commitments_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_commitments_pkey ATTACH PARTITION public.refresh_commitments_default_pkey;


--
-- Name: refresh_revealed_coins_default_melt_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_revealed_coins_by_melt_serial_id_index ATTACH PARTITION public.refresh_revealed_coins_default_melt_serial_id_idx;


--
-- Name: refresh_revealed_coins_default_rrc_serial_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_revealed_coins_by_rrc_serial_index ATTACH PARTITION public.refresh_revealed_coins_default_rrc_serial_idx;


--
-- Name: refresh_transfer_keys_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_transfer_keys_pkey ATTACH PARTITION public.refresh_transfer_keys_default_pkey;


--
-- Name: refresh_transfer_keys_default_rtc_serial_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refresh_transfer_keys_by_rtc_serial_index ATTACH PARTITION public.refresh_transfer_keys_default_rtc_serial_idx;


--
-- Name: refunds_default_refund_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refunds_by_refund_serial_id_index ATTACH PARTITION public.refunds_default_refund_serial_id_idx;


--
-- Name: refunds_default_shard_deposit_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.refunds_by_deposit_serial_id_index ATTACH PARTITION public.refunds_default_shard_deposit_serial_id_idx;


--
-- Name: reserves_close_default_close_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_close_by_close_uuid_index ATTACH PARTITION public.reserves_close_default_close_uuid_idx;


--
-- Name: reserves_close_default_reserve_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_close_by_reserve_pub_index ATTACH PARTITION public.reserves_close_default_reserve_pub_idx;


--
-- Name: reserves_default_expiration_date_current_balance_val_curren_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_by_expiration_index ATTACH PARTITION public.reserves_default_expiration_date_current_balance_val_curren_idx;


--
-- Name: reserves_default_gc_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_by_gc_date_index ATTACH PARTITION public.reserves_default_gc_date_idx;


--
-- Name: reserves_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_pkey ATTACH PARTITION public.reserves_default_pkey;


--
-- Name: reserves_default_reserve_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_by_reserve_uuid_index ATTACH PARTITION public.reserves_default_reserve_uuid_idx;


--
-- Name: reserves_in_default_exchange_account_section_execution_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_in_by_exchange_account_section_execution_date_index ATTACH PARTITION public.reserves_in_default_exchange_account_section_execution_date_idx;


--
-- Name: reserves_in_default_exchange_account_section_reserve_in_ser_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_in_by_exchange_account_reserve_in_serial_id_index ATTACH PARTITION public.reserves_in_default_exchange_account_section_reserve_in_ser_idx;


--
-- Name: reserves_in_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_in_pkey ATTACH PARTITION public.reserves_in_default_pkey;


--
-- Name: reserves_in_default_reserve_in_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_in_by_reserve_in_serial_id_index ATTACH PARTITION public.reserves_in_default_reserve_in_serial_id_idx;


--
-- Name: reserves_out_default_h_blind_ev_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_out_h_blind_ev_key ATTACH PARTITION public.reserves_out_default_h_blind_ev_key;


--
-- Name: reserves_out_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_out_by_reserve_out_serial_id_index ATTACH PARTITION public.reserves_out_default_reserve_out_serial_id_idx;


--
-- Name: reserves_out_default_reserve_uuid_execution_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_out_by_reserve_uuid_and_execution_date_index ATTACH PARTITION public.reserves_out_default_reserve_uuid_execution_date_idx;


--
-- Name: wire_out_default_wire_target_h_payto_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_by_wire_target_h_payto_index ATTACH PARTITION public.wire_out_default_wire_target_h_payto_idx;


--
-- Name: wire_out_default_wireout_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_by_wireout_uuid_index ATTACH PARTITION public.wire_out_default_wireout_uuid_idx;


--
-- Name: wire_out_default_wtid_raw_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_wtid_raw_key ATTACH PARTITION public.wire_out_default_wtid_raw_key;


--
-- Name: wire_targets_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_targets_pkey ATTACH PARTITION public.wire_targets_default_pkey;


--
-- Name: wire_targets_default_wire_target_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_targets_serial_id_index ATTACH PARTITION public.wire_targets_default_wire_target_serial_id_idx;


--
-- Name: deposits deposit_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposit_on_delete AFTER DELETE ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposit_by_coin_delete_trigger();


--
-- Name: deposits deposits_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposits_on_insert AFTER INSERT ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposit_by_coin_insert_trigger();


--
-- Name: reserves_out reserves_out_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reserves_out_on_delete AFTER DELETE ON public.reserves_out FOR EACH ROW EXECUTE FUNCTION public.reserves_out_by_reserve_delete_trigger();


--
-- Name: reserves_out reserves_out_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reserves_out_on_insert AFTER INSERT ON public.reserves_out FOR EACH ROW EXECUTE FUNCTION public.reserves_out_by_reserve_insert_trigger();


--
-- Name: app_bankaccount app_bankaccount_user_id_2722a34f_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_bankaccount
    ADD CONSTRAINT app_bankaccount_user_id_2722a34f_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_banktransaction app_banktransaction_credit_account_id_a8ba05ac_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_credit_account_id_a8ba05ac_fk_app_banka FOREIGN KEY (credit_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_banktransaction app_banktransaction_debit_account_id_5b1f7528_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_banktransaction
    ADD CONSTRAINT app_banktransaction_debit_account_id_5b1f7528_fk_app_banka FOREIGN KEY (debit_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_talerwithdrawoperation app_talerwithdrawope_selected_exchange_ac_6c8b96cf_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawope_selected_exchange_ac_6c8b96cf_fk_app_banka FOREIGN KEY (selected_exchange_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: app_talerwithdrawoperation app_talerwithdrawope_withdraw_account_id_992dc5b3_fk_app_banka; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_talerwithdrawoperation
    ADD CONSTRAINT app_talerwithdrawope_withdraw_account_id_992dc5b3_fk_app_banka FOREIGN KEY (withdraw_account_id) REFERENCES public.app_bankaccount(account_no) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_auditor_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_auditor_uuid_fkey FOREIGN KEY (auditor_uuid) REFERENCES public.auditors(auditor_uuid) ON DELETE CASCADE;


--
-- Name: auditor_denom_sigs auditor_denom_sigs_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_denom_sigs
    ADD CONSTRAINT auditor_denom_sigs_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: auth_group_permissions auth_group_permissio_permission_id_84c5c92e_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_permission auth_permission_content_type_id_2f476e4b_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_group_id_97559544_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_group_id_97559544_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_groups auth_user_groups_user_id_6a12ed8b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_6a12ed8b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_user_user_permissions auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: denomination_revocations denomination_revocations_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.denomination_revocations
    ADD CONSTRAINT denomination_revocations_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: deposits deposits_extension_details_serial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.deposits
    ADD CONSTRAINT deposits_extension_details_serial_id_fkey FOREIGN KEY (extension_details_serial_id) REFERENCES public.extension_details(extension_details_serial_id) ON DELETE CASCADE;


--
-- Name: known_coins known_coins_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.known_coins
    ADD CONSTRAINT known_coins_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: auditor_exchange_signkeys master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_exchange_signkeys
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_reserve master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_reserve
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_aggregation master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_aggregation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_deposit_confirmation master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_deposit_confirmation
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_progress_coin master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_progress_coin
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_account_progress master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_account_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: wire_auditor_progress master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_auditor_progress
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserves master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserves
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_reserve_balance master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_reserve_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_wire_fee_balance master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_wire_fee_balance
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_balance_summary master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_balance_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_denomination_revenue master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_historic_denomination_revenue
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_historic_reserve_summary master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_historic_reserve_summary
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: deposit_confirmations master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_confirmations
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: auditor_predicted_result master_pub_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auditor_predicted_result
    ADD CONSTRAINT master_pub_ref FOREIGN KEY (master_pub) REFERENCES public.auditor_exchanges(master_pub) ON DELETE CASCADE;


--
-- Name: merchant_accounts merchant_accounts_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_accounts
    ADD CONSTRAINT merchant_accounts_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_contract_terms merchant_contract_terms_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_contract_terms
    ADD CONSTRAINT merchant_contract_terms_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial);


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES public.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposit_to_transfer merchant_deposit_to_transfer_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposit_to_transfer
    ADD CONSTRAINT merchant_deposit_to_transfer_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_deposits merchant_deposits_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_deposits
    ADD CONSTRAINT merchant_deposits_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_inventory_locks merchant_inventory_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory_locks
    ADD CONSTRAINT merchant_inventory_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES public.merchant_inventory(product_serial);


--
-- Name: merchant_inventory merchant_inventory_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_inventory
    ADD CONSTRAINT merchant_inventory_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_keys merchant_keys_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_keys
    ADD CONSTRAINT merchant_keys_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_kyc merchant_kyc_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_kyc
    ADD CONSTRAINT merchant_kyc_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_orders(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_order_locks merchant_order_locks_product_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_order_locks
    ADD CONSTRAINT merchant_order_locks_product_serial_fkey FOREIGN KEY (product_serial) REFERENCES public.merchant_inventory(product_serial);


--
-- Name: merchant_orders merchant_orders_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_orders
    ADD CONSTRAINT merchant_orders_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_refund_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_refund_serial_fkey FOREIGN KEY (refund_serial) REFERENCES public.merchant_refunds(refund_serial) ON DELETE CASCADE;


--
-- Name: merchant_refund_proofs merchant_refund_proofs_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refund_proofs
    ADD CONSTRAINT merchant_refund_proofs_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_refunds merchant_refunds_order_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_refunds
    ADD CONSTRAINT merchant_refunds_order_serial_fkey FOREIGN KEY (order_serial) REFERENCES public.merchant_contract_terms(order_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickup_signatures merchant_tip_pickup_signatures_pickup_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickup_signatures
    ADD CONSTRAINT merchant_tip_pickup_signatures_pickup_serial_fkey FOREIGN KEY (pickup_serial) REFERENCES public.merchant_tip_pickups(pickup_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_pickups merchant_tip_pickups_tip_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_pickups
    ADD CONSTRAINT merchant_tip_pickups_tip_serial_fkey FOREIGN KEY (tip_serial) REFERENCES public.merchant_tips(tip_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserve_keys merchant_tip_reserve_keys_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserve_keys
    ADD CONSTRAINT merchant_tip_reserve_keys_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES public.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_tip_reserves merchant_tip_reserves_merchant_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tip_reserves
    ADD CONSTRAINT merchant_tip_reserves_merchant_serial_fkey FOREIGN KEY (merchant_serial) REFERENCES public.merchant_instances(merchant_serial) ON DELETE CASCADE;


--
-- Name: merchant_tips merchant_tips_reserve_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_tips
    ADD CONSTRAINT merchant_tips_reserve_serial_fkey FOREIGN KEY (reserve_serial) REFERENCES public.merchant_tip_reserves(reserve_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_signatures merchant_transfer_signatures_signkey_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_signatures
    ADD CONSTRAINT merchant_transfer_signatures_signkey_serial_fkey FOREIGN KEY (signkey_serial) REFERENCES public.merchant_exchange_signing_keys(signkey_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_credit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_credit_serial_fkey FOREIGN KEY (credit_serial) REFERENCES public.merchant_transfers(credit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfer_to_coin merchant_transfer_to_coin_deposit_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfer_to_coin
    ADD CONSTRAINT merchant_transfer_to_coin_deposit_serial_fkey FOREIGN KEY (deposit_serial) REFERENCES public.merchant_deposits(deposit_serial) ON DELETE CASCADE;


--
-- Name: merchant_transfers merchant_transfers_account_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.merchant_transfers
    ADD CONSTRAINT merchant_transfers_account_serial_fkey FOREIGN KEY (account_serial) REFERENCES public.merchant_accounts(account_serial) ON DELETE CASCADE;


--
-- Name: refresh_commitments refresh_commitments_old_coin_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.refresh_commitments
    ADD CONSTRAINT refresh_commitments_old_coin_pub_fkey FOREIGN KEY (old_coin_pub) REFERENCES public.known_coins(coin_pub) ON DELETE CASCADE;


--
-- Name: refresh_revealed_coins refresh_revealed_coins_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.refresh_revealed_coins
    ADD CONSTRAINT refresh_revealed_coins_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial) ON DELETE CASCADE;


--
-- Name: reserves_close reserves_close_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.reserves_close
    ADD CONSTRAINT reserves_close_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_in reserves_in_reserve_pub_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.reserves_in
    ADD CONSTRAINT reserves_in_reserve_pub_fkey FOREIGN KEY (reserve_pub) REFERENCES public.reserves(reserve_pub) ON DELETE CASCADE;


--
-- Name: reserves_out reserves_out_denominations_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.reserves_out
    ADD CONSTRAINT reserves_out_denominations_serial_fkey FOREIGN KEY (denominations_serial) REFERENCES public.denominations(denominations_serial);


--
-- Name: signkey_revocations signkey_revocations_esk_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signkey_revocations
    ADD CONSTRAINT signkey_revocations_esk_serial_fkey FOREIGN KEY (esk_serial) REFERENCES public.exchange_sign_keys(esk_serial) ON DELETE CASCADE;


--
-- Name: aggregation_tracking wire_out_ref; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.aggregation_tracking
    ADD CONSTRAINT wire_out_ref FOREIGN KEY (wtid_raw) REFERENCES public.wire_out(wtid_raw) ON DELETE CASCADE DEFERRABLE;


--
-- PostgreSQL database dump complete
--

