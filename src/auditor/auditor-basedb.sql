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
      'ADD CONSTRAINT known_coins_' || partition_suffix || '_known_coin_id_key '
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
--         INSERT deposits (by shard + known_coin_id, merchant_pub, h_contract_terms), ON CONFLICT DO NOTHING;
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
     known_coin_id=in_known_coin_id AND
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


SELECT
     reserve_uuid
  INTO
     reserve_uuid_min
  FROM reserves
  ORDER BY reserve_uuid ASC
  LIMIT 1;

DELETE FROM reserves_out
  WHERE reserve_uuid < reserve_uuid_min;


DELETE FROM denominations
  WHERE expire_legal < in_now
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM reserves_out)
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM known_coins
        WHERE known_coin_id IN
          (SELECT DISTINCT known_coin_id
             FROM recoup))
    AND denominations_serial NOT IN
      (SELECT DISTINCT denominations_serial
         FROM known_coins
        WHERE known_coin_id IN
          (SELECT DISTINCT known_coin_id
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
--         SELECT recoup_refresh (by known_coin_id)
--         UPDATE known_coins (by coin_pub)
--         INSERT recoup_refresh (by known_coin_id)


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
    WHERE known_coin_id=in_known_coin_id;
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
  (known_coin_id
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,rrc_serial
  )
VALUES
  (in_known_coin_id
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
--         SELECT recoup (by known_coin_id)
--         UPDATE known_coins (by coin_pub)
--         UPDATE reserves (by reserve_pub)
--         INSERT recoup (by known_coin_id)

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
    WHERE known_coin_id=in_known_coin_id;

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
  (known_coin_id
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,reserve_out_serial_id
  )
VALUES
  (in_known_coin_id
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
-- Shards: SELECT deposits (by shard, known_coin_id,h_contract_terms, merchant_pub)
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
  AND known_coin_id=in_known_coin_id
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
    known_coin_id bigint NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    reserve_out_serial_id bigint NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_coin_sig_check CHECK ((length(coin_sig) = 64))
)
PARTITION BY HASH (known_coin_id);


--
-- Name: TABLE recoup; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup IS 'Information about recoups that were executed between a coin and a reserve. In this type of recoup, the amount is credited back to the reserve from which the coin originated.';


--
-- Name: COLUMN recoup.known_coin_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup.known_coin_id IS 'Coin that is being debited in the recoup. Do not CASCADE ON DROP on the coin_pub, as we may keep the coin alive!';


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
    known_coin_id bigint NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    reserve_out_serial_id bigint NOT NULL,
    CONSTRAINT recoup_coin_blind_check CHECK ((length(coin_blind) = 32)),
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
    known_coin_id bigint NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    rrc_serial bigint NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
    CONSTRAINT recoup_refresh_coin_sig_check CHECK ((length(coin_sig) = 64))
)
PARTITION BY HASH (known_coin_id);


--
-- Name: TABLE recoup_refresh; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.recoup_refresh IS 'Table of coins that originated from a refresh operation and that were recouped. Links the (fresh) coin to the melted operation (and thus the old coin). A recoup on a refreshed coin credits the old coin and debits the fresh coin.';


--
-- Name: COLUMN recoup_refresh.known_coin_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.recoup_refresh.known_coin_id IS 'Refreshed coin of a revoked denomination where the residual value is credited to the old coin. Do not CASCADE ON DROP on the known_coin_id, as we may keep the coin alive!';


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
    known_coin_id bigint NOT NULL,
    coin_sig bytea NOT NULL,
    coin_blind bytea NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    recoup_timestamp bigint NOT NULL,
    rrc_serial bigint NOT NULL,
    CONSTRAINT recoup_refresh_coin_blind_check CHECK ((length(coin_blind) = 32)),
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

COMMENT ON COLUMN public.refunds.deposit_serial_id IS 'Identifies ONLY the merchant_pub, h_contract_terms and known_coin_id. Multiple deposits may match a refund, this only identifies one of them.';


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
exchange-0001	2022-03-17 15:08:08.539396+01	grothoff	{}	{}
merchant-0001	2022-03-17 15:08:09.880538+01	grothoff	{}	{}
auditor-0001	2022-03-17 15:08:10.7223+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-03-17 15:08:20.776833+01	f	30e7bee7-8c00-44b7-9a5b-969ddb27aff2	12	1
2	TESTKUDOS:10	X9B6JJKDSZTD9508NBY7CXHFF4XYTAYAGJC55YQAFNZJZ0K9ADE0	2022-03-17 15:08:24.308072+01	f	87edcd28-32fd-4888-a8d9-7f3b21cf6dd2	2	12
3	TESTKUDOS:100	Joining bonus	2022-03-17 15:08:31.549923+01	f	a56a2c18-8a5f-423b-8277-ac59f4626d0f	13	1
4	TESTKUDOS:18	TCZGWX004T8HSNCD3SP3KDFQVH0G7EJBJQ29E50KVHSMHD0T5CEG	2022-03-17 15:08:32.20766+01	f	7e606c41-339e-48a0-9526-be02604b70f2	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
86fa74ee-d047-406e-8654-209af5a61cc3	TESTKUDOS:10	t	t	f	X9B6JJKDSZTD9508NBY7CXHFF4XYTAYAGJC55YQAFNZJZ0K9ADE0	2	12
18191e48-8c10-49e6-b8b3-5ef251fe2698	TESTKUDOS:18	t	t	f	TCZGWX004T8HSNCD3SP3KDFQVH0G7EJBJQ29E50KVHSMHD0T5CEG	2	13
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
1	1	52	\\xe09693b90ebd8ada45f7730965fe74726241cf9ece95360678230f2c2304d18fa1de953d982683a69ed2a81a922480b717b6fca2fd7027fb799cc16211ae3008
2	1	168	\\x5a06f385ed420d3fac5491a29b5a5b0bc6bac26f7b87f0c6b913800f25f2726b8c261257c76a18a50aeeefe2df4629a751ae5ffb1a8ae88a7ec992aa5fe62206
3	1	177	\\x25476a50e17a9264ec5b4fd50eb4b10398075b5a5402f036a43aac77f7c4e6d3c88ee3333c4ccc9a9830dfb4aaebd6a65cdef4927e2259d720a61acef37a5a03
4	1	263	\\x1751b3c42e221b21fc8210450b6a4c693a714171cd5607d26c3f1426eabee78de3583ef83d299e91d279b4b4fd520b60bb2e2518cfdbc9ab74c6aca751adf60b
5	1	61	\\x0a864d71fef3193d3afe813a2872b88855989c6cee23dab24c04b6a742a8ce09a6835a198f4218edf301424f50f6474bb184e625424ef7532b2152867f04460a
6	1	197	\\x367ed61af469d8e8e6410e9c629288805e021bcd688ca4860a9875a447333059a14f2cbb7d5c5d0b9bb59943270ca32a44d11d0f16f32174f0dc27cf20c9ce03
7	1	424	\\x9399ee69903cf3b761974abd62eb98c8f44bdebd437c8952c4929bd3f3e61d9a92dd888640a0693e6f93fc724a9a4c997547c9fecee1b9359e188ebfd0165d0c
8	1	326	\\x2ce5044e416c59ec480a3bd439efbc09e34e799436e2068a63161ab70bc8a36dde77d03445cfcc0cbca5423cf39860d5e3aae771bb464eb938433bdcf7517c01
9	1	14	\\xe6abeac43d4266c3c11710e1bab2e944886d02fbb42f95ae50b0bae0f7dd51f6ee2d08f71462f6cb4631bda3ef43681032068d3209416f445bb1fbbf9ae59808
10	1	357	\\xf59632f74f576a4d116f4a8257a94adc59cef60b0b150f3e0a5418e4c95dc13f1b90982a115a9398d73c8e5a3080da1ae2465b39ef69ab3dfadd16a54cbb920a
11	1	379	\\x4b3388750b0b7e91fd4a12151f1c7102f8add08fd1a1129bb1a67d2569a09c68b662eab829e4473bd3e530e6351051dba467e929d5a7cbaae1b20bcfb454c006
12	1	68	\\x2615a06d0fb653a19b2972b43fd3b63b433a7f5f035d8d0db69b544d632acb3920b32b961c41cc828f4856759d1a228513fc86a098a2f9d80681d610e953ae05
13	1	92	\\xc0c886b4aff37bf0616f13c39447f7c6681b911af92d7b9ea56f6c560bc05bd69c93a0f325022350da9aecee3db8813bb6c11e8006d8399fce9173060301440a
14	1	112	\\xf82562b1b5463d499413b5d5fd9404ef0764eea586af615ee795d35ad256ccbe4b484ee78029045c75410ce3b50c15e54cfe5ce01e6fe78cd8967095b3a4c908
15	1	368	\\x4d756fdfe9671abbb6188f77910be5f3401b7f92d88796d2c7026fa905f45ae4e368c69c50421f1da2f4839b26465053b26385b41c4a54aca99a17e244174106
16	1	256	\\x6ce58b3667b21c99e91ee384b2781e3ed118854fd0135f562d9a448d5e93d3baac5d2eb9f805137e6adb11411f28147db0fb037f226a6c1ad86fa875b727de09
17	1	33	\\xa521dde785385c4c4f84792f00b36a869a8eb249214b6e55557e2a686ec401bb8c4d39db04a65eb8767019f70896f3bbbad9861867b1b9ca5bd599bf553ec40b
18	1	285	\\x1452d21fa84cb111a6351d4f294631074dfbaa1bc5918d81a375d85c6b190324e70265944aeb6d4e54190bc9ac78f8b0b9d1b400188b4d2c687668c4b7c00e0f
19	1	139	\\x252e89defb794815a3998620f09030309dd10d5dedf9264fc7d5ebdae6ff615b3176d68dd4af00b34d40c2418af226ca92b976496f46c920bda0ad008beffc03
20	1	137	\\x7f93afbc0d9ecb642a15c6111c673916278fd9b4d1777d7b8329d5238bf47e1e10ffc62ebb4db78de3685fd60486ac26e83c2cc96bccbc41fc04859444a7a108
21	1	78	\\x7f0f3196abb987c12ec007d9f4792b5cad55113401f83cdb4a8357d141e2ced0b4c2c34a7e3b7a1f649332f6aaf98b4d992a7ae7ecda44b79c4a3e5b0f188004
22	1	102	\\x2f85ce07e2865d3a1bfa43e740fbc10160f5dd3eb0a72eadec9cc1c236ec45cb71bb531bb88c1be623a4eb8ff4aa38dedfee3865035374d1993b601656cda907
23	1	134	\\x335e698df3063735985d158cd479d0fd4f26e7dae574e0989712c00bd2af20f975d9b7a94fcacd5193d330155def7ebb15635a1df52159bd3c353a20d29fb909
24	1	395	\\x378a999de809a4d86d5835864f878c1cb3f2f4590602fc397445ebd04ca6c49427f56c86e3870d960a66ac4ad0bac39ead597f22a7abdd012024bd6a78db4905
25	1	380	\\x5dba62ef3b93dea4402175daed02ff32de4db24267e699ccc86cbb823bd59128b64f448f17b68953b0b1890e6238121c9f4ce2aa7a810386e28db07bf97e6307
26	1	70	\\x95e4dcddf55921a34a3deddbaa5998ae220de41f684e8e67efa2f18682f3687a671c2d35df158773ba54e3b105df3b6522ce5d988b2609353469e8949a375907
27	1	175	\\xa5a736760983ee94b891bd41dbb35301dec23173ab038151f93b4f9498748ad59e87b7d4b011cad7815f04e519393aae0b606330527db204962faad9de7f1205
28	1	308	\\xfb9bedb447d1af92c9665a388b0a123c5ca24bc6826bce7e9a7318de01e29dd1522319e75f7351f9d05566df695dc8039668d77aae7c04724c5bbad2246cf10b
29	1	178	\\xeafa11bb95c8d544f2d6cd9fe07ab462668517335b1c072eca5265de1285a71c43664b4c18f041cb11dbb2ab18e33c16c530f8d84e3314c8c633c43181461300
30	1	324	\\xa7361d249d6797817e2aa9d07974dc8f3d87c8855c0c51e82c9b67f7e6dcc956ec76a5e906c43f310d1b1d389acb5d7e974c8b0bae3f1bcff9fdab0bb801420b
31	1	15	\\x5b6386ee728ea3440d18341996afabfe72515c73a924fbe7db579e41da9287e347f4d5c8500ff9db25ab80af1db0eb0f873a93c5c9e2dd229c104a9ab4319a03
32	1	316	\\xd2a12ab1b218c966e24e129db1c0444dd539c5bbc8a327abbad7be8ba827ba64a7adce5f37c40abe7c46acb367f7d26552e36c72758de094a2c349e73a53d109
33	1	152	\\x9fdd4ea250fe2ecdf41528406686ef89ab6bf5da1dd0b2006498848d4a7b9421fc92fe6adf26b78ccd076d4c50b29c98370fa9dfba39b4deae974f8aa5b4160f
34	1	355	\\x1f70b9757a2277ca48509bdfbf06e63742faca590d56644c07191abad1fc5a13d6dcefe391282fc2b22310c708e45bf1210c81423e85cd96b4baab666193370d
35	1	186	\\xccedd7100084aba85c75c04d9af8a691921095142abdeaee72d30a0b3c68ce1055ec7eb8a047a86e467f368d3f6bad8f92a9d15096640ca200f992fca403ca00
36	1	276	\\x3d93115693dbbd01cdc080c2147218c4bda6b39e4db19e79aa6b044811290794d68af89f83b8a978f13c7b609879771f3ff2214ff670b2b6fb702449fc19b30f
37	1	74	\\x081e21cb3d5a5e2abd4914233756df1c840698afefc10635682e8a54b5e33dc01518c0468367068015c2d92c50adbb13f3872611cc4f0bcdc68a3b8018a9ce0f
38	1	222	\\x31794497eed7c3ed97bdad1cf5c38208dbf6dda55dc1a381e3feb10282bc93e63639208ae0fec2f8091e7a751f1c4afb2d51e81a40cf3f0ae4e304e564409b00
39	1	234	\\xc9e86011b3eaa5d684c237e39f7d71ad788b2328775a778ff2f75aa8e9cbb7869dca17fe3df933a2f0f86e217cc6d350ab6887d4982aa8db39e89d5de705680d
40	1	239	\\xbc3b95240e80906d881d76f8bb8256fcfeee24afdfb25d748eee2b74e5de004211d3eaafe6574ae1d114efabcc4508ac4ee9b1b98327aec068db77594be4920b
41	1	35	\\xf274ad5afa50b7363bd27ad91070044ff7db9ad5d4c9602cb748fe4a8b60c46383a2f2fe2a9beada375c220348f2a3583a74ea205bf85d8dc7581b25aba31901
42	1	371	\\x72ca25f56817e5dc627c6ceab36be2d280371328150d217cd74f1bd18d529679ab1b2d365fdc49264a830eaad2487e270c6388255c0db8d5972e319542012e0a
43	1	261	\\xee0769a0236685cdabeda7c1a01f172b3aa140de9f01cac5125b0515a1b739ac4f39c23a6fed29fba92a74da943d2b5d9e691dfe316e5ba79331a6a6aea8060f
44	1	89	\\x5e562f0b4f4c732117ff197bdd1346fa09d34fbed872326bcc38417e750d2541db6422b55fabfce4b24634557aa4d1626391d778ddf63dbcd218f7c6475c0c08
45	1	313	\\xaafa4b4506a4774aaa238ee35d90295607c6c34fa186cb488c7cc7f0c6623ea35710cef967fb2dc2c60feec0e406719801f9aae4ad1d80a54ffad0b1f47e080a
46	1	320	\\xe32b222ae8584cc7a1bca6ccd0ee37249462ad90aab27d6b4dc7b2c664dbb8be380cb52fdabf3d6ffaa27c0905757b742756d1bf8967f86243ac932f48538e00
47	1	210	\\x6b459b0c96efd9edfe81c05b59d394776ef17e352f31d74ea41c0da375ac966b9b2f0be8443e62ececf81bdbc41288cba94a6eaeb38d5f17dcd4123495555a05
48	1	298	\\x4efed35bbb491d1a76621193d3a11c450f26f65226c71120b7cc777e6eb740969fd245005c3af1ae1a9dba7ec5dc6c120d85c6c4ee29c0cb65b385e2a6922009
49	1	382	\\x5f9169800c70d4b5f816be20dc5ab96ae5eebd38f867660639ca65bdc8f2ed5f9bead64d634beccdb3af92eb411cdd6c83ac1da73745ebb5c4d06a2272b54204
50	1	411	\\x55b4bf4907b38a894b4d2dff49ae3b7798a020986826deb29808b6dea0fdc66d75cfbd6d323c4d8c9365cd3f03835390ecca71e445d57e9bb6a7f5caa79bd90e
51	1	113	\\xbde21ec48c3cab3c7d8206702d3cdf7cc85a1faba38e9405158e324bd78c772b09a82f26e2495ea13574243f743e166a3333180f91c5086373742235f1098404
52	1	183	\\x4cdabf5a881fab7e0c423ce8fc08054e76fc4e60a3790e393ef23b8ad26a8ee058b37f3f8cce588a4a4fbfdab8daaf54e2751bc6374841e6d512d77eaffc940f
53	1	221	\\x715ef36f89e6c7698f27df1401e08e05d68a4ffd124b22e74de791bfccd3166855bb25f277f18e0aec734baaf172d4906023a985299317799ea8e98af344b40f
54	1	13	\\x04ffa35953d834c89992a7ac6884b92b00c1e74088bfb800d2994d1d84e8b5346429aa717832ae55ca899830ed431a5ad8049957174fb0d41c693bcf1797e605
55	1	100	\\x4c7b5bb09f8a90dcfd9d5c9c9ef557dd149f4e6d8dea8df85caf2170c5f2a50e0752cb45eba21d8b4eeb5b54b0440cdd33f2d79a1d1552f1d0f3928002df5708
56	1	104	\\x68ae2e9b885accbd1e79b7e19f7f157989e35b37a20d20d8bc3b880794aace488c43a7cfe7320e460c623a97ca571f776c6e525b2fb233e8db6242d18bf17409
57	1	232	\\xe78996915f4418f55595846a9eb1983369eb5ffe94e653f16040bf4a16bfa70a7257c68b0803c722cdb12cee6afcbe19533e97fedd51be97f6502d0d27e3c30f
58	1	286	\\x8ee2a8091e0fc8f859bd593d1ea92687d792659cc441f32e9aef7984c42c4abb83e0bfc3151d61cf3b438752fb377f9cedb172b3931bd168b76537981110330c
59	1	153	\\xcaa9dcae5500376216428c99e507e956986e4b16eeac0b57f9555b2af4ee9db5ff14e626ff9cc56f3854e919847eafc19ee5b0c9195a26c2732ae3b50eece00c
60	1	161	\\xc2f7e4eb56b9d1fe31f0076f7cb7f273336332e1b4570d357b3bfcc7a55c9b72be47a1d4f7ae3bb2a7840d09fbc462122c2d9e05296e2a6cd093d8c956d04304
61	1	315	\\x74962237b3286cfbc20fd5c73713657b98f534668e1f20b34eb9823df8f4d4a8fca505ef91ff4dbe6bd80c44af69e85dce8f05d188bfa2bb8d611731dff70208
62	1	235	\\x1d05c2f9a432cf50a8a7d120fa0145dd3b0be9ceb22fc658d9b28567b99a6bc544c38bac3d4e184f8abe0a1954192101bb98388e9f6cdd53860112d72f0e4106
63	1	83	\\xd97a2eb8e7e4472627a023a50fdc9ae3f9233043cd272280bcc6a59786f65d52d740db57775c5d8f63dbeb704aac53c8969a7d3f08e1b1f7541ca2845b4ec803
64	1	416	\\x92f4de77580b7798687cffd00d23ed3fa97035e2150094f491a396774bfeffe9bc3a83c76b39cb958b74f50e337a84b84f6c5dc93430004f3a0a6e63cecb5300
65	1	242	\\xe9794c1444cb127224e5471fa207563afcf9a8f5c3a62dc9e7e0e936749f7531333221c5eb00d53a5316e59866c33f97f7cac05afc2805cb0b21e9752bafe409
66	1	339	\\xe578a14ee23a363d5e49ca68fe2975b35c2043599eea55374fcf6bf19fe3f7a0fc214fc835ccc78ec8e1f5e42f658d66f40b5c21111e61af6761512d11a88408
67	1	227	\\x1e441cedf5c4d9f0819aad694415458f4a343c7aa8ef1a1154ccd38802ff5ca94f99c571978e5d55ca701e0982b037cc1af34636f198944aad28fb284079600d
68	1	330	\\x44ed5d8c2bc855552594e823aba2443458281a9795e697e37360883a1aa2f34c2f17ce45ee38cf63d2b4f4aa41c59390b3fc6f0537cb64e0a3275b1ed1fa1c09
69	1	226	\\xee40fd3dff09489b4be20a9a5f10787ea7c4f2dc765f7a4b564999886906a3754973689a48d8c772f6a22a0646d7db469ccba467271805be128290684f20f90d
70	1	228	\\x73a7442f683436c8a3754c3f25869130b8572a928cd72960c242cde77fb458adb6eaa819bdaf5f73de8f6790139447075a7d22068a776039c805f5ab24f5d50b
71	1	118	\\xcffa61db6b37dddf7d5a4b7baff7cc4da218fe046851a7c805b07866e52e286ca2662dcb978643cfbbd95a80df3aa7ac7b2efd0ef86a481ee57155be40a1840c
72	1	38	\\xf34587e39336808ab42d64f4d48caccdeb70765a566f40eb8c9da8243066b2fde3f6cf3c9282f2ee2972990403ec2c761f57eeb874acd4de3cec399de33aa209
73	1	288	\\xbc8013494ef9bb7ba056768896b71b9c0339d47b0517bb0725c383f19c9c0d84e1ef52b85b5d8c478eed15a6392a123f274cf2c8b529de292b7da7a58dd5df05
74	1	327	\\x553a36fd35d7a6d7f707c766339f4182f79e132b12f61366bd438d94fb6b87591e35ecffc8ae0a280571408ce8f0898c6591dc0183797a446efd0e3c5578e60c
75	1	32	\\x1371eb973a7fec01d5fd44a76c38bf783199a237d4bc2ac213f4c392bc95bc111618995bf235860e3a0788f0185869903d7cf6fbc36043832ee3cd179093a500
76	1	378	\\x7b49f65693e122cb29f2454ef1a6f564d1843129faf2aed04ce436a35aa19244605584cb77d97ab5daab5b7d259d67ba708dbf7074d3166f5867ddfe92bdf406
77	1	352	\\x760eafe7e176e3ffa1301a94c5b8009252ceba13ebb965372cadb63ff308c2d9fe7f08fada74499b68c10f0677c1302ef12c81be39a63ed4bd3c2da3d5331c06
78	1	385	\\x6ba85d367682bf5c983a06e54451d6d9c04b6b161bc2900dc385db85acedae765efe01ee814d7f413cbd5715b358600d73e527f39494c057a31a238faaa0d207
79	1	6	\\x65e062493316f832a502a7657c9a52254d39a5e591cd5766fa74354839a2cd9a24806259b9c87ba413606835cdfdb3a23aaf551ebfa8b869a0907b04db3d840b
80	1	176	\\x12b828162c7fb98f4ac61b8b136b51d1ebc7e3367ddd3e527c13648909c1ec6ad98cb8c8e54f015d5c075a3841d9070d51c4950c126008dfde4f78f07a16110e
81	1	179	\\x8a84929a9fe039ae44c641604acbc374b385235cbaaa5f2bea3f7ab8d3f129b94f6857df2088c985e3ed9a3cd0da42d972e0ee7c0cd4b509bdcab662946e8300
82	1	125	\\x58478540d07b0969efbbe12ba1d1399337db792b7e40f90ab458b618bb9358f2a1f0933a48c14e69a63438f789566997c1c7a2ebe446675384fa9fa5f02b7002
83	1	76	\\xd9102abff42579eb9a48996a4df3e08fce03d74910278bb66e1b473814ebbd62d703a49876a312cc343bdcc6797c8bd200741ae15f1d6479bbf021f38c6a0808
84	1	375	\\x069502cd94a416ad1616472973290bbeb018da5286bfefd33156fa3b57737abd9f3f51df2b954fcbfb7a484b7ddc704798dd35748a8e58538304910344d4b606
85	1	97	\\x8d9a90ed9e5dbb357845a2df49522aff172b296c261e4b88dbdeb94e279d70c055da7931e575d7deb9a6227c22c4f1dfe574d7cbe4613f331d5799510d346a04
86	1	410	\\xe3cacfe95b511bb7bd1f4b37425dc83ccce9a916000fd4f50e1212677598de98a0bc1e3fa431af455226202b12b5eab4a7fef92f2cf1f92f46e3440f4b399208
87	1	80	\\xde3b39f1e1f9d4666cc91e1a7e8d0350d5863e1ed2dc87aa4878f06b1dd950aa64d32793ff67e98c64cb1296b03399a720b46b7244e361eb9979def50403fc08
88	1	194	\\x72e38c508dcd8a5a78ea1bfc73151bbad8086e2121bc6409a9dbd6e429d2612e95b2820f30c6fcaca1679ae4477cecb5248c4176811f37c82631760cba549201
89	1	8	\\x8708859f758edc3a036f9717463a96d1518206c8b6df09a6f020a978d2a0b68021aebe9e5a6247f34525c5214de3dfbd38e4f26b03663bac75648c73997e300b
90	1	138	\\xda9f1c5b6646344954883d4b292cd5be2c23acdf29bd9e251e5655248b3baaf387c4012ad5fa2fb3de9519d1599550e0eb15579a74782d1bf71bf1526af8fe07
91	1	30	\\x507ecb78895c56860313b2ab793aee0649e04f657505b8188ef5b5c9a1779204c3bbd0a30288ba29dc3ccfbdbc6ec4206862bc9d9e6e566773c890945a9acc0b
92	1	23	\\x35d0ac17d56764c79adf5826eab781bb5db8afd528b63280600bf028fd47d853711a4c1b6c80d0faaa37fdc0537f49f86d61f114a47853304e71c6a4b17ad101
93	1	290	\\x6ac52dd5a68c3729c67f4d0ab688bf8af709cc6f3101df8b6bc6466d79ed5b6e609210eb96fe67a109412b8f91ef18e407b99dcada7045d5539225df0995c20c
94	1	257	\\x2a81a41480a0986ae18de63d5a78a4a516c10175371910475779476e3d2e80671a5350875a3e5c5cb3fe3da5ce10e6719ed8220642448ae816a5c52119faba01
95	1	413	\\x2548cf0978f732c1e44a6524c5d3e1bb9da0316a8866eda9f629478a608d56a27d132b10525e4fa7b45dba68a219f3be6524115d309f36fef4d13e06f55e6f02
96	1	417	\\xb5bb423205bca115d2289d0c797ca7f7663425178d33d9c0457936f02589ac27c387ecf29ac5d573d6f4350134f220292e2de54ce5c1725c5ffb070dd81d600e
97	1	241	\\x8e43e533a87762e102d81844dc46f28c9aad4b4582c37343cdeea18737524cdcf4b5de41b2e6000c25259bcb4968fbeeecd1ad188a2a5f41b757d15e61c3de03
98	1	41	\\x07454032b15d4dc013a0069a0c98139875d04aadd746e6a0f4985154f115d557d418f9fa3af968d29af6265b9113193124c882411393ca2d0e572e0855daea08
99	1	310	\\xe2a021ef40b3aed4097050c4a595b1733b396f8110277336c825c1b8f1424c5c7d13afbe8b6e1bedd27783615efa4c2ce7c576227cc7771d4212905bac30c300
100	1	108	\\x4587f00abba486c4d5bdbc3ae8ed0e042754a11fa1413dfc1b268fbae2c3f9e2dc0849f3fc81be0f4ade7e23d21b79cd0ddbe0a5a4448e637152268abe8cf108
101	1	343	\\x5cc43ce14230e00be6a098a183cd4349c7d5296088a4b127506b4ad41901483b2782f5acdd6db2b0d8e61623bce9bad569ecb3c0ea6ec1144db9c439ebc22f07
102	1	251	\\xd229f949637752e57884c53aa3b54de997ee865687130997b3f14b24704523b7d01e85499a66ab83d527d152e182b57629d7548150f4a521ebce8cde81e2920e
103	1	40	\\x7c35d809a086ee5084b784ac955744c51a82184a2bd9bffc34e96257e5f28fff77f2e5931e95ed0639f6a40c812ac3cbcb89730606f4dabfaed66bfd53a9220c
104	1	115	\\x5c6011fb9fe2b94bcce0e8d5183b1a7547ee1615f124e688398140cedb228573cc1bc1102ec73565a81b96a3f3130e2de507aa4d7f37dadc6d17a4b927681707
105	1	351	\\x69c8614fba2f5cd5038a5d6fa71225aa36cb381c33d7b2cf1d2968dc0442ddb39620f03c9ac9866751889a49498fe43e8f392d36ce97752b44b2153fadbed209
106	1	173	\\xfa9a07e40020c0961e4b2cb080e47bf0bc56cbfcdcd2e6c959ccf87d60f2e625fc17598c428c46ca206bfdf4e655f7c2fc85db26d747900851fa74f848bb1d02
107	1	88	\\x493bbe2c352a1595db4936fd51f45a75c365ee5cd43205303a509dd33a68ba2c27efea116e8fe49aa46113e0986faaa252f2984af4ce2ce956de77284a633b0d
108	1	20	\\x6d458ce02b2f61451785aed472d4a073205f3b9f2bc644ff5ca0625b7c2b460f6c0ca44f230afcb48afa520cfb52da2918cf33847144de5e0b0fa5adcc8e1f0c
109	1	27	\\x3f6e6c45d1e53442805e88e214f78ff244d643049c13dee9a93fb8e4fde6ccaa875cf8aa1c42569e87e39fc04520b1b6b965b7cfcf96b8ec4e4c2894b8502e00
110	1	65	\\x90987b65e2b81d3aa114b0d9a3966b25342be54f33208d9b14d68bf0346c95fa56d0c3476e04bdd2fd4314694e4b22b84b25c309f87c7f77b6fd9324b9edcc01
111	1	205	\\x0c0822df4c6d8ba663f461ed541ee9d0a2a841cf22f6cf6fc8829f2f39e32ff742b9cb9ab6163cdcafd5462f8d67758eeefe7df1aa5c284e5fb182ccf2a9ab06
112	1	143	\\x323ca7a50c529b89fe1536fbf1384627ffe7487c048f72c93344f0980eaabd40c7c55654c1f2a3baef7e84248e2819d502077a5e69a393793ef9601d42d49801
113	1	268	\\x6212d3f002cb81368ed740161005ac6038bfc4e0f14f5049f795ea6415e27089679a1af9b50f914824e5d8ba3c3a47d2621451151670e20720962c8a010a7701
114	1	172	\\x84297c5b6f93895a575901bcc3f0330c1d0047adf1c5beace674dd55563fb4baa6e74fd4597e5ef44c4fd6074a90778e25cc8315d32933dc8516a64cb3228d02
115	1	384	\\xd4dad399d287806a4bb000d64927ccc6e749e4787c3771058269a4123bb61ee9a5eb455067f4ff6355ecc9767b8f270c45657b20aa17b519717e293461a5c904
116	1	44	\\x747809e480301c5d591df32f6deeb17e887aad16272687c450f0cc6dea64560b88ed7429388a7c40dd9601e70bf90ad5f1d9f49ba709b26933c66180b913440d
117	1	42	\\x626f25388453315b82b4f8374da80e77ada9cfeaff8ae076581cba368b0b9dec59662e053a07d69d37b3c0aa657b8f6532aa1d5160b5418f9c5ca491fafbd606
118	1	389	\\x701bbdd578a005ee23f907a3642555422efdea210ed493dedb73b399a98770437bbe9f0ac64f41e2c07de1b45bdb2cf3c4c557adb1499426f9e7551ad89b8d0c
119	1	189	\\xead49c0e8ce0f087ec23efbf56e5e3240c89db2b42b6d85f1c30a71347ef0fe3cee929b90d802a9d2185682cd5f1f62a00500878d74f362678ee6d4a9e2ef908
120	1	376	\\x410007c0e09344a3a9f5a69106da8b4f66ced1843fc166f5d6001a46662fa26eecce7e6a21113136a01d509be4737cdd8fd8601bb6311abb8d9537d56af2000e
121	1	388	\\xd331cf6bfea3d542c2a6855071f2fb91a53a0e0d7f166f2925f01a546adf3618de73e3c236ed5ad1663b00aff41efb771decdf3b96dfd193957e16291dd7a605
122	1	314	\\x53fd6a3f19fa8b5614fd6b08b55f521396337b4f7523ad45b8c55cbe5d9a1a737f3954e0ec3386c798db2413ab1b184086a03fa2a86857c9730ad8200aad5907
123	1	26	\\x68a1ff2c74ce25f2d29fd66ef33cf29a33506af3866371ce30a1ee8724da61059f5fec5dd8b9f7776fbb750e488cd1c1a81413dd3bb4df13359ff85792aa2501
124	1	146	\\xd44660b2c75aa93d35624939ebb2b3462fca4b817c1124592defd6fc0070d80095e9bc7bd394693d6f3e8967fef89740254dd07713539d8a789856ee3620c30d
125	1	182	\\xfffb1915d5054555cddbcd219f63192176b2103027094c5b6875c368bcdb0a7b6ee7dc29b62d189f68658068dc727ef8240f3de7a6cf1b16b15ab748679b8e03
126	1	282	\\xb9f0fecf2d7f39452c69d3494347bcf0f0c6616c0176ab29936df246abad774884009c538aef46957e08d773c5536a2fb3992d9a2171b0d18cbb6a3f148bb80d
127	1	107	\\xd2f84807285c941382abc4b7d872f08bb6137cf35855c75fa0e693a2f2688b87b261ac8ef2a98d676ad03dd6caf03256361e40798c86689b3946958416b23b0f
128	1	271	\\x8b9a0c7296bf3b79349ac99c4555c5e50905f9cced92f00ef4d59b9354611811fa214d19cbc4c10734f39c0eacc62d4346cfe25741875d1b6d63f3247a71a50a
129	1	418	\\x4db9f9cfd64dbde44e2fdf745e79a49176cef5ab546e1c89fa6002a94e7f28de03056021c7d2dc16eb85025fe44dbd7176f1570690cf489ae4571158f7ac7505
130	1	55	\\x6ff8474d2b92123288bc29a14b0edd7e971d3948032f4fe5b39aa2a7fc93dd76a9bbc79eec25268441d05b1c28014ea225fc00e9917ead5440380041a9259301
131	1	387	\\x9441c5b8fef0f7dc35a5e0065d474070eede17649d18f599514a266073dc3c52bc2a638d2ca5bd3c6290b2affc30a22bd8e196ed61326ca63c0a630e101e3704
132	1	99	\\x330b261d6394e260bdefc66fe55e0ee22b96b58d3912e2c6a9504e1d8618ab84332616338cf86f2012cefda417a00854ad1e29e83908d8528c9cd5afdd4b530c
133	1	349	\\xfcaaed46885b293cdc1c8c33ed1ebe55b6f447eb2b9e9e86fbb2bf947c55b18cf96d9c7eea85b8501a34f03020b402e04d9463e4461918a19b6fd59cee98e402
134	1	219	\\xb93a2a8a42c3083cbf0282654dee860c71f433ddc5f9860d8f331984673f14bc0097c00788462933a61ad2384d6325b7ab6abfafe170621ab82434e4e6332f07
135	1	348	\\xfb5b455b3ac03072f3d817a0cef565d6325c8819c58777e180933eab60c66d2f3b69f6db0d4bd45c507c73fd1cf265010701f79b0c05deb51591519dbfafba09
136	1	29	\\x102dc7d13f24ccef6cbb98a5961beaff4962ef2173e20fa3a839ffb3b60ae2d9639e9e8cc86a0de1cd9636f8f9e37c4b2ea15a0c8a3de9cfeaea7c5fa1992208
137	1	133	\\x7ced288fe7f92715dc4e92ef1bb3c3f6d0db17ef24af065ac8c1c624b7828275612b7e816483de9e1455381d63071c5912be8373f9f1b2e4c1553986f8602e0b
138	1	43	\\x14c3977cf4864be5a9fa0eadb9cd09eee59ef97222514209a04252e9564b0f8a10b363a2d5953b9947b5cd5b62303622ded3ae6b9319295c54acdfdfa9c15f04
139	1	174	\\x8df8dd1f532b7a820c8b812510853f95f103b62beef2f83eb2bebfdd70b7f2e765d72f1ce5e9e9c0bb89a6cee030ced75b3171208add973bd38b6d877fb1b407
140	1	373	\\x564ed9c33c488eaf8d4a707738280d6245ab5996d95c5a6dc1231db0d16cbbc156e3b251490ae2db02d27a8fe51287401918c4456405297e4e6b1592771eb709
141	1	398	\\xde46229763fc525b499055290025e20054fc42609229665a7d428ad9b02fe21630c4ed860ec0409cb7c77d028ede8d36f73446b3b661bfe7877c6260e99d0804
142	1	390	\\x02587db847412096419bbe2bf4a5b12d05f45d649fce99b74f738f5cdc51aec352cdf41b9d1d189a4657f34a7079928e5e59b0c5aed9da6f0ec01bd9165ecd01
143	1	190	\\xbcad915773bd49b298ed77ea7ac98291da9187bab31adf6f4f90820ed29f9ca45f06aec4425fd7bb546ed89344c93d9270fb725388b0e5a8ef1bde7969df7300
144	1	423	\\x9bf81c9988dafd369fe9ceb10c0acf0ead7463bfb43c09d1119502a0675161934bfe9751c8840eb2f93c8544b0bc3513df0198b9334867dfbc662fb9410fb700
145	1	1	\\x544d9146ac20728037bf0ab8c42f0c247f79a69bc4da4bc27a98a3bf78e36b3582db4719c493f1f15a0dadd822412e8d5587a31a3c3ec8a3bed10c0bad931901
146	1	119	\\x3a037e9cce1241aa88cafc8d9f7f47c4b91a34f0a8092de76b67ba6aa84f25fd9083e5c3f71790984937aca1de091e0c66ba5632a17aa91b1d0e5bb4edefd508
147	1	365	\\xa8592643821f978c8d1cacb91f2ee5f75879f3207abe6f99d46cd71ae1eda5b642a15b057fb34db57b073d1112978d2b1e64c40afaa6783abe2cef235ebc840e
148	1	255	\\x7d6260a78be3a9c640ece2a38f0ef585a446c73720f77dc345d5fb8eff159129de6407b359b10c505066fd568162b177b02d14d006e8e2410b83ecb38a335807
149	1	262	\\x3029904b62dbdac4fb4271c3ce31ccfa2e127bda749184d0663b6a4dad1b023a29393119957e8d781c03f2a651d8e931ff498d06be5636efabcecae7f2d88d05
150	1	360	\\x7342733c20f9726d123544818f0ce458a0f1819b702b1e300ed37692277e82ffa878071f350b9a3f0f1a8c2129ac7d0b34b1e92b0ebe7b540b779ee222d0ba0f
151	1	299	\\x664b5924fd31b3b17020d242aba6c9d187d0c2802ad6801a5e1ef31c1e848425319f73650662e0650653d5022fbe33121268f4e5f96d4e21b8724f8b3d089b0f
152	1	217	\\xd3acb4a49d7659fed897394d6da26743f04c0fe6b6f435bd3b48823e8420cdeb2aac3c4597c74aa3ce0da4151900dcbcdb8c2f49e9cbea4d373c58181b041d0e
153	1	295	\\xde3b168570760fc399f9f6cf167311c251a4648b5f604f86d9a765b92de220038aa80b38d7a9f99200215a34fd250109a67f87cb216a886b034e3c89222dba05
154	1	229	\\x1a5eb589edd67c0a3449bad147b65ddc429bb898b234e17e90158d31400fde67bb80983e61e1dd62f56b7015bd25de63ff6b760638b1baf965a3ec127558e60b
155	1	28	\\x0a43166a6b518dd38a7ea17c5b89ff901542c5d05351e7c9334cced5d72dd4bd0d7991e711cbd98fccbef8873635885fce0470381f930565af8b82a3e29e4c0f
156	1	333	\\xcf8117e1d7caf33d90a0030d5b2ca8b8d56b62220cec8ebe23d5114067fb9b2121fd114834a83a8a04ab602e334108b14c7cecf982ef522d5ab65cbc4fc6e906
157	1	103	\\x51cdc94ebdf1a7bbaee04f8c4b020fc0ee6f40f2b2141815d1ec120c1e70de89527c649f02d618fdd01dbd8eb88fc1bc34d1d5b1832380d9b08ecbfc85ac5304
158	1	311	\\xfb0371998b640dbe64fb5eecbea05d13196bec93717223f793ce4865cef463891cd525df9c7a35bfcc7a1da7fa888a37a89be9cc24688b0159dfb96fc3b7b302
159	1	287	\\x3c716ea97b9b1d3de8441ec2847e058ac13bdb168dff60f5b18d129af0676aad65c55a20a1d8cdac0656cb8bc2c0e67d89ea00f2a44aca009dd0f1b9a8c07301
160	1	136	\\x29bbf0f490071df1effc383e3856797ceebd4720fd85defc38bad4d371657b18593385ac08084b31e25ed4f09405773110f117effd2b7d66e6ab04adc7183009
161	1	90	\\x4712857ee1e53799fe19613235cd47a1459c4c2efee00468787a7859e2a64a6ef64a000eaa2b1a4fef7d6b0bac0f438539f1015542f9ebbf64819df9e7cd070e
162	1	419	\\xec810b22e6c6b42131524f2e2f443fd544d72dd993af88d1535d5527b91938e02a43f116c076a7f69f27cd370c788d919b2082cc31f98cce213ebcc37beadc04
163	1	72	\\x3811c9d8968b8153fee58905fd7b3607741379ad1fd0658010f6969e3d4a65d94c63697aed78194b69908c182e8041fb4b5e3d6134c19fc7717ede265c70430e
164	1	73	\\x758917c24de720be1b86bbe0b4c14b12faed5003c88274c88514ec498c49ba399803970d37479cf5359942254ff826a843dbd7e01235b59d6656eed9191ca809
165	1	111	\\xcaa497fd742ba39858e8c577cfe53411585d610e121302c389b863872ecd1d3069cd81bc292d349afe95a8e18bd899b73a9ba996f99d5e4d009a08072026a40e
166	1	106	\\x05348807929ef4e61015b516e180df2b6bf5cb5541e49c9a06eab4f4c4e098d03bbf07136cda5efc5ccbce063485da1a4ee0a5c87f7d98d8b3b3044f4d62d00f
167	1	206	\\x5ed00f9c556c70e7d8062db91773eaedb751c8b74a4d4a71adaf1f8c252efd6cee9855f2ec4165b4e80e9910cba0cb414c6f3c1fa7c3435eae3b4676d91d7902
168	1	334	\\x91136104d5b2a079afd9b4ed8dcc62d6a174246a6b57edc6a89c3d33f8c6b2db70cb8eb7f21e5b762f0551e46b59501b5d5798acf0ed7ef19ec370cd0ccce10d
169	1	171	\\xce396c71f8df44d6bd2003a889dd4bb53357fde97ef67aed1b909e0a959190f7a9c245a28d3297b7f8197e2f523d41ba2ffe8b560ba5db94fa7eee01cb491103
170	1	383	\\x95f7bd58cabf0e2a6a76ed91d2e3ebf9bf1df7903e12a7cb24749d34023ccaf724af349519e1781e638fd70d5513ea622fa046661d90c830b6692adf7d403b04
171	1	56	\\x4b573bd5deee5aa15addaadcc175b78b398e3592bd0ba983ce0c3acd6cf485dac4d4530fd96c790910b13f478d118b912f5079f9c75f259be5c285ab1f2cb10f
172	1	328	\\x7f62cc781f14684126ff03e35208b69b86af941a37111b2386228a692af6980584c1611664fc68d655267c267e6998d932d65ca17b746a387b3873aaa8c64300
173	1	400	\\x5016c50d84ab15704039308a4114fc296131ebe4ea5ec04142a4ecdfcc1e9711110d262928913175acc7220311a19ac54b845ea1929c84f3bc93b8764c74d703
174	1	294	\\x61ea4d1831b1f7afef97eb4e62279052c9ce1d1be8fcfde817a3163679f5c95833c81fb19d29bf6fde1b9718af5c47738ee28be6d222bad4558ebbbcb15d2a0a
175	1	18	\\x384fd19090bc8db006222afe3056e87b01d71677a714c53346ea66849110ac0ee9499bbbfb7f75baaa7c7e6d2ac6ac6aefb46785d3af5326cf67692c7bc41202
176	1	391	\\x528c27625b58952c7540634299e4cb5bdd4b37f1beffbef6b8bc6aefd55fbbd778152f6207d8c4644c7861a2b1b25c83adf479b93f10ad13766b953cf244ef0e
177	1	48	\\x86570c04cc6a4f5ed30d98975c1aeb568a3164cedc7de966a6aa5722b02c851089f9aaab4f4ab5b16d6a89dca6b67fae131bcb64a47efbf5fb123ebf341c3e01
178	1	24	\\x982e0c4cb24e5d47d3b7d1b97415845b23145e031f5345d2d07fee6758b45dcf05a8e3cf4cc07136ddd525d7f8e2bc405190d75f7c39a6dd13261701facd810f
179	1	312	\\x822f3cb17ad148f43629f754a0680f327587979c74924a1820a66c8973cc874466a36bf3b64f37f90888f3a30b879f1571fd3387a584da88bdf3f1925998a20f
180	1	361	\\x5aa4ea54265997705d5ca170ab54143c420346dce9c66c6834097c4a8358eae077dc75f3ddd5c5652d4746db8278fd5294301ed8b1337c1a31d2d0a175503a02
181	1	366	\\x508ea15fc6cdbb4713655d43e20f7c0957392044fd2f30a8a15c2c7d94ebda469b1fd308914b65b513419e680997f4d4f949d20a8fa91c6d7a70080a8844500f
182	1	304	\\x760e24c73ee2b643f5132e845134523d664f7bc8f3885a6866bf30ee586bd6f54de5d3d803b4c42e3410dd7706425b22131d552a274acd631b730312e71ace07
183	1	184	\\x0c62e4f088f07868018ff12d4241bfb6608a432b14c586b56463556e3473704c123dfa0201eff41be59f3d8a97f9c48069c477d26b4292769fad95fd06367505
184	1	209	\\x286a79b7e42a5be3f8e207158b1c7b3de6bbe889113e9b1f2fd0bf27996fcdb254151e3d84af0f47684fbda444833948a8ab859576d8c4b12f15c43dbab1590d
185	1	188	\\xc542cba4165207d117b6a8fa3040953bb32a998d79d678804e2e3b9371309e66296250a3a6844ae784f614e378e0bb2dd5b6b275399187309a0af59b1743bd02
186	1	306	\\x3d07f6fcac2db7465e748cb6d3f60fc2687d820488c27f47bd810777f64bd3991c0e0a74366c8d40c544c6f32d36d2030c196c1921049e86172d696aa2c01004
187	1	204	\\x5a7019b3e594a01f67ef10287423a93a45ea9c790a2a8fca0164fdbfd2ea24b216f5e4e64ce41358b64180fb1d760aec06da00a3cf7129145eaa34a226b1d50b
188	1	105	\\x41bc19feff14123b02a374d3e059151fdce5399bb5d29c9ae365b9427c15baa290e4e92974ab3ecbfd18883ad2c3097b6ef2fb9445c4ce8112b5c4d8374cfa04
189	1	159	\\xbbf983c4262f8f97820678757bb7bf35361db258fdece1e6749c7d8ed50b47c3e49648fc713e62f0ec74a6d1bf2e4594e5532adc55f3c64abcb6340f896c140e
190	1	297	\\xfd02e3417eae3afe947db0178d5b11304c98983971482f77d375e94e201489a6ea46dfbd3ebd6b2e92fe2c833b1b1a71b56e23469e32f218aec77e2d805fd209
191	1	120	\\x787cd6549a6c3e35724b92832eaf96ba3d178e66d5d2bc15c090b2a56b1540411f174134e1e1fe7cddd296d96322d559241efef2e2c1fd98f3512da0a71daf0b
192	1	397	\\xa54873b538d30b0967590a5d29c55795872c78ebbb1812b3328eeac89e0cb8b02f571ee4483ad5ce234a3e1e916bd48125022d570e65ebde3b55fdabec044808
193	1	144	\\x75b1d2867cee94918a458a058f1c572a4394199a4348bbee2c25f545cc2f754286635f83ba17edad4ed47e1493da7e7ca36e5c2ac7b991612c665e8ef8df4f0b
194	1	414	\\x17ebfc14a45030a10206c2f7070ebae0b2d3d5fe1dc2bf9a23c31114d340dae029d4978244ec5acc493b07a33a91131083998e7d2f37f9ddfa4a410caa2b370a
195	1	109	\\xe1a93cb4366b16b0accffc173fffd213083548667b73563c927ffdc0b9a88465b058c4587554fd2eafc2387fd22196acbd37ad70d07cfdc1cb485368b7f6f10f
196	1	341	\\x28fd52b7f25ebbc9ba0e50e4469457ebbae3210bf455f1563de3be9b9e6e9556eb1d4e69f90dcd74f0b45eafc73b1a95c890e7712f16d98e0ea234369d594c08
197	1	245	\\x137b1f5d4092e2ff8ddf4a36f3977f29acd66ca8cac7be848fe6d069d278ae141a683866757832129e346f808f24129612800835d826bed6a5b048da9f723f05
198	1	212	\\xb43a936dea8718cd8f2060b2c515d2ce816c60d05c445609839c0ba341bc61a29ec54e25b765373806518b5b7020f1ad14509dc67696924803df31e2f3954d08
199	1	302	\\xfc144a01ab8392dea4dbfc9c2058f3d1fafd817183fc34375f9e5cebd1415632884892c4b75a0270941be986da7889a5e3bef393582654e9396fd6de26017a05
200	1	94	\\x8bec891ddf39d48a7f2298329938ed5a00d6e2cae6c8840fe7a508edbb69a490d61c8a08597579ed67272da4cb7a73d4f800236176a8b47e618e4e4917528b04
201	1	264	\\x29d5dec02b525868a48d639027edf3731364b30a5675da1ccb7991602d4119c4ba816fde80d35afda1e37680ee2672708ffbf0111b4e5de64919d7aaaf77a304
202	1	318	\\x2b0ee521ada422065afab9b808739bfe21e3cd3806be6e7608f819b2a791c53b3b5860bf515acc95cd284ad7a80f0bb3fb824fb144759a7b1cf3f70f4764e502
203	1	3	\\xe65978921649c9e611e9ba21636c330707edb28b4e5efa151973a8424d96e32c294c476e4671a2617674c3c77fb8f2986664f943aed9171cbee5ca8d6318e60b
204	1	57	\\x3797506c4cef6fd7530afdf8e56481108a16d17e1bb67443e119dd17000a47bcee803cab673594cb1a82736c755048f587898db8fbcc416eee4f489b54c1ac09
205	1	63	\\x836c2fb90d9a4c958e8c434aca15c78ce8456f305f1e53c056dac3a6737cdea383398efe65acad54eae3f8a8e1bafe170713eb16db50008d755c8aad243fb105
206	1	19	\\x01460589234c49ddb519d3a0bcb3fafd37550f06b2e3a371dc19a160b5815850abcc29b53bdf6c3229ec8ac8fb0bbea1811c5c3958eae526eb06386d0365e809
207	1	346	\\xdac248f5dc42f85ced95c96b777c2c3a20d556760a8a4fda3d917a662e240bd2c0c69f804ad62f30e8f5d81ce7e2b15e09c931b4dd4368b0684fd61da4a75409
208	1	303	\\x65734a4ee07199f551e1f5079c8f6efd7eacc54aac1d464015a4a2234b9ec19a178270b45b0d7141c079bb18657be5d8959391335afab377fda799781f7f6700
209	1	191	\\x0d6a7f8c11f6146f7d582470b31f68d13139a80de3590038cb9e4cc710d124b7f04635582f7dff6e273815a77269dd574e923c38092ebe2def3149f5fde5c909
210	1	363	\\xd9d9fabd55276ea6176b2ee569a71ff0a0a97a333741e27e2981f82da8b5d1f084267eca4a38b9fc1a54714735d5617b4334a59f61146a477479443b3f3be406
211	1	359	\\x06c4c8dd1b654bc04e963e1b4cb2a1de34f1b92c6f59acfa7e55dab9f429d7f0bfaf7db07ded48f6b0ed9a576b7b3a0afac3b22f41bf499402e5f3b646c7d309
212	1	140	\\xf418dddd98b3a541bbc515c75904a7617de7e054c541284496665cf962eaf93fbd7ee27181e946579447afdba60cac6741e5628f39d5c18100e6d3775cb7c003
213	1	154	\\x51d75119601eb7e4f2761ac0123a10e2c04deab96f75bdc148d45c15633a0f2d0c482b2dc52b3c85521c2b49fdc5574080ae4f7b19155aaa1f7d70e9be570808
214	1	223	\\x3b69b447abd744b732699982ad7428459e405abd131b94de78afda40602949f263b7eadde3ad8c3693877d5579d0d1d19c95112de4ec686eff9168e8fdc5c806
215	1	309	\\x8721e08359c03564d7b60f0862c3aa914147769f96dc62b8c0265f67dda7c180fc4eeed83861f30e37c52bf0514fc6974e594d323b74924527a71e6bd4bbe906
216	1	128	\\x7f0d0f85eabda2af443e552ac6e6f45d20d4d62642b9d4efa51ce64aced44eb2069a35d468fb1a8915eb467e5b708ebce1d205ad361c22eaf3a2c116425c950e
217	1	246	\\xcc921b10445ce3d24ee01a4bf35752920668bc9ea6e42c50d88c09a9b49765c9ca1193ae173a37e0c5ea19dc5269b57320ea2f7527896f9db043b8b8b0b79d0e
218	1	81	\\x0bd7dcf689b9de1a5a3de734ad0369518d3238773519555cf83770b8e25f85f4fe9e5aa900bac9e4d0179f6e4fb14df94cc932db2d9e45939be3026914952606
219	1	47	\\x5a89c0c4fb830aca3d52ceac45b8c9518623fee93224cf4e0d9d52ca77fbcda5f231142645a6f050190823ace424f3c2ce5f38873ca8b9d944597b2156ef4105
220	1	415	\\x2b8d71a1fe80d964d8a184005b3336a369c89ca2eb4bf94d4cf5abbf790fb66062b474d7b11e632d462b2a8ab24a027023b71cdfe5d5f6494865227d6b7a1b0f
221	1	319	\\x5c063806a3a4759bc2855eb282ab4b0d8f452df6ef894acc522796c722ffa7c5d6d861324b4509bb3fa7d51ae5ff9bb41ffab81c4a3e4d3e9d5315bbf586130d
222	1	71	\\xb158b60b35efff383318a3da394022f9adb850a2e5c0ecaa33ecfd771b1e980ff9d7450940a6afc523dca73b2957240696f674f131196401025514d7275d9f0c
223	1	331	\\xe77b838d973a72db0c5f58d138058293205ba4d5af937050ed4dfcd723f5af30a80d65e8830d32ecaca80fb2417d5fcf6a43751e2b59c9cfd75e834133432c05
224	1	96	\\x6d1f54d1abd5222f9b0f91c9ccc58dc1fb324e06d592f0cfb0f44997446ebf9d148cdff74cb321fdd9071984b15193225f61697a91650badefd64d7db579b002
225	1	338	\\x8dae03eb5473b85fc13845a9347b9fdcce9eda1114e2849e6daeda483416ec4bcad8e6937f1cee2fe57154d1504d85a9eeae236187c27f893f163e8173ef0e05
226	1	269	\\x642c43b8e62f512bbb639f600bd66c32a389292d05bc54bf2c0e3534339cbb3cd8497c40165ba164b4bd31a564bfe2bbffebdf517eccca75770068a174591e00
227	1	236	\\xf318fcd1e75b635b18dc9ce8e44a477db6e94a314f91519b673019c0d9fb404af5a62cba061b5fb993cd42a01e1adb024b0d8eb985cf0c8cc99d0c0aeb94b902
228	1	422	\\x8bcd5a3fd221d255a7d577c5118a312646fec9d3c4e9c37bc25cbaf76ac963058076f4ea7b67b59030b8cca841f2099c354a3f570c9696c52f66bfa17615ed09
229	1	54	\\x8b0753c2dcf2f0ca1227ff361b57d7d5b5f6e45ea8bb2f70499df2a61eff52010420279894fbf7ba79b325cf8768610e17960d493a916f62871029ac53f6520d
230	1	394	\\x18fa8922cfb4d8f1a91cb937273f066dfac04f1e4a56cd83aeb637ad49a12326f380e927f6f1be234cd3a03b50a7c0d9876189a560d93d18b23199c128fba80f
231	1	369	\\x5c4abd4ca4bef1dd8126e09bc74ca8d83f6eb33a65ae79d8ef009d2e3991cc80e9ae60c6ef27cd88cc6b6f1077480afbbbe94ae71776d6220cea72e205e67b0f
232	1	259	\\x1e289a121b429e71f69d7ca824222f2ad102c76d19cfdb68eea5d5f3d296b7bd9d78eaa9845457e25969319181a93c3d7782b1474d87135bb929b9d6feb2a70a
233	1	293	\\x67d8e49a0ea0b67eb349055ae05d444bbb4bc87c9fb2d941da06d8b462dbe16c6fd3760c3fdf985e2f5e920059381d62f18134b9a198cd67eed909a76161d805
234	1	195	\\x0cbcbce3c35941cfbcd246785f9205f716aaa7cbf6e7c3b6339aeda4cb1f71c36f546180cf9b8bccd56bfe06ba3984d0a33c7130ccf03537f8c328d97158950f
235	1	340	\\x05527531162c3408f128b94470f564c2c478e7e875fa56850fbca9f37ca2c52ae9efc8579fceb62546798a536660df3af037bdd255b0d2f378d6bcc18897b006
236	1	207	\\xfbb87d3b61a0a13793fbf70c695791598d9de338545abcb5189993e289bff72f48446cced24b4b8125a3c3dddbb9810bb8f98f43e789aa443ebd86d970111c0e
237	1	283	\\xf5f1dddb6d942090acba4f4b3e65e0358981c9db016bd75b31786340c6520e91591079e3eeea4d2bdd0ce517b26fd2d586e48a840334102525c9be023554050c
238	1	337	\\xb87981f477bb0d1f2fd32f9de7bc10283b89759a42c368af7c255a186f17451865632ce265662f5424cfd2ec6d5cacfab58f3b2ae4883423e2f5b9874196dc01
239	1	198	\\x563bac700b2b989983cd86f2ecc9e95be63fefa9e69eada9a33f65f745cf53f1028007ea8318b1875d5e7d791898236714409988d9d6e84352f91d50a1358502
240	1	291	\\x3f03c4b588d0672a78f54840e7965badc90d6c6d2c627368232eec0fc2ebe3dae9fc3cb58a2d8a9c3f8f7b81b60bbdd929f4e6fc3ba6bacd8f266d8d477c180e
241	1	193	\\x6bb6eeeb286e6c484e6ee11deff280dd275ae7d1d8e4007e310aa3ba6d638a6b518d367f86501353a7d60b56253bf8580df81361dcb162bb287c528408b91f04
242	1	31	\\xb4e51163914365bca711595e8837b57842f66b5a34f3f4d64d44fbdd316227ff2c11a33b3d106eb1d9fdf43e98c68a9abf4b42f23426e6c3e67297972bb67a00
243	1	317	\\xe1b6c773b6ddf3e4c3a7e0a681bed9cf5157bfdd2ec065a640484458ea2854ce6df61e4322f89f0b70cbc23f312a740e93d1a43bf8b99f09d1bdcd2fc5d86905
244	1	258	\\x56716af9e8280093637140a4dee372b5005c3feb763d1086ca6469163acfc3de2ef36d045489190434a123cfe44e7c30a3e647ac621389aa1a4491951fece307
245	1	69	\\x7c6944b618ace1986a91d2178e0b5ea5aec6f750b637ec71c478ecf40a86df2f0b5c06863fe4793ac2998af1d1ce087b007ea8e0cfbaa28f1465df71c9855b06
246	1	124	\\xd66f8ed2e84bd62c282ad9094a025b450081e424d069c200fedf7e8f73fc6693140f99a7452133eacc6c86721a856cc3583aaae3a15103226278054e4ed9f305
247	1	17	\\x6fa5d1f0cb351970d8d60144174b58da9b650b3eaefc0fcd3effe83e912210057d05773a5ac754896b15e0fde34a74b2e182b83f4cf07819360415823d9a7201
248	1	141	\\x5093edb1d5b56ccbb6dff537d6b06f47489ccd3350af95fbb551ed99f5a31261846d69899f4837ce99b0ea490f3719d0d61ecd732ec5f437278b4bef43fbf40d
249	1	322	\\x81609e970f9b00aff93da00ead7430e3171805e91ccf5fdcb4d5c2a547f17780c753f31ba106259ad413c5b84557cbab122bf35e03acdb885f0ca73daed4c902
250	1	406	\\xf8366850126d7ccd215f0901623cfc2d52ffd1cfffc0560d338df97c90e8ca8953742db64ee83add8cd7225daf9e8f1cf0fe410c8fad98e026f47a4202fc2c0b
251	1	250	\\x45534a2f4afb5bfa13f0244887ecf521863aca69adeaa148ef0f0e9d9f439f6482f15fc7e9fdd5e7f5792646c2b8f27698ca2f1a495b23b358bb593328fc5308
252	1	129	\\xef7a137989c2d03fb7227ab52a47304f11224ffe0d787519ecc92ba029028df9913316b7365fe2131bc80d0cb7713a2a056eea6320f7e60dbac9525273d91c08
253	1	356	\\x2e69fbf8441e579a2d40e99c53ab822d485d5f714102930ac74b387e2fa521f2c39aa24af83677a93741c5bc668dfa31deda1e13dd54c66dcff2a22613e8f70c
254	1	169	\\x558da97edea0706a495910311c7cee0f362011017ec805dd120f31455ac8139dece67d92b1c52f1be9150d56c07bb680d70521641d4bd65c82b839f4e0dbfe00
255	1	131	\\x30b6c0e1bc7b7654d49d983748b14830b09afca0842880bac30e314f103b092b4d250842993d63572b0b3421787614032bce5451389de48e0ce2c5435428c60b
256	1	95	\\x07b3ceff92dcd18dab332bcbbdfa0a0c63877fdce0df68960cdf4ed16919f60e27087e389ffdfaf5d9a8a0a34f2e23e48fba775761ffb9eb625a58b68f1e3601
257	1	158	\\xc58298659bd201702015946b2fc2050ee7c34a42ab0f774c1629c931e12f8274974cac00b801663ef338364d4d8c7e5a5cb565810ebfd67d8cee1e66c8491009
258	1	34	\\x32e8e6c901610b0a9893f65a26c73bd31fe68c87f03c24c602f083f3826237e1a5a455ba88b7c68d05f70bea6a72822aaca269e1832e09381422e43083ef610f
259	1	243	\\xd7674c6f3748346748e883799e0a1e749a401943e4a875826c9c4d6543c5953a6da8c15e80313aa40c8c255b16b224851bca40c110f1479235ae42dc660a3002
260	1	225	\\xe3510883346f7795025d905e64ea156704fa62f26ab33da873d9e88ca3f2a54ea18aa1bfbe43b1336f255451169516ae1b2f5be39a5e7e078216f70c336b8e04
261	1	21	\\xabac99599301d500179ab43870e03391c4cc5bbe8a175f6002dde2374e59ed6c5f87b0f66628512aabebac61c03d14bad98ba16c66f4ac454bda9776b394f403
262	1	145	\\xa1b437faf4513a1b60a27e4df464426525c35c54e5c3c385b9cf177afe05005e17ec50013a9b68df7a64f75b11918d2b13a19ab9749e74f354ffb52fa973e608
263	1	386	\\x7e797718733ae64eb36b754720c7ec0da6aa66555a489e93e218511557586463a18709783dd54b5a506db192ea5c8bbff7926f852f80b65e5b1ca2245891c509
264	1	101	\\xad4493cb8499d558173d375d9109060c5f246e98b5c265051ecb469d7728f0f1fcf334d51525af452eb4292239be99b6950d37621dda26882e14a2d8b89d1d03
265	1	252	\\xaadbd7c43988534c49d2fbb024f73405759b21bc8a6e7c8690ca6591e3180707a9d661d6ae09f98fbf0519aa67dda4f4e03a3c6399e51e3582404c8c03ce0f0e
266	1	325	\\x827309db01785a813ec3a57afb1b539910bdf77f241e0f4ef51ce6d7f2614579d9c16ad5d0992f5ef081afbd73532b6e0be0a5341e3325585684bde30c34db0a
267	1	420	\\xd4b5547530d31373665afebce57f308c65fc7f4256a736ac929082490b18ab924e71c9f45ae993541b3d0c5ede178b56efcdc4b1281556e7652eb46c43f0d207
268	1	36	\\xfe9206918ea0f777b794aceb9479058031ce54ad854a33812567ff189223a98cc63f20a21482b8b11d6130b0fc1fdf822d731e3125692c1a5c57f44d092ad50b
269	1	409	\\x22d069a422bc7ce362c0a238dec37dd658b27972f81d20f961225590ffdfc2dfead413b5b5e0fd3b2a44f64f98dca5f01a911ee4e124b339a69ca35ccd82e807
270	1	296	\\xd52fb4c69599916df092b347bc65e9277b777e5713f41098603c1be9d02c825368e67911337a7d97f315a9d24a6f23c957dec94f096bc7dfd984eb12fc60910c
271	1	150	\\x9e963df27fef9fce85348e5d6cbdf1fe798c478613962ed530357db065fb55c82fcc5b7612bedea6cb46679bad61bd06c8aade613e5da70acb14fb1effb58d03
272	1	265	\\x385f7bc82e5e826b0c4b9419869a4e789913b2f9366a476047816bb43e41b77e1d1f907a0b216682b8d64b907013541ce4f7b5274db528f1037849c3be143a02
273	1	329	\\x66a8fd685a603405e517cf1bf3627ab276d68d314aa3f6e15c459268be5c34b8687c763d021f67b57d851128ae38cd04f458a4f7718ee0ce930163c17e8efd02
274	1	224	\\x9f7f0e9e107109a37652487f75b4f986abe6925d6de5fad694ef67e2ebdf44832b640313b558398981784c104b02379c81b68834b04ff636d389349efcd89207
275	1	151	\\x69fcc45fb915d3cbbf2e167d54cfe895297cf6e8ba12ad3f17f2b76eac070a1c0157d19aa959d449c31bd4a8ed2ae37f7c5958d6d9519c5235b8aeafbc9ca006
276	1	247	\\xd5b0703786e5cba8a85939fd308cb5c396f9a0519c1dcecd19eb75e06fb1bfae892441a6389bfb6dfd41c21ec99150815cb8282489d82be7b064a6750d9f8a04
277	1	87	\\xb1a71f8c3a8bbfd3946df7525096e71338c4766eea0d15ac0d4f900576ca436e868f4de80dcb149856182d5d01dae58559295ea9c191380ce29440c4f276430e
278	1	122	\\x52267bc8477ef0e769c75e0ec7f847383e1d8be6668572e1994eba4275975255406cec1a43169ff0755a82c769b560bc321f9ac12f5abfd29bfc39bbd7a9410a
279	1	157	\\x0bb7467dbf356d8455d770e8d28803e1c290716c6777fef87dbb45e3d06db38aee51e5b4274bbecf370dd84483feee59baa01fb7636a3f292e552a7f79c5a00b
280	1	278	\\x27454cfdacbf3c41d289c465bcfbefb25574ac51db59896b30dad4b09dd3c04cccf665fdcbd062732e79e3250d997cb444b5a5d1d3b5481c6bc4c8a65e02ff0b
281	1	67	\\x62470cd6b3ec717afc4180257dad70ec01dcf682a1b30fe25b92734321d1053e5bd184baf8079b79ec0ee849d3751753324448cee3f19d44743b10bda74dcf06
282	1	166	\\xe5e51f5882d8858ec1018a46d83ef963740cad44c171a85a88e937e500499faa1564af9c20e6dbb9e95b60eef77f240b9c25090139129330bfd2c2df642f1109
283	1	39	\\xd494e57f7ba8349fd467b5f61e486ca14deeb3d32759abbdd514e7960f8947f2efee3912a5f71eb7fd7724c3ef3c2cb938df84bc3ec543498d6050f656cf6902
284	1	58	\\x90a60331e083922892c9e9eadbd93c171ace3487497f6b7eaae4b9eb8c3a19a3b813b109ac0c4aac564dc669641e96b089b90ea971f2850635ec2824f2c66907
285	1	53	\\x3a8d6d6604fadd685f20d5ad6bbd3c5261eabe5568649ebb82535c42e8ab45b06dc1906ab5bfb71cd6fa177c524f8f8a1d2d0563c0846c2d73a900263ea32307
286	1	277	\\xaebd6cd05ab9d12f15b6269fc754683c46290dc35932dcfad17e9158a93be76cd24a57e1d89f9b4ae4ea064deafc7553a9709daf0c419946b952643a8c4ff806
287	1	344	\\x3b663a3412acf3809c1c21f3ca2787da71db328917e7a2264786197e57148f1852d4bbfe8caccc9a10fab578688fb77f15359edfb7e9fe80aca9e1fabdd29b02
288	1	62	\\x13e1b2930ef016fa6d8ed0c342eefed8b1f0e3b22f6a33fc8a9e324732d0c78aefb6a4883a21f3750996bc28895a80e7328121ba452ad521a0383d2afbf37e06
289	1	93	\\xda8c65de839ee590bc515614ca90ce6511ac69691ab7589e18f1d341752f2fdd8f31eb1c98f4026022af3f83abc9b4af8a960c2cddd2afaae206e6c57461fe06
290	1	307	\\x359d1dc39fac2610caba4b255611698d049bdf6970b86152d11b014893175f8394b2b834a6df59351be44946fcbdbbb31ff8cc80a52de7c1e2faa8a315bb3107
291	1	267	\\x92ed950795eefc8ab4fe986997f0627d3896b352b078f60ee5fc1697e1c5ca05f43236b72934e817c3e72a6ee4a9cf2afd45f22c8826f5d08ec79eeb6140ae0b
292	1	199	\\x09ce86f871fbcb2c71d1a4008a0f0498e08fbe4846e2fbbf7500ba5faf54f6c1b6f3f147e84d08667488c2a5e69ee575853ca68142f53b8bd9752274cd004f06
293	1	2	\\x82f475c114aebfea06487fc3b5619b3393e936c93bcc69b6f4cae5cfd50624c3f24abdd66713406bbefcab72835332fef1abda8ac924d44f8a3a3e471f014a01
294	1	5	\\x63580f13a54091a3869af4dd296b2420bbb88a1c73616527014a90668e70fb1791e904d500280951a237099ced038a16c09b740a0d7e9d7348e2d227ddc62109
295	1	116	\\x494a4fdf8086ff23d4eb94e8d2c918c0e9d832dc42fe605b84b051310a45e14674e18b449bc002765aaf6bf069729f7a1cb25b62c0d84232f235c91b1e4bfd0d
296	1	185	\\xcc0e4083ebafdf3e87f919bb8879aacc77739b7bbf995d7c442bb15ccb5de05ec17530487852091b942303bee46c7a6c2c0c833d057096c2b2b37321049e8306
297	1	335	\\xcd31b423584a27d65c427cacbeef4e58604a4c47d2e7318bf7ff76680ca215998c5fa91c238689efbd6931a408dbd9689006d5f5b647e0efe4aebbab7a1c2307
298	1	165	\\x7c4878579f5012ed4e50b8d85c16278668b1b11e5c3cd083f3a586fcf04ce716854215ff464931ef2213952ab35ec0f60b5783a46cec7d91c87aca8c3b3ddd05
299	1	156	\\xa9142cff040d65b786f5158f639085c79053f3df4951edb982111da3961b122c08f31930181d7a4d76bbe198a6709d85a36b5dd22a2677a1d196971ba962b90e
300	1	289	\\x2b2d280c9b79cbe0de2bb23768c397dfa8e9142d10c1324ac30f97f6f51407f93574a3fe43aff2fc48ee8ce1f6ffe461c4f1287ec607391e7b5cb892aee6e80a
301	1	79	\\x423f4b4ba58ab7b60ea1a6df18d89f4b24e249725c48957201a90d62f9d6ec8a77b1761db9d3a7d665b2e582db4439796503ee10593aae310b3b1fab67a72404
302	1	408	\\xb01174997097255e41da9612900497b4978f04791e0cfc3c8c002b9db1cd25cc3c443b82233d0f2e2a83097abb09f0b2daea6036e94506c1d5aad8075d23fb0e
303	1	12	\\x2dda8ac0e0f6653ca06d10d35a11b1f81c78d6251b8fdfc21c63e0eaf425519bd465b37a5c2d713815b36198ca1960406fdb7737fcfab90f63bfb09d6294af07
304	1	345	\\xdd007f279364f1159c856aee90276f27042f60e3cc06ef1126d10bb614f35896f31bd6bca0d8003e1155f54e584cb8a08a9c2a415d1f4d526810cd81d4aecc08
305	1	50	\\x1fe54247421e7a0b528904601432fe6addcc80bfc4077f08cb52af76fe067bbaeaf469e6a455f4be8ef09412cd4ec93fed3f0d827833b405339dda39f195190a
306	1	274	\\xefe3d8a680b9e5506304a550d9f187fcb450774d59d12dfb75ef588fd48d0169e163f2770f68433389b260e142a2a69a352445295e157ab21f6f1fd6c2371c09
307	1	237	\\xcb2386ae3f922c73fca8e3f4402c07c881297e5c49f33079f48ba10f8e8b84262cecbac9a878fde7ad8448193578af2845e78549fa63b7444e7711afc782c506
308	1	127	\\x237b143ec036879487739ac84c19e2dbef14169eca84c465cd4448ea6ec489a1c0464d3e5b25a942514fd474866c7cbafa3e4b6adc501b17851045e49d925401
309	1	200	\\xd0643ce0fd04d518957a34203d40b2151cc034549838a755449dabb5fa6e47526c2213d85e3ecde19caeec4e46451ce20dbe6ca41ace6a34a14619058bf7e20a
310	1	117	\\x4aa08625211810a90be067429447ef2d186a352c22c5bf8b856a0acd88bbcf60b506e94c059c4b7c6ae83774fe7ec2d56b0d06b9caf01fae60277c75abc03b09
311	1	211	\\xa19a3ef8877a9e5b7094e1c73b092fec0ee45886d0771eb5aa0c059d6176c7416d053d026dc700ccd95cbc9ae89dae4675385609ddd6c519977cd192c6a97803
312	1	240	\\xad896dbbc2c9b343d245b0110e111d3f90e2a5589942098574dea5e784b6a228ff071df29c1e4ef042368cb14b0294b56f03193e050b1b59680e0676693c310c
313	1	292	\\xe89adc484c0705657ad694c697c711499a05e02d111051f4fa170dec2d0ec1b3191d9dde61c978ac3dc166dc8f3c94c62286ebcb4e26244f0fee86bebf43750a
314	1	284	\\x17d7751550dd0841065d36d10f1361a743d2ce81cf06dafeeebb4ec2b61670990662f0d019512b633d78a4941467ae519508172454b12fd1c941a503d016e507
315	1	7	\\xfc89b7d8473a138b3fe0807a89ca7c4490c4e822f605d1912f9efe0b82ce530a6c2426fa0899b8de29087459f9107650f2f9ea57d8ee774149cba37f9d04190e
316	1	214	\\x49454c7b2ba8ab9e7e90937307a6e2a51e5a1565952a80db9aea3d5848e9540f6af5c971a7e35ad2457342d516d39986ba03ffc5f1e4306fe568eac3eff62204
317	1	323	\\xcbd800c5d1f7caa6d5c8727989fb04a889782565dae2502a99550be4aefebf5499683a4153976810152b93396dcdd95a630a5ac5adb318cdb363fab143913509
318	1	244	\\xd8460d4e58a9dfa03abd180c2d6c99537731b1b53f19262721cdd93f0eb851a30709494327bf8e800e5d4c6583a59673e1d1fbe9b0abeb7b60f75f926ae9570c
319	1	213	\\x4dc192d6e6746ad1a226902971e192ab9e76fc45e9643db294c5915f2cde991035e3fceb31cc734b1a1b5da91b1ee00493778e44266e3ecfb587391f30c62b0c
320	1	142	\\xe8d4f85b5b8fba893e2fc64042944f72d2f350bd7944d406843268aeb2dbdabf2b063621200d98d0dd00fd41957fa8a4fcb6bab0e78a32ac3162e0eac65c3d05
321	1	301	\\x730a8334fa085807cbbc294926c449ef8b6a5fecea1386fe1dbd00cfce25a4af2f3377cabc0e4834e12e9427e0360b1a6f8d445206affaee3285af13444c0a05
322	1	16	\\xe0763277fd018e2525bdc3489f8b83d7cd104a4649cd2e22f22b4408151f16133deb28d9fd2a2079b81ec4c4ab42a7d172e1ddf2feca0eca21074b7f43ccd404
323	1	403	\\x505382b12a082d61301b16b90950bbd8f99d0a21c858625050f64133544e0f37b5765ac337ffaf17f8287ee3b2d5566f04132e549443d0a4e6c2fdd7166f8f0f
324	1	405	\\xf3a3a9365a04edf01d8452f39ad6b897aa2bdc4b5ef13511a8585f6a940967e2f1eb1e087e00bd586e009eef76f54779a6e88d0d15be4c21b9b95a973704ad0d
325	1	233	\\x31f67a365b3569172dc66eaaccd66f33db2a445fbd33bf7a11d3dde198cc48e2c58428728b9790f5f3a4cab01f6cde2251532d02ecb31eec3d9058bc888ac507
326	1	367	\\x8d392b3562669753a749f8f31534c94da5bedbca8111b3ce104806751e62569d40cd3b01652a0e9c088424b9442d9ee3d9b7581b350a0cd7b8b156a379ceac02
327	1	126	\\x1afbce425937fc5e2033f9c9d39081afb97e19172ebb9ae36cba80e63613d3ed990d20be9827122d76fe1c5a6c52b9ae44081115dcfd2ec9164e7d0a32fa0b09
328	1	300	\\xd4efe5c26a4cccf4c2b9a9516b4e8365d6b2dcc4ddae7c3317511945caad30f9efba38c458e520395cd8b7de7a47a87334533f60d728e7756e21a6586293e10d
329	1	230	\\x1df654590708bbca299339d66e684c2e82d58dcbe5a738ca56c7452c68e559ed2dc7591a41cc83377ebe3a4dde31e14255d9ebff818789ade9b17d916e895703
330	1	202	\\xb835d0b9a887466a5c96dff8d0f2a92618cb5bfdfd8ddaa0e5a9922aa7401955efb00dd208911ff868c64a06f79548573d689e520cd9c33fc4915c80fc9b3a06
331	1	354	\\x14198f9f1888fafed8bbdd0a6777baf6bded4ec2a5b23c38ab5628adc88381b02af4162223d6a430848fbc0290aff7c50b620ff5cab52373edff3f0f05613707
332	1	275	\\xaa2b0ab86a06b96d5313b7e7d470915c2ae4086a6b80fe4004d9c09984fa5bc3071be8c420b995f3ab396574f56924d0c0ca1f5be7aa47094c4d099d2c1ba502
333	1	332	\\x873fe448a9d4759b0c9ebcefe85a4b0d60bf143be72db4bd66e829708f416df27e111d080ddaaa28c0721e09311c36664ef0483a6c9e3e0338df0e74ef4ff60a
334	1	381	\\x73324486120bf370ac412e053234d5d5cc69ae5db7c90bc149e2a96232dad9191c658e32937bfd88e8590447487073766075d9904dc6fef23467edd470d81404
335	1	192	\\xc1120a5cb91ead3e84e5ce7b71f0f6bdb22fc6ce30ce78822ba6f1a215aff736091a4000069a4b06d70d93bb84ca3d244f0df69ad44171a04503e4dfc74bfb07
336	1	77	\\xcb777733978a987efbd01d5573cc975fb37c7dfd4fcde3589022513773523d7ac8470b8ea14585fcab01d13c61974e5854fe025fbbafeee3d007a26baca71d09
337	1	254	\\xd91797889cf8d0b7354a912b22f1776eba2b80c88d70e026547dd72d0c688e6aed6393cf3d1431e9e66d3aeba94b0db7f3381a7105421742a65ef9cb35dc3b03
338	1	203	\\x0df346ca109ef7f51ccf3e5a2eed01e2e9545517bbc3652e049d1aeb8ea876b2244941ceaea9f00f02d3379c54c77475a6956a66cd69977eb61732c2e2d1bc05
339	1	155	\\x16898564dcb1cda3b526a26ef7bfd62987a898d0714c2de548da511173c81944c18f0c66783bcf73967d738dbfb402ede61734d0af202e8a10ff5572f448ea05
340	1	270	\\x15f238939a7bb1c4c9b2d0d887e58785c5611a1034baacb4dbe75dc78c1ba8fac37641a5fe8917b0e994b1ee75c3c2594e840e58fa127e97970277e5930ab80a
341	1	180	\\x4e15537635fc7f13655eb3f5392cc710ea4038760e507874fad776d78a7b5b6bc0d6973e842216d1d1c4566820af640f920292eb23936cc5b91d0c3147cfcc03
342	1	305	\\xd4a3b04158161a723085052155fce9cddaaa8479900599c9fad0688bc2c20d219d42ebcc0ff417694f23e764a0c489541e6754e42fbebdf9a9a77cc330d31606
343	1	86	\\x98b424a9f69c7cfd43ec26007fce2f70461bb2db270eaf6b27a301848abf7f381276d6781d8248fa6341d5c9ed4ed2bc76f5524b4c487fecfd188a691b0a5506
344	1	281	\\xec9f02eabad1147f9033ae2d01d0c5f2af3ddeeb7997763ac2f1d7d2d8ec9fd9006c8865087c96d6f3a297d24d595fa68bfd895dc67205362482f3ea81ea1d09
345	1	91	\\x9c6ce58b6d60af910e074c148278cb35f83377ee25fedd0dce891403a998949ca9568314ceee38123987889caa2f1d8675f58cd13a8e78d408e7d495ea2d280c
346	1	370	\\x7cb03fbb6d8e9e6c2aa121ed82c0427b9ba42ae1adb338bb1d59b85a3a6560ebd58b5437e96859d2b2854fa488a186c92312f95fc81d4039b0aca7568699d904
347	1	273	\\x141ec11d0f025cc1a7191c24448cd5b16f6f8e91ff47e964d09a857ae3a54f453c81ffe048a3d8e12922472e7d662aaba65c091288f527dfb6e72edfa18c5e09
348	1	98	\\x1611e31f9c93d0add17a44cef22f81689b2e251a06a42b9b16d1ed5d5543893e2959cdc858b2026092980d90394236ec07763bf4dc8447e71582578dfd15ba0c
349	1	253	\\xdb03348a15c31eca1bfc912caed01e33893c902ed1fb0dae38a95e6afa60265d3a8a58c7905c37b530590b0c90e1c564e0a17a4cfd98855174ccc5315b4e2f0e
350	1	46	\\x7d41ed97f37db920f59e8c98365d5b860c6df74fc9b4b06525410384f55dc7c6c8754393e21396b8348d63e33b1834bb98699ce18b7e1d8e590e126a2c2ab409
351	1	84	\\x1a86b887e0e65a65ed58c0b66d10f694447911e3988b7899cf03fa18b61a1ad31cbcba4f61099d058b170284c24d3e1edc2f835a35c69e443eb646478eb58a04
352	1	362	\\x0f152a7fde351338231e015845cd39828712f2839b3418b4642de0757e7f359b2ed204a63509467122640344600d89e8f39a8859310ff94489c952ffd85dc201
353	1	347	\\x3e40540a8e08f02b10b7ed934caaa1367a53456e0dc9f1e06bec09c9216755d830812842885573a0a973167a39a5302641707740930bf946dcf96dc86b853606
354	1	147	\\x7c4e0ea2e724dbef67c142423c097a3e4ec62950e2c1517efa1ef69b90eab681adf1e6f68fa1bfe3f2c2120043b2467d72a1eaa5cfa5dc95b824ccbd55c1390b
355	1	162	\\xb5fc8f2df913a77c28cb70df452d69e779d47157ee92c43a42f2e0440aa7df9a9af36763d86045e0ed244541763aa6bce70ee75a0aea1f75aa03e9408a225f09
356	1	392	\\x3cc50a0faf6f83feff745a4cafff43b3a4eb974ad93b0ff804ca313305e6b5e99b7e4561ab2b679ce96cae4919473452b8f6e216e804edc8276740cfd814f605
357	1	216	\\x73bc70002b64bc10d8a2a4fd083c2bb88de4d38c4e150283d41342a79eb0eab8d4d0ca80c3770ae63defe90982677a60700e29ed4a4438cb03c5c256bf3f6e0f
358	1	82	\\xcc42a7efcf6ed2dea299053f9704e2642bf8623408884c97bcd9cbbf7798ba1742e7dc45efa9b456426645187e5ce6a72eb608b302a989852800cdc0458a7a05
359	1	238	\\xd582af6715b5a732fb0bf475b68837c686a79918755500c437b5d40ea2181e17d4a894cd876ed052debc1c14388adb7d83ef2b18fd8457aeee7301d171c94201
360	1	149	\\x54194aa83ab5d1b8a648511f76afbd77ab3c79d3ca8fec8cf180fd7e35a58fa3884f549743f746a08ef658fd0a2f8ec7dd1cb3b66ae4bf25065c44bd11c5be0b
361	1	130	\\x42b5e2e70d1fd6fa34c04fd24d359ccc8c6fb8ccff732e908eb482b9b2259a3788bf3e0e0bac3da44a5d0e59322707abb93170f838ceb7e5a4f5014caf405c05
362	1	164	\\xd9660ab9b0956807e5ca59b4d3cb56ba8e62d7279b8997cee17ded3ff7b68fc363633bbd8bab9b4aba5be7cf356717e45e2b835c69693a30b4827f0ee33ba305
363	1	396	\\x703db48acb8175e18af6e3c60c4592be6e7342a432f805932bfcbddb3b0454544c7e44e86aa022bac31c45d902dc7776278568a42f4d27c0b6b8687671f88d01
364	1	266	\\x597a59e9aab9d37d3db34f447e879a9e65620d514908cb5b8694dc0d4dc8a2408c68af44efbedfdc9030295fb980cc46e46cd09a5ec2b88ecf4dc0eda26c7505
365	1	22	\\x95768db2d612cd5b9cd620ce39c8fe4eca6286784eb34acd57fb9650365b30b3fb9c1393b6578a8d80524b8e00431e4a041bedc3aa6ef542e0ab3c76b1300807
366	1	170	\\xb2f0bb90bdfe778213d3ae6da7b48cc3cac94559624af33095221629b70df8cb1384aa5e9008c52751dba65b0660e39036558626a1ef62bf52cc7ce9dd6a0101
367	1	350	\\x39111831b0a82cde045b9fd78e07d5d77771f8c6beedb3ec5c4cb082c48c06deea424017ab82035ec32da49bf81c60ab1d648cd36f66cf538d12328965505809
368	1	160	\\xced4c9f2f66ae1d5f713b87ce58a4e8d285e5ab7af36adb26ab21fe16e579a1b83cc237c33bb6bb3ab805e5d21e0ffb29b334e12da152c8a13d34ef6ee9ccc0f
369	1	85	\\xf557b7222259144b05dd1f5da18329e791041491a425cb5610debb50893e03a4b5f2211bfe8a433f7460c1fdb65917f5d703970ef5ef2e34359459f861d51b00
370	1	9	\\x15cf02c1a9eaf7f26d72623c026b6364dcefd504a77e4b5d72a0f1143b2d7ca588605428b164f90b27da78c54d321e2b2a51289c504efc2c22cd6fbaf0c9580a
371	1	279	\\x7e3a95783f131d25ed7a81ef8c324d40c813c8f9a53670d94a69a850d1ae57b637f08b60a57f8badc32b768e34facccb41878873d1f377d36d1b2f2984a30402
372	1	25	\\x766491caee7a43720b8d5faa26fea78c46882c374b7ae7a35d60c6cc38cae64b8e9788cc8d9caabac3ed33733858b71d680ecee32c5fceb8806d1751b6b6d205
373	1	377	\\xecc2c317253fb3ef871e65205966e5a83d841a0d12c8fc6d56947f6f05b00b2f5279541eab24befb81713ffdf8b7a83417f0127f1706f1865eacdcf80df5f506
374	1	372	\\x0003939309d4873db33223bc933ba7533e1e2fa936809f09fdc62fb5ff15f376aab9e25460bd5e337ac13ebaabcf5af55e4343ba15e6ef354163c9b84f382305
375	1	336	\\xb83892bb7072653a0fac304f817c26472d8df5726a8c64c965b485876a257fed370370097c8a4a2181c4d4eb17f04b9a82d8c43830134114ea2bec8f6e03b00c
376	1	123	\\xbc96bd5d40c683a82ac53e3f71f91163e667fe3c33ab7a09deb01c4ffdbb17faf057f794c1fb48c17e6e59d893179b95d78b4eddc8e96cf0221bbd3b61191604
377	1	248	\\x1a15621c1eca51052817d9ba9ca6856e4aea4f5b96268750f3447db1468125092a6efa27bd217676984fd4918b56ce325f334f4f12c2b0b279bbe0249c0c2506
378	1	196	\\xf71adf1de02133fe207f409aa70c2f485f292b66089fb83af337175195af2850a87fc6f381052e6c5e10458e50954fcddff68547b1d09f984bab70cc1f3e9a00
379	1	399	\\x074935acf7c26f96dd457e34d0b68c9087b5ca03908bb2b421b94b6340e567d939a55b91e46dffa36f244c8f9c684dc09cf814ab2f5037a49d90c49160101e0f
380	1	60	\\xc25981e11f978e60366e361f3f2df85051d4ec19a9f554043fb802edf2c895ec5b3d1ae03d7e19e70e3d3fb0ce8bc53554405d4fc0338fa93e97bc4e3649db0d
381	1	135	\\x9bc670dc1bf829fe4f55051f928669f2f907182c8c6725c581794cb03f1d8e573be9a7a0840376911ce8a88e829345af49bd80cbd03dda280623e56597c9040d
382	1	181	\\xabd612fc3684700920a5b194a67fdbc5404c9279820c9e3f2d000d5af1be1fdda0aa2537c34f49dc4d874cad73a62a7f51a37bc602cb5a710df1da74ca89a407
383	1	393	\\xfab1fd770ae8ad28b5e620f2b9d00c90ba45c26dee8fa028e6b02f3606da95a8ce532e94b8d42d3a78bdf6feb299dbdc56bbf61555abc51126de36dc7ba6cc0d
384	1	404	\\x2b4ace158cee1306186cd3a094336fdd1478ee3b4f9794310d6aed6d3a3ec78c63e00c8470bbc5ccf565f2944a1096156c1e1f1688220b977ac58bf2f03c2c00
385	1	218	\\xd0a3a33054b8971e30d907cf7d976e88f691a3eff6175c68c3bfc5a96a6dc4d1d8fbde3f96b9aff628fd4755cc4ea3bd87c818be03958acf2a572c0653db9d0b
386	1	249	\\x7e75ff9a1fbfde593a807bdfdb6b80680bdb05d43e26843385e99f911a358addf6c291b0c9babe8a8382719aa52b61d22d5c83e8616edaf4730228c405ed0101
387	1	407	\\x98e1e84a19de9b09029f98c187a787a4cbb00941f3f5c3cbc86fa7e48d6c199777516fcd4cc12deb8002ef8b757b43237b83ce78ebd4ca8198aebe3f52c6150d
388	1	148	\\x7c3688c0f8e93a7604966d3e43435e822bf6646a9b653fa63bf42799722369ecc3df5a8fff7025b100658a3b6c75e35a679b8ee5fafa2004ad4c950071cf9104
389	1	280	\\xa011bf5f5f16584d184cad3882a5d71faff9e7a4f9691fea8551e775506a374dc7519cd1acd1d3349b5c6086e31abd940f699f961cce9fb5feaf448fdcf5ce06
390	1	231	\\x575d3cada24d0750d90d26d12bba07ba0280674b6dbc0ee3581d4ebf089af283e59cb62ef2f95831eab4c6b51b84356a7edc8030cb461dd685337e5078069b08
391	1	45	\\x8e4820b7335b41360a78b9136652d234c1c32c07d7c2752a3832e776f1f8a982e6bc89bc4bdc814522489869f5b0fc38d4c4b2266fedf2497da3cb26f2e7fd05
392	1	412	\\x812e5a41b9dab77c50f19d679462bac45e6f69f57ae20baa091be03b27b58ff64b56880ed7cfcb4862fd13d95e1b70d23625d95564dfc7c3f2fbe2e89e671e01
393	1	66	\\x9be3aec6fb9a21e8b4112211e2b061c96de2427e353ce2ae54b9e846a8b2346447208e9b293f5974316d80d4948a4eaf5c884f522f145ffcf386750933a09305
394	1	4	\\xc5a5510c18a8a42b23ea90b93b1ce81c9d8c6b6a0fc34b0bd270b25dd71b246ba888f761dbebd88b9d7269ab8457efa884e86dbb24d721d6617096fa06dd6607
395	1	121	\\x81162267799b621e091d6c618d0b993a7a88380c908a9a3ca030fcff3adbd432ba8256eb915507805af7267828fa583934222b0bae901a49b0366f4094aa6600
396	1	374	\\x02892d07011fef9f2f51e6a1aba0e7cee1658316a4c853c1918cef0bb8f7e02a77c36deb6a7700980d8301b55db1972c89a9b9300d9159c72fa29d10181cb300
397	1	321	\\xe41f528ec76ac4bdfd539edf86b91bfb7e6a880bbff37bcacffd5f02e13cd7b725e2bd3239df0eba9dba8838e9952611fac46521d4d0c737b71bbb19cd901202
398	1	11	\\xb95fec869fa26404cdb75ebc337cf44c1bc75f732ad76c83cd4efa60f5ccc13aad7e0d916eb0914f581ef6e819b09519372d196243d976ef91dec8c3b192c80b
399	1	272	\\x4f17240f7496984c418468cfc596bf41ba22bcb4e83fbe10860547840394835cd23307faf09427b8085ede0922943a8f5f0543e791d394d91f94a5a869b35d09
400	1	364	\\x91e6306e6d199eb8c7e6339bcefe9b4efb4d02c053d3badc4e6c4b3ece0e6c46654fa5ec197600f0e15254731a92ba5f060e0e52730aac3aa7ea2ad51eac880c
401	1	208	\\xdd43605f5bc31df9ccd2b2bf5e3979ed10b687447d07fe86299c33f352e15c56fb1c2475f1ead8865a225217df90d654e059349e499ba1466c1a2e32685a5e0d
402	1	110	\\x493745ee3c2b11ed9ff00d3d2817ad3c5966502d9aa34db5406653ea001bf12d7a192c3d76f84ddb8c5aeefba530eb1ac4be5e69ea45c6f3dc918f410ae6ee0d
403	1	114	\\x8525f9088f14b7975ec6e3b5cc68590b00a82c77a9ed0a395453c2a3f76b310aac8e9529dd89559847f0fdaab8907058f1c78069b07223b18a5673b4617dc003
404	1	37	\\xef4fa2229f4c809118a196d4a6ee6c2624df075e09d1de860fb02e731f7557d8a277ce15c2ef8dc1d140a18d531703e8704070865ccbf0329e3e70266b8fe400
405	1	215	\\x26c4a940296b89d44f552b36dd869f50891c2a026c23caf01dda91fa02776e6a2e4ccd7e9e50f9a98a837620368e808588a3cade9c68390513ea1e901c9cf30a
406	1	10	\\x48c95ba23610a11f9e0c766539a5c15f8a3e7e5785f727c219d6db049546bcde65798119a53d6e56143bdee509c547f660a3a0b4ba560f94cceb86f051ec6d0a
407	1	401	\\x5de35456df903867b2d6c31649df541ed5715cd1308f12c02dc7a71649b727df0a1438094c1c7b2026c58a3f210c716a86f38b34d1830d35a3fa374358c40101
408	1	260	\\xcb485accc6cc769205e39d2309ac6fc521cebfe10152ab6533135fc78682f8c8f53c41300aa17aeb2e3fb4cb17211c56f50cd8e3313d169c22300d3c596e6101
409	1	353	\\x5cdd888585202e643759e6345a47258ca962584b6b61739e17e96ddeb16c92ec0a842d8af8eba3353a3e80b334235c54ed7aeed419322c338ab7633904045803
410	1	49	\\x46c3e655089e9fd1331221ae61a3d86137a4bbf3c4e6c2b662b37a8214fe660ad8978bbcc2bfee54e66ebc5fb6ff612a5d28e2d7b667f8c5bc5c87a8ac9db30a
411	1	187	\\xa84d3574aed3bcc060483bd3b17ce810ed1028924d0456ab755592e6f3b9c12ab64d476fb633236ffa3e4280978f6e80d0515ce00dfcbdf8b97b9e0a691a990e
412	1	358	\\xe4f41c5bdd232cbb12cb77ffbb5004a5335646e83d8923bbaa29337176056a5766efaba20216cc305ec5525bc36349d5cd3448b0633ed1a45a612db8bc77bb06
413	1	167	\\x157b616fcbf6d850885703ca715478d578e4152fbd709349dcba9e4e0d506d7fc10d24baaa6aa0eea39e4c2219f3787159c29a2f9d8f5fb3f145e457b4e57502
414	1	64	\\x3f437490fed20aa3df69df41664ed7835eded9d538ff3f15137d66083da64e484667b03571fc71c054e290335a73f5434c978513200d44bf76d53f878b75c90d
415	1	132	\\x50b8cf4f7b3886a02bcbe2e7232b37c940eea00a7d112bf1faa1e7e25ee3f84bcdcf838bf8f327e5a7e43a7fd9bbe6b79e20a3c01458f3bc44c577a210441802
416	1	59	\\x1190595914e9b559b8c155696232789fd683c193b77aaa9ec0eef9e81a2163d787cd789e761174a6df66e0e181a8872d0c8d4970d36063d7a1a7408f8bb7a209
417	1	51	\\xa36d46e523a03b52fff885623796589d3f74cd18f04a9a621497d59e59386cccb909be60e039fda2b523e3bd04484622e17aca73bc731202395bbab1caed6103
418	1	163	\\x81646874e4c12f1b8bd3d1bb4fb04e16fa99c7fa551764b84ef2bf5ad2873bcb247743ddf81788c3da5be6200e68490689f3d9165a718321d63fdf65acbfa209
419	1	220	\\xf140369e500e6fef6b12305a411ae0e9e5f6329bccaa4fce86db7b4a52b032a123774c1e8d9bbff35c576d2818933db93fd4584131dcdb1a1fe7414c52d5ec08
420	1	421	\\x08d9fe0d96e9a69c47ae61251620e9ac9d9f155d7988031017d3fbbac0cff3d73d82b047d1838677685fad2a07e045dc151da386376b896c3670979d1f8bda05
421	1	342	\\x300329a62c8b5f019e483b0f433a197fea4ac5a9e7695c766f190341ed8f7baf08057b0ae664c74b57f0d3c08b5eb5c0a1db5a06c54e24c6a83374e7c57db708
422	1	402	\\x159d097d9f3efc341b7952bd5c5217b3d3b4c633efb9117e1c22cab2045c8aba6b396640fdc349fd6014cbebca7432e79bf3b0391afd4e881cb28ebfa2286e03
423	1	201	\\x3b186d85c8ea5035f937aade65304df712d831f0c82bb9f3d334012c10c8db6b09c297d0c2bef0c33ac0baba3ba15bcbebba90c16706c5de2bb37c7123a3890b
424	1	75	\\x24404a35d054b18290e9db5de5d8653fb02703bfb8753299a57f71e2f359434c3ad2c34aa71556f6f5f8b777924e33ef4ff3dc99bcd0cce4f4efaa6ad077ff01
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
\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	1647526091000000	1654783691000000	1657202891000000	\\xe793448592b9c003e981c03d157309f98648b443f3d6e08bb19132f31752fc21	\\x2e6491ec566710165e718d980f07e36c83948353e01ed42db720675e8a201e39d7f912b602fc2688e0c5ad00897267f5a00cb2af06d3193d4821d31fdc63af04
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	http://localhost:8081/
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
1	\\xbbf8b9cdd9b37ad49de3cdc19530cc2ce8a5090f477d9c1f8576c5d21e9a1480	TESTKUDOS Auditor	http://localhost:8083/	t	1647526098000000
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
1	pbkdf2_sha256$260000$x0uaBMuyS08RilfgoTH8oP$lIjOlW5s6loEc2NX9xjea5yHkl5GAnDCOG7e7I94S8U=	\N	f	Bank				f	t	2022-03-17 15:08:11.864545+01
3	pbkdf2_sha256$260000$7Ot4yPXzekmIuavDLgE8cX$CddGOfRbnNhxjZQ5T0xph2WgdZCBwjj0laewpPu8toM=	\N	f	blog				f	t	2022-03-17 15:08:12.14712+01
4	pbkdf2_sha256$260000$oRlajJz5mu75f2N7joL1fa$EfTpXujl81US2t3Yg1rr1dKGhAnwNrBau/TD5Dz59Sk=	\N	f	Tor				f	t	2022-03-17 15:08:12.287399+01
5	pbkdf2_sha256$260000$3qfZRjERgQidiElvEzQARn$k3M4k7gJAQGtarwml51MoMokKner7mdMkEif4QK+2jo=	\N	f	GNUnet				f	t	2022-03-17 15:08:12.426921+01
6	pbkdf2_sha256$260000$GRL8KjoZHXJOyJ7eIeQnhi$E85zxbBZlFkBEUyhObbpYA1iv/BkrAjCtwUZG06hBls=	\N	f	Taler				f	t	2022-03-17 15:08:12.56826+01
7	pbkdf2_sha256$260000$esLkOdjJLa1eJPY8W3MQJ5$fkk0HFdY/apjSk8teeZbTLEKPr+tkL01m50m1hcrkFs=	\N	f	FSF				f	t	2022-03-17 15:08:12.709304+01
8	pbkdf2_sha256$260000$047yXYwsU8AjLUUPNhbI41$7SAiVEW0iW3qGsmjBTFXq6RbXNrS2+ixon/uCNULyI4=	\N	f	Tutorial				f	t	2022-03-17 15:08:12.850732+01
9	pbkdf2_sha256$260000$GMP6lJ0yNGB0ccaczH6WEa$KMqwjhUwcK4KfF9trURYR4IDx7VLrbMXbrZV0QqSVRU=	\N	f	Survey				f	t	2022-03-17 15:08:12.991466+01
10	pbkdf2_sha256$260000$DZLccY18Y3jJKayDsvsNHh$9s6NNcbS+Q/k3NtoD8wqlJc+HZRMVErjscftf3ILbr0=	\N	f	42				f	t	2022-03-17 15:08:13.45147+01
11	pbkdf2_sha256$260000$BgPt87j6A75wIxCp7wpwAo$EaUAK9xi0whmJuidOIHdDAQJM8Di6soiAfQkfSr5ROo=	\N	f	43				f	t	2022-03-17 15:08:13.90882+01
2	pbkdf2_sha256$260000$OLVQmmnfngWY1h65aU3WEJ$IdGiTI1j3xwrPlaaLN2jaQ8+N5LD5cqXS5B1AVdsscM=	\N	f	Exchange				f	t	2022-03-17 15:08:12.006454+01
12	pbkdf2_sha256$260000$YmUmcV9TR4Qz4Oy0Cv9WDk$REQbV5Z+wob/cGBy4as7awGN580zYWlVW6+SkOuGUMA=	\N	f	testuser-azpvauj6				f	t	2022-03-17 15:08:20.657933+01
13	pbkdf2_sha256$260000$J9uonHlrVTI68tSXtwJblE$m++KAxiNSQAeTGyT0Kag1SeB1SJ0TOzf/spxt38wn3w=	\N	f	testuser-mmsicqqf				f	t	2022-03-17 15:08:31.425217+01
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
1	\\x00d4d901f9fbfd143688efb5f63c85334df6770963e7a04ff50eeab6d33fdcc80359a738c1093b84a0e7b3b0a967b518be5ec2e4d375ca683b852e737598d5d8	1	0	\\x000000010000000000800003cda7014e733129c1aa7c92df50a7ea2c6d71986417ccf4021eaf3bc8d0103f7d5a59ce2bae4141ed673e44fa3019727e212ccaec1d320cef0cc112440b10c1781b2a299639adb53625af77d55a17629b42165ba4d6d0824ea713e5784defcb1729c524d8029f425fb48955f2a0bea886f4251566cd08f83f6e0ea784d8cf05ad010001	\\x2003177cdd8883efa64bb920be645acb1dd450384d949afba1f5bca51e6622a17ce10368385d2f53d13bc86c0023f49ab71a3b25d0a524410091893a68bbc804	1668079091000000	1668683891000000	1731755891000000	1826363891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x01e4ac32f0df01703c229b25e52e7bf6bb64a583f680b9392232136c4bfc35705cbf8b526ed2878c1bd69d76cecb53ea17b72411f43b1b1e56b9253dea2be062	1	0	\\x000000010000000000800003d0273a4a728affd4730e92c280612bd3d2a92d0a76027903b5dd10cd708f8e5af878d462ab7f5a1293462976c55fd873973f1f7c4fa9687d120168f3856e5e972b94b71cd6cf4c5d383e10560ba21c9ea36ec2d1aa6b783e77e16cfc12b5482238ad59956270ac0e8513cd6bc2b519f516bc9db2a262417750b307b170672867010001	\\x5749bcba52734237c0583a61e6d9f5d0f99de15954cccd12955c658142b8b202256e421b4dbbaffdabc57a37e8c148f44c39249aa37286d87ae724cbc7738e0d	1657198091000000	1657802891000000	1720874891000000	1815482891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x02809c862d0aaccc87ee4921e4d7a85b7bd8485ed25b3c8f8f26a4fb1cbfb64b257d35c1725b43a378b282c0d22cbaa79d25083c504cb8860a473f30012373d8	1	0	\\x000000010000000000800003b6e6947a32a7bc29426762249f82b92bb1916771d50dd78e2dd57321ffbd64c2a8e471457951b7db5ea65eb135dd8861ea20dbeafbbc2024b2473f6817b8a95a2b07e4333ff02c1e5523bbcfcfe6124920764d76edba47e643a150c8521d73ceed9ec928beaa223b4cf88108a6f2626165bc61467683ded6e86a9f529e349f2b010001	\\x2441f926cb156de7a7261946eba48852b0c9d1a102ef78df5972abcd778c3e980e00ed2983e7706b0d04dacb1778692ef802a36cec64cf573e867893d5df3b0a	1663847591000000	1664452391000000	1727524391000000	1822132391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
4	\\x0270c6ee284f30005f06fdcab6c2eb1ad9b1fa9d3cffea6f5c136c4cea8d9ec2c05013a82099d77f9cf5ce96cd11f7cf5b3aee99d8e5afc9ab4ad8f91a3d2211	1	0	\\x000000010000000000800003c65d1c09383f416549f5b6d33a4e58c08466255ed8bdced637968598d1fa490429de5dc418e45f4aa0e6838c949fc596204dfd9d746c1239b95503338225c7b784d0f620ef4685cbc60516a1903230036e7a690ef9e45c79987415c54c6798b5924d66b75612a198f2ae58bd5346240ec2e889e4f47dbd7995eaf7334940c4eb010001	\\x5bb1d86ede67c9b76172001c47035f73ac257d01b5f008cd55de6a2b9f8dda51863bf360e170cadbc5c4281a8b7f51794b61519a99481dd1f23959b2375fe407	1649339591000000	1649944391000000	1713016391000000	1807624391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
5	\\x0900cbfb1d7e88ea5b654fc53a2eefb86a0f2f6986a6b957c22b027eb0f8eae07ab9d903e78b705cef5f62284bcc8e1a87578561168fd4dcf223d1e2b94dcba9	1	0	\\x000000010000000000800003f730a72c98e488d0c088e5ad741aecac13c21d65fbaf2ce0c4b7a4db52857f094b1a17f5982cdd8e73084b9d90466cf07bf2c968b6aa4566067e5cbd6530c768da240fb418194c685e9df9ddb403e24207169edf0d7215359798fa65fbd1b9b20c399e36a17f06934253205d286c74937ddc606e9a3f8b3d114a021d8c01c2d1010001	\\x978797edb7d8f3da0d19b68cafcbfb3e0adda9e6f156f8b28bbb2ffc71fb33f62a36feee7364fc958db2dc7d60d79427161b763c34d5d32157d180ff87c8cf05	1657198091000000	1657802891000000	1720874891000000	1815482891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
6	\\x0b8cffb253c057447edd1dba9b070578b58e688a0fbd3a12015773a12e242d26808d31cf5e1e0604025c0b0dd9cf1e6d01c5277d9e97def16b94667d65757c05	1	0	\\x000000010000000000800003c741a089890f754892e2624e316f0a517d79e5bb22a65d540cad34aa859ef11dd0de238f563e449affb4e2479076577449805c52d624eb9363f94e812699729beade8ce63cdc560e108185379ceea775368bb9c21201232148112bf7052997ac17f13ac1bd4d902e98a25c53188396bf127ebf75e2829f8278e33940e5324bf5010001	\\xcbecddd67c3268f3b40f201d0aca3a48249e5bea735ff65338e4f03f884f948cc846943cdc629da4ba7b30572aa9a2614d8dd150d7717311bd5859037d4de508	1673519591000000	1674124391000000	1737196391000000	1831804391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
7	\\x0f1422457e7399503b05816116c877c250267bcfd63bbb600cd540a594efe624fd2dfaa0a757685058d5b04fb0cd2d6140884b4354cbe9b07c90e553e9b1548c	1	0	\\x000000010000000000800003e3f76388f6c6a9438efcb3b6d8bb9891d4c4d2fefd694fe4b56290e9d84d8fcdfab5f55a9394ed09ede0f6931449a3318718af0f809d39cf2d9dc17882bc42a5b30d6ddb5c02866f5b1a2fdb803af31d7d28d3bd65d13b48653d3937ae428498e5f5939127e424f6b47bf01dddff69ff509fa1247f83050ddef7823d1c47b201010001	\\x601654a34f937c7962ec7c426f3859811ee540cb954e22a6b954bc31b4e037da4ca82d7a96bca305834d5f28424e7b71e3b3329cf5ee50407d87809f9bc71407	1655384591000000	1655989391000000	1719061391000000	1813669391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
8	\\x0fe8b29a5d0251b341066cb1cf1f161ad4a4fe1cb7a75bc8e5b63254af265482d1af1a6abf67d08e415b05105376765a8a0f3677cf794783708d802f519aff4b	1	0	\\x000000010000000000800003b273b2ad24d51bf0ca9ef1534eab29219791cdcc39229fe0c5b5ecfda89e6bc7505902214a48945839d36afe73be20e15103c6ef48f876e26013904679a20804aa9aa6a3bd3a85bd98f7830d0e20a69594c072900c22e26bf0ba19ee9ca4afa7240bb22aff84dce5419ed11ae529e818b9743f7dc02f9a9af5431698a9a8338f010001	\\xaf769bf0da69d3b8d7f927317aba42d254e3ebe31aa14614c21072c62f3b0b94e1468f8d944bdcc2b35a073fb7276f2f67212f88f4773a1b9a376420a028820a	1672310591000000	1672915391000000	1735987391000000	1830595391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x1090db6986fd34ac3e0122034930c379095564b6a2dc34cd9dfedc7dde56f42012a9e85b3390ddfdf88197f76caf9f0642fa1a84a571e849e98fba63f3595bc1	1	0	\\x000000010000000000800003b0c1cabd369d3ef426112bf5a387201adcc4e8ac0806706f13a98e2964b0db114f03d4b7b65cd8f7faa648ff036ffcf00712c2eecd16dc2592b539553e82d2dca7812838065c5c9a7dd0b18aae263511aa11303037ee9f7296e5a181e10fac6fe1af482a84931c7596a0241f0ead061bc14ed91d3dd206764b408177e546a7ef010001	\\xb485eb4b581635545c27af2d3e130e6337009c7fa3d7ed46d8c785402a54812b8e288c532cec013c88fb9d1a1121be3d95880951087cbccf1651f50c8cdab804	1651153091000000	1651757891000000	1714829891000000	1809437891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
10	\\x14d0f1f9d61fcffc43de2600dc394af9473f80f030e208a26391542d2a769dd58f1c63c404ed2fb26bdccf73c968fbf6b40c665d06c6a4c12a37617df312be1d	1	0	\\x0000000100000000008000039ed3724418bb7def90001d12d4b0130082d1b7f9073fbb9fab2ca18eaf121e1d4eef59de4f59d4edd7e364a1411517bf53399a18038dfc72bf4206714aaee65c7ad2f14e83fd44acd54bc02414599103b276a6d93fd461ed86f2ba64e5fd34e87f86aa5b319eb5e6429c5fafb366e6b6bbafcb7a5b2177840495a1e3a26dd0f9010001	\\x774071773fbb9c62fbc62e5e686806e52606273fee630dbbc87f735cb032cc2eba600871bb72546247d64b3a36f67e82c1e018c0009ee33b76eea829c761cc03	1648735091000000	1649339891000000	1712411891000000	1807019891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x1504c63550a3a006316212fc39036d5f4be43db422e696a155e1ec692c762bf5d03297da0d12ff5ebaf2df0a554a17b4305c6c89d39966b59b51ff578a8eda8a	1	0	\\x000000010000000000800003c9cbf9e375797d94a7f15d72a0b9fd852de8c5e7ec8cb4765eb108fae85e5abb7475b8b0c7dc44dcbf387745bd289c9749bdcd4f45bb046d56e5d68e8e8f61a973587b3ffebc50b9af8d8a8f30e6ef7d9de31dfddeccb4f706ad158673bb9b8623768f3b1e23d59d3b5c2898e7a61531dc663b31fae23d21d5e6b63e1a1889ff010001	\\x4ecc579b7b5bd3e786ac34931eefa24c23b0c9a003db197597f4dd545718ef77feff870953fb20d5644a2b811153505217caeebeb0acd603796cc2ae7dc13f09	1649339591000000	1649944391000000	1713016391000000	1807624391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x19d0cb84a183a3b2220e9047fa97a7e68800ebb771de55d510299699dcad6225cd9633c0ab91bcf31ccc63925f22684a5b81536debc5a92f6ae87d1a1c81334f	1	0	\\x000000010000000000800003a79491bea9b9dfd5bc93cc25672a1506de0c13d1e1e78264333b56c76d184a6724234b8012e287ff25ae328c47cba15907502ec979ab1fc51eb10e4a270e0a146a8f97e48f781ac3693a3a7ba1fb6bcdd8a0017b927de05c721593669c564139378727807402b5b77cfe299ece3e40a307102bcfbc99cf62d476c0a5781872f1010001	\\xd1e654dfaaa52cc80449f193f506c335a7fcf5039c6ba0e2aa63d5757f15ee9c3911741f48a3e6d0dd04483f96c7dc6dbd3bbe1131e0c574f009d630da161907	1656593591000000	1657198391000000	1720270391000000	1814878391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
13	\\x1980fb628220e22a086808d8b2c9d04d3858a4d62c7fd02d0482baff458efb3fc26046921f5f6e767c50d4e2de799f34f9741ebecf80e52347138db6b8df1f9f	1	0	\\x000000010000000000800003c1c40c24959eef1200ab8b241a4a0fb83b73d6520058628663fe6187a2637cba7dec208c0b4c544df5968fd6824b80f0cac4311b4b40caf8b695788595e06bf63d991aade3666c85ab9e95eea3ddb1193c93be03f48453b4e22ae0a393c36616683a4544ff55843dec73c7c240a91127738ac722a627275b868d88305e6d76a5010001	\\xfc913b0beb3b4a82c2b770176b8b4a64a9313dd869c9a365e208080ac6c1b7c131e1e33768665d89d0101175333b06c9319988f1868bdceb1bd26132e83d8402	1675333091000000	1675937891000000	1739009891000000	1833617891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x1a90a3d7e0f168f4c848ddadbd132d7277e9bdc8b8e8ff1ed7002740a0c8d7ba72de8d49bf3701c472aa6435f0fec4b00cc04ad579c937428597467f22a49696	1	0	\\x000000010000000000800003c695273f83021a2153b9fb69662341cd792b25e301a188bf7d0240d21fad67172274f9e250eceefc48c8e42b18ec48763d68bedbe8328c663d32c54bc820f4170f66c263040cdde37cb5bcd8f875cb49efe9797a5496417e471bff60d2edf29ab1cfa79284bab9d3ab2da411f2d38e9acaf65dfca8ad244f63b056d9206bc7bf010001	\\x91a137d6f77172f33fcb0cccbe0013b5a29f97ec58aeb5ed0ef63c56574e1e89e5b71757e496cc614d8cf7723b595efd0c9a38d061bfeeb63ff2401c301fd70d	1678355591000000	1678960391000000	1742032391000000	1836640391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
15	\\x1fdcfe9f2f482641644279b25ccefff392bc68051177ac1d1676bb31a6e04364c3aa736287ba1b2dcae05fa7e14b65f510e234435893acb8e2c5b8497d9cf692	1	0	\\x000000010000000000800003ac6e0253cc1264f935dcf6f8b4e40a5d5016df7b41093cedc0834d792be0fa692c0f293c7bbc030e03906b96a59e04c3291659c9a253e6b48427a3102574d4633e65eec7c90e7bd0f9afb0ef410804d2b254acd9f39d34b4cd8545c5b1cbe6f1774f7f59b6fbe8941e0f2d5e9e248a0c5a3d7bcf8f01945aaabcbe9dcbfeedcf010001	\\xc43281ed95107ebd9075d6da0427d3d08f353be29616434b0112f0501f99dbf4f80e18210d40538fe4b6b2738186b3a66ec7a3f9fb908ea6ec1af771c665770c	1677146591000000	1677751391000000	1740823391000000	1835431391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x250834768ba0e915cf829ecd72976b18903fdf84bec4329318a3c7581734ec8bd2877768751972dd92742815f45beeb9c212f98865e9c21b3d130dcb4d500288	1	0	\\x000000010000000000800003e6e94886baf9d002d49ffd72834d1c7e691e31607472361028e3460dea9aba51ef3af70b98b145becbebfe0166464e333f851f7654f148e96f4b7002ac04b07588bd87551908914da9f033e2bb7802b250a80209cc9aee576c1a5bf858749f207b641e96d1f337680560b51e47585f2889ed46e3588766b6cb47aea42844c5b9010001	\\xb910db45ce7d96832cfc97f260a51f6cbca68de4c6b3dc8d22887a83900f22bae870bb0744dd34c8380d64b7f806e6fe299ee085c142af8342ae302dd637ac0a	1654780091000000	1655384891000000	1718456891000000	1813064891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
17	\\x262067351bce681928780ebdf5a54e9fd88082ad8f246e8a37a35a8c99ca7ea2daeb8629ad99333a5bfdd0409507e57bb8c88142e1fb66b93c7bf1a81304041e	1	0	\\x000000010000000000800003c33ea179c848f8cdc80bf8a680fe6bb48658147888bcc6093a7f9504ded71109f733ead518ee9f8193c8122d762828b1b0a19cf09d391fa9a63ccf7244182620d18684cade599f37880c014ace57713d16c697b38f3bbddedf0f6e20447129d72f115713f4f090fdc595f502644fa8a4008503197ad7703c58355b3bd8fc0617010001	\\x90017be8562f43c5f82f8247da6a5e743780cc575d6b646949fc5338f129b3051381f6fae7396af9b9842e58cea10a65593985492ead0f97325630845bcccf05	1660825091000000	1661429891000000	1724501891000000	1819109891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
18	\\x284c429130fd2b9395d61eeaa31ff9e4e9ed1720e0cfe687eebe7ebe09e8779170ac286fbc7fe166a978df9053c228958652a673af081fc9821bee2eb772b4c9	1	0	\\x000000010000000000800003a3aaa1193c31588f2d230872803299dc3f468ad0f67294b5b10a4908f4bde6952c0864a0cb13e0c47a3a8cb443d08eb838a3799c0ebd864933e070e20bccf853ae81b5ed4550f9604f80bf64358af649c606b34b4afc974eef448ed19b5ff4498d10043135b1d1aeea927125608a9b29a745227d5272444cab8ea144ab0c473f010001	\\x6757df817de1b96681ea691b5b35027f78f26b13494f12d04298012953b43ee7ebeb7cd0b3b2a81523c8436a088b1c4519bd36bf5764bcceb2152423ad74d507	1666265591000000	1666870391000000	1729942391000000	1824550391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
19	\\x28d0094954a07e1a3a518c0511ed8190a14da76813ce61085bf6dcd8b3bfb2ccf62c3da02e8a0bedf8f2d35d5556bc1d29688d607225a2486749d4500d7d3b1c	1	0	\\x000000010000000000800003b574804707a475b8298c517d73e83db80ba1b3712030ac0541777624ddd7c5fccced54528ceb21a164c83f29d48e397759403f8b54098f0a1df280d58483f8f635fee160b64fc93c94ff87fc03f25751c458551add6f258781f61e5a711b9a573f4ab47e6d33f728006341a51ccbacfe87367bc279306cd1edf801c12c343e61010001	\\x8eebf4658d1282ceb73a66c0b5169f34fc2ca6292f4ff6b22a6515b26ed2ff660d7a95a65b8784d0b3ddecfdac6b34b5609fd62b67fd1da595fa3b3f7717ef0a	1663847591000000	1664452391000000	1727524391000000	1822132391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x295863818d3d253cb4322d17890c9f4b0d7e1f857ac2623a7721a2475ca283db9c1c8a0b5620752c63c7882340011e43c0d9a056e55cf27bdc1a53cb12db7950	1	0	\\x000000010000000000800003e7f3db43f4c136cede6f1230b7c7ab69bc55647f5e3a5c7e580a725f6aad7aa3e12ebad1e53583f7321a461c8ca406ad75155c71bc8520e5a2362f41de2708d207b4d176531c0e8bbc599e428f205a2013d38448709557708a1dc21026708c629db297f1631bbb9b102ad40d4e9cc07d03ded8b704b42df6b7825bd0efd60899010001	\\x0930ef54206cbf5e82ff962d08df005d3840e99643722050421258c45a3a292a0032ae19cfd7f15b559a26e63123a386452211650531be27d3f145d0940c7109	1671101591000000	1671706391000000	1734778391000000	1829386391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x2a6881aaebabad36ba7de4d99e43ccb5bfe960cfebf6dffa8c2496a98eeec7c25ce1e9d067ef8b1f65546ce33c75159856919d7b5a226497d3f2471aa0788c05	1	0	\\x000000010000000000800003c9571cbf62c9253f9d67ba7f1f864e086e2568102af2ca0d4d8a796181cae08a10515dda7e4a39078967d5f8ea81ee01d07064a51413e52f2bac7d863db8e325fb6bb28e20a16f128bfabdca22c944b766343328cc44f9e40e603994ea313425ee75bb4ce1fbc9be4bae1f2d4ad52d64fb05fbbd806cff49f5a22ecf68152e8b010001	\\x75871352860c7c49455c5868def01c3dd86b36d5c348fcddbabc92ec2da5ab4f04ee5915e7e071af8504f74f796cf8f438995785c6b839a911b7f3bd7009d10c	1659616091000000	1660220891000000	1723292891000000	1817900891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x2c68e6047fe4f9e88a3d483568a8833a0d00d8f3c416a108389925a925f7c92d8158b59af17eb3d24036391739ddd63ddd95bc529db656901851761e7f78f518	1	0	\\x000000010000000000800003c434a5d086d3b88ee39f763b2f692cdef3b07b8ca9187484aeda056cf48f8c8a86200cdf9212345f54173690de5e110d3919821129b7934e3870d771fa3468c32dd40c413d9f9e791d712c5e1906fcb138afc1d537b33aa0a102745b58db9d945cb475be1b6eb6b19d8096b3319979939e268cb4e556907f98e00a26fee2f7bd010001	\\x24612af40593e221812867c75f06f8cfaac7cbdd8f5859ef6a5e1e48806488019b330b698573825d9ea709289fbea67ccee09c9d059480f468f24e3e35168206	1651757591000000	1652362391000000	1715434391000000	1810042391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
23	\\x2ed83056538dea477da3e4b24c64f6b0aac7465b72b1870fcccd901368f357eb7eeeb1f245a229ff549988bc8bc4d4c364d92f9cb40e3a4e0b3c9772fe4a65f1	1	0	\\x000000010000000000800003e664f720ec2a3d48c47c77c82e38fb91f066782372ec1b5d041b660d55f60c9a99ddedca43efc12916ff61ec41a121f7d708f2cabfe56123c4a2bca425f6e597c661af7d8be8ed2bfb34eb0baf81937b15bd8f5b5c1ec0bed74e1c63b56373f777d3cb02315c9cc1716ddcdbb4751040d4e09fd56c2fccdba21aa17e7aa01b49010001	\\xc2bbe11cc7faaef87ced64f4ae431b228a655a1965b7e6a388905d6711da15071cb1367e2a1af655cca034fc676cbee8598e0c8136b30e88531112cdd69f1202	1672310591000000	1672915391000000	1735987391000000	1830595391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x2e289c42cb03ea81a2747c434195fee02e95adb6125872a1db23f04c5953510b84195f1dcf77d3f59c113561ef97b50fd108c97b99246bbb6c279434e00bb98d	1	0	\\x000000010000000000800003a5b3c49a7e40ab4882a69254bf50357d1ba1038c8a217e74cf4826705951cc727079eefcbadb043b410b9039395891f2e74c97423a5a075f6c58e15b73a61903b664b4beeef0515bce4a6a353870621165b59fb47c35be2c68a6e9c311a5e9c4014a970021a077692d4af05b55d0bfab40891995cda05942a030b2c1bb20b967010001	\\xdeb5ec406479af79b576ec93cfcd1d90ba861552c1d21b620aee1495b5dface1cc5a25f6f093d72b7d87a27fa6522e19a10834365a8b8227b11a315f0891d20b	1665661091000000	1666265891000000	1729337891000000	1823945891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
25	\\x30e88f6dba248cd86c5548d46df593bbc7c44cb9cca5b8bf48edc077c12376aa278185b18ca5ab9f25696f0fcca819e5cca700c1025cfca5c7d14127202a6f45	1	0	\\x000000010000000000800003eaa97309a22a6d28c60f27b27ea0ac2702655b7b29be6661868ede21b1a2d50086603f416e8ed65b7088690a1777fc635d5eb1ffcd12117776ea7dab3aac9dae80ffce4bf30339f75a7a6a2b0612de51853499b1a72b8e920b2337f971949e17991707d8b545fdb87bd2d1e1d12823f6300fa7e184c1e520e3c0b07723ccd4c5010001	\\x3568097ca907bcbcc6336406b7d1218b4a661f4a3643d5a2891290bff68b5f38778fbb9ab5b065461a02abcbba46882733830f4324e3b1fdef4a62560ad4fe0f	1651153091000000	1651757891000000	1714829891000000	1809437891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
26	\\x315c182923c8fea096871009b052ee8653fb9e10364f6dfdefc3fa43632a0a599b7e711b1306223146f69b33fc4b696b33290fb634b59a26d9d25b8383321e53	1	0	\\x000000010000000000800003d48c799b174ef5208f9170f69a2950f23384ccf6ac1033435579b6c33551ebc6f24f4f9c76fa8d49ff5eaff236a9e4b8ad7f1dc720402962b9671c5208d34dcfc2ba939a470985bb8c540ca4f830dfc06c9fe043a6bebd22ea03875703dfc6ef4afaecbde3283892bc193ad75614788a8556b47a92bbc2f98c7b116e2edd945b010001	\\x3e1c863514185328de13dae5698b4204cdeb47e6416db4c4a64671dc8ca086415a9407f9e2ddfc0d93a94b0daf825a630589194b4787d44cde6961c89c5cec07	1669892591000000	1670497391000000	1733569391000000	1828177391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
27	\\x33544689a4d2c9c5e6a86faf82bdb8b9fdc8161c0ecc3eda0875906d78cb2c855297fd721000aea82440a23d3e155d211bc932ceccf9b994881e64a0be26a820	1	0	\\x000000010000000000800003e6d292303b7175da138ea7ed3f410595b8e689eac29ae4ddcd55dcb8a899dc15da4a9d0aca8500566fd803b7b96a6c70fa74c2b0eb6f47cb1cf7a1e18afd44ac3a189a20083b3db08402d4c5d9bf57c9c7f61e2ab0b48bc7e5224208bddfd81556495533323011c08038a1e43efb5423145dc7f1e61857435294ac9288d41863010001	\\x4ee9dd8ae79b158033918276606e449caddec1da9bf688c3266511b316d404f606a98245643f3332c42cb2f7031b01dcea57753461a0311e90f45996f813130a	1671101591000000	1671706391000000	1734778391000000	1829386391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
28	\\x35a8001b8c8d3b690b0b7d71880d47301f65bb937e11728a383dff0b9561cc9da90055a6dd61c7f069ee460df78563b136a7412c5c2f020643b73b5b22819e68	1	0	\\x000000010000000000800003b82dde11f8f5dced452d4efa32597c15f7cb7a64c6d8e7435eab90316f2be948ea222775af25db0c38b8fe3e63c5933a57eeceba4fa7bf42ff50b2788eb08ad93477efcabd7c83fffa0e907e8e6ec72fbc41748eea88504de16e53d515daa39b66fbe42575900a3f576d63ec08ac2dd2c210f7b4286331a22aaa8e9b483702b3010001	\\x0658832607a478143ff8a0ff8d69fb212663fbe63035a3c6676607f1a366fb7a806e166e116cd0a2efccf23d185001cb7b3a7d1ae4d1358e05099e1ad089830b	1667474591000000	1668079391000000	1731151391000000	1825759391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
29	\\x3ed4b3f710c0dec0a85dcfae85bdccc1fa3031bedb0e73ba8b4f1ab8e7ca5fd76d9dc893471ca4eea53dab913eac71278478ba499b833ebe131b5522fe787202	1	0	\\x000000010000000000800003d68f75e2df973c1e39d3675308770a02d51dbe024c75131dbdad7038c4addcd50b0b64d04d490d3a716fbbae19847c1258ab12a65c81ae3cf46840abfd7b82f5c4e3d4b3c42a43a3d7cff3818cf3b780e61c199c5fd9c1d8fa01237b92ea63c783895da2c72537a3a016475f5a63ed362f2ef59145908d8137c0d137b7b4276f010001	\\x182853a777532944591d7bc44e253b1b83d50aa66b7306817073c512d7d9ce4b2639c81d849410ed6aa8ceabe70db1de85919cf68b6e21ba757022ed483ef00a	1669288091000000	1669892891000000	1732964891000000	1827572891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x3fc895c679f8564dc98bec2141ac1988e275ab3d91593767fca2c38f82bfdee562b8e10b5f16dfa799730c254b8c5b34ace15a2f914a1f2c7697c454c2c6a8e8	1	0	\\x000000010000000000800003c9f2c8201ae4fa779fb01c168eb6867891b38681b80655e38a4f756b85d38ffd92505e2ecdc65152f0f66f90fadf6413c8640385dfed213eacca9f7bed38baa3d89eac5fa9126015553e54ca8cb71c0dd0eabf4b8b362efb70c4fae4436165586c4d55b6a55cbd9049dca0dbdd880e26586f5e38693f38d68dda9ff789147555010001	\\x0eff100bdd423516fa3a026c210b180d35b7df7bffeb9416aae39d2909190638ffa09beab362124e31812fabd9765db1a82a37d05bfc59071acc726b2b522d0d	1672310591000000	1672915391000000	1735987391000000	1830595391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
31	\\x3f78293f7ff713b45b5ebaabd9641b524f1de0bab6d96b8f5a1f1249b72269c9015dadbaec7663881f7c19fd4f0ad1cab4b28046c724ea3d076befcc785881a1	1	0	\\x000000010000000000800003d4613f19fe10b0f60a55f8d353958b3fef79fb02880777c5d2eecfe2680e55555c0cf252d2a38876905514943fd5b1189cce983fd2ac15b4efe02456c240c5e675227f0160654165df7a343bc4d158855a22fa20000e2deb86bff2178be9ce0280bb67e486ba3234f07cbbf623cdad2204eec80cc2f879325498880e25de9249010001	\\x64dcfa3e33dd88c518eb63f8474f603a1bf0b9accfa10fc356db832c2e6866da6815504baf62ec81e4a5b7724ccf82a41fb36ad62f391444b90b9d1bde68850c	1660825091000000	1661429891000000	1724501891000000	1819109891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
32	\\x41fc547a4abe87128f2128b9f9b6866a0982317dc740665c73827980065a771f503258f9de1a7cf50fb8b3f11b42316aee5d5a55e75318ed9ff1f7a63f6caf07	1	0	\\x000000010000000000800003c3c69977c3dcf9b990f0ca2e0741503cc3f519cde444eab6511486b07ec69d516acef212a23695a0a3dbfb2520ad8bb7c0e385856b707c3b940302e74d3200535f799ce6957a6e5dc284eec456d270ada17e9a27a55a526917263a4984843589d64fba2098e1e8b71dd29f18fc03ee965f518e77c0b8205b984cca6de1526efd010001	\\xfb5761462c9c578def87e785792203510c4dd9bb8a535d018448cf86933006edb1e058c9b03b9e84e46538c91ce495f9badb9c1b42420bbed51b382380cace04	1673519591000000	1674124391000000	1737196391000000	1831804391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x41805981deadf267ffff7a7ce67f83edec1ac820be38a2bb611ffaf3a2116232c9d74ab97595c6f40919f4c658124e12f6cf38e09dbb4a9822563ab1ca5bf9b2	1	0	\\x000000010000000000800003cb19fd2e2cb3b4cd33327880cd87e2965293ac8e746e770bf2942359747bb96bfeae5f3ee9896e8d219afcf3879a2a930b9ec3e838c7b68ea4e69d41110f7740db6013fabf7c8a966e186d335242dc6151174ed8c392cc736b0826b6713caa06947181f0c498361b71b49af6bd07bd3fc83559270dd8e3e147328f877e5a9bdf010001	\\x33b44e99470916c323795ade73a28294e03912d96a7f3b4f3bae7c56acdfd57a0649e17db760ef36f77fedf96194177687d2aac32aca9f8034bb7ecbdb96a101	1677751091000000	1678355891000000	1741427891000000	1836035891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x4d603a4579dd891e3bce276a05cbfe9be7fe021d60258460e9a30d6c0002d0a2b20572ede06b8dbc25f47994430255a0d191fb2f0b2243c509cd51b72453d77c	1	0	\\x000000010000000000800003bd6da08f0f53136b9fa3a5615e8ff4d8d957628db02e8cf28be7a710364928bafd6606a632dc5fc027f4d0d60e288ffe5ebba96fb01bc54ce2826b3a882d0c2c810277e39fd5f3e534e195ed33e2790f8667e096fc683a2b9bc19eae0403631b95575938b323b81e98ac67034b7ce244767b65abdb8fef82feeb2cec8e37d4f7010001	\\x0dd8fe8477d9f1bcb2e3b7549ce79997fcd1adc2288d2d1fd786ceebe031dc171c3cd2fa95c4abf39adb8fd3211908e681e38966dbd4ff5a95559118a59b5c08	1659616091000000	1660220891000000	1723292891000000	1817900891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x5044bdc397c7cba4383afbd0728b497567f645b7209fc5e62569577d6c75d826f69f447aff5188ee2997ccdc5e9abc3607f4c16475963a77da27a5a04e5274d5	1	0	\\x000000010000000000800003c5a956a6c078849f65332c5dfaaf706eb3a969db5dd1f9f957458e4816eb0e1c650734a798c460ea058e7cf9334ff6a07850743f4a3c6c4be3180e98436965f16310d087948c0552f76a0a83848ee526c72a77cb6b4f3a3654da3d1d1603434f5eed405b8896f039a98d20deb16f2f34b94db443513a55c604950f5bdf901e21010001	\\xf0705defc2e0ab92861c4874186d1536e7f3a6834c874055dcb6ee5fc45664c4ed2bf878e7ac2cdd91f7f61bb1448c59ba41c6f54e212a21c5f787a985a51a0c	1675937591000000	1676542391000000	1739614391000000	1834222391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x520c796add35d80b995079e6c7db3e5b42c98126cc3d572590a92cacdee39aeecbd30686bde8d2bfd3e101e75bf5f3fdd2b102a21f6b4d3155e1b2de8854efbc	1	0	\\x000000010000000000800003af45773b2bed1c26e9e969d304434dc3be8c0b8d4de1fdad8b944407d29a48fafc44acd8f5c6e8c4e7be1c4c1865c237ea5d8c898bbf18dcbdf45990089cac9783db9a6509a6eb32bc0bc91ff8cbff1a75b28ab479d0b5de921869ceeef09c09335d48763176c1cb874f91a788ec9c2373c450e3b59d0a376cdeb565038363bd010001	\\x7b5b6e3b89b8e4c87e177c9f4a8fe992d32efe5e9bd71f9c4dcd3f2184b66972ed32fbdf16561546ca910e8d9d6fe714d1b043f357c7529476c70d460561e80f	1659011591000000	1659616391000000	1722688391000000	1817296391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
37	\\x5818fffbc3a893aa16a3885b38dac20fa3ebc77877e701799c67002a4b285b2927b4bd52afef3454531cc9fe65036567edee4bff395f409543317c3c10c98aa6	1	0	\\x000000010000000000800003cfdf8dc010db754a29566f106c3c1393d55c368de2775a7f2405b2f213b995740559a1f8397398d1c953c6c1b957ec3ead4573e289b7a7042c00eacbc4c3be1a981d685c4fdaa6668cb81a327cc533d3b41556e96b302fdc68f4404ae184e5e2a5b524a310727e0d5655fb290c14c042c510272ffcfca0660bc1a7cf850d8a03010001	\\xf8ab444f1162a0ac3ae431ed9463469b44308e777679af9a7b3487f29fe84349de2ee9256d8a2fb951bc1fb78d830e49bd7a96e6589f74a6d30ce1099c9f370c	1648735091000000	1649339891000000	1712411891000000	1807019891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
38	\\x588c247a7a0c23c11c0f728ad73aabc974da165eeca6fa75f4bdee9db94a2bea9ee33df75bfbf91ef14354dfaafceecb4af683c23a0bc1331d2a7fb9d22c1f57	1	0	\\x000000010000000000800003c99aef78c212f71d162bd4657760ca94ecdfbc661da2c0e004c993acbec55078bb065bc76141ec6e3b14507997a9e696f1a78cc97c3538b3126407fbae5114c6eb2f8415544896aba8d3b1e419b6e48dd5e0d4c19e5f54f1618e6efeaa580e3f0649ad143ce3364642b80283d54bb69b98a89d3837c9f67db1a640d64a77a387010001	\\x369e57eb48d132985f4f1bec531cd8433600f273c12ff8e9cbee27b6058ba0a21d13571562f175087b91c85b325753d39ab5933c643a0682ade792544f2e1f0b	1674124091000000	1674728891000000	1737800891000000	1832408891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x5ab8ad91d7d58103051962f1a4b5935cf53f56085b1136e9aafdbf1efdd46c7d99516835573eac938165c468d14b24b9c9b0941af3e70306e1a6f438d9c0882c	1	0	\\x000000010000000000800003b6c2213bba8bddbc0a93ae4a03710530a11715560e2f18eba076c52d1c04c73d39a9d18057c78c99ce8af1c3c6b4448b75f33442d820e033fbd8e369d84463ca3a354ac189a4555f0b23a254e0c71ef3e7c057370812b082481eda1267acf9884dc32bcc0b6cd66fb01665fa66fc95a1397c8c7a228a11aa13bce41f5484127f010001	\\x761ff70a9a48d7993f8ed170e7d2deccc819adb545cdbb3da1b6f621d66fcbe6749127b32817e2b003a722f68107eef9cab641d706c094e1df7230421ede0d00	1657802591000000	1658407391000000	1721479391000000	1816087391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
40	\\x5a5c6ca9939508ac9cda48e300e2c4873a0a161108625e93ee19abb27a73af287853c388f518c6f909fd64cb1082879446857f77d597d47a8faf04ad3298435f	1	0	\\x000000010000000000800003f202b5cab52132724462e317ae3e35b830c9801f397ccf7e421ce000e31102b7c199e4408505c8226a19e322368d5b0d909c57b91fd9e7762ecbdaf6b2669676a5023365ec819a17c633da508cfef626951395c29309ecdfb36af343cf2bd03708326cb77669ed24f87fb00e52878da6df3114afe8265cb4c95bc63001dc40b5010001	\\xa013bc7b99f24ae24e366b8095cc8af6b1dc19c860b027e3f392cca861339600bf229db7678f3050b000768e256972900723606663739ce0f2dc2c1ab7feaa00	1671706091000000	1672310891000000	1735382891000000	1829990891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
41	\\x5b583a9cb81bd7078c791a6ff0484f48fe8158a0fec9868f544c795c78305b76dc067e05450f1656cd9450478ea5ceb7fc501b9d9534210e244a76469e7fe90f	1	0	\\x000000010000000000800003d256ef6259967902fe7401fceb8109c81ef52e750d2adb223408e8149e8aa157fed08692f75ffff4dd8a4b7d630d729a21c6a67baec8c2f5c9e99d9c9a112a62c40a89a926b1e529cc2051ca08aeae103377534fd478dd4d1f723be36b0386d39ff5d6451ac28522aa539845927d60e643c857906fb14ddb42601bd992b9d923010001	\\xe0e8eaf86f194331c6be3f86e76f6d7b6da8f6abe7ca71d54c8e438518d137f4179d2a735e60d9235f43abbc833122ce1532c8f0a67e0eedba0f80e1e49f2e02	1671706091000000	1672310891000000	1735382891000000	1829990891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x5b34a8fa7cc459e1fe1ed11190db5abd8dd133a8bd7fbcc5bde5b43d5dd71a8f8ed35c92f1f0aa9a3d28ee7abe3c4e6aa4f58446ead3ae31ed46c996082865df	1	0	\\x0000000100000000008000039cb6606f7cab9faaef612197760eea67f3d78da79519bee80ffabb2d472535242b5d284737fa896f4f1cff30dcc883f835ab08cd6cf6c9b23fc3cfad4eae141da89825fd99eb0d489beb1639b940f13688fc05f17d0f104bb49fdf7980c16a7382c9dbabb32454f56d84b64aedd5fcbd5295c16167ed6ee998ed7714d1ec549b010001	\\xb68f2235a44c5ee5d22f2ee86a740f671b11b129692e8c73471d4f399793e47e87cd12bd876b995197cb4b55bc00d25722e769a94683ccf2a3368bc2d5f9a701	1670497091000000	1671101891000000	1734173891000000	1828781891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
43	\\x5cb880d7ac0674a85db512d31879843e21fa3b1312040d3ff657d23952523920157fcb5c8b6f6dde3027ebc34cb1f65c701f2185b890f36737c27cb68c9e7f1c	1	0	\\x000000010000000000800003b9997e829f9d80d20f620f8927b5b6fc987ac0c265a0b6351ec0803b6bb0868e958addd717305e97258e49aa3561863fd4fa91728fb44715ab997edcbb00f2de072fe90a404e6deca8f6193dd3b98cac56171d02e14a8004f269760b36e2284e92f1ba5e4bec1a7fd17a172c007922fa730bddd7938f2a401edcd090ef4f6b59010001	\\x3a613914ced49c38ce68ac076409e6290a6c748137245792fb1e0c5c7d7976be7d98afe99aeb92159b79b9c044629c680c47bc0da2a2ff51452f34fb579a5404	1668683591000000	1669288391000000	1732360391000000	1826968391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
44	\\x5d08a8f987159750af60b263c573e96417b537638e8e5e362c24d4ed16e855fe5572f8e9a4a33c4aa721dee6e6e3a85697ea7b12c67ec2f7708567df8e457b61	1	0	\\x000000010000000000800003c6b463292bde202adeb83291d8277a76ababe12a92f597c50868e8d7d7b06d295f5cbc818907313afbc57826ca681c8f618077088f60f5f0e9354c6e0304208bc9344e4f227957bc64096e327f1be8200b42c85002a8acc26a85dcfaabc97ab43ba7024432555cb3d0101d94958b6de999558e5695e8948b0c87f2ebb6eb54fd010001	\\x6c2ad0bffbb9ef2f23d447b83559aea608c8da0e21cbac1c0116b7daf39c99b4e8d66b79967bb4386bcb3907ba848390832398b3b6d8a92468106b6f0395de0f	1670497091000000	1671101891000000	1734173891000000	1828781891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
45	\\x5dc41800e570a828b90dfb8836b43b6f5d5ed76c6a7a0033ee645e7af9ebd649fcf7010377d9c27befaa5ac1438c98d96ae1415a285705cc36fdfb3296a59494	1	0	\\x000000010000000000800003cc851614537f0cc653e0a3922b3891f24f46ba007313a3dd7da7914d9e919693b7d3eb001f9e7ae3a4e2d0d176cfc262a80153a81d89ca827dc872044b8ec2828398a6e235e18dde0a5121b4377d141e80f445f77b1357ab8dc085489685231e1ab7c28ada05c0e7c684f31b9e60138ae786e82e62bfa6fa87beb8b90f253dff010001	\\x8443713bde98b7f674ed166a6c2fb91823b7336cd5daeaa869fd21a0dd83e7cf8b3b5f02cf0a88429c6c9b109642cdd15378ab751faf232c4d54e374d2f4d703	1649944091000000	1650548891000000	1713620891000000	1808228891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
46	\\x5f48dac87f748e73eea36f864629aa285de51b986b5a4143f962fa676c5be29692e65dff6af52aa799fe678b83358fefe7cce8311308fe44cca28e5d062700d3	1	0	\\x000000010000000000800003d11520359a4e1ea592b4b405723ea41fe945b22479d11a5e6c15a6a90d0e3d1068b13d5dfdf4265466ac23818de05366dcb231cbce901b211c19ffe761004e01ddb344584f6be6c15d178624e36ca363d9b5bb662775fe5f75e28f260b6a2022a2cfadac6bd2292cc3b2bec4b13746dd6fc5d44ff77c4fa9910a8535e7437055010001	\\xc07e5ece41b761efabff9bd67e9b488061ccd1c1e335a710afe57d5151bb62648efeeaabc365b26d1c1b6e58dfe1b7a8b2017b99fe15ce1347d060f8c4e9a30b	1652966591000000	1653571391000000	1716643391000000	1811251391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
47	\\x6218ecd7cf5e5922040e7547ea7314afeb0e7b3e6909838daa198286ba576e4dff1c0329cce27565a283ddbc5c8d2d79e4385c72397124dd2f8b110cc428ba2b	1	0	\\x000000010000000000800003cd6be5b56c480214dc132b6d6acc9960f2b586df680df43f4cc6be2c0bd8bbc6a88f57c72ba8c8361565fbc8bec53f153c0b359d7e940b780342912506924eb36ff2a2e4077010a08a502baa0325b73a1579fef82b2c8b83dc6eccd266a0591415b5896c5421219e0bdbe22ac525a211d8484a039ee7127d1e0fecb9d76ed57d010001	\\x22f60b9f97b427851e109e5581c2508f82d81bdef84b84caac1c6c7323d46aabb43ec27d9d07fdeb1a883d9c57e7978c8daf5e305b097ee4e3e915061dbe8009	1662638591000000	1663243391000000	1726315391000000	1820923391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x6514720816baf26bee86dea40ddaf30d91c79d177582f792ba1bae0ce6bd7aadf5143fba7525f777b670455999e705fa52a773715a7c4d444262aa907faa6c6a	1	0	\\x000000010000000000800003d08d7aaea50d0a78172ba154d634c63b70bf38144a32cff6f59e1332435843688ce716c4dc9ce988e0c588c504b460e94a66bee0bcca1f034561b312408586b8be7af5f7506bfc18c691474011604afa2b82475c57fe33a5900e427c25e4ecbaa5f7915706f6ddb332e5fbf968873ebf94f6885e2445608c2d0e5017d227b277010001	\\x45194b32c9144534d45f3df912ca102c3c0ebce6a2ee464508a9669332e56ef80353289306ebea68f8e816ed831a3978a69be24510b2a1a6cb5e4247b7849b09	1665661091000000	1666265891000000	1729337891000000	1823945891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x6a10fe6fd618615922891776df713979a8c9ee0e95f2fc1bb871e8dbe59ba186c8a9552970d91f070bd1540efd2508127e25691e049a57456ddf4c8a3b169e41	1	0	\\x000000010000000000800003a82dba9eecce12122f0f7cbab5d0f34dd0fbaffcbf7d11148b3a554554b4a63f85674c1d0dbce858869d7cf2604a151e6c684ce10c096193c1c6bc40139fc6efcbdd3946f946573991c997ad8438f2a6b97d21fc680fa179c8ce71f1add9d0b2edd7cea05a80b3ce040a7f1613a7d64cf7a681d7f438a16001f3eff661ff676b010001	\\x20f5ee5310f87fc352240873101cdb5f32646ac663229c5fa64c913cda30ac015e515f8ba376450968b54f0a78afc88ed08f4b38218154e2c223d4d65d745805	1648130591000000	1648735391000000	1711807391000000	1806415391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
50	\\x6e3cd994f08f973622b56abbe3e24a329390d8b7b03db71c7c9619f60c183c16459dc6106688d98fb71eae0827e3e96ef2977d838272272f8a3e954bea3ece5f	1	0	\\x000000010000000000800003e57c068d8d41f7869766f3a544e312931b59fff16448e05fe1dd4c1cc24944c8ead13042439b848629758e9d6468ec7e8a6e48435a0f504252076b0199164434f7284ffdc981fc18ccd1bce9fd8bfd879eaa65f7efa2c965ee03848c6625333cbb3ebdc16ea7e9ededa6ff9f404d42f73281f8c1cdcb0aa9ce6243ee3ed91205010001	\\xb5b5b5dee9be791c778d8cefc89b1af603d10dee62f4be8b4df526fcdd9ec6b013d9780ab592332b68752342d9c5cc34ce8b77d8dc836526bed4e59a61fa6c08	1655989091000000	1656593891000000	1719665891000000	1814273891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
51	\\x73f44060cc9ce3e462f6f5f616220fb03fee42cfd17bcd9efcd1c2263d23b85771c20f449fbbd3907630bae58a1dd8070b984e3883649e9b5051f913512659fd	1	0	\\x000000010000000000800003b5f8f425c3895b310f403ecd54ecd95c2b17a64bec05689a50c06028e9376a2879827d38daa8a2b4f8a93bc9739ad212d54fd125c7be1a81912599bed820c2f37943cd11b7bfc762869dcbeb68ea97d3d875b379e72bdffbf6e089dc5dbe39bfe2b7c58de774db64106de59cc6a4eaaf6be22966ad8840e38e0d9e3446f42197010001	\\x999dbd463c7a5d8deb8f6de74f77a69a8501bdbcacbc2cb5666a0fd72f68e21767613497af295b0196b650df958a0ea40c87348a4b1c2acee6e3b4e860e0dd09	1647526091000000	1648130891000000	1711202891000000	1805810891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
52	\\x751c70450dd7d22bfd5bb84903dd7a11cdca769a0aa7749dc1114ae45eaa0332b088b453cb6b92c0ed85e3fea24e11ab18efeedd8f8738f5dc58bc44d618bc98	1	0	\\x000000010000000000800003a9e68f5f02af970e02e7ef0273591d025ed07b20f18a2b93a79f1d178b0355b98b8e244d4dd707957a6286a55630c0414196b9cbd4db036aa5d65da89c01e0896bbe5c5694bb8f670d87f719b2965dc5458106fa4ff025eb19071ac091263b364dad7ef54daaaa41ae9f23532d89e1d5a7713000f43da5fdc62deba30ede1653010001	\\xc951e77258e93859c2a59c4d21cf08f9aa9323a8fedd755c776a2331081cbb175697d500467c1102ed97494049ad04c5ef65d22016637c071be4000d56809e00	1678960091000000	1679564891000000	1742636891000000	1837244891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x77ac1c8f8b91a30810ad11cdba77d727c161632571b853f8c5a4e157251984b41aa12faf1c0d98d19c66f8c3b710155cfc3fe4a420f08b9025523429f790f7c1	1	0	\\x000000010000000000800003c3281d7674ea10c95203f8c82df792123ba702d6df6938e7cc20a93d5cef80cd678ccbfcaefb49ee6070623afe752cea6793bfa4f096cb2006301712c3fa9283093bc0c2906c8a7837c1822af35faaf1bb3eed9af6e4fe71e8b1d8bf7bfdc1df9f5e132999f49abf586ceddd143b390a4120d3cb9b67e4bc94145e493ca831ef010001	\\x3df6b6ea77331dfef34cadb9488e338382e46809280919203477b052f7329838cecabc9956153b4c1224ed2a63c58d2576c67f2ee4bb7418b4f15860d8d11c00	1657802591000000	1658407391000000	1721479391000000	1816087391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x798c3646e0d794967b9feec81d6d39234e287a534d45dd9fc7e10de3b74c468cd9283d8a7547c36412012132ba5d719da981f5374c92e0e7e4b3901fb6ab9b6a	1	0	\\x000000010000000000800003c690fa85cb24cb37061c19961f2a5e8fc6efd2e2e2c939dae30f5d8ae840ae447ed2a31f45bb7337252742426dc8ff87cb1a5ec1332664f95fc37ecaf88d94e83dc9ff4e9ed0b16ee37654446c0a68daaeb43089cf65d3f75c665eaf2f66e97ea3c96e42a9a97446c0cee1bcb4c90ba2e968f014ac96f4578d6f198e55a7606f010001	\\xb97437841b545735d97cf065a5364e27752f2456dab0a1e44932cfb03071d4f048e7b9ed59221b77d8aa86515beef98c794fdde57781e3e87bcc2d36b41ad308	1662034091000000	1662638891000000	1725710891000000	1820318891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
55	\\x7c501120d82a7a6a19cdf9818d5bd2643c338d2aff08effe814e05976884ecf7ae21cbf4888f19c82fd7bcc8edbabbe7bd42a3e4603c4bf09f39a146ef28c55a	1	0	\\x000000010000000000800003ec1e6a8410e870afe55ec312a1dea27df8d72f881a1bb8daac66d8279cf5da26afbae78d111fcb28fd9e6f530a5783fdd78a888c74bfa0bc36b780b2304b07a704604eba478bc6f81741a270b7afa7dbde46ee59ad66be7c416f48fdc95fae20f03dc434a8cf00801083689fac461e21ccb74cdf212fc96b33c5140dd492ce0d010001	\\x970bd2e711607462b5fdf68f07dcae739098bd582adb897db9b83d0521d4cc2f3327829cf4445997887a3b568ff6e684163db733aee61afdfbfc585856b3a70a	1669288091000000	1669892891000000	1732964891000000	1827572891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x7d28c2c5558823ec0bb861080cc56b023290e3401d666cfa8595e1f3c837212e5bfd6e0864cab230b10fc158c751283073333aa4afc57905d4646b81ceec788a	1	0	\\x000000010000000000800003ca37ffe94e60fb790793bbf6bf2f3822db6a4fd0c0e0639fd27d87a749e9af42454beeefdec633776541ca2c8067ba9e3e8f020ca22fe5407c449fe69d621d81e326d52afc9f0d239efc6a8a0f34f464a1a553f2f8dc36a6f58f6266edc60cd5685908312dd80013c95bc7dc9b13e5133c5f4fb5e3fdd2202ff04f5839b97e3b010001	\\xaa73016186f87543a72329d0552f7b746cb9862f9ee7377836d627c14a52c01fcdba94309893d2e1e8122afc8fb8df78947b81af18ea44847fada5fbab125a02	1666265591000000	1666870391000000	1729942391000000	1824550391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
57	\\x7d00e361a7253a245f4bf0fe24629138155077464012761c83140c42053fecb968eade7c411bf7386b6d092df0583dd65f42e45152c27787b6fb47209b7f628c	1	0	\\x000000010000000000800003bd4bc3f84b3d414d9480772fbed186018f7d9a571268628364eca6d6118d1b7799aaafd0f03dabf2da299924f08f467a65804760fc7a90bbf64b1a17cb1cddfcd7e82846ed43222943ab59c182787db17c6530a234858273ed1986a56e82d0e2241c0b97f6933d513b48b4d80fc1d7ae18d702ca27bccac7baac77eef10b86c7010001	\\x52b4318841bfaba90a5a22051b0ad219ad386f95261a20df443352f148dab4695adf91b038040be7c9fb6a290901886d38a9f2429cacb8dd27ee8653878fe004	1663847591000000	1664452391000000	1727524391000000	1822132391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
58	\\x7f6844e2a76cc22c366202b9cf77fed8b058f5b383b20738ad5c0d2fd5bd74680f64d351b437629eb6fb005d7b45d1d1de78ac62dc7836c83f20fe2399678320	1	0	\\x000000010000000000800003e6b5fa0a3b3b2c5df9f5e53691b42404948dd282d10e9e06edf8979dceffce9e8a37df3427a932c0fb32858119f8fae6e9c698a0d44bcdb4aeaffca856446d1867dc7c73cf254160d9d298e81820e4bfa20a2f97993837bc956b1c5e1b2724a41ae3f5af37d99957d39fbe891f00ff29b84badc1ce329e320d029781e0c30c15010001	\\xefbc833c01efad1cef5512acd7070fa11957cfa579d174834d16603a35b7cdf167e108513360ee61c16f7614fe166a75d11d47cff0321a0e349156f313201006	1657802591000000	1658407391000000	1721479391000000	1816087391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x81e41cca58a00a70678e529a6bae7ea8332aa3c2b096061662e7f604400e83fabcf3c4a3d67290599e14155af0d3a8260b6d95844e44f803b8c960f026e09355	1	0	\\x000000010000000000800003cec9dabdcf403b8e3c4a571dcb3cb17c9a920ddad9f0cd1ee8a638432fbd986816cc8166c13a247dcf7aedcf2e7da145bf9ec1b0e9ae3f84dcdf30ff47cb3e7213da64033b441b26cc50120cf3f19d948150fc34a2c796f509285b9a8afe5ae1913b908b1e24dc5455e46212098ee723db277b5e3b8364544d08b2d715d59de3010001	\\x2a6da946082b5d0cd706891de9241d3ca1088b52cd6b4e9e275021063902775249c718e3a186bf2db72597954993f009671591f5d76649c38b1edee54e236d0c	1648130591000000	1648735391000000	1711807391000000	1806415391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
60	\\x83885a48706e5adfdbb500c9e3b1e85505b08a594138807c5f0b9ae9bbaff94c4fa78a9929981879ee30acbf95e704609133304792afd4dd6a27f8608c384034	1	0	\\x000000010000000000800003bc1f8604d5aa6d42e07e71f060ef37f08a334056f6f38f4b6c981d05678305e327acd5252c9f7a92e4b768fa0376e13fdb569615075f6e3d83f12cf448e55f3d27ccba14e1b5e94bb804248ce960b5807d1d0da2415800f4879383561b82f3a17cb1ef93d7bba43de578dbda36ae31a07b407a073c9c98a391a745db8072dff3010001	\\x33610fca100432507fdaaf7f5a11f86c4a2b645099a677fd35ced2cd6513962927bbcce583154fd4379ca20ea07a52736ae164f94a62d922a13c6e8599ba6107	1650548591000000	1651153391000000	1714225391000000	1808833391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
61	\\x85c83bdee6f14dfbdcfda1659b2b382205e776b89c116dbfead7d231e4fe221b1466a0cc691551a01ca65c06fbc9409cf61e956005bd5f29796ea47767130dad	1	0	\\x000000010000000000800003cb3306bf43c0fb548c2239cc0c3d026adaeeb976793e8bcc5eff79f6f075087b5619fefd029182b69262bb56a7bddf408ce6ab7b3df8498b6402d8cf6efda2879654d06f7023fb2910a51988061b249ef344a715bb457ed89c602cb6a6fc045b48d0d48e6aade0e9f7cb7b8606052a0a4d6960aead49d5da8442eff924addf0f010001	\\x73a29644f8ce2a5dab2615c6c77be1dd2b6431cae0ad405055dd7ede9497c1ebe38f85e24f5f67b45a363fe3058e83696dc144e74f801b60b14a5b67fb08900b	1678960091000000	1679564891000000	1742636891000000	1837244891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x8698e44532f6c6ec58b79975b9f9c5c22a0df44d570c898ea5cb10b2be778559d8e85aaf2a4fe096717acc26cce9cc94731dc5aa2a56c712fe59884d4f598373	1	0	\\x000000010000000000800003e89ca8d1c85f6ed6438cfa24d35e2ef86333e8481e701fc6e4d4d6ab6191531abff66c23052fd3e04e3ce62c6c417836c72c21ed314448c67710a1da52613a82ab0b661257c9ea659360fbcd943f333fc700a445bf4e5d26e24b9846d722a293ef9eb62b2832eff7e2a2ac9d6bece768cc6dc7016de27046fd811c0f97f6c3cf010001	\\x9b49a29a7ec048ea08f30e4ccb26272cc1859e9393c67128ed50b73845ec91c5cac3cccbc1403107aa77454a3a43eea935da0b9455ef910f130e69e228643f06	1657802591000000	1658407391000000	1721479391000000	1816087391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
63	\\x89e87780443c42d595f6a2d10d0e7b4c7ab7705cbb415e1f2423969c8f62b2fbd22eb27e1a6633f39e0d9cfdc8838a2515b928225f678678c6ee9e2ba0e3e9f0	1	0	\\x000000010000000000800003da35b65919a8471fc93414387644568512d79611838e240498cf7e7ba9cbe9031eed8e7fe0074a5679d7613aa1773be63b3dee4c841116c06e47ce1d934f8c9e4a3b6c8428d85a4a3ef843e9dff53eeb39e15e24b5f9fec00457d7d6899e503d92116cfa50b1316ac39df4214a85bdb8b6a110af3b2d56776e2f1a942efcd6b3010001	\\x5c92d3e6784c703eb61915a8cd25d8171d5a78fd7bed575307a1bd99ef12f9733d464756faa5245df42a8cdc01934d0896b7a2a6652cd5221b2658923d699903	1663847591000000	1664452391000000	1727524391000000	1822132391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
64	\\x8fa041122a92362195095b33244a5ac796c73f6e992936664f58f03596efbb523d3f8e35bede3d8fbe3471b83f3759cdb1e6ef1c918636d4b904bfe13ebf719d	1	0	\\x00000001000000000080000399ebe68e875540fec81d648616ddf7493968b0286a26e1221f1895e748cf929e20333b60240318761769f69e07030bc7441d0bd5b41b45a9689eede2e8a87b9ea429535ecefc6746572011f0b08387085e62a76570135f09176854f2c40b5b826dca709cb405b06b7f1e61ab9a74b377680309338f1dde188ff14ee18eb318f5010001	\\x9a642e783f5557369a45fcdc6c80f622f934f61d48e6ce69ae4881002077e70da56d3e832a9d75796178c80207fcceb13ab26a9dac0aa8f416bd18104862de01	1648130591000000	1648735391000000	1711807391000000	1806415391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
65	\\x90c0ae4e468d10875ba5b6d3ce0a47db9753c699b2ed30fa295df82af146cd5dc350cd745bd722f4333f030f2f33f2e94911d092b94fc5e2b40c3ea6d6cdc31d	1	0	\\x000000010000000000800003d636203aa89e3384b1831543518c0160a50aec657ef18a11e8d4a4a02e7595959809d21f24f7c96bb4c1feb2ff87814f2be4b3644de3d8a57005e4ab8a160bb20a7d6da2155f8d33d9868ce99c5a212b12bad1acdace2f19e537b7429c3f1154bf07eab7c3c32ba6d3962169df4aa583e7db3087296b19e0f787c8d065d2344b010001	\\xde54ff2cec9ecfed693b82c17232bdb7282c38a685d20f4e4fd2462536b52d940a6772ddfd0ba12948dedad00389f8bd15aae636e2d17f4033447a6c50bc0204	1671101591000000	1671706391000000	1734778391000000	1829386391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\x90ac0c04aa6ad20e558ba439b892c02285d1b41a1b80bddfed235c7751206ae10a65483c0e9f5ccbaae78415b612afe89ab5182b7eb37981931741ae7410f0d2	1	0	\\x000000010000000000800003cce26ef80bde044cd0cd959d287479171b77709d0fe26e618b677bdeb9c8667331b0008952364c58a7c4aae1d1290758af20f748661741da9002744730912a35fe1973ecb2d69057c86ebffdfbc6a2d11e628fe1fead9296da08ada0ed8614bcfc18db14be6e349d12d9721a6bf3905259a3da8dea6a18e3e4d428a57d3296ab010001	\\x651c5f4b793e2a132b000f4004536ced6895a6459eb2aa1a37755d834349add562975a782ef8eccba4de528afb869341fd1e844fd7513d60bbdbae4c5358cb0d	1649339591000000	1649944391000000	1713016391000000	1807624391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\x90740169919d5f52561e8178bb0a705718ba216bd88e26d736eb53a5da2856a11558379bfc2446801cf0334a7cf00b1e79f96e2b005e9d62071d9c7612fe3f2f	1	0	\\x000000010000000000800003c370591730e48e0ed12d9696a5f8cb138b43d92dca5278551ad0ab95e87da954b70d6f979912fb7a212f14aa9ed3a57d65312bc53208ea088d2a0533ae83d2916ab69c15ee6efa3bdc5dd4ec8422b2b9fc1cb5205004d8f74e7eb657bd7a8756c26911a1dc2809295526fa180f64f1cace6695d0461caf2ebf10bf110c1c36a3010001	\\x5abbabcad527e5f29e47400218a08e44a731413a12f6e7f27c3597fe5d456f406c60d235589598b77f9af9941d9794254e6f02f36cda46acc4dee37be42f4a0e	1657802591000000	1658407391000000	1721479391000000	1816087391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\x919c4dc236b8f300fc478369ff155f88164390f7e7fd34c1aa1f082be5f783c00bd924bfdeb2de5e012bcea61bbc4a1156fef2ff784dd6d9c3f92597e11bbb79	1	0	\\x000000010000000000800003b1d4df7ec4740f95b696bc143a72909a7665d7984960e1ad32ab86fc05193e95b4b37f162421af2bf1e151a2910566779acf81024e9f48ba107c5f75e9f7580284f6d3f7c7e3022e15e5cd099ac0e3ea7dbd97733afe8ba8e9de8417ab516a7046548d09a1e75c849122cdcfc2817731cec30895f1d36ef07ae1f54c56bbe3cf010001	\\x9b685dfb709e7103afa71c516ccdcc834fbb8beda24b21db7954c7ebb4a2b62a183568fce581510a6075bd56a3511c6a1d526780fe4784e00f8b381aefbdf902	1678355591000000	1678960391000000	1742032391000000	1836640391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\x957ce4c6db572ecbd55613b7f52c721aeb820d841c0b53f4a91886be98dc4dac534f08714093e7a46495fda3798887d0a2f73891e3b4c7b7d746723016d54a73	1	0	\\x000000010000000000800003b32034e2818ada227793f16fbe2ed75c2b7e36d8f2b600b8bd8797e83853a25763993eb42cfccd96dfb79427f0770cc6e70b26e49dd6972ca53f7e9b638670f29a1ff3a8c81ee8ce66d9eb62af3b2b07e3195e75b8537d87b6b4af4287532782a9b8b19b895cf7f454e3038f927b4d79a3006ab1f679b6fb5d74d416e73ef069010001	\\x2162f9378e4e33d62c34a990c93ea52ff15eb7c839a8db87cbfedad221ead4f2ba5bb8bc034d55fb0348674ecfc4633a673ee48b95cf041136e15355149dce03	1660825091000000	1661429891000000	1724501891000000	1819109891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
70	\\x97649e95ed0b4dc2e8ba717d9e90d2c2dec258c333b8c4039118731a25663783b2adde36a567a31fe925696d7af2e4e2016ba63bac882ed55688e90310da6f4a	1	0	\\x000000010000000000800003cc16604074a0efb3534d1b648f13499569f8797516adda2c8e390de8733d832c999b2b823aa5c961e619376e42f1e86c2717231a47fabc4fb930a721962916844b63ff2b375a897a360aeb347105ccc4db4b1f17d573b3beb32a4c3d2067d3eb21bb1b39115893dc8429b9cc568d0c7c38472f7a9942ce5b957b751f87780021010001	\\x433b976e214f4421b0db0362290004c54b5201323c56ff4ca6afe98cf898a52e124e4a599d1e3ab5f613a17a9db9057419248a5614bc6c8e7ace5a255a792e09	1677146591000000	1677751391000000	1740823391000000	1835431391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
71	\\x99ecf034a0c62a508c60d66c33ef0f5892e9ad82e43d7556899ce3e7d6ec7c35a0ad6f872e7fc9d3b1eede3d9afa6695a597e09c3e8941544390ab954c0940ea	1	0	\\x000000010000000000800003d7be3caa68206604d7e356c4cbab1eeff9c30da2e2cde44d112229e8b82b65f55b0db67c4bc0cf0f19f6828faf411668553414fbc2fd3c3de172ba5519d38f371cecc033f275d27fc67aa6823ddd8374e5418f055d14acf72adccba3b2c965ffd1c9c9d013e11bb812ad6d06278f11f8b108431f97765d948065b826fc69578f010001	\\x51a82f3d840b122a6563d7a3032af933b2b5e6b66155ff7854da2ea97fc0e56214fd9877732490899de5cf65b4386e7dfdd5c0e15044cd0ae37a3983b3c66901	1662638591000000	1663243391000000	1726315391000000	1820923391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
72	\\x9a1461abdf3477c2b3b309c414f434d9ee34a5482793535e40e442b0f3978eb33629b06bce69ba6c0d38a05b4ca2ccd8c0000b425cabc467626534beefae7d34	1	0	\\x000000010000000000800003b8fa3915f24fba3cd4156781c8f6f9abcf2d0dc9fbe332721d3b61951065c5c9a0f90c9cd2beea272c41f4b94820329eac2883d70ed57d6999ae4bf34c12150d71725a118d0f385d313b7b398a227da7c0a9f4d2ecfe0a5872f0eb4acdcc978462585162d98bc487b76977706650e17936fd61f0b99995d343783e68ad41b83d010001	\\xf4b989d19a21e4157c6ef4f0a4dac5377e1b7dfcd3ec9c30c22b5790deb8fe7e0d7de76f9af4de88630715aff913715b51bf4d48052740a0fb8556f299014c04	1666870091000000	1667474891000000	1730546891000000	1825154891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
73	\\x9e10b3bd99e01aa7441a9b75e944de052f1ea61566993767ea00a9b85bb8efa52bc6ac5e8c11b404ff700a3fd86c668b8c7018bfa64cd7d99bb6eda12e5226af	1	0	\\x000000010000000000800003ba2244d1c51ba8524f80ce4f37b995bfc4150dc46d14a2fbecf43b61be12f0c482374f7301f342f7e78c72f8a36a2162a818cb09cb56b3083eb261f729a64cdc7aeceb6da51e2af1e5ad9a3a4cb81ca0506a0a050cdd89894abf097661ea344942583815916c50fd17fcdd0ef709bc8f5a259aa030a99dfb37b06a9851053ec9010001	\\xbc9e22f59a6a7ddd7c315be554061e6eb8a2294361aa7dd0c88eb09b9769fb65c34fc38773db782882382a09cf0679e9fd64a449f4828ede367befb388295902	1666870091000000	1667474891000000	1730546891000000	1825154891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xa444bc90e9468ea872f4615479871d1d470b4649ee1f5640f1c2f594254ca4583fe2f48214ed4d77989ce9815eb6e0e19b7711674a405b429baaea71323979db	1	0	\\x000000010000000000800003d8d7084554ae6199860e8b29747123758a51c7976708c0ba5b76f8710387045bf6d0392a24b507dde08bd113a8e5ff39c86110130220ee92bc640240b376c8eea49d3cfd0873e8a0a3b5d255a2d2b4846b767f0b22e6a6f6d03a3710b7c4781356d566a1e27508cc0625fabc683b8204a5576b0580ac4e1dfc9b4adcdb305df7010001	\\x6ee824e4bc00fc568a4bcbae711a8a6c358843e5fb0711854ea278bfdd53913362a7ebf776b3107092d8e34530ae12300dc193c1a3447d5d845f7cb709fbaa08	1676542091000000	1677146891000000	1740218891000000	1834826891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xa79c09f091fb7e5e2bcbe3640b056913f9adabc65cad2e13b229df6c8c413f19efbb980cf7e86f0977b9c42ba8158b8f83076f1748a13a95996701381b775b52	1	0	\\x000000010000000000800003aec9b4018a0695c477481d888b5e085e5197360ef10af23d67483bfb9b2f93b975ee6e1e3f781f9c3394a6f07ceff30f3b60882f4dbb67d9aebd7b14c6bcd7d8e1a3e1e442681faa4208208e2aa6bcd6ad7b0f96133972e9a9c957f7f9012f6dac84a0ceef8de93ad6d1dc962673f14b3c6d94fe5d6bfb43bfff87f63557ee49010001	\\x6d8967e9ffa434d67bf8fb090155d858cb8db5e4e83f863b84ae812ced8014709d2d31c09deae6412c60fe5d078b425e222eeb27839d0c4a92f084bb70ed3e09	1647526091000000	1648130891000000	1711202891000000	1805810891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xa994af5a82b8790586b4e7d478ca35b55eae6b64f7d5a5ffb9644b1d68a90812c6bd28ed22537f229f8da2b1e6417b494909e6ff69a96bbbffd91f1f86e1d18d	1	0	\\x000000010000000000800003c422410a6bb4ed71e644b0ae7032296b8087da5e47ab59aae0d60ad8a4449407bbbc7d1dfba4f5f879b34e3cd4e864040e3c318fbc17696c2e97b8c5990d404ebc4636e4b23556d0b93f94b7fefaa93b091ebcee7a26226d8bc5f670f141e683464c5b3b78fab3a9071f007d4a0aa6ef132e2e77d17f536ba55cab07c4a3410b010001	\\x7270b971ba0a0338ef7b3e353e21c5927b1e48d2287cc0e934df46a68320ec61aeffc347b85aa11ac228b030c9d05bf0a850ecabb1b4ba8246e52be10bd1510e	1672915091000000	1673519891000000	1736591891000000	1831199891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xadbcaa96389074b239fe4fed338b720b321b441405c8b14a6ce8caef126b061775576724e614d1701dbba78fe0570a1da14fc9b45617e1a837c0700f69cb1be6	1	0	\\x000000010000000000800003e09fa0489a0649d340d6e665fd73b38054134c776a1b2df551e9e1bd8b9061977b3902e84322ebfd3fa08e0a1e18a8b59d5664ece8eda3cb8af7b36db2153a363667992dd108be049ab7457682883dddaabe247cf6a5af5d306bb2c2af0a2fe1df2af57c1e07c5173e66e8f2e1e5e1d3c4afea93e92a4a32f9d3565ffabe9dbb010001	\\xfcc7f9c8b09ad33afb0d93a92b85a52f96c47c2ea173d914f591a99ffc044a6bacb249b035a1ffbb69af9494c097270fe1923492d422ba26f8d5b4062fc6820e	1654175591000000	1654780391000000	1717852391000000	1812460391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xb5f0ffe784efdc9cbc9a2432e9a48ad5222fdb1fc253efb8b7fbcbcbb850007620e88195bbd6c25c4285a446db52bddd6c287481eddd3148b486c3d5377b81d9	1	0	\\x000000010000000000800003ab438037d263ec8be4432a70e45529168a3d1d11176383ef3f2e0e0f6ff7454fc1c036385bf15f1ebba882da92d5ccff7ae93c0873120e4bddc020e37ddc4b44fc19977b7ffcf1046b9f411af8e138011b64e304eb2b59fadfe1a727902d506856d3f5f255f61adce90e6e44c855a5e3e35423f693176be24ffac6b0b895c33b010001	\\x1107b9e4534900d5bdaace79ceedde9cdd45245548bf57c3accb80237c662665426e85ba0b96eeff232082ab7607d4c39b7326842ee141dc680de18c7156f404	1677751091000000	1678355891000000	1741427891000000	1836035891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
79	\\xba40e401f67f48ff9280749b549af24f64118000008be1d5eb212601bd46f998a3e9124ce4d4a7fefff8b863b2ad29709d950f17eb67a23b0aafe9b5f361c9dc	1	0	\\x000000010000000000800003dc93dc1eb397aa762c7a140869ad6a37bf82a9d16bb41c4e51d69e8f0b3eaab0ccb3590c01800992f6ea885112ea6732985fa3dbf0ab07ceccfd8d5bb601b91d3cb0c6814a67eec9aa3fbbff979116decc2a6899334b9a73e4fbe9188b15ed8b5409af549e7b6c742a406897b785884820482eb8069c21bb5da8750e5700c47d010001	\\x98b54f8ef87b33e1fc85f26a6fff971866cd2012e76c4fbda22b0d2955cefa0a38bc6776c59ff43b68c84d8f9f331533b134a72ba19393422fba1e054129b903	1656593591000000	1657198391000000	1720270391000000	1814878391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xc3f00611df8240d510750aa0d3fe52a2a97137ecb3563893ec99a0954186d85565e9cc5753ceffa8cf54cdd7be3d8015ee271a9bada2a5f06f02dbaa0bf8c150	1	0	\\x00000001000000000080000399ef1abb00c3a64f62bb034a93e99cd6adb02e858f38557e018efeb8e6d382b033030020a53cd04d684644cfc849a3a96de30c71e292dc15f1edb654a600464fa9fcee209d9eab4288ec3a9eb6ba2020dc031e69f471c4efae48a5830563406c49b35963dc5d810f6ac123093e011bced08908b274e2e5eb5b0d1bdcbbcb0fcd010001	\\xa98d6d4202a30a10d9b61b8507cb46a4645a1a2e4cb15d68acfbf280594ae51ff991391f93f15b29cbfe071602dd5b6ee8f26e4c06f7f04eab8283dead6fbf06	1672915091000000	1673519891000000	1736591891000000	1831199891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
81	\\xc6b40ec0d26f96f5549310d71554c5a98f92feb7fe725e2a4d4cb859cba567af0f9a8f5ca452406d484620bf97015cbac5f460d697f4e2dfe9e95eec11b111fe	1	0	\\x000000010000000000800003b972b15a4ee8e3be078f14222e77fdc027447633a6823f341176b5ef239595389b15ba5e5131b2371c4062c4be69d33a2be1852bfc596dc8caa42fd5ac68a375ff8e8c9dbcaa2ae40019d3bb0bd7b348523ed728adb331d7d3abc7969216447ff3b034e3750af179f595814d45b1d13658ccdb4152e1ed68b921529bf7750bfd010001	\\x74c61ccc9edd7da0976dd4c551b4f6e86d5ac49bffc4cb9d43d21618af99f9389506ab3bc1b3817fc2f0cafa0343e445c3e6950f5a5e01dafe55d40eccb34305	1662638591000000	1663243391000000	1726315391000000	1820923391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
82	\\xc678bbee740b07cc6ca35f68c61ec06a8a6fec264c911353d3d5d215363de0515d4d4046b5737128d035192c7464fedd100639698c34770746e65c5c7402187c	1	0	\\x000000010000000000800003df7505d4eb3158620ae3446c7a933295d28f21837288828ba25c3535c42bc9f196cfda7a4caaed37d29484f54e921d5929a97f58aa6829c72dfad4e65b8675bec244f8943c53d77aa9230fa1ecc77ff359eac211bb0d63290ef256ab82c87116229a32cec9ace48a4f34413483e3c198f2eb4367fa2bab9f3b64affa59a935d7010001	\\x7b46183ffd69286873dec938fa7e322b2a0fd6308594d208233a33fbedd0518bde6044fe883a98489d4c35440b5a23428a96fb0befe07e027e5b4eddaf8c4e03	1652362091000000	1652966891000000	1716038891000000	1810646891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xc9f0c03082b304d2564e161b9a875e138e973d87dedfee946ebda34eaf459712faae0cc038cbc14608a922be7e357544a57e70e3999bbd02a1852c432e8e10d0	1	0	\\x000000010000000000800003b7e5ddd05ac3445bbaba8908a06e66df84e25478710d44327a3479eeb14ad72fec3c7c3f02adf2d8b8b116c0320d945eb06079e64bb54c01f79ff431055e28140aa7259ce7843910662e81c1bcc99c997056147add7b941763a89c254eb314a9cab19162ca8a08fefdb168aacb7fc5c6a0233a35777b14faddbe12ec1f9a3149010001	\\xc59a7e1193b41764c9c6de59a07a508e304503c89e70a0c8e28aff5b2b175617cc9603d212d32d58ab311225b03934b5a610ed11a80239442f2d2884ceff8c0e	1674728591000000	1675333391000000	1738405391000000	1833013391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xc9d864d8148d388092ae815e6622a75acaf36dbb2ee421cc524218ec6b82a67c53b26d30e7785f5f090348e5c07f460a5144e4ec6856f78054d8517e40a00094	1	0	\\x000000010000000000800003c501b10439c9c2b32d61c226466ea70cb0207576cd65a9326c1b0343be2c4a44b264f186a6c09be042e8c75ff94dcbf1f0e2a3430d40c79f411e54b64a183fc871180ff11878d53eaded6bad6aaad6ba798ecddc39142c91cfbf5c6f72b08a0fc96e5666eee8fcc8cd715fa14bbba23518ca7ce37e2afa436525356e93b1b26b010001	\\x1ece9e4a732dbc2ebaee4c862cfac6f21b217223c2bd975f3c5fa2e79cb2b6e9f4a376e0a87ebb8862498e0c6ee013366345a3285f4b2ad9b6cdc093ca139f09	1652966591000000	1653571391000000	1716643391000000	1811251391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xcba00dd5967ce40c1e312347d08dc504afa7dc136d644d0be84a15cd53573ee59e78998d809a73b33574ae46b54a3b62a03ea5113002c6910e83f4952d6f4140	1	0	\\x000000010000000000800003d779e140c68e7fc05f530dc3f3ff4c87b7edbbc336b9234914b4f3fd0d4fdc85520b7416d59f07c1d80438ed7dea85c775a02ca46321986420838ca4fd4e63509d92d2af058102079df9ff6520de0dd12de448278840f7bb9ba7140b79673fbbb50bfc8972053e845c37cd1935c417abaa0c617e98e38fd730bb41690dab02e1010001	\\xa1a3fab2f17f2be1ebd3018216388ce12e4c36d68d53f91fc04b17c0173bafa24742ae28ed2f2aa858dba98c2ee9b34cf169ad5c436eecf502ee52cbaaeec202	1651153091000000	1651757891000000	1714829891000000	1809437891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xd42c6ec31444e6a0639c32f7bd3f7f00f6f5386926e1ee97825d3a21dea2ce15cead87376e470cbf0d9545debccd55d665b0cc2fd9d6cd371d87c2f1662e9272	1	0	\\x000000010000000000800003ce1c7c0d1a2a6c83f5b6019df8f88e46030bda2884886e33bc406ed65f6c0fe617ee2fb8815fc8da1b9e5996c6b3ee85989fe19950be66bb4b4dfb9fad4c6416a3ecf353e8639a3678980983e232e75c0d6f8459e8b417ed470b39dbd3bd68dfe2ef61312d2a1e5b434154584253177c8472679b142a08ff2c3f9b9816e7f8af010001	\\x7b730dff328fb4592a6430eea9ae59da3c3247de8760f2d2c229c8730cab4e2dc61accc487794b08cbb2d5f1c1aad68cf8c96d125eb211f892563e8a22875006	1653571091000000	1654175891000000	1717247891000000	1811855891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xd69cc5c1b44c77f0d24ce882ddf048c6603b6809dfc526db8d91292365123c621cf3d85b4dfb9ec4deac1d44b20316aad09c29526fca0525cd68859304599246	1	0	\\x000000010000000000800003b8f6a651101ea5421a9118196c1741f520b8c789d328664733c8540fef07071855bba79578d8568c6dea2e42a33eca9b4c70cb5ffb7eaa928c3bda5235cfe30814f3f53d0c03457fffd9ef66794c9b954442d81b52fc8882c597272da9356eeeeb8db2c540e10a1a82ffa4b2eaba66c1386ec89122a990ec6c727c03089c7ae1010001	\\x55c7125fe2be05138e107a22d72751b0f2acbe5bbdb5ab0515990383a2f5a645afe2c1ecded71adec464156747192ddccacfb45e802abe62644e43fdc6ee310b	1658407091000000	1659011891000000	1722083891000000	1816691891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
88	\\xd684ad88b90b6a34bead9dc53d237da4e1a69ca68731caa6bbd1a00526f264dcf8e4186e0bf30ff92e1331da0d8a6daaa6b90615b4c0eb1979e89e5723f87908	1	0	\\x000000010000000000800003a6d0e7520019c2d5e3a7a625130820e13d21affc2f69d4a644041c710e1cbe1788a48f4f0b0e4818d5ca616ef410eb45ea3042e2e145027f579815187ba338c0ef506d3cc0c6c4ddcf4864418a306bb3d46e095baa54d69aa9c59071ec83fa2c68e60701c99ead1013007ce5279f21221c5bae89728f0abe478491161791dc3b010001	\\x39e536e9d3d2aadd5cc49d788301a4cf02f12cccd9d3fd372be0a1396fb9110165c4c8c58915689ebec782aff647c04bc6a840bf520cc602de32dd482afc120c	1671101591000000	1671706391000000	1734778391000000	1829386391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xd92c2ec5b99369c8aef3362bb07f55d9531b6f2f51e9c86b84903a9accd11c06b423fed5809e8b7d81662573a082e931a3e65aa5aedb3b40910354fb6b5046cc	1	0	\\x000000010000000000800003e3c917398199754284e8a1630db3f9086047f3ef16955faadd2e81eef8ead76912f5391c742b00c8e3ce4ab3598dd9a9cf2d6b2197e28f8c40fc20deb3bce4bf0faf2e56fc827c99dd952d6d144d7b72faeaf7a49201d926c103c5ca0fb2f0950d6d3d0a7cdbcc40713f2b570470b8c2b13e5c0d9eee54f23847f6272deb8c93010001	\\x62496e669f29c6d79ee282e9dd21174c80fb01fe1ad055e0363c9a4abfbc8869eb81e805de3dc95ee320a4c2dfe34d4fca10fa79c26e7badd8b8c309f322f902	1675937591000000	1676542391000000	1739614391000000	1834222391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
90	\\xdbd83a79576feac3b7716d26c5b1d8bce02f11a0acf4e3aaeada0e5e071db322511c20a5588c1b0c76d48756881fd15a5e132902a90d8af999b6ac5038f3d0c2	1	0	\\x000000010000000000800003b2ac2f6fb7d0869df05a26a9253a740204c1ae8d4ffbd5152a8ea3b1dd79785085ca515edb8eca57385f77765be9f53ef6b9b23eb8597962358658a700f4b43fdefebc2533f97b030139b7c34a41b02a3127f71fbd825f3437dfcd2809a3a6f52c19a7064e0418359a5626ded1325adbec31f20ca5b467e63c66b58e00f31a85010001	\\xd825694bdf36987ab6c826c63b6f9b6a8e7658835f43364ad174d00289bf95bd8df71d566fb2083f458344ee02712423555bca58dae0428ee4c82599ba858106	1666870091000000	1667474891000000	1730546891000000	1825154891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xdb18c1e360fe7abc4114cb8ce0f4cca92b47da0f9c2a2577d7b514e8ab8e46f07014b9ef02a09a477a6ec03264b3808c51cfb82a20834943ab9f682d35c0fd72	1	0	\\x000000010000000000800003b1bb18809bd4fca8b64237760a976a2103c98efa0d0c1021242415a4dd762c4288a040d36b4b8a2e7486785ca0346d4cc54da2c2d86cd0df42d5fc0c4aa57ce7fc8bcb6f8545d612c600b34f85b4a3e826a5cc5fefab5bc9bf439d6c25b3fa671b788fb3292825f15d1c6fb398366b5885bed78bc058c7af25944e4930e9b5eb010001	\\x34920e61cfa0f290dc1fc1a623d404f2f43f557546e7a15258c99763590cf4d16d770850fb93a18ca67ecf5a7b0c02ab404c41e969786e5e4de6d607870acf01	1652966591000000	1653571391000000	1716643391000000	1811251391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xe0242070e10deb00ac8851ec3cfb850ef8ef6132a0386a4ce65f7b19b073a472a84a18a668f91051a225fc5d285f87d93a63578506e4eb4b66950ecb098d7b5b	1	0	\\x000000010000000000800003e06560f10af5f82812bf714430627f41f8090354617018c98c0f8a043e6020bbd5ef193f759651485fdb7f6f5d9b86da877df1bbfa2cf5321dd8e56f3befc15c7306ede45624c9062ae37d9ff212bbbab2ed2177339852e54742ab7c87125f8d26ab8116c45f1c55bb244dc37b84619c9ddc81b0e927520dd0461917facd2903010001	\\x7b6093160bb7609b83e3a3c35d99ade3c2cfb7352e47e3ed13b54b61b1fc19b65754a7a41cf5d1b101d7b40a168791d847fe04e516f7f5bb10432428730b6606	1678355591000000	1678960391000000	1742032391000000	1836640391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
93	\\xe13cf7a4df54941845d4ac5c16860dcbf5ae765d736bc51e5b4348983b7de1e6165ebf76bdacb333641ccc9c951b8b7123d55fd7eb720b355ee44a3dce614e82	1	0	\\x000000010000000000800003a6659899b1cc31818cf47dfbac567d6a20d5ea80acb321c6ccaac30421bdeeed9bb19dfe03b979b55403f07ca1202369b5e7a232539b419168ae20c7dc1e19d3802c02596e612aa528ab80910d97e439c01dc0cef51b3c3906d982c09554616653c8f2ad037b7c86e318f43fa66d870aaa61a3d5639f32ade45e4a5fe28b6edf010001	\\xd8f439e58bf8ff8a06b825ecf9a9f08ea3fc9a5911147c6afd054ff78390b54511998beedf27d142274aa783d2e381d11e55f4b18b4ea9ca2f0bb3c986faf106	1657198091000000	1657802891000000	1720874891000000	1815482891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
94	\\xe3948bdaaa2d64d9201619ad53930fe614584eb0a18ffa6d1eb073c6320dfc396ff5832096330843a4e7fef4bb3bbbfbefddd69130af4b6e2bae050768fe4246	1	0	\\x000000010000000000800003a215a9096e577bbbe036bfdd150c3342367b83c655a14edb0fd1278a6b64816781db0dd2a6f7afff3d4acf66554d66d5399e5f6541cd510d5b3d8a30e4a40db15b6cff31437a1cab5a294b6c9fa0f3edc2f2b1819e7a6fa37d1ae5d1bac25667308771f5e243be9bf6f4b690394decf3262a7ef97b1a53a72a3102ce72cb978b010001	\\x24c8bed3e6f050d99110c97ca023e51f49d8130cc3f0f9f6b1fe23977e0a538ed1c50387bcc059ad8a2fde717d94567296e0a95c9ef92f46656966da29a4f10b	1664452091000000	1665056891000000	1728128891000000	1822736891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
95	\\xe44010abd803a74301f0bd73571d0a7ad1df8d195f95913cb2c9f5239d6ae03f3a904b692fbe1534d22742a663b42395da3d7bad40a5913a0107094db6049ff3	1	0	\\x000000010000000000800003c925e6e543e422c074e50159b73101cf1aa60a11c586f7910b47d36a629be70e108610794e4f33a6e0585802ebc4acc53071cd116956997f9acbbf0a6e8c61e2dd99b23ecb0309b3e0b2a5bb7fc0c79a97f09dc956f03aa586b7f25019687c649ed14150ee5ecadb5018a6848b5233e26d2abd6568d61f00bfeef74ba8b42f49010001	\\x427f76ecc85b90c6395bc583c5a5f2e31b9d1b1acc18adcbbd6f61a0e6beac96c560464c2a69baef6bf0ff85010f959a1b80568839ae5b7ab8a5b6dd2ea2da0b	1660220591000000	1660825391000000	1723897391000000	1818505391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
96	\\xe734f3fef570658fed2c3f4e79629737bc085da95586e5d74d50a78631ffca8e44ced5fa5fd1742a2f9feeba5e86578d43f97fe524ce046c997fda5adc19027c	1	0	\\x000000010000000000800003bcdac9399c2520f5fa667488599ce7e948e21a9ee0c4401f3b6c7103c85da55bc0c954a08353ba31b3a6143c0549d8d91998a82cb720ae5888a0155779d523121d47aad99d0d2a152a5430eb3087230b63dd795f5d26cae45c150a03b703c7349b3b7dc5090f2512d5c78e6a5dd7096d698e0bbe393a20f454252aba10ace937010001	\\x461f378f9afb2c1978470f24447ea4be666228301ec0f884d47ebe95856e787ee00a330bd80ea3f8a6833d64df02876ad64219b0e891762d4af6c91a9243810e	1662638591000000	1663243391000000	1726315391000000	1820923391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xe798fc0575ac6e8ac844a7a729c44cd33af82f90c8c3127f4d2cf06515fe4f531d14bd5dff0e6dd73fa2bbdb7d1854e1de6f18b73e7905b185a8efbee49264bc	1	0	\\x000000010000000000800003de0dbf39d7501461212538d5ca1b5c1020e348acc9a53879c255a8ecb75f19cb0cac237f48ab293498d58d04e29de6ceb954e6464e6e886e1f404dbcb22f8b437389115ca2560b31df5e9912ec075a48e0e82fcdf1bd27bfcd625cf96e94f70c8cc08c24ccbfdfdb76acae76405b11bf0ab3d4abdcd4f55a9d1df5c1ce06f385010001	\\xd8dc9d6c1680c9eef0bf334ca9371097fd1d25acb97edd8e607497c66c0f1fd417dce4497fd2669d40c3844bf089b74ebb95f7d9c9c63d2db286daecd162660f	1672915091000000	1673519891000000	1736591891000000	1831199891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xe7b8624b3974337061a4832a78c24cc8b103d84ca452fed15c9994f17277d1855b2235da329cfeb1562e27432b722bb58e64a6a3f6e94f643bda80d0e0679528	1	0	\\x00000001000000000080000399e5171b0a45123d6cd6a348027417eae2786eab532e789b9c9c836fa8336919515e27a57a2e97934c34ebb32942cef6a163f68416a8a94d61f1cbf8e150e10bd89515a38e711da31168033a4f4ae3a4ed314c250ce7057bb46408776c6c9e427577f84012cd9b82560c5882b19bebabf5118b64687c579621fdded0a76c224d010001	\\x54928994257cbf82b527c52bd59841d677c6a6152919d02767422517513d1b52c7bc857231742833eb112de93c25a3bafbbb5dc96b8b4e1fc1681544f46f0107	1652966591000000	1653571391000000	1716643391000000	1811251391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
99	\\xea94a1bebc3c890df3e693f8ce2836f59c6f6ae034e682434f5b712051cb99fb88e05c972d6c0587128798068c3613e1f96341f3ed077ff4703adb1e07852f96	1	0	\\x000000010000000000800003cd7cb86ec8e606bb4137b3dae05ccd891b7b32080b45a6846e01415156aeab19560e4e2ed6efaeb17c4a0f6fa8fd23c88e341b1b64c9f8e6c4e7ee56e8d48aa8b22d9034316333acd5301d1d12d0f44d8884b5eeef68d8938db10291361ab65f2a55773ec47f80d748c478d1ee714596f14abb602e40bfbf9b00eabfaa15e91f010001	\\x904174b2e562a6124e3ce5f5bba5ad2461728cf5f8ec770f6fca7cce7611293e98a1bccc23d5499035fbddea79d2b8bdc340d97263e4f07d72c96fb273208f0b	1669288091000000	1669892891000000	1732964891000000	1827572891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
100	\\xed242a06842a79912267884887a41590765537b5c6ffe7a58a2d7431c97b22bbd1657f717c1ea91664220e249f6d4177a30794cea815e5c89c26077c2dc6fa2c	1	0	\\x000000010000000000800003d1b132620c7d4f053f68e3ad2bde074f413ea8fb154aebb630c6ce381c92ebacda8b1fc2bf83f482ecfa28f36f5f8b7328cd5b18340cc5cda9b97dd241c1ec3122650f22606fa2ec8ea5ca7efe8a0d658a6fcc66bd7661abb2cad04a4939b1d260b06ca46f4496c324a68ee0844aa981a19c87f5e3f4bc955919b297606aac75010001	\\x5d2bc445d70f8bf74bf6ed871e866e82cfa532bcdbf77798198af1b3587bdf3fa71ff693f7a9099602cb61ae9d686e5a3f35799e8e57366d82c5fa1bd0685a09	1675333091000000	1675937891000000	1739009891000000	1833617891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
101	\\xef108abf35e5c486f34d1d8ecd553a6ddd4d708065220d02fc26f9af19ac92897f06d3f18c8aa85251c56838e4a944f4d0e5632028f1bfd712d08717207caee9	1	0	\\x000000010000000000800003c7a8748c0f30c9bb9b9727c6c4524bcb69324eebd757138def9d5166f6eaaf5e26ca1f9c46f65bdcd3f19210c3ae42f7d8557b80dd637c2ecb7072d985fc23128d661a75394092d03c9fb877b203571448de0caf0b8316a838d0bd788ccb187c7fc2189cd7d6f35fbff83cec0a269fce9995fd4d58f1661cbe6746d828273929010001	\\x47e8642d5ee4155cfc6437d754778be37196c1570ca26ea766c5fd437a7179810abac65536068127552a16304cc6252c99f21f99bcd8569a4a4fb9edd97db704	1659616091000000	1660220891000000	1723292891000000	1817900891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
102	\\xf88490899bf5b14639a584736c845da6ba8c1a3469b8b7d736306540bf12f3d54c66f3ea0c5e42a3e5ef44cb9c841d9f9961b12d9dec01c376a28486c5de2f98	1	0	\\x000000010000000000800003c5982a1db72fb4f9f36625206a0febf4cd5e16925836cb19efe4ef6805a68b5272452ba11e317122047e8311727d7a8a71f3f8d636059b3cb9c780f7e53002c36854e43600305e79679ba903f6c5e582bd07ed260bfde97595b20782b30d7f8577dbd646b90c5d9a5a556611e54dc43d963948a1b6d4999ccd0cc88be3b622e9010001	\\x057ecd6dd949998d6a7cd02036586a59e22cbc30488e566a62a040895a619148d1216d34f23a902c2fdbe09c3790322b4078b1c6575c7716315889338e1af006	1677751091000000	1678355891000000	1741427891000000	1836035891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
103	\\xfac05ad3a519ca42d557011fecb806fd0b942237c83d0507279b162e422e61642015879e829c0415944c24784847293f16ebd63a430b1665e4acf5ace2d82abf	1	0	\\x000000010000000000800003bb4f5023180640d4686a13b2ad98d45a1a20d49f5f41b535072953f422ba34b7c49a151dcfa57b48dacc1fa4e2a0ce2d29f72792a9251047868405ae885218702e8ec417099b21f469d2d13268969c353e4aea327163a96ffd2c99872068ec8337cd0ab3a3fe5e4e86150ae6a57fcc009f380687d48cdd46ba481a70d463bba7010001	\\x637c7d7be7a0d2a533f1b9978b54baa64e29d02c9658051bf14b4d70a75d3c7305e3584b44ab95b0bfc1535a2538f15397ea01f7657fd762e06c260176b93c03	1667474591000000	1668079391000000	1731151391000000	1825759391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\x082d6e93ddfbdba5e4e6bb3019febc9a1b54b155cdcedc64fa28c6b70a918aa0dae6810233bf9a1c78c058700eabcbdb82308ca476e8750d91565db14acf3f7c	1	0	\\x000000010000000000800003a8c35951467e109e053c328fc1aa5d609f2342bea70d740639cae6c7521109b10eea80677e0975fe353d9d5591f092d4014ae27238d97fa98a4a6007e29ab2656b7ea260a5a283259d06a97d8d1024040033ac536b3a83eed39531992a19294f3d133381fa070d1f949ba91df9a150b2a1954049a2f4fdb8649738f416cb2951010001	\\xe1095594c6e9f66ab6c9d2e38704678dcbccd5dfc73081982612596a868e0ba5ad85717c27b7379e6de22e1aac189afb0e2df8d20529c13f0e428419e8224105	1675333091000000	1675937891000000	1739009891000000	1833617891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
105	\\x0c59bc4ddcab0cddbe01ffaf3d62dc1c499550be9580439ecc0e81fb6561b316103ab42253809cae68b6209ba4f08c0c895152c61b148b64af3aeab82dbee77d	1	0	\\x000000010000000000800003c23879572cf44eb2f8b3b0df58953fee1b0509e43e0cf25b61b51658cd96e29db5a588852c1c696bdde7e51d3d20565690c80c2ddfdb81a960b1868b67255e93977b79761ce4349c9918e2cf7db596e49ee830db9723199eca030914ab169baac194eeb31c64588dac411f33e1c119f1d2f6a8ef43bb3cd9ddde562d469106b7010001	\\xa7f2a4af89a4ac0ebab5f39502ef631431d46490445289131aa48c3c09850a946466ef55c50ea6ca1e449d07e9caaf687f7a4158d896f9fe9032a691a4b5fe02	1665056591000000	1665661391000000	1728733391000000	1823341391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
106	\\x0dfd54f5705f486c341e603382b2481f7635a6199099bdeaef4cbdb2cb65d55e786a6cba42b042f2f0a4c93bae64cdabf20f2b6a45b7eb6ca73642b2077a8e86	1	0	\\x000000010000000000800003d3ed5db2933897c655d6a1dbda95402db67aa94648c2ea6e824a01f4cec0fa536cf0229557f565a79b05e4a6755b024639b565ef29414abcbf97c06d59b8c2196581b930db75fafe4a9f136502c989aaaa73eb623121344c788b169818b9257d6a09eaa11e90e6af6d5d845b3b452836fd2d64a2bf5429245e53a241fdcb0579010001	\\x4803ecd721704bc9705f2aba44dd2788eda77816ccf5b0ba3e17c8f95f004c18f78e0893407220ba8ca4816d12f45ad7e48fb1eb8dc8f37245b28fe7f8e3c507	1666870091000000	1667474891000000	1730546891000000	1825154891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\x0e49f6d780a4c504c9629dc99356de01e6c67c68b1b2f032d1103623c72123a764d2ac9e53f224c1d527d876162aeb766542669f78d411d45da91a8ea624c043	1	0	\\x000000010000000000800003c225e4c38b62e1e8f86562ff121455e74516f6b1de0890e9e4239518d2c8e1bb3b2f3dd9ada90210d8d6efa1dd665a0eb529da9cec07d05b4afed1f1d2c82dbebf18935e9092abdd4b044d4f4f58ecf7f5bcd1e05132b3dc4f3ec0851e58b429f7174b40dfa916040ceab0cc5ae44e0c3174fdb9277337664bc45a5aa5001537010001	\\x058d1170e5eadd729f6175c4f5b3e9e0aceaa3e17ed3d43e8872f335414d52eacc20da768d9dc8182904c19e9f87a5a7a069e14d0ea29f65244ddc38f1fd5e0e	1669892591000000	1670497391000000	1733569391000000	1828177391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
108	\\x0fe573a7e641af053df1abd2699f7bd7d1f942fac23ce049cc1f627b87a3c650a4974dcbb381ce4ce25ea89bbd648ef3fcefb26b47aa0ffa2c4a526296d34b6e	1	0	\\x000000010000000000800003c2f08e6f9f815bb0025314337eeb42190f007a89932efa38d6c4dd31cc1f830663fd3070dd5d7f685cdb5239754b81b030c205570f727434c374e9fb8ec6e1dc9a79c0c595e515ff7586f87b4a6b677b28a77252e1a18593223715b087bf0959aa3650aeabcaa5c61febaa26f7e0de678067f8a3ee3c02d58181c31bf6595905010001	\\x4a65c1ae0ea10d34bb421d1a50a0e1625305559914634358dcd18a8f99cfd5003b4dd8e025fbd20a823d17b98bc1e87fd629ba0b7c30f5d7b9b3107419b75a0f	1671706091000000	1672310891000000	1735382891000000	1829990891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
109	\\x1395fb64e2194e8ddd226d7a5b79e649a86454c3c7add1c7a0517e9ac8d38614c14efd57db46aa85852cbba3760daf1eca86b3e34db134470262939ecc307d77	1	0	\\x000000010000000000800003c14c6c17c1b129a201cde061af83e80a0c13e14e9455effc0a990a58d7c68460782b8ccdf2421b745897ca74ceff8e3987e8783f9a928f2a2a20b0c2eeb11f4b1f6737811f01c67ad5c5b951f4863c26695f1b773afabc7eec77340fa9605df41735ae4a63619651ef5475eb2c1192e087a442f507d8000c50169be9c89d4dd9010001	\\x7eee1a6aa73daef351ed0548bb81222a7738d06e76108cdb13372201b52a4d8796746f0d869f308ddf04e91fe3e77ec2715004517c138448b4933ef882a95d01	1664452091000000	1665056891000000	1728128891000000	1822736891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x178556c85abe1ab2bb1d398dcc94760009c58e6ea0db1d2281705ef7eb5ac771222681f641f7df49165d06aceed8feb58f2e1f8e0d537f31946652f2abcc94ad	1	0	\\x000000010000000000800003c906d75e89392d101538da02fc32acc831007228db2ceb50f47be0d9dbc5f61cc3b9f0329a2ad2a92c5f5c6aec34145d03d0c586b080414a10d8580635572179a8132b3c9a04834097fb164bb565f6326dbf934fac48dc8aedd5f80e21f7158ccb0370f69e2213042382d82eb240ef0f466001a3db9ac5edd6e675d9959c977d010001	\\xad5afa3baee9387dfced3713521228041045ef702c2741a22647362a6f494777bf43a06e6752bcf25c4aa5dc0dc3fc9c29305b05dbfd352b296cc66d41c5e40a	1648735091000000	1649339891000000	1712411891000000	1807019891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
111	\\x1b65da672e1309f9a9c9a2fa90613cdc5273d7967eb710223db0e900ad2a25a7ddf2e83782db81c4b409da4cfd51a71781b8cd4ddca8e20f40e8c928dd9d072a	1	0	\\x000000010000000000800003fa21c6dc8341baf0e3107496cea84633d053cb89207834a3aa3bfce08ec755a758ab082bfa8d68016bb7a27eaf1b4a5e0a3b74988c5ace4455fca8b7c8f0ecf52ad9bc1fb1ec7e0ca9fc3e4fe9b58643e23428e6a4ea7020c476fc0a4f8373d998c2b340a64d6824b1d62abd742935b7d8857ae0717cc86f79891df09e3afe45010001	\\x27ada49686b09a0b31428a3fa8b2b50545a5624a7fd9293682847d642e484ba34b087b0874bffc062f8de4432faedb3647fe1250023c0a79a4b7eda544f26800	1666870091000000	1667474891000000	1730546891000000	1825154891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
112	\\x21054adc3c511cf31e4e6f303a8fb268fc51692ddafd793a48988335c33581a930aed4f242e3efefebeca0f7ebb812abead309e968e8a0f47014615387a01435	1	0	\\x000000010000000000800003c9338e63a6d19ce61d0467560a670a3d514ba039d7d5d1d6f4ceb0502e0e2a583f7d73656fcadac04e6cbe6c34cc5f46359587f8bf2992375df5db29a8b52700026cdfd0bd3008b0e39317e2ee95e0a430f2ec777b170a819d0fff36e1acde23fda0d25d401954af2fdd4191f0533c6e9a12a0a98905c16bd6372f4febb38b73010001	\\xa63d8a6794e468d179f17acde63a6138e6d78451b845503400e574aade3eee1f80debb57187b7a6d50d4b7fda0a9ceac06ba5d6ed7c209ee54e5a1bc95176b0f	1678355591000000	1678960391000000	1742032391000000	1836640391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
113	\\x24a50ed8fa4377e1c9218c195eafc9f97ae6d0f9b24fa4ca30343c3b7c3c8892e0ca84b58d1ed2f698b0ddaf13b4092f0fe06c997a0389f7c9f31e5d4200edc3	1	0	\\x000000010000000000800003b6d781fa277c67b0c3eb802d2ab3dcb64fb966ef2e9b32e1ddda6387f37ee4b1ad63bee6ce40d0ac796be71ae453c74760160a705415cfc488cd61ec8aaf3f25e79678a4194fca163deb017eb8de320253f4e395947fd8d2da751b7144a97268e82b56e5dbed1ec7bb71facfc88dbbb89e75e11f64fbc6850fe014b38844fc07010001	\\x6489454064bee884d6da22da01c1508a4d4523d407d753f6a9abe2e2f6dfa847604f9287ab08de3c8acdd1c6de3c22b2518a5153d580e39e76b73cbff66c830c	1675333091000000	1675937891000000	1739009891000000	1833617891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
114	\\x2405f31e3a5a0827e9b08e68445175e28ebf2d77b2fd8f6fe2750067978d95e0bf471e60dc17024df3efefefc34ff5a7318806583035f06d994a4f02c360c020	1	0	\\x000000010000000000800003b3a51084086ea8775a43f2bf715a9d17bd2cd27f16705b9fa3e0b1ba1e21c278a1391c4140a16def56d73dfd2585cb8c2f818b11e1622d9c4a1258f64443c45c61ba9e6ec49aba58f480715de7c48e69f34bb44ec37797532089bfdb93695c125884ea53c11b14819c1abd5d02a30cdb0724f98f2f958233785501d5b3b03e49010001	\\xb668f6b0b85cbbf29990d602bb2d046cc8a9294239387902c74ffd7aee273a4e8d4841373e6302cb0f994898858a5ea0cd94722fd6dce22b7e5f9251cfbb7802	1648735091000000	1649339891000000	1712411891000000	1807019891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x258d6c20424fb4876b1dce7bb639edfcbc9d5ff218fcb74f4f21311924050b43c10d1f494d0cf85b79db84b427b544fba2cca48c478b01bccfbf76ad281db0d3	1	0	\\x000000010000000000800003d3c1b54c4f8c316cbab039b5483e72f20ab29278c285955f231b5ca7377a5cc1d21bccd4b936bd974c54e1bd7805e7053b97d144d266b7e1528a151fe98234254379fa21eee8c02c077bea5a8a6305c9d77abaccd96fb567362af921ff4b8de35b4ed4a4c9fd701a1da1bfe6d371f9754c75a5af3d72fde62223c5eb0e866953010001	\\xfedf77d00d9d7ccfc35ba04aced42d1cc9584efb702ccdf891dda0ce32393354e4593d88adf2e18d52fbbaecb31cfd657cb574b3e28b8d90b5f80d29e9e37f06	1671706091000000	1672310891000000	1735382891000000	1829990891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x264130737d1800d61d40ce4d06d88dba9d2d63c3659d6d3167dbf97a63479a228682c0622b6afab78b83355dc7eb313b434cb4ad8cae16796531c09eab219dbc	1	0	\\x0000000100000000008000039cf93c2ac3ec2df9a11f0eb7d582945cbbb9b8ece29bdb8d722ae6147ce66775ce6c61e9cd820633a97ac4d163f385540198ff4e6abc659868b22bc967996a631fa1d1195937adce7c2165ef4a1a3de757328d3b70bf90e00eb41a59de9fc516ebaf3d211266c3228ec41de0484f1608475ae8f1eb770385a807138c365a2c2b010001	\\x849b5ce97ea7a13c4fb347b02fbb60556527c4edb6afea48c8ad857c779bf5eef56964a42bc0eef8feb5579836282ebdcff30c0f5950ee918323478e5d6fbf0a	1657198091000000	1657802891000000	1720874891000000	1815482891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
117	\\x29d1e8777287107b0510a3e3f03b77f8dd395f52bdea0afea3edece46dd777f59a35d230a4d21a1d45bff29df45cd1277a2211d6dfb8e6be11bf9314e8c61139	1	0	\\x000000010000000000800003c118d086a9f99af4e33add8af2d424dafcaf11aa9c0e0e4e54d6d6813d8837957d4b128eb60af4734a11fd36304609bffb2714c5dfc6c344bfc68c7abf8d4965d89f3aba44a10e3b6a5295a29a9c6c47b324b0bf292779186ac97be4b970a5f1799dc5c6afbf634901da68171eef469d5a1544a9676bf118e928bab0d098f02d010001	\\x82b79cfd07d6895170ca4fd15566b6c5278f3adf5cd3450f657f619c8b67cade588424f7ba29d85f67c9511fa1e12ccda778521651cd00744a9b02d088058f07	1655989091000000	1656593891000000	1719665891000000	1814273891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x3379dccde1be4c3a838319d13427f0111695dab536705e063056b1ece196f9304874abd295720c56d758fd7807e9125e9a7ce1e0927adb4be90ac9759becadfd	1	0	\\x000000010000000000800003c9f1d01bd1e1f43d552082fc0f8f6534aa743890c1c9e464471436907fb690eb98597f8c403e765f6df4a48f9d656f10f345288e9f28034ec718f5792c5ead5255226153d895fbad0d60bc42580fce7a3b06193f77286dfb0c540e5a72e13b643ee48c4ef7352b67bbc5d1ef7d27d5f3ea1d58c74abc9764b832c8dc8e10c1b3010001	\\xe66bbdd67c44b476a95b34a816e91e08ccf3cfeeb85537e6e19e0d6a2b307157fcba8158dfd69aac243476ad087569b392bc7a97bd2023441896a97f818cf00d	1674124091000000	1674728891000000	1737800891000000	1832408891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
119	\\x3db152be88b0fc9904cd4eada1a13332df0a09ba81b7181010e4110bcf133b63fadd2c2b025c9eb7389f3a6708ec96c021d89317996411d3db721626a3258958	1	0	\\x000000010000000000800003d2217dc9226d2741c42f610c927c8e0b71cb099ae30b2cc06fa68ea6e2ca86df178a506c6cc2bb2d177303c9a5ee512c062212440b663a82b58c8c6da1e61eac24d93ecc394a29ee1f780bfd268901e0d61383fb8efeb00942d2d44c4b6dfa16a3eed458304c847e51e60d580eb385da0b0c293259cb2ff768f4e9aa47c57163010001	\\xac4246ec40282ccf960ea71c3f8e6cd498e6ce16d53cc12451cbe351d730dedaa084476dba126213ade8508ebc4cc2b88e1bdf088ab2276d779a458b2ae6e100	1668079091000000	1668683891000000	1731755891000000	1826363891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x3d7907d400cf62b78589270614000f9a53be323fc31b14c6cce11883942697f6b9517b3fd1d2300517a9a081705c81db14d067eaceddcde555f588d964c6e541	1	0	\\x000000010000000000800003a654959a82ac968cfab5454f5290d69d0c8721ffa15ec1bdcad32cab26c7ba01eee1f2713ca8edc0e784e8bdcb4430ba9570abdb24aea8b1543a3ad2c2787229d7ddb42bc69faebf22909904b6a68863592a430fef7afbf20970079fd8bfea13ee521ca960ea1bb02cbc5b5017d64599968bb8b41c34cf570c33ddd9dce76a4f010001	\\xdcefffc75b81ec4ad4cc605cde9c5333092f91bf4303a74458fcf92a9abf9608384adf32cce691d7bd7f4b67f9d9f4404d2cfe69fdd6a8d3a6192671f5253008	1665056591000000	1665661391000000	1728733391000000	1823341391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\x3d716e33d0cfd688af6456105a06cbb7e51f17870d91ed5446cff2813624682b240f744cfd1102eda0eb11369a763444d6ecea4e2110e9cf178bcff4f04aebb2	1	0	\\x000000010000000000800003b7e3ace7353a0fd89701dcac897a45c034027a1a74e84f1bd58c2993388c598f2a52d6b7976fa4d50680522970393505e117c09783e153a939093541ddb722037a0a464f721ae9968f186f5287dd2a3fb189befae226a350d440bbe57fbfe948a98ad60840b069b448da256c0d8f126729e2b381dcc9cc6b644848c8fa977323010001	\\x2e1c472679751e19c2f17199db0bb0b400721717e5b60c336b941a1ee2f94d43a2b711b6eab18246de421f0ddeaf97daf4e96977a31da6709441f35848f1a300	1649339591000000	1649944391000000	1713016391000000	1807624391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
122	\\x40b9ca8cd4ef507ba12d0d1687de5d952a72e5c034c741a366c602cdd798ae41e2336eb097d3c3ff4d6dae3c92826a85e315ec6035dca1e34ba69422e8e2d7e9	1	0	\\x000000010000000000800003c52eece6048f1030ec87566d32784f56413bc15ee53a99a9a9a78ccaa6e56da3769580a73bf10e05738532c17c6a0fd10572634ca0165ee9a91a970d15cc0ab80bae0ec68f4363d0b28c3f3761a98ffbe5fa6ae710c7e3227be21fcc8e44ca9de77ed3dc37806930bc58319ad65654da29b589078111b4ddb491730fe1d2b89f010001	\\xf535202dc35b9bb939d7a44a55c0b350c42369ff8131b4c9cd9c1800672e1c56b7f2b0c978e65cdda60624a27bb82a3d5a0b0c57f7fc125f869113fcd62d1903	1658407091000000	1659011891000000	1722083891000000	1816691891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x40b12d0aa3024c551991a24ab1684cf6b9bbc28f27275b198ae054d154fb22ccfb4a1106ae1bbdd63d4493accfb66f762a3e98a638fad5071c83fb50ec20fb0b	1	0	\\x000000010000000000800003f2f7c0ce423106cd733ae937225b65cf568b5c4b180f0a763938a82d3fc037f6fb627bc8b954369baa93fe4107bc64ff7b2556d99ee40df4138a98803e24b98f1db74e6ecb83838dc0b0ea4bd6e05be80bb34f93223cf0bdce3504215562afffadd4764ec94d20f91443b96784a9f37fc1b767e02077be977b5d0fd09de9d2cb010001	\\x338850be26a6e4b9f211a7326b4d40eb96453765e144c7a996138613fc4fe3cbb4ff3f3ca37cb0889c1a2d6d387533073ddb2790a7d23a8d3b67441774b19f0c	1651153091000000	1651757891000000	1714829891000000	1809437891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x40015a3e8aa2058fe5f16c8c982cdaff05a9e017b9f13aa9b6fdc5fe3ded48a1ecd901f24dae60c55d41518185c4d8400e74a889c3b8f54e61d5c84625b17ca3	1	0	\\x000000010000000000800003b8d2360eee4143eca494c65b8aa9792b8d0983e8d8a3f3b9dd2a68facffaa85849ee988ec1d798cd33443abbca9d1f4c678e7e7faca6bc250a4ef87a1787caf878400bb6f4709c3003c73eada8fb1cf8c00c85876e0c3a07488e4ef10b9d709001418ec208c4f4cd58a43bc423d288fd2a60fcd6b20ac04017be689a8da38bfd010001	\\x7f01061e74f60731f2af91dd332b0bdc4d951cf60a950a70ae6def40a52588526dd01315adf4d7d8eaaa01ad21d6e54e10f44e4efffd74ffc66fde51f837240c	1660825091000000	1661429891000000	1724501891000000	1819109891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x4ce9e1baff03173330bd3441f1231a78d4b1363531983b82413b528fce276e607f43b9d72089f7b5d0db38002dae35e47f9b889a744aced982cbfec4010008fa	1	0	\\x000000010000000000800003a5b684495076ff054b7c7f521047ea8acd7c04c1fe5c43ad9ef42da0f37a7ee68d15dc3c651d5323347838dfa142092cf3b0f778e0b2cd399a4d64fed9e4ebeb43801d48abd384d2eb5765f5154afc1682a00c05558ab06988353d30ca0abf5b53f19272323342643947d3473d12c8a2eb7dd024dcb14d27932917e41ebb935b010001	\\xfabb6ba327d4b705717a3822eec23ca98c3d3a895b15d2c2f1507e913f21c31f69dc925ad9707fc5545c6538796664ebd5d0b8fbf3c3ae398624263129741403	1672915091000000	1673519891000000	1736591891000000	1831199891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
126	\\x4ed19bb3cf4e3b34426b552d72c3268c85974ca660fe042d0a35a31d51e86c20ceea79d5b9abd740f720037f2a654f4e92acf39c018357c2a6970b2199c32d71	1	0	\\x000000010000000000800003f50da13063e07f0e50e3b26586a9b911e11c6ef96853994e1d07e53d17a69e2c1f22a0626eabc5a36a31220fbc5012004b72b09980ff636fc55b9b53a384f673f2893009021d62abc124d22a5bc28e98f329be89b8a50cb73e122565523376ba4148a92cb53bb938bbe066f1519f89348a9b7bd874ee933b565f438d48bafadf010001	\\x0b7c24cacc004c4dc4aca359fa985c14db19b726926f5f21efdd6d5d7b6042b869134e37a7bf83b10d35ef248e9f8537b408933cad1ad7f146bc89f0e6361d0e	1654780091000000	1655384891000000	1718456891000000	1813064891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x4e995b61d5ddf88b6c1c32af0916bc69350c599a2ab54e80908a2d3e11ac1b154d717a58a5ad38bafb127de02bba1e0a86dcbd8031d1fbe17d14b67cc1e6c61e	1	0	\\x000000010000000000800003d68aabbe85fda1ccc2c5157a566ef54b7e37668b31f50b7c2ac7fb46666a14049bac279a06beb3712d3e84576738a5e3d964bcc3515f9cc75b447432c8948608fe4f1ba2df2b78667f988b986ec4a377a20be4cbadef7ad0b46d084ad22eb98b515a105804b324abffc171d3ef1647b05a453129e14c7de48821e42c2204f3fb010001	\\x71deee5c4cc64e40a556761a90a0276d90b375940fbe43ef975b75eb07ccb3c98e7ed7c95c47291045d960c5ef949fc1d0db1d389ee39637199810d5eee7740f	1655989091000000	1656593891000000	1719665891000000	1814273891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x5135619429f400c803d74eb55502b4b229e0d373d4051db80f3c57ed050b13584ab0b04ee5b0c616fd1667252a5edf0f4ec8f260d4d24c115391b9a823c48963	1	0	\\x00000001000000000080000397022a97cca8055da02e57f7d6d20b18b3b6464dff9f3af4663ca16e3476c4060d9d3d148d87df8540a559adb7499bb03234b1ae021a616a76de921ea70e2f04965647a49ae0226af003cf3679f62a3d3c9f30a1637be509ceb800b0b75a0207923d5a8af4342e33a68f8ec3c8b8c638379864a178f5fc088b0e2759a1940979010001	\\xdea0ac1dd24ec2de0b540c318e9d695ac0c65456bc2c35814e61bfca4983688fa028ebb69b3bafb91493aeb4b713fd01bd5e27d715e6ab3ab48d06c57db8de06	1663243091000000	1663847891000000	1726919891000000	1821527891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x5271486309001319aff7a091b26a8132dfcb8f7ff6499bf964e80772fd10f10551c6a0d8fc4201792345dc6cb0b2b2a1b6295a9038ea6856c1ec847d344062be	1	0	\\x000000010000000000800003d61849db601196d00fd30e100412a221370eddc365df39cc73efada7151a9f80e805c2abecfea58b20197702b92101d42fd17afdad5aab1e98861101eb96f1c359f709864532d795848c3703c7f091dff4c43d2cf69874374ec7d0cd4eefd4efe1d816bf9773d87a1701dec0e8ccb17c98c347e4b71c6ad6830b51541d119ae5010001	\\xad3e641b1f3b7ca2fc412c01dab1bd0a439813d9e38881c43975205a638295797f4a03bf07cdd59047eb1e928ec44a55d8caa16f408866570eaf1d84cfb38b0e	1660220591000000	1660825391000000	1723897391000000	1818505391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x58513670698150d35f5243727b35c6af767ea12f91cb8367a3bcbb8a3c21366641bddec59b2ee81dbdd274fb4106bc3997961c50206982e5291bba71e5c1db01	1	0	\\x000000010000000000800003f6df654a3f5a020828068375f81f39eaa95c6998edd221231604be49a55a13d3e6886568c6a25bbb4912cc8838ebda4fc3c5cfceb16d00bf43f378a38073795e6dae2fbd856e853c4877e83148d3afca2b021fb6c8325cc40eb346b7d2c10ce22f02bb3d28632a3335c4957ece7aa4702dc9fb7f1d37642162ae4fb77e83f99d010001	\\x566638016d45902da7bd5271be376ba2f7a28e1cf1adb41e24cfe0ebd3595689a50aa700606ae13fb549de67fe1395776d4b9d5e55b67bd4c2ce2d675023a90e	1651757591000000	1652362391000000	1715434391000000	1810042391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
131	\\x58c9aa12e19734cdce0031800c1c1eff1da51475d58e4f42afb9b918ade5398b8dbeb90ae25367d229fd2f4246ccbf9a90011dbaa79623858d17acac29513d19	1	0	\\x000000010000000000800003a8143dc44189cbcb12ca356947690554528ea418f173a3073cabb4905c2558b692130e75c8703003aa993345ac396525182bb8b2ae051250abb93b70d0c981a62d6f2de7758a97600918a151082f72ef7a4fec29a8a253683bd67f79e9f5025664c74f95a05abca444d1aa8e9827c62823eb06a5ef2ee762e4faab9de9940217010001	\\xd82fd21555f2c9d54e38be0aff3017dded05a327d26ac717de717fe5f13d5b6f972edaf1c00c6f570f36495089c34ae91114a704f165252e30a66d369a8a640e	1660220591000000	1660825391000000	1723897391000000	1818505391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x5c3188b8f529f944c69bdb9c9b5ea6a11bc67a4bd55d46b1c876921fc192510e9b16737df5cd23162b7c1a289b9e23eab01126d230e06b875082b5c9271d5c9c	1	0	\\x000000010000000000800003da96b3d8e29f21cff7b63f1abc85b350f59dad6e6619614b6ea14db8d9b6f3a3cc7622f4407928534ac6bbff31ef0465c935cc5d464192a99360932d5f2cac739a42830e8986c8bc060d89d499f01279c2beaa8c77103475783314e315cecd1953aa2b30cdacdebf47ea52ac6139cc8f1f60df2e0964755d8036ff56b3f51d7f010001	\\x9c2e118558de1dfcb3688e8f4791653fe2bca745c2686e0fd4caf3f8b0a9cf91da7c74388885d23425612b49785d19aa45ab22a9228986377c3e50956d52a906	1648130591000000	1648735391000000	1711807391000000	1806415391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
133	\\x5dad8dfd163fdd6c0077e3434c69ed7270d063bfa32dc8c80b7d4f6b9070382ec5ce2233fdcd739c457d833955d8b4396c4a8fcf0ba169019aa58491693b4399	1	0	\\x000000010000000000800003b0c4ec5acedc6333028221c484a66808bf7c020b0e13ee033362dae7f814735505e124d6c514d283bc9b616fa7e8bca12ea31a4b34992520436399b052912538f903e4fb5aa6b3d23354c6eb2c9690c506895d88f06a45110b05fa52492869278344f6d2223721a47435f3af53cec90b2ec47314cf6e8bb289afd47293d6a471010001	\\x7c0f92b0a97aa751029d3e39a25500d5ee119e3c9ee3d2842a360871a1cc64ddd563b7aa92629b900e8d8ca7ccc37e760703f4d3ddf3a7b9009d0084034b1708	1668683591000000	1669288391000000	1732360391000000	1826968391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
134	\\x61b59b0b0efae2a8ba00f30fa07bdc22a64c15e738a6fd883c6e98aca2176ee62458305525f95f6013a8ae1b1c5244023f2d624d1674a60098476549f58eed2e	1	0	\\x000000010000000000800003ab9161e0b8f631207c820ba72a99a77bb4764a25ed6ff136b2807a9c671c30148813920a4beabaab28171d1905987330332fa8d2d72930718567a341a4c5257b3531d823362f2cb8a2d0799d5fb6275f992d860a055ac6ef16bc2c9037e6fda87108d46054862f2ac2dbaeee2a37b49b474a7b52b3512a0dcf73d4959ae84221010001	\\x8f0f2d636fe2f80b5f33212cea1adedce374f6cb35283fb2b847aba2bedc56a4014a43edde63131b5a64906f34fc75a0aa5df77edc6f1aaeb919eda175508d03	1677751091000000	1678355891000000	1741427891000000	1836035891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
135	\\x644953c1a8776dcaa9972b20069455d220bc3f6ba4c1b295dddfc96282af34725db5b023cbfd27aa4c029fc538ebd5056403cd0549553cbac6be1c2bcea45188	1	0	\\x000000010000000000800003cad775ae74d98dd1dca235907836a6e710187740bd49602c295a86516161538a946d3489bd751c29552f81c9e64e0993b8b7f8e56726cd0423359b21034db266ce88ba8daead8d4806d04a442b7ae377e35c6fb842d54d0fa2f3a7cb9b7e37936103d044736686c105b9e654fe930cb8e8ce840ed33f6cf9f761ae44dd3360b7010001	\\x5e043754f1e13a0ba1bbd9dbbc9fa5f942472e210c15dbd715da3e34ad9dfc32ea0407285307a177411674f4b662168c6b20485473dc4c4ccf3334f2ffadb409	1650548591000000	1651153391000000	1714225391000000	1808833391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x67e146f7c157dcb8288b7bb0eed89d2719a79402cd853fb254bc294b9c0c21e83298ce9e9472538cd1b5225ae371d3f73eadf70a782a436d1373c9c1db05dac0	1	0	\\x000000010000000000800003c028d87d7ab4e98af1c6d932e01fabdfcc349c375f06f2f7cfdd502b7a95edf5cd944fb7fc9fcbec110f3969f994b5cee08bf4efef2d8dfd875d4c7904dfd4cf1f564be3a6a85aeceaf367434ddfab8d5594c48cc0a52f682679a7706a728ab950b19dbb9443e927aa23345197acdb199b28a00ccd1215ad29aa1ba473a2842f010001	\\x9ea63effc304e0b297ef6f67ea5971a766b82607e204a16218cabc60e04da69995c4a1d0469dcf578a49a4bd01b55bbf37597210d3d9449676d238ab3ce82408	1667474591000000	1668079391000000	1731151391000000	1825759391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
137	\\x6911574daf5c98735a71782c81ac93effe3488bc9c69da9c61ff5524a0960b210170b68b30be208f67f0723bf1f52bc7cc050ddbccff39d8edefc6e9f00dbcc7	1	0	\\x000000010000000000800003e91e8ebb347d8cbc385c13e905db0939b2e4dcc6f83bf45dbeb05386450c4fd90e9b611f3440a56f902148e2201c3422401f4916e6c9d0a362558a6e502ac930ff99746b56a8dad14734ef08d99628ea4fa83ff09b09d730c66b4afecbb53d80fa21ed288ec9016a8990bacfad78c28d2d8cf3c53bed5583e5d09519b88db407010001	\\x4007423aac7a850afb5d534539dd6e3ac07f04d5f9cba62023f1adca84234397f348fc1d4e698c291d5e1181bec059fea78d6ba0e87b3dd6db3f9d22277dac07	1677751091000000	1678355891000000	1741427891000000	1836035891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x6b3d4daf0bb94f9e18f6cbf2522f164bb0181d3cbb53dc4526bbc8eef21e81c180e2ea059ea1172076431551fd7dcf0dbb0e1056eeaf7ba571bc778090bbac15	1	0	\\x000000010000000000800003e110e925f950ede637b87ee8dc442f295e50181095b088d3a7bf7155757892a8f8cb44bc39d94efa7c48beb039d6a762ced3af2cf5e683a8d01ea274028a884443468407c87fdf84c023b23e0d0d7bec5dad398c17e74160dc23da2c7793296e3defb13adcdbf405e984dc47bf2067f56bc81c0b350ff641ec0956a897f96baf010001	\\x3cd1dec836ccd4620608daf1f9ffa4756b8a9d5623f4063b5936bed3d60aa4c497e21bcf773afe17d29076687649502e8c1be56580a10f79a949930fe5f96800	1672310591000000	1672915391000000	1735987391000000	1830595391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x6cbddf40f4585540aa37546dbab70596aaa84d5e6bcecbe6749c0436b7bb2fc0f4a22cc66c0663fb212a0d7608607976b044890ffa3350b9d2ec6a8a59dff341	1	0	\\x000000010000000000800003c13b237660c89c700a9c7a596c716202ae055608ef009f91a2e68460962428cb6f6355048ec50a59632a2436f04b31c9b842714809fe10ce8fbd717f18577530072cadce177e8bf40dc547600fa11bf73ff98892000c464afa397dfce8850586e0faa43581cb2cafe5a879d2345bc345f7b0212a07cdccbdb9019aedfeb594bf010001	\\xbf26cf0cc44c4b55f6af9c6827047eb4d5b7e14c7125e01d00ce67b896fedd6dfb74f3bb60d2b5364df4c80701006d3e905064bbef8dce657a551f53651de80d	1677751091000000	1678355891000000	1741427891000000	1836035891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x6dc5bc8ebc2b0b3715be198bf9e8f7ca3095a4f01a3c030005f19766312ae252ec96dec1c863e43257afdd47436145d8f77657b0bd20ff7fbfc957dc7b9bf473	1	0	\\x000000010000000000800003e9bf840efbbb88fca59eed757029a80fc4a11b43c0db6ce1eb96c4a5e7e09d0d7e816dcdffbd4f19c66ca0b9ed29963b202f2ef59b80d200d52feac24bb2d8ace44d37c8dbcf82117112f68bf87b97ad239337bed0c5eba9a94433bb3c08bc367664954f584f8262e642e6bff501c3724facda14a3898dbb7f290959f2c70f6b010001	\\x2253d6c403dcd1be8571de3ad6fa9a1f335524974441743b39aa7f315fbef0105781cc28d432c899292e60071d556e228d0e4c56b0bbf767048f9cc6f27e560c	1663243091000000	1663847891000000	1726919891000000	1821527891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x6df1e526f71730a52b338366b5a0cb55c6e7b0e9ad6945fda1dc6af1b44bc5c4394b76433b199eb0daa201e742b5579c7b4d3442966f39204fd6021a507609f2	1	0	\\x000000010000000000800003bd3af6aab1a6f08396b538a9dc4964d9870a9a58f3343cb696a45a90ca4bffbad2b3b82c9bc15e797d8adbf187271342ead3fe42e3fec0d6e82b676fe157a587b64e420c21559b8561b155e01544f02835dc54039450f7a07c90e76701d3784bb22b70d1bd08ca953f43ad183f54279df979750ffdd72f3d3ee5c003cb36bd71010001	\\x20c9d2bc91cc6448f342c504f981633fa1becfd4e25c8bd13cc016113c386e3e125b179875878148748b20199aa67e244d53197b4bd2f695375106de8c8e6b04	1660825091000000	1661429891000000	1724501891000000	1819109891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x6f09bac64374a67a096a0c3967d72a979940e5b124957abbf2b69754d8d09e472642f10a0ff63409e5aa2ebf8a2655de6ee7bd44fc764ec11ac48d3fc3fc0eda	1	0	\\x000000010000000000800003e3703720252f52d16f834121f9c05b26d912bbd5b9d76f3eb8a85ae0ab44517ada9808c9f93b0b50848df0a812fefaebae78c70fbdff863ad18e32fa6bce94bbf93d4328ec5033df2e47a05cf9df22f5da270dc7ceed90e84044be0fed4b902bd1291f28d0cb526b69f70a3d82fd583266a97e8c77450ae099b3f121382e4119010001	\\xea020531d0612c8df37aa9a45c7c935fc08343dffc1de1f55b82e0b1108bfad1d0ffe86a63ee3986ee0c7f465ae8a18de78e5d54de113c14339ae2ad5b384b0a	1655384591000000	1655989391000000	1719061391000000	1813669391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x70dd9c44850e1cb513327bbf37d02fb3a49dbad4b232106e7ec9b0fd3e73983bb51ea3e3276382c377e9b93dbfb76024e78c4c218722aa903185950050e179d4	1	0	\\x000000010000000000800003e4cdb423364566a6de27e191703df192b7d9294980ccfffab1cd07cd656b689cbdea7fd823c99854318345c69b622deef87dc8835b66345f32e6f52a792b2dd0669f61546d1f7bd72a4ae4278dabda7df31a73ff95aaf2d66a4479fad8bd836bfa1b07793ae94574db60de8c7a8b2abb489a8acd27502496c7298a4f49d4299b010001	\\xe89f02727cc71af4bda34ce555dd0af6ea6d1b559b957f0cbbf5486c8658184243e4c7a983933ada870fb3a18a145c410e6cce312b71f9a385fdd874455b8302	1671101591000000	1671706391000000	1734778391000000	1829386391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x721d454599915eb694e4245f7dbac48c195b17bd2a556edf992f17fcbb0e5b2554e18dc30fdad26f6813d4790fd6b792b3761a6d0a73038d6caac987f1a04007	1	0	\\x000000010000000000800003ce193a55267ff988b41c278fb05945253f4f5ad792d73a75d28497a309d1ac3ebd16accb522628a727559a151cf6cf75c812a667d092669f261e328ba77f222a6b8e277300da3ec0913983c3b22b580a8f303cb836813d80e8405c93a56c16c426bf76f02ad8268df0234f80a5ae9f827a0af034dc9663af1f5569611292a603010001	\\xcd169ac9c331afffbd6b12c12d8d839dd7a72fd1ce23985c86e6b49de6268a095c662e1f1a1320b6c11e0fff82f8a75d69a67a2f9658770a081ad25b4f108a04	1664452091000000	1665056891000000	1728128891000000	1822736891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x749de2f9211926789ad5bb32d6c90bdf24251be9a019b123dbf8ee6fe17671e01d41d2df6e7adb81dcafc063a25627b2b2acbd2390236dbee7b115f593608edf	1	0	\\x0000000100000000008000039b0aaba9ba83d1bbd01cd6d3eb72adcbeb6453326f4f54116e59d9a645f1ce5e69981a1b3dc4aeb3d9da71e089aebfaef43d9eb879083b33af9566b381d006b351d490ea1cf877ec5830a3c69cfdfa157c367a358b69d2516287b56bd34add7985afef5f26e68c62e4a4a086a78be023f6e9818f25315307b26fc549802f8c51010001	\\x4d798559b3e5076485b3717bc0eb83dbe4bf440003b24fe2db8c37b4fff049f9a43ab93127fe441e924393f587dfb1e66045df46ed161b00b19d1889cfce9206	1659616091000000	1660220891000000	1723292891000000	1817900891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
146	\\x761defa733462fe83026a0bee05f5d91e10d37508a31fffcbfaea410f748f38dc60d6e34d7f25991b01706782bfff6893685d7b44fde231b1816667eb95d9be9	1	0	\\x000000010000000000800003bbe1662a0bcf94997f32ebf7d909d587db4378face01362377c4edc1f396be89f51ceb5c7bd03f67e8e2b70c65d7a2e8b0ff23b117a391cf5f3c53b7678749e6832799e4abc242758df67583674ca77889dccc357670f0b73f68e37595ff34b3240e2a1da94cde4dd3b71138c556c388557b51c87e2465885976c55c483c2f9d010001	\\xbd0ed469fc4a0aab20a5871f1cf082e3273fbc524415089cdc083b25009fdf5d82e711c92a69960a9283f22373949279ef2719800700f3e97680bf10a388610d	1669892591000000	1670497391000000	1733569391000000	1828177391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
147	\\x77c1cbf2248f0cbc293fdce109051fb1ddc42512e25035d8128788ce6463c7262db444e65f8e98e18bdb99337bf77752dfa02ec3243ae40f52c6028994434870	1	0	\\x000000010000000000800003cd72b2b26d0bf777654aa3a49740c1d597bdf04e12120ca40f90acd83a93e27145fbed595036f7543ffc5dc43a24e070c5b0f049441b7027ed1346345cf8431c71e3b8b97c712edd0b2884e9988500fcc22db3cce0ba3db9aa6248a7f346dcd2814ffab5237621f13c430ea86b23a9b8a809809b390ed578ca672b0e3c2a12f7010001	\\x8cdf740f2aa79e1c9b31df614b9177cbf4ee7c60af3c7639bba10605dbf2285211ff7897fbc300356a4f951c71e73bccad9bd92fc2e619bd4953f818f600140a	1652362091000000	1652966891000000	1716038891000000	1810646891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x77f103967f40bff5ea11e8fd476fa3bc864df9e25abd0e9de389eac3730a65401576eada9891dc207b69d77ebcc976b825d85633b9214699b7ca72d3be4ba683	1	0	\\x000000010000000000800003f9df8dfe4a3584d4234af7c87c896f60e35446f4a6c32354e7fb8085c6bcaa139e44ec94e0980ae19df0609338559829815435ef227393895e163bca9d7723f5b33e72dcd5e8c5fb89c4ef080a6ce190ff375e9f47df129cd5fb21917403b5ee01fcb52eda14346390f8899e6daeeb724a42c3d6d85ac65fbb1c9d0ef1d3ea5d010001	\\xbcd40c481af330f9fe83edcca5484ab5ce0068b0c4e598359b292ec092fb11c8731c7deca2f96aaa78410c0b7e5a3791dd2ceffd2c2ee9696cb60cc38d83340c	1649944091000000	1650548891000000	1713620891000000	1808228891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x843195aebc347d53ba10b3ecdd83e77e4e6668588c66c1ce2bb3ba07a43a93ab48744ebc1048d0d8fdf756d1a8dcb90380da85969a4d28d0265084e877fedff9	1	0	\\x000000010000000000800003be86b11394671122dc69fc06c08d13bec1e82577a0e0c6bca47cab50273114344d8fee248182f90ece5cdc3998b5fbb56b19fdcde3224b22f63997da58c615b5a58904c43e526a876c088e3429f511008e67b443c6cb04360c3f6cbe5c7917f2d346aa96a4d7cb4ec79fd17e44638337dcee791ff707bbbc8b1fd6be7bde3c3d010001	\\x328bd75b30a16ee1c93d86e5138c31125c41c5b7a85af8aff4c4cb1c02a9830c8884668782aedda703079c0418a413696c2172a8f55d07dae1a6f5bd42d3450f	1652362091000000	1652966891000000	1716038891000000	1810646891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\x8581d77a2cca5273116623d4f54adde60ab223549e10ba62a78265f16c32cfb4804dd8f5bff81af57913debda4fd6508e0cd50bc1c02253eb49a5e95857b3719	1	0	\\x000000010000000000800003c66a970b959f7aebf7cdbee5e00fb5e5f05c02bb4b695a0d99e53ad727713022c706aae1ec429f674d7557be92adacef16e93a74b4b74f6f0ed86041d67e729c14cf1e94fe723d20edbb96a23a9817a368272f1b8d80faedfe1724cc57cad19c942a01d10e19c98dcc29612b761ea7b9e2a29f9119d62f763233bda2e3271a45010001	\\xdfa5492fa934ac5d0b9cc0d75416401bafc79a18c911a0e921dfdaae145aff0b70337cc6e588a00f6c29fb6b6b189d2e7c6f9bdb8a01b4e87a2fba3b958ecf04	1659011591000000	1659616391000000	1722688391000000	1817296391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x87f5f3466f32a166288e09c7652099d9d82058eaa48af3632d66f2bbea47b2ad4315c7ef5e2f5ab962e3bba6497cbd9d3f46a0a875183147b2901c98884d3a0a	1	0	\\x000000010000000000800003c5dcd5b1c1fa02b4a7feb9c5ab390ca5d2252555260189df48d98a77a844a38cebdacd1d5b297293144de539347cdf2c022e0ff5efc5f1127a82cd88681f227371a755d2579d74defa3ca8638a523f65b834b1cdd4d8ffb0576cd2d2b2e8695de2ac6692a4b25166fd893dd81dc8e659ff8c6d05a17aff0d7d2488436d6069a1010001	\\xc2942c5af57352ec934a4b31a9e32d630a18ea065c87cc0569cf9e2d78982430acef888c8767457b87c5e49b25df71037719c921c0888bf8a3f21ff1f66b4f08	1658407091000000	1659011891000000	1722083891000000	1816691891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
152	\\x87c195c1ec247838f5c50a79791b361b4d309dc364badc2b51928093af23722436529f44facb81ef533a883fc5b8d29683042a2d58e6f0dd6e9fc36638517981	1	0	\\x000000010000000000800003c4fe25c5128bbedc6a83f78ede5da2f1fb24c82b8195e20cb008ba59497503d815f2ff0bd40d8fc115e9e0037a3146179fe34a240ea7ebd549c5ef423d6a2249527d5781254e8cbbeb9aa1e035d4b320128fe225d03c7cf9f4c533158b37c7764bdbc8d5fab6225466fab5ff9ddcaea78d64f841ba28b15dd820b788b357377d010001	\\x51a7c21342a955c485ddee614d93be9e4803c2c713f3e73eb2f4f01ce3d6a76722ad88fab5d439dd828caf22de4e45d7064b3aa9a489820a14e296d166dbb909	1676542091000000	1677146891000000	1740218891000000	1834826891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x8865d0aaccccdee80c424bc7adc27fc7cf06cb48770369cac6ba531ed8e6b33d546a8677c2b2562439fe7759b7cf5303b0a10be6698ddec811649764904855f6	1	0	\\x000000010000000000800003bfadf3a227fd41bd01b1d1f5ed06937738314e2463ffa6f78cc48101d05872a527077942c0e866353380f4a0a52306e079b9cfd2a826fe8135dfca96c120b20268a576e11fe432eadf1da1fd9ffb97c29fc055cf18e0cbb3e650e595a01093aee8b4b8520bdd0b7c6c335af960035f84c2253ce319edbec4da0f24203edfbb89010001	\\x6ad0f72e5e7f5e8299ff33ca9c9f0f5ae8937099df154ed9216894ce53ebcce6ff35c9789fb792806b74bf006ce5bc658a8ea18fb28409b5c75512934b4fa30d	1674728591000000	1675333391000000	1738405391000000	1833013391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
154	\\x8eb5caa5f6c3b4fffdef7174f3102818c2023668ab59a9535891ad4446b1c84fe1bd0a5de7432dc636349d6264c4208fe9e2d4cbba623444be14816ab304f082	1	0	\\x000000010000000000800003c08e89c501b4391fa50ab78849129a40c953bef390b2b053081b8acf0747dcade23884da91d03eb6de001e0523716a2ffd74725d792c621c7d5d4d500a65476958318a17443648765a22d2f9d432845e777d4d67baa5f6c7029c77c986560d5e5105972aa939ec09528fefc9b29e7a95196e455384adb2ad28369375d8c35bf5010001	\\x36aeea7c346cb2277adaa66cb00f3bf506eb391a26c541d3654c88d9f03c68d152a9be28e5cf5197d4f1bc6e1fe90c1971258d21f5824c06a0eaa5caae717f07	1663243091000000	1663847891000000	1726919891000000	1821527891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
155	\\x8f6d11e066bfeb2d8e4d2cdcf428a35da1474fafd8d4baae00c31822d8bce024bfacd98f39c4f1030b23b7989ad43641231e00ff7989c2031585acf4526bc619	1	0	\\x000000010000000000800003b897dfc788ac0c39f5863b5a1e9704ca3e97a32f86e5b81740ec19c7d95aacddca9e901051d7cd7c4e27da2dcb5e304dfcc1776ff5bf7c82f2d8a0926ae50e4fbbe551d7d47fd651266ac0348d9476d5f29c4ccddbeaeaa3d7b971366b17698de6a74c86811df5830da930017e09ed062803e54119189c681fa406ec24e35bc1010001	\\xb883e64f8370b441b200019e8df899b02e4f36918ffb73aa48fe2b9a3eec2259381933dd2d96317768ada399dba0d4068b1acaf5e8bdf45c8e04dbfe17ebc307	1653571091000000	1654175891000000	1717247891000000	1811855891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
156	\\x8f41b93f4d1cdf0589b5e914770d79359359af3d1dc6376f43a92ff3485d260d393a94c563bc98a2902a5262c532253820736a1a59f9f33d7811002573293543	1	0	\\x000000010000000000800003c56a84b7c9e40751354db6c0649e8441277131a4b7125fe240e802a92d7f8a2860b74cb19d592f66884352dde13ab85e7d5a126aadc0a9f30ea81be8157f80f25346c9ba90fc1e7751b0a6483a5b4458a54f7abc3fe0ea1c9300150e8b6c7d5c7250362c8cf0a8a59b7684570ff12fb2d5c392e094ff5eeba98d5390f8cbb0e1010001	\\x60d6e726aba3e671c0f45fd2def26e80ef34effecd02be068edbfa1515e1d163362a57222144e07c0de33c2620a5728c130485be09cf497a8af2f790d929b10d	1656593591000000	1657198391000000	1720270391000000	1814878391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x90f51bd31efb0c9f7836fee3ec9fa5bad57153c436e63a1ccfe2843b756875e2a4c5a0edd89de93471349f10663599f240c4eaff8cb4cb19d4735b53c6b21b12	1	0	\\x000000010000000000800003a4c9a9d447dc3f7b1666daf958b6beef60b7a0098b8922f2d44b2c6dd3fb130e0929759d4faa929742c3657efc59c8127f5f02465cb1e9a32c31f06d6b44fc222cdffc3ef8573b76219ce3af86f684b70d88695ed3f178237288962f2d580d40ad0d51074b4abdf2c64baa93400eaf25e2a627c2c85a2113743cebba409f1d8f010001	\\x278efd2960bc3961c585b0842cc9f8a3da81406071770338ed752a88c1e666be13f50b6234972afb98041f362c0ecde54adc0d81d37cbe29be24a0042a73670c	1658407091000000	1659011891000000	1722083891000000	1816691891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x914539c5452757edaf59d976f7cf9d340888af8d4db1eb0fa285e4dc1cc9dcba87de26e5a8d05ec156277872e77495f866bb6fd8d58b91aeacdc48a2ed06054f	1	0	\\x000000010000000000800003bcf42ea1a98afb0363dbb9b47648272799d1bb806db2a197a08a99ecd6f15fbf1ec918ba8917863af35c889a019fa80e0d0a0b6c1a190cb72d727ad72503d3a3765a075d9d5677d5bac2bc9a6fde8a08760d3661a3e2c3b2ab4dc8b259eefe35ad95a746fc1635225ddd0911bd230a6d06af9ed3452c5be86c1c4114a2599599010001	\\x129d8350409f242a632166bdbea59894db42c55540ed5550571d8a47daa06b64df3f566f398a9994368ab24196f70875442e472ecc6192f1b28f8e8e8e5b030a	1659616091000000	1660220891000000	1723292891000000	1817900891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
159	\\x9165f7c4365c66248a350e10b8fb384d54be067e713c818565516bdf16aea16ce6fc499340f35c69d7595f3c008e81181e221ee29f2697705c7666171925a181	1	0	\\x000000010000000000800003c9cc3a61b14ee376881f38facbc54617f46fc3cbf3a3068e8a74d8e43ad0d55d6136bff87c5123171e8eca31159cf3a559adafc254f740920ddd1300c2c84ce67cb6f8edbeda8114839c0457a8d3ebf032d66e8f62dc55b0726f30b4fbd84009cdae465c504ba7ac8d786ce9d7e7ffa80c921ce7cb6343ba9e4bdf3080b933d9010001	\\x0c1e5febf503ea4919f16135c74765447092b94e71789f633cca08e8c371aea0d2eeab23e3775de73bbb068778e89500b0c93986609a6209995675492058320e	1665056591000000	1665661391000000	1728733391000000	1823341391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x95ddd6dbf58409565ce8f6c1959fcfdf28d3876c11888f75fbe11f6a48a09782bdb52ed918264e81d590d9a32f4f8eae2ebb0ef4ae40b35f066df56093a8f74d	1	0	\\x000000010000000000800003c6dddacdf0c11bce06eaf6ec372d6a6a6d9b4127370dafaba5a8a62d0f2e725ad40b64a25c6e5aeaf395fbd3223bbf34d8eb263700c27c2764d0b1f4d14e17e10ec4915c8dde0659dc4fa498b1f1e597b70ec6ce5f11579f8745ad56d0fadd561d55adffd444bb6f354ca03537192a925ab16bcd4d0b52bb51916d1d5501344d010001	\\xd4028b1222c415c02bb312a6b5bd45871551bc0ffc758db345c2a866ed2eaa40a5a05b27b585af435cecac1436228faf5e7a93d8823bd96c97c459eada008a0a	1651757591000000	1652362391000000	1715434391000000	1810042391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x98d95b4d96dac0325932b431e1ea12cdc0d18f7a3cd712804bd794b9ab0ebf7617473ce4149c7ff7a0224b39c5c377c6feb48f129de1f322eccb40e9081c88ef	1	0	\\x000000010000000000800003d7b929a9f71695a1164c427e709c1168b2199f5ebcf2cd1db2031019f1fcdc9de04ccda5ee58f14ceebff8f24aa667652da045757c30b461c4fbcb9e138185cfb145cdcfff1ea3c2651b3294f5c0d4a9774bcf2d806520a6bc76d81a3469104a9b04bd819bda34e4146145ce4a3cc4d7ad4c6af5281cf7c1f6d66f8eb0adff8f010001	\\x9b3ad32d18b56780738d0b9931afdf7adc60e9a3aceb1a81b14b4cf780232f6fbbbb5fd1402f0173b2f644670325da16d98d4c77472cd4c5d9f0939e463bcb0f	1674728591000000	1675333391000000	1738405391000000	1833013391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\x9da5f3ce00145df6c9f1515d3b83383a828fa2f31b94dd2257d6871bc4a9b12da226ac32779ca8583ebb322dd7fd0d3cc811de7296ad93624f0be2f8bf9f9e43	1	0	\\x000000010000000000800003ef6506e35911ff88d65b71603868957c2a51ec17fdadac0915f73dcdb2a0e8dbbe4820529214c50301bd6023fcd55ca045eb98a60bd43be6d95abf55aa7f9268c179dbe1acfb0a6ef5a5926fee03f8d4f2a98d331aea3a891437eb97f326b22fc11b22f0326f6b085af11a982d967927d9b9c1272b9ef4ee299d6ce363098a4f010001	\\xd4b298d83714f8d65001d4ca8ae881dea46cb51da3005fec5d5b937aef8c0c73097de78134d07cdbf2ffaa8cd0a7ea4bf39cc3677d989ef48b9a46ae3910fe07	1652362091000000	1652966891000000	1716038891000000	1810646891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
163	\\xa0957fd94bba95f970ea55cf0cf4b043f1005547ec7188867b70a38218199173c9ce10f96674f9c5fc386185230d84eefdd68e4a009bbb9ed83365f58cb73fcc	1	0	\\x000000010000000000800003c8b4f5f4d71f2c8cd9e27789a3393aa014210b308f10f2355acd18ce75e477ad58d95e56ec1b1e8199f8acb358564d80d4483a39958ac8ec5ccefdeeb6e47245e609d4104196a7a7b60a4d35b203a0a5ecdbf0c3bc6400f754a7701779ef9bfd0b917dc24f17056c8f8b6ee1f2ca0ae7b993438b4ac7218e0c0cf98f55bc6849010001	\\xe95a396149151f4020d9f3441bee8f3426c10c4612237f5673ad57872124d24ba11adb4d502b87fd08c2937f02b4c4e58d1f6e685620ef811b6b98ccc8e21901	1647526091000000	1648130891000000	1711202891000000	1805810891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
164	\\xa34119e8bfa268665d65fb268e9a206057ba5d4b82b4fee76f98e4f082e1580a6075f7e50595aaaea7fb1c4950eb66ba6e2d10831a67aeb51304a17461b1c0d2	1	0	\\x000000010000000000800003bbca03bfeaace860cc07a423e569a218a303b23c8b2ce3e7a7c4b43817d1b0b24cf419118577c12ad60ea9d03e72740a5f8a736c48b8480faa646ed8ea2375a5368a692d33d359fbd43d12697ed66a1e23ad2ff8f1d0f40b8cd2bce111865312a0052c045687bffaa745777b63c6fac6d32c32fb20e3cac844b66aba8be66f2f010001	\\x266404ae587287c17b2aaed85ddd659348d5ef011211efbb8436a973febefad1a1588a849ec24fd6bac8a58fbd7e264dd8775ff5c7efd279f94326bd6de3d30a	1651757591000000	1652362391000000	1715434391000000	1810042391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\xa445c43a5b57a1cd38d8c16670ff81136cbc3f41aa1cdc7a8f7ff966d58662a6f62d18c1eb0536896142b150a7fc2ca041ed3019b2e738115895f607e7629513	1	0	\\x000000010000000000800003d0e8a7f1886e9579f420dabb054b2484f4cfa07a72c0dacefd2d4f47033f014c1e8ab912ef0b4206ea3efd50e01c8f39a3e12ef241cce8daffbaff7197f678531e208f6b4252af458ebe82baa5defd089095eef35b91d349fefe23a2f844464baf4527370c926f7fd2497a19df1aa5f01dac2265d5bf3740925b41df8342b507010001	\\x7cd46ab74674c883a7bd5f356169278beb47d086ee219cce4625d5020171555d5471c04c845c70c54c5425d64463aad0b6a7a259df364b8e4d67cab2cdbbca01	1656593591000000	1657198391000000	1720270391000000	1814878391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
166	\\xa6b99dfa201c51c5604303e1177b60c7837856d08fe392c9bafc1d6ac742595f6ec75824d3d667245bcd2113dfb4d2cdcd6a1c9bc1dffa66eefd137af67120ee	1	0	\\x000000010000000000800003ab1b63db11db0ee9b08ff1b05125cc465d8212aa776366fd3325a72d7520949a21e68ad12de095fac98a583711bb1567d18597b754e5e05fe68a6d3c971bc199f861fbaf3eba3671066ddbe2bab4ab8ab48cc02554b09d4cbed011ea8d1aa84d59ed64d424f587cb47e8bdee9b48c46ac2216eb7f1652f54f291c4684d9135bd010001	\\xa0a34e9b0c71486435781b628d8b9d9d94dde1ee17bc597a18d85b0ff0d21c0b097316ed0a32c12ff7967ff1922facf759f32af4c367c4c7e16fe7ae66ab2f0c	1657802591000000	1658407391000000	1721479391000000	1816087391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\xa6c5219afffb98283bef09cee0f0dc68a84ce222881f48e4465589bc7fafae1c28419b81958edfc9e98f62243d871dc63ba542852e8dd8b1fa0978f2198c3673	1	0	\\x000000010000000000800003e31be0112afee9b99c05867a9b83eebea1e037e298c6deac99b6c79b75f045bce87911560db927d6dccf88819556fced8d120f3115cb1566b3a90cc35716c2f003ecf2c3c20daf06e39fe9cd322b99ff63848db649fe3efb34aa81041f282b372bda4d5c065be6e7592529c573db5f09fe0828ea8520fc0dff0e3a30907bf981010001	\\x8c3636d0370bb8186536c5f7f0eca349969f02e950490aa60343b9f1460f29bb796c9d8e17bbde8c776eef895fa14885260486f8fecf429c6478223f1c1f0b02	1648130591000000	1648735391000000	1711807391000000	1806415391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
168	\\xa85d996fd0aa6965dbc8288a973239117af7d113ba4ae7d9e3e0ba997dffff2df87712345cc5daea0ec0494bcc9ea967278027630ce1cc9e19ef3fc1cad1c011	1	0	\\x000000010000000000800003b70e56c276de95ce0f1aa39a4b490c9e7ff8ced961f02a2f40acf22206faf2c09a50bf38a7eb628561bf1e2d531c00d8e018e50976f30ce49786ccd2812a424dc6010a57af3b7a94b208a3a36870b9d3901fa8a4a8d244e1039280b9f32379aa214bfce8c2b53f9b5321bc2075412da251c5adb2049e6570d211121e4120bb5d010001	\\x75143ed7d3cadf021e12dc5e16edd2cc312bd97501194a63b9bf6188bf03e446fec03250eab742a15e41a2bf44c47a050b369895ee0c642e9c82b8a035c5de0f	1678960091000000	1679564891000000	1742636891000000	1837244891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
169	\\xa8d52f95410274b7bacc018f92045d4a75f1bb6935d33bc1b50eb23f5d130d49c634e69c4874f28ad486f9c26983f0b6d6bfd654f74449927b898f26aa41396c	1	0	\\x0000000100000000008000039d11aae8f00c26d00d64ef5bc884f48ff3d66a819f14ecd144ca2f62ef8f3394f52d4d54b4bb78f3e55adbc30a16aea4325b1b30596c202039d04d3564b4415b86e5ac1f3730ca5c577cd367dc6dcc92ef837120ce53d15445bacaf979e10dc591b6e3221ef0955fa11208d479d3c967b69329572e9b277d23e6b99ff3a37a87010001	\\x2642f44304c82fdbe616383b57c3e0814be10ce91c37172f44192c0b41359f31e9deb1181029b9746798bc4e12109e420f5e92845a66722df0a4a57f45dffa02	1660220591000000	1660825391000000	1723897391000000	1818505391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\xac21a4c5dc51655f1d006d96d8da9b828aaa5e2843c4ae064cb810671beb576d190f4812c2095c42907f007b3c872ae74ddc3d554d1b1d6fc7c0c35709720bd7	1	0	\\x000000010000000000800003bf1253ae87cf2866b634e6c2b3eaac5b0e2c629410595ed321b640da871c1fd6fee4310a9ec62d360261bf178c67e8b836a4c7e60033db27fe9e4707cc3e3cde0c27791b40bbd9e47a27cb7c241138193f04526c0074ee297255eae1da587c493f3e20482d66fae223a14a9af5e64d400469d006cf2cc38c02d1c1fa975d13ef010001	\\xfb0702a623c9fca6a82e028e75314203cd75379537fd41a230bef51a8da730f8d4a47ef75a81b03d9ab16c798daeb52fb7f39cc0127dc68d86d6d4ea1c1c5509	1651757591000000	1652362391000000	1715434391000000	1810042391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
171	\\xaea1d03cb7255462dce177e831b821d26271641b3346f7a683b3a422b974c8bfa2abb538efcefd5ad32a9294baa1b59929ef1a9ce4544b12ba99cdef133a8b90	1	0	\\x000000010000000000800003b6d0030d97834f0e6b7afed0c91ab179fc75bafb9bb5a0f7216b1c8f5a7ed4630500b238cd5d1894e320fc9eca6710afeb521b559e5533d57c1f58c3fe3a5aa2bf6c4d06224750d75472a8cf8a0f264530c19ca36970af8c9968f891450a7a4924f82529ea39eac0c80b63a3b9daa287a4925eaa69e3eb664751e2f088f1b92d010001	\\x2d3b9387c78502cbace58033fd12b0834b83467c8cb69681c19616791b4f4126b45444bb03180f316ede879fcf5c3cb6f6d080701b4a6ca69250d3bf44d15301	1666265591000000	1666870391000000	1729942391000000	1824550391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
172	\\xb7a5d780144d81cf87debb03a5a2fc720d0c70ca9a9913bf564b9b1709de0f8bdca41aca9725bd79693ee650216379a05b658bde1d4e007c1368b9c538e9cd7a	1	0	\\x0000000100000000008000039fd28668bd261e91a69cb02de91fb9a1dec02f03b63e6ed42310e26f71c6331edcdabd42f7c4c9536077ff81ecbabbccb50b040fd6744f3b55d9806919e22d94b9c6c40bcfe4b7a5975fa8a16a3ee10d9f68d9b4406c2cd5ccce52534ff5c39f0a348a6827a789385fb599e43aea65ef62d81afe54af1b1385c857fe30891dc3010001	\\x8a83e45ae8c0973c5ddc9579f2708d7ac87c97d4ec1c25888459e44cc4186f0a3c084931bcc782f9b0796173fc70c16eff02cf44b8fe5a598116b8afa9905706	1670497091000000	1671101891000000	1734173891000000	1828781891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
173	\\xbb5dfdf37511385072261ee5c4bbe9d2f860d23203ed3ec781da3c8c2a13b841e229c35d962a4e72ec2b88ccefac6fa08f4be3e83d20345861e3ab32c82cc7ec	1	0	\\x000000010000000000800003b9e69ca3f9e4317c1345d9c1308b5764edffec602fd1ffaa00ba1ec65356662eb801e578080b64426100deaea7aa8362631a3709b3582b4e96b19a8bad29cd9d42c61c66ca7e42777f533b6cad18d21f721b32b6e4fcd49d2c9abebe1beae5b5586a8400d60888cc166d4414628ab121f10cd77f0ca3b457ddbcd65f4edb0453010001	\\xa18e38a89a7d06c692431791b636183390477439e92eefc1adc9eb07d4dffbcf5902517f8310ac66d6aa01fedaaf4af73e35e6478bd02be4bbda4b4dd12b1d0f	1671101591000000	1671706391000000	1734778391000000	1829386391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\xc0796bc7ef7ec4f727716be1a2764f3d40b47b70fc931b56dc6074255bcd2603ea33a284ec2d715666f7376837907a198e54259a072fc13b33ad23419b32c967	1	0	\\x000000010000000000800003b306c71b80daf33662d8f2dcc1918defe651f6702456607eefebb79d518068e71a9548b514aec8fc0784fde1a04348e5ec81ff8146b62cc3afdddab98d12aa09c28723340572876104aa48ab89b657b1f239993e9d257239f03052212f96b6d9c6b986892803c8705fd2e2517ff0f0633b8822089d45dd0f444259363980143d010001	\\xf92462975ecea783b4e2f5cc6d146afa21abef07a202d5539f084408e1135d7a26f9f13cab920d919ffdfe9da9f7098aa01f9feb68a967367261c03c2e50670a	1668683591000000	1669288391000000	1732360391000000	1826968391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
175	\\xc1bd452a512eee12acaaf962ed4edade210b96b1b35b9ce1ff524ced689a702e88679ca2e0df64615228f5f9fdcf9412369ee9d0626a353901d7e776b1ac5b4c	1	0	\\x000000010000000000800003a9a114f6928168fc2cfcaf3ca51f05b1a9337c6d36faaa909029289bffe7a32b95627638314fb39d924933c08fae565b9c3b73a1fd7664a548fbe89aa5bf45a835e693532048c1f0b452b31c20fff2d2a1057e38b3e910d06c4aa6def68d504151d46f658387ec45f120de8dcbbf87736cf6cc6ad5c661742e2c23f3353364eb010001	\\x17fa53793509c8d101f5c316ecd85e4f46404a812a715997cdd4cde9616b53b0e7f18beeee9dbc7e4bbd6dc91a75030f76f85dd2987b777793dba733a1047502	1677146591000000	1677751391000000	1740823391000000	1835431391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
176	\\xc541db158e246a2daa99cfed718de800f219ad8baabcc6c06c3a9a921b85a64fc5f6e2d6d6067d2e7a62642ec973f25e378b49ca7b47b50378af3091e6ca4f52	1	0	\\x000000010000000000800003ced147751d540576f44308ee79441b03fc6cb06bbdbf1481ab130edd478064877eaf50447ae4630877cef6d44384832a39a80beab82fac2189c5610e819a6658cf65e4504931e09ab1b9a75e62217f18cb89024700e548996fdb953c1129df360a3ac65b62d6fa33c63f93fa858e35a0d53c0b2dde7c8e497102e5a480348b89010001	\\x75ff8b26c68134ac19a8985b8b827c8d20f289bf72edba6054a7bbf16dcadfeba36d9d176e73725708b93136c9f4b5f02659e4f2295c0c150984b5892c8fe501	1673519591000000	1674124391000000	1737196391000000	1831804391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
177	\\xc6b5fcda77c51e4659e74a392567d243df3b794a6652eff6b5d340ac5592b6ffa5998e14d80d523e9f6a5a47acf12b010df6447c5515cbcbe9347c5423de1e27	1	0	\\x000000010000000000800003aef2e0ad3317da16d7a44383fb27032cc322ee11fd89d357e7847dd1c39c23b2f1a79dfaac11f70c5ff15af778c8c34eff630b76acc58b56a22e2b952229ce82846a03680ccaed15d63b73ad852a2b09b6009470c555331a401652242b867d0264d6e76c6a58afc1a73d5a9811ad1c18041b02415b5e1364a45686c9b56a68c5010001	\\x30dc007ae632c54da403b9481b3a508634bfaa51d09c0e88fbbd71c493716ebe962dd76939b0a7896a6cf4814e9a898d2cade816386236d2dd41ac74bf01ed09	1678960091000000	1679564891000000	1742636891000000	1837244891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
178	\\xcff1bc9259155a2864b722f655b76e0fcaee1616c9436675957cbe4343025cae7c1bd8c762de157d68ae50c22ff3f833f6ab75e49d636b038f8cb8d00df496de	1	0	\\x000000010000000000800003cc1018c015335b28990e30c99db35ae70ddaf7ced10c56b9eebb7a464d13c5bab221775061a86a8559f427b712d2a2864386c07f4edab163166cb31463e2cd68ead6d16c8ca0bcf758b443a20844b73323426ce8d16e90934a79a4c615d0fdaf5799a1145f8764e0d858ea29f3c040aa15d76c148dc45824615aaae81b30c73d010001	\\x96bae14955b99ceafe326952f465f05811ca3a74917d9d8563c5ea4cd0ec7cdce8d64f7c9d7a72ac8043aa16eb774c0ae19f2d8e41fa04ace43bcd160cea2506	1677146591000000	1677751391000000	1740823391000000	1835431391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
179	\\xd03da683dd4f6c25bfe13209f999b433396cc930e82f42da72eafb5e0f15227c38e7f7701357ebbee58baef7de003d93ff81d15a50fbcf536607c97fe1d05601	1	0	\\x000000010000000000800003d3ab783da9c9e39ed82a7f5e2df36828e89c0be35f660a3251e7e7aa7d01448125ea0d2667bf50aff2078ad03b50727cd12c824bef2258cd63919f3c94263034ad81304e21f43ea2388b034c64bad5c181338277ec2fefa5e9e634182850dc6acb91d9e4709a108b8cbdd3f92c35fb20254fcc8a82f80c1581c13cdb25aead3d010001	\\x728eaba9cc8fb1ee5a9985848d0da913d9fa08818a4f1cbf46b187f7e52874b4a69f4b4d3cf5cc42260a3c85fd281ec6cfa329867d52b94bacdcb52ece53010d	1672915091000000	1673519891000000	1736591891000000	1831199891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xd1792c6a175c40e8e3a870dbc6ee19d8f4a4781fbc0dff24dba7182f4b46c77ff743bc6143d3f7027c7ed35d1aebf86dafb2c15c38e6804478d1b93ce5b4928f	1	0	\\x000000010000000000800003d7a6c714f6dbe6d7443cefe9826caf7f23e0eefe309cf218f0509fdc1f1cd2fa4c96e3ef5bce2482190b85acf4e4be0a63d8f65ed738a2d4c17c37474718388345bb791e76247c0b8e95890420cfcce0e497a611b2c8558ba6200c28722f8c188778cdc574935dee59ec7e6f8508afb1939a0716909704d60c00e00e88b9b2fd010001	\\xc167a51a6c327ef621fedb3fd30655600014e1bd5828e085b5ea92d299b564a0b5ab8e838b0a6dbf2a38c7ba6d6720d1d49237402ebe4503d601965dd27b8e04	1653571091000000	1654175891000000	1717247891000000	1811855891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xd2a1fc185b53880a7ff904d171c714f32f7657da3f547b3a879eeb1a0a9af4ea99882124fe5f1e7f54408906c8849af872e157e9d145b557b04311eacad8881f	1	0	\\x000000010000000000800003c136ce146aa5b67812f93b55aebefaa6d5809cffbebd8a790b918d923a7fece44f3927eb2876c3a0ac494242036a004b5ef55a1154dd0cbe91789e704156d757b0f618acffea3425c32857a7e4b33e4a97217310cce106832a09c542b16f653cfdd6af91680301aaab028da607fc62727223670f6b3ede76243cdf7d1ce49f63010001	\\xc78faa17935038eb8ac48de1dbe00648652a7d9f3ead1075e9eaf3553b0f78e544c33c3f858d87c73875eb273709ee6c74b1abe68ddbc01b3617b936e29f630a	1650548591000000	1651153391000000	1714225391000000	1808833391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xd585e6ac33b970790db837ea4146aaa8db0b28ebaa167ed6ab6d7e1cc87e2764682f2d899828f37ede129e373ce475669b96af9d3bd45dede7e7fc2f50778064	1	0	\\x000000010000000000800003eb844a4e68ff5588e0db90191b1006d678db8422ed4c9cafe89a652ae89f5a9de3072566809e65833c0b6537500092e6e0f0f0ad886f9ca12d383ba53bbb0f80e312e295e610dfe61514027fdfdddd16d32a8a9528700b83ec47c62351e33063363848dc5458c719eadfe91ca424235be93a6d5f02f91c0ee1adc48bf600b69f010001	\\x3f4998a6abec73940c99a92dc1fa793c3eb9057518a72d538f02f8ce23a8d1b8636862e3c0047c5a2915c9d4c6395aac41cb75985427808097d50d634c266806	1669892591000000	1670497391000000	1733569391000000	1828177391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
183	\\xd785372c853fff10b052a77bb7d8594f39581d2959b716930f1f891b3714982af726ff1fa6cebd5102fad4147637a24e9aa6a8d47d0dba96b6bdf8d82b3ad6ab	1	0	\\x000000010000000000800003b54f74442e433f39c0b4cc4b6c75953f8c70cacac272cc595615647abace6dbbb55b9b03cc804aa3148f68783a5a49a893e41372a4a0adaf07616c90a6b11424775c64fd987eeb98ea796abc97be111879f88347d6a0bc170772157b675c1368aa78618dca51488d3634be94cf43f227e7d8ce73ebd90f368f698bbbc81d749f010001	\\xca955962bb8928c93d9c350ca5a0c45e57c53eed2de253586a5c82b6148faa44642179e8ea3754064ff38719a9fc1e171bf4665e5350dc434cb8d610b68cf603	1675333091000000	1675937891000000	1739009891000000	1833617891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
184	\\xd84518c059bee9f32968ec0c9e30cef9eb7cbbfead4d00ceb63752b6a538b59a17b501ac04411c212cd153423b663cf5edda163e03ad1b27a0171dfa122042a1	1	0	\\x000000010000000000800003eda9565cbda468ff5d5a9acc8908dfd7917a8faa37af9a54e42a44afd006b18d8064c972ffaa7989ca2ef6a9c835e779c4ddf0009cd0ac39bfb3a617d51c571dba4cc5dc7d62779cba94682242fb2962ba654ef432e5af5fe1224b4a178abe0fc69b4179163fb1014b184902cb466abde3146834b82d9199bdd6316d25d23f5d010001	\\xc1bdfd487113287eda11ba26c2cfddeb6e382813212fcc39ad7523e42714e79c4564dac6078f74fded2d5b67e20d6ad3f3dcea94b0f6d7a88435ae161e2d230c	1665661091000000	1666265891000000	1729337891000000	1823945891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
185	\\xd88547d629a4ed89b79a7005471b7b66dd50790f38d9e212ccc5ab46e14b712b93be6bddc38b733cf29cb31e6960cfbd5f55c171c3a9381a0840962a68d3d658	1	0	\\x000000010000000000800003a27e0ff2f4b76597529b2ecfa8dfca64eb63a3711181f8d9756c3ff56ecb1f9b2cf034fc19da5c2bc623f7280a6d2f0680f49f58bfb0c6b61241a0d4699534741eef7c978465e51f1df3a59034e3dc8b948aeccd7fe76e538150f04a4ca68d0a236e16939ab5f91b0cabc791354258f837d5ff41dc79f86edb6ac74eadc88a0b010001	\\xc931fd5f0bf38c1f2c99f8790f1157abf9d6f9196ce15fdaaec557de935e0e21b1ee804dc3d20b62b142e0c120c985c89a3201a93e78ef92cb33e4ac9798d607	1657198091000000	1657802891000000	1720874891000000	1815482891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xdc619f37a13751a8b76a3549383bd9bbdfeb96844d1d610fa6a4f2ade977ec10315e03b2903137ecceed1e9331d4eab61a68190949085d05ca1e27aa3d1fb4e3	1	0	\\x000000010000000000800003b69bd1d3c9a364aee6b63c3f70b09a892faca7071bf3d66f2152b7c9de5630c4b258cb8629e1c08de2ff99aa186edc2579e8dfb50f1741aaddd4c650a815347e50f16dce8a10e4fab31609bbe51d356f11866ffda6b63eec4919fe18529a3ea6ad13b42ec99ad4f1070286c2e7176d2e0350f6c2475b48245836d44ead4fef0f010001	\\x45f4e4416abf90f4587a4efd2600b2f7a69732c697624122cf54f9215bcc1621b7d66d8067a7092b24ffcea84a135987a6ed2c50890f38c3b2a81bd71c125103	1676542091000000	1677146891000000	1740218891000000	1834826891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
187	\\xdc990eb0dd188ac591fa1e7abeed7d8152bf54e981d967dbb49c05e9270a73db85387dc7b1dce457cf54ecb3443f324303784ed0da29639102237e5f3ee9a20a	1	0	\\x000000010000000000800003b139e924437b98cdcd3229654b1cae968868b2fd30272cc5dccd47399444905e89c997790d8e8d3b210df901aeed4eecc251da86f427b4352e1b4d2ea01f93f9e305662bec165e22f9f659a0a7e5590327a558dea4520627a1a4f182a832b8846ca0b105906925400123aae9b3f110a58f013c045f790b74d9e11407467306ab010001	\\x1358c889ef6921945e08721c8a47ec279b9c8940cf995318b30adfa1b87f7566fa34eef8e733ac59373b7012e0ce9f82404ec067adcbd70268793050d7938708	1648130591000000	1648735391000000	1711807391000000	1806415391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xec3d6f7acdb2c738d7d91d4e7ddb1a7b132ba1829ff6c515ee6e0fce749c382181a7e7a15589a134d4a3eab6706ef20111ccd0fa87f76dc8c61399908db5875d	1	0	\\x000000010000000000800003e651dc67b3b6311a9b8168e8077020f1b72cbcef80b856551e5d6867466146cb65810bddf2dad8c6c56ab980f2f323e112dc657338d96b9fcbd13f7904feee87b45193de016013f964d9385bb6dbd08a172f53f66ea27912b0d29ee8ad095ba40da69265014c9f983e8f02e1fcbefabf2311a5430b1a747dea74ba1f6b4e72f7010001	\\x0f2dba9b5ab9925bb1217ade6be7a436808adcb6c3cdff4f7281ed565af437e0b3ef41109e0b53be82808b7ef7705c9c5c90dca20a1a41a9f4a63055ba65f80d	1665056591000000	1665661391000000	1728733391000000	1823341391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xec757fc5eabbce850345a8ad983b397296d71528469166d10973d16e5e79876a96225190e3f9dc20f028052112742869fbc9a4dc1d280e8baaf8ff370f61a909	1	0	\\x000000010000000000800003e8645a927edc2c477eb46a515b29999b51ae0970da510af129178544dfdf8f41b0a9b925a4544ccf55986a9ea65c93da0e311c1a1a26c5461f948567094b5c25eff6db7a8866dae8c0308e71e9c3a004fec00c30af974513c5202fb24ce9ce94b4c7f89e5309fb1ce712d2078c3365fb0010431c5f18d9e6c105ef4ed4f5accd010001	\\xee8371adbd5170edeb074e82faf25c80ba687044e551cd9651f1d4d88eb0dd024aa518b9783111573a9d8b3afcb7abb6de141a25d24bc88d9c2241a6f5d90007	1670497091000000	1671101891000000	1734173891000000	1828781891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xed49fa2b58f8494f8b5d2c49342ced94b78923ee2f9ff2891bf048dea1fe9c0d940d4589bcf2ff84dcad0c4fd05f22e464b9164207d6b2cbb0c4645d2f89e8f5	1	0	\\x000000010000000000800003cdf1cc4f983d00fa6d6560d458294b5cfb52d9804f548129d14098a46e939acc68d9fa6972c9892c8a5263ab4312b2d574e579972fb769695aa47976b42375a015e2755bf928f1d1fa3f1d806361895f35be8081e5bf8cc1d83bf97877eb1ee5ca238afa964d65d11c0eba7290273b41ecfb538bf9479670bf473a3c4d58eec7010001	\\x68988bcec9154829aa0b98e39582e011926149f771effde4cbf24b423d847aab13adcc9e1f2d51071b58d17c2678fd3eca43117031e80843146617f081b75001	1668683591000000	1669288391000000	1732360391000000	1826968391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
191	\\xef3d26600fb3185f4e9071a28269e70089ee74781845b970a71ad0ff8f79e285c2158d146afc0b382c2d988d774f4670381403916f2d73588fbc54ed8becb121	1	0	\\x000000010000000000800003c5f5358046b0e7e3db90aa86cbc768f9ce21f299fcdc40c3eea1a618585588a06ac49896800d6511520e0a12f5c67e9ee780ac80526a09ecd06a633806c8911af7bb2f793c48d9e9b1819677baaea00fd0c750e6734dd7de9b4b27602895e4712793fc0afc80a7200948888c72c26376e9fa870510b9c6ae965970b5f74f114b010001	\\x0ddac9047219282fc5500ce3a4b3a8d8bad78ce451ad8f3ea63ed45a859b2dd440829ef8b7fa97a7dc99c23d56a723e189b04f001f2c60c6e0765998aa47a008	1663243091000000	1663847891000000	1726919891000000	1821527891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xf169d2c3117bea47bdba34f43b6daba2c8c84618b04ff8ffd56cd309cc26751aa18c01fcb89023c957437a9222e27f00783e11317630694fd7c4838cd099b24a	1	0	\\x000000010000000000800003a1b2f16f1f07214849deec0f964adf2b404774475db998c4c2b0d73551ad624c1039f8caecbe792bf7d038b466685d05ed83690eafe8c732b8fbf6a49277ca074767576b629c339c81665559594a56faa4e68727c394294153ff87adb2cacee95666f540252dd49ee120c5069a56df522a4a0995ac77e43339872477b044c93b010001	\\x70eaa6f6273c5f7fd22103335a291d99e7eca04b8cb0638a6ef2d7aee85122e97bed18ab2985fe3ba65f9bcecb9d841fdf46a505b58b08bd0899ab0d76823e02	1654175591000000	1654780391000000	1717852391000000	1812460391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xf6f932cd06e2bc6bb980a920281b242bfff902bd233c8ac42f3a1bcdc4829e243b969832f17cd3a7bf2788969ed3e62b19801d43f126d2cbd10da7e1332e5443	1	0	\\x000000010000000000800003d1e133da8e124744448dea80a4c427ac3439eac43e5364cf7c55dc14131f4e617a8ca3e614cfe2545a71d513869d357162d97ccfedc231345bc68a895a79508b9d7adaac46985c1dd21fec5ef71cff9e7a711ee03dfa219ce6669e6a2303ddd06801dad36d52140bfd54fb96780accda1d28d19ac8917c9326f46da67317229b010001	\\x392d5d6fa1b171591bbfc51d576a7ae8039153e088e01e5d74f94f14200f9e0e52a47358297004d9026cf2a6d0811c4227557580c9e8ca6fae669f0ad783c50a	1660825091000000	1661429891000000	1724501891000000	1819109891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xf88143515cfe7557584230c1d5d4257dabcf71fa42bb31c074b2bfbf69d137da1bcc966300850422f5d1c86963e8252cec06c4447f07f4309c7db446d617bb7e	1	0	\\x000000010000000000800003da21894375fd4894ca6fbdf7e74f0e034336e12b004264fdee0ba510c8991106c49337f7e115e6f5f0129a7c2111c99e69fdbb26e0e8bfd7a517eb4885e654634af6d57e46f9f0941eb2c6abb85a33f8e6ccb95e02ed3fe283360c2bcfe570d286fcd537a3e97a6fecbbc28b35c070ab3b9010788933e4021deae864842f7dbd010001	\\xdc1650a5c0514924118a967d49a3ddd80fae6e2c89d95a892158680904989cf9f5d1f6cbe43dcab1541c51784f36f89fb2a08035a159157828baafe017e62203	1672915091000000	1673519891000000	1736591891000000	1831199891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xf9b54e5a8ba15f71695df89914c5e6ce062c494543bed340951f87b246991e8a19f0fd9d93547e6ace2b566d30ee0c2023347b846963f9bf9eca8f016435117e	1	0	\\x000000010000000000800003eadce7f2f6c9cab450e7ab7bbcfb6309299305fd8278d1341e58be61b6a45efdbdd19f47e01a2860ded2e95ab6ba92cdf3e018a042b1427301f50be6713937f51fd1cb2a49e608f0931bfc2564f6221c18777e488f31012a43753e8590aaf4ce891a89eae810156ae1193bef098d573159562e55c187647b8934f81a95afdf4f010001	\\x745284d7b7ba6c9d0a61181861143995ad58afc6df9e4e4d8a2e0d6d50f49e2e7e3fce55a07da5895e56d1faac33a669cf0b6093c8d54049aba6322bfc63f701	1661429591000000	1662034391000000	1725106391000000	1819714391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
196	\\xfab9a2ba79a48c201ab2392863fd1d86575e13539aeebbf576282d1b9a1cd2b0e9eb27fac388ab8d78f7c0125ee56ecbbc1d6c088eb8f2b63a8a9a6eae29f0e8	1	0	\\x000000010000000000800003ccf3bcc9d6511607b18f148496088831cf0523879412a60ed88c524db2deb89dc124f51417d56f3857c2681de0aff55e54ff7a832e4d99c4c85142a735df2093cda7af805e0ea02557193cf7513ed44dc267227eb99664a18cbecc7787b0b9e5f64d7190f5891fd6d6cf6ebe8ee8e22a87d38731ff5b979bcddfad0b841a26c7010001	\\xc1883216f3f078bbcc9961e657191e159a088d8ecdd15b4f76c64febb9a438aab5852183a6379eaf6123ce1fb340a2b5d21534fd9c8e331512d91f1b8132ea04	1650548591000000	1651153391000000	1714225391000000	1808833391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
197	\\xfbc167b7ea0c47db7dacf1e91a33e6085e0f856f0321a000d18aa92800f00d5cc70acefe1746dec6c6bec668c016a34552e7f134454a1c60f9e83b29da743381	1	0	\\x000000010000000000800003cda018d32d460edd1a40025836ee8f684e2e6801bf41980583e849799bfccc667d107861573aba61293e2b0765b7215b91ace75de42dc95675d6818bfd046991df3653528dced1eb3fbd45623a0704fd21ad93d07e61ec5dc3cf4c546dcb64d9e371c4b4d481182bbfa762260252a05ffc8cdeb570334147a9af4c3cf0ef3fd3010001	\\x7e2295e93b20ca0fef54a300f95d8d3d18fa41a9c34a277b3e6137d01172147bdfa6b071da8ec5b44e8debdb6fb9c4ad016be323b0d4d09cef3162d20d90b90a	1678960091000000	1679564891000000	1742636891000000	1837244891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\xfbddd8869c5df1c1cd25f52697b30c4099ab5c55acd5a76d70f9a34eb1ee7ed6b0549b455e33d002c32798ed65cbb805716a312fd4586942b4519b2cadee718b	1	0	\\x000000010000000000800003a064c2dcc27762264818a439ff54a2d8ed3fc99d461a57fc09347375e68d337e480cac747bb74f58c1ed9d6ede14734c0248a9b6b1ac6acb4cd5099766d57dcf3fd65f7ba78e842de0e021b33629459f49145ca1371c21f3c1c7ed43f65407d9466abbdb12fd659993ecbcbbb71f4e6a3e30d38266fcf1040bb06f28e3eb60fb010001	\\x55a4945b4cd429267c9308f352e8a65cc9cc83b2ce6804770a6efc39ac5c627c3c85e15bad8edb4459a14cb5e26e4b8a2fb4de3dd025a993b9275b48c24a5005	1661429591000000	1662034391000000	1725106391000000	1819714391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
199	\\x00f296eacac351880c6663e145b88ed2d52e6f84c693f091b998bdf277c7d9e15869762215522fa2d2f627b99bf8fde8c5e26c4dd3a5e179ee94ec40b8e340a4	1	0	\\x000000010000000000800003f9b5e0a2d372e1fd0d4090602164c46776e529ff597c39570bf315f7157b02f44e6ccb25f2529dca97d5e0a030d7a38a854b2c8e0174855922f5c6313d766297e366a3fa23177f0bf059a35c51777ccb6e3431231c51edd54407092a29641d124134295254f4a23e0f7eca146c4f5fe177f4f0844f17aab7faa0e12c1ebf3a5b010001	\\x5a6e2f9ea287f89f975a929f2d5336c21ec1649fd273718f5b24529a29af4e368f703b1c9073473f27a6dee06b33b554514b28a56bf5f2c38c3244df38b35001	1657198091000000	1657802891000000	1720874891000000	1815482891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
200	\\x013ee21082973ab58f55bc9cfc94291aa4f2699fee85cc79dc8a613ad9d6bfb88f6cdfcb6855d7a316cfa21e041de3a16db2675adb4502fce0dd6bfa99cb8aad	1	0	\\x000000010000000000800003f55a84287e8b4f2340e733bde13fe22daab7c2977262d1062b931593eeec723d21362f51efa653f5709839ecd4a08ba7b770b21750cfda39040e63ed3b21c3f915aba91f7457a94a714c55ce2a0cc9b0440494b3c8fda74bd351b43a2512c022eddd5a5fc01625653369707b57d7c065622fbbe3730857f59018791d2a2a9367010001	\\x2771feb23143edabdde12eb4f96878b73b2f930ff752465f278ee1e33ba50cff75ff4b7314bfe585a91b59d7adaeab903732a6ffbbb852b2755164bacd645306	1655989091000000	1656593891000000	1719665891000000	1814273891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
201	\\x01b2ce80a6b49104b5c615107de521ca1b9da5b74cdf150f4f025598fa02168a5630da854d2d8e18887047cccd358c84a625b0c11e3f805c785d2f3a243c0a55	1	0	\\x0000000100000000008000039b3fe9810744a3d98b1799eac7f7263606b7a0c0ffc8beb5bbde1bfdca5e8587e7898bda0a756c38f5ad12469b8a8ea7340c7f3ffd7823a294b3c4b8dda642441eb40a5e54d8f27cac16b8cdc2e5e9943f7be4028f20cec47cf103f3f1dc872c1be264aaca34c8c89ed07deb740d51c2b1721081a1636c166cfebe8005f2d5b3010001	\\xb131c5c63c05b2de9f4b8270c03c9117256d461f030893fb181f7426ee2a06b6ec41ea5b1f8234952b4bf2c5845bd4807071fc49855229b20778519ff1084407	1647526091000000	1648130891000000	1711202891000000	1805810891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\x03d6a78e7d6f0ed554af501f8907f9fb9edfc62a9c58ef94480f26f154ab3198cd1943be685e4df3501900c1bf3d8ec1754a64ba9a44d7bf8e9d3ad2ceb466d8	1	0	\\x000000010000000000800003bff5c1cfc9f65ec57a1a33ae411dc4a737bc6cd7d1a47032b406aef50417a435faed7857eec60f824592d21619a4d7fe5d8a9bf1d2b83dce645f5e8edd51734c625565835ebf26603212ee0a1d9c99dbaf5727ac8ab947b20beed2fb73bf02882b594b726a5fab8d0b82d312b69de95b793e9a48872af5e07c4f1257444035f1010001	\\xc1a3c3811c0b2489664180c2683dc1004958fad3d13c405f42edd868468ac37341bd8656fb4bdd3c22b98cec96b999245e3f2685020fa5d6e4d136099d140d0a	1654175591000000	1654780391000000	1717852391000000	1812460391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\x084e6f702d25f8ec750c75eb3c6c7f403304ed313f7d44912eb2c0b58abf15009ad5da9244af71e90b90bd30c79a308389d2537d6b12d3533dcbc28311b7a6fa	1	0	\\x000000010000000000800003f54b71f65b7806f37affb619fc8a5095bfd62e86c44e5706772b4d2afeb0ddd1856e87266e883cbb8ae3b8151eb1a8edd4f7ef876647ce3fadf1a47892cc6988d54fa26d14a7b985b9c0b3fdcd6d119aa6ccd34b1f5db693ff25b147b9cb881dfbca5d8d6cd062543004c7000e61136f6efb688cf11ea8e620be65b6d905e065010001	\\x5563b54854755e883c77c33e93b23151ea82f4df04d49ec57b8c52d508200e73f68d5b0f1cdab07c5f2b8a773991afaed4fe8afad7475e1af6e65daf89ce4406	1653571091000000	1654175891000000	1717247891000000	1811855891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
204	\\x0b26e92079f19c1257b93c881370ff8be45b5a0275d3f6c4805ea477a4a738fcea850c7d49b40adc8c3b43c7a4e007e83be0fd31f37ec17c19870f31ea8ddc06	1	0	\\x000000010000000000800003dd76145128ac454a9e51b763b00195c5401ab599aa6200f5ec22139e88a9808da9a8bce50be927e09e8e70249b4173cb67f3f7a93818e34a109fef539fceaeac7538f589bbd8a1a2bbda558610fe6fbef1d160f1ac14687df6f2d354f12ac18f83172c0bf25037b39b04f01b338095e066adea2775e9e5746d0f3e28d6925127010001	\\x73e7c638655e4b48d72b7b400d421d01298f5f691c49fde196237b51978dd83cffaf287ebe58167724b7bbd79a40a7b27632e7de4ab989488ead12cce683bf0c	1665056591000000	1665661391000000	1728733391000000	1823341391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
205	\\x0d565f7622d2c352433c256f718c236ff68f0aa0ade0e4ed8d631af0aa4a25c8ae781a155c373dfd3047f54d366da1209b5d688b368e1a7c6be8db75002915fc	1	0	\\x000000010000000000800003a382e8d46870ceba353e3a7562e3436fa73df527d68aa0e5fe973fab699addca89222e47cc426cce61310e35b2329ad645d9c86e39cd35f1f38c598d9d78ef2bc6f77136fe495e16ce9fbe1c79ea320a7683db57b21b35a4454444fe8454fe3efb6221a9c76124f8aa01e7413ea52f3ab983aa31e4453176cbfcd305ce594ddd010001	\\x863ee4a839d29b4c0a028820b3a9709575435d24f61d77aeec6d79608a650d0a1d77888d5133252f0ab10c7397d7282007021b20d18ac64f0f46433f67fb1d00	1671101591000000	1671706391000000	1734778391000000	1829386391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
206	\\x0f92a0a953c29273bba580ef1dee82aee5f068a56384ab631861db45768b9ffd675a1f97cd8e98229d71aa975859b66b2cf1bbba10ac22fc316256a00f0a043c	1	0	\\x000000010000000000800003cdc98ff04b389a60e4df099f3e30b5fe111f0b1cb6377b5bf18b2a4c4ffbef81b457132082320afaa4d06532fd41208fd6602ea5a7d9e0a97284fd4f555bd23006603672b17913bcfefcbd2097f217f2aee5e43baaafd85e195992e67a898f6ce3b5ce203fb3017a39edfb6f8a9c59a7f68cc2776b7e3ba134d438269104a9ab010001	\\x7eaa940d5f6d4b3e9bf49fd5bf14608d912df8d63735220ef6687f46fe79d059d83e391c643327132b3a68befb4f9cb384a5886f8668928ea52f3d2d4f012f0a	1666870091000000	1667474891000000	1730546891000000	1825154891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
207	\\x132611ff6703e08b34ffbc4175a2bc70e10077fe499189d0c77389dbc532a0a562acfa31ac2ef13a723367c9e667f1601d4d21d584f783acff0da91b3e5e14dd	1	0	\\x000000010000000000800003ae2190d6e216fc4e0ca07ef963f75bceaf739b39a3b0a3c7e6fbad517d49f23dfbeb5a01474e86641b6054505035ea96c4680120fa9fd46f2e15f67a1b147fdf06f71911a0f4a0d25950d87093d95c1f777067de7a2d08f32e3e434dc9c8d33e918faec6f07cba83a72769ad88c4a764865f50fe306e7ee153ed07a174eb1829010001	\\xaaede1957cdcf071a93a03bd2f0d80c792b2814795d6db1609c997db85713c8bf66a5389914a9015372c2e07c740b50b5a623393ccb33477ebb47e1f7297740d	1661429591000000	1662034391000000	1725106391000000	1819714391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
208	\\x15a68c6b92e810b2de1caf6d04603045d27a86e042481bb485895d40f7a76f804d7d20d09806bfed7f8b719b7bb771e0b422980041dc5ab6b01c803cfba11901	1	0	\\x000000010000000000800003c33e2d0719e2d6d343cf33d9071ac954a7fa7063c3ceac1ce1404ebe26cc401a739a7710e4f238d6f95a5ebb99fb2cd1c8c84413fc3e992ee264a8d395e1a183dd9021026c95f1c0203259e8ce2818ad91bc2b7c4d45690b5860ce84b7f830c8a42fe03d87d28c235ffb485cd3342645412ed978b72163fdc3ca553f0b2708e1010001	\\xb4a6e062918bcad173bdac8ae51b77945c9a6e32692c75e6e2518bd791582cd7cfcf368a8764e8b2e14356ed2d16b8f3ccd1294bb896abad222537a1c4794409	1648735091000000	1649339891000000	1712411891000000	1807019891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
209	\\x1642498ac99383755b9dad71a0bcc35f67b78797dbf5450a2d61b8891d74260e43f0a4b725f341b578a9ac99ff798d85b450fdd28377025c71fa52d198648512	1	0	\\x000000010000000000800003c0ab96e7a42dc61d56770e6938352826eaf75bfdf2345da79968a2dd14e7dbfd3b52b63ec0065181943c48ebae63bb8cf72777c4223da5581d6d8c3eee3d0485d0a66bf42043b053b219b610b9e7fb388a1ac4b2d272a3a8d71ca4b13e17c467907e65b49c503258a38918b993811364a09ce92cfbe3e1abca8515f95a637b9b010001	\\x1999b351bc435c6539d05e4b3f4c37e4928b34c82711fc96391fc5c291149ae7e8bd363b097b081bf7ae2d99db9a0ed3898c154dfbd3bdcefe2d628483088c04	1665661091000000	1666265891000000	1729337891000000	1823945891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
210	\\x18365cd50a00a48155bba7153f00e61a8c46318f8d21fd36585244406f39d9b00bac3ba2cf17edfbd5fd68f00b4f7d5989daee3ddac4fc4817f88afa4892840f	1	0	\\x000000010000000000800003cb28cec3eaf39ea3c67efe1833d2dadb6044ebd6d676269089cd1aaad9bc266aa8b802a0102902d9f7eac4907eb171aa2d8b0639037c8d323777663f8f5678a0b908259ba99fd38cb89d144e826ff63272921eb2af0d46dc350bb2508fd815d2e848bd13b48fa42ac300101dabedbd702409a7383d62f786ed1ccc967c1fd1b5010001	\\x51136d16451ca015ab1848273870b19dd12205341452d188e8f8d8de3a75fa0341643e2db64d0fa90c4321c06135635609a708b99f34a7b1a89473d3ef363909	1675937591000000	1676542391000000	1739614391000000	1834222391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
211	\\x21021cefa23f1110cdf3f4cc7c2217a5fc754bc507f3b3a94914300f10ad97772a71b4da5914c17948054ae3d618aa86dab7e732b1b34ee9beade8fddd4c0d5b	1	0	\\x000000010000000000800003a3f1fcba275cb3bd5b03880f5b702456d56295cd9075958c2699f21dd15893a099e6d02391f3cfd7cc46490100ffdfdeed8194597ab6b24d129a14e5d68005efae42d1ecf5e4de992f2713423cb273a921c784e037aeea08323efe2a6ed5d5a682fb0ee374365c53dbda71b7c7e7a3e29d87236feaa42144998c0df1c706c6cb010001	\\xb06202297bf1a3f7416f3011d02ebde67263f87e8ea3a7f628b7856216cb9ecd0c6ac049d5f74b561d8f3d550302f9fdd3786299026a730dc78ed1a7e2cc8d00	1655989091000000	1656593891000000	1719665891000000	1814273891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
212	\\x23aafb8e7dd3307ca07a2ec591dfe32d46e4dbe356f3fa796b8188f97ce01fbe525635ec31bf421853f7f13f96cbd0cbaac3710d41a0ea6afec0b9b6b083ba8d	1	0	\\x000000010000000000800003c6ca83f1d01a09502be37041d99a1d3b1720bf50c37268a8e95c862c94fe699621c58bfad80918a2a4ec6a333f6b7be92ecc5c2fe99b486530af739ca9b753cd47dcd6a935ca8009d4c4ab19ab4228e2ab692236da9a2eff5825e6bfdff78dea1a7527abac0f479666abb29d2e97fe14b7c037a74fe874f1dd2bef95f510419b010001	\\x9d087256bbe375481aeef5138ad3591d72913486e6e69007da1e49fd8153b7923e2feed0b766d8433cd010e224a372f3d9f26e8191af3c4482c490ef3993d902	1664452091000000	1665056891000000	1728128891000000	1822736891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\x24aa0a37fdd68bcb657823a81408b2a1a41825c7deb2a583a99b64329a7a22f95db0fddf674ba9b31450b493bb79a2e15bf1ab21d73d6c4780ebe91d7d3a19ae	1	0	\\x000000010000000000800003cf6c153632e0b82b542ca7134df3003e73184a9ca2b889a27de5305b81f2f5c49969bc891432267959af6be7370296fe89d9a8786b3802f024d4e6fd3f74667bbd48428212ff10257953c0f37d994aef59aa969ff443c04ab905beac6dc9e6f00d2f4b18db7924430a836478408a2233393d36f56dc38571760065285da4304f010001	\\x442dfbd67a7272a7eb40456d910a4fbfcd9e4a78962737f6cefe34656294a30dfea64152af3d5ef14950f880ed8d677853b4de8a8b202d3e56450db5bd2e8c0d	1655384591000000	1655989391000000	1719061391000000	1813669391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\x26ce70e02adf4d10e01aed7c6cb4cd1ede8b8550a8fcfa1c3b9e70440f97f261caeef112f54377564a6874a6024a17571406d12e1e92ccf5894c800d7735ba37	1	0	\\x000000010000000000800003c3a370af32f3491406d38fa18aabf3013087c9f65d01574ed15a605fa2e88981c98d8d7e35738442bc8cd1325b9e56474a8fe116174512ef3d71681ab69ac98dbf8c6429aa20d5cef85a2dba65395120e36862ec78fa46dcdbc2ccd1fa51c6805a252219a5a9d9512b14783d6ea46b0cd1c4049a33844644c256a0fd5c01931b010001	\\x3670c69a3a6f1bdbd34f96daa70988f5a600040cf982af421bc1ab47a983f458ec5a921b447224e3aaf5f50057b5e948b0683b037059ea729f11ef68c261f502	1655384591000000	1655989391000000	1719061391000000	1813669391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\x2662e792b2d8a11236d0194ad7360f9bf3594282e80f76b0d1fd30472d692d0514932ee0011431221dfdf4860f8b4aa2b1810770c8862804b649837e070cd87b	1	0	\\x000000010000000000800003b26ef26e83df0d177cdd847e6ec403fd87c797b4da30e8c4d82b737cd7b06a5bd69c17bebcc8a62ccde315009c39c38276ad9d0f68f5c0a3225d71b17bd8b9b2e6324dc60a5e8b5a84a369057bbf35d658f61a6d6c6ced495d175377fa37eb29c48a0cdf85522adfe0b0a3304c75e1f4fcf85b3674c9eb0630a58e6925b334bd010001	\\xf1b6a687b93fd50c445fbaf4f3a2a94ee6b23a5d6695fda2541f6f9dd6d4431085703caa16c807b27d1d4292af6c30e87849227b938bef04d63b3eb36283420e	1648735091000000	1649339891000000	1712411891000000	1807019891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
216	\\x2bf276b928011726967961ee1aadee58ceb76c793a5b6af90dc2cde57e0cea77c19582e6bba51f69a4306adce4fdf9b74936f84894569bc54272c478b6f74ec0	1	0	\\x000000010000000000800003d369a3dea5901fae0131d929291ca4cab17487fa76f2b922ba7d70f71ef6f3f3a9fb93cda44f5dfc1b71ea96e0eeebe4ffc1986899af75d04db3e52fd8d5b574c7b14436d8bcf3ba60c47aa676e6e2fc21ebb3cd3287eee30d8b2f2f7ffdf94607c23f2a24a36276fe3c19282a474af7ebae0af76c79afa40610a5ee5c5760eb010001	\\xe9cbc0ed276ae88c557c3bcbe3beffd40bf04630c711a6fc96fe79259d42ab0df11c0107bba88b6488dce5521557858c7f42f6fb5f5bbe988ba70e0dd3dbf003	1652362091000000	1652966891000000	1716038891000000	1810646891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x2e161d5befd4f470ab4887a33619c11f3f694b9c2700de22b40082e58c02f466267b35795de4e9f13e9d4960652ad77851fbf03ac52d6ad48ace6d32a51b797b	1	0	\\x000000010000000000800003bb91a0e0faae3f85f312460727e06bd9e5bcf47cfd87dd907010327af0238654b42f6bbb3a7734d26c0f0a2320e4a50c8e98db24025bb6466b7a143fa10f5431306cd9e5902d13dfffae0c15ce51c810b390cee4d08ab8fcf1dae44e03795150437695337b52793759c0c57dc8a00eecaa3a4816534e8ac53aee2d7d30e7de9b010001	\\xe4bd99e8b0cec7a252f1a5fc8b3229ede341e64b1cf23704bc846d6acf3f28d4a109dce7c2b2eec1d20b291138d3892ec860eecf99ab25ee42f1b9442943e40a	1668079091000000	1668683891000000	1731755891000000	1826363891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
218	\\x2eba027bbb88bc6f838d215f22e2776d944693900598e2de9db2e1dfc193ba95416796c6cc338d6176f320209c02cc50217ab67a3570f4fdf49a569de91d69f3	1	0	\\x000000010000000000800003bd43f61502f31feb3047c7e9da866b5c8d10f8dd4cd660bf6ce60847097b6fa379ffce40e911b90ab7479d5cf6c612fc506f74b2569d0bc386ca4ba83a698be2c1a8a00ccc443fcbc1b37f0eee7a851ec19b6f7840208edc72c0b73f3af13c16f7387ffbb69fe62601cb26a9b084b8a77cf3c15c77ceea72b9d83c27783ce7df010001	\\x6f9ea092a92b3b07e2cc32f975d25e0efd458fb28b4512b08efc56d532af57c2e97cef937e23a45ed2510acfa0a09cd4634434613ccf860fdf42feed2845a70f	1649944091000000	1650548891000000	1713620891000000	1808228891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
219	\\x37661f4f8c517808ce1662e63042babe30a99ce2687cb63a8b19a03fbb9f32e944dfebc9891ac6e6a6744c70f888112317feb2f22f65c27ecc7363d0fde71038	1	0	\\x000000010000000000800003b6f767a7e5b950d2aa374bfcdf1de6af3ebd2cdd91f2534bc131dc390108c1697d7bd0e5399ca95f893fe1bf91f5ee61ddba37446b442441e0d3287379a78ae11926aa8abea1f0bd7ff3b54f855327a13ef00512d95fcd5001f5fbbf7ced7bbebd4f7500ee7124ca161ba63ce74d2bf8f29654c0ca1f84ad778ccd8b22a9d865010001	\\x540ec504a7a6a988a100c93a82e30be1962757ef7edc28e53fb8c72c423991a88b4b17af52f1892729f0fa916a2164c85cd9e6a7ecaed98ee7e23670b068b504	1669288091000000	1669892891000000	1732964891000000	1827572891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
220	\\x37d29d96657b26832ae6e22e13c6d3f85134b66c3cc9d77d9861d0bc2ececb4964ec2b73f69b642328cc19870f01b71c297f36c0ec7f4b00483aefa259023257	1	0	\\x000000010000000000800003d5dc8e22c33251e881723e764a1d67385131a8ed3809895eb875d9f49918336b2c8d6adeb3107f53f09c7593e09cfccf2bba89515bc430c3d1c19d27aeef6479157d5b3a8dc583405bfce6c48ff9eedae702477f287732a7a41159ca0c7f199862c88f270b2f63bf8466e8145c2379a2de2f567d71b48055845330c13eaaabfd010001	\\xccd7f08bde48d77b8b002c306baca0ac1bdae63d99cb8d7c6c2bfdc8fe64cdc3148d54ad984869ce06f1ae59e207a51c081ffcdba32e32f6ddae71c2782b490d	1647526091000000	1648130891000000	1711202891000000	1805810891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
221	\\x3c1a29c0306f6de6386606f15fcce229ef4ce8cfc8fb12184eaa3035868a81e429ca66c854774d3a5ce7904347d88b850e6c5d7c5212bb3215be7b24638a814d	1	0	\\x000000010000000000800003d7b41ed9c6e6416ee8816137647fc06b0402f177edbd2594b9c7af2b013faa3e4273b477525fbe18982fc1be16cf052383038f4aa175174ed3debd73baa1291e4f30392f3f06c60cbfb3d878c651f548d311e1bcb9e2b4f63420fb141b6ff6b31be8109a0a04d3d4dba03894a7ea1e30869148936bf3000e796500b17a9cf2e9010001	\\xd5529e67d22e713fcca2abd8075a5342d22863d19a34fd8b34e61fca3c586baa63e9cf6891a7ff12901de49f1df8f182fe803254fd3f778c52d788c926b1430a	1675333091000000	1675937891000000	1739009891000000	1833617891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x43ba7a4e7b91695571d0a1d1ced20e2a1c636e71b5049641e9bbcf0a74d9fc32c7c5f336816b0cce7e20df12e19b805d97b4bcbef49ae1dcce904327abafdc61	1	0	\\x000000010000000000800003c0312fc5dceaeff2c7f582165adeb1ef4dfcda56ab8d7cc96338f4c1a8dda0c63d1eb909ee3896d511c26cb398a79cedbdf8dd069cac0c4df1d29e400c9d97e56446ba0146c2ea58b870d71a2ad5a9729dd83548da4437d8bf5684e4d1e5b26834aa9327204bf4cb6484dd9f8f29f5634886c44c1a6b7654c6a9b8d518748ec1010001	\\xcd72feb65544cf1889f5f99e7f883385d0311c553f119e2df0131daa161b52183e56187438805b58ac40066bdadf4f98673f9b5694fe627b5b5c900a2260580b	1676542091000000	1677146891000000	1740218891000000	1834826891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x46b28ba727cdd2200e1de38678cb202d04ff3c6abdabcd3b4cebd467bcd72d54a609dd1010404deb7ddd6dd2bc9b14dbc35188934c979849a317380f4eaa4426	1	0	\\x000000010000000000800003cad5c670911ff90d1c5468e572d980e221ba9990a496501f5f222909f7c2d85bf6e9e65e167459b3d92bcdd42ac53334ba50490791a787b5cf0f0abb628d4f25aaf801330e60a5cb65fd847b5c075582be8031ecb92ab603e43eadac9af4a06231bc53efa8dc2de0edcd15c31ffc0d618a038b8629424f2506bc4cd37adb927f010001	\\xbb9c9d9f717ab04bc3ac1edae8840b932a4f7e3d8b6972a9ffb96f7702f711b078cdda3b029ec791c70a22864463bcddc13e527d817ed2964821c72afb62b304	1663243091000000	1663847891000000	1726919891000000	1821527891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x48b24aedc042a206e87296a3c707b72b20b6af52ed6827e5250a22b11dcba64b160ef39bdfe56e650b3aa861484ac651db4ecd3b795a39abfc3a3a8b349077a7	1	0	\\x000000010000000000800003b77308f8b7c68811b87bcb001b3ab48d86f1b375f59ef0b8d2292d46c8c643d68ca5bae32141e58c11f63afe9255797c5d7ca5fbb2caae81e709aba28d27ea47fe2f3dd983a9c0b505d960f25c92c836ef858ecbfe2ec72001182ca7130ae5ab9102fb9040c50182d3227a002cd5ef486869220014e19fbd2db8cea59b90e6cd010001	\\xb5ab73f3a2057e4ec294ba72c072cdb0de246edb0babf89fd0cf3e79a80173b061fb15c5fae2dec3bc26ea8c23b4f592d8534bad3a339e81a393c1add4d16c01	1658407091000000	1659011891000000	1722083891000000	1816691891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x482e226538b9a9fade649e95e0447795a55de41b4630b75187efab4b8b2ddf0c8bae58697fe28e19d5a8d5e807a5e9ef5b8a7507e2d79efdfecebe7a0beae16d	1	0	\\x000000010000000000800003cfab5b6857c0cc3fd5ebf5f8be318597e8366caa62e7878140830c1042709d5f7958178254eac9f1b8eb4c8985622c0ac7ee62246707883610b919f154104d9f542e66a1d238f37fd89ba211a0983c82bfbe208037e0c1e366d2a07d5405290260d676959b03d6990298af7aed89e93e8cdd465bb0edf14be501943888c164f1010001	\\xd6277cb526f1dba01517786d8d43f51acdf11df44b3d8c198a3e9dfbd3512e3fd3ccc161a96e56d50a5a2787672c17cde6f5eae4f8011a4e35dd5343e2cfb00a	1659616091000000	1660220891000000	1723292891000000	1817900891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x4b9a02c4049bf76f6115832771d88e3bf9190d2d930fe79e6348a99981fc6898c844dcaaf65178afa6eed0c7932b880433f8300defd90fd6cc58dfe9ed95909b	1	0	\\x000000010000000000800003efcb74358fb0ddf1a19627ceacc847aa55e1135ef9a5cb8c074e2e209635447039c713850acb61cca6fabb4798661133095a5b7656c7fa043af8070f0a8705206da4f731a0ffc8040bc70a3616772aef7ff59aafb3062ff245b4f16b6b0922c0620af36b0b3cf72bb8ab3fc49d1d8c00f7298077a3383d145d71d2f9579d7a63010001	\\x602ffa43ca15e0f8cf2a8f3d709af72d18d97a4cbfab891b71756d0f6f988ce73fa1cf0647daf1c0b2043961cf05831346c718ac74222dded9302e2552ec4e0b	1674124091000000	1674728891000000	1737800891000000	1832408891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x4e66a1053dabdcb1301a8303ec7fe4fd84ee840a5375b4bd16cc1906b75d865a05c8632d5c0eafa37793461d2130732c377547d6a6aa7c2cb99f02f0bd38eef3	1	0	\\x000000010000000000800003c424ea1ea5d5854e7076bd355592abb6704d942fe42e91e861eae9d7e8da33ccebb470ff8df50a54f766f1a6310fac96e41f28ba286896e5865bd017f3ebc846a70626e5c2ecb11990b74262a4c372665959261dd2d099ad1d36de1e01b7132ecea5a5c21668b0f80892c10911c066df0b461773cf311d5bd198cfea86477b07010001	\\x4db942b49102a5e93d011afec87d887bb627b367c02a72f4fcf51bf75821676b5b02674a8c7a82ba3a01c6d05909790ac84d4d40186f64cd9cd04b360c6b4901	1674124091000000	1674728891000000	1737800891000000	1832408891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x5096c40cacffa3c4774eb516af7fd905e5dfe21f1b0831ae1e066b4ba311277758d971826ffc86333f9c642bc402db8007510da6b58b72439dccd2f167ecbb5d	1	0	\\x000000010000000000800003a69d16e269774b2e1a7661124d1109bf11930163598691a67cd8ba508cf97c17458eae6ec647964be4fefbcf7f673dd710d5b0951ff29e3d638d0688c475630f84a634449be2216f4c36d2bb7bb19b36e63526c575df42e238cc25fa357fbe9fec963a62329939d29a2e1c702bda8643ff7cd150998da262a400486a368cb0d9010001	\\x6526507df5db6deb51cb944d9bb4727853b1de0856147cd010124f3550238b3a296b9ac76ce33556c85f72eb6604931b9ea7bfda15421299d1a4b1713786640c	1674124091000000	1674728891000000	1737800891000000	1832408891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x53b6d42525833ca9c547a769466e885b36b03b5a2e87d32635317da2229e15accbf749cc30aeb03c783563dcbab3e65db8ea3e823c20467f6076eec68b317f40	1	0	\\x000000010000000000800003d440e95d84e65b9f244d001144c44cf71bd7b172e86d3f2ae21d0cb61f3ef110001b030733605ae280692d99146d0a6094d65cce02453226235d789c939970c967ff517f03713f99a707f7b28020aad5731808ecbd3d9d362df55bd6f931d9bc7244a50167a4a614eb838418cce261d923dea9e3ef2c38a0052b1356793e3751010001	\\x9fac4c7799f9e634125870bf2fb4d05b8fcb6fe3349faa6c28c04e89137a5263ef18f9b20ebe70108e6273d39f15ec14d52f332066321305c1a8e124eb2a7605	1667474591000000	1668079391000000	1731151391000000	1825759391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
230	\\x537e6cb8161d4b9bd4816513db4fb55409c3719e3edd675e62caf1d2ea7535d0eab2e0774e7fc84e65d5bc8f02c4a461845fac8a35a68f99cc92e13f67986926	1	0	\\x000000010000000000800003d3f991cbfb861cf5160c61b2237049cc51e5fc3550fb81f0417fc2700104c310db759d37d27725b3c612b49b9b0745782fad6ad20092b8faf4aabbb1ff26db6975eaea607d2288b28a97f8594401a9a4d7d7336049fe70b9d7caeb706a60644d865e2a7bfa6c841d28fac20d069f639a2109c2c60b57802bcea9c92e52588bfb010001	\\x1901d58fe0dbd93b047556b42381b790faba571c0e082d54ff28c8d5dc09b2cdf26f7fc1b546dd6b28bfd7b69d5f3b879fdf27d5b7a8ad61b61e3b76f140660a	1654175591000000	1654780391000000	1717852391000000	1812460391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x53ce5d7c9bbc5c9c71e013f821881fe273c74cb834c8b8434340d308ae895e9b908b1b2a723b01cb2f8f17b81697e7286ae0676ab8e9a2cc8e0a97c72aeb8ffb	1	0	\\x000000010000000000800003cd41ed6eab271c32a0bba83292fd78ab11716cc0c733b9e99792052101513693b676f48e9df69b55a111b6ac1a935c03d315b2a6c47070c3a52e2c345656b4ead079b66a44b9723dbe2dce14d1722a284c83b345334256ff910271feaebdfc62b81206aaf03e7f58daffe880b65a95a8474030bab587a7e30fd12d24feb987fb010001	\\xece955165337650f20510b6f98f1e7bd2846a149019d498b19c9d992bf0a4ae2688f62371998fcaeeed5d35298f3d6d0057b9ebd16c5f687d35527b06c915206	1649944091000000	1650548891000000	1713620891000000	1808228891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x554e3e8abc761d85957c3a8dd02d7a25a173ae82f54aedddc70e18a2c7906587e9828335ef823b2dbceefe3de3ba1e6a71075d3ef0ca46311019369a6f2406e1	1	0	\\x000000010000000000800003d29e848b8a9c93cdbb9e07ab4958640f5a97f09e680ebc09131181c58a5dde28f9f18de38616170618cb30cb1038d7d973483bb761bf55770ae4853227219631629b7ba561ad27715742beda7bb9addbd27dd2970bc4aec0173a6d16d96f71a8a4d6a9c14861271e126bb354b748f8eca5fe1eecc21fd501f9518f64d3e6432b010001	\\x45163084a8fb6a722cd6e5afd3c4f96997be0bac7d4a2ebf546a162e6737c9bcf0b0b0af58054aa71526d410be7beafdf92c96c42b62b6dfd2c096124ef5340a	1674728591000000	1675333391000000	1738405391000000	1833013391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
233	\\x55ce1f22bdb9ecca846a14fa66b0ef94bc134cd2ec72479b280ba5db9d3dae8149cf1dbb2f74f71338555e0a0881acbe328f53d4988479ac3592cdf0b5833bdf	1	0	\\x000000010000000000800003b63c4feb66ca6db322a77b9cb5eb298a890cf1addda618360ed2a77152551896691c91f5efde42b12b64e9c62b4e762e5d1bd474f640cc1652d704057730c8fad54b9782ded2c434970f0fbebb1891e64d5894f4984e68bdbeeb9770a2148273da041899efefc34ff888ab1001e68690bd0ff14f6827daa6d3334cde29ffa9d3010001	\\xee893877a9d00ed0811d7b3af6182551b7872a68a8e80bc528d965d7f610ed448cdf06fb06e34754cb3d109462406a3fc36182991a83dc59b3bb5ad9b8e02301	1654780091000000	1655384891000000	1718456891000000	1813064891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
234	\\x56e2e1235442510d9b4ae0e58c3ca1027afd99ed80247f6dd13b248b60882daf5c226a7dfc711a16ae4293e1ed34aa1cec57d2d57aa2f1c00b82982b926b2125	1	0	\\x000000010000000000800003ce6ba98e7c945da065f844b393fbca6216a253b58aed79eae0f45e0a5a1065d0f2bae1b2a36dc3e9af7a000d8e44b32aaeb0b687a061781134efbe227b4057ab913a641c11d228541f42f07a0289f94a472a25d8073e7c9e65a714cd81ddefd14f95ef3329939a750d9b42edc8d36bdbb1ee675dd29164d563d55798d5459aaf010001	\\x4533955d2c72a41ae91b063b0d1e1e5aa2811a5b30fc657c414dc05cc22f96318cf1408822ccff6f6d57c4c9f2b90c96c0dc9449d12f4f9aa39e1d3156c5760b	1676542091000000	1677146891000000	1740218891000000	1834826891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
235	\\x5a0e5e9d828b0f5acbb3d6a7b15cd4dc7f7772e69c7b5663b9c4a844becf9d0dfeaf7c49a86df59e0748815692abc2a72dba11ca7a54990d3f8768d7c2a53325	1	0	\\x000000010000000000800003b3f2e9a4d6cd5ad6012cbba147e7fcbd7611b98a22a5000c16f5f65254085b18796844247b7d59530bd14affe737b87413deeddb82d308b3d97c995576227c013a94aa9ee1ef67b9e3f82c4d5db88dd01eee8d6954ae16fb9e9a32c7f15c9ed34134d098d5878ef736e5aa2f824f2b2249eb6346d6b1f59edd3dd981c1912d61010001	\\x33b4575f776c3950cff0fe6161e23a0ceca20a33d5983d6ae6ca67d5251a3b2e1e761fae9688a1f9fb7d111d8a3a882811d07457dfea7beb5e50f92f1450a205	1674728591000000	1675333391000000	1738405391000000	1833013391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x6052ca670624fea1675d88cabd8ca54a3643c80f5212019a70c683d3938f2c053eacc53cb223d075dd4e56baee8250f498c6a4273244f858ba6d1e98ebefff41	1	0	\\x0000000100000000008000039299ed9b6b856896617e1ac2b011d436309ba2f6038afc7948ba94f536401821d8f19046fb7d8a614bedb6adcc1a61dbdbe8d8151bfad1297b587c6dcf8d3ea3972f802968354b778fe209ac769d841c5dc2a10b8969119bf6b28d59ad95146a39138840d6943edabad3432e1bd8b6707abecd0437e1e3a24746c606372aa521010001	\\x976b1d3a3f9f1ee22582f4084bb660fe8dbdd08aeb54fe4f96b7c6868980b8d87f675d8b652bfce76f4cd165c910450f17849d85f1aeb0465995d1918e54550c	1662034091000000	1662638891000000	1725710891000000	1820318891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
237	\\x614296220186da199988edd1264057124210eb64707e425f39ced4381a7ad16eaf9e4d216140e9b4cb63cb33d6c2178a1618d912c17796484d0afe7996bd4bac	1	0	\\x000000010000000000800003b35b59983dbe5c5d968b957f8821485bd1445cb48c18fa7458fe70069ee945d3f92f0bd06b74f82e41250813ee89293d298e83057c07f44e369f7b1fa3b84cba4089f7f6ed09aac4feee05ea04a746c21b5989729661c6634672b83a0933e09b0304aeb2b9fecc866feb6d15a1fde80604ffdc2f69c227fa5d1b9ab1638a92a7010001	\\x15a95f0a3f7dac866f213d12892e3de95c8fd66215ffa1561c076015d22930fd0e57b8699c53ff7884e4c655f6903caf8e282bdf11bd0e352e3bfc57f576f20d	1655989091000000	1656593891000000	1719665891000000	1814273891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x62b27efa923ca65c48c0d1ab656e5eb23ad993ae5f9a122fa5c6b68d358050b96a4a0aec2e69a05403c59fee20bcbc37413a9d0bf279a5aa3591b9e7064846c5	1	0	\\x000000010000000000800003d7aa459b5dd8cc4ec706a2c79e85b2d804a131cf3c573a23d5c727327444ef8dd9929a18a9ce5cfa2a931d82aa6b6c29ff7575f163aa8c86c7c5b04a6a4b6a097cc9a7a7a8d3dc078d2a8cd555422391b50d05073343e49b8bba20337d5124849fe5f7b36fe65873089a1742131b5710ab3328864daf1e3d1e58d257f7bb2451010001	\\x11d9f390781ee6e589d99de14e802ccede3032adf2e56ff793e17f40a1ac139284120f76d07dca9c85d39aca681e57f3cd8e3c607cb6cf55bd64a671921beb0f	1652362091000000	1652966891000000	1716038891000000	1810646891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
239	\\x6332c8b3e0a60cd07d663fc8b4e46478b4e60cce52745d5d4ee0857faaf0e951a1ba3b550259023aa5095559bf2fa270ee3508eb3578c305d61c4e3480317ffa	1	0	\\x000000010000000000800003bfc664d68c2c9b89a57b32fd0e0480a1cbc26b49270aa12ebd1dae9e0f2b838f5c0e8a1e95baf6ace7f4fa3db8180c2bcb8e4afd7a26390c2a7a4efdd43d7aa54c2c652a3974879c009fe8d9afd3b704fe8f5267d43b19b954f6ad3a1fde8753ba554bb650cc3c12fd3238187e3a234a8262bc430cc4fb95c39af3f17bed1439010001	\\x503e139489dceac9e911432e3ef4ff82c9a75848fb781dab7a761786394451bd1e5cc5903491390e233ebe7372a53c726364f4f92ebf58f5e016c38e74b32b0d	1676542091000000	1677146891000000	1740218891000000	1834826891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
240	\\x63067e2c43f19306060f8d556ac1552552ca7e7fa7924686d0a25f56112c4fcec8cf352430e370190e9d8daea8fc0dd04d76969094c6b5fb6a96b1b9fa885e55	1	0	\\x000000010000000000800003bc58005ca0db28ec4276ffcf68ce62c74194a25eb6db282d5e4405e5d043ed0d4ab0bfff15b8dc229345dfc405733843f00489dd13ae60a5765eb9d06b368f30652143bb8b9f92cbe202e659475f831ec9cc1de022b34c3b9b1a309d51ed935008b52e8751c7dd03107ec8027bffd8d9571a5b6bf2a5d2a194989f9328a3f215010001	\\x94ec438698a05e5d6f75df0db9f10987f43cdadacfa22c773ae18eddf53550517afabc1ace1755100fee6cae5bb6d99a553880c052e46042531a69c74a9f0101	1655989091000000	1656593891000000	1719665891000000	1814273891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
241	\\x6442ccda4993f50ae5916f5ff7982d08abdf5ae505e40be0b344d163deca66626a1d7335431a0c471ae51035bbc3538a245225373212588943af19bdaab9b93d	1	0	\\x000000010000000000800003a1f32a3c9908e963476f03ef85eddb61d02de01ae253edb7b980e7e43701571c07191e0d9cb2c806a5cca427656fe414cd14dad8cbb078e7d12e5ee2a58c102604c96f03fc4ed53cc4574ba38790b287c506ef8d12d8f1628a584c86782d49cefe56c9bee6af07e81fafad664f315181c819c62b42d465cd77be3d4a861db6ab010001	\\x9638a74eb6d9c5a83301017efc7c4f83d091d1d6af36b0636b8729cc4e97f59e7273a558228ed37f662744bb2c31ad03c4a7e4f0592b7db42598abef2988eb04	1671706091000000	1672310891000000	1735382891000000	1829990891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x671e0e53623aa5daca4708b159e8d664b1ba7ff8ccd5f36da13ba96557c90a25015e0f582fd34a2b38c970b20fadafa56fc08418a712379b2a431bcc29e90324	1	0	\\x000000010000000000800003bf783527e112fcb754eaeb67f4ffa2399f2de723076f4ddd8717394cd6a543c255df2f8b16c7a20d4fa5dd6292e5e3137220733f80bde7abdfd048128b9d449911ce72d1b879f217bcc5315295d152952d119fb044b356d4a5596d5b4c240955db000927cd4cf3231cae61a346a7b4631ed60fd08304b90947ad124f4f6bf5b5010001	\\x8352c49a34b38b7b7bb1eb050c0954642ad328a5c507d6cb3e0da188f21c5eb546031995c200699eafea3f4e8044ea7885b02b1d1c84ae14750f577b1db9620a	1674124091000000	1674728891000000	1737800891000000	1832408891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x68b631fa40d517114c325251e55b37336fe42d8d626149c3185ad43aa457e90782cecb750dd8b8e493ad44887aae5fd958ade2f9a9662ad1443b08cba29b7e22	1	0	\\x0000000100000000008000039b3f444b3d59b6a16b8103f923e8c6628d5edcc8543793476d06ee7ba570b819992b8bb4ec4e89c42fc767581cfcfd4f8da7e1f47c9db9fbecc92b09015d1da21fddf68cc5aadbc065f932843fa958e1447aead463837bc5c61a8440d5511a8513f720a3e8b9fa80fabdfd4a3a8fcef9fb136fa63932eb7be528bc80439b32a1010001	\\xb1b6bb8f62f884717e6a8dbefee5fc5c2db78c44b594f6c20f11cfff23c4589d0acbc81b1f2ba82f39f4d1b40a796d9a9e0b623237fe13d787660a99b1edd70c	1659616091000000	1660220891000000	1723292891000000	1817900891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x6d1269facb012fcb85730af20fa3b0808ddc5052b9f5fe5279a5418acf1d4f719f69aa27af82b9fe06a2acc81903269dcfef1f4abce14403a1c1c20729d94c8b	1	0	\\x000000010000000000800003da9be8f39ea67cb88a901036bc690ecae6539e0fb53910861546282e063bd8629d5e4fa8595722a3e554413697746b5875c34b36281a7e292b92614c613c30ab9c4ce43ab6c68a90b8628a7633e5f4bbcfb82eb081a9338a2f5eef26fa228c4eac5f739741ac48ff397ce67967eada4bbdb389d09bacd817df4575afa94c5837010001	\\x4cbd0f61ce64b192ef67da880f5182f845d1ad9f8de931be70cd28c14c06704df4240f29b8fdcdd7818cff58dbfe3010cb105a2c2ca8f5b337bf4f4dd79c7206	1655384591000000	1655989391000000	1719061391000000	1813669391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x6fdaeb37521ab7afd2f1bbf8eec1c94ff28e3b9008d6427f67999f71a9f915eea36665d013ce2863b1211330d977c28dfd40bf85c5c530ddbb746a040ed8ce10	1	0	\\x000000010000000000800003ab99d3de0008e63276bc6d19feb458fbde4c7e084434d1641f230f173c18c4e3fe1b1c34efe8ef2db989b6e809545e3c336049ea96906d60867aa9ebec3ad41b2bd2028a7fa16b48541d81a2912e20a241e4f2f4db86e708029e7c5d725c290412de5d3aa9c46a3643efeba36a6e918ca70ce96928d33d3ca0873a74129b4ce3010001	\\x8167c8e4dfba234af8f56b6947ab07c62436be757f61bd4fee68da044fb83f27339aff7587c63ce07bd83fd779bc34fe2301aae3ea7e88f1e61435008ad5630b	1664452091000000	1665056891000000	1728128891000000	1822736891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x73e661f50874de0c8153582327b18d504f136852229074ae223a99b8876b9da9565dd998ee45d6587a687b3980641a6bcd3e8130a1ba7ca77859cb53f1c7aace	1	0	\\x000000010000000000800003a842ddbbc4f69716838f1d39a420544988bdf7e8a6783a8946df2d371dd31bcb707fb11fc543f42397547381da8f393fbb181ba3615b3c4251e096ca3e68a1e40c69d6d5bbacc85cda2b6c0a00c7521d9e4fc68c57f1a83ec0a9a22e9fdf6aa7b71add09829a6784df3e4115896654d0c83f78f085f8ae20aa1f8f70f7c48607010001	\\xf8fdf2bdde8a948a3968bd79dba871c7fec01c55db993d76588050483ee723f2420c3fa71b57fbb0ea77fec710982ab6e484900a9679e27923f242a1f2cb2904	1662638591000000	1663243391000000	1726315391000000	1820923391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x77fafb7b27ad0a3f68c49dbd95d5a9ac406138bda7c1ec8bddc231c43423353393f0d2e0e206d9ac8e8ec924b52e75b57a944da21802903f6ac1d92fbfcbe2a7	1	0	\\x000000010000000000800003e3483d2975fb60a9b867db55ccd481a0af0612b6840d43492631791c5d0422fb947ccd3de9c7bdc55d56573f9aca9db4d25a1bc7c075778733c4889901a2a24d14125542d287b891c8943bc574e634f4361dd7f40d8dc37b93bd3dc26eb60f852cba0fed866ebaac6079f66fea828fc52fc651ed8e378120da9bb925954b3a79010001	\\x3b8761e77ed337dc8a443b9fdd2e8cb9dcf7c04f35304446341f3d7bfe87d784c222531563d96c1a430a2af749346d1a88f306598b0327b3b8ad03647198ae01	1658407091000000	1659011891000000	1722083891000000	1816691891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x78ea10eb1f27f0edaed175f7e87aa754f3a7deab2255c6187b706ad38687337b9d518f82b7adc3d7010dd5d0a5ed6665bb3f3d4511828f0b6f86af4097f6f7ea	1	0	\\x000000010000000000800003e554b5f62eb09778a3ed02533d3c8f7b8eaf6b8320b33c0667d5530e36b35ed3e32caca8d0a0ee306d75ba13694b345493653f3fa816c9010964325373f776d7d1616564d776cf57d466428867f11e6784cb1533b76098e3dbcb47825c997ba56e2ffc5f956d0855891a300ccfd63ac13d534c1fa5eac848a2a5afbf025bcaff010001	\\xa863dec1549c7639d83bdf25108ca17a938b477910fdf0dc3960e01fc2ff6d092c0b27a259fa42f1d2339aaa52997d19cb0d0e751e5586c2ec2765f9441ec20b	1650548591000000	1651153391000000	1714225391000000	1808833391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
249	\\x79fafb8f7d489b95232a66381b4eb64683fce6df65bce7a16b2bceaf9e49300bbf46a8a50ebbad79c1b3287be0e54e2bfe13ba0d2f544d95af0691a1f878eeb2	1	0	\\x000000010000000000800003ef7f1cf6707cfd6cca008210f08eca4e5f73270da501c1633cf50102e5a440ee953e7fb2140e7f22457c03900d3818d4b11a44f14ba973c28ed877a3ebbf8cf9cc1ed21c9ebb5add9064a7f5362af05382541961e091082ef435cfa71bc8b2bfe06be23649b0d64774d9bb9d29db3145655c627d64614954f1e98c84c1379339010001	\\x9ece2ef7ba649faeb6dd6b4bf3d8ae99f9f44de88cece2462b847f8d9f269e9e5155c3e0889a82ca1195f032c1504667a66405ec6d27a7afdf108979af85a30f	1649944091000000	1650548891000000	1713620891000000	1808228891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
250	\\x7c5e8445b52933c0fa111253e00909cd071c291a10d283ed367978ddbf8ca7ae9158ab9c995291dca3f3da694c2fe023d47b08c0aa4a3269b2e4e35954e138ca	1	0	\\x000000010000000000800003d8f0ae27a8a164ad2850458e65a6fbd9d86b03ce0b9c90f3a2084608a6d1c9d8fc6c1874eac7d0769460e554afe7269ebf30ecba121fc625d6a6d8b8db5be0cc3708c197545758549ecbf66e3b222f4c2b0eef8f977c77e1c060daf1e7895997822597a33c5157c55560d43e7ded65ea9189d537f189a175cc7ad286f9f71ebd010001	\\xd20bea576bf5a81994aae818ebb3b9016079b034ae3fae4b67ea34b4554c3afbe95fe3c87d68415faf61e5285dad940c75f0253a4fa2241a73ee294bc6b1f509	1660220591000000	1660825391000000	1723897391000000	1818505391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
251	\\x7c72c04ad71855750cb647a62b2da9588ac7302eef193b663758bb35876adc03db62ab1bf2e4575a0a845ecb61c22d608246406df8330a723c0b03de98102dcc	1	0	\\x000000010000000000800003c8a4082f2eabb0672f169aa929ac2467ed6b6e36d917e8f71b6348105b8339600d5d5f485337fc1c0181cc9cb373594d50b0feb1fcdffe2064d59f53d343cd315b654ed14ae94ec81edcf022f3a89053a69c717c606c73b0ba9755def28da91e2b5938870000c2c4fa0d97dfe1781b715b138092f35982e8cec59a6f4d8eb9c5010001	\\x6a6bb7cacede9273e08ae311bbb4294888a9a5cc9d45afc571be0aed19cc822316f7cd3c28ba3a2c8eec78f287f999d9707d2f3d19802411eaa9f9cb61cf190c	1671706091000000	1672310891000000	1735382891000000	1829990891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x7f82e4e4e089a531c1fbc07e4affb9904d8acc43298cb02fa467c6e1a3451f41c673707f585437eec10ceb3e340a5f4143d62b48f84af329899e3c8a4ef7e54e	1	0	\\x000000010000000000800003c906b33d445461ac1c2e8f74b60eedcbe107ca38454bcb982ed4942d11641dfe5f9bc73361ce3863302c33203e29d996001cda5d1b6627291986d4b2772a089061175dfd2132d859b2526f53a0522b6a91655ea78b5deb43a05df2c8eeb59be95b4054d83990c07b1a1c83d68f4c4e2b5d32ef118ea7e6627a8ded484ab884bf010001	\\x4bc2fe226b67808b6587361df299882b377e75e1ecb967e727be107352eeb51de847bc029c87f0090c1b4e768a471044c036da9e435b8068233de09717060b0e	1659011591000000	1659616391000000	1722688391000000	1817296391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x82ce1305e3e2b01f33c7987726d42b081079456378cbeffd7d7e7c121ad08ec601dfc9f04c222af5b659cbc56382f3170948403dcab4a55e16e8722eacc9acc1	1	0	\\x000000010000000000800003cdf56ba6b4ee85b49735d454f2c4ba525375e98c642970dc1128f2ca3e76614ec794eacde2ce52506fc810dd9dca7f92e397f1508888833ffa1aae3959da7a83b5f56a5f22504ac61c938f51b62cb8d4a2fcde70c1689f45455a202ac2fa1f0cc8dc06bee2fe6bf724975e196c334e60efa0e6a556fa58c139311fe69fd6b0f7010001	\\xb87a93804e080f52f78f3eb17ee2b4d663080b4ff1da60af018e28c981012058165a566098ed2f8652ac58ce2144da8c407441d4ab2e7dae5028c77aa295ce07	1652966591000000	1653571391000000	1716643391000000	1811251391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
254	\\x86065bca39a34c3d48dca9c0bae3465ebe8dc9bef393c11aa609c955803f9b3925c435455184c937fc48610fdb1fe159709c6169ba858ffdbd347654008d9c74	1	0	\\x000000010000000000800003e3c4cb4039de14e4a0a726b7b1a58ee014203dbd9adecada4336b5651393128bdf11c03ddc41caa7700790a9b12f8bb9bbb5de65377fb7bfa44a5cf55459cd4636ad555af8dca38052c8ecaaf678cb599408bb1a0796850406148765d037c3f03c76f92dd04c69c0c930ebbeb061d951c91b00e3db16398d6b3b047893753fd5010001	\\x074b1e4a8b3d79c1ace1e7ff2044d52bb3f201cad4b5f55e0170183059f4fc2f250423b7aa27560efe5e650faa6bed7ef717728e97081e6f560dbfe2d17aa50d	1653571091000000	1654175891000000	1717247891000000	1811855891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x86f2eb62326c48a02003173134332b6cf522959a327015c96a1999672782d950cfbad31f9d75c51622a85daebd2cf5137225a2073044edc38da466bd52d96cc3	1	0	\\x000000010000000000800003bee2df3602241f880b3456ead47de22b72b5bdfc2a14df4732be3933f79894d2182224e4a454ff97d38478f46541abd58d04cf4516ffeb74de0183a35e3a76f8eb5daea21d519ddad70bfcc8f49f87f4a7918974473ddd62cb7b3e4bee6b5d1f6f02bc36cf9e1da30ab8c6e378df5f5490ab6585dbaafde0aee204b2f680117d010001	\\x3b086d6d7cd064ca40662f091cfc0f350b8be1f29f592777043fd7c909901f6465ad947b90e61ca0e33f489cefa379e1b2f89335a1e023943e613ccbf6d89703	1668079091000000	1668683891000000	1731755891000000	1826363891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
256	\\x87065ddc45a17ad9c824a17473443f5f0d9e82c213d34f83fdc7d4bd997ac79374f8775e455f1831aef11ec6574aa3126d80d21090945a8d952b87535f7e9bbb	1	0	\\x000000010000000000800003df4eeddb47e376bffabfc6f9263cea493c8126e4427ca6a2f9ee5b0666f419532285fcf1175bf4a162158e2c5395bcdb7db383ee3e2f1d7c5778063f66c09537ff1846d51161af590b3967ee96a618dd269be84fc889b7d6b9af04b581d619ea7ec4e5545eeafed62a022513d61eec51ea052ac5d78d8d93d8bfc9934ecca985010001	\\x53e8e5e666ef87819f43a45abff1f3f15b9417c1c7df6ed97f5e564e532c5bc3dd14e5fe447a8eecd3f84bd04b5d8d377873166d5e03f43a27bd33ffd45f840d	1678355591000000	1678960391000000	1742032391000000	1836640391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
257	\\x89c24edbc490c3eaa174c9f5c1df6a028f4607a822f215bc85c1d6ac9fa12caacbd52d57d3ab19825155546803ebe14324c08ced9b88ab0e946ca7dd2a234d71	1	0	\\x000000010000000000800003b91740c825d337416ecaa5ad6262155e891adca968d5a71276e9f668f17d59876e1db049aa33617b4157e7946ce8f697e2953fe96c004d96bbddcd66859384346f6e74d9663df3611160c9982e61beaf08aa510ded3b3fe5542e6ccf8d60ea1b206050d9f82843b024f5be2d7b0a3ba263d44d031df7f8d704d8a1db83c70693010001	\\x49652ba278ade332cd1cc1ed7e088a690d99b51852b3143acf86770021bf0008aad7f324df88bb373519e43a782af90d476184587ad734b8f6027aefeebe2201	1672310591000000	1672915391000000	1735987391000000	1830595391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
258	\\x8b7a09a8abebc0e8d55effc9783512eb52383203a247d57d878c6a848df4042819fc66168689e9b03b0d235c1dd81fb9aa5f84cb0680fa6986ea8a26f8d78738	1	0	\\x000000010000000000800003bffbfecd9c062dacf44b96bd18ac5e2e3fd147cf0a7664b1b95d3590dcb6abf28423bcdf31de2762321e8eb9cb6571eba16a5d7c3bc4d72d1055460e46894ddd85b8c007b84828988be57f736a82478f9b083aaa7b78b8518fdce36bdd76d5bb3c2418ae47b15c516ff8cc36df2895d730dd8f8374b87aef4c801b8042877489010001	\\x492ee98e3c1ed3e3d32f5fd2c5a4c04009d957de51c9ca7f23106eb352fa701e9b8d89db7a953c1e21a69e516c9a64d5ec5c5998751b35588e12c3b655bff50e	1660825091000000	1661429891000000	1724501891000000	1819109891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
259	\\x8e621cbb5b723ce06f9bd05dff048e9f98e3543d025bd826dab8b01e1d73be94080dbb3efcd6c4796b9be0a4d0431596335beb4cf0bd2e2305a28748aa04be25	1	0	\\x000000010000000000800003c11e950b5b7acb36fc80de039f3278817668554d933a388ada5431e75155f27f86d5f237bcc65ea011b11f40e9a5ce6c14f2c0406e133882eabee7a25bba79caa864d26a9a9978afd345c413e7c5f26bfa284151a8edf107da8f5da06c22ac650b032b839f7109ac28c4f3f328899584500b02cbfc49e0e6b62d15245ad9f32d010001	\\xf79fb4e74db6bccb686039fe3579874bd8db292438ebfecc9fae722db4ec6f75f5e2dbaf2109bf2be98fa3ae1acc4ea6228e1ad95ea5effc67d37fb4b5c9a20c	1662034091000000	1662638891000000	1725710891000000	1820318891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x8f2e584a5627c165c831c1d22d156be0c44acaa56712a0f6fd8b7e8f3baccb22a958a0bae861023c65732240a389ba6e834dcf1da2fe7400b849dcd56f38ab20	1	0	\\x000000010000000000800003ca5484b7d7b2b96e9cdf44126467406bd6d9475f78715661e63bdd5abc78690434d632d466fcdd6365cf84c64f083101e13dacb7a739cab63ee832a8c2bc0d8979f2651701b303b2f3bd4957620762f0e303b43b6def2ab9ad92de30fdf9c9de508330efec3bae444a04d665f8dff65096cb1935c189fde02a02a8ded63539cf010001	\\xbc053efec7e48ad8f4bb84358ad3003c0acf3496806845740ce2bcfaf0b580cff56f29a9c0bc154ada4bc80439b836b6e945a3fc1c0321cf69aad1327437500c	1648735091000000	1649339891000000	1712411891000000	1807019891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x91da12e5ca8ab8505224ca5fcd433ac9f9cb449a7c9e4a17480ec63a38ff4cf6e9e17574e435eaac2948fdd4cadb60206f0b79b9ae3585923676cc951e30f38d	1	0	\\x000000010000000000800003d033c4db3f2ad1ffcc7c95bf81b788f158936938a44fa83007b6afa7996e4e9267955e2b015d5b3676bb81d7048986e84d210f0cb7b65a3582f31ed8734e81921d86ff3c4e869d422b67078e0c1d15ab45c9800ff69f94252e0e7e8340d7b26d60c7ae355092cd558aa1acab2b8a93d18e9519fadd16aa2b8a59b1771cc884b5010001	\\xded6e2513b9b2f72b17f4bfdb6b6dc460d638cf15c3e010dcd64a2878eeefaa5c0f9ea75221fd26920291cfb6dcb147f61c6c74f4764ecd1e21c689f23dccf0a	1675937591000000	1676542391000000	1739614391000000	1834222391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x94c2e6836258fa956917039d367d78263f36f9a1e5e9f9e4b79ff3e74e437d69ace6b646aea1fc61a02f8dcf089783c5dee66b503678cdad72dda5df9d7b8b04	1	0	\\x000000010000000000800003a68afec15f9069b9cc05526afea21047e2cb273a06323f299ba49713275d8ecbab8acf73fae88773e10eaa113248c6d848bac0b3f8005098f58f3074c818feaba75276dd09d43a1a92f89368134d1e37ecdb40f4ecb650eea30bfb49a449b633dde5fbef0278f1b4e6a6044877ec187a4ce98525b9d5c80584717c90482563bb010001	\\x1d54339ad94dfd62ec510f3ccf639fd6baa99e5979240fe02ef6f699a384b8ad012bb72270476921946bdff77775bb733ddb09de6ba0e30bd183aa8ef4a4b30b	1668079091000000	1668683891000000	1731755891000000	1826363891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
263	\\x96d260f0016bf34035e54b3be718e4b097a961a3bbf9205b00ae94b7b482a938f7a848233ca97772b0245f79d5489c5ea9dd5d7988afcc0c66f0fb0e8601ddf9	1	0	\\x000000010000000000800003bb7daf0dd0356c1863e46512ca3768d397d4b36c581379015e1b43613b009020bdfe34973e6df12b564db9112eefee6cf097551a9de10e83dd1766f87e3feb2d253c2861e29d2066408458ad7a41be4f8b8d659f8af7ce10cd2232bc18f6fd8b357307b4a89f33c171b53375e4715d0bffb7f8d5d3767e3e56da26201b497e33010001	\\xc3cb30afc4e6740937e9f5a8351907d2aa721c7f2e82cc10997f14c4f142abbf8ff3f9cf46fe736e45ae3c10b78b5ce6d5399d5a3f45bc48649b8120b39b0902	1678960091000000	1679564891000000	1742636891000000	1837244891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\x9b8a7157f14bea5139f8b08c128da94cb90186dbb53f88255f92e604c828efd40ce2af906114fe59cc56da37da241ff7e0eecd72754a1da7a7fc7d90d836a6bc	1	0	\\x000000010000000000800003ba55cf8213233c2704fd4489209f92de30b685bdb0375263a61f4ceb69f754b4026399d65df87af6ff6569a0010080efe57e398a00b95561a4cbf6661b89e6437541749088ba61f40bfbaf2d797f67ebf3dcf7d69b20257e78c8e0f5e3654270a2e0e1a0487514b1b9e31c92e7e1328e5e4bf2a584e2435465ec0e3e9b4f21c3010001	\\xa17a9567ad802927a8c174bb8e48336984e4afac1b60262448e4152dbb709572df98d52c0c1378ce6ebd345e1b70dd5924e19f9637418b589341cfca18411b0e	1663847591000000	1664452391000000	1727524391000000	1822132391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
265	\\x9b36b6a313ee954d9746954ddb270518a83f7b3805b793aad6fd1a46ed94b6e0acf081e5cf9f0812cc18c1095f36e0b9676444b6412e2ed5d095fe815eef85fb	1	0	\\x000000010000000000800003e45013a76a9a456db66354d6069376058abf97a9f4cfb7969a73bb99b65e6be783cb8696f052c625812666cc9f2df996cb377d2bdd3c3564db37e21496bfc2e9d8986f716973b944e0cc110197019d07de724256cc2e3e0d538f32ca845fddc286bc1f479b92d27f67265ff8126427aaf9e1aefef541fcc441892e6a4e45bd33010001	\\xb69c39ba05ff8aaa39d8e28b6905eb96bf3d69ec1caa5ec3cbe951364d85e7e334d4eda6cc174c26a0282db1d1991e36d1d2fe3888747ff9a48ce400808f0408	1659011591000000	1659616391000000	1722688391000000	1817296391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
266	\\x9c261c2687923ca6d6310699fa8bcf4d3e15714fb06853011b48b0342ab107b8130ff0fe7e360f32670aace94c0e51b9dc91781e387c8da08167aa442842f5d8	1	0	\\x000000010000000000800003bff0dab2ca86ca18824a9a8505c0f159addb4c402fdcd1bc275324fbc5d0a0ee1cf5275456b4b311420a2f3ad9885e1e43fa422d0da079891dd9ba51537149ed53cd0e49f0b9abac7bdbd66b2f4d15add4c4c455140e7719f7639739c643dd921a4481cbc65aec70bd3d243cb8021bed3b51b214584b9ff8eb7886ebf1f50f61010001	\\x23c7f790d1a2f0de48d1cbb9c485566b8d2b63f8044e981fc28de33f5abff3493d3c087e181fa173c97ae66a09b37f162b82ddd3ec349f1381c6deb16b943b06	1651757591000000	1652362391000000	1715434391000000	1810042391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\xaaea4dbdd98ee2b542828f0335f9d0d5632cee7050421d6b13d9e06b83b6cb3087600776fc6172c9cfdbf7c4a1c918ce3d974812d4e81cd14995a9ea82237422	1	0	\\x000000010000000000800003b8062ed16cd8b9ebd546a401a0c032281d8897d031550c79a02a692d2538548fd8163c79ac0bdb5d234d6619f05e760d299f2b2e89a63bea111976072e5e8fd03823633c1d86fc98732b6b6cf4dcbc5c7c632fccebe140d50322e3b184709ca565eb072ce32eadca711cb13ffbe96a688b18f01aa6c6989ede5bda816307b8c9010001	\\x2354b10f05e77eb670fc8d152d0ed0f39355cfd37f06d0d29781c0c5e1e63cb0fa07bdd8e96b7acf4f810a94397f6a10e22bdc0ba41fd4e6707e479b199d9e0c	1657198091000000	1657802891000000	1720874891000000	1815482891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
268	\\xac2efcfe37ab48d3f9c2c29eb61267f1cefdc0ebed8db7ca21b00b187f93318158cc8b5ecb8ba81cf3c1cc7a4e6002bff3823e67e828b6f3df1c00dfbe3a8578	1	0	\\x000000010000000000800003cc6f8a944586420f3987cf85a4f12ae8f359bd96ca9c9d9d0bf30f9a5e3f6d0fec7ffd431e00c5426399388ee0b7a5454a9b1e5f9f28bf7e2fcccf7e473ed8f615420f233946c752f8b039d4137521a0175c4f46ca00d831a1a487341c51754d7b93b179638b40df9559443fbf73ac57d783c14ba7c674e652627638dd2d3f89010001	\\x59a7d247c2c49d6170ce0193712cd5dbb6559fd8aa618424b0c53d864156572c2285de8e6be9e4209cb8bc1d493b06e19cc0657f9e87a7473dc6cca7d86bdd00	1670497091000000	1671101891000000	1734173891000000	1828781891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\xadeacfccb282eef64980c534d7ea83c13266f42d7c5dbdf9201c796d36be5c0336d71cd56737541348e0e4e75f82a9b965da9aa1333e57310ecbb57577296cc7	1	0	\\x000000010000000000800003dbd16ecae57184dd73a26e62729ef4b34049e477b576ac783242f26655f179cd9a082969f4a7f64802e96555f61efa17c3be6e005d920ed4040d00c11e3799485d2bcb84d55922d52234b80404b8b0c611c8873a89f859de6239d03740429736d5d8b70a14b02ba3ee308e2a636eb621eee66af1f53375f014ec829a77d4be17010001	\\xf610577163c5d06aa2da4b981da56e1e5c8a8c86c81d2d7e3e13331c5992b07f471c377945a631d5a17917370fc4dfa3b5a41436393394bc35efb74b16db920b	1662034091000000	1662638891000000	1725710891000000	1820318891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
270	\\xb04296a60373c3dfd4270ea29f5745e29bba7b3a9d16080e8e6cc0173152d23790d6ae939666184c9107dd14c79ace1df2f552d6631dcde24da318749a7f8c98	1	0	\\x000000010000000000800003ba4d34b3eb54a63e8b3de1875bb3696efa19efe5b8a6d796c19c095eba08759f9c28ee5a379c8efee9ef0555b6aedc00e2493c0ddd62bae3ebf00c26b5042176ecb015b4a519d100711bd05f128412c43c9fed2157342ab405be2a05005c7c68329af3d39139dec90dc0d5b34f82951c84719685fce9666817cec4fcad4d295d010001	\\xee431bd3293b5abfc501754e3073a996f60ba25d65ac9bd0a23d9e199b0edd45b4611074b74448ed439df7bbbf25ce992425812997b216c8471cbd963a3abf0c	1653571091000000	1654175891000000	1717247891000000	1811855891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
271	\\xb01e5a8adab383d8544767f20ae69f49c4209aefd81e9dbd01f0f90d198f1c2f3e499abdf4bf8e9d6c7806305608366748886ce42481d0c1af567514901c0f86	1	0	\\x000000010000000000800003e16411b2810a05817dddc5d94c5cc1047c3bb799062649604e3125b0b134b54f567af4a519b3911f9b72538c8dad1c9536db3fbf7ec5c42218a3f5ad95521f2b2e3563ff7810b198b311b793061c162b56f2d66303fa364802084b06412a6744b276a4520d6abb95323f44dc402981555ef8b1ee1a995b3b738e5202716486f5010001	\\xb576ec7931de6b6517a0f52602a68973c6541c7f03ee58e9b9db5566831dfcefb1eb6b6bff17c8699e5b4b22c6c7c235407512212b904ed7cf81d9c12b75a70d	1669892591000000	1670497391000000	1733569391000000	1828177391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\xb2eafe24f97335f33b691cc66be4457994cb471f3ba54b55a3211b6e61994aa80715f5ec66a395a3ddfc85a35df250ae4e26fab843596a6366384baa97d32097	1	0	\\x000000010000000000800003c978499fd6b1e076cf393dba021147bbd64f528027e9b8ccea7615a374c9dd3cdf7b8075a849753e75e8d3f4bb8ebd40339e1fde0b5e3eb55881e8b9a9b7fc333981be231e132f6218a802f361d41ed2b805b3c544af0ca65bc4c2f35d7d3ce43632e1b901c8e79435a50ddf1645dd0d2c40786395743f8c39405cc091c59b95010001	\\x14680b6252e5f0746f8ae5ce19b21a16ddabf6f7c41225bab39ebb91cba297ad770b0505cdbc645341ac475604c179afd70daa807de37ba24dfde89be4014601	1649339591000000	1649944391000000	1713016391000000	1807624391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
273	\\xb60e0195679fb3fc9cd27d37e281d96c70e0dc00f86c0fe20b149dc0b6d227ad7e686af40dcc1b5ac9fbb50bde28702b4ac5e3bf1d7655836f318e564e1ac6df	1	0	\\x000000010000000000800003e2509766e4366e3bed72c98efa93acccbfe0cac998828ce1372229acb41758a6df717cacc27e5d99f11ca92eb51c1cc806a7c8ad455cca26423ac2312f63a5189f22a3666c9b55e2c946214a0086e1d0166e83df433ff2d705f43909e29d7316634932d27a114f5cfeb1097f1d00758e4692a242d9f19119c32211b488b61047010001	\\x02cbf09f45d2bc5c8e0122d14c2aa33d4b6845fb262b1ec6b35fd1cd4a5294b0cdd27a830fbf8e73088f22d467bca247c1943536c3652912c7a0374012bc1004	1652966591000000	1653571391000000	1716643391000000	1811251391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
274	\\xb68e2ceaba3d81175f9ef9e77159f30a5100e844c024a6942a237010cd53feca2e97d1f2b2bb20a1c6478f3c5fe4bd76d94a3a1957aa220c967e005a83d65666	1	0	\\x000000010000000000800003d2e6e4a9704723f3cb889d77c843fe3c918ab1bf46f8cc6f577de660a12f355e5f6fc6a76e58948e4440ea5b4fe1b9ea391d29e516a0efff5608bc079c5b0186df4ac8a20a6c3d057247f62b5fac765b9f9c31c0b9da81baab8d7294a666cd03f5cb73487da943befa0f34513c312cd0c4a6ca5fb6f382bbf37017e8c41dde3d010001	\\xb3dcb194130ba3673842fb49a50847560bdbf4dfdff495f990dc0aa2870f73043b1c2bb38a357debc37f1ffc6aaf8e7f903c8cd2eaff0ad54ff2375bcad8460b	1655989091000000	1656593891000000	1719665891000000	1814273891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\xb7ee0f280207e3be6def903eaf7b0806f139446ae3bdaa8e1686cd1a356e08bcce20c5d8304186727c7b7f28cfa5181bcfd9cfce23abbfb20a8cb9ff87883a25	1	0	\\x000000010000000000800003cbadb5f0ffb86253da9d529adab4854f9cfb23dc1d490b59a7fcfe1e185f90011ea635f2c4d411f2413abc6e47032f9823125bec2f981b850f5330c24abb1acbda0b35139e072d6fedb51ed1c2bf79243dd22a131075b448b967e1328dbb6c59cc839e3dd3c1baffd3c75e42c917b2bdfb6c5b3cb3a35ed20761187d6024a1a9010001	\\x120db169c76918dbdc14a34500f1cfaefe22c854d21b47d48ca18e1ebe83181c9cbd01bd89d2523495660fd4167f7ade1c39de38fb01848992ba0582bbed600c	1654175591000000	1654780391000000	1717852391000000	1812460391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\xbb6ec7f078d33e01c756031e4ce083f706cfa781daef2f6e502cdb5d886172f0cffc2e46af720af5f53f3d4145ab792d1bc5b586549cc93eef94fcc5d28928ec	1	0	\\x000000010000000000800003f193464f533d3cee9b09233bcef6757d9edc9a7b87b2d730f9f157bada286f870f57c9aa786326753bf05f064132c8ca4a51d2faadfff3ad7e2527ad42d81efaa9b5ab2c79d56ff75435bfcf161deaa5d4b85d3b14ae0d336eae565312d068aa26cbd9245d1bde01a5f39770abf662da54ba1505517104f4fda78eb7c1860535010001	\\xeb2b1f912af3c01d3fe92a25ab75601c00db419e4cb14eff9556f86100effb5c2db0b41c5de852e9ec76c7d58aec538d9068793b1901de353110e7bafcc90a05	1676542091000000	1677146891000000	1740218891000000	1834826891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
277	\\xbd42632187225a9c2f6a91745bd2de14fc520bddf4b79210435eafdc0cbee899900de37c47c6ad4b2526043d27f6738d5f6ab13476898543d2d280b62fd18d7f	1	0	\\x000000010000000000800003a4cb45b63fc070c1df8d043f83052e0449ce01e82653680b98083813f7dabde054b83a7d95966adaf7b5d0dbe9c8c282e3167067238364c2cee17b8be380785f166a5812b177b76f0aaf4c49df865edd01c934a98dfd7407628ec5efc18ea23259278a3dbaae79f9cfd3431538bd726b02a76ad0b5c746e819cbd3036b3ec9cd010001	\\xe6928413e669aab29dd330578b8c0ae785a097918152b7ba3b7dc0f45008d8169456feaa7bf95e740bdf761afd975a2a32fa3a98d64cfa21609e779678df7105	1657802591000000	1658407391000000	1721479391000000	1816087391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\xbe2620c045990595dfcc674b9c9b4130a03515a48f7e21454ed6f04d180416a722a0da8352c5f8a29994a05257d8728518e2259a3b0e79beaed8221528479e33	1	0	\\x000000010000000000800003e15e1af2be2128733202fa298e83689c03e74c26095fc110a4d396c26c1a5ddc3cffee008622d108aa0b9c54860f7466f6d7a1ea24e7267b42f44208fce968025ec61e4dc154325f16093a9b1a87f6592f9a920bc989536a7ba5ec8cc9765dc6c99ba51e001e1d2c90ec98e03731618400453c853a481d7f649bb7c2cf366d75010001	\\x4a07a2da6d8a698c798971d47375750b50773d0e3ce4c6251d77c0e9b54ce25f704fc6cb6543e94c666a7a0362a13e5c9cb6837895be631d7ea9854ef2e54503	1658407091000000	1659011891000000	1722083891000000	1816691891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
279	\\xc492eb5043d3a970b02025231e871cd8b1bd38062edbf0d53aed8884e529c3dab12ecf35af4633f061e52e6996bde0d0b36b0467188b590ed663324a31776c7e	1	0	\\x000000010000000000800003cffb68cfd4f4041d4ae1553c74891455418187b2fc986bdf51bd64a4f09a70564ee29d33d52ecd86619a9f3eaab229cf63aa649e2c83aa007fb898f28dc74a135da86227eac9a0c1d7128ca17814bf93080d7fe17ad0ffc7586cd50825d35f34af9a97a693e71fa6fe8263f218a580f9679f08766eec7f5503a27c91cb1c1111010001	\\x403a4365085fa84e1458fff968ff3b54fa03b6b4adbaa500bb9fcd4be9f2c9ef80672ce234d3fa5b45dd840aff977cec6a1637af36aa0780de39c1e67832b909	1651153091000000	1651757891000000	1714829891000000	1809437891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
280	\\xc45653ab62038bb5e9b2c85f556d815174131c3cea86f71e2bcb53b6a19d5d13380739c6ec75909ced38d295eb92734cc5f9f07fa08ace47be5bdeff78948052	1	0	\\x000000010000000000800003ae976f1e78be3d679c8457c1eeee34d9bdf21077dbd2cf367c0d8113b29df0875deb24bcd3734cf3cf98641c9a0491bd8fb6e43e502c4bd373ed2f6ad278d05e084b0e51b1e9e3a3ea4a641e36581aa4bcbdad157a2247b78476a26b3bab46ed3c558960ca580fbad1b37325b12eb6ede99ec482c83cb645ce953c222a7dcda1010001	\\x437f1540996b816c732f6a18a40efea748ee391d986aa5cbc421ec946c05ff35241bbb6d719ebdd699c6d70c09a5a843eee3f6e9546c354232c1af482ad3b90c	1649944091000000	1650548891000000	1713620891000000	1808228891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\xca9a7bcaa062e80defcf34769f8bc170be464ff73c603a839bada9bcc6799555abb4bf3a38754b0607bbf2424bd9491067194856e76296a3745efd36173e2ea9	1	0	\\x000000010000000000800003a643741ff7b54942053bb26a2bc551596b78970adc0efaf08f17403aeda0a82fbd49c68a890b55bb66caa2b852d86054c02b3fd58266931867f765aa2f7014b8b51dd51f9d93a7b9de2a8018eaca166c3fbd3b050902838f57533c89ecea0dc11496d0b45241b01e6e51cfd146ab34b548ac9b8c2cc9e42c8f0710ab6701d693010001	\\xda56d18b83f447988debb5ea008fc762a85f9371397621c25074f158bb5789af03fceba18a513aa6d7e822bcd0ff28bf1d06cd77b4663f7d913c803def0da602	1653571091000000	1654175891000000	1717247891000000	1811855891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xcb5ec7379ef9240b06ecb18889b30a6905f4a0a62bf167612fae45a0c4acf1d707f539693742f0b51c281341739fa5923ff8d3f6ba6f6693cb7f208dc2cd1d02	1	0	\\x000000010000000000800003e03db9ef03dc32ee90d44b3ff2ec5c41df535919f5e5dd525906246fe52764da5966ed4bbb14af9fb5f85a1426bba35869aed55e0029b7a56ff623352f1039b14d73628572d9b6b2a3ed3718c02f850214d3a24f040d5dc0f241a37629cffac6d45046126b0e2430a88edb5139e162659cbc3f1927a1393d4973b8836ac58691010001	\\x7645276b0bf91ce14970c3af13540a1d008f6c59d77653e3a7628a411e0b20b3734daf4dc25c47e4428b324211a3ff0f1b47cb4b18bd0ed985a98dab32c59d0a	1669892591000000	1670497391000000	1733569391000000	1828177391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\xccd6712120f1c0a951d75118f8ec16ef28dfef8b5efa8f59a7746d7429cdfe39de50215f678a088d4fdf439d34903bfc9757398b14d1dcc6d250ee78b69e29f9	1	0	\\x000000010000000000800003c762c9c76e4615df66f03d35cd156f3b9c325d49a18a25800bd298ff95742b9f08474058f085a011cdb8ad293b37c422401bfd5f9d1dd4ad6e3fedd40c2518e60a738358e71953e03ffb63bc9fbd33b75efd29bd3cb0be4215c9c358a0965e2e43310e84997cb4080878178b7dfd18035a27791b29e5b04a9d2176fc71c8d4c1010001	\\xdcc408d8be32876cd182e9de521ba9854442028882f5cc794894b4a4c794b3db410296a95c375dd5d1d3aa1b72d55dd3f7d398a62647fc11b55e10c1e9b82c01	1661429591000000	1662034391000000	1725106391000000	1819714391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
284	\\xce4651fb22905fea35ff0bb8276a552fccfd5b2cce2910e6830164b92b021713c27721e24eb8931c967ecf131444fcd861149b4d3fac49213a9ba48578e62ec9	1	0	\\x000000010000000000800003a5655d9dd228ffa3b8fd28ed8ea890b5b9e749f8cc2eeaf48bbecac88e77d6ab6b81bb3ad99f8da83754a1f538a6f9650b8ea05c7966469c1954591631814b9e416e6a02be3a1ca176a5aa7b41918c0c13042002f95afc027ff12232503699043b321fc6a06940ce36bbb2f7cdee6bb6c8390224f844b0e2e737e03f4b05a691010001	\\x5db2657e0c4c8fd3c297d927caf0a469fadd8c3d0ad447f8d808ba4405338fa9baf2faa85eb021db7c2c7f869f87edd72234dbe17c1a074bb8f62aaa45527200	1655384591000000	1655989391000000	1719061391000000	1813669391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
285	\\xcf2264fde4d2771a9d3dec86939bd1c088095b7679d5b2e093751513d3fc3ca26a0c841772b5ee99cb0816167404a0f126822e92ec61b9a9c7c180483c973803	1	0	\\x000000010000000000800003c6828d2d6d0beefcea33317f39c40dc3080f7315920c647d21bc0e0afea20b8bc6998a92919f20d2465d78736d73ad664ac0ecd101c3bb291f22128e49f62408913607377026a452c8adb008bf47fdc51582c966c5029543201b365c78e00f3715287e280be2d6cd8c7875df5b3b2972f2d6c80d09af285e20161a89813f5145010001	\\x578a55653b1f24103f1eb09119e30b13cbec74514c8c5f6e66ff0e218e49233008b8e5be605b7b2127c7f9b8de92c0478d6e25ca456eb324ab9111ad78e91b0e	1677751091000000	1678355891000000	1741427891000000	1836035891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
286	\\xd016097bd2c19efcf093897ada698341ac2788ed6bb3340c8d3af7348791581c5d4d735b90b5dc7b05faf210c5dc3f73c06ff5f7c9660a866576fe844342bd18	1	0	\\x000000010000000000800003c1822a1fbcb6d685ae145a9fbaf24c2a17354bcad54f96a10bdf5a9edba8cc8fcdbf6cece5019f4a0f33a0fd499d4abb77b0ede62d80a64aeb846fac91e0e0313399fa17c0d2c46def05877c48f2432ee60c25607b2a90114a675eacd7163478d6cf5b0d01f6f8564633c05e137f238c94048d38eb8a5bea72e053c5b14ed4c5010001	\\x60275e8837e7ee6597183cf65fea575fb53729ebf681f26efeb1ec21903876f03940f464378d7d1e590f85fd08c99f9271da3c1fd4dc5cbd83be41e08c8b260a	1674728591000000	1675333391000000	1738405391000000	1833013391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
287	\\xd1de4a9b520ec6d0f4a04a531a6697b0d4e01cceb61a80ca79a80171e99e61391af475f4e69e35829965de3a11d5577df62e4774265717a39a146a8eebb5dd1b	1	0	\\x000000010000000000800003e9041181e6feae3b579b276ef96239632ecc0ebe9fed20d805b83b1d532862b7536b48712565f53969a1af04675dd44cd4f4a953868116f2e3027e263e340f68ac37c12a2338efe4afb4d2090ca66d47ea3acd3aa87980a3f09f25144dc2433736210eba8a5d7163333c37d4e993ffe7f1f8bd08cdc3853ddc08a6b5f85d14d1010001	\\xcb150425f5723033896b03b643d2c3cbccbf857182df3e6dacf38782652336cf49c4eaaf005ba5b59b2ca0fa1b5ec22029a2e60fa8ae22bdb7dbaa0814ab1f08	1667474591000000	1668079391000000	1731151391000000	1825759391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
288	\\xd2b668d806207ae77ee4599131fa84809df6c9cadd0ccdb0ff979e1fb21fcdf08ed1afcbc88bbd4027fa2a6e2d705e9da10583fa394b33e090630fbb9c4502ca	1	0	\\x000000010000000000800003a62b1b921bab8a47be2aab189dee93d9f51c6e65e5da9437b03830eaa0a0cb05f661ab02da2beb74f1e91b91465ec92a498131e8bab0db355d2c57f29f6fe8d73ef2d9830a8b6d82858d0c77d580cdc286ab1a52bbb4276029a18f077985c53b8bd60d4468bdee524a49cc67161a7f3115960798821544556d84d0adaab53a05010001	\\x4b4ff7a80cfeabe9da2ad52db028fd30bc9fa7bfd0f0c472adda366a6ad8d3079d38dd6810b93a5bb9c9c35cbc48a1a8129c4af57fb6799a4ab62aada2d7b404	1673519591000000	1674124391000000	1737196391000000	1831804391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xd42646eea0f97c51c26459d1ccb3025b2b4e02111b4501097feb9d256277add61fdae50142d5c9dc3c89d40cb892022de92504f97117261ec96382166a6c7afd	1	0	\\x000000010000000000800003c380bbd376065162e5f4925de0734a6effa0cefbe9945cfec71aa003d79f3cf0b30ef4c98f8eefde8ed53cb52dc4b9104558c1aff273ee739a10a6b18658f834f63098bfd1dbf7cefce0b082d7675d0a21c1e4da0fd7867313937f6723db389a0890df73fb0060968787416e256cbcc211300e6fd2c2426db06c163e977176e7010001	\\x92676f2d335239c6066a4d2e727fe47af5c060a473779ec544aaec24e86570d94e41d3ed3f38c5ff7726e40f65809482b59cb90e59293404612abe70c107c508	1656593591000000	1657198391000000	1720270391000000	1814878391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xd51a453a03c4a6ac880a1b8f85dbd06975718797e3c95001d0786037729433b296e7e871491f16407a5cc6cf66f7c0164680e0f16441625ce3769a8e82fe7dd9	1	0	\\x000000010000000000800003d20c23c25a358039dbe0819d58768d2fc4ba469aa76ec1c6de49b59f1bd6c04c3744ec0f712ba2a7a9c0d1dc9a35db1b2d298c7c2882c8e88671894e9ebbfc52a2c209171445ff44a29f0ab403eef506ea09039ca8af7c3a31013c244d49a9a4cf6ea9edbe7ee84001d20374ada63e718157e358b16826cd290b460e05bfcc9f010001	\\x9d73b5197c028fcd59fd489f976348bbd3ff3471b2eaea7afccbf974ae5b870656abb25c97181ad8901cd559ad1c94b39673f0bee62e1e81aaee1f6a12196a0d	1672310591000000	1672915391000000	1735987391000000	1830595391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xd51a5a6ebe39d3b683f6f4e29a855740decffdee14e03c6330d41cc09a61bcf61aacf92e791cb0fed38cb345cde9e1226e2e178c0d7ca5e88decbd0db4d3d6a1	1	0	\\x000000010000000000800003ac0b16c62f71082d929149f18b98bea562eaac7c81bb49c4bc25d088dce4b323f0b37dbda984b31a70242aaca8d29132dc1ecd39b5882af00ea05b54b05b845bae45f36307a37e298e0893e7a3381ca1dd54f1f1b4c0c8cae2a8402f6d9c32eaec5143c3502fbb191ba10c44ce73f015284800fcfc0f09fc40c73b011f1afb1d010001	\\xa3f6a7eeeaa1a2f3f92840f07da9628d1755b889d85edf4a44f730fe1b6b253333ff0711e722bb4f390d424cf7cb5406580e7502018329339e23ab68d2012208	1661429591000000	1662034391000000	1725106391000000	1819714391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
292	\\xd7bea1a7b2e1c93f9c2437190224b4a3b945f30f59bb43e8bfd373fe151ac6882966a46fffcb62957f02a8aa0ad7a634a30651a1a8a1988314541cdb2470dcc0	1	0	\\x000000010000000000800003bf65f619b9595f8e4962cb7e0c24b5392f99460962b0d598d1bd100a67f03a3dfa9efc56f11f66f0dac83fac86e16d51346aa01d412560fd3a56640d12806e9f9f58c260cc0318e5c27e7c42f11e01ccff0dc94c39b9cd9a642f07e3903d30257eaf489480d2fa73dfa62a668204d6f4f45204a62e60ec1dd53f451829be75cb010001	\\x98e3646d5fa607975a0cd452fce0c4167630b6afb8bfb139186074c95e007fdbb51f472436809a5a25214929a9b805351d672296e35e6a4a3bfe2ccd5a509200	1655384591000000	1655989391000000	1719061391000000	1813669391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xd766215dab9396bcd6a4fc0416a8696470399973fa63a42e536f9172acadc45380db0fca5381b20b91f45818fea44b53d701df62c78a407300f66ffa71668afa	1	0	\\x000000010000000000800003a7693238c55506eec7641958af7f7a3509de5ace2a013ba7aa2d58da585ed71382b72dfd5774bcfc46a246bbba7bfd19b33471a52cd3b845d02bddd3cad5b5a4166e022f288042d5252e84a75e899af196ae1c5596d524df337a5b7b24be79015b64bcd06c9f3e3f9d27dbd301738b39a99d3b5f92d4142e15acac25820a37e3010001	\\x8b50007070626e471f6ae822f749c228f91a1d9ed5dfc799badd168f09afe3aed81914666a2ecf7003fe9af3790a6e169ff7f4a42d8fe4b988f14d3010977c02	1661429591000000	1662034391000000	1725106391000000	1819714391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
294	\\xdaaef40c25ddd19fb2cb230c441b11700c947552b648566f0326b3325b7922d6900eb20c259ffc013275a68e7f68c0276d28cf2257b90b9ecf694c7062aafa69	1	0	\\x000000010000000000800003c26fa9d90e3a525ae6e5548f4eacd5a5c38ff0635998920eb50d6f9b5a79075cc69b01e37acdf56266baaf1df222fb6dd819abfa1588204ab9e236065196d4aa45206c400b60a5d9f70a8a6bb3e940ce27b9a08b73c485dfcf09d5e58ad3509790fab79a27a0c9dee7c9a2a9af514316cf83e2f6bec3d08fee7655661467e5cd010001	\\xbbc3a5ac9c549e07fed15ea4ec311f58c14fe50a16dccfc1229fbd7149cb329041892cfc4db174e7c621c3b4b35fa632d329da64fa9990ca4ee74f6bdde4e707	1666265591000000	1666870391000000	1729942391000000	1824550391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
295	\\xdcc208b11d0e25a18e07d4e4764ed1837880d7c32712bb14d39ab3b923faa61538a40f3fed58becffb35caffd0746f4065c7dce57463131683dcf83423192563	1	0	\\x000000010000000000800003c41ad09ea8c7e6f5128f67c9e3c20b21700c9d9358a57bc8a19d154e8ee0ae63db78265e9fa314e0e4d31436632337c6ed5df825107a2c0638a7780d709776931c718f0a446db78a33f6cf05e62c50e7f126fbc8adcd117d21430aa114cb54de9259ba66a7eea8afbf3db5639fac422d54669b896460b9719a369b35c294b157010001	\\x38205cbea7082549ccd4ac7c003b1953b6503ab665bc61c1179568fcf4629d3567f7a518c83d87adab9417af985ada30b89ab3638751094be234545d1fde5a08	1667474591000000	1668079391000000	1731151391000000	1825759391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xdd064295fa33f60d043d8ad4a14bd602d146ca7bddd21fbdc1297d56e80746a14cccd74616cee552df8bfe9904343086b4a286832e4594b3b4cc933fe0a3c9da	1	0	\\x000000010000000000800003d0f985a32f88e9df0d2a57900970ca0792607941b0c9aff6191e40d90e8772de73028a4e349efb612b67384e0194ea0818608908946de2fdf48097a40163cedd5b5c0549ed681408a9775c3bf400d51ca2c6ead833069d1ad241cb5ce019e3fd953425df5361be79b441e169585335912cd5edefb9d726a4a128cbfc39d515d3010001	\\x498be9ef332d6423d174847a0289197f9dbc53e6e5890d3a27c22612bc7b06d746091e109bec193cecbb2af146caf8b1fb550024d2f849c6373fefa04ef32401	1659011591000000	1659616391000000	1722688391000000	1817296391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
297	\\xdef6874cf83afe67608d4f0af580434a752b8d3475cb49c0a4d88149c8cbd829d1f21b4131361fdc00e20d6aa6ae5baeebc85c89e96ab4731b8a2fb965aeb930	1	0	\\x000000010000000000800003aa7cae781630e1f8a8cae6f1dd4f4d9c6c0c01233aac4bdbbec9e549e4eb09b23a55b3d84db4c464757f0c2a5cb5b4d76f4fb415f3607d193d3ee6689ad2b5813577fcddf285b7e864fdc635d01f5b631c09c2f6cc34bda8d16ad4980e1fab0d70a6fb4218150598fcb39b961086bde24d0eb47b51ea49e3080e571038730def010001	\\x4eddbdb776a4e807b984b0ff7c164dececd370eb5e6596475555e86bf5c9009d9c2ff29228cd662f6cfd74cd1418775b058f4cfd82a90c455c43e4554be0ea01	1665056591000000	1665661391000000	1728733391000000	1823341391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xe1729676e89a15c96e8005338308e734629c18a3cc4078beee6a5de7087049af3e3b2905516637981a0d1bfa1183edbcc03db4082c30b6bf0766c24c1322a359	1	0	\\x000000010000000000800003cb77d99984b8e5dbfdcfee2507ac83a24e59cc2680e80c46f1275991494806be58bbcac77fa8c096da8b83d08233bef8f5cbc4693d9aa0a9e59a8b8fd7eb928bfd133f856c45870036c454b8d14cb3b794c7bb7f5bc6322aae37d2dfb8ca6936c178057e61b7297d8d4c87f69258ec90a4591499c2cb3cf89486a67b586c165d010001	\\xefd8eda4136be3b39e113efe65adb4bcf1f0a55047c2f45e1911277fe29b409da527c7be2a89e321b8c4c2ecf98d3b5abc4c8f9212032f3283b292ef8c214706	1675937591000000	1676542391000000	1739614391000000	1834222391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
299	\\xe2aaa2923e368bf063f2700b138715ed15756d9c8056bd0f79506246fa7f90b7b80de9c4f2b011db1cd2d4b511bf9435d62c14e044d17ad81d8e4dc3891df63d	1	0	\\x000000010000000000800003f4fc4d91ff149b3dd74d3cfa5083c2a233b12a1aec71bd7dd6cff07ca9e8c5ee8747d3223765612fcf75ded73ce43da136692bba10df1dcb656db00a2b8038e0eb9c50863969f5be64784d8c32cb0e6960a7783b47ee9f2007630a1701c3e11f82d80adcaceb38aea3dfad85109a69f19020db384d5e4bc55987bf464ee1b2a1010001	\\x3989327b6072ef573a49340c27056d0b8be2eb34c33f9df60bb780f6dee53080a2999b01516db45174bcc19b6a5fff6f8ef8410f6cb647914bc5b0513614670b	1668079091000000	1668683891000000	1731755891000000	1826363891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xeb6e1575c21688bdacefaca475c7d66c3d4b647b04a0284ea7d97d460cec4803829cf99baf703957cc4f72382c2e8bc3af6a38794e9e61f8787a6d6c29eee21d	1	0	\\x000000010000000000800003de21a9f50f4ad9632fdfd752e12d1e9b601be1ab38c5f3e7d8c6ea82cb14fcfa45934953cc9b4a1c830d83810d2c157d7a70a4d0f54258f77841d14debb4438c0bde43f16e5e77e651413e055e1efd1d020ffd53c7dc5f40a993e93b71af5b6f39f879cef0e42c2fd7a7baecf347bfedf5d4c1dd7bbe5de8e971adde880b9105010001	\\x184f33b72236bd5f78692077a5f643916eb06181366161af442e9d4c3ea81077390575ed2a3ed5e42eac6f8a86be777c1ab7607f8003583fc41d3aa2d611750c	1654780091000000	1655384891000000	1718456891000000	1813064891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
301	\\xed1e5d21bc64eba494cb79bf1e9746774c3f6fefd6fb78fba9c8ed07dc3f56d5c8d3c8968f464076c868bc151b3894924c1f300fe5bbc394221b469a294ab59e	1	0	\\x000000010000000000800003a7e935a163a7f1aa4e1edabaf6ca682953c13268230a08cd6f5ec15b6f5afcd5a95c87b199e263de21da8fb3d3dd628ed8083a77cc1d249ae71923340893fc89ef05f21f75f8cded18d1cd61ad47833756c2c258e5ced5cd2ee68d0ef92078b2215b6f2b5f2d3c1c5b1070c95aef8bc5096aa150597dc52d91019e0351eb3141010001	\\x591b0220c48c1a6633422be7c52bb48ac10921973849f121e314d4b137372088d53440ac75b482eb886c38be393f75f4d765846f64fbb36cd83785f922412c09	1654780091000000	1655384891000000	1718456891000000	1813064891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xf13253c91a99aca95672608da5aa50311f941a075267f01ca0907e414afa117344d8648b2721d81fd6a205c96843ebec37b75120cc75a18c267c91b994c8cfbb	1	0	\\x000000010000000000800003a0556531adc6422c5576e8131991d5c1a519d7f28277cb1ac26e7f3c3273d26d2b3c64416e523385d0e782eb02ff096b1d82402fcdc4847d038466efe1b28287429371323dc8de15df1ff413caba0ba0609b8210fa341267562d519da3916080f1da21bda2ec2606998e15e4023b9cf6f30a0cfe2032b6dbe1a899f4c42602cb010001	\\xcbb2923fe20e0107406651ba046f5990c314f76330d3f62e50e628f771d9552b4ff6d2070fd4a70c387bb53b26f4f71c5a1d76af24c784f7b7f2583f4e8d3100	1664452091000000	1665056891000000	1728128891000000	1822736891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xf3eec0261a7ed59ca27855b9d8438d84ff25f3ed23d4713392a94ec9f30bb4925c9d5d8eff03ab4053527008b430a63c99a6b5b0bc65b7c557b934f36d18236f	1	0	\\x000000010000000000800003c176fd599d05823c5210e16a90205a99d91fe54fa7ff029f4f0e09eda26c86925f975ebdae7783b9fb7b5ccfaf521d558b6f223316cd08660bf9eacdc0c590683c860ece5c4d7bfefbeb710f082d7e3ad62d41fba66816095e08f97e9f9a9591e038413a9b1ce45fbec9c7147fe9948ff6d863e90f8118f4f2cbbde3ab9247d7010001	\\x0efb810ec216d25230c84f386fcdd8ef31a5c2bccd601cf64d3e99f3b5438ecbac2a78bb892316c7de25021c1169f039dacb90c0fbc0cfea3deff7c5f0e8360a	1663847591000000	1664452391000000	1727524391000000	1822132391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xf8ee3be68e2fcbb6428d53b5441225b28a4c2d96bcb1036b90f20f2b7cf7e647e78d6f96b31b6a73e7eb777434ba49887a4d8a71724363b81a17bba580af8a14	1	0	\\x000000010000000000800003cbb7b01bec824b7b9e765ed23b58faee2fefc8db0441475b4da24e4ae6f2c16b8bd9b5798e096bc47b18ef03c724c0ef5cbe4b340d38f2170b73a2a7d9aab7d1650a0039ca6018d7d5f03dfbbfc60105f7d965aee3d20cb05baad22b0ea2cf6cf9169f38cdde92cd003198af9457329425fdd9dfc06852ff5b5ff0a730684a65010001	\\xe82ad7ac2638e8a2095a01315781fd906351a17934d2bb78940de70e15f3cbf9032db31343313abe42242646144013b2aa3c7abd1f0c63f41e62be16ad75b40e	1665661091000000	1666265891000000	1729337891000000	1823945891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
305	\\xf9ee1526599c6034f55da52ea31cde53d8ff6603797b3ddce5d055b006d2e1b6c9fed831ca82deeecb9d92d4b4aa56d3b0e085a958a46320758c29c6fab694a5	1	0	\\x000000010000000000800003c4ca3a0fb0891a4eeb29ac1701751920c2d0e0859cc63384aea63c077c7152f88e9f645e84c6b61ecd67abb12a21af2e1f3402ce400c8bbfcdbd82ab62051a3d8ecfd4238317a4903c50078e1ff68a41e1231733e5a118e3aeed7a4df0448d21492b97f5486042e95634f1b7923887d18568d566bbc66ce9ebaa6824130f2bcd010001	\\x158d6694e85598953d2f98a6cb470d03b4215ba91d24be5e9381d7005f3cca695e0891be9ff770af7f89325befdc6e0dee7a68d092714b0434853c8dc5a8e004	1653571091000000	1654175891000000	1717247891000000	1811855891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
306	\\xfb56ea2c2cca8de9df0f09bf8580ac4a5523981c70f614eb0224a8e5a79634bc8d175ef370128d1f473c1dd356abb4cc155f7e233d0ccf5e9222fe9a3a5e4902	1	0	\\x000000010000000000800003d46aa20539cee58d4f6a4b0780b92a690dfd5cb4aaad7af7061775c63214b59333d2110b19b64a14047d51036effa42f61dbc4914d8562b4a88827befd45f620f6012ec00bef55a255698bb234a71acaf8f608581fc2c1fe0cb45e1b4347ad085ae9a8ce420784d6316632d049550911ce2de831acc289f20eb9422d313efe0d010001	\\x3ceef0dafc92250b5d21df18600f5a28b932f7dfaf0f55321f43cfbdc2467fb3590fcca438c6b845b9c0ff08340552405a40dab4bccbc6a58d9c2bd5d8341008	1665056591000000	1665661391000000	1728733391000000	1823341391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
307	\\xfdd2eb9bb5efb27e5db02d228ea7d044ef895f4bcaa06232289190195e1e566f132eafd5cc8b8d0b237ee34c969f9252e9b444bca1dacce628c7295fc344978d	1	0	\\x000000010000000000800003c48ba213c3248aa3a36e940d1fea365535d8d3aa6d3dcfbfb03ad8b47a08fcca2f7a194db17e27a04f107ce347a926471cd47f1f9921a559b26289324285508154c95ed1291efb9906d617498a4b08d28c4084ac459d455a77b3f8c81e849d3b0fd208f7e21f811b9a5e60952bb08c1d9cef17ff4402ce6037c45b424329e95d010001	\\xc66c10246176ddf280015e17f3e5c49f1fa75cdf52f483dded01a57852b261c9ad1e5cac1a3a17e292830d05e6ffa7f6ded3ed40151817572780e4092e6fb10d	1657198091000000	1657802891000000	1720874891000000	1815482891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
308	\\xfeaa81e9d45d450926038448ba05e8495360eba42109fc6b379e4fc3da8b56871619fc7580edcc8c31df65a4546200aa44d5a6f1e3ebbad976d5835e48fae68f	1	0	\\x000000010000000000800003cd47039548c1fdc9b5bf977efdfd4cf965ad35662be300980c5e09cf2e1267d6cc47e2339aaf4732701d30c2db69b5d1048f6385d1d9a2e53c701d9c83eb3dea7c62f52144a6d94412ca697efd6e6837e399192ca6bfe8ad5d9540b8bf9f5ed11fd1ecfedef6c2417d6fabddc4b1ec45150531fa1075affca6de14f1e8b82cd7010001	\\x37b421af5493da37fc0f16ac8a6cfe9e7050f82919f50d1e2bc6e9d200b4b6c0947d56781f3c891fd5e14cc58009ba3f6f51660a8241e8b786cc950490ed960f	1677146591000000	1677751391000000	1740823391000000	1835431391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\x02930cdb03f32c58c6f81a66e612f2045c250ba5cb158ad466d9712934d60f3cbfc74c0b66ec5bec49305bedf340fef17289698d4173a36e16fe5896dd6ab272	1	0	\\x000000010000000000800003afafa94e04ec2205e2eb45e4981aff4f835dd47b748328d4a371cdb70f919b17dcda5c458f676405c003ecf8730a16718ee344d1ae9ddad86516552654c2ce0d45f2c9234fe2cd43870d71d83bcca15f45148da7a07b4b61e3db9c2c3c28fb6b19e66cb6a0866727d7ab4d9259b7797145df1258857a7facee01633ed15fa6fd010001	\\xf761624ef8a2efdba98a2fd28d8b9fee28ca89cb948cb8f15e4ea859187cbafd83a8fd272cac2acc7bfcd19a3cf7223ffd55070e73bad10f6d904ea564644105	1663243091000000	1663847891000000	1726919891000000	1821527891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
310	\\x06676e267480f83acbd0e5073ddf81d3c91d4df1923db10055cb6df1be17b1e28ced3988b7a8fa472f5be0de2086254cf26343db20e022324b98f5faff82038d	1	0	\\x000000010000000000800003be2459300e3f787504df7de21e3b4b80b1f68649d20cc45db6d256cda8478e8ff911ad3311c224a471f1cf3bedc960b964eab5f599b341d48f99d9236c747ef12bd627a0c8a80bdc5c88c95d752e2b0559831dc75aa2482ab401f8baad2be51b9e5ed86f26d2b4694bd503893ec0436b0df3402a8cb55d1bc6469b7513560489010001	\\x3bd3104761c00dd454851f24bb1d7e5f9ff04000d2df9cbe04485277beef63b6ef668e0458d3006b1179841f89521a1ce5d3711ec629e858691edbb9a8ca6608	1671706091000000	1672310891000000	1735382891000000	1829990891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
311	\\x08dfdaa5721db1be4455f3daa24c38f7063bea8033d6b7bb29ce9fc73387342545e011b5ab94e9605b4dd1d3126756e258cc2bf1a020d0b1c6f8f21ec2d6f98b	1	0	\\x000000010000000000800003b432155665581c9c241fd56047e3e795a78fcf57ebca13fb2d9eabe2b5e62088f118104eabfc62e15ffd237af430f8f65a4cea1c10daff164c9d4dd21e88175fc1a3479b03efca4e3ac2c38468c454537f4b4814581f658ebf1ef14994a4e2cef827b837f317a6bfec4a726c6fbbc12bcc6580593b59f1c6b96b55cf7f660907010001	\\x961090912c8acfbc2cbde997385b27f702a4839ba10d360565bf75b4b087c997a40d5eadfcbb6c9e7b1fd87a6730f8a38c1f8b25943c57d95bd97fabf3fba303	1667474591000000	1668079391000000	1731151391000000	1825759391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
312	\\x08cb3ddfb425db863183c6c3966431e50c316836bd8eb353aeeaed4239a10b227d902d739568667530e26764e008dc097b2c5217c841b7b70ebbaef815065757	1	0	\\x000000010000000000800003c214943fa1c16bc9f1b937c1057b37202fbe0add6ccd02efa619c15b05308ed2831a82ff6f4039bd133b947590a3adf384fe4c9b2ddf39d52b43f430300406b911ff7f8cc5bdb75264cfe5ac7e59acbca12c1fe17bbb07f81479ec7edb8ecb482956d307fbdb5c009f5bc969e292fbfda8bc673ddca4c2dcf7d5d29c1fdd2d51010001	\\x0c29c789f1f38002af37b36442e0eab222b46504744aaed77bf44ff2da42eed1f03b3dc55c32ed651f9c19b6cc5ab4d923f8896b86763184c3759b58aa95c302	1665661091000000	1666265891000000	1729337891000000	1823945891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
313	\\x0a7b4846aa324d2f37d1286306b52e994b23e13aae72d7f4b5b82279c8d867363efb7559f36765a3fd202d98d9f54b92f2037e79e23fcb2f279affca4b90a0df	1	0	\\x000000010000000000800003e8b82ff4760719be6caa40b9625fee4279d57c4693c29eea611f03d258041005b79d03c62bdc494ee710ee7301cfb27244586eb5b1c91f3059366d092cb9896e80ba92995b022e661988380e8efd5f2b05aeb0a9d5fd829d7695b73b40bfe3f4f6aad72723504f1f1d52e2e9f7fee3a18ee9a457d3c4b568df34a4c797e1ade1010001	\\x2d4b55cc199f271cc9e50d625f9ea284e2ba85faaa2b8316a9ebc8ed6267c7c058222c88922c77fb9def5646e52a462c97d50f5b916d91ad6bc2a4d63c29390a	1675937591000000	1676542391000000	1739614391000000	1834222391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
314	\\x0e776a70b895ef5e454b05722510762ecf37fae5ad7d438373bf18ad63f74ba9a7f2ee75614cf5a68044bc77e228d5406c5eb6fc186331f8d3ef36019b4b76cf	1	0	\\x0000000100000000008000039b494629c6df569f7086874612196f06d61aa71b4aa1209a8839caff65313ccc58089634fb0a64824b445627f27ec219b8383ac9c50c50041bc43b010496ab2c916ef540e8e619b1f46272d3277641d6924315159128d220541c7e17b80b44365fde6cfdc2f57ee118f985c3285531a7a0642b05eeab52a83bee217a1acbc61b010001	\\xa99bb78b1cf43c9a7776b196aa605ed7c81d67fca51f4cc34121e8afe49d72d7231d4c65dd8a1736c94364b1404a90bcc96bc81556c06a38b43eccca8bad9606	1669892591000000	1670497391000000	1733569391000000	1828177391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
315	\\x0fa388291b08ae47deade9ba08447e2080d15c04890189407b87709e3c78f3cd3e7de673cd79269f907d68ad62257ec8e3f548d5edf90e2c769bdeec9993f0a5	1	0	\\x000000010000000000800003c6918bad21705ae8aa0f85c4a5c67e04252c1ba11425813fabbeec069ac8205e50275a6ffa801a9241144490c752c9106af99261082fc7c84ddef5c2d9daa37e8cb7be86146965a211548d2d29d2bf4f8aaa8905910d85b59ad11fdc1730c7f4f6b3e6c7b564320814bd1e02b2fca88b252f273a811c7eb7433696b8afd58e5d010001	\\x5fa31d276cbb7c1a177127b4845bcd64290450f755aeff3a71855052b54f9acbd5019bf2119ccc179252b500bc4be08656b8e5a25bd80a9bd462ddc808fe300d	1674728591000000	1675333391000000	1738405391000000	1833013391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\x0f471c8cf2f15a22524b523e676408702cf3ac0203053fb84b0227ba42b15fb0daf07bd6150b208a4677aaf2f3eee0f092b55a9c39f6773f643e6cc9bc61d6a9	1	0	\\x000000010000000000800003c1f1222f28d4a0b188308be9ff696c3662143759fdff4de41b41d0a7150ce92925c2c9a17ac97a267ced2fa3e793ff83f8412728905d671936e8ee2bacbf4d896a8f199d890dfe089db4ccc9fe9e11ef2ebaf6381f24434ae10c683fa9b95203d287819ffac1529495beaab43b1aacd783373d5e8eac422013eb373c0eab0a51010001	\\x3c2e6b2840c3004a03fdf237f3cb8efe22ae918b5dfbc39cfe33565317e2581f3bb73a13edaf7e7b83d89daf758f914e30a24e928c72a85ee263e16b79850c05	1677146591000000	1677751391000000	1740823391000000	1835431391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
317	\\x169713d9f044d156cd9769e8f3485eac83ffab440b3589f3c755aff7cd11b54b4a46d29b38c625b7eca850be7d3ab9cebdd81502b2ea5fb7b688e4dc6f009e24	1	0	\\x000000010000000000800003c1136b8cc3bda065b6befc74dff869053213ceb8aa524e23d4fb7d3715af5a42f005e53f3abffb885ea01ba4cb1d5dacc9b331cbe6aabad5b0bb6b0d694933ecb6f6cb9256077c9e94f8ca70f7307e43e52c7c18cdc5b3b4adb27835e8665937384a0617cbb40a0193e83931615fbe2b47be4b080a4fab7915eeab5e42afb8f9010001	\\x38b2503e392840d6b3a3e4f852bf539feb95125e60002dea3e874911dff7a711dddfd558ef78b287f00eaa9358d4e2a9c7d050a4b773d31032dd18f31d529802	1660825091000000	1661429891000000	1724501891000000	1819109891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
318	\\x176bd8a04283cfcffe5ca502d094f8571ab5debbcf469a89e07f7d1010452616ebf80c9cc180e2a3b78811b99c35974b65a351bbaef65cfb14a8f28ec4641897	1	0	\\x000000010000000000800003ca075242fdce3f108698a634f4b85bd94e1d32f4903f52068297490a734514ae7fd445b691ad37971bc218460bd783ef5d9e8fe94ec1bc28249180ba76928837af6f09d9ec63a08461f04cc43a37349c8614014cf4546542ce89abb26ce1f6b269df41031c13265538677c7b33d1191a085509c091f31f875e4b4a812814e48b010001	\\xaefdbb0dfe38aaae136a1f66b1c89aa6709a6e569af55e9f48983dac5db86e239391c188624abc7db70d3190db2fe27fa6f877f98a90512f78493e7b41c18b0c	1663847591000000	1664452391000000	1727524391000000	1822132391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
319	\\x18b38b4d4f5999f30eb8d13a5754d0a2090b600dda9580e4f0069e52cf0a80c9c0cb135c5164a863c113c2248a92430db03d0dc08c6092a91ea883d3203dbed5	1	0	\\x000000010000000000800003c95c8e649352d1b93b6424489ac70945a6e64eb5058e473c956671c35d01ca8d8d6907d7acb0817367aa5ae3026cf366c47851775707a97557d495b6846a9f10de0625686d969aa8033bc796fbc71ac733f6d62a9540fc45ce29e0fa822461971640d3f9259ee883cf50148ad0edf0372aee7dc1e7fdc28923babc0e0bfe9a39010001	\\xeb6f0e652901c787fe5d027eb8f9e180ddce257bf008483182bf28bb81323457dbf29727fa198d176b8e112a397baaf0789be14c215fb95e3082401bc7fe3e0b	1662638591000000	1663243391000000	1726315391000000	1820923391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
320	\\x1b07c4ebf3ba2d041fc645ae37a879d972dc498c09b31f1ec52a781aff4fa1d8181657481485d83c315d18630c4e017df99549e486216adc9a05e7fd5d97463d	1	0	\\x000000010000000000800003d619f3a5f1a57a937f714bdab196a96d980821f92c9c601adf093ce73d2a9f85877e061b2fbdfc79306b26263db5b4a119655820269cad1fb1d964f72e8fb08ca5730ce3ac257c5853e269de77e588ed52338c16a2f4159f9dfaa60c6f79246e1569e7489a5efd97c43a656301a7951f84d04342d891114a12fcad5cfe6e882d010001	\\xb5499a19f455723ba394d605848bda5a7d262c611f5801a2b2edea78a478cc4a24397ab1fded922dd5abf0c015e0b995a18906ab6f6640417b6daaebab75fb0c	1675937591000000	1676542391000000	1739614391000000	1834222391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
321	\\x1f6f729ce8d9c550b5b2624c01cd4d12768271f0f6e467446c07e0149ddf047a185f05fffde2a323f2b6ad4aa7206a0a09778e453c41df772685d3e68057356b	1	0	\\x000000010000000000800003de59cb60cfc7a47918258ccdafecd7d4e352e9632f609d8cac073eed8188589fd6b11270fe630e27ce8d3a099ccf86a6c2f7b4960da180916bf03d8a1a45e9e5634d421581a9a29a66084b7956536415aa5a8897ff0f3bda10d54636b6f3d766c988158d3c9df7db311e258f314436a084131eb75502fff22fe239ce84f163f3010001	\\x1e325044a75505196659c5285bbd6eef2dca7311681b6019b67e52b17833aabcaeff4c623332943e919d562cc2b3c9c4374a8c2d454a88ceb302e9001ea0f30e	1649339591000000	1649944391000000	1713016391000000	1807624391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
322	\\x204be036cefd981022fca307835f312bfab706572eb5279cab7b8e110f400a6c818fb5323edd05a6f5661bb8d6f9b1097dce417e9ef008586026df88ea7eec28	1	0	\\x000000010000000000800003ccfcec0208d27074702f1103f8c081e7081da37a125c4bbb44e8b8753be325ed83f10b09191869d1335e0a82f335636f69efd712565a5a55ef1e5431ddce7855406b4dead213dc178f380dd737ab13c1ce5c696590f9fe85e60929fe10aa6f35bf3acc065f58a5e665bf7444e05b88dc34c520168bfdb7386a49896e6762ad0b010001	\\x6bba9d4a7cdf227247fc6a640cc2564620d469270bcd37c74892cdaef7f160999543175954c494f4d30e4ec88ab9ede9d292854f7aff8a8841261d98a89c7d02	1660220591000000	1660825391000000	1723897391000000	1818505391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
323	\\x219319c9396a00b203f68923a2801e6b4f01932c901a2ba1a87900c2c6ac936c5859b899383a23066c3b7dfdcc6a76f1d5709684cc4a0a8be78669fd089b1917	1	0	\\x000000010000000000800003c94d6bd16fac3a47f678c0df292895b533285218eef2f0ca84a257cf3693f325d2f9eec63609dadba94e60d0bf7311d80a89e3a782f5e53b1be5a031d4069e7a9d529b85a2f9de1dff271016859985db6186361b7038222f77d78e0b1ab2a2c65053db97043a6c9e3b9d75a90c5f0cc66d7f61a5be206fbb9007d53f85963a11010001	\\xd413ccd0a6254674f4d40d9899bb6323c29c075257bc4deb6855941bf4aa6554980da8229d92197e1b806031d4b95b773e65c4ee4765863512787706f3082507	1655384591000000	1655989391000000	1719061391000000	1813669391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x225fc74035bd77d0698190a8e1558ce4ea65c9fe6cb9dd2286919fb5d8ae3d5d7bc6d666a582420498fca8a5fbc508618ee9bf647fe8cddf4857cabf3f30f8db	1	0	\\x000000010000000000800003ae7f70537af4442da5c95fa63a6e635a78a1b72894d1d618a4e83b946fda31470abc8cb9e32374ea500f317e7633f60285d7137756c60a9f3f1aa516dfcc2eccde6e85bd730a3f147d3f11c8974a205731c9873b86d1d705751893cc8a85ef75a368f4f513cc5235423444e87995db79740c87f1b4c7d42b4ef394dcbd87050f010001	\\xbfc8973487bfc605a44bb8e1f3551a63d7078d8f5bfa41431c0f7c407a56063688b6917d68e5a2a4d835dd7a018c464909ea53807b86cfec167c193b32c3cd0c	1677146591000000	1677751391000000	1740823391000000	1835431391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
325	\\x229f8c1ce61f3abac499812940066ac1ac2a6780b0135927402e7e9732421945a484955682abfdf36d5638f13ae044e9d6e139ded6918f86688ac1b4b37dfb9f	1	0	\\x000000010000000000800003a3e3bcf942fd0001ad3193bf7aea947fbe2b744107b3765f5dd088f26c4857e17b5b7499d5159e7b7c5f5b2ada978006bcd5a7be5187a9a2e862b46485954fa468bf7738521d018490b661f0f31d4f98bb72460ace8c1bbef4e698a50afabaf6114d0217f85f8195b5769ecef8a16eb840db387b3e1edd14487a0999ab4dbb6d010001	\\x2d1047314713b8c8619af0b708d4ae4aa24cbc206e4437e9737e62cd0bc68e3766ab55dc4a6453641c24105682fa2600a8828e77575d39d3942cd15b02d20b0b	1659011591000000	1659616391000000	1722688391000000	1817296391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x2363d1256880f45cf0c4492d5bf47d33d79c4d1ab5626f561735f168aac299b97e4415bb026a8e3c2c3fb2b99914bbdc10dbefe734a42566803844fe61911b5c	1	0	\\x000000010000000000800003acdeabc06a936aaafbaf4eaa77e35762b10cc3a44c8b3ac5dd3616b1e8da150d438b5fcf1545fbdc3b802af8d59cdaeb1ca43883260429ccd645aafcecfb78b902a5f165e519b989703cd65cc45a20f1322dbaf627f762f898e611ec117c3685d12c0dbbafecfbcc2212485e3ae0e2d4533b7084e2bbc9c53d473bc5f53c3ed7010001	\\xe7c524c018d7cb685ed5d65e2eed9d8acc4c3e73280e69a50f90f2d4c4180d97f0843cd8c1cb7f13b75d94a871c022b0660f3bfca6713851d8031ef8f934eb0e	1678960091000000	1679564891000000	1742636891000000	1837244891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
327	\\x25b7ce92205d9fbc9e7cffa6f726df6a7865b0cb8ac31e119013e40bebda684f985b67f855397273c06181680c7de66c64a25c2e9ae28408cf9de94eb6af0545	1	0	\\x000000010000000000800003e4a426d94185a66ac09812c45622e547cac862b68f7c31bcbea67cf02a111108c859ad61163a00e51ab95688838ec66e6ee12b0688636f9da95f4f196f5775086753bb78b3e387f98265d2296a6f9bb5069a1afc70a7bf77130ada024cfc00e88f259d48b6dbda235824db618ad18dc279620a9769c010a732b028f5c68c5091010001	\\x5ac09f7fc1cfb6a1726d8e0b59555e9b00cec6cd88c59f1b2e1825321bf2fcd7582560f07cafd0a25fda257b4e073e8120060abacc9e5d2bbce068f1a76b820a	1673519591000000	1674124391000000	1737196391000000	1831804391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x2d7b03aeedac260702d18b16c320451569541d77e5afc9b988a45b8d1afed7983172604706b994ba27ee5ae66bf0b2e74a8f57a87cf0358e5ad85d3871b07b72	1	0	\\x000000010000000000800003a83cdd8c8de98e63e4500a9f43a3d4f34852a3d4749352a7f4dc2381e6444c2402fab13032381ab446862fa523441d8505d604f3b4425a260cc8d4c5fc663cd28c7be2e7c888bed52a42fd6ad65d484b8437cc58f38fbb250de02e7a13bbd8ded3b857813cfc1a1ab037497bb136771c6b56ada6a7e8d2119ff38d76748c1bbf010001	\\xf46b39f12d1096d560f987ebc3f8e6d13671b46c0f28ca91ceb3fde0c17735609ed8219374f5263a95ee27396a45be1379941aea583fd872d8b9981c24b92903	1666265591000000	1666870391000000	1729942391000000	1824550391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
329	\\x2ef3e804dbbed02671f10b50d040f6e0b2bcbc306d578d0fd27cfbe62c4828b144cf1bd7b8193a803a403231cca951a69bb01aa04c713a2e5b39df309320c940	1	0	\\x0000000100000000008000039be5789b331534749909b5e4c65bda9e6f6009a08b6ebbc82cabb28201a32484111ae70483cdd9195ea3e9bf408c0922f14cacda6957af3288d87842d27741199726bfa5e51a2d622ffbee1031c601077d30d890ef308fb70ad36b93be5da301dc19185bde0f8dd8cf397bb8bea5263c3b4e77e71c784e06a2d47f23815be94d010001	\\x3f5aede34afb1c4092b9186f682949027abbc828c3f017614be5b0f0516abbcaae7dac29333b7129e8c59bb5252442a1595184668788f0f0cf26ad6cafe13607	1658407091000000	1659011891000000	1722083891000000	1816691891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
330	\\x312391e9d09e47f96caff45215246926530c44e352ffd4672bda25aff6e97852ad52fe4c1754868b775007d4f533921f0aeab6fdc911541718ee4a22c880d859	1	0	\\x000000010000000000800003af686342542ef10c404ad599031a09bf86dd4fca1cc7addef4eb509f8db3a369b5e9a3319b6b5c7877bded51ed6e709bf0c3073cdee971be79199acfe1274c9fa90c52cf13493809317549e5244452cccceb1c2f82d098e34b62269a9af7d5f1e1a09517df88be6498b8810457532a09c3582c77dbf45bad9f777ddbfe122689010001	\\x46d59e61013d131949435f866eb64390067523ecc24701a4a28c21068675d974ab5d0df45488b37e20077eb4453bc3238915a04358e68b8d9f1f8aafe2649304	1674124091000000	1674728891000000	1737800891000000	1832408891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
331	\\x341359595fecd2edf799ffbd83689d1a3905c34ac7cb531808d32440fbb3adb7e89240e32def4ab7463a2f1ba64cf9cfc9c37ba7c9418405cc5f74306fc75837	1	0	\\x000000010000000000800003ad26d26bfd2703c595d70b8c6f80bde436e1316d01b6841510190a6ded05f37436195732991241c3aff29c3e6e63a19ae8ba00e88222d46b11d653bab96007fe143fa3b182a95c027a30ded509ea8cbdfaef0cfe87f88f5f7a8b515482d4beb57f0cbd1d7ad80e7845fd73bc089379aebc12a8699c2d6e957088113aec3697c5010001	\\x7eefb551f11507d29cd2c3e5053cf5f4670f5e8d2f41c16222db7bfb25693120b7cdd5bf0fd9c090471842b3bf8f23231f4773d1d05cbef78395a2db86ef2d0b	1662638591000000	1663243391000000	1726315391000000	1820923391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x37d75611329c8861552166d1c2a8f5b129e2207585934952089912943dece068ecf73cc8a2348780457680ef896bd03cea36358cc1d5d866ee94ca5bcee355d2	1	0	\\x000000010000000000800003be604cdc170d6dfbfbeeb39712f639353b4bf0b9ad9d067c2d34b19f568a7bdbf01974caaf21a93d455cc7b8e81491a7803e4ce2dd1c6fbe772c206347820d133ed89d6e69d481eae06bf0b8a7a352f9eb12cb8636a17ff03e9335dc3993498a5a99b0fe8dd296ae0ea2cb42bbc6ebc4b59aa01d3203fee989a5cd427ce827eb010001	\\xdf122631921a3a4db033cfc3291a50fafd2f6b3b694cf72838082849b4918b4763d4fca5846df5724bf460cc557bc6b123acd510399dbb01c4a3bfa126ceb20a	1654175591000000	1654780391000000	1717852391000000	1812460391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
333	\\x39b76401005b8ad73b4cefabb835307771f06ec5c7850812e95064d304d627f73b2798738da9af50b04b38ce15fd8e9d13c8273b5c1883a422660d76f410efcc	1	0	\\x000000010000000000800003e2f7af940b2524e0d4a43dacf371d44d98d516e26e516eb4e460ea74dc0e18448c0a785f5bbc9ca24e5c27510c8f011333b5186e2e969bc48b49184218e14203a7b6c6111b287447baea2efc280b93770666ac868ce333c2563be0f59fee040a363b491f8c9625c44738e8e30dfa17927f584cfd24c17535d1290aae396c641f010001	\\xb20d65c8f08c7b11aff68bc282ff58ca075a91d5e15b137f1e098be64584b18441d5fd0fa6be5bdad6835043d726c6a825030c76d077a0a04a821ad62fa9e406	1667474591000000	1668079391000000	1731151391000000	1825759391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x3b13e154b0adb13b8360eaf0a9592f7ec28831cb10c0542f9118bd2e4063deeb1f3e52beebd2d1598f8ac9191e00fc34fd001f59c31580de927eb0fdb5eebb75	1	0	\\x000000010000000000800003deca042e9dd9f706067ecd306faef15d381b06b42e4ef47c936dd16ecccab3be402fa49bf2039b691effbba46f557345efa497a7f49e53d67d76d23dcf45574542b643ed860e0ddf7a4b9619207b5742387438cd2002dd5775a51fe31ea2d3e46e3a4efb3a0da5513e40f6bf5b9b817588937d6fa2e885e9cea0180a02f8d7c1010001	\\x3f1c43161604759e4bd16c67aa87bf7c8857279ede442b2e412e0d2550f5712df5f3d761b96e8a415b56809886e18ced472eae7dd56606b54da837853436da05	1666870091000000	1667474891000000	1730546891000000	1825154891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x3e87f0ce689a1afb86d65f49837b0f2ac6e7bdd6e58d699bfa4a00e062ef05ac3820b83c9eee651f3d3e6c63ca6d2450b388882c80b9ecb1237a60c86d67e257	1	0	\\x000000010000000000800003acabfc136c1c37d938f6b95c3a90911b4c789d458565bb4706a6bffff7fbccb638b32ffcca6dd254646ec18151753d4d33802b721ad4175c5d739c9eac28bec00340c2f791d9ddbb7e51ba5ad43dbb3c96db437e127a37f54d7cc18d14cae8c6975e82bd2ec6100b84353750e8fd2f4e7d88d3824e6319fa2bb328bc95c92c49010001	\\x52daf37cdcff5192411b1b4d25e93325c58d3fb5418cc8c07769b2375a9a1c3b50d2e371c365faa3d975ca0b54612678f2891fe57deac915a6332b194c7bce00	1656593591000000	1657198391000000	1720270391000000	1814878391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
336	\\x3f937e1edb46169d1f3614fed3365218de1a67e5f0675b521e1fdfc2387ffb333da24c51e0078f3e6b95d9f6f8d5dc3c8611d80a848dcbf49e5793decc90125d	1	0	\\x000000010000000000800003d541a80c551493d409b6a52a4338174e3c35e95c64d72835652f627ea8ec2c1f8e130824b82586569a85d433671c8962675f3aa0f1eb431394656f01ab8c7ed2242ec431bff605bb7df20895c50c5c1d073f139234855eac52efe7dd0fff98c5ca392a703a748b07a6d78d9443a2d1e6470ded9f857f69fc2aafd393e19085a9010001	\\xdddfa0c92cfdf2b2ac2550402247308b2a570c16177be0ab1dcd45906c1c939fdf8442d00c820a7b0a119a5caaa4c272033d0e7a00eb62e2d75134f57e58b70e	1651153091000000	1651757891000000	1714829891000000	1809437891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x3f6fb79e29d5bc7bd61a4cbef504ef44bcd126109dce2692f277b6c1bb4c22f2dfb961d41ee2f3ebce12ec353863e1a76554fa4aff65042dddf7b428bc2addb4	1	0	\\x000000010000000000800003f915a5d7f6273e0061048de78a15041af7b89957ee9fc6cb75a366727460a08e3fc3197b4e6cf0b7793266387501d7cae4fd750097b16d9b29fbb760adbc5adb23e370a6d26c31f1fa8dfbfc51b813d3645c442bb4893cdcee59108a49a5b010658b090ccc96ea8176d25da469199226f102d95632ee682142b118d5f79bcf95010001	\\x62fbf4e4de06481411242487ef3fcba5f1207847761f1deed5fc295fa20dd6a6fce8d85f6f79ffe7203f7a670efee011b41dbd3ac832362bd062480b5e64be0b	1661429591000000	1662034391000000	1725106391000000	1819714391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x416bdf58100b72b99411692e454be4d575d496a5a913991efd947d691a4932e724db145c0bdf3e49628a0cceb6a2bc1c2cf1f5482195a79cd3b9205452d20cea	1	0	\\x000000010000000000800003ba9f98a3e02e68ca808ec028f9420784a794999c3eb844ef4e22b4a6e07edd89d37a885d5c00e0d83cc2330c024900ce927d0175bceb36ce2f2721659251a373deebb1762d928b49214df2443205e1d3e38820518469c8c404446b69a4b69087598af71974ab242b1e613e726349b2d9a219019c894795facfbc675b950292c9010001	\\xe58bc592fd5ff9402228e78c30f9f4926522f63d8c8047f20f4539cbbd15400456e3660623e9e2dcbaf81b4d9c080cbbdab5283499876ff472dc03edc1780d05	1662034091000000	1662638891000000	1725710891000000	1820318891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x46d7b79c737e0c4af4ffdd80a9e89472953e87dee0acf6ee002bc32aea16931e3e24bb5f9859978b1a34656da6e498b5ba19c351f23a2975425d7796e2168e7f	1	0	\\x000000010000000000800003b07e2a28a512ea5c71f50cf572a49b50878a2ee9a006dbcaa595b364f5f2a07b3dac25123a0b40f95e127f0292771ec64b09c4f206f4a78cf1f124bb9a59834f62be34d745f4d5d8426b00d0f021021f1f1fbbc64710fe43be95cec2403b9401e472898cca4bb58a5781af7af97d697cca70cb9a5f029c94baace8ba5d34db4f010001	\\x47815c8833951ab8bee76e1147999ea9cb9ff3646e59a4e5e0af11d64cb3d1b1a9a7977efd50d1d93caff17f1c699c217a067c010aa5afbd31a9b5abae0b740f	1674124091000000	1674728891000000	1737800891000000	1832408891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
340	\\x48af1834884d25c870e108ccfa83a89e828f50a2c688c4b376324f031e4e40f37c55b393e48555ddfd6371d909ea6ca18c3ba1bc0721dcd7c8d532913d79fb1e	1	0	\\x000000010000000000800003ba6e4b32518a68ea5cd3e71cef9147a2fa2a2dc125b839be3d02ff3ac44916d584f82b7d76aed9410020d1890f0c18b9220d320defc0723a4b16c3b6dc897105a1f8650fdc224ec12435ce6810fdeb88817d73ff7c5e196620f81ee6be8c4dc03bcb42c71aa8c5038625008a7a8a5fd1e955d70fcab740654a7b08930b3553dd010001	\\x1e5ec38fc5fe9b1c491b7442bebcc0612b0772ee71cd953814a70b9e92a7ea9c383d9ec480bc67770799edf63d3c755caa44b0619ca93c65b6c059fd409ef600	1661429591000000	1662034391000000	1725106391000000	1819714391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x4a8379bd572b60aa847e5a036e17f8c83c2ce69e7615cb89c64845734933c9949ff7aa904cf101c486de95f2ecb4f0c1315e8da607d045c3309623061641fd9e	1	0	\\x000000010000000000800003c876eb3d98e090b92502601235e849a9e7ae3eae556f708c000a5f0c01a600a65e5377b92c1d344fdd9335c5f42dca186685f5a4c743369bea46a5bfeea7dd21498fb7266e83a1f766ff39084977e359683f78501787044a4d54d13fc9e6d953c03b06f7a78b8c5c403dbb874ae3dc45b218f06ca0ef1bcb0ba7c5c16f23fd97010001	\\xa6ecad483fafa11a6c909bef434ce1bacbbe90f34dda974c5b58147812d6d0e74ed0cab7e2c9af21ad1a6340eb7d6718fb193bed4c0ea99513ed8a370656b80d	1664452091000000	1665056891000000	1728128891000000	1822736891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
342	\\x4ae7dfff63a868b82f056860e63894fc285747b9381fd6c671963ce14c31ee76ff5ebba695e061706e2429201ddbe4d268bc864999bd3d0658f69361e73bc2a3	1	0	\\x000000010000000000800003d4b40e4fdb80fa0cd055b92f1474e181311334116724c01e2988a9c01e6cd382d556ee245a1432984f45bc4bf7de976d51280dd28a044f16ff1af2db4e12880bf7de928fbee1232e62f4a1d8539776b255254d9923a5ef5eb3b16c2f2beb3302ecc9a275dc7f9ea7e6b49b58e507b714828c4221f04743c9260dd6d93ff2e117010001	\\x19804118daa591320e5b1221d63d3a447644e836e94711d258bda92aba0f6e2a8b345f3dde23061d49eb8f029f85f1f095ac73df40ea72d6788edaf0fe632f03	1647526091000000	1648130891000000	1711202891000000	1805810891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
343	\\x4beb0788d985a2f2d6ae1c4c51a2f5b60028cdcb52991302fa5eec5fda2649fb72d6c3072229e1fbea04a057bcfae85c9d80f8c3fd536b64afd62492cffab48c	1	0	\\x000000010000000000800003aab21d3e9ffe83d548c78e118721c79cc3c101051973e2db9ca186ecdecea0cb1b2123405e91ba1eaf166a417bc72064f42dcb05eb0be07eacdbebded5ff9e4d3d431929f45e290a7ff239df940fe1441c8f720cffc40306a4122942575a10718d4f4c82465dd389861d7a1e179f8a2f5780a9c0ae12f503722052b8842b3785010001	\\x1015f14a14cd2ea31da52dbffc729b95c6e573537b7d1e57c3579052666a6fda3e8e4a11aeaa738ce680cb77f5d0b66109920fb8d91572aa38a71939f63aea0a	1671706091000000	1672310891000000	1735382891000000	1829990891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
344	\\x4c2776b0ea3dabf0c61ff556750cc6c1ebbfd7fd44b5857fd325047d5ab188fe1ac38deeee8a7f3adaca1710a8e4165ef19d9372ba3592e0789543c7303895be	1	0	\\x000000010000000000800003b38216787df0a5cfbd0fb95e77ec3429e05f488f4baf15a2315d36a4f620215628fffdf986055b0549d2a8e067069346f7695f6f2556df3d4e2f1daebf8a9d1c90c165855b64ec78f2dc780384b0a843007b455c9ad99fa42e7b389ef038aae12c0f7f5714d5db156df76b9df4186263cf24f356b08157603e2ccb1565a56a85010001	\\x7f5bd0a13d3088312f51e53d0d17b3ba2f4cf2a27f4b783d7cb3f617d2473a1bdb1b0cc493dd6dbe3518765afedcb6e9979089893a331fdf66e6654852ca8f02	1657802591000000	1658407391000000	1721479391000000	1816087391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
345	\\x51c3cc871d3c6905882df9d96508c5d8b1bd9ac6bddcb0530dd3e2c6420bd614b95d5e7b19f3b85ac3d783b71f23767a1eab2ceb7316f91b53404f2386de9f25	1	0	\\x000000010000000000800003f1ed214f0af794c74af9bd6faa3c978ffbd09b02a8bfd702e254f00702f0634554d9123508a0beb489657ae8b193804d1d1d80f853ad3d23e8bac6ea943ee68a4099d1390a2acf84debf3bd141c04630122bf7f2110dee74c18949ae70ddc7547ccd8256910bfff0161f164e9712b4f57d46c6b6cca55b495d4f0182521ab17f010001	\\xc909683b3c0df5ae2432b044de727356f9d10227ce0dec65fd4ece9d56cc5823816314b08bcc897ce291c604cd07ad86159d91d17dec560547e50c0142caa602	1656593591000000	1657198391000000	1720270391000000	1814878391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x53dbe956c39574e2f0fd14006928d86b636d43da42796bc12e6d4f0ff2e847adebf7ca87b31eec6386da087238b1635a405634f53e53c2a410c1b01faa756b53	1	0	\\x000000010000000000800003c7298bb8abbc3e3bb0741e190440249420463e9cd81a814dfb847bbdf5cbe8ddda835e2cc384a5b7d04732421d7e6ceceb06037f2d2d98ee506355dd0f0fdd6b2673c9fa951fa079364c5d64484391432d4f650f3ea5f55864198f17978629d0adeb8b3d56518a762b95a913618f83f60f38f145016289a64c841db8ef1d6fd9010001	\\x63d1724563a3e06d86e96a89849470cc08806b9b7bb2a0c80f2d6312cf284091a252123ee5993e132712327cd9f7fe80a3f1bf6e31024e88ce78409f72104204	1663847591000000	1664452391000000	1727524391000000	1822132391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x56774359460db533813b93f43e513e55b417f1c99aa5b95b50d2884910eb417473637a73d8f173bb1277af6050036c5399baa0232eb5fb759296e76be89a4b66	1	0	\\x0000000100000000008000039dadcb8f06aa57ad05cb7d8d6d1c18bdf90d167dcd2b9f4c9dabecd0b918e8fbc98c52d53bbf2c7ffbc940718efa48927e83656be72aff7ec82851930a4978d86af960292d8384f93639a54820ae0f26592271e070e12d13c844fd6df2156be1a946eabe1a819b44e17e6da3ae5fb939685f8e7b038402cef8f9b1295c2d247f010001	\\xa35eeb738113e7b5df78c28a23bce98a676d8036229f5e850071f8572b5c4c12276ef30b128bbd2c04950c4a2698b3e1a881668e56c440cca4125880df920702	1652362091000000	1652966891000000	1716038891000000	1810646891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x56bb530ae303e0dd09bf9d60d63b332538f2fddc43855109a254eda39a4cff1a5ea38e39788edb903148e4496883bbf54acec9f79f624e5a927da257e7324a02	1	0	\\x000000010000000000800003cba0310070cdd58db86018629073ccf72f9a4ae7bbd38bd72fdec285275dcd02410b0762e3caf2e403a1e152f115a0d2999209c05ab6b9282618f7354349ad44e6cfb3fc0fa814e547e4cb51e3eea7c9de473c6dcf0c378fa2932ad83656050239dab67cbf70b76228d2ad1d1b4973cb42c6cf7cd12de35975363554b44f7903010001	\\x121a5e0461a7d0ee8a7333875016def96a5812e1e595212ff91b54f68e9f7e82cc8a09d1d0774a82059781cc2cbf1f2ae42e9285a795f07fa8d371c93d6ffd0c	1669288091000000	1669892891000000	1732964891000000	1827572891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x596f5209eb8a017856f33a07f22386dcf3e3398bd4c706222a53106d9eb213df38db7708ea464db52577ca1b1fdf0fcbd1e3bba1cfdaad9290bac69953ba2727	1	0	\\x000000010000000000800003d7acd70c336b05b446d1b1e86df264fc7e32d1a226ab0ae541e80e00b77bd48fcbb228b60d5da4edab009f5368217befe44690c5f25f6ee33f837b9c175e9b40bf5d60017a0e3502740dce4556718cc10ae571f6ab7e8ef44f83df23c09c002eed0f27092e17a0b393cf4f67533198d968d8f2693942996a09fa8e30e27031e9010001	\\x09b8fa4d8181d1eacf79793636bab09107c233abfb36991c6787077a8193b516d346509b54030f2103af298547b4e64050f50725d8aa36a2f210db887986c60f	1669288091000000	1669892891000000	1732964891000000	1827572891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x5fdb8d29334279578249694274ec5342c3be0fdc612aa754597f38e425db57cc095e291b15497c3d2e0cf152160512ccc058b00350e56a80138dd6760f703db6	1	0	\\x000000010000000000800003e3eca22a9b513a2967c0a22248fc1074d9429317c763ccd3b332941666ab48d91614d4097b78d84de2d2827473315880c9c3e598cb313525234d11ba32524fffb00d895baa72633f5cdf18c16c424169ecfe5dad4958c7c42bdae922bd20b4b0b92cdc0ed3f4ec946a94fd6e41b6908c82c8d30976416b10ba3e169ba65436ab010001	\\x83f8bd102aa58c1080fdd406b8bb356d71ed231e9873751e603264be81752804a2cd8af3976fe0d0a6239a5e2d6a800e694c1e0bbb9b697aa6d5c0a5fcc2a70d	1651757591000000	1652362391000000	1715434391000000	1810042391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x5f13d08d4e97f0aba64a5962ddd0d88e1fecb7e20b8579b415d4dbac20e66a23947cc50c0e1cd8700e2a63eaea331606ff9d68a0aa222936a85a5ed30657551f	1	0	\\x000000010000000000800003da3e8a9fe4fd3b42b9a5a58b9c0272b1a851c027c89915eb0b13890cd4ed27e52defb201d94ebfa1fb6a615df2cd1029a0fda2aafa54a96f71d3b0953b490d64b8a54699bf0430a4b3dac1c7c95c213f699c207f9c6d46d67a572287ed7ef6aef2431dcb86253e4232928fe706814fa7e237a28b57b765be5947ff28de3ef205010001	\\x4677cd55a3134719ab7852b84ddd41dbefb2847ef97959764fbe6cac4fd8a4b172f85238be33e0b0b39c455caff0aac65bc582f6e0ba51156497e2c77164860d	1671101591000000	1671706391000000	1734778391000000	1829386391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
352	\\x601b95e90cdeab6621c2b1e573f16315315540f2bfb66782da32a89564d2ede08d44289e77ab83ef22a4b5454d813db053074c089df25c94fbdfffa1da178a04	1	0	\\x000000010000000000800003b538d294f7cc0a74589f4093852a184f1149c078b79c31b6b77158810ca4ec082f0590be727e956f3ce2d8b4d21f01f472a5609375903a1f454a9dece92f74c8ebb9d2eb65a807248d95616f8d4f9eeda5b9548faa0dd9156907d36589f8c71a42ad29e5e4bc4e0cd9afe13bb1e7fa5277a89a2716a430c0717b4939e432ad41010001	\\x61828a3d4c3b5d28d5b93c39b9d86ade2c4e760b1035440f8bce30b1e8cfec379c12c4f6e169d95f335b87dad33cb04336fe57fe52bbe3483dc3ff72b8f39e09	1673519591000000	1674124391000000	1737196391000000	1831804391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
353	\\x62db20c151acab134f59f8021e46e3226d374b2be7991559faf8fbe81bd522cb7159239b97e700c7ada24291a8ebeaaeeb9cb13712940a78104e6fdb77e489f2	1	0	\\x000000010000000000800003ae1d92cad7d323c6ca5104e8288d6be5f5ab535f57bdd9ebf604597d88cd3aedeeac0256ce05b221fcad3488d3c33ffb22e4e962d28b42055a7e29402428a68bbe5aec507c5c20def793b3162182ac6e603800ca164fe17a907eea5044ffa9cac9ea59176923d921f03da097ac8573e9c29397cbf89dabf621dcd02424904e07010001	\\x07813422fb4dde7724c98f6cac1c2aa3b4a86895f45aac69b9ddf127d140d24e6d2abaea861ef36f8c03395fcb207e4b9ad435bd617586bc51cab49dfadba90a	1648130591000000	1648735391000000	1711807391000000	1806415391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
354	\\x631f142a0d76617528aab33d48769bf7d9851bc4799e1eb88c3b43156d74a19563689408d32a035aa5e1d8c64a4706ff6cc4694d7e3a96c9fbfe635947ada83b	1	0	\\x000000010000000000800003c15cf4408c434a99c76fd2e6fac622c39a8357f134f19a699eb811b4753e6963d99eb7bb3e28b68bbe3a77cb0c2ee01b43d8157af80e63518601197c410154d0f9e28d3eab4f4281284214c9e7ab8f03d71221e37d0739ff2d275c45aff7a945522f88dda3ebf0cf771ca8e775faa1a01e99daabe1ac0f3833aa1e9451905627010001	\\xde2a0b5392e3db2e525d7020941d75108abc7226f696679b92ba7bc69e0efc0ede7f3a2487bff56729e78534ea36cccff1986b6bf0a005260d300b8696b75a05	1654175591000000	1654780391000000	1717852391000000	1812460391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
355	\\x68fffa2cf0b69166fabcaa03d4c8c585b51dccea808b2c457b492b22c5b3a044b229c8c3a2511252bf2c8267a77127862f020099bcad0e192a0d1c41fcc29de4	1	0	\\x000000010000000000800003c84a534a5c1a58fe9c3bedf494b540f6e7662aecd5647a0afb4479c39391c31109ef5fd459fd6d4073b4a61ad6cd2305be681f79ff2a82f76822a2dcebacc1f649015e030e35e1ddf437ebddf7242fe4586503da85f6fa9ff99022a13eeb77d6cc28259812da7592bbe36c5ba49c9e75d6d7c6e0368ec6dad6f15bfea1632043010001	\\x21dce5c4952451db13d7397ec27eac77e9f61a6195d963c13e6d1e68b6067aa9af0f2a209ce588473a4eea1d9ae26945892bd8bd1e204fb12544ee1ff5325c02	1676542091000000	1677146891000000	1740218891000000	1834826891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x693ff55a95c2c66ad6cf06e585358c3dbe18378cb09cdaa8a47e455f20cd191c0581b373bf77f5e2a310be56fc79f91daef606b24e9ca5203971358350fd3a2c	1	0	\\x000000010000000000800003a6ab6cc604df3d5708280ce7dcb1e8be3202e85fb57089e6f732d5d18c7a8b8b7d3d3845827a363e8bea8c639864bb047f6e0b441512c63bc4f303a8c192ccb403744fd64fa2980923456fafacbb484c25701e342ae6668431108a11e27f07aba36443a6badcda631e9eab6e503ffd39547f883351017205fa1c701f42cda417010001	\\x65bbcddb84dea928382df7ddd7dc24aa803677f832e4e0cad358c2fa32a4caac05ec4f4abe0c38f911e11be56578ccd80945e0634f28db97e170eb3d58252601	1660220591000000	1660825391000000	1723897391000000	1818505391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x6c37eeb20f1a0eafcd532d7ebfe53a1dbc06ff9178acb1c123354f17e88927536a3f4cbe71dd2be490c3ea46baa1f1a5fa06666d87e65de0e42a26f5b008f926	1	0	\\x0000000100000000008000039c8af4afcb616d6edb2880408496bdf63f5d5a14161523cf68eb0bf77894db61260f857f9fad508e4f705961b86325ac3a55d339a51f052a82917aa9a4d181e8d34d2db7db2d8986223802f63fd77692a5885b3fb333998a31c2057329282168ad2ee3f16cccee9f46ccd51afd1c4dbadb96e2ed4be5fceb02982d75851ff77d010001	\\x32829840314ddfbe6b5f2f26bf61b150d4ffe9b8759e382aad4bbedd99bad1309965d3596931eb4300f537f8b246884a19bef9539102a986b8992fcecb91d709	1678355591000000	1678960391000000	1742032391000000	1836640391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
358	\\x6cf38e9f010cbb786b6fae6e56e3d388d916ba25cb74858789d4c70bcd069b129351ff868a272c6c7e6af513d825ae3f1255bb6e210a85f147a125f25e43f9cb	1	0	\\x000000010000000000800003a9033fa616b0a6ad66aa0a42cd2c8f77c69d59d41869b60a87bd6fcde86ea68666b17fa10d2c82540892a400ec22663cd6a69b11591435d2f145ccda006134b3f85f77806d138d092fad007b0134e6e953ab7797d8abb02c40c9b6a97a66e81d385fca5ee587a8491d7fa2b66efbbb07be92ac3e36408c2f464e44abb37d4149010001	\\x8dbe19e089de6d6c96016c170dbd069a99f5c76e8a923b1d31b26030fd8fcd4cddb32024d89e360edadfbaaf7635f6466cff99911bb14648ffd17a9f42ed8d04	1648130591000000	1648735391000000	1711807391000000	1806415391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x6d53ce4a2be2b31958df44910dd0241040d75bed8474ebb210d1a1598361186949fb5cbb076bc44558101845990c15902296161c6d2ec2c4bd36c6df5adf6778	1	0	\\x000000010000000000800003b4041b28c406bc76e5e1ff65a9e964355758f6adbe07c7ac64f21a5adc76eecf697afdcaba814e6a23147de5b68761c13caf7861b869d14bb3bc65005649231238c1c19ab1413888499c06e139734ed33b02f53e6088433ca9814b25552829b616526e511e94591fed0a518d8dd7bde3465eede150c3adf76d2b7f1921f24ca3010001	\\xadf967d52eddd1cba6e6eb74f63ac288195787b5ef18825638cc700fd390aeac6adb6c61bbba466ee161f376f63b644f0e3c3753810120cf132571bd48cbe50d	1663243091000000	1663847891000000	1726919891000000	1821527891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
360	\\x71937452b0ef845b5fdb09502a159f01c873a2e39d2d5637fdb262a988b19deb3e25be333ae8423fea6fd91b4f34fc087749ff1d7cf747aa8f2a062474a76a80	1	0	\\x000000010000000000800003cf5a92966f08fa00de753a7e8c9d8454593a66e84d4c0717f41092362bedec0f20aa583881479d52bc6be6b197274ee17cc4b7183b3608b9a0adb8c85c7fbb81619dfdfc7d177b4383cf0f9479fdb8a07f6faa5bb301daabc6102f4d73c0abd9d8932e37cc46aaa0109cc8e8b177c7db9834d9d5678dade1d3e3eb2b938a0e05010001	\\x610a592afa3ccc9da77f7c3c119cfb38e33493e09515658cbd81a63d59f7efd3b680aa0c3ae23a823f4194804b45d61a21c7249a16ebe76ef57a47922e36320c	1668079091000000	1668683891000000	1731755891000000	1826363891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
361	\\x7af72be98ebba169adb1ec20cb9a28f0b5c2a8396d78c2daf3f339f0a586b8b6d92c8548613e27de96a28a40dca96858283aa1a449993c499a50b3933ce7cdef	1	0	\\x000000010000000000800003e1509841900568f5b89eac4b16c2dc410fe90b1dcdcb798aa5bbf80fdbb288d46cc789e00830ad0262d05bb5767b61e2496bb88cd588b022d077fce2613ad9064c204e4adaadb3335013126c1d3fe06e3a189a61897d81caf2a8c7ad45671aa223fd779f90612f0e4f2f1085a71b501c314b4f6fec8309baa6fd98f05eee0219010001	\\x8cf7f2792a1ba0c949d4c8d0c161695a1b6f98c7e1148ec6ae0c3c673afa566582a2fdfb6c351e5ac10014add6891ef002e044917c402623fccd810a64945005	1665661091000000	1666265891000000	1729337891000000	1823945891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
362	\\x7acf0baca4d1a9e9f2b381fdb8b988a7108f7af3d411ae363ee0ee42776764875181494f9fc070f70aceb982f2c7ecbcdaecf806580849bde52c7b63aa820f37	1	0	\\x000000010000000000800003cb07c6550abcb698e7022e0d05a935256609dfa704c9ed02a3041d29d1bd633f37fb6c55234cc1d01a6460a5bd8502a39627174283be33cd475557532c4e8887309c8f9e393ac99901da5f35013691453082dade3b7acb4143fbec678a0a8bffc395f34f41f961d265b5740f6651d187de6c5500a419633b86db1d53e37fa08d010001	\\x84191bcea88818560a218d4fc3594bd107c3606a20c91d7162ec9fad8f0392860c7504164422b3e439586216c62c7b67dc0a15357031db21b1da471c6e7a5509	1652966591000000	1653571391000000	1716643391000000	1811251391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
363	\\x7b2f101f9ff9258427ba6c8aee8b541aa47c9ebce4c4739f8ec70a49df06ba55546a769b2099a42318110ab1500c1b7ab112e00a6257d21cced159abcb5c2a68	1	0	\\x000000010000000000800003e1f79595715e96cf090a917d2a61d50d99e8def50b282a0d6f0c92754c53412b40643cbc134dafc64443af35306070b8da2018c699f8710b42a82803c890794ea4ef3163645469c5b0d87419cb5194ca5e0e5359d66cdae95f6ec192b745914a15bbc58653242d9668ae78313513febc75c1236fc70de003aeea96be379c683b010001	\\xf186683b83678257a06faca92b32e6251f7f816321b1f987ac7b58e53447cd1a16258a85fce4100cbbc4db23489a4e78c24b07f377c3555ac43b580e96f34d01	1663243091000000	1663847891000000	1726919891000000	1821527891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
364	\\x7cb7dffc81915875ca53231fce725aa0d26aa121a0e08de9bc7149a76bd46a91d6e1262848a8d685c808b267364442613bbb2e8c0cb96f2b24ac19076416258d	1	0	\\x000000010000000000800003dc4167ecb4163049ccbc77bbb93587904633fae4892e9088064469e4d85e3594213b89bf19dd4f9f1deee8d3fd5e0cd9f4104eaa876c12f96555055e038c0bf126be07daa61cfc7d3a659d45d5a76c3e5639fbd4dad0334b25247766e71d89ef8b66cced4e0ba8c112f133cf812d4470f4a7e4fdf6a1c503774491c7518f19c5010001	\\x9283c5a7e3ed7da5fc7e031b68be6c902a6d104c9d9941de8dec60c8e9d2913fbdb6858aea3f5ae49145483aeb3e66255c5f32f251df8253d0518fff2abb6502	1649339591000000	1649944391000000	1713016391000000	1807624391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
365	\\x7c63ffbaa9b4414c6d0f9f7939d5326d78e42d415aea987614b03ef18d35936cff9fa9e73715787e68c102d5c4ac17ce5677f278166f7bbe6f44fff9f4e1249f	1	0	\\x000000010000000000800003daa94d7826388bde86aa3ad0fedeb5e0f0c499fad573b0e04210f04ff4c4d368a9e44d6bfacf703da31e80ed6b81330a2381ba19a70f3419d246a517d686e4c701af1d9364fe17cf1d9750eec5f976ea3d267830ff8f6091e3185904762d57400a24598a4088ba9fd7a986df6da32509c6859378d1d81a25026514ebc68232f3010001	\\xd93969ff262707cf2d6bd1e65a505e8706bf479ab9bb5f31286f9a64b0387efbcccd3ed489bd35f5901bfdd6c78750ee08d66f0302a8284d22bf9b666b6e7e00	1668079091000000	1668683891000000	1731755891000000	1826363891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
366	\\x7e139e441e1e84b7bde6dcc6b2f4581af05ed11e700a67455d1633363d15017a71fd98532092f742847f35708f67e6f693c87bcc05462e16c8c4681d3bb6de13	1	0	\\x000000010000000000800003c77eb9c98f5d6ea129ce058d89dc0e1c9328fc86f7eaa40ea83c13e7ddc89389935b91e43d8b555c5640817966001c8f87bef9833e1815de65e5105c699af27430ba6c53fb96655ad7a9d6e1a32a0d27f79998fe5eff43a7fad5ad89f0de82121f83b19d01132bd40f37b4a1c45ffeb27fb77655f59984f2532d1d4bf90a880d010001	\\xa744f70c6eab441cce43427b4839fdde6edb69cd9b523b79fc0af695e19c3c89f19fa6513ab453b42c3b62bce399d42ce7e882c9a8b1c7de5b07701c1f9efa0e	1665661091000000	1666265891000000	1729337891000000	1823945891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x81a7add399bb15eacc8afc0f596abfca7d5c234d8d79e7f4fb0e1b182aac912ed4dc1d8a767bd84bed427f83c239e54fe1c965b7a370fbb10dc2487cfa90bd00	1	0	\\x000000010000000000800003a15e3d16e9e1f9fd91ce00d794e1830d0a1cf6bd8770dfdbb284527c175db4220335305d0b6664ec79ec57db8944fc5855b40bf61c917d1f802c2dd668a84d011524c5d4c0579f28cd02d07a037db193a9754ac3de17e5c2af96fb65ebe1a25b21168fea6b03d5af543782a21444c74978bf0392d18986a6e71f94a98d1822d9010001	\\x13175c88dc703bf1836b3517f0f44e85ae39bc63dabaf93e4b57deb37d9e591601c9d5f0d7e867ef7897952e336cbda5a2b667ddf3821cd88395b37036b6fc03	1654780091000000	1655384891000000	1718456891000000	1813064891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
368	\\x87bf183a864bfe06113b0b213dac7f4ded656ca1ae024205aa927e1d092a4ef1af59542f55c4db9e88e53031f95ae34caa1d9fd47a8b0c6c4b494144fa7dd365	1	0	\\x000000010000000000800003b627ec98996a0cb3eb343b472fdbf3cf7c2f9ffa4a602e18e99353bd620898a661d99fe484ccbf2d4c920f8365accce88c87861040c2a93837622a8221923e3bdb22a1d4c48931397b6247750ece8de56732eb1e9c02028b7e04aaa8fc393cf07f747d8e9278e552274146e7bf7b45937afa0af89a08137b2db84a0997b6dd29010001	\\x3e1a40bb1161d41b8932c81612dcd4dee6359a0ce9ce5510402fc4a0fb99351daeee12de4c70608d805554490829f2c1b1a55c707b7bc78b063b14ecce376408	1678355591000000	1678960391000000	1742032391000000	1836640391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x88d79b3c4d3387492e73166ed8ad0acfc9645fe0baa7222939c4214120064e51c1f33c8bf7c11c4195b42e26781fbcb09be3495a2e0cb1764ab74ef408ae4355	1	0	\\x000000010000000000800003c71524741344446c4898ff223be3079ed7f70acc5c6ffb747363841861bcc162d18093afc83c11fc2713406ab752aa059fe89c3aebf5be62721bed1678974285294a8bd73916bcd67831022c45ea636061968fa277ec17580bd9be31fafa2cff0b88252e89e20c6516824930f1eb364abb8e5ccddb34bc4f463f34f954abec93010001	\\x75fac6fcb15f836090156966668c102a832a189f6c539191f1b80272b09c7433e961f0302db95bce180a537d494f3dfca97e89f6bafa52cd0a189ee9038a8407	1662034091000000	1662638891000000	1725710891000000	1820318891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x8e7b0b0b3fa81421fe881a04571470f442ad8efb5bb3bc728ccd6552234c8b09728621cf3d84a00b01fd6420d8b5823130da7456713454967f20d4442ae29cdd	1	0	\\x000000010000000000800003a5dcafa24dcdc7afa3d84e9524eed1982e373183e88e4bff2c18c4e10e71fc2b486375bd6949166eea1eb6dce764c9615aa7c64abf5c1361bc0cc45fbf8fb3c5027f256dc4f0449227325994d86ca2ca491bcec32a4c02de80c953b44a6d2a1ecae98e35c649094886a59fda2de6e058d71a5332fac6f58f45c0dd2d7623058b010001	\\xd19b92767c1b4dc6751c5c2c0580de6e87c79d9312852f98b5f353b42b3d7ca1313eafd78d283d0d18d8fbbb8b4eb2cb2cb69495d7091a3f6785ef1a4c509600	1652966591000000	1653571391000000	1716643391000000	1811251391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x90fbced507029b390b0cdcc0d1aa2d58dde44967f732394a95fa8eefe28cad1a20ad4e26491e9b4e88e66c1c06e607d49071517f8f4a4ebbdd5d1f40eb03df98	1	0	\\x0000000100000000008000039905b889fbf5818089b7136acd7204858b10919d81008e259f90bd83746252493aa0f9a61add0cafd411176ec4af96f722fb4e4836999c70d347142030be60de120fe35415e7e1509233b43e724fed05296ccdd127fe9970d2bd5a4d807b9470b07de8fc629fc96ec4927c7f6fe15212d71d5dcc72b5d6802796c1a26b324853010001	\\x620713e3d53247d7e1d423984330e44e02e0b451b382241fe0e78780ebeb647fbcbd13d4bf4d12bfc17ac83a510f15227613c92d518510f2c42228a8f182120c	1675937591000000	1676542391000000	1739614391000000	1834222391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
372	\\x907b2d9d6d34f75e680873df351f7c7842455abe6468cd2697052da7e894fdba5f9b677ba0891edf5aecc94fdebf0ee46bf1716de1a728028ec17500f5c92ee8	1	0	\\x000000010000000000800003c520fd25ad98c8c45cf76d0441a558e6f4301c95f1f5219a299a3136e87b08e8c8346be73e03c690483a6297038f33d2a5a5ccac1314ad3b696aca3631ec76c7ffb6410a7f0aca07b2920838b6fafe6ac35612434e0cdbb70f606561a5d90e730ea31361ac0be0d6b03bbd1d1861664fe1eba76b1c160e6ceded13c6f0127497010001	\\x459e25a0a4b4cb20892cbf8c7819396cc31fab3146b365c8b03ab047c1d97ee0e45748569d9d85c0e0209499f8a581a32017026491553b1fdf11b752e85cba02	1651153091000000	1651757891000000	1714829891000000	1809437891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x97b37d8ad55e735a65fe32f05439f34e7b647dff62eaa6b6f10c4e2e2cce482461ecf6ed0573d67ca7646318b479e3132e017265358bd5a9c0bb27663a958a15	1	0	\\x000000010000000000800003d990c8ea347b725c701b4b593cb2e40b6b5a66ec63e80bbf8303713cb30c1a10bdd5092904824b1bd61ae8010c1f3ecb594f1eebfe03e299d0e49146eb126b072ff32d3fa6c4f7c276f17e1cbfa57dfd166efa6f858778f19d850025745a762a3cbd6fadd9f9a2504c0d7b4658732c632cb5e590a128e2ae650a6f939511a80d010001	\\xe076ac2a121a6053375426d1208e4f0855b08a0bc11dedf8fb64ffdbae724c31af2d13076c5195995a2aae73acd9d3b1c8d6b0e65cc40631ea30f9c81a723002	1668683591000000	1669288391000000	1732360391000000	1826968391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
374	\\x99b70036ffeb734b823d0efbb030da25716de0c0436f79cd3bd3bad922a2473d8d2ab67538ea63191f57af91cb16954c514351dcfe73fdaaf20147ff9e964919	1	0	\\x000000010000000000800003bf5dddd3467c9a8c8b75835c196b14acf84d40d6c4c6389da1898365afaf886105cf22959380124d4737b404facfc1c75471b64d9632e11f27057c384dc64757ebce2ef29b09aaf35aac7ba31e53015213a6e69731af6a02c9d16b16de262cb0c4a978ab44f5020605d1e01b15686076a74223a84fdaf5a54417c6bbe7cb41b1010001	\\x3c4e39b91bc6b7749ac9c71cfe34e8ae2836c49fc9bd7e8679d0c64e1371292359f84b5202de58903cc9b617972ab887084ce03fb39f60f8b9ced02d854d2902	1649339591000000	1649944391000000	1713016391000000	1807624391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x9bab2fef912abe4fff5a583ba07e5c677904d745019eff1c17a9d683b0417585c79d07b701ca24314a7987e7fce5b16a66b43b34d9d04d5cb9e6eac12c80650a	1	0	\\x000000010000000000800003c92c87cc1e3c6782d64cdb5f8ae2d7c12720c0d959c9d7e1adac67e2d1d141e5aabc075f745c33f9ab3f98325335cbad856cdf5f52e622c3f35b427993c1432196894603973c8d539456d501a3b13986cfe906c9fd5fdef786b0e3ebe49f6cda304f16a4e9aa9484ae53c69fe65fa2f14f9801d825c810661269958b112c5c8b010001	\\x823cf96e06a39b7a9c357ff6cfc19ce84fd61c5224d72126a9c18347521f4fc16fcdf0e2616cb38d828ad2e48759e5195f30b072582315e5e4f4e55532b31c05	1672915091000000	1673519891000000	1736591891000000	1831199891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
376	\\x9be3ff9e88aa21e933d5f518b4dc198bd740dcdd95fd4d43ae124ddf16332d9660be45e7579cfcd3ffcaea5f45a5941c4f89665f4a3501e6fef6a874da7f654d	1	0	\\x000000010000000000800003b3b497f29f7397f3940030aa2968b5b7c9ef40b3547310d2e8461038edcea1a1a9458bf68ad345f632108b1fab8b6cf5009ca41f8bc472eb438ad65362bd0677ed3ccc2fba08d70c1fa1f3225c77a4fdccb2d5398db791eb3062f1fa729d9daf5963984a6b954b22920a280980dfc4c653bc637a2c682a3564d18369745e9a23010001	\\x8adfdead7ca1a5292a7250ffabd3a9f225074d62839664adc133d8e7784986c0e7c6751095409d2d9e55365aa731e523ca983f2db35098e8eb8245d50d1d5c06	1670497091000000	1671101891000000	1734173891000000	1828781891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
377	\\x9cfb44cd64b2deed59319f3e31f16003b91c69129212484562a3f82116f647fa66d04f87aa8fe60b06d02861b6df51bd7d68557e80a1ff7e3b7c272c9ba2f25d	1	0	\\x000000010000000000800003c5297c4e18464443568c1c72feceaaed1f08471c5b23eef09def4cf5d8a7e270767bf544d1970cedf0d3d6f68a796a2aef6580e53c8f41cbd698930b79e105cc48d23355774a8b6570d92537cbced2ae8f3966ef56b8638e578295331190722890885cb6ee8a2d7f3d3ad7830646bb3eae79e467b72171531b436f37c0994f01010001	\\xed6dfca315ba5dbb0ed7ab843fc939d94feb4e0e109f8ac095239492c4b45e98643859857d9487987b831580793fbd84cbe7908b15efc8f3770d7d21b7529b0e	1651153091000000	1651757891000000	1714829891000000	1809437891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
378	\\x9c3f41a7a85413aa4750f53ddb82fe59f0354ccf577d144949a1b41522b4e78af054c4d972bd83f3882c427709d24efccd9b248eb6827329c8ead0bb2f3e865d	1	0	\\x000000010000000000800003e7b454d27efe754d6c5ac7b227982bbfb81b9dbbea945beaa6f64ffb26cc31f255b89fb6309f7267bc7a19f6a3fd816333523dd3a357595c791a296144e8f614315d6edf5170d193a192216e223fe9dd6c91928fd5872518d53862d5c4d746967058308e0e87509b806048535604e3fdb9d92d44ad6da72a86db8691c92ae8e3010001	\\x877112ac681ec1df4684e27eac4605ea124ec312fe74cc3bb4881b70aa8c57505a61e180410e18250a06117310c5dbb672eb6d3de0865946b36ffa597e2b110b	1673519591000000	1674124391000000	1737196391000000	1831804391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
379	\\xa1f7c09961808012ac48bf6e1fd3551f9dfcb86ec6af752d1ad7932fff6e2220aa4bc58c46c9a97d2417a8317de97425f16ebb3799bf5fe4f63161300bf174ec	1	0	\\x000000010000000000800003cb39f95107be2e0d4e422ae2d2fbe5d76ff5fd769e7d6e5f4886b0c1268b7715edef7d1aeade735272d0acc47ecd96645ab407460d3ce2b70a796faa723281f4d6a2ad6fd891f78e27e57d326a4bd64dbacc7160bc62e01e8267fa9defcd11eae84e08cdec9216d2c0a3b8190bad931d08d19c1b0890c86bcb09441a29c3c1f1010001	\\x8f6eba62fbd790728d5362d1aa10829c23aa8e20605b209b3d2b048838054f3b3d1964143c13dfafdcd64a49bfed41d4fed24c39cc3d66467025575f023b8b05	1678355591000000	1678960391000000	1742032391000000	1836640391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
380	\\xa2f7804c496740a5fe73eb2554c768027c790805d3a01ac061fe1fd770e75a208732fcf2a71d3d7a5a2e9bc86a37349ccaea6cea9c9202d48234879015826d42	1	0	\\x000000010000000000800003be3c171163781627fad8338115b22c150d5a0a4f04fe90e7d91b01187bca34bfae5d112c2bb99f8f59379785305dbfb29a5bfc9c8358efdb23d935f6249e9135ffeb8e8cb9288aa3d5ffdfa02eca93afeac759b8989f6ee28babdbd8e69c8f1e847e52d76f806853911d6087f8db04aa5d18288f8914edea15869d4a031fd419010001	\\x19a242a99608af1d9cf2ff90bfa656ce47470f0c281cc3dfb0c3d36a6d3f05bf5148567f9d98b123f90b5a203baac0d692b8de9b0912c8db51ddd341bfebf20b	1677146591000000	1677751391000000	1740823391000000	1835431391000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
381	\\xa42bae8e47d6c28532b2d2553d6f2ce794a7fb3f6c4b65dbc1ad130d88a732248f415f6f677826fe19e137ecca780ba648e288ba7f750181d78c73d03a0ea4ec	1	0	\\x000000010000000000800003b100822056ae127a1bcfb7b72940ea96e469be269f60ebb6f35247a632f3f03ebde8e1dc8ca1bdc16bd62ab88c01825483cdb9244916e7733bd71186a24ed4310c520df4677bb056cf78a04f558d2fd23d971e0bfca4868d4bf438cd3aba2fc8bde20e8c11b0c1c70ea879c510a208336a804f638d4bd3c72f03c530279fdd39010001	\\xcc88d0a6bab9fea549b302809922d75dd440f9f6b7f9b6ae06771b03efa8d8537508b90a12261f73226f6595bba2e927f901f92a90ffbca5c7cbce8c4aecc601	1654175591000000	1654780391000000	1717852391000000	1812460391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
382	\\xa593a0197c4b8690f98562331eb63901a4ebabccfbfdbe81277b8d41d9ebce76b57b54f46cd468a6c02debbe4054eab751369795bf0835a21361563bed5184de	1	0	\\x000000010000000000800003cb3e8c988cd98c1e81fba0349f6967b8d7ef312029f4de38c64992a3913b09ef13a5108e7171e325646c60b0d4c459334490127c73e230bf7db74a551365086086796d18b6f97fc1ccf51d102896c867529a8e9a7260ecdb0cabd33e29fe4185783eb2776dbdacd90344b2a104471c22e33764590847386cd33b92e3da5e3b2f010001	\\xcaa54405b038fa63d261b4e23fbc46d3e7dd4bf2ea3d0fe49ab7d9cc6c5faa78bf14cdafe39b54af79ce183bbff1391dc7c3c1aabfec1b69b67084bcf9201605	1675333091000000	1675937891000000	1739009891000000	1833617891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
383	\\xa60fff2a31cd9f30ac02b3ac347bc7b4277725f0469f3ceac1c1e57ecf53ab791c45313d2d02f73d077077672b589afdb8d3266dd2dbbb234a283865deb2dc8c	1	0	\\x000000010000000000800003bbdd4261efaac5b3dfafd4ddf362eff513591b3f9dad4b68005a00175f4d3b82c1331ada28d58eb16f7405a3cd42199e0bb3fd8030d8c5f725cf7c0afa12e81e7bd1bace48bab6aaed645876358c8ebe6db7152b627adde8c72ce53c5136323ed13c731f3a96ae872798f877a60255f5a0ac8afe668d4f1c53a3450168debb9d010001	\\x0a004392efee5a6318919e27d114a63e53d7c4c90bd32fd874ba4c80d1903a151f0d10dd4b29887f2263c8240f472ea275d416cf66e0c49f2ca5c3eb037e1d03	1666265591000000	1666870391000000	1729942391000000	1824550391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
384	\\xa837f153e3fb7de7784eed93dbeffe4207d4344283b55e7f4ec6f7268003273f45ac2eab8f43fcd2d8a3a60fb7e6d5a918745b43a69b9f93ac2ec8135c0f0ad8	1	0	\\x000000010000000000800003b13f9c66ad3e6749bd3ea0686eaa2f219fd890fdc64cdebdb75bf6bd4c29aad58102146b184ce462bc80a060cfe30cafbc8fe4c2325ccc31d4f96dacad990b69280c7b6464caa9f2fa4b1860333702e8e290cf23f6c9c8053c39c4b486ebbcfa76136003f7a5b2061832bec3d232484ba7477eaca48920b3e8423c5170d64705010001	\\x5efec8bf0e6da99988b962e35d09c00fa90b6a61920c711601a4284d0c3227ce7d6021925f9628229ecb5027d082b5b0643abc1ba5ff36bf95df4a5df846260a	1670497091000000	1671101891000000	1734173891000000	1828781891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
385	\\xa8abb6fdb64f4bf719157b102884469114fcf87250c6365f4df7bf893469b893c6626c9b9f1f6fd5c667126b2a968037c3bbe63eeca3c272eaf489e9c3d7ca47	1	0	\\x000000010000000000800003bc12bf189a49254545456204c1e2a1ea3a703f6dc1a5f50116b23fee9799f9232ddefc70664851bf19dbc57eb3cac644f39a29b361eefa82f87e6dc989ca22e012d0ae911ba981481e344dbbd0dc9f44c68f2bd1977c53d9727f7637758b169cea17aea49db620802f5a489bac865a0b1b2a372a0637ba1fd1a4bf18d4f3a60d010001	\\x474446f1b09a1d7edb1583ed567f86f4bed76a7f2d14227cfb8ab5d93a82fbdbfc760a284596691442cce791e9688b6ca5968271447edd54cf3c3f3e37886304	1673519591000000	1674124391000000	1737196391000000	1831804391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xa91bfdab6918eebdb10e0ba07ea325f5050d76a5506ce1c7048fae0e0f5361917f2b51fbf73fdaf1816e78711601bd73a0e4be4e355e946e2e944e1891a8d04e	1	0	\\x000000010000000000800003e01606fcd95b4cb57cb1f786d992a83362b4c47c97c2c7b6d39cd3a03afd7929b2993dd981909c79636ad63d5d962195f5125468150ab0de28804fe747b0b4d0eda50e39fb4ded531907b20d8cd934ab2e247b794c34a1537915fb6af16aaecae6f7b97680b29cee326a29cd8c0558caa262e765f418851a7e4f6c22151fce6d010001	\\x81be39e6a76828c7121faa989199347ab15ce95e0b0ad24c61ef3f72d6a6f6a20b7a65d87b793ad7078149abfe301391573b9e23b5603ef34fb14fa1b5b08f03	1659616091000000	1660220891000000	1723292891000000	1817900891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
387	\\xac2b53106bd95be9b1f0e60e06df54b4f66fc83de836111038f1f76be4806cac50294421ec348aa3ccd59d9fccb93cb4bcb881253d4cac15611125e61997fe57	1	0	\\x000000010000000000800003b9f9bb22e5262fe4e36f67b9400c7604b76ab23a3d50433c27888ef2723deb190bcdf96e8ca921cc885a753245ff2af9b5e29222e78f673061f4724f60fff92648fdfe1da6aec934713cd05998507500e0173cb0024117a6173b75887bdd3ea3c01ba45c9ba63ab74ceca44ccd823db6caf135d4228461224df032c6084e6047010001	\\x3dd4cb060de5e21e6a57d4615ccb7dd58640429b01ec5092e34e9d6616d28f6bdd3ae481f23646bc84857fc1c22497226381e6ff7321242abb60a303c63ae10a	1669288091000000	1669892891000000	1732964891000000	1827572891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
388	\\xb367aea1bb86f136d6ca45aed3d456166227b164a3a4ffea312e67c2dcb5c8073e984ce887054dd4d944651bd3ef69436e7ed1c485c9fce1b6050535365ad297	1	0	\\x000000010000000000800003acab82c22113a058f368ce97fde2172d7036011c04fea36fb2c27673eb2277565125c1a35ea640012df32e859bf09e96b3879fe06b1e2ee2c2670a00222000b71e2c677de09b431cfc690fc8c091455ff526f730eeab0052f9a1a224ddcc47ab109d175586fb40a73ff95d0b59bf1649821c051ad8c8d7908963624097164c5f010001	\\xe2c551bb05709369a637751c33d0fe78001fb06a34204674bebe8ba4b699d69712e7f2d1626246baca30a86e503f72e0c1a80f1e282c36f9eaff559bbbf25005	1669892591000000	1670497391000000	1733569391000000	1828177391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
389	\\xb3879f6cd77303ffb628fbc36c583bd704a0f12fcf305e55e410b1338206338d99b0d2c464557abcc7cfcc729e540aa8753f552a8cc534d0b483349f06cb0cc7	1	0	\\x000000010000000000800003ee5dfdc074fdee83ff569bb748a699411ab75ac1549a12b1d6621cc8c258ce0d2c52583155854b5aaf3b1c6bb9710079a49b1a54882daa31a1a1c59c7bc72835aa5b0bd4a59d90a0a24860176c65d91a47541317422c2297c1e7e84f8235865df7d688bd6bd46daea4dfb8ed7ca2eb12d38b29343f3b5c4ddec809c999f37ceb010001	\\x869c1b5437033eb7a66399eebb1d4d7f46211d01beda4361349a640fa9e8c47b501b3a4798c8f5955cb28ae61452b3bcbdbbb3451a0219a490ad89772213b00c	1670497091000000	1671101891000000	1734173891000000	1828781891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\xb77bb114f7fb410e6900707db6dcb96a3595cd7538c6f474405f7cff04183f6ef37956671af362e255f2176575bd44cd74a4cd6efbbbd9a97a80a63a9b765af6	1	0	\\x000000010000000000800003baa2116e4b657b1855f94ee658117596b7ed9abc43bbd76dab611fceb523725dd03d8c2794af7a1af2e2d13c36cc978eabe06c32042226e5dafa339d0a3b3ccaf84d8616305ab0922c011f467b999352960138412a4ea859f13deec604a1fac326a1ecf0635f875dbae9678b34059f76c14cb9704621b071bc6ff1796575e6f1010001	\\x971232fe4866186c93ec2eb6066a291ea9cba1729ccf6794eb452751ffd14e08adb663563c3b4e60e5c08a20e38f9903798b81a2c6b61a1074eab798fa37f304	1668683591000000	1669288391000000	1732360391000000	1826968391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
391	\\xb8276ad304ce6051c92071c4996e6743e7e1faf137d0811d74662093d0afab845b5fb41d05b4066ebfd62743c38e1c2c3544968ee8457b3bafe218a427c66342	1	0	\\x000000010000000000800003b98d82799d4c8b1dd8534f434337b3faf7314e761ccefee6bb8210470450de1bf368bece6f17522167ea5ce5414f6ec05d2fbac22f7ad470a85f67c71dd88d98c96e002594a679321cc89b8a174437afad53cb5be8be23c619f33631a515dc9a2366690bfd6a4d942cd27a67c7659e1de1f24f58d4c3735db2824e4ea276b493010001	\\x43484695fe0d664b8c898220505934cdbb12f98c581362c87379d110a4a1631f694a04f9bf3bae785d403fcb1b35685a675bb881010d6d08c0d282c6d3586e08	1666265591000000	1666870391000000	1729942391000000	1824550391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\xb9dbb5ebeeee006c459cc85b4cf3a65ece60a52ec120d44ea9327c10cb87d364e66ae8b3398095dc100a5a93863d52780246bc2a97bf41e5a72fc029469e0860	1	0	\\x000000010000000000800003b68cc2a146cb1ed392b9629e11f262d934ac9eb314abd6241c1393d5d11782f259c0b20e13280e385c61814bd88357a0bdadedde1188e8a2310e8f36d6c618253d13c9a6d0ef66a0a5a4b9ccc82f452926490cf9167fcbd7d2a56ef41beba639e7bf145ea13089fb374b0371a12ea54d5429fb609ff3bcc8a51ffc18a0ff5e27010001	\\x1f322db3a0a4841ed45736e0967b548b0fd71a9312979d97a3517eb66f6782272c84cc6961f5e91b3d18b4ff886c5d707fb0528b02b0805c3db16775a748eb00	1652362091000000	1652966891000000	1716038891000000	1810646891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xbaff10890727aa8f77b10b38d2b2cc07d4ef344b27c3f4fa3bae1d002bb2e7550011c6600d1e3d1125508d832fa6b08f1e6d945935664aa2d16c3c0e843e4ea8	1	0	\\x000000010000000000800003e2c2c6293a92a065286ffe348251a8757bb8bae6c9672a009f8278a9cea858c722d61f6c03cd8d0609c2c54b1ac6407b57e69acdc7c7cf396888f6ea8e054853242b92d77000c3b232805bec2da2bc3fe5841b1cd31b33acd090b9772f3e978e7772dbc3b552e5675391cad66aa9722a6d1ae7e87dc9bdf1b15581e89d1a3d1d010001	\\x1c706c14553d0b9788ada31388991da806000a4fde059f7a62b22b05e846875deb56abaaf802519a1d1b7e92e2507525dae1ab86a66d0c88d30c97bdd9659706	1650548591000000	1651153391000000	1714225391000000	1808833391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
394	\\xbca3fa869e80c510e7e73b734a8492d94c1d437c2c5dddf1a5bd41ac14f35f5f17e7c28f104962be5ecd023b690bd983ce55de230c14714534da8075239e82a4	1	0	\\x000000010000000000800003b00b549c4e21ab00d69ff11ea6d0013b1d796e0563d5d3c2407a07e070c8cbe9ebf6f3f0233e27c1e9bbb2ae9f96a58c50852d2b759d90ed3ae4b2d7444b1f299c42d08dc9443fc09a312a7d9d4bdb2be0108343c0550d1fcd6e3b68cb18a5e59ccb6c18c5e6487c1aa02d03911cabebcba2af67f2f3c87ec12d5d052f83e2d7010001	\\x2a15149713a5f2990110a22f32262211fc0671643d3a0536182ed008466385a034c5b277f7b3205bde3b6c59e2afdd35392c2e17ccbd5e91c6cc1dd057e55601	1662034091000000	1662638891000000	1725710891000000	1820318891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
395	\\xbd93a5462d6e07a459870732dd9b8728378ce4de2fc391ca6a868a9ddcc59c07a9c03237f297b8f1a6c49f4d8dede1c1730dbb729b965860445250d9fd40461b	1	0	\\x000000010000000000800003ce9c02317ccf5822ce06789e4816a361d516de93032ead561eb8d2e9ccc56ee926526f1d7ac094339743617358e9794d5deb872a1763e1356dbb6240e6bff54070d87f178b2646a2891031379faaaa7652c3313225fa63171c1d1905bfa0ff23b7ad56b4c563be518f970b6777da128bd17261a62d9dd4621bc33f6673ceead3010001	\\x7db82029ba939a3f41f12bed5a3d1e704b2ddd7931c7c6caca4e232d1881f425f74d762fb0c93191aff950e28f1ec61f40836099baca3957e2a8b1d8e032bf0a	1677751091000000	1678355891000000	1741427891000000	1836035891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
396	\\xbfefd19293c8f30f4c03ac097e9e070a910ddb7399747c07560a3da9047df6dbd2558e7d9ff07039320a7401f6987ee9ffa6521a8196aa32c24a236cd9818bdb	1	0	\\x000000010000000000800003dd69581db0c1a839146ec052550149075d9eaeb1ef91f6ff9eef67178d0123716e6863a765858b865b92b263bb5dd6b1ef16738b7c29582e590751ecdd88d7aaf43ff48a72239042c7ab72105dce2b1c8102d50982c19ccff9d14daef346ad8eb8393630a5e4b14d5a8dcbbc77288f4a99b3a2e615955fc70f09ca89866e36cd010001	\\xb32d1f722cbc98df2e6d10c806b9a78919fb4d58d2e47412bcf6548dea466b77c0a2e3bf3591f33a4f29cad7cf1f1e061eeecdca4fc5c150d1c55d081735200c	1651757591000000	1652362391000000	1715434391000000	1810042391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
397	\\xc32f2d1d973e11889f0e74677a06682b00cd423636ea77316bc850ac63b40e7ffa0cf7c57b6eb285cff7c67c097d0f1f5c8f535691f0533f653d4576845de5b9	1	0	\\x000000010000000000800003ade15e6b359e685daf693a79453eb5cb92ca14da64a7fee6be3ff619365ef747bd2509255663f57a4932a848ebc4f4e96c1859acb3b6ec79df107d12c9d7062f791d5a66e869817554038abde76c004a6c85b05307c5be6c9e18ba945598f7b5acf830f0738d0dfc0f8608bc24e4d07968c11d8e59e8c19ca10ab2d2ec0a31d5010001	\\x035fbd3f29d47d8a2c7e33e94d3b658d24d983ec031959997522d92078d4c559c9c35903bbed0c6932a08d5d05827d75477f10fc672b13c0ae03bad3e2e76408	1665056591000000	1665661391000000	1728733391000000	1823341391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
398	\\xc7d7bd5886829d9c67d787a06ca2e6c3a44d24379fc4769ec45874db20c46dc102d2f81c687798dc3a4b380d111fc5a53a38e0e9862ac2aa6c7123662f267cdb	1	0	\\x000000010000000000800003d22c9acb43de48a254cc4c87c7d4f89ee7e1ab8b9389aa4524744a485b600c1484db7d65174e7b6770674287879c98909e72a3ed11a34878052390f20f7ecaba35aed9ad81b27214e12aa68fad1971f1afa346bb2bab573429121f144711ddd9789e136b1b577c903ee2e55e68ed7199c6889eb2d4df957ed8422158bb114917010001	\\xe8a53690b8b9a39ef09c1982157d3c7ef07e7397f4dfc22df8c782f46ea358f0ce33b47bf165203277eaa4a859878673b2f0ba75422657693db3f02e0c0e9c04	1668683591000000	1669288391000000	1732360391000000	1826968391000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xc803d7164e833887fd6975425335c8bded1b00d6032512a6b5125e4b80c2d2182644efba1be258806b35e691b31e176a733393b82c045d5e70d54e9d631a42d7	1	0	\\x000000010000000000800003af3e09aa895786717a3d767906950c54045a134518424cbc01dab284c557b58b3d511adcf1f476e4b13e8950251f456cb548317ae0c89dc8e5f5b2c65cb8c783ca46e02329346cf1a370d33622296fa9d62dae0b33f8f8ae089c9c6e315a2ed44cdba3c407711a106ca82dc00e4baa322ec63db05258299dfadc9ccb4d667043010001	\\x9b51dde5c8b1c8251e2c531b1e6c05f8e45fda671ba8e707917fa04c32ccd987b663d547d7a78e01603d57bdfb6b0870cdb005c8e872ecd5d045f4dd4843b40a	1650548591000000	1651153391000000	1714225391000000	1808833391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
400	\\xc8eb28c691419d94320bd1e5637b3fb507c54b91ba32a0fe2e954b2de6d84cf786af76500d1dc4a99e8ee09d586e4802cf728ac53d5f218f8677eacf3efe1e6f	1	0	\\x000000010000000000800003cb6316fa054756bcfe8f9e81381c05f6335c80eb08eb1ab7cffb572bd1febb1a161b2b8e1cfe308f6c5513b01190f68ba966b9d12b2aff34d2bdb089631a06e5378dd8938f31493765c8c4133a358bbf8ef032403c6d036fb9cb248b1f5f11b285454a2f30b2f72c5e251c9ba6c5a627251d65bce77828d02a42f574836a42f5010001	\\x9c6998b56b6e6f7432dfb9bf17a71f905bdcc2eb8c37e692edf5ca7fadc2a9bb04927a0b179d433765acdf85d6a5525c701d7c835c42a266fd7fa917f8eb1c08	1666265591000000	1666870391000000	1729942391000000	1824550391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xcd13cbec4df4d9dcaf3cb67997e330afee3e6a12096a00326976f7894177ade7425836443d72c0292665272634c151ecfb6587b76c6af2d6ea1693292528490d	1	0	\\x000000010000000000800003d46783236e8e9968b80d6ee8af4050f10ab5fbb43dc947ed6c24465a5d208a7600a6e6c88c5d3d12ccab5a39b6453b07e63299d83e09c40c15cd32a166e6ec3cc645f82f96123cfc90f3b1718953372d5ac4ca6bfbabc8b72ba1806d74b446943ec13bdd40cfb8b2793ecddf7d49e14df4bdd58787964271839c462b4968a0e3010001	\\x5f30809db94828f9b27086c71daec2624cd74f905269fc95ac19c9284e174048a08a69f180d1c769b9e68c03252d4f25e3a91db6aed1e2022ed7ec5d21cfa40a	1648735091000000	1649339891000000	1712411891000000	1807019891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
402	\\xce5f3a99dc58b40eef2a03ef1af4bf8d95eab7cb849ba7d970870d553a64f9593c9fafafbfd717d8555c76b4ba89e300991e9d1a0d845e3e2b224e1d757b684c	1	0	\\x000000010000000000800003d165e569d101702256aca9f8da8348d18c2f9822ba39e5a07cf5f4a76e04ec46f86509ca3b4aabb4a6b0831b383dea51d049d1a54f2061843a761d653382ad614b890cd3e17342eebd9706294886b941015d48be142d0b695707c1d8fba17859fddba75ecc03bac476d5e3f5aa1e1d371af3c4d75117e7c44c698edfca66a75b010001	\\x9de86515b6689041161b4cd573261aaf4d32f667f351fa73aed9ec23639d50418c94bdf44ad8446c804724a1599313944741e7844b61efaa0191afa78d240702	1647526091000000	1648130891000000	1711202891000000	1805810891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xcfcb422207e130cb97119ca9448dd6044934ef333517fc9a4eaa9ba92efafefc6da54a701bedaa1d0270a360915a93294d1f62b620e8b00f3e9bee64082d1120	1	0	\\x000000010000000000800003d241b46caedd1a282cc9305092d228338d66ce9ff70fe3e7e10f42dac7ffcb3b62e8f6f498e8111dd00a4a3fe65ce3cbcbef898174364c00528d7ea28056cc3a0efb5554a9881fa814f449075a804acf71338f629647c05f0f768b8c83447fc567933c7c1bcc186a9b615e95c762bee47268f6b843f6da606987515704f18669010001	\\xe4532d7e77e38195ce06a9e52d10cc56371aed7a55d516500e0c4fde3388d68e67951a2fb643bbf0bf0f1358c3fe1c8642f29b3f23c32857a508262efdae3108	1654780091000000	1655384891000000	1718456891000000	1813064891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xd04b616db99dacdaea1162d2b11830a37fc261344b86cf60d913e1ed1763b9253aff28bfc8b2a3598f790a6d5acf405a6d045eab7803d164b1ee50a729355d53	1	0	\\x00000001000000000080000395c70153a3ac1fb8d4c74f5156545844423333e8b57a966e189e1f02a59734dbc271c51e2afecf2dc34f183d5a44b288dfc4653ed6ed4b610bbd8b6209c29c3c1f3683cf35bab40d373f0d448c078aeaccc5d338389ec9388241b5c58b7bc05b1bb72f91e8dc4712d7822d7bb2f455a49db1a27dfa791f1bfad5d536e299db51010001	\\xf27835995ae2d78227db73247c2305b8c7fb215939af3670d0f2727d4ac4027576587b7fa399eb8e5f741275ac4b3fb4b75c792b356c051ffced69e8b5140c06	1650548591000000	1651153391000000	1714225391000000	1808833391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
405	\\xd3bfab6d500f48064545b7bf97513929a49d9e2ace34173b652676f7e2c0b57c28bf3d4b95347491a35d3bc690bee25cb51e2ae87b1c58a0f3eba540c3a46be4	1	0	\\x000000010000000000800003b3838e32a2fea9f984aaaf5fecaa04e559fcc4cb79e6e167d208511a832c196a03033283cceae178b8eb99114d9e801d95e64d1114d35d37818f121f3e10290a5da742c8fdddcf9ddc3d8bcfa1b083bb210ca929a628217592329dc1471c1caeb102b04c6f5eeb0df648ba8be6db614335fa105fc901dca0e243e6c1ddd4de17010001	\\x242e44a5c62d8cd59e75a354f77dc3a353cb4740e327b7f66d73f382f432d47ca6f8d4803c63604a4df173d711e3dc55fc11b275a42aab4b44fd827806375d07	1654780091000000	1655384891000000	1718456891000000	1813064891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
406	\\xda57628719299466cced0d9b6da8dda17547921522a2602bb9a5ef2da1b52537596e1f4fc01e0a0ec01f0402149c5e28b558f8c740c93df7c48dd862b5c198e6	1	0	\\x000000010000000000800003c13c1b1b7fcb9b05cc8ccd04c10e811795daf4f7431c397a6843a82c07947892e2314d8daef108435b7f8c18626cdf246b14cbf1c78ebf2b2ad4008533a75e29df5051439afe0c8b57458dc377fb0c1b3d731e5acf5f92e290084a8802eb10693a9f6c6069e532d181a8edf071de2996f40aa2c8f3ab6a5f2d57039699b6a5a9010001	\\x84de1ac6b0283cd6c24d781fe38890ea7216024210c69f17bd1c3eeddcb273b4f4188cccd092363f595488c66139aeba4d42f74b8476d12f8f7fd7965aaf520e	1660220591000000	1660825391000000	1723897391000000	1818505391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
407	\\xe83bd75ffb4ec469b7549c0b93fabea7a0b200acaf892482024aba6aada2dbf955d9ac684714b6287694606f462c1fe8d04e54c043d2adf2c5a694f2999c0570	1	0	\\x000000010000000000800003b13888e3d2ca6a46d86caa89c7ec88a907f89950c4950bc9cc9ff2be02b81467d739d2eb5e7120da18f12cf06996194a56f748d313c2d86e264dd40e466c43dea4edb6079bf2d9d67dd080dbf06250f5ee5d59ebbe98d8424d68511078aa14a70a4b8b87cc23b0be5640232418a53ccc7d22250413186f6582146f9771bff3c1010001	\\x472d4decb0d2fe7ea3e632d29cadf32f3771fdf77020668c3c49ce97b478461b1578b0301b4954f01d5d1c7190493be10ee3b2e229a3a1e2ba6ea49d5681660e	1649944091000000	1650548891000000	1713620891000000	1808228891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xe9d777ffdaaadd9ce8a770bf75beb5938e63f78c4377d3f656885433402f7e72e5ba931f66862697c8c419ffd4ab2303631a40467dbe6a8a5f358adc4f4e2dd9	1	0	\\x000000010000000000800003cab6d0cf1d346aa1023465059b42a6d5df7c9722908d492d7a848c7a399316c27846957ff02d9a2b8610ec7fb87c01b439c41851c7258531a60fd874ace337e42ab2cb753a87fb7719b34c1b0a8de0502880d7978be1b69641a5e676c504740286e750439cc1277a87c268cddfd47cdd1d0572723f0775debfd358980341a677010001	\\xbd7e8e0196ec0d5cb42a1ac8915b4fbce80af5802748e7ac1497ecde514ca9421410975714ad620b7e12d1249ea4475326626c8cd63c8798ac37949736ad5a0e	1656593591000000	1657198391000000	1720270391000000	1814878391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xeb8330c80cff8e5572d2fa9a7f2bb7cb9da27654de5d72c4083cd84704a0ad5a09b5f8dff8c9ee6d6e88c01df1193ae8143d944d69bf4e67157a13bf78858742	1	0	\\x000000010000000000800003cebde34c8d1a1e2552ddfe441e6a9a5c455fb9950bfa628d54b2fa37363f0468f37c95068cf149aa15a1572f61f2820a9e8b3bb950a00120d1853ee0d2f2919c55ea6a0915576cbc74e37deab2545e93db469d89187739b5745c763b31e2f8e9ed4fcff434a91252b0e83eaab9ddcbddce468a4efa721375e78c213df77411af010001	\\x268eebd31cfc4863e7875f517e43d065575f61a0bbd53dee5a5f52ad9bf844cae90771fb99e8e7c90c55fd8c75bd8cdf431b2bdff25c9b0755cd1eeef9059209	1659011591000000	1659616391000000	1722688391000000	1817296391000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
410	\\xecf71fe102f32f2a62783a107ea7b7e3937a05e1b9b798fdbf9ebb674491ce5d0cbd7c7640d39da58c51288e8ff9b586e10f57ef2f1c600b5031ce6bb19895e7	1	0	\\x000000010000000000800003ca7c22c79783c21217afb5e17dbdb89ff349335356255e7644cad38bee5bba1b087012c908b7ed32c34e55c1d136478e039d1bd533804624b3751ecf7238efc194aa1c813c3fb91c978510fddca5ded0f0f8436904ed917a6abb3288fbe6ebc1baee88e7f7448666506200a734c6e35e19575fd36b3b1a9689683e9f64397563010001	\\x25fce77666f8c294de83c3a89c10774295d58c456e512d7760a233b94f50d355179f03476ea2402011b09dad0f072e695bef6f6e0706d6749ed937d23612b808	1672915091000000	1673519891000000	1736591891000000	1831199891000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
411	\\xee73f60c5ebeb895b550ea2e92ed7d61eff32561b28fadb61b807cb4f4c4630ffae7e396ab609484e999d1000f973963fd6422fb21e5b8a5e65a598adeb50301	1	0	\\x000000010000000000800003b47470c7ed0f5781fe8ced7b66b04ee2c7dc8c0df4bf42d07503421259af0cb01a4460cd982856684eeadb293729731bb1dda42d2f6fa8faf7357f6560e4886c0bc0e47a4aa7922d7462cd3ab6ec34184f72db2ba26dae94947a60479f3dd8605f660c0e5dcadcd5140f3a2762131935effbd7270610720a7acb289ea0609bd5010001	\\xf8db4c04ef1d1831e6c4e3a34819f689c014107bd25bf87aa832bb4be09540fe5d20460a8e6d93b2df9efb351d3e1196979f436b6f75beca792604ec4ed84308	1675333091000000	1675937891000000	1739009891000000	1833617891000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
412	\\xef7f2224de80eb255534dfc68c7da801247344cf369d962173e5fa902dac1dc32a00bbed6d1f00a06ab7258ce748a5c23a8262895258cd050149c75902dbe046	1	0	\\x000000010000000000800003df07c1f0bb4b6ba2795f0df689efab21c6775b3a19bbe6995af1bd02c750944cd9440a284a54b5986733abd46d8d9cee93a2a5da5808d9b4ec5628557369906b54b3192126306dd39d448eb79ffb8de37f87b06539ae42b42700d5886a007d0c8607decd8863d7617aaf65daa7e1bb797a91d1045e5721ed557e78d08e2b088d010001	\\x79011e95a8721264a3e2e712e3cdceb4b0e25f80c8fe01b598178ae0dc33f99155cfdb9cb979f2179c952af4b4099e9016d97882f75cbd92bd74923ebc8cbd0d	1649944091000000	1650548891000000	1713620891000000	1808228891000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xefd7b5f496b6c0403993edce8b248f5d82d5b0ef9b2cbfdcfd240b77991c88bcbe6b1a59cd7a71eec4e7bd5b14e8fd0085385101b3073d064a65e65bdc019380	1	0	\\x000000010000000000800003b33750953b83929410833c4442812632c936bdf2d16f4b325d703d35b61576666dfc693a1ec7cb4d53abf01b17b1582a4d028db83905e06141bde25a81625931cb88e2c3c59aa2c9f2843503ecfb2746d9140b98472df6816496f5b6ac00a832338ecbf30c7522a1807cd3e75807df19eea03355259b1fbd98fd709294deac83010001	\\xcd4c6c1cea7621f81cc81612854278437b77d3274e293c06fe59e66ea72a44b4cbf63eff6b55cc9b08f06db2b0c415c208549789c944210e274878e46e7bc109	1672310591000000	1672915391000000	1735987391000000	1830595391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
414	\\xf06b007d74e72749ce17530a271a9ba5ad2be0e1db6ede2a4812ecc94e30f895eda45f3fe03c26ee5c7281a2c5a1ebcb9e4d5da0f8856b593a3c3fe2c731c6cc	1	0	\\x000000010000000000800003c6c97f93e73db85d807aa746074a20c8ee00e6c24b88827d3b8a7655a01e005ef8c9df173ab57bc723f14c0c48be014c9f3c30f60f0a5416fcec3bcd54383894426a6483a6147fa470a8e575d0b1876c905c0f21a13557b1c5bf66904b34d8f20f87e94f05de1e5ba678049b2025383ff80f200ebc82e6ec66ce1654d09a3037010001	\\xbb738fe397024db1a3c0074841a0f778770f9ff56d1b36329d7f47b48b5c6b0d1f1d9d3b6b339a9d96b0bd3e373e577465e5c428df406d4d3d547bdd6e113705	1664452091000000	1665056891000000	1728128891000000	1822736891000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
415	\\xf037803dea207597b1368ab5b6b1aac98f5f4e558132c455551cc42b42711edca8d38b4aef080ee95a4a9d273026d5fe552faf7f9cba54550490063675b1b108	1	0	\\x000000010000000000800003b99dc563470e147ade7859eee52253513a89b0ec918aa93208c5a86791e9bd7e37525745cb547a857aa40e60f992e3edade3f298f721b65aa85c5ffd45ae13c2d48176b0d49585723f34168637d4c1478c429680ac030ccca11d71dd996c2b6aec233b4db2cad3fcd99e72811a1bd4574e2c5277f5b1c2e98c3f2de5b5fc1d67010001	\\xe353ad4f043187440be70cc0e5311f23e6ba7b8d8480483c498301145730f8359e906ead3385ce5f655a9a6c6e159042fb5d760eb7c5023754ac87e8863f1300	1662638591000000	1663243391000000	1726315391000000	1820923391000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
416	\\xf267feb53ed4e3032b239c3bdc4c5c0013d87e4b6bd97b9b2621a8050d7b8f908d1f3dad7c58ba5867d482a405e4d499e66b81d2e019bc55fd7890b32baef1d7	1	0	\\x000000010000000000800003b3487587ac43017686052ec421f9387ef3cb4bb9324cd72b5e21adf685c6a56555c36c6f65b33b594ee28778f3312c2bb06dbe01e485d996605f21838e7b6b9da5cb70dfe4ecb1d2e176a2a7a2017567781f8d743fad25f5ef559cb451c69a328dd47292b431aa1905ba1e7f487a0e4bf326f9e293931671248b4e0d24afaf1f010001	\\x87f6642cd4dc7ce671fa61addd8697319f1cd3489253fff34ebe216532eee6ace10427cfdd5f3c4c50da603c1c9647850ef809712d4959dff12cd1e9cb92b50e	1674728591000000	1675333391000000	1738405391000000	1833013391000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
417	\\xf473f4a0152f5a1038416dc821f68d9b0e47131bb30ddeb7ce45ebe8d1716057cde399ca66abe3038f857c372f0203b362039745f5bad5f8c0c5b3400d5ffdf8	1	0	\\x000000010000000000800003e5ffbd0c3a3f7b2bce783fcc346b9805d770c896e1ce832224ab3b44ef4ad0cab472b03aeb743260571aa81cc2861d0fadf43996cab73c1f83a341e9a202462a140d548b0244e07b6a8abedfbceb692b17c2286b7b856655e9ecf809e24e221068d2482d326e9da29ccaf549d67bb015336e3d0c792dc9179925189eb2232cf3010001	\\xe0c5c20e29dd5a5daeec222dd8223382e9efb426be4d1ec9904cd455c2798364aa97df0791af88bf516f00988f61b95859b03025115eacd5faaa1014f7150305	1672310591000000	1672915391000000	1735987391000000	1830595391000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xf5377be725e0761d089773d46525a8b1fe55f252256801ad097f03fc5ed868092081bb16f65855be391262ecdf1f07c9cb92b6801304ce72c693727fdea53141	1	0	\\x000000010000000000800003c7cadd3f5c48e20aef5c75b0207f1cfd04b0a6927d36d64e4fd2cfbf16e00c5dc3431c8fe2d9192f6f8f5fad0daa723fdaaf13d7ca45a9a2d48356afba19d97e99ec0bc6e08c7a5261d3e356488a40a76c0a8541f17fca36217e77ad623c3176eb23dd443478f71c4c8272a3bfc685c21264402e57fef58267d385357834ffff010001	\\xc7b6ffd934dd969874da9a00a39e0db65b1abd0fa25dc17a64e48ee3687ab54384cb5fa072c67028558f2c9203a7f61372251b210d6ed9b27f52f2a454b51f0c	1669288091000000	1669892891000000	1732964891000000	1827572891000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf65bfa26968ca6f3d52f5db228b0146217f5242886bec5c3bd64ea8ba1da016817bf44af302d13f03b790a953202143eb9d4e0cd88f4bd30e0d434ca3c29222e	1	0	\\x000000010000000000800003e4e4ca2bdf8707d9aa6d2a5110d6bff6e4f235dffd269cc4f9ba913f0810a7f1277e88489aeee006134a7f920c7f36e6d535c6d8ed29a44b9b6ff5fa7dcd2932d861bba2f2a3517680180b23865b62280b19125bc553adedf8c621fc772b0d55defb2ba076e9b3f6a41603f8772f1a8889ea4c1b3a83c255db7ca48283a031e1010001	\\x0a2b38043c2e7ebc20abf72005a84a9d4e040b27e5f0eaf66fd98aba6fc46f4c40ab64c79e491443d543f4b3d6f779873bb8f27838b4011fa9170e942eecdf02	1666870091000000	1667474891000000	1730546891000000	1825154891000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
420	\\xf8eb089873d5fe38c876150007b07e7da3a2f2eb867a28d286c50482914cd791ffe7ee204bade4225ec7390564a3f9d8a54a8b345f830c16eea9faf4fe382c49	1	0	\\x000000010000000000800003b6096a982d95b78161cb8fb968f95828cc2fe5f2f8c489717989f585508ab190a22a90764d2e419e2e7e1f6d38aa428b5db7ee2cd1bb204384cd8e3da1a79cdef5f4c3630a13122274f71e8bba2da1c9b67e7cdff267b3be488ff522a803c7750f7bd0c290e4292772725a823678bd6c7b53b80b2221d1e3ad4ffbf9e0d2619b010001	\\xeb204e3fbf493bb82cc05fb5340157d2516b95c8732a0a8ada9d8dc792c00e3e4b17cd2e5116efa60bbe54c3b09abec2a1d043ae2fc36b88729d219069fe710c	1659011591000000	1659616391000000	1722688391000000	1817296391000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
421	\\xfb0320f84d4a6072fd2b4dba3d84240d856d320c887e1ab3f10b5dfe293db111acc035ffe9067b28c3650255c1c974f0f399d4844f361da0942c822e163d57d9	1	0	\\x000000010000000000800003cc7ab9629a14805bd336bd19e2db252625aafe45b77177b08ef1efb197bfc33d4cedbec66ebbc37d7bec2c84bafdd9fe3a836cd97c35849c59f72bc05b174f441371ba50ddc830faed60ffeea6ed025a349d0fa8533b5ae691871451391e1dac48f49a6324b412359b2ed159682b41f7d0edd88240356c7a0a5f2278235d1b1f010001	\\x82c2b221594c5e3dc40b7d81fc9ca26206d9e23a8d20ea329faf307029e357b76e7333651a5e5f59b50b570615caf2ca46ec1acc7471e9cba791fd583647190a	1647526091000000	1648130891000000	1711202891000000	1805810891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfc47965925d15e02389ca2cf5961e1cbcb7ad11736d77681ac0851fdd8244be501a8b5f902b16555e0f53fe2335074a479ccc14661cd7ce044223938dd6881c2	1	0	\\x000000010000000000800003c9ac03b5bdaf1ba7c2a39c9389b25cb68bb973a95f580475ca4d7b38625fb201d160b03ac5a38e86473efb7a2fd78a4a6d25cd068cc3e784a33c5d530bb6d87085549d91c74319c48c85d823bc52a3e84ff210b3e50e13902d681db239bd2849280e5854cc8f572de296a9adb48fd162471e6fd7610bb5628a08ea0aafb660c9010001	\\xae9eb52df834a1e3fdb14aca1680f8a940fa01347936aa0a649fb1500ddc179ecfa45f4cd6a37ba2cefdac65b4bcbe79428bf2704209c25031a7bcac1bac6502	1662034091000000	1662638891000000	1725710891000000	1820318891000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xfc6766032cf663ff6527d5dc36b746bb3d64b2ed8eba15fc97cd3968627966e1824f8c8cb91000e4ddcb2b4a5b361bd721410d3c4d96f15df15bdf3525262861	1	0	\\x000000010000000000800003a9f8ec286ee75101720aa461dd0cf24656b8d16cdbc1eb599dd4a6fd42d1356e75700d91288751778295f6590d4fc06ce880467cc30c2d7bc2b67401fffa59e312698fe9520b832a374880c31ef5fe01761dba342c896a81f6fbc6475976b75292b106b7c6dd43222f5c9d1b283daa21b5ea3e40c04ad478e58a7467c29b3d05010001	\\x1d89ae4e42655077a955a44335689b1f4aacff65f57c0ccbd7adcca3bf148250d23c8bc3377b5cf348244cc223c9b817c717d2659f78d90b77d59f35ff8c1804	1668683591000000	1669288391000000	1732360391000000	1826968391000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xfe93fb6151f98ae436362c8a89d5370f3ae81994235694fa9e2bdc2262adaf8b2477b67d764d0749a752226f2319b991c7242ad583f6e7026fd8d3a966a100b3	1	0	\\x000000010000000000800003be24e43c8c0237fb557362a77d422904316a5aebf704c3ea481a758959dea427e7314387b82335c3490b853c4a62e5c583b58793ff39cf5c5ca45f9f0315f611eec5cda09e26048174de082108883e09ecc0411f2839a08b3b4e610c1148d99343ff2f979340bf44c377df47d04bf2ecc4b02b7ad71cfed48bee7de5fabc6cd5010001	\\x689f18e8fecd39d669cfba0165c3bce0c73a451458eb0e6acf7ac81514a927c55501ab06ca265502611af8da04d6b4fd885333937ea802dfe7799ddeee9b950d	1678960091000000	1679564891000000	1742636891000000	1837244891000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	1	\\x69e9ca3356971f56cba23689a974100693e3c37bb940e04bcabc7dbe18ce160d83dc78a68914ef3d930b5f56f5e3140820d73e4b791bf5d434cc398cf8790478	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x21e53bf2a6559be8c51ef5f5367bf151b1671d419ec690f1eb621fe8b04c855201dd23a575d89b3eccad9aa2ca608de0a42abecdc5f443e02ab4fce0184586ee	1647526109000000	1647527007000000	1647527007000000	3	98000000	\\xfbecda45f464f6067b44af539991d98c1ee5931f1e3c2fcc2849007baf748a44	\\xd3760c80dcd55bc5bffd5a828da1d8bbd122fb84d682f4f7cc3248d58459a361	\\xfc9272af06696cebb095f742e6e30de45953832e73718c092bb055ac4bff885f37665434addfe32052b2594dff335f0b365b12b42aa6fe56b1f7d521155f780c	\\xe793448592b9c003e981c03d157309f98648b443f3d6e08bb19132f31752fc21	\\x20a06659ff7f00003fa06659ff7f00005fa06659ff7f000020a06659ff7f00005fa06659ff7f00000000000000000000000000000000000000c7b4c576057fb2
\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	2	\\x2b6a68f162272c2b078b8e661f2043bca07a768f7c5b736f3aecdcaeaef7179f19a59280075c502d2be9c021da51c30021736bae42935dc6f63740512058f83a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x21e53bf2a6559be8c51ef5f5367bf151b1671d419ec690f1eb621fe8b04c855201dd23a575d89b3eccad9aa2ca608de0a42abecdc5f443e02ab4fce0184586ee	1647526116000000	1647527014000000	1647527014000000	6	99000000	\\x668918ab585e789cd3bdfa5a7f0e1d0775141d45104669300e40165c3637782e	\\xd3760c80dcd55bc5bffd5a828da1d8bbd122fb84d682f4f7cc3248d58459a361	\\x1d968c2ff4ecc899824bd214978aa656587c1fe52e840ce7de7f8331cfaf69d3d8208284dcc96b617d917cdbe796bab73aa0406880079c51e1f57f56a35cce03	\\xe793448592b9c003e981c03d157309f98648b443f3d6e08bb19132f31752fc21	\\x20a06659ff7f00003fa06659ff7f00005fa06659ff7f000020a06659ff7f00005fa06659ff7f00000000000000000000000000000000000000c7b4c576057fb2
\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	3	\\x010fa0a728acda1441f64f559f3f7b35a5299d5c34d575b3b3b62b11adddb180a3253ec4e3edc68843e8f7dab089e704dcfa99cb9d1da027213fa23f1446406c	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x21e53bf2a6559be8c51ef5f5367bf151b1671d419ec690f1eb621fe8b04c855201dd23a575d89b3eccad9aa2ca608de0a42abecdc5f443e02ab4fce0184586ee	1647526123000000	1647527020000000	1647527020000000	2	99000000	\\x10ae0d370fa743ed0eaf9edea6fba028f8bf6d4dcfd03ae3a11882606f500dcd	\\xd3760c80dcd55bc5bffd5a828da1d8bbd122fb84d682f4f7cc3248d58459a361	\\x3f5aec6024ffbe7ad26e5bfe167d4d94fb6254d4691b347e60f4f0f8768676ec7bbd42db92885ad0ae2080677713054c33028cdcf550b24fbcade4d8f1a9e40e	\\xe793448592b9c003e981c03d157309f98648b443f3d6e08bb19132f31752fc21	\\x20a06659ff7f00003fa06659ff7f00005fa06659ff7f000020a06659ff7f00005fa06659ff7f00000000000000000000000000000000000000c7b4c576057fb2
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	339058410	1	4	0	1647526107000000	1647526109000000	1647527007000000	1647527007000000	\\xd3760c80dcd55bc5bffd5a828da1d8bbd122fb84d682f4f7cc3248d58459a361	\\x69e9ca3356971f56cba23689a974100693e3c37bb940e04bcabc7dbe18ce160d83dc78a68914ef3d930b5f56f5e3140820d73e4b791bf5d434cc398cf8790478	\\xc4fa89957bf36fa13c79a12f2bf186c16fe2dd10c818ff30a675b45ff1ed48f1d398b970ca5d91d5696d4f1aed013c9a4f0dca6571b6b2f9281d0703d8e58405	\\xae00ea5c58ee58fbed3db632cb0b855a	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	339058410	3	7	0	1647526114000000	1647526116000000	1647527014000000	1647527014000000	\\xd3760c80dcd55bc5bffd5a828da1d8bbd122fb84d682f4f7cc3248d58459a361	\\x2b6a68f162272c2b078b8e661f2043bca07a768f7c5b736f3aecdcaeaef7179f19a59280075c502d2be9c021da51c30021736bae42935dc6f63740512058f83a	\\x49a0b691a0f741aebfc0e5569f18ad30c18fee7d83b9d8c6e44ba044952091545c5fa8b08a89e0087c9d360273a2c6f34dc5e0f6c9bc4e61681e789fdcc2af0e	\\xae00ea5c58ee58fbed3db632cb0b855a	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	339058410	6	3	0	1647526120000000	1647526123000000	1647527020000000	1647527020000000	\\xd3760c80dcd55bc5bffd5a828da1d8bbd122fb84d682f4f7cc3248d58459a361	\\x010fa0a728acda1441f64f559f3f7b35a5299d5c34d575b3b3b62b11adddb180a3253ec4e3edc68843e8f7dab089e704dcfa99cb9d1da027213fa23f1446406c	\\x588004d80db87e034168ae0c47126ea6cbc5643961c4e078a9a792b49f9e8b5d1f7ecc09f2317735750c348558d84c923ed5479aba9460bada383c495da1210e	\\xae00ea5c58ee58fbed3db632cb0b855a	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
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
1	contenttypes	0001_initial	2022-03-17 15:08:11.360303+01
2	auth	0001_initial	2022-03-17 15:08:11.520342+01
3	app	0001_initial	2022-03-17 15:08:11.649694+01
4	contenttypes	0002_remove_content_type_name	2022-03-17 15:08:11.663274+01
5	auth	0002_alter_permission_name_max_length	2022-03-17 15:08:11.672467+01
6	auth	0003_alter_user_email_max_length	2022-03-17 15:08:11.68022+01
7	auth	0004_alter_user_username_opts	2022-03-17 15:08:11.688385+01
8	auth	0005_alter_user_last_login_null	2022-03-17 15:08:11.695862+01
9	auth	0006_require_contenttypes_0002	2022-03-17 15:08:11.698972+01
10	auth	0007_alter_validators_add_error_messages	2022-03-17 15:08:11.706035+01
11	auth	0008_alter_user_username_max_length	2022-03-17 15:08:11.720852+01
12	auth	0009_alter_user_last_name_max_length	2022-03-17 15:08:11.7284+01
13	auth	0010_alter_group_name_max_length	2022-03-17 15:08:11.737558+01
14	auth	0011_update_proxy_permissions	2022-03-17 15:08:11.745629+01
15	auth	0012_alter_user_first_name_max_length	2022-03-17 15:08:11.753243+01
16	sessions	0001_initial	2022-03-17 15:08:11.785342+01
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
1	\\x60c54b65fa9ebd5d4007e9ec534f53578c8ed29d9612cf09f6f8b88cc4bac4e7	\\x365c81f0ac4131b1c34fe33cf3b917534b3b892e8314501c929f4f3e22efe4827d07495c40f50630f8e94629d656d29bd106c20b9ee3a06eb42abab3066c4208	1654783391000000	1662040991000000	1664460191000000
2	\\xe793448592b9c003e981c03d157309f98648b443f3d6e08bb19132f31752fc21	\\x2e6491ec566710165e718d980f07e36c83948353e01ed42db720675e8a201e39d7f912b602fc2688e0c5ad00897267f5a00cb2af06d3193d4821d31fdc63af04	1647526091000000	1654783691000000	1657202891000000
3	\\xf011680cb9e2540d62033e53147d3f4ccb277fe735561cb34dfbd7991119ff03	\\x1d04082ba9130ef902b2445d2e7377d61a708ba21ed840f5044586aedec4d4a671de5b26dc1d91d49ae1bae0e2d3ec70f765b821b2de8f7ace0fe7fd36406d0a	1669297991000000	1676555591000000	1678974791000000
4	\\xd1716f1ac7e2677b09e20b0d45145cd764dd8b2fffd2eddb4731f76458ca4048	\\x969496b43f19a68a3031276ebe786be5bc2c029dfcbd6c5bd39285cf6277186ebbfeb9b3c01500481c98132651fbf9d999f55ee52570cd20c13347b6e9ba450c	1662040691000000	1669298291000000	1671717491000000
5	\\x1ebb37961dccda92075bb1f3b75cd111f87fc9e5b41ef96b64d33bdb1bd41d60	\\x483e301ee6d0a8bcc5f632b112e22c9d547895ec53730dfec165c5a7a728fe742fccd54d5cb0f718f50f400988fcdb1545ecfc13dd164f0b1b45dc0d06c70801	1676555291000000	1683812891000000	1686232091000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xb589dbcd610ded9a6dee0f891b2b9b7a221669156f8bbf8a771b832f2718f9bb21f1b688a8efcb7b6e061c092b41a384599f88d1ca9aded10cb3ddbb47d7f10e
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	342	\\xfbecda45f464f6067b44af539991d98c1ee5931f1e3c2fcc2849007baf748a44	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000004eef31fd1b85a55430244ca436fa49da97e03a06e7cf28294bd0900169531a7be7aef195933549f7ee908a63764f9250b63136846b247ec84ca433e2d0d4ab822ac9a6994b3432a557ad17fdd9c4d8af0a108c1271644926fe71f1c9abc03f93dd0e1561b4e40e07e7e906878ef4cd013857ea044a4ae2efcf8e2afe433c608	0	0
3	402	\\x668918ab585e789cd3bdfa5a7f0e1d0775141d45104669300e40165c3637782e	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a274f2a23a61867538304cbea846a748b684d53e2d095e2f59491a44aad419da79ba147e930df47c0ff115ce493f14a8fb5168d7f62c1e01dcc9cdcfe20d6b77a8085e6d6a1a3840de0415c224045b07d6037d35cb3a79dd19156bffd33d5844fbc82030aae112a18b2d78658ccff3f4f965ea6a7adedf4ab51291367eef34ec	0	1000000
6	421	\\x10ae0d370fa743ed0eaf9edea6fba028f8bf6d4dcfd03ae3a11882606f500dcd	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000749e8efe81a53d24f142a7003ab123ef9a25abd8948aa4c730079f660a1e9d23b1f182f567a59fa5a3e7d9631e7696013b0324878db892c9ca14784f88e4fe3b523f5170769702ee0d5402fadb24e48efad286509352f19f5ddef3c696f2d4b4e910bd19e602608b9790fb5d712be5021e19f828aed4a47d05eb55c588aed88f	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x21e53bf2a6559be8c51ef5f5367bf151b1671d419ec690f1eb621fe8b04c855201dd23a575d89b3eccad9aa2ca608de0a42abecdc5f443e02ab4fce0184586ee	\\xae00ea5c58ee58fbed3db632cb0b855a	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.076-036CA810WSH10	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373532373030373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373532373030373030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2234374a4b51574e3641504459484838595951544b43595a4841365250453741314b563339315746424338465948433243474e3930335139334d4e545848365359534a50534e3850414332365931393141515636574258323357304e42395a373033313252445647222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037362d30333643413831305753483130222c2274696d657374616d70223a7b22745f73223a313634373532363130372c22745f6d73223a313634373532363130373030307d2c227061795f646561646c696e65223a7b22745f73223a313634373532393730372c22745f6d73223a313634373532393730373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22364b344e374b345633423139534431583154444d4d463543564558434b4a5950303742324e33544730344252573941334d563130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225444563053303657544e445742465a5842413138563845525146384a35595734545431463958594336393444423132534d444747222c226e6f6e6365223a224a3147384b524d34503752305145565a51333633513242573647583247504a415044434548563237355a42395957384b43305a47227d	\\x69e9ca3356971f56cba23689a974100693e3c37bb940e04bcabc7dbe18ce160d83dc78a68914ef3d930b5f56f5e3140820d73e4b791bf5d434cc398cf8790478	1647526107000000	1647529707000000	1647527007000000	t	f	taler://fulfillment-success/thx		\\xf12485582acd6ac1473f8cb08b832dce
2	1	2022.076-000AZEJKG5BXT	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373532373031343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373532373031343030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2234374a4b51574e3641504459484838595951544b43595a4841365250453741314b563339315746424338465948433243474e3930335139334d4e545848365359534a50534e3850414332365931393141515636574258323357304e42395a373033313252445647222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037362d303030415a454a4b4735425854222c2274696d657374616d70223a7b22745f73223a313634373532363131342c22745f6d73223a313634373532363131343030307d2c227061795f646561646c696e65223a7b22745f73223a313634373532393731342c22745f6d73223a313634373532393731343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22364b344e374b345633423139534431583154444d4d463543564558434b4a5950303742324e33544730344252573941334d563130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225444563053303657544e445742465a5842413138563845525146384a35595734545431463958594336393444423132534d444747222c226e6f6e6365223a2241435132423553503834394e334342364d383654584135464432355a5052354e315451364a4736533352574742374245574e5647227d	\\x2b6a68f162272c2b078b8e661f2043bca07a768f7c5b736f3aecdcaeaef7179f19a59280075c502d2be9c021da51c30021736bae42935dc6f63740512058f83a	1647526114000000	1647529714000000	1647527014000000	t	f	taler://fulfillment-success/thx		\\x649ab51053c238ad983c50e22e575d0c
3	1	2022.076-00YD1ZDP3QM7W	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373532373032303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373532373032303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a2234374a4b51574e3641504459484838595951544b43595a4841365250453741314b563339315746424338465948433243474e3930335139334d4e545848365359534a50534e3850414332365931393141515636574258323357304e42395a373033313252445647222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037362d30305944315a445033514d3757222c2274696d657374616d70223a7b22745f73223a313634373532363132302c22745f6d73223a313634373532363132303030307d2c227061795f646561646c696e65223a7b22745f73223a313634373532393732302c22745f6d73223a313634373532393732303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22364b344e374b345633423139534431583154444d4d463543564558434b4a5950303742324e33544730344252573941334d563130227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225444563053303657544e445742465a5842413138563845525146384a35595734545431463958594336393444423132534d444747222c226e6f6e6365223a2251533539394851395743574e4136443252344a41384e4b464751394158474b59544a545857535336544e41473859415230374730227d	\\x010fa0a728acda1441f64f559f3f7b35a5299d5c34d575b3b3b62b11adddb180a3253ec4e3edc68843e8f7dab089e704dcfa99cb9d1da027213fa23f1446406c	1647526120000000	1647529720000000	1647527020000000	t	f	taler://fulfillment-success/thx		\\xc456521e809a0c6bd4abb77c8f4dffc4
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
1	1	1647526109000000	\\xfbecda45f464f6067b44af539991d98c1ee5931f1e3c2fcc2849007baf748a44	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	2	\\xfc9272af06696cebb095f742e6e30de45953832e73718c092bb055ac4bff885f37665434addfe32052b2594dff335f0b365b12b42aa6fe56b1f7d521155f780c	1
2	2	1647526116000000	\\x668918ab585e789cd3bdfa5a7f0e1d0775141d45104669300e40165c3637782e	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	2	\\x1d968c2ff4ecc899824bd214978aa656587c1fe52e840ce7de7f8331cfaf69d3d8208284dcc96b617d917cdbe796bab73aa0406880079c51e1f57f56a35cce03	1
3	3	1647526123000000	\\x10ae0d370fa743ed0eaf9edea6fba028f8bf6d4dcfd03ae3a11882606f500dcd	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	2	\\x3f5aec6024ffbe7ad26e5bfe167d4d94fb6254d4691b347e60f4f0f8768676ec7bbd42db92885ad0ae2080677713054c33028cdcf550b24fbcade4d8f1a9e40e	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	\\x60c54b65fa9ebd5d4007e9ec534f53578c8ed29d9612cf09f6f8b88cc4bac4e7	1654783391000000	1662040991000000	1664460191000000	\\x365c81f0ac4131b1c34fe33cf3b917534b3b892e8314501c929f4f3e22efe4827d07495c40f50630f8e94629d656d29bd106c20b9ee3a06eb42abab3066c4208
2	\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	\\xe793448592b9c003e981c03d157309f98648b443f3d6e08bb19132f31752fc21	1647526091000000	1654783691000000	1657202891000000	\\x2e6491ec566710165e718d980f07e36c83948353e01ed42db720675e8a201e39d7f912b602fc2688e0c5ad00897267f5a00cb2af06d3193d4821d31fdc63af04
3	\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	\\xf011680cb9e2540d62033e53147d3f4ccb277fe735561cb34dfbd7991119ff03	1669297991000000	1676555591000000	1678974791000000	\\x1d04082ba9130ef902b2445d2e7377d61a708ba21ed840f5044586aedec4d4a671de5b26dc1d91d49ae1bae0e2d3ec70f765b821b2de8f7ace0fe7fd36406d0a
4	\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	\\xd1716f1ac7e2677b09e20b0d45145cd764dd8b2fffd2eddb4731f76458ca4048	1662040691000000	1669298291000000	1671717491000000	\\x969496b43f19a68a3031276ebe786be5bc2c029dfcbd6c5bd39285cf6277186ebbfeb9b3c01500481c98132651fbf9d999f55ee52570cd20c13347b6e9ba450c
5	\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	\\x1ebb37961dccda92075bb1f3b75cd111f87fc9e5b41ef96b64d33bdb1bd41d60	1676555291000000	1683812891000000	1686232091000000	\\x483e301ee6d0a8bcc5f632b112e22c9d547895ec53730dfec165c5a7a728fe742fccd54d5cb0f718f50f400988fcdb1545ecfc13dd164f0b1b45dc0d06c70801
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x34c953cc9b1ac29cb43d0e9b4a3cacdbbac9cbd601d62a8f5001178e2543a6c2	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xec92b8edc45e7af65b5b1fe305a81b913b383befcaa497f801ff31c2d1f63850ef31e9585efe4477797155a586cf369173c57ed7390a41866703193ce806ae08
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xd3760c80dcd55bc5bffd5a828da1d8bbd122fb84d682f4f7cc3248d58459a361	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x49b867cecc5219c066815c167717626dfcb7a6d222440b973c47b65673db2aff	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647526109000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\xe6989ae324be49e11ee3727b9556656a286bcf0c80d62ac9b83b08476c778f8599c9d2da9e1f27866495f30ac81946ef034310fcb7886483634017c8c9440b05	2
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1647526117000000	\\x668918ab585e789cd3bdfa5a7f0e1d0775141d45104669300e40165c3637782e	test refund	6	0
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

COPY public.recoup_default (recoup_uuid, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xf105a1721fed163a0a5a58c0c1916a0de2733de196f0eb9a7406ed1acff1481e1ca8a08cc86f60af11b9e4cd3983294f5561083d7e7a18eaff2430e32862f9ab	\\xfbecda45f464f6067b44af539991d98c1ee5931f1e3c2fcc2849007baf748a44	\\x4866837a205cdc29332dfa105db5b0203db0beeee73eb81362b6b504873f52353a5af2a2d3e9aecdc693bc52a94cefb444f612e436829f0f596494bbec9e6606	4	0	1
2	\\x522b70c476500a771c45478c4312f743709bda719001ac28a4752e42a32ace3b3fad0354f7eba7edb2c9b89373ef63e3062f89ea8785a49decd493b04756d027	\\x668918ab585e789cd3bdfa5a7f0e1d0775141d45104669300e40165c3637782e	\\xeff392d2588c9be2e212371e9f02cd10f4a20a40d87093f6acc558725d9664aa20bda1855f95e6fe7a3ef3d001bf8a06510cca4e31ff29ab83c04019a9369d0e	3	0	0
3	\\xf16bd374fe28c72907d8e1f6d49ff9a9319ee3bb0a666cb64c88e9e2843263e5ab162d1feee4f1a8399fdc7b08b23dd3afe2bde5f922ba6e7b39fdf4d8517270	\\x668918ab585e789cd3bdfa5a7f0e1d0775141d45104669300e40165c3637782e	\\x37c7e472f5e54216d4099280e3e6f186fd7f5d99fcda70c98a0ba86d4b6aacc0695f78f95471e74f110bbaa4a84af49a87f15f875b7a3213d7952c5c905c6f0f	5	98000000	0
4	\\xdfe32339d1428df531fcba24eb3348af727389e34ef5c040bb82cf1054da50e1b23264763909e43a9b167f087bead97a5043c13b5dfdc9104ae7eaf171f8f482	\\x10ae0d370fa743ed0eaf9edea6fba028f8bf6d4dcfd03ae3a11882606f500dcd	\\xac5721de710ff787135dfaa35efcfd91684108cec51301d605f977a021b87f51cc43f8529207118db9d4fb74f2b7874e85097251dc38aea034180eb85cc0b80c	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xf2599bc6ba43fd876bb06cd6879b20c9842b4a4ad2f1744cb378e5a5e26c2141b5bc63061fbc760ecd15aa5c9dffda9055645078cbb45d040024669893a8040b	201	\\x000000010000010009a9a61ce3202a218eb7878f335dab37352e54f4e1f41ecb8e827433642f12421315d8872352c5bef7bfe8bb8ea8fe36510da95ccdccdfa45ffb374e239af9e48fb7cda22391e8e81c7b2e588cd86b85f0e57ed06ee04a94d21a6edc1088cf78246e2f22a080fa3662954eb2f062700cb871d635d6a0f638098c224039e7315b	\\x6f42146339a60a671d729b456237d5d0be0780c2821c4fa6d20df469dae2127ed0a26baed3159120e6b53d4d5cf911b05d736108646d43e89f21a1f5534f7e91	\\x00000001000000019a654245db76c28253bf10b0654aa9b57a3ad266956c261eae9f6007bdea75718cf7c0b49977e730dbe8b55fc8100353a0d849d29f5215a9d57215a8691ff494e4a2eca867186014f2ca9caac2422eadfe83af5af21ed25b5d9c712aef289cc2dab0ca8e95625f9bd0b4696a1773d03642f3036a7478062f47c626a778235064	\\x0000000100010000
2	1	1	\\xa5addb24f73641d005598c2b8995e7d32a2919ff4b1fd98a7d19b3be90ce71ca3397bc6fcfc3bfdd61f7a37eda576a22867e0cac8d4fa1af5ffdd58b5bdbdc07	51	\\x0000000100000100216cd667addc64dbbcadcea1e25a61a7837181d62829915ccae1bd3cc8e558f8c9fb632a0b7725d4fc81a0888731ef90446016a6f6b7688f0d4354840c15be0065c347a71d0cecdfc6f5e39f630a5b1a97271975b1d28e08569b6c3bec7c4b63da46ea3e1e4bd2dca6b87e0fa2b0e93e6b71f48d06568647f82e8a50be4ffec1	\\x4c3a7ea01043e5d091605bc424869091a96b9df49fa4546c1bc17c79878897b8e0962086bc8bcec729dc569b7cc0242397873ee7d61e5dc7d1f5dcc2b82735ca	\\x0000000100000001acf7c726ffb0082ffe29fa898ed42b14f0f32c79d0c6132a1c6fb531ff7a9d132b3818fd5d6cc1cdfff18d3fdd5e25b1e2e7aba5869bd2bdbc5faa79db98778eafa8e440de0b90b776254bb61c5064ed44842614557feccff77d19b490cc986a30593be40380104953ed3a5cf9548ef431b371612a82ca28cd51cba2c05889bc	\\x0000000100010000
3	1	2	\\xc52718343047158b06d8b64390f74cfc35fc54d0dccd9ad0a5d0603b16bd4a3c6061f984c66533cd4f911a3e1ad4ddc96cda8501feec22676aebad0a1bb6660d	75	\\x000000010000010033c3340f1b18491af3d9b70b51fdae44173a7d451ac89183892ddf926ddab8a4a818f403942ac7d19efb33e6cffd450d2725b04e578eafef32b9e6fd583ae46217db11f0ba98febc910e6c9c7d1444c272c54ac32b9a800e9b2ef790899ee34c0c0103c4e67d9852a79741337922a139861e24a750148131654d0d6c56e584b7	\\x888b275737ef1147797c76c9d86aa167dc9276a951a4e7a29461245a94f68f4fe92d082d367f0f10a52d7fda048466ce879f72fecd4ee5dbf2e3ee71b0bf6ed3	\\x00000001000000013de80c0f6a7f26304210b08827f54cf783bd0a50db1f02fa1fa1a62e75e78fb45493df2c501729744a5c41bad094d691d75297fe105076e6f2f630b0897b80d46e74c562ffe67fddc8fb49c5aea923682e49f6ae3e9e19eebd976f540c4cfe97ecd945bf9fa8c53e28a4a687263e8a1f961d24779373481b744d1185e5e4bab8	\\x0000000100010000
4	1	3	\\x5acf8008b612fbafb30e79de8ae407441845fbaac626134632d870e9f0111ebd751116deae777f7e653d2b684a33512807d6849d8a2c17b368fc3d9d84197b0b	75	\\x000000010000010033c243ff9996af4621076be497d50d1d26093cfa2e0b7c3a8e10a15f70ba041c92977f737c54e97fc4dca3fafd03f83a9b9b36af9a7d9d9ba5b00789b1d08390a02df4b34e07fc69bb94c45c491c1e16ed60a4531ed9740ffd3d373d635ad45a500c453f4a620a44dceb8232e31648b209d7692748c0dcf46a076650bcb337de	\\x793b4753b5176c76d24da49dfe7013376ef89b2517374f81af5a3653a54fa6931b4eac9dc661df78270aad00f6b2816f89ba6e3d1bfffbdc4f5b45280536b99a	\\x00000001000000014067876c16a9ec1d5e894568fe9dc1204e6cbe2f9ad5040a015f998df4a1ae9f1c88e265e04edbb28ecbc2c5dec95e8d9c8566ff957693f6d2393aa6d77238bdca9940236941e958bdd0902f922efe59fbd62ced88e75f1743f202bf72137059529653e7aa026bedcb085ddde4238b0d932dc91f595bdfbebf870da80839b39a	\\x0000000100010000
5	1	4	\\xdb7c40f8dbf1d88f6b372237219e999443a8405116836a9b51b25e1e5377d4562ef53d86a40f1dc24ca569a43ee440f98b33d224b3bf5c7fd63f1f6805c9f803	75	\\x000000010000010020bf4bd53fed8b6a761e4f7873ab4b6c6456e927dfc5b12d4dca11e090a8aff908af15e78020e54bc1bcf86a4b0e975185d2a415494dd4930902a55d1f88df8694bbaaa890eb01168d40ba16c1168cf630123cb04212c68a3ff57bf2abbeb081cdb55868ec86a6bf0c43114ec2cefde1d7e4061d143b2770d2b7b81f09c696b4	\\xb94d302d43f028a3c41b084868d9e07a33255954c53d1e560b181beee5c0e9c8245187f6c2ddd9b68f603c54d32abc10167b9de3480f3bbf9f28e8f5dec38c06	\\x000000010000000196093106806c7aed231deda6a05b0f81a0fae910ad58535d907a876bafe0cb8cea4817344e6f61888a87dececdd33162cf510fd45f3eca7fa8438d21c2c5a4222501de1f48f72ce096579d2f704d5956421eab71370d36cef6d60fe283fafd2221be81abb5b929b9fb40527878e13b670aa95b57d02d0403e3a17acee507a727	\\x0000000100010000
6	1	5	\\xbafbd39c602ad851871950308f6ff1698b43ed63da8c54389ac950be00a465a06421cd91866639fb5b140d1d2fd8c87e6813baa7d426249b8feb05712e9bdd03	75	\\x000000010000010003808a1b8b52d9ee8f5bf086bb077caa609f4e38749c94135514bd2338dab0f6cbf68f559c580f2f3230d1b90468f3d40938f4f864c219ff19d7a05834fe7ec1a0a515fed00989ed8352813bdd56c245e2132ce372a184f979d89138cd19639cd937ea416f149c14fbfe340df5174ad3c1651c32af4af368927becc416bab828	\\xae3ebeb2670c94413030c81beda0bf81e9996b853842595e568ddb63798ece5b2f4549853f3d8cccdb6691f69a9f90c0841fc3c491b277bd765999ef6994cd78	\\x00000001000000017b70a5bba185dea33ac36a2a992eeb58e2bb7856c35c69fa03fa00c882bc163a1aa38fff7d953c7826c4d6b085ad498ddd6265aca7f58cf2718c5a6a197f913fea2f213dbd477ff7364a69dee964965617d73e6bef4d19c8020928e146a3fec9f2a6b0723e262bb74eb67576c9b643a1a11113868d566578a40306c0c3af5882	\\x0000000100010000
7	1	6	\\xfb459d9acb44d45563b653e28f32b9f78228ff5049fd6f1157e56255a847865bf8c39180221856ebe9ffb4410cf4cf50674e4d84d93345a321a063975244dc00	75	\\x000000010000010077d229f138e737f0863a598b717cbc0e5d337e2ec5258bd994159c001ff4f519b0f57efa915502d0a00f5eb5d61879ed18882207b72ac2b87b7ee6866c1757364ba58579b62c48d1b9bebadb36cf462e4989402c800aedd10984c5579ea0a7b311f16e82dac05fa38b094aad8d9e2a97c274239d51a21cbb5f6e0d5ae5353938	\\x7f415d0dcd09d8faa0de2b49ab6efb8e11c47eaae5ceb123dfaaa26bad70f65dd7033a0b67ddb6ead296c292f9c0c51f24dd2299c2202a17641a43687a85c487	\\x000000010000000135351e000c720dcbf30b08fff8a301c0a0983b2208398f22d8a75b147956db308f78be2735f801ad4f670aeb1a296246cc0a8bd57af6841302f1dd4924151e21ebfce9e88c499ae41b27ade0cbedb3c27be99efe803f98631b04518c6e39c0c4975b537915b492a96dcb20c2ff2a68b8ec9028357445abd62e4b7766394e475b	\\x0000000100010000
8	1	7	\\x458a594a617f379da6d438b925ccb9c57a295026fc8bb5a7ef112fa2058a385c3b97dc960cc83dc3aed667d6bfc50c25b61545b89d24195d54e8ddf437620b0e	75	\\x00000001000001002ef46a578db08cf4878fd81673973f0d3591ceac42013abeec8022fbbe2942e4f73e28fd3266a159f5ffe22fb8981eb115ae5293a50928a399b9f2e45f30db7984b284d5175a3c7eba6aa6a3315e0d1d68377bd8f93f652ddad480dd12c1bee05a371a81209b17dc7df376a3d7e1a30792de2c9b46d6628d199a3d64087b3a95	\\x21b517feef36bb2877b6c03dec01bd92ebd9f57a8859d67f5dd8ac9a4b0c06baea86243bd784d83b11694bf08b077669454ab8864136b93d40870f20c7e6c6b7	\\x000000010000000125a9a0180c82f0cbada3afc9a17b7fce88025f867de65731d92fea166d437adf8c2c16fe812ef3296d561c22194f3ec6244459e990c7efb9c9547b928f8ef7ba7a7569b4b1bc54aa5ce051d587f5f2b7365de6fefa23fa39a0793c28325153af8b9ee8f44b5cfc9ece53dc33c95def205bfe950d99c3e143d986b39c051e401e	\\x0000000100010000
9	1	8	\\x69f9c3bfc8a98fc5ba44ab0c3bd941c0a4dd33fe1f00ed7ff5a558f0b8b12e48bc82bdfc73964ad5841d99ebd59a4807741924f5d936b246adfc29be040b3f0c	75	\\x00000001000001009497112fcb5c94b06b60183bd5cd779ad552ab13f5123f14a42bd1ab330d5e21da152633553dd62c8b30ddf2974fba4cb735a93ad8c83b51e25d14846c30726145ad17326e8c7975b70f4e0c4578586e02bd2a55b3c5df780b7e4014aef70a18caf9fa284df6122b577347ed74019102dd2972ed02cc44b9cbfc8c1619c66f3a	\\xa35f0eaa640de99cc527f253106c1250976549c368974d0e521315a7922e8700061a042c4178831685ca5fda08d30e8064f633f45f0a3510cdbf0c0362df6791	\\x00000001000000019821de7061e7f4579a8b435b0e2d15500d28543d0a3af65df8448ad266b5d70fd1b786a231ec0a0d5e60013587573ed9d7aa7d2453aae1744f5d840730d424d3e86253c477c352b44439501156b0b1ac809120e426bb0d0f0836093a45dd90fd5b9dc832d22840f81781d8bbef22d089d09124b11212c2ed42e3812fb0b561fa	\\x0000000100010000
10	1	9	\\x35e1d25ba4b074e3cd64abfc6b2bdfd07656a4aee86dffd7cb83a3657f55a26552b7628cfa50bc73e6875822bdff2c1ce073794e261e76e4eddcfac5efd4f90b	75	\\x00000001000001008de7ce3c54e05c37655f6ae23dfd1ddaaa7a1736a0a33425738be2a46ad5c59060ed55131546d3165b4725bfbd5402a3c28e7a8a2367ba3a1469740b055bcaffda3cbd3ee4786e44a78b691e41c2cd6baa8aef44be2768cff868c0482de949b1d8478a2952910b4373e2c171436fd3d0a7869112b7b70b8ea68ebda2612e1f19	\\x034d3bcba47e303a419faabbe57ff58abb9361466e58e276bb504032e8fa7f9c404d81d388726d26e6ce48f9810649af6965e480632a1752ac95be6232afdc97	\\x00000001000000012105d41cd997700f19dfc04d742719e8c07f0edf32bfc6a663e787f5c0106eb8fa3abd8027d39a9705e68536e3ed5ad1bc90be5ba951e01ac9507f04ee63ae3e0d1644798e1d6dba1d5522756a64f2ccb10cba4c4570ab29bf94720c395389ccc3ea7e7a3ba4f1f9977766d2ad11f7599dba8f0d1017551223da931c0eb68bf3	\\x0000000100010000
11	1	10	\\xd50d9933068641fd40a4fa3a06cc5c3be9f13bb50be934374af262b7b0ae60206c3b1abb19de2a069f91ca6793e4e5743b8aa779ffabaf1a9922ccb8ca9c5d06	220	\\x00000001000001000fc398bc399385aad80656e650a1127a3b2c5ec5b979ac914ff837f7a7fcacd01e50ea5acab10924055da839aec76f1a348470947da2046c4f6a92c368b6e91021c04e3c1a7d88e8052d625b0bef1dd2033cc64b7894e913f2f886339059a17f24e96cb382f295ba6f75ff5688ef203322f3554c9c22d705fc3206bc8d812fa3	\\x09b7b9b0f87556eaec01efdc8a4c9e14b19061832cefb34b89c89a9c7ebbff9548fa2f11bb4d54222fd8506fcb5aba6ea41b3af798d86577594161a0463454f0	\\x00000001000000019df65646e41a902853d2484df01024585126b2401513e6d32ff3114bd0857079cdf277efc4fc356512dc8f909bcf70a0efd70413760e6483c1fc16a18e93dbf1839c9a471e0eacc326d15c8a73b5184cf4902910c2869a4181688e46cfb6fd98aefc63d011df0df4730e95767cddd203e33cb082fe235c14c32bf531df8ac81c	\\x0000000100010000
12	1	11	\\xf7320641eba593d1768b4913a8ad0e36ef6b09f1ce69b423494ef8f81d0c7cf3df1533906f61e8593fa1fb890f79ca23f35e00b63d6f405f029d551a8b090f05	220	\\x0000000100000100961987557dc364b9e3ab9e8fdfe09ce023788ce6e9e2dd7692eb255b5106ac61bc3348191190956cdd37a1450792b129ec25a703561e9038c8a5653e67ad5dcc9e0fef43193810ee31996a9b1e83d6041d7f5029e5fe8f8428cda5f6f75913c5daae570fe79f99763038d66e475148650323614927afb97a0253c7f89063b737	\\xdac5ebbf3c9fff561ccaf387f46e1bf006ca59709d5181e846bd501cb699a515d9c6ba52a4d4b1e82a9da8e08486b731132ecb7b8b21542f378198c33762b37e	\\x0000000100000001c6031bff14f091e853224ac60fade1ad4776815ef3427b207ec8cc2db667a737b6c1d9a15c505f1eca40ec451f06984cc48aa817a5dbe6694c6cdcb4503ead83b4245a820955be0342c628a7e33d355404c4af3d0db80bcde06727aad75d5e2aa2f3845528533900c8db8604e5a74e6734be525dbb2e60f8b01277eb1496dbfc	\\x0000000100010000
13	2	0	\\xc5bb4fe47d040839def786e2a473d20485b33dfd169972b0ca5031fac2db197d543aefe4f1c2fdae7fc7c9a4b87816f79bf33cdafeda519ecb1a7fbde9b98204	201	\\x000000010000010023821077169cd0ce818eb152aa8b717f49f9e8a8163774ecd5bd4212f1ec63aeb73b6b162df3561234ba34ac0036a52f0fb214d92038f4cdb801833fd307d98a97fa0dd0817a87cdada159615db3049dd0dd6fc8914cfd257f5e183a81d62c15cc9afb44a8e3abea722f622ef398b799c0818536c8fd9e767ad1b42ba031f2f5	\\x4138808e5d54dabe6545c04ea2e49860842889b1bbda63d692f531144afd8e144f3889cca034c65602aeebd0366866a78f908adc544c058643737095f3ae716d	\\x000000010000000158fddeab5432c2cf59ab8af28d32a74ab34401246dcc1c3e5980e6f20eae187c7adf1e282049ba064de365eb40ced93ac54231bd0091ebfc83aca86746d0dcc7e725b4c4504f2c92a715094e226012aed91a7877c537fe826ebd1fa4d6c930ff6386d076adf337785bc34ec593c2c3e4db419e2ec7a4a947febcb9a100d55097	\\x0000000100010000
14	2	1	\\xda7c17aa417ac7da64d77eb7626c9ddd630eefe7be2c554c3dceb7b6d9ff2f76c6e5088ee0707a30e69b72cbf3f8a9fb06119fed4b1d8fb350cd440527a34d05	75	\\x000000010000010062edda0dd5f18bade803c8b67a52962fa1a9f5e956ab4a988e17ba9a5852119fa17e5ba3c43b2841adeb22433de80ae21622e08facbbba0dff600d87c3fab30af8a80cdb08587ba3104e0e60b726c406f95940e6a65093dd5135d498feccbbd37459617899175bf77e3191828d01d8055975d3c9989d83830e0d349a3c6c5509	\\x97d215daad1d708dfa2dc95b0d7c2b53e9651d1e670463c56578b454958a56c517878425dc87306f85c9d83123eba06d244f9c061114551f276290bc00536003	\\x0000000100000001139d80757b8cc588af6b37905f9c9f76c6d26313be634ce0488d8b696411a2e6e35b41252b4ba8c6e138814283d03c5c2de4f407eefbdc33477172c03319fed7d8c932b9a6b921c0e438baed6d97885d64e11b08cdf8f81c1f99170362d2110014bfadb95e03f71a02b354e227144cf4d2a8eae02e146315b6e35ab04b82f8ac	\\x0000000100010000
15	2	2	\\xde3471ae3f4ca79a932e2a939d05f74c7411d531c94efda266dbcbb6343b805679168c731602d0d3e81427ba033074ccb8a2136a76cd5315d8672c4840490d0a	75	\\x000000010000010027eb2377f5950d5620a91ef17e488d0e3159f2880f020a1c1a5b38cd5edee5556313035feaa6d0480afeb2678d03bfbc3a8f77b52520d144bc9243cc6a5ee6543fad539e66aa6c43095538077dc8ba156cf4356ab2c0b230ca611cac1cd89e3403447ac4e092cbeda3c39923e632008b84a76c34db5447be1b1775e208f58bc8	\\xcb58a7e88f961f7fb8aa59156e23ff45c7b2efcbc5a33f68c792bb3ae3fc99915f85a1154d6cddf43a4e16244220e03528eefbdd582edc6e5d4feb5775d771d6	\\x00000001000000014f47c3e121f3d5627c8ab931e60bd2e527631f96788c2152654ccf196fe692ecc40f5f6af7f1ff85d1bebb2a61e1faa86715d45bfbb56fac8dbf5b979430770cee050fb1fe1175de285f927bb2a5acc665c49f12bd63149d7fcfffbd60c8fca8254ff751dc84da9b94f55f8daa63c967d972bb6ed41a9e0ef149d0a2a5c97ee1	\\x0000000100010000
16	2	3	\\x84ae82e276f094fffa62af78a368fe1f64c3be7ebda50a1971de067b163dc4dc19bd37ec0cadeeaf2836b06557365d2998f6665aca569c560a4a913da247f901	75	\\x000000010000010080624de7a169793b85a31f9731f4007e926bb292ee5e1c3fe3e997b4caa956b7874ebf35bf0f461f871d829b1d3122d8579cdf5f4df492395a8c32847e5a1cf6260001d6f3c17d4b50e26f792cf796dc059110763e0ac6eb81a5013d47329cfc128a367d924910f20e2506bb9b650ef8a0aa2bcef1458172957ab1c0b5aee2c2	\\x5200f2c835555d540f562608855079d3bf2f5ad7fd68981e8eceb5d9a9d4a8bf67d878f0004263dfc7868de147ea68b126955600f0677cbf7845c21995e3dc75	\\x0000000100000001457eebc40a59aba84e3aeb04a7d4ce9c0ece547bfd45c5642db46931d86f502bebb138d15be409eb7efb74541d30489d64c8224e43c4883dc359173685b1e6061cbee2aaaa5e038447b66eeb2adfdafa047edbc92779af481d64207e68da97c16891bc39aaddfcfdf5c0920ef81adeaea11e6b5d61375d774e278323e4c0e264	\\x0000000100010000
17	2	4	\\x1b7202c28316fc5f6cdf4b5492bb46e4cac86e74672b2908d1a80cddd33073c9e9d512eca8467e43ba5466d29a1d90842bf15d0751af37f6a7c8b347f8f9800b	75	\\x00000001000001008a01fa03cc55a1f2e291d8715cb1ceeed72e2c3a68a2404e25fcc69cf3887a642092f1e0fd6994eebb5a3d1e64c1fe4b483b235122462ad0e8d861f606af2f2856b495f8140ab8aa0ec1bece2de78ab986300a0c1f1012b4b4617c07dfb701e3614a198dbcfb4102a100b8aad46ac61c526f5f5bba2c7b40a78b2d90dbd442c1	\\xd31f9b3b99f0a9c938b51a78fb7190286057c6d86d7df8b04aac2604c9517558a1326bd0dd031fdfb4fb9eeb02aa1358ec99383dfd8756e5dff0e88a1f1a3501	\\x000000010000000159cbe08c36cf73b192eafa37cc1930e51e14e65ca0d4a53420831e109207a630486fdf2b9163296103b7a1bbf27bd1b30c6a9121c33a918e32e5cf1776ce78fe2fee9bba45a7428df019414710a9304739e871882390713c23df1137043a63ade0738bbec4bad10d422a17585759ff2d66bdcd2d17afebc05ff2514eb345f1c2	\\x0000000100010000
18	2	5	\\x968bbb90cfc96439869b2d988a954034119203ade6579b12811b649288fbcf2630d2f4c39561457ea529ed3fdbd40d9819720f85fd16964a1e114d20736d2204	75	\\x0000000100000100099a472aaa4a0e3b01c67fcc60e7a6c4872b28622e8ab9f830bbb3256bd3e43784abf571b9867ed034c237675b4ca0eac4cc034188bb7c651c0eb173a195618683c1bce7aa925da67c32e763480b80580b5878ab1ecfd321597528fef6cb5f2988d209fb41d6dc53b7f14c6698a194cae2d7ec2dc9bdcb09edc192e671a94cad	\\xb9d6b7e283056c15bc2238f2047a14a4003e4822654a0f455a7987e5513ac8d43646d905d20cdca6055a9aa4bc8d5611bc4b68e449aca3ce716dfb097b857c77	\\x0000000100000001347ab2227ed2297ee6d2a474e0caadc4e13fa7c41c9dc7deaa595aa2bc6537ccb625ddbb548466ecb9448adb14ba8e5084d6af013ddd5824e3fa6ae64d3aac9d5ccaccff9abcc8b4035a49f2d04e31a6e8afa313c1a42618d2667d3dcc750927db51a02aeabc2241a6793906249100ddbe6bd09d82cad4048bceec0185553fd3	\\x0000000100010000
19	2	6	\\x29785a91bfef08d8fac355622eae2ef88c9ae108335962f8a7078172300d225c1b658ad20b387509419574740f81ba9243992f3d1ed6d56e6b199f55d5b7af0c	75	\\x0000000100000100865362eacefc79d37b85ae35ba6fdf3ad7adb0bfa48f087039b3eed30ae825a3458e6f8d34b1341a165d18aeb583b2db1b20f794d1d473d46f94683e39fa7cd1875ed439d298c1dcbe6d61d045db0ba70eebb1243570cd05ebfed0502a3fe5bf4021bd84f8e9bb93aee1f33cc01f2238b5bffeee0a56e8f9c0ed7f1c8e224d47	\\x287d769ea106f789574c5ecee06d4d11dec9c5235e0553bc6b32e6aab065b402658bbc75dde20d778c9208f329b61303e889c7a0cd0487bea0dc1324809a22ed	\\x0000000100000001927c1644ba8bddda759830143de28c315babfaac9bd694b4fd1eb743bc1abf33d968783efd5b95819523659d46c24cc2977ebfea4d84f3e5beb250166159a2b3d5f2a87bb34289f397c9d67eae7c206affd953f65d30a552e4773f7f34763ac3808061a41ad030ba0766130ab19abca8530d086833dc3313a56b404574f38a71	\\x0000000100010000
20	2	7	\\xf6ab2ab0bea8a906389aa8a8b27c6458a65e07c4e08a4c6fa9770e4a778f03ebc16bd2f5ed2aefc4453ee924ec6f10e57fd4861c551c56480d5fd5028f713001	75	\\x000000010000010088a0ebdb5164c80935ba9e8dd38ccb0555671b1fa0815a3698992d7c4d35089df6b3abfe86c105f258656e5fd3702c0aba35e1a23e9f90177c1361b6e59c125ccc333d41a36ddc9ac9d09cddc017ebc0277a411ee9f31ec2c5ffeb6924e6a851ed024a704550c4dc025681c7a71b8f58e13ecb3c408f91b8ea29adc8b901ec64	\\x176456fdcd62787b489ca245a58732325146465a35facf4b4b4bc027fe7a2685ec108d501aa1743d4a3afd33dcb6cb90cf85f9aede81a74304c24e4187664cf5	\\x0000000100000001470448c9e040a88f95a598ca86edb96f748c305834ffa333e0aced0a76a55992595a9eea2699d846c92c932c18ffb102a33451c657e3adf1ceb7593f1e09c1799199116598feddaaa58d047a9199dbbda39a8018e50a351b0e00c497d98f6e3153c08c8267f7dc15e3f382ee438236bd0729fc00e000989d8ab7607b6fb3c803	\\x0000000100010000
21	2	8	\\xf2746331daf2057718a316b9632ea542eead2d29aed7eef70f0360d48d8702ff6bc1b85a12d49878b6644ed8e8aff7c7ba0e2193f2ecee01186ee0c03fbd840b	75	\\x000000010000010041bc08e5f2926b8eec18d1264b2d963b7d15e7e397441b4c7428a059e3d3467c004775b2fe43c6ad7c96adf44671955d7898a6d1b1c5bf928f986fa76fe55d1a741689f4e405dc9c9939f364c61e796ec713fb368b39b3480a68242506d94167d9a7cbf51c502118a49f8aa9ca3e3f8cc68dac5ee37d1b0c875287cf906ef9a2	\\x259d817afc654f4d0c053bc7cab9685ba53f40a2eda513ae051eae3d435978e676a5306da45090e35dbf7f0e631ea0656bf29c6a69669dec86844dbe2067b0c0	\\x00000001000000014529a3746e2c9df6182268a35af1d25babaf5b3940acb612fb45ddb6455cef1cb53a165dfbbf1004397db946758ac734ee27eaf051c127dc15fb84da5a32544b0f41e384597c087035d730f01747cbe629310a6800dd20f4a6a2f75f1a471673161318472accb9dcd782c3ce22f27650a601eaafe574d7af46d24df4357653a2	\\x0000000100010000
22	2	9	\\x8ce6888e1d6c2eb98d65ad0adf53f17c0e9250b3466212916c4d27c96eba5d1cf597d09066c477ca2a9acaae5a4f8667266ecd3d03245b661432ce5ea71a8907	220	\\x00000001000001004d85c9cd79e23a012b89c299c87169996805ecf45069c3917dbc0573462ff8e5e5f0068e7976a1792947e96c5b772c2d77fe452d4e7cb8afd312b10e66cd588a6a19e1bc3363a07a34c8997597eebab0385f5713f87d7c71cd711c32668e43c640979436bf1f592dec3e4e96ff03c076767c779c1f3ebcc31227c3ab834f38f1	\\xf5227058f3260cef3676e0443c455abb67ee9eb9a3de452f6f5d49c70a248cec8d656c38706c29add2e722cc6e85dc816ee1a0d3dab3214e784170ba243ed3d4	\\x0000000100000001cbd7196f283cee64760b8fce044e32905cf7b4be831b9c28f2ff4c7376734825e12ec24fe10a674a93ce54befad8f0511b15370597765f1c4695cf79fb8f1c92b2dfde7b6b4540a58ef16ce2d08cb88538a05d249e96c9943cbda5720a1bf4afb25a5d6b8414872bd018bb8c9237da2c7abeb3e5423accfe08fcb1dd6f378d11	\\x0000000100010000
23	2	10	\\x6609ebf9a8d3587e9c84037b247531ec61267e08193d509c992cb1ba8e8140d3ca06823836733773bbf91aa0981ca0318e5a3a710e2bb082572977bc0ea78200	220	\\x000000010000010024eebec145cf4b4b741effe6834e02503595c6de340e91cb6ea08e5b2bac21bd08c596513e2e9446956606ae66e4467a34342102be7994f6d167eadf248c48be16fc03778e195cd1fd69b4de6ff274d4fca140b605ede78da36c2b9c838596cd8d27a0f84f2a9d4e3d79f3bc9f29735cb82b4951af8c117eea522b060b022497	\\x889e056ef3c84ac1e4c13a888e1ea20ae9f03b4eea8f3913dd15e8b87fdb114ff9e189071b757b3e1e6770113e2113c7192423e3140105dde0d37108c9528565	\\x0000000100000001afd6c45031bf76a546220afb849369ac8b0e49504673e1d430fdd354550acf57cff77fbab68e63b508d53cdc108560cf5d16daa605cef51a8942529e486a2bc4a77ec76c70872de68cd302e0910cbb24446b1f040d8aa788af75b6a374a8fed112df6352995192459d5c2297f9bcfefd4e34ff93c7b94eecce0d021235771191	\\x0000000100010000
24	2	11	\\x5e4f23759f21b8894eee6ed6b4cd98436a868362f0daaea3a30896810c9a8ab0198879eb8c2c4e68361d2688698d41871ab1c4f681fe14c892e0fd6530dec004	220	\\x0000000100000100b4e75ec2cabb95742422e5db473443a4d520a8463526f5876012e3a982fc0951de2f84efb1f7bb514858b2cd68b85271d5fd35b6ee0c5cdb8ed5cd8ed152d66c3355d3e5650f790a981c0b9e51616101b3273d89175e9e29a61906a41d6fe44ce15a1d56301b8af118c04a38aa8a97146cdf4a16dc1d73a23ef8db998c319724	\\x888a0f73b16b940155518100528f4c461656d8897c68b4797d02bd032546023feef30ca67dbc7a663ea4a25529ea50b89c7617f53bcacbbdc840b12401e4e66d	\\x000000010000000172acb2e434e78a2cf5eeb48391df077bdddd12ae10819eb175f2db85dd37fe10f0da0945af6c6446d898a0cd26872f50c66b2fc1d5038a3ed90c7389c379f0ce3069834360888b099c6eead5ffae34c4b7a6ff0ec5be629afbab3f908d53ee7469714043d058faae3f03f6742a62718a9b2304910557fb18f0d168faff405b60	\\x0000000100010000
25	3	0	\\xf1a471f75d09ef4112ccdb3aabe51f694ed6a3daf0682032c3461db9fccce853fb394e87fc5034b41ad0d9b931b7c06d30be039341f1fee824ed4c9134ad7c08	421	\\x00000001000001001ebc710286ef316de466d89b435da21b41752178c8d5c1b5c6ec8e812e515f6bdc3e843bc69a34346fdecdee50b308e00ffa08b6ec8759389c9c47f27f3029e3cfe4b35acdd128cd0ac6916fb2d0876ed22c68d21b140c2733290cef81c647b703c4e24f52413dd26497c0f973ca3311fb6a043e44da25a9b6dc9530d4c2983b	\\x947b6bc80b6906098c1cee529fdbaf0115a7ebdf2e1d2247ddd9f091f773cfa815feda53f37ccd0b5f6b88f8c338d54e78acf222e3305613d557940d661c6d91	\\x0000000100000001707b192ed6c73ba987dfbbf7c8e3c3a6d91812d58ac70b3ffcd05f17dd84b34c09e9601ae570d05260c09913ef5d25c626485e6c0857289dd4f64395afb1cefdda39fe8d3ea0281d583f93c927605533397f75cf7965286933db4b2dd97fe783da64cedbd833c4f1353f46a11a38dc86e36acf80239a02ce2bb1640aad225af3	\\x0000000100010000
26	3	1	\\x00bf194abb86789f21b53b3b6367a522475404e783c35ff38d68eb9d3704a17b2dbfa34a9e62237ecd5b8e7c9f66ddee6a13231b3aea811a384675e62e816907	75	\\x0000000100000100a77bd0eedfba0a1b742a6b04a0d84247b12240d6013ea535e0fb3c295c1f7381e752ff58bb46d5552214cc4c2ed70616e7de2e75734c9f7e73419b86cf65a02ae432ab2067d608d4728184bcb7110177620aca38d26b87ac53ac604b7ac114890e43087e344cc909399701a848eb2ee4db7c8fa26bb7811e02efc885a0fdc19c	\\x384be3a60ace12174c56dc2ab5158b6924f624b2aa34573e31e7e881a478e08be55b39c876c086ef6c8982f577522d5a164e4109fca73751f1d56c01face0e84	\\x0000000100000001035932696ccdb5f7907d467836bca329e97fb4844cc42825c7f86c391ab94d70a2fb6631af61b9f3972f197ef1b419560c45537b4700fd4d7689fbbf6a5945c2a6b865a8375f1634064f3349512baf4417056d074f9c3d0e0e2f7fd041b87e913606dbc84aefebf4e6d143475e8b2b736290aafa018000541440dd0114d8b618	\\x0000000100010000
27	3	2	\\x787a2080fffaa1df139c1ec9dcc09a55e7ba76354da4557ae92d0162cfb1ba48765f18afff6f1f8d1aaaee3a6611dd6cb61ea493f30b052f0caccad91e6f4d00	75	\\x00000001000001000ff92f38d85079b019e80778896c7d27b3b641662fa2d083514c3a6c27fbd71ddd81c4e9a0a3c5e660ef0b4029557b227b9f84389b379fdaf990493048e547c9dbfcb70e95a7f794c25241a5e80d9f6c9532cecc8d3d8746a66bc4b2a04a6fbea649a7dc1c1c9c98a2214c831af26579575f5c01f62789f482d5117bc16f2f9a	\\x83850bf07c54535a40be40c3b49812db578173ddaa729b80e7e64ac184e5385c5b8bb15083bf0f5fe3e91643380ffdd0b7ca23199f0da9e8b59ce5f21e6d7648	\\x000000010000000184ba812071f34117d4b08e4d1b6f9d290b235dcd4aab78454f2cee17699a1a0f9255250ad7b54ae986b2cb9c8091c1dc9c08b86103d515da2161b1748873c8e0b183264470f037ee70dc00b27da93ac30271c7f856a6b43e8b590f1185df4c46feb733d5cd3ffdf2c6ca6686ec846dbb5ed7d71858ed35fb7fe8e4fbfbcda852	\\x0000000100010000
28	3	3	\\xf5ff1e246883b3fd756f5a2ee486cf6dcddd2fcd4269bf679dcc393698aae4aa45cbf5fa47c87b1e89f20474fc1666b125e6f929cbdc30600dce5253bcbe6f0b	75	\\x00000001000001009341b0966f1daccfb85b4f05ea34266f38afc43f405722ceef98739a61be3fa3089d6acfdd6964a89c083187613f9d76c8dad3265d7492c081c0f4fda6fad904889c4f764d7c916795ef5de719d57ce5d0ebb30be7456a86f54fd570c1ca81030f330f45158b77d59a5806ac6a3d76eec61387ec7385242ef35a8bbaabd904a2	\\x3eb8d944e0eeca3bdddfec17e6c31080752366fc776c675d3894543b81844d047b4f327db47157b6a902b4b1427c4c94aeed899e9163381e3fb52625a3fc16be	\\x00000001000000013ff0f3666309da2dce051419b99806d7957f163e8cbb0f96fd8e4c339929f7d5f3ad213475a9e54521a908e974d729652e50ee553e36d2f15b1db16ac0b8dddd57f619c7c22eba0a9e4b32d3accb7cb7c61f368d6e53c78962de23c1dadf302ed67664a627bc92c919570333744c597fa0e3f406b5735672878e56cef15eed60	\\x0000000100010000
29	3	4	\\x06f9978ee2c338dadd12a9a3cef1c219567c78ac56c2fe6e37adccfbaf3678ffabeb5aefd40a43f16e35bcd7d6fe324e149f8cb685d47cde7223ba841e79e301	75	\\x00000001000001001271e20a0290b8dc17764656e34d0175fe5b89c940311d15cc7818fd5a1fa6cc32812f2d1268f48f4ab8efa4aa967a99c33052ec25346b871670a3486aebe40af8774b2cca868cdba5a87f3b163dba5f0dd16f75ae4b5a4fd6cadc61a913c74a6f8d99d3202a838aaa915cd80024d7af4ce93cc7ba151d0715840085f536b8f3	\\x8a31b2a8c877748aeb21555f8b6ed2871418c3caf03a8774ccf53c7132a3362dc793a39a8608442c367ea2cfca9dc992028f392f2da82f2f5578e670730c0f4f	\\x0000000100000001a9fbbf86465707e4d34ec2097ac2268fcad29a2d6fc5e849da46b38cfe172dba6b70601c64c5579e1a9b47173d720f3c5e1a362a567e8bbf728ec9bfd191d555043a66a0eee0b0ffd8575537101039f7260e3827b0d3b4406c8cd776d79565537a749ae422b78e4cc49febf9d13a53583758929bf5e37030236469dd1bfb43b4	\\x0000000100010000
30	3	5	\\xecbd800cdba19bc46b6a92c79cc4eb50efe5bafc3c0abb801f5a2c3ab8877b81770e73985a52abd5594392a23f54d6b703f36498624d49ec9f976b257bef9c06	75	\\x0000000100000100adc28fef9de81f4bfed6ce9247e4ebd75d328cde68f0d9ee2595129c0c39a2944774b82b6a4373cff3c5bfe47015fb817931d7f77b138dc80f40eff809ecc3b91e71c6b5c6084b6b8ca288fa0799ad540d6e5dba2d701c5349c5f850dc175f257b4a3750e4ea9155e542b2ed33f8ff3dfdbace159b729439c506a93290f9f59b	\\x3bdf3679f18d9604834a08da0ff3dd1e435ad8d65910a172330c98d3d802cf97c1019e3da4b0b88f95c8010ac708a2755271a04db644e3530f73fddb0e26babd	\\x00000001000000014f9aacf5d885181f897ad02767f1a5208ba5b067902224eaa073ad3a2879193db810b015a3f792d2388697601d7d02c299db088ad5968e3856b253f0240ba147d8865faf0441b1a10470a13b1660e68d0794408ac1a50df8a909c1291eb4eb349a721fb929c2fc8f6a1601f7676dd8b9eff41e878b5611624803b9ec354cf1ba	\\x0000000100010000
31	3	6	\\x039337ff22008f1b0c7279c0787ad0d129d02410f15ea2bc8d15febad5fda19679fd136d8455c1242d60e716d8950400fb95d281b33c142308ff8f0d23872508	75	\\x000000010000010090870ee8e2352813bdbfc8cfe1fb92f8b5cdc6e35e5c9335ace44178d89108139ee46f1bc32b97ecd2d2b18024ad83683f54abdf82795f70ff8def5c493fc25891cb53facb2abc7eb95e23648e8a33192f5d1ced2507e275c44d5855e6d29e9892f10fc9ea726cc13e9f0be5e3cedecf369c5d840ef9a1656823491cc52dce41	\\xd1c97050c49e1ccf9857fbfe39058a6bb8a3cb37ad3ffbd63a46ea372afc0c1fbd512758c7ce5d50d8d08e0109da83146aaa89857f111d7acce164b979a14a7e	\\x0000000100000001a5adae99ae44e158cfe9fa8d5acd731a996b6bd020d2e8f79fbaa3cbbcf4fda22dfe125cc399d831e3fbd685c2e4a9f57248672ba9f209c9184cf927bfb99fa094fc2992e8bbd1b43d21878e645e99362ef947ae5a462b83a2a8d67b3dd25e0b7ffb4a16eee8a04d6c8131f2452cd0332be34fbf9f405311a9aa8dd603ee6c13	\\x0000000100010000
32	3	7	\\x32a85f30c3549864ff7acfa933f38b296d7635beb62f6ef633e7a9632c5005835f9f7d6f800ac2672247910906ec49f361db421a84c359fb96db4706b284c40c	75	\\x00000001000001005075733586029c857c11d3886efefeb3c5b88f6ebe5507d76ff284342ee41377973179f4d87ec741258a606a8693d0169d3867f6579c213e490f9626c2e9d50ef3bb28012c599b01d1dd748fcf3a0491f19355949b15dcebedfadaa28ce000da47cb249faaad003f50d46d1837aee8bb134553d9816febfecab86b133b9fa22c	\\xea58e355d060b9f6b1d458afc50fe3f83b7e4ae1d005bcd0d2e8464db33a48c72af48d22bee77a3cd86786e3315318aac37ec4934f59cd4d24c61a47430603db	\\x000000010000000174609c562d675fbad6ca75b4d718b444ebc88f33a20d9193d5d06d476b50cd831cce261a29b2c3e6cf671e0cce4fe16eb394318665db2ae81b1c7c7404126c13f39db2708762f0c846cd9d1434f2d87a4757434e4c155d74a5449c95184b0bfbc341baaa68339a274a2bb3ca602b094c8b13ebd01ea6e5659f65ab2b2b0e500a	\\x0000000100010000
33	3	8	\\x036d43c1b5f808b4db5e4a5c3f91dabba1b7959b82c7a9edced38978ca8fc39d30bfad2eb4134d99b5f00c81c131d56f45c9846db3b37fa3a8163820c3a2b603	75	\\x00000001000001002b2e7a0aecd9331a90bd3d31f0808a337e538b7b3b0ece58cd57745580a6973a2e9636de8f282ba160c8fbf842b12454fef2f9a8d2049e8ccd26c418bfffea1955e35a27a5ecec0b548fa6ccd077d48cf50929e148de7715025471c681813016aa125bcf92444999d5bd76b269e5f7d9c974d37d70bba322a698029fdcf0a944	\\xae00eeceb88c40f5c6824dce8624df16a5a1ff00703493033aa4fcecc64d1ef09cbd8186b430cbdd07cf1c15a438832616bcf1354b5d17fe5d1e63525e7fd0cf	\\x00000001000000012f4f58d3596ef493cdde1aa88551fe47b4656f3cbe5468d116f5c1856bad766657bf522c73ded72cf430dfd8ada67a26ae047d4d0374fcf9d9d1ed6d478d2c751d79f2e4b6d639726489ff6fbb0a24dbb06957d8fee07f546429f3d1ccf31be84e8a2d2085455b53a2f1ea13ff8833df747e20bab14349e4d3fb9851deaf13e0	\\x0000000100010000
34	3	9	\\x22f2f2cda0e6d9fe26cbd54b05257b64fc786ba1b57b25b730c3ed57aa10e57686ae949d03fba92a8b03e1deaca07167db25c247d5eea75cd4285a32b40b1705	220	\\x0000000100000100bcbb3c7af838670c6af9486e52a4c2b7475795dd8711c2de8fea2cf00876ed5eed6a39bd704da0addac8d8ec19b287c3ebf696da331ae12e7f139efe3b950c87311eacb4724937f81f74da9d1250b7639a20b048a81310afde83b1fa9907f48fdc86ca54406c493ee2ae428ef44ef838e5eeb91d0bcb27ffa68c1d786f3748a8	\\x4ec3f6705b586b670c48dd80a7f84cbf42f66f8b8b66139409efd132ed63d51ff8aa35c360b5465bbbcc9a77d17d2070ddd6c14562f6473d47555622412fd228	\\x000000010000000186ff2abb97e189e78f09fe6b397ba1cfd4717043630b3665ab3bdb61e87d60d55294f52127c5e03f1856c84fd143584c8e0b99b54158167c19d442427acb9a7883f6d3be0c827e299a174be4d1b6d77f34958b5fc8f0151dba86401bfcbd7797792f0a65dcc5d0db65d922b4c5b5648d74276efad3a890cd4e67d650da29e32a	\\x0000000100010000
35	3	10	\\xd47f32316567b9c403df292983c36c106327e98f8b775e2176c102e04375321745c6deaa13e4bfffbbc83e02c1e931e002dffb9309dc5c30b8c660bd654cd909	220	\\x000000010000010056c71effb4fca5ecf6e910d3cf11bbdb4e06a5deffa200d2a7514fdcb904371fb08da33d54f7b89e44216e761ce613b6b6d95ecc483764735f7f6e5c55410c613431dc2e5f48396c3e7aef483cb2b665a6800254e1c0366fbe80dbf4e7ff0fc030e1aaadbe129890eef1da7ce4e290090dc306b39424a2518036385e1fc88c82	\\x44ad4eaba838d308cd091973f64e4751013b97f3b2c55630076ca95203f7b584ec3d0ae880a77e8e639bbd6e029dd578885c25ff3ac0ee233b1cfa6b6d4a2327	\\x00000001000000013d563c3a387ccd67be3342e348b3e98cccd9d0ac60567e93b70625379a94527dea2c02fc6f60e606af5ab91514f95ee38905df82d3b4926435e9bd70956e9bb1b41a8665cc8273dae474b23558f57846a44378cec26ec99e16096b347c2ccbd5a7223af98e67f8720a9322a0960fea3c49855924b0a098c3954ad08199a76de7	\\x0000000100010000
36	3	11	\\xcb92c872d04bd8e95dd305a7ffe2346de4a5cda265d336be91dfb4dabb8827b927b05dce20827f372e6b94663d8b81c8e4e99c4c97cc8d34b390d45d4c636a0c	220	\\x000000010000010053b3ce8819247affabf8411f198259c2a6300ea52594cbb267d5d775c636f2b1e74da24db1871518b9cb39e25602b9bc8b1822dc87dd29edace15afc98290a65e94e264143e6b3698c34df0895579e9093bf507af52b7434224013869cdf5f03e16434709dfee052085550231eaf6d9d0970dacf24ef53e3908de2429a298893	\\xb086e2aeb3cb1b619181106d6c552da23cb8de7041b9d081003973e395619723474b52f31a5a14af302cee7144a4eade48249e45ce0a8200486c98dd3e3eb5d5	\\x0000000100000001321dda0259aaa8396624ce63edc0e1b0092e6681b8a26a03596612965f9bd8de58a0b61f78803a07cd8a180cf6a19751fa4764da037c6c5128d881ec9e772a9ed3c0c386e0f7a93307411426e4e4069c2fea8b98f785763b954ec3b9392b2d45f5c7d934661306a995565ad0d7ae1f08472414dc5651d968b9483533761f79a1	\\x0000000100010000
37	4	0	\\x229a74841a3d85f23117eaa6ff94f61e4e27f2bb23a8d043f9119c214f03815e3bf12081b850ebab65ddd6d32134525dfc51fef6457cb34bc56003a7eeccf30b	51	\\x00000001000001002e7e5c0a1ad568051fa18d42cf460697f6a349ced93bb533f3920454982499c318568215072dfe93edff70bc68ab2cbc73d83f1f84650deef82ab8172192ce2ccaefe3c2a3eb597d04d4e987d6c334240c28509aa1e6908b836c75288f5923b9f1212e7b5c07ddbaa78dd0f146b90b4850046323e45cb558ed5e5e52ae2f3447	\\xfe580e540b4ce988940a3190b78d95dd42d27e10f4c1d3d6673467aad7df165f112de83c5dd858576d65ca017e1aaf96e1bb1962eb02c15b9f40d521711cd337	\\x0000000100000001a2ed32d597ab2a3d2fd3c8b98aad96ed9527319c37fda65d645b365b8d72f68e1d584e4073b7fe489b051fd0b283030074a8d35dffb849a811ce18fa1361452b25a79c163f524505e62af9cd2668619659e0158ad5f014cde0c7b500aaa0886ab92bc851e6ff48b55f1708fe43550685c1b1128c340069e4bc0ed84fc47dfb1e	\\x0000000100010000
38	4	1	\\xd998cc6fc16dcc835cb58bc3787120f99938f981867099b3b75e2a0e86f9a5d9536a28639b88a22a2fe4f2f6547e31805a81188df6b6d0a1c374efc7b5daf707	75	\\x0000000100000100751fd3f392382fb9e8a77ed515380c266d24717d28ef301d4dd90845e8b56bf82a374e42b2c612554da65c520fcde32b3321f3e3c0400ff41823be3dca6d75fa43b05dfc4f0d5c86e2473868690bdcac5ebca1eba3e384e434ee6c16d0ec90fc2da806c9f77997c0b594125e84496a816c48bf440743f8758d2d51f7c23ce669	\\x7a49579fa1fcd426bd1e4aad140f2040fed699f3b5d9c7a3e18b23547d00221c40e07e8b4ff6df9742e3d985ed2810c703b027efcca16740d78927c2d5b7fa90	\\x00000001000000015dbd6dbc6ddbd819e6210914e3d68a17c405e99539a99dd14f18a21a9314560fa8d83f5f119a36452cdfcd494f59b7976546535784649f6f642733bf39c8396331c49e106b2aaf9aa24ac523e3dceac96c076107f7ab1d427507bc5f58e3426908673ff215e0e9d485622befe95a7c5459bb205a01bbdfdf9541cce6ee527b5b	\\x0000000100010000
39	4	2	\\x9c79043eea98c1ae47491af69fb809a0187868d30db84e2d50262bc9202d890c06d3863785a603c5120f3a88ed18ed99bc535246b6d86066fec83d7e4dd98800	75	\\x00000001000001001fec2560888e073e1335f907713abf195f9d3be245dcf7715d2c582007dfca8f58b44f5b0d89aac400f3158ff373457205beefda6feebfa1affd2b4e60c927f218ccae0c98e1e813add9bc75118a3392d47e4a75994585a789781b41539e6689a58a9216d00b7d94b21c5daaddd841575c8d6926234f8d799e58100a655b571f	\\x6b51e4f8049c4a972de15ed6462b079de96348b64dd4b43d0fe987bd4f5d6be15a80381a348afe9a9184c6756be020acf071f13545dc96d06c3f5f5b8a37fbe4	\\x000000010000000188b7ab5cd71cabcfee72c94aa50283cb7def02509a74cc7a19612f625becdfe485c8cfc52e90523705959ec3a6ef26c23c615d11a5d3d07012db32894701c3a96088870bf848517088cc4d57bd2c02f62f6a64efecafe11ae971088213c53cec049ef7c7db19f70ade5880dc22112bb8d9b2c7e84cf3918a7eda0e26a6bd1874	\\x0000000100010000
40	4	3	\\xc4f5ca7da5a054e7ee9aa30a27d0d1be058a23f773d299b1cdaea9ec72371cd49679330463140811b520a77aa943108e7699aa35cdc603f170d1611e325e0507	75	\\x00000001000001000ee5e26e2b68162b34c5bfb2c7ff9085b00aeb870ed7ba6700f54fbd8085db93fe1e145ac6d4b6f52533e75bb63ac7352be438fe7a7bab6a0c9ac31bca847153c2f76ca24589fefac3c5d81ea57b0168febf99c9d2ee5adf859d159e62d229050b284578fd6367d932e31a573fc263162d5a3ca85604ee53326fef607e52cd31	\\x957a9da519b2aeec4e0b41a007485d1515679fa59b585be949d16898d67004b87655a76d8e43796a2e80dded41691baf74ccc205976558d54f9829f85820ec2c	\\x0000000100000001a3f59ec585bb962517ac14638bc53f8611c2ffa086d9018cc761d59938505309aeda2d9f63083793f77a7b2261f887780c72b258a8a95947da50b3a90c780b4c3cc8a4b668193b8d7ab4e74e28ab354026dba06063ce00917c3dc8d074ee7a01457c2288f9bb76fbf695c66c2856e0eb667d52e694a2586c8ddfb54b911d344b	\\x0000000100010000
41	4	4	\\x940b4919347b74cab60e20009c449d4e9f1ce178756730c7c82b953a751f032edcdb29fe3d21a98e73a8f658fa7742952bce3f37bed1f91d23c7c3c69bfa9b02	75	\\x000000010000010094da22e5bf5318647fc700d27dc2340b300352352bb716504e4629c6a31bc5013db3eda8621f1ebafe2358d8422775539671e2d228359cb23729c3f5599af19b4830c50f4226ae47bef7bee8d30b5bba1b8fc4808d991aea239f8b067bd4852a28d2512e83152c7eb742e6076071465e5fc34af302254237874cd01a89829df1	\\x78ad90a8e1c69d951687c000d1fcdb75817353f951a30ed91b516b566a1c8ba15623266acc414663daae2c3c4c6485acdf5074cf5cf29a4a7c28c585663f1a73	\\x000000010000000125526b0dc0ca2922200ebff23331f04894f6c259197f720d5377483ee9e0ab6ef1cd51e3434d3844250eaf333c26920906dcc1b4aa6443ab0e1ac83f89382cccee4b04499c760b313ed49b5ba233a51edb63e1a1d79286ae993047bd046ac2e43407a28117858d9c187d1e6927e7672c1e62277db78e8dd4f28e0115ef161601	\\x0000000100010000
42	4	5	\\x701e64a6d5cbb97e4e0db012be7d51acb9545e5a448982ac54f813cf3383e00f18c49048393fd4924388d3ae3538f9ffb674782aa425defac0c8cd20956f070d	75	\\x00000001000001004f5c50e2e4d56a6922c69c545879ae7f965d210f3a657e6951eee35a2d192d8e0fe08c146d2715b72d3d7fa97a90d1dc3e57db2069b96358512bf3fc1915df0177517f9c8e642e6f8ac953a4a8a3cc0871d7862e4c8e9be9c3f8034f40723bf2b7fd97e79e109952415220b17804e92a942d02efc57cffedae7c3345d7514ed5	\\x8488ad45e20799c7a41085910c9c377a1cecfcfe52a1ff988c087994ec3dfe0ed5742e8bf031e4a2195890bca270d348059a599f23ee62c858df8789b8cf1e8a	\\x000000010000000124cdbfd6079adbec34075bb453e484bf75036f06f96867ea1b55ef76fc64fae7379b91020d339650e584b9281fdbddfaa74afa02faa7355797cf1006e795ffe9769a586931fb6eb4d3c7d0cd8949e7f3e14972390cb990d5eacda2b6871de0de09f817fa396db0e1a5897532a6d375603c1e120efe9c9e0a11b39d38bb0da9ee	\\x0000000100010000
43	4	6	\\xc9b258737546dad0a24ce48a18a592521a33ef4ac257975490a1852288a53de245817ffc8576ba747ee2c4456c6fd02954159c8706a80de2db58c8e79cbf120b	75	\\x00000001000001008c19256e8359b0c78359d8df8b07f9e6dec593b8c694156d45624e6c71747c893f8051ac94ba4282c8a2983278a5608100550de9c691ac7f32fa91020a398080122deec16ba9cdbcea68c86474bd2ce8eade87c84421886a54db9f4ec1295712c01b25364fcce62c8fc0c077a1681dafa4e532602df2e69331cccc50f4566329	\\x74003a00bc45223651ffd3f4f0d30481ec05c19bfa8818912705a36732044949952634a9de043cf06d315cca1d5b6913ba8f094f36e0c34b7a58696c8b4a0d20	\\x00000001000000015418a8e109e8f31921004fbb459616c644e0c6811133ea6f5c4002129a51b410b032b358976e6722dc8b04f5b715c9bbb3b4580e51ef1ae404a83518207792fda2b33d5dd072d4f13d4d484bfd04410d848d5b776362e42f31e27fa62c8ef9aaa09eb224646fce409c330f993f9c2a3d76abb15e22d301d620565b24bbbcbec3	\\x0000000100010000
44	4	7	\\x912dbc8f9caa668baee5c832d65ee522eac10ea75299d145862c4c4c7b9d17cab1fbb0d2af781b200849f6e4daca05ca2683bbfe242770e2fb234e1743afef0e	75	\\x00000001000001004ec61d6cef963c9ce106d3a8798a922d1ec9c30637546ea455e4b83b310cd5064d825c25865322ffc6aa7d3d7ed91cb92a0fb2f33d713e0857a0e453748a219f026de35f174f39c2691abfa908613ad9a9ca451344c47aa571e0eae498986228cfc6eaf308e410d01d2cfe45f96bbb032651e2b077ddb4503ba866c6a63a4f64	\\x30ce1241d44f713d7e283760dac70cc299e9a5ff58152e8182d81daf1933517b1870394baa001e2610c63a13b491db101ff7b82c77d18f387458a3d477a02797	\\x000000010000000115c8dfbe504e64aa41b9097b00c32c8b3e8f9e9c99cb6425373f6079eee445ceecb2af62843a8e2ac29e5805d3998ea9788b48720f813b708ceac3b5e62fd883846afb1c190715d905c10130c88fb1eb30543ad75d1ba2f75dee7286a196dbfdf193f0ffcb7e6d307944c91dd7d73d19e44b5af9089d3bb4bd2c40ab31733840	\\x0000000100010000
45	4	8	\\x140cf9549101e069ef1fb219d3fdfbd57b2c3b8d400ee7ca4a2dd8219fc2422a49b3ae661b6e6af248e4b93114afc63b21264a3d2c0b0fbad15b89fa6bcb2c05	75	\\x00000001000001009be98879c5bd8b1ec0697f2315ddadc44827ab4d346a326d24bcbc03b5ded41e4b6087cc0cfd57e031aae4e780bbdc17745ff2eaecf1e1cd3f47fbb6487f5833301d846e5159864349b0620b8ad94f90f45914484a225af946dca6ab13464c28bc21fe7261beb2908c44cfd69f3b3a1ec9d371b20cd2d57a44cd70594a388536	\\x14ebf8842bbad7a81cafcffdd12bffa503940667cad2913aa0520e6179309012b2b91b75c5fa098e55ffeebcd2949859ac7b01d11947780f93c37eb109b25f4c	\\x00000001000000011d6a063e78357ceda9f553059cdb45faac265df881bc3491a14a3ddf904125e78fabf06d0b59d9e5b89e749225f58dc8a85d9eea191dfe7d0f891bfd691cec04a7ae5d91680e23a2b788f294c71925729464fa1c2b63f41ba1233014210c24698134a5d71122f4bad238c295e00b7a5626f2551dd3b6262aacfbc4c079156de9	\\x0000000100010000
46	4	9	\\x611a47851ecd1578377acaa2d989b44ef6ca5a45373c695e1aa1777a7914838ddaa97cd62b01105e6f0c4f955f35577397b69f69ea90c318180cc10329629d0f	220	\\x000000010000010034deb9b3efea61b60a1bb7d15d5b5dff8b472fe320dcb79062aad8d49e4c9660c141c70558f8fbc4a7be2e60abe74df88c8178d0da21b50557a858e44f08d394c3369ebf15a4515a5edcc5f34c0ad957e1a20b4abbe27ccd498691ec5077b8ab569ee3030034e5414bd06535ba263dc94b3166b429516d104b1bf782936002ed	\\x9c40ea39a08a3adce715380e59289d1ec5bcef8ba19381e7035e027fa6ef1ab600d8a9b3f0f34c57bf307dcf4e9430385a1c0c595b20bcf5a01d8d350a4879de	\\x000000010000000137ef872ef8c8be0f1a707297685e47f21342746578c2da751b39717981054687bc64b718d1616d294ea8c9217ca2ea31722e42940063aa2615110ea952e2d812ad9d72825488e637db48f608db9ff20d9c37b55d192cb4374a573af1589c582c11a24e4d361cc48ff5883d32ecd1759998d52dbf4b477ba547e58ef2e545c6d1	\\x0000000100010000
47	4	10	\\x48b8ceadfaaba8deed1158a03dc3fadece4d0230ddb040f460c210b04ab704839562583e3535358072d6017e33d31d7fcd05d64b4520c8d8b8d86e7c2377fa09	220	\\x0000000100000100902cc05917a4049554e2a84467d4dfa2a6731941c0584d8ef50c544b793f2628ca7de725f311a749854017c4fdaacd892caac9c46b04e4ad5cc9d2cf535d9fb3cdeb2912ca15c4c8f53c14a15cc2fad65c6f199816624679870c77760df74d9476126595835515df3459ac58acb39348571386077cc362c08a1652f7ca569895	\\x8acce67891be2a2062e5c8dbccefaf22cb969ab74dcee80f1685ad7c7caeaabeba562a1323666e96e54374cd024906c904f66c5525c31622a7f6ed777683fc72	\\x000000010000000163f84533a0a92922c7be792ed2b937ce90ccc5865ce5395ba8030f65681dc3bfb39b8c46e18e06e938be47aad81b7eb1fc7d44c7c152d188b0c3e0c91e394bd2f1839cfb48b525b4c9b4938b5cdb5cfc99c7259b288bd5d1615a13b3df26a375b3584d2708c73dd66edb80caeeb641c669dcc32fa528c11762d39a80eb0448f9	\\x0000000100010000
48	4	11	\\xb3cb4b2341dc415c0749843e9283b2a03281440c9df58dcb97b23ca0301d60a384436539aa32a8978e7ea457ba08dcb48f294cccb2332f99251c38b435f26f04	220	\\x00000001000001001c8416d4e41f44c12b7ef31e10088b39022a5eba7b09b04695b3fc68c904964141d28bd47b4c92da3d00adca5d2bdedc7b48d7cc33e244a8e95bbb02b55fa056c2ac99c0376983dd5db34a051bcd05b64fd0e7a38beb0a0cd8e905f442d2628dbe39355223b6b50a6951c5eaff736642c428e6aa1e9e4e43d6662d5e19e09124	\\x8eeef9b4febc80ba9f6101e1bcf555b64ee6395f0ab8ed4d421e7462e26a13df176caef932aabc16c81df2e71ee16d63c13f72c193ae9f490063b5a501ccd629	\\x00000001000000010cc0f62d438e6fbf5eaaa52f0dfed793ddda7effd603ddc602134412ec7592613d0ed3aee679249b175abe5540c5d172547f7fbf07059402d1b5770f9a07f8b17b6c7222d5f15a35f5596ec915df0b7017378444901f42910c1eb067aad8e741665d89481a80cf78ec2c0cc45be12f401ea6b97b1ce3b4a8dbb65e378d853463	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xfccc7288e61d7a0eb197c977e3046777d5bfe464f989790bb5e3cf014d439c39	\\x4b2d799e71cde20c8e6ff65a54e5d1510f7ca0a014c4afa5b19559154155121b6c24b1300d85d345cbd8aa3ead925ee798f25f12a1a2699842774cdc7fdd6bdb
2	2	\\xc081d692e86fac98f1a3257f9f48fedfd277fccc6e4abea0f5e05337a697b43a	\\xf6a58fba771ac39ea9d4519b87c40a3226b09647398894afc0e20b15cdd1b9806cf40e857c8de993e5e26b4be6a3d94def2d5d462d2ecce1f571490eb01e4914
3	3	\\x76adcb55792f9110b59165cc8653a5114dbe5c25157f4b10d40103232d314e0b	\\xa53ed0679428e1e9819ff56780bf916c51cd3f324f44ebfe5f894429f88ba8755d5209bac4406c5f59a15e699ec5cecafdd5a24411fe8319ff36ff0b07835701
4	4	\\xdb3824590a724f3a6fb61a15e91ad7c1a5783016df20b23c847f5b2cfe2b4a4a	\\x77ef71c5d2b743e1222195802349be23905936cc8ea42aea4b08ba6575731ac955b1031e005ae4e4c2f5198ba0d65378b5e613c1d346e00b960c1e064c56478b
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	2	\\xbeeda6192c10cceac1089f9c0ad429e4d56121be93c7b76574aed7b443eb56c2d03839c3045ff2dbf7f7bf567c075b62049197993250eed5689ff3c33c34890a	1	6	0
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
1	\\xea56694a6dcff4d49408aafc76762f793bed2bca849852faea7d7f2f8269535c	0	1000000	1649945304000000	1868278107000000
2	\\xd33f0e740026911cd58d1e6c39b5f7dc4103ba4b95c4971413dc7348b41a2b1d	0	1000000	1649945312000000	1868278114000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xea56694a6dcff4d49408aafc76762f793bed2bca849852faea7d7f2f8269535c	2	10	0	\\x1125e481912bbcb6e98eafe94f6a0d338508a72294fd9847edb1084b298b658f	exchange-account-1	1647526104000000
2	\\xd33f0e740026911cd58d1e6c39b5f7dc4103ba4b95c4971413dc7348b41a2b1d	4	18	0	\\x4026c0373a59ba5f21c6ef17c5716f60c3e47f0c4bc2c181d35a1b1f5c11eca2	exchange-account-1	1647526112000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x38bfdb05ead6d00a5c275136e56ff0ad4d9353e44de18ca23b75bff80fdb30fa0fd7a8ba7888f327e982cbb881a3e10fcdd07a9f789c16b4b80821fdd00db465
1	\\x2e5cec710fe3a06b6cce4d0220a49e2354175c9c3518928b6f66816df8cb07541bc98ba74ccaade2006864a911ef2375cefa601f93815eebda4ce60f627d356c
1	\\x254bbb24b5dd2df125929ca11bf58e8423cd9836f5cc46c4bb765e2e4ce07ebbb36e72af55e1b621573452386c49f4a02f5e52a33afa84b283931434d8259cf3
1	\\xb2f71c39334b9bbd7bd2ea01644e269c75c36666f2f82b3815ab17910a12d80002521c301a13ad1b21b8b4b34589d1e1dff475c071a03f24438a4aa6f16cb6b4
1	\\x667e98a22b8698c94407c953f93c819b48b989f13cd3fa993ac6d81e66526dea6e2315dcb9ed822452580ee045ff604e40c1d0c514d8b74ea6248904ce687142
1	\\x8deeda8c8af2a365764da16a02983f2c6537ae2fbe0398ba18364dc82f68f4fe0fa52481d6ba2ade709a02b5b96d2b48324369b2a2652e4fdb4ebedbfa2493cf
1	\\x14937348a11723de17fa9399aea619bde457b554e0ed5e15ff8f6957759b1c4ce890be265094d3ec4b0223403daf3bb1af0547b21ad37e95366d4ae5895b4873
1	\\x38559a8a5e04981ad24294baab617fd79204749a7cd2043d0ae0434903e8ea503618e8aa8112e880693680f6008a3aa046159957565318c33b813a79e7bc381d
1	\\xc62940941dfe142a2ae714c8b97ac9ddfd0eaf79c47f091793b0c86fc54c7aab22cdded266b4e4545e3411bdefe3ba3cbdc8ca1fb4eccb8c854bf76981a5efde
1	\\x8c54fd75b65c97cdb8cddc9950fc9684b5486aa7b5c1c295720e60a84392a39a2e0e16f40c298b83e64bf3feb6191040f28681584fb367c1a84c26ecd4a8e10a
1	\\x0ee7b02e272518981896daf546e677f4b9db705b1a42513afdf4f9e8c34bdd368873341bdcc70fdc333222fd01e5b3c4961ce0ddd08623e521adbed086f3a578
1	\\x281f041145ddce81af9ca8d3030995f8030a7745e67ab0591530e96a161a4a0f2776c844442a133aaefa1ae7ff2edc76370baffac372aa1aeade0d2e84e4007f
2	\\x2d7afb38797e74883dd150503cc238bc55e73dfedc9744c78750b8c7c1dc86d5e19a83dd2a15a9c9a6f2908e51ac57848a8865a43f0fccaab473c28cac918047
2	\\x16f390489e74f11cf0ee86aa1e1eb80799aa72cf000cb9b6dc6e967922406a29e62e6d3b973449d39abcbe674232e63a34e501b54ff1cd4380c803939c151057
2	\\xd4f176b63335b8403fb09dfb3d33ca41445f6c3f5fb9fa380df90684271dc22ec5ac21e0f119df9eb6e894f2fdbe359c171e880cc8e06b9d621a13c9d0ab6101
2	\\x4d3e17d356571590bc4444b1bb13ed1a899c14dc1f5189f9e9cfdc3b1fcf09989b9380d68d1f8af1c0f5741f5ab22944981f98d63b91525c799416d3854ed484
2	\\x07f43ccdc3da9cdfb3b38636581b88dc82bf479b8ab61990b663ae2af32434edc0ffa0e689e77e02e9f1c0b18ccdc27182440bf3747b142601cd610ef3a59cc2
2	\\x708808f15c331a956cf552aa86e5370a2dc7919d8e197de2be7096b639a2a0e651079f671ba14103bc8f58cece9b68d892233226a83506d32ef6e042849b8296
2	\\x9e9ae9f5a4cd737cc5c356b0db0eba50282e895169f2e700b00818d99af214d4c4eb1d7c569d20a070d68710a1f9b2746ff2eff635ee65e9af8959927edcc6ae
2	\\xadc6c49e5673cfdaceca18389ae720981eac406cc2641736ac42ffa2f05923be4a1be3520d45a8385ea2553e6b9db9f58a06b50977bb68a1e82e28833c2e76f4
2	\\x36b5b19bd7e2b4dbbfb57f5bcced78b7887d361d65af8dcffa49b93b3bf504c9cb2d05eb60f3f57d308ad4e0cf40b5edfe66fb31670cf011c5625b2c9a28625a
2	\\x9f789754144a86424255eb142f58ccd9380887562bbf29c273ef98348d8abc4e96c31cc87b04aec22736d807ecc8d26dca172f81cb769fbe79695605ed36d257
2	\\x391ebe3efb98796ecee0d86ab9bef262da9b08e2d5abebdd446f8772e6bba6337629d18c65848de29bec34ad9a9086697ddf2d2097af9a144911b6b2038f066a
2	\\x1768a0e3c5a0e6700c7b89a827188379c8fb893f6a1389300f9de168b984211c595dcfcc89015e697bce061696004f04e135e1b4808ddd71faf573dcc82a7eb3
2	\\xd3cd8c588be5e7c15a8ebd4c5d1328a87a8c7daada6dbe0af98f224c71e5d0af7993d80beaa75951095d5d2415cb6864ffc1b4ed574a578c2bc5728820a465bd
2	\\x8b52b5d65d428220a0daac579f77b9086d55dd539bd1b454834f7237c132c253cbd1a996513bf72de6a6e281e43f39cce675257a86b71dfae5dbdbab152d0ccf
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x38bfdb05ead6d00a5c275136e56ff0ad4d9353e44de18ca23b75bff80fdb30fa0fd7a8ba7888f327e982cbb881a3e10fcdd07a9f789c16b4b80821fdd00db465	342	\\x00000001000000018e0c08349b8c51b2bb8d3334a4e0a10eb38f52b7a9e5b41d18b8760770cc9a826c0e439586ed3b9b3bf25b5f233f89a25608d842c02442dc0935253d50108ec7beb04a0c576e84d981110338b360696bb3189927a738b881534aa1e41db943db4e1bc535dca12a3f4e38b3a81e6e8416c686b4e1271073f0db3155f90f0bec11	1	\\x6c3f4ea1de356a233f4df1c2afc17e4218820ee8ab20075bb56ee2016f17c1027339b6dffd83c89ac953043f0d15dfdd414ade86358211c7f71c6ca7caaf7f0b	1647526107000000	8	5000000
2	\\x2e5cec710fe3a06b6cce4d0220a49e2354175c9c3518928b6f66816df8cb07541bc98ba74ccaade2006864a911ef2375cefa601f93815eebda4ce60f627d356c	51	\\x000000010000000128a8c7572aeafaf301f8bdc67c1f234715b7b81f3fff62b51b85506077a6a17fbf7d3c245d0483c5bb156ff9206548fd0d6491716bff65ebaad681d3322b0fdbcd35f1dc6b8f7706bfb570b319739034f7072d2183061840c06351a2256567e92b59fcb75832266e44f9ed9ea30fa8b4eb8e3f90ae8f2bea6268caacf689d9ab	1	\\x56c4ab40be924a9c779bea44cde055218f3f26dd37d7cb0c19afaf87e183ff850357ef97bf28eb142ebcfee076d75c264d296cca741e30a3d3c625af8eeb3907	1647526107000000	1	2000000
3	\\x254bbb24b5dd2df125929ca11bf58e8423cd9836f5cc46c4bb765e2e4ce07ebbb36e72af55e1b621573452386c49f4a02f5e52a33afa84b283931434d8259cf3	75	\\x0000000100000001388d4faff8f5540d525dea273dd02cc9acfeff75d19ae3a72c944237263e7e5287e1dff14895eac12b664321ff80d137dcb59dfd12ffb47effff81a518b2de4380cd7204d29fe06b43f11a741535210856a03f9e7ad90d2c47e314fd7dd807d37171eb7768977e14a0469074194d83f8ad311962c81f41d54c6f79dbeb1b13ff	1	\\x4a90cad05350d222c382999c43d69befcd6b8a88e030ed6595c1584249a50a72b89d350f7a980eda7a710a061e0879fd877b5f6c253370872e85720527c2af05	1647526107000000	0	11000000
4	\\xb2f71c39334b9bbd7bd2ea01644e269c75c36666f2f82b3815ab17910a12d80002521c301a13ad1b21b8b4b34589d1e1dff475c071a03f24438a4aa6f16cb6b4	75	\\x000000010000000189bf0e812e1a98f07959f292b7a5987544782064819985369b6386092d87d988ebd8ddd1a1049e86fffff9fc46574d3ced2afa363ebc327b29fa9ece13b89314c86d94dca4f1f214ea69143740e84a861c0e53a716984793d8229d1fc57a10d7b2103162af54cc9046ae7da1d7ad199148b945ccaa8d08b3485e33606fe7f0d4	1	\\xaabcba046b8b84928944af139f9cfca5b018abddba7da174512ea08e01fca25edc7ef3b9f4bfb5de68f83164e42bcc69d5f685e83f12fffdc3630041140b6a00	1647526107000000	0	11000000
5	\\x667e98a22b8698c94407c953f93c819b48b989f13cd3fa993ac6d81e66526dea6e2315dcb9ed822452580ee045ff604e40c1d0c514d8b74ea6248904ce687142	75	\\x000000010000000195eb3bd3d2144985b97f45d1322dd47b91c625b4902fc5dab50e6b9921a6ca1866e8f4b600dc606346bc1a6fada5d49247fa8ee948c9ce72806acc9703418425228eadf7cfa7761285466fc7883406c85b27a35c4bb6340c5dce53b53a8fedd4428097017917bf75fadf86ac38378e843a47c80831b18936c303c8491e7f118c	1	\\xfdc05e857ca4ebd23931b45395b842e52bb665775f2cb1db4507c7f3e66a1d8704c3cdacc3c72246d9faf075f5c22aebad94c3a98820f814860c99aa86f75206	1647526107000000	0	11000000
6	\\x8deeda8c8af2a365764da16a02983f2c6537ae2fbe0398ba18364dc82f68f4fe0fa52481d6ba2ade709a02b5b96d2b48324369b2a2652e4fdb4ebedbfa2493cf	75	\\x0000000100000001408c00ada685d1b6067a5f8bc4f3313e64637d04265afd480f09889549a06cdc25ebd6937825424c610c0aa3706bbf0c23cd87ebc5598069759a05ed8bc8e2a01be4a4f825a5547c93a9a3d42251589337536e29417302241a08f1fdf2c172e2040f0d0fc6ddb96362238f24a354e186e24b3a49d50b8ed0f85ed01ec14c24	1	\\x349a191df6ed5dc8cdbe68af69bc1c55a048bd62f66442f367ef72edeeced2798c725763d05099c21f25f75f51cd5576a0d6558b1f8c2cdb73154cad11bffa04	1647526107000000	0	11000000
7	\\x14937348a11723de17fa9399aea619bde457b554e0ed5e15ff8f6957759b1c4ce890be265094d3ec4b0223403daf3bb1af0547b21ad37e95366d4ae5895b4873	75	\\x00000001000000010ab3f0fe05096283e8793a6faaa251c4562b24e7dc60697f06c1ecdd10166f0b0b2dc8d034dda22213d74e03a5c9c9f9e7635eb7dcc399e0eb3ae646545917bd0c7bba95bb86f2533e8215e7b0dbdc2a9548e6fbf2af663f77d6d1783784847acb35e240f52e3bb46a52da300b66c3d9a4766b409094bca27ff452e9dae05283	1	\\xd0a65d5f168162ab98b27e66aa94fb0b395d93719d5e6f12e1c3193e9adda1d4172bc10b2c81e441d7f521e50e6402eb35d1de845664a711b5a76965e81afa03	1647526107000000	0	11000000
8	\\x38559a8a5e04981ad24294baab617fd79204749a7cd2043d0ae0434903e8ea503618e8aa8112e880693680f6008a3aa046159957565318c33b813a79e7bc381d	75	\\x000000010000000171bf12911712295117cdfde59fa59dacd2503e11b8b462ec862fb0351b8e8382233e0f2567a696e322925f9f68cbf0391b2cba9e7a09c61905066ef44e42ee6bfa5dd77ef5005f33a1c3e8d04d95c17f64fcbebea14f7867eb1e34997fae078119817aa3ee5738235aeed7c90dac8d5f58a979fdc172225ec30f1fa64d6bd078	1	\\xf5c7a4d61a32f741a05869ff8c3ef9ce173f31e8f2780e9ba864ba2914700aa22b98c7b658b32bc8f6ff814663bca06999b349206ff294b87facdd963997a308	1647526107000000	0	11000000
9	\\xc62940941dfe142a2ae714c8b97ac9ddfd0eaf79c47f091793b0c86fc54c7aab22cdded266b4e4545e3411bdefe3ba3cbdc8ca1fb4eccb8c854bf76981a5efde	75	\\x000000010000000133ea0091ba02a837c42dcb22a73ef1d096eb02fb868d26460bfb94a7b113c4457bc011200ed38a60bb0d91e957bf91108bbdaddca0b2bfb8f65d3dbef294d9b3a05f8756887508fa9c46e9752f9ffd9ede789248d2e431e6a29e445d7896b64cd899b1ab7cae574fe97ecf18430eab58bc76c5dfd7eb0420abc595854a3df740	1	\\x92b49432078e3b0d125951d9ebe1718e975c5b371ce2d3cf4b2684f6f91f1cf7cb46cdd38eb741c809545cbe073f52a1621710e788cb2b89e7a8468f1aa50f0d	1647526107000000	0	11000000
10	\\x8c54fd75b65c97cdb8cddc9950fc9684b5486aa7b5c1c295720e60a84392a39a2e0e16f40c298b83e64bf3feb6191040f28681584fb367c1a84c26ecd4a8e10a	75	\\x0000000100000001465294e3d27f9c447d4428ff658191292953cc0b0b67de4c1585d76b4c6fac619468bdf1577de2c496ae084db00622201740aac4f7f9590a05f708905dc3b615f5889fae14ba78268d10265436918753e41b33ff097908bc0eec60e2e1f0921b910eafdfbe2c0fdcca10136a2a178cb571e392f76fabbf5aa0a6e0fa6bb392e9	1	\\x5c608d62a1da38765a8e3d131809109104e5ab024bd7ffbf734bf1e090d27403effc8909e3d72958f7395b6771870cb6d856d6de7ae4e0fd4b7d41dba8825f0d	1647526107000000	0	11000000
11	\\x0ee7b02e272518981896daf546e677f4b9db705b1a42513afdf4f9e8c34bdd368873341bdcc70fdc333222fd01e5b3c4961ce0ddd08623e521adbed086f3a578	220	\\x00000001000000016f7d63342616de36654814143345addfbe502766f2ac40d20b08fccae9ecb1cd20589ca7daae1dbb2fe0a1d144bb733d69121f6423f6c147e9cff21fc6d47ca0fe5f7ce3809f0ecff03299f2fd2725271bfb1873590180f556aad41f686ff19c0d4a3716c1566efd335ae2255bdf96708a9df0e96d998b52dfb226dff0ada79f	1	\\xf39073192346141e4ef079899ebbae9b3cd1cf4db4b3e205ce1facef0621e0978461ad482326cf5e1da96d14e4dd35223331b155997c6d4132233de702fed90d	1647526107000000	0	2000000
12	\\x281f041145ddce81af9ca8d3030995f8030a7745e67ab0591530e96a161a4a0f2776c844442a133aaefa1ae7ff2edc76370baffac372aa1aeade0d2e84e4007f	220	\\x00000001000000014823f3cc7e5a3703b2c75c2ad5c8c95dbf227f0d9b486949df40b908542644a04e3b75e21d6adb7841c4ea9605f6a99090bc8a282342f06377b4917d2699b2ab0ba1fc36bb46d4dc1fc895608741b3c71ec275ff33b80f119f4e7278161af08efb1574b4ee67b7e7f0fea515cedfca54c06b84aa605bddb194c5cc8308a6ad1a	1	\\x797437b96be09060b5fad98cc653f523a5abc5bdda803510f0649811af0e4c73af0c7e6424ba4e7cd0ccbea9d0a046630b50ef5211bd3dd10f29e7621fcb310a	1647526107000000	0	2000000
13	\\x2d7afb38797e74883dd150503cc238bc55e73dfedc9744c78750b8c7c1dc86d5e19a83dd2a15a9c9a6f2908e51ac57848a8865a43f0fccaab473c28cac918047	402	\\x00000001000000011fa2e3cf09b4509effb1c5d1e95d07639ace675c0b04692ca32c30bdc397adf1d01cea017a1cd2aa821016e1ff4bd55717de36b66b38136b582d9f8550a0e3c94f12511733c77e4f811f27ccf0175b9c1aea55aa0d71666de729d5efceb720f36547d3008bc721ae8672f23ac4940a59ac0a0d970f3f19774058be0d99c782c9	2	\\xd326085cf74bc253bac0e3912107921747dd4f7bf27555f49870c9518889e4ddbf762045725a5ea86ed85b3882cb214835baf504e49f0634dc11133de9c57300	1647526113000000	10	1000000
14	\\x16f390489e74f11cf0ee86aa1e1eb80799aa72cf000cb9b6dc6e967922406a29e62e6d3b973449d39abcbe674232e63a34e501b54ff1cd4380c803939c151057	421	\\x0000000100000001384d45f41112eb6a5428636bbe335e698ab24c90b939e137ff7595bcf1e2480f0b7647515564315c30fb8f26f9f1348eb72ab1c33cb6077ee1b58e9bff4dfb232d7b4f4330ee7813a7d2343e88bae7d992d6d89c5121b077d2b2753ea576c2f1f80ced5cb9b898a854959c493c3f6c10db92c0a579d28c90ac5ad0dd6c0a4084	2	\\xc7cd6c8bf168476f4abe4afc075edbd4b48664bfbb9ec61f2f0f38e7dfe3e067670b4698e1638fc04b3183977cf191e2927c69038160b939a3f9b3385de9c709	1647526114000000	5	1000000
15	\\xd4f176b63335b8403fb09dfb3d33ca41445f6c3f5fb9fa380df90684271dc22ec5ac21e0f119df9eb6e894f2fdbe359c171e880cc8e06b9d621a13c9d0ab6101	201	\\x00000001000000019479af29e1e54fba4253fae5b47d055b57069b831fe80a260068f0dcc618903ac231488b6c6b2400c571b52303281d2919cd060223de7dcb16658d901917db1be510a1ad062b61b1e991bfa8cc09012794b6cba130e89158e550befed558c5f5b3b073da04452ce75c9c26883afce2dbb79b1960708cc88457a983f065060422	2	\\x1d94174adc046c16673d28b77414272fd4c1a5bf48402d8f780aafc888f38dec7e5036334332fc4ea18820e0c6e5019afeaca498f9d7dffefe621031d5f92c0f	1647526114000000	2	3000000
16	\\x4d3e17d356571590bc4444b1bb13ed1a899c14dc1f5189f9e9cfdc3b1fcf09989b9380d68d1f8af1c0f5741f5ab22944981f98d63b91525c799416d3854ed484	75	\\x000000010000000107e3c64469fcad583ee8e0156e01b317d54ee15a4a953f27bae2baa19ee193e4171c0fa538316ef05f68d970e0132a4d0fd59574605a86592ab590cc3620452c9dfb05c4a44b972adc113b574d958c5c4408bf78f7a1b6e69190c9a399dcf6c75d6d263bcffe0351566eb878d4e2aab4f1c8a80f36cb8719c33b017bc4f27105	2	\\xec066dba7c2f339a4ebe7eb4f139ebbcc3f91be750b901a23f739c7a21ab5b0f368d225fdb53361c03c7c8cc365e2f59df9aaf7c9b32bdcfca64b349f303b605	1647526114000000	0	11000000
17	\\x07f43ccdc3da9cdfb3b38636581b88dc82bf479b8ab61990b663ae2af32434edc0ffa0e689e77e02e9f1c0b18ccdc27182440bf3747b142601cd610ef3a59cc2	75	\\x00000001000000014f04811a136d1828aa30cf0bcffb69ad35af0fef8349585e61a2912ecc45a9da8d6b4d8363c54635950f66353bdaf1ad6258eecf83a2015f984c40d5421c5081f1c888b22bdf4c5717a439c4694e7d191fb2a7e3cf68d8b54262803b5c8546c2f3c59b7f64a25af3a5950b36be4118cf6f230f4b17c15ee94e07eb48521e2f3e	2	\\xd4448f7f1509bced82cf719e80c069922cd0168a9fd1cb117dd90b52dae5a0f918370655ebd62f579989c3e25113502a5189a5d1da8e70837fff0a5c5151ea0d	1647526114000000	0	11000000
18	\\x708808f15c331a956cf552aa86e5370a2dc7919d8e197de2be7096b639a2a0e651079f671ba14103bc8f58cece9b68d892233226a83506d32ef6e042849b8296	75	\\x0000000100000001a450521af572d55b3928721e1ac30c1f4c6bd90ec362fca9c0e7736c65dd9900618c4c5ca2168cfa10282f9054d6f4ac6124c435c2dd616501f647676119f7623750822596563f033dbb527f1d419bbb2f744fe96a32a010da9f414154d04c5dcff0cd9f2c1bb80f6c438639674baf41d8ef35635e21c9aca3441b21101a086f	2	\\x45abc5de6f4ec6f5ddcd08b7f3989f0f3deb61a33738ac52850ea2fb3e1a5c42220f1185e3f770b3da84c559750a308a68dc4206a875da9f86b6751cd1781e08	1647526114000000	0	11000000
19	\\x9e9ae9f5a4cd737cc5c356b0db0eba50282e895169f2e700b00818d99af214d4c4eb1d7c569d20a070d68710a1f9b2746ff2eff635ee65e9af8959927edcc6ae	75	\\x0000000100000001442eb6953e4ff4d721768dec34afc09b2436b12cc4bad7f07ee2d1d3531791474cbe057cedf213d861102c1a900dfeda020a4450be8f0dc4366834b53e66323050149fe29499727db10844d3c8b93fbb1ebb0b19d0715f7064634f75a2cb57cecd5b0a9afdd2176becb18c461b528549d67096f451a5137988f61ac4431d89ce	2	\\x050993e3b4843876ebdc1c8b71c39bfe313ff4f60874bf7281a966fa87089c17236564d519a8f87868df8655947f27c3b2330cb27ba7cf07642766de41d7540a	1647526114000000	0	11000000
20	\\xadc6c49e5673cfdaceca18389ae720981eac406cc2641736ac42ffa2f05923be4a1be3520d45a8385ea2553e6b9db9f58a06b50977bb68a1e82e28833c2e76f4	75	\\x00000001000000010278af7c99e60318611d3e109289e21a00cc4011ac3d13dd116091316db9f91ab72b31e1e27b68571a1d7d8d538a2f3c7fe3fc4030b9d9d877a79dfee16808348133d3ed8e303be139dae9a006eac8cdcfae782338c12f4c39ae9a4718c11abe087b9bcf649dc36ee1989d05689e85573fc1ab0e925622b82590ce85d2d8003f	2	\\x893dfd1fa96a2be2d0f23fd78b5259cd4bc5274be365500eec2ee454e7815d3f2d503a5e0228999cf7d394422a2f2412a90b555d8eafec0bf3a9256e81fe1700	1647526114000000	0	11000000
21	\\x36b5b19bd7e2b4dbbfb57f5bcced78b7887d361d65af8dcffa49b93b3bf504c9cb2d05eb60f3f57d308ad4e0cf40b5edfe66fb31670cf011c5625b2c9a28625a	75	\\x00000001000000018e0fa412ecc7054b96d420bc4bd72e808cded4cb564b56ebcf2b024cc7781b791f83969ec7348af36c11c47e368db3d03fc67256fa9c6c9d4689d8ad27a27a3c88c45f99a5e46ae26b94370a988425664b71f280c61635f723af565b8848f679782e474bb6b4f378b52c8660e8c7ad24327a6e864eddefcb1f0ba3967f66a10e	2	\\x1baeee61e60cf5fd692af6ccc8136df94a275d532938ff37078a9eb9cceb9895971d88eb5b3c6e85f99a97f9d3f00789151e9aecb371c6be39ba5cbbbe920109	1647526114000000	0	11000000
22	\\x9f789754144a86424255eb142f58ccd9380887562bbf29c273ef98348d8abc4e96c31cc87b04aec22736d807ecc8d26dca172f81cb769fbe79695605ed36d257	75	\\x0000000100000001a2551bbd3c3da3dcca64d32ce88b4eb192e03a6799c971565c87afb2f6700ace58043ad7b81cc3d520ffff15d21b65afd9c2e97becef06e9d0fa106d7e566378b2b04774584a39e7ef0234288d8667843bbd170c684099cba8592281080209d4173d159b254129c8913e06711eef60374ed7307642d06b66c83e17c9563fddf3	2	\\xc597bbaa0641c9b2e02e5638d6b3541eb7fcd65bb219e49500c42e4d5fc2229b923f2a9ab433d05a0c2c1240a6f0cf1380f13dc5704f28b2de4e4770d1f28900	1647526114000000	0	11000000
23	\\x391ebe3efb98796ecee0d86ab9bef262da9b08e2d5abebdd446f8772e6bba6337629d18c65848de29bec34ad9a9086697ddf2d2097af9a144911b6b2038f066a	75	\\x00000001000000013e285f864850826d1dfb20c52d2806b449f9823eb0bf528d51a912f0b492f756c6bc9e9f77c00ed3b9282739032e219fca5252584c646ee905f9a3897d0c5c59c88967069c09f1c24c5ad68eaef6664eedf9677434c8f85daeb75edba113eddc85a3233dd62ca5c46796f1ad4d38b7a60c814ec20ae08c2c77a3ce12ae6746c7	2	\\xd90b74d28b9e5dac9e6e7722f4c2b3dac5bf679865fcf62eb4ce3d165d976c02bfd766722b5866297906291d23e0d6169ce05fed437bcaa25e290b2566f32d0d	1647526114000000	0	11000000
24	\\x1768a0e3c5a0e6700c7b89a827188379c8fb893f6a1389300f9de168b984211c595dcfcc89015e697bce061696004f04e135e1b4808ddd71faf573dcc82a7eb3	220	\\x0000000100000001513a8b1872040d1417fe8af54bac22c0d19e9a641e36d01b6270e887a70ec881743e735ee426e48dbf78ef3220f5b95e5c3241a209bcdc973a5b7c948442509bb53231e9bba3e27f51683185035f5aa5669cfe28358bd12aeffe6de88e7fe58ea4905ae99cfac5eacc23dca229a6531c2f0178f3f289e46d28109e646801d940	2	\\xd5944cde717fd843409c7ce8c25c319c3362cd49ac3d113bba1f10fce120636a1ef407e50a1ec226732d3f2354e3eb9667d46ecc69bf26f83fcbbd2c9e1c0405	1647526114000000	0	2000000
25	\\xd3cd8c588be5e7c15a8ebd4c5d1328a87a8c7daada6dbe0af98f224c71e5d0af7993d80beaa75951095d5d2415cb6864ffc1b4ed574a578c2bc5728820a465bd	220	\\x0000000100000001396ee35d5fe02373073c3ed9a99c499e00ad597e36e0b3c5d1c218dcf7395960b731e820fd14b3cfff2a873857e1312b4c1bdd8b15b6e04d5416f89b9c6acfec797e316895fa5d8344c333a48c9c1789e6ad55844bb966f82088e92166c5fd590ce9ef9d78b665589eff4fda980e66691e0b4dc4b62eabc7a146821a504fab20	2	\\x911c0312de5247b8cf4326ef19198d6c584b23b4a0dbb4e95ef693eefbce6dc87719e717d9123b1a99b23fa4da4217ed593f63d6e8b131f65c69512799a8da05	1647526114000000	0	2000000
26	\\x8b52b5d65d428220a0daac579f77b9086d55dd539bd1b454834f7237c132c253cbd1a996513bf72de6a6e281e43f39cce675257a86b71dfae5dbdbab152d0ccf	220	\\x0000000100000001cc9cea7a15b4c0177a8eb9b9f48588b2558564601fda02bf57d5e989afb2e25ee18b79edc807fee87735f06890e56972392bd47404e26ccdad0d3cef4ccdc1b621891e6c0aecaafa06de4757b99c5c94cef1240c51b806693bf330b0d58ecb58bdc4fc5c6e7b054cd94306906e247bc018b32059c16a68802e8aca0d0bcffd03	2	\\x240273517bac8f35dc312633344b38f9bec4eb40d76d0d94387300ea86795a6a7d5016e990c6577ae900655c5e7e9bef2ba4ca949d62a506b5346aaf1c27040d	1647526114000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xf132e863387fc2b070f2ab6d4eaeb293e0f7472876e4527604ece9afdf4e3be17a1ed362815af871f764e1a3693e52c7383862e02b344172bd48f99460a1de0d	t	1647526098000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xec92b8edc45e7af65b5b1fe305a81b913b383befcaa497f801ff31c2d1f63850ef31e9585efe4477797155a586cf369173c57ed7390a41866703193ce806ae08
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
1	\\x1125e481912bbcb6e98eafe94f6a0d338508a72294fd9847edb1084b298b658f	payto://x-taler-bank/localhost/testuser-azpvauj6	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\x4026c0373a59ba5f21c6ef17c5716f60c3e47f0c4bc2c181d35a1b1f5c11eca2	payto://x-taler-bank/localhost/testuser-mmsicqqf	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647526091000000	0	1024	f	wirewatch-exchange-account-1
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
-- Name: deposits deposits_shard_known_coin_id_merchant_pub_h_contract_terms_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits
    ADD CONSTRAINT deposits_shard_known_coin_id_merchant_pub_h_contract_terms_key UNIQUE (shard, known_coin_id, merchant_pub, h_contract_terms);


--
-- Name: deposits_default deposits_default_shard_known_coin_id_merchant_pub_h_contrac_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposits_default
    ADD CONSTRAINT deposits_default_shard_known_coin_id_merchant_pub_h_contrac_key UNIQUE (shard, known_coin_id, merchant_pub, h_contract_terms);


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
-- Name: known_coins_default known_coins_default_known_coin_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_coins_default
    ADD CONSTRAINT known_coins_default_known_coin_id_key UNIQUE (known_coin_id);


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
-- Name: recoup_by_known_coin_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_known_coin_id_index ON ONLY public.recoup USING btree (known_coin_id);


--
-- Name: recoup_by_recoup_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_recoup_uuid_index ON ONLY public.recoup USING btree (recoup_uuid);


--
-- Name: recoup_by_reserve_out_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_by_reserve_out_serial_id_index ON ONLY public.recoup USING btree (reserve_out_serial_id);


--
-- Name: recoup_default_known_coin_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_known_coin_id_idx ON public.recoup_default USING btree (known_coin_id);


--
-- Name: recoup_default_recoup_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_recoup_uuid_idx ON public.recoup_default USING btree (recoup_uuid);


--
-- Name: recoup_default_reserve_out_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_default_reserve_out_serial_id_idx ON public.recoup_default USING btree (reserve_out_serial_id);


--
-- Name: recoup_refresh_by_known_coin_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_known_coin_id_index ON ONLY public.recoup_refresh USING btree (known_coin_id);


--
-- Name: recoup_refresh_by_recoup_refresh_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_recoup_refresh_uuid_index ON ONLY public.recoup_refresh USING btree (recoup_refresh_uuid);


--
-- Name: recoup_refresh_by_rrc_serial_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_by_rrc_serial_index ON ONLY public.recoup_refresh USING btree (rrc_serial);


--
-- Name: recoup_refresh_default_known_coin_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recoup_refresh_default_known_coin_id_idx ON public.recoup_refresh_default USING btree (known_coin_id);


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
-- Name: deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_get_ready_index ATTACH PARTITION public.deposits_default_shard_done_extension_blocked_tiny_wire_dea_idx;


--
-- Name: deposits_default_shard_known_coin_id_merchant_pub_h_contrac_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_shard_known_coin_id_merchant_pub_h_contract_terms_key ATTACH PARTITION public.deposits_default_shard_known_coin_id_merchant_pub_h_contrac_key;


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
-- Name: recoup_default_known_coin_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_known_coin_id_index ATTACH PARTITION public.recoup_default_known_coin_id_idx;


--
-- Name: recoup_default_recoup_uuid_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_recoup_uuid_index ATTACH PARTITION public.recoup_default_recoup_uuid_idx;


--
-- Name: recoup_default_reserve_out_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_by_reserve_out_serial_id_index ATTACH PARTITION public.recoup_default_reserve_out_serial_id_idx;


--
-- Name: recoup_refresh_default_known_coin_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.recoup_refresh_by_known_coin_id_index ATTACH PARTITION public.recoup_refresh_default_known_coin_id_idx;


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

