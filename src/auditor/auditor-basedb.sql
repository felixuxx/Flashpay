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
--         INSERT deposits (by shard + coin_pub, merchant_pub, h_contract_terms), ON CONFLICT DO NOTHING;
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
  -- We do select over merchant_pub and h_contract_terms
  -- primarily here to maximally use the existing index.
  SELECT
     exchange_timestamp
   INTO
     out_exchange_timestamp
   FROM deposits
   WHERE
     shard=in_shard AND
     coin_pub=in_coin_pub AND
     merchant_pub=in_merchant_pub AND
     h_contract_terms=in_h_contract_terms AND
     coin_sig=in_coin_sig;

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
   deposit_serial_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,done
INTO
   dsi
  ,deposit_val
  ,deposit_frac
  ,out_gone
FROM deposits
WHERE shard=in_deposit_shard
  AND coin_pub=in_coin_pub
  AND h_contract_terms=in_h_contract_terms
  AND merchant_pub=in_merchant_pub;

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
  ,merchant_sig
  ,rtransaction_id
  ,amount_with_fee_val
  ,amount_with_fee_frac
  )
  VALUES
  (dsi
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
   WHERE
     deposit_serial_id=dsi AND
     rtransaction_id=in_rtransaction_id AND
     amount_with_fee_val=in_amount_with_fee_val AND
     amount_with_fee_frac=in_amount_with_fee_frac;

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
  WHERE
    deposit_serial_id=dsi;
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

COMMENT ON FUNCTION public.reserves_out_by_reserve_delete_trigger() IS 'Replicate reserve_out deletions into reserve_out_by_reserve_default table.';


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

COMMENT ON FUNCTION public.reserves_out_by_reserve_insert_trigger() IS 'Replicate reserve_out inserts into reserve_out_by_reserve_default table.';


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

COMMENT ON COLUMN public.deposits.shard IS 'Used for load sharding. Should be set based on h_payto and merchant_pub. 64-bit value because we need an *unsigned* 32-bit value.';


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
    deposit_serial_id bigint NOT NULL,
    merchant_sig bytea NOT NULL,
    rtransaction_id bigint NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    CONSTRAINT refunds_merchant_sig_check CHECK ((length(merchant_sig) = 64))
)
PARTITION BY HASH (deposit_serial_id);


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
exchange-0001	2022-03-18 01:50:05.25842+01	grothoff	{}	{}
merchant-0001	2022-03-18 01:50:06.558734+01	grothoff	{}	{}
auditor-0001	2022-03-18 01:50:07.397219+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-03-18 01:50:18.235646+01	f	f4e366c6-9eea-4326-ba17-d3dfa635196d	12	1
2	TESTKUDOS:10	32FJNJJ5WR72PY3QDRG0FBQGBZHQJVC1R1AJEE03TAEN8D3BKK5G	2022-03-18 01:50:22.14043+01	f	45a3a6f0-e814-4c79-bfe1-a3a90099cd3b	2	12
3	TESTKUDOS:100	Joining bonus	2022-03-18 01:50:29.486304+01	f	27e143ab-ebe5-4474-be16-b4fca896b066	13	1
4	TESTKUDOS:18	BC4SEBCD6YEV3ZH12R44CV7DC4S97B04XGQSKFMK5FRHX1Y46RYG	2022-03-18 01:50:30.160714+01	f	7e463a6f-f017-47dd-928d-3ba2d1d629a9	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
192803b7-fbeb-44c7-ab69-5b91edd0a595	TESTKUDOS:10	t	t	f	32FJNJJ5WR72PY3QDRG0FBQGBZHQJVC1R1AJEE03TAEN8D3BKK5G	2	12
f4455baa-827a-4a8b-a8af-71e7ebc2102f	TESTKUDOS:18	t	t	f	BC4SEBCD6YEV3ZH12R44CV7DC4S97B04XGQSKFMK5FRHX1Y46RYG	2	13
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
1	1	7	\\x9c8354db3078a804cab58dc83632f17dca351c60d9688fe7083a5c13611d6744f7342ae4af5fc9dc4bdb4a791f9dfae54bb38c10ec28f9cc18241c02f1057a0d
2	1	221	\\xf9368db4c4a38cef7a171c5740d8548a424ee037b179d70c2abc55f6f13151fd7f117fc2cccb03a8424cfffc954b5ea752788f9949f9dca63711f7ab6fe2a302
3	1	307	\\x229c91d87593b474dacafc06da2ef9c6db135b250519b4b50d4512bf26cdd036615713ae6294eb3df59f7385094badcb5b79da353095805e39bccdd551fb340a
4	1	375	\\x485bafbfbf9f1519045ec7757f917655940069ca3849ee87e72e796a36962067e0dc88a0138bdcd77f1b0c7d78ef39351d1e73852b48371b04a4850e28000705
5	1	134	\\x3b8eefb167752ee402022691a4f8da029379b2770490f57bb74f2843969d9776b69d61abf2a7e59caa77b2cd7bc4a6d506397e3d50ca7f7784203f5adbac0207
6	1	329	\\x91fc209bfb3ef90aec18f730ad19bab64d26f9b27334417e9c7da3296d352fd8862e45968d2d6108cb6363e618b5aee39a63baaadb0a18aa4efa42caa5a74705
7	1	338	\\x2ba11aa961fb20b444060ca5a89e0d35289225606a5e223ee228da2221437946b4e4b45e5036be4385e8eeecc23156468f202337511190a59f63d7206699c70c
8	1	177	\\x794bf216d3c97556594faecf712478b8199d3dd44192b32399a83110c0acc15c372b610ae86f2f3e3aeac2480bc718b1c1e983f0c04082f0f864606156977101
9	1	348	\\xb9288496e36dd15a5af2178f359b8001ba40d0e7b93587fca31c6bd529c5a030e83c90affd21d36df2bf6eeb4eb883185fbe513df58592955900334b9085d104
10	1	343	\\x645cebddf14f4ca0bcb30d4e9f4dc715a0ce708882e014f75e5c98b21155b221d719e54fbafbc440ad852c1e976cc3d0b04ef96e1c5fe9b93f67f765e49d3400
11	1	107	\\xe3dcdf99cd773e0c2bc1479590545ee618479fdbc8d08ff7c83bfb40a8f28eb86167fccadda71b2530b6ba93c57cb81c703e76c4a100c27ed3de10f624d4e403
12	1	385	\\xeb40d65426229742f013763b58a774a7ee8ec285a99fa4e93ce59caca70f8859bd64333f168e4a451ec278416f529f48314c9eaf5c3f425c7c6bd6af0584970d
13	1	46	\\x5970e44e9027cd89836e417c608778686f31a45dc02c78be5af3472e38f196a7d9263054551556f2f8b188f9caa2173df7cb738521fc946af083237d3a015306
14	1	56	\\xad57a8eb0ddfe1da685e58be38bb0ec0dd9d1dbf6b77bdbe9425cc2f5530dac1d1f923728e99eb404f3b44cd9b13331066eeb9084f552494a319223c732bfa0f
15	1	64	\\x5eafedd01a9408418430ebb95c6ff29477ee20c0e4019fd255a6c7d080d0d3181faf3b05dd73db7f5c78462bd29c879d2800d229b343af8f95719ad8ac609702
16	1	104	\\xf1faee306daad272961720a03ca73ab697b6572adc0532ecc2510d5dedcbb293fc7bec927465420737f409b822d9da2f48adf39c4fd13e979e2f588a4ba93109
17	1	387	\\xe15683e512203f35a571202a37b6ec23cc93b9a4e90dc5a639ff0532220e9a8d1b3e12eee552a5d62117e4de9af3b2b0ba6f12a64051cb35c4ab0a0a783ca00f
18	1	109	\\x195f3376ed228153cd7fc6bf35e31dcf89fada7726d26cbf9cb8fffcdcac8d10f8de3fd1327fec6512b4f2b82d3ef5aa55927d0c269217710a1ed8b8357d6508
19	1	393	\\xedd774d016b710233bbc9c89742316e56e8626d480e71d8dfd8d30f8d49a1b59c0a1df1c8376d129dae9dbac23c726c19643af51af9e2582955309012fdc2c01
20	1	45	\\x400f64d31608ccdff7eb4220b90192d204774a3a545099cdfd3cccf84c508018d09eae9fc4d77431b6f99981ed254f2c9202a7c1d0776d963ff7ccdbf50bcc0f
21	1	144	\\xe9445499c6b45e9f643d053da71702a9b9c3fa4f5d9e73aeeefa781ede161271d0500eb6f7f0c772508094e7782806b6f4d7b567d78a4d52f574653f481bd80f
22	1	199	\\x0655cf4e8251329dffc942c3104d939d31d014d9f0a83c969c8be282ebd44a276634d9aa4d3bbf947905817218e9944f1280c8172a9423d91b4b5ce7a08f9907
23	1	207	\\x1293781d445553acff332c213923fd63f58f635d1fad858a8061dedbda65efae032dfa3cf12e675ab72a91694f03fbd9940d072423fc2b6dc7df22d8305b310e
24	1	219	\\xf52d450178dd15499d111ef476473ce76c64a2eca218c5f244e335e0f10248a668c6000d2d3041d0098bb15e8fba7edccb70bc856c78b1b33e27e75cd53c0b0e
25	1	290	\\x937c0ddf5dacc4834bed8c507a201c683bf4598f77b53f75fc2b645c89363f4a95418883764b99165e65c3c26a1d31a39fd72693bf17cdd066cdca88554da907
26	1	344	\\x0ae85eeaa9fc546788921eded61bb32c9360859d95b6d1c275012918665c38fb6fa6eba19cc39066c215b96f4703625844db066ebf5aac7f78edd80a6434b501
27	1	59	\\x87d730a633296aac9d877af0bc4db4d97340974602fe360a22fde595c30f9cde444c57ba892a01e75a1eee41898d5bc4c0ba8f1b121e5f82c8c4832455ecde08
28	1	87	\\x6f912efad485f7878d0f492ca083f41a307925c756be4f2e6755c122aac2239ab2ca9aedc0dea666da3117ece66cb508ff2eed69815da8ecc4f9c7fa8267df0b
29	1	377	\\x51cef88521b068418b869604639a835c4042d729c3f700d30d4a5fcae562c60dcae6aeb6bb796eec89163419ee06855d10d2bcb0d362811994c7e95476570f0e
30	1	247	\\x5cd71f7e24998a728e7c86843715bfda3905819cfec61192b6fe7d832d252735b317b78225f14ee4b64a8430799b1a15e7d9a1d4572860b1d7f6777e2b3a8606
31	1	303	\\xd09c62e9ecaa62a5da1b801ce925c6f24d68e78024c3be9d2232011c8a3acb9cc44f9832e2ea6b46b099ce757d8d1e5bdbee75b731776be04a66d917eab0ae0b
32	1	373	\\x20eb8028d80af53a12a5dc7cff1551ebc9291084c116f4166108a451186656935074a528ccd925d410c8edaa87bbebbe49ec042b2bf924e56d05fc12cf1bae08
33	1	404	\\x687c8539450b3c54a7b6c346dd7f334bea08de94d5e61cc95aabb250a1f9b289aee9ac13188b3071174f0da0e8bedce7aae1488722a0582e31742e40dc8e8c01
34	1	193	\\x5805fd7df1458da650274f9573c3d8b77887e7d5ed7892530003ba1808c73556da35b21f829458c7925b5b60e765f8a270afc8e2450597a1976afef09c97460c
35	1	257	\\x6f2d1039ed4a71fdf220f9599e8109bec146f7a1c859ea8deff73f802d24f627c6b8283bb2860e489e0e7415258f5bea9e33b659fe4ce10e332542b070eecf0b
36	1	281	\\xc307171087ece61326e90b6c728066fce4443adf7ca8482adb9df39048e283c0bd9650b314af3a34185039a3dd82cdea0c955897531b85eda310f4a27d9dde04
37	1	350	\\x2f1113ea74e37d6dba98324d3a77dbfa12fca3247e28b98393751af395e86e7d24bc1cf608a95f9335bc2aeb37230b02d251d45b29624235c6419279ce4a2e04
38	1	328	\\xce3d6c8feafdf0dc9041de76df9f5dca5c5a0484fad3a9f25d2b37d189265e36c5a74c46394bd7a22bb94c41c66800742b70c413ab1bfa354ecaebd613c2fe0e
39	1	311	\\xbe12a7fdd14449a13580e379da9815aa7528fd67431cbf8842bfc4dd5330897f4131d28affde784bc473da1cc189a8c8ff49357b5f8f7cd889652328b0c02503
40	1	314	\\x48e59aa7a4c11f40e2c117c9b1ed7393511646be21d9a2cd180aac58202b6a83e8de453993bd3c19594185e1b6e672c28da20d0b3b911d4be9bff2797137890e
41	1	271	\\xacf3a9eeca2d50baae381c2593322c5158eeb298f4088e22abfffa15713df073e3e751f35e7612fd96369509a73d0cbc478d426534fbc2cb3a1c17e77df6d103
42	1	39	\\x7968396be5ea8c3c93e0d6a80030c2e1dcbf8e92de89a4b0ddda71e1162e7bb89d14c443ce50d00c744e1c5d09a674218b36559a47e93e81d98c7a1fe1731d0b
43	1	399	\\xc8defa59ef710bbf24dabf5ee2c753c25fc3936ab96d86a9167a046bd3d121ed96c1000d0ace4eda5cb5625d3105d1a7ea8d17fd43e78de487c01e948acccd0d
44	1	364	\\xbe3965990f1c45501a4b2c54259e39d32cd54bf49e8a7e55a52c9f97c86c2fe8cdc7eca0b1541858f2a42f42a983d4bc8ec1ea58d8dad49b3a4d3c4dd5019609
45	1	291	\\xf95baf9f4a6c12f5dedfb8e903a2acad199c207556786e15d724519b3e33482608e09e994a8f8c5347c883a44a979782ee4f3b21be531d76175d5c96b92ce906
46	1	296	\\xd5a831f9ffbbe48b5b4a1c3031a38f9947e1f6b2bc02041b073e10dddbf04167740e0abaf4c0605baaf19e56089b182a2fc416beff0ef1a07f148efdd94e2509
47	1	138	\\x99204043257ea83f9b8892e08cd44da19f4c79ab860b03be6707fe988f7d616bb4fe5b3df0629d19b1e829e57db606b9d02e3fc3dd1db40acfeaa0e4c59a840b
48	1	417	\\xe3ff6f7bb0c7cb706727057c6e1ebf7e6e3d9306d86110036209addde35854a16f72d67f081557bf7dd0827ff78e327fe94fe733cf10baed0868d1aa1ca27205
49	1	346	\\xfe605775e0aef9e6e3b0dd598e304886d5b9605bb920a1d08c04f91d1c48c12cb862deeb9f7101ce1ae37869c9ebe6b19e8bac2bacce59e64c2586989d293c06
50	1	31	\\xf4b48564451b01af0583cd22282ca60d1e12b9e50f662a1926c693398facc2ba933714e2d49135609909ac01f1957f0bbb1c200d50d2623f35755c21d4b3ea06
51	1	121	\\x699032ea1ffb76acfaea313289ed9d372be4b4cbb85c59f63107b5f38d3df5ec344e223a8f62f804957f471e787f3195420686a11195a9e815e1a85e7fad1807
52	1	182	\\x9418495d32fdcef59daab9e3fae38a9a2bec9cec42eb3b207b2eeca4b056e5bc26a52af99fdf2141ccb36bacdc71196bf47b9ad0bfef2ec4cbcb0bb061b6030b
53	1	174	\\xf43ed862e96fb933041372c00bda1c2b86fdaf63fa71960c812c60fb467f4f544617c3a414f705bc84480ea43bb2c53ba9ec036819e233618e3e13705146e509
54	1	41	\\xd8cfd0e7caada4bb9714f73dcf28f00c71cffb90555db7724ea968bdff6d19b58f5ca4f05cebde5c143fee238bd0518729affa27ac8ce89098d2742a96571e04
55	1	93	\\x7dc7bebad9fe952e073df26a163586e806cc8b238049d920cb2c3d3984280b4e6f78a0523360c210dc090dca189db561f25ff2730384d65a1544fe0268257f01
56	1	374	\\x31a1c0a6e07bdf6a2894ecd608db78f1d29d6510c19ce87e996400a0348368d37b64512efe6ed8993849c91f09a5da9fe20eb09a17baa0f4752e286efed5d40e
57	1	241	\\xabf4f952e2bac1a66abaea94b7af251f2adcb2497fe994c47c85ae927321d6de189ee375dc4580371259398d0426454c69948b4ce1ae62da6e6a407308f8f704
58	1	305	\\xed47b22f55a773cd208bcb9d571e5f566936ab217bcf2966eb60faa7689d3195c4e4db3afb872bbffbd98cea6bd1d5aae213eaec590e50ba7035e5e5275d7609
59	1	321	\\xb20f4f0d858fa8638d4bbf3523b00628916174585a12616eed292f2aea9dfe5a8c51e1217f8b5f594b12250d7a471d1e95f7399b763de63d41873b9a495bef0c
60	1	246	\\x93edb7d55c88ae41330d552825b1ae4e022e9e9373d4c8075c48b8c3e1d44f3b4c839dfd381060eb6ef3cdb3961b756932fe972cbb9973df2ced7e590548f90e
61	1	265	\\x5e8c0ee642312b5f1114c6d365d4d2d8c12f813930c0c49fa358930126f67dce82b8f6ade23c381474095b96b520dee0dc245544adcb5042c4e50b985e344209
62	1	112	\\xbacbd3b956b9190c1062b2a77fe24f8225859e04e4dff4b79e8fa724ceed5b45e5bccff91c4409938bc0614d04798ed8d5623d1a21af450eca781ac34fc83b04
63	1	163	\\xb122cfd424824648dac27b91a6f74e632624a087af9fb5e349b9aa2cbc181e6595171acb9389c408910cac12e1bb20164b47539b3b1836add234f51a254f8d05
64	1	63	\\x0d85496fc91f675773cf4f42c8c591467c2fa4cc6ff3182b63bcfd13a55e905eb5e22230fce9c2164a783c3cfacd801f1980fc02bf6e0770aad059424146de05
65	1	73	\\x2b85f78473a367885b10b07848d598b1b2b67910189365924fbd080e2084ff0cab056605efe3605af1da87ac0660ae6d69c18c044126cec3b2064c6aff535a07
66	1	333	\\xe4c4fe1f6a4193d5138770b516ad79ccab054e8878370c5e3bc20289a818556e3d515798b608c640ca92bc4fbc575312d910359660364d67640d16eda5845f07
67	1	362	\\x8f3825b70b5bc1619dbc7ce04859a16e1b119a0014b2690a6e86388d62205bfb2d3ff6b69a3b375fd26142425e0fb314a2d0cc22de4f3f8982ea197bdb5c3f04
68	1	368	\\x9a8df5dfa71904fa5592d9663dd07d127b2197bed85e5cf496cc8dc1f6542a83a2446245e5979670293597042ea9091fc5bcb3c7e03cdbda4ff68f8f366a4306
69	1	66	\\x04bd3d944957464b6da5b759bb7a1ca1531f4ab7bcd7daf66a12726e8bd56ca31d8a8355c12efcd320b992c98596d1e9e5c7f563eba67b51ce5144b13453c109
70	1	84	\\x8f1119e9cd78320e11ee64d87f4106833fe0598e84d0b966a48bb4f439a7c0880f2ac632a12a2a2b6268f004b45208c8c2cbecd0f9371796da4d899765d5ca04
71	1	252	\\xdf00e7bca5646ce9a3485efc44fd518fe64e5b23f17a89252b298b1b347dc52f22324783dd5333d8751512b2778da3d047fa1497549c5f586093fdaa1145480b
72	1	423	\\x606d94e23edb57b13f4502dbcbd2184dc7bf908114b0dc8d49b4b2fdfcbe27b4317b7d881b1b37f33d895fc068adeba9d73f12481c0645019ea64d667c07400e
73	1	72	\\x9bc10ca9a84b95ae76299371241e819e73b410ebe2f1dd8bd2ec7b7d704dd72726935fd37d1ec1f7ebda1db0315686394e6a24252402052818b1c8c2ac8bdb02
74	1	405	\\xe22c59312a2fde51eb53f7958999c8cb9e1684aa529bf6131ba7ddac6430da7f8185be70a52e2b6dbf92d21be658a48e058bfc3a59c23b27f98550153d37ba0f
75	1	336	\\x3b8a243ca8c44e52d176e3b66e1096f032dc2508a5ddc2bca3f41fb359f89eba41199249d8b059f5b9a4f53e971a7a7319f558783567111bbca8e4313669ad01
76	1	233	\\x05e8bb5c9e95644d6bbde84a4191e68a353d48ed0f135b4ac7a75fd02a487897c3b6714a80125173c757002ca1a368c35177ce71599ebccf7d2544ed7a03bf05
77	1	220	\\x23219ac30f88d2815a67f07145ead9bee8f665a864d87be749cb545bb40b439d3f45d6ed8950f0c2711e746eaf730d78f75e1591b0cd0237f5ac762064afad05
78	1	361	\\x192b792b42d6057b0931595797a9e4b49d044fc2eb9109ffb8edd7ce7e11e505e74f9fb8fa5545b69053bc48d957af1d93b4d0d208006069c27e16e3ef4b5d0c
79	1	114	\\x54802d9aa8dbbcfd4469854a8e118c393c96731444d9c66d98542e1db682640793802391293fa474f163035e607734cc336f8c8bb71b87f03da259670e6ef706
80	1	13	\\x39241109a62d06ebba7938adb4984275beda76e2d8aa252941e342ca8db58b55c205f634a66a695be1d86001b5bbad59a918e4cb56244650f5a1259444c00603
81	1	82	\\x96332e6e95bbdbb5192d79dd993f274d4a21e2a129e0ed5af67b6642a893372fb2a4eff0d88bc733c69b46ed795f3ff1d119aad868962079b667f514f76b2a02
82	1	43	\\x556ea891927271018ddc2b3f5ff8aca19184cbf855edf590e9f5e956dd3ab77b97ac064bede6fcbb8aac1d73a3253358a5ad144ed6fa971d899b94c3fdf9f200
83	1	126	\\x732c8c8ee2765e4d1170a6389c715e12018992f9c2824beedac6a4c68652caad661ec9e35b9889764f25c810c919fa8d0da267601ad0b7f87d9982e1348df503
84	1	14	\\x97141e22c7f07c07738c6595fb8570d1327360d0f16f24fc040b458c250e61876c7da677a72fe71522f23b73efbece4771f5423d27f02f628f639e2b9f0b7004
85	1	228	\\x76f84967833c4eea0b5170721e2760854e27b5a4fa29e551b0b9691423137e2840a5301e3b4d62fbffd8e83cdb60ac477d751262aec3e341a04dffe02fd66905
86	1	331	\\x0773ce0e9e681aad3cd072bed90a7aff731d225d0331fa631a38424de1ebd642cd634cd5708bc4b33463c3e6f74a97a10e64153df18f447fc72931a60d5b6c08
87	1	168	\\xaa69ea5f0ccf3f9f89b43f14d635bf7beb604fd36a9e04ca3095dc1e20fdb1ffe8d9faf24542a73cd8d4ede66eaae6d36a8908e48b78ab2dd399bc8b68dcf501
88	1	68	\\xcf82af9b951f4f99291397134aecc61a0b405d3a15854c57da6d2e7b82915c338e68ece1bcf8d5aa52ff3493c599228b6b9165e2c484d9eaf4534c75197add0f
89	1	267	\\x397fb8de6d33310bb8c550cde1b189ce2bfc35e4288fab61b546364b9f352d76505a24450c6c0645eadf8d2ca02029fae25c904db0a51def57c306188c99910e
90	1	386	\\xa6284e217bf488092fc20bf295be545f9bdb3c73deade007d16c767cd085e7d50887f390e446abc8a75ef832c68e3a45f17d5780c4ed7a36c822b5664d432c0a
91	1	313	\\xd3c8ae9d11254ff2630916dc721828a4e071d83c439fc38d132a4def16eb0415be07331556615604869ea1da194a0d7d08b6a02318d4181fd39a4933e3444107
92	1	96	\\x77b24cbd64382ef98ced3222504ac79dfafd1bd57e4dd906e947b1e0861a85b49f23a61864497cd5fc65d2e6762bd6bef61f34a8f6950f7ba7863757d339180e
93	1	111	\\xa7da753414dcd1673acad607ffc68706e65588fb9545a0c1cb4d8551bd7bc6ae052428ec6f9f361594b1ee4fb93f1686ab8386dd2c8967d60beb444bf7ba2304
94	1	129	\\x78c9a940b5bde4cd3ce79a90f93599535c1da82f716fa85124408217244429c2b9148c26ff013f88ae683425b6d6a0cd284f1c57f084e5cc34700244c3b10802
95	1	164	\\x5583d2c42df4c700c540888bfcbf8fd4e271b04fe06c01dfccc2dbc6c8a2f155313ed069cb30601006eed62681bb4f3c06ed12ff94f70840af4aea2ad73c0f03
96	1	16	\\xc53af6a352ee4321586b240d2648819aed330fe7f95a058a7f67218ab54cd8b541ae85be17b38a2a03bf7ad2a473913b8d3e53e8edf5ae0d336343142bcc350d
97	1	286	\\x59df2dfb97671158677301bfb3713a83a56155a1590d122ac8ae2a27079514872df258a9cf0348e3aa561280159c21af88caecfa26f8171c4e15d0bc02d20003
98	1	211	\\xde20583495bf4801aa862d78daa918061ede6404d9f0e6f0da804fc2f86665bf892e8c41c9592fe70aa7a1e3884e1114f8b3f92371a3a3bfdfbdd360f22b9f00
99	1	70	\\x816360f38dd65c0226582fcea161bc1e0f00548f96be8d15dfb27d554d592fb753b4ba3c9212c93da869db37428b9fd8b0606697770bb1b84722b7377aee7c03
100	1	424	\\xd81b6f314477d9994fa190c3223c5035b0006689e7ecf2766fe0470b449cf2e2bd2e17e0f8b2df8705baa21efb87aacab45fe3ac2d4e99743975d61b79be170e
101	1	308	\\x5f6eb8302f47bfea5b3c2a3ec0f4003c1db8805e2875a0b1a678c57eb6cf70f976d39d8f1f6b7fe7b157917885f054b20fe380305dadcc00b68590cc4bf9a60a
102	1	154	\\x5c1cf4834845e1265ac038bc62b2beb26e622a991be3756bc2fa7a7a24f878bed6ed946e78d17c105da60d1dcf76085cdf84666589ffd2f30e817ac6aae26208
103	1	276	\\x706c12dd00e147a5526e75865317433ca688aea31410cf3b49b5dda9d3983eea1e7dcae02e2512599832b9dad4cefc63a28f938f133324fee4c43e35506aee07
104	1	367	\\x3addab07c41072896ff09a38e6ae054a34a635ff652e9ab6c93ab82c435ab1c093a99bc7025a95dfc91697f5d388a562c76a97410293fd02342c962d4f282906
105	1	9	\\xb78209e68ac0a05b1a2943859165d9ce6bbd874083f0dac9b07aaff33db445c8ad89910a024afc89b04d33245d205dcb78335840f4598af2233c82f3a34ab20e
106	1	371	\\x901e356f3030c600780dae162f459d3bfeb2ea6f34cd790fa7b7aa3c070ab681666c30de9b4b2285ba655c1e59941e44d20abbeacc753d2192a35a7bf61bde0f
107	1	325	\\x6dbdd5d63009a1862f952633b25279b6cabefc7d2dec33ff220844b128a2565525fd14a5a92b893239803400c25982e0dffe7b197c666e80a8c9c011c191f50a
108	1	101	\\xfad7d1aafdf2414f6964a52ce31622af84ddb043fce6de6e931a7cba83f1b0e9b9d83f403ca89ff3a26310545895ab05d67aaa7b0389eb13a7f4681c2f781203
109	1	318	\\x58a6c7b81fef01ba9aaef61dfdd3777d0eec29b9e24a22a39fcedb45eccb1cecdb6f7e24d060382707f8c7ab9a9a11f311978f6db40c10c0ec88ca4bc764dc05
110	1	108	\\xf91f689667c258c02e933a331dc295c93aca402b74c7b9839e4d35c98a03399e3f5e80ab43c376b933683b73aa1805035ec0053048735397b6c6c129aee52d07
111	1	149	\\x9361c65b4edeb02b05393dc2139c8ed345a3dddd38dc4a820cfbdeba2f7ebfdcab0112791ba35c93edb729fea55a94e3f4c76d978cf0d7ebe5b9e32a8c8ece04
112	1	381	\\xc30c2edd94880474bef789121b97854060d0d93dd102842e371e2b28bda73f21cc9bdae5cfcf6d4d7dd7cdf93c7d3982a896afeec1d69a7437f87ffb8192b503
113	1	156	\\x22b2daf411c494b89154ad7ed10973b64632ff3e894b2682d1ce3c3b48e26c23aae939d1692fdd937dffac4a0e6b5e0704f0798c4da9bcf665842a4d99a5690c
114	1	159	\\x61ac8d529e2e0233ad26e6ab73c5e3e67e1604a3feaa6b175e57abbf8949ecfd7b24ee93ed223531ba9d3adb3cb75944e55a0b54e8220b399801e6b5dbaf6303
115	1	151	\\x6b88a5f6193d44a79fb7e44590caafa1a80ff1e1ee84619412b79089a80de1e23715d60d654b6df0ae1ce85ea3744902262b97c09852adc48d9ee939feda2e03
116	1	148	\\xa6bd35935c45370283c0d5bea6003e7434e72b86a155763995ecdd85dbff1a751ee09480f6715c0beecfed5fad81de0f6a8741fa0a73d40250168c56d687b00f
117	1	323	\\xe1c25dab9e022021be02cd64779e238ecc05d21e78e8a07f1825ae40ba4043ca29d78ff3e7a833dfe2d10e6e9acf4ca721845bd0c17d1b699186f34e5aaf7a04
118	1	256	\\x325f03424a2f7ce746da3d10fc4f269f055bf519e7b64c1e4a8c2a5b54beae3d8da13f8b3fbae5f775399346ce2e99632d82c0eb46d7b05490e66f6230e1f10d
119	1	372	\\x36802bb7110db7b2abc968937ffd88d201663564c1bb11fbbf0dc6589f92c8a27ba203d23d8538cb79d4e5926d9ddd5ff0c8a800d97beb8018ebbec726acb909
120	1	419	\\x8ce8eb4f7433655091c57138036ad38ff3f834062bb8abbfd8ba49c062d2202161f3a3ee4d2f0fe171e9ebbb2bc3e12dc269b7470831bf028f22cf0fdcbd4002
121	1	301	\\xdffc6d65d997fda130e83ace7ba7b2707736f82f9460ffcaaa3c8c51267d542303e25722c8c2d882bf8b1629f54d920e0d1906d9df6e13b5aebbd63889d4070d
122	1	240	\\x52a9fdab97575163deacf0445186fa509107f8857b8c9114a77e832affa627fc99a49e6d5196e2e842414c7f7293092ac28b6097021ab7ef4aa35adc7f41d90f
123	1	297	\\xc887b6c0dee44227507c04f1da37fc7aa9ef38d18194d558097585fb1b062ea5d92ae84abdfb1a7c0d77a0d8e0cd2dc581bb7ef076620d3d718255b75e6c1d0c
124	1	40	\\xb682a5afe77512dade13350c204f708d12b1c1bdeae741955947ad33dad302959b452d8895323e9cb66268a5cf51a876e54c56cb45a95ce1fa276c7a93b1f00d
125	1	92	\\xe994c65511283d0b234128c992cd6655ecf0541800541d886c733fa4a9578718728fd4edd0271777a3283f2d0554bd9164c830f5644f91d1fb8079fcbb8b2b03
126	1	143	\\x8ad9ef32dd263a4f411584b75335c7b71e5cbb3688e883cd96ca7c32f047ff274f783466fd57cfc22db22e554161263ef4caca8fa6d75506938fabbd3a3f2d08
127	1	116	\\xf3057b5a136e66e9856f3d39264f47a826b97473a51ff6e7a5400a1688d7848fb5c3d364456781b69f8072f1c44747565ab7c41e392a9a0135d7010874f96201
128	1	179	\\x8f6c9a2b3f0c91eb50076f432819040f069a4ba606fb68b7891f85ecef568e828feb12a0e7537713572ffa5230168f7dccc5b2a424a9242b5c4030a2e91b7b03
129	1	103	\\xf0edba3d17265831ad2d2c7432a788bc3909d05f9802ee84293635bae4fff450a03b146f64bf3500b55039cb647898bbf7c70bc180bc2e884d53dfd54e4c2a0b
130	1	142	\\x03fbc4ef5ef492b8f20b304aae0fdfaf8c338cd136747398e5b6f56ff448f5a14a5a4d14bcb4869260a8744428fb1b4f39b972b34290569e81f1ba32e40c750c
131	1	188	\\x0c7713a0532f97b9aa5a4abaade7564ec14ca7fcced54845b2bb9cf2d1b7c56a2b7821f41d7890589537122b521dc5bcc3741f88a42347561e434c0ce0bbda09
132	1	229	\\xa42465e52a64e0cee64d5c1002197cbdbd83c1301347e790ba8394a1bbb01695d2a6d36309338d0c59375fbe05d18f6370149a7a139757e77e82ceea19e34206
133	1	217	\\x32d8bf86b87bf03b3ebacdeda35cc156ceb3790d3540cba98824a1d772af6ed2ffb8953f08455298d9255da482d14c52543faa54f64a5602917d8cde655f5909
134	1	200	\\x99e9fc77958b71ab73e34456c94eb5d2665107cd83f51212c8cb15c4b8860afad94f7cd85e70344dea2eed17fd3ad38b147ba21360cef89120378c95862bb409
135	1	166	\\xb45a1a8c38e4512938c0216fe35760a66a1881b4d72850c04e873e5c9dafe9f98e5849e8430d6b077bb55954ccee01266293b2577bf31b8ece349ce978480a0b
136	1	249	\\xdccda521eb04155d6bc0ebe303c627139f5c18d0e3ec88e11cbdb7e8a00e326c55c97243fb6cb97c97f787f4677ae677508e610931daac160657620d084a2a02
137	1	29	\\x5ba75c10ac557455121f89ea002693ecdd8f7e5ceba8f91f1c971a966e5c1966464e07ed5be65c24b7ab163976369178b6aa6a05d670ff84bc1237d6f5bba90c
138	1	155	\\x6f9e593278c6d9231854471a508f5a964b61fee6829fe8d6de3d858bf1e49019568529c3bca628ad10b182ba4a17e17ab6906c9a230b1956f7d1957eb91c130b
139	1	97	\\x6ad4ccc66f788064a21f7967cbaf88c29176a185651af11ea5789f04646674831e40d83d2c9ea2f0478e10291cc4587a534c30d918fafb9a7e2ad72d6c523402
140	1	351	\\xba47fe9f5e46c0f5317db21dad5a959e02eea0b3bc26db788732f4a3cca4b0697de3e657fe2191f94d0d8ea6cc6ec2f53e9e53c29e0a209ff04276f976fccd0e
141	1	118	\\x780ab059d674ff938f887590509f3e163a4d396d04eb72ec431ca759c59606cc064004f8d11192b2261c34cfee7239ee0d31a26aa5ff4b8d15c00d88466cae05
142	1	117	\\x144b7b1c2d4886eaae82991c7c63b0ab9739f39416d14720dfe0c1f56dee7c6d6c9a415a3f984ee422b52895fd381175785ce7ba81fc4835e726fb9b79f07201
143	1	335	\\xf95bfea8ab8863e546ed11f3bc5fe3a3bf6d37cef883a027a82284e37a3340a25ad126b9e4cbc529d8fb3e0fb70749f94f99b69a99e9f4a73bba802b4129650b
144	1	304	\\x66e8831a29231d436250b64fbb2af3ac955f242c3b8b45e1fc805ecf5e940b676bc2078d4257eafbd8750616e867ed10da037f7ab0b94a0ef4955352c0482d08
145	1	215	\\x1a5eab4353e6c58964f5c607c1a1944eedbd995ee3a5eca2cdbefe5132c248cf8582d897edc9fbd30995fc569b5656462f84cfff708f5ef5475676bdc8ef9401
146	1	392	\\x8280e803d7db888a2ce1bfcac3c42d162ca580b202fc85fc4d0c39ad69aa91fd861715450683500c44d4583d118072d6658fd3fbd4f87e68eaa17ef93822ad04
147	1	330	\\x759c30757ef9127efacb9c700b22b7ef0949ab46ed20ea30561131e6da8d9efbae9b1a97e5e4d5e7243f0c1064f2bee9bc6dce1145ab9731c303a36a0d706404
148	1	95	\\x7ca695412e33dd10d22b0647a3213701a71243106fbe4b7db3fb8de84696511b0a18171c6b8db50b19219fd6e70b667d512f1d9ea23009b05429e373c6cee409
149	1	50	\\x795f81afd46344f878e2e0a9511b478d15b113673629f187ad1ce0ceeda4ca059e5db71864cd5e1a3b2b8c614f52d3875223bd4403cddbdaee506b7357e96207
150	1	83	\\x648c80905109c6e7cc8d54797f6db0b20bd30a8725224fd7ee3df4413f25e04b613a1313c641860336f0a83c0de231510007be23919320d49498478e520a7605
151	1	54	\\x1e8a8e64e55e282e7261aa7339bad700d6e551237bb42e0d284234a270fd4ffecc9edf09ec607b687db50df675822dde47f1adab8d9eda622943600c3b915e0b
152	1	99	\\xc190ae50fd3c451a10f522089f163b17e0ec5c27d50183b6e640e641a36e8d4b76a1d7b4e1c724267e3da5cd9fc1f30f61d6005c080a125a37194facb012560d
153	1	42	\\x8fdd4c4b88cc735c24f177e6692d37bd6ea251d57fcf0856167fa9f7b2a1f7b1cc04a323838d9e8cd8fe26d35d6e2f09443ebe7b39dc2b5a924ba9e4a91a0c0a
154	1	85	\\xadf08c63c7977946101436049e0db992307ddcc67fd5b044eb6e0ff0a385811bbce5d5ddbaf635616d8b2a1ba4c40308f292ed78b244c4d0b49b378cc5274e0b
155	1	347	\\xdab93b2ed55e259b3af02ae1de6d213bb95da4b65a178f35f4698b895a37ecdd805b82beae417d2ea9a9b8bab0dde3be74f12f5180e315fd7d69aafd99eafd0d
156	1	170	\\xeaf287c01f03849d4e5348b2ae9172639a954b4e4586b39aab388ad3b518c33d6a72020871bfa759b71a7ea2b9377ad3345d3b5eb448f8cd7f79371e8823a809
157	1	76	\\x3987c4048b75356fa0a81a7b483496076e2e8b13a364805a984e68f6e5aa0ffd71a747d1d157e0254766dc7bafd11bb2910c17e5ea94dee901acb00dfca51e0b
158	1	204	\\x014ef45491779df56b9b5fa32e63ef66cc4b84eb3e4ca758ce0f302f0a167f09daa18a49671c65b06d43b9da7a9196e66022cbae8b711ccac568acaa0dcbb309
159	1	285	\\x1c4e622e2cf866e081db25c654396f3c2f7688d2ac78a3db2b847b42c4dc10044cd589a9f1fc98ef60e4dda2a24f8411e297fa1130a631eed7dc634d82076f0e
160	1	165	\\xf33527e7784f6212b0c87e33d486cdfd8d0f755c231686d45659235a779a6f135cf5b2c22efa0426630b342727f5eaa6aea40f79e5f8b5e6e2a191d96a0ce30a
161	1	289	\\xf986167f7592c1f8faa820ce2ddfc6c8799bb84dc2310a4e063bf53ed1a377f4164f27629e632090897283c843c1e903e2112f4355c77586a6cb8d8ba6fac50c
162	1	315	\\x232c6841c556231b76731b1ca5757139e46783c9433328bfab7552ead9cdb45dfe161b305dc90b91b504884e4a2691ddfee23ef5b29a20c7fecd443e77cede00
163	1	277	\\xe973458d1226f0307d497b20ae3df9c3e585bce56cba3c19b9e2170bc93513479db4514fac70150ef4921209f3189ad2a49fc5a5ff8a3efe08614e86edc97900
164	1	302	\\xddfb20eec1eb914a1dc67a31d46e87d97390360e403b9391f68d71f16a12c3da3d77f7e19816ee7c91ddd1748e57333528ff8ab2ac74a6c532c4fab8923b670a
165	1	326	\\xb489156c19a146deb967e621e5b7caf2c28c4fbb7e454d01f2359cbca9ee3612be19cbc710b9a8accd31417d32eae730f6d79b3a9068f098df3e305cb8a00303
166	1	183	\\xa4ac247d18d7dd27a1c17e6103754a84ee730666dce32f8c6cbc40ee0255b7a61e9b9cb3ca88d78e2fd498d1213cbbe050b468015456e2e54187e9882df78a01
167	1	23	\\xc025ddb13851181467bec4bd5cf2ca989181ab34382013de82244f31d64e13e2ef7406b3f81a88c9ce56d7f0558f7f846cebe4ba93f7d51a32e52433394ba20c
168	1	192	\\x9c6c81ba3e6bc49be652aa31213962bc27cf270adae7372c3d3e3f16db72df9591fabf441ab364140390f33b190c19ae7c6a8e13c71b16cd0c4524eae25ac309
169	1	242	\\xa014c41e3f3d084b9077c49ebc835d297e632aa2deb3d55c50350bb66defd051c29155f1a7c5e096d6e702a97840c17454a3b7860e6e0431370ae687bddb8f06
170	1	259	\\x0c75fa859c5ff89150906b25d3901e7d8e0498e34a0f53c35866383098065f020af2e6337a0c1dd13127db4b26017af19a367cb9b5542edfc324554b83e49507
171	1	36	\\xa48efcbaba9669617fa0d40bae0d1987b799f7c85177d25cdc87d205a79ff56165c45155f148fd88d163cbf6adfeda4a37e07aa18b46fbfce986788e092df300
172	1	391	\\x7f520e5b48442ea17822a02593213f04699c8f0237940442238727999bd3f2d39ab866027c88440df394d5724111f5a564acdbf3d2a2eac01e6693b73582230a
173	1	130	\\xb39b521e80505f553b91250973bfd3a0ff161adbf0d5a7f2b6e8cff715439e799e15121350dece3223f50cbc38f1abd74c0323cd287250dbc0f5ee1a4249d105
174	1	205	\\x48f3aa2461849d1fa22733c831fe1ca466a30d32c5369a58d3f7d36bbe2e6fa4c940e1dafd5d696811f26cc5fdd406f650c70188dab8405c4c77d8d40461cc0c
175	1	100	\\x0fdaf367df78e9d52c3cdc0c3d5a1b56e2873ca8e8c2564d0eab4b5c405b3816eb4d15bd957735076c79e1d31e59919923ab458ac92adf1dc8a842262d349f08
176	1	178	\\xc03f0700da468bbfd7057270a8b3c15784915a1a03fd693aa6b40790c3d3f0487aa2beae2afd4a003eb39c7c3a0178b5c3710b07d3cb69df4ff11586706b3909
177	1	167	\\xa7e2a17121cc784b001235106ab64b727e5ef889ef8e4d723459685a702985202620277d8fc940e4595423573ca333dbf579f740e5712068fc6d0c2f26eb9d0a
178	1	339	\\xb159f0540210cd8e986c52e75abf0714090edb611700919a4611e48a41073e5cf28ab1e9420ae86364f161560f9e5b7dfc45f882f512bcfd78c0d355d8a97c05
179	1	287	\\x8f4d863d5ad1669889cfbccf01841349771b72e1a4696c34c6852cef479a6e5aff0a36f3ba8c34518d57c0c1ecf88da8cd43c4607229c368d30c2fc1a077bd05
180	1	384	\\x39e5b59160b2a355c045ce8215c3ce6836332da8506e692431e46f52e6fdcbb3610ef04c6c9eb071f27e925cf045b620eb17609738c4c4c698d39e855facb80c
181	1	243	\\x65ac456d9b8d600a135fd2d6a454f6fa6f4f5b7b46a7ec9c88a5b84a008da928c1d17c5d27e7df0017cc2cf10c15dafb174a88bfac3dc41cf08c9aa240f99d01
182	1	119	\\x7fa37b54b8d209253ac923544c0ced43e81a57c58ba211f2c3d959b9712fcc7227842509570ac617a153508b05683b699ceb9f73507e592fc222bc122233230f
183	1	152	\\xf50f452d0ae68df0b5517565dac3aaf94097e22743556df25e7901629744fb0f5cf877fbf4e50409e71180ffb82ebb5103bb16eb429c9f982fed0f9bb7781609
184	1	139	\\x48393a12389ff3d0a18add6165ab0ca2b69f9055321054bff0c4c01fe605fb6670c855e7916e7b047ab19f3e8777652ff82564b877f2f35b1ec9ce4896c10208
185	1	369	\\x3a40bf9b20065a913acbcda8ee0c58d5d56499e812eecd09bc26b55d4ad5bb949a86fb826e3445b7d1926bd7e7a2d46fee3522c32f8e3b2b8cd170c688929c0d
186	1	17	\\x40ff209ce44e9dbc229027b4fd04c8982bf37090611b5ee03068957d7685a420e0e5a8d1274f28ff6b43cfa068b01830c81b8054cb68b54d6ea608981a909c0c
187	1	353	\\xdbd065616dcfabff241999495b7e69402113700d09c8d25fdd690d939988057a74a2e258e751c34ee61a6dec4ccba2e457511a88c57956bc1e7fb9f9c9edc40b
188	1	397	\\x49ccdc070336dcadfdab33a9c6efa6085018e5766050bd8821fecba9ba3564a4ebefc94eaaec1ce8eb368722f312b2525c375aaea725dfb7430cafb23cf1a109
189	1	172	\\x3d645eae8dc2a90be9c2c1028293ba0368315b98d6ad2709c2cbc36b3df3716c9b61178e051b42019becdec9878a59124f39a00b28395e87f2e35a225c64960c
190	1	33	\\x4109d003bf2ae28ceacb2cf0f7355bcca1028c6bf98bfc91310718267b220194255e3d093a778ec1dda010a5b7e1e76f7b3edd80669c724ce0f7c21d83900606
191	1	214	\\xc244f88a73542ff3357f256832c6961a1dc173de08722eb36c06f7c2edcf77b4ea6a53e2b6c2e3abd7d61ab3a1108e84f58ecc300e52ba22f09016ac52e52000
192	1	115	\\x69c94d99291b2762118b20619fe1e3e2c3959a69452d7629562448543713a5f314f115d05d046829972a4eb5707d0ab447cbd45b3c71800ed64e9f1df9340c04
193	1	35	\\xf50f131199b1902961b9eca7a49dd931b9cbbabaf2f976851b81588ef042c7531a716550008a3abc4ee1506aafb1dc58de2ec12e60f4ee0215b06a6b0c9f0e07
194	1	94	\\xe7d397f5fa8a439fa52e1d0f377a8204169f5102394fe1d3a1c7dd769942e249e453d5290655a344f6464e7302a35e326669e92de9a392dc6beb7423e1183e0e
195	1	198	\\xe35e21e71b610b50906d9fb7ac68235e8dff73ae87c8b901118634e9f296621466664a307c1de378f3e7a5391e8039872b50ddd12563108721b669d7e6ef6305
196	1	420	\\x152b56fa3014cacc3726f75448bffea1661797c7a5d517da7cb1a82b409b0075fff22402af9910748f5e11a5e248d0fbb4dbb4b7cd234ed80ee7c68e9bc10c02
197	1	390	\\x8981a7b703d84899d104f31632f40a8e2d13ee1e9414f4eeb5a96de82b5a211da23fa4bc7708ce51cd2667d14f4398eda7c25a62999375bf6e2b943a6e144f09
198	1	91	\\x88a1a7742cb452e643f816ec535041c0d7f1ce9e3cbe7a899674e27337c27f04cbcf84ac11a16bec6da6a8b0165f8d1cc140074c02cef6dac12e4a40c63f5509
199	1	406	\\xf938550e1b1b650ac4844b64829301ec196636431ddcd55a1e52cf3b544e5c64f79cbb635f53dc329f2bf8cf80dd7e5d04a6f966a95347a72512ef2938dbe705
200	1	173	\\x8eee65c69e834644d184d917fd5a80b535ce127783d3a431d015b77a9739ad9eac990f096678ddbec6a120e084d4c215e6fde2ffbb9fb97aa99c6eff5185f003
201	1	317	\\xe8b26cc058bb7af0551c436d8632c83559aea7114cd1019769704cce82a9b9fc43a60b9d2eb9c93919d8dc4a9831f6761516e0b116f716d9aa8d458b57e9920d
202	1	418	\\x82fb39ec455becaba3ae77871d9f206d90fa2296ca410bca8f8c5198da51160db0b46ec2d3dc929b20df45e19fbaada4e56258966ba946e29255ce106cd92604
203	1	206	\\x5b3fc87851a45439980d9c1dd7c0c1d9760395023df55ec2210c1241588ae894a8e9f7f4d413667d3b104173c8ab4a6193936fbe6813ed3a3f5175973323b905
204	1	27	\\xea03aa87f3f5941874430bae78488465c35c5294725855ccba864d64c4056e893abb7caf6b43d67be6936b17a17eaaaf02fa24c0641e5e6c77c9d28d9f8a5102
205	1	360	\\x05ec0e755dbd54fb4310ba2a12109861cd4c39c4154a9f7065a0a34089feac4c9c0d158827695ac7f2f0410228f755dd1e2ce3e79ed2a31cce8b8458ac4a830b
206	1	55	\\x06d3c9720c7cee74610c12459438bc38e4ef24fc953b70c63c483afea0a82c789943a52aa27c5a16549f3e4d7d6ac1b7317b6a30073d3cac61073a7208eec300
207	1	340	\\x63ac9b8527951398a86efede22d1cd7b18979a0b118188a1d2cc4f212c5e243c07e0eb05c006ba41a28d091ec19093a19f4e750a7b0eb4e1d6bb07e75e473f08
208	1	80	\\xcc3a5becc6041997f938ee67ced76d4c2781251d17fd3b0d22721a5a3246962c17a5343e7370a1bddd5d45b513e02ded43bb7d7989dcdab08dc9d27fedc5ab0d
209	1	10	\\xcd70f54a441bc9f0fc242dcc6536db07ddeee8a73cb39bae583a2b85bffa2c3ed4bd16c56d9602f31afbacc10d3d40513e56b99a8fd49cb2979792301bd07206
210	1	365	\\x4282a4e3575028b871208b25d62a061e00110a8964a34c2d77a6786f23ea01b5b5e031410be7897dcae177aa1014ee88ba448e0f072ebce3d470384276fbe200
211	1	357	\\xe2f3e0ae9e2a962fa7d707b451ce014c3857357a9a2e9e1a131d91406dac2b2cbbb3794d050ecc3fcb5815dc08af201559305653337c4e72bb29f59307f10805
212	1	294	\\xade67144c45139a64800ce4445f55470263a56817ae7af98efc6e6fc449966ab65515448eb24545ec976ef20e29df3451d4355c5f786eabfad7a74b7efd9d202
213	1	403	\\xcf5c325760201be98418192db5fa9095dc83c03de617c1e598ddfee29632f824ff99ab7caa6a8018c64ce654e6069fe9bcb45deb4cec192b54e95460e805a10e
214	1	181	\\x5694614ba6113659afbb8a41fdafffa421271b2f8a1eb64bf835c53686f7c9f8e605a63ead17651ee8e9c6bc64fec4bfb444dd48d4efbc7125dba6b819d99701
215	1	422	\\x351ebd82a07179e3e622a83c1790cc6d94f3debdaa695ba1581d26d1e42d4842ebfff6635bfd772db1ddb67d710150d5ee6e9f8b246cf098a8c07e7a26362f01
216	1	400	\\xe9c78138c1e2f71abda708298f02ac9b269974c846a0543332caf48058af5f7b69c8fb843459e80723bef98326b4e3bf4c7dd5fdfbc4671d64f7716313186e0e
217	1	322	\\x976574cb4fa897ec8e38e2e8556834b5b17456e5bdb6e6055937a77cb40b1224bac69ccfeaea8726f1c6d71f8bf33228b61936708462d6b8439b16d291c8e706
218	1	2	\\xed16004399d4c14c43667c1383a56b91106689862f51ae36c97e81f0b42e2b9f2d81783450793d201668b63ca4b87d1dc5d5dbe6caa408bfb1ea3f2c9da4e207
219	1	310	\\xb0d583f7605dccc5d0eec7778aede746988fcbdd95275b12370e0ddc572ed2bcc90a7ee2b88043fe7bd2ed4bbf9d9ebb019043e66e97044cf7a59dd770bf6c0f
220	1	414	\\xcfa7f8832fc5cc5d51f8dbca91125d962f184444ac5e4df1156bf0c149383cc43689257e45c5eb10734744179cee0491d09268bb993bb8eab881b6fcf7197200
221	1	122	\\x65d2db69bbb42098b47f6ecd70ead2c68ee190219172dab40a54c8878746321b762db46635cd078a0fab057eb694dae2d8846aeb942022073e0acb15f2ff8c0f
222	1	292	\\xd14d2891399f14be0da1b63ba9c37ea998cc778d7e7f091244b4c3f5e10defa0e257bd4926f1ff26681fe35ae305b73d9e496fc4ce54cd54f222fa94a8f97b0d
223	1	236	\\x10970028ffc7aa05cb47406cc2369e24bb0a2b326c13fbb1dd06fe1fda1113ae860034be3656a880a4837ba220b0750f14d20dc04b26398278bfe7a79f72e100
224	1	222	\\x0764265684afaa2345da3f9155a7260e0f631975176c99aa075178420381c0f2f33754bdc674ec4a7a9ea54f3e25d4a6f199360af0179dbb69a54ce9cd332a0a
225	1	79	\\x2796b74c267869c6e006ed75e8ceef5d0afd84b831d4ed00f9af814014bfd498e73de365a480b53c66636947fe74aa78dd6129cc7dbbf0aa7763deb8d4f1b10a
226	1	380	\\x9d5e25b661ae49b58a070dea9bef680397c1f961bffee2d4c5c02236af93f07903bcfb3556ab73a59f2d5ce3d9038c4fc4cc86b4ccbfc37a6014f7850a279705
227	1	20	\\xd9020b51cce1850e27cb29e8a531a4eb44dc798095bd04f4e4c1e45dcb6f46a580c1b3688b014608dbd35f89f33ddf7e0d2083834fbe11c476fed00ef240a60d
228	1	24	\\xd4a172715cc9ab567faa092c121c4b7d34c2b24754287c4bc9d65812e53aa25a5123e99ac0891be71afa7114ab554d81a886767b33b6937ab00a82023dbbf705
229	1	25	\\x105ec179084eb5a9acd9b884a9b088ec6bd8e2eeac4fb45ad7cb969c9f6da0e0e6429cf959254ff38e9705f23f6eaea26715f4967a2b3997ec7b907c3480c00a
230	1	169	\\x134efd006c031ed908ee98f42fc970cb6e132be18f34b5ea5b1a4f00ffb8358d9a201618ba5bdac7a93bf53608d9a47d3b5939e7cec0eaace8d0cf3a41dab90e
231	1	125	\\x482bf67cd96bd6d025056d053b97a8030e2e338bcae830ed676881d42d46f58f3abf3aa93ecf14ac4e4274737381a5ba70b8a167ccca1c5bb7da59e003dc5d0e
232	1	184	\\x6dc89f335f38397b3c8465a782a1696952442ddf205103ccec03b620de89ccd7c9f81c889cc08edebf21afa1c1af633d8cb8e32fca80ba4eb406db2b9eebff0e
233	1	60	\\x0a2bc01e238735f0b48b54775f39b66a55d50a448e5718804649547bf3abe9e45b10e35345243f4ba7c2ac90db694117e61fcdf34a306ff88a09b55fb3b9d802
234	1	105	\\x056250cf36766a2506975463bd10139b7846d51fbf05e4902046763eefb7a5f80c5fba152405d07f89ac166abcd7c8b5d9270f61f7e7e6832f915955ce184201
235	1	407	\\x27ca3a5b0da38f438937e990968f9fdaa6426a3f804ccd49a1e2c7b1008e5a98c4647053d67ab30a7c2bed024126aeebb788d7e42948682f703ebdd1398e290a
236	1	268	\\xf3805ff3c7b4af7d582d1eb65ae63df5776c1e23028698394e94b455df172948f5a0b593d4b04e4bf80af0ad18a1d1227faae301698adbc77def90a76351e407
237	1	363	\\xcd8d91076a6a8108592a9a834f15e0b68016699f56c03c2b13991fe21acf76195a65633762b7740cb4cf24c5fefa311f45ecd5ac0d045de7b406c17b195b8c03
238	1	320	\\x5edd39e5e2e073e2b6e6cb604398c9cfacaa381356c65f6237b17f86a62ae2d71d855e06f477379e80b98f46acce96c8175b3e50be55625e8a4dda54dd9a9b06
239	1	127	\\x1017497d3df5e3f5c27541deff84b2390da3e07fd242e5cf8d1cba611e19f63251b94f2f8a1f094a9535a29c4a78cd06d156b9854abae420ede16c0833456008
240	1	212	\\x13d6db26a98dfb22d99310d08bdfe5339554c24f3e35deeacb38a88a955092a6680d9f5944b4022bfb2e4991ac87b01f19c05e3486970fc290ae58a04f6d170d
241	1	44	\\x7b8e9b0ba7c087a8e5074334f0508d6a3be8c7835d0a73e5f51a856e8053615bd6d31076eb179d6fa4f21866f8bf3a9639145e10f9a83d4828f38e9db0a6ce06
242	1	376	\\x719fdd91066f41f5607db1b380a9c491e35f8f818cc873eb12fdbcd0f5f0e5a468bc6d2582949ac35532d2e4a2d54ad92f4115c6107ad2eed57bfae6cfae3000
243	1	270	\\xab9b8be8e6167f6676b417bdbd9dbf165f333c935e72fc86bb1fab170a582b9ce51fe9ddb1859e3945eb0a5bc1d2dc6d8cbc020ca69ed70adf3a437a3d2b6a03
244	1	34	\\x00de7aa5d770df3461a1c484120fa986bb90d5b21d858f96cd0264ace64ae2f79e04e5c8139a78f67fc551cc31e8d348d9694b808c2367421a6887980826f601
245	1	356	\\x13106761aaecfc8733355f9b87f40fd28c042dc92d255c7e35baddfb87f2e055d4249d46204432af54fd2398e8f95e95ef5fd7b5dc3ef7c0af1ae55cfd5fe100
246	1	421	\\xa45836cdb23c1be47956e25ac1f63cd52f581afed02b9c39e73c146ff61324c27e2018fa274caf039d5a4a21ce050ec643b511c39f4a762b34c0fe385e67d709
247	1	216	\\x2e01e54cb7ef75405715411337e240430b5c0639f7e84e41c93719415858e41b6b033d3c1e3dea91c316f1a86e8dfebc0600b07920711f5239e7b38f48955204
248	1	416	\\x3744a59824d186d5b19f02049b5d528d9cb516f4b23552ba9f564217f4dd4d8fc5940447d600332fc8e7a417068ab5bfe31959e5bfb289471e700dde61c9ea0a
249	1	28	\\x2ad070a9c7a90ed7fd11c4caa44da424a8b65e83bc657f18e7c3c4a9efa39b8ee1859b0d16de852d7dbc8e3feb0767df4fc6aded99a426a4453fdb81d1658806
250	1	81	\\xdd1afe86450b4c54e1cdea8b66c27030570b317450d2fda4816a395ec2e8d01f6aa3c736e5d44e9866684f08ba56f46932c1fed756d32b37725f484b62134606
251	1	255	\\xc43dcb64a18baa0ad715c76d3b1d9ba6d1bfa74ce5800960d632307592620a3ce4bbd8737fc7d3b6e8a78d759c96241a2165efd892b5a2483da2ff8fe0f6f804
252	1	312	\\x7ef273eea575034d20e7c1530d4412f5ca56b60f8aac58d9d43e7329f5adea30ed92209d7724e3852351c1e544064fcf1d1a93ac55719f32caef611a6fdaf406
253	1	98	\\x314ae516756ca7e125bf7ff06974f02b2a9901905cefe29b62004b7cd0a2db16926e8acda6e27b5a39cd2d9d7e052b3bfc58dd2c46c9efab79392363ad1a8d03
254	1	275	\\xf7669dc9ef9360558c7473704e4b098de9394a6333593c477e768222230e67c640f36b9833b2a9f39db405073c454df86b6e6a2ae6ea0f0d7ad2adeb77fb7805
255	1	180	\\x8d29320c66f85def39af0676c883613f92ccc86541363fa4673fc7d4420ab36105914bfaef590516011cd0eaaa0973fc8dfb1872d6cf3d4a212b6bf71904ab07
256	1	32	\\x8b30fc40d4f6bc1c12b13bc16f1e182cf614105218190c1a51e57e7d973fc5e24ec6543517e33d0f28c8abfd6bd0a60f8b2419ded2e9439f44e6c0b3ecd32507
257	1	354	\\x41c67af67db5f85b2ea6eaba0b27ebdc036574364124862dcfe9009e838e9fcc765b23c75748b7ea89716feaada73d27a7b16b1814aac5bbd4c59c5268028100
258	1	239	\\xae7f6fd186e4d72c2ed21fbd490fee18e90dd92bc561bc9fa0bf5ef103e8ad53d8048d671bfe12b21e50921c8b5835cf539d8ae13b5393033961ad4db693e400
259	1	352	\\x3aca6c75458fb54597d91679f31ba23ffaf00c53ae960556e1a6dc1c9af977904720e9f43ac7b239d145a1d1d70fea0fad88a6dfed3f0ff805476ea18f22ff00
260	1	398	\\x5f54afdf9d23ea32da73a9997492db8bf1181ba598f67811fc49a6399d03735a413a7ab24fbbbc163e34895824ee25e39fee7390dc3c169c88e721df1e862805
261	1	146	\\x0828d3af3a89d355f88b46fc1ccbc80de943452996cf4f98ef2912616bad2c034ad25b2d5764b3316de23e60798d80e6d3260ae1fd33f8860f736bbe79faa305
262	1	258	\\x1e688a57991cda960cef06daeb6a4149c9ab198fadcafc599fd97f4e47abd1123bc6f914de6b8b1cd4f62a17de8830b9d6bc887e1a8eb3a312c8eb0d1b597f03
263	1	52	\\x2b2226158d271634d42ce874702ddf41688fcf9d1e632f65dd38ccb7b613abbd2997e35ebb4c50ccb2d9cf3828b077ba36c0ee0957e657cebb5e111ba45a9409
264	1	74	\\x63ca3568b3e07972a146fbf6674ae3e6b6f9f0dced054b9f2ad6b420829463339588a890c6e3d2bbb5ad782df7b00ae85f33c1e1adaa850717e3a2ffd435440d
265	1	299	\\x741747700a3ae89529564d46df7063ceba47e7232ce293fc31455351c1834e885535dae10e05cc67de8ad9385adbdce19966caf81fbad371fe8ceb1f38f3a10e
266	1	123	\\x9d093eb9dfa01c6308d3af43e1e516744c226a730c8494ef087e51d0342acafa14feb3706f702559c88eac292cbf5f718f353f3e83f248be8f31800a22b6d40b
267	1	266	\\x5d26a3c0efa97eff1fac8d89ab74da0a3db6bcaa672c0009c6bee4360f499f80aa65f9fc80e25b1cdf77af53f198f22d7a825d3b6ff3a812be7b44198d077c0d
268	1	264	\\x7b00438c8b4ff59d92b9efbe8924b7d3a58b578294ab1fc60719d3fc68a784228db02cc72ddea0bc3b13e9a15d9bfe5377a3e6ceb00ee18f7a2d56d1a74eb507
269	1	306	\\xe333d74481681f0ada17d36e17e0b6993e6062932b3102a7285233070391fa61a856bc02110f0305b28e9a2041f3c4f412340dd7d95ffa855d3d8f5e8d191b08
270	1	171	\\x2563f89798080b2e54346948e66cbd9135c01b1be475fd087e0c3723dbea099e0b525f72dabc1010e173a5d51186215c2dfc6d8703b79c69f4a4f48f9a62a10b
271	1	359	\\x7bd2eab00ab4e83637cd89d1ca7ffe039c19c41c275b5702e64f386fdb8224e963696db6a1dbd3596d0247dd3d3f94d8c73df12547080b5a1146f5c013348104
272	1	153	\\xec0d4848b83df2f26a28df83041c10f1aa872914a265bf9f3c07b50db0204f9d41d107d10130d13c615df7691089d95c90b949338f8404427d5e5668999e0400
273	1	412	\\xe12875944720443c8d7f597485a6eecb48d028c5c15b464eb64a24357e085e8bd1ca301bd64fb0fa118000c3e5ca38eaa317fefb1502629985919bd30f39e70b
274	1	388	\\x45679d3f12407d0a1e5ba89af4cb429b3f30684a7bdc4fda02193db85c5a6b139b91fe4012bbe1e37772bf936c21764df246088717643f7a8daf47b8ed23060a
275	1	245	\\x3f9028bbb719b309083161c67cbd541df7c51fd34bbcb12e5886e184f381310f574a0e672884effecf273002bc08182e4c9de1e4e3464be493d60e7d8f74bf07
276	1	401	\\x5812c8ddbe78bfc8c510ec9f65a0c17224202375674bcf47d8af0a7498ae7578abb5272c15bf6d980943e40e232cef278e36714bb0b9fa7c8b961536db93f802
277	1	86	\\xe730c59bca7bceeb87e9a392831582e3edce2f43f186616c704f1ceba062aa1fed06be977bbd03c5ed92dedf32b982090014fd9bc1f10034359252cd5d0d6e0b
278	1	334	\\x54bdbcf666fdaf90278be508291b8a705dc95f0b0a57dbb47d87ba6b951170bccd34e81da4e54759edf5f7785a26a3a7db436a658faee9280132f60cd930800f
279	1	213	\\x0429650ed3877ea2d88c9c27ff2bc8bfac760303f263696fdb7678168e2326b8710c2650a49e7bda705365f5090b499c932e28d9bc80be15980635f5b3b82201
280	1	22	\\x2f6aefe4d8f83c61528eba3e459bb6a201cdf6575a46878e45b041fc31d360b582627d1c80801d197b63ee7c361940355ed23856a64c66c707c1ff9fc1e7c102
281	1	201	\\x17660d6e2822f56b160849c4c3d7cc4fe41686c6b1652353b824a8246e90218d0bcb4dda005bb076e4828d6abe7ea0b6bfc56f1a847266ca3c86bb115440940e
282	1	145	\\x3ee7a20b9328b9d1033daa2afe8bf629a5af1dccbde6925b51b166e9e59df61d31c15ed7aaf73d67c62586a9d4c2fb02cfad16ff06326aab9d9d1bfe8473a60c
283	1	349	\\x8b53fc58235654054893a114766ad266fa6390d5af0ca3222704b44ee4570413615b383a326240d708a3f5691000df36f7dacdec976b9d2ba59af86f73dbe802
284	1	150	\\xceaf64781cc444db39289d9ed755994b8846da2935f6910ea38c298a5d71e7b54cefadb9bad50ea87f26d7b0d1e18c5588c957ff6dd33d2275633e966a7d150d
285	1	124	\\x509f326f6ec71d233b65c5fd02c84fd1cf5d119bdf5ee5ec6ce969277237371c456296c0d770abc9c79399e87c340b939dc2d99b90101d3f2e910acc02ab1205
286	1	295	\\xc968cc02ee32dca22f087332fc4cfa7a501c5b91d42d1d4ce4770455d5d7836edb10fb9a9faa2ac4b46ff319788029ada6fec4b762992a6d3302720d4f693f0a
287	1	250	\\x6a3de62c3be9b7d1765536a21b4cbe63dbe3d6195190d140c09373b1007c4b3dff5412ca484bfbec698601bfea57c0d6d32ac7b46da43a9ff303eb0085553d08
288	1	263	\\xd92a5d42d6d14c42e602839b9cea19e1a397c2b6546dd04ea58122cb92003adf29c7f02f3313cdeda8aeb26755c5cd4a67f051744cd99027e2e75122e7bd4c0e
289	1	48	\\x0cdb83313a213d06fbe571810ec4ea32ebc6766d05c1f6f6071f8a006e21445835211572ebbe48a563226674d32ab04173db6c1735c13ec6b8a01093cfbe7e08
290	1	283	\\xb2deab4cbaaa2b8445c9f1a7a0955020a7c3b97015f7ba5e605b0052b2f03e81de52c3aa9292b68b72e40e9280ffd19ae752ca633a802218fafc37e39e716d0e
291	1	272	\\xc0cdfd02467e8a59738c5738929300d9a2608bf7886f84e0ab7af33d1e924dc487b27ad496d86be9004795c9d2a7057d7a6bc791fe38b1f9562351c2d856ea0a
292	1	282	\\x46c5695edc3accf258f0cf8d8e0aec03220ade24de922438ec38aa9d7a5b999df038fdb3824ad69841671640ef270203e98874a5986437f563b015a31b046004
293	1	15	\\xdc6a5a22e775dde892ace7924039c506d1ba322b81adfbff9fa90ce9a8f8c94536eede6dcb0d16142026d824f8e33baf65e50bd5d365dc5c9118ebf4d5877a06
294	1	218	\\x302a75a14afc7972503cc349f0df3d156845eab897a62b7f7b4b52b408fa840c228f1777ff5df090364fdf7a86126ed74ff2ece73d328427a443bc411612bf01
295	1	89	\\x9e00d39ab741eb536cbd03328ed7ef6e17860e04572660017cc8ed8cecf1bb6a2ded14a07576396fee4ea409e84e14ae780ff307639bc74e777fb4e3bd38b00e
296	1	175	\\x92b0d60b4e43b9cd2c075be0d79a1fc0da611d7f71cb2b52214520f478cbbf2e556b5e691378dba2aa404287e1a067a369de8a6e998d3bdbb2fe61778607d30b
297	1	227	\\x4e597a8485e88ea08b1b2f1aff6597c3a4ed5c55f0e2bc11abe1c5260b549d4cb73a38cf1d2619fa9a9bfcdd1d2a79297c04c6a30dab4ff7a0cfc44694fb4c02
298	1	341	\\xb5d33c698f95080843aa0085b3b312fc7dce1924a62005e6bb621e80f25deef40abac4f063dd21ef460b48bf11b34ba4b2c081c3ea4186cd1a3d5db57295f50b
299	1	288	\\xf7e79c4adb99f32138bcd3b10dd469b873807196a89cfbf74fe513ef26e263b6792df7600f0d4fdce4023480f64b994a06f01b57db78f22552d50a720e4f0709
300	1	345	\\x81a290c12351f16edb4cbfb98dbc2b05a6f7be2217b36df28c5ed5dabb8fa27f7f208c17a71c10a7267772dff53cbb3e2f2fa33b977c7139f92ab574852b9b00
301	1	106	\\x11da9141a2f89bdd75ba110dca97dff10be765115793cf118a20f3f0fdb2e7ddcd687053ae9e05ae84aed87b03991a038e7a944cd3928fcbece33097b5197f05
302	1	253	\\x6c32a85fe93579fa3fe9561a138492f3dca94dd69e8006e513eb82202babe6f5c2efce3300e5f0ef6d2e4f435b218d90a18dfd3b1c162310415ceae9e9c3ee0b
303	1	254	\\x113fd36785c2f0d2a5eca25205af91deb61a7e8cb4c3e81e6ca3eafa201953ca427913c120078dae5f02bca325f4842e9158d77032e5c6e3bffa2262f533490b
304	1	411	\\x4ae78effa6600c780ef1cf20e69e20034d7a08cb8bc31168b5ebe353d4a2bb94d5d6904888572128262a05a8f2e8688556920a46020213271a5b24a8c078ae0d
305	1	298	\\x74a9c267573d34bfa5ceca392149b7694b2658f390239721181e7a7943827360490bb7187dea129f5f543d76f2180dd85c871f4535a8ec36cb021c121ba1c903
306	1	378	\\xa62dfb2cfd4a25554c52631025c31abb322159039cf932891bcbe12ed25a60e6724c08812b18bcd6ae4b1eadb830055803ec70176d01ab0793b72a7642ed7607
307	1	57	\\x04e6a7c9e559fc57ba882dc66f560c08ba625e2c0628481b76cb38f628a9bd1ac6ace77e00b6607068d62e741cbb518b6a9465e19d0cb58378540d319ce7ca0b
308	1	195	\\x61611b5efd09a6569d7dd717590d294e9888f92e1b7982cf196236722ea2c847b3f6d8014119874f985f30d1676eccba5e8a38b73dde860c5d464e0d403d6d03
309	1	274	\\x580f517537c498b7b059e34a05bb7ce2135e76a59c5b7c0d33e3e9b06131f450f6e59987891b3cd4167c020c74efcd193fcdb8c0818e788ba1c77ac31d68ff07
310	1	147	\\x0482b4e8599aaed7f57946e2e0f8153cab2b944128455764bb3da8baa3306551e969d89dd32db44443bb3c9b00f6dcd939f3cf2b87e19dac569a98331f5df30c
311	1	203	\\xd83ac264a9d3fbb69880b8cb0ef7dbca1a763cc6c29a5fd82784ff84c43c5baffc6b7a42a8833f349cc2548f95c869bc7bd0e9bbb76eb00c671365ec002ed20a
312	1	47	\\xcd267fb0a26e8f37357872bbef6c994779355e308465c26aeaeebb3b921b349c116064beab3edcbc6ace5590bd995071e07444e271cb130a26f9224d9f5a4c0a
313	1	332	\\xafd365c03600bc9a42371117249c8bd59be51b28c9b4728fbc767e40dee4e17c05b1c6ed9722d78061c4a5acd888b79a7b8d68716ce995856d93bc362cbabf05
314	1	226	\\xc9c5efcf53773bd23f5f8e61822af0a21b8e49a28d40ac988a03f7341382411f580ab9242037df49707a94b809237f2478d02c64c02921468c64a740882fc10f
315	1	319	\\xb68cb5312e14d4faae88543bbe03a143cd75bcbf5c8ec6c49a7d2c4086d05e02382313f05fbd3970ea2677cea70ce5dcc4b5fd6d10d2f579bdcac8c2c7c91b05
316	1	160	\\x03bd2c4375518be585297256ccbb312a203fc671da5c1ce10358ef57608d624e5dd316179e4184ad6cb0657fdd50d47207e3e468dd53da50e6ed501505a33f0c
317	1	8	\\x6f1b051cf4b7ee8d694d59888030ef7d7398801d173a7868f67f913a98d0f6167e44312bab73713db5f8e3f5a4d248ccbfed0b3d508cdbea56e847ed782f9e06
318	1	189	\\x2dc2da392526faffb3b2372dd70a6c2df0f75f4fe70336fb9df37716e5f81d0021a3a7caacec65afe6ffab3ecf039800ebfe4ebb2333e71b96ca3a5f4ee4e40b
319	1	186	\\x6eb330af05a017a6cc3c19c1a6d6593617ea9e0946c1bf6245a43558066e1845354d3a1f77585495c674fa817b745f65f8d333763de52f3cbd904b893ba8b308
320	1	194	\\x6a9cd63fc0f3550425736acce9dc153252480009be196df00287a4736ef2a09729e230e6f99432c787dfcd237a8fc9e366edd6881527e509225202eb5b7abc01
321	1	38	\\xb83f3290f7eb90b0461d045ed921900aa59cdfc08792976f6aba221ab162f2d45db7cd32c1d3bdfc626007daa92db2f6396ef6b4126367750414a843c3fa4d0d
322	1	238	\\xfd05ad3c931a73e12f187b36ddc13cfef36a8f802ff333607df0bf6a8fd09c9b56cf55cd606048ea86258ac84ef86e420d2ff728d54e47c7d3d73aca70e48602
323	1	208	\\x7795f519b414fecb2ed872c0d15996777dfc51db3dd141f72e471eb6e84c81a6b5221960019081f930e29ec4b69a96049202bc09cb745f58d19e48a9b537fb08
324	1	327	\\xcc65001ddddf732099a751e4762947856d03ea114ffeb43649357b84362dc734699d9195766aa1f4bf064b81159010ca07504a5ce5a75debcd7fce42607d6807
325	1	26	\\x01b46a04f5872045a92680b04724cfea33e6092cbbfe05966b5562ad5a1842955bef889c08b8a6bedb0a8a4122a107d061c41dee903558392996d763d3887a0a
326	1	132	\\x4405fbc8d997d1a0d2ee1b30ab3d2314d4669bf0e1539141c5c0435b0ecc4471e59ea88ebbf79ed45a91edde510a25566b636be5e3a81bb527641a293fa2ca0a
327	1	77	\\x727eae7152a8caf03ec3a6d3c1583f2e24c9406504e15a8ad9b95ffd97a770a32b782cf88e83d210523b73796a02cd4d38304b4864dfaa6f382c264ce0b2450a
328	1	185	\\x112a355a4c5e2dd36cd243c1a6d1b7e515f4d2c3787686b94d4bfa9224c9c2c0dcc1d45e3df991b10dda2038929021444538d93705d4e31f143bdffc344fe003
329	1	11	\\xcf77a22971427b0f875afdd1065c23cc001e2491862e757ef74d9969bc395a5cf836fdd629c274d301ad7507dad466356a963a2d26bc9518dcd3423c4312ba06
330	1	120	\\x75610209233185802e44f7b51e5b20aa4deb8c8226aee1ce87acc8fdbf8563bca19ed406136e9350164335c150e094f2c40689e367c9f9db3b0a4c5696fa050b
331	1	136	\\xf014933bef228318e5f789578c45dc38e2cbfb64a2ade28ddab2ac3bea6fffc3b93b922b60b9bd698aa396cd6624eebefa1fee021157d0b4dbd8d949093f5809
332	1	355	\\x90bf69c91ed2875e4c5dc94dfaecde3a4d184c4cb878d863b8dda3fdbdd804a6167984933f8e20a4a3dc502bb3b858c9e85f35272f0cc0e6365ef5fb2303fc0f
333	1	135	\\x4963519f27879137f3dcd7506550f1e709479f52460cf9d0fa14b2acff4a77a5c96a2595f29b37d054f2856077ea294a5fcff1cbfaf322c3a26dc5e1b26fc10a
334	1	51	\\x64b271510b097658545bff2b5c3a57f3fcf5e9ca76364fc20dcb2e17af789e5c994ed9e12c776f0600a1c2e5ce4087dc475851d5de60296c35f365412f493505
335	1	3	\\x0a208204bd11cf3df94f263f576a3fb34faa0911ce83ac6b2f7a1529503a0e957d7c6b4f2c175eae1685aa92b4bec6e9ddc019a82273698a705eac1e4c3b5501
336	1	37	\\x572eb5ff381164af51126d5e4a4f9f7c97eda31b3182b38394f9b0e82ae6b401c04a9034e19863cd66e6ad02a63d6ca839822d0f4c82034ed729b98c132e9701
337	1	237	\\x5d5df848f81a7c1bfc2145930c032b2368d1f9019f31c30bb184e672c464bdba544261181365c1834e1ea298ee478db58c6676947d36ee77130f050f87455100
338	1	415	\\xe15ff8b845abdef69b5e263e1f0f680d82df7137ad3ccce31b364cf01b5f93f5a8551d75936b174bee26524801ea46764e760ec8aede12bb6a80f21a3e143e0e
339	1	69	\\xf27332ea8f76b9b06ccc71e56f4c64fdc5c67693f1e60eeee39a5fb0486414f91fa6517bd09d589c89e3a13153b365f398dcd971bed0cbe0b70d6057365bb207
340	1	75	\\xfce3ef9f539f98c983eb81978850b22a86b6984157fd897ed3ee206ccc535f678ad2a0ee0d7022bf57a32bb0a64c78fc88f910c0327e611d63a2840e28713706
341	1	62	\\x91ed34cd127fd7d9a198bc2545e04099571f94c0137da01a5bac7a030adf0ac3085bb4aa84a3248379f48b00b9f226732c2cd21890c59d3d04f1077daf23c80d
342	1	133	\\x23a2d45dcf4f4c2b1b735bf0690d0377f0ef9740323d278b958400de98e184f16eae9af78856df901a09957d4c4218479fd32420f16ec3b9003eaac42a5a1908
343	1	337	\\x7b31326a3eeb283504b1e4adf32aeaecfa3ba53e4e14ec50612176acdecc7b20898261b8bde61d3f7378fc538051d03b236f6f54e65062048d4c33e2650e990c
344	1	19	\\xdda08a4b3ceb639e83cc80a929e3bfc22ecc8c95ae83a99e39bd64c92a7a0ee1c84f4372211d6b25c7759c009cf157fafff7de415c6fe9460bfc52df0119df00
345	1	383	\\x67097bed92df92d86e722450ab76cf7dfda17c3e04adbe92b712f63f95f45ce0b54b3ddc4a670edfe39d2850d98a5a29ed81885c17f28ced66d2ee5d8afe7506
346	1	131	\\x16a892d8ef4747c32ff8ba19948d93c68b8c49d8bd6d3a07205950ae63679a0aebfd4189c44cdbc26895228de1ad70da624ba3e20621b38e2ff8f33735648b01
347	1	5	\\xc862762b4780addfd86327cf55e42e1ba50eecd47d68599d9d3390cb0285b2c6a26c7638405ecbb167021db18b8f72906d309312b3d55289f7a460c4e2842e0a
348	1	230	\\xfc5efaec0277f6f368a6748c778e017c60187e327c7f6a536e857bfe83c7814f0736ef212740851ef11056c00900ddcd9a4a781e518eeb98f3387284a20ccc0c
349	1	49	\\x2b8a7736d4941aadafdd5f758db7a0e6e6a3fcc8a13564f8e3b1dc86f6dac3f73c72f37270ac12c7a920b82e190d83ee2414d29269907e5e6eaef8ca9751b80d
350	1	324	\\x790391848de3e9b8800204fc69445ee229dd6e6cb3382c249bf936441c5d4554ee3496d2bb3353d18d62ee91ad66fe1c63a73ab5a16f7c86d95d6ffb0ee5eb09
351	1	67	\\x64bc0b741d77da387cc954e2dc6d3ef5b8e8e486fcf48fceb2407aecf237dee04851ea7b9a0d0f36521b89cf99d74416b694f4c3a401845213e9d80d5c5ddd0f
352	1	251	\\x72e221557908fc3b3776d89c9b8f6ad9e7d5625860355411cfa20393213e14b2b0bbe642b7e93eed5258de893ab76933f4142da4e6407c3f812752b4b2520500
353	1	244	\\x92a95dafc13e8ab02791aadc65c942f7fe90188ba856b77f77048e7b2e11892bc30bef997e595756f3f0dd0659f4b46ccbe7bfc6d4b6b3eccf074a3c31129d06
354	1	190	\\x6d65d0e5bcbddb3c993f0575fdeee96d9fd9008172ffbecd83bebce1809f2e6d9c86d71a9bcd265b931e2264ec2d229d3cc9984f571d64d05cb2a0303df44f02
355	1	224	\\x6981c0fce079d0b74485fd20bf85f6fcddaa4ed29430f0fda705d5b5d68d2627f835bb4373197b779260832c0563cb20be6c40e864fd106fc1ab0388c4eea90f
356	1	90	\\xd8e609baae83857468e378053be661244d351e72342891059dff89b3a1e0923f565a7726df93f29bed0923ed970d9e83d4dbb4281d96193c9bcaec7083ca4702
357	1	382	\\x0d1d3bb72c7b2bd6c61496878c2f5e82b012ed66a79cf2d414677d18c39b9cd67659d0898ffa8e4bd1f3119d740d77be35d1dda76896099d65e65aa12d799d00
358	1	358	\\x27dc2323331e355b16e93e2cbadee8542d25544ae03d3995eb4e0aefa8fa73effb54fb685bf048960b51d6c9a75298f7ac49cc07603ec963b3f21cb36ed0280a
359	1	18	\\xf4d72edb648cb017624adf35ecee97784ba7e371863daa92b662c298ad15a9dd5ecd0b53e81434a92673c4f4e6c8ac5753648e282bf93337400f809645609003
360	1	342	\\xaedd3426d18e5891c7515f2fc25eb6e0c155f8325cddefc6ca93e1bbbefa11e8e1fc2c3da68b74a27091137545d365fbe219161b5970fa2a9492f0e1aaa49108
361	1	280	\\x4e0458cee3458368899ff746dee0eecca23d022d05a38c82b61efaa3551923c04fb9989d2d558791787c299e3efccd625423e574e8e959e83f42ae2d9d7dbb05
362	1	209	\\xc7581b4f2ec7c46de1143dcb051dc90afe492c4e40228846ea22ec216b2384960d2fc9468351aadafc5384b2b843a595c84cb6f3086f6bdf879cbc7364e49207
363	1	248	\\x3c4146f01e228c6a0dac358620dec5f7d7ce861e12e10536e5f785011e5bcba78927f703aa914b47240ae9f0a0bdf207430df374da18959420c611f9ceafb004
364	1	232	\\x3c9028a8c59de3bbb8d77384e0133fcc5bf74f5a1913a3dbd38ec729aff9851841041405ae84edbac860e6f4c63d9e5ecf4a7efd4deb5ed95ac1ec3966640d08
365	1	30	\\x7ac360f17142dcfeb5e1c001a511f02488703b0813fda664bc6988d7bfdb6d22bc7299ec81b30626a83a467918921c754a722454bef17c8002f23462ccf72204
366	1	234	\\xa8b1ca363d6f1ab153aa487e07dc961ef3c4d9cbcfcb6ebd8855521f92359eed400c4de18cc8d8b725ecefbb47275cebda464b8b62ff869a55586acbc131ce05
367	1	176	\\x9c31de0818be4ddcc956224365c73b39aa947e10bb2fc1c42ba47e156b02e6b1ccdd61a6c34f8f5807e6d2dc97ec9911265456cae06611c377629dc398a7f004
368	1	293	\\x29b71cacacb3ed9bcd5c1dcd6d55431a504bacb38562d8fb53a8a76b80f386a5c3bf6ee9b616301247ed1723db0eda068d48304f6ecdec8da15fbadcddf0920b
369	1	4	\\xb08c0cfa8271824cd181c8f434f8035c69b4a388165c6848e4bc6096ed9765cf85da3a96b73c8009edadebc5c90e920431d9abaae4ad4eb85b37a9544f297708
370	1	269	\\xc3b426a3c6ac08caaccad1b5f6c71debd9cefb0ce6ccbf5c1dc22188d29aa1017d53a3535475683e881bdc2a2ca0a2ddae7a93ffa22415bb43ff59587da0e402
371	1	279	\\xf2ae2024da83c7ef6cac5bee035eb810dc765419b02c329d2e5680c040e7745da84e0db59741cd1ece50964cb4c0e4b75f1141f1fbc8eb2b49154e603a46b20d
372	1	402	\\xdeae9cf38b8e6c0f7662a76802f639d106e3a34b41d50d979ef4d782b3bf7edff5dcf10b52b4bef6d1bbbf2aff99b3469ad18176f4d247fc7c9072a0310ad30b
373	1	408	\\x4274f4cf3e4b2f20846171e7d8f06c65b1f614f9f5d0f3677f6397067850cd63ce688ff14a46a488f88c38fd3a2ea0c263d4cf747cb2d1d64696be0ebe65db0c
374	1	273	\\x21bf9a8918ad9d8afbd390696d423d365b12a435736658af5d229af5e7ef16493a2b69200cc0d86f643ce686345aeb3523ed8da21616202842232f03843d0905
375	1	58	\\x86b7a5b11bcf22d7c22363f82c9d2f6f75d50baca6f37b90678bd672387f42c6f3c02494b64666199450683912e0e5794310f9c3ef8015e81154a72a6508080c
376	1	202	\\x3230250ddc401794fc751d7b84db984421649e97361fcd068ec136bcaecf366a316394af567420b922438749c632f26527522d03e027d9f3d32052fa08ebd803
377	1	71	\\xe57dee1a98df245996711d5558c7ab48ffa816e3783122502c84d2fc9cd1925aaf123661724819939f7ee54c49c80b77920a7d274d9e78c02ea51211989e530f
378	1	158	\\x740ccdea1b09f480a60ef669d9e57977e9daafb102f788b7577aac50970c03000ff20d96f36099a29dcddd60e316e371ee984efcf4c7e16872271b7cda6f9e0d
379	1	157	\\x647756c4a85b2aae48ffbbf7a77488d9a696f688b70880bd646859ffd4c0aae98adf66e38418940e0daafdc1a3600eba9c5f358c244e88fc3950d9cdfd64b200
380	1	261	\\xe828df3e9119996cde591b8d9c0c6fcb3870be3e56fec06e5f9fc731c23a91b92766f36aa1a1516936606168f25478c39b4cf8ee514a3df143e8409fd5802a02
381	1	395	\\x6a53444aae39d5d6ba89aea1680a2dd78fe2b47157d02bad3934d9bc0ed9aab12e889388c417b8ec58083bfb86afb2d12fbb0b1d946b3918b066d2a7638ce90e
382	1	366	\\xcf1fb4243e1d82e11dd412e581d13d251205cab6ae34c59846e38067b09cd2b8ed629ab326ae8ed4c3a1baf4848c7b8f13c5023393604548326a6f13226cab05
383	1	137	\\x805c14255d09e70bae4e71877d4e8dfb551e678a60021274c1702c30f2acc807028088adabaaa32a7061f77f270e5341c773ae5e3068de360ac9e69419261c0b
384	1	191	\\xbb52dce49b213903049a267be1435d4b4b99502f5620199d288dee306d930143dd78bd788759705ad00e6e405894195eec816cf5ec4d7cbe45e3029cd2a8ec0a
385	1	196	\\xde786c92480b32baaf86a918d478d6fe58d6bb950913180161c6b5366a788616a7a33686f95ba7a5c0c2e300f8249af5a51aa8e38242f64903a69f4d473fe703
386	1	12	\\xec82327f35e7486a9b558e1eca0169e60c3f9e33412873e4fe576253611b096a525091a9dc02f9e8e5f4d7dfef0c628c92983396b3dcb77244985b82b9aadd06
387	1	53	\\xc07905fdbaf655e9f2c1c92bc3bd9f4696ba6980ae1dc3a4a6f4aaba7c9beab020671cd4b3225fb70316d35893436c39dfe558fb272a5fd2d7bb1a7483f0bf07
388	1	162	\\x8d1e3f74fb4c975f2590c30495b1befc8037a0c49910dbfd87990ddde46d2e07ac3bd1830787a34b2a1860b33af56fe217c75ad23b8304e18ef85f75146cd205
389	1	210	\\x97118b3e9c90fa6da27dbecf6ee2de082f10c4ae8f09fd153ddc12ee1cea9601ccee34875b0bd555e58089e36b808a71f1c2d8376f78882b0620a2393dd98d03
390	1	161	\\xe9e9553f8845440d41381be0618e88216051b907058b6413f5ebcc0c31813f37f8f913c5008125a2f9e3a83f9f50bfa0f12cb374a099582aaf2824818b3cac05
391	1	394	\\x274e0b1e67e82002530f987e488888e9d54ab2d8ac8c62a0b43fe80e741e1d671581b399e08190cb03e58ce58fddf290a85baf977c57778f077f26472da65904
392	1	413	\\x8374a41992d3933c379327af5173fa3b99b792635fa83277d07cb69e3302e5de12083ce92108815932d8d1dce1c506fd8614a231b9eb7e67c866884f7efa0407
393	1	223	\\x211f66fe3e0d2db7f10b2f145f7d115d5210eeae28a7d881aebc8524edd9b4e7c17031cb8c6aea48aea6581c30d4381dc5a3e5526b0ad1ec4f3772e31b6cfd07
394	1	235	\\xc291c44f55b662d3032dbec80dd7b7dd414f06c408cc357de4eaba90e47f7675433c79f68befb838900a0beb95951e2d34421f5371b2a77b330545f143b72b06
395	1	379	\\x3a465aa9bd4f223c3d5c24bccc429389ea6effb6f87bbacdbe4e6afca569c557c375c756ab59a8aa2558f7b8898bb090053e5f248b18f03fc5f4eca2270ee104
396	1	409	\\xaa57083a81ad62f4545758d2ad672ea4265f82c5fd95ea640e5ef9ea1c4c6b5d0c2e28564a3a6e15a26bddf68a3a2e975fbb87d49c44d2dcecb9b41cbaebba0d
397	1	78	\\xb81470fe1de843352da5ec7849fa728c330654289b651e9319f9e14e29c49ac24f8a61351cfab712d1a4a01c463979e27eaf8f406eaaf7948e581ae72296310d
398	1	309	\\x69d7a70fba1d4b3f1b5acea07056ed725b63f0248b2b9faf928e0fcf8c785ff2c514d9ca9d3911a75fadc3c3018584ee5760fdc6e89fe7874d774b56c0ef5704
399	1	6	\\xa7ebe7c1d7cbeda278eff055470a29cd7673087abf2d6c68e5d32bbca08a7647526a15141010dbfc81a9353763393e1c6daba6b4d323abfb959abfaf28bd450e
400	1	140	\\xcc519e4f1ddaecf404a6877ce446431aef0bd7b4cf6559a78395b754b3e216ff2f32bb4c012cfd63d57fc7ded1e69fa0509ee6b84b4bd05c78052a0326f4be06
401	1	102	\\xd757a62698fe4fdcf8f74d55d260dd4d403375aef19f2fd23e8a81b4697dbd9b58aa52b294cda10907b75a058f9cf36f3c936c4f8dfa96f4e1077cfcff0af60f
402	1	88	\\x99f172876b370eb5cd11b21a0257b8a34ccce0b2ca68a63497c6aa2b2e31f11ac4b65252553abed2e80ef1727229f1cca3862a76a7f030260867620a1920b50e
403	1	370	\\xd03db1c0a851ce026b05fcb2932e0fde549467358771d72cc87b4cc2a39cf1e748f0bfbc35791a54665a81822d4e172604274cacff0e086c23abcac4b05c1003
404	1	128	\\x5dfc959185872c2c3a688ee2a01fd586ae41ee294c5137f59fbe1638c2d580cf6a68088362293f747e846ca6816379cabfa4d68c0ee2b60665ee445f9f645e00
405	1	262	\\xe58c123d2ff0a9e395271435a41116c648cd20655ded2e18e8608f49d34e72faa5f997e26cc9cd03f96fea636784f8b3697e22dcc155286cea0790dcd6a61b0d
406	1	187	\\xcf8328086a12caf8755834a5f1947043cc91251f87cb147b18759c01195f9d4e0b7adf7b4728b9dc5d51e6252b21d8251d3b00356dae3c88360d3ead0327cf05
407	1	225	\\x279952c2df2ba09749fa435419e8a74b6e6baaaa9d6c0a72fc25c19a566c1acbfcbfad6171294ee28def5d8ed03fc33390eda3a7c631599b061c9300701adb00
408	1	260	\\x990362288fb59d82cfa7aaec41d3d35c7baaa7683956eecf54d3042e883b3613b2eec7df446782b04f4ee0a350fb6479fda2059dabfb2259907512a2b5851409
409	1	231	\\xbe05cff700574423750d115809cea65afc2dd795cbf98df33bdfd4fe11e232280214a83e8b4a06e2f04e3d97fa1ace7499aa27d3fb5eba110ea4df2564922e09
410	1	141	\\x8983f22fa481bf5eeee7ba5564607d9e9995ca2d3698584f614f642f25e7042646d128e941956ae401ac7edb8769a3225c941a8159e3b3ce84e67e36c254f406
411	1	21	\\x42da8bc99f5750483430ed3c5aa247377569f29e47f595eb796d33bb4ea7dbfe95e83fb119cfadaf7f17ddba349e5e52528bebb82ad9accdc8f696e2c397590c
412	1	300	\\x5f8adbeeeba340e81f76a3e6df33a1ca930f5633d797209a7b4d01a1fe961cab0fffadd187311b67de619cc93010489ab26147e297dcc750b6163d65c5afb203
413	1	278	\\xe8f33f4004bdd1109e52301f33fbd0f10c30626e2449a1e126cef551fbc115e929c4438fc0e979fab6829d4062e462f4fa564736791d355af0bf586fb380d50f
414	1	389	\\x918b4a1fe8c1a5650fc9f00568704feccb65b120e8821aeae4fe54e44db0640c43ae6118013e54cd71a4a8ed6b03cc84b68b9a5ee1a88bb59fd4a88518df8b02
415	1	396	\\x2700b86f7a354a51cbb211b722a0552ea2e09de4f14f50b2353d9a271539d7777ba3e25a805c7c1a81d55dc31e67d6f0cf8cb8d9024752f0c8321ead4a04400f
416	1	61	\\x769ce05c9ae4f69471be0c71452ea98270a8e80ce005916543ab0135e3b434084943c8d2b2ef65995e2bb22f014f0898910228643b472403bf9089422ae6e205
417	1	1	\\x36fdf03b0ca3760e3e6520307bcd93ebb62c7be7f05ffc2dd785cecbfef3c46d5b1b98058a140ce2d80ce8cab02709e35635d87d188f998bf26049c37aba1b02
418	1	197	\\x91d6ae19f168a2071b3db0a1b0dbf02db914ab4523f630f3dc83290d246a78e64b13b7a418cc9db79f7d8840f91fc90c86280b99a7f0a99cefc7c3bfb2fcf60b
419	1	113	\\xc4aa8f12821f61e52f6a1e94eaf9a3dce6db5ef1c2e73da8fd54aed158e6f8e44fc033c7a843b2f6a585550a9fd30e05847fa877dbef207684e56c335c3a0301
420	1	65	\\x5d8d984d6f94cf4458e0e7cd4b69d30da3aabbdd1b5718075fa41e6d891fe0a0b1ea07f3d671fb8111524980ae12f860bf0f79318937d41476c5afad986f2c08
421	1	110	\\x16eca6fda129292e83cc3baa3dc08e9b1655168a29f27be945900c018445d53a17e42ab6ba1ce7e69923f25d84f6a5333b6fb8412e12cdb6804f74772d89cc00
422	1	284	\\xe833a322a341b0fb048c956978853bd9a27c59f69bf112fa777d7c4d81c0123e77955983d2a77e2eabcedee8954d104cc06ca7434bf89e4b65b8aace720fd40e
423	1	316	\\x498f07dc07e45ab766fc6078860b172eade0cdea46d0683488c2414d2dac8a8015de21b6209365ae67ecb4497ba51cacb30910d6c80da9c5c55ae992d14a0503
424	1	410	\\x8fe580002ea5b6771618bff22269b3365fc11b681af10fe156a816741fad007565499f698d3c414cec776d7c993852de85fb29db397f761ad2ee92fcb08adc0c
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
\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	1647564607000000	1654822207000000	1657241407000000	\\x6129a04c011b0eaff2b5bd4b8e09d3034b10476e469b9f67061c874e81ae7295	\\xaa7fe527c912a8a056b63018c559aace86626172b8e5b70a89b325a5f0ed425ea61d74a7310a41bab4dd7818f3e2fe9e6d627236c409ad76009e25cb7ac59106
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	http://localhost:8081/
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
1	\\xaa8151558d3ffe52eddc2c1fb82804f6b2de91704306fc44a7cb76c4dcc5c8eb	TESTKUDOS Auditor	http://localhost:8083/	t	1647564615000000
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
1	pbkdf2_sha256$260000$K0TZBFf1v18SCrXeEyrexP$zg0/4Z2MwKy9pe5Ui+kS/XjPPOPtnGzskxt2AqgxRKE=	\N	f	Bank				f	t	2022-03-18 01:50:08.595162+01
3	pbkdf2_sha256$260000$b48Cja3oCWAXGjluKZGrE8$RbeoAAe1NiiRlHHeGLmvLmHpA7jcGepCUcF94OgsAkY=	\N	f	blog				f	t	2022-03-18 01:50:08.898972+01
4	pbkdf2_sha256$260000$XYeByfAhGFH5aIXTNYJPyj$uyTyXnVBlbxBVLNsUnYd26hjS933IBXEOfIsA1HJqzE=	\N	f	Tor				f	t	2022-03-18 01:50:09.043616+01
5	pbkdf2_sha256$260000$5LLsv30J0Vu7CL8V5xOQXG$KdoGdVIKu9xodPNUrwtRdUq114ByBysXrs26hlC9jR0=	\N	f	GNUnet				f	t	2022-03-18 01:50:09.186229+01
6	pbkdf2_sha256$260000$rsuywDztuRxC688IssP9UZ$f5fE+B9LElomcszIO4xasfkj+bN8F7r/fKf7rimupzw=	\N	f	Taler				f	t	2022-03-18 01:50:09.329617+01
7	pbkdf2_sha256$260000$QOvgU6csegQ3rbuwUlmykX$Ub6BVGFmkftfeHoW4KEdaecXOBBWj59RX6WWP047muo=	\N	f	FSF				f	t	2022-03-18 01:50:09.474456+01
8	pbkdf2_sha256$260000$MTQuh7sU8xTfEoN8CX9kV1$ONlYfIzhIyuIo0mUdtAe5oa7or6Foj65I7Dphx88KCk=	\N	f	Tutorial				f	t	2022-03-18 01:50:09.617471+01
9	pbkdf2_sha256$260000$CXL7z1bPgh0S67rkDVqUz6$rm+EaDvKInQHC8DzzD+MR1ceqXF95sxJso89KeD3ogs=	\N	f	Survey				f	t	2022-03-18 01:50:09.761584+01
10	pbkdf2_sha256$260000$sjlhajyzTsGbJntrOj98vR$CE3+AjbjkiH0LbPgGzmtyZ2NG5s1KWwHcp+47LHc63o=	\N	f	42				f	t	2022-03-18 01:50:10.246556+01
11	pbkdf2_sha256$260000$w4vUmzuBbWeghuO8Pemm2i$MPPJGepbQ1HZNJj7hAO7GnNW5wANKJh10RqzCglC80c=	\N	f	43				f	t	2022-03-18 01:50:10.782569+01
2	pbkdf2_sha256$260000$UwGzd4Bi9FceQs2Qi5LGM0$AQa2EMao2X+QeHTmlZ8gVm8wMAUKjT/9MlmdchxbRC8=	\N	f	Exchange				f	t	2022-03-18 01:50:08.752022+01
12	pbkdf2_sha256$260000$9nzgn3wUDndsLDuEUzTyE4$HsFXRhMVowOZwq7G8subpIVU2io56LbXSMRDm9Pa6wE=	\N	f	testuser-ikbigwkz				f	t	2022-03-18 01:50:18.097191+01
13	pbkdf2_sha256$260000$GDopLj9oRWgj0aiewEeOhH$2mZG6ZgsUWPRQAZnUSlxK53g6hbgbLbqUiKDUDCAHuQ=	\N	f	testuser-0tybbkgy				f	t	2022-03-18 01:50:29.364071+01
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
1	\\x00dcae8bf5f983bd7b190fe04a70bda560ddcf036d21dde67fb4b794031e3b24103650342b80c833b464c9afd6695e9ee8e502e8af5273864078377de219f43a	1	0	\\x000000010000000000800003c760cadfb0d7e72fe4ef8dfb9254fa3281ec4db82b1c9ad9012c62fe449403531bf05aa29d9e8e36170b113b28929c48aa5d91615c4095c216aaa10154d209b1f962504e67d99b6c7d6051645789b9e7e20923df1f26a3b3ae120c95ede46a17c5abc6826222cf7b2f15f34506d0448e7dc3badae0e2905ea043a2148630125b010001	\\x2369679b49e80a5722a57823fb6a0df0bded017c1943769b70e6c4c55d5a338be205dfb0a1c43516f20c2b8e622288987eaf506cd58553a468ffd57b018a0e03	1647564607000000	1648169407000000	1711241407000000	1805849407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x02a802c52e1adcfd550d37f976ed35b41799d47ae9b9e90a540bb94591003e1a853cf47d7050967f28a83384be24d16c87fcd82ffb0ec368e25aa1c856924d3c	1	0	\\x000000010000000000800003dfa328384df620727e9cc6303b716e3df9bc6b1e9a3636bd8a85522b9ff460feb0d248158b234d20603475e7c0a6cda8cdf9a97df1e63e34bab49af78fffc5b4610ddbee4b3ac1e06e6e344918e0632caeb96b071f304138c37f47fb73cd6f3a81b23e1224b4da301a47a938237d044efb9510f94d88c3666fb477b29a7026c3010001	\\xcad3d8a543cd22756478a3154c94aab1bc81eece6c75f943ca5a0c485250de52b05eb19f4392ae7dc0525888596fd37a4b4e2c4ecbfc5cbeb50c4669c0fc1b04	1662677107000000	1663281907000000	1726353907000000	1820961907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
3	\\x059c59435b31d3901dd4c17c62c6937d06b7937d4833a8a0db798645719bdb87c34631331f942690599d3cd0fdb8050c776837be07092332b8335bd9386b4795	1	0	\\x000000010000000000800003e595e2c6b1fbe75925e5bdf386e434209f2e0e6cdaff2b4a170cbfb1a16b189e2a1947ca5d0c985a3884097f5046be1e335afa021c809455cbe45e2abe8df86ec5550e4d727915973e878abc51c3a9cde3cb91f87c8f2e381cb66f7aa7fe2d686dd3a3dad2af3915cc4b7234fc7e649e0cd1c261648f92d006cbfe13f2524ad3010001	\\xc8574d8278633b9d6c5d58eabccd8c1d70eceffa13878e8db47c3c30287da681f23bf8e5d0ee360ef4b3be73c3dbf0a67e3b560f52d777c2d707d5665448220c	1654214107000000	1654818907000000	1717890907000000	1812498907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
4	\\x121089b1e13591ff6e577debb974baf7ef031b969b8a023d66cf3fb321040c71d34f48e11705cdaecffdd9e8a72b55c85912c36a14ebee3d05aea0dec0138f6c	1	0	\\x000000010000000000800003bbfaa9e1f7a52978e565b461d8cad1dc1047d76cd926c4b3fd5ff4e8d2cddb61fcdfb46808fc8c164ba1e4862a78fa41e8504dc47538918af2fd14164396cc53518dbc415bbb3b81d3f4d6f87fa8af2a52ed96a3dfbf5ea6c5332bcbfedcafd54499c8062b5c2dfc0cee8d7b90d9531af6ccf3dda6eae6cc2c9d1868229a8847010001	\\x0b86417125c7aada4877dfa4838bd9f5ed253da2d6ff25e4674bc44cc68319922c1966ce36a3427c1c23d3012184f8b8074f296f93bc16023f466112a4c07400	1651191607000000	1651796407000000	1714868407000000	1809476407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
5	\\x134ce7bcc23abf87a335b548d8fe1c8759153e98ebce7a406f019b3b4b0b5562369711b8e7df5d03d73450f8c58c3262f5d22561b71a5e38acb2deaef3815d69	1	0	\\x000000010000000000800003b59aa0a4d5f9f37b6405cd4e20e217ea883377501fec1fb4a0796b6a87c9037553a9fd1b9ac785140f83290a25ce273481728407e85ee3dd4146d90c9fa258c8b28093ac3821b504913bfc646144bcd7b7941ed5429e634583eb816e6545aeeb5e8d38111c682082f8e0bc1a2f0df13e34c763f7726a8811170b45d4de2b6a4b010001	\\x9dad5f21e909c4c4c8222298c7802a6ca7f10679c4b6913ce92b240c94b81c8eb7fafaa0369531fbfa41439b651de8bfbeff19ed8e121a9d6f6ad05edd3b7309	1653005107000000	1653609907000000	1716681907000000	1811289907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x15d07eb2d35764d2a342c0b80cc0e6716f1f2e20190379e010ff452f1e1a82015db0569e1997d3a8b9de978dced6363be6e253ebe85999bea941edd46efb582d	1	0	\\x000000010000000000800003addbdd4d95796744ad49d334d8c286cbf2339069b84caa2a00913b893cf3a13492c1c9b8e4b1255d6a0b338b9c8d8fb7b3655bbbb5fcc423330c837f3db7d8f3f0dd142dd95dc8f16f6fdd0487fddef50c0e921cd6937730989afa68bcfa1b1b051b8e1c9b860001c7253c3628296303da3693ba38b439e7165b148649666949010001	\\x863ccfab26178abcf9f97bb52e3e0da0e337d4654f9eb002b97fd84f1b15e1f59afe2564d57b5e050d9210fb97c72dc2b8bae0c715e2b5303382cdbc46f7820b	1649378107000000	1649982907000000	1713054907000000	1807662907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x174c0cf6a316a5bf7ef6c911d9a0da949089bc07a6a18b657a24cf0e95ceffc3f87a58c51b18dcd9ab77b273c28654b88804d4f55f4f26477588a73cb03373d2	1	0	\\x000000010000000000800003b3e1d2dc79417d5d1c919ba1606c663508730ec08722582efb9af7f27a5e2d54d586fdb2e0866980f82f225c4062c2285f0be69a0cdde16cde1c19c6d867d32fab80383e8763915dd1680746c9d2c389119a12ae0115e0f5cbfd192068047efaa065da8048fd90998063d9de807315429a9469012996edc1aee81add262f174d010001	\\x56371351857e97a836521951bf8c0a7bc0c536b96ed8efec2b5522a8e5d5d501c46064c97c9c7a9120d9e9e79046d50dcb5dfcb3cb1f718621c3b52e637f840d	1678998607000000	1679603407000000	1742675407000000	1837283407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
8	\\x1d28bbfdb48d8a44848ecdf7da9d7067fe83375de3d00df0058fb489af23c4841456988d8773324b5968f31e6f0f4c3dffe8e02f562feb48e458e8f66bb5fc82	1	0	\\x000000010000000000800003e2612dc0fad39d194751e7d4e68c6a498f99609b41dd6e9dde569d34458220002eed018139ee90e79859e478b4810b18c185392103247fffd3df77fc7a7dcb47d1fd3d9c5321d79109e662140ebca98b59feddfce63a7f609feb0be0f985d9d4cd79b071e2bbb5fd3650b98440fdef146569b8f4ae6af350bd2ff244ff7cc2a1010001	\\x968f076f0ac59db7ec553a79f1bec28a2019137667f47ce57440591f2e02b7c3e07e34a21c6d38864597ecac3735707ddcfc38d0545f9163da6c635420e19b07	1655423107000000	1656027907000000	1719099907000000	1813707907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x1f00fee2eb735590c16b41f472c9b90de87c6a50e00899cf2b835e41723563b9eb822df1b481e8be2efac48f6f9bb59382a6d67c2a865f909e23985750686136	1	0	\\x000000010000000000800003bf660205598e435914597eb7a84148d3b5741f6718fb47b803ac015f31b9b684e1ba93e0801381f8b47d59a154ae3d8f42b119abe9c503534b689389995d8a73eed175dbbaaf9f386006e981923a41507bc9d736c5e3a04d858fe1c18880e5561fca91614d493d18e33c77e5f6b0974f68d1a2cf1227be4315c685d7413df571010001	\\x8205a596ea36051008effbc38bf5f75a734bae5680def7f54d5214370f99448688975088582b7f4222eda7026f5ae3bb42ec13c367a5bdc1957d2123a10e9002	1671140107000000	1671744907000000	1734816907000000	1829424907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
10	\\x20988a129553255ba79994c7883dc642028868676e6bf17b2f33db28d0c06213ada76ffffd90f5a1ffb142e912f232bb741f01218d7bfe603400e475aac3e2ae	1	0	\\x000000010000000000800003a57d66bd7021006f89b01a37d162ad88d84389e8f8910c6fe319d71073ef8afc237fcd8a7e25d1251da606d8d82dfcc9864679b19301252846987b5c38a3534590a4b0711e9cd3e0bb1eacf9173679d48fc14bf664ccefa087b52dd4cb25c71de79347c645aaf12186402aa5d2caebe16ff95a13546e3efa439ab46296f89775010001	\\x5b1ea98f3c4fe5d85579341b6442540c70f4ab35dfc9f19dfdb6c4b9a00e283ed5ab01150439c34e428c2ce11150ef8678b3f8bfba173918cefbdff6e1f17e02	1663281607000000	1663886407000000	1726958407000000	1821566407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x219ccdb3f935d8a22a5c35b0b3349e3ee0eeba496eb0c42dd4bc13324de2738dca2c56d66d1e511eef05913ca9da035861e18969536957700c2846018bc24fbf	1	0	\\x000000010000000000800003b6b1b62d68eea9cf0d1ca024ac9e6d487bb012d61d68b54be898dc82c996fd19dbabad091544c05f4444de26affe5318b2461786319aa86c5808e871dcf8b61b543773d70c04da95fcd20f13eecf51fa48c0278c22088dfe566d6fd06d13012403ecd76a8a351b62b7269bbf250755ce0c355a942c0382409670ea434b6a4fa7010001	\\xb7c79b438e6de0be3b052a493e5102891b8ac2a8e7413d6b063e25aa1138a5c6220bef8ebfa0c5428d1842a172fb4970cb31f47a8cc62e87da23f961f4764b04	1654214107000000	1654818907000000	1717890907000000	1812498907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x2174560b80be2c5f900977c6c8c032b9f7b4c73e127c24fcc4012046410bfd26141d0aaf4372016521b84a9a0fd2eb9e0b6580ab11f609471cc600272ae278ec	1	0	\\x00000001000000000080000397ee870251f75d9ebb7d0f18d2361a9548278850796940017fe387b49f15d6960f480ac8840e892611f4cacee4b545cf787557ac0f67b219399a71bdf9ffd2eca809f384047755f3496e398e284bda5e212c27ad0e14611ed2b5c4287e69c33315a28ed0ec792d3c512c57fb7516801d86915cfcbddb23ba721cf4bdc05ab689010001	\\x397594e03a409017d0cd30b3d33e1c67434efff106206d902f63b4a7358bffa6dc03ef16f740c9596541361c3568b8d0f041c680043105cc689627d0e8d45e0b	1649982607000000	1650587407000000	1713659407000000	1808267407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x21a03de3b9a519a6c206a8496942f529c661877c5e09a42cf2715731915a8c6cd2a5c50c8d84966c84f7a07750828ddcff73efc3a035066435e73c69a034845f	1	0	\\x000000010000000000800003b48c710699da26414faacb32ab619a36a3d41a6733ff6dde62d1c21c9466bb7676b8db8b61d4bb5a48e72922005f129e34d726f07b7152e6af60510cf09411c31c8e3355b4ea5a9e4dbac2efd845412607596fcb0820c79c2f64773fd728ce3807aeabc2c649c29667eb7356a12a029621386a789bbd3f427cdd5756196de28b010001	\\x6723dd1c00f36816522c169acf002830f6450fafc03201b1d3a93647b4a27a9ba0a198dd59405e217570635b23215026fac4a73163d7d6e0e659563db5a61d0f	1673558107000000	1674162907000000	1737234907000000	1831842907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x234c96cf10ac245f3ac198c0c82565dbce448f601b909a53cf4de0f9dea5bc08906cc4c463ee2b6d4adfebf6eefc67bb79b4cf5598a9613c39afb12a8f9b8749	1	0	\\x000000010000000000800003d637a0c2db682918de0208935cccd0bde7978519fc9e5e528bba39d20cd2e256e85af62a547fb52bcd0d81b3bb1f1e4572f1622f22387345f595e19bba0b5f8acc3f2ef702dcd7306db45d500d2206d03bd3c1e00bf4d785e4d34f931909b545cd93f2b69b1a3b3c31b50a61a8817b6dddcfa2793bf79bba5d48da5ceb959ef1010001	\\xa42a20a52a3cb77e1b5d691c3ea4d021214189f1f9950978f4e4a1b4a84367d856ba9ae7b8f6c85667312e8e0fdd4a1bfc6a9c2d7de7e76c9a7a5bf5f947390d	1672953607000000	1673558407000000	1736630407000000	1831238407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
15	\\x27bc7b0e23100f67476b13476c4d8787433d440c64f9f104c55b3ef384361e1e3f596e4885297d4291d0f9ebbb4f6939c6945b7c38b3b166c3fda95c0bdb1b20	1	0	\\x000000010000000000800003a41444823b4809c1e57fcedd279e7cbf1cbbb3f1da0487722af08ee9f67378a607fe77577822252d1de43c386c2ccd55aab9563f6d310b765e59ac1ba5435d5af06e7966ad4a0e92c84ad7bf8c56fef2e9402faac0519c7e04ef1512a2f9e68f7843c1d11c0a75cf59db6329bb6e2a46297d4f5f632afd06645141f1eb54fc0f010001	\\x55e758efc630bd3ba9f21ad946a66367ceb5157fd2c40b9802b28e0362367fe595913f1d1e969a815bb92be9d3844b3be4d9116d8f3e048c3ca00eebbc2b6107	1657236607000000	1657841407000000	1720913407000000	1815521407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x2c64ace58cb031fc3fd53e057b009acc662ab33d01eac9bfbf632fd73026831e5fe9a4c028512a4bfd314fdd35729a11b65b1d99fb42db3ec4dc6c324971d138	1	0	\\x000000010000000000800003c7c214591f659d2bc404a64b6b2a11e7af9e174dd99140127b5363b93f5aff84f95d181a51a5f1165578c15e2cb65937b6eefde9be995eccfdf62222fe97646ba717dd68d9269524348e29621045d6213207cdcc212785cfa92ed972af13fafeaaeb2c8c3b7f21a114c5346467aa4e101ce51a47e4da7a0e9df48abc4f4499bd010001	\\x8acaba6b900d852e3252b695b8558247bdbdc21accbc1843f3b6da833f8bb8fdeb0369fcc607ed7c48a74f2a05537626a0a5af62280c95a73f15cb7874df110c	1672349107000000	1672953907000000	1736025907000000	1830633907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
17	\\x2dbc5a17537f87ff66314de5fea1a26ce5057d5bcfd1bbaee01aafa391e94d12fc3120fcecb539d606beb6a6c6e4e437eed8679e7acdfa8fd3e6953dd5ab32f1	1	0	\\x000000010000000000800003d1107c1f70eb6850dfdd2bffe55aa9faf0234047b6ce24ac1014dacc7a572950e8e769839543706075bda50a3cf004cbace7b90e63f0938fbe184f31b4f9d2778a950f80c8e532cfcb199122b377d1373d188c9e759dc648a0187c99bc4cbf1d9b33ebe5a953aa063aea321f0b3a449cdd160c32c438921d38a47125c545548d010001	\\x25b09960aebcb321719db22df36f2601cb18235f6a64f42655ae48f5bee058c3c6e4305b18438b6ce29b15eb66b01a075049f8ed06dbf67476683f9c632b9706	1665095107000000	1665699907000000	1728771907000000	1823379907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
18	\\x2f18473890f803850f808bccb242e12307623b7ce09e25b1f8120b4a57d49df7e929d4a46b4a8f8717a8a04db406c112598b142835f9914318e7771cfd568819	1	0	\\x000000010000000000800003ce908d2bb867a2b10b52f95536712671874b79b2d15083280f2054e35ebde753c14115bbb9e5338b60607edda4f41c9846dbfc537cd91763827422a5c9853922e98ff91ead039a7bf3e23577d37789844a2a98818dd5f5e2a5a59a41bbe3a3de376611c4be2c5cfbc6bb240d047b85c5653c602a24410f47a17ff99708abdf61010001	\\xdc22ec1acf740fc776c39da7aab7995471d9beceb33db29aacbb98a2ea09d26d278084023b362c4aca4fe425c92e92a0ef8985d800ee2f9b46368e83a8647307	1652400607000000	1653005407000000	1716077407000000	1810685407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
19	\\x3d7c382382113727ec750029d79e1ea40d70bfa5c3adc344f8b87cdb08aa1f8d18360cc87607e7ce8fd2f2cc46b3e6833dfbfa9dd8bb9475c61842cad4b2a8e3	1	0	\\x000000010000000000800003ae801c4d327a569d7489397ae22784872d7cf92c74a8dc16a16574144c14a988de456965fc7f68792addaa0ed0a1b784dd6c791bde373df1591d6d9d2f8d0b8e8c0810eaf7325648beb58f9159d39d1f5e547afac22444fe17370a164b2b551d02152770e1e3364c97b66b514baa32d87e2ae8d7604290bfa47d95d10b2bc2dd010001	\\xbe70823b8223167e6b12811e873780267b1ce6b6a745a062499c8ebcb971f5bc3c43a3c51c64479288cb709ae6ec8939d382fa6b3595d78328141b581a83c80f	1653609607000000	1654214407000000	1717286407000000	1811894407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
20	\\x40e04e874cb3b5eb0cec90d57ed2bb6e37c5f374703c4e12d5f959d08aa1bd808c7c6c9e5743745fc464136b4f55cd110eb6cd3ca00464e9ca75034155386761	1	0	\\x000000010000000000800003d20f566e3955ceddb804f08bf3b987cb1e3064377d6d53af2b47ebb8675fd5ff452e67af72a0cf8561238f78f39c71ffaffcf63a96cbbd388834ad617aff0972d14e5d1ca3f8ab4426d82d3f769c86a37b90971d0067e400543361ede4b58b36e10e01fd1d8be802aca0a9c576f46487453d6f453d76cfb94d2d4a9c853c665b010001	\\xdde46fdd318663eea003a70926291291404eacd746fee0ae77971f2e0ddadfcff9df82bd836145bd13ab7cc579ab6aee2e0f7c0d2b24b2dafc750a8c7b72a004	1662072607000000	1662677407000000	1725749407000000	1820357407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x41984f587b38d8046ac6c4d5b6d004edc6f5f19d99a54a30dda0d25d51ab2b26d09e4e8bc06e1e7ab143065793f07b1945911381d6f2ff1fbacc62cbb0e23176	1	0	\\x0000000100000000008000039baeb2a76dc8e715b41d9a73c0c48ea3d24550c04fc15537d4185cad20bc2311de311e40bf9cfa17c1edf801d184f931a2cc0f5cc1444a47033c305a043992014c56f43092c17ffcc0ef2da1b05a5b945e8b392d9fb0e36c1c7ca2a16bb1765cbcfa2c5b7c47be1ea45506e474129b144c4b8c8136c1454898d111a96c35447b010001	\\x0c1684218b09c1a4cd9cdeb4adee96255a6b052a9789cc0145ecb8a68ad8a61ddf03e28c75ff713b5a6f364aadf16019d083c0f620db73a13a7778a4bc934f0f	1648169107000000	1648773907000000	1711845907000000	1806453907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x43149b171fee1160aeb3e6ac7e3865f494cf2d744c91d9feb51b1c967af229a1b409caf2ff978fc665d8c1fe046471e78ae42c0dde32987657d23ccb847544c3	1	0	\\x000000010000000000800003cde00523bc4501665df38dc5ffc70d9e3f936565c4d5417252c17f535cee036c2f9c5dc3140efc6fabff570b71981a9e7f0cea2cee1de58366b1c82de4aad39088abc19cb755d75797d7ce3a9047f75877415ffddbf7abb59f534b6d8eee21aa7172464113ce5941e979f01578eb46d7a8e9902cedbe49a1bd052ca8170e998d010001	\\x21b82c9f770f902e1cb631c35e937be0dcc2856b0a97532adc24861d817493d46fc14600824cc5e504fe4ebda46fe5724515d1e8931e398310c497b0ab456809	1658445607000000	1659050407000000	1722122407000000	1816730407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
23	\\x45d8da70ddbb3b4187fcaf02ed3568966a8b4083a1e091e490b71f87c319dc5bc976ad8c29102a68f3050daf6ccd21cf610f8d387be79601bda0a39d8601a9cf	1	0	\\x000000010000000000800003bcadd34532e045442ea8f9ef7ea869dc401a67dbbdff7141047f8e9a13fb7140b99ec4a97018c278eafc207e5c86ca49456ac3498284ed6a9907bca8f92bcb706bcf610c5770428507cc462ab7c230aef43b03cf3d1c9ff27950d0236c42476de089379910eaecb44ada8e8b0ec816d81d569d18413152d8db4e692790bc6f99010001	\\x3f7ca6ed18e3be0ff32293effe04c97c612f4c0290913322a62faf189f9469cb3806d92a714833d30a4fb113644af9e10f092108cecafb7aaee0aaf363e39d0e	1666908607000000	1667513407000000	1730585407000000	1825193407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x46706b2a7e6f18a7f636a50144e68175aa1d39a46d2f94774afc394d06a858c313d3bdfa45e92373b6fd94f64839b709448a2aaead99050d82d82229b6e351a1	1	0	\\x000000010000000000800003f2101438dac52b295723388e3b7287dabd80c21dd4a8d11a8580a79e2bce03a819c8d81c73561317a12c627de0876c5551eb2cd77267a745e2165fb8f83b557816116a6c2e88f27284579fae6a716dd219734f6607e3e69f1a599d04eb7d7c0700bf024c596c073201ac4d20f81f60e0f3768198999e8203cc96236637e529eb010001	\\x61fcec96c16e67128dd6743a7d221b8c8ccefb05cca4a9c9bc3430d3777f834e8dc92ec3475125b841fc5d3d388eebcc8a3137997f4247132150f58995d3190e	1662072607000000	1662677407000000	1725749407000000	1820357407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x4ba816c55aabe9fc01c5a4608d22876fdb2d2ce8f8aaf4251f241bdb283aaf56cfcfb449cf3e300f1c2b33c0db6fd96590c54b60438ac65f6aa4e35d0c52a176	1	0	\\x000000010000000000800003d0f027e442dd1be60120ae58b38a6e72922476355905a9eb75da91902d8d85106985e52fe3ae9e691169f2d49d0911cf3cbeea7510bbb38d5efa5c4245e41f2ffbbf1fc7d5b0b6200f2537e4070593c5ba845b2cf4c4c3593689b3dc57230153711ac6384a16dec533f8b79a8b32640b24466544965ae894f17a9510c33b2d7f010001	\\x73e3a47d8df350d6cd134417b825a43d84e5e8577ce60e7c16cf05d3e788eac87968e1b53dcace058254f447b7b94b2ff8c76ed2b7c51c4c253a842c45623e05	1662072607000000	1662677407000000	1725749407000000	1820357407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
26	\\x4f1c44e48fa7e0b2a71f30b8e768a8d1f5785c281720c8e124bea86bf70aee4bfde707883f57c79e4311caaf02a1dbe6036dc0ecaba57c672305bdbb67389bd9	1	0	\\x000000010000000000800003ba81780616b7e5de0b5131bc2453e26a944f2c491862af012fbaf9bf9d39a8197bb2478c3063ab8d8ceaa108ed89479941b029f89926ccc0199cf43d38009aedcde5f53798a6595b17379eef72e4a5a54fc604dfad1ee5a2ae79e2b02336cbd45ca6dcda3c28451b36c4fa588e5334a938b38ec3cff5d42d71944ff8f2768667010001	\\x33eb9c0c08a8088310f1c9ef7ef9f5e08752975ea7d16c8d834f2b47412dd39a2ff68f1579e13f4ffcd43b338284ad0a46e6e6ce631f7cdc38fe61f71043d00c	1654818607000000	1655423407000000	1718495407000000	1813103407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
27	\\x5500201bbafb50bd1901eb515a39375f9863f36dcf3f7a4f81817fce2359c5fa151d3c226845bc8587410d4674a88c2fd7ee13f96a4bcd88d8fa3361b48b1063	1	0	\\x000000010000000000800003a73bb96cf47dbb787cd8e8b26cf093d9133fa098bed18e636de2d796294b561f01e1046ca50512e7b3b49da6b67b8e4dfd204dfdc99c6700709dcef0abfe52cf191758fee62cad73831846254b80afe2aee5130a6601987c1a8f3bd4438fee0f468fb93c3207dd0f2d822f9ec88d38564ffd77fad0bb35998d19faf1c08b3e09010001	\\x0db1bb32c9bdd4a28bb8e6e7ad4aa08b9032d74256add07211955168312e64d94a2916811c20ea602165fb774609a89d7b6c1b3b09923fe74780849f086f8107	1663886107000000	1664490907000000	1727562907000000	1822170907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
28	\\x56849c0b68942d05abc2760beef39ea42f35d934957a1e7198edb3a9af08ef33390ec52a07512219f7efe3362e6256bb1a4ea567f06288ea1e74e18875a96b6e	1	0	\\x000000010000000000800003941b7508b7d9d23bcb0f2fc1a797ca6cd600ee7eff5fa35cf44e94dcd4ab0ac01640fc391071530aabab0c5b3413b06dc6eef8fe97fbf6e5575696853c6984b738834aaa5e61c46e7e220e81773d3ca28a392e87ce87a302193a230d08e2daeb5b4f87c9b2c11fafb00099285a0bc99a30ee09c51e24b4cbd959ecc104de597b010001	\\x593938c773e18c0ee242805b7eec2001fa4181c9a81d7e01448bd2af87b18a5333b8179a1a3115485d65c1257ff4f8595ac508a877ef08fe687ed2648e178a0c	1660259107000000	1660863907000000	1723935907000000	1818543907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
29	\\x596c8b4e6f166d1b6e3f495a9c9bf2efbaa103f8e2bfcee83c63b25d5f155c1b954a0196d36ea3bf15d45836465a63d4e49bece7b20c1bbd408e8d77390112f7	1	0	\\x000000010000000000800003d66637dabc69ca94268c997e4adbb5945ab550ef027c52027aad38571a0db9b8cabf3ec2083775b25ad17a93e40b15b2b7408b25bea157e37f760ee37ff7110fc4513ba4583ba6c3dbcea6900db8fa2aeb8f8aafa9b95e0366b91a91754de7676d605de1e63d9fc9e4267d83d8e301d2d66793e740c59045d58592dfb46c6cc5010001	\\x4413eb65a41e6d23b90a4e86d224c8b14c435fa4fcdf6bf814c907bb528a92c72de7f79a0e7537afc0627d862204f890ff334d727bec0311ce8d8e3a7fec5707	1668722107000000	1669326907000000	1732398907000000	1827006907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
30	\\x5990fd3fd0db27d2f2a00295f4176b3bf6723a0a996bb37cb2002bbed1ae84b20c2c7840fa0eb47ffec94d3caa577a4cdfee29833dcdf2c552491fab5471db27	1	0	\\x000000010000000000800003aa107ef97d1ec6ee39cf4727f8e369df840da137144d4abd482b1d5b6648d83d99b63eabb19c75bd00b4573970abf44a6812f007c81f9bbeb543e52c601ba3e97101fb4bf2c29839cba2a1b329959e123b49e2b7456c887272b3a9f2dcdc5abb5e6eaca65c42f4586200fd3ffb21857b029b967e20dd39c3dbc377607804cc8b010001	\\x6828b21d672c1c0349fc0bcbdfa29ea961dfa4f94a54e49d319b1650721435a08a27a1813ae58d3b737c408a23da6f3122e0c23802a1fe5c30f5083217fa1209	1651796107000000	1652400907000000	1715472907000000	1810080907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x5adc4d9d96b037acf86324d62de948ac81b763fa0b47504a74e0839aa8f23f4d5ce0f66c649ad320386dbf6333f63929167996e12fb532082d67a10613bfeb16	1	0	\\x000000010000000000800003f2503c878341c7ef7f841f43a5a74cee516b41ba2a7246abd6f62f74563bc983798685ba9096ba08dc06483f6744711c78685c52a098e003630054dbdecbabf6048b896875c0527ef12f10abe626ddcb39f75521755597e402d7f497c7cdf142dcc81d5a3507da83ae34347470392940e7232ee9585a97b8402b3b83fa959fb7010001	\\x48ae55f02d7a30f5ce52c1634cf777cb4f1e8f00826974967ae489ec3b07481dececf01e4c48e57f01d8579354c63ac757dd417608ff17491a3b48a919c35504	1675371607000000	1675976407000000	1739048407000000	1833656407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x5cd83cc38517031d35e9bc1a2b080e527be31bec10a0ccf30e86457a8b5a73cc2cd53cbd11de9ac725668da1e6d2207e48e0b6481cdc0d4fc1883c93dec5492f	1	0	\\x000000010000000000800003e906957f1cf67cdc9b6af670cec9446722be8854762e9325cd333f59a1ca50b92978cb4f7c0d4658e63f112448ec07069ffaab951193613377e87f907532f0f4bc13ece2ea686511807cfdd6ac02bd4753c7810dc976d17b5181182bea5a0d9d6b6b95154aa91f3875e00d5a0e3eb019bfab91b630ccab8eb66f9a7f58175a5b010001	\\x4d761fe86e68ff7b8f81ade007a62acd94b0b0e3fa34cb257cb0215230b252bf0c92ed58e6364eacfc64c36b7f7c2490f948d26e28d893e47bc941ac1d36c500	1660259107000000	1660863907000000	1723935907000000	1818543907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x5d3436ce03a182c28916de7fb638052ba51d9843749eb032216004e2412c3250cce38682514b380b87206685bdcbdd0b4d05742025283a2e6e4d42d6867b14de	1	0	\\x000000010000000000800003d95e20ba2ded7a320b38346700924dfe46c45dd71729e6b73a255cfccc960e37b554e47d394dbb9d3d380cc7d144d456044487737c7a592146a93d6b64ba02ed47b333d5af77266d39102c9f608a6765e81996ee268d6ceb4f7314422808afb955b705481acffd8684119e13811e8010e80291d814c0d9db3ffae282ffae78bf010001	\\x366f713d2730f32ba2f5d188d4f9b892d8c12005e4b4cb78aab9402401e7b6732dfba755b3d3fed809e6d102e7d875c8b1dac5ae000625ca46c6fe26b3770009	1665095107000000	1665699907000000	1728771907000000	1823379907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x5d689613685fb67693e45bb4ba33c2674248eea5a58d21a8afd2336b72cfe086290d5b4251f91557802174a69d7f7760740b08677f886da852064d4630279159	1	0	\\x000000010000000000800003eecc27fe3c38eb8e81d6a9323f3b73bfd4b51f92b32dee01992954caec59b11c6be6421597097fd747871e167f36eabc865a3bc859105cc16da1e876cf4cffe784467f83649450ad2f83eab54ba6d16b41f27311d44a310c88689c4fcd19e5dbb4a392460956b1e66d28a9bf75d72df857d4e0bc83352b12026a6cd550a3155d010001	\\xa4aac67d144214299fba06907e5ca9b1ae18a4933e151f36467d9c94db9d96b285486d2841fb0851b334224643024b50cb2d203ec6f27e4a294bb81eddb40604	1660863607000000	1661468407000000	1724540407000000	1819148407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x5e30d25c5e811e7893848ee3beda9b43b4cea5c22a6fa6d265ddb75b43c6e59fbff0564b07b21bcf7bcf11e1c96c7758ce1b08ede48f8883dcf2d80ed7eb792f	1	0	\\x000000010000000000800003aae5d0b9a0faab0b0beaa8e0bf666d12f0dd74a8f0d2be2a11d2a72486ed7d6ae7acaed9d2fa98ead1e1c4b1af58e7d56fad161b3a37337ecadf791f616e6c2b74c2a180743898776fd2146abfc8e54754181b493eddffdc01de12942cd9669ea64bb94f8081d48228644f028292c9db26269349eca9ded0df528374bba0473b010001	\\xcb4237b6a020689b6f6e9120fae897faaaa29d31ead6d712b00937a17020972f12eef986964f71d65f4395c43ca9db59247395f90b70ea3e41bbe5b0d41c970c	1664490607000000	1665095407000000	1728167407000000	1822775407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x5ed0750c8c50417615a34c94dcc34f186aeaacf97e70df471a7a6da31c4232c114b2ec810e5fc92d4638cf6fef12059a4c1af24ae8f8f740cad9698a1468db56	1	0	\\x000000010000000000800003b2a1bfd4890e585d664fa38f586f2226eb559a303678ddf4234758a2e549607f1b463721849404b344af7901c8f7a55cc2e8a5568f8d29f2ab4009e662813fb9fb93a8ca1013c8e210c59ee23014da2e19f74490cccd65241e80c4ccc73b65aa14fb30d871de820376e90ead7bea857297e7ededc767996ab54158331021ad31010001	\\x1d0a0f158fa843afd46dc2e2a593bdd4bd3633cc174d1c098fd4fe820c5f449bc078239c6c09cba9bd688395ce30922ee87381ac9c0c6caaffcbbb731a366107	1666304107000000	1666908907000000	1729980907000000	1824588907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x5fe0675b9bda8363ae10a4388d9bc7e267d8f5e261b8b6ff112c2f05b0337a72e3984388ea75689c8ff3886bb873e88c8da3c17d4f07c5c95d91fa715ecb1732	1	0	\\x000000010000000000800003c428dbad31f12cc47bf203def9726b84e5bc59517436791ab3397d9763384b24ed038b60272ce98a1abd7951fe769a75eebf03e1ca70ba246924305cb61fbe93bb99b8b065e38ecf0316e9d0449a5227ea6ec6fdaf68217ad007710d4c77c6193c76f9e3675d8679fa2f1e26dbf7a3396c147c9da62949238ae0ff8ae566100f010001	\\x62e6e41dddc2b78d84d711e8db46df0c1f3fac894e728e20637b9dd5f2afa73de1df03e84dfced82bfd5f5700b24dd70a9d6ea7a49f6e8f5a18ca812b234ed03	1654214107000000	1654818907000000	1717890907000000	1812498907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x628c0bfb0f6769c08003c177d8882ae29a8ab905dbf33ea20d758f5e988215c475eb9dcb0e2b016bbfe76dbeb9c708f7fd7809038001e96c493066ab7ef9fdda	1	0	\\x000000010000000000800003b7c3cbebb5c85f0122539c8d78e011dd8f41e6112d184826378dddcb8b0e82d2f7089a55c3af0bc105df7ded08f58c6f84b9562d075b29ecdde936a4e9ba70c1930412b2639a511f3a7bd8220a55430439f2a752eb8ee7a89fd2e108fc1d09db30936a61069980d7a579b5842baa14dc4216bf63d509d9a076ad2d527c3efe8b010001	\\x0d1fba109d7023c51df82a72ec3a39af9c35d0912d913a43eb827afef290ab84831d41c9f4873ffc9bb72b6e4a6cab155c47c2e16a134c3739ebe1915962fc09	1654818607000000	1655423407000000	1718495407000000	1813103407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
39	\\x635ced35b58e528af7b2a9ea1a2e6498b00164381a1bd5b162912e783b4edfa7f0a705722d5c305a754de065f3495c7f5ca07840c6199cad3e8977af56431640	1	0	\\x000000010000000000800003b2e2dfa0dc473cd98883a95e0494a1229379ff57da81098829e2e27857f0782e3e2424dbd1115769552c6074129168b5353a323fa46729e2e352948b202dc68fd3ed0e4e1e3e85add21875a151a8ec0972d7f7c545146d2d7585b1a5f469c2835fb73d91e8b03010cc255c7faa4d9d6c65aa30335c718022fc613334a9a1b1af010001	\\x708e03e64a03f4f9f090d1ea9b03934fe5eadfd2d899c8520fbf17e204c4960f08b33a75e1f6ee12f83a103ee31a7824ef91bce46533e74640775188272d1707	1675976107000000	1676580907000000	1739652907000000	1834260907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
40	\\x66483cffb3e2b03bff6b65d89c0e13b9191eed442703d4aa33902210c37b19ac055b46a63a630e041660a5a836550ca4c03748e1ecf7d234342256e8db3bccb6	1	0	\\x000000010000000000800003b65dcdd263a3299ceab14341d27c7cc735ee41acc613d8cfee371362747e1b8521a2464d637c16ab55b2e51270ca641531d9abe73a20a5804b5cdeb2267120bdad4235729dc54917ddcf19db9d3e78d409ccc9864c0ba9a0f4dfc4f650055ce93c857dba60bdd26ef5d4f3a630ff210f1b32aa042e8a551b3353c478b707f671010001	\\x473c7c471a54dd031640387d30cc7f27d58a370e2073c57cfb0f8438ba6dde9e67f4cb194a9569897f154e3eaaf7d17dcc89372edb91e739c1ebc8a1d2acdd04	1669931107000000	1670535907000000	1733607907000000	1828215907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x662c5bd8f03d39bc9c3380d2d0f63e8db9bab5d5229294c406011c71e44b8c196a5580e189a16e2728c48a09337c3dbdac3274c63b1806f3f2f2829ab7e33323	1	0	\\x000000010000000000800003ba1ccec33875821f40068a3171da67b3cb56de8e4dac011dbcbafdc3d721b0894ec24427a4123958c3e9b7d31a18ef0d812f4410efdfe86aed7792bd0840a92a7204707122c000d158fd93b6b2807b6a87bf73f1014ad8ead1250f87206e9f49080b5d458464c57f2e9ec635ca102d8f6d91d84b5ac5c19c009b9f8dcefc2b65010001	\\x4334f96b4c437cf71e9fd06c5314e182000e31079cda9dccced36be40853c40a05bd614a3a47452e404fc203f9b241d29c77f5d952daa2ff2bfe3c9502fe070f	1675371607000000	1675976407000000	1739048407000000	1833656407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x69286c45e4fdb2debfdc4173bbdd3ee1e129558246dd4f627d6b706a27d71d2eaacd261ba5fde3a0f1d1e3f057166b9a7424b44cb26dbd4b1f9381582ce30395	1	0	\\x000000010000000000800003cc707dbe2f0decc7a0c062c1773f9b133afbc21fd269139d2b5021e637c125915388f789090f034dfe905c5c13509aa8f491d7d07d8139f039609380e884eeba5fe079eb8b1c8a8570034510b57fb809f52c60db724ebb7d5838b969ca2b78123743a5dc7a8cb85e0fa0446fab732a9d97b71248248556e684943dcd013a7087010001	\\x5a293e1de4b0e56ed3539a63eced82c816ba8499ea31ff9a820d8899bc7134164b6e4c7d1d08f218de510e45beea5498d1628f5c627746080d1ab6cbfe6d080d	1667513107000000	1668117907000000	1731189907000000	1825797907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
43	\\x69280f19191a3a35343a76e34be9f85155693f615eec53e640c8d3879050de8cb2506d4efdb8ebbce9187e67c6856259e7ab20156ce80728ef4a866c825b6330	1	0	\\x000000010000000000800003cad22af6b3bd680ed321ce353938d6f1749e03fe438355b642e4256564d8302e9e9dacad579967da031f65c6b777e957adb4ffa959c6b87237dc18d5d9dcd5384a09b71ff7e31f446c2e57c626f7e6eeeb5b4b6da68b8524e77c7dd80621af6d5e81240478896343dd5d2b20350ee1f7daba606171304a6d79bbfd1e0f355729010001	\\x614a6fc27cd76b3217c6f6e629baec34403600600cf53c183bd3040cbd2e20ce935356788b6069a28f75cd5f1f31b0c478a8d1ee7db6436de7340b87c1fec20a	1672953607000000	1673558407000000	1736630407000000	1831238407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x70548911d9203b0c73dc28794c6097f11ed7ca896e0fd4b6d7e9d01ad3be4112ca30d2729c12f3e79083e5107b63374911c76c9477a0693e69e5030d9cb8ca28	1	0	\\x000000010000000000800003b4ff80a9ef80ec734a8987b561ddc30420de2fb2df862796f829bae1fab343cdf0cb8bafc8f52fda4fac86ccd97b58004cdbd4d0a258a5e0eb1ab88f5fe6984d2600752540581943c4b6029a7b0de9a02c4d3fd6d4e480f325739c4a22e5379c826586006080b3bbcf0fbebbbd391c12759dd03d6caff7218fec700c12c9a31f010001	\\x68c873e8b14c0cecb4063278c3ed968e54bda6cf5181dd84af671d054d08bc26111e6b4e3ef051aeadaebb190d409c357c732ca625af6fbe45e3d5f32de0f509	1660863607000000	1661468407000000	1724540407000000	1819148407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x712003f57c3771796c1cb856bb3e311384935ea77de0d2b6a85352abef207453feb5a632e4f86d20378cda6d98609ea17872fb81d7a30b0ed4a550fb7ed42a6b	1	0	\\x000000010000000000800003aa09aeedb38dff2c1c002c6ca8606c4e8d11869c3c5858b576a717be461cc305a70a91edd18064301bbb3189d1cf744cba06df66977f8f6ddfb4c21a8094015f5890e1fe7f054e68661e10007f2b6e7260b546c81b675970d00b0bd6b193079812c86d565aef7d69ca869a7d5b02e836dfd6f9efe781c2a6de76e727313d98f5010001	\\xfc8e4615a8c7a5502f60ae3cb87a8eab71936eb66ab25709e6a203a7b645bf6af9291e0ff051c5d002fb622d39587717da52cec4bc7654525248fd868dcc0c0e	1677789607000000	1678394407000000	1741466407000000	1836074407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
46	\\x722cadad32d7be73195c31f159021ac040c13f8152a67f77e2c59612be5dbf07d7d2567fc522a79684a96374868d57ea43b7f0bd5252867088c7f9c28ee7bfac	1	0	\\x000000010000000000800003a571b64912b74cab80fa2807a2efe0f9323ab0fbbd542c90aa81d94ce47e0a169431d3b98a0d90bbe544aa4676bc11109a04fea9b32d1078b7c035085321c8f7326b6b5f359387a479c2df13fe8d90d4e54bc950c3007bb9209723fee4175a9bd909ee3222208cbe78f4ca0d1f6a1c7a26fe58b7b7d10bcd01f98ba8de77e7cb010001	\\x42a617699dcf3b820a11ae702097548b767d7cec15b7163367cec4c55eaa6e42774304ce1b15583725976c108fc5fbf03dfbee6d1340dfb0fa83cc12d9df3409	1678394107000000	1678998907000000	1742070907000000	1836678907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
47	\\x73087f302b691e3c7dcaf94c96bc9a5dfff30db44e3ebb64c9f687371aa6f5bc79e98988f361b8aabac299455a2f20ef8e5e9429568e821587606f8f0c756578	1	0	\\x000000010000000000800003ce8368073df09b2ebd592e3141050bc2fa2aa764aa629e6d52f69ea38e151e4b40200638bf883525aa6c1f4bf849ea8fc92fb293f187a976644c267fdabeaad19affd2af478e7b01f89eab17ddfe3f33679454aaa1194d1d1462898c4d0d0c5e3c79938601e5e0e61aa42bb6a09925c25d4a42717e965b20af57519e9562de5d010001	\\xb6034b788fb4e76cc6c57e45b02e9d438588a196050f7cf6533bf3fff1f7bac113a1bd60adfb2f31bc177e56c12346c2ccf7b5c764d0c9cbf5ef6b96b165660a	1656027607000000	1656632407000000	1719704407000000	1814312407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
48	\\x740c4956eefc67cfff42fbe12bc11fd90fa0df65b5d6323db13e6bc172a77570bf481188f11bc0b81a5f863441dc9d8de65713517fdcd26e0be99ecd0248a51c	1	0	\\x000000010000000000800003c4359e4346350d79035ea337076f008dcaff64baae1bf7df63d4fbda358e284f32d34cd17f3b9031e6f3af67269eff11d700a27c08873f530d62a85b2b1f67685e35045508909963d4d012b30abadde6c606bcc25909182b2f41257952182d722cbb466926de2a142fa575d55d5b6de01e893cbb2799387aea2024cb4c56dd31010001	\\xc3a97d9a7c9e76c7758cc27702d5ecdd73b16ba8111b06f59b0fbd2ef6f8bd877aef619ce077dc785672c65c733bf0fb73b5b20340e9e52c07e7e3efafb14205	1657236607000000	1657841407000000	1720913407000000	1815521407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
49	\\x7428dd411d948f5017263e03308a097672e470a64178cfa7fb7e9f923844de8a4c7ef74f310787412936f7bf560deded0e640063e2de1dd6d188edeafcb7fbd5	1	0	\\x000000010000000000800003d8464545df7e45b4768deabefdff46c2c186c1e2b57cdb3cba221b3d6e6d353ff7e2ff2c1f84fdd8e8908974aecbbe810fada458b53778e43125990f29465c6825bf60a2e49cbecddac5a0774131f192768be34c698340172f9ae0a1de389bd753e9469fcca4caa941a54efaed0c753c4dfdea85e5c206a994ae379f862edecd010001	\\x6726ab29625ed583807634e50235622318efa723437577230190eddd5d20f5fd7b42805be14fb1df4451b0f296dc605921eab3d5bf464f5571f6f8601f16cc0b	1653005107000000	1653609907000000	1716681907000000	1811289907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x7b9860fd52988a2c932c82ea4825052fc54dfccdecd8f96006c5115bdd4d5a1badf050895451e64341b7620c2f0afc221808615431e9812063f4af1b92d69e27	1	0	\\x000000010000000000800003be8f562da5b25e58e9e6dd3e03b53186a73e0536a23a3b365e8589a331378d6e68c8ca005e1e6e963f32bf6b944ba77276ffa780bdc33c1a54f2e49b604f6f98c03034470844a60dbb92b54baa902a1f2a25eb56b7a703e58f73356703ab19b8fbd16e0303c3a45cdbe8071bc521ec2afa730c57a124a4f06c7c5dbb0aa34e41010001	\\x8ac596fa497b07712b5250c58d1328cddbd0580d940be388651ebc3bab729f9ffcc47145792f8609df61f79d912f11bb23f5d74e3fd7dfe599be145fa35d3a02	1668117607000000	1668722407000000	1731794407000000	1826402407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x7d442b2648d398579d05e49c22f16f31c3a9134f512831cadea3f749a95528fb38895ba410fc22a3733d32bae7002d82ca67a038e220eecaef6c20737c82a0e8	1	0	\\x000000010000000000800003b4ab10a25cd985dd4bfc2a7d069951133a6acf782d170899b3834376e36ecea95fa3cddf2ac8d040a6374bb87b6a7fa7fd19e06be5596e7d904a9f6251ad046b47db8052c27e53bcf4194e58ac10e6eedf7ef2709f7749542cc4bffdb4640fb020dee8dbc2ccf78f513bfea931e8cc6b58817c5d820788cbebc33e95cfb7376b010001	\\x96c7df163689f208b927800c6a2d7ea2ac8abfbc3db30f96b944967cda22eb29acc606a9c9d1029c6cc61f3c9feb9e6744f62e8e83e3ee22f3bfcab4a700830b	1654214107000000	1654818907000000	1717890907000000	1812498907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x7e90bf258be056e9e9f011932c421c5837d86da06048ad61ebf8eb482be77ec0ab2fdd4574da8f3f0af59390cc680d20cdf905df8b68c0352c051fa1d2449b65	1	0	\\x000000010000000000800003a5f2eec9afd513bec5f5e0cd2419bb2a9754e2a756e20c68218142f801510e8c94c08e8246285e870ef6a865eba596ac3bf396a10e65ecafd2f6700af6909e234607be35d5ec8368b3ea81e4ce70c4139fe33eef40b0a48a89b3913f0d9b8029a14080b2cc4501125213b1525e2325a3dee7806eb78ee419a5b077f6c2889b7b010001	\\xde3a916cc0b47b7ad6d19d060eec0111d791ddbd4c2b144d80e4f426146dcf78533b7569f7249de975bfc6f6f862768cb410c6bf82628c11a6602a2fbe9f0d02	1659654607000000	1660259407000000	1723331407000000	1817939407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x7f205bb15ba83fba8208041a3638e14add247392d7b627e6ddab46c122d10026cd9c180cf98fbe18ef53d0f2ed1362551d8a58957d0d5abfcf642d1ed36d5236	1	0	\\x000000010000000000800003cc68cd9a29b7d2e7866130c3a916c67ee6afd4d159888506a37773a6ae20a537a57fce4d1cc4c9cdf62ff67aadc3a11402a7370346bedc232c1b41ea73064cd39f65a3747a964d8df883234051278326b7f0fd85eb7f372ad99a91ddd113e574a9257f05408d6b169bda434307036e414fb34d700c7b223321afa812caee6243010001	\\xcd732fb686851c20356e7bc3a7e6499d46c0299cefe5ddec3b16bc835fccf4020ffff2a2c6d2039defd026e4c37882088baa24dbdc23b153b822243f668b8e0d	1649982607000000	1650587407000000	1713659407000000	1808267407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x8538ab4efb67ec1e0756748cb42c712aaff568c6f08e34aed091122788aa63d27a6f95f7358b907897c6f492b8f38cd7dd2e539265c835788f38e795a64f85f2	1	0	\\x000000010000000000800003acab1ef71434c22d290fac9fe0d2fe7f6918a63d01939a16621f1b47fd17fbe4f037ccf4ef05617ee78ad40fe5fbf531be05a2b9b0a2279124d4aafc51d66d67a54496a9ecc71b4a30e7093e337362f66f1de836ecf59ed349929b3bd247c5c4f9f271b5b8aaceee904edd0c83b4343a0ddfea77b58a6329ebf39e4a133b190f010001	\\xf878be86892472be1730b64f2f4dc61c9028b369ae14e4b3729cd473b5cb008225208a76a544930b641230520ba4b3e67ae1c3179ef76ff8733f2320215ae503	1668117607000000	1668722407000000	1731794407000000	1826402407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
55	\\x88a883d22e6fe1bf15157fdf4b73556a6b811b7fded2895dacdd23368ba91bbb84794c700c826b73504ab1ef3855cbc5136b5ef8191443c093019ff65922f6f6	1	0	\\x000000010000000000800003ac8a62c297837fe7ee21874f2b8116c086019266935a65b427a0afd4c07ebdc6b5c942e6e2b39b0d5b0a0b86694d62403880cb3438d06ab87927bd6d01b420c340b27844429f7718049e3c7795feac45b88d0b6db9dd288fc17c67714f9cd9a3fb6de9f5b5eae57c813aa20a290dc98ee6b90d848d3c031f537605c9f81fdc01010001	\\xd2c620d2eb64e8251d83991cf578e11308038f041c5a26284b0bd319033fab336605c165acb2ee7673bf8a4cd5a86fbc512267ef3d98b9d38515ac9a9bec5b03	1663886107000000	1664490907000000	1727562907000000	1822170907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
56	\\x8b5421f24899de0281b065c7d76af6620adb7b59063a2c3760ba761ec073b98069cd9fa4f712a5acc34e2e4966353c0aecd8cf10bf8b6d6b82c4b9e05478de28	1	0	\\x000000010000000000800003c6d47b4b73942098d07b5f2906bc9d277218683fb4019a0080ab264878fdf563795f5941739ff7a638392cb6c08f21ca0fcb0700dc0518051057ef1ff43961cbb82a347ad6da8b49c2055df69ef0dd6967e7056a5ca3d2429dc9aeb8ad5a8827fd9e7169a372e3a106e396d4067509d2ce9de88d049d52aa5526c2dc5af9f25d010001	\\xe44f7caaaaf7f09588178e87e04d480da1b38d3e0080b902da5e136bb78508bcc8f0267af84230c2f1dc366f5c55bc7faa6e0abc86934cf95169597fdc210e02	1678394107000000	1678998907000000	1742070907000000	1836678907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x92ece44c272cf1c96d1b7fc614e2ba7ed91349f7cfa8fd0bb071175f8d6ca6a2f9513b173b3372d6320f69b74297d44fb1579da0f979794b4e0b208edc65ac12	1	0	\\x000000010000000000800003b1c478d9aa3508e2eedd3798876529604c1c23d7cf34a3a131f865275a91673c3804d603cd348cd63255372af0456dbe3b5ecd2ec526f5c6909d6336ac25804f54e86bf58e12019a845ecd7c81a86d9717ec6ffad4186219235d0c2383c79394ae858a4681482feef8ed3364f04281d25ce09955f153ca16d5a72b8da32803ff010001	\\xed44c279b8573c1473ac80323cde774db0203add202ab5c4097423e20a177b849688b7feee4259c37de66b6e7ef856f0698e21b1e22e40dff9b2fd1a95369207	1656027607000000	1656632407000000	1719704407000000	1814312407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
58	\\x924468f85e8c374f9314b91de2094572a06dc1509f7461f61f84be57778c619e94c24e0d21ec48485aef35c72d789ac2b873db8d852619b7e908e1b385f51436	1	0	\\x000000010000000000800003c3db85ff229f81440aead0677034cf96d2f2d8defdd5189085110b520b0fbbb65ad86010d336752901e82e62e0b48a1352c8a84c8f1e9f335a02bda6e536553cf0b2fdb5afe5f793264c4c5556bbc8bd60b572ce591809348934c88532481e7d0d4c8fe55e3c38b9444aebe030776eedb054f865cff76dc998af191aa93b72ef010001	\\x29f13e00870e67bc4545a37090f66046052d1f31213dbd4d4a6e3d314aaff00d557ec5d7d87123e4e435612a3c0fc01bd299a7a844b7c3635e4bcc4440821607	1651191607000000	1651796407000000	1714868407000000	1809476407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x936c36b9810df816848adfe6800446ca9d1a76075d2972099e40058b43bc98af27166b7d11a1ce0ada69d3d35163613cb628511502ab3b582c18a4ff0e9ed28f	1	0	\\x000000010000000000800003c80b7a0ebb06bdf965fc2167cbe715af4020927e8ed723af9e009bd50d0daa96f2b84826ab4fe2ccf9ab57b48d9d048155da882cf58f2f9fc9b769a0a33331c2f9c96f78ab6cda315f6fc4f6f823478733406a976d39246ada6521dd157a3d2142a4b6a961faaa96e9ba84c50766e23ac2441bd3f76ba0a0ebc374662c90424f010001	\\xe02e10e20cea338a1852a806c74833c92eb2f153ed11d67fee880606f56722a1e5870f3254914253d8db5e273278c2ea468dfd22f0b4160a0c0c6befc6cbb50f	1677185107000000	1677789907000000	1740861907000000	1835469907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
60	\\x94fc7476113972ceb078748c3b666f12e21d607419aa37c72b332d157d413edf43d1ccff942f8ea57f9b618e90ccea5b5587b8b7f48a88b923ec7cb1096c0396	1	0	\\x000000010000000000800003a18d86f09d8940bfd82c2ae9f72354a2a278201534b28f75b39fc240893c9cbea484b29d0e1039499faa8072ac6acee4f90a8c1c7da4a2eb781e4187aedcc49a1b8f97c26a7e2295e83565d3246a3f9eccb01429ddbe99325736a098ac46af9ec71312efe13e33901e81f0ac24107f29a53ca91601ead4ec360ebd3432151309010001	\\x3315f1e25301a926212e11cdfab7e1f6b1aebc8187f117e9b808c5f4007d0422911d309d1f65e128df7898f558e920be3688c21f8d625b9546dbb15c6de04103	1661468107000000	1662072907000000	1725144907000000	1819752907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x9cd8d985be50b2f98019ed6d6cb355ac71b44a1c7671e665e1ec8a1b1ae5562bfd114c24a0f1693a74677f372fa93a7168d6c43b9fadd8270bbeb89d48b239a9	1	0	\\x000000010000000000800003eb794f47864f1ab5bb53f5f3a47e8c576544f6d252fea4d1d7f7506aa45d49a04088cbc5bc74c6180e3e0d77dae73b3bbc0da86d2f38e5b60918a78619ae80e63d18afb946530e2eb0c0f199875fdf0a6e94f20a15d8df22dabb4e93d3613c52c17543866754a8797d326d2cc63617b6f3e9ca7e484bf04c2bb246348c8c78f5010001	\\x8acc64071283d25f27f1bdafa335601244a2509d4f50775f7d5b7566ad3a269d5487067247c55a82301efb13ea859d5049f5f810c4bbbe9738c43ccb58753c0f	1648169107000000	1648773907000000	1711845907000000	1806453907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
62	\\xa2a02b29542f8b9d13945b1585f53f93ac941a735679d41d1d85b5e84123fb4929314c4040ef2891d85e8d5fee8f35c010a396e2d732f064852fb76756dc30ef	1	0	\\x000000010000000000800003b766b91677fafc6d755b5f12bd414a45f268fedd310e9bca1496d868df9279db6f20a44490cbf26e57423049672726f74c6f158d3b4f30ae9d290359404d6f51816d11645a8ebd19a182be2ff970c9876c9a4284190c2b2534ac91d6615b484d9ba12c25e62613bb6993419fcbe965d702ca08201c81fabdec676106bfdff8fb010001	\\xabc43e13cf5ded57227d468428d15667e01edc77d756ae8d3be346dc4f8a07d23259ad34caf1846616d0eebae6018445e7e3ad6a0b563c90c1d52e56ce005303	1653609607000000	1654214407000000	1717286407000000	1811894407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\xaee09cea99eb8e4c6f8c0d52373daf7b39dca6bdabed4a36db5dc2a9c2e0c61b8a3a5d41d3497bf2747746b8d2843d674b6b1a71ed3eab1cf11cc8ab1dc0c35f	1	0	\\x000000010000000000800003bce72e1be17d86b5964af68bbfd3497d97e762ec9e7db95c4141c6163dd320b123d435939b8392e83641334d6e6a47acec4d6dcdb14fbe4f613b150092e228a7f7e890062c5c62f373432700c22243f7aa20def51e00db76cd89090ed6ebe8bb9db835a7a31e2150302fd2f28c8753dfff47a5884cf4c20d57bfc14b8fdf9f0b010001	\\xd255ff28cdba996a70656a712e1d10d5bfe9275dd94ee478de91de49b2403ee2d7679c06abdc964774db1b5e0d8570632ef47f97debefa90ac13d087ca6cc50a	1674767107000000	1675371907000000	1738443907000000	1833051907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\xb04c7d17dd11fd7317efaf245dc0f19c568b2dbbcbeaa11e0e68b5d39908f36fb4fd5b252c7317e107e766fcea7fb96e9fcf67f2517bd007ff8cd81d0d743734	1	0	\\x000000010000000000800003d6797e29ae8ded99b3235d6b8c2aa5b0701d9313c59fc6a1e5590767c6645f0415a9809ce7346f72e7042e4f834a01f67ea982d7d6645c1c90d0e8ec9bda1f990a1a5091ae99992d3407a6e1e435efb5f91cbd87cb7e469b35357fe3989f8d715fd065fb6c38d43361867706e5fe92b03a604e5c6822a8eb8c07524a22a79ed5010001	\\x89b3502d1a9d16869c3a8a0640a3769a5b7a3bcf2684f3863c181003ec5d4fba23ca72bd629fe4f83f016ac122c66dc03a2781263a02d907a93cc3d2967f0a0b	1678394107000000	1678998907000000	1742070907000000	1836678907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\xb344202c7a56b4bc2f71bb1bdda5db53d810e0b1cfab4b759abba7c5a1747551dc50322f8b046a34df640ab9bc196b9501c2e5b63ef80b59337ae528cca613e8	1	0	\\x000000010000000000800003a2e7596eb71139552da4343f6b3e9ab360f12ba6f0c82501da2a7a41f77cc8091d67375dfa268e098a88c4a0e3b31ba66accc745e778cbb1bef64337478dec79b2f4baceb434ba8374163ad97fad5817ca8ae1871ac797d4e6b5fc7568e797986bb74b064a1ceef4e0263e830588ac723d70bbb175759b1baee59aa6a1515923010001	\\xb8f9458819bd217960a2b1bd9bf8f7c87130e829dfd9e15cae00633439fed42b2655d49c3bbf1a0a4546c457ed67225d09a855601c61cd784cb34f5bd790d401	1647564607000000	1648169407000000	1711241407000000	1805849407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\xb5c432475c35246cc303714700f2f2a9f6e208d6e04be6ee3a1f9f6f275e5b2028104d420ca1f46d3b8eb53de4bb62d01fb344b3f5b8e4ef1aef221ea2a4687e	1	0	\\x000000010000000000800003bbd601af9ae8c31bccc074b573c13a06e0a8b463439252a4f7e9979c37f0d376af0ddc8866ea7f3536b689c04b1aee9278092a30309b3a61d47a3fc0edea190e5ca7db3a07820ef0296b47663867304b067929a8b847f5c065013dc934ae6f5e802ad9ad932c70663259f89e71459d2d6f98a29bfc6cb5577e6974696293e303010001	\\x2b6964ac34b9809d1067f7ba98d5a897edeb6478b6a139a0fcde523c70fd20b203a3c1e272c024bc3f0d0283d4ee46bc6248e1993d4a89f9089c58b85e32c702	1674162607000000	1674767407000000	1737839407000000	1832447407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\xb5fc9cd44da20a88b5dc0b6fa974d8d86f30a5f39a4312be5311e07bd75b5103a34a2a9e8fa008fd788bce4a835836bba7e6cc6696f17a92e1dcdb64392f457d	1	0	\\x000000010000000000800003aed6eb5142930a18156a228bbb50b47e621d62f4e874bd79d207a536e1adc0b7b8d3ae12b5d42f9a6a09d25e393ad6d5269cb6ee9f9bd15bde781e50427289d06730ef842ec0fdf42e85caed12c23b1be7d01c3b29b0b99bd975cdeb9c3d34a450e31d1145c2ceb7ee38cb39993e9492111f3df7cc88359a87f2b3905f5175a7010001	\\xaa6c891a28e99edcbf35249aac8cb7b5ee57292db6111052c9733601979718aecd573664c713ed363a25f5b37cebafcbbd8b1377d9ff483b2f378ca827c0fc0b	1653005107000000	1653609907000000	1716681907000000	1811289907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
68	\\xb88c85c912ec5420f7149a725fbbfff5f87cf93b2e156f7b2b412b2a9530f0f44a9665e8a9b674e3287787ef614dcd376e09c155e8c607325f9315e219445cad	1	0	\\x000000010000000000800003cc35cd6a2e115cc59137ef2ab74045b613d2395cb986c8a7b203e98e1d3785c053c30046ba90adec847ab6ecb5b74f90c503429c638eceea248de9803bf8d383d31f0f1c7f48225c897100f47be93e1285d7a276120dd11897e11dbe4a237c72a23e047cbf096c38f7cfb0d36010f90169bcc5f7a51f0e6f966be30b303f3963010001	\\x714af0aec99eca9d49fa576462477c13373098fad70801757f19494a1b99d2a7f0b625195455e6aa834fcc899b8ce1388f76e488e8da3f9687b6c387bc166008	1672953607000000	1673558407000000	1736630407000000	1831238407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
69	\\xbc2c208bca76c9510afaf343e4868e41c53a8cbde23c90be8246aef17b278358b279a07607f9d8f8bd616d7788f5738554ced1b04ad841f5b9626081c9d80f08	1	0	\\x000000010000000000800003d5467c1da9f581100d04978e626d1655c7ae85d488e9e24d287ac3b3d7a8ea6f33699b16297d1fab809bf5ee225f5a9365a6c3d77e245f54f68fc140768cf68d3513d73e58637985dcdf2f67336e126adbaa103c4ce5d99da0d54892d70cb93388b719cc204317a6f17b94be0d8d374395889a86ebbeef6355424b16dbceb761010001	\\xbeb8205bf9c766a27c11ca19d4a2dc585c6d753f765fd7732194356e6e7eaba3074fd68f89d31789bd9117f253a4ff87e1c2081a33d510fe4db084ceb2ba3208	1653609607000000	1654214407000000	1717286407000000	1811894407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xbe40dd2c6073ab89d8e757f1fbdcbd46882e5b4a056809124b8f0acc53e3441af281e11245d36662a06317cc2f471fa9f40e7c975a6d29603fbc0c8d06788ea7	1	0	\\x000000010000000000800003be95a0177f9013714b6ae24ee3cf2a473cc88552f643bb8d00bb07cdb66d1dc63f96647daebc0e3f901ed98f8d1dd939f185984ea659046fd336eb7aa5b30574a5d5e5dce6e755f6b78c93b44b4e8e4fbd4dbd419d8e6b00b876a9fadc8b82a1cc497a668c3e295eea35650b7da29e1a236e24d468fda2ad0dfeb14c5b9390fb010001	\\xa380635f3cee124eb53b8433644998f22c438443e9799a18e485f64d3faf763289c401eb43017f8d2b45cbabbd15d097976301971fd0047f49ffd4ad23b8eb01	1671744607000000	1672349407000000	1735421407000000	1830029407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
71	\\xbf9cd0ce00e814e235df630e069da4669c248a28503b220792c191ce0f4c0aa591bfe526132a579b1af806c8042262a97ea16564f6a303f86c60d3c1f867a19e	1	0	\\x000000010000000000800003b942ca9f71ba2b5a83dbca41cd2f8c660380f4a7abd3916bbd7cfaea54a2a4421641503b4d6b3f019c6455d796dbde4803e7426f2cd0c30eb971e8eb527a5bb200c0628d1eca343cbb98c12b0dd74822648860b81bf9da63883e9654b2753b975d4946f0dace3f004aca2afbc70d5621c5178d8082de96de8b9d3ddc9eea7eb9010001	\\x65f4498bb11710a455ad526063928339aa885e08d17422fe75c7d25e23c62c52a764dd95ec704e0e3d494cb0fe957659b86d9a8a40bf8c7c62fe817dabfd9b04	1650587107000000	1651191907000000	1714263907000000	1808871907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xc01028504ce5ec2e2542bf9ffa3f0f1d97e2f774d55db6a919c226543b5e867ec99065e13dd72969602e5f4ecee8c823f8940e0d52e57a9af2a0f71da3c5078b	1	0	\\x000000010000000000800003d369b6b23c863f671f4fa72fcc5d915606e8090ff2428f2a310cf378f1646d22ea1f7b154a6f9c35fc4c86652045230093b4bec5227dd5334dd38123ad387c3a3ff8dcae47314b751cb07108012a3f91ac32aea566876c0327a506057bd1c230e076e25c71154837cf714fc3028d332bfdc37078b2a558ad550cc9374cca3b59010001	\\x61e876a6586ceaf604b6b819f8456a5ed0252ff06ef372b3742407f469c573e083a60288f998b91c746262d1eb0e68be5203f900e99cdc0bd5964b6d124f710f	1673558107000000	1674162907000000	1737234907000000	1831842907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xc1b0ba57b58de457d6179f731e4655518d823c1e6186df3fd49033d641223dc2d0f0cdbc232d2edc0a8717edbb42c5747458addcdeff88029d89431401709ac0	1	0	\\x000000010000000000800003ef45c8b9225339fe57ff7a2698c8677f6e5d3fa6620dee09e481155e0a52ea5d7214bbe929c861da677d19d0acebe75359a0c91f114838f981dcd5ed3449c6da4666dd12b32316047ee69ca29300fd8e940d7b124d0c054e25154ebb129b4a75a9ba71ff8a35534e0df7b74484258bdec01d7e58cf7c4fb882ac14a432e7a265010001	\\x214c113a688f9508a627a6782c87cb0e643c763a4903c9d695a05c8a9d3c21d0bf4a5f8c0cac179bb0a0a3654749beb556f452dd2e774a8902eb9389df9a8005	1674162607000000	1674767407000000	1737839407000000	1832447407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
74	\\xc484193507d2f8f2f571b7b32b1dc0283b8a16f384b12789c828abb68c7ce8875c296866f53ac2bb53b98de09e9d43554726e690a440e235f0e178a568788901	1	0	\\x000000010000000000800003eab722872fd5443c10a0180b592f5d7b32184b7b57b7b23191078785082338d75f344168a5c31f5bc304c544a9cc97d089ef00d92a47d2e4d87ac5ac6943ef61f8eaf4f6d99547493a9225f9be7b050c4ee97e43b34d0b4f970568cf20cb33f8c3d35280e12205e6a64fafb6b5b270d219e5e7bf9bfb766c93843911e2e30cc7010001	\\xd8d06d8fb0af2b0f9073b1e145b75587fab829d68e2048143af140ac9b9cc4255e3bd5e88ae9b2b0fb96114424d21eb3f310ca22b7f3d8513078d3342171d203	1659654607000000	1660259407000000	1723331407000000	1817939407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xc5886a7e518784af85f7f62c2cc5e6bdf2f8f869a04fe6965831962b93809b4ea65c72bc16f9e4663b9cacd9397f98d99ff6bbb3ada0f35971ae4321dfbc1e27	1	0	\\x000000010000000000800003e0f54cd3a2bbbcdf3392ce5e12f74f63bbc02a908afc9e4ffc85a29a861b8e0b20e5825af1d2166c226d876602af9a9ee5539f3504ac4986a0acaba396685c854909e5a9636a120f73a9ad98922086b38a175312913743e68e0b66a260701cce12ecd4fb0519274a6144103a2405a9f7ba8d264b2dec2f01a05ab16ab59c590d010001	\\x82cf915154a61c73173cba14f9a57d5f431aa2f85828334c65b7d592d6161759520cb147802de031a68965f3827178409227e5d22cda87a020334655abe5bb0b	1653609607000000	1654214407000000	1717286407000000	1811894407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xc884dba13c49c16b0cffcad5e6e38b11ba69dfa332534918b9710c631afcc65247fe72de9357a53dfc0d7ebaa7c5f0ec71b94a66a049d949af6958c3cf2cc380	1	0	\\x000000010000000000800003b20efba6de4d906eea618e8c69c8b96e9d4b7e09a78ce8790f1c6bf88c887d37c00e9798e6b349d637d8d2a6bfd9e9479f5769415167ffb498ace2737a018b6b68f0a6c738b0fd0fd0e888e870ffd77da293eac44bfdae86986619ee5336ae763a1db474bf225ae45c341e0ea3fdf6cb487baf28b28a89725d10c4d5b3212f77010001	\\xcbd3fb293e1ec6ccd0dfb660bf77a361eb2eca7ed14172d80692b439ea910b1df233a8dd2a94828d73199523230f91e5b2ef3da28e7ff54ddb664159d5efb500	1667513107000000	1668117907000000	1731189907000000	1825797907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xc804eb384f7a6f246294c767fe15c696b7fb1bbd21cba59ba1e91b1096ee180d6c53bd85cba42eaac10b6719e9e216dffa66153b0b6a03e539ed57cfd05e825a	1	0	\\x000000010000000000800003b890a8149cad7592b5f5a3d0ed25bbf60ad99a3b61a5efe3338c313dbe38c9c672d937519a40d53208975274838f7817d073ce0459b6f48e2687081cf71a20863343abf95bcddce925b3d778dfeeea244ed0ee14bc0756fb76a8bfb73a824a8a7e6dc9de8df84c18fce5addf0bd7b2f4788670b0f9d781a1602c19b5e8b854a7010001	\\x712952e207b11af83fc0a5f21a305be50b98130ed769992d5228c01c27e0681a63e5b605d8aa8ba33ff91e05fdf73241fccbe65a5ca9941d22353a5621726400	1654818607000000	1655423407000000	1718495407000000	1813103407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xc90064e1639cbae55c93db8e69a633beaaba6cda1bb6b70562676cfd4530ba406c1e5eff44fac2146fba7ee8e167b281f31559a669b74f4cd35965b741d47925	1	0	\\x000000010000000000800003f6652cab12a28b29093ec90e28d11819bbee87fdcf6ddde36efcbadc69c8c00aac8466969795efb8c2d221e27d8f7fa5f0d1fff59a69540436d04cd9571becc88bd9498a58d36df9629b17c05991b9ea8ba767106f6f49c61c958df0a965815dd08dcad7a1173a1a7e0a2911855ac6f4998c42d18785e31ff04d6317dbcbb0e9010001	\\x91545e9519523052831a59dca11857b2baa164834490fc57b10eeedec46b40dfe4d1e7e747eccbd5078f6497eb8a5f9ab0f0d95c68f5b69581d991a688ba0c0e	1649378107000000	1649982907000000	1713054907000000	1807662907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xcb985ed5167e22d0f9faabaa35a5f95f9dc648581fd92002e85ab7a200fd147d1df54d4daa354e5f89e0088386fab36a1932f0cd83df6ee39d184dcb9443f017	1	0	\\x000000010000000000800003dac7d07df29d19645d768aca9f1df18a04b4eb7dcfc7c80d077d57716d83b67d2fd62c03ec7bff1f3c7a4111f4346fec19165fcbf64e936481f61f96e1fe4efe8f59b5b1a0aafd4f3b08012f8a52daadbb0bb4d15fe55f89fd8c42f72a33a5e1aaf3a8c9ad4d27962fab36bc72048dcdb0af17caa3de8a5ec8c3cddb2a28de9f010001	\\xbae31355ea02308e0f18bc28aa4317873de01c7f021243c95d517e706f9ebff5fba7ecbd13fb4ac4ab8a78e88345183f0322c6ba472b62ea7544f4f13a9cd902	1662072607000000	1662677407000000	1725749407000000	1820357407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xcb4091a48d8d67389d5bc1f3ec8acdaa29130745a6390971bffb5c391d9e15e299c3269c7ae88fcfc14cc4a8947f0143f08513ae7fe1ce361b1216656024334e	1	0	\\x000000010000000000800003d0f2177a85488f150eb282e9e0ecf19ee7ae3bf550b9c62e96d1fcb454954b7ce7f59bafc4879dc931f0ed814d668b068ef2bde0d1ecc0779a2357b4f0c5b3eb5d4d645b4cbdaf8361037cb21e1ef5c3eb8b33a46843bcec8f34bf8df490f7437bb470a2d6cfcfa26c0c3bc8a29c93277c2c2a9368d788a656e2913f684a85fd010001	\\x9164612be9353d50bb0264d92cdc1c36ddde8e4c9bc863f9a72218cc60ac790672a1889c55ea4b3176bbe6108b037d8a476cbd00c4b0a9e401ea0bf61fd5e306	1663886107000000	1664490907000000	1727562907000000	1822170907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xccc07a67d94969b3b9bcc2ad0117d688d175d8412de8fcbd482bfc13d91e43bfa96667640a93331a431940728ba2d23ed915a5915b9f668e0c9ac26decd895f5	1	0	\\x000000010000000000800003cef8b9e0e029c7265c75314c7cdc268a6dd09d92d175d9e358c706333e2133c13145206e35f51e903b9f80995116a098a047a5abb56c8b1033b74241ece02c977c0fc1fe05196715515a5a443e37eb83f717418e989b443cef8fbb9c09f42b6ee513d7738e76503c49daaf94daa4b8946d59cae3161c6d539670b58ecf1d063f010001	\\xb078139e372e75e198c4dcf861359b2ce6b1a2165a103a5d1a10b1876b742faf3d275f11dc0128fc5f2360471d35adde5bc138220f7d657fe6681bb21b1f410b	1660259107000000	1660863907000000	1723935907000000	1818543907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
82	\\xcdf8058aa4de8578da3cea5d69f1a5966081e4889139a69dda215f78ca8d2e2ba4cbc98e7d150d48154f61558b0abadd55ff4cae2cdac0936ccd4f7aa64ab552	1	0	\\x000000010000000000800003af97e4e8cc518e1cdea8a0655c0e597129bb24d7f80b4c84d1b45d897ce09489a4f678fe06282410f5348fb52ffde0df1b129f875c65d9b9575bc1fde1eed36ff46e32d9a8be703358f4e817a7317293449cc0f09f885ba69c9f38bb6db8b5e3793832405552b8e934e4aa45e245e69657ffba6fa951b3ad4f6b965a8c0b640f010001	\\x98805948d0ccc481d77130e16938fcdd7ddd809895309423ef77938f677f142038f079009d97f080ed156988b779e261e6e574bdb19f93d24c7e8900dd089203	1672953607000000	1673558407000000	1736630407000000	1831238407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xd0f0ee1f437cc1b1ff26cddf693d1d2eea92014b0d02132ea2435becef4c3af04b7fcf26ff3100852d56b3958d48d06d6356156e20f68ef0cff950a712df6a3e	1	0	\\x000000010000000000800003d8e9284c0643423b9b61bb6eafb2e39c9d602355759c84e39a1cb4489e50705aba5dd3dd9af646afa84f91b958f045b8ce40ae7e2f9d8b64f21c361a7c0e6be45ec96ceb0487880848a78808ecff7fe251eae2e71ad24f1b7ec4de61b1466d523bcd1a7669131f86686ee6efbd2b36429e6a583082f3cafeb4d21b93fc678ec5010001	\\x8c32a8cd617046b8c9b7bf7438be562126509e1c2fc55b317f782580d6cffd8693907585bc05e7480c4adc222df48c148802bd6a240aa8ba47fdc696f3baa50b	1668117607000000	1668722407000000	1731794407000000	1826402407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
84	\\xd3c807982b3d2b5696be9b14e4ecdb04f6dadf923041988de5b0ba172cb4676cc2e4b139fccb777213b61c5554e10d2cd67e85b57093376fce1978153fdac342	1	0	\\x0000000100000000008000039b21e927d76ca019835a40b933a72c5cb2ccf3a9345c56ce5b4a1c0c98123a3ab8355832bc9035022b7949ae862447eb5d7abde87ab19ca6fe06a84cb1ec723805f2edd5faa751f0cad2f079a0d8198c38c739f800f17889332e59b0e41c9ecf274848a86878e9540b6ca65a832ae44bea4e73aa55c167e876306ffaa6716023010001	\\x06b9c137294369fe4e620d579eb1798b0a9e5ff2afeb2df2631cacfc63df459318419384e84c604c7da776cfac6e8048b9a24bb4bf95c41f00b581f964e4f205	1674162607000000	1674767407000000	1737839407000000	1832447407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xd7c82dbf4e80aab014b558aaba84a0e3cd37928d0681c4384e22aff07394a374dd694687ebacd2d7a1f7cbbfde2d371ee4ee0bf045c073da77b56856589aaea6	1	0	\\x000000010000000000800003dbf12fcc18a1ea68c1c7705a6505981f8ed89095dc7eda7410f8fc5a9beb0d1a65e02bc97a2e758765315dda1ba88cc3e3e4ff2f68db60cfa4ae315007dd86b6306d7c01fb3bdede06a204de409f70f72f8c9f19ac10e55c160bd50dc2db9dea3b38e6707033947ee7aed5a2b1f351257d277ce4f356884c3389ea13e6d15619010001	\\x21e88786dbd550398ba246bc61fc777d01c7e6890fc967c8f21d185a07fd9aa38ddeeb5fcb48561e6e189e212eda1a2f83a881663f8a25ba32f0b7de7db7eb0a	1667513107000000	1668117907000000	1731189907000000	1825797907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
86	\\xd7289f848b1dc8f30d9bed0b62e0921363e09a2e7772a7802a1df7e27a3599d6d07085dcb3a721129abbd8273a8034f160cadbcf32f6df3bb4cfe5a8d9db4617	1	0	\\x000000010000000000800003ecca627eccc9448f01dcc8636745218d5358ff9366f39c11d01e0ef1eed49fe4286ff8c1a07ec2b9f959b945708510f643960d4086e058e18d28870dfc1be0c99fa76eaedefae593f4580d8d2834b7580c243cfda61288b0d310acaa952877d468f054025228be1bdd7248de2b44e8d5642820d9cd31357132e6fd2326314a0f010001	\\x96be77bc260174ddb4ad4e25d53446c3f39ef163f2c7094a4d298f924dc64d7a215feb8b0eb51586795f726c9e35ae98f6cbe7143be31b5083f87d41a149f603	1658445607000000	1659050407000000	1722122407000000	1816730407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xd72424a5d9ed0b72f8b6139ba9d31a644a4c9f258376f267f0e80148ef2acb144ea8a0d847933d189642fa157720ab42314a23e2173ad9c16369ddaba9f65c1d	1	0	\\x000000010000000000800003b32f2069d347133f6539110a7dae572234e851dea2c3476c1b11ea17a714035168061fea6491cca6a0dd84d547c0dcdeff91e5daa3b081bdfd6dadb71b86c9f3289f6ebdebc4caf680e1e5a60696846fc3d040b252927194b59fc0269c48c460da209f77c027f50f051f940083aa2153db8558903f49f5f7b9eaf31dd2a0f249010001	\\x20910b127a2cb519e86a6b4a91cfca4b285f99bec0aaa6d76283b248df1939accbbe4d053d8ce618056372e718e06ba74c780807fd407442be592b661a500207	1677185107000000	1677789907000000	1740861907000000	1835469907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xdbb82e795c7ee18df4f98c693df8ff36ebd28c32c3c329d7053de2995d8919b7b9d2dfbfbf7a88866b7cbad754fa802bc199e3a44ce71143ed4c8f6fd2f6750b	1	0	\\x000000010000000000800003ba2bd70853cf73c1e89344a32efdae6f34ebff1a6145a159e147e6f8560e46123bce09ed33c397d26db47d56ee7fdb3bd80443cba3a04893722370b2de585653148a36871555da5e0b8f8e856aa783b0fa22e4370c0b15bbfb0c02dfbe40476bc56636d97d54d5d0ae438f3a4300a5f1462b635048b367f0ca0993ade9d9dbcf010001	\\xe10f42180a6d151f3544be4b79676cc1bba3fa6c0e332943727f7a5eb273ba42bb848ef1796dccc3061bba619239d7504c3cfec22ab5b6f4b95d6bf31149c303	1648773607000000	1649378407000000	1712450407000000	1807058407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xdd886800f21e39918da5e5ddb18a121459ce77bac242506d4a8d3e945d46fee1a988ad453568f775ea929edb3f3487f3cdc2ab297274ac04a922e64d4a3b6c22	1	0	\\x000000010000000000800003e0465113deb0b3a7e1f610dbdc91675d4c9b23426eb408ae6a5f47e3f2a4b831e8ffeee1fa7b89a630990caffd87ded557065dac78742730b3787c67a8deefb631028eac0c2285e268edb0aea8a8321dfcfc71279a9c4cb005e0353c2e0478f60200e7b0da100cb01e30e851008d9810830e923ad79b4c59d978fe524fcf74b7010001	\\x597efb02167fb01f2ae3ade41b3660d2ce93a3eb62790a1e9a5b71f73aa5696a36cc8fbf073f16471756845e1e7fb1c489c71e93d3f9ab0ca26276442ce38502	1657236607000000	1657841407000000	1720913407000000	1815521407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xdf7ca85b580e6c517c907c450c338fcfc76ae73317c126e48bd9ba2977a5de3ca08b8832873f306e9d9d2bac91273d749ad335f7942591c451ff136e0dca5b91	1	0	\\x000000010000000000800003a9871e8f3e7bd4f9cb070a44fea39a0d9400193ce236263b016f8c95ddb0d3d1c5b7f9a08d3c82ccd58638b487e687ff45c15fd406342a040a81f1bae63c22c94114c6a56920d98c7a517f289344a94227879b76c28227b77e39e80a9f26ac7b544edf1894739c9a008483068b65ed08b381a442c96f746d4841806bf648da27010001	\\xce6393f907aa58f112ed9c0c72a11b6cb47ecf1e8eeecd7a78b2c915ca7e482eed11235c5dd56cb39b9ba1def6b07120299d29b5a9cf64e7b683afa828e95b00	1652400607000000	1653005407000000	1716077407000000	1810685407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xe2a4c409d9eb472ed9ab8c3817c3cef6b7ad6e4908961408c17f0af0c84b139c96b65859cad48b4e3a2d5e1f72eb5235be7eb6ed6efb76617808c5bec3fea9d2	1	0	\\x000000010000000000800003bf21371dbf9c12fc44ecbd02098fe55789fc92c93f4c24b958703532d2e66af3f3bf917756ee6220dbc6086f99c1fa422b99fe378cf8e37b16483647ad9ac81106cea76a26765e5d58352494c292da54f6617b72284643e712f7895518d9904cda5600c4556784d85db0609a54c41a3efe0843690261ff0a8e18b66e26c91767010001	\\x41e6583e42e6c0033af4f3f23e53a0f970486af9c0912a5bdb98c3d2af856c3fc439c17e08fe6e50c253f9b0f54f34f8f1aa76413c3d6931dadea59e40ef6c0c	1664490607000000	1665095407000000	1728167407000000	1822775407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
92	\\xe504becb11bf7c8732c2227be48d027fd89355864e29b5763bc6a7624f07c0b181fe88b19cbf7e6468299c50a0054ee81212b661c70e817aca982ee5af6f126b	1	0	\\x000000010000000000800003cb79034bc454760b6eeb79b04c13d7eb6513f9fef8f4042e6ee37fc7e440e098dfdbcdd03fcd2cad9516440e8a8c4c23f4bfec232ad13478efdce8d7975128681ed85650e1c50404aa21b091ec9caaf6d48783ca46247c2a7f2d7d1f1fe5f5c1fa8566cbeb4b7d8938ac59ef21b14f943ad3c7e345c7a5c907a56e2e90c2afdb010001	\\x511eab0bf115b0a90cb262aa5e336df273cae8314c493e27af86011eb9574d1a1117a28b76135be959aa97b8034c35efc41570806464f8f07520da9234b94106	1669931107000000	1670535907000000	1733607907000000	1828215907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xe7bca192d62fbc40ca46fd890fbef0766486ff7b27ee374ea9e4fe12923f5d4189c71a3358ecc0a69b0c08ef4d41bb906cc5ab25147d4e26bf2e3bc33528cff6	1	0	\\x000000010000000000800003cd6f710eb4790b4fd6ca3d323f92fe6fc299f762242a2d5a9e44658331411ffafe43019d67d9fe36e6cf242acbedd4577415d5dfcc49a333a0ded4376e3b852295552450eec69543f75f8b35c4282fb13b7afa4a1a58120dee1c25b3305fd3e86acc61072977f88b0bc1b95b1ba860c644e78c239d5c17ad7a391f73d33719d1010001	\\x3dec157c4b26d1beb644da4576453a3f53b637cd073872f219fdd0b56a07bd256a891243659b99eabf2c6bd3ddb3eddf5ea6f5fe2e4e1b0f9d2db0b564350e0c	1675371607000000	1675976407000000	1739048407000000	1833656407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
94	\\xe7ecc04af99b9669995710e04289139e8a5500a5349e490fd55fad5b409a121eca299deed1c8dc2d128f2a21c3e2d98fd07e2d79374eb95beacde7b07fb1040b	1	0	\\x000000010000000000800003bd1ec3f131442501a8680299819bdb81eda22814f5c5299bfa34afe7254fdcb0033e66588ef6b22f7eb46bbd5d46c9c8d502759077693eb000bd1a6b64e6e7c5057e1e3be2d5b127100eb555d213cecdcbeeedac902de87747795fdcbf4ec9c5e0eee08cc5ea11ddc548947ede20526499db2e8a0a67a0743be449aa24a47e0d010001	\\x1b702659ddb871f50bbdc8c2e1b698c51c3549ce438cad16bf14934e6c1cac95aebc0cfb3301d64a0714dec109dba4808785b22818726583dd740287d0d9de07	1664490607000000	1665095407000000	1728167407000000	1822775407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xe81c1e7cab5b51a2489f0ec6c2c2a7de436dc56699d45ec0ee3907596271d5d78ddc8cefa815eae420691ad84c41371481b0b0a8562bdaec418a687371ca50ae	1	0	\\x000000010000000000800003e90073837d906b4086c3103fb215549f3f5a4ab9d6afbf6e147e6b65fa8a4a4490e90fba4b5eb9d99f9e4133e2853ff1949997ff5f0c5a7bb60387c8e2ca37b2997b6f86efc7612585eb5a0df7fb159dbe0c3ba81369ab4c92931d89ec9d010818c8f473b0f51d73eda046daba02cffa495113c37607816fe8d6953d36a3ec6d010001	\\x14ef28e655541fc72adfdfd7c9629222484788253e3ec659f1893140b35a929d59547329bbe5ccb47c0b060615160206903ea2a043d90af5ae5abf96d0ba2805	1668117607000000	1668722407000000	1731794407000000	1826402407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
96	\\xe96c7e6849a60316357c8fcc520c3000afb94d981a5631d7d40a3d6a523c0a6132fb9ffd524b53d8ddc28dd9f1e05c69d6f4bf5d6e80b53dc37bad4715a08b54	1	0	\\x000000010000000000800003bab2f04c95c62aa0d3cf66ab109e9c1b1fc1b5007e08901d253459f774435de9b5c91cbf043fdd3bd04db5b68bd3b4842ef745f00a91560cdbbca247ac3e4fae9e1121496e3dd1316d97cf8ee098453d70b3178a2598838a3b625d7bad072aac888f97baa95989d4da42985ba44835680c1671783215f63f6e19e92e869f5cc5010001	\\x1ceda4a807dcc9f5c267a77e81ba9a9fce4e60198d566cf6c172a8bfc227bd3170b57c7f78627ae50b69bc7126bc4f3beff61add1865a88e662239b279de9a03	1672349107000000	1672953907000000	1736025907000000	1830633907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
97	\\xead8a4095ab8399c7192cd6b4d21d8805af86212deec95b6147b1930aacc0b7fae98bd17d5941ed9559f1723aad5f1d1492c0dc88d893b1c71123dc2a4a11f80	1	0	\\x000000010000000000800003a48ae2e877a5cea28541d51f9874822b181ee804426965cf3fcb1a74136478de294e6ea6476fa84bf290f65e7b9e20e2c4441b507b688388fadcbd6fbeecbdf5e1a58b95fbac177c44d13ec5c09c828bb7e30364b82dd589d7b42234c964cf6a7697cfdf78cf36490dca55f375b88eb0222e23069eca43f288cf0d1b248c7767010001	\\x7b7b48d3a79569bb5d51ebafa758856f843c9697b833fc59ea56325ef3f053267f1da291bb2e8f5b49147af317dd8f137353a28a39e624bee697832738ae390a	1668722107000000	1669326907000000	1732398907000000	1827006907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xef548556eec3848006a20443d50bb4a1b5b21ea476137fee4374f8e27886f5e3d1d9de0c35cc5358e12f98e8a0b1dacf8364426ebe87a9213cd410f147a10b38	1	0	\\x000000010000000000800003af610485989dd29197f0bb5a6f18e567fa09e2f21a89fd486e7b93944851d45f6c74b098efe484099e72c96420f904ba7cf310fd20e140d6a1b0b6599fa3ff8fda675e160a64830f472a087f07e53e1468ae399365fb23e956ba61d7cf87ddbc97577378a1882e452fed0ea40ee4b384ef42e68ed960b50ad39af6c45bf9fcd5010001	\\x395de5fd20836770b6ce6108cd180145eb19a2e30c6b4d18c2266321d2834018d08a850cb22f341bbec3ba7567c75ab9635e991f27c11233806e40515e017307	1660259107000000	1660863907000000	1723935907000000	1818543907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xf1d0c692104a310bdb03b26e35a29737defb365a546218396d7327130e9f2ea6c3c7ffcba812c09de45e9fa9f7bd318594e8fe1f08930091d2e9fedd488f9490	1	0	\\x000000010000000000800003b2df135b9b562b7927ed26899f5799066c0322120cfb4408ab492e25b55630c7abed4f7a27a3572acff1fd183ea5021d92b620cb7170764009bc42e8de2f463d4d3e43c257ff071d5d72e820d8e32135d0a85296e50a50c5f5a64c766b1126a6c5b355689f7dc7954e374a4d52632e2e705adacac1e51447dd1469bfe2afb8bd010001	\\x68bd835082f8b6a3e08993a594b7f52f2a930d1eaaec977e92c9c51d3173a8a94eaf3a63d881d0ff56da673700ca45288c85946534ebd4120b1d687119f4b405	1668117607000000	1668722407000000	1731794407000000	1826402407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xf17c9b7e12b2159968afe0bc1dc7ba5964f26cef86ff874e464b54d9b7c62ffff0a37b2875ce165798131c72da1739395b4d7357266f8535d53a805d2ca0cc99	1	0	\\x000000010000000000800003bb7d4ca4f289f1a5931beec53d520ab8f86fbfa937807252765bd8c9875119e112e1afa642281688ee661a6f3d4dd997935e735696849e04f1cfa6eb8a556c4de6a8529f0f4a670be4ccecbf762cf1e18b14859d703888b04c7cc1b4c539b9b77c35e7548121cfb2276d6b8cc699b13ffb3bc8ef86c15fd324b3bc48c0e59145010001	\\x4028ee3dafaec90d1acc6ddd2639d5c67d4fb8eb59850d3a46997776f9bfe3df111cc6e964a3d4e52f21de268c0609e56a9fcd4b6f3167571d778821cd5f590c	1666304107000000	1666908907000000	1729980907000000	1824588907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
101	\\xf208e05d013f317a3748a646b14999d80bdf048fbd5dcc231367a6a82ba6c9c79165940f00e11dc971f4680caa8edf95fd885950614093061ababad1bdbeb995	1	0	\\x000000010000000000800003c03954428f9a9641ea0c8f7b618edaea0423908cfbb2dbdb17ac7a714308db516ca1acf8889bcb47d27dca8b28eccf1b04634222e114eea7e4b0e2011834c60c089d544ef7744df8a1132d93537fcee9608b36dafe6497c846cd25eb8d570a85fd4898d7f41ea7d09733bc22223eb1b83e9f337eff175df09793f8bae02c9745010001	\\xf0849f362d15c22c99b0f9caa6fba43d69806f01dce73331e81404e21a5562a8e0ccdec8d3e2958f585156ac07cd3b0278428604d49abdcbfa6514c0517c7b08	1671140107000000	1671744907000000	1734816907000000	1829424907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
102	\\xf3442836a95e5096bc5415fe4773a0912d68c36ce5ef42b22fab3acfa62c67fa679bf6ef39fe8c00aae8c06ec0d49bd91116026be0356b0680e85985a2211f02	1	0	\\x000000010000000000800003f12044b7e0de46a8f8066139bc937bfdcd7f28511413d6fd1a7bf0f22f5371364a581acd8e6b1c8a8553d663dbc651ffb5cc6016e5cbd71eb1bcb68348431260c0742997e26c412b13c97e1a62e2cdc47a41d7a235bdf1072d7dbe8f4027cff888bd7b36780b702c32d91c870f575b025648a84185c4352c2f815c431a17be9f010001	\\xf8c2dc68dc4516f4f33e117fbba435f8f06f5e8dc1f34c00f959a80d8b65e97ccd322b705ff02db9e11ed6bebfb3ca28abcf99ecfda95ff9e838fde44aea6008	1648773607000000	1649378407000000	1712450407000000	1807058407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\xf4c401684ae21ff285112fa25cf4eb860bd5365e93f421da7cd961d5b0d76216e37f89764a84487fd409c4d977aeb1b1f10e522222ecdadcba17164bc0fea74a	1	0	\\x000000010000000000800003c7d4aa41ac40ac9358ab52efcce52574f67853035b042bbb0447b41fc85fcd0760b010b87a0d6920637bae144f95971370036f99608da49ee75db88a594d78236b9ebb430973b4942b23a2a2a8359169720ab2ab03890eef234b2270f2d38406d5e15147190dccc38ab751d27fd47299602f1feda7a244d39816909342bdf1a7010001	\\x7dc93d62adea40726da5e24f6438f8a4f41f39ed4451f10657435d64518408547d9f1959846fba6a7292f5312141b0e84379c748374262dc74378e593000f00f	1669326607000000	1669931407000000	1733003407000000	1827611407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xf7ac18f94c2f761196ee8e254bba7590c4b0a83787ddbbdb8543c3aced7000719951adb72113f23cbaf35bb14b19a1ed5b8d765b6e8253d54bfcacec964ea8ca	1	0	\\x00000001000000000080000398bf1aac1178ff0d7c3368a6853cdc6b293c972c56594cf32e169e32218e207cb4e58e420d9415a16b0046b8eddf7df8f8366c26d80e07e66351c43a072098fd35abe04e6301b7a2354fda6ba97f2262db2dd0eeea1816d5dcdf5f9f6db6af0294cc5bd354e2d0e0d19994a893894dce211bbb24a8dd1ef4c5853d5cb3e8de4f010001	\\xc4e9f5a23e994a3c454997eff2a728c2dfe224ea609dd859686be700f790f3b76ecf0f99c0cb46e31d7ec88ef3297b757935429d02c17a53eec812a0ffdc2c09	1678394107000000	1678998907000000	1742070907000000	1836678907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xfa3427effa655dfc4ba5ce7a127526621dafe1924290571051ca5bc4a704223ab259ab9c18051ba5b6983f9a71892f8b3ea5051045890084b5ac2c9a9ba573d2	1	0	\\x000000010000000000800003c6bf75bba01b98e4eaef6f24310342071fe044031162c00ae6cf41e06d5be6d811b7a66164dce0852f5e2648a27b83f4210e23b11d5616755b4013ac4944b50ffff5ee2f0d4aa8c24ac80d3235a0cd454941a9778727818a3d6c2fe28c5aadb6e20a48cb22ebe93f17fdc93c5deed75041979383acdc6de6b8085ac7da1dfb81010001	\\x180fcca411a26f27f7bca5379a1ed1d1ea36ca404b1273c315b4938982d83f5c45ccac9e4ecb7047cb99432a66c13d901f29ee2ec7936de4072695bd4b7b3209	1661468107000000	1662072907000000	1725144907000000	1819752907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
106	\\xfdb4a9310831be356de2360157003c0210fd6f9545729b2098605f1e3a292a56ac7aa802327adadbe88bdf02c443238b5a11fc5c55fb28310c5af7b5bef027a9	1	0	\\x000000010000000000800003defd5307135dfc4d93d6190c268f48fd5dcac2d57e9784fa7d1889bfd184e404d08cbefa7daca241ff2c005bfb2c51f6859520c43034df1524d59f73999cc6cc9631b3ad173e4670e19f9a491630513156cce55013c642b4e89a57003fa80c737bcfa2ec88c6ae1118a86ca52b6f9f73eb54228922b624d4f5e9d227c233ff57010001	\\x12c35f8654891c57c21414916b68a58cde2dd1dc9d17ac945029a9a546ff4a7094c3a6b1ad080f6eca9ced3d8f277f71ff1a8e0cd34c3bc59e13b5c3e0288b03	1656632107000000	1657236907000000	1720308907000000	1814916907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
107	\\x013d80cea5af9b85831d6bfad8f8810dfc21b89d75c94e6b3f2c706b8aa84bb5c4d8e8de56786a8cdcce388b7c6c82c81386177e959d2562454668e2dde38425	1	0	\\x000000010000000000800003c4c02f3a5e50d7b134dbc80176d8e0e16509ce4f67b10cf98d741b9e8ebc986e4e984e5344dc578d217be828f3e6d650ffb678c340f411ba6321efb2a5df3e68c8d587055bd21533243a491e25e3442d8c5fa21f83e9f48f60b097c31fd62c1a06f4998e36cf41fabdc85330b01aeacf9f1d4ecdb3035e553a91e59571f690b1010001	\\x81d69b34fec6162371ac757b429d8325b90e79f6a938445b20a451ff456c174876617ccbc49dc46696190e6d10422f1b952a93cb7d65ba87bc404c52ac70b702	1678394107000000	1678998907000000	1742070907000000	1836678907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x032da4b8ab44288521c5f8160d52bd9f3af46fdd05b3b82d248c4019a4f02b119e3ac749366f7a86096f0cf77ac76e7be051cf6e399a07b24e8f210df4b86880	1	0	\\x000000010000000000800003aecbfde1ab20c2d7a8c9b0b1e5a139bb0c023028e75a880a251f88395cd42cb58eb57ce506bd060e6f5f75c5ab0a46252cdd5d217202d312c9e8c8a951e511e08b4432daca411950415e199b5def8767bd7b2274e2200ef7bc0dec022f3b8486eecfa6f7f9ba5ddb544ca8986004ae4f870887de8d933931b97c53cd95f550d9010001	\\x4de311a7f51bfcb16a58f17ae65f3b91ecc10adf1858ebafb87252be8ea08be6b7ecbe504be0b85a7cbff353dd5f351c2d857d65fd580130533585e71225370b	1671140107000000	1671744907000000	1734816907000000	1829424907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\x09517cda86387533720c0bc1a3ea39c0402a5ace91017bc8f5d6af65154be5e474e743ec7fac7f0da57563453ee4e84f08280f3b5157a1223175a4d4698dffc8	1	0	\\x000000010000000000800003d6b06f96d6781246d6e8f7d29817113f19fca8196c1d9533392f6f87e9bdf36164c1e41c64df78e13775cccd6280573d206daa36174c0e3b2153eed13c8efaa1051ae00e2bbe7a03d2d12e7edfdd7f576bde9f242a2c6236617f7632629d27d31d5d4e530be9375932a13a9063dd5b7a35384ebded16a7746baca768e1393359010001	\\x8471a32b7b057909f6098db322181b50ea3b318e316e6b76ee23fb591c13c2b726ad16faec09c27d0b0e5584a15d1c5b7b8e4a1007ab06a69405636ef5998a0f	1677789607000000	1678394407000000	1741466407000000	1836074407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x0ac9ea695ccaa1e417e6c05b732759617e85fbb66d301a3156b1ddc9ccecab4fd7cd0f87bec0312f1c296503c28ccd672b570f238df5f55d1cfad784e1596251	1	0	\\x000000010000000000800003bc7e415efbf51d355cdece8a045a53be6a153b11c9e28b45a5a191e76b6a82f38e0a4d958eeaead35975ae247a25a77f2a1a4faa02cb3494d03b9d8824ef009ed1856eaa9bee19eb19d04e1eb4b7b33f46a828348a5231cdc237df9ed62f46a5279ddf2528a339f3c4e084b710e56c30be35b168284a1440353956479be8c9c9010001	\\x2181f7ff6d33747f24b4c7d6062cce8f20a9fac4d388722fa0a26cc20cdc7a1bac31ee9bbef310a1405bcb84df068a50f0bc2a241fb55912ff79efe275683806	1647564607000000	1648169407000000	1711241407000000	1805849407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
111	\\x0d41fb9a0bcce6ab384af96efa8cc968c0a89efc2375cbb35c4f1b7a2d992dea0d874e1aa63f98b529d52dc295a299639576f8eb63b3bfcc365c61ba1f8a49c3	1	0	\\x000000010000000000800003b3d5fa1261bffecaaeb74591ac215854ac90187368a89a06bcba3b1fdbb3346614d3c7817dbc7905480b7f24b422597144c5346c9886d7110ed71359d69de6fa624f67dd948b8ad0a1c9f3d10b517e28672ec323d579deb5998056fdf71ce412a4486e724291dad9af187f878f16b5cc5f65678df271a3e62deec4f2380fcc2b010001	\\xea18a4050a01ff87c32648d3fc01505e4fadaaf45230fff4f816a51543f7079b6eaa56d3085acaaedbacaf6e58ad4091c559ae93286d04d4bfa910b93678ff05	1672349107000000	1672953907000000	1736025907000000	1830633907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x1469c3601ee8d0f0a7e88c52a453da05632c20833a5bcb16f824a78eee1dfeeea5f0e9f1de318dec5671296be81ee663367ba469bdb352bebc5d6ede826f3925	1	0	\\x000000010000000000800003c0ba8722c7aedc9e13bffb873c54962b260be9c85dc838f7d08a88da4467c799c110b4d6be10d0ef7ae28a819acd162cd629482c04c0dd29e1019b9f608ca42b34ce97a1c9e71b0b4a7079e5d93de577fae093a77e6f32d9019751821ec5a36e4511649f8a62455ccdc6e5691710e727515b295268d019f3ca8cc78dc68e4c6d010001	\\xd96711d60411d82776345cb4d8bbaff13344ce80bdd34ed2a21f23e36e9847816469c45c424c04c3ead61dc5e5719ce51594de89e2845e31e18713561a790f08	1674767107000000	1675371907000000	1738443907000000	1833051907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
113	\\x141de08aaaa133c199c3f3fa0300c31dc070a534c73096768dea4925d77abe05b941197334e9fe8cff93966f39abeff9c58138b226e62b78d318dd7ea29f29b8	1	0	\\x000000010000000000800003955ba5b4814a60952cbb5577bd5d7ed33282b113ee5eded2973a198eddcd2f3f5a7b47055cc1a970bc0287d438e8451839125f5a3b114f11ebe9ceeff2477551e5351a0c4c34ac066663211c62d97f621667b6e4cba9db8d809bee5c67919435dfad023a97970f129f3596e7c109b0528e5792fbbdd04ecfc53d8c71c920da41010001	\\x0b62f46b688aef940de14d4ba7f3cd92981930e494c9abddafb7cccd05db01d9c96fdd0989af42cd8018864d7f85b089e2d2ff3ae6f4fb47fc173a9734615900	1647564607000000	1648169407000000	1711241407000000	1805849407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
114	\\x155565db5cb7f34c10aec8f0bc6bf90a5369a5d78c853251485c8af5d621cac1aaf561092dabb0076ae2b37bbe2221674a9d09bea2768d3f00b11453e0d95ef2	1	0	\\x000000010000000000800003b1bf8604f716922a168fe0296aad491861e98a70e5baf057650982552e350b81d2561f7838fa827152fff78c0ab1da1263d3ad607d1e73463e43d65dec95951785caa42e0c4aa41d6ed48203406429c3b405f5df19f69bc4c11952e0e27f1b63fc6547eb835c4b361f2db851c9629d149f0344a5386ab24c2322f2e32adfff2d010001	\\xa839f3067efafb09016dcd56f09fa7fd9f23e5f275e881bbde883f5f2a2c126a6d62f9fc7c102c63a9964e781c47b3d4a6e017b9e8bc6dbcbf5de1ab3f2d240f	1673558107000000	1674162907000000	1737234907000000	1831842907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x15491e86fe9ed05cc54dbf5b289263bbd69dadd0c65b28c3232c4ac4a31c4f066d2f5084f126ae1443d5eee714768051b75b964c19e2eacbc42d2f55d5644670	1	0	\\x000000010000000000800003d49d46ab74c1b903c1809c0b706db7e089432e752d26d17a697f814b166bc9303cf50fec8733b77514feb690183041b917b953ac19dce3aab76a6d4124c967c1cdd9cfd3f940bf01661a9611ba31e0f78555dba4d66b7df79e00351e42bdf68f339cb94b985def0f333bae0bfb826c57b00bbb7cbe2e7a3d793bda926e961b3d010001	\\x04701af7162880c90621713c69b0b1f688853b302336754427d2effaef608b2317fcbe8190ac61a31ea275df6ce8a539d410714c28de6e791e5d8952baff2207	1665095107000000	1665699907000000	1728771907000000	1823379907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
116	\\x1781662ecfff0c362342fbf1e55356364e454e3c9b9a485717c56228bab01d5d2f585e8e7429c0176317112feda6f30a4e95f2c3f0ef3ec23c6c8b1cd5cff14c	1	0	\\x000000010000000000800003fefc8b7573880eea44504ec62c22afc74e5f1409f52b6ad0e27b3eda0db7488f4673f49006e073b2009acdf45db46d39285fd2092a0dda34c28eb361c3cdf9a08103733502cb2f35b56f8d08ca07faa29dfa1d21eec38945a509fa9787de8b7cfd8575c4d7654ae6375cfa3ce36cf83cc1018c19ffe78248f90cf726f5884d8f010001	\\x54d989f8dd51a6cb0f34bd19f02b2508209b64c571243941b13ea52940ef005aba8827a71a3a836f8f70253a838ea312d665cff769b662c812bad6f1fb2bf40c	1669931107000000	1670535907000000	1733607907000000	1828215907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
117	\\x17a9e7cd9c1cb9567c9fd0503b3664e5fae0ac0e4b4cce28853a3a2da805e3429dc342ef2f70ec168ede0749d01bba45efc1b90d25510453f82b91314fde804f	1	0	\\x000000010000000000800003bc266c4557a6d0aee84e9450838bbcd05e771b3ab93276028af3f3469bcd3125f88335600040c4046cf788efc02cebff434a7ee365b09fbd55030098b8bd343608248a1120d86e79257abcb7515f64717703b1bbdf0b3ab8a43ebc3702fb0d16958a89b7ad8dd5a1adf4a5d8643d947bbfbe197e45fff189a6faf7df57e32541010001	\\xf885344956add6a4b84a2210689e21255dbda518584229630c1de3b0cdca41a30a6dc92b5771201a66c1d565cfb96080654c5befe4c2497a694d9ea123a00f09	1668722107000000	1669326907000000	1732398907000000	1827006907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x19095ccb413340b0a8585bb9fdc80a8f3299338ad13487532bb2773ffc3ea6036ad212c49961dbff6b127693c844ee5ed59a704f5a59acf256883bb5065ea8d5	1	0	\\x000000010000000000800003c15021d9ddb33788a34bc01f394349ad06552479b916bc52f31a5f28ec2335af585ad259c08abacf7fab99c0fd1bbecc9cb125ff59424999893258af93ec9f4bf5484bb621c1a39f7fc4c94eda61713bd47ebebbbb6be576c58a8e811cba82ecc66c9718da3f1f770d632d8878c85a645d63c8611b7547db9ff6c96174720c09010001	\\xc11a8d7e4d1debfae7a147ef40071df397355af12d620bb5db30d23be0c4677852e18f0bb6d7445cf4f5dfb4c3e7ee1fc97fb60aa9312be335e84d164be89208	1668722107000000	1669326907000000	1732398907000000	1827006907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
119	\\x1c41d4676431cfb5617fc3b0cd2727c0712fd6ccbde68c15c8c0d9a516bba733328533b2492fae01718f7a9a4b082352c2d26ab6f050b7a9a86ecd5a27454c3c	1	0	\\x000000010000000000800003a2847fef70eb47a2b6460fac1794ec9778f4bf71963f8fe787f16a0fc0c19a59e43a8e5f68d696cc9417a53699840aaebf52ca1b1069129bdf3c6a9e13dab8c550e610f3ecbd7d59f356a464d16bb2820c8a5b0cec6487e8346b008eeee7fbe535978d9aa56b28bf9ed57378cff804a77d8b031e6fe722acd11be1b0886b049b010001	\\x4b86dc1b1ad21c570057a2f6e01fd4c503df3c19455407ca7b0f524d317f613ea49ef196a7756b1f1917b4a45537b8a65abff030262116955dbfb71c84e16c07	1665699607000000	1666304407000000	1729376407000000	1823984407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
120	\\x1f01e91805ca17479629b514a6bb62611099e587aaee8ab7362881bdbc71648ad050f5cc215cf9cf715109358edd42d48396e560f486aa36dbb97c58ba7a77b2	1	0	\\x000000010000000000800003e55c3b3ee5d34ed1d865db8c6b6c976a72eab45dcfa0365a55ada614d17fc49190475bba1227db68596836d81f477163bdec7fe840b9cee8fe7fc2147e9a085c0b42d65207ef52a94d46544a0c6b158b2dd886b8c3c389683a7ae7764766689fe4388fda7eae4d14035e165550c44bb01a92c95043dbd8bee4e1e849f3fb4835010001	\\xb5d04983c3a18f7a64ea4757875571c10f6786be7f206bac3d928413f3e2d4df505fa739b2ea322291ccfded53e032a03bf4a518922ac7ea9100a67917030803	1654214107000000	1654818907000000	1717890907000000	1812498907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
121	\\x22819c81fe6813d32bd327fbfeb7634745cf5fb9b058427a4cf2a50509f8262479b0e0ca583a647dc7355bac3c0e7f2cb057914d41c53c75b762a9a62f17a2be	1	0	\\x000000010000000000800003a6e40e06e75401083ca36948864e2c88698ae18ee115b907498ce095b70ffa5cca430dbc57afd8a31187b80dace7fad3c06bb2cc51a92843030bb88293e9a4bb1d294b6cc15af96a6922b38b0b42b0fb30bcd639862129b2b751f2413d7ccf5ccad97eee01609c82d9da8cd2c617c4071418c221610bf19a8c63ce13e29e324d010001	\\x2d72932a0536acc5fd9197dcacecaab9f9d152dc9968b982c6d16b664b4d54466eb13416c6f923bf2fff8b455e8c961b4614b4cb7b81a3600000966daebd8601	1675371607000000	1675976407000000	1739048407000000	1833656407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x2325895f5cce7ebc9b1d60db6f679f98a52c333b4930eefc6fd74e1df3e4c9d5e9d32137eda7212e32704bee1c862f0c56a2fba58f177e22e85997dc0e1479de	1	0	\\x000000010000000000800003b68bd203e64785124366c380d3ab93581c2b1275de7b9fbb8128de11309cc2fb093e2504281001328139a1289e4ab9a665cdce62160eb77c0c2ca7b42bb16ee5bbe3d254b864e4315f51ce3157e1f7f7d9b99874dde212105f41a27b3e7fe61c27ee7f5aebd02eea85f62d23a712f3947b665a6bce9a7e4cd7e9c07e3597cbeb010001	\\x22a384abf417c0b27d2aaa10afaebad321566b40b7f0fb269c02102c3743f7c840bc951d9a02d0c7abda8f010d59720c67a6046a4034e21060abb3e82996e709	1662677107000000	1663281907000000	1726353907000000	1820961907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x2429a3462486d56b5072fd0868671196c0f35efb78655279690d3ba22bbea662ca59b763af8cb2abf857eff50e23105cb284eef8d9b4707ea287c48bb58c819f	1	0	\\x000000010000000000800003e1cffb541d50b90c38d1473044f0777ae318cf469f40328f8783eb6ccc0e1ad0d98df9c11607f199ef517794331a9afa6158e2a7d44e9cb9446d2e703f4190c03e198dbc95f009ed880c28831b5c7d67aaf9f851a37e718cad1a1f71541624ba1db4b92b8daf5a1e8ca4bce5b71fd0ac101261890467e3e911491ebbeeef70f9010001	\\xc6c05f49c75093d0f74a09900652e2d0b66081a42caeaa33d4806c17ae1e732f91740a3c80e9af97d3f5b04be394e2c90fa3c20e2c98d3156dec6b32105f5103	1659050107000000	1659654907000000	1722726907000000	1817334907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
124	\\x27c90faecb26be417103b008f36f849d7c19bfd4195d428540fe375bfb335ba43703d791f8c2565e3e7ff3ec7e5a9f900989a4e62bebe6422b5b64dd9f0d3e8e	1	0	\\x000000010000000000800003c86bd351eaac72b98973d6209ca4aa537fb94eb37d6d32083cdba374364090261d7306e1cda320dc8e13ed9f2a38a067a30cb118e04635f41f5b296183a9fdeb4b3bd60c9657de4eb6ba90f6f143684d5c16612ebe1ed5c1d485a26a5fd096d37258334f50c608f35916b6b318de9acead3e6d9eb2a52235bda23a1e8dd50581010001	\\x3b08ae4bf4ad4aa99b947741119587b7cab5a8cbd2fbc8bf8d9b2b21fc16e927dcf95e7ac8a1c91b356799774aa5b844f902e52d007d5e68f9fc11212b5cbc04	1657841107000000	1658445907000000	1721517907000000	1816125907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x2c3947001ac8c7079a22a7d5c6c1c6c26062b0cd3b5f55a481e8938ad2458bd2a972874004139a03b2eefd454ac2374aa8c6a070192d10f49c4c1206a5c01e20	1	0	\\x000000010000000000800003b7c9430f79b7af43e86e632d2fb3db8cde02e55504f24687ee5b120e413f730dcdfdbd6042985e41cdf7817184af3a84351329895c7bb47e9ecb3f9f980397e81c27aebfc71e33a594effd9ce4894efe303a1c8fba3dabe2ad3b1a163f5a3c78a12f15342f49a0faf81d4c068241c2c5faef04c0c5dd5244ebbe70105f3deac3010001	\\x4782dbab76d019aad1a8f14170d384b5d15936a24d896cb736ad18489279c56448c24d83470e3cd828900604b84f0724856bf861ad38ae77a0065ab1eb5cf20e	1662072607000000	1662677407000000	1725749407000000	1820357407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x2ea9cba677274dbd12c8f6035cf55f9bb8acecf67f55d90ee0ebfae5780e7a33ccd469f51b1dafe6fe5832cbf7be1a77483be6783ba8f1ae318ae8f8baa5c189	1	0	\\x000000010000000000800003c61d03a43d4c2c3877304e23522b1ec0693a1b266022088b8b3bb018a1ded390e2f42fe54b06ff3f467f9ad2aa3b47b712bd0e2c22a8c7fd197b276e5c578820207e9f18cbe23ccf929b704a5fa72b0b31391cd41eca447bc2a8424d4a42de1e97ada6b2742b473c290ea731bf02f51d6558aba02605b3fb06e8dde34fab7c91010001	\\xe9add5d0b7b0c3129ccb1212abd82ad9fb28f31569c632b4854610821c4c3e1b04574b434dc162986901c1e467484cc6630afedda47de53c87a709999ad8550a	1672953607000000	1673558407000000	1736630407000000	1831238407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
127	\\x32b1ac6c94240a934d606a8013c517a3071ac4ba966e48103ddd15a57c258d992ed588f272d6d52bdfb7987bc1002d0fa9929fef2a33b9edf640e3b54b9854e9	1	0	\\x000000010000000000800003d1dff5519849afc62b50f93e6c9187ae188ab999a20464bc35b9b6e00c0e1117c19e54ae5b36e2451079b3590fb6404818fd65772dee072510630b25c44cd121f7c4bf7c55c14a5d4d9f85e701a4221e162052b79e7d89559478e61a4385fc8887cbaa9cbd4b3599fd718e75fd56cc62e3efb27dd0bd17b26d2dd97aa4a6e037010001	\\xe396c6224fda15db4a5acdb8db925b3c3167c8b04a84d159ff663208ff750d990f0649b3cdd1bdddac916e3eee126dbfa69b7f4d3dd48b756b3017d5040e8202	1661468107000000	1662072907000000	1725144907000000	1819752907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
128	\\x32e9594eda85b17bce35de35fc3772cbb1b79350dd7e107f7de477582ee18843e479046f11aba144e9513de46b6a74c8aab4c1c1b286b541bc11604d9f3fc934	1	0	\\x000000010000000000800003c4f7ce1fdcfee56933eed642a49f6a6febaef2934d3bb67225793c6c95a98332a2dd950a73f2912e6116a35510afc5346abb22dee3b03b93c2e370210b4cd5d54c657ebf982d61d6083ce253d05fc07df0bd3447f4781660e7fa5a7c03655a5fdedd360a41b7fd00e86c55a42a58cafac72d34af3cdd9ae458c564ceaff37e0d010001	\\x0174aca97c7387b4f3ad6b30e0537cabed106ce1c31c9c2646f2033790c9e5406b9dec90aadccdd878ae5e5e271b7f5b493d27700b8ceef918b495d6b227c208	1648773607000000	1649378407000000	1712450407000000	1807058407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x3421168c446d5a36571c18db52e5b52280496e3a0e5de172511893342ae548d150c0ccd0d0be1bf0eb298d4ed7f49a5add262b979c84a4a94e458ca7bd4e9ed1	1	0	\\x000000010000000000800003ab2f00df77ebf82f2705d44eec40d0220f74651c08f52fb88d88edc3c685e04b7c2234ab04bc0f4bb96d25b83b42ffaf61fb29e62ef6a60ed96679506f8c0c47f5f979bf32ad9817d26559a7bdc2ba84b00d15250b93b9d9ed53700a82d6ceaf5a66d50cf69b79f788084a0bb84f37c80972055535bf5310ea1dd838981d62e7010001	\\xb2c5cf30365a2475bbe5b07252e7b514de6e1141bf3d3b982a26ffcf135c366d4f66a4e0b30200924183320a29345f5387dbe0bd3166661fb7a651d5665ab504	1672349107000000	1672953907000000	1736025907000000	1830633907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
130	\\x359923d8d6462091857a1869da1f1e3dad8983b3ada0725457ec95eccf170ebe2f39143aacb350ebda071b7a2ce21068978e40618e07e5366c82a122ec103912	1	0	\\x000000010000000000800003ab210bca8fc282fad92940e52bcf39cad03dc3676a1924fd0133a07f134751e3689cf357f0233c20da85761767a703c6119abfa797cb221637385859a8a45fedb625e09c828f2f83d76f3eda09102c6864a257a262bf95bd72b5c37e47387e4ead178fa0b7a2df239a5f22b14b648e65b612197e4f8b71d80679d0a8db6dd50d010001	\\x4202cfb89521da847394ae0e709115a24834579a6db4ff905165195c70ec6f987965d980088a10f0cd59f6a4ea3b04eff20ce812e0f65048df1a5bc36579260d	1666304107000000	1666908907000000	1729980907000000	1824588907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
131	\\x39ad9a209ade9de938e8a3e247458db49eb535d4eca78b380d6b1bd7fc7b9e255a75f42075287c671ef70d13dc0dfd6998199b303e6d0b7884f972edf035c37f	1	0	\\x000000010000000000800003cc94c5d49dab574a32b8a60027c864e8ce232e70d6c8d977a849afae36f3dc16d3a2027440dc1271495a9127076f8de6896d65216768d698ba50590ea3f6d5c3c340c63c829c2cb7db5ff51f3b462685ba8c2e7d41a64e49d66bae9236a37c80e15b4fab0b23761651feabe3739884ec3ff4955ca8e1f9b3b501d066cb35e469010001	\\x28cd79dde66d810381ad40c563cb538057bd32d444e3b152d6d7e632760947536721e5e860f4eceffda9d0e9cbce3e5692d7fa1dc37a7244a53c8663ed0e650d	1653005107000000	1653609907000000	1716681907000000	1811289907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x3af992b4776ae0a64c016c13e7b4f8332fcf86a867e13eeb4bd8d4ba0841846e2039f812266b0c9b2152a8821353fd8eda88d1ab375ea7fe352e176376d77b94	1	0	\\x000000010000000000800003c7e2ffc05a72afd3835b246045694c5f734e0715f8e85349ba514ed070b23703c4cdac586e10b2efc010fa38cc8b7c13e1a02f9e30cf10bbcdbd29c7d3db0f9b6a5e65b009504c43503cf12f1aa6a5b632bd5380fab6b4867df7429ab750ca14a07091fa4be69edef95e8db3789d5fd87d2ff47a04615c22019321a5d98ae787010001	\\x68bf13b67e1dcf3b2da5e3215a744f8905e8ec71702969b36a01b7139bdb48f8a5d04add82ad835ca2f7dd73ff6b16901acd95ec910d64da93ff3e9ed2bc260d	1654818607000000	1655423407000000	1718495407000000	1813103407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x3b6d8d6b3c343029aa3d7a7a681cdd2cf5b8240a582d632849ea51ab17c352ebc81f13dec166f36d04a3c8730d3983966d714a2d337db32b23dd7fb86039f025	1	0	\\x000000010000000000800003b05445cbc9fe5fca81af003b79e399fcb495fc66e7bd5dd0785a7e4ef75f4f7eaa2396a84417dd8a69e3d5be4735e8e9af890b133861e5975b23b4da1a3a063e157bde40faeada9c8fc508ea35dd0b6bb6b70da49a776694856beeee24516aed170027e8bfc4f389a79ecf0c71fa976edd437e1536abd8ec3546f06850d07db3010001	\\x841c881f2ae3f1b6e1afd8986cd27ec33b11807d9e3bdf3751069419e18c88889a2fba9ddd3960efc2172740d513da9d5924f33ac0f8c2b3acc32d71b323820d	1653609607000000	1654214407000000	1717286407000000	1811894407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
134	\\x3f459d281fd008e2d3841a1d51f74ec99fdf74b5799e8df77a052f3fa1fb8ae8fbd7db354463f26d54560229d52dfb913dce1bbb52a5b9cf3fa93da1dca1f83c	1	0	\\x000000010000000000800003d4a39e15b7400e234935628a88e040043b5b5d240946336c1b94a0219f73e57346701915ddb60a289745bd137192e9062e1992e45c4ca333e155a79601a992af130e143f0fea6dff51e0d504aee7a8bc90d94861b95b7c55ea1f71a5fb180959eef71bb6bcf9bce4f72136fbbe28393ded08a3424c88b3453c4b40993f17b5cf010001	\\xd094816c73f3a68b8119a345cd012de9e295fbf5f65649295edfb0dc0d4ed95c0245708feb6adbe8d67c12b1588e2306a616feede1e9d0885fa1b149329ccf02	1678998607000000	1679603407000000	1742675407000000	1837283407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
135	\\x44cdbbeb952c970c77669e0e53b882b3524f5ba6d36f5bab3180b328ba96a37291f482a48482d7deeeb2c41b547bc1fe2fe7616b3680b5a121579f4cb28f8de2	1	0	\\x000000010000000000800003aeef01e68150d6ddade55e7d1b212c3331a9cf69307ca8af51db120c07b31f7a93a1b20356288e6823046bcc8bc907f09aa04f2e4e693be19968bc21aa4e200c6c21e1e046c5a8aab478861ad5c59e6d759c5accb5f434144ad58780df6d450d8e2135d90abb267df9c42ef15941a648c0a17d6d4ce3889fd6371703973f007f010001	\\xd687c8913f0e5f098265b4a816394ed57ace53f7c618463446ffa4dea94e15fcc4af1ee6e09eaf68b9c531911c0053128564636906f68e5620e27aac66cb0804	1654214107000000	1654818907000000	1717890907000000	1812498907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x4571231085dde1003e999dde14e1705aaf15d01c7861110d3fcf645ab5e2bdb692aeca5ad0b776b143ebaf85150dc584924008c58aa17f85d8c2579dca53df28	1	0	\\x000000010000000000800003a46008231de44035ee74fb005262c04845fce53fe488553472651d9eec3af833ba2649d675b69355d8113f403af0f06af0cd9d02ee659357907656152e7c38af315ad1750c8251994fe8c55b09b77355b8771f910016754347fa3645671961da3014651e17399086bab697682ea36f8f76b599466293597dcdacb11ca36da5f7010001	\\x3ee10ae762a013699342f5e5271ac725da0d3f49f15beb161e7d67084db91dab9616114c7c512b8bbc6aaf19d35bd91124223d0621c1fbf0ece04a57b156d900	1654214107000000	1654818907000000	1717890907000000	1812498907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
137	\\x4711c30460a667153709467007c98dbd587e2b8e4517b8f63a48c7cacc9b1d8fe043add40a5977738b8109944d8c5503636c98a3308f43c3419f593086c64c91	1	0	\\x000000010000000000800003e0bfe839c97a5cc4fc4a31b681471288c9e08ab3cd99e6fcac1a36b4deda4449e795ccfb47344d477cc135669cd32cca3a16dabbc110cfbde5bd87341c839649f8ebd77a4ceee0e7cfb50dc8e70ed3750b460b949f630d2a56ceb758ea754cadeacabdfa9a27bdd949f8abbe50dbc8a2d02f9d99641e4c049308cf2bd2e31fa1010001	\\x35a98520f6e8392658b35ea9e5e834d3ad14a477310fbbbdc690528669ee3eb7403c5ac15c0946d58374e03c4c8248585c0e8f0c7337b662bcf3ea6bd44fc708	1650587107000000	1651191907000000	1714263907000000	1808871907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
138	\\x48c5daaf26e552d46cbd79edbf9023c64888f496f40d3d86bbb8f2c3963ba5ef260480f55152c5c49483d4c847ba2189e2eeb2f3af723cc122ed28ce8b674164	1	0	\\x000000010000000000800003bf870bb167bd92db2a56b38a7df0e3793e4966214c2fe74a54503bac1998013b83546e5bb66130b5ab40e6903952efc6491eff098a822bb6c2ad0d21c7b55c6bfb696e16f2de09054f928c5873bdcb646fca2e7b13768a38012ebae396a9da655af6ebaced0581f2ecc77e6a9a7546610f1d1081f95d370d7d297e3da3578713010001	\\xae7ac219744e53dc00742f631ec62490403b475a0a1a6f01a7f8ca9107dde8bb556299419800b6d4b6b42f84b5ea436180652599f72b373a9685a7f8cb8ac501	1675976107000000	1676580907000000	1739652907000000	1834260907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
139	\\x48d5b3c9c9ecba4bfef6aaec6be23b8ff3d75593748fef0d438a399b87ef8c23b75d64adeba21be12d70e9cc23473e5cab299d923c7c58eae5094088a63b66a3	1	0	\\x000000010000000000800003a30f9dd25d27a139e8d3f35722a33ab62567ea3ad3116da9f011faa5b83d458a3356e6edd7900518ab59606602f0ca4a00049fc196a952ad0620c8ac698179f30efa1151e27b9e43ab9db8080d68769220e73be93acfde05cdc8ca6e8c3ddcb24bd6241cb8fbc1908225eba4f3c3547ad994f47f49e37349af89675612ccca2d010001	\\x8701d6062452d83193e61355c0c90102f64dc0da9ca8d205619638d759365bb4fa0a664a6ddf7ba68d4ad65c22300114c9fef1c41acb50d2a2252814b354ce06	1665699607000000	1666304407000000	1729376407000000	1823984407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x4a819f97c5b7a30da96d3dd830512c5deb87105323f2b557ae61ea0bb2a3523966d5ad91d63a43684b832e04a9e8527e94f2b0d01e0cede0dfce76e04d82ba10	1	0	\\x000000010000000000800003d8232edbe5d198f3b0eb24ea2617aeeeab84c202d34cc8963230717d5a6d8ac99f8dd9eaeb8180e0ff7b8c125284a1e362fa4f07d54efe76f7b6da6b8be160206d1482a454de817c701bd3162a2692b32aaa8d2c6e3e487f713fe5e69061ef59d6528ff22e28411b5b545df467f0f62a52f0809049dcd3b08d3f1dda5fcfc22b010001	\\x26fa18c47b9afda23fee9b427e0cf52ca153bb51d6fae99f633a0c433876303ac83f9b9e2e8302fbbcd44a868155077b2051ca04e059af251205a9de44e93604	1649378107000000	1649982907000000	1713054907000000	1807662907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
141	\\x4ad19b5bc0b2f19669ab7c851180fb4b748645b94ef1c8a8c6e7b76fb0a445eb1af73e401c99584b684e5f2dd248b6a79178fe51409e6552ef256b52d41d45d4	1	0	\\x000000010000000000800003e4fd45a83d3a70ce8c215a06cbdadfa8a577034b45e24882daf533c1cc792e1e082ea90db896d52e7541b480a6fc6cfad40984e5f130ee8a95e7e0eb3d6222d39b88adc307354739861fca1dfe8f53ec9c779b75fe5e6adea4aa2f1c4ab2a911f598105d3fbba94f17cda63e7331cd78de2c6e98b97ee2bdbcda85ea804f1ab5010001	\\x57c2a6819eb4f4213f8c516b010f55df790f20cf3396d6e884d016b81befd8923c49d273831978205128be4764145b2f03a80caedadfca1c833befae6642f607	1648169107000000	1648773907000000	1711845907000000	1806453907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x4b554949068f94a2089fa928b9efd1b2651842f3340ecd4da562299314f198a04c2fc75f8a4e431882dafa9159bcdf5d056819508399e81ae106d1643764cc8b	1	0	\\x000000010000000000800003c31642a78603aea5177d42062b712a19e2113179cb1936bb417b33c273970514386f1f464aa99f3858ca2e7ddb66a87624c1944bdf6d0c4a8aac6887e9c0d3649b5c21384b1b3dfc0b981acf67e9b2dbe1514147aec2cd008d584a6a538e3dec9714c73102af0a2ec91ea4e2eff8ae0b1470a017e97903b1e16514ad94eca433010001	\\xaf42d460243b7165c29cb06c9e4dc79b3a27b773eff35443bdc28aea90ac8dadc8cac81b85b744b381974597b19b8cb0b2c27588be422e03a4e17131591ff50b	1669326607000000	1669931407000000	1733003407000000	1827611407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
143	\\x4c4dbea626a24a75044b295d307d85a5c3a55b382cd879f8d6e82f2cb464ff71d934d62c71609f45af48c5609a56657c4bbb6c930c734c1c05410267f13dd9d3	1	0	\\x000000010000000000800003acb162e02cb94799425cfa7c44dc0c5875c24b81410785206460745dfdff14110da1fbe046ecf70dfbb977529a98b5fafb4a12a6076b91088b74e2afe54d33dbfef0582b8d0ea2cb2aa0e5e96e6cf6dd4d4facd93bcda19f2a69a070c1f0cbc2dec0b01c2b74d6196aac23c16d168cfb1dd7c611fa257ebf73c49e49c1f4af87010001	\\x611d035e17f78d1fd4631158907f2babe40b4d52a1e3879dd689a4906097e557df6c43e5a29a132a6ae1f3a8e6acb5293aa37919195591a950322d0389fe880e	1669931107000000	1670535907000000	1733607907000000	1828215907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
144	\\x4c3936bf591f14f55b3421fc51020a8c9043941bf15d03cb8e7c2671120afae317bf26bfeeed1f72971b84ab25a1cb556be5e2f821058600fccc9f2d79fb94f6	1	0	\\x0000000100000000008000039dfe42af414e1557bf9cec7f03fe1aa951b9ad4eaf156138dbd6b08a1d95d3427394abd98eddd641abc2da9a3eef1ee3f35b2e4b625df8e0a87b7d67336ac351c199bd81f84226fcaeb35c84bb0e088d8f11c55f9007e0cb198ef8223abf825ea760db3787801dab4d3764677cd69edd2ff8c75d1afd707621df63f93ff1751b010001	\\x3d11edf2e2ec6f6d03e1c33beed2845334c0be648961a74c7b1b499398c540068aaabea82f17dcdfb323a2b25a9c96afa736f86aba209455159e04f836302804	1677789607000000	1678394407000000	1741466407000000	1836074407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
145	\\x4ff94bd0b94bbed1b83a5d7cd39d251b2b977262a3cbe35b6f218dbf470b0d39e674ce3079512d2dfb017c86c5c77e8ac150eef08dcfdf1667a2cf669cbed153	1	0	\\x000000010000000000800003dd82e9306909c61a649ec9f39653244147cbdecc27ec4abb9f1291438ed25a340d2cd45933283e940b49f5c0d4a6034a1d9d8cde29fc6745b8982bb6468706ae119b7b273dbc889245168f1aaa45f4789767a7b5ce5ca092da9b4a3b6c9fb21052481ad965d57ae21c9b36c3904b73ff21fed1c8338b6d99f37c6ee53f514541010001	\\xf0b2df268a3a18b69ec69738df49f966c6732c78e4c56ef2cab0993cac6c7dee0936cb19b4910045a8397526baff51e027d0bfecf00d5dccf40b889c97d82f0a	1657841107000000	1658445907000000	1721517907000000	1816125907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x502db3df1766eff474b392cc68834fe7388a58c7cf7a84117880e826b2c773ff0785c8494609c6a257f826117cd86fb09708a9265f8879a08a9c8d327f97acb5	1	0	\\x0000000100000000008000039e8dd9c450d9355ce05b3c6ca5d9115bd2089347ea9c11687fdab655a7595f29303c5194f18a98f21021bf31c9460a9bfb779875529488bb2165bc391cbb55ba72418042819cef4aa63df2fb068a14cba74431ef8ca319ac7ca1cba5ea9b43bccb3fabff1b2ac4d7f8191ae367cc91622e75b99bb79ac3814e6fd7398003d881010001	\\x3f20a7c9b03449ab9bc253269d764af0b5d0ad3bc470b9fe3cff798234c45bd1fe9b7fc8b0a622d06958972bb61589482667a66dd10eacc523bcf83cf5d73a08	1659654607000000	1660259407000000	1723331407000000	1817939407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
147	\\x506150a6ec32d7b6ce0b38b191965b48ff8cafd499be5b064b51b4241c80cfc9bfab591942dc8f1090e4ffe3d9280da96c78e558ec7cc42a43d57013bcfd584c	1	0	\\x000000010000000000800003bcc73f14850d6e57ea71c43fc48b0d0f4aab5e47e4d0c7563437e052e146fca4be93bbf87481fac11a6c1f585f9ad0dd380bc2cdcfd045b3d9dabdf48c9906c6276d2822ff90c4f9e87d117c294ff19ba18c8739b3433e3c5b4462c1688b0c64d0a0c1e31c51c8a2e8c28014db13bb7c0f3661d6f898ef0851ed7c15cd4daf59010001	\\xca29710286b5c5f21f1d2fbdafc625c7c874b277edd14dfef29438b01fe67d43cde5f810e892992bb3a9828ee0d6b3c42229afd42747cff3d263b6c0132b0707	1656027607000000	1656632407000000	1719704407000000	1814312407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
148	\\x5275430b88e15f0e1e559b0d68c23cd5430b47e67471fb3e79b73ed9d4ba8ea32e543158f8135dee5e2b559edd01932b0bdc1e5de1a791c60e751b9ae059ba4a	1	0	\\x000000010000000000800003b3fa1ae55e51f6fe56e24aed8d523658e800b780a3f00592d55f7323dec09897ef8dccd227a24ec76a15a1df677bbb85bec49956f6f8aaa70abc4bd782bb5d2e6edde3affdcf900f50a4c1784683f2f75a4ff991900653bdef4636496710a46961bdb81f428dcaa1c1a3abcc5b856ccaa66d0a6e267f6033e10d3f54d7743c07010001	\\x83fba073d05649e9b96840e4d0b859bfb57287bc57fc89d0d2e2d607820103a9f53bda623fc3b97fd99c11e97e2c0e83241fecdac64b39813fc2b2144fa2f902	1670535607000000	1671140407000000	1734212407000000	1828820407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\x5565ede000c79054ccea1660bf46fe052be8c96ddb6434392a50e827d8cb2ba6f8040f9595acd4442dddfbefb62dbc48789ba9a3a49a89d5086d5e74b4f9e17c	1	0	\\x000000010000000000800003e8b3e61d4b7bc58f3d2e0b1d5344d6dd11a69867c2aea3ecf0b132aa6bf8bea72e7a25c9b048e180af0d98db02d12c902e8a175f0f17fdc761f742433dbfb0963d2cf32f536ff560524f03b091c96866e87ba050d369d2393e11edd2b45f7b0ef1c5faa8b4bb4c93c7f4d6ecc505b9edbb098d0f529e16b602d5e7a1f2779831010001	\\x8d770ca1d585af96b12d59c86dc4b03aad7973f27441ed67935adf2b645d857fd151985e6cf2fb871ddab81aadc825df54bb8f8ca0726a5eece044e3803a1406	1671140107000000	1671744907000000	1734816907000000	1829424907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x5ec97efba633fd8e46ef4e998b29aa1cf3612e97b89e24bbd38b4adc7714286c82598e967b22ee67068bf84f2cb22d7f2da41c177af5d4d1778c67b189d611f7	1	0	\\x000000010000000000800003cfb31709747fb5f0b930f6eed074c6a3cb0bcd3476e1b82284fd55afb087acb8ee26cbf93316ca7ded8eb18e5d8b1572a3d48ad7a76a666da1d2a909f1988c754b939ce2827b417e6acd42325a190774d338b9e44cca521e8de04ce749c5efd44e614212f806215b979d046ba2142583582408309b7570b802f6988150dd0f83010001	\\x43228a9df4f48b7034f5dd4e3b1ecbdb6c3ce5d7bd454ef4dc07e93355ee1737729502a122825f68270b6d3d086a15e99edb4bfcab87dfb28bf8689fce4b930e	1657841107000000	1658445907000000	1721517907000000	1816125907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
151	\\x62a964678c16ca04efee771b74990b86b3cd89a98d91041b4928de41069bed69392c6c66bc9fe5dc39e4b481eb1c4b2e0e56471ad1bacd55ee09e0608c7e8456	1	0	\\x000000010000000000800003cb2594ce29d2dc8c2022a0a9acb54bfe1856f8319b8ee057a0faf4849b7d0cc9c7cb7a65349bedd94d21e231591667edad574d987f4eaacb7a5082b9d893f11ff6e69c8455aa2e016d785fb536fe6e996ee134d8237cd1922f98cd5add290c3c9ab589c10d7b4ff26ce90496669bb692939df7cbcac5a0849f77e6f3ac8badcb010001	\\x4ea09c477a2ae183edbfca3b19436b8ebf79a45021d25c9cedf0f1f0d3c58d0b3511b36dd0cf324f07d2b3677103d39a19abd30bd53dccaa406edd262b2f6e09	1670535607000000	1671140407000000	1734212407000000	1828820407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x6411f34c5adda1a2f433ba75ac8c09d2903ba1d61dc4cc0b65f53374aad3f3530cc4a676028d7a2308c26962f48ffc3603f79a79f70ac1e5247d572e34a4485b	1	0	\\x0000000100000000008000039cd09fe1fb959dd0050bf9dc0e7560c79dbf2ea30fda7f14f2b87e4477a0644933513b3036b21442e36a922bf2fa98898b4d16ee146240f22712fa69962f72836013a0efbe432a9290aec6f3dfd0d495b0e4a0dba1ad2eb3e7d280bda1394cfd8e3a6b13ce04434f3fdea5fb413d62c343e1a1fb788e75da7ad8f33a36baec75010001	\\xaa2279c17cc9c97558de27cbad89b2f7412853ee61221bf7bf70fdb72f0bf5effe42bf798e25e08b1a04257e79c6719495e467cd8d75d45ccc2e9d6b6c92d40e	1665699607000000	1666304407000000	1729376407000000	1823984407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
153	\\x644110e3de069a9396b3c7c10f4ebe82e09befbfde9f213df00c7d20df4daad254c173ac21b007ed72a0734e7c188a9ba0240aac7e8b023c5a9b237495f380bc	1	0	\\x000000010000000000800003a83984ddf1a0624919fd502f1b1fd5488e4940cde31e29cdffc49f9541a471181feabcbe19c1c9a9bbbc2e88cfd9a21e5809f08ca31e33dfdbe10593d2b0a4140b934d9b917696faa1c01ad019b884e18ebdb312bf1986633b65aff57b42782b0a4eb1455aca5fd33c8ff613232dfbabe1448124da16dca58bcafe1ee7b778db010001	\\xba21ca271f370e5c8181835b46c340e194959e677c5740f8a8a3dba8099da1559fcd84bebe9554649ce4b48aa52c76652369b552987020ede589aeaf27c7b809	1659050107000000	1659654907000000	1722726907000000	1817334907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
154	\\x6599180c53c34218d9dfa0d86c3b4a14327d808d7a61c52afb611718ce63954d3dd59c4f632a00e93cd1b4635097c6eb7ab6810cacfade6898b479c5ba160e10	1	0	\\x0000000100000000008000039f1ed307da2feabdf46592f2b9bcf88134aaa2cccd63741072042c242c63322dd5b9286caf4197e9bfb66240a247453ba50e8998591c089cbfea404cb8695011f12b2a5280cc7c969f00f88bc0430a509c99dad8702e3432f995b79453fa83610e6bc4db9d764cb7bcae72e0ffad34542114890f1fe1f638465f3536ae1eb8e7010001	\\xa9ece88efe1b633f5f8f19282400d5c9ed22a4daa0f657383c6ca78b43fdc5cd6f770cc39ea219b733fd5ef546e41870821527023a81fc26e942ad719e19c203	1671744607000000	1672349407000000	1735421407000000	1830029407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x6715fb10a82aa040b036959c9858a83b67c0cdd5000859376469c02f0e58888b11258bb29d9da568fa33b046d64b9c17cecbc66f0c2552ea0c2ac731f76425e0	1	0	\\x000000010000000000800003be443d6c872eda95ada7c8bbb45a8cd34e6a456641ee35b3c27d1348ef95bdd4572c9cacaf40e033b17f5e6dbac16b5f73e858da1dc64a5661483d10774df5485bf8a522c59bc3c17248b0a541baf9dce58a7a48988ac4f03b124997b00ff03b69167bb8498b4f6c411393010fa4cf237938ff66a8273a08980bedad0063a17b010001	\\x6ecf9f7841866e04efc929b00e89317163a686689a5ebf034ccb3d27a591517848e22af414ea48b2308a5b1d0469145258dfd6692cfcb7d152d38c6eb1b3df0f	1668722107000000	1669326907000000	1732398907000000	1827006907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x7101b0ed905154fc03315aad6de7233683b73aabe56f20e3ef16643e043c3155d5650f010b0ffe239ed8d8a4876d3ef7538c16da1234cb32274341e2e2e2fea6	1	0	\\x0000000100000000008000039a8238b9dc74d4360cf4f272ed22041f16134b1ed36d69abe6e3b9978196555bba8838e0dfb7867d35339e4cef3f93508583436e1562253e0f22e7e1624d6ad3c189a6f7a5a7a927f0abd767ee37907b0ba95e11fcb42a182e8fd98ac426a0932fe535e5ad8f5db53d6bd008ad5d349b78d6c5dc27468493d354e08de10eb50d010001	\\x4bac68a491276c94cb2ecb5fc3430ee915bd59b91c2781fce97fb9f3c1a81145d1805cd2256b68c635400318a3c4e7e1fd16c902600addca3ffc282e14e97202	1670535607000000	1671140407000000	1734212407000000	1828820407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x72dd5b045bba9588a78f840d0f16aa605f6f95a579a8240b5995d819ff033ecd75fa513c288b02dfcb1dd0265c7c42d5de31f2142f14e1b805c5a90e79dc8ac6	1	0	\\x000000010000000000800003cd077c3939a77c6896714921e5831f8deecac076c85016cfaddfced74d686908dbcd9837d564f0416d56464307ff994c32935b64c9519e8036b91446edae43a7307ee3fd3a8032469bc2618538d023e502d4c4673cf09e7505e0b13bc06d53a0928ff29106cc2d0a5870a4902691a9a5527c3f8abed27553e1b3d36ce3261fbd010001	\\x8b0ed50d43c56599b03334e1449aef1c7e29d1756a7f6bf5ccd4982aa6da9db64f8fe374191be830aa6afb0449a8ce7d0d6a4f7c875cf8480f21ca742130210a	1650587107000000	1651191907000000	1714263907000000	1808871907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
158	\\x74f10dbbf75b55cef1a90d03f12aac559bf8c149f499b646ec57965a6e15da532f101be2fe473040e2b2d97158446dc07b60035a8acb258bdb1d9c445bbe8bf7	1	0	\\x000000010000000000800003a9e6a73d85a772809d6eb01e957454b2ccc58b704b913b2d3c31e53b140dddb2979e8f0312c67d0b98405c922ce16bee918a912b518c67a912f16d1ead6bdb7c4483bd85601a6e578244e481bff029921a3f035434f7d315bf469312d80e0444016d00213915dd821358fab8a62211c54c070f000ba2e4d0b6923a12e097d157010001	\\xce472660b55a831cf199641d144e5f88dd4c0057734124deaa1d21641cf0316a19470fd63bdccf2b45bf732f1a6438f85d1a9067f221d1b10b0dbd3859afc004	1650587107000000	1651191907000000	1714263907000000	1808871907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
159	\\x74b982d70085bd307a4671f11b49ec3127661b4ce0b9a34792042a78bf0027eb258fadc18395594ab14066d9f6a6c7f473882f39c19028a8cae3728fdf6a3db1	1	0	\\x000000010000000000800003d3c4382141f4b15c3f90d87ed95e3e404d8f39a301530b74829b552149e59602fc7190915f0d63eced39501aad8400ec8fdb48869c7a9b7bf17130193cdd08f127dc952525f8797231d0d72001ac7cfff5c8038d6fe12f7bae4295809ba369bede9c1e47bd648957c475244513fc9c15dfac134ca0d38b9ac08fc0b603250133010001	\\xee4ddd70d365d1f0193233df3aa9b5eba7e39ed854126ab1b2a8a587bf161416a6bfecb16a97fd4c727722f100923301f79556c2d13b38a7366de129d674b80a	1670535607000000	1671140407000000	1734212407000000	1828820407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x7505e77412385767da4e87be5cc48067e5acb44ab303e35018e361a17450bed5e4fa8212e6eb597e478655c25fc585185f2d3eb595941e9e7f2400d35e230484	1	0	\\x000000010000000000800003eb8c39248651bd2814d2549e94d07ab76949457a656ed97f849035e6caf8724490b25b7e64423f6162f685434e64e6b5f5029b65bbb1e81336bc97719e51ddd4b58b89854fd73f2c835dcec6d30bf3155ffb53a878435442cc651348d21445fd2960db0da1faf54c9756ce61fb3036db3d3f45294fc86459d72c35dc6e2c4fcb010001	\\x0b85a66cd2d26ed62f26b0e21f1b564035cb11236ad8bfe2762eed03f9f91a15536b3163e582fba7c5b092e1875ab6bd98c7e054b6719346c8ed67b21e8f8c03	1655423107000000	1656027907000000	1719099907000000	1813707907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
161	\\x760529c3b97dceb27459bd0f3e4d2e3af45b44b5fa66fac5f2efacaf3cbc2ee42841552c70c4e1e71f97776ddd5dc422aa54b99c6bdba5255b0a85d55834d6aa	1	0	\\x000000010000000000800003bc0919a90636fef5cbc586ec4a8175f07305ece2a071c012433ee5458b3660ea4ad4917a0a426acb0c8484da0c62bb005fed7a14f06af9a7516f340add694342f6a2c3f6ae014cac81fe7ccb09605df067c93ff8e53971d787b147534cde0b899bf7825cbaefa06ae8a58d90d99c4d60fd368008e1c728944b301a86b3bc12c5010001	\\x0f75a398a32c88b979ef4e5eba53710a0958e05d11fde843809e758fba9a8393d44d18ef746777b63bdf5999cdb8790ba7bb2810ee8ace22182e4cf4a3c56a02	1649982607000000	1650587407000000	1713659407000000	1808267407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x7811e817cc9a5486101028dc005bb4ae18ad48489e9bb4be794903aad804841e4a247b30d3d8c19f30e251f3681b30128a0291b3a836a86841579299b96ef9e4	1	0	\\x000000010000000000800003e7f5ea936dc42322b5ed072a09ad6e954fbb229982f8095a47a8121fbb3e9b84655b89e0da66ae7bb1b60209d0ee08290094f1a828b9742e3c36d6dcd9456c00c67cd465cbd8d7463f2b377b360fd51878fd5f9c8d7ef7c0493010c7985bd68a8de935569a9f09590424eb0c1260d8644033adacb640fc2bf1604f93db7a8cd1010001	\\xb6429e460483f69cdc5361012272ae718a58e0b15566831c918d51eca9a404f923da94ea022bcb12089fcecc320eddb26ec61794798a14cb0008ce823c286008	1649982607000000	1650587407000000	1713659407000000	1808267407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x79e9ff6680e7c0c168d40aec6738a6de201494d14bf817083e07b3f509fbeb6fddf0dbc38cd462b3a9ad0665624b1136ad18b05393d91433bde978400a30fa26	1	0	\\x000000010000000000800003afa2343ff25ca944a6911fe94fb8ebd05a7d78f0ecc10afa33f4e381feb145e87d98ebc9d4c2c75ae0c190da383d7d82cf774e73911766a91ea6a8e6107fc5bff9571c129b7e47ba3d27fbdadece9816b2de8142949895558a2db3a74ef2d9d44a6bdddc6cdbc2939ec8bd6bd3cb99e7eac0481a6a1e272b9a02b95d3dd30903010001	\\xe0185440f0ba772ae5501a42313a449cbbb9a14ae133459eb97529ba410637b496d297401b7843fa104ff9770032fb9a84fa4015012cdc1e7c000f2d7b359201	1674767107000000	1675371907000000	1738443907000000	1833051907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x7a01721683c1a8db256462dc617e321711e87a03831d4c1b6b18d9b39125eb413e98e507ae7983211894caa208d23cde4a797f34f406b0198967dff59d59e360	1	0	\\x000000010000000000800003b7396ba88140df196ca1f0594355e7a96815f5cb55d955052da705eca362654091c7d27c52c23ae30448bc9b1e2eea332bb3aed9e60f46a718619f1d651d8f4ed6eea5e5fdfa78b30461cb4c8df268820012c7156ed74cf13e3f4affd27e726c0c0abef40697998a033a824d531b10d956b3e2a183c9154de0a469f7b1b640ff010001	\\x87386e40efc016b9be62f0326abf8edad60e7d25b38ba2a98e62443b15a500cb5cf4a6da434221d26772326c787570742f38defe30278c559a878f52a8ce6703	1672349107000000	1672953907000000	1736025907000000	1830633907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
165	\\x7a91d611c35467a5d99b22d4e7d5dbff285cc12f1436065f133b090baaf942e60d54043fb1740ac1dd1e1eb4980a7cb22fd528d999702ef36cf8b0e2916baf0b	1	0	\\x000000010000000000800003b32ecb329edc5a5c85875785e1db56b4fd7ab1bd67b9e263999b0319e1a277f4cf9113a5c3a99f07bd4ce59333f8e41b57e694109c4c204ccf5da655eb6ff5bfbe014eb561b118d05725f32d4f38dc10440ef8e4dc59a56137988b95a89851574785447c5132413b2bc644a9c483a6dac2314c3b38274095c1c32baf624ce245010001	\\xfa8bc8701dbf08dbdcb424f36bf7f54ace4ba49257ef463c5819ae888acc79ccb330fd7fd7086dbc6dee81fba46ccef7f7524f1d96d38e2491e17c17e3ce9b03	1667513107000000	1668117907000000	1731189907000000	1825797907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
166	\\x7d5932e168458eb24e4618ef5c3c7546e2a30a911ef216d45d31db8c0d0ad0d5f9acc7f6b03efd148f1dd76f038d3da5cc47cb09357aa7f9aeb3b3d36374cf5a	1	0	\\x000000010000000000800003c5bb69c6f91f005c46475351f544e3c925a9e072e365b2b219081223a96a5c13cda4029786a16425a4293740b7291bae72d8c528f881dc6f7800da982220551295c1448957699ca806e156e3e0a7c20431d741b150933d361e9c44b96d7a53ff5e3055b42fe32915dce1e0eed73a2b67af6b9375fc4802d14c5dde584c96fc79010001	\\x78d5672c98b3aedfbffcf59194b122067d3dc03ac9bc41a524f886eff6e6cbe05de0093609897cad62f80e04263bd305a7abb36ab4d34355018a1f20f0a85f0e	1669326607000000	1669931407000000	1733003407000000	1827611407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
167	\\x7fb5ddfa9aa16366550cfb85fd25441471a795eb290d88ca51a7a9df100b85cf7e61672fac9243d0a44e1a3713a13bae4e5074bfd3f735f1b91dab265f9033d2	1	0	\\x000000010000000000800003e4bee5541f1fe62830f28c28abfe08baf8ce663c51d670e02b5bacc8a8f4b53101dd12f9f8d934087f779f9696d7e01bbbc71f87a31d4d60e93896641221b7b545a5700d88974802987cdbb44d410ab144e8bde0012eb6c72c7c19afabd4b6cac6ba2963ad4aec424f3bd55462d0e0b71b8286641f92bb5f631cb6aaa43a5e23010001	\\x6ee8588dd6938c3d7f1b02dfbc0dc4682fe7276d3abaeb40a196ed7c839ddbbd528ae3f219c764d308a371fef921660ff82dbb7dd71b9c5d7aa32aafdbe61a0e	1665699607000000	1666304407000000	1729376407000000	1823984407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
168	\\x7f792beae23ed2254e5c814b3dc1821576f973720a820f385338e73bf3020620431eadf339c05749e4a1091351cf29f80623dd813e1c9a70dac73c18643d4634	1	0	\\x000000010000000000800003cef6dd3a106bc2af4ea2fd679f9adb4f1aa8eae77b883d296d410f4fff5e02523d43d3f2ca4e97ffa66240aa9d0ce9b05e2ce6bf51bea2f1b803b73dec4d8932085b665782fb6422bb11dd4ec2efd0e3101812a0bc825a2a30d931dd9f7e9ebadf854696ae8082b0120f87bfe5842c2db61e39c5464f5ddaf919e6a48e17a795010001	\\x7c8b9330daaf58d41dcb96ca56fcde972c7ef33023e48cbf21fc0bb2b59c4146a98aec0bdb07994eb228cb29faa045b6b3aa845bd1653e8bdb261edd18930b02	1672953607000000	1673558407000000	1736630407000000	1831238407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x804d5ff48175961d08fd733103c57156c557865b133271a4169d610fd318080efb5d4ac03d64b9f0aeb9db4a7568ba4c94b88e15eef1913981e620ae15846d30	1	0	\\x0000000100000000008000039f1190b04c7629fd88416acf2e75e4d64faf837970391a24970da1e56cc5617cc0a490561e10576b3c6d9d0005dc40d460c3fe66ab29aabba4c41228d1d83b286a264e9c669dade389b38f4e9c16dfea6d091582ef11f868250eeff832a9bab7e7cdb4ed3f7bda66b6715638c84c22053b63f239df920b6e31afe586c76b181f010001	\\x339d01540bd19edd36837b0802713fa485e7f8388882f82ff6aa683b9cc79e944e36e71477c6f634c6f21a1d4af7e2dd946cd7a3e4d3c3d7e7e2651fc4930d0b	1662072607000000	1662677407000000	1725749407000000	1820357407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
170	\\x81c1e49e8e19acf906541cda1ea9a5ad437d3797dbe6a4c255607ab935904096dc13c2b133105264d7666e904e4e4b485e9c5b11bc85566c491e1aa42bdd99e4	1	0	\\x000000010000000000800003d519a31767a8a9e3ed15116c214f40ef1cb5fb903189b5421732675a0e6225c17daf3c5f834eca2da44da12182fb9ed5065f336e3c8d1214476a8996d8e3b15702981611baa2db3a1c825e16fa0442cc0c371cbd1a0916555ad31b60ca929c1e2740221a7133f58f9a102a70165a4f530cf11661d30c4f2c3c7df4259d73d0dd010001	\\x6ab7d865ad65f6e840253d5c8e0c4b2c253f72b362df0161918fea4d72a9d40be912059023484f0e9ed26ca88c2ee59aa652ab2d13e3c0def743dceb19e6240a	1667513107000000	1668117907000000	1731189907000000	1825797907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
171	\\x8149646f471dd18c667bf1e938442af827198a3663fc048ab5598b100223aaa0772c16d640a895e2efef1ab9520ac9efb100379e56773afb7330bc37063c7b39	1	0	\\x000000010000000000800003a7dae9bcf88c0ffbd62008dfb14c153bf44d7a435723c976b86774a3be7b0bfa8b4d770948716dcdea02eaa7087dcddd26a971228832014f707f6cf470dd3b91c11cfba3f443c673784a3e646aaf2f0076c4e0368f8d3a4e07d07159dd6cbbada5ecbfb3262696520cabada90bb688b18f7edfd4b1e2eec113b79c378ef11d39010001	\\xdb4b982ebdc6421aa2c161f26c2bf009ceff67e1219295299aa5ad63f79a465c325210f3a462ae708845ec9589720fb667e8e294744343606cb2085ef37f8b02	1659050107000000	1659654907000000	1722726907000000	1817334907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\x8a21b7bd8cee328854f2cb98f55b280b61f8547e161840f3e5c66088245f2f6de623ab3245cde49d0e68d6461e16dc7adb0d9aa38a44fe96e3f396d1ddf1fecd	1	0	\\x000000010000000000800003d7096fe6bd4cf22e13d15348e94d78196a22ebba318ad68da9644d6de2fc38f39159a783796ade9b2e4e976e4b804200a68e18f35d7f16d5d05569666d7dd2a4b35b5044835e48ec654a7cd8764db8061807126a9d78cc431784ea8f770f7c328b8d658aee59fc7bf4eb10147bda9e405c5fc970f0c8dc1992324dbad6d455fb010001	\\xcb0c0182e155d793fbc60ed02be8e3dc410b63c851ba9ac8ca330b7f24dac23550839d37c1b3e797b996cf73ce73f6e65a4e71bb6a07bc5f8501d0c2b5499306	1665095107000000	1665699907000000	1728771907000000	1823379907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
173	\\x8b91023d8d8b371b87a9dfdc50f52438a6bcbe383b22d777796efcb0b899e170b4e618c53324dab32e4735cba7f8a96c6708890e4dfdfe9ad4d5beb96c25f6cf	1	0	\\x0000000100000000008000039e3adcd8a9d7459753fb450169285884dca8a06ffda312d79b9df2772ef5d239a470f7eb1febe3def96dcab8c11b9a637901b02452c5f648c4480387e86eb64ed0e5dd3c86d45046d29bd0c7885d52dbbb0f06fe318569363d227372e66ca6fd76674f84ab2de58cb9cbc5a924d3441b542f932276123a4e8645d5c37d4822f5010001	\\xc331060040e1dcae808b65a390b67c5c8b1513149fc485b178ff0a33398b0e2bee977a3da7e2bcf568ac16a224181ebc7497897472ad6901a156930dab1d9908	1664490607000000	1665095407000000	1728167407000000	1822775407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
174	\\x8d35e9ccfa0bc7f977988ef252178463ca490b86a62865fae26dafb3fbe25bdb8168c899c51343315670a26effd9640705534317bf48d9d230bff6bbb52c5a03	1	0	\\x000000010000000000800003be2264d2066798d6ac888a5dbd6f52ce56becb33c0e360f255ab44efc51b8c02e9f5453793cde767323641922339e03e6bcfc6ab300e3f25068261f4eeff663f5575cd8ae6a61157d98ea6afe422e1e22e15b5c6f930f2db545e4b83759455994642c79969fb6c61ae03be5a18eeacc981705fc4dc5ce539fcc2c2329f49ab11010001	\\xe0b663f79d42c164fd497108d4b3eb15386d93e2d915c50583a7118c7812dbc92903072a630b533eb94fe416d6a139720abba71ecbbc83ef2fc5572316cac700	1675371607000000	1675976407000000	1739048407000000	1833656407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
175	\\x91d177a39dd4ea628671f33203265981c3c4642f5b9076598c0057c1e668e94262dfd1aa8dacdc3b618e528cfd4fb9cb4b56ae8eac9e1722e8c7187e188b277e	1	0	\\x000000010000000000800003bc0878c83c7ee3832b5b1a9c0ff677cd64310627d00043b738dadd10d8312f36993f74ae78fee831ebf4d66042471d9bf0b90442c618b30d7e6fd0cdced9ceaed5825ccc118d2972dc1c533de719f0f75420836d069ce0601f5191f2fa1e42f9c92f64fd01100354c0e457190c48bd9076fa9e15270084fd004a8bdad216170b010001	\\xe37dee21308aea8faaee8676d36cddc62678388e1a29321346605b63c52068336a623e3ca6be058ea6d2a185175257826f94a5f8d79693e55726bfd7ba29a30b	1657236607000000	1657841407000000	1720913407000000	1815521407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x95053e7f61e371b73947a179f7d7e52a1534aa573ee1d25bc3ee7a6026718699ff40f80fb37f391eade57b5ec52c69a094a6fb6271b013ae8074d29f66661435	1	0	\\x000000010000000000800003bd6b9775b4e471f621cbbeecce63fc1b3e64434920354e1082ab5d3e8679a05e85ba96d658e08a10313428b38c84e982d26bb9e7cafaf062faf7a74e877eb46f0579c3e49a53590bcc607741129120798bfc0ab2ecccabcdfb12d856820cc72c96a40200b036efd922634b20f1dd1f224a849d46080966bfbe444d408c8c3a79010001	\\x4dff97d3f6160ac203d26f335b544ae56db8e92ee32ee96b947357ffe7b255ac3a1dbeab5e313230471f965c8d912a2f87b87372da1862c276fb200d68c44a0c	1651796107000000	1652400907000000	1715472907000000	1810080907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
177	\\x95751687f57d336226fd24bc3e838c1eff2de831058ef3989d3b824d61867a59ffec2a3fa3e26683c6608c20e4f75f72e67fef660faccf1a491b6642d08c95e4	1	0	\\x000000010000000000800003b2005a94044317d3549cd54f1a1840bd6a1c57acb7dc91d2e76a22b4e7b89cd777d61b91220069410536d33130a03a75b24a1e7d02406fdf6665dc9185c05f55bc3811edaf5de67d64d29f76d2ee386d2cf44c28e19618414cd7182524d3af8c9f379c9442d1550df728a2e0e59d5e21584ebdf246221b0a262a9f4609c6a891010001	\\xd47569503d02d08a869bf3e847f49fef099fd9f5ae1907c63b292e3f2e39036dbe8091d59f0ec84c74d6178ebe9f494b14a6d96df22e7ac1c8f7ac499fa6100f	1678998607000000	1679603407000000	1742675407000000	1837283407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
178	\\x9719a8396a0871c0a1e80e179c3d209f69ea05157b9c7b3a2515c3b809bc4ca6c154b298641821aef48f0789c113fd2d68fa4ece2906b6063fc11743f5011df3	1	0	\\x000000010000000000800003c52b96b493a97d8e6dd3511ca7a1208b543c135445318c2ce0ba0d3f6322a995e9ca42671dab2ca1f997784e49916fae0f90d8963d1dbdd7212d007ab0cccbe16309e34ff1f70333cc79fdb2afeb97da598f02c2f47a42a26761b71b501f22558a80c1714c361f5f31dfe8087d9b64ff991d336f87d20eeb85149ae2ecd1cb3d010001	\\x0de6add4dd1dbbbc4dada1b7182895e90b564776a321091190a0b4364751d0fcb25402b4873607f96eae2125f2248a9e393a53ad4e553874961638c5999e0f08	1666304107000000	1666908907000000	1729980907000000	1824588907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xa3b9fc9d3dd849be6b508d7f72e06ef3d86ac1b508b83cfa0dfeacf1f3cc602daa525a03aed6a632a1932e80d14dcbe7c42c11ae9dedf23202dd01f95a32e563	1	0	\\x0000000100000000008000039d27023225a5258c38013f54e918411030706e55dde1ee8b970fa9f522b4a8434d340d0e0e0f16bcf329707050887d08d78be11b3d40fda2c4fdc4dbe891ac69b3cbc204bbc9c37c92208e42951addd840ef9d4fe7331589b1e67b3e80d2caa12aa8cb62bdbf0ba031fa77f9777c0774fbba873e15ea987bb2987c2a214bbccb010001	\\xf231b76ef6fea0e6f772f6948f38b1760ba48ea50cf66b9e8f1b875a19b42a5adfb855fcc5e2db1cbce9d590c6b01e562776b9b39ff3cc6b1128fadcbd5e3100	1669931107000000	1670535907000000	1733607907000000	1828215907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xa5192b1706658427666a21bfbc82ca9f791f31c2e8e79e375ee0986cb3e302aceb9d8ace8e11ef460034535645bf55bedc75ae0a0685ef7a0c6fbcd1d3afa4b7	1	0	\\x000000010000000000800003fd9d7d44f3daff189e098e00c813798d77d3ca12c8fe421208e91a90b1f752670034d76008c534a70bfa79eb5b947bb607dfd134ad9a8cccf14e8764020d7b5245435d0a4d41959227f3a99c71a31a880a9441a1d6ff0693e9648562a4f608312f8b4b0396fde7aecbc39e09dcac15e2e3a62a52c216ad5cd98daca0e6dc2a85010001	\\x9297fd5058c6c0575082a454fc546375a0e79433cbb5819f95d65f77da87fbf6b327f62ee5af01787387ee652a88bb71246ca6c2f459bb0c7e65c6fbd5eef10f	1660259107000000	1660863907000000	1723935907000000	1818543907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
181	\\xa7690870a76f4153935ed70d030295c586bb3d9ce7cd43603aac4344dcb31aa52585fde0b76ed210166f98e154101d688b95ff9170e4a387c283fd0c2b48ea88	1	0	\\x000000010000000000800003b7fccc54e572db563f5013ac46d56cf11b0e20eb1cb6536d80af63833c536cff064baf7cdd2abd7a4f46b3f52f4cba6b499228e9ba5b353abb068922b0b7d5c974108f703c16dd6c126dfa080e204985df69491af76a4a76c0f43eaee72c269876d871153dc5d21034fc7985dc74aec5f58b5831446d45dc1fbdea40d7d8c351010001	\\xc6d0dc2360b574d8abc23480752305c279cc68e55c63fbec5fea32fdaaec632d822e381847d50f083d4f705dca120b993bfabc59f9036f79a07edea5511fdf0e	1663281607000000	1663886407000000	1726958407000000	1821566407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xa879a9226e521d3d8ce74e34b1e997b1d1ebc0b70d0aee61e1d97c451be921c69b3e7d4194715e36592f33f5909ee8625edd763f7fee491ff361d0771d591b44	1	0	\\x000000010000000000800003cec9c3bad8c51409eed14dc41d62e8b8b713505a837678fdb9b01b5e806b0b3a5d6a6298294402fe8139e8f46b958fec5bc2da91c7a82bdc184ef74c69af59125e15e9e76b88170ccc354f294dd6909bad558419432c5f5da02d2cf721c3f61bd92141825c5779b7bdb806e859cae49692acb86d046dc9be6f01e4e29f2c714b010001	\\xc3de8c7e6621e2a871b842f0d2599779c84f98ba60f475d17348b44fde493a72b97863bc55d96a20f52b9783064d650e2914de7ba82323f0f8eea951661d5f07	1675371607000000	1675976407000000	1739048407000000	1833656407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
183	\\xaa9d6adc6de76084e493f853e942642a40d1933a5733bf63fbdd553e01b52bce31af2ce16a022d0c1b88d24a28a67cba79f0827b2c3ca272c36d8793c28eb673	1	0	\\x000000010000000000800003acf2bc290137f9ef78dcaf020aa2df7a2521e4b1b71aefca2fa6c18ce475ddf65ba7159e8ce57a85b262978ba2afc1b83612f20418fc5ad245ea989a4e3e20cc49f004d42351af2bdc2cf96c6c8c5ab5b8dd11e29b517a86ee1c15dac9a429a01249f9e22ea31ec67d8a8e9adf05aa686586f2c15bb7071c18cfe472ee603163010001	\\xb393e04c169d51f9eb2ae48b01d0e94b54ef0768d16758cc9f713be555fc73e86be4e2d5495b0a5ccb84a4bd3940406740efc52227029b07e4ea85813e096305	1666908607000000	1667513407000000	1730585407000000	1825193407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xab091eb83b5e7af7c0413c4a18f51b84dbbcd0a89649dedcb9f4c47acb9ed59277c50cf29a6eb27bfe81d767e225a82ff5849bc2744b710ef511a73049c2ce79	1	0	\\x000000010000000000800003d606f2053aafe855de91c533bc2ffe8f84d93dc2d8b1edf13d8f0b1fa46e014315d866b06172d593c55fb9f5a3b77fbca77d3f6a9642cd5891f6d4df5fbada1df7f2f1e2cd4549b65c390b20e35503d922ce602c5b818476be1880d2343ac3aae5733ce3f72d3e3be775bf6f96a3c35d1442284a517f62af6b50a8a0c3f2602b010001	\\xab52c316844b17816a3f3623eb36d3c64aa66c646529667c72a9e67a5a13cc403d4bdbd6e141e7389c39c41b275361c3eb47bcaa6998fd0d86310fad27e4e80c	1662072607000000	1662677407000000	1725749407000000	1820357407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
185	\\xad61a52a6f58e212ab096fcd12d0d1f98bdd6d9f115aac1628d2bf12bafd946b4477f68a0d45bedb7471e3b61c113f77d549c5578f025879b7d8ea31955f7b73	1	0	\\x000000010000000000800003da04f9610d68445b84ee842cf25df666669dc99645f61a2ed659d1a715395e677322229ca5ffbd07fda1d6f16a455ddaff6f9483e3bdb5322dd7274b64e94f9eca4dc4e96da2091130a8a80d6c31da101f8433c4a9ed5cc4b4f778504a01b060a5e91e4179d601488502a301b158f1d7945292a4bc46abb2501885606d4bb093010001	\\x509510e0ff21e7a9c132b676d2a8352d8bac9d45a34eb5ca9fc27790fbb56f2327277e25661ff616455d26b8dfa3d76f106701ec8fefd42b94db9da8645bff01	1654818607000000	1655423407000000	1718495407000000	1813103407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
186	\\xad5953db4f4582bdc03bbcbf78ab69b8454fd9b822b9ae0709f94727e297c6311134767e840715b7d4330e9b521e1d45569fe917af8993490fea5e26051f2e61	1	0	\\x000000010000000000800003e2321e31b07aaa0c4db21565edc825a21fae22384d753f58826f011f0a6b44c78e88b7e9a1c015e2bc6f154c9984c449d734b4b682b142f68f973200df778fe3339859bb8d54c03f4b22dcfa2b33d9895c42495da15a65fbf5f793ccb5bb6a2dada1fcc85a77d2321f7fd792f03c0847f2055f93cf992db15896c7847fd03951010001	\\xd67abd8239635ad1a6b30e69bd8175e6d2c113c2744223f2587defd59028b7143050fa97ddd3935055b931f6f01a9f367d6fd65b3daaa4fa8de066d96790a80d	1655423107000000	1656027907000000	1719099907000000	1813707907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xaebd57c98e284d5986c1e4e0cb776f21307158c03bee13474cc688ac3bdbbc69147389a5925f59b8767c12937f9705ba408a3124626c6111f643c39a16ecd775	1	0	\\x000000010000000000800003c17f75a66919a038788fe47471cd32070525e65898976aeebd16e0bac0b3ed2815ae857e0b9e97a258572020067c88763b5baec30b8557e21826be6076522848514bf35a7ca3f7a856c52e4a6f16098df10090509eb074f1426e29dd5451bd5ef870946364cdbe1d91e69911f844f4c75675ddf7b592c6c911f38fc03d660d5f010001	\\xeded57353113d43cdd6e2a7a55375f27bb109496be0dd3e1381c87dd6388f596dc650ff698ee07b0f75850370a814cc3298b70f47be7f577ae5813dd82174b06	1648773607000000	1649378407000000	1712450407000000	1807058407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
188	\\xaf19ab59d1c51b556fe7f32be97e368f743fc06c0920be3ffc189284aa62cf548a3ce223222613ca5ecf70a94e1cfdc0ba315185bca1b543d1cf373064c2b7c4	1	0	\\x000000010000000000800003b0d45093c855d11cce56eef4944c3944741ee601b4cff29f97660ba34ba3bf1f8d409dab66ae0b6340320e22e60690fe238b5a36189e689b76f1ee10a77679246af4baf3614549b7218ffceca84a3bb34e97fd486110b23c47e346612471a4c30b4c8da5a01cf11b6b9a005a0efa572c72597a0eb922c60da8830c76a39e0d51010001	\\xbf72ef9561dba904b9aa5cd5e462e2782d5ef00759e2436d403e4d5300cf7acf0dc4007f87dcd80c6693bafc86d23057d2054d38814f7bba8900b01e3aab040e	1669326607000000	1669931407000000	1733003407000000	1827611407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xb025695b8022fdb6664e4cd7addd5ef3dce13d64cc43620c9016b05607392b3e99d17316b6bfb090f85aca93821d7961f07739a976ff9bffa82050043aabaf09	1	0	\\x000000010000000000800003e6f29068d836a8ff416049b954831d0cf15bc802152f2ab834e855c5433bf573c3b3b347c06d4a3250cf4d97da10b789475b4fecefbba6dcf30d642b8aec864aab3bd9ad36b3181dc8d6d2e94ff5619d2cf73e05acd8405bb964475ce052ad7cb7f6fee9babe47d96ca7c19186a39c0794e619643040eda3dc26a2857422c475010001	\\x5a0bf0b45c20c41e8c8990aa613b32946fdd9bfe33c0180f666102c34f92981c322a25ca040574f9d48b506ab3128b57015466230268cc9b03599349d0d11509	1655423107000000	1656027907000000	1719099907000000	1813707907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xb0dd2f4adf6465536ddfc7331f96a3435fc9810c52a1b1f611a43451583dd4ddfba215c4b29fb4ac4511af37caad5c1e1a8f6a68f6848d05eda8a5439706241f	1	0	\\x000000010000000000800003af3f5342760d23638b4639c1d04b983e7c3d066c5a22f9b3c317ad105dedf2a9eb26ebae14045d7666f392e4f2022e17e21943ecb78061fbac4f2e251f04983e82551114d169dcfb6bf738f767767663c0f7c461ecbcffe76694dd77f51e9e5a079038eafc31c5f45017849ae017388591cd01718d67a60c2defc3035c40b7d9010001	\\x1031acc574c29c545965b88ca00cc0439d032453c2556d5a3352b4f5c5d65452ffd8f9b7fef2640b916c276167d43c239e87aa708661a11d8f59273ca89a2102	1652400607000000	1653005407000000	1716077407000000	1810685407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xb0617af5671fcaf7a98ae17d658960c83dc6ecce551508df03017eaa6984d298c796873c06b0860f7ac93efcd2821e00d0dca17f4b97b310792d20f6178a222d	1	0	\\x000000010000000000800003e0b8e58d85e4c77212d16d75d99d83cfc6e8f2c32cfaeb12751dc7a38b1afb647297ef28c70e46cb75ac9ccc5b87c711d5fc3b7c044ce3fe4be2057ab97b391fb4f4e15cbf93be368d375d10063f3a9b1adcdc9fdb6024fb926697df4f68a084ab60c1291cc0a5132cde91aac376d6ca52a760e4233c52c56e192804a382ae5d010001	\\x5e349f23280ccc78b84ada24681d294139be1070c6e6be9c73aaedefaf668fd9840f3a0dc9c1923788c993d9498bab44e71605cc2f14c5ddd0acf6dd5a7afd0b	1650587107000000	1651191907000000	1714263907000000	1808871907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xb33dd55f023e41915386f347caca05fa337aa7ec5926196d1e9b5873ceee38a85589e1f240ccee65a0093787454ef5b458947d70d5bb68cdae3b2ae790095905	1	0	\\x000000010000000000800003bdc998155176f509def922117e767211947c8781160510713b68ead3dc53655fee4d17abdcc5c6d94950c5d92ceaa8e506768c394257cac58b6d5a8ae6b0748cb5ea0fa8715a1ebb076cc3019c49dd0b830c4575650df6d59ec9fc29f3ae5d64080b2ffeadf7e8a6ddcdc95d046fb0e37dc93baba50760cf92555aac4ce984fb010001	\\x8270fe7b461378869136e9b82df3ffe57a95db089a2b7bc9aa12d2bc3eda8c329c55e7edc9cb6891e535ee762eb6f37439a8526aa2d32b085c7fd9a5156fda0f	1666908607000000	1667513407000000	1730585407000000	1825193407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
193	\\xb64d60deec206ad6c376b75476588382a25fc8864d7d14ea096852368e8e365b5e15eb951e975a9a2f6e6a86d1ecb880d8f8e0d132d24e5344c11ae58e85a207	1	0	\\x000000010000000000800003c5cc5ea9bc8a968fa28773dc5351b8fd233b3f5536ca735f56c92c3dfb73d5b48a3c4ab30a4e32767ce32c0b24d12208850f66e51b9ee7c4fb43f18c27246b825af73de5e8f5a6d77937c7186bc13de24343f8e3e4a80cdae376cdd64e417b7eb7499937631a85d7f8e46838dc5b7713aea806cddc9b2d02263211a83f1d57f1010001	\\xb0215fdbe2b8f79c23a0de70ec615c6ad0df4e1969b12e18694fbb69d912969eec40db11ce1bafa58fad6e7622beb0541a29c7cfd06a09cae70e2b43ebccd008	1676580607000000	1677185407000000	1740257407000000	1834865407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
194	\\xbb0563c24a66c7bb4d5b9f427f93bd6b7ecbface54600a2f3713d2cbd2dd05fb65f8bde6503305e6f3355b52d67f27cd1fee9c9b73358b1d6cbce3d83b584e5b	1	0	\\x000000010000000000800003cf342c25fa74e919bc90ff9cb9b48b8789b8b2266d14e708ee75a686099fecde93f2124c7a9502295bac8e58529bb761bdb0372f56ba46c2df236d46c11d89c8debbb43fb3690137758127e120b189245edc71d9260ae5a89cfda3c7b89037dff24b8258db8e9dd99e17e27e98132185c43d07047ad50a0beed6a6ce000ff2e9010001	\\x12487f45fe2c1f0469d25538a1252cf682f81969a68c46c5c6ab01eae31c10dfc3f1138b99c2067fdef3823f11afb2b4d2144c1e74b44a60c4eef5fd378d5f0d	1655423107000000	1656027907000000	1719099907000000	1813707907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
195	\\xbecd3f04e50d9b998295650769588fa8a8a98fa4eab52e54ebc5f433822ac9f92d958d11c4cf1c9d151f7b911548b4d5a2c9a50ffd5b2b18934bca2b62b8c19b	1	0	\\x000000010000000000800003c91b8583bfc122ee6d4327c3b47a38462d13b4e9ba59562c4267cc50ad119848e7bd8ad132e82e0fab9c691be063490acf8835f6748384e7c03c447e22a59ab27d04bc4e06f14549218585c54e3be20e964477e9450ba2e3cadf0af4a22e93ec9424af58f45962a57d6258acd122cce9aa03f64a3dbfc51145b0483b63a1f49f010001	\\xda34210f4590c62924b4d42eb890f260c26d07ebddf62d2059c4e189b71ced74c672f2274f13a9676e6da2a77692429081155c1f37f189b5cba6eea15526ba0b	1656027607000000	1656632407000000	1719704407000000	1814312407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xc2a5fce6ff04001c000eb117e72ad299cc2f77a0eb7eeb6a1e8b3127bb4d1b6786d348b23adad72360e0d026216ac4fd890d3aa58bd4d730583eda32269ab4d3	1	0	\\x0000000100000000008000039d31679c987c984d681311a68087bc0a22c72e6aa3a64af6e740a2a702638085b5e0cd9db699d75f7491243695612c55b82b3dbc625b75ba41b973ef46b9e7eb7d5675fc09a49d37c042dc0ee884b81a1220b8799235954541e94b5a0a9ead9ef62b182f9bc7db3ca622936dba04156c305ef47a6453fa10e1dec76de6fca17b010001	\\xda922a2b0ed8d2e614153e87487b0ac50ec090b0b56cb17247af9bf8379d5a2aff1bc9900eb6d7a1e948fb238847c09fd331e715b97ff2f124badf1b3c2eb80f	1649982607000000	1650587407000000	1713659407000000	1808267407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
197	\\xca61947542ebef6e24ac2645012738fb4d8bcdbd48adc8f2c6d014e822e01fd2737e74c0b3e8e6ae362556e0db260a09202471ab1208b30c17eb871ad2cfcabb	1	0	\\x000000010000000000800003c3a3bf1bc3761cdc74a0899d10ecabb998c358c846b6ae322536539150bce89a29295568264970e531ce71a01915a2f8cc2cd5de6825df6b4d6a4f532f065427d2013df225d71fe35d45420b354b1a3eeb4511f371fd37de7d3380d0f6d90cfa4f4339d807282f5525363cc8d317c0cda4df4c615c8c59a1df0bb072707340f1010001	\\x8c57098f1f0c2e74aba06bda32a714ef9799f7fffe29ddbb8042c6cee8e7687b0ccfc4c6bcf67124496a314bd77da1f6db8e338aeac01f85e9555fd4df14a506	1647564607000000	1648169407000000	1711241407000000	1805849407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xcdadf229a132259c1210703814acfc555ad27536a711f888146f2c86524129900b99ad003c278657164f45686b722dc6f04c5b299e0c30e6a1701447af0d645c	1	0	\\x000000010000000000800003cd3d9cbc95da8cb6cc67d3c2d86993a395364d97e9b2c56d874a96fa87efe605cc2d86ff8df5265c0b563086471b89ac2ea0c7973b9d9decaf208c36c7a5bbd4bcdb04e9d9ff041a4d108b34b6cf0c4ab5ee28e9ba6d4cc1d0153d215adf107eea44b99b6f293f13072d0010c8e54104b2b1629680efd5d3f3a9eb10e140d54b010001	\\xd6e220def7d2965ff9db46ef082a164061bf756e350e919c07756640f41f219ec96f09950ad883126c412995a1db67b4a31715b8b287b6f6d167eb2a7462b803	1664490607000000	1665095407000000	1728167407000000	1822775407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
199	\\xd7e1d0796651b641fa1330c7fa9976f69fdcba4caaaeeafe0a2f1cf58ca0dbbeb00027a6aedd963ddc6cb3f14b36903fb590a55175c2013078b2e16dd58e380a	1	0	\\x000000010000000000800003affc65b3f19df9f3a51d7f8d3607b9249cb86964f2e650b4a3fa1fe90f74377a59823bcfe94cb2b67b9f12ae0b2bb4afd1f2814452faee52f6ac792e1d3f8d9fabc02607cc50686585830f3b48eb97c9264a3c5b9d693b5b4aff3032185d62b362092a2974d25ea8b239e5e513e42ca6322391cb561902216da5b6c16480eaab010001	\\x46148f2d6d2e3cbf822b09683a002a9c946605166ad14c605722add4fecbd8d9c5af0dcd821b74077ab515b4851f2e321a1532ccb9be1c70853903434486bf0a	1677789607000000	1678394407000000	1741466407000000	1836074407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
200	\\xdfa11c5382d2fb90b10cc53a7b7ff07aa69ced09919add8c600da37b82593fe82b5233baeee7c98d481cc341fac8c356d5c6a5ff32542d37f19a593f5d7177ba	1	0	\\x000000010000000000800003c4df1629155921b92a20cdad3628b86ba6631178361ff156706b04e35c71c447c5082e03cc0026e69753b9b03f9d62a52ef07d3d885017a52f5e008ee1030d7094333344b70149cf1db803b96496bc373ab6939ba90edf0e3603c395e6a65b880bdc9cdd404bcfb310bb453518247682e364b63cfe25008b93b3b63f982a0e29010001	\\x2432553e6f9e6b7f42ee8393613e624c8975dfe1b30d68d4252c57eff500366b942a1b783b1faaf54577846a2c43e0e6d632ac1864585779fae45569e6f1fd02	1669326607000000	1669931407000000	1733003407000000	1827611407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\xe7091f53d9425db606756544e047fd80249692285a31597fb41e3de3173d53d8ccfaeaf6e204af1ee0879088bdcaffdafc306cac06358c225833a9324c2e1f76	1	0	\\x000000010000000000800003faa07b76eb4b38d36f952258db646929a132db48821f78cf3acdd47b6c73c83e6969ce0788b54abc9deee83ac0361e5e5592f321470a075c49cc2c169b12dc7e487a3e011de4a527821e982f0743c1fe64e64fad1deb894005c2d1c828c01a7cd28cb141d5aadb2ea2d031daf0e8b42d3d4609364e327b596bd084c4441eea51010001	\\x88592636d2602de02937b525f634baedbc029638b6026c9b8a0b0e5da90415010392df6e1e30165e50fae087d27d3d68051f5c6630a29cd3868e7dd2ce3c530b	1657841107000000	1658445907000000	1721517907000000	1816125907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
202	\\xe76150fda1d6899eff1ba2c4664afe1f2e1809750e9fd1d12ca9a68213c1b8523436d1c7e9a2036592919f1f3319de1771bc4c8f476395df409ffb8105ab048e	1	0	\\x000000010000000000800003e8fa9ad171c7e49ea9acd8a2c8dbd49753d894fb5b141cc2d02ff023655131c39045d713dde0a6708b5cb915d87aaf01ab1fdc3589865636e4b387aaf41e26d29b7fe14d4af7907bebf5565b680b65161f74ab5a74aa0c7ecf585cc15d41b110d4b83bf270c8b32ef8dfd3a23d9a8ba61330e65b2e7aaeb11765b05baa2d4f29010001	\\x71500cf60a62f74b8fe9807afa3fb16820ba0e3f3fdfb7a2fa8559724ebcf9c2cce193f43f31c73f7316da6581f2d57180c95245fe4e15b8e2743137d096700f	1651191607000000	1651796407000000	1714868407000000	1809476407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
203	\\xeb6d5e9d1da8fd3d62f0a586366d13fef893f739343c61f1c9c2103441bf9f0eeea94eecb22c2da4aaa0fadeb82bde39d3d01d424892331d213278922fb5536c	1	0	\\x000000010000000000800003d50279718552698a25bdadcb1d34c3f0eb49e37e3d117a6db9f57d77cbf503185eb897e49108ea83ef480ab3df903ce3ade3c1175ef237bb0ab82862886d16e0576fcf4ef14a178c22db3b7a51f21431d9b58b68d34923471f8ee891cc0261b8974e34376e9785a2503d2bb85281c22e450d85fd5c8d52c00d56e36431c84d37010001	\\xaa11f899c515695d403f7538d07192a4952b9f6d849c67c92e0753dddece446e2267c6c45c3ac0a5d973f6cf7ba7ca38cd435006d0cd83429c940debf95c5b0c	1656027607000000	1656632407000000	1719704407000000	1814312407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xec4939a5d743f64d92e7af34a99fd971e6a7f82db79a4c3a747f6f3de013b0bebc5a123b37d9507e83c3585db8c4ba13c37d4124becf6a52baa865482ab8a12e	1	0	\\x000000010000000000800003f1a7990a6f25656ffddc45ada947b0d7c86ca14be15449f51f20b32bd13e9fc0a97d6431e276df2df334ce794f432b656ea7ea763dd737f9b93b2b9489b10e27cc6d325077614bbe8c31be2b00bac61a4290af4b5d67e83bd5f1c314ceaf5be0bb651071ad2a44dfb55b19ad9cf578e91d812915618fe67454a97dcc319814a1010001	\\xf568a16457f477ce5ec0afeaae9c228f1d97869fd2a814614a3f2c93a4376eae8cd5adcf03af9a2cba75cfd21dbdc7b699911a3387beabb8c99d92a1637ea00f	1667513107000000	1668117907000000	1731189907000000	1825797907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xee81e037f8b571ac82f981e920b964835913c3cb4ab67e28155ae0dc1ab29e3ca53f78608b406d4be3b0580ddce103ec38f94eb1d5afeb5905cca5ad82224854	1	0	\\x000000010000000000800003b8c563e39dffc21e096859668a4fb742f92d9e9440b2a6048fd15b1250019653303b72de668293b7edbe650af943115914f24037aaec5c36c253501c282e19b221a8573c0974090c60b8a0b055002a2778d0adf631e7522280a50089bc24bca76d39bac1c558b679995581ed797545ff031df1a6dff7d224d1a386327b32447f010001	\\x5c69279ae75aa5758bb64532dd588db6d507a2f50b49c3cac831a8ed8b1c16dbe77b8ea90ff3dda64cc6818f67693c905432ffc11156a8f927b4d28931e1e006	1666304107000000	1666908907000000	1729980907000000	1824588907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
206	\\xef79bc43c913314c0fc092256f33259bcf7417cabb4014d5fe1dfad10c14fa9620f1af6f76eb87ee83c175771fc8a8b732401af1b32ef002ae4c7819a2c3f46b	1	0	\\x000000010000000000800003c7b6d5bd93cecab63fb23c6e87aa7b63b461ef28d3d5bf518c7347286a36ab82d66327e9e5fefc299f30c93bd519f7f18e55e22595cb2fd2d3ebf8a8bbcf3d9aca478472914a1da8ec75b9dc1d8eb4787cbd1ac8a0cad9f9456571d1ba5a4b01b7c582434a2c39ff78e89db13717c24f9641c00693704f53ee17847c97bc47c1010001	\\x263cb7d10922bdd9f87c354b0a701ab3cc645239558b8779ba739c3715554cdec7bfdea221382b31a0f1e484df1fdb45570fa47b65e4d1a9a8e699321d480604	1663886107000000	1664490907000000	1727562907000000	1822170907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
207	\\xf3f5daf6fd6373808e352c33e726ea7193b9081225e8a1f2fad3268cdb2ec83d151d72d23e550cfd60da0c7b9410316cfe51ddb0e2a142d8b66e8a2e3f395f76	1	0	\\x000000010000000000800003d3d93d9d8f54c8a3fcee5cb757c1ba087736d90486317f4f35ec3bf1711a26c74b439c0d84419322588d0512c92a34a40a90c2ef0ba8e7e680d08cf7d5236c676b45c6cbc2680dec393f52a37ecb845b3e967c7fae616a7faf8afb93d1ca1458936660138265127ecfd7ebfdecdff333e922f196362bce1bce44091821d23b13010001	\\xd3f6c6e7fcdcc58433d29b47c336d0566d9e27d664362b1184a354ea8991fdea4e915aa83cad10f0e99c03293368fa6819d1f59d5be57f57adb6c5dce1a73401	1677789607000000	1678394407000000	1741466407000000	1836074407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\xf709a69fa96fe52d74b08d44aace8c507af732b19f547d2bb5064c1ad6185ccb0d9b6cf36b460aa7ec939edf234ee7a631ced2d3de246574d4ca9d8de4cb71e3	1	0	\\x000000010000000000800003b629c13d900eace789bfc37a4fb631be670d45b2c28c71e217189ac41ac205ab88741fdf0eca812a2464a877ca7ccc9cfbc4e4865d44731bcbe53898d0dda74efeb3560323a7a6ebf56a7a48f588a11f37a25cfb5bed4899719193d423b706cf0f7f58f5331cb5a224f245f6b7086203e256cd80df035d1066f3c3f2f5173b83010001	\\xff58d5880fc5f220246a0733e789ac5114e48ce6784ef339276794fec1817123e5125f2c11adcd9c470833d43ac446c79be2a98f7e85da3692147b2dea3b1b05	1654818607000000	1655423407000000	1718495407000000	1813103407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
209	\\xf7cd22dff1dbe20ad0313d8bf1e46e7162494ce3b57b3daabe9daed4a0987380b3cf7718c0e373def3871338089356a8dd0ae5cb09deb4e7daa4638944c541a4	1	0	\\x000000010000000000800003a756b33e525539ed84eebed2bad800eeed6c1f32e31316478f945a979310294f80825504bc9ef5392feb9366dfa7fab15c4ae53eeae91cf6a5b4c67352b20a8c899a535a90111047a3672d7e6d72d359ee94fc45473e201417566927444d52fc9d217587d7043170b46172569d9d1654c82357a55c649151a777f855d5089933010001	\\xaf3b52625a6c36bf8f723012ffae8b08a556eebec8b339bd149b2aa4ebaf6fd288d3b48d7046a6ee9fc5ed69b28c8fc8852cc8de32d09893b4a021d8dbac150c	1651796107000000	1652400907000000	1715472907000000	1810080907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
210	\\xf8fd762a8ecdee76d49b15f66e415815d5f6f9ec4ae80ec0a5b3a73be287a1c9474408a15795c5b71fe74de924b7d0ffa1fb06ca10503cad3c2dc5145508bcd4	1	0	\\x000000010000000000800003b0034c555ab9a1e2a88bbb670c68e1264d00c5a1164600e948c04f24850ad2e832205e8ab7c0157bfe48ded3db0f6865f19133c0807c932bd15f186efb7e7a4587b7f43d807ff730a45ce896ff828b593e90c3155d14ec016e2b8eee7a56e8b8e57e708708bd34dc24e0983d56368f73309586dc7cdf82fe815b8614aa4d1ee9010001	\\xbcf0c4eb3ecd04e245ba463800cb3172161d83b186aca083e4239ea96052180a196ab5f86c76de6790f9678a243bcb792c831ad63c03671800b0092057ff8303	1649982607000000	1650587407000000	1713659407000000	1808267407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
211	\\xfa2d7f5e5a48a63f79fe45c515f6ac8d99310e25f01f10c44ac14429b9f8cc58abc4d12d1d9cfeabed85f42e1c37c4f0c6277f603cfbafe7b4b754391df2e0e0	1	0	\\x000000010000000000800003b60fbeac11e06134c431de51b0b656149905dab60a691ff3b3e4a22ec53e6eb4028de528d42ea4bd7c07503cd1b46e5abef3605bb0fecedf165fe5bb4639c30470229293f34ab688d120961a3998e2aa346b8667bd660fdf7aa0e2e26363760b009b683eb62ee1eac77da00e44c53aac76a6c569e9c54ac67399b7b306756049010001	\\x2256bc19c03b5db9c34fd833b6b5d79d1f51b6e25143b2c194bdec58bffff09ec6bbb988fd795f5a3f0452f1e273918795eace5c1de71e21a7ff9891f6de9107	1671744607000000	1672349407000000	1735421407000000	1830029407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
212	\\xfa814e7a51029c01b2027725164f155d87acc43ab5771f2c3a02bdc6d0651ab60e2d2cce7522c0aad729a8e25fdd2872ac05ca71856ec138549c8fba9a421363	1	0	\\x000000010000000000800003bc4b1bb065ab088689a86759dc2c6b0d1f96fc034c3ddebecbd8aca531638d3583a1d8ccec91afa5937564de7d963e04f971f6020106131e4bea5ae271c06614ec737827eddcbfd9ae76fe02394b7edf57ba7cf4edb5ca8d5b382f48f0ec082e06ff3390e544c059698d3e3c2d65d965b66182c94507a8906938e2bbb2821bf1010001	\\xd22ed6c506125cccf5bebd359fca1a60b56ccbffb762f45c0891f503681cadfb6b7d1ab6bcbc27c87ebdcca3ad5d9ec41e2cb005f7dc0af37cd58209bbcd1509	1661468107000000	1662072907000000	1725144907000000	1819752907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
213	\\xfa51e918c6fd266de6b2ce6d4b1af7802ed54d622206fcde4e7e4b302a5fd5a4530a98114d514a4dcd4f78503be464435a79122a2667cf0b3371f327ed1adc99	1	0	\\x00000001000000000080000395356806bdbcfdbd3f0d77a8e8f7d7794d53b45e27d9a1dea759613da1fd44c37cc21642fac86a6eedd1a7ee5ec40ffa91d65a1214734cbac455e32b506d3beb213a0df4f4f66e80be20d30a03e530d95572ab7595a7f30fea4f4eca28c91429a6a6ff3232897eefa8e67f54384c9e9d49eb6ea07650309be71d002b5fe2b2d1010001	\\xd0df17a3b057d959e3255e58e1d1b2e36f64bda02bff50ea15606330a25e47e58959ad5321796e7dfd4a682d9d0ae117756469d8bff7ad9d9bb5f0b04fc5ab05	1658445607000000	1659050407000000	1722122407000000	1816730407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\xfcf9b91e1712bb7a00f2fd5b7aaa73ab0b0b0996b0fb2b75a441dcb465bbda76a284dfffd2a31e429aef05b045361a6031e98cf2dbbd0c38331d9ac9fc98a951	1	0	\\x000000010000000000800003c56bd47b57030d10443b6884b61fe6f624efc572b14dd08cc103368902c0b03bfe4b7c5648cf9ea46336d8f550e74ffc9603abd2edb2d0ae2b821fd84a9991f5fda1ee4d519d0877aeddcdab129e6ea8cfbf30ba68a4e9efb6db96ebf6fbffd195fef16967907d25350ec0661589675d3676a8eff7985b27bbc26cdeb8c2472d010001	\\x7844a7f696568b62083ba00797aaa75cd0752a87a745bb416ad674041da59e2c1c2b131238e5c3c13c3379412669497a7dda72fdeb410b4d73563141e019b102	1665095107000000	1665699907000000	1728771907000000	1823379907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\x001eb53bf6c2bf3fb0fad66a6b39735722cc2aeddea3ce497201fab76f46bbf91494d8b94e01fef0df6266de9a5a325513066c362db813b9da52287ca08e8372	1	0	\\x000000010000000000800003da628e7fe7c961266e5e09d79ac018cde2933d627e3115458a0cebab4ae3202b8a9ec21f11083f36f4538324ddd5fc946b03e02ea9e9e33884f2f478aa70e7189500eb0418d62abcffd04d8c0773d6932dc9e402e9478c1b90da92a394be7a4fb6d0422bfa2cae918ba2670b908970b0dacb46c58801f0b1b18725595bccea85010001	\\x6a04e148e45ae898162ee4e5436ca59d3357a58040a2ae8bebbacc34381aa02c6e837b68a19eb285a430b17418af87510f9b4021b6f129a0cd495f5bb44b4302	1668117607000000	1668722407000000	1731794407000000	1826402407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
216	\\x01f209b67fe9c7b10e698f8116f0aeb503fdf7755928c655698eca8d5e49e32a8520a14b90e9c8d70dd35b8a4732eaea60557a115db2428aec94867ee5b4051e	1	0	\\x000000010000000000800003b24e6580c77bdf68de94caff9c46f0e72b2758cdbcebdd260c4cac7dedb76f836afa0e426fb43eb7d25e9847b2fb5ad72cb2c64e39c6600976c5d937f31dca95197db48056246bd14f3154b20b7dc2e105ebef232699897c3f3d955e8b52afe77671fd6b1dde1ae607ea87c7784d19ffb36a141ac9ce44c2e55d57f50a28308d010001	\\x488f02321c3359f7c3b640d58cf71596e81f2be00b703dd0cfe3fdf7ac47cee2ae3397f3f69e2b99766e2a0080485277bd0825095eb807e754316c56e9f4ba0c	1660863607000000	1661468407000000	1724540407000000	1819148407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
217	\\x054eddfef3cb759eb231952838891909870ca9a25535c631a3a78b0a14ca350addb10eb73db4d1e39847053379d01aa9e6d4d0340d6611f3a3980adc44e903cc	1	0	\\x000000010000000000800003c582a1fbbc7a3bf52d4df2867f533da0f6926c65e276b485aa28e21b42c5e6fa074829b091fb220017821f7eee229c8dafa44d8f01476e23e50d4874bc23740fa51dcebdfec682a6ca74910177db4bdffc79aa9275f104729ad403ee2398368155f76b7b409fe31c8d704c2e42c7342762ef9ed14e68dd786d577b4f7fd6e9dd010001	\\xb11eb46da52f10d6bd6bc51284e3ce1b79bd859b23693b5febe6b0619e456b3c83abe40d9e1ea7b7514e3a86d1ac6b58b648a69acd325635b3739bf91ad62f0a	1669326607000000	1669931407000000	1733003407000000	1827611407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\x06ae96a2a468a0b8b4f05e5ef18809fea802e9882fcf19e3e5930ceec8227f69cd438b53c9f91e43dd09dbfc76b5c8e8f0f56ea21eaac2503319738f3555179a	1	0	\\x000000010000000000800003d64c3fe2fcc16a827dd22ac97cdaa874c6f881b9496459fa223870bf526ea441fe0b98806e2c4b618a202a10df7688ef02eef947b933ac47bf38fcf2b515ee26f16d6f7e20d8928419ca8e4f171b92099fef60963975a9f3c3817435d91408bc8f2d58467649be27cc535a6b6b65fab25bb69a38b23f0c31a92f9c5f81faf601010001	\\xc76bbc0576fecc2644d104ceb31a5faf7daca4e00b92a0e660f8389677919b0817a2823785f59ea86615e08e28f3b1707ef77224f96dd103d835b8f070d7b203	1657236607000000	1657841407000000	1720913407000000	1815521407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
219	\\x06ba3ac43c5efa1364ead732a131ea36fb44bd55d32cf098a5c73643ba46ddc871f800c9dd814addd9dd489df2b0e729fa97bc05c03ef5bfdec38be4c06c77d8	1	0	\\x000000010000000000800003c28d5f93c64ccc4fce3aa604d468d5865f2fedf4ac672e4e55afc4dbae7908666115a741fb8e613c59d81af4eb3b00efd4bf6ed5ec72a0b3b20632052ceba3c9c53fbfedbd819c9b15079e5d594be3372af3d8258132c59896198ad04b46c640ac83728a200d4af5f4d81c5f09cbcce299806352ae40d763a2998586012f6ee3010001	\\x7f9cc6dfdee56547a18f45aebd8fe4c23bd745d0cb89fd4224c3d0196b2f3a4913d39cb506a20132f9cc9e3a0c73ec3ed8994aee2b66733d732dcc3da458b90d	1677789607000000	1678394407000000	1741466407000000	1836074407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x070e916f59c27f8f9cd5188404bb5f749a5161c8b1d883235ff877a99144342bd349f10cf622cd130c123e487d93362ff5ffc3dc3592fc9cac92aef072e66e7d	1	0	\\x000000010000000000800003d6b0cc3a27e82f9f40d7d9b30b01ea48fd0480dedbf0b9f0ff9ca63caa6618a9a2548d99c725f97d176e6b6d01e3929b301936d8a602c9d06cb6ac4a9e49d232d423552cdd43f1d33d746437acbafe5c0da36805bf767c67419eec69d79e8cd641df5edfa5879a31ee398cd5bdf54f7b78bd52f8c8ea954e63d944b26e3fa5ff010001	\\x5578eb9d06a33a87b5f9595cea8589e551a05ab2667b2985e6341b6671a11cf530367b03c58bc0a256a1ab37c2a19b4c38c5eb5f2189a8a592c0dc8cc3d7270d	1673558107000000	1674162907000000	1737234907000000	1831842907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
221	\\x09f68153d0cc49a16d4d1b51c85bc435bfd647f3a9a748fdc4c6a1802c83e098ce012c2a2a3c25b954d1e134548930364b78ad2f5a2290430f18e5c444f85ee5	1	0	\\x000000010000000000800003df6e49135b3592396ca6a1f6b652aa4760af7cf7d2a9a41cb3b0aa038bfc301ef42769df9731a6e36db05c02b9d8d4a3d99644aa4179886034ba574242b049684d7e3f884f8b01eb96d692ea31c11322000f8e86c7e4237932bc3bb2c62e7b3d4b309cb6860499fef66e8e2c188964580b05db8c63bd68e72fb713943e2577dd010001	\\x2d6c937a74b3639eba7fe9aab3a261923d0e68cf5bef565a3ddbc58f64f214d6c746c5d63d734c680eae29355fd160f54fb1ac98645d71fecd7cf55bb8827201	1678998607000000	1679603407000000	1742675407000000	1837283407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x0c5e11b4fd27cf4d24a94aac71fa6facd8ac5ab6287912cab71faae131164c0d1565f05d4a6289cdf3f96ffa63b5660afd0d5428302fe0d4159e58f190f2f4c7	1	0	\\x000000010000000000800003b5164948ef588eda2749d3594d5ee6bc25cce3a52d467ae6659fd902b73bdeead7b1a1c9e52e6b86c59386d61bc7395bf32da0c497311d469062d2e9483d9ce324570e27b97c5a5f98ac4379214a1fa37252d3404616ccd505e503ee57491b051227f513ae2341e0314e248c1e54ccb715262a6f9f6c5a2a088729509f9314c3010001	\\x0fa2109679ac4fc32a367ddccb43f69146d3530ac6edff7f647bad4869662fcb7a03060098a7335c05ad40caf891c60d71e8b212b4243ff6e40103c123602204	1662677107000000	1663281907000000	1726353907000000	1820961907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
223	\\x10feb8ce471a1327c9bf87c7016b2e82edc304867a2d79d1883bba4ac600cd49748274d017c92703bd01edcabccbf84955797d8a6cc838643e1d63926c7b23d3	1	0	\\x000000010000000000800003d0f46a6775683108b2f3b8add5d5fef9aebb4b030690abbaa64c6a4cbc732432a0d0eceb3c841b1f50ec1eb191e23876ad5f82ccaf8daa5af59ed1e084c0b5fda165ad06cd555c48fb01c3c6a900b236410fec84101e53d0146c6852a4cdcc0814e26b3e88e7b4f26dc9d831211c93b2de3d3eaf11179ec4cd70b1347891ae37010001	\\x88b9fa57faacfe6ade2f42e3b7fb3c02fbdaed920deae6b1ac0c810240b1fb52b1fa849324e398a8b04bf696ac8cd8a569e8b17cea9f734970b9a113a55e9402	1649378107000000	1649982907000000	1713054907000000	1807662907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
224	\\x13aa7cc009ecb8cf0ca4c5d96cddeabdf7ac18513616ac7826bf4da8f84515246e030f530472f0dcf4a428ffa715739e409ba5e80cd4fc2d867ec685cb89a3d1	1	0	\\x000000010000000000800003a9a1fd73eed6ca33a630c93f163aa73cf80893d827c93981cc7322cf90318e3390a688ac558e6ba46db48fd5ac338d5dd906f1db7c1e1fe240cf40c63e57c0efb1c0c6ef50c85ff63a8b5987012f26b56130d81e5ec811051ca7ed18ec77b1f9d50e469acd31ff1b2b782b6f3041c0fa08ecdeef8c1c69909f5a6f16a0757237010001	\\xec1cb52acf7c0c0d4cf1f26c4b19709e6b6fdd3665f8612f134b837cd80806e7ad24bf5a5a1e0fbd71ce472faa69f565053471951c9199d69fa76724af3e2902	1652400607000000	1653005407000000	1716077407000000	1810685407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
225	\\x139a96adf0063b93262ee650ce5db8f13e888bc4626346116ab1cabf8188e8f6464951a2f89f2cc642d345fa935512e90438634c5f7597facd0819524dd1e52a	1	0	\\x000000010000000000800003da522f9bf1daf53d19296d7d54846dd2533fce418d79d76444c5961218c1a11c3dc1bec23874265babca02f687a0d0b69659b0cd14ac0537b39e0d8d8997ae0243c825d58998bc971b915987a83f5456b94600e1fb5c933de7508db3a2569bfdd7df3bb120bfab6fe5e4121fc2eb4e134c6522e7e957f912eef6649a02fb10d7010001	\\x5ea30659fc19a41aeb4013f174b3c711cc5d54744b51ff74c837672b166a666c86c626f28fa6ef75440a58838e40d837bb80d1d69a1e3ab4a31447a6b7b83c0b	1648773607000000	1649378407000000	1712450407000000	1807058407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
226	\\x14da817c81b96944b281b5625ac18b420ff92628dd424dc07964dc9d94f19e49513b79d182d737daf3b5df5069dc63057318770c4e9b661f0dc0032eca0d9e1e	1	0	\\x000000010000000000800003b97f98b91d3c44261683bbb8dd66eb2c4481f78009672b0a0c65bd0c72fdfa14f4865c395c987df75781d8ec1dc206e217cdd111d8edc837abd1c6ebc4c42afcb68c25a18eeb0741de4d9608f4077ee2962f1c145c4eddbdef6091c85d9b8e5dcaa098da0fa7bbfd858701ca3aa085d2efac974b88bdf2a30401441b9c596a11010001	\\xfc4c1a44cb1e24907f53cb8f483975844c82610ce2e0047b689f3ba37cc4b997ff420aad7ebdab179138093d3f0fc55469dfcf0913860906463390574ad7d70b	1655423107000000	1656027907000000	1719099907000000	1813707907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
227	\\x1da69fce4877216580bc7c3c0156bf013b95ceaf2dca95ea0b293def107a4c0db5a82e0e8bb8088e6b5dcaa43e40c482dd103f856d3ec9d23b6794e94a4fb970	1	0	\\x000000010000000000800003dbc805e5dd2f91eff59a93cf5541e56f59c20d4bdb17ebbec6e445e61ee64ac658196df953d5028996edc307985c43250e4a78ceac4d81b7c59ad6de59f2f15d3853118211df520e22d4b5b265cec065b25181a49a394d3bbe43b0844e0112e4018aec1b0d1f39d349f8d7d4e65bf25d582815b7aaddb11622b4e009ca7eb885010001	\\x124104b49439054061a60f5923872e777f47c259fa60322a196b1624e7326266815c602a306201138ac1c299c4b59b778e5cbebf9dfbe14cef71cc75ae905601	1656632107000000	1657236907000000	1720308907000000	1814916907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x2246cc3513bf26226c92b0745f3523a5512cb57704db5e67ff4d5859bebac991b47d792ae9ab7a6033effb8fc719e5ecc4d41445d79699e047024a4c29f93ee8	1	0	\\x000000010000000000800003c20df0389c3b1049016e8572e7cc37d0bc350b49fe1be201e3199febbbe0d68cd6080302913133a336d0d8fe61779ce162a6c6a0108ebad021c737215020e2dec798c2e47d4ead7319772159aedb54f76190346cee643e58ca62f97beea4b45cc9656b7a790d5825d73f78f77cf0080a5cbf9d1fbd54923418c34cac2d5e84fd010001	\\x504575abc9d429f823db5efca56db69b84d351bfacae1a67da9c14af8c1add1ff820242b91e9154ebbd0d66ab9bedcac026b96002a72256bcd32494227b13403	1672953607000000	1673558407000000	1736630407000000	1831238407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
229	\\x22221fceae12dd7488eddeba496781ec82a5316e6f1fcaec86a951ce6eb8fdb5c66e2010cb655d1794a54689a7b342397deb145c7d42e78d2de2b881789180d4	1	0	\\x000000010000000000800003d81d7d01afedfd5a703f056745ce60aa1d61ea1cc4e2d70ea43cbc5015d95f3531bc3d2092f4026d41a2969f2ce88223e2d05bd151036baea121ada630b7b022cc19517220016547b01beb9599de8c87495d8348adb13260dfb652b2d88d1ef2664f92c70cbb9e414a4a9dbea591357f968825793e600b122573de9fc823ad6f010001	\\xc61b174c02d6e3873411b281285d90a433f195a10e401039bd3cf522392fe92f9521628d4652c6733e4f4a0663cb5720be014dc380aad6968e40af94db18ba02	1669326607000000	1669931407000000	1733003407000000	1827611407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
230	\\x220653ac5ae2c1ff9c92c5304aa0a306d97400a175b828790962e870d446b1c1ea6f64e1ec4faa277742e93d338fb0d38966e1a96201e7b47981afdcf393fb37	1	0	\\x000000010000000000800003e4a3a286550caea9d3ced922d240e2d985944015d7c129f5bb4d9bf20fb6d3aea02d5cd1ccc2df75cf39c9d46a5381fac2970633eed07cc78214b5212a81fbb0dece70e411312a207fe3f5e0beed370deda321b24410e95c7c9dd5016d845d43377328a270aa67a5ecedb4383fa7f56aa1822e9f0aa270be74ea23dce66ebbe1010001	\\x920215bb72de015c15f0ce90fba18b320c4f63f19f69a333c2a7290f4b1e95c82ad3137927c1b1f9a10e0139f30028ab0e2b194459f7753cdc176027e657190e	1653005107000000	1653609907000000	1716681907000000	1811289907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
231	\\x25027f87f0542947d0f4797dbdaebff616286e8b53cbe6b05a87243ba36139006db4657a4b06e524a2628385994ca6ed20775ea59a7130c43ae09748c3f2c4b3	1	0	\\x000000010000000000800003db2bf3c4509c58d3566b36be74a7d75bfcc5719d355a3f03b51a5be0a295cf86524124519c3c1ebed5fea30cd61c5d709228027f9418611bd9a246ac70d7fc2ee2a3696205f08e9f7948035e3d8efad125692b08ddbdffec377a55961104312eb9a1775c99fe71ca9031d078e0169d058d9ea1662cbb68bdf4c44dd50b1d4373010001	\\x7aa933ee72d06d554b74d2a03ca9a1f2a647c1f418e0e3c318bb3dc411bc684aad0653056345ad4932102d7e4a5a41c706498657327a9c55e335ba8d9ca9cb06	1648169107000000	1648773907000000	1711845907000000	1806453907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x271e21df6849f3bc710f1fa8ae3ff3ebc1c9d6c874f37f15b5bd0ab4ba1eb6b5502e154321a9b2ef5ce01a4d3540cde63ea5fe527e9110c3330166be8ae092e8	1	0	\\x000000010000000000800003c36b2b16ad0f7b5402a506af862443b3e01b4a14c3278389e9bed2179a3718a42ccd7b878a973597f1d61210f4f31caeb10092abca3face7e7fd5146f10a2060bb99261946e8a91396dd9a32f35762f3d1d0654abea869496444a776b98531e277eddac8ed68386a7d0e6525ae9f72a0fff17928bbc096b74636dc897bae9e1d010001	\\xeec65841ac09129b5927a6f4cff0aa082c04f7840d33a9399d0a86843820438f15d51a6a2821fe59b44752dc126ea20587d8c67e8f717d2d54f3277037e4cc08	1651796107000000	1652400907000000	1715472907000000	1810080907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x284e8b584906b51937c5c1e58bbb5ac589badd18a84e8547e75c8da5a54834fea0740ddec46767ab2515d9a75a006c10806c84f878e885974ae24b9b199af50f	1	0	\\x000000010000000000800003ac1ddf6f43f608b19889bfc7d44279bb6bbef982e2373b1fa77dc52e478b2a24646e2d769441b8827e0742507c0de2ef0c08a3b8398506b2a042691ca8401ce49a9a2036913e70fc88a66c5b066fbc8319293735ecbbacc48d33a8b96b7c719af43d3ebfdaf22b0b28d65cc11127f18ba0364e480faac29d584a4e9f9368c8d9010001	\\xf4fe47c99a3c0e9b6217eb65abd2302bd41ec5cb946d5106efd8ec46fb16ac998ee9d42fb67451d804df0eb5d70d10f49fb1a29474263ee5270d5844ffdcd00e	1673558107000000	1674162907000000	1737234907000000	1831842907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
234	\\x2abe9040c7e0af31629dec6e6cc044a897f126728d08483bbdddbb7a62d0bdbeacf3c1b9dd6db11bd84e285c42f9e7ad0d5047c1b371b63116602fa9c918a756	1	0	\\x000000010000000000800003f639f8072742bfe3c704e39396eb344e994614108416e75893aa5c54099ccc6ebb1e570a9e4adb49aca9ad9c5606e1879fa3e732eb3c3e07bfb986deb5b0172fafe723210eb055f3dc9827e3c987b6316d9196288d784d79e5ca44164a4dd544556b6c7326945e998367c92e7b8cd373ae5f6bb58116801bbbd865763c29454f010001	\\xf098b673e57aa86143044b96e71c75d5bc5a94088e8e5e8e5134295affe68f99b9ad12b1fbd311f9f3f3fcfd0b48340d89232e9815bf155a2fb992a3949a080b	1651796107000000	1652400907000000	1715472907000000	1810080907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
235	\\x2b3ec1a044d2da6753a91a67540f1c150fffe8654facf401dc035493c86f575eed9c6edc9b1876f1d7001fdc5db3fbc1d7cfe6da5599e1ed4cdb886c422def49	1	0	\\x000000010000000000800003b06575d10c3100b53e3c54a195646fe233b254f2fbdca4b204d43e3625d93eca2560563faff9af08b91a39e2ef08b0105b267bb0ee8743600d65d886a2d9e579f884f7dae693d03d2195e90f20143287c67e62e27567e2173adaa3801f245bcd15280661da9c55496594bd587f2d2f3ab08c803a4bce3f308a0352e80b9f08c9010001	\\xb905d9012b1a5083bb040243b3cfb3d65486f73ef1d896e5863ba88b75aa20f1ef21f377cd75fc57f979c13d0850b93a0e487cbb8c8d00e2dfac8d6c58b69f0e	1649378107000000	1649982907000000	1713054907000000	1807662907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x2b86187b570c2ff760325ac70c9241d003234e0a085e45dd8f83287dfb981ecaef2dad6227a979d69ef7b058876c4ee53bb7a89cf21fee93f0a37d33dd0d0742	1	0	\\x0000000100000000008000039f9f928371ca68b7d9189e16bc41201bb03d2a13fee9138163e84eb23c917c864c477534ac042e695e65ce50a322d0f9cedb4cbdbd6cc5f6d286904c2ff73c446edce0caaa4753805dadac44c9eae844553a7fd941526b41e86242dbd0c11a98cbe9f2a81f26d19ca82790ba17ea79473ca641a64f080e5651f29e986738ea61010001	\\x226d913ec4b705ab14c13d0cf395f296cd97daeb824087c0cb1ce595b56525391c567eb641676d0051f5ef34295226fcd3930e1cbc826ea1b4ac69da8778fd00	1662677107000000	1663281907000000	1726353907000000	1820961907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
237	\\x2be6af73c6eb2d42d0a16db932046cb1a73c60d2f598ea50d375f5d5490adce9ebd083581afac9aa5aeeb1215e37b27974856580edde792a2ce17099158dee58	1	0	\\x000000010000000000800003bbe822e3b029ce194d1413bcb1e5932a9f57cc3a3a3be15c65d55183b6adb4c0ddf74f7d3c96bb1dd51ebb2b4d99e100809146d5976d91dcef7b46bdcf9010aefb5ff4f8703bf4bc86a1744622a7426b988c621e436517f46b5ce42e74f3ab0241de846cd15b51e25cb994414d40374c31eac0c305dd3193c792e2bc9fc16151010001	\\x830b5914826d53e3c04f43227a80ad0b646437bf028bdc5193689d6968dc3a37fc810cfe21a407ddda8b2147479515ab5fb87f3f26cb7a83241f30f60d933103	1653609607000000	1654214407000000	1717286407000000	1811894407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
238	\\x2c5a7b09f7c464e157f7835be380d744b6f3a293bb254d932aa214ab458a5600993adfcc338ace73a3679626a105f1a1d45ade92e81efc57458c4bc24198a2b2	1	0	\\x000000010000000000800003d290b9e76927f3bfd88716c3b367cc5df9bf1ddf8a94c8d90cbcf5ff68785eb43a2a2f3a645f61f2f441f7c78737f08ab4159a083f8b3d15423aeea61225ebadd1ba8d1b8c5477c514f2672d52f14a4e287665175a6ca8d791464ff3513176ba807e037798b5c1ca11eb1eaa445b9ff12570ca94103560edc4f3c919dd17f4c7010001	\\xe04c8755a65d5ff68420fa44f577515312fbbec82c3853b78fc06bd8ef65d135ef7bc4b7a0648f49aff983016c6cc9ddca21e5e9b3c0e8e66b5b9a0752af070b	1654818607000000	1655423407000000	1718495407000000	1813103407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
239	\\x2dead27be12947f9666735b0d59968e3d41de304411209b7fdbf8a0c911e07220822977623529a60be20e4735953de00583d08ce95dc4b7628162b43e54aaf61	1	0	\\x000000010000000000800003f8e7cb1b1615aaa60a01f80c0e93d43992c7c93a921bb6e58c702e726326ea996ef03fcd8f3c5f65d48f3210a2d44e2fe71fb8cdb57296844bad56cc67301471fc479b37bc1b893b42e1032153aea8f1e4212a0965776866692f12d31ef6fc8bb110905d564eb3078c76b3fd6be78b7fecb180ba34664c500eea42301995a4e1010001	\\x69ad8be0e1cf2ee4d2d435e5d4c85496ea1f3bb5ad5abb01222ff30b7400b9bc4f3460fbbbb77d528b0e5150fadf794d0850c1639ac239e603985a5427f3ff03	1659654607000000	1660259407000000	1723331407000000	1817939407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
240	\\x2e0e9e63155ecf13b40d870aa6b2859e7f2987c73bb7a37623c85e67925147f9905aa0e6d71c6820d480fcf01074d12101ba62f776b86254c941ec86bb510bf5	1	0	\\x000000010000000000800003b54d8f3213aa267f439e0edfc2f7c8f34408cff46331b6afcc967dba47aff29f62b9943e8c6da505def698965af8c891c29e4eef417ae95237981e69247c421a7efc12a351f91481388a6e70b99d9b75800238c4e964eafa933fe48fb3f52f20d61918afd0ab0455f04c36257f87adf1dc09db37c89823092d371bc3d28be423010001	\\xaac0342c8dfaa3e0002b55167a00420f12a469eccf3717c9ffd982757527940b3a572088a96036a3d1aa8e473da26bd07ec0551e8bf74fd6c780c25cf2b9b002	1669931107000000	1670535907000000	1733607907000000	1828215907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x327695051a392919d0dbc7cf35342a246fe62ca11221ef5c73df249c0c175b4d2310128943ccfa326d1c1bafcf7d9e17fe472096eb1b7ce4c06fde1dd028ead8	1	0	\\x000000010000000000800003d217d058519405e60525806048ee9770b3886a803de780746165211f6807bec844a101b415343952cb5bb34b4fe36ae16b25a69e25db67f92a0eebd74e3e771c815825afd32f317851ce7ef9490346dcb4476f23aad325163a1e843f85be9c1e99b756d0a74dbb3234c845948e66f9f91e4104d0f301fe006447c5ee883c5429010001	\\x3c2b74fac0d1d8102499c2844b203ac53ef067181d8929f889b43dd351470316c682cef427e1e7fcbc9613e265d7d94fca5a85aa9fee5dd4636cb89a4fb5a000	1674767107000000	1675371907000000	1738443907000000	1833051907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x36ce4229c91763978bd06d824a703cc93ff3ff08893ba280c9ded60f5af3e87ac767e79fa28ce3edc60c160cf4741fc947079047e2beada97e8fbcac81cd4970	1	0	\\x000000010000000000800003aec9dab7ff6415710f6434fcda1d02388d3b241645588f0c936e31c15a147494bd119572cdb70718c336fbfda8758476dd2ef2f729389efd66a8bd07c3e98acdbf801afeaf05a00bee4fc3e52ddf9e3b68fcdc2089a44a3b5a28772d468b7a150e70a5fbbc63e6fd96f9ffc37b8cd3db1aa1059a756438a530d7e544f73ca5f9010001	\\x5bf30bf5144debed3a2d48638178d53281796bed941d4390b7ef5405b53a59b49e2c654bc3f66ac2c2802308a560de3a4a8f9a4753cc85256d49eef078672309	1666304107000000	1666908907000000	1729980907000000	1824588907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
243	\\x3d4e0b45549d1cde8e8354012b226cae356a607fd173dd9bb580cfe243276727cd4cce88c6afbc1df9140c48f10c1a0f7e393b2ead5a7ffb090f3a2dc3cd4a6a	1	0	\\x000000010000000000800003ef17d6599f20aaa5440fb4852438a9dfdf240f0c176c6815ab49835ba18c56e17aee1e2ed4a2ae5acd65ce310b45432097602dae97cd55362a2b70929469be010d3f52cc77af7c90f2d8ffecec40ef2c09acc29951c5ad39c60089f132d78285c841f32ec07b2b36713df66197b7e86542b3d4033d9b0ab860dad9ec5d38f2bf010001	\\x6819cfb12518f8eff501dd2f002e8cee5b849a012faeeb93ee81699c9cf518a4ac4c3c99981f5a440a7d4e7d6a540e2c3e5bab4e2ff97f962174ecab3a04b701	1665699607000000	1666304407000000	1729376407000000	1823984407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x416ef2e835681411b5f792156adcbdacba03a3ab1787010780e603428d077fabcc79a5b3757f1926195387dcb5c35a4ea607875061395a4ab1d36ac8fad13696	1	0	\\x000000010000000000800003f7e82b959eed04c58a57c8a0d1f6c31f363fb3caf148367d7bb5fb5075aff504cdf3b7cbfca2485d84b682cff81e0483151e1a3a872053a1824f1fc1f2190f8db6c3462b20fe3a67453e0bdce1bcf3bb8dbde44cebff52821596a7210111965476b9693635ed16bc2a89e0f11dabe456d992f94e019ec3c22c9f8ccc991d6b67010001	\\x16f746fa39b38643a2e0474de10014fd860e08fdb1d1f8eb0b1f3487b4f6d0d0a1262574b7aeae2e626318a9326e8b027c689daf739aa77c37d55b9ae8aee807	1652400607000000	1653005407000000	1716077407000000	1810685407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
245	\\x4352dda1a5d5072855f6f44c608cb713047b4f376de343ea292ab74838d83e948bf3dccd2e43ea73122e998f4e1f97970eda6ecc43676645ffe06a850a875c46	1	0	\\x000000010000000000800003cfcf242e7c2152b5082f5cf1df0b1071b8f8fd44ce3f6a3acad90b9b34a49a8a6c920561e577376a3ec3c513d98578dfb5248d26f37388f9c8bfaa3790bee6e7693bface713b73d313a844adc82f8b443c58ef1ba6586d9f9df0355be280a90e2704d6387202051c367678741c3ba03f17a96f5bacc68013ebd58a56e79a92bb010001	\\x76eb3aa5354df0169a3943f33d24708f9b62891b87be85ed7823fc8143b81c8b0837447dd1ddeab172cc073fbdeb0f1412c265c3ef5e8c6ffad0ee4ddfee9c0c	1658445607000000	1659050407000000	1722122407000000	1816730407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x488a535ffc32b2455331ce67981ad24e928ba96a50f48a5edf87d386b53e57cf5fafb08852683ef08affb75c8f9c5ccbae841de6f28aa83eb0b9001fb9e5da9e	1	0	\\x000000010000000000800003ca6d929d5a338e7fb482f4ad589676608bcdcc93660851eddeb57a042a2e7880c32fc8eba6cebb618795010024b8923f4f0fea7ad9d0c0cdbc8f57a927c840b1d65f17ec3778bf4228ff5ef6f409e1e4c031741ddce1eecbe5502979a317cbf9eb5798c3032d35e8d833e24ca6b47482da39b80c5fb044e7148d2a310802b28d010001	\\x9bf1187a7f8a246bdd932f60c8973b9b37bddcb3bdd899f369263a6b496451b6fad6ea8d138424f94bd914c4c7fb779d70418d50fb1effaa6b338d254d40c008	1674767107000000	1675371907000000	1738443907000000	1833051907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
247	\\x4a3efbe927aada7e7b526a2789fe9214c688addf5f787ace67874a4a626ebb8c3de444d226b21d2cec66b066a6bea0998cb6177b085dd1b54c5925c4aed358a4	1	0	\\x000000010000000000800003cb6433718a5aab801fc718c2269ee28bd8a425444f126f587163cac8a6f413e20cb04abe14c64c960919666f9623f9bd6097bc27b57bd3df21a693a88cc17913a1ece7dc400a6a1a8592a9271d4aaeda87deeadeace508519635d57a8eb0a1a72a61b40bf6fd293f587cf8b0fbb4235c92da99796e55e1811f0bf7e84154def1010001	\\x1b58d099e692f8fd0a4648695f62224e4533410e5857c97d673d3c8f8596ef350e90452e09100ebb8baf82e77cbbc84ccd61ddde4142ee2e57bc61b4c537700e	1677185107000000	1677789907000000	1740861907000000	1835469907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
248	\\x4e8a61a59ca7744d78021b5ca7c04ef0d6d23b2a0ed568082467e4249b2c13557f833344d1c961f253686244030222aa7861f606e9e61f74baaa1bcaaf5866b4	1	0	\\x000000010000000000800003dd0f8415011a7bdf3e7c5d012a77956377a8eb5c05f753837053a8b5dedebbe140984844b7a29f5ba8dfab3acef5e039e6823658ab89e12403f38aa6416ee94cd69403429345e47e9b1a54eff2d9b23f8794bde0c490c21c4e5f91c092f21d03dd340fc42c84883d33c3ebed8b191b56046298af9f200111e9c0378530909cfd010001	\\x1a531b5d527b95fa1073de4c52aed6cb5c8646f34645a8c3d82cd1b243ec1a81aa169fc7f6536a6691f3fce4710785cec6726940a5306281c93c48465d0ad206	1651796107000000	1652400907000000	1715472907000000	1810080907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x54aee4f3ed7bdc810d4e60393b78b5e032540ce513d25f1bc3533eb78696410b00794f46bdff6124b78591c8f9d6d6e75c3866cefb03af59264ffb3f1d72d9db	1	0	\\x000000010000000000800003b7a06adc91ec0d72362bf3c93ec3e30ed6692192b3513f328952aac00309378ce5680b81e6517c785a3e6a9ad3ca1a39e64ab4b3eb0cd0913c669a71084bcb4b3006571bcc830cf28e6809484238558690246bb6d762bf563edd3eb72eb8f4c00478bd5eb366a667ae9272a49ca41c9dbdb65daf30e9547c31e045a99cdbb75d010001	\\x8330b4518f986aa467875ae1d15eef6965675c88c0353621a40e21fd0ca260e6669cc318a6243e9998e8a61a872ed5f25b99e0e1ad2dd93c36a0a1f6faa1fc02	1669326607000000	1669931407000000	1733003407000000	1827611407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x569e92a82ad9c5cab1b8d9658fcc2adfe4e4c643f75ca5c7647524f7e7911e332663a2f06daf8eded0873af92271d07c6b931d659dede3146d7f67f458524eb7	1	0	\\x000000010000000000800003b3bd50ae977a253400494652432352402277185e2ccdd11413699ef388b629da24f60b75f9e07986a36d019ff8239be7b1fb33255e7c481d2fe145ecd5a47f26114df7cae53498441d21be7ec867d2268412a13a9c1963727bdd17e713d2cec554cfdfddfe08d5a494378c0619e5391485c1c4100d76b373eabcd21401dd3db1010001	\\xba82659ea4c7352124bd866d8421584064c3fe2a0085f48eb0e2dbfe747211321aef0a8107a848bbf4806f48f0948ea8a2b4921bfd312661bb0e4e56812b5905	1657841107000000	1658445907000000	1721517907000000	1816125907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
251	\\x5666e1b8f056dd836907e43654eeb4e5a1d7dfa948f4be7ef7ea777680a4d8eb6dd2b7fc3959cc324c332ba923dbdf568017c17b47ec60e9618f6083f9831e32	1	0	\\x000000010000000000800003ba2f6cecd84f4cea7c38a8b0b946af023ebea793068be2606cea80e740f91e77c19e7e8c33472e34c9e6c273e11d394d7b1147056fd870fe044612c7bad9205f49ddaa4f9d7fe9ec2ac41fae182d1f38d09bac9e2849361e39068f2c998440911e3ddfbd87d2179cbcbe87254b66a1cece74588eca5173935cccb019b014194d010001	\\x54254e5e28be91dca68f51642f5bb258b473f8ca059445b2ddb78680b8665803539407f1ba57ff18b3a4bff09b68a4ba7cbc1be071a427ab85fa29068e0cbe02	1653005107000000	1653609907000000	1716681907000000	1811289907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
252	\\x56e2b8b2d29bb077af8fef787a8a73c8840e2e0436967345a653010d76ba052d4bfe1a38c8a67eb82dafe117b44c524277cc6d4c8dc61f9cb618f6ed69328981	1	0	\\x000000010000000000800003dd0da32e8c888ac42343c73ec90ff49881ce5a64de2da77b3fed607ff8464d0a9f11cadb9f56afe336328e9a687fdd9273b59e71bde3083069bc4d73591ab35916db6299135ed0ef1e7bf448dd083161653727d5b602f934bd32d940cb0f3d693662dfc18f902790ad681bbe05be4d5747a11945518d3bc77925140361bfeb1b010001	\\xa1a1ffd9efd907ad04fdfb8a1c721c7748f84f002b284cd7f85ce70b688b75109bac8759c0d216d47935fc277db7a2121106b2e0d69385a38654311776f9e808	1674162607000000	1674767407000000	1737839407000000	1832447407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
253	\\x567ecadfcc5cccd3eadd337d7c8e1ec545868d0aefe02452fec75aceae9a193721e8773d591edc0c689bf186655c89c11d25ece528eae54bbe81ec47ea705820	1	0	\\x000000010000000000800003b8ddc2ae8a7fe5bc29223a569fdb564366edf31d2ce3b18b86173a7de1194d29f80623801e96d5ccf5f0d3110abca20c94a6e334685cea5683b99c9b6a4d784cad678acbb5547a3164fc4ab72628521f32813224b39498f5f24cef3b4278e8c726f592805307c5b83d65cf1da09e839c0ef04c3d7b025654995fda4a57149dcd010001	\\x47cdbc2a749b7657eb269f4cde6e7b0dcd8331e68a713a154b44ad7b815423ccd3d4d24107f93980bcea4e9d57b641e0a64c9980008f574d79f980935021810d	1656632107000000	1657236907000000	1720308907000000	1814916907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x5856fa349831d8e8df5362d1632854b695709bdfba06fc63581ce5809f07a036f663386248f68a0ace9ea07d0679f59cc70f48e9721e473faf464480d8894bff	1	0	\\x000000010000000000800003b9fce50c8608f03f2b1a39e333db7a95eaf1c8bb1c340bd6089b5ae35af9ddff93dddad12da33ffb678eba6ed056b2bc55771d6f948ed4abca4c0e8e6295e01b4bfb3ce41d6f74a5c40f802653a9a472e48052508a69f00de32a7e55dcd40f093a8a804bc2d112ac022d2d364aa4a868512084ef3087d033157a2fbfcafc4c79010001	\\xb94ba9ca59382cca710dc319d51e2b196cbc863712ddf80daef1c3d9c2b4616aaf1fcb7b2dfd1634bd9fcf682fe3fab377e319ca168a22d165d1541706b75707	1656632107000000	1657236907000000	1720308907000000	1814916907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
255	\\x581e82cc98427a826c75c567507c2dae0a2180a46b154b51be62a2f259fab886efb08ed95b0891c90efa1f1345a6bf19955d68d3cbcfb76f1bb5e8443e75b1be	1	0	\\x000000010000000000800003af356f84c09dd33124ec70090a5ee86e25130336da3a1d8c08102eff4150b94d776fbf2f60b0527741fc56eb071ace04c536584e4d6af131391d86d2977f8cafbd2bc5f6c832db26ef701e7854eca2c3b01a106edd07dae5eca0801c54cbda375c5b35b192e878188cce0c06ce7a0d47571fac86a0060444359ba6b48dd692b3010001	\\xb7fbf0b77d2684d73407a467959bd5e117ff5817fb89bc9853219b14e04f9fb68423140ce5c61e2604ef41b1dcb5534bbedb4251b818bd57f30de4f336486107	1660259107000000	1660863907000000	1723935907000000	1818543907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x5a8adcfb7824b418b84c4a6300c737d5626b98ce7c49c17125451cf017c0e58021f00395c3a9964d27399e2acb440fb4db3ac4e9f4d763468244e6a21a9ccdd1	1	0	\\x000000010000000000800003afd5df83db44c5955e0ffe2b17a8ebff3e8d36f9a1e445a3737c1d33917b342876f0ce344baad28c88907f1b7fadc81344740eefbcbfcefd686aa49d0aaae2b15694e042e32a932b8122dd486cd24d48e8101f26cdb73a03d9c931a77603238b407bea04af09a9fcdcd74bfd7030e7c010d7908f1756290dc8e7aa419e5a7bc9010001	\\xd34aef0f394d9e2c10b84f5691b5fd35b7ab41dfc0aa75c136cf85f855c2800496c3f2a201c0440d37bbffcc3d87285e8fcf761d61627e92b8715f7fefb4ac08	1670535607000000	1671140407000000	1734212407000000	1828820407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
257	\\x5d5271ade3b2ad2fa8535a655dedeca94c0eea52ba57c858777eacf83acfbc37d00edd8b8e4ed3cc4d2443130093fb4d08faaadcdb5729a81f0a722c0222c979	1	0	\\x000000010000000000800003e0df675eccd5536a74172b16c6e04fa0d70f5f1ed4a06c2c5ace980da5fadbc20bbc8b7faaf51b3cf986758cbe68fc8f0de63d056db2eaf0bedbc011097be93aa58550d9450d5e21c61c46c428c3e1e568e6c2dbdfb1170b55172df005d95ffa2e09b01a633aaae0a238c2bda1701f1a1a7295643ae16d6a28d1f3c0a630d193010001	\\x523f465d760657e301181c6002e0e05dd248bf356ec11eaf3966d65cb202bc2420eda2238839505ae914dcbf452121af78d1753d7eca5de748269fb300027407	1676580607000000	1677185407000000	1740257407000000	1834865407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x5fee157fcb4d3cec85df234fd39ad5c94704990bda9045df96f9f3a514c30bf90dcaa7c693c090bb2b06b33aba7b3feb8ff59d53227032681e0ba96b53229dd1	1	0	\\x000000010000000000800003bd45b9a2bb3b0bcaa67c2e3760622995e7b513f4ce8119090aa6b87b5f641612c65fc092448e02a5a881ee53fbabc4439072ee7707da817f5e3671aac5689641f263543531411075cdd9692163e4d5e7185a1a760aee8335a8163d460a411a439af30128f5b41ffa265d63f8608efcfeb69f335f64a58b2046bcbcf359486921010001	\\xcadbe3cfeb62893d50a5c05ebbc373bf130bd638113c521fd57c0bac5a7f5d9219152c02928df60f518bbe9be6f21063adbdd3dd78dadcd631b91d7d6b6d7e03	1659654607000000	1660259407000000	1723331407000000	1817939407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
259	\\x6692503a89930d753952b37b7ae7a2ec43f85743647daf892c22da08d3bb16ff6940f3a84cfc17dd06a9800eeabc84e0b820686d2aad28d328668da240ac6d91	1	0	\\x000000010000000000800003f984f256829314df989c07100d1f93f6f49dc17969511eb745faf2b2033b2a09c20f5099cae36805f2cfe08f65db92a34a530609ae04d35c0fd77edee99d3721678f7106676f96d357797306ab3ed62e4fc213f4d8b26ac9951a5f7cf11cbfd4c29347dcca867ec8766b10bf93acd6d5aa49d17782dd1ddaa6cbcebb7735efe7010001	\\xde7146ec623cb2e75565aa4cb03f14fa6c0ada0869caad78fad0a4974d63fdd7b5c9952b5a69e09ddb250937110edd098fe064dc1b9d3ee1cfddc570cdfdc008	1666304107000000	1666908907000000	1729980907000000	1824588907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x67521431452d10b8975118041637e7134161e213b980cc49e8d8c7c7f4cc12843bd80607e83a8a2d881ff7adfd382017b640644491c3ea205b1fb82911b52097	1	0	\\x000000010000000000800003f552f2d2c7a5491d4e50c94ed08bc5fcada1dad065a58b885670341c0174bc17a483e97a7970ded2b20bc941b9f34988b62b65c92b90048971dd7acf2155b3cb5a6479575281600164f3325b5b478c733e10eb33d8499b22bd15f171ff81adfd99f6871588b45b79f82428cb42642644a6df28462a674d4ee3d1d48b3e39227f010001	\\xb1adc822339ff191e9f379af38c837bde8677e8d18a3e4f128e60fedc847ab960b87c70a66cb2c56fa752d2c71c8d77f22b2aca8e337e6dcd2d18bdf702a9903	1648773607000000	1649378407000000	1712450407000000	1807058407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
261	\\x69de9c070a66df099900e4e95a05e33b44b559c1c767383c9b86d57d43520fee2e590d3a5e2d8055b709b19a3bba8fcc2a982f3791da1cd3cd0cc9cbcb5e860d	1	0	\\x000000010000000000800003abd677d90f002d1456e26b1e2f4de29522d0725e0a17ad38521184da39a72267921017a66c7f64cba64a001705648a3f50b1233238d206d2ef034cc529df9f0cd2826e2f91ec35a610db905d1d47b7b3e693bb2c003a8c6dda61d6c871bf8a373907f8291820eae04f933dec94f654233b09d97fae7e687f92d7fe346337a491010001	\\xd6f67978de412ea9060b2fb15956b6029206dcef102f61762b1b3a23afc782ddfaa502a10b6339a922967371350521210ae17d8f1fecfb748ba329a15a1e5908	1650587107000000	1651191907000000	1714263907000000	1808871907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
262	\\x697ed8e58a6fbb7ad5f82e568046938c13184d3cc7a086a95cba62a9035c0da65b3836583acf2c44fa1f0a7dfcbfe375188cdfc23b8d48b026fcb23ded53fc2e	1	0	\\x000000010000000000800003d4e584839f3db18cc431993a71169bad9fd49e4a3b1d00adf4e71521c1557680092de27d9d61f709f546ac3d0af9635d29cd705021457743d6fcad13a7a123e969fa634c0e81553d022ec70706ddaa77bf82a4000260f35f2d5e23a29f265d4c89cc33b1d6b0bd57b412be8dea6d38273276969aca6cd298e8fc0b840e50cb91010001	\\x1c669f6583728621f30f2930c82fd32a70c9c912131b430bcbc8196b7f01f043ad6c242b60e265770d55c6896de8573d49cc36c016472d281df081c7dea05c08	1648773607000000	1649378407000000	1712450407000000	1807058407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x693e4ee4fb1826b4315e0ed796b7bb5f6d78119e95e9eac8219241833b67cb4503abac75d9cef3cda11fcc3dbbe0850677f97d04768dab2a00fbbffae06d30d6	1	0	\\x000000010000000000800003d1997154f22e869ee7ea1adf2d70cdb096807287530e7442ca4c6eb27cd8e2f6c9ca75beb2f6826758da2a0edc5b60d593e85c720bfd937ec22adff8f9f2b43f8fafaea0d683d1654137691c45a6efa5b71e8ae745fb9ba9d5916d56ad3685978868c77a9dc398df31295e34e443f87e43d437697cf9d23cb98a2fe0252b9e45010001	\\xdf15223404bd85267bf2f6ba8b79402a7ffa86206ac689dce1d012cfa54458f7958b865ba78e5536effc2916db780cc18836ed35012c359ad6130097a58fd403	1657841107000000	1658445907000000	1721517907000000	1816125907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x6abe56d4e94b8cfb18d18698466a9124128c7fedd4e2b58220baa9cda9004b4c3dd7e1456893f98fa930a9a2737442be4065293de282dd2c075ad14d33163a91	1	0	\\x000000010000000000800003b074cf432626cec8d403f9e0327bf81cf985a00d84efa3c7ba54bc7b7a03e6653a889b90ec3fa99b4dfc3f670d8b745d90b7ff57066c807eb7e642bdac933fd4cf3bf20b8b2db607862a14b0c157232d3c0f5aa0fb7cef844ab802df32eb8f11b257008ac1c52177af2bbf7919b19e980050cbb33be841ad29fddd10a2c2b5c9010001	\\xdb902fa677daa084f6ce8ab8dca51e14084e475db75112eac42dc13a7ce0e1b5703ff56ff4b0553d2ad9caff2f20d81411fc0dc3ef3c7a324da984c505ac3d06	1659050107000000	1659654907000000	1722726907000000	1817334907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x6fa60104121fa510cbca24e5378251ee0f9276878a25c1391b10ceb35d1ec440da78e0e319d6180c997ebfccff85156c27ee27fdc005393b4d85dca25cad7198	1	0	\\x000000010000000000800003cbf0634f0eb85d17f8e0343c3ed18b521568230ba5ad5c2bc8bd8678a3960a80cbb4146416d8c3880db6e370acc20a04616d2d862d3502102157d18c8a9d49d030d09cd02f2317e51b209745919b7f2ae122ccd32932bfd63ef4f5ab11a36fd80d94876cb4e06d36df36516603f929bd6caf267f9d12162c4e28efc23a9f9457010001	\\xdec8e5d0dc4b0d7a7f1448d63de30a95e477caab49a18ea301cbc5c8028595e0156fc042a0bf478295bd2136f97509f629425f3329fbd1bc3b3cfb17f9b3ca05	1674767107000000	1675371907000000	1738443907000000	1833051907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
266	\\x72c69ca3b60c9a239141346c65ec5fcea043342b63d650474718c43a33943bb96c21a573561d7ac04a232d662022da6755fb9a2c1191bdd6a81ed84a83586578	1	0	\\x000000010000000000800003bde5581da692ac1ff657832df265a39d69afea01ee8ee16873ff707e5b7b2c425f5cdbcef2a678aee135e7d2d5620559d3cac41796ed04cb6408ee14dbef3d40b7cd55c474fae5e33cd5344cdc1b9580baedb39fec332d7f6cc9a0f56f91d9818adbb500fad40e62205e46839d0ea4eb9c87a0b81ed1e8314bfd340ffd6102c3010001	\\x72d096cbf881d18fd1de8bc1be5985d4490f2d6c293ace97623862792a636290ca4f6bd03a0287629c0feb21de1843010c863efd0526c8a339fda6118928790f	1659050107000000	1659654907000000	1722726907000000	1817334907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
267	\\x768ea025ba38f5161627e2a01522bda909130caf32e50f18ba6ec93989fbe049db478ec1a75ce58a54bd4c7d1ac01b24a2152d40fd4a6f7018dd17a63c6cdca7	1	0	\\x000000010000000000800003f65af5b9bd25aa19948cb835385c5a24dc1315197b6845cd82e980aabb680cdf1c5c64588721c4dc80ef864d5fef5de616ab7392e1ed971a8d0c024a086972d68f7049b0286458f3cc518c931d2b78996805713b4740c1be6db4683f17b2348b41e2b749cd91b6ce885bad6be29ca25fb50b1c4a53d6caaba83c47b4289ec6b5010001	\\x3c4b7ecae55e77ebd14c3df6e4908535b51a6ac59fe2f84d5514bc75997dbc7c861d1a51a306896436467e258f841bbe3937d90d3d68b417a8aa01753b6b350b	1672349107000000	1672953907000000	1736025907000000	1830633907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x7d2213095cdee15e62d2e82a83b722696ff94edb21f00ac5c6ebb1070a9c5a4a6dbf4f8fa4760067eaa29b43e717873055f01f6e55613158efd201d8d8be2149	1	0	\\x000000010000000000800003cc1b1d0ddc3e338198ee7ab2ba5e5530d732255e202e8ca67823910d80f405b0397df188ac1ed65ba52d233a79182a61d779505b446580111c0444ad5edfa4f51f8ee5073608c3b69aa03897344627daed752584d92d84d6faefa4f0a435d79ae72f62a3d5aa807677cddcf8ce7d6f864a6e50396035be192173dae0e1d13579010001	\\x2c18701180453c806c0182933e0b690db372dc2fb3f43614bdb8773374c74c49bc48cc6447b745b6a5591ea354d7ee4b2f51b72e31d1b9ffa1142e1ee298ec0c	1661468107000000	1662072907000000	1725144907000000	1819752907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
269	\\x80b62b8e57c8ad49e81a39a525470bf69fd0fdc5016fd19ca58fd4663f2048cf3c38a4dba070ba9c4c897da76c4d2d46cff709d1dd62cf59ef28ecf3be0f1783	1	0	\\x000000010000000000800003d85f861a844490784bfdd3c9c4816fd656c83e1a481b82b1e4e352136ab8e133796cd50ee6d5fe19f314574fbfa8412f2d219a11a87c3f022352a0e9e599f21fca7cf5a4d948aea11f6b3d3a0bcb111b25d2476e74b0fe7e1158523d56cd44ba4eca7dcca12567ba33bfd384aaca29a24268e8460f6455d105e4c7f2339b9f41010001	\\x3a662a95e9193806de7fd72357ae638713e69ab50e7757bdd20b4b0a7e8f871eaefcd3054109ee94754ef147c0463b0292cc34223d5cd5a66855227a37175c08	1651191607000000	1651796407000000	1714868407000000	1809476407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
270	\\x8176161e235615605d0fb9cb13c7860803e671b50301a9c0a1fd8e27606e03a27ae6a10c626156dfe211a72d63f12ce1ae60ae57cbad4619cf0030319d05eca8	1	0	\\x000000010000000000800003c59f1cef6ea29e69fb3a5d8942217d8490d2c18eca6a787a8de1c8b5a674c5dc11ff4deca61c1de0e3057f38a415d76bb1992da82e4a491f8b3b78f2db745333b22fdd991000ea9b17eb5c1ed065937cce1412f8538d29c8f361cb4af47c0fb0888d24b8bcc8a2b52278d8844d343360efe3ef2c67ad423a7cdfcf98f0b8ca4d010001	\\x687c849e0ff9a450ed6db85365db330b954950f56999ca098f1bdb3f73242e21630441c577db3f3c216af492499174da6f767b44457ef533e6aead890c1e1a08	1660863607000000	1661468407000000	1724540407000000	1819148407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
271	\\x84ce7c164ec193db80ae67ad3ecda8df00cbff5449c2a602b0425efc04a77439b8a6ca3b1291d3397c04b75e7e843db4c4f8b0f132eec43f93fcc14613376f9e	1	0	\\x000000010000000000800003b941b2ccdaa6575d056b0fb33da7b09af476c1b59d51b430de36a919dc277aecd3ccb4407b61a4f8c68aeb1378a91175886342dc251c7cf824dff619567af3828ddac9b0cb8a80c92ce2aff2c14647504755f4c7c7c9dbf2f801acad629a16f73070ec3a0b78779e948d40d6ce2b88338d6200caf1fe0106480643737cb6c7d9010001	\\xe48fd48cf15127910d44ee01fc961081e0ffe5f213dc51518b5cc971aafe13c63653845b2d9c7b8541fdad2a8c26e6447bf1605ab93e4d4823c4d6bdc7ae6509	1675976107000000	1676580907000000	1739652907000000	1834260907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x867ef9cbfe6f7a3fbeb2d968d0b1cea1f860b26289a98cba2e1327dceb3a0a7ae4e55263cd6efd48ca2556aa21883fb6b42bc7c5ab71e660217ef3ba793d69d6	1	0	\\x000000010000000000800003d7acf1f2e4444c35155c46b9c97cd0475f567ead7a484b43f6330601207efeca4993e8478b1e42de42505e2983aa470dcb28f37596dcfed64551955148defd74e761617e9d15140527825999b6f38f869fd37ea4af6af8caf5a190b3fcb5bd2d08ff5e3719d1a77aa448a4dd75e606e57228fa9d44abaab3e957f7712d46f2cb010001	\\x8466f9573986ea9eba608d7ff1a8754bf9754c9ad2ad31acdd099883f78cb7248c1c2eee16d38ed9f73861829754debb5dac8477a956a087dc467064fbaa6702	1657236607000000	1657841407000000	1720913407000000	1815521407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x86e68942258f160b8c7885e18ce28ece4d2142a3eae9d221ac9be61431b0e3c13d869ccc52086f5797f89e9f2ae238a11ea9c660517ddb02c470f335ae396e2e	1	0	\\x000000010000000000800003da0b8b843d26154322378fa4bdbaf607c896f7bd7a304b4a651d0a0cee9bcb24ee70b02aef2802a6b042d99bef40b83336a4c376c170419be6184c317f1b6bb2a4de6055635ad32441d50db083111ffdc6d584eabb454adee6fd6e42eda574bcd1a5a640e7f83052ccb57f5f3dcd308585c14f3d3de50e341cdeecbe16d34557010001	\\x7157ee856d3caf5b82661db5f73f0cd78326e1b9a65845ed433f8288822d23dad1452cebb089385ef04a151eecef965a531967eff8946bf8d4dbd0dbcac59b02	1651191607000000	1651796407000000	1714868407000000	1809476407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x88be6a2b6a5f917fb4bc23e06a43ded22bea0cfd35f4f58e6ab220079cd82f54616ec78d2137509b7916a7bbb811b80bd6766ee74f557df4ad9203fd1c8a758f	1	0	\\x000000010000000000800003a6a4dbc8d5468d38da35380b10bb78e11cc72204b57cb84d876ba9330851449555cfbfe0f2d7feb73c8172fd94da0014ba5a52d647d8e7351dacb74055f350fabb1d45a20de013bd3b77726c93141b51af65fba0ef6b3b5bf54305c97f601534a9503d5a448506893639a4c3e4ca8124b80b71b3c962a4844c7ef514eabc7a5b010001	\\x161598adb08becc1a5f0e7af6d9b5c0522a98262c52f6def7209719f67d78478c28d72f981c6889eadadab94f34ce53d92ffadebc96e6a7e653a785a7181860c	1656027607000000	1656632407000000	1719704407000000	1814312407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\x8a3e185415f4857309d27f4f5e0c4dc3172f2454c59c5013b56eb2cea0542db685578571dd61da010842a52c2b12662c7015ffbbe3eb1aa369283cd1c7c6cff7	1	0	\\x000000010000000000800003c85f0be1684197e9c95af8ebfe58224e626a6292096a02ef0eb19c8655701bd7aa5e80c1cbe14a093d0209d64ed6f56b1de6ad2cc3bcd40f049cdbd8663d4be233173b89845f7ca3ade9d44673051088872cf80e25085b698841ec6b5038c360e5bcfb46b2ad1f5e9c0c3592be040111ae6259a5ebf7ff6428b4f256014b6349010001	\\xf11fef66b7e9a72b075af3b00584e398dcbba57566e78ecb190216de8a8a0957e6578b07efc80ebaf50d23ef1ded0411a4e4ef1af81910232abc64c74171c00a	1660259107000000	1660863907000000	1723935907000000	1818543907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
276	\\x8b0e0753ec3728106e06c30773a05d97d1f49a541ab7688bfff6dc1a36cb2f061b25dd1786c15d4de2abac7830ad297e2f59b5cb57a929f4fe4bdeec7184bbf4	1	0	\\x000000010000000000800003c390465d825d9bceaec9bbce17b4ad0e6b6d97f6b52cce9050c9ccd36d0e620759e973fcd491f21206454d98804acd43da2e676fce27597d469b4747759023357403fc51bd73af9bc41713b084c8081e8b5a6264bf4b8400ccda38999420129d7dec7df3844a94ae166bef78a295496f9ac365beb9ef7a5c52da1a7b77d1dc23010001	\\xd4b73c08f2ed81770de51e16af1a6eec8526f29d5c033e218847037631e8fbfe20e0e9b769a34067a3681ac88adc702e26a882bc31d777369fc366381bc47e0e	1671744607000000	1672349407000000	1735421407000000	1830029407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
277	\\x8b1e1f08a2473d2b31fbb42595759489147dd811dd98a33773da0b69a1ff676b621d98ae036045027ff8f987b53039933b7d3d6364bbdff90c273476f71726db	1	0	\\x000000010000000000800003ed5fe7d46763f5de2107fe958239c8007daa22fff52edf153f7dd329f42156985fee6b8ab020ea54ffd2a0d676ec958ca9633ec51de11a08accbecaa9d14da755771a50897aa0833738adc95852b437ad022fe6918fd423e54aa415cc9596b7f7d795857b49e7ce8499d9995639587715e63aac4d942621dc05927aa9c77aa8b010001	\\x3a6f0677c57139b590ee7d07c649100e1457ba4cd96cdb32826e6b240e68daed1959d1849a977478ee356c3d8d7082b2563bc21c55a0965dab1b22e0fbea4e0f	1666908607000000	1667513407000000	1730585407000000	1825193407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
278	\\x96c2370aeefdb7a5deb233aa849eedf6d9cfbaff197c452407bd273aaa4620ffa178060e6dd640e623eb8b82628b77c731a2b20881243f67b4418df9b0e6c03f	1	0	\\x000000010000000000800003b2d1ef99f350eb638eb98cc40536fad85f24ab46ab12c7ae28316d811d7cbcd60d7d5568e68b33fe4dcf5a348036e82f243663256fe9f77d9ccad5ab2d700bc933f158ac959fe7f11b5d051ed2ba531f5ba6a1b35b93588f398c69149dbb3d45e8643c9739c2cc81d3966ffe4fff5f1ca06a481bcac1bca2292bfc4d716fd833010001	\\xf4e4a4be3bfeeb424f32f60e6ec50c9dd9029fe701d78c16635f1f456adbe8516e6b1483d58423ee2d95e3eab563eaaa0f1e8ef6cce9db65fea503817fa1ae0b	1648169107000000	1648773907000000	1711845907000000	1806453907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
279	\\x976a44040dc62e5e5ddc543e76d46e01d7246494b6720cc86550bda7e968698ba013369058d0dd1da23b53954eb900f54da16efd322e8dcf50dc170afbe6675e	1	0	\\x000000010000000000800003c9d3a9c9d800dd8d6aa6089edbd05a967a4acdfaa9b3e4d5d438b32dc2fb87b9bfbabfbad7037a1c121853f92978cc7fac0c2eca7036b3378d3db3bcdb189f6190944a801ebd760e6d990443cd33409c5ac0f72ed86ed551cd12cc517231f5aa2135fc44e14d15e8b177ed8d576706fd5849e1bc98683402f0493040454178c5010001	\\xfdbf2beb16eefaeb12e061c7d4cb5459811bd9ab0d0ac49333a75b4a755f12fdcfe8282fce538ad37d5db288edaaf615f5da4385d8c82861af11757cf97a7b07	1651191607000000	1651796407000000	1714868407000000	1809476407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x9feedaea223c6478fe36f7ecc074cc934d574467e05c5fcfe9abef36366e949dd1f0a9f7ba47586f9b1362bce5fc89826842d72d3dbc6d0705b03ffb574a4698	1	0	\\x000000010000000000800003d0544fe9ec89914121c0851811f019715ee75950b53bd6d036f52f9d73fa84ccd47c4495a358bf199f4ced737e4d9002891d3950488c2d53282a4d193154b2254ebf3c2848cc6ac3398fc25e27b9a3aab93f5e426e2fc846ed1c97b5fab60ad651cc0502c3da5e5f46f7dcba2cad2a8133cec44bbcbfcba54fd83297b02eee95010001	\\xc9a868a42b9300fb8da2cecabca01622870f770265724a55938fd5aa008315e80f903da876193381dae4cdb192832154bbf722e26c8ea7203a43845610311e09	1651796107000000	1652400907000000	1715472907000000	1810080907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\xa186d64b560879d60bb0804e376ae47cb7f76a79f69f71a07eaad26216b689cb61da6aaa7f4547fdd4a02b553c80ba9d1e32a709826b0429b98229919a2243d8	1	0	\\x000000010000000000800003d7e36c696ce585cf55d7cecfc3cf8f89d2a8c61a01e14a4ff2ab88c8eee2c6f22391e297c34ac50def5c37af442b48d5c74afc3bee5325e1b56d426c5f81f6c3a2e7842f1cccc8f77f6213d556381adf82095beca4c4814c8e2799e598281ee4ea9257b1f92c97a473a51c6e060877195d712c88aa25a383ef9a6607b47c51d5010001	\\x30de4ba2fcf5da30d3e214a790f426c664b2aed518d9136daf864ea561d9575da5393077142fb3da54b864e31ce572221936507e816660ffe82ccec748fdca03	1676580607000000	1677185407000000	1740257407000000	1834865407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xa5de7837a8eb4a5374351ebd016fd7f3864bf70490fea47c28ded07e0cdbaf239fb2449d32a0e419551dccea79c14ea92555d1502d1163eb7d190fa09fddf463	1	0	\\x000000010000000000800003bbff2f086369b163d913b0548af89803bfadac6950ae736929c34579919a71ebb24f9155e65533193980339302ed1a04414cef7defeb93210c10d2462e5a2efb35b84a36838242ef634f58fb287a5fbbd3fb3dab8ac996756f738365abb7995b243b77c7043e1c6f4786ca140a5f0807752c5eb3fe84d6c237ccce7a597a921b010001	\\xeda2e6ea9a2d68ff97013b3fed92a1957dcd16301fd6e477b5248c89647cedd87ce5ba35e264c6a5d9328db4162958acb7df2161f0c3cf1419b9b0e0cace7903	1657236607000000	1657841407000000	1720913407000000	1815521407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
283	\\xa68ae55e4f1c9eefeaf2f5f9c2012d797d2c4839411ed07dbc2efafb467bbf2bcdf813a95b6c85758c193758a9c477e5e5e78e8225cfcfdb0ba0d57d08fcd799	1	0	\\x000000010000000000800003a9cc1f2dcb88d7b1a959509b1c40547efb4e1d33e143c9d668e44c3bba752fad5e2a564150d10f42bc16334ce55447b32a567e896a739e27664b379bc32781b61ce9c9ee5805bc5c275083416db875411a03e21b507896eb33ec5aa75524e1c0b9226dee7bd31b4f96dbdcc4be83c71071de50b609dbe00d78c97855b0638089010001	\\xede454803d3452b3d8048615258d3b2a4e727932647fe23d651d17c98eac995934e319c7aedcf52dce3ece9e1d222eb2cc441b674d5b61b7e11bad6dbe652705	1657236607000000	1657841407000000	1720913407000000	1815521407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
284	\\xa88e24b9a3d6ad2b2a19217fcda08f403f15cb1a170870b7a03f367c9e11adbe4488459f8577218861c3bc69dc696b6816c30fde1aed1efa51e191efbca98593	1	0	\\x000000010000000000800003d2659e091d4bf53ae5e0a02fceddcce813b39c695e878d5ad32f5ce73951c35a4e2ca357d377c3daf658931876c249ebf2de915d6dd985c9765c2293864fe1a772c92c40139651e286825b522229b1897eb8a9a986c9a26bad05fdbf2418ba2a389c5a635642dae34001b4995cf434b4bedeb62d2cf414669b1268d4b95229fd010001	\\xdae91f967a2336f4eb492dd18d2ed88adb2ebedbe761083dc0d1b587cf271a421c5419e74b23253be42da0805822c8378030b71689b9c7ef238f1f5d88183507	1647564607000000	1648169407000000	1711241407000000	1805849407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
285	\\xb042f38e16b7ff35fbb2514c8eb515769faeb2476a99360501cd8cf07ca3c3acedc86210f1494aefbd025397aebd207d3b5fac5841280e3a7b422e526910864f	1	0	\\x000000010000000000800003ccd78461456bd6c1f960d943751f9a9caeba0bed031c1f69f577c8f200d5c9a1b9fd3253e6dd284f5e1f5187ae26a1b4cc059f51a33693ae65060326f9470664864ac29530070034fc1df032c530201046aee795137b73d980bd9a48ba3f5d80e4f570a4c349033589f4e8450b7cb4f05fe7a4e98fa820864226768ef42992dd010001	\\x72b7d8bc14a66d78822a3ac6e24ab1903e392b4121c7c14022f1def1fb9a542a9631e4d3611585b5b174f0c9883c77e28034868f57ea32d8f9a68d653fface0f	1667513107000000	1668117907000000	1731189907000000	1825797907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\xb48e80fbaeb006f08b439de6547f0ec84c15127f25169d819c8db0f74db64015ec126c3aedeeebe54faeeca772e6a7b67c1291215dc6c0aac652d2d0672b1066	1	0	\\x000000010000000000800003c17d2df44677f07ff9a32d67ff4c3a950bafa172450dd80fc202a01de80ac052cb15c64c9606b611a478f50fdeb941dc3e57cd3643b2a145a7951ae3c90ed520349c551591fd78a9bf01fef4db4b879b07b97ecca57df8af85315321415ff3bf951faad00eead691faba7f3a4934ef032a00d7b35312a17f5d917b8650876735010001	\\xc050d46af67039cade4162ac0fa46d196e4512598e8f17a1bfc5934018f851b6d30204b404013b241fc8ca9891362af658ad95c97c1a915a93ba3b2ad1b58409	1671744607000000	1672349407000000	1735421407000000	1830029407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\xb436cf2290f59143716f53b998851baa9076501c5dd95a3ac0d66af661c0c2e0001ea44fc252a9929a7ab4249f693089617f4f47d85577948d1f0a266ea6487c	1	0	\\x000000010000000000800003c356044414d801a84e5d0d79c0ca563d3be3212b4d586032fd7a12f5383d4224b5e4bbfe52b61996623a54509b73f75323c4e9fe538e57de7042c8d8ce0c5e54744da55266c0030cd23ba029f9adbe60f550597f683ec60d9b6e18ceaea74ea5bf8fd7c63b0a6e3fd9291577bd1d88dfc81e65baa50c45ae4419e29d56a1d237010001	\\x8e5c1e755c58713461fd2a9b0d82b09b2eaca5e3410579fd500228ca0329641ebdb8e5d2ce6590941f268dfeca7202ee8f0a5ce96d13a10561c036eaef724d0d	1665699607000000	1666304407000000	1729376407000000	1823984407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\xb5eea890801d73bd337e85e0d65b0355a8d8069c5db6c7b230ab104542c4ef4bfc87ab996ceb98e25947ce9ce44545166a697680c28016dac49bb2014be04191	1	0	\\x000000010000000000800003c0348f4844a6024f1b05aaca6d535123318e15d64f135873e61bec775d72b4c816859af63bd005cda36a3fbd16f0f0b34ea4cd65070e723d0024964c18761d75c5dbaa8bf6d7d4379dd2b84d360e886cd71e076d5ac0e4a4e74998cb95d8ed35072fdf8b52a759ecf7d0a66ed3b1a987fc4d14bba57102e3b1332ef619f0e207010001	\\x79c87c3d1d5f14bced0d5b2018c9a96291e631f5dff973c10f22623499e12d128881bf1d57b74e99717d4e81794fb6d02e887ef9e27224d6c685901c7eb28209	1656632107000000	1657236907000000	1720308907000000	1814916907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
289	\\xb56e8b1e56bda96b5f891fece3310f413777b306f8b30d5274c61caa235791a268ab0394a463609fd98deef9c61e090d356bbcdee0eb53b4977979e7aa225a38	1	0	\\x000000010000000000800003b94e4e8559fc1e37fa7131f11b940bba801b07384a81c73494abd1b41c07487a90d7ceff9bb8a8503f33f39446191ab1dfe44952f15ddac87af2e3563504ba6035689bdbf779f093503e9768e7f354d2e924700613ee3164bdf5850f6b2619e5608fb88e98cf00add51c22929aeb84ea59e5a964c22407b028c5dc24f95450af010001	\\xbad1becdd8270ecbbcf0d3e5265cae51f3385cc0186f24f674f4144f9af7232103d486738d918d08fad2390be6968666ae9a1a5feae59a8114eec47510600506	1666908607000000	1667513407000000	1730585407000000	1825193407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
290	\\xb6ae8f98436e89702bba4677d6aa66fc9e64e14a352e60fb6f3356c213faac1cb8937dab23b3074cc487220eb0532fcfb7ec584f382ca8bf02d1a8dceac1632e	1	0	\\x000000010000000000800003c76163ffa2188ce2af8e84027c06494d5393d18d902a48f2f225eba354f34be83cf25725eabb9ba6bff713cdd78b2dcdfa2f6161eb93c6ae7ff18eef1f321a7b4db3dc27d1f33e73d36e8806cabd8f7844f13fd79d4ea89daf89baaa083adea3b473f29fe3a419fe10c9c95344f6fe941442d6eaa63f9bb14fca09958514aff9010001	\\xa504cf60d30232b96d77ee883af2dd092b805bf031556162e33138c35f716a62b6ba71a5cf458c69ccf8b75f77639d184a768c99e813ef3abe56ca5bf9112c03	1677185107000000	1677789907000000	1740861907000000	1835469907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xbaf28fe555dc21281b1c49df6a6774769f949fe9c6bafc39ede3eee8981a184a81f0bf7f441c91df867aa9379105bf779bcdb6355dd1e76d893ece38cf6fdf78	1	0	\\x000000010000000000800003ad4ec8c5f2be28fceb60e6122326591ecbaa411a5192950647aba41e083145e9a8243cdb2530d42f0c3349bd687f838de04f9d31f9d3811ec1751e33d44751697fe73bf305752dc718fca5e3b3ab96530162e42378e18b1a8e1dfc901a742b05729ed5fcb04f28fe757d18e934f0d346eab7f5b9f078b74f58599bae2fd62315010001	\\x476a834155173c1c2d78dfa1ef9999d421c6b721879d092728d8816b679bce7a2888432a65f438a07d1efb107b4ca62e0cd9c3701f5640b7c3ca518d53fa0d08	1675976107000000	1676580907000000	1739652907000000	1834260907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xbcd2c0311be06d0ed8aaff162f0b94ea996e6ac33d411e02d933be0d36f149daf89ac32005774a2469a2d53faa864060f4824603944ee3df42ded77266831ec4	1	0	\\x000000010000000000800003f19ae727362d5fc57e457c5dd7d8f1159bd49112804a4e07e12834987599599c9bae1ee9c70f8022537309d99a00643ce5480ace9e2e4a27309bf486613ba6f97181ce558e21b945fe42fef875d048a5d9a3b1f3d4f6a64f4dd1c5cbadd121723196cf6651dc47eeea5eca5fb2d419d4fb7a503038674dd7dffb6921ecf00bb3010001	\\x9d4f8d6ec51048ff34d2dac12b4385b171dbe0d4cd6f0cef464c277906196ab59c072dc4bb961c128eefea56be0cb1d6fb5124cc87973c171f6738d8d9dd340b	1662677107000000	1663281907000000	1726353907000000	1820961907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xc15282c290af7ad49947fb5607cb58aa3e1f0bfab148e566fbc54c43fc3658ea6eac4a7c29607952ad069510f9365b80ee42f83f29b3809a85fe887f5e395188	1	0	\\x000000010000000000800003c145b5984dcaa7045411432b3ab65f458b2e015035247bcd2268c5d7ab26edb51c31e3dc95d5573621ea97685487dbbb3e53b79daa2bb3c33f8da4280c569dfa9560727487f820b14db549baead3b90edc41659c7b32feb578c7e8d821bfd22bee30af1f23292823ada8bddebdceea39404807974fad3dbd29562a96421bf83d010001	\\x8aec4a69251b503bdb8803c863fd94853d2ee3c80fa39a3ddd89d360c6219192f0ae61e82f48b89861b076c13063d43e0f8707c010188fdc2eebaf221c0f620a	1651796107000000	1652400907000000	1715472907000000	1810080907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
294	\\xc2aa31322aa96029bdbf01ee09fbec66a14b13a770a84124ae7427676a25fd74d2c1dca36315deb39047fa050488bd913090fe0452fc42afdefd2f914db2e6d9	1	0	\\x000000010000000000800003cde1716f3f9672f493d7127f74e5b0f3a5baae763ae822bc79684b0a18954c3433adc7b19c9ce3975680e3447629095102e0bcc46c3c31c3b0f5349f181a6d91a1c732801b589b3e367e25593910566139c8da4257e7f504623ecbe729e6c15475c108ebf5068f60731d0e6209b065f8e5db2c4ff083bc6c57599d043ce8dff1010001	\\xc31f9af871d3c3fae5ae90fda9e33a7a09e7ec3920cc0debd5c9e5e1bf7a7c6f432069e02fd19ffc1ee3c7c08819ef45991536ec69ebe1a5fbf8657a2c415502	1663281607000000	1663886407000000	1726958407000000	1821566407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
295	\\xc58685b0218a39cb6c4a349792c64cf664a968b2eab82fd59ef526682341b187c72f0d8e02903b6213b8193a61c9a72dd3807a0fce5aaa46f16c9b65aa18fbf3	1	0	\\x000000010000000000800003cc37db270323c5c54a4ea5ca8af14792fe23bc3af5a380afbf880562ad263668bb77fa7f8f280c8566d49816bbeb0b0ea37e0e5155d935d30b11bc179d897a9427c1936ded6057f18c454242d149626c34ebb14aa9663e742f04a73cf3408be9407d0d2df92836c7fd3af1b93517120fa9d13e2f5fba384fc06f7c053801e20f010001	\\x2b85eb39df99b0e4ab4e2472d67752b7626204c2793aa83ae472058679b73e305dc9a4f9dceeeb612321aa5d2393518592bd3e47333c634a8fe38008742e7308	1657841107000000	1658445907000000	1721517907000000	1816125907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xc566511a378a6a114c5521b67b47da5fff9bca720dff617a0004620dba16c05b3484b1f9d68a48f09da0622b40c9d25ef9c6b65bd532d595cf689cf74b5b72ad	1	0	\\x000000010000000000800003a6e6712ce11b56f6a8fb0ec1451abec4fb979c67d18b8c86dcfd3572d5e1ca780455bc0e3e88bfbb11ba506906da2f422a5c6cca7ec21c4ff72f7159e4c2731382138ea068ae497bfc2c395719f99acfadc8ea1313cd5e0da87f12506ec5d9c581bbbdb7c50bf8e9cfba8b0ccc800b453aad991a5caef334947d4bbfa0fb6883010001	\\x0dc4dd04b854a8a1854f3cc6dc0f085753e29c69f234147bb6464c9e6a3550d79fae2c584a24120c18a1536de018df67cac3c75413a75a79f11fe5634c6a240a	1675976107000000	1676580907000000	1739652907000000	1834260907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xc73e288fb6d483655dc7cedbae416f2bba72a9472c86255cb0c3c074c5c337e8b8f7e96ef19798f6e96dce23474f4a028925e6625c7e66496dcb83a826ba384b	1	0	\\x000000010000000000800003cf6d5b8dee0f6c92c68148331d1d1959468fcd5bb5463e1a231039d666bdc9a144f427ce9559af8eb7cd819a82387c9b952142eeb55a8572fb96d44731f9beef634f27b4b916c38cae12aedd8aea39c90cdec93aea2a33e6ba839ca860484d64dde48ff0fd9b580766e8f8dce7aeb1ff40c1b4b342353611c7e8f23788637083010001	\\xd4023191f02de0579609b87503a2dfac720baf6286e937211f53e49ed6f6f38ce289a6df7d59879e346196517c4ffdeb3d3758d5022a2e189f6ba863ddfcf005	1669931107000000	1670535907000000	1733607907000000	1828215907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\xcbea6955e0725b8b61685a087f107e27c7a3b4bdc58319da71b03d01d4e8537a9e237bf78e2417bb9ed730b08cb543fee3621d8f8299ed4590a833852d8a2110	1	0	\\x000000010000000000800003b7750e89769ca9d3d96a2e225f9a6a8a31cb1989c3f9785202d71fd7a66a76ca426e675fa6b087b82d2b3d0c14c8fe6b575ffa706e5c7c17def5f1b30476f63f56cbca15bc1d0a9322913f9d0e08c499220f2fbc5249270af0b26a152b29833d0b67a25c5a3149fb51f0d21d2bed30b2dd341171a085d09ee4098661431cd431010001	\\xb63dc792a7b16230f5ff35484ee536bad569baa36e1f331fae760cf364c469c51ed23ddaa8b53a392ecd9d6300c38e829f46a7f4a113f5b1897dc31742636c09	1656027607000000	1656632407000000	1719704407000000	1814312407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
299	\\xd1cae0b1e39810cad2cecedf65b740cda909539c90fe3dd0860ed6dfce42b2edae59939ae3a48665f0c0d299ca24df59303d211121e8b893d4b1debfa62d3b18	1	0	\\x000000010000000000800003e0aa3206a3e73a08ef686718e61207eebbd6cb4e9d93be3342f1ced2874b4b68470033e9de97065fc1780ded02cbabfa6d8b46fdb1cc78a76d489993017fc847545bf66dbc7f93070f24512c601a2d9372fed37ac6ac32f4dce90c9b6b14ba2b45e223b6da2943f5cc1501ff2d6d0916d5aed1924ccc51206ea16f66bc21824b010001	\\x2406a6ceaa4d3e440a5b9e71467b72d23abd21334100526e67f5a9fce1dc3ec9ad211128a65b4acaaa0947b7ce4ee9ccf600c213522b07a2fde3661899dbd40a	1659050107000000	1659654907000000	1722726907000000	1817334907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xd352148cce3dcb88038e3d27bb0b5151a69675bfc1d1db6f26abdd604c36f3e5d64fd90b7a34a616349aab84e2f1c1b290269a55ce046b51919cebc90212b46e	1	0	\\x000000010000000000800003be4854dc1fac2cf28c3418fc0722b7b44f2a0c452ebfeeb25aaeb190b87b25218b0c447c122ce30cce301c4908c62c68633452fb55931a830533fbde9ebcba525e82ea75e34957d5f6e79b9763339871a2514dd4a6120636a0eb53ef9da8cacc9c3442782148bcf82763a3749a63e40b9e7baa93c033f4edeec8f654988694f9010001	\\xbcb39f20c33743618b1a92129730d1c31c36e92aa2f24edea88e22eb0cfec76584fd3e879e944fb6ea9bd9b6ddf7b10c64b9f2a1e966b3c8c3e39c0f5a8f9c0b	1648169107000000	1648773907000000	1711845907000000	1806453907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
301	\\xd492151426bb63940d48ecdd7b7bb0641d354749bd733414e768dab336dd091b7c748829c8a57578945f4ad459c01cf442e60cf281f1c439afa5c6c50a173809	1	0	\\x000000010000000000800003b159aee4c39e5835024c16000adbd7965f4d2d97affd60741896da544860a56ba4964d04c640badbb15c1825fd00373e7ea7267a3ed616b66b90ef4258cf65f07d677623226be72626cad38bee2f5787661ee5d246683d4abaa89e81e5b167fdc4ef36076fe85fc253cdb61e0fde2dc428d8ab75bd71b1f0251e1fb13f315b1f010001	\\x94fe2c0a9fb62d7a95ec1cb8bb5eeddaa5d00ff15975825a1654d46aada2da9cafe2f57a591ef6ff234c32aff9b3a9c622e308174f1b86ee9eea83b42224ad08	1669931107000000	1670535907000000	1733607907000000	1828215907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
302	\\xd9e2cc06b07031cf5769e8980458e7c07b86194410eb414c63bf7e129a9fb36509b8b7c6327a3acbf974125f8b1a909e4ffaebd9fa65281d5c89fde9f6b9c624	1	0	\\x000000010000000000800003db358c5f41bf7d55f234ab69a416df0c69ba4486733ec70b732bcd3527569c9d29494f3b93081f09aaed4eced527e11f12ed8c42ae9387710c74438ed675a4b88923d01f89c223b828edb8da8821d8c5b94768baddcb9057efa28db9498b909b2864c297b6a913a686011454a8745d8916018933c3bd9ddb4525c4be3d8059ff010001	\\xe4ffabf4ff013dee0763edf0133729d6dd6588ebafb5860bfd483129830701f6748ecc742a019f088cdd8bc460531da1f195872f2247bb5201dceb6313354106	1666908607000000	1667513407000000	1730585407000000	1825193407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xda1ab80a0b39fab941a182b96d64ad61bdef719d92d52bb613ab827c94f631a66b6c7cba610d5ea12ae265c56406b19e11a77bd02a3117fede5328fe4fb25d85	1	0	\\x000000010000000000800003e8dfd98af7496c6b3777090bd9e22ff9998b50bef1d9fd9d7c27e2822808778ebee7ca94a7a82480a1130ddc9668a100baec44e68b1af300322248c5a11474c1ad3ff57173223c72817ffbe39c09f595db7f6c13c89a7c5ceaa683fb50e9f8167479ac94d149236e6a85b67181b11b9e66b113fb9837e3499daa10cdbcbb6f95010001	\\x1c08dbd0c2a25e60fca9ce1dec2f44df2298032596c1f29626edddb30af37b5b498a12aac8db665da479f27f1e04d85143f9310d3ae8322398e9dfe4c58a2000	1677185107000000	1677789907000000	1740861907000000	1835469907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
304	\\xdc0eb6d8ae2f8ac2149c5f854fbd5b0ea7c041e7d27304571fb7b1cdc3c0244aa22f440b6f800d11dee3ebe7b2a76af3e84adb813ec3de7d55103e11e9c23fae	1	0	\\x000000010000000000800003a74a68963ee17253a4076d4567e106362bf279676546863fd992b3329252b629a7a27ad1ecfb522f7d8cc9484cd1a86ccd811503c6897294f91a779c9c93398827f50fb4737fd7e5b69d5eb83a279ef0a4e505390519aa64e9ecfc1ff1dd1eac455df69ed3ca2d01a7b1403390e270401231b1cd9cc2e024891f0cbeebe15b01010001	\\xb22751355d0827e30a9576f6d6fb77c6ae6197d7c857df8b0eb2c1658e198605db251ff7f2f7184f0892c080351c8cc9458996405a589ef138d8d229a615ff06	1668722107000000	1669326907000000	1732398907000000	1827006907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xdeb2bfa5b9c94e9531bf4f6068f4be3d2f8e000b97d0f27e3bb7bc21d30599db4f1673174c005c6f2d85c38fb82c6c0e325942ad012bf5352288bb50bf60ae6a	1	0	\\x000000010000000000800003b4eab5005b024cb2bce3849fedadbd023618a3f6104ca16ed876976adb689bbbd21a6a254f72c9c0689f8411fad58f2ac79a6978d51872dd375a0985960f23e78dc9647fb54a65d1ca28a888eae167d8de0cc821b2a9047d43b12b75a71c08128d667ff807182b7850536d0a8b882f748190e762c12b74fc67e7cfc1ac9e9fd1010001	\\x01b705904e227b24afda5a92449d1d27cd82dd70f83cf215c7b9e0b562a35e4b483bda24a054df70a9f29ae6fd4f0b9d67f6adb39285f0835ef94b2db71bbd02	1674767107000000	1675371907000000	1738443907000000	1833051907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xde5eb7a13202d38e1d6def8bd159619e503ad398b56c171a6ca770cf7ef0a63be5e09a5d88b848cadca0246f8521c36efc12fed1db12cf783837729b0bef8e88	1	0	\\x000000010000000000800003d9141f2fab97edcba48564bb70ae23db92aad177b8babe0821c8b1abe04b5949d67c29815aa2a53d9ec7e9a0404822e0646101e3684f79fe058b0868397e7dbd38183da14cc7fabc4bec0a6b5d8fe67121541ef6d2b4584cf6cd1557729d7f5f56d92b0dfce6b4c45014c9be52ff182ddea955dcb0046f7176fa245b7dedc385010001	\\xe7abd69220228680bf1af728594206aef8b9e813227dbe10fab9fd850bd11362f26399eeba682f5811d3eaa5601ea2ae3c7fdd99b2abcee3883f47dc5b6af606	1659050107000000	1659654907000000	1722726907000000	1817334907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
307	\\xe3a2a68bf94404cb37355b57cf06df81287bb8edc1fe5b5f67db68f66bbe564875e9d7c3ed5a3854956b9a065b96213968e14761eba0a1a1f8fe4b222a352a54	1	0	\\x000000010000000000800003ac2b9d866d70807c01e4d3f25d38774a8979ef6ad597c82399d7165960aacc997f750fc0aa00e310425189fe148538b83fee0de35a6427e56044d399eee17f5a19e24d96c1f9830232a1ba78b020c2c7636f1517092f08de188a27f2ec5c19a31d1be2c8edc7cd64f451637372ddb22577086898e10e5a5be2940ee0296a9baf010001	\\xb4496daacb24f04a7e886aead82cc9963826476155270a4ebf97b509fbb68d352b20ed1b8825cc7ef610fb9c24ed314bac0d7088b64aec4632398c5201c80801	1678998607000000	1679603407000000	1742675407000000	1837283407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xe7d6b12e906d324806779c98c2e9769a1aff6ea1f7614040baee6e8bd1a39d10fcaf50566ea1478142b67e6d1317b96841bc9eb02192872e1fe050cb2605447a	1	0	\\x000000010000000000800003d3f82319ea5b1ea94e5d7035dab0028607ccd7abdce84e8895b2de56f5fd97cc0f682eb9c2a65f31cd70483b5f94e6068544820f873d5029a527cffe5dce296b29ddc3109ac90e99b68e11837602d0ef1b8f49cdcfe744844f88789d4b103192a59a22c9a07a65fb41ab5626dee2b863e04117c6251b0c6cf2bc675d306a6bef010001	\\x071f23986b7e4bcd8bce7d3b60945c3c73efb5312819207b3129e5dc6019e47bd8a65c209e982d7f3da47194b6e96991964e9d2a02a79ca6e17df593c29f850e	1671744607000000	1672349407000000	1735421407000000	1830029407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xe7b6a1dab456915da823e54b949916905efcce03be12ddb9ec2387f59baa80d3db425270aa076518be345f59537f8461aebaceea845cee27e47e0400334de8df	1	0	\\x000000010000000000800003bf8d9d93d55c9d5b78ed1063b9e7a799e0156b86362e78ef2b224208944665dd4fc1555c2dbaf7de8602dd4ea92f875d9b466da35751d68c0a8d53b32fa9ffd0eb5b1ec4c5985af48a6961c617d4d2d7af2a11dce8b9afd087820e6cc43d57d64d057b823c2cf81aef552e2346d29eda9b9105568d9333f19442a981399914df010001	\\x328e0839a34f8ff8c83b0223e7c8807b63fc62e63a23fd9ad10e13cfac305cc5c95ec1ada3ab8855547cb2a001015c2695212584afd8c29412ccdd338c6cbe0b	1649378107000000	1649982907000000	1713054907000000	1807662907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
310	\\xe9c220c94d30c4876a077c7f02df9d4ef99c49628fdbcae9c9095f590f5ae4de67619f907b853f377da91e1f7450cd0452e39e60913a00d7f0480dd076e8602d	1	0	\\x000000010000000000800003e23a61bd377d8e295fda9b4291bb33a6969d3bea57b5f547e230e3dc1775ba41fefc15807ec77f24093f79bc82d16e7fbed92a17184a15b003f0743ecc002aa42ac2b2550436832f4f7336002c809d4e89bee7d3e1792c0e725f196ac1a58dfc887a4e9495038c0bfdfd60aa7137f21ede25ccd77c82456e9f189fcc97e01b65010001	\\xfa1d46195fb95379f7de54f1d035d7f5702b55a64f7fac5d76bc5ec5301f40fee6f85656f64f99f437088e996bc18fc389167f6904ddb780c71a95a2c2288208	1662677107000000	1663281907000000	1726353907000000	1820961907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\xea9a2e59ddb1192621cf17bb2aa5dbc6624fc74f427051b9e25d94618c2d6d11570654be08bf169ca231b34d49588134f8ecfbb5e1a00b6edfe4cfac11f32a0f	1	0	\\x000000010000000000800003b39d3ee31a33c9a6c6e53f21cfe290efed8faa9a5e336fb99eae6eb45d3bc75a0ba9c50f869b7c5e303c773991aa8ea30fd811472a3b979c6ca04c1689614c7d8c89bcab76c739dba043643f9eec9e1471089d025174f479ee45c7b2d7d620ea9f16e3b6e4dcff99d9a6f5845c3a5ed01f488cbfd279ba0dcd29719fcd124aa7010001	\\xa4ff613833e47cd2df3fe1c23ba02758d06301253937934e7017afca31e50a6c40b77e974cb9fce4abef13cfaadad7259a1c20e66dbb384658fe723388bd170b	1676580607000000	1677185407000000	1740257407000000	1834865407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
312	\\xee5ac3c1d46eb1b27966c1db28cfe4dd9c18b41508b831c44015aa0a2ae385576125b44f5336b5c1641c0e7180ca18ce1fdf82f4adc3340219966f27538a29c9	1	0	\\x000000010000000000800003eede94d41082c8f7e28b4241280990bbbfd0f672e11fd2fad554c18551973363950c98d9d5a01bbe5e898da049010f2e49631fbf40e65b20558fd7faba62672a6a052b41d2b3553dc90e5c76fa0a7872a7eb8025dbf807372e30704c762a7ef29c7e59fb44533683f33bf5554e57de90e4db4e1097cda240406b8e930cf77211010001	\\xe47be38ba70f1d5440aa1da929c0212bf76146f169de762beafd3228c9f381cf5d82a70decc698b5229ba49c55df39c92aeffa510c1a66cdcb56de904e721c04	1660259107000000	1660863907000000	1723935907000000	1818543907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
313	\\xf39611e8206cc0ce9dd035b067b5fa0f8c4541114283d48f17a353e9d35c84e0164c12b5d7db4e9134b6f20405eed061c66a0df0a65d1ee84a4ac3e7438e0665	1	0	\\x000000010000000000800003d76d86f519879192c9e37502bccc64f2311bd97813ff684eb9e7fe390a35beaf5e4e254a1537752dbf77c7ac07baedb799a0dc0d141dba9d537ce9850fc5be25fe7bef33499ebf7088e469ef88cfae76f62885cee2f7e1b79f53873d8345f1df6b5b250f5e8d102713695845537a01c8be120202965bb8c397d1e76373d73ac7010001	\\x2b8490f1ac9165de4a2c540c8fb3b84a550471867e05b4f308d267f85b112db32b48371e4daf19bf767813df5059bc577191a4d6c2feaa4e5727e9a9b8cc1305	1672349107000000	1672953907000000	1736025907000000	1830633907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\xf5a2c5011af1070aa42ed17bd0b8ff1fc74eb1454e007be83cab75b826e6977b717b9a3784f31065a7e889e6d3583c9084f29011b7e451d7c4c9edad4bd4c08e	1	0	\\x000000010000000000800003c69932d426477173946b5b5e07ef4da10a5da964800de831e5fe780ebe1bdfd1aa90a6e52db5b6db05ba37ae06030cb78475cff0f87acd11f198a37caffe27e514d7f126d18054bbabf6e32bb23298d632ab2b2fa0b2c5436f196b07e5a7e88732f9e41bca7a65689f4a29f78fe6d192e942ac3efd35524e015fe2609bc6b96b010001	\\x31a423037a3cebfe23e39e136b5ce6cb32cb43bbfcc4226ee4772a6b6658b651604a465f9606b5d93a6c760908d215922f649f9bafc34c7ff030dcdaf7116d07	1676580607000000	1677185407000000	1740257407000000	1834865407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
315	\\xf74280563894bd28608d10e60c7fa943b870666c1383afe1156697a7c1a84a5a6a20dcc69e0f6394b9410882e1430746ba0da42c6b3d9665fca365c77eebd29d	1	0	\\x000000010000000000800003d0ed19d95900706cfa07b5d22d027290f63a7f3b90dca14388b930c1697f3f428b407be287512a65ef0724011ad6039c6459e5f83e3b4b385a54ce019fbd58938a3b1f1b4f4dc83b655d994c44516827bdafc182c2fa5e3cd32f6e73bd46d65567e63c8921c9b587589bb28194a69ae59d7dded8f4adb12d815f097e79d447df010001	\\x5ebe01cdc66afcb494d798f1eabecc56d0d1b21f1f2eb1c9f678444e1142c6fe302a859fe41b4aeec2db8ccd4cab31c814eaeda568f18aaaf5a53a466ddd1c07	1666908607000000	1667513407000000	1730585407000000	1825193407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xf8e608f65d43b4cd70b1423f2fe38d473a9dab15e53e52cfc5e3539e1769bfe753cb224a27e1a1be3365365a01659552627b569b36658326d4e9926ec04ae324	1	0	\\x000000010000000000800003f554d346795d265d03ce6bfaa020f31bc4cce392cb2a9c54ab3ff4fe41e4d2b912bb176fa14fc5407f6248732fa69f8e4c81a3772a09c4e63459156f2c01f70456acea674c64fc3ee0bf9bbc9e30537f26d2a65544ad27ce2ed1b6a30202378d0aae1045ef9d2619212646f531a4a89dbcd943e4462f9b94b9b9bbf750a296a7010001	\\x652901248c9610f120b1cb0c197aaeb194cd5dc902a25326ded1f5643300232e63eb2ce00cf9c748416fb0e65256fa0563bd9bde5ad6baacea196822758be00b	1647564607000000	1648169407000000	1711241407000000	1805849407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xf9d297c74b537008635df9e82fc16dc6b7ccc9752b54be1325821690bc2dbf058e8a2e052728359aef778cb07dc95fe1451430c7fc52fe10111191fd3e12e52a	1	0	\\x000000010000000000800003b2412f44e28fb72bbf97b458ff39ac1dc82731cfaee71f023cbeb5a9c89aeddc329f8d527e3014e970229ed3f8208d078cff40abc8978a6cc085541d52abb2b44dfc1d1ded27868e8b7a64ea18e31bd3a8d63cb5c9afc6f898fc852fb11a5c702adfb4ddc3fbd9bd0c787cab063e3af0ba6b428101c6e963b58f7d46db1417c9010001	\\x79cbd2a4ac55a659cf8b63101a20c71e58bfe913375ecfbd7fc5d70d7254433a597ffb13e5af1d4d5a4cf5b298ad46a25c1ce3b1e5ed6497c33933af8d39dc08	1663886107000000	1664490907000000	1727562907000000	1822170907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xfa1a69ac1fc68757f0eb55c2f983e3be44f4bd4bd143418566bfbb8be5f94204cf725aea744e128226dd3b3ca8850138efa9cb77c963f549a64a43ee007210db	1	0	\\x000000010000000000800003d2f8df1db9c4e276462eb6f865916724f94056e6b60f0706cfb605daaf4598f17076c2ba1bec18610085e1247cee24ce0e803319efba457540a8525129f617afc233b00dba400718d191f0819c9cc2171d892e26d467b6db811a060496dbbb5bf5e86f1236ae96af896892b6666a9ac660f6dc1802934fddfbd4fbe4a2e90167010001	\\x760707943802f2c250a12bdeeaa78ffb2b0ada393a679c0b04eaccaca212f7ffdaf972aa17855d6c489af36527fe07c8f7effeb4162a6a22c86d2bff84aafa08	1671140107000000	1671744907000000	1734816907000000	1829424907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
319	\\xff86138b0a3cde230b0c938acf5fce8b7bf83ac5c380cfe17153b41e4d2aefa9706c772442ae5631889d885ae17271ecbc8b8325fc33bc8f6fff2d3e048dba43	1	0	\\x000000010000000000800003ca762f95bd5e1cc512af56f496c4c5c977e4d4fc9d1fc0ca5a3df9621e2bc056a1e89abcec28573c88fe3459a2fe5bcc6a8305b0d54760d6b4a902b2307d3291a751807edead3f3862dfa2411fbccd8595748d25d4f16aceb38f99f3ded6aaa79ae62e7156f34e8ef680dd2f3e5602163a6d7022cca744bcfa0201228e1cf5b1010001	\\x07a7c48d0372c5367609cec7e4aae86e1337f1ec3101b6781595ac7b980d1d7fb6068c7343fbf43cbd9351fb25d4d630e1411c752b34afee654a48d9bdea5108	1655423107000000	1656027907000000	1719099907000000	1813707907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\x0667367b8c90821c75a309efd8392aa54fecf7ffa44f81ec45d727cd934a66e48a419d7e780c6988d2907980884f02ccdc7754ae25ba0ba3b63c1ad39ddc882e	1	0	\\x000000010000000000800003ae42b5292de8ba0a1b1787c1264b4bd2ac966489b603668dfa407d8160442b1a935f1cb4885537a37d51aeceb1d58364005219b4a3fe78ce150eb624d8c39c3d28cadc84fed19dc3202457ba6cdc898d360e69d3d06fd09b23ac34ab586da939e44c1cfc1a4db2aaff98f962d995a3d848532bd101e8678c39224a39ab2a5519010001	\\x073fad63a03aaaaa5185d4143aaac73418df44d4061c2c44f8eae21eccd086a8d0dd76f8ec03d186ee1b12c779e8662b979df92d4e1026dfedf6345140d0170a	1661468107000000	1662072907000000	1725144907000000	1819752907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
321	\\x0737eed8fee167a98014e467ff07d0926f45b15881a4db51772a111640381a3834aefd7e243b2f7560d7b1ca6ac905414160c2dcc33975c8dd1f7f154182cac9	1	0	\\x000000010000000000800003c2fa8517664f553581d380db49a0d74a39cfc36104f71c4463f5cafd793b65fa48132b17618b1369a08c433dfe69cd4879cd2103557f1a35f2f7dfdfec81d388944a86d9129fe7caadacad9a55d3d64c0e3154800e2a0213d17afabcaddf13642e4ba4c09438ee94fc3bf8601dc5ece05d379ad4a5776d7f2b8e134c928d71b1010001	\\x6c2caced18141442496a73b899e284aa04bc8080f303b4d82d2db3ea8c04d67d82ee2157be82eef2d7cf16ee26b43ce5decd041963e1f9db0ce8f2a8c3ee1b06	1674767107000000	1675371907000000	1738443907000000	1833051907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x08ef2cde05c81a19399648eca398c9cc44229c61a52d8cdf25d08dbc600b406c7454b24caac1c051292b5905de519c58a00a6df864dc827a3e5a2c75a5eba0d3	1	0	\\x000000010000000000800003cdcd2ae372f0147d26bde3150b035c8adf642289fb8044e2d6d11dd31b02fcd810afdabc6f1d0373fd7d2b237343f3b330399a364ecb89dab2898d396c25c7fcbcfc2a8c59b70574340bf176d28d3808fa074284d23f107a9116ec51c084bf2a249ebfdec53f814e3be4e70e40d9cdbfde098aaefd162d128225359f7fbc766f010001	\\xd7340b159e65239083901cc342096127bdd5520a6484b285e6e4c852aff01aa760afd1a569ef6bc42f7f046b5600cc52fd0bf0d6e3fb43b90ec84556ec1e910d	1662677107000000	1663281907000000	1726353907000000	1820961907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
323	\\x089332d45720e1e3d2cf32ff815098d2fedf36638a09ac66a2012d403d248f35ce43b22a64e329963f2649d4becea4d01affc08969015f77854d162b890bac69	1	0	\\x000000010000000000800003bbc301ca867cc1f91b6e08ef7bf149b37f700fd5d7f331904797804cac3742646ed4e30e2e7ed3ebf95c2bf35a3e73d7e78744dae5db00ad773411bb8e136d2fb6399bb9a6fe56d594870b784c6dbbe39d200b3233e624f37fa5b1d7e228c6005af53fd82f72410dfb62dda6bb2e8b6febe11f8f8285abd7f5d6e21dab9c90dd010001	\\x7cb0cd5d3fda419484a31a01c71fb1adabac6d404073e67925c86bc9fe663302ffa61c86e2f44460c8169cf7980b3d2cdfb58b6713bd615dd3ace158b49c4e03	1670535607000000	1671140407000000	1734212407000000	1828820407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
324	\\x09378081240f1503dd3c7d12ca032067ab43c0d35bf92ad86e01ceca748c7e5365f2b6f0029dada23c79cd6c5ec0418afc7cdd3d986c45bb8e2385351c4116c7	1	0	\\x000000010000000000800003d62a3dc186fd4f3d5f51f73bc3ecea29d9109d0e9f328a148141d3a31c59b5b0afab15d548332c256568e0af4989b853e7ff878fabcbebdf19dda32228e05c73dcf8f80c7b84def3098ceeb83742d29c929dde9d55e6545e2745e8bf3e034f89fcd5b6afc38a93470fe0ea05280c54a3ad4c9cd86370ff2c1873693c99561f07010001	\\x6f42faa5b091246757ff1e4bc3564520f7f43ad76214ae1058d0007915adb9866e9765b225495870a1b9661ba53c2816a446e3e248d4e29d9f640b6438815705	1653005107000000	1653609907000000	1716681907000000	1811289907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
325	\\x101f55da9d50ae4258f444ae5f46486db2f5f6a4e9a77ed043ad1d0b55eac93de3de58a97012cc8e0e0849ce55f28dc986ec92a7871383de9051e3d13cb648e0	1	0	\\x000000010000000000800003c2c50b702ad2e874a154103bc1ae4ad27ad25dfc47267c82b0b92e0f701122158ffe652b756a9b502865caf180cc9f9609da9ff543b70e0c577aaf51838217a3fb52de35c4c12f981a563bc60db7a9eeaab12eb74f74dfc88f469bf6192763f14ed1ebd45df697f8407a73a0da971f068a17a5815881b23ddd594298e9796a4d010001	\\xa542358016bfe64893dae8d3af3ec38e05ad10d7c8256108eea45ca576e44a3fdb9758304ca2e0ee1d7fd5f02a3ce7bbd3bcbf389b9ca5235cf6d28728ec1802	1671140107000000	1671744907000000	1734816907000000	1829424907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
326	\\x15efbae8485917e27ec25b73b8f23df3bc35eef4595b89daeec479e423442124d683a858d308babf60cf10ba14de972ef64a80e25435c400e631d552e1b4723c	1	0	\\x000000010000000000800003b51ccdee8481db5a6878bb7e34b677385bd80d1faeac5a54ce02f34cc7b2e886369bc96e122a1262a5b0f9ca2c00b4b7ce6b7ff616ffb7f2ee8904f90c81e291614a389cd39e4216c562cd074c4f3d8db592d81c26dee516ffd0acbc9d83d2eb16bef2c965b73825202ab0541f040d91a368b37a5f575d31cc42bfab855f1749010001	\\xf80e031425d398f5befc07c3e1cdf868723d0bb60ef90d4bff2f3c3f3848125417afeef6a50be96f371b6a45f518fba14797717c40cbc4e1274a4417baab6503	1666908607000000	1667513407000000	1730585407000000	1825193407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
327	\\x1677d5f115b06abd3054975c79305983b2f6f19fc575390f76ed1cdecccf4eacdf91a55a40c9347f010e523777f7a94ebe6a82547203957d9b18550e113f99d0	1	0	\\x000000010000000000800003b4aa7dfc4aef5faa60afd4d5816294718e97dc8e9823b33a436ef4ac78249c4f6241de5d6826324c471e9da3b3c4c2bf6a0e5556027051b6739937e7dba99603a464e3b23fc5e34f4790bf9af8f4330611a0adec4401b5eea43e269e0a9922fc273429a5b7c683964877bc17b4da07ba9f2d0346eb0ee89200b4b0c6d43fe1e7010001	\\xb8deeecd13e64450481d43b7532defacba91bd5d0365f68cf839c873d19b78438c1405938fc51453b749c22e506667546df71f9ad602ea4e937e1c2f133c780f	1654818607000000	1655423407000000	1718495407000000	1813103407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x1d9ff3d91690926b59e241cdab21cb4bd6679525948ca115872f963ff0963fbf40880274dfb11a41c0e40f0164b927c7260103413c2708adba271de8271a5641	1	0	\\x000000010000000000800003cecd5d0491e3e54138919ad315c7b0551f703bb2f3bc2061a8af9982edef3bdc2492845ac6653bcf75226ee3d408bee3d9e605000f6b402c89c06c7869027c0eb776f499077979c58f8f5887f1f4613cb3e7411c6ad3cfa5ac566051093871e2fb5be6608ce9e1b0b820f0b6e2f5cc675b22d41d74a24cec2e698efd75b83543010001	\\xe46471db443bf2f16abd890ba3f4b412f26324d39b0cb341ef5fbd841a6e9357ebfe78af9bcf1d29b5f9a327a545c92774a876187eccdb93afadf49d8cf72b01	1676580607000000	1677185407000000	1740257407000000	1834865407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
329	\\x1edb94c75d0f7e9560639474f67b56f7ea2d6db43332de8dc7ba5934ae5ea1cbe5048f0c3a3767e16c53c54f3f2c325af232761f4e464be093f53b8fe705caf8	1	0	\\x000000010000000000800003c28c8b4f490ca470d2a1674ed698677395912cba0bce560966a37e3d21fc9fa51971d486badf461afd39f2004a292ac84b6edff773489ce54f64ef505533bbd52a6b1fd052c94554699e0aedaccb86998078f4ab9123c7a6e4fedf0b964e4f4a35a867b30e17cf6c39ad7893f7d7a5e62b0ee8346803802dfad08650f4ad4fd1010001	\\xbe9bda5b18634d8b973964d5525f46a46ce676a3628804e30f8ed2a342cf9c817572d5b25a7f96ea21bd14931a372ffe532d38bc7758b42ef22c930d35d0e003	1678998607000000	1679603407000000	1742675407000000	1837283407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
330	\\x1e2b3f700789be3f449604e87e50318bbfe1a86962df76214f9411ad923f7d14765f547fdd34990b096d494b1582a57863f10c04219472b8c65d0d160ebd27da	1	0	\\x000000010000000000800003ea309780abc7f5151d027ebb220d2d560294befc887d386416325e04ad055b7b6a6c61dceeb15fec932c7cb05502a5b991ea73f31f45f076df5f6a048a30ef9eca29489b030217f986221f9928d78f25b8bb50d2484abacbe066578be46e6190816deb6929a21085fc77de7acbe3933f5633737ac2941705574efb868ba971af010001	\\x9b7d200debd1010af60d7b9f9bae89fe54bfc5354716fc494b186a76764a1964b3072a110e6333ea9b1cc054e7b3cab8ac4f3f9feae32ccf14188b20bc40b501	1668117607000000	1668722407000000	1731794407000000	1826402407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x1f3b07be091c28bcbd4d8e925be4268d4b5a8b2dfe061ec615ddaf4876a729978bcdb969c04e998cf256237f338922ee8270eb0534d8dbe7e01e232cec0874b9	1	0	\\x000000010000000000800003b7bb2b286acfc07c142e806913aeabacb3309e2dffd8e1822cd989db63c92933a90c185d1b6daca1d9863d1144ff09342010d1cce5cb3842d9770d806e116b28566da589e0d0c6cf483bb9e52862048aee0f8e9b727d44bb8bbc37afca7ecd05eb1038e00a2a8014a57e46e873f9494c3ee8c4d8dab8d38e72132d3367c6a39d010001	\\xdff47cdf1fa30f94fe177f2e04bfe4615e1c58954e700c2b05d5fd3bd3404d2d1460da0b01da25d8aa0653be2202b9772dc2e68c515c873c985db3678738ad0d	1672953607000000	1673558407000000	1736630407000000	1831238407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x24f7f024eb53dd537975d965bd07d5e897e1d76242f3b7adbb55f84383ad6ebdf91d225655d7d2a59849f4b5027d11ea5aaaf1e29c522fcef02bd8d7824c5bc3	1	0	\\x000000010000000000800003b57d0888c24de268c526a30462d7f0bbb8d9456b957b49b8a8a66924ba77d3b376bd6c95b225a8fe8f6f9822480037bdf1a737c426650b63c260250bcf5863c1516b243b1b8f46654e2748135035059a1e2a0c07fd974bfa0eb5b1a9a0f814d422ac85b1acd76ea5a3395ace1604ed3054d9473fe58dfb3bdbfb62c2c910bc93010001	\\x4292cd4edd5a12576067210dd657d3746f32b8b9c75429fdb74a2b79d15235ea60db9217ae9d63fd03991bae5719ea6938a60ca5fee547526be49b1b21581e0f	1655423107000000	1656027907000000	1719099907000000	1813707907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
333	\\x252f612b10e0626cd74092316bfbbc26cf9c32c1d53e836f3b30cb1e37531d7e1f7629e82b21907d3ec3c98f91dd179d9c6d9f6d74378d58a039e9348822bf98	1	0	\\x0000000100000000008000039d2e4709e0fec0bc9784e06c8439b9638cf59a6f9d45040375eded4a0f2fc2449641a26bda2605ff9203bb32bdf0011ea152811075995291cc412191aa5c68e5efafcc63eb8ac6f82d2a9af624648d8d7eb2984af629e0e028b7fba1067679161042ecec1d236d733552e5619d5fbe0bfce95bda8946ba0523e54d218ab69495010001	\\xa383bcbeafa7d7c18b8759a15f4e60aba06cfec39d6fe336453c80eeefb70ce0385a2cecd18f4b8bca81e0d53315cea71e1ed20f8e79214e520d174b7d03190f	1674162607000000	1674767407000000	1737839407000000	1832447407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x26eb8e2ebb14ff83599f5934cf679097965f7f5dc2076a26edc72fd6ca46b59db56c54dc8271de69e72eada72f17079a08eb6d2c46c977fc093aa86452ea45a7	1	0	\\x000000010000000000800003e1d0f4e0a2d9f746f622cc25f2be0d8200177620b487bcca532e06b96c38c7d4574d24683b6739db73e5cdf8129c235bcd1f8a459a9c83aab044c7b71b352c8e48418302e5cdf936d7c10e6cd271cce27a51d640e49003ab9b57d0b5a6e12e068448b09931e7e92d60077e66016f3784b22d5615342aebc1df2bc61431138355010001	\\x46f6b3b5fcfec361eb34fb3149078a21d7f9e03a6e202619368297ba9adc94406d9a3f9fd2e23631f44ab3555b38b42efa2757db5e1f23ffdcb73b9b1a0b380d	1658445607000000	1659050407000000	1722122407000000	1816730407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x278309e389ec3250af160dd8c32ab5b3108f5633d379840b74e7c1156bfe39593801faff744bc7d700cd42ad1e065f3fc7cce02684a0083e5c60183991ba682c	1	0	\\x000000010000000000800003c9270d4a153c1d111446c98431f61a599e91059dee4b0dfe621210275ad2f384f6cdbaaafb65ea7b08fbce8443460b7083edc5d92ba6302ef0d7dfc4603e99a1c2c3201f58a66956bcec4521b7f87950314635f9b62720e95ba96da205b3e8b2ed36a2af9a01c307adae96b01aaf294f0d1c501f7de5e27672b202ce62085f57010001	\\x99934c4d2945bc815c283bd48f6ee15f8a2fbb1815e3498fd1f5b4fcdc4a725b5832c6f3cf82bc36c7c5fa86fdb3bcf1371fcee2ec56d3608344e19f6d491f06	1668722107000000	1669326907000000	1732398907000000	1827006907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x282f2860fadd58591071075e53896eb86cf9e61bc394af7f52f01cc242aadb868fa5654021e1574dc2acaf771ff27c78218116c074d459a4c127451d7232b11c	1	0	\\x000000010000000000800003c20fd5712f0c59d8d2090b59b75fa96d953be40d22a8c292e7e30bf746581bcd7976768ef8e959059202035652aa193488ed7069c669eabd0d2cfb690df10850b02be38420fea33f22b20fd53360b97ce00ba2926bebaf5e828850b64251de53283d06f0d26a49d9e579121bef07eea16cf5288a049634af91173f8818700a2b010001	\\xb7aaa6830c78a69c7292f47eb122ae517e1e1294f9e599eef7341257834e64bc8e492e77af42d01af0a0e325dc64fbf6fe91b9bffca70d7e777a399d7bb2f50c	1673558107000000	1674162907000000	1737234907000000	1831842907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
337	\\x295f12d831374c0d58d71fdea4ba7fe45e9af571661fc13aac5c2ce4676c3ecaad3ebad31fd66e16a2a9263b7919ca285ddaee7b6066ab285019b3d40d96bb92	1	0	\\x000000010000000000800003f4f32c51e11985cc49f8b6639c4ab795526d441c64e34c2542017b8a387c49bc8d3b038a85bcb88541906cb6c3f4fec6143fdd0fc1bff2dd69fafc2de1252ee84c1d6f0f130c20f8c175ac47a56ba43c2cfd36346cf18afab36d79704c75708b590a0a8bfdceff7f83cb65a3a35f7363e4f6df534e5c9905450b6acce7ddb8ad010001	\\xd56593fdda0f4634c5985c2947ec2675b694960fc49afea9ed1c3b36f191c64a12dd107ed0746f6aa3b061f5d918319d4fd046fefc98936aac9a6cc3d49d1a0d	1653609607000000	1654214407000000	1717286407000000	1811894407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x2b33bc32a22cb98603e47520bad994e6c0141cdee7f69ffd821200d03cf07ecf34fa084e386d84f44e06c1f794c6b55bf1084902b427155a9f34fd332cd5299b	1	0	\\x000000010000000000800003c725326ac8183cd35da53a49642c02b7970d9fd2bd5fcb4a8c469917295ab24af9661947fa205a880d20cdcdf7536309d775351fb524b00b42c6c4c1ddb2c24711012ca71f06b98f1e4a4f45256285979c4ab73a72bc471aa403f0ed3036e7b0c02a6bfc67c565855d20dce9194823853a1a7ae15e980fa95c60ebaaf97c529f010001	\\x22c4bb6c4f40a0fd1c0bb6f11fcd6f39165d273403674761faf466ed598209da03fd5051c08c18c769bf1452060915137a2e2b8d82fd5ccc3ea4da9caca9a104	1678998607000000	1679603407000000	1742675407000000	1837283407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x2cbfc490f31c9468f302333eede171a2dfcaee90c2f52702519862235dcc86b6b6f7171f18bee226b62b11820fc5494e1da2d41a072d2b7af2bdae83976fe8d8	1	0	\\x000000010000000000800003bb6db20932fe0f59dabaa61054a2f4298c7d09538694a7b52bfb1b006bd62a10fe4a5763d135a05fb749d12eb661f21dafc6f6534e4f7281621d5459e2712d4fe5a7fe9fe8af45934cf4150ace13ce166a3e8da59c176bab41f7a8003c81b0033811347f2e71152467b232e00a4d8cc79d353a8cbd0958754107d356dd991745010001	\\x7722025e57868ebd33d38195408c5538b04e16e974d639bfe84ae0d51d987558c970d52382403085f052ef74c2428d1d8d1caeee354e09e7338d0abd22160207	1665699607000000	1666304407000000	1729376407000000	1823984407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x2d83d26a775a6afed565db182aec06b09b0988529f58add690dfded6a80026fc2a6a50e3129f057c0c938b86b3509ae7b53524fae9d9d94fa77f375a5d8804f8	1	0	\\x000000010000000000800003e17dd053fb91bcdfb9839ff0def676bffbaf692d7358dc629e8c259c424e35255cae16296e0e9ac4e39d62a7250fcadd0422a85c2b47fb38d94bc1a723e49e904f713c301fb83ddc27790c5e53829b6926d98772bad6ac9661fb71ecf4a915eee6a818842c23268f69c8ba8a32292f0280f14ba27e99f58d5f7bfae17a35062b010001	\\xa5b05a87f07ba1a2a5af0b875d172e245f5a5511581e7b580ab052c7cec8e04f7a8a2129de0658dd7a10c753565a6541d6d332c5067668ed624abcbac861d302	1663886107000000	1664490907000000	1727562907000000	1822170907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x2d43ad67eec485f5c3b7bf8839f2427e2574898730695d1ba17159e0a6ab4dc5b876e24bbe7d21425b5e6adf31696b4ed6b09511930bb37e563f0a77690034dc	1	0	\\x000000010000000000800003bba811dee006d9fa73c3253ea3d4f05f0dad52bd70b5b873ce4c9ef85bc9c3a0aa47247c7d3629731f91f418966d94a6397f1a03056e628183155bbb720f38132bfa2b4cdcb17616f6bcb4fdc01cd8efc10fe847fcc8997c790447b73a268dd0ba74fcb5f77b3b7a7de1e21038e3301b94f895188c5031e9b8cac349386d8d5d010001	\\x0493c699b75c426ee173035a475f5f7788a0f95230a784721e85390ab6cfa4d8970a7feb0785d83f8495d2a439033647bafc86af8f26fa76987cc71cff1a7303	1656632107000000	1657236907000000	1720308907000000	1814916907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
342	\\x2e0bed87ac4e8e147f7a07439aab105768bdbe347762b14d3f72f4731cc14bcd87f8e58ad1d2bed1d1e30fa8bc86e5c64af83900e47b5989eb7df8cc0604f8c8	1	0	\\x000000010000000000800003cd99cf4124a0b5bcb357af3501993fd074267ece5aa11789cd37b5004c3519dcef64525da3f97be634c1ad94f4d819c1c066cf177f85f1f49df221ef872a8c33d075d13aea38d16e3dbdf29d7c8540af2c8e1a2ecff2cf1c674619cfb6ce89f964d79c331c657dc2b83323e2e72a948d60abd9bddbbc36d58e324ed2f666d53f010001	\\x913ef6fa56ed7c66f6fc7149ddf75a8102238e0b753c28995320407883a6d0027d3066c28af085a8c4a0b0a2e326a3919b49f9df8d4e0a4ab0a7e8639850560b	1652400607000000	1653005407000000	1716077407000000	1810685407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x32fb50e318d5d34f4aa044bcfb57edb5af6aa5c2162e409e018e7996115465993da0e17ea25f6b6b0a48ba0a555615852d48b778859fd8aaf238389830e0c668	1	0	\\x000000010000000000800003c87cbc19bf59bd49f4730c318eb1965a174fa6db39393354ea85f3418ddc1ba1ea580082f5bc0068de9113b087efd1ad2d1f10d8768f2a55ecb1ab65b1c950dac1621f034b131ac10b30d56805c131bd33db1e7d4f5de3f4c0f41dc126aabd121dabed6b4db7c52e9bda9b9f8678fde4fba4d080a018a530ad7d9aee4323b229010001	\\xa613a6685c0da42367725269a82d51edb3aa356d1e9be4a94c02e9f537e84f5a3a268bcd303aea525e2d04bf46f8af9746e1c7326196b6408658096d48f09b08	1678394107000000	1678998907000000	1742070907000000	1836678907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
344	\\x329b0b438767c7394b18924435272a65d1eb522ff1126a1a95f5d8421eacc602beade2a98bcded3b03db8905ebe7c386380a81ce796f952965ff1b2667d9ee68	1	0	\\x000000010000000000800003d14aaf1a1879eb6218660066f992bdb972c8d0bbb35236f3cd29babe5fd13ef47bb89547ebda7b87cf51ac329564cdf0be169a4dbebc4b2130a24b9c0c5e3e7deba47c0fbd93d1de54f949bd86552fd1fb38f6cec2f6bc2565854b0a212f7a284b5365111ac16a6bbf99bd735c15bf990d6119a2107a569137bde385be697a81010001	\\x2fc8b8a37a6b5db5a3698106b6b6a0a2eff623b23ce0ab0fc30ab0f9d18bd25c0fc3d2ab9642279623e9b19c4202d80310d59fc750eccb00b7569588dc2c5408	1677185107000000	1677789907000000	1740861907000000	1835469907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x339f75a1931ca5635064e46dfe42eeb6d3486626c80f88af8fc17426b1f2a72790026888c9341516355712c5943e8a8c4805e48c48b5c79c33f03b5d91988e31	1	0	\\x000000010000000000800003c824f5b3517cf4947a8b12e599f6d2cffa596aa9948ca12ecf3cc7feb55defdd80fff112dc33b44d7de48772a1dd71163b0456e909678a90e289d267fae106e71b814accc6519b7ca4c1a6b5d1084fccaa2a868decba3c22ba822b59c47176806822b7d96a5bb253da0a4f60bcb91f1f01ff7003e0450cba1ba2889ff3f1e9fb010001	\\xf95b8db5ad72058781c152703e3c34a85e6659e476de39eb98e3bb748e8fc39cc58f2a2bdb8cab896d62f03887abd53ea399fda1a4e9ab5581e4ac59f03df208	1656632107000000	1657236907000000	1720308907000000	1814916907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
346	\\x3623545723b9e73feda709b5e28158c55b6c6d2f436f78872ddf80d10fc7ce932414194e99f0ffaa378d7859d0a60480805207af0ca26795949e4e05ac2dd984	1	0	\\x000000010000000000800003bf491ba58f40d6d523142909fcbd7a130b7f909816ce84cba626ee78dd1437b6f0ffcd4f7c0f357d5cdbb78857bed4bbb75e2260638a6ca6c1e39f1b6ec43b6ad7c78951a83cf6c7a3d256e7d9e15fcdd3ef410b74c136984d4fd9bee3fbf4081e0857b17af4d281831cb4e2643def8c0410675c9ca416dbe68caec7ce39c06f010001	\\xb32c7fd134de366ceceecf35a9cb8f7ed20a1a04ab1a59a4d8e61586048b4ee9ba3b4561f2f0ded88b676ea17865af388ff355754dcbd2d6cb2c544d4b3f6709	1675371607000000	1675976407000000	1739048407000000	1833656407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x383bbe96d8827a384255a94f466154ea5a1d2cfcf4df71ff44cc6eee887d28db6ba2ea820f127c8c0742bbfd9ffac0d9dc8af66d6ef02ad9020811e68419e73d	1	0	\\x000000010000000000800003e5ecd33d2f648ce4d019d012a78e6397ede9869231d4f2f7c9d11af99796296d985868ac2c1b91e7e11a60897d5e9a6dcb734b5315ba4c7a6b4c8a7dfec8d7f327fcb02f689dbe7e01773bab2fbeae6f602e1f0999d3ed26ce25931fe64ce48d4f1195ee0dc909f4568fb4058caaf706c77154913c34eadac322a7255459bd1b010001	\\xd4890a7accbfb76988e9bed3e20c14d347902c64de811b22b87b81c134ae28c6b958f541a6ccc570cf14016a8176b6cfadc077918b7eb24aab15757d8fcd6c0d	1667513107000000	1668117907000000	1731189907000000	1825797907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
348	\\x3aef3bfb88980e0cb1c46373652d4d7f41fde82244dbe2bdff837df38f3bcdfc95ef2e1d39392ffdb310d163f882cbbc91e3d6ecdc20cd654163a36e2bcdf15d	1	0	\\x000000010000000000800003c2a4b17476a4fc25e8ef33cb2ba2f7a91dc25b2f66009310f510a65db8f08ed9a8a4a889d7df6217b7a311a78d378392ec092c0741ebd9119bc4a13324c6deabaf042a99ff0abdfa9ae22293c191d38cb7db51338cfacc4d855277cecfde31862247444c97a22144abaf6f01c0b329cf90c351a1db0736cf67669329f4864967010001	\\x3fd96ecb79438cd9daef85698290b3d11a6dae59b49a18ac33e817df279b28c4f733ea89993cd68b6af179fda4c9f931cd5989a5f22d5e4f356ef0f168e57a0c	1678394107000000	1678998907000000	1742070907000000	1836678907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x3d23f5b714852c7cbcbf081540b9682f45c2050a629475d62bceeb4b4afdf93bbba00dac82b894eed0c68d65f445cc32a1a28e16cca5f0df198fdf8e867b818c	1	0	\\x000000010000000000800003cc4d131931c5675d372aa4bb588b300f1e1acd37d8977d5cd76498096ad66dc29e858ac0b08662490cf2e18e393d7498278f2db2d3685865637045ac56b089259860ebec51eff927fe3f94922c440b1a5bd83d9c83e7b223f56b59fe286fe1243bded840c067a65da36c193aa218154ffd9ef1a25badb245a81f1030be232b71010001	\\x56772f5ef2f032e19f622a28f5bfb42b0b761839dca014419eb55aa0df9a3ee3a9d69f4ee2b3f203b1276fafe28b3894aba977f9ed30bb856939d3a815ec5803	1657841107000000	1658445907000000	1721517907000000	1816125907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x3e27ded3df4e6b254ab517a2b58574226e50e7c79cbf556f8387bf0c5f30e38ca52d308c394564dd7d0109ccc76ee4dc4c73b5958561a5871baaab4187f80bda	1	0	\\x000000010000000000800003db1cabbac95e804e52b20896862a976ec1b7db9a5fd8d5e893578f71b0149769a8ebbb3bd273c3ced954d7e78f495f7df55f792bdbed116cbff22f33efb04dd8c7c152b69c69787892d6c65ea212222ec848c704dba8ee02c0f2f40f1a8809043f7855e1b883e6cf04c815278e0c22903c292d95b327851b187efd3a16722e1f010001	\\x4c38f1dd921d6adbdf09628248a27ca38ef87950dbe76c20e3249d7663fedc967b0dbb1d5f4fbf029853f75a537368d51c64500fac6af0733543e080c23b8509	1676580607000000	1677185407000000	1740257407000000	1834865407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
351	\\x418baf40607ad5193f9d265364b86dfe32686c939896e212060b5c138d91ca3f16997df8ac46c15e8a99d128b0d0d90a28f0128958b9d3e52a65c36cc14c3ab7	1	0	\\x000000010000000000800003baa1ed0db28b4c25ff27f711ca8ea6b90bfc99f14c00dcc0ea04d6659fa052701d52b8d8b6aca31f57d7761f895df838098709e7b18db550c9aeb50d4a4dc1c434306bcebaa602fbc030f2156b220cc2f058cb09f7deacd8f79fa0cb32ef91ef6ebcf45ec4620f72cac3ec9d498108b3bc08d6ffc2af432c4b96bded76354361010001	\\xcb747a49f79ea3eb48aa851dd1d7d1a9a2b2b867a3431aef1fe9ab58ad66a943cb8e98a183f2c45f570f0405dac563aeea26ab89a68492fc5bcaeda401600304	1668722107000000	1669326907000000	1732398907000000	1827006907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
352	\\x4373a41f79298ace8933f530e115d1aa7dc494d5fa611319214e27eb629ce4a2693d296b44f4cfc18220024936840b62c49c0757d2fe17724d2f6c94068a5437	1	0	\\x000000010000000000800003b506866cb736142674da1e5fda4d9d41a966e041cc7119e2ad7c926dcc1d74b82dc412916090a94b8f159ed7dcd598c5a4b3256846c3428133c201fe6749f320b4ae7666d55d90cdfecf75e84fc71fe1d31767ee4b1e441f37a313024a496e440ea062678702c9176097e710b1ebbdc239362c2ff76fd315ec9c4473907f1af9010001	\\x1b6513712bcba3fadad708055fcf92a87cc3da4c50fc6d466024ece0dc98cf776ed38ab36419b7dfbb5feb655f712593d212928ae030fa707ad3ed866a1daa08	1659654607000000	1660259407000000	1723331407000000	1817939407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x46772ac68f7298cb576a8dac6aa5aef721b0f91f0883f563632480fec3ab4be7d3bdfe7c6dad02f835454d96ba1158c6828f7540afa9cbf72bc21fefa4fd7b70	1	0	\\x000000010000000000800003c76b32fb7b2b7a3b91ee2653744b08a8316f11892890fe078c224eddccbfcd18223a110ffe6fa439c00fa52d5084f042b11c3ef32c7fcb68c9275c1c3912f00163bcb846fa36bfe0293ad8ebeb89edf9c6a234e89d75b80852c94fe59255485d479df1bb6f5bde8259ecba406b8502e123793c8a58d5034fbb7eeea43601e0fb010001	\\x743203f662e21a39a67c92b648f5b7f2693f05f11a30ddccc9b8d121ea2b9b410e443e7f0db43612070159429a4482ff7133a9b641af29c6c97ce0ab0d5b770d	1665095107000000	1665699907000000	1728771907000000	1823379907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
354	\\x47a34d73ca5b8f59f4ee5f450e8801bd0cff7309fd30cb9747de601b93ba8a798d41667818f287d7a331087e4c14aa9ef7a3275ce105f5757032b00377f5825c	1	0	\\x000000010000000000800003bc97b43cd45644a06567b1945408e051c6d9a7c55d32a7febea0faf06cda35c19832fa07172a728c02e6eb4b20308fd7481782dffcb61dc7ce7d9f90d164e8f352c07a34e6ccaaabcb6f13299cb1d713e14bd94cea02a950fa798f60842e3b88d914277011c6b4be151a4741e7069b7e23d15f37362fe1155b8a091da6f0a349010001	\\x2b4dbce91f548c28d692d212a75f7251e13d56c5d97dc427d68f7b9faed894ce795a09115722dce6cf1d34eaff257ef52c508b7b674f7baca209d58902161d01	1659654607000000	1660259407000000	1723331407000000	1817939407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
355	\\x492fccc8ca0b01d6c8a8d4bfcb94f204e15e8f1dccd5034b6d76956f639a737848c2866b2b58484977dc8efcf8518234ec20aefbbbb9d76c0a69c5f72f518a19	1	0	\\x0000000100000000008000039c218c6c95fb353f5d9dadfbf76b23c7b043c9e4720054a5bc462207ca353add2775fcf5a2ff122f5a00f14114ff4f5e5eb02a3f9f668b4a42d71902ab729f50aed23c10edf46c09e56d9fb59b8e6870c705215b32eee38da1883fe1afa7aae1f608cdad1a0a045d01c3e1f6b736409e96c36defaf0818d671c2d1205a973751010001	\\x9f4aefbd8f98ffdb94da1f9d0f1030886f21fd29d4d09ef231d60173e40ebcd447c3571cd3e4594f1b62ca5e82881b54700d80f681f0a05185d96c52b332fb0e	1654214107000000	1654818907000000	1717890907000000	1812498907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
356	\\x492f5cad2647b5926611a4082d6954f57c81091969aeb396d703b52147f40034062e8027635251a504d44173b460391ccbb03c0456af168c69f20a970856007b	1	0	\\x0000000100000000008000039fe60354938a78936c5539b03a9e3b5cf0eacba3e003802214839d8794e533082c1b9bd62a98ce28e988b9c5ac83f27e203b1aed01d076f6e51a86868ae05717158a56b3741a342650a12c180d9c8d5faf793396840a6fb709c41c03a0c270a175110bf18c07931b7ed9d023dfd334dac76d66aed4ccdac331fa43d3bbf0869d010001	\\x49ab3750520c6d0dc35edba909f3edf540e3c69ce175ef2f782cb0a67a43962cb12657ca2265c38d86bb5efafa64ae1d9fcdbd377f2db378e8843bc27ae44c0f	1660863607000000	1661468407000000	1724540407000000	1819148407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x4b63dd259aef0485604694023dcb569305aa5587b98e49861ea242c9034bfb3f47614e66b067de21ea269d7bc2bdf2f788a636898eb0a3f0beadfb5a3b5cb0a2	1	0	\\x000000010000000000800003deff07b3df4323e35c9ea1e7dc3ac6cc0ac6e6a3eb56729b2a3aecd02ab7b96c6a2d643b83e21a7f6c97f1f4ea860f5a79669fc3b4e51f4d2b545939b926301f812eee1056aa4ab185f94d2c2954c655f0ae404fec6c57f270dc79eaa372393d30f409a97c3f001d2b8b9717ea775e0cebef9e13de84b8afeed376fdbb332045010001	\\xf7b38a0475186a1bd6390478680f3be446572f45da221a8801f898d81c1e50cdf613e5f1bbdfd3994c947ae66613567544bc0f9178c8982f2b4a48681c52d305	1663281607000000	1663886407000000	1726958407000000	1821566407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x4e1bb13bf9d29537fd3ce8d65c63d161916706f9093307d1cafd5ef4916ef4205497d1de1d7c444170b1f710ebcd455f087a41f3f9c1f46060eb38b20dd54313	1	0	\\x000000010000000000800003c9fa44dc9d3f3717302e65f23f150ca19ec259b7e273a8359a311a36ad1721a052a2a1d713067f82cf4412653e789e1ae03653238529b45e9c2a9db998000383f61c3127da1fc31766ee2a014a252ffb4651ebef5aad576f9496fc390e1ac8562d801a70387188dc09e47b32d785feda915c8e3b4c96559d18b8cd6711e1ecff010001	\\xe5fefefb0cdd670f179d4ad488030a9758be98820abc3d8a88295c5bd434483705461967b828043da6913d696319aab5b1a4e75148d3badf0f0e6500845d270e	1652400607000000	1653005407000000	1716077407000000	1810685407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x4f03e2e88c838480b2d4610181eb5aa912f11350f281162ba5330f0e1dcccf73188e4105fec72392c10cd4502cd7c5d0d553ca98507ad5a1d3a5981587134f7d	1	0	\\x000000010000000000800003bf9079d3e90592551b5a622f054a71809725a67d6bd30a0c1bc997e79cdecba4adcb384497116136f207bc11f82ad872d26c711df4d84e1cba5d83f909043a61428e3c871779193f09ff425efeb911085d18b2063b99a5da96fbc140c4b51cfdc1238dc27b3e9662f73a9a963ee40c05fc1ce4b657a4cb6dc34587924d44800b010001	\\x97f6e3dca0161c69ed981bd6ea88b4d784272bedf064705752596d990b75c4816005ae4a911eb011c39250185f100ef1ec3bfd0335e59a65ea4267f8b9840b0c	1659050107000000	1659654907000000	1722726907000000	1817334907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x519bf099af1c45875eaa647860a9c51bea8d46cbd1d29a0ba2c802258d4f735f662c1ca52343ca11a901770b5005153700a007e5acc6d78a3413080d9b2c15fe	1	0	\\x000000010000000000800003c190bf79fce5ff6c07f0ec04d0836cd2485dd699e2cffa9aa0eb29fa2d574cbb602ca913b048b547f46745b9f54d8278c84b4788446f8f8489b1845b0a5a97b79041b267a2132b9cbed44d196e3a60f268ad9640d9ca16259bdd156184ea5164ea98d69a4c2974412fc303c67c6e6cebebdb848c81ffb578359e5a27755c42b5010001	\\x485e1dc74b094170f6f959d79fef10d24c4ec7e4cdaf3e51d8f365a53e29ba8d1b1388e23dad7fa3cea0b69562683236d87fe8ed01633d888ca5e966fe012a05	1663886107000000	1664490907000000	1727562907000000	1822170907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
361	\\x5153981361ffa19755c2b3cebac1165f6fc18e2dce1cdc9102174dcc8fdd8664bfaaf20b3b9f390cfb5caa94443aa26a38d4c27fb803ce09606fd36ad4249d06	1	0	\\x000000010000000000800003b72cad65e5f36666e6f501848420f58d033700580e4645204412a8b342f0392de77043e3eeb0d50a56859e259e4deb1670183d7b1c793b8aab2441d28612e83d7a39069c4a31fec881e8af443d8300c1b07d06bc48aa2e639d630646a4faeb3136ad0c734c786731a63ec4ba9aed62543e16912ab5b4e9db3e8a5224374d8f37010001	\\xfe7cf40c59ce9f4b450f2487c87186a58542d577acb07b3c9a6c2f07e737965ca9e37454b7ac0b9aec4462c3711149aa08c52b2dcedec2fe91ee46bfd4692f0e	1673558107000000	1674162907000000	1737234907000000	1831842907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x53ebc73aadb27694238caee45a882781c33f821620d9da497a4bcb3ce3acf8ca2b52af162ab88a77997622e13cdf3410fbae284d6fd0a6d65d3c886993aae60a	1	0	\\x000000010000000000800003b8dab569bd1e7d6694d84c58703edb6b9980f8e299b6963ab49524b93dfb71f531202e78baf9c94169990beba71fd97f79b0e134d27bea61ca2df82d77c70f8d20cb71f7f9801ac889531fafb6944584dd6f00579a1142785e5a0b4e39a0eb132799ec751e4802d2f7e3038346dae04df01e23ca129292b6248a0f3b650c0e7b010001	\\xcc61ae9632763be3f9b43b50366bcfc68c81068e74c627df8f6809505c6885f42b3699502dfc0e7493be74b9a4c67fb06944956e92ace5edcb4fc01577546e0f	1674162607000000	1674767407000000	1737839407000000	1832447407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
363	\\x54f3cdbe65e29b9855ff190aaffcbf956af84ece618a9970728a2f6adf0e2699b8f31a052ec07ccb793a00f791d09f97302f599d2e6442d5669cfd1f77fac8c8	1	0	\\x000000010000000000800003c0b63d13b69d7c2dca00c9fcd01f759b3b839b80696be30c858c640566659c067809f8dfb5cae51e16dde216fe55a5be331f6edb56fa77ab44fba73d53d3ac80e8267b451ecdf4c1e88eca3f5606d35841c7f4aa74ef449321d28cc0946a7483b83913254df7119d9d61e4782227d6582c3d7cedb806e4ee75c71b6b9475181f010001	\\xb6001cb5acc2ee8593e846ea79ce6adc8f52c436c6aa39d10e1d8c0c30cfd5453babd613e52d8c24f46f4de9917a2a9eb605ef249408fe360bb4733523bf9109	1661468107000000	1662072907000000	1725144907000000	1819752907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x54ff00cb339ee8638e20732270762e07df3af6fbbdd3eb217984d6a870d217182c54ec591bd111fced9e465e9102add0c8634be124e8c364540b9fccb07f4a47	1	0	\\x000000010000000000800003cae0bb7d9d9ff8379b0e44ebd2e3914b4823bbdf7dc894107fc298ba3c806aa3492bd5e62e9d3aa74a95a070d3080cb204d5bc43b60c9c28624c829e0afa6562474a73ee4633fac4ee31e2dac70855d5a2cc6bbd23ad109b232fa32e39fb1ee7e14de57f2075d7005ae3e6074a81a9557540f0801bb5a418de6eed2c623440b3010001	\\x2664999cb1bd73e10d50f8ff83dc38804c549c9f39c1c88c345ea22f4e700d82c4eb023a76cb5af5e7afe8430a5ee49285adb332f1b8dcb80f0572026cd4170a	1675976107000000	1676580907000000	1739652907000000	1834260907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
365	\\x556f86edbc26de8e79001ef7d60d36d9e907f297926c36db3168db4a0c854aa97147983da3a6cc32fbd88144fb5bfaba3bb74cb44d61c2efbddadfc66b274548	1	0	\\x000000010000000000800003b9d89c4cbca5d29ef15ea0f71acf41ddf29a8fd079f54604ec3b10f1aeac009cebfa1c6c7f1cc405030a1cb4113e6eee567e48ddb8a4e640cb1efeb33845f48cde50dda54df1f701f4bc65574356a7125456a3db648d6e2fdd62d0d20c4b5813cbf077f2dfabc22221bac4e400907baec62e68867a9f2a47364f0e849d225ec9010001	\\x5286bf987da4253de95f101c7343ed05c1687f3f7d4a6d614c6a30ea0b2870e254983fd7a467f7e598c4bc420a0079cf42f2a6d7fca0f38abf70b037e22ebb01	1663281607000000	1663886407000000	1726958407000000	1821566407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
366	\\x5b3f4e82a5b949a5780e59d7eb558b941cadb907f2cc3134de86ef41565713ff6aaceb592b9999994ca03e7448b0e0ddb5cd0b77da4688f9c2d5384523766b1e	1	0	\\x000000010000000000800003cd0ff1cf1e39cf58bd924795a5c7033ee7c19151965d7f3faa764e14527d1381d3ed5389eebd1e068323eabeedd372aa97815479f9d9ee3bd9a0fc5db29a41d15299f75f511aad803f59091813ee94709cbd4ee44a434ebabf6f710fc436689ffb959a9ff39336562df19915c47ee0f555b7f55836a1885649254723a8298119010001	\\x073e495c5a87a3ac6ba30a6f23a6e06d3f2b579576bead06e442371dc5fb03e49fd5b185166a11416b0969040ece4fb3e478bd0c8ca2c43b5161002abdcc3d08	1650587107000000	1651191907000000	1714263907000000	1808871907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x5b97b5089f8c3c4180e1d5a836d1cf400d6d6a8a96d080af04574c39a05a5b14483dbb0aa7bc96ae38e4aa5aef47220580f7f0c2345a8903bd04e7d26fd82310	1	0	\\x000000010000000000800003b704aee5c35bbd9583c821f1dda4b21d05484c02a4ad4d37d2219bb793ae3b966fbcd8bdcbe2ccab88d6246e0f3f3a172d71d85196bb23b1679a5daca359f7c99b4797bc89c985fd5538fc50d238f0eb875f543e05b6e9c68f6682ff4d5c10cb4689aeeafef3a1256c25558d57d8ad28706bf97563d05788b77468b2fb80763f010001	\\xb9996618951a21ac0b6a1eb10f9eb3eb5a000ed87a26ae2f137dcb14fc42e1df2ed127ff74c30bdab1f0477626009667bf6fe82b3a73702fc5ef300e97243005	1671744607000000	1672349407000000	1735421407000000	1830029407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x5bf3af22184e98ae1b3a6ed79ab42beff7f0a7a703715df9923ff4d940090fa935b346bd83ba3edca2d16ea0efbc7a49d293d9492414a0590e6e46f9a0c8ac1e	1	0	\\x0000000100000000008000039b0088296b70469246f8d4dc76459c1a71b540dcf53a75e2f1e456b5c12967796fdbbe1c04a952ccca12b79c90b66362eb07e2024a267f0cfa095f706afab352397475aee8a13cf02e74f4049c4844119259930440f845515a81925e73c1befcbe0e57169427de22c90a95cc4c032c591e2b466ea9026b33fb845b923dfbc31d010001	\\x485de0f00a52eedb9f5ab0c35a7c8cd881c64153e86d41b429c760be2f9e08de1bbbec7b42718ab7817d4df11cefc81f3243f512de4e1dfe1345ec958d39d702	1674162607000000	1674767407000000	1737839407000000	1832447407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x5cabd617d7eaabff9395b2fefddd9678af52193a84c2d2d2dbacfc96623c08d8f0321991456d2568897d41cf65d1b9ad4238588d7a103388a94f4b18764156ad	1	0	\\x000000010000000000800003f1828631e698990ce1972681bf889c27acd57d6bdb97165f4fd3442b20be9650171caee22d5e714b0f484ab98b5791898d12f4c0d7f7138aec072d70c4f13348425cffb733b0465a95af1afd78ce8926847913cbd4cba39e836ba82047c0f0f6b54ebc1320ae459ae7de583c2a7f518f9c92a7cc75f4484dcfd7cd43a4abadff010001	\\x82961297564bea013f4af07bd51d0b04e49ba414f671f8deeea4ffcba81aa7f289f25f03ee71e82c9812ec789a80fe3f4b8fb780e482e0f17d633256efb2560c	1665095107000000	1665699907000000	1728771907000000	1823379907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x5dd7afc308f90ab3add4609308b0eba4757865c2ab5d705ad7b674ff8a088f3881c217fb1474c9a56721933af83f0941a26aab706e7611860a17a964e9a0d68c	1	0	\\x000000010000000000800003e48b8b8298db6e8092322bfdebcb25522a09138c570467ef47b776e276398668be079c4fea1c537c00a8424451d6d6c6522140494087e5106673c044aabda9ccfe13862eafcaf63c5fa31656b9a2ade7b55e0b97f0e3035fc918323c55e7b80b1394e421f76ad331f1636e762d629b28888e624cdec66cb062c7e583bed6ec25010001	\\x058eedc0967acc6c99aa57f13200522a3184814e73e5b9024657c4d145e5a439ee1ed2be86314b51d1ca19d99282029151e8d731eb8ab8058e65008a6bb7f10c	1648773607000000	1649378407000000	1712450407000000	1807058407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x5f5788dc21100f26fb680b0c01c7c70b837fb9185653adfcca2994937941daf2ae163d6f1182fba0675cf62487d1d26646c7122d79ffdd5bb0c329dded2639ae	1	0	\\x000000010000000000800003ed6020cd0fb4de7fce766058c2e0777f15c2c72c62a7c25dbba0aecd36754415a6a778d6a6337f473aee44124f5e1aa3021b43e68d6ef11c81b3c41512ce5ad8b4c3e734d739810a27509fdd7dc60c70a2fb720763df7f0d182abd33d386c98c4a3d9054548d72e376ece028e44477200582192e19aff807eca4631b0908d09f010001	\\xf8348174e47ccb1f5cff66829e87bb953a18f98169c91b5878099da344a176eefddd70f95543bb2debe1174f6f8abf6d65b9a1ac8ebccd3cd192d4c15ccbf804	1671140107000000	1671744907000000	1734816907000000	1829424907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x60ff32173ccbd0ae46e0c5177d85f580a7670a10588d009eb60b9c2f67b01968fbf707df66405ae9f23588eb5f61eb851e99ea91dc621bbfa206413a64f3bbc0	1	0	\\x000000010000000000800003aaccd48b1fb4c33eaaabd4ad5cdac9bbe13f893ca019dd97a277612768c129d7044afd007bf020637485d4540731cb99e7141950dffd8dce8fcaf8b3075814e24452d85f242ae87da4a3b9f6e57c31add705281fc900b8fedb9a83487187c3aa53a8936f7f7ad26e7c19e5c974f907d7a0743c0a7464e23048fc9d068219d589010001	\\xd5c9519239bafe28b6d3b42e3f0ba3b75a6c82f563b5cedc5c2f025cdede80e88f2bfad2a3b5eba81d26f34d93086fa31e15099aac25d287269bc8a1d0f2a80a	1670535607000000	1671140407000000	1734212407000000	1828820407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
373	\\x61af5a05da6fe35784b54c9a930464e9be78f61682c0605a54ca01122d970628e0862d778c229684356246e6317cd120871ca3119cf9a5823045285e54244d3d	1	0	\\x000000010000000000800003f9e239dbecb566ad50fea5c46a9d810fb375b2f807233a9c5e61057fb7cbd88eebf8aa94e39d9df617046a8c3b0629b02b80e7d805901865cfbbc19a50609becb0f52308db07732b2b68f1eeac2b22681c43f8fb17cf0fbd533cb52ab1a66f28a6f3b411055933af972b67db697358d93f5e730101b61ef67c50b8036b385a91010001	\\xd4af05296b05355d9842e2962e23cad308bdd5650a00fff7f2a32553c7a6b7a0900bcfaec34a115f0164625ef9446008660f4a66f6bda30515d1acd866e7450e	1677185107000000	1677789907000000	1740861907000000	1835469907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
374	\\x6233cb29aa23a03b2aefd867c7b0c2dd2a18207b6a0a3e7e1cc09923e66eaac556312b40605745861bf120b76b0515bd3537779a56bafd92467bf75cb26721f8	1	0	\\x000000010000000000800003c0eccc8f8025374d9ddd265b53bc740aaa0e9fe72aa817efc700a7deebe09a0a4c9b5cdb8f9759a9a0e5d822e13d3f1f3b820949809f17cd472b56f687a57ec15459fe2af3c8ea649687813e85fb6d6c9654543a40bdabf296c9d67cb7e6940fae0fe061a54a719edd5e73ca36062d61a60ac311f11b5b6999e80ce459127aa9010001	\\x4c6ed71c9ecc6107f5952a6544db86aa40e1601f6b5d775003cbc0bc20ec987a56ea0de5db8b162246bf8bce70daa30c7b354d65bce73ad29d38e1d753ccf304	1675371607000000	1675976407000000	1739048407000000	1833656407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
375	\\x64075d217c7af075e27a37d189488b400fdf13653718e92bb45eff83cf736edd61ba42a69514cfa920ce9f0ceae67cb14a92ee684dd221a5ffcc2902eee6d8b2	1	0	\\x000000010000000000800003c8fe6c347354029d13c1a8ecc92f573ef1e3137ec0ed6f87618bde62fc6b7f0b45938ceadd197720db14b983dfded9a8ff5ad93af07d90a7eb8edbe785c1cd3e78aef7e9d7d24a63423f11e7f927ceabff0811ad8b17cfb0f48e56ebd5e8591eb210636491c8b72d17639c848bc6bff74309452261d16a9134658aa08092e54f010001	\\x2d279709a42a724b01671a18b616e2107dfbb55571038d2d14efe6b7e3d6d3773813f58cb15f862352db5b0441f315cbe8887e86a6382e177792919b64622709	1678998607000000	1679603407000000	1742675407000000	1837283407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x660b5a61dd90284612f0c33d20ea9f07d7495098e96cdb3b523b7254b81f7704852cc066d40ae47fbb5f0d466223ee741200da6fb4615589507517561f42bc23	1	0	\\x000000010000000000800003f672c13213d057b5e20973ab742279e967db9b1df58c05d5baffc9abca1e2a35a61a90da599060e5c6aac35b03256aab2b46e109f9834c362d68c5b9e9365ab8070430f7045b03790d8fd5ca0bf74190a3d65edd5314f37c7e0933670080a95aeecba02b391e9b34c2a17c811fa37e641b07815421aec432821b46d4d17c3961010001	\\xf494d478b749ec36dbf83183d2fb6dcc91f9fb81db067e5e3d0c2c8791525d62c1780747ed4db5d91880a271d026f41bf2929155ebb11ec4b4301eab40f8280b	1660863607000000	1661468407000000	1724540407000000	1819148407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
377	\\x67afb98422f07728f74019dfb314d1a07422206db5bc5745c448bbb4037d26048acb1e896d2815b4cefde65d8f3b249b33791ae5a5822088149e0e6c2c64cf08	1	0	\\x0000000100000000008000039ead9c4d037c4e11d5765e68e60a00a9bba2d5d70c42dbcc4198dcf6907d15ec546512e6972dc4447948122420f97e603487d527aed60b750d698731cd3a59a63e09d1e90f23c9f64da56f9f836395146b4af6febaaef93b2dc40272e0cb4b88c27e926ada0662691d289b27d2ef2d92317bc12c8456759332455ad7e7d6f961010001	\\x9610eefe7a59ca559f1cc2f95e9e647e6033ab1b4413b0036eec64e8a7cf2577b1dacb7e084bacb58fb3b6ab3f7eb2a95d084cd0be09dbdb71965e058c558407	1677185107000000	1677789907000000	1740861907000000	1835469907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
378	\\x699fecb364012f93088caa05660e9735145bc5f6860e6b7694cf572056c9407d42a47616674d5b0877a8f8d1c039b0689b01d3a3a0539a25a5b2ad7fd8cbee52	1	0	\\x000000010000000000800003d819b781a9fccd99f522a0fdf984d4702bf7f047b073237e128946c6f5eba086c8496de9da7d8fd85151fbdbc4e3c4530518b469a89df222750bdee9283ce99cc87eb70397375f77c9aab1f4f2395d7f307f2e7a152fd215da6b87fa4a67c4a969c488490671b064a42b05b71c10c1f5f9f79e2d78fdc6bdfe59311fa1e1a63d010001	\\xa798dcf3c771111cadfeab8d346932e594100e564cf1754eacd6cde0f914a47a4683672bfc0b06503f0b63cf8b60df7e94b3c2be70df7e5b12fa6d3b9a025506	1656027607000000	1656632407000000	1719704407000000	1814312407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
379	\\x6babdea5c78dbd39244c4930ab25eee15549a51bd66dece562e6c344898e448ea0cb5c9b0c45880eb2cc6c66d8f73afb4345c86907fd205ac1dbbc5641ce9976	1	0	\\x000000010000000000800003b74fc3e8451eebac69b098f32dbd60792d8700ec2fda986548384691a77e7418fd0c84780527d9f51c9e799e9c799c3ae311d1792adfe715e8667b7fbda55846254cb68b80473de24cbda7d3d29864ca3dd66966da01f30415e15cb46c6b9fcb50462ca3304d21dcabd2291985b83b8440bd7f96cb687b806d7c942fddecc431010001	\\xb359a9e7e935e4e653f25e7f7edfab396fa2fcccffe7fdc6f3b019b2edfb893952631f9f9ee46cd1a3879b8d6ef6a76896fa079611d9ad91837b34205da1eb01	1649378107000000	1649982907000000	1713054907000000	1807662907000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
380	\\x6d8775e82808077c24bb6862d2347143dabf19c4ed51ad51b44bcca5f63e6aa40e3ab0852860fcfe52a55e9df76f645f3fae1c23ccf03976733fda10bc300376	1	0	\\x000000010000000000800003c463180cd73e60a733b000c7fa22e8b073261747aacbb813dbbdc4fb9c3ea31efa8d246b141128890f60740de6d9d9ab34336e41ba98e19755f596b94d8a5a53f33c6e2bbba29c8390757ddfc7aaeced763eb7c9aef6654db5ab157744016fbbf1dcdbaa53c27960bfbaf78cac7cfe1d7d7288702309b244b8a41d86f0a00fd3010001	\\x342d5ff1a84da1efe3964910f40028d9332912946f9e95a6b9247a07b1d4caa4ef7c841ea4a7a0355ae0e2a35ad4f9f36a4144c82aa833a66bafce01c0000f03	1662072607000000	1662677407000000	1725749407000000	1820357407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x78230865f3dea4345a432090f84134f37bffa3a75855378a1a1c5b0a5a9c448a0651d2da7846c5da8cc9a3499d5d2ddd3418da4acf50facfc9f815b3d3cdecd8	1	0	\\x000000010000000000800003b73a1368ccccea16e6f23ae35cb87cd3289a1ed526ca4db9a2527f583cb876f4b7e4745f8b4cba01f67e787ee1da5ce533f0dbcda44c0bdc1958d1040e7ba1ef65600d98b20a1591227d422d3e9df9b3559482e11ecda54e4134e7e0b0b429cb002cde7eedbe593b4a0b1384e6291406e185350324b2cb97cc428a1fe07ac9cd010001	\\x68a46bb75790a5a98c5e88706b51f12cbfd24a94654a20d4f58f4cb1263ec5e22885211c31ab760feb9125b4e3a62d988f495a5032d0e6a0ac1c3ebb1368d90c	1671140107000000	1671744907000000	1734816907000000	1829424907000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
382	\\x7b3f4cdf339ac122dce54ed83f6267f09a7b2cb302cd2f1b851652f2492a71f2d7504347667d7b56f9400ea5d0386231465a61f61a2056167f300c02ee0f0371	1	0	\\x000000010000000000800003a54a1cf0cfa2eb722cde9a0807fa4f8656508fd5ff3cb0f20365488ec76147e73d580d9844fbe6e3ee355d683c9c39c3cff73f1b58e1e1e31091a948a354252fdda43e8d6d2062662dfa678a87f6dcc7fc7bb7994156340a1c15dbf8393793c1fc39e6f9e66f99632926e4456f966cddfc3714165226ba601c2b7877d37d5b25010001	\\x438d72a856f428de7af2dd5a543fa24c14690ff2a78a1b643365a5e1e947a9e7a17f38eebcd537d846f89e1f5b4331f15b3fe1df6acc05cce21e941d2d0f0200	1652400607000000	1653005407000000	1716077407000000	1810685407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
383	\\x7e5b640f674bbd353120967667055f5dcd31064b1e14086510f7f7932e3c28f2176a9d9e38987bc73974f02f44231dd81e276760ea8e237dbaaedad643d3425d	1	0	\\x00000001000000000080000397b648596246174ac0c045f2f5da06411a4813e12a5d51e3952026460761c93ace04b44f0f4cd0a668d22bd3b7af4672f296b8d6881047ab1a28f2b6ed0f3d3350454212730dcca27000d1c9d234fb774e51c6a1f08dd3348e3fc6efbf1a1745034a6ed5e4ba87f962de333fd0ee81f55c6e3da0d72e5289f52804d22c66bd2f010001	\\xccd9a2d938da45d089a83bc602dda03c1f8ea3a2ee46bd784ecf14f2e175c740a0b72d9bbde865804f0c390e3c041d14a0b5ecc696b3c2eed77f8c9d65f1f70c	1653005107000000	1653609907000000	1716681907000000	1811289907000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
384	\\x7f4bedeefa8fc58a82eaeea4b3c3500f1866a56b727b3b6a14daa47f53a7923edaa643638c6cc7c74ffc8f49d987b903021ccfcba5cbe83726027e91b4f30ebf	1	0	\\x000000010000000000800003b311beb78e6305ee4d1d3e67b3c3b55c5bb0728c0725a18012d6c976b6d701002b26ee9b2f0ef4e00dc1b3dbea569bcfb404b3debee92ca35dade103cfa61e8e2f05aa7c0e318a52da5d3eec49cfe98f15ef6236fa135ce7cb468798832eae76536b2b871d0eaf8a907908b40177cd50a764e8b86d754d621f8c6cbec875aa51010001	\\x90ddbdf7d6b3c4d8d5b0152127a9c5b82072fc759c32f94c02a15919e81d1633c26247412737133365418b49664fa209eb9994abdf7a59348a64bc974b9ac309	1665699607000000	1666304407000000	1729376407000000	1823984407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
385	\\x80434febddb57e3737a99c29acf455e07552523309588c1768517c95cac3b10a912aaa2daa1e488ea629e12b2d20de64de7b3572e80c08439364c7fd566de794	1	0	\\x000000010000000000800003e19c1c77bf33bb1d5c6217e2bc5a3a0e7518fdca5a3d345c42ccdebfe44229a28cf2ce4f7ce549d4dd55890238d735f9c0ff02b7be09270ed4433db9003e30d7e83c815d4baf9089c41219e41926507cfd760d67fd606d83b4b5e639ffd2161173dba54b7b3c8c304e0e038cde33a88b843d7c618f5c5f6d9552e0a7ca936869010001	\\xe640579c9c9199f645818bd71a15166a6aa7baedc346ac1b428cbda1ccfb8f21fcb7127b8cf16ec34855aa10358b2e31154240f8ed721992f089af042f1b9a0d	1678394107000000	1678998907000000	1742070907000000	1836678907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\x8693e9be7f9945a176bdc4a59243a2e72557b110340729a0fcb27929f459b4d292afcdc32f2b7d1c7157003f9234d332bd4ba0376e903b0c92b7cea04b202e58	1	0	\\x000000010000000000800003b9648c93e5075b4a047a1bc384defe289e58e945cfce5b79f4f42c26df40dfeb6d38d7b0dfe34533f2ea8e5b347037f7c4e2245652e4c9bbac397924d022a792112697f543a4a2404ffa16f58d2c64c4ab0904d2ef4a368a85c994eb68fad2cb4ea95570a2bd0fb27c4e162b857c1d38b115dbc1f3da891ce8919d36417e257d010001	\\xc085303aed638c07e75e97f57e4c25995501bdeedd6819ff201b54c2ffcc0ddc57e9917cf5ff09c5372de16f4a753bfaadd9b63bf0dbe6381a0fd1d439b1c00d	1672349107000000	1672953907000000	1736025907000000	1830633907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\x88cb7c189274552c7f26ffe3329aa64c92dc379c83557611a4a07a976cd32f5fa06ec916b1326cd52a6b3d91d7cb4a2a3b481d0170807f33780514a7ac9f08b7	1	0	\\x000000010000000000800003c0b0fe2b5f5fb15e1ba6a1bfef1131c24665f3a49195a9b2052000523c53b68a264c264b5b7635718bd8f72160de580d9d11f8d50ea3c7ac8b2092ca46861d48feaefb7b568a5eae4adea7de89990491de17f1703d9bf2b8c18c0a56ecbf454b0cf38902403173c760ecb9ec31bdf2b88f8482da8e73549b31e3e093c3a34ff5010001	\\xfa87431fbd846653695063bad25bae27806b58f54b97920624583069a8d30aa796260735cf58ec535ee69aa110a550e4b3e594d3ea52e0c07fc54871fb43270b	1677789607000000	1678394407000000	1741466407000000	1836074407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\x895700bb427d479295982766b190b3fa88cb7e3e121c00c565a24fd59304b73e46425943bb4cfe3394fb917af728c6b7a3f724beca4d65fe58a907ea7a0fa48a	1	0	\\x000000010000000000800003f359da11fc94734a8ef86715c857328b01518b208cdde2f0a369c88edf8da6724ba21c05aa14cb094bf9dde16021202e2f2f5537252a48e70f702a59edb03e899a5665461a4550f79a76e03a7866bca0a378ea34c485a8d5dee9eddfc89c9f4cbf7b1d17c6a6ec143644a1ffb8197242892e016e0474d0ea4e30bed497837cc9010001	\\x925e0d5a97072c23bf32a6a4759b30123d41b9a74e6b8b16a747454110c83ad3ca59687ac921e2d1935da24df7acc9a43ad6ddc3fc6193debbd8f1b715b07b04	1658445607000000	1659050407000000	1722122407000000	1816730407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
389	\\x8abfdfdee32e953c47101eb36d02254684f9db618259034537a4bcbffea2ab044e6568f58ab17cccc8d7217449c6d559b92dd726944321d4741e3301bcfbf9f9	1	0	\\x000000010000000000800003bf1e78310f7c8c0bc7e84b2c0fedf5c95ebadd786c2ad9ccc2219a1136608968959502a0095d594ac767280bd0727456af7c6e900e994871c1d8e917ecbbc37543332f4a0910fa9c468b1bacca1a64f5a743f2ac921d6dbd78829c473342d562dd4aa030a7838b131b9142a31c91df8ad5d718b9182b5334f3f8446d0ceffcb1010001	\\x55920aa7f94f584cf32b6eedfadeda8f56c5436f1ea9bee16fd1d302774c9b3f0e7c3580b27c22994711df74ee70ef8476f5e8631d3e998233f6fbb5a53e8103	1648169107000000	1648773907000000	1711845907000000	1806453907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\x8a2feb25acb98c844da8858bf1e7c62e2f0e28485a46337b8fc9c628467d031690dcafe5ab2ead4f6af1e28cd7a48f5d8ebade77bf4ca8232c401a469c742461	1	0	\\x000000010000000000800003e42c06b662b12b0b028aebd58b2e0b5493cd8896095af44d1e6ea4db9db98f5860b2e032381a3e11c3500d3d192af30f77e4bffb63598c3fa464e10214a3e886ce8d7aa381055469766287b2216fb9bac873bc56b970dcb2a2f857690204a71b949db7122ebd59fc11c238d6a85ce92500a12eff32994ed2395902610f6393a3010001	\\x3b805ddcf9b9f15ed04bb9868ac08cf1be7840b29bd47b0b67a2434f4e76e140b6a2873cabfd5481c4b646a9d81f66a8478f96442c5c06ba1f04db2b4546bb0c	1664490607000000	1665095407000000	1728167407000000	1822775407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
391	\\x8dabe8c01fb2399a7acf97a2e1e6debb89f5c83b8f154b0f554d46fb15442332c364befbd6525c55f9629c393268ae3eb0a60a283483fbf35184d635de148cd4	1	0	\\x000000010000000000800003c39dbe3db96ed623c05f181c618c26e9eb2f21bb411b5dadaea5b192e70b88c2b366c4093ecf195e8088c4e9694560cf28af1b54b51777ac20fd0d91d58a17e3c3f3e0b7902db987e9dbf10ba5d2939d05673b37fcbe5d9edd616a1e8a9aa65fd11e59696aebbf84d0989d40cf50bb756de4df1fa6c2ca6d92a3f029e2c02bd3010001	\\x0b3d185d284431e9c209bf2d750043684f401b8592d23ba7523933e81bbcf5a9248951fd5306d417e82a9f87e31156822a3e6fcdb05ae0b6b9bbada18ac9840a	1666304107000000	1666908907000000	1729980907000000	1824588907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\x8d6757ee9f5826736f64ee109ba0a41833a84f4bf2c754b9bf6445b55b8578d5970afa4f823c60ecf430db0bfd2c44627a8f9c93865b21ba4d090c0430a03de1	1	0	\\x000000010000000000800003b0e33068b1b86a4d82a132b5d72d1f200989f548476f8bbb2e1e50ee7f56d76cb3aa92876b2cf991298371fe6a3097a7f7577f82d56e73f7fcd09c25d8a9ca4ef1c044b3e9d5a0c45810bc1db902bab15f35fe8df39ac1deb45988e8a73733bca385c3d2f971e9866a1b0893b6177e6fed86e3df4fa3aadb0f6b57e93a93d059010001	\\x771433151b90a9dc1695850a9a3cabf8488acde759b19f412f3186100212e26edc179f9436237de377e9cf80c15aabeb7a0b08618082594517b441138d85b80b	1668117607000000	1668722407000000	1731794407000000	1826402407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\x925bf9275d807a014fe1c297ee7d1bb06593b341822297e4655a26f5e1578d659f558c71ae008f46c3406d8e6b0a49dab55ce769adb43c93edc08e1901581705	1	0	\\x000000010000000000800003ae3801bc67e625e713279261120bd8b99a4f16d2c540349baf3d141668e40fb466794d0c733c0c261b802f98d008e5f23bdfd778e9417a87489e71975933bd2ab85e6f0d515ee29b86c3a08cf1ed8b6d21e2807f948e2b042b1a5e0ab1a89b83cd08f3ce83f9059cc87a5f136d32297074bfd5a3db453ec03ebbbecd9317b9ff010001	\\x82acce965b801e192033aafd17cd666b99e3f98fb3f4a3104da7430ea655412830700427891df8357c41ba71441aeac4414a6d333b5cad8ab09de0e990768c06	1677789607000000	1678394407000000	1741466407000000	1836074407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\x9487a4cd26d8eda8e5ae3e724b747bb1165b44943d41ad2da38a91a28ccfb57bd4f9828f354c5f6a3373e2fef47b8800f4f663c143ad9691c17b918f1d314e22	1	0	\\x000000010000000000800003ccb2facc26fc3cba3a5b15b97ea220963e7cbda5e1de5a025b77183a89fb73d3dbe1838277b4d13568c7ad6e24ce6491a56c60393f40c524e26291e21beabdcb62ecb68e917b5065340455bdfd4c38f79a33e05d72356a99a74a7ff64843298bcaf65632b2da5ab48e7173f5978cd7c71943c5b2c8aca1419b0789e914120345010001	\\x06b856c73ef2b9bcc1dca885c58e4440c87fee8c1973e519208c859c5bc42b951a2ee1bbc15deb7b6c0639e18854ebd254be402128ca20d812915ae012da9c05	1649982607000000	1650587407000000	1713659407000000	1808267407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
395	\\x99efd84ee011adf4b16e7ee36e4c7dd32b46556d3bbe643bcaf628faab52e25040b792d009c689cfaf07366cef71b85ab77b8768bda38cfa0d5f6e737a105dce	1	0	\\x000000010000000000800003a6d93d6d20a4847e5545378044ee7288406859076f3811beeef120f2e544de4ccc73aab1a0feb3a0d3fbbf4591440ef5206dc8f241e57e416fdc9663ff4689438d5ca2b9170c6929266eb3883ffeb21e52679ac03422f80c3b7d627f77307764a7963e1f10ff7aa2491ef7115dfa03cf69a055d948dfbf123e6845973d7779ab010001	\\x3e3f0702f9fc33b104969970283c3d09d1050b6c9cfd3a19401c751673635efc4735b9cd9798cc056c9303ff10b82fa410e827fbba0d821c4d8fe7636a275004	1650587107000000	1651191907000000	1714263907000000	1808871907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
396	\\x99fb59bfbd1e95b40bbccd87c837b8bfebba3380c5a309842d686a4e662ecc35f5eb2c9b8e30146794397e13ef025fc4dc274439207cfa369536fe5a73fb8b6e	1	0	\\x000000010000000000800003b68f14f42d7756e1aef54e255dbec8fc8efc5f90eeccdfcc69c4b32f3d86e8f41b1434924fd733971be979112054b98d48a144ac6657f1c6b2571ef61f41fd830a5ba000eec985d125ccd4f0f192e7c7dc18db6f0191d69d78f2386c5e3880c7d8718e4a5eb8e6e9a3c6b4d69b5143e407302c90905f6d0d7550295e09cfbc17010001	\\x3ef9a84b6dca20ed93bb7c15018f590dfa300e24d274ecd0c17ebcca57271950af2be94d7b9aa8fd109dd26df4744994db36818260692b2c8a1bf871a58ce709	1648169107000000	1648773907000000	1711845907000000	1806453907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
397	\\x9b8fb111fc764cfe3a4b5305ab7a6e4dc73c4ac1a05e92ffee7e99f1f26424106b8d1c6541f1e207f85c72120e456e166fa9e092fe98b9c6ab5e77946bee1074	1	0	\\x000000010000000000800003a111cd6c18e81d8c5aab533808bcd3beda324a26dad75e8e2ca908276ab0470e674d5c503a4615608ad46c5a605ee228ae0c6da1ebff616927987768ce7a3de7b30197d61de2d92335c4ad1213b32ba63043cb506508b07ca6fcae131c578c2cab1768c681f02b55b1da93c0f35a4371427ea0f3ae8179a608150d24e9d21c5b010001	\\x2437bc84d0ac7d8760e68e0b34bd5a3c4597a7c2b61e7ea0f3abb65710ebec73c445a8c59481ae1a8ba89f7232f69f0c31201e0f54f88842564fb87a5ab1f90c	1665095107000000	1665699907000000	1728771907000000	1823379907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
398	\\x9fcf76194995b666629d4e3409b9ef1dc258b0ecba8fed284d77dd30302cee3b5f66b7754ec32f788bf7c25f8455222adefaa729795890de18d448f86b0d1abc	1	0	\\x000000010000000000800003b173dc51a38d34ea0066216e90ff18a1292573d28833185ed8edef1e5021f06c56ad5b903c83d009cb8e8e70e051b7df17415cb76320e4d19c59ed09fa2fdfd2082c030c6d3b4998511daf76dea7c4d2a7a4898a88ed57d463161bbb9960e6d3696e858de6e2ecf15969c584ea92536236e7cc3589b92d5e34be9d87aea3d21f010001	\\x3a27defe11a7befdabe14abb2a174c6e91ab4312b2d904e257038ce238a7255e573cc52764e959703b2a9c3a5c38f7f34ac0d21421486ee7c073254f3ee24f04	1659654607000000	1660259407000000	1723331407000000	1817939407000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
399	\\xa16b5c0c5e1a359bd3af7c6493b87f6269fd0fc98da4692fbb64b8b7f79fb4a3e3581f2559d87b7c3688b24e8df185f7318aab26d4bb6094f226e6b33f1898a1	1	0	\\x000000010000000000800003c99380c349c8d6d08a7e15c5768fd536f49018d1e7b207448dd550e6b4998928dc21107fb21e65f52a5bcc928fa3627a010fc845114c98c10f0f0bba7de38ce090f560519577769d34703f8b091be2f9a8b1e5b0bc189f9d90134266f5902af4da4ce94b2733910c1846fb7c16b1855a12c2c03c436bcdd8f7d890b7c74a9d61010001	\\x6bbc004b3bfccf98ca089cb503c4abcc1aa202545f06700da5aebd389e69ba254524f38c4cf31a426a9b27868b38bedcab5380c931b4c597f98b97f017aac504	1675976107000000	1676580907000000	1739652907000000	1834260907000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
400	\\xa28768376889cfe7d561883bc11182d6da1a98b94a9cb2d1eb812065f92ffaa0127f5ac6f528f22381dd9c2f9fa18b7b4bf18c87217f6f24efc3ddcaefba0eac	1	0	\\x000000010000000000800003a07af8a23ac4acab3f89cd7c74e83e105e70afa8783dcf5eeffb43a6f94ad50304de5877bf2ebfff5139577040fceecb3bb878f1812efbb79de730a1fb81e5590d908b1e8f78127d98fc8b8f0b7b0a361b23d69eb7a91e36afa6e902cb1437cae4b0b589e00b151f1f95d1c32d213fddd0fc51b73d4239dcd4bca0e9bf866791010001	\\xb710839a161b565a149530c5efc24a6245477a40d445401a5e5b46a262398d262a0fab605773d551c9531d307b6ac7ea816c26aadc8443d21d73f3af3676e702	1663281607000000	1663886407000000	1726958407000000	1821566407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xa2139d0462851a260ebb66353c9990c652795a79524e7384d9021ccaac51599e195b732bfab424d96cd7fb9897f49dfb6b404696f7060b3fa84b9889b042edf6	1	0	\\x000000010000000000800003c3ddfc407bc6d66679c005a5595b1fc443e034bf0f7187c62dead353906479625cbe2941b4d94e2c540bbd16add787ffba49177bc7cd33b41d8cfbd8454908418e646c032773aef3d982ea3a9b444f8519b632de16be90b828c697f8b7dad1196ea73576d0590aedf86cea006406bcfc7d1243e76cefb561d3d6069e5360a45b010001	\\x14a7aaa6238fc1ae45aa1b126e7aec0020788d4a457e75a32b1fa810653816f2dc44ae26b220bb36395fbbe6bf4ab95562ef475e9f116e618f4a96d3dd8f6806	1658445607000000	1659050407000000	1722122407000000	1816730407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xaddb0c0e2e8158785335ab26cc2b081a46337b11efd3a82c5c69f14c672bcac524e9f8365f18ffa6b7ca79a55051241bcb56b3ed663239a2511ec5e9f996b12f	1	0	\\x000000010000000000800003f2854e01b12b8825e39860953830117f30fda0d2f661bd971fa11f77e455ef24b6cf768ddb71787d6b1e7b96e57e0d331b74a817839999ba69eaca998c97523a153851ab564714b1898feb6cb07b23b33ad6cbff3149e7ccaa98aa8ca7df42ed981baa1de816cfa3df4d245740588b30d92642ff9ddbd64ce214b46a7d62701d010001	\\x57b4963c3d7b0ccf5a7b8978446a7f105cd9b4af20301ea60ad66cc0c4578ea669a3ceaad72bf29fecc5b41a419796a186d54d319578cb7671ae69ca02caa406	1651191607000000	1651796407000000	1714868407000000	1809476407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xb1933080b9d2f8a65ddfb26c9e5130efc656c647c9cdce45dcaf5dfc2f94a6841f62fcff012d28594cb89fb6bac12886133cc22097d8e5196c33a3d84776f9eb	1	0	\\x000000010000000000800003d9fbf72737cdf9cf443cc88c5da8584e8906cf37ec6ece35625b4f70bf384c19fbbce5fed5451bc377fec2653ea0ed3f5ab3ae92334a55b8cc7ff82d19f24dca840e9534923d307ce485e01a50cdcf736c5e637b55bf367a54f66c4c959826a1b4fc11740aba530a772cfe4e6bbb6600ea7df3549d1562b46b1165bb4a8973a5010001	\\xb2a2b8d94dbcbf158f982437800a87e4d700732f256c14e6f08fbae180e01f7d6adb1afcc5b7aade6f931bf6f7f2a60f7c8118829ecfae92500b0e1629541705	1663281607000000	1663886407000000	1726958407000000	1821566407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xb13bff355983e7567ff98eb2347c8e5485a0fcae711ad845bd6f1f0678cfeafab40ee5ac3f35b50f1ef417bcf5633f666ff1b726280c365ed4bf66d430237ecd	1	0	\\x000000010000000000800003ae68317968ab0f745f0cf14861c3c54f3c76eae4aaf56a1733a7ada8b569d98197c78b4d4ff3e09e093c37ba086fca3d663535bf35b9b317639c48b848be8a224cb844da0f4166cadd115b0492a59c646fd8892ff7c68651d1c06052bcee78494f0da6436423b3c635ca595b79b3d9b642730aa04f158050e2466820116efed5010001	\\x3486d89276b72082f79e9e51915475fbb9138a88030316474fb9d546f842497fe8ceea94048a4a0f8c20b6a612624055940a5de5f709f21491bd331d7ab7300d	1676580607000000	1677185407000000	1740257407000000	1834865407000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
405	\\xb9cbf209205eb71b5829fee7709440a6b5dec2e213536228584653c67c86d2405ee020223c8c80c40590a0a0a036b4b7adb372ed92ddadbba8106cbd632645ce	1	0	\\x000000010000000000800003dc39834ef351324902e0e2ebbd75646559c205b61ca53de74f586957c7e1e8446555604c3f581ef25080e6cae8041177c0d91ccc69a875e9ed220d6f0dd3376914c2636b3b6570359d7440d9cb5648cce22d55d10239737a74a0f1d8a16fd9e47587b0571dffda1bdee945cf9eeb54ac08a44155cf089ad03e4b1796429aef63010001	\\xa78c1a42d87b9cfbccef3d4eada60235d3e8d0befa13c1dd63227b4cbf4d94003b2739be0c677f97b6f0c7b2117a2f12f926c6ed36fd5dc69379ed3dda22c001	1673558107000000	1674162907000000	1737234907000000	1831842907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xb97f4edabd8bcea04feb5499573cb585967b76b3502d8c3b55e9342aad10df13226c5b52dfb025d11026a75e993be3615cf2c4411a0daff6a841b951d76f1a54	1	0	\\x000000010000000000800003d10775464e39f295622170675c22ac6e822a6d7b177ff9ca3e5e6b0626785abe58ec375b22d24899a0997ca1823806e00fc14f0391922c8ff63819c6fbad3660e291d5caaa0a4e02795da7ba77ea302e6f921f6f57ba30b932c405af540d6a68d3dfe6b5275d838241d4363184ad32fac20b4904292d798dfa775996c562b969010001	\\x978a8ce88c7e925f594aa3fdbd310c809f0b0cba6aae2b45e1ea5f35088474b853dae4c756289121e82099d2b654e02c49377cd916375680f647a30c0cce0203	1664490607000000	1665095407000000	1728167407000000	1822775407000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
407	\\xbd4fda4c52f5c3eefe86bcc25aa80536d2e7196420b9cfbbe7e3aeea1553a54dd03c7ae3f0c78992e0548e55eda79e1e0ec929dd8a75e25c9f87e76a6b66d8fe	1	0	\\x000000010000000000800003b77bd4d0ac4cc28d2286d5b3d3fdda65ea18799ff611d242daf0df371ee490deea1c8f5462833aa56a9c4a374d91afe86dfe80d77049beefbc01b2c7b06ae64cebe923c9038f6693d9794d35f3112ce0562d332fa183ec91ad5198107e77f1299bf8e1ea81a27dac21daa9ffd0c20e4d1a031547b0c61933c9f3d7ace6e116ef010001	\\x3c57018c070d5a6d28e3a617e6aaa10937367100639a27d0c70011accd74f83143643b2e1d9c92fc40902b21bbbea4d472109f430159db9390d3478b98cadb0b	1661468107000000	1662072907000000	1725144907000000	1819752907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xbfef68ff379a697f6a40c0542db786d06e970cba282dca655ee4bdc11e074c98bfaa6459ae2cd36aced47cb269d9da75c55bc97399ac9b2acc350396d3076731	1	0	\\x000000010000000000800003cb5de671353ee1ca9a055cc52d564fdc831b6843da9b3f49a23c6c10999f1f37c6342102756cccbc9b00a03b8c78cda9c25a43de41d0213280dc498d88b89ef88610d97ef8d5451123a7145a59c53baa3fcfd7a72e8a6faba67d6d940806ac2e0789b0add7200159f6bb66c36c2f7bbadb635d369ae6012adf9fd096b607c7d3010001	\\x72b9238a001fd625b3e6c00f1e33dba8b8d503f99fb50de9f41bdeaccb6a3de1ddd01b0e29cdd547274280edf21b73f43a5c9ae6dab9f92edd4db55911949e04	1651191607000000	1651796407000000	1714868407000000	1809476407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
409	\\xc86f4363fa7f0a12d842a7e77e971423b3f2b30fdaa0c436723ca92e5230baefac95e43147ef788aa16173c6e79c744637ca49dffae8c5e839f866fd7ba04085	1	0	\\x000000010000000000800003e64f13463b81f1d15effc761dec315ce1d8a98bf23754053ac4822dbb0a9daa35970d1141349bf71b506189ea97812cc34c288f0fecbb11ec39045067fc5b4eb2efe7f193d80a2f3962dbad2f3b4d357b0ae6758b40dc4cb140d07ba4214f425cb503e2f1c7da68f575fa4e149aeaac7d45c7a6938e355bdc8f5990aa6d3df95010001	\\x24708eea344c6597ed904425cbb4cf363b70d428eab323995495e2ebf758f56f21d80aa7200d01a0af3f90820365b6f5e7d92c22597dbdb1c7ee185316e07609	1649378107000000	1649982907000000	1713054907000000	1807662907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xc9176895d8f8ae83542a8458f81d6b675667c638a9ccc210e577aa6ea35d214d5badea4321a1658338a781e2b3d3df2b390ee8b8a3559b0c65f09c11a5a229ad	1	0	\\x000000010000000000800003cdde82393388c1f5912bfcb6e903f17f5ef2c8c27f905ab3d7ffb302e956333f47389c270ab70da55192be1ac86f3faa827a36d685eaea74285f508ace0cd9e1190f7f73e825d770266780ef87bc26dbc15ba8974d59fcf46c658f245f3dc074d18d4910e2397545eec1e94c20126791af16b6c9556700704f536eaa8012de73010001	\\x1a2af37a16d66fff944a20e80fdc88b3635e141a98118af4ad6df19195f3e3d4e1400bed2abf4ea609af8a85d17643b16908182344f9adb77c7bd2c1c0923409	1647564607000000	1648169407000000	1711241407000000	1805849407000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xccdf63b1bbc93af86f0f34cd8f8a90d2295e9f163839afeaeca86c69e293564c69716bd6b9f866dba03a45e71abb8864ca7d8dae20065b6909aa50bae4ca0845	1	0	\\x000000010000000000800003ac8d3972c87f31a4da061d25e9dd46ead4eb6754f96cd929906aea9415ef956ee37a28ba52d823214f3c1d406a11d1fb8cbbd5dc4c76a0307fae0db8041685e919edab8df7814555bd5542cea3ee477a7d36a63a143d27b1bbaed8a62a37a96df79f263626100c130a4b7bd30a83a96ef3a4675e96187bc294e110d967ef915b010001	\\xbaa244f0ad370958e8386471a07ac627721772adb5ff07d6a3c4452a665ef5dd3b86f38d7b084556364de498d3d48f22705d364ce9af0e270f1f828598884c0d	1656632107000000	1657236907000000	1720308907000000	1814916907000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xcd0b1743e0292032d0fa0c2b616487eb2dbf98a60abee3670986fe278b68d548edc01f633c5f49ad1ca33ddb8960d3b64165307230d79e752391f808d82c3ba6	1	0	\\x000000010000000000800003bbbf08ffc050f730e7219d3d96f2c3ba80d711776d76db2b36604472b108fdc5925682d30cbac9d73b193c50eac54f0337648478f4ec92f3677265a4a62a6c2d35028415c6ea0da2150ac513c98dc636d9bbfe4829127852344cf8c5a5e20c543e96d02c15f475747ca86b50691a3e295fea18b28f343e710972e13b161966e5010001	\\x056907576f53d65112b7c26c92ab18595ebc86b8dad881bac09da3f0020324397dbbc9b2f93afc03576f40e3458eec78fe9f713b8c2596bcefab4be46be8090d	1658445607000000	1659050407000000	1722122407000000	1816730407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
413	\\xd2db5e193ad7d6208ec0a54ad4ac0815e23bc52cc456a2e65dbd5afd0f53bea8b2af3b30dc9b059e7c442dfbf1a86745b1d6812b1b873a2ea0ca1b727a236221	1	0	\\x000000010000000000800003cbfc455a0f102c4f0f25d4df52d08bd73b25105550ff50a93fa56fd6b6477b94338584421a46eb7db154559db1a638079bc0a8be6a5a0bcb0519c3951a32535bb631d9fc780534c83b2a2bdc2b11f84e371ee1e5c41666630762de34a4026a7e43aac32e13c6079b18c0f9487eb06343ce6766cad270800793c1eb1b1503c081010001	\\x0d5480e8471c617c2180864aacbc44b772313fa95d1f9b96bce594431007f45df2789142d6b7192f1c76b755eeb98ffd3fe3de28419b1a440112e26de2c5e909	1649982607000000	1650587407000000	1713659407000000	1808267407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
414	\\xd33f26a19847f033aa720a156b3e32281098595ec525df4ca2d84ba75bfa46b74dc1beb9997be6cc7f3f47fcf039aea0fdf50974075639d17d0e6197d615921c	1	0	\\x000000010000000000800003b4bc459db7240491a6ed36ae581b10e0f82ee02842fe88b6b973c151c6325d74b7c1994bed8a16c76a165debae6a1eef1d6d2f51cfa83b3d1553a05b0bb4555b5565860536d8734ec0343a179aeba1d18e0c6ded4c0482834fa6e84f2785bf41c05828a255e150d6296ca5af7a54312e8b8b5c84fe643998de0ec2e4fae9d1e9010001	\\x9f70b2d68503f2f98f43bb8bd3f7de4f891c919055f1425f6cabd0b0e4aa6a14a292e90b0a463d9757b9a685eb77427054ad0470b9c40307b01a16fd8734680d	1662677107000000	1663281907000000	1726353907000000	1820961907000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
415	\\xd41319544baa5128d0b0780f3e0e8cf072fb6aa67c70cc1877d79dd0259e28140aba85951981feb48b53ab0ae82c0ea9bd4421c712f4ac0fa776012369e12083	1	0	\\x000000010000000000800003bfd71c3dac23557305b55df9cc58bba50ea217402060f5a496af8899ffefc5db6ae5f368c7e59f46ae2ca2a80abc5a5e88927e00d732441b2c9225af1cc7b566d932ce93f1942306f58e5b21200317c206a9fc72066593acfbe48fb5ef5a5ca2ebad742cdf02c2921fe099b912b840d362d6d3dc249401050944a614cfe94e53010001	\\x2adae3edb538abb8dec7297790e5bf6521abd3d91a0fa3d244d51c2f0990ab4a1251f06b11b15f79ea8722af046684f4a0b697459087846c53e6510d3ce34e04	1653609607000000	1654214407000000	1717286407000000	1811894407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xdb3ba9631007baa30846d50839dc2bb4384b3edccf3fc7a3d4654bc5221750a785e588669c6a62f8789694750b14855a09081ec321f0c9096ef7745e7eb0cbc2	1	0	\\x000000010000000000800003c0e330c4380cbffd633ecd2b587d87565d6365e6405b04c3145324bd2f6695257fc87e33fcff7988060574ea5d0c3baeeb6040fbf5dce647d345f495145c420dc94c8b9d89ea2df6b95e6740150f28b485e2da0216c1f7157c543dd06ca85d4602f6e2088fe6ea1abfe2617a34a2a3e3d63a9822628f570fec109a97f7cb62fb010001	\\x14a739114df2298d27dd50ec5df49788e1d54c8af05c5f33fa0bdf7a0dd02bca21ae85263544a7369a59da3cb1d441e5cca05ecec6f88429cd1d785252a2ca0a	1660863607000000	1661468407000000	1724540407000000	1819148407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
417	\\xe90bc08c1409e4f9401606351bd3082618cb0d7a0e279e6e3c82f9b2441c8631f82aac1c7001e9d86bc894557f009e020ca43569f879fa50d4789cef2c9e3a6c	1	0	\\x000000010000000000800003d64e0c08cc0961d95947bd642143a567e38f0ab9fadf55302487166f386d559f9ac7782ac20b114b2ba20c34eaef80ec6dae8cc94d1d5af85156c0c5390ee64fa2640c3db6cd7afa5fe1a4aa4475b4846b20fbef19822616f8bba8c627fc76ae41a56129093a3415aeab35f5c5c14ee94a8aaf468be25b556c0eddbb1f201b53010001	\\xfae77c8ea0168b74bded7a973d312aca3dd66558b5d2eef19ec9a1dd81bdf0f53882669d7ff9084100213156b1663bb94fcaf97c45c8f2b4e46a4d6b318b6e0f	1675976107000000	1676580907000000	1739652907000000	1834260907000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xe9933ecf408e414d0a66406ae06ab277ef4952ec9bdc14b459714b9142f073e7482f37200df6049139911517146c4f31a479c26834fd36d24312c5ad9d7c82d7	1	0	\\x000000010000000000800003b763499bb88610f1710fb097bb066a2c41aa667aebf5869484dae8b24da3d6144e4f51941e9b4d5e645b7afbd0f582e27ac4b96d02b8d60c23714ebf07b53eb3650a2b9f74abc14fbeb7328f420902cb22554a5463bf71d49cd9836b01b54f640c7f93372b3f433787763a5e8e8edc6f546462a616567a5db833971fec9a6b59010001	\\x25acadb6ecb9b4818b9f78212fec21352037860b9dcfc8473cd9047e0727edddc2a90f92acdb66dd812f224a28f2f025d9585d70442b153a7251625001f73d01	1663886107000000	1664490907000000	1727562907000000	1822170907000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xebf753ec28103f0d2baac8436f769361e641e2eb6ab73e3d8d9e5b16ea46dd955b01a6ebee38a4d235ed2fa2bd62c9f88bb34d77a594653eef504f0b7d35f432	1	0	\\x000000010000000000800003a4f757bd2f55574fb980770bd6cfe99a78512d75030919aec4e526994cad94499d8ee2c718ab8bf45b63b6a514d00e478b6756c886f311a49fc48a23f4d9ff6b115456454aa2b5bccccd13c05b30d5889a997b4d98785d8b1048b97387a64e88ebca655c46e6516cf20e8c256d911fdbaad0fb2fd80b626405f6c3db49c88f37010001	\\xe3e75dc5d786b470939bae74535e89458a55971e413ab9d871f0212871210e388cb21c88dfa347830eb1ea56bd3c8a523f63570b3a77f5de668b7454c1d01702	1670535607000000	1671140407000000	1734212407000000	1828820407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xee8facd2700dbac2acbd7c2eb7c33842500e16d60d2fbde9884701abc61608ebec049c3dab813a58eabd899ff9d6c097f29aa276aa144d84284ebf0ed56e75e6	1	0	\\x000000010000000000800003d9d0f4e381a4f63018a1a72d4329d424ab81a29b3dc138b23328b87ca4eda8ba7431ede1061ce1ae86d5ab13b728058a6f13fee6491fbb599729d893b65b59cdc523a10c57a0da5d893f37f0105c7af3a08ba22fb86635b6b8f4f5eebf5d092f7f25541981d69a85b8aeda571389b17960dac9dae065a20caa3caadcb6630bb7010001	\\x96a1969ad971cb2954e4be33d9c01910de0d5762106e5d819e53e0e88efc68043f001fa269132b9d10ddda31f8fe4ad1f1be965419327a282a77248e05f47206	1664490607000000	1665095407000000	1728167407000000	1822775407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xf18385a6fd29b668ea6eeff90f887c93df46cefb63ca04a16bc2210be1bdd783c7960d96704f9730fe01404c3dcf31eddf79ff8df360f070a8ada31649790da0	1	0	\\x000000010000000000800003c5136d2c40f1f0fb2d2205bbef4007a9255b9882fcb5ca79676ad8f89201f1b91e674bd2205a4b13cbc1c1934a120748fde1ce8516de7de3806b1768a488f8818a2e554fdf374fef9b06e2633b2597477564e2ae1cfc1aa6d369cf0572b3b2d19521d745294391dd852397f1ebd9e3406ba544eb06f197b2a93a8d4f7bd19f11010001	\\x86410335adb10df7f6c5d8c46448bc99fd918413d8cab8f603f1264f3101da0fbdcb0c3f86e364772256d36553a282bdf34d05ce789bb597ca032194fc234503	1660863607000000	1661468407000000	1724540407000000	1819148407000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xf22beaec4878f295cc99dac666556ff00a2497e0a7fcab40b5b8091694735a46e3438769ead12848cc3effcffa3c7b30c22e7786280611983774dc7faa18d250	1	0	\\x000000010000000000800003ad752453dc5b1f0a9d3efdb418910ad1a8253bc1fba75a1809e82cfda29d46724aac2f91a0ba8144c91e143fdb3c121030fd132b6f0cc403862ac86ee6ef7d83f1d22166c94c673fd011488c2c9c1b10101d73c8a5b610cb0af388688b260d6ca6005fe7c6b30557a97fb52a19d1e82caec63baa94b65525efcb92e11037c553010001	\\x48ff3ba5312699544b2df890d2b8a0e91ee3cadaf583ce39c8984ad20c68967b00991b045255dd3a8ae30fd8648db6e54a8f8654060ef05bff98db430568a30b	1663281607000000	1663886407000000	1726958407000000	1821566407000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
423	\\xf4a7ba173a6069b5c103e391a39f8af90d7b1b261bb8cec983341ca15e940b3892c9c8bc8055fb0182dfe7df3442d9d72e933fe1287111b21458e5a6048afcaa	1	0	\\x000000010000000000800003d19aaafa7a7b04b2a089befa1f4fcf6711dc657d0e33acdf276968add42b1a5d302ffc6a0a347a7964c390905f94434b09ae2da1653fc01eb9860999c79b821c4c7b7307712a411e71afcf8ca203ff17f2a8e48ea3e7ba4cabad945ffccf94ec6610e0278a91be60b4494d25613635bd39f20357b7b2e75c750f9ad02dd615bb010001	\\x1f9ae16d066c23227d7b0d99e531a566baae1b834010b28e880dbeb404887fd87ae0f4fee87c424ef7399d47b2b8068f6af3df27b1439141f2e8472a8508e905	1674162607000000	1674767407000000	1737839407000000	1832447407000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
424	\\xf70760847f9707976f6eb6aba4856745b354284141a4d48d4a9019bf9ff93d13385eb033c8b379ac142245fcdb99c48b284189d31724d895a8676acfff9386a6	1	0	\\x000000010000000000800003af5cba212273ced035c7690d864bfd330e016679f1f120b716448663b55f85f28b4996b061ef26decc2725b30af41f493b42902e956d7f0d93272579997c4cac8d4c460bd0f2eee1d3ce6e6c31c0f2c141e80a6023995000a3e97a7e09085fb3393683768256afa0cf492e9c358347311a62178fbbe44c997eab1c6db5732883010001	\\xde16408298203a98fcb87d7885754b75a2655381b313b9ecd33255599badbeb99f4d9427fd341e4e604fb1d6ade50800d3cc79302a74c652a72084e7e4a17b00	1671744607000000	1672349407000000	1735421407000000	1830029407000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	1	\\x8db918db608a5f3590b09acc6cd1634b974f23c234a0ec090665b154ea76b93585a0f8432e0823d267d1ab0d3fd765fa8b7e01504d30a0f7b55b586448abb323	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6ffca1ac4998c915eb4423a72d61822eb886a8b001379fb8b0e4024c22cf6666da0b24ac0cdde8c64260cfccfd26de983a700ece565b21baf79d0798e4c73172	1647564627000000	1647565525000000	1647565525000000	3	98000000	\\xb75f93225e164dc3587706e4939f9519603e8a7d7a852bd7b98e22d31ed44fe0	\\x093100128acabc056faa92f194be18570cb16538a20a8d5774e5e583434afb34	\\x765cadebb496c658e767ed3a9190d0794f9cf07dc363b63af314f013903fe5dd5f333667656bad733a42ea86efc1e4a36a479e4d0d6675d247bee6f4cf388202	\\x6129a04c011b0eaff2b5bd4b8e09d3034b10476e469b9f67061c874e81ae7295	\\x10553ac9ff7f00002f553ac9ff7f00004f553ac9ff7f000010553ac9ff7f00004f553ac9ff7f00000000000000000000000000000000000000b6f0d482acbd08
\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	2	\\x2af0cff195c239268b0b00af4ea65e72299babd88e8ba4d9a77a66aaecb899e60bdec4b370e3580620888cfaa0acd34b0ff2ea6f00564fdf9d0af6ca7797a477	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6ffca1ac4998c915eb4423a72d61822eb886a8b001379fb8b0e4024c22cf6666da0b24ac0cdde8c64260cfccfd26de983a700ece565b21baf79d0798e4c73172	1647564635000000	1647565532000000	1647565532000000	6	99000000	\\x7bf0088cfa0137e48b4039d3cd4eff6fa7c3ed156d5e2f1ceed71e3a0e7bbcbf	\\x093100128acabc056faa92f194be18570cb16538a20a8d5774e5e583434afb34	\\xc61fb2ef786531416090d627cb039d422e8b6eb537287e1e2ca1e24490cd02b816cdb01c234ff5e174c7599fa25cd6a296b880bd5468678a4ea5625312be5606	\\x6129a04c011b0eaff2b5bd4b8e09d3034b10476e469b9f67061c874e81ae7295	\\x10553ac9ff7f00002f553ac9ff7f00004f553ac9ff7f000010553ac9ff7f00004f553ac9ff7f00000000000000000000000000000000000000b6f0d482acbd08
\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	3	\\xeb40b671d217611a806a355375ce73f912963b1d914b0e3370d2ccbfddcae00063d600db0b01c668b38d8a0c5651b1416204440f208d90ec6f89830930213cfb	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x6ffca1ac4998c915eb4423a72d61822eb886a8b001379fb8b0e4024c22cf6666da0b24ac0cdde8c64260cfccfd26de983a700ece565b21baf79d0798e4c73172	1647564641000000	1647565538000000	1647565538000000	2	99000000	\\x0215aa2a5a0acf5782baa78153a296e93d37673b5df3f987bcf8896ca713eda7	\\x093100128acabc056faa92f194be18570cb16538a20a8d5774e5e583434afb34	\\xd075a874cf1da5cb286edbbaafed28a05111e777475116b87aad6e63af686722a9e2de0183d3c50c4808a55ab425375e828d86ad760ed3015d5c9b7922ba5509	\\x6129a04c011b0eaff2b5bd4b8e09d3034b10476e469b9f67061c874e81ae7295	\\x10553ac9ff7f00002f553ac9ff7f00004f553ac9ff7f000010553ac9ff7f00004f553ac9ff7f00000000000000000000000000000000000000b6f0d482acbd08
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	2123969471	\\xb75f93225e164dc3587706e4939f9519603e8a7d7a852bd7b98e22d31ed44fe0	1	4	0	1647564625000000	1647564627000000	1647565525000000	1647565525000000	\\x093100128acabc056faa92f194be18570cb16538a20a8d5774e5e583434afb34	\\x8db918db608a5f3590b09acc6cd1634b974f23c234a0ec090665b154ea76b93585a0f8432e0823d267d1ab0d3fd765fa8b7e01504d30a0f7b55b586448abb323	\\xfefedb548ebb7c524d37ad4aa09637218deb7e5856ed76ee0492c575a97da1b17fa1fe44d0fc933dcb9a929dba585d2f529c28cbf3c50756b4ae0deaccbac306	\\xba97c349685502a8e587eb83d3a70737	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	2123969471	\\x7bf0088cfa0137e48b4039d3cd4eff6fa7c3ed156d5e2f1ceed71e3a0e7bbcbf	3	7	0	1647564632000000	1647564635000000	1647565532000000	1647565532000000	\\x093100128acabc056faa92f194be18570cb16538a20a8d5774e5e583434afb34	\\x2af0cff195c239268b0b00af4ea65e72299babd88e8ba4d9a77a66aaecb899e60bdec4b370e3580620888cfaa0acd34b0ff2ea6f00564fdf9d0af6ca7797a477	\\x576f5d8078a66472254702d4a2e393b0670f3c138ee6c7b858c19ae791d599f1091e0969c6010d6ae7657164dd6af680ccb82267be9dd83211f8140e51e09706	\\xba97c349685502a8e587eb83d3a70737	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	2123969471	\\x0215aa2a5a0acf5782baa78153a296e93d37673b5df3f987bcf8896ca713eda7	6	3	0	1647564638000000	1647564641000000	1647565538000000	1647565538000000	\\x093100128acabc056faa92f194be18570cb16538a20a8d5774e5e583434afb34	\\xeb40b671d217611a806a355375ce73f912963b1d914b0e3370d2ccbfddcae00063d600db0b01c668b38d8a0c5651b1416204440f208d90ec6f89830930213cfb	\\x8df1c2baad71868b86360791ef1a822ea7ee5c97908e650bb2c23a1bd24433181ce35f4fce06df9ffc723548bb255a149353cb562a7d80d2e0779b007b6a350d	\\xba97c349685502a8e587eb83d3a70737	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
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
1	contenttypes	0001_initial	2022-03-18 01:50:08.041193+01
2	auth	0001_initial	2022-03-18 01:50:08.19931+01
3	app	0001_initial	2022-03-18 01:50:08.327029+01
4	contenttypes	0002_remove_content_type_name	2022-03-18 01:50:08.339805+01
5	auth	0002_alter_permission_name_max_length	2022-03-18 01:50:08.348443+01
6	auth	0003_alter_user_email_max_length	2022-03-18 01:50:08.356055+01
7	auth	0004_alter_user_username_opts	2022-03-18 01:50:08.364975+01
8	auth	0005_alter_user_last_login_null	2022-03-18 01:50:08.373978+01
9	auth	0006_require_contenttypes_0002	2022-03-18 01:50:08.377575+01
10	auth	0007_alter_validators_add_error_messages	2022-03-18 01:50:08.389328+01
11	auth	0008_alter_user_username_max_length	2022-03-18 01:50:08.406181+01
12	auth	0009_alter_user_last_name_max_length	2022-03-18 01:50:08.41913+01
13	auth	0010_alter_group_name_max_length	2022-03-18 01:50:08.433471+01
14	auth	0011_update_proxy_permissions	2022-03-18 01:50:08.445647+01
15	auth	0012_alter_user_first_name_max_length	2022-03-18 01:50:08.455141+01
16	sessions	0001_initial	2022-03-18 01:50:08.489391+01
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
1	\\x6129a04c011b0eaff2b5bd4b8e09d3034b10476e469b9f67061c874e81ae7295	\\xaa7fe527c912a8a056b63018c559aace86626172b8e5b70a89b325a5f0ed425ea61d74a7310a41bab4dd7818f3e2fe9e6d627236c409ad76009e25cb7ac59106	1647564607000000	1654822207000000	1657241407000000
2	\\xa276ac534cb0871e0fa6fc2d76ab2ba9ed22a67ae465da1fe7a444a392da8403	\\x72dc7d1425d91aaa57e82b8e42f47d85e17d3142c8a77fb22ae114450a756a66129bdaf0b76c78a520343a3e348c418ab169bb0409591dbc6e88358c89370e0b	1676593807000000	1683851407000000	1686270607000000
3	\\x10e466c4be47a9f6307ca5d51a623d8aa322ab980793ca852734c3fef0b1f035	\\xb2838f2df964aaa946fa909c452c55c2ba50a3f2099487805e42157596ea05754e8c43eb6a256af718ed1973dc5a102dd3a62f70144e3a1de9f8c082c625370c	1669336507000000	1676594107000000	1679013307000000
4	\\x71a63ef093c799a388fa60227677bbb4890d893ceb53b9573fc0a5bd8790fd15	\\x3630182e74ce5c5a20b639ab2699fa6a3fe55c3daad4d6ba4753f007b565a8d3127efa0307f7317882b503d23fc3e2c087ec32fdb726dc5bff8def23eb4b9106	1654821907000000	1662079507000000	1664498707000000
5	\\x78f2c94951bf3526215b218f0464f8873c6ee4a0f22c57409be63e1ac5269128	\\xe144d176798f4e267a6cc8cc6687f55136926339cd5b828d1a70b92f020af75a0f1666b10384c49aec6af667a3e94bb1db87f09c7e7bda0d1a9e0aa8eb7dd406	1662079207000000	1669336807000000	1671756007000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x5e93295f6a16523c3cb0ff497ca4b026be6e767874cfa8508de5ff75dca2003788d762d3bda4122a7e531276a89374e31f6dc30dee627819e04888f375f48600
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	284	\\xb75f93225e164dc3587706e4939f9519603e8a7d7a852bd7b98e22d31ed44fe0	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009b11500051e51a2b82fb7251db703e904d16f8dcfa87793da9f4c5c724bf25b4bd106a9156b7dc417397995e64b5e4109e4529762903e39920c4ed7a8851cb15a5d2f8fafc2eea4ea0e0be2dddee1c8ea3f98762ca1db265493ee62bc1b091646a51fe2f71e184a89e3bfc2a89be3fd4a14a83f987ccf5e962e7e40bb52f59ff	0	0
3	410	\\x7bf0088cfa0137e48b4039d3cd4eff6fa7c3ed156d5e2f1ceed71e3a0e7bbcbf	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c90b5cc943dc91bad6ec89c3483c07635850af47d7523d5df44f85d2f5dfc76e5a42ddbef679b1da3eded36b2a19f88ab82c1a9a302092873c7c818592ea013fa86e25dc824c3fa3dd386d3c7c67f9a1e62e37e9598354c0b3d032100f4119b9ea741f25c61a3795a10e6538500a2168c9703aa8ab22820fdfd5a7da57bdf221	0	1000000
6	65	\\x0215aa2a5a0acf5782baa78153a296e93d37673b5df3f987bcf8896ca713eda7	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000005baf9943e9f4b46c5f27e32e53db1e441ec571b1280436b2ec4b93111d53d224ddbb5148b206530dd531bae5653a6c8b90a2a04f6f9e8d32900bd9c5613843aefd3328361f00b7f28b791286512563d40748f5af7f798f796d1990fb58423ce99f6eb8956e798fc50f6a2414132e563b25f140248186d8751bf06034b1624e16	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x6ffca1ac4998c915eb4423a72d61822eb886a8b001379fb8b0e4024c22cf6666da0b24ac0cdde8c64260cfccfd26de983a700ece565b21baf79d0798e4c73172	\\xba97c349685502a8e587eb83d3a70737	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.077-002DZ168G5QM4	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373536353532353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373536353532353030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22445a5941334232394b3334484254543434454b4a545243323554573844413547303456535a453547574731345238504643534b444d3253344e47364456543636383947435a4b37583456463947454b4731563735435053315142565354315752574b334b325747222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037372d303032445a3136384735514d34222c2274696d657374616d70223a7b22745f73223a313634373536343632352c22745f6d73223a313634373536343632353030307d2c227061795f646561646c696e65223a7b22745f73223a313634373536383232352c22745f6d73223a313634373536383232353030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22573943324235434e5650374a4e464233414538314737365644425a43574652573746434a5444533831465338334334504d464847227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223134524730344d4153415930415658414a4252533946475241573642325339524d383538544e564d57514a52364754415a435430222c226e6f6e6365223a2253434e483336384b335932434458444335544e434e4544543037384730503146544352435443575354474454454d42464a475030227d	\\x8db918db608a5f3590b09acc6cd1634b974f23c234a0ec090665b154ea76b93585a0f8432e0823d267d1ab0d3fd765fa8b7e01504d30a0f7b55b586448abb323	1647564625000000	1647568225000000	1647565525000000	t	f	taler://fulfillment-success/thx		\\xd424f652f4b59b11d057b7dc75c9abe5
2	1	2022.077-000ABXD8FZ97M	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373536353533323030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373536353533323030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22445a5941334232394b3334484254543434454b4a545243323554573844413547303456535a453547574731345238504643534b444d3253344e47364456543636383947435a4b37583456463947454b4731563735435053315142565354315752574b334b325747222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037372d3030304142584438465a39374d222c2274696d657374616d70223a7b22745f73223a313634373536343633322c22745f6d73223a313634373536343633323030307d2c227061795f646561646c696e65223a7b22745f73223a313634373536383233322c22745f6d73223a313634373536383233323030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22573943324235434e5650374a4e464233414538314737365644425a43574652573746434a5444533831465338334334504d464847227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223134524730344d4153415930415658414a4252533946475241573642325339524d383538544e564d57514a52364754415a435430222c226e6f6e6365223a225632484e3930534157315456504a4a34374d595246355959574b354d50413734445a37314a32334330563032364336324e575147227d	\\x2af0cff195c239268b0b00af4ea65e72299babd88e8ba4d9a77a66aaecb899e60bdec4b370e3580620888cfaa0acd34b0ff2ea6f00564fdf9d0af6ca7797a477	1647564632000000	1647568232000000	1647565532000000	t	f	taler://fulfillment-success/thx		\\xa7a3ef2e8392ab4ad1bb7266d844b10c
3	1	2022.077-03C6TASVXAV9A	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373536353533383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373536353533383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22445a5941334232394b3334484254543434454b4a545243323554573844413547303456535a453547574731345238504643534b444d3253344e47364456543636383947435a4b37583456463947454b4731563735435053315142565354315752574b334b325747222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037372d30334336544153565841563941222c2274696d657374616d70223a7b22745f73223a313634373536343633382c22745f6d73223a313634373536343633383030307d2c227061795f646561646c696e65223a7b22745f73223a313634373536383233382c22745f6d73223a313634373536383233383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22573943324235434e5650374a4e464233414538314737365644425a43574652573746434a5444533831465338334334504d464847227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223134524730344d4153415930415658414a4252533946475241573642325339524d383538544e564d57514a52364754415a435430222c226e6f6e6365223a2231594636374b4d50474b59594d5750584646454a35394d34583553384a583944453038384339304e394d57523239314535395047227d	\\xeb40b671d217611a806a355375ce73f912963b1d914b0e3370d2ccbfddcae00063d600db0b01c668b38d8a0c5651b1416204440f208d90ec6f89830930213cfb	1647564638000000	1647568238000000	1647565538000000	t	f	taler://fulfillment-success/thx		\\x4bae1961780cc93306c98d939f6e01ff
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
1	1	1647564627000000	\\xb75f93225e164dc3587706e4939f9519603e8a7d7a852bd7b98e22d31ed44fe0	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	1	\\x765cadebb496c658e767ed3a9190d0794f9cf07dc363b63af314f013903fe5dd5f333667656bad733a42ea86efc1e4a36a479e4d0d6675d247bee6f4cf388202	1
2	2	1647564635000000	\\x7bf0088cfa0137e48b4039d3cd4eff6fa7c3ed156d5e2f1ceed71e3a0e7bbcbf	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	1	\\xc61fb2ef786531416090d627cb039d422e8b6eb537287e1e2ca1e24490cd02b816cdb01c234ff5e174c7599fa25cd6a296b880bd5468678a4ea5625312be5606	1
3	3	1647564641000000	\\x0215aa2a5a0acf5782baa78153a296e93d37673b5df3f987bcf8896ca713eda7	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	1	\\xd075a874cf1da5cb286edbbaafed28a05111e777475116b87aad6e63af686722a9e2de0183d3c50c4808a55ab425375e828d86ad760ed3015d5c9b7922ba5509	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	\\x6129a04c011b0eaff2b5bd4b8e09d3034b10476e469b9f67061c874e81ae7295	1647564607000000	1654822207000000	1657241407000000	\\xaa7fe527c912a8a056b63018c559aace86626172b8e5b70a89b325a5f0ed425ea61d74a7310a41bab4dd7818f3e2fe9e6d627236c409ad76009e25cb7ac59106
2	\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	\\xa276ac534cb0871e0fa6fc2d76ab2ba9ed22a67ae465da1fe7a444a392da8403	1676593807000000	1683851407000000	1686270607000000	\\x72dc7d1425d91aaa57e82b8e42f47d85e17d3142c8a77fb22ae114450a756a66129bdaf0b76c78a520343a3e348c418ab169bb0409591dbc6e88358c89370e0b
3	\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	\\x10e466c4be47a9f6307ca5d51a623d8aa322ab980793ca852734c3fef0b1f035	1669336507000000	1676594107000000	1679013307000000	\\xb2838f2df964aaa946fa909c452c55c2ba50a3f2099487805e42157596ea05754e8c43eb6a256af718ed1973dc5a102dd3a62f70144e3a1de9f8c082c625370c
4	\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	\\x71a63ef093c799a388fa60227677bbb4890d893ceb53b9573fc0a5bd8790fd15	1654821907000000	1662079507000000	1664498707000000	\\x3630182e74ce5c5a20b639ab2699fa6a3fe55c3daad4d6ba4753f007b565a8d3127efa0307f7317882b503d23fc3e2c087ec32fdb726dc5bff8def23eb4b9106
5	\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	\\x78f2c94951bf3526215b218f0464f8873c6ee4a0f22c57409be63e1ac5269128	1662079207000000	1669336807000000	1671756007000000	\\xe144d176798f4e267a6cc8cc6687f55136926339cd5b828d1a70b92f020af75a0f1666b10384c49aec6af667a3e94bb1db87f09c7e7bda0d1a9e0aa8eb7dd406
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xe258259595dd8f2abd635390181cdb6afece3f1c3bd92d37280bf281b096a3e3	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x2ed353d5b53557c9e7abda00d12ac671b361281a07d6da418991cd6fc59ee845a7d8b20ba3315c87e48cf643c5ebf2bfce284b54c579565ecb07b3d4fba9f501
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x093100128acabc056faa92f194be18570cb16538a20a8d5774e5e583434afb34	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x12c2412cdf807ca85b89644d495ed9e42da76e243d66a0c3f562dcac41804250	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647564627000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\xc61c0c71e0d5d06b7585dacb26c771937518b109865bf23c0369fa83d58168cd04e8f13f46ab482bd1d0749bb99b4870fde0ee4c8b3a970844969003277e1405	1
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1647564635000000	\\x7bf0088cfa0137e48b4039d3cd4eff6fa7c3ed156d5e2f1ceed71e3a0e7bbcbf	test refund	6	0
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
1	\\x0434e95f0d3091e8831b4793520728049008beda1a3db14b022aa9b84097c209b2a80ebf6e57d8e365047605fa51541a97b2013572d8f7eb5cbd5adb33da8edd	\\xb75f93225e164dc3587706e4939f9519603e8a7d7a852bd7b98e22d31ed44fe0	\\x6cffb5d12df4f971874b41a9045c7ddbc38dc92bc7e8b170a8e49925d74d6e779387895fdc3ddba90e1d31f4d82f478a05ea4ded5114e4006718aeefd3a41400	4	0	1
2	\\x24af95e44cdad0f612e5f51130b980c58889cab3e2b243c9ed75489324c64b602612cb226bc2ef4202b6371dd3110e65d3fb5bb6396c357047357bf5a6642d1b	\\x7bf0088cfa0137e48b4039d3cd4eff6fa7c3ed156d5e2f1ceed71e3a0e7bbcbf	\\x9b07235cb66ec99b6ef2deda2032ae83679ee46e1f00cedb65cd9eb1ca1e62ed0aff3cfef41ecaa285dabe24afadb7dd5303d2606566fbc6065e7e31e9407400	3	0	2
3	\\x5284a482ec56ab4d56e36811cc687a64555cb238440c9b6a6c07a8234e0bf36318a42b5ea62a0b0d3d906c38e354a16f13f874cad2c2775bb3bbc74c935e119e	\\x7bf0088cfa0137e48b4039d3cd4eff6fa7c3ed156d5e2f1ceed71e3a0e7bbcbf	\\x0bfc59c556cb35b8042b4167a851bba932e6537e00b0122216c50872f6d1af16a75ae73cbc5517a74a0fcc7da2df862bafce4d9d07095bea763504806d7f3206	5	98000000	0
4	\\x67a15293ab949e7fedc00257c5bc31bcdf8454e92ebc4e3aaf4df96cd6fa6072e72ae29afcc10953644b21f25d9529beb8de740cff95ecb1d8f5b8399e6ad531	\\x0215aa2a5a0acf5782baa78153a296e93d37673b5df3f987bcf8896ca713eda7	\\x310b2bfc3d03097599554de5eaf0c48578cf24360580a48de4dda063251b4a3c4c7fcc73a84e8b635c93376196e09f267ed560c3e95cefe925cfb276c5dfcb0c	1	99000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x24724fe1b0f7a2c3df334bb819380956fa5c712eee5fd68be5a9c4f7e1e7f8edf8e4b3bf7c5653b32a9061a4cdc0c901736085c52e4e3521866183ce1fb8a507	197	\\x00000001000001008dd914043dbf65b6b93325b64d93a98820da005b4f26ec45ff5c35fa63323f91670722ad4397cf4aaff6997a7be689e7c14dd85d828f70307f8730d2cb2fdb926ebd713824e1fe76b357958831398ed85cef5d245e132dd7d1696fc8c750df9b531bc0fab4aa2c5970fd33711c534507ad985c5a4aa301179e9772364d16b199	\\x4376ae22f22db25eb330df7326589320e0edb466063333aa9388a08a2082cac6ba27c8594fa14cff357cd8b2d1555df4797ce05a2f44d6192da056f112e136e4	\\x00000001000000014008a43dab54407decc3498c07a324a372580d1dce1f7f79fdb5e497b8be9c2c3c5e1b045f964523243052687c6d916ab2c119ba995743074cd1c102f3b508a172ba7e16b7e987b3bb275421bcf1ee4b1cd8d012c700cef0e16ec51e9d2f441d0eb8751d4802475e61edb08639b2759aab71bdaf653e3fb619fcbec02eef3e07	\\x0000000100010000
2	1	1	\\x76395628f801a4084d5148782dce894678731967ab4e5590bbe0257447d933c4d6b5ebc2c78446a69ee9d2e5d2aa95bb111cc0df2e0a38fbb495187ff494a507	113	\\x00000001000001005497e2fb471c13c549e60f718651bdaff9f2035ec14b1b2cde266b6720d39124142ce7bd398b9456f5c77e679aa872e7bea6fee819d40b477a55db4da49b7dd0b600f38926930633a8b84429a0b08f471813486701c481a8368e15bb4e3ea841e95eab3391e9522a3bdbeb58c65f465c4e8e545709093853193a7b6f5f1672d0	\\x7e4fa98a9f69c0f8470d000efb13546aa0603b4b3607efb8aea12bf1e1eba0326bdecde35dfde2bed5eae44691e6a6bed8cf6388d6c30838d68298ba5c3c2cce	\\x000000010000000167e4b3d602e625629cc2d1a002a976427127e57d4335527e06733daee31eda14175e1ce421c7f059f44e25f3a7590331f2a39d49dd705ecfc6d2cb7c454b01fa2ec60eacd2100a80e4a9a3cd139e7cbda270e288c55d067ccf0315cb4478e0b0c5b1a6bb68a6f99081bf7a1386a0426f9a9f0600fcbe9b08059eb4f07e963df3	\\x0000000100010000
3	1	2	\\x4b81442c0a34decdcdfe5fa4e8acbef90911b65cd8e5d186e3cd5c4645c599f6efc3df07dfc4582d0c4a9dd87dbe71f42a4eb728970f04036ae080636ad93b07	1	\\x00000001000001001e1ca8c13823d23b422a7e0b05f0ccd6c2816b2b4ff155655844f61bc2f199d7ecefad4cc83aada00ac0083673aed31083a1c8d4cd1a6a6554224b10d613c9f07d683481fb0a9cfa9cbc06e8265a3f606817a220a3015146559c4a870aa03d14a85be18621b00b41a052c2562d963e3ab518524ff556063049471c1640554571	\\x142cca46efe9f6336db5ec359e7c66b75dd42ddae1f60bb1bb9378109b91342b1bb74c029f6414cff53a8d4c9c25381c9cd66183dd398fb96022fafbb366a8f6	\\x0000000100000001abe49d965d06f92829978855c10e202afe1ba187c1f13bfa7e8818e5ecf80b0b4c4cc62743cbb4eaf8ce4e9643b46a517a7c3560972ebe44080ec1f9886bf787e05ef613bfb7d6fd2acd391b945219d81f557abc4fee2a8e2161a2a630481bbefb5bbf6da4f608dabef468bef7fc8950a87ec2c92ac9393047a2110816e74958	\\x0000000100010000
4	1	3	\\x05db7aa2e890b0c4efbbe54f291777c05e3410e433126976baab8002406443ead62694b92f71549d32b67c409570c8f01b821cda6c93657fdc1a167d2c2d240c	1	\\x000000010000010045ea8a6247c0be96d5657315433782b1a3cb2717d0950c904cdc3d499a3e31f7f8d18846992369ec53cc81ada86de0a377e4c848c48067ad5f0337d7ae1860a52fff429fe29d2d68c4dccb5ec587342cf6a796dece3e6468815d5fbccc8b7101e7b71a0704fa74e53a74f71b0ea42877931eefe72f8f5d7ad5e775abbf7a0d0b	\\x8a1d0f15244354936932f28afe19438a23087427c0ac2130049764a6a15449f9240e4efdf3df6f33309821999267bd6bb63f21090f560c3547f77e211789fe04	\\x000000010000000122b7601095e305809e4dac2a474de97fb75d24fc81bc31a340ec089e4423bb8836e0a16da03cc5c0803edfa92754b5a8d6569b75c9ce66f8b5533cc4ed6de50638a0bae8b4dcd1bbfc42a234abee1f5c6e39996c5db8467247e41d0ad30164ea350dd670f29197b60926182cb5a6fd7dd23d392040213d573025d6479fcbf9c3	\\x0000000100010000
5	1	4	\\x4bd293cc54b53b9827e102a625de11578829fa4dd33f8721b742dc6dab2b739117d828a9ca99153d394dab49be280e25c846a875373bfb78ee1a5e9858ae8f0e	1	\\x00000001000001006378f7db51e0acbf25b53c3e59a50452245922d66754305748092c1f9a13a5112680657bf5e921de7d4de6bb73890082a1a2eb62f3445a308a3bf48c0476f7ae6b7ca0991c2b068bfbc8f0766d05532a1e65b4a72e2fad229db89c722a5f0bd9523a34c742132f68d6c40c1d4fb6184269b43c664f524edc9460260377b79d77	\\xb9675aec1adbd7ccc9cc67aab1d1f0c56ed29499c94124a875e22776fdb06bbd6d1f458d891e275e922c203beb5c1ab3be77f463ecd8a1a19548d6d52e52210c	\\x00000001000000018748ba14a73228f1a348579cee45a223ec3d321e047249ffda5f93fa9ce9721c705db487448aad0d7421555a5dbc3ac4a1b4a39333f501bf247e8aed40d3dc4866bb80c72caba1f6fb2afe23564813da3c59624e299b800ec09d3465e5c7a85e2aa0bad35613a0eb8e928461832f361258804ebf8f846b2d0c6e3f598cc0dee5	\\x0000000100010000
6	1	5	\\x860cdb6f6ca28b4202221c959e563a4618abdb1aa2f84d6920192d0421f2dabc2d0d0db942b4d3a26ba593ec6d6811af1ad9c59bc1ff2fd156a9bbd610543302	1	\\x0000000100000100904f27eba62272c61977c1d94f84b88dd3d1e713b94695501aadd3b071cecf60ea4c1228a2b836c5eec10295242f74f3f7acacd601ff4edc8370baac4734ad0f5170af664a6931dc2d9bf66b7b53834dbeaa7bf33994f38a12014dcef58a41fc680a0d078d37f5d0a42fe5b9f23c0723f292b3eedd673cc4a10ae8618f5b5be4	\\x010a7d5c88ddbd41a9c0ef4a6860276965bd75812a0e56f03df0fcf3dfcf84bc3109d2c91a21910be748d2a75701b8e1be7a2569d39862b678dca6f80e247684	\\x000000010000000164e832d341c808f818194a45eed3e749c354877d0f5114929053bd4fc1b5da8a9dc1cb9ef30782186d335273835192b4d0d6ddab3858b498acedd9f3f806f88a238d32634a712deceaecb45860b109eb0fcc54a08b120c269d941e8a41391dc824e397d084ed89d273ff6bfd39947d64c58fe9830eda9afba1a881fdb212695d	\\x0000000100010000
7	1	6	\\x643b89f451c296d9ecddbc83edcc53929a1f7a2c9e980bf13d4bc6b4c7c1858f654f08e922306cac94b16cc3ea36fa436378f2da78db7a35ae74e766a417230a	1	\\x000000010000010048835e2e82ecffcee1d0b44d790fce32bd54102adc71278929039b887167e56f82e2ab889be8e1d2c22755f5fb7a1143e30f0e277bc8212966969b792e17cf93f9fc0472bb62ef973586350762d7731be359ce178e9bdf72b6b917bf44eed4adb3978fa557f3e49d375da6a5f106bfcab135f49f4ceb19e418c17e474d1595fc	\\x1e8d757f623dbe8c326ef622367fc688f0a4c38ee7d3e850e9769f1671dca23b3ffe40b9beffe2f624b51dd49abd847a6038e48316d10cfaf6f71d39df7dbaa3	\\x0000000100000001706850a24f001893826ae2d7e874c3f7ac713550577e53b953e0868d8a6a207399008e22ce18947c5f47f18ab6802e226d8aa35ab06049ed06c35ccfe898be50bb836fe9b2a5d2e6f53150794e65a34148453c4a5195904d587d673400ade065ea3699c0b82245dc2f7468529b65c84497c31580457190fcebd76fc96803e3aa	\\x0000000100010000
8	1	7	\\x1792c417517f13f97310e9429ddca9d44a07bcb31e3105fecf79839ab09917bad82fd78f48d22174ab83f3db503be0d0812803625c728f25e24f39505d70e40e	1	\\x00000001000001001bf869c91b96e0627315648d35162fee405240ac7b291231131a79858a9497e54db586da6e6940ad625f5e8e8e08767d96c179330cb18cd028e92fed196770df7331dec3a572e806f936e30541d4ffd4297f205ffa3c383078e2ef35c46abb79834328d126cd003a13820ff8eb245fc7d103dc96a4db3932bb2de161a3ca93ce	\\x5d711acc6aa8377385c7d64b8e5acfcb7305b43496941a018ad9ce29563e4e14f9fc1ae086ea975a2ecfbd049692bc99c40677697ce615ce7b98c522f1c876b8	\\x000000010000000127cc34a3144de938ef4b0441cef5ed63e8beda30b754af153423caec3e8fbe4fc05101471309af8e4817e0b622f1e41aa4cb0b2199c5647a554c1cc9e20589efc9d6d464dde2909c986209c04560866dcb9c229858fa36847a5f2227a76a76ea5347a23aa674d7be684e55eab3b213c7889d92be93e211ee9d31de6766927faa	\\x0000000100010000
9	1	8	\\x3f0bf21ea6a2755d483801995ef86827f248c34e3bdef000955a56f4053d8f148263a881fb5ca6988c0c8055f9059602bda2fcb6ab95fff9da6579580188d30c	1	\\x000000010000010012d8d42aa08544d58a7cde98e1a54ab2222775a96379e8a386fcc72d2bfe847bfe183700f2d5c8838e2a2e2979a1774dab19d9ed6a375d1c102026e72114cb0265bf514db151d300cd73d1a41373386dcd7e2671070459a6c5de960868511e8b543d6796cf8dde858736cc0a271600b9df238e23f3a11fbaab32ea27a7f0338f	\\x972fd04c5d8c96eaa4f07e6a6444048b9e3a9856997e94ffd57ce9dc737d2fbd47236e754dcf9eb975c584e02f7b7ddf88e42503f311168ba6db470c35bad912	\\x00000001000000018c7ea7d6d71a98453d59f7a286957d6ad42bd6d14baffcd3ec7791518473f7d0b5ab2f90f98f3c87007a0bcf53aa3d88b56dfc920b30084cb962752194396e2566feedd94f9942b92923ca3ac99f9bd6fba313e89bd872b10556596804670c628eb88a9ee67c62f31e1f9495dbe7fdcbdf2ef63f8595f4a1ad3539200f2ce2ad	\\x0000000100010000
10	1	9	\\x161c845997e46429637dfdd1f662118ddb470a8ddde01d4c79776c92172c2114fb745f8785f8f31afbe1724ef9107d3a43e695f6590fa49d5cd59ed25064c40f	1	\\x00000001000001007ee3e2a7ab8cafbdd33c6dab10897e0e586e431d92fa93575018374dc12900e68475de9141551ff1f164c153c66fc2d1be998807181360a23498570a1a6fd845025ea09d5bcf17ffd37052e1e1c47c5b63305e189990a441137400a0e27df53f831ccf07771646f162b49d796d10ce2fc3bf6ba1a994c42e813159cecf7bc5e9	\\xbb5dc4bf1548fb1362a4fc881f30cc51f523d4e58e76e6b611bcd932f7f90e31d556e6d4f92330a0b222a16e3dd7148496232cdf08120b606c683fc9b19d1b5a	\\x000000010000000166ba83984ac4b8d196d2cf30a31475dca6deb6cf3b1c5796b2e90e1ed3af70137f187d61512c85fa4c61a82adafec0f2032f1feecdabe3c5e556de0af8c8dcbbbd310ac0a13303b2712d78f7fac8045fbbe2c3415bd2fc5604130bdd643cf9ce69256a54ce9055d7c27634b4e602cad3bc8fed2a60e2dacc7e4248cd2d99ee14	\\x0000000100010000
11	1	10	\\x638120e799828f4c36a488cf0add6acf3de590c7187909845290da267fbcdbfbcf6e214f7dd1c3686eb2da243108fd46ba9b1ae6e70552ab68b1bba0869cf00e	110	\\x00000001000001000eeb0aa7b866f3b48cc38c58002c46967375e8bb19773f4a4654157ddfba64c6a8300ba2bd6710f03637127ecf37817180d6fd1846d2abe4c8435205c86f39020095dda7838b4987ffc5ffedf16712a7c0d35292010437e700d748731239201eaf3e624d06f6af9dba8a7d9038baffd6f976f0b88c1f24aa4c71c3d185ced118	\\xbb2ab0c84616dce27cd5791ca7bc1dad5a20a4ff1a7128db593045fc774fbfec176404a6ea35e193e318221c50fe81dca2d994e5ae4a0d85dd4204e9d69207f3	\\x000000010000000126c5a98966b2d8b343237a403c8ae566ebdcd0ac9c69700ded4184698c653cc88ca40e60419234c1c6f902c60d36c491c89680d1929d2645385373721dc02bef037e3b0d38a426ff6293f8c50a1c3e09a9a197bf673a01e6b9c361d298a13aed10a66260a610a54d36e3eed2584a2758143d61159bc4e159eac1cc4744bfd367	\\x0000000100010000
12	1	11	\\x55ea9b06970b08c18adad3cc9eae00c6d8915e78875428c43f58dd2893b11a014693421e4c3f0f92a6adbcd0c0804f142e551e4bb3b7012f2ad8773cce7bdd09	110	\\x0000000100000100b19d6bc40a70d3fd52be343498208d821db32cf3088f1b0276f10a74b21445029cd3ef37acd6b076ce15c0ce29f544e5593b2107aa1ce29c946224224231f122f4f8195cface7ca36e04d2868f77849fad0d0dc4590c06db336ca44a8819b3ec6bd866799bae3c12d77cc8c0dd1c5f96ac346607ad64ffb0540791e003cc5762	\\x0bf28b5bb4e19806aff8bdf3cb905e797b82fea9e987a4589940a7386910ca292e61eb313ee921f96fedec78e91097a344206428fdaa70ff7d91944ec4168a6e	\\x00000001000000016e3ae353d541cea658e7dba05470ff181e43ad9ef8d7662123459da99287d4ef301454de4e580307e26deb2d93ccd72ce4c0f1285d08953dc85311479bf79577d07ac9c889ab54c0751c1cc503d71c7f534f8afd7f1eb7e903c48b0530248da15382c2c1291d2ee1b6aa0d2dae1823734bf4d35f730706379c2a7c5057c300b8	\\x0000000100010000
13	2	0	\\xbf1820927279cfe6e85c5969fc76e66f96d9da7dc877dfd2b40e72f8413665f0b79b9f1e60fbeab8a6813fb68073f4c49fb4249b3a30e06996bf87a165d5530a	197	\\x00000001000001009fcacdeb2d6d93ef46a760081761adee321bd4b69a8e07b719d5b86a9f0c06f9845d48d902f6512213e2642dce9069249f6a22bba2fe149f708459e49481b3a2517f665121d6abb677c668121847d42293ae6529cd7d9ac1b39887d0adef3bf55549e0c698f8a65fa153fd2c40854486a1b3fbc921a59302a5f0359132e7bb00	\\xbd5a8a0a886e3e24e73452e4360f0b9646bf68643cd38b8b6aefa79c06d79933fd9dcaffca77301486181ddf2964b3f74f331f736bbf52789b8295497d937b61	\\x00000001000000012f10716c4b91174b554b5efffdba1392255e0131a9ec9639f1a59743d7d06a81aee3dea93bf99056283a802fa39e013985ad853434615cbfe22defa574e26ba29d25948cf7d0e47bfab0ab7e60e5d88e3968817366b9ab647df18c7c4482b1c5a880461421ffca32428b5a59ec88aa7b4a9865522201e80db5f7997eab73805f	\\x0000000100010000
14	2	1	\\x3a2c6554352311a126a572c2e823eafdad29a67abf5477293fbba2668c4a3c8a288f1c3ffa29479b18a7a086fe011a123fd9ae734ea93f555a0bc7daf2bbdf0d	1	\\x00000001000001004e3af06146d32a2791b480ba30b728d1d776232e94a743ce0ded0ac17636cfe12a6bc20b51ea7dd3c728a50b1bbdd07116c937cded18a8a637e91249610da4fd84eef985a33ff1fa65dc3dd2ca17552014b23afb69637d0e2c3d5f57ef477723771e51d32d5bfb2d169ac1393621435b1ee0920ab8ab9316d7cc525e611174aa	\\xf8be1c56b9cee3567c656e747998a66a6ddb942f994d83396ffdfde31ca92d33d604df316e6c9d66299f035b2d6d2079e0e3bf1934db5473f25068cf74aee35a	\\x000000010000000116fa382d58d053c0c55367362ebb3e602eb82257e39b80e6af504f3755be52275a712e38809d4d4e34adbaf791dc80b2ef90b798f5064db3e0ead1fe200332c83e2f3f9f96ac1edab1b1a868afed74db8b49812791e4ab1c7f86f9a6fe6144adf6c98a51eefa3a028ff8966cb142067198e661e3d59f46216d3377683a056582	\\x0000000100010000
15	2	2	\\xe69f73c592cb8a22773ba54fca69eb06c10021bc3215645e820a7ed3a9861d0ef11f435592e829884b0e01fdb2d17df0e97b7a1695a4843043d8326c8f724304	1	\\x0000000100000100aed9d9958e19d5a8fc09532a70caa86c4689b9977d262c87861a9386c0ff1534e4dc6ed8bcaf89a51992f0dad45545fc7564e3d2fa009deb349e312784176a807294a3fc2ab5a6f4b9cf6fc3b9373ccb2ec9aa5539a7a573a5f43e9ba2960f4a682ef3002ea0eeef107783e4f5d6194f8f9a195a392b4071b261d66322f7d466	\\xd146b39569a96936efbbc9a1bec70c2cec145044fea494d0bde20b17117803158ec581cff5088edb8faef7f2460f7cce538e148ec2659a9c0bb33fea8d695df3	\\x00000001000000016685a8e963944feb08486f8462a80153b77e6d5fc6bc8479966b5b563249f5dcb3406dcba7b5a26e29b94065d8b5ffa161ad87fa8807b4d215414f042a976d83908fe8c16f0b550961a0e5829435741765aeec4ca6928461ec543aabaaf0ca1d350f16a5d59c2b522bd22c23a993d21fdc61085b427e4108861201fe6497da62	\\x0000000100010000
16	2	3	\\x2f03153057bd01bc562e77695be37d6461bb8f08027d4ff398dfebddc27ce590ad87bb76e11ebb8dec1b2d13ceb0e5605dad37e51a0691f473799456d5f76104	1	\\x0000000100000100b75183a5f58b8677134fcf3213e90a33ced177aeced4621607526b5db1a54acb102ba62a4b8102066d91c8e8ad97b8d113a845f8ec80cdae9a4fd3bdbd7ac2e008ab16e9b4dc1e5d2993f651719c7c72dcb94f61d78c68ff424663b8ea845e7cf2f8dbaaf8bc6c66f107fac9dcfefb22c1452f1d7e3add391fe3a294c953bfb4	\\xb84bab8d354756acd0bc62a78b621a24e8a00acf971f1a6fd5124cf778ac2a5a2f9be0601d16bef48620feb049084cbae0a72778b2646cede5fe5679c53cd981	\\x0000000100000001c2c0285c5ae3b1e6ff606d2bc5fade2b3945b23aaf64fbae75809284a84a331e9b2860be75111b160d8572b16fb433e3f6979e74bd6da2c58112dac2af43e44b91c8b598934ddd8c7256a13012379ba72f8fa111dd8da819bc7d5a931cb3933583bd3e668026df288a6efc230c1eac6b465617392d584b56609743f9b9cb13ee	\\x0000000100010000
17	2	4	\\x9b98646364cc0b8cbe204d8fe6f1b7d04d4dcdd28d62a19c8398b047589fe0199aa81069eb76f25b9ae1143861defbf1e78ffd49d16845cf075eb43e385faf05	1	\\x00000001000001003726d709ee30d3d7a8baf90618970ba9771cd12d0385782f9fb33a2ff2f280d47f9f772f3153788d66274485983e4578de25cb076ed485edd012aa426b8cf96ec58a8ae81b32c07635b80be9f0ad7a7bdaf9a2491b81439337a8273021f1aa7ffaedef08de7d90c14dbc23f62ac177b70d72588f574dac89a74794a6fe9c48c3	\\xad145469d44e6fa14b4e45937d4a3e96087b5483e8a434048959670f319930cf52463b4142b4d160a5dbc25ca8f625bc6b724a42dcc67e236093d64cb38f611a	\\x00000001000000014e127769cfedcdb38eef22c06ec6dcd07996481bca089c2a04a71581bcf1c1a23617fcae03170cae26da44de055b00215560dbd1bb0d1b106cb8c7dd8add9715687fc47dfb351f42753878a8924d535bb4641353a0662ea674e64f6db9926d0f46d0ce3b330191d64d1a486c05a95c6437d2dbb624b0bf5d7e97bba8d06b5815	\\x0000000100010000
18	2	5	\\x78693bb7588088bcf01f8069043f5be127fdc5a2c618ac2476f467f2145ef419b4bd8e31064592629b20b10e1b5629ee78b1392fe8c7f9711b93a774199b030d	1	\\x00000001000001005f4d4b076eb913d4ddb26f7cdcf11403a387c236533b24c915dbd57b76f9848730db9087676d48c479a29bc962496dead3060557333fd360cc0e518e6d36ca6b39c867d83ecadd7836e012c8f76ab21dd10e943d84f6f2dc0bb49e9f23dfa5e95ba44f27249df8db5b0318a2a40fff9c6c20b27ede90cb6bd67aebac92aa85d0	\\x4b16e6b628e45bbf7d46a9b2f1ffc924f8353eed0b90a20b7acc079e6ecce57ac6a07e6faa80e93fe48c2ab9d91c69b6d628da977ee965cf6941532e4d82e133	\\x00000001000000015cf786569d03628a2770c4895f6e88f88d2211a44a056d9cd49b74ea6ae2414c767740ff2b2526f05cbfbae608c87d488ae13028cfcf15ddbc5293f042568627207e34f801944dc7ffe45ae4de726c213332657042303c9b286d9a1259c3cc453fa4a80991953b2c0ed72032271ecea7f0f7ffffabf59814c2e9debb2793c675	\\x0000000100010000
19	2	6	\\xdd83a27808f55a01fc4db4864824e60dd73d2ce2123f6518c1347449b3376f2b2444fc5fb22a85ad32b75cf83fd11fa1818b71f43c4b272eeb3b4226b0df6c07	1	\\x0000000100000100161c5cfd08e7783046f32f101185749b72507f5b8ae9955e2f8feb6ec6767ce999d39ef4e21ca24dd1136f4dcbfc6ae74f8f78ae6619301603b99a0bb220486ea8895a1c407f1f76cc96e2988c5e83bc47355bedbf7cf39a44ab7709825573090912aae503c1987d0daf4ef7cc75d04f17318f29ec6ba6b72dab9d694695751f	\\x1562a9efa2ce42c1ad66dd9bfdbe2e805bebb295d94f4a18a834fbea4ecd2aac1fd03c5017ffae153348bd010c5cabe092c8705838e30786fce87c624f89d3a4	\\x00000001000000012d86af97e1d499e103bb2c214df84057eec4252b51322d6e65d0e3d5e995c7749693a02c8ce2303ecfbe0a11cf8c6c18f50f7754860bcbc89e36a28761e42ed47b6401a4b347b9b729f6817b442dc8e93fdd463fd01ab56916028f8b9716bc96228fb29e63d21df946af6d8048879b628f8a99b4ac5a5bfe3733136a18c92239	\\x0000000100010000
20	2	7	\\x21d3b243ebc75c38bd45584a92b66e22f303469ff182f070db4c290023e703d270169c295512b9ae07810e733a9e36d1c3527930d54688e7c5488256b50c1409	1	\\x00000001000001003ee0a0198ed3ef50d3bce145b6a77ad95c2f2d4c0d49ab5138eacd142dcd1ecbf001337dbffcb0378fe3e06e8e1948ad358a4f5473e771b4dd5b9dc2aaafff231308e324b608654bcbd67e2bd8d0227eaa963109402a8996fdf638140a5ac264080a629e8aae7f8d40e9c1301f8ee0a7869a7e74f7745f400c44c9c145d63009	\\x578e59849095729516ed068a8372f4aac00c0dc72ab3b41bc760fd46f93736e0a735a2fbc8218202e3b33a5c747397fea8632e04aa26928959e8ef997f77d701	\\x000000010000000188625fa7aeab63700e65a67d069cc22ae8b28332c6e411d86eb32fbada19c6bb234204077bc07017826ae2f08f537d7c423f1f0ea2f942cc8d3e7b18723adf69a29ac5aeba93861b9318d778af7dc5cc48e9bb1f040c59d2f138fc6c741e86afec07f6057f5d69e88f4994317bfba30b4c7bad532bf806760edcb14ea2b65003	\\x0000000100010000
21	2	8	\\xacacd1dc18b34ff006c4d799b9930348700ef00303def8f1da958b270a040b1b65baba80b42129575103261bd4b7bd53524c56a62cbd8b788a4c85a4fb197b03	1	\\x00000001000001000e5695c36051e86baf55cd1aa523e279ef049cc5c1084257e4bb73428467d18825d59b73a97e03be5bfaf35d8a2c4d43e70426465953339d5219757810b438bb58d894c8bb1ad001a14e08dc1158142a3497a3eab0700d18152f9ffcebd7c6eab734313d7b0863902ca5fa8d450558d615f51b1f3ba7bf928a076ed23e196917	\\x46915bbf2d42ca19802703b7c63c55d1d9a00a2e1ff8673ee4ae691acb01030b215b847eaf2a4535e94fd17c0a595fedbd57e2b5e0403e77ce7668e17c8782c0	\\x000000010000000142ad4dda454363df7f5e2f6f11bfed5e104425731ac97f4de9009ed8893c92ed0f713948179b45c9b1f1888e52aca90c1c95c21b6b98b9f9ce48f7277e3e7559fc56284491e5ac69b1c11baba742d0bebde29101227cfacb289de0883f8c9fef766505dcbceb41520945279d10c1c02e5a09d3667c83227a471f580ecae627e9	\\x0000000100010000
22	2	9	\\x4fec8885954a947aba2c23394e3be88c13752eda6c4fb2d8032e024c8e078ae16bb0362c7362c38f8437e9f4244aff8c3f6b92202c01efe5d309663ab8c94a0a	110	\\x00000001000001001f941d28377f9d963c69e516a3f1457479f7ca4355f47ba8840c0edb0bcb4862de7aea64489a17992d30fbaf01519070d07ea656a11614cd22b0d331bd766d1d3d79531b34c068777dd5d75a933979e62806298bc5c3d9ce71e44ac7aad9d2c1df87c01306ffa6b9c62bd68af5ea8452a962c88165aa1c7677c9b84b932695	\\x0cd180f9d2cbc40d7bf085d1bf772ba9bc9e287ab9a88b5bce20e7b82f3fc74d2c0c479b05ddcda5158e29e28c3f454aa30cd4759021b8e8f428de91703e5eba	\\x000000010000000199a231ea87c58fd14a5a6ced2c7764f38f3fbe2a1e2999516a3b413d369d6d596a753f56099d86259d85ae03eb8f34fd7658c75c6df4b64a1f096cdef538b38a2d7dc78b9e20ae124744eacec5fa3fb1a28a16590f2e021763b9cb97a5f9f7e97f0e2802a269fbed9b962d5ae5ce7c0bbb2a17071ef3d7cec11c9949ea399a56	\\x0000000100010000
23	2	10	\\x12062d34037aee2f0a12671bc5f9ec1358fa702fdd5829c9de765dad8a62de605abe3947f17ee3c643066e0be60f25c62defe46c5b3b9bc7d67f7183900fbf02	110	\\x0000000100000100336b775a8d90301f41055546099d0be1683823ff8699583ad918bb6d42f877a907c9f3762734258f1839935a819fb363f37220fec906401cd8087754a5045cab44b15344c02dfcf49bfc833aab1a7776e04dcaca14a776b010649cd88e1b5d9046d5b358811cd4dd827cc2385b6a390bcb59fa5ebc235998dca2aee650a3a6a7	\\x126efbe04ea519cef561f023e7e3465aa86fd9e7869f0ec9769528189c0f8d93af35fccb90ad3de835581e0d8e70785fa80527df4a20d6acaaa2f6ed775169dd	\\x00000001000000013ea9db4b3b150903b7472c6391a1f65d6f0d9d7bb1b02798bf7ff307689d7335fbe37370408103771f51981189e04edbd27751c418cc35aefdb6f7f0cbfedb2a89d509a8810f1c3d019c4f340c3e3612bba4e5e338902fc23479135fdabe5e5518513f3e5fc8f332cb2fb1d4af603bbc1eac19db56dedc498e75d66f7427b77b	\\x0000000100010000
24	2	11	\\xce0536718a494954286bc7a32d1dd8954a75f1609d5cb203375e8f4941c55649918313822180522e37e3f9cdf7439467b280d616da34fc72efa161f9b3f4580b	110	\\x00000001000001007cf4502a3b2f8121c38689a466b879c40dd598f58b29f045f2f1d91cc70e9bce54d668a9cbd7e66e53236417a314d35fbbdf5517a180c5affa58b16973826bfd13aba93fbc4660c66b974efc5076c56887769a53df6f300ce45cee3daa9f749f05274f7fc5f6caa38a1d89b17d4e18904c4e23cc01e9a1e37384afeb46c5a102	\\xc14b079bc0a0d91d05cfe83a27fdfac08d74d5024676e1007df4ee1129fb08c3737139963a2235823933287a8f771e4af9e74104cbb3f8b5e0e8ab0c035157a6	\\x0000000100000001a9714c22ed7a904b5360ca6bd57b178acee906522af7346c1ea35360ef25e8d79d853d12b6d12446d2ecb5d9e3fccffb3d100abda91c5c118d89434ffed61ba61e19a491d3b3ec9c9ab3d591d9ece3b76cfc46b30b69bd35e08c2cb685ceec3dcd332358f78e018c6701e3e5f7229f2ae55c4843dab796a1683a002637b2c5b6	\\x0000000100010000
25	3	0	\\xbb7feecaeb6875616c3a8972e7d64633c9a4be069f10dcd46f15597b3f820a62ff188a585f3653b45395adc2685628e02e5896624d1b6b472735540ccc640104	65	\\x0000000100000100186296c9ba7c4fd26f8f4cb276808a063d1e0210db5a9608ae36f96156c73102e40c8ebb5c3bfd1b8a57cae72b724ed73ae1f7fac2228e4dff04b86e8eba5b050661348594212e96820086ad5bd1f755e5f387178ca24545c14812b00758e48669bcc1e157882161d91aba4dacd71bd95386fb662f830dfeb0e426f239a536c7	\\x2d90001d48947927cdf2d28750092e0469cb0990964088cc44740018d84711da8afaa0b08a5c1910c2b6420f9d63b796a71675e0c9cf2fdf0ba958a553c4bd39	\\x00000001000000017106ac0dacdb38691826f0025243cfebca064f14882a6c7dc3196c9aa11d33c8b31547183e0376185316f8efe0f434a5bf2988ffd3d6f0e0e141252277504e879755e362ead5954be977e5d0e9333d4ec68e235473c7ca6ef5ae1138cfae4d32a520ca8d400951f240f388ec3b5bff556c1388a5071ff4fa581a960f9916311c	\\x0000000100010000
26	3	1	\\x29ea2516a5892defb83bd3756e85883763f57ac6950ea3214c9105fe85a3605fceb940f0acb7f9caea0f3139177d974dd7e5cdfb5b20dedbc161a0d510f0cc07	1	\\x00000001000001003d673f836f492772fc6c9280890af12c35c3ce65dcd8509223f5daa0c4b9b5ef919b9de82b4e656de1e217612e5bf514c1269b69285137b9cb9beb49b4ff74d382616049efd014aad69076d0db38eaf08764227e6732ca601cf9bf442567156f1b35f63268dafdcb21eab2ea23acc3f1ac7f1c92f5442a87e3978bde328b3b7a	\\x7dc6b60158f79344589b232a2389ad8ffb6e7f500665c54f2f5fbf171f5a2ec520603602946387a3fe1275020a1cd49d9c460ada1c153102e47418e8ba24cb05	\\x0000000100000001b18b847e06501bc96af311a8f63ed341cc1ca205277f9740eadba784442a2f656378d66334ca27da206abe418ca76062260c32d13231baeada8d7c15f436eddd879b895d19cb04625c0e9a4b027a33a4052394c3f3444b65ecb43c5dc83c08b2c3e0ee6a05f9bf05bb1c54f9c893fd65aaef81d5929b4f5401b64fc2b23ec9ef	\\x0000000100010000
27	3	2	\\x4f51869ee480c45d22b591246b3781fced24fa7188859b90b281577d45b3c0022bbe14376d1eeb13f57acfdeb9217a9d1129009841991e95b371e69a7d9d560f	1	\\x00000001000001006fd1d312f03561ff69d82418945da2053ef0d5254feeea3502423feb3947f1479e5a2b97bae900c0e1eec6fd7e0d5e14701e8e8165455841f67db9a6cc4ae1fb62beac601d1bfbc7c2d7854dac0097f4fa3e0741b3c0eb2a7e864c49556180883ff73b81517c1ec0ec059ef75f05758d3263cb2505499e377e00d681c5ac2728	\\xc74d574cbc5c2187f4d93215ef12a3d8ed7a41ec4853f91919b9acdffac61d20b13aa3f873bba76d1e7dde62efb64e8696d4e2f384f9c66afb92a69046d2eb99	\\x0000000100000001c4392cb035528223a24a1869558585b2479487cd0596c5884eaad3fb1f23035246ff3f21202617aee42d3069b43078948d02775e4a3e683498a84a433b077aafc32874b20432b58a2c0033aa9aef482fcf19c1b11da4c13dd8885376b9631de705b5c1fa06feb99ea613e0d366337ea901a37ab693f8a7000fa528e0bb109eb9	\\x0000000100010000
28	3	3	\\x68505345ac862c38e71b085ee5ddb7d82eeea77baf11ebe5b4af7c82470785f1936dc3c6748665be1614173504e82635ebd75cf9c070638cd44f4204f0640201	1	\\x0000000100000100a34791ddb69bd1764f3f0c47a9d16ed69bbe754095d2d01e0ec1e05e97e7c772952355e6f9b136493a6eb5c05b1ac3f057f1796451e7b69eb233663ea70f25b49999504cd6e5f0c7072f7136bba11c8f4656f9c607cebfcb6265b1e45e97e79f8015a552ecf82fd25618fb7f9eb2ab2cb9d3a83ff34ea1a82ea9da86842ee4df	\\xed312d0e2bc2fa4952a5e56f9d71b7fabba570b29c0c3b71061a4022678d136cc7fa02e99e7d673c795e3304c2309ab8d9a7a274ff67933ef67917d2f6156d21	\\x000000010000000186aa0eae16aad22a41bfd704cafcc07d5f8d11edcc5863d3096d398aa20a66772eaccf576143cb13169d754b087bf8a5cbc2b9ae82f460ff622ec155da8eb3d9156e56b84a17833879a4308cc69cea57961648e8b1d5de2d80a61f6c370942bd831ac23d1a49b36312599e6a59cdf50ac705a17a6a5d1d927254a70dd2e50f1f	\\x0000000100010000
29	3	4	\\xaedb415990666c6396706375f7c1da0319254367afcd8235c90fd24d2a139f584da57f0a055af82c2766850defb7ab955d5523eeec447538e6fda64daccefa0f	1	\\x00000001000001002fb8aaa5675ed60ded460a3a2dc767d2983aed365666602a2db888af56083fd4ca9452371a00aca88eca04944655f60892554e68a125959aeceecdb96409815d4bcea9fe6e580d6e3641218eb152e723fc865eff819b331c46ce54a02721f30d158a798ba24a3d6621733f34730643c72756b9e6f128eb20c2597944febda60b	\\xa2a9a11398d5be8bb128d908c085f58c4ef18613f18e0b3aa5584a5110e99d7a2d229f1470497d1d1d0160e20f0136ebd7a0db64ecb075ca284d2b7ab6a0a077	\\x000000010000000162136c9e3544355be9f732c463254c7a3f61fee38cc33490bdf0161b4b2e45fc2eeb1356c0a0f9031e7df2bf98929426b67340a60b3750ae506f0f5ba1b891c51f70183e9544c3719d8c0151708d8129e94db3368202e25bb300d27aa56f46c2fe881e20afe893244ac3fed3fbca84ea363f9527113fb157738a014707ef3326	\\x0000000100010000
30	3	5	\\x9c65e51fd6f01bab5c55370b2309b1af1e057aab7d17943166675f348cb4b61f7806c14b6db32da98e57523ec5a5ce753c3d8ced35e3656187b4bfcebc164d0f	1	\\x0000000100000100795cac84cde620336e6b008a43b4d736ad3d1b5aab5947958f50d21f4e6ca043e935ab13f7ea579f755ed79ae37440f24c362a558dde3439083bbee0a0d9652133922a8cbe5ece379ecb427d28220ba2c62f8cc41f049be3de0d99ce0b8c78eabb68675fbe09e689a333133d80cebc75162bde1b4c25994b96f7e4ae42fe958e	\\x2a8e727ee1e6549a48fb94af9cd86aa1d3c90d445f34114b4f7259e5d6e4563f191c72e4e12e3a4343c7f3ad8f38b0cbd517c3a39b5b30d8fbb873279dbfe55d	\\x000000010000000199a3046c32bb18c9d4895b8ba83ea41c58fa32953a88c58db855f2ff27a0d569fe11b435630cafdf67c6ca3ad8fe912df548cec308746532dd9d7becd45330b5505c8bc37ce88ac7eeecbac5603e98af57bc3ffe33567d259968f68e331b588d1e42f2b5c7cfbbdb6c8f8135e88dfe9165e73317fdd10870f5cf42bbdbcf6205	\\x0000000100010000
31	3	6	\\x4b305c37003e011276204d83f89b8dc4d788525b49a7fc1316d5d95b43d168fa3949c2f65c61c4deabb83cbfd06a4d3337d88954ba2516f46256b6485b59e70c	1	\\x0000000100000100a844cfeb33d2ee1f7bcb1e96aeaf7f481f35094f753a3d976583c7d8e761adca6668195d859510a3491b2f9cf948c123096a85f9ef04b8b342eaf42ceffe2d61fa4b6ef5f78b4a6672e11e6edcc1b30bdccc00ab1671ae58ccd4c3a3fe945ec900266248a2e28105b6c3f4f3776c16a441780250ccef59c049bfe3098f6f3266	\\x43cf8d8254acffd38c5e2938f11ded7a6e4230a8bb5662bfc98c9b8be4f95908b261ddcebdee617ea5b29db0e668417b7accb6abca5bd9864b10fe9f72f5b078	\\x00000001000000018fc029e026e036999fbb8a7254919a5712bd42667d7209d9c39a6aa93a4f50ae3d46c47b5187380fc3a4417846d34b0f51702e55cdca8f8a831c33fb28f787b856fdc822138469117e650105c77b92351cf2df9494f0b0acc66ddecc44bb92f49da6a05151dfcd49643bcb40dc2143af2acb277976ed0a3a4312a088d62aa123	\\x0000000100010000
32	3	7	\\x0fdf3622b136cd7286f64843c2047a237ebc19600aae1d6138e20561927fc2e1e54164e70de679581ae070d5319ef5c1f9484a801ba19e8a8b9eb3938a839602	1	\\x00000001000001002c8ab2104c8352acdfacebff43f927271eb7225c5f19367153cd3c98bb440daf641a10e43c38026c0bbb91dc840b8ef9877e040401d0646cd423e4e8afc781274ed86dbb0adfc7706d06e0320da823124e2e387929a102140d1663716f06e4b9a1e851797f64a45af792a0131039f04e4d12c1641b0654b346cad9800c5837d4	\\x1972f92917fb7d5a9d1898ef4dd13b02d7a6960bf6c8618b9bbf2ed5633927e1b20755196b16bcd72dbaad6d07fbb0c17059d7a45937877322eb03fce358f60e	\\x000000010000000124edaf0643667e9d3fcbdcb74e3b825a5510710e9e6eeb20752af33323e904aa50672e1d5448d2d3ed4740745db0546e25c3ba9933dee0422067d232679df8285d24689dc0c40b39704084cda4bf73a665ce76ec0b5fe44cb09d570092090f24eb4e94918f1a773b22c01b943809c8251e9f9c6ccde8deb7c62a16affc794b84	\\x0000000100010000
33	3	8	\\x1c11d8d3aca80b3b57f784c533c28f231ac6f773186e2a99f2f0e2750618929b12e5d9a0f0cf4fad875c3a9c9571822c22f87b7dfff1984b831f5d4ba2a3c708	1	\\x0000000100000100853f0a0ea69bf23c344553a5e63482c80434c765bdf0674569a8a2db4580a57a4febfd61d93d3cf5d79ac908417445c7c420120bcae6bc94014b88db9c3746c5e52825e0b6a6b82370484c233face3581563c2c1ce5037628018238db6875721b7b4fd3c9a076e3ec04bdba95e1db88ef9e9c35187c042b49dffb3b6d2b122ab	\\x47478d04c8fa61bd57207ff2fc807b37a95166eba38a1e6ca8a10350263a510bdee1cccd72b763386c32af501c64e0fbfb399b55b66bfe44b8ea0f234ada0d77	\\x00000001000000018867e5075c3f3b0611183081c8e4ebe267538062c496c1addb3cff51fe20600599bb893ed8bffedfbe1cf49c4c492d266737efcadaf5e81fef453e8580c7aadeccf9cd5f05dba297c556e883ebab2d17ced6e85d4d5f2543c614fd0c0ae6c390f2b0a2f9ab03a9ef45b86cda726b5b4d7a233a590dd96a073bca6f82bae364bc	\\x0000000100010000
34	3	9	\\xf3891096b4940dc92f3227c221e006c96366a6264c868c620bd32a0a9e5a0c296e5c84f45148c0c64038a3ea9be2f8fab79f2ce948181d9ff9abcf4c15c7450b	110	\\x00000001000001002296c1d548930c7f132bc702ff273e8eb78c3ddc3556e46575a942a0043f519c13acf81369281609a5368183cde0db897e95394b4501a506acb1d18b9bc75ae710f43c1e236f66cd93c4cf8da81230e496da7e5b482ff4f1660b852fc7af7895ffdb05a046725a734f8e4419eb1120fc3c8388dd7ee741f93ca790612d66197f	\\x035921e9b2ea7dc6905aff84ffb51d14ca5b383bb8a6c4a1e29de15059bb82e7fbb93f6ec2e3697ba21d99adaf249f4991ee3eab9f8b3c467ec63cf11d835732	\\x00000001000000012988251770575a954589f386b00d692425b60c534a927024590877281d1d2c0a8049d364c586b3773d5dffb1750d8d760a5b71db0c35ecf29d29981ba06eb0d0e1047b5d9863d3431755a7ed1e7ef978f71929a3f983c1dc0cc6f5657769c54b8ecef96141fc7ecc5ba9b09c2d3adb01a3765f11f38d2e00b8cc4348d1dca09e	\\x0000000100010000
35	3	10	\\xa1ca5731367f710113b129c8c1615f4e04b7f844b93fc33b4640d278fe376c42d57a24bfeb2c8fea51a17339173984d54cb04362cbbd0e1f3befda321f399903	110	\\x00000001000001001f99b220cdcdf3c09655a41567f77f75ec2836d9f988ce453e2f761cc1eaded38d649dd49509266061963d698d7f28b91a876cd61487ca69bbe1257f417bcf89d2a1d0d48872db534189e3b1bf0947f3535ecdd0a68849b4e1d30d3802a268f0c54242b759e30ee499438ab37229445701fda2c02ad31688a563f237be9fa85c	\\x5df778539f37959908d5a43a848e575239e58f5b693297c9072cf4e3e22ee275d1c81ec16b7320b30f1782617a7f510170cdd29c539889800bed03ec499d8fb8	\\x00000001000000019c2bf51de68d5cd561ec1c866b158cdb71ac15840ac7ff5659e17e4f334771a55ce67205e446240631f23563bdec5718f769a027b8a0828fa2f03c8f603ba68ed9045476def5dc53a73403c3d7a4a32e6ad3e1fa5797943365ec1156a370f85ebd17ffe93c69eff2412a0ef424aab08e0d4bd4558e0f6d730fc4a34d7cc15704	\\x0000000100010000
36	3	11	\\xa144803995b91aa82660a63dc934e6e1e59fac652c51e64c9399bbac26f787501ee6f8283a0800182234cedb5b382dbba64e9d6f4ea3845c94e59df524c7f70a	110	\\x000000010000010063ba27f40668556491267c61274289eb6a1712dbe5d32d90e56431f067a55122808c430be0e47554e6d142097cf34cfe04bbbb15e7a751b698d4e4b518535f0dfe953763580386d8abf1813b8495717534ed27daa08134eb4052d793260f58bd28d76ddff9dc4e7fbb8e9fe459eb9b16732f8a2146a67018da55679826e993fb	\\xc3819ea539060ac8fbbaa2e977370e154eb3ca318b7894ae38d68ee1664153d0353d6ed4b3a6b19a3ad2e1c8426b4d465962df1ad2bec1e0334dce28a8ca3f72	\\x00000001000000013ad6621c9e8ffb6836d858e380a3263bad056082d41df508aa456f29c76fecf979a5aa587417568d7eb75a5502f25b4a7c1ecdf8ab688efa66f42de74e135e032896f488baf32a0bf0df63cfea9106c5ad71da33d7f6975c49174ee1a151a66de73d286f46e3bfda33f2da2b3690551b1f1a12096f9fd6683e01c12e46bf5c46	\\x0000000100010000
37	4	0	\\xc85cff0bd62d986e8d4ea43c92fb48e133111e576b20395e85cbc2c355b64aa3a0dd03ed957c7eb885b06fe5a1be1ee326331972826386879af92a5f4a033c0c	113	\\x000000010000010058da930187f8965947d86ef676a5157131172b86bbaf6d78145364a8dd04bd1c45fda6436e65b5e7300d02c78fe7318a76b6681d9333963e87797d88675127d3fffedba1c5915e7e5a9a6628b022b39ade87296239f7da267d562c2869363c274dfdc2e5f649b8b3f4960943ab96763f16ec51bb6e92f7a6919946c1a79d8b0f	\\x761260306b03698ddd197dc2f2c8b8e4c1b658f5573e785386c5be99929b529fc7141a46808b7e928910dddd91813e86dc5ee654bae7c023b6fabe85f71aeb61	\\x00000001000000010cfb22b1d6c0f184ce1e38bfcaf78064a603ae4f837e6d3b72eff34e793430bdb8c7566347b2170d5c94931155b49ec678d3339fe8aab7e8a9d5afae26625cd27301d8373ed80fcd0f809648d77fb7e06d3def07f523cb2f875f306fd95056538244a4a3921d171bc605cf631f59f203f04a944c83c1a2b6b6432e6424503b35	\\x0000000100010000
38	4	1	\\x0cc3787bd939b4d5c315bdcb83407b41f08be0714ecf338270b45063b924f008364d099d80f71577e25250d816e448a1f43a37651eb0ebdf7925f6efdfe02909	1	\\x0000000100000100c5d4d94922d4d93408652654505ba73054d565e5d97df1c890efc286e151106991866f303f715e894df767a3e0410f0a22041d2d685901a929ec163bb84433658e4ed2908763d330ff706d67800b9a8a1f25b1eca2d59192763e2697a7215fc1bebbde2af33633abe0824150dad027b4fa32ad6ae0a522ef958e25c8258128a6	\\x812b8514474fc1c20fb77301359a1ce50ee4680859d6de241c62a0988eb802b46a10cf31d468283b76cb20309f8b70bcd4b1525c93e2522d098c6b474b2e42d5	\\x00000001000000016cb942f679b878032238e57c2ba267423b772e85cd6ac82655296f632ade7fd0895c6dabcf68f683ffba6fd41b79ff4d7610cfb6d0c746cbc48d4638a3bc41c67a3a8883849df269a72918bf300a1baf1e50d6e010e59fbf0b16a460b7ab58abf210b343b3391564ffeb736b3ccfd150c0b73f20be4f9ce089783c087107bc80	\\x0000000100010000
39	4	2	\\x8c32bb390eb3b4e4c82b596d59dc36c9eed14c6525c7de18d02765ac8315732ec998c56a47ee8d2b056910539fa92eda3b31d4475bdfbcffc0c4e601edf1f204	1	\\x000000010000010023c382cd91f9f32e537579f211fff1dfeadf79814af2a8db188a1be48509a6e3e713876f57075a24bbf7c5aee59472e0dc83a8ee301249531554d78f2d27071a5fb34f6af4ab2d9cae71baff2794dfeaed87a49a9620e8792b3c3345b6ef4b0291bd13ad8a2946af110b0de07b4226e9956b208d48590073ff310fe80c77bca5	\\x8b2ae0c88524863c5023a0b6d1147e798653915b6cd59048189ad069e944df5303f5306cfc4f8a508fe1d4dcc59cf20f96413623dab30804f3d84eabc721003d	\\x0000000100000001566afcb244ab8be9f6dd88ef5d4d1895f6e975139bfa45cef8d52915f56215b938704cff1838594260330f20755b92a3ba4e739e718c3d9857e7c9fb4b08a76e2be9a3cf5d4f7df0c938f520f890404f59f204f81caa8b42fafbf26065f951e6217ffd6d99b23763f36bdddf7359f0712e60ceb023572fc42c07eafa1a4b6d7f	\\x0000000100010000
40	4	3	\\x69e70c2a7aa6d2653c2cbb12a84e14b36dd7be1e177883dd5f077fe25e1306feb7729fc930396975f47d1e01b9ebfa856bba3abb30faa7e12457aea46c95e00d	1	\\x0000000100000100b0066ed61a20e597ccba2bdfe5196f4f72aa723491be1d526b21a0b66d739bc463b74029bf891cf4006f4e2fe23844a9c637eb37ea3134e52df740e19e73477eab4a2ad2e02cd2248d0dd0ff00362345f7e0ffe8aa347786efe301885a0a8d4671dc74602f10b50f0ae5ded83650c101aa6baaea3b8399c98083c061602439d6	\\xafc25d5704462e04f63b765d91061140d042b163e968fdcc13a5efd0dc2163cc1af4ffb40c2b644f2b147375ce25b414180d1eeb3de7c4bf786c1b866f06e5e0	\\x000000010000000155f0e548407db0f2b522e15a1df62049d4cb6baae4e0730ab8fc46140dfe08394f428935f31ffbd62cb179deca845dc7349692d1d58d2b46c213c825d96629c04148509fe13b7cce2b3aa5b3a66a7b80020a9577aa11092bbea8938b68548cf1772e7428c39561a8b36355d75f946ac3a67010c85d0aa481232916247f705753	\\x0000000100010000
41	4	4	\\xcb5dd80edfc34b64e110a694051f9c9e6e199a474e17c9006007f2cfc756b94c2d423d968eed4eab9b6426431a8bd97670f76424db9ba24a07cd8e687a485204	1	\\x000000010000010095270c4b5315bab6f42930d5eeb54140997776caf57cccdff4c9c959386565a6bc1e2ab47e52f7bbc6e80454da1bad2c658b6a587b42e2180143ad57d432f9567273788499191b25821632c3abeec69194c2ab4a982f9aa53c707b8ef85823986102fa7ab4d8a100c688869025a79c969c748ad31c642d227ae68c010c21da9e	\\x7ecce1d5ea8eae3a08fc0c4dea07d64995b7b928cd0e5d67dbdb67db410cf035de2cba2ff058e10d6277ed582e012d12b7eaa5723dce832d43173418d8779467	\\x0000000100000001b24662a8942ae96583ff71b0f713cca73261f1d20cb642689d3a2981f7db87db1bfbe43c8157ce99970d4b200be3b01c36e982565feaafe0822ed647ef632885be3e9f24ac5e4e648e4868174fe1449bffd2053290c3c5cfe559484f76903511143bfeb062109f212aee8ff487f41b2404ff375c296ce56f36fbc68156d747	\\x0000000100010000
42	4	5	\\x7352070519f18ae3706ef16adbcb4f4f5dcfd7c4b536fee786b7befa93d79bb0e12bd4d0672f9e5cb6dd70413903da5a48990e6f2ddf3494c5f29a91bf906f0d	1	\\x0000000100000100817b588b7da794596856c9ee33b4b2407f4e26235eb6872196b9b27a44d9e8cea4c4dbcfec62ee9f69b338afbf74c11f3e3888ab14e50f26d21f1503f234c24e195dc7be4b3cb12bd0663fd44f4a78ad1ddc05870c187936596b56e5b4f24adb0f837d4ead77307b5ae48d729d2c6bf527d6ad7cc5a9792f653c4ca394b890b7	\\x1d2aa388d6184351626323961592024b50d4f4b6f4f104534a842b31562f189550dc6697f42eb36d8946d2dba59457a0ec0d31ef79e2d2d229b08f8af8c2a770	\\x00000001000000018a2a51e084892f0f2933ed968c26e0da7da821bb681f2fd68dba66f057d2a49aef6d12dd6cf039727bb689c043bb64c94aefc26f8e5f8397960533fdb044927a27e9ac984e6412a576a2ca61fdf53ba9ddde448df273e61fa9e0e2eb4cdfa32f54233c9bb34759ee2726754ee036a005db547d461251b19415a75594b32ffd0d	\\x0000000100010000
43	4	6	\\x12f6400a977dd35ee594d55dec58020cf12308774890ed6bd8c0b7025c16bf3f80f7bb0c3aa4011c73004a48d2b562a1a65db85fa8a2974d6c67a0f8416b1b0f	1	\\x0000000100000100a56668519dd782c77d9f0392c4777b638a3d167b956c9e196a03e3ff6afbe75ec37dbcb7183042502d2eece688296269ecf763387e88f27c236e7ea79a1f6b372a410a8aadf72e7f9690c45f86222320f0b84b44e04d58d3826fdaf04271cacdca419b17eb8ad745cc40b3d5bb4d70702d5392b8548567a6086c0d418bf32989	\\x004450adacef666a6245037cad96b8040dcf78afdecb40fd80e3d1e19ecb85b592c3e9cd300a83ad49f0e9ebc1e0a61f2a36de238c33981bda2cff7fbe819e04	\\x00000001000000016969b076e82125a386c97967b6c2bc96e4fafd33137d2d9f0fe35a1538d3020665cd9e43e2d6d5a340c5781b16655349e0b9c23314781eab193bfa703ccab0aacf0b98661a6ac9c34ec9e0978dfc20406ef39f156a81b128578e0c572113231a9cf431cd8c053026d4a0a3f6eee48df09e02830a654e4b2249ec921d6adbaf07	\\x0000000100010000
44	4	7	\\x4a8fd3a866839bb09ad7adaf7f9576b055be4548f481528aff2e816efe5b152b49381fa6e55e9d541dde188d01e63e1c0232154da9d589ab124972c3d23f170e	1	\\x0000000100000100412f3f6769f711b0a1cd8896945ebafa71747579417d3ca3128be2d7f1dcc02d916ac5f401f3cc863162c3c64c989e909aa1d0dc672ac3e1f34126184a67940741f671cbebb943d8743e8824f2b1e8213ece04e2235b1847000ea5878c5e4196766db90b8bff48f9df1ac5519142fede965debc6489614c7c992eb6f274fa5a9	\\x4727d337ecedc921e9b99dae1f384d358ab0c5e7190b0ba3f5500dd32893f23df8b35f8124b91e625050aa0d08af1c2999b9b17443649e01a5af3d4da02456ba	\\x0000000100000001c2bbe3f1355cc65fb72b858cce74848fb8e72bea544d0eb17518de0b1ca471bf558508c87fdf039f232360281f0757bafdd819e2242a4ac3392b1245ec53b89107ee7998f1c24a6458923c7ab8482666e467ed4e0cb14af86dd9a1b23e60f0390fdc87e4582229ee68aca9ace8752948d23130897c6059e25d9540e3537c1efb	\\x0000000100010000
45	4	8	\\x623d05359c5b386affe5332020761da9cf2471e3a19a96342f8d0d3be96ab2b55a23acdfcdcbaae6c4d328660b02702253d65a65d22c5675ab10b15ff927c005	1	\\x00000001000001002dfac1b6be54aa140d2d8cd3ff760c519cb2051d806737faf5cf818fe113f564c5c027def4c6229bec5d70761fca23f88b245c3203625e2feceb54e57b0b6666295fc4a5d6e7e5d88bfa2c99a6d5f5226e50db090818bba1f1001af7e0518d848423876fcbec07b80e9745904f20884fc37656c3f908a8cdfa9dcf840480ee1b	\\xfa23592f57c112dbeea70f73b56f4378d9033eff3607ae6df0b1c1cc32208e3e7c403280d7228a289f5f7de2033f34e8e38d723e80a448d29a94b44d5365305c	\\x0000000100000001b5eedb4aeb7cc7d4d533accf3866917a47d3716cd9ab1e74cb8c55aa89fd78eac704675b88b1f13105d1580bbac20aa638f588cbaef09518725ceeb1d840040f45ce7036e35a21f65ff9589e29746a34b1e2ae2636668f2c050df9d648ea174f25bc15666ac6c124f6e19a956ef9bcd8983a6967f2e3416a40ea428e07477a0f	\\x0000000100010000
46	4	9	\\x53ecbb77aa04e2f71f4990187181612e44c41d994e29f20a591debfdd3d126d39c4af6d188c4a1182a4f8b540d433444a2114644231b392ad399cef9d2e0750c	110	\\x00000001000001008e891bee2851aaa4bc1717db0673421ef1ccc581075cb851fc95d1bfa8955eab6dfe5b0485bef09ddbbe3e03ca8d313fa66fd81f297f0f1084346906d6165302cd89826eb34549c4c9db73c8b90ef0f283580adbb6dbb4c3247db26fcfcdc82820d49276c372809885584eb9f3cf370b135bb4a07747aa03b71775f0bd82763c	\\xfb9c6ddd6bcd7a96e2c4067def3e9ae80b8eccfa4f1e5bcf7090b6260cb1d3885dcac032540f5e851c9950eb9b44d28db24a219da187180b12a340b22915f86e	\\x00000001000000010aa3f83f0919e1173580926026e0b35babdb19b7751ebc828059cee6c6fb8c81216e0843979a921f2f206d63b3e49fe2d19cb6db58d1c68c5fc52e84d38ff6150427f59c68d7bdf8bf0de8eb8785e36e196d485c8a46b82eb4337e21d0a475c4480352bba60167fcfe41849082c26a133217c631d7653c9a6026ac7366fea7eb	\\x0000000100010000
47	4	10	\\xc724fe4c792816214f986dd72437202fc3a45caaa04b496b43efa117c0ebb98a1789686e0968d66ba9317dfc5a9bcf5aedf20c7b42eae0061b4b9ea5e8aba002	110	\\x0000000100000100a4723b5c2762658ee326fb1d0195ff781fe3dded5ad688fe2b381e6a19c134c8cbf4b5a82eeb06cf646f8bd23bb84f4c17011cc648595d207c83ae7b67edae08621c259cfb09222c7f847d84f8f2fbc24b04fccd389e5a2faa18bb66b4c2bbebcb8d50dae85f74c046471336d5f20371c78a2bac614687c27a3592e74f6b670a	\\x821792e3d5674947ebe3e2f7c3215bfce1cc9408f488423021344ea93cfa0edda94e65f5c26706bddc432388984d32914a309a7c02ab4c6e407d841eb42ded45	\\x000000010000000169f824fe3e7f02777d40e653f4a72c6a4867e6f2e77130e6df3f5173b54703ebcbd8f72dde81f75937360b76c66b278d7dc1a2ce517d1bc829b90086bc530cee9bde7e8eabbe84520ad3293daf7dff266a6a6cbeb9a8f9fdafb8316060c55b7000f1bee37c6cbd32fd87e26ff069340d5ee8adc962fedabcb82bc7b85bf9ae68	\\x0000000100010000
48	4	11	\\x237a80a039c95cad9c621114f0630dd9ab323963ea7559c77a7266e8047bdf06fc0df4e9e48f727373d30c439dc334c2fd47295cebd8ad5c3e885279bceff401	110	\\x0000000100000100300810d3a231af6274db35da9219f344498580e8b2bd178099e17fefc132eb1a579b6200c80907532f557fc7051a9ee9293c691d432c130e790815d29b3e2543bab6168f0765c241e79f5499976b5208de0ddacefd6716c1ca365942e6f12b5f2ccbcba25a97316e906f2385920b0a5802b76b7da87e25c1429076e362b8401e	\\xe2058aa80fd9da49c334ea58734cee47da735dec4334a7c8db05c42aecda0700aaa000d8ad217a980da3a22b750444b49e57816e2129976db0ad6fdd81d83335	\\x000000010000000119960c891d6e03b06bdcf5531d15ecadada6b8529982263cdb6ab4380abd11afd3d30a9276acf3e4993be9a9bdbb4f51327bbaf990e85c1eaff165baa8e08ddb376d553993479232a32411ed2dc3e9729d23145714cb1a55c55696c76967b572133315a085c67c2b3256c5bffa8dbafdc2919033595b88a82a739a03f4819aa0	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\x6d20ace0baab040c1bc02094a9e1836f93ecf1bd60a7478683cf7e995838e746	\\x8018806f1f51770031077899c7989eb2c0ff3e1fafdee8b04caf8b260d21e812354bc6afd4b485208f50c384f9498abf52925d45c9734e2dab9160879b794f5a
2	2	\\x0e1fcae4830bdefce4155c7e4f5907530912c8928b73c4bfe2d2f0e78992e71c	\\x0747188b6ad8949635f3892bef5891c74feb70f62b10b244528acdc52f49b1135ee45c1d76cca4107baee1c1c553bd8da3f39818b1c092d59b1dac08767a5346
3	3	\\x0225ab1182a4683465c93155539b6468ec7969da3cdec6325e0f4fe02a463801	\\xe3dff8ee2bc89803b80c042c34d118ad0d0d520afac36531a59d14d4897364fad5910f3cb77cc4280a80964f6cfbc1060627bfcf8804a73b9b3821907b4adf92
4	4	\\x4b3ba608cb80424e8085de7029ae6b28389c70af075d9b51623c9d227f7de967	\\x9ae1f18f9b1c36b589184fcf59dbed84e22c3e155bab284560b8a7d752d1817929ad4b44f813a6b73143ccc99ea2d60c0a0278fff048792e2f3f3ba24959c898
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	2	\\x4491fbbed3ed92ffabf645158f62a3a26833f57231b2dcec0d9edd3316208157d1373fbb66c11f0528b272b1c744c7bca182d07ec554457000305e218d6e3f0d	1	6	0
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
1	\\x189f2aca45e60e2b78776e2007aef05fe3796d81c055273803d29d54346b9ccb	0	1000000	1649983822000000	1868316625000000
2	\\x5b09972d8d379db1fe211608466ced613293ac04ec2f99be932bf11e87c4363d	0	1000000	1649983830000000	1868316632000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x189f2aca45e60e2b78776e2007aef05fe3796d81c055273803d29d54346b9ccb	2	10	0	\\x5e821881dfc5c3b28e71aa34de91e4838301bf96e9b368f7acacb72cbea74774	exchange-account-1	1647564622000000
2	\\x5b09972d8d379db1fe211608466ced613293ac04ec2f99be932bf11e87c4363d	4	18	0	\\x2072df69b118068047feac9bd41620649f2d89d97cb61d65a23713fe4c277605	exchange-account-1	1647564630000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\xed84d7cd8ab15d35852f1d6c96be7ae4507f6521b93205926f5056c781b23dfcbb8758b2d242f20491ca92f4246706480544f30b6a54f068e2fae78685283e37
1	\\x06edc109f2abd6d39e09a73996b5b00983de1cf5532b20c781a622b84cf053040380ae52f4e965de9846baddc1b3f2c203b2a8d6861affb0cee8143f0fa1c5d8
1	\\x4527e136ff90f8504d8a05fb2eaa794897f3e6b6a11adb6b8561e8ad22aa0ae5ae5954245f02578433141859c6f92c5c7bb5d10bf05f0adb6cf10c830f9a1b2d
1	\\x160ada23e05e513002fef5f721a658abd06b70a5704526747865d92abd96acb95b9daa5f25d03dfc9ab9851e06a4ebc7d37129cb374a51fe89ff0f5950020511
1	\\xc8967299638a2b9ad042ee17775d6c31daeb090a8957c463937621765cfddba9b0771a3f1a2c66afe7c8885dd28787c340f34a42ade0d8611498caad14323b2c
1	\\x58c162912e244dbce84ee07c963cfbe2395de8b51d2c15646bf864998e668b608f06c4acb52c653c39e6aae88ea284e0cf763b016e37f57f3ac53d57c937d29d
1	\\x16077a1ac61adde0f2021b7f43b236bb03752a4ec82c1973ff09db23a33a6d585e04c621e5bc6e162495c0dfa6c7956d66b7ccb1351c34c2e31cb2f9186c999c
1	\\xe604b23a5a82399b4ef3bd4495f01a55773ba1e64fb766bdaa65516affb524dbcd8427bafe584cb84238683a151676919a9c57a3326dc393212e235785f88379
1	\\xd9e8859e64c697422e5985d3922873592ca93de81f8722ab3c482e4ee6b5048976edde26f9e86a5eb1d6244d6e10030edfa70ab1658d2b23ef1ed970dffb5bff
1	\\x677047e6136e003c44658ce828d016cdb5c7228236e9b7f8bd89518ce852f08674ba7f1455beb3f3a32334c6105204387ed11bfa53af4d471b149eef6d76b4bf
1	\\x266d960c4a23026e1061fb8cd222c9152b6963a2c66b786c4432c477c7c921cd1516dd35a3a86f782af7a9009222c303e8e0d606b4ca3dbf40eb8d209fe9b67c
1	\\xd98c6d87a2724ac80734d9398bbbe8bb17f34dfbd01e76a0a6388cae77225552a4f4acad97685037044368575587d82cef1289adca51c321b00a51a82dd83be2
2	\\x7c091d393d1a9ca92d38082059c9d1b8bd3c0de4a297eecb01fd70e139f7bfa74fe9116cea083f16fd60501b45ec8f42db95da62b3ae3bee14d4b5bf64cfb541
2	\\xcc1b2583e092865a61714579f0913443c383364bd88452974393bd5c332a99c7a01fdac0d7d837da9b2be480712fba7eef0ff93c007f01ce1bc7a72ba0387728
2	\\x6c11c6d3c6c08e4ddd2e9b50453a37d73af1adb50f92e7f188694c3952015fb22291cfb51a4c69c7eeb515d8dd443beb62e864876ce0198956040fbec6e12c4a
2	\\x418ca6ce6bfb72b0547c5da20196ec2be0a1ad17ae3d862dac0f37af44c0c95dd9dfdd08a77f74bc77db9a63a21096f5de4b0e9947ea0c64b954ad2e221e7d94
2	\\x382dd8beb23f98bea12b7ac17628460987c0cd53cfa8c602163dbe83e192af21cca1e4d9981a6b2b026da08f5a8286a39e9877e5ff9dcb8071649763a0c83707
2	\\xdf094ac1fc1b23162953a0606f418a89c43475e7926dedfe6fba8b9b9a35172f139c0f1ee7790a256b3cc6355e2f206e2f29781fc12578f3b4f5b4316f5d80af
2	\\x273b75ecced13c1d1be30529302319e1bd8221a688418019de8d188104a4c98da5be2a38520365766d92cfaa2c5b495e9dbe71852debf35ea5bcd9e286b1b92f
2	\\xf8bf3dd0ffb6365befe7b53e97be3dcdd8a2b265c220cb2a27e45b834122fecc1159074dfda2e399259c7ffe12abe68014cb25a692bd1863c03da9a96c56c699
2	\\x11dea2f1e447851ad8dab088fa2920d107f8337770a4b74354ffb9e008703fe6fcd24c68494964202b40eb0a6aa9135eaff576e3dabdde89a9e596e69b1cc918
2	\\xaa82f254961ad5a3563ef51597e5fb85c3a333a743cee5287f932876b7e511b55a4aa5b336eadbefb05f7f02676c4f324195c57983607da6c9ebc3965154b459
2	\\xc471e35b12d7f8a37bc108bd84019168ccf2769eb731beb11d42889687acd24f9e2f8e5dd9b74a2df07080f6c367464fb0fd31468a1c545441c248f3787f840d
2	\\x83da312da8509961cb9785e6c411de234fc6902919913a83361cd7c1a1a226b4815c63829b7dc3bac63e05cdf4c3d1bd522a20ee6ee5aeac5271de19d95b6ba7
2	\\x9e1ad1b895b15e7a57b965895f45c33659f8368585fe5840588cc9a21c5125e8bcf2fcb1b5dea85336cc6619680312f70d8a6b145ef2433f909f6225dd92798f
2	\\xa53454a97a0cf55f92209bd7f2a57b5e4af716fa284d36c985556abb35290885c7c5f816d0ebd8f9fea75f4ab013d7262718141e13f0f5a069520b87674adac1
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xed84d7cd8ab15d35852f1d6c96be7ae4507f6521b93205926f5056c781b23dfcbb8758b2d242f20491ca92f4246706480544f30b6a54f068e2fae78685283e37	284	\\x0000000100000001bf781b2772ac63d32b1cc1deb84ee804a191ac291b48fefd9eb232df27cbd7e31e933962b227192f470d0acf1f45a5593eacfeaeb1f1f39d39ac79fe31537581afc355c64f4df854b26cc7f80fc00fdd7bcbf843d273ffc196241ad96a8572f6a5906ff4e46592405a7cc126172c73a20bc1572c3176a2d942a0e5bb55b0587f	1	\\xe7db09d04495cc97c14b2aaba6a914bd5afb885cd3e3c668d926e713d91a8bdae21d2472de66b6f1aa0d7645a1b3b0f5ec987ed1e3fb4912724d90daa390d90a	1647564625000000	8	5000000
2	\\x06edc109f2abd6d39e09a73996b5b00983de1cf5532b20c781a622b84cf053040380ae52f4e965de9846baddc1b3f2c203b2a8d6861affb0cee8143f0fa1c5d8	113	\\x000000010000000109183f9d7aeff2fcf04bae6a4923867de44ab08ca47ece04c69859236649d527c5dfd6237bc5090504b78c756d3614a49c57ece266cfa80b6a3a2277b513df5fd09dd3ffbc22fd6b77c2f399da74b6c3078c440b68145b1ac1b2570c19da83bb75cd18fda17e5b94695a670484dccecd116cd30081dd7df6e2850b5208a2ff22	1	\\xa6192d9990627fbf77a713a2e59da84e8e4638a422c0088b4b4001b0cf529b94bfe43d65a1f6f4ec6e72ca6946f0e796ea6a0e60ae896bc51a0a644f021bac0a	1647564625000000	1	2000000
3	\\x4527e136ff90f8504d8a05fb2eaa794897f3e6b6a11adb6b8561e8ad22aa0ae5ae5954245f02578433141859c6f92c5c7bb5d10bf05f0adb6cf10c830f9a1b2d	1	\\x0000000100000001754165797ee42ed55256ba00bdb567722f490b728ebc982a0370eecd55614d5ba0a87595a99547fac257e8a1da5ee7ab6e936b8c13186a283bc81f733f6eb92783f37c4acbcf33ee9b242ca89755dbcc1a465b311b9b6d94983c5e56242db3f1d7e3310e3211fe7af4df78eac7dfefe439dcd847bb11ef3a90e91b77c53b5a92	1	\\xf9561431f60ecf2c1535294a969d5d123ad604c53f0402627aa8b5a07a78493db1b19d4b35c022e9d0fff7caba459ddc328c97f1e87ce8de60acc72656b45007	1647564625000000	0	11000000
4	\\x160ada23e05e513002fef5f721a658abd06b70a5704526747865d92abd96acb95b9daa5f25d03dfc9ab9851e06a4ebc7d37129cb374a51fe89ff0f5950020511	1	\\x00000001000000011c5276bb8bb21c3e2a85134876a6dec42feb92cc81d41dca73fbe2f72c9ed5172983e01e5d323a4a7766fa6743844daaff9d966dc593808ca8046ce8b4d48dbfd75e6c6ab8ed42e1570ebdd5e3cfbe28c0ccf2ecd060ac73724d3ac8f30cc853ac3503b3d8e13752260ca0a3a76b8f38f88f776d4e3b646dc6e8fb6cbee541b0	1	\\x66b6537d84f3698c24b75dbe6279635a4737f944af37a78e5d4e17cba32a56fdc01c363b61195c753d01353e4940cff3ac34be4f05dd66cab200e5bf6e52f905	1647564625000000	0	11000000
5	\\xc8967299638a2b9ad042ee17775d6c31daeb090a8957c463937621765cfddba9b0771a3f1a2c66afe7c8885dd28787c340f34a42ade0d8611498caad14323b2c	1	\\x0000000100000001910e8185c4d1c5ce608b9735852ba629a497ab5af801307460b0e2ab2ea5a5f04ba1abe9e07aa7ed7171365a64f5c09e4593e815fedad4a8f9b2994ebc8fa1973434b2025fa03b32646f6d2784275a71acbbad3c2a74ca7528c6a6cc8a0559fc832b432077a93c9e7473fb3a6fbb445602def9cbfc24febeeb4485317333f9ee	1	\\x4336c18efd3cfe58b1ab9c1bfd70c571df32ed6d595e271560f0ab25e12b2da4baa4192dbcb9b4a45c27d122512ba422749dc6507f5ae9337d57fb0b95d17408	1647564625000000	0	11000000
6	\\x58c162912e244dbce84ee07c963cfbe2395de8b51d2c15646bf864998e668b608f06c4acb52c653c39e6aae88ea284e0cf763b016e37f57f3ac53d57c937d29d	1	\\x0000000100000001152f6a1b318ad80e68ca34321fc694d837272b39b68d6ffbf077e862fcd3fa4bd23ac7ac051831cfeae78e7f33a6aa53ccbe8e4b2ced6df5d501f4571b0d8d6d3daebdb1a9fa05da889d9893915bea7438c981faefa0a267c5a41c0ebc47601a5fbb749d9251b8b97ab09cd3262ff71eba437d77c17d3396b92d4ca7fd8e1d62	1	\\x48ae63119aef73af70eb43f25f29cc7ccf440f5c448e5a19f1a267eb413baed8c4203b391cc6698ae2465756590f8ee9fdcf23cda4cccae94b6582622ccde00a	1647564625000000	0	11000000
7	\\x16077a1ac61adde0f2021b7f43b236bb03752a4ec82c1973ff09db23a33a6d585e04c621e5bc6e162495c0dfa6c7956d66b7ccb1351c34c2e31cb2f9186c999c	1	\\x0000000100000001be52d2ca16f871fd6bfd9b716aec5a80e668cf0c61cabb23609bbef5afbaa7bca3163f747cf719b2c0ab79694613e493c3972df42b0561bcda992bfff1654d546566193d58f7b1ec6ea64826cf075fabf6c7f2de9971930d9c05fb4b34a9bf52e5b0e80546a36fa83261f62eeb022b24af2218ad08ee6f73cb64b536caf88c88	1	\\xf01cbd3b2cd4a511007acd710b334b18624526582890e6f1e61f99f6052796c32347eee8f9b192d683606d11f2713b641e8f84090fa194ac254e1a1eb3f8a502	1647564625000000	0	11000000
8	\\xe604b23a5a82399b4ef3bd4495f01a55773ba1e64fb766bdaa65516affb524dbcd8427bafe584cb84238683a151676919a9c57a3326dc393212e235785f88379	1	\\x00000001000000011d433bdbbd140969ca84c6e5f3f737e135c32af654a0cb37853207901ebd0fce720f732ef63e7d08c168409db929a098027a52bcefc5c4750ea8540095bc5b697da7d989d94cdb10e5ae654213c3be478788577a2a5c69b337a0e31cef75c079d9dda7239da2d66f1b6231eecd02e1f2267f9c8751914b556d1f202ff37a675f	1	\\xe469765c4ec87e2fba3d6a8f96a13a5dc784c55ff347c5af47aff1f0826bd6c15c08f043a4505097f1ac3ff22dc60cd4a21a5a26479bd6192a6d191910b2f60e	1647564625000000	0	11000000
9	\\xd9e8859e64c697422e5985d3922873592ca93de81f8722ab3c482e4ee6b5048976edde26f9e86a5eb1d6244d6e10030edfa70ab1658d2b23ef1ed970dffb5bff	1	\\x0000000100000001a40d341917e94f2ed6ed746914ab84bc336aac58270140eaef56fca8d76e608723b2505acf0eed39c35d73d37f36b1b772b6fe08ae62480843ec63e834ea5c9f0588950bf3807606128a30460f01087a7a50b1d1e59fcf7228589e5a2635ea7c976934e6d7df78d3df99c9162b38219029b4389bbd7cbcbf68c489ca782f9f26	1	\\x714afd77cb0f7dfac9c24d5e14f71531e9aa1e6716ecf2729a96c751acd5b3c3da5312d877939c8d2286e32d68f052984a10b35461321c4ff890adfe894c1d02	1647564625000000	0	11000000
10	\\x677047e6136e003c44658ce828d016cdb5c7228236e9b7f8bd89518ce852f08674ba7f1455beb3f3a32334c6105204387ed11bfa53af4d471b149eef6d76b4bf	1	\\x00000001000000018aaac5ca99895735b975e0475396c06beded92181cf502a619d69c29ec5706c3ab5588d788a3c3bdfe38282e96bb76f53ca4cb15d214808f886242a9f075ffbe44e33b4adbc39ba9fe89e7d982b801646a16192eee7f9d6cc6dd402529ad94b41069f6217a077193ed03d309195cce86798b6216856aaf90dce87fa1524b1734	1	\\xfd61e8e7e6846bb73ab311f46883cd551a67de94dd4b06e78a41bd76dd352f5c7222972406c1e7863274d549d3ab5ac85ef7b2fab83ff4446b20c4f603683105	1647564625000000	0	11000000
11	\\x266d960c4a23026e1061fb8cd222c9152b6963a2c66b786c4432c477c7c921cd1516dd35a3a86f782af7a9009222c303e8e0d606b4ca3dbf40eb8d209fe9b67c	110	\\x000000010000000126eb516455e0b6de387cd81ee22ca01cde732cebeb17c2d365070817bed604c5ff3b3d9993e406627beec08c2b461c811d25e76481ca2ed682ba8205b761dfecd51d5a00361e4ef115a526978631772131bb8155ffd1c9616d2c38570794440a1a9d12fb8f05cda8169216070ba114e81f9ec634aabe83e9c7e0ceb90b542dcc	1	\\x29021cdc7e1b730c9a5b144ba1a679bf8d66d5484de27cf3f06aaae1a015216c985d910d2f9a6b850c8d8ffadd3b63d763238dcad7256c4c205d367510474d0c	1647564625000000	0	2000000
12	\\xd98c6d87a2724ac80734d9398bbbe8bb17f34dfbd01e76a0a6388cae77225552a4f4acad97685037044368575587d82cef1289adca51c321b00a51a82dd83be2	110	\\x00000001000000018c0aa410b24c5334c73ce5162df8b2f25b29990c839caf36811782cc19cf0bda7cc9bfc9f14233b93b87b717bde975ba0c6725531735c3899acb799f4a1685ed5679e273aa79916bcaa2c12638cc472e46c76b051e32ab1d38566e13ff40eea71977ad26a615ea367a39e2d459702c4f6473f125d6fa9f10c55029a3e09b8de4	1	\\xafcc33159228215367630cbe3c5fb0c38da32567f9ef808369f6af3d4b5bf5609377125f76868be9a25e2d8bb8a9a618ce1b74b16d9bab60ca3e89974f7e4b01	1647564625000000	0	2000000
13	\\x7c091d393d1a9ca92d38082059c9d1b8bd3c0de4a297eecb01fd70e139f7bfa74fe9116cea083f16fd60501b45ec8f42db95da62b3ae3bee14d4b5bf64cfb541	410	\\x00000001000000010f5155bb55307066291bfd64a211ebeb2f6b6443904d4257dcdf5c4f71452277146f1c451817f40cfb1eb769e57d1fac78c075d082d68cede5bbf1e5b06a8e8adf8c2ad34023cd05e2516400bee1852587df376e458ab2bf8bed3485a42196e95cf4b891fd471e76fe5422a7751a176ccb98854f486023a243aa43ecd2a61ee1	2	\\xcec26f7a89d50fce4252847cebbd00260b97aa4530fda4b471b96e7af0b1572f20fbf7a9267bdf3f9d10c91d344c1706172c070d70ec026993373de801d50206	1647564632000000	10	1000000
14	\\xcc1b2583e092865a61714579f0913443c383364bd88452974393bd5c332a99c7a01fdac0d7d837da9b2be480712fba7eef0ff93c007f01ce1bc7a72ba0387728	65	\\x00000001000000014593fd891d26f19ef35ecc50281ffc540d61f287605050cfdba7a230f4296dc7d8526487b00dd4c14e6a1ad88a084d8ed43f565c5db392e16add1c3fa2f623b93d3e769b4d3e6c509ecd2890e138eb874085b7c76ddcab14d992bcef6e2ebe3b161647a0b86c45ef0c83769491fa69b460a6cdd0958bc9d0f5d3374865fad707	2	\\x9cc4c329c1f1a4964dc23e0fbaf7d47f0035974a8d58a38e91248fbfcdc6dbaae2ee80699b14e72343a70b71b607e2ee23a198ab46de9ee2722cba12e0deef03	1647564632000000	5	1000000
15	\\x6c11c6d3c6c08e4ddd2e9b50453a37d73af1adb50f92e7f188694c3952015fb22291cfb51a4c69c7eeb515d8dd443beb62e864876ce0198956040fbec6e12c4a	197	\\x0000000100000001983395d0050ada929eecd34e0e5910c6f3cc979de6b60c87f76b9c78792f6eea6bf0c857a64b3fb726941c0fc69fad0644ee2a400bf9f1e5fb1fb4a6ea21311232d074136f53eeea8247b3386cbe2c0d50e5febe3e4b60b91cefbd8faf866720af6be30aa0dd6d53e04bb29bc60b6ec7c48e2ffb62314fc10c89c21908eb4130	2	\\xd051ac74b013a00b6f00e8ef4cbf5f27ce5fa3092e9af3152540636ec36281f4161bdcdc84ffb43340296346059504392b79f6f3fde8b06ebf3d695881bfee0e	1647564632000000	2	3000000
16	\\x418ca6ce6bfb72b0547c5da20196ec2be0a1ad17ae3d862dac0f37af44c0c95dd9dfdd08a77f74bc77db9a63a21096f5de4b0e9947ea0c64b954ad2e221e7d94	1	\\x0000000100000001141d559d486f3169f0bb9d1489c6a63c35699a7f75d5c52ff3d79e4565c878cd45e16af4184a56c261af93ef85c195397926ee9ebc198aed9e509035f42b3f13288fc4b443094c2e76f6aaadf8a21cbe9da0047150c65a183d3635f9f28e68ae9e80ae7bbb089076b50b368fbad569533af579c51a9f9722a1727b290ccf5ef3	2	\\xe91050412a303e149cdfcd058f7f40d53a4ac32661d2753d3ac2738d2d5b07b78336f00f6b464c3785cb51b03234a633f711802abb95369f343ed19ccadac504	1647564632000000	0	11000000
17	\\x382dd8beb23f98bea12b7ac17628460987c0cd53cfa8c602163dbe83e192af21cca1e4d9981a6b2b026da08f5a8286a39e9877e5ff9dcb8071649763a0c83707	1	\\x000000010000000149ed454876ba2f56c69b8b4779bbfbbee13a8ec8633e6202f11b03b03b6b064d1e5306cf0d690e05fe572366deec6510d1116f505d973813c39a31922723a7b283ab933a8efccee123c2f93600cb61ce67fe15d22d8ec431e68eb069c590f0c7cef14749690dd5773ba30fe0beacfed9355eccd6437a0a918906e396ca6dd12f	2	\\x8b597eb0044be27b92b9671b98dbb60c7cda5b025d074c11eb44da06331553d983ff5609de0579927c6875a116397aadfab1106b157e297f6c1bf4b25dffd202	1647564632000000	0	11000000
18	\\xdf094ac1fc1b23162953a0606f418a89c43475e7926dedfe6fba8b9b9a35172f139c0f1ee7790a256b3cc6355e2f206e2f29781fc12578f3b4f5b4316f5d80af	1	\\x0000000100000001c71916ad655ff2cae6b85726e3aed27a18c851e01e46be5d473d7a988d2d69ef4f1849aa207f0a14a640fa90848d17a94f35bc3cdd0f2b3d408f0c7d05dfc749dd5c19fba736f503df20be1364d30e725cbc2e55048657486101bc15155db90ad360b1d1b11a09af70fa44012b69a694386608c4475f77855244fe0472b45754	2	\\x282e6fa50a3c7eb4186dac73af43101478bbc679c2d8a1dba093ebb3050be93ccf37aad58d3d4bfed18e3b5eb4d945d58146f72fb3542911a67e28c80c1a3a0f	1647564632000000	0	11000000
19	\\x273b75ecced13c1d1be30529302319e1bd8221a688418019de8d188104a4c98da5be2a38520365766d92cfaa2c5b495e9dbe71852debf35ea5bcd9e286b1b92f	1	\\x000000010000000138b80e38f5e24ab8e3a30c3d9d8935a840f3b6daec4d6a4c84a387e6a555d117e3baa57a50a5719035270c95ffac4f3851796cdf4a4652a8cc8a55b0791b9f4cb9d1bc89fbfc6671a2358b1f34c77c9781d1da6b07246e955752522c9ad5a74e15564c2320a18c2d77af80014369ff87475474a38aab1af8fd642fe44bb0a27d	2	\\xf52419566719cc6c5235d18d3fae25963cd623b09c3f62f45fbcf0a5263196086bf500fa7b32958d6e7d862ac839f02d91e9733ed7129bfa009233e5246c5d0a	1647564632000000	0	11000000
20	\\xf8bf3dd0ffb6365befe7b53e97be3dcdd8a2b265c220cb2a27e45b834122fecc1159074dfda2e399259c7ffe12abe68014cb25a692bd1863c03da9a96c56c699	1	\\x00000001000000014ef4efded757f9cb39c8068724f141ce1c3526b84ecdc8daa6bc7816500864c837c9af703a76857224b537b1bbbd1b56b728bb88a95ada850556ad5be52230846807815326ace1e3694c643ae2905a5026f2db1f9308da194f3bf3b233dbdc171153a77cb927ba69d7e75381a34338fc635478392b6e3c3c6609f47a9d8e5cd2	2	\\xd1d73b9a50845e72995052b201c02fff15d0aab9b54077b193df3f41273f54d06a21aff2cfbb718e0bf617e4d41a778671f8438c5b08875bf8056ba80393f10e	1647564632000000	0	11000000
21	\\x11dea2f1e447851ad8dab088fa2920d107f8337770a4b74354ffb9e008703fe6fcd24c68494964202b40eb0a6aa9135eaff576e3dabdde89a9e596e69b1cc918	1	\\x000000010000000150578457a6bcc765dbad0016866884edba428fa61e3df0662c0900b3e4e5643a514cb5d2c1a29d8c15bbe26e84ce1cdd57ed9867d6259c7d4ec7994c73ebe7726009f61347358b5a88cd0e166b21e62982fdb1543c0cc964323c1df01300893213a2308fba7d409f709aa47951d06dc072c12a9804a857973cf4da0933abdeec	2	\\x31c9c08fceab2859581e34e1e270087c235d87bb32f6a737fa193771109c9fb37b4631baf935663f7d989679ebde6be6eb122d91dc6753f9b0b90cb40ec5ea07	1647564632000000	0	11000000
22	\\xaa82f254961ad5a3563ef51597e5fb85c3a333a743cee5287f932876b7e511b55a4aa5b336eadbefb05f7f02676c4f324195c57983607da6c9ebc3965154b459	1	\\x00000001000000017a68a47e2625764f2195927335c6d5e53196d91abe32cfeba3236a1b61661b2997edef2722fe99b9f04a1490258faf753e1ecee75a0e01a2b84524eaecc35f707f1ac287620cdad025f0d49d5bb76c48d583504c029ea49704625b2eb99d4219d67447bc51a724a4e1c071ffa2534568f01af46c0cebbb7a3ce49fc60102d8a1	2	\\x125e8a6c0616cf5cdfdd86cd10bfee83afae92353e28cba5e682145dbb4e7418e45af8b9ac55e0706b76f19472875f15e927bc85b596fe3e4e4a641d2a6a880f	1647564632000000	0	11000000
23	\\xc471e35b12d7f8a37bc108bd84019168ccf2769eb731beb11d42889687acd24f9e2f8e5dd9b74a2df07080f6c367464fb0fd31468a1c545441c248f3787f840d	1	\\x000000010000000172a2f97a34a8fc9491d887c7ab20f225ca0d496c35acb2b91208b36503fc3c4342205e568db99ce59d7d6473c39569b92ab373a42462a92656fee2528e1e22e1ff3d6c36d157e6f065941b4870173e986f0c44519c241964b7c71916d2a15634008cacb5a14120e8b74121467d368d869956564231231d1efbec1d0eeeec9d2c	2	\\x3dd3de243cb1d2128259e4bfdf49209bb38484bc0cf8fb66ee54abea6006a95d32fd11c2e0971e62a7ccc0d3d1845e510cd08ed62e706a7d921788fd6e3e0b02	1647564632000000	0	11000000
24	\\x83da312da8509961cb9785e6c411de234fc6902919913a83361cd7c1a1a226b4815c63829b7dc3bac63e05cdf4c3d1bd522a20ee6ee5aeac5271de19d95b6ba7	110	\\x00000001000000018c961924a2ccc37d068bcd9b3adce541e478ebd684553fa6beb38f834b83c3b4bc44f72bddfe4f754746ce5b0e007202388bc62135705d23e02e97aaf5b88535dff4634df7a0eba33eb1b16b75c4156f503fa22dca9701d16292b82d3dbc266499d28574fb036be5b731419c940d22b334d8f858d122196d777589f7ac2fa6aa	2	\\x1748f4a006a75b6565c1fa07bfdd6ab3f71c2a20b085d8456b0564a702e5c3a570dd25c14ddae55b8647ea45c36dab1ead39430d8c8592233912543f01cb990d	1647564632000000	0	2000000
25	\\x9e1ad1b895b15e7a57b965895f45c33659f8368585fe5840588cc9a21c5125e8bcf2fcb1b5dea85336cc6619680312f70d8a6b145ef2433f909f6225dd92798f	110	\\x000000010000000112d855be7189e0221fbcc45ad6771c73e8ea68347ab78303ab4279ab1ded57bd3a03d07c7e709e34189f73ba5d39e13cae2aa749431e75cab338d50f051f3cc73e02ddd436d85049f23cfd438c829c9a9c844845bf3f4b25b98a3c8771d61d8f4f9550f91d8015f8d0a4f5980f3a561a94dd4013e5f09f59a8e89c01c73d4fcd	2	\\xcc0be1e01936928920db0abcbfdcad6a067c3fe92b97ff6a9929e0d7b5108b300d8a107b0b26e1dc52011fac921b349dd725951893c59e0069666d5c3bd2e107	1647564632000000	0	2000000
26	\\xa53454a97a0cf55f92209bd7f2a57b5e4af716fa284d36c985556abb35290885c7c5f816d0ebd8f9fea75f4ab013d7262718141e13f0f5a069520b87674adac1	110	\\x00000001000000012efdd55c5cf6e694591d8a3074dc5b7926d2ad7b9248153addfaf802ed39d2fa10e6d1fd9e2b51edb1d3ec6109999363457d45a857b4161c6fda9214714bbd644c113294bfe8f9b9be9185a066102b492f3d4740ea03df5c01d10c5389af6d8a432650d518f0427307dc4cbaa6c46618492ade3feaf2a726d5fa164e4b71bc1a	2	\\x298867a42ff05319c6fea6b175d54778fc261dcc51a62643b6bd1a255a829ebbe41f4eed306ae864e1af1ce19c08ac7b46ccbe57408331fa458bb1e6ca4dd601	1647564632000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xc1192dc82042bfbead31e915206ab978160157b9e3677f0908313758d5c291350c31a094956446241d415c346dcb1ddd9f8ebfedee071d0ecee5ac17548a8a09	t	1647564615000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x2ed353d5b53557c9e7abda00d12ac671b361281a07d6da418991cd6fc59ee845a7d8b20ba3315c87e48cf643c5ebf2bfce284b54c579565ecb07b3d4fba9f501
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
1	\\x5e821881dfc5c3b28e71aa34de91e4838301bf96e9b368f7acacb72cbea74774	payto://x-taler-bank/localhost/testuser-ikbigwkz	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\x2072df69b118068047feac9bd41620649f2d89d97cb61d65a23713fe4c277605	payto://x-taler-bank/localhost/testuser-0tybbkgy	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647564607000000	0	1024	f	wirewatch-exchange-account-1
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

CREATE INDEX deposits_deposit_by_serial_id_index ON ONLY public.deposits USING btree (deposit_serial_id);


--
-- Name: deposits_default_deposit_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_deposit_serial_id_idx ON public.deposits_default USING btree (deposit_serial_id);


--
-- Name: deposits_for_iterate_matching_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_for_iterate_matching_index ON ONLY public.deposits USING btree (merchant_pub, wire_target_h_payto, done, extension_blocked, refund_deadline);


--
-- Name: INDEX deposits_for_iterate_matching_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_for_iterate_matching_index IS 'for deposits_iterate_matching';


--
-- Name: deposits_default_merchant_pub_wire_target_h_payto_done_exte_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_merchant_pub_wire_target_h_payto_done_exte_idx ON public.deposits_default USING btree (merchant_pub, wire_target_h_payto, done, extension_blocked, refund_deadline);


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
-- Name: refunds_by_refund_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_by_refund_serial_id_index ON ONLY public.refunds USING btree (refund_serial_id);


--
-- Name: refunds_default_refund_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX refunds_default_refund_serial_id_idx ON public.refunds_default USING btree (refund_serial_id);


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
-- Name: deposits_default_deposit_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_deposit_by_serial_id_index ATTACH PARTITION public.deposits_default_deposit_serial_id_idx;


--
-- Name: deposits_default_merchant_pub_wire_target_h_payto_done_exte_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_iterate_matching_index ATTACH PARTITION public.deposits_default_merchant_pub_wire_target_h_payto_done_exte_idx;


--
-- Name: deposits_default_shard_coin_pub_merchant_pub_h_contract_ter_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_shard_coin_pub_merchant_pub_h_contract_terms_key ATTACH PARTITION public.deposits_default_shard_coin_pub_merchant_pub_h_contract_ter_key;


--
-- Name: deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_get_ready_index ATTACH PARTITION public.deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx;


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

