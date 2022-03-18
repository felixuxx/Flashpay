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
-- Name: deposits_by_coin_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposits_by_coin_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM deposits_by_coin
   WHERE coin_pub = OLD.coin_pub
     AND shard = OLD.shard
     AND deposit_serial_id = OLD.deposit_serial_id;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION deposits_by_coin_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposits_by_coin_delete_trigger() IS 'Replicate deposits deletions into deposits_by_coin table.';


--
-- Name: deposits_by_coin_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.deposits_by_coin_insert_trigger() RETURNS trigger
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
-- Name: FUNCTION deposits_by_coin_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.deposits_by_coin_insert_trigger() IS 'Replicate deposit inserts into deposits_by_coin table.';


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
exchange-0001	2022-03-18 15:01:36.726973+01	grothoff	{}	{}
merchant-0001	2022-03-18 15:01:38.237739+01	grothoff	{}	{}
auditor-0001	2022-03-18 15:01:39.128566+01	grothoff	{}	{}
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
f	12	+TESTKUDOS:90	12
t	1	-TESTKUDOS:200	1
f	13	+TESTKUDOS:82	13
t	2	+TESTKUDOS:28	2
\.


--
-- Data for Name: app_banktransaction; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_banktransaction (id, amount, subject, date, cancelled, request_uid, credit_account_id, debit_account_id) FROM stdin;
1	TESTKUDOS:100	Joining bonus	2022-03-18 15:01:49.773959+01	f	41b4c42c-789e-4987-b573-3f30c70dfe8b	12	1
2	TESTKUDOS:10	4MNQWDRD0YH9PW9G0AQMSD9BY6D9FDES70AVF9PN72G4FXZQNCG0	2022-03-18 15:01:53.626209+01	f	ee44c1fb-29b1-4c28-abda-745b7fa3bc8a	2	12
3	TESTKUDOS:100	Joining bonus	2022-03-18 15:02:00.913113+01	f	7ba57eed-7c37-4899-b3d2-f908d367b37a	13	1
4	TESTKUDOS:18	0MNGCYJF7CJEK67D211W5B7WYWDRK8K9DM1QAV4KJ3TPK6S5W9A0	2022-03-18 15:02:01.558733+01	f	3c4f0e62-3c37-4651-84b6-12c4ba164c42	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
7b263211-a55d-4292-8972-beb2f650386e	TESTKUDOS:10	t	t	f	4MNQWDRD0YH9PW9G0AQMSD9BY6D9FDES70AVF9PN72G4FXZQNCG0	2	12
bb1a4702-8d1d-4ae5-a53f-370b5fb7dd4b	TESTKUDOS:18	t	t	f	0MNGCYJF7CJEK67D211W5B7WYWDRK8K9DM1QAV4KJ3TPK6S5W9A0	2	13
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
1	1	34	\\x7905e5cba81a0882ea19cb25042f198e9cc3869388199d22fc6c3b8322d425a5d928f3996aaf20fda5c06c65970a6246a2218250cd7ec394dbac1aec9a7bd20a
2	1	213	\\xeb80e7a8969a8c5f8e1c25e0908d56fb3e1720354f4be8321544e22063ab6f519acabe0e1b8136883d8c44335827a69a117ec5f7ad781d97fb244209c3532b01
3	1	423	\\x41c35cb31170949f211c9f7a636243833c0cf87e04dd8e6f165eb826f4853b21ebc4c640ede59a96488ef59272fcb2db856b2026eb3dc3d76ea1d88c92382401
4	1	215	\\xb88f7ab391e53d578cf19ae2daf0c33915b9fd8ef28ad96e021a0b663afe28cf5ec4e43e1cc791b010984ee4cfed0fcad6591901c0ba8ffec56f05d27f85f104
5	1	84	\\xc0ef57a394a78673603caf957c47bece71030b12d8d04605af8bcf92e6d435faa9931eaef1a38349a696d2e0b16e9f035b43bc9d9ea1f34cc8341f22a6631e0b
6	1	222	\\x6b85e5428e610dd213a285d5b16d18f8b8614a9e329457e53595ba83ecca0820a9c5113d6443b9fc72fc7f45501473b8b1fc63c7477760cfd4a1d9ba8d876c05
7	1	110	\\x880651b01b6955390cb37930f73e6e6306879dc0a7c56537c5b4889dda645e838a60bd8d60a5cc8cf556160927be5e04ff3e1505005a3da2a39859560d4cd902
8	1	163	\\x90fb6be683ab4348a93ce9fed02460a717ff8e5d19ac48f54653b0984936cdb6e9abccf870a36db55732754ea7f739c85dc218efa1f80e2a9e9e9b5e1a092f04
9	1	114	\\x8f075b437b217bcdd8bcd825a0ed144fd57002ee1aae478cd94a4b8b8179b92cf82e7eb737e884beb3292079bda6043db6095a42096d2333358c37b93146a206
10	1	370	\\x75bd7205ebea506a67d4da56c7fcae71615b758036105a63e29a336f751a4fce44b57c3a5436332a7bb84761bc301d96f4c60df58ff57321ed7d4e2fb583ef01
11	1	424	\\x036219d592c44fabba300b7ca89c7d0d231165573c422da74ee09c375ddadfa08cec69e2bf12fe3fd50c21c0b2465969d5dfa6222e1e31d7bfa6ff2f02660501
12	1	329	\\x1452cdf749263a8b791c300595abd9374ccab2ee1cc0f3b0f1525d09d10eb1fef0707d3f94f9f6c2ff44880bab07d3994ad63be4d060a576895b49d5f53c8d0a
13	1	102	\\x2026207d7caa2571351600f71bca81b7edbefd3d33707771092b033546e84f00b043a0cae34e662bf7fd0adcf78f5165a283a45345de71d395616ce03344230d
14	1	29	\\x50ca0ead05db2ecf6d9ed182ce2564e7e480149dfef7ee30ca5fc8df1e57b990b766448bc9f1ec26765231fb76bd5864fe5ec996b1d6c0fd1fb8b54cb272e606
15	1	196	\\x87441e0f009c4d656e80bc5dc4c93debb92b3ce5c8a8b22bd8006a949f9dd76663ad564241b820db3cbd6126b0658561ebcb06fd7cc66c377097ace33d198604
16	1	339	\\x75d064a57c0bbb67f194589aa59a4fddf0ac2062e571ee25dec0beb467f83b691b072ec73e1cf77e457d3085bccc4ae009284903c5089d93e72e8ec11dc2f705
17	1	226	\\xc09252070a2776e7347d0976191f0f6425adf2eb19802e059ffb05ea1b08fa8c504e87fe3a6af783925257b44470f8bcd74db6a426e08a25b8a87a8689e83c0c
18	1	315	\\x6d8755328ed91680865be6d5744ca2815edbbeed7fecfc3c9a77ae9bc9228d85dddfd9f29be2d0f24bdfca0de20294616e181f36ab101bb618a2e9bad41d7f02
19	1	43	\\x84339522fe0c14499af8aa9e09bd6253fec64ac4d4b0a7c65f29cc9756feadc5bb262c7119d8efba21ae58262a891dd82ae23bb26651ff390254a12db6dfe70c
20	1	77	\\x493325221099cfbc10717730c7287fc41524c6c8f9e336b3ffff1019a2ed1ca4cd66efb78cff584cb44946b27c2478c24e487b17b2d6b00af0a220ed8c2b230a
21	1	152	\\x7acacce9ff0e5326ea422e2a18c12224666c055765cccb3a008b72bab12698d2cd09c578014f9c5e9df9bcc3d70d64dd477b51be00d4c7f32677ef8d7434660f
22	1	355	\\x7683faca8b33a7cb0b8782b99d0d41af560c24424afc4866bce83e559bd065231a3dbe160e7b3a00fe4c0704e3b20864014f93f591ab9b8509e412ed205c5a0b
23	1	10	\\x01ca3bef25bc1fed0933675ecb05b8e182f1b11541deb154f2ad9907138727f1a159be834f36b3fdda6881c6b4548d1a174d8aa408228d74f6f0b88ae445be0c
24	1	277	\\xd3fd300e90115e05852ae551d5b5a62e616ae37d690751e975ce01bf2ccc6c125978164f5abafa0c69346c37a5ff95541aeaa35e697de3cda0bf70900ff49401
25	1	182	\\x789b65c39788cb2009f6531427ac72af90e674572239a6b02759ffd935d5b84e9b6da41c52b56bb93aea558c055a290f422501689161752928877be937f8ef0c
26	1	7	\\xc9205b896fa2269b2ce3c7c04ce499e64c90e449d558f048049e83549978000e91cad8789a008d9ec564de0bcd4a56fd5208345ef893c06190d9be7a527a1000
27	1	144	\\xea36db726c8473554a493bd7362daa69cb9ec42f592759846a6d987016581d0f3ee250d4107a550bd49bac8f328d1c84cc6496ed54c6d419952a996ed3ed3a08
28	1	69	\\xe52e0e61c4cd02919975db83bade9edfb342bc219656564297870d7876ab5edce7ccc56373ac1e5cec7e84f627d29732d5c5ddcb6a81d79516dbf4c6377e120b
29	1	349	\\xde3a9d4a78b4d89bd97204863faef9fc27164c3a769f162e5932a47f7c4ec0b163fcf4185495820735b379e08b71e1665a28217ecb2b88f61a3f21aa1877660c
30	1	117	\\xf2ffd31a6fddb827b86ad241965d88ac2b5227b1ea6a14aadbead31a7625331f1a7ba0b997b7efd663b847741384475dafec721c52445cb1f5101935b78a990d
31	1	364	\\xdbc01cc8b012b25af2d6b15cbfcf0c577f41f44f3e7cd111db57f82393a279073e753604d46f026d92a458ef4a46c3b87c6ef846c496afac002777e9491ef801
32	1	271	\\x8033127bda20e911727a4b1003b070ad9e197978dda770fc1d1b8319802ae8ebf4c9914ecae192535ea5fc90bcc065a37510da815f26f24526b05c1263a5d60e
33	1	251	\\x98150210a89f3c5a568f6173bc4c4f4ce8d099dab63ab9bcc134e9fc31cb75d399304595dba0704ffd262efbeebaf84b92fde6e9eec94d23c8829a902ee21006
34	1	287	\\x1fa5da790040e424f87dab6d62d7e8461b09b45e73d09b075ad6cd705e634181f571d409b7337d6ef9217b9b97f3d59941d3b912af977302cbb905fa318dd607
35	1	125	\\x949b755d7ec801276787305856bd14f289f433c1e3ea147288976529cdb0474d2719d2b12c59076fe7aa58e9e6c1eb550b8776446a34ca526a446a168f1f320e
36	1	400	\\xfafc52a6c00c1c53f9d47186496cb9630a1826287b4922425deaa19405c7c80c4562bc307118a1c9d287e42081aca90074a1ca0e6ea780cb15f481bdf1a9e909
37	1	124	\\x27c96636e608fa938b7d7acb634bd0c5170db13315a521573f58118caa10747280263821a6c387f8fed2a39128ffccc805a52e7ef762f3682a599a9d8d87fd06
38	1	354	\\xa69177f2165fa71d8d61311af4116fe0a311360e45edda9958e837a1e243a50e3f59f7cd16400096a8d4ff877c878091e08e330ecbe8c1f35d9f97859fd2440c
39	1	59	\\x05298d69abf1d98c0383720d51ef88e2d5f03332d719fc73e1c07b03de5b19f0e25dad1a8598896d0b6b5d80c97ac8d2a8f1512441f52727c9bffef481d71409
40	1	4	\\xe972cab1d49bfe4aa38e3d6f80716c7ebe41f6a69383848e66c03e6a5617b4be298159817cdab050f6a4be89fb303b9d52462bb7e32b5bd651bf68e3500ec50d
41	1	159	\\x2b3d3a41d6c2d9794fe551bc49e980120c7c67083df6d5b03cf3883fdd5365ac289eadbf158b1e4770150ca585dd29c638a09ee6db62ec4aea288157c809e904
42	1	234	\\x377a18c81e61d63f0e4dff89f5ae3370e56d71aa661a5d8b74d9e28e2b6930262fa33ec27747ce7591d6cd26d0d32e582c774a37a4a01e9335adf5918a36b50b
43	1	294	\\xec49bb93fb9a5fbae49a59aff906f0911e3d2d9204e8fd445563f91c718ae1b977e2de4d5c159a38b46fb69f9f80af06432f0625cd023cd91c836768536e150e
44	1	383	\\x1227d5120a7333453ed978631de0f68f1b15bc7355cad8bd1d2e52d573af017fb156b66fa0ab92c6d13a07398b8cc45da7ee39bcfcca06f4e9aacbfce9b52404
45	1	230	\\x88425a1cd8b9c30ae772f025dfc87b5baa8ba816b6dc2d2b2a685f3938e78f6215e6e2602ff9455ad438e3d5b456ee50b3612233cdb2fa86fe4de3795a9c6f08
46	1	219	\\xe7e690a92fc5ae554557f78e074682b12166730cfc0002755f75d299b7f734d32ab2fa72d457c7f1bc363420d2ee69b9ff91743b6f933bd122bc62a981bed102
47	1	92	\\xc5980595efd21a8f691e6af46fa6e34ac77993c6c675559f03d7dee6a70679c58aae478170140ae89eb2dad05c2ba4b14da098b712a03977e64276cebfe2090d
48	1	156	\\xa256d8a5e328a7eac82461fc9ac96cbadc6e8e63a49614feeff5e8b925b29e1b294944c66d61e44f4fcc24f266f2b3aad844425e18d5c88ff0015ef19bc6df06
49	1	39	\\xe729d58c15bd9267f66f94d12952e3826810152507876b400c508c0219f1a9712f24c7f5e7f68563a373bee27f703bdff5188a19b8c4e7018565554647f7900e
50	1	190	\\xbe158000c595c072f7cb6f4ac52985fe50304327ca9525eefa44fb30d4a7733083a8c72f9107380806fa28ff58cbe146bc5770c1deebe8470e6b66126eead902
51	1	82	\\x052a7765f58d0a658468bbe6844724f5a55d70808faaf681788ae33720817bb549784f81f13adef5e0b5960c06676d3ab90f984552ab4f5f3bbafdae5f4ca805
52	1	184	\\x5bbcddc5e6ef3491a6b8698286fdb823762b72721b44f57e59efb0aa083d14e7d63ac60af5ea778ef860e23df8a8ce308454f8c665eb4cdf4e713ad241c44603
53	1	25	\\x541fe8d56eae32cc68ea007952428b57dd09d7b6b7fd40d5999e57376195cfe930e80983c44159f89b5ef76aeb4fb8168b1b8e9002a43dd63b906f87a90a4b08
54	1	28	\\xe898c3f5e2e0469550937fe2ad1d9a8f7698aff1c8747f46a802397d76126d8c903c6df01aa359e9c5575e38a64e7340f9356e44ab23b585c95cf88146dc0a06
55	1	211	\\xdc2ada108f5b6769ac20b3c6984a4d1530092073b4f03d9a16c3da6a0dd81e26f235c66d9f136c6fc4219edf91883aaa5e1858a0f4da4034ac6b4b89503f8303
56	1	273	\\x46704b4f75a4f96dd1126fc19a4a82e016f813aaa8f17e33903511ec84f33503194f7fc17aea0c0d4047ba6add370498fe5fdf51dba17f04ab3c2d425b010c05
57	1	113	\\xb8d8733e9b123683ce6a2554cccad76114e3fd74346819c8df188dc37fb522699071013adc71773c791b629c6d3988bdbe5609138d7d81ee765f46dc7474f70e
58	1	335	\\xa1501e1cda72dae55e4d216f81898942cc65741d4454af393d09ff19091d622dac0f145b5909796a590193641990aff173a7ec4c5238ba85b6278cb5bac48a05
59	1	141	\\x28768af32be69ad13112603cfebd02bd380fba623bdaebf0b39ca8ae10bef38da5d17856ee829f2b491dc6d3354f51b63bef58c9d63969533dee201350362d0b
60	1	388	\\x4f3820407162311295e6baf791692a5b9e17b8ca77e97cdd0969a2e0aafaea2d89b6441cbb93a2ccff687c6e52f81fd2394201448504afc8a542c565659df30e
61	1	86	\\x77ef2389a61cb35892f4bbce6b23c1fca1619c8082b46d8b7dc15d4a9a1f4ade19049f741ef333c07b19b8b75dfd0ce18c276182a5dbe13837155523b486e10a
62	1	283	\\x2dce0998dc141e6433fe130f97f15ce7ce97288c73a3f3c3dd9e0a468f7f70c589dba42152d32cbd43be9c3db4b27bff0a8b0320126dee2b72fe2b3a1cd9330e
63	1	146	\\x440f1f2a363bbc061197226a071a0aa9cd81966be792d9baef8839af4fd41bf5215817a7712afb17b707d14eded6293a367331dcc326c64da534a05dc1c58209
64	1	314	\\x813638b5ae1efd7b0cc9742c04771d3eb0405fc35ab3f20efb9151c52bb94dba816f62f478ed49a56d963cced157944d37118769d931762d4229b6d787a8ff0a
65	1	126	\\xe267a65398d7717bb245854884f1b7c931253cb2c1fac3a37482b125bfb2732a7735fc4b8334fab9067b0d8f9e6d5ea82950aa8605c19319ffce693b340aa003
66	1	17	\\x0fdfa5f899d3aa80ea0a7742ad96b9d8a2bc8e8af8d1e467ef30ad135506ef9296695be92dfea804b9015f7d2e565981579e8a5e5f0dc45806701b48e900ff08
67	1	134	\\x30b410fb19a11f6fea6379a9be67a6cc042a11d66af5c58d79ada562ab79ff601d3061fc9ee07dc31a4e2d33e8696df75e787483db0161caab5d6ebbf0be8d0d
68	1	250	\\xad78b2a2f831247b8c01b97187b4f2b277a80c46ddd6d509618170b858a8b9eea38b46dbc07fb08c4f6c1543e4971622671de1f2193405463989f2b430f65c02
69	1	326	\\x82473e9ea9451c85d301ea346a79da8d0199f0cbedd170c51f817da4e8f88f0321352e6c33b1340b4e79d29fb7712e7ceb055731e89071fa090bbb7634f35c08
70	1	319	\\x6eecc5319dce08a0060dde823f1a3d237868386bcb9af358eb442e98900343cf514f53e6c6a8c958ac587fc5202d2f70f280805788b1f2a71d3203333e69220d
71	1	402	\\xfadaa76c46b7fa846f67a9d6d831289bf29470358381032e482e56149f866199f178466e65775e7b48c94097876cd9ac744c078a20055710fd537e3d79a36209
72	1	368	\\xc158b1094b17c92ed13cf9b4ed09a2bc303c326e0539d4c82ac3055f17f2caebe66b3d43a79f6f948f40bafab8317f6b008e2e4f181033f6e446ece224702201
73	1	401	\\x4b90fc4a6402aaa561d1d65edb245f68d46755badb15b3d78b4888e7a88d660434b07c76422999d50cd5777cd65d49254d5614bd23c7c1743624ff3750a5e100
74	1	194	\\xb9c8532b5a7a5f715f3ce097c493d97a8a641279f20cbded13079ed31dc5076ae0792a5e0b4796ecb5ef143ed646af305ab3bd2fd00ad4d7649b51100e3ae30c
75	1	309	\\x51226d5cd053acc922026120615cde191ef5eee73e401263be6b227a60d9e5f12b2610803f8c76a8306f39cd82a6140bc3361f7f223506c4e9879c946a67e900
76	1	398	\\x5979693c198a274eb5fd46dc0012b9b6669136412f7a0af1dcfa512add04e103ad71d779b3cbd106da6aeff17a375346711d29b30efb080e32090f9dc837440c
77	1	378	\\xfda548d94100a0c9cc318cff1b7ad74cb0b5590b1297200e7d684ae2857ec5bb7b49c0e43ba5d2a36206b8f1e7f8ef8c0fa591329020ba61baa6681505c13100
78	1	143	\\xeab124acde807f39b2792c80b4f929415d3b52f1523ca00dc8d92b375d1ff77d1df70038b516770af5117ed033858ceecaf23a58980140eb4b4050253ed19a0f
79	1	238	\\xf1fb7ded53d08bd23d76c73b1e78033902c9cc50e2e6be61ed7e515b62dbcdc0f6fe6535d876ba3dd618bfb404b32eb738b8c40e85b4b0d04febdf16d7720104
80	1	108	\\x6bcd7e1ee6d9348024bf1850921b9426c869030d89232272006b69e009da571de2c7bd883d7a9f1bc8433d480ad33f2a3a5e7c61370b25164d9cfb09f585d10c
81	1	149	\\x3baf9fdd50790f4a80f24c0df82d10992dfec98d5f50112dc57bc2c12bf66e351f7f5a7d83cf68b0d08fc410e331f1b07a6aa2bee86ffdd58e61ac5f427ee406
82	1	72	\\x87b74ae5e60d78c7b1de03c65eed8941b4e109c56ea9f631feec2417708265db48a68a32a1d21ad3686f4d1bcb35085bff0e5aea91fcc12a15899b6132a06707
83	1	408	\\xe21f3e692b3b532460375070b03fd9513fafb9a4ded5a5d5c02e7b5b785a75667a999ad39877f56b7c70b62c8b56f094f31fc5d71fa429392eebf0b2b3566f01
84	1	313	\\x1d64053abbd94385a1bb6732e3b0b7e6a0378ba0473d99f88a7d8f6008cb84ca530bc8988179306f97c4a2554374a7d91464669b57b0918068d1543d7647d406
85	1	337	\\x5e92389c8eb7681bf2c6118d17cf8f635627cc22869c3dd9bfc4af89eba5ac8c67c857f953cb68fe4984cb316fedff32686facc3635715952e6ee0bd24466a05
86	1	209	\\x00452d29d48c99fbe71e0cf2a0e88f09f28768591094cb58de46ec37edb5eddc342ce0ed1e3a237ae35023d028fcdf78204f9181b98d06c736812611d86ccb00
87	1	353	\\x6c96e0175bb450a8ac8dd19b1af94345f5033b8d90a7397f16935747bbcec0248f95bebb2c6c52c8311db3a08888e97d959c80a25a3cb1576e11883f13a0cb05
88	1	157	\\x56f6056293f360d2aa09fb66220c5a5a6497d85a80b3ef477df039a6049ca47dbca36c796b48912e476d0066149ff38af49ec10b5a869105a3080481a7a1fc03
89	1	123	\\x2ab2af3997dd3e4529e1ea73f3a35fd9d60d8a1250700badb4fe98120993cd7925c3a2f4196f28e2c8803440892c8638752d6038a666be417dc33d6495b31806
90	1	96	\\x139f4bbb8754df00edc794df79026e14fb1e640e88d5613f858f25cbc375581c910863319ce43f9f99671b1a76e9b016cfe7b5ecf17bcbad5e620379a572f804
91	1	224	\\x587a397fb9518148144f027b636cb44397b934fb523b0decbde9ac8224d85f7c4c404e2d463966f89ea6a762b44d00a5d69bee7e1e44f5bac1e619e3bfae5b0a
92	1	14	\\xbbe8db8a51415b63727104fd350892979832fb650e8d224d89bca0bfeb8d84bba2be587ddefc7ed9728dad453fe4fb314440cf2b9046da4462fbbacbcd57e600
93	1	162	\\x86eb62763c805e265de745fc9653088233a10b8e9bbec8a4c709e7d6c14b04c60299a41a54506b173b5880bdf6856f88dbd98dc64363ef7cc2b2b480363e3f03
94	1	199	\\xac414f4cd4a33f2f7fdc0e976d43d3b267cc32aaa4fe4e2288e92ffbeee3e35db28f78523a9190c29a10087c331e7cfbaebc14bc6ab89243746ed9c3435cb805
95	1	379	\\x0c5aadff342406fd9a1c33faf0dc6cb98d49e349c8ea39cfe270bac679ef5662cc9288c0161ebcbe58e14092114ae195d2d588ff74e1db046674c7a34c5e8804
96	1	300	\\xbbb236def94e91ce782fd0baa03b43a835e58ff26009ff3c6ea4581f4286b3f94c8d56de83ffe75536c5b703867a0c4ac28a59b8fb3dc3a8224ac38a6ec3de06
97	1	121	\\x11b9d997909a8dcdad96d522e9ee1da9fe3ddb5afc6c7317de9e25399373145aa139d68736f2efcc3bc3b3b56a444cbfa9a52c21862f95bd9bb610154fb32507
98	1	389	\\x82070036e5881b70efdfdd2b732e8ba27c2ecabc0e8c3419a7cb04cce2ef5eab0931bfa288fc95dc144baa5b6bf089cab4eeeb419a067cb25e323eced8a07704
99	1	44	\\x517fc3170699712ef834af764504e0cddcc0e3eb7a696c6953dcc08861978228a8e79b1ab3b4e2fef2ca2168ed1eb91bd1779e481f4d0909d1764f9b3543e101
100	1	38	\\x94973e86dd195d6663b2d95ab515bb9211fca5766e18f90084f759c5958ef6493fe513b5165f28068fbca4855d21b0d62cced6cde898d4db5449f0f89b314606
101	1	188	\\xb8acf3636d767156a3705370f497ddffc4fcb0ce081bbdb00a899ad3871c342bbb846cabbcf018b571ee5735a7066f059f232550f12cbe109d2d19e6bcb2e306
102	1	58	\\x16655c78531212467cdca054d9966960b8c37e4010404c93d732759674ab7d2c3e5f47b586aeb89ee2d2bc307243a1dd3c15e2a34766da5814d767be059d1209
103	1	241	\\x6345b62de137486a3079ef48c26d2d3fd6baadb59285fd5a25cc38f3f2fc8ad3e42c58c543f48562226ff2a4a3b3d080a3623b280bf7044da1ab01119ac2880c
104	1	377	\\xade1ee17423003e66c23e82282f9f8190b9e4647205bb6f5de01493c9ca18e3f1255a2b5cb4f962da732d3f772c809dbc265c51233031651b5c469c68ad29b08
105	1	305	\\x00ff4c0aedc0296f38f11c72e0ea1c81e49238acd2a8817a4fe549f469b46c8e861994f12451b962847d95e3524b47fdc3bbff6b20e0ed75bfd714d39868e60c
106	1	304	\\x79db5f2e92b26c878fc1af55f3a4102b7d67d3707c0ff62c95df61e18448ee1ea77873d0a867f2cfb04a560c0521bba54f1f34fb9dd157dcfa018aa13dd5b90d
107	1	56	\\xcc35e012d61ae979090af5744c019875466b5136052075ef90d38d0070178788d2f4af83aa011f456e9eecb6dc9447b038bd4a1d1cdd9742597ac9b6ba4fab05
108	1	168	\\x608563ed86eade7792745d2ea057d755e44128b55b1a309b45aac290454f2c1858bff9b74c243053791b7a3ecf8e9ce8ee0de9f592de96f8a51f759ae835cc0b
109	1	331	\\xd1753b6d059fd5c326497168ae56405fc3cb0bfb42c77107b4c1097fe7a9f475fa2675f653aee31677e6670b7cd60b5cd4cc8b528bc47e7a35dc9ecc9aa75f08
110	1	207	\\x907f53b07b3dc35c0af3ac75016c6a133e5d4cb4c3a8489e914b3e0d661f0063c5a2bf1ddb055b9eb9c43c90a7f26264f23bc1c174f2557fc4f4415d60910209
111	1	97	\\xb8354025660146c8750609b23f522e39bcc35eb4595e7ac162625ad77e63860378cba63ad55e4867deab853eaf000d12b1be87b2279cdf78fbf5fc139c5eb902
112	1	399	\\xe9c21ce2982248d11e65df933684d988ec52576094f1c00bd70679fe1dcb566449c265e4b6a115dcf22c6ec2aa45dcafb0ada6fb3a7ee4e5ea062ce95dcce409
113	1	90	\\x27f72d64ed3b6b91b856a647b15581a18bb48fbe007c08dd8a55d87b2a8fa7d193065c57d3e1a53cd20c11391810854e4b7dea8fa7e5d52da71c85b84ff7000e
114	1	363	\\x26049c6aec1ec98859ad2f8f6ceb98d27672522b3aa24759ca36e4953ce7caa63246a06759441cd11031ce9077c03287b2f415e784a148fb29baa7b4ea0cc900
115	1	244	\\x451d2344471c85841e138ae97c6d71c3d969089075fa905e1082ad073f605e359f1ab7d0b30bf2ce699027daf6b9bc45b97bf36f8436cde44fad35a0ff467c07
116	1	137	\\xf04e5f2e978ad2ca8919764bd1b531d5972dabea90686f19e7086e585d7d2167608b079c654e46fe5b9880ae05c33cfed0ef7cf602bafd7cbf882f56e1e99004
117	1	254	\\x056bd2e67027b734105f66920291ca72d75f666e0370b633405bf7e9b78adeb292d57b400b2a26082465abd126f5a254bc2f78aaa8e4069beac4c934c53ab80a
118	1	403	\\x90cc912ee4a58a71a04f89f6ca85927557c48e353d61024206ebff7ab45a96e289b0ef06706e443e37c41621f0badf8007a919e1341c0ca0ef537afaa66d820c
119	1	40	\\xa580145bfc74096173e2933158fd368c84d2f5db1a5bbe37bad49325d8ede8eb0b29105b30cca560f5f6ec06d4890dfa75c676bdb36220ceff71e5ea1ebe930d
120	1	333	\\x40a2f116c74279975a9b5774765e181740d047d98ec569ed237f2a75a8f854c7780b9150d0e67383d64360553031cd1e3d3c7892a0e4e418f1f4838f7d91980c
121	1	320	\\xcff00a3c82ecc27471c0ca7be05916f8e7c435d7e47b5d9f31c1aadc4ab47d0901f474d5a7ffe6ccf8c6376e879d19db69e3dfea0aba40105c5e38522d754005
122	1	174	\\x464ff759f0f23908fc2b0a249f1251d2080204ad6eb8e341c08ffb81fa5e0715b01fe9dc0e550c4e9de9f7c29c7bb4c06576d5bd87df36f5e42fefb8d670a900
123	1	195	\\xc9fb0d22766923efc4f426f936fc1d679dfaf63a320aa7905135a2f171892fc3549263814b59de8dba0ebfdf7e5e917b4cf7181b0e061b419c54979e4eff0706
124	1	130	\\xf905dadb1bf10478b228006b1f6535a395d58611c6b4897e788443bbd470c2b89ef28a15c4a07118b409590e29239d7c287dcc538f56475a1f39c3d9a12bbe04
125	1	274	\\xa57fbb68ba85a142c47a3324a12f04313e6d5bf3f9b1a9d3bdfbfb69c253e5141b39f62208b35d1782d5da04d17b1a258fa8c454d71c6a5a27cd8835c1fd000d
126	1	158	\\x22dbc5608a770f4a658a78316d8b12c78f0c6f9504ce011756f956badc35b391abe50de27b416b8bc56e6d69a16b9c57fe0d5dec86f5b96887f4d1220baa7209
127	1	375	\\xede9c42feed6cb398812fb514520b9138757846994d986db259a5d7901c241abb8ac241a1cc34d16f30068cf22bd0090b81f134260f6ec3be0d1730472109e09
128	1	369	\\x3b993441376bd6e963cba572f29b89254ed83f2b9f2157d2e18f140b0664cb3260e9a84ac94acc2c994d9224c0db9a278d3fede54ee5a50da1fcf2eb914ef50b
129	1	31	\\xcae2c7c23b91e23a7107b47cfa3f6c81a8cdc66b8e5c7bc250baaf0daf81fa5635e39d4bbb9fb58c56cc35b7c29c895906c70970d0704050c2cea5dcdfaeff0e
130	1	78	\\x1dde19b05c4b6670126c007934a51c9070ffa6b0876224c4beb4fbed234652e7856d2bfe2e34ea06f1ad2c386eaaec1a61ab45dde02b816199383a2dd6bf5b0c
131	1	406	\\x568950aead9d18c5bd88fe4e765f19fad57e5966d44f94b5c36307ac3fd08c1d838c26dea0f570a98e107b2bb5fc03871b7e44c09af8a4b25b03473b9f027502
132	1	173	\\xbbb56c63f581ac3e7ef20c184ed612bbacdff4ac1aa7612b8f85f74880b78b2c254db05fcd4ac6495a549fa941f61ba282b60cef7356e293e05b48f436ce4307
133	1	351	\\xec1177356d86e19dcbfece2523cf596658030846b0c660e4699aff76c095025eaef2d6bed8cced6251f93602cae723680c1a628a551e95bfde4575122d756a0f
134	1	268	\\x3acb6c0bbe710a65a9e4895ba850c5bee93c083fd2363eb8d435bb010d93e971080e8ba3fadb21a43209c8753b167c4ddfc3e30817a3567a7cfedb4317ec550e
135	1	390	\\xf6c2f7d678b40fa5c57011ecb51c329f0df47d1aa7b8426dd635e7c96335da58fe2e0a11de893c3ee9e9dececed9cea6336739ad1462107cbc3595debe87c803
136	1	79	\\x5ec3cb3244b7fe226ae0f5a78372846c30b678dca08999e7ef271198eba5584b85ba7a1d2c05dcd5de9a8f6acb4eb08cbd6dad42791cb2d4cb7252c772c33f0c
137	1	415	\\xba9cd20185ec0ef04be25d766ee9448285d4d1ba064250a89639c0158f8f6efb7e513920d4359909890acb9683ed8ca090c4e23900b6a0496158eb75bcc47604
138	1	276	\\xcfa797370257972895bf72bebd352153651dff79e4eb41f199aa7cac1d20b02cc27f6c0e6b545a4d5bdf235661c3aad99ecc22c93b3b11b4cacd183f1ea00c07
139	1	198	\\xd32d7214dd2cd9437b57c01e03bb4d40e7bc80bd5cff582f3c7758183e9a0413f1ca9368b240aa39ab443ae45c092804f0a7948ee786a17490eae911ab6fd90f
140	1	235	\\xf0a1c0a9457a65af050e3bab8dfcaef48239caa7674b0dbe68714279c4ff5848fb8d9d45fe8c930d334bf22087ea61c9144cad2914d0f25ac8f76d579ed7f40e
141	1	136	\\xa4fe51b53b2ab556d8eee069e1860e39fca036b9aa0ac0fdec66d2299d2838109cc21320cf9a718a849f43b5908277414ee3a540eca7b731c8c415de1d6d1607
142	1	22	\\x5dcc4d07d52af3b51809c82269d1ce83af06fac92de18371707dc0b19129083dccd2a896aef6dcb5f5f1b90265dbb68ee98b763aa47296fdee329168066fad0a
143	1	263	\\xf1827a12a8e7050205a2e17dd485a3da516b97f0ff59a88c6c03c1e896c3e7c354f0e44e9380e6f25eb26d191430e0405b6cb2fa5b3e56b49331cb83b6a0a708
144	1	269	\\x229edc4effd18ce38e9810c06f0e844ea8a4a987709b913ae77daae4f52892a66961084f9b9015cb81fc7d90e72f2d7dd70c55a777bac918ea91b4589179550f
145	1	297	\\x520d613299f2231edb80b3a67b6c6d8bb7faa6d0bf00a6fd3b193167652e0f092fd53056e574dc16d2a44216a9547216babc278ac55dcd860556ec7d7fd0d701
146	1	325	\\xe27c81725ad09db0ad213a32c7cb8acd529525379aa68fcb0d497f42af997c56180d8c28f8fd5a12d5fa6cdee92a14062def2e29b7bf773ed4e699d0f7df2303
147	1	47	\\xcbd2f46669252013e7561b9d93cfd3a3c7482d7090b8e242358c40c6fab821c00985137fb220857d0d717776a8af019b86854329b99190c84a697acc5decff03
148	1	247	\\xcffcd60faaec6f4cab8fecfcd21e05a7e94696ccab2f98b5986c53a789397bf28e7553d072fdef0847a543a877ef5aae463d99af76df9f6afae75ac1448fd505
149	1	80	\\xd3193c5af77281daa2233f2b1c700056c3d8cae5d0eac853b1f39744134e1414e4ee7300bbeec571612e77d409472afb27aede9da1e8d19455ab2cddf0a25507
150	1	416	\\x522e3943edb23933aa1aa2c31a41906442f12d88c106cbc312d488af2cfb0eceae42df75938deeec4c3d0d863d90dc21f6562c1ace38a4a0ad5745f42b44f70a
151	1	67	\\x2ddd786e860c289fdfa9ca800a7bad30e2a54c6aab57e086cd8d022453e2e6a8cd26d6324dd5af6f5e42ec2516fa5060bf529d5d43dda5e7988a9777afd41d0d
152	1	223	\\xb4f02fd5666218a8b0466126135caf9baa8196ef46e4d49e202c16b75107f1e8e94ec0ac8a95463a51057d699fae486992d11a8b7122c3b78975f69476dc140e
153	1	249	\\x346cbb7a19c404c77a793838a0ad3cc1f39df448088c352203b2de0ec1602758c95fb7b1e7bc5ec53f6e205224407ab3a8a763aa5bbf83c00f520ec7954b5d01
154	1	361	\\x1ac5edae4ae12608d745e5fc06be9173fcc89e4488849d916fbd08c9e6201bbdae5d310b5500dde4b89357e146fde33e0368b47de3595fe13f6ba063fa85ad01
155	1	417	\\xf0055ed0f11a49ed52ab82a790feddf0b2b2cf15873a017b11a03efc5f4133f2f63cb7a5deabbe48cc3ab32980811f685a52c5726db7d368c96829a8e29d820c
156	1	150	\\x7e2b463cb28b5ef13064b96593e90ee63a219c9b5bc5080e1e12a64ff50e242443a1f281e0be595855d032051fa264a3097ef084818121b8848d3251d5d53e09
157	1	202	\\x4315f204941a61bcd4d6c7b70b963fe7d555da7158ebd6e3e681ebe4b4147ea1d3021480100cd79f1bddce47d3fd45af94000c70013b37e23d4b49d721fac10e
158	1	203	\\xdb907a3b743138c82adfc23b3a2dd080dfac50a3ab62aa52cd8f31a10af63468450814a1a1c5e53716c2e3e93f0481bf8d6721e588bb03fc98b5580f8ff7ee07
159	1	27	\\x4f1ac31e23286298b78240e27bd2ae7ee901d662d44ef537ca3581d262f1a39f78a1452bec817a95e8ecac190cf9cecacd77c0e5e7470c3af3c5b2bb5dbd9b05
160	1	119	\\xb3b97134df5ac49eadfb5d3fdf49da13aee1a15fe15922cc8be3b6a8fb23ae9bfff0f2fbda510ce2a49e468eb5228bd3b3a9aeabfefb07e172d581a66583df0c
161	1	85	\\xedef7e237614e2172b4949b1995311cc0b2a7da9867d11de8b8ffd1a70219d1758fd28ce8886930c3c6c546bcccae8ec4ba64ad87e353eab5b043fcd45205b01
162	1	312	\\x6cc73b58b938466dcc6cb9783ae399ee3f1f89c4b7c66dbe8859dfb42aff78231e2cc724636cb7ccec9d65f9fc4ce4da14ab35ef5625a683de92f51bfc5e4b00
163	1	60	\\x50b3a3c535a6c3f80c70cf3395ca160f0a7de2e027550f6026a9e4d9147c47e41933946917e9bbfe8101d5a88fdde709298fcbe4994e5d69f87e20a5893bea01
164	1	99	\\x25710c291531c134b9a962373631d922153c0e37f7126f64dd4ce0c6cc2d7f1e9dc856e680ef6f869f39e71e4e3bca4a6079f5006fbb33b153630c26e1003a03
165	1	384	\\x59102f784d54e469c51b4a17188d89a0fe76fc4cc1490f2547468a102e00f360ab8e654aaadade763cb6468edf7d3f256de86da20cdd5cb14436eb2e81ce7106
166	1	133	\\x8045c494bde94460b3f0be1ddd606940d24f8d5bebc3658cfce14ab84955ebe922b49f938df41315aba6e38780b66bb4fe3afd8b7cfc5ad513325c76694d9d0a
167	1	140	\\x93d224dcce53676c1afc475d0918863a3185fa775c7648988d09ed4925f89c4be3a8db699236b9b996e1cc712f6dcee8a71b509d3949c6b4c52db1fe73038003
168	1	221	\\xf53384c741d9918d52e97ef55215d58b288f6aea30e0a294578f0fb5e00495d878659fde4e6950baca6422b41a4f602135dc3e39cacaae10ef000511310ed608
169	1	177	\\xb1d146a1d2a195181b86fbd5099c3055789e1ceb3b49baa5cc5d91a357e893eeafc61e9204de9a1e5ee249e3b59743354ed508ced1bc25ccbe66d76427a36507
170	1	189	\\xf92ed8a2abee7e6c12ed11c703131d1902e70738fe96124c59e57671e250fc134ca5ac9c614b0cb82962b3ff1372f73d76f9bc5f8145cc5f00d0abac8c64860e
171	1	16	\\x45ec1e265acd417444976db5012557c9aa7c5b9b286b5d58dcf9c5ed2592676e3e445be85f0130a0283134c52673e1ad49a70556853ad6d37e5b9883f76fb107
172	1	63	\\x21b7b7470250baff8335723ed210ae99e61ac899ea2c32542821f6d41441a557b7b74c1969641677bd2c0df66e0be3cbf85d8295e85e770c3f16897df2112d0f
173	1	257	\\x75eae0f4fade47784d20acb214a4708ea04ca540730586608d5b4b6d7412669e9ac0f5ee6b7a0e53b962e64e0bcef923d8fc5d371a7f6958498a5e44cc718908
174	1	75	\\xde0deb514fafd3ecbb8675fff33e73620199f97ec308374c089498b354bfe8fd4ba68845a373f9e0c9006a370f0fcb101a61d3389e67954d3b5fc590ba08b006
175	1	21	\\xaef4b213a3895be40b89045d73618ce3dbd9cb266a6e01b7357a8c48f4702ca4fa04bc51e67be895f06acba44f1d85bfbc225e7f07297d46292607494f55c304
176	1	2	\\xd3a9626629ff71b5eb08b6137aca4cf9e4b9d358d3463146d5dbae84df0ffaa3e86529e5052a6eaca8972db886f93667fce29cd77edac7b4a4dbb9d807099f0c
177	1	352	\\x8f959a7724fd39c66766dcedb937f494d0ddc2d9c56b1f7971f7ca69dc91bf90473c3d384080f00b672ad3d95eb2619b4dad2a5e2cce6508f9284ad9260ced08
178	1	186	\\xc11da1205d8ac90bf6a9b943e2bf24fb258fcd386feba876b68a2124234dde71ffa40328d432b2984dda017270521e7aab9c206c9a28a63e08651433798c6305
179	1	372	\\x0d1c0aea9965e405189523c7d1cf978fcb09506b23501c8b8a1ee4c88150fb1178310f941d264285e87053330275aafefa18836a4b17da4df5737c7b53922302
180	1	327	\\x878beee3f833d350b7ec087c5064d6525e5c41be785f8bd53eef68a7f0ed71dbbcc08584f2fbcbe58ecad1ced5cbafbdb6c61227aca4c07905c4960addfa8206
181	1	46	\\xbffb5da99d18352295e772dc7f5b79140367459d962d52ebdbbb3b5e58f52239336af9a14c748ec2ff7b58ca3dac89eac7023ace57a336f7bed39f9fba184008
182	1	74	\\xdaec4a3bf90b4787ca5a4c1c23baa8eca99d78bb7426cb098601a573e3bf5601b9b35a449895134510a1d33452b669a48c0d5271387de61ddaa5271fae63770a
183	1	366	\\xbf3d57e6c71c49209ee04a7768504ea8c7e286cce7c27bc454dfdbb53994bb0fa80a78d41ec17500685f995dd4be62d1e77319f09435aa09b83985768169c503
184	1	62	\\x590630eb5ffe82cd0989964017e4cbe348eb4b4d50310c2130c523b1e8722de21afabba20e5d305f51f1e1f96a7f033615979ab871311ddc6b054546f5110008
185	1	131	\\xcd76abe095a4d6b8f3d64b2e0a204b43bc95cd29f6b00e056fcdd242f830ab983929be00bbf6d6bfca12b04d990c7adeef8175d81b355ab39cc327bd3ce1780f
186	1	343	\\x512a3e904f8f5716e1d1e6413833aa585ce1058ac0dc1e0b8628f9ed80fff200b7d9d43953a344147497f0fbddd4149d47ffef705d5308f7e2053ed9b45ed80f
187	1	51	\\xe44a29cb0ef0f7b67e4d93cef80483a8b1b659a50251c5ff2672d7b83c6b1f5c771915760779d0ba2556884cd385cf657f7e5475455618bf4b03b6335c11aa05
188	1	127	\\x6f06d2a67d516aee5fa24402e911158ab923f7ef8ddb7c66f476ef519f385810eaa6a3e0c80df6159f4fa058949dee389d7bacd15e14bf03b4eaff79f133f90e
189	1	128	\\xa4a4d9e7b4aba990784c90104288f620f609dd9b21bf8dcff2e40377d4f40644dcd5c6c62a4224c34a29e37a4e78818c556eaf43fba535e072567077be5cb50d
190	1	48	\\x30e6d9aec611b246bcb754e2f33b835447d7556c6dae7766db51cde97318b142e608b75b20215e53641a8b64ba270cd3b47f1eaa6277d012fd1faa79e0fe9d06
191	1	37	\\x8a437363a23f1b15a65414a7b9a7b2f4762ee7a01f6f2ff1eec9ea8eb71947f20000d31d1dba1ccb6909f58824af14ebb0207c42591152a683c61cc35289390a
192	1	147	\\x26747ef3ef57fe5ced93177eb9ff6df07d4d63226e8a05def48f1e47d5d740cf56f6db1b110123a4acbb5a4ace425d43ff5c124e12a72ed7549cfe1b445ae708
193	1	258	\\xa5cf547ed7a7c59aba90f3346f9aa226ea88c92f57c2c616e9768b6cf3a2cc3fc04f8bae1460b72287b67a2af53cb68f30990c3e8db87960261f194513618702
194	1	316	\\xa21fde6f673c06c467fe9510c4816373515874686b3c5541fe34deffb362ce5dced9a01d9d3ab2f8782c8a2fade0aa0592eabd979225a30284b92f1f5a11c40b
195	1	15	\\x79ed32d3bf0fc99b5b0a6e04dbfb3eeb290a6d93ce7f0b3875daa510115590406a019e67ac1a6ffa13e9fdaff63167151fe3af1f4bc02f0b7130ebf94120c000
196	1	95	\\xc692bedb39de6c1c6058a0530c10db386fa2f530e50da93184b30325f8c5008643b18a2f563faf41fd5551e5eab70c7fdfe5fedffc6c422d69f24cced1979106
197	1	289	\\xc9cbcf335ffb2d62f0bd9f4a90df1b75f5e2f21ada65a71fadfa6fcb7037fdffbc737bb1dc36d2ed578b4fda4009cb8b4d5be8d25bcb0c41eebe180390e45108
198	1	23	\\x0fb42900a81e990eff9c9935934029163342ce4a3a8e865177084c76dc3114fe07ede815fed0dfa4a4d42c7794534b4b4ce93040609aabbf3ebcd25f717b4f02
199	1	365	\\x7bd8e7281e69c9aff4641fb2fb4f3a5c67aad564dffed5671c906375644ab304fb70096435054bbd3b36023b7015893673a23d0356d99ace70555e9a5071c70a
200	1	216	\\x37002c8c67e72265bfe01c11491ce5095aab4eb3df80a40ead7e2ed0ceb3bb1576bcae4e0073dcdc01100829fcbb08b5a24c46f99c84f045854c35ac75de6505
201	1	66	\\x6ad765c4c38f791a676eed6a64dca8e695966316371d97e170d6c0d8c568f188650718e1574055111e092cc1df9f292770354173b4528f853848117dbe86e503
202	1	91	\\x9b3b87b49f616aca8b838da5bb1dcbf78f9301466413eaa926ddcba30c4f2f8b08b354c6f86aafaaa050102f039383875739306c0b21cbb8102699323f900b02
203	1	413	\\x4ba203d5794c49640443123c0610791797f9743aaa178c1f34befb2589136aabaff79e5496a95c0eef5696d91b29a0253f117bcecec2c89aed4ac56919e4ba03
204	1	278	\\x7398de7175cec6b7b71964791a2e575283b8c050fc717982a147a6bc5759f5e0d2c0b6cc2d7ab23f438180781f28b1a9892ff25c55e4043a2aadf6547d3ccb04
205	1	12	\\x750758a9c4cb08722b1b4603830112c68f18dd6d801a6dd310564069795297aee57da5540e2f4ac347119ba6103845b2a9d1b3f92cec1b17c5da081c34a07502
206	1	129	\\x3b49fe8f9581689c0b6fa369896cc1a0114f6b159050fed3ce86fd1ec3525a298f2aeeed0277ac116d99a5edd429d4b51400fe2c7050ca55c4acea80fc59df00
207	1	295	\\x3bc860bb9af667d766a9b18522729c560dbe4a29b0d9ed97b639b6000c1e6f7d97ba13e2e81c7e54de46ecf23aaf56c2c9e886bd09de6ee53530a4dcec304b09
208	1	201	\\xb747d23b2c34df0e66cec61d11047bbbe0cab7912695d48c75156dd36c5a7adabdd03a2dba180a2397b261ae819add87835e1a69b6e46f04aed75f8005076b0b
209	1	208	\\x6f9bf2e18f477fb5f028e4d0fe70bc7f140abe506b1b7e5786645264632a9d548ebc25091deabea6ad5e5c9f7b27acabf01ce1648a279fbe63d36a07b9413904
210	1	103	\\xc01aeba8a9b44004e97115befe96f9000280a82b7c470c1354d4bfae13f31bf4db47669a99ee1eb47d077d53b69a24864cf4813f3aaf86556968c8ad18f4020e
211	1	210	\\x7c86bf1212c5f80e556d3e05987314c450979744ce87fbb83b5aeed1f8922dc140f594e28f491b74991da884edc9333d37710c06af564cfad42776bf960fa20f
212	1	183	\\x301ba5655a36123bcd49a1daabcf54f1250d11fcf6337f852225b973679aac653b4e852c7ef3253720449defa72804b2120114eaf41215c8efe3055d3149b10a
213	1	30	\\x86b5280b228b1fa0489dbfe75f459b83f08fa82748c51f17fb5b5a547fbec11460134d0ea0214f0564b8c9203a96804b3ffb34d91879cd492ba30336c75d4405
214	1	153	\\xfe119830f6f420bf0a6f10781fe12caa5e3cc92f58fc016bc81ae107c646062c7899932a65bd2b321dc89248f3a8ec9bb9ea6cb9dad7a51a47ac0a90c901730f
215	1	172	\\x7b7657e75041e9041aebce4638127fdb88cbe4f2e4cb6a3b0aec755e5992f485885c8b9bdfe5265e463bc0921ec64f3ccb4d2d8cd815ae8619e2b6b4c7a0fb03
216	1	42	\\xc8ff1b43845a8771c190f05b388bf9185aed5dd1450dd32f867f6cc13fa178f41a3e53e9873e6d9114c078a3f0dc3eb031475cc9e83475e3ef2208ea2a64790e
217	1	404	\\x176efef209a26877df0a8f3c6a8131fffb522d9c60106bb36c3b3e84f400ab53a794a57b8611114fe6b9b83c33a68d2b9ab9349627eae48eb59268434fc28a0a
218	1	148	\\xd8c895fadb105bcffbf7b8127f7835c421bc509326cebc3efba2fc11c5da6d485c286b6faeeab83f47330dd39cbadb59e8a1ce5f1fb520421324968aebf39f03
219	1	111	\\x3b4e6e2578459e93f75ce2e029062d779a728c044587fe52c839ced2a2ddc664fc07a9b4be8f16c75b31156dbcb1ecc041fee0e972397bc78be4bc4e2541d807
220	1	93	\\x2613424ba3b1bd84715531d5067e78ba7f58f90c107bd75248b79359c73f439130f11f4e5248232b7a87f0e6907a2f3972fee88b97720b2cd5534f6d63dc2b00
221	1	367	\\x78ab808d679b8758bdee987eb4bfbddb03db4a2510e14d778a344b999204bc3482ca12524461802bac633d73536b716bf2071561229afdf9f5c3e08d0777b103
222	1	410	\\x45bf9d3f2b934dade94e967caa970482ea2319f55cf81b35fcb73a54b2eabd6c1c4ae4d6b46479858f1355aa44a456437f938343138d6fc9adfbf323495ff203
223	1	340	\\xc16c11a8f289eed039f15e99ab00057d6be05575db3b8c65e6bd9f09bc96744fad1f800c69b2ba207b5a2c77b3dacc9a2a242b77f755f0932d33e12c6a51ac00
224	1	83	\\x973ed130668661ae6e407bddb617d0a66eaaae71174329b1dbe50d084d2ee22531bf07ec9b78cb88c64fdae87268c5641aa2f671451de4d0bbf3f6584156c30e
225	1	392	\\xa8ac4f7f6abd02a7678888141e999e0c835bc70d33a5cc28227c5a37b781ea1141ae5c4c4717dd1b402aa1a6a7db0067c839b57b88a3551236cda488b87cb607
226	1	57	\\x3152ee77241ebcff1238a39ce568ae3b9e086b557fc92ea46fba61e9705bb5c202095da2dce3066254917b217880281d0334b2cb623967b1e19ba4d0b2635603
227	1	246	\\x66bd74aaac805dad3dd8b6aca5ae7d33f1899f311c7aba55a36dd23b42a45620fc7fb7f32b044fdec193cce3e44557f47d37c4a5d3e4d2ea9cded864c24e790a
228	1	252	\\xbbf795b24a8f3fc74f2c9291eed1313afa7bb5a4897706631081ee42bbc544b1a1f4748e03a93135b83498dfde3ecaa47b6b3b3840f3ce81ac7e759dca751d0e
229	1	391	\\x88a36fa6922caac645a677b02d4b2df09385cd01d50bee1c47a78860f282b14a6201b2cd58f440826189c1ee8d9db79a2e4a0a1479bc0ac9132d839d41b43c07
230	1	298	\\x81f3a24184c98b0e75d0f7cd107c43027e1143737633bc25fc6dce2e4936696bf2c5b4cae5b2db13073d9673c3cb525c6b534e97057e528ce7531aa1fe089b0a
231	1	288	\\x2049a1dcfe2e4e8011a2ce422bb9e3a39ac5b3caa3518eccfb8c9fd6d425adad0486776d8e44eff9d264f18b7fc0036d6c7e950b6e6b57a7d83d863c789bc10f
232	1	165	\\xdc1a624723c003a4d988ad0795638e9d8b731a99f12f2d0f6371171a8fb4d94eabd93cfdc7c74e53827b4205e94f8ec11d08d35a12e0d5c155def5b027dc5a02
233	1	166	\\x7ee672d6496bb08921609f777efb6ea8de65a3aa0ad77065326ba312f9463dd9626f17560d9d57fc97056a6649cb3724527dab6462fbe290ac9ceb559a5ab509
234	1	6	\\x506ae61f2339e73ade4b00985a6f17e7911f856d16cd73cc4ef8cee91ca9abbdd9825c4e4324aa180a12571cc587b84245a50775836bf037e9fd12724a7e870c
235	1	36	\\xdd0ef3bb2ef77626953822e464eaedb599720d892a07d9aa42c2257495010589c8b60d2928f56c26cef58efa49405c3a8e0dcdf81ecf230c7f36c589960e3c0b
236	1	332	\\xb2c4603e125272bc32f8bf976020c207ca645d6189a02f9aeb05f1e4c1e618bff7a1bebb6ae5e23143e10b73124ddf5f3fdcf3f34225e05059467e19588b7e03
237	1	138	\\x345a0a2f185ac24a29a938e477e49269d5315366dfed5b82a8892788633d2d8ce7dfd540b100e64816b474a8e1775202cffb4a104330f5eac8c06e20205bc302
238	1	260	\\x1595ac66d89a832f91def8cc04f94c87d0883e02981c78792fbdef442a22ec55cc5c8859263fc8f7b7877d3a21905c989a078e2c1ced8da12d1e3d28d7028708
239	1	200	\\xabba56bb85f0e58a7352b1bcc7e3d8fb0d885494980ad477b5513a906b1b7a5028fb40fb232bee8c5e5f43f570857554fee33968609ccffe0accd30aa7216708
240	1	286	\\xc6892fedc7da522f3021b7fb26110e7879c1d7c4c75126b8d4f3e2b0198425fa753908b756e0c5fc9066e70c629ec7f74fee55da74bb8d368b719e50054bcd0e
241	1	291	\\xe64f33b2fa318f14099b8c7e50b1ead6cda9baa7eaae21b3531e7e2f269987139f50ae44c63366aebc2e8c198479c49581b66c879e4490577db68310f8bc5909
242	1	94	\\x11163a1a37f543f5b4f7074324083a833bcef13e421c9dbe4d620833362c3d043759cf5a443ad68774982f21a035ddda5fa8af16c93ccd8ab65ef9237d9d5f04
243	1	396	\\x87db7fd432a5f96ad754bc8451610ba2488dcd53efc7d7cefd63f3422c7af3c283bb554352d8fd0b72950f712134d61cacd61d9b4ad0807879c897497e06400b
244	1	161	\\xc003f3af7aed840cb5446179b352d745d1f7cdddf82d69d135d81d092ee9af5a47d21540450556f7215ef0e2ffe78ee212052e496e6e2caf5427dc561aa53004
245	1	26	\\x9b9f31e46d8d81053c924a1a29c2b0d3f29277375fab106a747935859502be83165c87cb2dcd5276412b00e25322a0a613533bbcffe17af2a1711806a7a3f704
246	1	142	\\xb70833794cef6a3e4be5e9a9cb0a35da682b7190be4795f187682b870a1cd7bfd8eaaa2b023bfbf00869b6ba4e0efc411c64bcb21d69d02c25179c36b21f760c
247	1	248	\\x99c04f41da9dcb0fffcad4b036730ec37b4e1442f99b3bdc41506e60f2eb47f311b2cc41e9485f7060974cf16a8a8aad8173483ba6e495c72ae34d77c4169c0a
248	1	279	\\x1522f4d1b4db1e688e045c0a6e585e4811dc34cbacc4ef8804289d6bef816fae1f24fa9f7338329b48d1d81dff83af2474f74bd6d2c47ee1f623ed2259740a01
249	1	160	\\x1c2d1801b2393955393b70b3bc54493817e20d32d8446db904ec0f82df36f21cd70ae898244b416bcf849cffe7268377e0a96a0780f4dc4ef4fc104ce873db03
250	1	346	\\xfb8bf6bf7b5502c59c69de1c8b2f1ee4946dd587159d1cc47d2c95962ada667583f6c8f47aa53e5ac78a5697bde63b8da9a13488e5d9457821d46a04e7d3440b
251	1	24	\\x9bce2545bd6996c25ead007d730a61b687ddfd92433b8d7fa6c460b564480082879d92c716ca91152b78804f02c7a41462a6bd93ec104b15406569ca92e47908
252	1	228	\\x85a8486967dfbfaba7cbf5f03c51a763a7cef771066bb05b5cf5f6f39ea819b3e8f67c867929c3c7331e9c87e35d12c600da3fb5953fb8019be1fc0bdc245303
253	1	255	\\x9c77e9affbab08b0b36738a81008c57937fdd62e21f221b5a66a19569e34cf1ebc0b4e6697df72208b52e86710b4cf4fdc114c0bf5d4c206a0b3f61b32a33608
254	1	175	\\x1eba214277002b0bec89314727787670674a5308b9aa7f4bc6cf6bdd8a20e063d914cd081a878ae5065de2d2fd0889282e583386252c9ad7b7c9c9b62fcffe05
255	1	409	\\x11fd90de32bfa1386ffab976f86ce5f9824ae8da39004ba976f722c98ee3013415efca5dd8712f727039656663823f759184229411785609f6d7ba72581fa502
256	1	135	\\xc5cef3000f5e31e5207b072c7674ca294ce348a888a3cb4e4d5dbc0d2ddb7fcbddc758f71eb8768547293211e70b74a168f41b3011412d334ef381223c78790c
257	1	220	\\x52927ee6807f1cdf5aa504228f8e91105008154e6289b63a5c21b4e3e0c7666318f8f8dc7f16381b7859f64e319b25d30ed76d11ff6d78e59a7859682327470c
258	1	204	\\x9f01bc6fb23676550d05f496168a46b028925d48d90d9f87d0ffcca5a20614ea2820ada1e4ff50a9560feede227aa639ad4fa8713a43ffa2a562c0db89bebc05
259	1	212	\\x73279a9a2bf61f39c6a1947eb011c82a1e8fb99dd2ba06f7f4ebbc9b70569f89749344cda6994c8d4a3d81ae4b53c20c63d8d4f4c2412f42f4265642ddcc3101
260	1	49	\\xb1e038fe180e6c334ef4e6e8a94e9c7a021e365de0f34e9b0eb8e38b386fdbeb50289053cccf0f21dbd219f0ed80901342e5407acb3047a623f2eb8c2e361107
261	1	371	\\xb0655ea0d47ab01b24c201d386463f9171e394b91802479df0ff5dd0d5348bcdc8f674abdd9bc89db1a90bc694b168693d798a602a731e134b6cfa13b8b1b506
262	1	382	\\x2199d79bfd2c99e303ad0fad012f1fa1882b52fd6222fbc8665c301e3f283663aed12aea863d2a8fabba1dffc8a3b38ac5989d72f720d322ec6cc245403ba80f
263	1	170	\\x227b1688cb7e355a7e410760d8b51c543b112173ff2f7e7a08404999c0f966edb8eab1b286d29919e56f150b0a3256183f0e4cc3dfad983fe83b3977793a3008
264	1	100	\\x917faa8dcd1795546a74f88df27deb4b3064f55dacf2bebcfec23a4d81dcc87cf7ad9718e225be760435593287d6190239975789897a4261fdc336fe702f1809
265	1	45	\\x73d11279664c4d908a9b6136c44c15997fad18535ad7f561e2f5c21c4a73298599d795a7696990cc1019080431447d554558f31a3372c24344ded80cedc8fb02
266	1	318	\\x2848d7f2d409b7d67d642d6fa25d7b58e98a983480b03d12d4807bfc0b7c080b41f70081725d5473fab3e3b6a66f8bdfac91c0dc0e57018b424e4afcae97de0c
267	1	107	\\x8cde1a2cf195d9179ce12964c59ec5fe4b46bd746fccc6b6159ff0f2383e5456fb703d4adb98124701c1699d2818b29dde03bc0fd33e24240024637d99057b0b
268	1	180	\\x1323f22e63628b5538519696332132dd9b7424f5e593e989de2ef350ac9cfe640229e98dbf0b14c2d90c631980c576e8ab97f3e2547cf1635120639b909e0906
269	1	330	\\x2c75e7ce1b4cf6a8568ca9d3b1bd69bf2ab18feba3701f98990fbe6ad93163ae9d114221530046e2cd98b61237917cbf17f0992586c8040c9544033916ad1f06
270	1	303	\\x877eabf6a140c65fc6e56e586aa6603dfe806d943dfbfab5af8acd97ced847b4cf9660814efb0cd735ed4d4af04a6f71fd1ae4c1b1989f09df2b6d1705556b01
271	1	3	\\xe6b12313f92d2cb5780b68498bc8103a3d7c507e9c0f9d6769fd4bc2ce3ee8be0694ada373f00f495f0aafe4cb3a2e6ffc1f2b2815aece45d519d8eead9d2502
272	1	292	\\xf683154c5064969422074329fc67906580fc09a9023a7305c71a54584d7fd9654fb96214aa71182b7d722d1d0900b49e351c5816e478b6daf72a2eb25679e505
273	1	197	\\x2102be40feebcc77ec9d04893ef926f7890a2755fda16d6ee9f9ac929bfad73c9d0b7d92209bfa5b2654c0f592e6964aa0c297f292a916f2fdb8b5cabf974002
274	1	256	\\x4a74a78a1f2db2aa4fab4967f649a1cfe4665d02e57b75bfea25bd216b329d0532950b3f2126bad0843e070cdad8be63fb93fc4cecac83d900e3c1594ebe4d01
275	1	243	\\xe1d74fb5c0945e3f4bc49617d8f31d7735e786f513b24ced0763ed811a8adaeeaebe2c34bdf06df4ffcb971d9e8ccf4d81dd5f2a3755fc128f44b9a267963502
276	1	328	\\x32e53be026ae893b8918901adb86b859b6b20f20f116e4481f6563fbb7bb623490b1b1e0e3cf3227aa4aea2b3adc7853f2b8301bedb92478108a71f6f818d90f
277	1	68	\\x2d8d9f25aae225f2fc0431c6e77c69ca6dc781d2e1f3e2c7a5484d0d5ca8a0a8970320bbc7ee41aaee6c1a90cfd090bea0f0a51240ae120893bc61262b5e420b
278	1	342	\\x185b5ce15709a29298e315db6b848a5e86e325ec18478dd532546c392e39b77d6b14c0a6609d3e3e2e27f14733de3e9e2b041e95bafa125c274ea864f8232d0a
279	1	373	\\x875109a6f77aa476b0d1834d4905bb2ce866ec1ae1fa9529c30675d76b91c84bd182425b73660d6764618c1c5082edec2e48826e8f9bda07860065ac63cf9800
280	1	407	\\xe140d31550c6259d94b2aafd2a4aeafba1d6d7cae508cb53c5e1c3ddc386183e95ee24cc6286a6911e6e9a13a53c4aec667c4783d890384e548c10f0943c3d08
281	1	70	\\x6d3e5b09dbadddb905a1714d6113ab4ce9155abe65e1ac3c7c5194fa12867300ae7be6f2f48b1e8290517c48cac752eaf5306fedf9f48c2363990e8652e0e709
282	1	345	\\x2b1b131fdaf19bf952fda11c56b4ae768d0550ca3da3f499be4f2df0ab4c6fd8679cd99b9d3af77d900c8f6b72bb0ea5cbd7490541006dd42418aa029ee0c80e
283	1	33	\\xf304d6f4cdd30c1446056e4b4faabde632167c6363fa7d56c4347ea26414f5cfe56f1f8f3a61c72ac2143fec1fd773ca0848ec5bff1cfd4103783fadf2479d07
284	1	233	\\x6edf82e069a1061ec0f12bc8e6f5950641470af07cab4921e22e7d36d1f201862e90799abd2abbd9ab49117a77911eb1a715689177b78ef920d531d0dc29f10d
285	1	280	\\x52f72aaa1ea6f9c23f8c7d2f562cf521c50ccdb9a469c5226b0204cd52fc3502e0075a39be75ce262366f3c6e9d5a2378fb19d21bd9f99810ee4e896267cdc09
286	1	299	\\xc3ccead333480e968c9065055a9325174b4b2d418427e09e082418bafe8c1dca6cf871df30f370469e08918f8e45d7097cfc7cf0822c72aa3e2afd72cf8f930a
287	1	179	\\x040e956a91d9271b945ef14c2b22c3915b88b2463ecc24ffb5dd1b40319028a4c51901d55901acd3bdf8419836c5774ff1052d2ce215b047c5c2522748eb2505
288	1	323	\\x63a00016a43fb548a4d9d41518681f4136913cd2879554a94437ce3f7d0b2ad6cd1c334915336096e06279e6332b8ac6f37a9180567fd541cae0fff47125b00d
289	1	61	\\xf8172eab6febcb0ef094993dd931a2db7d8ad6be9083e56c9520242a3acc51bc164bd2560c7363203fa690cf9352590f2db700d10c5d6a5ade5fa5a257819d00
290	1	334	\\x03d06e6aa8cacd6c43987693f76e45474aa809d1360555863607efb4df1a2185e11e04ff07ebef8f308b565f6a234420725e49d683a553d389dba9a8deeead09
291	1	284	\\x77129193e391d2385a8061e04aa21bf103ef95795ebbd30bb347b19943e9b26aa4121ffd65861ac37715e8255ce3a08aee74c55a23e24367654dcc4e903f5a01
292	1	11	\\x10463db6395d1d88ef8b76afbb1d309be6092ef58c321b5940fdc4023ab123f70a1ae61da981bb0b4eb90bf72c44d6c8ffbecacf4345ce8c8751b0f89d91f408
293	1	169	\\xdad37872965a3f2a3ef9efdaa96e5b2e0331776895f2b48a34ca88cc38565cb18d9f1278a7a6ebbcb396f420afa85b782fac4017b37f4c5be641cafeb28a6802
294	1	217	\\xeecf591c26a7be5d205b11641ecf33191fd1bed556aaa0a70463e1de8dad83dd70b04e3e276c283644b2f47cc018d57c531bdcb0a602ff42672a932e6d50a003
295	1	232	\\xb96d356b5b887248f58c55acb9bd36a6b7fc9e291fd342e401b95945204e4d114917d63f823283c09e89afec187ddf84cec8ace59b72e86ed7c70cd82889a700
296	1	267	\\x683efca5a5d78b65ba9322afb9e193f3c6dbc74003a443909925e47ef3421f3066c9d174daafe1db7fbe43b038402d1a787c3d96fda40647c7a45ff43c436509
297	1	397	\\x17052caa926a328082f28cc9686930703a967df11414da6078dcfa5f59bd4e9cc420de270b3361aadcc72b90c1510b4bff89fd464286cc7c4f801822d48b780a
298	1	411	\\x076d5befa9af8817c7a69ac037677c7fd5ef46e7c2e373d03101668901ce4d36c9894fba16bef6797de959999494e1d7faa6a50434a1929ce06b4108483e8707
299	1	167	\\x0d1ce4afc5ee2e3ce623561c64111467b830e83578f84673b1077a27b44233bf5f8bcf2c9795b7d2abdb2cc55b7489408c74da1c8537f27a489a9ec0821fcc0f
300	1	181	\\xfc77fcabd193151ebb6a385274d28cecd1204fa20f4188f375a004455ca38edabc8f98bc0aef7080c3a36ea97d69150bee79d16f74eb7ed985f756ad2187b102
301	1	101	\\x12e3475bdd64999af43f32d2dee8d0d25fa31d9576d96b4720193fea068fe6b2b9a066ea50ddc69917d54c07805553cbde8b3c69252ea5e9c03b4cb764586b0a
302	1	281	\\xe4a4d9b19d16c2d58e8cfd1784f12febd5561e6fcf54368389055f132963b8dcf1a70bd37a19afdf539fe62009da246a3f3897695a1d93814922fa8dda407800
303	1	307	\\xe6e5db10963ffb4ab6cc1090a3b2b4007ad59718858c9aac709aca0566a849ccd32f63c796f8a13051e877f6f8764afae3c58177dfa2793d3f040edac1113a0e
304	1	344	\\x653213557e0b076f5a6dabd5ca0734efd62c70d62d493bf4d7885ccc10f8be3439adef66140ae1912782b0340ae52d3404c2555c5d669b9daecfb4243b81b308
305	1	308	\\x6aaebb0bba17aff5112d6c56229d6ac77efd7c7febce8e08d5f116654f609364eae25baa75cc77a600e4b0d8d3a13456ad7ceeee1a6b7f92a4bb372d5c10e80f
306	1	376	\\xc12c60560f7e4586f39b380dce5f1a47ea22e25aa312ab4f72cbc4bdf29871f174b735e9984649fdd958afe637642784163853196fdba3e53265db8cc1359a09
307	1	35	\\x3cd768f6b4eddcf98561460474ba3d3788dd692d8e77d35796e141f85e655e870d434b1bc0a80ba1dc3aa63770890d002f5e1e23ea9a05c481f2f05ae7c60905
308	1	73	\\xeeef684102dcfce0fdfb2d9fbf36b647833432fb0783adae8b4f17a97f741452d037d41561dfb523d1161642b069b2e23eb0598a3a143ed4a1f16b18e67ab405
309	1	81	\\x27f8b80bd4963920535966f7c3228ee3e728d30787a62f491ba19b8fd7fd154836a16028fd4b2a19b1eb20df0ffc718fccb1b8a09e41138e6951f4c49e3f580d
310	1	118	\\x57193598ed7b52b0f70fbf839f85ca7277397d9350e630c5684da2638d598cd0f9c3f47832ad704729c710f0e8591b3cdf26cb64f85042de2f0dba779c1c2a06
311	1	359	\\xce19930d759ba78f8636ad33b652ba06c70bc2a2cbf85f5b1f6e7e3a6134cec1257ac246bb091e53cdd9bf29ee925feb404eeecb0be38b6301fa30d197e28704
312	1	275	\\x9a7c2f9c739ed1baaa0c2ebf1684ee085096412a841f357be904dda4c416726ca805139d42ecc47a3cc3387360052801410ee8ccc280406698c1a421bcc40201
313	1	52	\\xf6ef3cf7e48c267486de1f467cbd27afd2ed94997cae7eb160d67770d2699c21d32cb7466b9fa98faa238a174499e63052eb43aedc191e4ac73fd886c6b0590c
314	1	341	\\xecc6fa28314b1389433f9d050ae5f1fb9d735800ba7c3b8ea586125c33edc1a149670b17aa769da97b590f7def8f416f74c28199df04986f3579aab4e763c507
315	1	106	\\xc06e7e3391b20600217ea7a9109a3050b92188c2e50ee872bb54108c0d924de77c5a7b0ef7e5d260414ea33c9d6afdd3118f29bec12859a3c8678f2c83d62705
316	1	270	\\xd3ee475ffbab7dc69b97a55029922ede136e40bc76a56a17492611ee0b9c3cb285d31a39a61d83ffde5d1aa15d11cd8d74de71692d45f5c7c21da840a3e1d802
317	1	191	\\x8ab1f86a11d186bdb1d82a1251b77104f0db9b9480f91173fdce4513a22e861c0ac89f754c6cf415a287580e4ddeacac0225422b6169b706cf6f3e24607e610d
318	1	206	\\x77fd6c8cf9c9675e1288358b66a52afa69d14a21cb1f8f8808b5235ebf3f3e97908a866c1f8e27a51b10729fc9c4fd9681df337d85a1234f0ad8bb790643cd08
319	1	422	\\x2e7528aef3eff8fa8b5dbdcc3f2a801703e86342921364fad889db3ce983dd4871dc71ddf79df3547eb64e1087159b742765eaa0e4569d984a6419457a0bcc02
320	1	336	\\xbf0ead86733ef272bd90211d06644e987d13c59bb4c29231136cd63656717e102e27303f6d7eea436ae577127819b5e48b35426bb337deb44aa7be29c72aab0d
321	1	302	\\x626ac452d40c435034917c9441b5bb1d8fc9df9a426ba7d25089f74931fb279de764c19060805cc1311b8b39d2d71b1d33bbaad49040de52f3aeea2197485509
322	1	272	\\xda7fc8ae2579d3a06c3f536fd4b51e41e2af999f68080e08086ef614cf8b4c8ab7a3b82c47c71b9981d46672a996ac82c23bfc2afdbba51fbb387fba6e454602
323	1	229	\\x9e1b17ab0b216cc14fd7fdc5a59fa8646d0b8c259fa0e2b3fbfb24f438902fd53167596f155e1b3d10f96543f809270827f3b9dafb0cce777bbb0246fe49640f
324	1	104	\\x378b87ce0ac9f6863b86aa985a61ffa57b14d1cb62042eef1ffbc03b6a69717735ba7f4ad0c3b702baec414068396dfe4ec0edb060eea5c4e8f496a2611b530e
325	1	418	\\x306bd43fe7e7a8056d89f3d86abeb54814e3ebeb3fa5752cf4ac387c6ff0f3d7df0933ac051f37662bd41c81cd6203424be5d5717e120e8bd7986a04ae1d410f
326	1	76	\\x2fbcfe595f4ff8aea6f2b1054f6c4c40cb47253fbd73b44dc3aa5b50352a3ba282b2a29dcf1a6ec4a27087b3ee45da7ba7b75b4c8b2f38206d3380af497bae02
327	1	317	\\x3ebf3ecfe76912cedb806acaf8b0184420f15bca00e329290eeb168505e148816d1adf934e3425375d5cf7cbab1919bcce7e3b4cfb1bf6fa895e96fd02ff5e02
328	1	381	\\x3996c399d1132c2219dc42e62c31b3c446ff9fbfc8730aaa7ea879cc470ec875f1a91f69f445f4e47c6c069515b411b206993533ffc605e3e3e9539e3f06ba0a
329	1	282	\\x471e39d1f80c0f38b6f23a4769ce71df3a50f809b8043204a79eb20de6575ebcab65438729a12d444ee0ccde41d0d260f46be8ebbe5c1b906893fcbddd350e06
330	1	64	\\xdb2b0a568bfabdf4e9562ac4dbb90463d13ee65004d305a3b1ed088f729998b4aeb7ffe7c1139c8f11b9f2fa12c4085bdcf1b4b624583cba9791b64aa280de0e
331	1	239	\\x982c1f01f71ed16123a5500ad1e3f4ac0d450752eec585e5899a5473e59d77a03d8500e126f7b936aad130bae9029822998e3d589e94ba09968837f59a545803
332	1	214	\\x1fdc0c8685e2c20cafdb6c899aa34ef83a803138eae4e0e0cb5161381cd400e065522bb94dcacf41f31d33f0527321724894c84d4800b10bf8071d9143594a00
333	1	5	\\x4b7bbf69daafa4a291186ba2ecdc1191824aabab2facd5d8712a83aeb7a5864b6349f9d0344797b4cf319706f92fbca4df82436a47d5139604cf5d3413dccf0f
334	1	237	\\x35c4774a324e50fd830ee0b7beca79f14f72e9fe18368f388b7ba9af68ab5c582bc45e0da00bf36d5ca8b3d4441dd641b236d0c9244009d3db90bdef2cd37109
335	1	225	\\x2f19c09eef628b891438ba42ea1b0de0f6cb71e3d02d3dcec01d789f6961ae9e902cd719fbabac54d9cae4158eb34dffe6c3f05317b5fe04bbfdc9cb83a36d08
336	1	32	\\x6b7621d2f8f3b87889f98f2c5ba364181a3b8c4e89d6e2e38d3f6e9fa08b3e8e6b306f5c57552299e51f33b736923f903cfd49958c2962a4de9072f6dca21d05
337	1	41	\\x69e6ed769b50881529e5dd16a23f315d74c3d78043e017175232d7c87f008d75e4449f3e7b4be9866769dc12a1dcb93ca40e2e94c8b8aa7d47e5309a18035205
338	1	301	\\x5d66baea47b5b871334ad1191e489f8b933c2b6aa94d39cb7c13bcdfd3d7a2a301f1506a9bfd8cb1a954ef3494d3dd82fd9983e012934a4eaca0856c42a87c06
339	1	412	\\x6d95616303c6752a4c2479a99d0bb26cdb0785e68bf1bd17333f9bd8f04f50ead3540fde2c7182ea501208dfca2cc042aad0e96a53abbacade054d97049c2204
340	1	385	\\x5d109433481fc13a05c28adc2ae9e61d41427f60da2e68b81a5f224eeebcfdb981fdd500f8e9b0a383f030c85e095b2379f7906a5ae3cc6bb05dc716e586530d
341	1	218	\\x66209f14d0d092ea7fc4781d5f9098936a1223ef611335b3f224cb0c6ab39e3e9bac5f8ec11245c2462d3dd4f87e4f0d3db4a76561a3dffd1f66fb386270c508
342	1	145	\\x295249d1d011a97eeb147704a2e3b8437455a3d7f0431ceb1e9d5b8f61fbff3652e011094869f4af21a2c47e2b8da89297716e8352b7502f77c74579f023dd03
343	1	98	\\x80deed40c57be69004219d50362548c4fa9b34567ce64caa037c37e7ee016eafc258a34913611660beb74bf34a45fac432557d6769f61a7745645741ed69130d
344	1	54	\\xf69174a7f611793573512506ce672f01f8a9c9d3bf7c31ad39d7d5df8ddef3c5453b3b85c1e285cce1d5f43349e682321748d2f463f95d627acdd02dd4bf5b05
345	1	262	\\x979912c7c21e99bf9bb11667b5a98af2dd59b92636e499448f98a3403963446d7145baf6effce26db0fe73ed8a4cbfa0ba8f66c2f8bf3825dcc1b9a2c801fc07
346	1	348	\\xc08b79d1515dc52fc9fa810b71fa5dbf55237f2dca039d6ed1ecd200a96514228392f1bec4dc6547f56ed9d89940f0c4b27e0ef3fe4f9435cf8c24ebe4ff2b0a
347	1	293	\\x679648c8b6f873a16694dbefcef637c975b2af34f8f393f79bdee37b08a817e61bf708694c66bcc05770c67184a03c8fbad05460a0eecdfa9fec40ec720f4d0f
348	1	116	\\x016dfc3526605d27a8a8a6043b3bb3d37d13ce662147c733c835ee8dac7a5919e40d79b03da440c6a31ccb3f40b5c665cb6d3a18ce48ab1b647369baa4be4d04
349	1	321	\\xc385d8b93d4e7e6068fc704b57031617b65e41b306d747b98ca369836731a7e96e4bfebc99cfe94085722e5da1d7ba9f83186df025d7bb6b02eb652c9e5e940f
350	1	358	\\x0b47651554550734da248e6c59919bc819fc2ca4d24d71aa893f05435bbb13b0881e2b5d53c50ecf7f000d3bc5ee1854d26860ab35dee02e8d3647f016cdf20f
351	1	20	\\xe8c59799262c7f1a7f2c0d5689b4cdf2d69ab74684a66cda8904f027e168412614eac39033b817b3449db84040fed3f6ef6e9f7df9224eb6d107ee976b61b30a
352	1	360	\\xf764299bca0be1d26b1fcb6aa0a4ad548b85b02d6efc08477a5fe560911f491f7dd6ff024a0f77584b80829ce6cb8876dc945c6d151a8c2d7353881e0eaa4205
353	1	1	\\xedcf63531362b21ea7bcdd22fb834f101a3085775342dbffd76ad8cf025f093a93ff45fbab41e5a3b307402df92d56fa9dcee7bece6c09c74a52b328fc9e960e
354	1	236	\\xa5ae942f39bdd9791cb86caf28e5cc4432f51a0a8c0ea1ad5075e90df2fde80be6276a7d1638e7f9ef059ae9f20d6f4b74fcd99bdb4d840957e5926e30cc5a04
355	1	87	\\x40222ccb18a38878257690a39994c98ec8233e561858ce9c60f301861341dd8e4078c1e5f5096f36c6afbc8da293b4e84066168da01bc3e2c5a0f01eddbb4e02
356	1	164	\\x850b18a8d15b66cafcfee0bab60aaefe8b1f5da5f6e19bb0b6ea6df2eadfefad3eb8e85c08962bd16bb5b5a90a7df09f196f705bf4077fae94c8f9f792e24d0d
357	1	8	\\x10b9242dfd872cd8c8176ac20d628793691fe7777397e35f6fdef355f0f9260fec237dc703c11585186e28530d1daf5b3e6a837a2c4a97b4b957b63c7e4a7c08
358	1	112	\\xf55156dd61ee3b2cb68408dac4a9fe659d092bafea0b065e570bdd1de5232986d0bcc7a71ebf9e7bd3a6901dec843b1fdc8d3e46c2e8e2ad487becc0b4a8f00d
359	1	109	\\x026b7cca86d2c943ba9990dd7c38b5e9fe81382c2548b14285ab6965eba2de5f0191e6d460613b503e53fc2140199ddb79773201da792dd977ca943bdf454f0c
360	1	89	\\x6bd9e03d16515b6b2ae18967aaee16519180443aafa6245ea9c2391941963106e789f795bb5c13e7575985a4e571af8ec11f0795a121a6084f58d21eb0adae06
361	1	187	\\x9ff3386bd60f4133e98d60371619fe983265180f7d6924aac76a964eaa6cf7cdfcc83647ba675a0952abc6597e1d0eab66281e44f82dd5b1d6d4a4c17b678008
362	1	420	\\x5d6bfaab878dfa8bcaddf92b0233721db84061681f3c0d69d6b0f5c6a76ba4692e1f9cb0d18e34c83acffb73b7582025922314e97449cd6bb351b72b9fd76300
363	1	50	\\x2a4da0f40285a09b7e1690dc5d24f7a8bea4ea62b5937a4fec8abdf12d03bc93b97eec67578d297c66a1073b84438ab76e6248fd8102880dab0af1bf22553f09
364	1	55	\\xdf7ed4e9edd51c4b28afef1fe8556ef61161fd27fee94d12bce128a19db26657c7b5b14ecfa3c1fed2c8b05555090b8aba9ccb7b2c1d815886b16476fe6d6701
365	1	324	\\x472eab2e627b80fd37e12a0cae274dccdbe8bbcbdb2bc1de335b31f7897a776fb6d6f90c4be57be5f0854c25ad646b90d961ce216278ddc102b5ba4ec7ab3c03
366	1	71	\\xde7e5d87f74f3d764585cbad3868b981fb7168fe2024fbcd27f6f524680ea67ca684501ae52df642da96905a15ca9b28abd702c739b4852664ab20b12d01ea08
367	1	176	\\xcde4fae7cd989cb492a9484530b2e8023ebb6099bef0f73b12d08ec2d5c1397658b8367d11f98cbd73aca099b290ec23c9ffb927a6833d3d357776f1070d6f03
368	1	350	\\xbcbb559926c420aa30306d70802afb72e0d5fedf8feaddfcf23ac01e3809d34ea2e646eb7e7d3140908eefe511b4bf4532bc9b0e86f225fe6c8acee970e61a04
369	1	151	\\x424ff9bf13b45be74d98ac7a41528794c9815f214e999eb59c8a4ada340de9f29481f0b1adc1c126458bc4e7f8930d85c586ea7ce5d73b43df787d1c2687d60e
370	1	338	\\x865eb932116a5cdbc4f3cc7e922c78e769bdb61a2a59db7669ce9034f4ac95fc36823f5d196b0b3746cbb01164d5226330fd19a29d658e9eaef8f4f5336efa09
371	1	139	\\x262613a2ba5408af6979cb99d1f6a2f76362a384189cece318fc09fdf5ff9e0e4581fcf2c1c09ace589e82d770f994afabd4f55f5e652e52ce80878f2c90250e
372	1	18	\\xdbc68f04c9612d95d2cee524bc4cb31586ed95b87b10c465a5952d24bbf6bd13f78cf17a8fe22f58c5eac7a9158147da32446af6f6f6c99293f18840f9b50000
373	1	259	\\xd67700d69cf0749ef809fd300b2d15954b3136aed78d6e5ffeb85b9ea542bde33f924c1d8e2eded1ec1b36d85dec109acf36362c079a728e7069943262068d06
374	1	193	\\x987315da10167a3fb9939ca625f65a20fc3725540ecdcc379bcb55955d9175ec7d99ee73c56fbfff3b6eccebe3fff8fcf94d9f7019490a0592f05fc78a4f3000
375	1	178	\\xedd8185fde280d9fe93811ebd0a082f86124eef135664ae913ad2647ae31ae5fe7d4969e94c656e201b81315a1d1508ba5f61b5995c8c3c5957e35525cdef301
376	1	374	\\xf105395d8c7d942489abb76a19964c53c15a96fdf8923a997b287e7b10b2a0479e4342045b11f7269d9d2b7f27e1d272ad4263eafc784cd300deabcaf1fcaa09
377	1	414	\\x19d9235c4073b7aac72ff38411aa3ba011a62518a49a6d300ba9dae30c20f0598259ae308bd66343fd18a46c873bd6ddfa1259bcd74eaddfe834f4cfb260cd02
378	1	245	\\x676f7984b147e9a07d227f087fa38ca9e0666c7a84112b86cf231fd1a6b43273a256c38d31a1f22050801894d9e9a25ed31cdec7542f4253471fa8e4a3bd1704
379	1	395	\\x57ff458928bb99412d0fdf17619154876ce29fc1863c21f65df4c3ef017a37736c129c3a984c70d43e2137d852886ddbcb74bbe1a9c7b579cfc73ab20fdaf309
380	1	265	\\x6a1ebbd1909671628393652d81d7373759f8f39a988f138b8499787fd7be4d883f4b4788c10722d5d256b1a892d9e2d2ce4bd0cc7fcfae2d33603603aa2ff40f
381	1	386	\\xe486d60ded2ca1e32bae3f8e1ad0a925d83c868b5ddaee7d674c3b5a1ab17e09c20d1b3726c8fbfe54e42fa46214d1afc9658afc4c1edc6880b5e56e33a9ce0b
382	1	261	\\x423731e3ca938795d609637971278960c0cfccd06001ef550258deea4baf9f9cd7d148239fe7f2878c65e367459bff9a7be2ee6be10f06442673b55443589d0c
383	1	421	\\x47d1ba2ac134477eca2a6575ca6ce57d209140ef157c1384454cec617db426281c7e0dde6b9e4df8de6db8448de6ec71bf357adfdaf5c0fda1de762c87357103
384	1	231	\\xee2a264973fa00c8f7e127fec15c0959621a485cfddf3180cdb4448823d7c63026a7d337d0fd69578bcd5d5eaf8ff4aa6a6369a7f5bf138e5cc3141d865bde0a
385	1	264	\\x978b65ae4774d1d095f0b5dae00dcdc5d67a524e2a9364d4198fcd7cdc1671683623f4670827dc207fbf6499696c6bb690737c1060ce6ab95d5c9369a93f2f07
386	1	115	\\xb89148372d33d4a9cf5041df186e0ed52230ac4fca16e7a9b8f3a80a203880aad036140d8a8f2a5b709e6e6acb60c1d1490aa2324145790e67ed89c818faab03
387	1	122	\\x9e5027a81e4b441997f7a2179109db555d58ac39ea9dd1f797b33b25bc2f84780514ed73405eca894038679239c22cf5566fa263afa0e3dcc317626f97551501
388	1	19	\\xd51568df83754cd271fa110438a939c48c501816bb98ea9b921d916afde768ba2fad67382e7a61f9765a22c8f9d3816062015200f291a2684c44d8abbfdcd301
389	1	419	\\xd80575309a54e2b95fa52f185aee65df2c9f3f8f0d9e5bd64d5d1f8222c587a5cd29314f4bd24f7e0cf0fab364a6dc5617cb1cb1dd251d7f79406a9821e43504
390	1	393	\\xe4822182615aa9a207e0123d5848e0f999f5fd24a88f3d21ef49a4d4ee9e59c6928a84dfb5d665c75a0a7717205b7a595cb83aaa60d8ca5d7f21de5d9f81580b
391	1	242	\\x4a4e6493a22232bab194f2a5bd36481e1051e3e42d6394cad7b4603fd278c2187ccab1a81449aabb6e766b98f80e28e0a2c4a7c05156465cd31cac1e3a641906
392	1	154	\\x25ba0bb684d358951338d357c350ca05bc3cf1592811986d244edec9f8e52f60e115909ff66db5bcc7d1bed5a21ef4e0473401407bf6068e8d00e676da9cdd0c
393	1	357	\\x075694a270e0ee361ad313c49f064cde4c02a5e2f7728298ee0c93440c68b9d115e57013d9dcd14b271a5778d78b7edb7b84f05487332e2208b14d52989ab103
394	1	306	\\x8b42097f8ebda0b85e2d20f8f39888c81c4b44c5d51bc9530dd3db137f41777b4f9bd06025da9304dd4afbf0d3e9481f72db726b83856cb9c81a972bd41c5f07
395	1	310	\\x7404d1f19d1da13c9668a8ab8c475a92ac901de94d3432c72a643d20c8b4414ef291ffbe036c48c151e10e2b329ca135ee8faf58ac072562dedd0174bf21aa06
396	1	171	\\x9eeb15608978f28966ee04c3d00ae12b769172c797baccd6612f63bd98c8b9952be687d735998dd53518bde57943cdcdff7b682d8a6050f3d750336a504ee30d
397	1	227	\\x5b0195842a008199c60e085230e4bfe763b1c20a57b8d5a474c212e94f32d3b060f323f7a9f63c138a06f3d466e20df06e4b8c46d1d211d6191ea72216221a07
398	1	380	\\x8e95bff1e9fc00801b8a43a439922b0bca70a040e3f4ed31f71b7c5ba9c427e2f2612654836c3a603bcbe7045e1fb3b31360efba23f2bea3ebfd04c8f4551f07
399	1	347	\\xcfcb2cb2fd417763fd1ffe8539bff788fec0eca6822957d1adf06a17899de3b3ea53bc60d479431ed1ccb396e33efb9443aaf78a7a3ac95ea7b16a6ef4af230f
400	1	405	\\x88dd90e4b7738de4c08b22539adbbc97a285d051a339d624d5128f109f479226513b0837aa13efe0b30b0fdf66371156c0741b78665b2d8005bcf3be43d8960c
401	1	155	\\x2fae9c1e55607d1d96a42e635abca0bd50e8ebead49a4b0079893d3ccdf5858a80269a377455220213b9927a3a7b8a2040554ae6ae19cc3e507e5b7508dc6f03
402	1	387	\\x27c5e8f0698961bef7246d91418a23877747c8c104a7173586223f8f08f84c0d697103b91a1d92b4bbf9a97e9e98d5dffdad1a454ab979a0108a603966a3dd05
403	1	290	\\x9bb34976ad079d7c040a8ccb7506ad206066c9524b42ad16f664cef93b22316195e268c094eb15ae12ca1af5fb645d7f709efde0dabbc85baace15ce2516e60c
404	1	132	\\xfac022764b16c5a85b94c52afc838d789a43df63a430197234e82a2709fe126fe35c8d09faa0ed8a0b7f3364aaeb95fda9ec971f839b557e4777383be79e5007
405	1	285	\\x72fc3ba9c7909a947ee30415a5cb88a8562351820e2dcc94872cab824f61f11ebb6d0af902e5d2be4a3794213fa4a1de4e2ae0a287977e855c11c8e8cf180909
406	1	362	\\xbc82e7fe16407d3e9a549cafcff880e0c920c4f12dac2abe359a91b20aa40b1b641a677e1309e165352cfa988fef08b1b069b8c23de53c3f2bd6fbb04c807e09
407	1	185	\\x9c3da85249fec37ac29074ccdcf05bb303c8ab8adaf2f8bf5a7b1531e7c7dacdd83eddb09aad7d84a68ee41e05b9e619c828330fb4dc61e3b3af48e5fb44c80d
408	1	192	\\xaa4a41e5d5947952e4232859d007280dc29b4b4186b08f82c3ce3cc61f040f45f8a936a3204db53c5a470f7d54e488a4cf1724ea082d0cbc889ac310052add0d
409	1	88	\\x51205b4a04bcf5ba88df1dcb435693cfdf1b0c7c197ed13999d296431a5cf4358b8c41aa0e7e943f9d8bed9b44aad99b6023dc73c22f32ea05d7150b8aac0b06
410	1	266	\\x1ec6db656fb5a4be1bcdd63d6045befe6fde5057dd231f8c5f24f57ef5f97328121e1e45d35550c200f4f3d479f853278c2220cc2ddcda5cf45cfc5976b12206
411	1	9	\\x290bc8dc6a022b31fbeae991e64861b249eb9af427f6b90f03f7c6de95fa8cb4b877970aa8f1f4d6053f07cca858de050320811cf4fcebc631d1e7f7830a8403
412	1	205	\\x04b97eda3c67d8ccc7c550681911e5ae717df256ea7a5049bcfa3c9ac8d5489c35e79b8ef8d616cf95740679387344c450088e3b04d10b3bf7cc38b7f8ab5506
413	1	296	\\x471aaece980542ca96ff0180d60491fff62d821ece26900f5d92749ad67fa9614377db2efebe6616b5d53fa5ed28b8ed314a10e106033f569a2cb7e4cfa25507
414	1	120	\\x0a0c821f8b0862f2e7cae33a8a818c56051b012fb3b4f90d61d97a2331cd4282ca182d3a142a650be494dd6e1d2a265c695980b4e60a76b7b6eb7e23f07e6005
415	1	322	\\xedce9897a5ba5a1f8e7a86c7bea2bb119b91fb92f23927e1493983c58d39d9b10f09579dd8835421e01e63c1ea7c295cc72ef30c28e6b58032e282a27a72eb0f
416	1	253	\\xb51ac80846e8d30986526e02f1366eca1736103947daf86c14f082d69f999f88010a8e7e93103e175a35fbfc13e287fe726e9ce55f9d31fcf833eb8e81a1ef06
417	1	105	\\x955b093591623ef81bcab6e3ea09209358ce6455528e6a06355fe05edfd5f30a5a6fd3d669f177e31014d71a7416620c4ae38cec35cbab8b8e3b40064a5e510f
418	1	13	\\x02a21fb216d9a46e986ddf0d9442f4cc7dc8d4c1d0b7b2c61774fa7e6e7d25979db69601306a17cf458c35f6c298da667fb5f170d5e29c37206fc245f3c27f0b
419	1	394	\\x03058e1eed11ff61006a6fdcb15617d5c73ea7a39ee50add00f6476f56bd2e601957ae14a60759fd2b63e4bb91629d3284442f12c5e40ea8e1979d739459070c
420	1	356	\\xdf3f19fecbcd9113c8f611a436f743bbdf6f0fd411b1de6e813eab9cb84e4a3a86d442cca12c3c5db6bc0e7c88f2516e64e22bee8f3317f73ded8a3c09e5f805
421	1	240	\\xd70cf109609ffc34a71f9c4f092bf4ab631b122fda88ec6abb61fdbefa2e57799e4d9d7b08250abb46b4f50e83613bfa45d5cf8f373812d55495941280f6970a
422	1	53	\\xda9650103c0c018fbfbce549f43ef7c7df2901cbb3ce256dc2f8f2b855b676dd687a73bcea4824869d71401b28d46f48d657e1b51d4ec8a41bd6c7771669fa0c
423	1	311	\\x736a76325f02d737577a6a8703809e5d95a12b78800c0e47f1232735c1b79043f39f23cd80d80fddd2837c7d4f0b65d7291866c5af0c3da1a1fa6ee695cc4e06
424	1	65	\\xcabf521e9564f0495e5be5100147220608e779b81e2f9c751b099fb6ec05f1aeb9046b329c485462922ecc36d9f470e3f67d7c59b9cea3f91e69b5dfa6c5240e
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
\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	1647612099000000	1654869699000000	1657288899000000	\\x2a79e08adb46aa280b8af81ae2f530f66f9a854e0f9cab500f4e5fd6fa7c9ad6	\\xe38561d0e5c90f740bdef1507a715e27d177f233b73fc637d456b4b8a21471c2232928134b45c7ca3af7a7cd626f3b933ea404d722ee2c9ad08c6f415306d401
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	http://localhost:8081/
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
1	\\xa202a437070a3127c5b9caf29a48064b8b7c1afe55588acfd3234f89c403145b	TESTKUDOS Auditor	http://localhost:8083/	t	1647612106000000
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
1	pbkdf2_sha256$260000$XxHOvJTOBaDfiHGVVT1rK1$iJY4qNsz2TuGO+CuEOmyA53V9rmwXC4FIgmvA02QcC8=	\N	f	Bank				f	t	2022-03-18 15:01:40.392746+01
3	pbkdf2_sha256$260000$Qu4eVvOsKTIjSY6kBOUgxy$5mZpW7oZfvUQz8rsFGz5GmuHbrRNjh8LihE3Ojp/RaY=	\N	f	blog				f	t	2022-03-18 15:01:40.685022+01
4	pbkdf2_sha256$260000$YL3dOdM3NPaDa7cjfsvGGO$pZtrOd1gkissJ04UMjS0HOD+6rG/C3nM2pTRvvwVu68=	\N	f	Tor				f	t	2022-03-18 15:01:40.831249+01
5	pbkdf2_sha256$260000$HiCjfCaqAGT3VKASIcS9on$9LIu9C91cJvor8RfRZJX4i8ha9jQv++BzqZuTDUg/Xo=	\N	f	GNUnet				f	t	2022-03-18 15:01:40.977383+01
6	pbkdf2_sha256$260000$uUoGbQYdHasVyDP7evw8jO$UyrR76GQuivwaKcf165HG0S0+C/kWusEjnR6FTJeRCs=	\N	f	Taler				f	t	2022-03-18 15:01:41.125548+01
7	pbkdf2_sha256$260000$NUceovR5yA7RBLOYg9WfcJ$jqBkNJ07tBm8pUJWGOGTlq9C8Mbw3djWyBC7+QAWmng=	\N	f	FSF				f	t	2022-03-18 15:01:41.271826+01
8	pbkdf2_sha256$260000$9T8CKLFMCgsklqBtbXQRb9$KQeoesp5vdNH+y3IzSlng75kgPT0MTy+4Z02INeA/T4=	\N	f	Tutorial				f	t	2022-03-18 15:01:41.418178+01
9	pbkdf2_sha256$260000$PC6cCLlOWcG0oNKr7mQrVN$1x/fqHpI26D0Z4LzERzbymRzX4KjQ5VOFqle5FZRbr0=	\N	f	Survey				f	t	2022-03-18 15:01:41.565413+01
10	pbkdf2_sha256$260000$vGaC6pptgzJLqtrZTkgNhg$UiuCeNtDKxo0HDV7MBA1nEqa5wXHM19dQKiD2NKG9a0=	\N	f	42				f	t	2022-03-18 15:01:42.039136+01
11	pbkdf2_sha256$260000$dkV1KgwFbupMavylPImlVk$Tb3aBj31ZJLacwbNEIvR2lcEMs3uzo2S/DnCAuvaqzk=	\N	f	43				f	t	2022-03-18 15:01:42.506836+01
2	pbkdf2_sha256$260000$sI6hLh0bebxwUTZ6HC0JQ8$vFCMjnQzxPrYzy7GqwgxRmoRFhiri77lxcAG1/YQfPQ=	\N	f	Exchange				f	t	2022-03-18 15:01:40.538856+01
12	pbkdf2_sha256$260000$mEZGX32XuhlLqeTDA3wgeh$EJEPUbbGQ5R6JEsIoFWU4eE6+r45EaciUubFbcBpkKA=	\N	f	testuser-jrtseipx				f	t	2022-03-18 15:01:49.655618+01
13	pbkdf2_sha256$260000$yixNVH24ZbOKkr91jhznjK$1T+PtcRDhuGgfEOCKxUJuWDWny/mgoRzQvv4BKjKL58=	\N	f	testuser-wpkhjfah				f	t	2022-03-18 15:02:00.795466+01
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
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x02c4cfbb99f137fc2a4505235be980d8f533c979197df8640191b8c456746a31f730b5fb1bb69e3cddd5f97defc2ea1b3ae66d626fe4618400c104a252521f94	1	0	\\x000000010000000000800003d84529ba38eb877a3b1250e6b71c0935ed08d3b4e0d5051ecb54eb3c5bf656f27f3f8e1d1c6384200b5e49a3329be01590427ff26d94d22b89c11e873d2269ca4ba1e4e84b79ab410bc600f92a0dd1867930d8c3124f1d677b6b4d5140e69db383047fe1854030ef19ec4720c335029d919d0e6d826269ea700f0bb52f06ef8d010001	\\xb563cf04251958659a903ba8fe214b002080c1c4db0e9440b38af22722857c28126d50d1827e020160763ad3b832d7f0a9d06fe598af82090438c15071de6601	1652448099000000	1653052899000000	1716124899000000	1810732899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x0648b60c7b1ba09419e148abb454b0a375b54514607e87abce4191d3e6e0c549dd8bc7f19b9519637e498db47dd9496401f78bb9e965b987f9aae8ff717abf73	1	0	\\x000000010000000000800003d986aeb619490f51a61807f3ed8ef8a96f295bda1baf0217a32351220a8925491847f1391d8056b0f15c662e3f684f8c5ad534958193e5ae4e5333ac143d79fcc2acd125e36094ac065461ae2bd65b6c13d5707b68194c44b578440adcfe7748edb611d7f7b29d7a47f574268eff0ed0e45dff6896c25ee624f9d1fea1953403010001	\\xea53c3e39cb6dcd5c69b36e54bf7ba5499a2f32337f48e977dcac8eb240bd2d408e64d007cc99a5f6d670fc34e0c596023da2b0c43c17bacd20d6215fa59eb0e	1666351599000000	1666956399000000	1730028399000000	1824636399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x08dc729f27c9da1cfed8767b11bc338b4720fb9bcaa22483918f3d68c396c628d9edb4e4dc7eb122b0be0410622d83ac88e6f7abb7e3239ccb02400a84f35484	1	0	\\x000000010000000000800003c81a39a5fa426fd0abeeecdf6ba28c09ecc209718bf9410ec0779a773c250c8e2238baae8a4e25246075c6c97bc994706a3d03893c48dbf8e0d970afb5391d0c4fc8e87234dc271eabf7dec829b83199e43105d25fdc7e2e6d9ad75eec7231d5889f1743403147c7f244ef371d040d03eb56cafa05e9c4a4bc3a59c2bb27f5ef010001	\\xe86f08b238fe1e1913e0f5365e7f4d2f86c1e96a336ecd41e2c147214e18956da077bfe1622b7235d315049d513595e2c0a9e3785183fd3313e788f22d7b680a	1659097599000000	1659702399000000	1722774399000000	1817382399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
4	\\x0818fd71aae9f1b13fc600fd01ae485b40a637fa4e588ece3d30e3f8716db9e325b68e5c722afda9ad97c78ae031e4eba7a3940372ec8b2988ee8ba70919ce2c	1	0	\\x000000010000000000800003c36ff337229e43a6ea8b81fec359e00842f83bae4bd2d887b72298a1d51bcbbc038ba46f773c76d07c02dc2ce802e8f115cc5bd2e87340ff8757f407fbde3bca7b156b530bf00aa409f27960cd4a3386c6a51ff98a5192d292a0bd8427be6c9a766f8209f367e00d84cba1dd615c8dc2ad6d594391638fb13630443d4d490763010001	\\xf8f474d1e4db5027dcac946afe4f8049210216746a8edec86fa9d9bc8a92275bbdc07a9b671dea077445a54c8744a4fa6af4ddd40b613df1b97d6c92e6d8860c	1676628099000000	1677232899000000	1740304899000000	1834912899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x0a3cd6c725ae2f834cc8ddfb26827a5096c5391390d4230eff54564cee005d3043d4a5eba922f1ecdb418730b83f7d266fc8035104730d17bd2c8aa7328eaf70	1	0	\\x000000010000000000800003b04ed2e511135f2099763481a26bbd32125043ce01404187628aa0abe3893b44b4f6085fbf488a34e08878123ae57bdebc31f815ad409bf9796f3a1130dc79f254e3fec54ed015da6a10c3734c2b1b0bae4a898a6c567a222bdea08d8ad91def3ff15fbad45ddd28cc9b58212bb040532ff810ae5f982968cb40098d15c6db6b010001	\\x9cb851600be9b60dcefa78a817ceaafc8f1e3e9fa3cd4fb719674f6dd395049a9718458b2db8b67c30cef86181e4b739683d5a280c5c66833f7d98f59d9d920c	1654261599000000	1654866399000000	1717938399000000	1812546399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0eacfa8bd3207f71ee912f5eebdfe4de7c2e49ecfb10e995e71b0d955ef64586c155ce3761e7b7caec498c2fc33ed53359be451829b8d5522a5c350718ca4fce	1	0	\\x000000010000000000800003c7d65d9b118aceeede3c2f65adc93701a1420e5b2bd132ae04f8d92bf75c07c64eb6bb9e9fa0e7e0b8ff50b590f112a19e5d3c27cb87bf91f67cb08c6ac4fedee0c3e02e8ac5ef1eced21dd75a4b066f58563559c001375ef71842e18f59bf015bae0e1723f527e125db14492c6053126e4bfc95686453a7ca58721788d42915010001	\\x386d4367cf64f093b3c56fb0e9079a9893873a415aefbe3af17b8449d33cce87071bff3e8c03f33ef3c8df22596abcba99976e0addbb80704cfa2a6f14a51501	1661515599000000	1662120399000000	1725192399000000	1819800399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
7	\\x0fc425f3d276b8111c32512d2786cc9171dc98915db9ba5c5f5e461d46d90628edd62e36a9db4ada833d3ebe23b45150acec7374cfc6f7784254e01bae9ad056	1	0	\\x000000010000000000800003e6fe29e220d630b94bb1cfca898a51fd7b5fe10f9411519a2cc9ef61f26fcf18c6a150d0b5addfb0bcc23dabd7fb580121bd0da7781791b25fea5032ba21f7913d260137e4adbbd8571cf4bc57b9fd77729212629edbf6f67fe16295be6bd39dea1f2c0ae160dff52771f35822ae72dfd4150c802b568505d4043e9d004c5501010001	\\x35b7ab524661e7f52523e7683c96aba8cf9f32f06970969041f2e2aaec8887c50fbe2106188c49f9af0ea8713fdeefb45d47564528f26e10e7bb1e7939122300	1677232599000000	1677837399000000	1740909399000000	1835517399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x1084cfbfc2684375a15c96b8985dfc43a54e8f7a7a3dc80417369d3cd284af72dbece8da4513b43611a798142871a23b82fb998101584f2236e11648815cd30b	1	0	\\x000000010000000000800003ab523e998b80a8fef9816bc6efe93689c171353a2e3ba11015959cf420bffc4fe950a2b31d8375a139fa28101217ac000df28485fc56ddb8009d2ebe2b3999b67b10fda4ab54c9d216b43cdff86091d1c38d3fd50c80a5e678ba7886d441a37cad9e948401641aa6b04ccd99de6a551ccbd5aa8d19cf98261f95ab1dcc683477010001	\\x09001f8e763ee24ff0cb0f7ac95abad15fe3c2c8fd9eb87ab003b24a680df8d4b62e55be065052e3f4facb50582f9d7fe48576f073a88879eb826bd6bd6b5700	1652448099000000	1653052899000000	1716124899000000	1810732899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
9	\\x1238a1580db726d4f4cf17494e71c2c983976e260362bb73e370550ec6aa1711b8e10e12d1061af9ea1e7624d3ec109e336db42997da855fe0744c5121459649	1	0	\\x000000010000000000800003e7673fc47434f131683618ed498be89fb06b8961d95571d4e3ecb8ad13c688707193fcbbd405f07a1156869c15bc7de458ab89019d99230d7455aa8029f21545212d3180c631f79c025ea0376b9e88bc03ea80494a55ffe6ed4b3be1a3fe4ed41df7a2107339e1a899153ca9208b4723300372dcedaa7b8397042e014da56acf010001	\\x988decd74227c0ae6f106f78f22b14b9c09a70bd2c6c194fede87a4663933fbe5f17b12c3a046167392d0c7412a95d76d0ac5e907431ff6bc17b95f510ac2902	1648216599000000	1648821399000000	1711893399000000	1806501399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
10	\\x1278598704812a0332bba41d394d52b38f9e563c12dc3e264f16c758ddc34fa8031dabbbfeb0b5a48780ea744a95e3a596bd74b2de7a8badf4ce5503efb70f43	1	0	\\x000000010000000000800003ae9a3ab054851cc186be6283abd6b2463b9c19d876bb65d3451fb885aa198c8bed4fca940f8980bc92d218699a8d0de0808ec2c881a4c54f8522844d1bac1d90130c277c2e0fa0ab60706c8c3d9fd9be43ac5df4ed88fd2e42070b486ca3d27fd3c5f44c91dbecb247892d91bb6b9434bb6707fa0d7b2b69a44bea411aa9468d010001	\\xec32ca1f20e185592b84eb9a45987e47e60ee11121126835f14ac01bbc01b0eddd86d0bb71f5204a48326cb3856ae52022b88c891793ccf60836214d75d03c07	1677837099000000	1678441899000000	1741513899000000	1836121899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x13e4ff4988a34a1f8583ec75b2a3f070ca26c66a2ee8197f24325b265823f9de42413b0d50df28d0d1d0be46122b9111c4232f34a6fb5c53f95069bd2410d142	1	0	\\x000000010000000000800003a61a2a338ba2c3bfed3f2a65b291de4cb8c86583e79fca42b4fb651c5bf5e2f9d1dea4c685ffb741f86120a39dd913c69af2cdae3184ae700e0ff95a281dc9f08f6e923219323887b17a90ed54dd88b27cd469f26abf526d1d0f8b89c9216abdba6697466eb312a186d8a1505ad4ce506788fa51aa3e5f00a197775246b2e9cd010001	\\x3c1fcb27b4a6fe40d5945809ff2d4541689a2bb079ec7d7e26477b4de881d93a8461a685011edb40c55f5e342f5a99b8accdada40f7a72c6d3562fc56df91605	1657284099000000	1657888899000000	1720960899000000	1815568899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
12	\\x1498817fdbcecfdec996ef72117379b0c1481695b1aec1492bc2739cf80a0584f9025725b1f36dc329c6e400d42adf590d2ec01073128d979e911475d1442dd5	1	0	\\x000000010000000000800003f8fed811c0e3cfba4c776db5f8447dc079fd2ca571144b199448d8998160c84e18f2480d1f091e2a55a5a153496d2be59958ab07219166240e835698b5fbd937a767beadd166fb8a70178350e59f81c3503a5296e1bd753681dfd9b0540873a66bcb90ddbd6b11c502e21efce539fdad1c464b730a259153af87f6c06f681769010001	\\x76f3dce6d7b3884d27170f42ebec3504865fdfff16b9ba828a885ad1fd8e7552851102ca662d66a7128c5c9de069ea7b9da66ea2303895a4a6a2303eb5caf904	1663933599000000	1664538399000000	1727610399000000	1822218399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
13	\\x1720c43e931171100aef92737a3e6995d01468eb3c3bed0232b81a5a2b479d27a778a61dded05bbf9d9c86157a398c527dddcaa2c89f907f2cac85c0067b6feb	1	0	\\x000000010000000000800003b78bbe1f61038dc85045a2ef32535b26e9e17c8313679452a678792f42ec4190247f15a2b74a1c321536d6e7a816c30b5a6282f183f03a7d89373309e8f30e07a106dcef8792837c0ba720edbccf0952f41afdbcafbfed38a3ac0db7d3c5320ebbbcff1b4fa967b1a483a40588b59e7a6b5069fbb2ab6c9087b1a1ca77ad1511010001	\\x82d66d49bb843da230c81ec99f4f7df97fbb37103a51c3af43975490e1a74393554e65290b3ffc447617d8764d206582fabeea84499f080db43ab1043c671f0f	1647612099000000	1648216899000000	1711288899000000	1805896899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x18908c07e46b26d5f148c325d61825384aef182a32b2dbb267def1ede2c328502b5e25890c1b00b316cc7e17751f6261a1e4c78bee56356add0910436916922d	1	0	\\x000000010000000000800003b83b9507cbc90d8283d0fdfe183e06f567bcb97cef54a8c21fb7af2113fbbc5f47d631f66dbd6aaa51719b34df8d7baab9dd9ce0c5b7e987f638ea84e6f42ef9ccd68d5fcfc41bad732af5371ee7f8335d72d5dbbc8eabaa048aabeb06773b1b8e982ade464dda13860d66486280f6309bc8e3e344dca99683a6e321df58ae6b010001	\\x878782eab876b1286d9a453328d0f1c0397793abdc0619babb75cce45fdab4e31dbb0be9273042d7e625e3aafecd99640b0aeb4cf6073c0847de5c9a9db5690d	1672396599000000	1673001399000000	1736073399000000	1830681399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x1a605298c0c3d3b08ff1ebb3ea76cb63dedf65f6bbd1300a412b78a32def23ca3b681d74e6b0919a9d88aa3ee495e48ca457f07c6d5e78bec7a8036a1d526995	1	0	\\x000000010000000000800003bf93b48ba3b8afb562324ae170a5eb17a164e58389cdd254e4be17c1e680a7e18326096d963ed2d2e64f3f8fdeb598d1cd6eea64c5f44b807d80434d0bdd9c5b08d5a25644dcc4243f7712b7682cff496540f6c564eb7ca948891bd09d7640bdfb4236c8ec923ed969145078b69dc34ecafa29db42f994967f87a4d35fb26375010001	\\xbb7844112b1f58474240d8aaf83ccbbf30e32599cf231e71631de1a08ee02cfabed006d36debfedb80224538545f6dfb9a5eb1729559cc59469863cd2750a40b	1664538099000000	1665142899000000	1728214899000000	1822822899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x1a70b9a96a929f6c1677eb19178432064392dca4371833be01abdcf70cce4fb27f30ea2dac03664fd3291fbb6e664f1be61e81311246bf5151f46030f08a2b52	1	0	\\x000000010000000000800003be8d72225c536a6a7199e66aa584dbdc44ba538a230ca04d80ddce0905667b36d9e68bae20d33bf767e6d252c92f71a93320b127a87891d41dd205a9801ac6474d2d7295d09e883eda9fd004a9895fe83cfc83938cfc98c60146042686f6920133b058b4a8a26cf931d014bcee9c2090425307cc6fa5971187c7fbf97e01e829010001	\\x9c58968292d7533c25e1d83021d7c076773ac0e701d13234c1ae426e93f5fa2d8afcfec28486e131280d5ee2c0de5a94ae51b05c3b0c3cac92cf5688b3aac702	1666351599000000	1666956399000000	1730028399000000	1824636399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
17	\\x1b4cc86fc9734c9dff0d2bea8fab44546acf601f7e06fa8e0012f2cd3619cc22fe8c42555aee0bf8ab8245655681336c6c5083de159313a75ab9bf6ce4e45180	1	0	\\x000000010000000000800003ec6f628801037f86399a57b31f7404b81495885d6adba5e9b11f698593e6774f534d877397e556cf0f080baee4496f359ba85fa3d4430ad4df5d8d735aa32276845530c08c46828f4e4ffdfab33d89f6d25f75732499b626875506c185454973b3d1c4fab89558f340ef01cc28632c5f855785bceb8b143bddc2e93b00bf32cd010001	\\x1cc1c0c278e8aa74e93c58731c058f62929be5f2b928f154b62cff1a1dc09b7298f9a64fb6fb1ad47a3d4c7699a090524a442203093c7f6001c209966e645601	1674210099000000	1674814899000000	1737886899000000	1832494899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
18	\\x1d50204eda5f4d819156584d9fc5675bfd93a236f7fd68d71e06cce2732f78e58f89cbd3feb5f77f64ffaa2671689ac8edc5152e61f502097a5aa9ef4e2213a1	1	0	\\x000000010000000000800003f7c511963ddc1a2211cafed8ca10fb813d80855782ea9040174547328bb2f753f5de6f866eba116896e79befcadedbd6df18a5e89be405ecb50874014932e3abaacbb344ab48897423e293158df1de109e8668ee277b27b8a9917c3629921f4f89515ab839d1107dbb7881f95af59c4d5c903d737ea5c8fa15fae521ff000f3d010001	\\xce68efc0d358888c11987159154a41dbb04c80e43a9680b06c49eff442111342c6598060b071ea788b3c8d9716a51ec087cfc34974255439e3dafbdd693f730e	1651239099000000	1651843899000000	1714915899000000	1809523899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x1e0c14b1c97bfb297c9e74563835febe14997c85b197aa84a420a377f543b44e71872606699b044d3946098a618789fa5b76634d16702cd15437698d39180859	1	0	\\x0000000100000000008000039316e54467ccd0010122f39e0d8b7a6c6e3c96168a45331bae8140e529a4d72c14653f7dfa24d6e18bb14c4b2877d0fa6c2bc78efede6fa38e8491e7e28f0d258a46f35727397ec8611474b650c561c1eb0f9d0f119a8890ad25f7bc52828965cdfe435b888578c22c76690b847105ad78bc3a9f1cdd454c16c56b068a5220bf010001	\\x2137679103d1aa4190575771ea81f996d076b4e80dac3f13953d3bbed7135a1f34915a6d44daec6badf96cce4e1e7e8f364eb6a37bd0589e64ab6fbee71aa302	1650030099000000	1650634899000000	1713706899000000	1808314899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x2428c2c830fffaf3d2ac1af8748f0040da0205bb74c09cc44fae7b6865a5ba38f451be96acb486915e7d3dca44049a728d4a9d8aa7e1b08247dd519060141f8d	1	0	\\x000000010000000000800003fad2b4cd0eb0d7716eaf14c7bffda5a34ed33f089cbb0ac414385910c23eb94feaa735faef9364981e3a9187a207b2363f800b3d51e7986dfe2bbe29c7b7dc2d13640307b7fcfa9cc4b6535412be1ef9c18f906126c8f3cfe395c1ed97ad3520d60bce7791cd8b6923ded252dc9fc6ace09380d54573605dd3a10fb42237b421010001	\\x14e1963cc84ac9b89c2863b03c42e6764ff1e1a5e12369298a744f5341077a4263230bc8a4c99f2b84e4fd6b0fc5e997aeb5d6e18c4a79d6ea14c347deb5e401	1653052599000000	1653657399000000	1716729399000000	1811337399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
21	\\x2578b0f8ec30c05b6430666eb3c4728cc1a7e8ef0451be2535cf00082a7ca7a4addf69051b04729f52371a22cf7f245a2d3f47a1e27f53f77b0a62710c9fed2a	1	0	\\x000000010000000000800003e140cfbaaf2afdb797753ff594f2c1fb5ac12cb4c6b92ab80e7cf27695fc97b14ac6451865154ea131ee08c7edbc97c0cce88e7a65216ef1c11fef5b37429ec20791efee02e27f76845aa3a133b27960649a194c4f0a229c0410ae54b9f3700e9785e0bc0fc950df557338d420b1ff64f193ebfc37cdca37273fb05b5e03aae1010001	\\xddf4dd296d4e754df9387601b06a2c4e890286506cef95f54a810329a44076cd302d5d625c86b370958d2798ee8b8eb82f63998c425d5f9b6be9aa9cf99dbf0c	1666351599000000	1666956399000000	1730028399000000	1824636399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
22	\\x2658dae63bbaa0f497d13d00de16adf51d13aae0da2935db08a98eba33107b933c921eccc3fb40b2307da3d6cf8b30646a05d71dc8042975c5d6ff6117f930a1	1	0	\\x000000010000000000800003af5f5e60a2dc84c10ec7a23275c3b8b4b0a1c4a75eadd5884eda979fc8b081f0ed1ac254c4fb0b8c7145f7d1460935df701f7f868fd84106726f2f5c43ecdbe25c8af27e9881e4cbb78f4a7dda13711b8bcbef518a58401c528197872aac1a3b66886294191620f613e0dda5ea362292cde0abe5534d88bf19d255dc4b724a1b010001	\\x5cc0b792ebe8903acf10623feb82704bad20ec539c2551260efed105ec7e1eda189dd6df28a13542c8435339a130bb6b20b53cff832c053b78f9ac22db47a60e	1668769599000000	1669374399000000	1732446399000000	1827054399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
23	\\x2bc425a0513b8d18abdbe23f3145f5002e5f581396b5b7a11b2458b32309c39b3b17a84852e0e1a9f1a93e43351075f349a182ed712238b8d747cb58c6de213e	1	0	\\x000000010000000000800003cdf8b266f4df745eb856f7d7c01731cb02de23d11264185074d7c6b0190f69ca1e0e2216f6ae15f849e7cabb4af395cd8d2352585809ffa1be0fc8847e436cb04d6600a48cc2b4c103d2a595f72c53b9a348da0c1cf8fc1a7929625b1d4314c5e5f50b91ae00dc22fbfd81d6b0814f63bad3b3bd6138853aaedf0999009500e9010001	\\x642b938c870fd76292077d43a6f520288661f4c878331e9e883e22a8d5a5cb98d37d9b69e7991f7ce86dbb20bad6e9ecee7cbb97611fded2bf296c7d84c0e00f	1664538099000000	1665142899000000	1728214899000000	1822822899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
24	\\x2de011c1c410cff01ebb2192b6445997928685e2f0bf5240d79004379d467bfc5d6ff4eb1cf610bbf250db55f399554d68e9d2a9748629da224c8c78a068cff1	1	0	\\x000000010000000000800003cbcfe6c3e5003e4af404dea770a79f7bf8a2633fab84220bc33aeafdffca30c0747f548a8f3276723ff784a824f0218ba1c45150062e6d14a98c7bc2e4f8520e7acab21f236f9a79d534d49727e3adeb85a7f906a3c14b7a98f0798a4008b475564cab51bc95d1a56c83a76ae1bc4a9abf594fe1b48475693d30bfc21168c019010001	\\x44c02e817ca5b7d379a81f6c986716f326f4095c6db399dade74940e1e3baaa9cb7d21b5d634f21f32e25fcfc6e522baefab45139a563929237b348527e9c90e	1660306599000000	1660911399000000	1723983399000000	1818591399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
25	\\x30b07b01b6bb62b7109728f69b7bf7ba6b8e3741cf5d099c330dbe6173402dd1c5475706c2ea399f1ba400c52964b04ffee0f80cf19e930098b5e4f9e3bf473c	1	0	\\x000000010000000000800003f1d4d23fde909edbbdafb32b05b487ff9468731a39c6ff3a45e44ccedf4f6de04ab954718cea7a796942239102443e744ee8148fc78ee7d008ed8882d5610d6d58cc412e5696e85fa23b0956855b46efae08918124844cd5c7632c66db7462d4296b36298f02ba81c142926daeab60bf586eb6e3edb4780e3f4ca41f80320133010001	\\x59fb2aafaae4ebbabf4f4bceeed632bbcf10ea13315f4f9304096aed8b05bd0e2038a26a38e3371dd57d73df87176e921573efe86086422bdbd70ba8ed673908	1675419099000000	1676023899000000	1739095899000000	1833703899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
26	\\x37d45a40337592e2af82b51b15fb7c084f87ff714208c6d78314541e02ead66e4d0ca0910b6d2d260fbc4d90a2e6ae33afb23538699b55fb1c206400c3897a79	1	0	\\x000000010000000000800003db210979de9ff37db91846dc9f2292abf53bf6ca4e1b758347c41dc785ec3be1edc05d02cb7264a21e3273e6f2019ca048189855e889de7f072e1f5ae86372b56bd889b10c45f08f3d536ce19677228cc3b912ed2f95e5148b7b9ea60c2043360975bdaccb9503ff67986c564da043a81c1487b05e48f76e84a6896c58b20ff1010001	\\x58d340d8458633499e495dde653fa53a09e8ec2bcc5101d5058a81f3f5c1a7f8654728a3291eea3bc66d3f129ccdc69dee3365f0cad887fcd9817a7d3df2be09	1660911099000000	1661515899000000	1724587899000000	1819195899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
27	\\x38a8060b36f3614d81958f38b00f0819c6ad1cbd8c290b15ba3c85a411d417558574fa98f0df71356bc7ef031404840dbffecd7f2fd1f6651534c193e32265b3	1	0	\\x000000010000000000800003a7e715a7013c23e9b4f009e19b60808ab5506a27369be099f2aa1e998024f581142cb977133f7fa683ab389155b63e6299cb71e8178caf9cd2ccdb2cbbe5c97806fe9c28646d85950046f6a6346e6d5d35e496bc872b9e1f464fac7ae9a5163a4020c60d9f9731abd92267390b23b1bd4ac0b5854e3a12f888600edfea94ffb1010001	\\xa73b79b18d80772dd62e552bbe7f54965633c2e9208cc48786a3ad512e40a037dac5d926ef5d18820d406442198e733f1a47e7b74e13c0719e06fa123bafeb0a	1667560599000000	1668165399000000	1731237399000000	1825845399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x39c80ba35763b2f82c5ef4fffbe3a1b7216000d51ebb31f6baf1331936cf264db062ba06e27374a9e885fccb7e6b63f248a2a0f1f6498800e79b070aed04bbc0	1	0	\\x000000010000000000800003e4367cf3142456fe4fe4840ad5645c3be1eba4e085d99225f1f202230c3e4670fdbfdc84ee3a911a82b1549cd1a36be4fddaedd4076de5e3302c8a28a4ecdaef8a818a3f2f697b4d7a42628f536ff8a582b5ec52e959422c5581187b20942dcc583c5f755da2636019d50531f31271f4e66b130143b9bdb22800d4ae691e12cd010001	\\x6b1bb43014606e7f6858fccc674ee0f67b4176ec8d6c21c6fbd7d5b9ea5934cdc723d050712fdd2c2924287dce104e620a6b4875792c01e2ffa3092d395ab50f	1675419099000000	1676023899000000	1739095899000000	1833703899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
29	\\x4074adb22398dd18f6e28d640f3576cc8be71d0cfe401171cde50a58878340eda2de61eae7533f0aaff3ca242c0c0afc055ea40f54b05eade3b7f50039e6862f	1	0	\\x000000010000000000800003cbaa8fe35d2a1f5a0c72343ed51ba742470a410a9bd2cbf3301df063b033d84c221533f074c2108ad53039deaeb2e536f126c41727b8602cdb12a8ee213319be73c4f5994b64f6edd19874876f0fe3e3439c5251657822575ad20a3cae995e749ee25f1d191d66ceeafd8410c3fbfb9eda69df3980f507c7ad7a1f014dfa4d89010001	\\x5aa3afff3fd8ce73b12bba3eb026dea0148e6beed3ce9665f94387ac4d7420f60bd33e2e5cf9a5bab11eefee2a8a4502176401bcf9043fe75e82092ba5e59207	1678441599000000	1679046399000000	1742118399000000	1836726399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
30	\\x43046a089cb37c0b792714488b837adacd52bf3b6547a51d0b474e20e0961bde64815adb4bf4d6085dd50187c886f311ad712812c4d2687722403cd093e2e684	1	0	\\x000000010000000000800003c5495bc6456f3bde52e385150dfb664b17eff74cea7c9fcdcde540403393b6b51969e03a69cefadf3d131c252c4af940c4ceb0e25f444c4347df2dccd804c7f9407d3d516ba297ad6da48c38dd0041bb8afb5c21ab2e58623694738440b07ebc756a3ddf6c711e02d39ca81414338f216664cd0a73040c7f7769c0d042793b9d010001	\\x5007ffe1f386e24b098a38f1d48a5b96d85f6c3b96265b526803a5e620db6b615ea45485a85d740ca838d4604b5391bfff7ddc7e883bc9c50e06b2ff9c08cc05	1663329099000000	1663933899000000	1727005899000000	1821613899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
31	\\x458c44efb14af19ee9132bfa6c48916c654d0ec314d6d68b00a58aa107aa6a3de1600e722a8ba3e1a141cbc7cb22005d90b6dd55eee6adbc9231c5fe65fe2b1d	1	0	\\x000000010000000000800003dab4b5eafbab808027b438784f7c3b45b993aeda1435c106fb1147ec340cf975b397d3b0a9f3cc7301452966ff69aabca5c9b04193c90e19419d676cd77e97fa76e4ec7f3b66709838b01c01cf7a17898ba8f3c4ea8fb5fc2cd250f814e1af45ba59b4c0a5d3168cc7274901b2fa4bed04dd2398f35715d58171d42f6809d94d010001	\\x959ac3b0354c52e4a128fcb3aa413212062184e46a65c7d607ed617c5248b93ba293b00a46f5b899f755293884a00ea5b502f4ed0a80e18e900eec9668b47001	1669374099000000	1669978899000000	1733050899000000	1827658899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
32	\\x488ce2a785f42fa3aee83fb6064a0101b5b92a529efedf2ee1c73011820c5d40e6ed3edc390f92b036fcb97d5ea5f5c58c60ea0039667fbbcd2079384b487d29	1	0	\\x000000010000000000800003a8afb244f1d1028505ddefdb1582c589664abaff8889d14cae962a2643161b39800f6466074d3c95105259c1bbb346d62e81017ffab1980d1229623d2233a6f1e209e300661ec6fd03449b4ffa9c7befc10151832718208c6c69b8b087cf375be0073d462e6d8ef0c625bd8c74cb9632976038d3ee14339c5b1a0a5fb8ff94c1010001	\\x7172ffa3899c0c1e982dc3138f80e8a8a33d1058c1b717cb1d881ec3df0f1c7d1c5ad992ac0a8ceb71b07de43dba33a2c2450c139777971b4e64335c70679e0a	1654261599000000	1654866399000000	1717938399000000	1812546399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x4848ce511c1263f3dc56e878817b83fb35ca9ac7069573d46a755b49dc858f4fee591e20d268cbbb75d99da7e0c99c48b5db1c7eb7ab92fd323e271938b2ce3b	1	0	\\x000000010000000000800003a51f873b1faae2df8e0a5afc3ae244d28e2e51faaa493abf45fdd333e0feb2afeba2d6a757a140aad684b0edd1ce18087438b84d4bb67f894dba18320a0f61490efd32ad6ede0ad2179d1ed4aba63601c4c4bb80033faf2c56bdd863c2bb4d6748493f2dafbb29c0b986d8d86ba4be6c438ef2190ad245ee0edeb6bbccc87e2f010001	\\xfa4b04884effad593f4983579f19e3204a675e92e48a6116bc634f296c24d1da7a1d7f21a9038ef7922e62a68a3be842498fefc9764798eddd65bb2703e38f06	1657888599000000	1658493399000000	1721565399000000	1816173399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x4aac8bbfd44079d84df398028d68631c2c44c02b02d9e2dfa4bc9d091508e976a0b0cf1e85815940294124669b9e2d1b31c2abe72633e63d6eb840f8b9766086	1	0	\\x000000010000000000800003dbb1b27ce8929ef04f24b4d2b990962edaf8bf019ae11213d0b2ae90aa6025c689222c2fc5105c0ba6949e42d70291457fd6e9ff1fc6bb6bac36cb849a75a6b5fb544b8880ac16dd7b976161477cb60f5ee4cf0072d3fdbcfe71f346e8627f5c5d3eaf0ff79f72254e07c2a86dd30da71cb4627ab3967fe004c04e9b504dc05d010001	\\x43e251d53c46520b4a350c27edcd7b44da397aeff81239c9e3c00115dd415e465c53800ac84eaddc78b06c30b6af406d895983f43efbce3528d82a191394ae0a	1679046099000000	1679650899000000	1742722899000000	1837330899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
35	\\x4b78be961be8a9877697a9cdbca155b6877d351e4ba8bae50f9f4f315b659566ffc2ac01695a796900d28d024e9a5bae61212eec008a454ba42ed8213e69168c	1	0	\\x000000010000000000800003cfedd74520553b3ea7e53a307bfc4d5116bf9e14125d8a1107e87e3c149bb6ec9c3cd06aeab2abf524633a15bac2b4d46c6e6219d2bbef3c470975c9344e151aecd137220187b1b2388b23fbd29d22720cdcd382bb3f660d8d6226ef70b7636a040aa510ccbac9b00ac6733034d4e37b2c4540557fb498eb9c004e74c5699d03010001	\\xedb663928b735c5706d99502a1a92864189f22fb2212804811f729b7f985f75ca827900a67de08e83bf614b5b2fb092cde22f7457ef03d484031c09376d46b0e	1656075099000000	1656679899000000	1719751899000000	1814359899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
36	\\x4dc87590a09e8901220368577494ea6260b88c0423b0fb4029a5bf2e5cd36ca9f4b7d636f2741184e2efeb4fa025bed143080729c0dc2400f0a35f39f14a10a7	1	0	\\x000000010000000000800003dc6b3cdd37c21fce245e0e76a30dbc206f123285f8b3c35e415e011d877a17677e45c475efd5a2be1279a9a28903f12e07d9d420d71eeb65661656ad8bea77bd6bf06f036d41cd1dbe75aa163c4744b14017678016aaf6ca7d164f64f1931e5ff4830776a53c60cbccd1d574d0477a58cd389fbeb522e1b1582e6871e5c6e905010001	\\x4a6e6bd74558b711f7979d20eab51a0e7b96822c6e84f466ce722a8e394983d703bc778fd63fe034c7b0ea121060a34c7444bcbd8a64a020b96ba83e2612a30c	1661515599000000	1662120399000000	1725192399000000	1819800399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x4e4c998d39e34ad61dab5c92b3ea7a7a677ad099574076bb1ad5ccd1a0b3a13e308c21563d66f33ea52876803090a9a97fcbcaec7a838007bc91e5261f4c272f	1	0	\\x000000010000000000800003aa5c1b35e22af2b4d602885a17022915d7da614aa37db23a436e30b774ca9e65b204a4092684789e74c5361c24bb743a4dffc766322fa6e634f222fba115dfa4f38a863a3e49b81a3d88851e9739df481fd9fa2224044972a00f5834c4019d72f51020242723526f6250b09bade30b627e004d272a5013cf2ed8ca11efde3605010001	\\x9b5c1b5cdc8d3982efc1183b0c9422c9719bcb2163acf8337f336de6eb88f61dfad83511e3bb0b9eed7dc5292674292fbbecbe9714989388a78b9418044b9705	1665142599000000	1665747399000000	1728819399000000	1823427399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x4f8ca25b9c3ff2a28d5133e34a0ffd0932e151263fa063b89289ff27f5b495c61c46ede616c2c74374269a3184b7b98f359b2c87d46cda73a0532bb2e3dd2338	1	0	\\x000000010000000000800003d8dbadecb7b47d92b7d95d1e3c880e4cfc9751942d85c004f7400ead7d4bb533af0371adb788e5bb6e8226115525489328e2922a84cdd102e785e144efe830fc0c82c171a168d12155258e96e34ff810dd3b2014e47a676640f58186eca5fb8dba321fd0af6e37634b3f6dab4e48abe7e815c7506d59fd891fa1c6791714b709010001	\\x33b3cf5a84ac029c14efe93b462278dbe8d0e9e61ff830580fe4370361e463a55576097b14406c62ffaea7d9591231b891b7163e19fee2fef08d8267d042a207	1671792099000000	1672396899000000	1735468899000000	1830076899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
39	\\x519c0e6fb1d63a829b26f878184ed83d20e59b9b421dfc398b127b600977343ae760ab87fa233a9c9d2a32dfb94b91ffecc1f14d67f79fa683701e3cf3b391bf	1	0	\\x000000010000000000800003dec1eb438876c302257ef3a38960b4df66f96f60562cf01962262a5b72ed718f8c03edcff2c0e8ed7316f7660dc08eede5c3de70ac10e0dadb2e45e1802053403c57f0b9aad348eec0440c342c6aee4cac355dc5c057291487596c92a12a0373b0f8f7a04579bfb379e91e92a9d6e938ef3b642734c277246dda431bb20aafbb010001	\\x6e896d8bc999c5f3d69cbd91a3c13afa0c4a734c07050a08e469aff1be855b952f02fa44c6bd304f4e52d8ddd00dc925d12ae5d55fbc45e22c50d4d455316b04	1675419099000000	1676023899000000	1739095899000000	1833703899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
40	\\x572481b9bdd7bbe0b4a0bdd6a1de35e6beeadc68a0f18252eaadb8733a502c050ee46e0f3762792eae02dae58065bbd5eabab409acd8c8d1c12284787cba9c05	1	0	\\x000000010000000000800003e7460747c7b817b6a3d055ef4314eb868526f4e4b76e8dff6acf36702470a29407536da288288775819cc33612e48b626645c1b94b10f6c52e16ad26cea137c6f7438539114a410012ddc28e5cc9e17fd2380496c16292cab13c795f9846fa8cf4159b9122903eda92b0137d9b3a6a7f4f635ba419ded9d6cbe4c0004eab3b51010001	\\x58299004aa1595c409b76cf81ecf1689ebe25401def77040197619251343227cb6c9f67b25548b6d61ef1a825833caebce25c5090b019894e22526a8c059b405	1670583099000000	1671187899000000	1734259899000000	1828867899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
41	\\x5830c28a1603e1348f57b6a1fc9545a2b23c390cde5cebb620eb035df7c866489c814845bac996f890cfadf54a1b7a7a93d52ea9dff0a1b1f6899d46feb8abaf	1	0	\\x000000010000000000800003ab4a9e2cd351102fb883f26801cfa520677f72d556fc824016c5c1001c1ea0f9b57ea45bf7442bcacdf5ee23fff3ab51dd1fb0946fdbf3b8da2c612ee30a43705e860f50c1c795fea4e23c8c15c823c377a01d8bc2fbf7a66ee6e8a58628199238de8bce70d442de110b45c9872245642fecf5493573817d8b94de8f4c71544d010001	\\x4664c5de892341c6eab353cdf9fa852e9293169a043db771b58bb19792c4279bbe75ded813bb9d7a81b2814f2fba978e5ed3822808b7f5675feb0fe222ea2e0a	1653657099000000	1654261899000000	1717333899000000	1811941899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x5c1421a11be99bbacb51e36f059ec572d026e7a0d3b10264a58af00514e66f8db8cbd2ec77f076ea7f61fc1d1a7dd6ab17f8a8f5295666d577f26777ed5f9e4c	1	0	\\x000000010000000000800003f199877eb70dae785935d99476ff96973cdbacc7b0767c67d8135d1931d0891ab67f1f1fd8a0d4837c92ec56e625d7790d347eb18987ac7cb275bd6f9787604c5fa280324c752f7f1e9af528e2f2c6724dc5b56b572c8f1e53e66ded45136ca29c1f283ff5da47e95dbbaa3f1f13ff854569de4502a2e0cda44cab69c4e1faa1010001	\\xec1a63226387115c288923b9b75e12b82527f280c60b6b69b5076037ff11586c82a33faa1e6c3d644c5bfbdc1ed432a1e92725e8aeb1bd037fb504ca4de3b506	1663329099000000	1663933899000000	1727005899000000	1821613899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
43	\\x5cdc49fe694ed9b5f444f70de610bdff894270e450188207e5bf729359d330b7587366d74a78e35faade8a543d341a7421c3a00ccd680cd6c6d9f53fa12723a6	1	0	\\x000000010000000000800003d660c625bc33fb31c4e868fb063fe74f7c2b3ca3014fe0554eb9159be22a3566be3f96cd1c94412c1461f6e4f819a26678fb8e398161f004519306ec6e1badae0887ee427cd17bad758ba0a8d5d9f50ce190e80978fc5432ed1b0aea3ff968cf021c9fb8e20048247bda518f1c5fd4b73eb679229b79530b2c05cf84434f5c83010001	\\x95c07497b40ba0150243e8eb2ee4ba7ead2c2b8a677d40eaeb8355f6985e88074227d67960a3dd78d22f405bcabf3c0c81fcb4e13db8e72e3e7022513af6db01	1677837099000000	1678441899000000	1741513899000000	1836121899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x5cd06de13e8cf68558db2c85a8e18c6364e473f918cd7eb7d35aaf26c1538c05ea4e7b483829546c4f5367176a1ca190535db9ca67262006651fde7ad735c9a7	1	0	\\x000000010000000000800003f650b75494502cd43378d71f889ea9e88d1b4eee5b4a46d5d4fe501d2572deb7ab1ad798ea26fceaccc022266b30a6186d91b448ce762a031349f05019b50c0c068d2c6216e500836b11f7209500835941b1027fe30f7a0b9af3fb3ce95bd2937194d3c2c25bc21c76104d04fbe75d1a0d76b00b2d95a71a9a8fcbea0ada0325010001	\\xd069b3775c0545abea5ccf1c63e3f4b331e981573c986c341201e01f8c1a0557fa68e9e0426ab1c1b2ff239cec24800c257edfc4ebb7e1f7e7aec8b15356a40a	1671792099000000	1672396899000000	1735468899000000	1830076899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x5ea822ba5006060fb2b4c54153327ef8ee46ae80a17181140b5c64daa52944fb38ac4ef4c5926dd7bc51de2bf68b434fcb2d81ec989529c3d12e86a426e6960e	1	0	\\x000000010000000000800003c0ed190505242c977345fbd3f753ea33fe39aac32a13c8d653d898c0bd885d2f57ce80f09b6223e394a67583c411b7072375cb468c945bbc15d3d8de7aa59e41b86af41dbacb0beb2ba893fe25852818dfb45ca4429f0188cf12093440d4bdf1a98e95faf6bad52bb5d07f38746a442d2322acfe97500da22d27cc9e0452b7a3010001	\\xc731ae4aead37caa1d8b35cf7b7b331583ca0c134626e00f576977a793e7d8638943ccba43089fa9c8a8bd4b84fe154aebc9ecd0a285e3665fca846b70645c08	1659097599000000	1659702399000000	1722774399000000	1817382399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x6084611b5186b12b3b6daa9ebbfdd75bc44cf2de51fd939833adf04b277ffe0b3f1327ddb6b42245ddd9d51f2b99f60ae678b899f4b111066b5e3927f6953460	1	0	\\x000000010000000000800003be1d79dde7ffb5f3749aa1781be8f245412247d9c3fdfef75434d33aa5ddcc16fe187c586bb9bf285097ccef4dbe49906cf4cc90f764e4144de6dbda1097cb99b2e279e93db16d5046844fb06de379b2e2bbdf03255972a1955fdf9a9c15921392c81b8e67667f0b6c2c91a48e980f37d151d00fc4de10f6753622ef2a95a68b010001	\\xf01c80887ea84fba3bebf5ff47f5fa4719ca05cda0b3c72abd72693c0db3a25c1222e49b6acd4799217590caa2777311abbef346de5c184d4736f5be76b9f601	1665747099000000	1666351899000000	1729423899000000	1824031899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
47	\\x60c0fad9a2927d3854ef4c4bd3ea1dfa7aff1b1a4a32e2be0b22efe5400ca2cdc9939de6c82b90e2b98063b82e380ee01295ea29e2e4940800c5fba1e1a40f27	1	0	\\x000000010000000000800003c02d75e95ca55fef013d662ae0b486282c8cab96dbd512364ee0e21f5edb359effcab1db0a53a60b84378c0f144b091dd1da78cb1fca4e9149374cfbe0d166e4e305436b4760450dd1ddc12d4e5e6da396ae056aedaaf32a7978a66d5af31223a33f084b693763eb7b71ee0417e8444548ae87ce38d3d7ece3b4beb40c13f567010001	\\x767a160ac91be277384e439e13e6dd76e36c3e4015f6f535b78870b71b3c62fab8cc71439bf13703d70db529569eb8d2bf2aaf2d9d4fbfe4b11e0869017d170b	1668165099000000	1668769899000000	1731841899000000	1826449899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
48	\\x63a02d5e05362cc95749a6df590a5a779c53b9306e40d1083dd07b70eeed7ba8877c0b3be1e078c2bd2508c22e6c4bfc1bae69701191e67d16bd60692d1213fa	1	0	\\x000000010000000000800003ce667641eddbdd44e2c688a41275ff2bcc5f3bf39403cc96b34a8472b62edd7fcf1e381b535c29b257e5ef13abfae9ffb6b7853198f454a198a9179774cc8385143d7af1f1b18ec3912db2d732c1b8457a8de6c80edc2c60f5366da9cbb565fcb94b01cc31d136a8053cc1eaaf10740d724bf517435fbe63ab48fa43acdabe9d010001	\\x966a35246270edba04051c217249e97bd0caaf8a010645d071986ffe22223cb7c5d4f2b04d2e9a6f55def1303183897de3c7c157d1e1e22412791fc4d407080a	1665142599000000	1665747399000000	1728819399000000	1823427399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x67fc8e9e0d09561d410690242947108f7f5b15013b0d26b39d049a3837648507b39d130cd6baa4e1ece62a470e82921c6f3b53d2b06ce6564fe3f0b6a7f79a2f	1	0	\\x000000010000000000800003ad8c12ef9b05d11593905f1cc8f48e200fc654b1d7d8630b5f13cd67d1a7b25bb254c155dbfc0cffd1dd18c96ba1441d6a193678b9d0bebaadf3a00aa9e0b6deb0a29fe9cbf8587773167f6b911fe88d88190dfaa193b764405cd0ee90bd4767b1004b3685db51ebb3ba848319e2793e7a60db23b97559880f5f1e3165cbbc91010001	\\x646d83f7dc00147cd6d3342152dbd88df4a90d37b34a1618895cdb1690d2b34b502b6c1fbccd67acf7a7fedb6049c73da66c338cdd7c03aa6129a85e6e8a2a0a	1659702099000000	1660306899000000	1723378899000000	1817986899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x6bb4bdae68931e95eaab4e0b294578e0b2be7a8ddddc0c3988cf72e99bfb1fa8be2d5d5a0d2c38f79621f16a85fe77e040c1aa5dbbb2635ee7ecc9d1027c32f5	1	0	\\x000000010000000000800003c903a419ba6b25f3a920e6cdccd18583ab3b412fb13518beaeed60729b7ad1912b336c64abf39ed85d3b16931e6ae4981fc2298a01509661950ab60bdc54eb33e2e21e940c8d1d2c5098e44e0863dccfe1ad9af7d058958ef476603038f2811b2e2cdf35f6a254f264a147cbb1464bdfe8ff26e0873b47a9adab6b96a4d93ad1010001	\\x7e3d2387ebf22e703e0c8615970c91126ef59b9b60d43c21b264e32248abb714fe22131689c8c925a2276c360c98c4d42a23901c545c1130dc7826dab1637602	1651843599000000	1652448399000000	1715520399000000	1810128399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x6bb40256ecb0bad4ee662f546b49d8f80d31d14c6e30387dfbfb107c4544d9973002cc29db58c418a462cb84500d3d361ee48081c74495851f128f228955b791	1	0	\\x000000010000000000800003fb5dd2de514e7eee9b528cf9ae54bc429c8ecc642e958721e073dba44a84780f7b7dc2d15eb73e02bf179d35292a6ea4f16d155d5c6ba0fd5746b9182f9c4269b58966ee619d38d380574dfcc6dd689f1e2e8493f3b59d2233e558169cb1965fe9ac47246eec5717aeb72283c66e3abe9ae0833ef776bc428084cc837745f287010001	\\x3eaa186a606f4fa12b4f238e15cb384bedc79eda6636a640db8650f61092819be581ff94ac738e208be711ada0dab69e3f9c856f6d175525285bed02bebf8705	1665142599000000	1665747399000000	1728819399000000	1823427399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x6d0c810ef6b7f3693e9e42b96ada15ef2f28df98805e600bf52856ecfa379bebb615be2f0047781d571f2b2f93cefbed188f896d4e45c363e2940beca7b09285	1	0	\\x000000010000000000800003f1e144d0e98545b84a41dfd746ba212637de47afbbb2244909e22e6a0508a420ebda8d6000e7bc421a5a00d05ce147fa8128ef67cb0ad6c28d1cea921f9ac1142b5ed7df4cdbd2b1727a240b5f7f3ebb09da68792d019aff863f3adc59808ca85b631579e0697e95ceb566dc73d0e5f2bcf9f1b3fcd6a984479d51828fa4eba7010001	\\x897cdcf1c8c88756bad8d3eacdf97d3822e38fba9ca9bbad19509a890660499b6a0835136a49d6e5a9d7074bcc0873d66d8f93ae2a18f47fbd5c79a5b20ffd00	1655470599000000	1656075399000000	1719147399000000	1813755399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
53	\\x6e08e6718bfd2cf3d7e22368778ff4faeb2847940308e24bcb7781a211b6d4b0fc40c6aac442ba8198340f8cb295e6601952145891113af9684f3e369f24b09b	1	0	\\x000000010000000000800003e6eadb38038fab793999e5363dace01d70b121040a1bb40eb8bb92ddc61877b07d41520104db55ea2b2da14ae8baf465b750e22d6add2bc4f52eae10b4f229e24607a48079134f087dd09c14b7c979be22990dc0434d5a77e26577c366b3ea22b0e243750f03e1f3f15a66408347b83fbf0a77a84708c43096eb62eaf612702b010001	\\xf3044930df96b651d0a59f463d37375b3a56500f67a22e305173fc2b375d5f0004daaad20544a717278334e1f0c02dcbaac43ddceeda98b98f30b685e75bc106	1647612099000000	1648216899000000	1711288899000000	1805896899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x6fac7d77862394b2646bb270187a97893f88ab76b3c019130383b299c0bebc1e83113f6da5d015b72468dc646f29b9b32c10180c5aee57822cff591b3249ceac	1	0	\\x000000010000000000800003bab1910d750bfff3d3f1a339a2b80186e64a3e4e024f10ad40c79fe27c8529fb14778cfaeca4dcd12cb370eea166626d6e3c2ad64a2d9a5246bb824b7d846177d7b82a21b67361723c459029564671d31693364d82fbe4c97eafe0373fb5c5a1fe96ce6922f5828344dd4f1e9370ff13332cc61f7f096e170d84ab9d0cf6b603010001	\\xbfafbee4cd1b66d03879ef0cb2e4e56393df42c38f20de72db6ea4e50df9004bdd7b0f346eb6f41faee71f505fe1922fd76573c1efb626b201a9d6a9c3168809	1653657099000000	1654261899000000	1717333899000000	1811941899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
55	\\x70084df40caae868ba5cb371682b2e78fd3fac485765cee96d71f1095a630360134ccb7f4054840ee22f1e20cfdcb73da909522a8ea750e97e4c7b9bcb04280b	1	0	\\x000000010000000000800003c6b03c85a929c57930d83a41760dd0d2a5e2be4f98b02470d7608c86b80c21f64a39981750b7caa15d997113350bf8a700106df6d819f476bb21e44946f874632c691a5221f51bfc1c749383448349cb2bfb90c407d6b37ff2ca4e104c14ef6c3c147e0196e12d050a1c998308d504c1992a3a582a321f76334c30e5b88c7493010001	\\xcc4ab137be3067a2d2326b6014ad9c87a7513360eb457d3a0a42d2a3d9710d4c49d1f80fdd9093b83b4049b883f82320f6a70d17d9f95e9957d588d7f33d6e0d	1651843599000000	1652448399000000	1715520399000000	1810128399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
56	\\x77f01e0255b7d6a3e64454730703c410c78a175b077219895853bbc2ff473fb891fc379dabc3a014c3edef6517f02b40e6ac49959e540b4284a37162d71d650b	1	0	\\x000000010000000000800003c420cdb5fb00165e3356d5427b1d3022e63b7f4fb686e0a43aa798a76cfabac34285566b14d22a3905c1e44c6792c61b78577fda603e2f9d129177411ea3683c4fa344b3859f0de8852eff88edc18712ba2353c11b2a5b83248a75353c1f3e8eff514c750c5163bb26163ec7db5654d289ba433a37533ee05c076c8ef96d6b5b010001	\\x7826eeb60fd1a2d5b90a3de9a9c2b5cee00d71a9d90760d933951a1697991c8a124a38316519a5be0314f81c7b316432aaa140e42cd43af78cd3a9899019890c	1671187599000000	1671792399000000	1734864399000000	1829472399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\x785c54036368eef0b8faafb2ee03d88ac7cb8e7437273b2dbc9190e4c01e993c642d321ca4cced9767a6cc96de0047f7db58937d6eb27e51481ab84006ebd465	1	0	\\x000000010000000000800003940257f0fcc8d7c093ddd8e8f9894dcf917ec425783bfcc7e6e8386d50efb98ec49a7dd0a389e36faf288cf6ebd3cc5e13294efe96c77a5b3628feff5109c11655fd090d775a491a14c85c9f3f359fb2656cac6f33ecfe971e989a9df82a050c3b6079e378e71c0bb7ffc6e570888bbb767c585e380189476c39524af18f3307010001	\\xbd699c9e12bed65c92ad266c6345b5aeed077b1f89c9153433db0452fa823e770d2c7024b414bc66074be06a629890b2f6be3297d61b9ac80e0a4a7afca55905	1662120099000000	1662724899000000	1725796899000000	1820404899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x7a480ee831044ed0b7357a3ffd30d484db60db2978622d519d328a9ebaf4032c023c436cbfde54bfc697432bf8e72316fe6164a04ecfef5851847cad8a0eba10	1	0	\\x000000010000000000800003ca101cae14f1fad20a095cf7f951aa5f488cfbf3bb4a19a6e10bc9abe305c4fcb3ac3a44a4ad359303239571c7445dc77207f08e6067014e4df9b74fdf78e128e64638dd02b19d949b145bcfd52a01b98b378754be4af763011d33fb6d072db8d882818f7987ed5c188072cf5e9247e9f25fff72e831774d754ef4e738c4ee51010001	\\x57520a0cecb07b1fc4e21dd2bda3fd8d16d99740a78dfe54cbb30258db14f30f25ad0902943e203037163689ea75a236fb97a5ec823c0b2c22a4c0bc642fc20b	1671792099000000	1672396899000000	1735468899000000	1830076899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x7a145900a9b81cfe006f1c0e8c6bbc6a28dbdcd2dae36abb98d342c00dabfe1a1a6b9d6da4807903a104ca1b8f02cfae01ea59d816826c4b2b53fc8def2031ce	1	0	\\x000000010000000000800003d75f4318e92dfa2b0c48332442ba17a04f910725809afd067c8b24d54e5f4ecb58ba61d61cf12c00b9cf6824aeee1e30f30800f669bdbbbcec4c1bd88aaddf3063b23dc1d33fa1527f2ac830f57aed27bc88d5c14aefd618188da861baf2d977fb83ce05abaf53c8263c26b121dc93fcbab69cfc33b9e04fdcff28ca26a7aae5010001	\\xed7948dca1da0edade180b5b08f59859fca5e28329f40880e1c2d200550c4ae4a68bb4ad057129264021ee736e9988a5704203e9e588a114a9eca2efeb6c2202	1676628099000000	1677232899000000	1740304899000000	1834912899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\x7b785c9d0e8433b84b0ef6f9daa98e3b316b8ac3ebc6f548fa182fcd89e28bc87d1b44786469fc70354e48eafe12f2e02e2f711c21ab93eeac9e11e6108277ea	1	0	\\x000000010000000000800003baf8fad27987b1f9443984f13f03e740774c8aec446b59287b1dc14e4ce634ea87ccad3b6643d827c1c58b24c120089d5a1cd28717b6b0dc7b3b488468c8aef6e93a88a0d0dcf5e79f330687d10e45849b245576619a694b76804d610e639e2d0bb27de34a7f04c0280f2fd1adc32b4bffcf44fc9f99ea3b9442453b4c293d4b010001	\\xe766aab967e3811ca21c4592c1000fc6b6b5523add173f47b9a930c0557ccdc32fdfa0f86fd2d09175b99babd6b2ad6bbc6acdb711f36cad1b4f904e3c465b0f	1666956099000000	1667560899000000	1730632899000000	1825240899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x7d40355806fcb1907a6978952298ac55ad1de72b6dc4ebcc6380e38d808769b0416c10877765bfbc32446bb43adb1fe6af2eeff25ba41df26696547b03660e8a	1	0	\\x000000010000000000800003beb2154ecc7eeb0eb94651aa7bd2d012a0094629f9ccf5536526fd6cfcb4405110cdbfb46454bd4be339f91bb6ebc9f3a1159e8ef70c38e9d7c0b4f575babe76fdb749812a9854d6c14beb41ce10c7b991731d5f68ee94af0c0b723080443958d4b9582d7b5918da7fd66d6893e4e24152ab3c7a0c3a752c089f04863223e783010001	\\x29c8b7bf8006411474b4b54574da1e17af064d98e75eb089e17aa90e3e898ecc7ae835aecbdcc27a1315a93e28174f99fa967cc862d1da3b760eb4e3cb62610f	1657284099000000	1657888899000000	1720960899000000	1815568899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\x7d8c8b1c65bf6ca1c7b64a2d376c42c530f4ccc9277b8c090685731784321bfc8782bc5d17968d6cf7cdaca88962342873b2a22757389121ee18ccd2b5a574b5	1	0	\\x000000010000000000800003b7f12cede38a632d2260317552c1fce6199206ee29820939f5b549bca4bb880eb76b6aa15e5e2833e2840d232ac0bb2b08f81247ce4d31ac578b03479a33bb73cd2609967fa99d47d6f90f5eb2888ca5abecf81584cc4607b47f7a4d93d333633c5637af8f16aa422bd7ef95011858bc5d1a083924bc80e02429180c6e4cf89f010001	\\xa1d6410e3ebeaa4438b750654f039a8a728834ce5d73b5295b83250c2bfa57482cb6d6ff846135b60f815c3effd250a9752d72476923dee810b0d2544bd0d10a	1665747099000000	1666351899000000	1729423899000000	1824031899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x7e80866711f06e8561afe359489da4f96b0747b030177434749256ad15f20fed933bd479d8ee3ec0dd6c36b82c701aefbc3a5c4f50c15163ab7efbc52a024d56	1	0	\\x000000010000000000800003cc4477b5877267b0bfd7c1138edc699daad87b571547ac7d9f573d61f0bf5f70468a443a28238513ced34a8a9fcb17bf37e774948896968af0e19ed59853ab7e86cde264b83ddae897343d21e6ef52d85b4e444849012cf2880d75437f371a7d1773fbd2d527d8add3f24d9985889b0cde0be8e9c9fa46bb2f4d0f33acdcc4f7010001	\\x9998cab1891e264c5208805a9952097e354e731f806475cf6244a9a36dcd8469f0216558de4f5aff7a8a750599480c2269ac26b4ec1458a78fa6d0a75861d508	1666351599000000	1666956399000000	1730028399000000	1824636399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
64	\\x86f8e37e2b25da0a2fe446785f36af0238744e3c25a8c4909ec85a98d49947203679f3b89d33ae4a1d0341575bee2b4343ceddc7cbf1a33ea40c3925d38257d8	1	0	\\x000000010000000000800003fa5e872239103234884ba029610825fcd3d91ba15c2989d80fd2b33ddfa75d61d47715a54bc0d8f89c50c433b9b31bc6eebd2597bff0a5fefba16d9bb062b1b09ee7fd83cdc17a25b5e4212380549837a2c3578506a40309462c947b49c57c207f218c338d51762e8f25414adf7560943bb5fd6d8a257c16abdd629426bb4cd3010001	\\x39c82b989ae827a7c818bd1b2937d5cdf6c2e43366c968194bf8855cc500a435717ed7c0c048982ee95bb8e2af35a6d6163cabcb488b2a84a10cef2150dfd40a	1654261599000000	1654866399000000	1717938399000000	1812546399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x882cb433c02303994784c9e0ff889135a7bd2c3e0a89d4a1ba6c7958c14c04902d2c2af1ac52219dde74aa36365feb72ee36a3afb6b548612d38da901154abb2	1	0	\\x000000010000000000800003cd479371717de23445288c6d3ec92674754f956416fbd9b077104adc5f366b99bfdbdc96f3df190779de0b3da699fcb8481f76b23edec08a0c485b7f4a18ad0daf8ced16f484c2b5bfc515af96688739273f2a32e39cea1ce488dc7980902995a2a6a6f387666c244c45d7948e9e7bc334d09e08a9534daca84ee8291f63c0a7010001	\\x35d0391da0ef8eeada41c7049831e5b46bd6fb2c1cc17e7cb5f4e35390110025fe1a0ac80c181b0cedaeb95c4570f762bcd7e0321c2b3bbba2ead9c4062b7b07	1647612099000000	1648216899000000	1711288899000000	1805896899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x8b90bbbe220b0149a7bea259228ed67b39ef1fe0350bfc523cfe5461c9c0bd2009b3ae35417ee28738eaca35a5f829754cbb9fb8620a37c662853ab11305a8d8	1	0	\\x000000010000000000800003bd2120a8a300437e460efbd66dd7e918dfd9557ad53ed2255a462b13561f40a1f728c86a15a77e6ce320e6c34436adaf575951e314d024147a5f997b59cf4edb862e12a1a2298dc6554780349026fc630ab66c8b3f8ae92116a7360e5cf9df9238324f848446186a26d8b5cfa9174418f5455c6dcc74e62e6173c564b8105499010001	\\xe012b3012233589aa20379b46ca3aa0d4e16522ceac5a18b08cc0045e144a0d0ed17093555ae1da75164fbedf9447d58fb660af067fab76d9984ecfe81553f07	1663933599000000	1664538399000000	1727610399000000	1822218399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x8c147e38fb504b45457bb17d982c21a9a28666f4c833220b29b021aeb572c8ad062294788da85961a481f0df3edbda53f9313bdb48b654b20ab087fa59f8aa0d	1	0	\\x000000010000000000800003bcbefc12cc2187b76b96689faf526a6553349fbc1bd627fb2234e1fa0d0c4d6a39dfae37031906574f4b80f829145c2cfd9c488d2d36045251a74e17f5969992c608434a5b1ade5c2d2578b7094a226aac91cedcb11221e68feb88a29e8137d9ceb575602edebabb46d7b622e93ae875871a92684e9c8ab391b4a5ab5a789ce5010001	\\x8e9c2c86ce593ef7ba745c47baec56b7c90a3705696ba5dc100c4001adc9805876409e507ccfa5b92362a19547be81f1047ba2c419ec6ce36b3bc152ee72eb06	1668165099000000	1668769899000000	1731841899000000	1826449899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
68	\\x95a8bcbb37b961c08c07105a4f37b4e7f1323f6d1e517a256d24875a217536e069222f0d25e4f919764caff5b5ff17d54c8975af44b3ca2949cdc16bf3d26a83	1	0	\\x000000010000000000800003db5527828ca3452a6baeddcb58d3f746d3ad30a51d7a504f2b96e57c9f814ba6f47940d117a8c4def376299a654612e9810c7989cec66f6a483ff7ce3fa8db98f517d850b9fa91df1fdd7b216a607c11c0ea457081a5541679d9e9c14228be90360b8f4629efcc6841c548686a640f52e841ba35ef4e8e41bc276661f589bfa7010001	\\x85068449bed55edf0af792dfb0847b03b7d0c8dcfbfec25695422e065d25f3702957d141419f8d923a842016f2c2465bcaa48d3a3eb1823a5062ff0e3f60c10a	1658493099000000	1659097899000000	1722169899000000	1816777899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\x98c871119752009b3fb762a5e8a888e56ec477385cd9fc0048e236b8437b15d5e416e4a5d62d7652a552f92ab703cc5682718a02a4a69b120ce5a75d21e3c9c1	1	0	\\x000000010000000000800003a737027da011746db0eb56cbd5b07f675c776fbab56793f779f80d905c46740f13641d74d89b7194f31ae6af802a0923b1e67ef0031ed3052b8e351d216770529fca7f914cc8e0f481d86b5dcf0150e8e967ceacbe4a345e6836a28e68b46e8d4968f4eb9d03779516a15c4068392dd6d758007090ad7f1c51c213885b8a5ba7010001	\\x3b4f2dcb3ab7bb3b26179d8976ed5608188b6ca6b73d1327469f2a24177641daab2561b27f0223d6f3f52f6734eec44d807e4bd8a0f022d45b54d51316e19e04	1677232599000000	1677837399000000	1740909399000000	1835517399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
70	\\xa164181bc4c8d45651e0d0c39f17e198b6c5bb19bc70c0b0f9d728847dfeca1abdc3966d9f8918867aade71f45af70c2ebda19435aab46c2b4e1f8085f9ecbe2	1	0	\\x000000010000000000800003b002ad332f2e99f5300f9f6aa8ef52010f338464d721448e2e67457e0ed35590d3c0aae4ab267512b63934d08b3a96b9e52e01c59f9ea6e32efc41ac6f810af56a1bd51fc2e44c44a9bc062637fae5cf2b58af3a590af8b44b185ad041c26b7d9fd38570e65176c760afefc29fffd2cb88a5551a8886869df50bb23e44366e01010001	\\x1cac064cb40258992c45f6dc02cc0a20e33ff34f4da64870eb249681a610a21a63094b504d063a996374b1a15a38769d25b118c9b7ed0364c0175e44cd222e0d	1657888599000000	1658493399000000	1721565399000000	1816173399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xa5f069444d26cd1328dc8b2c2d41b910542cb3e2035a4fdccaec79b6899e8d342c15e59e75b6601a13e0816f57afa5565449a0c810d553f4b7dcddf150f5aaa7	1	0	\\x000000010000000000800003e030f7a5f43c088df95502f22a6214914750ca4e4bb3c5cd863c2334247319b30913cfd12fbe464cb48def234e36ea1b527bea967e385d510a2e78d6c2b4dd5e734a53d7b0a99abf6f7db7230f9f85d03708bb57084a15e01587fd1dadeeac58c3d376d3f493f57a186dbb68bdfc274f576647e5ec3c4f003ecf7e94e2e7a339010001	\\x90e3a37007956b8f289e801b2bb75f52f8f165f0526cd935b5c87ed93806dce07e767aecacd24aa70326a4b6d1830916e69a8c4cd45df0083c3efcfa67aaa30b	1651843599000000	1652448399000000	1715520399000000	1810128399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
72	\\xa604f39ce0af19c1ba19e25cf5aefb7ad7f595fc0832e20ff2d0365c352803100ded8f3a267a30e0ed555219019509622715cbaa8593a75d2988926405207819	1	0	\\x000000010000000000800003d3d1567ebdf7bec4a3ea15ae1d481fa4f999e37fb2579ffb0c06e92c7658c456a0387b5cd30b90a2b704d24a23d1f6bc283d3a0f7ce927f1e3e04da9feb1d05befa0be623e561700612f5b75e8141916f86517557b6ffc8907587e6f7c725f5685613a82f8ab95edf1532cb61c3871d0685fbaf95a042143be31038436d38675010001	\\x469938539e0eef5e804f922ea3e532f3a483c3a13d9aaa9174944ac5f8cc723767bdd75250319308ba973b6d2ba3079b176cbb244ea3a1b16a5829bfabe1760f	1673001099000000	1673605899000000	1736677899000000	1831285899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xae94bcb03ba8de084a84f0fa9721627e3a069f25d91ea0babfa7289a0a0c1b610b6ae8fc6a6d01c5849ce93efd9f1e8bf98c9641f36f0018f8a667190cc43910	1	0	\\x000000010000000000800003cc45038e8ccc1a30fe4cfe6ecebfc2a449c14c44d58d0691f9929bc179dc7996c0d2d851643cc3314a751b98fecdc6e3b1b935a6fd8aaa5467acb1014c5239d4e8a5021ff29e56ff6c816cce9a609391c193b3975b3b5713f24c317bf2440b2c3273c99d82f4592d748fdff1e8607e7055054b58c9315584391c9fe7780b1215010001	\\x4a2d68961653d31c7988c955fe3291b117a0762d1225282dd7f2c0e4365cc634ef71adfbd683d99df4173e9e85dd765bfe68f5e7df275f35635fb66b58a06c02	1656075099000000	1656679899000000	1719751899000000	1814359899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
74	\\xae1c78272c8545dd80594597e580bd0777271278003681e13bdf1906acab9a2c63b8d25bc613ec8d3965001b4ba50ad16b57a69c4b81c99f8df8a5dc3105149d	1	0	\\x000000010000000000800003d0b9099ebb23c3e93c43eff2d3dec7eee50c484f1efa7f2a3743cb5007f1ce531ef93956578f52f4e656c5ab27ec2ed6bbc9d7abd99a033ae57d1557b9b930d043099cbe0722fdc3d99656d000f4c4d7e7699da66e3a9210996c3e39bc82d65d68e6d5cf4654814451041e1395ea3b69f41049985c5885d6d17f4fd785642cd3010001	\\x2589043a531c3552d562f21b9fc7c52e330b83b9f4a2e1c9e1f37cc53683bd4646301db096e5f0012501c6bee6f5db88c9a112bb71c01d8420072a7daee8db0b	1665747099000000	1666351899000000	1729423899000000	1824031899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\xb080468cb014f328eaf1c7a99ed15b668ed117c45358e54b7399fd1c3b8eb9c2150a66f458dba2edde8e1a3da656ab709234e32369b896f4e64ba090da758ee7	1	0	\\x000000010000000000800003af6bdc0aedcb25c212c08c04d7742621e2b8417c89ca8998bb612f4a75647ef483b3802d40fda29947c1585e6b5560ed235e2f55525da7dd6feda60cb71e50acbc8bdbc8aa3997646b5dac74da6b11054356ffbd1f052a74f680277fc47acaf7446f931684e494aebb39753414e11219fcaa29c15b2c265595f3acabdba54aaf010001	\\x56debaabbd2274b4b0ae23746eb00fa27159b61c4fd3f497cf66144acd0da7024b26ac32f29c87cd511a1294c7c0f133bf1d767d4156ac9ac205891b27ea5c0d	1666351599000000	1666956399000000	1730028399000000	1824636399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
76	\\xb070c33b3b9ab28499bdcbd2f9eca3b92fbd82b6d618b8785c6fce61ff292b30057acb4712c663e8963807e76c034427d0ff5ff600a96b9e8dd07fa7d283442e	1	0	\\x000000010000000000800003cc14d156053e3be91b6690720c0fd215953045704364878073691a167be0929f0919044e340991c0f012498226df45a7fc96506b3fa6e283eadbc54777bf7570b8b38ec41a66e954234061540d96417075f807de76a80cb5c8e9eb0151f6072cfcd296b91cdeff06407341912ad416c897c7fae4588f74b44e935780f040edc3010001	\\xa6fd3848ebe88277b8d3fb6374e6ebc5a6dd22da7397136e964b082bc7279bd1482858ce6af4dbb20a2bc6caf4ef9900e831526cffa98229ce6c5d29bd22fb0a	1654866099000000	1655470899000000	1718542899000000	1813150899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
77	\\xb338d370580c04664aaa3700c41d4cd18ef34c41ca5f2b4b4eb5e6c845009bde95e99606b1d7241ff9517140ef1d80ead0c3f2e728aa374e7cc5adfa9f588e6f	1	0	\\x000000010000000000800003e0a52beee6509fbcb23b76695b726e273c282798a59d2828f1695ecd5a5b2a6a3663add625c4a8ffb644e42bf20ac453acf14f603304f5f0e292956989a44f87484afb06ef7a3d2a3c9fc97dfff4cc16ee107689d7eba48cc0110261dd28e7896bd04cf845e8c25e5fb3cc08b4e890fdb9bd6b52c5a1a572f01be8e543686379010001	\\x453ef84d783e5febc48ed9dd1572906ead9a5402bdb6e086c858cf18d0c9bd796b7f41523a978c9395dbe6e1aceeea06493dfb525597165e5def137b3fe1480b	1677837099000000	1678441899000000	1741513899000000	1836121899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xb4cc89366a1ee270611c1d4ac2762053bcb9dbb7607a214833a9757f1cbc88c82e647e8e6739ccec6517237562d2c031c178a38728ba9289af0b510ec723b4c8	1	0	\\x0000000100000000008000039e77ca26d3f1776249cd06dffb146b73fbb3a7638a509aff21e5bb85178bdbbe73e337b0ede4accf3c2ef6f724a29e6195a1f88eeb0f5d983962b646970ed2c8410e48c67a35856c2ad399acaa313aa7506f5f921238a5a02943051760028675e820b2fc5a85cfcb12779467a33e6b24114180b649357d40c104564525c84d1f010001	\\x651f8c5cdf67d4650b0643a8fc33125759597f6c99de0dcc4d9111fc5522384a72451553e22204ae6d343cf81c208b167d440d61622190abb80e26138809dd0a	1669374099000000	1669978899000000	1733050899000000	1827658899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xb450d38b303c7b4c11167f8f9b265d77922b7d56d44137f3684728ef4fbe0718430ad6a2b27e67ccec0bd1c09ce109d297e57f23e2dab74a64c6a5c2a4c5aa42	1	0	\\x000000010000000000800003afd0c698decbff8daa7c4ca38b0506f28faea8c61ba105c4788f6a1d7815097d1eb907139a7fca5e2eb4e6d508907c4ada29515894c3277f68e98bcb62c17b36060f6ce231661fc54635a1739e133446939fc49ddefbd0d36c1c44c1779a3540fe603e8dae9db078a02c745bf6814f52fad6d00304f11b2f440e31b0cc16340b010001	\\x3c887cb6a47175b279c662ca8a3ac168490f8e194cb5884eb3a7b3891414689fea372967d060e3e0d27b530fa609eb8975e695b11a7e271f1d6a19c9f5cefd09	1669374099000000	1669978899000000	1733050899000000	1827658899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
80	\\xb4fc8ac0d5d8f84172c6e8f2acf3d13c061f0d1aba955c6a3d30cc4f3cb7bf312f1e702cf3dc853c3e744761121fe7eb7280061402d1c4a4e2ebff105cadeb03	1	0	\\x000000010000000000800003bcaf44abf08cb8b54da9a4b05fea422f3517dacb1e6fd10423f4e9bb4aeb5b6bac77a25415b20922f0d55d1bbd1c3ab678bd5cc30aad1c1146ce8d8dd6430382588796b88a3880b921ba35dcd125b3d991993743d72a6f5cca99d2def863ca9efa0a645e40efe6148448953235617ccdb71226cd05d7d88bdc75fa4def429231010001	\\x45b1e3a415931d4e53b6c652a2760e19298f8057516551d52b7e1883f01887c84a4d082879a387e03fc49cf731d84301d8c6298af8c1d300b24d8e396dcd7c03	1668165099000000	1668769899000000	1731841899000000	1826449899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
81	\\xb5acc7b57c0c40f9f495d643abba631765181da16820304c9365e010f206740097181897b918e54956558e9c500a1e0044ed8f70500d3bedb5c1faf40008ee5d	1	0	\\x000000010000000000800003dc6bf1b4c757632c642aad4835dfa022cc43bd628581a3ceb93fb3268b954bd4848ace2442ccc5e2550ad67d629143f77b9fbd8772ab349a6ea428011fe0958347270be6ab8bfe7c886d7d35182f1464f92c889b620e071302a62cde98181a1ee3a782a2ef2ac2491d66f05d9b773176dab44f09c0ce2b8d554484f71786ecef010001	\\xbb37fe68f4681cf40378192a1821429b7d7054ec14e2cff50a8c456b3d99d45693c9333c04176827be4e06b0a72e02d39ff5c0b2f2f074e62d3c8eafb8d27305	1656075099000000	1656679899000000	1719751899000000	1814359899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xb520b88913b6dde4e5f7c95957578cce116ec88d731cc37272b8fb57589aca71fbab6a499caf8b0d9de45ffc3e7dbd006d732d452f0c723654d887deb248a77b	1	0	\\x000000010000000000800003ee8ace54244b9ed73bc76f04c78fff4013163aa979f1c9752918faa5ba3e7c9f3d8d655055f645d271896a74175dda6b290a19dd5ee6a4a3beb8d81d98bd2770591bebe2b80fa7aacee821c42f22cf1a9e22dd768330d091ddb64e8bcc4c4cb965c0a19fb5730f9a06d5f211815089448e05595e56ae530cf077ad0dadd65b35010001	\\xf99f82a47c359dec49f5a1be1b441297289a31478761ebfdc1abd97a8d2a14c3a6476b9e2d5e752a6589c7ea5e9c6a2f0ba7c3019a0de730faa5692419d61e02	1675419099000000	1676023899000000	1739095899000000	1833703899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xb6f0f7059bc3004afeca5737cbaa5002165cb62916d432506cbe43076bd8b45128aa68df03b6d18f21ebfdbaf5b68582a4daf1f306d346b60a306e9222e6ed1a	1	0	\\x000000010000000000800003b53562914b159bb2678bfee618b51d0b92db8c074d22608ac7268b9e0393528b45ded6336c8eb438102567c96558a32ee45bf5cea83d06d15ed3b0895d88545844e63f046977f0202f247646dbbcd7578723318d220c260595c4d1f5be8d7de0489936bae479edfe9a39c3d950f1ee7327e9498ba8e0047662e0139ffb70d6c9010001	\\x0f8d92e9ebf7433ef2a7174c2c6b5fd0ee57bb652f0bb2820a3ddd81f4632ef8a3d66648414e74ea170dc2140b6f3dfc7d6ac6b273de764654732d213c33a405	1662724599000000	1663329399000000	1726401399000000	1821009399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
84	\\xc73c4cbf1f721a1e600bbd35d230e7b33c8487fdc7a4988e03048b1510465c2ffe1b6804ca42e089661e7feda000f5df8de0db86e94da6c349a5d264ffebc90d	1	0	\\x000000010000000000800003c16057420055492f0c6f473e3520f4355bea5de1b7befcc0653da256bb7ba479b5a78de7416b807b26c6d1707b6e46d6d45d241f3e342121f8895b0762e30b3b1540dda498ef9900452744cd6aa1c426281d8710ed4538080474b8fbdafdba945fb97bf85ecba20d9ce45a89135e8686bc6cd4a57e0ff9780072e95ce181aea5010001	\\x2acdf877781b4bb9e2994971add1ecea0aea9404213db56e895f874c81e387865dd7ffbe817e3b72d0cc5626e8ae2d97d0eb2e3a2a7772b7bd7e1c49a8e6260a	1679046099000000	1679650899000000	1742722899000000	1837330899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xc82412a7275b72459a0447f32defd294275699bfa8f605671796f01217fd0470d2f8d5875a5af10944d28faf9571d338f12cb38d1ed36851d23735ceacf2c601	1	0	\\x000000010000000000800003b89b42780dabaeec9172318c440c915963dbe8a351376c0f3cf29f3d7e11ea8d7c9f0bbb36eca3a26c970ba39389120e5a403525ce7350189898ca4bcda32e5b5d101016ab223886aa643cfe9b346903ea48f3273f46488ec4657ab75302c56e73cd0304c212c8926addc3bf99ac9be4222cc52da402dda71dd6a946b890c6c1010001	\\xd82f4f7509412077157cb6d45b7bfcf8a25319a0878d8d0e35719bdeb588f9a8416b791328781e22619787482d7ca28dbcb000b858887dd54fb03b931e65d907	1666956099000000	1667560899000000	1730632899000000	1825240899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
86	\\xc90099746b5e486826b397286cb5c735eae935c090374ce39e6d202584319fb4208a9675f47fd268c4e13ff7fca50e9d20f85c60e915df6ce5b5988b676ef298	1	0	\\x000000010000000000800003ea54faab6bfd3980aaf42d28daedcc19273d0ad541edf8fcdaf908bbc2999be087018764bb214616da9dd0979c0a2ea6689aaa0b2cea243b1003d9f03075b2ff1aaffe2552b71b752ea6710252cf27e6b2ddafb13e78da9fe636d57f29bcec8786a45fc45a66ae1934de65dfc81c7b2f9ee214d42a1ea621c4521219221ad8a5010001	\\x612814441c97ed9bfc435cd9a370a24522be40d79e5c14949ba5856d7a0e0290ee83fc4a9450f43045bdc69deae0d7120ef8c92a617ccad3f1793a1333e6d102	1674814599000000	1675419399000000	1738491399000000	1833099399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
87	\\xcbf0dda7d71dd3467bc669154e3076b453a8661edd1b9dfa6e2c305b08fcf03d479481ed287eab6a6fae8e67bdc68c24b2d4f3518406f278dc38c3be2538b2ee	1	0	\\x000000010000000000800003ca759bc71f7dcb8fea17565a04fc9492afc951a195a3382ea993f04080a3743eb3df4d5ca8aeb4cd12b666cb21542eaa901fd12e6e6cbb6d97b2f406706ed14d7191782072f7ef2dcf3132169d1cda9f01a0ba23aa818b12b0d75ebabd3ee06dcc1cc6c89bb7b2c43d3b758919df171300dec2ffd6fde8e772e41e18b32a220f010001	\\x33d47dada0f6a653633351293071896f4136b5b2cd53e0b28af12ba7546aa22c80a6cdbff70daece9a1c4654607383bb6af73cd4f05155bd342897dea999f607	1652448099000000	1653052899000000	1716124899000000	1810732899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
88	\\xcfb0b032f9734a77bc7be55930b59e0f3a809644156c0d536e8fbe285db9b6381de139cf99a080e46512af702869569e1852284811736d56bc7f0890b597b8d5	1	0	\\x000000010000000000800003c5d7d2a4bc985f96e7ba1a98d7e02748bba2812bc4ed3b98e6461522d2d5bc0464abac8c945276840aacbe1a0142985cf88a418bdd0d0ea6469fd8508324eedb2e2b622cb754386da35d87ffd5af78a90ce9c4bd095abe22e7fdae028eab6acde5a5ce2cb511d47d6831119d2fcc3eeb0bdb36b2cd1130534fc285b6daaab863010001	\\x45d8ae823a0f202bf4f42860cb94f337e3cbd835c555b83862f8a877bf15efd2026687382f9641bb7920e5038b3f83a8eb45d121912f0c2a34acc1eeefe5e60d	1648216599000000	1648821399000000	1711893399000000	1806501399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
89	\\xd660c99702638e4ed5b1708c2124c6733ea5b75a249d1726ddebce77b700ce6f8daed0e4adadeca208ba3d2911db437e67cf29bd6abed9a9f670fc1691e1999b	1	0	\\x000000010000000000800003bdd91f18c4785764e01195da5762548278d92edec3a3f2bbcd3e69d967fba0ccb370ec2c4944c9a9d084123511677ae7c736d4d4fb57cc89c5c30f61164b8e5b5cbbb37499848d440be7020d86c349c65052a8712f335c24baeb8fb2e62a53568f78a2c316d889d54016eb268ccf3c5fc08c78eef7c2912e24d2c47044112431010001	\\x78ec11b68f9680c68bf9e758fcfc49f345a3bb0563205a65757995801d9e7c8f0a70cc1a09b55c5aebf5227c0ab2b2bf0209240ef0ae2e6adb02f31ae86e0908	1652448099000000	1653052899000000	1716124899000000	1810732899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
90	\\xd898e90a15040ef4d16d3aa8c311884b1bc7880d594d6475f1f9216d0b30f733d45286379c81815c566e0c994526c325941c0855ba745d3ba4d5adb883511e6a	1	0	\\x000000010000000000800003de3fa5ad91af03eb23a3f50073cfb118a36b5a1f0576a68a28c6f1f976eae9fb45f07f471623faec7e5b7038b525c2771ce74f194e5f8c1cb40d36bf78b1d4e0c1cf0192fdddbed70e6f335cf962a898bffe270ebccfcc30064f9b57d5b5f9543732c2b5c891fe1d819c2f55f9114f6734d926d511176d2e1d120ad8cb70ead9010001	\\xe3941a21b204d8210b6c23ed7738cb9bb959850f8673995a7213616d804846616232d88d331ac0ad66c8e0f59bd4342f0ed522f1c6fa7575477daaefce430a07	1670583099000000	1671187899000000	1734259899000000	1828867899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xdaec686096636ec4335d8a7e055ed2194d8e84629af3dd5d0f85cce449e72af5b3be5ab335886d92025890459e17be474a996f503b88452fec0a728e8a8ee956	1	0	\\x000000010000000000800003c34086ceefebc2d502b09715c4908b0dc20046749c624d8128ca9b373240df82de3f1a8480194dae1ecc65183e1a590cac8d8ea519fa7e650c48cbb6b5b40c3ed3d4171e46e36c3a48ff410be02205b7fe72ef5c472a6f7aa69f29355abe402414c66ea03dea43551eb94d043f63d9710d7a563d9a7b048ebe8a19239c60789b010001	\\x493cbaaefd9d39da6400c0e3a5430ed6975a631137751b9329fc9ff6dd94d9b0872a1437532e8cffd0f168e9487f0de97cd36d57b92dc11ceca6917180232e00	1663933599000000	1664538399000000	1727610399000000	1822218399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xde144479f5a20e6cf7e8dfce6f7f38765a6bb9da7917b6ce8d94b0ebd8f6b552c394b750bb460fb9cd2a85b4e88f105fc764130d07bcfd13188d3230d8ea1803	1	0	\\x000000010000000000800003a3c59497b4d4d5e4b480586460fb9ab311274c8aecaed01eb409e2c3acb413b959f2f72326b24535c84688a72cee4c233e2081922cb1a12207d1fc74f304e966d66836007ca643307a3d7d8362671cace412ac4874480a2d03310cf5a4cd02947291116978a755a31abec454a20831a5b4fea079a55b922a23cef2a26373b873010001	\\xbad13093b3970ea5a7f1909559aef4e95a3120dc8de3d7b8e5b0e0c86955e4c81a1fc1ab7609ca8ae32d2de4cac5d6e586af5ead32a645a0fad263ae9101a100	1676023599000000	1676628399000000	1739700399000000	1834308399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xde00bbab31c40cf0dd77d45a31377da6e489642a2d2aec4b6a8ff99c993a03c83e64d90abd433d5c4a94735c826896c844dd53faf4a72521fe52ed69fce62ed1	1	0	\\x000000010000000000800003e02237ebe9986cc2f5cb23667d54c1d12cfed85636792095307f1eadf2e63ba7591e3b884605e59eea5da0eb1caaee08cc310f8525ca86cc2234c21e94377e3034b10699c3d4383623375ce1a43e871c89019de331a25dd4e545ca9ee114e2f8d02235cc5d5fd27da63e7df3bf730c5e5b0f79c8f41ff2688d2a2b78a45969db010001	\\x3ceba07062194e9218f061d8e0ac8dc04e6d5d9376fb62279ca48fc817533d4b93a21c187c6c8334611ff7bdf774a422af964f4815934263528ddccdace80d09	1662724599000000	1663329399000000	1726401399000000	1821009399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xdf7c14514d4a556fe165522dd2019078ae63a3a836acdcade8428ff83a1ffd68c25b38ff9c28789cf0fb297083237f10b1f66e5cc3f5b1a2adab63b32650e60b	1	0	\\x000000010000000000800003a80d1707b27975c4827a683fa62fd6d9ca74fe3c2eda0f3d834b6821121856609306932e0975bf45f05f63258bfa212c0b590a28ac0eff6e4647b4ea3a79ffb49e819f7c0b80227e4cf07bf0ac3b452fe736781c27d87ad4a09bc23ffda132cfd0b47203fdb375e68df088cc467b1b4310992675cb93cc4a52cb7f58d38f4b07010001	\\xb86338c4e4a2c9b0599eb10a760951b89eef1fe96368cc1ccb40ad0cb47d6dee5b60632d9effd6a664b5c7518b6781c1c0ae8c7934b4329c59881e796b37b901	1660911099000000	1661515899000000	1724587899000000	1819195899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xe3b41c6e57d3dd9dcd280e28b1d09ed41ec51eaec9100a683210a5f4cbf395c22de33b1bf3c97f9c1649f5e9dac07b751b0415fa62e829f463b4b1c0d4e2f8e5	1	0	\\x000000010000000000800003d2e4d79efdc8fc446f2207c2cd99c12117d5f836ba352db787549364ac1ae24fe39916e2fff79193fe4f2962f971f6bed267ebe95ca317dc7824c71b1760cefa93c297f5f20c75c780094d310e055ecbaddde047c1be701dc1c70b5f848360c8bded9b983e17cf54d4b62007503912d49ae1f42ad36af5ce23aa6e9efaa74e1b010001	\\x4e43be836be493110f7b87a1815ca973aee759e7da5f1c66ffc3ce37ca2a836d24bedbb3f910d269202ab2c1fcad74209206f2a1e6974d25e5527cb6bdf2b90c	1664538099000000	1665142899000000	1728214899000000	1822822899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xe7b49e594302b97d73e7d451966768b5b226ce4c090d681800a63ada19c9e04d8b557d885b902e2d2950fd735ceab4045f29969c0397130f57b7b44daf04882c	1	0	\\x000000010000000000800003b3c3ea653d575461c8baee75d28f0b520e6bceb15084b2a6fd414d8fc0d13a4f0a8afc581ccc8fe5131e1f70b2bc302d1a1528456332fc475cff489721b4fce7adac029ac7aabd0883904133e716f2ab63251c92f676d40257255523012ab40bbeab15abf34cfec831746c46c3468c4f0ca72f93eabaa546ec769c22aab9adf7010001	\\x187b1a6acf49670f3b6a62f45319acccf147948caf28b4c22c59dffa28d3b63425939b5de38feb246d5ca6dd607080cb04ca80e5d005e69d4d895a64f840ee0e	1672396599000000	1673001399000000	1736073399000000	1830681399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
97	\\xe740b595fe56abc36b23273d6b98325399a443ea8ec7b558246873f0387fa87d4fdd565c90378a0e8391826553d46eeca45d46841d43b496176f3867b0b5411f	1	0	\\x000000010000000000800003aa508f2134a5bda42c980e7f1c350969d7c6b5d93706018f4b961288af9a7feea874df462007b7353375d4d52ebb09576e41c16f4974f8212489714c0f6b714f625de6465fd99d0b688591eef3ac283cb218ea1cecf16fcbecdb41342f87d79b067728fa47a6ab24882ca2ee8f2c696fe1518ad520d46dfe9dd3ad3bc2e2b839010001	\\x3e4ac89bd54d16f26383d77e31a617d52b348363acab8a729cce7819b5c9548c1a7a17ac48dea5d8ffab679335b5f0cc623f16caacdbe8b3aabedb3e2843ce01	1671187599000000	1671792399000000	1734864399000000	1829472399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
98	\\xeb38b16936be9b690dffc9447d25aa3f796cef92c1e48619b41e91270e32361f1cbb682f016e118b6dfedc44fe6bcd2b4b07debc50ab0cde2c5127e83b86486e	1	0	\\x000000010000000000800003b907b1dad6fdd1f45d13198d3ce36e6ac7dd723bb9354f9c565931e41aeafe94861e07829dc19409cb582d25266c1b3e221235972677aa3ed2679899b3e8fc1d5f1dcd4dc0c98726750c8ecd08166eaf404a0c0a351694cd546129b2ce7c065e9cf038d5ace4488839f9788b48f290c9ae5272c5703e9054866215ee05d0891f010001	\\x6b838db7a594bb5298ad077a87306a35b820ff4ea8d15ad32d4f62c8644f55a9ecc15e70564a4b6e87c2a0a2ddce627826af41a506c289b6f8070f5e536dce09	1653657099000000	1654261899000000	1717333899000000	1811941899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xecc03f343901106849b78b86dd292a0609688053d2b2e3e3c663217eea26e46cdad1393705efa9229f84c43be2bd18c4f158548e1e2b0e4e8c3a6ec695aa9af2	1	0	\\x000000010000000000800003cdcef021ce6489b178606f5bdfc20484fce058ac74b93647f9797ba8e269be4b32cd7d16515a073e8f4655f7ad009b08dee91d4a8826588331bf7f77bdca8ab48a9ebc608260160577acd6d1dea6a1f27f65ef75e3227291e6e4fc1b3278acd8886d24814914b873901570db1b1bc1cf8f6fbb33b6e7badf52dee0ba625cf7ff010001	\\x821ae4ee62f4b1ef88b5e7a4ab49cad94bafc5cfe88643d2cbd30e6750a01393be12d63cadfd3e49fd9b20cf19714150d90d5c5c8e4a2453ff5a6e4a7947f405	1666956099000000	1667560899000000	1730632899000000	1825240899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
100	\\xecf898cf56aa52ac8ccec758313fb0ee3c93016d9b031050753848936266e8a5600bbaebbbfb4a2eb7537c30a28d10a508f6c1419786295220981e616c48d24a	1	0	\\x000000010000000000800003e81294081149d3cc1330ea73706177021542c36661436d9dd77be130cf37b871b2157bc1585f348fdd0380cdbc12377b3357eca56ed385a68f520e27226ce3b81be53823adf11a8b22b72dcbc4bd443dfabfe04731f9d62f92a8f5d860ef4417cd050b383a721f54100dbbed6338e24b9fc0d7845f4f5ab5bf0123eab88605ed010001	\\x078b0bee700b08f5b47dabfa90aed4b86bd2d1aca72a7bb4f31ff3f9e4620daf8cb29f14133b51a11e49c711c9a76cf4180a812b68ccc82fa2bf38b1aaaf0304	1659702099000000	1660306899000000	1723378899000000	1817986899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
101	\\xed1001efb98e3da4a354f47e83ec0722cc4bfbe6c38a89a0025ffa62fecf5b025c237bf7b26c3b77581d614a3522bb8be6b9665e5bed98284c884a554bea83db	1	0	\\x000000010000000000800003a6bf8ac1c9f52ef709ea07a1c3bdb5b98c32f0dab651245e12c525ba7e72985f00b881650617c339722428af18412f7ded12b16975a8feadfbb8d159e25d77ef855086e52023c810890d513d905dfe93b46eb99586025fdfaf0320876dd74b5fba323b89fd2f7601dbf224688b520992b1c333f54b16669c9303b58ce57cd0c1010001	\\xe781202ab78399d635429bb88bd8d1d99e64fa2be6881236511f8f3d05d43ce9871bb908cea90b56c9f7b2a27e301ace470836b6e2cbc608364bcd23781ad80f	1656679599000000	1657284399000000	1720356399000000	1814964399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
102	\\xeff8407605e21fedb86f18c07a301035babc61d8821acfae362965bdf61560f9efcc465270dffaa5fd2e34cc22f9c968b9f62a2c58575bf0b2e8b5946277779d	1	0	\\x000000010000000000800003cb625d6200a0b91a3abf7ce3b4d5d7ab781db81606feed4366b2e8d43640ced385b0b53bd2cd24153b48773b9a91deff0b0220ca9594b9e5abe21d89816d6c31a4c013a8f584f1c2ea23919a9ee5d782bf674eb638731ffc5201570cf063ff792f04532afad2557617ab481b045e62312b53944d744bc1f749a21ebf6eefb75f010001	\\x17295e9fee7c8921efe46130171f36ee5022c36b6d7d3302aae3c51c6d2f7f28ddc96fd7ba3e7569f6c22b7d094983e9c8535a6b566b4167a80ff4c9b6dacd06	1678441599000000	1679046399000000	1742118399000000	1836726399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\xf01400b08e31fb016c73724d9307563b5d84462102a95291f0b8494d1e6b5b6506ed6eee5778283dca38c6327153022673868a0cb0afdac6de33bec3f1791b73	1	0	\\x000000010000000000800003e2621b59aa45b3fb2da2b09fb68ff93622201deb4bfb3efae8d5c2865e796020e1a53dfaf2db61d7222ba8ac5fe5bbbf83a41c6711cfe8e015e7f4d225aabd653ff25b477634fc19d1b4bd0140ab38321d7bc8838dee9c86a85b12c146af398609031092b987667c06ace2eed9f92ae7cd68d96b72942938573e24e932da658b010001	\\xbafd4e25b6be929bfc124d5fffce61dd7f7e9c4bf0a46a91e72132c9e4a1f543d2f364c291d5f0dfc0676433056013ffdfff91c1e7a2e1fb3e0b558a97190d0c	1663329099000000	1663933899000000	1727005899000000	1821613899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
104	\\xf2b89b15feb7c4e32fca6339791a42c07e27f5af7453b884af2b5cf647591e614af90022481dee4bca69e738d35ac50c92a509ea70e0e4704278999e51ba5c9a	1	0	\\x000000010000000000800003f099d668e96038553356d84f090644cb3d111ca71c859e07e4b4d0b4d14a86d46fed83d6339f3dd7f99e73ed48b5db6b595f7dcf069d77e7c99ec17d3857042a09daff02c86dede887fd07c37998b2d62e583a47bc05a66681c5d5706c293253225386f5bda24723f2c063f3e573a54b43ed88a6e78b93d3d96fc3a75bf7c407010001	\\xb651bb477730fde4e0f83ffafcd66a90330a98f167d364f30d4c09a6266f348948930083cf34379ee1c758ce778153a153bcec1cf2bf7ef5563c5d655b640d01	1654866099000000	1655470899000000	1718542899000000	1813150899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xf3301effd53cb11aaddc4a02f8a4bbe030a8c75e559c2bfa450a94dc42515b34037a6079844f6505ed2afa2a0ec0f6c00b5e0d615555d74755bb43c6be63b270	1	0	\\x000000010000000000800003d019951c4e96742c94b267a1b940571f277e96e6a782b0430422b79b5ca49588b2c8929733be97f12e98c4c0d4a28b1ad7e7727ad40fd542f5c8d9dd6e90d5e6cfa3ba6e4289534a48948ec0839bcf459f509c246a0a5fc274314db05d557c3de71df41efd8368ed39d803a98a1637e7e41aa381c8e25c6827bcbdec60d5d455010001	\\x8c42a9c94d9c1df8e34744c48952be447bc59a2be8d3505622495076ae948c57d9e7e6bb03d23c890a94e4ea839eb8e029c2657f9924b4cb0eb87b2cd51a3a09	1647612099000000	1648216899000000	1711288899000000	1805896899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
106	\\xfdfc09aa71c03323e25b9795bd1be031887f1e7548b2ada9196e3a2d7ea686a88132c72e54151fa2463dc7c51af65e68129c3f071f6e7cc64bc011f5652b593d	1	0	\\x000000010000000000800003dbec37fc6eaa70ed5134f7c5b3b4d90b7e50c63099786eb525b0873bea0cf32c42f2a12c704db4d02148de6397965d2cf8d42f3a94c40770d6e34b7b1f78f79139fc90fa2ce4cab180272dea67d9e56fde4b8b218d48a9b58acae66a03f686ebceb53456551638545740a7de7dd04e50c3e873a727f46058759ab70eeb409849010001	\\x6b71877bd14f17ef3878a5c8b795e5af68fec03ffdb64abbe209b59385b0b22caaabae189deda22ad1e3e2ab9930781b6539e67dfc06a26df9f4577abccd9205	1655470599000000	1656075399000000	1719147399000000	1813755399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
107	\\xfed40da30f638c2f5eaf79f3a186775a9071930f042e243a7207d7f66555b08fe2888ca113ec2bd5e1fbaedcf4d837e2e993bf2e5b37ea286edf904d1dd7d6d1	1	0	\\x000000010000000000800003a5ef25f78c9393d18e70280522022423933380b7b1751ab21a3ef0039540b865b98109f5657820195e4bbe7dceca8522d9bac1e74fc441b550452b1f832ad3acf206d935b754f3df8af3de5f9aa2a2e8753a1f685c794bf11228132a12ac278d0c8076c9b851dbc033e42fb96df8d8cb1bf96e32affd358a4c6657c03d8d104d010001	\\x99b3ea4cc5069913c5273b493de547dbe50229b30507403f12b06a0e8b6a6f8e9357b561d0012f4a1c5b8ba946562e88be1e4d9a64fe53fa1b0d0f8646a91306	1659097599000000	1659702399000000	1722774399000000	1817382399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x023d24a23bfeadb9c51a2382b8a93699884a8031a6be1a1d88af9423ecbcd3c70aa58ed6c295cf33574336a9758aab545ee1a23ec25d22d10d45d02852b9acb0	1	0	\\x000000010000000000800003c39dac3760703eb4b349a2e25ee30cfcea8cb48edbe2b6144800456de94f7abfeb8b321e674a1643898cd38bc1629eaaa05d3bcf5e2eadc348ba6dc8e2ac296cce688400f061d0731793f29c7d044d96915e5753a6cb8078fecf5f7db485530dd65c613ba8123d15b92b64b591242cb18fddf46ab1a955df8d871a6c754218a9010001	\\x706258134a03e4dce375843260ee3e4e9cdded69ee36ca48e4d73a0fa2c48e0d9098f2ba8230cc27b4e6ff3d8d7e598d4dbab42307c7d9d39490d5fae424b909	1673605599000000	1674210399000000	1737282399000000	1831890399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\x03714ab0de4afe0f17c765caf0d487609db023de228531feeb920298c40a5d72afdf09be4e6a10b5898c1adcf5f918fc3caa978cb9b5db9fe8ab9fd334583cde	1	0	\\x000000010000000000800003b82de03122f7ab7a8bf1815bb453a3e116773eb77a0c6e4271dc722d4cb9f917025189f12b6a3349b31e0f4488e8a5f2b06ae71b80e358b606bbf046707153cd54212c7f57ea07839d132601b8d1c2535fa38947f6a127994fbb46b0bc2fd22e6b2f9724f285ed5e334d34af87e015b0c4e3e640f6df732cfaebec9a6448c2d1010001	\\xa74147760ca680777dae5bdd9a3f8120356f0afe74db3775d64466c1e587bcd65b3c13fcd62b12a1a88accd4047f58e896197dc1917d390a30fa64fbd26dda0b	1652448099000000	1653052899000000	1716124899000000	1810732899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
110	\\x062d6a2695768f390b4ea778a46cc295480514f07145056e89cb6606c19259f9a8304b079634ce8a963dfe42f62aece2de57418eb6ad51da349a6bd42de934f2	1	0	\\x000000010000000000800003b59418ba1807f2e26d8a5e1e3fe12816609c8aa847db66f661b6d357e47f52b4c5117dddb3da74a27bcaad7bfc05bf7ec83e34222e836eabf7b58a1d49fcbb6340e548663ac25e4cd46ab6f2244969ee29c0b0f869d59333c1bc6f03b6772c3562b2d2d9050196a36989dd466802fbad2681ad2106464ca960768e7458a94c61010001	\\x4f19136a6ed023c76241e39cd28e42f26ff220521e7619e26c224897dc8d6e20ef27356d004c3196ab3141913cfd1ad36667e80ae5aab4fe381c0297c3646108	1679046099000000	1679650899000000	1742722899000000	1837330899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
111	\\x074d68016b5930c2962a86435764a5f10178e22ca09af84cff7f6461bc20c1777970f47ddd7fdd008c29733d84a147972b33470bd5dbad718e67429c8740c00b	1	0	\\x000000010000000000800003d4a6374d48e2784fa987e168206f93287773278a4de04783890be1320d010d0359a31a71295e8f17cd14e1d4406711f8bee2bc38a2587ecbe76a50a4e8bfbda6ae915599e363b4c007c709dd887459ce5312a2ca65a87bedc74b31a41b06ec0d9b7b8bf2aa97b0b2c4b8787a4895add8eb1b2f4f20b6736de65ffb8b545bd3f9010001	\\xe4553dfbbf27d42f3c68acf85dc9f2b145b2265106172185c1511a0bfec2ad7779c9904872154276c06d92207c1532572ff1aec89c44ff52c3851bac9670dd06	1662724599000000	1663329399000000	1726401399000000	1821009399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
112	\\x075d71cf48b5de0029548c7ec831ca9970357078a86349f07157afad9c1db1f39e0309041a4ee50033af3bde59bd1348577b8522b471a265dfca3d12dc5cb336	1	0	\\x000000010000000000800003e17136dc4c3b91dc0ab46f5ef6cffe118657c363a8338f1f68b87ac03eef7317bd4eb83de879af8c1f33657413b42e12d5f70de6658c98c79123f72e211328c6757784e1a9b27428136cddc173eaef3ddd35ae2e72f9fbcddf1bd02cdfaab4604c4cd4edc0e63f6ebf41dbc2a3aec9b59bae6f5fe7da807177df15512c9735d3010001	\\x217c0f3b138659821f8cc4806eaa632ffe6a1488e91b02ad1a3dc349c467e84590998a6515b039915c98a5cf346a74f7b4f3fca5e3ba74e6071df015db687103	1652448099000000	1653052899000000	1716124899000000	1810732899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x0ca925756e46fb99a6de50b31b9d51bd0d56eed5578e890781b39801246bc7712f24c692f56df237edb3d219ad1060606f25e147f5d11e4cd00bfb97dbb87304	1	0	\\x000000010000000000800003d34e5ae918e5ffcc3899ca93174658ef82343a6849ff2581859173f6d86fea89be49973fc9515cf9d957e831e1d9df5e50f37e9d821af70f3729a09d0ac7c8fbbd8ff661506991618f461bb1162e1fcd8ab5673e584f800e0e536f7cb9760d539894c4e13f38738c03b08fecc745cfe0ad9351c4fdeb450a55a838e1549829eb010001	\\x72dd6e2a688827de205d12b3ac2834b0377b16e783a6ea81932895c3935c71eff98495df6035ee4ee464a6a7fd900de91787f2d5fcf3d9a139b68b76cf791c01	1674814599000000	1675419399000000	1738491399000000	1833099399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
114	\\x0f31d2596a7fa3fac1ca3511d7ebc11225c90f519c3592cca321ba88a2318308429b9cf428fae087c3ae876f51a78ab2f75fcc814eabe13ec8652844b4f33d4d	1	0	\\x000000010000000000800003d6ba06979e90e715ae1452e057889a6f2234ba43a54dab50c3697ced3507c5859b4b7e3dcfb20fb2d9703bf2b30e21c2278cee5bd9f506da65fc4fac414e3369d512ef7e079239cbbcfb0a3d2bba7bc0e119d12ceaefee5bf7d50c0059b1eea26e0956d74bcbff8479c42da97ee3966c534de68383ac677fe01b4356291fa2e5010001	\\x567698c7e6734d83f961b28d07c6e75dd1919cd60e096646cf1c9e081896a816bd1b81be736e8b66987ffc2452bf41bf624ee6d87b30ae5a7f8e3748f59c8402	1678441599000000	1679046399000000	1742118399000000	1836726399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x11516fb7d2d48ebc552f8019561ca6ca12f818a7dce83d5b7de704034f59bc28d6153c1bc49b0388f15c19f1019b6f3dd42af4ac3ac1fa7f4ddde4a33e7c5e85	1	0	\\x000000010000000000800003e9cd38c47bbce18713799bca72762f2c1c1ccb35aba0714dd6aabd6f819bae19f11f3504157bf179612b2af6ec02524f44f1fb66446822cb07b7112741995d5559641562deaac9da59c76b385e38cab049339cf64adff024118c580c36493d6424f9c3f7df6dfd838db86c1864224b6e9aad3c56a07b1398c1bc011fd7ee5619010001	\\x9fcd05046a6efc727c3c4c124bbe5dd9d26a17888b060eff474997ae3d77b88e91c3ba497b6520b96ee70c0bfcc9591aee5a033312f937149e838e7f96c11906	1650030099000000	1650634899000000	1713706899000000	1808314899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x13292c3f07d570734f6b8d743f54a7919e889fdb676eda16948dce674570f63cab9df070c7bfc0286b20b0936cf5b5e39b2eedf2fb469ddfeb64684d68dbea6e	1	0	\\x000000010000000000800003f2bd4455a278786b04480c5a1c0682626534e927308002c937465fa79ba6b2508eb5de1d5e6adb0a89e86b0f2fdc3f43b9160817e4b5badda5fc68b95246e98ba59bd4957a9254253c519404dbb37bf86fad4b93ea2cac8db1e7520dced175d70e45cd71d3972fd781038990c50f8f1231c075fd517f18da30ecdefb542e587f010001	\\x10617318fb01cd271013a351f1ea612d7041bcfcc35949604aee292b62881f39c5d29becbcd21ebe0223978aefe255229624015c6384afb557229c0c09704d00	1653052599000000	1653657399000000	1716729399000000	1811337399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x1751ddc27dd3fc6512efff6d1c6582c0aefac99f738f9a40951795d6926986c662c697d33d48260fc4b199a1ddc2c031ced6b82fe7462b0ffe2072ddb348c5db	1	0	\\x000000010000000000800003a9daf4352baf8956ca3c8b297ed7edc6cea20e03adf0fe1aa5d90ae8ba4a6f54fae7741f9d9f0aec4bcf3d7e2a9640af51a79dcb89e19107647b29ec2ca1584986f5c7ecc5e1f7a809c19a9888cc6caca5ee4aa3358bb7769048d0ffca4776db9943f08fb70e1513f69da4adbf45a96b255bf0ca6e6888e6d30f17c829d6280f010001	\\x6814a51adefb3922521eb7b96dfb9396e94c5360e2810afa301e69dc14237e66016385a116673a2c0345db0be778be266fc9283a99595a8e8e3aad7a1727f007	1677232599000000	1677837399000000	1740909399000000	1835517399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x1a616ff51cdf9696a35517892510a84447c883f09ec8c015700755fbc853ed18c2959dea66273eebec94f88328b5cd3bff7ebb7fa227e59de60141023a42209e	1	0	\\x000000010000000000800003cd42be8fbed7b0f7c624bdb389f4f0a39f7072baacadc561f4641fe62ac90930e54f47421e1d78c6e4edb3ce03dc15c701ed7adc861619c57b33d7b90e00ab6a514489d1b42dda53b0a7158672131b517f9d12e61b3858004ed032045046d26d95319e6ac600f78fe2f3e294dd56e9ba4db074efbe7fc45e06d307ae5d705403010001	\\xb03a38f257244c35e28d67eefbc8aef2aacc2a8c3fd2b5c43fb8cabd1f25550412b979b17dfc1188592124e36e3d690266363475d0ff021fd93b891a7d502d0d	1656075099000000	1656679899000000	1719751899000000	1814359899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x1ef1fe4472dbe66f7f7cca7740902f07393eb6b9f981fb4a19e1de49e64fec263bdd7d68b7a851cad2dd523c5903b68a30b58fe583575892ea49ed6f9459fd6a	1	0	\\x000000010000000000800003d7e8a60488ea37c6ae301c4d65e82b6176328253499fc623572d4116589c4092734f9e4a672b7fabeee7e732786f4c336123631d1c24aeee86debdf2af852cef95385a5e8d5e9ae3758daecc6177bc6d3911bb917ce24ddf5609fe2afa7d8adbc1c653ed63e3874d652ce59f786059f383e7ffad16b7fbc6f05bea76f38c4495010001	\\x34f340c1d9c5548d2135b74a86ed41a7970de6f38133b5bc57813a542c972bc33ea4336000d157b622e3900916074b58bfd6d176f33db5e7e5c0943c0bb39c06	1667560599000000	1668165399000000	1731237399000000	1825845399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
120	\\x22857c3a6943783b0ee360ee83c7c9f9e648b0c5017e3a6a2be927c1d569d0d3fbf840650a3e5493422ee2dfae2a049a95a4c6f58c132626ea13ba9ce8eaf0ee	1	0	\\x000000010000000000800003b3402aa8664ba330c5217fef0e60f96ff1b9f4741bcdebe15cd49dfa68e727fcea6a2b084295cffb73d1ae8b899b4b49300c7918a875fa0660355b435fafa06ad927b123f2524b4cb9d07ef796eca17ebb81f8120c7a91d6631673c06a5e2c07745031c5ae66667e6002e19d635448e95c317c600988e263da7638d9f525ae3b010001	\\x0becacc404bce1b01537006cd818724143c1fd4543e7513dcc727ec70c18fab3329871e920ef1f19e9f86d107805b84e46537be4c606ea4654d0e0ffe1482100	1648216599000000	1648821399000000	1711893399000000	1806501399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\x24ad44be2f891c322f98857f8333c4cd3531db020f9d5b852b2fb61eaf06bc677d0d64ed9bde1a890ac393faebd3c53e2440d57cf714494595a5211fabc0a3cf	1	0	\\x000000010000000000800003c1cf01a04e8222fd1da0fd2a81ccf6196b2fc6599cebced63ca3912b15b2bde734b87bffc0b6abbfe76dfbfe18c811fef264e153721d11ac73079a128bf268f07495e129c4e15181d7b52e1d7aec62bb1e8c04b48a98efc505e9730a957b39445de154090793a41097d4a315f59b08a8672ed1e8811f4557505321a9f44fdffd010001	\\x880b3a67ef0776381035c8358fc08aab91747e7c86a6e8f7af7cbc7d1ef5e55d3a2101ee3e4cd8ba5241fb4d3e9e4ca001a636e5331d51061bd11ffbaca8ac02	1671792099000000	1672396899000000	1735468899000000	1830076899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
122	\\x245121c646406cc8583bc40b963eb89ecf991cbfff8b7ee8708fcb54a9930dbde99143e0f7dffcb53c29c10773844bfb30b4a3279476b326d5afc049ffb7aff5	1	0	\\x000000010000000000800003c3cc17e595387d6564af68dbac0d2890018974b5b6a410e25bb6f95aa19c1bc7f064318f1e9f972642e87b40316306c0441e788a16d182c38b893413335ecae927d5d984dd5a6c22771af9cbdd6d8d9ba81956ef3990f12de869608cdb6727d1e7b1eca2668ddb62b6307144141d1e1bafcfbb67527a9321ccd2666e91c676e1010001	\\xc7cc2338aa84dbe996bcded17b04c90111ae277b7d04f94c50a67de4c60ebc5eb5c38c9a11971b9ac065ba8a4eae0b10491f7d13a3772593e6ca58ef5fb08804	1650030099000000	1650634899000000	1713706899000000	1808314899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x273164942f8563160ca6d5f9bde331a15ddb88b21a8958db5b99f974234c9021f4d83215c0efa977a6cb3b03da4424dc0abdd1e1f38fad0857b6cca515ff1fde	1	0	\\x000000010000000000800003e45934a01f7654126d52a168c8e0c9ad9166c986ad5c4f89be6e25e09a7f55060a98a305cc5b42c497720b6b5646eaf18aba3d03cdc34dc82944b275f6f687f8270e7386d1987b85945db070c677950cd5532217deccd384979d9bdc4048fb1344c9fd06b7297fe1f0694d54d600844af535e8e1587b37896bc72eccd27fa2ad010001	\\x02e9014044250142dcdfb0e9c488d08edd5b2877f7cfe2c016afee264c05853fcf544124d09efb1c70e233d499ccf9f90f9ac0be8785acbca1acb5771589ad04	1672396599000000	1673001399000000	1736073399000000	1830681399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x28918f82399275e79120678870e1ce7d8a835d3615415d6bdf48a5932a92ff26e3e1b59719b752a744c4560792a12c58f14bca07b6e368fb3d927b98ecd33cc8	1	0	\\x000000010000000000800003e95d988d9723983ae89828a1f5ba1357e4a94b610d16302b641c46d1351ff6cbd33de77933e3f84e526eeac43b18e20c9eb6e21f005a1f3d91b860976c88ec5b8e5977cd3014cdf729c7c7ecdb3beca2982f9f81d518f0db03ff5652ed4f05c79f5b2d360d350bb5fa33b80370b45e45a234196230ef94f7e7b10d23655679bb010001	\\xa478dff84e846caf718834b2caa4267785504c661ae27159dc85c8d3f9454f1c2147e2ea9aaa71c5b144c356be418472aa03f5e4e544df3053ffcfd7db32de0b	1676628099000000	1677232899000000	1740304899000000	1834912899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x29fd379119b3ce769ed736cf990d73a34565fe93c3ed2d8123f39410ef3ffa8b69dd7b2c0e9df2c2c079a9ec4b1a93f9ecaeebd3b1953f57662f0e11cea41bc4	1	0	\\x000000010000000000800003bf8346153166070e50f1125cb244a5a1ee958b98c266cd3f85e467dc68cb11997ad000dba008b6b768bfde52b1ca171355a5ac3a913361f7b23b74b3e2beb4648deae888cfbbe77e83c1269063198de32b8708157224157db05a718cdcc2c2562c80fb943baae3a34d607d44acce2288096a83836f281b562bda8116454574fb010001	\\x27d96e341ba060b50c14096499211ee987b79fc550dd5be35362147218d8faaca6fffa45f1a15705cf0b68bcf69ab86f1a773377f65676e75f85daab46367809	1676628099000000	1677232899000000	1740304899000000	1834912899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
126	\\x2969f0e034ffa97d8967fa6600ae24a41281835dae1e46055167bfd9165412e891e90b7bf8d54a8c180b0ec8878db3a8059ffa058892415f8d47661f09787953	1	0	\\x000000010000000000800003eecb2b519938e2f1a9fb3bc69675191440ee249d59511ee9580e71f2596bf414a138cbc70392d51e739accf14ddd9ab22f9f9319d8b3dcc2b0f6a60ffc4308ac4d52fc199c86c83ef25e5f7780157720fd507d3c39f86583ffe194639671ad94ad9fe88b266325f60ce4a2b3a21f00295d40716eb86d66187cd83c674e594b31010001	\\x599a9a53b3ebcf5899b5526063b0253a4073df10c7cc5d1bc8634862dd77b21b59e0cdffc406b516e94cea7e6ffda3b4d14e12d596316eee427081d951e56e0d	1674210099000000	1674814899000000	1737886899000000	1832494899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
127	\\x35f5e019604b0167f8ec927b0e3a577335a5651af6dbc52874ae7e60df8cd413d2e664d7b297d5067d1fd28b8c43dc097ee118b5efc15eb8b76f3b725cb35a36	1	0	\\x000000010000000000800003bec21fa7cb5852ffbf11483b6546ec5b211e285372a57a274666130bb2fea5aafc8d94e986808a6ce0df908d8bbad55566100cd5f5cf37569dce5a48fa7bb6a95122c3e611c4a6daf6993e31f31bae587b82a8e533bfd9ce1f2fd5af086afc8f28b2006442e711a3f7250095e07ba119fc4d30003ebe5bdd3e1d3acabe4da4ff010001	\\x1bfbd5eac14da54aa5f611db99c9ece55cff35bb3e86469ea31f869f3d8db3edb1d3bc06490f4edb47dc56a6c01215c099f5196bf86442c7acf04dc6e8c4ef09	1665142599000000	1665747399000000	1728819399000000	1823427399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
128	\\x37f132bd86b55d9b4700b09090446d2349a93d6cead11c5161f4da17ebf8a863e3286c352c2ec29b8e7e7793d11626d799358f85edd9a499a0a7bf512eb91d3e	1	0	\\x000000010000000000800003fe33c6568a8a2951cf71747317e64b8c08e228a6404825c273f0d27e2b54da21f260925991ea136f5386c9fd794d5d16267bce72427e4c5acb43d738dab555aadf8f2f5aa4a5a1cfba7f47dc49493f21a5f45bbece82ebc504f74c44e42e851778ecee9eb144b52355b49ec5ee8fa6cdea9b0723bd1e2c90e6728466b5355c95010001	\\x30335dc27051312d65548794dbaa255a8eca2bdeeadec2c0265361755a4c52e18a92ecaea63163fa1c4b0dbe8d495cdaf674d53d5906a0584ae3f2e434482508	1665142599000000	1665747399000000	1728819399000000	1823427399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x3f25d70e1caaf56ef6263b791bd36c440a1d845f54a2b9c196a666114af0f1323d9b63efbee8f9dbc17b2a60175f9dc03a84b32bb5548d94b2c5245d54aa9909	1	0	\\x000000010000000000800003d8e6021789b02fa463f3ca9850875b689e9a4fd21a3afe564ac4c11c3e824dd948f89eea523798fca5c1b18861b3b6d3fb9a473c82804fbd37385ae9be59ba16bd480be3b513035332c1504059b6d1c3d3d3820023898f51d559374dae395933a262dd00eca6350b2984b54a29a04998499485fbf181958bf59f2350e30d3f07010001	\\xc86f1bcef5eb2d472a38003d391559b30246469f233e87135445c69421fe4b1f8f4ba6ad75e85aca663c3b149f57b06e6f7df39559def2c3daf3361b1ed97604	1663933599000000	1664538399000000	1727610399000000	1822218399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x40e5a5d58a3088d31c278b088e8deea146151ff85b8c097347f82dc276e896dc6a81d357aa9d7ba760d7fea164620bf696500f369ead04b6b2e69c38c4f50168	1	0	\\x000000010000000000800003ae5ecc5c6eca9f37e364e26dd10fc0963dabc0cd548460bae102538077f137125f9dd045bea27e9c51d231a80ec092d63b08e81e9695d0a4a3b4a4640b8a5d8d66db1d3f359956b79b35e0f81bd0789f4d803eefcc06fc9ad420e33014d84bef7d5ddbffc4aebd2d2d8af147a898314b8bcd8313537a3ed2c0a420bf0edc48d1010001	\\xa0f995e1c05df419ee5ab53b8a3a90b356b57df4ec1abde3312682d4c16035c6cb8eedb79f182327bfc8a769e6627b9cdb1327a2cb9a05f5f46010db7d7ea80b	1669978599000000	1670583399000000	1733655399000000	1828263399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x43a5c3361dab454c8d5092d501363bc266090340dc491f28ec4dd010a31a81f0abf41c467c5ccd40c93bee9805cd972d3dd486c184666199ed9fecd454d4626b	1	0	\\x000000010000000000800003c3b1a588f9a9f41fe73468570ee734ee3dc9c3698069185daa949a62e322156d5a8f14ee7e22541758d04990bdde198beedce402aea8986cdc9a2bbb97522d7ae9db60c530f44639892b35e05866145add353e1b4c83291019b430928aa47c6ea26b8f3c6ee0380d5b4f9862138eff43efe667778f6ad8d0d27c173771b3bb57010001	\\x2bd13688cacc3b5e44b82278116c4bdb33e5effae8092155d8016d710752b31c0579dbd18113b655e708051519d87e0145f3e9d30c2d3311cabc7bfb0346b90c	1665142599000000	1665747399000000	1728819399000000	1823427399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x471df3e43cf1cee315d415c86601fc9cbde5a2b8567fd66be61f8afe432be11b2454f243bde9777ee1f1be3df0863354b4d8e6a7e1903b89a98efe4d601c5b97	1	0	\\x000000010000000000800003b1c651139009589f419773080b7ee4bb69316a83f44fdc8f3f7c2f34f18829f54e5549672dca8def220511fe464e8cae98b22bf728114c0e031f8ba5a6f62045a21ac777e1ab8ea2ff5a70e3ea2e377d9b6c8bce3f5cb12204cbbe3668bab4bede001dc85e6fb5ac44b1fe635460721dbdb677a64b4af7603f997b5d913c7f65010001	\\xd2ba99445c048cb21b0876da8fedda974c91b82a210591721f5183db3c3313d7ebc9a8f1672fca82ee3cc19793568abde55481a8c5b3dd3e0f348d7bbf6aaa03	1648821099000000	1649425899000000	1712497899000000	1807105899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x497165859593eec104fcc9bbd6ba90338393dd09fe4cd6b42b0e8af225df3fead9225bc6b7455da868deced54e17407ffc118034bfd6a732201473f5e2d1e02f	1	0	\\x000000010000000000800003c335aa8229eec3eabcff658bed9373fab60968631a7d2b8d1f963159d60e3949e2b0aaf32000f92900c3149103ae32c08da485a65009bcc555834005e138377b4fb989a699e0ce7d599f5c9430f1753e48cad5b2efe16ce6320efab9d49122781fdf11f74622c2445de546f3ffcf46ae1cbfc04fa3bfe35c213fbd74f2d5dfb5010001	\\xb69670e13a2e17c13a3e27fac2b2a6edbb830669ace5bf343ad125bcfdc99cce98e71659e07eacc5ec611dd883948ac8cdecf4a44e4294488b371becee680e0f	1666956099000000	1667560899000000	1730632899000000	1825240899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
134	\\x4b75befb29e8ed2ef82db5187864b8f4e808085696bd7e68bd93c1a95ce7ea425e58ddfe75bb88c22c280073b25609961c25c8a50d1df321c4abbf2631abcaa3	1	0	\\x000000010000000000800003b5cc5ea4bc03c673c56d9ab64dabf37ea8b086b9cd03d58ba803d9ddc006cf1394f3e527e9073ca8cc2379a30ee21ad5b553812020aed6e22724be7cdf6e0c78e5513a9a6e0e9d36fa7b11b688495d454e48aa89d39a6459134c36703c9f05c2c0f99314ea49e98b4bce5f2283f9c7b758f0dd27745eaf2ad59b781360bf091f010001	\\x47601028f3b32a5c6a9281209b7c9d7911db00a23f4eba85cb4d29e2ccbbe3e5edb8ed17eee2dd78dd739cec8e17641b7829c77eac47139965e3ad089669820d	1674210099000000	1674814899000000	1737886899000000	1832494899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x4d05e83a48eca3179221def870081b03a926abee46a56769d14c3e7aa07a11e8d48d4fd9b63d95f595c0e0a8e1dc17f4e190347310cf660b701b6b0403bd2e7a	1	0	\\x000000010000000000800003c3e9a9308a40aad8d00c882860843bcb21dec908c5c58a8f06c0807d3d2497548e0cfe610b2dfb5fb266c3c274cf8bdbb814020f829dd217794cab95c4fab461250fe0be1e8279f5eee25badcf3efc090a48fe1cc872821d2ce41757111a2ad946aa7d746a4f431d13174e70dd502055f0c3df838063966cabfdef017c854ff3010001	\\x98a1f5ac4538308ba7a352ecac8b4da863e861327a3d2684f8097c789eb6eaf4220e77042f7f8bacaa4ee8b792e453ad3992c9f777ec23afa8c4e9bd12dfd500	1660306599000000	1660911399000000	1723983399000000	1818591399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
136	\\x4de1a3f5671370314577dc66c4f6036fda8c0fb4dd9a859e0abe039a737a905b8bcc968105797089bb65a81be0d9343b129cf2061cd327cbeb0ff10feaba351f	1	0	\\x000000010000000000800003e50f97a16cfa21185c0fb3e8e2e0943034cdac08212454fb49a47d8a50526177c97caaad6f495ae2e08801e0f241e430cc1bc946fd8bb8cf0db12b332eb27ade9c9d1f47a214e0e9130a392fa16efdb00f44845b8006cc0a7c5b02f41c958f9c30312aa2429146fb80168faa25e59ba5feba5bde30460c968f032228ed6d6777010001	\\xa67a4f76f8acf748f7b7a5a3b67492a54b400411183abc37a008fbc11f73e8ffedaa0afba1e1d6f793630817867f8e945372d556e7825a441f98f3ac4d10f704	1668769599000000	1669374399000000	1732446399000000	1827054399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x4fd1a0904aed918dd12b0d800ac2941745a1b6f6d09650d5f064bda2e3964cc3b0ac63cd73ca61213d8f0107394ba79fee32526af19b903b011f5783991cd8c5	1	0	\\x000000010000000000800003f54d7b74bd5d8768821dc5c7133f0359360797b4e4d93f8ae7d6ad2d26c78e81e7f664209082571ffb58b44475a7163c40fdcc837fc0ec38d8ffcb15eb966c292171ae5507f015c723c8701e3a5c4c04c17fcaf27584210d3c27b678fd99b9057ac534a224babab79081ca23808acdc41d4b2917ac5451a0b9b669c8c2165a7f010001	\\xcf15f02d67746e527ad1923907b669437847f6fdc52f939a15f85fdb36a802a373607cab33bbf4beac65e7aacea7537a025d3d3ea1e20ffba64101026a54410a	1670583099000000	1671187899000000	1734259899000000	1828867899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
138	\\x522d701ee796714ad290a8a258e0e9f1b43c8c9726df70a8f405e7cb3c78de9a17482d40c3035ceceec3ba1c750d3c712f08091bc95be500644f7bb757d94139	1	0	\\x000000010000000000800003bdb56b3c2e816ec3cb911bf2a0c67a317466175bbe0630c21815138b0982209f30b96c0b1a2a167786609b2b0f488a7fcac2a7941d4335def69fe1ceab218b79ebeb13f7daeeaf04d17199be14dda3dc2dfda881e56d121ec60e9a6e029ab0489164f539a1aeed467d296ac04e544e0ad84313c3c1838269db7ae7f5c85d327b010001	\\xe19a61188e3322d191ed7b4044614866763da20c7fcfe6cf87c3ff58ce0c87e1a3dc0f6787b8ae02764c5fa8c54d98b10cfd1aebbdebfaff2fbd53ea1c669301	1661515599000000	1662120399000000	1725192399000000	1819800399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x53b55ea162b1bdf9b227c43d5ae86a249624f801f58801397004e43434a0f6703eda35a54e4cda93c2c3f35bd04b44de2878658bd9c2a070d711ebe2e3729a7f	1	0	\\x000000010000000000800003ce3f61c6872addddbb661e92d493e3a3ad74bfc93ef0a8db2b88a255a7dfb7ddfd315112f9e27c072a9a60bdd21a863f3b34012306c504c970eaf74e696a53fc7d455cbcb28ef2bb21bb6dc9fa4fec7c4f575bbfd8d2e41c8881eed51dde5d43ac66bb6719485409443fb825fb7e4a2f1665f70182c1771a36d63e19a7f8a845010001	\\xbab53940a15824ee45dd802c6e28b8eac932d2038448e268adfd15eb0d9c01b70cc99e31cf02d3f2b836e36a086a2e948a10429d7f855ce47f67ab615bf6a903	1651239099000000	1651843899000000	1714915899000000	1809523899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
140	\\x564dbd4735de6d591a46bfaa6e58cb3728bf79a378067d301a33faa254d4ddd3794a7bacf276035a3a8ce3ee40d9557e4aa7b6ef7c673d0102d2e57b20cc08da	1	0	\\x000000010000000000800003d73977e8664e83d735cc25e4b324aae02fd034a59948006d00ef5f622dd1ff569e2e477e8215d1563d0d2a6d64caa888cb9d0ae810ee17f4d75f3355745fcb61bd644d6678f661b3d1bd682ad596bfdf864ae6358d6e6fbc68d10a753b1d4fb85c7e52dd4ed2a70b08484d615e585586d12096cf9fcc23596852ab2ab6d40f91010001	\\x503fa377765aaeadc435ef2bb5bfa68dc8e4b74f25f8b52668ac37e8380c937791f896945399c52e76b5045e3d30ea29d582f05a05d0ea0dfbe099fc4ceaf006	1666956099000000	1667560899000000	1730632899000000	1825240899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x5705f4d1b701d5f494304f58df15051857cdc6fad43255651914305c6940c9aecd2e14558c81895681645ff09dca06013ecbb5af0e3fcfc737b598d4888a5a80	1	0	\\x000000010000000000800003a41e08fac5378ad044f37198f35927ca65acaeffe5901af075847e9bea43ceadd426825199c103ed2bcbea5f35a1d8666d6bbbaa50afbfd5b1edd21930ba6980260210f9fdf00a0e5cc66818eb5778da12f7176aa494e51146035e4eec87035495f8c0dbebeb5b0118ee9cd11ccf0752b5cd92f1c3b0e29ef2a79429b1a52e63010001	\\x242928ebb7ffcea76367bef8b48fb0339b34be56b92807750b91c0a45595e1f5b02387efe3085bd29902023774b2433b54e4c6e6f09ce84d270096c8809b6507	1674814599000000	1675419399000000	1738491399000000	1833099399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x58a1ea5788cfc387827e6016235e6cede05d2b1ad9edb0450abfb2b3cb83fd174c1f44e23ce3d7609ab24aadc6c00e7d85519af76324b20549ca872a1089f257	1	0	\\x000000010000000000800003d74af6859931105b57dc5ae507a2c7f123d82041675506ab70e99c474e50a3395a3e52d159543011a308d5d7700207b732f5b7de099c0c2641cc0110ef9a05eb49585eb8432c211d8bdadc692c9bdefcc0c137a7fafaa7c631940505da7c99bac9965b68b458a16d74b4fd3d9fc79b94fae8fa741dd0bfd640f589206418423b010001	\\x3a53c585b762b8eaaf4c759a5f79676474262645950a169477ac9d45c0fa22db7ea6b5c36ea4bbf1740daab47538c9f913857d2a4785bef637870286b668ca00	1660911099000000	1661515899000000	1724587899000000	1819195899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
143	\\x5a61729c2ec878ff8b6366c918623e91cf201574e0ddb3f71c36f74df1c1219dbd8af02ed902a269eff628424844087562f4dabdb7c267fb7801760d74797df9	1	0	\\x000000010000000000800003d7536084a724aecdcd4b8fa911f72d3cef68d0cd7d0b68fd45ae07bca6d35c1a6b2d834cd56eb31c3a6b18ffc527b54547a0d0ee631753a02a046fd8f101a688dd5d94ddcc69a4cb923e01199bcd7ead5fec2cb739734236c1d55cdc2971c42a44de5f14664d973e25570f70784b044aaaa8ea3f19c5d717dd3b3a3d1c83352b010001	\\x9971716f2fc76480e696f0202104b9b72df2c5ac46120dfe211f4db802ad739ab285fb50f521ae8e67de291d6092bf4d6809dc0ed8c0c45e47a36d49c1e82009	1673605599000000	1674210399000000	1737282399000000	1831890399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
144	\\x5bed54ce41100058c100bbd68eb66918f8406ee78db83702e7c2dae82a0fb753ba8e2e71c19bc12e60730763bdfe3d484347e3729370ec6f785a4090a37fdb72	1	0	\\x000000010000000000800003e534f2af1858d87c9b1d43f0e7bf09309eb92a1b28c1bd0fc1720ccbf8b337ad19a681f00047738f1cf55c933332b39366c8ba4ad530194dbf2cf1c88894abea0a377c6b39f6b1e9f07c6f189a67f35f9dee588bdc162a0a5b43ccdc2cb2ca7a82548c374a275c0cf60c8fb97b6ebd891ebad2b34104dc5d4599fa79a03c162f010001	\\xe40b9e7d5c3227d1d18d6f5410ebe1b677c98144383fb56b0c26a08904c8e8e8696ef0c3492f926b3cd352c95c371dfce784a44a1b657177c5a8a71e853e970d	1677232599000000	1677837399000000	1740909399000000	1835517399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
145	\\x5d21991698c3446f9914de1fbc5574206c1c19e734c99da5e0a6827cdf71c892ecc7ab4ccaece41cec12288f47f83b911974230045b40574a145cc987c325357	1	0	\\x000000010000000000800003e06748a5fe2902d6bc74ef0f78a60e1b2c6152b8bffe58eb15eea6ade7d70f57628614aca9a5be839e9795fa64075ae3f03e296f10cd86ca43379b404982fd8fa195354fbc399d6fa93da0bcb3c864f8305f5cf16961553d09f61cc7f029d6064a2aebab4d2e2d4fc5b8eed52406cc200b1228ca387325573fa672d705355d4b010001	\\x3097d0b6a2e12e69f14918c8fb97e424329d2430a6149afdbeef27ef6ed5d48fd042a8e7dfee6f5fdaab0d04db55a0cd02dd7f003a7d710d0430b3e145f0520b	1653657099000000	1654261899000000	1717333899000000	1811941899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x5e657edfed7caf612002ee86cfb2c90eeeb7705efc9d4d0a8c271944bed2bd7c6a068e500e5cbeadcf3c3b833fccbeee8de9e20ed5d05b6fb75eb9b484fe8bb0	1	0	\\x000000010000000000800003b16c7f1573aaff22ae1d8872d1fb71c14025516535d7de251038882e7a97292aa3faeb97f0fbd272284bc77b8167b0b2281762910ad28b6873f2f42e0de30a3d23927fb0be6d8057f6c581e975936e4554ef31a3a879db9caad0fb92be5eee0a8177edd4e7562db559bded082794f491ac3a9c2944a27c1ffff2d1ba8c32c9eb010001	\\xfb8e9f309195a70eec219f91a15448f86f14d7d113225f4a774a51988521b9efbd1231248b8b6572a8b0a218ed79b3824a4086093d3ed4a5e5cb4cf8a7cced0f	1674814599000000	1675419399000000	1738491399000000	1833099399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
147	\\x5f49dd8825ecc46af7ddea55e8affa0906831449300fbe2a91885c1c9a417886a216879ad3b3981eb870eb08368f0fd01437fb3f4966c4a0863e5b4110cad1a2	1	0	\\x000000010000000000800003e16ee5f0f410b3160a7e4b0d4128d1498b81c50aa5c68451c7d473bc2ad8207d684fdb70bc29e0baa232d0921ecbecfe57eaddc21425112817805551f77e0c4c6055e7a52248c6a5fd650719b7ec42ad42c4b2460cb3b0358647ba7ce613bac75abb5d6b9c9d11508765fd8a26cbb2b91b99111d3710d07916ef9ad830080875010001	\\xc6a09ebe7fcb7fe3269fc6e4ce9e34e9ae6e4be1b1d9d72f847673dc69ce26310ff4d4ac4130e2b61671693f15e5474fc35f4f55e08eab60922a6208695c220b	1665142599000000	1665747399000000	1728819399000000	1823427399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x5fe93c5dcbfd7d46a74eec3e2b5fa9ef73acc86198e80f24ce06b49baa784b36a01532d0b7543bd933d2290987431959f3b59cddcd8e645cb07a1a8f06f7df99	1	0	\\x000000010000000000800003f33227c56ad4f4219ac7e15dc92144e31158aa9b8fa9117fa5f40d9adf205ebdbfe42ef25464c439512e2553e20b0344b404af3dce44b0c7748947088c38ef64fa664d0e51bbaa3f1429e9e078fa990c8f51d4d79d7cce492c713b701159bc04de1999933f2e540fd6f23463b79171d2dc6d8284d09f21419f6cf0aecfe34ebd010001	\\x8df12a7b5889e114d695f1690ac60a5b2881bc889ce790000c70dfd397c47ae017dfc91258b325d023d674e07ffee602a4c947b3caf4f2bfb7e190c2799db709	1662724599000000	1663329399000000	1726401399000000	1821009399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
149	\\x60213b4170829ee99b62e7d2534c5ed72e6e53ac7c04c3af8a4cb6d9c8b1a4259f73a8f07fcabf16d84b94097d410af1f6b18c6a2768b93cda9220e550f0f38c	1	0	\\x000000010000000000800003f609f242136bd586bd75c8696c77567faa9bf86bb821a484a18386f1ded4be6bbf39ad749d82c324b6b4dab4e9f511c24fe1a17787477bef9a1c716842310bc3a04555c66f0e5fb2297dc039c138663cbea148af7626eced12f8d98423b9cdc1e7cf4711b83d52669236c837fae631eb4d1cc69eab2c4fe0553da0a6cf5da7ff010001	\\xf305c747e3ab694d4a3468e3179171e5e424d8dab0a44b11629264a55891b3f09b16bfa601cfc3178cf66b40b69a33bfa319638c38a2f63be4c9e97cbfd8110f	1673001099000000	1673605899000000	1736677899000000	1831285899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x6179462fc20ed04e5619797a793b1a9a312dd842f73ac13ef4e4e060776986a385b173887b7202869e2d1e9b60249d59244cddc543a82aaf4bb1f416d9b1e44e	1	0	\\x000000010000000000800003b8f20138c84906d7e3a269db2c65e695538bfffc3db03cd699d3031e8cce77d782f527649cd59f39584c1c5957e1f08a64e449b3b75871627aa01057c4273e24be33af4bc484dda495039c3e3fd2670416babe96318cc312994b723cc59fb893ff52becbcf910fc85f43d4488878093abed07c024b6dc8d733bd2c9b875177b9010001	\\x289a3f56c0a7f34e17e5e57f3eca5e4fbf04a9c613c04a5ad41a539a7ef184095aac717cf7c039c21e98d0f060c13aefd400c1f58dcfe7407160997a1654c201	1667560599000000	1668165399000000	1731237399000000	1825845399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x6285274e7b77583aa0fb3c549cad80e8ae3401d2d9700caddaf0a42c58650edc951fc8906444f0908804c8bfd0b8cd623f4251927f752629805ffb3ae7902617	1	0	\\x000000010000000000800003d7fc06aa0b5021d8debd6ce771598d12596ab0d79e681c8776503b87ab2e51b27971e12f4e7146aa8a80c96dbb7fd0e1a3e277364e0463ad85b746cf2b8e6521efb637aeb08e3e1ffb60a39f3f31469af9e07ee9d95446383a7ddcf828924a5cbbeb058acc76c7b07d7de1a3be667f26157404332f4342e288c7f61fd99429d7010001	\\x627edbc25252d5effe660cb12241619d2d7945c5177301d2613494fa9006d4230ce59094f23b93f77501098fd59d81189d23d6411c717f6ad76ebd795afae40a	1651239099000000	1651843899000000	1714915899000000	1809523899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
152	\\x63adae475ac4376806a3fd19aa0b7394c9e836af95a6317f1be0c9e1bedf656ecddf9b11a7826e28a0af119fc079688f52e4b3fe5f55ea343227e04707687666	1	0	\\x000000010000000000800003a31f527c70927a1999cd6edb1e4cb0f784bdd2fc9767dd2052f793dbe19e83e35f55c813ee67b06ea0751a392b00b68fc3fc68d1906b753e34e6e3f804e7d6bd461d1ddb92902d077ae3a0b52f86c5fbe3e0f5a6664de0304dad895bddc7391d4581a833b00ba971181a6b7cbf52185bdef03edcb647662881930c6ba24e5227010001	\\xf500ccb7ac84deeb24f24c22ed4ded41c5aed3f809c43696498b6ed02879f64041c8718a99eabfce16194856ea83d03fe51e68f8dd0d7b12e5d5f967fb5bfb0c	1677837099000000	1678441899000000	1741513899000000	1836121899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
153	\\x64096b656b31818c958b876b0fbcd4e883bfdd1e1672428711ee9217c8bd7fb78191171e33bcdcae8910a30d19687f0e24d631c300968b84a10de4207bb1b4c3	1	0	\\x000000010000000000800003ba5214a367c91b35401783a1cf7c1f89770ecdcc22751c88eed68dad4a868d5b7f6cb0129b61b3459e956787386798e6621f80bd0aa2faa1deb1fc2a429f090b263087ced2abd43f3706f8db4499676fd26b52529e4f7cdb67a275b0d35aa3bf6005125852bf890b19c360934a83f45a408db58a9a0ce65189bfa0d86ce9d713010001	\\x72ddd92533f421536751f4a56c0c7c67176a14dc9d619d61432d96b44ee9c7af87fe3cf4b1b55955644cefca85c6afb45c1b60f9e20499cd982a67f5c5300d05	1663329099000000	1663933899000000	1727005899000000	1821613899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x6615010cd8a547366c7fd9e8687963018252b25d935f9569d0180689d1082abde6ac5dc030c873747c75a04af82b84db79dddac17ade48506d60726375172a4c	1	0	\\x000000010000000000800003a493addbd30a82752eeca8661f9048cc2f386d3e55ff5463874026fe1c30baa2a75b5be151880c3b031f9412bfb73ce6268d26ef38d912fde808f4105162bce15943be95b71e4571ced138e12a218642393804f386d7f4b2fbaf6196b177544a6ee9d1c45f7b099612df5a66046a41ca694e40125d91e6042c2b6b3e47b4ddff010001	\\x2f525d22032b73f1b7abaec3d69f986906ed45d375a19893f4c75ca4bbf687ed98471802613038841333f85614eb5f23bc776d0d21759b9d4e394419275efc02	1650030099000000	1650634899000000	1713706899000000	1808314899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x66e13cc829369616153c9298f4f45d9bbc9ce58c1d002b3a47dcf1866a76e83d6c698bcee9a175e025af10f16b7b1d6165f873f0438e99549ed58ec625f156d7	1	0	\\x000000010000000000800003cd34bf561a2c60e8c47f77eaac2daf9d4244ae87beeb6f956e923e948b028d6aea383d0e58d5cd7f2863b76cbe7ccbd2bd3930f83268806243aff937076b49b4c73de6765d55a3a96f7d76759f8e32867e89a097c820a657a05d7f984b78504f7b5255bafc14e3b70888e5e500dedac108f865b601974fc39ff9ae840d613eb9010001	\\x8753825734c869a2615cc30fb95009974df98e1f6f05588eb87f3e29b6600264a7b6d77be6eac334f697e16162f8f04c19eba6dda9edaabb525da7d2006e160f	1648821099000000	1649425899000000	1712497899000000	1807105899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x69cd4f8b0b5fe8a8436468fc0bcda97e03fb86dc508503daf95b39027c84b4ac10d4cda1704cb2400c76cdb9ac7772225043f27bbf946b1f16ba826ef7b1a7f9	1	0	\\x000000010000000000800003c1cc494fff8058287db3e62bb9045fcf587930ecf6b0662f979318375c07b525925cefa314d0295d3020fed881174808755c5b103ba0797576c28cca3cb6155ba678d06b504e6a42dd7fb40ee50573fee6692c76a77bdb099970a0a4134a98e2f47ae88f409df04a89b277155a4c16941f9f855f3b0cbba0492880e0dd77fd33010001	\\xc951864b62496b84d7b9aca494b17715de431544eb4f4ea533f47250b3984b43a06d429111634c9229b88644bea30ef66730ab55920efb75ddbc0ede7d4bfe05	1676023599000000	1676628399000000	1739700399000000	1834308399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x69edb054247100e81621d74432355868bd32b3c952eab80e2bd1bd45b992b798655c9adcc8af47940f1bb24b10ba402a53b8ab296df5bbad7f63e9b56cd0a727	1	0	\\x000000010000000000800003a50905241e1bb4005f0f0b3ef83804f952c75cfc931cf087ab893dae7136477094cfee0af5ab762d7ee7ffd416d87d9f4f2fede24dfeffe4c0c5c5653622e12963179a65052e6bf1584d16c5708cde650072ebb9e5aadf66b930eb4ffb78fdfd63dc1603659b0d3eb383031fb3ea6917f03887bbb05ac27f26840fd44d541efb010001	\\x2058f9dc63dd764b35421a9bec03047fabadda0c10619ff57e96b26fbed753ba082df78c53114804a141404cb0a0453b94ac5062d50e93af15535a558f90660d	1673001099000000	1673605899000000	1736677899000000	1831285899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
158	\\x6d4198b36c7ab25a9c719f93cc211f97f688685296e306a44731e41802798543780ad1b7f4d7e19dc8a4dcdea7e7a6fa3ecf97f89a799fcafefce5b503791da7	1	0	\\x000000010000000000800003ab2dfae64fcdc1474dbdc11212bd97334647f814e7e830fc48fb21c1eacc56d746e15405a2c796153d7f2b030661f76215eca436f776bc0736a6015c05ba62714862c04933de72e9aff0d487981fe03af4a5f976f6f14e45887f46ad319a13bb9facd3a07b6fcfd19f392a31d39183cf7ae48d9c8bbbfafa16128b20fb9071c9010001	\\x978a0e8fabfe47d94828b5e85ec74b2caa1d8ab892c8866cabf81379ee332d93d4803a2702d4180a5dce7113c47b995da2a1482c4eba26a3c816c4f9979a7709	1669978599000000	1670583399000000	1733655399000000	1828263399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
159	\\x6e9970beb7fab2b73b2b9cb9eb08e2881f10425f5da6dc7e901b961700681ea695fe84e521d94f9cb99809d324f9f89d803964c7d43a4387320c7b721625c600	1	0	\\x000000010000000000800003ad15a226034c99374d20163e29cdd8e6d6d83ebb860c2254be64b5c582e1108d863dc0c4695169e63d398519a117f34416833a7df4b177b8f6e216e4bc36dcb01ebe56bcd68ed29a62d6465545ba0fd7e925655f58eae40ae5586b074a096cf2154a2eb6eddf25529e865609b9985247ac6316e05694417d02a27f3da4acede5010001	\\x9fccd9d45ee6fe7d11bd1bf71a0dbd6e1ab6f68bcd7bae1aa6a95c5b5d7aa307ce94c950e0bcc3d0a86f516c5b87b0a66b0a63ca2313be8f7fd6fb9964d3e70a	1676023599000000	1676628399000000	1739700399000000	1834308399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x73591f1edd160f76bf1886cce6a52b72dee47ee8f6490002a3d11e485aa759fb089b51811ca88fe29335966debf0ecfc670731079887cddaf0457b03bf4e94ba	1	0	\\x000000010000000000800003dea5ed856c01d9d3161890137f2a47f179f01e3ee7c875eaac837b3df93d43e15f9a714a5f7f287dd4fdfd6ef03c21239838d426010fb8a646f6cffb093750117c7cba35502a49626b0b31b8154274f2cc59fd0ba3f0b455b9bc593acfec5ed8876570a1a726f8bccb1b0bdd5d1518851cc93381eda43fc782dfe9a3e4679e0d010001	\\xfa9226d7171fdc2963223da4f1e68bcc6fde648d3302d6ada5b3398aff75ed7cbf5b3c16bf79eabb54df73cf9c4ec9ce3ac2c14907abd6f6e38376dfe75e4609	1660306599000000	1660911399000000	1723983399000000	1818591399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
161	\\x747d37c1c03479203c40c47435ba3b6b7e1734b93b2307bcf573d0da88e42545370117dbfd99d0c76a7fd09ffa5582217d829e8c2e7b0d829db9ddb555cf3776	1	0	\\x000000010000000000800003cf4cb73b37b797a65690a7b86a2645b61acd8aa69bdf37f576a190884b39e18486522a896fc97cc9d629cc29e414529eb77d7852687dc714829969e09a7deaca775284ba2050d767d0da1cbd7e2920a999c12d722660f785833bd926e866d18963f89c695468fd3babc126b1bb208f7df143c75c449384f001fcc4ffb04b6c91010001	\\x30313c1862fa59baa74b50be53e0a81ec9da6f4f30f835ec6b026a015c62848528074498af00ad2fdadf1ed1e5df1127488a59b8885d3b883cbc762b90fd9c02	1660911099000000	1661515899000000	1724587899000000	1819195899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
162	\\x75954b6e276638e5e6aae2518a7df8302883011475853104b0d5de05f751374d5e17b2e4791b59f956b622bebda2dcf3da5a9be21c3cabee4a69099160fb02a9	1	0	\\x000000010000000000800003ab18d6c91098a5f8e4960909b8535bb79fbafcdff749f27e4090ecef5f752e7347a463c6f07f36e1aef9c6369e0dd03ec0f359d70ddb336837626d3db9ccff52f606d10a1cf45608f74e01bf59ce3398df0b8844b1674d73eaa92bd0320dc9629c7553f9fbeb29f8ddedc6f2eb4521f17e39b36999e4bb20ca89c66f923d9daf010001	\\xa3dea11cacff66d2c60f718415c37a22dbe65445e6fdd4696106fcf89b97093bce2f14519c2eabdf65e34804b6e4bb8db15a0f732576aea947c7bb333bfeec0f	1672396599000000	1673001399000000	1736073399000000	1830681399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
163	\\x782de264451e0c8ae44cf96ea0a1e3595e86c654aee506fec36837b59845b2c647f70367f9a2a6c113ca30d16173d894cc03e5376a93ac7da60b9ac03c848bbf	1	0	\\x000000010000000000800003ca4689a37d13e40bd49b52dc5c944e7edf3c845faba36ce7e50f60ea7ecbe9ff3d5c120bfa83f3e2ae4a01d650e6d4daef2c72d9cdf18a37fb98cebdc24955b445a4dfb7f88cc22adb3387d6232ebeecda5dfe22d165cb920c9a358da957e11f20ccac29c6fb7b93c0299a636790411b32fde5004948ca7a74e5ad3d4b0e763f010001	\\x42234ab69ec9250cabc1e8b77c6797a210ace1e49aa457766fb7a2a1130573b88c105d9a68fcce13b993c745d9b5dc89d9387023292d269fa927b4b152cd7801	1679046099000000	1679650899000000	1742722899000000	1837330899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
164	\\x784dc2d112edc25da0cf0472a7fa9a1302d4fe27219ed341f989cb52461cd4adf9e2002c3b83ef3a086dfd364b6ccf06c943d0d8d44a4681b263d0524210dfc7	1	0	\\x000000010000000000800003d90f99510b5c05e0ea0d7f1d4f843c05c946a9c3efe3a65bec0f10e002fd0db6b2b5208158ee27356fee7a20caaded10acd46aebf034a2f78f72c137a7328a739b0ceee0c18227f0e0bc549576496ba221a4a90e583de530bae62920006f695dee109b88db6ead5289598e51021b33026df3daa7ec7f811c5a880ef251524a23010001	\\x0f415cf87320c993eea13c874d1a06267dd8845e59bbdab30761c82aec3e9874a2fac504460b881dbbf84e3158eb8f7945bc2c798b08c67cbff55d39420fe205	1652448099000000	1653052899000000	1716124899000000	1810732899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x7a01d1449c9c94d78c1748c145119fe8a17598b58d1f51623c8ca6c29d821c8a8140ecdf28f3fcd65cddb004098a8315e181e3c3a9fe403c6695a5d0364bac7a	1	0	\\x000000010000000000800003b16f258cab2c5b141b4d5d97f654227b65febb0c77a435a7d75674e24df0247ca6cad08e1f18bfc3177c84cc5a37345c27c0b1f953c4fbee7082e902faf355dbe635e459a25e13d7086b02113d55746d72e77cb77c3689026d36c3195cacbd5ca33d7d558303f81d36cd05c6f75d845512c7668d7bf73e4d324a2dfa8768b80d010001	\\xba0abf96780f879fd4d0828054cafb6b13718b32638fd0c45eae743cad98a1acd9cd4286d976e34cf4675454e2636296715e13349f587f23696522edd300b203	1662120099000000	1662724899000000	1725796899000000	1820404899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x7b25807a8588974987d1065189ba76e8333c282708875ff5ca33890ab19a6d9b7c6a4aed70538731f4900a220cecf3ffe3045c048399b4758d3b2d9367a1b0b3	1	0	\\x000000010000000000800003e2f3055ecd9a6bacd612a29b82b5e6fa42f033fcaf6b42f2981d1bbe9ce5d288d83515a5fbc69e286966d8306b129625b896924b99baaa13c6d3bcce2d6386b72a2291a9c164a572fdaf7075a1ad22e5e70fc6d95886bd80cc2216d022af47027a7e8a3a803c5892727df03a2e9a9f8ddbfc558e9ef11c43f5ef7a17898abf8d010001	\\x3f5f7ff11a06752ed3331e7bbdf034316903257445d0dc87b0bb0f3c049d7abe2b7f97c83dc66cf0bb9fb46630cb1af962f761eeb13986f8d541e44fb787bf06	1661515599000000	1662120399000000	1725192399000000	1819800399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x7db568deaef247299a2ba73a0af50c883f5ab657635ab0227f953c0de3963041e6636d5eafbb1154ef9cd85c108339440ecc969bdf3fd2e36540bc8900e99655	1	0	\\x000000010000000000800003c84d67645a908b968f7c0aad8848ee062238ba6de6596efdfcd01ab58e9e6232750c8f109c15fb691d3d327c31fed7d1ed2afd1261fb66ef0f0983ca953f3775a817f2e6a3dd09a9e639e5048472c5cdffb66dcd35ea475e5c70558a06e50bfe401bf3a00bb9ccb0718a5297c5c2d4f5e09cb70ad607983a246dce0646524433010001	\\xfe96f8c6acaa9397a8134672543f203dce56ea704620b3b89d93b56555b7d5a8e0e39c7267e93a3ee56e792cca5ba82d64193e36784a7f01408011aa4fdbb306	1656679599000000	1657284399000000	1720356399000000	1814964399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
168	\\x7eb56e8cb8345732c6afe3ad1c9e2ed25dea48dab45c44941db635af564507e39eb8fcda10649eb4f2b97505fe2a3316f655a8bc142a94e787d3d2c35690975b	1	0	\\x000000010000000000800003dc5aed70dd064be145a3297c8b2d3f7ffd40333e5080260847d83d84141efcb88934ad072d7d68a8d67680a99edc9bbf9ab8431d24f81cda5a6883b5f59c92754c948209b0c16004ba056a0e0ed7bbcd5b54f61d91881e4a5873246495bfbf9710b2e0a3da0bee2d2fa2037f2c773323a60d40ce737b9f8093ce1dcb2194945d010001	\\xa36a4fdb6aedd43fad16b7d1d3ad3351010d29eb1ed8fbd311c740a65bd7df5f9a9d6a2c3f29ea33c1d0544d661f47ab09ae0d5c15aa1a18422d87960c38100f	1671187599000000	1671792399000000	1734864399000000	1829472399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
169	\\x7fb9d508e9d599b28a2549f68d96aefed894669dd451733ee6b933103083c5bf8e562ac4c3f5abcd27a6e8126b3a5b3567a89a677991d5548f48a5ac44feab63	1	0	\\x000000010000000000800003bd81ce6ef9bb5c27361260f20d768d2d0f9ce58e5e3a61a0737fa0271c04a462aaad4afe1cde5b1f5e5d216b3404a4b07ee5128e686f7d883fad7d19c1d033c73af294a287903d5d8d3dbdd148fbd744cb935f4c5eb752e55ffb07024fec789af3f6acac9db7063b0183a90557df675857414d4bac77e8cf828e257259ac70f7010001	\\xdaa4a4cd3891e95267e6e33cb53ad3ce107adda2fd1f3739a85081ad1beacd14b98d2508a990ad4028ac4bfca1932a93cd980346abd3253e035cc4c9516cda08	1657284099000000	1657888899000000	1720960899000000	1815568899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\x7fe5f79a5e2c8d92b2ceb0dc19867e804349371fd7f917a5b6e59bcebe2e3e09f01a00c6f9e9fdb76f6b2488425e170c277ec4abb96b441943e1e7ae90596ea9	1	0	\\x000000010000000000800003be4838363ea565825434922583799b233ad30c924dd9cdc1f97c04f3db5a06036631d8499b448736b20627d3f507005cd476d316694e687ea305bb581f560c87618e6e89e9f0b09344782b90dc56e5b7b55fbdbaa1d60901e1557059dd22ef4ab6a868cda78455c9ded8b998cac47031913846dbeb6c679f7f98c6e1d83ebcc3010001	\\x84b45fc0a4f2c9ed4978fc48d3163c37c683ee9b55f31a333ae2ef310692bfe9282f702b52c743599e2e87735fe97a215fe5c1d36297c3612c713458051d480b	1659702099000000	1660306899000000	1723378899000000	1817986899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
171	\\x7f5d501e8cad65295535ab8a594ece5a895caa7ef756e8d8c58bb1e125b5c627be7a79d1f04a0dc35caeecdfcbc93eb937401e5e4c004f10ffd28d795f4baa87	1	0	\\x000000010000000000800003cc3cef2fe56bbd90e76504ed3506d8fd5785d4a44d31215e301beafbda8a133dd2401c91e089f1cd7dbfa8aae0598985e4558daa725557fd6119a5ff81e705ee7f8e86ccc6f294a6e8ae9feac5e1890595b30e28243e3c8dea2214695d395d0d96d103a1a111e6fef410ae5f75cf525f821089210bc5c2c6ac62ac5652c35f95010001	\\x3f9cd8903537d8683588885dc21912aeebb2e99d02ffc662908f7f4a537993bd9715b3ba70381154ff3f9cfda34ef9670f652f8466f75250c77a5c671252300b	1649425599000000	1650030399000000	1713102399000000	1807710399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x80a157b6aa82d156987599b19741cc6d5dff6fa482487a1c678d2c99c5b3d1f841fa75bcb12eefd0f104988b8e05e2d046682561aaf525a9d739cf83806ecaa3	1	0	\\x000000010000000000800003bb2ad3fb35ed58943ae5275ee1309f36d3d28087e3267400ba5a5226eafc2b88a6147dd412bd817db6907e60a7dd20427ed366b93d6af622435acae0c0257102ea38b0a4367a1016257c6607cb25702dfcbe2f12670a25f77704976d148f499c37c90af2da3a42a267aeee9161d5b435795d819849e464a16decf3fddb48e94f010001	\\x37384852a86ad71285034529dad28afd55c5a34822cb57f77bda9b77a24aedede6644eeffb726e09335e676d2cb8a6c680206e47060cb820e7f30a66d6a2b304	1663329099000000	1663933899000000	1727005899000000	1821613899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
173	\\x80e9b414fefb95281115e1d14dc4d5a98473c4cb012c96a6dd39c9b1402029eafb905d45308edbbc6e381dfbe5c71f0c7ddbe2f2ee610a9cb17b6026e0a0a164	1	0	\\x000000010000000000800003c81206aca53e2f2275fb0a59be1131cfd3b9e6880954c8d2977a961bd435b67c41ccdb8def02a8f3bda7b1b6223630de31c58cad3d32ce13894d4f715b462b0e43d0e52ea2053bda5f244792f611c88c1e8c95eea8ac5389e874bc5d818940e6bbf14db53caf02c9361550325a3835c9cafd0607b3599f99ac950ff37127eb61010001	\\xb62675324d5c44525d912848733ff854fd8e516dfb9e4d0c22f061831683b2bde91a02a2570421738de52de55d69b3fe84cc8ebcf80ea47297b8319b99543703	1669374099000000	1669978899000000	1733050899000000	1827658899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\x82ed853076c1bc000a75bd93d30a2f32e1b843516948cc9b4984da73a7ad02da533d8e8809cae585dbc9febafdcd678f67a67b3226e637438e5c90bfcbd07743	1	0	\\x000000010000000000800003a086abf0479021b36b91b679a24dd56450921490e7079da98bfdb8048a165131f2f4279ce10c1a37c88b5fccbd6367ba9f2c4abb416208c4407885f5e665aa4f3cd60e9c79e7404c99057f795a775bd6222a62c666159d16059dacc58120bbc4aefe97f713464b6c92aae0e213957bce6ed97247f405e3b0e3e2f721a1aa6edf010001	\\xe4bbbc0d1b7d7bf3c8cbfeb9b9fc66ba2e0e35a244c1c1fed5c363d51982381183ce9caaee3ce842f88d99b9670426c3039c2b48604555dc67231b766c950b02	1669978599000000	1670583399000000	1733655399000000	1828263399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
175	\\x8341b2cff8ba74b0b61b339ee633f5855ce25ebe3e9f9cd4457b6faa6bfe869bafaefbdeff4ce61ee203bed7b6f4095e03cde0f34036518ef86065ffdd8f3f35	1	0	\\x000000010000000000800003b1039aee65da121d5479f569129decf6761ab881d3991c3f70f769f935c56f8987767e53900b2f267ac88bbc6f367aa9a66692a8a7c70f5646abdba00ca73bbdddac4dfe792f7e1d7c6fe23b42c06e356241577107425378ad4685983dc0e64bd9ac0582bcd37edc5d50bbb54004e227ada2be6ee63f9bd6d32e62f59f513131010001	\\xeb1b45ef72add08c3a04397c66b4e9ed24e6e9b03d30295a2d2b95d754e916d13103259f88232ff0e63060e7609145de7952e35fbf862d6eeea697551f263d0b	1660306599000000	1660911399000000	1723983399000000	1818591399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
176	\\x86195560f3778aaab3be265c4717a695624dccc1641bc30d944cc83c3b7bb30155d9ad9560d34a84c8d364e099667b57ec5a18e34ca678399ba9836c27995379	1	0	\\x000000010000000000800003b9d2a5c9d0a220584a2ba66206c862ead9b89e6e1572571fd87fcc17e3d1cf5ea749b05a424f727de46e422bd20771c1de26af685837dd17c41236a73992923cc7ccf487a21b4157729ef24641535b749d742a5a56ebd1cc9626e86a0ea7047bf66acc3862c118753ebc085d5304385f5c9e40f37e37ce2df645a074ef0ea9cb010001	\\x832050239f110c75d89cc7e57c19509b8509b0ffa78a7a37626e810d7ae9cc5957c010a2b3e78995db828e4c6fd13ef76f15e22cf8fc2b4b02fd85e160a95b02	1651843599000000	1652448399000000	1715520399000000	1810128399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\x87e9c6ff3c5a31a36af063be7e20c3175da2995dacc3dd13294f8ca4e1520a9e391b2ce47ada260f9bc6c4cc7f81f11119b8454bdaf3b24e047948671cff603d	1	0	\\x000000010000000000800003e7f1a2c3ce6e52b1a8b41ad9d662415727009c9a58b8d2a54fed3ad35da2c89a21d63c7e07a5d58796661b952229254543dc938fbcccfdbed8e8cc0b91a1fc9398ffc4b64ec2731faf4321973ebd8f85b7a1d2bdfa197bee238ec6913a859eec07cb3e80990477339ff89d1fa8f2e6faa43b97a51f764b1129e0bdc34cc751b5010001	\\x7c83d41836fcb77c9de9e9447c869b92353371bc8aad686329d1038a5a17497499e40b4f4bb26060ce6d56aa8b78c7dea36d8ed35f49bb885829d7fea65f8302	1666351599000000	1666956399000000	1730028399000000	1824636399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
178	\\x8e3551bfff4466624be9dbef0c9eb2c3cf18fe60d7169b9ce95155951457b4b3c438f68623f3a4603f2585f02cd36295ce4dd82794baf7b7b16d976342fbe5bc	1	0	\\x000000010000000000800003eb5c857b4226f61d6417770fb80ed70286a8dbb616fffdac83ffcd1991f3946af84b121ce58916ff59527edd462e90647fb5fb1ab5c3a9d9bbe99eb313b8c781194ffa47e67d2bfbf8a076b0348acb2e8175bfd4985cf6449ac219f97ee11c658dba7cc725db8206dee124a46bb36c977ffd02c34906361d84687ad32420ec05010001	\\xd8a2e111f86c93ef12b40ed44458ea0b71ab798dc39e6aa887c9559fd8c8b4497f7246c11dc4eecff3ac366aab88457f49ba0659151284ba5469d3b6d7e5fd00	1651239099000000	1651843899000000	1714915899000000	1809523899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
179	\\x926dfdfade047c1fd36319217c63886643c9a3dc6f2e93fd8a88027e5c7e97e6711eba0c6320ca5c0b7c501bd3b7d1bd19765c07c2c49e7a0b19c98e7c2a5770	1	0	\\x000000010000000000800003ad1cfce5d399882f85bf1ef0ba189a41eea1a5b7ef83ec3b1fc31463a09cecd6fc087540448d7c15912dd7a238b7c0d6a7c75b8b8aae2208c0342f5bf0e12b4dda1b168f0e069c3bd24b61669722ed000f839f7f42ae2e8e04b41733d50c069452994ccd43a98d097ea242010c21ae8fe3d056b09fda444472f8ab33599c9c2f010001	\\x9b1bd8dc4c4fc2f0a08f6c8517b1b77e4968ffe214ad72efd42ae8d647c31177567c7bc5a1698154a64ac63bf2981329420f5c0bb0b66e0e33351150e3c72c03	1657888599000000	1658493399000000	1721565399000000	1816173399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
180	\\x92550a6366588b03e73702e6db1f701075e3f0d5e2f8d698cb8b52cdf10c4526cebd437f6c782f79a89ab34886ccbb92c95215510a95b35c16321a01f954a1dd	1	0	\\x000000010000000000800003de5493e2cc913e45921330747a297619f03fcf08954dc7f02b07d5a117db7bb126873af1535b31c93942f7ae66df725c84434761c685820843abddfb4b1fb2aeb9143349ab3323886819081d5f0fc593ee7e639341869136f0b9779d687fd87a90527253eb9b4121ed08065f414d19cedce923502c474b48e9f7a853c7326f57010001	\\x8c9cfecba72ff7582b37ddf660598ca13ecd9ab6a725881aa8f130af6a88b9cb233f4b4b2f179633fa0de0154a1fbaac47baab006f58c93e01529c269a13a802	1659097599000000	1659702399000000	1722774399000000	1817382399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
181	\\x92154d764d69e51fdde1afc5e7ee08ec760f1d5dd9c3a0a2501ea7c7aaad17556d2ffe354adca42c642e9da8292cfcf435f39d113d15de9c79d258760aa7332b	1	0	\\x000000010000000000800003c2a41f38cb6e270e845201d8ae53e140ac7acac510dd19c66b2d3ccd1438d3979644b83f1032f1ccc1ae5a478f3ac335ac50b824e365e4565760ab01079e77f8249e3eae1c49828310d45602260ef13e76ceb707565fbc68023c95e5ca7ff4dfa0f704a2c0042f27a9e8468a4d409110bccddb5525f01fc159f6685d50795173010001	\\xd8bcf4440569da931b4001f0184748c7579e893b95a8dd7a66a91ee26077c226430466571a01c8445fa63d5cbed07fb3d957bb991ee0e24469926954098d3308	1656679599000000	1657284399000000	1720356399000000	1814964399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
182	\\x923183855c62c2029a6739cc8295f76263374842e5f02d63248ecb36293fabf7719affffe7b6d334092ac2096776c4a0d7a438f15d9eab89dc82aa307b2ee0b7	1	0	\\x000000010000000000800003b31646ae056eabd2df8d6fb42c927c12150a1d56cc0af174236de1941866104e61affdc15ae2301b72b369cfacedc32b4715386a645ecfdbca2411ce5cfcab70ef0b125694ef77dd970fc0a2a8c111127d830d9f2004dabe698259ec8b7cd24c15d32b060638d89f25b007ea6cbdb33e88dd505c0c3b719be0df6e9478fc4b53010001	\\x61cdc4d8bc23eec74b423ba080b8ca565d9160d9d9b79c48b0acf5339171cf04cb16b6e84cd0133d17d49cfa904c3d92c6911a90e0e9248346eb2a481dd17e09	1677232599000000	1677837399000000	1740909399000000	1835517399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\x93416d57570fbbc253dbd68cbcc72f0cacaf1bfe316b179fc09a9895ae70083e3467eb6875d44c18081ced8248ca2398d303a3b235299426a8d8efb9dffa894d	1	0	\\x000000010000000000800003cfb4826145dd6085f6ea1a2eaef75dd7ae6271a3e8c20fe6ec5e6a2a8fae9ea7eca11f577ac3c23bb80fe52937e68185ceb4cd4f97e0e9125bb4167e7d21c86d7f1e6a7b56ad598853f004ad8ca3e7c9590e234def4be9ed758152909428848a9da56f583640d1cc16a61d2bb85db5c7a5e13c847a85ceccd250519f5d262275010001	\\xfb83852361d73d0a5a25608238a52ae5a20865720f0e51edf44fdb6e7a02908f5f940259af21009dad720f3b763f1750a244bd386d974659d0b8f67eb299df0e	1663329099000000	1663933899000000	1727005899000000	1821613899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\x99912db77ec884ed9444152ea2b190ef07e21c4a8d66d8de2897e380c426297b76871676d88df807e2c4e61ea2714f1c0c1f47d6c263a0e6f833c162446099d0	1	0	\\x000000010000000000800003dcabf3f02135b96bfc4aaee298ec93404578045865e71a7d8acbf31713ed85dcf65012d9bfc168d73b92f6f3d5f19c5632713614d4b745fc4fb40e0feb48d016d80a37f45a22345b144050e121ce140e5ee6c10e8692809547c894732b9719e43bd4614da8523c0dda36b194bf74e0b60b31b1a4fccbec5b4ea4ded69fd2aac1010001	\\x1dfa8f6521130eb68ae68bbe989902c118b9cf9029ff3be6eebd72f4efceb66c9a31f413d39ca12ace3436a181e343603cb1025c656f3199c74a5636729bdc04	1675419099000000	1676023899000000	1739095899000000	1833703899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
185	\\x99f1d43528bbaef5f953242415ebaa0479fca97b13484ae4bc402af3e0ed8fba3a93d35d500003b2a1948211cab6a45bd30e697ab05dcad5407bfbb09bfb5987	1	0	\\x000000010000000000800003d336c736666d5638d1b999843704750f2eec409b974fdb962429f0844cbc8863987defb1fd3bda3bc6447adbe451e7575c3ba799707a3c16df51a2d82865130dc827e2339c2af6b60200ef130545e0fdbc6742bca77a1b8b6d9cb2dc41242c9ef81357ad5d21ee9518f4f2b3ce5f73cc937d7d9d8748335e0aa742a292e2578d010001	\\x443f1e17a64d80ffcb63f03d57815baf4d2b410c5e9619b9093013977a27f3b2912d3eea308100f3b2d98a625aabb1961fb388aa8f1c7b63a29b6d453c674301	1648821099000000	1649425899000000	1712497899000000	1807105899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
186	\\x9b6912b0566c95215c366395aafeabd365689b32c397993f4a51623be9d7ba7dacebaef3c758b33717c9c5e373e489faa3ff7a66aa5ac6372742a53ab016732a	1	0	\\x000000010000000000800003b1ba4f2dca9ea1ebb182ca8f91b3e6ec350f3d41d2a8826ed45753a2d1f51cd2c652a42750c70b6f49b2c4b628698d624dc59de50fb19c5d7f9a72e9b0b3ac620b73acea441f409ad42d41625133ebb7d51f8939eb260df22f9b0a16fb94809f3d510ab19050a91f480699e64e33634befa01ccd14e331af99447543050eff8b010001	\\x5f6134764d41a2bbf1768713d1d06d8a33914d77f2a3b88a9c9424e8f5b46fa922a15d3b255a5c1990a23f58215a391810d1545802d82311135ead5f96f8fd0a	1665747099000000	1666351899000000	1729423899000000	1824031899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
187	\\x9b49fa3614b3067f4a108f1a1680226e09172f064067e6ce0ccd55779eba2aab859ec43a02fccb46fd18a83b2a96d3821be640ab8100e60ec6842c2224fde5f8	1	0	\\x000000010000000000800003a89d3f1668547f00ed25268c6d8b7cc1d77718b67930d6c24eec791f8f8113c78f4315183be53e533608dbc683ac8ebeb2b200147b310b7875e079c8656de6bf755ec15ec369771bffc7ecb615edf9b8ed7cfef5f284b0429a062abdc12672f622500ca4f4f7b0aa05afd38f508bcb98913c3d078cac3f11ac27ce527fc4f727010001	\\x29fb854ca41d553e3cf55cac5b8ba7fba0e35a9457dada4fa4e3ace44bd92cf8c750fdb8e744ef7cc4975b435f52d80bff3bbd3e908470d3eeed5ae5e1967007	1651843599000000	1652448399000000	1715520399000000	1810128399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
188	\\xa161f395ab17205108f8fd065bad352aa166cc0d8f897b4f1382a7e7dc4d449a0ebc2a348500fb1ac60e8c2a2fc28ee4126e9693055dd23bf80deadaaa4672b2	1	0	\\x000000010000000000800003a9acef5c182327744b910982b252853c66b14af07f907d9130bbf604dd32ddc8918784cc59de4138402130c532b67b4af2535a091496aae01b393b3b96b4385c9395c0db99de99bde4d79dabb025e1367d6827f7e28b7d396efe10de4637029f8481b4267f60fecb7bec7f510aa86fce9346403f3e02026f790220be1fd1af8f010001	\\x8e9cfe6b961fca6b84e39974c76478738b46cb6937834e4f26ed7ed23ca61fa6c1770fec6a4992ab2a85f75bf4d4016721453e0af1d9696ba61eed28f4eb0d05	1671792099000000	1672396899000000	1735468899000000	1830076899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xa33dcc93c611800f03f4cce58a8e6a73812a9ad688c41bfaf099f558d35e89779fced35ac577e4b98b6861ab9476a33243e05b02f0a52ad10ed85f0069b38f02	1	0	\\x000000010000000000800003d363c86cd125035cf02fe0822bee9c898dcc53a77ca5321a6eee422d1e35f127a65b3de73f9c366575ddbf158040cb4c983b310d888aabe5bb264af9f1467b79d03568aedeaa2bc7d3a0d5a1630a14bc0a05336c4859e3767202e088c9f31eb51c1b6101e3679c8f8866d12d8b1028d4dfa0d93e0ba91d91a67872954eac50a1010001	\\x025c9b997655b8a10b696a44279433dfb203ba1a269f77493a4e731d0efec8ca4f45ad4c5d78bae03513fe48c054948399272bfe1491f23aa429b4d206ea9e0f	1666351599000000	1666956399000000	1730028399000000	1824636399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xa775c8e2190e2ad871a24e4f796427f7264579240fecd73293875d56733f92fdc92bff350b3406896ac93a2ced6242a6f49088cfb700cac6365f46e9951d2729	1	0	\\x000000010000000000800003d7f024fa8cc9b7d834c7d87cb479a5113f8cabcf0a150c6a19235b54356677ee6600548797fae70aae2070c6a4ecb61b31ef2765ce7c01b7957abea8abd4ed682c5a53ce1d78a3609b1669a2a0a798f6195ff0ac9a147ba616fc89499f3e9b45c2708641d304eaf09011bc3eb2b35273249060f4a855105f57a285ec19051087010001	\\x90471d413744b38df0f678c2e5b128b161aa66f12833d6b01906aa0fd635048e495a242f7db3c4e5853485279009f116f5edcb656ee1ca8fb8271a24a420660d	1675419099000000	1676023899000000	1739095899000000	1833703899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xac85ef4e16dc638beb3dcf5d79e918fc1ac79ed281470d716b2cdbbad6a79b5c999f5339f27f2a453144e29eb334ce181e79fbcc65976f683b9a928dac5e28d2	1	0	\\x000000010000000000800003a1f5f7c045bb2f0b897ae305867e11d006d0e4fc956fed3e7099591f45aabdf1c60e958a37428fce2cf07b12d6b3fc273a74a5ac67e531e641834f16fa78fa4a69f08d7f0e6584898333c607fa76a356f81266ed1a50e841c3e910d6e40a456bd1e5a6019c5badd78faface5a71b5815aaed004e659cddc60d8c012c3ffd825d010001	\\xf656c9b8f3c59cefae03258fd4cae79a9c0b2a2de309a46b18c5e8a28f4b220ed10205147a8bd9e4d29cf60f514f80d86546473f47dfe42e992fe9804e118006	1655470599000000	1656075399000000	1719147399000000	1813755399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xad791480637db2f4cd033da907191668a86add379c0995e043df5fad37e92491008d8471d4ac2cb1d5c63268fdf0bb3b0bf0804b6fcb58a7937f44fc8ecfb25e	1	0	\\x0000000100000000008000039d156327523c072c45632b81305a4cc676b9cecd4a1aecceb7c8f3410180e7a90d366cfdb86c07eea7fbeb987d9f01a9fd4352571f0a0610e7a5488d134ec5f1dd8dbb82516ef42a1f7a0020b92cf9134f728cc4b1b7b13b4be4bb445d0d555c527bb8c2d3bbb4e1bd443ff2c033232c86a44d154838e73d2e6d31503d65da79010001	\\x3310dbeb629f8059983900b60ba4a16e0a31c46330791d034efda181f3f5c21876315e36d8139675b73d6414f3cf8e10762f39224e7e4ccca197a1f0370ca10d	1648821099000000	1649425899000000	1712497899000000	1807105899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
193	\\xae2dd8f56765aa937747adcf141443f711d7ff6072526f9d2f20eda4234ff4c5d82df8e706bc72509ba732054eb182f4d783156658cbc83b3d43dd3f08ccda3d	1	0	\\x000000010000000000800003bccbd5404bad8789c8013cefe54a17e66cb67340adb794181534ccc64ba285d5d12fcbcde494916f8be95957cc1cf8839a153e8fb5d79f10cabdf4e3c6a9cbca17446058363f599b82dec24b1e20e7beba3f90160e73c219fc61cedc2924ed8f886c7fe6dc995f31e02b13164dfca1f9249dea2691bfbc619f5c1028a1289955010001	\\x80d783448b490c50d9a53d2dc876ce8a36ef3c39617d8e31d9cdd2fd0eab30942268be36cd7055a39d92190b84d4448d264f3c79ebc6ecbdab142103a7d26f0d	1651239099000000	1651843899000000	1714915899000000	1809523899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xae6166f40f154fcea58d3258021643479be73c93946bce359cfd5d196338f74c410f2244096ede6fc41526f7ba42b666487667c5352e9d0ff9e0d52ec0e43157	1	0	\\x000000010000000000800003eb6d1205e8d57bcac1dc1553a16c3943ea80200941c7f6e977b9e4262d153d82e60d129ee2265d4818ac660f03b81ac92b7a4e36a6ac7277c45c125b0f842d3521872ada21addfe2811293bedc7e2a92777389cee7fa559a34b0826f6f5243040fe4907bed0d2047e006b0c7caaefa9be6e7ee67ef7ec82c350923213055796f010001	\\xd93cb9c416f870d385021f8ed1251e479707e8033707f9cbda676b98ee9846b287bdc5d659228deb0486786e12b4f6986a3779d673ac2265fc5de8af3d4a9f0f	1673605599000000	1674210399000000	1737282399000000	1831890399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
195	\\xb0055c56244eacfa3ca946c027dd5b5f780646b0692deb6802d5d8128730a50657500f42e084d1299e67498b6f3ce1cefb882ed01c49a0e352cc324becbef1f5	1	0	\\x000000010000000000800003c8772d693860dbb1ea29d39236992b68aba773b6fe06ee1152085d88f7cf4136b5f6d52be5be3065605629bc7507eb4035c57a99ddc5a34ec7cdb71fa31c219943012a97fe4647ab3f81aebfc9cee8796a33e40a3a173dd5ec8796246a896337c470f4ddbc0e84b76cc63c142976dab622bfb0a5a548a0e09a0b3e187cd419b5010001	\\x4f96cac1f71ce1abff253324d015ff0f76757f99c5d724e9fec294375956b735f10133d59f52db7b4fdbf6c82bbba56c7ac7bd59ba8cc0506a0f829dc113b905	1669978599000000	1670583399000000	1733655399000000	1828263399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xb3a5d2e95359f7839ca04e9b87be1c5078f544fb4a1c273a3d5d6fa6234876fceca1b964cd427913eedda59395539a0da5be7d08a6c08e8fb080b29b52f7f92f	1	0	\\x000000010000000000800003a801ba92315031f0d118ac1240fe4dfd94a9823d32a37c616e83a68384a82a602f1430479ca16d1f6cbe07a3077ac9dd6e3ddcd52221100a4d5a58074a11d0beb5a4ae1d27612872de3e2cf03e420e8456c4f76f8b324b5656913be38189e21d64886d1ae483a48db2dcfe6a065464d79194ae1a362dce50d31b8507eaaa57ed010001	\\xee82d8470c60aa7de83ea2e2e28de6f9cb182439c13f29360380c7565e71f9319a226c1224cf58ced0b24a092cdfe1b57ac087e4335c4192e2a85b39041b2106	1678441599000000	1679046399000000	1742118399000000	1836726399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xb4d90e6c05d09be79b9f04cac6c756f525293e29573b7f8b0e27d4e4140802ba1caa5f37881b6395e819a408cad39604ff2441b79b4bade1e76fe4d93fdc0f97	1	0	\\x0000000100000000008000039e6af7f14038da5e0b69cadd85f5dae9c89329c64475961ca536ce0b2e84ed92abce5a94da429cd192e7c105c272662cd39262a98b8c7e327bd838268259ff2688286907392bbf224e64ced92db2eaedc84727aa02c4c126a7a07aabb917fcbdb964fc051e39926fadadb925a88247e16ead05b2202097466b4f5bf5a726e357010001	\\x6dae698ded4d12f16fae8e9d0e9071dedc33fcd4d7ad1dd83f9879001e4f2b21c405089629ab7e91734721e9b9aa6b5de10391e17376cc395f34f898ef8bc30b	1658493099000000	1659097899000000	1722169899000000	1816777899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xb581982ef4f9465741ec3914a52b216f4fbcbde57851d6f9ab06fb19f73b54408311e728ba8323748c6d9e0ce23044fef9d166d50301f788a16a8712f7e53279	1	0	\\x000000010000000000800003cd5b41f74f71f5815018ed93496681e81b2e7850f0aef2e9979357402835e66a62cf94f13f89cef59413973bd45fa1e909e90fc47a01763b559755651a9d6828038a765ac9390805385531c740bacbe481bad1ac14d75d17e91b9dab491568995afce59e92b2a71756d46ab3a919e9355d7a65ececd74ddd9e22de88f415bfb9010001	\\xeeaf1a58d9261bd49d95df2f1db022b6087a17c9af0aa17fe729c3a52864e9395bcc6bee2c1af0bffc508d79e94bbea6b538f8c203e5aee1e93e9a9f149dd70f	1668769599000000	1669374399000000	1732446399000000	1827054399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xb8fdcba291af5e753652279703850cfd42c3d229cb65bc848e33eaf452c88ebc5032f51ca0fe4ad12ebf33771a0ea8048473e1610f51745c6c2b3adb4af4e100	1	0	\\x000000010000000000800003ba227baa8e58a2063d9e7b3e9085c0720e2b3ffdaeb2aa4293094bd9c4591da121475df7b0b4bf6d47d8676257b8e6c7eff0337565503a7395f6313d65fe63b9ab06a99a143e8b5ed5491e090e98c69112808d50eb52c4f251f17a812019b9b057ceb9cb834e5adfea6af08055d458fa5eb330308227e817631bb23260146c35010001	\\xa5262eb624c40ed1800649e99153fba665905590b1424ea9d03f5fb23831fdacc07240cfc2f6748a0f3d4c3e327ab061cfab17692f2f2d1adced1690f834340a	1672396599000000	1673001399000000	1736073399000000	1830681399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xb8756d47414b06d03ab8b81fd0eb0ed0b0cdec6fb4ce6ad456ff5bd50e70bcec171ee92be46132f7b4f819a7a8ca4cd12b15c2e3b755b30111822a21d622bdac	1	0	\\x000000010000000000800003c78594b196163608f1e4d1d3a8cfe5df8eb43df6d186270b6a43dea5a371f67c7e28cec0cf777367bde3228bf6bffea88d8cb08179f6ed06d0ccc8f2c13b8019ae0ba87e76ef2a7fc065773bd0f7a37ef48573fb6a983fe38431e71dd0f8475bdbb899c49fd9624ff3b388e8bda589a795259c36abe2bf74586c7f6247e5e3ed010001	\\x05a8dc4e1f8f876202a2ca09d58ea50c62fbdb2149c025d263df19cb558ae76bca5b4fd76050644084cc0285883a0659af304a9aaffe039dac9290f622ea1609	1661515599000000	1662120399000000	1725192399000000	1819800399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\xb805879c1a94f4deed06c28faf01110266d5855b4c4bc867945b21f6a1703336e93e56c860783cb8a25be3abbcc9d83981a2c026f5047d6a1ab6ec9b3332a81e	1	0	\\x000000010000000000800003c87b51af169d268aff308237e3d3d10a9dc2e07e2e822bd867ecdcc7abaef14c57c193f0217eaee2be226aa59b09e154c78f145fae730dd842503e9f1b7a18ab291c9503fa5b431c42310823c47fe85615d93a8d17e3b75cb5ff7d4ba17f68eef78eb4c2ce32dad005efa23300d3bbddebe05ddc31b3963aede057e7b3fd9d8d010001	\\xf5e88bbe174b14d9178d08a3b82a6be426969f1d4fa3d15bd5cf10ea66609b410cf30d79ad44c962b8929239f463f75ddc838d7988bd8d286ef802b7e8bd2005	1663933599000000	1664538399000000	1727610399000000	1822218399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xb97d29f8c4b78b7a3c74a40034fe7161f79104d6358016f0c550ef00a3ce098706a5aaae746ad0c3f145c630acea934f698255edc2cdd9de57bdafbdcdae7f3b	1	0	\\x000000010000000000800003c8808236fda07e1c003f41da560eb5e583343290f068426bb2b77a242bccae485664a8679e71ded4aedaf277330528c0137f09d85be0df179f1a64bfbd9c63bd96efad7e830e934126c9754dca80e00dd84b839dbe8c071af88771d5c04f3b78bbad695202c8beeed41236cf5ffb426444cc42258f9bfb08e90c8f70d02d9d5f010001	\\x2c482bcccf414daca680174ba13c2c54e5324bc9b24cdb9b768aa479835a95ff167cf7616cb0033f596efba758580ac88ebebfa0b6fe7c4cf9d3263959152c07	1667560599000000	1668165399000000	1731237399000000	1825845399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xbac58c801a63830dba32560e4208666f8cdfe0a3fbb943cb772886a345e527ee3e7f613796b99dcf5acf5fba04f18fbc5b4dc1f8db908fcfceb2c14e2ad772f7	1	0	\\x000000010000000000800003ca8a4cfc502c4f3617819fe066328aa2e979a0cebb674fb35ec33f416ceffb27e7088024eb860148b6fcd76e93f07d812861f0ccb34a1af6a131c4ad3867989f28014dd8e15267387becc279a0c422b95ec916dc1af6c98f0647089841103e16c9ec68374cccea8c136cea88f9facfacce8d2c1fd59bec8f74e97bfb6bb57ead010001	\\x828a2dfaf86280a4abc11ee7b518791db3b009561bdc2603150c0d2440ba4d5c10ce82d44377059468ac34dab63784d3c022bfd5b189e057b567aba493290304	1667560599000000	1668165399000000	1731237399000000	1825845399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
204	\\xbc85502ccd5aad1ef14b948025de399d8ba8158d5a5035d20e26689c3398fa5cec2bf0574530e86c3d12169434105640b236264a16069c4d927ba9e088f44348	1	0	\\x000000010000000000800003a16d1afc258a420cd8bb9767c20eacfeee51b4ee5d4de64c3d6664fd6e41fceee5c8dc4ed2389fafbf9b688eacf9fef6d3ce3c20161369d2cda6e0942b5faa545acad1daa9e75b0d963e430dde3d6b775270dd53a74812c1a38fb92678f4056dd14c1efdd4242d5be58254be897ef961737163fab69cc4b78be634852857c4fb010001	\\xc4cb0d41016c1d72b6c48807f40817ba816a52970e1d5e815b3bf377a21616a24f5e50ea7640c46cf9dd3c625bfb962bd260ddcd0fd987e2ad4a47f8dec25c07	1659702099000000	1660306899000000	1723378899000000	1817986899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xc0d1056b997f7fb932194e3ac8bdaf3224ea572e4b2198aa3416cd2335af078c43069c62f3ec03ccdef596ed0a14f6b5459d26f6f0b69c6112f6ca4594b2f4ec	1	0	\\x000000010000000000800003d2d31910ba8443395650f7233a941cb4935783492ba2c9869eebf70db62def6ab6b06ef79c38ec3c36225ea59cc124d938b6f086acd335494d4ad1b0cc6653720515bfbc543f882afa44fdd14efa4a9db31a95b17d9e9d86e401b42cd786196458ae76c2272f0ff3928daaaed04769f6e8363a76cec19b77261a80937ca69cc9010001	\\xc7b028aa27a3b882680e58627b8d1f29772a701e133ddb6107f63edd5996af3086f549cd3fe955dd4c268a2567ea24048c86616ffbab59cef58f79de3bd4250c	1648216599000000	1648821399000000	1711893399000000	1806501399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xc3bd0aaff0df80064ef607fc8eed8441d6c2d9c54391cc9c0fbd2ed4fedfe3d8adc3844d375962f0ccde1817e1f6d02f41c5d08ec265ca5ef65c050535ae66c8	1	0	\\x000000010000000000800003ca93fe62d668201b25a653f808671f3c991da76cdf0298b528c01e34bcb960fa285618f078efc491aa512ba620a07d11d44a4803fb3209f6df757e7e9a781d025a358ac60814d897457d352f01dd212de4b6c9143938b246041d5b6bf8a5994ef7eed9588027f0c27327147746010b74eb71bbd7809ccc231cc7a72441c58baf010001	\\x9cb6cd0b5770840209cce4b1a482a07bb8bd8357457c8d97a6d18bb2a7c99785f5305adc48612499a30553b64a924fef92f41d2c9cda903ed931893b15796a0f	1655470599000000	1656075399000000	1719147399000000	1813755399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
207	\\xc5b91ccfe8dc06b11ed77f9de3d26fc2a22f80891d301818631df3e109187df8146a20b892045a52895f38086dffd6dd8cac2a15cce1cae12e0349df8af9bb4a	1	0	\\x000000010000000000800003deea5d6868fcd6e23b316e1aa18cf1bf5b5d1926c2f982d7639f8c9be14d5538283d8fe758f5c087062e2d1465844d65361a8d90a5bdfde90facdfe236dd6f002340e43a833adb285a40a6e4e84362df85730e44914db8485e8d8134f1470a596d1929483cafd6e63f0c7eeaca32d38e76e874bad3d9643b81c6f60f5ccaf675010001	\\xf0d0026af848906c638c33318e9bf52c591348c24d3b53b702a309cb84efbfaea905e8a0b0e551b8f10fbf4bb7bd7435f9bb175b9e00a4cb205e9fb0e891560f	1671187599000000	1671792399000000	1734864399000000	1829472399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
208	\\xc5b964d596b685f8e7b38f2a306d34ab368d84e47e3c7f02491af894eaf51f66fd065e429e330dc997b84deb50adb8bdb77f19d6657757256c8b9027e0c94dca	1	0	\\x000000010000000000800003bc718db7c99c380defa706b7ca7d0a61ddfbaf17095f49dfc78ce97962f0a6d2add5b3b0133a678e50e3fd502162ee7f9bad0834ea743a09c3b71ef314f732abe42e1b7ce8093c5fd102b8c5abe2cb5f5b3830c9a9643697f8dff4d0929063355fda31e293c730aba1c71d52247114522ebfa7c2401c57463667e2862ff70c5b010001	\\x0f6532666aa24a9d28ff8bcfea66c3782b2c44d2d54489847eda17333b1fb29963ec8126c5e699f592bb03b07c005f772bc04882dfd0bee16bcffb877be51708	1663329099000000	1663933899000000	1727005899000000	1821613899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
209	\\xcb91ef3ef438374e8da966bf2be8f8648fe1a36e2b8e1caf0afbac0177503d35e21a9a707c403dedc9e31bd02b19cd2e3b02f4f0fb3a001fb21ab2a269a21c54	1	0	\\x000000010000000000800003c61afd6ecd92e8996b4f9aa385bf6f925cbddc5bcb017628fe59792d75de7f6805fb40e7a25c2800cd1838ecbbde6b5747db27331fce0755386271fa6aa08da4cb62258535a8650780946dbbc7efe638ec90c46d6a7e0b2839c2dd8ece0fd989a59310d69b9d154e027e969f29a9b8aedc03d7304ad9b37f64b3cde5e310f79b010001	\\x327d3508daef6bf9c89ad429f28ef62f086e048ca64e3af511693bc2e31118c1c245198d17b3be1ac04e8ecac08e8863f3529d3cf6266eb41047ada13622fc05	1673001099000000	1673605899000000	1736677899000000	1831285899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xcdf12802d43c64cabe4e798e5447718edac700629ad2d2c7ec4e0163b07b05b449f01056c8c3f1b262fc2e329a2435ae2a2195f9117692a74d6985606f7e8407	1	0	\\x000000010000000000800003cd5017c92544f16cbbf3c5114a86464cff69909ac9ac1abe20019cd2acbb12ebbb35110099c744175db1b26b2547a94744dd302778a825b1ed6b914658df84f9f385059cd45f678bbdf7ba1fdef073e120ce2ee54dd9d229557097e56f4fe9a7487579131c726f36218f5a0f2b7ac87530b94ada4000ded1c27927c406ffca53010001	\\xce15907aea9235cfe439787125f2786ecd4f670a64714d65094735501abe99d08da7d826f321ba9e4781b1ccfb17cbfdaa976ffa03badfab83f3a3cc0d0eee0e	1663329099000000	1663933899000000	1727005899000000	1821613899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\xcf1d089785ab7aa9d2e2a43aebd2d2b4fe5bf435a9b61121c0ea7bb33830f1e156ba6289420f01210e70c494db5dc812cf7137c91ba406e7bfc58d256dc1ff90	1	0	\\x000000010000000000800003939efea71fac872d72e1e8fc140265bd9246c5ca48d1eb9572d59ff06e9870a3a36a81bbb16ca6ed5c70c9487d13ff02bb28937111a89c96ce2299bacbf37d3463c5ee9a7353b70c9fe4366a42252b907bccc8030f36e29b4ebb417d8c39ee5a5a8d123f9e845bd32ee721d679b892501021afc802e33af7a1c5bd9ee6d9307b010001	\\x5f650e940b2d0633e05242081241600a7ee7e0a6524a20ed16da9739086003cbd1692a7996fce8409b0cb96bbf72c5fe4a37f616963a9561b3c055cc15c5b30b	1675419099000000	1676023899000000	1739095899000000	1833703899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
212	\\xcf8542ec2e5cc9586dc4751f9a52f374d52a2f66c4ecf56e05266ea3f71acad7efc0bec7e0e2bc352790d2e8bb4c0700beabb8562f220192c29e32a4f870c7f0	1	0	\\x000000010000000000800003c4ebc3843a89e53e89c5745fca670b8b9bb045eb06851235f7189519cabf0fba02a966af22c1a49f33140dcec4a21cde43671cd944bdd767a1dfe3dc17d47a827a790047e8ca9c1e8d2d4c6f231c9470981225d0c20a31fd7fa6bd36849f21629f1ec0c216dc60e6b4341874fa9970a580a21945746cd7332740fb558064ffe1010001	\\xc7a83f687ff808080f55a2943ed65af90e065f1888b3639203cc9e6a32274ec29b8d9260406de3d3dc16650773246ee8c3927b5f53350a7b65a49451a4f2c00d	1659702099000000	1660306899000000	1723378899000000	1817986899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\xcf8df3462a0ab6a91de734be3e187bd5f9917ca01cbbaafef0769bb14154250b27c2a7b3e7654efb2808f9503cc279a9ed37f0bac6f4744752e50e9b47542364	1	0	\\x000000010000000000800003e61fb611c6c8e83c13879c79b8dac7363cbc57895e0500ae51f85be7072c3a424a7db368414c81356e4b81fd2e8e9ac2b3bf46c6ceff621a863c755ee2a52c0ac7edb1e0d53ec1fb71ed31abbb73aa58e68deee96fbe258e1be9d0f8b4e62e17e0c9aaf9a7d43dd8365023c1ee0153277443984b7bcac8f533fa0fbbfe5bdd1f010001	\\x680ead10c463dc532dd700fa4001ed8ae9b5b7a636e1b6865d20e8aaae2b22fb51aa7b8d334cd74eee9d3aea298f02fc7151260dee233a4339986b64b818eb0b	1679046099000000	1679650899000000	1742722899000000	1837330899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\xd15dacf7880ca8720c4554d7de21beb1b755bae6dd6722fc3aa4fe0412dfd79a410b181bf84fd620508280b8794a59214d883f0dff3a0a0b45f699db91fe9931	1	0	\\x0000000100000000008000039e724bac09e1eb8d0801ba29ebf5ab5f1c92378dbaf8edc80ece602e63238cde5bb167e1c90ef920f3ee09ad86c02dd727f2b16149a4051509c2b3cfe878618b13a2224fbc87478ce80e5845722b52990af3b95c6863280c53c0ef0ab083673fb34987c309c2d8ea0709b3d5a58f6cc86a1f67f1465eb29580c677abf46c26af010001	\\x04d2984773706210891945f406e3e28319917d66eb12701ac9b0becb46a4a9ad663e6525d9f7759b8e9d510e4ca973ed2aa67fc3e6a69105d999316c0e8e5e04	1654261599000000	1654866399000000	1717938399000000	1812546399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\xd1f5870d70b9cc6f8566cc4803faa9fbfdb8761dd61540b0a97ac945cd049f8c892a0b1ccde8f33d015b2aa337ab02608a673c435cc59b37a2beb469899bff38	1	0	\\x000000010000000000800003d2678ee909d1b0c290efce0af12c7cc77d9a59d0f41618571984a916611df0340524e88ccb04f29857383cb9f34f552fae046d46dbe20860d4fcada8eea701cc27dc5fde0fa6a1b238d0d5e7e44b91c523bcc704cd6337c1d52a8e7c4ec476f6123ff991865a5b8d62339ae7e161b580bc70061e2f3d0dd9bc16c6cde12e7a0d010001	\\x8aa8d4b9b2f1be1fe20352adf69426788e0cade4e8076414d79954ac343421899f09757ac32ff2e5f01d04486bdf84e91e58ef0abd89b04138f07612cfde640b	1679046099000000	1679650899000000	1742722899000000	1837330899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
216	\\xd1e98ab2418e5f8380271d33bc143bd783fac3d0a309e3c34de88fe0c8193a73fa0e08dad1c9fd1489f472e2e9743a49cf7dc3e31fc93b2180700212bf77aa5c	1	0	\\x000000010000000000800003bf4e77385d7f46a2d10cdc27eca2d6d4f98550ee6ad33da76d308de41b63dab1ccac82dc97ebbe82c7a2482b9d773375e67de4fecd654b0862740b2b91920ab8519d06a0e2761b3b952368d8b4e18beea4dbbf2ef24116d93b034e180e227cdf49fa39b13d0386fa171ce4d28bcc3dfe4f89b2249ad5c0b4880f58a19505bb03010001	\\xe3d0f2812240948b9880eaca598a1797343b11882dddf112f9cd26310cd9b837eeb395808bbc6770d75f97c458a3a5f90c0a54f4cc711509082c36b00d62b80a	1664538099000000	1665142899000000	1728214899000000	1822822899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
217	\\xd1ed6132acce27bcd5fe5d3a91be254d7726258a996b096cf185128c4c9cefa1e3851430707e8c61223cff904a5478fd66b6c7fff60f46d17db76aed6e85a488	1	0	\\x000000010000000000800003c0687803db802570f316ddddf2669172da9da0f0a795971c2c12017843741ac13ca79d7d31dde823e303bfd11e56f7847f6b9a55263d63307274ecf3db273c0291751edce7a82ed637df906c0b647966f4d5f39b59fefad0639fa4d4022204690ae7d8fab36d124007cb0d14d21e53213ef47cda8104f7f5c64202999e7c3f3d010001	\\xba11e82074145e418730ec34fefef3f0f1aaba2c842318b9f2cd596eec31be68593c7f5f6da115f40aa38bbfabcc9cba2cdcb4f439ec9c8a63876d365725df09	1657284099000000	1657888899000000	1720960899000000	1815568899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\xd1350ac460e07283bf30b5d6e77c64c7f68a148c470c7675e9f4478af438e7294f3dfeea34511e1bb74766d523562ef94471acf589204e87b68f1c9b5b8c6f95	1	0	\\x000000010000000000800003cd8b0b880584f036e11fa7de778cb58cd87292ad15a98c045eb42a2daffd684587879ed586fed69ac22991e2e8b2543e5bb576a87a41cde3d5cba739d43be0d6df4d0b13bb27132d79a72d542580b11a1d4662455f50150e2a1f1f83d5ee3b79faf5c2f7509d4ed6d81fedf54bd0090a9f709ad6b52e5a6cf57402b9dedf6a47010001	\\x271efd55f49bb1c667049e909e2b131397fa2f6cf5af2e0d3060f4bce561d2dc549c571f4ec6b75ce76df90973f9a8d91ee7a4de4b27ba33c63b6c5ab323d00b	1653657099000000	1654261899000000	1717333899000000	1811941899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
219	\\xd2293714c64488d0d570f45e926b6d5093dff5d68d688539e50b0746e3deec25a83907c9c40784b4ba731e7909921dc4126e91ff2db7103235129cb110c89457	1	0	\\x000000010000000000800003e390683dd00bb98e2cadc2cba6461c9365fc52c9226f4e82fe6b999795b17667ba047c193bf8aafed683bc6c9c5b88cdbdd5c6d5b2a486b34e17031e12addfeca8b8d596959664ee1b6564fb0ba658675db2c31d7851283ab60ff5f4a6b4eb5b94f3774f3618690204d0eff87a071de6ee5506867f1e3c4f24f6f47f796ba0a5010001	\\xb1a5b2270f7c5c89f171352f8df61d4658463c01127074e51b7d6d6afc2015961076a83630e014ffc0a8cf7a2a0d1f7d815719e82c656af861d8f237eead580e	1676023599000000	1676628399000000	1739700399000000	1834308399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
220	\\xd4951be7e7b642a77798348d667a8f85bf611c02aaefd9bb053fc107d40e79553f8e6c931fe8c13377a2cd2a4fefa3ddaf6b165fcb810fe0780d8f40fb162583	1	0	\\x000000010000000000800003cd3f39bb13be87d00e72771b9cf9cfe44c0402bb3f71d458fd83e366345c08625ae1e0ad5b8e3a9a38fb50b47b81462565974e78bda2929adf79db800d42879337d39c0f1f841ba844b2faf62a59424feb1c3f6a11eecfd8d77f63c7836d60cc0a10a13000ee9f742940d667ec87a37b7b2ce8a4e7a52bbd79f806c38990a8a1010001	\\xd2ab640447ebeb8cbeb7d893522f4e00bf806236ca510e6c02b0021ba873abe053eeb1b308847a5edda13d2ab8a517b7991e2dc1364c41f442fe957509aab90b	1659702099000000	1660306899000000	1723378899000000	1817986899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\xd89141abfd3d81c8f2667584b510c5137231fb3ce236ef3d964b7f4e8c3c39b3c959bffd429ae8c8c17edb659727e317051acb2f351d958a0d9292c0e0265b38	1	0	\\x000000010000000000800003b0f88af2bbaa03b543319ef7448d3273e8eae20aae69726e574b7d5385b7b76a46eed2e0185ca6eab461e32bc867825d87e254f58d5c6bbe64f38bc5768896733fbfaf13c14998117749d4663e0ac886a1f0d7b02469a0b7d03a5e31054b82bd4d80a80e3f2e63ced97ab4ba7680157c7c9aa615d470149f59a26966343551f7010001	\\xb0e64deb4adc35e9cf9c5981f274953942f58b95d63dcc2909a2c19688922cb70d342e8bf6a35c3854ec57db99352c63c4442b03b9630720d5e29bcb8d5a210f	1666956099000000	1667560899000000	1730632899000000	1825240899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
222	\\xdcd9270a9041c72bdef0d77479fa7912666a5526a3c42b371aa490671cc42021588454b2bf10ab1fe49c9a7fbef9f8bffc0afbe06200427b205b994b91303ae0	1	0	\\x000000010000000000800003b70e5e9261c3b6797f1818863a5648e71ef0609b9ee63650dbb5bac3e72ea0a436a783a4af73a3cdb49bee008199fb979d3eeed3d359c490ba4017573cefa5207c5c15dcb6b514a9ee645aafd5f8a920e296a92ff340c81e47f9b91b0a82a0b2a623328708b544b5bdcc745556e81788f7450c5ddc0c137edf43a277260795f3010001	\\xfa9a6855d162cb02e9d8a1bf6d87e0baaa6799468491eb30d56b87db64439e279cb37305e0bdc726bf59d73c12bea06b0bfab8ecc01dc86481544732f8cdc30a	1679046099000000	1679650899000000	1742722899000000	1837330899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
223	\\xdfdddafe7df1a89434075452776e99863ddf490b95db0e34a373e9911f24545bf700e2f84c4585e1bb5311b2a5a7aeae92d94001dd4578084379018f75ebee76	1	0	\\x000000010000000000800003bd53672b1d4141ff295e478e9b979b3cf89a7227e8c5ad859c531ba16efab6a9adca019d5d2465f71bf959662d2c3ba84bda240ef3d5a50a678e7777a981beb2c21376c48cb846e4ef659588a7566b4ab5cf58e30e1823e55ab9efd1d78251386c5afaf49117ce5103d4d38ae92a05213012554c8e92dfc4a97f0bdc1476fc49010001	\\x92349c2629355a7b363c93ccc1b5c97450f940cd9777076dbbb8a930c683ae8d06afbf5a60728f4bb4b26184385c0cb14cb362b3779431961aff62485c7ae104	1668165099000000	1668769899000000	1731841899000000	1826449899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\xe0698b6db427fff66cc3a9a4a08e977b13885dc02880ad19bbbe95497b2851e2d121a814228a6592903eb90eb75ef51335e3d35e9be9e77b0092e12821ffd4cd	1	0	\\x000000010000000000800003a904fdb97c52ac2bdc84b6f1041d3632a7f0b12d68fe60ffab4997318c02d534ccbc028e554efd1ffd28e179af808603683d494cf1b2d0ff1c026b060cb057438136499122362bcb79cf87a4bde3131e43122b3ea6ccf45f46796c5b60e88b7a1b3e1f8a376f0d2db4295de367a18cc55b41bfb68f294882bad6cc8289de9401010001	\\x96ccf7220336365a80703c4c8d7cae5f76fdb60b3e4837abe27810d7e342050781c6d8d21d8a725839ab0a479d6f52c8b7892d80feb3bb719fb8cdfa35850208	1672396599000000	1673001399000000	1736073399000000	1830681399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\xe0755d3f98be6a1cf6dc11fd0f86a0258a416830cb091f528e50b36e5d686952c14713af3e34c2a3d12ab8a715790cb935cdcf952b59e389343f8af3ce8b0e64	1	0	\\x000000010000000000800003d5de30290d09460e68f4a9497ff5f53ee11422d8d4313725d80fa24540d7f004d96228b413aaa61f08f49793dfa02bf3589715a58eca72994014532a561be7efd33e334d2c450c261ed86688d625a11dd0820260a165228a8f059701d005c1c29ef3cc59750072b464aeb6f5cc98ec90c08e503df2eab07b5c2746f442bc3761010001	\\xb275ee62e03ffebebdfe58095b5c6daf45908e0b2e987217d53551e03775f512bebb49ac8fd1352633bd1d44c2b5d3888752901638e9edc6b921a2202cf15301	1654261599000000	1654866399000000	1717938399000000	1812546399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
226	\\xe299f602e766e9faca3e0f2c4bcc8792a7141d88eb43c3695e4c4f12d19cc3227d971cfcd22ee4bd19446f9c49d659f3c7a344d39faac4a2bb6f5fa970c7ee49	1	0	\\x000000010000000000800003fdde2a6fa4a4bd10eebbd8d3e18738ac12e34d069b5e001d1f79e81cab7ec698b4b75f5e288f8842c0397048ca6bf706fae2c3232a650fc7a8c24f9c9ed77cc58af2393d5d32588d44853add56730fa451fbffd71e67d3a91623a562e4884d695a8fd37a0583abc78408e21a449d8c026acb510b606aa2f2692358c88ab77e6b010001	\\xb9ccfa4acd68bfee9d5a21cff0a1847350e3b72c54cb802774f059be3c9f51510d1818d24c64d25871280dfc966e4f2929db53c44ee12f753f5d7e4ded449306	1677837099000000	1678441899000000	1741513899000000	1836121899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
227	\\xe30ddb986178e97f93f615b5df2c4e328f6a52b9212c0c294faf080664d395011e59c4d42ea2d8ed3c7ed7197e4394db4fe0250a93adc60cd8f8a4b97705dfa4	1	0	\\x000000010000000000800003a55e6ca11fbfc01835c9d05a6af6553b220bff84c8c09e483b00d7e27f556931c066ebb00fac0b032c3f396023bf87931a95cfa70f5f6e1012fef5ab5b93897fb56d54d6704b05d244994287152531dc05309646fbfdaeae0683914f6974eb72da6aea77d2496d8ae2d2271f2eb1c13debbc0b2996a26d71fac7d1f5facac5c3010001	\\xe2aaca19c8e3eebb1ae37f5991d07f9d6a3166ae3fe9afa776717d30b0da61a20513b62d74123aaaa156284a8bed18ce7c94194e32023bda8e99a16d0f687109	1649425599000000	1650030399000000	1713102399000000	1807710399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\xe4c916d93c62e0d216ee7063d24ae30293a0192d42f387432b4c68340f5e36c0f6f65c2fa9d75eb75d6106c6aa50ea1ef31f6c98aeb1ffd62891940c963341c6	1	0	\\x000000010000000000800003a7c6c36aeac0fac04ce01fb7eeb3bcea29544db06c22de1c831f3134f0e42e5ccdfff6bef1bba0ab19abf419d14e143abeb47b16b33754e2c3e869e1cc27b815e50f32b3c544b910bdcb53190a5fc303d0cfb38fa00c0e4ce3ab44c9c08438a3db01be515e47da7fadd118df2db47282cd15a24b083f919c2165d653fe0c50f9010001	\\xa07db39a33b8c5d99e339a1576fc58b9bae7a6432c7bb742f32fa3452e3e1e70a2d2d37ab712eb75905160e81bcfb8e9a4000945731cbbc5c4010eba44d61402	1660306599000000	1660911399000000	1723983399000000	1818591399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
229	\\xe65930404495dec92e32ab75aecd3680d8004e7978bc47ee320dad2467db081828a6444cecda29da3c9c324e18148c6d6725a2382f10870ad9e1db1fa2efbfd1	1	0	\\x000000010000000000800003df0f50c2f78366fb5017b3ed6b78d906c6a5b0bbaf89ed29b97a8b65a81b27bd280673ee9ec5b92624eb41c03e119960dcae9ce67e7102840e09c595518afb8fb1d0d4f347c4e66ede017fe0f1433cccc92c08f92c0121381866c8a84885910646e38b1e2bb2cf2eef8a9fea7e213b0fa22aea6bef52c318b097027f783e86d9010001	\\x1b91d3c76a41bc83502d3a61c737c00146fead33289ec90f3e4bc331960edcf33fc56693fa0db8a6f82d85a021c4ccb6ca4816fdb0228cbc7505074b9a372f0b	1654866099000000	1655470899000000	1718542899000000	1813150899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\xe961f48cf901696fa8cb6d7f3b1f92fde8b62ea58ad4a28f19ff84c1d109500d7f833727efd6bdd2e56a925b86780c3ca8c5fbb417b76c914e601bf4fb9e0a0c	1	0	\\x000000010000000000800003a646f29b871fb684e14e0140fc394f1d740893d43f6e9286a408d3fdeaea64b04efc6503a5eb474313411b776801043d6a3b6534ecdb177a55e1508cfeeb93b7d687ed39231a5c26f7e0242e3fe6e00aeae55aed31465dc78b197a8c362bed5cac1c7c5af30c3b2018ae544e637d6cd8c49edee10c19f25556bc7b3d4c6b64db010001	\\x38371cb6be0d29bd47a956f2c027fad888db46ecf8c0dd3a09c402f61aa9b29164ec7957d72b88b41eca83d564c0dea01851cf9281bdb504ee0a69ff592e0606	1676023599000000	1676628399000000	1739700399000000	1834308399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
231	\\xea417e1dc12958e9dbff1d9c355d5b0a9703bc3738c19ed8ff3a811f64690167a348736f1eae6cf45bc0d9cdf342997ae826ce1ac62ace114006dc1ced9293f6	1	0	\\x000000010000000000800003b04004cc47c4486fcdc278f9c7c9c3a0ca8028169124c93c58e603f945ffeb2191c088b040aeb730a7eab8e90f70fbf9e4e0c3bc9052a84594c912dd340646d3db1d62f8e3abd26cc2d5f9fed3a5fa69dd357471848af39a73f89194f7e997dac74d3dff9443e995ff05d1d5a76dc67b1cfbfcc1d46c575b8a5a05abf15cc987010001	\\x033d733b3b25f6beb334ec138e5e10a889763bdb87f4707237f2b989a9fb100b6ea2da214d38425af2059b1acd79b122084120fea29eec356a887c8f180a2705	1650634599000000	1651239399000000	1714311399000000	1808919399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
232	\\xeccdf0071ebfcf5864cab067704d1ebe2237babcf4d1326ccb3054b7c4b45523a0ac4f56f3829176289ebc59eded165987b93ca166b9c4697f879ebc8e5d615f	1	0	\\x000000010000000000800003c2dad0df167fa69112a6d8e055a719d7e8f0cab7e62b12c780b58a1c5b2792c138d01055c41ab589868971dc316fb806d46dba108364c789e140db8b0f90a2e3231d3b6c007d9b9cf110b3955effe4583ad6acac3c80eb675bf14599ac6c7aa0b1ad1ecefc4e6f34213c33d006cf0992b2257d94016e079db0830e56a3b56bd1010001	\\x7df6f2acdde116fb74317a92ec8b3b14c0d20b1c0bafd634fc965bf559898bb03f9131d90890f01309050b3e008aaf8817fbca5ccaab0d3e2eb4d16df33aaa01	1657284099000000	1657888899000000	1720960899000000	1815568899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\xeee19437aa7b87905126ccefe2691af2a0a6ea23ea6471a4ad74dd3e5b6a9eb659357777ce9c1488957be04f4dad3bec2968d2d3077e6804b032ea8fffe7ec20	1	0	\\x000000010000000000800003b19c102d68904170a97594142d6727fc3fe7ba803d9a79d8fcc23b7818872d622528f8053898ad5dd063ceb6e6e065d1a43e4f61eee1ce779919e685106f8b4aaee8a6fcac1685386c0e863e37aef4b0d8666dfc0b516553aa0a2712506962b03a98d77d64a8e442d73bb1f06990d17afea020e8fe172172048ac1671770ef45010001	\\x35ec2960480ec509980468649cff585be9dd7f028033326b366d34760feeaf3693a3c8639e5dbccd5899fc261f88c1bafa6b05f802c84910522c9d0d4a86010b	1657888599000000	1658493399000000	1721565399000000	1816173399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
234	\\xf161a22ba9f90bd76af51cf8fb28c850ce431a523ef2f4608e436349916c3d8f62cc36c57ee8f1bd41a14e317db31933200b238e1e6b75dc0138680b8d96c8d5	1	0	\\x000000010000000000800003debd52d6fc04337d2afa08d1512ff7f1916b10adbb51007709f4422a8240b812b2beca6ce6ed646e4abd0220afb57f2f804b338527d09d74718c2afb9541ce887103692d7e94881ed63d37127a9ddaf0993377398434c3eb74bab136d7c30c86cb66c8a23a7a78f48a45efc8d4396c9348aa96212a3250e665afd4ba33d12c45010001	\\x4500fc047e484992b2a9012e684973b28aa327a04df779a2e69c3dcfbccc1d9ec656a82893c3de42caa3ecb7bf55f31fb29936b1e3a32fa9f741cd8a8091f308	1676023599000000	1676628399000000	1739700399000000	1834308399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\xf2c1935c166292cf14ffda8e4696a8258044ab0639449cd01f7dd79bef82974a362bb264abdcfb85024fcec5310dd1c4ec87c61f68c525180d5116015a25489a	1	0	\\x0000000100000000008000039d0e25537b662d729d64c30388aae972a10efa88f9d11f5fd3fdcd15c002980fdd19ae33b15253b78ba366639a7f72a1abbea875cde8cc986fdddfdcab35d546f2e14ae7d1a18fbe31548753348b458baec42ea64c739d9dd38380743c275caf4ff07d5a29be05099744d388bcaf9f72cddd13a99bbcd2a7796ff586b2e52b4f010001	\\x32fc38f3446fc847a887613af1318ab85c4b3d9cab12f3bc5efe845ad783ccdd6fd2698631ae8e9bd42941a436bb98c2a23c38c417b747c0443ba4a18da18e08	1668769599000000	1669374399000000	1732446399000000	1827054399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
236	\\xf8895aac9ec7c831decf81827970ff2b172b6891b458bd3b058b6e2072c378508a54dd3460b2c493799daa29da52b685092409f1137327e935073711323c5096	1	0	\\x000000010000000000800003aaaf85fb1b92ed821851f153a2bfd73f5625ec59efafb8ac94eacd25073b933368ec40d8496d55804dd6782f0ba36b03d8f4b0c6d8c3eb7d275254453c5bb6cff246b47f91952dacf016eb4310788a1775e8c922c801529ab7d54974cd3e3762edb75d38ecdaf12aba1461cfe3fa25d6e3132c9fd25d02e9cb4895396ea1d555010001	\\x03767064997b0fd808fdd6355915bdd08b2d73d951d3460786860724e98c18c0268df52a0cc6821713f6a866647a3a1897eabd81328aa294f650be65d754b80c	1652448099000000	1653052899000000	1716124899000000	1810732899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\xf9555d44de31acd5b94f61e5901aa4cc20d4eac06184f012934f29c913a34a084fcbfcf7563c2410605dbd63fa3a51e6eac12676933ea95c7abc08adc759adfc	1	0	\\x000000010000000000800003baf40ac142193064a8f469522574dcc00558c1b69cebc99aa461418665741a262c5cb45b9eb586d56a78e706b445b29d7b9d0da5d4783647c4d18bd17e7c01e1e2f5aa1788d16c95b5e84e2a293c317dba61a3a1fd8f043eca895d13d8269962c246f6784c13a48d9238c199527a06e7d360b2749b92432dfe4df006aba42e1f010001	\\xf99efa7988a4d40fbb8f2e52a78b7a5a5002d0e8d42f851859fed0bbe0122ecf56988bbac326bbc9e2974641c63c784b85662359601a0ee5090def3d42cec403	1654261599000000	1654866399000000	1717938399000000	1812546399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x03fe722731193b83186dbd076fa6f2d8aba8eae0f121f0516d8e3b67766220dd2f520970774fa97f905b4e6d2cb98ca4379fae72de823f911c0bbd4dded9bb51	1	0	\\x000000010000000000800003d4cee242ffb739269889de1c4717bbad94f060753c1cf7f266eea753330a9b91767edae38b7a1cf50ce1c92db11d247473d858b4992d9fb373fe0e295415e60b9a2fc924f3559d4048c8ed159f21fa2b0b971c29874acea4ff77ecae52931f9cf8d4ade2cae8f70a322873aa60a2b5e02e46c8794144367cee9beb951f663a2b010001	\\x9cfad98c744d75a71d9d5a4d6e36c516a0acde1c2efbd684831cb0c072a9d4328c6aab74a8b92b79a99dd9029775b91bf079387ee8bee625c12cced9ea1cc708	1673605599000000	1674210399000000	1737282399000000	1831890399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x075a212689092e88e3dd2c1b16d22875c4b1c1f475e2e30807be602d84e50335fd1d84fe6b470ea8aba22ac8c5857ef36c982f515d4e72649450ec8073154085	1	0	\\x000000010000000000800003c04e14e01a594151f599702becf099bfabc576e440aa61170b21e41a4789f138f9334b7d5068d5666e97d80e8a833fda6d98594df1a404b1fd01e0cfbba5a60056b89cdaa22b4c5e0def58561d1d334696777aa0a0438ec9e3304b8b76aa04d88559d13701b15761b52871ce806dfca4d8a8c8e22724d136f2b072d190c8cef7010001	\\xc7876cf242cc03d63592e845ea8c912818157bb02fdc28f1dafeaea1b7c4e215c1abf3328ccdfb907959c8d098946e3f0d7baf30f712d15568f3f633ee662a02	1654261599000000	1654866399000000	1717938399000000	1812546399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x09e60cfc747500984f24db261f02899d55d1c7a7de64fa2641607af303761aae8c78e8e647557a87110f308301463902444ac38e8eeda4504c4f09bcdaedb9a7	1	0	\\x000000010000000000800003b03bd744384c2d579a6595c56f7196d43b924b5316229f717666ce51f0c4e8ab755bf7bbe53a2239fbc76f9800aad92c02265b006f9c5bd8d516e6146d262fd46d9860c743d3c928494bb849de09c9cb056c1a1b3707633662d1c9d0ae6d049fe830eb523134cc945f2712927ea5b1fbcdc762a45914d068afb697d8f4544cf3010001	\\xac1d748699a42ce0f4ea611afae8dd9cb2b3f4db91672c6de2550abfe3a1c04475b95d996231f1d3007978a95c3c094cdd1f48de88fbe73438406dc74428f302	1647612099000000	1648216899000000	1711288899000000	1805896899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
241	\\x09ba5da9959470f8939f5f5195643ca6bbc911bd55d2ff21a6d67aae5cd9fc3763e10a3e50a802fe701df8f5538b8d565b5b0b9972a363cdaa28453a260b897a	1	0	\\x000000010000000000800003e95e005abc2c0082e5b66088037b8ca2d40805730da8e9a29b900770fec3d1a474b776e15534693a06310d4ca311425c870131db32fd9c8fa7b2647beabb1d225b9daa5124c76deb018bcfb2da13f006025390a27b62614a7dffa44eb50a66b7ffa80e515be7df04bb7cd0e7e989472552189369e31f589aae98440b46b3259b010001	\\xe57b2807fee0eb2b55771ca2d3f093c407eff26a181c2d2a429fbf9ab37af70a6b433c77742dc3470bf9d7aadff8533ea11fce1c59539e8d357358d68ba25a0e	1671792099000000	1672396899000000	1735468899000000	1830076899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x0be6a1f2181c27228b856f23b32fb290ef2570adb00c5a4ea4346aaaeaacb42f532e6caaca593118061619467ae621f0846e07c4faf3f203006ec02f0f597510	1	0	\\x000000010000000000800003cca38e939a422d410deaa6c423ed05d83c21a4279f354fd5200fb3253e07ec44c58194f871278044937836d5bdcc945040a515f14422166bef71ecc12d036f4742821a2c4b3cde825c0595e9d667f0210c6028f2020ed5dcb5c0585645936e8045e1991c68ccbc857cfebc55372dca568292ebdd854df35985c606829e2cc34d010001	\\x93a180c7808e9edd08ec96a9f4517b8518ad4a50e5226b1ff45998d2a5ac0436dd027b7f70e3c1e4f6c37c0e9fca518f44976bdf9f310f258011f1226f50bb03	1650030099000000	1650634899000000	1713706899000000	1808314899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x0dde2fcfceeeca44690aa8dba5f654ecfb2994c1ac7978ec80c882ea4b41905d93bc0223498b92118f16e6f99bce0f7a1b2450ceb0dc76d8d184e7507038b8e3	1	0	\\x000000010000000000800003bd00ef9812bffe2c0d7a9c343868672bfcc51692abca1ae38a20976d7a047a33a6f9837f6a0593c2d3f0d6433bf6f32d0631aaed58f1619e07b12814e4e2ccd193e7e255de925758a396911620001d1084bca410fffad5eaf53782dcca3e56f9cb7ace916d4563641b079ff6453cc0f99a2d0cc60ca2e6af4f42d70a50275897010001	\\xa6b94ada3011d686e494eb665e983bfa57705790433de9a7bfc45aafd379bae0ced5af9a55d516c21c927f919a54db00c8022b118a1658cf7080754e11489f02	1658493099000000	1659097899000000	1722169899000000	1816777899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x102281cf3001863b6d57d93d849d752d3cb9cd96d98b490a1b87742d778c88135b128c47033e589ffee10a7c141378e6e5f77ce25a92ba1933a8ab64bbd30f65	1	0	\\x000000010000000000800003b9104e8cc1857f68d9d9cdbc462adefc78b5814126e8f8f7fb225f22824f10a584828c4bb8b6fbf99ba30f5aaaaca0b4648c71b88ed76d745df689e0ea52182b2d1f6c97293bda416f6662472ced8f90917203718574891b8dac3450d27c26d6916f0d7ebb9c3d86d9f04b5bfdb9d6d974f9a31e4380843c116e6832c6bb6d99010001	\\x944c27ee7017a358c929413bfd4d4e445e72172b8684d9d70e44ee14f4e12eaba159d4140143f9486f00608bfc1013bf2021b68502f4820f6bcd2c0f1976f50a	1670583099000000	1671187899000000	1734259899000000	1828867899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x1426d4f9603a975d5a3d80e6101e39a4e832ee8492e17a453a936ff7fcb8285d584f6c04e499bfc4d50bb85986fa4f623ce8b0de916ab063ca6876cbf9420bcf	1	0	\\x000000010000000000800003b9716e833e518038a18911cc64bc160d796806f53238061b6da2d7f93eeba898db93268f755607f5f49bc26e0c2183c284831226531e7d3ccc00d03bf15003c94a66a66a704183a297ad46ccc52c5b9f7eb334e4bb2dff0d97751603adb0d44b4021d280062f05b9b1996659dfed97ebd36bed0f691fe7cbdaf37b261d3db955010001	\\x3f5d2eacc5cb9fa225045ee20a5e6831462267fdca5189c0c6e3c1e70fd7ad7a88826a7ebddf53711ae6f166402550f2604986682fea5d836d02bf9e921f0e0e	1650634599000000	1651239399000000	1714311399000000	1808919399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x169a0f62e3f5dc01bd47cb65bfa4ffb69d1ae70a48f02102ce8892bcd11fb2edf5379d5ade930e87e9a5f1ee075a1eae11d82c1441f865060947f57fb90d7ce8	1	0	\\x000000010000000000800003af8571bec8ebe2f4407e732f913fafd0261f93bf83eb8e944cf9b56af6f6e107a3d996e97d85bac72e790a67db480560b2ecedfbeffafcd0eb3cd166b31029f1cef35c27937ced941c9a99d655ddb988d8bdd2b431601c1af582d939182533cd5723ef9a5c148b037bd351d19140527064ee9366f89cabd53c08b01091d31c77010001	\\xb93c8ee6842e941b3d4f5a016957fd45a9ab132620610d53ae6ec907e2248e3cb9be1f9bd8c69c134d3298cd81da0c47393b36ae771dbf20214f1299ee3e270a	1662120099000000	1662724899000000	1725796899000000	1820404899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x17eefc77c184f63b70d25e9c0b7c3fba22ed4dcb7787116613b8094c368e061296d5b0fd6d700c7c96e6cd174fc145bd83988c25ca36dcc2d6ea0b00ac428e35	1	0	\\x000000010000000000800003d89f5b9d60c25c63969bb0d1db9d7b845068e7eae5f4f8b728d31fc45e3e52c96f7d18d31171ea54825163178c065efe51d6ab397883c97e0b1f621b67041a88a7994df8eda6ea8a46eb137dc63dfa1c1049dd04c33dbe3946172957b0a3d391f8a28dcbc699c667f6f0a4df2212c36536e37a0437c385beed01b89749b4348d010001	\\x33ead2f9cbb61df72a5f86d45b0daff5312412e1c313a42c9053bb560c3312cd796ca17aae6479240093979acc7eca81e6f9e2fb8faa025672f773f661fe760f	1668165099000000	1668769899000000	1731841899000000	1826449899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x1aa2416841e72e29772945cfd6eeb0965ed1a8fb295cfe78e9ad6c8a71c62f8df73c186a65dc1b41b6f02281ad6cf841ff0fa6a35c987dd6132c9d39d79a06cf	1	0	\\x000000010000000000800003c367de5d516e17b23e79664df6f65427e5b395915a6ed05ce41406a2d7eb5bb2fbc8b0db2f5d664f2422d89dcfabd5768337abc16b73b9260f8f3c29802ca7d80b9559469dcd52f7adac892ae51b2b1fa7394cf3da67316b4dd96985425f1c09dcef5105cf7530bfa4486bb71968206b8312b2aa9d5e01a6b9aaed027ad22605010001	\\x34af15c07150826fa44aa438144f7c6c9812f84f267ec220f66f34df8d73c59c00b35b62308a5f01bb29e9c8b261e4a7657f5469358bc8e08ee6baa131edfa0c	1660911099000000	1661515899000000	1724587899000000	1819195899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x1b7a7a8293d5295d82a883548b94c652a07f01a71dd1b3b5ba94eed8bb371337cc5e2324d4bd75be44372b4cb032b99626dad4c340afe79f7278c1032b959ba0	1	0	\\x000000010000000000800003c15caf55e31bd7ad4ea14706ac89a102c0621b55963697adf0e234d19dc41843952d4619a2e70b72e3f89fe9eeeb318f1f4ef99e5bb5db4e6209085acccf8219a236374f11774a3476515b05992d35e8b838bc5917c053b246ea93a2630efe8eeaaba888998b2dbbe6a0ace2c75f0223b650f470e1dce28ef7ef4b81f6423f99010001	\\x4aa03c5faace40a606ba329f093a5de5afbe7cd3db6edc06dbbc9311e65b60c194637655299f06d21c62e9e21645a60acfe0a5a1b4976f3147d83b7ce7c7c502	1667560599000000	1668165399000000	1731237399000000	1825845399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
250	\\x2202209126839c6aca514a31f16677c36fe9acd23f4dc39b544de242d6a81a3b0f1d2bd8a4be525f1e67584160a7babd1c82d6812dd4428b923cfecc8e2179af	1	0	\\x000000010000000000800003eb2f5d9db070f7754c59469a3f339cacaafe22997e193208e8467d17e52f5b09f7996dbd4513357a22894984e3e4c24a68f7cbec99af4e5bb940d15b3971d6a3dd1108bdd68db4f89e27ec1058d5d3ffd1f019fc9e95eb540072eba1631e23a4929f02cdf0df26000d9286ca811d2d526035ce9f6b53422680f9ed329415a22b010001	\\xbfed8666ebb8bb065a4e9bcc5314d297813fdf5e3264c2ab438304094ab6416106deab061b8bc6e14cd3454c312e4881bfa1a0ccec47707420d48b7104f8c00e	1674210099000000	1674814899000000	1737886899000000	1832494899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
251	\\x24763d87faec1d64a339aa3bee7287c627091e23b2c4cf70b8f5934e907cea19cd41cb8b958d3abe832fe831c2700ec56fded9619f28bcda7617556e4b8ec20f	1	0	\\x000000010000000000800003cdc1d69a897f6f374e8727abeeb2d30a9f9b6e336bed5fdd4a2d32469730e1e5d209a6a400637a8ecd90e2dfe5b9e3de41a7c79a86cf281cd0dcdff9781d7ed424ad3db5a528a1f33b7741fc0dd1572b72cf6a39f67bdd29cfe29e02ff6cfb40a8cee13d88da623ce319dc1647e65c33b6e6890591bb25d1f4340596684c5f45010001	\\x1e2ed9aa76f3eea16c35645ca61f9b97b0f0d94a6a5650f2d14b5ad0f72fde1f6559a9f1c4df6f5826e23e17ebe8a6a124dab11760a58f4aaa138f6ef7b64e0b	1676628099000000	1677232899000000	1740304899000000	1834912899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x28f2051a4ff6ae29f63cd8007902a72e547dc4d1380558ce5426885118ddeb315a267162c47945a556e158268b46e8fd537067d4eab895025f3bb92b4917414d	1	0	\\x000000010000000000800003c917a39b24f1620d3526d58cdc0defa49cc99cbc1a03424e66f9ce8f0c209ef7e555f0fdeb4f65b45b42dfc5d49c0b918f29b6447e1b86e55f742da1b316f92699c8993fa8f7453a07a522098130d14a9159876f51b49ca8d04f78ee46d3148d2bd8f85429a7c2f9e7d92c76c8a0baf9c2017fbed7645cdcd1c4be408488ff81010001	\\xaf4dadd10e00e5e43a3074dd4fdf47a97355d0e525feea6b4e17e8c37320eb2b8792030f77fb77e7e9c5d66147bec2706aea9d770cd7d822f03420cd17cda107	1662120099000000	1662724899000000	1725796899000000	1820404899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
253	\\x2816507de6cd27445a5fc3a7ac1714322ddb1ae7fa7ed949364fc23185fe117bc15ba9e3d7d445c8ed0167791a878e399c5622283e1b1be4855b8a0e582891dd	1	0	\\x000000010000000000800003c7132824553859f8cba9861dbc442ef1b2fefbb98469e028d900237f03302dec261528059443c10539cbc992a592c37fb4a8900c7981d1825913212d409b8222b2035cee8a174039f4954a89596270fd85473df1bde27763bea1d7a5b59f7979cef23a99d463dffe5015429f80aaa1a86c4ffb38ee8a8323e7d1dfc03b5e3455010001	\\xda01bb28a48c5395ea6c5b3f67fab58921774c20a197362a2d77bd5a492b8f7b8aec418d3b7369fbeec6773a40ca22234fe8cf639f996afea4b5083c8037870a	1648216599000000	1648821399000000	1711893399000000	1806501399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x286a42042f25b3fb0de70b492840a88c86568624dcb2c6df6c53357f0162cc92a1a8962c4c45296b5e1f449cb70742a62236bf79463c30f3d0246b5d00a83be4	1	0	\\x000000010000000000800003b7c7a4d5dbcdd8965891c661a4efd061c89def14de0ae8089b2813cb02d55795a27b148c70be1073005e20095a41ddf8d2d7ec4538459d014dab8f5f5432e533c12ea34944fd9f373ce12ca4ed0ecfbeeee37fdf5b1db55dc3ab8a03a439246a9160bc493b6b6178e10f9e5e8a4eba058d9bda73849f93c894d2c9419e62d8d3010001	\\x443b4aac82dd5455f919ec8c2c65aad000c8dd96bb1afb61372a47a9779a99013eb0aed744fc0f6ecccdd4e3866364573f04a8bf935f9c6976f7c9db4e40e002	1670583099000000	1671187899000000	1734259899000000	1828867899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
255	\\x2e0627434077e8f2e6c2d8b6384f285548f68337b0bf13d7e557e344675537a36dd929eb7ad28f0a4c0b34f9e767db9102ee2695fdef534964f5f7f654a1ae8f	1	0	\\x000000010000000000800003a814f2dd3c3a6e44070aa170ec5064bca1c45b6aba7be8979014ce9161439fed4785d8b61fb8cccce87d4ea66060a12d7a5fc56e0ed9c0adcc9987de4e23382b420286fb1c24abd43f02f194d9cf9ab44295c16e449e47fab1a97c92237a2411acf76c160cebcc94cbe0a70985293526d39e1cdd65318dd248114f3691f46cff010001	\\x047c136a0d1273a102866af42953f47e22a1bbb57109d206bb6b3e3040ead3d7f17b69b937115af5542723b398d77c0a629ca4f0a0284fb6e50a12caab154100	1660306599000000	1660911399000000	1723983399000000	1818591399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x306e3c45365ecc4f3f0a6e055fd7421034eae646d6d0e166fed1047a08f2e150d9dc6dd2c1343834fe8d009e3148e520b13623441f38e0926ef39700600613b5	1	0	\\x000000010000000000800003db876eb135d52fd487b4aa8c51f33f2807d441994e29a507fe50e8cca1669bd084a3ddcf8c5b3d50221d3bceca0745352e7e0fec5e82ba9fc66c27d99e8bc2e43ac285ce9724ef80c4bd31c5e323018b45c93cf5c4652281949f53bb0ac8cdac1c8c98877c3b66e68b76727a5d113a5e9474224b267f5c9b1c6f9fe51b1c103f010001	\\x4f2204e7b74663fa55721811667f58b97802e2a641f630dc984f633ea4142a4ed22b603dfa4d7cd05006b668a9d21a509da0712e6f034fe8e0d306a43ea4ca0e	1658493099000000	1659097899000000	1722169899000000	1816777899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
257	\\x30b6be157429ba487077018b953fc6230b6dc8d09bd5a89cc1cec57e391128dfeba1506c82ae6aae02c1db0af6f307c6df76c3791b9dfe2d70ac2184458cb1be	1	0	\\x000000010000000000800003ae51c7dacd6e403fee37551d3d4f58d92e13999c5a80f6af1e5797377850dc351ec724ab72d53eb450e7009ba4f05ac2d711879284137d907902edb0b24e1f9338a07c327dfef27ac4ebaab877b434a5cb3e8e99dd2c2fb4f274a002e8f27c50cd0411218c41e910683e6e07d2078acebb8413a90b0b300d3c501bb90fe1361d010001	\\x45fa543d4e9ad90f7472dada09ecab18aa8fb24736bf4ee1a4d41d3123081b9c33fe4ff4dd77fc6336be4f756f0c192c5acbef05f9e35578d9313357a86b4100	1666351599000000	1666956399000000	1730028399000000	1824636399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x32129c50799afefa8233b91162856b401a104070adbbf5ec470daba3a4d327efcf837dda0079ecd74ed6344a754723370045be88dd7710ae59482716fd7e2271	1	0	\\x000000010000000000800003b757618122f31b01ee33b914188fa5dec3ba756925afcfc64ff87f70500fb186c5376413b1fbab45f8b23a6e259477046dcd56bb0f915a3a6a865f1597eb5222e599aa606fcc2f84e6307d3475630c48efce8f86c6818c0804450492135d4fb2d9270b1ad66451d447f76878d9eb5e157f9a3f096c23a836e82f9972134ab1d1010001	\\x0b606c757052f3a281824b7e1c59bbddd440e72b5768e00c76dd29559fed044ff739e4cbb114dafc676e15675bf02292ad33303391719428ab94be0883a35d0d	1664538099000000	1665142899000000	1728214899000000	1822822899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x33a6253614e33ec8277a9fb86e8d5d5bea8eb4032e22e1a0996333d9566fdcfb0c33e9ae0d2f3dfe7c5eae67c59336b1b21acc609659db05b031c0a9b99d17c7	1	0	\\x0000000100000000008000039636029dd3c4e1d0514b6590334229dec3133e570df7e87bfadc8c4a19eeaaf83f9cf691fc30a38fea52ebadd2adf708a018b35dcf431af2e91f9029a72f4c534d702e3e9a00e1aaa696947fecd7b24c151868b8fd470f970d4301ce51118f7d3b58c34ab57bc10bbbf3700ee2f871e93f4eeff5b5766af730fce2b4975c0d4f010001	\\x52842879a8de17c724a2d7187fb109c3ca76e353ff0ee285d5429f65663314adeac58723c7e79447f4bf1717fbfe1844af14eec71ade996ebd76250b17b1c40c	1651239099000000	1651843899000000	1714915899000000	1809523899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
260	\\x358e385ab201c2c5abef93fe7b7f3ae9d07947e657262140c19cbed428f44abad36e3110dbaf7fccc4d2d62283996da3d5f938b1fe2931811c1a515279feb492	1	0	\\x000000010000000000800003d753169c777f8736acb805b5154efad8fa6f8b8f6faa817644484c6463d2407feeaefb529506d74eefa1195525f92cbf34367fcdde473238988f25e16b3e41f83f47b39503180df79dbbcea80d427c61a9be1601c1c917fcbd2ced82a4acce202eb6775e6dfa4e0655fb01b13c65efa9b6c7b93a6933a6b62047464ab425b357010001	\\xa256acf3e6897953c0c064fdc264921eb6863ac70c6cd02109107bb5a1a93bb91438adb8b815f2d20f0deaa5cf99934274e909f02d1c66ea02563e1adc0bc908	1661515599000000	1662120399000000	1725192399000000	1819800399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
261	\\x365657282e337ee3c0d7d9aa4d07c0b129442ede68b5052d225c757186314608e1b7c04977a0ce5ba20b698c8f8784b8a9f62e72445972a9768aea032f34c08d	1	0	\\x000000010000000000800003e664c77e6c21db5c32784610d93dfdb2e262412dc0da3d2b8c7b709977800dc7d295000c508bb5a235c0b37b4561ce086b5b6dfa9fdc9bb92cb1cef1d0b9a6efd818a4264f8966cd31f9886d4c19266ae2ced3b5cbec417f5ba5899c2221d009289a396be624f93b44109af047d955bf888c20b54357b6dfe1288a2d0479f2c5010001	\\xafaa7efcb4b2e4028d5e3b68585404e7de9de23a7c34c4ee02fd8c38ce85e724c045021eeafea35f02da1b941d0559e5c96fdccf8966b47130aa825de49af80b	1650634599000000	1651239399000000	1714311399000000	1808919399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
262	\\x377290ce1f2d4656faac7bb59c7a69e9697e47740e438d04bae78d151408e713ff63092ee156f523a6b5de5d9eb921ad00b9764191a52eddc0fbf00187cb0b0c	1	0	\\x000000010000000000800003a7898b81594048471709ec91d3cf86c414af1653178b7b3453c355da5021234ca95c1084315b284aaa64cd6ae529ba7aa8625403ea670275b1f3487a128f2cf43328cec69aeb2811f958229f832c832418ad4bef45264372d63ad270db0b635c4d9d567c400c21b609d4c90a214d58bb609ccd52101e64e412199d59ab8da7d3010001	\\x0ac154895aa1c75c405fa7f79d80a90183563921a66311bee1409890eac13019b6e1f7e3f68362b77286fc8ecaa587e95b86711c435ac3c721156f2d2de3500d	1653052599000000	1653657399000000	1716729399000000	1811337399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x38d6639688c0f2208b345e244be203794665a3a257f9b64e8f141c90b39313a820a5d359b8fdae2610e21477728d46d7b70c637654d4216553c7ccdc85fbcadf	1	0	\\x000000010000000000800003ac8bde77e5eed79d5b93b2948f5216c4eddb7e21e072c074db633adbfdbacf5809b6c75a4f014317bf23373c4319b244774bba3dfbfdd20e1c28ac43c56fb7db655604f37a832e8689a3df64a2ff075e037d0da58a312a84f1071511e27626702df0e8954e7d630823f7b76da68bdf2c605972ff7adb01f778f56bbe16ff007d010001	\\xbc7c524dc7f45b570fff99860b7d68cfb138ba9bd581085a711fc9f0c21ed2a55b61d2671989fa5e06a1fe525347b5603e079bebaac051e92e5dc181a7e3b108	1668769599000000	1669374399000000	1732446399000000	1827054399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
264	\\x3c9e889ba4c6ea94486ecd6206f3669fa41539348ae13dd3a0c29d2d2b6e2a7dbabf7979ef532b1c2ee81f1e132bac2406e9faaca5f49374534690362d60b4f8	1	0	\\x000000010000000000800003d5c27a5ae1222475130f73d4d9a1d17187d9b601cff15c409c50f979baa5c0aa435d19e8385639709c5b3ccad7ae326db8419986eb978f6b6f60b8b9c55f62149ade047e4706c554f3c0ca0f2c4c80c03bb9dd7ce9979a5a937f7d12b45b69eec2ccf82c1a030a6979f6eb3a171fae28df868f5d3ed0374943ef15eb046439e9010001	\\x6b2e1a2d29f375de610ba9859d2cebf7a402f41926f3a8f37ffaecbf70b472d50ae5558a221ab59d7276890494105de01f67d57a25f1ec116e7512a0ac9aac0f	1650030099000000	1650634899000000	1713706899000000	1808314899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x414e8082039eb2b67b28404cbe21cc53c67cfbb5f3f70f473eb2b1d2b06c857bd71fc98b87c6adb7669ad6bc6e6b69d2c46f01bca2c5e2038fb55968efb95ef1	1	0	\\x000000010000000000800003dbcd59d7f17f94f40134d896a8283fc7a6602ec3aab117cddb1eb738c3119f84f4b6339f1a21a66e7ba76b4bcf971e5f8df4f3e53f61fe9fa654477d9d05bea512b44c14004372d53369a2adcf23795fd787179f7b5453dfc9051cd3ce6ff4d751d4fb6e23da2866bb8a8c453589ada8bf557ba3f1048a6978ffc81a8e7e6679010001	\\x686b4a4d0c31db3e0ac67b569f7edee8837749b3813e387bedf9646a0f339c06d464ab0826c4dc55ef2d715a1b4c74f982243e70f04788a2fba447133763e509	1650634599000000	1651239399000000	1714311399000000	1808919399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x479656b55289dd7269b258a21a2b27bc1611febce9c2279a41cee10f0ec3cd9f48a2c5655865bb3d9c79adb1d37848a3ce3e64a8cb5b71fa41120eb35568716e	1	0	\\x000000010000000000800003c2e81e5b352ffd4feaa15615d2c7f23b86aef81fa52c15790508bb9b78e7b01d64c630c820874092c16bc93a1c5a6e2bf36a341853fd5ca8242598797969981613f488b1ccc91459cad629e85ba2f0fdd6c1d36523f079e8033af37ffe8b471d8e28aa25d7fb49c0c38421a4ebac7d7de7e3201a1fce08b14576b148ff79cd39010001	\\x16f8e795e1d6e75345b097b1bb296c4033dc3ca410d7a1f787e2c996ec912f0b1be47923f3f01ad3a71adb4f6e64e3013f3ce84cbac0ceb36d797b5938bcce09	1648216599000000	1648821399000000	1711893399000000	1806501399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
267	\\x4bde6348b94aedcde66bdfad4f51253ab759534f3e49a5965874b4c0ab39da3b2d7d46ca084a0f9b352f58963e31484302c0dc5632e836120d515d8d1b383d71	1	0	\\x000000010000000000800003bd28eeacd28dd286095d3ccf507264f9dc9e968219a219863203e1de751a52ebf771b7a32f154cff414047e80bb46a112dfad43e8829eb7e588c488fa3a4342a62fed4669c3786ae84c04e6e292eee62c73ced1c5a1d5275047e29b371df851c1147eb55c2a9bc7496da851abcd290d447d7add5501faf8d14b8c93292684053010001	\\x95126b44fd10b2853c5d2f969b2090cd6929e19ebb2f64183117f108cf883dadf463d19f19a2276dbd53f12e577c37f36fc3742828425a852a03dc32e545c909	1657284099000000	1657888899000000	1720960899000000	1815568899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x5026402142f6dd6491199155500acfed4213dc85d1a886b542599d5aff5f510ca5a754deb6c7c8a1cbd0c2aa79bb61b248e5cf9786d878003dd18e1ed618f31a	1	0	\\x000000010000000000800003d5748838fbcacdddd6f02ccb62b3ec5e6a48e13491d583c5a3b7f7e7241c39f7c766c24f6127eb60e74598f497e4c104b537450397075e6936864b8e3d4753aa8874974d1eec10ced7a050ab791af5fa3424d153f418a72e1ada27147434f33f48699b446f243e05219f7abe95a497ebd969fb8c87f2ca1d961875a09768b1c1010001	\\x9408dca4348897b41cf67cfcdaf0ff46c5d07d77c0742634608dee452fc637c4af16b9cb4b9ae4621a4990b3e963d7a82ba073acca4eb676aa138ce43484f505	1669374099000000	1669978899000000	1733050899000000	1827658899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x551a5cda22b75f4eb338e6e660ff12feef28410f6450c0a9a0295359939cd4d66a0a1ddfed9ae9121707b7527b8ff178e2a4f36dbb55d31dd226dd8a8b1236c9	1	0	\\x000000010000000000800003b536e4d65ea84df6807c94d04650d4a7f59f70a3afedee8f00a1f8943854e3a83c7911b633584e39e5febbdfbda9cac5f6f4be636a092319c2f2c4631bf79f9cac45b7fa20e1c1bbc410b258fd08469c73b2ef3a637c59d4016195fdfc99db8fc3550e34779bf2a60bce507c510c0fad264c1dcd4e391f5cacc70dd3df0fe957010001	\\x6ceb39aa3a5689b5365be570e983a5a37d603302e752f615ec135881479e7356841e71368c955dc116a44b63b7be4a17511ee941dfd2065f7ea9c6514c467802	1668769599000000	1669374399000000	1732446399000000	1827054399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
270	\\x552eb72cbea2e1b0c40d971f88cfaf581b669d4426eeb53ae53c47162304e0e3e674caf5ddb2e8aefc084c751b3671468618f187854adaf96336eecfb4d1a449	1	0	\\x000000010000000000800003a66a453b71cdadd8ff28544c7c88c23722b191198624ae09bdfd36b60e0b3dbd712f8e035115bd622e3ffe480a42a378b895b258cdf7801ea2a52481b9947a1ee6abef33f159ec450012aa281b1e5174d113e5898bcbac73f9592ae5d5108fd9c1201ff7104e5c370c90c238d3de3c703001e2af4a63820658826c384f533687010001	\\x93835160e6f303d2928db6535d30833faeecf9122cc73ca54ddcc736f8dea21b68a0fede88550a1fce8f5b497984eb4aff0a19461e50dc8146947056518dcd05	1655470599000000	1656075399000000	1719147399000000	1813755399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
271	\\x57ee9b8d88230aa0b6f8366df671db7229154009abe4d8c980e849009ae47a35379b8faa342085934433332ca9cdc12738a995c225d6889286a8b63b3e68d65a	1	0	\\x000000010000000000800003c076b854a98c2744af5811afa9c841dbbca91a101c2e94f1fd309bee523349abf5d6c3e5d49b4fa5460b16d0a93ab7b4dd1a12227015938a7d5f6b71716835ab2e0684859df322c6c88aadaf9f9760ba5d34f8aff38b927be93b6c8279f6be1bda7c61d2e20abe58dcf2c0ec6e1679d27bb33bf0698514d66c5d43c599911583010001	\\x10f0d76c835307b19a412cc2cfe99072e4fa417a64a758d8353c84cd3d4a171fe98800c66cc2c5e1e9e23a76048695e07e0451954dc873c35a4a96642bcbd90f	1677232599000000	1677837399000000	1740909399000000	1835517399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\x5dfe6891a61759263da7de6c7c56ce2595cc51921a53ebc30955949d5d9b54ca42e05b8fbd3f415042612b4c8d648143bcf91f9bd7f8ad6b6f5f883d266e84a8	1	0	\\x000000010000000000800003da6b5974f55fa3b7c9ecc8fd71c5f129d3b785412b61945eb01c9087c756cd539a0bc3258fd04525208a0c1b78a5fa3c5949f3558e6562c99473d6ba889e4b1a956e35dcd723cee1661082d580dd48d9a9be422cc47dc66d51d31c7318409ce8716d0c4cf7906b4f9e41ce3df553040e1982ab2993b16221b23077cbea4c9423010001	\\xee0d34b89735c547e4d60e18c62ad85ac9f3d6587f71f8a88105ccd1b4be59937cb80b8c00bed72a58edd50cafe7c0be7cfe6ce6e6495ade32447862618e7401	1654866099000000	1655470899000000	1718542899000000	1813150899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
273	\\x60c68fcc2c30848dd71db72844f6cc103025c9e9d128146ab1259b43ca7cf74d3ecb59f97953901c92919f16ec1c87c1864824b729d6141cafdfb91bfa5378d2	1	0	\\x000000010000000000800003c428bc38b948637d612a0a574f54b156c159f704323d2647ec22bedb38083856a848cfffcbee4f1abd9efb6da96033adba00bdd68cab95c1dc394dc321eba0f79f2dc208eee74a0422cfc62bd1a3e8027e3155f3c9d834bb5773cfd87ef9c7ff80c777c56943ac67022e3b4758a35489e272834aa49d57d0329b5fb5d3790c05010001	\\xc353f92245e7a2568413ab1c5e27ded6540678c53dbd8204ddceaa847ea36afadbb948e306a537deb29f1b4321493677bf3ee23ce4ab826068a5dd6c90bcd501	1675419099000000	1676023899000000	1739095899000000	1833703899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x61be9f57128ef6e996c4dde22e6770a7c2a2df1e9437e47a157fe78f9191d71369945f8a76acc56aeeebef7f6317bf042ab077681f5ff48e5e1d6a69c2eaa9c5	1	0	\\x000000010000000000800003ed1b4823121a29f51ca20283304d9a2f3dc47568397d410896fd6d7e1ec0c4572bf6ebec380cfd43e3f83db212141bfa9b52045c63779d133fb9c6f57d78bff99cc8a814e213306e8d2f518992c36ff5dc4ccef0d63736dff0bddba127dd1c0d33a6c40a65df838a2c59e8e9d9a6d84a236d43bce85843e52a672d3ee3ec293d010001	\\xf0400fb19ee7e7df7429a817c2570b2d17e03baed3eaad94b1ca71b0d6253a6ad18cf8eb8a64c9a66da0f5e16524da0e59460225350b45857176c4752e385107	1669978599000000	1670583399000000	1733655399000000	1828263399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\x637ed5d0eec7a183c2457e72261c5b6e5f9be643d7b63a0c4b9afc5bd9834215e170dc5d9a55ba0635a4afe4dfc023a56fea50415b039e9c81094bed464ba9f4	1	0	\\x000000010000000000800003e576fd0650d660aa5b663ee1f33aaba7f29c0b698a385415d7662d53a39e927f89e3673d4fec4b8bf07d9d1fdbb786787209c96e2dd8787669fcc62e3785f6d76281329f1e3095747e26e9d3845c2d8eaac066f1ac1aaa3fe55c8bc49322e7cc16a7a778567773d351d717ad0cc749c990b2161622518424e2ffc9abdc2ecf11010001	\\xa1891135e8b337810f27f7b84ff1ff647f6a5ea00da0bb3de40441db3d5f194f6e499ec0ac0f664c537656f6841f1fc5bc5c6aa6b0a4fdbff181cb0ba8d66b01	1656075099000000	1656679899000000	1719751899000000	1814359899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
276	\\x6d4a5e72d6b6a1b0c5a968be4cba4064bac994319c14cbb2e6f12e2d751f22045d71e6137e61c296712b241433862dad4007a6dd8fce6cf414f75ff56f27bf2d	1	0	\\x000000010000000000800003bbc37cad84778e4362af1e8db979fae2b9c327a9ecfee9a8f2370b1691a6fab1a9e82826243b03a22a018fb3bb3ed526ad59e88f6712f1cf2491f7c170771210522b82841662c413d58ac1b14a84d5a772aea861af70182c445d8ff93c7630f3eef430f8891ad8a04aa054cbd3b3931ff3114dd75d5f1df6836d4cf5453d843f010001	\\x2e2131952a55a86cf9811d630d6ec9b38be90f0bfeb6f428e09b1ecf255a52eed666a8c5926b2448c3cf806498868324589fb2595961ec9e2a08955381226903	1668769599000000	1669374399000000	1732446399000000	1827054399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
277	\\x6f0e399e4b31dc8d535f4f4532390c2666a5dfe467c8f7cdd91220e7881a592d2659e8e61c422301287a05417da43337702fb4fc2d899676d6319b5a5fda5f8e	1	0	\\x000000010000000000800003cf07c0cf68739b8cfefc23402dcd6b08c43abcc0dd79322ad224dfeb90c4d24dcf9118dfb93635e2346437cb2f3d7b20b7ba7463f2720770e8d59f3e58682e7e9d078d4458fc291693486fceb491591621b8cb4765e0892815d74280ead10389180cd78e33e31776c06cec0b9e2136b766bfcbbe94c85edc50f502d8a4ef289f010001	\\xf8ff86e8ad1d7a1cf9fccfb8b199ac731edc6abc5cc589c49537d91f220c0afac254ffd7dc3794467e795bf7c994d57f90d03914458655c7f7f6f9d1a9dfab0c	1677837099000000	1678441899000000	1741513899000000	1836121899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
278	\\x71aab215b5ea6baa8972685c5dbb53979b7783db3610ee695e4136cda38cb7d105a684b15e2e172a732df0b8c3362142ed40903ba3e7aaee503e96209eed4790	1	0	\\x000000010000000000800003a598a7bdd915a55312852fbcf6d3a4961d85f5677fe16de1edc9fa6c7614ebb9bb947771db22f27036f749e25a5e01f8c51b3c1aa4515143422b06c70f1ee2efedd1173a0d5c6dede9384b5ec40b93bb2f363ab02b3cb6f5e289e146fd5114ae71b65d70745a475f7927e202e4b5ffad9e2cdb8bf966ff920aebf319e774299b010001	\\xfc7561854afa8c56260bf878b1eeb2a6bb10104bab18ae7cd48e2bd67742f23c4736fef3a8e1143e9978398bd6e82653a21fc0b48f954194b7bd63137b5c4a0e	1663933599000000	1664538399000000	1727610399000000	1822218399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
279	\\x723ecb30f5cc827d4fb40bd22e92674262d4d7bce054bdd15f12528c85f54ad9c5f419d56cea97fb02107716419a4da20f637eafe3f1040ba98b163e986a66d4	1	0	\\x000000010000000000800003bdaf466df3dc71675fb5e79b1ba915a7c3be315c1819ea7778aadd23831799188fec5510cd8de632d8cc8a5725e377a5d333fe482bbeae95728d5befd70dd17dd9c7dd2836878af02b526559ff711c374ed0b81b5cf8000949c10268a211a878603cf35c38b45aa81ba95b57ef380395ab2086a9b15a64d6df3239c9546ec909010001	\\x75a7b4af89fb81161d5b5ad4ee04e75c6f812c951fe8035a9d8a77cf185df8432789137a23c22e512067de29777cc8212583600273169ec08b4eccb0ba10c309	1660911099000000	1661515899000000	1724587899000000	1819195899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x74762f8f861fb609a0a288b3d231a2254898248be0da51fd4e0d859d120c843b9db2d54fe58dff2df3bcf6c69bb6cd145d33c6ddca8aec51285083d4d9989aa7	1	0	\\x000000010000000000800003bf2aa111cbd30d5b55fe8541849f177cc1e1fe27ad16bf82cd68930e52fe80bedbf4600a6b6fa753c0abf98272b3bfcf218bc0fba8f79e4b7b783fa844337810b8411bef1a5d0f2e0a945d8d13bef4dba7b0edead9ff9da3c996283aef1d6efd4fdb19f962708037d29f3f25e58596512ab3b5da9b798fe29cfd24662e5eae33010001	\\xb2126ca642e0c315017072fe2252c067014723aa7e34839eac13fd8f3a93531039a96365fcc7b516dd48b6ba12dd9865ed064f18d894ed34190108464cfe6f04	1657888599000000	1658493399000000	1721565399000000	1816173399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\x77a652c881dca52da3d17f6cf0252883c0f10fcdd9a0852e0e024a42d0dc8a32abcd20f402eb0cc19e7f0757d927d7a7250ee7daeadf561d553de2984a142276	1	0	\\x0000000100000000008000039fcca92887f433671670b6b08d4d32c30e42644e9b678c434b4327e9ccc1c1d32b511326beeef673455d2a638ee8b8c52c5e3a53424736254bea974b03dd95bd721cfcff908b3fb9bcd1b22e8cfa6931e0c76874195163aecd4c060e2cd448cd2a065928fd744a20b7ff6fe7ec9249e983db33ca443ac7aaaa7be015fc100c31010001	\\xc9bc07bbdf9e0bcbabfc957102b07f0b25ab64412daa0808405f175fbd7ded5a6ea424dbb95adc1fa6d89b4ecf8b7939c233e5d32b927697d7de369ab5b78b0c	1656679599000000	1657284399000000	1720356399000000	1814964399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
282	\\x77b2e06d11c18f25c8af91943740c882e8e6070ea266b9d390a7581bd902915fee23f9ecf2844b66b005cef696e3578750729b9a6b49832b0d6f12a0ac1ef378	1	0	\\x000000010000000000800003e4b3fe91c0f885d43f653ad34ca22c5c1f300f8cc3198e5514490d72804a69069de447a3924cb5c422ba74363657a4d79e09ba9e434676db3f635dcaa2940a40dce772245dc6b82e0c1ea6420a82ffca883b2823964d5de0a16aa8c1f953897b1491bc29a08d04cda8821834e7cb3341f4f11deb48fc7f1f90523149a196087b010001	\\x0a49ee5848f5775ddc46025e9feb11c5db3588c8cbb4b2f5186265243f2fa6652c469c5a779e08c7847bac11a58271899a01d60d2b6924380999de2f1d24af05	1654261599000000	1654866399000000	1717938399000000	1812546399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\x7ca2ab5fe3979a2b2db66902c383c201830f8f9cb6788a6966974be0ae6a183991a9fe1cf9ad1d52ba92450730f2d8d6a70b3b92b9c5b74d176d948bf154ea2b	1	0	\\x000000010000000000800003e64fd58ef3e9c0b8984c938ca7f215c1f13111f7b4f81ac41a7489fbcc79187f5b159556af00b488b66e513ebbbf71420cb304d4d7c06a2c1c98e9813ce3938f96e0313610681fbb685be1c7e2a881a10c6acdd3c67f5f8b415e975c278e8a68a95e35264efcd7b203fdf05a5feb5aa3ff6581daefd871ff43a2817c344b3a89010001	\\x24844b632c583c195d9b1d9098ada4c7872ddeb300429b940cdcf6004d504fe9b6939bfa409f78a12d5cf7bab49af7c0f67c03a95ba2ca49552ecd2d24c54b0a	1674814599000000	1675419399000000	1738491399000000	1833099399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\x8012fcbdf2883c59abd633330eeda1352dfca8b78b7c5204b533dbd2c95c82937f45a1c7da708b6061f5802b5b4e7538d824d51358dc0f7c44e725903b667a85	1	0	\\x000000010000000000800003c57d53a9315e3669428d522ecb701089dd2d8be2135c31befbe68a588f7e3deada3feaab942a017ffe8b849c2dced872ec4914128401762882d98eb4bc8fbfc8b405f67dcc49d26dc5bac17d95194fa18a23c7b187b41095222aa96616351e83a723c61b11b1e3853ab35b5505f713c3d54f6ae5b4b8e4f38aef807af245b32f010001	\\xe76c7213ee2b21bb9be37782542d440099516290c4313bdcba45b24475ee50e60ff1f5e580a3d29d6dff3950c80ba4a1497c5a330c59d8234616a7338c2ad80b	1657284099000000	1657888899000000	1720960899000000	1815568899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
285	\\x825a0cc8d3ffa63a25dd002b2a364748fcc827115ba7672995d0381e5d1d971b186f785372c8a604bb8a53dc307b957ed33657bfb794d56b87c35e2b8f7c2d39	1	0	\\x000000010000000000800003cbfa47d1603915b41193d10231cdd01faa5885e929a18966b3dc0cb22ce40247e23990e5b1cde7c596219e6e0f9b4ab7429c504fa9ba8d149c7c02d8c1e72e1e7e5bf6d66ee810bac99ef816a2996580c0c1b98b337250a2daf5b967f277ffca4d6deb3c5004dcddd6d85a7272590d5e7f2df8484e1e9fd94804755193c52f19010001	\\x2d798c110b95d7ef22f6845b7c3aba189a3ef4cf73168ecd9fb8e9bb1068f067daa27c9736f075aa8b96a0993bb1c2ed8031d181a40d31a133e77425abea970a	1648821099000000	1649425899000000	1712497899000000	1807105899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
286	\\x8252046a133aaf7ba392003838e9f2ba8b78ba2edc159d8ee7927c5d1273e87fb9b5e171269299a29e82ef2b15763e3d735208c4d4e7d555f0b8bb1f61dac33f	1	0	\\x000000010000000000800003c4d6285c1f356f025cf041b189ae9c59f947d98234eba9a04f173f7c7e71655317289a85cfb9f2b5e2bdd89ac999462ec8f1441ce3c4c219d9942d6c0394f3016006c930f99ee6b249fa458ba5f2df8c6fc3323db989cad9b2fd4e48987a8bb3951288574d49062c38b15ae6e87c212275c3347c6d19e4f9286047396e5e79a1010001	\\xbce7515571921d1879aa361cbb3125dec7f108cbbf5867172cdaeced32491b15454e589a28f04def21f11bdefa120d1968b2979e09bd2411cfb112ad6ba5da05	1661515599000000	1662120399000000	1725192399000000	1819800399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\x83ee5a8006acd9d44f3e1ed9a46c909725f3eea89f694dbddf0c1b4f0119b3645b53d4f269821bff5e30b566b8e08df8c2ff7b0989c0ad2cace069b38f742a0e	1	0	\\x000000010000000000800003bbc9ea44cbd1905779d9dbb72e43b934755c547f60ac937612813d6410c3e3d6c7b0a0e0ab4a7631325fd5db14032f409babca39fd424d7023d3c3930522ca498fe8cb4cd8d94930b76e27b144c52af0086c304bbac1ee1ce22cf5efd2b7e4eb1694a186d61d3a26d8ed874307691211c0bd1854beacc4ddac534dd01ba774d1010001	\\xb02a0f3837c54b5cc3d3a899b3680b7fd616a52e8383a3a0c869ae5d04712654ec241878f9b09863ae6e029dd1feb20b46cc55b0716d5b08de75692353e02e02	1676628099000000	1677232899000000	1740304899000000	1834912899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\x8476e1eb7f46049706cfecd84a78a32c3344efb5a186dcc1ee2bdc9d8a9d9a5dd97878433975ac5a90ba4d5feb98ed0133baa0ff745a8a46bf28711247062178	1	0	\\x000000010000000000800003be170f3927e6dc51484a79120725ee883b0f9a18b8c955c82d141c5e95210c38a6ce1ede2fcd1f2910ff3da9299e730be21c4d318812665eda2c2de7b1470d964d6e49640f55b986ffc6801691ce53d2b82c02be2299bec6896ca6e4345792cd2b23daa28f5ac9cf0157cacbc4aa06304a347fdc424c4b36da458ff6dea45811010001	\\xd62ea1687fa16754374de57bb8f31a9dba4b61361558ba3fbd254c23a721a5302a64a2fb76f33a7a7d46b70214f14352884b6ef0941dbfe092477c36a81ef803	1662120099000000	1662724899000000	1725796899000000	1820404899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
289	\\x86169de0241b2c46ca050e9117ed244f45801770dadb5ca6856cc92012fd112aaf86e658c37439fe3f3d9c0c744df75c2f9379ce27dac50bcac84eb47f27b61a	1	0	\\x000000010000000000800003c2e3a1ebae4f1d87e0169fa32adc84984297827a0fa3856efef2da2f84eef4e30ab3bbb30f2c301e37b9240f29775fbaa255fd8476a7ba551c0c5fcf09b85df7714f1b3c212595c0908cca6dd9cae59b28c7299cff0c419c96c209ce76592e6fe26f009c0e73cccce374a282bd9d4ba9ab3eface8bd5d54e5469b1bcd48157d9010001	\\x43e0271864f92fdb2594d9adddee67e8fbdf1ca7510058558ab0204847ba693a193134d6dbd5ecc5eee69fbebac6533b5e910e02e4032f9937780c99bc87c203	1664538099000000	1665142899000000	1728214899000000	1822822899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
290	\\x88b6a54106a494521eae483476cb613677c58e9b42a9a5c3be1354e9175d37120845a3c276c2d2462912921a55aee0d7331bdfcb71f579d5bba6679a43354061	1	0	\\x000000010000000000800003b82c202018857f4194d63149784421c60077497c888efae3fd111e16f119baa2a7d963169f1d654954c91332bff0e2d1b3fe2bff4ba1dabdd1553b8b8e6887a61fba8cf1da77105955fd42c5b89cce0545e5554273772aaa2a6348aa1623962711c3f363bc018653d2b68f844a0628c56f1244b1d07e6a22556bc45987e083af010001	\\x13987876663ab534cc5fd79072897eb50afaf5013f5681018464af619fe655391aa88169798aea9576a04b8a38d6ab810d883fbf93e7982f21c4c0fcb98df101	1648821099000000	1649425899000000	1712497899000000	1807105899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
291	\\x8ad2f2573c2c90b0a342a4bede8405159db129b0416da38b53cdb3685202857d4a9dd577515d2c3306609a0c25dcc5719dc38102bd1f0512becc8368743f92e2	1	0	\\x000000010000000000800003dd472c46a68d9000c78ee7229a85380f4e95eb3ca2a9d4c83781a6e58db34d503ef3f5c336f7ad4efec725806ecd33b49e2c9c17a4edb7f7bade684227ef74364481e0f4caa55b096ca8427afa23340591456efdb4457b2d092fbf1e9ab70a4b23bd0069a1350731b81ea8fb1a5376e813dd32e62ebf1f62f5490b03da40be2d010001	\\x50fed3f457c18610a99cb932288b315aeb444056cd2ebc7a5e5e5f65928e2c6e20ad67ba6bd7ecae768e49e270cc086631126a3403d3dbfe6246864c7ac57704	1660911099000000	1661515899000000	1724587899000000	1819195899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
292	\\x8beefcc9bfd70a0f79c5fa1cb6162638fb600fab61bc6d606e7a2371a7b3e7f489f66a043b7d932e76b1e3b36200863c0f15834959b800f7ceb7713f92f8e347	1	0	\\x000000010000000000800003bb44c1b0048f16981dcb5acf013a8d2ba59c8e25a933b2767c4f1b753072f8b6c65ce6b2468ac5782dfb5df13c28d262881b6187ce8b6464c71710bf1157bad357e2bb147538ab3349638df0f73173cc33c686bd42493a2786292a93469dcbe091b0123ed79234458ae9b4bcd7b4b49ee2410c532ad27fc87568f574adf3cbb9010001	\\xf56794cc5e3d93b03fce449473ea1c7ae155657f8e74eb8384facaaecb5fc5ad79632a3944c36e029782cf0f9a2dde808753aa09e3cee24b1f9b285144fb2d0c	1659097599000000	1659702399000000	1722774399000000	1817382399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
293	\\x8fae82dcf49943af49074ff2df173f2aa3e0bbffaf29e1f2d99c1a5cdd0f851fe5872c230a583ec356f76f2faa287ae93e8441b152ec8e386a49fb2bdede2b08	1	0	\\x000000010000000000800003cf257bdc6cceae4ee708f01db6879c39d119fb6902e46dac69495c3090b6a5d04f9bd2b12dd61dea6448c6cdaa986fe520a35d3ac8671464e4e081fb70c5e7e14ea150c1d64fd3a94e91dfa430a8aaa596056170e0f3ce3ae5040f8561d9a2cae63c0e515527c6bc14a12f9c9df910edd6b7afb62bff68e246d02f0fb13faf6b010001	\\x35a519bb2077d0f8fdfdcc74be816fa8e3cd0bdfa2b6ac3e06f99bf83936bd85605dac3fba147818a9032368f6458705b4a3eb82ee69f9ced38b810eef529c0b	1653052599000000	1653657399000000	1716729399000000	1811337399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
294	\\x90da74d0c1170f15ff74b0d931e47268ca7c75383be46e00a8a3445f6f2251773bd449a9e64a3cdb9afadcfa48a08a24456eb549dfc88297d6dfe352528db459	1	0	\\x000000010000000000800003b7bd4fece32eeaf0a91ad5a60b163458604382124f1f9c9a96bcddb8c2eca573e62431a9706e000f356adef99846d0744112e8cacbafe996953fed8ec65c0d164df4d00faa74762e646a528efc3c28a1d205a86bde99175fc526f1a4bb26aa5ec44c60c006435b0101eb2aa9708e6840ad4d12b358600479091ef55084baf6fd010001	\\x9983d3bfb49d180a1e37223394913ff9d3930e07b7909ff8d5f68068ce69387a0873566fa4aa2bb561395bea0d8b3d96c95b846bada7cc1f57f8ab3390f04c06	1676023599000000	1676628399000000	1739700399000000	1834308399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
295	\\x91c2dd4465bb27c259afb7f55e7e865be5106346279beaa503f46d21640e7ab447949fb8cc55f632959d2e80afb3befc27ef93322f3114a50daa5f58fbb9be75	1	0	\\x000000010000000000800003be357f940d435771ad72f2678beb7be8d08f3f00c38747c56dc1413d6756450df51836ed2ed0b4a4e49219c62e72f34ad16f176ce35307a54a91b5aebada2349a7e5108d2b151276d35dd636311e290ab257f6d303604b96ad932c6729a3ad2802ceb7e6ba67b66b86d759524837b0c6b9042112add026d93b0d8261a1b49b6d010001	\\x824c7719997584d50fa1f858a13ac1da32aa089b44801d5d15769e737ecf8c925529d6fd94fbbe48d7c0c933ecbde7e7bb756bfdc7fe91d7bf29ebaa8aa1d609	1663933599000000	1664538399000000	1727610399000000	1822218399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
296	\\x920647a32a6dcf865bf54a3476adb5b1fbc06bdd69b9a571e6012facda57cd68bdfbb4546bf794827c01725969b30754e45527d1984e8de125032216b368e641	1	0	\\x000000010000000000800003b98f35d8238e332cbb6fde6b77b0f1a089d704a2bfe6bcbbc25a1969ce3594bc5d756eaa3f88b34b267fc4ecffc8c3d1dad10b4c8a8c4bffdc59400ec1ea6ff1ee8b747b41ceba6022dc2fa0ec8d1c851b552bd3e60acfd5b3b4352f1b1b40ed96ebf7f9450975894f55a1aabc50babf774bffcd6a49bc115c27224d82c1998f010001	\\x493235c58c15f34e73caa9b9bfcd1f0366df858597e05180e3d21f6663fe3d08621f611d498bae663114f73131cde61777b38b177422e784fb5966a657716a00	1648216599000000	1648821399000000	1711893399000000	1806501399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
297	\\x9bfee9d8f9f95dbd171d80fc5c2d19de9d6d82acd622cb64b9cbd7902cfefda2c16bd8f8fa458de3eebfa8d3a4b9f2d35936feae3f726b9b58920f92850df12c	1	0	\\x000000010000000000800003b3558a235fd641494f7c8b4018f238f84f95718a81eb2e05c07359d87432bc6276af3555e0127fc9b87a57f7252e1164f52d536e52445b9386388227cc7245685ad0aba981214c5e84320b12e9296cea918140fc75fb7a9ab9ee46a6ec1beaf2fde2ba1242cba51d9dc28631ad5de831233463bae136c04209fa5e9344e173d5010001	\\xa4ff609f669b0f701b9f4cca1c958c9223efe8a5c7dd4dbc20ef7caddda758fa1240c26d5a5f7eed08a4ac3a9a761bcbc3b4b7ca1d11d1e91926ae646053f907	1668165099000000	1668769899000000	1731841899000000	1826449899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\x9be28a543895ff8b10c240266e2ebd5b0f4ea6a44ee43307fa338007ec22d2264bdde6a08cb068d815f2894aed2bde5e5c2d647d96a6bd1192ca512489ec482d	1	0	\\x000000010000000000800003b5549f9f4e00da693ca298c0fe9c8f836d72420f2a0e4367d342796ec533f218281df5ca37bd4252a587a858509d25843f9c2fd1501b90b95c360bed95c6b5e7085223e4bfff0d6f0dd16145512bbb33727107178b3ac136437dbd45b2e0b3bc25c7671ca19eb83674ebed363de1d5c39004d67bef884b8e3ef8202972793f99010001	\\x195a68059c75206f50e7e5212fb60ec6c8f4a088e7a272104a3c88dd6dc2e4a10e7dec07b5ad437ba13f14dcb04a400342c4bd1c20b4711a424b583ed50c9008	1662120099000000	1662724899000000	1725796899000000	1820404899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
299	\\xa17690180224fbffc94e1b784d81ee98b75d5dad01f7e31fdd80e36715051dd51b70661e67c039f308bf860088983da8494926b09199cf0a7e93c7e2baa63ace	1	0	\\x000000010000000000800003ece9f4a7b90fff45794b7d2f2beae6f9931fcba8b3d71fa2fcd99b2652a59694f165e2f68ae775e7e415fd5dd499fb25f6d7fff5eb4a971fea02a1f78eaaf94b95321680cf6bb9418d46fc57b4d81b4f5fa838bb58fd6032e6e05b223a41acc4292ae9e9f79028172bd3d4f0028f4bf6530b4bad8a49ab6084718098085ae749010001	\\xaf53812f9409a3da6618261f0f14e8a5adcd0253881d88d0f94f318e2216434dac6ee8661134cbdf9e6ec236356e84dd7f0fccf0b3cb2d7912d09abe73bddd0a	1657888599000000	1658493399000000	1721565399000000	1816173399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
300	\\xa5b6eec2a4da3314f138181cb5ee7e47bef3ec045b3539b8f1c3d7e0eb758215341fd8a5c3aafc82ad5b5ebe81c2a6c1ccb867f87cb900be37e274b69b6133e5	1	0	\\x000000010000000000800003c031631d4e0e0b2e1fb4e28e01fce13f58397c69e534ac27306a1c23c880f5eaf0bb8eb50dd6565abf29d78455b5b2c78066b29c5fe32dbda7b5901598c1c9a487494168c555e0ecc06b8006fd07c701b070833fd8599464e8c715de6fd07d7959456c6a875fa801f22c98bd40c5c3cee0017bf7855892c59529e841bae0d215010001	\\x0c9a99b8c378b1d95aa245c8a6d79ddf987fb3b2754fb2d1c71c37c5f3856dc71ec7ef0f6f8421d7c9466f6b8a1eb7c8326780565117710bc0ba91f740ab2b0d	1672396599000000	1673001399000000	1736073399000000	1830681399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
301	\\xac1ebca2d8870274de3351fb175a21c2d4be2b291d0a5d5cd4442459bc29417c213e050bd5fe9546aee85edb7b716ae60a1ca82211ae8713f268373e09d456d1	1	0	\\x000000010000000000800003b35a3b05bf339d861a77dc54297d810fd64dff1a750deb3da236ee18e50c4c85686a30e5de74f0a0b4f05bab5ab96e95ccffc61cea4658281f19a1bf57f6d197ae8ef33d0a89515b0e382ca81f066f6df0e5a86eac0e7942a6f54c61df5665767cafe7cd413419912d2e7b310032721e187da2863d8588911b05a41809297f99010001	\\x09d74739eee06fee3b8454cf231fe65260ebcbbdbebf59b13b91b8ca23759067c87fc5af4cdfc833f4178c1e325619004654852ebec24bd46ed8de7806f5d606	1653657099000000	1654261899000000	1717333899000000	1811941899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xaf6293e924b25b2ec69be82a5a9b3cac99d8a9ab07ec97d8437f7bf70f3be3b0c42022a97c58e56c630590d7d5da9559b83341a59e9d9463c18e60128c5feffa	1	0	\\x000000010000000000800003a88ea5312aa0e5142c0e9e73a3c00d6d3f4b69b7e3c040ab054c7f5b475f240e37f40f5b013e0fbb5c6316952ec7639aa637d4b000ec006d82a752c6970bc00341fa0a8d73ecf4b2883ec9e918b68c0a5fd14d28e48d0cebc3fac0beb6336c535b5e39c5a9791073079d5e88e4f8803c89be5d8aad844d127387c2e5f98ad55b010001	\\x4993bd880e101252085f21eec3a96f64e4f022e1fb561be7867d41cdeb958ea250f77d6475b5cec3ff5d93d9728109246df229be3f68ec7b2e0dafe0547d9904	1654866099000000	1655470899000000	1718542899000000	1813150899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xb39e8af3839d17529bf5807bcfe47ba544c3b05757c76e837e53f58eaa5a1d08b4f93945cb645c0da2537035ba84053e3cf21814d6fc192c30e63aa328be25d6	1	0	\\x000000010000000000800003c5ee05ecd585bbecd3ffb4d6c95de0cc85f7a8e9342beffd9b3a014e6c3700c192fef63200ff5a55befc1e5edc4bf45aacb395e4fc1453f86e00aac1e5b2e5535703423fffb527eac240c86bce0bf19234f7b87a47e4d9fe9defc41899ee57fd1a6e523792ebade0dcf460482288ad7608b42464f8a845ab49dd4e94a6ae8f27010001	\\xdc275b74efb3541c77006a17b3f9d93bfbe69701230cec3d1deb4a50d4a5fc4fb82a8abf9f88363aa472095b7b6a045c1f33d5d135ef282c126742438c968a0e	1659097599000000	1659702399000000	1722774399000000	1817382399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
304	\\xb5962841c416325317d3c646cd9779b5821cbd6f163dc727e50516a90915936cf5d05b233fd600ca993382ece340f9339907692d0acbdb125db345795f143a27	1	0	\\x000000010000000000800003c463e37475fa51f8aa25f51173343eec883629e64702488fb24f8a508067c949e692c470b8ff67ffebfa3604d7d9ff98651fbdd74cc93f0afe299386331ae6845fb899454f02fff3ea6979e509e0f9a46b48f6f19311f9cf4ea14371ce6b221f6c4ad39c89a26ca85be78978c6df553f60a4563cbbad53c2719d967d0cc9e4a3010001	\\xfb55cdcb5ee2ab2bdd5088e3229c6b0262ae09c79f50ac0e847da3a3c1cfc7e5c5c1b9d502c7f8f2446fa690c0006ffaa118b65222ac93f0227f97aa2d03700e	1671187599000000	1671792399000000	1734864399000000	1829472399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xba7230b42794bd2074bea137b9732587728794918cff82ca3f4be4a55680cb7f1200b0140664779378d35f9c7c2752927be5eee6ab710ad87534739c3a4753b6	1	0	\\x000000010000000000800003cd83cd785c646ea8746c25f423e164b4335bbeabe0efca8f947648a19bfb4b34448898e5666f94f9f58a0c50907cae4895a8dc147d0a93db5126cbe1c2506ac5a1b082b5d6a0edcc639eb206bde301ed7a1ff27e16ed998011dab3b82269c07636a65368dee7242c2da0512de64bfe501415a1bc754ac4d1e730394dcc23eb1d010001	\\x17e134c0b0e23bfca1145b22b509d5e3764a3bb820a80072ff0f0a5a646266e4aa029cb95fd5ef1deb8ba2beee901c4e5c37b527d01e4a958c8950f2675e010c	1671187599000000	1671792399000000	1734864399000000	1829472399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xbc16847c9a620a4566e00e964b068ad70f94824527679ee778bec42f1f0cd92c2f79d933202857f39b64334449998602162227deb877606aae75308ebd1ebbf9	1	0	\\x00000001000000000080000397ee1f65881f918e9d9bc5957f7f3dbbe189ac59e992f11831bea678b52c8c76b9d7a0cb9660589fd70ac7b11c566720cb60771321c6d11eed59d30a3ea21c04f04dab79a7ce383d1d583528f5c6f721b083b21d2df7d96467f0bdb31c39af6f231ebb319dcfa5e14dbad9707469cac9d55d8fd033cc97e81d6ff5ae8c598601010001	\\x5a0890d9f3f77bb1f276556c7084f227ba17728e932f82cd8d3b76da944bbc685b72bfd271918dbfb843d264b9306c5bd5aba8af75cfa03edda911f4c42c3b03	1649425599000000	1650030399000000	1713102399000000	1807710399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xbdd6c2f22de5740d8358b036f27622b65e001675b404869e9e212a1405e88e7a0652388b279b8f972e1f0ea7dbd07c387020acb76924e61a94ed1931f80630e5	1	0	\\x000000010000000000800003a7ceed838fed87bb0ee7a25abd34c1ac38a6124d471ba106ea3f34ac7551254e3f2c5638a15223bacc6550436ac86017e25c2cda8388b1e670385073761e1df1a40d4cadfda4fb8b458e59733731317f8df267f4e2e8cdabe4a06c29205845b0856c79024a96ef28d5b0192415c790b164725e84086bc2f26526b1cbf69cb3bf010001	\\x180164b0b984b3693ebd546f95e74e702f18de27a58020f0b097077489a4f7115fb687263e288048534bd3cb91826dfe2eb8e1cf45e4e5694a92193478bfa500	1656679599000000	1657284399000000	1720356399000000	1814964399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xbeeea774e0ae94026dc83ec6914d8e2c311f30919777a8c965c56a3fdefd53f10b05b0048349ec8ad13fb0287cf2f253e56c70bd85dfd65a2366c87cc7fd1927	1	0	\\x000000010000000000800003ac5ab5cc8bf626c772dbbba8446466ad8b65a108106242eec33935fe14bc4b1682c0d253ab3b487b01ac62803b1c713734eb987dbac357ec00e4e85685967a8de6698c4ff5ed6561a7a2140bfe6b8c89552a873bb826b1b7100a34fa22a9b0fca45d7d49d3d53cd359373d1752cddff68256e251d05594bf30e6c8ff5a104575010001	\\xa8a57a03b7471182f28a6f6b1b8d2a657c17eb67f4cfd3571e302932f08b72888bcbc35cfca9ecb6e1dfa7f90254cb74e455b93a792e8d2ff75a82673baa7d09	1656075099000000	1656679899000000	1719751899000000	1814359899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
309	\\xc0ae1a7ff0044b69be660d46fab3307878323d4ef0b0e5fc08663cb64df762bb3091f817f2bb394dde48f297dc3568dcfad9a8ca4aefee5f1b989741998858e3	1	0	\\x000000010000000000800003b0749890d703d17cc521d2b26bf926c8a68f6e66a0a10dfd9a22e1a6a20c707b8832d4b2c4c8e1ad4b1e8a19b9b019c095662978e57a8b285a61fd96cd54f70dc6e7b13f4d7bb0ab906df5b3a3e63ffb220bed76a4512fba0cb3dab13edf1daad6200e5902c2031502d8cad2b875a0752543fc866cb774b5295ddc868bee1aa5010001	\\xfa8db0ca420d3ec3a208358f87ded75fd58b61cefcf0b2a2fe555f6b9f8338fed6e47d4d9744452cddc8441f4e51f3308719bbcd19286da7e5e538840b13c408	1673605599000000	1674210399000000	1737282399000000	1831890399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\xc5beac3933209ae99be70197d5952d6badd14b71567f8f5bf064729e57f3732ddaa6846eb8d8e4895c19f4327d4915fd4e63e9a8cc701b10cfab3e8533b0b315	1	0	\\x000000010000000000800003e1e259210cc6c8df5a1bca96db7cf8f7545feca0498b5824edda46dd1bfdcfa443bd4474c881139a7178b07ca09bc67169f16245823ef4ac45e0621a6a9085fe5b165539f4e68cab0fa14197c282fc412762245830f116b5dc40e6897aa59e1b211403837c3d8e0285e016bba3030787d82eaae4d738de5c5ba7a10145b35f25010001	\\xa5407c15da5eb2b655256853ea0c1fa901fc879db825f378b9049ddff7cf0fffe6ad371b8dcde22bedfde5e3884ce17e03d5431d865c74a41ead3a0ddb9a190d	1649425599000000	1650030399000000	1713102399000000	1807710399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xc8f68e7aa86f41d9ff72adee34eecb14950ae920a94d118b9db79d3ab20298ce8ce4240a05f463f5aa4b79ea52895e8aeeb5a4ea2059867053d69b5670af5b9b	1	0	\\x000000010000000000800003f06d1c25a1c19ae021feebd150a3b62339b0999fa9418093953c4391176d0163d05b8d585933b60055bd64e1aa82daf1c704fca57d4ee818ecaf8f890168cb5662d63c145973d173458750c04bfbb93649aa5f802bee2956631633b263531a273b7753bcfb0e536adc030b9fd294c690fd6f93406238c0e9a17a967e7b2f7345010001	\\x7e1949f5b46fe33e54d3fedf5a85d56eb305af94347a84ff1d15ed21cae1b3015074bb54e75e6b476d3a1c4e8bc9696a2464045986a363083332699349d77206	1647612099000000	1648216899000000	1711288899000000	1805896899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
312	\\xc89a806a01d028735bc2a88b5e520356d9cfe2b78dc1119c0e740da786bd5834b909e531083d956f1d0b49d69ae1a0ce498a2e5b6c2bd21a1d7ec529cbce99e5	1	0	\\x000000010000000000800003bd5e44bd5e2f66397bc32d2536af24a717e9f4a25ee94f86913d9bd90352bef28ac834c1356c47dc5d3a337343c1c8837763c92a9cbb6135fb67228741a98b186d74ed952ee5868a7f30bbccff2c37b7887f81887134bc12d908716f75d5f63f1bb4d82b53b3a561cf0abcfeceac889843da190bbd227e5a5060111f3ba67211010001	\\x517ce8f79c5d78f2c791e963ff16212ffe9b942bb8f362567ccf106f166a320ac087ebb6e6301cd2c109a8293d93fdf5fc25ba6fc52068732f3c07a5bcda2d0c	1666956099000000	1667560899000000	1730632899000000	1825240899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
313	\\xc9deb33b56e3f5ed761f49a638512e5ef7547fd1bbb510b4a35c80895293018732eb7dc3aba43e992b67f9c2e21455020686a3029ed346f334ccecae778fea46	1	0	\\x000000010000000000800003cdc2515d5f244d5f1f1616225a145867fd5f2337eac1ef53a31f697691c861b227c14437d1db21fd5bc8d4a962687ac9e8d03206ad9ba9d28f95fee981fa4c122c502c4801f3140632ac143d76dac8344468d564eb8ab41de623dff321eebf64965780985375ad51d7a78a3e86dcf0afb14821a8aeead328e3155452bb0b4d75010001	\\x7776ce22a3db22884e3128b2f2af6cd9b7309f97d10699a13e7aea03d0bc2960758d9a6711c6abe1674268af558c8984ff17db1c79b1a6d5030b6b90ef68c20b	1673001099000000	1673605899000000	1736677899000000	1831285899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
314	\\xca5249a3858cc480159db37843e4a2e85a412b209cf4195cdf7363340e0587a8c38332482f28f32677558b66a4d83b5db68913b8c8a645f7013e13a8086044b9	1	0	\\x000000010000000000800003d7a76c9931fee3cada827fdc3dcd7d4295b6fa4bdd0df81e1dad3930cf0fc28b094d598703e0a58186f3318edb9404f7551d92ac34c11dbc67db36b281c299481d187dbc81457015b9cfe5933284eca528d9eaa0e97ff5654f3160d9a1bc7deacf944554ba4f6417e66cc79822eb723340842ffbd3863ba4f6e34daff94a495d010001	\\xa581444dfbe1db9cd4b5d9070c06195ec93bf9d24922852a8f3f1974c8e16b8f71b5dcce29fc213cd084f8445523b6ea04dd37b3b82f263f6a3a3855e04d7506	1674814599000000	1675419399000000	1738491399000000	1833099399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
315	\\xca1ab29c0fdbf7b9a794d3b12faf4f3c7fb81038378f0e863a383fd6f7739d889ac166e02add48f68008475d295789ffb57b006c25fdde24b17b5633b9d3543b	1	0	\\x000000010000000000800003b602232c10b75a96e36ed32c3765430c309e8739cc17f147d25eda9a43fd4c4ca179832d78e5436a8f4e1729c4bf13442bc39877b25f5a6a5c09c3efbb0832273bf6cfe1274ce1fe61fa1bc13a22a2af248817519f0e8135e80386380842031c0193d12bc098722e2338d2ce8b08f40e37b62f4d8cef49d4bb74541803696721010001	\\x3458e4a5077706a473f3adb6fc86fe042b4f884d85134d2b76f9bd42868929e53053c4462374c7bb63337545cac229f4f0fcf90eb4ff933bed2b53c2276d1d02	1677837099000000	1678441899000000	1741513899000000	1836121899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xcb3aa985f066f20235248e6e02d715fae1544430a07b0c98dce979191ff64b5ba1270874e226d5f9b8836efb91a4458f732f61346f3ab001341aa0bbaf1067d6	1	0	\\x000000010000000000800003d98af434ddafe414ea28fb4ffee66b487873a8f61b9b5494fb1d13954d141a89d71da3e43141debdb281a907b370fcec44d7b89995a427fcd52121e6ef3a4fae22b35dd651e4fed0151958ebb64e385bb5800e9a177b6c8ecd5f3da5edecc11de75b937ec97688f6bae126971bc03df4b06a61080b1525e21d56517324d2f625010001	\\xf10d9659fc3828d6889dd1239a1ac764dce443b8c04c4e0a319866d20c9a8cef3c4a7b70e4c36e7000500d7e4550ce9beb1e378f9110a03f9531f3dfa87bc103	1664538099000000	1665142899000000	1728214899000000	1822822899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xcd3aa8f9172833a03440ecb3fb8474f86f58f037b8476e91e58db7498b9cb4a8364a7289a884748866b898515406834e5f2688b24407c8612a40c88ac6211ecc	1	0	\\x000000010000000000800003dcc82f6bddb3ccbb6f9fbf1bb41c5899b48533bab0a45b5c7713ff26a51df5fad8aedbc391b7d8ad666efd69b04a615cfaf949af4cd43c772be9c9d7c3a6bd908d2f4a8b5221da85fa85f6e56734568207483664e1650551b0912b80c7376e6f87e004b50ef2ea62d28870099619a4118909aee81e03e7ee8596458e67cee92d010001	\\x541d3fc39ffd073df0a4ed84e33cc7e079d556cf91910be1633bf0781e46bc38a9a3c6ef7950060b09c92ce72fd9bdcfd63ad2f895a7a697335bff4d38e5f700	1654866099000000	1655470899000000	1718542899000000	1813150899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xce260cc9811fe28a5044dc4d4fc6bd5a73caaccdd7ac4f16a16514e15510372d34c154d8bb6e916b64c4c128015c394a04ed677b58d44640307de57eff40920e	1	0	\\x000000010000000000800003dfe0e768992708e7881cbf42b3bbcd709634c8180b15a3ab30d4ab9c08e00c5659d1033cb7fb37d7f4a85fb3daae2e08d35c309ffdc8fddbf2e4f720b721a4553f5d931f859bd08ec7111a746f35ae4826057d868667d23d7c5a2ecd3d2488c48e6ff4809677e4f06466819a7433fe7aae7518d241a5463cfcf22ff8b7a5ba5f010001	\\xbcf41086aaeb11c319058a5639efdc4fd107de7960564b02975158edb4364b2f589c5aa225769a4e579dab4322093a366af28fc48c1ff6325eeb2fc335074b0c	1659097599000000	1659702399000000	1722774399000000	1817382399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xd02a15a3bda6b31b7eb900cc15f744f25d915e1475b42e4c6729dbf83712cd7281f61c51e3788440f634eaf85d638175793b9d5192b44764b76ab29d2297a7de	1	0	\\x000000010000000000800003d1a4f92555127610c41da14af024c538cf70cd476695d30064a86c24658759f99520188fbf83a533274d4620a23d92bdcee120097b57d2ca0dcb3af23ea421169a1bc6be5fc91e95273a6722b517bdf2e27e806ccd6af84ceaa8975599ab407fe7c41190a41202e826b6ed0fba81f59a72a0fef82a476106255525e5fb46d459010001	\\x415e17048b8efbaf73fccc511e838077fdc6751319828e194f121aeb97ee3784f6f50c845d24aed20d9ff1fb0358038867c4c30be49568c65535ff5731965306	1674210099000000	1674814899000000	1737886899000000	1832494899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
320	\\xd5c6c211fc6a8abba0e53b760ecd248cf940e5061ec255e9f935b1f3d8d2af1204c213681e6defb6dd619f8ea62c631b490c2fc5079a37fcf8ee8c5b2c3890b9	1	0	\\x000000010000000000800003ce6100a93b1f6912100b3482d92e0a385121d924d309f60ea3954e7f419ee8ad279af2046a34edc77b444033c44b04cc7cdf7c4793ade4e039cf27fe689e96a8a592957cdf57dacb13c8c5b91bc8116d01107891c9679cbcd2e02ed00f7801b326aba63d62d19c5e257f60f0ebfeda533f2a0d2231f460bc1c6ece8b94a42935010001	\\x9af7cb1e6272c2b4b772262401af692141b3d1b16c4849e8f01556516b2242b89e9553c415ae795bfc7107e5e73c06df7096ac840643aeb57cb1c9de3fbdf102	1669978599000000	1670583399000000	1733655399000000	1828263399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
321	\\xd52240b961a51edaeb9de08fdfe29c50e3fb70f7e2f28316ebd9698f85eab063634ff20bac60c4047f96a50db48a1f1a70c9f3f47b6cf46ad222a74855340b94	1	0	\\x000000010000000000800003d2be300d65a257ef99f3dc5591a31b5c74a26275561f6d2989de2eb92ce9b470552a54503cac2dd87c6d5a8f5728f5107e7459045513664791e859131dab483f52fc7dc6e3d19277133a05703de8e170953fbe5b1cd0e19e06ed7def70212074d86811b53c99638d7d88bcdafaee58de2adc5224b1aa2fa4c372993c1cc942cd010001	\\x569575d57102af2335a03ba3d44f4daa5f2a2b9f4f4cc624730555a4ee4b21d56d665f4ecf4ce32495e906ed356105e7f518b35534906603d48637b0c8f0c00c	1653052599000000	1653657399000000	1716729399000000	1811337399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\xd8b6897bf0438a2862c28468c26811430dfd4c4032938e21476adf3e4dcb75ca9bd80c298a152969c7c5dd2a0917c74db2c6d42dce5aeb7fbd77113158976d35	1	0	\\x000000010000000000800003b8d8542e32b7cd016c6a5bbeb56613240e3e647cb4ed09f1fea7e3541dcb9e0c2a688579b374aa5d6497483c405588050c2eaf51009f01859a921cfac1890c38e23d42bc8ff760758cf6fac7f41e014cb1ccd02fb9cf8bf5002b45c38568749d4e75f0b242c24f58e65b2ac48b8040474127e0ced50579069431132704864a77010001	\\xa9b536c85fa7e0ed6da5877b536953c73ccd625e08a12e75e6294d91b907bb761a1a9ac109a1538455c8e84a661aa96116c76791f2d9a557cc99c39b3499dc08	1648216599000000	1648821399000000	1711893399000000	1806501399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
323	\\xd9d2166f9663d118213009fdd9f7211102d32869420e37c07916f381cd155fbc49c9f346d27d2d6238df0f2884fe72f77d5442f9793422fecab6d6eda3304058	1	0	\\x000000010000000000800003c9ddfb0cef2aff40fdc6b6510d21dad959c938e2ec94d0ff75e15a7d3ded5f8cf993b418df239d11cedc9b8fb46911d47af427ce7ae5c0a8d6fa02d5a60d5be8dc2f986998e78e6a4e9015f90f0a17da7874cf3149baf4739b04c868171cef1d524f2eaac62a5ca01713fef25b24bae4db9519e6ab180013f34836f024d89c45010001	\\x8ac72ff2bfda0362f3ee4fe2613947d7d380d881dbf67bbba6e5bb5f7e37d238c6d9e27fff914e71918073fcbd2457128a209cc66021d208ea4188d43dd98b07	1657888599000000	1658493399000000	1721565399000000	1816173399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
324	\\xdb124ddf199b654993e8945fd9ff084badc8935ae945732c37165f1194aa6a1e2b8fddf8978706b2cde92a9177c54f65af4bbbe43b0c4e66d6d367c0b32910eb	1	0	\\x000000010000000000800003de1ba21017725413f2b5a07f6533c0253aa45623716dff4524bca7a0e9ae8c3d9381c66baa13f07e3ff1735d1773ca9abd91785b1d9b502ad4c8859a82bfab2ee869d27c9710bc466fc338d5377dabc58a2476a7f0bbd651e5c698bd23e0e85bb8adb80af0e097e547b99c1d0b784b0ce6493a7538ded4aa16cc760f50342997010001	\\x2638142273c32e29816988eb10ceef87a3a0bf01f6051f231f52f3fbad371d4def7fe8ab2c5298319f0c79487ba473fff6de948801c45bd39ef26355fd6af301	1651843599000000	1652448399000000	1715520399000000	1810128399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\xdc36cde5550ef3db5a0af3df3906d34e022cebb0c2fd263bcb7ddd307ddf4d758a33bd84242a76457199fceda2441534c3ea65b88ed172e9a4a41d4244ec776b	1	0	\\x0000000100000000008000039a2012acb71a2780ba591ee7e8f4901a7e20cf8b6afdfe5476913348df5897bbe8ca10cff4d9611155d48a3b66230ee176832f1b5c634992ada1032d5f7b5ce59145a7a44595a77437876c81aafbf57d885e4eb5e1cd3b1714f620023feca905042fe6438bc796a5346e844bd506c6cc4a4e1fc97e6545ffa1639b6fe66c9693010001	\\xfc09c3699b4f7ecf5824f6d4df9570a65808733df85ed63596fa744c3901407d0b5a57c71b6060dae080b8992ed9640c50d2fd8c46a1d62d72fd7ce6973b400b	1668165099000000	1668769899000000	1731841899000000	1826449899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\xdece545cadfa25f6f3e42f52ad0c1d3c28336b63fde843f2cbbd2942669295e269b6b31a3dff6a8ef8eeb6488626be0d53e86c4c613c5c47b978d7c8d35f4807	1	0	\\x000000010000000000800003cad64d2715b5c4629e609e540ff4ce0c16248f51a1a98b8341b1816e13c5ee90c1a1887d917327ab7f3397dca6862d407ffbddd270bf377bb503a39c4a9dbfffd54106401b595a20534e9c5a85a850ca8d8546ad17bbe3da524ec019730e6a200702ceb20e629ed91113e4a61259d55152014ff7e82a5205c5098f9e70f173dd010001	\\xa65d49467916df497a752478523e5a9e09c9de543f6a081bd2373cba1af4e3e7ca14dd6c705964542f9116e844fa60fb725043654c8923d3d36f10d1d8b74906	1674210099000000	1674814899000000	1737886899000000	1832494899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
327	\\xe6ca70c0effa1a5e54ed44b3996ba5d4b728fc52c8652e2f40d82cc2f49b1801ea5ea65d069fc76c49b877477ee7a71b440e246bfc5754c2edcbf5b35e17b40f	1	0	\\x000000010000000000800003b7fa83150a3f500d702350b2a3b3f879f794a6bcdc62414c4c5445ea5b2371ed0f0d997d11a3fd62c977c4ab509692c40a6acc936aae0a95d43270c690c54b86d0f63efd4dbca6eea8bcf82c86dd35d4a335188cd6006332eaff2276187b224e0bd1f5f4e5fa68eca24c83dc9f82e10e5a123f7c210faf2c115fc5e271474e3d010001	\\x7683daedf05befcc642c74166fa4ab8335d6faea2daf1dab96bfd503fa28d366eda307e1386a0e0bdad112ffba8770abf7876cfd1794c7c396fd8cfb92c08b05	1665747099000000	1666351899000000	1729423899000000	1824031899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
328	\\xe9c6e8a4d5fffb21fe518c32f35676a25944a2ec5cc06fb51b0c3196f8be649f4d218ac6cbdfd9ca6da212fcbab40c4b97865ad9033dce51fee009563652bc82	1	0	\\x000000010000000000800003c9f6116955ec3efcea919cfd28ebd248fb09bd053822afaaa8611e90008ff592e175e9bc323715b20c97069259407812625c1df534fde6a30be312ca8680f0e6d5246df55b3536130fb50ee1e5c2cab70bc9004ae3b977d1be4bc79b4b98ffe33df4a1658094b89023c56462829297cc138ad46bf8270c8664c1ad3b71a8808f010001	\\xe8480e8ed498593c0e9b1ccc061559ae831dd6e98dd2c14bcad7e4689a921c0a6831090b10ad3c0cff26d6a7a78bf0553dc3d34527ca53cb1ecca5e477d54e0e	1658493099000000	1659097899000000	1722169899000000	1816777899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
329	\\xea82bd056dc3caa3e262fcd3eb99eb2950b488672caa275fff8c7c3b8676fabfc8500f0efa682d884b4ed632be70abeccde71813d0eb90214eb0cf735b9d0f68	1	0	\\x000000010000000000800003b031d054bd767649a8eb2cf295e219b8bc338b0eedae844d038d6c625e6daa56ea46bc2204cf2ab8c2408d5da00fadac90cadb0700b7f92e76a90e22793b2c3a2d15a73c6a758ef10d3bfff9bb34d776e5344b4243ca93c7ba21ba2dc14d6d5c646d1e89569aa2d0b7423a9698d692f08979b685f13a931458ef8b0698c4844d010001	\\x17a5828473e4bff834d3e810cc9525fae3dbce35f6ae5987354e8377b5e5954e86f0328757bdbfd63669d0529c120c95b7ebe6481454efa1dad281dd70deae0f	1678441599000000	1679046399000000	1742118399000000	1836726399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
330	\\xea1693ce0470b3e0aa8bf7085b1f31559b1d1c761febb6d32951d3fde7127a106d812fe8595ceb13a3c9352721f6f36cf18c60377d0330fc57cf6d28d7eef3b0	1	0	\\x000000010000000000800003c4c9112e95764522d6eeb0f288f8d6bd5fb602c1423a7d05ffcd57eff0d5c63c18da36bd56a321acf24630acd2f7bba9848b6b35c56f937ae5e528909b87b22ef9e9d0d9a82757866e255d849fb5af2f921b15c8009b8993468ba56618a24a52e0bb58bf6cf2749cbebfd77cde3fa285cf2e0082653f65856663ee9a532ec529010001	\\x8ff38eaec8213152276a192dadd4d35d4f353c254ecc63d61dad47b0e5b28df7e07a793b3574a5ac11ba9dae773b9af09224ef3ba6ef2e53a7023cb0b07c3108	1659097599000000	1659702399000000	1722774399000000	1817382399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
331	\\xeaf6b60849f64f08e42ec20a5d99b230a647abaaefe2110643762b526af14aaed06f934d3712f8c8a251665bef9e40cceab0b75fda8266d1c1a23bc87f4cdae4	1	0	\\x000000010000000000800003beadda817dd08f5dd40cc8a2c3f9d73f1de571f43d9221603661dcdbd6262de424338c61dffa8b20dd122d44abf262873da92b4a9f841374384d91f3c4eb7a47c806b283fc210ff405e8f7fcc59f09114ed2d556b12655de6d445b346e66776df41fe5839470a90294a0e4f4267d0f293f16eee0755bc77d6efd45cc94038651010001	\\x2d4d48525b0a1830b781a113fbca3f291454f9c9ffc1ad3fc470fe8dc468a06e483706595ea573b3fa40396a085abaff44fadc6ca85ae93a6e25eeba90ecb30d	1671187599000000	1671792399000000	1734864399000000	1829472399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\xefea4fa1098b32b465651f57f0594b0199b03d375e952040e06987f6653cd6f322bd456ab43763ce6e6eb2f41689ca2f06e5c2b9a7bd1694216c41e82af08384	1	0	\\x000000010000000000800003d89a5a4c81eedcaebacb732a93987ac53610cfe9b0afcd480a0fefb9fa69a55263b8588b5d6f7e634c618b3ee850d24c1f537a37a9ad2276dd5a274f9555882f71c3f21874eacbcce66691df0ce179a0d3383ef78e357a2e24dd7014a105b1286ecf3775158f0ea7b53e7b0d0c839b67b2e34cf455dbc9dbd00d1752a04b77ed010001	\\x661b3c4a2353900ca19d21fed473bc0cb0792ae386cd55e5554ac360ebbeac381a31f0cc57ab8e37cc749922e1ef66434bab544d02425b38f6f435ec26d7c207	1661515599000000	1662120399000000	1725192399000000	1819800399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
333	\\xf3de8a690cb74b3a4576c12e325388c261bac7ae344c566946b477eda588263bef357a71022406f61cae0e0f0da9684fc0a878968719f61b18b313752561e04a	1	0	\\x000000010000000000800003b8b1880b7d3bc59f70446de442f23717dc3e1fb25a711b89094be4a0efea26a3e74643aafe749f24b27d0db80aa5e576fecc32e193f740448573dbd378a904d3e9a90dd1ade36335c4dab95659f8322e00cb7bcae6e8424e9fff44b94a0735e2d72018a2807cf928a0265ea5a5e9204bb3ce94b78aa3a34c48e9333cb90cdf1d010001	\\xfa45b3ab5cbd6ed86cd762feee2b7daff7f2eac42198324fdc4a303062b79797a1d0dbca7a30d45d2bbea59ff0be31afa496808727742061aad83e2543d2ee00	1670583099000000	1671187899000000	1734259899000000	1828867899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\xf972ff5daea695698e5f66bf007c9aee54bff57986f9019db50c0b94b95799042cc66d350642eb36672262b7d948b5946ac45f26d0472fde580657bc4c24a3cc	1	0	\\x000000010000000000800003c6c0941edd48ad0ca2e6697db94c465dd45dea476103470ed85380fd6a31bce112e20067df0ba1b16b1669aef1c6af7f07e29254a063226945d87c2172048698d70e6ea14b90a875cc784ea73c89f8b5b707f5c263a907f70d120f9bcbf2dfa8a2553387757cb49572f41a96590008b39c0f87ffa951f21f8831eda226099725010001	\\x2328405aa02e058ca6fc101b4143cf4b0d449769c6edb2cc43b07e8199d8ef258017f0d8fd9fa3cc1abdd71462cdd142b8e8768b215a25c2d4535d79f8b81402	1657284099000000	1657888899000000	1720960899000000	1815568899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\xfa4a6d0cc41bf77b0b09293830158e215c5fa5fa5aa2aff73b6a8105f1f8533e53863309647138dd1bb1799a0990e71ad8b64adde3f816b7eb3fd07534e728b0	1	0	\\x000000010000000000800003a159729b01c087eb3dcea87a3afae6260be6a78b3c0557e45c37b36574c32edafab0e012fc323741556c0d5f1beb193c4bb56e1ad6a1627375eceb5a4a7e9f16e372933f853e5a9f81714a7933a690c02aca5dd21ee3fe80ecf393c8e3b0ec27e7c588e4c1013bd234023d7def1a33f2fb98eaa2fe4953c55ed668a6f88db491010001	\\x74a77fb17ff51fc34d463366bd208747816c351b76861e2fdeede04484cb09ecb2fab9a51eaafd3a6425ead72b20347a169c38b145b7a759c7c7d526b2c2a80b	1674814599000000	1675419399000000	1738491399000000	1833099399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
336	\\xfa3eecde008fd842fed90ea0837bc2226c9c4d5ffed5a0ea3befc5c5554b15f30a8faab9b3d4a457a545afc88f171edc66eb20298541dd62f893f5326134075d	1	0	\\x000000010000000000800003daa662046ae0fc778a494c4e497b3cf7b222de3b995d4611d72c2b9f257d86fd39e752e04caf0480a021bc9628e5ed05a4f8a67ddd7f602d65b1329cedf30a63c7afc81c93098739cbe792937be2122807308dcb425ca35523b9c1aa9c0c30b1288cc68fa6c0fb15faa1d3cee76f9f0c585b6d68e1ffff0ab79fe0d63220e9a9010001	\\x772316c711cbf8762c5a7f34069dba87f0cfcb0738c90eb0995344cc82ae77e70ff1c168613895942ee2543013511935d16a7847ac31646971571f1f4042010c	1655470599000000	1656075399000000	1719147399000000	1813755399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
337	\\xfba23ae0add5fdcb59e41dee1a145149be2447594693b880da9ce387d48fc9bde9cf58dee0c2cf456b482e3afa9fc6402351b5694625ea97a48827a4342900bb	1	0	\\x000000010000000000800003d536900b89782a15350867dc3e23498485e3c84d6633ea64e4fb5da798a1bb43b063a6a50d0ebb1b9225c2f95399e2e40d7b8a9baf6c61dd082dbe42fa0e20d425535fc9c8b7d309bbe15c40dc4f9732a6aad42de36fe1aeca6a00cc0542863779dff5dda265fa408fe49a796c274f4868b32a9900be61a3762ace9a8827d34f010001	\\x8d6fea1f960e59d7d0678fe58fc23e2670e059b10d9696b67cc96725509833ab0a19707d0a9474926556e89f927957f6745a0b994aeb666b4932aefcd313ef0d	1673001099000000	1673605899000000	1736677899000000	1831285899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
338	\\xfe0ea7ff1f8b62c49a923fcd4ed2b8a47ceed80bb736bda440426979b436279c6cbc4a76c106e2015a996c3daedd6a7d7d913118f0aa3156e7608a3b530a3047	1	0	\\x000000010000000000800003d89d70ceefa281918387aaf82a3b5f9b8e2e5326d368f849632902d2bc43e946b0932c46dd89b9f4d25a27de37505372538b15156c28c65939c8ba919f33cf645d8a931f70cc565e513c7e923aecc7140111549a007badae70b9bad489404949816d442a214cd64f6e581b53485ac6d55c1bb41251478d15242f9d2ca600cd27010001	\\xfe09e905e58ceb6e3df7970e360799888393a1aa13264794b82191b4ac5107f22f6e22dd11259567ea28f70f90b0b47ddf718833867aa62261cd113f2d46f10c	1651239099000000	1651843899000000	1714915899000000	1809523899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
339	\\x02575158e492394c6e419b5caadadbd7623f67525fe3f4e2072acc8509f18a2970a37d8538869f02af6db0dcf335face6e8b94b3ccf6bea519cba3608a40fbab	1	0	\\x000000010000000000800003ae9889db5252bcb1b6cc511adacb27c2e056bf6ee09411541ad737e9740703daa195fbe61b4fd6408dc4682fbc4d8fe20852dd77633b39e9a1d5015bcabcd3d19c543d498221c70fb7ed68c4454c4ea764f25eb19db36cda5c0a3ca00bd0b463e8af8bb07a94845bd075614157bf1525e0126d72607a720de413983ba38a0737010001	\\x525036acf70512b664402f10bc22df9e56ac13f8efe0f25eccaba857b68ea51769b0c3ec7df2d0717e8efde96696dbe69d112931e880b07658a812787f013e0a	1678441599000000	1679046399000000	1742118399000000	1836726399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x02fb968d1542d69a213e19d339e36bda26d4cc02baaab10c74cd26cd4aae67327140a3a0e943c8779b67e9c67e8e48032c87675e012e974f415a3a9417535bd2	1	0	\\x000000010000000000800003c120a4985adb3a1a1d4be6b670c1dad5b16adc1d381b772ee4c25457aca9e417158b9feffe12b0203daa71151ca129d0f449385d093677b1b4796adca692feede8881c619f03b3951b68200e8882417568b7d31bc7137958f5fc0e353fc1584607ec926227324b328a66aa0c72905222782af5027cc4ffcde5ed8577331533f5010001	\\x5aada76840c4c493ce42f401b5adffe3f788ab4f1885d678f614d7e7b121dce533455b9f6e7edb8570d53e3f1489c8335f8b16064fa604127f6db275839f300e	1662724599000000	1663329399000000	1726401399000000	1821009399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
341	\\x03e7f4eda992cdcf91ca7c9ca0c060d1367a84d4818ba3e6b21fda076246d8b04a4a2a53809a3dc797a305559878823cc1e6f7879b377e3001f8ccb910187673	1	0	\\x000000010000000000800003be95860f4bc0612600ab945fe4aa42d527a2b2f1295af2fe507103b57a0d7527904fe6a0de477ea7727e6ecf605a9b7e712cdf913fdcf14680e4f7b79f353c72ac2ed8252f545c1b47e3748e10c4788a3ddde138d6385fc5fe536ce896ab4b77e5d26155cb69e36b0153c98edccac6632a0cacaba8b8807f29c00feade1d1877010001	\\x3faddf25044e1f455a4c7d14209088098f0e05a7d9926f53288584ed8e6920cf0d1eb1733a0732c5ba1d76ac7a1a6f0aa7f053af9f2bd2c72983b0d3876a0904	1655470599000000	1656075399000000	1719147399000000	1813755399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x03a3b2ae9db9d88c94c8488f4b61b3efa348e53f37a47524867e9d321cf1c25dadedc0494fd79919ebdde0210b67b1449d64a5078bb285441f5674a5d9c55ac3	1	0	\\x000000010000000000800003c092917d726dc8968a5c276e6acb91b03137f3afdd58f07ed4390a5a0289abef80b53683ff9fbb7cbceeb893980844f568059d9d5972186a85b83df97a02bcd101313ac6b167b2ad533a86ba47b005131341523d8c79a3e245057e4451f07cc4a9df8f5dcdfc368574244d7075e2e2e063cbc1a3d769891a19f2d7b38e8ffc3f010001	\\x9e3328efb75b51f36a16fb631ae370824067fd85f928e9dbfa843b0380a0c6d524d49c99b4c9dddaccb34aa5a56a0c63009b81af5c97d95a59b1046e76800702	1658493099000000	1659097899000000	1722169899000000	1816777899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x089fbf26300a3aa09579ab82c3e226e345140a6654473af9c6c9b2c4eb361e6bd50c642449679148ef4aa2944b6b4c7c5abb6aa99c09abaef0eff97e559c919f	1	0	\\x000000010000000000800003bad3e2ea4c49a7f96915229410e5b466335745f03693a4f8e2848a916ab2370013064aea29c1d8daf2ea5c0637bc19fe4850b4e2b56504151cecddefa1280602c1bcc537b23568a5034ab5a20b415fbac1d7f61b0272090e41fbc0432fc34d50781855cc9b72c7adf6918b1edca560126a2fd96d39d2b2f9d1ff38b8e85bb42d010001	\\x97755b6f38a7728bc5f08b4cc4e1a6fba65e05ce1d775e987eab0bcb7b54c817ed2c16e23f696cf0fc62cfa65baca734422d367cc54582b4c6751abd380bea0f	1665142599000000	1665747399000000	1728819399000000	1823427399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
344	\\x087b947813e3c9db03619bc39cbda83dc73cb7a75cd485ddee2df1511a18adfb3e41b5389e222e30a9873fd7b8491adfbbd5052abce1e04f3e8c46919558036c	1	0	\\x000000010000000000800003cb5b27ec101494320b93b17be7dd612035f1a61fac0e4fc96f3eaa8a03f63030ca5baf756da9efc1d12070286fc393a85119e0ae674b6cbd8f1e9aaa0f2fb97a94a21c74d04305393b48c9f672c2060055d0879180e2b27371c4247d9ee8527dd841b0a290cfd0144ba9bf1ff5a4fe62f2d79d53078556086333a417bfbc64ad010001	\\x1d49100f0160b15aa5235553916c649d80ffd41c317d37c6066ab284c0e5fba6a827cba8652c7f67bc24da84b56404d7551740ea7d9c00dea22887b6a186a601	1656679599000000	1657284399000000	1720356399000000	1814964399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
345	\\x0a53cf5639e69907d1f1927539b24cd2b5c27980e0a1b46930c7e96470ca981561c29830a064eec12c73da58f99bad41f5d1a14fb21ff16a2e02126a5c83315e	1	0	\\x000000010000000000800003d43c7a46f9114dbfc8f8dbbfb1688a499a23c7c53d7a8f7332091b467b80eae2abdb24eb2b065a430bcfcc25157cb9c1772c8dee3f2d4d12c94f499a9c5c12b48cb1584198e438b081cb9292f279c1bdf046d69fa573d6a7d60380e9257fc12fdd04b704f9259ac8a66200e9931dbd207812275f0902116419d2ff8f5a57dd97010001	\\xf926bb64dbfaab3e84a8c5eaf9a017a32d484cc4fd32abc1cb36eddd5003d529011d43349386a95a228ab127ecc89bad19f4cf523adbceacd711fe1965e0c800	1657888599000000	1658493399000000	1721565399000000	1816173399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x0ccbf0960d80589996c257c5590a8658c2f6ea093f6e39302f8edd24d019cb0a7aa33a2fff4c016a13936f07d61bed168f3ad10ac2f32c1a3ff940b331a87516	1	0	\\x000000010000000000800003d4f1001c3e9ed51bda5676a91859ca782447ff3e45283422d48b9aed25738a843eef67cb9e97bf9392183c3ad8a4485b17d8c71b4401a9c425ef61d80c4bb9ace67fa5e9468986208c66d4f2b3695eda879468e4ca130164028720172fd9cde380b1bd21f70d5b34b07fe7757bd4e0aea27671e30ba94c08722f87702cd6373d010001	\\x65164e10e2b226355ab535642ac562a3cf31209b8e23d60bf682c186d99f5e9b81c41ca1b0991aba80a5c3ffa64c8eec358dec37694f673c3bf6c3b58be9c50a	1660306599000000	1660911399000000	1723983399000000	1818591399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x117fa05cbdd6b32f1dbf486ffb9ecd9248e96847cbb3a7cd3915ec36c20689223832faa182c38d84f953c87b7266aa3a5dd8d45d3f1caa9343e028afdc62d763	1	0	\\x000000010000000000800003c5d991b0e03ed0d84102d0396c7e2fb6154438b00616be7be332bf8fb253e3c9db48b7918a3273ba4ce05113a92706c5c4666081de1cfbe7c370b726b6cf6fbaf5fb5938877eb1871d4d62e9e32ab29e68be19fa8cb49d2da54b75dfadf971ba7aa643666ef591cb1c974420ee9d6f1e8ab7e7d590f77541b0bc9e4d85041911010001	\\xa59660f71b25934ed60e8e3140583f967aca80ef23f5d754efa38086551aa05eb59521a260c13fed562d629836c7a1cfe0cba144e8262876666e7b0447346804	1649425599000000	1650030399000000	1713102399000000	1807710399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
348	\\x123bc08d8bca79f581341aa817d1deae1bc66c2fce9baafaf5392a2a455dae4245ddf27d7c54ebe5358abec0e99da508c7dbb3deba361ad204cdbe21d0bd9515	1	0	\\x000000010000000000800003cd69552009411f8333a0ed446db0e7b2be83d9ae115833f984c3720e027bd415c61c1e876aa7dca0b695c97eb4ffb794563c4caeb976f1b137970c9a1150141775426ff15a481ae7a243a661158c24c7ac100cd4a82a5972d256fa13ca51de71af573bdc7ca22ebedecde25d401481951e80b46c0f2c6040fdbbfbf9fb93618d010001	\\x93c05517ed6c2229e7bb97f68d2bbc7be0358584345170e81059b1966dc00a79495ef3ed45f7aee029a6a860eb6f3055e8bd5982ae2c1981cce9e0e33d282204	1653052599000000	1653657399000000	1716729399000000	1811337399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
349	\\x1947b1c34b6c18694f1aa2a1c69c1d6429fba23f16f9db9919e0a74bdf17652ed9df4baac136f30aab9a6c7fe96c605762f7b6ac7fdc1a04b8d75d69d7ac44f2	1	0	\\x000000010000000000800003c34f13506f9e01b5423f1aa4e2a2426b394986b05d1a47a75806c010c80d32653032134cd4209b3d9c11c98238842383a4c50d252584a6ade6002ad225a7c7f07ce989bf463be7fd4f5a2ba4b3fc98fb6ee835beb00d9ee22b56415460aacfdc06a9d2ecff99b7de7393148df982872e9f13eac11f681dc92965dbd4b90a1fef010001	\\xdd4d26cfb46408aeadbd70c1d1862e8581715be1d0b000fdbbffac2fc2454b40dfe854409ae3febbd87834824fa87cb286fa866a31e083e75e2e44b39285fe02	1677232599000000	1677837399000000	1740909399000000	1835517399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
350	\\x196f437eca3b09c4b97fe3beacae5c05f3e1e1cc99757a7e13cec5da0dd8c678a15379c1cf3f4d5233fb7200aa5104c8e7e43141314baeac6fb0787941e33e94	1	0	\\x000000010000000000800003c0147303c19b7e3f31395af03a952049eaca8847e9b737e1e4ebcb2f1bcd82391176eaa7d6f243ab56eb7f38894d86c3817ffd07d0c4f43945b36de0746f40a13d542d05ac751bb5a3676e13e23f8fb1d6d20a74e0f5bd050ba6b4a94e3d10bcc189d5edaec80de8e00ac7ae45d5284c9650732dfac7322e0dfb9300194ecaab010001	\\xac7a8b98ceee8368ed0d025285c66c5b4af052f9ab8ee5f7f5308f379aaf4cd3f7139cad574e5585f3a440c2f217fbfe3283c362183a7ab2b9b66364429fe80b	1651843599000000	1652448399000000	1715520399000000	1810128399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x20c34f60ae55a75717bc3243468ca0de0097d373753ab118ca21e4886839aa57cd82ff3a6fc725e9574af6e1be86ce05939731f5adca03fa610364686c31b131	1	0	\\x000000010000000000800003cbff9148cfd163019a32229aa557260274887b4f94ef02c5448ec75c127cfb17bf12bf6127cc07cb843fdd092d5f9ad15dfc2b6c81e155816e7643da91580c095c8b1a304a1c539338245fbf1ea1c2c2de4210b1d5a0a1f41844d5fb5bcf671994eafef97a91c061c595932d62375193a8129b2407bac76d7ee6b70287046313010001	\\xcce02c776e75b5f2d7babe445c8e199837704a7136e8e6fb13131b02c9b0bf6c381988e00fc3284d34398dd00136c9a098a0ba6a0979d670c5ee5139535b030e	1669374099000000	1669978899000000	1733050899000000	1827658899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
352	\\x215f807065abbdab1f4fb5211d6b91d42287231302610ddb3d833c69ed7bde124ccac7196975134eeef0a0b95fadd3c1dffcce02ac060a6aad43cc9d4ea97f80	1	0	\\x000000010000000000800003e826095b2d6fe560797d0c8f3de8693569a94e0650ac9e1bb849fe366545c81f90f428c5c8ff471571ce95012d371001820618647c91fc121e7d760968cf9d53738ca991d39bd66faab29dd29a1b1e11f7c020fee055e1307249c9d9ca19e67bfaf79299f1831e7cdd51d546807e35ccaa0bd170f7433fc5f4d34f524db4d8c7010001	\\x2ada20e8e5fc42a8211bf857ddfeca82ed3433e51283adcde347f8d7ebedaa1d302c29c4e9d734af54781d8437f457bcc256c96fd350478c4f26f745ec62440d	1665747099000000	1666351899000000	1729423899000000	1824031899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x23577de3b5811cb90cdcd486a9259af8ded028ca18e306e8cc5a1fcefe692b324d7b39e795eb6b99c537b17fa64ee915321a95f9179a744b970b515fe8a0fdba	1	0	\\x000000010000000000800003c34fd744bd3c1012f2df1aab9c42d381e25fd9e8a821a80c9599670c6425e7a5332f3c5fbf4fb58f45e7921c7df4fbcee6bacf3be82f9a1d7b4f037bf1d6438e0558463f0259141a2d751d65586b7e3de2a6ada1b8a136447eadaec827767c0166a33c9aa20042242e1a9d6cf8141d4f613c51de8483667d3fede3cbba05a6f5010001	\\x3e546a979513c0a724e02863dc3e8f2a481323c993e4f769b4ef126ece306c9b6acc7de4c4708249a36e68780446bd80464d2e7eb24430518b57d0b27a171009	1673001099000000	1673605899000000	1736677899000000	1831285899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x25779f1343fd0b6bdc380e76e5376883b62245048ce8b63d7d985d2f9188131a244754aba14cf8ab4657075be74da51e1e6e34cff49c0730646df5c89c1eae5f	1	0	\\x000000010000000000800003e6fd59b18a55d2285c215548e5e71c4329a2f87361ae931bd2c14709020786be56a2dc1af38d11dfdc0443eab8cc3afd5e50f3cbee6a1d9b1af457364aa5082af33702611cc7002b62f84a2abb54f6707a073ec771e16af92b2f818c1580440c140037442108dedb1e9d0a3de1001841def46dc998571d7bbc310c5c582f35c7010001	\\x67140e82858afa97ce19e04062846ba4dc5312de2680a81fcff8fb3d1de1b0fedf88e76cf80d1fd80b0aad4a25cbb4cafb2c05cb366d7715bcaf9896bd84ff0e	1676628099000000	1677232899000000	1740304899000000	1834912899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x2dbb9b705b560e2107849510c8bbab80c9aa873c2a2c73ccb5a7bd94576d47a4906fc282180f788216e2324dd8d695327d9cf764acf31590257e16e939ccc68c	1	0	\\x000000010000000000800003d161f7b46dafe16efc2e522b5365a6762f1a976384f5809619f7c8e53c21e0b212faa94745fcad2cb9b9561664a42763218fecd3f2c1d9a01cb581d2c5fd7da1ce40f2c02835623d4ff2747e7096b34fbb1eaa2839e1ad4c34229322a4ad34bfed632e668f2f15f17e532fc25d9f1974b6f1e9f2a6a0a9e47c8ff4f49661e1ff010001	\\x3f881e377a3e00c922c7ec7f4d9e69f79f96ff636af926d830044ed206508299e4f4ef32efd1ac613a23bd544b5ddb15d62e24713a28d3decdf5cd1ca65ef70b	1677837099000000	1678441899000000	1741513899000000	1836121899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
356	\\x30d717db692ae3e16dea06ce1bb343e9ce94723bccf65f6b7f33e534e306552e7aad3fdb6a6947797f1085ff29fc75897119a8d5a4543c2309ccb3cbf6d68d89	1	0	\\x000000010000000000800003a9bc2f18a6a59305433ec5f5fec4a18da5d44d0f8eea6a68e21526b7e3d3bd198f9e18376802ac58a18bf52146af8d59f64c0e681c9d8829631ab791dfd48e0007d8c133a889e2dd307429bbee158a753519d60cf7f9e0a87ee771c674ea3811d2807320e37ebc19240e6c4dffe81afee56b6993e6b5e2e5cfd16f76eec727a7010001	\\xb2346e5bf92b872166c5f637288b3305ef3c9a0d8f0d9ea79d38e1495c61046ae2afe3493cb849297e9475350dbd12bb90b4c17bf12651a2179286ad9d92ba0d	1647612099000000	1648216899000000	1711288899000000	1805896899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x32d732a0036d9997eba41509d4881147ce1aeeb3dcb4242bce4daa509155d03f83dbd53fee26bb906764fc56d912908b05e00f56e4d2c53aa44d7bac029c899e	1	0	\\x000000010000000000800003be44855664754c2e6800171081fe09e47de51d3d1de180f0e9523a1c2782821203092806096d533780e205cf680d23e807c27e5dc768b37f3ee67259705ce038b78f7e3f4f1d2093e469500ff01ff821e9c9dbeab9173f306b2a75c4065ea2e19da9465c0b03c8a3f1fb3236333e18bc3db0f2fbb4af2c56b28d89cbf452e09f010001	\\x270d1bb23f447452f5145c60f8486a7fa1e47fd2376a72129454b1645b900f7d7552b87e14b214391618a5ca41cf7230da9f3f05064a1766adc8bdf153a24d09	1649425599000000	1650030399000000	1713102399000000	1807710399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
358	\\x355b6195665cae4ae92c60917d2629d844d198173c1411e4b1f0b49a077728990515ada6c7ce6a9a816c96924357a5d68fb970e6ad9ca8909a4de79e867c45d7	1	0	\\x000000010000000000800003f1c7dd915692145c96bbf652b6d5555f43e12010a02f5f90009f17ba73d6db813f2a7300951893fdea240b051e8ae35c726ae10a958542d285e2a5b744435f1d892231b35b6639440987e4622d23665ba7b13a8be8a34f8304b5ac26ea8feae98116f2c1abc7e2b6cc3bcff6b7cb5bc566341a8ea341871c3f5415389036282b010001	\\x5c8666828b6ed248180d18e970a730dc9db8ee22c8983718fcf31dfdc57f27f62e245793c31bf995538102e57aacd50e0acd226af0eb0599bbd377c3f5d62503	1653052599000000	1653657399000000	1716729399000000	1811337399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
359	\\x377fbedbc7b0c0455a6bea630ce8077ba1a6603afae11f03a1ba7f2461e935e4ae231830a3ad7ba5ee4b4cd2a6f2384a47edb56b3e32c565d2203cc37826b14d	1	0	\\x000000010000000000800003c5c2abfad674e0158b3e0c6da37a3a837ab29fa0fd05103bc8b7a7f59aa8f2c4165b1eb3904320864ccd6f66ed1904b9287b8bc3ee83e537d4acc968adedb96694119d90b6b6bbbcb988109f7aa5979fd2cf5bcc07aa93a9c17fa9b9866e4cb75147cd9565af665dbeccee373b383c474afbed3f008f00282397397233e6ce41010001	\\x1fd612bcd949910d3ef2de34f14bf853390716fe07a4bf5c421e6a5632b9aefaba681e00ba762339873fde5fd27476183d28057b2dba5fcc68020b90fcac5b06	1656075099000000	1656679899000000	1719751899000000	1814359899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x37531b3d94a0591c6f51c2e7ed2eac02312a02ff24f401a7c4e10825fbc2a2716527c7274323dcb52fcf360185fbe51e9f6ad39e31f573a9c94d6c6b849d4826	1	0	\\x000000010000000000800003b0b0623b16833256adb5008ceb6c67319db0bdd4c60be290d59ba77e560fefaeae731927eef5a0667f7f2b709fe00a16dfbd1e620ca6fce6cbcc18a34efcd80c3b9ac3968175a811cd760f2491571428d31e07c6ec71ef98a55a035b6d77efd80d4ed8ad7456ced288ed1394b2fe4568eae55ccdf147adcca8842ea45cf280c1010001	\\xca75c1e698b4d3c6574ee8fa6689afc7c5da990002d54881324a44b1460a81bb7b4af03047ded85f6d15561b732b73000b76c279d13af555caaedfb2f076cb02	1653052599000000	1653657399000000	1716729399000000	1811337399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x3c6fcef74a2185ac9f75074ca6599a2a3945434b898d68293163d5b109e037ff99734d0a17f94522c25f8059108765c22d267c47ba922d4711489ec8c68e8235	1	0	\\x000000010000000000800003dc07b6dcae72f4b54cb593ff02f8537534c8c3ca42b519fcce2b17ccff285dca18ae61f9e524d364c4f2ebdd0751dbb657018f4f022b6facbfaf204f9e7c8e468101687b2bb3a03688ce6af4e1cf9ce8c708e23103f91c73d84a31e2b9b4ba6c3c0e3eccaf720f15a9a980274e8ee0f0f18ee540e66734878b9ad4f2dfcdb435010001	\\xa5e03eba27de7b7f32b41edb87c0e8bb6f3b6ad8aea05d4866b7d7dbca304aa4aa4a3b179febf29c1191c4bbc9a011023e055fcc3b3053dbf5a5c08074f5d700	1667560599000000	1668165399000000	1731237399000000	1825845399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
362	\\x3c031d23c60b64e24a6675c00da5ee218e9b0496d06bc73672e9911306086d031672eff16680838aa6d5e7d82ab7b7b56166824f737085108afaefc412532b6f	1	0	\\x000000010000000000800003bcbb06c9576af1021d93c67cb2eee5daf98e51c4d23e8d8106bbbfcadb92d33fcbd1c8df8edebc02f2137eb2370a40c5bf2d7132348646d8a800bb280807cf0c3628e3998fbfccd81220bf3a7a63bf180b832e9eb6ed31b3bd27822fa5762d2bb881107905bc81b23482388667fe3098d38e6485d4c6868d7ef05b4d59774f57010001	\\x39a6d4a844219957e462b5dd604bb65ef7ded3562c53dc42707676b9231982302e40a69a0a1f16900f6ba7ee3314f2f1410fa9d41444631ade8fe00495fe910d	1648821099000000	1649425899000000	1712497899000000	1807105899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
363	\\x3c0309dc9bdd1b72d633e9ee59fce9b8747db367a0e79a5c237618cd69e908a29932591edc84b17184119ffc3ecf77fbeaea3ac6e2bb62989e8bc7277c5184d2	1	0	\\x000000010000000000800003bcbc6104121b509e3b014dcc29463d3184af6b123b331dfdeacfa511e85b0372ede5ba2e9c02ede3b956387c123b67b723be58ed4327cf02733f18067d91561ddbc521ce2b611edb3a24828ab1b9289eec559b338354e8280e90051533694c2b88b0fccd06b49d382795e7a33fea3fdf76a11de6f69f2c8f0c878b23ed517d91010001	\\xaf68a0bf9cfc6e7ac0a93065054bad0b0bb35e6bf11fea81f2c05bc429107b7b0b2c55ca8b13c832743191702e35ad4bd534af052824466503f2197db3749e0d	1670583099000000	1671187899000000	1734259899000000	1828867899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x3eb33ba9a9af2aabfdf135fa595237e8da668aac484bb187f7d4b037baf6bcea8610e38942c5c8d9a2624b9108a26c9b99dbdfb727d1c2cd3c0676181d12e2f8	1	0	\\x000000010000000000800003c463de72075c395762afcb599e8335b1aaebf3e1e967bd7061568e1e06f355886e4fb16a5201bdd9fbb5b65ea2002b09f07416d702202c902693b672a9fc65dfa7df055af6daa82dc5c82a72b9caf0110acdeee1f5c5d2b91c19c6370cff756fac3233cd3550355eaead7bb8fb4e9c880c79704c5cb704cd5b1345ba7bc7d5c7010001	\\x3ed388272e81091ab28f6874c3edecdbe2687e43808fa60797089b4d131b2412ee69a8524b3eee984b25ef7939343f070698320471bf9f3a0aad76392aeaa60c	1677232599000000	1677837399000000	1740909399000000	1835517399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x3f3f9327c3c43083dbb8a1e56645efb9fcf9393856e46bb0bfaec56bd770d686c8f20759e8f2e68e8625cb346a66565bffef3331084c6cb80119584c72877654	1	0	\\x000000010000000000800003d53b8dd88ee57d79a3b4f6dd860032bb76b3d15ea7527744533a313039530cb079c836767a1662901d245bd32622a117ab68f69cfd5dfc6b0d656f8257e3b763990342772c029e246a5661a3146ee2a72f23dcb22dfc02aca89a5280d96c3671f43b3fc3b4720be6bf009ca922b40df4c0befc536f1ead5f717f7ce7905996b5010001	\\xa7f0398a0a28bc151dbf8d01d12b8b0508c108edf0be8301e97ecdac68a5db9bcd895d5df469588ffb703a316c276345c5d1850a3b722cdd40612a7581f5000a	1664538099000000	1665142899000000	1728214899000000	1822822899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x4b1b0e6b7d50a7154a7547dfdfaef6301f603125852604d0cf5d9debec4f7a52b2307940796200ee89a15c44246094fa099e4a0afd568460dec6832d6e20fd39	1	0	\\x000000010000000000800003a2486ba93c2993878e0e2c7eb0f4927583528a29a7f64e4b2a59c0156a73ed7e2c3796204db172a06d2584614eb23e26e3e726abfc2807a0c3879b8319691a60559e02aa4cf78aee7254bcdc114c53dd5d7275190eb98522b60c207c852e80858ffa835f335b2b11e2dfac542c1bca33b3663b4ed089bc23b5993f4892d5656b010001	\\x7c0e8aaf2ed7c9917d42a303d58670a675c4110799d30afd160b5384a4aaf7e41974f45875b682e3e9182b3925c54387d9438828221d5cb76e96e10376d2970f	1665747099000000	1666351899000000	1729423899000000	1824031899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x5143fd0adb6c4b37725d26179b388262cf5bb107335afd8732b7aa7c002ab689852d4656b48d01c8f86e5520f1790feb36ede3b41511a3efd9a0c2518332d99a	1	0	\\x000000010000000000800003a15c87f7c975ad46fd83fd5feb9a6ef1fde983439e7c86c37e6526b8396873ed45f9106b5f0eafbc8c6025694255f60417310cdfc7bde1d494620ab9b0f2d9e20caef63e377d0021882eee2356f57e9d19e353efe5661f6829706f76f2eabcebb96c89d699ae6bc6719746b788ed00191f5032bcc970cc0e6992828d86fd8221010001	\\xf68ea67f4499d4e4e4d007a4adbfa1ea6820e0a09177ead1b45eef8ca5d8e8e0f944b60e5c153c3ca5d372acc745266e9dd58e087b6b1b029dcedad8e020130c	1662724599000000	1663329399000000	1726401399000000	1821009399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x572bbdf765f2e4b774fc0f3ef08ce9a731e7859ac61d303aeb436bc6edc5f720b10943ec96e28cb75cd822d500fee9175ab6e1a1c46e7cf16d00fb6811ed89ce	1	0	\\x000000010000000000800003ef5c622a53142e64f8d3ed39fa5d343d7acb8f7ff08c88d49096489fd0975fefc41659ed365df70889f716a15e49be7cf585ba37f95042bea8369d39b907aeda009a18e617ef94feff4ca5a2a1af90107422edfebe63002d31b227b4342d570f8d41694f883e8904f69a05d5938d8bbc1a52492f98e6de7894263348114dde5f010001	\\x6cc22788f65d0145d3fbef7190a6b2023ac853400367966f5133a5a2f4aec84fc9f8a4d81f0ab9527c24cf17ba29af8dd6b48784cb7f07877f1497e7ff38db0a	1674210099000000	1674814899000000	1737886899000000	1832494899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
369	\\x587fdfb57084bb5f77d9bf4a6efcf4afda0c5c8deab76a5f6e6926ee8383d781ffa7fc5d66e76fc87a356976f5d8d6613152be34f4f5eb738473a387ecb6a177	1	0	\\x000000010000000000800003d085156f4bf044038c797bec94d8cc2e03220bc43374fc6cf1fa43bc3bb126a09da34695268ea0bc1dd44d93da6b1d59c9c5a102624d821926337966b0daa9214e08324d42151f9c7d01dcd8bad3dc6232b2dcd27bd6f93a09140c4de728e5a4a4229cb38e54892670654b1bfab25c60d36cc51edad370b98cebdc93ffa0a52f010001	\\x0cd0e326ceda069e5b32524a79abed80300c893897fe38fe2a2a269fb968cc6fd5e46247e9e6c3980d229b0d36cb73ff77fb8cd508ec0eca960b9117e005ba00	1669978599000000	1670583399000000	1733655399000000	1828263399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
370	\\x5c3f74e567125ba8c6f10aa8dc26be50574b86a19eb63b0c78081c42714fb5cc571ca149dee41e81ad514bf37361f5d47c2c27da7f66af36970831fb563f232b	1	0	\\x000000010000000000800003df34cfcf389ccd40018244730feefe792b7e3f20ffb41a8c5f936cd44c80fdb6445706a718db22cae7abcf1d5f039cf1ca225dbe03c8cadefe31b0f1892af52ae3118eb8582ff40846404fca4488f6350761ba90a3d92466f2e2802f2eea318bdcf2fad94df5651099a2a0933100d958a1de5dc427230987612811eecf90bc9f010001	\\x6742b04c4d21529345c6bdc00c79257d8811868b8377811eb1cfa81fadd401c660d884ab5d489b3d59cbd434e31a679c4a3d704877392d384aeab1a49c38a205	1678441599000000	1679046399000000	1742118399000000	1836726399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
371	\\x5e97890fb8f4704fafc17ebcf2092e30f72cbf7d4b1fb7686b0f63bfa732fce96cca5ce1cd899691dfe23145f3880d6f32effd2cbbd63fca638d2520ae9d1611	1	0	\\x000000010000000000800003d530f0c4c84e9ffdac49c590484194139242ef9db6bfc10b796907105a3b06bf30170fce8ee37115c675a4421f25117b6874bf2016c6be0a10087ce1f5692e363fbb750bc4ad6adef9f75041b7105184f01d1bfea91a81d4e7247ca799b38af1e8ada3c63d90b585853b8e05edcd8589d07519bc1f5bd2963e9caa8165b42a31010001	\\xdb2b5bed9f79f25d0a052073afbc8cb96d237a56e46d1e612309ce0dc4be40cf02d516ba4fa4f1eea1d20863c5a84f8ef1dd3abd08715f7ab36447cfd6a02f05	1659702099000000	1660306899000000	1723378899000000	1817986899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
372	\\x5e2f768a23550333000cbf454cbdcc76518ce6eb5a4adeaba05cdf466d946a87e818382b62c7adb704e0cc40caa43e0614c41cf21195b687369c633d324035bb	1	0	\\x000000010000000000800003f6ec496bd2f47a8992fa095cd2ea1c8a3b7925eb04c3f7026303d4284375532b094cae990f0444b2f03d3cdfe7030adfa5e67fe9c65ce36f1e1c8526008bab189eed323f599c767e199bcaafe9895fe3b93f7dc94145655b16cedd3ced6a62adb82c344d007ced94d63b9f30e90820be500963f2d22c1bde4a64ec76f55aa657010001	\\xe8afe614b2d8359a6c54a3fb746f4a2e4f1da405484f5adee9e3b7f361004fb2e47d112aeba9586ff2302765855c4f930375890d423964099a79da0bc5448601	1665747099000000	1666351899000000	1729423899000000	1824031899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x63cb83d96d80f4262663a2a2813a83d9d37609ec98eec41488aa133c7040fbc0ef993ed666292efdd545d4290260087f7cee0728e3743879234c0ddfbcadfb27	1	0	\\x000000010000000000800003e17a9c7134867e6c02e8a8162ea18089e5f06d28cf10518d33825c9c72c6e5f3429f1f1e68f154d4ef8e78f8a837a93c960ea85ec11df2be7e7e1b61b9930726352630b7d4b5b1de04bf9ca2fca1035b9b8b77be7ffabafaeb68a413706cc1df4aaa15953a1be1bd7f71b25e7afd9ccc3b7c70347fdce64aa3d4c68afa3f2a2b010001	\\xbbdb639bda51f9fff99e9a1d02f6bcbab7d37c603f3786edac3d31c83189d310cb1859c4813177098a85251ef32a0186d8fe58b84d177cc2c189f70f73792c00	1658493099000000	1659097899000000	1722169899000000	1816777899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\x646f1bc9845fd3831530c5f17e463a6b4e7643c9607d1e3761b7fd941f5d5b8be2aca5df37b1287e904a0f0da4b42410dc4f0494d0fc4e0b3cd8a4a49ad86382	1	0	\\x000000010000000000800003e02f0f2994b84170bf0bc02561e2b1e6ca04c23712a038e20d6d4bd0b110a3fbd4587d7629fdf51af7e264813df9acfef9fe16ac7b3da6d778ce2f526fa56f39d683ecc3c5493a56a4f5db9c2761c5b37add4bd6857f159f7186f5676344f14f811826ca34ebcc173b129a277034250c2b34a306fcb1ac48c67beb1eb59a0019010001	\\xf8717c533779a18aceff8493c7150f609c951cf8fbd17bb1b5a3bca5cc2e17da27b59f60e775f9d0b4df487053ffc931c7c458ecb7ff950fe8342dbe3e641300	1651239099000000	1651843899000000	1714915899000000	1809523899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
375	\\x65fff07587a62c068464b5edff2bba3e3b97ab229ae36a45bbb55c6041dc7155150538a38b24823192ee3c726321af57712d5ba8378ddb1d27af6a36e5de60b7	1	0	\\x000000010000000000800003c1a53400447e9f4d388ed34f8a4156b5c7dc425f9771887a1e0c3266e6547a2ed28334faf86372efc9c1dec11d02a227d23ee74cf5a4109e3a454c627577514d171db8362ae3a4bb9a0e96671f9b35994256481dea057ce1a4ca6bf9d77a0515b1311b0356333dd2928c4b299565ba54ddfa25f348fd303894226bb4734b7535010001	\\x0c6cdb98937c281d626f54349ae925208b1fab2110accd45270497bc5c41a60d853301f80ac0effd0ba8f112e94c449f472e1005698224b8a74e887015a2ad01	1669978599000000	1670583399000000	1733655399000000	1828263399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x65cf376e1ff45d8cb95708ceaa0df2446e05a996c5202dd1e68130d5cde638d0122a5f4ed6c57c89b2922f695716ca4d9c94c6df402a26ba46cd18d824971657	1	0	\\x000000010000000000800003e187183ad773113cb71849f5093986809ed10497d6440d09ebb159b251014d91a0865f6da6279c9529ba1f37778ba98bf29b8e54aa1876a7ff1a7f4e080a51467b750ad3b7f77340a29a997d2451177be74f6202d73af37bbe87a8fcc75faadb701eaf16c614386a5982635963f5145fd68c47851c9081330ad2b4f9fb038315010001	\\xd728ce59cda5ddf46420f3b4998f31b5703783644039faec68ce89543284c575ca17b81a4b8d6564e9bb21f015e9f4a923e8c40f0ad02cc93e03ed49fe5e7a0a	1656075099000000	1656679899000000	1719751899000000	1814359899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x67d3643382139bce8a73a3311cfde4db617d2a92c12f1879c094e770c163caa4a09398c28cb487a370f51c762b1aa010ef75efe11826b55f68a3d1c8ff6b3d8e	1	0	\\x000000010000000000800003d517cad1785c52a49b41b25db40e0ec4da1eca0ce38043b59047ec626b7be3417cb9390ae81bfc0ec69a8caed4e4ec90f7ad61de8f5bc6169e7d56ace03c90662b4d1065f63ee3de3169d3107b9f6a3430512dece11f60e87b48ce65adefb613f6dc910434c5994776c53b5455e86c266c6cbdd3f686720b735f94d314310c83010001	\\x8ab7fad66ff00246be5ff02882ed73684162b1cf34ebc23b18eca9499844fdff7f06d94b29f0f69a88ddbb39fd3570a8ff268cce24992a56fdb402388008880b	1671792099000000	1672396899000000	1735468899000000	1830076899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
378	\\x671fd6cc54507bace62b16ba5f8bb568b910c108ee887114e772ee78fada2f04019cf613d1d3998b0d0d1b7ef5a88b3c6d5e88f2c79b8a7bac24cbfff9c18c4f	1	0	\\x000000010000000000800003b9691e59bd1e9edd0b272375f9a6d0d8040bfc025ed6caf4e48f775d2ce857d6de6febb1b4b1f6fd026dc50178cd031840c058baf690fe5ad4e25deeace446929875fc51c3b0db297607447392be0c32b37e3fc529f01b4d9683ac61aebcf4a95a573d57ad7f76546a102519f67fcc3dbd97bf2ec5937bd299118cb7540c3ec9010001	\\xc4b91b47c582b632adf45d1cb99190908e0a3d227aefaa815aa1b0c878a626c743b1f244a5537476e24402d1ab195434ad40c669e1ad4a2cc0a5dc70b9c2cf08	1673605599000000	1674210399000000	1737282399000000	1831890399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x6c93e3ec3340cdccaab7e9ec20898e81261e006ebf942fe74c34a3034e61afc7c4d0655b579b165d1e4f56656a32e4d734707700d989d424a295b2665b8d168f	1	0	\\x000000010000000000800003e64b55d26ac9cf9b2de0952b13dae548213dcfa284484d92a20421e942054aefab42999c5c25d640a3ab9bdf4decb7e37d4ae7d67aa5f61ca85870fe30ed67c59bbba990bc5f7ef8ad0c2ee8e540ce3270cb731d974e79b4c3dffa9b3b6f0ef6b852d653981c11f123f48bc6eb378bac5ae6a5e3ed60fbfdc29a76ca55d631fd010001	\\x5bf62934e22d8a4fcb885356bcd8a4b351d50fc6ba029f9a67bf802b2cd400bcfcb3f3e58da12d106f2e76dfeafbc7254543821b0e5964745c861acf332b6907	1672396599000000	1673001399000000	1736073399000000	1830681399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
380	\\x703bccb056af7667b4ff1c6fd6999192516227abe72e5bfa7c3f9b2fca595fa8af66c29380ea5ddc331f47f42220b7bc7fe173741107910a64bd253b3a0f702b	1	0	\\x000000010000000000800003e1a023133a7d1fe1b9e36b282c2ea5f72b4886e7e82bd41f6913f1ccde24740c51e2d186821bd0c35994aea93a2ba5f824be447a2fb02b2e479cd87b58e5bf8532a1aab538c19cfa30c1e5d97437153604487c38cd7c3a66b9ae489e392348330f1735a18cf0534efcb5d1c3c8ec92488308134d4f6cdc6f89848124c00f4c23010001	\\x891f786d654b9b64740bb8ea2f65e9a284e5bb6f8b8915530bc6bbb54b409179ec8326d32091f746b81a6b12533ec99356d18654128be52fa5743b5cafe0f90c	1649425599000000	1650030399000000	1713102399000000	1807710399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x772b59ee8dee3decce7a9143ae5d030cb2a3ed56db13b4114bf0f97c7c8b1662a04f326fac5b36fd8a2891b0a2b75d5644b4907b55953c5b6001a6774d8965c2	1	0	\\x000000010000000000800003cb0e059c204dc5165ff1f03d7dcf5188de31f7bae0f606105ed389abc5a921a7260308fb51d17f9610360a4bc100b2227c6b0c7b3e54ebde73fe0ee49c4a25056d2a3a47f454214fbd4c639703844baa0517dd2ec4196d3cbcc7baaaa8f734539b2e54eeb919e7f38be0212356774ce9eb548d728a93ccf880084c1fa7628c51010001	\\x7c8335b43b9c734314bcc2d1c491b33254808f0fad5c01fb00222df38a2a9e943d0847dbe11739681dde4ca11dc6c14b906c6392889c2f72dee681707a6bc30b	1654866099000000	1655470899000000	1718542899000000	1813150899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
382	\\x7bb372f41db6ff32614d16afc1513aefe85ea453d6698abecc67bf06b6fdee2952bf22a0681c5c6428e3e6320cc67819f89815ef93e4b0796e7391068a940a4f	1	0	\\x000000010000000000800003c603a563212484c026101792f4caec9f5cfc9b7ee2765077ea4dfbdeff04a6d53411e524154ecef6b995c612a60ccda7185168cf15c79b352a81840dde8bebb73e7582baba90473418d6ff829c96c9e84c2e363c226cc41aacaed69eb6edab1ff55be8127f8da6ffdaa3eaf42b038788af503980718e87fee49cd784aacd3381010001	\\xbbbe5cfb80f640430116bf16f31cea0fec2463818f2915fc58c18b7f656230d2a8ba30fa659c41e8f36f8445ad1a443e02f9e03d3bfb98b7c51dca9acb531408	1659702099000000	1660306899000000	1723378899000000	1817986899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
383	\\x7b23ef64b29ec6cf6110f5d939463b4f5ea50a21c9586dfb75b154a419021757fd04ccce0710ed6c710d4f51743a393475f697f717dd27bd8722dc2d063f1a1f	1	0	\\x000000010000000000800003a6c23467681bf9e1959af7610b9442f298c428e2cf7e2bb1dc4e164b5040565c025ba34be53f4b56ec27ef9c93d8c5a641a7f82d973f0cea5bf8fec0073b93e1f9f0cf2e53f2ec44b2e1b5006afd851876477d51cbb1c71c92c3a2bdb6f7c2f601d7190e17ba9a28efeef6d317a588a444863ffffe2a55b1f094a813ddaac929010001	\\x719bdbd9ad463d6c7f2810ca9b8b63faf979f2901fb0b4c5d578cc59802ad1d62ab8f69e45e4fe739e31cd4f1c4be2b21140969a84588441debffa4eac4c2f04	1676023599000000	1676628399000000	1739700399000000	1834308399000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\x7d8f8913ca5c7c26c845dd842f8ad3eacc654f12af6841c52dd4dbae7af366194712742b502f41be0b9613dc355383c6cb58b66e9f2bf62ac68f1e863227cd90	1	0	\\x000000010000000000800003d2db29578f50d305d0362fd1d71b848e6816c4aafac4c63b173909b8fd3f3098a0b66ab069f71ac79710eaa69d0f994049fc16a593425f4073665eabff02803dbe6c22b59d7796a505019b129b1f476bf2d462645f4360351c70ead5f97419f48dd89e1029e24b8d524cbc867dc3ec03245bff1fba99fae06917d3ba353a2057010001	\\x1c9a285b3e22a1486ec61245c32436ef41abac7d484b7072f856a36aca2c3379ab6ae108e4719317d99be3890eab629c1bf404157ee9b75351e6d4b29615a507	1666956099000000	1667560899000000	1730632899000000	1825240899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
385	\\x844fcbb6923762a04936d997e746047348c7a54f1b0850fdee74682f469344395f4ee7d1be8a2e93b1698d7cdfe5e2f6695b71a0764a5a66c172bed9d9a44899	1	0	\\x000000010000000000800003cf4099be2b8035e49574c2595887a7870e46bf5bbe3791fc9970d530bcb6cc2bac742b1ef43823a24034eab7c6b1114ab28991fcb89cbe0dcb2ea5f26a363bcf8a4c34aa572378be6d25ee128b02e5722437a0fa2184e3805a206905fb7f9c00170ae09c5466c1939e20b4b59c202b67ff4f8fd8ad4865f8701566ea3597c479010001	\\x650ed794f510ceb6831fb766a0661fef33963cff4220b6ada4d4354ce748a6a18cc4d468a847183170913dfee22131c8287f8bcc12416c8ca81c76d5fcba4602	1653657099000000	1654261899000000	1717333899000000	1811941899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
386	\\x898fbe2de7333a10d972572a6a6d22828d9381306df70d9d81783e7164c10a0bf43201066070b4a81341f8d8176ebaae67ce1506bb2cdb69b51c52c1a45e18e6	1	0	\\x000000010000000000800003fe87d1efdef4522761b8f2e1b5eeef82d8ea336adbdab3349da4d4aac9b47173e75666bd4f896f83ef8737334bde74bc694d2b49d1d42ba9f3534985e0b288ad145c22b7c06c828db67d0c704474a233599301d8a93cc617b9025f9d862d48c3b0b2c028b43d33ec36a10fd0b4ebbc7b2f7892eefa3250537e7692c833703e51010001	\\xc5eb9fee4abc3c9e4a3e72095926b2f44e2db71e5844785020de177a221009e6b69b90c9993f72f4f99e1626e2f64d7f4e3349604e21bc7bcebaec805c57d50d	1650634599000000	1651239399000000	1714311399000000	1808919399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
387	\\x8a3325392f42843f5e0c93ecf53944f074fb0c3083073e4b79fa56cfdb23e8c9b5eaeb1972911694ba752016847c66cd8ee33f984768d51836aca841076b19fd	1	0	\\x000000010000000000800003c7b51485fa6f5abde7856f3a484a7a76d915b3e6969fb3e557ba8e6fcf2774b04797fe0b6d103292328807c1b6876a986bdbc5d206a31dcb31c4bfb3d63763197f38d68659bdf431c3b1ea8dac69593653b4af8564fea6912c9d5598854d07a37e783025a8ab50ffac45864b39e7c76893e9c1c3627360df1dd4dfb38ce0381f010001	\\xd71a79cd9ae6b464456f838a5e0071ba6ab021c0844491950c0c41d55e2f30e47ffb64b8e757a420fd889abc09b685d0813a3446e6b589f63ce3f16b38269601	1648821099000000	1649425899000000	1712497899000000	1807105899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\x92df164fc6bd8935a2b40b9c729e4e3838ec7d521d5a824d4b1d981af61b639b3a7baa99e5c6391bb8cc39b58968d44e9c866fdde217b96bd8033037cca7d36f	1	0	\\x000000010000000000800003c404d6531677d405ba4f3b8d9f2cf0cfcff7d098cbae809fe40a2ebf463a6307e87844d01c2bb9e5e9f7cc32989f5702bf525746125d5aabc394ad1506a4698a20d95848f23ef40b95ba98cc90d72264d9355451695354d1c264e78764c30131350983339fd5c80b877d2583ea8833a2cdf7fc216ca19438a3a1247b974d7975010001	\\xd26ff45b88450c821e38666e77e37d8df7f74cf75cf7f5fdb34564a34a879e9cc0606f6f47d2d9d661e3cf3bd2e3fea0a8f13a9c506ed6a6ea4b08867e2cbc0e	1674814599000000	1675419399000000	1738491399000000	1833099399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\x98471130fd10c44951b9d691a2fbd05fe568b0d89bbf4da51d9da5a48506732ee4da3948695016a9cda0fa84b210cc4e5950884e08dbd54ad6ea71c11a229067	1	0	\\x000000010000000000800003aca0a58df904ea23d22bb47c3e2ac908d18cc339c83c67936a2f6154a279db76b7d006e4c1bcfebe91f29ef8163b1139b18ff007daa881835666946f4d0091252d69cd93395627dcb1c166af68947e13a4c6ec5fdba0cb7bd80c72c3a3c4b0d682d77c70e35347d026c8522137a8f9ebc2cd1c1d3afb0aed5252152f452473af010001	\\x39fed8ddab07eb1f06a56bf0021e10f8b8a1edfb3666661a0b90707908c92ad24c3cdfe7de4e0dc0aefcb4b21f505d419ab53c682a59276c119e639255f2300b	1671792099000000	1672396899000000	1735468899000000	1830076899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\x981f86483270360679b22a88608ace6923687f3b9acd2dcafa5b8283531109b7d3576337863736b60b1bc671fa099a59d00bce9dec0f91c47b4dde7eaadd9b63	1	0	\\x000000010000000000800003ed8c2ef7e9a9cf662730fc40e9583d381331b6b8475d8e096b6aac1504cc8015281c1afb023e85136eaeb1f6616778927ade71e06c40e0ff299ede8c27421b3b16561abf428f17d0f856ce4837a556d976b9c8413b05fb48ed79e7db0272c7051731e4146f21757a8b7b8369fa6f719d1542ba8e4bf7cd74642da8b52f6195f9010001	\\x289677e5296d90614e017a650e6407dfc37af7dd097327b79e45863622724713ac055c73675ed895ee14411bda86a0ecfc03eb4ae2a9d72e8b335bfbe7dd6c0b	1669374099000000	1669978899000000	1733050899000000	1827658899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\x99f314a2b3a4ef68924bd8e57fa6b1978aa09f2e0d174350e4a0c0b5a1426a262a59be59b10cc45bd1a42c104d8cd04e82a778778d86239dbbe0e8b2f275d83f	1	0	\\x000000010000000000800003bfc63d2d3e77170027027df0ac5358195601baf33bc84f9f2d24b13f310705614d02cca1d4f9afd6f74fd5dd8fd094260bbf2ac317a90b63944f582ca20ed97846abb628f1c868996419b7e58315b605f264901fce691a3cefaecbf268a28a9cf5873850f66570fc3af0f46d397919646584b0542ebfde5cc8778ff5bafab92d010001	\\xbe496fe6c5fd1123a49270fa6e337a925537284515fb04ff315343a43f1f7c0e4a7bc003a360d6236d7cc0eaf1a99db802310a22058a63c84dea91b00a7d7f00	1662120099000000	1662724899000000	1725796899000000	1820404899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
392	\\x9b6f200007b4ff33ed012f4a083ea71a270e13fcaad64ccf97d0578eb1baa39d5aebc0d35a3b9842da365fc2bcb82481f9a80e603b74ebd7173b480696761ef5	1	0	\\x000000010000000000800003cb319c4d4f1240ca1b273c3cb859be841e9870a8251327e4d2394eceed1a7920ae0807ca36b47fb849a570d2f7bca685131c55bb96d32190fee71f420b178dd78efff0010d7031d8c81a3bc86084fe830db32eea551a2e1f3b24b76862e0fc77d9b421c417b45bcd799a5f8ba7abbb07ad756a26645be47d3f925d930aa726df010001	\\x4099a398346e8de9cae0cdda848ebd506059e5b3f09de35df2a050216dafec001d1be3c6ec214242f1bcbbfab058c347c667a1cbf0471bd785f58027bdbaf807	1662120099000000	1662724899000000	1725796899000000	1820404899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xa3e7023254279a7e1cd6912b3bee49ec68d353850af2eb603a7e9452bf1c5b3e0445d57c3f2d759a69b76b69cb711b8b2e070c40ff436b85775e10da6beea8e3	1	0	\\x000000010000000000800003a116d0efcb60cfa853af6557ea4e2ef6e9b2d7d82759c8881a3c675a51e8b6edb64e9dbcbcfdb2cbe86643ac390a697e949a977e1af489ad4948dac0cadd7960d5749f79b05b91472fee4429c6c24c22aff9aca902fa8c04056f1b6cdf6b4830ba2e6bfdd226dcfe21856d2321e779693e16ef7403a5d3fdfc0bc8e3fcbeaa45010001	\\x00c0fee01df29bfe8be1af31fd9a0347c2746506c54d43ba6559657e5d440e9384143ef64904d5e1b2b2ee6c56316a5d912abbe63a11568159b88a08a877e60a	1650030099000000	1650634899000000	1713706899000000	1808314899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
394	\\xa4af9fa3c622b2c233780f45da861a45991625c433638bb1103b703aeaa176c4cf4d33e554718a6894ed5b4bcfa290eb1612f720308622a21f0de02746060705	1	0	\\x000000010000000000800003d5f4067b29081dec46eac3ccd0b94ce246d79d7a8adea84cd45b5ec55012b18228f6dbd60792a775aaad7180fb53124b1421e5347105ed5bda5f4e1aa2ad11fa903b07ac48c2b8565f6a494f796a9ef8a68bbaa68e6a7ff917bc72606f26ff1697ec72be7dccf40d8531230481eb2b107c28d148f163b75aa6d9050c82eb80b5010001	\\x0bba9ddd0150bceed0bd65b93bbcc9270206cb28a67bee5a59705427e3f4f91e506496a26f50f51aa17bc321c75f01697d57d3ec6cfe785cbb9e3c359f233507	1647612099000000	1648216899000000	1711288899000000	1805896899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xa64baab4138e57051d04eab64b78b441adb2bd2cdd47990193bdabe10cd6e0681fd0e8fb9888eef85c2e3c8a75a265bed2ad0b839f0ecc0056bd2e40f6503d93	1	0	\\x000000010000000000800003c2ff06d15aaf543342b4b356902a8aa44f22fd1f282dd4c8e1cdadbf3f79cc4f0f09a26839e062c06ef2b06b161802598555cbbdf7f7f58f919b44d23e41849baab0f4ec9b4720b4b0bdf144fb570775f920708261a84c71a9a058cf9825406c273c84ecd5e4690a3343be3689577e13a1054924d936d8fbe531e4f48bf6e65d010001	\\xde14c8b6324eed44dc4c9873a1ef5a16ba3e458e373a66ae052d87ee29d9e73949dfd2710b5347af18f25776dc85d0359b1d45a46ad8759077d9dda5de80fa0f	1650634599000000	1651239399000000	1714311399000000	1808919399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xaabbb0046d53dce3b677931a9e2cde9a3e36fe39b69ae91b764dea2ca16f7c04e39d6601509e859d0d70c8bcf1031430c550cec068e11563538ad2be25a4e7d9	1	0	\\x000000010000000000800003b8e921b7d33b26647bdcb95475af1f7a7936db7afabcdf5de3c39e936118f5a1fd28acd857761aa238c9f65330a3e63bf237e16f116b68f85576d66e207dc54b68f7c65d06ff726de54639a2e4022af68642c0ebb4029b1af7b0111c7b00e2b10a9d5293961d068c251e41b4195383f2b4d68f724f852f0598f409d766e72907010001	\\x97e86befe8424ec760de911c078a1edf5235495a03a77f2b9457f07274840c28c88f1cb402eadf1e573d0f635b187c9dc26ec15db7d006f573a31b275b5fa506	1660911099000000	1661515899000000	1724587899000000	1819195899000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
397	\\xae3b52b45118a0f2f24d7869ba5b92c2e2e21cac37ff0ccbaee891a569fbd0e1cb995965fa65bd1db6d94ce0091b6413c74f5646b9aff2f6176fa53e6d6392f5	1	0	\\x00000001000000000080000394e0f6e779e22d23087a7c0ff63fea88602b8f3e248cd44e505fa6c12b02dc57f2b8b80926f2617a672310a517d7e336d18f8f599589fccd7a226db1a2d2e9a1c0d2e408f6aad22b51a03da2c52fb0afc94daf20e770d8f874251470f77a63e9103e1269888301990b4aca2edc6e92376ac8a41c183edb23d24d6037abf79b39010001	\\xf27c0f14bb49ca478ab4346dc9212a1a5460a44189f0b32181136f93a3fb8d6cfc0f8e08572b173ba8b0e4beb986e244b6b2b7395ce836158e6fff966d24c709	1656679599000000	1657284399000000	1720356399000000	1814964399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
398	\\xae572dd95d322deab237ce801b1f61859dd6301615a8eb9f489421b58b4187d4becc9bc5b00a79a1a95707785ba3489f91fc2168b0f0502cd1415a321673d7d3	1	0	\\x000000010000000000800003a784ac03ef3fa765c991bdbad986f8a3f2fb9ef0d554877da511a7d399fcf895ae6a2d987ed6967b6591c6c02a7ef507198434d4b564d3b7a150e5d2b5b59d4d5ac6d5bf81db11d92fc7d4b18cec69ef4bf6e2c62b22d7bfb2ba5d1d3e045c706077343b135cffbab2f9f79622c185614bd01ddccc84e89c1c5906ab99e1bbf9010001	\\x9b5a3f43b6e7d72f0049f92d8033e393daac7773803aa93bb01d371f2957ceaeb3085380817f41ea92524e5029b9794842caa9a2d5079a24a1b004ea17f86d07	1673605599000000	1674210399000000	1737282399000000	1831890399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xb04f1da78c61af7c7aeb0901cd7965e29c625f328beb6b86dc8d7e87db695242fe7c3119e254ef801b3427d26ca59ec28323ddb53e6d27f79a7bf0c232f8103e	1	0	\\x000000010000000000800003d9ee96177345dd26065ff09247988ee26a2239b37fa34655d21f49264c5e4e65f29284654cd9ae7d64cdc0814f589af675162f183893fbc423aaabb0a92b452cc04856a2ea462e2a2ab886b0e7ec65fc55f9ed9e10212ee66c070818802e9e6f8595341be5ee16051c10cd8ca0f7102666f933823dcc838f8d47ca2a2ba669bb010001	\\xe7b3a9ce30b78dff8a5eb3732caaccd648b18314e0889a15d18743c70b1912b269d2d63f166c6a86499d8b943797e57d6de628c3968d039d26a129e2c29d0c0d	1671187599000000	1671792399000000	1734864399000000	1829472399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xb12bcda1f12cf47bcecf5a9ed9d6c380fa15c3dfaced46fc7359ea490457fdf1001c59dc3880af65a7b3175d446ac285070656bb16c612a629f0feeac61df8d0	1	0	\\x000000010000000000800003cd0dfb1770e771b3f3c5ebd85cd6c5801a33587c7391de9846a3113986162b15aee666afac4f1fed8bb462eb324fc3de83f2fa1b59477833f7ad1885d81bac78707be0e0a520a619b2de12e06755a902d5990f6263b2352c2e41b09c38741c64e1842adb8807d9590fa17f335e09bae7dd057d69e9d51311eb8b9da934ee462f010001	\\x9962899793357279affe62b1a66d812a53406b8c4664c553561852b9cd2549616f5a81708a18a49174712bebba9dd06ecebc3475a00b9e38dd5da56501d4c00c	1676628099000000	1677232899000000	1740304899000000	1834912899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
401	\\xb353cc4e40396d15f6e1e397b9076a4a489fb5b7839e194d15c1c548b41c4a989351b27bc9e5507be519e259e022c1a314d9f6c9dcc175446c438302a37ba32d	1	0	\\x000000010000000000800003f2a549a22aa1631a5f969b6e6f0b38e893072900237938ad1b24242bea0b2b86821d6121fa2de16a88d6945e791fc1db84d75ba11dfb7b5027b3915c508bae891bc21ad8c37d118f5169f610d52596f622f6dbc2a6672b4e918f7b994bcfbe4695b7c86af01dee2f76517665b866c8aac84f7bf412a34e408d60779e938667cb010001	\\x8b8ef9ff1aa4b4e53ceff9344f9b803581a34aee7112cbb434b16b00e3af4328413c66df9157fe1b2ba3b988a319b51b878b00df10db8cea077cab275f8a180d	1673605599000000	1674210399000000	1737282399000000	1831890399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xb41b97655493e53598b0b6d3aeefa40c3978b1e1f237fd8dc7250980b245fec3e309b6f3a2b83823a0a40c0aaae7f55441ab69bb6e0c64d60ca04b6ed0d9ce0e	1	0	\\x000000010000000000800003cf80e355407639bb135671cb3299e86503c5f23ad4ab08754bbbc2f2c4c207c830eb8c6d626a586f9abf12930169066b5aceab898b2f2e5d965c9cc53caf4810bccecba4ea97555fb5223fcda8ef7ab221fc6cdb40e8302370297645fb7bfa9184e7c9333cf655197dacf337427366917611971d88c129e2a014842abb0e9341010001	\\xdcbbb5476fa3a0f67c7771a43d8b3ee5bf3dd4fdfeb73c2290e319de1c700f6bd2a48951451a1b106fe5d5742a6d102717ae6f719ceab347a0930b81bb3a180b	1674210099000000	1674814899000000	1737886899000000	1832494899000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xb543115c21e562bf814879cca2f5f032e3e3f7e250b003d20416872d0b32651c4174c0d57acba8de7679ebf8ce76df7498ab8475decbeb64ebddaf03024f91f3	1	0	\\x000000010000000000800003a5f5201390291be02233f0a1b625998a9f5cfd28ceabcc97893092357883f272768ea862604cc599acc15d3515cdbb11755eff780668e3a5e20e1822405c925d3b51155d87142b3b8dccf13f2311f36c332a05b7af732b0d7759860e057ca55e5b9b875556949e37c9db98d922de3cc7435ddd2a8ba29a4bab75c57d2e1171dd010001	\\xd4d34dbf452f61c8e1c7c8fd0ed2675529522c6fb4d86a63139b3a6bdca1d7bcd0c8a64d3a5159ff2c004273f26b7428b319f66ac0220fe058797170191bf804	1670583099000000	1671187899000000	1734259899000000	1828867899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xb7fb3f099ceaa95b6738a97c7eae2f1158072abd3b822a92f1f3b4137f736a3e18d00a974b1c1836e41ed9168e8e7baec49e91bf7cfa8b3de4f28efb42467565	1	0	\\x000000010000000000800003efe10794c2126d81589ef6710a6ecfb8223ae459e9bc2d7bb4a66051d1093708308a0036c3e6f5dad63496f374c9f23f5795c61a184e9daa7db29cdc7ffb6f7f4a402af388fde3610555ab71182ac08b5cc85f9f06166deb54aeb17b886349899b4782c1475289dea298c4000cbf181704806a56258ccc7477f74980fee26e1b010001	\\x929d104e0ca1fd5d8e108f306c418f7b39561149caf0075b7ea7b02731fc745439221368c91ba6775c2f8f0377c243c24e4b3ac4f12e184e2aef39c08a1e8802	1662724599000000	1663329399000000	1726401399000000	1821009399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xbb8f2b37904bed69c8123f80ff2f02d1d7c7e73fcd179ce4316f66a59816a9bcb228038c181303c29c840335dab7634b906dab0cbf981f5a3aa54d52e89e9b49	1	0	\\x000000010000000000800003b420bff86d06cbf0676a9fb0dd0ff657baffa5960d1bc059e9ca045ffb8626560bde9292e375cab9eb2444e73cfd5cde072e55f335c24a4e20858c4601b1e3f9bccbe810a7670077af61e57040b534107b1b5cb1ef854e5c0bc8e29efc9b3393a70cd98af31445fa51aafb8a9206234806fb9e39a490aec226a4937a727ed5d3010001	\\xcab0080c2c6f28bfb3a5cec21e4f5750eaf0d8e9b80eddf0d8b48c65bb6e1d1d4c9b5cae9228173e38258cbf858f5d604a22b71df86a00c3d7822d273df9c700	1649425599000000	1650030399000000	1713102399000000	1807710399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
406	\\xbbf7551997d348e24948ece1ff11f32be4b71b2258907ea122ed6b3057c20f5ac024b390517b1a49a3ec437c9c423cd2698f020245b31c614f9fb88b44e97120	1	0	\\x000000010000000000800003ab5957cbebfe8d9747e2d7533b4d7b340f5ffff16c5365400146022741e8b531fab1f386609d4f7c934739ce79679554a267c756d3046fb91b6b93653bc0cf9a677f321e301518fcede0ee82917ab42a86a4f47bf3898470333c9db4cdba2e04f397c6e925cc8f1c69420bc1e42f7faeafb6f4dab44a5bf4cd0e427c1f5e9f5b010001	\\xf9c4a548d6977536181a028b7d09d552cafd163aca45e33f6a1f78e109147832048d59c454ff6736d386ece7709a0a6cdf1e5031cc04d2edec04a066c8a74205	1669374099000000	1669978899000000	1733050899000000	1827658899000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xbc437f1322aea5c622bfe9f161e2c7dce5f8a61d13cfcdc2295f774b6873532292b9f3c6776b514620e4132e885ba7dd9ecb6d5d3f767fd49627edc92da0a2b5	1	0	\\x000000010000000000800003d09faec90a6ea8f040b32e2e3a800aa4b83e47c7bc6cfca367e99e0514a9ed83499763790cb9c0f6d4316208d2abd93cb47322fe71fa7657887b8150ee1522e76dd9c3573d86a0da5ab08c9ac74c0788c6f5c04943ebab7db60eae9e0bd797e73defb36e7ea4999dee5cab99aa9a2bfdb3bc2b845520f57f3ee83263d18ab881010001	\\xe94aee23a7e615e03bf34a01836e766dd5ec263c8172df91b82799c14e7ea63ce0778710b6b23f49c53f2ab0f8ee73faf9f8776019911dfaac77573033038d0f	1658493099000000	1659097899000000	1722169899000000	1816777899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
408	\\xbe07d6df4b84db177a0dbf9e204a03424c115e19cf65d55e606bfb21d061833b4134cc68a661483d67752a7583421e0cb42474339a1641f2131e166e74139dce	1	0	\\x000000010000000000800003d6dfce4bab718f11d22cf26749ce1dd47f12ff28d9387f61b1e25adfa7aea49eba62c4ffaa7d745627fda8f1fcd41abad72ffb0eb35e8373b9c352ee87ecd903edcad43424c96c0fbc088d858a92d6d07a069ce99d029a2145cff610f6fac62376d9b9fafb2a1d801743458bc6c1384af93c0f65319c7df7b9a17bed0dcd0e4b010001	\\x56ee0cd127de1c330dc482d06c56383b62cf68041e05c2786623aab8753dfa74b0b9c2fc8d5306955eb7c195c5cb35becd8ff01a94c5fb2693926f8670601e02	1673001099000000	1673605899000000	1736677899000000	1831285899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
409	\\xbeeb702c8bbadb45ef6012b3a76a1a556256cea0b88d14af2b6231de59cbc98ba0cf4c3ff4c3b1e5818d807edd95d1dfbb901c3d44e1f58f44bcb5dec07b1c9b	1	0	\\x000000010000000000800003fabbd82b9ea934343ee1bff841c6fd1ca66f06f524c45c85f5baa48f60370b6ee1e0019a37e655a256cb5c08ca56acae8b384f06aa1bcd5a8d8db3435fc8dfa0de2f48582d313dbc305a529ac725cb712e6e61a04ade5ffb63e2243d645a6d227b83d2947c81f3bdc188b7fb839670cf271551a852b7334766fdfdcb5efc1d31010001	\\x21e0e51635b73dd7abb1f143ad9afcc898d80402c3046c803020cb0a49a69341ea1d5de909d75ce1548e06085f4ceb794b6390b6bd10392483330bab551cf205	1660306599000000	1660911399000000	1723983399000000	1818591399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xc34371f8fe1ce83cf9769e13fa5c027702d851251c88a8e02c01915d404126a7f9fb498249598bff4951b7d547a7d6cd6ea3f124b110749950fc7f9ad9e58552	1	0	\\x000000010000000000800003afcc2a91e6fde380bb2889a21582bcd08c460a8336251474599a57378f68d4edfe80bffb19aa0d16785c044ffed72c68401311880db9a88dc4fa3b411e75d746afe41159b718cbae69c98885af60efced1ba1b826e5f5f9755c8a1a3e402d96780f48aec60bb0277b94c6da258d505e0df6130baa177bbc807624abaafffd5b1010001	\\x95b6ffff1cfd0d049118c8311da2fa5eee2d62601e0e8457b440187dd93f0104e221628bdaf04c21b5e260a300e595b3a6aa2beb39aaecc0617aa5a9233dff0a	1662724599000000	1663329399000000	1726401399000000	1821009399000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
411	\\xc7e3be76695006d15e2c92ab526bf265030cbe1e9cdd5172537c59d99a09817a3cfba429c6e7133fc7ab6a8b97e796f6926465538f6a2ad4e19ab9ec59e77480	1	0	\\x000000010000000000800003d756780c46c819fa102c64733918513501144c9dee80f9f5e21c3d9228a06f6c6ef59d99a88b9774365b8efa6e7a2aa43808f55a55bc1d8d2fa9a4337eb621697990c01eaaaf2b98d34ea60f4c61b726940f90303b5d3961cdf9c9f5c930b3327dd2415afed594ed97d3e7c5dcf3a477745eae6310f1705b47153d6abc96ebbf010001	\\x2fb3690d57a5f79c790a16f0419c90a21b943afd27e81cc80433c8662f65c1164b412bbd4d70594a945b597521285a8ce12de50616597b60e3d03444ab1beb06	1656679599000000	1657284399000000	1720356399000000	1814964399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xcdb30a9090c25d7a85d79a72d208dce2d9b869f04aa8413e60430ab1552c71299185ba43035368c8dbb2225748566d19e496ad5ba083c40fdc749ebf82304bfe	1	0	\\x000000010000000000800003b1303538c7a5e9d14e3839589393031d687c941ac88138e4d20d09764fad437637839fefa2b0e61019e0df7d3da9ed3e6985881e33e4e2bb74021f723e0ee86b16eeda1949b1338fe2bd2b313d6c785a0fe31b26ad560a286406d0c787703c9cd8314e7967a57a11790e1f79e68543a478c197d112645066c3909b89e205d92b010001	\\x39c1a158becaedec87bfdf7f985232594dbc6eebc11ead37efdd25e0525e5533f5dbe380d278f04aaf091b2f9e7de664e1a8cc4635ca0957f2f0dfd29c8dab06	1653657099000000	1654261899000000	1717333899000000	1811941899000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
413	\\xd0bfc77d0dacc371b21db1921a6f10fa791010854304767a943638d04be280a59bf0601ecebc64c0e075539fb46911f9d9d9d3391aa5c796a301c5d6d026c6e7	1	0	\\x000000010000000000800003b7f23b7d22cb445e20bdf237a791250a065b13b181ef98e37943e849a579b1c8cf35bead39a681d391913f537c3c203c80d682a8fbd71b3a746b25e013eb4375839e305c430bafc1b364918096a6a7493baf80d5fd2a4f4f6c396c211286ea0b5c907cae91a4917534fd5c08c0c1e25283bc2546d98d72dd16783046e0702f85010001	\\xa72cd9f1349eacfb685b4118cb79a283773f60f8345bbf884a1a02366bcf1549f370358c269555f8d9f91956828255c1da5e2813ad07663870c2ba438844440d	1663933599000000	1664538399000000	1727610399000000	1822218399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
414	\\xd6db2875b0dab416935318270b43ac05b10d418ee5625e3ea12f311a8b5ebe9cf99b6b195401f44ffe3d9457b6bdee70e6439dce02cc662756a7eb1b07528312	1	0	\\x000000010000000000800003ddc37725348a9a58214319926089bb8a5ef340e3339eecdeba5702955c7fdefa77d9f889840e48a0f7d982b90ab7027116634f80ca364af75eaf55aa78049b732f8b2169f78c24166ae14d98e9fe58815fed14fe05f17bc15e055531fa22e89198fe0da90e79251de6a07accb2e28056bde44c8d3dc7cc8c4fafce470061a5af010001	\\xc5a297ddc0245583021fb8fa225e91e83ae0c865976196d2c70f5a08c01f16f840128163611d77f285365db29d718968d21aa10ee8b112982fd4056cd4439901	1650634599000000	1651239399000000	1714311399000000	1808919399000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xd863f5dd6f9eb70361d868859fa9e3568871fa3c5f386be482062a8b2570bc337d4c0ef8927cfd0ccbaa3814c58d60cd83f2533016905141a7f46c8cc36bc399	1	0	\\x000000010000000000800003cc9c57f0459d0835dc595c78bb86fd2dbc5763019961ce6ebd48b1509d5fc42d7078ea39cbf5d276c692674950fc9bc5a48d488d53ab7dba6a27c0aa7f10ecf0c3a859e6ca40d397eabd37df5fecdd9405d351b36242831fad40833da314d500025770a71a8ad2aee8ea25ad31265b072400e49b727cbb1add05eca60a6af787010001	\\x3a5c0c90c870a4ca5766222c39cb02decd2f42fe6669fa8e549af2b7f690a5dca7ff5175b8d0d006d98adfaff4efb98b2ab9c2df22522352c04a8d80d5d55909	1668769599000000	1669374399000000	1732446399000000	1827054399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xd8a75cc2dfbaffec0c784a8a608ae7734bae2e9f23d5d33799f68f294359e37b86c8aa43fb34818460c8bea506a5c3b5dc316d4cf71d7cd6cadb89ffce471329	1	0	\\x000000010000000000800003b0d3318f19c11c0c25be8ae461e845b3f08a0a441b7bb331dbf358fdd9f83aa36a17ccf44638d50cf557c4e8afe3ffaf2108406fca50550c617e0ceec21121a10092f5e6521578cee93fb312523e1f10fd04f1f2b46c7cb579a0e8443dbf951427592e27da838e90565632d388754d67b10a9275b0e54e48e1a390a10412d5a3010001	\\x81887d0b065eb6452f759bbd72e9568d641ee73b36a5a63296f12da139fc2099c33f75b6963b5454b68d7b8205c7fb2002b9985010bd20a26591fcff930a5b05	1668165099000000	1668769899000000	1731841899000000	1826449899000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xdebf2e4138ed5da261085c5f95fb8056ea66ed044b58f776b1bf1f7fcc03a79fb202a9a6996fffa5a6bac26ef449467e2d2f7c6889755de60cc3dfb5a19c9f29	1	0	\\x000000010000000000800003d23f47157b137ddc6a04aafac0c77ccc806608a24b92d41354c659c158ee59f8e1136d9e14d6ec97995ab83ea46d28ac1da79889f4babb54d0424f28d23564e7a5d5925524a6a2267ae60222e6137b8e59a0c32ac1c940a169c8b037e3a6d9ada98086cdd9d598d1479a8242d1a32e523b0ca0b4ca5822fd1110402e6c37c5a9010001	\\x8842d2c7fb7caf3f826f9c32a0d2c09f478681f92c37e6b9bab22233964da820d6ee439dcd2cb32a666d3dcc83d47cf10dc06f7592d4721225498f22b18db908	1667560599000000	1668165399000000	1731237399000000	1825845399000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xe40f5ef2a9837b9b39863c230ec2919f029c1e08881771fe4bc8a42c9a26e9e51456d3ac7810f7f196de49ad050900a45354980b3383ba343b4eb125c61f089c	1	0	\\x000000010000000000800003cd7352942282d646f0aeaf4e2c984f2907dbb7c09185a0745bd6098d761b660b589740aa224882a792e10b4b4a018f48c8add6359ade35d75a6c94f0e09efbe7eddca2624619f4ea4df3fdca9dd46fd2f4177876b4d645d63b339da82016985e13e38e7eaeab97b01519622faa31dcac7ff67706be37ff7f0287d61f7bf3bf8d010001	\\x69282760d43972fad38e058bd050b22d19b291bc7ed22a5b1c8cbe13fe103be75bac6a34bda178d3f9996de5017f4f11ca74783c6569557edfb18ac6f697bf01	1654866099000000	1655470899000000	1718542899000000	1813150899000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xe48f340db85ba8895f4d3947e3db6466933ed129a710f6bf8b51a3aa754b022e772ce7f0cd0ff906f6cc87172c448078dd11b29e4cf75a4a4ee74594a91e04aa	1	0	\\x000000010000000000800003ce37816689f3d5af59909687256e684f3d874abcdd13dcde09541c4951efe147cf0185321099ab5e6c80b1562f1d62ca906a8b3f5faf91f78283fa28f64670767dff8b9bce84247d6936ec760db8b6c5efaee90204a117d3107eebedb1c7b0d9efd2289ee37aef1eae8c5dd8b60cb33c66771416c80e073c8e00dca2cc803b7f010001	\\xb94c9f20e277777e4be5fb3350ede55e9bfb865dc0c0ea64e94ea2a2eacc2855a1436fecff517a988c102ca8be6b443f459dd0476edbb3f46ea9ee0b9e350303	1650030099000000	1650634899000000	1713706899000000	1808314899000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
420	\\xe6e725373898339bbe6aeb89ab04a79afbae4049385103694a0017a4b734f0f44bb7dc3078cecc4b80958f03f0f5895ae3c620fa1b6127e14af7f27a250b2ab7	1	0	\\x000000010000000000800003d69cc6435344606dfd9508775057b11a7364c80e40a91d2f192bd28b9371a4c7b2c685d1bbd1fbc118bc7b43c3787e6b03a3579f74c9399b6a593bfd8183564346c5fbdd751b89c0d69ca8dcb338671c964993fb466a89b1f2d4c3a58ff76f9e0aac5270839d5f5bbc57250a35cfbc99b09a66113a3b4109e75317728ec80069010001	\\xb0ab182e9dd20a48fbb5a1bc54f91cae5a675427e8e09c3f738dcc719866e6111aec1bf6334a9e75f4a55daf1f870681c5dcead5a0c3d532e2058b042caf7307	1651843599000000	1652448399000000	1715520399000000	1810128399000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
421	\\xe7b7a6d2a526ccf325fe972fb15e2b7318662db891a8ba3645d929c02b3e3cfec8a0470060f4e8f3930a1d85b10b58b8337caf84cd5b51c82dcaa124d3e65235	1	0	\\x000000010000000000800003bc936f40f92962c7f5e4f942587cf6ae1bd5cf41adbbf6cf6ee492cb8afe9c7c3acf1f22847610ca4ead626db57a76c33875bc7221d36e65179b9181b0c366af96ebc5b37b66d5179df4638ee66ad71df50626901bc59e1414995d76e40c7e4a5ff920058bd0d620307c18f99b3cb81807ef035e6be7387f9fa43905f3ce2e09010001	\\xef209528ee5b0bdeb9728417206f4380477cc7c8279ed4fb1547e1de08b839ff6c4d68f02b6648df215a08c2511c752b5ddec718b049be0c80e2f088ebe50e0c	1650634599000000	1651239399000000	1714311399000000	1808919399000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
422	\\xee8f978b9c1491239de7b7462e83cfd631a3cb99ce2bdb2be59a1deadd6bc2b760888cf07f44006024a60e3b2316e4b4173122e11b7cb4d4662c3b655a1664ea	1	0	\\x000000010000000000800003d7a3558129a5ecc0931d855bc2f12eabd839bb6fc18f0247b95b41293d687d005c7e6fb239eb8dd6cd9edf52954368fde3248249b7e5706691c9188bc482e294c740932d76c3988fc8d39fa7a2c7841d4eabe1d4299ddc4f1fed264796a018b709cd9ba98a550d16aa8d6c9f7c88f39f57256816a8254b31dbf8b459c2401e93010001	\\x3dc125b292099c9704856ea5a535a5a864cbd1925d57ddecfd6bd85bb46e8fdd1f3716ebaca94cfd19fc963a4a928c5294500ff65d3f85037fff73717153b80f	1655470599000000	1656075399000000	1719147399000000	1813755399000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xf6df652927f61c598147f512ca593785b0f5d98fe0f1bcbb4db70459529b54d08d5dac214dd5a9bd859a99d25251d4fe24ac212004f3c4136bcc814a7f196fda	1	0	\\x000000010000000000800003d153a997f64560831f16a0ae692eb602dece58477c04b70100f7827713a15115d868f19bf3dd2fe435bac3d6a441315ae9010b8416b182cd7bd20f08f861861b0d136daba791fe394e29c07a2ff4838a906cc4418130d441ae340d19c2d4a7b4355ede055bbcd81cd8a962ced569e5c89e86ae0334bc5d5a0d10627921e52867010001	\\x3d083b41011e37ca689f57af03a336422aecce24bdb2a80e2640d7870bfa007b9b9502890dae4682a7a16efc7815b16a912c76f533efe5d07894181628e78b0b	1679046099000000	1679650899000000	1742722899000000	1837330899000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xfafb6755fd4a087afca014252674a1870ad342ac02d449b47b8c35993348697961a1102a7394824650547ceec22af3974b3d1f6d43a748993736be589908a2fd	1	0	\\x000000010000000000800003be1ac128ff31c8447efc5fa31cc925c9aec6bdd439f5c03beb29358dc42ae6dd42f42877848e3d7d546811ebc43beaca33b2a66d9026129a0391c663c84178850625d4ac12d8e7fc0e8a154a54b3f1d658a552611cf27628c0616cabed6dc3155e4eee38c704e398d0248df80477dbd083e4fc3057460011d6592b612ea58381010001	\\xcba122104c6124f0e6efb4c8c90a59aaa440ff33f1e4e0c423c3d2e23bd9df2744de4ea0a8681fc083f240c8c5039c551acaedb845a67c21552e65b187bb0b0c	1678441599000000	1679046399000000	1742118399000000	1836726399000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	1	\\xd523f396ea8c28c420aacf7d9a1027eded3b92081e97d918f66bebffcf8dcd51789159b3a6f6d5df53a1b2e74931be1dfb158f43d4ea940e7476ee98f82cce7c	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6f03d706ca076a65d9b98103d0d8cf8caf1832d0ea19cd465db15ae8d6487a4bd2406811a5cc0a2373299ab695b9d17397dfd4caaf284bb41e56459028548727	1647612119000000	1647613017000000	1647613017000000	3	98000000	\\xb751f25c4d3868ffb1981c44720cd032082ff9c07ff2e84fd582698a7d842d9b	\\x547f391b283fb1b15690ea726ae38b85ce8c97f16aecce29e34744e0df371f0b	\\xbac2fdb14d6e07b15ee500f6566c1985257e3743733bae4a6e2fe7e9a6c2b7346938717daec19341181159721d908139d550075c9defedb8264a17c7cfc5570e	\\x2a79e08adb46aa280b8af81ae2f530f66f9a854e0f9cab500f4e5fd6fa7c9ad6	\\xa01d683ffe7f0000bf1d683ffe7f0000df1d683ffe7f0000a01d683ffe7f0000df1d683ffe7f00000000000000000000000000000000000000a8d92d24bd3dd6
\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	2	\\xb993dcd46b2689fbeaad8644e6d1080b161b02c6bddd0f0c41e7660737eeac508d3d8bc28d31b630fdc2285292adac81969e77440c797fdf097ad978df1578d6	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6f03d706ca076a65d9b98103d0d8cf8caf1832d0ea19cd465db15ae8d6487a4bd2406811a5cc0a2373299ab695b9d17397dfd4caaf284bb41e56459028548727	1647612126000000	1647613023000000	1647613023000000	6	99000000	\\x9cc8bd44dba52ef1790ec5bf8eb8e4ff43f3f58a2c937af3b61ea7e00d6db260	\\x547f391b283fb1b15690ea726ae38b85ce8c97f16aecce29e34744e0df371f0b	\\xb3854cdee2be1726eca38172b58f1ae0ca21aaab8fa2b96cfb67244c8b81e1d342e6931c45bf1bfbc9f04793446c67fd3c0da8d557a5d1c52f65dcf6b651d002	\\x2a79e08adb46aa280b8af81ae2f530f66f9a854e0f9cab500f4e5fd6fa7c9ad6	\\xa01d683ffe7f0000bf1d683ffe7f0000df1d683ffe7f0000a01d683ffe7f0000df1d683ffe7f00000000000000000000000000000000000000a8d92d24bd3dd6
\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	3	\\x4d84d4127f7d2ae8ed6e080418188f45a06bb389bc4934272dd0b407bdcb81e2dba4676ffc898440c949ab8df0c0ac4103f319a28f1a19608d1d6f7501dfcf94	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6f03d706ca076a65d9b98103d0d8cf8caf1832d0ea19cd465db15ae8d6487a4bd2406811a5cc0a2373299ab695b9d17397dfd4caaf284bb41e56459028548727	1647612132000000	1647613030000000	1647613030000000	2	99000000	\\x005d0fd25a6b468b208c8dd76b2fb489c90c4141069cf8a49fd1f90b0c9dd1d0	\\x547f391b283fb1b15690ea726ae38b85ce8c97f16aecce29e34744e0df371f0b	\\xe82edf788d78e5b3956fe25656ce5900455f9772e38edf179353a3d0f361d67437d9a6ed8f7ed82798f5a886e38497d43ad8686ff66a702370f86d3923474205	\\x2a79e08adb46aa280b8af81ae2f530f66f9a854e0f9cab500f4e5fd6fa7c9ad6	\\xa01d683ffe7f0000bf1d683ffe7f0000df1d683ffe7f0000a01d683ffe7f0000df1d683ffe7f00000000000000000000000000000000000000a8d92d24bd3dd6
\.


--
-- Data for Name: deposits_by_coin_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_coin_default (deposit_serial_id, shard, coin_pub) FROM stdin;
1	99372245	\\xb751f25c4d3868ffb1981c44720cd032082ff9c07ff2e84fd582698a7d842d9b
2	99372245	\\x9cc8bd44dba52ef1790ec5bf8eb8e4ff43f3f58a2c937af3b61ea7e00d6db260
3	99372245	\\x005d0fd25a6b468b208c8dd76b2fb489c90c4141069cf8a49fd1f90b0c9dd1d0
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	99372245	\\xb751f25c4d3868ffb1981c44720cd032082ff9c07ff2e84fd582698a7d842d9b	1	4	0	1647612117000000	1647612119000000	1647613017000000	1647613017000000	\\x547f391b283fb1b15690ea726ae38b85ce8c97f16aecce29e34744e0df371f0b	\\xd523f396ea8c28c420aacf7d9a1027eded3b92081e97d918f66bebffcf8dcd51789159b3a6f6d5df53a1b2e74931be1dfb158f43d4ea940e7476ee98f82cce7c	\\x33f8441bc20a5469ae844b85e7ae537b9800fb2b4d446655a385adf16d6b23953c05407e2f2e210cedb3a3e7c3beb2d009e118acd46140bb573a013f31322b0d	\\x06716ca9809490aef9554723c42531a0	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	99372245	\\x9cc8bd44dba52ef1790ec5bf8eb8e4ff43f3f58a2c937af3b61ea7e00d6db260	3	7	0	1647612123000000	1647612126000000	1647613023000000	1647613023000000	\\x547f391b283fb1b15690ea726ae38b85ce8c97f16aecce29e34744e0df371f0b	\\xb993dcd46b2689fbeaad8644e6d1080b161b02c6bddd0f0c41e7660737eeac508d3d8bc28d31b630fdc2285292adac81969e77440c797fdf097ad978df1578d6	\\x5f160d3316b2331084f465e4560094d3d0a96aa565ee51a4f252823c1b0256d0e19e4fb15cf787a2ef58878913bdb548ea91eb6933979fb8b14450e5d8158a07	\\x06716ca9809490aef9554723c42531a0	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	99372245	\\x005d0fd25a6b468b208c8dd76b2fb489c90c4141069cf8a49fd1f90b0c9dd1d0	6	3	0	1647612130000000	1647612132000000	1647613030000000	1647613030000000	\\x547f391b283fb1b15690ea726ae38b85ce8c97f16aecce29e34744e0df371f0b	\\x4d84d4127f7d2ae8ed6e080418188f45a06bb389bc4934272dd0b407bdcb81e2dba4676ffc898440c949ab8df0c0ac4103f319a28f1a19608d1d6f7501dfcf94	\\xc26bc75a14120a80ec30b1c6c805516bd15de40fe4291fc72f81e24709dd7227f52a84e8ff7c1741a5f8928c15c44110b9efd9843bcc79551c45ae559ceb8006	\\x06716ca9809490aef9554723c42531a0	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
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
1	contenttypes	0001_initial	2022-03-18 15:01:39.847002+01
2	auth	0001_initial	2022-03-18 15:01:40.032157+01
3	app	0001_initial	2022-03-18 15:01:40.169359+01
4	contenttypes	0002_remove_content_type_name	2022-03-18 15:01:40.183835+01
5	auth	0002_alter_permission_name_max_length	2022-03-18 15:01:40.19333+01
6	auth	0003_alter_user_email_max_length	2022-03-18 15:01:40.202271+01
7	auth	0004_alter_user_username_opts	2022-03-18 15:01:40.210903+01
8	auth	0005_alter_user_last_login_null	2022-03-18 15:01:40.218658+01
9	auth	0006_require_contenttypes_0002	2022-03-18 15:01:40.221656+01
10	auth	0007_alter_validators_add_error_messages	2022-03-18 15:01:40.228793+01
11	auth	0008_alter_user_username_max_length	2022-03-18 15:01:40.243601+01
12	auth	0009_alter_user_last_name_max_length	2022-03-18 15:01:40.251268+01
13	auth	0010_alter_group_name_max_length	2022-03-18 15:01:40.261031+01
14	auth	0011_update_proxy_permissions	2022-03-18 15:01:40.269509+01
15	auth	0012_alter_user_first_name_max_length	2022-03-18 15:01:40.277329+01
16	sessions	0001_initial	2022-03-18 15:01:40.309347+01
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
1	\\x6057a91559f5f464b73a38fa2d50bc2477f4cc80b8f20bf5f0ac059bd4dbf078	\\xb29657f502301dab399877495ebb03970ff5440230c68837ff2045a8c1762b8116419e8ee3afddee85a4eea9e849e4320c198b3a66e7aca0225263f9000c2201	1662126699000000	1669384299000000	1671803499000000
2	\\xc02b4e16601dbcb190c2ae0a7aeb475efd1f9556e414e40e99010810c82442ef	\\x0efb406750c53d011f9d6b4631eab7a2fe00bc1a89a580cf46ef9a15fd8acffedfa5b5275ef7d778fea3b419fa19f0c3ea8152b1056fbfd1ea0ed9612dac9d0d	1654869399000000	1662126999000000	1664546199000000
3	\\x2a79e08adb46aa280b8af81ae2f530f66f9a854e0f9cab500f4e5fd6fa7c9ad6	\\xe38561d0e5c90f740bdef1507a715e27d177f233b73fc637d456b4b8a21471c2232928134b45c7ca3af7a7cd626f3b933ea404d722ee2c9ad08c6f415306d401	1647612099000000	1654869699000000	1657288899000000
4	\\xeb585c683f594574ddf068d0a7471ae7e55f1ae9a868918f8e9584bba1c3246d	\\x53ac4df6eb2b025e6fedfbdc30de5d56f8661c2c922f30951c3e49f5a3b951ab1b3e71fc892dea43cd9bae8757694d566ee47c6cde1955f855078514bedf0009	1669383999000000	1676641599000000	1679060799000000
5	\\x9972cb7d0277d89188884ff30e99eba360aeaf6ab4fc1c68700ffa8bf2947923	\\xaf97f6fe759f4f8cfb236fd91a4d11a5d20cfe195a40075609db69e924efd36e582044e7371b46bf3758f3615668e3580a15ac9504f755d744d64e5aae480706	1676641299000000	1683898899000000	1686318099000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xce6a176c49061d0f27fa6926ff8c98994a81a9e0e11437e880585a7178080c36865069590d08211f953a0da59e8fa910b06dd2d4f57ab68818ac6bd56cec6e06
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	311	\\xb751f25c4d3868ffb1981c44720cd032082ff9c07ff2e84fd582698a7d842d9b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000e2316386867caba943458f0b6b7e74d1f224b774ef8aeac3f48acdf66ffa983630c323bcea682e88b8c1b504981a6237bf8c2acc9d10c606392a56c4e1373f43f85d5206ac7f8860c0bddfe86c5b6f3080bbbf836838bd559bee0b47789d8c2b72034c76b77b88d3f599040be9e85463cdefcf82aa2d189a0ece90229b95c4eb	0	0
3	394	\\x9cc8bd44dba52ef1790ec5bf8eb8e4ff43f3f58a2c937af3b61ea7e00d6db260	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006d1ba3badf30ad5e5e0668664c18185c1a81b2de9342b3c04c94754fd8c00c0e23fea091f9fea0d48e59928bca560d564b789369718cd3cc19239e2813a839e44d8a2d4b6d2671ff1c12ad1354334882d3f0768709326418f2fea2b97016a52b822581fab33bb01c2f55e06a798e154cc68c9506267c140d9659f08e84619b52	0	1000000
6	53	\\x005d0fd25a6b468b208c8dd76b2fb489c90c4141069cf8a49fd1f90b0c9dd1d0	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000074884b5622f6ffea84ef189350b51c224c75974654d0ced93b58fa7651aaa2a80ee1563978acb3fd46eef9dcad84db55e79cccc4882329a8fa04e116963e6e1bd22985f4adee8d26578d24c56c1c4ad0df1f89539a1912f612fbe4ba6f2ba29e36f29d80fb13c983d757d204a9c20207d4ca0b3f070c0f8f742af885d4c6e2c6	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x6f03d706ca076a65d9b98103d0d8cf8caf1832d0ea19cd465db15ae8d6487a4bd2406811a5cc0a2373299ab695b9d17397dfd4caaf284bb41e56459028548727	\\x06716ca9809490aef9554723c42531a0	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.077-G2SAG79GB7A0W	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373631333031373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373631333031373030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22445731584531504130584e36425044534734315831503646484a5148474350475838435754484a5850354445484e4a38463935583447333832364a575232483345434d534e444d4e513738513735595a544b354159413242504746354348434735314138453952222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037372d47325341473739474237413057222c2274696d657374616d70223a7b22745f73223a313634373631323131372c22745f6d73223a313634373631323131373030307d2c227061795f646561646c696e65223a7b22745f73223a313634373631353731372c22745f6d73223a313634373631353731373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22473531525746504b503946505a46305647464a425238424e31424e345258533956394450515837364658355a4e5950594b383130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2241485a4b4a36533837595256324e4d47583953364e5257424751373853355a484442504357414633385832453151535133573547222c226e6f6e6365223a224d43313044475151524b31305051525038503942454e31334352393333453532415931574a525a4e3558384430374d4d50463747227d	\\xd523f396ea8c28c420aacf7d9a1027eded3b92081e97d918f66bebffcf8dcd51789159b3a6f6d5df53a1b2e74931be1dfb158f43d4ea940e7476ee98f82cce7c	1647612117000000	1647615717000000	1647613017000000	t	f	taler://fulfillment-success/thx		\\x86712ee81482c59f142dece8f34a3640
2	1	2022.077-01XPAAA6QPS18	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373631333032333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373631333032333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22445731584531504130584e36425044534734315831503646484a5148474350475838435754484a5850354445484e4a38463935583447333832364a575232483345434d534e444d4e513738513735595a544b354159413242504746354348434735314138453952222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037372d30315850414141365150533138222c2274696d657374616d70223a7b22745f73223a313634373631323132332c22745f6d73223a313634373631323132333030307d2c227061795f646561646c696e65223a7b22745f73223a313634373631353732332c22745f6d73223a313634373631353732333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22473531525746504b503946505a46305647464a425238424e31424e345258533956394450515837364658355a4e5950594b383130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2241485a4b4a36533837595256324e4d47583953364e5257424751373853355a484442504357414633385832453151535133573547222c226e6f6e6365223a22324d3752515642574750583651365a3430334d4e584133323838365334595648483046515443575753425756324734564e304b47227d	\\xb993dcd46b2689fbeaad8644e6d1080b161b02c6bddd0f0c41e7660737eeac508d3d8bc28d31b630fdc2285292adac81969e77440c797fdf097ad978df1578d6	1647612123000000	1647615723000000	1647613023000000	t	f	taler://fulfillment-success/thx		\\x8009ccde97d24e7f3e030d60b1186f81
3	1	2022.077-01JCRN6A65K2M	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373631333033303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373631333033303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22445731584531504130584e36425044534734315831503646484a5148474350475838435754484a5850354445484e4a38463935583447333832364a575232483345434d534e444d4e513738513735595a544b354159413242504746354348434735314138453952222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037372d30314a43524e364136354b324d222c2274696d657374616d70223a7b22745f73223a313634373631323133302c22745f6d73223a313634373631323133303030307d2c227061795f646561646c696e65223a7b22745f73223a313634373631353733302c22745f6d73223a313634373631353733303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22473531525746504b503946505a46305647464a425238424e31424e345258533956394450515837364658355a4e5950594b383130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a2241485a4b4a36533837595256324e4d47583953364e5257424751373853355a484442504357414633385832453151535133573547222c226e6f6e6365223a22375450434e395142414a4e50505135523337565752513854413538575247483952364a4e455646314a31374e5739425131524d47227d	\\x4d84d4127f7d2ae8ed6e080418188f45a06bb389bc4934272dd0b407bdcb81e2dba4676ffc898440c949ab8df0c0ac4103f319a28f1a19608d1d6f7501dfcf94	1647612130000000	1647615730000000	1647613030000000	t	f	taler://fulfillment-success/thx		\\xf4e45d9bbe63f0a7c79c4c8f5fa87224
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
1	1	1647612119000000	\\xb751f25c4d3868ffb1981c44720cd032082ff9c07ff2e84fd582698a7d842d9b	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	3	\\xbac2fdb14d6e07b15ee500f6566c1985257e3743733bae4a6e2fe7e9a6c2b7346938717daec19341181159721d908139d550075c9defedb8264a17c7cfc5570e	1
2	2	1647612126000000	\\x9cc8bd44dba52ef1790ec5bf8eb8e4ff43f3f58a2c937af3b61ea7e00d6db260	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	3	\\xb3854cdee2be1726eca38172b58f1ae0ca21aaab8fa2b96cfb67244c8b81e1d342e6931c45bf1bfbc9f04793446c67fd3c0da8d557a5d1c52f65dcf6b651d002	1
3	3	1647612132000000	\\x005d0fd25a6b468b208c8dd76b2fb489c90c4141069cf8a49fd1f90b0c9dd1d0	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	3	\\xe82edf788d78e5b3956fe25656ce5900455f9772e38edf179353a3d0f361d67437d9a6ed8f7ed82798f5a886e38497d43ad8686ff66a702370f86d3923474205	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	\\xc02b4e16601dbcb190c2ae0a7aeb475efd1f9556e414e40e99010810c82442ef	1654869399000000	1662126999000000	1664546199000000	\\x0efb406750c53d011f9d6b4631eab7a2fe00bc1a89a580cf46ef9a15fd8acffedfa5b5275ef7d778fea3b419fa19f0c3ea8152b1056fbfd1ea0ed9612dac9d0d
2	\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	\\x6057a91559f5f464b73a38fa2d50bc2477f4cc80b8f20bf5f0ac059bd4dbf078	1662126699000000	1669384299000000	1671803499000000	\\xb29657f502301dab399877495ebb03970ff5440230c68837ff2045a8c1762b8116419e8ee3afddee85a4eea9e849e4320c198b3a66e7aca0225263f9000c2201
3	\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	\\x2a79e08adb46aa280b8af81ae2f530f66f9a854e0f9cab500f4e5fd6fa7c9ad6	1647612099000000	1654869699000000	1657288899000000	\\xe38561d0e5c90f740bdef1507a715e27d177f233b73fc637d456b4b8a21471c2232928134b45c7ca3af7a7cd626f3b933ea404d722ee2c9ad08c6f415306d401
4	\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	\\xeb585c683f594574ddf068d0a7471ae7e55f1ae9a868918f8e9584bba1c3246d	1669383999000000	1676641599000000	1679060799000000	\\x53ac4df6eb2b025e6fedfbdc30de5d56f8661c2c922f30951c3e49f5a3b951ab1b3e71fc892dea43cd9bae8757694d566ee47c6cde1955f855078514bedf0009
5	\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	\\x9972cb7d0277d89188884ff30e99eba360aeaf6ab4fc1c68700ffa8bf2947923	1676641299000000	1683898899000000	1686318099000000	\\xaf97f6fe759f4f8cfb236fd91a4d11a5d20cfe195a40075609db69e924efd36e582044e7371b46bf3758f3615668e3580a15ac9504f755d744d64e5aae480706
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x81438e3ed3b25f6fbc1b83e4bc21750aea4c7729da5b6bf4e67f4bfafade9a02	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xc1d397c9858ce52f7ac0c594d0478042690ad623c987202114f59e281557626870af85bab0ea8b968a7ee9cde493e57a3e6a00a606da1b84c10ac85260fe980e
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x547f391b283fb1b15690ea726ae38b85ce8c97f16aecce29e34744e0df371f0b	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xf10cfcb83458b35e6e877c36f5a2553cea23fe838745160b8b19711ad125986b	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647612119000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\xfefa4bba4f7d67520ee54482fe7932058f3c0c92be8e03fe1dcb10d3a71a004d4e10f7985a695428767fac508e48299b3fb94e3d406fb0b2a5acc8b92eb2380f	3
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1647612126000000	\\x9cc8bd44dba52ef1790ec5bf8eb8e4ff43f3f58a2c937af3b61ea7e00d6db260	test refund	6	0
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
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xee1d6f1c9ce578f8226e2ed650d1ac96c2474f6dc947768759b4330f60be92f2c910e7ef33a8266a7b3422884cd67701140a927a9e081ffd2921c5542589eba8	\\xb751f25c4d3868ffb1981c44720cd032082ff9c07ff2e84fd582698a7d842d9b	\\xa4584a233022d3a2918e58bb571ea8f9e067ba9f5b35ef6fadbd3a9f45a90761137be75b1e8d3151318bee519e3d4ce2e647a1570abe20a02748913bb47f9101	4	0	1
2	\\x496a9d21b1014e224308435174d5ceeefc101872af6d6861f219ea6733d94ecba24607b4e056d0a56ef79c47aa072edd9568e991a10d6af120e7402f2f5adc40	\\x9cc8bd44dba52ef1790ec5bf8eb8e4ff43f3f58a2c937af3b61ea7e00d6db260	\\xf86d66a8c48eae8289cf9642274f35aa6beef539efb34fab5f1214245aa078df020e4792976bdee97d7d511bf6dee827ffcc1605af675b41034e97272c59be02	3	0	0
3	\\x085789dbc78f93c4533382ce6813be622d0a7ee5f2ea152e2b7ba697fa9b9aacc335f7d2f40ba13fc0e0a2b10faab1ef37d79a30e8e0db8bab9f6aeea510de77	\\x9cc8bd44dba52ef1790ec5bf8eb8e4ff43f3f58a2c937af3b61ea7e00d6db260	\\xd567ca067977d07830bc6d044fc3a5ad84e73a25a5967fe138173aacb71a9fe6e6f0734a9d3bc20c12e1c13b38e5f13e394a52c1ebd2c117f267452d47c0030d	5	98000000	0
4	\\xcdfb28ff043cf5796e54c44bc1149c0608fa703c7c24995855e163abe890743fc9b3f782d88605a9a71cd76b617a25ac222e386762ecaf37e6bdf2fb3aabe60f	\\x005d0fd25a6b468b208c8dd76b2fb489c90c4141069cf8a49fd1f90b0c9dd1d0	\\xfeadedc979479bfd4af5578d6e89d5245f6e7297f065d352012603fa34ed41c766a4a1a20a9ee186d217514db7cff23c988006002ff5df7163b709ec5b65db0f	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x15027cd14b3c7b9975bdab1a295d1b0aa7383118779e4637868ba1a8869640734f487679efbf01de47e4877ed4ac5153cdb5b1c0431af0efbd338883db8df00f	356	\\x000000010000010034e09e8f0fbe090ff24eff38205a805b672211f509ce7e6f1311743850e75729c7805d3897784b810e8e11eb6a8c2fea306083260c6320f665223c68fe4fcb099ff8f1e2231549d89ff281a8cec5302a90ab4aa9f87090b968bac2fc73576ea6daa22d7b768c13e3c73c7786923807ceb0c88500f756b6a5b9d4163afd37589c	\\xaef95f7a786fa65764898dc92525d5d7aaa7656b705f34d11c36d96fbefeb9ba531815d3023e96a225fed28b291a30e2839df4de33a6ad9b8d0281544a9aba83	\\x00000001000000019cee1aff79f6488fbabdee8931de8d6481822f59219be9399650d20c31e87e3334de79d13824655b747e483266d808e102e75edd4980aab4fd729e3304a456345e00fa1b7512a139c70715d9a666a4aa444b493183134a9e76f15e5ed91ad200df57b89a68bb5829e7eb509bb4b1421b3cb2c382b18e090fe8a19bbdce4e8fb1	\\x0000000100010000
2	1	1	\\x8225aca17d55c9d1cf0e62a3ead7cabd828c71ef6ba6525fe50476d5c6286094a358a129384ccb5b344c57d9d928bb3027aaebfb24c94db1bcd5c21f8a26f00b	105	\\x00000001000001003d233e0c1116458a432df27326443928299a1e3775f25c7625b3423b4bb2da0130c5bbdcd2dc2307fa107b39f601c1d0f88da18338f001056c69f637965538108c2a6c5583d6a2937ef2ab0fc947033a1a9d64a9fc0c8c79a0c9728281cad0af2b5e68b388a5f76ed109f73bf584cdb573893288e37b92d20651c9fb4e7e5d9c	\\xffbc2fda7130f0dac1d73c9edee4b50f941708f130cea446ae9605fc79123399e4810be960bac15d3566583ad8f710e96f5d0cb526e5318552fed85e830c9924	\\x00000001000000018dfef9b5766edd2a1758b53af4a87c3b091c870ed1c04c4c91363f69099a750f5171bf50145aabef90e1cfd79e97078f566a53f96452050ef0561cea10c9087f67967d53c4ce7245d97a954b75fb202c1a6bff39ed960d126a554923901e0a66a3a9647fa5b4ec7f4acaeb8debe33b06bb16068cb69bd0e7e6cb44805b2e4a72	\\x0000000100010000
3	1	2	\\x77d00c5870eb4d0ba15e3925429603d8f7e5d93bd6762807900a651234277f2332d212dbd28e5e8dd34ac25e34302cdc01af12530d36b33365fe638510689302	65	\\x00000001000001008e2792e326b4746c8aa37ae5d9b51de607c40ed04002182c01de82e5389a177f9c33f777a623ed7696208d7f7ebe2df01554d82e5fcfb3d12f7841c1291f10d6ef8af20676d56a8fa3af2d9d81581f75b59cf7de9c90c68fce2da68de89445202e919963cac6fd80d44b25c177c88e28a31f4da76b0e8d3cfe79d9649b64d580	\\x5aadd1dbb59317182e8fe7799cffedfa1e9d4692fc458006d89395c290279e34d271eda66b59e14faffff6f3ca84a54c34466b57fdec8b36643da44ce852212e	\\x00000001000000010d3c937ca13428a9f1d03a24e736b259517138e1f326454260345f516e76fb77db48a3480448bcb1cc76e3f7ee2f6a90ed31dd99073dc4c001c6895ee5838dfdec461396908faefc069f3e1fb5fd2ba273b34ea7781f6cafcddfbfbd809edc62a9dcc06c06b05eb09aab7a60443e2859d3577959e827fe8fbf39a96715c9a88d	\\x0000000100010000
4	1	3	\\xc2c5e1b8952dcf231594a5e0e9d41f3f0f15b4583e9ddbaf289d5a96677b32e4020dec489b1aef3d20076f31e3c344410cd960d31df5b610e1321e865d98df03	65	\\x0000000100000100cb7ee9539b8d80f819d63b38f5b9a76882335bb6971e04ca685109b6a2e0650a7e9f0ca560fd3328d943fc00a450092467f78a45f3607b46d08523c1734208ce8eef6445cf007732959241d856896de83273d410fed6434ac8df92b6f35eed000c55d959686e652f5054898a654dc7babdca3328d690a535b2d6c6cf26d2a97e	\\xcc56da6be01d8151eb33b7dd74265b64af30b677178f194f666e7d907a87f571617e333cfe4d8850c85ffbb75fc30294a08d6428d8dee344085ebf40b3fdd98b	\\x0000000100000001176693162c2ca9e8ffef42559d148436f80046ec27d5914a5c36172988900a9791d68dc95286afad83f1935c14cd437ccebb44d3093c28762633bd6b69111494f966174999bfb76b3ef88d47030ac3797eb6792c43d2150a11422326668af67ed95d06b91fabe7838764a626c8abfba96092f2b88bc294d26ddc35845dab337b	\\x0000000100010000
5	1	4	\\x03f9129df32178ce7005e0925ec24bb540f5b31768c223afbfc5c4bd8193ded3cd12636574e8667a14f9cfefe6a64271b04dd1538af1c27a76d1221290309c02	65	\\x000000010000010096795d01f76362ce77661d47ead599389550fefc24a6ffa0b079184b8e9f7916141427e4aaaea713a6318626efbd375dfa4fd27954e0f435fa22a71d2c1d0cb5941ad297170cab287290b2eed9338912a01b6a311a96941e23c792b9cabb92de757ff8799a0ef557085e0b87ca50cd7a9e84fe20a731db900a9b6788e2aaec4a	\\x618294319f4bdfa708a2a66d5cee3ece1d0ef3be546b4b2e8dd62a6a13f161d9790cf77cedf43cb0a35a87e6c761bec79d39ce7ed1e4fa34eafb61c5f1f28822	\\x00000001000000019ccd963c423d28701a7226ea270d9bdeb093dc1d4f841c3710a059db89e6be5a4d8b362fb74e3d60c773b6ab771c961e8fde091152800907d3028c4fdf48da5a77042108bbd9fa5d6483672a7d8a9a1abe56bd356e23afa3d282348c4db6375a687596f846eb4b7f7ac34b65ff0f52d5320d183ba07237da9b5ea9d3f1b9c783	\\x0000000100010000
6	1	5	\\x0040f0df4b8dbd8e7464093f87f4e471fec09228d2088183ba8121cc6fac96c58000ab3d8f37211f58fd823605af2126236da421c33e5014534be1307857cf07	65	\\x000000010000010038db091b069adc2e379f795af3be7b2e02f93f6a92485c7cbb6c5215832828a2b7862b377b7f361a6bedcf5259d94570d95fc0e5fe69b0df94b257e4cc804ad50b01da1ba70426cb817bd03b704b52d9ad33a95f3103be8d7c03580ffe8b4e3e52b7e4c6dfd8ef324583210529ac3f73f1e41e1f4cc7c642348b024b7896d692	\\x841f459012ed4ed8fdec955ddf4b828c742677990acf68b62c60df86d54593582418beebeabe0c8dc5a832d700e2c6770c9f6e1e93078dfcef5e080b9d824fbe	\\x00000001000000015c5a9dc9e9f967c743c4ca906ca61e3c88bd93d1ab433b3fdabd948ca8ca5f56642ab8ada36d036c04e6bd214083a07a9fcbac196cccc48561e3c485246a97be472ef27892161ba4c516bd01d4c3cd4283f64223dfed8abc82b15ef477d791b4f7771ff34be9f87f437bed53f9f564d0d3b9fa176d571379a7a4e20a1f151c49	\\x0000000100010000
7	1	6	\\x9704f53b2b2cc326f6fcf0e3bc60cc5c5967525fa2506acde862b96cf23eb9c1fa54944393de06e0a2415488d065285d31747a645800c75530f7b0d9d9755e06	65	\\x000000010000010045d8301b0e9599524f1ecc378e5140e5dcb1909f644bf1d41601ebef83a06c5e51a763d916dee02b04bb5cfde1ac463ebcc205b78dd38925cce5bd6425132e32c9bb160477e2fd4b2988a86cd7d6b18041152ba42f3653f21ca0c9ef4b7e6727661209e3109d8d3144a0bb40f1dd52a2cf0224df9ca5dc4bddc8ba68d11592a6	\\x33ae3ae44e36c4052a0239922604bc31de3e48568d61ab53ad6b78b41e339e3e7cb216822ba07af87d46969737ec2dd2bc4b3d4318c55a83f077cf29f6458cad	\\x0000000100000001617350fe216a41bc548fa93e0f4c8cbd5bfc062b3bfca4f57c0b3c1dcf5acfab768d8af1509138f76d4c4f0ea9cfa0c8ba1d2350ad94af90a5ca85f2a82cc61d4f807c5844b67ca49a6df079fc1ee25696609a0d6d08529815c4e226e40d286834c692f0ef4db8c4b1379deade222ef681e18eb7232fdd8ad6cc4527ac00a852	\\x0000000100010000
8	1	7	\\xee807fe17b37200fad51f46529660f3e41bae809fb0028730afd6aa4f82a38784e0acae2cbfbe60fd656b0744181ae7d2b117581f2e3ad458a6bc8b85d2b9602	65	\\x000000010000010092aec86f063458c141a3e0c12d697c0125382ed2c180c7ba651d230ba4a4b2fce3e9f9ff05ffae850cc5a533c6bb7c4c6e463a0550d31c1d9a5fa597f0ca549b12e4338dc6df1594e763b181ac5de7dacf8c8a4b1d576dc33849377635264aded62909ebbb3b27d8cfde7a02059f0aa5de69a37b701963fff5c95582ce58e669	\\x8875e333e5772c7f365a7f79802e0951122b6889031c54a78c22b7ed2d4bc1874c2c5b5383d65136f1d11fa48e2e75de6e84b167a6a1fea98ab9d5ee01a745ec	\\x0000000100000001917cfeba0a7d9e3f65339b11803a4b63db9cb005f41e281ca8a9117601b37018139932754424a39d273d86338d5bc429b07ce1ff8f2234ff988dc2e3f65e459117656908da305337167554f6d9233d993234c6193190a02633313fbaf8261314e334b15fb380162a5e02b3ecfb95739d8f693459017ac588803573c0465f7df4	\\x0000000100010000
9	1	8	\\xaeff23c7ada425aacfb5abb1bca71130aeae72a1e7b777e3ff4346fa8148254f1c6b74af63c0e7d6526858a0f1bca10bbc033b282b78851862bd628cfeebe803	65	\\x00000001000001007c52e2e489d0b21ace1950c2864208b5b871fde2a666c99ac3e3cbf3c73d2bb5f6715bb460791550eeb196192a6f57867b649cdae24f67f8c41b1c831835f7981fa0da6548437c656ff657d6dbca27473f2fe07303e9f94158c06e3194017bc983f26fed8be8ebee3c149727104fd37404b0ae529090ecc137bbf87ff0546881	\\xecba4d52d78e00394295d30bea4781c44059f863a4f69709936b1c1571f33655ffed380bc1ec1efc3907a19856e501c2724df15630abe9659d868fdda42fdf79	\\x00000001000000012b8797fa6f9e51b77e1a0a466354554afc5ffe4bab119c0efa704d8ca2faca73510ca69d80c03b52bd921bbf9ed1ba272e87d13819c637d47588fc12e5fea12b8cc6de2dcb6313b62df95d0fc20249351a3a8ebe9a0038241df313407388c92d7807694fdceb7573b3b869e4e3b97e2298685b9b2b82aa1d465c6b4260039595	\\x0000000100010000
10	1	9	\\xca1b14b51f4bf056bad9016f94cbdc78615912bf33ab4570cadf7180590e30bb599f931bcf296df97870473f5723c7c90de82f53c05a01757a15790a221b3c0a	65	\\x0000000100000100127dee9b42dffbf123a75fa4824941eef11d37ddec89665fec64836012eb818abb33a6cc4e73ed3a0f4ec2a9ee097859f8d6492f311904d7636c31bd85cf1a2a4ca2c3ed7666f73473d80817bbdf15bc6e11f79a0df36de9aa75947fc4adf19c4551e1501b7580bab378c0ddc25571ca6c473fa4520c735e439bff3d3f2d6c9c	\\x5ef186b1413b5fa436fefa779f3ac25d452df7c116a41ae1fb1b8752ad7a6c85239d1b6e92426a32125d8b7844d5eea4a73d70bf9c0e54e481e78e5df21003ba	\\x0000000100000001aeef9b7ab2f8ce2d92119fdd0f44d72242a0d06b55a0e4a1541e4f2146a771d2940023fdcb8e012bbee3a202b53df7a06b81b02070bd980f6bffc2651d3efdadffcfe8998d9207943fbabbbae14809823ef5886f7e94108a2998dda4681ded4b18c6ab32f5418c69a27138c275fbf1f8e912027c6e6debbcc80f8a072fd3097a	\\x0000000100010000
11	1	10	\\xf986d513faa594b36be3efaf9ec3fe8bded09b3815aa738b7d498d5a5b8d6e30e095259b823ed89d749134491694bd4c216953560c3ddfcc67a912c319533e0f	240	\\x000000010000010044558a96bd3e6c7c1bd1a82376ef5e97a03d3f4b95307bea8053d3c8ef3f49fcb5c5254faaed78a06e157076355f494936d69626be8811cb8aa7d735f96de42f6e0afaf475afcc8cf79a0c9147b8aed3c54637d3f3594e4970aed9551eef975a4672f13d6485c9f343d47c3505f2fd857d475b40b28d170723a71c8c7bea2122	\\x0a290509faa414a7b492fbc3aa29f2398c9da6d9cde76da2d3010bf14f1e3eee3dddf567828731f3da87671f65a0ab14895bfa4755493dc6ce8b78921b7adee6	\\x000000010000000171d7ff61042819b4b802c9c6b0bf53d49bc0e6622a8873378e8a684d7db86583c2171a74d26cf56797312ce529101dc0d94d58ec8417c68e8cd1234ba59d952f0530999e141b10ea3e3421bd1b87b0fb23d78473ea8223cde6b89ef4b1a534bcdc3e82dd8b007c0cdba0ad4241f2cf08669df6df1eb91b7c4b3c585750dc6d03	\\x0000000100010000
12	1	11	\\x2f2681c36bfa2a7ae0c87ca78a05942234fa1cdb794e0d2ecbd28a83af1d6785801c38d56d3bf3f368396975b4fa0d3f7825add4558d8c0ec488fe8efa985202	240	\\x00000001000001007472b7065372e3f9329e0506eed9b0dcd68523db663238bbb167f887e59c4159f6e079d8b74f54974a22b81987e2e6410588d48e1c1bde5a0b78f763e520e980306ec3d8b0213324ae2353a34da79110c9d1053ef96a6ab26e83fe91f0bb5dce55e2169214b2521341ac0c69e89a595b359091951363cee1a9fe7cc7bda9eebc	\\x4875edc1614c55f11e26da6e51c004ac79f6bf84f7c1c19064df625bdd44e27b5ab66ee5646ea827735ad382a1f60d39f6461a2e770591a0c594f5df4050ef1b	\\x00000001000000011ad8f153afaf9c94565624cd1eb5f5217fdf9070e46d83bb45b56926a812446a7fbda19d1ab5a515256e9557cd02f45746194d9deeaa62229a7722e7f834adc5def26f86f50dbc82264d04ae8bf331b5f96a474463d0e3b6ef3ec16a7946758caa088ae0594d6923cbc3fe6e85ad08d4c13b6c15f4828d40f85b9626b6e6bdaf	\\x0000000100010000
13	2	0	\\x13d34ce7cfa1fdb5621cdfed38708bd601e20f1d0e506a8b48c84d8773d72d344a1455a24a3708b5314ea438e4016e1f81ec4e0cfc65aa4383d6e2fc51818c0c	356	\\x00000001000001006cdd4664390efac2ca2ae6d455305d0b65189c4f665bb19b50eaa95253e20150a062c5351de45599ab736d2be8fe0e533dd7b10a121792924597a58593c05c5b113f81ba0f16009f005ab1149c407941099df634ce5a301c450f290aa82d23e8a660d8cacd9a60d8572b40448ce4efe4c6a6ec6061a78ca34608c7d753ac8f72	\\x456ff55c4355998b5ddb755b6674bb6b0e4c797d0b9a51937b5ffa94711f882266787994df0ef01a06d7ec385074baac582f806ad422621210517a6eaa9a10be	\\x000000010000000113373f306372f5f8cb03ba8e39cb366d28b8bd6d5425e6c9303857d384d4ce9e1f6194f3a855ce25d298b2fb3a0d0c327e54ba0e48d5300862ef91ad5b8e7a72e1e4428d3014a67bb73c8ab96efb51799efd43751e403667cc00d711e9c6e65a4701ba5fce4806f05e4e69cdc17a345ed7e5216968a0d5e52690e7ebce402e2a	\\x0000000100010000
14	2	1	\\xcafd53fab8e41adb781cbda7e9eed649723546333d7235d3f559de833e7d5077632c806dba889bd72f6fd921069b5be628271d2338d9b9d2d12b32636bc0f908	65	\\x000000010000010004b5155ac4301df05f748dc90d17c9db0dc022ab4bf525594bfa76780aa830e30248c5c9311a738b64ff4fde14ee55ebd5d6d5a3238a06d20d5ee941f58d1f66052ecf5a29507912c66d0c652b2a019cb89bf6c84e736f01c2fb12e257889d524a25ffcf7fdc62a3fe7767a075c44dd8ba29fda9c7187d1ec1512dc55e64f0f1	\\xbef7ace636c229d618d49ac8ba8868b1f206a2dd95fc80fedc42533eda45d37b7c463f63cc562c3c70dc53cebfe66ee3c514b23eb98af440642d69fdee7815fd	\\x0000000100000001347b1413ae3a7c2f3f2a1c12c3939ffed1cb42fa5ead5db388ef476f832fbe91976d3037800a6d66b87224b6cd26451eeb9965794a9e7e4878d3c41b58d1910354adf609f7009f40e29262a9aca067087ac6658061509e7ac1b721eed2a95c89587bf660887975e5749f4d548ba6708af58a7bfd0f342419eff681522bbfbc81	\\x0000000100010000
15	2	2	\\x432b80fe922f5c84502325f06d26f0d68e0ddde0ca0e8aa5807593400e5efd65630a411dd4ade000b5968c0c97ae434263ff18c7668680d39367b8a727fc6d02	65	\\x000000010000010063bed4dcd5859a6b43f1882b28e722bdb4210188b37460d912b42c33d361ba5730ffa61519bb27a4e3f9da248a179586da0f779256cc112ed889cb258dcf875a130f9403fe03651c6f4552ba20f231e8cb6d45fc26355375259635c370f6b8bf400d8b6047a5074acd0f4a5545f0507d11a471668d5d30c3dd146d6234791c39	\\xe711284f8ef2c896506854e709e6afb76297ba1fd9946453eeb70cfdf719311af67da90691ff2acecd1801336f674795e42d4f0023cecf18cf40bd2e41d92a73	\\x000000010000000164c29f218465c0c33cf9f6d9af9abe39341c012fb62e0bcdf35ae7fba4a2595311d7f9fadf468a789455f022b3465e86f3f1233fcffe33f61cf388e449279a0f7dcb0d9c6788ca2577fc4345f282494bed5f46eeb009d23c72c150a781c6d29a8058a4e7e49366f19c3009e444fb9dfd845d9f45f7877e669d79e3d1f7d91f72	\\x0000000100010000
16	2	3	\\x1e3186f49c3b852936ff5ae831950ca57856ce1a8a6faa43d9497b2513ce1f53d490668e09713d8c2821add33e8d83e55f9bb8f7daa67968f4b5300c42e4f50f	65	\\x000000010000010061aad045e9258b3746b0b6d1e8a06ecd42b48d742f446e6e76a7902bee9ef3ef211b81567da69ffac2da51b025d5ff3e8e088c849f935c34818a6ef4c35259e2cf7041bbfbe0f585bdbb76987c9cbe908a8a5ccfd8116ebbc714abf0b7d5937f63e8931790a4f203b07ce0a4a6a0f4775e9ea81f1a3a19ff2072443b92a65ae6	\\x438d6678f6166aeaec74c23b5c3aa2d9c5ee90f0ed3647e05c4b7b352df3a4070ffa550dd38973b5b7c532f2281036ab42e48b81653c059cf1e8c52fac5a415e	\\x000000010000000156bde6d26ccc803b96c5472ed3a29a257203b122e295f9c57f0f78f561c8e39443c0097ae6aacdc71df683757ccb17ca2a60692bc4f3a5d68bc5a0e0e6fc4dad03bcf73a5aa4d61737160a6d1821e32f7cf419bb197a3be08bb7256c08ef888594534617b49a76d6eba51acfac7cdf64ba94596a1dd01805f491c9d0df8f5563	\\x0000000100010000
17	2	4	\\x38a57226fe97d36159414a25534b942f627988b90a16fb72931eee1f9503bdaf5152cd951e1fc83189513ee0b9fcc9c50816dd7f5916a8dec9c65579126f4e09	65	\\x00000001000001008e2bd7fa9b63d516059e9f1befe259b2983b5ea1d634cd5befb4d15c5134e9c6f92b457e531db33b35b843e2b9664b65bdf0e2e3560f27637c15144e7d19d82ca40882a4aa9fa10f360341cb0966974283b44c6466a0784146f6c6feeffd03ea096f032cbd8bd11ced40ef1931e48105ec6a2c15531a98daee4994dcaec5b75b	\\x3f1e3cdc769b68bdb15024598ff1be036da8fd0e42dc0425b2a2cd8e1a896a1b71c9924a5a327c6b489a995dcc43bf92f637cca649e34b0e7998e495a9489c5d	\\x00000001000000015987f15b59ad9374f68acbc593739ddb8daf460f35e50324d64715b2be97a3296f94a6cc4a5bf1481136213d4baf2f9a678b299084711268634e749f486220bd7777edd4fd2564cbbfc9c211ae8daf422c4b296269e12112fd22a9aee2ecac0aeb4e4576869689f4ea78dda534c0f78c4fc80f39ca0680442ad70dc85f6294c1	\\x0000000100010000
18	2	5	\\x421773cf2e6ef1d2b4dcee2152a0404cbb4e5855ce7ee42b8ea9cc732d3b12c6b511c7ca96341a748afbb3c92c6feae9b07a33dfd4832fbff62aceb8c4f61b08	65	\\x000000010000010060c9745e9ec7020a01703e7c29252a315c39537eb2072d907beb6b73447841a97f8698f7bb2951eae4901f47cc2fba880af15c9022cab9f40dd6437c36daf24533ee6d210c2750496c4297dfb88a8b400b2b8c9e6bf5580ed674d2684ff194843a595adf887823fa2aefe9d35fed4c491a8d2e1fcf36199cc79ca522ad9bfb97	\\x28e4a778af2be40fc53af811a70dab37e1e071abc8fd8e3b8e48c009efd8c6f845ed1ff3680d1408a62f8af6fa034c0506de0ccd01fc9a536a2004fee4957083	\\x00000001000000011494ade7c0a4a49911fbb9b62b57c919b9aba96a7d6716d7ea4f85a37ceccac83c07430c17a7f1b50a9f1df176ded4e91463732b90e720e9fcc77ace58d379279391510b49424d3ed658e9229cdbad60b929dea431e0c24ef2be9b8890968e112d073aefe91c76cf78b916912898f7591dacb71606cae6a3b4f08ce9237034a8	\\x0000000100010000
19	2	6	\\x56727bffc7ad92cf3a903e0944f64d9ada14ef9c58abfb1c8a24c2c6691a7f160580e67f5b79381ec53efc1e73ff567f7047ddfd2187a542c4c99208c621e80e	65	\\x0000000100000100864965e80be8c9de36f7a37996927f9544763aaed60b7b75ec3a615f437242c42569f6a8954dec40326bf5777d1bddf699977280d044bcc5290fefbe83d60867758935eb18cffd6e40f1a077653eef92bf7d9615112ee730748eb286519cfb34a2e425cd136b9298b38b53da6e77d15311cf30afbf2e496fd517364d6cd84a6e	\\x7d5211a0f714c0f3fce778f00c2004236a4911ebee69ff492df440ec11b4a4b5b495b707637a83c357104028068b6f8f985770a61ec30ed43c1f3e09fa81199a	\\x0000000100000001a96d71b8c13b847ba49f14724fee6463d0097bbab4a14a843c473440c40052f71a8be7fc759edb125e49a4f52a8b47a7b036c6debef41c57b5fe797d87a8d8619a507df21136ae990df669d7bffbd5de312c855e696c15d8665f6c255c898f7c1deb0f2b73f5fe391d00fbe9541ed6185354a8c3ed2c03e00d8ff29a3146e315	\\x0000000100010000
20	2	7	\\xb5820211b3ef6091e0d767abeb286b34f94df203837fa1751224a0b61b5d43fb8eafa5fc01e60744c31bddd6cd02eec9a133383db5d610b3e0ca62244584f906	65	\\x0000000100000100053c049e889626b3b564f5e1d1d37ff03885e04663d5ad7d72af87f38595fbc5ace023ab06ad84864356fbbd706464f7e1208392aba66fbdd3524f0476c4e1cf6bd0846635c665f14836ecbdf7571c3d113fb7acc1b31e8ae4d196d64e6ead277643aeb2b9ffab44105540187e5f03102f7dbe44a22cec6c46a2943112e994b5	\\x19a026b1baaa9489284445e7209420dc6702ad3d7189c3ea245c95c207bc0ef23e37c08216c96df589fc0e46d540dbf99a7877acb9026e5e381405bbbe306c23	\\x00000001000000012c3b73e00857001df9cef245d0001988d7540413b9b5d109674963734f47b0dcca45bdec899aa62fddccf73fd195cb0677b89b0609cbb55995b79ee5ba55f4c6e439f1e4c9302e1df37b242d9274a63312a35386b937e6cfcb7426c304b20cb4e1790104168776c8e88de042bc77e469c03554ec62c73c01eeb4bc6578dbc137	\\x0000000100010000
21	2	8	\\xff0a62c2148be69d6849cf728860d03e20059fa1b1b8e68317dca833a7ce4beb75ac3b688feb42100363d336f1d746d9f66258d7ceb2f9bf8fddb4c875e5480f	65	\\x000000010000010064e711d0158830d51dd4eef52331d0e13f0364638a5f4c8811c2d58bdd191e6ebaaf5ee3498fe12210226c00ec3c3d2ad8673e0f435604bc897da017f940977ee065a3f2edd1047d5fe3f590ced2513ec194379dd6ebd69c12631b10c170ac4fab171c5cbcc0ac3366e7b9735872909109b938f91db838af489668fb7518a7d7	\\x4affa2f5fc01e4525c21257e18abfe677e3f182902ebda56831b79bf35834b5e847e25d1f9839b7422f2e643720c3fd3cbff75148d04cd1911054f9357f434fe	\\x000000010000000167f96ed5021ee9f27a37f139997fb5ece86bf36b7644a0229df0a531c50c9d202d65b6a41c967ff03b6aabec18cd666aa157cc5d5518a6c9a090b59af695f6ddcd89924b726f2da9a589711a71676510fdfc100ebaffdcfe23e514141ac15e598ce67c9717e6067099b49582db978708adf936886d077ad7ac796974f65f4943	\\x0000000100010000
22	2	9	\\x80303b704fc64fbb56d0cdc1be2ceacb127542299863e094c2954c96a2a9a78644b1fa876ffa6882c7fa656202226e6e844339008c7067af3a4ac6ea75ee3308	240	\\x00000001000001005fdad4378b7b7382d23f399d8463254dff3324be9fc7ddd59b13e3b26e13fdf4f13a74878e59f66fbfec6871418411cc616b1b6c68cf94b404c62c80685c17285a06e842063dda15ba73b3e663cd9024f68ddbba165b9e4f44ba18e6e40ed2afff10f62ae63d3d4a29efe8abbd3e980fba82ddfcea70924cc68917cd770ce4df	\\xc3b46e1e65e80a3d3f227129646298f3e2221c7cd90cf632c8ece9fb7881937df759abef4bef358f513bf37bf9ea916958bbf5acf4c3702e700514343701b5ad	\\x0000000100000001469a0dbcd049335a589f17a5abfc7bdfe583f71e740c29f31e5b2af774aea7b60fbb8b388fb7a41ba5fe0e4fbceb08fdaf1e1e2811b735e7d879a5bd093306452aaf974e208321fbf32a02139eac23d5d63ca63fb3090df3b15bebf97fa2b957b703c6cdf643356bc95442f4191a3828e5ce4848539957a304923b70b400fcaa	\\x0000000100010000
23	2	10	\\xd36771251b8daf841db6f109050c35e26e1752d441b15951c5f39a7e199e529d5bb0683ee1fb3f6f5e5425f3aa6b36304d9a0eacdc43c1ba492033941fa2c60f	240	\\x0000000100000100a158bc6018b1b48f6d654bb39ce62eb470519b2ffac5ab802cf167bd53c8b48a7b91fe7b1d1c5ee1097d06c878f53a07c76d25747f6fc7ffa16eb17bb9b0647b27d55ff24e03a6f0ffc7ebdbf9beaee0cc7a27f7bcc90ccec49a24bf580c07b686b176e7aa66be71ac90108ab179411e27bf6926e9ff21b913f5b88992141dda	\\xc51f2866354c03da6e5346a416db05dd15e791792620359285cbd86867f58c975c22df5276e3aa14b89877ba68877e5423289dddb7254fdc39fe380e03a57b33	\\x00000001000000018742f0087eed386cd7e7af2040426cc3a3966bdd0030c039415d21c766c6a7844380ee3c892a8e051f8e431d171723be3c7082a437ab877d79e384b3ce730875b441afc070503467fa1398c72baf1a90b7a7bd1eb4893a77b97a0f112fb3e020e72046b437a01bcc5970cb2668eb7fb1c36270ca45c999ff1a36992b9eb8e88e	\\x0000000100010000
24	2	11	\\x781eccf212e8757d6e88270a1454face8c4d9994d5d6c37d0adc7a0a531b6777cd21da69dd48bf02f437d16fcf27cac44452c2eb802bdc303bedb999d4eb9405	240	\\x00000001000001005409f0937f0c33530afcf45c79756c35b64f197e9852896fe09a7d7d6933497b558f3ff7b7eb5834439fd62c5530727c580241a72b1ab0596ab95af2020816682923e89723e6fb1113f297e9e28785b3322c3a4fdcfe90fa4abebb9616e90bd9fc93f2d74b21fbc9202b8fb984e5c7eb4cce342f7414746f6613c72d155a0572	\\x2f8c64941a09b1406a618d576314dae0a1c026fcd69ee57be3475104532533c36389e5c4c098c4ac26103618509f2c44b88d1490b56a76d29e76b7b3accecd29	\\x000000010000000158473bcc410333668c6f049e1546b0e0f8c438e5880eba8ce5766dead3226970f4a7f41d50ffc35ecb65f741b9e45c7b7b675c23e45042243a91a0b5856aa7b725d837b61539bde30e0e7473950d5241778aab811e8b7e36b6fe9ddc4c3bb168bc9e95ef06804beabb85fa424cbdf3682921cf8de6a535c7520be6ef5fd2d4b1	\\x0000000100010000
25	3	0	\\x2137c335f4085233d479e693cd966e9710067216eb2dca49774f06a1d609a0c47ccd6ae011b83831f32a94bbcf24a9097b285bc705d5b275dd2f0aa238025201	53	\\x0000000100000100075cddb00c74fecf63378da3eee505a3901d01e283c74426a48bfe8f46599e9e1bb9d1beadbf6ab2b70afc7a9c63638ab6fcba88fdb68d3a1988ed0e385acd1ce56d6855229d156369633338c32fc776ac8f53f267b4f45476be014fbba6a453fc9aee33c33359a1e9535f8fb808c7e14ceb1d94ba55ed4252de5a52a4210f86	\\x5146fd9867daa4f02b4fc4d2fd1d151cbe3a6b1e570ccfafb4e778fb9d50081c9d38132ed8d48a935c80bb1e1278bde58bf60d2e0fe0dd5066f6c9488735b771	\\x000000010000000147835307acc465c9dbbb6d6d9678f2e87090867e05d34434f35ddab939a4265cfff1e36a00fde86a74b533a4ba6fba6a1e7a3cf5dc725ce6db05f49429fa994a68e665419c95277e225ee3676c2c3e705f6ac5bbb4a22a189f94ca08a632c947095a60b4fd483d74b4cdd50fcfc174c4238f6de96ca77f62eaa257b3742599c3	\\x0000000100010000
26	3	1	\\xc8ac882ea611a7acb794cc9fa711a1574214ce15916c9667837bfc0e0253acb0898aa842d16b19ff21ed30f1ea957b9574f5067e7b64afb6c4db4475275f2309	65	\\x0000000100000100a0eee3aca7f7fd4fccf75479d5ae330fed6688b0d90125ac57abb2eb615cfd2b5ff86a786dcbf4d1c130ab753b84ced58306a36581053ffc3b59e1c60c81a8c6baf358c323ba3e4f99979c7d65c8a80ce3616f8d17b33044706908d760c039a8521b348ac0511ab5cf43fa648b95e7036eac76a7a30cae7c4c46fb1a199f08a8	\\xbb64d76c4d7a70ef4cefc95d2abbe03559875d20ba7e9feb05837e6e3f77734627f00171986180e3b0be8bfc5f6cee6c9a14abad18fd13170d408deb5f6557fb	\\x000000010000000186599fd27e1517f57f5b716275b22f0e749b6d34a0fcf22fd3af47a0ba440567ec974447dd8cffe99c89fb6359bcf53b46a57eae412fcce27777f31dc13639594acb5e7ce955a92978e5fc2ae624c7ceddd98df690c2a28f34287cbab03b09ef6704204382dfba012f470729a062b4b23d4d1ed90cfa7c3f1cd699f336f4ff7f	\\x0000000100010000
27	3	2	\\x0bd2760a603455be9f03046d121c656c3d37eedb214723e1de1dfa116891bda7320a31d4d36ef6cc29200b69e64bedd9b498c0f34c16fa97dd188fae31898004	65	\\x0000000100000100bf93a62515d57a1cfa33b0b53e0589db98d2ef3bcb15143d370a1eb2018d20519c5fb80e7493d38bf0e131ba3e8b535f33a7bec257adf0abe4af4ca23495b42c22d257c02e9ca6fa0d940af810cf3c5fe6866f9f3fc86dea0e456a10654f99c97a19d4a8b0c5650b5fe849ef9655ea5c7e4b6b02f63e865f2286f9f2911540c9	\\xaaaeda8938fa03dc0ff0c109669bde907138366944838972e4c85b0bff12de5d0dcca7109b3d95df73dfc4e904a95dfa6126b91ed7721e75b8be76143b0fb2b5	\\x000000010000000198fb969988e62d269f507756c69beb72d86ab45bf78c385840e6cd1629b8275a6ff8b3db334b3ef2a737c24d424799c0d08dc980a0cde00005c4a1675d52c06b38d97b7c5d5d059fbb2cb8e6957eb96aa782bfdf935a150d51cd61fd36aeb5277874d892b72586e062a7349c8d1f93def2692309dd7116c9fe0b322f1d7b9f55	\\x0000000100010000
28	3	3	\\x1bfa9a4da18917a23b40592030ef007c964e0013638d10cc59daec513854bbc8cf10bacc8b2d68507c1077ae4a1451151442797c31dcd0482e18a29685094d05	65	\\x00000001000001002c5472da54fef23e1c44fa011ad5233d41eb341d61e7dad6e271d2a432056e1a512c745ee2373c02c1aa09723a9c13a580e59544004ce8bfff2527913d1ed772deeb9ee2d65bebbd8bd535f56291de424624ede2dc7d6ffe016d2d2a3d4b719fdd00b4ce6fef907c60800a1b3c6d84aa654f270d586db624ce22b84fa3070d54	\\xc0f07345b4823a849dc2ce32cc2cd47f0ab3cd2949a26fd72bc463651c2e6257066e5aa6c5be720804dc42caa4ec3ebb08d334d4901b0a31e82c56cfd6572c21	\\x0000000100000001b2455a9642e79776124e2e60f767813868ebf30c62296c007232dfc0fb6c2bcc2032c0c82c7e92dea9939fb7f20f68fbe21c8f873a87b10fbf0282dc15b8618b2b3b33b0290e594782d389d14adaba830d19c5735da31810963e6198cb7e41d5965cd8ca81ba05f06560376338b38b938c978ace878a9a9a8e7cb9d85bffed8f	\\x0000000100010000
29	3	4	\\x9b3cc18faf624dd372423dfa88da940692b1bd15032afb4f8b52a26a43aaf7efc82367caf7cf34321845ddcde994ffd5701ff0e9f30263624ec54c1fbc632b01	65	\\x0000000100000100afcb89a768cdcc074fdc58aa2a386880e5b27f6e45f45ce21682a12b817cba0aa3bd0517e9cc51c2359aa7ab7755bda54b8fe544b95b4c6ed40bb29b92e7d1ae42f52b25acc1da42b96d7f8a5763c2fca6cf9978e5f7afbc3ff206476048f3c0041dcfdeb111138520a0eca2c3a585d460fbab3985d5df8adeb17941463c60be	\\xdd96489613a9ba4f9f095cf139d07d65dc95ed11273414f3ca45958bb8a00b554aaaff7a30c2675d9d034edf7022a4127d58b524adbf5aaf0ba5eeab9d15035b	\\x000000010000000117adf74d03a6c8dcb9510aabc686da57117b8af98bea7be2e8d92bd95fca629f2d55394d2c9b1090a55c055abc20de11f4a83b38edc6dbb6eaa4e5faf3f440ec1909e4a9439642c4c522e5ad45e0984afad478af503edb7612a90b35139ef57b3168ab80c9ac3816a17acda9ae4b9a70bcd871606dd1fb5c1cb3ec4e497601b7	\\x0000000100010000
30	3	5	\\xe4f9054a5469169129bee87c288f7388a21d5722182b04a598178714943afd4541d775aa6963adcc5903764de4bf0d40ce939e6725942e757eab442416e8ac0c	65	\\x00000001000001008989ded0fd000cb5234be5248ff2474355b2aea0eef203f6aeed1c4dd7c457b9fb105bc96f37369ce92fd2725e30c305da495813a3a25258b5e1a62bb417727f4f9d5432ee0f2b8b2c3c484e5efe442c518f9ab69014df195cf243acfc98be79f7cc89f1796e4eae758b27b29c128d3e7a6cb4e23bc405d4aedcaaa375829e8f	\\x30f22bbf886ea2a937dc437eed12c3c6f7e4bcf72951b7bfd45fddd14933461759d3b7a407823247088b4e927d9fb730502edfa47f773e58f016105a24d28436	\\x00000001000000011656eb74f11b4a6531f53aa972f8e30e08e0506adf4fa4c3a61027859b6606fe97e1982b48086cb3cb5f864c1291471700c5cd01a910ff40a6b5b974986d1575bef0105352d9d90197583615d61eb8b026fb7443858882fe9ccc9e84cf8c4648d891c22a76ce93566e52f5b5a9ea4f6b2bcc946a30feb72e273459528a35a691	\\x0000000100010000
31	3	6	\\xf13fa23b81816475b479dd61079d17aae56e9922f7139d7e13c4a8d929a682655d3c0e8e235df1633e65ae496e938cede275aff7f0db0c3fdb53268d45d78d0e	65	\\x00000001000001002975d4275dd26e4ae32dc711e1a6a346c3dc9bef0fea7bafe2fd6164cf866b85204ac0d110aea2878e2cdab74f73c57b46a0e1be77a913db999ee7a0d5f7cfa7ef078ae068085c8210a51575abeb700f026921f7dabbe56a00a58f18ec512c5c6fe27d9fb780536fec20a5503d05012265409b7bd5d420346c805acae0b7b045	\\x69c73c5b72ca8d0012704d9f90140251b38d27b3c7f4734b484a4dcbf7382e5c8e3ce61caac60babed3453b72324b1127df3f6fb0aa973fe1d30b5ef782b3da2	\\x00000001000000016a5fc43ae2f7951a3d94699997a12f67c09f25c1f580de5202c93c237c76e9a4e3dc415a54cccc909c94b4a0fee28e006cc57d81a45f24b38c75d85ef41efd656ebee73c07956df764aaf4bf21ae803e13f4c442f0c5025e96eb8ad8f96194602054aa6be002130e9dba17e2007dbefd6ead9e8e25d2877e8ba49aa6e4d73744	\\x0000000100010000
32	3	7	\\x64e499d951840f12b0b212de11aad44af9788229033c7b3ea8f2ad43eb217451cb0463ae2aac999b58dabda182940ad9f6960b5b46a98046345c90703b42ff04	65	\\x00000001000001006c41d92c60be9fb7d621223403e1f7f2d2680a42b8012c4b918aded196ca4f574ea71d2805d76c670157f4dda07e07dc3826cebd2b8328792a1784151637ab6957752378959d0117fb84009d9065b6fd62ffabd60ce660a56b52ecf3796246b568dc2b2f98a8845fd9f0bdd6cd20224e7ae2988f9ca9dd270f5097a7c025ec77	\\xbfc352a10fa31bf80fc82a6a9b15907126cd1e25256ae3e2e937ec792b17fecdf85498e33244036f7141b21b645d60d7661e3e6d2d93db49a39a6bc40deccec4	\\x000000010000000175d5b3296ba8ac006b1f11ccd176c761cd555646bd5b55b0ab782936f1aba16b0f88f165a434e81af79dbe15cee109446ddc580dc06128647877d22fa614e4760e919e51b088a50a0652f3f7b00df2552c944210b83293673c071ababd23be520c7cd98fb2ac8bda7a6445d4f08dd4e9f97d8eaf23107a8e24240135cea4f365	\\x0000000100010000
33	3	8	\\x1791e1bf5fa38c391f8f8c8537c4a395a43c4c3d86aff92f46282aaad9f0df6822ab7180f5ab604e61bbc968ad8eb4c75dc202e2cbd0e3f9c4f9211ea27f3b05	65	\\x00000001000001002351d0385218eb36d5809cd4dec26b92749cc17c3312f3fcd9fea92f392922177d6ed8fd675d9fd97e1fd7bc789e9c696f6c4446650cf3c41715aaf52d4d96b6692d8438b63211e9ef1dbbdc171632b48f503b0b38f13802efdd6c4cd2b59325d92e03d18c1408ca9335c02cf093d57506e30c12c36931adcc41ecdbd47f1bc9	\\x66ce92e91b3a7dff29b1fe0381506299c3c8546c81f67f892a7bb33b00906ee2d54edba6fb9ff26880e9618b9e8fe1d05a06267d8c71af14bf28670995b35df0	\\x0000000100000001464cd47f38aa79139e78176bf7b1bd850ef3f2221be24cd34948d003ac8b113db04b48bc62d03995ba62713244ee2c2545d3f3fd5760b56a3108eaf6f4b4b971d331f00e7157eaa1a06d50ae6ad7c702ffab4a24c2daa9dc724321217b5a8deda0ddbd83a72ace18e7815fb7a0886b520acba7066d0d786e94c098b3cb663f7e	\\x0000000100010000
34	3	9	\\xbc6747341ee71c32b47faf0128e68df914552d0522738648c5c7d1b2631b306065af50bdbd54b682733b1ba1c86e4fa6ddcc1cda9340f1f71db3af66d4d20303	240	\\x0000000100000100a4b77ec5420a9c02c5efe2164caf8899878f499504d7faeed46566ebd468499212cbc8943042705fe17399819fdeb81b1d434f5d11dd8e9339cadd6053c9c3dad351e9a1a6a6cc3d2214bf46ac187544e56c9b099b52db0b616e0147345afb20b8dd6ac8db98c19ca5aae954f1a12233c61af9192279d26e448c1f3c2707a854	\\x80ea7183bcb8d1f935aee705ae76619fcc83b0425c5cb74578aedb31d0a617192d024fd39a02af54168257602f6d93be4443dc16fcdaeb739ea09606db9fe1cd	\\x00000001000000013f228a36dd10b5d7bf9b3c93fb14caf6e4ea7e86e3af9fe2a3940c691f1444dd32bacd713a6cb83594e84edf22ad35c8492feb8ac41309497876c8a6f42ac3cb628fd6f63566a126236cca7240ac338e5b1a9dd6288f994669b475bef60307a45b5ced7b82c8b164aed90407bb900ac551fd20ee152cd6e7c683871a64d143f1	\\x0000000100010000
35	3	10	\\x4060f029d66a84ba31f044fee88e5b403426b4b51bc95ec6adb9849ecf44ee4450057e76285b3ee4bc9c3ffa510e8567ee734c5bb46cc7c4557f11f64c2c8809	240	\\x0000000100000100a13b95676ad2251e4a6e365efb8ae8606ac58c09009615fa505f4c2b0c2dfb4eecdbd8013b2ef99b19e901205cb5e8fcb67f2d3512c13dada8718c93419b638bdd3ec34e2647f62e613ac07b2773667dc38d1c74263b89ec3b1b46a407aba0c857f6385add5ab0dc38ee0d2095fb83122977dd41fb00c8945a258f4e26e52633	\\x9e487c2ad9c64c68ab24c330e8779ef2e367fab4f90fad4ad70773eb383f21b234f9d539754920ef38692586b03d33a13f5f9b7482179abb31c12f411e48f0bf	\\x000000010000000178011ee87b9b86403c79411467f053076555156ffd9fefc33583695a6e47d4561cc6c6e9561edf9b80d67592cb9e06bafca3048911b77c48bc87245dec0843215c71be7e9d6aa51f6eb1a3563d61f3225f3c566e8012d4c6f54770000938e0c4fe6d19ae1e417f1ea54d7aad21d0845f1b114c90d710ac20f93106f7e1cc8ed0	\\x0000000100010000
36	3	11	\\x881910ff5890e38d7931b3af0b0f2b42651f698af0754edfaf8980a744a355a4b7c4c6ace3d96b16b13a7deaeae7058161f96a5f906cfc3056350b8e7bf94e0a	240	\\x0000000100000100712001244dfe96bf90943268afaf747f72a8e44d7642e52712a25d5cbf61560447e1606be057ce145aabab546dbe0e6c81ac9f10e96b9a95cdd47e917d689ceb945a8e761bd3a281524f7c58bd0babf87a2fe8bd6fe32c6d2a45070e02f03b8371ff1c5cf7e4cf027197ba8ddcf5606ef9a4b63a319555c57ce391084bf0ce7b	\\xf451c3165689f47fe77b5370d62e475a0d64d9d8ded10391526d71c23cb37d9c82694f4216b29dbd7090be1863acebaba8ad73facc93af6cb407f8014e779bd9	\\x0000000100000001103e7f189613e9b20b1353e1da0c20c240d362180f01a3eec9672fca29b52de82fef95557a6c7eed1051d50bc3ae604b916a07daebb248fd16e44689243488ffe83870718ec80fc3ad8c74c0bfd08abceb21c3bd7c395aa3dacaa810947c40e785b4e03e259bc9a973fa6f779892de435c8b22d096c092172c95c980a342dafc	\\x0000000100010000
37	4	0	\\x619dda837061a0aad1f4a07c5bd802915d8522cbbb6ed85d162f3e8b14f27bf48833d07ab5d0226006430537e16d44baffbb4c90a1604274890fedfa4552a50f	105	\\x0000000100000100282faf33f2514b0712266b260e33a1eaf8eb3afcc8bd31c1984a52adda8aa99e447246a867aa75bd5bbea9e6c99e06f1b3a22b58e109948964692a5878f6a1afaba53b891862e94843c0b7cf5f47c0d13e8c0887f8668a2aabc5981f9ac3e339db08ff89298d3ecb2f99b3ae68a399ee18e5e0e7f71ff6b8a49ceb886a9e3656	\\x3730edf2b63bcf96efd370ebd258f6d7d450a166ab20208be155fa44f3397f0999c3dfcf55790cd30da5cc11c45f7f974af0a6f02465036b408af0dc92d6a66f	\\x00000001000000011469bed9d8df246b7a923fea9af575c43616fcebb37d4f59efb0e592813d810b3bb745752a21e45c769d2f531c75bf5916aba552d126c6420bfaadcd4d3096776be049a904be8b84d7b662ed8efdb17eedd03a9d3fecbf8049c00e7a7639b9da59e92841ac409fbf31ba24d89ccea2e579b65e161da1ef151ad54104e22251d7	\\x0000000100010000
38	4	1	\\xeab6d07c944bfb7f295c24190544bf266aa896b5667ee0a4c0bfe255bb59e2f942c12d04c8b537066faba1e482756ee5a6530b9eba92527f4909a462ad59db07	65	\\x0000000100000100601dfc932a680647ab9b0fb23f140904cd2f00282e5f67b176ca667612b8b5a45acb4e58d58b276cd8e2e5d54986fd5ab035c586a22cfee14189133d566271a3d04592ee54222511760c65768cde3761e4eacf41f0ae6ba00229130002733441f634252a39cdeafd9269d9fb2cca82937e04524107af2c9b06d9790f469b44fc	\\x3a9f445f842dbdbb623d914a1fa669fa827bc586f060431d966cbeaf0509861163fdc307101d39fc5ca8a0d8a55378cde1cf12e189e43bb31d25f75015d24111	\\x00000001000000010f631e7a2725ef120b36e9ce051ef8a105ff7986181481c98be7bdeef64302109096e6cb7531e748e620352dc5b8f804f7e712f2d02cf1e64bbbdfcb8e8eb3eb14389d2936dce0c7d25fbcfd020d98b7e312132a1e3bd847abcfddf1f11b1e7593c014e8ef3b09399145816236c1475a7831933c594e0b9babc7886014052b60	\\x0000000100010000
39	4	2	\\x39c428e54349118a5d7cee8c2b6b93c6b47dcf591589b085d0a6e8e047d85d87b3b207c8692aedf98c309c2b77d4340ce1c19cfcea000ba54febac3efcf21d0a	65	\\x0000000100000100a5d99da39d00aa4b49ddbae56413815c1792d690e7f685215c6470545256f23b353b8d7a14e03c089c10ec0f8fec28527732f1746b5e7af0f9949ba5a47bc6e0079c409698aea872bc572e943fd39222ad5dc258da9c491598b0f05a6022ad0991479e134eccde9d24771fde46081b108fbf86a665610ce0ec73dc2259d885ed	\\x7d3d417c1c5b890401eb7e8414dcc08930021e73c63a23a275344b68980179b27fe475171f0381637498ec8883c02618c4423f2f58d45ef65f777ef72482ff2c	\\x0000000100000001272dc28ce44a1f1e63d4a468132f4a07860aca63ebeb84e98c50421a1d4da2b476ff0f5daf9cfd5571c694f9ca3b2aa7a287d9beb0bd794e56183fc154a2e52c2c4031d48bfdc9a0cf624c468e057312aaad6ebf69a554440739e28c403f4b2f8beb08a397e0e7f01909cc88c854a39d1e14a622af26d0a4d52cfe3fc501ad14	\\x0000000100010000
40	4	3	\\x723448e116a265e7bf52f6857ee00b82accae2bc7d06d34f11853d35353eb652572fc7de450aa3e3775d2d0fc492d4ac87acc1403a8c8a75fd1a77437b10510a	65	\\x00000001000001008ccf861dada60fd872a72cac3920b8e66757435c7e60c30eb9c5200d390af5cce1379aac847fc7c4bfba5b5deb53ba3c34d279848c118d97b0d7fb8eb8354eedc03843e4f40c77a201b79f5227f378631aa73656134ccdab8715110592782f5f5ee146d496b2b638d72f2c703fa20b635fb2f22e0b67bb7ffa8dd7508e778bdd	\\xea19cd09606b16578d87eb9c708ccb8bc0969fc3f2952c3b862d6cf21b23418a82df20b859bd77fd4f979c6acd273a14fe55b453e44064219f8cf3613653ec7e	\\x0000000100000001a0cce07d6bc6a626b1c364be77374909f5ee3fd155a3a2bf915a283a27c62782543abdb929b6fcdf3234788ce626edcf7ac363ae114d094090c9373971c8a42baeae40d3bc92e41e36c0135a784c7004d38fe9205b80a3a140cddb5905c57822afb8a2d19dde49668f5d829ba688c010dcb355bc8b8bc9ce7a82ac91b42ae3f0	\\x0000000100010000
41	4	4	\\x4dc80c5995d72067e0c8cb6045094ea316e338ef7073f047f294c2d798492b58592074657466a683fc1e31360af1a00210b68feb52bfd735531bdc12be344d05	65	\\x0000000100000100cc6db4d51d2b5d429bbe27f325610ca48cbde970fe28e069af5adb78b1cb0e0dedf8a59240d16ac7d00d6b99b9375f1b8062b1b5a6fb490b22b6bac7d5da9ba10b139b5ed87f46e7f0ac4fc556fb0e07ec1ce3f69564df994370962ddeaeb1259c2507487b6646b1a5d7e7f78538ab8350c78b5f04459e830ad0637f8aa690bc	\\xa69a42b8415ff26a79a19821ced87f843905d98e05006381c478d8a82c30a616fd56f62528433a9f76a6fef42468f10564089dee39b2679f3d48561641ca034d	\\x0000000100000001a0917deee0642208d5f7650e30c1896e84653aaa755a7723efa9df7551e59f9a83cf1ef9d7f763e9e3a7360db56886b8e6cfd74d0226ac1648745d3a726b36ea8b6234e0fd02db23dd6331b7cd22e5a370e04452897642cd0dc90677cf94c738d7e6690d9d2652648f36baf1391d336377e7c8941fd45b95e181d296f9f669c3	\\x0000000100010000
42	4	5	\\x83b25d89eba557d7128e37109fbcb335f0c34c01fdb3c348aca5093cc9a7b57a9976195ff5409c096628796cfe91116fe8925f8d568c3a87fc108f5a07971b05	65	\\x0000000100000100190bf9f16ef6cb559d08e078291667de8c2886fd8035b6eea706aaeafab92d4121af15501ca5127992d062cfe388d64e98af1a29106e44d6f0ec1429951ad27b617ab08b560366c9575b58aeb9b27a2273356bbf02c8f5d77c322ac34e4e6ba3a703ad4a170da6c324b595a6c317be9bb03f0700f952f86dfa11cd5b3bedf22e	\\x4b5cab9c4296a44205d03e342a413c2ba8e9c3bfb2869a1eae3ff04fe10e312e0a5f9083b8f33b860e57b4708da3f7a514845155738f2b243060b7a23869fe98	\\x0000000100000001603d114f26a3eacdd453cce4fc63bee53e4387f355a9699d6e58c1390399068016abac325506925a73fd4633901b7696dd52a7a02d226c6cdec8c0382540a367cba98dbc8adfab3b2ef44fd3b485efa7bd3fca516f0432e5c738672de28361ef45d60b1da2c49af686c4054adfc3de23e71d0279c5e0aeb615beb7c58e605338	\\x0000000100010000
43	4	6	\\x33948eb8d5f26b09004181ee1baa587f20a86649f2fd99348b561a2fd6ef07f5a05eb9513ea689f56bbe7c018f9c02791bec48ff37633f8916ced15ceac1a10a	65	\\x0000000100000100178607922bfb8d9e969cbc49df96b66ccb8bdf2f33259769e20528dcc1a9ed31f769dbb9c7e60c7b068e50a1bd15524135a8192aa6b049d8c7a13771641d990b8b53f79db32b02dcd22d10682eb1d4e2f4b09454dbd5d6330cde568f027992cb9366e433b4c041f5d6c59cd2848d5043f725dbad01574b468c7f907833d6dafc	\\x68a88a8881a350fe525541793eae74f8202c6ab8ad1a62cf17c55b40b40dd7a294377f8661be29fde8b5cd83860ea4a2139677d03f2b0321c61f3d80002d1106	\\x0000000100000001435778413657e341f3e3ada7ec916c0caf9962a12b4f77c59f3316f4adba30a5ba5f1a0f2580f8644b468a1cdf197092c02fc11ec859af4d29a0c029017a7e65d45d73744c1d8b11469370e825ab4457822aac723a76cad938c52f99cc630b7d136f504e4ce8329c8c27e45c0e4d95fe58d7dc8da9fdb4d4dff62bb201485385	\\x0000000100010000
44	4	7	\\xda41cb105f81a98d77c902ae56b2009b143c5beade5cb7c4a5014f73ff2f4d50c802922e29b49ac343e44fd89b26c2cf905deb161c81739306a6079e0796dd00	65	\\x00000001000001008fd0169219fbe4f2c3a7e6570d81658ea4d854146ac96f8a92fd4d3f75084ea4c5f403c844c44780b66a61e6c79d866d66d17318e67338b6f3fbaacbf99ffe8b712b6b51668481cc1fc019a796df6e8f79c2d2923968464e7f9c02f25296d32f5c939b397e6c4eac968c011b0778692b1daa15df0a6cf82efdf0866403736780	\\x8fa8897ef898bd3de6eabbd69cb259102732f8b4c0864358865e6e7e45cb7aa2a4e683dcb4e5159f0ee06626d97fc93798a4cd67ed8e61e1547a7a2d94fc8944	\\x00000001000000015b402a3dd46316ce41f8006bebc044492cbf7419943f6e45fb0aee031d5c1aec1deb0d34d7e5a99d439334ff7e3cd1c24a7b5e33d839076e3e7712311015ca90967c627c642e5a2ab405711328a89b2f068b2fe01348440eb20292c772b3852dd6982ed51a464a244141d57e7e8f9c61181414f2068aeec78974c9fce0d19b96	\\x0000000100010000
45	4	8	\\x2890d9fb43fe9baf75a23166436cddfe4d54ffc811de657c52d00e0e3cefee46f6625e2df99ee64f97191faaa45e39a0abdccec9805231471450284293e3e206	65	\\x0000000100000100acf745592206c885490ed5087afc17c9cde9b87a12212c058a8ba829b6c016e80be65cb6de026c633f46a6e49af04d2f469a12d9981ffb55d7a521713e2efa205552e8b59a186cd1592d37d2b3c30f886057db0d9d67ede862a3d6004874e2646f19392f13c5e01578a22c68c794fdaa5d5070b5951539a9fa6d27abf74a024e	\\x144abe9a2f55b800e3efce52ed37e15e1b4e304a4a1b0c2ae0af868f72877ad2a962b1061e1ee5cce8b3b03ad15c4e84134eb731297e2c56cc32a676a9d5e104	\\x00000001000000019de8a81e0fdec03a00989be2295b5ea88c420664b04fc99edee9ebbe15bdef46570308cbc40f0203ca828e05449759b2ece502aaac7e66b3f3d115e44e60c996dcc0529ee7659c4db7b5bad2e75c8916510c37501021c8abd565bd74baf7cd7eae15087d026fd0ff5bf9bf27b62142d589b561016f7b3dea494b0087e96a1dc4	\\x0000000100010000
46	4	9	\\x1b559931d424cec951fbaf0f95623165ea5e2a34a5dff85bbfa014269a1e4f757dc47e85e0cd7583a718402581004d5f6e76077ba7a6125249a4c025489eeb00	240	\\x00000001000001000f191cc2142f096bc4bc267e5a94d6ce3be0bdc8936d450f9a7f8a4b3a087bb9ab1fac4b96e0fb02f8e9bdccd8be8071878dfd8483c873e3217eaeade46d6fd6305c0f58e5544ff581c1b5a6d4deea7719a1c894c318c2c6f91c193e83174296f3b53d7cf448d3677fa1e891d426236bd60e49d63652b0272c1d66cf4c91ec67	\\x469a26315ea00555cbfe7d576a0d6bec38873851fca6ab89f3d7ed7f39bc6760f776568df496c667f2fbc8145e8a793b82023da0edee68ebb453af348e7e09de	\\x000000010000000102dde6532bfeb6689f84adf8b73a5f51f31a7b80ea32cf8e2e02b92e4922fb782265b36b26c4d18fc6797096c8a77c0cb4d4d8e0899ab8b2d8a3ec457c8f2fe20c279a2d371080ad85fa81da8cc5f6eccef3f75407b63a84a1714cca9b3cd19dcca9ec8708aa0d14d4e1e8401bd37d2f529af786d6f5f96815b05d3e1ed3bfcf	\\x0000000100010000
47	4	10	\\x61095ac4f025b2abfa4536df60506cc67d9c1395e5bff8f00c019e528e99697e12c1863a0ce3df2aab2a00ab35dd6c2a558269d3a4b74aa06ffb1f8f5d5cdf0d	240	\\x00000001000001001eed60616a70f45b793ccc2654af90a7c35c07bf3b6afa5d881aeab697cbb34988905e0f596ecf7744bce6e76051e70cf3c7ffedd783fabf8b07e3a898894f163bc4dfd80d67bd1f4ff84f083c4f61b33aa18194c5d1acfa67dfb244d9d4221f47b070122582d65b7dbeda74317d8c7c6c87927498e278db257abfaf21e5e68a	\\x20f025b276096880b6c0ab68ac49640ccf747ecabe9abb23830900204428f4b4299b94ccac9d2acbb575468266c2ab08827079c9e62cd2c587b79925a59af50d	\\x0000000100000001a8bd0ca753df9f5cb23f6014300da791238c61fee331d8a791bf0a1faef8e7d4fcc5808881aa0b0dbbe41dec5ecd41d491131e5093e157f54b7bc77cfdba359dd1e74a04ee80ffa06b97f0edafc040d9ca4322d1922a460b8d63a301ac41e4023a9e0b2dd743f95652b6b4c9a9bc7dca83911b1cd8f51c19c28d00b3f4145d74	\\x0000000100010000
48	4	11	\\x5dd990f8277e0da091ef448891f60ba58e84790b60e0bdb342b26e63837bd91dd7303e2ddaf007899bf6c42ef65fe0ffd88857c793679a72cd262cdc4933b70a	240	\\x00000001000001003dda32c2a3981bf0d3fe69cb483d359dadbcc82c98f0310df3afa569142430a54a3f070ea90a7dfd72dc6ce7fcec3277c10d473f3bbcb00ee0925cccfb0d29e9cb26a848fbacdf5c7641b2270c7e8f4fb5d167c45d7384e31dba86a10210bc2a526b82f3783c9f70e28aee6f0cb89d56c808def642569b0de5b87f4c5baaa485	\\x89d337bb5eef77a04d988abd822937e89c0eb82ee7d04e408a63a6432ca222176d306c409c5fb318b7aeb3ada2a267a0d05ac19351304c45eb70b3a6d95c01bb	\\x0000000100000001261aa5ce09daf98b1fd1ef6e6eebd09f2ea05774b24f6106ad5f7cc0115530990066f360370fe2f5bab90473b22eb3851863aa8039fcec18702463486a3a94d8484cf45181266ce563fcd62e22b82f593549f2dfe7d46253f7464b2ae623f179f5ff08b1f93e1de62174e8b40038a7c36dab835a7f441187ac1050536a807313	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x25bf158302387a29b5f06d30facf2642b06f6ac7f50b1c0deaa9372dc8fac435	\\xcdb988d0fe700f3266e81ce3fa122370be3722c3ba00ff0891596d706577071440d2ac816ba92ab8e429312d58f523d1afdedc157bc6c16a3b43971affb24533
2	2	\\x140f930ae2d9fed38c53a414b947906a500441581350340c4ca512bcf0757225	\\xe67c1b4ee7df6cc87582100bf6bc19b72335a5140a62a18ad0bc40502f3f8603d2a4d21584a9f4609685f3f8645ac13fae41ea85a9a0a23b58f9df20ce152100
3	3	\\xfcaa2e543e5898894063f370194fffbf1b4d693b24f582d66093c679545ebc75	\\x39a8592365d51f8482bdcbddb324954332724312c5c51390bb5a2d55c64d61eb04a768dbbfe76b7ebdc2b56f971237e81c3b06d309210987f696cc39084be92b
4	4	\\x8ade43078a9478e2cc2d23c0f08d234ee87cd3e983dc28728041dc07014a7b2a	\\x9328a486ca20b61d5d574abed35c420177774d3e906f51fbcca6d51f830d63d94c63a694111eb7bf3ae71595c5f5f3b23b0cfdf7e2298fb197607755d195ade2
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, shard, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	99372245	2	\\xbdcfa08dc48ad2b5e464ded39a16524ce4d732bc18ce3c7412120eef7ce40e1ab59746ffb08d1d847769d021473efaea0435d0f91770380a28b4715a8578bd0b	1	6	0
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
1	\\x252b7e370d07a29b713002af4cb52bf19a97b5d93815b7a6d538a047f7f7ab20	0	1000000	1650031313000000	1868364116000000
2	\\x052b067a4f3b24e998ed1043c2acfcf71b89a2696d03756c9390f5699b25e254	0	1000000	1650031321000000	1868364123000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x252b7e370d07a29b713002af4cb52bf19a97b5d93815b7a6d538a047f7f7ab20	2	10	0	\\x1419a85688ddc563e7986d6652c9ba1dfe283fd3eeecc9feb2fbd50b95355da2	exchange-account-1	1647612113000000
2	\\x052b067a4f3b24e998ed1043c2acfcf71b89a2696d03756c9390f5699b25e254	4	18	0	\\x0bd7bb0262e1d1edb068862d55e3e4f396b77a45e49a659006fbe3aa87020903	exchange-account-1	1647612121000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xc749a6d1a1b2ab26a67f19f8a4e8c49d7a5cfa80aa6a0297fb66b2105b6dce49e3f21dca6296b83e63a828d1fbb3a15df495e827e8e1ac9fe10b83f1c1736c1c
1	\\x58823c81a1676f9f6bd03014e67fa2b0f81ef74ab13bf2562921b9058a86e3ca52600d91182d798fce7f263635da29f668fee480e9af44cfac5a175bc00aa627
1	\\x618fd1183418e71adf167ed1a71a5616fd311853d3f78f0b9f3eb25a1f08c6b10c301b8e7292fc51aaa9e97470619b1e7dd0ff31d94e87a63d56b3234688d762
1	\\x0b9f1f4bb69fdd896b1a4f54181a763a0145de810f87b479553cc4d1949e7fb40187b5c5a4a4e6eae70363250b7c9f8d65217ac58de4a6a3906a54858d330132
1	\\xd53c7c4dd42817131f57073a58e124131a089fe430b88155b6bc5d1b7f916fda1ea6cfa75aa18add24c5e072cb94bcb80d0e7c07bcd7b5995498812b03d8fd3b
1	\\x5f194c0a7b3c1ae643d70db7aa8d504578925744578c4bd26ccdcbb8b5463c90b3fc1ada53268d7b04a1044683693f7a839e4ad7520a4095ee3921cc6e7e7bf7
1	\\x8808fda834afb1fdc61db8e4574cb40c0ac59799fceb271f4634d3dbeaa1a2bc4694de62f3da80138f48564f1b63d828512176f6204202c229d4c823d757b12d
1	\\x7ec65f4b091eaf23dee160a2f9c2697d6041676459dfb50bc285f1f4c7edef566f1796e6eaa53c83e066fd3542f362efb5a93e0a0ae152a5a9d6ac3830601d65
1	\\xfea59fe2a758d389c54d055ff554e53a67a83631fd8cf341d8b035b30e2e9835a0f75badc604bb3084c121390e4c74ed1e7cffc56c22d7d3411ba03c47f4eaf9
1	\\x7970346cd5f5007eb542f43096775cc6c72d2c0c534973cf3d1f4224d03562048942107436d86e629536ccbe9edcfedeefa493caaf938dcce2d2def2fdacf497
1	\\x08fa7aa9714d60defdefb22c629014a3609347d94326814c9ab56bf6ba237831fa320f3edf1ae41d25aba8424fe596d0220ebdb40b90db7804e5d0728c7c3c66
1	\\xde092e8d6f09384e00d9ad961a8f893ef764abd544daa023a03dc0c999e8867c82aa506e8714785f13eb95c7753911077cb3f0f22960078aee2158f6b2c91dbe
2	\\xbf3049d6369430dc5d7ef19513a8e6a33738ef6d4e5feb5b37ef189c1b8d20e54fe752b65cf5a7647aafaa6935a494ed2506455bff3047b6f25debcb1fa8331f
2	\\xbc64ca803008a450a907df2ef3d20370a4dc34d1131fbdf0a26498ca21eb3e99cba2f390a09cd9926ddfc3e96b899d491b5447759897509543d5de6b82067161
2	\\x674862ed50201302d794138c747da0c0dc59222998d17a4bf0d23d22ab1fbd4d3eab8d73399926684ca2e2f53b477eae7abf687a984d96855e4ea3ae559f2810
2	\\x036c244b4f220618febee0698baa981232114c8c35f08d56313d070b141c8a33c8d497e69aebee321210a2cb01394a0e91e9c32c777be03992d6aecb52da4c78
2	\\x583d39679f78e1245d54aa1a9690b1d12f8a05781d4dd89d14ca8e2418093c207f9ee3df601d32af369ce51c88dc6f9ace9cd2bf65e554b95be9303dd98da817
2	\\xadf50897d6ee94dc1ba66eac0ab65a374942b688f010ce4bace4493b342df579ce3c475ca0e49bac49f7a93cf027b08cfee9558687505bac4ecc92e60aacaded
2	\\xd4b9f1c036f5a1b0e6c532f84af85d61a7240f59ff50f603130652b0e9455d4bf66643180df762a7bc9ae1e94dab34988671f56016f3ee4194a524769e858488
2	\\xd67c54ec1ec2c3b78dd95a3483acc44397ee34175356c08453175021b9dcef3000ce910b3b6fcfe8eb94dfef180a39d998648f322556eb9bd6818b4cc91dfdb8
2	\\x3bd61d70fab69f01779539a9aa71f4043a2635497c53f4ed029c1a2c464ef24c74103eac47d385e5e2493a53843f2238bb2521038011e699f26b3c45f2c5a399
2	\\x50426f76b7238142590cd26341962e4794d62ebaa63aee78815541074157e90a0ab18694e16f1609c509738ed1ff924029a173a47a78d22f20aa03af460c5d94
2	\\xd0244f7770c723965186101bcb121678468dc1a37531f08ad38c7200a7a35f0193feea04eb634b56c81aeaea813cd5cb45d9e500ecfc67d8eb1e8eaab78763fb
2	\\x926e7e6f0392b920a8b5ba7f8b52114861a691dc7164fffd6b686a6833d445fb4927d90a72752f67deee9254915537427421c0ed3b7a511dded345d5c532d6a7
2	\\x2103913abea2a583cf08a102a52b3b31ceebcd55dc11e60438ec0e540236f17b7861227a0afccf86b8f9165d5649a1de990dd32ce49f8db919a36ab05dbcc21e
2	\\x0416f6ef6248b43f2f9f32996d71e6ea07acfaf6f273ab8f15badfafb4584e9de7d654ed4bcfb5b6f6c66c0491202efecbd74bd1081ab02bac64005bf055f043
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xc749a6d1a1b2ab26a67f19f8a4e8c49d7a5cfa80aa6a0297fb66b2105b6dce49e3f21dca6296b83e63a828d1fbb3a15df495e827e8e1ac9fe10b83f1c1736c1c	311	\\x000000010000000144bd219a6a9c50fc371ed06fd978b778efcd707a3b50bb2f51dcdaa1cddc16cf67146e96f9195dd5e9d096717126938c4d342e74ceccb0cc05d24b50b030fef1610e040639a60544467c2f01809f1326387d356b612e76a4e221e94d08c4f5e20532a249347740c5dd37fe350258d9322833914f6caa8081074582878b7b16c4	1	\\x8cafac38b52da950a99046d7a5fa4c2df7da9c65dc54f24c8a623489eaa8f61827aab02a4327c66d88a97eb1ce69cf871ff1e2e68f7b87e6ea8528ea7f8b360a	1647612116000000	8	5000000
2	\\x58823c81a1676f9f6bd03014e67fa2b0f81ef74ab13bf2562921b9058a86e3ca52600d91182d798fce7f263635da29f668fee480e9af44cfac5a175bc00aa627	105	\\x0000000100000001128884bdc732d4a971febf4bba55cc5b8070999e2440e9e665751a0a0d8f6cb0e6e481600e7f5dbe89b1c936d25b3e24624bd2a71d341874b00923c8e2c082b235ac543888f65a4f0f9a75915f208fc7402e0ce96134dbcfa24e858b03e44963bbcd90eb58e89ba715c4217ec3819c2ae1fab6be81ec7bc664197768965fc0ed	1	\\xc7b7b23fa9a533ee087c46002adb78e09753b3550296b3ae1f33e5923b1b3151c8b3b6897c1341bfe221cf44e1a7b77bfe1cf8e9e9d955158c3a664b804d360b	1647612116000000	1	2000000
3	\\x618fd1183418e71adf167ed1a71a5616fd311853d3f78f0b9f3eb25a1f08c6b10c301b8e7292fc51aaa9e97470619b1e7dd0ff31d94e87a63d56b3234688d762	65	\\x00000001000000018149b8408ee8e3f19f82c89a2060d171a2e8b9d224ade633b4d4a98398c2d58e75dbb558613e13fd2ece623407214f5d357441c085f4c09ef3dc37f3ad0f12ddb24744d60f609db2205438936ed0f5fa16444e7d7d4e4080075fb82b4c73258fec8f37d14e86de459dfdb31fdd69de1a41e5abd409f91f6982a870b079d81bc6	1	\\x568da03fa01eefd03e17d15e7cc245ce1ca13c6be93412a7f22e38cf4fb1bde3a82d2138810e06c155bc89d10a7af336883ef11e372b01331a606a3aa69bc605	1647612116000000	0	11000000
4	\\x0b9f1f4bb69fdd896b1a4f54181a763a0145de810f87b479553cc4d1949e7fb40187b5c5a4a4e6eae70363250b7c9f8d65217ac58de4a6a3906a54858d330132	65	\\x0000000100000001096152607e2b9852bf9c281a398c786569efffa00d204fae43453829883d79c13c36f18e1d2d9a3d65dc5ef6c6afe07b31b3859ea2c530d36967c783ccfb447c0276f5726cab14044cc842f5a2b7c262b01ef094a17f48d3e08e0de0bd62b8979147d651bf08628530593d63518dcccedfee968b00ab03120f2439e2bab65343	1	\\x19c102fd3ae9ffd92eae736dec63ccee55420a2821b52e4f387f2503fa0eb908eaaa16066b74656977c97979b02e6124aedf127c1c79eb2175de3334792e9d07	1647612116000000	0	11000000
5	\\xd53c7c4dd42817131f57073a58e124131a089fe430b88155b6bc5d1b7f916fda1ea6cfa75aa18add24c5e072cb94bcb80d0e7c07bcd7b5995498812b03d8fd3b	65	\\x00000001000000012a2670f6f6dd9adfa32a6b2a4b9b5579e00629974d382188d4cea1a882941448a0449baddf40b942e8fcc810b702d728a97e79c7ee33272b42cc232e6d3e4676f1b12810953904484be4b6bf10350bc11bb6bffa259da92ad8f3dfa53c4da571583625186cb35b8a918f113fda8bd1371f93b5890f83d0d1b9301120887adab9	1	\\xd03ffe68e52253d1cade1eb8c29b581c1bca77a42b79dce83e2f6ddf829222ec78a73cd9ade469c8a3dca4ef0db171b2734fa7f1bd43b498e1bb89bc5e701303	1647612116000000	0	11000000
6	\\x5f194c0a7b3c1ae643d70db7aa8d504578925744578c4bd26ccdcbb8b5463c90b3fc1ada53268d7b04a1044683693f7a839e4ad7520a4095ee3921cc6e7e7bf7	65	\\x000000010000000171e5827f838d5f404c071a7e8cb18863a106e17182382c99d7095304cca024d0159dcc5a7a3b31dbb94cbeee58cf2da9ea1554f0f62b71b9ba4519eac0abeabddaa9b0b17f4a59e41ea74e37ca1ccaa1387c561ae6d811ed53a1ca05a0420a99516c1f484ff36fde02988a418664b860427008482a9b5158bc98ad1bda14ab79	1	\\x21d889a504d341dc89e94c330fd60ad9b9b37721d31947ffa78e02e45588e6867cf1b28cb1b058c347d56d9d4f7f228f90c9ed57913e206b3e48f9089a28d609	1647612116000000	0	11000000
7	\\x8808fda834afb1fdc61db8e4574cb40c0ac59799fceb271f4634d3dbeaa1a2bc4694de62f3da80138f48564f1b63d828512176f6204202c229d4c823d757b12d	65	\\x0000000100000001b185a36fce23450e4f32a021039cd5a221d1ffea10e7e109e34e1be3808509c5dd2e4535fe9baf53c66f8149d61788e43a0a0c2cc48ea005e291df21cafcfc77fa3e2e963840a75a7f99158499d23cceb4f6154342a6a9ddcd798cbea0af18c1de45bfa4e7dddc121da05b99a055dda207b236503c1029250343364dbd588222	1	\\xecd8a1e39c0fae330bc7b6c7a4d16bd6efc45099051c5afed77b0b0c269604aa169e3f2530465a825931588d23630baf451ddf5073f7be56783b30d2398f8b07	1647612116000000	0	11000000
8	\\x7ec65f4b091eaf23dee160a2f9c2697d6041676459dfb50bc285f1f4c7edef566f1796e6eaa53c83e066fd3542f362efb5a93e0a0ae152a5a9d6ac3830601d65	65	\\x00000001000000017c954687f842487d2ca279299759256b7e792afaeeaaa834a62b0ecc027d6f907b71b559e6ebed63f0e82c101befc8570fa428b7445cfc83445077207a1b52f9e0a51d69d047ae87ce4ea9d9baa29836ec887972f3c0548b9db9a13b2c32fcc10dd74c750901cda31468fe53f753ac57cf72e90eb60dcc4439f35bb00b2eb04d	1	\\x9f0351b196a73674d3de84957ae5319274f9169b458c00522d78e1f7c5e9298a7da691cfdb10c8a3894dbc761831172b024e4489db1d26ed792556d86b783006	1647612116000000	0	11000000
9	\\xfea59fe2a758d389c54d055ff554e53a67a83631fd8cf341d8b035b30e2e9835a0f75badc604bb3084c121390e4c74ed1e7cffc56c22d7d3411ba03c47f4eaf9	65	\\x00000001000000015fc89e47a7843dda68d1c4f06ff2a60b8e82bcd26f877b6c387f34d278c00b3e26a4268e9e0795502786737fafa4d59620074ec8f81b5d4c30f136299de29a13154c5cd43a4f65b268b7054ddd5771a9de3bd6ac0388bf87edda5c0d707c5499c9fe49fd6e85332ce1d7fe17b0e82ee858174655343c31de714a357c6e210653	1	\\x84e968d5b5ed9ffdf65a0cdc7edaa1ff9383d7ff6016d2d6df149a9b9cfa950229ccbf4f15eb01ae982b5d1e7c58ccd2c5ce4f27eed7419186593e86d0f4020d	1647612116000000	0	11000000
10	\\x7970346cd5f5007eb542f43096775cc6c72d2c0c534973cf3d1f4224d03562048942107436d86e629536ccbe9edcfedeefa493caaf938dcce2d2def2fdacf497	65	\\x0000000100000001a2d24d9f9e0d46cd6745ca0ab6190a0a1194c99f16f57e4a795b17ea15fd7ba9634abdbf27fa879db7fefc2e953197d387ac0aaeeda1c778ebf52f690a5c751ed429d795ffea6ece6e67e92c615b9e5e2dcbc6d494aff9df924d81945443d7e4a21eb2ec0764a906d86274dbbc15e5b1273746fedc0d2453a939e637870a2139	1	\\xde767c957b463809ec709d5d5b7049e1fcdae5033a85a3ed61c416b2f8dff1a11f9c0ff7839c8431beadb3259b63b058447b4842c78e79c8a083167ac272b80b	1647612116000000	0	11000000
11	\\x08fa7aa9714d60defdefb22c629014a3609347d94326814c9ab56bf6ba237831fa320f3edf1ae41d25aba8424fe596d0220ebdb40b90db7804e5d0728c7c3c66	240	\\x0000000100000001a5a0b7a2d867b8ca796ba63682e972daae33ca140a066a6ae8022327dc60a1c805985471cbc8d06439a26ac90a321a303dbc12dcfe66aa8a70e91f298a2905c588a3e85d39bf1a312a85bc7329afb20f9638386d1c0bcb970437961891ed7a1a41b3993b4d0efc1557863ee6767aa4cb222ffc5284273fc5b198a8a65f01b5d4	1	\\xdedffcc2e8b5e2f536f6e2fe2468d63c350746dc0f61ce4d9f7116065fa729147de49d73cc9afdee72fbf221261cfa6f4604cdbebf3a40bdd21a4a9d4fb7660a	1647612116000000	0	2000000
12	\\xde092e8d6f09384e00d9ad961a8f893ef764abd544daa023a03dc0c999e8867c82aa506e8714785f13eb95c7753911077cb3f0f22960078aee2158f6b2c91dbe	240	\\x00000001000000013c26131539d795a3af359fbde418ce624122013ec07c3ae61b5422e3a7ad3ebb251bdea6a7f62effb5121c05c9a37adfd0a76c5228b637107183d5015c8e2b1c3c18f7c7f5bb8a0bf03ac839faaae3c67d99b540f569592128c0b8e9160d9aa80f1c1ba950fe6e52da42ca3651d1bcdb37036c5fafe38e7697c8b624070e045b	1	\\xdb5fb3279c279197a0e9ed6bf74641ae111b3f2dd5e735292e2e31279ef3e9d578cef3420dfc3f05908055f862aa40549f413fe5ae90e01de1ac44c939d4150a	1647612116000000	0	2000000
13	\\xbf3049d6369430dc5d7ef19513a8e6a33738ef6d4e5feb5b37ef189c1b8d20e54fe752b65cf5a7647aafaa6935a494ed2506455bff3047b6f25debcb1fa8331f	394	\\x00000001000000015b5d62dc49429d69b6f51fdee21e94a59b4a9bdc6adc222f62662aaf3d48b04dedced617ef8eda3b532b2fd62b662775fcb7a5b4891e56e8d841a9db7ee7d67e2acac56044680263e21505cfe7d953d38d926c122315dc5eddc6c50796ea5d1e3a57247f9e223b39b0551d3a30b3103445f27a0a67edd9cf038831039572df1d	2	\\xa075a23d05342aa3f8497a6e21540405fded1caddabfc2bcee726086cd36a9f7aba9ba47f6e57b4364358fdcf561051713c001885a33528531d30311d43fe50b	1647612123000000	10	1000000
14	\\xbc64ca803008a450a907df2ef3d20370a4dc34d1131fbdf0a26498ca21eb3e99cba2f390a09cd9926ddfc3e96b899d491b5447759897509543d5de6b82067161	53	\\x0000000100000001d8cabb53b522d31d5c61724618c9d7abd25936bc23b2ee76e0eff26b345e3a647582ee5b56177926d542d09393e6ef30d9eec68384a6ef88e0f62a8ea6b32f6dfd3bb86d421471bad7f047125feb5116b158cde689294bcbe75e280017397db3272eda9e1ffbb9d2b620c7efb4b9d84a9ac09c3b7e968d44377d9b45d037f535	2	\\x5fe56e630cf941fec1793a24311767bf3a41fb4bc591ca10122c48d33744841ef0ccedd52d1f2d0d958b8ae8122c6e280a96682da276a6db3c72d2dcb64e0406	1647612123000000	5	1000000
15	\\x674862ed50201302d794138c747da0c0dc59222998d17a4bf0d23d22ab1fbd4d3eab8d73399926684ca2e2f53b477eae7abf687a984d96855e4ea3ae559f2810	356	\\x0000000100000001043faf7222fd4c85bba324e3ea7710d88bda7f8c2b492af5ce8fce819e40d9af7beaee86f60f41b11662f6e18733771a3758c4b6f1f870011ab7ae8ff818283421c60704ecb0dce6b60fbdd5b9778ceefd7896adb961254fc063c222a3e55cc0fab8cf8d7d20530deeb2e12691d5ce74ce44f2e4e67748888bfc73531e024bbe	2	\\xb8b1dda344209265d40839fc1521df2cc5d3e9f3b17a82854bfbab9ea675e86b690e548d7ebbaee8befc29e8a51437e38fde1ba99a7d136330ff649317241806	1647612123000000	2	3000000
16	\\x036c244b4f220618febee0698baa981232114c8c35f08d56313d070b141c8a33c8d497e69aebee321210a2cb01394a0e91e9c32c777be03992d6aecb52da4c78	65	\\x0000000100000001b8459738ad2a6282b4f4b22f22da58a27bddf4fa48a860154bdbbf1e3b154a652c58cb34dab9b09084c856e11b3c9ca4d4211ec7916bb2e69ba68d4c151d9e4dc20425e298e2b256fe51021cbc8f5d6398c2a18a8d3e0fb101ac42c17e5c7a1a6dbe82c46fc5b070171a55fe26d85827107259c9230a1c9e806023e8ee6fa65d	2	\\xb77f52cc062be5c982821ec7386172b01f939893e43092ae043155fe115f775060e36d768fd8ebd1a5a85d4d8a884198875cb5bf37e2e5d5e5c91ea4e6258701	1647612123000000	0	11000000
17	\\x583d39679f78e1245d54aa1a9690b1d12f8a05781d4dd89d14ca8e2418093c207f9ee3df601d32af369ce51c88dc6f9ace9cd2bf65e554b95be9303dd98da817	65	\\x000000010000000156cdc8998185fd0c9c853af18a99a69413432327efbe1daf9c7cfc552d9183935ad51a2f77f785516fe333d4b84e0625f215acf9554c2c5fc1964f73fd8a92d43dc857417d5a8e27d60f378bc974953b7c9971ed2f3dfdf17c188f800f9f4c24d72a86c7f26e5070c3a03a95820d2084672aa61345b51b7f0eeda40fe5b553e8	2	\\xf8fd78efb51333bf30a1dcbbb4dd1928a205cd5910d43e2857efd16faf3e0ee1286eda3a0de469258215aa728639f085b1634caa01a44f85d70a39d6f2908201	1647612123000000	0	11000000
18	\\xadf50897d6ee94dc1ba66eac0ab65a374942b688f010ce4bace4493b342df579ce3c475ca0e49bac49f7a93cf027b08cfee9558687505bac4ecc92e60aacaded	65	\\x00000001000000016768fe6c0309dbbde151adc82bfaab2a536e06eee7ecf26828610d46fc46a9681bff986f6728834ba10fa047ed6cf9c5e597664888019b207f39c5877a8579a5fc94a5eb7fd74318d1e29520b7bb90644742dd56f9864e9b9cf91710607e7113acbd3a7241bef92ad6507eaee46e5cf371cd4fe2083e7c00ee2e6a38bec37548	2	\\xad4be5a77d150184ae4cf2da5f56644a63e2d5d53df5e0f43208596cb80d3368ef7933f7ba10ada21015eb6c5e3186c1f6965f7a72bee4178e2d69cafaa5140b	1647612123000000	0	11000000
19	\\xd4b9f1c036f5a1b0e6c532f84af85d61a7240f59ff50f603130652b0e9455d4bf66643180df762a7bc9ae1e94dab34988671f56016f3ee4194a524769e858488	65	\\x0000000100000001236b1ccce9d912fef5dd0746443f3a81020e9f877e4c2a9a6116c2703f292abc95198b8c81fce83ea6eb98f56966231b3f76ea25b914dadf6077dcd96582afbfaefac61e86670063326f79a1cbc1929460440f4ca0682223bf2bc4e9b3d604927868bfb89fef5487988c0e758fee912f0a2b1b9c306eca79a2e5e35b2c8394c4	2	\\xe2940fd956d54a006cdd2f2ccb36ff39c7e079386a9a4be4930d194b92695a0d86af43d3f3319e35e027474c8d5ae23f20f4960eba9a0445a5e1212cf81f7306	1647612123000000	0	11000000
20	\\xd67c54ec1ec2c3b78dd95a3483acc44397ee34175356c08453175021b9dcef3000ce910b3b6fcfe8eb94dfef180a39d998648f322556eb9bd6818b4cc91dfdb8	65	\\x0000000100000001039ced639b78a47b6fdf5e7511fe33fa313cbb992351a44a115f6501d9485c1d65352545da7a362cfb37c1ef9bc6e5b0b39ca4de461eda20c7623e6b0b4444168bc50fd38871f1f2d8a87f65f336f85e0ad8a22ba389d05eb3ecfdfc94f47dfa614106ea1a9b08d3bc7e1088c96297450edf58f83d8c221d54b6b6524f581a2f	2	\\xbee1df5688baedd5b3e9153e83b71c7caeb7fd817393b8747e2303a01c77d4398dfacd970e52892488f07b7974cc1fff1098eabd01460f772f86a2b9742db50d	1647612123000000	0	11000000
21	\\x3bd61d70fab69f01779539a9aa71f4043a2635497c53f4ed029c1a2c464ef24c74103eac47d385e5e2493a53843f2238bb2521038011e699f26b3c45f2c5a399	65	\\x0000000100000001c2d37e0eceecc8dadb5e88feb82baf2fefc386ad24c6d24bed03d58aa431b438e543454689b814587fb6620e30489d406c495a8bea1c5128cab9055499f3a375d7c259a69592d42286f16a9cb86ef625b8da96a1efb40aca46e6ca774864c89e6235a706a075ae512baa2068a6879cff86e242425df1eff22fbc8de14aa37466	2	\\x9983b3ca3334850fda69089489fb8e12e87ae9db5d23abf84652c62d0009ee58e0445ae2adab7173e617beff2cdd2b411710c06aabbad8704158aa065ac3bb09	1647612123000000	0	11000000
22	\\x50426f76b7238142590cd26341962e4794d62ebaa63aee78815541074157e90a0ab18694e16f1609c509738ed1ff924029a173a47a78d22f20aa03af460c5d94	65	\\x00000001000000019fd1f33ab3e67e3a0262641a19e098e3ce8c1e725251e1f772de1c2b7ba84751a98888b0c38aaa4534e54dacec80080a1fc5f4aac1bcaf2af791e2b7b092dbe12a334aa15ac2f716266f021609073011294d5c52100aa46e3861d967eb07e15c01b6f2e270f677ebb57b81ef6c582ba7e9233c34d6ecad7e3b5fdd4262a3747b	2	\\x66283fb533cbde6182be8ff5324c16295ea1ba6595e9b94c0e7e3ada29566529c617b049a002b5259624e35f902a2759c7877ff358c52c5cf011ca9735966300	1647612123000000	0	11000000
23	\\xd0244f7770c723965186101bcb121678468dc1a37531f08ad38c7200a7a35f0193feea04eb634b56c81aeaea813cd5cb45d9e500ecfc67d8eb1e8eaab78763fb	65	\\x000000010000000134a4fceb7119cb0b7ea71769ce2e514314e553b4b87936ed4f26454a47f83ffa734e1331aa8aa73854af9c82c6a506366486cc4f82386192f1ebf1d7d621f2075666b46703ff39645487962a29e91b9dd1b4f7c8d624590088a09a3ef9f2ec6996b4076ca83ca84a08a647059ea2cb4d5685a70febffba885ae6052135fb10b7	2	\\x85cd9862116d852a4f49a81747c4f4e083b5c05c50fec2071ff5693d0a0ca275c6b4c150211663b427a5fdac2a8fe34d0f435ca94a50674c8a198bec7a9fda0b	1647612123000000	0	11000000
24	\\x926e7e6f0392b920a8b5ba7f8b52114861a691dc7164fffd6b686a6833d445fb4927d90a72752f67deee9254915537427421c0ed3b7a511dded345d5c532d6a7	240	\\x00000001000000012f90adbf7bb45565a35da8090006926cd20c04e5a2f32f6b7d86f2c86ffa9218dc6ab5ff609992e7eb09e249b8f049af330ee8c455ac4ea7511df087a3bd22c35915e161c9510880cdac18a0fb3dd1eb6627151ec33977585e41b419fdb47658350f78677bbe2a081d2a8b87d760e7c160cecc64aeeb338c8ab3d2e6d028bd67	2	\\x01c6276da104da51285eacab4bea794e78e1cd69a790285caa97a8d8edd1eddb9f6e93e2b6380b3dccc205d3f9a8c538981a6a50bb42263d0753872278d0de01	1647612123000000	0	2000000
25	\\x2103913abea2a583cf08a102a52b3b31ceebcd55dc11e60438ec0e540236f17b7861227a0afccf86b8f9165d5649a1de990dd32ce49f8db919a36ab05dbcc21e	240	\\x00000001000000018449ad6ca39e7f014f15ee1b3b9e3fbe48492d25f20986dde1774351aa31df0ed05502356a4672948021dd374eda8103ec994d642bfe95e826ed4836fe47c3c3582cc19821a407cf30268fdb419c54e55ebeb6bf425becf7428042086336f2c8d24ae4fb045ce49214fb3f93b5c3ab1813a67f51ca8a7651eb1638813ffc4add	2	\\xf6363c87888fbc07097d17bde97ee857fa996fd525041bec41e6fb54532e8020d9a627c4de75267c96e8f25664692b26b41547288e1538d7c31ff1499639d00e	1647612123000000	0	2000000
26	\\x0416f6ef6248b43f2f9f32996d71e6ea07acfaf6f273ab8f15badfafb4584e9de7d654ed4bcfb5b6f6c66c0491202efecbd74bd1081ab02bac64005bf055f043	240	\\x000000010000000117871778df69e039ea1632c6cfbfb9aaa80f38c54fc9dad608a7b44bce282f1db06761d19a266f4ead061f769867286be71c4eb9215f529ea9e6d827c56341c5cc977b0cd5c75d5adc9c7bf0b377ac13a6226b2dd8b06543444f4036f0a0009227966f6ccf1bf698bcf7a0cc6cf44c779fcfef3ee288c422925c0ae4f07a8dbe	2	\\x033b2d69c286084ca03cd8c1fb1bf2062347439d140a52372604815dae7892d8ffc9373de8a1450a1e82400cb2281c7555ef301ec72bf7145642ab7e29ca1c0e	1647612123000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x2628bbd44c57d61e902d3c4f0f8553756922774d2bfd069f12b7d0ea1cf15d5409a5645b56a1a08ceae0a30c531b11859eeacbfb0fd8c61a31d9c60b4b00f504	t	1647612106000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xc1d397c9858ce52f7ac0c594d0478042690ad623c987202114f59e281557626870af85bab0ea8b968a7ee9cde493e57a3e6a00a606da1b84c10ac85260fe980e
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
1	\\x1419a85688ddc563e7986d6652c9ba1dfe283fd3eeecc9feb2fbd50b95355da2	payto://x-taler-bank/localhost/testuser-jrtseipx	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\x0bd7bb0262e1d1edb068862d55e3e4f396b77a45e49a659006fbe3aa87020903	payto://x-taler-bank/localhost/testuser-wpkhjfah	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647612099000000	0	1024	f	wirewatch-exchange-account-1
\.


--
-- Name: aggregation_tracking_aggregation_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.aggregation_tracking_aggregation_serial_id_seq', 1, false);


--
-- Name: app_bankaccount_account_no_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_bankaccount_account_no_seq', 13, true);


--
-- Name: app_banktransaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.app_banktransaction_id_seq', 4, true);


--
-- Name: auditor_denom_sigs_auditor_denom_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.auditor_denom_sigs_auditor_denom_serial_seq', 424, true);


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

SELECT pg_catalog.setval('public.auth_user_id_seq', 13, true);


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

SELECT pg_catalog.setval('public.denomination_revocations_denom_revocations_serial_id_seq', 1, false);


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

SELECT pg_catalog.setval('public.known_coins_known_coin_id_seq', 7, true);


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

SELECT pg_catalog.setval('public.merchant_exchange_signing_keys_signkey_serial_seq', 5, true);


--
-- Name: merchant_exchange_wire_fees_wirefee_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_exchange_wire_fees_wirefee_serial_seq', 1, true);


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

SELECT pg_catalog.setval('public.merchant_orders_order_serial_seq', 3, true);


--
-- Name: merchant_refunds_refund_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.merchant_refunds_refund_serial_seq', 1, true);


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

SELECT pg_catalog.setval('public.recoup_recoup_uuid_seq', 1, false);


--
-- Name: recoup_refresh_recoup_refresh_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.recoup_refresh_recoup_refresh_uuid_seq', 1, false);


--
-- Name: refresh_commitments_melt_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_commitments_melt_serial_id_seq', 4, true);


--
-- Name: refresh_revealed_coins_rrc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_revealed_coins_rrc_serial_seq', 48, true);


--
-- Name: refresh_transfer_keys_rtc_serial_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refresh_transfer_keys_rtc_serial_seq', 4, true);


--
-- Name: refunds_refund_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.refunds_refund_serial_id_seq', 1, true);


--
-- Name: reserves_close_close_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_close_close_uuid_seq', 1, false);


--
-- Name: reserves_in_reserve_in_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_in_reserve_in_serial_id_seq', 2, true);


--
-- Name: reserves_out_reserve_out_serial_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 26, true);


--
-- Name: reserves_reserve_uuid_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.reserves_reserve_uuid_seq', 2, true);


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

SELECT pg_catalog.setval('public.wire_targets_wire_target_serial_id_seq', 5, true);


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

CREATE TRIGGER deposit_on_delete AFTER DELETE ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposits_by_coin_delete_trigger();


--
-- Name: deposits deposits_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER deposits_on_insert AFTER INSERT ON public.deposits FOR EACH ROW EXECUTE FUNCTION public.deposits_by_coin_insert_trigger();


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

