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
exchange-0001	2022-03-18 01:51:40.007798+01	grothoff	{}	{}
merchant-0001	2022-03-18 01:51:41.418207+01	grothoff	{}	{}
auditor-0001	2022-03-18 01:51:42.250108+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-03-18 01:51:52.151207+01	f	90bbaabd-64e1-49e2-b556-03388b9f3b73	12	1
2	TESTKUDOS:8	0PHJ4H3Y15WKJ6STT3E0CV4MXTVJGQH6VA1T54C9ZK1AHD47TJ7G	2022-03-18 01:51:55.7775+01	f	16448430-a225-4ee0-b7ea-b6e12d1497f5	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
f2a56b24-9563-4bfd-a9d9-a445046e2957	TESTKUDOS:8	t	t	f	0PHJ4H3Y15WKJ6STT3E0CV4MXTVJGQH6VA1T54C9ZK1AHD47TJ7G	2	12
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
1	1	34	\\x3c9098a38a1ca5589e220848d86e098b8978604d310260a22c992c1232ab46556bdf88bdb5d82a687d89373fa627beabdd0e5c0e5b524eec98161d6a9e8c9903
2	1	121	\\x6ea2a755b30c75c28bbbc4586d65eb13c60a733c75f34c6e7dcbe8125d97255ff5d2ec51bbf6c9b2cefb8b173d5e7917d3117e8a201aaac8e6239d122cda8303
3	1	181	\\x86fdda3998e432b224d04f5a834ba50ceb95790fb45d32cce303ae3001f235d9276f530d587f8cda58dec2877828ed8042a864ae661416e62aef84129a59e000
4	1	190	\\xa10bddd8de56668d085b22a7a574e9dc02d697cb7b5858a0b53651cfcb15556fa2ae88ba3b5ab3c0b9300abc4ace4edc319c7e118c35ea90e30a5e01d6ff8e02
5	1	53	\\xa14e05c3a7edfa7192e1b64f12fcecb412bbdd2e3bd4b22b6c8346ae4924eebd6d45eb7263c2bb0c6b410276b46ecf1b13980449c6c95a11b1a5494398d00903
6	1	362	\\x2d0ad7026aa060afd5b96792e64246f76e6d4bced3bdceef0c11ffe52c45781bc4936fc4b55ea104ad07626c451acb1e3bbd1a8d5ecdee61ea37a5f80b249d00
7	1	390	\\xf1c17a0d83afa8bec118017a0fdc832a567c60736e24112210e3b9c3032c305bff090b77a1e88d91246978f08ec151c5c7ce52759d9863d0825ebf411678a50b
8	1	392	\\x325422fab2124dff64421d0b623c2505bf171903ae24ef631125219c960ff1a852497f14a2f00386ccaeee3d4f9a1a31f700c94d92a4a0a2bf5e700437bc5906
9	1	45	\\x679f984cfa8d3320070229e6e9a505e33f6e090331378be10111f4f836ae4f6708eb0e01bc39eaffa9948c7822eb5f7e14b4ef836c66721e569aabe89113190a
10	1	102	\\xb48ecf4e5a4aabadccbb897bf6ba6acdae0a2f3cf03c350bb9bdfbe54206921f904999eef4b3276d1dd882dd6f5f235cb8958d6a7796fc9e8741093b5a2e3b0f
11	1	302	\\x663d34058aa6d06e9ba2b1b9d7b12871c0c0374ebea141dc5daec5ac6273430761dda79e839e298772726b242309780ff13bdb35eeaeb024c85c94df95b9720c
12	1	278	\\xe7e7f28f88524bdd2b5d29a6fb993a5736d9d17b7eb92c3c2768d1802da383bb0f3121d2c41abf9276d493baa505c95f3773d7416dd247b6e0f2f39773d19202
13	1	188	\\x20fd0792c10fccecdfdcd67597cbc4eb6032134006beaa2c24ab605e526f85fcc2d935c8745e8109fb4dc3f35a370e21cd3f2d9fdc29d92eec408ba5f853380f
14	1	125	\\x138f43d0a0d47b0047e1b4f59a1688757cab0a6962b09f5cd09ce49415e7c40174ab4a00acc56af7f14d28b80f52fb1da0d62f8463d20ead26790a3f41df2e05
15	1	259	\\xaff0f9b1015ff3e39c1061e3d582d6bf9488a9dfe0f0fbb2193ac3abb9f91599536561ae14c4462e7319323de03143626db892de53dc444f89686abf190a8b0c
16	1	242	\\x1bbd065008d5554abed30bee7d010bcc697cfbe49b27c1e50debafe9dd8aa919bbae9436ba03d788acc048f049c45d311eaa9dd59345af17c96f863b4215970b
17	1	199	\\xb41edcb246b37af3b12982ba46513bffd6ff668e095c1c653c4fecbfc7a1548661cf0af605783cec37e7a6292f0f1ccd6a92c658ee0a3f15d2877cdfc13a5d06
18	1	360	\\x35c06dfdc45e085ede323239f8217a487506557c2a158dc8a1d429ab36101bf26a8ad29dfda21fea4a69b2fce0103e8037a0faa66dca63c35eadedb94b25e00f
19	1	285	\\xc0388fd2a100f4873e38cdc228aa9880ac3bdea019e4abef5b6261bdb21437e925cdd9dd40fd8d9bfba1f31ae5d69ce6ee9cfc9de1912cc7972476b374787203
20	1	377	\\x091da892e915f3e240c2b666951465ac885e3e7f979d9a03ec99984e725ce95692260996d9e67b67be3693dafb5953ab965d74e595fee351b6b234f7c6e26f0c
21	1	68	\\x9c62329d730d67d876613e1787b249008785bdcc525232d73ba55bca7f48bb0fb8dd9cb5f07ba01761d72e67fb01290b23e23ed07fbd185f9684efaa03fe6704
22	1	164	\\x2fdae6cbfdc2bcc3e590f2feada82386a17c9fb8aa2bf07274118083fb5f5be56bf92a15b0d4c08cf259f2f4b578e0b7c42f04aeb1bb4e8492c6430f72926d07
23	1	72	\\x798b1b8d854669f5b9dd8a23c4d0de445778070e37f222b9b15e6470ecc39ea79957f7b5b2cb345d35da376c1452c15612388b1df4625bbb5f8614b327d1ff06
24	1	112	\\xb6d646110c582852a1fb7ac567fa7ab9607a5734b5680e7955328bf7782769cc9d0a417cf4bf6127434e3214189f8454533763cbb4b6393bf0d8e0f41aa1fe08
25	1	239	\\x98c7abd44b9527ca58afe2f3fa85e7fcde30872d41cba2ecd50bb3f200feb7a0f0791f05d1499ffb9129263c2a565f91d656b4f032963aa5a806a5262d542e08
26	1	380	\\x9653bddbb74ab19af043c234b54ef8403c86189e7fcf0066731dcc10e0cc79d6c77f49479e7b85dd4c6d5f559f0f93626fa9e1e61fb8ddf2e747760d510dcf06
27	1	306	\\x59b9355bb2905c2f8537feefebf595978848ab8a675a31b13a0ba2cfa6813a866046e3e4397a53825e403f78635c1f3ca61791b7456373536eda07eaab1ad107
28	1	116	\\x57b56634d8a9b8a347b8637d2fe078f66a5734d65d141ea24380ba8a54566ecf0d6e6d2a5220309969a6b3e0449da94a7dd1450f9936ec6f8776bc8ac7418a0c
29	1	319	\\x2f980e0c5817530166dadd2455314db4bcbd40849812af6d60d1362ee49a4ecf7eb706026d807d9c839fcb56711ab4bbdd571607f3bb2c282074bfd1d129c407
30	1	393	\\x70a63a7cff86d9491e29837807e788b743b89fc45994c63ce4ce290cd6edd9210164be39f8a1270eb46ca554d0da66f9e161b660f129cbdf83d942a45f47c10c
31	1	344	\\x58ef2a1f681d6173f14f19fa58140ba1d27cf016c39797c32aabb3cdb2ab5191d18aa60de736a9e1806162f4aabed2fcabe4c9f6210d62331d02c3dbdf2a2702
32	1	221	\\x9d4a3d21fd9e74518ff4e8cf31ff52ba952d688ee6ea74b318eaf65c5afcf5a9d076d657ebae681634f1842295af91295887ab5be1789a7e74d6cf841abcba0c
33	1	38	\\x99ee24d9ef12eaf8afe309af61afc70a7237d380fffae9f333b2771e6ef04411beb6e74358f41914f9a84fe640ee21b4d6594cb278e68efa7ad11c4177a53106
34	1	328	\\x7911baa7f1492e5b5e1e38d3d5cfe601f8ba8623e79f4228009827310668aeab1dcf526aa7035c37cce0ec563c9d83492c6bc21fc4b81799037b0b69c1a7cc04
35	1	330	\\x26f1c6e26265a07f33d2f37c2a427f0020406198379ea4704582e9d2a0c9c869f68459409ca2607372b7ea4dfc9643a827404f4765a6a469a23af78362765d07
36	1	363	\\xd9c0302deba03b3648e2a1a0fb104a16dfff424f6c1367043c35a99116bb6ceb929f7f1a82a89bf44f6720bfb84d74e96c423b395b7572a68318cd45b0d91f00
37	1	333	\\xe9f45e20890bd1ff9552303acc4cd5c9cad2771d277784761d674a0ebf4685fd6402d5638791048347eb328b17cd634d575b9b07010349f9d415c751e1989408
38	1	354	\\x4f69daf7074919362fe96f741850c6b3bdcf033f284cccf1bc4856dffbd95a761c3a5b4d147911e9f25f588703780eebe8a1ccd5f9ac8ea4a5e89a4421bd8e0d
39	1	166	\\xa34e268a08473021450cb4f03572e3c7e40ea54e2c9ba447049b4e89fec833af3e6b79b74aae4ea180ae7120313c549ec8e811fda392b51260d807c057afd90e
40	1	64	\\x0a859ef9a3d3b35098d2b2d27b67e31bbfc60d2c98e996bda0d97625cbd333753e125912d08b73e1bef125b4cf4a7c03b17936a2b89c31ca67c40fb8501eed08
41	1	2	\\x5580a0eadd190252eddb97a19c19d7c0144a20436589740066a212481f48c3b0ffd56856264bd52792e2762dfe08606fbd60b27c179f13300ccfb8a22e644903
42	1	118	\\x2800bb14e5c457d27eb37076411006f6d04b08f9e620ec7c80a06502c5786dad9236e9bce97242aeff7d607c74e604ba2fe8db70ed90d90043d5cb1c7473050c
43	1	105	\\x0cccd47f0bfd56dbcdecb59019d5a3e713400519d70344510337033b52a0cbd39b08647165d93fbeeff3889575461388b3f96d350278dd56f56285862df7ff0a
44	1	346	\\xaa4e5ecf032403a787b8d2450131f6f7c91245e0db53cba94ca31444bf1831d7d19db4aac1b9b479fb77ce831595b7f999dcfcbb4ecab1c787cb19114a1f6504
45	1	310	\\xcb76d2d93ed978b1b0e3648423da0d6aed44971a12bd9ff8ca5a8f2e267dab885c932bd05f61488c94400cf70b105f4a447f71a994cb0491e039fb82e599110c
46	1	288	\\x6addda9828c89564bdafd48ee90a1070fb0649d77d16abdc3dd47beafd86485e815a3d51de6ff416bc12480d040ba6fc70a58935857bce4015dd55367f9b5605
47	1	345	\\x03d77b5e62dca3039b6c11c7b017a46f503de864c1b9b30ea9e091515cd40edb4ce6c2aa4def905e9e95eb7d89586f2dc7f3603e3927925fcb1cc710e0377f06
48	1	372	\\x2f979aad00892864ece8eeb76a6d23c1589349de960b5b48b162fd813d1a5c24760c2e7c2365538cbe19ac119a04dc5ac632024cecc9af7252d4e3921f298d04
49	1	268	\\xb0c953beb5460aeceb208067e390b9ee29751bd9dd60f19571178ecf5deac235a54b5776236d2bf634e57e5d951246800091245c95cc8062700d987703de0b00
50	1	197	\\x4cc03b83451294987220cbd9b36ab42399950c34c38a18fc7f82d06d10a13cae69b5d50f19dd0d1ef17f890549dbf5df402a18ff05fc9263884639b587650a0a
51	1	329	\\x46c117181f3668fdeab5ebd476602ebad91776264a165150cd5b0fb9fa977e52acab0d54e1b969c4083b401834f22dcc1aa7d09b418a4233ef961b925fdb8905
52	1	293	\\x031e85c753ecdca9dbe17ffa461722238791d498a0cfafa489df75893861f30d2e143dbab6fbfb2b2c00adc7d33f74a3c8c6181bd7e52043c9226fb9268d7a06
53	1	39	\\x9ced8956bd574c8cb99725ccb935a99550c773d4d5bf18945deaad26a596e1c1a9d6e65c853b41e6a87a8de5c63644d4e733feddbf25fdc317c8eb0ba749be09
54	1	355	\\x6182b68bed929c447e7907b2a42c9924c9807601e2240064e064faf3d1d9f06d42fa90feec67fb46ec07d551416b98a89e3e96a16ed45c1b129c3494d02da10c
55	1	3	\\xc408ca732f97524f3142a5db62eae28f3ff5c56b012a079bc583d09d1e61bc9de3b9610d25a8dda068426716f37345e1f1eee451568761628a17c44532ab820e
56	1	356	\\x22110e98a405b7e3fbc3874bd090cea241242ef388fbff4682f0ca798820be3e95aef745a2d876f9d770ee240b37ba322262fdb3fa1695d2b023b23d288b590a
57	1	109	\\xab4a24ffe78514f842b6d28cbd762841fd960471e2c745063146748037825a8ed7a6272d91aecfc7145aeabac863fc9eba3c1f600a2d578f9a24ce7410527501
58	1	200	\\x5e2c289a162fb44a8418010ef9c2d1414a62ce17d7c3e6b5f7bf537209625eaea755c1fe3be9e27454a3c86a4b61b26445fd378105accb3dbc7f89db7745bb05
59	1	191	\\x4b0d845f76ef42e22681fc796ec18a561065f23fcc8ea374d3408beebaaf7e22cc1d4e7077d054d0eb7b5f753043f8ba3e198d3cc3f4ff1b6bf640d3b2458901
60	1	55	\\xae25e1c8f8136d38c271bf6c3f8408c70a7d26f3805dd07b1183a83690eaf130e5400b799008107b99694c2587f302ebaf6987b653888f3094df77ff57622c0a
61	1	332	\\xcaa10cbcdbb3fe82c63a5d038d98af2d46a19b71fe16d25d68dc563207278c83fcb6ad94d70b08b1304404ba8ee2e7153f6750c080e9f891b526982206419406
62	1	368	\\xb387dba3144fee1c4e6a217aabb94b33c47fc3f8c062dc50a18aa1c9480f44d42cd18d1dd8f9ccf84bbc34928e2f292106f2ec1ae3a2c292379eaaf4fc6a8904
63	1	227	\\x33f506988ab09bf60e8d9835b1718c15559503dfde0816072a88ed28cdbebe2cdb610d580e044e85ab6b12852203fc4604f1f12b1bdb300edc93b5a649cbff00
64	1	233	\\xda2348d6f3b1174a932bb2fe68dd61c1bee2848f9a55ccdf4642b30caa60a9238056046bd9d4eedd951c81d31b9fd96f8a5728ae118e9fc131d7c420edacc701
65	1	62	\\x68a37ccdf74fec87436d0de8f0a03a3f9c6552943b3b3aa3b118378ccddfd9924bc9206204db17f8e798ca7762f76ad851cc059763e6b938f7498e1ed0314b0b
66	1	92	\\x032a4bea4cafa816272c45490ccbfcee1e904bb01905cd762059fab662624721c667b486b49875c43713db1c304342cdf4364f31afb8d82717c8794a1307e801
67	1	24	\\xd8e89e176f7164505721fdbd1ee3f9d8303ca2e7ca6704a3a9e3e57771a005f321312b5edb4484707c67d2371a0f70febfc383b2694f3eb7113e95d9f08c7b0f
68	1	415	\\xeb3f519988b4da405d3a60f4ca92bd5d53abca663054bb4e54af2352dfd22755ac63bd7620d64df41a5517d70920f6ffa772c2ffe0a0ccd60d6065dfda3e5e02
69	1	266	\\x07e5cf6a64e7b4b63dc3ff503697881385e654a12d88000ced4e4ad468980b7c2de305e7730dde984d00f22b9438b3694c588b3e46ecd517bd4a52d78b13ed0c
70	1	202	\\x7d085f9b92752893c6d7bcd4e0ff3c6c8d731eecbbce1ffea161fbacc545eadd848481adefcc92c3a45aacf5ce6db0544829b42e293b216deb09a18597790009
71	1	335	\\x4f26327a069e97d4e154e1d8fc39ee2da953e99dc6c2adcc0fcb84902452e65f37b982849db3fb11e00c3d08970f3a8e0760a694c722ee24bd6b2eb01301fc0a
72	1	159	\\x844de0aaa6037884067fa255c57dbb5b8682b5dd3118e5cda0e7e4e8acf3a39f5b10a1640285f0eed34ee2c1c815e5ce29aa9dba863cde6ee69298464a89a805
73	1	153	\\xee529309a640406d7882f6c90350dc613ab22fab973d39425ce24ee4ebf626a48dfc9a6f1685f153eb5dda1545acbbb5114c77ef2f846be3c4113f2af0dcad0e
74	1	114	\\x09736a8b3f88e5b0c303e9d24c8c21c0a03a1b565dfc86100f9145b28b08c8840ea4ac42b963f6d4c1965f298c9c1a27f7b4bc695d045e4ba7ba55b7d97d3201
75	1	93	\\xcc6649e3d8579188fc4f611d5de6f6996557c18c9aacc682546efabe73a736a724f78009d3ce399999d1694f93cf3c1f5c5e9a24518962ad4dc6aedc3fb57b02
76	1	339	\\xeae8dbd6bc952330f4a1aab43fd9c2b0faf284c202b291355bf36e48ae9cc0fd126019030008e90169011d812b8fec82f5cb234262d5407d4cd71e41232f7c0c
77	1	263	\\x10135bc117fafa8a66f43c838ff5904964eada46fd40ecfa4b5a796ef115f976b829511b3de8c7e06104dc400415478813356685831850569e3dee867f412703
78	1	20	\\x0cf0e296a63d9e37770b96667bef92de894deb12494c56706b88461f63c910ac46e84abd0def5fd385a76241a76085cbf47a75507a70a581f51f2e549fdc0a09
79	1	212	\\x536fd1735666bd7b3006e1855e35c258e4ceb5924b2f6e9468d9330ec3369b57b2d39a22f2d66d9d696dcb224585d65bfbc3d562eccf6fdd8c51b4d796395002
80	1	81	\\x5d7fcc2e2dfe81dcf633dc3c72388d093aedff65bd6db86f97b961f5bc14977c7216c845e9609e175432361f502a2f411ad371d3b88ee786a63d5165e01f6101
81	1	192	\\x3a900cbe7b2ab8c30275576e2416ecac0115fa377b1af0016db7a189375ad5f881c9a296ed7aee96fa8a647e772040bb64b9a3581d838f8c89700c6b5b12f002
82	1	404	\\x36dc8dd6eaafe52947cf0fbee28e8b17b27f660abba4054a6200a827bcaf91fa5dea9a2a1123730065b4fba2afb6b97721d7fa1c9d94dfccc8eff4c410e1080a
83	1	183	\\x8f482aef5c2983b7b0d9aaa6a2fdde43d1b528ce1d2b87fda9fe4088ed30d1a607a18a870ae7d6c24fb5b8f8a3cfa6a939a7f7ade21bd4c3a1d3a74c9f3a000f
84	1	142	\\x22235ce91348da5ef3c8935cb037c9b0a075fb040d602b488688304fdaa163c0b8ab0d60bfdf52cadf125a4ade4670eb56ddd134c1af4fdd611a579445a2a203
85	1	90	\\x5913997d85d982f408eb7eaac59948c0a9bccda135ebb29c0c54418cf8f0676f93413619c4ef5bbdd6a9812cdbfb48378f13e283bce2d8e6be7fecd23759cd05
86	1	100	\\x8f6e80cefa308bb930492118567df7f8cf180a9908094e996468719723d1ad50700879ed3d66a35d4149508206c546f737349f0e7f4dc24d1e6d01657e9d4c0f
87	1	394	\\xc1901449a03a58201d8a24fbc8d8a3b53c328d78b263a539b84539fbb360907117ce8a3da423c42bcd2505fb565e18566279c252b3f9bc4210d26a52be8c6d0d
88	1	149	\\xfc29fea7eb229d6447b0803e354c19ac80d77718e56d66e85ff3e5a9f5f6bafb65a03d8b5c062fd88d386bd384523a8c5ee413a679fca9c428aece39cb09f80e
89	1	185	\\xf6d26457808bfe9533ed938e88985500c0c1373d07481cac11cbb342493e6878a3fb07190de531af9c54548365f235782709e613db0d9180bfbe8ef8f657450f
90	1	308	\\xe3ab232a85d7b6e3da39fb53afbda862fecc2759c9ea5e9a2748619214cd1179cb18ee9ff16e23ad07a5849fb81722ba81e124bde3f0f76c837fc27111970806
91	1	101	\\x33101f42ba764a90e4eeb0617d81d2650c982a59c086410b45581becd4ba491c6c60bd7a768b1ab30cbd37728158dadec9e6f695fb4b666ef02a061baf254102
92	1	42	\\xc47981f3145cc0c94e4d218e3b4c1728359e9c33e77d88bea6da70977532a813f430a96ba6f74bf22f107498683018da3bdd2ea20750a633e1550a051abad701
93	1	317	\\x86c85f1446c887f20934b9fc8d463cd4fc4081f4fd28a842e6b087f0a15fff059ee78955f871d717fefde4e5aea5abc407efbd3b4d31ff4bca52265db1efdc0f
94	1	248	\\x2f9287d6a54f5e20749333c7bc1497544c85f90b3bd0323be21fa55fbcad3c9dae90031ba429ff179ac33eacbeb5e8627e62af04fd945a76bc94a1eb224d6c09
95	1	73	\\x1fc29a960c9f888d62803fb842b94ef1b62da7db6beabde6529e3ad4c8d95b5502b20d931cbe1a7a54796b33c56efcaa3210942104ae430fe3674dada5196300
96	1	22	\\x213c9a4645cc18d9e1c76aa9e952e0822132bf94da2cbe6c15618d84de99800cff299a50b6b9561bc9bdec5dfc31a83f4a251ccfce7fd14b4a1db25cc6cb1d05
97	1	260	\\x519baa9c90080ebf90662f6f669934bfd7b6b61700089168c54439f71ea6018cf38234be49e03abb51be791365458e162824ddf87f0d1d779e4afcddd27f5606
98	1	44	\\xf2644b684f13f8b10a9e25de15f837b7a3162e2c2e73980a0bc70246f1f3b07106567fef3bf8c0c6a194bf778ce4ca0cf213d225b8c781c67f1ace2f468e240a
99	1	205	\\xe454876807a87c7aa3b715a4e53c4f26a9ccfc8c0ec83e9c081c9b5ca11d051105fcf12d2783e6bc244d2d11b7534e16ef97b09974f9df14eb0659c03f279b09
100	1	184	\\x4fb0de1a992a3cc1a8290550a4288078cb36a263c03da97f2261bd95fa9741eb20a33700e3d0b3b3e0539fd0c3044b897e16eeb79f4ac6ca94fb151765bd710c
101	1	137	\\x8d7c50802d8f64b0868e59f220cdd09cafc616bd54cc67fc3c485f009c224df5429bb88b7f013441e1f7b83fded3b76da58e6eeb05816ba205acc3305b93450d
102	1	75	\\x8ac57698f3bc61629b84a56f9aec35b2e44ff2a32fdbff7a8c1ac526e0c01cee491a70d738df0b0fba9ef83719c6217433b0fbf9bdeccc06d308010139d4710b
103	1	74	\\xbc6ec6b1292b0a5716571951fc798907ba8c8a22545bd3cdeef27d34d2fdafcd66d7256762d03cb6f2df957f8557538d085852a60a5462e02701bd1078009d02
104	1	422	\\xf97a2f16cec6325b1e5a12863112c8bedb3edfdecac6c498b6283369733460a2e0a23e347d2f73d485803e6f00228cf0c631227b0e70aa2ca47a3cf5ac59bc07
105	1	219	\\xa7f4d9c32a6a80a30d0f1b7211fd3c445b9f46c2a71b7b3396032ed8cfe79a4217c72ef4eb6e075276eed5c3f478cbb0bde8e5580f640f405da5446d794a800e
106	1	4	\\x3f9156674c6c3d69e7cedd3233b7930537654e4fc88c3a4265523ed12ea19e441c30c696612842b192a7b596970dcf6c2db462a44d5ced56bff4ec85e3235c01
107	1	411	\\x7f9612f56e4317293c1f4bb20f87049d06578a7db68bd58d94f68ebf94128b2233d84ed0b88b903b29cb4480151439b2efa4124e6ecefedfb3e8b8925a8b5201
108	1	373	\\x7a4849530e679f2938b0a58a2d126811ee626f7b9ac1f4d2114bff3070daf50c3372c7b37d0da3a4c967a2a79eb7479da2555e7fcf66acea44663e78086b7901
109	1	97	\\xdbc914d9358e486dd49ae930042a728cb27339c7b817be049a42641440759b589d98f9aa28543fb5b3216472859bf271ea36cdfe11090b431092dbb0c9aaf103
110	1	403	\\x79b5cdd1efd7b7e043e21d915a08ec6a0599260fdcc432d3666209410da765cd3a8287ce105b66d42f522f07ce06718fbfb06ed13189c324c4d914e0d70ee20f
111	1	136	\\x648838e8a4d9c55df6d8c8dbfa6b62f8f5d1e808eb29dd8647df81f165a02a50f1bfd235dd5e3b00f39f75112fb5ced7800e2b74a4d29d4e3052e1a7d831800f
112	1	220	\\x46472a6638878dde69c8ab701040f146f79d0033b4a95747d1703eeb42c9a2b69695dacf1e34edc701ec0cc60107d6853d25d641b5929b62d840a8c85d64220e
113	1	311	\\xf8252274a09d61625704757aff1862c71c21577d8eef50da92d281eae52affb645e4832d652e3f6612b8b2423712c0d6c37c99b89f1c79a4dae284db1e710b0a
114	1	315	\\x4f86c658262a32e9fee036242e5bda2fbcf4848cb19cff6c80df6e0628dd9089e95a2af050671ae04bf2c97366b165ddcfd4bfa3eaf0ca901b9631210d593a0d
115	1	9	\\x966d5e776c5598b4c5ca48b398be6636af7d0177703e0d89983d814eb136a824aefb87af960f83668a48ecf0eb29967d90f9c2e3f2b00aca42f2235bb658c503
116	1	23	\\x730e3287f2b1bec26a8951835d1d4d7d7223eac771be12bea3e651f55d58ea1b413fb4bab5715912ec025650d6bb57d45c97dca5f3b0a53a41bb228f96bfc20d
117	1	316	\\x6b42bea4d0d06405eb73193428bc573089c754adc74cb86054fe8c1c67f454feb532e808c42a07f6f550ad5cebef4b73fca8303b449bc2e2b391ce8af2b44a09
118	1	218	\\xc13254232a59b9b906d7080b9880e27d83bcf02f0cc5a4ade63615af56fd13af985eb919005682d367033ef2aa90bd25d698e06df8001da9e4bb0cbbc02bb80a
119	1	13	\\x37623368cac7975b762acac38f8c854c2fe504c7270a8f73d9b91bb5aa124b055592f071ba0a914d9b68fe969c1bf69c449035d5c292cd9ebf990173af22820f
120	1	338	\\xa193dd0f1b8b983231d3f3a832a97172dee566808c2da43821a1e74e18a18edc60bd9e1d51bb02c81afd57b79e2a3aef1c1235e053b5e22ddc09880534fa6b06
121	1	161	\\xcdea31986cf38f467473ff923f328df1f5431fa8dccc270b126b96bd0214b0dc20c9d0a4645825219be774954b7ec448097bc2aad9fad6c55a4cd337cc8e420b
122	1	276	\\x290c9f1c36f595ebc0a7dcf6bfba1eae5997023e057e56c7c0a87f3ded8cfeb94ea7f6c48792fa6fa3559c0dcfa5855e3dd627a0a7341a6f1442dfa844840400
123	1	348	\\x0dfbc9c794ffe62b6dc71581022d9334955d9835c0f798537334ef84651333c850e7473dba2455373c72bdb9fea10cbb1494e251e4cca5970eb4cd3463de380a
124	1	386	\\x3568277382f0e832088c7a9df1590cfbb17f91f7ac7ae2e4f98a4c5b9c50ef635e14ac8cda95b81217f793fe98f7ed138c0029e89fc36f8cff37cd2d9a0a9a04
125	1	340	\\x1d044997d1b24d05f6cff0d329cfb42779233327a5d72a60df8295a58d205202bb13d5704fb91f332994532eade091c9c41147a3958206f29a0b655201312309
126	1	381	\\x95c087c82ee79ab9b040b80a38cd31167d57589479f152c664b003a9a10671868bfd22147c14f805cdbc6ddd336531ae908b50bfee1f88ba8d88f409e3751703
127	1	331	\\x1a9823b7ebea6fa85eda65ea315e4f37afea7bb71f1bb19c12770bcf224f1e2924d7004b367834fe392ab399f37cbca586029b537c5851d390d4a14c514e7703
128	1	145	\\x89edd67dc6e4e231c69d7e4f6a012be0fcf52a0759ec88c11f41e760435b679454a06759227239ce86c1f7606a9ccd9ca634b1514d05604e7a554a44b0c8c502
129	1	162	\\x554a750cc55e4df0edd1d89c7c21f6cb26b3e5bfd0a3f76d48f80639de024f77615bfaf2658732318f43cc779d7564087fa3824bba9cdbfeef5cf786ab068004
130	1	414	\\x87cc65e30dc05d002c6e1fd445f9c8cd6c12ac2ba40e8c1eaf632d29866a3afedcf2c9ab80aa70bb0713ce5cbcb56cf1e7d668caa1d38e5fe131b344fc55330b
131	1	347	\\xa18dd6e349abda9b0a1842749f4ccdfd5d14883cd94750c92db088f5ab306a9be9ec63d6ca7cdf5195046df0e35108927fa732f961a1de7aa3784ecf19058b06
132	1	25	\\xe86927a8cbc13980d87004d5e8a5c54c0062b73ab82449307970faa559d3ff4b3b7d9af820f7ebe5436fa45e428b33dbd70b2c55ed5d61dea569c10a0f5fb002
133	1	87	\\x5bd99789b0c795c41e08b45904409f937b0ab952e40a2dac83af16d46335848e69e9438d2029bac31f167cd9cbd44540ff71e21883731247f2ecdb3b7b8ebd0c
134	1	349	\\x14d2783ef8edd4056a44849d6cc12e722b2e2997945a3f4816de557082355324bd080ae377438743c03d5706487a1b699a5fd1257452787bd071742e31665504
135	1	82	\\xceb7ccc28fb3bdf70281dac8d855294a60597642843e17dce50b263014d74af7705f541e94b7d327725f8eb287d4d8d1cf593bb5f27a9f57531eb8a8e7858d03
136	1	35	\\x34e93bee7675f0350236468db4f85b6d1d4fb931d52d5a63543678a2dcb71f88b2b92971994fa86358c289fda7c1c22b8e8b60d5171e4e8b997d07f118d1380f
137	1	1	\\xc89d1018096d96d52d3961a4ff6e48988983a89ab0b53b426f8e83fb1ee985cfce90aabfcafe0bb2837a90e94c12c4eb1df9cffbda276c06d7ecba2e016bf800
138	1	178	\\x622f40ce7b457eec44657d207504c7b74e30d90215859ff5ed87fbc3493a0c56c3cbaa382487d007f4ab1416e790b2c6f0ccce471ab7ba0c781df33b60d46707
139	1	352	\\xe6401c012bb1fca87bcd79bfa9f2993fcc5c7a8e891ffc2048bceb82b6b57ffbe465f8e56a4adca6e14287be4b3e85be7759770a9f8e5799ca901578297a300f
140	1	412	\\x6b680802e05dd88212314882e73794c2f9018e31efcf087c317b5a3f5179b1f3dc6d8b88fff60f3f6d162b9673d361ac934bebf86166f3cd4aa3aef8fd6a540c
141	1	292	\\x0643bcbea43467c7d2bedd3e55bb169fdc0b984b28f023ca48636e9e6705752084947098b3b926c35fa4e9966cce7ff55ae0c60b1a66b4d77eb39dad416ed800
142	1	21	\\xdadae7eb87fd04b2810662dd78e39dd72769fe944f460af3971820d668b0b26396b17afab061c09e0ff1444c8742cb0c0a4766d0c43022594f1b95d0388e2a03
143	1	210	\\xf833a7a184862d947b3bd8aad0e3ad2a808f0bce7c8301efa6e2f3006182f6db2015829306cf2360f65eeb2885f3da4c9c345f270e122b265daf1df92101dc0c
144	1	359	\\x08657a3ba846305df7d3de89d02e171b20bdb73e2498d5439a8162943b2a1b9e604ba2aa3e048d96d2d028e31e05f741d0f7c91f5354fa2258178f96c06bc10a
145	1	398	\\x984e156cd6d7806751d7a9906ec4b5996b779621cef4e1289655ac76a10277c27515598e918708bb2c55d606a50b47ae86afead8fef4d94f3a9bfd4f5436b509
146	1	146	\\x0aef3629ee6d9f7d89aaf1a20dce85f613fd9e0db0a4c5df8dc2c646864da777c99bf964408ee2daea785e538647300f80b2ffbb32b52e4bd5e709348f71d000
147	1	63	\\x0001733a3aa5142464c8b448bf3308d59577ad19e24dc53f527259eab8eec9aaa353dc0ee6edf636c147e1a865f3fdaedffcf5fc9e918d660ac979c3be47960e
148	1	30	\\xd85a203f47f65f5a8a384f37ffbd32237d749d2e12fb119cee63765241c73005afccf4211201b0dbe16c303cffcee1acf1862dfb8a9817524c1572e91f95660e
149	1	215	\\x036abf7f9e18097bd5e4d904d142194ae0a3119ad778eb9e034222ee1586f97a7486e8516cd851ee615c0874b589bbc94eecb9bb2833a3233d51e191e1067c08
150	1	262	\\x1eabd441318db7d4746b2b693ae7f9db93b535da84b8ef6ba71415587477ccb9952a69628468e52f39da0385779a2171032579f7a14b7b84e7d7179ec16a4500
151	1	48	\\x89d8cfa1fd72a19494e12530407568190f9fc66d12569488d14f4ca587744014cdcedf960c6e1b7a419bf0877b10d8e972ec63aa1ea809fa628f72f0b5215a00
152	1	194	\\x5ee09c17d58a1d8fdded98eeabca4b5c3dc8040097b3e09f580e6c13e6356d4a43ff152780c6249ba5099a537557d037083e52edab95212260d262847a93700b
153	1	17	\\x505338114c3c1b8049cc4bf58503dfb87df9804ace81dc373f340bc971bc712965183ead378b84f439956708df0fe5706f8af91904274affba9c6e2495f1fb01
154	1	124	\\xf7198daa868b3b9957ac66b91a84c96f0aed339cbfd83be49a8093742a373dd9cb4a28eb05568bd2a271fff7e5c2ad872075582b49f3076ed3e596afe0c1e70c
155	1	298	\\xf69bbddf664a02f6e2d319c3062d8730bfc925e95655aa6f6b05aa5a63c715206a582946b1e308a73e48ee51e39fa2e67500aa8411dfed5f5299e4f026778e09
156	1	318	\\x9232ddd1233286864b6e687f4f5affad722b1150a8c1fd6e0c9338852f724171e52398771065b79023c26f79d19cacf4da973a5a92a618e813461135967e3d07
157	1	424	\\x4c06542bf07b83bef838f6aade5780a5908bacac5c602b0e4241915400ead90ff330c14f493540248e13d6e6d5302321ae2db516d6d8dde76f55775cf9077108
158	1	123	\\x07902cea79b69cb534bf0e7e0faf8040ecf91bf69606b30f9bdf2a6b628811b5d484789a7d8e6f6a0ad987fc218476d82ee51a2048cb0ff9bc217effb9e0d904
159	1	294	\\x820a8dc2f5fa78bdb4464f895aa625013df65618c2ab8e398e489b0b6fc9ad5b9de83f9b316cb9cebb8ffb221e854202af997dc9ae03e4e4893f4266918aa203
160	1	370	\\xe7aebd841d7e93d9ea5e3bf731574310b56dafff11228f5949b034dcfda05d11cdc32cd965eca40d1d2cb3b028e2d6c20eb7b7178112b89b1e4dd299b75acb0e
161	1	255	\\x9136eaf1788bfe74551e3bf01f229eb34e90ccaa125cc5e6ecec7e3b6c278994562501bbfd36976343d04f72a6c8a89e177531d78ceec335a5b521b60225eb0b
162	1	238	\\x81f0831766db00918683015377053714ae0719d90789870ea3f39f9852c301c58d8e8388754ea0077b87aba440410c4a6ffe533774b7de82fa956aba85b41b08
163	1	211	\\xc112a6b6d5463f3318ce111b8479a69ee15c6654dd856afe94f7ea3d1d7c95c1365bd467a6370305ea23a60cfbbc60859a916b9a733161a56b29bf796548b905
164	1	67	\\xb2152d79727ba3a5b8db9bc374d370c534b2d877b2d7a115196e2f8d9b17f769a51c1100cb1c4231d48a0bdf46750977a6e3f349dcd79892918b2590af06b900
165	1	327	\\x4e7f7bde3275243a82a1fe705652fab3bf79de290514769ca202e9005fb12b4ceb80f4d1aebce1bc0959607beaa7eab7f791fd90e77ae7871f64d8ce1fcde00a
166	1	12	\\xe21bc80184b477bd106a9d939e042674f1e404837cbd0a1071919b78ba92a7b28fd0c6a0893ff8afe8af9c4db9a1b2ccdff53140f48d8c9f826d0cc9c2541b01
167	1	378	\\x3fb1c7f54fcb9a324b827f5e240514b7234b278ac4bbee0521b6efadfcd1152bb76904fa18761387baf85f46386ef7337e0c6d41f842e72c9eea92d02bf0540c
168	1	337	\\x87deb708dc0127b2afa920a55c7254e364baa95a33a7480c6cf735d377fa4268227f5895fa8b061b9a14ba90eb67922da530ba171cf499b4e60e960eb8e99f08
169	1	96	\\x1949379b64885d53465bcf2678c4606621f77102dab19f696e657f1a4686bc842d8d071a5f4c4daf3985285acadf227fea7e929475536bffa6dcd034fa4de30a
170	1	374	\\x13f2b144501f13ddc31a124c3e262fbfac86627023f6eb7fabb0bff9473ae7d64619f6939365b79e90c7a4d55ea5194a80157ac4d09a1dea6568df1cc4c87c09
171	1	50	\\xcb7c50d1e306dc5dc707c1b15c3324095f1b5823b99f5a082f512d7b3675fbb3cabefab8e6cb5adfa63f5eeed17d415003edbf51a8ccaa1c8991fde6cbbcfe03
172	1	95	\\x316ad0eeecec11b44fb93d59ed6d5a049c5267384fac56e697fcdb53675bc1eaa927dd9b13314cabb1c7d59d28d73e41f2592a01a6fbf960edccdf5829512507
173	1	94	\\x8f4e6e6d1197db5566eca641ef20eac7827d2fca5a8c3acd186eeaa0eee6b46cbddce0a957b9ff9a2924a36ebab41466d384424d938389b434385e5800831a0b
174	1	297	\\x4d1e9424925cff9862f0374843a0356fc3d551f77a2faf7f00db9f62199b1860b20df5619fd28121c1f75f6eccce5414d2fc0bfebdb99d6e013736a8ba7eb906
175	1	229	\\xac2a864c0c67d659cdd563dec86967b0258c5b2742c2e3d4898a9020a84a33f79ff980132f83690bdaa3fc5f16d6498a544bfdd0e4bcd6366004a00e653bcf0a
176	1	138	\\x0ce20ba715744dd81915fbda5be30a2938663e3bcf95c1f55ed1e6bcd5a11d05ada1c68e8d9febef312661ce78538acad9601bfe1be3a21cc54f2593f2468e04
177	1	407	\\x7fa8b9d325af57469c9f8c0de7acba46c1d45ef3a47bea004f26f0e3d63ab0e49367e0d5aa71b4c95680e2c591002d92c41fc2877d74395625eae36e4d056a04
178	1	79	\\x880a1b0858bff3012061b134bd22400be6bb6853284845a3f8a5ad1d5f6d3763b5c07c06e70f5f1b2c6bac51f8a4f2532a75d213356f58690f34966912816702
179	1	406	\\x5826edaeadf709a0dddc8b34923b3ae465ccab22a94adc52b1f58b648c5109bf1899d3f0d6e6c695dbcf99d60ccc421621c8b8cacb4d7048a822d854dd404000
180	1	295	\\x02c34ce6bb5becd473ce9165acc5604daa5915c01ce7acd2bf3c9069635f3b57815a49587b0e1dd4698ff6a89838eabbd1f0b5ec34a543a352edae1e4792b80e
181	1	397	\\x582d1c08e4ab82806bc2cff70b0ec859c59d20b2346a44bed72346658fb287dc4dd70b33bc9c2bb907dbb9b3e9455f6f645e095c94c27f4e064b8fb41883670a
182	1	91	\\xe0674d8fa22de9b6d08e55d96d9f88418f2611dfd6df50ac426f3b35014fa2be615eb9c0368d24854a94522c4ad920b05c44d7f8cfe6cca708f4af7cbcf0150c
183	1	300	\\x23b6cc7926b2af642757e00f8e8066a4b1e53e461370317ada253b17502003afcd4fbed73d0cc54f6da0da34790de5780f8c77757a5e4529a5fcc12d749bb30f
184	1	383	\\x28e251e9f9b4e3d98e09ea1bd35e9b8cfd63642ad8d9b32284d0d03f83d63480ac1056cd5d433958602a58bff58b018b1a19ccf3fb7f2b7909d6adc0a4aaa30d
185	1	175	\\xdacce3f42504b1fa66d2206d4030545569f600ee59aa858c60b360e867173ba5a3215d629c3a39cc71679bbf2acd94213b84a2ba71b7f43b014a4bdb996cfd0b
186	1	66	\\x0e1501879b2c6f617016ae50e1b0274bcd840de0d57b6c356b83c9aee96ba1e49f360eb057d60528db0284cf97be23b4386a54b79f132cda70ea8c46b6f78a0e
187	1	208	\\xdf3f0f4825838d11bb9bd6b5d6e43432e42798006faa95aa8a4350a22186308b7b94ad181d8c3ae0cba41f3987bb9410bef57bedde957b18e97501336e63d102
188	1	127	\\xaded0321f7df89cc78bffef76371cefcf037f023057f8d578753938757f65d16187bf0cd6e233337669f491ddc1c6e5a1b4d7ba344a484a83086bc82920b1205
189	1	89	\\xad3a62b72eaf4e011e83a756c49961c24f7cdd2d5879c32748ab64e3bb2fc8a789779dbae09b524d4f2725de6f9f4f37579d6f57f1fdaab4635c140b797a9b05
190	1	257	\\x58328072d231603eb91f605f626abf215b5280a3b46f511f41dd98ea6bdab4917a9847b762eb3b787cf526a032ae7e100bc8269496c2096d41cf05bd9e93c60e
191	1	261	\\x958a4b3100d7efb1d9953da438a372a438733e1b545f89a64d9b8dc1408ea83a2dc39721a279a33d445010be9e26fadc304159cce16631726d966c3819f97409
192	1	395	\\x639febb2b5701f790e47e4143525bfaa1d52baff637378105e992b2d7563a69e4d203c0011ddb91762daf3522121a487ef32388c106c9bd8d0ebe2a2badeee05
193	1	303	\\xb470768cbe8572b73d07c57193b46ad3a3ab5864603a6fc6cf7cf36b44631d97668d7720a2160ae8a75ff441f6d07dd3f38382ac54734f5225156f10f995b30e
194	1	46	\\xdfb6684e2f8dfa2f209beb4f3dc7eccddcedee67e0935bdf09ff610db077320deacb95d28914fc28c516e42eee50768565e15c35ca427a8d04708f6c8ea67301
195	1	86	\\xad468478277e9d9e68e43577f8f00255a3b788596b06b03bc14421d85933ee145da7f91a00b5c8d1357310aa3514d964dd797077bdd1be8c8575bf8e55f7320b
196	1	353	\\xaa6894b9b56025057fc77bbcf8726cdc7ba5ed0aa9b657769e43f3a560ba5af382c602d93b4839345add1fe0acd33e729edc3721588f1e64f26609fec585f600
197	1	103	\\x17f680c5560ee9b88d365f72c853270daf62033d195930d249197b19cbdbcfc4e097c1fe22b396c72f5cf6b0d8f83e5e7f171deed0d1f69e7729ac68ddc3bb0d
198	1	182	\\xa73571a27002247501492820d6d8b0120619dc0c0471ab5018a2036269ee45ee0075327d4341dd618c1b4d985a40ecc8f300ce0b115d514e3e4d24c5af1fc705
199	1	170	\\x54e7639aa0d561d2dce182f4e858d03c887955af6bfcc21002171d46241a65a973f85fa9ad4e5086ced90bdacd5a65d5f3fb84830d8cb994dfc8056e5ffa4706
200	1	246	\\xba78dff7393ded1461fdd2c221b9c260397e2bcbe7cf1dba92ccc246ee523ed2de0db5cfaa8b5481d1fc19e3088c4db7515eede384705ec66db739c6f309030b
201	1	110	\\x9eba9f508e2c3e5d4b3e1ce7719530cd89d0c97dc6f02fb3c9cdc17944e08a56f974157814906b7fb0e01aa6e55069221289e0819056664c0b115eee265fe107
202	1	31	\\x1a5a09a78a21a7f8cee26e9e18516fb8d4ec165683300916933945781579ff67202bd3810f51bb6c87bbf50f39bbeeefcb168e11d2a080d4078daf118842ea0b
203	1	32	\\x026af718a619727962898bdbdb9ee047d53632971d4454c6d4884ecf49f9c8b60c95084725eea6b42e799eadb8f0f37aacb3295ffe037e017433c1c2dfdf6802
204	1	152	\\xea65c070f4b703f81128f337d36ab4dcadfb447bffaaa1f0c4709cc958e552ee5033f68b6765c2bedb0b1088c3d70a6f9cddd0fd58a73d4d7bd645824f430400
205	1	201	\\x384aee824649e4df92497cc54f785d92dc2dd64f40620f6d8fe84a566ad0e2e9cc666ff88a602d5d0c4f30d070b205587cae226976c3c452dbf8586d5422800b
206	1	189	\\x895af18963e0d83e79cd27271cc973d024710e130cf487313b64ce09a692029b54a99c324de8efcd0d6250894fd6d53cb2f7e8c0694f333fc8cca3012e1fc60c
207	1	231	\\x36c13f5cd63a28747f88b73e4590eeb16c0814b704758643127ffb930074d8e0422c51dc7d9a2ce6f48444c5e104404d42e0491492021779f0eb68d1bcfe9d03
208	1	382	\\x4fef8b2767a41e6b5230a5e941674de75834197cc0d7a4c86136dc2190577c75d56154604f6f68bd10179f9eef62935a21e4d5fcf1b9366b6bb5a8844db0f70b
209	1	27	\\xcb230234a3e0bf1d887bea28e657f71478df3d4d3f51470d4e7b40ba8f7a25590e40958b4a0895dffb620b69d049089ed90f72f2510365fce2e17ae0567c7102
210	1	171	\\x6f3e43fcd05ef6c65f949ae8f74e6d519353de0b0c5f0cfd8e7d77378efcdac1a648a2b0f34e0ce5355c1f5c650aa26ae2979fac8d0951990baa453b8ac42d0d
211	1	307	\\xe24fb4c8cda327a7c003115bd256749f1d560c5267a90c8f1c5b75b8cb2b5999c8afbdb02aa02e6636ecbc23039e4cded9704989aa67af2e7a89652c64104c0c
212	1	240	\\xd0ca2e2363eb24b0080330188ffa90d3706d92c1ac3027ffdca0191a3bf6d47319fc7ad1ad89b720efd383b63ea93de37fa7b086f0412b1e867a1da41728f405
213	1	54	\\x0668997c42d00476982b98958303b9e1b88142b4e79178dfb331a8d2674b75fbba8034625002c01496849e72d028f46fee58fc2716e6f4c215eb493c8511d80c
214	1	10	\\x260348d82a82d4f70257e06f3380ac40c4087553b2c37c312e17a00924036526fbcb025056bd98f6e45e748d4b6b68bdb72f2e6559b04e9328f8b7dd3d2ead06
215	1	358	\\x8d1b36555be0bb2d0bd482174ddb5c316542300212268a8effd115b95a2efdab69f5f7c9300691f244b0a5629761a7bece0c99d0ac4e1a04a59d8c9fbc8b1c07
216	1	323	\\x88db6dfcffd3effdba39563cafdbdfbc240a0952e47a204353151e19968b6da4491c87588940bd8a095688a3ef21ee31692425d2c7eeba6fb2b8bbac4d2e7502
217	1	272	\\x4fce1243e9126b214f8d8e58f4730128491808947746fd9cb91a1adfb8332854667de2cef5a26dcd68697e721e58213e01d86dc1bc4c9f13994e71a03250f601
218	1	421	\\xbf0f2c529ce05992c142ce42485433795824eb2781e685b58c29c2b19f41bce387bd4ca566941a20193788e364f9a94078fe7d918b16efa9b26b1069c703d900
219	1	104	\\xc7b5347d9504bcb412c42bc0ecb7c4cae50ddd2aa824a70720359a712858fecff2c86121a8d5963635228fddb3b1658fc9682bae564faeb5e7e5424ae4015e0a
220	1	413	\\x64d13ddc4f3871a26b8941f168d1b1733d3a7f30b23f42e76b227242d9e89c87f66bc28122267fa613c422a34bafdbbefc3913e3779da48b07ad2c0054145302
221	1	284	\\xc5dd55921c0b5f57a8b658e7314186dd688c2cef4daea045a0b4a3c49feaf66e807e0ef24ee3564a89960644fc606ea58d6f04bb99143206a4b2250d4162a809
222	1	282	\\x385ad890ecc598058e535f5daecf9fa818bf3153e65404279248bd1047887f1f9b8548e6e929452d45381a314066ff558770e628569425ee92038a1108f57005
223	1	19	\\x3f47a023a23d81af7a3acbe6cd49ade21283151f058a47a63c3990be060a312bd425f554700ddf2805eb60a7589836b2bcd1fec4fd34f4820bac0088e045b507
224	1	366	\\xba760f465238f474a9fcba1156ca16ae60aa93508f12ca7bdb04ecb8b7c1e21ec9e5ed42d1031909449bf4fca38438d1dc43eef3b4b839f15980ef7f0ebe6008
225	1	269	\\x40db6165b1a3bec1eff2322e137109f1ce893e2ac8af4197bc0f6d08c95f793dd5e6d4711fe86f4afa5036f7c5c471854dfd0d6e3d2976aa5ab704b984b2b405
226	1	235	\\x63205c538750ff3f0206ac5d8a6e922a0a8e1d665f56fcafb86dfc216aa20b6d6c89eb937c2fd8f909796462e443f5a97350751545e7ece3951392560c1f9103
227	1	80	\\xa530e2ab8ea2cecd2acca1fc160810bf81cff199118dd0de7db2d1a07df90237b606bc915f3d08d3404eaf93d7e6513be0365d7b0d669542026d92b91c9c8f0a
228	1	117	\\xf6e458079cc799af0ba32a01b2eca3b6bb2f36f6c45d1e4a4c89e5c33cec49e95ebfc274a23a67b8772f442a8cf1fe5684a63f2bd2c6b5a40f4250ec8249e003
229	1	206	\\x324dd61066f6bf017e98de0b27e7e16508c5297c16f5f1c3ac86c69a1bec7b3159428a52d09ba538032366b3849931073555a39f70d0464c4a1278330926c304
230	1	343	\\x195f45160a543cb6c1bd0fba63a521a0fe0211cdd3365a141c31c10bc7e0db1df42435d5f3ad086b7f9d0433ef680bd68c22e1fcc9cea1e89a344b2597854e00
231	1	119	\\xca544db87637ffdca550f6bca088a927848885fda2d452606ed3e45de4f5e486f6e76a904ad6202ca74b2101fbf46772bd356b2d5f6e30aa326b90e81d39ae07
232	1	141	\\xd403619392bc691b6d3f5a41621fd175b8bc3758f2a5cd94eaffbd505d6283c0e27c2cc53d424c7977ae2bdd0507405317f6e474bee37a41bcc04edb955cd008
233	1	139	\\xfddaf980d5f4631bbc8756c1c844bafbd13cb79ae307f74e66a980f8405bcabf966815ad8ba75a1d8565c31b0866ea60b5e597e88b787462ac488b8bfa66860e
234	1	281	\\x6c22f30808ad7e6fe1af6e6c3e17ff4e364c6e4a0149611afea4e699dfe101c0101a7294178afa49e9ce0f6eb34323ee24d7f89964c3e1caebc06e4443eb2808
235	1	14	\\xed8cebb907b42ba3f9519a8f8c4242aa7e34b521900b20dbc0d01161c8e1f61ccdf2d704b3f1019a68b82ef5283b3ed8540d84dc19509e92103335ddc809cb07
236	1	193	\\x75c2f448623394dda6c0533b60166e62607ed6fcd40dd562699855acf73b4b6b5bcbe24e608ce13e15ce6a617a73068c256ae36babb9f32b3b4158801c7c100d
237	1	133	\\x8b8420b43ec1aaf8914bf3e5ef371184636c008271cbcfa79a82316ab29b07450081405a0167290255cf1861a3f33ae88b3e5316e5cd46e53a3a93341cdfa002
238	1	351	\\x5a755a07b6a349cac887a27b4b69bda7d908d1df8d6d6f1051ad57078bca222f9d94ea78746259b2dde9a166124a456db41a01d6e7374a5286b5d51ce7026a07
239	1	134	\\x0ebe20bfb14960fa24f49a4a764656bf4aef6c5d45bf9a667a2ec03b69238c6f0df9c54971af927616caf0e0084a26c94c1777a2c8edb6a7b965cf988b6fd30f
240	1	37	\\x7fa9b9fe22f19f65d5185541be8b76c3223ec455387f9a804b90d83f49ee06e24f8f81b5ade87c465b93ed9efe817a5a01a50f476c62ca5fd1ae816de8ba9806
241	1	130	\\xdcf2aa686005458818d267a39de844a925b9af0a66aa6c20948f30d2760fc601818d7675703f216a854cbaf9a536abc28fda03ae6e74b3e46bfcaa2a45643f02
242	1	420	\\xfedc568d133043a0b456f2718557cba725fb35b59859bd1a1eb8df073a793c9fae501a8b485ef7cf39fc9aefaf94191c9604c1ad37d26bffcc51c31b698bfa0a
243	1	387	\\x1c3a49be0257008b13e23c53ab6ce09bcb8099ea43a305cf06aa4d421bbe157a5e49a0432cc1e0cb051d1bdfc08a8776da871c3fea45b9b8b6a8f3b7bf662b0c
244	1	326	\\x7a361f9c338d56eafde6356dd899219065badbe0cbb286d3ee763608a629760c1fb2d1e067fa28fa3fe3dc4a0bf66e1be3f5798200b60d49db5ae1d397328108
245	1	88	\\xe9dc5132b64a83011f3484d91ed6b58aeb8cecaa7aa69a95a88db718e995dea50bd1129d33d77a9bdad5ca4ebda5521b257f6cf584d336e7b1aaa3fd7f8be40e
246	1	419	\\xba7cf687bcbf8440c7b5b0a14c81a42ef50ea5a15f2bb2d69e3d1ca0581cc341d2cdd06fb8512b2c4034f3fcdda80dcb8ac3164f68107e2265ba95020e6a010d
247	1	376	\\xb27803806eca1f974fb83a7c80911cd2703a6339df5fac38959a96d47e7aa3c62b74df7e1b9e4b41f55873a9ae3995e7d74f6c85c6e183710087b1cd2b9f880a
248	1	225	\\x4bcb24369ba7860c26a4dc130ca0172282b6a78e53831165f6a345141a48ca78049b5f3c58f431d96f6640529fc08c5b671a65947cfee9beec29e9f2947e4d0d
249	1	43	\\x0423138fc46884a6fece705fd061d53eac144dc664d2aacd814a69f5b7aca9742e81fe9d27804383f78b3121050749b104cb93cfb903d9205119141f5096c709
250	1	150	\\x0eac95031cec4092b2b37c08700118f611b7ef0591cca4dc9575ddeb1ac4f2b534c3e7f4acf9bbdc938fb889e4636a61f3ccd39997b98207e69f9c2cf288e20f
251	1	361	\\x5fe07ba233f96387df04f0f5e59e5ca16b692085ceeaea0ca579052d6c787c19a5770dfb4a1b241ff8029daa1d8a855510af80b7dfb97e7f590489d145671504
252	1	279	\\x23ea075fd4ad22cbb707c18264be79e6091748d81306428da553d7ad09bf351662e49332bb278225b2d0015fe9f9cf63b8b825bfde3107b2ea48630d68d6c60e
253	1	341	\\x5feb1a8a024145d2af255d9957d4fd012b97227daa8c3c14c6b46d0c9fc5b414780d0cdf905619b5454e999679541a1fc9de3ee63d479c4e070d9908491a4506
254	1	57	\\x848c9f55472feda8eae040ffcbe72a5c7823ee9b27ea8bcc88157ea7e38490c9759524ff388fa82e445e3640dd4abbc207f6bb96cf52261e3c754a39b2551e08
255	1	214	\\x64cc6de2a2d3fbce8c35e247770202261bf61859f481b52f5122268560df80e535ed2c2cdd813be3d8a480f3b383058fc166fdbb55c7c0a38ac921c576986907
256	1	169	\\xdfb81937d0c0e08fd5a40d74a2127197aa9c134f7252ebfa6c8903d9b6dc9fedf79765c70c6c38f541e30a87b059d53e18e2c8b749fc4c735c3ee3baed9a2a08
257	1	71	\\xfb624b506bf8201c8b225abc7cd8eb997ce148148ac72d9b5548f9bc1e7f621901466e866773414e36b3646d49d333a238ade613aa685e34cf06836df2245404
258	1	151	\\xeaf32c8a2f973bf076c3f5157e84bc9636c66f2c799f68bff53403cfbb013e6dbb5421a53dc1eb4a10decff311edb94a8d21a167a26e827e8f2b838d15f95802
259	1	115	\\x7070b61a007aa8d50d77e22807e1eaea390395a70980d529df302869ccc8288a285c9e897a29dd61329ca69da9753470e0213467059064efc5c43fdc06b7e203
260	1	76	\\x17deaeee76c86b6697c018b5958eb7b6966e0f461a8e809b862357f435a7b9c8aa90b7c9393aec2575164053cbee81221c9c703f487419d94aaad53554317401
261	1	155	\\x5abbede8532440781d21918620265a7dfadf9f0f1d9568f5a0d407c89e09fc3378d5eec7318e05268e0301053fffd08a479f1de14b53cb98eacc1e2351081b09
262	1	28	\\xdec325cb11b1ef5608abcb7b172a931c51312e96704f2f7daed071d23f234a6353d0cb160cd64c40b21f0c3b6c0488eaf6ce398e620cf6fa7f65903879a6520c
263	1	241	\\xd38d6300259f10fa0ad31d2bb791893082546536851bdaa294e45549fdd3b5b3023b5ec7ae489699ff36cdc94ae45d971b0290830f15671658428e89337f8802
264	1	196	\\xe314fcf7719af8103bc29e67dcabd2e275bf4d99d9191b9c36a1c9f5df240b32b76c7b446ec0e55f39c90267b778c30c6aa58c59dd9c51977f1aaf1913a99b0c
265	1	301	\\x2d48b4b3285839f2654e96eb751dee22760ec24e152a4cd034b279c635e9d8c2532eac6a27fd79b168aabff98189205f7f6dae1b2d0cd3686b3cd2169dbe4705
266	1	417	\\x04d041fbf742a705e47778b86aba9991abd237b11d97392bf4dc54b20b08030d2c1c71164e7e20cbc10afa06b9a85d725f3cc12b4e6f1b124881b939792e0a02
267	1	65	\\xd3d6b6d6da5e6bc36764597af05bd4990f6360c32c1baa4096cbb227bbff25b6017ecc87e65567cd12cb5977c84d7811ec102a3377bd9ea3e4f2cb1b8b475300
268	1	77	\\xc4e921a0d5039eaa37d1288565b88f8e623c9102b1aa208a9cec834419514418f8625f94a48efb63fa107b1d79ba12458aed77b8aa09ccacccc2b3bbd6818a0b
269	1	128	\\x47d14228bde3d573090506b35b2b54841c0d35179c6c2be13e9264a5305daedbc8ee655634d9225bf32923214051be7250ca329baba70c41b65bfe89a9ca8404
270	1	258	\\x4c148a7f0196b86b069d31efc02a33c34b4167e7dcd7adc3eebf26d916848bd0a171468d3e3fbc2c77c03c4e1b41ccd8b5555ada99c590ba2bf40a6865552d0e
271	1	350	\\xdf78c0eed36c1fd47bbb740d3eb0a50a5603012f23cb990fd4fd40159c40d188b7489c5b47f90d9f8e5f32ab7b614607e2cc5db98d2fd898db9f2f05d1de6c05
272	1	296	\\xdb49085ed3a71786883335268941b4b59eb09b47c1e5aacfe78874df57485d19b2d2f260e18957600bf5ff1ccd22e764d31ad6f793f13f1c059b72c2e369f408
273	1	251	\\x085b5dda28d5b4973c89582c540dcebcaed4190b0d8a687395047f563cc6617ca508ca154b64f31a2bdc48e14cac104e0b1d515a25deb8a479bc7b6bbe79c307
274	1	304	\\x208ac94ae8f3173dbb7ae937b94744052f800cfd3df9a25bd22f09dec078b3eecbefa048f5c579be4a26deb1fa52d5def2e8ac6db99c4d9b51e9ebd71c25be0b
275	1	157	\\xe63af807cf317c698e1305a9f092e8716ff5ea59229b5b59f1083281184b247e6699456126559a693b7f8134bd15c487bf1f1b332097b951b7a67ed8cdf5b40e
276	1	198	\\x2e74a55be44a026ac0a0982d2ecb58599ab3d246ac4972bb263fdf255a2b2a067e5816b4a4c1ffe8d8f4c745c520fbcf614d845c67b38913cb6aa26e93aa1e0a
277	1	375	\\x07b9453baab0783bcf4a8736c7f311fbd75f1cfe07984e6b127c20fc4ffd6212faee412275c2a257997a3a4fc5bf33a55f481896c73c57b392118f9e0d7e900d
278	1	173	\\xd0e88c71aff25036fe12e060ae2576171f98000c122b600640578d94e53962c2d617ad13f917889c21cba22dfd6f50551f32bd306ecd3cae7c3cba89b6ae390a
279	1	41	\\x9b947192a3d13cfbc6361bd6cf7d33879e41886b1a81930528109c4140701c52bb9bbfe514317ff6bd93747772b4d5b64e52a69df46e9f85cce8e528029f0e06
280	1	11	\\x2bccf3a607d1c79cc8745e47379a582c60ef329df64486e30ff5e45b4ff36c899c87b33c4398e3a56fb95d85d62f3f3791e485299f1e9eca7b496c0c186a5a06
281	1	78	\\x4916fd3f902646e35ccdc71a2e4bb79de43a9392b8ac9b19dc799c33f54db5b5de5a5d7eddb1e7f2fdea1fdd1445a9b913a89aacddce36475ead1848caedfe0d
282	1	167	\\x89ae55c9380edc6e31b3e55402696374d8436a401269e64f9b75b31b30a195c7ebe2961d61f577bebe9fd2b9395de764e5c97e046c6aecbcef68bf71708db904
283	1	85	\\xc8bbf62db9a55d08912cbade722208abe6ff0ac3e76e6388ba9ee09f9eb5c50713ef2d388c1fd11949599b594cc674f9b4bccdcd2267b30d92d6a4f39d78c704
284	1	274	\\x1825b96d68c93c29a31339a9d94c251ab9bca17c4c3e28915cf3e08f6108420f281d48440114c7b3790fa0e968c069225084e61da7fd6497fa99b1b69145f108
285	1	36	\\x8c8eaea96a6be6b78367c0ffb55e10b80f3c85c5f1f8bc5aae3c37c746d2235d330f8d11d518e431e93d8e2fe100618085705dd43270be75615a3d9d1d04dd07
286	1	59	\\xb47337d857d4cd41adab87d10ce6694f4af37e8834ff03bfa3b85e59a805410f7203f33ebd9940006c03c44e7672d0976a207e5afbe5da39ec0ef4eab6c63604
287	1	367	\\x973621d59bb50b4d300a955460efdc375492bc414772f93dc8ea46ac4416b608b093814c6619a28a8778cf0e4b637c526820b9f2213546eabc2b309af0118000
288	1	209	\\xb8ee991ee8da2c0d24c1ae4280992e22038abde86e189d63f0191f42542eff801167d5ad0690e0bca926a119eef9ec5a66a1ab8746373d77df7cc90bc93fdc05
289	1	385	\\x00f26c0c7892a100d8d7baaca2631c2032d939eb7b48efa8a77e3c61580def383b6db83f2dcd74ee179a07d4cbd392d66d86f643b2d0bccc9d6c3700d6fe3c0f
290	1	253	\\xb201f245bdac6a464d4e0a162af1187151745aa5cc906468871349835a4ee7f12fbada7a05e455c11b09823b47655e1c46e18ea47ad152e3e726efe1151b0c0f
291	1	232	\\x85ed56dd327a359984e527f6a706a2134f04d8cb44d439206e9ce78f8786835778f077fe6fa4e2bdafb3327737169e968dcc69febe62663dc3f8709a6510e309
292	1	280	\\x70d58695becbda53ad15994ec2d512469ae9861a59763257cda61baddbbaf0b3a313a611fad2c032a5fe60e733f17d2545fb7b7ea6b9c04d5fb63d0a69e06e09
293	1	16	\\xcef1b279880eb3450dd68a876ae0afb9e8cda645bc9a4a344ce7622ccff9702c0c3a71a8f7ae862929d8da2e9e7242f36deafa5584d75e229cd2ea2de9803207
294	1	40	\\xe1a1dd4e3991955d7821dc6e1195e484ffa3960f5882d469f5745cfa3e6033c3bbe4b10c32719f83478638af9b1e04af21bace248787f9f5cb23693e2e777a05
295	1	405	\\xa116a2191da7fa47cd42f456959ac7cb65047362568e05ab340de27041d9cf1f4483da757e3b7cdb47ec940a254dc6780003d87d13102073f456f92b03df5602
296	1	69	\\x0f588c8aa5288ac7f9e921cda17916b05dbe3903e1e894d961251eca8a47db16a3972f8f689ae23d4f869ef3b91e8f8b16b8bb4e82e4710846215c174412a704
297	1	99	\\x37e3c4c289644826b903950577aee242793eb57385e5fafbf7947579b9ce240c59d59f24fa770e92c33c5c22d43392447661230cdc311e74609af42428465c00
298	1	143	\\x07e7a648644b006bc5e344f94efaf969c91e755e9e9df45cdeea5c478290c1922ffea96271610c66e72e3ddea2b9799b5de0ac9fdd17ff3d3fca879cf4cb9a05
299	1	177	\\x12fdf9318f5c26b070728753ad291726fb89bc1a0201bde59039eafc2c1531d75c6051e6a7fc1567910f05ba0cac254e8a68e7dcb79ef1a36e9db5bc1792d906
300	1	309	\\x6e4727c0ecc6f29c7945a075bf6519cc9c01b215bd5d8d768d511449b34bc2c1df2f063792b72a7e67a30af8669d7152a10cec0b5efcf3a06c49b3b44436ee0e
301	1	249	\\x270019b49b7342f9f09e1dd6bcf110a1f2870b9e84eb43cc330e7b3d5d75f42cd05d3f975a5feb1df8d02c22e6c0b965043c40d73970101ee34eb180c4339302
302	1	6	\\x2fc7b7d1291569de04160b9f7ca1878559c5a417369f0b5ed34af186fc9cbdb57209b1200d898b9b908c6bb98fcda482c33171477999ccb605f7f41a89ed010e
303	1	312	\\xc4632e52b857704f63e60d5c2203ec40072238c3776e321014f49f389138e07444fa7a8192305a12a73886235a64e6acb2e58832259bacf60f6e2d2f609f2e0e
304	1	122	\\xfcd73d02e3f3a273f145267a3680a10aa2e4a8f14b3ccb0e95f3437776f5d81fce712a05682b1c1b0713f8bd66c7453a5e4bc777f205fa22ba4ad6089fc1480b
305	1	7	\\x1a68f4856084579d56042854234fad49e32b8fc9362ad086d4f306bcd4c17fd41bf46d057ede0d830ee41f1a0fff023eab0d348b27285ae1cf3e6c1d5051500f
306	1	156	\\x136e216927f1d115805dcadf63f675c6779a0096ed4662579583e5f968f7a718098670e2508ce2dee553a9a9f7cb1e32bfae906bf67d2e10d309c2506d38cb02
307	1	207	\\xb248ff4fcc84125537dfb88a07d7df8c797d661ba0dd3b3bd48daa6908f19b2e569d29c3d22197d6c9e364241c97c74a27c0e80bf8a2ea708079effdd64bb900
308	1	402	\\x30ef0e87bb9dfbc005c3a010af4dc1911d208e65da9f187e9b4965e361c14423cb2c91bbbcb992c91e156b08b1729580d43668300c6001c933937c4bf5862503
309	1	144	\\xf7dc37151e9277781f285ce73345e37216e4ab7701f300c18dd9d12dd8a9f0bbe3ab041bd279b73844d6b69b5f3416f25ffa0e28fc1c09f0ea58cc47cea2880d
310	1	305	\\x87e6532f529137613873eebc25c415c0cb4ec596181b9fe5bb496c239ed99df5c6ea3fce7fc9af22bdaa81c944e450c076920da5f9a1e8cb4367f801bbb36209
311	1	47	\\x588763d10ae94a69976a5c64301707bdd0c4dce0f75223909bc0756745b014d6a8ef18e6ab2ec2ed60dc06e7fbd58a3783d2be949fcc7ef5dd54276a3bc5aa0f
312	1	265	\\x46f824a93aeeb636c7c31d53e2aebb683360b114eb2f699e97cf06da4823797a96145bc70c905c862a8f8dd01bc513eb0f2e2854a38f06770f71426b38955c0b
313	1	321	\\xa6b205ff2858e8caa92175a1938b3beccea733d0653bf8904e33a8cb30cf108f285e5a103b9864ab6d6f9502c33be486f40c960aea915905a111a5367c93d00b
314	1	371	\\xdf3bafebd35f6fe6ee471b13a35c7243261df6333c789d78cbd12aad1fbb9426d1499d5d63571e85e3fcc6cf6b6e2961e5aaa96bccd2b3d499b608e966ae5f03
315	1	129	\\x1f88fa7815a20ce1bd0c59d64ae10136415b8c789807a3b97c90d487078d43553f93bbbfff04f78620c063848eeeeb46e3366cb1fe49916124d63a56e694940d
316	1	286	\\xab2d240035459da88f69491c8bf0b3f41ca0b3c9f1b2c50445d5af6fd5d46002fa8293c687895d05f2230831fc5a519d1ddbdbfb1afff82b3cb2158cb5281c01
317	1	5	\\xf005c317c7ec2aa480cbeb17d16193d737864e777e59b881fd60ae959afea8777a30e57f0d29a739b7f319c57269b78608712402ca736e4e33499e81fb58a404
318	1	107	\\xb2ff12867382351ce3daef6359abca3b83978d9b39663cb375b15f61e4970a0ec75e2d68b6b090baab0dcd41c89c1e63cda3cf6e9f32f239e8366a324c767b06
319	1	61	\\xe83d061099eea7259886ef5306ac4bc90fb8a4d29fafb1478ee5fe63e562b73fe44aa4f3be0dbda5688d0a2e7f96cd32420e7fcf1d47c23222a1f1d0d10a4a09
320	1	396	\\xb6d771c112ea925e7cad8022193ca738ff0b336fa1f31a571b9fe1d13975f72f7e63f66fa8af9babbf98ea1ffaeae24fe9ccdc25d6446a1b402c72813a650f0f
321	1	186	\\xf0c24cd74b718b4fc6c057c92fa787f0f413e4d9f7ef03f5f5f9995fc0796a7e4901b4b37e4cf2aab17e2a2911fa4a3a0f74031bef51c3e2d8c802fc1c9cbf04
322	1	120	\\xcfe105fae93c215222b9fc01fce5e7cfd0a5eb99ec67c056e67cd6bb50a3e5ee27e1fba0283ea657c9401c30a3df3a6504bb0e5c8a8cfb2c4a9237cae2b4f403
323	1	423	\\x0eb714ffc00cbbc4f8461fc28ad6685a02b183f06762018ff86fb04c5f71a0f949e1c5acf5ca16c6e4c45f244ecd6e502b922670d4652bb4f9d25ce329721701
324	1	384	\\x5beb788ef3c10508fff0569e3ec761ad0fd9bfc109998c1832f922c4b7e4a902b9de69551bc02a75ddb7361419968055c6af4a244a3759169ae001cca182b20a
325	1	379	\\x597599fdeee905b27c997a7094adadb4215db60378e892e6912aa5fb813354b566078c6acf98dd08b37bba85e32077c4ee49c63d838a4c0442ce042adfbb4207
326	1	325	\\xcf69faa7e1a9426ab096a28ac512da638d3331290812c8639d2faa1d5ec60cb6ec6e6bc231af7b89b0f42ba5ac0270e4b8597a6eb2d6e3c42f360d2caaedb604
327	1	131	\\xbf659eb44184a0507c71077847ef12764ef77eb2998d2ab03d10c1c65ed51a0be66ed130c13cee8300b6c4528b6b81f3373280d6184a49d08e3308d98b788e09
328	1	52	\\x1ac3f9239c78c2c51ca4ab1d081447aeb45d96d17205c4c6794bc12b51d42689ec86795a10d73d8378d37add3f4f0810746b13c6a298ebfdd62b91c2bd06fd04
329	1	250	\\xda529bec0ada6f8ac502ba4dfabec6aacc0339fa610879a5da806b82d4316ab0f6f469a5258954e88e35b27e9b7d5b3fa9bca3502e1357fc1aff2e1fa3386e07
330	1	56	\\x497c1b6dc297bea4b7c95debeb5f4bbcca829a6082c92e11e9d7a9ce68e286b80dc67b6779bb9c06dcceeb4cdf46ef71613986f0ab016da8dfc2974b2a6d3407
331	1	174	\\x4f97dff159b11eeb891036bf9f6db3ee6526a7cce07e2b38eca667165e6815365cbdfb35daa91d3866b879824a4cd6ebb3f86b75521dc9e1433b67b11914a704
332	1	217	\\x2ab6a17f7e74c20090682ce85fd8e8722f34efe9f9aadba0e68f42cfe0aa4e1fcf383c112b58cb7168a1fdb52979f4b65090320deb9477e981e6d242a5418f06
333	1	226	\\x5d07057f135fa65ced17d36b88eedbd44e51ed0be0071ac685893bfb80a8c0555f14cd86774c3f9a7704e552d26bffcd6da3237f884be9abfbb0dbef06d41406
334	1	418	\\x595bbb23192cde3a955748fa30b5e2d1cfccf1043bf750cf6f5434583b912591f7714fb5c946be366afff9b7535a765638bbd60776cc7a6aeaa058d557406f0f
335	1	18	\\xb20b3405b466b7e1336803307a4286bf8797782742daabd255e26572ffaff95e7315f2082f5fb05c05aa98c5d836dfadd9abc368fd26ed3d5c7cfe7347e68005
336	1	401	\\x588a6288ba4835efcfcb73e05ec8790eab12aec61e5d523c5481506d227697a552b593145b2c3273f9af8bfe928e93c32fbfef332db4166d1691ecec7bfee609
337	1	33	\\xba1f70f36c8301c9a611204343408644e31c96686f3cfeae8ddca45deb32f4029b6efe901a742db63be73b1a704927429c63e1b2ec715253b9e0223e3488870e
338	1	324	\\x053266481d943f25262c0b77fdfb39e2f59b1fa847153b2de5a71f79cc0959d51e5f61e19accd94d1d8106a57c8935603d44cac4b5c02309b45e2031e496d80c
339	1	236	\\x6dfdbe84dc840ddd421fb5c9a7b8a19b491339d2d84c4447c46a83e53e33be991598a2f03ebdbd8f62ae0a4f604bb162303b378d27645e5a58b8cb27c7f6c409
340	1	254	\\x541bb954760e52f2a562fe4bbc6917b6d7551026265c3e7096c4eb7145d75932d16ab492b753706b4b47ab0d98a01df488ba3d2c2c746743f4ab035cd5a12608
341	1	58	\\x2cf3c82db0f8cc83c6ca29d536054422677005b360dedea3b05b6eb13bd91c0fbc11d51f0d0cf27aa69497a61e7fb7f8d960da69bf051b27f7d23dd8809f1000
342	1	283	\\xc53584d1a50d8d6bf8a9c9ace7c1a803dc4df4a1373c478997f117bc12c8c597e0708ea307cd31cdb2989b9f0355a2615fe53da422407158c257a1387d012b0a
343	1	275	\\x2472c8a210e742e844f4bb3b1e9de4ea83108fa028f8e6625cc7ce9b9fac57d3bc5f259168d9357b780770b8294bcdc544cdaaa9ea3aeefa7ec96007edc0230d
344	1	256	\\x092678aae1a5d6f5d0a5d5ff22dc66c12e32d11cb7ab3cf7f2857744589fce70ad532dff7e632a09146c227d0e4194a9c5041bbce6f24d4173f90d3ecdda9f0a
345	1	391	\\xe9577bc121464bd9249721bfeb7b6639e13d8282023939844052899e5464af65d019dbb2be1a778103beedacb8d13c249c13b2db9e1113b56a4a43bbf8f56603
346	1	336	\\xe6e1b3b48050bc9f9af89c8f5df8e1af6440acc57a39a9746eb8719bab1799a3f3c7b63ffcda2b604b80ec087162f5a18e621c2c55613ca575f929a524dadd04
347	1	49	\\x479e3ffb6072c59ffde2aa919a000b81a97a97bfc44b0eea00b3519578dee8d38e0412ae623f4e56129e22c0b0b7226bade65253c1d1d80cc3ee93767e73e504
348	1	51	\\x3acc7d4d627032cfa88906d3b3bc7ba3df9ce3001fdf99ac5da120688563e65c2ddf5529f8f9be6de6c9aaa800435a54f3bc7a2546a59f8ab33bea6097a7dc02
349	1	84	\\xab6e0d97740044e0d4912713cf7437dcb0131e61fb544eb803a4620bc5c410651e9e7be80ca15df1802ee8b61fe8e17badf0474457a8f902882deb095e16f903
350	1	222	\\x6985cf52889567e5b314603b8acc22a1b0849395b02926672dfb5d7320e56fcdcf0264f4afea94c89bf68a92a8cc8fed2e2326fe64aecf7e31d89b4f9b0d4904
351	1	245	\\xf026d7a864ce0dabdee80368a2b55362e125bdc943881d1e501df13a0fa01a188c21eeb3eff6f5b1cedc05b0868d59294d13af5273c7df5e665be889b208890e
352	1	267	\\x77f2643cf7c5e5fa64a0d78f52ee0eea77c8157e0c206108bcd6a57adbc72ef7e95e7379ef84a03da9ec7eb1f65148373f3e3947658a8ce32402201252b82a0a
353	1	98	\\xed57560d3e09ba75dbd5d858901cf4a876956b2a09f0c1e58788bd8d5a4cabf7f04c2c33d39f3c84da02af6b95f8dd9103436f0395e7da2bbfb3b5b4faaf5a0b
354	1	234	\\x8a131a15623e65851a624c3125842957e5888370ecfca977065bb9a1414c8434d8ac23237841e447cbafe569bca2adb0ef271033c2f970c87e8baa68fadc220f
355	1	237	\\x54bcd387a3b56a07d35da1cf8d5a34941dcd68dc16eade19bf9c17c5ee295082716b3a1096a1345c746521dc749417d8193df7232e161d37a08f15b80473840b
356	1	15	\\x41b72147fe2e7fb77832e98037dee2fa42f556affa9ed988777ccf2bf90f0a75ccc9c366daa391c0b41e91f7cbb98f390da63408333dea2f83baacb0d6fca604
357	1	277	\\xe34ab874c40083fb36baf4b3bdd0e2c21e47e668f3265d4e856c51d3759d959d2a3cd5e6b7387e4a8d3ea790f0bc25b766d93d65811a12a778c7ce6439d7250b
358	1	264	\\x8cac005b1fb3f3e98ef35df7c08cca63842a30b8db6b7dc171d09fec7294f88eaef6b219076639c9b7c508480214036b09281bb354a1ca49d691755bf49e2800
359	1	342	\\x09aef98649364903af9f739c35fdd5c7fc6012c118e118bf1529bd1734bfa7bccaa052a433451898bbce3cbeff471ca7c10e9972f766724f1bf895fe350b3e0e
360	1	187	\\x643b8df21aa7e2f0cb7358827f91b315c14d865af5c4dcf1733a78d12752cb932be453c132340fdf60531588023c9457eb191e46d78143be3fb47c8c5fac1d09
361	1	364	\\x7072eba9dd889d5e01911f93e41c1bf8e84ad680800504982e546ecad3006b73c069134818e12216bebe9dec1a3588b8d5dfeabce7bd00229dda8d691f20fa0b
362	1	334	\\xaf5414e2add01691231b1338dbaaec5939adeec0b53e9bccf01e51faec82fc06edb4b1320af3a984d7201d5563d4594e400e9f1114f662479105d28b403e970d
363	1	369	\\x6d34bfe088cac4e0eaf983e14aabaf7c3f1266a48f4b9df30ba8678cfb642bbd702d9da22c87013fe590e333cc1ea6b6ebd0fb5f9a440a38e52d3313967d4603
364	1	172	\\xe8819cc004cdede8e7200b72931820ea911c81cf2fe22dbfc95287a0ef1661bf533c1207499b436c7c0d006b38a79ce9f2785ca6dd0a1a320c55e14e9c68b10f
365	1	29	\\xa8a9a3dba11b8709c601e2280ff91cf64bf63206c268b2680f422c18256ab4b5f2f134bbe12571b6657d7aa8c6f8667324ccf099f3d00f83a58ad6f47e3a5b01
366	1	389	\\xcf639e8c741117f713a400c5269024d482d8837c99cb121be056d31aec18336bafa8015dd9198a3640b823248b03b28805d49a129619dc4c4a3e919dc40caf0b
367	1	244	\\x17fffe56ea8e1e685b1ab5d69e5ade9229ba220c61a225c77e036970419ea6073132d72c79cd68ff04d397d72480f043ca4f65f5d37695cea5a9da92bbd3ac0e
368	1	180	\\xb4dea7dde61746973534ac1fc3cf6835f8f1f7e38de9316580082a6373ab3e0031584ea10651f95a4b84adb56d48c9d52dad3439ea0252911cf22ee3d814200f
369	1	252	\\x16053073d1e07dc21b901083204d27ee68a237d475f6174f31399e3bc746a4fcbcbcdffb9795b1392ea722ff7db03ca1f1ee75ec68529cf54adacbba3707220c
370	1	399	\\x9fa5df54963f48382f34ff5784ee41c4a8fdb094495226d94582dbd69db2a986e7434cf9673143d2a3e3c244b47a999beee94426c89317f452210e7743905b08
371	1	83	\\x2e0ed214459331dcd411e9655e691d1699bda3bbef958e1102721efc15fce484dfea3e31a4beebbbeea483c9eced8a3c90dcfc237f196c20a1e73304bfd3710d
372	1	126	\\x82b4f03975895e6e3882bdbbd9621e5b9e9652fb138020b703c40c8b308b923f5c013aea9dc8cc878bdb8fd4906f959a7e2005750df8705951af58fba9ab5701
373	1	165	\\x3e5769f302c903ff2ce04d75407ae841e4cff36e2c21b8cc03bf2d675d89b1f147f7515588048b2c96b62a64e28cb43fb6462020b1ef55bd7090071189a9a303
374	1	147	\\xd39ef661094b8e6035dd1779469d8ff51fc627899d247f13a562e3e6b1a49b218f296897a8519cbc847d47f42c006dfd9cc98d5e8d1e68d51744f580cb310705
375	1	223	\\x88db17435a87ba11aae713b6ceebbecbde8bea8116d09fca5fe0298f915e8d20cf4315816c80c21c6b2fdbd9676a2bed05f77acf7bd82cb2925bff23b41e3308
376	1	299	\\xaf2f6563a75a79d7684e56b33d27902e7776cd61900b8eb6e181afa35534cbb018919849f58eed77bc4bcab376e38dfbdca4306f716c846d45988fd2f86ea20c
377	1	322	\\x7db464c04e0c2caf04e870de031612b13d0ac45540e2ef7a493b3b3697327bd63a283ee6e0e1d69a7c3fc49aeb0bd9a4c241a2d4590626c11cbada7798166b0c
378	1	408	\\x63a070e621bdeabd35d756b4f7d5112bc71bb9cd034ea9a7962ce0691881b8207bee6947f7a848f2f3d80ba98d4b369fee83f2b327a91546406b57595dca9903
379	1	289	\\x9fa33451fe741af85bb4f6bb698fd1a88566aa05c27b1b3a3f2ba641e7b881a6bf608dcd4a491e8c99fe2169e7f2e217599c6a3b7a02521dad1ffb2aa26a6a01
380	1	291	\\xdf7265839c1c38eb6dfa4f8d8a986b5097d5c8afd46076efc8f191c3bf8d875a659c918ec4604a220c5686c6001d5edd67c3d25d691c32f77adf0486abe2db01
381	1	230	\\xe2b068a5d4318ba02eac019180f7c50b662153e23807ee8f753692c0d4dad8e4d13a5b848aa4d6b2752db8cc305f0ae7e93f40b180aaf73716f80c145c91240e
382	1	135	\\x30bbdad287c2fbbf1a1e771f1b92efbe96be0d5a5899ceb3fe6cf68e2c1a214fed4a340c4a6d96eed16c29568d1e69fd8e5513dce7a82d6730b270e8653e2908
383	1	106	\\x07a5f7f93193d35eaa6b82482c9ef535a497382e343e0794ce5b33a9e2e4390c198124334ac15d96c9545c4bb7b69ad76e4de733bde0c484e164c33eb50d150b
384	1	290	\\x450b26fc1253f150a6c8debf40446f8f6ebac2fe283ff2201608887aa8b6ca1f49cf7a1c24e66b8cc1c7c93c484bdaddf9ad6f214b85b497c3a1b75cdf0b730e
385	1	410	\\x08f63bdfbe9a7ab35502cd9b5dfb5052be3f8c738aa77e6659224fe00fc3e611a20b782ccb7123e9263702e8606b9f1257b6f4daa33c8b606e37bc882aac4909
386	1	313	\\x98cd47a624da872b7e82a9a167d779460eaa242672b3c603c6f3b9495d30a6308639fb7a124c8a593ef17655ad00a2fe48a091e326ddb88eca758303dcd2ab05
387	1	243	\\x4b02fe7dfa813008704e5e7bed304aaf6bf1b0e544f1ccf0010798dd4a301c2bc79e8bb60eee3d8218dec264c1004ec058dbccc9dffd5775016f362365a03607
388	1	132	\\xb6b6b20b3da2dde7a677fd26fc657b3b712688acbaca9ffa211b2fa0f0a438c7fbb8f9600a4fe22f627a29a616bdbcba180780dc9cef77b3f63545da5055ae0f
389	1	160	\\xc88263e9b34740c25d7a93129d3b8a3093ebd03b6f1c93a60e69dd37b7a2b73386dde3ae90a674c11be9827da8e4dbb351ccc0afa4be45c0c2d43a95075e7d0a
390	1	287	\\xb28ae820aa6534dff9eb441a2af219b305535bca30f0279f931e6082891534359ecbd633035ff9f37ad9b34b86385eb11efdb6b6bdef9403fe8d15d0a87f4f01
391	1	271	\\x6ae1afe377c626a4a459666c8f08119319194f0667d00bd52a1f540290a68baef63fe52709746b81b08094ce6898bf2f9c9a7579585ce18ae42a68ab1c562f0f
392	1	108	\\x5e457d25cb285248c1475292fceedfbb06c28f57a1954652b6300d211fdd5db6ec2ac8b182e63685e70f0e4dd92e76db6951a4cd0b61da52b5bff7a724e08806
393	1	148	\\xa6c5d3af7d6ddc7c47f4a64adba536bd760b33819753a630550884d0b860829a2fbb59a6afaf7831008afe3208139bfe8cc8968fd2c09d5a57b4243126c2050c
394	1	26	\\x72891ae9784f95e5335bc684e276f5d322587be855e1af3874aa9ac5508b8004ee314be52c1dd8f119cbcc81616f3b76da04a18852670ece1a548ee61305400c
395	1	409	\\x71d711b7ef34aea698fe9f0512c5dcb035d423efb8c520e4c6deab2ee48a19e4d4d0325ff76d044436a6ce36d648324840532e8a25cc35404dd882272ebb8209
396	1	158	\\xb0ba510721e7c105c782af316553c97051c3c7c7f0d94b00da446fe742dcbf97aeafe3dd2553c8074466f86b7011b3db10ea51fa8b399e2bbd60a731ff1bfc03
397	1	163	\\x03f0357c84c3d7a8ef0fdd6dd1417c83df8e9050f21242dc9739c905834f5ea3a682f170b3fe1ffaed3092c824714ed9d16c99c77799d314a03c3273ec7b7702
398	1	140	\\xf15d80b115434c34debf6c4bdcc758fc45b0a0697636937b7027afed9105bb3d40a5690c397b0372dcac1dbca1ebed1abe37695299c68e28b8f4e36fb286cb04
399	1	320	\\x2525651ea50334dd69d7521c1160ea4ff6abb3976e3d09c17f33a570f524c96ac29199cbf6ddc6be9815581c46dee79fb53a58a277cfc8ef2cf60a0252cd2900
400	1	247	\\x1e2af0e2b9e6298442e63c9b5aad5865b49d939ac72b0cc17b2c75d044c041e9f43b9c62dd9967ce78adc43fb2bcd4594c0674744eafb6bbbd675c3e34f67609
401	1	168	\\x08356f8c27eefdd9c8bab5b99d11287a4bb09ab9838754ce93efc4a0f692f2f61a4e2fef9c125383a22c17c3aa19a50a660a94c53c655b47b3b19711dd05f00e
402	1	228	\\x3d46adeb2138dacf3ad1db08a33b9ec90711e15ffdd4a9f34e4f8369e3a35c3d57970f00b4d4b4c20e37471488c731f93293341bf8e807015b9b1942b24e9a0b
403	1	8	\\xb15ff70031d3aa8db5e73293bbb8150d31068730afcc17fc7799064afb5193761564b6dbc4a5089fd831b621ce64571c07dc6c44572aee5442ecb5b73925cf0a
404	1	416	\\xa1e6bb6b2fe43a40dbd8d60cec504df2123e39fd3c4ec9c2e23f622749f2efed0b55e4740804db9dbf8d869e0e56e617ebf403207ec9b1543cd70e2beca39806
405	1	365	\\xe03aac7d13b7055acbdf8b3fc5366d4e65168bb023ce0eb2befac1bd5c3dd92f794d7eb940e733910cb3e4d3d0eef4086ccaa8fbe3cea8bd1fee26134bfeb008
406	1	195	\\x7fa1006aab60e48ad84db2ff4c3afe71817d0b341bf0beec8da4910d7c0e384f97dbf5293b32119edd7072226b548fbc96978b55bc5f71ce62a4231628d09c01
407	1	273	\\x4296085b2d6b12237ff8d7e6d3b905403ff8450da112dd7cf2705d642d0646e4be2206373916a24fd5f2018772819533ff635c683c6b74faf1e8f285dc02e00f
408	1	70	\\x21361f355023175f9ea17454327ba30a9145e6fe81a758d5910f0a5639f3bccbc77ab5c8944e1dcaf9f32695e2a2bc4cfac8fa8020c27ff6531aa93456ed2a03
409	1	203	\\x887a41a73f6e8ae82bc315d2a18347caadc312ad0e924a890d8b499bdc9869628d1d06919f9c1dcfc50f48f12555b54f0ca510cfa3cb9321b027345ea4f03208
410	1	113	\\x879378519a02c903eea77a7ad414b9a13329b996ced4f446c3d40f2c08d429a3eaafba217a1e1886a5a1e2ae128eca7dd52518ce9d0a2e637d144298c9d93704
411	1	314	\\xd6ea983f4c8417487daa6cc33eeef2b8f0290e426b4f30badbc9b66c11dd2ab3ac01ab67dae2c907807266e35a631630ac6ab790064835d0af9faaed8169530d
412	1	216	\\xf6fef6ac277a99034367d6b1df573d428e58b8bec2f3dcd69e87b29df0e31006b0f488101e10083ce64187b8a87e5594cf373e50e779e73a7798653e8feba808
413	1	179	\\xcde94283547dae92697e92c27fd19cc7e8b2bd20a0ba73ed7cbec54d46deeccf8c36f328f1a65efe0567e22e15050156e94bde7c6ae176ec8bfca4a4873eb907
414	1	388	\\x6f4e342a1a193272963cfce706fd0aa6f1db083ad8dc2f22ccf78718a0a0fb46333a3ea86dd5bd70bba93aa712bbffa2627b61bfb7a263191407bd18bfbebd0b
415	1	224	\\xd1096d4574b0a791dbe6de6653b0dc2826648013ddcc0ea85e1943465533eb96870a62f9464b0d0a93418ac185d31260431b7e2e2bc6f73a0b29d58cc06e1f0d
416	1	357	\\xf125ef4a145ba150fc6df0bf1ad87a8e313c14086748c7e2eef90bad1aef1da2537b4e4dbcb3131582fbe05acff944d749f3a924205d417ec9682d62e0f1860c
417	1	270	\\xcd16f7e981448b0ef0dba95bf9927aae327de7e0b80140826bcb2cef2bfdb0dfbd6cbcb0b17b603444ae935b53446fcca7a03e7fe5221c9fa6a8ccec7cc86e01
418	1	213	\\xf28029f17e3ff0720405e78238d5f54e96b0237d20a72d25fb921eeb77b0edc83aaae17c26f1160c9b894a6784c3ad3361f95e536c82c678158946385145100d
419	1	400	\\xe0a09be6d9c5f1ededa8c340b7e74f9813b935c5b7e3027e9fdaee16c650e433829762ec2b4649fc1deef6e48cb8a8d759f2f5d600e784a1bfcb12b45c9a180a
420	1	154	\\xe1f9778a90eb5e24b76dd9ac7485556a36027fc8c31f939062d570034559f13fd513b629875bd7a8cd22fab6d2def0fda84023393d3da7688d1d092f671a1e0d
421	1	111	\\x469b3906827474a0f10e2a84a72ec5a55cb787a88d5d181c4d2c7a967e316ad1516b55713e02b0388d3221b2c2b6db63a7f8873c863f965cf1edecb1c22c3901
422	1	204	\\xc564943477acc5c642222cf30e6c8fe0b94f7f2360d4a8c9137c2b56de1dfd399d2cc77e0f4934730551730289df2ea683725834c57c9a6876050686df9c840a
423	1	176	\\xaf8b6fd5048cebb5c095d0f5d6d9166610e3eaaaa44cd13b921629785546a6d037d26e8f6336b58fb0a1a6fab8c9246f458c6aa7a7eacb30369a5a2f6295270a
424	1	60	\\x4b1d59a917698e1fe6639d1d602e786809fb94d4ad907db30098b3e95a0761abf0c75206cfc9deb010baefa6d3ca937aa687af62a0129cb6a3e7d777a00b490b
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
\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	1647564702000000	1654822302000000	1657241502000000	\\x5886a7bc94b7448b8bc4e3c70b65545e0c60d7ff5f7dcbbf10706fe469194415	\\x9fb8c3634d4b66f713f115fbd52f26803c7bdea0ce5094ed771a9e534ecd9d496ef5dc32ab179549d6b8d4c4aa2b22818032be931e9d13510bae7079ea936701
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	http://localhost:8081/
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
1	\\xd456a5622e3b4e7cf4961fe3907da831d5d9b38662798422378f75604a63d070	TESTKUDOS Auditor	http://localhost:8083/	t	1647564709000000
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
1	pbkdf2_sha256$260000$L212NBTFDqZoFtcoCh8vCy$xekldog4EV7iZfUT2K6u1ZDnREtVaMdWI1NWVGAiIE0=	\N	f	Bank				f	t	2022-03-18 01:51:43.410643+01
3	pbkdf2_sha256$260000$rboYunsNNHjjSXGzN32eZr$fbMp5ZF2/DScs6/B9qXEVYuWHjXN6E5u3VZF3Sg7PtY=	\N	f	blog				f	t	2022-03-18 01:51:43.695009+01
4	pbkdf2_sha256$260000$qrjFpTyqFHnycNbKkhzcRL$5UQpvxkvbhhyXuUUqepiymUzIxdiXzg8YBOyOHYaxvg=	\N	f	Tor				f	t	2022-03-18 01:51:43.836874+01
5	pbkdf2_sha256$260000$JgrUTRNCTvSLmBps8PplPE$CNrj212XndvD1GHuG2m9qQhi3q7UaDazPahXVx9SVyg=	\N	f	GNUnet				f	t	2022-03-18 01:51:43.977952+01
6	pbkdf2_sha256$260000$KfCzC4ntMkD56zHTsznN00$z6ZahX1r/bbpwFH2KcLrLxYs92UM8cTp8RdDjtv/sII=	\N	f	Taler				f	t	2022-03-18 01:51:44.120147+01
7	pbkdf2_sha256$260000$MvBJ4NC0cKjjEjXOF1RexU$zr6rf8ipeZSB98QEVwGClrWx4mh7icEoPLBpGONaa1Q=	\N	f	FSF				f	t	2022-03-18 01:51:44.263084+01
8	pbkdf2_sha256$260000$7JMbqkT1RmftfFnpMp6hNu$m0fpAXez8bGOtIMAM92tr+eP8PA0D+rl3NCmSTVM0W4=	\N	f	Tutorial				f	t	2022-03-18 01:51:44.405011+01
9	pbkdf2_sha256$260000$qmmVMUnDJGfiVlKmW35isu$ZwKAn56vjFKNCQOYzdfyhVuhXV5KOqW4xdksVyjhNwU=	\N	f	Survey				f	t	2022-03-18 01:51:44.547606+01
10	pbkdf2_sha256$260000$BlXHtSpehCsrhstaZczRuF$w2ogEKiDIvNXVGa3Dxf0Ii1LPLNkcqKU+kbh9oKxU5k=	\N	f	42				f	t	2022-03-18 01:51:45.009679+01
11	pbkdf2_sha256$260000$8cQjhciscWlEYKS4f602Pd$nuCvrSV3vi7++OPmiFW3h5S611FcNXCEtzXa9HdD+m0=	\N	f	43				f	t	2022-03-18 01:51:45.469557+01
2	pbkdf2_sha256$260000$d4B3yF4qBpUJmr9SnYjZQ8$fIyCLQOUow/pfoEdIy8HMAckOao9qL2utO+NHv0jHJA=	\N	f	Exchange				f	t	2022-03-18 01:51:43.552333+01
12	pbkdf2_sha256$260000$DUEo4xkVDLvZUlJ1gbyrjH$p1Oyy7Vmo5ju878xAph6/aDkoaA20vorQvZRaqFfFoc=	\N	f	testuser-gwke56jx				f	t	2022-03-18 01:51:52.030649+01
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
1	204	\\xd154b8b5931fd35a4fec74997a3ca4155a3fff9919688f2a98ffd88e27d4518f08d8ce1b57bedd0b57e2ab1c79b49f2922a1ab0ebfd9d7f5e80f1d3cc8d5400b
2	224	\\x057c3c37cda4b9ba99071c5261d7cd658f6acdd72a5b6be681616ec67ac1d951aa095d139bb3c61c61b2de3806a15d7793cfd262fb0a1d1e7bf88082cf9e1b07
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x02f0dc5c1a4fc5a64833e39bc13cab5aaec827a75803fa0ab7998bd880f29551bd715749584bf7a6ecbeae8bf9a1f8b6d142dcdbce05986241f16d7efaad62ab	1	0	\\x000000010000000000800003f0d4a3642970305338460b4e5c2117b6413889c8d0c90016fa2e03c8217a4c843979b79e358c910320ba0955b3edb79d42ee83c9b6d7b03c94a6cfa1a3156f02017e4c19724225175452c3ae9f171b8363913d50b97b2a36474bbc27fe368b9779954cd78ebac794f442e85ecfc76923c646938c995fe736275e075fffcb4461010001	\\x9ce48cc6a9465204ccb3711d0098189c80ffdab8da403567bae084142086dbf3276c970c9370efe6296718c86db49094065c50220b127fc1c25ba779f8dd4d06	1668722202000000	1669327002000000	1732399002000000	1827007002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x04147c344bf7f6fd20753d21834035a5820bba2bb0166942238bf3ce35a6e5b3a4dc5beb9653df20d4e17f397835acf8e40f7023a7721f2a4710efb758d4d7f0	1	0	\\x000000010000000000800003d1d08b71c49d8d92898078ef310c19e73f2f0b2cd5bb4ef4bce3e60e3933689cd6ca64d42b7d85997107f521df0da6588babce75d3155f9fdf1a9d3a30429f54dbdd3e2729919a017ade918a1c318c65681be068d39dec95c19205ecfcdafb79d7106ec51351dcdc9120d008b0b75eebe6a367aee0ba528b84ef28b14ce538c1010001	\\xd2c9c731cc46ad1866054f5248ce0d9b2d8fd8c18e8af6f66d38b273e6e38c9650f08507138dd6dea14b73fb649e83f75ac3f6bb47a7a5d17468c0cce8c8ba0b	1675976202000000	1676581002000000	1739653002000000	1834261002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x0580f4c1ef39278d1071e545389aa8bb7e264ccec5e88740580fc1d4200ea68972d9cf3ebeee04e3d169943efd9209e07de6e67c63280858f49873ff7530f8b6	1	0	\\x000000010000000000800003e01f539a1fabaa919533041f27a075842b9a26a0427d152aef987e695e24fee8a314a985828aa407db39085ce4043aaba10e75ae06ae8fde876737d0f2b6efe7c0304811a2fda43d07c9050175110f8aa8f2354aa6c449bf03ae2c956bd6316f4092bb25231d3a6842e79f012d12806dd03fb4d392ad370998d8019966c8ec81010001	\\xa1a5a7df332b5789ec805fa48d5e5f23883e2a3fe97f6b00df56498e12a2eb3d0df5a6860b4e3a24a0109560503cb2cbdfca2fda2e86b48055b89249d04e9b05	1675371702000000	1675976502000000	1739048502000000	1833656502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
4	\\x0714dada3908a20983d5e7ff26dc1d68eb5040e17d2f8277df4a702f9897c8d4c0cda901d4454cbb25b8ce34d2a089ee1beeda29426bc93907e1366b59b59afb	1	0	\\x000000010000000000800003b429cac52b46c58f01825c1472dfb4c196ef0a7dd58f100e6615f716f0b7259fe894d48874b0522f288f8babdadd2ff73acc917119b4d4fc3c863cb47c0f6255510005760eb0b36494ed0810767631ce089c10945aabb3ef755cf336addb7d19749354e858c77bc1508f997f500c5f527a24ef6368e16d184bc3b20fa8b7efd5010001	\\x406f6538d02b46dcfd18dad4277a898f5be25bf04f754cf499d5a8cc81fe26200bb84566671a215d3f84164f310c2121e287a27ffc367f86bf4a98171fec280e	1671140202000000	1671745002000000	1734817002000000	1829425002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0ac0c0ff2d3f8598feff401987ca71a4d4004dec3d000d434dd8967732508403f78ea8066841e177d1999c18c81f2a3b58f54c31cdfeb753b559f82ef9942b5c	1	0	\\x000000010000000000800003ad68587a41914dc942dac9c935b9fb9aeb4e8a212dd11ded37f25477d346438fde4eb9c7c3526b9135749c1b8bad7111db1c50768192abac6f08b61d06dbd1e1cf0806352637d90333bcacfe0bc9d8a98aa1abe1ddd466e3da1c6a8ec16b7c49b24ed899cefe1353885c87aa1d22dc52da49a9a08412e33fb1db53aa4c925f47010001	\\xc377c3ef962c72dfbdae0905b19bf169b235480ee7d169e1aa926c23cecf3313e1a7d9a637c25dd5a5c69e45be8d66d51ef74866c5158c31de49368bd9c9f109	1655423202000000	1656028002000000	1719100002000000	1813708002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x0c0867db39a4d4c92430fc12a078a89416f515d0abee18a3dd8d5cb99f320a5b08cd7856d450023a4ee69c2abcb57b71cb090444ddb125b4f10cc571bdc1f2b5	1	0	\\x000000010000000000800003ab1c911c541a3f3a91f6cd09dba136a00caaf5897325f178c9b4e23e867732bb55a84f5c6cdb37a9dc75f4ee218c3818445a95c8efbe5a718336a7d04aaa646b62c85d9ea1435e801cdd676b051b8cafd868c44f220aec6e5b16a21124cee43a93a65237aaeab73401c33531bc5efbe08615eb33a50601cc3d00f6410a050dfb010001	\\x5a343ea1bb58349c7f7b7e949c175c3b3aa2f857aa8a5197eb9cad6816927edb9fe027bb1621231389abcc37c1504f7fbc6810ae6fce82a524d2084a99e9a00f	1656632202000000	1657237002000000	1720309002000000	1814917002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
7	\\x0e74bc801c2cb0f942d726a3d5d8d921d5a8249f7ab775dcf9826eca978a189226d3e04e0d07564672f7e76b29d85dd05c2ee881b79a631c638e863517ba8272	1	0	\\x000000010000000000800003bec1eb0f05d91b0ff3834290dbd4c637a697b8dd244fdfd18e0f800b95292bfd456849d0b3de772497b614426c222f7e2e7b5fdbc3a2771ad80fc2a80841634ac7885af351196ae6b4ce0d9fb96a54de3df955c2155b4b250b82de8d7732fc810f57fea9102abe58d2c62bb1d68b739e66930bf8de4510406f80bfbabacfff0d010001	\\x1e7ad0de5c2a2a0cf0d5d9eca1c628b47d8c3b7e1918aeeb435cdaa8e9d1af9de41a23f4bc4be34534a6c43df1f0b5c5a7bcd8bcf6553aa770b377e2ee89f90d	1656027702000000	1656632502000000	1719704502000000	1814312502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x0ed48d1c6927317f91df47e9b9695fe14a3a36a1c34ad78dd3fe9bbc9f4242004a69c2ef1e8e1c8c3be72e1353c09ac66a4e490f7ecda5732db1f728b5e28a44	1	0	\\x00000001000000000080000399da0c2615c3d3a9b5b2de9e57e27af89c43e72010d235ab6d10837070a0f596b9f1fcbc15bc6b42be04af7123e67db1d4c4a58ab38f814d4f9932823f364be0222b48fa361e33f467bdab63cb6e0a28c0694aa251b610e75f02843a3c2e4d0d70166597703015466bcbcb858221378742836592b3e3ff7d34c75c01f159acd9010001	\\x0faca4e251d6f962043835d3b69151ffd0ab6a4ae467917c517a8d2ac94499bcaf8e12573541867d9d942ff033fe10078cf6d237b6f3a3c8396f7414495d1a0e	1648773702000000	1649378502000000	1712450502000000	1807058502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
9	\\x1078a5681f8821a91d64a891252f73d4f496b3614651ecba5f76bd6e221cf8e2f8bfc970a51021632345e0895b49c3196991d3748d0f1f8864ba3000b7535a7a	1	0	\\x000000010000000000800003add27f1064605ddf23a427ac53d7131ac7d67a8ffcb6508085b78038f329e90d4ac83ab70624b4d45d74adf8aa34e0f0e3bd8de8365bb1b231659e546fefa3f6d8d842af402a76ce5120b3047318927f1fe483bec0eb9d8c176fddfc3f050c31a862496f48bb8cace0dcecc453e7c58cb364e1fd92945e366546541abbdcc3bd010001	\\xef4c2f201763feede75832cfa28190bd7a6813be9cdd2feb54c0f61352436567bef70b2d62bd4c6a50f4fd585099bd551e569f395e923144d4b8d5a8f530f408	1670535702000000	1671140502000000	1734212502000000	1828820502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
10	\\x137cdbbdf01b50a6de59c4b0c6ac1bfb1392fe99dc91d3d703420a2cbee9c83219bb2bbfbfc30dfee83d15ece0f5341fdd24fe46955b3fdc98926ba066401265	1	0	\\x000000010000000000800003ca69ab85f65387b2d5c5cf7f4ece1af6cc70840aae31ad5dd90510733b48b368f84db48fabfde9a2ba465ce27d799befb5136705cb3865b9113e28722f0d181505c255d30570d8a4242e52f8ba09b95486d5151af2e736462fae1d20a3998452dc6aa72e3c56f7c82c0f9a1b1eba168b0e832111c56b27e688a84f68c7a798c5010001	\\x4ddc72838c9a38c9d37caf076ffac7a33309fa52a28dcb34d538f341575f8ddb2832fbb8b2e5d990590b1e267ab8cc18fdb1dd226ef16e7170616533c9c00a0c	1663281702000000	1663886502000000	1726958502000000	1821566502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x1660331df65f079ca0dd2cb6267e57c213e70024fa0498e4f95796720e508052e3a380f88a9c3fd52d9f637bad78400fa1def2b115c6ad2454bb51ef7e267246	1	0	\\x000000010000000000800003cea93583428f228289a149815e1c2369dbe9ad859d6940917dd30d48b1c5cf260fea7e755cbfaaa048f2cf908301c6508c5381f6c876650da3e279f295dac1d05bffb69e384e447071500bb728ab9f6638d5659c4d4e7ced49a6eb68afc3f366ed832a8123510c3b104dff5ba2ca5292e44c3f3bf1cabad50e0729d4ad10d401010001	\\xce67f3ce9c1f92abc5b423876cf753e10f1d06d4a20cbd4c1f97c321563ab671593ea0d16ecbc773bca31059dc46fc251b678b91f833c17b98a8aea6fb790007	1658445702000000	1659050502000000	1722122502000000	1816730502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
12	\\x17b8fb3793148146a344df63372404098918e23fba1daad3e8b6992f06cb31f4cbeae0685bf492b92d425802b8f50259f7dacd2e69dc4f9f9de369292e50ff4f	1	0	\\x000000010000000000800003cbf17274d66cd338d8dd22a98d015364ca9e22e8910b75a3eb479ec96b08c318c086a327d1c00d7ca596940a24ab98534425497cabecba8f353b892822bd7a5f81d172f3449605237b694cea90ddd917377f4b5bbc0e0e36df11816889c91394f44104947f4d36b98def0c75a8feaee8e099705d234c4061900e5bd3c381aa99010001	\\x8e1200bbb71384eddad664ed0760dc50764fa10403e56b928fa3cadfeb4117813332c44a265547ee6d5c39c19637b5e6d6f4da519d648da0a2e84c461c1dab02	1666908702000000	1667513502000000	1730585502000000	1825193502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
13	\\x17e49ac5857a6cf7d2233423da9319f578a3f20c12b2de759d4e8e1a6ed6aac9008960d1d801dbb9e3aa7566ba09ce6ed0acb3f98a092495129a898e07f30d20	1	0	\\x000000010000000000800003abfe04f5b114ccaabd2d55248b558aa533e2e7b6fce4765126c1689d5a5e8e0c0b0b74bbb125b7562aee950335caf22296c46cc166ba055d93edce8ac3337f7a1397643a3d3680e1a311b76bf0569b9d54d8b7b2d563264012832693806129e1c02b53fb17615643581875b95744dece2d48acee2eb8e6b3745b6b76180ac909010001	\\x411169648acf005dd58814dffa035be508498d1f940bde24a9631f267716732349f899c462aea4500a35a274e2bc2a9256d6d37f46084f195215b193e2c39801	1670535702000000	1671140502000000	1734212502000000	1828820502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
14	\\x18d0edf25174197d5544a741f62e3abc140441fef38e8ae1738ffc161536397ec212a184517e50ad734946a4ec88c8459fab010c30aca181cb6fa493dac65cc1	1	0	\\x000000010000000000800003fbac9ab31a00a2b7293a6e56896c872f70be665f5945057be8291fe9df284cc65ea6d6ee0139123147d3527f1185a15a1c596a4c59f10ef20abe513d740230fd64a6f7b851ba4fdf3897792ade884d61e9aa2cb5ff594aff2a31e656a2224f59d8e5752f7954f11c28045d42c466722bb930fc6ac336efaeefd9fd5379f6df85010001	\\x631535802486fb817b62e6cec3b9a1413ddd86799224d920c1e5d5c69ac728ac69848551c111d50b6076941ea9465911d9f6723fc1b934f03a62e78f8f76590d	1661468202000000	1662073002000000	1725145002000000	1819753002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x1ae89df97f9f041490885795a06eec03ec204d17b56513839de77bb14b84434b230fb4885c925296fc60c59c8358a91b64aae3571d434b46b42164707a1b62fc	1	0	\\x000000010000000000800003c4fb5d3962f395593ded00754c91b7d860a797cce434e0309002ddf0df60b2343e6d3a46fb6415263d514681f9248e888ae552fc996eabdf32a08eaaa6cf3f214f65ca38c0cd0c11ab24c178267cd6af8672dd216724fd189badf14ec61ae17cec64e5c72360082928c6d8bc2483d5defee977cebfaf886f9c366e2df7bedd6d010001	\\x27ce2d3b4d7c21534b96e7bb5bed0dcdd8e1871fcf616f3267762893714d57ccd87fe4d03544ca0b397de4fba57d01465b85de072b450853694df229044d7e02	1652400702000000	1653005502000000	1716077502000000	1810685502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x1a5ca88d3a750d4d43fe889c3a9524ea98877d90cfe18f467b1904317f58ca0f147f6f30b4309761d3bd107948e64d106d48e806ae24e10af14007142feb4898	1	0	\\x000000010000000000800003b6d0f46b360a9725844b3c09a32cfeadf278b6b80c7e3d5d5f71610ce756deb4d6143f45798bb8e0877351e429fd894c5697a81a43b351cdec3b06243960a685f728a08135be2bf37ecd8f1272f9ecce517fa9e2d8453be0c7c0af366f71e085482974b890d6dab13abb7188f50af2ca925858fa320f74e8d523abd248062923010001	\\x9e5acabd2d4373d5d5caa5fab99c50dca14f90ff6b827438cddac5599bc3bd22f6813659fbe8ab1c89e7074e9a7de6ceed10c0849a43ce0f08843a0066013f05	1657236702000000	1657841502000000	1720913502000000	1815521502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
17	\\x1ad8b0a9b80a72e04d54d8b75d56e5ea7a725c246f6c6f29ea5ff3fca6a8fd2ae24ee974adbc166675b9abaa404f6b6bf3edc81071c76e97a4582097fd266cb6	1	0	\\x000000010000000000800003ad8e37ddd7e4627d823c8d5e4eb5feddffeb1048e28073445e145f7e8ba6429fc7ce5258a63a5c218acdb20f14b652a75cc07ed794414d965b53346025d8299c42fa3d5dcf1fc7d74a3d5a8dc37442df5fd3210dc3525c2da61ad762ac2ea4dd223ae087a36f0bf86a8e1e17c028c9ba7c8f15b8469d9ad44a6a2ef10af9151d010001	\\xf5a102252b4b43e89d55c1a8893ca00819147ee98a7f98b20ad8bdc44f34cb3caaafa01584ba99bb04375ad93fc9280e7ad2c1f0caadc340c1af15397f443804	1667513202000000	1668118002000000	1731190002000000	1825798002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x1c642febea5a1c64e9e14e80599aea28ff869da3819c365af97ed0baa0f85d7548e1dded247d698d12882099a6f2cb04361890c013426d009ac9bded338b55d1	1	0	\\x000000010000000000800003b7388028980b5723f76712010acc24ef66db8bacbba21b3ebceb38ce159c1102376c3d5a5d9caf293d1904b638a8c476f644a5a60d1d64d084d6d33f03bb233d4d767605858d6634c82e55c5e34475b9b59113ddc4e80924a2a539c00e74a2570ecd4b267314aeb5b20530dc5864214d68a83ed83ba8d865a5f9416be334238f010001	\\x54bc00fa2715c827ebc714f1077f1be42f203fbb0af29f96ab46b855315b2600b2cbe9b0353cfe5dca622c93266533a006dc13484b8e38bfc40c2fe236104e02	1654214202000000	1654819002000000	1717891002000000	1812499002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x1cb8344b071204a4d3bad6c07ce7adf817b73103f3908ea1043540df26995145d665e00020cc05f821f5b3a17ed90f487becb8128ce15362f83bd96d7f6e3ea8	1	0	\\x000000010000000000800003b2b2cf8cb8ad5dc2da4552d917e07123dc05d474779b95441376916f868de1cb4cd885c11ad84b2fed77291a73b930f8cc270d947ae34b3d5e5f927e6de68b548473f0f541e5eb995a2bc8d2730f20fb07bae08740a18d8d9989be539e926468e46fb331d3f0f4ea0412c90af6f379ebda1eefc22ac427b85b20acc263f2c6bb010001	\\xe296b6f49f8763728e0500833a1172d1346d6973c368689198fc4763de16578e485cc0a2ec3036e236c5a5395718b24c8c53db0fcd1ff4a8e98fd426b3079f05	1662677202000000	1663282002000000	1726354002000000	1820962002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
20	\\x1d4cad805f5ae8772eddf97030fdcbe4218e7659e7fdf5cf864b8cc860c4d858852e3bbdf01231aeb94b19c7ccd925024b4225a289e7e78d52b8c9ca0dbe4f7e	1	0	\\x000000010000000000800003ae9c5d48935e9967dc57011156f58774c09a59619ef3e95a538fd4767480c1e5a22a0393f422c2a7f99a97aed8ffb8149de0aa8701369c378c0ae5877d1162edbecf0c766784065698f5a063e0099c33f363d688a12f2771c7bd60153aa13e7248011357278c97a5ba49eb9879d61c700a63e8269d7b4c3806cbc88e1946d2bb010001	\\x46cc45f89538fe567fa1eb86a2474f1d6f92fa1d5da65d3c5d2478bbaf2f109c133e6c2bfe2fa7e7baec1074b90fbf38a64d3978990cc406f2bb4546d86c6d01	1673558202000000	1674163002000000	1737235002000000	1831843002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x214c5ad1a5a78895c78c4711bb4dee34c559fcc41a7df63c5acac82544a25e507acb02f6cf6a7ee3fe2db9b239a0bc61fe2554dd931ac78a21506e92bbed1d31	1	0	\\x0000000100000000008000039b0620ec6baadad771fc1fe9f9d871c58f4a2af455f9c5435f426e17d2db213e4bc1e7c53828a468236f1bbf7f304ab7a8c7c6ce6a712a4086fd3fe32f18a029fdafec524f908b1150db96923f113784e9c401bfc5ad22027438c9dfbdc0eda628a69bff17c794c4c8b691381a3a4b858b8c7d01505a881c52ba6401c31bb877010001	\\x90539ec1f813010be8c124fc5fe715e5616cd311d9efe14473df7ad9572c99b90b2f53105d6aec836c1f75b0ce84edcff903972120ccbbc68b8102e7044cf003	1668722202000000	1669327002000000	1732399002000000	1827007002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
22	\\x21349644e7831b640dd8ff94dd7a10a750a04bf3ab3c754a44392aa49aad53a3b249b25bc6b24d86aa43c1134a503c7ba8252b93a0a41fd053dec127285c38ca	1	0	\\x000000010000000000800003f1bcf18865f652d78da096863038c3f93d19d97355ffab53bf7cb241da901be36342c6d802a15635651b6a9b613df848176554671173651180a6d7ef85f898f76859ce6ad5799f77685a85691f8517470547f7d134d9214dff0fb2d5f0e52c07c9fff195ac72bb434a5172079f11fa575f896b7fb9b8dc20b09491cbf345d869010001	\\xd0f74e0aabae13a13674edf4a998d36720cc861f65bae7f64ed9f831d5d840df3316d7499400488284b17adaa26ed2e141b9c38bd9e6c5229d61ae3a826e230d	1672349202000000	1672954002000000	1736026002000000	1830634002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x254c093bd71d75e4ddbc7d024d3f71a64286db8c5060b1fd4bc32848032c8815df4755c6c388ec468fe93267919a665b81ccfc2a6ee0f8f8f77a9a5912f9ad11	1	0	\\x00000001000000000080000391bdd9b7125d4357f74fc1bfa9ddd1bebaae59de6e4b1679b4440bfb0bf46030f57157828c869fc3b75a9f2fecc8c7a0bfbcc88f992d7cea91b30d281e2d386868f09a40d9c6a6232af1585df4a1fb610962e56b4acf9a1753caaf9179d8d547df90e06cfdb763d0276c6719de7c5903b13fa15398dc87cacf30657f93ebe3db010001	\\x5d9bfb2a34b8e605a2c803fe46249d076f6eb71994d0fe6fc32c75adefe5e67548f19fea2b0bfacfd09cf74f07d9d70d115559907c2c46b2d53d183c1bfec701	1670535702000000	1671140502000000	1734212502000000	1828820502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x25dc10094703199ff6ba4bbf96998bc9a7388d51b6af755ad84d92572835bfc8a5d5dde36167e764174094973b0f22cda560836586224efdea54e9dc47fd8607	1	0	\\x000000010000000000800003a8e1043f29adcb621dbc8f68a12f85583545d4dd0b65163b22524d57b7c25da7618f35630c6e66a787f4149fd22a8973e0ae35697f425e8b42e25542ae8c31829a95cf8e531e6a7b543ecba54f6e639b6888f45b7cb86fb583593c6a0e8031ecdb4b60f94143a611ee6b9c98e438ff4dd9cb9d2dc088f86bbfa3ff62ebdcc075010001	\\xffbe8351e588e3524c09c9d35574c7fb3b7cbff91d34bea03ed678f9bcd2bed1839ded8aac53d1b7b26a42d0b074873c0237966857806a1e51ee7f6167e84101	1674162702000000	1674767502000000	1737839502000000	1832447502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x25c09817b024fc3041874bcfd3c2924c0970091e175171f044e17f796b453587dfc0d84a826248e1b27eaaa77bd14aa761812ef694e681437e36a3a63f08cd5f	1	0	\\x000000010000000000800003a612bb8984cd97211928c435d271af26acccbbe77f8cf7fa48e0628bfbff3856140301436452cbd453f745afeee7116b1b7ab351f8f8c4f5beb25653e08c89cd5c2af9e1c3c7a6dae6ada04e21b503dc9e544817b744af44641c5dceda3ab449f9a31b75b83e4f49bb286138967f93820df7fa7870d9ff88674217a8ed2299b1010001	\\x28e9015c588be811d19c7c17f500bba9a7aebd420d7634be248cc86644b4096cc82c447a53f003265c3038a474fecd0313606fb992505b39d98c57b782fe3f08	1669326702000000	1669931502000000	1733003502000000	1827611502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
26	\\x26a8921ebe04b7980e6682345ce351d79c73d19978be69c6671193cf456bf96514e58794c7e8dcf871947852cb48811dcb664b674efdd8e0a40c29b4f9bef9d1	1	0	\\x00000001000000000080000399bd1de0a24b6c4793beb122ea26c67e1f536d83d30e883a5d11f4b11a2ada167f4de97e561a4b2df07f6af2711a7c83c5f84e1e1a97ecdbb52e46f2d247d2f268d7d1ea7e454e6b3ccda16729e5f218ed2b2fb3f8bd6a7365d3b9f6021c38324ddb5b78475e6998f76b1cef8061b36d9abbdb5aac30eba40a18aa10063a7291010001	\\x033ec9b398015f3919896748b0d0f630c7db7d287bfa3874364b3a33af5861fe44300da21768c619628af116a7543497e2a799e21be8c205b72a8b4f3d230b04	1649378202000000	1649983002000000	1713055002000000	1807663002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
27	\\x277c3bfaaf4bbb2d87f64b39d8e267ed481d7d2bacb28dd0dc9edc4ba4a6b56f5b2d8da9faa0fa7f48ee70577035c0aaa2f0cba3bc7e207662a0ad03b63f47a1	1	0	\\x000000010000000000800003934d4adc752a3f9bbd3fa00e9c6e79f3ecd08e2056e0ae23bbdd9c8ecc71d533989b5cc8e17af409c91968141f42b36d092c1c2b9b68dccfc2b29cb5cb50b3c374bc0dd340a70a921941b71e01f54fd30bb453590633c3fbe8e26ac1db6beb2091d93d1c21fa885afe6567b9b9750ff0c149932b06e0c76407c5e77176b9c503010001	\\x375393ee916b6a062e05ded5633c4f848e884f1ed5f715709b1bfb80c2ae50def41d61163bb1f7ddef5208e113fc220520559b5fe0ec68f83d6553b242d7030b	1663281702000000	1663886502000000	1726958502000000	1821566502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
28	\\x28609c8051bc286da703c7a884f00e2543727fe5dd1dbd11d71f4f0993b5059b33775141d6e43d8963c6c22d6ff80941743ca030a6d2ee78a4728c2adf3e98af	1	0	\\x000000010000000000800003b965543a5901d60d2b6cd159ff9263c1a240353a827d05ff4820be3c3ab05c8fc8722f31704f71f8885761fa4fb005937e92f343b621eb5bfc85f608379cfb7936c1d97421eef92fd3dcdcbbc25baed0ddceef88bf3d6a2a774c216ed1c1250f320556420ea18ee637adf705235da4003b066924ade157288b18e716ec52ad41010001	\\x84bbb01a2c1b75793e468ecde98663740f0711c0590243797e30a4b75063e8d756bdf9c378d3588212e3d3069b7e159decfbcf106ac1ead5634142b420e72a0e	1659654702000000	1660259502000000	1723331502000000	1817939502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x29ac0fd74f22e4c2c29d126f3198995d3889bbbd662106f0d8591a79be0d0f7c95e6b7c4dfa22797c835cdff1ddf8437558a9d99f64a053179398c43eb141a62	1	0	\\x000000010000000000800003c30423a73d4ab9d3422a02a3c8956c2bb51b8f9a1829bf6e6315e393b1f712be2c2a9c636f9ed48ce71999f23c6075a93fc3ae3bc66558dd14cd806cab33b2bcc575838d21302b5dd82841cc5b76e3706b0c6cb5fb8eb2e15d85e72a0c8f61580bbc289c37765227bcc1bdb6ea0cb3f108de3323430a1e01813c7f444ec52ea9010001	\\x8c0e51c1b5bf5dd15b1fc8222b01d0952f200746e51a0e5c949af033c406db96dbb8ffd0f1b67ad75695c82fd9d7744a75d7754670e0a1b6d74481d8a9b04b01	1651796202000000	1652401002000000	1715473002000000	1810081002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
30	\\x2a18552482ba2e0718b3102831a46b0883548a1f5fabeec48ea36aa55f273a51c1aecc3c69663464e1d1c02daf6c0ec3442151e0df06784d15b4ccbc1e5949c8	1	0	\\x000000010000000000800003aedfcea1d0b3b3dd021a5b0d74d6917e45b3e53cbbdc6aa0c7133ee7b76ebc0fff43798a1bf7238120c3e257c734a3262760a1d79fa651b41c5a06d6e81b1da9cf679af49c1ae9bfa8bb4a3db1e06a89562ca5a84f2964f174598123d0953e201c5608e8157e454caa82e8cce49951aa53442cc3e77868d198efaa2c91e48acf010001	\\x36a49a3c5825cf1cfa1bcbd3be1acba886e781c1723fefa12b356e13c34e20ac8c52b6c4dd2f9021c9daded8a94564bf90aeca8eb7de9087102a43ad673c710d	1668117702000000	1668722502000000	1731794502000000	1826402502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x2ad023af4945572a435f95313dd0b82ed1d01563205d9c3407c6f57772746a5fd53dc53460d935dfda8074f4ecf389975535391d8689a5eb4e20486604446e05	1	0	\\x000000010000000000800003c682d15ec9439ef9a890ac95e7e71a1b034198aa7e70b014f5e63409a71cc5d6c0aae670d4ff7e0fc017c375d17c2679d035df2b8f9c3281d4e8e5e30b1f89a397dd3ccee825594b097617a487a3c60c5db5364941059734ebb76045384d3f8f5e0ce36c73ebf9fc0ebe1d83b6ab92ddf9643e648a012ac72ef7b212fa95e8f9010001	\\x60b5ceb1c7a22310dd5a286c5327417307f5d1375705224055fd276645c7f6f46678968976ad772f3caf4d3388a68d3aa9693ec367675e270b9076a161f7f20c	1663886202000000	1664491002000000	1727563002000000	1822171002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
32	\\x2b9c93a9a942a3325cc0fc1d5ce54e2f92d79e794c6bccb74b54d30ca6bd4a81e44e53ee739d6522db79b9242839d45802362ad862af213b33756210fc9b0b60	1	0	\\x000000010000000000800003c03777ac1d1f2c6b5df2be3e8d8bbe3f86e128232833a128c37654909e6fd8696494bcd78ae8cdff248e9b91cf2024e37ff20ed1a124f6817a5adc3a0b3d227a5d55b66921d009b73a289b66be8900f2c4c61dea62959fd7de4e3c5047207467ecbafab057f6b51b9ffba96730f9db7af645c6a3e1774b1ccc1513e4fa2f231b010001	\\x54c8a3f1afb6897c972d1d2d856d2b5927008056de1d2f9ae36ecf2d79cd8c64b8c4d2644578918535f3b21cd1e0b915c0bdcd20a6b3091d1cbd60ef9d88220b	1663886202000000	1664491002000000	1727563002000000	1822171002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
33	\\x2bfca642eb7f65e4d515ff2dbef9d9ac64d3d05a1bdceee4fb95d10aa04750e7af7c4e3a53f9dbbed769fc91f64644b7f3e1c8ae7f118d983ee83cd2de1aad85	1	0	\\x000000010000000000800003d96db5f2d86244a34d90a92bcf1bcd6d089ef73afbcc5f1810ca017eed509797e23cbd023291454d3cf3bdbecebd68256f90033c41fe49c7e29960268b34994955c4b5586e11dec10268dea8bedc48ab3958d628f2b13b40c4b7e7f8bf437c33196cfb7dd4c6698775c299ca7fe4c5508dec5212704a54e75b56e1cf15d52abf010001	\\xe27633c8afbaf72248750ae226c0f49159347e99697d4b20f5039367756823db00324224f9f8bd4caf20aa39d10ff5ac92923a04d5fd04fd3bd21f8dc5ed0405	1653609702000000	1654214502000000	1717286502000000	1811894502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
34	\\x2efc4e1c090f84016985fca26da9da89ac5e78626f85ad2afa219e13ea8deff6a46337d918d74a5e813e5b6984d8717917d44e62b11a6dea4c6b530134e6cd13	1	0	\\x000000010000000000800003a0d5b6e4984cc4dbd54d26ec3c2e288ee8aa48261354b0fa24b51db82176b755809b1d262c2c2ab755c574ad9f07d81a861e211644b4445abf80adb6f3a7fddc17087131f7894703c006bcb50daea1b6cbca05bb3aa284ff69f59871ad9cf61030d3f761544d8791a0c001036d470358c5184df3e18076a23109485a04624907010001	\\x07cdf03d28a4e3435c4c185f2fef86fefc94d1fc362fc93b364e17740faabd095c521fa3f1850133fa8f17d2306b24725abbd8ccd95b210296e8346f271b2f07	1678998702000000	1679603502000000	1742675502000000	1837283502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x2e5864064f0d82aa94e22b6b7e4d801b54e84f0e63cdf53e40fbb07c1c0636cb62cde31ddd722873e9f18c153209429f5ad1b4d22ad8676ecc9878d519d1b067	1	0	\\x000000010000000000800003d0795157dff2ad0716ca922627a20f8fc95fd06d3ddd74dce1b06565ef9a51e8a1349a84a65c14252e26ce480a0d911329e27f4fcc78713cbba9874bca4c7083b45fcdd62618bf7c71752b2bf09a0e6ce0444583e1402cfbd82eeb3a5f685c50e2c7f10c2db4248ff8a0e6fa22a30a70f32ac2435b7632f21c8ab0aa283f3b57010001	\\x5d350125ef657c080572b29dab5c20c406bdae32f2043222f9847ee5f5a601c220b1a64eff554da5a8dfe385e0635c34655b7f0ee5a235f99f6a2f0edf9f7e09	1669326702000000	1669931502000000	1733003502000000	1827611502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
36	\\x37a8c1c587e0ce16d9e734af6fbdbf9e0a5bb5d22b0bc78025d0f2d962a2e7a3130cf480946d40ad20116772a978c345678e5f37bab02e2794490447fefeabfd	1	0	\\x000000010000000000800003b1f93d030856833867f0440e0923b3ac8ae7ec4a596177aa2c3954c26e8ef98559512689d09030b35cdfbef6552c6610fec9ed710fe37f8807cd33baf42e97e10cb83f1e93e26ea19111a0c15ae2d3405563982a88b839cecd13615bd34aa8bbbf890a9d135dbf1b741fa70164df5c772f3e6a6aa13f924cbcea12317bfa4e8b010001	\\x7365c4d1dd128ffc970d51380f1f7939c586c6900b36d5ba25fa174b9d9a79a51d34a3f8961e7d5700c5d72b8badbf50f5db68a59fc3409edef6a8a3e3a8de0a	1657841202000000	1658446002000000	1721518002000000	1816126002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
37	\\x40e43f7bbc811d15ae1f681999e01756bd9b13ea0fcecd31d142edefd2938f66304293b4c14f0372b4f6cee8808b421eb9fda095d42f2b1b1766a662169736c3	1	0	\\x000000010000000000800003da2b43f7abc75e53affb201ef95a070984c6bc3f8795da05527da8e362319dc082f7efc2aa77856ffdc6419f3061716111075296f0207f3200fc635e475db8a68181591e464a450a742e29953920cffdf8c192a782c225aaef86bb5d3bb20a20e3b69f5d366b3f188dbe217af82aea90d7f053091e0cd558eb573dc7eff4a8fb010001	\\xd5b353b885ab15f5acbfffa5016d1cc77c7eb03b6ce10a33f235761fd0d2a3b3c457a2756babca3eb635b89bef0fe36856f170cbfff3aae947723b5844cc2604	1661468202000000	1662073002000000	1725145002000000	1819753002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x405c9cbdeff57fba408d5677116da87210628e0593f782fdf4c45628a5bb922d78d9d64b77a1e15fb644bf33a352024b457d4bbaca27136db111d2d0b06742b4	1	0	\\x000000010000000000800003df4323687a0f8c363645c05c4955af43fea24b6130d8fc00d514a3ff54026458913b08c045bb206b9e82627138ccce53b83a1fb7c32a64b043dcc79f4f7210f55cc0ca12bbc91b93878059c7fd797bfac550c6717d3ecda299abadbc117f69cec12eb19db961dbe459859fd9db31270b6587116924b1f6f3eaf28953a1c4fe63010001	\\x05e87d2e688ac1d84de316e07fc160da772992aeb6902318c04ea9157405daee05b2cd6e83eebc81895b379e83fc8ec6f34d5825e7352867766257bf68176e0e	1676580702000000	1677185502000000	1740257502000000	1834865502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x42d45229a8d10e32d7dd15da7539f3b7d93770ceb36e8777ca922ee6620c54aed9f18bdb5e9a89779c4a1b17cb441b987660586916e1774bb698e6b62fbe599b	1	0	\\x000000010000000000800003c742b915444a54db5e6b2be53fda1ecc315da04afcb900c86ebf13cd3408c2cd80495b5f6ea41bf6b5c55af5c79fe1e9d2baf996808dc7a11803c2ed986097be55167dfb1a187e95330dc8e642f3f5ea4198925bbddb5703e68f5c8cf80c3d42b58e70164356aa8ceb457368e67f8803709a51a26c28e0ccdd84c5274bc44be7010001	\\x6a415f89c1ddcbc6a5c9e542a07ba0e8a13064d6abead2efce7a408733788a397d05fd3bcb46e4dbd88bffee150b692759ea2349a2a6813bb834538c6baebc0e	1675371702000000	1675976502000000	1739048502000000	1833656502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x46ac6158b518bc7ced98410559959f96c5ca7330b9fb559389f0402eff65112d6947445392810e530ceb9a2b21070a720f2740a8a414e9ecaae6917f5328bef6	1	0	\\x000000010000000000800003d3ba6079f323303626f1b791353a9e206d9005849c0b1f2fb32e5cc7b81b36ab3265f5768f9d5c00d2d1cae337e4c0865fde13fa798644b0d0abc72cded85729d4793d4d9a4e93d61bdfb5d583fee9d745af54989d092c3a6f78232934ee6f606c04487f426326e7739f2966cc5a514707b65f95acfac7dc00178081eabe2335010001	\\xad6eb1e2157a4fbd2ad297cc0c2040989d8df67907df938c77b9852f3914099f7e4adf3d65a8520b02d9e2484ff7b356e5dc6d58f66af475918254aeda012608	1657236702000000	1657841502000000	1720913502000000	1815521502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
41	\\x50b45119732c28cc56a635c84ce8d7f119c23adfee90add6d5ca6a0cddd5faff8704654f2b498abcbc70d5a956624b32320239af7d6c2eac0f3ad5686832b7e4	1	0	\\x000000010000000000800003e283fb905d75dc2784a155be906c8a8522061e8f8a39e4482f79094fdefd49db857d4b56f1c50e6626a1a64b14ead0e481a25e767044a0f8a46f834007d783977d81be41db5fdaa9a598f11b485dbedf3e83d30e73c1ceef1d51f59f63dde5da567d0a6a3de89a0e2e4493052de13ce8b89d4fb7238d394e5758f54c0721a333010001	\\x7439b83699806fe82f5abacbf15a06bc9b39cbdea35f732e3c4659e5f01ae37ab481ea49203146ae580eb3edc9b7c43975727662f0b63a1133497c98debe7702	1658445702000000	1659050502000000	1722122502000000	1816730502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x57c0e677648386e56a0695b69a275ed1ef942d0f2ecda24f5a9e87bc88705a3aec233b1d4c857e2857a8fdf8819e1e58e99709fee3bda700bff003a1150576da	1	0	\\x000000010000000000800003dd933d32a5cad6f931a5b39d3801620c32aae6d36e57673df64792ed4f544093e08aca949ec94d12a72158b9cfc88522ca6ef607aa5d7a621b34bbc33521c73a8b4ddb54f49e557b3c6586c3863f44db557bc871c7702cfa5f551cc5fc63420c82365a46db7c96438d988f8fc193b20196096b9fc2830c71c685d62b9fd80d3f010001	\\x518f42bb0746a4e910c9c696ac9d0b9711bd4f51a6c747dcc90ed6f826241768910a64e3cb667d40baf7c41a87d759eaff58262eb0358a146675147b3e098900	1672349202000000	1672954002000000	1736026002000000	1830634002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x57a45b3e120ee37c80efa3a12728f98739f931fc77b6947730b5a8426cedbdce99de68bda97e347725f2c6544ba1cd8d7a8fe9636341d314031da401dff32a15	1	0	\\x000000010000000000800003af40974973ff08ec3d5c5b73087786391751f7601ead559b3fefec8481cd5e2e88a9f0757434e591c38a0c77c7a1ae08597d4e96066f252fd329140734829f74eed3df794154a6d7390cb219f0eba99103d22800e3ad3c7fd1a8dd4482e3846fccfe375c825c13e4c27796c1c7096ceb8f5fadcc5a8f2d76bc4fb944d28a47fb010001	\\x510800c93acff5905f8deeafe74b270d8bc9dc7e15438df9f6817bba5a2cd13bac657b3b29db1b2ef546ea95bc643add971ccd33b1702dde00ce9200db51380f	1660259202000000	1660864002000000	1723936002000000	1818544002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x59bccfe2c0c71a86c7a845486f2724ad41e0dbd0daa9fa3f779623c04220e73e22ff3e9a639e2e7ca60509be5915198b75c4468429cc7ed2b97e267a968cf9a5	1	0	\\x000000010000000000800003b660a8f10b16a591576e332db64065aae49a0560fef3ac533fa5317e3b96af862eba569bf1b4ebef63bc138128a7e4aacf27c2e5b18d5b349955d09b1eeee82a2b73e2dcd56bd585df2db5db88ea775952c1874611da6a04484c5a621c4134a6d6d2f601fb9c076b166803491ba322e184bd4a7aaf4857748f0bb85482265209010001	\\xe6584d4918d5786a3b9dc1cbf538b3ff12f001cfe08f27092ffa9ace7512ad8fe2650eeda8ded15c25ed73e4f8901b2198ea3ef58beb91a9fe6b6328e016b406	1671744702000000	1672349502000000	1735421502000000	1830029502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x5ae4ccb967a088576708fd791303ad8ad12d1262884a373bc52da97eedeec19b6f3f4ac751dd100c2bcd17a0125f082c588fa223d53dc2ea87619ebab89ad111	1	0	\\x000000010000000000800003a69c5ce30e6d4207d7607772a01903fab4e13238dc4618cd63a0260680735465e75f120189443583aeb61c38dfc8e63d1f8e9c4c484a095a223c538c1b92195bdfc92f9ecc168126aae8e14eca22e2a0aaf5eb1d72c090d0602dc100ef8d878f402daa99c2a1bcf0c8a65962a642a28ce75ecb6f641efc5236cb519b5c039453010001	\\x8359b22ef6616ae9af0a0aef0cf280aa48c42519b8dc01f2175a09833c0debdd90cb5dcf14338a075786da021dd7df2ac36ba46ac925bec4e80466c1ea163302	1678394202000000	1678999002000000	1742071002000000	1836679002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
46	\\x5c78e67039dc8e41b8453de4578ba9b24f42a5a5dc1b982fc8182971640bfeb2fb21cb97db2e39116005c24089ca850ced430c5fc54f25c92ab275c9dec03f55	1	0	\\x000000010000000000800003c926681ad73dbda000bfe3109600f4c8d6e79ac4e3a8d35fb6085d7d82dcf560d0230195e350dc5e0466161e9355e4f01839d09a0307464bd11e8c1ed42809644bc7979c3c34e635d177409afa21082c02448f878532b3c28fee8dc90d9574bbf644a4dfa5a06f9b81f2c2d519749c7e880405c567cdbce1088626a7526c6a3d010001	\\x4e86f5213817dc3606ea371ff48c7388cd4b5641306f542c95c5528b8011951a720b010c859eb0b6c1947c247f16d96fa96eed72dde23ca4438f89caac0ed002	1664490702000000	1665095502000000	1728167502000000	1822775502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
47	\\x5c3881368f26e7b9b19aae85e6ec2af4042b145edfc12d4e0d6df59f32fe6c47a17f00468fc74e2362247470ef40b90895d41913f9e1de579a11b543b28cf665	1	0	\\x000000010000000000800003cefa8fbb0ef78622d7c2472330477b6448d8834137380bab8a60c54005983a9d7d77e2ef2d0e80ff169d6e1ff15012528d94ecb84e8dcb2f7c8d53185f428993e29b0cd14de98c5d421eb408567b8ab9037666c0f1faedd4b45648061947eca44f1d49d5b467972222e427b3a2887a2956df5890e65ffd3a511b644f51038079010001	\\x1551e97bda6e2d4cd89febe6c6e9182f9e89f1923183a4087b0af9d946650a43a353e7eae9abb54e08d935b1e8ca39db671ee23f0791ac2231c887892767e40b	1656027702000000	1656632502000000	1719704502000000	1814312502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
48	\\x5e743902ece76c82b88c7f029c271b61c56665493eb63b0e3c67a411de7f6d4dbb2a8fc17b44b295a0e1ee51d26ac2306de3743edac5c6bb487d09d5e3ef0953	1	0	\\x000000010000000000800003c0d25539681157a3af5b2ccc93aec08cedf20a9b42e409b778d73f1569ce15665b22b9773563d42a7dd43cb91415aa1e02b2ef81897075d94eaf86b4884f322e9e647d37b5ceb504fc17c06b1aa2aafdf1a97d79e3df51ebde95a940ba3d2373cc508248479a841d96a394fb53d864494bd97b4b18a2e27b324015b4ca754fff010001	\\xfe1f977def1f65b16742ddd146e7106424f65f6c02f21bba8e0b8b861b3f87b5fc9158a4f8489afb73618035faa2af3c52a1761b30747e2c9407318f85ab6808	1668117702000000	1668722502000000	1731794502000000	1826402502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x6700be06e504df18dd4dd104a4a8280a599ad48514a0ad586086a6e9a4cd2057a678adec9c98fd268207e7ae6bf79ed8abafcf82e97a380d4fe83e7a7a9c551a	1	0	\\x0000000100000000008000039869ccce24c3b3e43b3ae99d4e8e981ecc72c7f1071589fbfe91f008e35fc949d17221d49deac5e7b7a2e2a993e784f95340822338686af2e7c74509c65f48c78a475d6b330eb8c921c73facc23074762e28cc34885acff3b86931a94ab6f36ad52bd102617a6e883065bfaa239c03c0042e34d6537fa8c3bb7750a4ce682ad9010001	\\xf49000d90ddbbfe7086e03621cda2e8d9e27fd5400cb05d373dce8cef6163ea8a24dd01a88376bd7ed8dab460b17e1a2d4e1d3749a31296d015587f7484a4a05	1653005202000000	1653610002000000	1716682002000000	1811290002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x68145a0a439ea755beb6b38e226a0b7edf1a8dd3eeefe127866a03d604e26bd6426dd0eb38a2eec27f0c427ea5b8c00807ba581bd78d44a71434a712d74de0cb	1	0	\\x000000010000000000800003dd485584b72fa41c57fa6a562ed6fa49c4155aa2398230a961b4413d5dcfc6b7ba6bb8e7445f8f866ca51da96262edf3f1108623e3ac8304a2e23cf1b3c4349f7935c7d92a58c78e7b67bb90eb8af76141746addf1b905f4323f3c882abeed32e0a03a2969804c057c478cb581980b28e5a734f3141546c7a599505764a5fc25010001	\\x3ff34c1c2448879f18cdccaa7b3a720f04e691d86fc97c417d60c4c2fb8188bd1918cf415412f3586b814d070355eff7ff86dd0e441e1b7c93438c68e4839201	1666304202000000	1666909002000000	1729981002000000	1824589002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x68d043acd4a8400d1ba103814b422042cc7b51a4f368ba6b2aedb9f43c5a2def244f79b790091877d5e681d83c8b6bac84040c4740cce9c8b5f457c8d79e3a3a	1	0	\\x000000010000000000800003b4342fa97590181c852bba41dd3caf6f8ddda7832079f11b60e516bd7a8a70c97ca0d595ed89d5670511ea091f0b5dcd2fa90326e6a6660c93c46f7c6a496554076a130430808f61abd5451541b4b682dbfa9e0fa6f6bc7d90e11645d309ad845c33d643609e3d12590444a564ed52bb6d8b22707a8e6cd79f9a27d48d48d35d010001	\\xad9b530acb0ccb8aeaf8c48e2f0b1b758cf2bd598af9fa3ce77d5bad12b4806cac89083249fbf1fcae247d4494321f557821230094351bb84293761cd1f17f08	1653005202000000	1653610002000000	1716682002000000	1811290002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x6a103da69dd48640f49b8cce3c2a8e45386d4377029f3943b77b6a84e171515ac168bdef1324f10bddc3f90197175db5e3ba0d4fd9d345ca0977d8569d6714ec	1	0	\\x000000010000000000800003e69a47a13f62681c57eb304fea2ec65c2ee87da60b500b9073f1674ade0fad5f316c1934d6d3169d26b06d56ba5d9cdfbbaffa3b8a27ea060f8a813c83064bfc376371af8700c54f793c172b7a8edf5eedfe021de3d9b9fa33a4a2a0083d8c024427ad6dc0c572a5e2b2324a5bef7d529331ef89cd7532ceaecd199fae3410d3010001	\\xe6a80041681b13859de2ebaade19e00d9c3b9e350193368422177a957d9bfad364de9bec005719d0bdd72e85817d31f9af90a13c9c4cb4386f0bb3a38c875f07	1654818702000000	1655423502000000	1718495502000000	1813103502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
53	\\x6c084a2d8636bab1eb271a56980df74232195cfb343d026bfb53fdf4e9dfde88b841042fd2415609f1fdda20429ebc9c9edf2d68976b8bfbd72a686ce87a61f9	1	0	\\x000000010000000000800003b96b64cada4a4a771bd65bfb9f291820c937c9006abfd3c798a4693a745187e485118d1da3f59927e73bc6c162c21bd570d64a5818e329c6dc475d3275c9203614938d16a35c78b2a81c581c7cb311c2f4be2ff1c73833d5f5b7fe43619f93557be0b71bc6e754d36e170bb4e68579a0342cf6a41677ca3bd7eaa5a0e0047fdf010001	\\xd8f0868d8ac03862998547bf15452a3165f0cd8bfc549fab34cae3d93e0e2e7d90c748671fb630968c28182959cb30025fc2712adb0d1dd164f4897f86abb701	1678998702000000	1679603502000000	1742675502000000	1837283502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
54	\\x729ce53bcc1daaf701b7a70d82606f05105560d05aff0b1950e3d42741a3ca07856438612a1cf80fc65cd691ecd201041b15499298c9adbb6db650b7d6b371cd	1	0	\\x000000010000000000800003b147da43e5ecc0e3742212ed25ea4382d5a4ca55da41e971b01e3e1afd8572bfa491efc7da65eebc18399f4723e002a9289a6a8fabd481be89fbeec4fd9b73260ec3566ff02a83585af5f378f2ac523b52e2316c05915c12ec988e8dd845235c03c2e59cd72f1b74abb839df54e6a0c980d7b15606575226c1c7bb5365f2d1a5010001	\\xa24446228c278fd2a50b5920cf9a088fa0cc7e2e69f9075f233cb28c07bfecb9de9d06d1d2dc630d38868f4b465545d25eb8f7db05e251d00e8833f59bb0f80a	1663281702000000	1663886502000000	1726958502000000	1821566502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
55	\\x76384be88425b88c270c2f097d01924f551caffcf67387dde669511c197c9c3ed835cc1ab6dee0743133c97a574db4e3649c00e15264cff8e709ebc74ce08992	1	0	\\x000000010000000000800003c7c0f5d7a2c131cecfa7afd5bbd7cdda0d5f6b6fb029b2d5452b40496c746c6ba59a9344b424b2aadf1052f02cfa09fd695d77626f6344501f86a46839185b7d0939ffee51a87ca2f21d8a0fa5ae1e214f3cd5aadfe0a94b03c02ab4be326815769feb2a1c2c8f4f2755ee23d7d334ed2be9c5fd3589bd3513724b3662ae8733010001	\\x133318a7e99583b30c7c33811f67ece673ac3a3109a74dee9c490c2a9184de84c783af2fb7825e8bf5dda84a6937fb6285930690f8683c4323cef942e0e35401	1674767202000000	1675372002000000	1738444002000000	1833052002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
56	\\x7ea4e3fefba74e8a4dcdd86b595d8e2e3f003c6b8cfad450f3ebaf6c886373c3070d4a92042bf658d52327cddfe4565bc0b4818e1d58fdbba34128ce2c7762d0	1	0	\\x000000010000000000800003bffa09efefad2a3fc9da8103da0ecef961e4d2868f14da198e6ca9d2b4a9a1812e56ae8d456d0e8062b73b1f4bbd71ca36a821be158c6a4691dce539c14239a6faf3a21fab34f319c770755dafa6b4cb9b97cde57bcf9dcc6bd43736acea764748df1e1ec5f771d99e8f68202e7f8f8a7ea0c23827170aa13e36c05c6d96ba61010001	\\xff64bb0e4515bb3cf67679d7cf519ac1d86e3c09721e56cda6c641466b76ae3410152dedade28f1729e1c06d59dc6b488a5562db148441ee65ea0871daec0705	1654214202000000	1654819002000000	1717891002000000	1812499002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x7f38db09ad7c55a0e344f7f1913765cf7846595d71c70383de1a9413465df0d2165d07a5aaf4a7803ca2970f7fac9252927b3055914abc1b2557ed9317c0c602	1	0	\\x000000010000000000800003bc874679473e65942dbbbf5cc63a58ae0fa805dae599959faecd299ce1f06e3f9a9a7a9b5358eeddd5b2b3146044d4343c92ca30a693ff9a8be70498c99c2728789bf9dfe226231a20960fd3d16648b7fdd1bd2594bbeb6f17395ec5a6b560a62d404ad09be42a157d425e579d2c9ba8bf1df74133414c1ae117447fa9f8dfeb010001	\\xc78ac016ae5a0e572bd6d8c9c85057e93d7f72e32a3c381bca4dae115a80f09b6bca89b700e57886537ecd4545df0b21817ab61c90bcae96896cab5c7acc0109	1660259202000000	1660864002000000	1723936002000000	1818544002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
58	\\x80ac4812e0ca8757cc790d04512b9e3ef55a54f8a8958c35d7ae3e2476e8505769ecabb0ce5b91be007aea946ddd1635bfb480da257f8b5d86b896594a51761c	1	0	\\x000000010000000000800003939022f4b5c5fbc9e3919e61d2597f93d612144f5cd33004e37e0d2d8ea1d0dec0611353e93d0057c221dea4c492a7f47828d8ae98808caf7c7b870800b65ebc0ba266be5d225e6993e949e4d28e75f2125b51bdc0a66f78206363eed57983d48b8c9f8fc6aba7f6ff549e19924e997c85124049bd68ccdf90ad94f165d912cb010001	\\xf674c1c7fb480bfb9b47463e451b14165a8e41b32be448a510a992574d629fcc0cd4054a48cc787bc6724f440db27036fac2ced0c81e749768622199f07a6d05	1653609702000000	1654214502000000	1717286502000000	1811894502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
59	\\x87c4335646a4ed615e8e7c637b20cf2268fe3acc6e87634cc9796e6f41781953150d70be338cb36c51dc532ee088b43e7435bafbde5228250ec7c1e75f94dec3	1	0	\\x000000010000000000800003b15f18d31100c83da175bc61aea4b154e04dc48b3540ea9f54d5a6985866595105b267700ed2b13fbbae24b350757e6728a6f7912c69581e6b7953efe26994b3a5cd71cb2beb8b083d0c16d675f05cac4c9627b776beaff040d5798891f6c279e5f66d71c3cc69c8bd84832162b9844806792d5c299d1e8df1730c09b988d799010001	\\x9c5227badf6c2528ee91dffb84edf47862210d56a25a5eb3890bfce9df4ad039b4f90a1eb391fcc00fab6da16940fbccee8df3d844817cc381b4f9817e7b0b07	1657841202000000	1658446002000000	1721518002000000	1816126002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
60	\\x8cc8db4e23bccb2902a0ffe4c46dfed5c8297b8e705c5ef9ae6c48e24a5febbcc3f449daed161f76b4ab3dde94c8901ee9b616a7776b0ffd897a8ee0ec1c018b	1	0	\\x000000010000000000800003b1b6809c594624d6a747b2f01dc52b10a9e952aaeceba9de251a5b1bf2b19d328dfb99ae6c14ffbb4c6070ef18efe9468c06d6a5560a196219fb26d1b6459875355d5ecb6a4e6bd3f0f30c2041fd92426c09aed0fa89b871276584a9a7c3c7eeac1c5dc9540f8f197efa602fae541bd4e6f124a1b8315cfbfc5565412681c6c7010001	\\xd4a9554b99eeeaa22fcc565c40866ea90cd7c2679819867fcdf966e908e3f5cd4802a3498680cc09f22898dc90c3001077bc3e26859a69d6e0547a3c7f509603	1647564702000000	1648169502000000	1711241502000000	1805849502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
61	\\x8d20fb8ffb361eedae21faa7c8ad9e6f06eaac22f0d121abb79703b5ecab57dae57b557db6861b1aa68c5adefdf9e0174314dac849e89fb3a4dc9fbe95030d61	1	0	\\x000000010000000000800003b8b28cf43363b20bd3e84b0f4fd7ff5750890d158efada790eca9055e00da177b7231a63847c73c5a6943923788a381deacf42ada07028c6b6aadd4487a77600ec7d911d35c72a0fd6afe998a4f82778ad631f4f2de8d66645820f130ee9a6883f0eb447f30774e1162ad8b636d7b72ac7c482250aafdaea2f442d4d8ccbca3f010001	\\x8a74e716c4a724ca67e41465c277fb90f2a93c94d42b904f4469d590fe0a2b4175ff60f098b8acd9a7a8897f3b1c26e6c1fd2db1963965d008658b35bad45709	1655423202000000	1656028002000000	1719100002000000	1813708002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x917436749cbba7b6f74bb09a945b452dd1322ff988e611c457d04e16516cd424acf37941386a8d250e42ef934e2799c231bd3a530b4d38c5c56a8bf9111aed06	1	0	\\x000000010000000000800003c63fb0bea8d5f74420f2131d65d77506f8686c69b3d250b15f5dbc625e10b032197f846fad511f0f778716081752bcbcbdaef38e67736a83dff39fb0e50ad2e128381bd853b8fb9449295a3cf0666e323f7c2f9503263917a8c8722823f6c6b4ccfbc4ad1e48016482e0fe364b2f17b66d298a80f3a22e88a4be8ccc2b539beb010001	\\x0cb16e2f7bc8477ddb0aa53de3f6c94ba21d14452deeb785766ef8d3f266d3829af682ded352da4ffc928bbe84d8bc080efb96ce22db3b23f0083ffa73377105	1674162702000000	1674767502000000	1737839502000000	1832447502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x924086646546845b733cf549a75351fb5a7cf3f07461f48f090e956c5372168eec776e9cfc8f8d4c53bf3d0b81bf59dc5997b0d6948e20ef12d5518cf469ffa4	1	0	\\x00000001000000000080000398bcd2fe5f68d90b5c9649c88668ff0aab69b0333747b26c6692ac512472b1a2e0f804d1431fe3b82fe5070ef57bcceb2c9db640b4142fae633f5d15dfe3164a59d726730390df279868c424761dae1fb694cce810adc79eef6af3330b8ae5c8e9dc191df37c2121bb92c44c7e290d13e764f689ff39563e90ee166ccc47058b010001	\\xa6f184601c4d3699d49a9960c23f6a2c032bc6052f1299724e525085c228390417a551d7f8a25e3b551f1de1c9fa6033a631be51eed321e102bed47c680f1b02	1668117702000000	1668722502000000	1731794502000000	1826402502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
64	\\x9284044446f3bbf1688bfa1803ca6edc3dbc0a8635a87a5c2854714855833e25f719caef20f2b7f35ec56730afcf1bcaa7eddbeff2447b83b42f7373d2301017	1	0	\\x000000010000000000800003a85f82a0e74f89e6a85f8ea50192fca32e95e0d8ed905b8c3b29b07bf6c46e089716cb7d9e8d489be1542ea827c3ee58a605cfca74160031eb6856a756414100afc926b1ecb0a03255bf5def8dac550846ae8c2d3380e60cc49a48bfb3a1c3e54986df04a9deca86a5cf870a475b055aca8924409c9b979035afd46c2858b739010001	\\x1994c54c75b5d517b55df7d72f3af7651703eed8ecffec603ac478d648d6d264f09191ae3a0edcb6a61b9064ccc7b76517726bcd275ba7ee402e1510caa9cf01	1676580702000000	1677185502000000	1740257502000000	1834865502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\x95204a4d740c8ecfcb699b6a5c50628b55c462b8e7c2768c91f86da65220a634d59a8f97cf12c184dfa6aa3f0b1667094d8093d84a6b75b6e89e38d77bc61ccd	1	0	\\x000000010000000000800003b2b2cd60725e45fcf01df99abb0c6973cc747a26341459903eb0b4c421ea970c8c9fe3b78b31b71dff66ec19db47c8b8d24fe2f40c3cca42b49428690521eaf4b46ced88b96828e34849f6837c3581f41b4e3be5b860958bf62513a49dbffd0380c7eb7fdd2f51aa3009441c82d13f8682530c9a569a2530c14397fff4b82811010001	\\x4b72a57322251feeaed87ec08f01598d5e492421988eb453de7647abe9eabd62e803444171e0654b418c6f3a479cd0c9e8591ae7f589a6f5e860bf5cffc2de02	1659050202000000	1659655002000000	1722727002000000	1817335002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\x979465cd223b48e6680a49e3b6e2421cf555177920033f8f7fe4a41bfba0a64288e65551ba6da19ebab05234860db0f7344ac9e4dc63258ed515a03b6eda4016	1	0	\\x000000010000000000800003ccfa2a5a0f7521c9ceee3b789709f7654e967e91a090d02dc382a0864305a64a448867950b1d69be34eca628aafbd717e4384307153146997616c8506c96a78445ecf41d841d7647ea1b2ebbf48b55a7cad56ad97ac42035781a0eb3f95f63518b0045906e3fbb90a866481690df103dc89e687d180924ca25c3ef95d95e62e1010001	\\xf9b413c21a59d22f3e0d615e2fb235b380dfcb57a2251ec2c91bbca30c756d098ed05e08ee57015fde6905d730ef3211d108cf8494c550d5ce8accd46528c804	1665095202000000	1665700002000000	1728772002000000	1823380002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x9fe04ee3325480bee205f73fa8098709eb15805ce4a94c8bfc97984acd405b0decea2e834c69763eb0e6e60f4a0f1156e3a8bfd2520bc7b990e96897e454b70e	1	0	\\x000000010000000000800003ca80ec14e60e4ec3fd91fca59535ba41bbbae73a0e056d7e279a80130a1ee295c46799bb587f8bd12f17c281bdc695a588be40d2d9a898b4e55a623a07b5cd4568a1c8456cd6abf9f57037e4aacc221fc36658d780ee43a1b367b0cd014041ca5c55247787cc8315a13e4c42322d88eeeb9a9d1a60d78460eee62503df3a66f3010001	\\xb9e6761acbf5d5b4eda25ccc8d05331f96689a640ed5666810d887a29bf888ef442fbda907736e2627715e3558621bebc85083f71d05bebd4a388fac0b03370d	1666908702000000	1667513502000000	1730585502000000	1825193502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\xa428662de4b8363da048543a90d2218b210b7205c842d77114426b0cf7d9f625fdb32bace6bbc8788d18bfe651ec931a2e63e786f3f329f37c4c335d69b0d851	1	0	\\x000000010000000000800003bd8df4285659024ba209c84bcac9aa9329e6ec6412f9f5269022194d4fc14388099e0694a87cf99ae0dc68d7e951bc0078125c42343da0dfcc223b2824b6fcc9043438ba6ab303aed1a04d7d17785a4fdbef4e5a6a9c5547bfa465c2b2c894e29de58a40869972a2ea2dbccd3eee44af07da79f3df2964b3618f6bb2b079fd09010001	\\x5eb796ccc6ca52afd24fbda492df664a2ed8b7f1411a332228018ef666d8861ad450ef406beec8ac73d7d64819e306c896348390bb07a9bfb47ac439bccb9409	1677789702000000	1678394502000000	1741466502000000	1836074502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
69	\\xaa642c8143b79a0fe166bed0b0623e27122f5a41959d106e30a5e8289e99c47a2e18cb85423fe21572a7266767da85ba9a57c77ea9d9ba657f3da7197dc10f81	1	0	\\x000000010000000000800003ebe117a21ce1e5c59a6efaef0219c9409613ad4bf15f176ee442ac3ced90654d0a25519eaf32eb5d8475543999cf5806ecd656ecb3a61f33ee5cfa2c77de90efe52cd465ab4b2f33e6759b53671937d8729ce075d3602842d8f343fc6ec698518b47480afb612e1d2aa00194240d82aff62aae75b91d1a73ef1bb7b85082f69f010001	\\x583487309ce637ab7f8b01917bdc292fc92e02c5d000d3f425b633d1ba81b125257c920e52bd5af4664276a44a393eb0afa4b9d2ba62717344e7836f518ddc0b	1657236702000000	1657841502000000	1720913502000000	1815521502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xad6cffda8d2015ae2cc96bd2f2804d07053ddc5e0c86e1790eef8ece86647ccefe4bcb0d967a28a3f1687c845163fbdc14af55ccd5c8b1539f998a53bc27e9be	1	0	\\x000000010000000000800003c67773101083f0f08cd32991b76889606f6548caacd06a6a746f4923c7c8db7ea2a44c81ba33c44b7cd61cf561271443a32890e6e36fcd858e1b36c47ef9e214d5e8a58f488f57cfa168b2349ee5c05e07206a7d0311e4080210c9acd1ac9ad21e5569e5e148181ca6bdd7d73b1c5c34361d81d2152eaca4ebc09896e2fc6f2b010001	\\xe15aaebdfcdef77f0861b4e4cdc1fd960b3e1fe31ec46164d5b51fd190305c64906b9a32f2f43c96748dca601eead79b8e183256d93ee224129c40860c13a107	1648773702000000	1649378502000000	1712450502000000	1807058502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
71	\\xb160bfa7282be2167f016d31d3bc1eb77d955485de96371808077f0edb4114050c994f1d4683c3e55d63955adefa4d830de441f6b54eea51f22b23178623115a	1	0	\\x000000010000000000800003edb6d15efa04864f2241c04389cbeed605736e2c20e2b9f3fec4c241b0aff6f65588511c84c374544ff5b41bdeeed698d1b80a19d39dad58b84939c55b77757d5232b3ed695511c3b79f45627965d6a0f5f940854b6374bbf3e0a1990ac0703d90c7c82a7f97d1ef2699e01cdfc96525e9944c12b0ea5b9f1db34dbb4abd1cf9010001	\\xa4e9e3e52d1bfe7534321b2060f1d885fbe64350f56425d68fac6b1e032f9f17e41b55f4b1bf4c732a7b8074c92a96795e281e5607e5a330df1b7c793c19b50f	1659654702000000	1660259502000000	1723331502000000	1817939502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
72	\\xb2aca3f1f8eaa661dff06fb546172fab389e85e41694b7edc3af586d4d6ad1320b4523af6d7e613b53feaccac4b054c9fbad5cb3e4080ee016334e10ab0a9c82	1	0	\\x000000010000000000800003b3e64e54661b2bbedca7c9a7a697bf6a40876f8ee604d9ddfaa9877145451bd65ac2c86772e222ae67fa698c99ee77a6b50c3f9af751d823ab7e88171f633d76a5eef437745d00ed4020b1421dfd059c56ed9c57ac9a63364b7ab489099974c40aa1e7c05e29599fa414645dfbe186fa9a89b8bd4b80f37fcd6ca9356aa6b367010001	\\x184320db5eb0927b20c5fe121336851662918e519f93dbf6f20abb7c1aa7fbcea0b217ffe9389a75b0923b470a3eb83692e46cda2a988817443967560f0e0903	1677789702000000	1678394502000000	1741466502000000	1836074502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
73	\\xb30cffd1fe786b4a2e7f8c5745ea2a4fb7e6e66ac87d556c498d4977f1c090090e34e30c9147e48020cbbfd7cc30a957f0340d51e8b1a595bc6af39b4eb6066d	1	0	\\x000000010000000000800003a1bcc4dc57dad6efd7dd0f46c4fcb748ffb9eae0cb9773e36533fe776cbc8e852c21a81e6d91c50e44d54d830c3ffe1549fee20ac02250d45b9144a51a87a715948c82f6e39c69aa72a14d6bf277db9ef7ff2dbf3b27d5cdb6b7f0be42aa059f879eb7e695b746bfb64602da3dcfed1f0a609f13a281b439833c37545ef71955010001	\\x5721e29028a328690d3b6c63202197898f7a7cc7d297587c70307de3d3d0a9b5dd94858fc041950f7445bcbd47a875390f7651cb13e9aaeb0df613d897de3707	1672349202000000	1672954002000000	1736026002000000	1830634002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
74	\\xb468924ce536e3da45c99de2df1b1a1147e901c4a5ad020e29b254ea0712e010e165c65f19d3d94732c837e78538fb3d8ffb10083d60cfe6531787cee1483847	1	0	\\x000000010000000000800003ae8495a997d173a072b72e5b99686bc197206aebb6d5f93ba0980a5a16e321f7b904d2c6a1fc2b0773f73a487dd3a643d16d09365fa770ffbd5c1e9b5c999c96e2ed0953dfa7804dfda6a97124c2e49836b86933a3eeb549c64f9e02d7f5e3aa5a0e898689f19cef12ae3221e4d97c86a1eafccd6fa94a452a24a9d822ac9a3b010001	\\x4f4fef7b94f69b7911620f6a5c5f1367576291b7bf346e868f3647f9a0983bbcab3ac8f0145c96e848579ec9a2de865d9e285d9bb2a60fe377db74bdce4e570b	1671744702000000	1672349502000000	1735421502000000	1830029502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
75	\\xb9cc960c9d8a59ebac1e1659ab80ba94591b5d89c0d5db23b9027b31a7d0f223c0cd49ca55fbc1acc0424bd5ab24312b7d5a5350dc88f4f74fa3b7a2b1dad499	1	0	\\x000000010000000000800003be2583b207b4fff1a55e0772358ccccb6f563c288137e9f296e1b52a850d6bef3777e2a8477b63c345a9466425c18663db01f3301d93ec9a0da57cfb046efc6c3b9659481e0e4c75912356e3b55be5f272b830f33a4a98a48a6f1200c6d3cc27bbc319276ac2f2c2fed105fcfcba81e0d9ce4966c051ffa2c2d5cd34279cc907010001	\\xf19cafa32f10446517191df855b180c1fd90c482a335f1437a4122c6a6b934289b589fd803cf10040dfe9685417f687e15fc98d703efd6a9d4d3405986494b04	1671744702000000	1672349502000000	1735421502000000	1830029502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xc1a07f035755c7803b07b23794aa3f7eb6db38bfc8e825cbff4c7579b21d1a426a9c2f26e2697a7d11f24c573c71cdf26b5548fdc58391c8c7795be1568cbbfb	1	0	\\x000000010000000000800003dc95aad3bc62f604b2eff340da4cc4a7044198ff6c1306dc2968df398c4bcb0488cae0db7dbd3d54b8cff595731195ed7a7049f0fe78481a9806b7a32bdfe30f3851d8c9b07425e6e4e34fae7cc5429c1b9f92146a80ab62328add74a18d8416ea4e606e15b8242063b27ea9d171892107f3ab7bbb5f6a4d8db2c1a83af386e7010001	\\x2a3edf84ca75c233088b608621c1b554c95f22f77514eb1f2368244c8fc3eae8618a00d5a321ace09df496ace3101484842b8f20f2bddcf3d4edbec4cd38aa03	1659654702000000	1660259502000000	1723331502000000	1817939502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
77	\\xc1d4f3fc39c6e38f93af27a9f46e1d8d1986c0dab59755fc0ee1264979c419012db4a63b7b194551b45c9fb65a5d0cf05d9d9ce320751e5ec634f35817116610	1	0	\\x000000010000000000800003a7b9e0f2822614439be53b5203ddb66d1ef4e1a95d04dc464f8984f5dac2b7f8d368454292daa144d4a48a06dcbfe594e50ebae902490dcc84ef80ebf8e8f1e67f55e14efd77815936bd23d06c456428c754e3f9456e47f439e55747adad2e3dd2ba24e8ff89ab239a2efda103f0770fed0938a64d00842e30a4eb9572801327010001	\\xb7dd6b1200ed1f89b5408fda477463d8a5db8b671fda3299161bfdef25306dd1bce579b2cd12f24c0a78909ce7ad070d6cdc89a0e0c0c3f669e6edc4e7d1820c	1659050202000000	1659655002000000	1722727002000000	1817335002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
78	\\xc57832f6f1b857fa2d13b11c9262048207adcae65254803f496ee7f60b2a41782ae3f075d0d5a1ce188086226d02a6a490b0126321200320f5b8d3e488724eeb	1	0	\\x000000010000000000800003b2d3a0fb68c171cf1e0706b804aca359c792ba30fcec15e35d00cb523229277e17305779335fdaa4ba9cfa342598c7f6d40381bc3242fc6d054c2fa55ceaa3ad6abfd40136d0fa7cde24fd96e18452218c478be33e5590d590cf53cf6266eda082e501ad89b88c8c80ed057eada09bed5aa6aa73582abcb35e67d9081c300329010001	\\xb73f8f9f7023110f6e357f2376d0a1b4e842b9bbda4a3ee0ecc55a3be11756eae5ecb0d54410254a11e39fac6cfde8d67089470fe5c697f33fef9eb84f64560a	1657841202000000	1658446002000000	1721518002000000	1816126002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xc7fc17c97ee4ec8beac1b704f23f5119592c1a6ac354979676bee465c036a660ad183cd8935fd91c1298db2783905688c07f1613b8628987d614ac040765fe7f	1	0	\\x000000010000000000800003ae79e501fffcc854f8003a799738cc4f59b462ef1ea03bcb498f70323059b5aac131589ce5c047ed61c8b7a790370d5031be1a85cbaf0a7ebcf3736adc080c81be949c995f1a3a8b0036eb504c67120fd5c475ef511675cdcabf5acf648f66c3a06af337ebdbc59677181ab6c70e0904545c4e8cda66101ba2190c05fbf30007010001	\\xc3b859a7c2e2e99c26de2925d1cc1e2689c74e3e0d4b514cd412903fb3b88de13c87d5588440be721f7747c8d095e6d9d2b4c343f4d75f4026290228759bd501	1665699702000000	1666304502000000	1729376502000000	1823984502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
80	\\xc77c323c7ed3532212eef5a15dc3aa8a82c9bb09eecd40bf1ceaf9a19d421009abbfe0bed1bb494a89db7c3002d571a30046c8d05d39f98519de7e11fb80aa8e	1	0	\\x000000010000000000800003ad453cc03f86c522a38306a1dfd5297f6c2db0b0d43ccfc86cee0d78f1274cb0c1f43ec5845745230e188f3870c7cc28fe4197098c5550473ccc929989aa01fa80199a922ae79015ab7dfbb9787b2f3b985b871c169012c5a1a1868bcbc6ff35a6dc90f94f8b7d01606b430bc94f181804eb3f7c02d5eca91a8102f73cd6fced010001	\\x9edc8ace87b99d085cd2113e20919d655844a6608611d8ce46f39ea5d4c3feb46701abad2c4ea41dfe9b7098fde6fbe6e645f74ee630a421378ddb768f619006	1662072702000000	1662677502000000	1725749502000000	1820357502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
81	\\xc858e0b8ad32705445630242bf676e1f7bade34064a1f3be46fcd4cc8eaf8a94670330745fc7b921a054aabe211f6d3ed1ef0284152adc1588253894162e746c	1	0	\\x000000010000000000800003ce076dcb700d3282cd67b9a342fc6c25b71de77ceea2a1d74f89db2927c1afca7f8c360853021332e1190bd4b7cb2d2c38488deff470df7429cfd43871aeea95b3c5834542f4a2a0113abe8bd101f5721cad922c765c3b6cad52ad7d7a18db4b846d16e22265795cbdf446d3ae90248db282744f622863c86ba989483e8e155b010001	\\x713ad7e132f7ecd9ae3a8f150f0b58aa9f2f945330115425805844b334a754abd4300e94d295fcb76b4de63948ffa07d0fccd1a596dbd311658fee473243ba0b	1673558202000000	1674163002000000	1737235002000000	1831843002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
82	\\xc9808a630b122e19a942911eb28eab3e7d70088b9df7e98b6331273d1c06a86366851aaf9452dc96aa7b6457eb0db28c47b525e36b5c822467ee88099cc2382e	1	0	\\x000000010000000000800003af901d66ab8f28b4720028d079b450e6fd107e11dd49a20bb9516decd84bd66394af32e6af133629db38897a82f3ef6718d72c9267bbcb0b8f959849641184f32bcd5572d8a7be027bb8d1fc33ae50b7250828b4db8c8ff9696e88bdab993da602f8ae0d2d694cb2b6fa60ce4122a4ad3039faf2a15ec24593a037dc8e140265010001	\\xd4111f8e4e8478e927d47bf8b9273dda71bb377ffbd181472a0feee63f32d612bb98c9f8892c18ee4a88dafb16e077dff70b46a2f9948ecbce8f14f0d7b49004	1669326702000000	1669931502000000	1733003502000000	1827611502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xcc5ca516da067ffbde5db0ca85da69757be28b1dab0553a05731c5c70e65371b11a372f3f18801e7481dcd70e6c80fcdfc2ef8967f7e2a035ad72b6749e7c148	1	0	\\x000000010000000000800003c60a6026128f7e560120b22dce9e8c75d43745d7d4e6524bfd8c3b75b956b75b85c83411ee28033d2e2609499ddae5e5f902852a4579910e58bb88cc75102872628c390093045abe5e47936ee26ec105c5c60a26a8b577ca83408fd9ccebcfc0787e47e966d98a151d28a17be834cc3f3601ba2c786b7c0bb32e00a413f32111010001	\\x06d17cfeb84c13f4ba118592783dea1e070198fdd422d0c9e08cccf58abd56f267e9164fe85992a36bc85872cb0974e17a33ce4998996c332488422473949f0d	1651191702000000	1651796502000000	1714868502000000	1809476502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xcea4ed82060c53eff3c9ceeb985db724e32e9dd323f1ef78d3132302798961e8c295c79a0e5df14258508e313710a0bb3ab31070f64f8e4d14b93c852a697392	1	0	\\x000000010000000000800003a5cb87c5738dbde528a022b064865060b561d4398e7d940ae69d6cf0d66088d203a78d39684c3e08189030616531abd338ccdea47722ed5bc2e6a1b84dc5b1b2fb2db548346705438aaded598caf2eff84d8f61e54c41d056941a3804d2bd380fbe05dadbf6f4357cbf2f4fdda93f06ea9f99e346a0cad829a39e6ab0d68527f010001	\\x1133904b26086a844828381ea034a7a87518fb412b4e5598a894b743cd40b871c3507f444a486c0ff6e62d5466636f02223c86411bfed07f813ff49ce754f606	1653005202000000	1653610002000000	1716682002000000	1811290002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xce24840a5c7f72f877fd083d022c3bacf80b05fb6027fad0e346b56021198858faf07044684bead57bc083cb24a0a4306f11c3364a52ece31e3a42e580cdf9fe	1	0	\\x000000010000000000800003e52545c143b96db093dc30e50764c2e9051a3f264dac8d75d94db57f484fe88b511bd23607ee88d82e751a3a60d5fb1c424fa8f29a5dd1abae5f25bc26be9546042d046ec73c14a2e74bdb8c9bd622362d07c558147ffc952db2885b358b05ce7e607b628a7070958ccee598008c9026424d6c3e00799c8f2bf7b24093f8e233010001	\\x1481b6761a7a11236300ce5f282dc2bebfca945e952c3354ae5530513c36dc78c571a6f321436036be7be4b71419ab4c2b2960ea0f0642cc5cc0ef19babf080f	1657841202000000	1658446002000000	1721518002000000	1816126002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
86	\\xcfa0c18a277bbfe701d0506b72b1116468fa7868441eaf0c041dc48e56c3f74a964e4bcedb94cb72752822d81f0d98e32d610e6ae848b43b89faf8fa71896e84	1	0	\\x000000010000000000800003ab9a409416c2776b0e29103abb009d5af34efb91867abc24f68e5825340bf6e7d780a16fffaa1cc57d8dbbf18233c78ed4835dead4ac7d9e4ff09387d6638fef7e455f9c90ac781216cc7e64a3c2680d1b767f8952538f0df150135d4172c6f16d56855ba6ee5174fdb81960c3cbb2280a005a255a85ce81c8ceea2cd9058f2f010001	\\xf17cd4f504658650c4d32d2265e3ce96645ed985a7cece667e745bd26ea57aa27d0eeb415fc4fa5c4202e2c150be85ed5a9794f534376e9ca56728cd6ac73403	1664490702000000	1665095502000000	1728167502000000	1822775502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xcfc833954ce168b5bb6dffe1e4e3a92307d7257c568c4e2e71c791d1b85e778d020b20c831e814374a0049ade67bd406934bebdee2a91a7d4f262cc1598177e2	1	0	\\x000000010000000000800003ec81d2fc0ede0fc57546ed869742050d2cf7fcf3f8227955c770f52e98723bdf6e4c3f0140291325d67f19e2aa253d572b7d8ec477eb4ac9a0761e3577295f289ec24bedd98918909d651ad18e1f7c423ecb6bd022d0005f3263f6f8e5de823b64359f94a453abf6d569804efad9eeedcf72eafa2dfd25440160ac141460870b010001	\\xd464348354bfdc0fa7e940cb283846eefdb42f9e1effae4fe61fc56b56b699a6e1c9181b087e306921652ff7aad50fc0c5a06c4f4b8f1926f10e83fcbab27206	1669326702000000	1669931502000000	1733003502000000	1827611502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xdd9852e2b36a54d7898b61e39ade232e443497e1941e96c9ef9937ab471795d79928ed69b7fdf8da7c2983b3b5718e12d6a34611694e03be58fdfa29892e29ed	1	0	\\x000000010000000000800003b6ab8b4e4aca19122eff13d4fa1b50af80c8e76140f9e3632bc90ac996dd29151cc315ce5696c94ea2e3bc6c8f62d409fe8e7aa465a151a68e98b484adee63ec38ee45a1fb2dc8f676451c6a95b5878e770be37a1a80a4261babcfa294f4b2e5330544171993e86f95c05c5123fb9562e9868aee3b6d30addc684d12b83d7131010001	\\x2ba8fe45fa03f8683b6e488cdc82d83c1a7e3f58488159775a9a2990247af32f0354fd8dd0fecc58838661278a92cc74b7df52ec030db0c77a6b98a69e648c0e	1660863702000000	1661468502000000	1724540502000000	1819148502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
89	\\xde1ce25b3c003f3e5f5521731ec51eef742110831a59618562e1ea3d9a0aa25c69d949841720a086af3f3968ba7503989a5f68f0d94cc3d4039e4cab10e36525	1	0	\\x000000010000000000800003d2159b1af43cd37e859aa98488dc2dd7e13a6f3c6f60521a785fa39816309af81870c3e21271f958dfa605d9542fa906f0283b47cd4dc89d40e318f79df94b9d4e3aa57eb46990457e38213524b88012a693c63bc37f83a4d8381e0a2333ed28fc1b524e6ac70dfc1ca864bf2c6521489d5a23e3fd4164a5be558665d65b384b010001	\\x39cf837d86eeac9c2487b0e56a318f243ee4cf685d53aed8c43532fe1ae21ef2c1af6a78aa3516d342312c410fcc91ba2affcca1312b0d8803d6dc4a22457b06	1665095202000000	1665700002000000	1728772002000000	1823380002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xdfb48a1244192bc662d23f77b6cf4f1c30755609d7686ada58298dcfe3bf54aeb648cd694e24b503b78d43ec5b70334e69e5acdfcb7384471784d8f4ce204d60	1	0	\\x000000010000000000800003a1e992320560ccc4dd50ed1c04374598e92532e4140a643b42dc014c8fe6c17487716d7fdb12df416dc455c41a98bc89691376a35937c28f3921e3c8511d47b894162cbc636a5854a0e9633da7c9c911a569882c16ae3454760b6981d8d6dc15e0fe6a181eb9fae9558e6411bd9f058e92111da7d487ac024e0d8ee6ace846e7010001	\\x1db82f94e1e0f92414bbee8afee94ee9d254982fc5ff30602c7679b18fcd877e4ee135196dbd291c21e095b16e55c0a8629f523c053dbc661f4dcaa1a2d1f906	1672953702000000	1673558502000000	1736630502000000	1831238502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xe2d0d4f3437816c7230e4c2f0036724ad9c561391dc798eb53ec4735d915e861ca28109be8656af5c22044852d12192ab71fc2ce66466d48e356e9e1d8fc2d28	1	0	\\x000000010000000000800003dbb2d6bdbb73ce0ce6fd4e0341d2fb8faeded7141a089c51277e6fc48807072f559d71a225de8840976c2799cf9121774fdb52da32f9a6a7412740c535554a89783f8c1af5f011b5cb01c5d2f3f793237e52a31464824ea60e3220d6fb40c205dcc43a04061e3bc1f36e1bd7a22308298694482ddfa158fd7a05c557cd20a339010001	\\x01e3c289fea1cc5e81b14a6e56df3883e7461a5f61ff09a45cc6203dbfd24c4c91d59c2a36caebc53df0f4bec0c3c32521c901a925751e3a606608e1ee55180c	1665699702000000	1666304502000000	1729376502000000	1823984502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xec607a56bfc8679b532003316b1d7b1dfb08a091ca46b5b24f66a465fe170aa75475390e501f6715d6c69965b773a6011d5e98bf278810253fa72f24e9d97df5	1	0	\\x000000010000000000800003da8f993a410cf7d30f9ed895ace18c2c459e135e219c7b771603ac60c665e9a49694c060a10f84663eb1bad9420a3212732316644287762a3203eeba1c1b12206dbc82ea484820cd8042aaa0c659be554c00612d43691241825ab02eef156a723261addb10aa9426d31b32ad3b4f4ae9ff512111113e21337458ab52b34f164f010001	\\xa6e003736553f2fe6d43ad4bd55fbf45592ba740afef195d2999a8910444f33b7e074e7860b8b28bd3c3c73f17e1d9ba88e7217779dc4c01b0a6d0fe50dcc00a	1674162702000000	1674767502000000	1737839502000000	1832447502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xecc454df6a25f1eac90b6837632bfbbf30be88a0c9a44ddb9b693dd034c801dd32fca84f46398b7a69930d1f1213ab726da5713afb274e8085301db57eabee70	1	0	\\x000000010000000000800003dcdb108a63713e0764e227559d1698cb8b268ecf3e16ea2515738f62b0c39122f0800ca059b9aeac2ee145d1524027b6bacedfbf7d2bbf607e9c87a75de4a8b635e77d2485b776c8d684e20d336b08fc023bfba633fdd4d6aefa3c95f9f53427f3caa30e63235d6fcf43cf042e53bd89c023cac1b621d29654d2d8f0291852ef010001	\\x4ece8cda80e14b79ef51338c29cf8f3f7e943fade39f2af5c9a3fe47237e52dfd314f9b3a1a3e4133d52c9fa6b5b0a0a06019bfe3e8c3779536e85b531e99407	1673558202000000	1674163002000000	1737235002000000	1831843002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xefd81f45c01fc81db3df53eaee7d2d1401eef01073aa322cc18fdc03495ff8a1aaa30412ac2fb0f884a386b34858174b706881fbc04b0d51ac7c4743ffeb0405	1	0	\\x000000010000000000800003c9776672fc4329bd02fdfa067c3be1c87295a68861ba4bbdc2415e73cb18a4bc340a884f531b87b913e59fdfdb8d67bd808eae1dccc0c570bf5cdf7d7d6dc252057c36fb7e135fe0309f0e8f43a76f8fb8eb3fc7e5827727d0a339c90b9e1070c162cf58b18c7ef2f7e32d2537f0f0531366ba3bdadaa808b636be05265c4277010001	\\x5b283e9516f17bfca46116f9da64cf8aeb19cf8bb2d2006171f53cedde33de9dfc1ec8d711d2dbfed08d6ef6dfcbc0e1b959aad257891e0d26b14b7abdb0a000	1666304202000000	1666909002000000	1729981002000000	1824589002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
95	\\xf6609db04c3cde6bca69c4e64ef122aef28f5f6a625da3b5d0f337cb195a702eb224d46b9db7ae24ea0f5ff89e8b4887746b80171d3d5015ae2ec5330efb0abd	1	0	\\x000000010000000000800003e052b6609916f998b5adca20b7d227a5cf542d9a47ff6b497a85b04823bcbe5050ab379693cf5b8ca93ce306426298a94aaa2bd9783448e799923a4af331e489454e78bce2ca5737186dc748765efc36ffc53210c9d06128b08ba3fbafe7a624bb083f41490a92b528aa906a456b281382764d775bdce0e2ff659404b7c6c3ef010001	\\xd82bbc59d2e613267dc2f0be22b9b5c8627401739b1ebaa5f9d373d798ee370bcf7483b2bb5f10cb4ae3e50d6fc1880af8d894979087281d49401c21f6409302	1666304202000000	1666909002000000	1729981002000000	1824589002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xf9a8007332570e25aaae31abde439f9e162d326b834554b71132653395256e0936f3ff709307f50ee18ee8697b4864efced453bee474a6d5bd2a254c2d754d73	1	0	\\x000000010000000000800003b7bc0d4ea4681f3a3ce86db71082e84bf65f1ed5925fd4471da5732be78e57f8339e461c513ea827db8e42530a6d06af502b8adf00393a6abf548dc1c32a183a82212ee6b8f20bd81e97ca5658ef5ca8501aa1821ec4b3fffef3078653ba2364655a715bc2dfd7e1528ca66a953e644056c4b2d763a40420a7881296b7574f2b010001	\\xb2ec3b5413cc045902e58ac5dec02fb8a3e1671c171674ea7dad0f20108a180daed12f9f17162b521df4564754e986083ae5735c6134f567db3c62797d0b2f01	1666304202000000	1666909002000000	1729981002000000	1824589002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xf94466b9e427ef584c9ad7a491ad7cb426b3d4a663637fc2dd0b7593af52bd71c8998016a482171ea4f0d765c238a8def64b7318bf228c64234a6f195bf35991	1	0	\\x000000010000000000800003b6b1db40f4a532a0504e22d130c95892f9a039df40e8adaa89885337b965ad597a3cbc982f76fec4b8b7ef685736855c8a29b55affb23813b0a35ecba4265e1c3b7d5866b74215590c72189e75f831da2dbac76e175ea14ffd6dcb86bcc1aa5742f98c507915074838a0de87254c9fcf38d3959195f28f363c42f3a419a445bf010001	\\x5897979a89dc6c6ec826b7963a58ed509ae4517de24d585aed244a53ab9193814b76bc16c3337b5f0a160e0cfbfb8b03ddf34ba30dbed9d2c3914054f8ba9a03	1671140202000000	1671745002000000	1734817002000000	1829425002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
98	\\xfa8886a25eeccab556e73c8ce83fc5dc693584d3b5e98e1a7ee854104f73c3da37dcb9fd240fed8ce3617d3a96a8811faf69c4401221e607168ef28609b95979	1	0	\\x000000010000000000800003e9a00439171d3cb16474d26614c6062eee8cb0458221454ff65d86e7e9dc56af23da58984eb2f6b03f2a97666d7a908f546f32dfd35e66c845b37800ea9c43d5a6c99120a9232a5acdd9f5a3d899d26132bbb3c318ec1cc59f246b8da79e9e079e1fa7e442c09bdc29b70c74ec7d6c995f738a856337b019f7a3499b480753e9010001	\\x212cc8e0f30df9285e59dc9984e5cbe3fac4aa5134b72290893ee9b9d0c8d119059edd6abc81b10d3ef1b6a35bec926254bc528eed034f4b1405578173564006	1652400702000000	1653005502000000	1716077502000000	1810685502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
99	\\xfda460ff738db8f853890b27dafd9482a059821c477b66ad5c565abf246831e56fe1d67923a8282b800f2c14ca1ed68ec14f96eb4a22973e00bfd588cd75056f	1	0	\\x000000010000000000800003e9cdd5887a3278a65d7b5415f810c90d94d4c83b7b8c2fb20b289ba6eda55f58e08fcdeb71f51940426b13ace32ad8867895e422f3adbca54befdfc4a5de3e59616d4ec8d3619016274a8c4f38efb2cbd02ae68eb56c018751100090ccd6962506f97bab8e714cb9e009708d21b0f15601e4e2f7b25223a716dd788a18259969010001	\\x65bada0730c3395d1bee6eee20296a77086134425cb9908905fd0c91a18fe4f07a29b074068cb8299fbff4529bbb3e30957c70a34053452a43adcad71c26f405	1656632202000000	1657237002000000	1720309002000000	1814917002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\xfe4408c54b24182660be66e44120bdd5d24c4af5a732e7f8198154705ba10e685ec22e2637662fbf2ccf101f3c04b61348b1be79404a96b21b9a1b036810f272	1	0	\\x000000010000000000800003d1355950e7168df0a238a3628bb9a5bb4300047c2aa964bfa1a671e6a7022dd6900a6c089d24b138a9a85f2154cebdeecc19d55a61ec845490074af28aff60068bb98df76e6c9a5befabafae723fd7a1db7f6ac3f554d52b14a72505768fe01ff8936ce3e8639c5fce3b6ecc6df8f65b615dc92119244e54adbe7de9d40082a3010001	\\x6fd97fe816a1c5973018d2e32ab2a57657d8aacb76255f2af880bbb0c5d6578407c64d2c470551b2a661322429d259756c2047b27292070cdd69088ef2768900	1672953702000000	1673558502000000	1736630502000000	1831238502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
101	\\x01d5ffe8a33890274aba264310f7d7d3b0f3e022061eaa8d766b97a9e9fd547785de5670716d0538971997c794cb5eb1e3a9b7c539e8d79a4ffb07e125fdbe78	1	0	\\x00000001000000000080000392ad826f9dbfdeb8743662a5966d9d87a9ff59f6305d2fbfd644a69e51aef373ea612ef1164a0b446ea73e380dfe154d1fdbc9328c96206ef59b0e0faca1d820a5e0a02c548c5ba459184060a7f65087073ec6ce57b0ce66786bcc4f0b1ced52bb30dc37e2e3135e0b61526772133b4823269bafdf62170ec0155ae562b4c5b3010001	\\xfdfee1eb48640ff28d52eacaeb4080ef90e1c1dfd5b8bcdece15963eb4cd4a946a0f9ce1f6ef13e318cd1eb92c0e4ff1cc561b7491bedcb9aba69259e0b2db03	1672349202000000	1672954002000000	1736026002000000	1830634002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\x03e5df27277650b529a34000a6850bab0e09aa99657a5cc071cdda6c9c5e0cf05fbab3019f207fd469422c9b47cf1f7866dc98bfd439ced6c1f26018556ac7ae	1	0	\\x000000010000000000800003d24e4eb111fee42a086ca98e1386ff115607d094bcc274918150d89541dc43d698a1ce9d8e2aaeed8bd35fa0d6e6479f0b13ab718a0e948d7f5917468da5bd2da9e3261412f93c3ea52e9ba9632a680a1dbb982ae1c9e2049b46e27ecb14a1e52c0e14d50206d2bfaf1a9a78133437c32dc3016c05d0da5059704afed5545e9d010001	\\xc3c91b8ffb26fe55bc1f17fc12c1dfba6b84e1bf0a3fa3f84680bbb5196125b678f7cc76a3759c0316020218eb8ea9aa76fb2cd37f0239d18cdd91ae5ddaee0c	1678394202000000	1678999002000000	1742071002000000	1836679002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
103	\\x06d165f55b29bed8c97070e67c95515bbed41df6379bea0bd6f1964f497086735deae17bc67808dc3c8b30a20b2e8f31a73ea1c418a9f3cbdfb4385ead5f37e0	1	0	\\x000000010000000000800003c46698021ba38effc116d7c528a77db590d49b64ff00598bb6e8b66711662668faf41a92889856ad56ef398b5c4b576d9da833ce2437a59d776f6cb8a23d7e963bf9c7d540c94a2fe7aaf0a7e0b9ef7bc6c33c2ec6c4274e8d4607e763d38214312937b6e243288d57e197bb4bc03b261c70a3e3c89e4f685a04b4035f763581010001	\\x6ec25fac286ccfb91e875eea58d0bbcf99cf3e97604b7ac719674bfae304b1be1352de668467c887494bc6c8ce6d65d5284efc4f7d300e29eb744ca76fca900a	1664490702000000	1665095502000000	1728167502000000	1822775502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\x0bb1a8aed92e7fb29afe5dd7ccd683a004a0bb22746eee4c247ee3f8d280ba7f3680b1a82b35b835da86e5a18c288f69c553f08c2d26c72600e75357553df8f0	1	0	\\x000000010000000000800003cf4b8a95e31ff593109e5553d8e83838d03e518a482b1e089b487cf5ce8c0df8880c7a3c03a916978ebf2d675b315f680a39e9226b7062bd456b55cd666d13a712b07b381ffd8f056733541280d75c0d145a831c7cd50194859e01f3eb767c4154d5cb10f762f4b9d48661ee7737bc843088c618458b3c1abdc116a2c6aa6b41010001	\\xa37175b52309fd729853d92d47c47250d5610711d70df83e9834369e203cbf21aaceee19c4bb12ce0ee62d44929f91e0c097020153543ad5f4e325a176d84a07	1662677202000000	1663282002000000	1726354002000000	1820962002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
105	\\x0ee9982a2ac449d4d2aead7ba426586340c0610582a88ec2b457e3c70585ae3c1a7eec76f18441365f81b22fdcbc73b411b1202d6353fc0679f2019f0bfd0a32	1	0	\\x000000010000000000800003aaf957151c4fdc56df1144b5bb9be3d3ce7339b51a1a14f6404b69a4c293e6a63f43d866521e52da2b80be31fe05896e071093099bc1a26230c1dae32d9ddcf7fd2856b5996c77f35e91cb1152e35cbae2b591a3bc9db19e034a50ce3af47ddd63aaf6e7a49486e206eb89c6eb6d8dde27195bb93d688434c07650791e7aa3db010001	\\x303d3d6497a3f07580dfabcf05604b72829d07856aecc15704c829577e70f35fad87f61c8f28770f127b88d4b81dcd168f2aa1ed75d590560b462e7a25e02a0b	1675976202000000	1676581002000000	1739653002000000	1834261002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
106	\\x0f1528aec699205f14b73b9f2d4f2f9995ab09374fd958c5cacd92861b32ce95cb51e59317da9c4294a7ab10a4d90c6c734ff1d1df26af1d472c341285dc99ba	1	0	\\x000000010000000000800003ab5b7ad59e741c73263e79d5ca0799b57ed65dd15c908f18c0b703660918ad889b2323dff46864d010612dd0e04998e3079f28746261a63898e100d59a072ae3b38bfd5374a396607df977f5aae8ee63b58aa00e038c0ba0504592e6c3d49dcd7d95815deb3cfd085516f9c05b00bca27db1bae97fd134d49808e9c392b57681010001	\\x85fc7522b5fe1b985522e6873bba2fd99c57aba8b7757571a446e84e92c28da490fb27c35570c69501cdde5dcdcf47e8881683b84ea84e5466ab372c1f2acb02	1650587202000000	1651192002000000	1714264002000000	1808872002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
107	\\x153152f7b2236e23aae538452f8938e4d1d7c91f2aad70f66183a53ab8752cb5b078222169a7862fac592aef57cf4b33a27aecf6d3969676be4f692b6249a803	1	0	\\x000000010000000000800003b55df2a9c13e04d580c555127e3995b48dbbf7e1e190672b25546d9198edafc8cdfbcf74d92a31063ff905188e7fa6d3b170a2032ef1b583ae7976b064de450f8290165ff44a034077ef8687c1b9589d61bf7308221e69d5c760dc3cd9c79f10364754ae59b022d36e0cbe0bcf249103a9df57330b4f06f2298c730d475208a9010001	\\x640e1cbd51101590bf75f26a65f031ca6b64e7d7bf689eeb2e2d2b7845a15c276b9a2f852cd6dbf28231e88423653b525f9ceab5c19ade9fffcd981a2653150e	1655423202000000	1656028002000000	1719100002000000	1813708002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x18059cc7dafad80d4855a531f8cdc9f04fefd90af2f3b9ac620f685e4e966cd26844de19272a9646a40e81b3e558dcd071e7d60535272537f18890c7329be8e4	1	0	\\x000000010000000000800003ef8b471d07a57842385923f8316ad17832a6874940974ba676d826ee472e4c72ea2c3bb517d1c4f3121f4f0226cd4662660b33c2ed3a3ac0e1ef6cf75bb17e3a59b21993dd88a5aa1bb4e2e087211dd46a83deb607413aecaa45acb3a27d1b5ba9149b397db40d40ae5921e96b8e41744ac78d5c98693a06cad71d77cf2660c1010001	\\x451e8d12eca990ff5b5bf790e0d40dddca023b87b444ddc4a6b449c3a83429e3d1acf3f8eb14dd3fa22d452331148e61c417602ff0b065d0addcff61e1bfaa00	1649982702000000	1650587502000000	1713659502000000	1808267502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
109	\\x18fdc00514936bd2d9c51392c1f0dc3bf5502036afa3102cd20a7326e80df065efcd53fed2ce476f1e0063507316765367839ef811b2a047b3504f3b70bc7e08	1	0	\\x000000010000000000800003c30a260f7acd518452e253fdd0921afe91507f4e8d08256886adeb108ceb81168d09158fc8b90dc73fabb64aa99c7d1d982e40d84ec5fd31e533a6a7029b9b6e00ff8a3dcb95afec54a02e9c102546ca777431e85a860474d50fba30aa4884c2f5c62042fe50c095eb56464be07230b56183758228eff29976b3285b969ebe39010001	\\xdd5b81cc19f2168535a77b945f9a00484c531cb140bbaaa30e92e80554a56ec6973011e6a0b7f338e595f59108d668aa56ddb21f4d9c1c727cb5cf9755e9010d	1674767202000000	1675372002000000	1738444002000000	1833052002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\x19a5e3d224cfa54a5728d0a46242f3d948fb48e212b01044070a292f8ae8e9d4758485794b9031d0648f1d590e180134f0a0f70ce438f15ada1e6a003328ab64	1	0	\\x000000010000000000800003e564ce6dad54382dd5bef2d42fe19446678a21ed1b9cbefaf7da6a485ff2586d71b304c6c9f94398d9af8cbb233c333952b627cc137ca353e66cb2aa91ed82043e56675e173646f43e67333ef773806c33e61a962003ef0f61dbe0d41dee82c95e790a0883341c08767d699028338d7a691c4539cc84c6f9f921c9e71646c5a9010001	\\x8fe8ded4b7e613a74175e7a50631199afb169bbb4724b681e9df361f5b322f2f3df35fddb6e7de0d620ecba2c8a9d87b983fe9b8ec1afc18432a5398c716df07	1663886202000000	1664491002000000	1727563002000000	1822171002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
111	\\x1c0195c94dc2a7b396efa6b5b96438d570d728f2533a8ee7a78d36a121dda8e11d1924735cc2bd1427677d885c7bdacbe6eec15e81e55f0b6b26cae44502fab8	1	0	\\x000000010000000000800003d36cd93e50f53697562cbfca3724c12bddc11d5a099a2ce854ede7a60d194255618bceaa7b1d75c6c7b5e7cb9af7416fb1d3439b5df8b0ad5534720a7a1f09831fbafa11e07fd2a188b3f0de135e1101318ab5eeba4b609d54d44d77c5611a5e3bd46b30325c5efdbc3f8e07f529f12dc7d41e1639a350d51ca73126a6cf4fa9010001	\\xf4b8fddee3761df0722c64f65612953b8d065334bb8c851121d36c9254120fa6b48f5ad6067909373ec596bb8fa3dabf0af177e34e9ed1741bfc740fcdc4a904	1647564702000000	1648169502000000	1711241502000000	1805849502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
112	\\x1e3952555ae4358dbf06257f163c7df88005c6656ed01138adbcc4646aac89679606e47d80541c363a2fc01244e3e569c746c090cb46e66cf70d4e7f3427bc24	1	0	\\x000000010000000000800003cbf6ffdd68b4de3054e65cbfa529a184f5675dfdf45c153a678e890e54e162a6558aea7da46e1e56023004061113c3e45ca8096a9df28196edc6ea9796c0d9fc4f531d4e4127ef1a96e78f7aac4b783268eaf505d9d7063e4872c285846aec5e74557b4d353bab21e99e0a2bf1067d3b610061ba12612beac20acc378a5fc777010001	\\x3f5d34423a1b25b6e569eef67dff9f0055b8305ab0a5f4e16b6667e606fdb17882a0e2af6420228da79539ac83d9b0416a29f2d4c8900636b89c68bf65542209	1677789702000000	1678394502000000	1741466502000000	1836074502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x1eb1cd07c323a63c6df8c08552ee5914dddbb4f9b0d2f39f50445f5d7f66b59e238952f7082f809ddce8675c81e8c3728bb0ad86419ec71750c2c46c216569e1	1	0	\\x000000010000000000800003af495c501800b6465b201818bc6b2249afa64c43cb5b682511de326861474f21a2f5be689609f6ea06fb3f9faee55cd0de0bbd9a2823e0de9333fd531379cbc3dc15db8646795a59cb468c5f17197ad152526473d566d380ef693fbc769c5b3ebc1427e4d1569f336c2a68294cbbb198af9511b7f6e84c07dc56f2ca1fefacc9010001	\\xf0365a359b2a0ac30d9bae883b0e96a5751c2e1031c6f1d46b6fb62b3343905125123842b345c5650403cdfc2f963f869ed28e63aa3e65c9e1ee06c6b6d71808	1648169202000000	1648774002000000	1711846002000000	1806454002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
114	\\x22599e6a83b43390157c26f980477b698feeeb275968fb28b331191710525296dcad0186e9357a0dee9b48a0d3a3a64bc07c3787a1018d03e594158ac51fbdbd	1	0	\\x000000010000000000800003c00d1a9b81728571889bd4a78c32f57e12a2bcc68b587a9a2271e8ec065f6741f48e4545cb2e0746d98c6ead10db37b4ff335e8ceaefd547b26f09c0e96a0fe9433e9bd6fb8e8b569bb761d2396aebcee6c19116ebad0a30ef2b205cf8fa644b4b80744adfc2888ca539f460a730ad221aff482e791ab77a7ca0ee3818f77c63010001	\\xae57b24f1fab8ed06b7d97e6dba334920b2f03dcbda0eed1615a7b9eba0b80e5d11f57baa4547fb0a3e5f723a41aaa1f842c55bf844c0420d12d9f2f2f9b4008	1673558202000000	1674163002000000	1737235002000000	1831843002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
115	\\x2365d3e1176c28551e312d78471d266b7f7a9f80ec1c64ddaed7e022375c6b00182856965fb4af82f057c9a8bd18e4db0335a545d118566094d933f9309ecb96	1	0	\\x000000010000000000800003a6780d7564544a98f6d6a7bd44c701daf24ab35f363946365d18391ea1509b2d4ae72fa6c87a351c6d8f717445b5b8161ab8195963044b0c03df01d6d8c4b61c75c983347fc273888b558a831e547b0d22e9277e2494435b524121e34d160431af37507a1c4f0cd2c116e27b4acad6274f6c21d49cb7cbde1fcb45488fb51db5010001	\\x074007fc89a43237085f10cef93542ffa358430111ca9d14c809538d75222538e9f63522f599033b9a1836c0bfb285bb63c47734438f5ed9fe5b3a4f182e0c0e	1659654702000000	1660259502000000	1723331502000000	1817939502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x24b5f141085e0d523bc057e2f0972e0e33b2bfed9eaaeb28fe02d5fb1672a0c26b2935c177ef8c7085940dcfab2f874f36294671b8c9aaf326dfefd12962ec20	1	0	\\x000000010000000000800003ef1a238adfbe2e3410f1c0e06cc9805cafb590cf72f76151aabdf6412630970aec7fb21e98199f9a0c59b3266154cc6ea51254a74def325cfeaed8397b47225715adb75172d4c0f88cd9f5517f02a16828869841a29b56cd7b54f197268063afd6c70605659323d42bf9bad4cd757759675c82b6f2a440924864657d7d1e810f010001	\\x9fe276a4bcbe3e4b0bddee3af5f80e8fca194b7be43c0f7393039e857d3c9f4eb85063567880448f208994c941e0817011503ce09d804255fe29ee306752970e	1677185202000000	1677790002000000	1740862002000000	1835470002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x2571da58b93be525243a879c37dee8747cf783b42b57ca6ce1b7a6b2d3d491d007173166ae10ba38d5e795a2333eb5e48ae9f5af18f2182404c33a5260337ee4	1	0	\\x000000010000000000800003d309b1241714c7391a0b4cf32b5a359527bfe24bd5d338064f64bdeefb051a1b3606c0ddec7bd76f51db0e8ce07365bf63724ff8a0a06753219a6b423232c0daaab998afae81aaebd53cf4045c8e8b68d6e85ddd72c1742411b4d01688d5e75002a5f59497a708a6ffa61dc102efdd0e120381317027660fc815c0542cca8bb3010001	\\x2c096e4163a07fd97f056c4331fbaa9a487a457229c492f2c5252963db52fb01c1b7c120f9182b0c3c34d7e660fec3dae8a017bd08b0d82aa8d323a073e4020a	1662072702000000	1662677502000000	1725749502000000	1820357502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
118	\\x273962ae37f67ae02c82cfebe61ed3c6f01752a1352513c66026b2e25b81e364cd306f3673b937535993671f58c4f55007f7a339435f003844b153d8047a6a64	1	0	\\x000000010000000000800003c2f883d1a2d1db870d69884dd7d9e68f3ef019b8db6e6bf426ac30c22b4f965ef83ba1529e0e2a0b7ac817219631503fbde8df85b0a929c432b9ba96750a427d9d63733b92d40e4969a53f0c167c6f9d67cd1e2d71cd29145a25c087dfda88ae94d218406ce6c85711f6241dfb7c01b5dbedde1ad17461a0a99070af885e8287010001	\\x686bfc8347247a1783ebf6e4c63f8b113fae73b02560bda957ea1a020740160f05cec3dc105dc28441d6d1ed7f7d370961e9407630770daf6bf799915eced40f	1675976202000000	1676581002000000	1739653002000000	1834261002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
119	\\x2e75e81559f961d77028d6d8998b092c918e001f51be74beba446783feb75358a65be161a596263a625c9d2eb6d1ca2e54255d39c02ccfc4e705aaa8f946d270	1	0	\\x000000010000000000800003a1b1cfa00a8a3e43059aff699abe3bff638de13047d97dd98078956116e20ffb8841b2610d66b4ebf0fa3cdfdbe8ce1c91b5dde7fc1b2660483348148fcc693cf3d0f0cabdfb7a911024c158d5b85f74bc965e2141367932d33390df7521b91d2af386dc2975c3f4b588644d61cfaf1046bbcaa02f53501806dafc1b1dfd0423010001	\\x663924442b327d5341968089133dff068a66926dbfdf587806d4b991eb9be5a51ce80dcba2ae938a1b33bfb4b83b8256525ec38fcf77dc52c185062d40caa70c	1662072702000000	1662677502000000	1725749502000000	1820357502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x33cda9cae8214ef2286a7bca60deb95a3a8a480a8ac2c174ace3cced38e12d4ae12ff442dedcd873fbf8813de1553bceb9d23f3c811cddc36499f266b83c5831	1	0	\\x000000010000000000800003ce7c83c33b1034e90e4610d39e1b71b9963e6dc2145d2ed32a62459ca3a03a62d73536c97d1ecab73a3a146b3ace65b299d05c58e05ca85e8aa25764c716372f377717850f049f2bf42f1633710f687219fe1929958a6d8c7269bb2e6d210c7031a54bb500dc50d0d73beca64179f63d44fae2477e7d08514b5ad4b1f93d46b3010001	\\xdd7e4abeb31037aa76057be3e8b1cf2dc130b92ebbe1230ac445e239b75a7e94309bbb1a3b58dbacd0607970f52c332b8283928c9b29a49fc011f1c896e8c902	1654818702000000	1655423502000000	1718495502000000	1813103502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\x3575084bccb9aca88600ca6b776afbb2fc9ae2a12a56c52ac78b15563a5a5c0941b441c0678eb760a2fc6593d4f88d1f71ac197bdd926dd01a0fbe97c80f4ce5	1	0	\\x000000010000000000800003b79a020f0bdd001b9e08c90b372a7a24c0ecd857295e14d3cc1525fa26c6e595aa03a09f6141afcd7e9194034b241d989e2acc07d2d9316bdf457d8cf0420a4c94d6cc9953ae265534443b327d381c0d3c6476127e3d3013667d582023a07d91fba7af16f960254cfb6949e60ee2a2ef470da044691c201220cb0e7678dae293010001	\\xd44c5bab3bb83466189c0ca1b705c3bc3c4a30bcd69b0aad40e2ebb2a1f217f7b64331e1861f82e91081e76d6920747675db515ab5295bf79264bde21c7b7401	1678998702000000	1679603502000000	1742675502000000	1837283502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x362d8b2ddf228615e026ed0f999d1789bd47572a46ce14078362e632e73c5f62ebb088e5396729ed3aed4de4f07a7eeff36a55588f64ab914f41ec4d140252d5	1	0	\\x000000010000000000800003c1673d4f59e486bf198b3b97977dd8ad7c3ced4ce904b1fc8818f3eed459ba57a8c2dbf44cc19bbc699367708631b3fad2363bf6af86d1e1fd7098d63fea31d99dc4641704b0d6d87f83a59d04d1310fca4663b58744a52fd2a763bde27ab5e077e3770d6dfb2d1c957e0147ff266ee6fce8f49f106913c485c60b78a426ce8b010001	\\x94e70990da0dacbe0f70071a507620cb1cd1599d9505b45910d20a5fea56dff7695eb59651ea25d00d2a966b6e5cfa386c19453d7a7acb4b87ac7381e4c4620b	1656632202000000	1657237002000000	1720309002000000	1814917002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x3e358ea2f6c2ed1357f3724996b02302009cea439407319dc41b4715be16bba8dfdc816c9dad04d2abe19f8cc13becc33ab787f05d654a40f4ded04620b8c9c5	1	0	\\x000000010000000000800003cc048918c814c56533f6b64473d45d29f5549b3d3579dbd41cc247ee2bf91e3f6de73173d31d2ce8da02c64e2a6c88a7634f507e608128d361f3984b9af13cc533fbb149fcca81bb21930c1829dab718d627f51c2d4ef14f15bab6601119497b4598a0cc7e8e4b25da2b66afe601dd3ffee4c654360198979ef901285538c831010001	\\xf5c743107ecb6671ab62094fe3d08b7835eddcfc4db2f2e3368004a10fea0d3bfae7761090d316616ff802ed673f58c74c255068a624ae41b4f4ae957448880d	1667513202000000	1668118002000000	1731190002000000	1825798002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x3e911c53ea320b4c6cb39d719c51fd813405e8984714390bda1bd1eb80c3a9a9dc041cb57d6b4ff9342f1816b3990772d45e2800cbccd2dc0ffcf15b4ea1929c	1	0	\\x0000000100000000008000039d7a390c4632a4009148e6b221e9e45a22765b0878a9195d2d3ccf9764a053b51230ca7e5167d4d9178fa699ea494ad17badc4bee82275b48cc181da77bfee183a1c80f946baedf75c282bf3035d7536a0d0160a0cdc3100e0231309ebe288449a24c256d35a3bec93007adf3e51b3fb1c9bb5f69ddba6f062ea44befa7d67a5010001	\\x45b2a1b9faa92aca433c5b2d314ee1de0d4e2d3c91bc5e8fdd5f159b20581fc15aea0ad98a9f631df5405d93e20f36e7eb2ad02f8ec6de3af248a998c93ae70d	1667513202000000	1668118002000000	1731190002000000	1825798002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
125	\\x422905bb49ee7b1258621fd97a84f33ac2aaa4ffe0c1f89f0376ef68473e7e1666055e472f2185cd27ee5fd1ed11b6252aac12f01ad47ae0fe6a05ed5cacdab5	1	0	\\x000000010000000000800003c1b31680e434eabd9f8a7737705091bfd79ef362387e328b26c824d0302861560ecb14449d079d016e2326311971cc97511f7c71fdec55a4833d4e897fdb7dba6d79624f882a16c500298dd45b1f0be3cb064b1540cb7dd6ac469dbe772624ec40ce48380ff36ef8a7728d4b3b522b9be1bec402d20b4e5c45fe800932a2a10d010001	\\xe3eaace7515121e30c6035080eed8df9afc6c8b5b36303a8d7d8814aa54bd5f42724edbacef5ba7cff8078b3d801a8458edf19387ddf728f7cb94887f199d500	1678394202000000	1678999002000000	1742071002000000	1836679002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x459d0d7ffce830c69c4b2f59c410ef1f2ff1170fa0c4105f623cd2721d0d3327b2437f8af71281732b1d9e9595d92bd0dc386302fadf77531b58679b5b0a8415	1	0	\\x000000010000000000800003b737ab8a623b9b627b66922a8bf7868aed60f527c93ab3bf653bf75642dbf4cd37de44d10eb0c9697e34e51f9f9a0523c4f8e9493b4c0c81a33ad1198ed99f94ce61bd6447ea1a15a19d318c4781649283afc878bb7e8860f65485200331c8258019985416848652b3e74af7f4092a299b0081d65fefbf1f2bbf8dc864417599010001	\\xbb5c36d09e2776554d70203c8d031164da67d88043ad5797934da70a3aa1cb2d786cd7e497cfe27fe722cc3698f76e3a1ea1130d6e85e6609ffe08850d68770e	1651191702000000	1651796502000000	1714868502000000	1809476502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
127	\\x47a9fbab77be4c85922a9157d12bf58662154a3848dece3119f6a10a2da914a2fc289aebdd2c69376e80834ca05d9bec6a0ad571bfd0de5cb4ec0b0fa1929181	1	0	\\x000000010000000000800003d587ba18fa8067261b12896755e6967aebdd52b53bbc5d496dc4fc99944105fdeb6967293e5bfb224fd18b0eb91c6f19c379f9ee5aa03f8cdc413c0656c47b1d0700abef48f70f592474fec5a62d3966f7f29ee6367d1be4fd08cb06573ddcd817e811165e7b1037cc1bd433e9b259f6434b9143f7f624a9e77dce26c5ab7d39010001	\\x8acbb5a5818c67bd5975e0ae74c21341be714aaffc6c78294fe71a6b965f4f205d867d4e27d745c761cd030786a14a61615cf1250e4aa04569d6f2ed615c6102	1665095202000000	1665700002000000	1728772002000000	1823380002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
128	\\x4951b74a1adeb00d204f8d5ced22fad429ea4f856609664900dc7b42e2eee5ba5d76765938613d36843f186efe9adbabf98e1e4dabacab4c7d4ba2c73a5e764d	1	0	\\x000000010000000000800003a442f19635ede47f41d780a42e6c0536ab82d4aac34cccb49419753a8cb116df24eed98845915febeffddd18e1d9e24957c98a68aa93268be8f1f849d1338f6f09f31b7a0d2575d2d6f82f0b6a31e86d30ed4d944568f2c78578783cabb2cbd5f9cd73e2b54e55bd7f2ab4d5d27ad4795e8de9a17744d028ff9f2ed5a8847561010001	\\xd555410c9ab2a504b60bb6a2cddbdf3d6f620fe95abd8732e9516ba9b3acf70529285d275bb48c4262cae317c102cd4a1492797999d7a66c8bfde9518bf37b08	1659050202000000	1659655002000000	1722727002000000	1817335002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
129	\\x4a49cb350893042670dc165323667b5b67e163c155dd2844a425594fab283a5fdc028c3546f4d0de8aaf9494f6d3e84e7ec14677e463e60a000eb254300c7735	1	0	\\x000000010000000000800003c976955deaac2cfa4194b09b1a7496735eb309e77589fdaa73d2ad82c64b06a22b43972fbc1938801c519d3e24916cbe3c65f59c2505a13f3b26ebda45d32d91a13d398f8d2a6d4e9131521c8911c6a8d30a8bf3e97938d858e3e1c71fa531da9510a2f44166bcb08552a59580f682f09602db301cf0eb817305455ccf605acb010001	\\xa8d4d3e034e9b06d9cf070e22d5ec48515820dbed4cc3febce8eff26d11c8833b384521e33ef0414982781fc09fe3198d60a27fab447aa8d1a4daef9013f210b	1655423202000000	1656028002000000	1719100002000000	1813708002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
130	\\x4b2554015da9be46c99cc2b00e9d01528bec8088f6a8852b3daf3511090dfbe7a88d0df3395360e1f73964ad7a5104125504ca05bdca46037b2f27f26ad2ab75	1	0	\\x0000000100000000008000039f6728e1ea3ca4e146b7f33eb99a2533f5bf981213ae3cfd1e781c66e8d1b6f0c11ad416b4a8646490968db26d80665757125c2a9267c90abfd85e6c7f6e3fed57657f75f9830103c1dfd381a2f9f5ee4a9353f819166152bab076ff621299713bd72226269181b7ff834b09d1a8610aecefc1b6d80c1f002976333cc5b57453010001	\\xc46cfe4f6a477cb66f157035c45ae5bbf54c71a4b7f07178277d411e113844a301753cd35c9e35d9905af5304abc7335c267b94a019b1afac8b7504e6e145b09	1660863702000000	1661468502000000	1724540502000000	1819148502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
131	\\x4f912cb0bd507b5307376f8cbfc5967f5246db779292f740c88aa04d5eb1a613bdd75343f891700e20cad26d74e710d92db9d749fe250a0069210c06cd59e1a0	1	0	\\x000000010000000000800003a8d655173fb4a30cebef99e2370159e6af12c6192201737483b74d8408b59a2a0dca4a6cc368f45313f10378393cdf777aa62a12831be1b40124ec0ff7da26b0bc2dee02a22613ae6f58facb7c9c228da7a73f5ca8d0c51256188eb15c992d1308a35bf4ba12f76e2056787f39d077605a5ac6cecd23a513b662031e203d3a25010001	\\xf1695dacea38fe22a131df3628af7e9639f6a1074af00c0c6af48062bcc29aa8aeb3feb93a3efc4014d59f1868665728b1e485f4b7a1ccc9d3af97ebb1579504	1654818702000000	1655423502000000	1718495502000000	1813103502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x50c97707ea1a4bffa2424e214b3ad669d66206454586dfc19fbdcdce06725da3c3a119c4f8daf874df52dce1777fa125e6bd8f8a12f3c81b1c14331613d33497	1	0	\\x000000010000000000800003d9b49bac619cf30db3d765302f0be6160802a885e261fc1ac2d903f66f7b7580aeb734c314d411ff0c64aa635ef4ca5d602719dd31b4b7fab218a4c7227b1bfbe55064b8f9e6e80e7ea4cec16b71fbe9027520f9f88830a0939f8bcda09e543fd8a695182e1542dbc76a7fe4088e4b8919352be2ff10165424662b02e5e01a31010001	\\x30ee46c89bd2049382d56ab6deb902b657667fe770092b7b25a755aae8e1ba60d19247842e3ea43e878cd1dc255324a1ab16b209f3c12026dec62d97bdfdf909	1649982702000000	1650587502000000	1713659502000000	1808267502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x5035c7dc5a20a6d7b690a0d328042f342bf52276ee2ba76a8bd5359464648379ae345d3c8dddd4f82ff12ae6e06084cff65f873e9e7d058a9d121796d6baff50	1	0	\\x000000010000000000800003d3bd592e15eccb4e463b83dae852853a7fcbeb8432391d60c2f9708ee3e296e27c7b9c9c152659e3080037cc750a493bcd314fe2c31f47850daeba006c05e0888abf2b2f701f58a3a58195c49e2c46e31e7ae6a3d5888e5fc07a3bc5c299bca9b6d0f614fc8a3f6ef3c091d4dcf4f61a5fdeae7891abfe045cbe0199440d6ae5010001	\\x4dcf335dd9b10f201fd5b333162520e38c360db4149682a68048310772c552adce34cb9dca5f6d81f05aaa73f302891d119f7b343b427a7f59ace4b293f0cd00	1661468202000000	1662073002000000	1725145002000000	1819753002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
134	\\x54b1210aa158b452d4333e68ebb515bf10199155fdb4247205ce845867cb56a5db69208a86c17d5a8b1465085fe0c9cc290f635f3a1360e1678f4cd7380fae99	1	0	\\x000000010000000000800003da359f004da3a89c138cdbce67170fc76256b3268fa1de9b868a0bfa8e0878b279d3e1b4e7dc8f1f08387f42d7ecf09b920f7459401185b606bc9b8c0c7b68d259904b4eecf2c80a452a8c516ca22799c8d6cc44760007b69f5a74c74ddcc7e468f6e7d86c77d9cbd43dcd55673ce23e19ee646dcee0d46b7bc7cfee7c47940f010001	\\x3f031e11ada99191c02db0d7900e505382d63b18a9e02c7d51a9246f1b918549ec722ef4bf1ab554587bdf1a9020f15c5f9c480779abf1c6fd54fc57d5c9ce07	1661468202000000	1662073002000000	1725145002000000	1819753002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
135	\\x57156d5343f1e47650d7e1d53e71a66366261ded99a72e9393a66dc677799820431b8d56522b82c9b78109dd2fe899e0898f5630b39559f385278ab91a9a7116	1	0	\\x000000010000000000800003e3b0304355d2c92087008d9e7a9176d056063a37586be0b5f81cf5e60854cf14b8d82bb1d643a8a7b3d0af17f06c1bb54217ccc7406fa83af6cbf69999309c22e18cafcd311dfa2453ce21dfa31ccfccafc7d8ff9346604b50bf722c1b020f17d8a3ad06b039f3db0bea67906df89d50688117390c65baa15f53b672e292b2b5010001	\\xdf089f276a770ba7732f9d2468b976a1eea263e4eabd85c874355b3b578650587a830acb8c503f230ac4be2286667d167933d8ed7eb35cf317a8030cb780b306	1650587202000000	1651192002000000	1714264002000000	1808872002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
136	\\x595d8052b345278580a7f04bc491ef46ba1d71b597a904dbd7b538720571d93ee90e092fed1dc72eb6d3ef96908b16b27bed81af7764a674e1a7bed9df9c5249	1	0	\\x0000000100000000008000039de9e6dc24a69a0d6ba27c66f24f75f895b89e7e5677fe4512a288c01b64bce4ce9643a54ace5ac85569dc03f1a2fe5bbf9ec125577f86847652629cf9b7e3af0ed51da9c754148d7631df998d62cdf61e67b7fbd087434c6d76b5ac8932e1ef57d32de8868be44ca86f6d53b6d92933714933135935d12c2022aee13c4e5783010001	\\x50201b975b1aa567bd244856b0069f96e145cdcd194a69c7f22e50a968767b030670e99d01dcacddb54859bf6bfb9aa198dd034d2e3ad95a04ff4d555920da07	1671140202000000	1671745002000000	1734817002000000	1829425002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
137	\\x5b8d9219d51fc752f978ac3a845545ab29134ca41acf868f3fa8ad40c079dfc4b3191a9caa8d60d77d2762cf563aae7dea01967feff305bfe4108b4414ea6d65	1	0	\\x000000010000000000800003dc2283065f93bbff086b1973af1619bb61976de2510d7a75fb2a0f6d265df397f2dddbd5a48e3e419c874b358fb1a1075434a8f24f0f8b7823ca0b4133c53bfd9632c0b8a0d54ffad6374edec7c5ab522e47e0e51b9f37bd9081c971d41ea6dcbed38ad6430bb00a8e3ae9016db42c3ecda2166c2c38526e72356186c10545c7010001	\\xa89d76559c55184294c5995abb2ab101722ecd4f61de338fcfa5973a7e8f327c00bfbc77e96f9352d7584a60407793249a633b87a0ebbf2b3c74665f32cf6a01	1671744702000000	1672349502000000	1735421502000000	1830029502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x62e168902c68fbe31c199c46f940dea91b0ec0df1865c0a7bb945828b5ea8c047773116d348b087393957e5bbf308ac9642588921673de24e3278748e40b96d6	1	0	\\x000000010000000000800003b8c25e5ba20ce8f410c85b53d900fd56c8a88df28435df9ffc7140aefd17d37c3e27f1d7ebd8f862c299bb682a6f5758c059b6bdf79c264ab9df1cb50aa010157b94bdd9625dee6ec7df0a6dbd500e6c7e3488feaf0d2cb54868e4cb92555961193e2bd694da5ffb326c7572e21b216ed6379156916a2cc645c448d22ff58001010001	\\x7361208ba6d47eca1f4862133bc62f915446283f794af3b92710c941f43ce74bf9d55d3c85f4c8ffd0889ee0a6457f1033bdf1c0a7c9f50ee0c125441aa21705	1666304202000000	1666909002000000	1729981002000000	1824589002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
139	\\x63e908e4427911872bf6d3022bf4702ca39e7faaab2353364a8e4300680b3003fecaa56988b2dd6c425d43cdcc0927a9baea397dfe94b0646893f95975ffb156	1	0	\\x000000010000000000800003bdf299d850a1847515b95bd008f84bb4114e27d6f8378b0ab9b8c1486ff88236f6f9b14af04218c6835200fc3875dec0893b41cc113957594197c26a5a609ed5811bb96d497b326f3ec508b27bdbc6941647bdefd308e658f65ef4c37695abb23b69a1da9267e8274a220ef38e8aa6ee0f78303c8a7bad7e93894c7f5144ee9d010001	\\x435a0ecc4ee06311490ff6cdc13eabfffb9c1c1a018fd02dad9503cee8693760889326b3a071781e27647c3bbf0be312adf7635f0187557152482286f1da5607	1661468202000000	1662073002000000	1725145002000000	1819753002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
140	\\x639d21311651fc30af2023e5966ccd28a674c4ff1e917955b5b73b1027ad7086a0ef20ae8fdff4bca250ae0a8bef33822194a7395372dca5bb4be5df52b1bb72	1	0	\\x0000000100000000008000039be298417db2d0f256c312f333744df0d669b11df8aefdeae99df565969da5473b114a8d089f9a18a48cf0d80122a2f7bd5f20ada17da7a71d3311bf957758ee86c1aa6af4ba2b6728be8d026f97b0ffe85474637205cf8bf63dadcd22b095dc32adfd6f9f7d9e16f6fc6fa001074dc98a0ca919eda4dafd738616dc7e862a73010001	\\xaeb7a266292b45dae12f80ed38e6c0191e7ca065be01c0eec1cc9bd3e0c355d653769708f74547fde31b0f3bcebf914364e79c90d8160f348b8a8fbf7da0a206	1649378202000000	1649983002000000	1713055002000000	1807663002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
141	\\x6401d7f40aa35dc5ec905cbb1ef669e8d164e56b9f83aeb0ed3640a9c8198189a51ddddc7a6026e1cd113f5aa7359b43c0262ec02b2de234f7eddfadb240b41f	1	0	\\x000000010000000000800003a2048bdaae89f3215d5e12832eefe3698bf1ed845dd3bf516880d86f48afbbff41d66b0a05d0190cbfe95e0d4246231a64556ae4add755d0ec732142b3dee8db57088697f770ce897c5b1bcbde17edf8039479a83379c3794d5fd01351b35e6afa79d02144ac331838932570de9dff98a97f253bab92468ad92a30295418653b010001	\\xe7c18fa33d477a91c840a7ad8b8cbfa5d46ec6469bdaca6bf94161dbc64ccee47d4b1b26ce26f767445e7965716d838b2ac2b1cf9c4c5b05b01f9f53c3b4e209	1662072702000000	1662677502000000	1725749502000000	1820357502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x6661d64cbcd3237bdc0c8f55a1331db4cdf1e7139a44f529170c57c8975736da1bc911e76ad59ace4d02882ba364200f29abe0c96803613a941a654ce743eb6e	1	0	\\x000000010000000000800003bc0d7a9b49f6b2af25fe6647148787a96ef9dffd9bec847a6d942c672c373bd5b3cba2805439869edb62973a1933893988c357b3f836b0e559191f28b1cb406febf82b2be7022778f2cf6ae7a4c140a14af393005e945db7dbe6d68ce68083b5bc749f1af8eea4e380bf46d048521973feb8af6290edd93bc7b0e82efa380c49010001	\\x45e3e6c07743ab109a66faf520908b11ea16021f3a30c9fde88f8c8115d3105b764b650c84c1bbf6f339a9facfcc4a4ffcb1bd66cc044b25680865ab6ab2500b	1672953702000000	1673558502000000	1736630502000000	1831238502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x6b2dc256350f205b735d2d5de0e51aaf605c7d46fd4b257db7545eb4980f80124b2c3d476325071ccc531902dff6e10beb0468f5c72a2704e4f79343ab9f0be6	1	0	\\x000000010000000000800003b403af5a4e7d9b1fa1ca8fbe4f1f3175e958f5afa1bff254c7568b677537fe642082533db9f4e4058615159d0c6449c844d45c0c3adb1ce69e2d66a34c68aa0ecab6d80b200977be18ee986bd158f77f7830c8bc5bc513e658c4ec36575520b565408ce74b264c5267264b1bcbdd4f672f4061048278088f5d7abf4f908fd0ed010001	\\x1a1580147ab5d79ec1068b7e01899abb5c1f0030639833d7b9e946540ec69c182d5bfdcbb68aa18249fef3fcbbfef1353e592de58c8e6ec86d5c3dc1c4716408	1656632202000000	1657237002000000	1720309002000000	1814917002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x6bd5b3b79857192b7cfc9e29ff80ffa6f201590673495c92909ed7557718bc8dea1f9603532d466ad95af8fcf3402cd5d53d67d521816abc93043368b55767cc	1	0	\\x000000010000000000800003af528d23bfb86127d9fb7b9d319a63bfde88dc287b9defaa86da6c944e3bb11ff78f7ccd9cfb0507eff4bf2765ada1eb9f83f01dd786273bac6fd41b8d273eb792177a95485dc934bb0973b8dd6a1ce436d6ad57561260e7dc2ec00106fd5c42cb089296121cf2d3aa34a1b11c2f2a1b9d37977c156727df281cbba65eedca43010001	\\x03cae90bb90b7ccc462f195ef7f0588c945f4b6e367fc99243d027dee170f1fc2859569edc43255218d5c2181193f82948254dab8ce1486282285b4de12da90d	1656027702000000	1656632502000000	1719704502000000	1814312502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
145	\\x6c291a0ecc20739e0d204a4b95dc03b37be323a500b9b2f69947fb01b80e2a6f5d1a315d58c2e2f95d3500ee3e959291df22e3d1b205ec2bf9d24b60e32ae5e0	1	0	\\x000000010000000000800003af970e07bf29b5526427bb9e679d84f45eb9675ffcfa0e44f2a8d7b4df8cbdbe26bd9999c98e60c58eee32b920bf7f3a099b02b3c3ef9f3673c17a1657c8394cb79fde52df5acd64469684c221690849b7a65cf30a8973632038cfe3909e86bfdb41160f5ae4825f8d265d48c616e9cd0ee6838a58e5b4b448854faae00352cb010001	\\x650ebd166a43babd6296f4ae47bf20b327abc9531bd8e829cb91c953548ce9f2f25f1f1c251419cd0a3921b49bec668acb3184c08ff9880d0a54682349d95a0d	1669931202000000	1670536002000000	1733608002000000	1828216002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
146	\\x6d4163181165a23620690f2fd87dd828863a27cf3f8f3d1b6481c07f6bdccaa399046c867fb0dae97a8cb826773d81e9f2a33dcf785c9c3d1925e18681e97c3a	1	0	\\x000000010000000000800003cc3021ee48ddf6a91d21fb27275dbedf43fdcd0f4efa8feb9180ffc9f19a3f3901a7db490992cb3380aa52b3fed274360b610a866cf02aa0fea6d333018bc9cf33e7554f0e50262749db00dd9d3d0bf155c915760099acb90ccc4b255a7ff7c3661acf19e113d59db887eddd96c83dd9b4ed1717c1a68dc37f03ed6521061045010001	\\x31778523194818f588894baad393d7c1d64e7e9cc2da9a7e59610092dc7791d6c71fa10a465dc4033d0e9e699f2c3545e7925e188f3395f8bb3ef3a12addd405	1668117702000000	1668722502000000	1731794502000000	1826402502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
147	\\x6e1d7415797bfa94f73075316d69301c544b33bd8b58f7d8a8cc4ebce8e8cffd38b6fe83aaf14fca7b11f8f03a04516d43aa87a6588a4fb1dc9e093167632bda	1	0	\\x000000010000000000800003daea7327d9f57e2556376ef7b6ff54eb8711fa8037489662d6902ee3760aa5a4a9f6043e4a1dc549d26f23c75ff99095013feb43886515b8ce45c4afa2f4a5cbde1f24ce6b0969ad561ab2bff636a83b817dc10e6a2033068df73e6ca2ef70eecd551d23ee07dd2e3d9acff6545bb1e7720ff739b8ee3da60f4bda5083976ff9010001	\\x479ede17d29858b6bd2c5fcd7e9a0b129d5ceacf993b4e495756e6e77b39ca2d2a3a03f854ef003291ec98f7f9098db510f345a2cebc72ee447ec7c726b9f800	1651191702000000	1651796502000000	1714868502000000	1809476502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
148	\\x700585d4009539f8a7c370129f73fa1b2801c82dc73ccbe6ada5be7af33cc62b1a071b7a6cfa566d5a1e170563d344f560b3e687e5443a7c31b7d2a6dac00ce6	1	0	\\x000000010000000000800003a76e5dab17516ea12c359f076297efe3484d35c97fbe8060ac5b810e1f6741a709f50e47a6e200f6fa49096d364f515dbefbcaa0f874bf3b32f329743423b250e02b4eab5241c5b25d7e18a69c397f167796f235fdc0371401155e72900c28dc6f90164589a4bba2b7a31d69b62e986287ad531f683ca2322e07b8f868e7c029010001	\\x50eaa1b40670569f52a068b58948185de8ba163c6757d2ca4dea41c95b678e96b1af5d650e16b222ee6c20ebb4a7698f34960ce8d1f3a29faeed481fc99eaf08	1649378202000000	1649983002000000	1713055002000000	1807663002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x71fd543479f4e750abe8b3dab7eb797f5544447403558e47bc53dc853d658d2da81ff0e3c3c02fb8fbcdac80e481c617a009884cd5b768d8ce89e1d2343bff01	1	0	\\x000000010000000000800003c9bac835b6d85ad4a7042798d3b3118f22d9668857044775a56988fd2d624ac37854d555997cefb86986a0e17d2b460b11fcf58f89cab5ff0c5bbc092f534b6756e08de57f11a0fbeb26cecb3f1eaa956d86e74d0e786a07e780edafd0e452db68ea6471eba715ff0270e1228c50c28e8768ffd1bb3b780c57898ea14ccb447b010001	\\xa7b7dc77b65f20fc1c5bef76a00e6e8f0ef0eac14afa94dcdb65177c7ec3915df02d8f4537bf85cffd8f77dc4762175e717b18cb839dda1b1657470a8edcda09	1672953702000000	1673558502000000	1736630502000000	1831238502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x71e5c46c6973e48f95160e9c455ec01d662a773c979ac6320bc15a6757432bb48fa94be6a14c80009f642ab5a52ef0334aec490e24d67081ed94c53c9a500c96	1	0	\\x000000010000000000800003dc9114a426f9a94c5714d853827841beee27635f3830c242f2dec6cae56bc9888b543cf675be9be7db19bc391ff8515edbdbebbcf549b5ad24bc049e4240ffb909ab0554522071cf55c12f976390a939c229c4572eaae2ece049e9ed37222315f59e35b373e13bd35b6cb489b250d16afbd9010a0bc5698d3dfa02c087142a85010001	\\x5bf3d4a158c861892d46da82900a2993693480e6f67096404d86fc66cb4b3df5e07675e96aea108b7e8d40e62ed77aa79343e4ac5cbbcca3180b0a1298301907	1660259202000000	1660864002000000	1723936002000000	1818544002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
151	\\x74594a2a40c4fc65169a7b06df4d51fea316d74fb9cfd87b348c6d77a3752a3517f7248f334d30cb17822d24de44cf6e0141850241f1545024ed26408b3311e0	1	0	\\x000000010000000000800003b2bbb8a340d6f5776b54c08bf3163cca9ae09113867058339f5b78e835fe03a291a78ce700a0a335bd001005ab7695a4d954cbfe6cefaafc7824f4e3b0cd9800f08a1801fd5f8370082b91365e9e075438d4e2639b736173fb8cd79d1de392f8d18ff2f12820b335e81b4eca0ebfeed85fb71d23066e4e93eef9da82a423ac55010001	\\x1b963e031abf82c43494303a80d9a7892d8b723fe9144e6d93dc6a2e12361c2803e2f58891e9b77dd16b8545ad26f48bedf463b77555fa13eac2282f60157400	1659654702000000	1660259502000000	1723331502000000	1817939502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
152	\\x81597f951a47adb280d70f5cf1dc5882f79b9851fdbcf7861b07589eee256ad4606d31cbc18bc94676b8c9e4d118cd355fc23e8d732668bd68b4a28531056b4c	1	0	\\x000000010000000000800003c9abf390d0c56be337c4bec36f36470481ab107a82966c7206ab69ad322f86238216c39543f2e46ad16fc16bb0dc7a47a1db44194a64df39a851bbae31144a02e30f6d348a51045911ce08a7883f290c17b924e3f176ef28070bb2a7c4ece6a0a583b7c5e268910ef1ca54020389f804d420146b3868c269bf15b69f20affe11010001	\\xf5fd41adcb6ec9301253a49f1742cd09c0cdd365c385d2ef2ca58f82b2bb400ebc5fc65b2e815c2f2375c2ab0d9b10e5f63003502fc49a158f3afbd0d9595a06	1663886202000000	1664491002000000	1727563002000000	1822171002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
153	\\x83157d9c61a91e58a2f88362c17644caed3c7a801d046fa0267a1ff88afa945d9d8ba5966f13e776ae7868732d981a063932ea221d62f06c96eeb660938b40fd	1	0	\\x000000010000000000800003d288b95a640b53780c8f768101929f1956b6e585b6dec06a48e16faee3f96010faf2cee063a18d3c862673c283923be797160b4d77b8772bdf2b1051c8a0d9da1154fe789eda974ab78ae4f5d9ff6913c479281f66c2081fc275a6e03f6e9915d9570d8f6f5dec578e49f800e8667d365897d855df057fce48a87082acb90815010001	\\xb59b74d150970f4317607d2e7ed9d07adfa669cd0b7fbb05a8eaa3297e9ba0160801a978d0a0bee0c20ef701b78650c1aaf7a6db12197340b8dff113bc0f3309	1673558202000000	1674163002000000	1737235002000000	1831843002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
154	\\x8341494dac4fa7e81248130ed9c2a123e8acbe1e6fc7ec33523526e81c5a6805bf7ecd4980f7767cdc22caecfa12521b0bc265bea25816f73a27525e624365e8	1	0	\\x0000000100000000008000039e59ce442c0c25fd6f704db0557cd5bd1bc7638a299acdd2c1b2f3a32a8718a2e21c5fc9b3d4d812767f022c9d74d948fa9861679fe3c3981789dd075a12b7c27810b56c2876fe97d067e2bd15272b68b9c39c65d71d11799c232fd872aeab996f0f22c39f18a5c7d681c4779b6e985f14913a8436e1f022cfa4833f1b922799010001	\\x02a86381b5a3508386172e440815b3413caacce0c96b59ce33b1972b03711f9244c82871e1b18e010b51e9b6c380b406ae20554311fbbe98aff6bd2c66c20106	1647564702000000	1648169502000000	1711241502000000	1805849502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
155	\\x83d925bf2f373a1dd228cdab9f4829d20e305b2b6b67eaa225b2d6b8f13cd703dc641a0d919da061556c1ec7028b95abf0c7d9bb65eab1b24dabf495e6b69c88	1	0	\\x000000010000000000800003c84b801c74ed91fc27c05e43ff3b0a6424b774de3f9f4001b95ba6f304a0c2f20bef2848c59ed427b2929f39713dd8ba49798c7df9dddf834d0f90a80abfcc812e19ed931e2b14b1c90e77559e3b75f1f077d00cd8666de10511e0f5a94b4763de1a66d7fe38aeed1f7b0ba2dffd5ef216449ea48a61fdae8ddb04d1f27a1189010001	\\xf5722c0496681b927c749bab6769df9d4b436192ee3d07616c05b8e91118411698908fcb2399134fe2c56248b774efedcf2166945a6ba446d1a504f96adad10f	1659654702000000	1660259502000000	1723331502000000	1817939502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
156	\\x8ad1ba10c9503dcb5d5ccf3ee9bec15be6330b77efebf69167c5b96950867cce7da60751f0ff664a2db49231af36c6c32dd326bc64812be2d01399ffbef89dd1	1	0	\\x000000010000000000800003c08d35e57814e5ad583612c57750029dc2278b3f1fc56bd9691d32017dd321228cd70183f99255c459175806619bda2db114d79d6b7513b70388075ebc2a0e7a8e8bfabb68917f4953619e380c48f07dccd413bb79f1c5577804c7dd39696aa5fbe69fc0088f1b4103696d80a11a045a0e6adfea937ebd3b9fa565f2cb511f3f010001	\\xc530d9a585a6cdc1a2c1b9cf25d221767e9c77f1b412b5dbd0e810fca3d1983d3a29fc7de3e68f75fea0e2899dcd55d2cc6246baa5f8d4a9621d4f69db28e602	1656027702000000	1656632502000000	1719704502000000	1814312502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x8c5931228b7b686c5b028a58bb3c02281e63e9638fac5be86ef27b474c5d349040cf70a2611448e97245abbbded4a27132e705bdfc35fade826e07e967fe35a5	1	0	\\x000000010000000000800003c9950a1920fb3b2d3c7a0b55152e58cbc62cfab8ccc7066e31602bd7ec20f31ce128117283b333965dce913284eb599b3d56b77d95989b5008d1be17ff565b9aadddf0d162bb0bdfd382979744a02c36f2e6da81cbe4796b1ed47d48c1eee80660086c593f187d4b77482233c770d540ba7878ff8256db0ed740ebab1a23ee47010001	\\xff38cc98bb24ea4ea85e984659f02f5de07ac43085400702f57a117c363b117bef6dc4a9814655b217c682052a2cfdf62558270bdbc724dc1b1395b33e193c0d	1658445702000000	1659050502000000	1722122502000000	1816730502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x91e56e1027fc17248ac83c924837ed94ef326099383c26532e5a3fa3e096f687317560209aa68e745e35514e84b74a8e61d009c222976987fc708bd0a7ea0ddb	1	0	\\x000000010000000000800003c1f663142eff84433e7f95afbeb2fc9f430b8616da815f2f606be24f6d57821a540270aed2d0153e9bf9ab042cf350dfd0666a777b08b92b42acf4412ba98b41385d11fd0aff69c403f2538e3a46493aa379e2c155447857573200aed156702b5b465d431fb26018942eeee13fcd0657f6b319bdcbcc9710bcb133fb5c52133d010001	\\x181af92c40c1e67c64dbb24d658d4b4ea44345e4aa48873f160c9f0cbaf780f3a712dacd0ec52365f18491fc1a48391c59bb5936ddeec9a941f837e1ea25070c	1649378202000000	1649983002000000	1713055002000000	1807663002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
159	\\x92e5c5fdcc28df1ed069712d96b2501995a5666e71ed873e884f0821d260ae1c74542ba542f72bd11397cb3fcc18ef3a2eaea7fa7bf2b284d8fcef28d08753a9	1	0	\\x000000010000000000800003b85025e0666e9de73de0cbf864aaaada04221cad4a6340ab5b461d85a9688cad7c070d31f21a177cbe90aa085e6382aa19c439a56b8040a7a4ea3539e2d99a4c49136b2dc9490abeb774bbc406c39bfc24666deae50adb7a1ebb32377861aea3b601f36ebc7c0a2fff276c9ffd7e4bddd2f7ff0a2ddc8f10331545b1df3b5fe5010001	\\x546b82cb5dc58db853992a8c0f290b17758e5d663e7d3069fced72b44a76abf4ed52797d882dac5bf78a64a5418db0aa518833d0bf523623f9475ff128ee960e	1674162702000000	1674767502000000	1737839502000000	1832447502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x952539e3661f87c72f5c89b950ec487590c5e13955ef40f6f9d3e7284d8191c229ecfcfab2c3d1d2f80c843f6dd7ae3706306200b4c92cc59c488b10bc1e6d86	1	0	\\x0000000100000000008000039e13f2d28d2c30f5e633d73bf3aafe0f9221565bb355fea215f9e1b6c7668aa2f5e79ebe0a7197f4d920296609c40c5a85ee59883734619e495e4d09306699751558266d1bddd23f0cb869b923e458937b563bfa6906f3ad0c6f6687baa7213be6185b3d51f936e3d905784d56d17fb4d6aef074b10e85c1c07e77a9238b8215010001	\\x40410d84561aa3502073f81d9121adfcb4109478b4e39ddadeff62ae6ffb4420d4c8e379fd957f89fd14ce83c7fb57e6ccf2b2013d42693a214bde3e8ea1a205	1649982702000000	1650587502000000	1713659502000000	1808267502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
161	\\x96f56a76bcc9abae1db915a1479b7d5ce8a61d2f217649fa35a6f5159bfc8ad5ad27c464754a133c683547338a69c0bb344b8b9e181a64fb39cb0f2c41ed7b45	1	0	\\x000000010000000000800003e0b12722a2007a67c900a93be5d804bfbb9ff40da40950e3af3419be5886f14a95665064aae636c3400f2dfdf98616de48d64feaf42310ec30da355cfddf1c5d00776d8aba82a73acb02ee64f4450942960a219d9017e292c4573be04313a219c2a3bdbeb446fac2c52f4ba35a9857ee4cc054d5885444577be77b77d17a43b9010001	\\x1c19525b736f0088e5e929c7f8c6c0ebfd88b8a40cb59c09eee661b920938845392a88690193f7d2e25b59428dbdc83fd5321cbf534812c2e82eb88c9ab94e01	1669931202000000	1670536002000000	1733608002000000	1828216002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
162	\\x966dc0eb5e00b90ff981645e9421c1de1de0f37643d90041741f7b99e831fd7756e323b51fde0f88e3112284069568e119b40089df9f806fcc102fb205611cb0	1	0	\\x000000010000000000800003ba870603831c08fce4b150b30d638d5ba4c6c414b403c9cf5b0a478d5b486dc7dccab3420226577f17794c81268b956256eafff7520b5c0e2a47a3c4086c9e01a2f99cf4ce8521d238b9d1cc6bbe4fa213dea07bdeae18d30a42e3cbac02f6b7d7329cd8ece3aba6cbf7c95873db36ebe7d2bda11e15b450dcee2eaad1527837010001	\\xa939cfc73aaf43eb2f15251afadf2f66abde53cf1e37a281dc309832c2fed8f1332740241c68c7d4db0e5fef2db171e9d98e4347f8a706af6c2a78063123d903	1669326702000000	1669931502000000	1733003502000000	1827611502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
163	\\x9aa50d72f9e6fc2aee8111982cc6f8202cbc36cfc9eb782480018e72e27ba9c73508cf1927c1dcf4a515d6b2f6cfa085192bb64f3b048c3b635ccb91dd6c0bc9	1	0	\\x000000010000000000800003c440dc9eb1dcf15127fd8d7a42df3d4d16aecf6f0fef5dc22a48a0cae2930366584fb978c09ab8573fbdba81a546571ec4f7f3953bf454443fcfe01f8d2c62b1ab49efb33ef63316820dd7295be04574e0f53687d3dcb5385b916b47490f466182ad0ec24bcf71c2f27bb41384a0556b79763f6d3119bb0fa5bf37bb4ba01e8f010001	\\xff0e7556bb7996a82f6fec74c071452884c09e0635f8255f242502ab94ca4eacfbd84a5926bb25192cddac372e8eccd6778cc8b2c0e0034d62bad533b9c07608	1649378202000000	1649983002000000	1713055002000000	1807663002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
164	\\x9b698c3ed8aab3df6d670b38520f3c6ddf28af62a447d0380c21c214285a1d9a23238ef02fead96a1dd5c1891f03234154dcea2db4749adc4f39d23de641c026	1	0	\\x000000010000000000800003ab0e7f2ad7f4f34c8cbc64ba50ebdc566b6ec43994d34b25ed03448acee65a0c9880cccf721fcdca51ada53062ad9d9a218e440009e80440bbba6014db86ad9a98826b8f43feb54904db95bceb5d71ec0f1fbded8456b57186b8989ce7d5d59c1efc390e6b43c3b23da32f2d74858b0b72086023c910999dd44ff9bb584a5dc1010001	\\x9dc537cbed1eec53dbf897635414aaf93b04f68330fcae3c39539b27c44343b4c5da2281bc85e51f6779b7718b0984ff984f6b71be7ab5bde9b02c456f7e7409	1677789702000000	1678394502000000	1741466502000000	1836074502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x9fb1c44f3a69a684b68da74e84e24ed81e7779bbca18b16e49304a8fd4e47b9ce62170fb28cdfa56379edcb917bc0c6b7786e7dd4073e839c7dbca81b5dc1ebd	1	0	\\x000000010000000000800003bad72518d19b9a9a49cfadac626109aafa22a078790162b06e58bcd0b1b9b10b3032c66fea5860d5865c89c7ddf5054e109ece6eb1932bf439611675822565d7d7a2298b98dea35ffc969d02b3ba37793b7ad02c6b8741ff79559961e75af7b693726a92893ed276a2d3c9a77b84a136757a2f99d2c9f7f5080d9115d4f968c5010001	\\x677e0941f1fd5486bb6093cedf99fb9bbeabb39644b7aecc7eddc1588d8fe6d9e4674f3fa1ebd1b104acdddd06de1a4f759af5521bcd91b59b42d94676c8d107	1651191702000000	1651796502000000	1714868502000000	1809476502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
166	\\xa1b193fb18a8f8d6f4466e20a937b2595fe709a8b668a38e7f38a1203fb4254aa9908315d50db2e6e788c1b67d78a659e3d8eea7500dfac07bb251cbddd687aa	1	0	\\x000000010000000000800003b8793f1428f19fed55050ad20bd0397d2dda0a2af16ccbd01b6d22dcef44289d66c6fea8ca2cdab7166da5363a37db2cedd8a366c4f696d43cd43f1a98dab5f0463a58b525600a33f6729fea145795ef780abbe190f0510ff828df1129f2025e2e39e16ff24c161ff35f7be78db86d671248324350957cfd2da3930cec304e21010001	\\x3e8f369362d7d12321cb398360da7412eb32fe846a9a79610fa86acff87aead1c03a353c8c8a81150f6de5062db65bc114c44a5e5de9a8da3303c07077ad4506	1676580702000000	1677185502000000	1740257502000000	1834865502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\xa2e9c7f62f31b65271f97b83a7ba94a42e67a8739b580a6036f712de3cdfa1f90ceba8612cd18b824c8f2ce09aa29d3a9ae9291cf84bfb3bf05a579e11844ec4	1	0	\\x000000010000000000800003ca5d0810a3a16bed17e368c264d53dd9847eb308b04adb2895a7794774978459950428abf0518cf54af598911273e4a14efb4679f985203903ab0a80ec07d2483dd9bf9216bcf836ae390468e563e45629e7224ba20deefa821bea4ba571b14347eca779919b84075db089f979e22fe80b23fc7b6d51f6cc083c0dd91dc00ed9010001	\\xa8c95bf04ebd5af1a313aefcd16ccc3f40249ecc3effe19b0101c9cd1b286b353400c7e79fc2a96c63eb39ad82d873f1b17bb9d603de21f770e24fde03855a0b	1657841202000000	1658446002000000	1721518002000000	1816126002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
168	\\xa31954f26e93bbe94df6209024d57a077f103860c7845409963c5dce89398e62904426d347935cbb6581bb0ac69b103b32ebb867c2cdae9b001834986e1a2ce3	1	0	\\x000000010000000000800003c8f601eb9c9eccad2893f54b71902cf75eaf686d02f45605959a56dd7e2e8e00278a98d4b185adf1de617f003b83b9fc11458b1cc3ac630ba3a68d20faee29dc09113517209360c82133e24be4176977c9115f15441200cd1fab1d288882ea09fa70c192118d2cd99822ed45a9368987b17b0d2fcb0d48f1214dd51d719e8387010001	\\x69f62560a8080917d798535f79d76617792815f1d2560eedce0f36a42faa1e33a450357bc9caf007ada91a698cfe2aa9d410e278018aae7cb704d510f88f5509	1648773702000000	1649378502000000	1712450502000000	1807058502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
169	\\xa5f162482fbcad1a37a06618e6777ffd334e9d7bb054feb20b2e884689cd58f3591f96201a2272b4aac8038cabc9654755fa4945c03b04731dbf1f87cd7f0a13	1	0	\\x000000010000000000800003b20889309e167efeb06b04e614c848a142b24d068d3e35852cee83f822691607f5a6d987534aa0ff482699de8cddd1de1b87fe02efc1be5b5bfe82c7855661e96f6bbeee0248280fd824712e5266f22e4b6e8035dc44ed6f4217aa56a358f61704779221d43414f606ec12ad77e672bef071cd5f4a236105e2574fd1437e11ef010001	\\xf7f68b2747640ee9eafcc00be2341b68727343f82377811d210875468fcd4858710e013e31026b921734a3f75e1523c4ea85379122b2c339f825702cebbdfb0b	1660259202000000	1660864002000000	1723936002000000	1818544002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
170	\\xa521c2483dfadef1aa5f29e113dd086df1cbf479a9d150db3dd6ac222a3f7e1422e54883ca38f88772904b3919474eea29e5f1b1a27f36b59a4bf8f84e4bb978	1	0	\\x000000010000000000800003bdb75ed871223ae3b2b884329dc4f0bf9220152a16f28d80286f7edd80ed9b821691a498e486c428441a5d03c6b5b095737c0120d4155069e43a8ddd6a2bc9a862b4a5a6206c7019f858da3adb94bede75e43cb78ca5f7e8287f83811559289a333ed1ac5ea0c3eeb8a4a4b022b0ef80b598d86b6e3707800ae74fd8a52046d9010001	\\x7b9f40d7a4e5f7a463bb216d40050f1991055e61d06210de9558cfae5b13583b500621c850e3f3a9aa96924d54c4ec7f02576ca0d45b929e7d224591df9da40f	1664490702000000	1665095502000000	1728167502000000	1822775502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
171	\\xa805616857748cc28a6a368a366470f591cebfde301bf491fd14efb93e618ad028096d4dd439ab876d39b17320c74933de99dfd314bec1af05b419d06f58a29e	1	0	\\x000000010000000000800003c099171b5059e8c0e18c9fc400fae8d404a731ea64772459830e4132476862fb4bae65dc8d3a0c13cee2b70ca7fecacf41b4c64ea2b3bfc0e5199140377f47e9a86b32d59d5b8cadf09195eb139f58ab27839e80f4cde80f0bfb5a5b5a9bd1dfaf32fd174447f06d4b6d0abe427d1a7dae10b525ab698a7155fb44aa59569c39010001	\\x1916a377e15f2199a9fd8e41f2d3586d43a2eae0ba2e3f5fbd8412dea0ba95d7053e0dd4d5b283f4b138f75008e09f3abbaf3e2a76f98916a5ae20366ab7ba07	1663281702000000	1663886502000000	1726958502000000	1821566502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\xad39c6b54fd3fe213d1a099ca73d37766974e59dee788f266d650c84ee65fadb776a060d75f58d7b517006a330445e490bcf2fcfcae82211d39306bb2f3f6d8a	1	0	\\x000000010000000000800003a73a18fe20c4f6bad6bf1542e28f0831956f0f50c17ee78a811da57f638052ff7b0ad05b4a69a6b4736070cf208d877422327c1748a3c25a3756eb774019eeab77d0e65e2140246eaa089c445f77082c1ba09aed8ebf4f41948e4db282699b4f832b27917a5deedd5d1b34bc23bd97a8336d55f90627fedd5bb1bebe2453128b010001	\\x7a3ad24a6136eebcaa7ddbd3e12140b18efa1bddc45ff57fc44b370d4b40a1267e0aa4e62bb20eab44f86e6a0d1af79358149456f1564048ab32bdc22b637409	1651796202000000	1652401002000000	1715473002000000	1810081002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
173	\\xad61dc7e656a8b0fb0126c84f1e986e7387bcb3cb9ac07e2c768e8fd9e0ca84561db26a95f0e8548d6d88b565227a7dbb814ec5f221190892ceab1e11227dcdd	1	0	\\x000000010000000000800003e4d2bd27d4a15d521de614f20c905c57cfcf4ff9898edf74e220faaeb4598b0f87fba2b005b5505e3f9f8211fe92ffabcdde5d4c05acebc52589ddfea1c51e476acf48399d3036d14d0e1e23528531e4c71fe94bff9f436479acc0384de09de2fc301838de85c34aac28a250f94d552673a0e3d877e90d91d4690d5dad6af3a9010001	\\x8577db2bd1352a3bc9a67361cedd2c842eb1672a07e1c716a7c80b1995c6d919f0f995502de2e99f8a62680eb2bf7e1ca9c5ff57cb3fbd362bbab0d240c57b07	1658445702000000	1659050502000000	1722122502000000	1816730502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
174	\\xafa90d08876ccec4e3ce7e7e8d4c8071c563638b6f7d77cc2f57de66093def09b39f5941aac67e5a11cce060b4199b8c779d1a17d17b35b52f2ef8fe0f24a98b	1	0	\\x000000010000000000800003ce2fc40b09b432a198345fd07c194581b29248eab9778e2ee5e3fefe304e6daec38689849ca6ab5a35430cdf76a3534aa0c9a657cd2ed8cf973e02b6515add85ce43479d4420f6d71e40b782f4a86b6f2d4e7eb52797305058c9cc1179c97d2745da40a7aa5400be183b9b6d0cad481ba0fb38af84f8fd7f543e2ce5174b19d5010001	\\xc197b5e150d5fdf00cb4ab31f401d1cf8dc392829ee68bc3c5d0b65e48a72701a8e76df40f2ff4e690d01ca340754dcc263afd145b30f7d8ae3e3874fb40040e	1654214202000000	1654819002000000	1717891002000000	1812499002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
175	\\xb0317acd78a5faa82e2be536af6f674d76a4bafbaca4685ed10272e50d99ae2813dc1011b53f1a1b6cfa5161564a0fce0c017511defa84263dda5e9fb9c4289c	1	0	\\x000000010000000000800003c1b415fdaa54014ea5f19e47f61785aa54753141e3c7e58a2c50ee547aa44a0e3ca822d2e089b3cdea4f43f4cf5194a0918fb44b43c734fafdd9a10ce7589bce6980f5e12ec4620a475bbcef3b55167ad8a53c7bf9dde77f532a8018ffe8c535736729d99fd5b5525f4879a23a5877db4a6cd81a257ee943d850781dbd06bd45010001	\\x64a768d060a6607b55ae77e5241eeda3ab7eed7df75aa6fa48c8c9004e922065fa6da4b2ca24b2cc0c6bf6eebe96821771f0d280d191d670895ede35359ec200	1665095202000000	1665700002000000	1728772002000000	1823380002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
176	\\xb7a95950942b82474b412f90a4c7a3f43f02ff733808799049d9f977d8f90ffbd6b4fd73624a656a77e0935c4e0c168a44eeccbf91c82d169d0fe459da6411c9	1	0	\\x000000010000000000800003b265f82a1e99c8cccdbef4564256c91eb27089050de6059e9b321b86eb8d1c6e77e1d6ae309f8ab9167d0173a3a6589b4a215ead6f823f9a649829d172ee67010674ab8398e5ee6ad55cfd88a8914d3ae4e800e4641c24ca4411234c5ee7a7ed2254e2ebe78355004a1eb8dc09520a770ed6ab09a00421a39473b563e098176d010001	\\x986b95516060a6058a55cfaeb281eeb7bae5b627dc605da5dca1da175c9b57f971e324b38ec7eeb8992dcd69602fd1c17030e720dae8e2ca8cb9e71d9e86230e	1647564702000000	1648169502000000	1711241502000000	1805849502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
177	\\xb9752ddca4946d7cc20b7daa097b0b3f29b6337c0d2b5141dda198bc90ec2dff91ec0d04ee5d647908a86c901417fddd710f7453efa510ba75e7c2fb52bfddea	1	0	\\x000000010000000000800003cae1e175de9156fca4512e2eed69c682927970a71246926c6a9173ad4533d72526f5b2cc8b03854a33fcc84768af216cc61c183c7f7eb6393035a24f31ce8e78c6b34ef45d745345c31bb20c9466930655f623f90f39a931a27a55621c2322233bff0c4cd775d1f533ab397de68b6625520615eb876800503db64dc467b19519010001	\\xa2886d4c8d4a893c6a50884d6fbb95cbb9ee0648848002f772e3aff683050afa8a9e331d958d37fde9978bfbbea1f2fab7e6ebf4e8845c7dc8c2ef58866de001	1656632202000000	1657237002000000	1720309002000000	1814917002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
178	\\xbe21e1989adace041ac438056b6f41e6f4f7212d220da2b49915aa9d585c400e2998f3d1debc2c4121a99144298d9eb2d07ce5cd3ac16f381047a1f9562d0d61	1	0	\\x000000010000000000800003ac2420db9b1ff5a72383b9a459f1892753e72f6edf5ad7f83084fa271f88d5d789c92a97bc658f1eca8c9919a6584dd40b37719f191b43bcb603951bbabc2f43570cd7ecd65bdd70049f93afa0d1e8f07c3574851a3f842500ece12c6a1a148f48b44426b4441570aca78c20cadb598dee20ccc244a298188d8f880d81c708fd010001	\\xbd7b4b6da9cce351f80fd685af709a92092d43840227828e9f02f3e78ff4c16fb4b5bb46e2782257aa3bfcb0ab77f38811563bfbe63dc4f0796cd31b6f68d204	1668722202000000	1669327002000000	1732399002000000	1827007002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
179	\\xbe59910f8c7ee72c0176f57c914ac3267d2d3583cfa0c2beaa358afde2e8249dffc5023bae9f8825931e24a4de7a5019390baec3e25e8716fd6c40e8bdbad2be	1	0	\\x000000010000000000800003b9d900e4eb5289b2d8b4d7879a867dd859dd8fbd4442a226fdd7240fbc146d4c626c71fcd25285974cb5fd278f026f9e6a03a85e24243f83f12ed371e9bb34caa3f473bce3a2545888d57a481c15447821ba91e2f33fafe892b82e640f42a9cae15e59bf805aefc2106204c4a2421dc58963da21793cab651e0e9e105dfc687d010001	\\xb77996068f6c78aac8ea9a24831ec73d366c18f3f1eaa9179efed2b0c2b78a98ca0c486292b7bf379cd7816978ecc3f41b8a096457452ca21bcacbb017ca8203	1648169202000000	1648774002000000	1711846002000000	1806454002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
180	\\xbee510086ccaaef4f90f9259af51ffb9aab8795a93e632abe24caf474621fe837f3e536995763d98809803130a0dd8654801a1b7b772fd870a8bba35571851c7	1	0	\\x000000010000000000800003e4fb39408c7f34d5398dc1df1579c4d42d35051510d6c822ba85d87a3909963317b105a63c3813aba080774afdd7a7323ae98b2cea7fff5463306184e628db3212762a8b2e9e352629fcd81c867ebf5facfce70774579a6b220a3de63c96bf5d12e80d627aa0c8462abd7c1c06d6e7ed6eac5cef604bd60ffcfffb3c964ee69b010001	\\x34487747d01d2d1a83666d987685d55e7be33e8422819e96ef90316270272a9e6bf57979bda24898af685d8eb486a0f8f41bc3454a5ab14fd313ae6f9341c70b	1651796202000000	1652401002000000	1715473002000000	1810081002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
181	\\xc029781ae1d131dcc065e1a26320106b9368e6ce9f116ac9e7ef045f49fae76718284f4f89732d8a4e2fd9c800e4cb5c9a8ab4b2492a79183bc3333586f6dade	1	0	\\x000000010000000000800003e0ae12ca95bece652886cd7b9edf6dc8691a9b7de2a36a91859986068c944fc65ed1af22211786b77f650a3f50c9f457c9c8785b00e54f7b87dc0eeca41b587f72b04ac6f7acc53551194a162307f1d794fab27879f61e122c6829251052549390b084627b916940045ccd4e4207c7bbd9349631b7f4312067d7958f75e8d3eb010001	\\x868e9bddc98a3bb4567dc78ae0a97cd840055bbda17381cd39efc41effe4673f37a4c713895b9c72d77125f394bf9f8a805d3cc277739863a45320c1573ee50e	1678998702000000	1679603502000000	1742675502000000	1837283502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
182	\\xc11df3bc8c4d3f9353789a08d7870508733f404600f11ef472315ddf857ac6f9393f98b048b8da0ee288325fb89a60c12798b861e6ede87f603abaf041f2aac2	1	0	\\x000000010000000000800003d65ba9ec4077ac03fef0b8fdad78d596a377f079aa72cce1924f5b9b77f52944c4ddea6abfd2c24cb15852002e2b99e37dd788fd6ddf5bf60c46e583b7bdf07152c13244d2667529dfbb960ffca973cddbab8beafba17848b1fef81993ec8e53a96fa848ef8a85f52d2084cddd1085b498ca6bf17b3d7f735e81c715d9e159cb010001	\\x4d2077f0699739dadff1c0d46f2351e3fe91e43f8e424e85a98604a175b68e184dd997d2e60f90d66a5cd9f39f3546c8e6f6a969b7bf053d26c519f12fd68a07	1664490702000000	1665095502000000	1728167502000000	1822775502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
183	\\xc7e564e686b61d27774ee866d04e89e1a28cb0c754eb85ad4b5887d8da00df7f2606d2aaf0c45ecd1af29897ca87a9cfafdd5447312a81a814603e153b994e7f	1	0	\\x000000010000000000800003e4cd528bc5670b4d8102a7cff6af283020a144950da29ed100fbf21023c07504857adee5455b16e1b7cc2456042eae0cec80b333f98b22d80e49a0737290ab64dad999b90647082e76100caaf19cae32f62907f4719e4c1ce5a95587319f31eeb48e0c2057518a1f455d4399b7bd4f30c5ad0e1616eed2c967c36d47bdd2a139010001	\\x5974e9e56054e650b79506efd3e58e9d097aacb0f186d127bdad7484872f904bcf90bdce26be118077c7913136546902d5925e9beec9375bf0f10423f8c5fc03	1672953702000000	1673558502000000	1736630502000000	1831238502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
184	\\xc83da8fc4b52770c386a61b807fddee251066a563b9bc591f0756d95531bcc849ad416f8e598534f8c519108b3691ff03193511e3f1ee504206cbd6d0be90759	1	0	\\x000000010000000000800003e3667b1b346bee474a1ee0ecd475888fbd4d7d04ceca20f220de3c03ebc9ab1d4c7c6ca93209570edd2eab534cac670a67abb090a35219b108c3e53782bfd06c6f126459c273f775b17eec1442400d0a674cd748ae43045511a01a91f024134827c2c347d26ee9bf78152378a954d9e11670483a57f1731d478a050bedd5af83010001	\\x39b8b4f87adc05805a65d409e03f22ed66cac2c2f20ea9315f78640a4f18c6bd1161ffb6b381916694921a4056463bfa71f35907ad0189cdca4dc4a031693e09	1671744702000000	1672349502000000	1735421502000000	1830029502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xc97de0b069449b4d9be958b25542715c66edda49ae71ac96e17414277d4fa22db4adb0848a4e9b00141aec01c1c6b8a62f841bcbf50973eef3d9a2057c5cb60f	1	0	\\x000000010000000000800003a0445ea0d4c5feb14b3b42d1f7e1e51ec242a1b359d29dc6740d6cf1c1e2017bea9c1f8166bf2c9860b0f79a8c40234e2779bf4905705f852fc542e6cdec9ee05d841267d912f8d3e4a5800ff7cd657f0364a0708866b22caeaacda259b111787c0e890367ecb7377947b1bef1c9a4dafcb0059b8acb9fe074ce313f69834533010001	\\xd0f15e0cbfb29f026ed99fadeca3986c54f7ec894499c1b0daeb2f33277dd47fa42549902b8e2b63d13a10375f3474466b2372750ec00ded72fd7d9b69e59005	1672349202000000	1672954002000000	1736026002000000	1830634002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
186	\\xc929842433d60c1e13bef1e37f65450c07a5855c1294b9494ae814cb7ce6a824e0f2336cdf961a5a954ee06da0fe516168788f4c642977c7963be758dc12c730	1	0	\\x000000010000000000800003e77c290eed8590ae75a23cf40e2b4469e916199cc0e28d1aca57befcabf7d41abac9b33b2934a9472c01441b75493d409249dedc60a2797a4a62f8c81415a127094e6253dc8d663d74ee9a93c7d07ea86652fdc249606399f2761f334e705ed076b0e37e3de050e315b5357dc9b30a370029e5eb3c60196a518a649d7723a2f1010001	\\x77495b72f7001b7b87c06921306c7ba6113e79bdf5fb592807b47a6048b055a5d4a1b17a42a05075028aacadc9b15cbc78a130f19adba034d4ecb2bd3ed9e00d	1654818702000000	1655423502000000	1718495502000000	1813103502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
187	\\xca614d48ce73dc1dad5916cbcdcc78a48ebd58cc38a291e3f82440ae15db7609cc83aac47f5b869a3dd5ab240a7a80d092e2be8d928645fc74c98858218b7cca	1	0	\\x000000010000000000800003d6053735d8f2559dd339cce70c8d572d04658b6bdb66e6aa05f15a4e3e5c5744b77e37ee155edc234ec846e968876c48509b1e41eba437e459bc6232cc233cd35cebee06f9622d294345fbf085d8282c36d9cd757dd9f26e9cf20ede49442a91a8f3f4728ddb8c0c0df38af06570d63bd9f689bf95bcd167a1b357e878c88acb010001	\\x3fac8ada43084da95119545e93026c14389155ab730e21277f779875920d7bce9a06a2702ead445e70e215f521ec7a0ecb7a42c2845f7ce2afedbb5d44437308	1652400702000000	1653005502000000	1716077502000000	1810685502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xcb79e0ce8e276a73eff784d0e26cab2401b06283338c6505751943ba86fce154b8c21e82bbc2204bc3d0c88e94c6df4b1f96ae6ce1848d327c47375b56d37ce3	1	0	\\x000000010000000000800003b6257da0bd02a02188d2700b0e324d96a9cde1b39527a2ef6b9e1e74c7156a325eb2155b665eb0c53bfb200cc2ae2e6da9c3d6b3b693df9eda5ae001734967113efe37d913e92fe24662119df6658333056cb84040b719f74b98d01b83b714fe95d9260d864ea56929d2603d30f47fd5490387be1cc16687f4f524b71bad7cdf010001	\\x182360e04806934ce6887cf86f8cd8cbdf11137841cadac523d83fb4a7b3d60f6f1f6fd67a7d2d60e7049f36eb202482025cd8647b7cb2c030649145afc74d03	1678394202000000	1678999002000000	1742071002000000	1836679002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
189	\\xccddcddc353b8e44dd4d3621f052a03a73c6c08e22a63816f1a032f6d11bd1e93205977d365d68e37eb664bec38e5e5071dcdf5f970afe49fb7d6f356402b3b6	1	0	\\x000000010000000000800003da4c656bffb1ae63b2df36a17b9a73827c22cf96213dae7eb4f8066cfebb9a509242bc0643e6d92888b003d102960ac8ccc63b638a4961b5a4f8dd36469e5bbf4ea916d698301405a2418a7a57c311dfff874f3631e62dd7541bbd19db3c143b320b965645e350ba6c2b6f5feea1ebf2a1681253bc14853a0078600175fa8143010001	\\x6c21ed13a39ed9384e6f257d79eb8f447c107a03f0763881b31de2ea6f89c9c7ff9dc373a4f7fc3d278abadd66d5104977a3694e9cc7bf2bcf97a0f820b31101	1663886202000000	1664491002000000	1727563002000000	1822171002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xce4de8b162ae803f5568ca055c0a5ec9179d135bfb14cb109827de7107de172e49c503f5cbfc3db584d3b449f1ca53272966a4fb56b917183ac640e5888a8354	1	0	\\x00000001000000000080000395eadce80831551ff64a9ecb1790818b8c6a3440c4f0c60161674b277f7f09fafa63dc74f79e0d02e495edc15b88b22241cb40f4375602fd0aec14fd4d227f86867d1ea40e90de8ae7681c9f3781833347ded3e2166f6940bee8c231b1b08e197d169a6fcbee41c5500e9983dc8a54128cc982c78a194c881e9f4e22acdb77e5010001	\\x9dbcf2e51328d1399ef4d1bfc05c538bd87d3cd50f9ee84f687f117eb6323f479fbc8e4782c6d9ffb3da7f38d1c46368f080bb3f35bc71113d9601df69d5130c	1678998702000000	1679603502000000	1742675502000000	1837283502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
191	\\xce118c9457dcad1c4114558d2e6385c57fc4e2dcbf3a24cbc70382a8d282f66a5e74016ac9a2a1a81d6b7fd4b5f8620ec6926ec2558d364091efeff830d9b86b	1	0	\\x000000010000000000800003e0d0584ed6216c5461275feaac3d0734bd0a444bae0c9f236ffc4572639adae7c7d99a4c9b97c36c53bb4bfd448efc9aa890b429c65a4e79b6206d9371ac4b5e2fe8aa28219f1e03fe0315b29db10cbb1cbdbe6bc56d26ead51bb045cf4d1dfb305a5d26fd1d578b9f943cb39a7aa033d5a68080986375f5c2343512c601a73b010001	\\xdcce5b83bb3a6b4e63ebccc273e321b52fc31a82ad523f4aae921a9da520d7483c937cca43166b976d45f5961e6f0a665fde1743fdf87874e4afa139cb07dc00	1674767202000000	1675372002000000	1738444002000000	1833052002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
192	\\xcf9d11ccf41dfc14794e9081b7311f39b650bfedb98f9da12a97e0911759f9b0a41afd0903f7f35ab2b68a4cb6b0bafe122945c4082c8f1daf89a92e79dc14e7	1	0	\\x000000010000000000800003ab9de4e078b3adcc7a2b08461cd612810289c248842d3a80bb11655f045fe93cfe4a6804c8c680a277bec76ebfb5623a0500436b0b31f8226f77792872b651ea0a6e4175308477d831ff745da139963944d0ab817eb3fb6044ac5b79e749170aec36dc1db760d5ba1ed05cc82b9943f5a449c001654398095fba75a2c78052a3010001	\\x3247dfad4a78d86bac0cefbc6fcc4daf319af768bfc7ee006a1758c3d8a4ef1c9dd4d49cc66c3febb08e12d1e1800e71bddf86be73a2cfeb1db07fd328215d09	1672953702000000	1673558502000000	1736630502000000	1831238502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
193	\\xd1b5408cc9684b00ce7e8dfaf2f652bd550d2c99ca257e2277d8dbb08cf8f03f16bee451224301d368682f04d8559a92971fe90b93f8329c6f3d3abdb82c42c0	1	0	\\x000000010000000000800003cb94643349424fdf9e107c4e811ac0024f1aa0702aa18f3ba1b48a3fd8484a085968ef031e6871dc2882c50dfe18b4c3981dea475448f4c69006992cd29e18d7fbd3a6ba8b0030eed3ce75d9a4adf849dda4377b464752bd6b0dcd897da8e4828945d69bba8cb617678dd1e721078e74133487571e8d9aec68861b59abf33d59010001	\\xe02d169bf04618b572f5f47afaab6e4f66af278fcb1baf292e10334f64511a5826e52e086240d4a58868dc14111eef3f4009c7c6c116720ed395dc4502016106	1661468202000000	1662073002000000	1725145002000000	1819753002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
194	\\xd3d9d0bea60c0ff3be126c0ae778237906d988b97b70e62dc1fce4f52c01c6b51fdc748f43862e5ebe12fb8965abbeaa52014d0dff76318ef85368d72a06c55c	1	0	\\x000000010000000000800003adac8272199a002bbe37628ba9477c91c3d36120a147102620fda11f3c56dc864454585718e2f728b4c8811b8c4cc9e0814c761cfe7358281becded12de896de8832ca6ea5a1f47fa5a2a807cf410072deffd522679157e68a3fc0852681e5339bdc3312dcfa6dc48cf493161874494abe73e867ad3ddd889363b338e57680f3010001	\\xa04704b885c2a606ad42e1b1edc3cd6f3917ae83ed8e1e8256d9b42280b39d06a72b7960665f6ca97f4ebce7bddd8285b19a919381ed6eaaccd0e2498a36200d	1668117702000000	1668722502000000	1731794502000000	1826402502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xd711a974594999dec6b1a4c9854fd77c70175af098400fa15d7ee91b8a0ff5b2c9d247f9a9e60e6a56383280553cad035b3bec4ae339af92557e15ae6ac4b5c8	1	0	\\x0000000100000000008000039f442f634c394d4c37bca81c60e217b78e9e187df01a02ea8665215c88765f19984185938afa388333f924a9d3ced6c164fd3196008f388ed19a3eceee8b8dfee15d5c5536682baed77ca03b9c5fb0428d074e2794124e55fc7c9a37bf8405e0299b108cf515a7986f4e80725f0b6bd637e34e4534ba009e631c7e6119cf54b9010001	\\xa4ed3444e16f29a64dcddbba815a58be1330921889b38077b8c254e9de23c4ec989f150c699a0ee445404f3738e4d7fd8ae5a19a114116459d2a582aa10b630c	1648773702000000	1649378502000000	1712450502000000	1807058502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xdac1befe8985dcf991a7f5dbd2d63d9d74439c2276dea4ef1cf0a2f51574659cd2e450cbe29f62c8d9ad7ada2dcafe06995367fe43fdddcf5e81a93879c6b086	1	0	\\x000000010000000000800003aea966f32e843fb372c2ef78bd6f27a17d600f3092a1cc88892bbbb51fcf1f6d66d01aee856ecd2e2b104d84c1b5fd70da98afbe597e5a90379d335a2b346b09218b0af37f413358d4fe35045d6176f8e8d10795cb3aad70dd0e68f38486f29868232a3194838a26401d3cc6ddf2414349aacf9e0bbc7278a06153c20d0ad815010001	\\xb4cab98cff275157750447aa5f2dddab77002865b4eae8e829e2df0ee204b9d499d6a2c515d58459e41015c065eb0e93a919a94a68bea12aab54b27239a41307	1659654702000000	1660259502000000	1723331502000000	1817939502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xddb5522a2ec85e790edfdfe5ebf818fda05808829241595fae981637f763eec9d1adffa91c93084014e44f2de4ae30a5248f0cec2fd49da9c7e572d0b21269bb	1	0	\\x000000010000000000800003ac61f80164f197cb9f55aa9818e22cff1917b44853c29984b9d3ddee53c12e000da1695681fe0af09a5e0a495e14cb8d60427f61187bcf313594a23e347102d3f51401ba0dc7eca90d013639db39a4371c68989388ed37acd5e92f580e8813df8c3425bde5026b95100029e57fbde5dc22a8884a2b139629fdea5737775a05b9010001	\\x27565aea84691d7430385763bfe4f31b5f5cca48621caa91919adbc238e8d42e3599f9c3d824699b4c52ae2bc4ccb190e38dcd9a9f3a58e154a02ee133719f0d	1675371702000000	1675976502000000	1739048502000000	1833656502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
198	\\xe17db6a6abe3eb0c92c3de4e85d40559da7ed3e86466c72cc2b859227f5c7bd8966e198b9d352f108031745b0448298f33b1e3f0426b5aeebba0a0ebd72116e5	1	0	\\x000000010000000000800003aaf222e1b90416af6049825f15442cfb2efe6a8e23b77b1e51aa49fade1367016461813d1e8c5ac379f2e74d866b32b1c2b387ecc3eba17b0f603027493a262086cf04e649471d8679838ff88e7fc4f1315cc71576fb48fc158af24b39886af118c8fa2f65ae9d7be30257c903b249c551398a5e0012b2d7a176a1a058700d29010001	\\x593f1ffaec0a704c071426ab73493010f8a63e888dd936ab9e32af1163124ba97ae125bc23ac271e3eabf3716f2bf5de1dddeb573b93ef3b8ae0e5bdcb4aaf06	1658445702000000	1659050502000000	1722122502000000	1816730502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
199	\\xe395b86faa21bab4457465e6dc75a359f2c432fbdf08cbd17eb22bc32e9a2481c40703d09086410b1090135e0a2bfa31af25b51a3f0fd467f920c08e1715dee8	1	0	\\x000000010000000000800003b38f5456777416925cabd67c007df64fe3a0314919babe5d4adbe74622fe812008b7d006f35aed814babd1bc7dc81a80a25e2480b41d5c55f7980dbe1b8474e1705ae869e9e8f3e23f34efe5ee2f97c49a53cf707f6672815353b6aa680b76874cecd921a6a67136953ad4fbaab4d0efbb0384232c2b9c4bfb887525282fe87d010001	\\x57d1d52941a04786593719d92a8ee449aada6d353988563bc6bdae3963965aecf7699836042161eaaaf134698d8a24246a30173eec8249c00bfa5751ec358b00	1677789702000000	1678394502000000	1741466502000000	1836074502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
200	\\xe569128b2d2d2a6667ee78f9737f08d3d5ac6ef9b54493f2aa8553d60f18c90ea29b3fda771697ba836c3da4144f95aecde84aaf2862f7bb1ab175c5f433ea21	1	0	\\x000000010000000000800003ab66ef0d5c4a115a008f71c4afebaaaeaf92de86efb680dee1c687a267d715447b50d82c3bac31557be98d8def7dbf8f2db97fb17cf2f503551242305ad755d225c0b7782ab7bddbfcd7d412b9e89ec0afe581ade2427c6515aac33a449b423a4eeec8f023749c07424d966a17e413e63cfa0450217bda7e7d8a40280a72e9ad010001	\\xa31734f7b1fa40b32685c91aed5817914d0cbc93975cdf7f70b7028a0abc4c72b2c60d81677f5b6e12a976a7ad04028a425c005b7396b73a84743bc63a48300a	1674767202000000	1675372002000000	1738444002000000	1833052002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
201	\\xe8994722bddcdb8c3478cf1726a65ac3a79453062c9ece31a0669baeb01a5ae21b79fda3451fe07483dcbbcfec8b81a829069dda41ab4a05dd7085a17dc9c5ba	1	0	\\x000000010000000000800003b6ba558900a6c9a04297811fe17ed2f3e97b7d0c21326732ed3fdf11d19baa5779ee2510951a72e1aca3f5b8f2adb412b89b22eb250994f829235b4df02cbeec0cb50f63d9a31d62511d89b95422cd13f15c6b55f9ca3949b9c2dfd5445947b1dea708ea851fa2c121a21ee17f7659ab7cdc40f7c9a6333b8cdad633d5b3294b010001	\\x79d1f8936e6cc27f1978fb12a23eeb3c962f8808a4190e12bbada8341017f1334372d38e41f7ce808db6ee210641599e6e1678c6010f67a3a8f28729783f550a	1663886202000000	1664491002000000	1727563002000000	1822171002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\xea35cc7dbcc9ca52081e7ab064bb5e321db86ad70aacc72bd521f802dcb1efa965e875f20d424d200fd79538f623f89d3ecc912e3f2bf3f7497b1a0b8b693eba	1	0	\\x0000000100000000008000039e6d8fca622fc63874d3f53a54674f30fdd6d7bd3ed141e848001f028237bb1d82c02bd243e510b248ec1f2af1d6a45f45a6ae458b21ec24890b8ad80cf57b8d5950aa72e636b1c811c0600f14d53226f32b72d27e9aa8103d2001f3e3ce160463ada509a494c90b988482c8c97489b137fa64f4d60d0251a9fc9b90c41d3f23010001	\\xcb03c9abc43b787ca099a1d190b159aa7ca72ab8bd1493131c66fb84ab001d60ae3c4ce7ac6810e4034f6f9d30d8568134d834e51cc7df59a94e20fbe0f95008	1674162702000000	1674767502000000	1737839502000000	1832447502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
203	\\xeca106e89e551df4c010f929e47d05e837fa0505fbe25cad1cdaefbb1bcc4460ec8afaf0dc52ac6086deca6605ace72e3b1bfe642397979c189d93fc336ce2fa	1	0	\\x000000010000000000800003b02e515bbb5d3bca66cf867beb8a2a79247aeeec60597461367f32d0a36bbb9282f3fe6806a7d5008063469fc13874db66ebe542bbd1ffe55a635422e8397e4e13a59074883c0087b2c298a7a5e1e40c34167e6566f064eb4a2cc3f4ca9adee22699f4958d75b86a3fe4d5dd7b8c408787c293fac3f2cfb843e194f7f50b0b63010001	\\x41013599fa0275ef77cd66458d180fe58b2bbdb8c99fd6cf2afd59f61196acd3356f14c6cfa1b16f4af63987c02da76e512469cbde8b7022e7e5d6a17f068306	1648169202000000	1648774002000000	1711846002000000	1806454002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
204	\\xeee1514e9ceebff23e061fb099fe44aba07848341c5c2790db95045970913cb16f3eb45815713ad0c77e3132319259ea1782fed2d91eff01002ecddbe6a0e8ca	1	0	\\x000000010000000000800003f0387bb8d58ba9288fd5bd58de0d613ed15677124da3d70404ad698cc5266478f9a78479f3374f10d5da1a0d87f8a787ffc778716de307f19409c74f01b98fd44f5ef15ff25bd9b195e48e8e72ba61ae697a8875a1b20cdd66cf1afcd6b7f13a3bcaf5a927586b5bf30e8ad584ccef3522757844930aef08b44b9c6459943e29010001	\\xab6bd57a36fb8d8532b53aed2baa9db5f1896ec001e9712ec92bbc5658befe2be2f3981cc9ec881dd4f876052eb5ee61f81862a2620fddf89c2e7c65c36c1604	1647564702000000	1648169502000000	1711241502000000	1805849502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\xef8d82b5768a12c70caba56dde3bd7cfe58d24094043556a3da96f37006eadf0daa92218b32e41fe7755db2cb4a0efb085e53ac642a33b1ad766358af1e06cf4	1	0	\\x000000010000000000800003aeddc881d5dd6effa801c5cb08d5b7e4d1f23240f5e676895ca37b76f26723bb0205254329a5c7eee7237483dbcf0b537626ea1dbcfcf6c338b7a3bbfa6b561812e943fa9610b3cac7bdb204e126b5a43e8c193691f73d65a228e1fe22cdb89d72ab747c85ddab3b1e2f7f769faf91903b796bc96c0e602da8980aabff0bced9010001	\\x9e59565c1b634cc36ecf827c18b7b9701d596fb3dfb38084accd22b2db15893b14f5de1f1b0ff32ffb14f7eb983b68373831fc6fd9b755d61309486497cc6304	1671744702000000	1672349502000000	1735421502000000	1830029502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xf1e92eec309654221abbf9c9c8e20183786f12cd3db191e9c0e2f85fe22525cc54cf777bcdfb4754a55ace649dcc0ad4871e704a88fd85df38ae1a9390191c5e	1	0	\\x000000010000000000800003e4ba84f2fb20130b95aad0e6dd0eca54205d7a7fc5bce35a9d88c90841479cae0756fd0e9bf4e49e9cb413854bf91d6864e7c7524fa85f6c07942f5b74824af15521a178f7b5a41cdb8063eadec9555a7694315defdcd76837b8a0b669f1f5229b7249723ce536dbe984d570c1d6c721405847b15e23f3314fc6a37b77582067010001	\\xb88d709bea462820b418b4c393744c129104f795e9e374ad8e7bfc57272781f97153f38257c573ad2a21492c5842173f8eb550dbe2260a2003e437e7a7411703	1662072702000000	1662677502000000	1725749502000000	1820357502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
207	\\xf22125270a0615377ada2a2cbc98c5b29c94e48c947c375daf85bb2c770f37e3fab7f3295e553763353c85126c65561eb482a8cf61667393d4a62b46d9f3e67c	1	0	\\x0000000100000000008000039eccf07fd5a8e19c75d8a40db12a6ea1246557874148baccef9d52e6e58973b41a3096661b762a0b7837c9c6afc03ff3bd8d7c7d3edfbf0b058df43b5a3a8e2abfd88f2a3ed35e5f990cb49f0482298183bbeb48c58f6562efd7cdb843a38d358bfa58d649043572a39775fd16d4851365ba9d8178edfa6360726ded7b3fbd41010001	\\xd4ed0472f8d30374cb7ba09ae052d620c364965c466b4cfd088a98d4dcb03c710a1436826f6d2922abacc7efc212ac3796449341b139886df0579394aed4150a	1656027702000000	1656632502000000	1719704502000000	1814312502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
208	\\xf2818e9084daaa5fb4fe6eb9d2d976a100b76c04cc2107bb1c4762538bd70011ea5401196e28b65c6bc0e611cae30b90fb96f27227f6b0b4963039891173daff	1	0	\\x000000010000000000800003d4ce2ff365dc8add1701acc036a7e53200e4d37eb2ab6fb6262029d10f3944321a41aa3e1bc265def4ea7bae358181187e79b4aa6d393f3c673d68c45ccaa280c496efb51a97cdb8f232f407bebf4a8ba596197edddc1587eaa9cb5847d44963c7c07b67df6eb99323c927553207319ca9b718d98e8a1dd318ed321ce226e0eb010001	\\xddfb84e594060e765197485b5ff48696b8803c8b716ed9063b69d4e7ee9bc757b9ec1e964abbb2c6b3fa100d709399fc12547eb5947c4dc53d503d8f7b11bf06	1665095202000000	1665700002000000	1728772002000000	1823380002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
209	\\xf885545dc1f8a9dd8cbb1c0e6b446629027123c547944a6d428c9ddac873220038964fd7d15cf491cde345e0485a1cc0c3478b54774a10aded48a35dfc1a8db4	1	0	\\x000000010000000000800003e2677c7b0aa3c6fd51f9ac6d7b730526555cbe0e58c8e88b2c35b1de7da4eb11cad6b0aa1b83ca380db8c1857863416559497c8dd87c5e97133275fa1aa57201e10301ba2beef8f623fb76386e4b1afd960eaf19f63680aa8bbff6a785d65515d08bb2dc54cad60acff5571ace45a1ea7559c66652cfd80576031a94f44e672d010001	\\x44916bff671719dd816923ff804e5d917f85a720624fbda3520fc9104668701adb4ff6a469135d3397b497f198e227127b64246d5dfd72fc14d2495d26a36c09	1657841202000000	1658446002000000	1721518002000000	1816126002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
210	\\xfea52f2c9b819a1d88d58f86f4a04c911e19210f7b54099c043d47ebe6c945a6bbb7a331c1b6a0e48e13a72cadf0415595febb37c6a4d1871b722694e6ff47f2	1	0	\\x000000010000000000800003b79df06d19039e188bfab84b72702a3de71cc4d2fd5ad7e3e59d45fa7524980fbaef7f3578d55b152e15ef346b8158d4a46af20c9a92d02a2efd08031eebf4d988c45dbf4502a7abd9a4d99ec411c14b84a02d62880920672da9e65d23dab95c081ff1b48892bd1504274e9e2c0f22fa21edcc8b58aad3e0840e645182f57493010001	\\xa9b854ef8a106753932894e4c2ab5f6d2be6986c43eed559d862597f2f0b2c57984e07b4816c88f5b6223d220deac3bcaf282516ee96f9a2d4a596713e0e1503	1668722202000000	1669327002000000	1732399002000000	1827007002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
211	\\x005a4c0f8b8e429117fb5d99b25fd8b76be5d79695ab7cbf0a35717cb984e8c2ee680d53dcd00846100ab5196d5a1a005abbbbd15320569925791b05f8bdbcab	1	0	\\x000000010000000000800003b525be97336605962f8df39abbe1bd9db6d0be80b8be6c5309057b4bb73dfd4e512962207847926263ff4966e07dc83555692c02aab01af727909ba0b3b4f9ac1389355d2d1e2651344ee8ac9c3bcfbcc857755c566aa30dd89db16c32a209b00c18123c5925acf3b9a66fabaa6c98d25b5c35d814e7d860335cd33f4ca2e7bb010001	\\x662e82a26e89709ec1a3c701a8cc79144b67b2929da140b03fd0be621717dca199bb08e6565b22cccaed58495edfd8d7f2b603889821a47a86836aa441c5bc0d	1666908702000000	1667513502000000	1730585502000000	1825193502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
212	\\x00feeef6fec92b21a9f41b006bf90f27391fd9b134fe2cea5b810f3a38e473b66e802b1298bcc84487f0b5266c90d07f9456249a620f0b3b8a738debb3e64d92	1	0	\\x000000010000000000800003b47bb9fced2d00ffab3456662c95a25344956812ddfc6f7168da7b56a1f95369318158f33c49fcc4a06a110840a9bd25a99c6ee2b2720be0645621652068b8b8590448a095520394e9326949e7d3fe01e8c447fb6ecfcd6513f15253a191a9d9eb5ba19aca8d249a2353030a3fcd4d99fed91a17fc1cec6cd64959094e3f7455010001	\\x34778c88d7892ee7429c1f675f1d25a0eb93b7681642326ed25c0a85b7956594e6da7573a19a8ecb52b78c93190a6e1ab1b0af234c11554dbda98eee0772f504	1673558202000000	1674163002000000	1737235002000000	1831843002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
213	\\x0ce69ae34cd66e688b76b1f972026e6e8d055c0b7f22fed885020392ac4aac93cdcd7995663b1dc26b88f5beca2eea34600b61856079a1e6330ff0d852158459	1	0	\\x000000010000000000800003ccf0727d206b6bdcf56d88cdf1cf6d710ae867ddf8ec9221012c6a610cb0ae43038cc079decd55a4b4361f43b97aac6782736678aac32d0daebc8603b99665dcb23a104e5868628bdb1f3311cac3eb8d1ba04a1e187b721852e577fdda42d630a0e1ad0f6574d57e5e0c57f91b25e5276f7ece0b215dc2865dacfcf9562580f3010001	\\x0b50a37ad5db59c73f1e1b487631dec0d99053418f2c8d370fd33f6f1b43a12e2bf057a8d108d787062a47204fb70e8b43d5ba1215fcf0e60700d0680c16650f	1647564702000000	1648169502000000	1711241502000000	1805849502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
214	\\x0f86c89dddc4f4210fa6f1df93ff22824cd52741951c7f8d22f03cdd72f5296a03f5284989c42367b0980d02b938e7d3dd6cd8f94fd9fdb413f6d8cc34ad028e	1	0	\\x000000010000000000800003acea8203a3e93d9edb819310e493c920ca20982ef90d338b55ceb12fb4e2452806558f494844b0defb19b440733434feb12623f881514a9fa8a52fab4307b7c1ca84d6b596781ba5d56552d72d33f0be7d525d17555fc99363cdb8ab60a0365daf3c7eea8be0c9d5b84a46b1e0df961d466277f68d2da4932ae09a0ac3fd16a1010001	\\x714c464c6f7282a570b3977a53a9442f0ea60f869e2a1a721dc6d166a79cf1cb1f921badc936e4c75bdce6275244016a9bbd27587745911c2c0c05bcc899cc0c	1660259202000000	1660864002000000	1723936002000000	1818544002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
215	\\x0fcee26e18df3aa9d0f65e7443fae133e22e004cd1c82bc36ee9893c23d2391f8f247497151a5142c09471b997415a53ec1da3c1909504c23398dc9c2c6f731d	1	0	\\x000000010000000000800003c8daf9317f51170f749fdbdb38f21d7fd0d5b019effe61c4d9e18898eb682dd4ba508a10589f53cbe08fabdb7bb9b0caba06e79790813d8d201587cbfb185c47a413972035eb2902e1524d096f976fbe689595067637e2809cb67bb88101b9ff1ed35d1f7320d3a387840cb7f225fa74c22a3b41728a2dbba9cd411380936229010001	\\x9888b7efd32aaaea894ac610cefb553326e398f8df3262fccded0330e96c023fc8bfd26b7553096e17595894bddd841696703ea2fff2d6a1733c911cdeff180d	1668117702000000	1668722502000000	1731794502000000	1826402502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
216	\\x130edb7a9f6643efaee6f93785d2f45147cbfeeb978ea363ea1ac97a1bc79d1b9b93534ef1430da1e1a4b8accc364d378dc3341eaa37ceeca595cfd5aaed72c1	1	0	\\x000000010000000000800003b866e324623e82a92f7a5656d1eb50bdb896092aa1fe731e781c55395648ab0e15408ffffe164b0ed9c7581278dce6876810ad2c786533cffa48934dd08c565e9512e34959b6fc183ecca103e62a43a02fc20f45abc03e7164bae75f3e8fa16ab24d9cf2a59b226b230c7c576028dc168e28c53b200a91de5847535e22d3954d010001	\\xa1dcec0edc0e48a31ec18cef56362d758f5d9719c95e971bc52031ffc575673a0d5f28d66c6c489782e3c4dad4d9390b430266d0fd27cf339882045a81ad0a03	1648169202000000	1648774002000000	1711846002000000	1806454002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x136e3683f6a8b9b8854bcd7e97fc43a5b8a68dd714635843d60e1f6d4a84b87ed40b2e161140a1682cec28dd951b7e62a7d4c188c1349fb5cb5d17dc5eb4c9d6	1	0	\\x000000010000000000800003c8487b1a2b971e83e2657f52934b4b36b010cf251789f48cce5adbd00b77a232b8b09b354fc20823cca0ca13d197f0eaa346205d12132916f2d7f6b223b54de978da204b1666d1bb065e529621252e1ed9e03ee7e5c538e5f7ecceb9af1f1d45ff8411b6beaa8f405423e41e61956bc11d22f6613b3f062981bcdedb7752a56d010001	\\xc0bb0330702daa447fb42dca6c67fe9880271bbf1d61125c7e522ca77153a69026dc40ba12ce8229ba0979979d326dd5a3c5da2e2d4ca57f2b38f6dec9907e0b	1654214202000000	1654819002000000	1717891002000000	1812499002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
218	\\x13be3cf1253983fcb08dc7d848a32bf66906c9f81fc43625a0bb85ecc7269bc90ec3e9249fcbe2e9d6243609aea70c908a03ee7daf92d80e1e88c6f2b6ff82be	1	0	\\x0000000100000000008000039c88da16b496908ac4d82771141ca49b43793b5a6f723cbecec60de0961b5a352cc679a84d8a341e14d8f463852727248f14731c42b1c507836b229b0689fb14ce927dc0427913301c98d38d3341f2bb594cc9339289a15df7a628edee43b6012b96d5999b895bb12f5746fab7153a4710dc170ed400df8da653d212abf061f3010001	\\x0f80c2438be2b2c064546b787b1e50ea7d6d28d630d9dd4743a69bb68fc02199642d0fdc8e8509a801a69bae7f0407f87a07c347295f998e0922028c559ccd03	1670535702000000	1671140502000000	1734212502000000	1828820502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
219	\\x18467f461801c9105e4f30d8f58e7f0142173ae1c38be3b2e11b42c65ec56b045cd7f127e3b0376af1a1ec2538ddc956285192f51e1e6bf957f10a63e4487f29	1	0	\\x0000000100000000008000039466741c13662b13a150fd8850bbfcdf0ccc0395ca03267fab901bad66492ab67b7350c1e2439ba5db3dda110b1ad6391a714d3c2735afd24bc4b582b5225f64beb7aa1259142e58e3af31400a23ba25581e2af63629bdd2dcdb5f391f2beb35070503d00bf7d0482ceeb8435a02d75710f9209642e80d32944d3cbf0a78867f010001	\\xb4391e9f130ffc8bf58ae5758e16f021c9d4537aac6e5191c520e4f5bfa1bbfbc6c8d14e6adfecade21e1e88834e63ea2877b388023715df6a9754a362acf00a	1671140202000000	1671745002000000	1734817002000000	1829425002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x1e8297012b920cb2f6e48d32ee9e4adbb05a3d129ae913041e18d2ff37f0604e723cca8a01695237ed92adea70ee2cb2fcb0cf68494215ffdf3790d848ce9c93	1	0	\\x000000010000000000800003b2004e9b7bf8a203700c506149eb7b555647fa5b9ed2dc81d888a4646467c1443046b6034f69a2fd656e158a934e953eb99dce9ae3c93c898fdc8b46cd76b9db4c162f36f20cb9e8717881df45d55db92e67d11e677e4d80df4d23edbfbd070379dc651d095faf44a8c66d533d4da87e20d1bc26ccdc511722d219177f215e01010001	\\x9966d65eafb2cdb7325b069600aa86c778c26a8d283654ff9d31ad9251d97b2344496b72d41c2e99abde290a195374902265a6ddf087d9aa9cdedbed4f027a00	1671140202000000	1671745002000000	1734817002000000	1829425002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x24ea58e7d458961a31d19a23caefd6201bc8da2b13eabc4f2dd362e448c3b3384a15a7eab479a7c3f38cf83782db953fb6c9e3d716381f404a2c2f453b3ab23f	1	0	\\x000000010000000000800003e078a0a6d65f10d49b1cab1eaaca3788c9ffa5511e6fae6dc5910aca1d3056cc43bdfb3a8109f27313361ef39a3a23bce58ddbc4cbb338997d9621eb3995b6bdf205d428e19a421e3980e6dd75f9c6a1956878c8783191d3031ca9538b932d325cd553b6f13371ada2a3bfc2e53036f442dc2dd7ba43b166a17bc76e0d348b99010001	\\x392bb455a48c473c1cf3a989b0ee09a09b837c18e8e51d635217862b35b3f0ac6c58b905a286c6d49326d672aaced6525d79bb1e67362252cff3429f37897e02	1677185202000000	1677790002000000	1740862002000000	1835470002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
222	\\x243e38bf803f9e8e0022f3855647a83018b64ff129ce77486495d473cab9b16c58ab0d0bd85c9c46dfa313b9157bc2285c97e0f6cdc5d8cf7107a2e38c2d92a2	1	0	\\x000000010000000000800003c3663672ffe201450f5101303e942b36a3cfc9b119b376a4bf98f06eea35a0f44460a58a9705e76e8167e880159f9e84a19bd2b6cf8956abdbffcfaa4ffc7b3dc2a2b05e9a850afd2f897c791ac4a25e2074e87706e44a558c8f315f473475cd91c31aef0e8a3a117608c15004acbf0c77464a0f095c8825f312d63a1271f15d010001	\\x934bbd164c9ffb01f52bebf73192c36bb25266e6fd21eab2341d9609481f86ee5240118580aef8f6daf8fc68303da4c63452fa5df3d84882f5e584cbcce02406	1653005202000000	1653610002000000	1716682002000000	1811290002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x254e72a8fb1a6d734f4e116190f7025c6aa9ccf2836be01ff423b3723ecbaf228c9d5dff23830eae18f7c25c2f8f4560fa21b04543dfbc41b576934218dd11e7	1	0	\\x000000010000000000800003b7f6fb63d1da5cdea084eae5160085328883e1fe7509f1935614d2069f0b8af79a5c8bef15e56b86a31d35a16a4df7683250f31bc17011b0d3c84e89c3094e8591d1ba2a68f596e8bb8d0ede64dff85d458fa66895574892892a804899690d3a043e54ce676419c0d74febce1038025a938e2f0493b7ab74da4de0fb9da0708b010001	\\x67919406cf66b39fe943e6381d1569c593ba918d648b8f5e367c0d14c8797242eafd03bab2d4142e3f9a9a687c80ad723d6b86884f75bdb1a5b5c5a418849203	1651191702000000	1651796502000000	1714868502000000	1809476502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
224	\\x28a2ba0112cdc9b9cee2ff393554bc81d5286992420725c8d6bec9495e450a42ef14921fa3f42e8d58dc816c9b10423fa8f3e4a47b90be7be21e6f9228bbe84e	1	0	\\x000000010000000000800003d95f64071556198e27fcead3acd32234e55b808a9a86f974e08a461705a8bbc8dd4e608e4526a41b18c3383bff4f0b43719dfc740789182dc4a10e9e2611797db19125b399bf3f55ec89b6892bf86c374493c65515d62b175cab4a62c0673eb340fabac2b3dc28377ce58ca9c9ed3f2d9eb78f642bf65c89db49f6658ff219d9010001	\\x61107cfa40094e14d8fb01bacb119b1d12a53662dcbe675748fb408efab5e400fe894a9354e0b026836d65997455878db28e4505f03d46a10f9be7b914b72506	1648169202000000	1648774002000000	1711846002000000	1806454002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x33fa0bf9506eec4c9d26aa381267b478cca99b08d9be58222b1792c494597b4babc34e5ce127aa7a14bc7c5194f2ed4bbc2a238b7c795fe8bea4895ef71046ef	1	0	\\x000000010000000000800003b62e4996ea25ecfd677adaeda7fca8efcff9e757290eb66637ca9bdb2dc95fc0854662733d258f4a32c45c4db25ffdfd3632ebf4dc3a096e6b18d879c4f05642bd14596e6d1a1a00351bc0292a264d26558d4a64ab43b7c97d1cd9ba5f1376244f270bdbbbcaf31a224ec29236c84f6c6b515d0384fa49598433d4f53b0e1b2b010001	\\x48010c891570b1df58b041395281bf3f7ca27f24ba5d2e5943b965f8ce79513a89d5d3124d4677ae3f2c498b56ac1dbbc95bffb444a8c962b3c32af12bb3270d	1660863702000000	1661468502000000	1724540502000000	1819148502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x3386546798a2b9ce5e678e44f2406d12acf56e5bb1f2ae4adab983aee754c9c00de48c68a337e8f5783c6f5cc6039b2f09036de245eb3c50ef1f631da73f6df3	1	0	\\x000000010000000000800003f0736e67f23b48f59b39c421ed62f5ff61c67ab80374524a918c8eda1af9ca25a7f97c1cba13c1a010047d643763e02d34aa185ff2d2bf8ba5702532b27593a1996028d1c88ba7eeab1b20ecd6a5bf1cea67ef879146a920b3ef38af53804afcac370ee38f1b498dbd09b3e1dde0b90cecca53f1fcf513fc1c907ce58a4df11d010001	\\x4e3f31ae34ad7ded47c71264f2868d5ac43bb1848ce4ae0a0d913520d312d655820ed20297f62d0c3f3897562ed6c24dfd487e11533295424715f19d20cb6009	1654214202000000	1654819002000000	1717891002000000	1812499002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
227	\\x34aab716af2870bfd7f19339cc7424c580801ee5540c9c4a0ccdb5f7be018d83ab54cd880b31ecbd9b90e6ceea045dbfd2a57a963ca574e186b6e61a082614ea	1	0	\\x000000010000000000800003a9ed846b8ab2dd0ba2f69b95e7bcc447c76d885aafce2ff2ad3f8dbb6fb2e19d49f4ada1ad572ea48327ef795a11b37d937e64f9b32c91d397f459626096f96700bc52670492777f841c811ca38e68b471d7510b85a46326c9629ff01a43174c33d6fbfa9f9c6f8ca6151ecbeaacf58482c144b4dd613980852774091e85e403010001	\\x901a1aa2b5c4e2b621fb2e7833e804666ad28cb6d7afe69098fd181199b9a0781e0cca15e6474f047a46df9449f361544a202501d10869237fb7806812860f01	1674767202000000	1675372002000000	1738444002000000	1833052002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x369277f72782a591221b5b691f0548733adf536bd32d72401032754112d26bb8f6ee27e6295c7330ba30619e67b877012fd4fd4f3895911fe37111396a8e4ead	1	0	\\x000000010000000000800003cafc4a186e958ad9c1fe17c449908e68ecb20da2c6e3b0d78b62c16efdb66af05af45357059524ae376211a6f9f87ac8f41062aa203ad00e261b9ec0dee11fad88e82470d3b50ec964b0bc04cb01df257e6cb275246f91d3d6fe9eaf13b5b61bfb35bcd634890ded7dcb7e7caf0aa7887090b3064cea8cc259d360dbdc78f4f5010001	\\xfe949e6541cfcd6f9af7d5c05fee8b339b5241a7535e3d739b4a6f723eed0ad213b3ecdba09153a8ef5ce4b13c3b2f958b75e2635d5b79c26229ecf68882670a	1648773702000000	1649378502000000	1712450502000000	1807058502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x363602673b9671cad0fb6a6b614e4e5f047c73588e5558ecc7b0985812b09f513fb193e993fefc7e7c1230e74ecfe4c80ad99c9f9851c538b9316ef2fa02e783	1	0	\\x000000010000000000800003f8f0ae744ba423512f85532878240f5cb1e6c52e1f5d34d6b057218ed686729d470eab66c245c8bd36e0f052eb2a31143a7d2e1f2c98a427338e28a14f787c634016c8e67cb0cb39978ee4a272bad534bf19020d10f6ad321fae329c8fcd7b22051c6de7dc6379c58a0811922b7a48876a22bc352fa59415d2c39aa5e5b5425d010001	\\x48e13670907fa77e704713d237cb57b3d9a05c09f608a6bb3758419043ea3ff2c63271a8580e95897bf13f0940844a55bf630745f958d76ca889d8248d9bf30e	1666304202000000	1666909002000000	1729981002000000	1824589002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x37da635a551ef345d43685be79cea5ae1d991fbadf4c48f28062a8c55feabde5788c3e6fbcf7d8e48cf40608820f92b478b19a14522c2c567ee1f180f40aa4ac	1	0	\\x000000010000000000800003d038970970e940b683c7ebec4b488d45c4cec1b3f0a448a6ae06e004852801f571780a1a89a916befcfa5931bdbcdaa8f3e5ce626afcf740f93bc7acec1f4ee92fee020597ca8932b8ec3f0d576cc43fd85111b320cbd5bff784580b034bd818deccf0a3925f87915b226121312a8175df0d26a207cd51deb2dde7a9914e1f5d010001	\\x8d0e03b1d8d88383134933b1d0868671c2ac34bddc2b90ca265afb6750c06251c4d8616ee906fa918ba6b20b76d40939e7853767daf9c5c4bc528e1662b8760c	1650587202000000	1651192002000000	1714264002000000	1808872002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x3a623826bf0d58d3ff873a0eb65384b7837eee173790e8fa13fb129f6d254783d142d0807077ad4040315a55b62f09ec2628d1cfe5a70478495114d305601431	1	0	\\x000000010000000000800003ad2a4d8575e2c7e67a5619ec1e44c13251b30d47501936a90e5287333e257ef26c8802d3e31e01600df10e4cd7fc95ff436827dc0c7969ba99d9c828d8053bd0e05a90205075fd616e8c72a5a661cf6fa0018016b6521ac3ebcc7d69b5244a31acd27835aa49f315da9a7ac7b371e96878b74e387bd44368b14f83f5590ee639010001	\\xbfaefb9e502d182a8b3667c1931dafec6d3e643dc08b27f0fdb24189af2643495d29ca481e5233fc5aede6cb333d9ebbf191e6dd49a35d5e2075925455e0b306	1663886202000000	1664491002000000	1727563002000000	1822171002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
232	\\x3c4ac2e50b1c76f6531fea5a5b1fec4e996386be87493c9247a3211d0b6b1280a13a13d769b61d262002ec6f510d8e726b352e4f198b6d35039c075b3fbffb04	1	0	\\x000000010000000000800003b344657fac03ba97a37475c1c54a2fa2fd98f8a7b2c4790239ce038c687884552f064add05b8cc11ec20e6ec5a317448a9243621d2953778bdab05b44ceda5146b606214ab7e4fbd6d12b74a4b3c70d4119aa352aa87904363834d97a8f4291e02b8ac2685498658b63d660e332ac50f4812e74170a6e4c6689c71ece4e9d613010001	\\x91f4b220b3f28354cec4fd917de1949f820e1d54fe70b3527d9460b6676e021c29bbb896cf4253bdada21b3de50ef96532470dbbcc0bd1c2a800d8718e3d5405	1657236702000000	1657841502000000	1720913502000000	1815521502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
233	\\x3dd6f57e6c87c604d31431c68cf0d4621c3afa190bdb88ad89d0c02fc271640716b7758d50fe427316781b95c3adf2ed3abbbcc380477af3a8374823c9fe2656	1	0	\\x000000010000000000800003bffd045494ebb402f14ca4195409734f8e20430cab5c02b772d2e5e7754f99be6a3a2ce4a6edb0712613985f119afaafe56bff3efa38b38d441e6e50a7be1c1ad2e4a64a51b9557a2e05c0aacb6be43a8083f35307623fcac47e06000b5aa020c648311149be3aa857b366666176272f4a2abcab0666db115de9407a288bc78f010001	\\x92f7cef5c82a0a5afad456f7d34b73c341eb829c7bb8ba6df75e93ea48019f633da1684b14a209d8c5bf9429ce58db477b1fd6ba1f1032eac49b4d6542b74a06	1674767202000000	1675372002000000	1738444002000000	1833052002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x3d1607ac2f1e15cda4b396ab54d0f02f2cd029663877967315800ebf12080f7b1e334bcf920cfea69b52a46f5268c569850b2342751e5f287a487b3050d3845f	1	0	\\x000000010000000000800003aacfaf073e9699439b4ae42bfe043cb902d93f0139281dd07577cf9cb9db7e989abdf34f4b4a1adbc6872078f07cdba841c4b23499182b038636704da6aaae11ed04a91adeb255f900d19ad6e5522c960d51f7d3e556d409b9ed2d294e99832e10b40294bb56c9279c9daf178863ba5e359d5b384c44ca9f2928d9d08369d3cf010001	\\x29abad7f688b7249a0c0270ca31c4f08defe2a2a2664f8980bf6a9c5dd291e740bdab4526f2e3dedfa097984e62964168d403295b316123cde4c10cc184eac0c	1652400702000000	1653005502000000	1716077502000000	1810685502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
235	\\x3db2c347016f38f66ecac4c7543f2c4d752b2fe6cbc57ce84fec30cc54b7010f2997a565e3df286ceda1cd416a27c9f5400c97d0209bbb72addf17c2ce832a0f	1	0	\\x000000010000000000800003f4da79673887cfa1277cca94c82e547ceee6215038d3bbd4a13e844fc7eb9ba6a5a7286d4b32babc01cff91c58482b5f0b52277d133d1ac59e859fea5934ddabb7231b335716dba3bfb584d4ce6d06475a57036ea593f04ac415039c549277a01759a0e534d10e8941420b96954b16f2c6e3033126d91d3dd518125daf25ee2f010001	\\xad9e32fb23a100385b763e37b9f60f3238d9a1148022bdfff430638a48e1faefb62744aa352c7de1596ca75090b2f45b6ff78d6690af2523c9790b224452610f	1662072702000000	1662677502000000	1725749502000000	1820357502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x3eeeaf7adfeeaebb0844f18e0daf405e380fc0334be27870bd3a8518314bd6f4281dfb1e2f255a58fe9cded9ab25677f993d20f827f4a4841e6f30a18bd0f9af	1	0	\\x000000010000000000800003ccb86eafefc428f477e02eb7bce3206957ebaf6fd9265917a164adce0c9f25bc542ec64c4863432599963bea8d1cd21af4d3914e639cb476361fbf23c8939874301298f2de6d1f5115d5b470073aced9206e92da46f70b6701873941b35ba61ab064971376e1101af32469ea9d0a5cfc3c33e65e597ede89ab15f72f4e3e3bc7010001	\\xceb2d150e103a8ad3225221a5627ac86e6642511c3e5feb69f16733578835cee388a095889d967863016bd5a9f1a2811b445bd942be23618b8480cd4691c1005	1653609702000000	1654214502000000	1717286502000000	1811894502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x41def39cc9803c7b990d4f770bd1ecfa37b1c3f9324d0f55ee86901fed85e52ee0478f79b6f6eafd2e03c4ea9649b9eea109a25edcf4571658532ceba8728a94	1	0	\\x000000010000000000800003c6da42fe0255be5e23fcd46040d3108aa0d028af4e583ee45e8d29b15850f5e36bba6af8a3cf345f1dc59dd81c2966b33a8e9573aed09d49925cd674886681ee8c6d53ed4079243318f86edebf87c4ad92da25855f39d53e857df81543e664d49aef11e7d15af5fc446afce52d422517562b1919a3c27eb63627bbb9682146d9010001	\\xbdd8fdd9d33931c9f95a1451cece0debd569120d2e3eefbc1307b2314022ed6a84e38e8c3c750909aa96bd87faccd92f8b0ef92cdd35afd4b4d1d419b24c5606	1652400702000000	1653005502000000	1716077502000000	1810685502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
238	\\x421e474c8f9c4c424e454888e8478be343d1d1fd1cab53594a86424151f4dd410ee033b4d9e05e67559b9b3d816866ca49ca996d33c51601d1f48b55aeee6725	1	0	\\x000000010000000000800003d539d7257bb078a284bd259ac86716cc2a44e0e794f606976bd14163f44526a0ac2c3f43f3c06f8e45a48959bfc15964cec14065c397e6f92432a522dbb7bef883b56b945eed389d91eb01ef628723e15ea2685ca53565b77f80e3a118d063272806875c5f4c8176c1647c2b5c37f31b69e802757451d24baf82b09b22b0b897010001	\\x543e7fb529ae4d4c641e08af1de6d6b373c1e3aee85a79cd999ec1b68162679d5652d8b812426a7c6d7ff78e4ef64f51352e004e5c2414d05b03ab7ded3c0a09	1666908702000000	1667513502000000	1730585502000000	1825193502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
239	\\x444e08317b94a2b246edbb0d965b0db11037bc7f3d2c9f9f5865d1e5cf8307584f4c9a028279c86a521bb95c08617ea5db3d83100044343e55f16e6ebaaf44c1	1	0	\\x000000010000000000800003d25bb1cfb0c7c06cca0c3dade17f8fd9637d7e93f41d27a9f894ce57677ba7b0948eded1d6a94b42f1f86b14cfc0dfbece8242d924579c260a35478ed32923197714a94a6b5409cedaee2c27738b3007ab9fdede088ce55231b86ea7c9e0c312d466da3dbc4aa4e96c08d9941b1765fa4eafe018f1772e3a600380f782133b1b010001	\\x8914aceaba21efa264b205199beeff8d3da1794e7d8eb9bf69b98985df78cac70779adad2b2a0d8d70b57c1eb58400f07010a6b3d1412f927c3b75211ed8c106	1677185202000000	1677790002000000	1740862002000000	1835470002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
240	\\x45560e80d9274d8e317926250f35461e4669dec8e3f141d072c03b793958d7fd1c7f1d267ea5806e71089715d22d9317d1512ed0b076b72d2ea8c5a7a253f2ff	1	0	\\x000000010000000000800003e923e4b45538491db020e071562dd2def244d408f5cbb0d18bcd58362cae32a0ae14e308a72ed03241fbb8823a070d4905d51518855eb0b5e0ced52df08b247809ff5492aea1a247041797c4ee8458410b37782e8826754b22b79029128cf20ea325c2f1df3310e8c30d221ddb10ccfe25d0086b8b76fbab90cf4c8f0b57bf05010001	\\x7d272aa30e4dc39af0dd7be18be05bde413b55106bc30df79f525efc1d254aebbc1385f0a69858cc7d77cb4266d6f2fd63e63e4ee7788c1a0ba79b87faf8e80a	1663281702000000	1663886502000000	1726958502000000	1821566502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
241	\\x474a1fc90b0f7fead4d4e2300a3fa08c14179c0d5ea8af7aac961bf7fad5fcbfb7c04412a3c8fb62005a85cfa71d187e8cfb4ab60303c8d609733c2c3098251a	1	0	\\x000000010000000000800003cb7c2acc95344e79d69e6afdde059f4a35f4781bfa13c27d879b7ce1706702e94a73bae5cdb482412fd3145aad432124704bbe2e53746802e0cac909d04c616b388af7340f48fd3ac17867dd554abb04d81f2c552bee45e8fc22f94b2c24a39839d619989fc98379fae318c4a781422bfad6a40c14235335028f66d62b2a65a7010001	\\x6d091884c48e2d7f0eda3e4536f295b8d460d90d9610c9b24019cdb0e0d0a95f691623ea03cfc915199da00cb2dbbcbf721accdd3fcbd477f4321ee0a7e3ee02	1659654702000000	1660259502000000	1723331502000000	1817939502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x4a227dd03822fbba9eaccbaae82a46f36303a42566ad44c192fc62d8866c089e8486507f92629c6cecebd50b5f962b8161f55ca76740ac60bb0e4b2f2dce3aca	1	0	\\x000000010000000000800003c46b45483226558e30cd180c7b24569a4390446203da5f59da5c0d63d9ca1d19ca5aaa4d3bc16aa3a7148f8bc4caa86f1ab09345ecfd7475b69c1e6eda05e58860eb50fd8d670b0c4643425b3c8f853ef24268ee4f7fbe09ab4749ec4b0dc84a93a7e6143d63b19e0e196fc0508a1a2c3a5044a2911cb979240259ceffe5c605010001	\\x0426a1f88ec88067b638555f1fd2d5f54ecb052808f69623cf72bbf7aabfd389bab996deff7a3b98650c54e29ef01ba49bc62211e625401fd12e3ab4a9449a01	1678394202000000	1678999002000000	1742071002000000	1836679002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
243	\\x4f6a4f47b5cefeb80117c9a94e9993f0e039957944b904012c3ea4b3fd28509dca1c68b575a9639997359cce7edf021385caa0fd1dbb7bb91e9a399023753b32	1	0	\\x000000010000000000800003adcdb68f30bcaae025979d7e1334c0ef14eedc7fe8001928b7ba87c7fa996dbc27a925310a9b9fa97ef91e84c3b6156430054d424a2d8aaa173d494610b8e5745afe4918752213f4fe137579106f50532a1ddf563e20f06c37b587f5f0399d5f4a35eec8d8f5b5fdeaaedac83a227f740b5780a5b7e60e1f8e9314e0fca2f0ad010001	\\x5e8731e76f7c8a068b4e6d1cf831b7854c87751c21e913dbb77629216d59b07eccde3c9e3a74496c81a825d411bfbcdcb20b320bbf183552125b533c2c94e10c	1649982702000000	1650587502000000	1713659502000000	1808267502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x512e5495046faa3f0d4021fb4b277fc7793775c1ae9bc56d218c33725084245709a8c32c26ef22ac7011d2104c619f7f1b2f5b2fead32ec5cec0fd17de82142f	1	0	\\x000000010000000000800003a5eedd4a0a612b118f79495169afff3c742f9a103547115efd007e3f5bb91fb5396799401f000305020e216303978de522da5767818b807dbc8031751a0c00da3846875af4f96d56e4f012d073968a2e920e2349aaf8866b6fdffa0be1e996de38c8707e1d8b3ad80ba9687554b98bd8e2a9e41b7be0976ebf5b6f14edd6c0f3010001	\\x5a26680519909f167a37b56cceda3b5eba4a1fdbd8ee4a7477827d35d0a62f3a6c56172f1a316297f9d8a610f44a4200f41054d7d3b598ccf1a8b521f1211c09	1651796202000000	1652401002000000	1715473002000000	1810081002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x54e62e0f2bb03075dc83b657c8021c062eae77c0cd6285f13a219aafaf695c7babe29beb30af4cfd5b2821b13d8ab19ec5703e207b41b466718296f563dc99e0	1	0	\\x000000010000000000800003babcdea1fba5435e902b16a9ef9eabc8a8398f9ea9dedf500eccc34cf5e3c153227e0c888fee55d8702a819361177d6b01bcd161754120499126f802c233807505662224f68e280e9a7cf27312812350fa4f6bb14fecd31ac7a62f53e6be92f58346aadfdeb686f41e6c422bb65191deb78876f06c3a1163e9a78a23cc7e2e83010001	\\xefdf5c4348f69f616983eea31af19d10cb7ecdcb533b48615b622a3f57b9ca0fe54e0bfebde1ddf079e4ba74feac618b76fa7f53c9c2c92743e5f8a2e0f2a90e	1653005202000000	1653610002000000	1716682002000000	1811290002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x57fee20281c05b24ff4e33c3c48e08a312d1fe293ce514050696be7d8624d10395668b18be41137c757d00342b849962f30e07af135f8663271df5040eb82cf1	1	0	\\x000000010000000000800003cbe3901305ea1f68facfede0e33f0a2c83f89d3704ab91465118cc3fbde1b1dc43baa32d84726c8a96f8d4004ce19dff34920e6e3e7f0bb5845d094ce1ce5060c7c8360130828e4b4721f0e80af30a0b5181d292e3509869e2ffdaa2b85c26af5047d479421197aebcf8109ee72ea84df5bdec3c13ce13cb53454285996c4891010001	\\x1c0f8f82d01fca5059d8a820a3acb37eaa27c40689de423d8376de71d932dde215292214eff6f659b1474ead04e2ebdca442a3e7af7d459e5f863d8525f5df08	1664490702000000	1665095502000000	1728167502000000	1822775502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
247	\\x596eaa31a16f630302116e0bed580b6044ac331d23c2eeef665f281b2af6283157717c37972a003269ac3b0176ca0223845c5a43a58e6ff072b882eae5b19941	1	0	\\x000000010000000000800003a12e7a1001548302345fa5476aa8b538628de4b3ec81d953db3eedc79e9593ffc0ce3b134be0c702b1797fefb36509982a9ad9c174c60f3f837161dd32156ce9f6a1b6048ca6f29a163071242cc90436c525cccbb149fc43cf2c221c657dc3f5036cdca1c21a4857eb7a3d24713a8f2ee7e40b49653bde9b3d2fd22db52468d9010001	\\x0ee96a6b9fe21522bd0fb0a2fd52aaf3790613997aacfc3c6f0eca2334160346dc75bf6a8b0c2d29470772a35c007a11c2ccc146f1a37f52726be8e6ed07f602	1649378202000000	1649983002000000	1713055002000000	1807663002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x5bb64810220db139bd63971ea9dd39715bdf1ae07f41f6f06dee3b18b288243359195a424cd770ea4cfe9ea67242bf43bc14428124ca671e3227274b86721fc5	1	0	\\x000000010000000000800003b72140267a00980d0f3597c9a3af3122d2ac5725b2216e5733f849064c92debcb17a4e72c48691ff35fe7ad41f165b1296822c54cff58bf330afb327d656361fbba1b2c0d91bb7ce6c4bb0a780cbad75a28da7c7e57516fec86e937ec0f8643cc794b58733f13e99a39941b9c12baa269034468ddd8e29443585f8d0b744731f010001	\\x9749e9dba33cdc8337483fcc59e194bfb6afa3d702b19e64c58f702fd105cd6a21a0654f7d415795258d58493e15d8a839329b0da9600200e1d1f1c27c874b06	1672349202000000	1672954002000000	1736026002000000	1830634002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
249	\\x5ce67af51aa7a75db70da2c0703afd7d76591f71b07b344eb594bcb0706561389eeab099bcf06e759e70dcb7365e19e480ac9045056965536ca9aaebdd73b330	1	0	\\x000000010000000000800003e278d52904ab580aadfaa7edfc870475789104e94af76cf6a79f4d8fb8b9aac90d9576f107e5d65a35c3ae273d9671660870524c868738f51baab5b23fb4560587232371ef23985d487b1695e1d67a9e84b26aea1b002b3b2c90521eaa5c9def60bce7a81748ef668468050d8341e5d40bb88241840f9d8263a892e25c7d2c71010001	\\x47b434478e6a05024891243d9ea9eb03cd5e6cdb6bf074f68528cad4c1dd3f6eee6458f0f4ceee0f8ef9c06617583a9287aecc3e6d814bed3299b07ae11ff806	1656632202000000	1657237002000000	1720309002000000	1814917002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
250	\\x5d3a2429f6b09cf2f8d8802003bdf9c64cb58904ad041380c1aaaed94b17da16aa72a6a3b4d4b97a6db7c26a7fe4b2add3b9efdca2938cb298cf4130963cd9a2	1	0	\\x000000010000000000800003d6d4ff13a070c420c9731c7a002e3c55141e4e4545e44c85c3f80dec4ec439115865fca2c0fae4e180da99d061ffba9db29912d804a4cd18e32042b119c3b2fc833fbf798a9387509f049d39d10baedeba0f209bd48a9ddbd7e1c3950425c30738bf3d5489a43580b47d46273a149873632b8555cfc5d93496d9853927b0264f010001	\\xb6be27165343583d9b3b219498efa5870d6f261ec9fb9d6b3e6d7b49efcb74926de7e95dc48c8b89311d023afd67fbda31dbfca5d6195d1ffd6954004d32890c	1654214202000000	1654819002000000	1717891002000000	1812499002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
251	\\x643659fe5e8843fcabc5a71efd1ac9630980933b3b16a3156914615b0a199248cc44ebce4dbaed83120c3be90a2b3f25835599ac2e20bebcf3040968b3e680d0	1	0	\\x000000010000000000800003b08c29cd99009b97c842aed9c6d05f3ffe87d64a9a05ad4b17f1bdd4b63ec5deb7078cc5a65d47d6e1fd29520301a6056522f48e3b0459a15e1badc20101bc581b557929331d0c059c6acdb5ba3888be273efcdbf2b90e0bfbae4f38de2ad1b86f1f7149ed48e0b39555e5c00aa70fe47a8dc7b47a8c2dce29bb72516e793b89010001	\\x09b0ce6e251bda77b3777dcc6abb8a91e27ff64139ece153e7724fbfe7c0475fe47a2c2e703af2509b0ec0f7db37cf9bb0b31c09871afd2d7b6449361cbcf105	1658445702000000	1659050502000000	1722122502000000	1816730502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x642691167924dcbf749246f6c281acb4ec3bd2f207061df4b9a05aceb597d5bb2a8065b8af74bbda6419ee4fa4d5b0ec91fc0543416a384fe083d15ca9f658aa	1	0	\\x000000010000000000800003bed6fd6d3e419b48f1cdb6e4b524836befc06edb561c74f0e431477c8a4afdebebca2e1023d5cc6682d2802bd2e149b06e942d4d8db8463d3f0140e1e3c941a434dc0c6e7053fa7d2d9f7986365de594bc0131e11e6249dc8845a48b0a762b8ead6a776163e77908f41e320f1f21912beda1565fe39ba0de2cc63e2434181dcd010001	\\xa0269d99b2e9f32c0742dabcad767f86b44da0e5d219356f9790d8337026968719126f9e49cbc7402d3298bb9f739f5e4f927d9af7ffe9971fbc6ef083902a03	1651191702000000	1651796502000000	1714868502000000	1809476502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x662ece1dbccb1e4a66edb7679962d12bbf7407fde01e3c7c5adbd8223529f7945d5f4f803f330d5e31a2ac5625b1191151fcb3640cb9dc373371fb10ffb5e35b	1	0	\\x000000010000000000800003cf3665f8dfe85cbddfcdaadd83db15823274298f9421df84004f5840ad9f4acfb5abfb73859a06774230dff8ac656dec22cd32d042dc34341a1fb12868898eae585cb03d1c8b37a17a7a74f18749b53e3cf36eaa0f41256c23c5cf4e6426cbc71b1d2419b882baa966bcbc59bcb145a4afbf57ef191ac0b1a5864ef918def4d1010001	\\xc83e89fc9f21173a4abdc3c6edcc22cc17c92e3700f4cbbd6f9515223464a234e1589a5beb8c1fecfb494af8459cb3af719bd5ff638b65384812c9bddb8c4100	1657236702000000	1657841502000000	1720913502000000	1815521502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
254	\\x67e6d1d0a9647f188d1520d26af9b27c0ea1b798b2d782038d999d3cc3335cd07eb1044901ceb7bb00edaeecdc0dec125ba4f56e82177629b79c3213c3605403	1	0	\\x000000010000000000800003e804c8ec616abef0df65b2d731eb1a5fc64468a2155a4cc7964cc9a6f95a9d96ac98eb975ed9fad84ea009b7ed309aa0bff8ac2bd729fa161c8c26530b78ea047e746592b1b4979baa9b351dd29e72e9a419125161bad68c1341a72b14e22196e0d7fa271da4ce84c7fc00a3ad79d49f849d37188cc6ee88443443b50059acd7010001	\\xac6e4ef684f8ec427459a8c47acf8a592b68ba70a668d7cfe217a5b16661506a25a0b9d07278cf6a85ebc732ced73cafb4d85fa09b7bfd38ccc43602fb9b1604	1653609702000000	1654214502000000	1717286502000000	1811894502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x6a1ab0dc56a1d39698f05ef4055ad70df6f08c4d1a8a7f4343b7aa2767d26ecac1189a2f08a560636e46fab83675f8367acf73058dca481850f57dc34269032c	1	0	\\x000000010000000000800003afefc19c44179f8323d16f69d3b042de328a2d9d219976599b3d08c151119920b1d6d28b1257a1c8691a34d9e2b7915142212b99e0ec75f219d9eb0abd53545a88607b7d1b639f0792932c8ad7979ad575f20e1393bfeb1b63b8ef6cc2207703617df522aadfea6eef0d2929d770803d3f9bc07ed058bbceeea296a21a1af667010001	\\xfc3906c34738c4001afe782328c2d48409340521cc5e5bfc55590a59606c8c188824296e98ee1b3785211d65406d50400b2364e4ab23cc7c42ffa7d2c839e009	1666908702000000	1667513502000000	1730585502000000	1825193502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
256	\\x6bbef24feb6bf23c9f8207f320f2b93430203250e33158f2ccee5576c89007270fe95ab8084f8379a4a5957a9afaec657456d4945721691d6ba6d08f54e3bef6	1	0	\\x000000010000000000800003ce567775f1f4e7d0b6d000d70114bcb158cfd80955b4fd3c0376ce58f913683ad00e71aa018bfcdbad8aa0f1eb3fd0920c440538a33cf8a289f54b89b90ba2066d650c335273d8bd26e36614a74bb9c8a3980e9f2f96b1c3bcb91103c357ad8ca7de749a5c931abec016b4bbc3f33809030665de0c26efc6c29dc50ac7a8461d010001	\\xae8c6e98f9d2830cb3f5ee29cd53453485123ccbf8bd700a05463fd3ab029d3fc8d2e06ecbb60ca7d99918a8fbac97f824b33c35d08c9f235c99e0cdfd41700a	1653609702000000	1654214502000000	1717286502000000	1811894502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x6b9e5e42f504e8496d7ece99a3918b2154cc49dc8ee5bf067c80aa229e3a47afcf9b9b15d459ef9be9f0d12c677bb8ea28da30419ca3f2d4ef0cf3d59d6a7d31	1	0	\\x000000010000000000800003d62c66668698c3c348d75c8fad38eeed8f3770c7cfaf198eae3549d6c29b5a1ad0bbb1558fc00eedefe9d3e4a06485bebe61bc9e2621071220cec0bb240fa87ba69126c9e276cb67251e91ceb4f3f142ace253e2868b51a90e193eb8fd562b3be5e7ed8a57166ba098b8e6fb9edbb1605b1c6ebbc13e3fe15f149f22ee722f3f010001	\\x9b6e600046398a8a307f1d0636d058e4fbda870b25d5b62309d6d615b2a4966f9f515496a922478ae59e5f85a26e878b13f2c113a4d937ed7efc38b23eef5307	1665095202000000	1665700002000000	1728772002000000	1823380002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x6c92e11b73f17d85711805211e8e80efe8a6b83dd837647e15f260416ed840657b1410d8a97bab6955e777127454383f4aec59a83c6048fd94c5dd70d096695b	1	0	\\x000000010000000000800003c97f1a86a90bb8cd7cbae017a92666f05b5859858035e712bd20bce21cf182cc2cca8f097744ffa5fcb7da25ae51717d5c63f170c16f25a3005181b5f0dff9fd03bd3e2a98979665d251c0a35c3d1453a843408152b720c97b1b0ddb394f50f8b2f4386f1684a0728c96100037d2700a87e4efbf9e7d2835b73ce4f6d947c255010001	\\xd2e6a312078b64ff93312dd2fd8ec76d7948ba256d5aed0d43e11022ac6ae999073b156e2e092c3e180bd622c3f3c29c7459b50c14d81f11d2e2cf848bfcc807	1659050202000000	1659655002000000	1722727002000000	1817335002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x71563b8375c9859848cf7abe8767a666dc5bcca8d2c1e770421b63d5b2e11ac970456db76b175d3b4feca55790e49c5cdbc14e760ffa15cf6433442c700f7b50	1	0	\\x0000000100000000008000039d1dcba75a2fbf7bc81a7fcc51622dc9a0ddac7b14726cfe41808ede96aa4917e235753bd4221e16d930ee5e3e0c3f8c7aaa99d0c1dae37d6efd65d1e62e7f1886d358c84b3f2d3bacba7a9bd058126bc624258dd50f077c79421f885bebb14c5f6a200896912c4a2059fd649a8567d721a63a69d44e54ccd1f48f8782c600c5010001	\\x70fd351c5474810e4df389960d2071bdfb5f6cae155805b643eb4bb1638c18d4ffa6e5354d7a6330dc7a44f3d87e6adfd9e0d59c139b2733e5336db376ef270b	1678394202000000	1678999002000000	1742071002000000	1836679002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x7c8af0740dbb479110d2d2bf795da9fac945dc9a8b91b66b44bbbf7bdd674bdcc409c50796a90daeff5fd20843e2d8ee55d994ac78d2490d7c8bf1fa735e7606	1	0	\\x000000010000000000800003dc8820a838a19eab031f8d52ac04e452eeb451caea04bbe065c2514bfb069ef141e903f633aaad8e7fc420424b9b552fd045b3622bade6a0e40fa16faf2ecfbcdf974aadfb50dada34b2eb766fe8102464c1a422879b99ff90bc75dcf0013dc2a6d005aa9b9dfcc99a501f24dfd110e985e06656ea655deb7956ddb07004f733010001	\\xd5153f2f08254f25baa23a8cfdf1a5fd5c44d813a63d1557c2eaa8906466f348c92de896a830325875c749af23b1763641aba07cb695af51a055192876eb5400	1671744702000000	1672349502000000	1735421502000000	1830029502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
261	\\x80c6fcf1c5efb2f4a61b973951465068dd06e60407353e33fe7659c91c94f89123d7a9e3c31252d9db3e74da5d1033a0de7d9f23c0361078f211be587fb8bdb2	1	0	\\x000000010000000000800003f9e4ef031fb21d6690c306fff28c70ae0a4682e1884e79621f86e0ba1bc5a1ce08912865a37900c7907d73506c5df0e6e66d8ca743125a46e74d9f34b4ce4ce4a185bb101fd4f3e4c810b301d57eef97ea03003ae47cceef276d3cbb7653d649bbf14c7937305aa84111823af84a0572756bd13d0e8dc671a6337614877d52eb010001	\\x6c37e42578aa8b06b105e885fd08ead560e6c32078293e65779f5e681eb14e6e96d15ad39e1e0c31b425d2493af0755ad4d2c562a253dedda6f2a1c9c558b10d	1665095202000000	1665700002000000	1728772002000000	1823380002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
262	\\x83f690b9116f1e08044748de739e094bc9d6eae17499555cc2cc0202afd4966a0a7af0d71e746fb34e7d6d1fb4381ff1f5f4603f87a46c6bdb211c46e7a933c0	1	0	\\x000000010000000000800003b0d89e7366bd864b23ccd6500fd9bd81f61eda943474d7c4e8fb377f6427c7f1d2b06482d36e9b5bea8f0b60337855d6eb683e44d42f0e82aa78681c7e9b18604e2b096f59ceecddd4694a2426a2d1718cd6307b086da700601751bc62abb7b65ce84dd17bbb1e1f0af1484dae2337695f2d59bd9d5e057e366c385e58063877010001	\\x2c8c3e5770ce37f2e9ccaac5bf1c328c5da18a27fbaf42ee345f392ef28b96f02a0f093b897e8d9bce9a06b70e9042f23aae48d804d5dc218cb5b9afe5a89405	1668117702000000	1668722502000000	1731794502000000	1826402502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
263	\\x896255147bdda6fcca6bac4753860b93f370c64e8a66adec6c58af982c8b774ffbb2b6f25836d166a5344a13c646d86e26c3a834a15510c373b2408a55fbffa7	1	0	\\x000000010000000000800003bac09e6b3d3aa70ed15347a9f2c417b0de22d0b87293448d571a0bbd725bb4a7b1b049288a84c5e22784f39edf9728aebb88710197f10c5e719dc9859913e3a9eec48585865d3cd35ea9149b24937344bc320b7106e75956165ad2d8a6a6e626931a8ce64ac94286bc6267c39aa83c5cf0898aa9887b9125b0d8c0858be0ba0b010001	\\xc3e0ed604dabd5e758b4d51c2347ce605fb80014c394961560cbd2bcd20c2d37e4634eab5c7079acc49c61bffcd2f6bd1284c528f39b6c460474be24b959010a	1673558202000000	1674163002000000	1737235002000000	1831843002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
264	\\x8d1a69705fd5109dd23824b7de1ddc0bd9c66e864126368f7e70ac497ae8d9ae8b6e368c8a4a7467044fb5a46015b2fbae9f22140dbb6809a5127a91deb561e0	1	0	\\x000000010000000000800003ba88aa0784037ef7bf83b252af3b7a8482b1722fa2b8835a77bc051a06eddc7ed75e6d3df0f1e946962e4a497a81d230b91b564dfe451b3243d83b6f04e6e515ffe4272a91fe4e05075b70619eb6a809b0139ab36f163bf8b084491e645a35a9345652e0b0596c9f6526f0f617798e25ce4096289ad81d89e26d49843ab3f4dd010001	\\xcf4f50374b0e9a7504f6e9ad6b970cb7dfcc2800c4f7f49d90c7d77ade3cf79412337d5127760e51f25dc79a3c9153347ed20f7d2379f1b8c3e476bac6696d02	1652400702000000	1653005502000000	1716077502000000	1810685502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
265	\\x8fbe6ce89ac8c450f5bf063bbcbb3df727957d5cb694594f607618d1cf6d157d53ed9522fe5a12ca70174c6d76b712b8efba0019547bb7a027668da2b179213d	1	0	\\x000000010000000000800003c237c1379f44a2bee8135e6785fb33b0525ab16de51b236939d538ba5d9f4215dce961e7719759bb7172af98201a6832ef07ff3c458767962cf92d2bc9450c4ec8d438a48292df1da018a0fcb76cb3e63005498505fe541fd88d55de46443b1755c79097f4f1d7e1328171cdaf377b16142e876bf97bc746946a52c5be034f6b010001	\\xf257bef2451ffd5129603f590decee1d3e4a7619420989da75ddc37bfc0e96ae6fd5012d45c068623eb90d6da75991175cfbee16fbf6044e57bcfce161900903	1656027702000000	1656632502000000	1719704502000000	1814312502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x8f2e446e3553f830147f6179fc90cda9c2b825503caef4f772f323382847d9a3e0d95b7f887a8b3857a4e4d8f3237e90bc77a80c62b9353064a03806c4c40dc5	1	0	\\x000000010000000000800003b2d808bb5dcc0bf795f6a078dd27283ffc907fa7c5b999053612c7e0643d2e37b330d520630f96a203aa237f8783a9e9bb67641178e89bee2f747622913cce38f24e8ed59469bd12a20ad73ae4613ea0d5c6dea6c66389b8b03dca892fe6e8d842859327a12f18c72bee718c1bb85cd65a88ba65ad346c3f0e661f92296af53b010001	\\x02eb9f05520b3f8775637ed40d0d3173d38d29f098aa5817028d38755e16d009c7a529bbaeae3352e1e6449f1e264348dbfe829ad6e44befeda58be07ca18201	1674162702000000	1674767502000000	1737839502000000	1832447502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x9936b7b56698da209991c612f1c765253f6dfb118ec029a88a5738e2ee65001baa398f715e296aaf728c5d13fe7254496b34aad65cbe2aba12be1008f5eca310	1	0	\\x000000010000000000800003d46f7c1bbc1a5c6c8349dd3709b17d3303b7be02ebfa688f94d7e59e920f0f32c8e46a3fbf57a3649daaeccb3a2741c8e2672a98ac1164d220b028b1bfcaf4ea27dd9629f2d7e0f772b292f6afb7bae0424847cab8b2dffa382c4e39bcf4dcfb1c181701e1e290ac9c1163b5474a165499884b69499509071be08498e1120c9b010001	\\xb6774b86077ea8de56af2faa75ef0c7a155afc203f64bab01245fb4baf6b2316be89bb667ba0f0e95a21eb19d6798ae005203de744f1b9349d9f3b80a7480505	1653005202000000	1653610002000000	1716682002000000	1811290002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
268	\\x9bd6d609698caf3f6be9a52a28d5a96cdbf55ac2773c05b2dfc402fc902b1361d61933e1c55bc0df785a8a0d8cd41982d450031030a0e7113a9a18f3840bdc34	1	0	\\x000000010000000000800003d74df3496a7767ce14a9147a82329128cfe55d14a3fa59d81cfaa90c442bf56720082cdf6b46a171e9bf29bcd655167ad4b0b088e3e33559a184f8cbcec3d7c88ccf4aec1511a942b058a73601a21e511c5b4d0b637d9e7fca447a846c576443f914a47f9bf5fb3f58d33dbfc0e160ae4dc2e94c77205e8e2a33c4a4d4c1e1e1010001	\\x9b8da5d8b65e0ac1b56d5777e960352792786ef9e455190ebf8f18519f5000e28818ca5bad0b9fdc8776b98c4ac1970be5fb41dfdb02a2873af5b49c41de0207	1675371702000000	1675976502000000	1739048502000000	1833656502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x9b26513fcf71019728a1a953f2a03f323c51f047324f9931086deeec72d2b48495d7c4d9ce68109735665bc17fa3f5f7ab35567596545aa4487d0b856588f37f	1	0	\\x000000010000000000800003ebeccc0d47013c463044359020eedc96bc95457fdd173eb3d0ed424ef67e602e0413ee3d641733217b10b8c213913d8c72e352818fe39ffa3580ee352c24393104a8cdde4c3588bbc6da53d86a4e8fe309d42147aacc3ba5b73f4060a180ead135759ad14d0b79ce67db04ba1d364674110699d9e7101d9f7e620b95d9df01c7010001	\\x53c39dfd8ae53fd684cab7197f61834946e14e6b77b219946a00bd2a4378b505226d9bdd98b6c2350158705937b94e4b6bd688fb64e8d506fb4dc30bdbd72f03	1662072702000000	1662677502000000	1725749502000000	1820357502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
270	\\x9c8640a35532d913ac7678b442b097259fd5dd81f1ca7c705c5a702a08940073d092fb75d86b7389618202aa2d8c70d79402f8200ca0377784488b121acf14db	1	0	\\x000000010000000000800003c44f2eb42a45548f0eff31c4f9f7ad14e78b425f39cc2207b70ca720891d9f031ad2ba3750c5f817e315fab656d4cfd246c06bc41f24d64f87df3be986500f514f34aa6b2ede3bc9be93ad89d5528bb4af24c5ae25b9597adca7691003cd98e750d7e5541e9e7d9422537d520a02baf2a8f9a9eed51c14be06bde381fcc5effb010001	\\x8433d9f85552644825931f0909b9937b85572a60f4c668db96560aaf42583a8cef434921578f1bfc77ba20427c7ebee8f152a6f39c1d3b82e18c4f004d8df508	1647564702000000	1648169502000000	1711241502000000	1805849502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
271	\\x9d32e2481f07376611602dc50682de0dfd0a24849bda9b25dd67ce84be1bf66cf012da78544f9569b53e815ebf8c7159a4dc3b86aa4cdc4ae7697d1e00f0eef4	1	0	\\x000000010000000000800003e9040e1608f946f437f3f3eb8ed36e45b4d82e880cf82a7a134766512d71b4af19600fa3ec9e8bdab1c5567bd18ad86043c38fbdafd25d816bf96b5e56efee254ca278fe0cfb35db9963719c97bf3d95ac4dfeff1dfe60045649f6a63468b4ea31ec9d5f2906e480ce537e41b81b3c6a92a629290d84f187dfc599dad6bb72ab010001	\\x5d689b20980a7e76a712bc17805db804827ce0573a6d198e57eab713b0f4d1bdb5686369546a17cb7647b19086006cf29171fdc285559e2cb32353acdc790209	1649982702000000	1650587502000000	1713659502000000	1808267502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x9ed62982caf3a0c2e06c5cabe50588fde968ce1add2c1e5c3778a52a16c1903d75bbba445dc3f49411ada2a4905197db6f90b46d998511aefba41cf05029d011	1	0	\\x000000010000000000800003c8a5622488f32147344a869b9d5cd2edb9961dccb664760c547bbc6e4ad4ffb98e8e75f9627e688ca3419593d0a913a13b6aedf67d231675c7181e99b55e9a214a6dca0de3fc691d090d4824c5b8b1c929c4dc36ade8fe38fd79582331ec761772d94dcaa8a5f6e22bce875e1bdcf449fcd017e687eb4c4dd5d2dd37742c21ef010001	\\x2c75688f97d3ea9ec8a06c8099bdb709dd2e8ed11d15e51092d7636c6516380173f2bbdae3eb4b8c877b1c3c150657ac56d44cdb7c31e8c9d7c3023c3935920e	1662677202000000	1663282002000000	1726354002000000	1820962002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
273	\\x9f820e74268d0f198aecdb4397900456bd3dc25de25bdaa9c85903ff4abb5202989610741f62073758b368cfa099093e959e8506d43dd8ee6d1cc51742d4570e	1	0	\\x000000010000000000800003d34386a8c9ed59867342ba0e87b0d2fa937823aad5831462d85c5cdd42309d0971a031308802e7acf4b2535e4b1d799b85c5fff9d4014f7821d4239900a0120120164b6ba21f3d5e17fd4411338a348eee3850a9f61bbe883fefcc379b02d3a3e95941fe076a5b3e10ad94e4b8bd3a407e2ee39acfada9fff699d073a4ab5595010001	\\x0e362ba9e5b644b33db57dcf70e801e425623ed8078eacec19bf2e289ee3550d4b20e101260ff7f3d0bf12e4e80f608bd29540377012cef16209b19bee6c3604	1648773702000000	1649378502000000	1712450502000000	1807058502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
274	\\xa37e849061b83a6b136c9191df5581149810772e13fd8884c624fa796fd1fab3613428306aed219ceb090308cf11787e8aa9ae8de26a999e01c7382ed8b4d7ab	1	0	\\x000000010000000000800003b200adaaa9349f70732841183f72cbb7859da4f1e8a12ab02405bc69591cf0ff13dc31ed5ad9ecb1745ebbb784657b7f47a2e2c8aad0a881653a2c2f19d42556a99c6a7a925e125b97bf43c99dacd039326a777cf0951a9925d100cd34818df3e94191fb533b5741c1f69c412374a08b3953e6f9d0d7d9ab0012a620c5daa357010001	\\x13e390e4b1346c3c033ca16d5e1d5457694c3e739dbde2b569e450b85b842339dab509df663c0055f449012affea247f9581b8ca465c1f8952917c3c03cc2302	1657841202000000	1658446002000000	1721518002000000	1816126002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\xa372def9181645f772eae6c3e0e033131f04db9c17db6b778658a6a65140241a21e7c2dd389110cdad32b496a11fa6d1c0266a26a4511ba0fdefc005fbfdfd5b	1	0	\\x000000010000000000800003b22d398f4b88cea02cf720b9990b3c3a6c25959ea6bb5e111909de592974cb39528761efb48ecd7884df69aad50c4853ec2353792e8eecaf440d2658c574d881b0e6df958f23da123d3fcb2cb7e82309b08f988e1c3321301684fa8860eaf9f3b9e64e5dd2f9e650d777baedd7de955ed4a88b1f5d6132dfb3389ba60d1a4389010001	\\xa07b69439d0e1a0f7eb8b072b0ae9f35bb540674e011fb541ecb4885e99d3a37ff29152322f746c051017f7c7f4fd226668a73b3692b49f3333c35531309bc0e	1653609702000000	1654214502000000	1717286502000000	1811894502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
276	\\xa73a3432294cff69a0a0210ba446bb6b8666b0365167662dd40030c5d0b686af355e308efdac18a81b11ea57aa7c87875260711c7410020aafc3fb7dfa18ae50	1	0	\\x000000010000000000800003bd037c23b5f549880977d0af53e6684f5f412f16d99fc50733cd41020feaae54c5e8e81ef026f138e3a2e32b0763ec40399118e92a2fcfd3550c3f166ce664ae8611f64b307b13466785c7892bbf8ad4322d530ebac99a04e2cda1507838300e2c03a56b31eea1965f49ea1d5382c6fbfffda8aed872c316f9270d0f2d8a7083010001	\\x22159c5c44c1b2e46ce88ef6e11a85b66584827cfd50e2c56d8cb28994bb8fe7b54abe9c76017ddc92dbca5116198c44a4bbb47c32032510b0c5ed96940f2803	1669931202000000	1670536002000000	1733608002000000	1828216002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
277	\\xa95ee2f1f555fd1be959b565007c196008ad7d54130d17a23b2a203acb2fa91798a99ec9132f2478d63079ba132af040bcf05a9820ba4b7471be9e33d069daf0	1	0	\\x000000010000000000800003cf55841b07b00b67810d3bad031e424981779c2273a5f32da7e2695dc60766a66996a0d18ceee69a4c5d1f8d1a8786470f39ee0f924553423ae2e7dba5c84954ad85a95ac869a9d0234518bd58fefcfb055b1ea438b932dba09ade5e30ac02a3a2687a943992113df24c639f8f36b27df8f7487de4d018ec10999e6b04950299010001	\\x7e79feec4fa6929a10b3bdf8a910279e563d5bbf55135f9abe3e26ed063d0753c4c15dc23fbec151e9589113a6e0495c7c41f15346f56722cc45ab357eaf8b04	1652400702000000	1653005502000000	1716077502000000	1810685502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
278	\\xab1eac59863ee36f3e875598956f5153b7947c261d7b68c69955ecc3ede923c082b879f5aa1c2d695c03096120d1c911e379c67cdeec77ee3559077cbba8fc30	1	0	\\x000000010000000000800003e4115bc74073402a3bc7542a1ad71b30b0ea2ef9a806444c340d64a9aef36694b8674ec5b55877a9ff3625337a7ea9c44d322583290be31a2cde542833db8482d3b448dec40c6b13aab722daaf2aa3f1ca9f4f8bb394b91031dd145b7de1418f5e1a85d8d69dd564eff62446e6ad411c2c51a7f6454b6f2e2c69b197342756e5010001	\\x6e13b0d03e24fe752c133da14a795cf0f076631dd88c274fa953af1e3dcb9c8592177f21a6eca091dfee48f899ddc85430cbacf9640a70c011c2dbbbab041d00	1678394202000000	1678999002000000	1742071002000000	1836679002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\xade61eb0daa2d4551727dbf44c1e6af0ca5b8b23f40d4bcf19cad7755ec7d2a28e71b99de807c5c3d81a4aecfa36de51b3870ec37587d5566d2e00a0ee37cd6d	1	0	\\x000000010000000000800003c9ea4c8fffd464d79a7a948db097917d0da95a2bc937b0c2ca86bfc1371e87beed2f602531334d013a0371ab712d44d18dc33b8040a16c0987b4b5ab643adce6b04b47884d20f3822ea1a7c53eef2da9cd4f3fab88ed5e040c9e2cff1a23c61620e12994ba3b06039a0b99bf6dc494997e699d0cfe3a23387eb1f595942796c3010001	\\x06b304c2805ead3850b5f006ea05e4e4bcfc88f5f9f1b928c5881d8fd60a54f7cd93849066f8782555ed5a51e28106a76738df00283a28a1ed1d05338b9a5405	1660259202000000	1660864002000000	1723936002000000	1818544002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
280	\\xb2d65a036ee48d24f48545ebab197958486460212d0f6e00cbe2eba206aae1edceb05681c45511cdbaa1f911b72fd63dec47ada08ff31c370d3724b41d7d35c7	1	0	\\x000000010000000000800003a5687e9c818393e4df23ea603c204f492f63d0e814b061b189a650567c8627acbd6ce506e2466b523973635b72a6739d640cdfd12e441d45e487f68d5104a3f7d00d71860c0425a2e92c82ababd018c336db8de9a0af67bfcd069261a6c0c5744e79b0a86a947d9c318da804c571f806a9991d3318bb2cb032ce24d59b96b5a1010001	\\xc11af101e4af77bdf4e14a12553afbee6e4e14cd6c0126c4d11f0307d5854b45af0571f64e93f65b0832b6eaf2e37638879de30906f820f2046f0b70f304200f	1657236702000000	1657841502000000	1720913502000000	1815521502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\xb3c68dffc3d526cec1888a58a277ee3dfc995255041f2e3fa1ffd2ad0d1492404d98d835ce8fad4d34768b5fa535c1dad26dc282052f769c0f16a917915aabe1	1	0	\\x000000010000000000800003f71b09acebdf9c50df4b63fb4e2874de7cd2e4d072098c7452721e0dc06e8c71232cc168ac9beeccc034fc8937ce232c59ace16f768dfe9a9df814f24935b287656cffc05ba58c4efc6741cfd698797bb3ebf7f968b4e173dad4220763b5eb235b897b91d7efef63b888fa1e1e7df1e09abd0d775f619864e4c8481bb93ad041010001	\\x12eaa344cc96719eefcf124e76b6858a2c3c84112ac76ae80a31c1354dd7699ff072f9fc62958d452d8d6221652d3889f5b42fc8efeb41cf4670d3c21cb2de08	1661468202000000	1662073002000000	1725145002000000	1819753002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xb74a945e01cc197b060bb7e4000f58d4976594d53f69e5935163ad48e055c98cf323cbc4a6fb73307f2ed51f5d57381280c439beda2279e9f405b26c272aea5b	1	0	\\x000000010000000000800003ce9ebc68a30f293a65118498206fe7df3096eedfbb612c5f4b95edfb532afb904753a8596b93c8da92c96a4056dac78f045640e39043506dece063571748d23a0c9978c0a7441893001f88d1fc64b783d8159c997893b7b58428b1461c19854b922b6ed6f09e38eed3f3a60f8ad5076f76156bc371acb38b2c04dc9f2a9c1d1f010001	\\x4831b18d9d928ff42234fd74fa843018dd5b507bd6303c871df70b21a5f4eaa8e1de93d39ab3c859daa9e6bbdd65d048e4bc7a2dc5c1f0ff8e73aa2de34f2600	1662677202000000	1663282002000000	1726354002000000	1820962002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\xb8aa6be1e8894f558bb30d4992eaa8179ebb40effa9ace268bb7ec99265587a1bd2fbc2625f9e3f4924fb79eef6f74def47c4c1e3000e2a219b2912cb4199049	1	0	\\x000000010000000000800003cbaee949f87557747ea49a6437d8868b9bb41e7a7cf73dcd561edc383ce4994e16a8db2a03e0b028702bcf93f1b7665e90d7d3324566493c05a52d86dcb553d0f91bd3b9933be3e36abf14b5204b1e7eefcc34c583b0fdbe67d89fe87e23dffd0c342439b6bf265b76f3dde3feec791466915e983d4e7f724e51085b79951581010001	\\x1b130f1ac747d0e5d891c023023f61d258b0abf4e3748b6c58c27734ad3e9257d6ffb0a4fb462d1f7e75a8c8fd597bc3f8d3c3cefa8be045ce28c7d71e59f00f	1653609702000000	1654214502000000	1717286502000000	1811894502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\xb8d64cedf261557da8d842c9559ac4380b8d82ee62ec80bd0df0c21099885b704c89328cbc41891b2088cad303966d98d80783b39f56f34149cd5cdaaade09b6	1	0	\\x000000010000000000800003d47ae043becd9fc599a6149990d3aba3d3dd59061b78ccfd77a0c55683134bad1a83d6d7dcf715f3bbdd9b5e0c393edfd8343ee45aa6b674caae2f501b8e1d65a17fe154fda6527d933dcfcba303c7847ba41efb6067f61c852dedb9606050548fb5b537a02a9e5a2c27e6783dc9e8ca7453dd5562ee5a43aee5be6b684b1da1010001	\\x839223ff1016c6601d4845314551d516f4c661d7082c3777e4892c4ace3c619d37a4bf839efb334743da398131597bfa606cfac4f0786b2b8ca39f6f5f2a6d0d	1662677202000000	1663282002000000	1726354002000000	1820962002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xba1e355bf6bbfe878e0920cd7bffe88ac018abc32cef17f18da8c979435b06253933df5843a96d62a9df942329ddc9f8e94d60a5805d2318d3e3f20e8bcf9267	1	0	\\x000000010000000000800003adc69d3d978891be33b451938e307a47e2b2ce8e4aed9c9576804eef33bbe12ae1b8bcbbfd6f03fd7865c51619d291f2e8ca65b5db0fa954c7e35b5e019cb89d125662b482b85475ba3fb53aa7486cf79066859847c3888d12cac81bdb0600a359bc0b67a17076bbf01ad146fc7eb84cd61955452696b640d9ecfcd8e87994e9010001	\\x8bc9e4e3168614dfbf09963105386b6d85dfb030285bec25c938db4c9ce6cff265beccfec99cfc1fb44762bc392f543f34bc90bdc58c6435598692171a40fb00	1677789702000000	1678394502000000	1741466502000000	1836074502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
286	\\xbb9e818e47285c1ac6b74f664c0a69d63c79d2c406ebf0741ff152405b5f7aea546cc7769b27517cab8f54b9702dde279c2f670c08e585d20e8d5635da69c5f7	1	0	\\x000000010000000000800003ae9da7eda434811e348ea78072b80745ed53a750e84d6b3ce7a00d0b5e4b233d7f4ad43c6966de5eae597969955824e86e0facf6857b32fb064d7c0fc165735908ccf8cea3d49a5586095a7db89f7692c5380becfbd8904567c76919c1ab6510dea7367a70ce5fd0f28373850952cd00606c3b72b340a254a93a7683ee351f29010001	\\x60372cac499a86cd119014195bcb6e0f61b1fd702a286b7100a38ce6c28a4775b8788e74fad2c815a92313dadb50adeb9cc6063d8dc160e5fdb550eb4028d30c	1655423202000000	1656028002000000	1719100002000000	1813708002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\xbf56dc7f1ada5a74eaf765234c4ca0401d6ea7bc24bb4bb9718584f358658ef76ea6b2df21dfc4bc01209837ec841c95dfdd3436f4e81945535e42218299bc88	1	0	\\x000000010000000000800003d979016151a9f27958bec12a9816883d7691ffac641ecc455a5d90f4cd48fe8c94be5b75f1d20a1e61f18da71be02c6b265e76b45ae678f1a6fcb7cca8ee0b39d58ace4e647cc72253777c04f421dad834fd4ee184ddb6c552ec77d70188f1ac3480546813da32f32153fc72818416a58cfb1aa0fcbc753a04ccb15d0f4539ab010001	\\x6b54d26bacf39bd83000876abd9521fcf8d0f911fe9da8a453740586b802fac39e50f2d1e4a16c2080c114a83a27cce03fbdc0649a6e7c1c830bee92157c0700	1649982702000000	1650587502000000	1713659502000000	1808267502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
288	\\xc2fe9b9f2659627ca728b297488ebbd7e9b7d3d41c4e10036b75acc70c3d51dbaed1d2551282e53fc2553b5f5ef772343911ccd4db5d575a989865cd6cc56abc	1	0	\\x000000010000000000800003a48b0d8e2c9ad1a24919c9f15cc25d6d730ef8324ecb296d249567c26ab3d378885d3764a0a069a0a9d1f5b74bcb14c8ab2cbf0a1e7a3d624049586064f36a937331bcc86de63fcc19a8ac48214e10f5e85f659ab6b4be4c0c29c05ea8d3dfe6b2fda084e22c253848230ffb72a18ad90c09a438cf78d09460fe7678e2dd1da3010001	\\x27ffe615aac17591c9c32c96e8bfad41cb2e1ac9f58632f887105c0f8e11bfa739665d15bdb5595343d4719abcf3ed978bdda83a3b44bf1195f740c89b16f60e	1675976202000000	1676581002000000	1739653002000000	1834261002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xc6ba4a5932428aa131b032a4e50402d6132fc26cbdc0337047dbcd231ccd107bff6799009e186f85e913588284dd35cfaa5cc4e7af808cbf7b4b50650ffc43d8	1	0	\\x000000010000000000800003cd93bf2cc474d440a766bdca9d0aee7a1dae7eaec3d42db718fe76f1ee5417dfc4613d280a2aa38fe017fea86eef5f40b227cd8530b1ec8ff66446720a547c1c17f89f0fef60bddbe9e091f8f93694aca8b8e2ace98d647329bd26294a05898ed6123952d648fc9e75a144846a21df8aae8fa152cd1389eba8704ab7aaeb7b07010001	\\x00b8405001bc766db025c4ce62b5b5fd2e3aa3a9a2ab28c2f6cadfe5dcb2e17795349a5c43b6d253f0e7b828c23eb0aeb04f293d6052490685258b28a9c0000d	1650587202000000	1651192002000000	1714264002000000	1808872002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xc66ab3a2974ab60ad94e65c8b0959f5cf849de3b8bf69274bd70d0f077cd4de8a650b4aba60cee4deeacb257e452eb9197cd72f2bb6ce1eef8325fe986d2780a	1	0	\\x000000010000000000800003c7f2a47a04ea5651196c2c4e8e613cdc88d4636ce7abe922304c38ad58b37172dbcf09b0c16aa08ec17c85edda6b8f47b0268c4453d59974f314f743721c482632bd8d619b52746d4c9ddbe732199efa20bf6007808a1d2623f82306cfc97790edaed9921f26aa8f586c09a112cab0ced02ac35a5bb92c5756458e5a52f1681f010001	\\x1f837f12feab612090af59be5f7290b1d8ae4467447d83d0cfddd5e00c5be7b8ca0d0e9d99195116494cbc27e56315d75de69532bc3f938a1afc3632619c8a05	1650587202000000	1651192002000000	1714264002000000	1808872002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
291	\\xc67666f12563928f736f23c1e9298e5a1efbc3ffaf06132dff2aa7b41e982e642d9f917b8ab5fad1097fa3cc99356fefcbc16713391f8e60c42d7c6c88ca5b02	1	0	\\x000000010000000000800003da0c6411de539d94a229595bc8c654d4a364544171b048cd05a34cece13fea0e1a70d84619ff04fa56657c2862aee597a8e898d44d389a50bd53d8eccbbb36eab6df1de84b8242b4ae4d9232365747fbbfb3e642e6565123cc9081093238fbfb572147c02f4f12844201d3079adabda4c7a89d16e77591fb5781c785b9f25655010001	\\x4178c7e40c55b3cfca8ef04fe7e2a6661c7aa87ac73efa4ef18e7db51333d42fc5935c739c6af61a56af34f799ac9d54c934fdb066c04e7fb9b49111b0f5fa06	1650587202000000	1651192002000000	1714264002000000	1808872002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
292	\\xc7b67190c455e159cf95e874afd9dfa8bf39d25fc174e87609aae691ea3ebc6e526c9de0bfc6d61ad0184e262bfda016a907d4213d0128b5a37f5a685f442a33	1	0	\\x000000010000000000800003a3f63924bc12a1560c1c935e171ba13b1f90b6181b544efa6cde081db8a9ce535379bcc50e41145a6545796e84b70ea654c01fdda99a0432fbfdf7ce4e3636a4b6196fb31cd8a5970f2cb934c4d915768013c576f8b1075b80cd2f7cbb4928a47dfd65aae17370626206d53285c3cc4e761bc3d2d89c560269838aa9d2f4e6a7010001	\\x5045f6e04ec72c4a76f0cc303d4d8d3017a9165fd3e0fff25c50bf44e6f17e13c6ced3208485e07464f7d2d0b7b5877d0075ee341defd928e31cb23b4462170b	1668722202000000	1669327002000000	1732399002000000	1827007002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xc852e9c0f0086278c1c2482ee07c8d1e10e40668a4a9869e8658a2c6d04a454f298f9abdb8413d3ec2d80bce669d52fddcfa595f0ea7af77bd26e8f893da96c6	1	0	\\x000000010000000000800003a14bd72e4b63d66338beb3fb6c85150a58a0fc8071852bea781d011d810fb3f65a43e321382895a9dd1490fd957e600ea5339fb9d5844594f0218afb8b9aa3b64c53dc96d420c0d1ce9db2ee4f81362ae879b9c73a676f66be37650f9f60405f8268570203febba56b37ace54132e7add8abdcf9723a7e6719f4916af2d1ebb3010001	\\x40f80d92816e543e13edfb721ee7a3fb8d54802e559a82aee86ca2225f470a3a26b7e296f6e90a72ff634c5e615ec1d0a887e519e1a092aa78594dabae913900	1675371702000000	1675976502000000	1739048502000000	1833656502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\xc85256106eb3a67d644a340f984bbb73957b26cba7d1d947e0c95a34e506e839550de52a00b7418f4fe9a26543fc660390a679a58593b0b9e31be5adbcdfccfd	1	0	\\x000000010000000000800003cc4c3b1f4598d4579ba26f3c37932df37628f86dfc382e99b5bd2de49eaeb1b9a4a103fe55959d7af65772fee2ec3cc037015b505386beb4bb24f9dbd98127b9d8dabae6ce906de487e8c8d0656881d10c6d6f3a5220f6459dbc1cb0e3a936e6317d0eb34f8e4e11748beaeb51fd7da0ede02bb25e6ddb7c8c5b6c21b2abc303010001	\\xec86c3558d834304bd88daf84856f6b33e3e3b88b29c5b7c09d67f99bca8841fb45aaffd5bce00cc4a78c0f35543f985d0d7a0fc55f46e091da367bd31f43501	1667513202000000	1668118002000000	1731190002000000	1825798002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
295	\\xc89acd85d7f1ef79dd5c8b9cb541888194ef2c0fe0d0d9925c0187cc1cc0bdc397ccfb744bf5dbf7d5bca22bd8345c52d09ba49b78a3a5b18caa272ad7f5276f	1	0	\\x000000010000000000800003c48fe37f66dcc6c0c46c61c41b74379bd3ba6f028307b0ce2fe76faa013d84b01f74e45164cab3aaad685fd6f16283580458583f38825232195fec0460596aec4b2668806d46c67da482bb784a9bfd92cbac88488d4153116ad4c7eba5802bd3b8a0919440e755167272c3d949340988b9a50488c62017c1bd29b57826aa03ed010001	\\xc298297e03944393836a974b928e4721231dd0d1943adca4247e66dfd44b33c0c0697a6c2fb0075c5a4067fe6fbfb78c37f659d148fd31dfa2ffad1858a26c02	1665699702000000	1666304502000000	1729376502000000	1823984502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
296	\\xc96ac746aaa06f96475c15f4f35e1f9bc9a8c4da1345f3e22b312c99a65a50d0215c1882c4fe7fc20f967b4faa3467d110838f5f9de3b92e0f279773a3e2c086	1	0	\\x000000010000000000800003eee4b509584d06355cbf6b45d127abc37977882b03023fddf59a8bb98db4d0a65ac5fad581ad0789d89d1c5d2632f0e19563d69aedd5031a6680e3d8f9f9ad57125a3e00e17aa96b5180df36b6965eb886798f07f7d015a83189a459602cdb919f3d45da542b369c9830f4d51bbf65d0f07909ed47233c1c6cafeed8ef8d89dd010001	\\xfb49470443ca75a288e7275807f22a1a17799b72efae2d8cb71781af34ba3fd1c81f4388098af240313604d38580559e2a61db4e15d1c4812d1cd1ef7c08da05	1659050202000000	1659655002000000	1722727002000000	1817335002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xd01a5a3187f6a863d83c5e3fa2994e16aa0fbbdfbfc35e320b06512732ffef64f497e13ccda546f9ca4d0f3bc322355310db003122d11e7b0db8c4a60ad41efe	1	0	\\x000000010000000000800003d1ba337fb902e13763244b08f87ea7990a0e8822ae2da157c8cb6b703d5b81a82f2491b4649de755a20f41f283d5511b70fb964b38c4d105f48a7328e3ae6a0bd338eec14fd7a8a2562ab807de0c13ece31caec7662a9d4cbd41fb9dedce66ccb69185cf683acdcf7f4dc8456d1c5f4139fb175578c822a4694f7ab78a05be5b010001	\\x02cb34eaebd0fbcff97e8def2b4ef747c8a0fa372aa89e57ae63954ae65c3a14f6b4c906797339d2ed4d2cb31449b747e22a1abb9a04439d15eedcfe8a161200	1666304202000000	1666909002000000	1729981002000000	1824589002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
298	\\xd2ea84f6d7649e64a4a71eaf7276bbafc6bafd0cf6ab538f3bb010f5c99f6b07a986ba78a9ed1735b0880a1692269a77d8e3545ea4487447c36bbb28737e4e40	1	0	\\x000000010000000000800003adec8f76239729d53a0179c55dce9f41b4a877baa78f56f1702876648382e5ad6c59709e082d9622ab4f2ce57c0bada3f3400d593c243736363f807e5762246e230dfde108e2cedfa6330dce234d311b1019f428f2fec17a065681b58b81acf63ac544289d5416bcb91ea4024086e8898927a9c4ff7d6bd33097a871a112a449010001	\\x02a454e58f941108b5cdab1084c15f084781cb7f7af50251cda5fc986c6153bc8304b4c83941f40e6d4b0ecf4677df3faae5dd2e755fab354a6cb853dce4c603	1667513202000000	1668118002000000	1731190002000000	1825798002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
299	\\xd58e6a141e7e32dbd5d1ef3dce6292107672f24543d94301d72588e7477382bec4211da3e048fef47f4fd4d9ba0e5d7d51bfe5cd32d44a420062fabacfd61cc4	1	0	\\x000000010000000000800003c01b3417c0d413b957bff61ca0bd4b1016464916383d9abf82e9b097412193a56e007519df3020fcb8d4bb74782cd0348974e66ae6736efa59e9fb4917dff527ac10721066c0f1fd432943820b9afd004dbc58f0907a18ea50e2d22f9dae366ee4f5433a3a3b0726da93c4850c17a1ece869993c073d914a2e279fb09db007fb010001	\\x0813d227151006582bb6fea54fa1ed732913c1859a8de163e76e1cc561e31c85d884535f2186f4729c1fb607c9b5cb67bbd94551fccc69eb725131a39fb25f07	1651191702000000	1651796502000000	1714868502000000	1809476502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
300	\\xdc127d0082fc9a30f31cc4aab4f679d79d84396ea173ab5f38e215eee4f7a0f089d42384ce07edfe2cf3211ec7a5b670eb7162a3453ac74ade94a451a75b1896	1	0	\\x000000010000000000800003bf6f2cdc015979efae3285536f6d52ff5b2ce7293083b7a29c08172061f4491ec22be2ddeb97ed55b1f180bd6bf3f21c98313793e5eb073c14f8fd5144281f818c773b342042f5c29b1fd910fab0a135c4ee78d808277b622f3327b3d47a1cd1af51cc897fa6c2935a9d2954b3150eafe7b6c73a2a0d54054fc5880c58bc8e8b010001	\\xdbe3feefba898defb03e0110943bfbd7e7f17eeeb2c064f1eda6edbbbfb845134dc7b2ba00c7bc5d7a968b967087d7796d3e0b52cbefb326a6429af7047dbd00	1665699702000000	1666304502000000	1729376502000000	1823984502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xe30a40cb4104aa22d0b15211a154aab551455135e19cc6287cb1a2e7c80e696ef8b24d563afa97496e5661579892f83376620d553dfaa13292c169ba7435f874	1	0	\\x000000010000000000800003d033ed8fb83960185c77ba5374d4c9c8867da1d0e4fc620022640935e33e1f5319b947cd462ce58834b3135983ae8df4a2bda9e2fdb32c06b1ce6421344a7a1e66024304668f1d3fb7494a35fd7073360cfb5671025c1c1a0c0da8898df48bed2533f4c91b7569ee4384ab3e43a59610b4c0b5e7cefafb72dc8e2086284a9561010001	\\xf93c0486c243b7330fdcf60301368320f4f6fabd4755f9d0e8e7ab4985d5a2077280389e022be293b640fe743956ffb8e6fc570d243555f7a2ddc77258ef440c	1659050202000000	1659655002000000	1722727002000000	1817335002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
302	\\xe3e62109e9639eb880d7e07240a3963a7b43bcdc636bd9f09b505c11e2ad6777a6b49d488d24a3932fc1c6de4f0ac855254565177e807f74948e6882653fc562	1	0	\\x000000010000000000800003b069fa6bc97b0a8d46ce53fc0a8d17008cd288a0534f8dff74ce85f440538cbe81462ae8b021e32dc5963a63e8c0108e77e4f909391ee577f5a76782ccb9d6f3ac99af8616ca161f6c6ced301b30a7ced8087e6466d0bc1ad436fcad546893b95b0e2c797bd280b322606cf60a46e7c49b2f176ff94a7947cca2f4b17891843b010001	\\x9c28bbaaa24e50307518f7d065b64dd92517a45841e00c4dde3a453082a0c099893a3bd16f7430b6e66c3a8b50534fdf4a3793781a37b4cbf873a7e24c249703	1678394202000000	1678999002000000	1742071002000000	1836679002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xe3d64cb123cbd33acf8bdd799cec901f7e58a6ff9bbdfea633ff8fa1449a4dfc81b8f53ffac91c1703c94842a0d86f23d84e2095fcf4cf45ab96c6af927fe034	1	0	\\x000000010000000000800003b7b034e41993b4cbc1d5eb9620f2b717289f8c0d21376c5b68f9b16d27192e0e741d4f8b602a8cbbaad5a6e157c7cc46bc1f59041c7d85f2dde2721f53c1b266990a4265295dbecccfc9cc6a66ed5a610fbb5bdcc3f1d903633916a38eda9c3de7179e35b45d050f8f4e2d66585b0c63e2e16b472d51157aee0ee094681bf305010001	\\x8b4b63d4373d9000ff27544cd86b5c8dbaa8dc72adaef579e901e9ee9b7cff7a2030e3bdf6ba401af26579c97378ca0ef967b70d3c3d8cb46f6c7d3bf9150602	1664490702000000	1665095502000000	1728167502000000	1822775502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xe4f2f4de7a2ee4f150252ad42e3d80c083d3b747175dfce5c629d131c725b233d8eece050fbd2ffc2cd3cf9a7015d21dd64264b6065fb327e81a72b1efa2c4c7	1	0	\\x000000010000000000800003d1f43b3228ff7a712717208bb6d51b2a8e5a56d98ae6d94235cadedbee47e9c0453b1f8cfd217cd00087027413ff083ddfa3174e7b9cd7756b744dd3dff1a29f8ba3a498b3796e1b3902dd17117727391d7c3f23fde1516fd8b0e4eb6a30043a9f58756100c0bc39f3206298c264a41ec4b855f817cd1930856ce67b179957d5010001	\\x924ae4e2aa5215cb45ecab912b7746f51214a9a14664d725abf3cad74c1759b73730a9f6cdb310285719ca3b3296a8dd8b353bc8bebc9947c42f0e38c6d14508	1658445702000000	1659050502000000	1722122502000000	1816730502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xeb22f77d03f49defce9f22a62a2f3eeaaf1689bdffcbc5adc7b5d13c3263c7d55f9f1edf37937d82c0f3f0c3d9343e4fba9fa7c66996e99a33ed76c36606b261	1	0	\\x000000010000000000800003d2b573042f7aae3ef91b9738b7bb887cde2faad0b696b21343b47e9e06a3cbb2208b103e0d767fd4cad61e8aff9eab6bb0bbf0a9c002b010be4ecf1bbd7918ee7d5e5137bf7df0b2ad7107787c3600a13538ea3f7fc2a9228456e3bb89fb72a957198d3569afa158427cbb1c9b5ac315fb981ea6baac95efb77d805ee4afddbb010001	\\xc4e085089cfc2c87ff4b93ee720c386d588d663c7376d9701cc2ef940dd381ea9e22a57991ccf6621b23d56511d66d8f53928300e8d587cc6f35e3d363f45002	1656027702000000	1656632502000000	1719704502000000	1814312502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xed8e8656b608ea05c149ac0873ec03b196cd4fd442396553177572fbea386aba6a311887d351b62c1cca1d821b6c5087c096ebb0beae925a211ecaafe3ed92c6	1	0	\\x000000010000000000800003c12a642f1a8117f30ae193dd25689baf9a14f3fe1be15512ed03412b9dde051691388f42279d8a78b7eadf5b81cc053c12f48cc69f689e1b3eae8dfa886775fcd3cd26bcee4928e8405671fba28702cf9fb38e96d193e05bd1432e573f4b6eb858138ce257080f406762613411f08f3597ecfa3088a334ef514c4d1cefe0f5d3010001	\\xdac1a385268671a1a641623ff7e24389b4fbe3e0add798a5fda19d18ff1ffccbc1dc24e5af42044a5e1fe08adb0d9b7ba0d9f138b295f7b0221cfe5679b91000	1677185202000000	1677790002000000	1740862002000000	1835470002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xed52d3e503d378e9982889797603b7b2a3edc1d7b3186f212b6de3c201420874e135255a977cf05ea248866534244996ce97b5d274c6551709c1d9a3330277e6	1	0	\\x000000010000000000800003c96509afd05360377df2dd2627a2d696ff4413fe865eb1adf5da6aab19ee9320e536591d382b043078546bf81efa71c3b215aac1b136c7754cab32a297f3404c7ae20bf003266a62f787006ddceab88f9e6768c98d33a46780323a76c39b3656d31d86cbc863fc7e512283874a3502321b4a496bfeef807813c56d864692ed91010001	\\x6dd7f6690c5dd2e99f200ed19139c48ab6c4453fb405eae7b54bb5ad48dce231738b55c639fd80a7975a156e687f1ed0939f2db97869618aa55f9fc1fc49dc06	1663281702000000	1663886502000000	1726958502000000	1821566502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
308	\\xee025a15c0653480121356cb5be5ac494571a698df06102046e12fc7a22064bf6a77dce2e377cc7e2e09bc3aae98b7758b146774e4d292ff7cee5b1bbfed4a40	1	0	\\x000000010000000000800003c54eef9bc2f9dfc241d3abff3c0cebadf5142de089a37d3462abbcac2b6c6936ec9c9a51324abe21ed1a34eab2901188eb0ed24169b31a7de84c9716d457945e8f284a0c05b276084dc11015b0a22e88b46d30f18645ff26935cc12279039d6a844116cc1e21b2794747a3ce404bc81a0690495309f035fc035fa247e71b69a9010001	\\x10820bef8c8de641761d778740a0fb99f35be7ee358f4f214bef8219892e7b468b8a1378c825e6f2514e83f90e777f4716afaa5c7f5bd00704a03b082478e60b	1672349202000000	1672954002000000	1736026002000000	1830634002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
309	\\xee724c74bf676405431b98cf750fc0d47a73b7976611831deb2c169af19fd7988ed02109b88ff23bca587309149df82d03dc4398b4a55bddaa331500ba0ce284	1	0	\\x000000010000000000800003d47bae9a552671ccc0bbdbd7b6459f22386daa5848e3b97ec879ebefc15cc4a335e6ea39597a94ff9de6eb4e4238797fdcf37ffe692dfe30efc9452ba9cd3fd2c855da81715f75b23afffad48eeb5acca4c73e5333e88d0461f5ec6fa4e42f1c59f8349c2726295ffe680a00769a116e876a0ecef695a22478ae12d240740c43010001	\\x10746bc4b4030775d501a585f398a5a49b36f564538d582e7cce649d3b33f959838bc58f2aa0576c5754372c7cfc5c6d4a118cc61e1f9c3caa78eaf9c2b8770e	1656632202000000	1657237002000000	1720309002000000	1814917002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
310	\\xefe6538caca892a789c2dd5f36e17084a91f9b7568e4c9c708b9644afba5633f6475e146026b75c391e528b8ba6f3351ad07837e5cde0c30aa7b715101e44799	1	0	\\x000000010000000000800003d7085253d56b78a98ea44d3acf5e9eb16b3484ee7908443aff5580d74320fb4daaceac8021ba4bc4e0ec44ad07ee2430eed5a06de3bd5e060f6a4779973da65807edb0c1513fa9c650a7ee6d0670de23909e0a69d64ba939e8d30ac9fa52fadc8755e712718bf918745194b6b0e11981dfe27a393ee9230f2220f839828f44c3010001	\\x1653fd689eefb9ea190270828428ad7c01343af5b4bc37fa85c6097616869bcfb347d3c5899d5ae4e73401fc6aec87b422c374d5d2f7965d7cb50b4e9a17e203	1675976202000000	1676581002000000	1739653002000000	1834261002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
311	\\xf0064e38f8004156b3061d33f26217a5c075602e1725f71634d553e3ee755d0b7c66a433ddc08848f13ab0c8c0914fd2a2c54a8d2ca864ac792cc3a10fa61642	1	0	\\x000000010000000000800003d61c073c8cf3460a7f1bfde4dbc2164224bf6eb4875c7b54de0702a1402e22b67df203b7440cbcff35d360bcfd2521085e63bfdc76ca35c3c4e5d64c8cc5d4811a8ea5440f53cbcac3282a9f3ede8cee0790063424a35e556e2ab40d00ad4141215e914a2e26c26f7ea08cc303455719e2612b746f33fb2546fd435ef3ae2a61010001	\\x6ae6c7696d618323d026493cccc79861dcdf830b1c718f2fd82be1d7b28459eedbc7dbf7f6a73770cfde4567e2d4d10cdc582e23f01dda42897b9f0d5e6b710e	1670535702000000	1671140502000000	1734212502000000	1828820502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
312	\\xf37e5394c1c96431e830b3ebd928293f1d8f5d5cac74ba2652cedf702c1e8105340e709fc55ffa28347b60f4a82b3fb14420e67bcd7616d036118264f7ee51c4	1	0	\\x000000010000000000800003b668bad36ee17e1e8af96f6a9e3224d30656438f47a84f4b6dc23eb9556034afa958f2165ae7b6cd129ecc9b2fc54a771ad8575d5b7fb53ccdd7df8b5c66e404af284b37f680bae0d9d7ae919127f5729b5b5b734533f28d3a5b75a4068798b735476370fa2432844b824e04589a5a5c712068619e8f1cfd1b8865f2388ec8e7010001	\\x04a063f9dee15eb993c424616ffd8fabdb4401395a1b8b1c49503517b0782d736dab1c94ca132c073386f4ecc64de2541ddcfa809030948363566bf3ad95ba0c	1656632202000000	1657237002000000	1720309002000000	1814917002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
313	\\xf4e66806a1b392c5b80bc69d2fa6a587166db2feb4c0dbe73d3b9ceab5c3f05e8949e99f40ea99a8075ed912afa2fec4b9a558b5203c36d38dbec4e07d95e3e2	1	0	\\x000000010000000000800003b3756be0923bbef003f741996c69acccc4884ffe241ac35ec2ea26867d0afe5a6aa56e44ce9470d455c0906babf6b5739b53d8b9b629ba81c67b6576bdde06535641431c2ac0a479f7f9596fb81adbc82a664d7445865bf2e63cde2b844ebdd6b890bb71b2f514bb53237725ab3954955c4becaa27c6376ec6fec9a0dd89fb0d010001	\\x6a4443cdc0d4143bf643b6e38ce2253c535cadd61f8926264191a5e2b6dcbc2e5ff81a812f36879720cd5524688f4a1a21f4ff421b7a6a06cc5a86db7fc25d0b	1649982702000000	1650587502000000	1713659502000000	1808267502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\xf872a4224917ba6a56fab026ceded3cd48b609a9382f92f8d58d9df9d73613a905108bbd7b4ca06b59a3f9c7631316c155b8a2bc2c4d32cca7bb8e979e6bd79e	1	0	\\x000000010000000000800003c468b0b4299054a7c078330bba60bd97e705a99914d995a83ab65e0a4e9a88d7f934864fd75b6b2d5cb12198174a1477aed892d598f58f39b61a6b1c478af6cdca180aadda2e8714cb9482e15f981345aeb6a5555bf9e1d3c771f5fb1381ef04169d0cfbd65d0f25bc95fb66cd326fc188f2a7d713441651c5d14baf9fe6f89b010001	\\xbb265793811502c71ada653a13df6c3aa8dc56e3a5b1f1a0d0fc676466743b6296bdf6d1374969293e5916e6459cbe98357fb75a93fed1bc6997b136b5cc0d02	1648169202000000	1648774002000000	1711846002000000	1806454002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\xf9ba82a70820f594c47eaa4fa011649138795a040e8518b70031a14d65fb64269aa3cf86eb83a40a0412c61ac398cc56dc3a646061a056e8487c5a33ad8085f9	1	0	\\x000000010000000000800003e92e6c900f44314872d80a16986da10ec850dea2a9b61900b91658a92665a5fe40389dc49f0619f55ec276e98101f86dd17094f67446d1987028df1cceddb83463f3e5d1d82997b436db5d4b4fadb42e94227b0f91da0194fd630dfb4f92190e490c9ce9a3a7c192f1688fe0ea8b92684be5f40fc55c35a1e59ead1d8b9fa6ab010001	\\x2766f92fc0d732d23f2db0088d2445da8bb8a947af1a92ecf6f03fd912bd7265e7db5ce8873d32b11e4d54b17274e544d4f21ff286b5c45d14b4f0bc6016d602	1670535702000000	1671140502000000	1734212502000000	1828820502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\xfafa540e14a0b57ca0068a922b25f6a2703320db2b3bc9dfb7d0340a7182ba4f52af89440e394d64c79d73efe68d58fb3830ff0de8a6f63ed7dec9762b17609f	1	0	\\x000000010000000000800003dc8cf98e8b4556d369664b076ca514ea194a1cd052ad91fa5d2ef0d8cf0d10ee3e2d8b6e0bc3bc30c5837b6973d72196320691990ff41b91a00ee5ffd3f47ac0cea12ffac4a00b94dde9996696063ff96a1b562339420d5e1359271bb059a74ce19d95ae8ca1ceb465d67b141c704c317388ef8d0ee4f906671f855bda420f61010001	\\x635ef115c15317444070d252a0b5b1b2e17bccb2ab8febdffb5ee6f2edac5d3e0fdff52eda5f1b627c5f6f699dd271e6a7bd84fbc0ffff8e4c17007badd59705	1670535702000000	1671140502000000	1734212502000000	1828820502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
317	\\xfbb22fb12535591c5b856ca73a6a2ab86e0006308848789feabfe1e08a594cdecb056c9813286e13c25e8c2cf41c9748f88ebb4281d4f8aaed4611fa11abc235	1	0	\\x000000010000000000800003af0fd58c8998114af1b8d6d99bdca0f0f8a1670b1364637786a75cc903c710667a1d5df5e597dcf939926168aa881c17d8fcc678bf515d27cf6bc35d183ad50ac1127557eebb955dfe99c4e70e6b46e9394b0afea4575b519fb35c3f07946a21b15c619ec3561d6dd31b92e2c656bd5faab27bc8aacfecf494216f7d831bd61d010001	\\x3800d3dfbacceab74b43af47c6eeebbed3f587142a9582a6f6a9b7d69c911d342a4add08f35188b986a97ddcf66f45441b8f893ae8437f1ceac5cda1b592c305	1672349202000000	1672954002000000	1736026002000000	1830634002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
318	\\x02779bd04d7dcd5cf88a739f8c548783d79e3fb2328343151b866204b60cd89450a0a0e99d0acd7d6a5c2ee10c75e2b64bd2db2951264affc445e2580f7d9549	1	0	\\x000000010000000000800003c977714fe3585954bf2573e1548a9cc1a64b0465fd3f1d6738d3f8fd828297c7a51765a6b5e17fa08e8ad40c218036f6feed10de9b8443b0b503926f64148378eab2fe56f1098b4e3f375f1a447e84ac06a36a468848ae16a7cf37728193ce34c1c34718a623b152228756104842ab532914669c4494e590bcf374cad57e27a9010001	\\x96eb5bdf0f9871f1dc3e97ea9c90bfc5122fb8d3ebb536ceacb5d26c55bff887adacce00516a5a3ec8aca1dd1130b8eaf7fc62117966962ef1287b2b76c81a06	1667513202000000	1668118002000000	1731190002000000	1825798002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
319	\\x0797fc7dca8b7734a68aa694d58076d02ea72835ee5f12a1161174c35f172219eb1418461e910daf5d6445922d16e2e8ab6b9561dc205d8d61fb5b08a246248d	1	0	\\x000000010000000000800003d611ad3a3b17cf120486af770328b57286a404645cda75ecbc46ddd475899c0bafd461849fe3e105120baa18af34259f44ccc59bb06da93d43d4d8400bf412caaf9bccc1471756623c745c88486795fd9ca5be4831d4576d9f15ffd8c741be54f7fd802f70c2fe146e5ccf8f7c88f28bbffab5085bbd564c9daeea307401b8b5010001	\\x8361aced4cf5499cc3bb90eed8af69cb45832232626008b2562aa9187b4c66ee34fe2bc121b8a81b64eb5b18f55be8910af7df39a4e77b4ccc06c2873eb2f805	1677185202000000	1677790002000000	1740862002000000	1835470002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\x0b7fdefa08e72f09186c7ba3dd0e9703a3c8b7b50866a1f22d007c9b6ef379feb9529a921e20a044471a26b6ca70c178d9d368950d0ca162071ca5ecde672575	1	0	\\x000000010000000000800003cac4e624d3498bf646f1798a3a68fb5e8fa91f531e77ed256503f5abebe2c1b0c11ec9e02cccb47a5c184ddcf13dbf8028975ac653c0278f68623e7337096bca2de66f34433a69b5f6b2f8be8a3f345d3a03a0eae6c4f3a3da8c6276460ddeedd9f879fcd1a1669fa6b223f047370ad35ee150a15905d5db97e48fdb080a6b4d010001	\\x85e920a04d3b527b2ac7bee82be5a304a4c4a738f6ca79767f5b7feae27048554a8064cb3ce5a32db1135620254e29229b8466c619ac358b16bfcf244f18310f	1649378202000000	1649983002000000	1713055002000000	1807663002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\x0c43fdbbf47d65b032fa1cbcbe2e8126b3bc70bd8a020ae64fe782312858ad1b1cd67c2b2c8588b2a5c885c074a2f705994bd5e9d033934806606eb4ccf0c6c5	1	0	\\x000000010000000000800003bda5c56aeddd9758fb2e31eb194feafc8479b6735499eecc4412841927a9300681bf4e62e3f52e38b17b9d16f1b643c3df3135462cfc187ebc77859718a9b30304f58003d5d99787fc372f04ec6eb0378cc387f5823db696b377f31f92a134e9927bfa3c6ae35267ad8c0521b73e0b62cbcaa9deffffd4bdf125676c41cf57f3010001	\\x8df0101b4b61d8edba97bc2dc445bc4596678fdbe4df0de6231e3d1c3779c7cd2227cc7f8646d7259f97dbace8591af8145d788f0b7f737ce80e1e1978d1a903	1655423202000000	1656028002000000	1719100002000000	1813708002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
322	\\x0c3bf1cd329c63cc37c84753a61bb482ba0f0cc30bdc3b6365b6d9d24daafabd0e4dde9423e19d76c023ddff8d948462ad714189d900fa303d87378f9e253a00	1	0	\\x000000010000000000800003aa8e17e7d7e1fb5e24ffec3824fcfe9a729b7cd48f14f1a5b645686286ef84035081e3e5142353f504b6b83d0e92e887eb104f609cf6800194de30b926d3bbbb4fcb7676da5ff6935ef9a00d50b1dd14eda3e5b9e03e653ce7161a4756abafd17ea102695f25a6ef60f9e5c2fdb11d6ebddbb557e915802160c4ec552f65b94b010001	\\xda5469c5f94bb1a36bea1344bb92ec1c154e3828152b8054e3740fec41e0d0ad550ee3f9499992b1058f7a4133fe1d8fdd9c0bc9b776fe5a5b9ec25030f7e10f	1650587202000000	1651192002000000	1714264002000000	1808872002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
323	\\x10f35e3b2abcc1bd130b150c2f3ffa9490c5f9e23c1f067ac90d58ea3bcf8225ced2297142a12e3d5d946bd217f9df87b0da269f1082d2ff7d33eb75fe8a8cf8	1	0	\\x000000010000000000800003ae2497ccc83e003d3fe79ffebddc72fe6a585eeda6b413f736cce6a6276800baebe7e1d59594267656da14b95013b6097a72de07486041277d155b73bcfccecccada32a61b0662570660c9d4d5988c618d24a1a8d42b97d7943a02786b94af42eaeca2925c48fdaa05ce06272658d3eb52e6d22457c607e00b0f42824e6b88e9010001	\\xd240a551f73b70888dfd6a0265e11a2007363baad1f075a4f7ee4992c77a0e63acb167942be9c2dd4a5ae6a7a15142675c3c6ba8db44d724c5e53e13291fbb04	1663281702000000	1663886502000000	1726958502000000	1821566502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
324	\\x137b6f67351c4c2ea758839de978d9f1989800e50082d1503d336a7339b96802b4101ff62a3263d747dd24607cf1c0b400dba86bb419219b362c2de9be8f0a47	1	0	\\x000000010000000000800003ebb75ffef937a7565b497b8a1a1e8ee6983e52cb1ad9580e7a034d72018ab74225371007b712a182397280b510b63c02dc4f5a7197f0f62dc18a84a3f5d36fa5f3ece05ad4d0d35eb46a5ad6d4643852965bbcb9e54da7a4c4b480ae80e007a7ab0376d21aec4b6df5345a3b9259a6fbdd002aa444acd9690cc45586879e60c9010001	\\xdd437ac286f02178147caf46c197f7b80d1f0b7fbee41cc7a5b5050fdcff8bc5ff6430433eda1ff4743e733be09a524f6e469b5d43c3064eb996a49945c83d0e	1653609702000000	1654214502000000	1717286502000000	1811894502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
325	\\x147354451d2167940348a112cb8e50ad9cae5f7e9f7496b88f5b1ddc518773d9a11d449a1fa00951d90c5e60f7141815a4fcc91f1402df7d0290bda0b05876fc	1	0	\\x000000010000000000800003e210e3ec748bb334374427df55d67fbffa50466767d35c0600fd9b75edd8666bdcc308208593c300cf7d5e768fd50770875f77a83d492c530f2d18dc9ae9c7d2ae6cba29c2a4288c13fc4a1fbb1add32379f4d81042efd3b8e2c4caa1d7160f045f2de57691357004007feeab281759a24f77f9f9cb96910f04f7fbe11699e61010001	\\x7f84117e0a3864ad0ad26ad48bb199038941386181604e0cdfd226d92e347110bb7c5a45aa6f3cf9a80711b43b077654b3a61706281df3c26f3fe237e3b9f000	1654818702000000	1655423502000000	1718495502000000	1813103502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x171f32c321b94cb7cfa8bb5f42bcdaaeb97a4744bb94fee25a5073f6a294af6442ca67bbe46fd0ee257c8b56ce702f38551a05765fd28b6905451d91d6f5f583	1	0	\\x000000010000000000800003b9e94cec6ee22d6ce2017fb2b7f5c2c82eccc37ad6ae1c62e7e7e1e32a5a63f2ce5182f90335e60989e2cac9e4c793ac993363654c81b7c81296be88169d6afe1795adcf1071679bea9c4f6f7ff3c097729c01025dfe85ac86c9d54944e01fe4b7151daca90b14cdedddce35fb8253e73024de19c60ad437bc0e950f9c1654ed010001	\\x4249c96ec1b35822a821b7f1fc17acc0ecb429db7f87f001ca81a29cd826f5fe9c89b25e9d14c924d05d10b3335f9acc1c6905fea7811f6bdccc80de3f4ec600	1660863702000000	1661468502000000	1724540502000000	1819148502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
327	\\x1987186534b075f65261197753dff002e8f3c2de8d5a7bd64e5af917fc185936ededa585659a5f3e52fd8134f926d2a92290db99f6f7a447a270b91620cd666c	1	0	\\x000000010000000000800003ac1cf38de24881a76912820f2ce107c77b7f3f503626f502a9f45ab11d24fbb9d35e87a8f69dce642bed5bdc05a6fe12115ef21228e1c14985814f89ffaafe6e1eb803c4650f94d8d9f19712aa761458bbfdaeb789ce48c5e7a5ba726f5adb98066e5da2fa14d3d5f3356a727dbeefcf6e1c373a1b47211eba0f1bc286146209010001	\\xbb2187ec661ae22238cdabf6bad0068b26f268633362205b4386d082ea4edefcee36fa6bb13f2b4c803a83bccfcaa8b7c6701ca937dad38e643304f29bc64403	1666908702000000	1667513502000000	1730585502000000	1825193502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
328	\\x1eb3e94c2f1fa6543ad8e50fe1ca8d53c84ff8facd3c02cbbe89be1d7c1c3b0775e13239205b96cb72dca6604d2c5fd29e2f96ff206ab5601f9f64bab296087b	1	0	\\x000000010000000000800003d174b066eaeff8c30431373ac80602fb5fa819e7387d324ada933dfca906343e193019d32bbdf739dde9029a05aa6b229a546a07c59f00679396cce9bd1d095f9a1cadd4b1855bd89d587d2a0f6dacb73c3d3283f5aa579bdc20729fba1a92bd574d907afe91867dbd352bfdb12a21a9e7ad62e8b195ebfb9be9a7d979945eb7010001	\\xea825c13c467b6c6f75f5fd156b731bdec86ea4c12bcf0c6710726c0e9e8ea54e1d297a6f640998f98316d8cbc163d7a7d88d445b3673157cbaf697d63f4c60e	1676580702000000	1677185502000000	1740257502000000	1834865502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
329	\\x259f4c8653284da3bfddae3180838474e2423c79bc53012b105e62db4591942c71d2b0d1119507272e0b399683439a30e3b2b9eb6d699e6a60b88bec4ec5109e	1	0	\\x000000010000000000800003cc58f5ef9cdd57c0a39ad8cc6bc2bcd796f6bd63ea5bbcbf5c8c74fd99432b8e634680f6638147b3327c7632de3b80642111d22e30399dab474dccb7192d3fc33fc681e8ecfa634f2f2c5134b3f8937c05d41f41dfb717e1236be3111b61269d7a103e1719ad68e38152985c56440e8effeff259016f9a3783d80cebef479961010001	\\xeb4470a856dbb32503bd0fb5c9e0595e111722bc4330bd43af5c40895faa7fc63ae83a96fb8a4b4686a2d72a5e6975c696593556d756084ebad1cdabc44e3009	1675371702000000	1675976502000000	1739048502000000	1833656502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
330	\\x268b15d9c32033d721acaa90cb45402395ce6c037eff36ad966cb1555737e7148ac4d608d715195921f948af0e9ee988ed6c7c8e200b1e443821fdd7ecfffad3	1	0	\\x000000010000000000800003d1ef94b6324f0316b021c30e6a1bc815de13be726084118d4e733096f8c573e74a00e6d699d6c8319cab69c7ea3c207f8d22eaead17e5b74035a22aea661fd00d945072e60ffc76b998293a5f8442a08da463028f30e4971b650f1f96d042b98f4065ad2475adfb339334869f686ffd674cbf1a44010dff80662b79775ccc92f010001	\\xb3a10d2c9dbd355b4b6fe9394baaaf39906d58305a2a6eaf09b3dc6f1aaf5057aeb356ad0282fb6b9d820a4988a4884fd498d24735813891c786e38eb975af0c	1676580702000000	1677185502000000	1740257502000000	1834865502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
331	\\x27cba18eee5264cb1fe4baafb744e92321da17d0250475eb02ae4df0bc9d9b2e4cb3a5202524a1103b72b3faf840aabf6a495986540e2063e971783b66847b93	1	0	\\x0000000100000000008000039da9a02613051944a52ab7ad32cf270c1f47138eca6f8d509c2c2555d64229f44004e09627b53f22f3fb2a4ccde116e682e4004b8570bb77cdf2dbbb58afc3d2d543f501c94bb69b83ff86c0d9a93bae20f944e2a70af51317d921f302fd87954a0f6e6958d3a7c22ad1f9e1dc79bc5c77a18a5c1ee3ad06c7a843b008b61bf1010001	\\xee252be53fcb8cb0d999c88601cec0f55a2760d50c4e6d1e610e09f7823b5ef55c68a913e6163011dd4332eebadf31bd6d2fc7cb55903f5c772a3357592d2c0c	1669931202000000	1670536002000000	1733608002000000	1828216002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
332	\\x2b376500d84edc60f23674bc06f05730d731597d9ca59c06f38b77e968a630ac14691e9198e3f81d42d5bfaa42d6c110d088dc72840a942369c25426ddcb7586	1	0	\\x000000010000000000800003c752e8b2aedbf130f5ff4eb677dd573a3c372f90b921d4a69605789421ec61185edcbc888371bb119f49f7ef30e601e6cde10cd99c229a38aaf40baa8345208895be75fe31b78560c2218a9a7e83cf42a53596139cc1c6aaff526fbf11b81ff656c62a42145f41fa64136a879e7aad9e7e85ab1aa4df8a424c804d187ddbf7d3010001	\\x5fe9bcb8c91c9f43caa1ef2a3029845c296a9eaeba55ff9a91c2f826a3253e8824d6b0aa2da0373f3b688858a17d02cd82ad6bb940a2eb8b9d4db8d17932800f	1674767202000000	1675372002000000	1738444002000000	1833052002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
333	\\x302bfee7b53be06aa966ee330743f7512b04134c930e2963b487820e323753f1996d91e8cb62168d7164eac1da3667f4f45185cac60d6c37b6ecabd4d33f6d5f	1	0	\\x000000010000000000800003d489d07344de0b87fb9e7ba1aa98279ec324bbc53ebc2408d19d9146044dbb4aee027579e8ee0c64fb4ff08ab9ee6eae223c1f99c3129a78fd85c60da7585a2394c3a17bd85bf3799ece6c5d0af42c08fe399a3635ecc93ad924fb4349d9a7dba78d216c96fe02866ad1a19cb79198fa17e04f1aa4e698df31f6cedcc0a284ff010001	\\x4a0f4283efddb8cb70553e17e48b95e7c9637cfd10685c54ffc25d344961803b7339a79fabb13080d002941898d35c865b0d16aabfc16ad0717fb1e68d2bf305	1676580702000000	1677185502000000	1740257502000000	1834865502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x365bca639355989421ca03a41e762f5d3b22da587cb73cf4f2d0ad485e05fde2e408af765d0f779622699e5bb5bc5f4991b02f824c1032854c1ef3fd344eb9e8	1	0	\\x000000010000000000800003a6d66052faf9a1efb33e570509ca712468c440c4dc18b10e297cf62caf40f3cbbc7457efc2c37fec9d01a100c514f5e324d97395e9bb15acd2871336297ce5bf461386fd115d3dacdb6cd828e715d903623c394242135154381ce9cefa848f1714648df7ed82488117559e4d04b9eb6afbac49727deeb7e2dcbd0260797644df010001	\\xfda5e86f30808a8a8e55f5812fb464d55c6e2760185afbd54f619759578e20df11830beb4683e9739869fb42d3bb4db08281a0c4489492fc8635a2ee435cd50f	1651796202000000	1652401002000000	1715473002000000	1810081002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x388f8d4372631121a02f1a4b9923cf19de3a469c6072406de71b9e15e9ba0c5c44c5f905f7ce915fdec1e4a996db72118eb723c50dfa9d8f788f7adc211aec82	1	0	\\x000000010000000000800003a95e77a5e092fa16ba47ea9758b8f6e288c8741508c8580472fc40437f18c5f1f7faec93e4dabe2dafabab75253d87a957a530849c3c1aa78bd192cae92cce88cb37e5562c067e698929672ed8f8fb894e474ef1fbee92823b05814dbee6f23bb3a1d0d6b7f0d81d79b71caf6dd4939b30e9d74ce6f6c5caa0c233dfee2f0f99010001	\\xa8a8a3918112b6a19985a24927cb0394fbf49d3a7562b77fae361cd7a0b1de6e334bde12cd6ef785ac7eb10357c00bdc43c90a9131a18a32d2470bebe64a9c0f	1674162702000000	1674767502000000	1737839502000000	1832447502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
336	\\x39d7bba4886897a520380ad1a1299d3527d4560b04074ac01136c67aa40c232e2cac7d9ce26868867a993eba6fc9b3751587415fc15606d9aac1329b99231b31	1	0	\\x000000010000000000800003cbb19dc8eb25b2aaa86026281076c54403ae264279fa9be3d8de26d9de5980d7dca7f0393ef22c2c55d64d09b3df3b4f671f69854c6695a8bb11b537f3787d784b5d0e9011cde005bc9e0edd5caa52f0f9906a1c8480059f3327bac3aa067e3012edc71dd770610c0340800e618439054e9970341ffbdaf39b04753a7cc76b31010001	\\x8df8bc1c2a22edebced04a72c8bdc9eb76cbae03d3e81d412045fbeb0b4c0a2b09e9957f3e88310cf232436c46be66a891f13b60945311c7b4d38eaa22aee20b	1653005202000000	1653610002000000	1716682002000000	1811290002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x3d8363fa6b0e2bede66c5bc15db0aea5b960a629ab807026ee54ad2a03127dfd32651c718f77477809cef5c90ff56fafb25ab398dce5704237178cc2e6d8ae1e	1	0	\\x000000010000000000800003d184a2f95280050f44adf2541e72ea049ccba67efd44bf186bb2612f1b38166c74dd629e5fc001e9421f1e52831b1678fad94d0a709d5623501e9e2a0cf614b85393630640eaf13232c843128b8f2b955d67d04efaaea7477f539858cc15c64d7ca0b289d6f8e2810fea237bdce29fdaa25977d178b728bb47151318e3fcf313010001	\\xd086970aa87e60f431e99222a1fcc9228f7a931f88204635dae2ca12623961facbce6c07a08fc3c6961935eb5a151dd44fc152319bb2d7dd35b08333f3b5ce0a	1666908702000000	1667513502000000	1730585502000000	1825193502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
338	\\x42effc973efa414649b8ef2b0c7971b30ee760b7c5b7590ade8de244e744c2e23431cf626005f14639c54705729eb20736c44fa929289c50fc82fac3ff72176b	1	0	\\x000000010000000000800003d0252a74f35622ee9cb29083c75e14997bd7e448929a4abda3cc38f846729418214a1d7885f1dd1ecc352a5688b4d65d17c7559c67ea3ca0c65b7d1302a5d0659dee164688b9318446d3ff2edb8368b7c370cad82f25edca96be9256b5f621ce1fa1015dc825c9bfaa5893dd9943c0bf69fdc3244f3e3e960dc9514d43cb720f010001	\\xa37766b8c7712af6c2513b50a5444b629599020eefa048d5a25964c76dcaaa7ef3e5daaccba571b66ddef13e34db14955e41740aafdae4816376abe7a8e0a509	1670535702000000	1671140502000000	1734212502000000	1828820502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
339	\\x43bfbfef223dcbf3e1d5dd44fec78f30dbe18baa2a643beccc052861a7f8154231e3bced14f3326d324df0c9b219b4961e06acf87462690265b87c32ed8ebb11	1	0	\\x000000010000000000800003acd9ce228612003af5f95cad52ed28d779feb79de3486a1690036c6003f49c234432f7b7beb69d3d902cc738c729ae093b973a34d67f5013f794eed2a24e89b3c026fc17a462c9d52864d928334a92968767573eaf9f6deea272a62b3950348591143af516c56e7ddf4ea12acf863adf5fcb334484a7c2292ff6637a29991875010001	\\x91c19494969795d8477c1d55d45570aeeda4545a72b0cd2d4a8278cf714a19cded80428188a0bfbd335db0bc56197e7fd0b074c56b9fe697007b257f771c8b0b	1673558202000000	1674163002000000	1737235002000000	1831843002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
340	\\x49ab444487bbf0545cdfdb96c4f7df1eaa2046b06d594dfbe445ad686b809d4e6749775f16cd8d6605b8843a85bfffa2d6a86fa72c960dd565287ddc8ccf19ee	1	0	\\x000000010000000000800003a14c283f4f59a1644db0e50a55ec2cfa3620e2880003abdc9f1d0f6fc4505715abb260a98dbdb154363890ee8b9a474e0b51428d817a5627ce4b88e22c6b7f9fa420a442dc86f89d78ebe2e528375bf15c8b740c6b7f45e7203a1d871ebcbf020d3bd26eb9226699956e1d1f395d2d20afd741d784d320aaa4ec5a76a6f0e6b9010001	\\xff2678da0084e4c7814d0ba9ec4b49ae2e1901884214d034af2c6ac1329773b489fe3e5ead816182e151a6f7d37305e43100f153c946cfd2e584f852b5ddfb06	1669931202000000	1670536002000000	1733608002000000	1828216002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
341	\\x4937bda18d81f8312b5c3a297300380e7f396b93b88ab6373b9174ae0243841babb6979568d726f5d185dab7b6468211dcce236393122f7c929a7d6fc7f8f781	1	0	\\x000000010000000000800003d25c32a473a66b442e1bd1a404f574bd487358f524f8c105f489acfe4b57bf151026fb28437eea304e9ff162164cb1800522dbb2bfb6fdbbd2fe3b9c65e555fd78bacdc0b7bf66e3828f721969ea9bac22baa4d6bad6132de894cce939f0186a4e21fb8b48854108d302ff86920121480836970b7d89f42dd4bc65dbdf00c2fd010001	\\x4df6e1edfbe4162e4fa017f4e0abf1bf0b7a55b747acdcf8ae32fd273d2856e7ec62c0cb956e55379bbb6ca6982b7698faedaf45c3374014abbeb43c43e41800	1660259202000000	1660864002000000	1723936002000000	1818544002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
342	\\x4bfb21a71e1470c9d07111891c2f1d91eaddf9c44428815247e889f16c07058bcf43f540ef33731e1aade012dc7b35ed1ef5a1876ee07cc098399235beb7f10a	1	0	\\x000000010000000000800003c849c982351a79f64d80da78dd81b474c604d0f445f6ee5249131c10ae2f10380e9b8bb4129754a0831f60c0d616d2c8b11e80f58a9ac35520875a0b845d810d20af721c84680020f02d4148ab0b4935887b1186ca2d9472aa96cc7c73c43a2f8791618e30a298bf8a79f998d44483f48f7576066a78ad777d3839ecaee3f3df010001	\\x0eae63875affd26da93277c182793c8984da265373464eb1490829dcac0a4bd7bf0d9c55cf14f16f809133dc7589019f3e54f5711e34b94e4663ff987fded502	1652400702000000	1653005502000000	1716077502000000	1810685502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x4c138be5c9022b2efed80c06fa9dcaee1656a9b789eb14d943b78c53c6a834a44e589d37fe0c6abbea33929fe245871b217324e20f4e1e7f5fc15c9b6e573a59	1	0	\\x000000010000000000800003a4db40f6dd3231c58ca0eba883b27c5ffe136919bb4cdb88bdafbc8662bd2512a02741341a95af4e59761feb0f56d4e57e21bdc61aed9f4be4fbfaa19d89fd2a89cba302cf2ef81ca5d437c3d214c50843d226bceb014a3d7b64f1f972d6a5da03b21719894dbf3f3c16c935887dd4e25537eb02e04b9fe9f011a2e72a913981010001	\\xaddbc8f4e672c70a3f3ee6ed62a6beedfc29294f5f3d8c23114011e40e3e7c3629b96c8d93711a67f3aef3ffb73857e07228ffe5c521eee1f46b271edf9c370c	1662072702000000	1662677502000000	1725749502000000	1820357502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x4ee77ebb7678306dcfd3e0f61a158789a07b23158f02cb271143282f5d77228f9b3ba63f69aee51f7a705f507709233badb9101fb0dfef2bdb3ecfdd487fbca8	1	0	\\x000000010000000000800003c1d0495fc08c95afca1206ca292602f54b6ab684f960c06364d78145541b7af82291f46736fa1ded718c8105ba0cfb9b1d74312da552519703100cfe243a5aec16d50cb83e926d82628a3dc88654a0286fdd7fa242e0f88219aaefcebe94bad5adfb2b9bf7bfbdd37510df8bee1aa067a55a8f743fe9a74f171082f1fd24a9bb010001	\\xb1c8635f5abc9de187d451eae853cd6d675d10872511fda08204cdcaed2e6dfc6ba5989b761c345890161ee15b34670364e51a6ef861d6f269d546a16acd560e	1677185202000000	1677790002000000	1740862002000000	1835470002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
345	\\x53b7296ba73fd8735c9f988aaa2b6842b7aeb87d175b3cbd051d5c9999516d3318fcba17575733843853c56ce070070015340973aa873a33d3ee11f293537d4b	1	0	\\x000000010000000000800003f4fc397d51d124fbc4f97630f0eb12d0fd795da4355c01bd2894cead36d7baa14d6e6fda52bfda41cf8de7cc453f95df741e5ce6b5e6b233de29ad32ae00f274b1f1c954df0054bef9c50d22b1bef9721f4885da9f588c9f6da5d0b887aef9ba5b1381e4d60c5bcbcc7249fccf6981c0fc9774ee2a7683219694e22070feee1f010001	\\xe65a3b8340707fe817ae5201021cf59f9246743f620313a0001b07ceaba327578071c300b74e54638c34695fd268077ca70935d936dd4c399224804a2758b409	1675976202000000	1676581002000000	1739653002000000	1834261002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x56af3049e854f9aa8d3e94e2e2dc0d09d019342be98f6702ae4784a6444e5d04b206a2cd4198ce84e143b962ec79b89dce6e73e960ac6d6cafa812347dba8464	1	0	\\x000000010000000000800003e5356b3caaf68b8271bf237ac982c52880729ac3ecc10441b557af0642c139761650c59757c0f9220428eaf0c54357653d879227b332a4716bef490ae248392e2765a1ec93b1fa0aab5b5b1212967364d0e6ed98b48929beb36897649619f970bf9dbc84dc4d41c42a84382545d914460639e9cf322a1bb96822ae73597a8947010001	\\x2bbf9e8615a5d00505f428b9706d88a363634e584a23341fd8d19ddd27c4a395c7995090c627c2fed2b181e48497390c0d442c169ccb0800fd1bfda7656c4c02	1675976202000000	1676581002000000	1739653002000000	1834261002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x594b71734c4a35bdb069f522db430c1d6671c5f160d1a854bf3cbde2fc3c3eb27e521099f15b65976f92ce2ea62b44faa8f5d728f43e914618fcc4661f059b4d	1	0	\\x000000010000000000800003a65973b6fd8ef5dd46d2636346cc43ac53378e7f58b5b709449bec202b8eb6fb33f30385c8c0a7e156ae18b1237b58b420ace122d56a0b236d349121ecfaa9d71d0db721612c248e2201d37c9ff3206cd3be3057530b7bb3a7b5fdc83995908312113294655e997fef95fda1e0c4fdd8a7a38a804b792f3ba679f1595568d1f3010001	\\x6010a68654a8b5943512a63f530a40b050bb130150382ebc82ea1ad46fb84ba43b3471167da29e424a9f2f35712fb9e9e359cf99c5fbfb0d05d3d0bd1a9b0d05	1669326702000000	1669931502000000	1733003502000000	1827611502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x5b8f5720b1fb3859b21c3a05058fab4a89c92e25807581ac7b6708ab015437dd6a8db16618fbe46f6d63d63def51d4f2f16ec3b8d75690dcc789a72d9487894a	1	0	\\x000000010000000000800003ca349da187167d2ba87207f28fcfe268201d6203ea95ee800aa7ad17459855d95dd604bc6cd33413ed6dfa93aea0c73c9e91b6d6043170d3f5e15653ad6cac48eafae70935f6833cd5ea90c5f9027a4d5050c914c1a0a64fee58771895fa1fd106cf3e46bc1976e60fd5065f3cbdaa3a361c070d90a3307fd723f09f463bb0f9010001	\\x4d355276f842f4ebcbf198c1a899100b2e1a22776c25dc5a72c059c0cfa4e406a912354d6b5c4c60ed34b6d9986cbb4299844ded059e2abc399d5d6433c34002	1669931202000000	1670536002000000	1733608002000000	1828216002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x5bef3859cf84154960b045d177ae9d6a59148575107716ccfdf091e83a348019cff84300f805515e9a2ae23494bf1b2369add7f220d9a6ed6ccd2e7f56610ed4	1	0	\\x000000010000000000800003c598d5a9af70e371d3a8b90f880192a594b696421522163850705cdd7a7fc9c12ecad3d21eb98e7b2a2ac27e0b16d5e12e42d915465497b85a4238f827073f1a0d0a4d14503f08e2fd6e382da5d0a3d6c0e0af9f4ca9bfacae711565f9caa5efc189e1c3e484389c062305878376f4a0622aae84025c8966b027e497f3e48083010001	\\x4b9de1bb496d7fd7cc05820244f7ad2c587ef55a2b47e75595a4afbacf5b50c2f843653b9934c2e225aeebefbb97954d5e0840b7e9622f6bbfa37a9a774cc503	1669326702000000	1669931502000000	1733003502000000	1827611502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x5daf811f86aeadd821d8951b6c4c5983fa5b3a8b666a02cd2282f87a9c9a833b546bbf4a24ab8a5b6360f23edea70db48d9ed6313a0038eed38eab78f4573a6b	1	0	\\x000000010000000000800003a34b298ff1f8373b192d7749a33c228ad0e8fd5b088ed4277108b4e2a1a42034858da624ef8a8b02565d2329852f5e28d23c57ad961137f9a958c5bacc34d2c6d5ba496621d16625e70af3e15f82a011f6209f1f4944ee8caeb98fc9971a610af69825a2b641b54c9ca5a332e882d6715b744602c977862895b88fb71702c625010001	\\x761fa9ccb2b219a53018d8bf1246198a876d0cdcc3640fc25345c42d11b560ee77469dd9874d7aebc5c8893b040670b615d5974cc33b0b8c9daf34f1942a7d00	1659050202000000	1659655002000000	1722727002000000	1817335002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x5f8320884f891e92fa0a25b00465340868fdeff3c1c53938829269bc1eb2991f944712fd3b9d1012675dc0c609970a10246a35991f058a7933afe6b1946cfaa4	1	0	\\x000000010000000000800003de3bc7ee340dc6e52a6ba0c372b91247f74a146f13c46c22304b6931721c98fe5af9f9698591fceade7a32ed7bbf7aefdaa6f49bd9bd27b858e45a99e9dd30e1d24e6e6147de31ad94765e25cb4d55bedfaf7d09c51377a9ed2990e7fecc9e06ae8eeb5e3ae9d3de85646c320be451a0270cf0f0a67c61f98c0cde204776ea0b010001	\\x4dfe710722e71ffd48fab5588f4e7c43d7ff93377fcd812a5ed619949317248a2e69be0afe6743915a73ba29d432258c962240d2fd1155b1fcbfbbcddedacb03	1661468202000000	1662073002000000	1725145002000000	1819753002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
352	\\x657f07b1718522a8171f5bafcec759ed4c8cc82a9b3f92e818dc28794caf1b870d31a413c65fcea32c10e46ce05b726f117aaa0833ff33e3eb170b9dbe5ae15f	1	0	\\x000000010000000000800003af2ce6060385117301cbf1fb983cf23fded705ee798bcfcac3e192f8dc23dcd4b078bb1adae12b706fa3fb1a1df1c9758ac720ee9f372598f7eb79940d25234d78999c3bb8dfcc1d2bbb0c9f0dfda9343eb24f880a0a448f490a568656df7887a10cb8d9497f4f39358f5946ab71891df8ef5cb2bffd5013b92e07aa3a6ece1f010001	\\x13017b9c18ef25146130cc53bd63315cc880e7a933eddd5b9b61024541e0d8cae284e66906daf10262871d18286b5188f32f35a6fb807932139d27d9539dae08	1668722202000000	1669327002000000	1732399002000000	1827007002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
353	\\x68d301ecd8e9d213a7a0aeb1b77e1da909833b0cc761f9a2be1055bced6c9f600661eca2fec1901c11548f6c85d313c1cfee2a5881aafc2f8f3ede13577f881d	1	0	\\x000000010000000000800003a3af0ee0df4a1d4409530b0f21be1e873b91fc23fc90cc4f8b26b7c7fe27b626e426fc4cc9b7b20195ad6a80628b02e5ec68b5d2831aadb176f0469c2ecdd3998b0b64fa5f9aa232e9ab3b6b90029e75c2d68b2f2f2403a6d930d1d579e07b2dbd089bc589804c133210eb3bc9600ca10f282c61e1a532c5e0d0c2b4806c1525010001	\\xd988d17dac99d795813a77ecc48d47705470e478cc394709d700bdfa51ff8cecbfdd1925608944ae32e7c2cc80ca2fb5d25514c0939c663ffd77ee0573e92f08	1664490702000000	1665095502000000	1728167502000000	1822775502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x6b0bae3676748a633f0174028249f008056a8db71b32151e8276b78b2ad73ab509b02fa848703d9a2da52890a35425dd1f6f17b4726d9ba4fb5ee9aaaa3bd0e5	1	0	\\x000000010000000000800003c5ab2d4960aea44398f01f42a58b6b53a246290ca18dd38242e0f5f943cd85a59e35acc6a8546a8fc1cfe853205e5ace938f439379e6ade01c471daa9435d61847b7c357f3e1b6b80c87ea3e9ecd13121ef1f09b9b647a9f7a244b27c1a521d6fa75afe9762a13cf0fc8e91cb5f234f6e4b8009643dc2df1066f2ffcd1063bdf010001	\\xb94b0be9f8dc2a90e0ce4a13d9607e216c903001c7cab9db2de43202aa259a1bc0aa2ec77c19b201cc217e2188b8eaf8c16e28a6dc60ab828d4570cda8864c05	1676580702000000	1677185502000000	1740257502000000	1834865502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
355	\\x6c078eaa1573d89926d3e33a26ef6b42f04b1b4f00179d9b07f10938d7c43133d386c7f278c5f8a735bda983180ffde219aa8e4089edb5fc0cd3ae55a7612761	1	0	\\x000000010000000000800003ab2d0d4bed8d8fac05f0bcdc568348ad702f0fa918e42cc80174410fa23629ff9e68f5143bb7da375d63e438d57acc49b5dc11b150818ca05f3a55067f928b7fdf180cf720472289fb7563776962b02e4db49302a6dc6d6cea8103bc5768c558e3e634f9fd0fd0928f87e1503f9b3afa4faec45039455425a7144047473d157f010001	\\xcc9ce9b8053698357ceabc5de1e3dc3672bdd17594efd5a3a1feb2ecdbefbab2ca909dc81a6959db082fc680a23c31080dcfd913463c7b83493018bac3e5040a	1675371702000000	1675976502000000	1739048502000000	1833656502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
356	\\x6d6fbc83ff01688db4e12627f21eb56a1714970b528b76a8315919a96921e5aad9ec0f6d2c2547573a0f54bc777c355247b6e0d26f0f3701267c50f89b4c3879	1	0	\\x000000010000000000800003c080256b6cdd0757468b86a8bb619b8fc297ff5cd1e5fa408b6c9f0ac1eb3e0ed95096fb79dd5af2666cbceb923880d7f52c9b92a842a65b687ef36fd9be20cc4a7676619df7c9bf88bdebaed1a6b164de47757184300af76fbff9bfd4d97e85e5a6b751d197a47adb2b55e9e174c45e0dbc8b84c03e7535d5b0d0a7f1e0704f010001	\\x4a60b3d09760ca8007dad658bdb54ab681acedb9b93cf4dc5451190b747f54d40cf657bfc959737cc664b1e292f08053ae1670754d2454ba3520b34d7696b60c	1675371702000000	1675976502000000	1739048502000000	1833656502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x6e93c02aafc0f729bd1454ff7da4b10db10f0f1a0140c56d5b7059b25f32751222fd9600925bfc6c8083893f076956f441678618e9d9b12a2f78d556cff6ed2f	1	0	\\x000000010000000000800003da7fe7630162ec39e5940f1fab1710f110a096ecb0a742b6ff4e1144cf887ae202092f7f5d0991d955f0455f3fee96467efae933d5102f3dac4d9db276d3cc50ddfd2de4dfdbb3ddfc720ba4761d3ed21f33993d5f2e89e1f0be67db12fd86db145796f8175b98e35870f936483a4fb3d21bfa752399b83048231b830e6b7c9b010001	\\xe893695a92e7842bf14ecd84d625625549d761002fa94b98d9bc2ca146d6eb7d7a27c648fcc1b30a5032e4e3036d7df0d9f55c32b4d4708c192613b8697a8901	1648169202000000	1648774002000000	1711846002000000	1806454002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x6e3f108b6d96721eeae6449790126df82279c145381c78dcef1d5cc6ec5401808c2957693efef23ebf330f9b6e0ebcd79f3f582624a9a727a70d5cf378eebc84	1	0	\\x000000010000000000800003aca9819cd214af5854e0a3d73e7cdcd201df7c8583088772dfff14d8d2e3e446d5adaeba9f8f169e55b13d6c9fec4ba65cd6857969baa71a43e9781ab10f36282c7155558a4eb478b8be38e4ce93ffe91fc28eee60f5de45291fd8eb66786a187e5823a48f0d3ec479cfc75a6d5186f9ae0e6dd07382fd9cdb3eb4a19e1c71d7010001	\\x8ca52854ab8f3741ce73c9b660211b7a89a22200ab3f74a6adf9cba8df14b468aa99e9866ac58a95ecb822bab7ff1db8b7a35841f8971048412f2893d7e11400	1663281702000000	1663886502000000	1726958502000000	1821566502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x7157dc4448630217007e77a34b1cadb839d87d2e600903a58449037ec109624edf73a57315f91e6701a76fe2605b84e9f1dd4db33af4dde2ad7d4dc092c2474c	1	0	\\x000000010000000000800003ddc0f21415fc2bd0a91e81bb1a4c5363f131da47366d53ce248cbf7d145202f3383626914832af657c4e9e75c3cc52d55c3ee52226c185f6597fd497f2d6432e5995f21aab2bcafdd9de88362683bc7778e487526b191c29ae26bbe811a74dfddc963a7e613e1a08ff0b8f4934af096110cbc129ed0197489a57269b75b8b3af010001	\\xe92a2f21edd95455bea7987c8a0ab3675b8307652dd2dd6d20fdd4257281cd8e94624407f6aff9d030da958044e7c78180b902fd3594b6ea14040c13557afa01	1668722202000000	1669327002000000	1732399002000000	1827007002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
360	\\x7203c54172f634c3a124d5dfecaa9754d05414f6335e43267e93b6f49159a2940a6f8462f39901def08a17d49ec418a820caba21a6e0daaaba7f768d042f34d7	1	0	\\x000000010000000000800003b4eb93c0fe2fa2069a8574ab65be76df8e55b86a38fcc9d1fcf15ed51188f18d95dbf9c5eccf140bcdf760ae648b9e9e8a7b036162798435d6f6d7fae9d966efb87bc1a08024aacf4099d31acd9f66b1918da6cb9a8ee0909f4c6c38cd4d86d1a6934c1da39a93774b089fe2132290aa4efbfeef22ad9c0d1ee7554e22db1879010001	\\xd633497947b1891a2d9d811874b76a3d95f7eda812ad4d7702ce3ad96c36f1c5f2e86e149ec1e17d707dcf7f1aea884eb52a503981a9df3ca82cf190d48e4e07	1677789702000000	1678394502000000	1741466502000000	1836074502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
361	\\x74975c356fc30fdc104e1f8900c365f0115dcaa887b48d1396e9da26d893ccfcdb9b5879e0fb84168acad5042c74dafe36c4526c5ce91cbccbae3a83880b3477	1	0	\\x0000000100000000008000039c28909413dbcc3acb65364d4cc15459e7c62053e8b2c96a904001c45b59594917b0f9dc73c7dda8e450753c1576db244ad3f88bc5d76f4421d0ad92f8a32e89f2c07ff71b3e57a3a0ea3c3ddfb68a9f9f812af773f10be4626fd4dbb5701390cd9b2eee8dadd04892855d9eff74395ea571fda22713054e775425c782c588bd010001	\\xb52f67283e5900d3d61ab3bb0565314aa08f2ccc9bba52e7ad253b3e5a3f0d04b3c5da47d7af312d781141bb72bfa1265c3aba145e308cf2770cb61ca9e63000	1660259202000000	1660864002000000	1723936002000000	1818544002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x766bef6f2661ab82a01956c6ab5b3572430a5dc8c85cbcdf8a037594d39abd5609cf07c71b31568d68927eed5a9c5e2154d256681c25b77e2541f2f0ec496966	1	0	\\x000000010000000000800003d11c88425be1c1096e3329f544373445a08f3550d793a4fcf185dc1261d32ec4a169521d6ac4e74c2664eb8359d79a0a902264c42e80023e8983d5dc815ed13f8b9ce3b9d9f1deff6d1c9cb12b20dfdc5ad38d5e008fd648856709ebafea50471dfdf7ce7313661abee71ac419773eb433d4181c2bb137521f92938d130e4371010001	\\x3cc092127bbb31ca72f8bf5daa58587438455a5354d34548e299012ab3fd87ec16f0bb77e060cfc7b6f25d7ff6affca55627a1a7afdc70810664bc517849c204	1678998702000000	1679603502000000	1742675502000000	1837283502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x785bc7df4e46dbc26cc0a5ce6528ff80e188d4d44f177bc918fd734f7143dd581b5b9151e8b72ba6bdfd89c3f46ce9ecc72c55fcf8807f685b169a1906995b71	1	0	\\x000000010000000000800003f46a592fb5e98e6d3783921a6c024c59007e6a9688fb5629b2ea23af23efb453623033d0d625c1c2501f48e1975baa0c340f942f2fb6b02ca458eca80975b67ef3174d2cbec538c3f9f744cde0417cad1998d1c229f28feb1e22d900158aba057fb0b0481cbd16f60080c7a75e13e4be4233cfa5632efc3d68b135eb84b214c3010001	\\xfec83c08c9eadd9250f228764b3d27dfd4d0a3054ba6346886aacdc4a2549edf7b4eb2c13cf1c6dfc6415a68132bf4ef9e97296a421d40b853458d2bad21970c	1676580702000000	1677185502000000	1740257502000000	1834865502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x79af6a23cb52c7ed04550fd6b9e3530a6fdd0b22ee855ee4690fd54fd81d1af6cf66f7eb70b6f6a9a7ed381631c540308d9551836ddaffcb8958472c52354af7	1	0	\\x000000010000000000800003ed52c2a3130c44ae059f29daf0cb73f0f6924744eeb5265fa4bea954eadea0ea3924c69ade30aac65662bdeae5af6b7fe9dd2f29f7aaa489081992c328469dd78e4d8d7cfbc137166189f800c6d1d5360a791c78ca0cba20c88d4dc9afa11587e7891f5716e2a56a238ee7a9a79c3e4f66d069c977a43132c5897750d2c1da3d010001	\\x3097c91f6d1843b06a217f10d64220786f7697a9c88f8b53cbcaa5ae47a38403231b275c4939cc7b51f09042b37082d6f57527226be45eef93e6de45b5dccd01	1651796202000000	1652401002000000	1715473002000000	1810081002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x7aafadaeeb38ef9916e5c95ba8e84709ae8f08beb026555d24fd0924f893b54769d2bdd33b3d1d22259c9285de3e022069279a6381867b81377ea51d4ef52fdd	1	0	\\x000000010000000000800003c71462f3c47c957ccf3dcad31acd4a0247b6021bd57dbc244b9a3294993990090649729d0b549e4c989f321b9e468d42213c7847be1b89aed7e69a0766fb776c0e5b0d94d48628438839146423a19f267cb0d513f30162a5f28b45f4553ce6d3f7ec57c23c0bea8b60fed1f921eb92e31cc40f3926b2c969706efaa33deb4e17010001	\\x06b92395bae8b42f73815b63fb231c2623d34486d508f032b4784b70240ec3d10b12cb143fb4a9696a3e9147bb02e80134827589388bd0cb6c4a4b6f7eb5b201	1648773702000000	1649378502000000	1712450502000000	1807058502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x7ec7f6e47c6b18f43872d0cd4ddda085726f0865ae1f69639b274c56d15e1de39f27edd3c4bfe9f5651b9d8eae3c5dd8b93e0cfc632d21c38b71fd64817bef64	1	0	\\x000000010000000000800003a064fc4464685d9692e2367818987d43f92e14e7c009160404e75980e8f25aa10a7c23cf557a3dbb192d025cf13e4973869742f66f1b798e7c5cc535efc6d1396dc5ad0b0d1ef752a2c961ff663aeac3c45ab7ecdb823bdd2406a0ea41977d90f50905d04d6c2b918f09f85da8ed2421d2ae414ab5df31ef3102903418d0ade5010001	\\x1dcbd7d19768403592bf0406f395499e9ae657cb4dc992d3dd48cb8711cb574416af053f505bdefdb399bb61b1fb5708290f33e20ef03560bf5cc4034a033900	1662677202000000	1663282002000000	1726354002000000	1820962002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
367	\\x8293ff2b5d7e02553c4242c0961db03c85a2880d6ad305f7e830cf07ae11232c92e45838d54886b04ce515ba298995fb4b2ebe4177ab25804e137f48e6c28df7	1	0	\\x000000010000000000800003ad52853d516b543e360309af2ccd2920ea8e77602f79864ed58508913e3a6734b1eb157c1eba75dfa41eb631b2be04d51968de71dfd619564258eaec23a99ee057a8eccbd7b40f19d737ab66a691e6328fec042e9621ff42188b1818aa9182a30fd9ab873070feca1fe98fb591930af47d033d704d77af6bfbb43dc3e38d392b010001	\\x993a3efd98e560320ca639e18d59457a978d5f08e42f9ae7b3bc72608ddac67744610f95fdf457df9ad6f4e3219370f8a086e4aa9836dca40ffd86828f50390a	1657841202000000	1658446002000000	1721518002000000	1816126002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
368	\\x8447d9fff77bc7026205377275a191cb49cd9feafcd541b5aa5ad9ca14d082f2517a615f66f4314e81ce15b80063569b594d5002c5d632fc67fc1d228b4c9065	1	0	\\x000000010000000000800003bf87511a2ded880bb08fc20fcc7255266f74bc67c10169ac5a539f77776e5bd47e1d88fd3787451d7d8f8d6da1450d43f142849dd5eac8f39912a5c41dafab8145e5b1e50ac9bcbee98757b88c6b17483863509dc662a2e853228bd4728cd5360edafcb6f785cbaebd43baef100ec4fd31e0add5c4d2fa9d7d3928d2a4359b57010001	\\x4d6c1d650ff3d4850ea339a00ab68316549cf2a06fd00176d8dee646db373c3f20f59ae183a5967b7a98e1341ed9d7e487c8f53f27d76f8b8cc6281ff6d54e0b	1674767202000000	1675372002000000	1738444002000000	1833052002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x8cc768142739f7c9cc1c9ce8c5f71478bbbb1fcd9671586bd2029d5085e721e354f6bc98ce88b7db1626b7f3ad1efdba670d249ceb5f97855b43822b60b1b68f	1	0	\\x000000010000000000800003cdafeef75175b13a9dfd5eb396baee865d16a754c53283847c66ec38e873ecc78bca689e376b195b3e13ce5c6050f7e4aaf42c0d7b221185eaffb2a4ede89e80d93715c0e8bbdd1393a1656390a080cdbfb3789c14d41ce546ec5cb3a6f7333c2bf16b66f7faece3cea1e1c07bf0e52697aa1f6fa6085ddae1c18d27cfab6757010001	\\x3aa79940572f11c12c62d73e5a31eb0ad1df4f299c1c3c99ad11dd9faa9fe16275feab149d8cafc42e54ced2e2b29ec97405c2edf95c5284af1fcacf10baf50e	1651796202000000	1652401002000000	1715473002000000	1810081002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
370	\\x8d639a0c9a640305fc363aa9c0ee19fe3a769a4cf1615e6e30836f5cc1c61f4c1e5f3a390fcf1ee3c708cc9d2e973d060f85d9559b56acfdbd19a117ff95f814	1	0	\\x000000010000000000800003a8d758ef64b9d038b753fa6fddcf6c61abdc89e62226d373e78ad295e3306ea68d5bde8d5d66b5c2f8aab9c13d3d47f37354f3cd39e92bb8485ce9dd6c4fd0b4b77d0f0da5c355bfc3c16efc788f70ae239640cead098524280e4063b3b2ce13218e49411c46094b750216d8260822d7e5ba44c1c02725b93c946e83548a833b010001	\\xe83a887607b92178c5eba49f9c533d1f081b497543f5212c63b50f5e228cada65e99f5c398ce0a9c187875a79573985523d82fd4266ae080f6aba77151e1b508	1667513202000000	1668118002000000	1731190002000000	1825798002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
371	\\x905f1d3cdb34bddcefe6cea246be04f9fe0cbcce2178b7eea92ca178ca2e13353a11258771af09431d8f2388cec537268b865df1c0f144989bd5608aa399eb73	1	0	\\x000000010000000000800003b7e2768912c7e6cff745047d2df4ec8f568e23d72605e76e486e8af3a02199b2e620bb331b57495be4271b22232b216cdc426e0ed12d9e442d62b5bc021ba932b0d02bef0357e4c05daef24789a23b3a96106d708a50de8caa8c841118a3f4a70a670536465f2314601a0df36326919be478384338c13a67f5fdac1d6a5c023d010001	\\x3d7a9428021387a17e749c3b0574cd9e83e8c814b28bd9f8d8c605643c1a322cddd97aa0c12f6e32a2235b1633a1bfbf97386c3dccfbaca14d03a954a9ad0e03	1655423202000000	1656028002000000	1719100002000000	1813708002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x997372ae9e8acbd7be367084a3f8436efc658dd94a762b8ad51b7b7bc9f27fb5af61bd401996eabc72e76c835bf0d587d5225849b6c9c4dd0a7827e2fc778727	1	0	\\x000000010000000000800003b6ee084922981c1fb8ba646ec457321a98f24e368434a878c093af2faceca2a7eda57b685042d57757c945f2bf7ffd45718026c3a120c283f35c69d0bb36663fe78f5ea893b1c92494aaa62e7e05c166177718ffcd209efc52a2e9bf929cbab5073525819215864dbf4143cccdedb7fa2d1fffcaec81cfa7418a91d863492bd1010001	\\x1ef8bd3c821fe3b17bd5e83fef469843ab0e3a054d78e2520bb3dd0133e1f4f62e3b046e9f477978a4907f760e2c01377ea1e33af3f6ef510035fe1065e23806	1675976202000000	1676581002000000	1739653002000000	1834261002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x99bb3af8ad349f7f400d81bfde9da6c4e23020763db4d5f3a78f2969410b5d73d1be2647947d31e9200f2b7769844bae2e183daab3241ecf0129d545d3989180	1	0	\\x0000000100000000008000039a55f1c40cedb43c12d000cad5a55a3b5764967a192fd9255d55d823700d47ef9810a8235a83e71c91fa890c338b9618de60c521351d479eefbcdecf8c7d636f3fa6a34c82e940a8c6b46d78fe9f01e7a598bd4a7e3ebc0492fedaa1d8a3c988d0c62b6b08bac85517d110a2ccada24b35344859d95421214ac3b83b2deedf37010001	\\xb659210b632b5fc46e57d9a960a68f48fe8f0dc3546e9ded75c0c57e69d51876403797c995d751f6b6b7bdb28255ac4ab318862dece02a44e404eebc9ab8d308	1671140202000000	1671745002000000	1734817002000000	1829425002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\x9e8f4f3733b2fb311933940a85798efdbdcf6c8910cdbc8d7b1292c2fb6c3c539cb9e319aef508ffa1ad0930d7fb43c6e4f965e2dafe15611eefb45abbacbdc0	1	0	\\x000000010000000000800003d9ad6b5707bc2805e33779eb3f56d93bbebe04ee8a9a5687113216bce81bdc8414bd7e8917643f83af331828c4acdd9f67554b20d96a1658d9e6e01191e7e1a4b8f18c3fef6941e70f0329922e647483312e3a1ee4057ec9e319260b856ae1bb42f9f3a5f536fec5c4032727d9ebb4425117ba4aa5b30474d0f473842d9bf9fd010001	\\x84436f20ef8e1e67ec09e235dcd1f0d04c8c04827563995d5715099a4f0c9d08751ea481a99e4b959831416246dc93e206f6d7b7e3d9113c31fe707f6e94a609	1666304202000000	1666909002000000	1729981002000000	1824589002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
375	\\x9fe3d33b0950cc1221e7ba1fbd47b4cee5313d794af646e8abde2d65d2ab0adba0dd03e16a7a18914e4ee4cc22a719344fab232e2b4707bf11a604814f370803	1	0	\\x000000010000000000800003c148064c4dcfdbd5566decd1b7b63a54d775b9d247ab4515725104a0397d4a858c26c95e601cfc83a68cd2c817cab190b138fae0bd6ee05ba2e2a1319f567ead813aff53882b6e02a7f1dac2506cb60dd7b2f2d4cd3f71c8e8821c1421a411185b2d846c4b4922dc8f4b17407de21fa10eec9cc8a466ce03fe93a849b7fce823010001	\\xd2adc8922a5a85b8bd310c95f2ce9c7939db257e4956d09408b35a0565a98b0292bfe9bc45b3e93a7dbf4a95a6f5f75410cd7cc0972319cdda8effd0ac0a0d0e	1658445702000000	1659050502000000	1722122502000000	1816730502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\xa13fde48ad06a4c4c831d3f5c078e1ac838de64d05bdd15c2ec0465d048cf7c50400bbf9aae7517a34b9e571a69062f257aac252ed1070237f01c00cc0ab1a8c	1	0	\\x000000010000000000800003a33e9fe7d24b0c9974fc3ad40e9566e0da0a7ce59f399dcf78bd6e58ed9fbed187e0849195990fbead7ff7378c55492d808e9fbdf0547f0874edb003ecfba873d21ffba88b33c528b3416d6bff6f9c91a05953105d78ed8b091dae609212e972295b5ba1f3473e6d908cf9fc3edacd5de6d9a866a506de47dad3b02449206513010001	\\x177789ccf221390dc36b2d71449d7104e729ac7f8730e1ecfd9f956b2e148af7606334bd6a9dd1da3d35d0c11d63de7b296067f200d18f19758c103b203b350c	1660863702000000	1661468502000000	1724540502000000	1819148502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
377	\\xa32fb6abb6b7ab4fa1cecb60107220427f3ae41689482dfbbcadf8fb8e4477e80142b22b0f81b73a12d8f6ad3475bc2c0f451a82af2d10d0b9459aa6bf5de73a	1	0	\\x000000010000000000800003ccfce89824a0902fab9ef2298f67cbe7e83b1de41f71fca5af2e87e5132274a83d189dacd9d73474c40d0c3a41b8c31c0d3bfc41d3ff6f4ccb46b8f60efd198b33d175c183be98d09d63a2b54931e3aefc99c035521a8b78c6c8332d5a50b956871d59c7a6a4bd3b8939f959340914b08e52eb4e70735d55245db8655fed7e43010001	\\x9332f8419ceae1bc878d2043a5fc2a93a86781ea6d87609611760ad288de9e55f7d17975e02d7b933b52e3c97ab32674862d8de85a9ad2cac3a329b3c5af5d07	1677789702000000	1678394502000000	1741466502000000	1836074502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
378	\\xa81b4297fdf7820c10cc58904cccd38c9a2cb21b0276bd5a07059067bcfe623985543c1d7adcb72506922532068d1b83c73518091b8d2e98b22ae224544a8be4	1	0	\\x000000010000000000800003c21d60b8db9ef5f8dc68489397de86b2ad172e0e76cb494820ea2e211a9bd2d096ea8117c666a439328c4c8393b953939b0832e75a3686cb068af465d5f16e8b3928ee874d104342d81a1aedadd33dfccb03ee5dc86da55cf667c538a5ff997252b7d5ac38661693e318a86b553c3a532dae76181ecb99cdcba781fda6f19e1d010001	\\xedbb156abeedfbd8ea0009cd6cf26612e9f8bc24f7cb7d669737fc0ce69c46f74599a1e4abad8049a72500797d14100f585fa6691813722c322e7702cc9ddc00	1666908702000000	1667513502000000	1730585502000000	1825193502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\xa99b954f33cd1d7ba656defad360fa2c9cb0365de25f8391e7d0d817eecf42573df5f39e451ae1b53603cfe826c10b13ad6dd202da717e91b2b209ee994011c7	1	0	\\x000000010000000000800003a528fea535bd7b4d4e3e5360c231b19ebc6a5fa79c02268705016b3c8b3358784357ce0f4f2ce558a2fb4030105d6d80c54c93ccbab9f36bbbe50f15d86a04a948e115c3bc39652499d3e1cd87f2ca53a7e0fed515f5d4d315b8fafd9a92d546b1e92cd0dbbdb3a9e8fa6f4c62248ae636de0b1888d9f188f5d627675001d29d010001	\\x8a77b2ed05f2d5a99f91f7a4d08e65758d34d7fe36ffe415f26a63ecd83bedf3fc5f3ce492199a73fdf4026f91980cf748bda4733a4a5c3dc438028c3cd8930b	1654818702000000	1655423502000000	1718495502000000	1813103502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
380	\\xabbbd823fb401a467f9afb53b77369aff78c325380f740b207c9265f5e7afbe1eff9ab94f7fc5a26f513b94a268d44d323c71571c502000e6fd157da8dd60da2	1	0	\\x000000010000000000800003c3a96248f1dcd39aec69e15bb7cd1621a9a84818e061f44ff476d9e6097e4ce25159a45427e48e01016b54b236bbc5db486e0d53efdfa768b24e4828278c8562c3e638d8edd5070354ac837e9c65f179ad20337de230d9acb67bf2a67f0f2f4a49894f94bb68ad786467e0d08757033af45166613dd8970188299e36448cedc7010001	\\xa0756b7bbe72a922ad6920ffb68c5de37b1afaab3f9f6ba8b83a11968c822a9a6009dd1da62fd383245e3d344030db3900dad14b6c969c367cfb4911b4f9c50e	1677185202000000	1677790002000000	1740862002000000	1835470002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
381	\\xac0be06ed1238238cfdea8e31a7716350a98f55e7137a67a1b6892f7bd99813ae381774985cd41d364da55883a92c36136531c0ead2b98a1f4835ce8261712b2	1	0	\\x000000010000000000800003b124bdbfaa919e5fea5db78a32da0dc34bdff2da7003c222b54f629e1c2e3675ea35e8f0703887b4dc86f1f8098bbe9ba7cbbc87d707cab45363dea65dfdf5263781f6f170f9c83cdffef745a3dd8a4df3cad482c40055283fe23b98dfb1db5a08fce2f6d14a0469cf2359d2c0746395d7ce6493973238071297192b6c61e06f010001	\\x3f5e34254a07a8b63ecf358013bc05838cc4d4e6f19cb1861f53a70e1bc3d3422fdd07e8307082b04f97b2d69096d79cb908411eae0066c457ea17650e66bb04	1669931202000000	1670536002000000	1733608002000000	1828216002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
382	\\xad87f816d7e41bac4259b9346a7ca3f7767a0ca205f53724b885a823983166d573f4f4994268e3e20b9e13ab7989551aed62cac129b0d8ce9c3efbba5382bff3	1	0	\\x000000010000000000800003a700942d4ea50fb49343376ee296072878ed36de90aedefcdb0da9eec5a38c1443ffa88bfd52389afd7a92f1967479faad142091b1b5a68d201d7f809389a22d9217a4ecca2c958d3b0be34d23fe3c8532d629439531b644080a8b0e7d410f399d91d7648d6a3c264d3b1052f637d28d383b7adad693a41fc8117e68d45ff9f7010001	\\xd300e25a5343717bd87ac743442b692b94c11a7c3e4040c26894f01f07842caf628b27cd98bb8cb68671b101bf3e8e8e9811b4c0a1e6959a3bc91ec1868d930a	1663886202000000	1664491002000000	1727563002000000	1822171002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
383	\\xae2bdf90c00539e8f26bc50697814b5c979a93e45447d5aa605bd8f3f0a5f8521d6ee2afb67481d350f2f0935efc0749a129dcc25bafd13fed26b9a2e133e771	1	0	\\x000000010000000000800003c718dff1266c9ef8325c3df5ab8ae0db0455952df04c68bdc66052125d4a4ac05ff12e61c6eeae63e854834bad43faf7f8bc06a3ea0f3b2088688b89048f06e89c7b8b46056923c7b8dd10f96758f16bc74de1a86da9cc840cf2f3ebcfecd2054c4b5bac8c04d43470d9fd9aa8fecdf9fb1a1f8335e2d2cdd9b8fc87cba0a669010001	\\x2396f89acc33296b64fc02cfe937ee495f00348127cea2cd13e2eee85843054f3c33b5d25eeb13aa86eb28c6fd875687c6f0bb0f412f4dfbb37e373af25a3b0f	1665699702000000	1666304502000000	1729376502000000	1823984502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\xafa3dc56c68f82829837e75cc5c26ca64e4b6d7dc21f6d20c8362e94f17139e235fc8b4c26bc5e66fd61e55742269317ed1aa400e44e0d644fa297faaab734b9	1	0	\\x000000010000000000800003c84c5e81343fda0369dbca94993dde752bed8f98c300c40e7f1be2bb2eab873983bf02cccd38a8fefdd377bd49d8f9cbb8e5fb8f12e487d27ff93a1b5edf53757ecf426841e687f2949f7c6635b85a0614dc556c520a2824bcfa613a3452510763834280423792b9afd9d52a985d145138ddb369bff01487ae4002a00fb01933010001	\\xb7e0c94af9cd772b9dce578b3f7e20a8bf15278352d4086575f09aa94d7c1849ae121d39d312403467933bb057983547f60c91f8b7a9837328b36a585529fe0b	1654818702000000	1655423502000000	1718495502000000	1813103502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
385	\\xaf0fef42fc1daf951096ff6fbbbc8a0ed73aa9297e44a5228e80e06fabad1c0a5b1fda5338489f8967e202199949ebef37a61c65b9f94105759cebcdc0625666	1	0	\\x000000010000000000800003cfb5d88354d77341b7cc8e6a12ded09e6c4ecf03343a0590a82fa908ad6a77e034dd376b77387beab98667942699d00d4a5b835499debbcffc72543d966f160cb831fe31a92bff949d7d626fce1c19b85296a9ae33eb3c3701533f780e8f1bcb1c33cca3c7a9b3b0d1d953bb858dd906c10988fadb22e3ff7a8906d65234f367010001	\\xaffd4a15ec7174e49e76f9d31d828ff40598aa77eabc84e464a9f11aa80b54c2279529788536e1d9cba4962d4865c8de7cd6c8d69612b46eeccec3c7a7f9d304	1657236702000000	1657841502000000	1720913502000000	1815521502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\xaf7b073c40e089e1103ab0f233d425c211ecf91c922531f02719247b6c7d64201bb44aaacf1beb070654e65f3397fb7a82dfc7a31a062db1192f6a1a66ef1f15	1	0	\\x000000010000000000800003ae7d79cc2209ec3da81e0562bca0320fe26e0abeb225e37a0650ca01d1c59ecc889cfb435a43206d44971b9de028c788b9316a1d8a92d22ade085d178635a2263af05c1498ba47b10633d5ab16b285cefef60ff6f12c39169f262b03e43a039f08d00fb61939cd28b74a06784c875ba6ee0eef5e626169a507d9679f00931245010001	\\xc6caab02978e85b944821a2e8fcd292dcf290f90c98165939240e55af8da9a82f72c88ed892ad8bd5c66325b70c69969e642495a433092a5e0f2bf4c9df9a80e	1669931202000000	1670536002000000	1733608002000000	1828216002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
387	\\xb2e31bd6b9ae17a47ec597bb66dc533d5038e8e1916abe2c15cbd4fc3781f6b9a584539f6b46de5b63eaf0f5cec0e4e4dbeb16918ab64c8135e570975ec86d00	1	0	\\x000000010000000000800003b4360f9a7b61271cd9f89ef8e1ee4d8aef71aa8acfca34863df9d6d56af8dd34f051334a9eb7ed751e8c5a1d9540e6e8b7d815952c83fc311fac2abccdd246b95a343df8209d991894dd333bf55918bde78de9d9fe324774b7ef72a023fe374fab83de8a91b619623f00fa9415e4dfd812aa9b4465d049677e104efe007a0e27010001	\\x6a3cc78e4df0bb8504e74a64d5747a5f0a88e8b9fcceb8f8f7fb5e140d90f6c835b1757e9790aa8904625d5a56ae87e5ef559384df1cb8b8ada85a7530d9240a	1660863702000000	1661468502000000	1724540502000000	1819148502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
388	\\xb303da03c0f04a1fd03bc89a90c0b2ddf22a574191d1772bae6af1f197912d633d1fd854cb4e0939ca36c40e57f4b15e88fde3ccd4605be9ea00d11de1503130	1	0	\\x000000010000000000800003d9fbde86376cd23227b58d23413f7eda270808927ea1d5d61e4d10339d667b54c130e80192be4e47bfd730c49e34822f6ca2ff2ce9c260b066091c742030e34202f7ba88bacff95c87b82fd5fea2a8c6c14059e4dc4b6773feead2e1f0960841dece7fdda030a641af540923378f5da5f6af30e48856ca5da5acc3c457656609010001	\\xc34b58a9abaeddc8e68d34d5c3d3589157788f88a32e6aa9d4bb7f36f0e3c7c0ded7ada9e25910c23796687843ce346af4b307587f950ce42b8e6b67db14e200	1648169202000000	1648774002000000	1711846002000000	1806454002000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
389	\\xb62305dc4088eb1eec91c443790ac7a4b1353b207f89243f7d0e07a918140b2493c29e7714519fd65a1a431ff243d18a9fb659f6825e4cdc46d46170deea36a3	1	0	\\x000000010000000000800003bca05d8b1dadc0f9aae359d3a2d4d05fb2162f09ba64e34901e57d73973ff51d36fc959058da17b31f23999fadbfa133e62a0b84a9ef1ee908483d91cd37b55fa268ab791de6b4df70cbdf9e6f5aaeac449ccb1d66e5510136a6fb8eb8a3b779f99d6e4171e442594711b8ae4ca5b12731badb05605d97632409f516e9035103010001	\\xea743d12d738647deeef0b257e1c20c1b5fbebb24239d8157ecc6b1dac80504519fc29908d3e08eff80f0a9e5eefcbf7912ffb2f117d6f7c2c0c72c2e352ae01	1651796202000000	1652401002000000	1715473002000000	1810081002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\xb757dc9a9cc80a7b20be73474730737d3a015a1910a877e4db4d8e7ba0e811fe6556c4fa9c58a596949f6c5d6761b8dce5f3de57f06fa8ecc1485654bfc3a114	1	0	\\x000000010000000000800003d739480e8699006e3df42b1e4ba761ecb089dd5711b3a6fd4be4b239880fb574dd0be112a496ea4a24cc808c44601024c98016d823f5691647d62a4886aafadae12c0b155b472fd1df1bfb32265673e0af956925883f2ac2f52637b66f70f4dde479c7c926e61b9ecce632b5de8d5a9fc89bf9fe65ad31b03fa0a1810b7a4ccd010001	\\x3e022d629c4f5a8d1f21757e36639c8cec12d7de432844d751bf61e7ddb7825d10dea36d3d30718a926f8b480334f5f165c6dea40efaec0f96cac80c256f9401	1678998702000000	1679603502000000	1742675502000000	1837283502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
391	\\xba6f88eee21a2dff0a87912a686768a6e4968081a123f7da6f14c188188c11567fd898735316c785001054e9323865cb59312381fbb44bab6f83536eb90a0ffc	1	0	\\x000000010000000000800003ccb37749399adda3b21b26d926c34cae98577b652bfd3bc32f6951fbfac578ec85972a6f0fd278841211d2fde621858036818f205ffa35dcb0c9badb5ec1b8abbf70328c23e45222f891ddf5adc3fe6d4ef0bfd8bf1f00919e1e542b6a8bf3730d2da447fbc782205c4278fa5dbf2c5df2246c9d3df1e8dfd655951520cc5557010001	\\x9424bf38a4cccdba6a1f61fe4572f6c97a32c3cfebadd4fbcebcdddc21fe17aeda12033df9ac484365829d808e3c4c1c4b47bd09233b86765dbaf2cb6bbb3e04	1653005202000000	1653610002000000	1716682002000000	1811290002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
392	\\xbb57fa965dd61d6955d8be3924fdc1b2e0ef7afe82b20cf81996296946191aa758d5bf497e6d6714ddf54f697fc9a3ab93e894478cf92f95550590f51f8a0519	1	0	\\x000000010000000000800003d5a190e53550db57f88ca9e1e6cb7dabdfa4d87a2e42a89fd8ff0764eb57b4080b8f0c11cb538c2e4a58532c726459e3e5795f07752da056c5523d75a21594c713b33889c3fe3b90ca921e3bc9b83113a3f8a36326bb76ddfd9bbf12a36957a452c18ade743432ae6225bb0797450bb31493c54b68da0f2c4df82c28b37d2bef010001	\\x7b8320eb088b476b606c93a260b25bb0daccdc2a7d5676a508df7895fb5194f8b6971078b63a5afa0b16fcbd6735ffbab6daae028cc71f98ad26b280d4149609	1678998702000000	1679603502000000	1742675502000000	1837283502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xbb3f6b75e6bb5083b0e90cd3442003e497a9ed6148dd95a6e9011b8ec9552c357ec1ddf04b2d88e857c3f731419a4427932be64c6e625e7d2c8b7ee8d6088a48	1	0	\\x000000010000000000800003c595ae332025e1214331217616f448fa5582a7a530bc261bffba8b2a689c614d76c9ea2a8c15c9e53b9e5271e9599cc49667e0627471a8b1b3dad9d14ee44fefb9a63ec2a673c1fc9504d5fe04eb6190a83a4107a2064f245ffc78f76b7e4d45f20afbdcf9d3fa648bf0616d6b1138d3e6df9cdb2cd2080e9cff1cc09e174b93010001	\\xd4302385bdd76fd417e55cb785e72a79e0194ce804d8e1bb23e62820249d26063a1df16232c81ef506153f58ccc36d14242635947c18a5037806c44763bbe00a	1677185202000000	1677790002000000	1740862002000000	1835470002000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xbb4bc540ab0d42496ec3c2a2c171dac68fed769450c8e987075d60e9d83db9c9e9177ea0fc06b6b5750a72f9536959abc27be2a29757cd34092ba81c11b0ec6f	1	0	\\x000000010000000000800003b42dfe66bc221af2b2c3283c7067cc900ef43ed5568b96aa34ce57ac95434e7a2c9a7adbff9a5a31aff55d4ce74fdb924da3e5a3fd2e4ef443c1d7d05ed4e1d0f415faa20d75b7d6ca486eede1bf9599341f67079109b94ba7bee3564b83bb9749c971413cda048a2000c1fa07817516662a5e9232f46d6bab89eff4d7d86867010001	\\xb9e9f46f32a42151251da934df2b19c4531f68533c7972ffba2d0510c3cb4f0fc14eaa787dbb6f15a5c6db7fcd11fd3b1c74b9f9cf671124d2bd9f559c5a150f	1672953702000000	1673558502000000	1736630502000000	1831238502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
395	\\xbe9b5f1b9f99f16023144013f2d3d911f7371b15497c72d7fc271213fe1e75592710a9e20083445c78bc1bd01f132f81e2803ed05b16b06f55fab64f28a03f1e	1	0	\\x000000010000000000800003b3788c6efdaded6b523f6b726b6240eaa22b201c3d6bf5fa4b3406d1e497a3277c74bc47262c29909a4c5c245014070bad49de13a5a88d5f3a6c2fc6a7e46fb2001face7ff5cc90ca18cf8611fa83609c46fa61f4124430bd4b06a77350212194ba6fe0a4923b57abba57155c87e8b7cbcfd3316e1653ea894a1939daa7fbf81010001	\\x1f432d298c51cf36fd1526534c2520ae2c3f26a00e4c54bd0fcdcd7690d5a8d61959eb2f10da91f63993129e4b24e660840124b5a5e430ee5036aaa9a305ed0e	1665095202000000	1665700002000000	1728772002000000	1823380002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
396	\\xbfcf7445def510c92272c9faea339c65a3518dac663351595a917572ad4c7ad0c00d8338184b2438a1b493569fe1254097f91d279eb5503f236b2b35b768a18c	1	0	\\x000000010000000000800003c3a5a33f4a668a1f31bbaf5db0a4b739447630446ce32609a0606e3ff87d9cd539ce48fb8dbe0f820d555239c678a6f5f04aadff6c15c0473852b76fda80958e1ac3e43e5fb998b98de49baf19089790433edba1eac143a787826b129cd05daec52a92dd5d5930057a9638e9addcd5f304be8b9ba85e3de710704024b93692af010001	\\x97534492476528e4c9ef448e65b4bc6f749f6e91be06f948e73bf674b03b7c0a023c243f83bcf2e336575f534490fa5b30862c563982337e68f7e94d7105480f	1655423202000000	1656028002000000	1719100002000000	1813708002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xc44b30a3cb40f03b82326e85183011f64c011245776457070c41791d11e9d2bc2b689d17a5d2942b7552c9a25a51d59e986159dc3295acc7a17a7b8cdb44df4b	1	0	\\x000000010000000000800003d43a4a5a2b2207188dbe874951bcbf423e5357493cf58d144e61fe85181dcabe3ecbfec0ac1d6892b6fdb3eac93d9c1717c5b05f219bff384558eb5d097222602bf9dcc135b9d3f91633cbdde5338b42d9bc080bd3b48f2469e11732ad575ee8c0b25b58a91ea7e9bdf48fa405134e956154006505d285bcbd4fc8d43c510c59010001	\\xf6f62f122a944c0408adb4cd0b7c5c28188ffc565be9a6624a303122b1608c062cb1a630d79929d6a629ac4180ae0e774f070c4351c9ddfe2fac9335dfaeb30b	1665699702000000	1666304502000000	1729376502000000	1823984502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xc68b62b175c491b1e2c3a079dd44355234b0b58fea6a1441c89bb64f16a5dd67d1722e65b0d03ded962f21a17bf5349771bf14543c35953d13843d5bc3adb104	1	0	\\x000000010000000000800003c26d59b0fab46d3bc5a47abc7fa78088a181261f90f30cbf4aae7b4e10c6d5a344b923fcd3b3146493ccef785d8ed55fdc243996a655f007cb999d31ea3eabc6de645ae284b996b743ee8fc5b7a7ff3f011d18117e0a45ca87a9d5a8f32981d8589681a3a01a22ae17f1ecc3b1b9cb22c98827fa0c92aef5a16a4540a883b571010001	\\xe51f6d452085ed87be7c17712eb41440cb930b67238d97db04326667299087010bfc5f17f283900dc098bfa9d8c2aad8e608217ddfe91d1db0c957873f55b408	1668117702000000	1668722502000000	1731794502000000	1826402502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
399	\\xc743343590333de13ccf7e579c18ebcf5f2f1c85c6d74a5f23b12b10b43a6d63c42281e4eb94d93fa40f406f63293733b7bb4cbb3fce5d18db791b444fe2a32c	1	0	\\x000000010000000000800003c259898105100209c900a607e2b6e93c5e1ae96dc85830f995f21f305a37b45083d62aecf22a72b98bbd1e42fb0554c61622a204c7e8f6dc0a731bfcf5cba8fb267e27f445aea2e06155d84cafb00222bcf146a1cb5720bd892bc58d5e191e427c8cec336fbd7d94722a12657c7ab1d0082b25bfee7a898a997be7a3743e03f9010001	\\x5af337d1c71aacbeaf17b6bae7e2c5163e3f8826bd2dda0477b84fd4073f3544735158c00d676eb487ad887521f70a48856608c516a160a8bb09cf234f43df0f	1651191702000000	1651796502000000	1714868502000000	1809476502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xc98349337f0763615772ed28a4dcf41a60b62829641849d25fb6e4f815bb1f86799296ddc555be71633a982b15d8445f695b0aa6edfbf4ad1cd9d1b14047710a	1	0	\\x000000010000000000800003c87068a3eb7187ceb5ab9dd976c4562d5c3f81e2aa9ed34124b3ef2ee2c2420f84e8fa257c66a5d9aaa6917e1ddff6fdd1e65ea96414e92c2108a3dce0dc220a5e7c4d72b8941f8f7f090b76d7b9a280b0e655bacd0461f841f561dc6e72cfffb9f43dac670199c62da9f41ad5b5442f87cac77f91ac304301cbc8d2416e5a6d010001	\\x1e1b31fa09a2d1735cdce7f1189ba70b8b4ebf93b61402f90639d24f1edc843d6c8f599063392f56e886a1282a46f4db3d2f6f469f5b67c3a3a2d44ad7895d06	1647564702000000	1648169502000000	1711241502000000	1805849502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xcbf762073c2a61dc45fed1522825aff3aeb2f793ef3964d5c273b4f7ac74f4fdf7b15eac927d8c0b3151c813a73ff9312c441c1a4600bf0c3fa1d14d1e20a597	1	0	\\x000000010000000000800003c94910cbab512ffcee89c92409718b49eeac05b2b77ebf263ddbc1867c7dbb51baf5afab14402269d3dc164b799613e193189ea230e15a18cbccf8d5331cd625db7c1a1d86d8bb5aec2ee6a2d461ad8181dcfe82fa2ddb32d1f8904254d787ff7390f5e4eefa44af521c09858559ba1cec1eda4923626d08c65e68f82e30e0a7010001	\\xb47397bcf78958f2c34049a19f15282e222d3c500fda8dad7ab028acb53e0e199c51842b97333aa40140c38a5101de2adbd85a4e542226ac0d84166e4a0eb50e	1654214202000000	1654819002000000	1717891002000000	1812499002000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
402	\\xd24f47dcd7bf16954cc3c38682be3783708264e8545b25b3e19e6f8da0f2d90705b8600324db8d919756305ebe0af0a143eb8647f1a42bac22534d25fde90d63	1	0	\\x000000010000000000800003b3509124d608678e86fdd160cf002d37c1d89429f4be87810c7c8628319abe7b711c7385e23aed3e17eb3ef840919bfc9b554c27e5068c9ba80d6bf7275d61f39288c2ef8386a2dcf03be7b0ce2b44163be96780689ba0076db673a53af97edeabf882dd90d2bb14a77ed377bbf8fda10f41a721c6215e751678cdc35852ce93010001	\\x2362aa1b88f8b8d15c7352ac1827b018a970336025388e2f933623c1858febd6910d4fe3e1fee5777e0bd0129a3c53632ccc7410c451177742475895a5fc380c	1656027702000000	1656632502000000	1719704502000000	1814312502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
403	\\xd38bccb3f55292ae28ce91c49761f48a6a7209f0906d8ba7fe49d21d1ddae04a1522c048778bab6a3ce54fed597a1b92def5a253afe9fcf1448185a34a338729	1	0	\\x000000010000000000800003d84b160362bfd8c60a47e17d23acc9a8a95f3b54810dca79d4f6ef8bf9bc6e500a14783fadcfc7a42f28da9f5d0ffbbf00b9cebe0ed057ff2a0166dea66c48294f518bc8bbb8ec4b6b51511ce69b92be8b0384265553516915ba182b442d3d2f0cadb6a643c2984f060e338c83fd534f1b77ddf3a7195cb057e868ee39a25415010001	\\xe26cdc99b90c8bfac46f27f31c45709c81b4794798927fba7a5b032a07c1084fdcbe0d536b0f3fa7d8c1512b4a5b9420a5dba6b1de838a85ccc2780c9e8bd209	1671140202000000	1671745002000000	1734817002000000	1829425002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xd30b5e84345cbba6a415698f8804a8944e659118e26cdd84282e5243c0af007e551284758fecb57f743ef26253c4a5e580abe2e6f0a83409f9b059614a997172	1	0	\\x000000010000000000800003bf154499f615a743c445cbcba4a84d132f6f9e1c7be8637044c1179969b71017ed71babce8d782883699074b03eda93c901af12a8b8247dbbdd86065ec2e0eeccd05cbc7df08eaa45cad55deca85bb8e45ee5265a744a87415ce645190f81d0e41cc2ea5ff696045af82d5cc3e95c9294e0d45684c3360dd74e09fe32abca4dd010001	\\x5517b7c9f803b9d120104a16be7fb80efc928e3bc4ec93ccca811af9b4a167ca1a4aab21f4522530e9bb15ba63b7a43436835a75485ba86298602ef82cfef80d	1672953702000000	1673558502000000	1736630502000000	1831238502000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
405	\\xe2effc82f5d4d9cb5123beca98c1235937f6cfbf2628ed5ba8ddc4e6687202a856086959bd181f293467d94fc7a8af73d5df43d60b31f78c91b856b889137499	1	0	\\x000000010000000000800003d702892c34f56600e75e6360777fb3c3d028b0db26ef0391aafae3a1662707d3d1afa0ee421a3325e655a96344bc5385dfdea71a186ce11b4845d12ffecd8fafdbda896a74f6c8151e714508a6169a9f63ea3e45590dc6b2608f34f01e03ea080c3aed5ef020684acb233dcb4563732214f6f381a97f2ca8e1cc4c1a1ecaf641010001	\\x45f53c299e765a43e759f75fae958c14a1ed5e0f2b0e750e52b49540fc93576ac1d3410c018dd9026064b9aabd90753a219a1add18adc074ca3bc7f43737a304	1657236702000000	1657841502000000	1720913502000000	1815521502000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xe387a82a8593f3bf62e468484611eb55d5fd14edc5651c8e0584d42427e0d327afd5566d2533be08781e0eb9f94998e1b1961bde5c3294b16d403922a613638a	1	0	\\x000000010000000000800003cc1b4cb34f95a648de7ec7533567198258af12f78792c309f605f0a30169f49704d17c0f89247822d63e851278d2d152a76d4dbcac98fcac906abeee5a107e5564235d13824cbbaae6fcada4bf00b7658051e30894ea026385c2892037b0ff9a9f0264140caf10d58fa60834e28ad9def038e467a907211278243e680fe1a81b010001	\\x79d005f38d3688a325226448db9b4469c4f1466e77a6623df2526c17fbbaebc3d6dfa6254134706a40d86ead00d41af9139e498eadfb4eaa282c01bfcc1efc09	1665699702000000	1666304502000000	1729376502000000	1823984502000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xe3e3fdfa93e27ec169d7ec330d47d1fcaeac2c2fab16f72441b2bc391bd3df3a3538574204146090496f6a9bff058d59191e6e0e64de26f945a8d17bf7791f9f	1	0	\\x000000010000000000800003c7b9f598f8f12e45d4fee9ca5142178d25908f6a88cfc74448a89346c859828f35eb1731f46e75de517ddc167583500ff2672a996fad89de2b00e0971ff42f891e91f0d992f987f5f230fa41da6e3e695fbf673ba4972af8bf656d8817be0414053c1fb493e768093309c2349705d9cb7c910d5cfdcef720df6bcd5ae12c0f5d010001	\\x0f7bb801a2b318d21f6c181440d0774cf6e9017bf86b1ff3ac32e69cfac2b34c9155c1f1b0859868665bc18e7fc12126a12eb7dd6acdc0888bd15f5324245801	1665699702000000	1666304502000000	1729376502000000	1823984502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
408	\\xe4efbc3d82306519922dffe4d2603d13134b0a660ee7e8e7902e520071db3402e7e09f45c52f6c0408a9d9919b5c5ffa4a6ff9ad258bbb8acdcf737ec4c5fa40	1	0	\\x000000010000000000800003e8b7047fc3a2e463c3bf048af1a6f26c53916e0de4a8a601717c4c1e3aa9119618922340a43dd300e08b62de4b660c0e5cd6d8da00f351467b64958214670b717785438a39ece7b4ebb1a4c864cc5cbf23766517d20d0f7dc7a704872ab5cc3e281372aba1e290edd018ba745168d9f6e5079b5f375d74d89acc613215e8fb57010001	\\xb429db257325d5e1dda2de15b4722e1dde6f9e8db12feaeee3409ab023b83aecb7b9b246df594cbaee3c9f0103c0e2ac83ca88a0530f514e5ad9f216da8e4908	1650587202000000	1651192002000000	1714264002000000	1808872002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xe403c86a9eb70b1cbcaa2e8291e14c30ea88a3a74091eac53083d610c75aee679e90a1dac2e8304e69985119e492f4d4fb59913b27423f28fe067cee39f7155e	1	0	\\x000000010000000000800003cef8b6321fcdffacd888879907fa4a1072c67b9ab763e3f08af2c6dbe9e16b8d3b5c5dd8f1b22529dc1a2e495e7437c70c31ddf6357c5d5d76b8d4f83a46526aca2741f6bbf2c305157a096a5a09fa71b86f5b38fe767d19a098ef95853aff0bb3b8915e71baeb4b27eba38d3e1b054d8105d14b840f7feb84f40d1350ff485f010001	\\x1a3bd3e329d1f432d46b2bd8eeb77d8f0017beead075a46233f44185c389c36c9ec3783e43025a8eaa02d18cadb15f7c263534c5177dcc605703cfbaf2d0b70f	1649378202000000	1649983002000000	1713055002000000	1807663002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xe4671817ddd4d6c3290c2863d99593d6f92191ca222ddff39b0603670c49c8f86283830a44b52e39623059aa1c65beb078849414b3c6f39274457e1f8b8ceb3b	1	0	\\x000000010000000000800003d53a6d9c665b5afaf0ab83577b9f4c150d9097c765fd9bc90042b6cbb3cefce75ac83eb5142cd12fe705f81f1f9da795822b0ef0b82f48b448f12d0fdb68d0333e33b7c0f4c39b64960ed79524aa23d4d6efdbfa4d3f7f093b3a2509fe15d196d6b1374670aa5e4ca02dcb9480e4ef22a880ae9275265c49edddb22e1427bdef010001	\\x5cf0a1429443c24f60b8cbe6cdcff8b08105dd8f87442da015a8a2afdc4b61bbc6f3dba580309e7b75cf2056202e06e3dcccf7e1e275cfb6d8428dd95e8ffd01	1649982702000000	1650587502000000	1713659502000000	1808267502000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
411	\\xe57768368618bb7b83f9b71c7a4f987f531d05d918911706abbc26dfb8bc51c66e671fd7366e50c430c5ba67abab320ae7a2f4357222212ade133ce236939207	1	0	\\x000000010000000000800003c5ee64401c06492196d25bf593de34542c2c567e7d536949d222fed00d53d92f87f6b94722fd40e39ca59040111aa274286e57f650d4b61b79b99ac3aef4e340c61ef7f9ecd54acfc4e8323f56a8d789b8ffc1762b50bc17d83d223c3addae8dc9d912453de6f29cf96b3715e0f4904c4746bb2b4ebcd12278681749b46f2cd5010001	\\xaa33c44f570291b9bf64312981e8126e85f1c55808b0d07153b5611aa9b36d2dfae4ec647d494d5da96a538c6e5ea59efa8952e2e69de319fbd26c8ed1e2d206	1671140202000000	1671745002000000	1734817002000000	1829425002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
412	\\xe687a50a286a13c1b93507ca6bfc44affcf862cfbb23d4f52c8af72213204a1381a67ccb3ae5de7bede0270d108c02fa632549f36c108d8ae6ae6dbdc2f713ca	1	0	\\x000000010000000000800003a4c9bef72107486fdc9b26905b79ddb8013a8ae6206a1c441f8d96721d2826eb5279ff53ed02ae3e1fe3caed7db5c3a3acd45dc2fccc620bd173194acecc4865539773195dbef30748e9c4f33271d744e9eeb4bc270ec51575171cced5efd09ee1cedcccd610b1585111111a22b81a3e688553f15e0c157e70db58615a66b9a1010001	\\x14aadb3379d1d380b935d2fcc9c32ea77bcdf2f4ab1e6495834fa1637e7ef3ed53a0d32e61700e45a42c5916ceab5ff866223b14195f93e82fae74992fe9f505	1668722202000000	1669327002000000	1732399002000000	1827007002000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xe7c71acd665eb0c5e891754c81f871e03dbe9bf005b4860eef411cdbbcdc069379a9695dad1567bd87099c3e679c551a3f947c03054ab621a941a3880a1c504e	1	0	\\x000000010000000000800003c9521d8e35f34fae0fa191b16db3730da645310520705104d387001b36208b3cd24cad1b1460c0f974aefb014c511c074aa7ea82d5bb08aaf008b01096cc6dd376616a9a713cc334f58e5061d87af0e7510a1fd3d5f62d0dbc5fc64b5dded44a8aac44f29d4a5bf8e78f74a3c3617ce561f0e038a7e9d87de30e75d4bf29a80f010001	\\xf9da5648282df5f1457a07dcb47dfc79ab9d6bf54061e36762da7dc94c81eebb3835923ff74a3132ede6ec1e49442e10b36d31e0957c0156e19dd4171a0c6f0d	1662677202000000	1663282002000000	1726354002000000	1820962002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xe9ef36570b1b47dc18a8907941bb642549bd65a38b64b0bac8efac379724b3c85b62ee3a9d04d1df50aaedf9c206dff2b1e8fb702706bb172206d0fe52f20bb7	1	0	\\x000000010000000000800003cf1a621714df5e0fd2812d424a236921d58abba7115c96068f44a8d776fd296feacd0db127f300743f31d21bf68938a12e267a116d894468bf18af21bf0cb04c19495ea3946af55fa6164f1df307fb04d82f674af8d98b8a35d6edc74c391fd75f49419eaca2c774fc1843dd56ee0694c5c6322ca5e88ce38ed7fb7cbc0ed6e7010001	\\x4a67143837053c182fa2607ebf3102d4aededdc5f269b9141b455e46b303e8e91f439c7054771a31fb88caeda40b61ae77801d5a58abce97c9bfc928fe2bf108	1669326702000000	1669931502000000	1733003502000000	1827611502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
415	\\xe9e74b8b4c4f498f412a7c62f54541eb272db02e5389e111b72572e6e6778492f0902db5ee8e413cb17129c6af68923f59e3f6b490005cf4ad83e3a72a2a043f	1	0	\\x000000010000000000800003fda768d6b48aa16d4d119ce1bb3cc71bed032813d9f5a15bd00d8572030f7339f8a017044ab29f7d0fb901b95973ff7aece3b04682a852ce13e09d48da9e49ae38da19691ec36f41e8c286f060e3f27de7b313d926151f4c1f9b8c8cc037d6d2698b3b868864937020b8e4586c47f5af64c16d51adf71d32919b0e79533f90d3010001	\\xb135b62a5139f88286a399431bf55dbbd51288328aa58616d164aaa19351995b893d419db619b18b2f131a8241fe2fafca0b160c0478b7e8504e684b2cb90c0d	1674162702000000	1674767502000000	1737839502000000	1832447502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
416	\\xe96bfad2a4c4e2c901aab08bd358e31f9ebe5fc3f8370e11066ce425a0c2b9e958478504728016972ef615e0e265ba474adf115cae4396bb8f6058717ed7a458	1	0	\\x000000010000000000800003add9c8a839146b3b0932a482af107c1dd0f3b1ff582eccc6970a47453d3cd3bb60dcf5555d7f53b37825ac93e431132ad3111e31e94db78803f5283c22b5067d72d3a715f97224c7c29e72821efa1dfa1dfbd06b31d93df39b401f18874165d9d687c3dbe9486eb372233e235c71b26be2711c79c458309d11add389273dbf97010001	\\x2495e57298bdc1b9c103eaf4925a3884e1080247137e82bf27a46298bb5c7fa9c8999d36246cf8dc1ecc04dfdc41deff287767720b84d013176f351c10049104	1648773702000000	1649378502000000	1712450502000000	1807058502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xebb30bef5cd3c5d8dc2020cb8be41641685631834204d302bcc8af8bdde4a78b5eb08fff046f75b745702a6a57cf1cff1cbd67f88a8d97854665571a8eb84c61	1	0	\\x000000010000000000800003a8a67f54b1f3f7bad074680ace7333fb7ed992e926f9b63bc2f21ca9c0396241ff5bc38b2f6e6a2c991c245a9d48eba75fab8d50549897d50cbd6b16d32c0e37eadacdce448e4d0cd2ee8de542c005fde733c0161aab6e355558ce40b966c6e8d9b64da6879a00ecc683a21296261e877f8823293eb4b300991f67221c8dabdb010001	\\x911a266f6bc04f43d2da561c11cff4b6dcc616a8ba78117016f6ecad9e69332153c9a09d37c8602cc7289caadfbfb2dcb62f06c238f7dafd4c11140fc59a0407	1659050202000000	1659655002000000	1722727002000000	1817335002000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xecef1afd116c712d74359bc598b13ecb6b86e2b852fb665cc220e4a76091003e11f4c603c38f35ffe327893ffed219f63d5cca222f7871068fb62f264c68f413	1	0	\\x000000010000000000800003c79a61fc8a3c20d61a4eba6ce8054d774c2bbe6b46889add302addd8cfc9d9953e70e380e47dfce2cbd143305c8bae50debb27d64cb97c97b23552d840d5972ab73deed777ee0fbda922831d0d37919ab0862e8d9f908ebb44a4e4cc7ae78d811e1c09a31b22a7f2215d4a255ce426eb9baed44ee16f48d5157f3d9b94b79241010001	\\x8588661096798fd25cdd48d93dfc4939b65ab06776cfce4014f9944b418eb9340f89eff46dede0cedfe4d96d5b99f059e5c5b6df99c800b20c48f654a8a96e08	1654214202000000	1654819002000000	1717891002000000	1812499002000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
419	\\xf3df47bd6b6e86f5339c32d2d71f77bf593f34f58a706cab874206e4d1fd15f09199a2d217ff208cd423c5aa8c1c811a18e5e5a69e53803b95a072831cd3cdfe	1	0	\\x000000010000000000800003dd39c624a581e6bc67e0eea2cfbb3822ae3e102ef79e4d6d090b036834035181bce9f4ad0817c71606aa934f94ec2366531c4b4ef59e0039ad8fbc06c38c26caefacc2d8b0f780a965f7a7e277e84e007e9d2ecd5caa3c92204eddaa27cceb8ba00cc065423891d3a7bd500c0eb4cfd54eb0db7af2131bb41ef4b3deb048aca7010001	\\x196fea8032059e4e33a1f249a7f973cfe96a129e3b521dcbfac6e15901778b31e3388c1dbfa24edfc7d68d2a3cc4d12a90e19757bdbc653aa54096548d962007	1660863702000000	1661468502000000	1724540502000000	1819148502000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf52b55aea940aff2856bb9be201cef752bbea75588ba6629fb28468f7e4ca81d2c000b8fe05eb483615442826e2050c4742a89350bad611dd10a9cde0eab6cb7	1	0	\\x000000010000000000800003bfb0805ec028d7cc91a4203a4298dea7ef586534866bc504f313dd09964ee49ee09346933fed0474433e73ef5b39fe4d1bb637df6405b5b934428086a384cab5a6f460fbddfca214b3ff57ba1cc9dedf0a5d08642c50922bbd992c2d9be51ce53bb6f710b2e59f80bf17c821635875a2c99601ba835f5bf8078362cdc3d3939d010001	\\xe8dbc518167fb1ead34ae36517d0921a8ae0993a44b2c54822641bde5ef9064c59e34e99c1f263565644659f7fcc1d12d6e16957954a6421a71fa82ebcd70601	1660863702000000	1661468502000000	1724540502000000	1819148502000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf807cf10dbf4cb187b60476e6c714da7ceaeac72e86eed6b135246af003742e5a11f1e59786d2e4f56009bed014e3e5cad9a0111dc3feec7e58cc382029f3a91	1	0	\\x000000010000000000800003e621c2069e720f4b023da68aae1f5cb74a9b1f6bc053af8b6db73671072ea95490a4386c44825e9fd42632cf388b7731aec64363218273bc5c961ce5afbe7c31c0e82718ffbc62ba6a03615f9ae710d9728ec3dc7a904a4c9212f17b857d777c2f0e146da22624d1127f5a497901e393661b162709e292a1998759fa950624c9010001	\\xb47852f28b48903ab18f2140f3dd7f8cd6d7c9676913140f7ca3d630bb33dd9bbec1cb1ec1a0970bfdde966bf8571b113503e77bd75f80a083db3e4511d5680c	1662677202000000	1663282002000000	1726354002000000	1820962002000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
422	\\xfa0f7c4dce9ad4bc25e0debeebac524cdf120e4a393ffdfd69e09c25a63f8cbddd5d9484f02feb2f4519b0f77e62305c5778828e3e80fdfc08a036e3e9924fd2	1	0	\\x000000010000000000800003e18e9a5563cded4f670df271d04f1621bdfbc8128e5ad1632d3fd4020cfa8294cccc7ac9bcacb40c2c82968f84956648a5a93ad8a3c3d492e2ac4d839c74a3843ef3094704e9ca6c0dd2b99ca622d33fb8a9f22259056d3ea57ffa1214268c3a407b939bc90a0090fbe103fd0548c45ea54c1b7ec5d353810ad2f3e43b43c51d010001	\\x7f2032f5dfac0776c1821fd7f4c7acb7ffe8ab52f05fa050fb5cd791bb3743342113a8805046d0eaa2632b46e8efa841880aab685f3dd11602bdb03504a9070e	1671744702000000	1672349502000000	1735421502000000	1830029502000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
423	\\xfa133ed392cb2e801f13bfad05ac2b4dc7f0bc69f51cb15ce79417ee2114298757cdebac3a87d66d33c9e43a0bd79e59dd7f509a711cf57fd49f66860edfed81	1	0	\\x000000010000000000800003c2367952316f3b9c636f118b8885cf7af16c1e7b61b931dc94b4f4e0dd8de3061b3f8310d4456fa59e42112bfaa8d108508526f1cfadea45d0583e160f1d86f01f0e1f50c83c44eb7b6c8860e0828236285068eb2c3fd025ee76967dcd52ab4c3fc35e1bd06d6f263caa0590d13c2ed60c9ff6e272df618bb4147136f893efdf010001	\\x20c730171ab6a6007358fe56e65f9df8f0dce3932192aa099a3960d014e38d9b2868ff08643191ecf8bbbe67ce48b3b69074ce621d64389c3d8c2e453be2640d	1654818702000000	1655423502000000	1718495502000000	1813103502000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
424	\\xff1bbb50138bbe2324dad1eea345f6baaf8e54b8d9e990fd9d0d9f05cff5b5303700b5ad4e70ca2f58b9bddf43cac7b2952127982b353d91c84b426220c1213c	1	0	\\x000000010000000000800003c979a3d7d384ea21c51c5caec23af4fa7e9f444370181cc6f7f311d1defe3a5b426e792e2d2b350c00d750f34c9191517f8d2c5055f8aeebdf4a6e31f821ccfb30a5fda69189efe7787aecebd006d52c5b67b26c3e6def75d0c3b083fb0f5bf3baaf532a18a9de9143f17f37e6a9261a1981f4e090acd608b3ef45cd170aafaf010001	\\xd799d4603d19f264c0b899989cd2c4d755c540b71abd69e86da09777afd2e692060cc3fa188b3a4615247e1a89ae0471653efc7e6a084566e3a51600e4e50809	1667513202000000	1668118002000000	1731190002000000	1825798002000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	1	\\x4f2f580c30b97a87fa7494929dd14bfdd573666c888699659f866581e65de946fd88949f99a18e8330e0963a644dc7fa82282a919e309aa348fe8c6ec0a0dd98	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x3396a5bad3796806a3953ba7bdc481bd601ae6f4b681dcc37579243675aba860a24aa05e1bd0b0919dcc3c4170897b4e4c67490631df162632f4985e29d95f35	1647564734000000	1647565631000000	1647565631000000	0	98000000	\\x6c961137406f123d4f40c274b612df807d01fd59bebf433f1de743e9541404d9	\\x0f84681bdf5f3b2192e1390c392ebecdf560401cf6036ed7afcee0ca9d43a13e	\\x9bdd98131ddb6994bdf4535cd03c30bcd609ad1988f7a217605b4cb4a8d92460ac56a7256bc09222d7d070009416ca3e6205e6978c3c616464e5cbee3c82c109	\\x5886a7bc94b7448b8bc4e3c70b65545e0c60d7ff5f7dcbbf10706fe469194415	\\x00000000000000000000000000000000649bc80b987f0000000000000000000000000000000000002f97b9edde55000010a6cc35fd7f00004000000000000000
\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	2	\\x008617d0ce2a5ed996d9c93c02d9801e4a0fa26d3a2697e9dfd7c48eae85748648a83544a7bbd5a569e7e653f774ffb3d67e5f754156227143bf0b59820d2698	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x3396a5bad3796806a3953ba7bdc481bd601ae6f4b681dcc37579243675aba860a24aa05e1bd0b0919dcc3c4170897b4e4c67490631df162632f4985e29d95f35	1648169568000000	1647565664000000	1647565664000000	0	0	\\x0361b3f8f97464cd3d5441ddb1d01535bd78c0484b060ad2463ff7d7641d7f5a	\\x0f84681bdf5f3b2192e1390c392ebecdf560401cf6036ed7afcee0ca9d43a13e	\\x8f311c784f2412ee299c30176529ffbf5c3c62ed09395b970fcf05f074c6014b2a8546f6b0a94065841761808a2e2982d893070e602750ae7be64d3c59127908	\\x5886a7bc94b7448b8bc4e3c70b65545e0c60d7ff5f7dcbbf10706fe469194415	\\xffffffffffffffff0000000000000000649bc80b987f0000000000000000000000000000000000002f97b9edde55000010a6cc35fd7f00004000000000000000
\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	3	\\x008617d0ce2a5ed996d9c93c02d9801e4a0fa26d3a2697e9dfd7c48eae85748648a83544a7bbd5a569e7e653f774ffb3d67e5f754156227143bf0b59820d2698	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x3396a5bad3796806a3953ba7bdc481bd601ae6f4b681dcc37579243675aba860a24aa05e1bd0b0919dcc3c4170897b4e4c67490631df162632f4985e29d95f35	1648169568000000	1647565664000000	1647565664000000	0	0	\\x10900cc6346898481714962591c7bc68dcf17bd0baeca88b42491203e44fe521	\\x0f84681bdf5f3b2192e1390c392ebecdf560401cf6036ed7afcee0ca9d43a13e	\\x77ac99f303a29f0b201d886d2a5e11086c61470992ed1f1cebb3e93ab88ad33d6ae19ae172eb026c6b674d0ead0a5729dfd5dad035a2eeb7776d2b8d590f9000	\\x5886a7bc94b7448b8bc4e3c70b65545e0c60d7ff5f7dcbbf10706fe469194415	\\xffffffffffffffff0000000000000000649bc80b987f0000000000000000000000000000000000002f97b9edde55000010a6cc35fd7f00004000000000000000
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, coin_pub, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	794197244	\\x6c961137406f123d4f40c274b612df807d01fd59bebf433f1de743e9541404d9	2	1	0	1647564731000000	1647564734000000	1647565631000000	1647565631000000	\\x0f84681bdf5f3b2192e1390c392ebecdf560401cf6036ed7afcee0ca9d43a13e	\\x4f2f580c30b97a87fa7494929dd14bfdd573666c888699659f866581e65de946fd88949f99a18e8330e0963a644dc7fa82282a919e309aa348fe8c6ec0a0dd98	\\xc64902448c28dd16e9f2919c36dd95592a22199212eaf1164fa06b192a21a450cea127e60b22a9b5220b6afa3a980666d5be171bf8f9c48b09e395d964523b01	\\xb70f79834c2bf0c79b7892cfd0d0b3a5	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	794197244	\\x0361b3f8f97464cd3d5441ddb1d01535bd78c0484b060ad2463ff7d7641d7f5a	13	0	1000000	1647564764000000	1648169568000000	1647565664000000	1647565664000000	\\x0f84681bdf5f3b2192e1390c392ebecdf560401cf6036ed7afcee0ca9d43a13e	\\x008617d0ce2a5ed996d9c93c02d9801e4a0fa26d3a2697e9dfd7c48eae85748648a83544a7bbd5a569e7e653f774ffb3d67e5f754156227143bf0b59820d2698	\\x3aef9034290d3c43bfcb95d735d4eee4b918069266aee669da32992bba4f634525c0e5db34babcc2a9e732a9f0c4ea81200126981d1b88e8b5c14437bc4dc30a	\\xb70f79834c2bf0c79b7892cfd0d0b3a5	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	794197244	\\x10900cc6346898481714962591c7bc68dcf17bd0baeca88b42491203e44fe521	14	0	1000000	1647564764000000	1648169568000000	1647565664000000	1647565664000000	\\x0f84681bdf5f3b2192e1390c392ebecdf560401cf6036ed7afcee0ca9d43a13e	\\x008617d0ce2a5ed996d9c93c02d9801e4a0fa26d3a2697e9dfd7c48eae85748648a83544a7bbd5a569e7e653f774ffb3d67e5f754156227143bf0b59820d2698	\\x3bfd47b15160fa9424af412c20fddf448ab16a0dde60ad3ba0761ee5c117f9c652bb2c13588b6f008e76ad01e6d374cd12015cc18559bb168050ede04a05340f	\\xb70f79834c2bf0c79b7892cfd0d0b3a5	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
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
1	contenttypes	0001_initial	2022-03-18 01:51:42.90954+01
2	auth	0001_initial	2022-03-18 01:51:43.06349+01
3	app	0001_initial	2022-03-18 01:51:43.189356+01
4	contenttypes	0002_remove_content_type_name	2022-03-18 01:51:43.202325+01
5	auth	0002_alter_permission_name_max_length	2022-03-18 01:51:43.211212+01
6	auth	0003_alter_user_email_max_length	2022-03-18 01:51:43.219429+01
7	auth	0004_alter_user_username_opts	2022-03-18 01:51:43.229336+01
8	auth	0005_alter_user_last_login_null	2022-03-18 01:51:43.237143+01
9	auth	0006_require_contenttypes_0002	2022-03-18 01:51:43.240297+01
10	auth	0007_alter_validators_add_error_messages	2022-03-18 01:51:43.247431+01
11	auth	0008_alter_user_username_max_length	2022-03-18 01:51:43.26226+01
12	auth	0009_alter_user_last_name_max_length	2022-03-18 01:51:43.273948+01
13	auth	0010_alter_group_name_max_length	2022-03-18 01:51:43.283456+01
14	auth	0011_update_proxy_permissions	2022-03-18 01:51:43.291672+01
15	auth	0012_alter_user_first_name_max_length	2022-03-18 01:51:43.299277+01
16	sessions	0001_initial	2022-03-18 01:51:43.331668+01
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
1	\\x03c9bc46e1ebadc613034a01886c7a508ae7ffc27797dfa510b706346c4f6d05	\\x07b1dc27bd531358fa4f88957f5b3b8b1f567ea925c583564e81689e658ca2993991b367d01eea87c8c0e3015d9ba6e8613ba34abba748cbf556e4c6d77a4703	1662079302000000	1669336902000000	1671756102000000
2	\\xa69aa74bc642b3c1acdd48e6e5780cbb50934578aba7b032c1ea176a3ef4c502	\\x556442b54a3a82b68b0ac2d939c5da6da84461898316718aae2490f009822f0d3255bdc5caae7599798cf9c705a939e0f8723d41a905c176289f00c02282700c	1669336602000000	1676594202000000	1679013402000000
3	\\x2ed59928d829a3e3fd075c8c6cf25c23b4b4d6e37329510538cec2770e6a38fb	\\x1444107eca762474ef2d01a4cff8305fc34b183cb84d8533f2fdaafe5add62280f777ee3531064ef88475e31870f7b3d28694ab73e5e0ec8f705ca1651a12003	1654822002000000	1662079602000000	1664498802000000
4	\\x5886a7bc94b7448b8bc4e3c70b65545e0c60d7ff5f7dcbbf10706fe469194415	\\x9fb8c3634d4b66f713f115fbd52f26803c7bdea0ce5094ed771a9e534ecd9d496ef5dc32ab179549d6b8d4c4aa2b22818032be931e9d13510bae7079ea936701	1647564702000000	1654822302000000	1657241502000000
5	\\xffd16db65b215946280a600281e5af198ef5a99d7e6abd4be041c0813b4725c5	\\x98718ce723040d8facd9bcec279238f1357930da8e2e74911f7e4ac0970342e646b4927a72ae9a80ede431e327094582ab9f5b4a97b25abc2eb04c6e8afdbf02	1676593902000000	1683851502000000	1686270702000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x18834a21d98f865756648f91afb4692592d58f914a1099c04503bef40832c96d1d2ea1a82d32e16a3b85b32c8d5665b4a5f6d67466c43c77e2efbbeae37a0004
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	204	\\x6a24b03edbd3fa46c14ef8c184571f7110050c2579220112c2a30a9283bce8b2	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000007d44570ede873110bd521f48baf98467e2b98bc4e23e4ceaef3f854d8aa8c2f803df090227692ef51731ce5eab4632b2490783ead699b6c8607060f596ba31c849ba2371bfbcf76536d5a92ff848e71d80b159b90b0bebf926401c8e3ccfeb81f49efd71ed225975211da520dc11413d23cb0733f9450bd654790f1aeca04deb	0	0
2	154	\\x6c961137406f123d4f40c274b612df807d01fd59bebf433f1de743e9541404d9	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000001dfb731962cc2729fc01488e0b65ed451a9e4adb9109cdae0b2c68d9ce7b6302d9b07d282bfe5a2a00141fede6b09cdee1361f33847c23315455f71dd0249eb43a878948c3a51bdd5a7757d6df39b8d5962d1450bec70087e5097596112bd4387fe5c4683757e31c973abc7296497e909b0d287c5a13ccb246a6154366db5b9	0	0
11	224	\\xc612336078599602363266ded6cafd3af31789fb87ceb4c4271c29474207a4ae	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006b5268c155138b2d92692b3c7f33a7e1c3f64a21ebc84aeff4d99d66ca84970ae469d24110a6970244656583a433579a34ba8d97c0128a9fa4ac0bb055466815a4ed53a1fc16787e4750169c8b1b742a4e66ba77fd220abe967fbdf2a89a6e1809fcf9e0997684f15d624d5b7accba932144465116460c7391224fa2de7e76e3	0	0
4	224	\\x3479491fb8637ab1d821033658ec38a66d5b210f68d144c2de00226dbdc4af73	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004b345e617814b2f4bf7ffc1bc68acaedc2a5425b3e77465c008e8b965a9d08aa7c2c1bb2aa2cb7de49887b057e8c8ef206db97a942b4b162ff3b69d15ad1f4a9e8bef197018efc480e46c07be99cd339f5a32a2d9acaee0294f924c7d9f99ae8e28331209d83af499d54b54a43261e16b7ad0e6167e762c9e5537762c8024fe1	0	0
5	224	\\xf040032a2e9c9ce179b6f9ce642d4e3d6d52390c19b2c2ca0ca07eee0377ec94	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006dcaaee444af4feb6f575cfbfc12b0a0f2a8f91f04e724d63d53545019bc435f34269ed41fe79cfffe4f3eb9ca6c4ac59d1500add3c3715d3152c5b76c0b29beb4605605a95a80215e0c82165b6f1393f44b4e8ddd64daaa765c0e4d9bb8ed0db61b8175a941bdc0f6c6c7d68ee47423c82ae89da65992d91d51d18622e14012	0	0
3	213	\\x060d6345e173c97c20b68c0adf21d9eb60e99035aed4b7c7ae78502a6c72e7ea	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002119f66c78518c1431a3b7aa938fd4b65d752e8a48a9450446a0e61a1074eff9b6991119f211c97d4b4cc6767eae445f9c2eb71473b7bcbbcf56fcacf76425049b09e03690be5bb3262567e38df45db9f8713d2b59d68c49c33005f4eb9d5c2dc70e62ee8524066e40366cedafd14ce4cce3280d845a3c9aed7aa67506a188b7	0	1000000
6	224	\\x70caa4cfaa5f8d22ee22107e1fd22955be526ff33d2d27406fe403101c122cd9	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000006637af63f912f855efd6c9fc0c2fa33bf33529386a1a452b3f0a1fe6bff57040c9b5cc2e6ddbd6a3dbcbe291b88d4983089e374c632ba35a6ab4564d33110fd2d34d4523b4a32b50f24ffa99f4d864a308793432165df51890727d0c610d9e8a0df5e72d99e0257a4dcd61829299919683c4c494922a5796ec8c22d6603f04e	0	0
7	224	\\x52eceb87b25004343567783f40f7dd3dfd7c4b1ac4c520d4c235fdc9b3624883	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009c6f6dd488db592f2e2165e57c47025325c8956054981924efc0db6a5bc475dbf6334ef5ec3b87d3e6dd62e4d21eae4a13d8b24c4fcb9fc3affca942a4a6f8fd552688426003138ce0fc659040ee83eacf79dd6bb9ad74d984124258836455037fecf4cf52635dc74e66c5095f2b4cb5af1c247ae27d872d8373dce347f772ff	0	0
13	113	\\x0361b3f8f97464cd3d5441ddb1d01535bd78c0484b060ad2463ff7d7641d7f5a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008ef9105f161779567623ffc0fd76fa8527aaf239a76fdb729a3fa9adfc99e8a1014a3b22fb0589001ecb05a7ca767ea63f7b55a0f28fbcc2610af2fdafa35020c9b7d3962ab6015058f3c85b4f3039e10f4e78416b10e0bbf0b183b08da6bf4851fec2a18bcb5efd8854d3afb6d56e55a6d24d8c1eb565e4cfd37633ccb5af4b	0	0
8	224	\\x64a83b4fa6148bec86d28d83887b56b5199356fe54d2d609115d80968ae10e5f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000068040ac7d3722702a37149fd830603bbb21278023807ecc2a7ae3a6555a6f0d815084d75b1ba929faec3e282de6b7eeaf1cd081382fea671c3ef8a70be4c253a26fa30c639dc615827f0fc3a9fa9eb7004d48a52cd0e2d7dab4bae35edd4c46af98a4bfce1a08378a165290e9b973ffc2aa9dfdd1a45d2b16b37dfefdde9ee4e	0	0
9	224	\\x766fb6d49f5319c2de7bb669bb2aecc60b09502fa637615c0a8225daa1e2dfe5	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000008b0e58d4e23b5eb733e772082c48fc5ab83d02cb4475be8a4c4306cafd1a2842dee7fe65e5d5c670de449ad1220914bc118796dce9deb0d83074bc30abb936893ae6ca8b59ca0e105e90a45be4392f91bbecb9d2afb040e71e85e96c0e1512c12499b6892c57c9c7d44ab82f90f9913f1f74951acdfa1df950839db8ca6e03e5	0	0
14	113	\\x10900cc6346898481714962591c7bc68dcf17bd0baeca88b42491203e44fe521	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000085b641dfb16519aefa8dbaa400813fd280c7284c0315d456cff45c96ff530063de9a7b2cf0a07df118559285f63f451a95cc951419f5418b19710048d14d646fa39258ff337beda186637f4d98a25a75133b65de589e56a85c1b7834c268f4694d4d187379d8302660040eeedbac79dccb13d924b9e5b69d55d7e5ef9a2dc00	0	0
10	224	\\x79a82964fd33f3b3138ef2a2b16aa33a744c445bc47aa5986140875ac3dd32fa	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000081c62948170bd48e985f4dc78608d8bb96874e2f4c402f3cdf0d0f26e40fe841e599790e881bf702f1cde785668f8e9b3cf1f53755eb172214be93b3d08054dd7cdf1107fe310ca005cb476de9456c9e7200ad3e5a6982f34cee2cccd05341216886849d06e880d4a97c9419a335db8cbce4ee2dc566a83c558d693d7e833210	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x3396a5bad3796806a3953ba7bdc481bd601ae6f4b681dcc37579243675aba860a24aa05e1bd0b0919dcc3c4170897b4e4c67490631df162632f4985e29d95f35	\\xb70f79834c2bf0c79b7892cfd0d0b3a5	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.077-01Y6R89G7TV10	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373536353633313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373536353633313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22364542414245504b46354d304438574e37454b5656483431514e47314e53514d505430585347564e46344a33435844424e314741344a4e3042524458314334484b513633524742474835584d574b3337393433333351525034525346393632593537434e594438222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037372d30315936523839473754563130222c2274696d657374616d70223a7b22745f73223a313634373536343733312c22745f6d73223a313634373536343733313030307d2c227061795f646561646c696e65223a7b22745f73223a313634373536383333312c22745f6d73223a313634373536383333313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22574745504b324b4e52334a3935483848454d5838574d5838423445375a4241454e58594752524a58523230443550594430353247227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22315932364736595a4257584a33345131373436334a424e59535154503047305759523150584e5846535647434e3741334d345a30222c226e6f6e6365223a224a575445544a574858483031524b34475730574256524554345931505a3650393843414559525243425634414436465938363730227d	\\x4f2f580c30b97a87fa7494929dd14bfdd573666c888699659f866581e65de946fd88949f99a18e8330e0963a644dc7fa82282a919e309aa348fe8c6ec0a0dd98	1647564731000000	1647568331000000	1647565631000000	t	f	taler://fulfillment-success/thank+you		\\x9e12e65e65257d9237ac7ffee70e71f6
2	1	2022.077-02W3MB0JBGEHC	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373536353636343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373536353636343030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22364542414245504b46354d304438574e37454b5656483431514e47314e53514d505430585347564e46344a33435844424e314741344a4e3042524458314334484b513633524742474835584d574b3337393433333351525034525346393632593537434e594438222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037372d303257334d42304a4247454843222c2274696d657374616d70223a7b22745f73223a313634373536343736342c22745f6d73223a313634373536343736343030307d2c227061795f646561646c696e65223a7b22745f73223a313634373536383336342c22745f6d73223a313634373536383336343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22574745504b324b4e52334a3935483848454d5838574d5838423445375a4241454e58594752524a58523230443550594430353247227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22315932364736595a4257584a33345131373436334a424e59535154503047305759523150584e5846535647434e3741334d345a30222c226e6f6e6365223a225838475048393451394346303857474a5059584244584557394d415a3359355645434b384150525859394a3151455739354a3130227d	\\x008617d0ce2a5ed996d9c93c02d9801e4a0fa26d3a2697e9dfd7c48eae85748648a83544a7bbd5a569e7e653f774ffb3d67e5f754156227143bf0b59820d2698	1647564764000000	1647568364000000	1647565664000000	t	f	taler://fulfillment-success/thank+you		\\xfc770c3f042e7ae4519bf6b11e664b90
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
1	1	1647564734000000	\\x6c961137406f123d4f40c274b612df807d01fd59bebf433f1de743e9541404d9	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	4	\\x9bdd98131ddb6994bdf4535cd03c30bcd609ad1988f7a217605b4cb4a8d92460ac56a7256bc09222d7d070009416ca3e6205e6978c3c616464e5cbee3c82c109	1
2	2	1648169568000000	\\x0361b3f8f97464cd3d5441ddb1d01535bd78c0484b060ad2463ff7d7641d7f5a	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\x8f311c784f2412ee299c30176529ffbf5c3c62ed09395b970fcf05f074c6014b2a8546f6b0a94065841761808a2e2982d893070e602750ae7be64d3c59127908	1
3	2	1648169568000000	\\x10900cc6346898481714962591c7bc68dcf17bd0baeca88b42491203e44fe521	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	4	\\x77ac99f303a29f0b201d886d2a5e11086c61470992ed1f1cebb3e93ab88ad33d6ae19ae172eb026c6b674d0ead0a5729dfd5dad035a2eeb7776d2b8d590f9000	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	\\x03c9bc46e1ebadc613034a01886c7a508ae7ffc27797dfa510b706346c4f6d05	1662079302000000	1669336902000000	1671756102000000	\\x07b1dc27bd531358fa4f88957f5b3b8b1f567ea925c583564e81689e658ca2993991b367d01eea87c8c0e3015d9ba6e8613ba34abba748cbf556e4c6d77a4703
2	\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	\\xa69aa74bc642b3c1acdd48e6e5780cbb50934578aba7b032c1ea176a3ef4c502	1669336602000000	1676594202000000	1679013402000000	\\x556442b54a3a82b68b0ac2d939c5da6da84461898316718aae2490f009822f0d3255bdc5caae7599798cf9c705a939e0f8723d41a905c176289f00c02282700c
3	\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	\\x2ed59928d829a3e3fd075c8c6cf25c23b4b4d6e37329510538cec2770e6a38fb	1654822002000000	1662079602000000	1664498802000000	\\x1444107eca762474ef2d01a4cff8305fc34b183cb84d8533f2fdaafe5add62280f777ee3531064ef88475e31870f7b3d28694ab73e5e0ec8f705ca1651a12003
4	\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	\\x5886a7bc94b7448b8bc4e3c70b65545e0c60d7ff5f7dcbbf10706fe469194415	1647564702000000	1654822302000000	1657241502000000	\\x9fb8c3634d4b66f713f115fbd52f26803c7bdea0ce5094ed771a9e534ecd9d496ef5dc32ab179549d6b8d4c4aa2b22818032be931e9d13510bae7079ea936701
5	\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	\\xffd16db65b215946280a600281e5af198ef5a99d7e6abd4be041c0813b4725c5	1676593902000000	1683851502000000	1686270702000000	\\x98718ce723040d8facd9bcec279238f1357930da8e2e74911f7e4ac0970342e646b4927a72ae9a80ede431e327094582ab9f5b4a97b25abc2eb04c6e8afdbf02
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xe41d698a75c0e492c511753a8e53a8591c7fad4eaf7d0c625dc080d2dbcd0145	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x67a888dfbb404499edceac25572c93c900d111ef1e3f35ed6fd5f7fa71cb0b499a6d477d407a73fc05520eed0a0bb1b43fce5299a6344be8e686385c82fc7301
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\x0f84681bdf5f3b2192e1390c392ebecdf560401cf6036ed7afcee0ca9d43a13e	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x26e6f18797e274fb4f1606c70235decba5270a22820eb2bff4683286ebfec931	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647564734000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\x6a24b03edbd3fa46c14ef8c184571f7110050c2579220112c2a30a9283bce8b2	\\xc39659a7633c03fb05254739ca2c060f3199614513c7ca290d6eb2aac3a6e9e30ddb1ed8fc19ecad06cd0969b621c1b9a9d79c53cd3006f63de03994db540306	\\x9df22fcfb4e414aa40d41d1f46dc0d5149bb4a91cc42c867fb428dedc55de09f	2	0	1647564729000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, coin_pub, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	\\x3479491fb8637ab1d821033658ec38a66d5b210f68d144c2de00226dbdc4af73	4	\\x305dc236cc1d88379aeeda1aa471543450540f02ad4e8f81fcb4e48c61a62834464588eb53a33c6c1b1e656f70eb4eed833438496b5ab666f82ebf72558c080c	\\x765c2fcd83e41a964eac301fca3ac2ec2f12167b6f93117f92a5791c2c114b3e	0	10000000	1648169554000000	6
2	\\xf040032a2e9c9ce179b6f9ce642d4e3d6d52390c19b2c2ca0ca07eee0377ec94	5	\\xe5f10f19437905b8fd23b9e30cc518c22e1f9f84a329a9aca626ecafac9c00651d1318b916f728bf079698b1ea8bdc4bfe4c9e9b164940fe042854bb96c64b0e	\\x435e342f6dfa3cbb23dfdbd739bcdb1688c98aafb85a01b3e40f9a9a35c37904	0	10000000	1648169554000000	3
3	\\x70caa4cfaa5f8d22ee22107e1fd22955be526ff33d2d27406fe403101c122cd9	6	\\xe44e1a281ffe08225b232276b2677534ceb61f6975298bff28a2ee52b90e438a97be0b8293055426af8c8b56bea5718d74856900cb82f9eaf28118d5a035e800	\\xba451627342f2e0f8982f07703c02d75b916b6e39ad9c4df0a6f99dd953c331a	0	10000000	1648169554000000	5
4	\\x52eceb87b25004343567783f40f7dd3dfd7c4b1ac4c520d4c235fdc9b3624883	7	\\x88c2c29b616aeb78705d25c7bebae933adee58f89f92f29cb9823721a7937e151e9871d94815d2eca93c20192380901e847575349e013ef6644ae2805b492400	\\xb759d5bcd80067a81936e5fda1cbb1b7f10cb1bd17cf53b3a1ebbdf7f5c9562d	0	10000000	1648169554000000	2
5	\\x64a83b4fa6148bec86d28d83887b56b5199356fe54d2d609115d80968ae10e5f	8	\\xf2db6b5cc169c733fcd73bb5901e34fd947797138f73f7aad8ca443d72e1ab127b14ed4fc6b1a45856a65f93f46cac7334c27fbe0885bcd1b511b091ff057c04	\\xd9f25a10c93bfa215ad6860ed0960df8b972dea1f2344d33b299dbc5ae2736dc	0	10000000	1648169554000000	4
6	\\x766fb6d49f5319c2de7bb669bb2aecc60b09502fa637615c0a8225daa1e2dfe5	9	\\x8e10939dc1048913120cbab3b5da5b88886ba0ee0d4b5f14e5ad78e118b1748a2ab7d3aa99b511056c6bcad3767b165fcd0f93fe754047c1be40134cf3ae630a	\\x13f617c7337d60a6296d0ca5d34195191748fa8edec9ea74090f2ade29bac512	0	10000000	1648169554000000	9
7	\\x79a82964fd33f3b3138ef2a2b16aa33a744c445bc47aa5986140875ac3dd32fa	10	\\x7903e8194391adf49be3afe1bd907c4c81b2dd7336cc0a4e97ee00474ddcdc2f6a86b3894b325f4e11542fc5e6e112864ec96842103b825f508afd0b9223fe0e	\\x996f39debd5226a65f226f89a8ccc961a79afda71b1aa5743d3182753a055ae7	0	10000000	1648169554000000	7
8	\\xc612336078599602363266ded6cafd3af31789fb87ceb4c4271c29474207a4ae	11	\\x172925c0b164562c5e775defeac737941a4f0623ab06a6cf0a45d9cb10ac0001897f3dd392c81f5a721da752d0322819ca1a6fcffd3b8d7d48cf32471ceb6f0b	\\x098f41268b9e057bb6118bd94f09bb64c0b172fd5dea2130215cd4f1edbedb0f	0	10000000	1648169554000000	8
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x0d97f11e48ec13b417c33383269f5603d4a99ee091760088d08eca9f879d6c589069381bde0270c360909f9d27c94517fcfcce5d98c30cec7c66404bb097499b	\\x060d6345e173c97c20b68c0adf21d9eb60e99035aed4b7c7ae78502a6c72e7ea	\\xd72b708ef744276b07010ea2ed555a54c46c66441b060dc498727b13da687e77562201df62696f6a051d332642b4ffd6b52e1e7758dd11f0935c4e1b3db1920f	5	0	2
2	\\xc1f1cd663e99358ed03292a1ff868ce0953fde5c5c5faa6517d8fb4cf479982efdef8ba731f40fb613446958fcd7628137f0f90a61bb51039773c4d3273aac5c	\\x060d6345e173c97c20b68c0adf21d9eb60e99035aed4b7c7ae78502a6c72e7ea	\\xc393dbbdb49164f4135e9700d1ed146ba3cf001758061c1887c4a03d62a44d665fd1dab861e148c3b12611ee8c708ce48cd68a088c6e6341982a3bec36521806	0	79000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x589434fce026ef181e379cab7ae660f7846fd45d585a57c3435038041c1b98fa2b13aee5ac340f98a585ee58b98048c5e75a8a57a782786fb1304edc12ea9c02	314	\\x0000000100000100040b1f31e0ed9aeb9eb083961839765a5ae0c34ad1081372ff4b27ac3aa7b380f00d7d2b3728f3674cef8e1832d9ad73ff2cbbea9cf3f2b398a444506c4ca5adfbb41f16928b47f32dd97553867a8a8b3b989b6e220a83b321476049a12357eca76dfaf26881b47782cccf4a36121c4aead8e79dba7b731c328e4ae5e09d2d4c	\\x4550048912d3a198b641234eb95506117cac2f08a62af1980b49b4e913e731333f06ab619a0b311e13c640ee96ad020a62661ccf45c2dcc2a9c4c0cc9116319b	\\x000000010000000189e7cdb2fcf0adc1343402658930085af712122f5134fec404f828c5085c39e088e53ccce81aeb21d3d93bca29ccc6c52f510b10d48677a4d2b0baf9b3d0e6cc6279bba06eb4ddd9769a22371aa88ec4d885aca34894f1511dc5a9d865fbe26f45b03783bf9d03946da8287307bc9bc349010e34a3e19848a2a029e05630e469	\\x0000000100010000
2	1	1	\\x06165dbf50e304d263195deff87ffcac161f78edf73cd2bb7a9adef5b537343e248799582d2b3a1370fd7cb4c4a161369cd62fa1a3811991b6d73123f17fd203	224	\\x00000001000001002d975ace6dd69b83975a05c65cd926faecd702f14f34096826b60c119dc302f7c549f542f522c0f6915535a772e51d412f833b1e8199d6503fb7956e72e7db7d310e707256cc0877289b322eef3cdc8c4e8c68e6ef5af29fa8c533680979bd2fa34562e5bb63bfe8ac51e146f0b9f2f8b4d249f971e21842d49083bc3d43fa40	\\x5926a433ac711a6249cec600d56efba2d408839ec654f63452e9614127b19a5151909e5d5f2b22191266a9cfe0e05af8c85e77e985f2d5f846cc9776b4d84227	\\x00000001000000012d3184f0b1d40e3c674596f66c4989cc22464e135a1b637a3646cb14f9588a46001160e727aed4dc4c0aa10ccdf1ce4869deb659203b5364a765af5e07f61f23ce1b36d431895c4f32ad6bba0fd1cec657e22912a20252546c18b2338466aa8e1d5f6a13e201d70cb4a6841494f356f7228ffa30fb892145f7170ee03fcdc4d3	\\x0000000100010000
3	1	2	\\x759f764ebc4894bce340f04a83984edde34129909f55874b4e26490736e2091114721e64db0dc51408aa0f195818d25fe025d09f3a254c3352d5630983c5e30e	224	\\x00000001000001007d89ccf58318baca0d65d7a1bce5c4606207621cfdd48f75e421007a70dff712b86fefcbf613d8bef217486dfed9363054b79b3d68a62fa6e7316d2325b6914fac769c8bf74bda92eaf78322ccedb0af1a083c98ffe60445afd4755a35042020dc304d31ffd82e87fd6e17a06f6043f6b90fa6a3696a4187d02bb3e077774ae3	\\x7ade22fe75c7dbe2d86269eb9b539a2f59779d254cea2f1daa4b5cdd755c819a031cf8e6c0e2b25f5e47a0ddb52d8259d8a44f23f35b279000e0280d62da4554	\\x0000000100000001b460609dfd14b90310e6640d549969ba4f29e2fc2c1403f489913ec158e08c532be90c7de139e6f83253ca74c71340a23a224b9604d69b5c167a4c28b3e96da4000a506ea113124b663457fa078fb77e6ca904d268dc28fa7c5ae0907ff4141ac0c8aa275ceb587ff4dec5fb446aab98f59721fa48418ba20abeb6bed798a056	\\x0000000100010000
4	1	3	\\x0cd3e5d460b1043ada1b21499bf4a49a40b39f50ac2b1cb1f6f2a222055b6e63686ad53d43dfb9a9802da1a3ec0e8fb12d3fe3d628f407042d73f0e9bf43d80e	224	\\x000000010000010026b78c6b79207b51cbb72de3384065bb8ec5cbd1edb628691be7fe416b6428d2f1761ecc0115f94bcbf1508aad6f7f5b0a6b58047dea9f4836700e4a02343b8415d9061b4ca686902c79a9b7f7f9e451a1d5aa4894c516e0112b0b380fdec95c3f840a6171a59c02c30b2cab3610b10cb5c2567fa29855abb8c0588350715035	\\x632bf9e83778c69fc943fde6b73c0468eab746487f0210e5e8b267f8734db6ee864854fc2a1d84651cc10f8301833301499d581b354a50d058dbcf42f8cdb709	\\x0000000100000001ccd2e88d898fb6871523e8341b1efa1173f5e568e799b7c5ea61ae6fc03c329c8a8cb66faff6e517faefdce1bb9c64d0b9e2ecba37d16e74aa422dad95aad1c961ffbe1689d917ff28f26d3bf319fc6bbd2359059136b95f6c4751fe9b687d87439230f28601754d3c1f668fcd44a0c72d2173c84cb9724de52894adfa163e3c	\\x0000000100010000
5	1	4	\\xc0987954f5fd2f9f5d3e0b2eb29bb8e8d2f8ad3b9441e9d992aaec69dfa9eb1cdd8cc4be2351fafdf72a79da3b4a14455bf9722dc4a53899a806d37c55f4ba03	224	\\x00000001000001005c5eb707d37f19027cd1253b82bfe07d68eb8f4a9a9fb72ce063a6eed20c41aa0a3145abc8c4ddb530863f0c5da7f51cb5529afe2bf58453a8105ca18db0356b33c9302264f94cf99cf289c0de512ed91fed6022266bbdadf6598dc43ce709af347c911e7f847ea623b169c6f7fa17b36fdb67c8cfabd5da87a8b666a97e933c	\\x3e5a005e9e290c099e4e027022cec873b85491cd654f1ae1b0ab75751fd935baeb0402a818beaa8357614a82d29e9d634cd228c65f09faee6e63c3aea78ad23f	\\x000000010000000110a6c52f7d6a9b79723ea5d0ef8c1171123a747c75854627729d0dd40c871205459482520fda0111a738a9902666725ba25ce6da2e6e9e1e7a9455ebb8524c1cda9b8dc1ab04040ddb2802bb34903dd53007a3aec72639af416591d929608a93a54aa502b25804ba13251baf813af7a7d2e56223c0a1de873cca185b27e41be6	\\x0000000100010000
6	1	5	\\x8b006c10a4d7e92686684b1b36c2d49a27ba462116e9b87a1936a43cd23f7387fe9a342878aa218a016fc2b35c82f87d7215e2f335272c8b97fd00cf1190d40c	224	\\x0000000100000100b69f45fa60394c5d795964e37f79f97d3b0278ef7d580a1162163646372df31cad65225b9d88403560f4632709f7b3a3efd742badf76314ebef2c89d990dc9fb9ad530e7ed8c4ee8c2433e25e805c72e0707fe49d3c7e61143768011c5fcc0d608e1e151deff841278d9dc3ea5e13de0adc7ddaa2fc894e9835dd2d6c338cdf4	\\x0dbef9c3f3d310a51ca52c36d9a2ddf55669f26495a81070553fb6e4c1947318c2bacfeb82ef71fb887690507bc6376a7827fbd2ce8f1c327d64b6fd378aa8ca	\\x00000001000000019f37d2e864e5daf2fc473ffad03a22b5daf5f71cb1ae1c145abed11efe8e5fdf3766cae3684d2d0272efc890aace42b0500d9dcc5c12de17b0e340e71d566f156fb9b546873c7af1cd5e6aa483114c05035d672d9c9cdf6621f150eddc378e24537446b99c2688e1e13a323411603fc7727048a2fb735b781fcc2f670696e6d2	\\x0000000100010000
7	1	6	\\xa1e871f40d0efe4d1b9fd6f02d8be20a316d14939e1e788a21535fda6b732d004e06f6dbf41c44265d446b496f9d45fb739ecf88ef198197e8cdb94060d8c807	224	\\x0000000100000100762481eb8f202d6ad242c819e81a870c5f505fa4472fb734094728fba29999916ce93fea9ba75c3a995cb26671afa4651c74518229cbed4d284cbd5502ec96778b07df40c4ee0c621e27391e4d883045c50f981aab03d384e5ded055f703b8f7fd11dd185e5ee9c46d5c8a8b1b541aba0aa7add1555eda427ec9c1af58ec5ef2	\\x341d935a4895eb329e31092f7fb11ea0dbcb3f653b4b047e4797626ce6d531f5f7738ba3ce2a73c205e6cffdb2b43c901fbbf5fcb4f60d7e60086c02000ba880	\\x0000000100000001b24d8d3b755c1f4b894110a1473ed494cf3261a89a38a4bb6fcbddaaac51ff4ab88b2c04448561f3635a1f926faa755e1a766f4ca1067956a241741696bd7346765ecc6761d9895a88bebf982937b6d2d74a558ae4ec58ab718d68799bbc543c7caa4529a7ab8011ceafce69e2fa469b143d48b3d70d25b8a602b15d1b5b910e	\\x0000000100010000
8	1	7	\\x674f605a9f22a2df2e9fd9c9d4804752a76b643c75fd6d5fef9a33ff1d30d20d400c1c940e8f2039bc457785dedb29e25be02d99e3eff27047cb224b6a3a7d0e	224	\\x000000010000010024f5be9e0c6ed99662a6b8a3bf04dc416c8cc4f2e62eaaee57f51f25879f27b058690a76c8a139b8c7312565058f7c69ca0acb0201598dc789c6cd15ae317e0089c4785fba675ef82c0ce904273b5385b19a117b224e1ff2df08e03b5d767f38faabfbee2343828ac62f5e0244f122f49fbbf8a55405ae912e77e97f749c72e9	\\x77dfc2f32e98332adc1ff51bcf7b63e351255a18af7efccd8680fd5fd499e0262dedcfa321247deb8abaef55bf6306ad513a529c76b035381a280f81e3057e82	\\x000000010000000192fbe18ef512fc07a480c2ebd0435aeb09f71d159baf3c6392d01b59314b64072945d231b6a6b24ed12a777216fda03a6dab619a2a14d2a95d4e9df60f77c373fe3517591e2a68b070e1c6d329d9ffe0fa945a8c6febae7dd471d9e2561569ac54a377d7dc680c75637cb4a407d832ace01cca945bc780a406e2305f3d1dd2b0	\\x0000000100010000
9	1	8	\\x9e0c7b50b55f534d953fa9edcdb7e60b0506c8a5e1a64ce8794f169326905f83d99d52328222adfe4910e5c087a3233141989e2fb76aa0c9d5c873e13fa53e06	224	\\x00000001000001000bbcdeaf265c9027b3c7d0135a22bf54205d54ff2890427c13ddc9e95d6994df1cb54b5a9654eda6211f871f0fbe32f5aa79c24f3b3e23edb43e43288564d71c6b674ed39e659814fe0135603e47cfb6543eb8c35c0ff84791176ef3117bfec3b863c50131845ad91a68f394b845e1738c2314a518813db5ec70c762d612a08c	\\xbe79b9f0b76c8e690d6d058131decde2f3857d7b0876ad8b0012cad61fe0035dddb6a4e0563a40400db9d09ea88446c635a7c7d4e254ed5876c97e6b1db7c3f2	\\x0000000100000001b54a01f978d1cbb93cacdf0c56616054195e369f4987ebfba0bf0dea4feb7b31a175c189b4d8b5e92e8580a6925642362c86baaef2c7b510f94ae538c6e75e1e038d02f280b8c9e17984fe7d5ce7deb36abd390f711e66009c31d04da050df72113a541dda8d05390d48a7f59a3e1751c4f611227e241a6e00b20f81a9fe3c4a	\\x0000000100010000
10	1	9	\\xdf7f9bf7f90546b6e06db30bdd8c20cb7fc6bf28ecb619a025ebdfdbed653d797d34a369bcea5b844dccf5b0826bfeca411d1e7b33d796962e38e99433556101	113	\\x00000001000001007d6d78e789c47281a8367426532bf343e34f9ab7d0e9d835c78e520daf0cdefad4eb662b969be743b0bbd954306bbd1d90a31b3d964d46942c784272568625eb8e018f877a9600cb1c67f888b77de6b1aceca645db7906dfab04a7c76c82a0f3d3f971a5d3cd19616450b8c95031670342e435ef5139c55f9889bc46c32b1df2	\\xc1b162e407858436d907da40319ccdadf263b516a99b6d3aaf133f46b046750af2ae63873d4a765d098a3fbc73565e805ff24a38f043606a235ef06f10289d9a	\\x0000000100000001448c576913caca9bc680dc735832a31e84d099463c1942cc3caaf34249a39b00448c5fc7ad40400c6a997353bf86ea485439cefca2a7a5e8374679059f2320b11f2eb72a3b6d87c11088f52dcfe0e77dc55ae8d88a087a83cd8284ad8c7b0f622f63ce91f9e3146ccf6b69243d5aff14c22117b4d3672ba309e10c3bb287a333	\\x0000000100010000
11	1	10	\\xed24ed506c842c8edb5c47a4eba4093cd1ddab500788ab24455813a3a7eec55d3bdbad6f01fde99fe3af0db370171c7ba949dade9d3a93a9a6660de8eefe3a01	113	\\x0000000100000100052c7d775409282a1db7cb95b2531fcd288c7cfae88e0920e78341113db6ca1574f3d778e0f2112cc5f2a3b74bcdb53cba54aae766280f9dcdd1e38924f6e65b5366e543815d89ba16c2b37828b75fc240ef3db98a8666234286c392e6e6489c5ce0aedf323da4dbf9a9dfcbf8e143e39ee9bd3f5f791b1985bfd7cd55816aec	\\x436d8ef0538780865c8d09fea5ae11b1b294f0b3e58ca9cd9630c6ad0e80bd4677e94881869a8693de8b65a4b1289331e7283547c7c046ea478ae082edbc57f5	\\x00000001000000018493a28923f515614fbbb47aa63ed87fabfcae297772db6e73617550f0ed84ef40d214bc07b00a01f6e6b26af33e53798c99c28f703d11dbcd8590bce6bae2189523e7578e5668b1a577eceb351e0e11d0fe14cf862d76aac6ce67c4e958eca6793a4150f4723d0c6680e5be44f6d882bce4f468bf73114ece339f454c358269	\\x0000000100010000
12	1	11	\\xea8ac8df00ef15dc5e4c93d25f6e1b7be5938d62e36ed857bf62c1ffd371165f31e96f9fc58abaf0aafd377e01818558007d3e2518831df7354b1027a016af0d	113	\\x00000001000001009e7cf1ba1d8ff7894f93104621372b3303f0289f09fc539d2858e49dbe33ba5786ce376e741aa72375ff6a071335ba4d25085c3f0f0599c8184806ab69b2667c73fdf4fd78db3d54bf93216a158642fc4ac146abdbc3d2b09345ec13915abb89cd5b80fb9a1ad736c58bc73743660d9906e62825ccf8d09365b244097ccd648a	\\xb41eff0e77b65b3ade14a2365ff58ffc896152d32cc11ceeabe0320480e99a59afd8aa92d1bb8312178d696bfeb00f9b3cdc26b127cd66922a89e03b33c9df12	\\x00000001000000012abcdbe8ee20a82e1927cc3d8dd58eedabbd2783766fc151dcffcf07c0087f0a0f08badacd34921d80f52b0755143ae8155206775881e4528a7857b65676cfc2f354e02094dbebbfd28dd44fabce3f6d04ff054fabc390e7608838207567caf49f5ed700bfb4415ad1b2b436667651201ba3fcd5641cb6d12fa05a12f76d1f16	\\x0000000100010000
13	2	0	\\xde49709ace8873b0c4a76d7029f57fb7cef7e16b74f8e3fc472e29afd5a89c83ffa5dbed3c8217eb5560a0eae1bf9432db159d5b6ec8fd54d357012935e1b203	113	\\x0000000100000100a9fa09e3cc928c1cd27c8c2ead8ca1eb928e26403bde3728b5becd8f2f6e212157550163339b77d848727fa2ff82e6ee7dd6ead496289214e62dbc07ed668131afc21faf8f8b42abdc87774b504d1d7c9dbc35fe332ae31af33b6fe5414c65666a5b22f67bf39c0bfcb1b0dedd942ab7599231cce867f0a23e7e1846735e12fb	\\x50e455fcfa48c21c2c809992e8b63b913b9faee653d7bb707688e369a60c2063a6679089618b998867cde09dae3d692d56e1f09f05f0f8f2904ba0914a390250	\\x0000000100000001880cbd7ade6bd5a04df4f897598b45ef3d0fa9a4ae86a644e8b310a84fec70ed494f4d9e01d8504459a24cc6ec345a312548eb6b379419f1da1f7bff5115cc62307f783d7430141755ef45647ecaa879fb077104dbb45bc17e364bdbbb9a2f213c08a12e475cb12b538cb9ac64a49468d02f3efd9ab23d90956cf07c0fed884f	\\x0000000100010000
14	2	1	\\x2d1a194aabfa40b7cab93e952e4e4074dee8174009949146eb66741d2b53a7e02aefd1c1450d5669590f162fd26938880c7117cb702a3a12d308d22c67a37701	113	\\x000000010000010071e463da9a910123734a643c48518fcb457923f13838e19929a68083991713c510a2084a262ddd9cb375b468302ee7d3c88eb3198de03215893db55cf4d0ec85381bfc25a2efbebe9790a0852f666d54141ce0fe4c244d1997b6df844d103fd259a8c307e49b74cf0e9130cf715498a29448632a7a2ea89ba522940bbbadaf1e	\\x945b8536ac97081fc7de5ab9e5a065f16a2c4939e92eee1c87a454dc5328ada2530fdfbba567665bfe9e01f524f80ec6f1a7e918ee9a1c4f6a28a5606f699b78	\\x00000001000000017cfb227690af97c53a97dc9d9494647030187e14d1cb5a92010126bae2d350ec1d68dbc0b962fac3e3004f4a746697fc1a799d8ca046d7316f6a8ae8105448d82ce16e4d16e820bdc7fbfa2036eafcf75cad396462c8f91890967caf982e3fe888164f2e589dd7d3276d4ec937bdc72ec95f375b39d674670eedf33281dc4f58	\\x0000000100010000
15	2	2	\\x2b2673d121b7b4fc719d42bd168af4eac66eeda36d27c62b3d4b74b6388ba79a7b4308b0d623cf0324f8e59e7f60665b2738f50e40fb084d18dd67a29272a30d	113	\\x0000000100000100340c872fcfd09963647f8f0c963d91cfc52d66aa36ac7ccb0b4b56b8282fef3112a63bc9f7d7c900c898ba495b67cb9d450a009b8d0504960db8710252c97a2a68b311f45e6cd8be82e9c1636c8efac32a124972aece5f0df0e25817d7daf418862ba07b33a377098e0b9dffa9bc1b6a680df17114548462a298565e886543f4	\\x6f335a93f73131de11ad14cf08e3a95bcc10771d1f0eb8d83452a406008ad10a6dc1cdf647ce149bf78b1a359e45e4a14e314765258a01999f4e30cdd4ee8f07	\\x000000010000000151311cc0caac7ac6b27f8cc9ee0b284f1e492251a44721f0ef9df9fcc0773eb42b0567aff2567714c2eb76f35a0281e62da2a21f3d497eda86ee0742d21df218a9c591eea5398c8b34954eeaca771914c2db86d0dd80737c21045d7667af5d0a3862529ce6f0f432fd01aa559121a66a6a5b37cb802ddfd7b55d6fe7b5067e6b	\\x0000000100010000
16	2	3	\\x0f72ec6643c5f8992f4542108a4fbbfb6adc717d059bb10c9a7d2998798c276678f6c74b8f3581101317cfe5ad47a0dfce81554d8c0fcb666ae8d142104e1203	113	\\x000000010000010088f0013c7a348ac0f77849945abf76620d55afd929db70f2e57a439ef2edb8705b5a0fdd3ed7b0a47ef769f513455a3a038f4d5651a6b49cf9c348bda0a7246a4c3cc4a435e1c362af6ccd2a680a76ba3f0c49a9468030b9b85963dff67c4f0caf3e7ac342a0b12d026a2ae061f5d80f6fd9507cdbc7825f32ee492a35c49703	\\xe87115090d8aaa0f9134e985742dc312bc9329fda62acc2f7b42aa34e9f57a9fb7fdcc64f7c002c6ff30b541ebe4462b6cfde64b98c5b2ba5985f129e5b463f3	\\x000000010000000129421f951243bdd36fb8d19e85f35977dcb1749ec0b49a64d6d65e533e7c355145d1c1f585158cb90bccaffa88d4a9475985ca73f9959f9e8a211c00aa8494801c10bcda8a81e4dfe4313ba1bae4a7491e1f6cb85d4cd3548ce1e79649726a9e8368f46bfa973385567597dce4bf88e6531815e9166ad0bc8370b5e6bf6f6192	\\x0000000100010000
17	2	4	\\x4ff1b89fead2c9b8c97a13307ae0ff3ef2cb37d22f77f77211561d56d526d4110cfbbc4499c6344868d42364f6131801ef2573f8bb77a978a668cea47a35bd05	113	\\x00000001000001002c78c29a050f80ad1c8aec20ed528bddf6b0892b7a165fc37ce331baa12bea5863e433b83e9248a3ea15921f0056f6fd7391a726ee60c31fc53b7366ca26b4d450e191891a35fa3afc23574e5d5ee5ac9ce3662abd862a5636bd4f1cb2bb4f3c6b4b9b97c605329b826d172e52dbe501482dcc5bbfe7dbd19208a2025bd74af6	\\xd4ef40e3e08d9892768822e22edd9d85e3afd931e972a9da204be8ade107c569f9e7080fd1e44975c61614c9c6451b53b20bc502daec8f0be02ce37b12f633d2	\\x00000001000000017f9803ef25bd5977498742ba4e1c34ea31fce4d1f948cc2ce5727e92ef594e9e375bb1a2b081c0878e92a61573a17a0646d7728deb34e2c05778080ee3fd7b13a4ea090e119ddc279171a7eec32c3c74c92b30ca0e810811e83496f520f5aa9e336834ae640968876e7e26c912c1cd3e27ce5cb6f3ead72f46ff0153a3b5989c	\\x0000000100010000
18	2	5	\\xc6b8e0cbf472a0809e52ee5f37cdbe7ceb1ca9dc68cce14974f63530a64f1ab9aab1ce41ffa5c5b217c8ffba5188e5001b3d07c2281356996915e14d03ff8d09	113	\\x000000010000010097a2f498af3d07f88bd01514b5b09a5ef6f692fa81d5fdfd563a795471416df03554ae1b38cb63235871df2ee58e00bd16b0a95701a8bc5563780c3c8b377314653578c4e6019ab350718702a6adc04c1d531a67707d39336bcf22be561a1d2456ad7afc2d85b71ca6c6c825818a919021507b7347255a8143c6ca791466a9b1	\\x63b77722f7b0fa0fcd111f028a1ee785071b3527d96da9fbeba8712023fa46bf96c75455ba2fe61f34172719d4e232b2807d222cf70b59667d65f1a708a049d0	\\x00000001000000018e894e2988199ed941eff446aed94587b35f3c7413852fc2a1af16ec157e329029316ec80aaa7b534adc632e33b063e17b1ac767c74da5323d9da5f8689d3d9daad82f021684a2dda66b99c49fe5df08dfd4c1cde3ddd424a60eb7625136d3987fe1f951895f1c1b9144f3f48fb047beceb7cd618fe36adf787b8eabd54287c5	\\x0000000100010000
19	2	6	\\xb0f7f037a0197335160f20238b5a5273de7b521c83b62d62c8b5241274ef2ab6b2110585f3d9df3dcaa0a94cad54cba8efa6881956b984799ec2452bde52c901	113	\\x0000000100000100a1f2952ed7a219f2ec6f4bb93a60d378af4303351b464442e223f92173324b09749d94f4689e439ef0948775c2c2398478513d57e32d60bf3ff0d7bfc14725ff2601bd4644bc00ebe91060634aca4b977693e11d0c29910de143151d599823d42247b8faa290e27bf9fb902d65fdcbb7908f8c8dadb09410881a869c0c6665db	\\x69ed3d67c0013f476c6f5f6afa4fc02fb6a4c69e8d331fd137aeeba2ddd7a2390aa756d1e9a72ce0a8b63f5997b473b734ae809fe40409360eb88ef9c6377667	\\x000000010000000149e97085c264e1cea72e22bbf2fce8056e1303f9601988a9a9e8b5ac9118d319182b1b712379cae958f201ad4012970b3ffecf578adbd69755feb19732533601a83e928f2c076c54f7ffbd2955742d473c4600b4d480fe3f16cd882a0ad9825f58b42bc5e7f5edfb31fbb0ce49b2690d76c9800de2114788a950e55080aa467a	\\x0000000100010000
20	2	7	\\x6582b654ba2847ba7f08e10d647f646acfd312eb134e8a265bef68c37e5fd40cb02c06da1f77b028323bc50718f96eaf2042127a6f178c09d9fdc228ebc00c05	113	\\x00000001000001009b1762c8318a5748a1c6010bb5e8f2895fe09b42d5630f4f87a5644809e2a0f77eca662ac7e81c6f33e1ca83171691f4ee438a72c7f0184b893fbe79f32dd2ff6c9728fa7c7ced5430d1e04949250c5d0455447553e7d62d77f47fad00021e52774ea38d10c6def0025c3266c888ed0fc6da4f45fba86afd423e42ee10507c2e	\\x532fcdc84b4a5a77bb57cf68d60b8d99fbacb6dc8c3389229a6d467164de5c339db5f06b21b9de1fac7c1b827084800c49366b042327767cef9cdb083da0b6f1	\\x00000001000000010cf43a503f5c9437c3c27f782ed750169bfb335b32f7f49082caaea7f25206b597eaaa4ad69ba3cd75557b8924c48052b1d16dc4a8a5126dd4ccafac5e6d9e79adeeec9104d78fe83ffc6c446605ec7b046f4ad8545df7ebb99885a92061776c542902e6945382f7a7762ddddd8dd52dbdafbd78dc38c7eb8a269adcc24c4a2a	\\x0000000100010000
21	2	8	\\x0afe32a7ec2aa48b6a98acb913b950743979ef161b63f5fc68ee7b3199e5f2b42f6c0b613fd56945749c7af27cea2b8bdd6414926f98e04282e3c18b78b9fe0a	113	\\x00000001000001003e2ea1bbae0c256e3cdcb88d9cf5ad7390fa9cfffa3a6440017500beb7236a921676910d9e440c1ed885938a502e7776b751f37e5d7c3834cf4d9c8befef88a6011be1e00945849de4b8cb732cbc4a6f255bb8a735c0884ad9414508f8750e07ca140962d334ff33f42752faf29cbc20ade41b93f3b6190800396d7ef0756abf	\\xe62f3b54388dbd54eba9425811f69ae6828631c1c04f27258d45bc4d7061479678291cd08db296d4150487a2f678bf5ea877ac741144ad3da5cabcc2c97bbe4e	\\x00000001000000013518d92fad8878b7a55a8bfbd4d6fd6faf0f0c7f17c792f94cda669e2cf21e404ba27a567ccf8116a04e4e7c7c32c0a96b2cd8a2dcba17ed323a2f0a9f721d6aca8c05e7681eb8e6db08fcbea8dcf52e8276fa41b29dd76612185887345fb7a128e9864cfa94d13a7fbff3868bab21d6abc4583ccdc6617ebc7811a7bc26fcf7	\\x0000000100010000
22	2	9	\\x67cc71bf69c5f2de9050e31ef69d414f4394e822cea732a0a589851c0f6a2222835786544eb8640eedc1d3112b1cbb27f0c3280300f0e72f7e12b44426ad620e	113	\\x00000001000001007d6d35b09619813503b097e5d1a669768923afe74b3819204e31cd352a59b0e8b86ccde311e859894ee20616709feb073d7ed0f30aac8d850d26b3777171133d41a4e0b7b28e101cd0194f0f17c88181f17e16f95857b8362cd66b8d26deb8c0820ab6e9b375c6908eeadbde0ff3a32dbd4001780c204a7c82a461ceeb75c010	\\xdb2e993158df83ee17f3440ce48c8e8098f35f97dbf5188f6e9e1743a538d7edcdc3d957fea2a9669a9416fc6bf4541fcc8d2f2cf96cf48235be89078861a90e	\\x000000010000000175535300d3bcaf3805ec6ae10719243fa3ee99381a07e62b651f321851271b0bcc6344782979f3ff399b756f422a119e324fc67f784c76f09db9c7fad40fa18c3c941c93c992aba6cd1d0e92bcbe21993b7e66e4e5b1e6e2fd02a9d0854eae96aa7c83013175abd0adcc4724369b75271587720157a9fe7a46826840e5acc0db	\\x0000000100010000
23	2	10	\\xf79aaad55d66b00397a0bd20b3d824f4f4c1c10e68ae4d318483e846767aa87f47725bd728a2264ae99c61e5980e169da4e3262740b78ef616fca7161cb95b0c	113	\\x00000001000001007e315aa7051b5530c494fa382f56152e727fe050e00e8b0c86bda7b63d5846053ce101e4fc80939a60c44697ec89adeb3f924584f8973f492090f0e4d283074b6eb919e849a24f19e47cef3ae36f3aa8a7b90808aacbef2062ba55b81db599b3cb9bcfc255b0d073f6ea865992976981ed9c74a4a26492e759251f6145efc889	\\x517f79c6ef746fb02d958734430b3697734db7c67a680a02d1735cbe6504bd8044cbe2085e56ce1332f9e459efa1914a752bdd296fb5ae9b00ff467028e5c681	\\x00000001000000018b74a97255a794b411f115e91f95ef17a72bd3a13fe1625d4003b5e840e10b771e684b96c795220f1b8039a36451b929e4a16cd8b9efd3ef58ad6c5ad8d900f59778e792d12910f726ac68df5fd984e6807b3f92765952309474c8b97deddafc3799206c9987f42aca02ff2d089739df6751346ccb0ae50d969443bf2a8169d6	\\x0000000100010000
24	2	11	\\x086d81921da4d2f4ecbbd75c268266dd99a52c93f33803396631cca2c1c18de2f9d5bfb36719d284c7939b488bff11d2a5b1ad89d22f8a0e2f68f15a26559803	113	\\x0000000100000100a694754207850cf4b2aa0e3af27659e62578c928886d4f58d5b2f4c03297ea4216b28c1995e6bdbc6618a6f299d0f6473ace5096ae5346fdd83bcdf7a39cae8ac34f1f115c5bd021aa7ef8ab2105772b605fa98d1b3f2ae44b15f1597289cadd2207b464fcdefdf5b49146b59d6e7498cd3bc3ed21c8683b38a73d3df8ad9b9d	\\x103dff6d3054793afbb122148465aed57658a65cd05d0b71c274a206225c93bd5e2a79472e579c048518225ff16cffdd627a41d59293a00558f9e9ee8cc7dd16	\\x00000001000000018abe247da4f3c4b2f5438f3c41deaec8df6823a116811e593c2fef48a71ad8fa8f97ca2c8e2e75b72eb2a526452419eba942d61ac839832b6236ea484e50ba4482d9c80e2ae73979931fe4aebcff1a3e1f3b49fd9ce35b95367a97dea310740fe48c8624bc84f217e961126a3ffd55e31d4b1cb18b06ac6cd67e516626be4cae	\\x0000000100010000
25	2	12	\\x5afe96781ba37d49a78ee9b03ad6d205387c5673bc56c3d105978b7bbddc67d73b42e2928d0318788f9a6d14dcceae1828b5a16e359f01f89f20baa24b448f05	113	\\x000000010000010002863ba357a899d6663e9ebeeca239532fc332f4871f895cf48b168426008895df929ee3c5b2cdee89a401948c00b1de47954390c5632c35a602fa5549a433c17ae6a988aaaac21754488ee3a8a00b08ca9a6eb87114ad34b5cc5a70a35a4bdf2066d9496a819357a41e16f9351bd5850d81cf822304d7bad95efcf9cd263669	\\x19d41f85c989d625d4e244b74cecdb17083590355e5a2fc5992757555af0af6c6645fe4ced4e4f11bc1d251a1ad4b3b339dccbb5e75170d8d90b393e64845eda	\\x0000000100000001109ea9e7b4ebbedcca41543cf72d35e2a092a857930a25d014b20ca31a09709c1d0b2f53dbb1d76eb92293933715b5520e584dc0689574b92b2436d9f82a27d1578e9ae8ae3f0581cc4e9da4971663edc5e9815e8d7bb3ef8c7da54e0675e7060e150f213cd716f916de4a4cdb1d3976f296b78d6096f5eb4a76699080a7603f	\\x0000000100010000
26	2	13	\\xc9ecd4c79ec74f28bfed02200f6d29bfd7a843b911c8db4ccb0d800e171885bf6c5a128b0deb6f42ea099e8b223c803b446578c30b2ffeabc7b41f1a1e24a40c	113	\\x00000001000001004ebf19060b02261bd457fd152bbc56ba11e23685362448216b1311cc87135b16709fc6d193df866f1e55b2a83d7abb08b4b697442d0be145c87d46c8f80bf0c22a46b641329add9a18e4db2f2a9c8b21de87d9fc56ef4c0480e9dc706b6508d6e14a5b71e1ace314579a8da1fd0bfe33320c62ec60451c5a19712929e225476f	\\x38b3fa4bd7a61faa3e66fbe3f909d04531aad6e346d64fd1e520e80ac5e0508a8d08e8d3fc79489c10b2dd7c21aa587ce9fff5e19e15182093692e0c8ba84959	\\x000000010000000196a600c3ff8cc3fdcd182cf2fd71534498f8123484cc7d28c6c6fd0f73f1184f9d6e4d87a9aad11866924b7f85e9074e074f07fa355c8d61b8e41282cafded558fb5e31bc464822b781993e540fafcdc7b3c065ac0a959727ed60e9bdf897239d5afe20aafc53b4c449d67e32c95061a7dd192234280abee977a01db2aa122a3	\\x0000000100010000
27	2	14	\\x0ac5eb29024fb35729974947dc3ec020d5a187b519f02fb30d9f2263e777600ca83cdcc5fcd03f38ee20a9d0effda811fe137864e0e3131df7098afa4d17a906	113	\\x000000010000010079d06277f55f85e8ccb0a6158ad9be85b60ddbeaccf57d87d57d5987edd87cce5810c43fd693304d805619303472907e04a035500ffa0bcb015f9afacf7dd8393f0ac740cfa626ece2686b54d23657963ade14e5f117a29b282a0b82c1ea1dec94acce1ba2064bf8a391f5b926aba89884074edd63037a393e2bb3328cd2091e	\\xa4ffbf04796d475ea8a7106e8c9af7ff67f418580f1f4a9ebcab5506b7603d2c53f4f0edf6fb46cdad0ea9db36ea2577887c5fde0a96d467ee830de321942986	\\x0000000100000001748cb3a576fa9a5c6ac9e29a72c1550236eae70ff13bc25d5dc0867afb1f85c75a7e6ef72e65f9b8a504d44965fc38e7bb71a41591cdfbf2078c093d75a1c0a60dec0c1ae949dad0d9d166b89d44c38fd2388589a36f952a4b6c0612118c7acc12a884a4edf5055a3d1ccb1f9f2133c69cf1eff47c58d051992cbc2a42e3213d	\\x0000000100010000
28	2	15	\\xd0b01eb3bfdcc6fdd5a16c9e163fc9e39b67c6199b81dcc58a966ec60c949054baf1649b83b844b1a3bee4b542b1a49294c6449300b9d0e39d05e461f60a6d00	113	\\x000000010000010025635f65687125f771e114ef6d913a5f7f5f06945843a1c2de0ef147227c43b185d6a47c641ebc7fd7cec3bc2dcac2f50f9b027e79ca1bc8966198dc85481f7f7e6090d6eea0a833e294efe8a164e07a5fbf207bf79bc623ed3daf83fb6a2ee9ea3282035b03505b47a1e7d70cef3554afb1d97581cf198ef334cac333af2a6e	\\x960be851ec0928252a1d026e854b74d17b2ecb671e1eccade04f72095e493f0e19a2d4ed98ce70a8a760d46b81cec8ad86cb9d185b8fec3557a96feb77f723a4	\\x000000010000000130c40275174801dae4dac1f6763969d7d3aac5560312bbb2aa37e5df4724d40c80051e4b530a482b8532ed97a85e78d2f3f5b2cdd2b52f829b0e171300b4037d2f08aea1f0e508a0989ec232660538ff8ac70f34c4b66cbd864f0dea7230323240928528fecaa4265298beffe0aefb7dd46338ee5d2f490b3100922ba6f90f78	\\x0000000100010000
29	2	16	\\x27f95d83f7ce6cae03872185413a2f58d3fb12daac92095954984df1c1b38d3c651416f67c88508f291f6cc029b516b8b8f90ec299702a494cdf0a98f295ea09	113	\\x000000010000010054c8c0a28eaf2b3d2fff07821520901fffb6588a7a7876a776dc4126c75d420171402a813b1ce7a53e314ceb34e509e1003c5a7bf2bc2e6febabf517b40f06e3a38c06c9e46fea804c025d148c60217f4a534c4cc0e185c5e4f5e09d40c64687e42bb5d23ceea032ef2a8214a51a7203a5eb6809002e8ecf743c8c771d1dbc4d	\\xe60590281c10a0eec95a3bbbd1bcf81439367239dfa5205fbdb247824e2b278e9f6844597e6dcd1965af2d3054be6f92d55cda07ae6941aa273fa9e895e581ea	\\x000000010000000175c3c8c07aef4cbe6d4cd365b7f8c75447cc8e5d296ac199737ae5d6ab426cd874cc7057d4cdfc6d5d6c1c442f543ba23f708b5e361af2758d54892a497fe0fec159a34ced3316ed2a33f7ad6948eaa912763768aceae4c9e82a78486ae7b3bf35c46770330fb86d9a5128c26e88869bc19fb1d70e5ea78c49e7e6fde7240ab4	\\x0000000100010000
30	2	17	\\x98b42c25f7ab773e0cc0de23d9d295330d255ff0f92799f8e0e6c3d988939fb0528e1d4349df55fc0be07b1c83c5e3cea0e6758e851dbf5b85e89e7c45915a02	113	\\x000000010000010005e248a2239a99ea4cf139f296704ec1471b114bcc5766bced5def51b42dc0ec2f645df9d5b5faa503b05d44ff96e95acd8dcc03f1ee1b579e14ae8c30170fe3ae28f7b4b8f6b041dd1c736bb248d4e8c2080e677f54847a36b29dd41fac11e1dc83cdf4351e49b208a0b62147b23986e4c4cfff7c23c0887fab7b61b95d6c68	\\x89adf04a04737f9f9451348b3a6be5674de9351d4f26a6c7bd794977e77e2e29aa29d43a56545ae27b1e6b7eb36e41d5a5272ee2c75eb079879b2a58f7bbdc9b	\\x00000001000000017d50791e935b25051fc1067ce414c9a5fee4a29065f1ae4c40199f9783c77464408c78d8d0206d193780f6bd79889a94cc0835b8c6500d9555a13bcec0618e900a3183503f06d9c11bf3a8c88df145a113f22e24558fbe60c6b74f1139cbf24b1f02b0dc2faf279984acfd20174d85a17e57072a97669fe83e105b72a69df735	\\x0000000100010000
31	2	18	\\xf402da1e547dd61e6be14892b3e23762202a314937bf6ff9b3d247acf1ecfd78e1758a27e3ed0088bb948098c01f3dcd46f7fced6938b969d3dd789ded24260e	113	\\x0000000100000100263ef57ab6157c6924b0e822c25558489c3cd2f912663ceaf156570cc09dc179088dee5486a0f62f64106f986fa4e4c3d8aa84607c2e7395ab809568420e8cc4f970cdb58ff3a0506e34b8112520d965ef2aa11c0f2cfb4ec6fe57b6d39a4ecf033462b14ecd3dbfefa10face1e6b6c456bc5ad87fb76b4e313c3667d208aee1	\\xef2b0e64920256e9a7716a8527731241958b7f7b9b469ea79ac79e77cf17199580b02dbe1f4f87eeed2af96bf713b4eaf573bab5a7de36d1d4c6471ee1fc89a2	\\x000000010000000115ced6c63a4f5a0be6b5312a47474682a41d408da6d4ae8d2478bf1af0c6417b917d4d515b97d594daf5c97352ce6882bd2c5a454a089a9aa6217acdc14fe0af91b56602033276adb11955bd36938ccaa61902d5ff303bbda7a656edf1f9e1f9506003182a2217af794bd058bbfe14a5f998aa814cf572b98efa857ac54d6d3e	\\x0000000100010000
32	2	19	\\x469b1cb4eca3c35617a5fb34ade25b970d9dc302359abcc637c530ef5bed701d88d3dab1ddb01925fd9325fa0d52c7b4764aab525f5bc70aeea72339e9c7f903	113	\\x0000000100000100514debe585bfe4d173b1abbc4ea842896be9455cce01701648ab5baff312ae53c88e83375aead99a89274dfee1a0a3719714af673b12ca07639fe10d963331eed55768e8dca7604606379f3f7059bd0a7ea4d08c25d29c29be68302f144391bb1c7746977aae37161e952c60244fff2076df87a1015c183b6bd8a4926db23a2d	\\x2e5389d11914f965474bd721a1e4ba8bff8d96bb219587b1e110570ecc63af54010733d69058e9eeec3cf1d719d521a0a42aabfc26c29a295e42a14503c3fd5f	\\x0000000100000001501ed0c6eab62a37db8c36ccdb4166a7ce6b35a0009232891b39d4a2278a034b98d1614abdd3c76f7bc32de2b0c6d55c75707aa72cf0033cfb0bb61c8b4104bc29f2ea328e25e3283b2134a0a707b13e8a54c70afe8b83f719952aaa51d7ad5f16c6d13926923c42b0f930a342db5c0d54e59e40e505a149211487fa14729ee5	\\x0000000100010000
33	2	20	\\x3fafc084ce69a37f86067b21774734518468a8513ef854e8d6f9c2cd3cfcdef12304a7cda51770afc2d041206fd710b712f044ac2475116aae64ddc5c023430d	113	\\x0000000100000100632eb1425054e92ac4d93a27aad6f7ef1b2555a9170eb6cc4c6322ad32b3073e2346210c9dcc1c76647e251526b269d42a588b3c7f41a11672ede146f5d510539dad4dc930c017452044f156f236fb0ead002cbf3816c5ab30499f9610a752284efb86935e9eed9e7eb0ae156f9059707cddf5ecdcb48c64a10a3a7a6f5b4269	\\xdf59f8f5aed54169209123feddea6ea130c3ab60bc3939432c3169f398d6877623c7ac5024a72cb63a3373d5dfb96e83d82128dfe073ea6dba62b77a4b50c755	\\x0000000100000001aee31184f2cc3868146ed1601459e95afc17c609a5416459580160490445755af2475eccb5a563e29add989f8e137f26dd4863ee06d46e7b4ba28743eb8377bd2bc535cc0bde20e786038e9f11656d3360dbffdf1912e129067a22d61f85ae90635f5a5fda86fb53caf546a112eacef98026e0d6ff7b000035885d59c7057ace	\\x0000000100010000
34	2	21	\\xef79777549a92d73495dd660a327126c7ed2af31127e717f16f82b489cd7de4bb4cd7025d0756aca94015e0a6fd8bf60d7376163997e0cd62b050e3bc9987d0a	113	\\x00000001000001000eda9332642640ddf860e4e4019e50b31c6fa62838a709a01965dd3207f9d4141feee9fecaf5da6f86374fbff7af31e0513e99af7e105d2faa0c6b735f67b6ce661f66c2f3deb5bff71574f4cd3b3725fd5881dde12d23a3df422d68bb85d041b6b9f02e8a7f5bcd124ac85320ae1df1f34d62ba2a3846c20eb6c12261ce2c8d	\\x82da9aa9ae5b3568a1dbab055ff7d0fcc347102a192e98d08b16469a9bf1617436f62a814632e28ec3bf74e8375754f532b84a5135f38f2b9fef540518d72094	\\x0000000100000001237183b56415bc73b46250411066d0986cb938aa40679de5525d87b98dcc3e27d91b53fd7bc931e27bfdb32fc203b1d3ae9f4233a27a9f8e5f2debaade4dc393fd2556f4cb94c873afe8bc953646ee7797182520e68ab9a3a7498bcd09fb773b3d6ebb6cf26424ada92e51322dcad73ba574a1cde0fb14db8a84a8161d3c45bd	\\x0000000100010000
35	2	22	\\xcfc316c9034f496dbf2c1b215e597327e556e243205245b2016ac8d7015350d8220f7955fc0d63c2a51798fe8eac415e435b09ff2bd60100559f4375a8282f06	113	\\x000000010000010044fa2d4e7cf6c8ba91ccf72fa7aa45efa6e52bc520e17f05670b1c5d0bcd32b8aaea3c0ef0979abc824a8711a9bfed45a3b337941e32ad0e7ca77e1390f5e39f2ac8d6a2caca7e778155413196dc582a508b8748c476a070529d7a15e1fd7448b2320e36da5c073ff5f49b9fd52e1b943b34a5ab681e312e04d1dd1c48c3a689	\\x4cef4020c6f918222ce042fb76a6537ec812e9c2fbab9b090b0e8fff7aad53c6530e89accc997534e6d1a38968bca2ea87011e97ddd2811874352ae56ee197a2	\\x00000001000000015ffc6c364f9fda9623e3b86ce72086ae0f01e77913372470e66ebeb0e29055c90fd536c25a5fc6429dc18bdb25e832cb9bbfaf23ebce2d7ddfca12cdabc8aa70d48bde159af1b82c6611fe66c507527dacce832067064ae21259bed13a63d371996bdf6b053a5f85351d6590458ba40d797d45f5255e1a972176f075ef406d59	\\x0000000100010000
36	2	23	\\x7f461f15d072c60220bacc32ce37f252b7e830657ec13c9666da73d61ff1f9240e3eb91ccacb38964e3933d1c13b54f1f55a4e9f46cfa8ba68fc87fd2968fc04	113	\\x000000010000010071f271025271e37828d3013647c4b6b8414d6a57030d80bc9bde782a66dde23ac942b412b0c2bc4f0c65e92bf819c0e9d31a91b76b2c2501818b3ccabd37bf3fc6b8cd9d6aa2a783ca2e7adf5f47b508344556f48413e61a5ca5436407cd001bbb6fa6b9cfe22a4091ac585c01fb2b5283f093ce31ea4201da7fbeb330907cc9	\\xcfd43fe92daa7e22cbd83c8ba9300c4f453fd63461b3e1ad546839bc6eb7cdab2b8deea1ec57d93512939a0abced440a112c1685823ad1bd33a911b042d351c3	\\x00000001000000018bd2db32f4e7dc75eaa34c46f6ed469a5707598e84daf89c0d5d1c36313c0d46a6d33efe215dcf38d7d811f172ccb6f52fbcc9bc3fd0c66059d54088d47a59b478da56478cd9928bc32d587ca429896e21cab06f5756dcb8024f904a3bfd1f95afc0b5b2d566eb90ecf3aabc3bb7fffb3943b3f9470759ab1fc58e77af79d592	\\x0000000100010000
37	2	24	\\x7df63a0d754c6206e57197870723d0bde6bd1c75ecf7830c81cabc503d66c9b22a67ef8b5f17f35312e81430f3105ca0e773d80c2264d3aba79cb989d67c4d0b	113	\\x000000010000010011814b53e8d9c81927e520af09966b1ae9f3e0d0b88b1954bd50cfa0aa6618044a2dfb3709b9267d9e9e3863773d3241615249dbd1bc8ce2f7908c29b13019d6d1d0851d7973a69c8edaac9b09dbb80a36eea3a8c0fd1c77d652ee79ac715b13e0e4bb9d3243e6ddfc221958f88e869162f442e3ae250d4bdf9439db9742cccc	\\x6cee50d17aa7719825ac500f459c77a6797a5946640c4a7f9846fb9f6d92277299550f8c08112e70175ed55e9b520691fae68cbd63a16cf8bc4b3eee5fd7b7f4	\\x00000001000000017cc24cdd31bfbd48ec9269f26c4ca7aedc6407f0cce21862d7d8686e77a6ef39eccf6a13353a683f2db2780b5cb2dc0dbad96309541e5033fcbd14f6a7912ee099a4850f837606f978a9a47e421d171db989289449a26d0bcde21bf9766bbadbb5706a8a22924beee7fba10612892b1e51b75ba72561e543ca8091a1d16269d1	\\x0000000100010000
38	2	25	\\x800bbb25455ce501df6fc44701b22784e0f3f899073a43bc53474201da822169ad3ed54ecadb66fd99bb77f4014275b99ed97fd7a7c14b1b1650d0242ffb6304	113	\\x00000001000001008f4c88804240d321bf81456c98e9cc05d6a0696d3bf27c081e604fe541350bc2d6d55fefdbf98a27c68bf1abe894dae965457f5706dc8b2b093f27531f6685dd6e887648656db2d75c34d981a87173468da6fc014d18fea209b74f3cbb433ba1422d88484b35f19b0b765efe395612995dc53e4547a0d2eb23458df585835cdd	\\xf849b9c8c73a21b4a3c12703efc205cf7d2ee612272df1269647da392989589d1216ad08248e69592a73d9f6f94e9d8f2cacca2e932353cf4cc25320c453e2d2	\\x00000001000000017e1004184e0355bc8453075e8968f99382e4dab9e14342950f3f53be5b9178cfc504f6f1bfb3b31833cb0dec793b8b582d6c097a6baccd47ae7d8a5c40e791837ede47923c4419e86faf6fe4ebe92f9d9211919a8f50b092951a8387ef4057f9bfa73cb322263aba2af9142d205e4bb7cba408aacfa241532e7085dc0c9185b5	\\x0000000100010000
39	2	26	\\xf56bc962c980343a77b5416bc9e11251eb3017b6e53b3d1566170e4f35c9451fba6ee188e9f24927e9d35748c5377c6dccb5e3c8bf611f26b95e8e8256afa202	113	\\x00000001000001006b8deab05afab8eccd0ea6901a5ddf46ff28885937d5e1fd9d17594285ea62292eea842a687d27f07ae8e8719dfabe253c0bcd8701c73f6245ea795e0fe48f876442d2f694bcb5acf99b711148cc4ca9479544224948da17ace5884299c7710a53a4272f13a3e45832b28a45eb65842f513ab686db57ae7a0a3c667af7a45b56	\\x1e661c59d00eb804a3ab5bd9ae52afbec7cd1ccae11e558055f80ea24c214a75f254452885fb18b89508ab36129a44f60fe729de616f749f0214c41cfffb38c5	\\x0000000100000001a038c3168e0787fbaf608cb975a51b24a83c03f57902c008cd66f500bb3c6bd4674af7555bcb254aa524be21b2e2145711e292ea8604d047ccfb93e4a766381e4f0cc719981f5ce5dc66e86c92000afccde6a7271e9e6cf0625963a10f22b35b0ce5b7df05a43fe956fb1463cf708caa7b0f6df633dc272c1688c78adca5dbdc	\\x0000000100010000
40	2	27	\\xe124d338f19de858d5c19ad39f2cab2b4d03622269ebfb5d1a21093713c0298001bbf30a5396a4342201390413038dcdda16e786d172ea58a0153c70f99c9c06	113	\\x00000001000001009aa7cd21f23f786e2c4f90f55a9a797515c99721146088f2b363910837570e0b92e56be802464d60422f9b512752af72eec2cb5367c89430ea133f99106f885eea5841671ca6e1921ed1549931849b39cb05f20f8ea9506f5b68d476e04cc3fde355397e39b16797f30aca1acbe66bf67027ccd3b0361786f69a675cca6d9e28	\\x61efc305de59b374708f4c843c1274696157f7d0e729c308914d897473880a6ae3720b0b8be8484f8f642c42f7d3d09455ede2ffa52af1efab049527164a27f7	\\x00000001000000017c822fada16ef16b14de89578d3bf177f944ae359b52b7fac6bd3980a18a44c7607c4feb5a975664decbe8f1d6ce21109522eacbb69cef4e5fa96be13f049d893cb10fd49a70c2b52bb3e7ec5491a56e8306c0c9534a1e52182e1080161e86f072f3967a1e1df8387b5d86b8cf11e31ca0c584d03e779d92506e8f0a72ab7c20	\\x0000000100010000
41	2	28	\\x48843be774928fe90ea46d7cdf56b6da480f1cb4160b2010d4043bcdefee178c1fb90513416ba37d3e9c6f4c62ea7071cd5ab8cc70f2a4af8e9966c48ff5540f	113	\\x000000010000010063c184c381e44156abe36336371594690aa733ceef50b8f9e5fd3eb088aaa213185772868a190a0f89ed1df58604c0f1421f600fc26f7aad6485ec7d8d945455e5cbcbbbf351a180509b15dcf7983f9265fef594a3b9ceb4dd33b83795a6c26ce3226d36f3f8a9bd0f56bb8a49ce2adf7deeff62cfb527ab964710ea0e05434f	\\xff6b630952f4a6c1bbe8f142d98e8c732b6654de7044dbf2e41cf39044b3baf92b9cfc7cc39164117b7613367890eb444292b0d1d826a03d3cc7e036b7e10f42	\\x000000010000000149ee073d6ef9218ed91d0558add9d1fdf2e4c3cbf2f65e2578ef4f6ab141ec66984ec7885a9135c83ad9221ef5b671789ba3bb4f63f5dd81493e7dfee16a50b6c1090765da733d4935cb09920f48202470b70ce4c53fe56e6e0b735671ac86d146ed66a109834dae3b2f15acbb298ecd95f743f83cc3f74bcf879b80f96d918b	\\x0000000100010000
42	2	29	\\xe0a38c2f615a1eba85c8151be69406ee595892b2a14b2ea4a585f60d663e13b34c0abf27087c624cb7dc2b28ae677babfa175b352b16ed9a65c7ec02949c390d	113	\\x0000000100000100566686385640505892fece6960b55016ba041b19d595259ccdd4d788ef99e26c35c15687f481e33d7c0e951ddd1d6e3acc3ea78b9aea4aa084c2b239e8ee098183db5d8dfef1b00fd409aa55eb0f54207d5a6b40c7bb516b5bdd817f5317ae379c93ec64336a2dfd1ecf7fdb7845acbd27026e69abefcfc7f7d24fcb93220c38	\\xd9c8d9fe174fcead4f3d98fd745ba47ccda08c2e0a05f415843c1d9c4b75e2d31d8530bcda43a94c993ba699ecda36e878c971aca3a314c3ae9c1e5d555a45d3	\\x0000000100000001410d48da05e75c6ab9b6f23a8354c717728eeaf999302668dc134b582608af369b0cddb42b276911a3f77637a489da13ea3d925ea799a6a29d02c91dba85d34c0d0fbd4718b17a4aa08f51d3b7a37afb2d4fff5b5f49b3896721a8aae2c0ae276631b5fc861fb8d2c7c017ddac27d80017d8f39228434483b7cac6c903c65dd7	\\x0000000100010000
43	2	30	\\xdf8c5aca8b240246e26a3042fb97d91bcc74f9d2ef65c4c77c53e007a4f3e7f1e5f3c7170ee341e66445172b74d60ff5c4dd1814af67a18888504337a2310a0b	113	\\x0000000100000100386cf4e1934b02f47054f80efc31f0f238d4acd2c62d474d57bf64649132ac10e731894a7e38079fd6837db212fdb8844c51a995f5c31cea4269332ee5d8f4339e660d9872756a02b7e96d8c62a8ad8469d6668ea012efa394426da322b175762320c56c1e09a150e1ceae7feefd88961287ce7d304e12435a0318094461da94	\\x645dfc5b1e1c281b15be9c0828651117e2a0a0a50ea71be4f0f7d108701c397e7f3d738a4c5d73a9b443e5c33f349c4983fe8ad44c26e8d27a2250d991363306	\\x00000001000000018cc9e1bd1ca828fb4d578cc81823ff2f5edbdb0622f2c9f47dce4a83d220b789bdeefb3d2dd00a250db040572769da9fc068f0499e7e0a12722b13a5383950f425bd67a0414db8f61c157d99cc2c24d35b314ec522be83e794c02b67b7737c528e6afc214cacf43169e06bb0803f04d78af0db67a0ad940f91ecf3df7e5f3b4a	\\x0000000100010000
44	2	31	\\xf98585db52dac4560e1cb3977c62d4e703d3d2c384786cf759e5e97f417c47f9f04ca99e4a1f3b5db7b00d5235c9182bf13f8b71d368f283e77cc5ba7de7180c	113	\\x00000001000001006b275193dbbf55c1b91784e775fc5f53253757def03e7fb93dccc73079088158973f7bf5de9607292ccac76638fcad490b8b661db605ea2e52b10ac00b44805f0538b20ad66fa4bf921e1e120306e7f1dd5cb6d0cfff7be277fd9ff41622b6222f12f405d466e0677923b3fd2470f76ed98e65029a4bc34de9d430f5ab0cbb4c	\\xc1dd1d90ff58098029b9e90aec460b5182d74c9bd2c306666cafc1fb9fcb68deeaadbc7b7bcbc4a30f6c0b664025e769cee0b697677e3c02e6bb7a45de450dd4	\\x00000001000000012ce62b62b27640d368de8d18e4c74df4a38c5ac21854d17d6ed0b283d15513ba4cdd3911e66d2912942f30cc47c33088decdf44dc9869bc68093e251eae71db32bffce62c92145a7e6268163702e891b4321ec7663e1d0cb4d00a56582f8017f2d4acf0a4abea9239650e36f502cd19237ee6ca64de41ccce12122ed34b0df2e	\\x0000000100010000
45	2	32	\\x44348ee4460962d6df8aca937a6eeaef9df66e0d11fff7a382224caa65f0f6f85e5c7f871c256a0aa957018e1533bea23a350f9158a3ab13bab611bde7ac1d06	113	\\x00000001000001005d0065446e7d02784dcda6ed7e3650b62a9b1d81245fd1393d93f8a59a8c7a81add09e5c4846ab341073ec36b40f43032ed851f90bad87ed89c08503b411f09e145a61a6f5db4ed4c2bbdb04d8a41b92343890595d07bd9be827d5da659aabc83820b48d7dc4486416c4b089ea967039461207f9161e13884773f1e463b5d6a7	\\xd2b940e1604504fcaf9008e770a5419c622194a84e8cf559cb16035a6f79d2dfbd13440cd81f7995d264174d0752e12648146c38635d30ec40e6a7c8f9e9df23	\\x0000000100000001109b235fa39837f68cc323b1d4309fb0755e098d5b2d09587008f9d88190fa682db89886570ff53d0718c1d67a2f6d725f566db910c72d0de749e98101438e95ee06a2cf965a9eaf91eca81878a67ce50b5cd947b701038b6fb2372505c941e4d9074bb07833d0b734c2a305941704a20bca9ec67eca2a1fb4ad049888782d91	\\x0000000100010000
46	2	33	\\x3210e130e2a69dce5ca44fe0967fb5b0459745aede832d73a719b2c7c452e91f1b804886f4695d152d279b64c817dcd1d00ba8e1044c402da951f4f71096a106	113	\\x000000010000010035bd60fc42edef0f3176f404b680beb8feb6f604cdad4b752f0c355900d2c5d5d5f0c7bf5c5e37f054f5500c3c6ab035f2cbc07eb9f682312c3538aef76e6a889a731c0786f217e2587463e9e347623681b9f787d5ff0c936973c021580d8ec0d4cce6d404340a53164e5359524440928dd58ae109a13c6649172c284a9ada1a	\\xab0b51f627c0c6c5ede613ca2bd860287cfee16d84ccb63e82cc07f7dbbb14bb6594ddbb347ca6974ea0c55d36685f47bbcb02a486241c79a3f22c8180f43af7	\\x00000001000000013cd9880bdc5de8adba52bdd56085ffcb17691e492b72b246a6600c028be661a1cab8b8582c317d157e4f1e18a9d6f507fe3e057a8a28e48b2ab55a40adc8cc75ce568b381e5753803bc6baed423775fa59733c069cdc5685eb26cb14d6e94aa14045d6f0a0af31e99c0b6589a17853a646d0dc9b8dffe1a423704dabcbb12c69	\\x0000000100010000
47	2	34	\\xad4ba8b1d8a140c92273e969eeed58079cb8e9e6d2618d863d6d626b8d0c50f2dd97c1f08b9da2e13f373fca2c0def734d2ca169ccd61f2772edf7324be8960d	113	\\x00000001000001001a115d2e057288640b65b4e7110569c85a0c963e0459c114eee14d867ac8477ee580879e89572e45289e0c335c3b62d925959234d120b9e595b7529e0015b8e53fcc15616086f75cfd39ab2f8f1f55b69b0783cb001f7fa351181577a8819a8b8631ca7a5a6bad0cefa457926dd6e39e2eea1a4def740a8e4efee902fd1f6778	\\xd81051d0beb464f2d84aa42762c857725381ae6673e4f4de7aaaef762e50806cd0b1f5a58a353f31ab8f094c919d90de1ae6d309ca6498d13d6ff693d7758a79	\\x000000010000000185edcdd50feb6446fad5cf898a24e04e12e0523f608e57e30730f46bb61a2adc61e391137ffb2837998a5974d7ea31904d8e98c255df8eae35fc916b11ce18726b6691c4d1c7e2d0275d9f6f446e8499baa7adc79e7466c14ef434a07665adf23297457dd8d6019e73c43ab7f5a6fa98e847fe38a66aeb9ab3632fb2f2d1e267	\\x0000000100010000
48	2	35	\\xc0caabaa03c77744dba20f78ffc41ad0abe14dc2e714cbf2526d5a9bc247ef14aa3084b0e911679b5de668da028b38fcd1a4dc914e54296e5c4c419cfcab6e03	113	\\x000000010000010036a8997ef0d7d6e20f60a6c36de86de8fb022795f3b20db05f8420e725dea84ded6867b9184bcde6927fa415b844c43fc7fcd9b621792e951a1effbc4718a4ff878dd340160cb1acb5b6fb08dd4a3af7f389ee40950470c6403767a997d4c72c3928c696fb7d08186d6110ccea7d464b3b64e66de6957b2b0376a68f6936b735	\\x39966277d5360fcef9777cd35dfdc8cf55d055e96501942a347a97e44f33b8c5633e90e88628bda37c52ad6c2bca8164d5f10ac2a86c08a88eef83a3691c1663	\\x00000001000000012e09ddc65a534e5d8c0b14bb8c2a33bc2ac02316de7fe6044adb09c5dc7ba34a4a27c4ec736f2bef1f6ed221955db136d9f50665397a1dbceca036735de9acc9916cd785675f0458c443df5a0adc577622af361ef9c819881c905deec8bbd545e2d2ddd5cdfd6638c803eb1a7183b0519f2043d1f7c1a3848de33c5d0699d801	\\x0000000100010000
49	2	36	\\x681c9196cdfa11379e22d5ae9bb2ccc887efe7b9c44f2309d8301177eced6c34ae6e3d0436959833cfde41d1c9f6d488a109df3f96673f58a4aad5e013efed0f	113	\\x00000001000001006aeec9d7970d77d2ade3f713fffe731385effba6228a756a84e6cd25c89d650161cf3d0dd579c04ece2c96afc5881d92682ef3504edfaa2ab5694909f6d6f5b5cced71ccd285cbe5b42711e5c9ace4fe66570f7b075b284cc75089651ea5ed9099c9edd3b069dabbf4e225b2d04529004cc742dcce87176a35e156f1a2e30fa6	\\x36d481d712fffe643d88d9f4d0de17dfeefe6fbf203f893114f6b20b33202ebdc795a2f36aa19e023496494fc5d2efaf1e34068fb6e28868377c01d55cd3bc80	\\x0000000100000001979b2e1f33b8bb631317dd6eb19f5e59bb9d4daa41387d6090b794645c9fddf231bf9e19da09b33b6693277098da33728c419719b72fad9a902c3ef2c8900762480e424498fc456f3c77825cc036b75def02af335d87ab1f3584286698a683eb57f4d96ea9cec6f2bfbc1ee7d28c38e17aa1c2c711f6c0756dfd854121bf024f	\\x0000000100010000
50	2	37	\\x8238dacd9365e7eb295f93f4bb2a19f2f4733a5fc893728a0b210c219036295b6d32a07330a2f7c84f8fd20ad55631ec498d7c3ced715bab8428acce734b9507	113	\\x0000000100000100606c47ac0809af15c103a3db3db2bd2536e2017066c1a88e4985333cbbadc3e866b4abe6ab2117394bbd35dfd7b036426b71d1d939b34f82c33524f31ef79882f0e94999e624981bbf59a054d715553b97c75d1d1a4c8ef0331968b1c3e4fb013185a5e9026ce7c365532c61a574caf7b64fc6f10be58a8ceab08d9060fc64e0	\\x7d90423b3bf406225e9a274b68019afb5b3e7eccc0bd826267209cf8e6dc16d3bb284c50c195974ebea1b797f49f7c81e9aedbe5e400c07eddaeeb88a26bec1c	\\x0000000100000001ad0577cc5e9329c91fc2b776d638b6f107383989ccad9921b5a8f7ef3c62abb24cf7d4023306a3aac3947b43711d445580e9b3925ac6fc4fa3c6e2710a07d9c38660e3415b069db95c4615a6acc60a349112738f82956642096f6011b3ccb36eb7174d16a7cb193b04e884afbf803d3005abc85f619da4f6fc9ff5593122d897	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xf0a840e387988ede17d94237b5f47c4979f1b04253ccf46ce98a007d2978b544	\\xa265e365c5b25c34fa89b9e04c8dc8d81be342486cc3f47e70f6d7e0d51fa5f2900331ef74f431bada42842a96283292a8350a312f2d919bcfffe29eff9606c7
2	2	\\x25efba22bcb35e1b5557f6f195924e3cf949655d1378b7448820b85383fe4b52	\\x592c63abc397cecbe87c33768eab88f82cdcca4747c80d266fb5f886e0571ebd16c5629b603cb755358981220dd5060d6e0c9c21a2f41b24c7cf3b3ecd0af937
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
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
1	\\x05a322447e0979391b3ad0dc066c94eeb7285e26da83a29189fcc2a8b487d48f	0	0	1649983929000000	1868316730000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x05a322447e0979391b3ad0dc066c94eeb7285e26da83a29189fcc2a8b487d48f	2	8	0	\\x1a98fd247c15052bbeb7cba595dd5ea0dd56ce2c9e0af520fa0ce9abf11bed25	exchange-account-1	1647564715000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x5222d85418faa41d721bb9ad6114cc79f00f04efe72a9be936e081585634c6a1e570547fcc207e0311c4fa3f3619550856afd981e1e827b6ac57191a1530507e
1	\\x4de52b1bee472e657e36bf454920fa67b3048ba718ba7cc6674ece251ac6746e9b853772d6c2e394b8f5670c7f416471e2b69e9d07f94e83bf50320296b6a7f9
1	\\x17e0cbe48b7a2415ecb3ca2738272d0103ebc68f3353a21ba8ab06ab1dffa928f638ef5636691ef57bd69a8aa6c78df5068e9774a974f1e3280455141321c369
1	\\x33648209b6272ea88da587be209cff94ab02889ae5a2749310c183dfb95b006ea3dc9d51e769c3cf3682bd87a5558220d1392917c45041e6fdf7b1831c40fa6b
1	\\x94b674b22d4ffcd0cf8a39158d726a756aa9865043d53dc0599dac336649fff4017bb9f1cee72be89b692f9518e1e80d587791d370f5b80d58790ee32b34dd78
1	\\x4c5ff51782c781e359d2dde68ea0be0f7a7bd5a2a33001a48426370eceea1425d5b0b98af68e5d8d8436c10f54f04aa55ae7c52d93431792957d392d4f14d376
1	\\x9fc59f70aea9983bd05fb674b2c40c1585f0c254cf510afbbab4cad2e9e74207800105158ea56f6da1e9976b5ed8ba9943c1712ba1d1135dbfcb93501f696e94
1	\\x86522d60ed26807d06bef843a3cffb005da32ba10aa384d35b5044d4e968f8c3de1732de1dd9007eed5f8a157b49514182a5595d5755b17546921632e5a53724
1	\\x6aad25a13192dfabbfdf736dad025d03aa31d5c445b374f81a5f76f2eaded3d0238ef753a0e69cc90b5cd69759d1af467716bb2bc9c1215b6d9afe3c78869bcd
1	\\x12834da8fac5ff327733d763c0b7ec2d213dca3c910f964a132a6f45d0334c438a72a0e66209e4eb3a6ff3ba330043c20dd87cb628cf4b539001914bdfaec2c6
1	\\x83bde56723414f83bb6af7b4f6b08a49cf3a38a4c170d14f03912362be53f757dc457f0228e205601e523784fccab96e9b6886d330a70ae85faa97de83590047
1	\\x7151b0a90187948d9f1a7434f6d07402a944a7d59f7de7323da4753c27ec426e8f7ab807042249f65ceadf208e9e1103cc751605d2a2a70e95b62b261bd9fc87
1	\\x5fd8e65eaa1e2b2a3345919320f9c06ff8178d2737d850e6c540b724997cfc4459b1566bb29374d14efb3840c400dd729946c0ac3ace22913fc6dbeb67d075bc
1	\\x04855fc180a88659112dec378020e14de6035e504be2254c6d32e530ded113c129fe512f9f4410c50c43f56979e66cb6c7a3735e84c328d0434abb9d19f49b96
1	\\x8472d4b46a879782de9b81cb63ba88c13dd3e8234d619057453e8a7ec5be125437d45418f62759e50797cc5fc30f9cc65d21aac583a0b4fa4a9d5f8a20214a13
1	\\x6c21557dfbe176e4eb795cf3956e0ab325c4d543211e334267289c65f42b5a0e7f941932a49335dabea3968c4b28bfd9da8cfc58588b0a6f49a4173a0d0bb480
1	\\x3e3ce076a02b88420eab385b594dad6444bbb30e05d3c1d681849b2069937fcfc8bbb9dbe4fad52d8b1b7b5aea266a77d80ddd1e5c87df294ca764f4df2e62bc
1	\\xa8b636292f9bb3623f7cdc45f838e6312ec0361282abfee3e2e97baf5096d76f5f2f66b0f1d8d1a82cfc4370522f22d17d47c3044b0e78d0cfab494e087aaf74
1	\\x9c2ac6c874b1dd0ade0740778e4fb9b61ad4e3a9c19cd8deb88f4da89962457b15d30c34472fb609352a3d208e9551ccda7b55f95556eb49da7c8e28b53ae866
1	\\xe9aa4e53d346409ab7da596461daa367f56ec43be4a650a910892e93ec61e990068892dfdd3575a39c27d5dee8c2c9fc84c450271fa1f8886b59c42f60c6a073
1	\\x3957a9e92c9e833be1be50f2aaaff1176cc934a097668dc089ceeecd797932386b1d49802957c869a6f89d810577152354508cd5bd510a41c0d1339a4bf910cb
1	\\x91ca2efd4f01efc70906d351eda562a5a6fa97bc86de29655ab33e2195b21c43d3f8e485ec83e88353ce40c7ca852c752f8aa015384229742ba789fe6e8d3ada
1	\\x2eb117dd6a64a076320601fcbc1fe58a1af51d60c2d62d7e4f33eb3636beccb387f9246a5e276fdd550aa4282e0988ad734df85d87bc841aa8167e66f0a9aa47
1	\\x727074bf9b0acbd78036afece3d3c9dfcc0a84cf32d35256b78c30221dae3b8c4a9ff61132d518a62ff4bdb5946103f7e093706dee3ca0fea1efd1e84d791ccb
1	\\x5cbc4f6e4e13b5bb1c4ec59b495df497018d8a7e03026bbf9b6761cacd5edae46c576f70db17cbb4ac86bb407fd399a5bf432e73a538a790f9b4f69eea1e02a0
1	\\x5c446783c2318e7d2f4141d9f71b1d27a178dcc75b87292ab3c2c21830052e5347b2319212c614c7d5d50d7e4c43c08a427c29a650f9e2efe0c79d6a4deb8712
1	\\xa6bc446b90e9f6bcc902d1f8cb9e5afe90969ea4b8214fe59dfacb89e2497fa6a890d96f285fe96d8b11d176f62f94a642f413ce03efd7b4b9699286e8dc0582
1	\\xe312f03077163470893842f2ad740e4c0151ccc5e4530e9dc75356ef4a7d6ea758451a7bdcc4f48844d9ad81387591cdcf9dba9289535f6b466227cb8f91bbbe
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x5222d85418faa41d721bb9ad6114cc79f00f04efe72a9be936e081585634c6a1e570547fcc207e0311c4fa3f3619550856afd981e1e827b6ac57191a1530507e	213	\\x0000000100000001b4165c23d216226d0aeba32b891901471c8b43083b1f4c3b656c3ffe585447a953591fcdf180abb7b09a83e2bbceae914f9881e54d129efd140fc7839e2f1c096d0b30294282c23d7845def8e289f0153eb68cb79b04e297a9ff0e52dee3bf78eb09c53c31724bbf7640c7488e5caedbe0dc12b88d404f05ff62d9dd32fffae7	1	\\x1c6af3360a92da1560c9ffa4faca4ac32d3912f7c55af23339c9d9b326f4085304c4d058754f6cd2466376294cb36542b9e1badbcb58ff7ad8d6d0b00bc6fa0e	1647564719000000	5	1000000
2	\\x4de52b1bee472e657e36bf454920fa67b3048ba718ba7cc6674ece251ac6746e9b853772d6c2e394b8f5670c7f416471e2b69e9d07f94e83bf50320296b6a7f9	204	\\x000000010000000102181a70310890cf2d2334334fc2fcf35c982bc5e502414485fb18141442e6101696a846014b0215cc7402112b58c647013be2c691f0bbeed46e7436375a41f4cadce606999345cddd939bb694951da447a8bd425a19556cfbf4fd089e6927e9b9dfdfb71ed1cf4eda0c09fe1dce8f90dd2321a2ea4eed2bab098b4ca4519ff5	1	\\xdc3402fe4aa2be5f816f0dec4ee8da08dc692c1515063686ff8ee0f7e85f52eda1c5753c39fe43602c906e10c4ea15ccf5fbe868954048db2be167dc221bdb08	1647564719000000	2	3000000
3	\\x17e0cbe48b7a2415ecb3ca2738272d0103ebc68f3353a21ba8ab06ab1dffa928f638ef5636691ef57bd69a8aa6c78df5068e9774a974f1e3280455141321c369	111	\\x0000000100000001c313e328a5acdfb4c0373bd8df59bdc84e4ed59b348f821912f4e620e44224e277ef0eee80be058e86c50172b6cda51efc7aba9e6a764c537a62c90551dac2ecf149c2ffeb8a33ed069712695756fd53b1e8832ac434100f7e4e0da47500c85fe580387a4d3efa89fa110fe47fc962581ed54d24b8cf3c6b2d25c780173b8a4a	1	\\xa71b4bcbc7ddfa2de5c8db1843dfcfe1bab926dad38600110a5dd4051a635a36f599d9807a347a3300bc15f3b9fc95ede47551f73d3037aac4181c5f38d29003	1647564719000000	0	11000000
4	\\x33648209b6272ea88da587be209cff94ab02889ae5a2749310c183dfb95b006ea3dc9d51e769c3cf3682bd87a5558220d1392917c45041e6fdf7b1831c40fa6b	111	\\x00000001000000016f9a49d32e66f4eac30f44739340dddcc2d4d582b9d682545f240357116d86a889baddd68994ac1bedcefb99d49c5f6c88b819d3dbcabcbe4ee1952518d49711e52cad37fb7374f1817d6ba426abfde83aaec27b01645aa8acec9dab396a891d9504c95619000eced58a845e27f7f5e6d0bd2018874e2b7284b96ff9d9d7f95b	1	\\x5c46c549f43b97e48b6e5a13eeaa117c521feb8d49628b67427fc0a7c5424e0c90d44581113ba810bcc06f4677d224d596e03cf67eb18b82caea995f66c71f0c	1647564719000000	0	11000000
5	\\x94b674b22d4ffcd0cf8a39158d726a756aa9865043d53dc0599dac336649fff4017bb9f1cee72be89b692f9518e1e80d587791d370f5b80d58790ee32b34dd78	111	\\x000000010000000105f3b057f8f2e5ad68380f3883a658b731e04158845b4043ad65770cd863c09f62ab34f4abd2cd89487039e9f1edc966b430d0b9893ce1c7fc0e9b24dee7d76e7ffaddd0c69678d45f7131cd12bba26ae7feb81807c768e2518ba09e80c14fd203d72ba98c8e7d715ca44478ec03f4c955309fa8740a0f6650d49a6ceaa26b98	1	\\xe13aa9fc3b32deb9fb687e8c40322e5ccd6de67e65d84e9a272e19bc1cd95c22e6f50253965ae41690eda0acc53f8b994479d7830e5f11c025daefe2661a2304	1647564719000000	0	11000000
6	\\x4c5ff51782c781e359d2dde68ea0be0f7a7bd5a2a33001a48426370eceea1425d5b0b98af68e5d8d8436c10f54f04aa55ae7c52d93431792957d392d4f14d376	111	\\x000000010000000119c96ac07f6e123679ff06db65b0fc3a6884a9d100e2bd018b1facab9005d7899eebf388307cdd71bd830bd403e95a49c37060fb685fa80172edb2f49ae7d8c830f762a2b8f3dd6ea24217935f00606544abeb93aa1cf52a319d868793515da65e9a4d9120af0843f9a864ecb3e7909725a295700e3091c3fabca20351e1f6a8	1	\\x137b03388ac3dac9ce2649c986cdeaa6d34dc2843149a9019cec9d8e7ed9e5fddc58e02c8052638dea47cd8769afe5d09fb4c1bf420f8ce378baa0454c2bdf01	1647564719000000	0	11000000
7	\\x9fc59f70aea9983bd05fb674b2c40c1585f0c254cf510afbbab4cad2e9e74207800105158ea56f6da1e9976b5ed8ba9943c1712ba1d1135dbfcb93501f696e94	111	\\x0000000100000001ae928bf895fe5fd7afa6e4b922b9443a1394dac60a626ef17f4dcbe116be156b44f2df643d9d249fd7c5d4fbf4c4e40557f0fe9a48c7a31c21239d4f415e174542b77de9eb51b682c1104dcdfab4eb1bd63282b55389792b8ae05371656af6b94f51d3cf3363f006529474059ad679c5e640e052ec4d6c38d5297bd678da48e2	1	\\x29a9f7398ea31318b18e4b6b49c72d95ddbac35e58bfacd5a281e44d813b20cd040c40aa69cde119f7a3d404bd93ada2642f60f769921f73855c0d6d7783c303	1647564719000000	0	11000000
8	\\x86522d60ed26807d06bef843a3cffb005da32ba10aa384d35b5044d4e968f8c3de1732de1dd9007eed5f8a157b49514182a5595d5755b17546921632e5a53724	111	\\x000000010000000109ad4a6f0b53b8ecdd7c83350c0580b0409da4ff88d3041497ad1e13d12f475a96f3b5f4740d919bbc3ec0a4037be49891b3e5bfba393e46cb6201ffebf49ea9982ffe5c867a561a87e5a57b84818a7347325ce68458d31a1bb00dab6572734a9986e83e3fe6ca0ebe15adad5722bccb5d08a114f851b788ac377d69adf78d75	1	\\x8c414d1c900e018caa78d319b755617db63268637361fa08e535ca2766ec3e60e6f47f4234d018b377652d0b6b893c7af7afa8cc2a237a05cd77959ed015a10d	1647564719000000	0	11000000
9	\\x6aad25a13192dfabbfdf736dad025d03aa31d5c445b374f81a5f76f2eaded3d0238ef753a0e69cc90b5cd69759d1af467716bb2bc9c1215b6d9afe3c78869bcd	111	\\x00000001000000014011608ccaa916043264d8b9d0bed20d5e1a230f891737e4d66912af0f690ffa8adfb8993e990d6b3eb6ad81ca3cc195f9ff053f2d286d9556cae680ce6b75afec57b280e806d0bbf4db218d9e551a20f8b88af0c4f1dda2c5712e023598c0f044fb99fa14c3002a37b76329d9bbd55e08d39fc7dda2b9a9a0e340b9ca7b5de5	1	\\xf87124d47dae78fd164ac52514567dc9050565510ad1b6390eb5417256ae69c0b7282f0e4068e1f1e3e7e281dfc8471635ab809b94d6f0d409977313a137780a	1647564719000000	0	11000000
10	\\x12834da8fac5ff327733d763c0b7ec2d213dca3c910f964a132a6f45d0334c438a72a0e66209e4eb3a6ff3ba330043c20dd87cb628cf4b539001914bdfaec2c6	111	\\x00000001000000014f566b6a6b30cd6c49197e298e4cc9195f82e2672db2876b5685b27effc92d8016faebedf583fa2e427a5e1c30000fcc3deb4ebe650643349cb321692fc11be2b0278d967524b40c06e80c3c692c7465527f99c6d672f0b225b5f9dbf40bccadb476e08bc88b4a84da27008dc81cf06419602cafbdce4173c909d78636242480	1	\\x72ab6a22ca9c8abfcc4698fec935ef446c33987ecdbaf683be46634cfed40e0e90d15b00bb83dde33e473c5d0a4b89a9f4f2b4291a92ca15188ca25ed56f7708	1647564719000000	0	11000000
11	\\x83bde56723414f83bb6af7b4f6b08a49cf3a38a4c170d14f03912362be53f757dc457f0228e205601e523784fccab96e9b6886d330a70ae85faa97de83590047	60	\\x0000000100000001444770cf929bab91700190b74288291609d040ba714db974b4b1e1f0dd477b20a2f041eababdd6bef598524c7abfbd3cb9c2c8a7af13da906f4144f2d5b23e6c4641d698b9cbefa61aea464985cc145ae6f16d48d016bf8f2ccf12baa49e8e946161370f758c35adc5b2987c94d7c629019267574b0b75ce6cf314c451e16279	1	\\x1e4aaf2814eeeae72026cbe74677d149ba695706bd8dbb714e1f613377f072eb256057530e246fa66048037d37f1d8da7849ad9f7cb2a01bafc16c62c50d670c	1647564719000000	0	2000000
12	\\x7151b0a90187948d9f1a7434f6d07402a944a7d59f7de7323da4753c27ec426e8f7ab807042249f65ceadf208e9e1103cc751605d2a2a70e95b62b261bd9fc87	60	\\x0000000100000001725e891abd618dc705b86dcec77c3c6fb0b9a23605619f6311a126d865eeafc6110bbce3c46344b4a49613f74f71a886a4ee7f0d7f0fabfc8d44ec93181a4c8176570d5dda4043a3477631d442ed2ff758ec49481c55c41e61baef47e648d74d045b93e0c0d3ea5775f93b3047407a043996b03235e65bc3a4eaaca94abc019f	1	\\x827d139f9dcfe760c1e0446d380791cda9fac81cccc6e07fc78f3c03b0a47b623f4a103f19c9b2add969a151b954e4453387cc41ce5a835bc28798caf15b5d07	1647564719000000	0	2000000
13	\\x5fd8e65eaa1e2b2a3345919320f9c06ff8178d2737d850e6c540b724997cfc4459b1566bb29374d14efb3840c400dd729946c0ac3ace22913fc6dbeb67d075bc	60	\\x00000001000000016f96843aaeb74843a8678dfd59d46d35f281b5ff2ffcbb16712ee5beb28f021263cb00b1ae1bb6d305a46f176e3b253f9f2180fc722021f73d476ad0794b949953d5b10003b785e62281988fba6f3d2d112bd28769abe08eb4272771ac856301d49a499299210fc45bd263305955d11c09a110adfe3c98633ab79f1986b80489	1	\\x3024481f1ae768f85937f7ed55841459c3eaf1bc967fb5c795791e476f1e4cad5d5938eac62062f81ea8b073cace06f0e4651b9ea477ff78019929e104eac100	1647564719000000	0	2000000
14	\\x04855fc180a88659112dec378020e14de6035e504be2254c6d32e530ded113c129fe512f9f4410c50c43f56979e66cb6c7a3735e84c328d0434abb9d19f49b96	60	\\x0000000100000001304dbb8608ee84818ae00120e7a16546bf862d794f7985802227d99802b04c1422c2b96f2b0b744a62daebf0b41a8e7b170e3c0b529ccd11ce9e8e6c020ae82b7e95fc63fd2eb1f7a99e7f4a337951d903721187e1fcbb0c839cc927ed6c906d2fd37c241cfde67b785060f3a4e223dbd83e9a212f31c1b7d07e08889d5625d3	1	\\x8b190e85dc001e04d69b9567de55bf3d9fdccbf274ac30f19b4f8f57aae01c87bf452dc2ac1da409cec3b6c8e2c751cd8e5b369e14877218eb29a1449738a605	1647564719000000	0	2000000
15	\\x8472d4b46a879782de9b81cb63ba88c13dd3e8234d619057453e8a7ec5be125437d45418f62759e50797cc5fc30f9cc65d21aac583a0b4fa4a9d5f8a20214a13	154	\\x0000000100000001251288c53da58e1d3d6b5d3f7e9a09ce7a57088bacba3baeb822dde8ca471fb38affdc29c0e283bbfbb18072359eb27c4a2bd3b00567bb30f171c255a3c0e899a0216336f86dc7e8cd4e04ac8af0b5a9f6b5ea1c463a81ae66632db5e9e683eb5561166ab87636f99f29beec7bd00d33e2624b956009ee0c9c7573f53611bf81	1	\\xb32de8dee2bccfbe125862a941be9d0993aa7b435ad5b52fbd79ebd2d41ca34006b1e79c8e4ceb7a0355cf784833ca4887d2409a8fc17e7c5345d94ea4cce001	1647564730000000	1	2000000
16	\\x6c21557dfbe176e4eb795cf3956e0ab325c4d543211e334267289c65f42b5a0e7f941932a49335dabea3968c4b28bfd9da8cfc58588b0a6f49a4173a0d0bb480	111	\\x0000000100000001a40566643c77ed82031d875e945f83c66327fa30c8e54ce83fd6b50eb56aae83828eb1b5ef3376762e5431572e14a3b8da8c864a3371f64c60fe81732286438dae1c3a651e0777619d9ca26962f6926f8fcd840ff48406641ac920f15644f01c46d2993f5e134bd86b95dce1efb674be3b0ab4de1bb96318c914a25ff0075e48	1	\\xd87d28c499dd3de8f295a8ca5eb2fadb2efe6e85943d5f133b18e75577df0dfd12786c4a40f701c09f05aa6c8f37b336012898acd5b976c22e95865ee92dca00	1647564730000000	0	11000000
17	\\x3e3ce076a02b88420eab385b594dad6444bbb30e05d3c1d681849b2069937fcfc8bbb9dbe4fad52d8b1b7b5aea266a77d80ddd1e5c87df294ca764f4df2e62bc	111	\\x0000000100000001bab220dedaa26fbb66a7de54fd971ca89354967e69f7521b28b354ba48fb9dae028a75d6dc92fd2bc511797ee12e51a50e4627772b19e7c3caed39a5a836220c79010b7c8c9e4d995195059c210be6d3bbfd17dd24eba3f0b94e3fbe9f048213aef9b278cb5c264f567fc5ec105a47c59b6fca4b0179583d4a24c5d2a94d367f	1	\\xbe3e768d4287e5e3a54c427703a5a39dfd830283cc046ef75a1b00be6ea4a5c519741fb26ad9cd08cfb6f137f6df1a8d8d670765dce2cea4bd7edc3f7fd9300d	1647564730000000	0	11000000
18	\\xa8b636292f9bb3623f7cdc45f838e6312ec0361282abfee3e2e97baf5096d76f5f2f66b0f1d8d1a82cfc4370522f22d17d47c3044b0e78d0cfab494e087aaf74	111	\\x00000001000000010c82040c1eb1661c2b5468576b95f661c49ed8f1336a4de2d5bf7b915d6343588289ec0878db5761dc796fedd6056f81b4237b1cc29f7b43b01ad6f9c7b9d6029256a455c8e19d7706e9c03ff99402184a3eba7c59c08d7e41bc34dbb591273a9592e6dfe832c65c91c90e0a52099cacab6676d5086ea6d9e6db1ed883d3f656	1	\\xbd5734995a0cc59f88b27112d1dcb68cb1092fccacd6da18a010c00f96664a17d5e4cba4551243b8c503515e9a695f8c03cbf91f74cc579f6e3fe9b218c0f30d	1647564730000000	0	11000000
19	\\x9c2ac6c874b1dd0ade0740778e4fb9b61ad4e3a9c19cd8deb88f4da89962457b15d30c34472fb609352a3d208e9551ccda7b55f95556eb49da7c8e28b53ae866	111	\\x00000001000000015d8911e04bfb3115a61711ae49e3bf2c09991de8e6852341038044d849443c245bbbd5362cc799d42bb1738b25615e2c086fe2cc0e3c463f932fb094af93219449cd3f29dd7f43092fca93dbea2c6d0bd3439e80b952408dc7dbc135f5ed38f8d7292aa3e36f12c15cf052ae534c4f1a83d812f97c464ac2f338500a0a0f6a09	1	\\x9f0c9fc8505cd07b21533123b3f11f8c5a47068a7e3afa43163a55a0fc1003e6c5da01388059efb2c4ca47f17c6288c7b2b91d4070ab176fc5dafc09a651530e	1647564730000000	0	11000000
20	\\xe9aa4e53d346409ab7da596461daa367f56ec43be4a650a910892e93ec61e990068892dfdd3575a39c27d5dee8c2c9fc84c450271fa1f8886b59c42f60c6a073	111	\\x0000000100000001aaf378fcb1d7eb55c21020af31b57a88529671d9cc094d9ab4712655e78ab8588bbf159beab375b4632770363d0f40152cb1461b42eda8d66182f4ffef8a9853b5710a4215605202d1f1bb28a1899283afc5bd98a11e154ba3786065602760b37d599bb83b69ffcf20582ea99cdde9d8441965e4732928657a6cf30c447b56dc	1	\\x1c341b6791dee26cb6d682646a17ad286d57f39b8006ea7a5d0ffc8af0ea2ddbd324d9fc294b494cac8455c5ce1e9445f0e439703023dcbfd2fb05cc2d911708	1647564730000000	0	11000000
21	\\x3957a9e92c9e833be1be50f2aaaff1176cc934a097668dc089ceeecd797932386b1d49802957c869a6f89d810577152354508cd5bd510a41c0d1339a4bf910cb	111	\\x000000010000000184be0c15b593c43d0e5c78cba0209da9f2b2e98032e6ed2b3fca991639c94c2ca620ddd426644f2087ce1d3319775732b7d4d5569edacaa395f6d94bbc22268fc8106cf5e91f60ec8a63ac3d617da53bb7acb8d762b9ed0ca6e8720dc5fd126696267aa6fb2e56e6bc9e714564fa9ed7cce6742292314729c10b4018e410cbc7	1	\\xc3784ec8d2ea855accff6957efb07689f5ed2a38b35a22b4a0fbe727770da37e92e428c6658c171455998cfadc754ff7e7ab42578398ab7278b3927736ee1700	1647564730000000	0	11000000
22	\\x91ca2efd4f01efc70906d351eda562a5a6fa97bc86de29655ab33e2195b21c43d3f8e485ec83e88353ce40c7ca852c752f8aa015384229742ba789fe6e8d3ada	111	\\x000000010000000199b4f336fa2542b90c598515e57963b39fda981934a2077037bd7b6c046c19ac1c5f25b53ec4df540d6d829a30624f17a6a647361f431e4cc6798defc04ca2fab970ee885778cdad66f63412ffc91f4d81bda44d13118e2abeb506def40323bb59a7fe2eabb0ac595d578fbc5cde3c43cf28093f98f66d1b8d28c07735e230f0	1	\\x59eac7f658d357966c1a3086ac9e502acd36ff7ce8352c4d93b74f9b4806864af42985d96805ad513c940849a15c515b7254604262a86a0fc7075613130ab20b	1647564730000000	0	11000000
23	\\x2eb117dd6a64a076320601fcbc1fe58a1af51d60c2d62d7e4f33eb3636beccb387f9246a5e276fdd550aa4282e0988ad734df85d87bc841aa8167e66f0a9aa47	111	\\x00000001000000016c69b27a100e7b0d352ffc1e3a6dec46d182dac941575c27361eb3184e0c92678695bcd68fe8843d6a9da67dfa0c19137653de775c98d3e62a708c4746d22b32c20eea8167a30f98813a0b6fcf2195a8af7fab042c352b582dc725cfeb8c59eb55ecfec265f87776f47760fa354ad3872216dd09f9c9b186f83ec6bc4f1de5d7	1	\\x1d381d8c340c290067c29bc07063f0656278538511aef24bd0f5afad75f4218e27b6c8d73647c32bf72e992a1913b58dbe9397f7fc20b4193f80baf0698b6c0c	1647564730000000	0	11000000
24	\\x727074bf9b0acbd78036afece3d3c9dfcc0a84cf32d35256b78c30221dae3b8c4a9ff61132d518a62ff4bdb5946103f7e093706dee3ca0fea1efd1e84d791ccb	60	\\x000000010000000194b9cbc4906da6b348f3897a4e4beb4ca95b4470eb6780c8922d47bc8b1178fd7d21c3a32e7a48bff1f66f3a4fa61eeb3f90f3045cb014aef5fe05a1866c6599d41a15053d871d3ff13627c5541fc49ec1404bdda4caf63ef4570472b59ede36b28e24ed9e1f217184255d91d058d9777c747280b4763936e22700f28ddb53c1	1	\\xc15617e1d28f37d025946e54e2d7e11120425d773ca6ee0e720add3450bf81f66b47e016cedd60d9a0774ea135fd3de8347598e1a5e367cacb8569eae4ccb302	1647564730000000	0	2000000
25	\\x5cbc4f6e4e13b5bb1c4ec59b495df497018d8a7e03026bbf9b6761cacd5edae46c576f70db17cbb4ac86bb407fd399a5bf432e73a538a790f9b4f69eea1e02a0	60	\\x000000010000000196c261e7004507ae7bf9cbc901b1a91f90bfba75e606dd38012e1198421685a13d3c4874f6457b524e300e389ff932a094ae9282d50a017609111b70896d01986107e84d72f7c583f82f947e7d26a0f74eb5b24a3fa4fe5ce8795190177ed0ee074a6bcd3043848ebd9ae8ee112c6f18f0c83b6ee00ccb9125c911785d317f98	1	\\xd061b3af258d6ad65baa15f8426080af0c04560dd1db67157e1da845d7dca785fd2da93a607c327bd56648a9c478e49374be14b4e6f5f926fa0bed563672bd09	1647564730000000	0	2000000
26	\\x5c446783c2318e7d2f4141d9f71b1d27a178dcc75b87292ab3c2c21830052e5347b2319212c614c7d5d50d7e4c43c08a427c29a650f9e2efe0c79d6a4deb8712	60	\\x0000000100000001028cd7324dbf198efbcc8c37ff35db226bfe626e78d5c6899fa35dacd37e7c42f60394816ded74a658610ba3865837dd02340d2630d10d7a490182a719529a29f378421fb1a5457e892a84e906bd184cc7038d663b805e81cde2cd9b87cbfa5014d189009bd79d672f8df5e2f3430af85f3791e5e38f5b71ac94a864e8be2cde	1	\\xe03bc4ee255619ff9dc82f58d5c0f7d62880a32bd49b26420a1592de490c3abd98e54bc47113123f4d26d0d245405c0481413a98e3ac0e405be39d268c5ee600	1647564730000000	0	2000000
27	\\xa6bc446b90e9f6bcc902d1f8cb9e5afe90969ea4b8214fe59dfacb89e2497fa6a890d96f285fe96d8b11d176f62f94a642f413ce03efd7b4b9699286e8dc0582	60	\\x000000010000000111f45862a9a54d14d80107fd8bcb900a692fdc1ca29f84a4c3f6463cd65d6b0df8f1b9d8854dd8e6d92a22ded8f22f47bef61e7914acf016093e27075785be8f7f62456211ed2851407f86f24c50f766c9056193eb815cb5f20abaaddccd51c049ac3d872f8638ad9754cfe099be06dedcd1ad1d13b3d9c7617ffeadbeaf22d0	1	\\x7b51dc83b15dece9b92fd031da5eed918e2a0e7138cc1a5f7a492e85baa62324110c57b3fc5753c592b262a6f50c8207246a2ea14e6921ffc5c9e7c63f54e108	1647564730000000	0	2000000
28	\\xe312f03077163470893842f2ad740e4c0151ccc5e4530e9dc75356ef4a7d6ea758451a7bdcc4f48844d9ad81387591cdcf9dba9289535f6b466227cb8f91bbbe	60	\\x00000001000000017788007a602fea9636ec6dce247a927d0435a2025e16fd9a7a58af95e19dd164d5bc5cf251ac5d065e595313171a54e95a85057f1d2185d97f93243e9bcd0105b0d9576eb1dafb3e6e436a96b9d5af4e5da140bf9f8107ee1fea9f64ea6bbb3a8c8e856829b65e88dbbfb348bd773717a6d62b653c865bc24c6419448750a3fe	1	\\xb041da2d6aa6f9c75de5bce248030543767f91411b05cba738c1739e7dcec454e72225b47d089e70f9787056b8a2109670477ccbfd27ab6fb7386b1e1823810f	1647564730000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x32a9e9dfa8ff1000b657c1323ac8706c54124d53ff61e6812bdeba219586b0f773a486766a7d9220e4b88361f45d6921cbccc65e9d1466980cdde3924e792400	t	1647564709000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x67a888dfbb404499edceac25572c93c900d111ef1e3f35ed6fd5f7fa71cb0b499a6d477d407a73fc05520eed0a0bb1b43fce5299a6344be8e686385c82fc7301
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
1	\\x1a98fd247c15052bbeb7cba595dd5ea0dd56ce2c9e0af520fa0ce9abf11bed25	payto://x-taler-bank/localhost/testuser-gwke56jx	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647564702000000	0	1024	f	wirewatch-exchange-account-1
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

