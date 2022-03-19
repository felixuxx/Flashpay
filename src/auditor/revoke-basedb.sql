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
-- Name: recoup_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recoup_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM recoup_by_reserve
   WHERE reserve_out_serial_id = OLD.reserve_out_serial_id
     AND coin_pub = OLD.coin_pub;
  RETURN OLD;
END $$;


--
-- Name: FUNCTION recoup_delete_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.recoup_delete_trigger() IS 'Replicate recoup deletions into recoup_by_reserve table.';


--
-- Name: recoup_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recoup_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO recoup_by_reserve
    (reserve_out_serial_id
    ,coin_pub)
  VALUES
    (NEW.reserve_out_serial_id
    ,NEW.coin_pub);
  RETURN NEW;
END $$;


--
-- Name: FUNCTION recoup_insert_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.recoup_insert_trigger() IS 'Replicate recoup inserts into recoup_by_reserve table.';


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
-- Name: recoup_by_reserve; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_by_reserve (
    reserve_out_serial_id bigint NOT NULL,
    coin_pub bytea,
    CONSTRAINT recoup_by_reserve_coin_pub_check CHECK ((length(coin_pub) = 32))
)
PARTITION BY HASH (reserve_out_serial_id);


--
-- Name: TABLE recoup_by_reserve; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup_by_reserve IS 'Information in this table is strictly redundant with that of recoup, but saved by a different primary key for fast lookups by reserve_out_serial_id.';


--
-- Name: recoup_by_reserve_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recoup_by_reserve_default (
    reserve_out_serial_id bigint NOT NULL,
    coin_pub bytea,
    CONSTRAINT recoup_by_reserve_coin_pub_check CHECK ((length(coin_pub) = 32))
);
ALTER TABLE ONLY public.recoup_by_reserve ATTACH PARTITION public.recoup_by_reserve_default FOR VALUES WITH (modulus 1, remainder 0);


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
exchange-0001	2022-03-19 13:56:26.041479+01	grothoff	{}	{}
merchant-0001	2022-03-19 13:56:27.347438+01	grothoff	{}	{}
auditor-0001	2022-03-19 13:56:28.188805+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-03-19 13:56:37.914216+01	f	253111c5-31fd-42af-8e52-eb11151e3ad4	12	1
2	TESTKUDOS:8	H9PKCENX1RX1ZDV8CQ6MD19N4VNJGFT6VXP2SM3MGCKRS34NZT90	2022-03-19 13:56:41.575617+01	f	f4f2274c-4f9b-498b-be4f-46e9f6c41fec	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
a4c2ab1b-f6c2-4203-b5d8-1ab1b700248c	TESTKUDOS:8	t	t	f	H9PKCENX1RX1ZDV8CQ6MD19N4VNJGFT6VXP2SM3MGCKRS34NZT90	2	12
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
1	1	93	\\x980641a3dfa692b60ba5dca7f08a6b482163942c548018dfcd5a846dc988871aa03d6250cc4f435fd512e938a2ed9d48792c1c458e7768eccb988bbe22eeb006
2	1	385	\\x07d3d16d0a3f1cb6496d4236e4613db5402ca77bb26a5593eaed1be8684be24f1ad09a01daff6b59914ee17fb19a645388a1caca886a4a290cfd4d3192800b02
3	1	227	\\xcf348eaedbd46878e44aa71d0479edd92b276a2caa33be68d886bda26266b362c1c7084b78fd03f6c535f4fade2c647ec359dcc72eff7b933709e8c16d104902
4	1	253	\\x158cea51cdf378ae4c2eaef2ae43c6a93d13b6d54de3d80ce8caacba355a50be29b923a57c2d84c3fbf3891793638571a88d7c169895c570d0f14724bb240802
5	1	410	\\x48f94d7f6c35cac89023694dc98ade2670a36faa830e89ce2256b25cf49ca5d53fcceaa0b48458c691116175f48971d468b11f8849c24e4eacbc47adcc87d20e
6	1	276	\\xd7dfcb43ae5eee8c4535dfea2e3c31c6ab6694179c7e95076ad14ecde2b3d259697db4b597dce7c41fe4eb4020847a5a053c96dfb887c38f616a5e0c758c270a
7	1	408	\\x7653a8728abe750c133f8ac4274ca39f5f794059bfc7a094b3b71c804d318fa6bfb2605ebe9e21469a455cedd6b23088383be7ad339f56704b162136a9a69b0e
8	1	340	\\xb6514799306bd0a5418eec11ec8caa33aef31fed4d4877766e7a243cc09679a36611f6f5ba53ecce5a2f2dce3c32865e51cd8c7db2c8e7a2947086a7e669ba01
9	1	299	\\x6533952539231b92e79971a162c86c10ac364c28ffda9ff8b4fe926afa3db6770ab6b3dd4b74c742531a4421f1d642c0988ad712651d36baf6ead6365c53320f
10	1	252	\\xfaf16df2af26c044ca00283b354c12cbbf1b545693d55c2fd938b439966aa94252d87e7a26c78727104c2b0c29d301e7b7d7bcf9c9e8d81204fd67be17bb6c02
11	1	155	\\xc99410495767b497ccc9905a5a60a46c2f0af31788daf02465d97871754887a41b84835b5584d2cb87ce99a07bb4b2fc6a737c6774a469241f4f6269f05fff0b
12	1	177	\\xbc0b549347f50e9b43381ed0885865de9e5a62b44ec0773f102f76759d0dc76bce6ef059189b930cea0ecc894edd3fa9ed91eff0f224871246545edacb0ef40f
13	1	4	\\x7f80250698a0c4e089102f5769e0cda04cec9aa7ab2a1e27cd8440695b9e192a2d917755108ba8a0b67c0d7ca4c3ab9ab41f76ee861bf15e4bedbf7707543408
14	1	355	\\x0bd1c79608d2fac375305f3251a4d88455b2cfa3b71575be2854101271542b81f0636b1370605d9eec354ac3f3a65ba6a8862e3a0df7e984dfa7a322c188290f
15	1	20	\\x08b0211bd3128c188e3fc0592f6f2437a0d1d7058d62ff8296a410c686df9f8765e33ccb5c629c7c4e6a38a5479e0fd35f2d8f6d350a25013ae1b59bbbac7901
16	1	328	\\xbe7ef5a7cc5e5d5603a6d366b9870e8106b8be62970b89310e6726edcae3a2c3ad2fccc185bea6c435c3247435f3eb27bf0b5223cb4843572f146808a47e0a0d
17	1	172	\\x1c4fc413a65f4de76359c2b7d62ebdb331ee09f858ee5c3f2267b784c2eff642f2a7c470498d044831b9c71eecb6a7a0a6420568bb85dbabfed9a27e85d45b08
18	1	180	\\xf420d87496a4e895cca4cc87003424d3fcbf21a8e003086e759696f04312d5d0ad6f81554a32cbed93fb8a58b3744942571c6cd1eaf473a9c6e2fcfb8a630306
19	1	10	\\xa863c1ae77c853b974add7df2edc037eddbf5c87a73de91301ed9b5f740020907f4658616247cb0384a5e8f195385c7ef387ebf1f0e54177e6eae6c674729a00
20	1	296	\\xcec36ae12fa3d0a32a75d583544556a75069d685de7037a80b8e65c6e9f090c52aa421daedf54d3cb395f58f3f90595a6740dfc8e7c6dde932d21a462f96f80b
21	1	105	\\x9ea829e80e774109dd865d6e9d42231ec452e27cc8f0c6a59c5f475681f6712a8880a093adbcf0d960051aa2a6cfd9e19fd52039cd39b56dcf029945b04fc70c
22	1	421	\\x49185a0ca445a03729c77c8a97dee31bf022c1049abd7c0c71485870fb56f50aeb2a20e7f3c57472497e49e8bcea754cc091a6e5dca9027bbe5bff39e1226402
23	1	354	\\x84cfceba0078d475b68850279c012e3b035cd510cb000bba7bbfd6dc8cff45bd0888ff7131bfd9bb6f0420f43a202678bc73b46f49e437114fe246ac45fb5f04
24	1	404	\\x67e81eb101fc26b828dedef6aabaac934a14080626784509061664d26ba51fe5370d53b0321e1361cb76c07612d89a3bafde298fab8c8761df151b230e208b06
25	1	327	\\xdbd2167e91b9e719647b44ba699e242e94595f6e75698a691a513092c85f07be685b15585274a6996326c27069a95525cacb67bf4363625d84fc9740bb8ce009
26	1	96	\\xaafdd30f533c53142690a4b001412cd6d9308d8fde98048bca224205a5c3592c2bf69fc95b830b1844130e4241c40ee257ef021b4c4730957f866c52725ca508
27	1	225	\\x05cefe18b390b4ab2adda6df876c7644a12df93032b7e30e8f7c1980929608615d1d1c3205aaaea86d6a6738b63b37afa40ca8e1ea6753092bd099b3e6fd060b
28	1	17	\\x9db424cf9b00794d89c7a857f4b4a19e3050f728a46b0c4f5ec80ca9c9382f61648d3b9bb3d6a677e717eb6ca4d8c364b386a36f41bfb43d81f69dcaddf3ad02
29	1	331	\\xf445e1aaa90669561f08c20e83623b2ed0dcd047ca23a6ec6f41191bbf56b5bc08f87bc40d55ecc6f40391dbafbd494d0049ecc83cfe9ce5d3c762a5a0ec080c
30	1	82	\\x474bdc0b7fa0413260fd5a906a8aa7f794ccd80a7818646020d44e7e4edb955cd2bd6e8fbe62ab3fee8e9c9c0815a0baf631ece1823796ff7061b5b722f67a05
31	1	316	\\x7225ee34095695264a2c1bef74081a035932778ba0f582608816cbd78b6363eb1b5c74651e912e02c88bb2147b87d535e902cbab0f77a998bf7cef52b730f008
32	1	325	\\xd96e3e1be11e0eee3440c8a059a2a352f088e57ad6ce54e3f4d44a7a5767baa976c4b585c5d43649f245b354c14ac95095a2cd06014e62b44acc7942608af500
33	1	261	\\x59391bf4b5fe5e6dc38afa85d5ebe9e4152f9962a015021d6bc178ae33d39b16725a4e5b66a9acf822feb25014cd60b4547f1684295333a7930d3e5c5ef9b001
34	1	273	\\x1394d515bc35ee5b57335bbe82d0c8769e5cc247ded804bc87a415aa20e0f6df9622f2cf30a10ca9cee2e247efe44474f3cfac3d4b5fb00c24fdc6703c9f6008
35	1	41	\\x111b70a2bd2c560ae5447e18af0a6d0ad26e996c4e63a1ae6288df5c90d9cd095905631fc179019c5c8353e65a852b04b80bbf8735e586c3691c574c86b57000
36	1	26	\\x03acacaaa0379d54cbd0c2547bbde01f345d778bc98bc7f7e3a3434a6a513c1311103059bb2e3bdf2be039da4363d95977881cfdbb7b06f2cd04dabde64a0102
37	1	264	\\xfe3b74482500669fd83903d44a67cba4b6fb36ef1aa3ded0ca945942cd376ceee4b264070e16895bee879a5b39b053a13aef227a2c92a60157c3814b90f0040f
38	1	235	\\xa411b81f6ea93ff462b843591620d6e11aa7e8f69244efa909e98e92188e0a7b6d3eebbf6f38099fb0cf2676271618109327d180f5f8d9f4fae50377cff49e07
39	1	393	\\x083aa86682ab99bb925716d7e803fe0275db4926e6ce18044eed366a817187da4b62faef60a01e2cbbaeb665b77862149eeca39ec9b9bbb83fb2c56125431905
40	1	329	\\xfa2a3861202c10797eaa8280f4b80560e9808ebe28a6f1011c24aae8ea4f724d2f4de5e8e09a27eee9e0ab4ac17912e736820f43a2365d5d24c7b36b2198970d
41	1	22	\\xb16f045ca72e91b9d377439e065594c6890472f136e3e5bc521f02e70e3da01d3b01e93cd533c3b4d90b27a7c9d4d490cfc36c281ed4cab81c3b3bf809d4c00c
42	1	359	\\x1cbf9dbf7867938ab03248f3e8d4040b14028b4ef651aaaad5e85a93a805e85828cb9fab3bb9983b3ac47b03cc0de4f6db5fe17d7da607e3a3d8f0f221dd8908
43	1	394	\\xd1987d89eafa78a58b9cece1b4beddeee1c0e4e913a1ae6c76730566b5a3f4e936ceb231d5ac93874c87172c9be496024ec7f40b251343baa426561eecfd5200
44	1	411	\\x3eb5693b95aea53fe1c2a54f35118191ac3be770a3c3f18f35b568f633ea402af27fcc049d39377d493f2e27765ef9329b17f60129d59b77e0c4c35ad40a6d02
45	1	142	\\xb64167a1f01fb6a573bae1e86b94839128080467d97481a889a81b220ebc79f6d99a7c376d87ea3205b0aefefa7c636285be7c76cc152458e0e9070806154a02
46	1	168	\\x881af22d61cdfd1042465cb3f1e925861b3a4296e679091cbe4e33eab13fcd69b20dd6a8e6873cf5c618238a2e1a0c5f7e6c30a02164231384736f856b371000
47	1	226	\\x7bebac8b1f96bc762fd2dcce6ecc4bcac202dbfc1e13db2f13bc87675bd38413dff4b87496cb1d9f650d624bb02020ea7d5d25d96d46d08b531334789ee93903
48	1	365	\\x8bc217a00fdc263b9430d15cc0fc59075b146de65daefd3df063040b7eb955fc594271e24593434177d4868eae42f423a5a2d31ceacef60f39e96039c9933407
49	1	343	\\x6d2d0ff0aeb88f64ad8ed5fa1d262184a05ed762d45747cc0ec6d38cf4c24d01632296df7c89272cc04f54a0005152bc5a53656afa4e712b3c4247aaec2d6503
50	1	304	\\x5e6fa5cd3766dabcb3b0c47f9ac5f0f07cd1dd23efb9635c2d2af554622060d62b8127f2aff0a18f9a32a7490baa101783bfb42a22dee09d9127964e02242904
51	1	59	\\xf4a6b0b3514288729079212a68290a3bbdf01de1e62f2f25e0dbbaa031dd3f3b232fb123273ec8b85db287c242bf2015a4c69b092b41fe1ee610e0e03421430e
52	1	8	\\xcff6547bb8646e6d8bb751339931acc7e7710ccd860a3570fefdd16e420d1ef18c6d7d54bd4a68a86247e5ed5abea9d5f32e3fd7f506cea604bede12e8e3fa00
53	1	241	\\xeae73585a76ff54ef107ddf2642fc6ba83a8d694ccad39c6cc2b9b33cd0e5683c9e326e6b28fe68f65a0b774be0e82346517ed4fc0a74ecff0da8293f6bba50d
54	1	363	\\x9ac0a027645b10d1ac744051d6ed192a03483f45f44be6a3628ba9e02e8a4a7be63abd33e7880d0f977986a73e41a0d43d7e8b86f26fdd0c4d7670bbe8451f09
55	1	53	\\xc8b01c6276773ecc0d82a1f81c76636aef1521958b303d7be338cef137fddfe5409c921b66abdd8167ecc59d4bf4518f47902bc1e6f8d84dfe316b3b432e6403
56	1	151	\\x167ce9e504081fd1c39f9f253519f83426f2d23d6cfdc4c1be5c25bbff21cb371a24948a95ca7700aa9e8ee6f06ce467433412411ac71008a580da39b8c8700e
57	1	158	\\xff575e27146889e0a811c3d15d36ed14c13a9450b4c5fbad78c53f04eb45ad1412af43011cce800d2ac23246004f10108acd0400797435306559a590f9ff5e01
58	1	44	\\x3eced2541846793bdc99d0a613fd25542d97339971b9dd5d165795499229c8b52d27a94218d40c186524c5bd626bed521ba5c07f4e2a814a16a4341bf2f0ba01
59	1	39	\\xe5277b8f8c25c5cbf47fe56e0bd1ca3119c0030b86ab84fa9f0375464b2ca0330cf1afee42c0d5ad75fa64679ddc76768066a9c23d884ad8777faf1cce4b790f
60	1	146	\\x81824693fa396a91caff761dacc0c21244eb474e84a65c9e028aa1ed8c30a76c9cd82817233c5d6a143ab1c726deea5668c711e8d1e0586e772a0e1195654400
61	1	150	\\x448aac0d184402ec7c945a168824e4559253927ce04762a0a414629b4044760e2c4583501d1447597acf9b9df938a8e63ea71bb368094a12cf24a288bb9dcf08
62	1	38	\\x009302fbcff7fecbe863a8f18edb92b7e6be8471de5d14b1949ce2da529ffa7b99592df9031d499f0b15c9828ccbf3b55a4e8827857042b7554efc7287f4bb09
63	1	203	\\xf173bd61a59519e6df02ba540e0909f882e04893ebce988898429c66e75b7ef50018854ef5f438c31b1b70bd1e5d16cf6092eef0cf7d033b4434dc37697ffd03
64	1	379	\\x40820cca2c1588b86a79bd3db721d1723d7b1d41d4b981db27a01212d55f70b6e81512bd6137a694ef7ff41cae41b7d040b6d00e5f17e872fb01289e05154f06
65	1	406	\\xbe623b19d1fba7b1a5fe7afbe2b48d10bf5cb48e396190200251e9deac2ce0ab3d36b5bb83d545e378ab4bd4e653607ffceda154d3299fc97ab23ade3cc36c04
66	1	377	\\x58a8a0dbd178370e5e9e96e8bd358c02e600c20ef93a6281df82f018038d47e6e0c432b03dd84d95fa90ed07f9a8afc4c8cc1b2f9d7f30da3f71bc4fc2dba308
67	1	183	\\x8261e193622caf7218de130b9cddb367eccb9f7356091fdd6dccea71e2285149598bf9c620dcc0de81a4c07a4fffabe51e99014a330f5de711b62034a8391c02
68	1	179	\\xc6918b17c1061ee730035d8c4ef10dcd27d5587b14b7da25ab131fe8d4a78e45adda8e870b8aaeaf2845d406322c473757ff0d0286f9795acc590d01fabb500a
69	1	391	\\x7ea2d5df4a22a3a378012bda6abeb9cf2e88af1a92535a8d70b1d62236b104cad911b4ceb4b0b46f36c4181f71290c0e3f09acd945decf1899af734f84648606
70	1	249	\\x46164fc794fca5b3d5635367dbba4bcefb98eece0f4272b57605b64e828d4bc3c613c7391d96a04e7353cd51ec956f5a46b42b49c08d4f837e568323a173db00
71	1	175	\\xf2638635426913b17a80b79e805fa9d733970992a2afb4f60c16ecee5ee51b9dba641a46ff58e640b432f4c3eba8c5bbf3a5015b0b212ea0724be57e689be803
72	1	109	\\x1999f64bb49239107783f4c75d0f71845be9931aa80b079e4f48829261133153535a1588e41c8ef98a774a7c68b400295410789f74340cdae91311d01416d607
73	1	244	\\xaadeac237b851892f2989d02c250e1e2d3175d98b9ac9428f7432abaec2034e54c0283fdb2077e7c25c44c4cf887a44f79b4a63336df14e57aa7edf62703bd0f
74	1	48	\\x6bc3c5257638ccb06c7c354298f271d7acd6b136e4c3f3fce1e677b2b9de72726f4a6066c93df895658df03b2ee1647a53ac8ee1083cf9cc6c18fbc1b2b48200
75	1	202	\\x6d24813577d05c27317ac20ce88754079ec51c4ddfb48666be818359e3f120c1917dd9dcd9347e2e3753a0ecd4ab0c2d5203bdf06a101d11c8cb14defba23700
76	1	231	\\x5fcaaa9756fd23f89e2deb5d0cea4cfe2d7545fef270ee1bfada23102c8db794ab5edbf2a623536ca704a88db4fde121d9ef23fbcc8b9d807e2c909be6aff406
77	1	326	\\x6a25a5acab9ab1acfe1c59eae780fa29411324ca03a30127d45002ffeed8e562f3d601ec794a9b525bf4e87607f515005e71d27888047fb6bee7f44587d0ef0d
78	1	320	\\xc729abdb0fbf458a4e80befe7aa951c2b4a3229331bba1e4aba7e45d6a0432a6ffd24a574d97e6dff676a0244eaee62ef125fe9a1a432347aab9671b4cfbd607
79	1	348	\\xb2a16bbc91498b59940c36f85b06c8b6a10e6a885e1045e71f17157e792db9f64cfae5cd872acfbfeb5157bb39a1a607d0a3afdfc410f31df9422d21e12fae07
80	1	342	\\x6c95c1007e37a1c5e1912d53d622506ed0b50265865cb7d596d9ec02b4133e9ad193a97656992195ee538b4662397fe492f3536ee40e2ef60cfa525322007005
81	1	11	\\xba50bcfbbc11696a4ff7a058f65e2be18b46d08efd8d69799e6bd07b21ccd53058ff6f8b29175510a81e0091cdd4f2b091e537d75ac639556dcbb2c00bf00802
82	1	260	\\xbd33457d2a3e4a47f5d7d715cb64b386be7a60552b603474d93fbabd6ca3c66d5b3ba3c7ee904f4c7185c2b91b4cc2390cd7bf23ba2893abc4c45e747cf5ba0c
83	1	28	\\xe75b9f277830b22b1f96b6c8ced499b7b62222b613921eeabfe8600e60a4839d267044d7472ca135cb94770f4fbf4809d20a865e88908c20ea7c070ed9b6c40b
84	1	169	\\xf3b186456ec2d931b36398bc768c421802fbf85e33be0d0fc0d016f7e0c5b827a6582eb72357d15fd327ea0c82b6fbf14e3feca3b85f0169d57014b62177f204
85	1	50	\\x2618711c9d26c8adc28a9923741a2606fc45db736ba48b6ef529097a22d18bfbbdc68134be442fc1d96dc263030e57d46462458801d3a8c696c811ff899eb205
86	1	213	\\xa36d54673752ddecf798b0e9f33472f98b617d4b6a3b94bc93af38eecfc9df9bba46d557f4c94b8d988162bd78d9d2f3642fd016e1d7f22bf62ee629a9cf950c
87	1	185	\\x1419f4d2956307e4150f662d9532136b1389828580a07170f6aed42a841414d34afa4e8000ab13e48d4a9e511e6659cd390f29b1a8aa18267dbc4f0eb22f6201
88	1	49	\\xb645b0ad2d8eb2e41fbb8efcb3493d1f0ea7b9445ef74f454b9438e1ca792a172349193a30dbf2a11cf8aff8d5e349f72f908e8d4034a2a169fe793609cdf50c
89	1	31	\\x3f9c21523ac61b79eb1e20a719e5f007cedcaf7f49953fc9ee8c0206d599a09988547d56f5c59c1e5e62d83517a49e6b8749af75ec62a4c5d0415071a0fbdb0b
90	1	409	\\xc8342e3b22920e43f43dfa1be05120fa40456701315fe2273f725dc394a51a18fb8849cca41c1d6d1b2755d91bd494725f5e3f47aa6d486acf25fc1468847805
91	1	140	\\x8a5f2d54dc9fcdbc96a370b803b19b5ab32fd4ce99349ac4f5678b559815ba0b34875f4571295effd9885db345f7492f449ef51f4a1924889f59a958de5cf90f
92	1	60	\\x588fba7d216ccd84854d5169113fde12aa35b9866e20c8a5fadcc7b80cdb355b44caf15d48da390007098a1d3a8544fd008f47dc067fbbec551657f446f3a904
93	1	373	\\x295b1fe3c942079bccebb21a0fd24e49c1a3bedc2c1f4f051160cbf75d8fb19c3ae61ee78503699c1577b454fb9d63d9d3a45a9a6296657f20452c20ad9bc401
94	1	33	\\xb1ebe068d1a5c3b4d6f1b6b873157954efc5d661cd25bcb7c3bb0af3a8983bb0f1d770c9bda3bddac576ceb1a48a2be1d9d5ad63f231747c431cedfd405bc504
95	1	317	\\x35067a1d79c9c681d5f331e9409e18ec791027ea21470d67bc6bb14e43eee101e24bf213c2dd1de615ad386ad0443aaad4e3057894fc865bfd854a7dcab32d03
96	1	221	\\xdac66717d449cd6506470e378a9216d3273d757048427ca0ea19eb613d12c197129f74a985afa978dd8674f53b52651433c150a92c3555580de92b2c521c6d09
97	1	27	\\xe6f54ff6c5e3bd77817ce0d0ccfffa7d639202fbee357d5e4f63bc96bc7a32d41d75e088e0a58a8c84a6aeeb6fefb2d03dbb8864405c17885fab0bb9276f3e03
98	1	207	\\xd1c63f31cae04a59eeb95bf8d9594519aeb1c0ff7c02616e708f1c47b6c83bdf7e93957446edb345de2eca6e032c61ca96b76b949d838d1609d4b3f643721f02
99	1	62	\\x9b75fbb4c8205d2eeced4427108d681f96f27e2e2ac66eecc52112c405175a0d3e9efde965b0622c8b4066168e9e2d1cbcb3376943132c6ae1b38cf4aefde300
100	1	298	\\xed40032f6c2398be64fc5a2d4a3366b6c58b12b2669b28c084000d2b13201d74174c946fa88f57e253cf673cb2560abcc73592bf7697313817079c07f037d503
101	1	405	\\x44971fe6398e1b43895aedd94412b39eec4f9fc89065b59590970cf208df921bc6c44ddef0d695883ae10932680560c398e30ad5001818bf952768546414e206
102	1	211	\\x2495a5e723072f291d64180d1b1db31ab2efc0059ebcd91b6a9c71daecd348370e82734de21c72658e49ec86c7e2083bffe2880ee0c66145218b5d1a897a9e09
103	1	362	\\x81fd459ffff2098bad094b348dec2ef812d0280d99658909870f5ed2dea410f3d499094d24994bc19c9e97f89bf2693fbd92309440d972e54aa0b87cc3035803
104	1	130	\\xf1f2425afe385b1a38f3aeef38a060c1e7dcdd19f4416e8802c04b79f72a5c195a4f89594a77467616383467573550439e652c55060d7e2865528a8d269cdf0e
105	1	350	\\xf478e6427cdb4779801e83fb6135e581867cc00a2c2da5c27dc1933d47127f2091629ae856726d055c4ec1060f9b989fe2d567068bea9c468f44169c5eec6101
106	1	388	\\x6cfacfc0e901f7ea886ea26def0c64196186aaf0c55ad1008d6b9184f12dc62a917ed66f4a560061ab209b2ecd362d28fa064c084d3c78b79fadfed888f17b05
107	1	282	\\xce1c03682cf7b64df515ca2b102020b2f0eb066fe3eadd2a538e75b5bc19d24503b01f22bfbdba0e02b21e07885d183e31a312b8bea6b55e33b7a0b0695ba60e
108	1	412	\\x519a449ec514c1a5f491d9960360cca38322722080286865fc127d16e417d8a983fa50457a892fe2e2373caa6cda70440fb9d22308837eb6a43852cec0395e09
109	1	103	\\xaacc5dce1fc3cfd889ba44d4870ed08c0db5d071340be83c3e1d3a624f279c38f184e28a6d40223f86825e4cf6d8eb2104a0d2b782be5239d4baa3e3804b330f
110	1	346	\\x7910d68789475d71c53b3f71a35df1538dcad12c7090d0e91b5931fcbe80c1f993cf60d10caecd89abcbd490e78500cf69268d78352b4b11cda9a2e48b708500
111	1	206	\\x0bcbf150bc21078bb09ae7e4dbb982cf3e45aa8a30d1b0eb8d9d55c87dc90ad624cdba85b4d41b32cb0af6ed2e56e497fcdd3bc30173b74df885d9f932f1c20e
112	1	281	\\xbe1d2a97bc468cf6eea7e83223d3bec44c144ab4afc75b0ed4a79c82ec15f4e21ec826206dcf4bb32d4881aa0404b28983609e64abfb594ddbbe01dddff30506
113	1	147	\\x4a6b74e1682475d3ed76dad62c54e38abdacc48a0463a5123433ad4a61e6dc3af4646ea26c35534942b7778c9bd4a81eb15b432c4af61a877301463927b5de0b
114	1	47	\\xefcc70f68dc49274070a4a78d45bf54ec8f52c5745f6c2762890672e9c669c34ff25a3db3a2908063b077460b17f487c471bccd1bbfc9484c6c61c1140e8600d
115	1	242	\\x5ec2ecbb6943f6a2dfbe7f5e32091ca8d18d6398cfb755e77b55ac1241755e0053c75565392d171a6e954b4ec991208fec39fa6d9f2b169580422529ab7e010c
116	1	255	\\xb21aa8b5d83841353ed3192e5497bae940c0a17172832e391a81c40c9fd213b16f02c06103633a49a3823cae650beadf4e652431b27acb24efdfe22a19bba004
117	1	306	\\x6249b12d0923ac53c1d7a30e462cdfa6ea0e892beeb8dcda79d04151905b3b2dae696442fbedc187ef7f34dc1d5451721a4bece6406b22cdbe297e590d0b3000
118	1	201	\\xac67099a092758f7cbfe9b153b2360f94ebf6860a3edd94d3d3fdbe7fe0f49fcdce05b836f4ec4071f307d14af71c583e1d1c2de4308e2d8b0b1004e57d3580b
119	1	351	\\xc233b56a11e7a2d333df279a02401430ad26a514dc9225abe306e81cec3c53de8f7693f00902cea14fb4f7f96c26f84bc75112bf64656263e49a7a2c60df7507
120	1	79	\\xfc7a95d22b4db8f96c7c6e7cb01dde3a006cd09a9508af830d6749a0b521dbfadb188202db079330b6a23ee8dd76dbd07860185b7553dd5fcf2c60774c15f40d
121	1	310	\\xd730ece37f3ee33affbc4ebc714a5929da132cc5f30315034dceb491cd3c951d06db628ccdc1b8cc6753f700017e5752fa22a2114bca2d3e5ebd7b1ca74ed60b
122	1	283	\\x5e6ad6f8a67efdb5b6ddc881ad454fece6192fc1f01275eeab8c165e684178f126c344ee194e6546ef26429b99ce2d91d26be5ab712aadcfc31ec85cd659050e
123	1	339	\\x3435b6a412fd7888a50a0c29e94b0f29b328c7651c24227606364e63516d165769c76b06487cdb8edeff5bd9db4f27913bf93520e1f69cef9fa340e237ee8204
124	1	418	\\x8d58606b5e97f89b17705c13b1b2dda4668b41a6948d07a0fda20bf5309987958b871295aceb2ae69c99754b90f2c64e6b0afb1606aae32a9b27a85ee26f7600
125	1	34	\\x83962c0d113e63637bb3d58f3108aaaaa3f1b6f1a6bc299bdfd66b9217da56a54783cc6e994a4aa2a990af59e6f8247254a553aba5d40fa8a5051cda7c9c890f
126	1	5	\\xb69219af0e1222a2dfb1581d57164bc52d00fd1b140f993042153d90856d9d6ac559f9966ddb53f710fe42ca6f25c4ab3bc592c9845ff81268734a24e9e76409
127	1	247	\\x2c3cea18bf94e608e9c553c7df460ef6ec93695ad2a2bed96edcf11b6f8e24ae015bc16b30a558fe3e1586113b5b99f6d5510652eaba3e568eaaff9021237d07
128	1	24	\\xa2b215b7281b47df5a4c5af9622897f038cbc2bf27bc91128261deb2b292f69ab017e514fc7644e1215deb9613d9c9979e82271952db0dbeac24474edc060404
129	1	285	\\xd78eaa3704eed22f6d753392be93cd85209ec389ecae45b084011f361cd075a7261cb349c7b832ce683c21cc3a738f27b162ac081b5f8a1e5391c315b968d405
130	1	303	\\x8934c69caaa8bd525f6ec80ff116fb9b895c522741ed503c6a2cecd8e008ef74c7bcf64efdbaaa4359d763d0eb50d8856c64cee45c20ea94ec57983221fcab0d
131	1	67	\\x11ae0344b7445f649291e5d5c2dfac1c01a5e34975fcf4ed518d7c32096668fca947a78eb29016ecf1fb0ac7dad4262da7b4a33c92ffddedb80602844123b104
132	1	14	\\x616efddf6c8deb5f946454a822acebdab1260452534cde9d830baacf8aa4a345ae635c493c82e35cea41095531ab76a5bf4fbfab8009ba3714bf692cb9f2b90b
133	1	364	\\x4ae3a448d6991465deb2cd3e87f1559ecc3affc4297bdddcc8edac01d6b75376e26ad72a17c570d228ce253f3f05a88794274fed5e851005e5bcb74256503e0a
134	1	58	\\x25b961f97bccfdfbb09c2a725c5e1b6bfde46afab3db4fb25a409d49a976c13f9b542a3e2e39a5ef7cf0dce32ce287fca76d6290b7e8c9c645a9110d0f54fe09
135	1	271	\\x5d3d80fada968be92d10b46bb1ebc91bc8b6804605c4d8b2f7653c30f0b354c979b169906da17d91d71f77dfc9e6f573dba61e9bc82353c3bbcc605acd3e410b
136	1	269	\\x7a788a7d95df0d2738041c5ce8306507e8622e9b7da2c66bd912da0184da3461fd03ad40257223e26eb41447fa31f0f664edd22b9fc0bfa34091d2a680e4df09
137	1	149	\\xddb7e19eecb8e4d95f11ce4eed5cb84f6ff7a11158f5bdfcb73ac675e3dc9f7100e8b045c3a4f934fe4806ac4cd17e89d712997e66caadb20af893b04e0ffc08
138	1	87	\\xa281a5162049f9fa3f444c2084699b6c307dd5a3ce108d83a0b9ba8b0353260b1309f0f20b306154b6c1735f87ff868ca94c7065da1d8bbb0506ffc91280e401
139	1	148	\\x31734f80035b2027240565d2f1250899807d0c6ce685b64a09eb93e7268d8edacb8f71a537f1f7d84d497a7bc32e1bd0eae057abe6b0c921d1bb629ce119ae03
140	1	174	\\xf5bb8e1314d9277f5777398c0f7724318fa0599777e9d32d8e9fdbc7bcb915e9a95e517627a8daf96290489a84ffa627b0cadc429dbcbbed9aec17fb9127050e
141	1	68	\\x942313ca733d54589f228894934979e6ea8a0ca47b0bec616aa88abed8973d344ebc6062dfab50605a5308ca294e09c22900c37cfbe8b92f5a4cbd8d1f8eac08
142	1	184	\\x6d0b3b0256ab7d166e57b224fd6bf0473b4abb83c6481d00130d1279e38b74a0f9df289f4d445ea995a8afab1a8d0fe37cc1d92ae12cdc434b0a514338381909
143	1	204	\\xfbaee75b79a7355e63d43fad8ca0780440a04a1c1a696b8bd9449fd36e4a40b44b350590583259551c877d14e135eb66f060af455997095320d6fe2f329dc50b
144	1	88	\\x2622de32cec66d99c367398d9cc7026bf5c5bfb5aae07271c1dbbee99b08ec1ca011dd7ba437cef1b9667bacc693786457db6c6707a9f812ae511255a02fad01
145	1	99	\\x027bb2164ebe0edc1f35bc410493633ef5e96b7ddec2c70c91e5df4cf507530d98ee408caec9e79d79c2b1d28fd4d54c50a305c73dec2e1148463bcc9fbda20a
146	1	419	\\x1dfcf9bcf950f4fda034d46bc3b2244f2d3cf63efe477129e450c6734ce01f3e074aa7aedcb0552ee83b66e1e321625c3a33eecb7443868e266efa8daffdc90d
147	1	290	\\x1b28d4da4f33e1e20fd61ed1b85386666d7ca2287b030f64420de652b5e7b9c1c96694a52916cc8489262307c0ac76e581ecd05add4022625601243cbc8c350f
148	1	160	\\x8c8162939d390c967a4f117415e76926cc930c66a498a9a58e510080227fe8da109bb85ba2965b76578ceb70208d7a94fb51319e3282c2329dc1b5a52757cc0c
149	1	30	\\x5e88608a4c7176e18248633d2baaf62ba8bf9d2e37e2cda1af2c860c0f9e4bab71caf6eedf1aacc9b27ad4aa8e38de466079545fcb9199fd94ad9a5f8bfa4f09
150	1	195	\\x912fa37242cdd03b6297dc79c5e26cba6ce502146f78d1bd88bac27fef3f0bb978ce0f6e86f4ef3700aaaf22a1bbc49b05a6b8d7c9f8150d6ec021f96d361a0d
151	1	83	\\xf284ffc6b3d0d6788b42a0d94cbb9ce29bbdddd20d92edf7d3608cbed6a467c65eff7b3908cc0e23337e96ad44bfcf6d176b3106233406db93ef088bf6bc8d0e
152	1	69	\\x1ac84512fd4c38798812c5aa3c0d04a396efd4bfe2a87b47dfba1c6b702998f9927cf47f375f6cc5d199c1328443d16cf8ee75d18d439475f9c477a60c4c2302
153	1	360	\\xf16bccaf22a7e66eb3a711a5eb90169725222a9f60d9270f10844c1f536821aeb5689721b0fe6bc0ef2f69074a436243cee31cb3928dda1fb313715f66ea6d08
154	1	136	\\xce7ec7b403656e8827b56903e0a6ac86d1b4158200aca95b11fc362e4e1ceaaa7bd5d8ddf0b6f9d534ac5b96a6bdd828be4fb0c79c8dee9e4bd571567dbc180e
155	1	137	\\x744a3b83a4a8336091ef7addabfe9fe6ba34a28fde98b7bfac7cc7e965cbade21d9954303897e8daf2183f1f3b60db5164ec8301a15e6f66d29d0cc6d8c93308
156	1	250	\\xde364c3857126484089cf6aca9405bfc86c8c216bc0a8cd12aab5860e6c0708a7f50b03ed0a6bf8e7c43452ad09a8540cfa394afaa6c7f11eab27442241bcb0d
157	1	116	\\xe4f16a3238ff7ad8b327ecb25e13f177ea8a786688d4a4f23d476886b9654469cac8b877ebe6b7b26a2fa556043c46615d9f731ab4103c1b257adaa343ccc20d
158	1	181	\\xb5e3cfbced9ad17d666ababb56a3549093e01aab91a604d13f0bf9b44ca0d6b4160dec89bc3c2a6e937a990b7b483a340f5a675d32b53037bf3c5ca032d0c50c
159	1	78	\\x9f7d4df84878b244737907e816013c1f115f9eb1d0aeff1685c4761bee706475f7be764c890d4f04c2c7910756b500f48a4a54ccb908d5a2b45e017664919d0a
160	1	97	\\x492da148d8695551fe4c0116deae6ff6a1e59a9612e5fbb293d93078c0fe82f561670829e96cecc96108abcc413cfeb72f1fa6fc434c50a8752f1a8d2cc7e10d
161	1	70	\\xb314b01cfa26dfd3fbb7563e37882773982f384b903c15c8467f4ddbbbc4a25bfe2d30d4aee3b58965038ff061152661e290cc9d67ab3a7943c807dd3d59a40a
162	1	245	\\xc8a1fc396b30f4bf8375754b30e653a55bf9535c0801353ea601f3d4c82263c504419f75a5c4e216e631c905a002c51ded7922a13b4675a89caae8d9312c8106
163	1	6	\\xcc31e4ab29e97573e677f452c6837c0c8a19e0d8744ac7cc992b9b5f2039761706938861f9abe6635cf0b2487b0f790230ca3fc547076e647b7d26e1b8921907
164	1	157	\\x23e1aa6523e3dbe3afd28e0ea57d228bd391923310d5bf11e2b2469b5a62210f48d0f01b7c3d312b4b241a346726987bcae0a2677595eaceb467f310bb0f5b0b
165	1	114	\\x57d741e3037e649aedc3c5f9d32fd3e1b925a2ba2470d7eb8e61553cccb4685077a0741d03536f113ec431dd4e5518f27b2695f0c5a3dc68548677f823512c03
166	1	120	\\x78e0666d319a617ac26a38447fd1884d38d920475cb35adf580bae1f5f205f7168051d18524fb590091408a25eec4be05004e1c766dac3d3031f7cd76c09b10e
167	1	51	\\x3d08331f91eac6a7c4dc9d7a32e80f44f4ba951cfa5ecdc5de1354fcb07a9cc11c90284cfe580fe45e99617aef7876e5caa5363101a7542cc44c52892f162a0e
168	1	80	\\xfe2dc1d206c0f3eacbafe67c7547079f908d649692e649a50d492b472a25ddda54d45a35098eb86bbdf059d1732a0043fa5cd47bd3e7f13c75fb62bce50f9206
169	1	57	\\xc02cde1f7be8fe4d762ceb1e37daeefac2debcbcfa9ad40959832a1fb23e55a0ba1588ecce398464552e28a077e5b55a8781b9be80da1f21e70ff1dfa8be180c
170	1	144	\\x8ffa6e27fbed92fb48b825796e2b8f2f333cb2765fb0b92e03b9c5ec45258fccddaa51472def1e839c510c53683407662d79fed51f32529504442ac6d2e20a05
171	1	189	\\xcc85f382f6b248c084da8adc7c45ab56bfe249fac6c7004e4f95adf037b8be0559a96e7acbfb941eee1e3c4c4047ba1e1507c9055ab75cbf038c060deecfed0c
172	1	153	\\x062df939f7bd706c1c8134924d4e3accd2a0a23d18c93340651023a772371b2eb27b5d0d512a9de62c6ee63a7e1d43e081c0de5be7c4b1d663d2f50728f3df09
173	1	107	\\xc1091f09b9f467eb82294bb29fa2c8feca93cb778e013a983ab59f0f5a4a0979fed24c75657fddbfb710fb33c276eca0d02737e2f032257e8d2e744461006700
174	1	223	\\x755ed1e998a20e2bd07bb0622bf952a73c7e4396fd1c2a4509e64af3dbf88685357687511329590b2a9ff6bc7885105b3b208c0ee8c95db4326a2b28fe019000
175	1	414	\\xcf2955bcc57a0c8438e6031b933224c12d1b1c0daf9da715848f20bccc76d7158e6043c2ae20e547c8d8bf99e6dbdd85f116a1f9ea894bb51ef47cf2ddd7f707
176	1	403	\\x94181affbee94bcfa7cd0ee0b039d36debe921f2d707eff9497a32fe0c739ab35ad4fdc0a88cb52bfe9330d3bfa9331ee80dd03f5c5aa4591d590cf01b07a00c
177	1	372	\\x3b520510d68846248a0a51ef629f78cd741dd899ba5c4c46d7d7ad2730f9e62b1a38bee76eeac0949e91237336d41b91ad7301725df0c1e37356c7653b8e3801
178	1	294	\\xa592608c45d731b1107f5307a48b944d689c7031d31dab4843545f7f4854fa317c6622dbf4d39fb67595e0dab1c68f0aec69d9412028c74c79d5c68baa486902
179	1	212	\\xba55a09c1a8e5646864fbbad9c4c2abc99f6b1bed809717e80c443b0d38336e55f7bc0cc93d6514d3ddfb6846da45843b87a634bf7022903ffbf7dabb7617c0a
180	1	338	\\xfff6182339944a5d30e63a773d2dc25f6b97860117771a453ca82e6c4004602e5405eb72add6a8dfb654baea2ef3a084ff3c00b7862ed199d4b5f1d03c372508
181	1	358	\\x906d445635a27d5df666414e3eab7bbe7c4abed8043d9637c601f5e8c464adfa5f1133fec751c487c2c212fbc25c99972f31c0c9e2ad94e71e54e191f5fbde06
182	1	390	\\x169bc18dada77013706aeaa111c943e8f2e2ba963da3c2ba9f01540afb4346d4f6792a277847691c9558cc9c21477129bd9edc9838ba48e33158427c888bab09
183	1	141	\\xac6f258343153e03e85ac91a22a058454419661c9ccac15a9843aa6be5d0b571aae2cd45f3028e434ab0cf77afc48a17392f308ce509ae90896f8af307ff0c0c
184	1	420	\\x2afdcdc33ddc6897b5879639a49487d448953b27d76683f6d283fdb8781803dee8ee3f353eed06b4132094f61fd02b6a53868718f51ad2f3cadd028753de180f
185	1	217	\\x72abcfeabe4a1656066b03a0b5141d04925dcb9cc4fd8a8b579320bbcd4b4c3e9eb019460b23491a7848a10c3df381bd0953312c6dee1c2ff80055c87bae7900
186	1	3	\\xa9a42665dff1232ee136c1b7b116aa5f4a8bbcc17cb52dac4565d59643661d66e34e5af49e62d4f075d32432c0cf0d28c1304722fe0112894e79752335235207
187	1	122	\\xc52b263816836985e73d924ca4e75757bb02a27a9af06f22ee7923bd9916421021ac63a75a85fd2368a24e18a0a4629dc0215df492bc503b5a8dcee3a4e91000
188	1	224	\\x4c372ffb6df4f61edf775a310e5ede7239fcadd7d33e31c0427fe299192df8a3768642d60a881359864264be253283147632b2caa4990e22d12d865026d29200
189	1	81	\\x7a792fa54746d01d521d7de184f0cb146bccf561257eb9534c171eec7e55089cb1c7b5be4276b706ed0d25161a484cffc4add1c1aef4b3612d83d6e6a0131d05
190	1	13	\\xea49852b3e42924ebc76970aba95a27540a9da3826b9b97cd02eee80eb477e44851f36d11724152d43f85ac5a49d175b3a9c5adc6b6cd323853ac7ef8f7ba609
191	1	312	\\xa1226347a8c1d30345776bf751309b5dd5d85b2186dde8d6675d5e3c7e99780098a1fc25984234deacf0d02ac7fbd8b30818257b61979f771da26b2a55c36209
192	1	357	\\xaa4a3d473bd433e2ff518520b27f7c5e11d0c71d86864e522c4b69dabd44387a4a0835fec713cb463a278caa33561f0e618914dc7813d586a59ce8ff765aa206
193	1	71	\\x8db458e86a18317fbe623ca1c4cf81f5d8c3976b2dee5bf7a250625b978af3a47adbb4a5c3aa383175c0ea03de33731727de5a6fe63d52be58bc7b9318bcab05
194	1	401	\\xe9f37824e8deb14e0565f97e532734e598f1656706b0c60ec6852f5f97d58a4729d8ff9cbb43dd5654da4421e3d5129c8ba62a1067a85d941330eb1f03779b01
195	1	398	\\x0fc321198b7427039006e5e014c4113d51f542f8b1cc422519d36f7eea3025620050db8d6b077d97dc7144d17251d522c37392f832c60f3c977cb2041157cb07
196	1	309	\\x3e2d951583f83b242fd1cd45e49784efc58848a94213b092b18d75a7d17242bce583b42b220fca630ac241ff8c2a03d4e37d900d8cf6159ae0b70be2965da60f
197	1	229	\\xef0d3e4b7bd3a6a34bcd7aa4edaabdb5ed6889c8e9f529255992123e8ece506843df5495bfdf939ed8e288acbd0c0f48753df520c03b741699079feb0390b10c
198	1	305	\\x0d0127fe871bd7543c8e8943b4e2974887449bff30e731ee5f1733f8ce37baa04ccb547faae330130625b539d2d1ec5b26e29f17cabdd0b38a454b16fe848206
199	1	291	\\x0e9ccf5f66dbef8aad7aa0bea0143d845759550004ee8cff1b33089a7398568b4186cb31720c84f385d44bcbed9cfadc2186af435cef9773e3ac71ff85376a0d
200	1	159	\\x8e07e7c67f98509c9d1570d17c757c5037cf50c7646e937206704e5e6d80b9192cad02f16716983bf8b6d9c9b6a48986972cfeca78aabcbe1c13bca8d0b86501
201	1	90	\\x18061618aa1d15afccacf52d5aef6b67f1e62d27e71ddd36a737a02aed4c86210938f5d8f3fdee3c1c7683ffec5ab7619f23d91678db658a978ea11dd2b90c0c
202	1	188	\\xf3a645bfa39afb6a6281e8840726df2e76f1662f7428fe80df94c7eb2e366a2824c7132ab7c734ed2f27178538b6446f14a56b6919b383796855eecd98924605
203	1	52	\\x6b2fc040f63e032f408d5427a796ab95212558a08d6f6c1bf57a68ec15db59b59ed643d47a874c08b4179818559b12cc24f971c081dff345b08a3a75398e4109
204	1	95	\\x57b884ce05e4891c18ca25fac526815733c88f96d7561f1242ab2399902ef4cd31435fa6ca89c417d46ea2c34369010899746774d6ce99c0c4f1b14ffc81010b
205	1	234	\\x0470f87081c26e26fb4d477d574707e13630303b83736a79016f9db1a154431b95ae8416ba1e868fb55df1e90155ab879ea8e4d2c58e9bb990456f9d72f68209
206	1	322	\\x0405af310682fd6c53cfe6a52207890e1f958c1fa490ce8546f4efe53290638e812f04df3974c415524890837080bb95a651f4a6c3453b777d6ed11bbc643d00
207	1	112	\\x8459a40f373097f18339466c7303a0ad2bc9c642abdd20c4314bc0ebb6b5997bf036c0ed1ca24eaecd4face9483b0ef9d8b5f89caeba58174d7de798ff294205
208	1	35	\\xf58aeb0b520b3eb995440d2a2c8b618d91e9da8ea76040edf81c414da4d01d9b36a0824dcaba1f02620eeebd2c737a63b9a10d47776da0dd08541366b2981300
209	1	163	\\x9cac0f3ca38328576fdee8e03b2c277de8d16c00dab6fd3e5d3ef724f013632ac80636831d005f83a23fa8976c44ab9f31a1e1ac9938dc7aec2be8b4e0cef405
210	1	246	\\x01cd88b9a62be6dd385464febe75eb1675ef94dcef4bc26430671c5f4daa8ea71f029b5ca49ccf4fd5036ca8fd88d4f3125e2ba5db9e4dd3b3db14e97475b60d
211	1	194	\\x5097bb77bb98c5a77e750d18625350d174bc63c7ae3c843e97133a3fc1f57687ec62a21e367e8637a356afef6eea7701e51d018009f9a57c82b6d0856a836b0c
212	1	380	\\xc06c3c5f20ea8de57b8fe7e54f41dc5401cbe3eedf57a03154c5dbd547b7c8f7f1457153ced636e4005ebb10439f8166e74475795724feed0f732efda6a04e00
213	1	115	\\x4871b7508ec032490ab66229a78b9950e7f22d74addb44c91012f9a2713f57860e0c12f85804692e76b174befc27f440e9aac829ad3a5023ca5c8701bf131903
214	1	324	\\x8974b0201e751bba3ef2e5c19a7808ff0254752873f1ba76902f13b95a477433caab6ff4838f9c661f23e040e62c80bcc72b805e2b2a00e8fa0bf6851148890b
215	1	381	\\xd1080e51ba7f0f82d6f86fc0d439e49fd6739a7bc9a3edd4cdd2dc3b34b05e29937fd95962d63da2e5d7c1624171097a8d0953f7a54c4c3ecdb11a1252cb060e
216	1	347	\\x7bc95f2de10ceb3714aca7d516b0e52feabfaf157a176477d62a123bac0014d132ec3f1c85105b16a79e8b645f76eb9b7badf95af4fe72700919efba7e707801
217	1	275	\\x508777724539ad68d0a10cd72b1e44b208c6905ccf9adff4aa37db1d6f64b4784ba7f57a0d0517c12a8576c2b0821894c045220171933ece1c6c1308d76ebf00
218	1	233	\\xda4c4e7679f7cea716b66401bff52b31597243951e1a1cd460d4d867bfcd238a61f493e574b0018a8e8283cba7e139c92698d0e48e496691da0b03b45381ef02
219	1	46	\\xca7e92065e368587391259d58f1eacaf6d143a1d7420cb78536c9f7dcc4a40438d6a476acacb9a4e031b06ed5f1f2b2ede3bcfad21986962267ef2b339ec6f08
220	1	214	\\x82f74b0b6cdab13edbf18abf3077eb48a75bea27e780d3e25530c953fda34273ea76bfef0b98a6c872e900b4028bd1cae918aa0759face47d7b0fa1a6684730d
221	1	77	\\xcdc1e3593d2521737c024e22409b414edd910fc1d991509a615ac368805141b1fcb6da72d4ea07e5a4f451c9f0eb4a1e4a5132b7a1fb74258bd2a115a9da7e02
222	1	383	\\xd64779d30ab8f2bdc6abb3d913873b58f708ebc817fd026b7beb56b20c01e1c142854bd1e8f3820b48a2521035c2b836f15799ca2ce121c626659d65ac330a01
223	1	154	\\xdf6a65e545b854f70e75acec3bb9799c5335d77380fe11e940169d7a59cec9e1deedea41a86a336908be7f53c1e885235b9269bd3a8e437ea6772febf1a0ec06
224	1	336	\\xaa4e56ffd8bf367d50b15f22addfd2169213803029e8818cce550713346c264c62f703548646f8868a0958eea54b3d7dfa696f1571bac758e994c2f403d43900
225	1	345	\\x8ec558c5e1399a9ef0f466f3e200e87386356115e4d7d56bee32ba45077c7d41cd8cbf4516e8b2a09f14b7debed59081e48b2a612355898af946fee2f36fad04
226	1	138	\\x5b76f2418bff593ed937d89628a5e863024423c2a17806d865e3e4a709b94f7cab773ec250395b69b48f049bfa7f1aab3c96319e722087f65a559de05adc9e01
227	1	333	\\xe1dab9a90f6744178c2ce98b72afc8df0204eedef4b8788087c309561a653c265e9e2fdbb7a90433c08b6536c4e287e4db90c84dd59d3aa049e14a32e163cd0e
228	1	254	\\x83fcb4879d244fdc2ae740f567829b3c8a5a274290470d8b7ac9c2778afae9d919324f7cc25d114442c525f99105c10b812b68e53b42429785b3050c26282004
229	1	263	\\x39ba218f605839bf90f69630f4262aed7b6b6903f08116b592ad4dc27810aaf1d56dbf603cb9e5dfb289027224bd3dfcd23244b590828e5b356319ec9ad46c08
230	1	196	\\x560dfb086d4c20e5c73160885d9be7c7e21391dc9b7d56884db42087e71eb75b11c83437a90767ce8973aeab58ce9b59f8fb10b8d85885ac0048ee18ecc6420f
231	1	63	\\xca5921636dea45c9f5f0c26de9d898e2822850942ab5d9972d983489cecb7074e9986ff72609cf1c82b9910707e6e103bfe60c0d8ce7994d40b987012ab27f04
232	1	382	\\x6c48f4fa4f16d60567c3f42889b28e90ed53832abad46385d5a3b4f7ba794e52b0bfa3ebdddb8e4976f9a4bac52cb84968ed06b2229ec1d98b5c9379fc6c6f09
233	1	101	\\x7df8063687f2097a83357dc4161f9a787abb0744d42292a0773e3404e45646c38bf22da218652955daff3d50fad967192e7b6c8f3b2477b9d8a7a44bc010f60c
234	1	266	\\x0b9adba73053202a7284fed6d22f0c304eb25402be2c5b8edb344bf41fddcfbeeb179c795c47e56a4d87a80b6c00d985d540f4bbe183fa2f040f30001d641505
235	1	186	\\x52c09d657128fc461ab6e4fc3a41bae49351af5c435a02c3295d815832603afc360767f9b1600c0c15b9db53b6cfba5ac36f04d2f96abc8fc129d091de81910b
236	1	126	\\x950d4a5ab556ea51c47b0b86337778ea9772e4ad4b393b005d044da16b8347f7f2416943607a9927ba29cceac4551f08a9e9a4cc19c4b0ae11005e7c82294109
237	1	301	\\xc1ab5b4c82e75809ce489ceab6033eeb5c8bdf27b6a61ac474839123c6bd99057d592858f17ee67545faf8942e58b60fa65b4e618594023f676b03264f186600
238	1	257	\\xe0152c1b09d60416c6be038509633df3b63b9da9101327fc01e05dd547aba2572eb553ac7f611242ba00e9bc0d8010ee297ec9e7e80622e0cb2a76ba51542c0d
239	1	9	\\x20a2dd20233550ac2282d19a9a7db796427df97ad356561235dd9ff782ffe2c98307308e89236a66d6c6c6be82fd66ae37d4416257493bde1c062c79339b9c04
240	1	199	\\x849374b16f0f4789aeb033645eaced263d4d1ea18f77373b381f20642fb76e6095a681e433a8a05215c92783ce3d5d96d5d7bb78d9531357d3ed08ee57a25601
241	1	167	\\x69c17ac94a74b8d3022374d2bf575a8ab6b6961db4898b733ae23f75b33f1b973e18d99689645f330482e712ce02c40e40ca505b7548b582e06ac87977c3b102
242	1	102	\\x8de090a877422a76bcc1b3e8ae95b4b23fc2f756fee80e46a6cb29a36cc4e31c0306a632d621d98802698bdf34d114df151ee46cf958b70bb68de94a8ed94008
243	1	392	\\xe3d858edfee75e45da252f820cdb638a03102efa7bcaea5ed38830e4cc53297f8c846697e0718c4af3a7a1d4a5d3ba630f2f29b44536720e5fbaaabd322c5b03
244	1	143	\\x71946fd26cbb95dd7af0345045b98da049f54736074b3e1b3e1d0ae44ba469ff6c4bc7adcc077eea8bc4eaa0652e2ae043c7a070be72f4d16d1aef8e48dc5900
245	1	40	\\x87910e08f2b26fb0f4c12af9f2656849af875325e17d15de48e5938f2cf810f99b8d96c5f2c14d35a494b8a8230f98edeafd01947598a3b2937de5d25fe1260e
246	1	19	\\xb3d6d08581785732d5c722ce4df18462c286f5adf4fd4e056ecf9b1fc9fe930795e5c575de1ddb1bc3fc0a236bed7b96e7050a263a69529c45de946a19016103
247	1	55	\\xa6be6c19a0b6878c17d9786f2b24d0d499a3aeac55665ee75e2efbcd39ea3f4c7331c3e36ded7d2e5ff9e09ec8a9b9e98ccc5d3b6666c4b922c797f1e47b5e01
248	1	187	\\x7a43a61db5791e59b71342dc4474869e3b4c5ab654eaa6f0f46bd04af89b1bb0b522c1535acaf48a043c4388312469965d7a2f30afd8f0c034e3cb6b02bc7408
249	1	370	\\x3545216c97df54d0b0fdc26974e7d8635a792fad3534d1dea76d18aac7a6d5a4d3aea3e231eb02a30ac946394c7d510983886c931f273a49026158ab371f8d01
250	1	402	\\x8decaa2674668eac8f68983efb598d04380e8f9a95c7c8efbbb93b80f4747f8845bf43cc5c66db0723096e871efead44b8ce0fc1c0ec3cf279c51e6942467205
251	1	268	\\xd12f22477dafd45ecc20d03200b690bc6229009ae51c6763a45414e7a264db4bff80c682ba97c7b1f568df24d385bc5609e2462ab12f0e0080137effa0138d02
252	1	321	\\x13598813feaa9a3660df9981c1b8a4c749fdf507b93f96863b21a8644c95570330bd90b8673ddf446a72b9d3ddcb5c99c8fc5169e61a938f82c503b1be088105
253	1	84	\\x81884803feaad91443ad6673dd6aa44a8761a5cb70761a4f5506782cb1ab5d786b4c9f9229310a1b9eb3633f5fa3f8e2b05b327f2f43590998770f9d03236305
254	1	349	\\xa3e043126e7e993478819ff9aa685eb98d21d4a462d50f4cf991dc43948932be460799ad568c31f9c0c6884ccf776e78dafc5ba16324216643890fcc162fc508
255	1	341	\\x7bdef43b926687f5cdebd2e537445851fc8465eb8b28f6dee3f019378944ea7d50fda55939e31bd1aac0b843c974850b1c6803969a62c886fce0935618cf6b0f
256	1	42	\\xb91e45dd145ec0ab9937fc46edbb9fb89b92ce85f5e790663acebd6e0d7635793e7c8dc7d84ad8ae6658607d6796b8b73837ea9f808468f2a32d41a13571ac03
257	1	7	\\x1c857111c4cada80222f3f0ad0cf0077d6047b0c4c64fee73e145533a30318a509a9884986e4f755c3e4a7f6cfcc14949bfaba618b0a23b9345fee1accbc6303
258	1	218	\\xcd73478477ecb433b51b3b19944a704e4cebf9b0425efa5ff9652fed7fb5ea0fe5aa92a2ff452353df924e8f819a62503f8be2c79c884ea624dd00504f9fcc05
259	1	139	\\x07f2949e46a43dc18b3a530711174a9d882fd4c15a2739ac98c43f84212d25d04f2c9593035b6a5f8720b9b7677c449f004d8026c6dda0fd7c921cbf0d29c608
260	1	162	\\xd59adbb402a3c7d8b05c6e173489c7c59c7b607caa7539066f4197c6ae01badc825386118302c7c04c4821dffe0f987c5bc6d715b459af7f4861b46e01a67e0a
261	1	98	\\x8e323a7414b046f91400fe90795f7c137940f1718d6fd381109625197607a7f43499db28af0868133a0d909a079cf03565f613aa4faf128bcf41b0d374c60405
262	1	371	\\x2e00fa3c0fd09dea03f14559fad50e7929db7ea7ee58bca1cd4e880d4e67cae5a6420176061faeb3506176e3c3191c9bf8f2eb710fca01b5813cdc3211a28f09
263	1	2	\\xd2e74d0075521142a51fc494cdc524c644b11a5a9362171d024bfd0a2757e1622e835c2404c09e6ed43f0a08ac3cb169fecf502ef2158dbdac9ad2023e2e9a09
264	1	208	\\x824c7a80b9150d6830103748bc9331e208dc1d87b848016510e10de9b2558eeb4755eee76bfe9bf80d99d07f15fd68a778c4f8981c0512381c781abad9882d09
265	1	295	\\xa69bd7af0e3ceb543f1c65eb0105c06a803fc99b2b3a8b8c4438d0260ef9fee2969728c5149de98fdf1bb3147be5a3cb9a96045145f066f884fecf4ff852d000
266	1	18	\\xb533fb0368c6e41cabb941fedeac29c458a92357f594772377d2cc6d5acb37f4e7ce93865452579a119407509d17c5e8486136d1310de9e252d7aecd694fee00
267	1	72	\\x556589e668192392e9afe2d475987c1ea6878c646e0f0edde0fda79bf4ded0135e42aad396c4d747d3265e27db979b1f8bc0c77dc5a39ba7a56db3cff9bf090a
268	1	292	\\xa33abd60b5ff471bb0c2fc8750306c8c48886523e5b68a50b869089ba5cce1762d95cc88ded43e8d58374815f25e58e26cd2ba9d0c3710ddaf68ac8f32539a05
269	1	132	\\x298231a782ae58442fcc59b807763655721b3714c3425c79152251ab513ad6111e7b4f5241555f91f72ac286408c0406f12f6a9db62bd7c30a240435bb4f0a0e
270	1	16	\\x80ac4dc15ad8b66ae67b7c2c9b823c548beae20bc3ae653e67818b6b139cd3026d099b16e712be3682cc4972723cb16ea8ec7c66670e8eeda04ba2cebffe5004
271	1	238	\\x12324d00b8021e5f0a034de654b913c33cfcae3b5fe3eb6ef6bfa776b12ec37afffbdbca32f3b49bcba095d89758d4344f23e0623a4534b2a84c6fa9fa67d20a
272	1	182	\\xaf05e149444650ce6eae8da389296114ff106e2acffdb257a456fb86237745699cbf4f8c10e286f491015a8ea71225738b845111a8699edecd5890286c11f10c
273	1	265	\\x1373bcf4381e3171102966bb936d088de69b0de5d3dea5975123d6c82b53f8cec84954750b5fb00fc3054a07f8bd0a56bd7c846f1bc402e0cce5e58a7e05030c
274	1	287	\\x94302fef942b7a5a26e2456c77577809a0c459399b732056c4ca638eb2274f7dac81c013f3d5c18c56587c227c8cdd4e3a8d824df671355b344b633677246f0d
275	1	413	\\xa24299de67b466400b4056b11d8c7c40c0e8176401e79317cb8b3ff0d4f0d2c9b4e074e32b4b05d00309021353b8c5959b54b9ccee110c70c8ec46540c53ed08
276	1	170	\\xf457d881a97497f6efd4ae1f4e30ee4cef6c5c7c2b62d6e22b3389d7d78208fca0b64310a03db5b52a74d3eb52c37ec953a596fb028f2670b84c83f643e72200
277	1	94	\\x854330b3f64df2d1fba43875f4d24ce3c8341ca88565cccc045905f1d56c214e9209e0f2322cf5d720d0496d93c5115ad638933b39aa13d9d6ee850b64aeda05
278	1	222	\\x1f6c7d6aa74e770fa209d6ad4eb652b3594af4bc967797e393b4195063f79407ae928d76f2e8508166bcbe8602f1ec977305d236d13cab102ccb5be8329d8a0d
279	1	85	\\x088ad00c429360c30aa646f90bd892d5cef80360aaa43530e45cc18475e399fe25189d047e4fb8bdc7f4dcd66b003a859ab14a3902d88f9516345b080ae67d0d
280	1	277	\\x8adcd1ac45ab0585211f9b77496f1c1b6ca8b218d9d4076f539097451d2459c257f6f80ca8e095a772497496fa99183feb0702cad56a7737feaf08329225cd00
281	1	210	\\xe0be6d326e53260c9a59078497f9c7949c1b9d0c368ceceeef7dbc2e71d57ddc1fed9481daedc29abede9517701e7502cd7bc985c2203cf66799125d501ee004
282	1	165	\\x1d692630a1df1ec98e1cd457aac0e47c46784c241605ee27a9914db2cbdc7009848a825cda7d13946511bfeba21b41895fd024c29f5ba22a578b1d9998925909
283	1	374	\\x4cea9c0dd7c8021c072993e54f8aa72986a2921fbd6e747ceb63abf18937fbfab34ac47df32133d9dba83452ff0f7adf4e9f0ce9d94bae564a9b552fcc6a2d01
284	1	198	\\x4e36c536b27fec34f821b01ca09876914413739f4452dbb045cbf2829b0d5255e7ee9aae3d09262476f8dc6796c65450eb0567132f269aa35c91f6ba08172c0d
285	1	243	\\xa22e1acd36d4dab667e97d7095dca167d09f582fd317ea67820f7b952e7949cc858bdf377fcd13642a11fb6ca1d5edcee51659595af9f8720f1e4462b923120b
286	1	274	\\x47efb7a86e985f81d201d83f343aaaef87037ab2d53fc7cf1bc06a939165c6f46152c3ca7004213fd3e56d503ac2761af85e275487ee802c5d80a060af97b108
287	1	262	\\x7ff25794e5e748727ab39aa6a37ea3087b458fd32f75af460e9ec72c9db8dd7355c68d681b7a48971a1323cb31a40de3f7563f99f46f9a59f8eddbef2f54ee00
288	1	424	\\xc90033076bf5b7600e44dce011ddc50aa36c6be833a20971dbbaf91eb2185b952804e1343b89165593b6c99f623972d51e82a38491124764a74f375f73b67502
289	1	417	\\x4c8121e9f0bd4f8b3c5f1e2a260dd294de505dabb3d3a3104cf3ce0e2c2ea1f32dedf98d1c0a8e1b2f4a527a7e78b308b061bdc7a1f98182beaf44bc6040720a
290	1	237	\\xdf417fd246605b40e1d2c3422e89bc72c2d2f517810cb0edb35bc686b7877ffc701e006e8fabb641f2504036d6c956506e41df1df871785dd5fdb87652f3b500
291	1	220	\\x3ca1ba588e9c869a294291ad328d5d49cc1eb1e0e4d148bb39f568529ad0752595473974bb9596f5e903907d01f13d7f33b23f0dc8813125888d3c735ae19e00
292	1	74	\\x899134cf74a2d2e272cf3a56df5a37f414f630b7dd235fae3f937cd2c8d415f60b0b3f88d806f027a89039e81e27e3d9aa85f2993559de973dcc59008e0a930c
293	1	236	\\x92b3fe7f08b0f18309a2d83aaaf94d59074deb38a02090b9f68744455aef27d9cd8c5c3f5524b93696c4e64f71ae724375b0f03e9bde066e70a68e067a3af908
294	1	173	\\x6545cf044bc7e09acc1b7f51d20bdb113f10fecd61305248372ad24a412ed16550b423ab80eaad703d3f4a162008eb601ad283395667571999805a51339ad002
295	1	416	\\xffa29262cfdaf5e93335f12e6371454896146d9ccb8e87deed002f51d43c389286e305d3180d41e4a186add15fe0d9b311c0ac52e0cddebd56ff79bf6ca4830e
296	1	386	\\x0a431a8c1b490545b127cf669ed90448ca1ba9ec349e01aef2f634e5ddcd01f6ff8215b582281c388a7bc2f1015c66258741d618061299f2723539a2166f0b02
297	1	192	\\x3e94f6ba19288caf44253615b126bf3966f2777c2361f9c19221c93a0517feba3231454c9ca40189f940f461e5b73e1f419ac0f590bacd7a7a3cd816cb55ba02
298	1	36	\\x9c4d7b64895c131913ccbdcd88168195e379b3118b02001e2803332ce5eb6d29c77d66750d28c2ea813d4c52cc8793eec0f83fc2e7fef98ebd4a71465c6f0501
299	1	127	\\x906e745d090d116492aa55ac02a87469e9e766e8c12b53889c6535ea4bd05146f7f423bd73aaa6b9814e95c780737e22baca4e39da2df8bd23b755bf15fab709
300	1	407	\\x074e4539ff4b83750bedf7e8a9b5254f005a8abd14700c0dab4a5c82347f322bcd1fd83b0d12512f2ec8fcd8d33e281bab882e52d655558aedb3b254efac6a01
301	1	286	\\x728000fb96af78db8128642055242df6d14a86080183e7914b59ff632427b38af7f6cef879e25654814811d3d041b7f285cc14bc9ca1fc9c7280b4a394b5b102
302	1	117	\\x7fb63c0e9e30b307ebb20412a0ccfcb9188e219ae1268960c8c140fb526473531c450cc36c77724f5034a67c3d5c86fec7b0efbd794a32fb8be7c8f96415a905
303	1	133	\\x5a927894c6252a7c82d078e1a4d9699b8185be366a164f054a9871b62c5f781be137b27fba92708a905ce0ca70a7108db9b32dc027312918b2b9279321706808
304	1	66	\\x891e5462310e0b5e7878234097e22b2fd5b2bcfbc51cafc79b35329ce18176fa03372ba78703a028183cbc551eb0c919e422aa32fe3929e75927d658a929c702
305	1	302	\\x1a900e0c506c74807e32529f5dd4ffbcf8349ed561e46d6cd1ffbc94cb855393920798ffb5e0b40895d92694d58c2928fed4b0826e2a63f26edeff878492c60f
306	1	89	\\x26689b56bd1c018266fc687d3c7a4d71d1fd2fcd9fb759a739f7d3f19a0fb0f6768918ed24ebf0f109a60924c62e8ae553767fbb0b5a03d553354ed6e68e9c0e
307	1	337	\\x6911a6226569a27d0c2bf6dd39c92c007693a02f1ee2417a6cec3554503ef80a3b3ac826f3db3b4aa11c6973d9a611879453126c2c508998763e08b62292d00d
308	1	369	\\xe1335246c89aa9c1afa404b3892a0f9ea9ba3978e03f9b1c9857491d4dc516dd41c34ba3f9359f26360de9a3b1513b14bf2be20e0ae7e1dd2f2cd53c09330300
309	1	128	\\x213050a4e0fbcff4e0dff4cd0294238ea8d49586e2874da8c681f8b96bd746193fcc5ee5bd7f8552f5a21d910a6a95c7727f435659abaf5f30680e266452b90e
310	1	64	\\x4d28143439f2c194e2456280ce1fa80c2bca6d3e1cd746e8f461bcdeef8186dca77b0e56a338fe7f788eb72782bc95c7bd90d156163f86c054e47eefd460e60e
311	1	423	\\x015d6bc241a1289b6881f99e40a119230ec139274a59c5e639f67301fc3f285a5a1cfb63bd2ffa25d1af7f064a8f5be38d8f9a38cda5a2625a1534782218d009
312	1	76	\\x40ed55755ec5e52757361039e5138369bf14315da405f652a8c6e12b75a8c6e03dfe15257c8524c36c4795822606c122e6407b59249c7ba5a5a5078dc1cffb03
313	1	43	\\x1540b20ec72263c70e483b1bd696749a01be1e1044c8a75d4f8e9eb779ba80d61fdb972b96cbb76d4546475057e5e55bb8a4ff810eb5b515286ee530b3b6d50f
314	1	300	\\xf130c0632068e713cd4e8f6975219db932fd3eb623fd42d9ea77bf2bc797273c1724d5f9ce0d4c8a9f071426157a7b49700bfc7682f924908a7bdbc093828302
315	1	15	\\xe102d7307e82873132e7b7409fe1661f56541545e30c75b6ed5c5b941763cc55258cc809d6cf70c032e024f0b8cb916e2c91db449ca72391c6f4beded4fd720b
316	1	315	\\x7892747084e0ba4c7f03955fd96253f3b959df9d82487e532799bb6ae9ab70abf4df9d6b92fbd3597ed2617d39d7fc93a6a46f705e52eecd9db6027b66d71002
317	1	361	\\xfb8b92675da3a089510cf9c6f91ecce89488895a8b1c79992701bd75253b2eb9deb9c1a6bd47026b9bbb3dea873a574e4ea16637bc2d89b8539481d14d400007
318	1	284	\\x5b97d7cb29882d45ceb558e58e52293b7c144bef3dfbb91b2f03fb38759427007817cfa1937b032991a0e996a03c3c1327c73af3d46f7855e956cd564947c000
319	1	334	\\x1ea0aeca5104676f67f9adfb9f6d8d4bd00739b203e53a359b3066e0658ea5a5fc3ffd88eb85d453d361def06d46a2ff32ce0531a9e54d723f2b70b7eed34906
320	1	111	\\xc9a1ded19a044ba7d4e81871182851e0d85d3368a92fc17b9a69c7aeed71f857891fae60af1e8118de42f6f19213b21588d2b97767899c0c11277dd8e1434907
321	1	190	\\xbcb1bca59b2a0b08ea1a055edd92c8da018265177b948ac54588c74687e0dd3012bc4422a2e93d971f556eadf35ab96a7b8e34324c5ee632504ba08542cffe04
322	1	134	\\x7708bdeb21a50ea0575939a416ff133546688fe89d8a029cfe433aed6b2a42270b84c38835a0d6cd6c4d8f60a3d7b20e5cc4effa41da5c66d70ab4325398f40a
323	1	205	\\x360494f7e68a5ca7ea2154c60babd060cbef3fa6c4abc38be3f5a7ade57a1f25d59397c10247f86fa18f68815869b5fa70ecfbb8e566f40c20667f63ad66d004
324	1	56	\\xf096a54b08bb26346916da0ecb14435eaf4bb5a12d16f5c447ea3e992027121c7f757534b1337b47c2c8792e3095c7b48eed8e85bb67d85c21c2ec0f44ccf50d
325	1	293	\\x232134951cad17b00d25f9efa2a4e5640957045acd771f61be66273809eeec158b94d98d58b5c8a3f3cf6f7f52ba412799546492ffe028fa607a2b764d6bf408
326	1	92	\\x1ea16d088ad9af569f92d07a31ae3fdd5e9b75adb5e9b20b1392a62448e2e790022487fce42bc30907bd39052e62600ad88c644c312ded4634298256a902c402
327	1	256	\\xba8721de27dd5c03ebca515c253d1bfb8ee8ce64120eb177573a21554edc049e3a424e0dea461eea490cf9c43d6944c366fee07afadf6a5f2e1d4310a5728909
328	1	344	\\xd36699c741f5e16fc6a984c620439aef4035cfc56cde86035706f5d6ccf476a4bbbf600401489b0d3e5fafd22788a28c084b8053f38c2cbc058bdfdeec4a2000
329	1	278	\\x8a97ec643369b04ce2005d150d80c6e23accb32dcc16541d6d9ea0f37aa1ce0a886bcab8f06762511acf4bd431f4c7967add39f2040df1c6e1a6d027d74f1201
330	1	197	\\x1d961d9dcbf36e58aa221238653b0d85b129969ace94b499649e5eac98ddbae512556bc748e79d117b80d54a680f59e82d9f881bb4c446073f39109e3c4fa709
331	1	110	\\xa6976c6fb642d5c713d2273dd2525ea6d961b4240680cb6ba3134c88e0efe139280f1cbcb32710597404818e625e7ddcccfa14e4e46a2738a0d80aeab4249905
332	1	378	\\xa82e218e280ff164a8d8d4479862b26071355f3f143078739012e0c0343b5fada15b7fa4863b34ee707dbc86628385b56ab355d6504f940392c1aedf53a3500a
333	1	176	\\x9f2b875f5ce224469898027bbb81374e26d4bbcf97be2f31b5e38d6c9621b8b2013aebd1c73b2e89b598dd107234949a80facc9466985e83fa3017298248240c
334	1	228	\\xf65ddb0a72a811af9ad65a578ca1c246ab1d54ca9c629be2f959d030fe98d1f05bdc10f57cea2e5accf2332517d92c04868a410d09e1692bb7463054b7670206
335	1	156	\\x46ebe3f6f81cc9062908f79137f5ecb87a1db1841434001c8a918b5d92e650dbeef051d50d54f3686232fe3a2838550b6194a8bd9b978d359b0af3107624bb09
336	1	415	\\x0e7642a5e46a20987e7a2d3efbd06cc1feeeb2857b687c62ad1ebe41543026a7bf9ecefa151a09205fc8fe5d41747e942685f4a7fba01743cb688ee4d2a2c405
337	1	209	\\xbb68e67b945b40d0fd9291f02c1da037a28213adb3605d7312498297e83cfdf4d30c04a4b14bb1be22ae346fd6f81bb802af8de8446741f1d5d4d950b0ce200e
338	1	330	\\xf3e815b24a8cfab1b5fc99dc78b5433ec885c559e372ac351042b3aacd10ec3f488c6940d60c5802848f5f2351b0b4273900277771a635a3f3ce8def5ea21302
339	1	135	\\x0112caade914192ace20492cdb2ea504c8dd619fcccc634d35500c49cd4cc4f76536b6c0ae0f8471a35fbaa5224a49a46abc6fde0ef13066d80a09239bde5b09
340	1	118	\\x7beb377580beb566e8aff2e3f8f8e9fe8bc835af38dd16006f92058167b14c22bd7deb975fa4f11354666d5f1c7b5c767ec3cf1cedd5aa382adabec528ce9600
341	1	200	\\xfef1f7792207f63231f50fbc581a3ed1251890bf258a55c19545ea178244b673c24bfbbe4a10418669666e3a603f4933ac6b9af2e2c97f667c309bf4377cf305
342	1	164	\\xb89e4f68b7ba5b7a7a804aa51d150ddd26d3931005784ee76985398234098effc7b5f6cb23d4cb4cdb041d6249df71fb5d0fe6a5e72478e4c469ca562fb99c08
343	1	37	\\xca5c7f929925dd366209ae6e477865fb7126139aea136249f77037a7c5f572e113d089c51e064f75c11801bf28222e09721d3af1e40223f0611331384577710e
344	1	239	\\x47ba8f3436dab7ca783ce7ae0eb1e689d79f354c9d7559c8d4ae090a191d122a7d48a48b0d0ddd037ca30ad8999174a4b15f47e81c0893c5d771ca743f068001
345	1	73	\\x39a333c2a6531e6def3c31b91c1cb239b29600112dbcf55b63de0a2454ed72f863659851e66bc0364de9bbb91f180257e808fc919a037967b8745767abdbf108
346	1	397	\\xfb7be821e6cd1f2e2bd417bf8a92210cd992693f1d5f277cd14990ec1793151f1659e6e831f7ff2c5bb2777e89e43cbaa70ba04a25958cd1021749bb11aed209
347	1	332	\\x728905652b8fb9ac378b0160c6947f5c7f95222e44fbea54188822af647057b31803162730a1ce43dc7301f24fdbbeaaf696250014bc5db414786326a7a8b90d
348	1	171	\\xffbc11677b942cfc32c2b77a516fed1c3b07c07eca2337eb866771bc97e48a9362c7855c551781896025d63fe9f92273f965fac088c75d8005c817ee0a70f505
349	1	368	\\x7df77588008310032c30cd70d19168c3d8e43c29c8ff8e4b822a3671fcf3e64693c58b7bda2c07a52dd3b40dd9641fb8503f77db8956a9b8187cf2313861b70e
350	1	86	\\x56fa8ce6b1665e96ffd006c00a38ced224bc4e3c4a892de179443122c0a11e63ae83103f03e1360d0b111300e0519db8b9d65c65c21d69c63925506d227e8e0b
351	1	131	\\x1bf63ae4bb27879270c29c20ef7c244b90099b65381746e8af5a5a6120e8499ca907b8d34264e1facd21279191a79d850b4f0305da101e1799c0a6919fdfe00a
352	1	248	\\x3a176599d2090451f648cb5fa6c9e4ebefe5b17dd83d1c5e81e42b48cd4a3a9a10929e8f16e98d5af792a4924fe9eea610595546f9457f960d89b30149797b01
353	1	289	\\xa8e29fe5e6f7861b54058a0d6f9bbc5c0bea940bff116cc810a6d5e52d36fcb4ff734427cd5991cba1e6c744b97706ffc5fa784d9ff8d80b5e69a1ad9335a50f
354	1	152	\\xaaf1f09baaf77a60cc2ebdd71fed2e01fd0570cc4238c547e5e21b4259a990190cafb6167db9eafba73981386d52058dccf5be8739d45f4b743618bd99252408
355	1	270	\\x07c92c3419451d78b70917258d6f531818bf25d7b7607a9a52d679668841491ac9f34e07a0099e6ebc81ead08ab3ea5f095e543528980353feb84da9f5b7c80a
356	1	230	\\x10d0e42945496efa046c0550439c30bb3a167bebf99d668f894723507305a0298f9ee1cc178ae861bab1ef9ce8b00e3674ce0dc622f4300c99902af14be8cd04
357	1	323	\\x3513e96c10246470ad07c82dde6eaf248c9e8cc231356e64a7d6468acb43cee2a78a365a423ef2a47e28632a18affc64dc9e867bb7ae0cfa8bff0ab0f6612c0a
358	1	353	\\x7a6b8d26fe5db8eec60a85ea95bef20664b50d9c611e2c127de5efbdb5c2a660b4c85957ec39d8d5866dc4bd03a5a75a53ae3b95fc7d14b32bc8a1c832bf610d
359	1	259	\\x4d96b848c643ea2f9700963c508e9c2f833ebab4ebc7e892b196c7a66f62d78cc2c9f398a94bdc1160732cb6f308bba6fdd113a494e229741de744d9dad7b902
360	1	376	\\x62f7a63b7403ae8624df118a12b479820a3e37d42fb58492612fbcedcdd3d9774065f7b64c5bccc3e7966a66b9c823031dee684cc66580249c4799a81fc81009
361	1	12	\\xa34c748ec775328ec9afc453239c332a894db03579ae859ee79360f22d4ca64c4e59ab5cf91e2a0c4ffe6add07b7fc5b9b13c01ffa8961c7f2d40ba15ddccb0d
362	1	61	\\xb6df2929408cac8b94fa3640c9c6c04ca5783a6857fd1e3fdefc5e81b13a519af36c3882c17e5b940b7572c027e9c84e52b0b1fdd9e7820a128781fa5a06980c
363	1	166	\\x598aa95488d4086983abc8d1346ca02eed4141ecf776d4886801946dc52fbe0659b949d769cdf2440c5b816cfbb1a8a4137181b4f1a0369541fa6c098985e402
364	1	178	\\x3622fb5cae5164e3414eb4d8ab1ac45af4fbde9e308502461249f5bc70e39c82e3e9d75e88bc14665d9d5146661bc565304d77dc4e29c01363194fb53684570b
365	1	216	\\xcddc0c4fa5b1de5199528a1d571b59f859e2eca9f60698b9739588cc8209cb889c447283370e42086b59886a19b70277b2ebe64ce5fc7e7e26a213b5c014380e
366	1	279	\\x393bebdcd4da286a8440230bc3470dd092dfcd76cfc8db11e57d01490b195f4994c23bbf6ee3b3c6ffe9f998ab7e5bd444a6a8bd28ab277d6dd7e18cc0b2f805
367	1	104	\\xbdfa015c15d79b4e62a5a97f849b0f11d1af889c3a088292006604f75d4462416327b0483da82dfe12a0a5e4b1eab266ce66de5fe39b53d18acaf8fb4209b40a
368	1	29	\\x48bf038f86b7566679728ed354b95876c98ba2f4d81c2f402c5b266b8c3ae765210965cf8f19c9fcf133b0117fc4dcde843dad3f7007ccc07b7ae2178d17f50b
369	1	121	\\x18af5d5c4c842e5f44e2e565859a37eabad26907a1591c661c79ed99242ce03821a3ca1208765a8593de4322d76d0314bc46c5e6188b1a234bb160e7e494c40f
370	1	125	\\xace10958855839ad78fede62365a05b113acde3f6df0964d8d922f828daf6eaf8ed083dd245776bb76617279d5b729486d88f9922e7d5debb486e50564af8700
371	1	91	\\xdeda2cfa58ba0f2cd0dbc5e8b9766f21771a90dc114a186d2ed7930743795018bf5795baf044cbbbf0e2f4b9a62f6cac352cce413df8924a59cb009d54669505
372	1	400	\\x43851d5cd70e0619c5ef03beb391dede0881f40652e5909d2ff0c0f8a2b6921bcc345d4416b20886af04f9c458116f2f86121568e684d8a0050df3dfbc310e01
373	1	319	\\x16a479a97daf9054b18487d85393d27dadd65720569fcfef46bff1cafed6b17e72f5c40f86dec70d1359f879200967c6a905ce192d3ad6d99c6739d6e2e08c0b
374	1	108	\\xa538b3266668ce0bdbd4b89b58ad20832643108aa6592ed8cdf89d5f03144a1faaf38b6380df3fa58cb019ddc2a6506ce12625fc1586baf717fc25e6958f9e06
375	1	297	\\x8cdfcd0884c12529a7933c695345cb165967837ef2c4d1dd4daaa6ccaabd80359e6a4f1337867861a4b94d91d7c5633f139b39844bbacff11d916d05273a420b
376	1	75	\\x92f8e075fde107c2282162663a5b00c294c27b257a3c81e7ed97fbb6f4878307fd4b3bd31a075950c152f2b978272a0f8a9bc8b6c5598568a5f626395edea407
377	1	65	\\x1d2697ab49606aeca77a9894dafb795ba1230bb18ba0622e780c527c39cba1cf4c5a8f4805b54119786265d81fd034c770c6a3c84aef171ac0ea7a5f5d96ac0c
378	1	308	\\xfd6d520a97c4d290e0d3c9151a02f9db00ad8794bcd797fee33c3fc0e42cef33da638d859021ab2566fb36f96785525da481d2145f5be3bd12551f64cf84c00d
379	1	193	\\x5ef26b63efcd8e0c2c61bb1d93f4b41a4bb6987ca99949ff01a338187ec6b1bbfbe51df3e2467b0b880dab3c3c6ffffe9db8d039803c8fd830824c7e78b7bc0a
380	1	387	\\xaf114b53f624e48f4023edd508b92e821439ffd3acad12facd8596ff4c3c66e6a686a1fefe9e9d413252ed85b0f71c0934ffa1b2aa4603c09b96a2eafb310307
381	1	258	\\x889cebaffa3720956108625aea168aa2cba0d3edb2ed54197be9113720e6bd14fcf1e5ef8e795fe19c8148106b138c4881e872a270c0f3e4e68845305e87000b
382	1	1	\\x164226ffb1e024d4e370fbb4976f3888b185c51429357acf4ebc900b23fddd30c83c8dd7163c8d4bd34952b38af18c73ce947dbd4b5e2726000707d0dd302c07
383	1	119	\\x2018384903891d831c01d60d3dbc948c26410d098d05b47aeac9e6a82c9f9e02b96895ca00b3ba18f1dd70261ea2d02a087d074896403f3235ebfb7742348f0e
384	1	396	\\xadfc7edbc1a5f573087747ee7b0ee96d8eea07b40dcf723b833ef9d693767c8565b0fd9aa7b00bc8f3668e27a8a52ec089792fa64d74af71eb01f10833bd4703
385	1	124	\\x4af64d758f03fea148f53ca4f1c924973672afd086dcfc909d4b65696d26c56999ce636ffdf8a9c181f61c00d44400d37eaf89efd5d7ebe0a5591a6132f9c001
386	1	123	\\xc81b8afeb646b2dbb6a69c94cc4cb04b70112aa83b6627fd8e47c6d73a797b55fa50c6ac21b079e79db7d51ab04f3e7b96137c13bc73115f6ccca5780b67ca0e
387	1	422	\\x6ec6322a665c4e1708b4555d7bbdcbf648f84db0947f25826788e6a368e1dd7bd6cf1cfdb67b94205fcd34b4a0d77ff5181037ce83ad2c65399e54850ff0f905
388	1	375	\\xa4a7c0cbf50bd05d19ba6a55651a872098f34d930c0775ff320c40a58df0dcd2efd6f0b1e02d63dbfce9aaaa30667e517319c93bf54668955036b9386144c405
389	1	399	\\xe1a3e540e53e23ed1d5e67d63133e55ac73fb89a2fca045493957dc46f41d7d5e57a586a13804cb2aa903d85396a657d2965443e82eb962d29c03ac86b7c940c
390	1	367	\\x4e0c1e663b235579fbf26dad727f4c41c72315f9273c504de75ef05ad31835abb7dcf55e38af18a9f83eeae78ab3b4b47a865cecbee9e4224e216da3e3cf460e
391	1	335	\\xa4dcebab92fcab804d764221aa4a6a2d348064e0f44e74183dbfe854140be3d067faf99d108580aa6ab527b41541745c156f12934931481017c2cf05a28e2700
392	1	32	\\x9523cb581e53c6070f6788fff47f74081d0d9026ac6ace661d5073bfe330f08a4edfe9f532bdf632a1140459a27d710dacc92f736a8368dd889186bd51a0bd0e
393	1	384	\\x417f887227b20f7041e51ad872634846a0602b62b9733cf989c37808ccfdd60d6c669663dfea358e4c1f8e2677fb5659bf3a23077ae69d6274ee81685a1f270f
394	1	161	\\x849d56f3bda9c249d1b930b7e7667106ee39b427c5c2176d615ce7a636f0464c0cce22c61c30c0005c0d05e738ad0e88dda261f7af9a8918d0ce415201b4ff03
395	1	23	\\x837f73574e77048af6bd9c0a9fa86c90d2d296c48677f90988cc2e052dc937a3dfcc9add0ea05bd21497b2cd0a14c683ac029f1c21db88fa2de4d379a0a9c001
396	1	25	\\x764ed28222046e4669abae0be06afdb8d05efad636a1c61939c162542e61c8bdbfa9d5d78bbceae190aacc4bc6ed357b7313c31a1144b9dd1cc2ec63398f6104
397	1	267	\\x1c289bf14f95af8f0fa3ccd443b3e0da6bb61a2c166f53978a33a7ca09c8cca8c663ccc47d2145fce1c022296e0cb8598a2cf678554c8ca95ca52f8c6222b40c
398	1	106	\\xc491db2bc4be5f148c51ed73453daf3c3749a81eca21531ce4e4b54f50bd2f48c048d152d0086644c183adc1707849bcec1ff70d3e1d0db385a44f911ba55307
399	1	219	\\x6205990059f40897c1b50915d0afb0e7e5d1cf0da29729afcabeb131c279ac7602f169ba8089a91625efe500b46e78bf4616612b607e5974cd34f4937034e20e
400	1	54	\\xeed6a5705d3f2419123b776a1e7997cf33e9c7816e362dd94784cf78c91830ba41276a80737818d70f73db26e22be741451d2ce1463e1bcb0d459389c51add0c
401	1	352	\\x2dc9ff99353c25bb5cf1c5348885e725db5e4b29ee1d1c2e4cf29ec905abb4ad542e8f840100fcb2dee5bb563824b9af050d34d8688b66d835cae1664d30c60c
402	1	366	\\xc5cc40ed133a1ddba0528b6636075b65972224e57c0f994a66624e7c7c610375ad58cd56b13bab3af9ee34dd87dd46991aa5d1177d7e228097dd4ad7f199cf0c
403	1	395	\\x504dac1034bbd8fcfda34fc8dac60c0f2ee6165d3e05a202afd53665fa0936bf61ed8332ffa80fa94149af6b22fdbcf5dee678abdb536136c606a5b458300d0b
404	1	389	\\x49d967935ebcd93aac553b238e69f5b41d829f1cc8cd9bf43793f3a4b48725c33ba5d80530a958fda1c38be33a6439b288fb16a108592dd35b94376b318ce901
405	1	240	\\xe2700c7b50eab1a6fd1619e10f8a1a8272a4ac81054a20abea4d46e1a072e75e0324d7772e661447052f2a87288092ef777d3dad35e9b0b377a2ae425fd0620d
406	1	100	\\xd3738356876bce4de5ddb997a2e8acef9df92c4ea8f89840471d4dcc4117e7d9b17df4463381c072e5f6472c1b03eec4136e02fd3ef2337ea57e6b47fd0d420a
407	1	288	\\x85334438b9bc27e43deeb3d29489623202aafb4a2bb866cb8c636f7f0d08a85454013565bcdec56767b9dd3d180ba42d6950c1cd79e21ae05c1a599dda026b0f
408	1	307	\\x65f9feffa82071d918a55fcd2780e0b7f7f966d2fa625a82ae5e1c4f662cad5e3e71dc1b473019bc45cbc6d2d2e220c1742019205ebeaf3f445948a090985f02
409	1	318	\\x205e4540c9b962d7fe1fbb1bc095d0f240b8f703f05767647b18933c1d8d0ed0925cc5dc9cf8c5fb71d30a8fe665296e41a0fcc96a8fc04742055c7b1b214005
410	1	356	\\x1371ee7254513a66d4628b42158d2bca82aa57d8ae54370348b72c8d85de80edf87aaa1ec15f6b02f4ca932c4ca0a903fe8ec738c0e491ec74ca1afa9f565f02
411	1	313	\\x079800cb06a6b6f87e6a7216936c9aa93458ef793bc460efe7b643115ac5cba9f2b52fcc5526f23b80b5758c8ba82f935393d17d546781483cab1f5d0894f600
412	1	311	\\x3422a6bf49c2ff91e4b3fdac62fd8ff19293144389307d8114401f30b43a70f05f42e606ed8e50c7c6408fc4a9a19e748d157a0e2fabc872f3c984f32732cf06
413	1	45	\\x5991aa43040f17a53d488304fcaa71be3a5ee052248d67c64976155dd0b0b7649c050086beeb1dc4b2e6d06f13fbb698a2fc5dd781008d7d1b459548143aa903
414	1	280	\\x954c02182e437dd085d1bd72ddcff2be0572197c3712f5681473d51ff4305133bc3990ce66d2a24fd983a0d6a870cdb185b2e3cabf10a364cbd777547910ba0f
415	1	215	\\xea468ee4d6f234a9fe2223444d033a38a4c4b276d6cefe1df3c27134864babcd0c629bf5ea92b82afec8f0d6d7abb38c1b81e79e74e226c59ed020d52a15c405
416	1	113	\\x758174755e8209cdde3078f2c2fe73d07a06e2c98c2fa9e242416906ae8e09a4cb3aebfd06a03ac57dfdbd3e0e126ef7a2ec60922a0554379bec6f6721117d0d
417	1	129	\\xe986fc2637532781b89c9cdac3d1fcc4a3f741872e481e1371b02b75684882855b79e1290f61fcb5b6a3596967fed3f710c4c2216ea35ab5c0009714517d400f
418	1	21	\\xe37141f33b5fdba79faacd47d4a21fa9f4996f06eb8696361386e32c1cd6088cba9764c6c593eb0d6f2bc88a0365dbc2122a1fe15ec5ccd50aea335213ce2600
419	1	145	\\x9a1141ab5e46fb67223f273183e7e2664b5fb52d4fb49829885c56b26c2a31814aab6dc5c97d6cff6fff99b7076b0f890c66c035b3f95dca96448c6acbeaca04
420	1	191	\\x1dc00e2f43f5509dc2b6c8f5f57d59e94c264eda8f6a0c946a9fefcf4cff989cdf8f69eaee0afd2dd3f3b5134e86240572326931a4b15912e7d71279ba88ca06
421	1	251	\\x9570ed86b985a9c3b123f6c898e255d6d622d550a18b780f55f2d5cdc27d178d27f44cc9e3a3cc5bdcc8468cce3008666385814b30bd4465ab9ee9fabe36250e
422	1	314	\\x3e836411fefe4ae1a1abc0d30ec5dff45ba76d46d7077bfcca6431701331129928e24379eb2a4a82b359a5e3027a1bc8e31859de87aa62e92c11d6a2fb14f700
423	1	272	\\x4a960822883cdd5b1f04384fd1a67caf7d5aa0225b2a2cd85434d70f795517380eea319025f5abc959d252f888ef64adc394165e0977d42b1aea18dadb6ec00f
424	1	232	\\x786b1fdae5547eff2ad779be0f71282ee6ebc326906401ae9e8486dba9307b5854908391fded8a681c40c230a2bb81d68b4f6cfee2df0891aecf53487c4b6305
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
\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	1647694588000000	1654952188000000	1657371388000000	\\x5a73f96d97cfe4b187e933f4447080de03bafa7ffb631c737f793707087b76ed	\\xb193a56946b9ddb5a9b80eb44d76f717860a67172d7a04e48deb5f8931e84042bd8d5041a1f108f4d0b4474126d07ad57c0416e837d46a34980217a6b5ffe201
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	http://localhost:8081/
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
1	\\x1c1e4288045904ac12dc7d94aba763b57c02a4fd3aa6c54d01a785a6e4d8bce3	TESTKUDOS Auditor	http://localhost:8083/	t	1647694595000000
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
1	pbkdf2_sha256$260000$I3LRzVVJWhIeRlTzLeLBun$sh1FK/ZjlgHfBES4gqHwim4qtiDvV50zK80+C+qdyro=	\N	f	Bank				f	t	2022-03-19 13:56:29.332692+01
3	pbkdf2_sha256$260000$JFWHnwWqyD5b2xFYr2ovIZ$E6VB8M0iGV/g94OUpLjgRS9LOCpSrN2ieOyVZ0xjnFw=	\N	f	blog				f	t	2022-03-19 13:56:29.583649+01
4	pbkdf2_sha256$260000$mDz4TlrNdyUwm57TClG7vC$GkOCwFlarAEP/eTwUOD59C3sJWiB4wdlUpWeBX3StYk=	\N	f	Tor				f	t	2022-03-19 13:56:29.704306+01
5	pbkdf2_sha256$260000$Zl50YQgjBkFiaCFhtZ5jYq$SSuYFQk+ptT8pMh6ALKiwYmkBmLcn4pdFCa97fLqajw=	\N	f	GNUnet				f	t	2022-03-19 13:56:29.823151+01
6	pbkdf2_sha256$260000$nRoIDH9zHqBodu6NgB7Td4$VHaSjYEf/RwMd4KFcvDbbmbNJH8+bWW61mDaXNEKyoM=	\N	f	Taler				f	t	2022-03-19 13:56:29.940208+01
7	pbkdf2_sha256$260000$fitoogDxPgQt3EzbbMp6y9$jua5eznJ4umtOzoZdyWvkbRGd/vz9Uy0svRw3VaYiaM=	\N	f	FSF				f	t	2022-03-19 13:56:30.057824+01
8	pbkdf2_sha256$260000$ldqb4NMO0E3eAtcVV9PoVS$FEA4N6uxylBoB9zocowERNs8GZtzfiW0N6enq1ym2wU=	\N	f	Tutorial				f	t	2022-03-19 13:56:30.177776+01
9	pbkdf2_sha256$260000$akcI6VYvbacf25DFyl7dyI$ffKxUqsmIpK0RF7ss1KcAnbLNfEmJFXyzk4OucPR/5Q=	\N	f	Survey				f	t	2022-03-19 13:56:30.295443+01
10	pbkdf2_sha256$260000$FIASlEJxNY4lxRjJSt1R3Y$NTCridhDQMKAiZB/GeFCo9JKJnl15nnRhgirVV6g0jQ=	\N	f	42				f	t	2022-03-19 13:56:30.693107+01
11	pbkdf2_sha256$260000$jar0krUPXLMjLyTeSIXIS4$dx5rqUt8e8ngwxyXzV6GUYD11lwhdffoMaD1o19YVcU=	\N	f	43				f	t	2022-03-19 13:56:31.136686+01
2	pbkdf2_sha256$260000$0c69wb7buuGczljDLu4zDL$dP2gPG7VMjq4QZLl/Ms1gwgb4tRoCOAsXoIdL+efYWI=	\N	f	Exchange				f	t	2022-03-19 13:56:29.459075+01
12	pbkdf2_sha256$260000$xUQWchZ8hH5D7HjOvY6H8e$+d3CsksS9HCG8Acwu1F1RpUNol9oyEXZEZP48FwLNlw=	\N	f	testuser-h8iduz4c				f	t	2022-03-19 13:56:37.792166+01
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
1	251	\\xe9ee8e086abfcaa41a8eb21309256c0419618b325255a0dba26a76a1b537e111ec435873fb42d7377cedbee1f8c062244b0c9da3fee5b652074de9730420da0e
2	113	\\x366ccce9385632c7a1bb47f74c97d305e7ed1f4753d6326dd4032ba543c2b46812d26b33f6a9f4c90cd8de803b3ef8a91db35a1d68f534f0b1d4263b4f75ab01
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x014cd38944e0d930ab1757bd2b3225f4afbc0cfc4ab8dbe24c2c9f99a3b0fa84cf6da29f04a2217e336a78c61c5bcf05ce721f4b0e0dcb9165a6724359fa4fc4	1	0	\\x000000010000000000800003c1ac97725aa2ebad18a44dc794892eb6b61e9776019b1c579ed0749a5184f4143d0c88e4458d7da88c99d17ca1c538903080dccac81db73ad506cb3c5433f1238e4a9a2e9606b2fab523721014fc5f175f761f93112eab5129e2e8412d822aee05b36f1bad34183bc5e02980242aafd93036c3860818e309d0543414fdb74e4d010001	\\x3f3365e27038b1d4b80a9c080e5d1fabc288067b22c393774844f6811a547d059b2f8eed69704ca0f62e62ec4c6230c5d5aef447e62aae76c3317a7225090903	1650717088000000	1651321888000000	1714393888000000	1809001888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
2	\\x043c9a416f83f9653fb169e6e92784b3f7ea56a60d8e76d26e3c65610e4ed35f8dd46778e143cc80406a3a2e9cad616559b3be946d085ec6230605962dcb5706	1	0	\\x000000010000000000800003da31bcfa77d52b9bd805a4b808e3758d8913beee31270ccff85e6a354d30785af3d8515e5922ffe4f368f34fc6f68394c5e3f23c3e1d991e6c4412e13e861afe0146a50f8ca2b4b90682c9e911e6dac04ed32296af1a1fbd92e5857cfdeae505196ccaea0dc694149d0c2cfb5dff34e13e700a07b714cc03db0c0a91f0c99073010001	\\x2a9474d2c73f19f448b83aba1289992c87eb059ed8f198ffe4910413ab9ad6f0637501337b053de5b6be5beeb6788a555e22e81bc71fe029e6a98ddb57bc430f	1659784588000000	1660389388000000	1723461388000000	1818069388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
3	\\x060cdab20ba1396b1feecb9a9bd316305397ae250a3321344157607c3c61e682c096beea79fcc349b4249f4f7714e68e33d063dc31242e34b79f4a7c73413261	1	0	\\x000000010000000000800003b72048f9d82f2d2119e46ca90588856abbf0c9e9c430b5cb6421d34444dae3c2a24203948a3a39bc1b5717c76c257be0b8f11e1c341a54e5f1efa438e14667791e3c246f2184d466e75b80d96cc49e79e471ae740254bd630f0a2b9eb1aafcfeb86de97ddbb132ce1830740053113eef463301c558488728d6a6d59b24c1b65f010001	\\x57342a75e0baea6b2233027a3812c37578e744f841ab8033ab740e3df19b72df72a73da1d0cddf4048e2bced8ff4b8fd43af00195d8cc0d255568474144bab0c	1665225088000000	1665829888000000	1728901888000000	1823509888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
4	\\x071c6a8209561aee64316293a19f5e89fe055bb83bb264f0c6ac46522a4398e35a2b49c80a65c137caa8227e6cdafe796f5a071444a581d017cff1706d419c4d	1	0	\\x000000010000000000800003e75a476fa7030eafd841b255b7ecd75afa6fc11bdaf2eeda6ad9f204e42b10b3e32a1207a29aadac11e6140b231af37b941c2935c1c99a463b6af6e98d45925a87cd54a80ce7bfc7cec209724fdef963a6ca61de1def14ad9e3513d741cb122441f44c955919d120bb20a6226e35c39749fa751743b6d01c8d0dfffe0763108b010001	\\x5cdb5341b9c4c80ae6cfa08bd2a0cbf397c3630b273b57c3b412d884f6099695b283c77fbe232e04f2981c1db1e8720a9b56a8af0ce145cb16a534f45a117d08	1678524088000000	1679128888000000	1742200888000000	1836808888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
5	\\x08f00d33197f871e2bc1634f74045eef337a884f4cb6cfac316b94907431c6dbb53b58494f53741651a3541df0d10a846652d7b223b67ae60045ca2c641853ce	1	0	\\x000000010000000000800003eff0db12e568b34867b2674e71a5a6c35f69e1fa3324b20df1737a0bc0962cc93783ddd0fabb32fbfb3917c43d50bacb26138b8d3882722a350e98d9b04766ce5c5d22a7968e1e3164145fa98b68b5de881281060c9d60f89ce97f83da709052e636c04eaa4830e9e28475e5bf423ce4795492f4e339ea42925ce4e0055f12a3010001	\\xaaa18e218bfc100f70c1246899f2c44ed1f028e1013957804f734449e087d968ca854c4609fecd3838e76a17b28ddcac3621f84a57430ce80716786b4cb5e607	1670061088000000	1670665888000000	1733737888000000	1828345888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x08b01bb9386614fdd873595333d0c6861967dfa22e00dce71e728163807de8c4c1e5850a69c14b2880aea0c3d5687d2839760d6592d36b463727186707a1ffda	1	0	\\x000000010000000000800003ccb557633ade203e579c61ab908c7a6abc514b32b17e5a4be3a3db28b51165e5ee35efe4b807fd9df6b471a7e59565dd13d5e0edbf2957e6d930e546ed71e7d6b77cf7f364e917f4dfcbbcc84683f318b0a1f9895d7d9d8136a41653d2475fcc4569d9cb5ba091999a86a942716c892c1980264ea5a3a9271b17046e36752619010001	\\x3ecc9d669a3887e87b4416e7bd3c8b2df1a032f616262882baf8b17e50563e8dd5d159b2fbc08c4e2edb2bd484757669871905f16a884bf7aa5b0cc41e76b509	1667038588000000	1667643388000000	1730715388000000	1825323388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x093cfca49ff7723025a445a3056026d33dacefe17796ee8e79a4ec3f8e2ca2d9a596eb1fb1d9023fc1f28220a12ad86df7116fcbf50422bb797432993b834efb	1	0	\\x00000001000000000080000396963ae57d973b7f8cd17962c5a020a636efe232bb7b8e927d613181444f52b263b8b889595b01d274faca6d445b2ae46f7c499d8164e61102d6a8211ceaf36ceb3e5829e0ed3b21373e5fa0ca3ccc2fcaeda464003815d15776254b9694902b498b8a907bf1a8c3fabbf0123f562f67ea2933758ffa82250e3df99ee54e2ded010001	\\xfade608ecf618d11ea85964023ff7899fd26d200a6627a69a108ca06ba70e9fb640f0bc47a3fab115a45c66b92ee6d40c2ac41d26dd084a228f35a594fe59003	1659784588000000	1660389388000000	1723461388000000	1818069388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
8	\\x09907c9509b0b9e51e1d88d7cf95bb47482733bbb34823e1d13a70c70c4040b778e4c05f90d3cb0142e65009624cbb86bdfb01245aaf06bbbaa90552c006cac5	1	0	\\x000000010000000000800003ca8588c7109c716f516eba41e38d042fce4dd9265dcd0b004a56871831b1ce4e164612cbfca3d8dd48591225d209fab848e449488735aee08d47ba19e969526f0e07ef6bbcabf8449d31c6323b4f34a5b387dc161b65968e595d62cd6ad0d666126bea2f26ac65b7976026ca72c957573d1d3c4e362e88a17d02416859d87b21010001	\\x5c101b69125140cb176d036c0a062c2f57c4959e7d3a52d571c4f9b0604fd4e43a504d6517df5397204da1c911df90902afa519091fb856dff796742ef0d160a	1675501588000000	1676106388000000	1739178388000000	1833786388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
9	\\x0a90dc23e516616c6011ca08fcddb3f88fb1538ed4516f78198335310ecf2d26159328727770cec122192f32ffb0ab9963b003c35a2c822c334096b72aaa70eb	1	0	\\x000000010000000000800003b75d874010fe1c8544ba6dba8bfc682dd8e27a4a8894e0985bdfe23b2b18d5c01a893110f0a9041b7ee26acd339f4ff7933ef4f099e57236f7b58c25446a65c618fca1fb6f0a8d06894ca3801373e5fa29cc7fb803a5ac9702c05f45f135d76234ac7507ffd3e95fe9e52080c3a6d3accedc32d8b87c19a27cb5d939a196c369010001	\\xa63269f224f960b3f13b084c0b892ceff864ce75dd741fbeb6db147be482816f8cdb7fb0f2f0fecbef8853ecc2dc2069e0d2677105a113879adf4238fa55560c	1661598088000000	1662202888000000	1725274888000000	1819882888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x0adc2b4ac000947984e5df9f369cea8105e5d833aa255206ecc81c99fada476fdb1f33139babf34395aad9566d471a70c6c62ae998cade41a877a93b7233a211	1	0	\\x000000010000000000800003cdcaa15b4f70f3c444274cbe13190668241ebba137221617ab6c2e44c6a5cfec3c87238344caefeb696683326778b2bb8c80e50766b394d21982a6b33885d08b289d8e600f507cd264bbcd9eb46b1b5ac6938e05bf105e9dc77e8b6ca4bba854d24e4f97c37b53aad5693e843a16ca0ba5ccadc163051eb4a154a1346806df29010001	\\x357b2441d3ea05375e775c3953b04c22d232a91503e2c7c17b81209d806a0d61096c48709f2e99746453ccab634c66def4a27a05e68684bc398c072816e64602	1677919588000000	1678524388000000	1741596388000000	1836204388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
11	\\x0bd819b600a3107226015723fb5b8f8a5b2ef2f0cbdf0a34dffd4bff51d6083d46d0b68b189a0fd58e21e51c4d6bbe05c198908e18c865f7b5ce6fedfc0b5002	1	0	\\x000000010000000000800003c27b6fc6a1953557e535dbbca0e0864a4006b0daa442f1b9c4be8ffee51d8da82a5784df6cae8d6eec6a9a377b72e34cc586915c59357e55a03c53cf7620321e91d0911f24c14f2eecb37db2d86c11c029b69fe4c5c4059679f66c24ea56605dfcb4ed5794309855a163fab9bd7b645089a5c805ca96454b4899c53bc903c769010001	\\x5fef435a08931f66f88a7c8edb179563f8762b125fdc08cf9399e1dfd932617a28d1f5078f06310fd1617d93909557255d63b0cae4e88acfd76b4a41f3f05109	1673083588000000	1673688388000000	1736760388000000	1831368388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
12	\\x0f4097292f4bbe8751bb058ffbb4079b73babf35eb3eb86d253328097839d93d35f51715d3841a9fb7067680c2f11ad6b25621050ab60c221015d9b236e8cb22	1	0	\\x000000010000000000800003c8c6369919d28ad513e09b39aca255632439bd2a072d8b353c2422b76e84b0a03827b229230b5918446dc75103fcba6c9b6fbed6b2101f80a5f734be05ceafaf885346ca000cb13af0717e4f02bda99e94549f6ed1452e71b2d374524dbcae1de65ca50c6e81205668276c6e1ab82ddf10e24f48ebff1b313b2068b7821e7abb010001	\\x986240b753ede1b3f42c9823bf9d2741c8090fba01c906214d5f84b80bb92c692b0d2c2457717de0a854d4400fa43beb07df66a71b776ed79e2ee7ab99eb4b00	1651926088000000	1652530888000000	1715602888000000	1810210888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x0fbcde014e323fcc1f8a1c7cd21831bd8c88eb3b6b1820a2ccfece26f58738f43c4cb646df57677d12119e981f4b0d446a5a23f144617442cab10ff47dbf7534	1	0	\\x000000010000000000800003ee4d43d588b306bad117651f265964595fde8308995c9dcead188922c5c4b0df9a0e5a396165e7746e978a502bd60531aca3df944a63b5539b5b67550e1b6416c6512cdb21a45af93ce992cae2bd44e2996b3c1544d49256f706922017bd1df35804d43e3d8df1a250d89086352d05041dce5ab63d329d64c6d49e5784707ceb010001	\\x0e1b5f8915ec6bfb2bd35e4f2d2ff7cde7805716852e210593e6753fac01461e94347ce42bb452eeacfed1c01b39fcaace08b8ec97af6727627817bdf25c6802	1665225088000000	1665829888000000	1728901888000000	1823509888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x1128b0dc9f69eedc5aa14edf336bef70c62bee4eebe95fea9dc010ff0a15ccea5d303a90159b3d2bbe5ee273cb924c7ec8e7bf8832495a84a559fc7ccbdd4031	1	0	\\x000000010000000000800003bff2354ce0fe82d66e35b7aebd2fd2f7d0f339af60cd782f52b24b56a0b4f897892347193cf1f1a505307155204dc64c31676f4b9b70c5d4e99f109cf2091a03effbfe4a4b3a8e4e867c790192f01472ead5d343cb94efd8130f2a081b27cd2ed68829cf63e868662e624ca006d33241a323016a4482f91dc2303a003388ed15010001	\\x29fb058daf44e52d76f1cc1a7f3e991637099604cf4fe153b3d8997493643de81cb0971b78f7bd8b284a9143d667dfa7526d6d3a8620be9947e3162800e1910e	1669456588000000	1670061388000000	1733133388000000	1827741388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x12f00f8c9a537295997df075167d78cdf83ba1d712bee0336cb212d98c6885838c88cb1a89c03d932b79f6d4f107dac535f34ccbbfeb89ac39ac66c6241ffca9	1	0	\\x000000010000000000800003c09f4c4faa90273ce5305b27d388d5eba5e9d9466647aac0533a564b20a5637a4535b9ae0e0de144911e975eb87ce783b34206ddd01ac43f3eeaa6f0d528b2d49561cf2e5a2f5aaf9addc88e7acd600bc63b3c6928227797091d95d890c79ea3236362a6f0d093ecae4194819e99baa6b036a6c64ba9ab0c3d3ec4be807b3d27010001	\\x1221f96e1f30d224b241745ab5680bb6c800f537b9f2678b7d5c98190bcaf829c9d3a5b2ec5619916d41c734c47e3300204e5ee6f4e25fec11da165cb68d2d08	1655553088000000	1656157888000000	1719229888000000	1813837888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
16	\\x16246c1288a8416eef68ccec3280b3620f17ba74d922877b9df6dbf4472c2478726d1f85ee7b54ca592a7db61f259bcbc47b7d920762f6d486fd276b0368db6f	1	0	\\x000000010000000000800003dc22d214a32deac9441c2a89a355cc4d7245ada94016b22998460bbaaee620ec6870266864604dbf177edb1b0df03ab38b2d187838a1404295a8d69806457a581ad90693757de27a4e10d57f537c2eb63d67a6b29025b09e970be94962279ac38f064c9d14a38516afad1e8c025e727997a972213271e4afb5d264c47f0c447b010001	\\x66edeba0b1d802bd6531e2af471f8f1d4f174d5e62cebee8d7e4674324b46a04f6679d0ca707985e1f32f1636a6d6ec5c13727854d9f477bb89186e00408a400	1659180088000000	1659784888000000	1722856888000000	1817464888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
17	\\x1900dda121ac76822cb2702738a12ba6998c75fab7201b255c6e4ea3796f4bb2305e95aaf9a4f3dc9f06bbe2817fd657459186d7f479696b59a28de06d80016e	1	0	\\x000000010000000000800003cc47b11bdc571ce6be934b3a02a8bc75719db71462dd126a678ceeec2ca3cd7ac546a16e6f9aa4c79ea0674e6c0a7638c4a2ff86ea6792fe28616d8781745a8cfc055ca2c5f8b2e65e02dc7f31e3bd187b3252d87d9fea42dae5ae93256808d9afd08e0e6dd71cda36f9590d76e089b7e8b17651b1a7f952af14222f7e678b15010001	\\x24541f384261c6d6e95fecad7e8d4a53f64429e818508c0ce9406f8bc6d82ff80b72d203846c34a0aff66d8ef2b98567efe4e31e765ff3ccfd71766697668800	1677315088000000	1677919888000000	1740991888000000	1835599888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x1a58328756fb59ef74212880a3a213744b8bbd4b36cd950cc954141a30aec677424e0ae9bd67760c3a7e9700797e0271a035c8999fae49996d1d3721a54751b4	1	0	\\x000000010000000000800003cbb81be924d15a8daddd080551bbb45af1f3afc2485eb7fe60731b959106fbff88d53326a23da5f9da5f4ef1a558d5577d345afd43a6a80b0135f6fe68bfdebc60463e82be77e3c08bda4e8f981378d6018eb8267ffcb83479fda2ca099d5a9c19411b8daf1aad99905ad99e6293a3e90afc69544fd6fe2647395a370115ccc7010001	\\x1b7824e506541e84ba699f9b64bf4cd073d5462dc03a41c0da9bccc9faee9e8d891fa094d48b76e7ed01652cd59758a2bb2e834c0292d6be38501cecd9304a07	1659180088000000	1659784888000000	1722856888000000	1817464888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
19	\\x1b709bc4ae7ad8deaa6723aaf96160a2a148a2bfdc0b2ca28dc59b36afc6f4877ace0b8d7c78f321a12fc2abbba6bd16205a71c278b4e1c0b2d02142c2992eff	1	0	\\x000000010000000000800003db23f5219b83ab778f0d7090605f2e8b5072032528b1d82a58621dd17282836704f70fb9d90459ad566f01b1a8b27b502d9cd3e00187ed176c3a03eaef0c842289b6f2d05b73548bbd1ae5739425f33bcb5cc72335df35059e654ffbd33c2cc346ee200b329d8ecdeace4f185c073a6a05f286133de6fea089837476ce3cf6a9010001	\\x52870a2d9cb6f71a2038122d923078f620aa595fabbf4aae15015161417057723eac263a8404b0371049294b59085d2f58e8e113d3278418abb8ef4dfbcb5901	1660993588000000	1661598388000000	1724670388000000	1819278388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
20	\\x1cdce0ca4670949f52c9f941041ea5b84676bd466afd9665b25365329ffc06b33c14f9d25f87cd9af98b7f2bd31f4da8c23df68469800ae5a4489eb6af451dd8	1	0	\\x000000010000000000800003addcc82a6b6e1a63a3b435d1efcb6f8225d56b9b9373b7349b6003c87f72dba5c4e7339b5d43db3dd8643a2cc3b6284f8d9c4ff12f26befbfd0e472675cb729beca9df8f143d73b5e90cf122fa3581e64e6df682dbe0f97fd2f7e73aa5ff58fb67dd27e0f97ecb6e4b40d22407c3a4d96506b5a87250e3cbf912d05764068ba1010001	\\xae760995b46047c2423c875d708acdd36c3ea373ab3152e22c08163cc7a2d26b7342c44aad65635b227cbc7943100da19917fe0a47e3ce29c1121d4244d24406	1678524088000000	1679128888000000	1742200888000000	1836808888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x22cccced94cf44614db7933d5acac829f1aaa23366f2be40d682117b3fb75011820440c1e1cd4b0ccef73d3eb3c5ae7eed2e35b1a28aa2ea1545340997f98746	1	0	\\x000000010000000000800003a686192fac4bf31d7851cd90bbe15700c826bcdc4dba88505ecf5d9cf315879696d3f63b576f248ac8bc15d0a4039d9de11ba431f3317980b0ae4a181d89e6e6d5381aacc01f6713fff383dd105ba0c5ec9b7173a266808ab068745ee7a5a2a45324169648e065b6a4ba3f63818d296cd026f1ebefefdf151baf25d3c4d7f8e7010001	\\xdab333847ff6f33b0c9befc366f05559e2a7aa7d8b53f37f04c7869629eb22b45f1bb40b34e31accb28589908f471d42d532a76bcfb4b873039eef9598062806	1647694588000000	1648299388000000	1711371388000000	1805979388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x23e08733290efd2fcd30672b3854566e83350c05b6b90fb3fa8a490e9f66f7d361f46fc314bd2a49bcf122ea288a6622d7d63a22e001845fbe752ddda1a32de1	1	0	\\x000000010000000000800003ea8367434e30dff58073321db2f63465c92e31c94235c66c7f5518762e5080399b01fdb16f86fd3e082f60e194e1f5682be3e40e9c9f28406ee133b890869d38d2b0e62e2563396e67054a93f768227100efd558bce40cce0c9e39039a155f1785131efd1636f9bb63342451621312f7b385477dad978655208c26e5b4e4972d010001	\\x7dc3a7c6623d812822c197dff250b282e8dcf8637abb615a99a3ce9886f2847b5e8cef0c2dda9045777422109cb323119499e98540147d36d385c011c1352d03	1676106088000000	1676710888000000	1739782888000000	1834390888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x29c43c73ed3fa227c77c5f56d139780d1088182dddc7d8ebb92a33933af1d9924f1fd0ff68622775fe1a09303af3fd78df18dfdb83d408c2c105e80c142de930	1	0	\\x000000010000000000800003c057db3673738609f869cd42368f08500026f0a4242a1df23215ff456b954eb5c912df0c7aee55b6c2f90230be9b5d20d825a80b78428c8592e54abe252c421b4355cb5aa4f49a3a034b3514a27eb2f5ab08ea8f5a231c341b0ca3cb8529d3bfc879efcc98baca8d610e939324e8c1c43cbfafb9d6cb22f3f8ac9135bdc4b1d1010001	\\x40a77e955f3609f1a00bfbeda5d1946d40af17c9ea993ed08b1319af5fe1366f7131f727f3349d157b93ac63a706950c39b04b6b808c88977509ff8c24202e08	1649508088000000	1650112888000000	1713184888000000	1807792888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x2b14e1e9df6456eec152f0c2c9c3158b44a22c6b6ec147350c1e05ed2aa6d33138abd531462260fb8c05661a556044aff83e4beb03d97a20792b3ca5ec79290e	1	0	\\x000000010000000000800003b115531d4f7bbb6e6cca663c8a574dc41c2d7c7f42dccd40849bf50dd8c3711ad7ced29c254ad137535c042dd32f6215ac643180f2fc7f03ae6ae5724c753ce47c1c719eb5cc58c5004730f01bb796eb2264c857ec2a252211ea72db1617c0dbef1f82534af709d2d8577269f1876b734989889f5816f8e605bb0a665157ca85010001	\\x9ec7c778bf3649998160a8f1b48c1282d985d2b43c292db39c242c99b0275826973b1fa5b19f94976368e964dec88614d1fbfb3b746a2afececc9b58b7450203	1670061088000000	1670665888000000	1733737888000000	1828345888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x2b0094e8b65222c2f15acdc1cf0ad901da51b09356771704a3a057f79eae7b1478f79ccdd6f80d668c03c711fa654e96e77b51c22065ef9f8516125483f5d984	1	0	\\x000000010000000000800003bb4cdbe6d1efb971d832638c0b804051ed6b873790946576099d7c3f6c6ffedbbccc76bed4164ca93ac1321c1efbe779753f97ab82ef24c4ac894d419bdd3572ad4bc4544163eb57585303ceebc53221b4133ced50a3c03056557308ba606932a4d2d2e3b355e64adb47274c675553dccbfdeeaabc770d3626dde619b3e0edc9010001	\\x9b944d6fb980b6669b1ad42cdf564b453d09ba01699012f0f13584b39003a639dd4a0a1d18b95022ee6d143e32f9c443a17ccac5d1ba76b47c625c06725a6c05	1649508088000000	1650112888000000	1713184888000000	1807792888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x2d6c4fd6bf55ba9baaab8f5ea7ffd71c73b88d348c77758af333be536514ef63daeb0f3a6373654b756c5b4b7e513bec5c01a66daf9664ed49df8b105e929aee	1	0	\\x0000000100000000008000039afa942f1f12fe0dc49673a61e30dc25ad57649a7547a74e3ab33777ed06bbeb1ed8ef863d768094ec6d7c242c3e75e47446043e8f70a3c8cd7c4d69d71b99ecd67c0b1b91b9d27bc00405760cfddc5543a2195012cf1005bdb47a43ff18ac8703010076d1944073fc8436682742763a5041fe8fa8d2291f48de978ee1020187010001	\\x840e2b8bf71be56b78167cd543626fea22f0fb1c1e07e751f80045cb789d864ba598bff9556702f6556fa9dba5c9ea880c6cea5cfa9e27d25df7a75d25e94f05	1676710588000000	1677315388000000	1740387388000000	1834995388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x2d9ca223c215d23754642805b5c57e3a6087ee2016e62bfa842a4e28357e5b484e0272d3474707fb93c9e3bdea037a7503150afa511aac64ff1b8cdda33581da	1	0	\\x000000010000000000800003cb67b15bf53506bbcbd1191c2e76d44062428d382ea19468c1a965157f9b9c722bcd15a1b386a142b260f2bdd0e50e17e224fadb3c6021d2796bd58984bd46d334155cadf0801e00067fb5405168fd35da93256790df0b519ae0ffa16494622162e9266ecce80a4bf751cd2112552609b1f18ed44c65c2d4f0995f87928f98e7010001	\\x333a3ae6b3ce8d049c3b210f516412eaa7a3722e148ba9479fd8949ffe448a65725da4174d61e15215ebcf3292662a1b52914493fca7a08f441d4bf1bc51c401	1671874588000000	1672479388000000	1735551388000000	1830159388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x2fd49b2a402ba5e0478454ce325c02cce572f184acc9ec2e1bf1056746740f87d9c1110beccf7827c8c3c02cbb376a90c213c8fb930691b63990b0d7eb7e315a	1	0	\\x000000010000000000800003e6d9ea876236c233f83f1883c22f21ba4d0e4b21d3c6e5ebe6d05c0b8a5c403b0ed0d2f3d64a19770ecb1c07488ee65987abb710d8a3b68f624717cd7ec9691dcc3d8810b87a5da911ba242c0ab8deb7e58fd772c795a74f3e1a2ae0cfff498c92ca03374d1d78aacf7c18841d7c7e859e0ccee83d8ff37372cde2526dcd743f010001	\\x98eb2d80dff9ac76bde560bda1a42eb051ec1126dd483aca15e6b751ddb0850d8f7461eef9db1fac228f586c3bf8a070b9030c0002b549d701d41f4a0852610b	1673083588000000	1673688388000000	1736760388000000	1831368388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x31689b836bc4f14c5fd92b57c4a2ed48151d535f4dcbaa37bb6918f4ba9ebec9c665b13abe5cf1838d9904908c50060b891503cae02d5c5723f44c1cd787355b	1	0	\\x000000010000000000800003b3012d1658b90848c7e933cb928f6f5022a57d76f2590c8af423f976588925d7f085b4d03f95972818a43f0932a6077cdce82aa7646288ade4c068b6de4d4a3934031a4573958776c48b6ae774c3b798775ae7e5b7a50589994a2a9def752d60c5b56f77b6d8688a34766948294276da35869b5d8aa99a952388ab1b1d16fff7010001	\\x9578b8ada30bcaf0d8eb1807e42f963720911996589bbaea0d53e10a26e8336728e84662be3b5e82e317c0b2fd406ad6a2e9cd2f8bcae6b2188c1e63e01b900b	1651926088000000	1652530888000000	1715602888000000	1810210888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
30	\\x340814486529119aa0c38d1bb01c6915b4a25d1730250db21bfe044aeb83d491eb25f791f9db6bd9de78ca20cc3118e26e21f236be30506b2d9fea80a1192bbf	1	0	\\x000000010000000000800003bd17a6d5c3d8b0d065f0753a18bc6330b891f46c431f4a8d01e6abdb73ea9cab2e99e87ec1b3384c7888ad83d5bd123ec55bba321ade3fd89878976dd8eb20eb017bdff43b70e7aa4a6bfc7b2d75a8e4dd34e9afd027d3d202226e0862e69601747f32fb3420d265be830fb07455ac25d665ab5f1c315852546d33d4ebbf6fe5010001	\\x95ec195b0eca88a8288552839f76fadcfe662d9ba5e9c09519b806ab691f79b8c8f83d5c60cb83b4050ac05d8b5819e63e9206b71bd524ea7f11a9a05f9f1200	1668247588000000	1668852388000000	1731924388000000	1826532388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x39980a37515af051386227a824f342524d3fc13c8d9e29e713ac8dcfc0e6df233330e56ab20f6a52e9e9101fa301a1955ede75972a7e96cc9f303b358aefc2e1	1	0	\\x000000010000000000800003e26bcae4cdd89e13e58d1e6980bf408b66e6f33bc2d8d2eaf19fa9679349ae002481e0b4e35e4ffa9787f2065b6891f7ea43ce0618ad90fb37f9b50378423e70d8d658e9f6ec035d85e968f54be97640fbe70d828e80ab16d8a2899d1a0511cfb796dccd16e06d6e00e63fb29b0e9abaf814b7b61e5c93cc1567ab9bbdfdd81f010001	\\x0307e8e00251f20de8d86257a5334da8353f0b8be84d398b2c5bebe4d19695beb85dbc6fca0b6a32b44a2783c6781628dd0b075f9d8c36845d9c6ea27f936a02	1672479088000000	1673083888000000	1736155888000000	1830763888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
32	\\x398c7060ae0a761a7d2ad5ec3aebb47668052d0cb0bbb52d31c6b5e9baca8bf743a0ac9b4abb82f6a88bdbaf22a224feb2e72e0975e183b721b6e8cfa1a79d3f	1	0	\\x000000010000000000800003b349154ed3b81276dbbf4f187e2522ecd7224b55cd7166b5e9e9a5ff47cfda8a6a8e327c498555ea071e2ae29b4af59789e9af41c7f8390ca78b5243c25d891d32047e3ba9238eb343cc4e8b0b8602c086d67b0717cb5bce0d5a397471e3b9936f58fe31e720cd5e19b61c9ecf7442083945ccf5349e2a4b000e3566dd098ced010001	\\xf8b1469663ea240eba8c9bdbcb42aba0ab0285414f9007543735a38c5b1b38f110a45959350d50373b63a8eec5a3193845129c62dc10959b905b0320164b240f	1650112588000000	1650717388000000	1713789388000000	1808397388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
33	\\x3bd49265f8f7d09630cb1071deb67069bfc8d35624e68a7562dcd9b543c8e40e450486ceddefaa928bc1c91da460f2ebc1d7ced4d3064215bfeb94e27a3e3b73	1	0	\\x000000010000000000800003a4e5dadccb46bb0f79e1fdaa9c835af607f9e90fae7d38b6183485d9850620dbbe6f8198f89f77693697e19b76ab29377ae012933f5ea8da78b343b821ea5d9a2a3ab013df5fc647d8c64957bb7b75509ba533a1c0fd385ce0af5f950ad3af79fe430cb895fe39e90a9f50c1ab19c8f2f54087fd4a28db93f614240cf1fa6719010001	\\x2ba32671264bdbd9006428d3476a28407f6d46a1f2505c2c0fda7fda6385d4518fcbf2e985d061ba58c4088b8948e243e602be8f877ba4a18cdd8cd86fce7e0d	1672479088000000	1673083888000000	1736155888000000	1830763888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
34	\\x3d64392bb579b7f4e98c9801e853faf11587c0228c5b6de716acb37f82b98787b13d038329f1ba60235ec76ed133e28cc63635806bd5ac95ec23626aed4bcda3	1	0	\\x000000010000000000800003cbd113d64c4a6631681610b6072168c5b4feeeb30ef7cbf2ef1b07477a02e67804501ae1a59b61556887e001afca9fb97533a14e60f237173f706943e4262b2d7a263f7784a0e2e1590bc922371366666305311d798249c061bbc4c09ae6294440e8199f757f3cd49fa9c5355a348b9345fcfa2a1120b897f0c1c9e61383ad55010001	\\x138361b61b0c96d335ddd9f01c5e6997e97a82efff6af236337c5293088d79503055bfa4f7ef591e75c1be00948a20118640a5351960687862a8e4b3caee7104	1670061088000000	1670665888000000	1733737888000000	1828345888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
35	\\x406030a278ad2847dee38110ef1f2f68384228387caa69bff25714c99bce8235c4a3659c72aad5455598944fc0a84a79a5ffbd587520c16634368382b023baac	1	0	\\x000000010000000000800003d4903b3e13ed27deef0ac07ad89267d02097cc18c8ced0acb0083bde930275a784ba5c67192cc114eea59fb98958db479dbb78f11763c00e5fede5c0530fb15f8a8e07664929c3c7c1e37a5451947e7337fa71b6a65a29610234766fcb2ed5af3ad40471c5ab4f10dd95ecd7704065eb96ea5fbbc9b933e7797a1ae10b4050cb010001	\\x45fe7e8c876f11e1db552baaaf2d17e96ca073a7564d0eb33d1b65ba7c9b40bb54f6d67ad1f6a7c181211e0738bf5f24eeae3926cb55a6dc875db3a4f3d8c70e	1664016088000000	1664620888000000	1727692888000000	1822300888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x4190f70822fa82b5233a6cc0baf41cdb7d9418a74e4bf1716a9a5979518b29ea5da712608f2a4c14300c5602832c6ef99067c131de161528461b8227359dbb11	1	0	\\x000000010000000000800003ae26e62766566d7dfdbe54c02607e01d641e8d844b87a2f8b4b7deea0c4972094aa26c40cbce9b272bf12ddd438b7763fb3dc92907f80dbccab9a33506299f9359fcec4ed50c9e371ee3bfb136bd3e00b034203d776f4920cc6dc9a3c2abfa1c7e94293265a8dcbc6981643cc583194de84a0387a11f0ac723e142628b858167010001	\\x1772a94cb40a2c61f18c086bc8ec5cca725658d94879d5683647f70178c50cc278cf52afd673804678db8430d85a4066673c79f4abcbd43d9e8b020fd11af606	1656762088000000	1657366888000000	1720438888000000	1815046888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x45e861e03a1bbf805d5e79c3aeda635a154eeb55c55e33fa33a28e7260d51622b21a53211c6d8419317c1efa3ef75c5307c0f76396a508a7ac49acd2e4280fe4	1	0	\\x000000010000000000800003cde1118af34644ecc8a8634bbf4bab8665936cb6352227183b5b6eb3e2b413253d72f9bf203e074d8284ccd315a99f86a9e3bcd049c28d1d75216bf6412b57878785373611d1674777648a9357d9d3e7d388a280fe9dbe5b5bc43ecc282f0c8aa88eac4c6372e0e478cfc485ef1b38dea26dc66b6905c92339ee5d98ba332d87010001	\\x2b76b9666dc33b6b92cf670631671e82e441f917b5194454d9ca27980af58ef82090273af8305e3af498d1abe58e286191d01580461f581c48890ab280066e0a	1653739588000000	1654344388000000	1717416388000000	1812024388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x45b4e9ff79aedab8ecb471a4a8005a2e8948b2e22269734956447bd0fa5094e3733c0d0e1cfceeff909a550c6968afd96e9dbcdf49f1a6642f18aba41d7c7bc8	1	0	\\x000000010000000000800003aa77adb436fbebd62ae5d15aa17730ee7467ba46a16bd549cb80554404834c90f2110914fe523f6049787cbf5a5486859ddc1f6937aa4d1008cc355c9c655ec44721c05e26c5dd41b252db3e594ac02d5654fe826aff04140148b0e69c99ce7cea4781c181eed53ddf638090952f7aa67d996b9a110e48d4111cc8777b24409b010001	\\xbb9d77c80849f5bab2305f957d5b22bac6bb3350518fdf99aeda6dd86b1634c69217133f9beadbaf9bfba98847acee5dada42535bc5528a9928ab0d0ef40b90c	1674897088000000	1675501888000000	1738573888000000	1833181888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
39	\\x478c08cbe25878b69c4c1a68a0e6c60376009ec1c2d438be445cb7b65a8b1d0976a9e4ff45857ee42a7d9a5eb4042bf00b03e2c0cde4f34a235d8cb83ba92f7f	1	0	\\x000000010000000000800003e021d8e7e0c9b417ff6066730cd6b051d59acaf5572261202d96785876cd74eada5e041dfc2b3ccd2bc985863dd726c3921b1e2f9670f259cbafda33fe8fa4962d5528f2b25f436d6d309602da77765eb612eb8ba7e380286e93b01d9d796c0e567a9cb50bee0f7cdf97f5e2641139c0ec46a808eb3e7f9b525382e92f98ca13010001	\\x14bc4d482e3d94069758b8c5f098ad486a48830b97dd3bfe6bded558f4f3a572a37f4e1a0041120a2179189c6c61f470a1e8169667ec1b6a59c9c11717f3710b	1674897088000000	1675501888000000	1738573888000000	1833181888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x4b449491caf332368bf3ebe2e9f903f537141afdd7914a5cc61fde81c91848a8dbfe55e2a33db89b6246d3e9c6d2155aa1b10a6d4cb4bb75727f5f85a09475e7	1	0	\\x000000010000000000800003cda913196b7998845c0254f38f8f54f92468ea304ae63bb4fcaeddae044f1f685f314de47c612a291540df52fbc956bad8b86bbe1784c1e8b6d3d39907bba5c89a18fe0ab8135ea2546b148e1c4b947d51098c48309ec5567a5e0bad0eefc32fe1199baf1971226feb3059eb868dd046f9f86dbef0c53cba758e5aedd4913259010001	\\xfe460807bded6fafe74069ed7b0d71c8ba38f05738fade1b16fa0fae8e12cb0de3b21bb34604bb317059bc1a1b0ec1dafabda9a15e48d22030581209b112ed0d	1660993588000000	1661598388000000	1724670388000000	1819278388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
41	\\x50146a4bf59b7dc268665377e0a5a38cde7256eb4c0f1c5945c15bd90e759e6328b7d1a9466884069a0b2e53d58046f23451b40ec3fc7e2be96a0f7cb3f922c5	1	0	\\x000000010000000000800003c3ac95178b7ed3555bf00b576a02b3b5def03e3cc5260bbc5e6d80edf25ad41b327bc95a967a4ddbb5d0dabe5fbd7cb8b684658f9d08d01c63a7c80f7058b2c37a28e2699c87b27e68134b4cb42bdaa65e323f9983d6d26cbce6aebf49981892ed664f1a755e8a3a9533143073dccffb04e1174f44de8457eb238ae0bddf77db010001	\\x0b2592bb7f2c742dcce2f37aeee4c275de6e2e5fba64a6fcf8f9249b9aebc0e0875f9b787e8733a9657f7debfbfa96bfe7c6c923e5691957403bf09c23d97c0c	1676710588000000	1677315388000000	1740387388000000	1834995388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x52e45b98e566a523bbef44f877dc4c184a20c3b657a45ff747a43dad320f16d5ed3ce187dced79b84a971ef9677f4849275e9409b1fa77a32ebb43bec1943376	1	0	\\x000000010000000000800003a90f5bc7438088d729e2d693017300e9c76df20345deb15bb181e3a97c343b5ecfc6317542d10b2c3b850df079296958500e77c4772ad22670bdb08ed291d4a8d6daaf45b8eeb4873c03f696b59c54088179606e4708ebdd73c3e0614207a23e8002c4ca2ecfad446354377c7c6f5368615c2afddb0ff8491d9168cc84ca7bd1010001	\\x87d6911cd1fc18a73c8f97330cdba5e55dd5b1d9c40da5abdb8f6e1119528053ce8ceb05220322eb4b025891ecf97be00522a98c086e58fdacf597b399600d01	1660389088000000	1660993888000000	1724065888000000	1818673888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x53fcf0ef70606900060fd0c98d15618dbad4d294d064099c84765d6d41df321168449491058713e7d2b96176a47478edaaa4492e445792130cedc7598d6cc12c	1	0	\\x000000010000000000800003b6ba90315741a3cd90234909646f036e503d7dfcaf200d92cc6d5e59870f0310bc4c3532dc3a768e723e11efeac0327422ff0a051e325f8fa576fd89c5c00fadbad1f98f9f724276662d960332319a74b0aa6b3885e5145d5ffca890c783c262a819629db0aa4de3c4099b5066143ab8861db34e9c91091bc510ef2194ca712f010001	\\x0c0eef51119d9914de2669c6d08fb9aad90002d0230b0aee99d22566725630d363ba6e542e949311a6706fc6d566f8ea8cb6875ecb6eaa57662708ea9d71ea08	1655553088000000	1656157888000000	1719229888000000	1813837888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
44	\\x558c33e4140f5ad76e13f09b1ba6e3514177ca3c321ebd1d85025cfa78880127c6d55a11af604ce052d8272dd895e07d82581b7b2ed2fc6eacd2d1aaf6d819fe	1	0	\\x000000010000000000800003fe3bb12d797f31fe5fd1a2cf5222ebab1ca73cfea157c4b75630ecd1f5d6d2727811d5ce0c9ef7a5ec677b052d0a96a87ef6d7b90a76dea8d69bebe6aa1511d788a05aa6a3402386c8eef5fd205d72d7f3f166e229bda26465392f99471edf08fa715a132f8cd4f5f37bf64c9232c8e377914dde4432251e3456bb133c75a3b7010001	\\x4096cf7955b6c9f114592b3ab757e4d33faa4d5cd9e53b36d9e26524de37a9dc07dcb4e7e1b26075566d24910c5da9b2c1812897f5a7624b2d61652fd1faab0b	1674897088000000	1675501888000000	1738573888000000	1833181888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
45	\\x572c44906c75a98f776564878e735da28381a6b636ae999e07deee97a62416a699d2372c12ee922e035831b10dfe3d70bfabe21b072704807263360f4c55116a	1	0	\\x000000010000000000800003b7978f97678a39d3f651a0b3d124c923168d50c969be944018ff06b294ad94adb47a00f777fd1cfb864b4565dcfc112e89b12e16a5912c6cbd06f29f9383e8e713fc74919df8ac28aff53778202fbc05542d7f7fa262ca27b46a2f046c9cc87b521310e5900b3e9610dd61b63758fbe961bcd03472f9f5a058f812fc37d2a671010001	\\x8ba32dd6c61732e187802c2af7474b9ec865a8a0c4dcf34dd3f89d06e7010b41606f5613e618287b110b6a1254542418f656f77e0112a478b4d05c94851a5f0e	1648299088000000	1648903888000000	1711975888000000	1806583888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
46	\\x59048db3aa95292ff6cc82a6ce7ad7e1a0e450dbc4ab2571a0a42caa1e7793d9436a0cb213714a156b2d8086628f76cefc3d43a88381f2e247849f1f8b1dd2e2	1	0	\\x000000010000000000800003befbda6ed8ffc633464dd9cf5089ae861c0b1530995e0b34e6a35593de80c45805fe9737f81c5ee7dd334626d62a471759a97a4c324bcea46d6b618a34853e06fe6929d2f5b675f955c900c0861ff331b075e886171ccbe7effc1caa0d7e0e6b78e99b4094e50b76bd59f2dce19da43e2ee0cc17200842dbcd59f08514a1623b010001	\\x2b1d439028183360e1424a6b45c14d78a34dd298092bb0654a701a5a3f0dcce4c8ab88256793bf926a4995b414217d7dc5610e27c39ee9207e69b0c45bca6e07	1662807088000000	1663411888000000	1726483888000000	1821091888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x5a98778565e66af099996fb2751f49ad840d974dccec152ae6854a163788ac67fd37e62fb8bde20241839e77982bf8db1af8bceb00574d54cd9fe1a877403bb6	1	0	\\x000000010000000000800003a2689fbe6946bd75d41cbf83b9d25c8c2911308776de67ee7b1d4f29de7de5c1b8fc9238f83dc3977166c14050034556d98a7e6311759952d38e8f60337c7c6784846dcd1087e974fda0f0b5fc95ec031ca7ae6a0debd3356fb643095c2ecd51765696a4373d5924efdf0a0003b30fb0340846de84986d1b9d941ec9090e170d010001	\\x7174e9c4bd2e7e223e5303915ab004291cd08166dbd800fcec7826ccd00556f0bbed1e751d80cad2395d4c3c3bf451c5fb06c01bcf13410fc26c2e268edb870b	1670665588000000	1671270388000000	1734342388000000	1828950388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x5ba4e82723085e23f2567533c5c3cb60083b05e6e13ae0efcd7d021e0219c18419c9e3838c1fa8a381c048bf6dc105ecf35bc0de33d487aeb79154e9afdbd4e6	1	0	\\x000000010000000000800003f85872530d25a05ca5714bf0a1513bbfee8e99643d5b784e3e41f8c5163caac6a4799533eb3a4ed4f16b38f3c6b1bc1f6c5a553344e1205cfe7be0c335fd33d63a3a5a7f716f46f1cf002482b5d8a3e8efbb4be1a32852b7f0adb7b09f2d730c17359e6e24020f63d91d9749b45c9b8ca69b1a7b9bb20f8f665994440bc88235010001	\\xa11503ddf7fe2686ef3f8e869b61ea9c5193ba664c976ceaae48531d4c231ba1fed70103b66e65e4c8f1bc16a548cc89598f0acea057559b226863c12918d205	1673688088000000	1674292888000000	1737364888000000	1831972888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
49	\\x5ba4916394091ab94b8dd2682534f57afbd7e779272b849560da3497dd082ae07327205888b905abfb67012d09d583d2744bd3378c4d5a3c70e5a4192c6207ea	1	0	\\x000000010000000000800003ce6df1d39c00bfeb6a1b26d5cad6edd15c8366d69402f07a6e88d4594e50ce9302b45785a13ccd8864fd049a53bc6dec3b694442805c861ecd668856e95c1bdeb215a2e1233a43826b5db52398b5058f13b338bb2d6c687220ac3d49e8fae4d6b3b243ed8b697d9eda06f6b52c796e78d1bda954afe141eb86fa359c7a008649010001	\\xcf1c2023eeba7ffeb2733c56608248bdbb134d71563aa968dd4b70202df4d30c3e1dd4bd327e3df13aee523f8b03a488540f6cadf00a5533c97f2ac987b67602	1673083588000000	1673688388000000	1736760388000000	1831368388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x5b705b8eb03b084f8cd731a517fa77dacc6baa4a4492a73bc43401c8dfa5c23b258a4b9bba08f8b88e8e6aad7d1f7b6ea09e37962b14445d73bf8bef7ecb8a2c	1	0	\\x000000010000000000800003c73471410f55c3a43393699aaa0b6e9f9aaa3b95e233c2c9f3f9310b0002097ee103de9bab34399d246937165c6521943c6077ab1491419911beebd67361ad91c9390f114245699b2050283c6f21aec2bf1eac20c382ecb94affa39286412b178f5a9ae13e515506635bc1ad6dcd7cf96f6c18c936d72e945e3ba3fbead393db010001	\\x02db8cc3e5cb00ac5c719957bb70be4a1d961f4c069a52cd261e835d95a74ab9731c5b3a873ab4ce436fb9353e75b9b481dd665fb5d205f314cec62b0d4a2d06	1673083588000000	1673688388000000	1736760388000000	1831368388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
51	\\x5c18e050787ae4ddd223f4fef613a8053c49bf9f9c665c07025ecdcc15a8da537998279866f9535c2505a1aba857745de8b617b84e356e454370aa89e4902d14	1	0	\\x000000010000000000800003d3a4cf14c2abba6f22a4a83d6b7a24ae66ce296f1c8bfe09debfff68c552c919550476c69b22d9f797ff14d229e926b1743885ff3870d1576a34bc08a258b0ea4cf24bfb7e75fae33e1800f1115327a1dacfa384613882e58cb6db2f2c26084b1fc9d2b013fd211d8841f6bb99166b7a2bf8d4c43ceb67281ba43c028134ae23010001	\\xc148c84366c07cb3ef5635bdd7116486b465d7ef4e5b7d1a66898786425730fab28086ab5bb659d8ba63fa3f12a453fedbdfbb418e74d230274b33efe9d8d40b	1667038588000000	1667643388000000	1730715388000000	1825323388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x5cb85c4bbd378874088e91dd7345d0193b5a71413efefc1a40242f800dfb839c3fe2972818398aacec95744f3d43a52729453e18dcc20944c66a69af1401e2b2	1	0	\\x000000010000000000800003dcc75fc1c41ffb38f6301711f15e1b575d8ec8f93bb6be7006945a3d092f046fa258806ac2878648a39c3740fefb946f448f3aaf6684fb5e128e6ac6e55f8eeee9b52ed7b1ef85798037bc3bdf4789c1c4486f215d90744d5524609d96ff4ed509db2cf4d03aa298b3049e733667d2ffa33b066a101b3388f3c160a40b319659010001	\\x1a34c0f64d94d758ea951894a815f9ba49674e50e4b13105aaada2ffcd31a74d352d4d8cb07a9773c4b2ea59d30e17620e570402556b5cec59a7f51db2555e05	1664016088000000	1664620888000000	1727692888000000	1822300888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x5d18b7987977a4e9be8d103ae73c361cbb3482b976e38406855f79705525f8136f3b62cf0871bb9626a0fea65f63a3d48f54d4b9d7ccb7db660d315db36abec2	1	0	\\x000000010000000000800003a642cd149f55566adef0ef7ea0efbfe3e291a9d3668619896dda94236cbcd01a19409a084d7fb73579f048d73eff0272a29f5a8974e4884a7e3f112223846f2e72338bbe4283ae2bebc81f428ca8037e8b3953a1b64518961422a51fb61eadb108816e9471a7fb8eeab7f49291587b3c70e6bb688ca3c3f5e0cbb16818dcc243010001	\\xed78bfbe7b472d26414964996b8e13cee26e4e5e08f6d188ba5458248df35452770214a219cf137d47e9f7256f8dbe51ee1fffb5cfa1c0d316335daa65984808	1675501588000000	1676106388000000	1739178388000000	1833786388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
54	\\x61085a79bd08f78e2a71cd4f40dc408f9084d5d282cc26e924efab8c4b03f5283037c7579ccf21f9af69cb46bbadfcc4834f694b95c3aa8fd7b4e7234385ca9e	1	0	\\x000000010000000000800003c662a373618d217934bce07f0d671c2f3c53a6756dd03d35d72839ce82de2fd670828c13dc6c51c6bd1c2d90194915b583d1ece7936e8798193ecccd538fc70c7d8252615f8be19efe121e55f954779e263e761380a7f06ccbc84e58204bbc29290c7ffaa8cbd313327b6f49e90e61e299771e23037ca15dc7bf330a3ae6a145010001	\\xc45df8e89218dd656ce8252004d4d5f918586a7783e7b2f40a5b30f718d4d0976b9d53672cae37480598294863d5f39795d433df1a534e2bbeb0480ae53dee03	1649508088000000	1650112888000000	1713184888000000	1807792888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x6834f564ded0de99c8c6d76defbca1fb4f30389520476133c04c26f54a9cd434e87d14c6f572f2cfd3c2f4ef2da0e8e2cd67df367d17374adde74e04754b6882	1	0	\\x000000010000000000800003ce36512757e89e1685c87177e7c5a0608f6c0a3d82b904a97769aba189245278c5088dae47e57094ba095b517c0a04cb847260a64b7633a2c6cf66e5846d12fd39b6b627fa8887537c3fbde0df7f38ae9b255806847298a618b70ebddec42ba491bfde4c2175268756170077aeb75be1e6e743406e9d456ac67112765761b77f010001	\\x7b308298d50cb33fd26b323b1c42a02f147f4b47318699c916202572fa9f0a1317beeefe1d454357904111ee49ea63838a7401ee161785c323a2c0c4c1d75f01	1660993588000000	1661598388000000	1724670388000000	1819278388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x6b48c9278792355cf9f14e2d8f44cea92e3da1a4f3fe118b91199761f53aa392dbac244cbafb53b5ef272d3336f511df6e493a144766278fadcc212bf9b5dbf5	1	0	\\x0000000100000000008000039a80616fba1addaf883733eec98bcb0f181569adf278b363d075a4c96c44d7f25863628cfc3709553beaf624f08a9025968e22177659b50e4dad198119bb8b0aad4394e9671232707e71487234d26cccb7e3ff15f8b506aca786f7cd8d940a255e0cc512fe2b1e9b4789c0e5b4e5e0d3708b0d189fb1ef2bd1fb0ed69e158f63010001	\\x77e9b1e10a5d0a6a7b0d5765fc0f3ddc04a6369ca0c3858d96b0c57290a7bbb5f433be370e6adc592e69972a7f8f1e1ea104c9716d2c33752bb83dfd2a4beb04	1654948588000000	1655553388000000	1718625388000000	1813233388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
57	\\x6dd064830d07d52f0a5aab829f691c152799ebe638966d5964a7bb4fcbc48b9af3fc1ecf3d48cc24979f5abdc11b3814cfda43309c1d2eef4d77ea91873c8708	1	0	\\x000000010000000000800003c61dffb8f8615a783fed5cfa60df0c2d2eac576598cea984ad229870170c3721a51ca5169477bca621bba9b0b86edbb94d4be3d35e69b8b7df0043d8aa7ac5bad8179c32519662e234c2484d85227331ddc8509624dbff516ce01d21117b2f3e31e149f137bccd8b89fc6fecfc75ea7bbd17ffea4a9e98aa4df7644f867dd1ff010001	\\xb003b0942f2a5844e8c6483485c634e41d68d9df173eca361002e34736eebfbf4ec215a42cf140a3f61663f5755651e03c22e4885e5f6206ea4a721f1ab0c505	1666434088000000	1667038888000000	1730110888000000	1824718888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x6e783e2cbe19c25cb9413a9d3f77e63b2bb57f096a9ce300c270d181de7840ce0f2e60020614e14a85d12f3da289146c05dffcbb69a25b77de5d1e8249264ba0	1	0	\\x000000010000000000800003df94d0bc92803948cf12536f40195c9044f1c41be7b6aae1a0906e239587b0d333d032098e932bd139d5b31388689954b172eb68dc591772496152cbad9829147ca95173fd960b9ce8f51c8757f0c118155a9d744b07e39526f350056f4a25fbeb1c79c31bc6297876b1d7d2cb4aab8fca1739b285abfcb37369ceb9cbb7664b010001	\\xaabfdf6b1bbd008463e7e195f281641cbca151c65bdde53c2dca6658aeeddfeb5d327a28a54049b25f1fa917b6fb882c0f7ac52c1802233920af126300e0400b	1669456588000000	1670061388000000	1733133388000000	1827741388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
59	\\x6fcc25d3aaaade37543b4bc74bef54146bed5e744ad24bea567dee17ae3a05b60726748faeaf8e6cd0e0ec0db2766a1e14caa8011b06ba6ecb08ad1326650ddc	1	0	\\x000000010000000000800003bca6a6d81533dcf0352825fe113a227fe1cab0610533b82198f437850f9b586a1d422cb9a2ad50cdeb013f7c4c61696902c28993b510cb2002fdd77a505251d1f7dc6b698cfc610849ae18be721c7df801288eda08b7a2b8d22e6dbf8f2d7540ee9ef930477f900d14edb8fd84c434d03540be1c7e28eda5d48a019a37c08e83010001	\\x1b7c08971c99a28dc35d5f836e3e194c61f54b505915e1c64fa102dc183364fccb82f09abeb8b911db12c46401f362770e675adc0d4e97defa06de5c47527d0c	1675501588000000	1676106388000000	1739178388000000	1833786388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x6f04e9d206bc6938fc5526dffc4d590a9e77cb545ff8f2fa89654bef8f97e058e861d76c7fffa4dc99a52b509213a1114be32aebb2a965a47e14a61c89c8c459	1	0	\\x000000010000000000800003de18d85d246b285b0ae7923c8aada21beb6eff255938d0f8d9aff7020471c2cd989255da8cac568f4c41a5bf524ca4b7dd0ef8690e117354ae4aa8e4b3c23690d9d0f6e6e872d67995c13f5242c08b747c1e269bda2fbc153d1096c721296473cfdaf6c9780cc2656ac09c61cfc178bace955f351d14e67824ac6495c0882ff7010001	\\xf64ec52e9a5292967f0dd847f1e9b171d5d09d78c2bda4701817bc44da38fbf2b9f4edc665d451eff7ba80019a89660748c47e44315a9d479c9fc2702102850f	1672479088000000	1673083888000000	1736155888000000	1830763888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x717c13422b9aa9faeae7e552f864d78e977d82ac527c78f731f16a45f1f39665de0ca404e6c3e2e759176076d7125e6d1378e4bd5ed41c949bae17f7aeed82c4	1	0	\\x000000010000000000800003a71547dfe2c77fbc22b454991242c078637da09b34e4baae24eea6159894c05c21a914eefd0ae94fed5c887e191eb1dd1bc1f980b422ce7191ae3f4811189553768c2453c1af32942e116bcd0e2de1bad2e30f587ef18a348552e1781a5c073ecdae6c7ff030075f3060e9eae31b9098746a68677f548d2fdefb3137b8eef15f010001	\\x920f8a48133884a8675105e0062860f7d6bacc6a826fac14d48f23ca587bece0caa14f5b212c06fdf341bd699b87265b443d10e1ab225e3f92e0a298d1815c08	1651926088000000	1652530888000000	1715602888000000	1810210888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x71602c409791d2b5f33cb2a6a36b10014db4c10db883a654d02766815baacaedf53989895e5a71a78e7a3042042946aacd55a3a952704a63a0363eaa070f31d8	1	0	\\x000000010000000000800003d6eb55fd35173a9064803c525114b26a1e31e95dcbf24b57898df6074bcf42fea6656c850aa152584487ecbfcd446451cc98d47276c1ebae5a443e817c9dee0964abdd5ab44584496061a2dfba2506e01143eec82070e5316c78af77a1374a36c76df16f31b9807c90ffd030b877eab1353e5df50aef884fb1326cecb52b9493010001	\\xa98c137a158efeb1585424193f651405564beb703a7f6625d29ee9a31b3936aea639c9f85d29e252c11060bdc15b39068db9468713baa5be6160e98f924ee503	1671874588000000	1672479388000000	1735551388000000	1830159388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x71348e99d1b8326c846add906a93cc21f1ea29cf7841369a581ae5a9b86f45526850c5917e32b3f1dbfeff2849d4f67daa9c2710e0e93bdc0751895c9cfddd11	1	0	\\x000000010000000000800003cd9acc7c4342f4fa00cb0de1666e19e053879c974a6a8d436a8d5bc5d9e3f171d19942595e8db6fb50ff6eb7974b36c735ff3d02c965fe86ced5e762b2867e1db72f2174291b0bc813674fe2678d3bcc7f8f6e8932b13c4bb58c8803d12ba2e05296b7c6862e55d7758771cacf07ee43c6a56302a6d5d079a6e28d3f736e0aab010001	\\xbfac212a442a3ab6b3b3b4684a1ee3330e14e6e49a402eb89d0920d35a18189a6c90bbfc52d15e357d16df913df405e5e152eae8e2bc596baddf778282472308	1662202588000000	1662807388000000	1725879388000000	1820487388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
64	\\x7438da7b7f4e8dd45c912f9bf798ca2a707e31c7e755d4419541b6865b0741783ba611e7a407a73d5e2dae1409b1e07f3e973b470911da48024c77344af5b5ac	1	0	\\x000000010000000000800003d46431a792bc8f52aaf9c2d42bb721de89705094e150067544e89bee566e58e7005e4ad0fce8a93ff52783452ce36e2cfa9d4ec9ff498fc2033c4488a15cc9a4854e0dc81902a2bc8c70628c6af1f01ddcd4d120835bd7741514089c95f7eadc6dc6bf7b1ae9572cf1e46f26c09cae3b6b77fe31eaf5caadc5688348504d1db9010001	\\x4557013fbc485de90ee752db690801de948935e777be1f9b770941f434890039403bbfaa28906441b7ff5bc1dc8464125df38d454cca629ff08cdce1b829540f	1656157588000000	1656762388000000	1719834388000000	1814442388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\x752cc99e0792de3a143ab115e37a2293d0b310aafdee2c6b4569bf85cf9ca43ea3f37f5887d448a8b59b342df8a37810f5b3d1de29b0675c24869ae626c2bdc3	1	0	\\x000000010000000000800003a3567855304543c47acd201d8ebaeefbc25aeb42e4e01c656a450bd8584cbda6794f234529c85b8baba52f505180ecc30b62907662ab245c37da8798b58dc944be5d725aa4b778089252fc75038d1c1ce7355eeb1b0f2efafb6c302ad7210e9871063366a4d167deebd5787b78072246d65028c5a4f4dba05d39d55da15da4f9010001	\\x412fa7a82fbe0ece61b70021a9896b35233fe7de03b147a599faf49124af49aa4bcedef6699b1b8bee46dd6c1baff84b94dac5f56afe442b11dff34159850d06	1650717088000000	1651321888000000	1714393888000000	1809001888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\x7c74916dbaaa3525b347934b581efc37597cc3165692da830fb38edf53604c835baade7db88007b3c85892fc9243609a59c5c224598f1e7df5c7bd2aa61bd53c	1	0	\\x000000010000000000800003b23c9ca5576d58b66f4786a0233fdf40c3494c973fba59620c10c57c53a5320dfecd4c6cd4707346fb17a7870ffa897d37655822cfcf827cc535dd3f8c7a8e42dac6afabe0310a138c8d3a4ce978175697e3d5c8c325830881f9219b1fd1a9d164088f6a2762e2cb48a6efc6bbfada21c25dda4286569ccc5eb84879f43b4453010001	\\x9fe4ade2070acce0cb1f4de34af7a93b288c5ac7d0e3ba7f831ea450d73997de1fdbab04291c381ff6432a5bdde7d47ef2d94315f866baeefb5379193d53160d	1656762088000000	1657366888000000	1720438888000000	1815046888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x7d003cfd1457025ea07cf59f3c53d8ce1bfa5f293c4a23f9f4686800eb853c9324dca350cf5c6b56a51b8f848ebed0703031bd63abff6fd747ca2ec652e43b67	1	0	\\x0000000100000000008000039e41eb2b635bb10bd6f7d776a841f341cf014887b5ac84741440ecfb8ec8ae91259109ebae801218754fdfb5f5b1c8425c17fba8da98dc0c0e222b2c4e0253c398c25736025a543a676cb88c8edb46edf342ae2b06f43e1f1511468edb303fbe16ca11d41ca377b3a5cfc263e8b9d3f5a784e4c3b234eb6de0fd13d2afbf82e5010001	\\x6e9a7214d8eae6c5ca4c01f6f4a5acef7165b82200275eb9dab24742c485a516e38fa46030fe99f875dd05a2792092ba4d6942df618719e646aab97943012e08	1669456588000000	1670061388000000	1733133388000000	1827741388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\x7e64c98839e689f5c0a1b0564ebb31bc4e43bc5ef9886f25c375dc26eb6cb08c0eb1cd4985bad143f4c4d2f8bc38a1c302a7d29378a9ad2e8fb58d793c2346a9	1	0	\\x000000010000000000800003c1497f8eba72bd5674b6434f1482c2f2c2d17bce91493a9048714b40313bf56bf4e45a07d7ef5647de8d658125e5f47f072ac29ce9135ebef8345939e3324575401de54743cb874540525eb007bfc4bffc039c573446cf90a27f94b43bec5d14c67bef4e22ff016a53a7386e76d431231eab6a2a28bb556f32b719f684174b7d010001	\\xf6664c0d26d6b44537287a40a185576966a7bc78d22907d0a0515347dabf90245cbc9631a1c784f11604dee138441b152c64bc54092e9deac023d709f9111403	1668852088000000	1669456888000000	1732528888000000	1827136888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\x80903bac7ab3fd482a64f082ff046b71268ddee9c3257caef375ba0ee0bc9165aba842c1bfe033c5b545e92c1d318cb6c9c34f10f27609758943ddb7e46c6d41	1	0	\\x000000010000000000800003d8a041f97668178b2f62a0d1a64e1d6aeb74772ff25b44268c95874fdc83828ed6895aecef3666f277e87fd12153a4ccb6fd4c59188a095d4d646fba35605768b202069a9eaeafe828fbf03b390e33daebed93c8a516589e75486d46a9a2511a9dbfd666723c40dc6ffee73a9f67e22e41c7c93b5524e130344da02788f0af43010001	\\xf7e64cc5cf9759e5430192800672ac0ae2971873cabd33eeac18b1347beddd8edbadfd6f45d72813726ff1f11bc292ce5e148ee6b1568734a8e05b6d7e1f160f	1668247588000000	1668852388000000	1731924388000000	1826532388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
70	\\x814c933af869ad957de9d8eb95edfd701702d8f43bc1b5b088d12b2c5dd00587aeb6d7964cefafbc29f55d95812bde8f8c05acf55f02762859162604eab9d6dc	1	0	\\x000000010000000000800003da9e8fbe7dc4811dac27be42158a67e23b6108723583b0f011943c2bb404bbca870a5f1084f8034f5476a528d0d70d7b5d5de8ff8d10420587c06482ef8a8ea34ad68380ddc07d0574f704c109d4179431649bdac77cb5b544f9655f07c326b2c1ba3e58b46ea0d7838d90bef992de5f679ab57eb995b106de74329cd47bd889010001	\\x92fb2690b7e45292df47211435b9761fb80c185513df63707dddede289da96992fa214e5941c6f3583a2d68cd17ac61ec9e8c01c392ad7e2f74aa0faddca390a	1667038588000000	1667643388000000	1730715388000000	1825323388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
71	\\x82405474211a452c85bda756ed1f1d7fa4f141cadc334393e5e2537322dd9177a2f62d2671b5fd4eff3241c90371edf582307bfa31ed21b5cfdd9ab9d0d9188d	1	0	\\x0000000100000000008000039dc9b11af27f8a32a080965ea7f4981df4a01ecb6eb20e7bf3627a8a89668847b5df0eda1853a7c5d057308b4f35b0fc2fb18fe21f0b9400565e222eb062fadcbfd76acc8b43e0dca792133f10fb98e1b819fb449c570fdaf2e9ec34af081510ae50e0f75037f4d872494a2b17cfe0daa5e57135eec25d3e34916ecc3ae5be79010001	\\xc4e7d7033c019484321b6d9f7dd53eac704574b3a657d48293e5368ec6412c4fe53a501fdf7527fcaa421c3420b018974f2725f4001cb5fa519b644f43aa9d0c	1664620588000000	1665225388000000	1728297388000000	1822905388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
72	\\x82f85cd813f52a815e6628339ad0d11e80dc560480bb43627e245b73cc7224404ddb64803bfa07ac6683df0896fd44a48a14002cf488453e6d5b6926db6c420b	1	0	\\x000000010000000000800003c3791ee53a5d9b76e3548116ccb9995424615b188090544f00d42dc82bf95b77f84a5a2004db21a59a356a42466613bcb22ef92f63397e295a8c0510636009f183e1f11e7666eaa1ba7716fdeb3fe938cdb0559d362eaabc8829f0dec3b426b29758d64b864d3173f6885121dbb4d0aff96db99da44c4ce80a0142fd62b7eafd010001	\\xaf65ec33d6d963787eba47807c0a66a97f1c8d092b83567a22e1b063532d80bb7c7090a025db47b738b95cbf2a03670148c196037340d2aff73002b51c328909	1659180088000000	1659784888000000	1722856888000000	1817464888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
73	\\x8400dfeb733944bb68a556f2b9826fc4e899a54bd4b9547a5b05cdd789d529b374c7c75fa4d728a910fe107b6cfcce770a42a82f992827eb64695acafb58c91f	1	0	\\x000000010000000000800003b67f829cf2cc12db4c58793ae28e763d97f116014446f55f63350178f09aba69c4985023e5d970f67c837bc641e0a4f087b911e2bdb0ffa0e106f629c5f9147eff48eda48d598d95f1fcc3345cf02704367a42669e43c35cd4215e08f2dc1e43f80c12e6b32c21e15f39d43c67022d883f3a68b1908e82e2f846afb78f8482b1010001	\\xe74b6800f576c1bbc27e059401509ab7c2f0da31dbf3f3e422332a3b02d5e4e98110720f2e9b7bf900b12f846f067646310cc27c9ac31eb09ce412c2fb5a610a	1653135088000000	1653739888000000	1716811888000000	1811419888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
74	\\x897c17337167f456829a48d5d7d567f5d87e337745c31984dfa06ed3adb5a03fc92a001628ce66efff9f64ba66699a52f05a39e5bacbd8a890992f30fe149293	1	0	\\x000000010000000000800003b38d1bd9eec5f3d706e3947508ae8a0f2548924177b4ea2a9fccb70f3005bc0099c71a060e8b7f04bd664652a7954e26a16793f8ab632b0b29f61b0c36c672581854be8db3a97cfd022ede82abd2de7ba6b1282ae77335e6eea214d3964a3d0a0f66470f885cab69b7e89f276161e7daf52a4a3a8f2a258b054fbd83934506c3010001	\\x4a64a3fff048266765f192bb6ff140f1300f94827f0acb90da5966205734a79604a7d908b17545e098221338e56fe4178438ee83744bb3ec9f5694fd05df8c0b	1657366588000000	1657971388000000	1721043388000000	1815651388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
75	\\x894445e3a5951ead78c00f697871e4633911eb87180dd51a9b309172e70990f3e05af69daa563dd15caabd536ade1740135061fcac768c27daeaa06a0a88105b	1	0	\\x000000010000000000800003f97464c52fc8462c5f5bf1c54ab03075f1429635269009fc35241f42962e4f921acf5e97515e759307aa0abf70f2911d541ecde2b31c631f2a42126a22421ccf29d8a90ab8aa3bedf2f7e428494f5739d748272dc17eddbb5f269ac7926363988fc274299e42d61999b6f996d40246d837473e58ba56fc6f2b25a70a6a7e9229010001	\\x8803dd706100b6ffdc0052ba18bb9474718a978325ca266667c4dcad11a6b226f4f6a8fd20975d8d8d609ad0cd31bdc3d33c4fd5ea85ba45b5b06b06cc4d8f0c	1651321588000000	1651926388000000	1714998388000000	1809606388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
76	\\x8b30f72d8f29417e9eab2e1010666446e32992646fa6c396c43ecbbc86e3ce487e192db89d1f0afe7d6d9bd1df9a2955fc7b1176bb7d90ec07c383f5f117bae2	1	0	\\x000000010000000000800003c0a82cb8f228e2ef9b3e4bcabb320bdfdb079a6b82bd14e9313945956b0f3fb5d4c616c64962ac52548e620a5126f28262b5cdd7b844b723a8346c338be998f775d47aa6f4356d086901e817f58e6f893ca52465a48e68cd43f57710f352f4ae017db9bb558e60bf248f502586723960808003bcd7f7eb8eb550a55913aa2475010001	\\x1945ac19ae8323bbf9773d08c9192708bb59c72a066972c4f8af002f894bae3f1cc289438a4eadb0b91d83cc91b99c60131e39eea9aadffc7fd60f6dc88f0f09	1656157588000000	1656762388000000	1719834388000000	1814442388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\x8c2c6055a358c2ba27e602ee5236448ddf8ffbbc20d9e1eb2959888ec7dd4bd9ee24dd40f28583636e3524e1d0e2022b9ebff7b1c5b817af8a941301310ce894	1	0	\\x000000010000000000800003b3eed99afacd1ab3a46da6851d3b233d19f12d4036b849a74a094b2fcc94bad0b9c8803a05d8c6a7f8b121de34c13aa9955eaffc9c7e55cb4c6f0b6bdbf34b493402c8675f3c2dad83897a2b877b947b18d6a358e871adce53d580b7d494ca63299b883016818489f6e661144ba8c0fb8509695095fed94930a60d366479db85010001	\\xafba659eeb6db4daf4be041be328fc645b15ff0593261202a366e881757121852190c64f3893e98193d0558efa52a4b9d78a5767b2b5cb4755f402ba1641b903	1662807088000000	1663411888000000	1726483888000000	1821091888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
78	\\x95109b0516b01331f310903b2b3df0a23532faf81efb55cb735ef82dbb145c4e68ef79dd61f9f01ca6da1c0a9347905528d40a896b6d1bbd8d257c8efe91e5e4	1	0	\\x000000010000000000800003b3a6e5d38eb15e9dd784c41e73da66159e4e1e3eabf5226ebb8a1fcaeecb153095542c19cedb80406951e02fa7e6a067a528fa775686a7ade7df26cf33374ea40ea5f88029f5830d4f32a470caebe125e48936f4500b99f327fb4c8627ea9cfc735e8da6486a113de47e9ddf04b531be205673736a5b80cdce0446b108c1d5c1010001	\\xa0f6c0a013896356e10328ced50ff5bd62e1b2b5f73f78e5131dadac5a3576cac06ca8e4ed4ae5286b1bf121971bae1afdcdee28e1b76cfa863480ae6d4cbb0b	1667643088000000	1668247888000000	1731319888000000	1825927888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
79	\\x955ca3c2ec651271c01064af4546f7743671adba9e898c9689d9a5a56bb407ae13cf78fc944eb3a463859714ec9fee7180323f85159133529fdf50e81c0afb24	1	0	\\x000000010000000000800003a9984cb8460642ffdf1d90ab5fb79bb7cd8b4b585e29465b7feab82e2805697d2d4ca0b6507789839cc789c7856a9fa724f2574de14a31a846254a0124a1de0f15c316b1903aad11b0cb3e1c9c352b416dcdd6a1952f4ae4e7a4792526fa0b249d8618390cf7da9f1a216e942e57df1c6a47cf7128075119ed02e83460b7c193010001	\\x6462b08016ab4f66602af3d6910977f10039b826369ea3c1e447660695e4f6a66f30c673c18c5194f5015932457188f4a4cb38c38ca2a2b3ec73c6b605df000b	1670665588000000	1671270388000000	1734342388000000	1828950388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
80	\\x9d84f1d435f40fec2af5df06794076cd89110e319eab0152419e0f50b5627eff2351e097cdc29400090352d284887208238948e467530bb4cf02966fa1c64bdf	1	0	\\x000000010000000000800003d2eca11456ccfc63c7e8907671f0e3c815dd2b40eab7fe107d291d498dc7f39d913b465e2ee57d90614a75e5c6371b20355891f126df7a0123ed59ea7e715e15b58aa6bdae5f2dc85a844732a3dbd72b3071e89a848e63972d4b1869f1af2dd6f57809698b17397f49e633d4524e7483bcf506b44bdd08736204219f26c7fdbd010001	\\xc425c52a8f48ce6bf5eebc54edeacea6cd919afaeefb65da8f45e3b31c5c78805008284765b2dc1bf45d7dcd20e9f36d87ca0b1139cb1702db7ff9f5186caa09	1667038588000000	1667643388000000	1730715388000000	1825323388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\x9d583ddace73d75058949a22a2ffbf17dd5b4cd2efd192acb9c7b02f18a5c97cf8eb9b30bf8a7eeb3af03a4e386bc102d8898d21502bc699563a7e3c2063f328	1	0	\\x000000010000000000800003ac523e9d753f658592616e318966b2241dda932e9e2a541d1cb6610704f26841fc92796ceda6b3b8d4f0bb52852b12403b41f640d9faa9a60114d8b6e5fa97cc644e046fa419308537ed0ae1b275b4c190d1e2254bd839df1534b5ce7d943d1bdd53203f37df9ca2cc7d6cce4e1afdc1ac5d8d7aec56af475657a73cd060b197010001	\\x8303c9ebdc78477def86ee24d6a0b9146fe6c515825a2e54739b16fecc2afb015384e98401e9328fb24c83184f64c3bc4a55c8511244b373aeadeaf5cfa91a0b	1665225088000000	1665829888000000	1728901888000000	1823509888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
82	\\xa07498991dbedb57405eb32307d323f785c440e4a2e9c74c534cc84892b670d8ae1709dd46e954bcf16a8ac34e8e41570bae3e1159811cb5118f0efdcba5c77d	1	0	\\x000000010000000000800003cd03656cca5508215ed74d1381afa8edb687178aca37b88cf6506da33d91a37163a1ce9068fc1be67c8b242ec9f63575f61260d3043d98350f6017078b88277ced618c55df76541221207c68aa5b0b95cfac1fc35413b9349f7cf8511aa57173def4542687d997aa5c5d9fb3c63bb10f14c13922be934f5784f7694351c9f865010001	\\x8aed6e64144200cbf86b08e2395c957209f4ee57eade210e3d74bef2b1c1af713e22bf1d19e984a1164d48ffa143118f80dee6078a2aa1ee056412ad7465720c	1677315088000000	1677919888000000	1740991888000000	1835599888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
83	\\xa2d0ee9b236274b1f0662b53b98a20f7fb3be7d197f9da1f860c400e72be0974d0f9e5f1073e3bed444a2ee462a40e255878f50cab4725ffcc4b3b1540e52440	1	0	\\x000000010000000000800003bf8ca9ab05fc8cea67a970ba61ca0e7096079cc663c5d00f53d9a134eddff1f44275cc00a9024bb88a8147e7ccbc4af2dc76dd8365e282951c67862249b77c18f989a7aa316102e80eff3e3e70bca235de9955d71c94ca38687b8513ba6f81c24a39ec03704db9fc3e7db784bd4f6cbc282c049dc585ece9a2e838dd5eed074f010001	\\x3a0d78f7d66881aa9370118c8200987b8b8802bffb3df2d6dfc8b8fdc5bc074c6b062131d64791325520059d4af00fad2e8e8c11d28bedd48aa53766db04af0a	1668247588000000	1668852388000000	1731924388000000	1826532388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xa3509ec79da1623c62ba1e00c42623fcf5202754540fef501e1a40424f2ebb30ecf49593fcb8748feee8e1c11e95b9027faa49385c8856c362c66fddc9779b88	1	0	\\x000000010000000000800003d31aff5d8d9e8be67d5a5364b6205ce4e3d93f469d50b6e301d36a66265fb22454dd54dbd86ad75e6efc205564fad1ab44f46fba6f142a440be1dde77b8cb107ed59b02200e3ebc547268653da438f2626083fdb4ef9b7ef6c9366fbb6d7f9cc273b0aa7b720d71278892cc71b10aa15c034c8f9f9e2a2fa7c002a3853664185010001	\\xb26f89c9ed76048f16d354f628015e25abd68fca5b039f0e5660710d0d9d3869db9b81b619efccaa9bbbc6041d919afca9d9c4d58a4cc369e863da74bf3b8502	1660389088000000	1660993888000000	1724065888000000	1818673888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xa418bedbe4c2364a9841abbb67dfbfdc94bf843eb772df2e4843ee68b9fc0f1c6a500692ae301cc210dcbfe301a795b62abff6baa61f17b74040fdc80f787e46	1	0	\\x000000010000000000800003bdbaa817e9ec85f1035a7808b79dcf8dff8fcd8d68e6b4fd688c7a8941627396dfb4f3e19d1c9942bd2f5a630b86fdef8dd6ddbcb2e355a2c240b839add707dc2cad9455ab8f85c20eb6673834fd677b0c1e65392465a10e9f0856fee8826334a42f030c18c265009bb03da48f91b7fa7f662ec420cb0a9231fad04f06cf6867010001	\\x2e1dacfcfea19b3ea0d6a1af99601b0360095e8a7085213ed02cc9a4e30e3a2df8e3247b5b7cc38d6b97907c31effea6c207cb2545d933fa14ff617882c5d305	1658575588000000	1659180388000000	1722252388000000	1816860388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xa67cc0175aca969ec2696957ab407e8067358b6016ab971d0cf1feae4dd09678bcdbaffa52d17ee22ca47fe328feb2ed6dc6a81071384af03c8393f0a9df562e	1	0	\\x000000010000000000800003d6de7657d8717adefb57ededbba5869f6793daf6a0ab918b006b134c187aaa255fbe5fe28e7446c4cd303547a996b9abb6081b799fce10eaf2f8211a93953c7fa71f50c1ceee274f70ff2d2062e763ad6fe2c779f1a252968830f37321224463c28a4a484e5aec034fc52255a88ac95df4c724f129829c6cdfcb36bf26512a5d010001	\\x7eafb184a884a597a25950f56568207890b18bdd25296357e9c155c27c72ec0b47e6b691ed82cd598009d05f83c4dc96e791b5ab56106d6faa0b4401320a6f04	1653135088000000	1653739888000000	1716811888000000	1811419888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xa7f87ba53a885cd1cfe9ed8d819230c0e7e0a055c3b569140323e8f3ab7a372b6cafc9982beae686f7969a60f34f40ca769435ecd476d5f41fa15e4b5ecf332b	1	0	\\x000000010000000000800003dab437d84c04cacf7aabfe7dbff57f5eab82f3640a0014b7a6b81d11df0e2a90af89adff33f2ec9dd4493818044a9c0e7e4aad9a88973f0da88ca3ed4af85c73b83c165ccc68742db568c34378a49d314211e02656996346b5adbd1c57c722e2d2d089f12e37a2d5350e2771838f1f9061dbfe51ea88e5f43f463da65d9a9aa3010001	\\xe6f3339524a4917bad4577d1f44802a03c9f75ca6e03f36a4515889b36de3f0ac0718d8460c1164854771bcf10b9419b87c71113c0f0a0046b27bbd29313f90d	1668852088000000	1669456888000000	1732528888000000	1827136888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xa724ded71c815d77e9639b9f0e4ac32a8b610eafd03e85c7c03adae5b93299bd81bfa171bbde8441edbe83f90a3a17406a3eb3b5053a4d75f545acaecd3ed885	1	0	\\x000000010000000000800003ef7c6fdb2a3a1254f867e3501050bd53135cdc02a681c00ab15b8c94cebce51442d889663b1c7f9bac3726f2108adafbaf2dd1e94e14dacfc4d3800dcb14676a1df36350a8921f1fd1f08540f7f4c1533317e6556e9f573bce836088bf0a026f19ada931bc3881424c2fe848d5667bbf91004b525b8be0bbb125f7cdcb017747010001	\\x02d157d118fcdb74df92cde6565fd72d9d1b247a65e6f977e709baa074bb9123d84f3f5ba261ed46c98473efbbcac01984410d76b43a11ac567e46732fb0030b	1668852088000000	1669456888000000	1732528888000000	1827136888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xa98c0e7c4e63535a4baf5b6bb46adcb27a625d09bfbdbbdcc641b6fe6869dc22b924be5f7f9601dda6dee089d26e3e22c4e45240e5f58a3bf99059861c72ff4f	1	0	\\x000000010000000000800003bf2ace6f94323479aaddf1907fdc0af04b4a71c56a5ede373554a47a1b67496f89479be8f5eca315e1c5359b3a9f4f38419751736c559238c64062d0d38a27866c1a8ffcc82f5a07e68ef72aad7fdcc1a79eabeef400720fdb4765a7b2db2bd94a04fce26d83bbb10d29cae4766e72a0cf2029bb37f4fbc28d6fcf45cb8ad1b7010001	\\x00f70922bd6a95f9bb21f79e89f27e6aa90dd12d297be19ea727bf12bc8edbc7a17ec9e01346fb0c5f28f9c27b629625c8eb4432c6693d366d766c54343d000e	1656157588000000	1656762388000000	1719834388000000	1814442388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xb4fcb88c367f5b7b2aa9c70279063b60da5aeed6b8a50fbabd9e94d2a8f74076757a80950e8701bca15b7719d9707d0a7c6630e8ac6737f4ee8548a53496e9e0	1	0	\\x000000010000000000800003f1f89148d1d77f8741b20b779eeb9ecb9f1925e5e7a502da68d4b10299aea47e6cbfa13005f08ece67a8e8f6ce4fb443501283ba8173f019a096e8e582c5dec3a576512a3ff4337d73ff93f4741d6a3ddb8283de262c1b45f1e50f98952328ff35af0c39edccc621c6863e5bbe628cb49088d4d22d0e1c9f26f341adb848fd7d010001	\\xa05ef3fdd2607937cb5c9a6ab7c5cec7648809b716ed94f9d84c329353d20c2b9aea44282c5f16426f13bc73b987593ff66f2ddab614012b4cdbaea471a8cc0d	1664016088000000	1664620888000000	1727692888000000	1822300888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
91	\\xb7904d93c9167989a4b85c8c316ee5ab542e282cb89076807f998ede853aae38133e85ff7768df0363ec75e8c3ebae615411fe532747517b2788e66cd8322d6d	1	0	\\x000000010000000000800003be22ef783c72a642992fc078f61086b3dba253332cc287f27d25e9ce7699643c07a8910d07a6e51d426d7bd49ee6f32b2c5c4b9d0a1f5755d7b0e7b3307b21ab9b281ca50a724b9957245ec083263dd85f3fd41f1064fb89b6765b7d18691b33b1680209a6a31e993ea42c1b29e4cd4bb5f27d3ab9ee74d71741226b81cb4107010001	\\x9915013b48d313cfbb8991417497c783d786fee0747c5690e6e13746debfd3f80f4e80c8d10aa5ca4e726ad599523a7181eae8919c75d7ceb060dd91e1059d09	1651321588000000	1651926388000000	1714998388000000	1809606388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
92	\\xb95c26145d50fa5d0ad63a73c00e3ea02cf79cd4ee7a0b765c73c49b25720cf10676f6de57aa870769a1a7938dd0a98654ac1b139446dbfff7240144911327af	1	0	\\x000000010000000000800003c3f8db1d16ef269f514b52357eae39a54485e808039513939910374fbd9965569a4baaed8a2f43261bf46a23076db0d329ee89a7792e78c2e1660a356c261f73b7b5a014330f2c5f8c040cdd5e58c301c609682d4ec14e46f1adc7b087b234abfe22b7b640661d9f4da0300c14b1f7f6f5843502686bba3ad6b565232db821a1010001	\\xf42b50ffbb07e27785845c9a1f6c0044899b303b090798b92bad43aaedc8c3ef70c35d16cd987f2f047c8e990a5741060e13fda0e12d5bdfd7616ae252010503	1654948588000000	1655553388000000	1718625388000000	1813233388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xbbbc3d41bd6beabd33371841549249af31b89e208d1e7b8d35a8ffdaa3fdce54a2712440bbb107091d3f7b23c31969b7cba598727c3bfcf63085edd640e9f220	1	0	\\x000000010000000000800003c8308e5854750e485942635bb7322590328a4b9dfd9e3b38db53be00fd682e9179ccaeefb0e094fa9223d4895020ff9249b3a2e359dc41e99aa0a7370f389521eaf2ee537c68d67b935ecc58312e0487ff61e586f0a7f71143ba884dd4d6a631edf063b1205d3236240ae393bc80ffc75bcca78d20eb4b7cdb97239526fdcf51010001	\\xfde6eda03feb84113f5d14197f5b78a7ae529ea9b8c378556ff19c4aecf399c01dae0b77a4b6d0f09890761a26ebc888b28fd012442e53c0011f0ab47dd7f10f	1679128588000000	1679733388000000	1742805388000000	1837413388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xbc38c9e63e57d826e78b837dd57f743042b22e0672c366e3f9bdb73b8cb9d5d01cc39387961fa659b79fe6e2ce30dea385d612065e1a015dc63202bee5d6da75	1	0	\\x000000010000000000800003ae653bda27f6cc5bd3350c60df69106fd6c7c3532c4b3b05824d9bdfa5427e6acaf60c3c3ffc6e8af48621cf168939d609f0e3ff277b70f2f7d0b9a5abbcd0c1c928f155e56785f9128af7072e6e2aefcc2d5745e607dfb6852bd7caf2e3f61822f5de7903b1c19ed13342506489dd5ba3fbf435306902dd90a2ef58f074e27d010001	\\x06e4d6149dc138288dfa16edcd5516fd4bcff927695f8d61d4e529ed7195f3c3bdd9a1066e27c5e470e3a0a78eb7cc4f1cc3c21415edd28761c14636e097c308	1658575588000000	1659180388000000	1722252388000000	1816860388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
95	\\xbe10a9d1021be4cb84774adda9647781ad97a5c4a3eae7fcb21df90d4df0b8a477c33e71daeba0d8d6e94cb2f65a4cbc666f728118f034dce02b8f3d23451f3c	1	0	\\x000000010000000000800003b8b5cdc658b2b13a32e6f1f749aa59687304816dbdc106231837c82090f1ece0d8818131c2d7b2d5b2ae69c823590b2a5fefe0cb7f1dc26d0b35949c8cbac17ceaa11e4d6dd073216ab1d26ed4d95b03154dcb86b5a4a7b1515e78ce270efaa32ceda86d445b5f652e6f155abe8e1e467f452aabc43846fd311c24116c7b2021010001	\\xe892b9a24e5497ba964ed9ded90d828f73c645b2d2278c6623b40b10a4d07490db6a71bc71d4c4904a09a28559b5ebc3ef0fba1de30872291c464ca0250e7b0c	1664016088000000	1664620888000000	1727692888000000	1822300888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xbf2c51e27c158ff607dbe664e4538f07246d6e02acb7f034991ea8f3b3cc088af6fa9dab83da60540c07e7aea08b99827fe91fd5a191f89db72cdee19e9059e6	1	0	\\x000000010000000000800003c24f6f0ded256cb167d39391fcf2676ca82823d15e7408dcf1ce545c7097408303c2f9512f3c66413bb75537c2962e311d22a73eab23cb6d66e014bc055d2eb2009a883765487eb4f398b0f3281f1c44e099f171a11ecd356693eeab277b80a37c825e2330cf6d8b1b17646b6098a43c848eb66c8b50d3371b1af01c1560404f010001	\\xcaa056f1ee0efe19c37588440bf0657e9ffc70d5be8b0592a049bff3c992c0452d7e13dcad41778ae92ce4993fb061db00423bebb1d3cb927e3a53cdc1f43d0f	1677315088000000	1677919888000000	1740991888000000	1835599888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
97	\\xc0d8ace57a0b8396689a559c22b3370b61b98a75391a10eae731b4a7061f233c60aa6db76bff8a1abf86cb69fac3bd473f132e0aede2211ce640caf58c1ac399	1	0	\\x000000010000000000800003b406dd0b06b798cf7d970233c3d100f8dcac65b0f19e74aea6b511aa51ce7c6a9d33cd5efdd7e3049459b25f4d7f6f24cebfb90753aea51032ad3aece05487c3a4a43649f7d175b450ee105000eb29d87ccd3f3129662846bac006a649d48e14a23cf109277fea435d2c1982886c8aad4f0bbde68fbc0b3f5280c9f3833365d3010001	\\xd6cb71411ceabf09515458969b63217e566a90bb7fd5b1066fb9e4c520b422644827a648b74bb442400049fb88c17152316bdba80f8ecb2cf593396e8c3b3800	1667643088000000	1668247888000000	1731319888000000	1825927888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xc664b8dded127ab6b9dbc1e644f12f8283642a4dbee31054dd7d1bb939fdd2ee537dc2ff5215a4ad4b5ead61e295f696ec0db223e5b1ba7fc941ef943d8ba22c	1	0	\\x000000010000000000800003e23d44d1888c4dd651f9090e4f882366ad6e276edb5801061cab9aec290603318f7a2206a213447f84f0971e63a660ae68b0a42f8e6e31ccc6d8c0aba7ae1378a022c020185cbeb6207c388eefaa8f3518d7689256627d21c1164317234ef01d274d2530e9ff0341d068c9772286478107b811d1a93b7d9cb4361a381985be4f010001	\\x1f392e91875a06a7916dd93840cfaccf545f458e0b93da7f86055fe69792fbb81a4441a44dad0245bf0281890ce232b7ffdf70cb9226dbf87a8d57b1a5b96808	1659784588000000	1660389388000000	1723461388000000	1818069388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
99	\\xc810927770290d93d0e09c3a9dd3ef79cd914f42705d21854af54cdf561618316754a8a64e3cccb1062a992849f5d088a2fbd17063ab04fef6bc7fe198e941f5	1	0	\\x000000010000000000800003b59da7eb87bced4799e742a213d13323ca62234fe69dd7d67e687b80d29d1ff723a24fb92291ead2931d49b595b870f878411fad5b954243c093fc1b1d4e2cd076674f60187cb4760529e9a43a27ef1258a61aac4859995a8fa69ae7a27347da2411ad16ca4c4f3dd34536e72e51f598e8f470a563471a5efd774291a4877799010001	\\x1c938460b3bf8805eb9a9262a52e29a74cdbe9598544d3d8944527e7da1238f61c516797d86ecc7070f6dbddbaea41d3bf2e0318e303ca87c20de4ce2e40c701	1668247588000000	1668852388000000	1731924388000000	1826532388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
100	\\xcc944e150c9e21e063cead97d558a5d93e10ab13a87de440724d6401ec00ef6cb900e5196f41275a4d7a0165018c6aaebfa85333d5163b44a58e56d87b366e60	1	0	\\x000000010000000000800003a0f48e3c7aa867b7ebd5253b5b73b4a4c3d3610d91dd345fe998a8fc83f4de907cafdab6ee1513787f8d1002278491b328c3443ff30b72aead1abb806b98cdec163039911a13a726db868fa9e37742a5235874bdcd25a7bbd0b8b56f8e81eadda32cafd89b712bf11dfc9dc78910a36720c5f5297bfcc8d1268aafa748eaadd5010001	\\x17de66682430ec8b4af34526177d2e19b03223fdb1f305cd0165765fc2bed72abd3d5f9001b6833b1dac41bb9a09fc5bdfd00199b604700037e21205bbf8ca03	1648903588000000	1649508388000000	1712580388000000	1807188388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
101	\\xce10087c9bf65648e95c24b29c88da2831849073dbaf255c31130668295f3e20e1d57c201886cc04ca91b3746b3e19a4afd5267c8d51bc14f244eb8c385dd6f8	1	0	\\x000000010000000000800003e06b3f4788f2e5de5ecf949e0fdd153bf2efa0d83c744bf153ee54a2e4dfb05960b4304e74776794128c9d4890dbf46d67bf76dc2856c31395a1aa69ecb055c2b89f623c9a6b41ff0eea085cbaf1bcfa563bbe02252f2682a12ffcfb11e6b69337e7f7b4d61a03ee2dc17486fe893413e04082be32a99e63d6cfc73b74c2f259010001	\\x9b6d9046902a78c7a0c389c8c5140a7e94ff472d3475cd0864de4f5d5fd91fd533197dbfa4fce49171348393df8b2232898dc2888fb64c2f65ab0db6828e4e09	1661598088000000	1662202888000000	1725274888000000	1819882888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\xcfa8016d445e4be938479bae0a916c98aa454c13f5fd80acbfc3d42952c1fd948419299be93637130476acc120e10a8610d87adb2e899af75d53e8966cad5d16	1	0	\\x000000010000000000800003e75bba2c6ad6f9d22b63d1bdc345b157459183302d04173cd3da0c01dd39cf0114f22ba6218166f2e37f07f13426c696b23d07396cb26b1faaaaf3f09456921972f3dcc96bd5caaa1212dddb30e7a9cfc92fb520de2bb9badd39697a736e1320868f4330b64f0aec06faa5d04b271d7247b52429c7124747c098dec1c7665993010001	\\xb14c39d0754836cd40683c4179781343362745bbcc32ed698eb19b4d26f5d412bc92ec851b725a65dea0ab3f4d9680fa8c209edf03125b0b2b0df9872f438005	1660993588000000	1661598388000000	1724670388000000	1819278388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xcfd003c649cb522eebe13002f8927616a01be4fb6e26913a173b73984898e00a56bd066e329e8234961e6244004f39093a823783b214f6f6afacae283efeec84	1	0	\\x000000010000000000800003ca7bb187c518cbeea8e3ca1e6a801d6a2eac4ee8dcb876085b68eccfce9f28c696d62463b0cff860b592d3aba878f21da1ecb8e96c67b65009b85bf2f069df2c34ece1cd23cdf6fcf3dfe5f2ee3c38771292a01055d39e31e28eadc3a176cdaaea2d73079a72efe8fec4d3d3d81c040b403adecd209667374daa10b0083d21f9010001	\\x69a165964929a7bf71f7ebe09a36f00eb360409dc8ff9698cfa3a17db9607f8df8020cad5b43ae5064a9ba6ce9b65aa9ecffc117edbe488402c07f861e462b05	1671270088000000	1671874888000000	1734946888000000	1829554888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\xd098749c867d7aabb7786dff5d850ea1c07b08088d77d12419ee4de66ef5f12f1693c16458a266beb17ae66bc6865512f9f6e354e802c9d4972a85a5b4a0a475	1	0	\\x000000010000000000800003be53f5a0b2dc65785f4b58d66ba1992dcd0e2abc1386cdcfb1ceb1b37642b85fe92cc3ddd50a16494ab29fde5bbc22b61ba02edef8b65d21b9a23c5f3a1572cd4c77ec8b58825cc321f3d3a3d2d5790c300425bba970702fc1d8bbe9494c3b2ca6ff8c7f6ef721d75f61029c2cb13d78c88412fb89eb078b0853ec00f8005b57010001	\\x5876195b111a5df876ea69e6c25d5c99e1ad3c9f716f53135ff55ea1e4bff22e920ccfffcfbee4c23f4c6bfecaeaae27ba2b2ce5de1c9a65de5e323e35e27c07	1651926088000000	1652530888000000	1715602888000000	1810210888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
105	\\xd2a466b59faf75ab77cda02fe6c75f0b52914a5f5fb38f631a6603245d32b798b55e3a07f14f09bb48506b316389f1cb9c0e2ab4ae129a440328d6e27ac61f32	1	0	\\x00000001000000000080000399ce5565c6fd2a6f8989b68e4e5529adc6efcb2f84ff82d08acbcb627ca5aea8125f9ff49ee74fab84142e0588ffc33d93e368190bdbba43f80349e00fddb3717274e4419aa8381eeddbb1e754cf847580e42815da89704d89f1b649b1623987f0286da48863a92a820924dca48371b7f3c4d982f77d7e1c9513d506e91af457010001	\\x4ed281172d101c4a3e7278eb1e9f99ca58f4c8ecefef1109d814a9af41835175e522418e916205cf760afb412c88d0adea25939404ff8ba3d84e3bd6fca42c0e	1677919588000000	1678524388000000	1741596388000000	1836204388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\xd484053d45ff3a7f38b9374b5ab5f51b2e4a1bfb212bea2bc0e10d119b3b3b2dd75a3d2ce93c98bd5bcdff8ac8983c694eecc7bf53465e41132e3d7b4d104b35	1	0	\\x000000010000000000800003eeb9a7b05f68b110fac5ebb5b88793546dbb9b36b48e95957b3a326c01cda622ac2ceee5b2dfb26e23a4abf31523288918c36c177bb3412e7ff53cbf9d381b4122a8c791f6c43e61feb0c75271d17c3656695a0929acbf7d63eeb83ea27412c12b1503657ef81dbdf91a74901b1ab7a2f7ee134cb19ab569dca68e455d0d0393010001	\\x8e3e636ce4e1150151df302356ddebad26c7d00b486b5c45018343c24985dc65c23842bef1646ba110ad46f63ff54fabd12e27ba73a918e78032fd88dee0f407	1649508088000000	1650112888000000	1713184888000000	1807792888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
107	\\xd5f481730f60c170830e21ebf5fae302577c1a548a4a36d2b8c091b2d1182bcd94add0d987074e017d2300d1cafb6307c459b00f5bebd85d80619ee06fbcf837	1	0	\\x000000010000000000800003c879be9771f7239236e4d199afc2b21f016729128f4822bf8490029bb5ff548fd8d7e514ca97ab058e1bf51a55a28c7d5bb24febe68c9449f79837bb91247d325446130d2a559f25501224815092b960f04efb8b79ae78e9b1803e9d1dda87adc87aaa7f059e26f74eb4bfd2a22cf36cc2994da569f891c53ac658d6e349ee6d010001	\\xb3c3576b2e3b408c109e4ad75cb884e6e0e08aa10c3d9213c0d0c67214ec3c9b17b7ed4688adc54c1c31f43777a02735746508cd547e65f478014c26c43e2d02	1666434088000000	1667038888000000	1730110888000000	1824718888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\xd59468834fa02de7a426f99d54e44a52c013b624c02ea1a73d56c5eac7fd0c4582df861891c38f9dfd5ccea944a32136ae198ef4e9b9104fcd85b917cab346cf	1	0	\\x000000010000000000800003d27cbdee7ae1aef5b2d462860a7bfef28f439e04bf34eb3d1bb64997c4ffbb7cbc99ef45847c4d871709541c65215b35ab44738c8a097f4b260e8e334d176ca5577d40b5cbf749d151b8a7c1e61bda6a98dc3a8a34ca36a8f07d925c71d7dc8afa23e9685e43e347449a0019f672dabd2cbbf55192e710fdc45f0adbdafa6e55010001	\\xb8f9c427a576a4867b8856efef806f6d3e5b8fd2a6d8ec3b7e0d09f89b157261a8ab7f1447929e7dda02e4215101fa60bed21e11a026b52773d4fe3c9f9f8a04	1651321588000000	1651926388000000	1714998388000000	1809606388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\xd98834fe5dd937056153e43f8dcd734ada23e122378f901312c732426a80fabe6350ad91070352c8fc0357341c37b6ce1deafd91d312a92fbee6947fde4884e7	1	0	\\x000000010000000000800003d1a44f23cc517151efabd6168d309e9d5102646f31547d044d14c09eab91be5ef28afbd5b9735ce2e6e2da6a4ab09cfa0bead2ffd23b102dcfb3f032909cb7734d80e602aef4d4d2b8c8603bf9b4ee64a1d1de4dd7af3adfa78c4907c8b7ed0c914729f168ebcbfb469f6de00c23037b6a8f1fb04ed8512a76f10cdd22cc1c3b010001	\\x16d0e48eeb937a33edf23c5775083a42e17cefbc1cd0068df945543f2a0406e52b771444e25fbe50d43e70a6b1082f77f043b3d8492e88dda7ee3f2171572c0b	1674292588000000	1674897388000000	1737969388000000	1832577388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
110	\\xdce0f927de8f79f90ad2f10ff27fa4377c0b636e89e3382af8f494a31c9271936fbd7c714380188b8053ca943d618c083c9cd5c1f829853847cf12c531fd13ab	1	0	\\x000000010000000000800003daba020e6c36830219df2152454ab3a090e7431120c68abb0be7c4bcea8dbb16d4be525e7a60d5dd248cc5bf4278cca2fa9e60f998249d986b722c3fa933b1c1faf732198a99a232ec1a6cf4a4e605c4f714f4dbf8115627ec1e87f7920608239ec8d55916ea5cbe199785f2e1d66bc9a73d1405e312bb991ee06e844df018f5010001	\\x4e1818facfaa18bfda9bd6f758601516fa809509ebdd042860938648c28984610844616231c0b0eea828b947a59c156093374e34b7f8bf021430fe57c7f6f701	1654344088000000	1654948888000000	1718020888000000	1812628888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
111	\\xe420f5dbaef82ed894e4cd04847e10103879b7f14c82a8a7fe44974b0bad21f4b88a72ff9c86901ca71b4c9e1465fac896a4364dc006b24024d33f1508b02d33	1	0	\\x000000010000000000800003c65f8f42bb301f142a16331f551bab672da5202b19b54077f11b7d76be5e195f0765ba7663d87ea5d179443312423118efdaa6a19b88fed4e60a983571ebc182e0ee9451563a0436b72adbbfe761b5847356a336433df2f2b5af2146316a5a75a7975d307f011739fa85a620edd13faac240197e9cdfbac59c81fe40c267e7db010001	\\x2718c58a1920e9b640123eedd1fa27742b3c586876de49d888fd260429ab52bff92b2966ceb6966f0d7fa1ca5f0f408bd627f2cc4ee972bb41dbd7b88575eb07	1655553088000000	1656157888000000	1719229888000000	1813837888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\xe5a43e346abe37088b04cb5ab6491ade053091e9c2e8d6fe14468a72438a76164e56c5f0b8f293af94849d2789cb6d6a7823af28176149c3c8b216ba7f1cadb4	1	0	\\x000000010000000000800003c6c28394a7426397ff5c46f86b65358301148364a4e20e6ed6d9557b34d6039a4dff18e5145c164e82d887052702e2c30632ab38c6dd430ed863666ec88f972efd17522eb4891687f76b303e75e6cf03ddb3c6138014b9bb74e9c7f9161b33c737e166002ab4288c608571e7d2e4d80c3f328f71571b73aa2e95475d3e3e9d7d010001	\\x717680a685a23945f4154dc97e35453bb759655b6f332e3a06d2fc7593b0ad7e83e6dac84d9088f613d9b607158c28cd44c1c0518bbf2ebbaf4c669f6871010c	1664016088000000	1664620888000000	1727692888000000	1822300888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
113	\\xe508f5a54b66ec91db733b7800d18feb6701ae6f5142e20c6e9b2994a856d4bd3639e03c13ed3b1cb10e667192092641275dfc572dfe56eb232108303bfc05e1	1	0	\\x000000010000000000800003dc038162b9b830e4919b1950e40e0b492f7c7145ff6eed8f32c35dd2aabe9a0631cf270da1c496e9cd1212467cd4481b2f9f07e5771f925593699e943eddbde29802b137dc10ae5a6fe01d9c21dd2afd66e61ce627032b0441eaa2217bc19ca59683d623b09278f652b959e6d52908ca613e1d8001738d969a58e6d6d1166cfd010001	\\xa63c11c6b51e1693a3efdb6facac0deba59bf381b01d44575d7c210b54d08e37c97a20bff19de32316ee78504ccabc73ebec52794b9b678409be2c82e2a8e503	1648299088000000	1648903888000000	1711975888000000	1806583888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
114	\\xeab8a00b87047c286f623bdff4862607a7bcaab4dfaa67da8e5b81f7f1f0988c065c3aa26c7492603f18db71359db60ec3e30299e557df34e2b78826ca47ed5b	1	0	\\x000000010000000000800003a0070fc6149675696fe393c1acc6756286d8be6d5be45aac86eba00d3c5908d397f705916f3e333fc57920e099b63d0f489f47f5721dd36c837c5797369db8f8b885491da086edf604115b270ee6f0c410edd30ba98709dc186d61a02106e42919574ecd672d81a0aaf6083f4cd311621b239eb515a63a902ca17832870f3041010001	\\xbfb8129b12370464512bb3bc7cce3816e9f887b56d13b3676ace5f74dccc98c002f3ee5692ec0493b34cc60542a16a4cac2553879e56be3c0462e83a86214801	1667038588000000	1667643388000000	1730715388000000	1825323388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
115	\\xeb38586acb392e6ae0f9f47bd5002e7b58a1e0b304ca061f0c0a6a62d5df1be33727ad50820d25b439b3d4257f9025046472ec0e302b47dedc13fe4ac8f5a895	1	0	\\x000000010000000000800003cf829dbd5038a897ec96201506b333028cd61a1910159a5898cbda066722c74f6f01915081cf1f905a3024cac63b37aff42806125d0aeca00d442a05dfae9d7657019ade9a5a0e2db825da933f33739ff29813532d2aa61ed5e575568d72d7f8eb66659a23cc1433a8572a5a5d6107ca902bf0cd55d9eacb163749aa3598ce5f010001	\\x7c2c73d5b5b0138145c87d77119c4c191512b0e5520dc9c395ea1576357418f49e37629d936e7277963fcace916a65ee00a6757256f757d832736c9af225c702	1663411588000000	1664016388000000	1727088388000000	1821696388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
116	\\xefd8d22b601a0325bca114fc9b0f3c025f5522b82614065a5188412a8e21d221826784a342280489fbbcbcd21f4993e694990719892275f3203b6231b16441a1	1	0	\\x000000010000000000800003b18045fc1136728e16a178a47941a32c9e80d5f0b5301684ea8c836cc1f502002410d06787b30b1726ac3f88699485ab582788d24e4223791668bdc9c321581f8fbd18c14db2d899322908d1f1b6f892a63105a16b475fa7315043c7aa034e9b1ca014939c423d018abd493a471fe2246722e5301362bf265e5c2bc9f1a74a09010001	\\xfea3fd3c97b8a4f99ab1274b67d207cc49abfd2c9a6cb9ba43d3b11b7fdaab4915364edd82ab591d51f301e75072b41a5269bdab26b1fd77c48b6a8167c97d0a	1667643088000000	1668247888000000	1731319888000000	1825927888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
117	\\xf454531b3a38e9b9550badb11b5ab187e10b864aaaca055b18a7e319c76f81daecb47cf07579082d42b9a1c51cdba07d28ab29b8f2517196cec5ae4e5febd27a	1	0	\\x000000010000000000800003ce488c2a018aa9fa44b9cdf0b08f4cfe7a4f430ad9e3d1d6b3b9b4a2f76da98a0c478edf5c22bbb2b9367d8a46b90ca55fa2be93c7e35b74b0fdcb8d6e1794cd2c35e26b9397192a901e3f7eb5179f1e1a9e7e2bc388025854cdb015bb53fca049663034e3bbcf24b7996b98d95b0a7903cc9a5b339c28fea5f752c6cd5aa9e3010001	\\x8fb5d4fd203922f4ece4062d29d815cd74047dd0be6e01823252dc221bf987a4e03b4149879c5b004030d69bc9336830834b56b47fec5b3339f97273a1d4a307	1656762088000000	1657366888000000	1720438888000000	1815046888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
118	\\xf52caf1c977087770c39cb09332d3336153f7349917b2f3088194b5a5ae6602dfef53caa6070f3a4d9263044c810f22546544d7f6ce9a058b4d9c1125650603f	1	0	\\x000000010000000000800003c28dc6261e5784f9c2d9bc42cd2a45c1a96cf0b061e64f290c3dc66103fc7cb488dbf2951992efeb23387f93954ef243641104dea56018807cf1bc8b6a25fe4625be1a4f3e5e7d9d8a9533228e7bcfc4c326fe2dab7e513e3e9c4cd7c1202de96cc4d8e47f319caa985a358f9d807d32b68a16da7d17cd540c2b3015d478f313010001	\\x3271edffc1b4f40d605bc8c06e6e44d623231e3427a2d6a5714b4f7c9f2c0a3d0016983efe416e5d1042b9cf428fe2148be5646e90be61d59e91a631b0581d0c	1653739588000000	1654344388000000	1717416388000000	1812024388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\xfa18df1ee4a3cc9f909c331fcc61f403c2bfd9bed4606babc67f9d05085035d568f97e58e0f68e140a61307b68779d963ca04cd176da9beb30b6527ae8cf4d17	1	0	\\x000000010000000000800003ba675a0fc8b63c02b375fa8421f889d2eee15533c3c5831e90f00da943c60e9e343bf957736e2c45f352ff981bcf7759076a6aecf2d630bdfce80f8aa3488ce624bc372585e1cce393ec6e45fae272463e160f68f0725e9d62ff89e96c09c8b676b59e70d85d0da7c66ebdf780496c2c83077312e5865ce80bbe77ba11fefc41010001	\\x103e36fc139df9a0b5af566679035a93227e778f5c0d8da81c8a6e077edc6d61250e5b8acc87c3d0c2d672860e5e3228daf589c535ea3dbf52f9e59e83df7a04	1650717088000000	1651321888000000	1714393888000000	1809001888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\xff14711b4c94e04289cf9d75b6b924c061dfdd263354fca22b4f540d5ec898067f7eb325493f3300dfc2a555e6badfa21c60c5330e363cd226d7cce02b6b20ec	1	0	\\x000000010000000000800003ce3e7a28e4645315544c6426dd329bb9d83068edf3bc25c41e0863589647f2ee0e9545503212e1642097e7e41fc5f528f8461923181fce66f903ad6ec7bd39297c5a671e3c16c74b1f5004ec855d20a589e22f79dfd8ef43a2ec9d9c52c464e6d8cef8f732ac1c2b980959fad56b75d3038a7b7d6d53e9b277b666134718d53b010001	\\x3812f3e7f321f412db2dd231e776fa0c4f97bc08073a6e81e9f5fb0436fd116c6fbc20e8040cfce11bc1c8ea21ba83279516461a2f7b1d9d80b3908903d21205	1667038588000000	1667643388000000	1730715388000000	1825323388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x0145208151c312fe8b60318e75ef70f5d3507b2bcb8a44cccda35dadf8cc63c255cb3c348e57d75636b777a623fbc3ca73cd77bba63e52196234735fef896ad5	1	0	\\x000000010000000000800003ea593fb617112bac2e59b311652d58406348cbbd95879212abaa21e9530a2b2ef5ebcc1aec4e8d866d8eecba7e2f750154dfa27c60b07aac7e94497d168bc6a2149f87e64310e6df4c6b80e485ca9db06a7b1db8fbad9be75f42cbb7bbcb78b2f4c5753035bfa1c5259f202d8574ca6d8b3a82b4ccc8cfa62846e31c137e14b5010001	\\xc9307e05f31fbcceb800b569be184193dd092e0d8a65a56624a714d8779fd2a03481845c941f0f6399b8b5f749f7de2fd05828b3402b80bf11985fa3bd09fb00	1651321588000000	1651926388000000	1714998388000000	1809606388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
122	\\x0479fb6f33b6c7aef21ccd858e63d96b94fbb5dc2e7bdc0c9d69a830e8d4e210b504f7bc28de5eb67e3b7c47ee8a01cccbac75e9c9d7a3ec7bd6b6a34cb125f4	1	0	\\x000000010000000000800003bcdb1076c3430882dae48baf225b16c1f29d247349ecee840efe173e39b3f6c3fe6948629fe4f47d375474a423883cf6859117e99caf9ac93a902fbbe7d33d42d3975bfc56723722f885829df638796deac0cdf5460e161807ce1713b98183472e6620c3123a956123981da061b6d79c4ce7bbfbc25f407e09af069f1a196f5d010001	\\x8fade96545a2110f22853e46dc122ac0bde39854493b2329078fd1c87376f84ffa731827e223ec8206807208362d791b23a3620eebf76862eb4aaaf7abd3e406	1665225088000000	1665829888000000	1728901888000000	1823509888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x07e9f217f74edbae4c0b9264d4d715870a8f37b76aa0d8916d7efdcb56c3b176cf8b1e95cea69ab33c7fd0ad20674b40dbea7049045f664e6ed8231c303e6ebf	1	0	\\x000000010000000000800003eed20f17addb77ddf7136d089d963d2cb7c99d4fdf254b8bb0965e6e037714d2615d7ecee8eba8db1bdb2468304ebcaf168f943c7679cf9dc5850b7cbd7c1e8fea8ab75ce9c7398d0b12f0d01bf8c0bc25d285a97febd19c9f8458a7a5d13608074c587433905ebe1a44ed802272804b6c80cafca926166afb618b5aeeac8b1b010001	\\x3dbcb3cc49388140b88a523d7ff6eeb8e6e5e9ebd11d4e4916d1247c94e6a13751a3518cf511f5d996dee7dc46969684c597105c402f26865126e785769df101	1650112588000000	1650717388000000	1713789388000000	1808397388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x0831976c814689d52d5d6cd95248b3fd5dca9b4e4cc4f3c59f56c1e1082a90ad54c35b63903cfe2201098c2e159a255a6bae53a429588b445817c69ce44bf2f2	1	0	\\x000000010000000000800003c085557541d4fc3fa59cf57cfe55258ebd22e3b4644235620d54dd2360cf429b19a322f87c4de421d9606326d1cdc1513a9c8b0caf6f7c9b05e692a57ae09743b29e644dd73a2a1ed6e7f3d9cf8a6f310e438145c653a82cf4296b7694f7f3485f92f45e5780a12dc46992718f44b2da371bdb38660af7deb1d1d9133544a2a5010001	\\xfc4bd54f4bb7d000356315a9de06bda2264c82dea288ef3d27d06d2f4c7e72608edd6b159aba4b17365be43b5348a6de0375430867a5feaf172e15546f614f0c	1650112588000000	1650717388000000	1713789388000000	1808397388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
125	\\x0a51cce8b9c73b89e5199479923464043a6db1cb2ee6c708a910ab3a87ba99c1769af81d90fcb039d87117f5a30fa6ef58728fc54288b6c94b53ee6c7cb63220	1	0	\\x000000010000000000800003bdf9f2d884049fe5c6410d8cf3ce10017a54353e8b65c50082eeb9085653edee47f65c5b48782ffc58c2773314d5ffc8bb5b751dbfc7c819e52f3b1f271655df74513f77b9606618a26e1c3a1deda10eb6517f9052bb7f1004f37f16a315172bae1c27d41ee893d90c55fd759f75e8f23e4d1902cc14cad338328adf4aac9865010001	\\x082cc7f47afd9a4bd1ca8e21983d3e4c6b748b95ee14d3bbf95874586bfa28fea3f8f18a715428c8cb082f94c80bab5f848cbd84964bb51ac78706f03fc35a01	1651321588000000	1651926388000000	1714998388000000	1809606388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x0bd97295210feccedd525980dcedeb83ecb10c00d87ba2fa63e4e5994d64691a9cf6a0b08f49a5365fc2aaf7745efa3403a9fb97fe6d766e5fa03d1663e323a7	1	0	\\x000000010000000000800003b071453a2b7f6368503046ca392b8375fe663ea291376e48198a62563995684234a19066e797e2fcc5e522536d0587b420cded90e3c3c3392373e1e0e51ef4653d0b27e9d2f1a84111fd34c6052dd5045c77e1de16e22a9cb4143f7b61b7bdfdf48f05c49f8d0fdbdaf20c6a36222b350e6c7145dc1b5397d088c5c1a6c2a757010001	\\x07ef8e83eec3d79f6bea5fa6cd708fa8da2c1a2d1b74d639204ab65fa5aac25805fd128376ae0f1f987407736fc077293da5680fc0ebce28a09220bf549ce603	1661598088000000	1662202888000000	1725274888000000	1819882888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
127	\\x0d65645b79f70c5c64dc74184fcaabc6db9b7904792173ec7373d6f69207e13c68b240dde8453e987cf6dc3757d832f3c78b4db5370b87f5ed580323cfae08dc	1	0	\\x000000010000000000800003b0ecdbff68843c6511557f970a6cc43c0967190b3c83bfb523cddec0de5fec8c26b2d62054546e97dce867a811a0a5550174f9e017cf19ed19b2637ce40768e428a86153e8abda707b8c7b21be991baa536aa8cdd6694ab5d37a804dc27643797f0263f6e15d6b5d3d7657b595aba56a1381ce28b466f8643ff63164fc8ae3f3010001	\\xd4d80f0e9a1718e8bb62925cbcad5e98ba0e54b87ca62c5ed5dcad0b9cb84e1ec923cba06bd57b6d4bbc794b4e1b7623608f9a3390f17dd56fe3cb3b93d0a20c	1656762088000000	1657366888000000	1720438888000000	1815046888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
128	\\x0e4daec7a2b824ae6dcda79b947e29c4e66e6da37cfe21cfb634bd28ce8bb09a798a81b6006d29f30a63e26204095848d8e73016b96eab25d1142e9e670e2c84	1	0	\\x000000010000000000800003b961079756e380fc699b94c1fd622d50b706b682d33ed348bb0e825799adc92f3e8fdca63fc08ba87aa71e556354ca20a1b4893273da29ff2e9602e4d337069c3d36da2ad3d17b6a06ee8ddd725e18f545e0e559deaa5c3ce1ce1b5c47d01192c23abf49577ba22885336dd7b91c3e6d73e18a11a9e3aa3e364bac6ad10ffb23010001	\\x4ee87f936e1ebb5bf12140bd940a479a49ed48e26584dfbfb4628a43e95ca0ee1d4634fc6eff7648d56231ed8c99ee3d8b098d97ac2ea93be5b4d4c59173fd0c	1656157588000000	1656762388000000	1719834388000000	1814442388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
129	\\x1159727f4b1369a0dd43006ae3d250053438d7c7425c96463a13a72fc00f745223b088362769a0636ba960247cec686dc9bcd046e17e10ec98c0ef018200a605	1	0	\\x000000010000000000800003cfe677004396c3b9e990ccd344b954a66447a54cccf41ad7bed04cb90eba9d7d9e031dc303de2795adf71c52947a206498568783ac0461b77e21054897983e647ff2beb685e28c5889e8202624c0b2ece47e4bda150f30ad72c875a6a6971b0b9ab4c8f35b3b3c0dae4eee1e116735f0ca2adb0f17ea865616fdf891faf56ac1010001	\\x7ffeee5990d3b5d603503fd1bdadc492f20f275fc2b1dc3a025efac7c4591fe1edb306dbb3891cd5c986cae798d7121b352d1d41f7cda68f3e7b5001ab41ff0d	1647694588000000	1648299388000000	1711371388000000	1805979388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
130	\\x1481271b9310bd0f55edf9f18fec1cc5680f0fd3c9370b55d5c8e172e7827ec13ea12f0131a765897517e3492dbd5bcd5985ba5196dda368bf799dc1905e63f5	1	0	\\x000000010000000000800003ae6f5fe29c77408e5ea344f42859e0941a5dc1a101ed56cd6bd00c7bf2357a010fb7639ff1e2a2da22ea673530d2a173f2ecc25ceb4f0544251ed35eb8181134235f8f9803f5f89b55dd0e9fb945ca0cfc0f39875f8340948c8847f9870f9e076a767c434b39e2b89b773d635e6627e4dd0900e92c27878c4ae78013f6a61895010001	\\x6583aad9514856c010c5a06037262267de2dd49593b060e27090d12d5ad9b8d5df281372448aec90fb2792be51f2484b6ea78249ab93c5453c51760a05aba705	1671874588000000	1672479388000000	1735551388000000	1830159388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
131	\\x17751d78c102ac7dc392fe4a66aca06bf87b038d7f01e0c202cfea717c05cceaafc86414d2c7804a1aec7040b17b17178b87687c2f7fb4ebb8531dd3dedd2f61	1	0	\\x000000010000000000800003f55127f7d16cbe17f4c00ef0044e86d3a92e9c803aaaeeb07df32b7564cea14d87e02695d0c60eb06504cb01f9399c35c572634936754ea888e2835d2f5c3ee108ca56cd20daa3e7ad09cd848a63495414d4b8cbd8cfd336f0f0e8264a529b79d242e4cde626db84d180e8ccf64c7431629a31cc0c0fe630c193f8b42fc1ef9f010001	\\xcd515df05437dc639e69393ee1add683c6a0b9b690f0dba1ee57d6deabdf9ca39990f3572b96444d08f1b9d8923eb883092ede0a81799c35b5321f3512bc490b	1653135088000000	1653739888000000	1716811888000000	1811419888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x19d1fc5e5d640ec4d49500a9945c767ac283b2f999d29f587455e382c5014e1b5b75af0cb22a846faad139a78d2f673c8a28fe57510a56be5a1dbbbe0b539734	1	0	\\x000000010000000000800003ab1613f63ddd2e3076fc34653bee2ecb8c462e86ef1051d546c29ca0ed77f4c388525b0e736e13e583657f7c2d348ab2417e110fafe86397557f10ca9e1d8fb00ae166dde5a4d1551fb775057c35061a49bf8555fac238190b137f7510ae2df664d6cfbfe7701919e37dc785c13226a09c2c03156d123d79b711cbc51168a30f010001	\\xfe2933a28610a030543a7d30c349189986edab5049746982e3420faffb322f08b8baf829e62088932dc799f788a47df9e0c9f63a3acdd5fbbb6c983ea989dd0b	1659180088000000	1659784888000000	1722856888000000	1817464888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
133	\\x1eb9e0e7e3c8d0ca02ed2b3f7d0adc9444120a1734b91e132daee7f8f36a8070911ab6abfc928bd6d89f13763d30e2067105f3dbd96c1f9abb0a0b044fd50f06	1	0	\\x000000010000000000800003b502e8bce17adf4fd05b10a670985908a2da850232fa496c9729097125ba62391c3cb27ad4ead90f5ecb6b9b139866027262e1831bb5019e31cc09f7975998424a464f98068b7bb0a8f35739ecfeb786d62f6475f34c30c8799e5416224165811d5e88144f51703dead3e7994ce7d5f87656c69162ffdfbf26aadf4ba50edce5010001	\\xba11103a8d48f11f1c2041330a08734f6dcf610df2b3663e1d4bb5af8ac45d851311c0b631cf163549fe57f39b9bccf04e7d5b6c5ba1f9642980446f1a855000	1656762088000000	1657366888000000	1720438888000000	1815046888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
134	\\x1f292aba46e1176c07988c09ebdff203e33143451e8ed5698068580df1050692bfdfa455464b89704c779d557afeb80237eaea706912f085c03a12afaca0241e	1	0	\\x0000000100000000008000039c3983532b0c0c9449f4b5356f20baf0cc78f39ec524ca690d6100975af85c1380508d64db792b9ec1f59c98eb4aa108da57e952a2647199b14a5805a762dd60d9e8124b09386030d6ed76b0b80997522b903bfe604b12f017d97f4b7b53e9892affec1000abc0dc329bfa66e84173696dc9536060a5f52f2da4729f0453451d010001	\\xcb23dc526429fc1da4057c7a41bc740de4104776d750a82f30750c7794c9eabc1411db5e1c43f970ee7b151e6f5e063d3637c13f5f712bc12d843d967043b50c	1654948588000000	1655553388000000	1718625388000000	1813233388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x2195f71ed3ce2141908eddd1b6e77eff2af9e3321794e233b3f869f246032c8b1839057c7e46ff0fec3d60fba82cb0df17e176659d57297fbcad5040864a7f9b	1	0	\\x0000000100000000008000039c29fa61e902529e53aa8a620629e37913a5521aa9df34c27e6a170df284ac006efcbd1bc9b6167cf159dc5372273c67b30cfee18e03fdce17c299f1c176a61a88a9a387b11823534fec8ce6b17a1fb09a0f60eba06b709c4bdc57f3300e05840064a2180905fdeb252566a0ee8ccbf1465f2a6f774dd7a14c44b03e3ff7878f010001	\\x28eac6c6a581e2e511cb81096ea7a23f85b51b1b2ee3cb69fba87f95317b56e24c0cdaabb3ffbe0f99c98e55ee190f4810453d8fa6ea10c8bd83b0d0c3a74e0c	1653739588000000	1654344388000000	1717416388000000	1812024388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
136	\\x23213752cbc837c72470ab97431d86c232d3b6c651519df01d99d05f333212ad1c5d98fece3ac15298d1808dec5d29a21159bcb4f162cee54b073ebb6e72893f	1	0	\\x000000010000000000800003d192a1f6185869773c22d554438fb82e96108728718d640f6e57485252ba3b516aa48b1046cf65eb9cf8d3220b303da15a03e532a6556207c7346d8525a1b5e7de1814f413d4a6613c1aac4801b80e3981c012c2ba1fea0adb4c8ecafdec2c247f6dc72155eab0ff1c842d4c275ba8d7bec22eea818eaa23d9debc4f0a59b88b010001	\\x4d83954c528b3550a52fb3e1caf09e839a51fdb880f77b1e5d2f654fe3a0f21c9b780e390a608d5700a3331edae73047149f6e206308e762ce14b7593026f40a	1667643088000000	1668247888000000	1731319888000000	1825927888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
137	\\x244d9d0d2ef47b9f34cbc68f934b997726655936de135ac165085b5106184803c7471e19adff8b2ab8ef51ffbbaf18553486d3219c4f21279c486f2e73399b8c	1	0	\\x000000010000000000800003c1e48a2d2f256ff6869ecdf1ee928b67d397623ccd7fdea4bd145b2df111bda1f2f92cab5f5b79e22b7670308f012f988c99ad220486d60d843588144b1be96b21007360b016349aebcfbb060a192afae7d6e78b1b3c91bc979fbe951550fa30b45fd7c7c921640e7bd5430ae4c846c71d522cd7972732bc28763a3db3294dcb010001	\\xa28a26947d4294be6e4f3806b52e15f2fd1800631f4ab038d1023c933736221d692892729debbf3b8cb9d6be1b805a8be633906e213b3f78494822d9d9ae830a	1667643088000000	1668247888000000	1731319888000000	1825927888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x256124968f6d5b1f622ebc6edf65073450fbfe1e62e3ad8301dcc2e28470dc5e8254305256ed797732a1231a404fc8b70a618ce7f85c1e471d5cff64ac43ead4	1	0	\\x000000010000000000800003c66ea6b5947d59c6789168d38940afd0cb27b312f57c2f3e87096976e01ca3fed5f90cb402b6619af34c1671e4cfcd7526b9d38e8f56d4fa313c8c46c1ecef4aa7e6534b328c54066f266d02d717e2cb8ef32a8084a61eaba45f7c8583f03bb7cec5b688491789dd244d97e5034abf1695c7bfe6c5f8119445c26f26a2287dd3010001	\\x56bd911d3039a04a943f61ad0c15bc683265b0ab850cdbb2317b0faa80dd3856c0b1b411f39fc073dfe1cc09cc864d3a8aa36acda7169404ae264d38edaf8006	1662202588000000	1662807388000000	1725879388000000	1820487388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x264566b83a6701de0f3faa46f5f63428a407c18ac31f80fb280f7f516bc5ff870bca444eeaf8cc387a326f881568e197907af45da41eeaa94d8bcd1638db634d	1	0	\\x000000010000000000800003db9078dd8eb99235f8b7bb311429a609b87c27af85dc60208499f0b64f4734e4e07934d3f974f0316818c7b8843706e24e40de21b96745c3898c7081be8d8eb592010fbdb12763038bd370acb130d8a6ed1e08bdd9c9cdfcac39988c9f6b8f85f609732fc52a5e4dc3e4dc20e6d9f38f1312f656433c71415bc942c9476d59ed010001	\\xb42c200dbead7164790bdff8c2392c53a6afffdcc38dad4d5ec2383d0c21bb5a47390fe749242893dff3a7e367b07f35c4c09e82cc390b59b9c9d8754236520d	1659784588000000	1660389388000000	1723461388000000	1818069388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x2655ac2d8fbf02e780606e41da7f775f2ffc107a497a36cab5c264e4f074d6d84b78e3a8e74efbd06ddec34b9790b8b9eda7c2d3b062117fd7c1ebdc5dff2949	1	0	\\x000000010000000000800003b2fb520c0beceded9995631ef7005b96f77826298d2c182b84b2e214b8bfd59f9cd4644f1a30b7548544dd0ba7a59d64792456d5ab2c6f13f084615cdcb70edbdbd2d832358fc8a78e37d8b5cd92c665e94c00fbb5423177c6a86afbc2aaabeef314db947401bcee1530d33ae64b579216e0f9292eadbaa14866205e4641e057010001	\\xc391dac32b41ef5d092a6ae75866df850a0a9bec606db0e659e0efb00ae7545f6fa33d25559ab5c54dc12232eaaf944467b6c50a52f821673a854961c3470e07	1672479088000000	1673083888000000	1736155888000000	1830763888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
141	\\x29bd576ddc6f9f7dc2abd58628350a68b6c483dc79f4c77d7937a57966f2bc149a27796c817c8ba8143f69057d6d1abfd64bfcf5d4c62f725bb49f7f3ad8eb69	1	0	\\x000000010000000000800003ccab65289c565e7a7230b608bc6307a4c0c156ad7bf4d832832de9e5944e6989e4118703bc614f2d91d6d156191a8c51e569ae1928b6999f78fc9dd93245bbfe9ee3f57b2bae8be0bcc05585ea7cb76147c469ae81e4622f36e2070f8ac2fa33c600199b6554ec544762dd7c4f376bc56589d79b9bb7e3917e3778f11769bea5010001	\\xd1c508a3fd365acc1cd0badb8dccc51a403067c0485b7723a70dd41cb93c04e901473d7e71c23f5adcb0beb6476e65c691d397eec7833ff0e2e546e66c849602	1665829588000000	1666434388000000	1729506388000000	1824114388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
142	\\x2ab936e5e9fc518e6ad2e7cba2b9c06e81110f953e0a8623c346be8e4520300577ee1989a6a6ae58be65bf2aced2f1066134f98cc732c654582d218e862ac1d8	1	0	\\x000000010000000000800003f6c5906a70b57691ee6bfb8d61d16355a843a5d26d07b5c0b4c7c51378ebc6c3bb245bc32239c9ccbd0292e38a197e831f4c59b341a479909fcdb692ff67642cbdcb368ec20a03d1b3b6fe597842e58b6d99b7283b123cd8cdf02e00a7e688b4ac5268cd3dec2b8221e9e02f360cd83080911901b2c8c1795c97da90cad45419010001	\\x32a69626cba5a361081160fbc89b9fa8521e6b1948acbe070a22f08b66c4e44e4bb73ca12bdf05505de994dd40438fcdbb46fffdb8db62c4ec09f3d355bcc10b	1676106088000000	1676710888000000	1739782888000000	1834390888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
143	\\x2b29b763b62c8da885082f35c356d4300865a843f0e4bf9f8952f33840e77efae2226ea50260648d6d4b36780e760adb7b1fbca87e30f5d4dbbae5298c6336bd	1	0	\\x000000010000000000800003e430a2fbc5a31b8040f9fadd3723ead931a8715da2b6294e628031d7580a4a301b0bafc90c0f184f00b7d362c2032c7dcbc0036e3dc608a6f0a3123ab75bfec37705173d6d32395b54ae7bd1027ad8c9b32e3e93c03c19e5974cd0f14b05a08ed358266caeaa9765f7754dd7ae1018ff943f40f7872fd4ab99ba353cc97b1e27010001	\\xc5150fff0b167ad086da2928ac9e2452e751cafb15d8cb67168bb78cb91474c711e0c9ab6d977f226e6745eedb4cec9db4f2fdcd7c0905a94465e74853de3d04	1660993588000000	1661598388000000	1724670388000000	1819278388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x2e6db21a80d4605e8b48a3b7f1db434a0274738e94c7187d056a38da9ed38deeea5e9273bf98eaa8051c9ee1ae501873c27d36bbc507fa6d4659b6bd76f093fc	1	0	\\x000000010000000000800003b0bba35f38e8c9d60e4feb0fac158dd0b1f11c981eaf7d4cc76cc818553d9cf64f50e185dc78daa0266095332f9dd5a27b0f6a13640f6f8259fa4ec0b7ac094a86d951d1f8d34527ca931ee4f17609a6658629810dc333fd5fdcece67fc4d37a16e85836e36b94657ad41852bb2a5b886180e373535526a563f5c1b4229e3f4b010001	\\x174834c00967bfd1ee0ce88f960e39e204c4798af6ebc6d86fc05492b6fe4a2d87fb713f14628dd86ad313cab0663f69136913d203cd19cdb4016f82802a420e	1666434088000000	1667038888000000	1730110888000000	1824718888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
145	\\x30f5b59a4460fe444c574056c17f76e4618ff9752fe438fc9a7aa3856aeb816a61aed0b7289198467fe6eeb9e10f37c1866c4e2310255c657c930da8d8ae5e66	1	0	\\x000000010000000000800003b2d726650712f9686e8d6a1e9287ba03f5414c19f92023491167c3ef9d5566cfc37cd1fb3add76aabe85a54f4421a90be80ca3e2849180a2145ce7e904590596afc863ee63c7f178db5037b696b8f8e9a8dfe4588d63229ee7e98c9b066b8e50b82687d59085074eb413808ef9c26c408b6060275193a403e88bc44ac40b1d73010001	\\x423b9cc819a8f0201b7d3cdb1ea35fdf4c11d953bca0a263ad845b1c9348235772e632c8d063f1734194dc22dc6b6d28e4f51142a17427c671a0628751a7b809	1647694588000000	1648299388000000	1711371388000000	1805979388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
146	\\x316544d612ebcd1c51736bf33a45e11f1f990ebe729eab8d53d802cd594a101629c65b372d079f6004755a57c4dfa2cdbd3371d5c718971fe1365a38fd26100c	1	0	\\x000000010000000000800003da776761db64d590b24216f91f603fae0be89d9aba8e9cafec69b470d601f6cfb6047e57926edd52a33232179b651443c05e03eed74a332219f1fe1ad8b21da9079d272450b6fdb2441f3569f157b772a99a677e14e3a42967c5a6ccf542baec557dc2d471fa3fbb3c5c545e65670f60db70c678798a53b70eb3a7f40df254e5010001	\\xfc015a9146b6873e7b628754ac6c511b9bf311c475e6009ba9e5c8c43f3d70c665466c94bbc55d130cb86d7d68efe49afbcdc4bfb0d18e217a3830a7eacb2804	1674897088000000	1675501888000000	1738573888000000	1833181888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x35ed52b9e45dd369732d4c103bd87c2478ffc069886724be0ee11ec8332d9f7597d22277c4c6947f742f3de03fd41a83f0e6c9b5f88066cc81ce98f8b7938399	1	0	\\x000000010000000000800003e445a8fbdf5370798e6942db27bc9b4b4e9f72b3e8e27193a2f2df99cc3e94a279b22200197a32620dfe8addba6e31aa576e2182d75064f1d9f71c76b303402015a2c7cc3fbf9f04cb239f6f5f8266b55b8c5da622c7fb23035cbfeb5877f142c3b2a38e84dee8e2ff8918c2443c779c1590e8ccf3e13df81f6a592d37116f05010001	\\x76ea8e4f28291bdc91f99092b5e7a373b5d1e8eda1e202c67192428b577f294b14a0b46beb81a70b0623b4cdc415b29afbd75a83583541db383d22308d0e0308	1670665588000000	1671270388000000	1734342388000000	1828950388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x35b58b4e6c814a72915741a18ac1dc726c2014155945b60c5eb24efb63cd3ce1834591178a0b32c5d025257cd3efa2150f46d3db638dd59d87a6f8fa08fe26f2	1	0	\\x000000010000000000800003c5f7ef5a3b3cbf8d2ec564e940cad41b82e4945962708f40b91cb28da95a4916ab13f116c71eefa75de0bb8c65b4b9765bcaeaf3ceaa4ae84e39b9e420cd6d2665c53182293ba11dedafe44b0edcca9ab27a5f4a7c6c0db15d73e1fda407f7463e7b8d5b791d29c83c0d8efaf96c78a90e97bfeee89d50fda3c08df3000fff25010001	\\x15e6c09764a4d07b7fe5cbd1072b1cab71a1daac8c3ad4c1a9bdc1dba25ee06ea95a01372aef230734dfddf92f82147a4930a4dd524c4b012c836c894c0c560e	1668852088000000	1669456888000000	1732528888000000	1827136888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
149	\\x3a593c381236d9724bb5da33748d6a7b84b0d35dea8a222f61a2e7af13ac3532ffbfe4a0c03719828a6e96d91454188a0cc7bec69f74bc2e4a2fb09124da5575	1	0	\\x000000010000000000800003e138ac46cb2a2a9dfc509209656297529a46ad5ddff72ee4bfb72214d2d979aeb32ce80472ba77ba63d6a7388663315cfc2591d8a2f7c45aace437361c8bb371454863f1c0c5fd15d838cb6257e9f92d9b1de7d58a33820589e0bb562418ddfd6dbb8d51ff3727c18d880aa98f117b6d9e55db5bbe4014eae386313a15308291010001	\\x5b70dac0d4beaa1e1227ff5814cd3c79e381a3a993233c3e4aec9eb8f4136f8c2a666ce95c420ad619b336a97b8251b5a13ec7102f22d4f3b888ca7a91cdec0e	1668852088000000	1669456888000000	1732528888000000	1827136888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\x3b45020b2f02e039fb5f62d83c01cbcd130e2f218cf0f972a6e26ed9cb55ac6d97191aec794c2e55e909b9123f1776ae44cafc7ba27a8c5e4fd54a604e7a82fe	1	0	\\x000000010000000000800003abfc8cb164ed647ed2d4a7dabee0625821f6b9c0e173dd1484636988507e25ddd7ea64dc5de7875c79efa81421bf471099d93a6e6764e2620fdac1b421bb19232b2b07f4bab3d4db27305344024a673221fc4ce7b66bd033b64407940dacc1399241015ed380b41ccb9787d3293cfb0b83a8475db4a9ade4f1a130f3fb681f5d010001	\\x9d0cb3fde0f8e129f2dfdc63f72b2c70e19c43a903a61e67047211726574507cf5b55d1473c8b8b82d138094e9596d0d55ac6b1ced57db82dd4e7f0015c8280d	1674897088000000	1675501888000000	1738573888000000	1833181888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
151	\\x3fb97088102d44867cff5bc5273b8cacfab69dd16cc9ebcd022dbaa098baac5d4eb07277e671b07bf1b3cd7d7e67b10ec30b5b734401a112a22e06fd91954a17	1	0	\\x000000010000000000800003c66f702b99d028663e3037e8ba789a7574714a54e014a10c57f802221c396a5fb0beec7b5a1bed207c641627113951d4df206a162b820d752199f792bd796650f42e98c71192141bfd3ee7fa17399c48ddad117bd8e33545a4111db9c5113a4f0c35794328248f7bc072bbc9babd01bc5f9e6f5e4a6f2d383dfc890468a40783010001	\\xdfc9a5b6a7450e14d399bd9122952e0121c74a74730c955645b1a333aaaed08d6522c3856e73974f0d3dd90e534713b9fbfa7d99c85ddbe07b17c796388e1704	1675501588000000	1676106388000000	1739178388000000	1833786388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
152	\\x4ca5c75c2546c112dd1609f05b4d76efab65edcd08bcb4fa3e23cc168f56f7850e76c00fe9ac9d3a9f36bac35f84790c2704f24e4d505e8f4e2b08224ee8c5e1	1	0	\\x000000010000000000800003babeac47f9a4c34d77084da68904793c78a4cf4dc76924499671da058fc13a463bd5f5f849c62ce8ece282a09ae76526202d7a72f4ac80a900d4584aea52b41ad225fa176e33d49a1dd67a078918c1686848cfe90d888710f0a9d5ff1cded35911190455964b3b053d38bdaac1c5b0c05a0883827532edea65ddc9a5832ce8cb010001	\\xb3a0d82197681fd6aa6f072f75f39e148f3423af7747f42e8fc846435502ee0876de382cd6a8da770e40b2dc7ec2347defddc1add8aeec36c2c0583c63e19d04	1652530588000000	1653135388000000	1716207388000000	1810815388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x51f9535efa65659d1bd6baea80e642ec6f2055e66f0357d6f7f9c178a25e8fd41bf941026eb254f46d88efa07b477aada8020c376540a3e581c2f659d4dc31bd	1	0	\\x000000010000000000800003b45a7827c00f93438a29620df09767e4f8e038a5c20834c1a853a2efc43554dd40484493a21c9e2deb54177ed12f68773dd90e42016d5809402465e1f8d85ab1532ec881f123f01b32690ff0b91a2e88682557bcff8c41405901236c5b124831f65e5e5caac0aae2141f8bc94e231a81e99772bba9ab5b1de6964536d83751c3010001	\\x8b6d5c455960d540ca9ab8dcfc0d3d526fbd5f415bc372fda39fd45531878bda69c3ca79dc31032d4a4003a96857ad212671c42da0360fd533f26913512f4e08	1666434088000000	1667038888000000	1730110888000000	1824718888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
154	\\x5245c7f56d8279ed032a0fbecfb237d8e2747426419443b769c2fad7eb425c58c9ea4cda81d008c710207c956bbe02c18b19ec3c4e355ad48d60f0371489c977	1	0	\\x000000010000000000800003c74c11e21982ae015810c796fc90adf705f1d66991ee7319ff3565d96b09fc1fffac304bf24b81a0a1929dcf81908bcae539cc5e35d818de3aeb94f4d738c848dce883f524c26726502e48584bed2491f32b6c4344082d59b2f6e038f8c1047e5add394ecf66f907db63274cdb02d9765c8e13b33973e4a3e515695197cfd023010001	\\x43f2d47787e53741db05effbd8554196d506fdabff03ecca53586cc60b20e0bab11fd0587a9b217b6f7c3c1028b40453e8810c244acbd28d2d48f363e36a1107	1662807088000000	1663411888000000	1726483888000000	1821091888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
155	\\x547d130b6b3528e88d6010b66a3d453262a8794db2d78088768470ec9dc4e3291920a0fe0c8f2440022648ccf562d8f5ca74e63d9432a86d07d7d343124ff42c	1	0	\\x000000010000000000800003c875d959d3208b3b57de68e0a7178af0cac62b2ee544e2e4092ffd04145c9ed8d1f76a827b145891045a718c248acb252515c47702e81f97e4cd43195c332eab1860a4d32f8e6c2493fa35f6fd1ed0164227853408a79a650b08f52b3454fce539ba3b3c4925b93abd953de7c0cd61fb5807ec6c040983f7da45d1173b2ebafb010001	\\xd9ad74e86b85e4feb2d587102efc7b5deb60740d4e1ab0dd4cbbb9de15c76bb5dcd0f1e8bd3d3889edd651badf4c651c4d297cfa6a63dd4c04871e9a3c32aa0f	1678524088000000	1679128888000000	1742200888000000	1836808888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x568d6d5934e6c800e9d467a7f18aeb8ec3c89e393ce40a59a94d14c2611e2122e1961141b7ab5a0fc66487e54fb80fbffeb8ce642ec7c317610342d6765bd184	1	0	\\x000000010000000000800003bad839d56c2ecc44ad3f9663358fd302853469913aa9650c621fc820a25cba42da20cd5140c88265e8704cc19aae33a82de6f8b44f5b5c7f2c6489742e4b97dda06dc703b41af8eca055ba9ba77d21e551fb5f20db9131a08cb9484030e66de427e1c418138f7f21cd02335bb2f65fe29e5b2e1f6988b9adecf8f1e7b186d25f010001	\\xfa49a84dc53f24ec5b5a6e1cf03b942b7e6d15e5e180422a84193ced6895a7c93e5048dea195ca16dda76654b94dc3d1afa205a38d1eb5dfe656ebd5f6482804	1654344088000000	1654948888000000	1718020888000000	1812628888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x5c25fab589711c0324e641e37697b023bab4e5109920e87ecdf3c9b78c279cf514c269d8ec1eb7ac2bbd572a67c1072e84d8538af9a0b8a1d72398e01fb5baff	1	0	\\x0000000100000000008000039ccf424b05fd6b4bbb4c46de420787b450f0542e5c9c801c7a141e7e72893057079ea316f16eefa3f54f1a64b8664443661c8a0a9e7d68180cdfe9ccdd6e3d742a8373e90428317249a97db6d8ac6d8dc8148db5f732d6dcba2caa445c0db533c9077ccc4dc11a67ca321c24de17c45e48af174d426918208ecb97400b91d55b010001	\\x2c30434da0459703e5d38fb4f832e91d9964b168757bcc2212e54b7a863884557d0230573215dbbee4e87c2487dadd7093864af78a0bf7ea711085e9d12a6a0f	1667038588000000	1667643388000000	1730715388000000	1825323388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
158	\\x6115496df1bf5164796e73db3a53cc8b74dfd84dfb9bde49d662625793342ef9072115c19ed1edc8d5965a95d7ab0a00d8dff96dc0cafa618abdf6f495c43a87	1	0	\\x000000010000000000800003c9f352b0b50559ab00925ec05cd1557e833aa449d93041bb18b82eff7c0940044e5845beeb46e7a9e11ca309a1732bcaa9c11a7ff10a34c61aa93cbd31bfc24f9be94cb5597e11283a6657bd62a3dbcc629568322aa0e3bbe96feaeeab092404ed2d0d6e2321344c37ac75d83e56c64ce6dce24c392a0b302ffaa33801f15da9010001	\\xc7cd55cfedeead221a97b60e22dc66b6fc9bd33cc3d2e210273109988cf68a83fdee694c78f1d14e9e8a1e0b181d8f5fdac79be9028e45439f8faf6aed67910e	1674897088000000	1675501888000000	1738573888000000	1833181888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x61999762d2edda892cddf1363a3adbdc997550c082a8b9e31e56334acadb4ed8110e1488c616ab8afb4a254f9a11d4088996a13194fc5e77cb6628e1fd88b3a9	1	0	\\x000000010000000000800003ba65d56ec6236ab828aecdb952d9d0bf8a86b07f51439b0d0a067fde972dff1c19e33bd7522842bda3b7a9d2f7de3e59368d6712ebee2f708ef4e0b4c4151d2fd455db3793be0f8eeec739c45a652266201007145e7106b24829f1f43a01a08b2a37122685b169459354c48b0359b00a2960018d74944ff31add457d61fd3ad3010001	\\x8dfae6e1ba6490a34323922589ecd1961d643aef9ee739ed0abfeffcf8026e3bce71af20962cf3406f5bedc9cdb9917ec844066b523f48042e4609d7a148bf0b	1664620588000000	1665225388000000	1728297388000000	1822905388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
160	\\x63258ed3d81b0656c094dc0bfbb2cbb40984fe5e68ef7caeef12d129bfa5b9a4d6f5852098b4c396969e9766c60eb1f2973de80148a1e7459b5f8a0892ef0563	1	0	\\x000000010000000000800003be7edaf925467719b072a91d5f5afb57cf73a5c1e7bb2fc7da312e94631a6c015120e25d5b69c7102b9cbfd0e4cf77f6407a7acc694a3a35d79c71e1529693d1034664db104860222daadd3eba7648312a9c7eaf574fb6f2e9d07c0bad506b96dd8fa2c8cd475f115609d2d363a9c053aa2c720d7e27ae133551ad6ae2af60e9010001	\\xc423e3c1e9b2589828023d13c5b0a4d306f01ca275e678c93ebb551e82a34a9d41e760823cbbd614d84c1a3700ed5508b2c05f878c5e393946c3e883b65b8c01	1668247588000000	1668852388000000	1731924388000000	1826532388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x682932aec92ed0e32fe7dfa62e738770ab78a6eb5b62f0794b250d599c69d7169b0dd1b7c633d66c6b72c863fc0812e503cc8d32fde85e33a79401e1a2d08d05	1	0	\\x000000010000000000800003b8882eca1ecdf6c30071754bc7681972928e7e983b29f0b39a97f5bb4375d060e5d6e3c4e3f245361a2de9a825a6ed19de28146a183772050b33f73722de73b24f49ab3b2d351db4454046c0676d7056dbebe5f2a05b373d2828381e0700267bec163ab54d04eadd071b896741a19a837b4c979f70959e5946441119e2c1fd8d010001	\\x4f3775a3ba3b38a79b172d76e065f6495d4c3cb6ff43e0b56209d9f854e8aec48861ec31fcfb14b6881db4b2e01c2ab71d3a05fc449804a7e9399c559478000a	1649508088000000	1650112888000000	1713184888000000	1807792888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\x69ada43c1ae19c9dfb9807d075910d917a0e8cfa1cc00ea24f6e78c9441f38e04e14e7727e57f163ef9ec254d3240cd147474535a06655d598e945ae6dad6a8e	1	0	\\x000000010000000000800003aa4c47df5942ea6caed90871c68b1d7dad719f72664e69edb0bdfdae4067e263658fc6dc1f9f92d9611c0768bbf2bf5579555f65e8fece7b93ed10be6b8a77d1a6bfda876a158d3a9abe050855122d5a68f50d5330afe2d216b00a98cd6459f5454b1f13b72550be047c167df685e9eebc501aa1a789a5cf324026c069d275dd010001	\\x0dd60a3c8fe5744befd15426e4270139be06b0e4f318fa95b1383b00911a77c00c3203e5dca0e0cac6e8a9e44457f0210fc53eb00b078e6cd5e5635e8efef207	1659784588000000	1660389388000000	1723461388000000	1818069388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x6b21ba791da1148dca3046f26d42527998359b5d32dc8087a5103f83cd4251dfd24a6e4d89673f7424208cb9e330b3448e610dfdfc3e27623d718158acef5633	1	0	\\x000000010000000000800003ae0de60c04472da9ea42a265c5db90cafdeed09992c97f2a12303e9ed226e878ece76ee6675fefed7ed40c52a5e4f90cc697bcaeb1ba27e803afc9412306f066a31ba275fecf7674983580bb6ffeb7e6e83ddfb60bda029c2b627a1664969c701cdd240ad238d3fa6d742227fd9c53da890bd1c47d644d40476e3d5815eeb481010001	\\x73db82027c92ee18c94abe988da02e7ea97f50d8371e563f2a0179d790e2b96bf318994cb7a0455a2bf575e2780c4b4cf84ff414c29b6ef2123e2218c0769d0f	1663411588000000	1664016388000000	1727088388000000	1821696388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
164	\\x6bfdbc4cea1126c9996726700ba52fbfa3dae275b399021b40d191d8515d3aaf243825275dcba0676aac3ed5623808a052193e2de8de234af7044848c5133e7f	1	0	\\x000000010000000000800003be0b7226cbc71bde8e132af68502e2e0635d4a6c58e4dbce96c77ecaa3832f627f9a7db82c0027a13eda8d928208c4454813a6f1f48b4c69639c342681129e8594368c600ba3931b980264bee9d5fbe20af0be68fcef6dd02ee8cf750d61d7ca6e4c6c872b59110b71c86e61086391dbb4120825703745bc5365881ed87ebd75010001	\\x29f64679e7503fc64a675d0b3282e8177cdcdcfd1f68c0c21ea57b552f1a251865d09f3567423e5c681dde950e3d64b2fd0e7780cb4fa6179e02c376a3d19708	1653739588000000	1654344388000000	1717416388000000	1812024388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
165	\\x74b9b0055ffd085c172ea3ce1c1f50a136d2ddef43f2b9dd851b01fdf10404cca9c92953dc4a86b4e3a2e57ef22e67982458a2cc3d06903712d28c2db84b627e	1	0	\\x000000010000000000800003a79d73bf30d0119ff2d7d23301357e544843eddacd1daf2340a773e2daf4277d2c6f41bad63b94462398463fb0b12a88bc2313fdedae43fff0f739febdef7a99342228a7abde2dabb2f37431a0587e82b9633dad274433a0ebd85da531d62f8c244cf93e14a24e9c557c308659d28cc348b8e386c3573a8fb312f67217072f79010001	\\x4a67a4863297bf8979ca87ac0376ec04e86359b7ba3ba95f9c76a57d043528fe4573de27ec2d3c4e1b20c6d7a9a551397f39d8bf4ca01316dc57d6435f827c0d	1657971088000000	1658575888000000	1721647888000000	1816255888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
166	\\x7d7d533cc06503fed8c8d7ff54e1875314c0476880ac3c740e68a7298fd364ffd40583716e3d1f92a11d48897d2f593813ccfa696faa9f9e45ea1693d7a61784	1	0	\\x000000010000000000800003f193a01958c71b7f35b51527c4452a93387e46c7dc724f3779bd1e4288130bc892acbc5822c8b8728f412538ececb237226e63d8642a2e88ddc33982b4443e9d9dfd4bd4af3c0c8dc18d14c4893c612ee0a035500707084b5422b488618f0f75d54c7aadabe6395249e1df5048c103d5592095c877ecfee7aa968550a2234605010001	\\xf2cffb40bb32e010b63a8532a975ce04dd0983aecc6beae9c760419606768de1044f6c1bcc6363210d2105dc23e935ed39db164375fda358ba7520c33bd09e0e	1651926088000000	1652530888000000	1715602888000000	1810210888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x7f31ce2e3788ed981c3df8f4ae438efbbdc3adb42f990774794ff745dedb5b34fc65054bd3a76e51f890678e8b95ed38334cc30998b58a7c086c44bdaf6396ce	1	0	\\x000000010000000000800003c5e0841944889c6764261ceea4fc716121693f46202da6ebe475f40d4bb8eb9b3f7da9fd8f138116198a3a5fc95d5ddaceabb8418824f2c40f0a9e0446314cbb025b2ab7a04c1f8c8d88fc5b83c28dd3028678b27cd5e9553083ffc7469b30071d103ebb1b2287b1959c50d56feec7f76c435a3385727a9528e827edc15b0f03010001	\\xbd657bb717c9be3c2a8015f28421edef54e398da1bc3aa711a18b9d446010a6e59c515756d031d30886854f5fc4a5154502ce5945b66091526204f60caab790b	1660993588000000	1661598388000000	1724670388000000	1819278388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
168	\\x812d00e89abb09bd2dc76cdcde154ee0a0b72d5a1376f5eb0405a9890ed342d6e4e60e4f300e676c3576caa885090220a94ec0c74cff639ca48625ddce04ceca	1	0	\\x000000010000000000800003c297a746d0876cc6a3a9037bae3218f1b5a5d8d45565057f265ae19b2e84d1831de42456caabebf8afbdfbdfbab22fd41fec423754e5956ae8d2b868bf6ebcdad68350150ff8285c555b8730034c54c254993e7a43c088bab5cceda02c6e0b053d2dd4fb72b0a48ce0238fba7ba74719513ea8b38fb93c6577d709640b36a6cd010001	\\x94b3cb3c5b1dd7db2c636cba527c84841e62cbf2a87034151958767d5cc7d65d99c915436d6391e4f9d14dd59886d4da627a89337e1721d1a9d8727bfe920d0a	1676106088000000	1676710888000000	1739782888000000	1834390888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
169	\\x81fd8c59c60a734dd019da9bc73fbc5ba944723d15fb99afe3894e69877492e56574872997d0e8d5f55163499847ace865eb4ba5ee907d0e2bda9371b60e7186	1	0	\\x000000010000000000800003e35a91fae3a46c5961653dc207c74e05af29b4275159fb231ed49ae4fb8bc40d6983ca90894b824c16b33589ade22319b5caa4ce083a222dc2fa29034c31c406f053c56e3f3ad67a0b4a259993c12eda31e851b7ff5263e6f8514f876535a1141ef348f61638a9b51851dcf5e9b1bf199a2ff060f01ba65a651cef66f1d1827b010001	\\xf7c1c045430a861d09139ef439e8684901923dd97bff1ba09e87027567b366835ad30b17f7d2a10c211a2861be48a3d8a7739b2a567fd0bfa1685c1af8512208	1673083588000000	1673688388000000	1736760388000000	1831368388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
170	\\x88c1b7c7417504f2a864f379e6fb9b32810195667dfc41af03a519cdca75683c1f48e0cb9b99539298b2ac5c0c9a1c5278c6ce83883900e7a61be0bdf957c5aa	1	0	\\x000000010000000000800003b59e2c5d3374ec10c6fd1a98b6d33dd5af385a0a2e946d3d9b46cae06fbed80a1c183230faebf48e7cd0b043996601ca68a17781f2ac68ad1ad6e3b804d952a881b944f57035a7ecec8d97f49fceba70684d0da8fe2df2ee86db8550797dba592e95a458c0fcd2d7fd5460a86f7d0fcdb504f334f7bdaee55251166b0381decb010001	\\x469bdba8969e41d0ae128f388dca2796cb9ffeb906518b6025f179653f6985b2e483d7e3fe522c2d1fc1138f0c5c34d3d01cf642f56dffc72aad2c187d3bd103	1658575588000000	1659180388000000	1722252388000000	1816860388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
171	\\x8d214f9a6b3b0269916537e28c6a4f039c0e8f6c750951877acaea547bc5cdeaeb81996a54712c87c829da731f8bf141bf781ce37bb3dd57d704cbe30476971b	1	0	\\x000000010000000000800003c637e93680046d1e3feef642f5e3830a428e83ec97d586a3367db55cde381778d3669d41cdfb4cc66b56c78140d33eb70d2003706bb04ea1fb3ae9bee78cf1273a99a517d247b81ddce6b56b34847504a77d7ec835f6b1d1bd8ba7084703a2b427828142fe5defa02814add62e9f027249997e1e7284ebdcec941e285904fed1010001	\\x9074d79a2c5f510241cb457656eafd696b1f7ad223ccbd5c710941751835080c799c583b58ca51e059e72834ff37c7ebc3fffcd5479ae5f12b2b281bbfecb708	1653135088000000	1653739888000000	1716811888000000	1811419888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x9711407bb5bf4ed47c5aa18b17aa112abcf76e7b0789120bd51623be71d5ce4a352c95e81236dc80306edd947e3ed46b03d144ea7c25d25aeadc9bbb3e8c1f0d	1	0	\\x000000010000000000800003c49b18ed3ace9a30ec618c7e784d01876e23e5a680402a32bfa527438418300764ed8f9fa85bb1f68ce00053c45372554d13e12cfe628e0f57793b1335b0e41a04ff819c7edf89087f09c715a3f2d7d705993cdf0e10188ae5900757238718c22c6e55918dc59b9c2460018002892472339cd4374b564853b467dbfd8db568b3010001	\\x0f89f00f7780527ef664b284b6aedf56bca38465322116765b56fd237da9ec40824025cca7e64552252327f81c89559f25f69c267ae574c5efc0bd5425fa7d04	1677919588000000	1678524388000000	1741596388000000	1836204388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
173	\\xa779e8bdda63ad3ff42bdc8cde595547ddc4f66210269faf29d2c49cc0a6f272d98899ae855fe844beaf8d225aab914ffc6562d50bff150900ca43a1000c05cd	1	0	\\x000000010000000000800003c06e11347adbee030b0411b7d2f46d21968eac02ab10283a1d20ae517c0eef4089dab0ab06950c181c9082493492997aa001f20227dd8e6747c38dfdca6988545bd8ef21456b8c9ed4835e7c9d2f31a77578012d68798a36f199f40701a188ad113836b2f48bac6dc0fddb3e36ec6452458e2e76e44cbe2c52e9a45f0826b019010001	\\x137816a24222ff6d8cdde7af7544f84ccd011bc6646088174407639930b026fa0c2ac5b8b7aca06c551936ffd4e28338a059179247c477b0f02597c9f4c9f400	1657366588000000	1657971388000000	1721043388000000	1815651388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
174	\\xa79d1d427dbec1a2ba3e457a6e1453e8dc3bc840f7e73bf971eaf562b6a37b5aa2af1730694bdbae33d5cdcfd01cd5b318bad0a24177ced0be0b6cd9301f2f79	1	0	\\x000000010000000000800003d308f0956b68584ecd623400a7d04fa368eaada89d708b77c4ea48ee8708283041d8348cd1c6e693adb0e080c4ecab2ab6c069a20dd5861d377cc93cda8c55e460bf082badeeb301ac691aa604650c1b92cff163a10dcb667c22044dc4d3ff0f7da421995c240720bcfa271c916a3af8c619eb11cbd1b904a6d60acc88e09985010001	\\x0031883ef9b4b0993055fa4ff04c0cfc65071ea1f83ccafe7357914c833c18092212f46e2aae386bdbc38eaf3f43b34a6fa8ff975cd44b9fe4e0c5f730038b0d	1668852088000000	1669456888000000	1732528888000000	1827136888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
175	\\xae31d36fa0e76c6eb0d5971d626aefd0fa091c1b4dcf808da3941686d23f83293cb83eb886d38d17e21933d25887494e1b87c6215adce1086ba76634f54205d0	1	0	\\x000000010000000000800003d872876bd94b4bdfa59797db244a0264f947d143b60a6ab4f75df21e31e89b016abbbad266e6137cdfca33e5f5094d23040e61b6c677be075655f413e14abb43f0ca578b0d2058959cf57d6a00fddd8a7d65e16b70492cd6bbee365b39f5224266f6ebeb16028fe8f4efe7e5201ebe6260bca00a4224bebdb3722f1f19fc888d010001	\\xd4901f0772b36362698f27a1229f0313d6e1baa752403def6d66a649f0631dff5b06ed8f2bdf6d2dce162972ade3cab43c1dc07a03732d996c63344d50721c02	1674292588000000	1674897388000000	1737969388000000	1832577388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
176	\\xb195bd40e51082456409aa1b8a17f9dcf0fd827afe8b2edfd919662f72988f4f74f2bad44b94bf3218d14dc439bd4e00aaf8d3c96ed9b6e9f6cdbb915377e997	1	0	\\x000000010000000000800003977cf573017092c970bec26d2c9bbc5dc2abcfb70d62639c57c7c13a3618ffa1c39d8f27bdf10003c84a46c79135969dce5fbb28ec77d113ad8c09b293640a60b70c878362ca468be02936a70ff9d316db6b3c6bbd616404f54806c56069a0f944bbee3c697c31a578a5b74e2b11e85a1e106796cb15ae7a299d4f561681628d010001	\\x3c83077ee1c6592d74720912a01c2a23cb5f0d6474f0354fd21252bc27c4bd76bd53612c9c9d5a844d53499954c8897f803f795e298442095fdcf3193e40f10a	1654344088000000	1654948888000000	1718020888000000	1812628888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
177	\\xb4b522a60e1e046eeb7be382faf847cc80b1f641b07bf81c9970c0f56ad95b5d1be92ef52e927972be3e0c2c956f4317c1e45e05e48b87af62add692991985ca	1	0	\\x000000010000000000800003c8f7091f081008e3f92c7cef2feabaa5d60ef2621b0e8ac254c1e50c371a83692e1f8b9610c57a73817302d9a517237172d4590a045bee89c745edf07e1ab63bb3b6f7820fe3705637b36837b09ccd7515dca440273a4e79668c133503172578588cb6ccc3aab8f74284b62ad1de6e1d3b21bf8134a906f734acc54e972da1cb010001	\\xc184c05090db016bfbcd88b9f19f299453c545f8dbdef3aa5b702d4d878b3a97d7c53b84e56b0cf6afe62ffe22c61de727a719d06448bc74faa6321345c6050a	1678524088000000	1679128888000000	1742200888000000	1836808888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
178	\\xb52106f49f807e5ddb07cd437a0d869aeb73636c3dbd2d80ac965f82df980dca43f5ec95906e4b33d4706310daabc16bf6f118cb15d5d9b26d737262631e2696	1	0	\\x000000010000000000800003d6ab0b7ed2d2b7b36435e60d8a0c10fbb25abefdc90fd32e153edbf0dae66e1eee07d8b6c29e35f1f7b9b8973846cc30b771a247f4d962bb57664bf6bd34e57f56588a3f4257a80a5add690a2a34b45de80dcea83d046ff03a141584634194351d8cb7dee723924a1a7b04a114a9139e1df6e2b78da9dfbf1149ededf6f8a931010001	\\xdca8683464e871fb316c89024089098f29d354663685703ed3652a322b42ee27df7b359e851dfeb12bfd2a3212c80b4ac23453ef99a0ba5977328793ec672306	1651926088000000	1652530888000000	1715602888000000	1810210888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
179	\\xb7f5a1b50e555c2870f49715ec7ae5b3738a5732892aa33062b6a40b6a6967a6dfe8172e97b12c3e4a152ad7a245e46bab1db7b6873775033da94c9715651b35	1	0	\\x000000010000000000800003b78feb6c75c2225d5c817d43da8a8a3735bf7bd6f8a144efbe6b69e002123deea4b5459561cd9f9042f3feacb237a39c878cf21a329d4f87a087797a070942c32c938fea8ad183de5dd713baf9f6d4fbded086de6e406691e2a59ebc25aaa39c9f5047952a9c8a7a7f135cc82a5fba34cbcba78577400427d693d0af1a51ef91010001	\\x082c568f86942aade7960aa36b6466c9148b043fe19e294bc2c6c323d07b450a54da8cc0b274591b630de9232b611c0e8cf30e06fce3ae4d89b4ccedd99b4a0b	1674292588000000	1674897388000000	1737969388000000	1832577388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
180	\\xb89d94609188c417292345e56703d25f0e59904a87716d139ce1faa0b4d3fabfd31632416a1b7f83f728f7c641e90a9bbcc5abec554fb029873a036974265355	1	0	\\x000000010000000000800003f16c10646568379e18b184f79623b76013feeae4a6434fd221f796505ad649cc560852f4f688559637acb581333851e1180d9457d96158388858bccf220917609002a5ab5e1e480ac01e324c603924026b1e54da247b14004945dcabcc8ea4922fa1195429289b7074f063887fea71733c6799f3ab9f806e1ac942d370e1ea09010001	\\xf992812fbaac7614ff94572facff1f82381be34b14b99f5adb8ea01b12bc9e09b09749f173fa038afb7918ea440aed05c3015c0a7269dfe7477be4507881e709	1677919588000000	1678524388000000	1741596388000000	1836204388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
181	\\xb831d1e4aa4281ddfe9b13f8e7d8dbc1ab856821d34731def4e0aa9d479cf3a856d58502d70d6099e678f0908927cca8055aa6a3abcaa151429181124cba4359	1	0	\\x000000010000000000800003b95ad8451010f558daf8032b951c80d1beadb66888b702f6229c8315e14029bdd9f7beb86ae00a9c513eedc2d50f655831b8f50d5534c6c420d1299eadceb0257d1aa7cedf65a3cdbd452dc3cc1a3f7150baf93afb2923860a247c0f18153580e34cf688e26b6ea242ad36148e7ac1f4069b736d35688b7fa8a3658b2feb770d010001	\\x76c6fe7942fcf3a2dd7d8d17f4eb481a573283f28ef41d6a1b760494d043b4d3d1dfe56cddf397f2b6bfe396081aff9e2fd399366e01774ba2f557d8c5e5a90c	1667643088000000	1668247888000000	1731319888000000	1825927888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
182	\\xba613566357b69f02e5b20ca4cb75050707c28c973f99c5e8a61fe783f47fcabf7c2bcdd8bb0fb04aa4f51a5d591daac9a270e0485316e250920ca59a4f18ff4	1	0	\\x000000010000000000800003bd8fce637209dc66642724599f73a21f106f4a32dc2be51859ccc0aba1b1d8c81a340ddbe1298cd523e4d08fb49b0397592f8d78e6266ebcdd3c4a2fb4eb7ba0c17fd8f326fe77c8c9bf813e7586d99729ab5c959b5ad6b3ab2c26cfce5738320708672934663f27f45d3ca9cd903c9f0e8e5573beee7fb44e9539533ec1bb83010001	\\x077c622d80c3cdf4158718a7b57ce868a609ff47ed0113b71cb3d03b423d1cdfbcdda4a78ef6cad0009dc61f73214fd4921fceed91623b1d04eabf9cc6ec3302	1659180088000000	1659784888000000	1722856888000000	1817464888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
183	\\xbb151db2d246b21de25fd5e01904202c921aeebf2a7061425b9712e872723705e25ae2508478ed98f839351e0c22ff35e6802478b2ff031b66dd6dd8e4eece24	1	0	\\x000000010000000000800003c50dfa70dae08e5158ad3978ebdf7082b38fae582cb99de84dc2ce8e466ca88b0224c1b2acaec73edd0d29cc7a4fc55a83ecd9fc46411a4169b5a48bca15f5b410be79a0bd8ba58443d8750e11a9cadff85d8724b92608e0c724f55701745643c3f16a8c9442d7ff42fd8b4ca0d408569e0f007f8978c2180213fa38659734d5010001	\\x6e6af9597d85088d1e2face136e8a432c9471f2284bce2d6c7547058b9c589614f89a277a9034483de11d2293a8bf502de75e1b72a79c15857cc44b244798604	1674292588000000	1674897388000000	1737969388000000	1832577388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
184	\\xbc291db464d110b0aa6ed00ddc8c30710e5d436c7657b03cea20f6ee6f67d79bc3bb394dd8444e582b16fc88f98afb4e206134219e35a157a41554dfdebaa169	1	0	\\x000000010000000000800003af8334dc52cb2b5d2f5d3beed60fcd02230592e6284e1844db6893476be528da2fb22bfbca8f551f855bd51e0462cace8f699e61d1f36788d8fa9ca134d6884f9f3f841b08c17bda6e977e21be0365a586aa24f372d0325e7499f2d2040ae81f88953d8f04d2085f451ab0afc6b10c5e475936f2e6baf87a4e1e364d091f4189010001	\\x8713d7dc7f8faf1c475f99bd13cfc6eb74091dfe2e01541986bd1906c60aa1376d4497bd6955a9c2838ac7229a4af56ede0ebc77dd4041fc7cd294560e226800	1668852088000000	1669456888000000	1732528888000000	1827136888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xbd01c54c5c5b46a983cd91a59906c34a6b667b817ea3a1f364774f72f5206a779ca140d8b47876cf29bbf3333b14bb0c63507b8b7b52e78d75fd2f89592bcd77	1	0	\\x000000010000000000800003ca3e5976fac2979d73cdcf091c2e94aefdc64954cff96322fa7379a216a38323d2dafa46984cdb8ff73988d93ed3ead77dfb397bc562d801a9e1ffa8c9f710bfef529fdfbf59f76c4af63a9e4f58e3afa25ab078c5656ab28c62fca38f298bd4fec57479dd729b571c5249dc40e123f3e12edeb4acc8839b32da1fd0dd1a52b5010001	\\xafb66b31e938c3a222c7b7fa67e5d31b367240e3351b0e4a512f138aa77611315badec8f5b9133486e69733d81e1bf061823b930c8300fd3fd31ed17a1cab109	1673083588000000	1673688388000000	1736760388000000	1831368388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xc08918002da6016a02367f7dbf1917643fa9d5d751996689981012239fa5dc47812960c8288e7f4d7b6acff56817395b5dc2c5dcbca0b00d5d13caba80968812	1	0	\\x000000010000000000800003a5d11ccb9e1036dec2bf8f1d6542c8c9167e6586193eda159dc55af5cc67c8df5b752598ef831b8a5636985fce2011a8903542ce9c203a910e06aa5083b59b7fe15e770b66b0b9f6b7c0708ca06a08bf459bcdbec2cf53a5f4d6db2079cc4688757bcfa6837b5b466860b7e283f2bc28639fd25bd81a565d698aed529cd2962b010001	\\xb146672bc6ab09b05ce206c60ef991d82b804755c3f22ad9ba2a0ec2f171a90a901c43dc14af29f4bf6cc81c2cd1615b4c74e70214e8682cc7a250341a3e7f0a	1661598088000000	1662202888000000	1725274888000000	1819882888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xc0f57e92902c1bcef44a9bf13adbf26ec514cff70214f454dc1ffaa8d9491a371836210dd266eb8aac2e1825217a4eadd844c7dc1a7045c3d3496fcaab0c500f	1	0	\\x000000010000000000800003b5d9e2b37f600e2b4ea1f4a051dfcd2d086fb80122e390bf7af1eb2a338e1159b50654374100104e8de63ddc8f62a82ad00f2a51533c44da4dba4101f6d24ce882ea7c44b8f6a1638180547a22bc3e3e87ee113461a35edd90ca17c072caca676593e83d1dd8adba1df94cf76a7a367b14f5ddf4924d3a6837111b3ea98d7c53010001	\\xebedf7c29042d1acaa6bbec38b48a7bee00084faef9a2c5bc9a2ad98f90d5ce95bbb783f2d2ecf4c8c2bc5aca9f2146e49353bcc828e8198284f30c0c3eb1e0e	1660993588000000	1661598388000000	1724670388000000	1819278388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
188	\\xc1c5c2ad3622325bd6cf4e45a584de7efa2a8a9b115bcadf9f88fb401a002ba89e888c9048ac7358f4ead39f99fb5dba453fcad61c2ffb78743eb88868891478	1	0	\\x000000010000000000800003a68e2358ac42ae46cf6022b606f6c39cb528186d54892ce2fe8a42d29333d05bb4ef938443ceb434e6b7a73e1bae7e7ece9eb874d00cdb7134f542aed90ac4e10e9915c52d0ba51c71e8422c86b37bd0306d3a5a3dc6a10ed9c7d6675b34ed9a95c2859453f86ca455a909a94ea8515d621c1a59bcbd35f6518c06ce93f16a75010001	\\x1eb5d985e7a21190eed447102bd22febd7f6eb219351001225c305018d9d624cbdc7a147ddaf0d2e7d2b198880664a4287542cae6b48b05fbab2ba0a8b8ed309	1664016088000000	1664620888000000	1727692888000000	1822300888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xc611b26d7f8dd526c405238be0119d392c4aedd30b7275c12e5262bb2de77ca9dd549cfb6a9c8186ba9ecfbd8f8df3eeb8f2eda25c23b5e961b2b0a0e4e51ee4	1	0	\\x000000010000000000800003b93ea45ed7f414d58aa6fa8b804e86e40d6b80393f2b0597dc776d6dde86e82a13a3ac9f06ee9692d14b5b4150430c5e3f3de81450d4b7c974b7c7151f8c934590b536f97d092fa3512b5f531a27cbd632ec6a57ef29f84acdd2e99bda5209f2fd549a87eea5d8ff617854333f2ed6b3c34a745c135626dedaec59652e734129010001	\\x02178587021ac8525573f842068d30fe2095f4fcdbf8f2d20b2c9d3d0af442d578d710ecdf3f8887973638df14a3a5a7dd4c736eb1285048067affa629587f09	1666434088000000	1667038888000000	1730110888000000	1824718888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xc8d1a0aa65a08161a6ac22d6d182d19f34b70e793b3fcc59fc1e8e22eff4ab1c5b4fe28f4c703e922be88570417eb15828978329086f04348587cefa211d8c15	1	0	\\x000000010000000000800003bc35aa69d24883e6d3b8c365fc19b2ae4c1f306a75181dc7ee71581a1a71c741072f6768ef8c0a359017fa459d5aae7f70e77398e7944a9664f6bce4240ce4705aef54b16bb69d06f0475c2f82481a029a0c0f1956a9302af74c8a6635b9a95745b9b6a3036dbbd946165d813c3d980a05421aaf6278c8b65fbccb444c2ace55010001	\\x38f34b19692e36dd985741e3f6a2b1a45c189aa21d8c74834d5878745240f164c9615c3d36df5dd2d54175af08957a5fe1439fba4cf9421017b442454006430c	1654948588000000	1655553388000000	1718625388000000	1813233388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
191	\\xd1edb9e1150e6b8518e58d25fae2b161ffe5ef70f8784ed70527d3b183216c0d1ed020f88d627058957f48ccd347e5be1e39305cfacb04a3224bfda013179aa0	1	0	\\x000000010000000000800003b9c02b3a8311b3cda5f5baf90fcfd0798437d04d9e215e6c42c554a4e4017db4bbc5d3f765d793d78fc95d30619c82026294ac50c2a4dde2d05750a585eab270e713b6b2c6e9bf077ddbf8f54cef25109d539f372517556d7d096fd9614e901513c1828c8cbc85ef0a8e55c5fdcf59d7c7f0852371d0da5d04859be62d25bfe3010001	\\xa7d4c52b776a2f6e0c0b99c59db6b76027bc744a2b165b2b53d75e7a9e8d6f4591c42d770978d8596b1648b1b6e9ecb1cd9abb8381f8d1636b58a6bfbb65130a	1647694588000000	1648299388000000	1711371388000000	1805979388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xd2f99ceba5c1fb1db9c00c5008ff6bd5817f2f2a1bb4cbb84a9080a78c39abaccf5226723ac343ad20ad1e9d002dbf2e91ecd04d6ee30b639b5c1cab0697091a	1	0	\\x000000010000000000800003aa0519c3d697cc60a03eafbc7ef1798f5748334a87a00958fbc06f399ea3fbc13ca138ae6881d6637da86c06bbf290f9b4fe35e6d1ffb8ce612d215274c6c178ee4f0373c1f48a0c0dfe2eb895b3b97598e5e945a5637d60d0a8da7dcc83265ca3b2886e25a8cd48e51b02fd6aaeb5c589e0af99a430862e7abba4df278d8139010001	\\x3c46302bdd05c4d60fb02e82dc6d7ef580c977d084fc01d768e3ff5d44ea030364b9ddf47b5fc02946c51eaa6f1c76063d127ed6172a9324b9d6cea67f6eda08	1656762088000000	1657366888000000	1720438888000000	1815046888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xd3d97beff753194e87d9d05d49139d86ac5314e2585779208acd22521b142b9373ee627f08d8c25597ba2420db5ca25a542b2d9afc0a488fbe1b36ff096d7223	1	0	\\x000000010000000000800003c16ca34d50b55452d6db05e2a1fbb6d74fb18da476c2593dc0c0c58c5394a5e94febf89bd274cf854fcc95be11d3d6916e69bc9a3b40edffc8b9d1d7fa25b10c646724a9f750b7bde8f4022459585cceb775af57fe8ffc1c318fb4ead5b6e03325533421682889ab2c549c6faf90ed4d162d5e8cbc18bd17a350c6b2ce313733010001	\\x123dee8771614f137155231f925cfe857757aee5019187a473c1176f16b7a8a9efad75ff0bede7788a2c8db67123dc19a0137d6564c6410dd46fa1a9d1671a02	1650717088000000	1651321888000000	1714393888000000	1809001888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
194	\\xd63d7f43108f93078bb78a2e09d119efc4795e8614631d3a653738028d459b4f7703546cf2750a457f6f7da09790d3d5a94215cb9cc851c3bde72cc62deb497b	1	0	\\x000000010000000000800003cb22ab5b0bc6ee85f9ff294045a6b3fe2f0ccd7d2364cf4e7e9176f19787e6d598d66db181af961c7b55ffdb29eadd624fa11fbce00e96c3859c5c4fff22f1ae429e0b56866709fa9a215583a2099526cdc8be04ac963dd27bd7e7a7d39385bb44e7663f0ca2303ec5c1cf97a0aad1649ab68b6f85388624b132db5d7f55bb3b010001	\\x33ebdd718615df1f053871e1385726fe44026b1c9bcf5275c6005327e769675a5b1590890726885d8c1e70da91c998a0bca5237a943b98d83cf10683bc60f409	1663411588000000	1664016388000000	1727088388000000	1821696388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xdeb9be628e48d90d85074e4d1148b01c868b4876a394daac953adb97d408e6fa42769472562122cb6d4f790bc27f80fe2ccb0ef39d19371a6bc7a9d87d30804b	1	0	\\x000000010000000000800003dfe19cbe489fca435527824482bf6108cefc6a04ade2944cec9631e522da45103d78096869db37b978346a2e68cef11054205b44c4c41144fe1d61836a94d476eb3dae46894d90e76abf6df4305bd230e5411eb88761a1c61a422eca33512418558efece5d23738056034c274bc3449d31804b8a40b35e3b21712877969178e3010001	\\xa6365e745e8650ece7a6fc81f2a1602e28b394b06fa0aa8ba239f4a3fdf5638ed01195d87c322b9beec70515600dce0cab693e0d4c7108b29d0d1be6f21b0f04	1668247588000000	1668852388000000	1731924388000000	1826532388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xe005a39bcfb802f8bc7e8d51ad60fe1b49e9abe79d352698d981f17d940986d912771e30cf9b6ca8359daa41b0f416c89cfa8c3dc331a83d7705a009b63a1f4a	1	0	\\x000000010000000000800003c9ba426133522e3543c4748561b83bd620a477835f1990c2b9c3debb27d25d9bdca53d9ae27867b04ed58a60e5609c358c9c16ed277d8f096ea9e5b12dd80019061481f1034877878323508ba8ee4ca2dae572f3cab9e6a8b28bbe2a1460316351f763562018e957308cf84403edaa8c6c2286ed9fa9ec9a3fc0965e307e4b83010001	\\x4aa1439cdece6c5020fc03bc021b52b881c7fb263e6a38d11618794d1f204ecbb908f0a2ef09ce3aca28af26427df977a4044b705ca27956892e295c342c340e	1662202588000000	1662807388000000	1725879388000000	1820487388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xe2d5af268c620fa14169b9fa601a32f289aea7e16f3007174e6e4e5aec640dde05a5fde5729f28b9dbbeee4c4e3e73db07f6b1f40d155a1f6355cc480431cea6	1	0	\\x000000010000000000800003b2f1cc96be1e046691f9387ea58ef3bbb2cfec3aea5b15ae11fb326dc0e60c8d171956d9131d424d59bb8175cc1d71cc825c208a766746c9cc6e8b44bcd223c2a379ec845a29548026d4e77b2d90a241900630d8ba3230c4d260736c38147096bc55e22ea3d6585d96f2f53855855c288ab898020bd9530ce9580f35875e8b65010001	\\xb115e5239b1a3b383dd9a3df2593f0423efe4b2b18d0a5f12cc40c07e4823746ea7134290f74ed13e887b8855f65634ed70e988d9ade364aefc63e636688df06	1654344088000000	1654948888000000	1718020888000000	1812628888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xe5310c2c0a8ae25dd0ee910dd5586ecb88b0673d5bd213b83a6c2744cdcaabbdc456851978cdda8c808af5bb9b53df4360c39be7659e0cf9f7b4a77641632491	1	0	\\x000000010000000000800003dbd302de94bb72fea5a4d455c2721274b09824362bcacdf57f83a4c364b9a5a4c7bc5032a9ef859bf12b776b472ec67b5db8f86e9dc7cb218850e3e8d11294f49535b10de27d7839c5f3e28a2f1356f9fb0af3503e43d1b7359844caf6f6b26aa09bfd155874db5a8c5f7abd0a4adbabb3c4f9b48d202bf56f21c4941df06015010001	\\xa3720de3aefd03f310386109669035d9be6e4d74cff9f3d3b5cfd65ae95315d59db07e66e64d676dcd97d8a32c9c2c1e545b7432154117714ee70b0df7f8650f	1657971088000000	1658575888000000	1721647888000000	1816255888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xe58d6a5e6bc25e093010a1f6ce10250a7dff8a89cf99d2377de9d2d6aa94723d381421a6528755f8a9db65fd1d3fd0c8d9fb0e46cbc53cce9dc9704c57484212	1	0	\\x000000010000000000800003f5d24b5c107afa3759ca2e2d7c1be42859651e57569b5daf40f47e78489276b3319554ccdd24428e7f3cfd212789c6e244d38e8251a02e873cb7e58b318850335bc8eb0ad33d0becf8e010bedfb6ea987c637542d186da99fd8699e65ed6af358122ec198fbe52acbc20015d52ac2781f02ec6b8b83f24e15d5ac8d19e03f585010001	\\x26314665acc288082b424608b3af0f1846a9de8f907e05d44f8685a843265560004f111bc2b1ea1d60fbce3309a038baf39e30ecd89732e77390003fc3de6e08	1661598088000000	1662202888000000	1725274888000000	1819882888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
200	\\xea01ddaa5603c72c7ed90f6a35dca0420fb994e771279d6895b40ca83b76d3b3930b4d47871b2be215fd188219971c032835a779f79da6e4394bb2ced64bc446	1	0	\\x000000010000000000800003fdf30cfec41fb5f0fe0803f2bdd6a2cd3fdff7c038e943e5afc412f3f461961d7700b660073839258a8e5285f9d592f4af2dd6b7e7e074c3ace2da9fe92933b2f660a798de1b2ab9d7cb89d84a3dd5077843ea5994714e3e60b5e59d816e742812d889e01e484e8fe37e4d5c20c108f66554fef4dce1d287d2bcd832b2d0590d010001	\\x13a10b76216632c94b4b89e072e7cd8e3d6c666c7f0206e82cecd87b6e7895c6f3a95cac901b2bc0fc313964e42c083867d798334f9431a31056647211526106	1653739588000000	1654344388000000	1717416388000000	1812024388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xed71c7b2722c4965fe5a037dddbc848a0718bc6d0da4ca185215610686bcee57871d2ef7c97e9e4d72a60cb35625bd6692783326f0243e4cc39d5624b493f32c	1	0	\\x000000010000000000800003c208d53bf3c7b66df4235b18ef71bbf2a5c6ab23dfc630991c24eeae364661a6acecb3bf826d96bc8e5cf67c309b05a83e04eda34abf324f77d8c7178e9cef13dd67e451f31efe048bc8c83ef4248562472b9f1637123a2f39cf712a735bede6cf4af8bc4691044fb8eaf62cdbef9611ff116ce6ac7c1186fb63db7a763485c7010001	\\x73775b58ccdcc75b18965b98cdf6ba4d7a52722871cad36c3125aa14854ecd7e22fe26bbc7d28780c101a2330346522f951b772c1939c00cd5018d9f941e3107	1670665588000000	1671270388000000	1734342388000000	1828950388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xee4591f3509738019e2570ae7ad8dd92f6b8da79774cc8dcff4e638e846809b7c09d5763ce6c5c91cc2fad7c9e45dd217ac1db89b87337bb169dd5c74569bfbc	1	0	\\x000000010000000000800003bfb095ab7b8769ece303fbc8a8e962bd9253edcc08e7acfa76253a5f6ef89443eb4054d4f17b46eba88142bd576e7539056ff90a5cc1a18b18d1b8726852c0b5c11d48da971454b8ad596478281b547784c7c1773a2292751708eeda1b1ea72b1de13bb8be64f0a1a7a58c0da1963775e3ebc689212ad64dc2d82a578ccca6eb010001	\\xc57c0cf81fa5fa4653fff5b9664c21f144f138a08e17a9b93f7d2cd9fc33311e83094e9f47b822f09cdb104a284c9871d9820a11d6c06c7648b125233f00fb07	1673688088000000	1674292888000000	1737364888000000	1831972888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xee5d454123b77cd9d3c03b5b7aebbeeeb43eac06957c7e8fbb17a25bda01825beb39af53de301bb04235630c060541462d7ddaa16407e408d8982392e7ccd158	1	0	\\x000000010000000000800003bd9661a1eec6ea4c1d1d2ea49c3e5b4c4f5e3e2f81db6556ca219aca2c8ca6a4dfa7a31ed37b7c037f254fc5da5edeabdc0b453b6c49b3c6d8d96e24f6ecb0ec84509ed7780dacbdf92e7be161efa42f28fbc4f8a03ba46d8e92c726edbd869f0a06093b380402a99c7a6c7c9efb584de7b8adc4765078c5b4fe2154a4e707eb010001	\\x71c8efe8d6d035931195307332343314e114a22fd11c00a15d81de266a0fb307e23bd00104bbb2cb32f6feb22596e3aef7f9f4f8cdbda22193f80b83d1fb2e07	1674897088000000	1675501888000000	1738573888000000	1833181888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
204	\\xf171f162c2a3390a2d15771ae09cc85bf6036d41917c0411f4c0a123d6761cfde9190c6fce5040139434b90da35da582f8c52e288deebc709802912ff8d1a099	1	0	\\x000000010000000000800003bd338866610bec459330e9bbd48c35279286cbf1809b1b7571a08353f700bf15014410af47bae41d25d849e799dd9eaf486eb8e8f0df13ef178e4f52168b0c8b8ce791f5f05aca2578f1527228cc94f6385174f4bf3e289b01996439c5ea04101fb5bf6a26130d7d905673e63288d7a4d1c00f1c17c9c4bab249c76da985f211010001	\\x32e25ed63ea7b4ffd923b6ac9acc327019f7b298bbbfbb2502c3ef56e8b695e01ec72427b1040c57487a6a4d53573620d8362b8e26704d0a9b29e7ecb0b60f00	1668852088000000	1669456888000000	1732528888000000	1827136888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
205	\\xf50d6a8259f528e33158caff64c8b55647639866916ac27497ca17a6cf8623d642f17247846154b2f185da8849544a43c3222d44628aea305fc525240996fdc2	1	0	\\x000000010000000000800003d9785c4c83fc0befcdc7deade1c0f2892d481f69469b48abd51ae34e68d6d02ff11cc07879b21a9316aa0acbfeb17f8cf9e7df3a2aae829b139cfa42db179da844ce2d3a4bdce46aa7c6db3684b69626633c70f718dadb23c997f79918816ba31757c07d8e0dcc31ab0c665452f2e893a09a2c3471f710bcd55e0a4796c93bf1010001	\\xc897d32c2c46c0b6dd78b8c0276183f6544c50c608376311b5e66a2d453ca095ef79ef0fd4f8f555cfd0caf6f3038077fc271ee915806cf38eb1bffd3cfe7b05	1654948588000000	1655553388000000	1718625388000000	1813233388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
206	\\xf69d82ef1ac8743de3ef2e190afbf61c0dbaf0e77ee6d2648ec66651fb4acf5570ec239fb802340e1e0bcea1333e2fdc4c17a975ebb7b4dada444733a209f56e	1	0	\\x000000010000000000800003c38586d0f6cd3108d37bc1a4748c393294b363c743f90bf2eb573793c3346af5aa662bb4ed54cf57c628f2ba679d3d8026b9bfe5dfc6ceb61b04b2193137ebc6671709db4767b1fea324dc8125539f0c168b056a5d439adf80ffb303ec9a813fc266a1900e209d67cd52a19515f07437459c9c1f83b424735f114586ce000165010001	\\x30f932b56bb5798d028fe258685957c095633088726838541a48b6b830278fd0067ce19ee9ef81b3005a9c25190586deac10c60ebc978d5ba5f5b1f1d4958c02	1671270088000000	1671874888000000	1734946888000000	1829554888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
207	\\xf71572dac32993165ffdb1b85396910f7bf1b0ded39e2eaab7ae6d2727bb9a7998559b688bd6ef988ebf37e97d6faaeb121a27a1aec443e8c40d698219adf349	1	0	\\x000000010000000000800003aeebc8104f2c7f0cfb4008d75c1d63136f93d565869f7def4916ef98ebaae0c5d631db89e530fc717d8bd7b547476eb2d244ccc2557d971053d197f9101105b5090d794297ae4a7d31ce3a34673cd4a3db4f3dd074e723cfb397fe6db548d815dc369b5b814ce92ce756754364cf2e500a94b211f888c35f843662f718d0cd15010001	\\x66fd55e726d19fda7aa2ae63b1760e87b58da4641402bc101090d3d78a91d7a8887a0d79163fa4a6ba485d1c1a18283b68e2a8e9a3a827e7e62c27356b49fb06	1671874588000000	1672479388000000	1735551388000000	1830159388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\xfeb1abd5a74af7e7bc94d9ed46f3c8574836c91da1c596513485fa7c868d259b20eee40c77e329b29b6f1959d7afbca15e296aba244b6b1942f90497e9872768	1	0	\\x000000010000000000800003b995f7c3104bbbe2e1f7de49132e624062c3daf3b3bfff30c54a7b0c0c1a4bf8d7a6297a7c17e9fb31f0e7100e4aaeb68c892eeed308e9cd5b97e5a1539c2651d91e92718c9e011c339ab29132d128a0eaa82a66f959f3d96b51aa587a21163ba49d20d07d5b10c719bf01bf3f638c6a01eb5a51124d54a723b8588981c3c757010001	\\xda26ecd9152ad5821ae1245e973dcf58e7504c6098eeeffaf5498b177390896d527bcd19ec11cc8402f9fc0d438dbe27ede7949f72d615b9d13eca7963432607	1659784588000000	1660389388000000	1723461388000000	1818069388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
209	\\xfefd7a957ab16faf6af113e36a7cf2d6b7936d60886428501168146beb41e3dcc985f024a055d16f20996abe21dd1ece94648107bd52b5c3002c3a18feea247b	1	0	\\x000000010000000000800003bee91dc433cb408dcd01838a6f144d32ae81a568cafe18b3514d08c6f9534edf3fdbd5cfc8ee5f1e0f893af18016363597870e79ef8d202e75c8c8fb42eadb585c78da00a54a427e09ecd703492f244d1efce303ed67b1fbb3cfddba8d5582d068caa4a6d07d4d848b5ea0d1a6ef278709dfcf484a4775c9a4f94b84cdf404f9010001	\\x5dfd7f030c1a1fae17a4c1281d09d7505d32412f233f5cafec190cd8770f11529dd04f8fac6260b0dd1b5bba06f037ed16898305d948613367ed4fbe5442320d	1653739588000000	1654344388000000	1717416388000000	1812024388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
210	\\xfff195d35311d5c32d0ce0751dae84f6706d76b28a88338ccbd488f1e9401189e99c30b3a730f1bed7ecd3a06f8c375c30c287cde3f8c53ec157707671de2c12	1	0	\\x000000010000000000800003daee857eaab966ad564bfe07ef3b0e844ceabdd3403c51a7b7c93a084df3b5c3f8fe520d57b4c850a3834f274a92a4d9b228bb54c44152f6ab116f9dad99f450497eba9308a81fd06a9a77d5eb7a96f00be48f16482d2f3430f7feaec8e52687934c435fd7a1d338c3c5b5e9bcae8127b900272f48ee9517e752a49d1f4409df010001	\\xb37dc4e782a381a3a9f9ebddcf1747094c12ab1d11f0b90946dfcfdb483dfc3ff541715d4f3a96232f00e8d30b00048a513975b0af3a271538bbd959e3afae0c	1657971088000000	1658575888000000	1721647888000000	1816255888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
211	\\x0506b104cd671253abe9cce54fc44d06c9c0a85ec75d67a718cb93907ec415452410721726a55ab2981cecaac21b481dbdb2505af13f7ac48bf6aa61e8c37318	1	0	\\x000000010000000000800003c79f9ddd43da5ad17118085534b1b524bc47625e5e9afaa0c26de04e5cb201fde5534252735a622c7b6748c611d4936d2048f0b347f83de47273e6ae08b7a8e4503375b6b35af7cdba3a85e810bbd26623abd9079144d82776ddf63dcd8fc8c9c92bcb76e6dcafe6077de25fbac4aece7e40d0b15a0fc00744d3bbf098995959010001	\\x222b197d4796fa0cd266698e510f6fe9b4e1d8971e3a610cf185dc24f263a1660b28c30e0f0270a84aa9c6a706832a10b7deedfcb222dd4bbd6278c6efda160f	1671874588000000	1672479388000000	1735551388000000	1830159388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
212	\\x0a629eff2449cc6abbee4f330316992aa48e8a3e084b6615ea6d2fcf2e214e270163c39bb6a88ef0bfe04c29c5d9ed186470f73eccf81358c4dbb7e753c7ca93	1	0	\\x000000010000000000800003c59821fe431a0c0fa3bbffdf26c15e12598121ae9feba5a7130f29a5d9432b575b657f65d47b735dddc812d1bbff9861f38f526406055c19a70c8dac95651ade66832da7820023dba5cf8295949a4bff20db1509b176baf9b63d90cb13906d39c3e3041eab99e05fe68f6a0ee14234b0003cd01bd9f29c76c3ddadfde91c0a6b010001	\\xac873d2b62682be65b50929aff0fbef59d525d76f07ba3db84a00590ee3c64282c072e29ff6d02cc30f4396c92a21aa4c2d41b44427b78cda689e505cbcfb006	1665829588000000	1666434388000000	1729506388000000	1824114388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
213	\\x0b66a2381d5c736bc37e3fed693b49b4f0bcce7c7963185d7009b13385f46ab3a425d96bf10cf721423bc53eb9167233325a2799df76391356c548755d0b431a	1	0	\\x000000010000000000800003c873e92531125bfb55406029fb4d593454a7fd234864a9394b902faa636d0ae6bf92b2dd2dff3b47152bd220e5655c7e175a376036d24f1e9b42c177c5174a9bc089c6f8cfebd9fb91d83c8f630a598aa3acfe0be7cbe749710100ec5221ea9a2f4af816980ebfb016d4cb48c4b038e45319cddb36a1754257e8c6cbef0d1e15010001	\\xe78bfffd39d8c2e6b120a12b5553d9ab7c5ed084d0130d00ab3a2500ed0b99d80bde43b5f6bc783bb834e7338f42d0c5177eafc73bfb9a329ba81690b8bfc90b	1673083588000000	1673688388000000	1736760388000000	1831368388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\x0b1e3efb80e2a096472b7dcda21e9af9522d1c92fb6c2e70344fffdce4202f441fa336f2d470162fa808b60a9dc5ab83d480309a6b27378955ddad3a26aa8864	1	0	\\x000000010000000000800003e751613a9bdbdd48ce6423da96614235445a865bd3f45657a43f026cf3b4267e6f5b618447bdb1286a919f082a6cbeb5fb662d2642b02534976789d5f699e28c86d888df5ca6ae406ee78ebaf86015be5f3a8807eab05ddc2ec0151629bf2e92452d112298bfce5962e65cadb1ede5403707a991b2a1425f757a194fffdd0027010001	\\xf2a8e9c02de7379950dcd31fc0b154409427191b518381a6d9c5fb4c2b94e75ba310d5dccd60228b9811f093d38a2f0bd1f5a20ce876d6254ff69391dad4b807	1662807088000000	1663411888000000	1726483888000000	1821091888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
215	\\x14860e16d47889f559c08688ec06c1e4c96a6b8d782ee733e6f42cbeaf05fa8d0cdaaa6dd944bfc47a556fa7d0ac6dea7c7fc41a53da18b32637853b0fed0a6c	1	0	\\x000000010000000000800003cba45961b4abb65120b88c9b07187607d7ba74cec7eb95f86f8b4ebd3346c0decc2892e26b128900488ca0d1397b3087e7e2041305408c95c917b44b954a03fa9194c4e3178f2f13b579662e6b9e90862f8f58200e4285d4dfd944ad32e433dd69b50b043ad7bdd280445d6603af6e841657bd9c6582277be7937e34eadaf9c1010001	\\x0bd1b5fa3b46401411489d982c313d28e32352c76b4e359db921dfb309c86b4ef8c0ea27277276164fde78f4ee0552c8b182713ebec65d638e213db25c8aaa09	1648299088000000	1648903888000000	1711975888000000	1806583888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x14fa85dd007f94cd11d8297ea9d2cbf8e00e2edd1dac79a19264424cdaf7369a3529537e1e0be4af575e76b72acfe256e506144bd710c638b6fa1fb96891bdf9	1	0	\\x000000010000000000800003c0dce4e373152e6c88690dfcc03234364d8df9d0b6c8cdcc5c3f98a7f5b63281861b2f9f221e4afb031656440406527f288bb9a628cadd05d1e241b9da51f7274e9394f9f7e8ac063cb43e61a111c53bbc4140f7b58a8fcadeca2e35092f8875e5eaa908ca94f9df618d4b2e0dea872b089487c3546460ea0c9e29feba3dfa31010001	\\xf05c7fd4a342d07ff331005e3d431c0a0a9371c833d989647c1af9d050ae942f6038a32d44d4e134a06774f387d4dbc6a5ee83b3332d009313e157093b760b0b	1651926088000000	1652530888000000	1715602888000000	1810210888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x1b929a0cf3cb05a7940f4d99fb430126db5c90cce05226ab483e15137535953d45141457ca8f02d961619c59a6df546501725d4efd35e7b50dca29e45d0bb8d5	1	0	\\x000000010000000000800003bf591c9b50c86f0fcb189ec90c24af8d625aa1c17ea3f086366e29a43ed103ea0531d1f325d826c2c149b0dc422ccc4fda94270049f7c2ac2922f1b43a0de8b0a6dda64f0193db4e04e1f416c6aa4da5d86e494a0ec361ca4c9a94e8135d95c99fe63e7478df61c86cfb843ce02a5b4b6ae5f45c642158d42f8978e237ae95bd010001	\\x8e325bf1781d813deccab3badf855fb0c81fc4db44ad0684f255f3d12dcf2741b959b225952976bdc80abc9bcdfa94b14740bfead1c5f65fd0313a288d952d0f	1665225088000000	1665829888000000	1728901888000000	1823509888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x1dbaaaa7706b8f1fc9869d21df415a0d0daffca16fd0fdce0d42475319e21207e4dd8e70c9e7fef0c9f5271763e5bff0f8080db06e78a6400e11f15dc17e0c01	1	0	\\x000000010000000000800003c65f4c2b9531eec32b090e9804397baec1cb913a08e44280d062afc7fa6620c59b0325a94f80e94c9120a17238a792d90f55db2e896c91da65913215e4c7d54a8ca9f340feeba5147c62fcff8c59168a360ead921ddbff817c647666a8d4a58b41db2ef044c73e1d2a742dd46131c86a24917b5b3daaf4e3391d9a3998422bd7010001	\\x964641dbe495d76cccc7784d0e2466d368e0cd860a1f38387c24fe3c7dae17c5f63fbc4f30fa55cf8a3788c16d5a6578e9ff4047efa8ac04211c5dadf1df3706	1659784588000000	1660389388000000	1723461388000000	1818069388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
219	\\x22fe3c239ebde8d8de7613b8b92649aa2c9d07ff31fa06497a36311fe0c237a90570e5af06d81d3a94b17249b2bd870f4ad1b74b50fc7b54196bf6436b713d7f	1	0	\\x000000010000000000800003ee6804ba78bf84a088fb07e1b21ac9018effa8024d62e9bf087b363e9f1c34a148ce35e8efb1b77baf2d929399bb42bab309c15ed4943e9a0f69c255871ffb506b280f23cd8fedad67b53e16710b08517bb6bfafeaffd966805e35ca762f1e6110e27de65e3b2a8efa3dabd5e5d4b4e39dcf712d0e38c378e32a1bee9d7be44d010001	\\xf1beaae59165cc1c65a21f6fffaf502aaee5de8c19bbe3de3a441265ac20b288854481e90e40f9c90cb6fddff48d75bdfdffeab05f7c0f6800263fb7f7a9480a	1649508088000000	1650112888000000	1713184888000000	1807792888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
220	\\x2366b9dbca7313a1fdfc8b997628dbe7a3d230af00237ef56568c2af75c897d9a1368960253cbb371b5d482ab1128faee1312ffbb1926e8ef99823d78b3c52c3	1	0	\\x000000010000000000800003abbc2b1adbc5097d3ba2803170cdf65b22aa5bdbf58c4d15f4bd3b8a7c35b1b690f59716d4e57be484ee2cf73819fcc19c137ed35fa66ebad6ed9759f9ca5ccb4e27aa1ec8d7d30f29dc354dbb3d3fbeb87c07024f047267c1f7a17e06341ec7f60cf3f476d981e016344de78a95b58e39b5e1703c81d61a0d698e34bc6dbc5f010001	\\x0a3bf54e791af55594b8ccb2010af62ed2ac53268783f8341710770d98085ffe86d6332b4142406010b629e4d9bd75c8fd7df519388d0accd453bef866286805	1657366588000000	1657971388000000	1721043388000000	1815651388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
221	\\x243af771ff6fa127d502f17cf856bb8387ce6cbacc5b3b1863a74a2bfde80499c72f2d7d0ead9299d4ffb0e5121fe48c3559a224798dad84930ba85692812773	1	0	\\x000000010000000000800003d5a062610580c9c45a8be0d82b59416086fac55a65b2eb8bc72c1cc54a8ca1f1c0d931c9d23a73b10583faa39f349039322fc2b146bcf1d0498d1e6ab96ca4454a0432483c71ae2aed51e5f7841d86fb75daaa24830ad696e664d70612654d9d6aa70cf83262c1e556f75a13faf2bb19bb32bfc9ce67ae151a3af72e6197d243010001	\\x5cf382ff128577830fb769db1ddf383d5368b0a323835b5591f1cd36b99120c4d1bcb3ad4e3f3a276d05496bf685303a2f46eb53b72ef282189b2cbaa8cebf0a	1672479088000000	1673083888000000	1736155888000000	1830763888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
222	\\x258201f0a60176a6125106f62e5d21aa6fa84c8372b512a74a19104333a4e1ecd9514d88b6fe3898a54a87544da3ded447af7de2e374a01f58ad99d52a39400a	1	0	\\x000000010000000000800003be4aaa60660da59d89c34ccf22d045ad7c279f899570a056f7b3e234c1fc66e625cde9db2a7d5f2ffa76659df143c1c99274374808363fcdad1129ea6804cff380757f451baf612a711c31247d1577fc696d462a492a9a2a819677543740c932e6a103291b6eb14e75773badbdcfd90fa3ef31f5adc106293094e0ea2bbbd63d010001	\\x1d3d01d9082790e1881388fa1d4888af815ed91688858dbba93975219e0fe6c6ba0c9dc4a6386addf69be8ce0c37e2635aadb968864a39652ccfe664b7556706	1658575588000000	1659180388000000	1722252388000000	1816860388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x26e27291f4e4ac5ba275bfda7b2c4e44d339949c03049eca20376ba16d39641290430822581060a62725283ce2d2be80f68f9aa8fe05c6489eb6e97d8fee9212	1	0	\\x000000010000000000800003ddbe84f54103342440c239f7f8776bdc2a089f22ae1255a1ed60e6cee864a40481910846263589d0ff4852f36980656c3e85fd148e695d2dfbfadf745b6829eb381d8f7e443bce08b4ce425a3a3e35a0d9f0704f84be70f1eecdeaed894c251cc0b42611283d4f94a34e2f99c0ab7cae812aca8c4e52b72988c18b44020bb487010001	\\x6b1a4a2a9cd8b4a9909fb3bca87a8ca404fc666dd01a2a1a446125c022b23d73ceb226147fd4d98e889173651a058c6cae91c5b2c5105df4702d676e4fa0050d	1666434088000000	1667038888000000	1730110888000000	1824718888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x27763b5d40ead89f5a70d34bc02d4a914b5a82a882f164a7a70e947054b1b4c544513745ec2e4013efa829bfa2c4cb7a5d5d3ab0a61dc78a5db5669dcc10075c	1	0	\\x000000010000000000800003ce907295371d1f482258b1b829f21a2585111fa2d59280403b44de57b36feb467d11adf13fe1162b64abf6cb2ffa0712ba0b477968eeb433c9299826c2ec98c2d05bd06f1dce498f56bfb64b43d2c5bdd9d8bbbd7806a55f58ac6ed6284cbe9850ec524741d976ce8fc4336819241b5bd881ca70580cfe761db9cf0ddd248a39010001	\\x59367b5ec4614d5037321f700806b92c1e336d41bb8acfaf13042c07eb33719e47645390adafcf9ff1f1539602985083edeb7b3b1dbdee13df6b18ddc400b007	1665225088000000	1665829888000000	1728901888000000	1823509888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
225	\\x2be640271ae78be67445d831df2720f3063e24270a46ea41020278583033285403cdd4313a476050773442ab53e592c91e1ab3f5a125d2be0e008c097f18914d	1	0	\\x000000010000000000800003a6baf49e6b8e9afda8174e7fe957fd772a59ee5fd2d4cda4c54e0354cfe955c48194f7d6b2385a17dc1b2bc9733eb3088bec2707041c2eb605761b1992be97f2fe00f6fa9794406fc10173b17a4e9075efda9728ec8a76019b41800c0b08ffc03d5c0e1fed51d48505819522acb371740ce558fd2e25c0b3c6a23cbfd36bd737010001	\\x512407560c9dbda9f7960dba42a416f0b1535ceba8e1d3a7d3900a6e691bd089028fe598aa9e6a0d532d282d0571f4b4e5ce31122aceaabaff6a218f04417f02	1677315088000000	1677919888000000	1740991888000000	1835599888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x2b42fc3cfcaeff090571466eabf843e9d9ca99eef7f52c0d4a05d28503e2fc99b0c505f38fb88917edd628c68e8adafea8b9845fcba3b29e26b22c5a8a1e67f7	1	0	\\x000000010000000000800003df668971c03fc2839f9dca599399d92899dc4fb081da2a50b168aaea954e09cf06a53148a228484da2daaa9dee04b2cb3fa48b148f37c808a03c5c013f1bce32462d11d3537466c246ac25f0a9c03ec55bc49eb4f6e0c7d57be5b74c67a3679a06b3cc8e8de6f6fabc661c2b68cdbdee43df140eb067d6cf5de8af014e06eb63010001	\\x771f4ec5893da9c0655f556f6e994e2839c8e60de3b86a1d8e7d68ff2dc1f4a961b10449959276323fe60560ef468abb50a30633d36098d66fa589405e926103	1676106088000000	1676710888000000	1739782888000000	1834390888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x2f5a1cee626e9e80c1f53e91b2ea6914d8268a2609d85d7100ad8dafde8d22b5551fcced6ee7ad8934c0db2146af61dd0ee5129e8dbabf3c5b1ea834194a9b4b	1	0	\\x000000010000000000800003c4adff8dc0140e4ad25e6efa56e27bd1dbf0c8b265c8f7b184ab16e1716191e1a68af1c1910f3d4d8ac2e7ab6226208dd589a1c26eb2d4bee681556f6d2bdadd47aa83161710a8b6cd29a2cfc5e895b28f97530fe9fd1bb7bc6d3807659e5ce9707930ca451db1e098eb459fbd8e4c17e147aad7197ab9e7a1757e994106b1f1010001	\\x1c80854474f4010ce4b8c1769b98d4eeac83e3ae2653ca6bca28cafd52bbff771a800553eecaa852c59ffe5bd8849dc3270df1d4f6a1ac39c49574a32489e407	1679128588000000	1679733388000000	1742805388000000	1837413388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
228	\\x2f3a19a459e2cd829e0e6a54d75a6c2ba02746c2dc26f32c9b3af023932a708105b06981279ebc879e4ba239091fe26edf759013ff2c06ff20010c25ac4c4a00	1	0	\\x000000010000000000800003c8a100fa2db8a6af7cdf2835f9a4f3f4b5997e6b933e4087b2e184b85344630686aa8742ba436ae58451b678435a3c9c2834203033c19069e2c32e0549da3d0d9ca14c0510a857b6e147fb9b3f7eea8df47876fdf15eb84f8cb246f4669d22a4b9895bb28bd5138e972083c9dc08abf1ed462e35082401ecd889c9631500e047010001	\\x591f898bef31500587068005b794359372270ece0a67a844d8e402a6e47c00246ac0fb9df28faa01f21acbf33fb5f036378109af87814fd4c480e68e4992fe0b	1654344088000000	1654948888000000	1718020888000000	1812628888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
229	\\x316a4fc7cb4d6da4a956df08bb6dc4e8a22c509db524efa2196ad10b47fc44637612ebeaa351ff58ba8f43668982e3cb3ad12df6cedae25a142333882578e6d8	1	0	\\x000000010000000000800003cd2d279feb1822c4132c332c14d53ede4884030cf85e803fe8c7bb1c7cbad5ed212e35d830793820dbe04a57741b083a6c2e3d8cbe7bea7e10ca63ad7bed8a01e7a4a6b3968f7234fd4f78014558425fa4c875d50c2ddb741552ebff8c8fa5076f9dff9bb9a8c2de05a33e0c8fc3ece1da4558cde7d03d3be78337ebe972f6f3010001	\\xf9775cef0971c5f2ca581af772a3a33d2e14e9f5594fde8b74be95467ebd359bfd8910d78d2da2060775bbd21c3e7eb1a7ac729fd334d5e561e3c37b4dcc5a0e	1664620588000000	1665225388000000	1728297388000000	1822905388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x36e6c62a0fe2666a06d20c23be81258df45d20cb6dc7954c0b47b7495927f99c23fe415629e23962939beca390cbb5928e8ab7d3295038d64acebc93392c0765	1	0	\\x00000001000000000080000396e45000dcdba38dea86570e5feeb9dbbcd9448984ace39acf911553d32cc56a45797f319784557540b60ff4791d16f0e5199f29eb6052ef556bbcd6fa88cce236022980b7723ab51527487cc88cdd59357b86b19e074da183ad489575116f797c71335d2d452e305c6a1ca03c0d6cc05848ade271d73bf8b36ae9598da36b47010001	\\x305fa88b48aea0afacdb45e84e0edb57489b9531b25ac6819122a3f558d7aeeb13a0579e08395d1aa9e144e34bcc92729ef0fb4fec3fabfa4dfc55c2020caf0a	1652530588000000	1653135388000000	1716207388000000	1810815388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
231	\\x37baa5759a77b556e6f09cf76296763652ac678b95675814005df68ee255929f08cd0939babda93e82f08e9882ea7bf46eeccd46d0e4fff47c2f7e946b345692	1	0	\\x000000010000000000800003e1f0c333de4699cfee6aa3f0b6bcb94f4fc764823c171356365227de8a0fd5741dc741f166f30c451bdd728dc0b5162cecdd8773fcdbd444efac3d513c37cea3bac00a789a1dce93c28ff45f66ebb22acc5975178cecb82b7fec75508b05178cc8e2f6d58ba76ba93cf82b6386f8773fd8bab799f5513d393fd4bb68271274fd010001	\\x08ea669f1232a10504344fd375ef9685523d05d66c4050d1776a102cd139ac66a03a52eeb7ad5033a57a62f327002f0ad870dc7585c723ba17bb27c6df64a707	1673688088000000	1674292888000000	1737364888000000	1831972888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
232	\\x392a2e77c8d65c4aa250ac8209882bf4b3d64eb0c4c4ef7175be12f5bd5ed6d40421b180e6b1f0cc2f9a687ff8360f38b37fd14c4bb9a407119fab0199489045	1	0	\\x000000010000000000800003c0598f9745c291642476aec417d3b37991afa7c720e01d4674b1c6fc2ed3710abbb19aaf77a6cdb2f89488332619bbb97ad6c505a055f7a777a54314fdb49eebf24accef3a02d933d8b68b038424fbbdd12f38c84523fd8fbf90ac98b832e50d9421e0fc7ba7e78fbcbc670a269ab4cce6d2405ff77c842b0fc21f150d1cb289010001	\\x598b21ce018a74ed8ba559418f351945766591728bb5d8d9f5a74b7ae950b81146395584948edef588ae48e98157fb5cbd140751f015c508319e8b9bc77e8e02	1647694588000000	1648299388000000	1711371388000000	1805979388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x3aba6a7e2e4980a0c582baeabe181eae37248cecba62f3888b4c3e4915e2bdb14045c180e1a02cbfcf0d094775ee628d3ac66e7b6b40a2e6170501d48f48ddad	1	0	\\x000000010000000000800003a02d4097cde12da4e71b3782f0a0c3c91142ac3a96c7738e8adfa2ab84f477ff0dfee1492f7bd8444083dee191a1689ac72377149de30428e12371ba998532881f4861ad7a68260544ebf74ab9c1b3eb1f6132760baa96162a78b32c9e7dbe4a89f2f88e3c3fdddfd9dc6c57ee7e2fb7bb5e9668c9c2b8edfc2f5e51768ce067010001	\\x659301cf5471e46e95ff10bf2cfaa1feccaf0c12a83bb3a7f5cf8e551abd1031ce1642f3bce5e17aed68a43aab0523ffb6b7ec9a95b59744142a792aa13cc409	1662807088000000	1663411888000000	1726483888000000	1821091888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
234	\\x3b0eebeff9c81322f847b153e34090da550b751945a6c71a5a22c2bc7149b601048428500cbd2c78e94b6c861d5159236cbbb6c2e93ac585d1bbd9b6a53ed830	1	0	\\x000000010000000000800003d82edda6bdc99991f01692382e374d93ffda5eef6b8d85ff6e034cfe8f707bc71c5230e97a2af42282aaa69ac741b07490e5cc30aad5a5e1f3c0b8c23f53f2e2e9c2d3cffba7157324625294d234dc4dd2c699b36230d419ace2c7afeeb61d5f5171807a7fc2ff5fe4e0598afdab1de12f6afd2567977136d8fc61ec5140a80d010001	\\x4879cc6525f2c207740980f6a288035286ea2be88166874da1b915b2c8f1d3335e0f14508a6718d52fa8791738dd1cf7255a8e02dafaecaf0aa0b7c230ce1408	1664016088000000	1664620888000000	1727692888000000	1822300888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
235	\\x3b1232f593bf3f2c7a0d6ab1376968b357da9f0f56e062d6f8ff562f16933a736fc3812d2bf5521e8ab0139bca4dbe29804892d08f0c661da10c94b28a0821ba	1	0	\\x0000000100000000008000039ce093868172b7961b57555f98b9ae1b6ac2314b1a611e3aca47a7199416d9b3213920a9b4f890f03ee81c31cb2c32b7322430d613c0f0fc7c237d642cb4d743b9b57885f99b7e47e02b4455b96dcf119a35d59ae50a0ee5ce1fc0218264d368ca7ef021bd3c7dd9a80c005a4bae3e017f717c604fe497e8985f7173ebbe8b6d010001	\\x780cb68e5a7c7d306ad3164fc1527367872bf062a884e7d06c3820f6a85ae89ed7281ecad9c7d228e48b099a0984b69c247cb453f7281bf2501720eb6d6d080f	1676710588000000	1677315388000000	1740387388000000	1834995388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x3c0e990fb1f06330b3c137a053aa9a0e18da2c94e9ceb8b1fe19ea57d53feef7e88f0846090c9d9fc1f995f2e746f5f5787437b595710224e9e5ceae51c61fcb	1	0	\\x000000010000000000800003c5270318d1403326081560ab63bf01fca575b1d6708a6e62e9a896262eed5bc1e29ee07b147b234f0262ff2831c975071e5404d124fc33ed07544948da48f315bbfe86e6453a2e057929eb1862d94a10c3ef5e7b5984b8d5ba5580aacdccbd7bb6e6741d8e44b51c4165eee108ec5cbd687f428939a83cd6b91d9a1e8fb5e399010001	\\xe95147c2d086f7c22c5654157b50f4ce3752ffca8f032d01bf8a8d77aea0ae8ddf6b9a87521a5eb8f46e08275141ab7a6be73c62fd59ba6fa721e084366f070a	1657366588000000	1657971388000000	1721043388000000	1815651388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
237	\\x3eae0e7a21c7d8675e11942b769c3e504da29fc6deb693465591d831fd2047e4ec1dedd319cf223925fd8d3b510486c9ad8fbc2bb17fcefeba2ff316843ef8ac	1	0	\\x000000010000000000800003c023d1b09bcfeaaa4dc1237418566660773c30fc4fdd1fd2f9650bda1d9e38f951cd8e434ccca3026380bb65e225b1500af51657315af03748500828ec5da1b641a8f6b47169889fff9eed0f20d958a0d49ef7c6227c42fc876f5a9a00254ddf17ad42afa15bf39306f8be9401ac0d6eaf99666791c85cb53dec83b9bfcdd79b010001	\\x26f9f031cb44607ef943f5e68c5bac57e8b5e1ee1843bbb6f91dadcf39fccca5e66c134443dd3edc656031be9d5f9810c1be2192319e25ed1c0835bd6cff0306	1657366588000000	1657971388000000	1721043388000000	1815651388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x4306f59e50a7db65716992044fef9d169980e1406db1b8faa3abbab305813849a9ae6c3ae9b540555c63f897146276d3a5501def88941273232608df806a32d4	1	0	\\x000000010000000000800003ec65298c8325d014cdce6bb3494e13c72ab9fafdeca6d65c616de1156690b344cebaa0cbff81b53c38ec938f86413065ddfd863be1f8a664f3c309518ab0dc84a03d7ac506498dfd44a8d871e207c2fd226a08b9bccb4ad9a7001ff3c51228c69c93980df4d3adbb7119f01b9967f4bebbbf249e379755a43bdc2196ad3d2a01010001	\\xea9c2f531c538bc5dc45a7df9f78cfc56f3dce1506d304ac139777a10be1f475c091216cb4a567da5f533c1b2d08f5874b65ce038499acbeebef8a05147dd907	1659180088000000	1659784888000000	1722856888000000	1817464888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
239	\\x489a7339d221a34ee052d6bcb265f0af2c018ef7a5f72189b8e99e8698fd0aabb5c0cf7bd1b56b84373f85378a3199686a95145978bc6a1d1bcf9849bdfba73b	1	0	\\x000000010000000000800003c57ae3165888171e4d2776886ab2a13330ea459b240d6156abe01e8cc4e5706a70faaeee437a477f95f07a01f9504f5b78310aec500bfc2ac96c914dc0f62cff76c7be1fc6512595e86e7a013c1b1e6591bf0b3af2628776c2ec3d293e17c641455374b76d00cf63d5eb39ca351121b8ec22ddb8f77675858a7bc63f2666e531010001	\\x4f009c9ea9509772c92828b7fd1723dc8c58b8e7841a142ac0597c0dacb03833be709ee0dce132ed4c895a1f1d3f544a3fe4a4f91d3db288e369197c48b5c008	1653739588000000	1654344388000000	1717416388000000	1812024388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x4e8e3b8d903401d8cdf42cb2048391bb03b5554f0cc6726727053dea8af76ddc5f1dd35478dd81dedcc19dcf07d09bc1f92212a1d9c818425c9ed4b8a3b1de17	1	0	\\x000000010000000000800003c10d75ccdbd4b53b63c8b45a298033860f230b480dfec0ec9d1955a08e67834922f0433f7556d991ed8710227975cfadd69b86eb73dfe15baaad31f7cce96e7d6c255d86ac9c3337205801d9b4b09c7f1a5e4b6e55c5d7d706ce46ee4419bfcbc775afff73948a028dd4923c943f456c83b2b93820b2b9efcb862f2ea523c5b1010001	\\x1337d0b7979d5e0270d97bbef9f61e5988d5ef0d10dddeb17dc4e9b7f0f663e76107403258235d6082e06c625758b88f9508e0c989e322013e1e09b739858803	1648903588000000	1649508388000000	1712580388000000	1807188388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x52f6fe1adda1de61170deb23c2d8a7d27b104de4774e2e560304f8e949c3664666555ecd599d986dbf0c56d023215f4325ac4474c0be0426733664065eb9539b	1	0	\\x000000010000000000800003a2a6300c7a14f16f172d63700cd19dffa70ba4e42833b17f43e2dac42e29ad04517ddfc9f38b66f0d9f1cab1945d58a48572f2013e0f9cc4020def436859922b768756e6ef587341a75d43e95589cbc31c9d1ae9502a6d454e1b218844235debd8edf0f63c7649cbe757f4e8710d93e7819badb56bd104f7a922f79588835479010001	\\xf6373a05ae37bb7ac469df9342dcea1e2824db71151be9ccd01c3225bd8748c29e65468bd84c7bf3df7cd5f8e598eae7948c2142d90c1aba1ecccc034617f908	1675501588000000	1676106388000000	1739178388000000	1833786388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
242	\\x533225f59dcc8c6911743aea57af351a2ea540368cb64bd5647b01cea7e16b56db7ca188c85305daa17fa7febcb0c49e6a614e27e455bd4d58740cafd81a29f9	1	0	\\x000000010000000000800003b0f86352b94de47021f5942e238052020296c6f336fc462afe3c9e95cb41ff4dcb200fe6f13f83add7863aac58c7535a1a458b60120d2ddaa467d67ec28d810404ea1b1886d57495155fb866144eb88ef536d918eed4de1a41626d85a1254a8fdd6b20ebdf0ae01cb75d7516bd85a2fe66571562a65dff8f99522dee84736b57010001	\\x78824a17f4304bd9cdfc83ea6e46ab5a0b27e6fe2963d6c8a41274d3f713758049ce65f0c2084c3d403d07313cabe82bc47c168bf9cc4f030859a9b3506b7a08	1670665588000000	1671270388000000	1734342388000000	1828950388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
243	\\x55060e2505c91274bb62ae696d4156cb96a2d640c9b826ac8cd7353f0149b8c63d0b6fa2875f0e2a8be848e421b053f85f91599099bbfc9ed720af41b082bf4e	1	0	\\x000000010000000000800003ca31a67bb8a7264d79f0d6168889cc332ccd1d014ec97fc28a93db2048445f58e61f53c09855bafc00c38d1746e109162a3a0ca9054969392ad404f0b9664ab45f853c11c8ca91afdcb1b7f530251d42d8bc57d39abfa04da1bfe74fb4ecb1b1fa70b3ce66c9cbf1b6d4c9bb1d87347cf05f8d9c92294bebc24dd7723f4a9f21010001	\\x80435094f9c7d16d09952014be925d6b7c823ea80d5ba135dfdaa7b36285718bafdf804b6434bd388f82f3a5525e3a40c77a6b421fc967350b0be6730c393907	1657971088000000	1658575888000000	1721647888000000	1816255888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
244	\\x5636e467d3d6994115db360f6dfcc07b144af0f111670c9bc50f9d2225e1157874ec5e73de76258b9d84c7824ea7989f9f6c384ae31611618c192d5bfe7d3919	1	0	\\x000000010000000000800003de3d20a5734e39d20b5e0ff9034e3aa8ac6236953a01fdf0337178b37345ac21a423bd7a31739b2ad391a9ad6759f674dbb7cfef35d24b96b0dbd77871f9225716cb0e548ee47920786bed3a5a1b7732d20c21b2ac1587e295b9de48e37a346cde423a10b08333d42d01f2ad65ef6084a64655e01a203d50f1cc421e66f57233010001	\\x70a180bc856a42fa6e1704b91738f9cfa4b34b9a9863b387b59340c1c796541d7469e5632129bf2b2a64da20d4a48ba52e07d498261dbd200bfec3a5740d6c0e	1673688088000000	1674292888000000	1737364888000000	1831972888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x57a6d12c9fe4186f98bed3c35039e989b3c05acd5fcad5f861e2a43d93ab560ec1336c4ddb01387884bb3c7e98da266bda94b468e09c266675411740bb69e56f	1	0	\\x000000010000000000800003e63178157f07224685b1327bf7e86d23aad83980a05b0c113b6dc23d79184cfa5dc032583ade3a89b3031d7f506b85d51b4767faae6597491201e6d33ffdce7255f4a04195f6acc8619c027a735ba4fdcd6c5fe0b4bd6ef5d806dd608fb653d355d0bc161018cba172fab2e81f29ba2d133b8ade0675e71bc86763d6655fb077010001	\\xcaa3cfa67fafdd036a7713b189ff03c07396cfc141d4d0e4fd64faeefc58fc45fa00051c6dab40e785c094f8ade4dd98b6b5e769d4c4a3388d874f61143cba03	1667038588000000	1667643388000000	1730715388000000	1825323388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x585e42a381f17d2f5a71d5421eddbd0fb705ea6f011d4425ee3e2813de7936cba0933273d82f38d4bdfd5fa08c917249a641fb05ef9d381702beee19fd16b5c9	1	0	\\x000000010000000000800003d82fb43227f79f4e6d50882e1fccffb5934e9fdaef04ca753db87deafe381beb44999c492052f7dfbd75148a3f1c8fd6b6e79a75aef3ebb7f58244da0713972133ab2f3a743971c43b881d040149272347be9d77bc0accdd2bc3763a2b279fb6b8c52c65f90dcd1aee5993898cec0c46074c3c13e59b507970253429d93bb7b9010001	\\x1726e97b863eb6c26df0f4e6eff04f595bfb4b500d30ee882d1c3d255102d4c7a69c2049b576c46917c4bf801c83dc22d6f4649826ebbd4fd22feb782c419906	1663411588000000	1664016388000000	1727088388000000	1821696388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
247	\\x58be66739261ed9da6cfa17b60d6c1de00fc529e792c50d5f60ce7d5bc8ce9eb93b780c6b4084ae9c073f4fbada72c00381f017db6024947006f6077bfded568	1	0	\\x000000010000000000800003c29915ee8e6e7aa4f31883de1037df619bb597218d23039537dc44ef7c4a4af582fa724013f01d94cb7c542b2ec8eeeb382b2c516e40565104dc4ec0ea2c906ea1460b22932a8832b16e4b59f0955e89c85b126f76de1200e51db5d6f5a867452a564101ead3f768a91449aa9d7b4fcd73c44c9dfd840d44ededb0fffc419667010001	\\x909b6457f8bba03c8bce21b679a92e8a581732174b6eb5790209d3711272d9ead30db865723a9d774483cd7abdc975c2eafbd74a03a66aefb679775df456eb00	1670061088000000	1670665888000000	1733737888000000	1828345888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
248	\\x5bca81289b559f95c9be8cfdd068f388228a7dd721c78d147ce11f6f3f8178e508ce629a9094f9a87b7d6d5cf9dead633f4e1209a1f9cead659664ade36e3429	1	0	\\x000000010000000000800003dbe84a5c7b045185edfbe96216c9a6494d18168e450bb03a8ae662a20769bd1b462877c25d5b2f1a03765a53d03e0f79150d53635c9dee9483a7860877cebc1a2b849fcf9d5682fd1c27ada51f2b94c2c5c80b0878e013d5394d26c73092087556fcb209b53c5f528dd0777e6d4d44cac9a8bb715e98d32db1457b1ea128be2b010001	\\xaa64d61d82eb303518750b21a39c2e61dcfc823b3af7e58c6e0122b2bcaae70b154481bc11ae2797e9e290a8f09255046dbc4bd30e6af0ae9355f46feba1d80d	1653135088000000	1653739888000000	1716811888000000	1811419888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
249	\\x5c9a072fdcd06e60353ca0235cce7dec2ae28d1b3dcb17c497e1a971d35711efa7f3e7024590a31764092c5c40d022ad5d9bf22780d0e64162a27febb1d62960	1	0	\\x000000010000000000800003e737d1795b1c49745cb93caa6c91cc452b85fafb750dc06be513fc4a03f94000e5ae5d19e64cb18a89cd61c3d95aa2e79a714308b5938b282adf8dc3823f947f2b39a58af674d4dab99c39a11f17855f4c3bba42046ba95beabd287d9dd6d2158f7d5d2477e7afce9022d6f2e2fbf6ecc5ff3f7f9131c1a4972d3aeed4d730c3010001	\\x3c2a2e50d2039ae5504ee038c5ec1025f8446b0bd7f351772e255449a99de8c4e5020b0421e5ebffad39d11b060349d5a2f65be1b8f911e07493890ce7e6b20e	1674292588000000	1674897388000000	1737969388000000	1832577388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x5c9e5de9cab00d01e185226770dfaae7020dcd1d32d9d0f0632fa78e6059f8007a4895d2bc8fbc00ebd9f32a2385cae2850672eff29fbf642394801b7d259298	1	0	\\x000000010000000000800003af219706aa866759a2aa6064b3eed32fa9a9b7e55b5d2512f35e817aa55dcb66dc6e11fbbeace1b93198c6c4b3061d302942219c3bc89b356f2837058c30dd87411ab01a09ec67074b414f3ba69d448fb73666c386099f176d219af8a4bafb04bac98a2b5f8fc908bec8741b2f578d0c40b2b6f891be60154534d25c63b94c59010001	\\x4a6f7621ca011889a59768934507542240e82930de2580dd100ec856f5a516f2fd39b52a2a1ec9944cb1424ccf3427d7ae9e8fa9c99fea97cf512624cc46c80a	1667643088000000	1668247888000000	1731319888000000	1825927888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x5d5a5222bdfd6fd82ccc960488dc6b3e031eb485036cd43b136ba184f9f1080896680f52ed10a173c838789a18d25a1f65599e047d3ce7a24a965c76475e2c77	1	0	\\x000000010000000000800003a7f0a3bc1461f725c324db76485a1326fa12500be1c6a38c8626df4828d308a2aca72ca4501ae786da347b3719c8759a443547b0c0ee8c676a39297e851e9b1d091ddc71933960faf7170249f2ce7c391e84480d31f6ee0fbe36dea020fd904c27f493a21ed7d872b59d541211ace7b9809e811307f3a08c90296d2be97cecdd010001	\\x79a15e4cea0d2e87a27b7763d59a1e2234c71b659fa71991ffc9dab1f7830020d36c3f47b345907c7cc1a28733bafef4ad0e41d37cc3901d704232244ac8b901	1647694588000000	1648299388000000	1711371388000000	1805979388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x610696a6aa6112a7404650e6777e0602048d428ff430fa23d5dcb13f019fdec1ab7911c8a34f264e66f4e1f5b5b0111db85f121654a7fa980ab8b737fd073a15	1	0	\\x000000010000000000800003b98918f2d2a9c9ed10e2ac3302f208223a438f6261218b96bdc8d1bb117f0024c863004be22b5d9137bfa20ff5702733bf99c6f5730d7fd1ae7a1da16ad3cb1e937bfdef7a98d55afe6d03d2226ef01c34bceb434dc473600b702a045cb909873999d9741c08af37f541a17d6eb034c0a7890034f1fc47efa699685e12a7ec39010001	\\x7c900a30ea72a65fac54d9ea73c9d1c4aed13169edc85f135be3782c0e37dbcb389a5fb8129438e3d0f0a515c4f2f4009be23ca362e86f556bfe36ec07392d0a	1678524088000000	1679128888000000	1742200888000000	1836808888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x689e29a7794b0e8f3d3f147c3cc3f23bfec9e73ccf8e25ef082ca2de66f3d162e38fbc70523c433816934f4efd5b12e13c603ba7b41d86903e5ca54b6c1abdf0	1	0	\\x000000010000000000800003d40203bc667e700bb9bb2d9fe5c13fec250cf223a6ca3c0b7a4576547a0131734eb81277e44456a2909b5e4ba6d5eddab422fa41b03d5d9f13f3694433378c1944912f7fbaefffff391a2e8e9003f14b110ff39a32092f52e1758c08a35562fd4ce7c68006b0f8ee1453048e20ef7c0bb140d2be588478bacfb699b9f232e01b010001	\\xe8c402dabf75451cadcebcfa0b6ddc2de6cd8e70ebc88732b34be08f1b0071713aac25c14fecae7e5a6a693d3a74f3914882a4b5f6e58853e217498b9274c90c	1679128588000000	1679733388000000	1742805388000000	1837413388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x681a2d9892a4c9ebde3b409bd95826a70c62299099fb4d34fb28fcf349505e05d6cdebc53540d87be7e112780a11286b89ff365bb7bd90e3d4b121e8bc7e7a84	1	0	\\x000000010000000000800003f00996a1ff7dd2f36436d6d34542339ba4dd14b7bb41755677aeb27c31789b1866f935b3b8bfd1be31d42a19fc4c9a7114e480e699a7a9765d4a406b5634ff60a499f05b399bb022e4b02bbf21636c2203ff3bc7c877d6e32bf9e39d6532c798116d7c846317a2d50235815dbb961a4bf54ac70438850ab63abe94e60d16d071010001	\\xf37c58d993e49ec502146c426e79edb4e6d2b9fd44587812aca95760203add043a741778c5ad0d35838c1ff4f046098bcf00ee1bef8484664fb48f21f1a05509	1662202588000000	1662807388000000	1725879388000000	1820487388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x6b9a9efa630bf342c13793cab13b6fc8b165c05f6d267b2a1114b077e168befbe7e01ecf00ee5914fe7d7c86d1660e3d8eb610866b6f7767cc6f65d823a0c4b8	1	0	\\x000000010000000000800003d41b6fd1757e3d76fba917b045d7624196a69771f4dd5fe0acd07e6ac4202d44d9e023e5cbee286addcf902638687827eec09fac5d58fbebf7d36fd3ce9d13e3298c1ed1c6cc29c677dc7b56add66072dfbc6579623183330133ab8321301361a55844e9b10485ebd8cb23aab2968ec998913e64192c65bc39460756117dc6b9010001	\\x73287dfece5f03c43f8e8f1ccec0b814b756d2eec5303c9e7948e01ed78c96125ae915ef4cb6dd038e7a4fb4800e14cd5b350782b07f7fd94c25858e8afb710c	1670665588000000	1671270388000000	1734342388000000	1828950388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x6eb629b7b8ba8b5c9ed9a35c6438d0cee3fd6a14c4922c2d0934706a34370ccb084eaee6b2436f5a39654f8856ca747a52366b6b65fc68cef0462dc8828302fb	1	0	\\x000000010000000000800003df650ae21f556e0bae956fad638f3527ce78f98f2b79a132942ba05ff4b983cf6d98876193f9a93a80f9be1769eea326b929c272ed2538831a087bcc93daeb0ce1e639f35b92328a081e16a93bbfaa626b74a26ca2c4d5bbec35ddbb723319de8fee2e69c1c9e453b16cdf43c6faa3949b844e819c129ffd5b0b1e057cb0a6cd010001	\\x46a99d62cf8dd9eb8ac11c7ef582e82bab66a1fed12213d3b50c79e9edf7b0e059dcd49365d0360069f9e4a0b0dd43176ff323b2d92c2b1fdadce856f7a72904	1654948588000000	1655553388000000	1718625388000000	1813233388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x7016fcfa6f9ddd0bf7aad20cc92acfbff99e08040d8241ae751a364b4e2b94a59af2fbdb295c719b454257c6c202a9208c9e125e9f33069e293853b7731da6ef	1	0	\\x000000010000000000800003ab05960212702fb071d8ff230efc0df0df23423bebb932edf30fe4f418ad5a872393cba0de4aa2811faa389e5991673010280f738ee5cc6d3eb28985bb75d969ed2dff541d7ad03da9fcb740b6c151e97085bd27161bd9872f1acdd40b99ced0bec7b4ff3d7bfcefd06675a7807c1fc0856e8a5a183c5b9dcda42f6f9775d5d1010001	\\xc5563387ff72b95b2fe937df785aa51fe4dbd246798ba02843072e5c2d9af899475cfd5359f55c7aa7631d44d71598b968154ddd5720ff9a5ff52802109e5908	1661598088000000	1662202888000000	1725274888000000	1819882888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
258	\\x745eed98978717e269e6964943e790b016413e4d8b9ac0245af1e8cc51acd6f427b20c1be871bdbf77e228b9cba8013d286dd60dc0b97c7fd348e131b93b3ff9	1	0	\\x000000010000000000800003f0f0dd5a216cd8bd16563b2886c7d780dd4d2aa6f251cea82c1c1e0f59c7112650f83316f77d77dcddf28524d2b884e11b344e9891c3e755a2931c7d7c2146d8e81626253e34f3885ad24d37f7382b5220286c6dd342e374479c8a1f4f4b3c61b669e9ceea212664490bbf90ff8719e8e5266a99766d6ca3b1eaceb2a415a475010001	\\x132bd96440fef1b1c5f9d6fe771cc5597291605a2d395974352e6bda92c4f7d78421a49a569d1c9316b4f588750194f55d0cedf54325712f07cfbbec9c4f1b0a	1650717088000000	1651321888000000	1714393888000000	1809001888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x74024f931a9bc606ad853ffdfb5ebe62ed04d2cf0e8794414a9a80e53334ae7dc617f9d509727da37061d1e4a0de5a337485ed5eaafe8547778923baf2d388df	1	0	\\x000000010000000000800003d6a7b3fcc528e7fe8a785040b38ec01fee95530346cdb42f482e7fc71bcb07a5828a6575506bff88fcc9da2635c267c602fe99ac692ae9d93ea9ea73a949957ea4a0a37d0a86d9389bdc3cd663f1df64ae810e53d9caca6d7d028392071a2f945d8fa3acbf91259cd05045d04ec7dde7dea7154672db4236908310b1afcdfc41010001	\\x57bf42f20087a5814d0c2c2deb0ebbce77ed59dcdcf3774575869756427065a059bc02262ca3f8d7fcb7a1fc18e0b7b5c23087cbccd9bb53289d160f9a1d5500	1652530588000000	1653135388000000	1716207388000000	1810815388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x79a2e31a0565a2ccfd3161d44fafd01fe6f68f68e64e423b3a447811480752ab0ed4f2d9775350e8e37b779d47133b9048eaf483e10d0472d9c85c166d1e2783	1	0	\\x000000010000000000800003ab3dd53ebaa019872ab7c94a336328e060e4cc790793fb1a9023218c006e7e00ad9a084268c6192306c17e5739548fd92bdd2b145ca4be422a9a1a3d18ea765f15a7fdcc13f2b09814ad044df3ff8bd9bf5b963b8c9432eab54378eceea93edf5a9ae096a6551c66a989ebadc8e5a29a3be20b3df4542e6757703b6a6f722eab010001	\\xe1f370fb3544b7f13f01b88d763118e51b04334a0712fceebb665d3ea7ddbba98d593581814cafc06cacc1f5ab88152c47931513dd8b5efa99f49a92e6e73604	1673083588000000	1673688388000000	1736760388000000	1831368388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
261	\\x7ade44ece57cc2563fbe1bf60091711d52ff2e7741dc83318420dc9ce69f1a6ae2c43d857d102fd7408af620d162b0b6a2bf070eb4a463588615d59de0b1db2e	1	0	\\x0000000100000000008000039b8902f4641cc90e5058b76cccb135d127be5bb4461127fc0d10d8461904269664bda0e5a3bae03ae804e13022f7db03193c697f9937acba69ea4ef69dc1a94f1782e0546a76fd03b496db634ea3c81639982fd8dd16424809841d5d02733cb74332b6770cd3df8971705dbe24319c0353926454f949950475439a207d443d6b010001	\\xee1c833181144b92129475d6df94c3de655bd8d6a031ebfd806bca5a604dc263037808b3f7b52de69e3620baf388e85de5d724b88fe2c4a86f953b10e5950d0d	1676710588000000	1677315388000000	1740387388000000	1834995388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
262	\\x7fde4e9fb7e0c54b0206504fa08cb68adbd0c258ead8d305c92588ae1986aa57fdd0678fe0036b736e6d707f1832cfa4c74b85e7a26924802999b8fb6fb78ec6	1	0	\\x000000010000000000800003b76b2f36a703041e0ff800ccc8f84888f3646ca36744eb4f7ddab0cb146654c837a69c0c1b8a5e2f01ff7fea57ad8a3dcc5cee14f805438dead6527c79a05e245d2412d04d07c7719cdded0adf10e92d84a0ab5fcb20842a6d403365d0d8b17489b625da4cf07af064e1a0410292613ad74561186f104dc32f6098f9b0fc7953010001	\\x7fed40cd39ec3c24e94f6bc527c67940023cb378df1b0f7360bbf8538786cb43da70a9641c25753efb7c50ee73b518f61834d6df22a162613ad314653aa4020c	1657971088000000	1658575888000000	1721647888000000	1816255888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
263	\\x816233d021ecf0f2cfa0364082520e4e85de62542ae849564882ac0431f9310775fbf941fd49ca1257606dd8037541abace2c3f56ef23a0241a9d6a330d8fefe	1	0	\\x000000010000000000800003bfd38c56baae20161a37517a3fa9a6a214e2e2e054f48c1a29682103dd678aa722ed9fd917e7bf11599345df253d5b63923fdac6777fc83b41d7b844d78942de25f5dcde8378034054591140ba74caacbbac52dca2300733836e4faf76167a5ca7d6f38d69f1a427dffa072b031e91c9e98b5dbfa642e526bb4418acbd83fb21010001	\\x4d943ab2a5d4c06ffb9b49c01f8c5f4e064877cabf87af2dc5b2771f03e7c3567951aaf55d0cdc50aa586433a502a5c63364ff74afb06d49b20222d354220c03	1662202588000000	1662807388000000	1725879388000000	1820487388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\x82529bd3cf62a0b55f94de47dbf0ad300a10122859ec13f23ee9cee5c5924aeafb58fd4ecd993ffc2ee94b4440e8a8b280666d1c0c6801f35908a9dd3d9cb7c3	1	0	\\x000000010000000000800003c5eb673578549f3be5bd4ad76e633e685db6bc0daf59c914a932d9e7253e72dbd4906e079f5af7df4b3f17c039231cd80c0919cafd63640ef5a72f37693b3cc99fe1e69b35c42178e818cdfcad7c9c702af4c3a782df6955b57798298b6049d7985b367138d4a20368b9c0c0654bb31b4777b57ce38c688befd9600bbb4eb6db010001	\\x73f68f5f29e5d21358d0000063bba617c4cc4629fe87e9df0272720faa13ea564aa260160971f463139a26dcf9ee3413bea377522ab8741400a53caf6229e107	1676710588000000	1677315388000000	1740387388000000	1834995388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x83faef53ecfc739edafc6469954f81263b1bfbb87ed964c50913750242c597c6713b6fbeb0cdaf1ca3802c18432fd1de6712febf5d94fe397dcf41774ebc5cc2	1	0	\\x0000000100000000008000039cfd105c39ba8e6e118cb80e3ee4fe52931d3083f0ebbe5b36e6344b5bb0997975dae7fd187379e9eaa4ff06e2d6d2d14cea1714edff45f072a6a19edebc75abdd102441f53a5e12a1db19bb0af5120d231feef807adb1913531a820b7feffa60875bb0c04840218c4fb31ce761b0bdc021dfda6cffd30e206443833f14d965d010001	\\x355a7ec07b322e0d2d0510c9c3dbcdc9e8b82b862965fff3f2eaae31b27c33208bff3705095176ef6a73bfa572bfa3e95bd8dbce6e1bbcd8660ed988adbc2005	1658575588000000	1659180388000000	1722252388000000	1816860388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x84c2c0d51442c6c5abce48908a0d39e870b2d3298140a6d0e682faf594252b4d676637dc7d280073ac27cc36557fabcc0212e038c3d529e92ea1feeb4cb0cbb0	1	0	\\x000000010000000000800003e411e9b875761991cba37d913fe2695695e45a0a5e0924c46611a5ca970d7cf518ed9ab29983a3f8e16f3e6c59838dae4775bbd7747a2a247934c20a8daa57bc4b7924ab4cf3092bf69f85ca88adf62830d325f630cd0715a02deaad08bf6c49bba65950fe7558226f9dfb00183e8a45d19da65127098040df173c47cdc2fd17010001	\\xf9a5e424ab0e5fd3f31a44965e937cec5788ed31f24e9a48e2297913a422112e1ee8f692d897af85703299396e3bcf115738a0c648db4482914611d9251db008	1661598088000000	1662202888000000	1725274888000000	1819882888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\x865e78a196a2527285dd5795c8fcf1ac2e3808b7dff631d1df4087de888aeb5999b9640549fbadcacdcab3b71079cac9ecf7cb4988c8fdd2e3ddeef319652653	1	0	\\x000000010000000000800003d74fd0ab63cc28114be6fc1c7f402fea26da53c11b31d5c9d81a04f726a8b42f839347364a90ede93919f55072614ab82ebefb1a3b5ed6545100f0845f63a610bed914f7f1845dce820ab266f8548add95893f30596c650635f4f25e7d1e6194b5d91037f769aed2dc361d371fcbb388c0c329643fb519a2ff6d2b73cc9407ed010001	\\x30593acab993b795a46ae8affd851d3dc42e04c3b8431cd9afeff650763473103f3ab70d68e66711e2b065c4065261ee43e0e9b7f8cf4bcc8004fb0fa9e90d0a	1649508088000000	1650112888000000	1713184888000000	1807792888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x86eac4f634d43f201646a7a5cfef78fbab3d9660f6e025503cb58dad4983f75c20c744846376ce9a97ef642c508cca665d698381a2f4b06c53cdb6b99cd1fb91	1	0	\\x000000010000000000800003e656c76c283e4d55496cd4d1b4cd5db7941ec5bde625d0491d6e0e14a1ac1dadf48be92414a639836d06f7797d8982286892eb621654854b31f0d4faec86227de7179dfdf81fd8c2635eff0323fb85a7db704c05fc18e9587c147f792a70c9726bcec43da9f7c53025b851b6dbc276db0be9e43389abd6252092cd45db63483d010001	\\x5606933b77bc9324e829b66b6e907342ddf0e41acb784e3e9e004957f00d240995fb62bb8ba4d34bc28e00b5961fff1b2f649cd3b78162f21b2cd3ad67410d02	1660389088000000	1660993888000000	1724065888000000	1818673888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x8602f51543a9b1ff279249da2da10d9ac01aa8aab53637f86e343a176d46bc08cda930e1957ca7a876b6df922276e2163031298df76508310e38f066a6ccac34	1	0	\\x000000010000000000800003b88365068f801c3185b75512268a55ca1db1d3bb3d75882be95b21a1ab3ad1df8d603f9b52a79f8aa282b87e7448d242ef6e342cc0c7c290d64c52a254e8764658db1096ac56c01542e5450d7754da294430f31105fcfb7d1a18219e4af5249e26d23fb630505ed4433132b59fd6c2c61ae8f12082d7c5f62ace3cca2bed82b1010001	\\x4f3e745c613f2d39d4233f56f117f6f53e366cc336e8b1c3dfe6338cedacd3b7575ac672e6ae5e7e61ecdd54509866ed4bdc817ca9e5ca57e7081eed149b4f08	1669456588000000	1670061388000000	1733133388000000	1827741388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
270	\\x8a6a7c76cd7e8b542b2131df15a222b679d327ef44044a718143a96011d4a06434a9ddae5d7f887fbb9e0925c5c63b129913bc9eaad90d365237b8835b8f90d1	1	0	\\x000000010000000000800003ab77583400b26d4d409090aed048720ca0c8b91ad04aea819975c74a02954bdacb0305ab5a9faeb58482057703375e99ac04c588afaf13da044343bbf2dafc556fb924d401849bba190fbb568e9bece3f7a4ed5f9068e40be5409787736975376343375d057b4c43578dbc8d0fe06e6ca403d97be7ae11c8275f87034008b97b010001	\\x200286d659bc89947ce0a68b2d08bfa706aeb1289aa5bb1bc97a8570e0ec7ca8272ddf4b6e6699a9cc4d10002ec84aff3200e63bd00009e1972269499377b101	1652530588000000	1653135388000000	1716207388000000	1810815388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
271	\\x8d669032c6fc20b19a0a464184469d54ba72682a008245c2a4fa9c1a5e11767c915a45404d2ece81e7de474718152dc626593a2f527edeb82d0e270befe68f06	1	0	\\x000000010000000000800003e1a88b71b783f7998d42623dcf446445afb79248bde8a4627c9f3d7aa3f64795d6c16826cfc19de082b6e8ecc1999253e3d341cf4c89c2b0d49c8129d341d623676c6c6ac54df8e858e7a7f98ed9875dfa27101ae7f9e2e2b5be134f940c1dac86f63f5c61307b4dbe324f55109e877dd2e902b0616556ac600d54f62475f61b010001	\\x4798f3455f90942beb04bee08db1da9e25cbb1527fd192cc465a6318b7b64fc464e241d2534e2889819765b58856edda8b54cf41b7dd5da73c880b4f2f25a400	1669456588000000	1670061388000000	1733133388000000	1827741388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x903ede94e98f5e95fd187d5fd5c365e150f2f13c64e03a2c34073f7b1480bd67d5ab762347460a020f5d3a3136f13253f30b0e3456afbc20677fa0996bfa52ae	1	0	\\x000000010000000000800003a32447a55ea509dd103cc185bdca860616f0eb7d20eb9f774d98db46df90a4be9ea848f4288bb6fce388e9db3531bd5a717a8bacc32534ae08a7848a64af2c60d9b8525994655cef13240b3227b6afa9db8c2148f9c3363d17c4710b005d8872dcb001b5496a7056d6fba5318030261487220838e2303c20be41fdfccad0c69f010001	\\x0e4c580d642cfeaa548e322a23922274dfd923d58e1403380f3adf15ea6299ebfbe9dbed930ca5168a78abeb7568d876f3558a9306fa96c5bc96fd7ec2b27d07	1647694588000000	1648299388000000	1711371388000000	1805979388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\x958e59b8d4b6d848a14853200976e3800b1733d583410250163c7a196d5b899efb48300b977823cf37d449751f8dea86516a436441542d28a604d579741c03a1	1	0	\\x000000010000000000800003b7579ac5f8dc856afe356c8f3a533d4832f4fecd5d4ae765bb37ee3d4c29f7ea6d8e34f387a90bd1b40350488b6cd02e3c879064dbeb3b17ff68fb9a2ba72a7523f3cfb1ff80f03ca419969e0a8999d7d1d003bd77f3e11cd639d7967753de46f687015ed85c76456eda3a35072591600216bdcb248140028c41b87c8b9fd519010001	\\xceed7874be362f9d9ac1d478261b02880762d3fb6e1eac7e543445c1e3d4fbdfdfffaad37753cc018287def681c2369c4a30635f092f72c32a3556c5461ac90e	1676710588000000	1677315388000000	1740387388000000	1834995388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
274	\\xa026cd162630da830158437a462ec6f4ee352a33f7cfcb0bb3e38819c4ffbf78bc91ac5a777012c2daac249d7594be434c735ff301a6287a840867bcc98d2ea4	1	0	\\x000000010000000000800003ac999174a00cd29e8d70c02b77a11751d8f110f9e32dcdfa6cce2d7202e59cf87cd47dbd8d45254eb3e4322c438734b422687ac934893bef30379c6f178e2bfc3d77c22b1d2ed5f44a5eb363f19afe820c30dce8477f39b1c1a8789b175821d3ade1453c40532ae68dccc0c029d1ee5daa409cc87b79de70fa4c17caead4df0d010001	\\x723fc6a124db2fcb312574ff62d2efb56e6e22c05e229c85c1df09997f36ae4f7bc78a9c1e7681b5cecba883f171de123c2e55d850890ab0a7edb94e6449e400	1657971088000000	1658575888000000	1721647888000000	1816255888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\xa302f8f2a9f105637d857502453d4d1e3a06dcdaa5d630a096b56b57b7a3c63abbdfa3fb140993bbd12d4d6122121dbba07f059b4aa506df76e2cd5b1d037cbc	1	0	\\x000000010000000000800003bf7ed5bf5262008879468b4202980b8643bb86b7ab58077ac513ddf617b26e4b843650caeac9bab8a2cc77a80f63289e00e58647a7593db32063c53b7a872a499e1acc9a85b9af42683a433a4b7b2c4ad1c0ac54478c02ebe53670594d03c0aa48cc25545ba10ab9b6414d1d42518b0c636b96e55c038f6e9c610e662dc0080d010001	\\x79684d6a69a025d5eadf4025b6b18b4849fe83d33f457f8fce9ba5d48159235e8d1cbbc4f95b6c81dc4c7db682954eb5f991655476fbc2f1a73eca2fb21b5e0f	1662807088000000	1663411888000000	1726483888000000	1821091888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\xa7c2478044ca0ee92a66b042540907a37c1c7d62a94655b868a8105fb05cc595e134e0174699d0908cb9b08978ffd00a9ec05fe8f9abe3c0f544ea620a0fd7ac	1	0	\\x000000010000000000800003e7caf25616cd4acb23f64295ce22facabf875a4cb0cec91a401f954575d74e7d5f9d459203e7a5c851e0383f5c92e715297eb396e23b535846b197ec1b4453417f0e879046fb55118690d93d43ee4b88a926530fcc02c8aededde9865cb20c77059781a3f64902c76c5ef7fa6094eeb91c0019cd26000ec7dd4017b120633049010001	\\xebd275377c96560ea67f0d7f5ca77512ac54b9e39760daf94b039ea9a93a957f515b6ebf3def78ed0071a9d1dedb3c7eff0a86b2defe4635c48a876d9b9c8909	1679128588000000	1679733388000000	1742805388000000	1837413388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\xa9628f64c2031f874ee32c2a32b90dcc933eb394d9de921ede8fe0a1ee0d55ef93c80f344d59ae2cf39de820d8abaa3384d173ef64be24cca32a3bd13e0bb389	1	0	\\x000000010000000000800003b953283ac1f009b8ca7f9b689b41743a7e4bbd3f92d3c40f52b4130ea05c045e059f68f2643f8dfc39b0ee0c04e89f1cb65126d76325a3541b36611ff0a8ab1fec2d7eff897e2fda013756ea2752196a9804bdfac0c9517ce0760188d96b6dc41e1e386f06080e25b015d26dc04890210516686fdbadcfa2e96ed5674af4bd23010001	\\x00215ad9649a3997ffcda8bca32ba5b480365716c883970efe88f7dd90dfdfd8b23415ab994443e35fb91f15bf01ff418264803cd73d48913bc11bccf3e38009	1658575588000000	1659180388000000	1722252388000000	1816860388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
278	\\xacdeee34a3ed491ca27dba5aad4eeee756eb532b1f7b74b07b9fc69ec0148987a79bd6ca19b5ec85579a80d500cec830be4146f6ecfc5197f72066a13c17a5ad	1	0	\\x000000010000000000800003d1c1dce28bcdfc4905c396757305790636600837f731c32a33e5ad42a08358c5ecd654f53885caf01fe80ca1cea5f4c98f3708ccc5700ff50884f83d15b207b8f436dd1803e180656aae712ce3dc0d2a842509b8b60550de1948e9c4c8d96eeffb70f564c2f84007bae5ff3d097a3cee138d2d3438eb1e032aff53982680f319010001	\\x7f80a869f422fa5150a95121816564fee70f24de4dd2be8133fc5a6ba70d0b7da614fb7c39c471e4c482abdb7381723c4c2095da4bde5c821887a7ed64e04f0d	1654344088000000	1654948888000000	1718020888000000	1812628888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\xad9ee31598d7b3bc3a7daf9b8ce51f1f831c327b4e73c0a7056bf026251e2794def687dacbe8016de1f6c14ce44a68a277b4dea2e54b49db60b7c878d7fdb76e	1	0	\\x000000010000000000800003d601bffbca2ab712807d5d9a7558b975b1f3800e7b6cec40cc15fea0d5f29d6ddde213e7e7f95201aaf1c75e51fd1a039f2a84f3bcd7886ddd83226ae7c7f36cfe7d0e5526d6ce65764274c1703f345cb8bdf2f80bb691786b49c94caa7f9e8822679a53e94149159b3dc6f9171092f6640a44370d46065f836b30c88296f277010001	\\x6d18e326ad333edb397f1dcdad33694b657f7413d7da2bc3422908cd26406731d46cc5469d5c54f17bdb38c7136208fbe8e9c7b30166f0f286c7464ecd402907	1651926088000000	1652530888000000	1715602888000000	1810210888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\xafca111de6ebe77f0cd8bdd6fe2d697ccbd05c10feabd902046a141f8c33b51b2acf8553baba4f586de18391089120870bd8d66fbc96206915066b7cbf480fb0	1	0	\\x000000010000000000800003e9a6887a21241d785111a2291527ed5201e7da5d5f306f8aeef086a8ef1b6212728818cf3aab85f114f974cbb2c4166b62d9dddc858e42f298c93d219d5665b09c5dc80690d3e8d1b42c645b5aced2dfc74121991a93255ef002465aec3aa75957b634df8426dd30fdf5bb7f9be7cfc24866639f471e4b7efc87b187159cf723010001	\\x2df94ddd3358ed59974805b99fbb3d750a306e840c04924a59fddc31fa86c3e3d88369f9e2d35d658f5953e9df2cc1991d10ce7e0b1e2fe633c661597c0d2f0f	1648299088000000	1648903888000000	1711975888000000	1806583888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\xaf0a8ab2dec8e8b1d9c623788e35a39a227d217dad0bf66f0e6bb874d0a5033ae190cc9bb357afa2e178cb46f60ccf2d86681fcea2ab8492ae0ab2e13b15fc5b	1	0	\\x000000010000000000800003c5db9c6acfa27d039c5e0135389a51322739c4ceb017e2a85d8fa54c107083049711047428bbcdc17cd448a55e51a9a6d14335702ba124364e9be498db397d60268aeec042a56ab6a32057fa46e07f5a5d818e043d7cb1b0f05d02cf07271590375293c29b3f0bf4ea4d21486a4ddba1b11bd94c6bbcf32b2622c3c9484ff2bf010001	\\x7f9af5dada3fe15c994f57b9aa4f2bc16504c2b3da50a8aa2d49b544c8ee05e293583a8dd892ce4fe9904a9d8308645abe300babbddc4b3ded2c86d989f3da0d	1671270088000000	1671874888000000	1734946888000000	1829554888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
282	\\xb18ee3d11951962815f724538b2edcd1ed27dfd4d703c157d60fc3a559785a99fdd91ab870225ee31056caa097a1c4375a2c0d32e41c50475377994f94449539	1	0	\\x000000010000000000800003a5b9306d6ff6cf6aeaf07a98f990bcc00bb1a68904908dec18e0f845b66155d95be32eb9068f4eff9a092098b7b88f831aa3d8cb776964059d3574fda77b69959b7ec8e81fba4d5cfb61112198d9f0329694d78b19c190da25e2c29574dad4234ba51173b5078002d5f4d22c687cda92bda92ba2df3f35d3f7540da8249a7ea3010001	\\x3b8f119d07b5a83fa9a1fed3e45fa1f61e8956ffff3839765441b04e75f0affb1dc2d375aef70ffef17cdf81ba29a3751dbcb12c8ab0490693d5f7a82cc8d901	1671270088000000	1671874888000000	1734946888000000	1829554888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
283	\\xb10a33cf3beca75620bf1bc04ad269aa8a3f4d2df655200b16e64984295acb6b17ca7e74830e2b206c46f5dc1ee6c6de2aa2cf762fe258aef9c0f30a528daca4	1	0	\\x0000000100000000008000039be13da0e407aab54f291042fd7e4a34988777c6f3e9acee0a1a3dbbce1b883453857891e199958e9035493f32efa622ecf35a95a44ab5b52d3fce3aa19529d488e944c53123cb162f7a49610d77bfc7696b05cd1fb9f1f0d62f3a03a9092030f5787af6957758a66f733df430d1275bd7bab41bc3620c30044456c756da8fb1010001	\\x1bcf0c8cd3499ea341a90bc7ef3c920751d21d5f583394191d6512410f57f69f7cef6bd2aa601080fbbfaf579c2a4b25b3be9611cdf171de6ae487c4f033630f	1670061088000000	1670665888000000	1733737888000000	1828345888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
284	\\xb6da441e81dadd6d8836a71aa878c4e8e05f5a1a403886d1fb042077d39e7a03a52ceb72b7e92ed5ce6b66c284ed2a6eb4e5e73365f373fd4f8b6ae55ad499b5	1	0	\\x000000010000000000800003d0244e7f031e5f9590a74ca02e0b1168c72dad80d5d6def2ac53da0f8ec9e4296ff29e676e8f60c956b0962c48cb1d93b97ec487000d717c7cdf94039eba0e7430460bf1737a6211e73f89b0f325a142966e0685921381ff271fae3c88ae92b50485740a2aabc22e57fa0e00fb61853d0304da6424cc12dce0992fafd2d901ad010001	\\x93a21a66e272a186800c27f73a92640e7aba33ceb4abc6d35b4be3c46f48e4acf9a69a5ccc0e350b080bd6d20af76f2da8480fc7cca7c40a02c3837fed284f01	1655553088000000	1656157888000000	1719229888000000	1813837888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
285	\\xb662ae105abb36de0c3e760a93a798a80b268bd45b5aba53e79a9360780e9dd5c5b122ce78d27597151f0a3c37b68ccaca253d9cc1911807154990efc00729f3	1	0	\\x000000010000000000800003c4305733aa4f59910ef4cf1bbf6986b55a77047f1e99f3783d844068221e99433b770b1db64ee9ec8074b71f46e80374d904eaa24a8f51aca2b0153f6736a7ac68b7891828cfbd3304e3e2f9e3c696d05bd33b99ea5c0cbc108193ed0296dcfe21fd0abd69ac9f2dbff2819d477843e7fce8ca337fb7cf8bb65d60418bc17ddb010001	\\xc0b572c82988e49b8041c030d1a78d51f8117ad2fc00a277a2eba6225c9026d50d84800b110486e6bf34a6cc54623996f067649c63b7547e404a710a35f54009	1669456588000000	1670061388000000	1733133388000000	1827741388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
286	\\xb71630c84f43aed1f603ee84d17d92d191200d2094fce6a7fef68068d4f16bbc8ca0fc45e7c3624747987bcbb970fb3c04bffbfb15fd1d6e8dd7b042bfea8ef8	1	0	\\x000000010000000000800003b5402c17df30fca14778608e8e1a31cdf7bd2ecfd3af5ed07f50293bfaf61e24d264d7070d18f8854a4c4e851356c06facdad0da2d2ba3ac9a6c8c34bb3b39ba18742db9451aaf9e7342f3d82c6097e09de9ea636ae704ace47bdf107185afa6b645f8ea9139f2036d19b4db6afb45218ff36678ce33c503b8a967afb5e2f8ad010001	\\x70cf8948f160a0ed1c6f555963abf8e8f799d2bcead03af55e1e4fe9e8c603df34521ecabc797536fcc14eadef4b0547ad96ce859b441c37865373f886eb4a02	1656762088000000	1657366888000000	1720438888000000	1815046888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xb7fe2721d720423f9f55a585dc3c95e027b6d7f2f5f7de7267d7936712abf489d82e04c4942f419cdf2e80f4bc207e5765c063dfc02172f89e9e2007f9d8b3d2	1	0	\\x00000001000000000080000394e52cc26632a9dd30144e7c387526160b8f7edaf745fe445a45f8ddffbc5112d2ca073a190d7599229a523732ccd0179579da1f9f4b46505a405db68aae23081cc52a137759d629285c9e0228bf5360378ec3270ddfd4a13600341731a473e19d7a98ac0c7e85ea1ccdb05e9b01b2ec0fb54ae8fde2d1e14379f7f4eb0eaf4f010001	\\x99040bbd34a8f263580b1785a31fa520edd2a32d2a3d006cefc8cce876f74fab47c93a29a93eb92a70d0331d79981e413c57a153c446585a16a622998bb4740a	1658575588000000	1659180388000000	1722252388000000	1816860388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
288	\\xb9c26e7443876f2cb17e252ac1f00b076e724e5b4aa7e11aa271ad1c92ad3d73330e1871ddc8983090db210f4d9fdc81d7005ac945868d18313409c8d7a44b06	1	0	\\x000000010000000000800003a33259af48c5d7c875633708f33f61750ec5d9cab4455e3257456fae3d38653c2310feb3a80c06a4082908b5d4b98bf245f9278da0ef3b332c5ffe61545d75d37656d39e7a81f137ba0c09677f50024c20b87b0d3231a7518ff95aae4393f4de5e5de54b0cf49832c88336ff4bc3e6d3f443192bbf61b40e160616b209fd244d010001	\\xbbe41b16bc524407459d85ed0e81279002363bc000b398a1b56492867f8bf18343615fee2ee63270524faef6e5701db8f31f00115f02be14446462a8b9a0270a	1648903588000000	1649508388000000	1712580388000000	1807188388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
289	\\xbca25050194b8a3d8e2500f49688cab04a7460d01bb7bc255cb0e25453418fb19fbab3694c905c248c37f751fe22b6d2914c916baf77e1980180337b41dd78eb	1	0	\\x000000010000000000800003a866f07b1305b2c19a9697dfe03d00bacc18b71ab5923dce53846ec65d3bf807876cc6a7f4183e1948036e89797807315155c28331fc37da3d404c2e2299009595d182f749a83248fa2bb8f795857ab697c3a1973ec1f8ac2159ad455cb0adef558ed92fc921714ef7521cf411266b928bd7a3a5839b1efa3513d6caccb86915010001	\\x22983c89bb7cb6a731f389f2d4d0f1ac8e7440b33b567189c226b262852cd46dff3d3f7b8f84e099934cfa85320009b045702154b06e5b270d2205e78dcdda08	1652530588000000	1653135388000000	1716207388000000	1810815388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
290	\\xc2ea3142a2db696700b3c0cfec721402a6e96dd204fc5611c8ed5bb4eee21f4cd80a3aa720d3241ad6c7094de2f8c62c0c422c1524a3ceabc13acf415e5834f2	1	0	\\x000000010000000000800003d649b68d72c809243d75ecc26442ae996093f472239b38804c48aa3a7201e7366cd4f82f8c29dd76ac8a836d1f831d4323ab09ded8f91b8fd6eb558b1cd5855cf0a53eeda55a979c98687dd78647667ea32160c45b82ef213ad85e6b844a6b26b89e9f3e4d7f9468d5043ecb81598d710e08d1740b44142b658d168060abd1ed010001	\\x0bce577f0e4226c9d5208e7132d95421517d5fa77a22de6f33ef385b787833f694b63c68ab75e32b41237b91cb10f2bd86925cbf2d590e6047c1e7de35d55308	1668247588000000	1668852388000000	1731924388000000	1826532388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\xc6123993bc3bb17fb9ac4793cf250d1fa621601534a9ca3b61907bc5959d044999dfba841d07c39124864a039d956c304c0c636d0e3e4fa8aec5b1179a1f3d2f	1	0	\\x0000000100000000008000039fc468ed7d6d4d45f0f853c913e88f65744e1bb759dedb790555bc9a7ecdfe094a4ead526ca298dd2ff6b62e6042d0c8fcd0c63121432cc9e136cf6b88bdcc73ded085dee4914485359d75af3b034b3cd43d101859643e52fff32812f63780686eb20b6be114a4b50997134d4ed99ae7b841b283fb5578f6150b198202f2cae1010001	\\xa1f5bc43ac4a5d0a331dea717a972f93b0acfa86593323b561584652d65ed956062af1b3ecbfe9e8c03ebd89ded0420f1ef3de3556341616a129c17e62db2702	1664620588000000	1665225388000000	1728297388000000	1822905388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
292	\\xc7f69cf2518d3dd8c95ce5aedb011d331fe1751e42d228d302766ed10208445533d54318b1833111bbfec57ec987767613e6cca97f8d60bbd1561cd781126118	1	0	\\x000000010000000000800003ecf932972074f19c0259a70cc5775d0169ef08e1bb738f1c78ae92f564fa3fef083303d0d44c9e40cc37b1ef4f912525c1902892f274f1e6acd8ac61d48666c5e24d46c90b7774ab1b80421542b540d04f620fa48e9d9d23291ce84785a65d478c59de4fc2c5f3f8e709a049e1dce478c01dd2ac3ef5506643491ba81961456f010001	\\x8aa8f30044f3c8b0b28d566c12880a2ddfd0044f4b5ee51211ec96410757225a20f00e7565796e65361fe71781c01dd0b793d6374afa6774b2931be9a8ed3b07	1659180088000000	1659784888000000	1722856888000000	1817464888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xc7fa635d65d248db6f99d3858c9e4493e1a9d93cfa954b322bb87aefa148b885b2a944fd861f1c8ccbf28ee704c84215126b54ce2e4ad15de43f0399faaae854	1	0	\\x000000010000000000800003e731be7789aef6bd7db30ce3b2b95a8d89e20d5377f48271b113ab2b31911a8d8626514beb80489b9c70ac1e087cdfb4b16d86ae594688ceff4d0c66e9e0f78b4b0b435b8c29eef6cc6ca609137e867a48aa9d4fb0717f1f1e4565d96c09354574dad70b41e8e1da87f2a87e61c1f1070db643eb49685df3bcf64fd9ed8274dd010001	\\xf872a79a9c14fc7db2b42c79d750151c8e9371c0e98c667d5e43956e17c4611bdf3725b5ef28ee63c624ecb5f011bf9d01bcf4a4e548722e127dcd5591e39803	1654948588000000	1655553388000000	1718625388000000	1813233388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\xc93a02acc1a0169ea81271d8e1ea2de61e03131dcdfc5a9f1411a048ecd4cd314ceab4e846eb9a0d46b82bd65e1f183501511a1817c05ed4c1b7049e3bafced9	1	0	\\x000000010000000000800003c003ef1f0621bd328945323ee25c3456d6ce3f4e23e66d7bfa13ac3c7e6b9a03a405e5d6a694a657feb72f85398f0fa8b29ad4977de32731474abd01a0abdec42c11f2412b18c82c94868f356d727b7aa05cdbfe4aba263e2ea810cea7b8665af989d5478d55930e162c4311bc818bbdbbf3afb71265bf806f88a064d35c7ba7010001	\\x5e6f7661d6f5dd01561cc3268b588ae31c6ac2cc715f7b8c563a8a2bdadd14e9919d0c8e6558eb0f79851f1b035fd40f91c74109ba1041072683eda9e5bc590a	1665829588000000	1666434388000000	1729506388000000	1824114388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
295	\\xcb2a926adfe738ff2d3fb56593c49db616f2b45b0120b4d2c3c20f5bb84769aef009ed597f981fd551ebadcd9ab0570e2db8f493e95bedbdb3c810745ad8909c	1	0	\\x000000010000000000800003becf62876d5ad6a3ba8011098609e68e81e5a014c837a58376d84413ffcd4b11e1c8e6f971e4431c41eb6f01e808e02aad68d669e2726d530fd6380eaac80adf7d01901acbcb6273d5f6e781b694cb10fdc0dfbe7eda30d0aceb418f89437ef4811fcd1cfc2eb94a2daffdee014967077e5d1b162792995b6775accf26a608b1010001	\\x3a3433c4a2131ee3f874b390a62a49a8ce3901b0c10474e083e3030e61bb08e4f241c087a6feb2f3ba25503a1ed620112699284042983b97375e6356c150fe02	1659180088000000	1659784888000000	1722856888000000	1817464888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xcb763b5e619e4ee34a1369c9610cff3099c1c22b2342ad58a661eb1ee076aebd88541259fc0cb72e1f56db81db502fa5bed3d3befb5edd794e7f548fa09c6ab1	1	0	\\x000000010000000000800003cbe04be8c5ed03019c63b2fd698ec82a3f1ab55736b90ea566d9ae4464fb734a3f9b1a8c14a531041d8b5eff87a69b3de6249a6b53817d8d2555a2f5c4723a8bf1c44ee6201b3b263b609bc5b9aa643d2225ea639fee34f4e5784d9a9eebe8e6b78f9d6b34f4e0b05e16e3ebc9446fef1a46dc5656e94a609243570e7ed598f9010001	\\xf6e5371308a9e7ee5c02385f48df4d152bb0d1e19ffdd8d7da808d1683bfc60116cdb9ca1519dae47f2055d37a31730f2db0e073526e8fefd935c83916928304	1677919588000000	1678524388000000	1741596388000000	1836204388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xcf5eb885203fee6ca59598d4e592a453f92d5d4902d6992dc84f556acd528b22632740b18a25c4b3da4515371d4533cecffecf784219ba46061cb59e8db819ab	1	0	\\x000000010000000000800003be3af6bf8c1d972660119fd5f548d36e8a4b5e2e705ff83980aeb48682d1e5a7b45a4cbce8d2908b40848b227d0c970a2aa149aabd0ddeb38298226363464ceb133afc3f36194284df52de8893e9ca4c5457d16c6df4e5ecc29120809c2d17eb240d4561f2d26b2c909e3cbdcd292365dfc42418ce974cda96d86d1a677fdf7d010001	\\xf9be9685694bed947e6e40f332a9c00cd1bb3a7bebcc57de79e0482e0620a618890f281b026531d95360a4074c21a513ca878bb49b3c786f90115fb4267b3e02	1651321588000000	1651926388000000	1714998388000000	1809606388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\xd4f2b077abceb9e3b96ebf419db2edce7e45c3c6172a6e536c576cb891fb1961eeaba3ec12f146c8c5cc8462cbcc42806615b2c7dac7ca27c82784e87d7eda49	1	0	\\x000000010000000000800003c2f22b8c894732b389e9808d21593c6002469ac524428ff19fa6e20a5432e8f823f4719f398167f2a66fcc6982465b4b8ececa78066e38e1106491624dc95528c588f83bcb9f6e67b6e5f44b52aae80f581401ce7cd0c2387d889da19ef7f74699c4faba1a611797f4078b174aaadde8a169bb3d1e07cbd820ea547cae55400d010001	\\xb5c04c7022fd1834ec534318b224df90f16ee054384d48cd2186d8507aecb6641c7368b76647105d069a298df815487fec6d59e5f2b76efdbd087cff71e26c04	1671874588000000	1672479388000000	1735551388000000	1830159388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
299	\\xdaaa675a5489ad2f327fed38cbeac74571d130154358be5fe66775965b1e8b2d0e57e40299ea7cc74270283b86aef195082effea3727585028b777bb1e462f50	1	0	\\x000000010000000000800003ed62944ee567157c7019f6d7fa07b3127c528f9da3e416b994fb06f3db522b46606eaa9f67f1754eddb74cab769b58c857dfdaa1e46a342a44cf25766671a627a873c20a3ee8157eb3977efaa8072088f4b431f45d9240ab7e6a1a35783daf592d5952ac0eda4bfe269c356406168c28d3a43dcb724458e40e6eea783753fa51010001	\\x22b29a99f83067088f660471e7541ec27be99aae0022979ed2246dd2bdcabf149e0a53e4bc45fbe10c496e950de3b60250cb985bd6c900102aa458bf19f0700c	1678524088000000	1679128888000000	1742200888000000	1836808888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
300	\\xdaf65c6d65ed90c06edfdf0bc0cf29e0ad0918fb811156e7726d24b887d1312af19499378035a30e20471fa8ca93b45a56abc3eaca6ec07b7343d8c5f36a1eba	1	0	\\x000000010000000000800003a6545031ed111810ddf81d6c4c5bf704704061a3f49ca4d09d681263fd4eacb93675b107dd3a0342bbfd7326f3e516644c471886dacac194b91cf7a9232f327a03f52d6b577973cacc4cd20911052416bfab09d03b47479abde6996f5f44b1276d39d8fed8aa69edbbefd851181db36e5754def2898046828571823f9c1bf245010001	\\x4df47f5383760f579c2692be6e8b811768f111fb6e16ee916ed8398413120d36de50e36fe9e349257dfaab1f3a904b5b43024f7b257acb309067f8d7669e2804	1655553088000000	1656157888000000	1719229888000000	1813837888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xdb06c20988be3b3aa693e7e3326b535009d2ff5c0f5dd826300f18687c8f986b297bd6a2aa736dcea6b8851eed59d1beafb66e7b5e132570032957ae9900c3d7	1	0	\\x000000010000000000800003cb7398d9906a67110cd345d95bd85b57f7a6dc02cd8315304d19d4051b8e8269faca1f74fcbe0d5e1477b811008f8f5f2d6f58a5ab47cb6402b76838962c42ba2b4a9bdd13b46ac0c01ff2035461604c40806168ffd45bae8777d62e9381652efc17a49e05c38a1d71378078604814af6ed41d56f777132e122182aa70c3da19010001	\\xdc8dd964b7d85f12e886c4db170c24e01b970379f71343c6b57499d4ff90fe6ecfc2a7a93482aeabef5b1905198d287c7d3662710c2ce70e88fff913c91cce0d	1661598088000000	1662202888000000	1725274888000000	1819882888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xdb420b589ceb4072feefaa7180d1e58ca302dd1b7002964e3a3fcccccd2c298aad3c69fa5efaa78e130503574a801fe2fb22948f8f1a6df830a03b33bbcf771f	1	0	\\x000000010000000000800003ab697b1637cc1f8745347b56ca50ee5bd34114280eebeaf56ccd887ae949bbcb384900e9ebaf8ce89554d7cd92fbfd210db9bc432dcd1f6c3e9a33d709078b41be5ddaa17a75c6d697d71590a92a064ac8d76a2af328f6ef4660fdf108fa42189c5ed171c2ce56b5810b9a304d73a7b53037ad55e003909dc4cb6a07d5e3e86f010001	\\x60550231bbfe64e3d0c3ca6e235812e4b54da3761479fb760aec2066f498d50f7f230406c5b9cc7051ba87597c3afec39664011a568b062ebf6ba39aae1bbb08	1656157588000000	1656762388000000	1719834388000000	1814442388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xdbb204309de1da2c3968c5c116b08b0ef73556fe89f466dbb7022aebb3ddcf9cce4f33af7c3fa31c915e7c35816d7d2fe4e663466d2f13e3289152381929bcf9	1	0	\\x000000010000000000800003d6d823c4e37bb750f63274b2ff30448609160b5936b15bc6f8aa88ed6ce63734ebf62f4448685bcda84720a21a372cc55f7e64b9cad35b5394bf4f5d1d5fba4ab36ed93df03c9a652ee32dcf01b6d258618e54a128deae9b6fa65e77fca360831606876622c0b375c52a9947d94c59c62df7c41cafd702f981592f8685982733010001	\\x2823d630e07df53c8089c79f15658e7904e76d73022c27ad982d5fefe287fbd4fff92993159901a6b9cf3f5751a6ee9e7be0adbc27e7e42422a02545baf87b0f	1669456588000000	1670061388000000	1733133388000000	1827741388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xe05eedf72471c8eac84ef6bf0446a32f2081cd8f62f6cc74c54c04456192f09708f823658cc383bad146272faf761c553324db59bdcfd2bd330ac02655cb49c5	1	0	\\x000000010000000000800003cb8bbe27f1f9abac38c143957bc52dfedcacb5b6348ed53f236fcd2559ac563f730111d7d08a5b0023f2155c675ab3989b06519dbabe7ab6dfb2bd9a4125c6f62ded00faa226ccd741971c8f5d88822d3e6d9647d1e8c72618f08398f91abd95b2f4e939d9f372735b79878fd7c5ef0703fa02d18a73dec94b05e7a72c8f747b010001	\\xef99ccaab49fe7eca2f907db9ca26d1562cd8eb03af87d1ea1c3c2bcf2e73f889662d6cc21b99710a9805b60ae03c01438c2797a595a59eda5561a4dffbb300e	1675501588000000	1676106388000000	1739178388000000	1833786388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
305	\\xe5c20217a30a8bce943c2d37b9e4916399dc18a0b300387f6fdfcf51918e048b70e1089da9c90f6d2acee9f37b95825135bc39cabebead3f480cf238c930b697	1	0	\\x000000010000000000800003dd6932e72ae60dd97f822a1879a30429a154c5e79b9ff58806616532b4ca567f420b3075e49bcf42ea5849f5c1c5119f21da94e130c0c26953c4ecbd4310bc1ac8a7886cc47568c3c3507f11f09698142323898b9b645f70409f951491cbd78ad823180330ed7cc4b20e01dca2f94a3f3cb4d600baed9a8d7a653397a47c1367010001	\\x1dd5e7c9ce1ffe1197ed28a4c77b4d33eff7da2272ff2c704da8d9711388ad835ee97fca0cbd0f56df8b41b18049a6ef4c7e12a80c182272d0ffe01a0417d00d	1664620588000000	1665225388000000	1728297388000000	1822905388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xe7aabac9d1aa4ba192ad64ba99f7053200a8d3035a7d7d16a3b48d2c0d994eeed92dd02079aa0403e5a7fe4a44af3d9d373b0f48ce3b1dcca84fc33be7f9d131	1	0	\\x000000010000000000800003b95fa25db4472eebff78cbd3b5e7da8cda13c916844036d8a1767f70cc1d1d3046887a1297c0a9799a4b8dfa5bcf431ff0274bbe5ef99284429cc78ad31dd0e3d510c16c968bc69eeb74919b70d4dde561e4cbcd64f190987d5dd672be504e0554a2c1c0c0db9ab26562ec70157a34858ff21481976b8a8545706cf7a6cf794d010001	\\x5b10e8da1c12c8aa0dc65e99b48ee4ae085974b9438072ef0b53dd88989e2344186a5fc46a41f88758316d604f1f8d60ce32fc52e6a5e8751eb54b7c64242b0c	1670665588000000	1671270388000000	1734342388000000	1828950388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
307	\\xe752dad479681e528296a380e1c387e09fe8a31e654b426a98379ead13ea329183aa78c1cb229b3b77905ff0b8ff014762027a50e48db0c6d32f06b9dd3b3f9f	1	0	\\x000000010000000000800003bbee72612c8f217d726dc693114304edf71ef386c0177e65b4ff114b01af8061bf8cd6362aaeaf13fb43e8e4e32f63cab0ffe8ccac7242f22905816cb6108ae35e3d942342335c316faa0ecd611aeac768345b98795ce38aa5d6f85f31977b4b90fc7a5bb1ddce5d9477e51309828b0e790bebb064954b4a0f27179a7ddd61c5010001	\\xfc69ff0ea643b5de1658241b8e2468296888afe638e958c4a21295e415cfb2a49a04d8642cd8006afde29b79460663ee7d71b35a5d17de7e1eb17a5c2bc68c0b	1648903588000000	1649508388000000	1712580388000000	1807188388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xea86b1e50fb76627bafaaac116aaf28a103e677d467c6f919232234a27fba38155e956548eb7ff90a1e6a8f09b9bacbc8bee1375faff98af11ba538935e1c66b	1	0	\\x000000010000000000800003bc31960e939b012ede8009f151cb52c8a036e7b263d275f2cd1e2cd455c8f757b114d5df44e9c271e48ff8556abe0505ce6edc6e6fdc181b93d7f1b46610dbba4f36c93ea2f18efaffa9d79bf6307637920e333f7b3b0264947fabb2ba8d9edd958918c802960144a384a20c4769dc201a8cc514ead7449f6c58b910a030573f010001	\\xf794127c284d5efef520912ce6dec8a03938c9d1cd5a18f5aa7d5d1670a63f27ea11ea74de68b99026b9e05a8201b07966a84432cc764ebf567efc174059120c	1650717088000000	1651321888000000	1714393888000000	1809001888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
309	\\xec5af04f38be056d3d94fe3892a78f9e2b726ce71641f6171393a0fc6a05dafc88746fd52a8a336165686eeddf1d30290dc15bb28192165a25e57b99a974b71e	1	0	\\x000000010000000000800003bee170ad74f940e8b8d1d509faedf878428dea55174c2beb88182a83ab35452a6e0cf661c883e55261bb62dc617a2fd82f213bebcd76f015f70630695920137c06f627aa02a86388b3793f36a0f117abfe33ebddacbf97d30220aa79bfc260d3f525f4741dc9e7b65a3c2deffd91622c9eca376a35345e0f2a2735dce2451255010001	\\x0f2d2ef01504de810366b495ed73a3327f2da35c3be9cf8a0229892d491f78e23fe5499a11a93ac72b5d5b51e6aa2d9784981051b4df66250317cfdabc152a01	1664620588000000	1665225388000000	1728297388000000	1822905388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xed6aaf76f50b117226cda3d2e9cc667437070a54767769b99e97272b0595c624c8d57dba8cb531712f31c8b2bfa3c871ecbb78bcbbb95f1e01c358f208f46ab7	1	0	\\x000000010000000000800003c3ed7e7eb3e87457c9ac86f9f5dba9a244e5c64e1c54e1d16e42ed8d44d59466c12aec9cc5276ee962ecf9e2019949f373313acb25e71a9b08c9b1df0106048dc1eb07f2a3754876467421a86874e0bac6b8d84101891f5deb94660adf15be7dbb73afbcfc9076a0b7cdc9ed438b83e21dc4b4dfbba3efb1becc24a88dca2163010001	\\xf1389c3d6cf3234c6afc8b5b129ff7cbba4a1b680c7e592ddbefaef55af1daef6791090107a2128e78affa2f68b035245f5b0f13c3c8b4f679bfd6d2cf657005	1670061088000000	1670665888000000	1733737888000000	1828345888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
311	\\xedca3c4a955c4bc27b956f961f35a9c97d455fbed2f24a8a2b851eef0517b6a6b5ef1a3e4853fd688c5e7df2090eba7327c4db118739a64426c62010b4e6f1de	1	0	\\x000000010000000000800003ca8bd194fbb1ddfbb4839809543ee904044c43ec7e48ead5577e166f087fe707f9c84b34113c47985a5459d01c5b8ad36b0d62e312750693b54f76b2c24c46ebee500735e5184757778cf469229dc030e43b583cf4897ecc33c97c8ea872c8972628c8c3f1412a4128704c53c9940f25d0b26b38ab97f875f1e9951846722477010001	\\x6b8df6fd6563fde1f07b0f7ccbe1bd3a99c5ea8f15adf71d80f19481c0aa85f0923a27372d1902b1bc7e5f750bacf68fef78cec943439568b21a3a61669c2001	1648299088000000	1648903888000000	1711975888000000	1806583888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xee8eddb69fabb0369bd72b0f41c3d83f2609dc24217b47a566a18919b2d3807c21617563b094853aa804d3b42fdd249f7bb388bc9b2844f3de281828f682318e	1	0	\\x000000010000000000800003cf8b94626f7a081e04a25e30ff66068274aac09324b9a7854bb2d721fa23257b265fb80ee0820d7dcc406ffb682329867b36230041978df06d4c9478b66e19a98a1c5c8f368ae27d192aeef549499f788c47291cc27cd66d75e02e2f0ed5f6540effec1d41f652ad87e614c4da2341728ed30436bd26062bbbdfd0ab49838f45010001	\\x6e2c84e7ad6e188cc092aaa88319eab3161f09d27a1579efe33fea8cecf41187faea3b44a4f15fcd7255ad352edea2aed160deed63719013a1d5f58b04632904	1665225088000000	1665829888000000	1728901888000000	1823509888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
313	\\xf0763d92725fdc4283ada239e4f0692f845a96e35bbb1cdde3501463690fd4dd8d26f9cee9a84a4b3c5971171fa71ab96e0247c61065d4ff13796411d721616c	1	0	\\x000000010000000000800003a846a7a940def9711d217e0cd07a0e47d96e016ab0ff73390bfd03659cd1058af46e601a17c780d5d5b7296d23373f96396c28dce5e567a021ee8175afecb850a44fdd8fc85418a0179bfbc0918c3ae9961559042a14959df13b1a99908fdb147179c4807d7869612343e6aa5db93feeaa10e82c0269dc438e1f53d927c4e449010001	\\x81c8e1518552ed4e72a548dbea346909af12eaa108e61aad05abe322a904a1f574f66271022efc9e9e1e77307b4c7bec951815ec22e1624093c4ece834369505	1648299088000000	1648903888000000	1711975888000000	1806583888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
314	\\xf1e684344995ff31aa99d81c741e8e325aa4bc1ac09739393beced1ea15de4d131dfea94f64c68c9d72d290763a14bbadb9689c9f1974a3959d42ba7cc246e62	1	0	\\x000000010000000000800003d4a85b51207b11c9602df3c607c8950cfd074dc966fa8a12584c1c95dac5bc3bf785b46ae29ddbf2dd297dbc534b89b54c28bd75e6f855a494ef1ccea103d69c13b64efd6bbafb89d73a4f9faa2a5a11616e1535ec4ab533ed9bd934465ae263b13bff1c2f4d2fff079e8f9efc9363fdd171d65ccb45990cb429d8d7391e6e05010001	\\x79cc4da4cc4da745c05831d85c38f14ac26bcc0bf174d7e313105bb83a1f2761390eb1650116366e031a1e87ac3127dae4c2a16253cf2de43b5357ee86b2600f	1647694588000000	1648299388000000	1711371388000000	1805979388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
315	\\xf34e6244779276d4a73ad2d26ef49ffe7143433c9d8bda52ea59acaf52aa8629642ecf78cba6522b45868980b9daac616d1486706a0b12d729718623c0c1e54c	1	0	\\x000000010000000000800003c08a345ba40c0d29ea11b6fdae02e3cb0ac9f98af47119dd5c2353007eed836e295741cc8567b3ece4eab00e00599bb3eb05482adebbcc19d0e6559d07e186bc9e4d341677e8ae0b21881c858e3f54fe86defbf8df75185c3c609063aab22f07b433de0677d9df5a5ccdb2f9e626cefb2e50b0c96d41b0bd3f1d6c0f391c1251010001	\\x76dc3700ff0045b48c2c0171e0325a534d88e7f51f638c98da95050a06a6e152a4cefd74d133c64c5088c9a2c16335007e71482dee699a43bc462a6d5cfff606	1655553088000000	1656157888000000	1719229888000000	1813837888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
316	\\xf792f7b379a0317c01df232c55988aecfd1994667f4980b18ba097694caa395b562be53e52b58d3206fc4fc1c86a3dd6891d2d9eaf0da34074f502dd1f17e94a	1	0	\\x000000010000000000800003b2e3e77bbd664d617887ff767aabd61c54cfc6b692d42f2fe6c46226165c486693b6cac7ebbb4b96413a0f397e063f42263d9b6ff756f9efbdcd709e0994d322c9a5ceb349798b607f0ef97240bf01217399f17e5d50226dff4792f53ff9c362256a857c5b57bca28ff2522c772a9e43c3182646c1564ab3f87750f1168aa961010001	\\x458f80f3641d0772e56a38f3dc8a3aad7be2dec509c653ac88b625f0f9bf5d79a4aa49e3a17e253acd9aa34f23fb01e55be1f5504f450e5545f4f4b6333b3e0c	1677315088000000	1677919888000000	1740991888000000	1835599888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
317	\\xf73e7ed001a96a47c03231fc2eba1ce5e46f2518652bd697096e8bdf43dd2925a4a9c33b6fa8aeb49c4d343631f652ee05f831688e4a33dee011adc52583dff2	1	0	\\x000000010000000000800003dc02beb78cf531ebbdc7703995144b8c4061055f4bf1f25b11f35629089f2bcc60f448be0540f0cf216fe1c0547c3b8a820cef15c6c6aa97a7c25a1bfe6dd60f25cf53c0346ee2833fb4484c323b5a6f40da1cd88659b7729bbed917930ef3a080bf5f6de41f67333d03598e657a105be1ff55c56cacbb15c911925f21a10f0b010001	\\x1202cb5e2ff0dbd3ea984938665ca7b8ba1c10ebfb4432a656f232f352adc23aff0dcc595ddfa8e037a24dcdbae0a1149a8c12e6455112aaefa5ec000360a702	1672479088000000	1673083888000000	1736155888000000	1830763888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xf94a85e2c20f9f5f3832ca6e346202ac44e8a85102cfd56d3709fd9b3aa2ab3bced2c7b2d0d9b994aa3b7727f37af0098aae40c436467b5ebedce44df126e68b	1	0	\\x000000010000000000800003c78c23d493d8c99c98120515c3616ab073f175ea55f291ecc2ad908ded54aa1b5294b44d08b5f6543f6a49d45be8b4df944addc4a66f565f80c5a97c97aba3fd34e5485502ab2bd0bfb9c99d726d7ecf1bc55dcee5b04e0608c6f8c8ebd88e74c35357a16e30439c53e0bf495b72cddfb20fd209fee240e1bf13bae7c5028c9f010001	\\x1225ff881d6f1d3535e53be7c1c228a4293ca35d0dd9031602506f55881885916476de1fbab9048acafe61bca548417631a97e2e268a687e22b6acc02e492400	1648299088000000	1648903888000000	1711975888000000	1806583888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
319	\\x048bc8c5e21324b132edd3352cfd20e6a088f09d344b50b8325f13ec10fad0a18a99a7ede2cb7fe5516374c4e1524a4ce1ace6c50815218180cadc0e61edd883	1	0	\\x000000010000000000800003b7c103cb8616d01cf7bfb0d10b0c3b78a6f719e8fa61c2a8d7dbe3444756038144d42a8bf21fd29a927e4d10d0a1ab93b9327e028a133228f443cde02e076c5ebf06373db3e7c640b52153bb77ac371fbbf0e24c492bf32b8654cac2664c927b1a1b492c4e499d5452c42a8061aa3cbc3822437700753dbac9a3bd5db9cfbb43010001	\\xb227ee135dcf3bf00d943a0e5f209b5e699585c07908dddb81340930dd5ef198650791bea8ff83aaead9012de18c64bfd73dc54e1775f6d9c4b965caeb23cf0a	1651321588000000	1651926388000000	1714998388000000	1809606388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\x05d38daf58ff826d4a183e130a7ce0394c5910a3d9b982a5cd25ba31fc0deaed3be931509206a94ea7088e396ee331975d013f0bf598407c9c3e6ff2637196c5	1	0	\\x000000010000000000800003c5a62856ce903fe1a110b6aad8222ca2da5cf7783aedc34cbf1620aaf66544b7bacb26d0c4dee2a22eb088f66580444b8ce46c399ca9369bb06fb0210c32016ca68344a9a35838717697b57026c7e17cc9cf788d086af74a93b4f495cc04e2f3f9b4821a27b27e13ce8703a1f7682f3166b7d3715bb45549bd19e3173db5b5b7010001	\\xb4c3c3e8afb40c562ee1226abbe24eb71a94b0c7e0a05450f3e04d5abd8441c131d094977c36bb780b1e5d95fed20e49cebdeec6575cd173cec90dd101548009	1673688088000000	1674292888000000	1737364888000000	1831972888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\x0697415f5e6fb82ff7a1cb2a805b0d992a7fca8cc09a9bb23f7e27903f411238b74b40536aa3b1f466ead6f2f552f404ddf83a1dc3a153a4dcd013b9e321ec25	1	0	\\x000000010000000000800003a725984265706ce259546e8ef9337f0d370985472513c383f1fe97f582ddaae31499b9d072bc484eeb17296de5f4564b9d6bd006252f498bd901d5316246737de0fde73b4e9c9db09121cac969175e09b04090337c5206dd55174a7bb5165ed0293875efa71226ede7472ca06846422e7c0d7d70c169271d18defb56ac09d9e9010001	\\xa8b4e05bd924a557ec8cfc694550a175f3f363e78888a694233411a265af555bd1ee831e47da8c3e6ecfba856d2491c16fcf73d61285f45b1466ff8bd05e1408	1660389088000000	1660993888000000	1724065888000000	1818673888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
322	\\x07eff0bd52038cf1a841540b6eb0e847d50f4f95a357dffa6885cb57482c56df9c67d7f6e2ae2bca1169ef9a5a8183ff0dad8518196e03ae9727d6744b248e8a	1	0	\\x000000010000000000800003c3a7788f97011eb6c4fb0563c96fcd14fecf4234e0d3c29fb985d0c230afe45b221bde2f922c13051d9bf499c1104278f1350accec15218c9f398be54160e67d36a76928bbca1452075a65dc30f15fadc6b34302587cf2fdfdb106ed03725f990b9b39891f000ae01693b1d4d4d92159a08cf5049fbc87979cd045398254121f010001	\\xcc5a9f91b6190a9a4834bba3cc99a1a64bd6e39ad7c4443a5ad2f9e906f87e1b3375e7d90bf2fbbbc94a86602acedca1b4e9bd45768858d4d4667f8702a2d60d	1664016088000000	1664620888000000	1727692888000000	1822300888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\x0e1f9cf16f14d2d747d3be656ff9d7679ef4130ecdc6ad67162b8da4b6a43031d63e93b8acad8800a1a2ad3ef1e08e994e29a7245373f5af87624978705b669b	1	0	\\x000000010000000000800003df7da41495d65267bda623d79c5a0f22c3d964676bb324f8db6c85c8d7442d5aaf6b55924247076e39d9286188b91e9d965ca6cc1441c27bd65b4aa19fc1bb098cfb9152d5f427d044c6730652593a1944667f1e25efdea82d8d01c701097b068b2630c187ce3424a64f870dddbd10c92747f4ccc42d490ed8fb06ff6ed510ff010001	\\xb7463deb32f58d3939c73b25cb95ae7fe490e9435a4dc42dce4abd353b5665f5498f822eae876157c68d198a3ab06fd8d92b4385432c87c43beb97f2bc027d0a	1652530588000000	1653135388000000	1716207388000000	1810815388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x0fcfe51e1f2e3227b4105d3c14b7b751db8369773987ee7c889a3152c732730908c7a8474a1c7ead8a7534e19186fff9402e7677aaa4f1fab000450123caed2b	1	0	\\x00000001000000000080000395402e1a797dedbb7a0d7ba52325e4a55199892eb0ea658a022189d86061dae8b39359c13baaccf8b8d85660ca5c8426b74888a31de75d9d6d673dd80e0678475711c93533d6868c5a39339f68e6f5637d0ae9f8b0360dc7a75034a4397b0de041e2eb217aa8caa6a8559be12da99148ce25044849910867f4b2559e13ca88dd010001	\\x9508db20cf9edc77b55becb4849a5c4062677efca80176b0a8bc0a0f4c1f66311b693bc6c2de3a22e8e9634dc48b53d6c9240ff42522159cace1c39274dd450c	1663411588000000	1664016388000000	1727088388000000	1821696388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
325	\\x11fb623aab3376f2e9e1dbe83e30c982f3cf53cddd74f7cd4d8ef40d1b8ddf2ae6eeae12e5045457b4ebca078d3af61821325c1fc77d8156298c9522ab2da0b5	1	0	\\x000000010000000000800003b5ca80e68fc3d2a34d46487e5acc50ea2fd1ff0473d28768acf96040d66c5905fbde15bc3b968847f59e41c30110f9ecc3e597ee89df2a7bdc6e5ec8b808836697d53a7b7d4ed3114dddba966ee2fca9672816afdb100c5519e18470525059665949f78509cf06c54ad7a3b241bef31c51cf789615961fd1ca8816a48bda60f7010001	\\x0945d1e30362f58738a09ca4e7c4f326ba155cdce3ed29a039e718170aab6d7f8d749c9855f2af0097d97224b0ac9939a4a9a1bc613331fd3a6895c2c0944b04	1677315088000000	1677919888000000	1740991888000000	1835599888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x12470eda0c1f4cc145614e3779403cc822437bff83681b90e6abcbb4331a2bf70decdc2bbaccba69f6e69a23e7ec54905e7c7ab713ea0671c4f729e5d596fe3e	1	0	\\x000000010000000000800003e79b5ad78c8c3116086adc066fa3f943e8a3bbf6f2ee6faf10feff2d9c31a092747f983298bd1fb35d547f2a4680c89feb3fbf04ef3f4a420aa2eabe07596a3af4d3181095fec683032d462c4646662b45e237c48c5e7ab83006605c3ba43bb37c63d112ed4d26bad9e868357f37954cec495242a3f7de54069a0730cbdd3d63010001	\\xb7ab25070d5e828f98132bcb07de5386a8c9785a02867a61b1e0c021475a82a4150dd0873cbd19fac8aa3502238ad9f66ebcf59f9db9bd8ec9e9c5e194f16f01	1673688088000000	1674292888000000	1737364888000000	1831972888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
327	\\x163fccdb1a3447c5ead3493ff78eb85339db54c3ff36ae427706155a7df37d2d636aa2db26b3062bf43547238447bf1cbeb02f7a990834736c02affc14b31c02	1	0	\\x000000010000000000800003d94101a694c205c47d376d9ad29b9bda34f0cff1081d06955001bb4445828554346f19a4f0c92d0c87b1237ff16378ae309fc81a2d921a2bb1119d25fa8f99cd5b218f00dc0e8a9c9fafc784deecfd0152961e911fb6bf5e7b5aaf2233a3c82e0ba325ceb0753a7e844e537a0b8c3c112fa88220df05159cecbe2f27aed73a87010001	\\x37a6ab6dfb20a4933ddc4391bd6cc1512f38a37f54c718255ef3a20817bfbe723c4b2b33b0a402c452b8fcedb4c9f7e0e59a2fdf3a47b435a630a4e273d92c01	1677315088000000	1677919888000000	1740991888000000	1835599888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x1a5fa1a490391ae0303a0febbedf583354ab00ad05919a86466acc18ac41ba2465805ebb0223b116c73145cc1c1358e5c597d0bfb4ef6d51a42cc3443ea1539b	1	0	\\x000000010000000000800003b738729f3f26315a8fc7cefde67466032bd328f6dbe12a63e42d1030b0341dabaff716e83be236502bffc702a150dd9f3371b4fdd32887ed052a0598df63585d1d0a1f9e11911e867550be18e3fbcd55a261348b85c3bd1d32ac84bda5f25cbc655c1963c3458d5ad0c1664eb91387c06cccfedb8dee8b1fbc4a2321c7c9aca7010001	\\x973f81c32f5b7f9748e2f7a3fc7faa9419025d5fe53181b4fce35f4cb3d5f33247ae8da49a9cbfc396229c222d5249b6fb49efb3a4b8758434f0fe3340ec6e02	1678524088000000	1679128888000000	1742200888000000	1836808888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
329	\\x1a7ba44668496e466c3d4718f89f3f957dd29ed7f4a0b7de436d3b639d5c5b3d4d0c247848c9aac96bfde9a679e802fa7ab61c2f7fb7c500aabdc294e87fd58d	1	0	\\x000000010000000000800003b28288c69c8aa6f17a575225cf441df4f4f26b02689dfea507b89576ae70023e1c8b66f6e4271302e2434230f4c63a99fd4d22515a8c521cd133d4df593e72986de307b59346363cc42519c62bcaf1db9ffe58732de053ad60d94f24f70f1a5564105117f1d55c0cb1fd7a180263e6c751a9134b56005985248643c3afda924d010001	\\x9d3e70722f43983ab6df69c48b8f0e429586befdb06e421a0b1f285c155fdd232820cf0a881d9f79b26229067d54d6af8d1c43ec9b32d5fc514059d883876a06	1676710588000000	1677315388000000	1740387388000000	1834995388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
330	\\x1cbb66a9466a7d74714e21156e182b59569ce2036cc77f20484bed5e4449f34d3b5f8d737165e05eef0927736863ae074e4aaa3a5c72cdb8434fd253db76cc3f	1	0	\\x000000010000000000800003c1c32500c4ab15e5d711f2775549b3aa49871fb728e11d31ad2aad77c6c1b3f8229da209c8c29b7c8811c60fe6494e55f8f2951b6d9d4170624f29f3b4b80f47000e61cc8f302c66305dff4f22eeecff5af7800cdbf40d5527747f73a623a43776ba2b8e76242088302f03ecf3cf99db81192eea0f1c5961cc3afda5c6b8342d010001	\\xc9c3118bb7c13613b210ee61987ec71f52ef6cf16dba66a9c18cad0e2bfc7e8b0f7d65efd32fe2d0dbaf65727521714b2802f82772e129e792da72325e0d1b0f	1653739588000000	1654344388000000	1717416388000000	1812024388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x1fcf637fb9c2aa572b7ee2f58201ca655dd50c0da55e89b0a12d5c6a5772bad6d4e6ed29bc845dbb4c108a74d563946515d5c96fb567f0768a4719c10d216f73	1	0	\\x000000010000000000800003ee3ee05c53969fb625303d945c9a026e25d6b93dbe2fa9c6a0276ddf71bef4ed07b5d37a904fd463282d51dbb8bc93cfd4457effd0c4b1cea48374d74e953bdc4b9bc20dbc05d4cd7e657fe3ef39d4745a4a85c2afd09c931fe83e2d48b6ed275087b07aecc362a7b25c1282374756ec1b9a299dea704fcd4e365e05b86884f3010001	\\x84352cee0cd8640bbd18ac8dd2074b8be103a20e16ad4b16764ef41fbad052297922935c8b2d4ff853d5cf7d7b39413eae0faed71da61fd2346093e7970e3508	1677315088000000	1677919888000000	1740991888000000	1835599888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x20c3d29a367a7567409cd6f93a24ed4feaad7c3ae1317cb2ba026948e5b3c270324f8b0f8b157b04c5625af3f201b5e0d1177259f28c8cd71f6c4fd3de27e090	1	0	\\x000000010000000000800003a7beaf441639ede529ac8be91c594445ac424889dd268e360512f3c1507f51eaeba112a9bf59458f1ec7f39b04606afd6835b45b0ba3220866a014c14c7c1471c0facb9b4b7e5da65dcb26909933023e9cf59e9f0f19f519284ad74a71115f1659725150150b68dc59cc250917ba265b4cff6c082a779bbd0dce38519a863ca9010001	\\xfd93e580139e9a0e801804ea2727ddf8bf7e7a332d52ffc9850e148a71f36ddada88888edd81d359cbb2e2e1330e05823dc3816a0cff621b0b5f988100888a0f	1653135088000000	1653739888000000	1716811888000000	1811419888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
333	\\x203b91186e86fc517fd6f353e328a5ad41dbc4c3b934cc517e74e0c68ed557ea41d9bc180a2a87c231493ba8edda5d5d3d99212aa152fbb0d35e92d45431d802	1	0	\\x000000010000000000800003c32e8cee73de5f9215664378efbf8e64986f0a56de84b19d1a9bb1f1ebc1858debb9abe74e62f0a9848dbf20494634d3b87234a5e0f75c03bd4dffe14e7b89c19602f51d6b15c9cec29e7fb777fcd06b73e3148f30cd568017972dbf061edf3ff31573f9d4ac4382206bbe3c39b5b4f3c217564838b90fa064e7d77a49a41095010001	\\x8654e2f7cf2a681048b1bd2768c7b8f269d743657eb98e386fd5569d570108bb622d31c73aec9cfeb3ef5ed69c88191a22fad8d24167345884c512e8d0ebc506	1662202588000000	1662807388000000	1725879388000000	1820487388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x2193a4a99ba13339f145a00da5b47472021119f5d3cdc8b642870943bcb7bacae4ba4313b280db6863447f62cdd228d6d33bfa63a04f8f731a7cde19194de589	1	0	\\x000000010000000000800003be230401198e99bd12d9db1ea94c7d05021f68ed30b38caa2fba22a188e63039b8163640cdc16edbcceb6700d804784a15153f60e43319903b443e37c9672cec465ce3287e91bee56866adf9808ab4761ac88363add295ec31ca83746d429021f33177a1dcd2f9022ed97c819f4b4f834aa86c7c139ff9afc2fb2aedc0d92edb010001	\\x55177b534ec33d5316ee8dd3f8611bbfb8309f4f8f01639117bdd0e1bdbaed2140190172a4bf4a4237c9fffba4193d6652ca89ea262bb628f81bb7737d41db0e	1655553088000000	1656157888000000	1719229888000000	1813837888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
335	\\x24eb6b082a86c91e64dc36d190ac4e4f933274cfe37ead34b5407c30e1ee154a9adaddc5bab08cadc3896156bcffc9db910c5cdc96e97101f33e616e52cd7fda	1	0	\\x000000010000000000800003c945bbe0a0237efd1b473d467bc213c79932243e70442e0be255e6fb3d4a5ec5fd4b352c888b3790558edfed61aba572344b5fae6f2640aa58b02e36accfd8cfd14303b712568443421fd3b1345e822d4e26a9669453d9405bcfb65bf4cff577b5d220f5234615df3a50fa93178b4e675a75817c26277eb31447792c8ce95f6f010001	\\x806a9b815185e676ae9846ab9376ab7e96eeed164c4b4df1888c185a8739a9245a16a781ffca19ce624699b68fbb68521278f3e9242037173263472eb9d1f00a	1650112588000000	1650717388000000	1713789388000000	1808397388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x244fe0771851f2ebd49432277d736673c9d57b3c282312e231e0583f17bcc77878d232a7e36573a11e0b5e4ca5f61de829382482460f4aaccad0a601d8ba4af2	1	0	\\x000000010000000000800003cf84eb68be8a174859c5eeec2dfb580802cb434e642ed37ac6dfe11414c879a7f53466499ed7b20800c3364be100f8cb71899e64dffef9fce155d2c7bdea3b326150e0f27e14e7706cf449b0301ea98043a7cbf6ba86b09969975e960ff06a058814496a31d528ccdf2946d586e322cb9856cbb4df5c1067e01172ae91d867e9010001	\\x381ac004656210324c45cf1869631ed3a0c9ea348e0c308d1044c64f7c113d32061eecd1da404f7d4ef7a07098aea14cfb92ccefc4ac277d75ee26e30962340f	1662807088000000	1663411888000000	1726483888000000	1821091888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
337	\\x259b939fca258faf946ecd59dd412c30dee6aa250e0f11e6350c50b65bee1cdaafe3ad9dddb1722760916d188505615110421e5a060154b961f8809a8e678f05	1	0	\\x000000010000000000800003dd18048d32c46b9ca6bb9f090f095d4c90707a7b6045016af873e1255ba3b5bd104bb95d10c8cc94a2d2d773c71552b1e24b7188ecc53123fef2babbb6812296365b991a42d47055fbd5516fb40d10c512f34eb9afbc49c01c7ecdc8eeeb8a790f572cbd56caf881c2d0e999140a929f7ff8bd2b91b4b0efc78703529a09f22f010001	\\xcf7c8cc7bfc796524a79f9132f6c457da8cadd20ca48578532c0e44add04f18ff24229a3cdf6086b66ee3de575d6774c53fdfc554f466379f0ecf8ea56e2820e	1656157588000000	1656762388000000	1719834388000000	1814442388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
338	\\x2a5bbed99670ec4d37d751d755c4f77edfa7fba7a6ed6df5ffdce8431884743f5e97056c6edcdc4e228b6ff01278804b48af1a43f1cc91fac5c43abef308b7e7	1	0	\\x000000010000000000800003b42721a523dfad83716a8265bb3958e838a1a49d08c8186b73f8265c132823bbf5319b95ad272af68179c27f3a9f980c46cb0c9512f45c47e42485fc1f40018e065513637ee39a05e364912e4580d50c93e19752f2ae3ee006035d5074375da8153fb75751dd6eb34df2b622cb246d82fe9696b7c7d517331ee5dc3cb5ccee1d010001	\\xfda6a6c53e906a69eaad57fd5ad08bf76b0474a8221ca9ac34cc1cb029629967dc3273c111936506bbd5f1a3b4a2e9d3425c36211f4417ba267b3acc46636b0d	1665829588000000	1666434388000000	1729506388000000	1824114388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x3417cafdd5a5edde1006eba90a8b58f802b78d6fa7d3de1408a8737bfeccba951c90ff69792740d9a878019eaa283e2a9e961b44278996e91e2a85f238e57072	1	0	\\x000000010000000000800003b95d511af2885dd37b506a14bdb52dcfe43a426b5e1a768617b24b728239c8f0a2bfdef3dfb06d8ca98df275eb722ed7b8559d1be046a364af4b42eae17c861ca6fe9f6cfbfb16ac4648eaea64bd85f4186322bcde6c0dd1b1b2cf4508f27e1a1a49cb37c32fd68fd6a1ec8d11c6d3ebd6fde8a91d37f8bcdb9859a3613b68bb010001	\\x3996896921433d86cbbaf3dddaccdcc9b7c9b7806d5e4160eb1822f0b4480481823dc61a96bd65c160bee7403f9ce87a2ea5f483dd7a2c40209a449af1e59104	1670061088000000	1670665888000000	1733737888000000	1828345888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x38af422bea3912c65b2ba49fb4b692f1ac513e83319009789c628e7cb17bb42145f204f5b1d488814ff395652939d6bf77499a0775c25a54f364774f51162e3d	1	0	\\x000000010000000000800003df4e957a5c00f8a7b75ca13809676bb002bbac738957a18589c11adbd0d0c6a40457171e7cb39496c298afec8ce5b842c138f747601d30c7acfcddbbf9f6d8daa0f65fbb630a04fbd593bc12a13e3d215df9deb2a597d8941482534ffd6ca14109cae5037bf5da3e7308656a6b17ed51117096f20219de519f2823d048265737010001	\\xf2f6651736d938238fa1dad9c27da69b77b5f7eaccd8fc1f6dd600f715c84dc6470b1c7557d5feb29506dd4bc728d3013d5f2bf8d488ba46b97b8cee5aca9008	1679128588000000	1679733388000000	1742805388000000	1837413388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
341	\\x3a237d3fbcfe65c819743f25b045036a5e29d5c39afc5c857d624cde894fe08aac1b757866db0b1e0013d8ad93d020dc0565203be7aca8455ad7498d3de657f9	1	0	\\x000000010000000000800003b3c093c3dba550110688cfa8f95a247e63e70f29379c139a9989b0fa3ecad610031e4779dcf2a7172f78619db3751f46fde3d297dc59426383bcd948e41ee81a9729b9b4a18361a31bef352e11d4e85e6e2ee3a4c3cff8bea959f7d1f8ec5cbb1b6dd60033e0f4ff9176d38bbcefc8d92929fc548803af06b2a35cdd29abad05010001	\\x05740d520d88cc253b199a1654f5b7685403047aec8ae40c5160bcb01242892208d7d9ceebe2eb0c3e302a6cffa0c4dd6a00ee95d4ff7194f386ab8115b0690f	1660389088000000	1660993888000000	1724065888000000	1818673888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
342	\\x3c57b7d5644a0b7d44dd3dadbb0b67960ce3d556821f837236b0a7b4c0c357003c7b8637a47f3489f749945a8e5a44a731ec8e25732e47490084b5090171cfbd	1	0	\\x000000010000000000800003dc7d0c769c5260365df1a82cc6109eb4f50d39d1986f9aa75906e51cfe8b51d5fe3e85d25a959afdabbbfe8b8642d47a3e60417500a5ee6fb7fdcf3fffeaba29b99cbe2feb1e719117a118a9c364e806994cc4c0d2e22f346223070aa6b274b5cee5ae6af8fef5abc6071a1a29e8e944fa79f338674f6013632693ccaa1291bf010001	\\x4eac479172efbd17027f7a6a2ab9cb081973af255bd2dee50a18b8c1b7f26ee2a4d18eee0f7f21d858a533a3f0e472f6d791d2fba8ec6bb822e0f3fb3e25d006	1673688088000000	1674292888000000	1737364888000000	1831972888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x3d63089945aad7f01b23cc3612fd21d784fac1cc05e354122529f64766d3a47970a95b7449637e3877f5f143d8ba707c88d9d9c8b4b661ec54cd494ceec11888	1	0	\\x000000010000000000800003bf35eeee5f377ae9e0c2af9443490ea04dd864f7117885056739967462e2a8014f08ca0d760386257b40920c59aab267a30fcadf82cadb36eb0c5827636d81b4b74632a3c7294c15aa4ac66bf5232daa89cde97c91c3c338f0a5f7060758559fca0beef08d2ad3b546d59ccb98ba5072d3971def1f4593407a397fea8d328a4d010001	\\x12c918922b2056ae329021b02d872af9d628031263cd818dcaf8c516fc7462e96d6714d8d1207db9d89b6391652e20c520f81d9098c8d7a0c69f19ffb2ab090f	1675501588000000	1676106388000000	1739178388000000	1833786388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
344	\\x40ffc81460149a298bffb98d08fc7bded6cba1cdcd623bfecae842abee6097736e4415d8da78a27fb8b65df1110f71bd05342c63f173094b1bea582cc597873e	1	0	\\x000000010000000000800003ca807f8cd226b4e2f38a2a16a3b8080c0a42d1f586b2ed84388e799ff97e0068677189a840dc3e651ccc9143d1f78e5ecd3d48a4aa0afadf2975b8429700470e1a3e15b868b7735e28a4be7e163b62711bcdb3095436022ffd13fd9f27767ea77d6708bf9533a9a2e466024dd625defac3bdc1c82af8e7fe2346d3aa12a419fd010001	\\xe7941eafb6169924ca3ff3b41c06793f65018f95f0a6e292a23394edeb9f79f79c21ce31d2c4359d0e86a37690abc307242133060dc3e72c9a7bb0046319ca06	1654948588000000	1655553388000000	1718625388000000	1813233388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
345	\\x42833022437ac243fb87947175cd1cf9db33079eb2197a4927da3e693e2d097e3cff3ffb47e1582ea6724573462f99d43d108e06e435eb707d8a85b63801906f	1	0	\\x000000010000000000800003b5a791e289757aa53a731ba3de02f2ecdd5728230f76fc868514930bf6e5bf7f78ec6d23a023123d4498906aff7444dd41c47c2f36760965c29583d5668803cfba137607445cfc4ce568507107277f61c05035bc2ee33178965283e36e7bafa3f8e830a00b7eb9b83c2060300907e4218bd039a9f48fd24159db8a56ce388aa3010001	\\x577712491f4c35fe9e64a90f518ef34fc9bbd2e8fc6f8e5614a710be9700552a01228081e66cb72d0b86dea168fc9a63f11be7b9804be9dd6b55b5726ec8f60a	1662202588000000	1662807388000000	1725879388000000	1820487388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
346	\\x47b3c58125006a82b9b68ad58af4c6ab66ef3c06b6c07775ac760332648cd723bb57d6a431dece73642fced90d21eae78aca0a92a6e664a3999a2090feff5db2	1	0	\\x000000010000000000800003adfa6ce334f8d614bcca873d270b054e862df1a4c746d66ca8f85bf0d6ebaf3b43c0095118f6e8b3f0c1359da709fb4b658163aafa305a5b53034e5444eeaa139cd302dc2e79c53b26545b9454b0b9659ffc41028350e79f1983d47d41b0bfbea6008766954e1c8172110d69dff6b4cda472d12bbc95c63c0e13883f15fdc119010001	\\x75fc39feb9d4e404ef6b97e4979f74a41b6c3b25a5c0563b1f73684e133a12b79e9890cfecc31978997043395cabf1e76a1a31cc61a62758c66f14e854a9fc0a	1671270088000000	1671874888000000	1734946888000000	1829554888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x47bf0b703251c7c40cef28c31820d94429f2743219e7dfd4bf7c92a4cce34bbcacca323a6b3a1e22eb6fa5dda55c537ff0f5d380f1f75a8192f9d86ed159eb32	1	0	\\x000000010000000000800003b8901de9d1d589c3f7de336007333c2f1e1980c68749d4d278092d369f7dc0533ff30b57db59d1922700a8eec6439eb746de9b02cde887b7d79deac9f94c7177fb20fd6f15e5f7710caa367fdd4e7ba693408f7aae157c5097e192e817003936c949b4550d7a430e4074ecea5fa51fcbfbe5ff5088b116c4538aa7f81129adfb010001	\\x80ca193d47d15d69407c3677a0505f5ca22a47ddad2654db1d2ce2a0597ed2000fa53468cda992df586a5b7cdb5bd9b46f6d2d8744872877c226dee2467e8108	1663411588000000	1664016388000000	1727088388000000	1821696388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
348	\\x48a37329cb53ae0ed7ebf3aee1a795f8b348c15d0c2ac4ebcefe43999002fa7a3dce9df42e87cc0bd2eb73833258a0c5c4d948ed6cf6fdc5c12cd29b208ae37e	1	0	\\x000000010000000000800003ae16d428b3f1587b5d7e31a36ecf04b471e9bdcfae96c0c58dc41375fc092ccbad2b11035885aa50e34ca2800e2a23ad30315a9fcc54ec57bc322080f163ab84bd751bb0913c5347bc3ef65acb1d134f2724cd7ca741c6743473062d598f4b7a365b43478d5d70785871b83664b2303e5e4c27bad8a75f97b846f26edccedc51010001	\\x7bf545425eef39b171d7042c436f0fd492efa9308828f6d9a416c1594aead80a62662fa3074eb7ab78fe6166b808231ba62ece8fb3c1c688084e88c90c20850b	1673688088000000	1674292888000000	1737364888000000	1831972888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x4bff157bd45646a6fef380f2462c69c0db0ec5ba35ce60284843cd05baa58324b7628b53d070388054dbc2fdca504c379c6569e782773c0e6212839d2006ef7f	1	0	\\x000000010000000000800003db401a435d199159ab6b2a5b2e285dcd0f3b893287758672a3ac25dad2849ec0f9b8bc31a90de67a0aa86091cfc55e58b53b7c433534cba8b9a5d7b4b4bb91136f86cfd756a0ed99321e4365ef513fe4cf855d694968873152838d47d990381d80a222181d1e0ec8ae7189dd4369c96f3297be55cc9be5c6d3a8c68aa1d2310f010001	\\x27b204789b5b37bbbff74cb884379855078765ed4778c87284426cd59a35efbb296eca0af24659c98f25d289f66e92320070382d886d89296878455bcaba0e02	1660389088000000	1660993888000000	1724065888000000	1818673888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
350	\\x549fca2b69bb9637fc7eded2503bc0003c3023698f839a6392b088688908f53de717c50063dbdd23fd46fec8ecea396452583ef15a1adb58546eceaa36faece6	1	0	\\x000000010000000000800003f082289c55fa216d79d48a72ab711c36212d13720b9792fe5e39b1877b133742553fd5c6c57cf43d7b1bfb3ae2e92a0edafb229f0535e1d0b9b9e3668c720ad3c6c5ef7f93339479b3625176d4aabdc475e682246a69fabd22685c0fc707a98408138d425f959cd8f2c37ce0f567f4c6c31fac04a8bdd585786f3040924c4ba7010001	\\xf4af6ca0c02d5772652a5df6e9d759c611fac6e77fc656ea76c9753a480f1f49c307460dfc586992ea07cf192f1e8c04df5c9e0a9270c22b708ef5e241a00205	1671270088000000	1671874888000000	1734946888000000	1829554888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x546fa44c38b266435739061cee72c2506772aa28292dcf912b17f5ffff26762252a3b8c817249c2ed867440abf138bf9e0d415034ffe6d8fc2cd6933caf4eda1	1	0	\\x000000010000000000800003a94eece40a130624af90737d503afdc47a37294da603dd2c00993647501b769a13bbfa97ce8ad2b14d71f1fa347cfa93df685594dec6d05fbcf4994df8bdbc81706fa253a746da0305576d02054da7638b0c739bc204885234d690861d88b6a9a779a6dac4a08d591a885fa89e9d84d1652ed643978c8976039d08af6995d953010001	\\xf1113d5040f9b037dce87cba488a255f5daf5f3e3caae105f88becd47a61aee89587f9fd8b34de53887af349a1ebef1d6ce3798eb28af75c5af08e95be00ee07	1670665588000000	1671270388000000	1734342388000000	1828950388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x554b5d5ad159aed4be1c68236bd706ead1355cf703c364de93c29353cd3d9bf50c731723f36802a805eae3d1aadd3096f32f388422397928306cb19fcc1b8709	1	0	\\x000000010000000000800003c2ac6b7b9785ac21f79a426a27d92818bd5a805694ebcc1dbf75703d1bcbd3dfc6eeae7737121d661cd340f1d229268ca69bd6b62e46eb330eb576c35773bcbcbcfdbed226332ff7e25c4f60089abd41f8d39f2b85533630f9f1be34bc783dbb311c881e3c1253dc7209e7c50fe0c3dd7dd82d8784bd34dbe2671d885400d663010001	\\xbd8117ecd28547bf1972bb1fe04e6bb5cef0ca41e8da3695bb0052b0485fa7f2f3fc467b03371252e5c0bc871f981d12bcde8a3be4df210c8bdc29449df4570e	1648903588000000	1649508388000000	1712580388000000	1807188388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
353	\\x55b7d0f0d4b791dd1f9035f9405b19b616b973dbaeb52ec956985fca366d4351885228b4c2fe945a0749cca7a5dd767ca41f973a46bc99398dd95aa18755e058	1	0	\\x000000010000000000800003aa0eb29660cf81db000e783438ed86bb9895990c516be143d3dac70cc8b146caf6a00a0e08ec95091e1059a0c09b39ba8a24848ffd87640a8dca2b8ecba6104d1069959b4b14cd4dfee33750cf09fa7ad326eb7e5db62bbff78c177fcf3ab0d1ea4a039e56fe0758588f0eb149c80f79354b58022516247804cd4e1f07a5e12d010001	\\x90a4b794bdbe0a74d96893a433145ec375b6246632868753b6c1d41ef7176812b17900d003ebb53ab918efc28fbd331d2c17af1d2fa4eaabc42db3093e7cf80a	1652530588000000	1653135388000000	1716207388000000	1810815388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x56cf31f6d4169b970fa61630dfb84193cfa860c4d35e82329dfc6b6f848712144ada8302af10698c212ed648f471aae2e5c7ad367c2ef3ee154a6ba907c368ec	1	0	\\x000000010000000000800003a5a1d168eb5b0502bea4bc74edc4151f13b028f160d74d96850a75b2fa2cf17da44a52c1f5070a98adde55b2e77c3a964e9302c03361ae83375d41aafb50018ecb59486f0df0bdbb2fc1d0e28bbd2a4de62d55bfde57e7275b6d0ec8f2e0f93f5365fcdc9863f7cc1e980ae0e902eaa8da8e1d512a575486939c5965b3a35a45010001	\\x00cf966c3e7ac78590c1c47243385a99ded500e9529b6b19bfab84e64adc0c7f799b4117a01ff789d3de9bd740c5448109d773d381fdabd8e804a7c5c1b0a907	1677919588000000	1678524388000000	1741596388000000	1836204388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x5af3d228e72f03edf3db8d37b987d3abb7bf4322ea7bcf95d3d5f47526e463e0d3d1869eb0398e23c0bf80c5ea3b09491a62a2ca06e9534c29600db8207efd9d	1	0	\\x000000010000000000800003c6030c443f7f6c17faa30f717ffa818f9ac5d8afca5aa77fd674104c5ebef1a9e76c6db8f4341bd482d7f291b869291e106eee831244947e1c9fd0f5cf6f03ab3d50c7c86983fb3df70ba25efe0b43ead33becf6d415da416d9f62a4c2244bc08aa1894f0f72faee8f7c7b31cab759e1d21cadfc4a3d29e798d60e46b34d6c21010001	\\x7e7159162afa05c912845bd71199afeaee1de19bd7cd3e606a4f79f1a04245a749ffbe3eb87d763c8d6e979afe0e80f3d6b70d342fda1e0a12466c40e8939502	1678524088000000	1679128888000000	1742200888000000	1836808888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
356	\\x5d9f7dc57f2c99f6a4eb583cfdb310f31cd443342ce6bc8ee05ec339c577152f667384325ebae1badfce267dfb9f067653d51c68785df31d8cf0e467ab2db979	1	0	\\x000000010000000000800003c10a8ccc75159c7510ef309278e8a7821e7d0922e44e726b9d77ae23ffd18244d1e9b9e6759d6e452eaf9eff44159c44f135ad0da588c5ef3142fd8ca820b2bca44213ca966bfd2fcf006d5754e5f75130ffbb02a04ecdf21c82c9b885015710d71a85685ec29350894abfd0f34f8ddb60e152c2b6f92527e65810e1c988a08b010001	\\xffbbf1c727fad42ecdbd304f3bcefdde8212aaf44f8915ff815d12d7882ebd78a6073cb2ba61ff3ce529507f89ecfc6b8ee5ff694d145101609f009c6b51a100	1648299088000000	1648903888000000	1711975888000000	1806583888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
357	\\x5fe7fed698600f1b1fdcede86942b2822a05f782a10f49945dbfecf0c26d7d4e8e64390e6dfc1fed1dcf29f494ab3571f1a7a1df0a2f21371b7b16d13379579a	1	0	\\x000000010000000000800003b51b53bfee4de88d9f803ddd98b123b7117746b4471653cde682897cda9f57a394cb5753a776b437785322d936402b5c89676b6ce556e2502695f89b64ead838e40a2953c4504473f193d87ff54390e4af862c2e838c053ed2580f867d0a95bd04c5d34d3e84281c498f34af2530f2b21d91f78fb3f49e8983914203cb47c4f3010001	\\x2f19d1dfd3dc0cb74d7de0f51f360f508d8c5101220d5ea793361a2d1329fd742878b0a7483b37708c9b29c7896ced4d68b2776515ab3ee43547cae79f9ed903	1665225088000000	1665829888000000	1728901888000000	1823509888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
358	\\x60cf631e18e7d233091dacb761f622effc45fa3adb51163d27b808adbdce75b26d1035758c056814e4ed8e92e1759000a8676f31547574eaa317bda8132ab2c2	1	0	\\x000000010000000000800003bd7ee8b7efac805a8ec2389d3b64909813eff2c1118ac4009250017080e8c53f3eb5ddff0b88a785e45b80c72da48d7e8e1752be26c22995ab3ab02523f8d9dbe79c8346c6ffecc0e1ed525fee58ada8c510f99bdb56c87b8f088267bee639fc68791d4e6164ed3f52f7504bbfba096e0759fadcfc24e061b6087d898fb51527010001	\\xa4d8c0d7661259caea85f39d69929f2e8650b3bace112e53819eecc62361fd98e81f8fa49a3c6d6e8d021007bfa054e2825e59dfc77e3553687c97c46f012208	1665829588000000	1666434388000000	1729506388000000	1824114388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x643f15bc39bf2e211bee883e72a7cf91c73093497c7f17a66f7b43fe129988cf31c6e064d777fa2521f866ee23ef2e9b9a2fafa0e22da0280b6d4b4c142b8617	1	0	\\x000000010000000000800003c83a4e77b461b1ba6324a89ae876c22d62803bdbc6b849c1854f3f0e55a3e0616e8fab7029d43209dfb2635e5bd085fe022fe40985ac4d8eae2bb91a3f42ed760f0e0ec996c0f5a7147cec042e162868d359b8bdfa2f31f8130babd702e24d6fa19b162578e0a190ee9f1e6c5c2d3d7d7c31a4e7f395441fcd41674c4e5d5def010001	\\x43d1b004577c2140bcaf160ad8673d8ea24f7e95a5781224c1f28a6e8955e36dc6878ffdd90e5968872be7aacf9bee157ddebec933e220b78adc022a8b53ef0c	1676106088000000	1676710888000000	1739782888000000	1834390888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
360	\\x647779d2d2ec0d24ec94682041a2cb04a86a72583c56d8eec5161465f2ea2c2538e6ec25e8267bc34a204be360a3f214ae185709d7d37071579da7375e2f5ff6	1	0	\\x000000010000000000800003a47eded0187dc3ed2255c660eceeb924a3c008a1153a14bb66a053c2d788c6591cdc4e7454cced16e54fe7a39a3f64ec77a1e1fa6b8651aa30337fecf4279eac935d3fdc8116a34abbf10ea9ed96d328115cffda7c7a2eb5a646676d31972cbd76c7180b84dc4123d2e64b402d2b6f9ba4bf16aa3646050d1c81aac568a48847010001	\\x7f3db555509516bb5f080bb3e5626358f6eaaee1aa4989112f71874c8103df155fb6ee807d80d4d03bddaa15713daf914a6fdf891af85d6681f71637abfbfd0d	1667643088000000	1668247888000000	1731319888000000	1825927888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x657f81a33a8ac6f810ff9f419c8b5038e2a26dc10055aaf7d61ff585a88c65444c3b3f787969b1fa2cbdac09ac648e405c945f8d9c2a804acb2ea7d77b28505b	1	0	\\x000000010000000000800003c11f7d4c33b18749d9a3b9d0f33bc793f4b855e1f6c9e27d459a534fda701a07f9ce2ba83c8a24aaa65ddf075c2b666573b4e4782916d4a676e711b618015a291c62a68bb1e1a1195d7ed387367112c4a8957f56d29d98a57479206d1811f86ae0725122aeba4703ec1c38a01e6e5695bbf0eb63aa12fcb1e6ba5fc5440111b1010001	\\x7429ad713ed56933a7d34ee7371985627cf4574dc1c8b47d237b52994b59486278d7b10b58fe57e429a15e8f548655682746db750703f6bb2fc4e03250f53200	1655553088000000	1656157888000000	1719229888000000	1813837888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x665be470fe56951953f15eec895efda44dc7074c323619c33fae62ee70d58732e6541900f86f7df210040b9b85831e19a0a8b69ed83cb9f0a398a3e563e95763	1	0	\\x000000010000000000800003e5e5cfa6eb652c184bd1e765963eecbc859335d9d6ade4a6ba0c963bb8d88cbbfeef2a77df288802f7a709ba5ff3a23206f411daf3d85eacad97336ca1a9819c1efbbc83b623e9bfd58213d9ee0df11a7d7467bbe22765dc3624635558e11befadc9c5c545a673b79889341dd1c4952d568d2b1834de340037d1e1c21b21abad010001	\\x2a2a8bdba596d00d2690af86cee76f2d2cce84fc1dc08063b5ccb2a1c11886e2323d6c1f95454e8fca84ff66def5e47dd003b8bf5f5bee8a3587b7bdfd96ad02	1671874588000000	1672479388000000	1735551388000000	1830159388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x673fea89103484d647c378910f7112acf3bbb5a5c15b6ba731bb8d8fd968e3f4c1dcce4fdf06f9f1e31ec2909cc3b466f3cb7d6f7544115352c622260ffa031a	1	0	\\x000000010000000000800003e641dce5fc2c0254beef83ec121b85ce4887644e44d4c0e2359a2f6759adff3bbf8d19547233982dcaf05e25894a3a74e1983a0b37da299917c26575e3da8aae644f5a7aeafe0db31b6ddb36574f6d3ac2daf10621a6d6d3b5e5da5027b98cc466f05f9b3dfc52a97851e03e5fcc21aee93cf625c118c1a5cdccc85b1853b91b010001	\\x055a0b72c4eb1ecadf8b8a7b8686055eb4579acf24be9f4094850abe8695bbb809b8b5338847bc799d2770132a8deacc7cdb06a0f5d6dc0ab8d8bd8035683107	1675501588000000	1676106388000000	1739178388000000	1833786388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x6943f13e2a7335d6b06b380dea1430cb4908c3d03ded29ca45646850a5023cd8df659a4dfb42544ab4a8b27edd90777eb267c68a683587be56fc999c9dcbb802	1	0	\\x000000010000000000800003bc701036790ca819c5f692c03824fa5aa1673958ddab7303471ae4df90141bf89751cb71d50d1b07a0e77a0de115f0dc0168eae4b1ad69d0b06dbbb9318f7328baa75d7e29640d76903f12019e279fda1bceb94116d242215ab5cf1d4a7ba71a829c5e025a9d600c7f7b443fa48f2c23684978eaf6e0502c5d689858e8b84d79010001	\\x2c954ecec321afece5c545d2abfa0c291850215a022ee189be3f24732a92ee2e690eb5a0add54dbc5be9391da71e42134ac12355f1ce3e1e788a5e066d7c860d	1669456588000000	1670061388000000	1733133388000000	1827741388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
365	\\x6c27bde027f69bb761a5363c9d045a40ad62e9654f946b0b70f7cd71cb0143708d073c3047ac3336c8af2335f862531690c5fe7d51797bce2f0d605c0cbb3f80	1	0	\\x000000010000000000800003b6c7904dc81d557b303a361008b8b80e24ba8426a35ea44105b19d6c41ad7c401f852dbd664636f3773f0bbe51fa2b523d914da8d5af17a41f0f1bb6bc68f1b7b6cc95c32cc31a6d512a35108ca4032a39cdfcd31b4dc8484df3a196279847b4a07b3e0ad20f4da5c7369c2b81bf686171c3386b078e8cdec02b7a81acec5bd9010001	\\x468e32ef5cbacbbd6ee2f1d3bb7e31e28d9b5115f867094487452083c7245e059ca11b75b9417388264d765a43a7537b3df04fa6783992b754530cbc10fe7804	1676106088000000	1676710888000000	1739782888000000	1834390888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
366	\\x6cabc981997a816be91197af5f05989b9b81598e8cc1e5d84e6b5d579588600d847562db3027f49b27eb879bb465f8bffae0b4699989c73e39ad52522dda6fa7	1	0	\\x000000010000000000800003bbf9fb8ee3c612737b9d42a24b23f4d113fb636edf91d6ae877c6a89ca21192bfd9845a1db7b20dc200bf044cd5f39a5181477e30643d4e83842a17a2a660bee9292cd46893d99731c43da7ed90fa8058b7be3e13f3877bd9f3eb48752714339f67ff7b7cfbcf05143343309205e37652807b985b31908940c1e62c8e90cf2bf010001	\\x7d0df6423c4337dcb5a1ee242aa0ebb1d955710e71549d1847482c56f6cd2ba061c96ff6514e837b6c7899d8a95d2b366e8f6650d61e8d782514c6a018b79409	1648903588000000	1649508388000000	1712580388000000	1807188388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
367	\\x72d39743f15ff6261fbf8ec2761c803cae43df650f4bca0bd69cecd4741011d3c73a9aaa423603835d0fcaa09918708d92e2bf61d1c93de1944f268eb93c5416	1	0	\\x000000010000000000800003d7c228e652cc062f423fd45d3254e176e19aa23cda8c523f6f6f4aed348caea6714e961613649ff55be8ded0f4e1c681f7d4ae6f51a6b8e18556410aae5656a66c8d1e7fc4baeb928a5c90dacda2e1e02b8891478dad96f376dc584388cbf9fb4fb60b092e6f7793993e46428ab11e0721118e266327285b299255875c687409010001	\\x150a7822b30f1c7bd106ed744217c2e45fc7395a20090ea278cff5a29f9c127feea7e425b5cd42f2ee8eed2c22f00ea06baabb95abf81571beba889f1db8f100	1650112588000000	1650717388000000	1713789388000000	1808397388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
368	\\x73dfec068895853ffe90050a34eac8b4c14418012b29b4c962844ceb9edbaab475daf43de01309114ef8a2b3e373551d145c2ad348f7bfee53c5a52628f0a044	1	0	\\x000000010000000000800003cbf0cf64a5cab6341b9317df9628a2ea41545fcaae1cbe8276d56063eaefdb6b54bc6706e01d90826dacedf9c5fe31c6133bbfd7999d6a93af661a64f4ab2e95849950dfacbe8d61ef665651296f6b7a1546bc3c6863bd5ba5b13b079448cc5991a24e71512a3160deb59731525a0fc4d8275183746019ba74e47913a4ecfcf3010001	\\x1fea90876dd7fbf705e085e9be59dbc4b39357e2518702c5bdc7ac513dd9fbc27ba50b03d3ca020c8cf8eaee734582a70ff8bfce183eb39067ad3dfc0299c702	1653135088000000	1653739888000000	1716811888000000	1811419888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
369	\\x743b46c35cc48da1ffcbe694befed72374afa2816fc766b6373f9007feadb85c3382c9b9932a5e48a6d84553e36ade078c256f55e8f47639b0cf68d2183e5b0c	1	0	\\x000000010000000000800003cd7e4b22d6795b8e23f4fe9e4cd2df56c7aaf5b513cdbaf4a39589a9cf2c7dd4e561abc2160819642f7d48d8cac0951128ed6df746fbe9a458b8c000001cd9f3d414ce6e61d0e138184faa6d6b3caae5d9fec4a806d341e59b863ae02c62e2cd69c379ac995dedb9a37ccc314d30617f25c08356556a8134fcb1cbed3c17fb47010001	\\x733ecbdf45ca6536806cabfda89c4a33fedae3c2dab28b260dd62ea84f9827c5d180ac7e6bdc78c69c6c1a5014c0cd9480d601d51d365261dfccacf81866f40c	1656157588000000	1656762388000000	1719834388000000	1814442388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
370	\\x79d32853dafa021501c7efef90d7a5bfac7ca5389458da2435fb4c13bba922fa8d7fd2da204ad2f4c210f0386c5672754db9a1438e044764f40fd7accf4661c2	1	0	\\x000000010000000000800003be1cb00edec4d260c8c2ae1e390f34cd83de8825522fa12ccb4bcd7e4dcb89a5a513d7058a396d17a6cf8065963b2f0e450351f0a22e3aeca07c9e35fad86d381746629d1036e460d2f9597b51b489818eb6c4f18933f97e89e89cbad857ee4f5171e0578fe2313487adb053ae33d694e438d94b8229cee27ce4001cf35a2d89010001	\\x2f509ab911abfc1e5a009b5a355acaccacb6167e73df6b3cc45c0f5bc09f1cf6db5d5a22460458309c8eba9940e30904e1ef2a6374512e2f6c8fbda8c7e0760c	1660389088000000	1660993888000000	1724065888000000	1818673888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
371	\\x7bab1c66cd806cbd9a297f2a34ce17da12002a63aa4d7b562569d7ecfb5b4e7fbf4f79432891f5797ddb8abd747adf38cf70958409487bb99fe1edb36a0535f5	1	0	\\x000000010000000000800003b3240c57f212399ae8372d5291b2379df62ca142b794d24669d77bac73658cfdfba082a599f2845cfa15e5d38724a459990385c006ebae8ed77023863b28d3444732c0c9eaf4460af8918aa11e8c00ab32006e7c97c1e23fa555fdb01f68d278c49a795150d8fcd71909fc60126d3ba2c54e5541784d1d40bcda5c78769363ed010001	\\xc19ebca5c12c84efe90166e5d31552dbc81db3520140271be486fa4646adad53957332a271331d2be1534bba508fb21bd015ea927a1ca03d8397f71310e23d03	1659784588000000	1660389388000000	1723461388000000	1818069388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x806f544fb0452640c6e0e2194d09859dd1c152ee14a7be4118978a378dba99234f88979f567481f95995a5dbfc39f6185b8fb93caa336c2f51110aa1d36bac5a	1	0	\\x000000010000000000800003c614e36ad601a89cbc93c70235fb3c72df64c1206c0b72f6b4a37c754420b0ffd15d09afff48f59b121b166e0187b081b35d9abb7e37a63c1051cefa126ba79b13426a343882046d3e7dbf6f1418e288600cb1abe913fa83b768119ed9a43bc27c332cc43b886186e48555c74170fcb8b2e8640770e5f92299a06069131f1b4f010001	\\xe270a2eeb5f7aa0b697e2d1d2da8694a10e11d7bdb824404b3bb838c4ae9adbe5464c9c0282104d0253190a9a501c0aa954e027ee0ab2ebe341bc735fe28af01	1665829588000000	1666434388000000	1729506388000000	1824114388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x828fabc4e163db13aeff483973594ae40cb1ef087ad0d48ffe824c21a4ab155b7c72787fd1c902bae32eb0cdd37962396c5622483078a2895fde73525dbc838a	1	0	\\x000000010000000000800003e6ee1b325c3036ed5888ab86ac1f05886ade1ed6b988700593b6e2c383c80cad1db82bf85fa2fd47989eabd547943dc0a4722e685f7d252290a57047780ac54cfbdd8e509fe1c37c4622c9167b6c472c19f156885e8ec2dfd18ab6b7bf19ce62a8bb3b4e16acb9290d753346bb778dc772fe2fc7b588e6e2ec22eb84d65ffa8b010001	\\x79ec3d975b8c7b606340b1df258e278fa2380b128c0dfcc5803a119d1032c90b4ba9eb74b984a2ba7bfe567ba23c2682544c5a579f8c049e1581aa6991988206	1672479088000000	1673083888000000	1736155888000000	1830763888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x8377125fe5a5654131e7ded831bf6649025f616d3df4c5b2aca42ca28e61a15996c71c1dd49ff03bcae8a792894172bde3ebba978dc8b212e11d1051453824ea	1	0	\\x000000010000000000800003a0899cb44bf7c31427ef60f2594deb90b17afd9ffcbd43ded073ce1979c3f1ff82d04f075bd98e3b8f718bd367888ac66ba8de96be1efb276255fc63b6c5a11d8190cec117fc3f4b73664c61eaf00328cfcc88466e947e449b5da929bb6355387d47fdfa89565b2f8dcb8cca34a09ad024463c464c8bfe4b944e18d248a3c8cb010001	\\xb4aa915a4d30a5331d777ff2fae8eb6410e6e83f0ec1d460211a4ed5d6a1fea8e0604184e82d2e926c2dce7fe6431631efeb6d59e1b6ec0db78a176040cd8305	1657971088000000	1658575888000000	1721647888000000	1816255888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x84fbaa44f6fda98fda3ce6e65f8ec819b9a17ae448f13b5ffcab31b4289c35776854abafc2a0416181d3a691f8bea378853511373ecf3cfa0843e5b72fd4ab8d	1	0	\\x000000010000000000800003b681435b53dd57b29ca1982ba7589b16e42d2ca3ed58f3e9f4430ce0367270aeb47b9ad34de1a7cd0b38cc9f2c6976a133184dc71c4f6735501689b3e664fb9bb097da2a6cc91c01f025f267b530c8c8f9cfdbdbecc069ab0d8162a528beb9d1ac4c45babe7de0468fd52f6ed8577b2e74143f012829d8b9f21484c2062d992d010001	\\xfaaed4f9a9e5dafab2e7ff12c08154202d3a885abd1c96e00dcf10b0f05a09ddee133428066bd5b12551bc243fb7238e5b07f437f27a60ad8670c6f0ed5bea00	1650112588000000	1650717388000000	1713789388000000	1808397388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x85c3dcceef44feefcbd913bb3da2d6c42ba2f12ef8e309650e5c5a95b6300437fe5420c258eba26587fdc68b7cf335dd162faea38400f9d1ce84c8a2c9a2c524	1	0	\\x000000010000000000800003ca9085d1a81a9c4e9c42ec0bf6c90b756c1f70f7c856ba808f2773262a5ea7a9fbc21705d77325b8b260f3effbd6e37363cd6da6730c6235d633bd10180738e3ad7aa577e065a5958af03d6399e09fcc857a43a7afad6cfbf54c3be6f6b6ea8ae24b1211f0fb9ef651d586ca7b2efa1fc2742db44a388b6375228f79f7993095010001	\\x63d3d7f3758f88818aec84af0ead7ad89358cb1ac6c82f4df32557c5130da9f9a696ab55af4e4b34776b5b6dfc9cc762e59da26ad73fd67a775e421205b16008	1652530588000000	1653135388000000	1716207388000000	1810815388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x871fd14d60ca15c1f59fab307bbd903c764081c66b6fae6c258f2fbd012c653488ccdb6cdbd1b1bd64e6b970b0d77828edfa2939a6cfa8181befb05e27b5a01a	1	0	\\x000000010000000000800003bf03b5cc6de129ad4b0e63a7c105d8a79cea7905bbb8c514125b550126830134b92fab74c8549b0eed2029cc0b0cbe51629af86524fc7be8bdaabde6293d4310bba5c9d0ae29d47f98895bf07ff366a1ff57ac3599620865794988b19b2cc2862743089ab5781a34d43a1c6cd03687aef3f37e2639b650cf7e4388607f299fff010001	\\xddebe56c0f66fb9c63e875f28cbd2870291d40fe6b1c9a72a10aee3a95534df794fffb5422efaa1c9de2c35992a32a085005ca4cf8c3a5fc4cf4e4e2a4d9e800	1674292588000000	1674897388000000	1737969388000000	1832577388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\x88336cc5972aed680ebb37d6a47d9b93e1d8aafb436cb1eb0c5e03f8436d038819b3f54eb4009f9c3c308073939a09e2234aac82cb3a577001e6aa9fe5007afb	1	0	\\x000000010000000000800003b6a4690f698cb96a63bbea1252f0465ff2c4df428f3e4632f5a0dca28f6220083876efe12093f4729c81552d716bcc41c8d90e5e140e6bf54ac9c6b4a59f6994951b8ddd91afa2401e986645af982943cd52a836bc88974178cbaeede2d537b70ff73854f6e39efddcaad24a2d137b50ea3bed516e2e1364f4c41eb31c0a55fd010001	\\xfb26eb3d8c2d2102f4ce88a5365a7ed3fbc40d13bf23162946f198e266043945db22e8569768b3f96649d396d2e52ed70665bea31d1d474132a907ca644bf205	1654344088000000	1654948888000000	1718020888000000	1812628888000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x882b2e4d6d617f98d9b59d3eb011bd67932a927204179745da50f0ced21a50c9a70e90fbc1b001b82747403e02bd19d940d4c118be565a4a1776586d080b4e68	1	0	\\x000000010000000000800003d3029c3ca2a65a39481cbf6e0e8b8b2518893607e527cd04aaa2ee79d36acf7d8bd2abf7f04a3d6b683d09d70e20aae0dc76c98e3a5bdb5d9fcd6b9329ecde2c2dd47bbe391012cc669ff82ee4c5d93dc0a8c608a1697942a2bef57d5984a09e975fd4654903bf9a7f706a8acd0693f96696e2705cfd63e316c8dff159c8c7bb010001	\\xe88c40c27e08c1f74ef62ac97b9f8d30f44c2ee2de5fb9ea7968d5f157bdeeac9e414a1ded4da962ef2a2988748f659d5f7290f1c7429bfc64b3d4b77121f105	1674897088000000	1675501888000000	1738573888000000	1833181888000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
380	\\x8a3b22cbbecbab6c3142fdf38a6ce61a173ba99d71454db761e7cd745e80a4092fff7ea19a693384930a1ea078d1d7bcb1be977244b24c0a46806e03bc324860	1	0	\\x000000010000000000800003d9208080c9434f15ffb80ffad03fd4c374c0a66bb6e2a285e05aba31749f03a7a8fb9e7c7f4ef0288a96d0ba81d0b4998df89f5a252e7b07030594c6163b556101dadce114ad8cf6459e8f432d8b3f5e223409c2535d0f206283391121bed4e7486f7d7f9485ebb416397e662d84344bbf5380d5679daacb9150c6868b40c875010001	\\x1854bae13edb00dfd57d8b8d149cd41ddd3acfe5623b6949cdb5e14144adccc875f59a27e3a51300c057536506c9a080bae1281771c561ae915e5acf0896a803	1663411588000000	1664016388000000	1727088388000000	1821696388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
381	\\x8d8f628b406d2c1de3bf709998aaf5d78eea3dd5fee3afe6b235fe996831423696e00d73fd51b29830649e73b82559c579fc6582dd5b62d53542a57ddfd6025f	1	0	\\x000000010000000000800003df1b91008071d60c6c69358767010f9164de035abc5681f987807cd0e87453f1d06e8e17cc5d5449ec9b61fd16baeddc4d63de40df526678c1b412dbe7a0130ca67619a832f10e8f54b9905cca6dfaadcfd9d8579cdc021eee2c4d663eb14e89e567eb167a5f461b69f1c63ef713019efe39e6a668983272c3f64b77debcaa93010001	\\x428344bf03c05fd5154982e1272b9d2686a4aa128b3381e43d5abb73c29e0b0bd6036eea19deb14a38395fe61c5f4f448db4b3102e6b399d3675cc2717e5d905	1663411588000000	1664016388000000	1727088388000000	1821696388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
382	\\x8e83a5669bcae718fd0a19c2b7f2219e7d270de5e463f61dae1e5f7790581032f509665ca0bfa85d589b3a2934aede00388bad36fe9362820ebdea339ebf30e0	1	0	\\x0000000100000000008000039b88b6e7092cafd7d9ec5248e64cecc05944f0027a99aae6f5b34e6bd3b2fef3a3a65f4d3589e7d2f1b1922c60cf4fe3cfdcc6a89692d833e0e2c1c5b6826e10696badec4572cae64f2a565b8c7eb2fabc98ec1f64224e9092a5fb6607d71967869b34d598b2277b1cfdf581a2c63c17aacd59c3f7a73edd83c47755dc809817010001	\\xf170d02ac82916bc135e6d56bd00e6f6febd360968d9cb117fa58fd657fb3c933702fbda6be201d939f5938e574567fea8d9949cbb0087a8cb2c1f450ee66704	1662202588000000	1662807388000000	1725879388000000	1820487388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
383	\\x9c1786838d4dcb4d4058a8be97f711f24207ec8591d9ffb6863e4b20ca45772e7250b834b63eeb8bc1ec24e980d9367a6aeace07c3508f235fa17e8a2dd2a6ad	1	0	\\x000000010000000000800003b89c27e597d6ab98464bab2b5e1f77bfc514d6c8b2a639d46fe1287207241ca46895eec82297dd8df66d32aed3021842f06a8a6579e4467e55cad3ca4d32fae0631a39aee4498278b1d0466378e3b9eb350291d176eccae849f19b494ef92818279eacfaf812aa03f5ea2de3f976832270ac631b4bd8c4a47e9caaca8fb67db7010001	\\x82e169e81ba0807cfd226a293e0cde64b3abb8976537d6f718be8e8c7d790bc539958785de7104ad024f4c1fa92cd598b636bdad30006bd3dfc5689ae1a2e408	1662807088000000	1663411888000000	1726483888000000	1821091888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
384	\\x9e8f8b8e415c955fee406a4926a76aa07c1954d6c8f562bbfdded02c366de77b0d00db68b744e218f5ad10433199551341446d866eeb4fda444a11b668763452	1	0	\\x000000010000000000800003d2c97df297b822e005eea9634c6915b24e63c14226c9688621000adf4cf803675d5bc85c4cef9114f2c64532ebce6869d57b792db47dfce6a017fc685b3d2fa42e4393eced0c20dd899c7fd403222ff99c872a22c6489185f2b531d0f153a06ea5590a4c1574efb670c4f3a7e4c66911e1fdbe75e3fd38a663333f47b476a813010001	\\x9edd5977a8121fe485e473bcf073b328f29196f95e48cb8bdf2ef07ed6d2aa50bf298ad73f5287239206291f8627c7d19d3463f857df67d9e17863f34653d106	1649508088000000	1650112888000000	1713184888000000	1807792888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
385	\\xa487a759360ef7579ff88d15ce1748971ba7ddcbdcf544c21c422680f071ed8e198d7f5c484591f0fd72c568880377ca1ed9a525a80ac2380a58c83baad79437	1	0	\\x000000010000000000800003c75717feb50f830c7cd9a1620a7dd3ca963f9f0065b5baf0e63c331edc5f4ba38e99683a3a2145cd663ef6892e584c793c96da5fa64ae1905460dcf45c432df97d6178e0479280b31f97af2b700fa9b75bc12ac85c91adbd29e49e2d313610ea3e0e62e47e778db7327226656e442d10ec4d3db2cf46473f6728a93d71e47d51010001	\\x84b92a57e159dd03f7667c9aa2f98b023d8f01c17b8161c0f7d5eb5d90e19bf1630a939c3fa6c63f107296ee65df63f0a7a451baacedcc4e09411416f3156b0e	1679128588000000	1679733388000000	1742805388000000	1837413388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xa4d7bed2d8e47852a30bf5fab42cf2acd5c18fd82e7b1a7d15f11b1c442a1028deb85694fd8168102005923c961f950ff0865f53217dc327e226f03e877255fa	1	0	\\x000000010000000000800003a6ac045f3e0352517c253df931a379a82947458fbfe71b5adcdfbf85910df8dae340d391c340e25b1f4ff43848e216b85e3a7e25223fc2b2c43a993dc6feb9b8e84bf27d69b2d0d8aca70886b058742feb68b4ce5d52499255ae067fdef1de57c19a7479641b332842cb499be578cb51b0dc0cefa3224a1d3de96d0c930fa62f010001	\\x807280bcabb59b2558f7260dedc74e4b4352fd189c1b9a4310b739284f4723148113a929476cbcaacd1be20c603b7a6dc4e5f97ae898d98ccdbd7bb7d4c60b08	1657366588000000	1657971388000000	1721043388000000	1815651388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
387	\\xa407db7819a6c974535c69b60b53ab98aabb416cbd4bca8c2693788e6ee7b279fc9d3a896b8c34ad33c9270ffe887549b9a32312ba44f7c6a1f410390aec15fd	1	0	\\x000000010000000000800003c9bf0244d62ac4206d4655ab1220f1c9ea3d6804953f3f6b78fa6091857678a1c88b23e61186380bc1e7e49391dee8c0b9125e4b95b367d29cd522a1715a0b16f81f18f0b658a4791592c49b903b76555190ec1d53128a84e4fcd4f6e352dc6f838cb6d8959bcafcfa80e4746cd954e0e58a3e2dd0739276772b59927b22f8ef010001	\\x33931a875545dc960d41b1b97641c408988216ce4f45f02794065bb0391585b8f7cb5fe38310f6d5e0d46432ce9e82f135d900d5662f7440a58e2296a3e4480b	1650717088000000	1651321888000000	1714393888000000	1809001888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
388	\\xa93b6d4b2e19553576ed7425a31d2fa63574ac010d17ac24206c8e22be351ec27ef7a92e91d007cb04016489a45c1ad8deb2b15688d7f9fbf2b5f25201c87046	1	0	\\x000000010000000000800003d6b4e30d5097d046c822e5834c2f2064e314efb344e735ec4fc037b636167ff7bbaec2c053657e027d796a3d96cdd36ddac410c9f2100f39f2e893ec058b5347d2f5e609891460d10dbda297741a10f147ca8536c173c2da50a8d9103051370c7ff3b4af9b61ea933afcb04821cdfcfacfb779b8742bd43c4cf74083623e7bf3010001	\\x1956443eef819de1e885171842e54b928224d8475eded1a6f1364afe14623738823275ee843ca2780628f9a7ef2e261376ae18b664d05d7b5c79303e3dca4f05	1671270088000000	1671874888000000	1734946888000000	1829554888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xaaaba301e3c44306e5f09cd145d5e8bfe3a9fce65bb18ab6d74ed0cc5008331512847ad954882fff688f3fc954081a2bb3aded33ba6d6533d517db79f042be8d	1	0	\\x000000010000000000800003c4a026e7c6c57be8929a51baca3ca54bc9f13211cb98e802392436b152dc55e0e758374b24561f9f6b64053bfdd9b88bb92d64bca9d06cee8f5a0daf8ab2263cffa1a542237278206779189565a6eb92d1012873bd91142b575f2cf9ba528497632afd938a3feb2f9d4a61c010f8a2d95413abf270024a12cfc146e62cd1e5e9010001	\\xf3fcfd1fa584c1098836d66bc5ac170ebaffd3ebba4792c6489bc6e3e91cff285c2b66b03ee69420749b4fc9d70f42a45b9fc16ae74a11d906d33342a324f90b	1648903588000000	1649508388000000	1712580388000000	1807188388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xaacbe096376dbf47bd0779b2eb59d7b5e1bff058aa3f3a3185878e7b64340f62a8f19f8367a53db303fbad321d1a1930ba1ddbdc9cf92f22b0208f18ee735069	1	0	\\x000000010000000000800003f42a59589bf213c1a1de805397fcbde6ec0337e911be68d8d31eab18778eb2bdab780f8b570cc4327f2d0f3b31f5ab30d150f52ca8545a061e0b0fbc8b9281725b328e4c556f61fe28156dbbe875036bc4378d3fac439db714f71dbc9371c4bfa8457c53b2d8e2798d72377f7987cb6dbad3b41afdf7c9c3f6c648e2521afb11010001	\\xad8916c3439ac124c15f3e1c92683b1c283adaa98911ada8ed096e1a148be70495151289248a83209bb258bd762402183515019b04c75374b35efbe5080c2c03	1665829588000000	1666434388000000	1729506388000000	1824114388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xac7b008a3f7846ce2f959e4d5cd3fcf0c48130a84ecf8f48c4947e3f42198c1ae76b22f87789e782fd6655627b44759a2676090e10d837b91f7417281f505404	1	0	\\x000000010000000000800003d4494c6c1261fe176e631ca958e07cdf533d3d6be9cd3986695f1930ea6ec5901f5780b1711549df99bffbd90dfa0e88fdbfc57ce4aefc2de80470252c0322e43d64b1722dd440fe91f052b9fec6bd25e24e959323715c26a556bbd608eff25f5e9823d7d80e44ee81888cec80d1c65e0700642743346e12c8503865947bbdbd010001	\\xb69a0dba28e3d98bdf1cda4b3b6de99ab9980230f65da83231acd1f8786ce2fdafa8fcc583defa3dcf6bb558c65448dd4c97db96335b16c76cd52d413c453708	1674292588000000	1674897388000000	1737969388000000	1832577388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xacc395c2165b12249e0b320d9b47703eb2d63e1624d30a491ec6880f5eeca59a6187702d69c751f975dca303856452fa5c48f590a7a51eca476a164619a6c546	1	0	\\x000000010000000000800003de1b99f15eb0f25221ea5f0cefe028a521e4a715a952105c83ba216a48e5797dc42403126d347b0e42c5f505259ecbb6dc20866f5544f98a0014453cd1f71e35bccc11effe4843a12c2200640997132c75e798fb2f6f5dbcb8b55ce062e4c9972b33072a7d1d808558aa6bc45236f99dc8abe9ad7a0d9a34cd37b7b2d195011f010001	\\x9bc5eee850bb490fc0ff128df52f635293ed44fc62fa50b589d5afde4341d008b5b801adb8602c92367ecfede01dbf2203b33edbbb544289007554dbb52c9607	1660993588000000	1661598388000000	1724670388000000	1819278388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xaff35326c0b5eba6351b685d991fdf5ffb9e0126bf2327340cc7211a8705084327aaf65a9c317004f3ca672dbc910143e49d85da57c63090bb914a76399d0034	1	0	\\x000000010000000000800003b38951a7ce051ef4b36c59ecd9cff6a14531334cae482b32b276dfc332bebc1dd0d645d6d0233e7b35f1911eaedbe3fa53304cec917d251d2bf36f95da1d703a958bf9345274ab0aafe99c58eb31bbc39ceae02e44fa3e9cb9c77b4abec3401facc8ae8dbb3efff480e97921f9d0b4b5b3b11193ed7ddbe821aabb77709f1e21010001	\\x03378dc0bdea22e41d1f78c7cc1e9efbb6b942c02ec405df4171681cae732df648bad89ea5769d98a5731cf841db1da2dab39c170c62f3566e7b0a94d7130100	1676710588000000	1677315388000000	1740387388000000	1834995388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
394	\\xb7d3aa68be3a0df466875eea89c8535fa462427a4a1d9a28fb68a3892ce701b145699d99753faaed14d721baa300475c2323389c21121529fa39baa70b2ff696	1	0	\\x000000010000000000800003c63f274214f17ac20b40da39b135a92c2909d936f36aa8c4321048847ed54a84ad47c00f43ffc5acd6eccf6d749fef8ff9ed38d4a4a2a553ae65f50bb2707ceb1d89450079107b4dbef1583751d0203347bff1f673ddfc780d9f993f9de2a75a2510243d0074f4734e515dcf2b0d00540c2853835443588abcf11f4d2a17a399010001	\\x9855ac2016510dcade335457f93240883ef23e44f4003630524489793df6daa19a64467029a91b112663d09c2c8881d4a64c1c31c418d63ccdff6345ec6cbd0a	1676106088000000	1676710888000000	1739782888000000	1834390888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xb9a390a88e54eff28403033a32a5d99c490f9157ad0cf95b02d4ee0d930f6a6f53939ecad19d3fabee79dbfda7f999ca53d9c5bfe51db30065f1bf8264a2678a	1	0	\\x000000010000000000800003d67993892c81b275cc04f7bacb2218c7a05e3dc715a6b54a12ed2ef264d173eab536e19fd46f48e6c374d7b92f5889feaa6ad1da3aa77491687c7cadc7d43ae5638f4e185b8bc4cb51ae9a1d68050df86dd5c41e5c3a1668fe2b2d6d009fdf6222d8a14ca2b8a1270574aa9425242a50d6d6d6dae1cf52ff1a2126fada41e699010001	\\xe468b894d589746d104de4f166df8e9d7895e3e87790eb44f335b34886a3b2362585b387574095a6eacbbae4829eb0a90041e122af24a22ed1671a6481848509	1648903588000000	1649508388000000	1712580388000000	1807188388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xba57ce81e666493ffbd94e30809d5367ca47146375f82143ba27273cc183e83b0db5a3ce901daa2dbd3f717b6c7e8d99bacf31315d21b1d8f4eae22bb5f51ae5	1	0	\\x000000010000000000800003d19622602b95a53943f8b4ee4c6a11d0fae09f66c9a530dcac3bc659e188acc63c4fc912cfbb97a9e88ccf1c4ea36fd822278e60ee22de11a1743b23e69d6891dea50ff32eda9b3d2637f372064a11b10471b87dba08ac7bd4dd29bde46a7154d3670e0737aff59fc702253de27a8f403c00d5679967779ab059584cda860ddb010001	\\x038a8037cede22a24f82622859e5003d09c203239c24e5720a684ade48b0171d10b1ac835b904c076e47360b3c7ea047539e0603b5f359f719d621589265b70e	1650717088000000	1651321888000000	1714393888000000	1809001888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xbf9f4170d317db752e5b2114e5fcfb0de72219f76ddeced4b7f551281c808714946107ea948bc8101604d4398b8697996a4234e5d462d795c41e54907112f161	1	0	\\x000000010000000000800003bb7aec17d816780ce2e72194aa52ee5b67b9af6f69a28608a3b934c46b8abe4f8df274f7e9ecfe500e2516bc8e46d9a81506c98bfd3c25129d7f1fdb63a584f223a9a284ffb91279d9abae612742260e0900fed4e52da5c2d1defb355d8dc507ea864241ab28751bdf432a97c817a527510703c18d759b7b6dc6face0b6c9b77010001	\\x0fd5f2ab25cd7617bf2758cbcdea55c7c4194bda6f6027b07999e8a06ca6801dbe729e77fc4c1e697ec446b603df2c0dd3d8bc111cbc0c3488b2099fe5d25a0f	1653135088000000	1653739888000000	1716811888000000	1811419888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
398	\\xc15bdbf683ea5fa818886a5155acd8755a8edeed1d48b6e3df48ec419ec1c3798df6578f992d30c1950bdf29ba6ec989a04d39670262bd97232b083c815dc61a	1	0	\\x000000010000000000800003c8aba148591f398b2655eca1b4561c95856a011e4fe4368437f26df17335ae3b929a9aec67ae668b1c27f4d6e10dbbf5484bb61d09cdc2bd4f30593e29f0975d893133694a2b711a0cae7e8a1ed2ecf7e826e7e0e4b702f797e3deb01b786fa8690edfc79aa80b150ba5db13d8b079b451d0d515fc8cdd56e2c5046610e807f7010001	\\xf35e5f193f48807a201162c423e029deb2876c2758ad268cf794cb2e6319d367b5d3c75397946c18524b34a65af73a2f013c35f9d44e6533bb58d928a2b50c06	1664620588000000	1665225388000000	1728297388000000	1822905388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xc25372ea02fceaa42e5a7623de7708ea7d42a815a10241b1853d7f288a899f0262a8c74b001afd87d7a9a84e36581fe91d3be6007ab4d635d0ce3d87f41be72d	1	0	\\x000000010000000000800003a3e10236062b8294d1fa461a4f89270c9ab5a7ba1c7504c6e47549d95f5df13e57be83840991cc4341469b3bb960c5f9fb14564183536d6c04b71b14f837690176f993e6175f75a4fa76de286767de2b81a0c122a0fa824ce34c85ee497e435789dde09510f43ad76d82fe9f085a999d4dfeb66f0deeb3070ba3052d369b41bb010001	\\xb1c5024f0ed105d90c8c7f70ffe8952a0bc6f1b51aac61f0be8dde0dc442e6df701c954d4078bd61a2e062233f0e09d82f0c75cf644cc10e726be1684cafa90c	1650112588000000	1650717388000000	1713789388000000	1808397388000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xc3cf90113631a4b2ad8fee6b194341c2f9889eac303dfc6e550be73ea67adfa3908508981229116a865258f194e3e25d748f7d000d26ff1351077e3535d97681	1	0	\\x000000010000000000800003e92149b9fcfeaac66caeb4c64df97f292dde3686ef4795656f0b5c953ec5b7a509509455ea09c9916f6cc0aa995c330aa23b65208a44ef90b57fcd12d6da77197958832aefce5d290fcf79a6da1c70232555a92c9037703655d81aa888814c6b1fb0624ace68e90d8c089c9488348a0accda31426c829c5e30754e6de53c24df010001	\\xc9bf7145cb69a0ed565a6cfef28f81c6e828eb55a18cde603028ef7378fb0f74ad74b7ff58710829cd318ec8b0b54ff223d153fd77de7449563feb1bd6965907	1651321588000000	1651926388000000	1714998388000000	1809606388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xc3cf32cceea18c589683dff17a20ae11e91ffdadcccb854ffb12b95030e4653aa64b8f15d75ee2a5f8f75d53279043bbc80dd6f28381d6a09268ebd8b9b56f17	1	0	\\x000000010000000000800003b76389d199bdcd5d70e8397e7769d630188d8fa19c0a1cc3ce5024ef9f00c89a51f967a6221abedeccabe4e52d6e5d6a5e9869fa5ddc757bcc3b1804d3e545947e781e173ab3c24f56d135bc4b04e410198cee0dea80fef6a93c5a92a7bf0de1730af35945bcc122939b8ee639806acdbf8a8d964b31e7b93cf5217aa1baf1d5010001	\\x8b9530039c0ccaec08d1444a6658be4684f25bdf589384d7b028f3bd7f76db4529e560986470162a3bd768f587a35f3d377854160c5470f70b3667ca0564b700	1664620588000000	1665225388000000	1728297388000000	1822905388000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
402	\\xc4fba74b32e70e2992fe5eb7c1e6e4522e2e283010bcb2ba158c6266de7f9af60eaa5a01e7707c427932b120a4cbd7f2f4f273eb1d396c51e24f052b5dbd67c3	1	0	\\x000000010000000000800003c56b79fc14c703cc3736384bbe33cb01fc611ec98f404b68f91b2f690197fff06f33a5cc17ef79339e14b7cd3c9a16fbe9ed882dea1bf477b3427896d655d54930fcf7ba50e40bcf5551d3740d5fdcbd4b0c78b53550b8f39e0b246874f5b07958eddcbe9e102268ba64dc06884ef3626b98be2b2327f4aebefafe9d52d79eb7010001	\\x3d532d6ac80362ed8900f1d622f95516ca74f29b77084679b40803ae5754e7ae366b8a0bde8ac2d70bfc93d697de530845c5a9491d8767fa91d2964648234505	1660389088000000	1660993888000000	1724065888000000	1818673888000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xc4ffebd9517668b822317fbdeceda80ff5da85bb2c23a6888e56f482be6ffdf48d6087425a384982920d7ed32e388ce2235a3a0a3ab2d6f3853a22b271fb58eb	1	0	\\x000000010000000000800003b5a5e890695c9140d470b7791e50f3f3b63538925fa24495b5b34b5fafa4cb5353f9aebd994e275100d25a6c2faa2ccaa1aa81d318cf2022aefe93a0b57bc154fdcf97ea410c5d131af28cac71b2d724d52b5805c7f42bc96cd20b319cd1818a1bcd60688c081eef0844f930a091967cbd76e547c51ebae710b4df61959a6913010001	\\x30e0c75cdd4055bea12d3795a4d083be81bbf14149d390cf529bd4d0b18e08b086e9b102651407900d2508de23269eb83c90f4cf6c11501e60f8e2f00df5c501	1666434088000000	1667038888000000	1730110888000000	1824718888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
404	\\xc57f1692b0de237b92b8a5dfa658443d9a7a76a8ab2e31c5dbf47dd823aa8633f2dedba8a514863dd425076f0ff332a094d691d776a1f65798d0069e42971b23	1	0	\\x000000010000000000800003d53393e0d653b4e5531a5f893ac6614bb4f2027547ec111959e3136bd332b129d6a3487e9a878575a168836e6c7173313698aa5f635992f1073f4b9c6fff26d90b083c7592be9db67d32ee3013f0ea81fa2c2f4101a7209d5b786725a2cd2032b2abbf1cbfdbfad5f36f6a442c0e2bd48ea1c366d72ff31d705fb40a5983f5d5010001	\\x7685aea6408258cc650e589fe9df8e3c5208b7f14a6ddcfe89b3baf90e1aed7b08fab8f1b0cd9dd7697e92e0180cf6cae5167d5aa793a150c988300a39278702	1677919588000000	1678524388000000	1741596388000000	1836204388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
405	\\xcbbfc375b5ca7f2a0447c8c8fd3b0c0f87e4ddde742a1cf7661b8ac0daea3c7b35ee0bf8f0a0c702cb83115deed93dc8e9259a90226727f4c517d0decf4bd9a2	1	0	\\x000000010000000000800003a5d0f982459d7f141a6c2c88560da6c92c2051ed3cc6e10f86b716d0606252fbb5a3e5f110a1279f938813d7f04661e7128de078e8816555b35200dc08f129ee58a221cd88a8541adab51108e9c4e67e965bbe1a2d2db425536307626409ee422678d1ff35bd574d17af64918ac0ddfc265cb519ced65c1a41f717325aba5d7b010001	\\x145eb38980d7eae8db868cf9ea15313273dc0ac26ed4cd2a1ef89e8cfa7384669a6a4f83057a49ce72138f712664491cfc7b81c30fa65d054efd6a879d47db02	1671874588000000	1672479388000000	1735551388000000	1830159388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xcd1f2259cc2212dbd6a3da19bb854a2a376dae7f5995bccdbd0a0dd8c06160fe31e6e6b61e17b0728f1b3441af52d563fa740064d74ade3a78eecf9fd4bc028b	1	0	\\x000000010000000000800003cac94bb78938782b876f50ec4fcbc77b5e734e2ef498121fd179a0fc93f1d2b2a4a3c42d1c1cb2b2825f05d5ad04ac533b2e8ee8948c57fc6e8e13a78a4de0bd7c727528808a084259e750eb46daa1ff737c2d2d6e1ca64ca856c919cf2687e3e499d96447ee60c44325b9283968ae4d36418e1e5d0a52800e1835fc546ae55f010001	\\xe675fc9a6b7bddd25d4ffa4f77bce8766c4a57c0aef6707ab12a2e480c0495124a98173d6b5361cd34b570be3b4e61715dd81faf0a64aa5e4654e37dab9faa04	1674292588000000	1674897388000000	1737969388000000	1832577388000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
407	\\xd1233dd5e0f1522de3656f9a39f1e0a9de07f82afd135520ddb2818898aa2cce2a18737309e369e01c8de74542715010d0c2c301a4dee4ebad8db727b7f26185	1	0	\\x000000010000000000800003b9133a3e3bd39c3f6ae1f07f0512fd64e71c2a1cb5cbf5e3ef166dd5b916031aa57cb58342cb9b9ca0bdd2263bb262c8f8dbc9d38fd212128855d2c70ded681d9dbd36d2f598866b0e0e84d6a51899fab9c86632ff52ef06380afcd999711be783b000ee833d8b4c84624e0f794f74e97b182599296c069bd0b712f171f8433d010001	\\x3814ae5b11d03ae7a961a73bc3f04d4a4cd3e0a4f2988118b8b4e28c1b39ceed25012c0924f6538700785e290cd3daf6f2aea255914da431f18f274d6f63c20e	1656762088000000	1657366888000000	1720438888000000	1815046888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
408	\\xd217b1a6b9f5f42b53c74fae2c5ec59ab2eeb25edd52c8b7bc7d3295cac47043811c0709f9ce0a87ba7ef575940528dd2a186e4a0756ea2b44d1144712b2a4ae	1	0	\\x000000010000000000800003eb0246f7a2c4793832a1522f5b67a3edd5958d83af7acbac01d20befb7dfd15b91b3cd3186888ec63e3466812af7ef2845c8a0692e7c2d2a81617de9323dd15c8c24fe9a252f65085ab6adf27746959afb9ba93222fb36746be012693519931587130738ac77516c1071f309979bcc9d42469917849b524ec9e743e40f9ad89d010001	\\x187745f08511f676f60e3eed08051770a69ad2c9b8fde5eba5cb182408f0c18333a622318cde011c71b73df86192ee9e87c62386da281d81858974ad55841708	1679128588000000	1679733388000000	1742805388000000	1837413388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xd8b3fd433eb92272e17fc1ae83f496917f542678494e8792bae1470a35dd581e6c27ea44ebc14367e18e2ddac9c5617e7b767fa5433fe979dd73c921d442ee87	1	0	\\x000000010000000000800003a207b94d7f91ed1a6b4270a5919a5be82168bc7d5a5b22fda9393ecc9a9b9622fbfd33e29833d8b7755c49da3e2fa2f6bfa0dcdd65fc1dc357fda6dae8195dc52d7f5d610dec89fd32f1c2b807a15650573999515036a5f4eb953c1f5733afd6a98e0ec7391eaccfb6a9d98afd1bf72feadcb815b1bdbde8017f06501686d605010001	\\xe8789e153f067b330e96ec45e5bf07d9e2be8a04a1f5f14d0ad070cf9eea7878c63ec884f65ae92e08e7ba359fdaf8dcfef4f83265a1044b93be3081d0547c0b	1672479088000000	1673083888000000	1736155888000000	1830763888000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xd97fe9cabd773a4069d0a812f89a53a718f3e737e570f8baa66b46a44f6bcc89320d3c91b8a599275d9b60d81e29d8d9e7e183b9f4951a87aa0eaf48018af8c4	1	0	\\x000000010000000000800003d6c1563761293649a5d8687152cd1c921917e5675c42d9686c8ce564888caa0ae1673f12bb1fabac49e2d50b254170d608286221b0c3ee9ae87f445c5a86b0d3b1aed5a4e2f61fd1617449298e6c26e54a6e53d67699bb59f6b53d0922d25f28415415caeab50044d54bb38decbf4c713d777d2682abfaebc3f85840b5711749010001	\\x699e7dec95423a2740cedb02a97f7ad2516bd3fbae5b8c42a8eacb60f7e34b93c2dbbf323d3f0304a31f4ec5db54c37039f6227b181300e6a7c1a69a17198203	1679128588000000	1679733388000000	1742805388000000	1837413388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xdacb49a32f9417e2dde39156279411a34255551e55d6c19982d95a02707242a67cf131be8c7966e6b946dacc479c461a9c42d97a2de4f440cffa973c551f0399	1	0	\\x000000010000000000800003ac597ce81d2e6ee5f3905cc55392bb84436aad4a6b2a12f65a5aa9395849fe08a72a38a2e29b3ae13862d017d0700c9eee7a5deee4ae11968516b67de25209bec3e5cdd346e792e402191503beddb79b2856f2563616fd8de0af5af58e00e259069afccb2f799cbca6f2fdc67faff9f0032731b81dd2e33fedd7124144ce5cc3010001	\\xb4008d73b98208b91548150d63290666de7d1aade1b2e6cf2e361463c26de169b51a1a8331676332ccd9e7efc0a05890c1d5cf005e8c780455d110e0647f870d	1676106088000000	1676710888000000	1739782888000000	1834390888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xdec7a254e809d9a9db010da648230fc77ac7d9faf074b623eeab90b090b08bf661438e9a44ac1c0c91b15b0bdfda92dcdef0aba76a43f61949d9d520beddad44	1	0	\\x000000010000000000800003a391028e42d9fcce385d9b1d9a3de4a3f974201f98cc083c1513f6d92c067bfd8e62eafa98e89dc84741a65bb3aabe3744b74b457e98e42564d216118cd440993bad0aac90d834832b7397c70db1d77ea2c43a4e22e3289e1296dfa92ad83eba767ebf61eaa9b643ce198fdd9d0458e97da01f221b95746c5f503ab0816e83bf010001	\\x5ed6ea37e07dfb2032275907ce16323416675d576cc900389c82ce10c61844147d5100e23b34f576b8afa73b9e22d37e9c1879c28eee5a8debf852296a9e4508	1671270088000000	1671874888000000	1734946888000000	1829554888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
413	\\xe70b2c58eb113b724f30ea43f3edc14843a8629fc1094f651f8486e57ae2cac346f0644b069ef576ef9c463672a828270796a0b06bb374d8dc6476cf4b09001b	1	0	\\x000000010000000000800003c4546166d21fd100aa567a9524b43654e0901fd81f21ab53b561c0d14ada79ccb7a7a9541a0d8348285db36529f8808ac365134ac37ed109cbb40a6906dc2cf6a2c4be46a66a0267490c32136db01d02ba6059c923f6b4ae358901e28ce5b3e5abafccc7a78a5dff2cc3511ca950f29049600e386b5207f93e179d5ffc39ac39010001	\\x7216b91064ac1feff9823476321b1706786356f2d08bce6ecd454ccac685075fcfbc53f08844e31b3bc795dfdb492325b4a0257b4bff5dd1c1797a9ca2d01a04	1658575588000000	1659180388000000	1722252388000000	1816860388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xea53610f86279060e25cc266e33dccbd5b621d64b32c99114d0e6dfc3c0118e464c0bbce2639b6b06ee8dcccbeb70fef8f88e3f550f1a07511d0e3fee42624fb	1	0	\\x000000010000000000800003e1165ccc9210ccf267d7d356bd939786cc605168ce2fbf75b5828bc693b7ccfcbaff4b8a115a3159e133273796c7ff6883b7926f16414ddbbdc6ed319b0b3cc2ad5e8d85bfee96aeb31a16c91ad803bb74c186038c4a57aeabe12cd0a8092b60ecfe5ac7fa3af0cf746f0796427ed88cbd61bc3ca2174b4b1e621d6faf65e16b010001	\\x7f0fd73bddacbe5b9537d839331cac2236b5fa1c48d0e1e6b01559d0fe98b1dc6b9305b26fdaac29ff73f8686be59f1123bbe72e19e97a5ef9aaa4fdf8176f0c	1666434088000000	1667038888000000	1730110888000000	1824718888000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
415	\\xeb57ec478985cf621dd6f252ea4fca21403fa5349cdc1fe65637bc913147c4c40a46cb4e0cdfea84e839bd5592193a98d12e02f0eb4222fab7feba8544a7a265	1	0	\\x000000010000000000800003b2e950c884ad831b1e1009d1c98f44911f2df2395b673fb29964b6a8e24f18504408e6662b86c676edd454111f69b73952d247105e9fae470017360e246cf652b6fcfe7b0c765e271de78e0915042e80a52661fdf4e1165ebdf0e333fa73b5c24b028570bc89e5b76245abcdf8fe69d43c54223ea6b1a7d44da81e6c3469e30b010001	\\x5a321f567f6527d5684506a6283e76df6a87eb5d1902158f445e2ec9bd873ba07727edf9437eee3a0f183e6da45402aa10ffa5520ab26e02c96e3b9e391d5109	1654344088000000	1654948888000000	1718020888000000	1812628888000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xecb361563cda0ade11f9b63b5a3bc120e05df76eb79963b761888f698fb244f194437d57ee7d6cbf4218511b04eb09f07500e9b7f920e3f33a041e7fd4c57583	1	0	\\x000000010000000000800003b45f0db0449e7d61086220f9b42e88628bf26dd2ffa2ac0d0ecc6740ae41377ec1c562c5185af3ee754fc74cc71993c43e1d2809242bb347281bd79c561646ddc8904b8b4245c36d90aae76331b2fe577ce560c34eb1981d5855309426732ca77a17d2ab0eb1f75b462dcfc9eb931b32730110bea5318860f42b0a9794a53b0f010001	\\xdf01b7e947325c700e27f91139eba262968f2326bb5baa71c3ec7a041336c977e20e94760a9c4ec980dada3493b9f2c449ea592b9688b3295dff130744baf90f	1657366588000000	1657971388000000	1721043388000000	1815651388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xecc31a31b4dd4256623e912820df87d54b584d25458b00224c8abd28a876390b855bd745cb311ece164696c0bdf7de68d0004a455c7326a104568567fbd998a8	1	0	\\x000000010000000000800003b8be853cb39a06eb8e48d02b1c6d4e1c609b17457557b6880a759d3b10687caa40ca57aee204beaf597131b7764d8fc0fd05b6f3140f14a950642840ad5538f812d21c0076235e73d96508fd6a8bc8333869336f839dae8c844c575460bb651c2a5f1a8c9155da0907808c1221e9dbab8cb0b0496809d24adaf410e4514fd8f5010001	\\xb0006db5e1a821c7befb42ef9d566d7195f35c105404ea4caa7f9f87279f98a6feee6eef91a1e5a47dafe3f496b67dfebbdf7163bb8cc13f0b783b9d00fe280b	1657366588000000	1657971388000000	1721043388000000	1815651388000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xf10723e80f15956156102f6c8b6f83f094fd9327e9db2c039b9d9840cf28c53b69bf9cc10a7e11442825a10070da0ec4138db1d174ef9662e0de31bdb4572998	1	0	\\x000000010000000000800003c744735e6ed80f617b73483eb3636c506ad702714687992b30ef2795bbf2c0e906843b30866e5e80793ec96eb684d9574dbb1b7cc199635a22168905dbcbf332794ebd069f7ab3e4d262ccdba6a2a86d7ff76a78e4c6f3490ff5d989f986c0a09d4e15bc661486b8437fd6680b17a1ab91c6ee6b9c204f0f1fcee059ce197031010001	\\xe3b660b4692c516b2f211ec2fee9ff6a0f8e42493dee1276dbb5200b08a61863e7f81a0369696d46e9e92d9883c573217d964616f96ca6fafd12ee72ab0d7c0b	1670061088000000	1670665888000000	1733737888000000	1828345888000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
419	\\xf47712c5a51d711d8aefb02d386d21558fa50e9fd4c73fa6b2e595776cf1d02d9f6f9125acebd26c24d642db85500d2fd9de6958a2a00a6cb3c57042478d81b0	1	0	\\x000000010000000000800003990ed87411c28d6138ffcf89e9f33c8823ca3fb49e64a4de37ce6a1b0f20455e93f46e845fcc60937a35842b78fd74f15a25ac40190305d6d657c11dd7a2b3df23ce3d3922f4520b6c4e3db85b6176c95b3885a4b957f2e176ec76da845095d97501a63dad391c658e5ccd83c9fe6aa9e376cfee4dc093b6dbdd811b05f9cd57010001	\\xb4768fee56ff9f6aea4491a6d7346d4c2de3efcc5a321684e91c740715a4cf19ad1c9a8d6c25679fabd7d0cdda5c8d47fd27c2430b5e2f477695cc0d0b96030d	1668247588000000	1668852388000000	1731924388000000	1826532388000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
420	\\xf7afd341592c0a2662ae96baa9811acf966d5554c2e1ca668a820c2f5f5287b8b461d8cf12853db371b0b3e5a44949f25a66cab7016360316a13f079cf01658b	1	0	\\x000000010000000000800003c8c92ef6f9047ccae24e9381617396bbb110ed873287e1a9d8c67bc329b10df7eb5a371cf6e9af070dc69cbd6034b697e9cce3f19aa55999f6d2983bdf294963f0700a5735da838d648fbb5a12a96c8f4cc15539fa151aa93b8d6fbca44509631f879fdada693e9f475250b0cd3c99c624d4195663c0bc2d24e244e69032a303010001	\\x4482c8b8caf9b7996e22d9e486e75f09a519dfdd074006d3b569a957d4bbb2ce6cf6d40cd634bcf4f3d46f1885bbca93246cc3773f72eefe0aca780df8fa6905	1665829588000000	1666434388000000	1729506388000000	1824114388000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
421	\\xf83740684ce829c91243b9e6a464f8574f84c4ae940955c6a13e1191f9b50b899f1428c401261130a96c5ad5b4a7a49626158af712f186f2cae4b5350ecc36fb	1	0	\\x000000010000000000800003988b882743a6af135ab800aefa8ae856c217ae63cc84083505dbc1c38339c4b4247cb501ac03f5a4558d92f93dcae1122db0c630d02277a79faced57cc9da5f5a9b33bc2f1dc704a0a49901c266b6bf4b65b0f8dc77acbf3541533c1d2bba1fa027298e0df27c98fd78811a4006ac2e8623fbba3684215764e0ce9f68a0e8c61010001	\\xbaa64ca7dc5364df9ba89f3bf84aa8b87049e291646705f3a9392f8f749f238ff719ad406e92c2d4b652a001e0edacee5dac6a5d22a1a23d0251da7e121aac08	1677919588000000	1678524388000000	1741596388000000	1836204388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfa6303a0d18436e8112fd5258873fa133bccbf09ed46ac9e99a4f0699a3f97794f3321654cee419727d5dec108b4806138bdd3da9c1fd71a237d70d1ea20383f	1	0	\\x000000010000000000800003ac9b0bb560da40e2faed5c1539eb46d55e5efc6be28c6efe0f4d49fe8bcda108d5793cd534ed39da751bd3a2202d257adde9e2220cf335548e739650f1044f0f21273b9c58e3c9eda23de57603e971bff3278ab54c3c7b8dfe35c95beb54023c21bc16cd468012697b66b7951d81cb4c4b58aa0d482297ecff1b2850c298b943010001	\\x0072728b0e224268a2f032f14a842fcb7778b498c43a2ce64ce0b4dd6bae53a925d6b47b3b602c07e877b3f595c28c244ae95878a46479cfbdaf1c7ec68c9e00	1650112588000000	1650717388000000	1713789388000000	1808397388000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xfc9f0bfd5333d21fdc7fcab2bf25d5d2aaada4a93f8cbc1d930a4093a66f5af316dabc0a5ca1c569a8396c0bd3ef35778df07a66325f49f143bb59ae66d25ca8	1	0	\\x000000010000000000800003b23f886cdedce712f011b3f9e86df7df0a2acb4ce3e16ca1e141d95a6a1bb2bdf0dddd3c2927c29d1be08dbefffff12b9d6dfca931cfc303acda0b0944830534eb12c36bae870ced7b92429073e311ffce66a6e995074174b75cf8364c56f32379a8b5fa93089c60a0e68db89e387917ac2732b6de1453bc590e9d3834c4ab57010001	\\x48877428d4b6ca8ea0344ad7732c5618a9f3cafcc5d2338e8a67e96f9c7cfeccd2434655e5218d3e2676e7d2bc2e5c4a17721905dc909120e1257238a78f5c06	1656157588000000	1656762388000000	1719834388000000	1814442388000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xffb30d352f2000d947c87509909046917436e136a9d864b9b671338ad63bb561485f2ae801d02dcecb7da57dee60b504fa7736fc3ff4435aa768dd8abce1a981	1	0	\\x000000010000000000800003c8a53992db2fbfc361792d83c3b430082f09dc4ec9b44af5bf5ccbc0cb97591ab656e4c2f4370600e3fcab752073afdf79ad3ecaff010e1c0923d8f5e07b8592466fc592425d2a53b8472b45406ff7ec04b46910106b4a02749f40b4439539c36e0c78637d139af03541da12d351382cc7d7d202e567df34f1ce3520a1939b29010001	\\x4ab7ff93c004491a9a6b25c6d9fd42aa5740b0bb95d2ff59a601a82622f4148e2e7d24ae329d501f4019c6051e982897dbf6c991cb90e38e6b366719d967a10b	1657971088000000	1658575888000000	1721647888000000	1816255888000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	1	\\x0830028e28b9f10167f30c0e90cfbf86e0d1bbabc8fc92a42edd77ca8ab02a3acc3ea521812e85f8dbc28317466862440847a446f5eed161df1081e77c4137a1	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x350d74cfa14192f4ead848e9075f869868497dd2a07710e71d7fdbe66b2de27a1428cff3abb0d8574a3c0eb467b15d564d32381e9dfa56de0feffc6703b990ad	1647694618000000	1647695516000000	1647695516000000	0	98000000	\\x429e8d64870a64e8bd497c6a565291b73c9091a95175d82d97370f0f996fd4e0	\\x8569197d87ba73fd49daf4e41c1629b0d97cb7af13b8ee5ee7de9cf4bf47e595	\\x2df46583426776eae07227f539b25f74279eee14924ad3f9efdb8d88b1c49b7eb1d70e81276162b98c2503607c86222c5985d38ab484aabe1e922b8797a1980b	\\x5a73f96d97cfe4b187e933f4447080de03bafa7ffb631c737f793707087b76ed	\\x20202000000000000000000000000000644b90d30e7f0000000000000000000000000000000000002f27b44d01560000205abef5fd7f00004000000000000000
\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	2	\\x56b21cfd664007df37da70f4214721e91b04345e8726fa5497373bde85de39d61853637cb3223add08272097af391d606ed82929c01ce00dae7ce9f1fffe1099	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x350d74cfa14192f4ead848e9075f869868497dd2a07710e71d7fdbe66b2de27a1428cff3abb0d8574a3c0eb467b15d564d32381e9dfa56de0feffc6703b990ad	1648299452000000	1647695548000000	1647695548000000	0	0	\\x02ed0e3d8aec24040055610c5728aab63a823c0a881ef5f9eeb04a81f79884e4	\\x8569197d87ba73fd49daf4e41c1629b0d97cb7af13b8ee5ee7de9cf4bf47e595	\\x982846e9b0ce296b8dfc4c592530d4e7874d7eed459d83c4defb77ae7ea00710972e932166bc421c83ce7b5618b0bc20b1864300b153ca98c43c07f8b3d6ea05	\\x5a73f96d97cfe4b187e933f4447080de03bafa7ffb631c737f793707087b76ed	\\xffffffffffffffff0000000000000000644b90d30e7f0000000000000000000000000000000000002f27b44d01560000205abef5fd7f00004000000000000000
\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	3	\\x56b21cfd664007df37da70f4214721e91b04345e8726fa5497373bde85de39d61853637cb3223add08272097af391d606ed82929c01ce00dae7ce9f1fffe1099	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x350d74cfa14192f4ead848e9075f869868497dd2a07710e71d7fdbe66b2de27a1428cff3abb0d8574a3c0eb467b15d564d32381e9dfa56de0feffc6703b990ad	1648299452000000	1647695548000000	1647695548000000	0	0	\\x0b428bb81609c8b688f6003c627b980db53bc469e398cac116b958912b33ee50	\\x8569197d87ba73fd49daf4e41c1629b0d97cb7af13b8ee5ee7de9cf4bf47e595	\\x607aa33d5b58eb5f9b0bf1d70151feb2d0b521dd5f7a81026e95caf83f664c854ba59cd3b995380f7ab2d866f187f178d25fc88bacc5897ac25c7cda82bc190e	\\x5a73f96d97cfe4b187e933f4447080de03bafa7ffb631c737f793707087b76ed	\\xffffffffffffffff0000000000000000644b90d30e7f0000000000000000000000000000000000002f27b44d01560000205abef5fd7f00004000000000000000
\.


--
-- Data for Name: deposits_by_coin_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_by_coin_default (deposit_serial_id, shard, coin_pub) FROM stdin;
1	1330420884	\\x429e8d64870a64e8bd497c6a565291b73c9091a95175d82d97370f0f996fd4e0
2	1330420884	\\x02ed0e3d8aec24040055610c5728aab63a823c0a881ef5f9eeb04a81f79884e4
3	1330420884	\\x0b428bb81609c8b688f6003c627b980db53bc469e398cac116b958912b33ee50
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	1330420884	\\x429e8d64870a64e8bd497c6a565291b73c9091a95175d82d97370f0f996fd4e0	2	1	0	1647694616000000	1647694618000000	1647695516000000	1647695516000000	\\x8569197d87ba73fd49daf4e41c1629b0d97cb7af13b8ee5ee7de9cf4bf47e595	\\x0830028e28b9f10167f30c0e90cfbf86e0d1bbabc8fc92a42edd77ca8ab02a3acc3ea521812e85f8dbc28317466862440847a446f5eed161df1081e77c4137a1	\\x1f8ea9e347c09b0134421721f4d607e4fc5d09dbf0a0796a0ef61e9b593f7271670a9c6532599e358bed770d2ce043b81c784e7957a61f486f443678a05baf0c	\\xa237b2f45ad840244b94a3abbf76836c	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	1330420884	\\x02ed0e3d8aec24040055610c5728aab63a823c0a881ef5f9eeb04a81f79884e4	13	0	1000000	1647694648000000	1648299452000000	1647695548000000	1647695548000000	\\x8569197d87ba73fd49daf4e41c1629b0d97cb7af13b8ee5ee7de9cf4bf47e595	\\x56b21cfd664007df37da70f4214721e91b04345e8726fa5497373bde85de39d61853637cb3223add08272097af391d606ed82929c01ce00dae7ce9f1fffe1099	\\x6f1fd0348bdab15712d0bb10f57fdabe377a9748d18b36fbd64e7689485342117884e68df7220f93011f911d732e449753bfa5c03839c4a0a626a317c0c4a00b	\\xa237b2f45ad840244b94a3abbf76836c	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	1330420884	\\x0b428bb81609c8b688f6003c627b980db53bc469e398cac116b958912b33ee50	14	0	1000000	1647694648000000	1648299452000000	1647695548000000	1647695548000000	\\x8569197d87ba73fd49daf4e41c1629b0d97cb7af13b8ee5ee7de9cf4bf47e595	\\x56b21cfd664007df37da70f4214721e91b04345e8726fa5497373bde85de39d61853637cb3223add08272097af391d606ed82929c01ce00dae7ce9f1fffe1099	\\xceaa0ac57911ae9aa9bf417985f91fa5d63733b37e2bf8f689e69f995e6b88987e029dd80c131fd2f86286c552d5b5661bc7b2c337fce3af156031a109562408	\\xa237b2f45ad840244b94a3abbf76836c	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
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
1	contenttypes	0001_initial	2022-03-19 13:56:28.845925+01
2	auth	0001_initial	2022-03-19 13:56:29.005197+01
3	app	0001_initial	2022-03-19 13:56:29.132978+01
4	contenttypes	0002_remove_content_type_name	2022-03-19 13:56:29.143558+01
5	auth	0002_alter_permission_name_max_length	2022-03-19 13:56:29.150773+01
6	auth	0003_alter_user_email_max_length	2022-03-19 13:56:29.157388+01
7	auth	0004_alter_user_username_opts	2022-03-19 13:56:29.164315+01
8	auth	0005_alter_user_last_login_null	2022-03-19 13:56:29.170577+01
9	auth	0006_require_contenttypes_0002	2022-03-19 13:56:29.17333+01
10	auth	0007_alter_validators_add_error_messages	2022-03-19 13:56:29.179348+01
11	auth	0008_alter_user_username_max_length	2022-03-19 13:56:29.192933+01
12	auth	0009_alter_user_last_name_max_length	2022-03-19 13:56:29.199174+01
13	auth	0010_alter_group_name_max_length	2022-03-19 13:56:29.207451+01
14	auth	0011_update_proxy_permissions	2022-03-19 13:56:29.214416+01
15	auth	0012_alter_user_first_name_max_length	2022-03-19 13:56:29.22076+01
16	sessions	0001_initial	2022-03-19 13:56:29.253471+01
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
1	\\x84c54966850fb200a43f3c2fa44142f0e9cbf0c42fe306e070f9786f9e776b92	\\x68e875bf0dc509577b6aec68d6e675c814ad92e5fc218f241b293ac4f6b5f7b6111725ac831c6eed8f9d00a0335b14387ef2d64b77d481f9d67e980962afca04	1662209188000000	1669466788000000	1671885988000000
2	\\x4732e6fb4c983ecd8ce3e19c4457bfa4b962735f482494b7cfede7611c5bbe98	\\x269bf7f736a785ce6f2814861fa9a93744d5475dc3912c1ae2265c5b152482fc994710d029f9f9be6c5584b9554367304d908e188a67eff8557651aede2e1a0a	1669466488000000	1676724088000000	1679143288000000
3	\\xa846af8cf49c4537c949d8f77fd1a41f5fc4d1817da7112973435e97d828ff5e	\\xed2714f69a59b681bed5aaee21a0c94058d321b77d3df8b5497fe6e7c2380f8c88eb8072088539fcbd706152fb712c4438094c8fbaa1fa6287ee2922a110f606	1676723788000000	1683981388000000	1686400588000000
4	\\x2fa57c576a2c8ffe5f9b1239fae447ca395a7e95c12354e97e9e80b471a18f29	\\xfc64aac26e4fbbe66e89dd2e494a54ca9e38b23776613b7186d96eb3a775aa1abe80d94b70e626d82b8aad4b3fb314600df6e42576477d464fb20cbbe1469209	1654951888000000	1662209488000000	1664628688000000
5	\\x5a73f96d97cfe4b187e933f4447080de03bafa7ffb631c737f793707087b76ed	\\xb193a56946b9ddb5a9b80eb44d76f717860a67172d7a04e48deb5f8931e84042bd8d5041a1f108f4d0b4474126d07ad57c0416e837d46a34980217a6b5ffe201	1647694588000000	1654952188000000	1657371388000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x679029eb2594574557df35c60f8521916b98bbf7da9cafd619fb89da70c8abe5847c1077f4d7aab96f8fd02b645dade6eb8f889465bc1f548d8113d69aa04008
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	251	\\x402cf62202f01c9affc0c156ff960802b8e137c28e9535fb8671b4d2028d7ae5	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000093490ceb3e3d458d4ff6a9da7b2795c7fe10c2c86335ad8e279fe8030417ea5e873fa218d0fa91a2cd5cdfcef8dc5c81e473f4898639e3376f565095e0575fa9c7823e78f98aeda0fad315de7d3c3b5545f29cb5b74f2141c2d5a277988edfcfe892f8df398af9591b8ef212817cd4d032f3f99936c91e246fadaeb85c0008d1	0	0
2	129	\\x429e8d64870a64e8bd497c6a565291b73c9091a95175d82d97370f0f996fd4e0	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000069449dd2f8c969e6bf276292331b2663d42ba5f9f3295b7a02c4d59f833f7e3e44d777c46a9cc4bb8f945fd66db2f7ca32854113fe7989547878d2c989f512965374570f457f148fa8b7edc4839bea6308b07fb547c8b811f3b50e87b112b39be8d7d8b07350504a9d53153dee91c99cb379b594c3653d89eba1a3ddac2170dd	0	0
11	113	\\xc6814069d86ce4c57895fbfa27a6c50e65eac78084a49dd68bd3d52fe2ae00d0	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000036a3d858fcb80bf8c1052009d60fc9d685182d2e4d69f87dd60a5ecd5b8b5bd3471b538172b1726dd1b6c7c3db59c43c56e406b3e63b796b5e204b6c67d5bbb0c24fec816a5a7cebcf656a3c8217504a4a2d4b69e9be9f56eb09d3427984c434e7be4cac66ced336e23e1b2e4032857e286f47512437b62b840f5fc581802f19	0	0
4	113	\\x07bae6d40f7447809213690b1276bbcdbdaa1c1bc775a4ec2ef1a9fcac4a85cf	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000036d3eb91a36ec1ea42f750b6323a695654c1e3e3c85c2ff0d63b893de0b21c6f79b3f0223c48c824492005ac85e9882188ab9fd431dfd5008a2e3082a016a637821b63adc968745915d35be5ac0ace72cb2979b7e7b64ca203720ec63c938cab59891dd3ed283576b1bc7a6cd418af87a677b3f9c5ae50f64f28182d1d25a2b0	0	0
5	113	\\xcd51363e0097e319cd5a013be8d0740c39b1455c072c0a2090c65db07fee420d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000d6d6ce3eb29fddde13a85000eb251c7f1913fb73211ce19376e26a3808dbbe2a0b9c455d37d34da4b5be0734bbc580602816b94f31421146e1b3b607a7b3d5a9d90505f4ac3cb018175d1e47678a0773f1e3391edc4383a833fd02fa7c65b9673da95220341e46169cc4323a8d51601a06a478b59a1219dcab5797e566442643	0	0
3	21	\\x05d4a6a78ebdd25171f4ad09a43b9808a0cbc7c1ca7a313dfccec616e8204f49	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000793ab3f3dc4afa6f7adef0d7b0015003a624837708abfe8df22b24b72b36dc2ad2712a72be830b0d32bb2dd9a6c674acfce9c96df94bedfe639ced209c4747060c7b6a5d3b053c277f5e1ec266c24d7bb8d7632bf2aadefe65b6cd4cc91a0604a5962869b3489b47e959ee552c229bc08faa78e0bc9c45fc7c5996ad379efd65	0	1000000
6	113	\\x2349bfa2f703b0be6cff7f12190adff4173cbf19f075ec666d165c046b7814aa	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008168df15229d458682383963f3503957971801a7d67b3dcc1d61cb6ed4a7bc208a50dfea4bc4acae09fd419aacb78a61ba4c84bf604529a957ff3d7e4f8645e3407d23ece09ef81b0cbe22b331846b04677f445adfe9d7cc7b06cf5761aa8601d87ad4b35d61f3f7f8d15da592914005021e6430cc90741b8d236a54a786b0c4	0	0
7	113	\\x24c9712114de765d5eabe982c96d0d3663d61bf63fc33ec929243141b472d1f5	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000001e3533c9bf53debc8dc642ff078319929d24219a175922b2686459ead5e1c72c2a8db8a2c33f4614197d55029aff43783d683ed095d339377da67543bf169622c0489b8c29d3b74bdb22532f9024d5e268600317efb42b62540f00409d130b14df100b61265282dc82d85aac324f135a81b4adc9f426ecc1044ed189643636be	0	0
13	45	\\x02ed0e3d8aec24040055610c5728aab63a823c0a881ef5f9eeb04a81f79884e4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000092570aacbad79b62c77775c7a90abf4242dd21a8cea9ab6f6185ae147cf978e0636d07c9efddd7a0830d0b510a5327a739f35229115a8358db88e0eb0441863fbc82e4916c91e7e8d1792ce0e2d9c044cf9c6780541b69a3bb4792f6335e5eeba147b84b7346d25bfe26680add54df9a42d8136978ed1ed860d9b4fde57242dd	0	0
8	113	\\x36ea6e6a4bab402c2cd5687572e9a1f540dac671ab0b078e9081cbdb67fb96ab	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000007170d173badc5792d144207af9f91baeed42b47f4dc3fad87dded0d4854a0e2e73e7233d08328978a22864f573049ab6c012e06f05c44167fd6616b5a5295ecc0510b0e310a0c9f784d0023cf70a70c8c49bb5908b931ce893f3f28d5e056802c0e59eb0a565b1f77f23539271dc8a80884213d19486b7ddd51de1b5e1f42453	0	0
9	113	\\x4c906fd6e1da6c408dc3f4220dfb0e06d71a2955a05d3a9e60a79e218e374895	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003d6c2bb7c3848a703d18d342c72cbf1eeca7f3587233b0750bb8970178408e5272882f4f62c01caf3f42461f12ffbb4fc215b1f32790395a9cea7249eeaee20794a74f6d5c8f7f187f0d662522b0898569d5c4f079628e508d8ce4f8a622769e54779a642e95759de9a464909e6ec619aef9ae2d248e595b8a5d1f90c373fb0b	0	0
14	45	\\x0b428bb81609c8b688f6003c627b980db53bc469e398cac116b958912b33ee50	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002f2f43350cbf8e2c0380e3991367fa3000959e529cd9a9970af2f87f9261f809bc823c751adcbc34aff8cea34d4654e501aab3fcfaa5aea3703997966958198b25d8f75439903c33716905a3187c9cb0c1ea73463a83f6f111aa938d82d13d6e93be48932649f6b87782fab1a70168129ae13bfccbe672b3a68c1f5193550d44	0	0
10	113	\\xb81bf4ff8561eac1e58528640d93cbd691e2ec514034abb5e1a42dde40232a0b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c572a5fc29e89d0b6e4f6ea3816fd170312f5dd77805e9d5e2b4ebf3461b62ed9828ecb4565119a8b61a508b7a0cd4f5e6a35f8fcf6acbda33fc511ea496efd78063a026f5a45dd77cc977241c34c6f4902f5b2b963eb4bff290af06278105a0af6afa8bdeba008b87b28ed5270d429fd00a4cedeab34ce1a616a2783356bfdf	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x350d74cfa14192f4ead848e9075f869868497dd2a07710e71d7fdbe66b2de27a1428cff3abb0d8574a3c0eb467b15d564d32381e9dfa56de0feffc6703b990ad	\\xa237b2f45ad840244b94a3abbf76836c	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.078-024BMH6R8DEJ4	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373639353531363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373639353531363030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22364d3651394b5831383639463954505239334d47455157364b314d344a5a454a4d31564831535258465a445943545344573958313841364659454e563150325139385930584433375035454e434b394a3730463956594a50565237595a5a333730455753314238222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037382d303234424d4836523844454a34222c2274696d657374616d70223a7b22745f73223a313634373639343631362c22745f6d73223a313634373639343631363030307d2c227061795f646561646c696e65223a7b22745f73223a313634373639383231362c22745f6d73223a313634373639383231363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22394e325a3144474d3151465a475050375a534a505259534a3436385252315752593831364843305939385a34565a513635355230227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22474e4d484a5a43375139535a544a4554594b4a315235483950334351534458463245574557515137565445463946543757504147222c226e6f6e6365223a224b383941535356474341365032393339444d53324a524e525456574436434d4631564e57514450305a4841584e48545943333847227d	\\x0830028e28b9f10167f30c0e90cfbf86e0d1bbabc8fc92a42edd77ca8ab02a3acc3ea521812e85f8dbc28317466862440847a446f5eed161df1081e77c4137a1	1647694616000000	1647698216000000	1647695516000000	t	f	taler://fulfillment-success/thank+you		\\xb424750ed04c83b2aa29d16f11018941
2	1	2022.078-000CJMG1FSJAJ	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373639353534383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373639353534383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22364d3651394b5831383639463954505239334d47455157364b314d344a5a454a4d31564831535258465a445943545344573958313841364659454e563150325139385930584433375035454e434b394a3730463956594a50565237595a5a333730455753314238222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037382d303030434a4d473146534a414a222c2274696d657374616d70223a7b22745f73223a313634373639343634382c22745f6d73223a313634373639343634383030307d2c227061795f646561646c696e65223a7b22745f73223a313634373639383234382c22745f6d73223a313634373639383234383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22394e325a3144474d3151465a475050375a534a505259534a3436385252315752593831364843305939385a34565a513635355230227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22474e4d484a5a43375139535a544a4554594b4a315235483950334351534458463245574557515137565445463946543757504147222c226e6f6e6365223a2230373558483933534d303533454b545a334642355a5330544d475a41414e4e524441513743384439424d3759504d4b4642355930227d	\\x56b21cfd664007df37da70f4214721e91b04345e8726fa5497373bde85de39d61853637cb3223add08272097af391d606ed82929c01ce00dae7ce9f1fffe1099	1647694648000000	1647698248000000	1647695548000000	t	f	taler://fulfillment-success/thank+you		\\x8f6bff35652ef41cb6e0ba9092adb739
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
1	1	1647694618000000	\\x429e8d64870a64e8bd497c6a565291b73c9091a95175d82d97370f0f996fd4e0	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	5	\\x2df46583426776eae07227f539b25f74279eee14924ad3f9efdb8d88b1c49b7eb1d70e81276162b98c2503607c86222c5985d38ab484aabe1e922b8797a1980b	1
2	2	1648299452000000	\\x02ed0e3d8aec24040055610c5728aab63a823c0a881ef5f9eeb04a81f79884e4	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	5	\\x982846e9b0ce296b8dfc4c592530d4e7874d7eed459d83c4defb77ae7ea00710972e932166bc421c83ce7b5618b0bc20b1864300b153ca98c43c07f8b3d6ea05	1
3	2	1648299452000000	\\x0b428bb81609c8b688f6003c627b980db53bc469e398cac116b958912b33ee50	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	5	\\x607aa33d5b58eb5f9b0bf1d70151feb2d0b521dd5f7a81026e95caf83f664c854ba59cd3b995380f7ab2d866f187f178d25fc88bacc5897ac25c7cda82bc190e	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	\\x84c54966850fb200a43f3c2fa44142f0e9cbf0c42fe306e070f9786f9e776b92	1662209188000000	1669466788000000	1671885988000000	\\x68e875bf0dc509577b6aec68d6e675c814ad92e5fc218f241b293ac4f6b5f7b6111725ac831c6eed8f9d00a0335b14387ef2d64b77d481f9d67e980962afca04
2	\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	\\x4732e6fb4c983ecd8ce3e19c4457bfa4b962735f482494b7cfede7611c5bbe98	1669466488000000	1676724088000000	1679143288000000	\\x269bf7f736a785ce6f2814861fa9a93744d5475dc3912c1ae2265c5b152482fc994710d029f9f9be6c5584b9554367304d908e188a67eff8557651aede2e1a0a
3	\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	\\xa846af8cf49c4537c949d8f77fd1a41f5fc4d1817da7112973435e97d828ff5e	1676723788000000	1683981388000000	1686400588000000	\\xed2714f69a59b681bed5aaee21a0c94058d321b77d3df8b5497fe6e7c2380f8c88eb8072088539fcbd706152fb712c4438094c8fbaa1fa6287ee2922a110f606
4	\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	\\x2fa57c576a2c8ffe5f9b1239fae447ca395a7e95c12354e97e9e80b471a18f29	1654951888000000	1662209488000000	1664628688000000	\\xfc64aac26e4fbbe66e89dd2e494a54ca9e38b23776613b7186d96eb3a775aa1abe80d94b70e626d82b8aad4b3fb314600df6e42576477d464fb20cbbe1469209
5	\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	\\x5a73f96d97cfe4b187e933f4447080de03bafa7ffb631c737f793707087b76ed	1647694588000000	1654952188000000	1657371388000000	\\xb193a56946b9ddb5a9b80eb44d76f717860a67172d7a04e48deb5f8931e84042bd8d5041a1f108f4d0b4474126d07ad57c0416e837d46a34980217a6b5ffe201
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x4d45f0b6140ddff85ac7fe656c7b3221918c0798f20268b01e4a3e4dfee62970	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xd87138f99ceb81a1098d98704a59e70944036844268d7f670a156cad776ead27b2fa5fcd5b2a32e29d0c801e21fcc91c15c758a11dfcfa186ba0bae47f2b2603
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x8569197d87ba73fd49daf4e41c1629b0d97cb7af13b8ee5ee7de9cf4bf47e595	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xfd29ac2b775c39c22023781905dad24ef8b93557f97e659f18708d2eef54d94e	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647694618000000	f	\N	\N	2	1	http://localhost:8081/
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
-- Data for Name: recoup_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_by_reserve_default (reserve_out_serial_id, coin_pub) FROM stdin;
2	\\x402cf62202f01c9affc0c156ff960802b8e137c28e9535fb8671b4d2028d7ae5
\.


--
-- Data for Name: recoup_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_default (recoup_uuid, coin_pub, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	\\x402cf62202f01c9affc0c156ff960802b8e137c28e9535fb8671b4d2028d7ae5	\\xa30c2d3b415022f117915e7d800611cdf1c88adfc113412efbc0a4f28635ae6c3d04fe7a7d89501c3f43c8ec87d1d7dcf4d611914e81c1dfa4b6c33320a50203	\\xa6bb10cdffb79eee33209a9dcf800ec5317607f1b11d01ecf2f3fb91b17df6ef	2	0	1647694614000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x07bae6d40f7447809213690b1276bbcdbdaa1c1bc775a4ec2ef1a9fcac4a85cf	4	\\xfeac558d21b6a47794522b70dc2834fe292b7e9e81abce8321265e5f8bfa4af67984dae5db6f013871ba85b032efc0ebadf7e9eee0ae4865dd1ffedd42566b0e	\\x23fe47b4b5d2f27216ba9e5c5bb47700d516fc44f2c9e8c6823fbc4d7b164994	0	10000000	1648299438000000	8
2	\\xcd51363e0097e319cd5a013be8d0740c39b1455c072c0a2090c65db07fee420d	5	\\xc7414f3b7dac52414633cbf7901b5bcbcac995c178fe17281f30dac80cf983a7a0c768a61c41515d16667e9802c0dc19ee6472454f771a81d3716fa92b022f02	\\xac8ab73e2a11047c4e2b4f7c87743a9438090302a120b478e81fd6c15729a812	0	10000000	1648299438000000	3
3	\\x2349bfa2f703b0be6cff7f12190adff4173cbf19f075ec666d165c046b7814aa	6	\\x4c87639647336fbd8a6062d14a8482248c39df700fb10aef71719b15c9f24f7a6a328d971e40549f92fa173c6e19425ddb926a0e9c761c75443bfb1656989c07	\\x3568a9bc5a7c2067cf9a12abb4842ff59a380305a9b9aa7c818c72e375dce596	0	10000000	1648299438000000	9
4	\\x24c9712114de765d5eabe982c96d0d3663d61bf63fc33ec929243141b472d1f5	7	\\x502e27282ef3cf0b51630f350333ca8f81cda8622ecba3a931ec78db7bbf2c64594562f69bfbfd9269d03271f170ee31b2bb2540e995ead30117a6b6b64e8a00	\\x0db7976bf35bce9d858162d4dcc845a560f39861717e8a966c2de76b56ae2de5	0	10000000	1648299438000000	4
5	\\x36ea6e6a4bab402c2cd5687572e9a1f540dac671ab0b078e9081cbdb67fb96ab	8	\\xb94233e9bbe7c4b673094b7f85a9b70641a90cd0523fb4e51600f066d170a75858f5a5205eeac13e34f6a30a0605374633f7afe918a4dfe0e52d6a0af137e605	\\x9f00735dfbb98609b6b42d49707cfeebbce1b28b5786b4f629bff7278a1fd855	0	10000000	1648299438000000	6
6	\\x4c906fd6e1da6c408dc3f4220dfb0e06d71a2955a05d3a9e60a79e218e374895	9	\\x3343f8a494435640ef9029eb35cc3004639af84e38d88b32b062c39dd205a0755b9083df1456cc92319b9e9f9ee7b288d3c8807016766dfbad6fd5775419fb06	\\xe9929091a0ea99edc5a9729ca1ba4a962cfeeef0bebd9ae7a83c99d15905850a	0	10000000	1648299438000000	5
7	\\xb81bf4ff8561eac1e58528640d93cbd691e2ec514034abb5e1a42dde40232a0b	10	\\xe0106c8e718c5047bce0ef878686e89af7deecc4b04e2da0c8554815dedcf8521656dad04a8c731fc5e90053982deff20af00016494521d5d8768cc4f8e4b009	\\xbc1ab626995c8d21b6feeaab800347b6887a798a3bc0eb5df5de4d57fd6c2943	0	10000000	1648299438000000	2
8	\\xc6814069d86ce4c57895fbfa27a6c50e65eac78084a49dd68bd3d52fe2ae00d0	11	\\x34318f415289b583b08513fc530d4252aae27cdd18469869e7e0660fd0f4c72e8f20ec4de283fa8cb6dcd12ca9e0b0a92d03ce8b1e9d0ff28b2b987680e39d03	\\xbfb22d35b37f8b56b615b52b212ea6a8e3e8638452139c0ac2035461b9d34c01	0	10000000	1648299438000000	7
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x3b1431ed89dd238a4c021e187f255c2cb4b21a61fc448e76cb0a5f35749b70b583ef5e290117d42f36185f0a30082a6f3a92fa05c3d1cdf4ada1eeb5628ce8de	\\x05d4a6a78ebdd25171f4ad09a43b9808a0cbc7c1ca7a313dfccec616e8204f49	\\xf01e4adefa5fe76796a1fc5c480ff2788d6662e66e871531fb25421306e831e8daa3c2b2cfbf0e580cf19f289ab4ce1abc34bb1e27cc3cca46d7681df00c0e00	5	0	1
2	\\x8e4833ab2687d2bf07fcfe0efae82cf041b36bf0025fd02e6d5306e5a3c72250bee008aea0eb96e16e8e4adde88a14db832b81c849854872c379932ff0d6d2e4	\\x05d4a6a78ebdd25171f4ad09a43b9808a0cbc7c1ca7a313dfccec616e8204f49	\\x519b214d4ca324bd26e15d4f1c6a1ab50f0cb87aa3d700fde02fd1a5b19614c420f3aa8ca3abda0f333095a98b0add48f4dd1e510282b5172d97c6a8c5996705	0	79000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xf807eaf01279a870c85aa24911d49d7498689845dde5de6c6ba656b947abdeee194ae495726f48b9c7b9aeac08f5adec5106037cb330909fc418f951c458e703	356	\\x0000000100000100a3f11a21ab78de32552b82b47de0b6884653345fc8d86579febc4e553583f783ee128d8df1aaa751c20f5c6907a7001233e5bf31198c79ea61fce5a2c0ba1685a1a4c6fda5b33c71d971fb2d20c8c1aababe6283f8c669c9950d45c09021e1de165b0b84e2503e390121b3a899021e8547886923242f3a6e7c77a5b6a7a1b95b	\\xc2846cbbfbf97e387afa0bf09356f5b2585f33f56dbdbaa7b1100c82de1faff2041abe9b19bf50d72c617137563619b6b5536bbd53c73c48e3a96ddc0bdc4824	\\x0000000100000001354eb1c9d9fa8b4ed026832e2f2ecd9efefca90bc9a03dc8d7d494b6b96353eeb2acef3cae416fd85fe7b501acbc56cfe99c5fe3662908544fb1832b32aceb79c57b5cfcf1e47f4f651162d01ca5a9f27bf0b0f61fefa050c0fb17d8553c8b9dbe234d02e2512566bfdd69c2c2a71aeb3e5b50d2b50cff2a51b132edf96fdce8	\\x0000000100010000
2	1	1	\\x164951cd991de3ed2c14ac2f363b19becc53576ac4e7f615f09099a53c9cab995ef2583a773a3e5c44a668410139031d0dad2465bee3955330ea40518a047d02	113	\\x00000001000001008de552d189e558d9479865501cc6aa90029ba9069fe91273f38d22f9b3bf6ca8870b1e1288f4a2222e702cc56caa0ac2aefe21c99822f9f1e8924300979e5d7c21a6823d1a8d1b8e3adafc71e4c398c50ddd4159b790e2c5200ff871f8c1370062e595c52c56cbea4fbfed71b90f80adae6afd369d6fc7f075294fd09a301dab	\\xd6f25bc391822b29d56152279e1951c3b39ae7e7e584bc55f3146e2e6b0a4f26786ce2343c8d543231360514367767040020671921f1b02732e3eacb4973d9ba	\\x00000001000000015177c28c15e7eabc96fe4edbffc8a1af66f537fc4789915591b5d518f8ad0823d94a090cf129aa68771b724a1eae416038def21a43cf4f6143b05142f303b8260932067282a7909788a68fb1cb70ed693d713424a468ad799b70b82ca4a0e905cd0c833396b160d0866e3d3d614059bcc489bfb7e7fe1ab3084f93cbe51fe7ef	\\x0000000100010000
3	1	2	\\xa8cff3af1ed7b72fb44860d2213d95f0f7c7050ec04dc34834714be3b0e17a1fa2f07a3dde1780a655626bf42370b12ad79f3c039e0ea6a5c7a102e70ab0e103	113	\\x0000000100000100774267a17f6d2f5abc7c2fed4478bdcdc64bd17a2c509bbe23ff49e237eff4c962a104b2a7148088cdbd27a512c6dceae473802c015f025e8b5fbdd806e60b521a9699bb38b8ba45ae788476331d4c2b58a4a9afa8f12c7f876bae587e01b5fb97c95e5366232bb2cf80a7f5c5a43ca3e119b3501eab523ea6848714d8beae64	\\x8bbbd1784d4e4ca490477d54d1c3dbc8af57949706be1d0f4baed27d33d0f7b43bb00103b5a186664031bac35b6a320b0d431175522ba66e93fd0c00413ce310	\\x00000001000000017f6a518785e68c5372fa6cb2b596d15ed781d84c8adab5bc151cf81be85e50e92dfbb38648f2324e8a09ac7ca631f19f9210848f9f566ef94e290d11db055377f309b1aa6d833a3b2ba56d9e85e28e7bef704fc5ea99d1219ce6c03d911394cb770331b82917e01bb9e1a425e34898bc410a6f83d9fd38b2082dd62c42e50ece	\\x0000000100010000
4	1	3	\\x7f4becadd40f05a4d042b293853cd2713113ccf63e935676a22b63f489808bfecb7a371160c25c8fd5296ac3dba51efe785eb4c520f8301f48e9c14fc1741907	113	\\x0000000100000100d52e3fb45fb3b216c1d4995a43ee6844323411e2e4363b16759eab29013d403eae2d1f5608d7e80e1ca8dab36f4e4ad5d4abd4ea33f091121b36f3d41ee2be5287ef0e964542bbfdcabb390ad5dafc291c5897e17b111b3819b81faca26330ecbe90bfa6de5f1d0a8adb7adb9046ec0404eeeab0f44ffb6e19afcca9b2743bfb	\\x58ff3a98f3bd3a68e281e6d2fd997732fa27038fca01356675ab45162a58debbe6f0ecd94e5f0bef934f87aa957eca553deb2b70c843580c88c775e2576b5dff	\\x00000001000000010786770bbd2401583e335ee861a53310a4b02d2c18816958023d581a77f3f68063b3d7a01670f51699c34a002deba7ffd1e5b2afd61553b627c81c781ed672ea5cefd42e2e5aff7608078728451f865da5d57ec8186d7a61416d9778f450b8021b4cfd93b0950b817b8b25bb79f1aca1c9f531c1becf8eaf866396f9e1576ffc	\\x0000000100010000
5	1	4	\\x152d457b0f4e2096633b95458b67cf4b176dc89f4dece61c5e279f6ce2c0ba757cbcfe6528d281bc38c79498dd30507029aaa510b81ea31aeecf3e5b55abd307	113	\\x00000001000001002acdc6b259ad6f50af096aab4ab57806eab10d6dac4fa3a47e2637e3a57810198df07a1f81b7d3e50d684efbc0384ae02cd8f70502e9d3b6486501f930d416b3399082134632f2beeba6875ea5387c917175646eef0cc55ec1d6fd3ed1f9540b9e673a8f5cf566213c6c5982c7be82a16f111ec108d4ab0a32b19cf9a60f36b7	\\xe53bdd0ad6fe9ce30c6cda183b1b2f3e4d5df608e4f4201002bd97a7c41ff431ea046e7b132b03479fba0ee108f94c2b6ec85a302ef06532eac8eee24081885e	\\x0000000100000001ce04b1b24353591490da5c1ec67b3975a92f9ded5dd33787cb5a1d20f69a25f1529a82808c6be3c7e85486da4bd35fcd83dcca182dd6de4f24af2771784cf63502ca8b4c0cf571c85488bbf79c7bb248021e4b3306ecfcc21d44796585279349ce9879d14df6c8f5ec94c644aa5972389591fd04fb0e891ccd5af31bb629bd6c	\\x0000000100010000
6	1	5	\\x313f11fcfb54ae110d9741aa8b272efbca6094cff21338084f79ad62cacc1314a5425f4ce5d5d0284d02c31f3343bb47f66387721ba24bc40c58d2aac509ad09	113	\\x00000001000001005c76f902f4dd2ccc1a1819900afd21e0c45da24068abd939ee918342b96c6890f9ff35a6f62b1c53e4b9314cc9d42ada253065292676c5a628cc43adf38c05e5321c34d6a5acfbd9f17aef971772c8516026411b190f629f431b00ee17e3f308417644d15817c70b370a96455679ed2e64776ff7cb1085ebbfc34c68833b6b3e	\\x60400a47c24db7072c761296daa9beb50c971d826bfa8010c736f71514cf6c06639890feb2880abbc467975601d12b73328fb2bb9761a418650034d4ed69279d	\\x00000001000000010861c2e5514bf42c9ee933776011d9d4545d47f2bf0d18c6e2e4222532d82d9ca6cdb1d4bcaac162c39e5bdaf106b2da5818428e23e3876397f4ca594dc2d8570414cf2677288e12ce8426fe92d80aed1ab2be5375bd3027932c586d6340dd815211eba0de85996907cef5d608cfe2aceba1ab8186aa0f1eccd3ae414db7d59a	\\x0000000100010000
7	1	6	\\x406adb7c0396a40d07bf92a1206d6c9179c43d66f8713c125a1c167ddd60ad1e5f00388afd9e7e8234592f24071cc45d8f08b26be6c5faf75df5733d24102801	113	\\x000000010000010062968b26dc43a11bf0e96ba1bbfbb8400e2143ebdb4c0b63388aa31b03ca8d5d9d3a4ce51cf1ea81ce0a8ca85660fd73a1c26df5c1f36ecb89d04db94acec982994f17fbcac4347831d53057733b818bc07cd7773989a3404ce70985515c1b99e0129999766d0e08f14110fffa3614648947412d3a70f9c342172907d0ef75fc	\\xfe2adbe8d12cf60b2842cae6a7bc56edac335c204a7f0c59b7d49efedd7802c1118bebf98f05ceb142d79976366c22decc0d3dda67bd50c8a91ac94d62f514e7	\\x0000000100000001d2d45277471cd02cb96a4330429211d633ef7e2f670797aaeb62a93aebd220cca1d74adcf2f084c898aae5e98631351a5cabab0a8e65a33349886baab4dc1bff28b10ec98f092881cde1e84fc2b1b9c7f463edf84199af0a772c536f6cfe511a1f1ff845b99d0f020bbed5e34ca6696fd5467ae6e6ecd89cf34b45da051bd6d9	\\x0000000100010000
8	1	7	\\x8eca779fe89203024862c7cb483190a4539d110618fc638720571cdfef503052d3a067bdc1fa7eea311552b8a8a02112a32aca24032190ad6c3402c0bcb19d03	113	\\x000000010000010089b569c4c65f2403d455378a6fbbd9ebe2db821173ef0135e5f6237f51ad0c481160d2e3876f43fdd5b61ccea755bfcdcdaa6dc54c149d56a1ab3714767cfebac0d94fe845efd651d0c8f434bbbc1d6d895c21909cceaa491c70529191f922b633786d8b1b75d6fa0cca39abd7e469a9508950d799d6841811eaab1855b28c79	\\xbd90b4cef5345c095a1d137a249607cad4f0f00bcd3c4280f48ecc297fd323cffbb2e2e5f86acb83394ca9d4f9b80d637131f22ef301b29ff39938fe41cf1bdb	\\x00000001000000011b1257814e67198d24dbeb7995e841b4bf87f3d095c26851789ceca709e0523743e660a9c9af414187a2c56ff4c5961f512674fd8395378b6fa5e930b9895aefd6dc52509bf85abe96c14df06c20a30396ba95e0c02ec54186226ca7809c50e7a17778c6cd4a4ba4df02a4352daf27fb4b8807c95efb85b63b29929d66ccffdf	\\x0000000100010000
9	1	8	\\x77cee408f2586ca868b8c0b1700fbe646beea2c5441702ee85d4dc3b565fcd3ec2c4ce1c4235b0c518152a2e76f54051de3b991fb2ad68759ac6b95686bde207	113	\\x00000001000001007bfed344f1f3b1fbff806420aa59d01a81a91b705f2cde3a5924a4d0fcea977cec2b7dd8c4ca512cb9986fd1472b1e9faa725e59a50f38a4cb28cd710f680b9e0b81ad42312f44ed1514c489a5252578193c7b1f2612a96ac2ee9eea34da259b1a9268d24675b473cb03ee1e836bf2cc9c74a18641d1a05e37148045c6578c90	\\x0393412ddea5f419d98445f46eb8112c24856131a3047236a581af4aa9f5204f131a36a8cb7b76616b40a2144511ff4d71f876109db7e611efbb0e5bcc729947	\\x00000001000000017d4eae406173b9eba883df36c0c58ee9cc50070ab11c4ac29f5afbd46f9da9d17319a492cb8f824cd0b7bb00c2b4fccee0b5558c68c1b556012832974e7d5f517b828c415fc080ef17c0d2c17f064a47b795f7b9894deda0d0974e59a8df0a888a12378601f75c15f344b0e9620953766a7280584585f303953fcb203688a2f9	\\x0000000100010000
10	1	9	\\xf7237369170ae986d861c107da7dd0b18e5de706545ac8897bb0526026c9f9095172919c9ad8b02d2ecd3d6e77c6d3be9695d53533669efac9e3ca0d24fb2d02	45	\\x0000000100000100ad3d883adc2b891a1c9c695237e6b7b537df6f07f4cc4a7c3512a28a886c676990bd4ed4bd222f74c4e6a18526a5e76acf627afdd9de57d4521ce0de032b0cc3cd77f4343400d24bcc4a7309adab9e9061ded4bba88d60097fabc9f6c65a62d46df4993b31253e8f540f3ab4191745b5680f54cc831b118714b660f8c080763d	\\x89c6a839dea3db21d226085b3f271b43eaf12c25b14b873c027bc2e595ff09caeaa072ba046453316b85e2bbeac91e8676fcb53147f468e01717454adc41850f	\\x0000000100000001821e66669f693a06d8123f0f036c5f202206990a2a2e52a62ae6e2d8897c04f09edc2af30a1e8a26f65bc9a4490088571490237ac0723731ef4122a7e1d4a06e3beb8d9046e41df435b267c1ed9f21e85f7593e50970a476188f33399e51fb6184b187467fe7f6d35a912351cee3bae9ce0fdbfd5bceb5850e3cb7a54182af53	\\x0000000100010000
11	1	10	\\x6b50aa21774f4f47e5ba684755a8c18f104e78ecb93bcac4ec231a141d58a2dc9491decb74e38bcc2fb7bc764a59e1f0e272d3d19a55f3c6cc05dfdd8dd1c50d	45	\\x00000001000001001b23938c48bd8db37fc4b9523ced54f7ad5192878c7d617fccb7e67a566e2b53063cfb0c2ee2b26be37872947adb5a56160fee33dfcba32ec18c97d08c71bd526909fcf513028b20705987fd797d45b2445d98c0e41604f0c1677fc1376a94708983e021df94bb86bbfa7ff1cb3bd4e97ad5d3fa745443c90094c985b1c93a23	\\x39f3dfab812a53f4c50b50a4be6ef83d53e242863668b42fd8dae203eaac8fc99652223a6a097677efc307d5c9e5ad0e87b7d511c49485ee2b37c7e86f6d76b7	\\x0000000100000001ad0727075492d3488ab0c552a182827924815bccd4fb6cd6449c90283a40241a32fc9f1d1e3d82601e4ab24412c08727b32db10e171056fd85cfac64a4bfe912e82c5f346cfd5450957b94617099cad6a650c7e923785fe88ad99a49561b027530fb2bffb23b1bfda0eb76b5ca573f09a7d7b4c1c5f30761c95b00a10ca896bd	\\x0000000100010000
12	1	11	\\x217196e8b9f39c8e7cd32e4c764214273328965c86d7d48306ebf933b65702f8f6026acc5d163731616c0e1d0a306f8ee277174533b8a5797d34b571a681d008	45	\\x000000010000010099cae264d683bc363c829f19b76b5abc6ce42c4e4e667342c519c24b7ef0b12f2882d9c4b89b30807bfe5da11c165df33a39eb835dec66c9a00a19bfff8c611044b963e0780ef12b1507c75a7c660460d9184997e4a8ae0d056dc755bf1c3e529f6d6cd9f802e263157e1dfaad056162ace083df0a4111354a75ba704263044a	\\x9fd8f5f1b002d1862ff3a4879faf8c78a2599c69d5b5b59fe76d14d51efc643228689f14b675cad25fd59f783ca8f008eaf4b43d309da5c8729ff42951da48fc	\\x000000010000000128ee140bc48c5af3a66362950a8ea7bbadd99588fd09d41a00d3a918e7c3cc5df75db8f04759a1010bd1e9eef40d5456b1cd079cd2a8619bbc16618e09755be3828dcce98d0f062b2bb7ffa17b90cbf1614ada82173eb03ddaf8b97e4cf2d11294ac8585c59c9c0c69b254d09908952fbafe97f9746f077a770621a1f714f116	\\x0000000100010000
13	2	0	\\x37bf500dd879d5cf612df00a4b984c5bb2aac660fcec6d9724dc0805259e67b7ea933e10b4220c3ecd5213589776237ebad0c67d5be2b6b4c52679288e47f403	45	\\x000000010000010052eb5f086ebeda7ad6f92f4dd762f8a587353741040abb68b7ee27509c3c0d5e758623b984e550ba8149e5011cd6026bb303b569a6883d9afdba3f1cff8f62bb9ee5e190cab7e6d214c85fe81583a27ebbf99032caa188bd092090603e263242b452c0e30e18f6dd0a23f9d0b47927fbf52bbfa607c485681793765939d9fc35	\\x1326ffdc62a220da417b2fd3a4d073d0f1c7e1d2c7937511b53c344a4b31475da9669dcc9fd56413ff2d1859be5322790adee8bd26f601a7614410782cee6cd3	\\x00000001000000013a1c9bd07f2b212831707849974d84dd6fd40d7be2a02fbb85e9a0f9f33faf3df1c65c0db389856831dc8b0a5c2cd570f7bb6d415df591ef0c8b60d7ab9ceae9f6ef498d7aef46747200954cf77ee8d90bac9c801003c93a5513410efc63fd533604feac5c686bd4a8cf88705758066ecd4563d28ba719b951ba38133a9c21ec	\\x0000000100010000
14	2	1	\\x4e6a83f54822eeec80f164b544845d1e45c5de9d1af6aa933fd42120c2a66fa990097d2f49a4a65b41d6e2a3ff3739203985924a73e5cec43af58f3d33a81901	45	\\x00000001000001001690f50695d0996457c0ca3affa39d5ccdb0f54345fac40be00982ffa57e74e68c3f8dfd22167e2841088891fc7ad81528ec3e4d2a3f9674beaf5d9a57cd4852ab2a04c9d9d47c46d4e76726ed9e1e6df9e6c692376ad350298fe8d19de9ade17731505f4bc7d91847cc74b9bee324ccf14aba2c50cc99d6427d4f4ac8aedc51	\\xd360db1daa5639f88e85df58a6dac2f77efd4969fca5dac678f28977ce83a63a3f1c4ef6a758ab141c634e26173f0154ac6f4c2d39f367ed7aa42e18f958e1fa	\\x00000001000000012453826abcca906d0e48559cc4ec81b4290dbc77d0de497d5d991346842a167ee408fe5f8274428685c9161d310f6a947dbe2e445db78b8261bd3077ff4087ebf83ca8d506c84e65027a7c33b04ba8a55c0f7daf26a1c80446e320c1f9be2d1be38954df22ce238dcd980451caa7ae63b251434776860a8170929a2747f53c84	\\x0000000100010000
15	2	2	\\x0c14f2b5ca6081a1847b405bc76b5d4a0c1e6c88bd831e31c88844f64260676a1db058d0516d4a6436617874b39610a6cb8bac994767e4b2a680c60166e55103	45	\\x00000001000001009db1b7d9ba781a022984ed6cb3eaf8a06f9b0d10d89bfa22f39a51b92926df1f68ebe464ad0ea331e08d6023efaa632bab7ce89f592f7be19d3dca7558cfe8421ac1b9db361aca6e3bfa4b18b45f32f0720bdf7c05b32077e3fed09aa77f7248d8b29972ade6b6806cb902913bf40a58bf71dee2e0a60f758d04b3fb3bda47ed	\\x29187829e72065f9e88bb3009609e08451fbab334a1ca0f1f4817b2e9d2f1a2c593add03791a6eb6e7a104971ee321540febc500d56777b9ced6d5faca071d4c	\\x00000001000000016ac8a9cc304794c3df33040496603c2875f484709b0cdda03c11c7ea2b644d03063fe72835da16661e800b32d1dd1cfc6f91346aaf9e96a66b32638a5542a49b24c63d2ab095307649d26162ced2deadd45a36318700607228c3bcdaf808cfa9dfc54aafe94a0b39b5c07488192cc729b59d06121958165fd221c6decfd4d09d	\\x0000000100010000
16	2	3	\\xf6556e6e40f5633160dd4350871d4d3f3ec1ae33b78569b7a629d67945deb2c19d55253cc99c2a2e0a9892dc1e264543aac6cac21a7ece39ac6918cc328def04	45	\\x0000000100000100a76821830b21912d0754d2c658af8aa3aff1fcb96bf7ccfd02dbc9bd5272c75e790f51b78ab3badf5051d51694aa0651dcb8caeaafade057ddf0f1c8a82afa3e25a8499926bfcef17ecbd8f767067b9b62e7424f379cc77bc5b5de1bd83b841812643074fde9cdd6f97daf58f0a7cee2f9528f41a6bb8fa04d23a630c154a0a9	\\x997548d872f654686fc6e4a91dd12356b3c835394fae6657fd218c52e2bda3c0ceb147947ddd329c670789f11eedd7557201e4147bd5e6294e18566657fdb084	\\x0000000100000001ae44b011345214283c9d68e9459292ef704cab39292edd0d45ca902cabc9c2b6b7d3c609fa3ccee5265df1e76aedd316dd5932c63e0f54e7a2a5473a23e211ff50b081c8152da44fd82bdc10ea0e5f50ca7c9f6ddd65dc62f9b3f3c63ece53ee4191098cbd8ee0fddc18e1ccb4cf4e9930b0f26bc6ff734b9da12813ae679d7d	\\x0000000100010000
17	2	4	\\x00b9ca8141f8d586994fc5efbc3430b5713163e406987a8e26f8350790d84ee6f53843500851bb92e9ddbf17b0a9881ec68a6d113a1010e5c1a52633c00bcc06	45	\\x0000000100000100a61757ecce7743b244e80c6b4b3cc674f4a38a5b53d405c5932b941acd0177f8e4895ece6c18e5c44cd4cbdaaeed5fc645b3f4841961d225650612fd3551654a484f5d508c88e9bde6b2dc80161217d84b195510dd7c829d1b29aec72ee36a83acd12a8b808b8b9e280758c78c20ab8669d720ac33fc85dffdcc46c01df81fc1	\\xadab2db4806c862125323773e90676fc918deba665816b838d898042e747cfa35c056bf6d19a96d442cace32b539a9f92ac7ba4b9ce30dd426a264394bf39dd8	\\x00000001000000011d5ace38559ed35783fa7ceffaf48327352783b766ffb04e3bbba404565debaf5d0bd21bc1c1aedbc8a7b3dd2dccfa4d5e605f97c70a9f446ac0188b7d204d1d2010b5a7ee1cdf36139281b315ed6c2f911ec5d60220280d75d28c7be796286d0e586c1c00217cf0c6b03e0317d690aff302cd489da163d0ebbab14a6f38c7b0	\\x0000000100010000
18	2	5	\\x50828bdc3a4a68e48f0e83aa9e38c75d7790401caab54c93aa948ef9a38465e6876ab9568d7f5f372587044a13613d8ff8db6385799a6a44b8e27d06d716dd0e	45	\\x0000000100000100a256590039e491c0e7cee34eb6cbba9a0f79f7c9b257203bab9c8b26f1e78a4752495c3dc01dac321a52f04556eaf4702291cd650fa1a89ff43d46595da3d92b5ced04ccee42b50088d30c8f0e5ccc96d829708718a32112fbda73a139900e4280c4d69cea2119db370c214210d3eb8f2a3c839db68a9f0176a31f9441f8b4b9	\\x4f2f39212e614560a01724309fc1470a15969416dfe16d7ac06f8cd74ed16b6698fe61bb03b5e4e3905da38c9841a8f8676099273e0ca166a3dc66ca2d0f3caf	\\x0000000100000001a8ed6271ac99b4258d1a2da413a63fad1b8abcf2d44cac2aaa18d57966c983ef8cb00b5af24ac38bd7b18f0f69092dd38765001d1a43643c7b3ea945a115b0de76af13ca165cad9d6b29cc11f180901032f2706098eb4ec32130d7d3ed7e218dd7fcb7fab4fa6f444b296a06098d453b168776fe08e7b888e70a49e9b1bf2c59	\\x0000000100010000
19	2	6	\\x974e6c46223851e497f4a6f93f22297f600f016af83dd79e5ce88725a7acacee9ec4fc8863002a53ea3d716892a42a646486011a0ccd9dc71370a083689ad007	45	\\x0000000100000100444163ad0b6c3feb929622088dab89c83662c4dc6c9b89e6672b7cddbe4fa46e6096a9d45c23b98ec7c2d6ad723492778fc1aa842312b0f2de4ac54aeae07c75d4bb5f825c868b22a6ae6207ad434f556881f1b272ba32492ee4a8f2260e0db485f762b90b9c7fcc380597a1401503489ac838988b336e765e9215fc570e7107	\\x014e9f8a5bee044bbbcc3d5f1e9bb734f57248dc2f64e657d75d8e9677beefacf0443c1dbb08750d979db6157a530eed75f39e678f36a7fcae94fc83b369a62c	\\x0000000100000001a6682e74d0cde5d7e01d6fba0793db15d2f4831b28d9f262e7f0b7bbe34c930c5eebee727ed9d39077951dcc7359df82865a5a0f4a79e62094ab7b930daad8c31415f0530a541a6c37f0e38387425608ca321eef117cbef23fa26393c3d3cfa01654397c819fa2385ccc99e44120244e4a6da66e9e173038bf7017767a4b60bd	\\x0000000100010000
20	2	7	\\x834206749478e6ccb8314eb14cc47c0398085a39d7675f1abe1beb820ae20d3f9c6f58eeeb9885ff9148f124485a2fc46e917f9286c0e35edbc5756829a6da05	45	\\x000000010000010082c86cd251a335961a130d1829b8b31b9c15d23baf05fcb2006ddb1e185c9be9e26178cf98d898e6ef4aa688eaeae244b0bfd072b99e3204f864a409935e64d5109908273905a6d329361112af7c43ae144f93835d5a1bb4717a67b2d0c96dac2705efcbad020329964ef16ece79bb83f1ae0bbe448eba47c7930cb6a348cb0e	\\x100c4dbcc366aac19fe7bd69b8e0382b3f936e1c1f606b0e1f7c315db50c73166e4331e9203976dde7270d0b5fd0f62306344bee0c8b7cf233cb1a69aebed8f6	\\x000000010000000113a458dadc50fe2c293a7a0fd9ff18f5f69584e7285b7f65f4ec99f87b537e9e868d6c515d28b89476cb0f082e4bc6757cd0e117ab7a7c46d6a847418f94103e5cd610b080ba3dd51b958db5ddf15a61ac17f45aa5b61c86692b695714aae6d0446a666baed79ddf77360b1a20b94c8691a71b7e5e3ef4d2fb881eb0cf3660a4	\\x0000000100010000
21	2	8	\\x63eabbc0b6749a82e88687a08e6bbfa16f0e8ff6af8b330392b791bd32ed0b84d09ed31fd6d78f2799b44b3f47504e37f4a0d91be8ffa1b28d9a09faef815301	45	\\x0000000100000100ae0ab1d3bc790e2037908782bd2d411e0d3cd63c135ef2afdc1bfabeb57d215a4fc0853cb52774174f5e78e7fdced613c3bda5bf385a1cd5bd7d45e6c349271a9d3964bd920d385af71d2f7f86fc2f8fb8df0d5d775b8e47b2e6d54ce50a1ebb2cee3d0ea3a1301a1e16a2ddae4b354f303866d78616c9727750f2001488f872	\\x1b9f290871c913e317a45e1fbf8da5ce14c4dc8e11d1584fd46b616bc26f1d6576ae49cd7d502e06ed773ab2828306fae45f49d67ae252b76e8c93d287c42f12	\\x0000000100000001a6519a0cb251fff66547f0a0e280c126bbb435333af8bc760ffc30e71f279281c0d806e603a1d58c5189204d5219196f529671b4c09fff6517a6fb631f0d1c88924a886d815433564415713c3117d209bc38960673f88244d2bae328d82a705307d5527a0b407dfbc560df5073e408abd2594f9722ace558bc04b5e0c49513a7	\\x0000000100010000
22	2	9	\\x08a5d1ec8083104323c3cfb7dfb3b7c611ac16ddd333f7b01552c4c5a2a2ef22944b5249d47e16b48a5546cba1f5f6cad00dbb3895de81f31a037f2843de8902	45	\\x00000001000001005be1965086d521660c6819d10ec454a57300a41e68df7b4283f4d98d87bbbe9704a65a31b7874d8145d5dd56d0a338ac902301c29830a111cfe4e531b2b74c99f55513b5a46c4bd4c4f62fe04644fe6ce7fe42450a5b3f7177e67244d26051bb41cf3c5caed8c845969cc1ed42639572fd534ebc5ef777ce68a372e7f05f5483	\\xcc1435ae8e07ecc596ee2445cb353365516cf0aaa2c3f459890bcd01073b49f9f02cc72dd7030ecf2e340dd42172ca86754f0c13fb1c934ec7859b3ebc1f7fcc	\\x0000000100000001020c6ad7517d61e4ca550740ae2cfaa58e6128ef8e7e397a9507c2819ac47cb9482e53ee03148276405de40e1cf768d101ac3af2a8d26eedf82956aca7a31f9c539932ea01198708cab00db18c0c537afc7f3dd74cdd39bd0a8740a283a87c1ba0a1c8bf78af2884cff3073aee1035ad47b1e8f18b1b210d745ce4728625e61e	\\x0000000100010000
23	2	10	\\x352f0f58cd0572ff7cb0cef5db59dd126a18484b2aea495ebf5ebc7565ac8f0c7d1ba26abc761964b492d1935e66fc08e40aae3a891c68db9ff21276ab61ad03	45	\\x00000001000001006c21ae6f8333ff7a23392b7f0bddede9fad4b3873a9b3fd74886612e0d4c893202657ed032d45da635d7722661b0e94ae67ed0947afe3071d39f16654a7e95252a4410ad5040adadde66363b7d764eea6555bc1ce11823285ebf7b04127ed1abeab4872c8e909cfd83ee3af26e34037daf07eac3a346e1b33168bd8fed1c1fe4	\\xad3008f24852394fae5a37f4845dac8586f2a3cebb56a439a2931ae94729cf31d29d53d35bca624fa321de0865948656c0ef652f13925ceb03741a724fd919e1	\\x0000000100000001640e099f0563c074df76d374b24cc406ad8ed622711d661a17e3ae50343e01a1ce38d1c5b36e2fb6545d9bc2d483e8796a8d6c085e133766c4843612b071d900a6d63e0359740e94726d84d64c5350098d9305604d9508286442cb189a21ec0c4a7b0f6e4d76854371400fbffb47b3bd7d6ff69a6ca64f1989312803cdf56d05	\\x0000000100010000
24	2	11	\\x55f518ad97a676725d224c44422b87fa406128e3ec5d056a123030b08053365eb9eb5e6bf03c1db259ae6617a4c4f1ffecb2eeb44c27d1914dfc2e412e9bf001	45	\\x00000001000001006eaadc28c204ac2765862e9efef409de562539badce7c8338690f544c83ba3a2053b05ab50de11781e9fad59f0647f922be0f932b4cf1fb78c3326b84cca6db13e57232cfe757a6b7d29f34eaaf36fbb8ed23bae81057c16c027c2c16907f0dc8d76fed75d5affdd61fcd1550aac89baa7259fecb86de447b2e9d6b8d95bedc9	\\x1549d79442608f26f9af620710dedef635c4aa451b0f6c5aa12022e8de5b8f4574622b063f24e2a161320644e17923d3977a822abf52b291b0d62506e0f414f4	\\x00000001000000012c5e22be0c6393fe9bc8d2dbac62d25d6c8361365cd17ed3128d6d70ad9f97f8f7c16f4d2beb7874610f5994fe013e307c33a98068f2b493abb1fdd142ed61dda6d677b221e2af18bbde08ccc3f8b68c8c605a36b3d0c8892bc77ed69a9266c0e3348d96e05a48c44656e3c10cc4497dfc39d92d224e7fda4861ac74be0fff57	\\x0000000100010000
25	2	12	\\x59cd66d846035e058e491c7d3b4019a019c65eb8ca56e6fc969bccc2f8788cc6c05399c8898f5f19c908618c2cfa724fa9199ced9a57f8e3f77caa6d710ab406	45	\\x0000000100000100a1cb53d0cc655236d60dd7e6eaabc9537d5960ca4d963fe23c8c7a58679eec931735e47481bd0882b118b76bb2d1d87225b7d9a8c8cba0dcc35e95f530cea7f7b4784df5e6cc400d4577e3051ccdcf39b01fb2eb5517deff10715b727f99187ed4d531ffaa03bbd600d2433c0da90c733bba4628cc1e57dd40d5331d89ece821	\\x361f460544c3096bf894bcada79dfea02a4bd952cdf3d37b51e41d3925dbde4a80a14fc1140f963956364c696ed432bc8324311cd13d6421b4f97af734dd55eb	\\x00000001000000016caa32d5311480b6ea0f26ed959ade0a1dfea56c6874ff772d3e20f46d30b5fb7db42f5d9229caf387e19cf08213903c990faa5323f1c675f704011e1694ea2735f635da963940769befaa5d6155dae82585e4c73efc78a954a2c29f884f5111639337e58aa04ab74ae095d780c75bc61c95e4d5dec022a24642ecc3c1606e6a	\\x0000000100010000
26	2	13	\\x44a0c39358a27c00654c618172b6e646cad8fa0c7140fe5607983c8a93c20aaf134b14ac07d32796c0d27576062e1646e06520ecad3e4b60cc6ad70d81b1bd00	45	\\x00000001000001002d06f87a3cf6722fe5228a26392e1c49672353c94fb8e925c1c2f48c171dbd2b0ccaba142c439438e7c8b171d50f67c2941bafc38c9e81dea5b18f6819328ca1bad1dc90abe22b3cae651a8033ccef38a27f63c60bd2ff2c733114010670a03cf886a37d4bf817b039ae0725eeb1c1c64063a207d0dd810de6eccbf8fb8eb687	\\xcd9c78fa4e80f6cad58fb039b9cf1b6ed40691855f7604ef6f2fb8c939eebb05fae1a011fb4664d31581914b70fd854072b2a97dd269036ee7e958c7852dd800	\\x0000000100000001a29829bb4dfd864d544e04403dd21d0ae83f8b70d0b4f8c511a6623d7f82eb202db5a4a90207354ba698fcba1412363f3742d8908e53eb16315dd58262e91ffc44acdaf93bbc6655968e8e2a69104473ca685f1de2c8cf379660add057c9d385576c3451c113a6e69a4e43d4f918eb469b4b2d7238a6837300daba5af6b176a5	\\x0000000100010000
27	2	14	\\xd0dfc5298996cd46e4dd0e84a14a14df52cc0694b9f8d85fee30a162fa4586a2636a615dd653e85094ad2b88a58de13a6b5ebcef4613fe31a25e5196e9459b04	45	\\x00000001000001009645af2d6f5ca81b5af990f8b97680642bc09f6033195f55a7e67b1d1c49fe7b37be746db1000d44ef8f8c1ee8e8fc04839b22f1f06127905c26de616391867ecba6c0ed10d64e9e5f756f8fe550ad476d0a629d9ad5a40fef6642c1e2ac6a3812adae352bb078d2b498daa4ad306877b540c01be03377df089caedb20ff126c	\\x0bc841af5455bbf864884c32b43156c28b9dfa1637f2216b8db345b10df06d7cf34f7bba7b94f0b490d0c1e5e6d5cf5a1497d3239abbc9a7810b6f65f6d956c2	\\x000000010000000178f5e020dc1a9225f356d048c9a1df4bab9c985fba1d1559386da42a598c3597bd2aa039fdaa23f14f7ac0ae1716acf5b54cc85b7be912c197a06ca96e954414753ad27ca4ccfa32e4663244ecb2304d900e71a6e4071a3cf929408287ff90eaa8fa6f093f2275fe92c60e8e02e09cf7b2cbf5630090cedaf3259fabb154d88c	\\x0000000100010000
28	2	15	\\xb80e02dd0693a1674e89d02a8b8e0baadcb780e0d3619c83cba2f2230f819153de750774eac49f6d9ed40a71be013bfd8214331e85cdf4cad16573c7b730490e	45	\\x00000001000001005badba38acdd79555c75f6355fca8a9b336ccd340ff643d87215271d900e5a4f9b8600b92cac80e4ade0f91b11b503d0fa5f949b22bfc2c983e50338f41ce68ac1556da0a63bd086f7e1d397d5b32e07b03ee9efaf9b1ef739a18285c280db726084455d5c5ebd5cc6883b370ce78999b5685d5f5074c7b3fadd93f7e632a012	\\x4cc7b140b7229ae8aa27fb9cb332d091c47de5431c08f3f7b7532bc85bca56990cfe57387238f498f71cf9642c020004a577f4c75171aca2ffe8377e4287f293	\\x000000010000000112d40b9f5cddaecb8757c7684f045bc96cbf0b1e65493412152337a3c7033f8e06d63d5aef44f2e962f5f8a44f1485989c7e0dee13912c190f9a20087f976c7a9ccc559a08f887e65c4bc6ae37b4d83221aff92df1830cc2c79d6d18a5301cf4a15502cb19b9331b650347b6691da226886a98662f650cfd5865b6881e8a4cc7	\\x0000000100010000
29	2	16	\\xe8f5d806cb27c80a77eb1218f6708e39c31778dbd78878983cc374e8fa221bdd29667cbe9878cb964c24255db65deb19be33597c72c7a259b2e61ea43af0710b	45	\\x00000001000001008d6f83dbc677a1798e84fa5f21da12432208612e43e4e7a976dd066aae8b9e0fba7c1c09577baa23ed3c115630d8c55b1d3aeb9a56e8394c5826b387efa97310d16ff3b1b2bb9e57a88d6216874ab2ea324d3ce4e8da32c546d4445ba5b3cc018dbdca44c32cf0b8f05ad7205ff57683d0ca8734416761bbcfdf2df009f8017d	\\x0731c4c73acb0bfcf2d18c31b5ed84d1b8af22f0500bec26c806f6e72ba42cbc6b4e8838f382e5a4efdaf1f0fb46605bc27969622e5e2d4e0b6da5033918d982	\\x00000001000000013edbbb10c70ed13b6614805d2c06f233f27ffbd946961a2e2dde74815d640ef98d13f43ce77a406983eb0cd197dfd36cb1a1202005401923af00fd83a99f92e48dbf99d8390425c29b5b438cfd182a2d54a6dfc76cc8f5eb88ea685f5209631f4066a8809513979c9faa6da167aa4e929eb5d02046f9d19dcaad667d0197faf6	\\x0000000100010000
30	2	17	\\x4238ff2cf766386e469d993ffea715b29c452b2431b75c416dfb47fbe17504730ff68df640d4c5a9527bbb69b2d13c8b942242696fa5d8a47acb480dc14ac503	45	\\x00000001000001006cf409eff672541bde95d486f619601a2a080d5121d6127b4674b89a28802fdee44e297deabdf90bc45f0d47767a9390a5ea53126b0db6fe433104c726a04acd0001308cd6a9234b120c8c845b75f967a3965909fc8a226327aa81716ce693391b4d08651585e0f1cca1846f330d16bf449a1c1b3c0a858e13c97ca2fb47eadf	\\x39689000a5d2b930c2b7461f3a062840404d094f5a8da6ab193175864a54d52911179f1095a63167c8da6b878f9e23d1276db9f63cac8ab6a2a0a43ab3f4e3df	\\x00000001000000011ee32f379c33fcfea525f54504c8abe7c5cef19676b5dccac292e6be04e20f3c62cebb9f9cbe1e6cf25bb437c45a2458fac37c1a86615ba14c9446d1efd160945a8181ef5d13ab042ab1cda89b90c3ff37a49db446bc3ba80af5e7a14c9c24b20cf07365b8f3cc5e3c47af2edc51be829e386fb3a4bb1b79078d4857411c48f1	\\x0000000100010000
31	2	18	\\xa718e0b43140acdcf74ed8157fa439b6ca89b1d9eb9c52d7aab42b6f6ddfa9be176511831da14fded614514ec8deaea709de07aadbc9c152680c9db654103e04	45	\\x00000001000001001ecfc4728d34a004a2c1948324a2d68c1e9e851204669b1d179d172dce75062dcc7765c0a01f910ca6be774ed2d066aeab22adb70d1393d836b22c6a05838cc2ab9aa1f6e4d4ebad61413ac1664784ed1f133ac9db4cf8441e41b01c1ace5bdbe2853c7fbfc4341acaa366779de0eafc7bb8911415d6f8fc827dbb84f014912d	\\xb29a68ecd9069936ca55afb2f7f19a9ba4e8836369be33adba6d975fa15996916f5573458a037d9ac82b7c76bddb589275dbe6c609a9db1536d4080341f9453c	\\x000000010000000151c58fec1f4aa1a935781b404586efaf36e1f2b9ed4b91539c36a8830bcbf604beff4f07a32414ad15abf0c5d14ca741ca2bac11674927115f8cf1ebfe2d82fbbf538c504824bdc0a8cccc14467464cbee9b2df5127dae01db07380e19e1defc90cca5d15b4bc55c1acc0050b36ab50018f2138e0d5954b48948503769ae51ab	\\x0000000100010000
32	2	19	\\x7885eed2658da81b764d4f60df8007398116e37064fb0a3430fa08a30fe728801230b074608a7136969cf54fe3b499d7309e71c4c01fd1c25a3ce9ea47d1e505	45	\\x0000000100000100440400e09246a139da189ffd2138a46395c5499b0b50e7dd72b97915d774102f79ee16c0dd57672f850a2ded31bc63fd2e306bfaf4608fe48ce747919a47794c64ea87f76a5547a5e389a4a85559f623abe0db84a306d4a5c542d7b439ba04de63837dcba7a54167b1204f8252e20d66c052ba81895e63fd0ab32af2c3be184f	\\xa3166df52b07b62bd5ed940036f839dac83615b05e08ca10896c6730f0576f6592d683b9cfda8f59b27aa5ca8ff30eaadd9cfba1f9a33a7c336e0116d84f9cf5	\\x00000001000000013ac4a4e4965de5e3453e0c44c9240ca664326757cea769e4cb900e46ae681589e998f4e9d42cdd6abc5289f34af0925c959cf0d8241ddd4484b0348c4280ccf9b7d054199d0d242f6cf3fbe65f12fd92c40a1154766c30e22a1acf3f4a13374f38cdf8c36eeeeae1b1f655e888349eb524965da5742d97532749be325c267e93	\\x0000000100010000
33	2	20	\\x77a9feceecb3d8e336ee2bc49a78f1308acdba59f7e62d79e36ae090d66ae062b207fa610dec610cca61a6486eda4c4038fdde7b521ed39a4d236646fe323a01	45	\\x00000001000001000caef92b24ed1eabc9a420d0409510d8dff75d607697be8df8d0c6700d560833592eb8593fea4630dd29e677e604ae057f2e22373513a11fef9c68bcf4169ceb3667bcbde722fc1d9a315ffa3ad1dacf0d8f70a86a6fd3afa8f8c05d00eef81b93f2abaf61b943fc00b1f89c88de16a4257556dae39081a370fb564d8cff4df0	\\x8eae2b9bf787bc11b90ca010eb936a3232a69d81d981296d1b9698f5c6276c454115068885dbf44d1bf370bf7638532abd4939223920245c70f70fa215c81bf1	\\x00000001000000012ad7f52849acd1c94e712b3124686349860b4b532df11daae9ab971f49548252ea2ca88e726d0ad73d69d89687eacb8684e8afbfaf4db1ad4264a8c980476d511b2e38c3d9c476cea3ba6a35207f11181ea6ba54029cedc89dd69b046fcaaae8b395651882df848ecbeeec5edca8acb97de0a4a46299a7ebacd5cc58035682f6	\\x0000000100010000
34	2	21	\\xaa62a37f4365a6fc7ef2eec54ea1c8edceedff47f047796a869cc7a6d1d1d57670cb752fd4a93d61c205a7267ba8c8ed7cbd90efaa7fd52189236617d4394e02	45	\\x0000000100000100a55d2a90b273198a2af659452336d098abdae200e5f1bc8c2600bffbc8d8c4c96e2bbf81fc557f24095f54328fceb9ced8f0a0ea8d9c770e6bf23e290c4c0f3a2bc76be253bb5467e9f4fbad48b9ac73f00432fe8c52e153a605cd6ccaf423d8907b1ab91f377ec405caf2bc128997770dc2a8f03cf5e7e1498be458f08fe2ee	\\xc17e708c9ce93846e88e8efe86c1839b0517e67a70273748ff6e913ed79ef8c852b8428190a82dc0e99a57db9ea4dab48fa5ea84281af1c403d5bad1625c2085	\\x000000010000000115cbde6a519b2a6afc5eb09605ced90ab669d209dd70d510d33a7a15fedca567bb8fe520b48fb6eea5940f539393cc0fa0ecc9152dbc3c42c47edeb5bc76a03f79b438e42f4dd7e8e6c0bca0fafba75daf5026b7692418cb1125c07c45fbb91fa052045a1808d4c4d10decc7eefdcf1195cf72501398b4762e0eaff8db55d90b	\\x0000000100010000
35	2	22	\\x7e6d59b91332cf6c88bb3d001e96142a266a7a9e4e9fea4dd92250bdd17b622f94428749c020f895b002ed32afd896887a0531af5e70093ebef3880bceb3ce0d	45	\\x000000010000010042d870f144bf89149910a1d91593d4b3366dd1dd6217c8d6408be88324319dc3f6accb10ec633e4701e561e523c754df7607af6770edae2b3052276f89768328617796388b5ba1426f3bad31356d6ad75a4250aa1b941584d13158d743690d81d68d971be3e75d849126e74232254c765de51a6dfaf7e547b46004a5d46b0c0e	\\x9feef048c7aeefa0a1e8ea6a6e3f0f63f2600f8bba6d28ecf102b9ef1696f68ae27595fc42d48ce9be60e4d76b5c9f6816577a4877fc2700b0d39d82222c7bab	\\x00000001000000010f433f34b0483a9d7da0c1a82c8ac4aa66442e1d4c22d4ac7b69fc26675238fb7307f404e6a5e52f56075e7904ebfb5308ab8d8b1db4d2ef2eeddd0be09a45a631ce21615292ade0ecda130a050e509fb3856b62758b7507a89b5763c066f8ad9ebac1a888cadbbb8e2d2f4ed5e56ee326d7c79323878c063698e28ff3040f1a	\\x0000000100010000
36	2	23	\\x6dfdf1633fe37fc7a72356646bd58f9e89283cd2d17238e1c93c09281b1ebba47ec73dcbbeed2b9a0b9ebf2c7cd445520661ce3d5c25f5d272dab6f7853f6c08	45	\\x00000001000001009b6f802cfe81a06568c503aa20cda1490ccf8fc0694688690afef52ec8f43f6b49db89c572abd76e04c97d3b621f30d6ae3c1da18fdb1db1b4e597503c7d7ea21a28fa19c57e14da86ee6eb54fd7d1ea454eb82eae5acc87bed9ebf120093f5952c61df511bbf0279994aee96f163836a9366970f55b6bd54cc0f7adce9c2b66	\\x83d3940167551a83f57e5aa4623aa859ef65e671be6bb336729f5ab7535a50f21ba17e9a877dc4e7157e6c15118bcc9ae73fe61529e716ee2a700bc1728f5f44	\\x000000010000000186336cf878ebab867d19e44a381b11610fe67dba5251827af65e2b55b0de426fe772cbe29ed07f42c4b8dbc76277b2c5c05e218e2d9481e86bb1914ac98484502aade041b21181d37d1c5d8a7c056a44ac6e36ac731240b5bbfe8c5df8b494f9181748149a9ebe880533d3025e871c95ffd038252b0eaab8491cf1d9bc376c88	\\x0000000100010000
37	2	24	\\x142ce389d3295149d6800992d853a89ef445aed7871e3f27ed510e4599ad0ab4e3b16d8ca7d56048357e2095903ab8ba3c384fe4950a7d371f042b7d23da9601	45	\\x0000000100000100146a9db7c790609d08949a8e7cecd4f6e19c11aaa2c19c9331cf55112a80000947967de694229aa50c63a5ea0a5e06867dfd722afa163545bf88b71f2d74291a27c35f0279339f20f800862676eb1fe887315cf4d36f49a016776befc767599c32a72020dde2fe6bdc0a3a949348e42aaf029ef2fd49e8d70bf3912cade90c70	\\x990b5a96e838eabd34a9cc3a5e53936be4deae45b7f436720d2fd2dd90c15a3e93dd692294ea94d35e8a15b68da220c3d1c821c99b46d0bc8b3f033d82017213	\\x000000010000000189661ffa0810fb969adc4160be351e270b68996995654d4b07f1da452bc05640e2dc92e663bbc136caf383dedc272ba3600343467fba41eb8cf150b58af0c085f2914aab2297ae0769992530a3f93e76480764573a4db9174d61cd06c9f9cd10778c31694dbd595c93f142b06547fe5e5f509acd84e6b290f9d3b3c44b5d64da	\\x0000000100010000
38	2	25	\\xa29f68665b53f0538be8b79b49723bec393848612c1951c9c41d2d2d4ac75abb62079f88b24eb384c314adaa55e8c862e43f309b0e81613b32b706f3c745c801	45	\\x00000001000001007f045f64fdd4179117e28028ecc277d841928b4f0502590ef0c230f769584d61f58da262e692f9dec2c766fe4362df94b5fb28301a72e391be4ae1cc116f648bcf9d1aa8daca2b54ff35b93b673425fec2c0f6b0c38c0bca2a56a7b25892001990766ce1b551afd7d21e95e805cc2b9d23dbb87b43b3985e094baeecc03bbb36	\\x702b94f2a683ab2e8c53f02946f20eca8d856bc3b8154e6f83b23586b82f70deef1bab907ddb8404cdb4ecfac75de44896f08201f5675227e5bc64f94f1c336f	\\x00000001000000012459454d30404633ce3ef8f40e1627575e6eb22bee9d0330af9e156d3517fafa84c6d7e3c2d1aee45402249285c6416eeaaea76b4c9998c84e29aadbc3953f6d551e4466544691df635c90571c988c825f00f4d89f603d55d1d09637a9d83dedbf3ed85597a81f8badc3fea637d12040de875b18faccedb0945476000fa34cc4	\\x0000000100010000
39	2	26	\\x3b81f74ba2bc67c54425c799fc8a947e242469eb5b2199ef120464b56dd41e522c276ccb7249ea167f7895b0eb439682dab1a08a1f809b0c7e27b20a5e8d0f0a	45	\\x00000001000001008d7bcdb512946056c68afbfce199b3c412bb91afad9f397ad6913126412005b456c5126d6fd15726befd4c962d5063d259c63b612bbf6f92aed4a9cb3d4f8f3a9fbe3642132ba5c949f1ca54bfe1c37554414b0ec2146fdb7260f7391648647d61b5af8aacd75c0d6bdf6b7b4dbfd4b6b78a870274ab945219a64bfd8f6ef395	\\x39f2eb3b63ba4700706f7f6674056d1705abcd2a384345ef3fc3ae110b67f7e6897bd5e32724685c0f128106649992217f36ccdc2648d75e9f0c4b966b738116	\\x0000000100000001a8305e9332c866c397120185acde5c438d27bfebade9111a6bd1c11236fc720146f0a354250fb33d9c3ccf39e363808149f15706291039dc1eb445b16e59b2d14d2dd4398969025a062fbeec0d0bc8d62189ba45cf9786d54009d00a6df8ad08562eabbab53cabd0526e8a1584679756c22e88ec10bbba5e7aa7b2f15cb94bdc	\\x0000000100010000
40	2	27	\\x0927f3451b3d1cc4406c4b04423943befd40acaa64151215f7e93024bce80d32943f09ae8fa1b9b8f4c2b50fec44d50597bc8e39af3ef91017d3d6f0a42b2a06	45	\\x0000000100000100ad8033cbca48942d340aac7533a746dc2e7196e02287ab68dce7b267a2584d15af99ea199293d55955ec3718735d8677cfc598c29dc0ba46c493b89f0eeb65a5b744d3ec4ac294e1cbec2cc8c2361d47e85c1abfcfda101119c6c68b0084941183111ebacc693a1256acf84bad5b4c6132446cf02afea44441adef5ec4bb0b74	\\x280c69e3aa3304adf6e95788805aeb6674a0547a639fd256edd2f16fa96b0455f8d55757b4028b29c2fdc6ba5fb485cadeea4ec1aba787cad12a9aa853e9f423	\\x00000001000000014b0a503149dd74f23dee039995cbb84d81d486013642292b6ccc594f8d2dd0c6a21334db7454725355fc5a708985a89876fbe80c8574a09d1806c404763ce518127c3434d0054708c0b538826e0badde790bf7a52575e881b3030f80d05bc2471417ec505a3fd49474379447eaf4d977d7cf1be96d10553d50b129bd1e743c84	\\x0000000100010000
41	2	28	\\x495233b3fdb31866ffd7f93e7f5b39796688951937660c67975bcb8b107760d92c6a51d4ef052b595ac79142122ebbf2653df9396224d243d42fd4f3e9be7a00	45	\\x000000010000010068fe9228a9ab21027785bfcf475f9478459644f79e28279ab11cd176d33529cfd20605416bc62de7e1524227a023e25050af9fe949bd4518b1e63c9065a5424e85d6b4226ab2de58ccf3becc2855c9291ec20909b84384bea0ad1300542de69e31fc526f9c33b1b755418764a5c68442e8eede96ba0b1469335d99d23fa9ea62	\\xc3ef0ed2014c8127fe61a04a6c7c0744b3d0c7b07a1559a904c3bdd2678f56c73f085819784bf883082581ea9218a91d54ce50a71f9b82d17094bcde56fb12ce	\\x00000001000000017d59abf825b835e30c27159710dffd185cc2e5258940706d235c79509f9c7b5cc2e0aacb1853dba72e264c50eed4377e748457e687d03ba9614e4d698f034e2498e89428063292116ee428aad0ad79a661ecc6be1fd7eb9e2fd89133dbd7a0c9001b109d19e425517498856ddb393e0eb564b03eab9998a9ac5cd3693f8dec60	\\x0000000100010000
42	2	29	\\xc30b5173d3632a18a4b278668c55e1f9e571b3bf78c9cdb6f1625357e0098f1c505890c018f33a5a546178eec36497698b4befbe35152d4f7fa24c0ad7b78703	45	\\x00000001000001000f7d8a3298263a604a26926da35be1df6cd4f8f05181bf94915e1a5e444d73a50e4ebf6191e63e95e75fe31a7bc9bebe70623ebe6e746302352c587b8eefe8defa4ec7ecdf793384831534d0c02c2d19b8a919a244eb9414290ade9a26fb53d08ee6453a1a2de2cbf45b541023cb15b4dc51fa76782bf21b95d36bb8f61df6db	\\x1337658a524b7a6c68ac4a8d43200e410f67f25055ff318fe9b575b42a2c3b8bf5ff67dfe48b8e2b3a685631d2776469b62e91fe1a75ec93f92302eb2f00c480	\\x0000000100000001b0ce2b3dcdefc089d27989e9a496a4cabe733ac7ece06487558aab69a8ce7c8e02e5925040a379a7cb8ebaafda2e6e2716411d709bdcda2429de2f1eb833fbd0a29827aab85d739fd6e7e98f7a8c3f8ce3b34a5fa630049ad59cbe3629bb3e349c5aa4d483285f21145415631e56c245766e61ff73e1c029e5c74cbd158ec998	\\x0000000100010000
43	2	30	\\xe09a5bbc256792e71f0df7ed3539bbf9951046b0da653c71e7a50d0451699f4b6ae1cb61c1c58161a7bdc54dba1deee9daad5f91f3faab44bce3b697f550af01	45	\\x0000000100000100242b18bbb596147833f84280556626ad6c12704e909e639ff3c8a025859c70b91cfe619967d14c22ec29accd7a2f17cdece1e927fc79123b870672482fb949006404ebe1de71ddc2607cc1036217ac981468455867557fbc7cbf42af17dc055c68e21dfe8104c10d7a320a85809da9a773b85daefd74b04707a7bd2803d4cdac	\\x5860bb20429677d785d83251d74c8862025c92d1f533f8b28348502cb92693e40ed24d1639d424be6a8f09c488b54bf026c81e4157de6ce7a31962f2ca6ea2b0	\\x00000001000000010858f33997a7e6cd5bc480e63cb222af90f5c4b332e927045ac494ae33853d133ac6cb73343377696c1e7d5b9c390b8576fdeffa28231bf3f92660cf268a2ea765d80111b491bb5392f51f0100b08d35242d8e5f6756298184290ec3b168cc21b14ca851631d8cec7c7b787817c8282eb9abdea3d98f1d48137a087fa444d735	\\x0000000100010000
44	2	31	\\xb832adf2f4312b08490a87ecce1020cd892fc1a65e027c15236e041b5c431208a751b0ba7767f99ffc528ede45598b636930df0f6f5fb5e50d07e11e7cff5605	45	\\x00000001000001007dc7a9a6e279a7847e31b8868c3eae266de345fee0856053237f39000dd8f8e6b4c52fb5d208bf53c5370cf9cc7637a59bb4685eb53516b292cd71c97efa2f502bbba921c9aeba2d7f202c2144769f5085ab75797b664f818f25b0c3e44924ea9f27ce992d7a1fff5ec2f9207ef3c1d4b662c9492a2a008050edd17fd6178e41	\\x75a596762b8c97a677dd3f14c833f5dae66480a564b74f0800d4da178a996261735751cb9c4fcf729fc695bd67a24daf768924743037e08bb8a85276e77d365f	\\x000000010000000118849d995ba44eca1b72b1b05a4342b64d31eb6c356e7758e38ada20faaa8cb94be395d4d4bb2b8f35d03fbee1da9fa75f2a16804d30f1e5e2366b1bb225792502dd1eba08b4d5bb292b344f43cbfb1cf6e192502f479c89a1fd7cb2cd2e7c65d9d8f45199758c1634dc62b5ec23e1829b310895fb9e85e720d9e54de365ce8f	\\x0000000100010000
45	2	32	\\xbff032aecc42740a2b2c26ae263e934b03522ae841f0d3a4278d16cff1cbef6a8a8424ff0886b59d796a2fe1beb24ed25bfe8a8333ea1bb1345db093038cf106	45	\\x00000001000001000cb4316fedcea979e9b0504b7ccf610fa17efda7a76da97d4b96a57e3e577c415d128b10f06e5f4562ffd94543b74caf85890dd2e285172ae7a71aa5e9580ff87332760a898049c6a08881d58bb98d2645944f43a17d5333c2a237052d7f0984fcddba1855412470d88cdef61a68fe77ca4c5455a417d671db2c4024a656cae0	\\x9ddea67c6c7a6f650cf0dffe1dfb2264ddf744a7529b7e495eddc7f35ac3dff20be019083c5eee223a5c98610eb664a40d7ef35afaccb5574788b86ce739b49d	\\x0000000100000001492d5a3920eb6918fea79872dd80f2143832586746b9adfc60e00c90fe0b6876f2734f9831fd55b1a931c237495ad25cdefc24b27bfe682cc711ac8f235b0da469fc2b4de3cfa3c11cea522136ae2c04dd842f58a614e4baae6f263eb14c686a3890a9c39966abfc4ae68afa7ea9e8b4bbfb3968345e19be9d349a255aa273cb	\\x0000000100010000
46	2	33	\\xc3b7a3bd4328d20c01247a85304e6ed3857122507295ace9cb13f2b10ffa9936282d8394f9f6b723228f60d2c2fa0a8954f91e975ed9ded0be6e0c6b6c381b0b	45	\\x00000001000001003ff394399ae5bfae52bd75fe215794fd3f8e049df584f39f3a60e67962e91ebc491e7eba7c08b9bd0a595a5afed74606f192d7de892c50c18858a4ccb22b94bbaca00c72e95d36e49c87b3e680e589f0f53d0b3e94fc22d314818e05628053fd3e7e50a93d67d36d428c6d4db4e20bae0b438e70e31350cd593cb118129541c9	\\x1bf9e3c0a5a6f59d41b614014853a6893ed651fb1284bfc4129f271f6edf9766a65ef3f67f7a8620c6d482f7c1d7c3f32a426a64e133031133d37f93897d5aab	\\x000000010000000106e306f16cd2a26329701a4e796365de0704a6d5ea41276f47578a885a0d50de5a302242735767730fafded67ff5c435c9f4fc6de01f30323c9b4c128ed3517c3b3c049e579671ccff72ec6ac32168eb8dc7c3602e429535df3e8520983e11a00633c3328ce2553266bc1459e7cfa1ab93758f2ebe4ddeb3f302144285e2a3f5	\\x0000000100010000
47	2	34	\\xc30e3b2b5be220c9a8de69a7026ebbd29eb5aff639ec584e089dda62a62c292e6eedaeb6dd48a9c5ef19d029a6c53ccffc41e2e4ee1d45a42acd7b88a4969008	45	\\x00000001000001006af5c8c085435783c4f1615f5cbe7d5aaee3daa9343d8cd2e0b1f4311eec40132dff99a3a823247a76b14c2c2158b1346b0b0af0b4fc5a52f3d7e666db22e89aeff1b3a1de427d438cefa4ba1ddc172222966b68403b62affeba455580948652b4e0681398ee144e791a5f8a8e38684f15018627b1e81a8f59c8bc3340707859	\\x9fb8a3bb3a712f8fbe4167661320f3ee0086d123189d0a388da850c1e247732d3fad4a757b7651f888e64c239f86cb55e7b95734ab431c9a97801866b8b4d8a6	\\x000000010000000196857aec378d071e6f46b7be43eb22415cfa790141077b8e37f3a1243a0603e83c1bdd59236efc8711544236a7154fdff947d67facbe01307ae446484b1da9172a67235d2382f7a4e7543bfe223f37315d1eb86b7e2e89aeed971813ce9b2e78f8b558eeda5dc3d5cc98067c179258f165f3779b489caa750fdd9673aa7e0479	\\x0000000100010000
48	2	35	\\x2af308b9ea7971c44869961bb3408573a4039d5eaba9857a2dfc9ca17e2de00898de2afcf16a3fe085d74f33adb1be4af651d83d4e99ec9fa6fb5e7d56bc240c	45	\\x00000001000001006ccf2f0be268ccd1f408292cbc0bb6fc8b60690f158e899f1c9a8a686432613c52978d36567876ff2d0239889fcdad327ca6c13ec80cdb657b69c92be6e69a940e98167302fbd1c5828bb4a2e3563719684da0fed5e1a00f7c1311bd7fd4a5a5bb0ba3b2606cf3c5f5db0f0db09203132d1658f5bf765a25cb2ed48506d92692	\\xc65f74c76e93d7e48bdc06b028664ecb2e1e629d5bc149d3017e305ead8eac69b977b122b88896820f09060cf9df6b155e210f76a24077a762d8390febbc1b7d	\\x000000010000000164d82b7c1316c91aa9d3019b10d419b9b7f1e94b92f1873885e92a61186e08450aed85d6783507c991a4d7d1dbc5c6ebfe08a1d7dd4e8423af743c1c58d53d5d35f50bd83e1616c8d944b62ad3d6808413916e3106f6e43c12c222340cf32ac2ba9be2f26a0c6177c2e01d671705caf9bd1fe857ffaf53ce52b36a50423cbfb8	\\x0000000100010000
49	2	36	\\x0a8d628191bf20f7263a83391a29f6668a38cbfb0a2c28bbfffa478bbbaa09cfbdab2a31c0eb365dfc30f1cf326ea0607af29aaf71c0d4b13eb5043b0f73600a	45	\\x0000000100000100af51a0eae3841f0a2e989b32d08d8e752af522d4a9c6940b29925d961beba4a57bcbaa3199c8f17e6207aa75cfa1310a7242c86742258c76842769444392caf444f60f8021dfa5503452351ce2df6da39e467c6a7497072f281b7e67fc4ab901905f2e4e8e17d319a6c570c67ffb5cfe03c526a61358c1bf36cf879d27bbe045	\\x4bb0ff8350e26ae3562cc2b7d19a85b678495a5db315148dbf9d625a59afcc848a8aaeb91f9127190d3b3d6fbe4ee2497bca2bbdc68a5d74b33a079e25e047f6	\\x00000001000000013b124ba7a5f745b8f73650cd1d413651f2fd594c63006344dc78b94b75ae0cdea5cac5aba095bbce82347836edf01e0d615a943e4f21962bbd0eaf8c449d2b17b47577cbb090d49572484d4219db635cfc270b04748a5930b2bcd30fff0d652077296c313209abacb1cea01283bf0c1c35e65a1088fa99564bc3cecd3c4a1218	\\x0000000100010000
50	2	37	\\x193a0059db5d503e7c992bb108709ed6f56bf26fd35f1f46c5b84223d8fff8ad7d7e15e32fa1f52f00f2db935cdd03814323386e2c3912cbc037adbdc3414207	45	\\x00000001000001006a1a1b4236550510972d0a06a622e8c53d20f851ba8776512b9f82683b46440b7c8f5b1c9ca66a131768eb6a94c3fe722635f68c6253bbd46d5a19330494a3afd6ad37025a6bc218f26b24dc578d2bddb9588495348243f448d91021625c1be3a16c6cdd63b693a581d2648adb735fa0fb12c53845833f96f2054dfc7a51ebcb	\\xafad54c29590f9da2cbe107fed3d65b96b6f8a2abaf64f47113dec7c9bc764009ecaf0dfc137ac9ab50f517419494ba8e6417dca72f9884df743023fae244a9d	\\x00000001000000015cd048ceeee499b60a0a35fd7b92513bf0efb88705b6d9cf1dd07f69f66679c370a77d514443ca8933c87b394398376d04b961a5e3698b2abc2d29b5ed2550db734b4e245164089b661ec1b02e1e20181859d8d57f1c918e230ad1c2b7253b452dd4220a213493abcc282efb25651c5bbdfc4a1518927aec10c544953bae85d9	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xb9f2e034e233759b62bde2da65a960337dc02e5826f8ca1e38cebccedc6dce31	\\x15582ff020274fbf164019ad16cbcdf591958d1855badd91031d5b0d5c5280c78bed93ce7df07fe08ba091d201db647f64b8b9fec95f3c9662c06e0af6d974dd
2	2	\\x44320b9656003f7e5e197310c0ecb6744803cf845d10b66295479ee8c6772320	\\xcf504136a51077a0668fc191301c9a1d763b83f1e72346b31a84b203b618782b3d5dca4647f275b4205778369068860a948932a0c51a7dd564d631cbe0c91911
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
1	\\x8a6d363abd0e3a1fb76865cd46853526eb283f46df6c2cd07483278c8c95fe92	0	0	1650113814000000	1868446615000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x8a6d363abd0e3a1fb76865cd46853526eb283f46df6c2cd07483278c8c95fe92	2	8	0	\\x4f07557117ccfb95350a1917352537f1e1aea759321e6d645b09b509aa087f77	exchange-account-1	1647694601000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x529d7cabd6238d9c7cb0c354146ebc49489604f97061665ac90d8d9f51a4440ac11966fd3a7c864fc792d2d4a0d81f02b2e42e06d9b6c5cfa210c5c2c9095845
1	\\x848dcb27086bfc8bee4c4f028f138d4ebca5e76a7dddcc6c376bcfea2bcdaac111a0d52908a46c5547a7b5f577a7b012b45eea0705c1caa979432099b78259e7
1	\\xef3b1b0cf79f97e6872ed178c901c9b6b6a5bbcd528a63c2a8b66b4b7a2c32bfcc5aed8c526c22866c70d69b37cc242a05f81f81f114f9520e0ebbd6c03bb256
1	\\x772dcf23441446a7e0d5c85e9ba1c08b46fe973a140d68ce52b1cb36cefd7b83044c335026edc56d9e8f8c4862e896e19a6cd079ec9e49d7bc06cdd9b53a9699
1	\\xfecdde65cb515b36a84cab3036ab1ed82cd325fd7e59e973d75d7b0f884bfa60f35558c2bb00a0d2b25a5e60cb2869f7f2dfa7c52778bd7658ea8d03ebd261e4
1	\\x6518a21734dc84212bf5f6978230f5f054b6a798166dd465a8b3c7075bf020395d4539ff6fda715112e9a7c88bc0adeb5cbfcdca3fce23e4e0ae24e5557bb88e
1	\\x61eb9568247a0e94e39d169c99408ac55d8093b3dd5c5e34c195704b14cd71f6c4cd2be7259ab6b1a1d08d9bb44040d340306db3b98ae7464b069226da6b6f19
1	\\xc002794ce969cd87e9d4f7d22b7c94fede054dfee9f66af6ba7a73b6dc4ca0413726cc030aeff4f20bb6258f9899993fe0a1bc745e323ecd36caf955bcc68709
1	\\xfc964c25a01a7f078fe406b030729ff3b90827b680a2ba42437bafa9fca18489d436c638091aff281e7b8fc2b93bf15e048c795a01ea7d6767378d152ed66e14
1	\\x3cf6740553e31a13e1349135d9c01cdaf287b6b7ca91f7d3a4063e7272db25a167035ab589263b7fac54843534bd96c5fb123e533f4f99f43f7b1e8ceb6d01e0
1	\\x943e7d2fd18181db14176a3269d73c0b3003a9a6dc2dbb73d33d4bd91dcef94e12c2cf7ed4c383f0480f9832df4e8c393ef927d1d3a7a7165f8652d3bb0f1a8d
1	\\x33d1965fd5b340d74dcf390ddfeb805eeeb41d6ef6e5fdbbdf550c180f1992f7feee032f2e58f4155059192ed5547a4c18c4d23ed679d5f5f2bf50876e6db8c5
1	\\x72546d1916238eda096a6d69445b5cd2e46c671e4441d205a651b91b33d341514e3921ace1c6c9f1440e8a2aa8d023cc81deeb4ba96bc04154d5a3ac747b4585
1	\\xaa773c7b127bf551023a3925b32b798a77a958d954d92774b2d1a4c663280e7f8ccf306dfed9771f25a58248e79e048cf95dd10607b52d833acf251d4ee70c18
1	\\x2173e4cf1fea850a39964193bcac42c66be7a283594061e5e35d3938b13b4fade951541ae47d39fdb98fb167ea43aae55533771545e47ec08c39da16e629f8a4
1	\\x95305224b511e555a13e8ada6c8718353a9936333d2784a4aa319e89a65a0e4db5153569374af2f8d04c9d4d01986c74aed984151eceeabc48239d5a5c87b2b1
1	\\xdc641cadd268c12e509f0a83b6b7c07d72b6a649002ec2f1c8c41869f0112db9f78173135801dad96fae6779d4ac49d5d72643faa66a781082fda45fdfb88a1a
1	\\x14d740ecbb4d5fab6624080054f3d7562fd504276875d657fe27da76ef36c07e9d6c0786c26108ce004564628b09e4629088890dcf5a8ba1d854cd31491a02b1
1	\\x08194fd90aa9a893aa409785585136c70bdace26248dd6afcc1f15b4dbb39ba01d028030ec950d9e5a60575ad864b66e202a71748310565e1b0e68e6531e4c6e
1	\\x53f21b0ff91ad0e4c0c99d3de5c91b4de8a3157417e603882434cc61adf05e3a298073e664f01f43409f5a83ce30df108ba6cc2a1c891bcf9d51f04c4537570d
1	\\x6c1daccf111a13de01d239e9a8e154fac5435f33198ba8893bb02fc9407ca8ccf971356cb36b54c99f3104f6e0605d85605ed5a8da7aad4cff9d2971b983d60c
1	\\x4f5bd1c85e2df0937d9da835bde84b5c81492e46d9fcd5571ad4e1c4a8851e6253314d861d1f9b1c0f06a3cb1d534300eb21bd551e0eba17a5fbb3bd3858478c
1	\\x1b9c2542a21a877b0285486328281221c500a3866c36a4e45303e4705f5b93c2f23b9dfddf3a5f1e34d2d7ca01127185edd4127ffac264d2b0b6ecaaaac316f3
1	\\x5f4baf5ed9d25ffc5d144c651a9abcb8c1fddd99fba9bb2330f28e04a52eedb38788ccae11b5e619aad608257403e62040e0a55c046e5891a1eae468898208df
1	\\x85950ad80287927547fe8eb5d8459729008de16f3f0834ce55e8d853d60113ba7c70eafe55680d8616d30ed799914497210a83c43a47804ca6843d7fc4cc07d4
1	\\xaa16caa093be3e28845ceed78d81ee973fc37e0de26f9ff3c6e7f337f8b0462231bc5ba5717f620d2e0150973d2fc671be0cc6e4752d8165a280ec717a64571c
1	\\x877522856c602c51e5b842fbe8d0efd96fe06e21addf6afa61f083b2c707edd6c3c0edfa585340b81ea1f3bfe2cc40005f089efafc705efa6fdcb3cc33a11ab4
1	\\x149d8369fd5d2cb91ef10ef1b08c3da56ee2cd4db5154d2d8aaec5ddf54c0985c446dabeeae3789aa89ba2be1a33815c6ada1e037deb786ae90071644f0e9be4
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x529d7cabd6238d9c7cb0c354146ebc49489604f97061665ac90d8d9f51a4440ac11966fd3a7c864fc792d2d4a0d81f02b2e42e06d9b6c5cfa210c5c2c9095845	21	\\x00000001000000013c1ef0cadd080d66fa91d0b8d41d4bfb14eec1dcb853f0f3525867234228b041f760299b61bcc92f37a0673adbe1c0e6dbef2ed17ab32e9ff0c5a9aeb3c57717251bf9cf97f9d14d05180585fa44635b09d11d5998ca8f6d952218fd585049293e760791395f78e64d3cc4d66fbdcbb652b6b3948c0b5d298475218a8a7ae662	1	\\x9156dc9fcc77dd7be105ad835517fa62393eb92178992fbece0885db528154314c622712771620068860390533f22853af68700575b065edf729d73ca1ba5705	1647694604000000	5	1000000
2	\\x848dcb27086bfc8bee4c4f028f138d4ebca5e76a7dddcc6c376bcfea2bcdaac111a0d52908a46c5547a7b5f577a7b012b45eea0705c1caa979432099b78259e7	251	\\x00000001000000010af0f8c7ddaa8ffc2d30a74b077728bb50e0633a026d951c8f2c6605e9156786c86abe8f049ac2c03fe3707e1c6113ec9e5fcbceae8d1a4cc90177fc641c4b2cf99ca9d091e122fc71234be0986fe2fcd4022c814f5ee15b65f7199534216b0f13ae8fb16230a295a4e3686fe08777d70871b121a1783dce6a9337c11481037e	1	\\x00efa385168dd3ec2bdff1413060669c4e9bc674f0f21c5325efe08943b03278bf44540722b4660bcbfaf0a33a4716bf2ba51f40fd06963db4a31063f19f0c08	1647694604000000	2	3000000
3	\\xef3b1b0cf79f97e6872ed178c901c9b6b6a5bbcd528a63c2a8b66b4b7a2c32bfcc5aed8c526c22866c70d69b37cc242a05f81f81f114f9520e0ebbd6c03bb256	191	\\x00000001000000019bc20306c173e9cebdf36356d6d08f3c0d3ca708965880a6958e81eb6155dc5067e81dcf6a38bb82b3d905280255aec20ef0948e9388976d2469c1b38b07c4773a2a7dce37aff5eae06ad0e85681dcd5135481933eb6c452a638153bcce90b8ffde0df73a74630ce8a67fbfc6b13278203d3a783fe2553161cbdc8d75d536488	1	\\x23292fe1d745b5defc068af23d10105d9b359386b23f89cd70a28d801a491fb939f44755ace8abc2ddae2747d27d6b394a3a1b764840f6d78a4da0bf6473bc0c	1647694604000000	0	11000000
4	\\x772dcf23441446a7e0d5c85e9ba1c08b46fe973a140d68ce52b1cb36cefd7b83044c335026edc56d9e8f8c4862e896e19a6cd079ec9e49d7bc06cdd9b53a9699	191	\\x000000010000000189ea707a27d9063accc0a502ecdc9eb84ff77235cdeed99d6d2536158da61f2f4cb86803f0ed8b152ac422ab8db5a96c768991e6e5de28fde1ad469f25d7125aa90a47dcbe7a0618fb3b3d6f39976e0d8c7a2c1a4fb0e0428e997926448389da3916c65e993eb3d44d7ddeb34cbf8f58e877ae380c79382316155c437c562f37	1	\\x3a3f0a24020a5c2e7ba6b756e0027ce1e787a3c7359e782304f9e1b5c6f02c8a643ebc9cf3e83fd8bcbeb45df17c1e853c48727081fa3dc0b81745ff89aa480c	1647694605000000	0	11000000
5	\\xfecdde65cb515b36a84cab3036ab1ed82cd325fd7e59e973d75d7b0f884bfa60f35558c2bb00a0d2b25a5e60cb2869f7f2dfa7c52778bd7658ea8d03ebd261e4	191	\\x000000010000000144fda6671325d00dee030249b69f5a71f0a18208a3c0529ae12e93ee6105f0da96b39e016a8093457ded05a552ca0e853a663ddd52131a50111a7538bc1e28c05859c23577655898c18aac9dbea762e1a5af7c405cf296eb32459ee2e5de309535533f6643115724f77249ab2152a993184f64991b0bce080a324c383130c158	1	\\x3c3e23977ed95d778922abb5fc7e160d7ea971d35e9ea91e212357cb22428e2ed0aa1d48d85f84131d5ed038e540d293a3b08b18f96afcd962e0250c4d14d306	1647694605000000	0	11000000
6	\\x6518a21734dc84212bf5f6978230f5f054b6a798166dd465a8b3c7075bf020395d4539ff6fda715112e9a7c88bc0adeb5cbfcdca3fce23e4e0ae24e5557bb88e	191	\\x00000001000000018c28be8694daaab5907baae123ffbe161d75a9f66167af7a73fea3106704624bfdd226bb1aad626025466c49ec8e582e03b30b8fcc6a40910bf5627fc0227a2c10785b47e2535992ff5ee2097057ff7c47513d3a629296509b4c20be670423af3522914e19d91da42a7064e4dd87f4234d48fc71a9f4cfbf366b324a41c76c2e	1	\\xd976e10192bd3965c42cf0b700bb14d0309bb4d6be351e807812719530c1427b76492787cd1216d929a325781cbe3f1fae6162cedd5ba7af35b60862eefaae04	1647694605000000	0	11000000
7	\\x61eb9568247a0e94e39d169c99408ac55d8093b3dd5c5e34c195704b14cd71f6c4cd2be7259ab6b1a1d08d9bb44040d340306db3b98ae7464b069226da6b6f19	191	\\x000000010000000193cd02348bf3f633b9ede061609269786787de72b000916d271f01b24887ab12c0a92f41b64962ad31b90bd75b8d2721b95848f57c16cc76e5360051b6ffcf817c8b496b718b095f7ee577772e293fa18b1f07266f247bc1d812194706c3b18a388e266ad3ab9224078eaa4b51188248b7078454f03614c5f6a04cdbc26ceac4	1	\\xdf46d3fbb958648e9351539b3631c8bbbd2e04ae75c05403eee1a096e7fa7f49b037889e13102b33b468ad9a6108a9090d963a84c1a9f515f264f5a7c1a5c406	1647694605000000	0	11000000
8	\\xc002794ce969cd87e9d4f7d22b7c94fede054dfee9f66af6ba7a73b6dc4ca0413726cc030aeff4f20bb6258f9899993fe0a1bc745e323ecd36caf955bcc68709	191	\\x000000010000000151ed23647bb60f0bff9ea38c1abee4e5e61a601a492176fd666fb38a3601218e436adbd9931ebdb9ba64082250e78ed127e1ab8fe5237b77cd34d74c93fa5185f7645dbc7482b00f97c6198937a21cdc446c03d6d331e3bbcd8753822eb3620fad44a5b6e63940e5dfcb4ff0b2166250a6593e367e61f2748af6dcf83e53a93c	1	\\x0e64045f0946ec5e980b82ab1bf1ec6f5b9d8c1508addf33812e24fdf709f29678c98c6bec2c19819838cebc59c3eee499790431bbbd3d7ba5b7fe3a7dceae0b	1647694605000000	0	11000000
9	\\xfc964c25a01a7f078fe406b030729ff3b90827b680a2ba42437bafa9fca18489d436c638091aff281e7b8fc2b93bf15e048c795a01ea7d6767378d152ed66e14	191	\\x000000010000000133e7ddfa4f8731ccf2bd4af62061c6608939d0ecb84c0c4eb7b75412a5dbb6ffa65b66d8220065f2d9777a2b911dacaac1902cf43304f09cc5cb2e0e5d6ae4305c371e9cb88b20523c2ad3d785346a2448dbb57441c25e9a9afa7c4d7369cb4dfe5fd7d31d2dfda9110d4c264d7a33eaf6afc68f2e6684a19364f94bb03282ff	1	\\xca53cb007e622378ce8a04a34bef898dcf75851286f13d8e14844ebb65349f81a26469edf47ad57164eb1556c55a5a7916bf415aa1a0c6f6f6e848199bc1260f	1647694605000000	0	11000000
10	\\x3cf6740553e31a13e1349135d9c01cdaf287b6b7ca91f7d3a4063e7272db25a167035ab589263b7fac54843534bd96c5fb123e533f4f99f43f7b1e8ceb6d01e0	191	\\x00000001000000015ff341b77e75d752346c79ee4d9593c3768b0bb5cea69f92e5c67f045a667b9078890fe1fdbd86aaf363d9e40bf7eccf5b895e9e0c91d4fc2017bc110ae85a8707795409eb79f699a73aadca214b8b00ea5c0565e5b390f00befee24421b8ba959a7be6810c7b9e1a6228dc75cd27c970189d01bb2baa6276cd0acfa4a83b984	1	\\x6a46f957cf8832cc40f0750bd0fe337ce19cd1cfc4575ac4cd7479ade7d06248e7003180bcbd21f78974c43cc951f7ff2088d9020e95dc4ca0e0a73edb126a09	1647694605000000	0	11000000
11	\\x943e7d2fd18181db14176a3269d73c0b3003a9a6dc2dbb73d33d4bd91dcef94e12c2cf7ed4c383f0480f9832df4e8c393ef927d1d3a7a7165f8652d3bb0f1a8d	145	\\x00000001000000013e04d21f89efc9457a3526f88497b31cadadfbd0e7a8dadc7092c8fc350aa14a192f73494451d78fc3e07d441416412c170286f2578adfb772087a70f54fe1f069f8718724b54e61a21df9ce024d4c0066b14f8570e8d0bc8dca020f3891129cf254ac06b8526e63576f802b2670c25163ee1c2d6d06fc77bbec1d2a0abfff66	1	\\xfc9404792534c333097693fb06521dc452970b8ee7224fdcb2e24a9dd2f6c143c2173854541168d81e2fbe1a61434382ccac77f81c77c34868fb93acc506b30c	1647694605000000	0	2000000
12	\\x33d1965fd5b340d74dcf390ddfeb805eeeb41d6ef6e5fdbbdf550c180f1992f7feee032f2e58f4155059192ed5547a4c18c4d23ed679d5f5f2bf50876e6db8c5	145	\\x00000001000000011238baf219af06f581e09466fad3e5c1abd4a22fac82ef3700ec125c941fe744cea12305a3af8590dd79c75979293a04102d93b959715cbca6375e70046a39c3e0903da1524f6162ae51b6cd7f3cabd6d56ed829671169fb590b04bcbc7b4871b9626f559aa38d1cbce1f3365ea0afad72745d156cd160f88ecd4c51fb69ad41	1	\\xb1431d5cc58b80d70f170ab78840d307240fe16bdecc6e3c8f0463b5829e7b337f3d47aea2cc91a21474a80dce63f19ba6d6322cd118a44a73f34361f023e104	1647694605000000	0	2000000
13	\\x72546d1916238eda096a6d69445b5cd2e46c671e4441d205a651b91b33d341514e3921ace1c6c9f1440e8a2aa8d023cc81deeb4ba96bc04154d5a3ac747b4585	145	\\x00000001000000013a19a357a178fb5f991d00148bd2fa9465341a2dc3fc095c74c1b88d479ca15a2793a0df5e58561969aa6b98099acac34442901d8b3ee5b66a7a6707c166732b8e0c261cf6bbb6279b54b92ff5a5cc7810e2c12df35bed1d68a1400b6f6affbf8ab87c782dc308f5883eaa7f04644cdb327055cd1bd2580f7ec668b40a4d5a05	1	\\x13f063b33d058cbad281e7f386e759fb20830277dcccafbec2c1b50bde5b77c210b55fcf1463dd751f8b3b6384db7cc1704aea5831928e9577de99ade11d6202	1647694605000000	0	2000000
14	\\xaa773c7b127bf551023a3925b32b798a77a958d954d92774b2d1a4c663280e7f8ccf306dfed9771f25a58248e79e048cf95dd10607b52d833acf251d4ee70c18	145	\\x000000010000000140b22c4b563403bd272228b1965a123fafc354acf14282d9a416b97562f5de7fd284a423b843a2c9fd89e6581b37502270cd3cd53dc772cefdd46cc2edb0a7188682a7a270b3195c53d8f0d5ae046898ee48974ec17788e29e802c18ccd32310dc04806503e893701137a288ffbeaf1e65fd3209a9c2ac6ec11745ca057683b9	1	\\x34b33973f865265c7b331767c1a483e329dc693c741cbdf98bf879f3af5435e6214790d435cb0a1bbd52c58b091e5050cb431a3578ac1b54e886dceb82e0c60a	1647694605000000	0	2000000
15	\\x2173e4cf1fea850a39964193bcac42c66be7a283594061e5e35d3938b13b4fade951541ae47d39fdb98fb167ea43aae55533771545e47ec08c39da16e629f8a4	129	\\x000000010000000125da7e7706eba97fd5c989f31340bea5dafb7863340634b45f134cbd15b428011af2ee655a9cf3f9423545d50179e7a1e339f3a3f857268ad6b4e4d7e55f8914877bb175f190f8054ade4758cf52f065f30f76c0d1b0e276a96fc4836fd364ee10b2e274362d66ead535790775fd612593fb1b2df820663fdd3a8b2337f9eae2	1	\\x0f7c107d1ae7cc5edcc966282087c526404549fa788aa6c2178f966f65bcdbfa3b651d4b7da4e5b1ba62136c5284d83f4cbaef78294cd1e30c1b88e75c7db803	1647694615000000	1	2000000
16	\\x95305224b511e555a13e8ada6c8718353a9936333d2784a4aa319e89a65a0e4db5153569374af2f8d04c9d4d01986c74aed984151eceeabc48239d5a5c87b2b1	191	\\x0000000100000001672f4cf0222fe2c77761cf6309475e7e0b14b1f22cf654cb18fedc6bb9793b4c416b9af340280f6a0a92ad3ff4481e94c5a58e0ef2886cc9b73650c6e9c8d695c319112e954e9118ea48907ba36b44b8be0a168fca6b189b65f6ee8cc062f165f8fb9d265ce277e0566ffc7ac9bfdf921bf9228b3f639ae8d38869baded32046	1	\\x6dd8ea696446d40619290cc998c0f3895c59853489c20bf3054e20fa600bf59118f928e0b56508b749b6f0e356ed7a8e543fb20be2c9ca2e843c4b897ee22c0d	1647694615000000	0	11000000
18	\\xdc641cadd268c12e509f0a83b6b7c07d72b6a649002ec2f1c8c41869f0112db9f78173135801dad96fae6779d4ac49d5d72643faa66a781082fda45fdfb88a1a	191	\\x000000010000000141a8fc186eb17137029220d614383dff40a0b127dfc8daa9e0c0cfc448f5e09ab44c7dcd0ddc48144207f958d7aad5e58642fa9a0188dfca9a873d5d571f88069441302dbfa96a675ed041204de55be53f4abca164b208f5ac67ba88bfca7bc757d932306a9680c80b8858134bdfe8b3de60abc76e0c52fa6bb28b97e1a086c4	1	\\x2b5d34f7e8afa5368384ca0b12e9d03b7aacd569216727ca76a4e2569323d3eef13f893e74549a5772a768c228935a2cfa667d8ee778dc23d5677b481640fd0c	1647694615000000	0	11000000
20	\\x14d740ecbb4d5fab6624080054f3d7562fd504276875d657fe27da76ef36c07e9d6c0786c26108ce004564628b09e4629088890dcf5a8ba1d854cd31491a02b1	191	\\x0000000100000001ac0446dfab73146fd133f62f8d68ea23179d33c0b008181d6d599c85700142211b5e91d01ccd06fbd53a573e9f55aaebd901ec3a39b5de639883ad69ce8d6ba808e1de64a5b13c163f01593a2b03a6abb8eda950c2586ddc097d42945356df730083394408e2fe60609e6347a21fcfbabab45cfe7e4945c10a069f61d9734d44	1	\\xa630b7df1b346b8c320dd66119335b0917619e05a394eea0777bdd1318ca02f762481a9abb8f9f9f11360b5c843eed6f8bb90d931f1bc0dd272e06e3a9c70905	1647694615000000	0	11000000
22	\\x08194fd90aa9a893aa409785585136c70bdace26248dd6afcc1f15b4dbb39ba01d028030ec950d9e5a60575ad864b66e202a71748310565e1b0e68e6531e4c6e	191	\\x00000001000000013794c7113374b7c7fb9e8049b8b2dbd7dc68740bd729bc0e5f725566a51250fd198cd95a627fae2f0458b4f93afcd7a6c98696f796445b1533ee778341d69fdb6d814f9adbb575c7961685328050450bb747b3a3e9178b9198652ede6a027be5ed6a0508ef3b283bc6b87c6a858107b5d4e71964e3de69513d61e475a298a173	1	\\xb8037e95b1f822f1b409aa2248f96c66c0e2400797a91e02ba5f5734492a086c05264dc2a5eedec1c8b76c5d569b635d6e02a6735928983c762b161f16df6c02	1647694615000000	0	11000000
24	\\x53f21b0ff91ad0e4c0c99d3de5c91b4de8a3157417e603882434cc61adf05e3a298073e664f01f43409f5a83ce30df108ba6cc2a1c891bcf9d51f04c4537570d	191	\\x00000001000000019351e40a124000f6e26692b4eb78c1c81a03587f397b63661334b3b85ce4deeffc717a1d56012ec9cb5a903561c4e04296373610e785e3c628e3368eedae32dfcf530f77c5236b3808df3e8ac26d679ab4715c69d7d4a6e10934d6da3b0e19af6c4f5451d3ee75943922d784d6864e9c29f6713f004c1576681d861c69144be6	1	\\x997fb1f3011165cb24469147053b1f9bb2b84c46d8c52fc4afda74ce58201acc20c1704e31e38dce9b5ed90a76e73a756251a16ae40a1bcbc2553cb51448ec06	1647694615000000	0	11000000
26	\\x6c1daccf111a13de01d239e9a8e154fac5435f33198ba8893bb02fc9407ca8ccf971356cb36b54c99f3104f6e0605d85605ed5a8da7aad4cff9d2971b983d60c	191	\\x00000001000000011ba21885a2aa38829ecf67c26a2bdcaa4483d757fa591f099a77605a6fc897beaf85ce5b7c028a1709638d7eef60a1800836b34fb14d0251f43fd725600e033a8afd284ff6e043b9b4e1b3da628ce2f5481f44709af8080047f9fed5292d972f75acccc26a2d74cb3623d1fd785234d82c4863a60a770d74867c84562f9964ba	1	\\x36082675bb4d0f323ae7198308c2ebd67efe23849d04613ca1753ad6540303b6941be03fa9fb8c9e33af5590619f92cf8f0565885b95262c207378206ed4310e	1647694615000000	0	11000000
28	\\x4f5bd1c85e2df0937d9da835bde84b5c81492e46d9fcd5571ad4e1c4a8851e6253314d861d1f9b1c0f06a3cb1d534300eb21bd551e0eba17a5fbb3bd3858478c	191	\\x000000010000000152ebfd94de4a113374d55d2d8978c21f66fd24dfcc31000ae1023b50f6ac837496a1027c8b86bc2876aa171ab8d357d8b2df50c6ff8b4656f60cf514ded20b7d7e06475c1f7a8c79c2870c018b161aeda9be2ecc50b593e6d3087ffb7d9c8ca467bdb746a6b6b26088ccf095994355bd48f16329d49c3f0091ca9b2b9205c69c	1	\\xbae5f4d6bf402bb3c6acb2a0c3e0d88e4847d752093775c9c77cd259166d7151f462ec16536e11619e8e1d6ee386ea059913ab500d511a1467a76c8ebf3b6f0f	1647694615000000	0	11000000
30	\\x1b9c2542a21a877b0285486328281221c500a3866c36a4e45303e4705f5b93c2f23b9dfddf3a5f1e34d2d7ca01127185edd4127ffac264d2b0b6ecaaaac316f3	191	\\x0000000100000001082dbbe588f02bbc2950a770a3643dd4d1fc442ad3319f551b221af7208a50a1599388099676d99e478e54da564431bcdf95a0d0fa72811b847f4247f6f6a873201044cbe2f2f722d10f3651ed9c62a8b4c68bc50c1c3265c550fe52bfe2edafefe264a6c5dc9aba48769c789e83384228fcd79cba0fd05ac410b62ed18b9139	1	\\x67b7c119e2c754dc996e04b91dae6c19765e41d45671d812e27620794e72748272009fea85ac8c354e83e298ab169d70cc056c2ddc79bda9dd0f2a5f332b940a	1647694615000000	0	11000000
32	\\x5f4baf5ed9d25ffc5d144c651a9abcb8c1fddd99fba9bb2330f28e04a52eedb38788ccae11b5e619aad608257403e62040e0a55c046e5891a1eae468898208df	145	\\x000000010000000109f1561e7d4dc0ed00deca6a6e4da96afcfcbea3c1d5f84aadc7017076a1ab057c1c13d47759fe1b51804b869466a3cf073c53dbffdde1d7d1b9b385962db859680587b72311af0a5d5c87945cbfa97493f2da106005b13262fb0437a0677dda431a683c5ffb75dd40d53e31b282b4722bda52c4f8a253531f32462a5df05ab5	1	\\x4cb206cb1ac22e2ac84fcfcd14709462498a2f60928fec8eb7acbdfe3ca89887a38895bb059312768b8363bf77785c029b33db8b0856e90c906814714c4a160d	1647694615000000	0	2000000
34	\\x85950ad80287927547fe8eb5d8459729008de16f3f0834ce55e8d853d60113ba7c70eafe55680d8616d30ed799914497210a83c43a47804ca6843d7fc4cc07d4	145	\\x00000001000000018bc1d2733a866bf38cecfe232f82fea86bc124c2f1b620bd395291fc4a27043a86e4637e39dd6348bd4107dd8d7438af79638301f405d4ab53de15fe1c0371a5c9b29cca1f28ecef653e068b5a0acea37c8bbf7830e8c64d0fb22471c1cd8a477d358b096937e37860c7a18280b6a911aba6e622fc0d1603607e80eaaefb9c1a	1	\\x0fd9a54600d125671957c29dfd2dc2022967e3271c4624da1f60b79b513ad85a9111ea9ee2b2fececa8a186da53de06de6fd52cf4317e148b27a4d07acb4c006	1647694615000000	0	2000000
36	\\xaa16caa093be3e28845ceed78d81ee973fc37e0de26f9ff3c6e7f337f8b0462231bc5ba5717f620d2e0150973d2fc671be0cc6e4752d8165a280ec717a64571c	145	\\x0000000100000001a7b3b76f396063ab58a95e68bc92ae2d65dae19b35faf416ac50acdfe7559b325a1861c8687705d1c478671cc98a68509f39443974b8c7e727dac6430fd186be729d912af77f637cd07432548989bbc53a85a2a3d55f1e527f57589f47ed6f0357fe0a9e72b659de497727f1fb7b7c4d643b4389b47e85bec987caa217ce57b8	1	\\x597039c3f995d81e4a572d9fa5b1e22a84987c978e04ccf8f9fcb7d6b4a036396bf1b53ea890fee5ace7bad37dc5313a0882267c29fbb3673569024e22008100	1647694615000000	0	2000000
38	\\x877522856c602c51e5b842fbe8d0efd96fe06e21addf6afa61f083b2c707edd6c3c0edfa585340b81ea1f3bfe2cc40005f089efafc705efa6fdcb3cc33a11ab4	145	\\x000000010000000116460b1e38f5c208feff82c38c069f4db70f16405a98c9dba1df1c092b1cfea6dbf8c26e56f964984613e80388779019d61f52b1eda956e6c54d5b21689d7a621de778c59dd62ea1be2a2e5e6f47fee5c42cb69db4e75fe7d5a0d01090f0af27552f98d6215c2e666a534cec6507ec4ce90ea119dfaf5ea993cbbd1525792130	1	\\xbf366405de704ec82b6730317ffdbf63065f59ac4ca289a6150d200e143555bd57d97e6f3bfd7a07a8cb21f88182758a2f7e88f6cd95d3b90964ce41435bba0e	1647694615000000	0	2000000
40	\\x149d8369fd5d2cb91ef10ef1b08c3da56ee2cd4db5154d2d8aaec5ddf54c0985c446dabeeae3789aa89ba2be1a33815c6ada1e037deb786ae90071644f0e9be4	145	\\x00000001000000010c854dc2bbcbe94aa6406cc000d3c61c63cec653c624cf9911115c7918773c1e9342e2078783001d2b6d8a6aa0a10f959fddc8313b63a4c893e99fb3cf6637c44e9d23b6292e70f640df3f426aaf43428156ba924970549e8ee7e36f6ae7e43a63231019ece8c9c1677a3bf8375509a86c443176c58277603270d2b18579644d	1	\\xe8c5c24e2f20ac725c18709333fb79b3968924a06f356d0301c9ca94904788f13fc0ac39fbaf44cf48485b459b7d93e7637f42c1f19fe4010ad2c21345207401	1647694615000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x63ce16a6760e54fb0000cc4c43628fac8bc12947d4db6d39f23bd51aaeb4f805e929947200ca85c18a7a1fe43e2d1d0b2db95b9721f4aeb8517db6970871d902	t	1647694595000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xd87138f99ceb81a1098d98704a59e70944036844268d7f670a156cad776ead27b2fa5fcd5b2a32e29d0c801e21fcc91c15c758a11dfcfa186ba0bae47f2b2603
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
1	\\x4f07557117ccfb95350a1917352537f1e1aea759321e6d645b09b509aa087f77	payto://x-taler-bank/localhost/testuser-h8iduz4c	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647694588000000	0	1024	f	wirewatch-exchange-account-1
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

SELECT pg_catalog.setval('public.reserves_out_reserve_out_serial_id_seq', 42, true);


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
-- Name: deposits_by_coin_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_by_coin_main_index ON ONLY public.deposits_by_coin USING btree (coin_pub);


--
-- Name: deposits_by_coin_default_coin_pub_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_by_coin_default_coin_pub_idx ON public.deposits_by_coin_default USING btree (coin_pub);


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
-- Name: recoup_by_reserve_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_main_index ON ONLY public.recoup_by_reserve USING btree (reserve_out_serial_id);


--
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_default_reserve_out_serial_id_idx ON public.recoup_by_reserve_default USING btree (reserve_out_serial_id);


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
-- Name: reserves_out_by_reserve_main_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_by_reserve_main_index ON ONLY public.reserves_out_by_reserve USING btree (reserve_uuid);


--
-- Name: reserves_out_by_reserve_default_reserve_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reserves_out_by_reserve_default_reserve_uuid_idx ON public.reserves_out_by_reserve_default USING btree (reserve_uuid);


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
-- Name: deposits_by_coin_default_coin_pub_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_by_coin_main_index ATTACH PARTITION public.deposits_by_coin_default_coin_pub_idx;


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
-- Name: recoup_by_reserve_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_reserve_main_index ATTACH PARTITION public.recoup_by_reserve_default_reserve_out_serial_id_idx;


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
-- Name: reserves_out_by_reserve_default_reserve_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.reserves_out_by_reserve_main_index ATTACH PARTITION public.reserves_out_by_reserve_default_reserve_uuid_idx;


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
-- Name: recoup recoup_on_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER recoup_on_delete AFTER DELETE ON public.recoup FOR EACH ROW EXECUTE FUNCTION public.recoup_delete_trigger();


--
-- Name: recoup recoup_on_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER recoup_on_insert AFTER INSERT ON public.recoup FOR EACH ROW EXECUTE FUNCTION public.recoup_insert_trigger();


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

