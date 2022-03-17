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
exchange-0001	2022-03-17 15:02:35.873149+01	grothoff	{}	{}
merchant-0001	2022-03-17 15:02:37.148529+01	grothoff	{}	{}
auditor-0001	2022-03-17 15:02:37.95991+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-03-17 15:02:49.062137+01	f	140842ad-983c-4194-9d83-5456267eacf1	12	1
2	TESTKUDOS:8	6EQS4YH00QC94Y0G0ACNDWADB1H71AM8CAS9TMEVHVMXR1MR10KG	2022-03-17 15:02:52.633286+01	f	6dc186c3-6292-484b-85a7-c0b8e40b11c1	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
3fdb9a41-73d4-49cf-a8a1-afdb59aaa3d1	TESTKUDOS:8	t	t	f	6EQS4YH00QC94Y0G0ACNDWADB1H71AM8CAS9TMEVHVMXR1MR10KG	2	12
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
1	1	43	\\x6fca1007c0d4fde985cac34df5da1bba00b768603419781e61fa580368f649b9edd708b0c2fd19d7df3e2d3f6b555ae8cf28ae7559081d4be15e12fe1b9bd70e
2	1	157	\\x499f2761730db9ab26b1bccf0d5ed200e0c292e1ee750c9430b0c4d84057ba4880b90cdecfdfa0ed4afd54cc78a58acf5976bb7d27ee8485fa52301f17bfef04
3	1	406	\\x1b996884b72add69410aa541c7615103cc4b87bf1151212c704e634812031e0425dc1121811de99a5b9f9cf3dd3afd7fc7dc006343e17d1f2f55498cf5dbf200
4	1	63	\\x0646b937d2898c2c0543af85b15320ee64080eeeaab11f55d87ae34367878e0a622f145fd62534cc9aebbea8c0659fd62f196ec0aba644e34f467d05f5c14802
5	1	195	\\x5fa6bde3cefec5a97b9703f16f766b58a5fb2df460800fbfac4fab310b80b7d1131afe2541694b99110f4bda744ccbf386e9e23921a855606aabbf55091bc808
6	1	75	\\x97aeb03d01acc10f0684e44c5066b812f61982a46b90004fb1807c85004b1742473443ac755c42fc090f78be4f492831ba8f3836e9a970ce5a263e3aac537001
7	1	396	\\xc0d06f678e8f485d13346ab1c21b424404167b276758123d9197c63a5f646b9118757f7c7ce6f4e04baa85d674c08558c2007b798ab917eace8de584aa5afd0a
8	1	291	\\xac53faaff2ad47a44f241d017f9ca0e447acdc2dfe49d1e59951db1b919df3cc8154d17a4b6dcb36c45a320b95c79caa150ec354fe9f90c538fa3bec9fc8d00e
9	1	208	\\x3a4671957ca4a4b7372b3e4609fd063d7dfc4b1664fc5ac81e4f47a8f54d12b2c9f9a5e28c0523cbd0baa1cda0a1b99cc2a643a343dc949a8d13a4ffc06bee08
10	1	317	\\x3c6dfc2b1f908a30c808ed98c44a0ec3f59b90e4e1f87c9b0a5936c562a67dc3c46bb7db7d078cc90a19ed73887e88b092d7f061537bb74dbb92b83cff6c2a0b
11	1	59	\\x3cebaf1f68f2cbd681d682b8b89d5bb5e8e9180dd38169497ef5112c616414873461e7f7fb633087bd33721bc915a9ec0f8ba7da1b1bd7cc3b167eb701531f00
12	1	128	\\x0000480980498e29c3e4fcaede5893286a33864606af20c9402f9f4a230ffff0c87a921074baa363aca24ad500f8388d5f3f9183e63de053326dbf254444e40c
13	1	367	\\x2fb151338de2dca41ee9aabaa3a8a298e0d31dc9ca61989e24c58a990a08951cfb49d9c33be3b85c5ac8f2b77fd7d23aaa15bd95a7356dabfb89a562d6134d0a
14	1	9	\\x82a06e5f07dc96f37a631c58015b3830ed717f877d575a7b36299d1a2ebc9b7ca8b17f584c25800ec8b407fe931f57235c029df85c4536d2031fa71a42fc7608
15	1	20	\\xedad77d450be110107e62285b5d99c4264d31a0a74b06c089074729d6705bb5a03d339a8c961ffa7ecd92c60edb909000c1d051ca0f94d3f686f2a32719b7c0a
16	1	137	\\x5fd51a30b558cbd1078d9a01c066b549fb918d3bb7eb563623d75e9a14edb288708519018a9ee8cbd708ee92160ecd2353638ff10436a387a216d50f7effc800
17	1	21	\\x40aa17ab782ea34fae9a28d6875433025581465b5633fe1c3507a9f883c545695e6234eaeb9ae17bfd841ec7f3b0bff1a72b7a08ce8a852907110723f0dd5505
18	1	97	\\xeda42e9d0ddf56ac402c53179463b5f6f26ef440029d5c07ab206382f2afac499d556aade19b5870b3cc7230188f28c89daaacb712fde1c8726bc32eed35f00e
19	1	49	\\x083f8782b54bdd1b8f1680fd3f08cdaeec1aec998c8311319501aee1b4f3458743eddb8d9ef6537e0874e5199ea9d90e2b40e676ba321c624d80a0cc3cacc60a
20	1	372	\\x1f850d9508779f968f65173a5bc1e6a0984bd2b6ee1f72ac3d5346d8bac7a4d4115a684144b883357f744a3e5bdb60f042bc3c4073d43cb8be0f737b117cb40c
21	1	188	\\x8eebc5c5b2db56a6ad9c8a173b27bad9fe6fd3387f421d9ad05efe4fa7e830ab08cd7628c924a39c07604a95b044aeffdda80027938a2e793e5278e851a8e70d
22	1	218	\\x063b750c7641828ceb19c4c7062df7feb8cb6c723d23385c5c61f8c4b0a3cf47121e0126722456d3630585d02a9f3f88c7c2ffef872fb832272d4a98fb97ca0d
23	1	292	\\x7139953397d26366bf062a0059f0584dd9e13facba2bebc0c6fd89029b94528d515f34282c42fa42988fc6005b51bdc8f4f2bb841c81c305f7ced2cbb7ffd201
24	1	373	\\x1d3b128f081dd3fa332ec9149249daea34fcec8b63cfbdc958de3a4203e745982bad90772e4e78b516713dca48be219ac0fd59f6475bb71e2ab20b2ddd70a30d
25	1	357	\\x65772d6d45c37f86df848b6a031955b3e681e2c9d57d681938ab46173d499fc2ef080aa8c8b8bd762dfe373c2df04e00f1e631575f567c1cbde23cd4b90c2209
26	1	308	\\x1a27c248ef58bc29198a2ebeae678035a29df0153a368b97872cb7181142465d2ab7b6875fd6d23dd04065963ee60cbf1eeb829ca27c69bd5dd716b3ce608003
27	1	213	\\xa206f740082727b5fd488ce088941e4823cf75089d84deac180b41d533703766114dd2b2bdf4784653ab0838d0a4606de7bb11d3e3311137f0e09ba25c3fc50a
28	1	345	\\xdb204d49640e6a52c355a30ce0d7fe18341be71af9586d64e124fbbbc86b152c6ad673f1599929222a269532e92e99b64e3ab873f32961d468f33e8607350706
29	1	231	\\x03c5cca8a42dd5dd0abb244ce3c264ec0671452ed9e0ca92360bfd741a7e005107f77f33971bb3033f45423f8614d0c793ec63651d6ba54e28aa29ae58c8c804
30	1	331	\\x4382406448439cdbf1e8c201f458f4024aef91cd4bc9b818bb9192cf322b557b0d51e16c29ef3e6b62016f7b1f2ef26b4bac15a015c0e2679bdbab737c75e400
31	1	60	\\xa11e88a2d07d4a2238d38ef66cdcf8d4a463df09dc6638be093cff98a1e3368879cda88de0c7a90b9374d2c7349b244d1162d621d0592c01f2c70f837f3adb00
32	1	7	\\x21476e65a1b034d608d310c7d7dcc37d512b425f39d4ec3364eeeaecb6cbcbde325f58f5bd670d656c60c1de6045cfd4931ab06233aefa8f82d68daa2bc4940a
33	1	256	\\xcb328b8b2f8a0a6ca7afaeadd021b8931e9672b08e729d06f3a8bea05149221873cf4b7d243d3406c9b93a54979cb49d6cbfa857c216e6ac835da5466dbad606
34	1	318	\\x88c0da966e1039211d8080704fd078be1f9149e47fefcc992ac1835d004c384a06d70c83f810a7d83206c791333b4492f2fcc6fc718d8bfb5977bc2d8b8ff90b
35	1	76	\\x2ae588b2715f93f01ca0757bcbc635c4125459e9431279cc35d3aa73767962ed863545cded49bdf9358c6e3b9df05c055d32c2d09051ed8bfaeae38092919002
36	1	203	\\x579891c33517bdade48a936d781f38d1fa2ca94fa4cac7730e7187684c9da9975ff3622b67bdc485ea8baf9f9d0627df4256a5592c45a5251fc7acae0371f304
37	1	328	\\x33b0a61893bf351f6de52f1cabb2fc7a31476987da4e8c19c5e3c831f1edf4e6955df169004abe947af626873b751cd2d97900718e7716c0dfeec9f87e4de105
38	1	284	\\x5be39fad0523b362b8a5799d9f905d4d5df409cb0528de4ca959dbbf97a69e7a2b01f6a5678de282666ae97395fdb9f2fc737e77b1dace8ba0e9f1d1be03f707
39	1	424	\\x4d6c84be89978436fd3c500d67cadf0aacd698cad11fcba7f17f2bbc306f96be4666e9d3f779e2fd19113c1a587062a20ce8a8249545501727cfc95128c33305
40	1	269	\\xbe9ab6fb5ddd8a9798356b17f3d977d68b69df708f5c02a434aa59686aee40ab9df4f027ba58132d8f2b099f8a69e134ba9a9e0ced6759466cb19e93cc918e04
41	1	358	\\x71666ed093e1d833126fd6167d1329d918999f62a974b8fe3796fd7dd068678e6c77cdb9e6b953e492dcde5c1dea2ca79d1c13919eab505b4db8cae46ec14f00
42	1	103	\\xfce1906d29449d884698e4c7c91b51b1c55651c5f3090027e17d1ac62b3b163bae55487c2bd6d60aa9a551cc6c3d720e7cb0502db644556aa50e40599083a70c
43	1	96	\\xee470494bbd33dab70134f7d058d2596c3d00fc1966672c6d039c793712abbb09a2d22d2f53161326b199336675051c0f7e209719465b27a0fa1b27dfed05905
44	1	170	\\xa18d62ce657a247350167c7e1fd7cd3311000196ef561760e9e7343b504010980a035c92f1fc4b6fb65b96f533b7e06487c8f8d292810d7f390ad3addb3be70b
45	1	360	\\x81d49909eebf68eba352b34d6608f6982c5ce43e3bab81340903288b1473fc1873ecb6eefc72ef354ef22a566f6d3a170d77d7f2b2f540060b4af9db6d8f4509
46	1	301	\\x96cb00a62fb7e30db6253fb3e47e69c3b05249ba07defd9ac7402dffc8f5ec2460cc080e14046ebaf1d485546135687961d049cda4f734722645cbd484246d06
47	1	389	\\x9cfc83fc830c59861b65bf9554e9204507312624776b2ac46c846f4974f1a1bdcce43b68c9908c4299ad4e6e66cf42f30f39b89c9caef5665512d92efbc7ca0d
48	1	332	\\xdb87c615cf2989dc2c68b9951b79922f3e7eb5a6266f5a8d69abe97880c69f4755930d3779c24601e964b6f93102c46cdc0b09b5535e28ca86cd3e69db280d0e
49	1	356	\\xaa1fda37e09f67bf5034f65785c7d96abc84110e2b7397649328e879fbe9f64bfb3d00d14cc3d791431002bd4075c8c29413dd0c81e1a1825009a4f78e1f6d04
50	1	136	\\x7cde391443502af262e2088276aa06882a3c424e5418cf9b7f035477ee07f78de1cb834b35323d6249bb20bb994337e45ca54f8cf0e8c6be928798c9b68e770c
51	1	197	\\xa3462a41dbf75bf50c0df47d6fe0e77697117e3dbb854f5ac8014cfa572a22a566b414bea16de16ba90600f98aa7a2fff01d988e806575527eff42dc46565905
52	1	224	\\xc261499c9ac74264446668b78defb55f921a17f92e2c9998267211fd657ba6974e5d4f97f76849f4e09daa14b83754c01bde84efadc9123c139d63ccd76a4c01
53	1	241	\\x71bf9a7560893b47ea446eef3e14bcef03d8dfbc7c240d920a657849393a4428d167da901da5bbd1da2d67e6dbb1aab7ed198b11b1519dcba301b418b0a4940a
54	1	165	\\x1fb39a010ec0c3b5697d446b013a9a4654d05deb95ae5e6e87f47d2a337cfbfb9b86bbf55e10fca9771a0630f1c95fb5bb0b983a28cb73b3d11fb4de1b77730a
55	1	95	\\x517874d8375751061e93d0b5bca64338164fca1fd5bebc46d0dcae292fa198a1770b1385f50f19431f3c4f76740968abf7f25228685e27c8fe8dff37297b5a0f
56	1	69	\\x9f92d8134736d6991a9e4ebe70513c0eaec782b59228be493b79dcc83a432d690e2780381952680624ad8dda260a67f0c19ca95d525d80e86059d67d89a1c908
57	1	378	\\xaa9be7598110ea6ea80e03c82724d3e674e7cca640b96df927cb05a66ea7118dd1415a0a3d49bee98863f3e2bb32f043bc827e09d27810633a1e0b5925fd900f
58	1	134	\\x86a0525a95b403a909c78cd0442509ca7e8e342a3fbd572a0bd115df64cd9734f53b849d48ae5511f4b9404c3e6e42411d5e23d3f943390468116008d1bd7c0a
59	1	261	\\x3445bb35f6c606fe455e9244b421d28387401769624be189c09c56f3f995f9cf8de7ffd44c4472239fa4036de8969609b981cbf38f9c181780ba52c890cdd504
60	1	114	\\x62e024266b0f38014e7d8aa48d94c3f5ea203d1120598454e2ff7198a52b95e44ea8ef1ad4fbd55066ad191877c6a576947c57999a554f3f56280b1535c3df0b
61	1	130	\\xdb642da0dd36850c738d4e44a3c7ce672d68d6052d89acfff932ae31a34a34384b841fb09ba1b72dfb4bea10c482938924b5f26d0b7ecb25e930f7e8eb835e04
62	1	104	\\x34dc58a004b71a2372f41022d4c244a62f19e9d5ddd813bbed8bb7e6a0a883560410c6a1fcadb5253ad7a7d644e658336abea0f2faf4bc2c471165e3fc7adf0b
63	1	280	\\xc3b74d18ade18720db55f99d12e32176101cb41cd780d7d44214e1582c537da4304353bb1ea318dc5ceb7701c54ee36cced8d091e4a7f7f629f710ff8a532102
64	1	88	\\xe4ae42b14d81adba5748aad97e1a858fd93555e5ab211caaabb114125b9325116acaf1db521b18b758821f1af9b051938ba361dc38497dacd6d6bd3fbb31bc0f
65	1	315	\\xb50bd87889c7c3f53b87517be2fdf0d1c8d00e044f08eedd906c00993bc5d97d69e81edb7ddbb223c186408b4ea1aa99e6a75b22dc74512b79d6b87e49e5590c
66	1	143	\\x5fc072e72f08b99d49f4183b40a64614731c7787c75e1ea5889d19570e5d5c728d7827cb367f1706d66ab9c0435c2819c0c7a101ceb8ce072082ae26cacce306
67	1	371	\\x6186be0d87445696dd258900f10a7f32bc4f4199e96d6cdb338bb84a862d0f921dd48b16bec098958ac17b7cb7fcb01e28a5b0e7c619c0dc60749863c24bd302
68	1	322	\\x080864397037888e5663b6fb12c288504a1044822f3923b5492cbe10607d5c322f4f8f7332c9b0a08b06afe7c957111b5b20e31b75a00fb57d7b4dd690ce8106
69	1	72	\\x41431b363cbdb9f63f2febf8dba530bddc5b7e1f7ece7ba9a91c10c186a03a442d87ab0ae41bc939b1a16b5a56d090c870148d24a7cab4d4ee0012021d59b90f
70	1	66	\\x9294a6a7a337d760fd979a9685d8eb4abb9b948d488c64245e28ff33edba3fadb0e253621c95126f6bde3a022adceb40aa4afa9eae79adf6d9abb1772bcfd703
71	1	260	\\x68cc96916230a70d9220bb395e144ad6204ed0b9c03cf1968da7c4b0228855da40b2c4ecf1c5142cc27b45a53bc56be00ff98e339b2610fc0fa15d5d3625f90d
72	1	293	\\xe862a3cf202c3eab76c166c9a875e8e81778297b109ab97276ea02fb266c8579326ec3970721b5e384f1136d49ad3863de3f846c960bdf82d1726cf6da35d40d
73	1	4	\\x0e8f939f29a101326e390fa294289fc95f6c79c107e078389a2c25c67a4175dd832a534f97df08b8b0fe55233bd6144d809fbc7340c7a737f57006464b496101
74	1	249	\\x668591844825358863aadfd2793ad0bb696beabcf9a631c95e807ed7715c065f835f2425764e6eb1615245d2f81b056ab6ff4638b9f6c3b1a5c548705f640c02
75	1	324	\\xbdd36ae3f594a4af6d9cdfbdeddb2483f725a45186c8bfec260dba3e855e3f02c065303fc2d26e8f5ee5c3e36741403591c2a5951015c4334a502eff95514d03
76	1	310	\\x13ec573cf86108f53bb08c1507320c0c143c4794a7307c0c791c1b6cf9044fd04819488cc7324032a4f89fee47532ff6ca460848d124a88ae3b861a09b8cce02
77	1	148	\\x7a3201a222b87dc32fe93b8779cadde211102ad80d048170996fff8faa66fe4c3cd460f0839c3d2132a0f38f4e7caf5b63339facd1b36fbd5c61edb27f063904
78	1	178	\\xff16bc01cf622586bf69c43405e4ecaaf8694800585795c983da7579bf4c5694fd5047f39a93eea1d98662481a33dac9f9ca1ca5e77a16985f878b84398b3503
79	1	221	\\xcecb1998c302f1091fd2d4aae5f9d1f07e67098aac297b6d55c07032ae2a4d18e9dcdc9296e4172e80b490fc69167f6343b6453c218c4b9448914dde8f9a3e0e
80	1	227	\\x921ef5fa5854517956049cd42226faa7f7009f096e65fba9b61c4535df31b75738169661c49549e5b2e260ef456bccb8d4cdb1d8b7bf8525403762ea27a32203
81	1	226	\\xabcba4aba17f403949b039829b917ac9c2c2d90df44ce6a78f9a393976f04290edee5f59e4057c9b09075e79dbfe1f8bebb78034b1796a8764b7062eccfd4804
82	1	11	\\xdaf447f4d8fbbd35df8830afbf9e348583da9811c6d7a9194933101d6693caff519f03fc6e878ec2458f26f888b65a76c20cff6a9e893a5ca04b6cbcfe9d0a00
83	1	321	\\x12563e251df079f4c577951cae88965d74b14a9a4d92da9313d73d0621f1379af1f0d259ae720abf88943c37168491272fd8ad50967156e2e0cfdc5c21497508
84	1	395	\\xdd5b8183c391ea42970c9ec37f879a11ae9c5e98256f1877d7b6a0495556588ab162b423663b075bff3e635810a57058eb15a3b7dbd95c8ee42defaa2d670409
85	1	168	\\xfaf585c18654645045025e34ffd43f94aa137fe5b8ffeabb4b386dec6217faf67e7ac5d48601c414330732201a7803765f0f3b01a34cc414623a3df2484a980d
86	1	83	\\x986823499f2ff8187f6d7ef96f2bb6d4ee7aaf41f946076fa2f8cb2b4d7dd6204fcb8f1bab1c739553af4f0f7ebf7a8ed89ca9e5046c43dcfd175916dc1f580c
87	1	173	\\x2d8a6cbbb5e7d199a20d4507fad5a9b75d2e2c5f58214f2c442f030bcf71fdf01e49cbe3b415beca83f2e4b4cf5c4eeccd115357ff313222fea6840c55de5509
88	1	285	\\x5b691690a3feddde3ec39c1304bd7935b87ec66632bf76bce4c3d3e3713ad11ec7e79795a823b3b7bdb2d344182b0c4bd55cf395593c3483de358af4873d7e08
89	1	275	\\x4de3127cccb7645141a2869a478797fd6e29ebe1d9f3e2ecaf2808885e62375d9bbc7eb1cb15d81791b8cab95d08d56edb5ce41af84a2eb05a2e859bdb7ec308
90	1	145	\\x8429fec55ccf805cbc4b477b346a96348a57c770ba6f47e5a590818d9ac87252d2e5c16c591680a45c328ac7a43ac15025a5754430165ffc6690a20fc4476003
91	1	283	\\xf9953ef99e50569bf6ba37562f332dadea1cc88f6f412ee81c58e3319a9ec0ffda7e6d4e264f6acd81a6456415566b2a7c913ba943df90062d8f8df1a5428e00
92	1	219	\\xe5aa16807a1eea7190b3522b86ed21319e80afb03f671005fb476eb40d81dd13637b467f2eacfcad95cc6a4a7a9746db3655e419def22d06dbc49e31d4d09106
93	1	92	\\x41e567206815c2df3fa060c6b417a8b188ec6099d057794ecff607b84f726283c12795c6f051f8a5224cbd3e57c3ae3fac33294a297613791cdf14f841e9f808
94	1	152	\\x397208d0cf70c167397787d07a860de17d203fa51762e72f0c39f57eeda15057b852fdb9bd1a43289e74327b13c483a5e2d83d10a6e92e50d8220da5a09e7d05
95	1	192	\\x7808ecbe3866f8e873eb01d4d6f1a2fb6abc92cf7061ea2a49f33c4c4a96fd38000108993c87fc6d625b380adf9e93d74b9280f9d60803b17f16e8dd216ef60e
96	1	22	\\xd1dac570dfb45f28105715bef5824e16a3908cd395712c15b13e18aa28c639f653dd80b011c549f41ee9d7c8e994b6e61de90f0cbe48401f599fc9fcede90301
97	1	30	\\xb0755b254b0aa8814794a1c9c00acaae9b46dbd32ec007afbc78a07270b08283a4827158c006093acb8b201471185496ea478c14bbef3f12ebac17c215582a00
98	1	343	\\x85009885f58f39e656da6421080b365f82be14ec891479dd6b4233ef4c7ca1ee79544efd1070b09bf994cb1f5707c49fe0f36093c28d1257c577f6c984517b00
99	1	393	\\x4df796c0f511e991f4f5ed131bee5389cc690363c842a8d337ef5213c08720b6017c2ab3dd4d6164ca8a529b249dc7eb8eee805463401734c7a5af135693fd00
100	1	156	\\xe56faff516e6924f990eebafa60b7db2663f992a45a7c0492337d0eb3ed6b3ae17d07c82fcf347dd9bb9411645d47c7cdc89ea5e1a20975134f42a7a1005e00f
101	1	27	\\xbadb74c483d52d27ef77f4e10795582e6c97ce5fab389de60c604cedb6c31b581408a0acdbe755e254da1091ff714ac9fcab0ff8d286884bf7c74b00b505c600
102	1	390	\\x4728706fc33cdfcf71688d173f005a83014af480832aebd1e68f62464e294ac379a78e7a152e42bfa0f2254383d3ad428c73af8be62eba03a410589ba0effc00
103	1	251	\\xf1ffe0c9bca255f40e4e5d426f377dac34ab54c5169a3f94c7e28ce9e982c40b19289435824efd2a22945bd48f27b41ae7099e9ae1e39042116ab1874f3ac108
104	1	391	\\x36b2f69283c14bda928d92d9a77fdee21e23f63a990dff168430838a1a7a8c8eed4a8ece4e73072d5a6c217089eb473a641b74d39b7e0be97aab4325d4a93908
105	1	138	\\xb9e1fad077f36d717026604af4c4a3d37eb045fa90640bb1588f0a07825ce92e53e4ed33f6ebba53598a3d2bcc7044971b2d7961e30163e5a37ca336cbb6a60c
106	1	194	\\xaef0566d7019d73fc4b286286521b5dcb2cfeec3e25ab42b8ff5e0dc1feb1b1417bca6b1470050fcb1dc9d830a86f237f196ddedc8edb6d642d4dd0c4c8a1800
107	1	248	\\x22fe1b10422c0fad14c2f4b04e4de224e9d6cfb1925ca1afe76c91a5a4ca70b98876e279a04bd31c942ad68834852337b1ec62a576bb657deb89d3fb70269f05
108	1	273	\\xe7c1004490a1f918ca3d8c79d8944e04e0ae8831d3cc84ff3f85c45a50feb2b13de4161466723b1118f09f2063332407e62bdce6d64dd0122ace262e5fe38108
109	1	312	\\xa818f96b4cdc2c3d6844afd0d4cbacec4190447dbdca47b0ded16dda8c70bebae32c3ef737c2c928af5340ea0b7a5ea4f5979c1f44d6257105a48da13d348006
110	1	71	\\xa6f4ae52518ef34fcb4b90ce572238d8c6f099e8691db273985edf8ad1f221ad6bce3af12b9df633ed3a1a9599ed356fee21c47398cff5d59e42797838ce5008
111	1	101	\\x80c7b66d20f53774fd78f2163756a288ae32d7e7275a85dc8154b90476ece3777539828dc0e3e32802740ca8ac29cdc0d98a9d58e5a74cc58ab9937c89f99f02
112	1	98	\\x5b8a38280d614255a183a949b86d80c9e9c342087ddbc6bbd9bcf42a6da500a1226131435f41382529c96f606a1f7e144bf6ce73b54a709be0352b921382ee02
113	1	1	\\xaf0ef6674e6b39ab7c71f0b37b438e598163210aece8aaf9c29a97d6dfb6bdc15959d261ff8592593db26f85e763134dec1a9513603affc26e7d27224e70bf0e
114	1	193	\\x5a4abc57524749d612817f11fc9f4d050086b394768cb47502492027a39727b0e2529f775fa53cac4af12ed96ad01fbddd8be9bdc33fd03201a3ddcc57167704
115	1	123	\\x5bb5fedb6d8f7042731143baa16d5999e9298c0d8b644e26ed4c369f8bf68c2ad307caeb30aaa380a56471a732bd10a673fc9a2fdd46d5c6607e556e6e05c808
116	1	257	\\x5e02cf07dd700c035bfad3db0863ae55b48bb312fb66f713e25fe7575946061391d334fdf4ab867e98334168167fcfe8fb896fa060650499504c285d160a4507
117	1	388	\\xfb777665fe6b358f04fef31267e7442c07a7651e2a7ebe778aca3b6b8f1a9023c18dcc3b0e65bc27971eda4ff5978fb2a3e043dc785e558bc2661333b631bb02
118	1	341	\\xe85ad50d76aa58a2f0f2b5a1ca83eba682a4c78a6b5366fac755dbda38590a2f1b15ba1d47c4ba1222dedd5030f2387ed87115a15d6cec1acb5a39d23a23e502
119	1	264	\\x16065c50de54ec9eefdfaaf97cf531d4eb0a28a17eea749b3a13eda3922a1594ada67cff1ebe06ecd2d25d10c23f72f4210e8f723ba4ae5d04d1887eca244206
120	1	413	\\x10b5941ea58a8bb0de0890a89d98609e65cdd9a54dfee080fb05f35f0a727d984040ebf40e6887dc1cb3a7f8f80abf2fe19194e550b0a8e977905ea86d7ef406
121	1	28	\\xcc65733eb7bc84de94d4a9921524d84b74d7b0fd1112e09ca7501306901109a93998d369e23a3bff1673df5162a8ca57170ab6db45519104a08f2f2a8fa75704
122	1	297	\\xfae80a84302f1637fdd17e599165c36d0e094795c3c5d436f4901b10b0f217709f5e1cb9a75d46f8235211930c149d874f463110b8c0c5669166fe3d2494ab00
123	1	79	\\x4c718b49556fa50a97a1ea49c8cc2ba39a2ae6d1ddaed1c96082030f7c57da9b5097fd2f02811c3d43b6bdb66422c0f71ef73a0dcca357d2203a548860603e04
124	1	80	\\xe2f5f5b2cb82fc7a653a6839f46883c9a1de9ba534d376ccced8dbe729c3d5913b528bc831215f0d64fa0e89de500592c16e2feb03e00eef166e1258b6698603
125	1	149	\\xeb5d7374424673ac60f67e10fc6960d4916e9050495cbdbaf53b2afd111b0304884d36621219173bae5633e6caa157de91754da7b2022a6592c2d48159f26804
126	1	305	\\xf4d7acebf9452b692f741f1a62c8c40f5bf43ec420c178b8295bf0f679eddae441a1a61626bfe27205ab45259f7e7d36c58091594a18f5cb437ed029dd104600
127	1	113	\\xa72b0b509617de7b89c9170f789705b222a703fde5f93459685aaa55ca2858a9905bf28ee8a993a92beac798866e12300bede70c2efb27b5de17ec966b433b09
128	1	47	\\xb07ddd1ca31d81fb7f678c2b1d2c48966b07ba702a5383ea73ab82780793c159d25e009c8d48ff60de81e80cfe007a395caca48c139334860d10eb729cb38a00
129	1	109	\\xae6c2d8af45c41c7390cc33070c63cfabf8616202e32926bdce52079db06bcc55bcfb97dc999c4d0e9c8b65c4ff9c0d8bcf217ddea49dc6c532ddddf63efda0f
130	1	24	\\x2e84aaa17119f0173ef51405183993f4dcb28d8685ce8532551db0017fa89b067c09e60729c5b3718041eac4750e5a50f86e1f4d61eec1edeb4bee636a585805
131	1	344	\\x3254fba8df711aa4a48e8a46c17f2c3406cc3deb475b91bdaadc0ea3441da8ebd11a76c1ac89ca9e0daf560ce1beee7cfd146943fabd0affd0917dd4d2f45308
132	1	281	\\x002266d47cd1549a74459e676626f71b01ffc8a3ad49b8357d3ac7a598824cdd7f23c055491d00a20960b66f51ee8473bfc041ff623cf40063d07809a2e5aa06
133	1	93	\\x5c03ff84365ca9cfa6f9c7caaee712aa5375fb5ba89f7da0ab9a3bb483d0b4af12476a4a3f4678d4c6c95aed0996e72bdaea50b3900c98e34b05804926192a02
134	1	176	\\x7d7a7f9f6078ecfb8dba457e3f061940195aaa8f27133919fd7e3e0a0702d36a5c54f37135c0e6692deacd43dccbd7b278f5dec04059663aaa85168e9634d105
135	1	266	\\xb473b9c00096d166cdb86d962a1587852f2061414e90be2b76cd94afa85360ab2e51a17a598fdb380ddb2bbe37288344fa499c324fb18b0c2893f2765434cf01
136	1	329	\\x73546548f9ebcea152894cc716cd6df1d5470c1a61c6bf4654efb09c622cbd0a36ab1e88db45d30c44aaeb5481af3e2f245c72e89f10b92cdd8e9ab0121bbc0d
137	1	289	\\xa78c1b816948e40d856d9de7c52f10bdd96be962c239426e14a975812d2b0182ae0a8312c7630f24eb68a1a54d2d319dbb8f82f832a577f30ad8ec8e9e2f1307
138	1	422	\\xe110ae08e11ce541fbdf1a4df6b2e5ad6787e9ffd69efcf09a091de202b04b680777c3a405a8ec458136b0c7634e7308a9f81b8e8a91a026e8c6dfd6dcf6800b
139	1	52	\\x95ebd506b57ba2160148a9107565f3af51e2f0d0d06b43f39bcc3725cd55db6660b0a567e2646e9721aa6905b7cc7997b9d14d8b44b6cbacd688de8b7df0af04
140	1	320	\\x85d4fbf791b68f10c0498dd49f858632d1dbbcea210be88805d941195fd8e36d5a074895bfd5737b878693f92644ac699c267e12b39fb721776aae4268f9fa00
141	1	339	\\x9ab5e5a1a6f4b9ed0746e090e4ae1a2e23cdb0f8104588b7fe2aa645f80e50f71b8765cf1e49c96c72bf9ee054571cf3616de2dd5ba322539aa903e7f4759703
142	1	375	\\x04eb59025d536a3ae3ee31952dbb1b5c1baa9d28fbb304c6dbe579f6daafba58f7011619c2cec34942d566e4068cb78a49a6de61b68ca6efba407cb76921ef06
143	1	386	\\x431900ebb17d736c64ead8d0e20cebb046c553fc4aa2cdaa48f46e6bfd18a5dade4df9de9b20bd4319c2d7d37d0979bd588f97ade1ec53c83684f2453f3fdc06
144	1	342	\\x0791f3e2844064f9cd8ce13fa1243330d8ef5ab80b51bc4e6a415d48262639109022a917144785b756975d8e4374ea512b2657d3e8a3dd4a9efaebe595673d09
145	1	33	\\x75807866874f6c76fed712a96bae79c37fb2cc4a6f1bc5f734c138f5b2c582d7ee856a3facb1c53e1dce785d2a9c2ae2efdd6912f60831b9cc01d9451d5c820d
146	1	346	\\x68bc6c0edce8ebe8284c1c26bb9fa5aae39a9c2b654492b1ed281145030e6fd1a4dc4e88eba10b714b0ca988cc445600c78b3281ad70366900606ebdc5f27808
147	1	214	\\x5d17c717a2375c68d35415986971a06f5ae92ffa94372bf463fb67f7d8e7ecdda94e89f33998644f5d83ec90caab313d6fabf35e5901781720f93a23f65ecf05
148	1	201	\\x2b86f88ba64d43b64bf85d05d413ff14415e398b71db7a1c7dd0926a181606fd8e4e5f54ad67c030f7450c7705fdf25d274fa77fb3c98084806ce000873a1b01
149	1	209	\\xf3b642c5ca661a9bbc18a43629e2b11986e72ee0e22a8903dce49316420230b9e7896a86b6a43489398564b08baade49c0c1a41ae2e938f36ed6858ccc150208
150	1	46	\\x2eb35a3e9f8974b74e2f2b26f739bd0624a3928f8e2cab2bef58297553b24e4c554cc44d2c23411117dd158b21d3723d85314cbc06acb479f1e5bf67b89f1303
151	1	246	\\x19bb2eee2861ba7222dd0a2e8ff0f9f5e631c0382cde6209f336d0b14e98632e749c8801902d69ab0148813ac507e9274227e03bb78311e428c9924902aedc08
152	1	253	\\x409d49759f22927a581373ab42d7fb7d9e6185545a3f8aba829e568ef17014841feb7966f96bf32f4a29c81fd249093bd1837df212139ac7256a36d8f8661609
153	1	94	\\x3d804408ee430cc8491d9ffdac8b1736cdc0807848a10554bb0bda26effe14156e206892950d940253797a2603f6f638e8ebb9301064fa10e6bb6677735b3508
154	1	304	\\xfa75ff193917b88584ea8527d0c12a526ca0650e7f73a1378810368c93b4669e6a27a5e01cba7c2a6b8f55dc610692fc154e18e703a3b5350914c64268581f0c
155	1	161	\\xfc81cf1f00b2c0ff747c2a9bb1acdbf2a06ad6a88424aa5652bc69d3b29f728a3cf859c72d24e5c6226d4c563dab399dece177dafc74da6bd3cb670b71a01809
156	1	85	\\xa5e52c7637f24f8acddb73deb84c90b3619887deca8df1bcd8d2046ce8902ae3b3e20d31ca9288243d7029c7481e876bf015bf3776ba993e04260322174f8007
157	1	316	\\xefc2d9626c1a8d46a5f98b959cd81e16a48214c7c4497957fbdd8c96d22f6c625937e024dd891be22854e282ee72a8f73f7d43aeea2e6833e24f6e3c7ad3e101
158	1	376	\\xe80d8d54e72c3494a85fc91dcb2ffa25fb356e40c46210b9a7392ab22e3170a385e03a36cf871917f9c02d9ef448115fe10fabdeeccffa83b34afa527042730e
159	1	419	\\xe4ac707a25e7cf74bbadd603ef2633f25b4fc119b0e3154565d52cf9f040ff7eb462248a4010d51421ab21fca58db73e3ba3febe6744cc08c9042f11b97d9a07
160	1	206	\\x48f5793d5347845e1e9f62798abeb2bdd76c4c9af149891d862d525544b2b82020dd18acaa48fa351fe14ab5c6afe9822c83281f3b208a8e4542955e9cf9a806
161	1	146	\\x7aea12e362f96071ae8c2edc80bd9fd014da30c75f34e9811162695ad6b42e7d359d7666c552cb67b587a05ff13cdeb2a1eb3c8eb96f710d73552209b412cb0d
162	1	220	\\xb915672b3d317e5026376ce447483979f62c0f556e323b0aa05c910d570842bce12cbea15055721fc4d387df8fbf8b78a11e8efcd5a2d659bb63d461bc203a08
163	1	15	\\xb61c3dec8eb1c2509ec895a5e9987123a33315c8de01401f042e04fe49d23ec42741bf729497c09df3d04d3da85a8880ee81e77d4fa47d3683b1ed7b2dba6501
164	1	263	\\x9a97128a82de65699684e4074aa95604a8459282aaa50db3dde2329f23c1a32824614659297bcd2fe9da0998e9e132cd6159c32d9d1634336a9175c1d38c090a
165	1	262	\\xac6cd6eb109af3046b2cddf10328c1608ede962d079f81674d64337ff6cb04d6dc12e88082c34add87715c31d8c0d35adb3fbdd7b342464f2c48093148145a0a
166	1	397	\\xd192aca65d7617c84ed1d3686af9212d167e54b00f94693b2525f56c7146d57db4ff2ce290076f70d09c869314d63d113da9e5c6b4b7af79a4fbf179fbc04a08
167	1	236	\\x627227596369c7564019af9d3932c175eff1e667eeb4f51b4d42161fd57301ff47c82fa90657f12f097646572a4f0b26509ea8eff0efdb04860efefbac72f808
168	1	10	\\x235e218602bc92885c09c5db6fa93817649d24c3089cad2ac968e51db81fa3dc52922259e2261e20b0a501e7048f80ee2e0397213edb21b03b4e04440d986c02
169	1	377	\\x3c6fbaf35b6f40b9810459b98121dac77b6785d6badc92f08992b598069f8c6a30d86b6372d862d9a5931233c75ea3da4a84b6f09e21c7cb5b36dee65bcd9003
170	1	154	\\xba1f475c01ed6e2c9ed042de554e4de28b58d9c1906d51678e8a939f68c9bdade8b478b4cc89e5e348d3e7687fea12e910ddad490ac14e00f171bb9df808930e
171	1	368	\\x264df6ebe731118ee966b8cc4c5d36f69146b18721307611d06476aed6fbcbea5490f51f907286acf343d052b37d920a6d76ab28ea427e08c93fefc0f400f206
172	1	191	\\x51207e9941559924b5790c88146c58d717fdd56fd226805aeb0606997f917fba2c1e237b1728a2d6547f4a0cacf211a34a98dc1e51bc6359a41aae77c0bead0a
173	1	58	\\xd3e2dbe30149a8d685131ba14fe0700a7e5f1dd6b00c07d3dd6a91712dfe1760844a20624b43bdaa53815623e84aa243230cfccaf8a1c1c10ec563e40656080e
174	1	252	\\xf9591b34a8ed76b04c3937f725220d7db9ed06908939c7eeecea5a1e3cb4ff2a670768aab9f8c3143bae046fa0dad5eefc3caab5e6a4e0bd044c768fd5e9ca0b
175	1	119	\\xd27c1b01d38a0c8d98662d28bb5c78bcb286ecf73435a3bf521ea332cf67fedb98411a89a819db602b02ff1602bb5910eb9803520424ba23a18c37b54e3b2601
176	1	370	\\x8d1863edf15b94585715fba715237e6aba2e3f9b4b960cb8050d1eca3686f40d8c1e6b6780bd2974ab50c3f01e2bb88976b73dc3ebe8d1158e7c587b9d001904
177	1	255	\\x9af3c25831b56ecee19086493e3e9cb9556653650f4924932820c8869bdbc8243fcf605cdcdb8761610d53c5ac43f367c299c091aedc73b098a6cc94bbd6c100
178	1	70	\\xc246571efdb88d438552dfa59e3b5dcdf47e0193ce2e8d7dad550e7a491b76e7f6c9a1da30abb12311b8ccc98e9420100f9586e0509356999bd1a6066436b30c
179	1	286	\\xee86e336190d787b27d2c3bf67f0eacbcc8acd834c4cba04d1be29d9e08fa34d6873fc69fa0b877aff109097a498b62ca8a94a20f52e6a53432119fc385a5602
180	1	325	\\xed818eb7847861d2088efd9f79138c4d3f76a85cf007c61cdddcba9ae991b37a7d3449788ac855098c396e1b51a58dde260de587449b07d30dda4b9cfbda000b
181	1	271	\\xf64ff256a773dafcd53111f7e761954c1d076ead9e282cb0a16a8adec1e34dcc4bf7e62f9e13d3d3664ea5f794b6997e2a25e7c0cc737de3e10f81acc49f0c0f
182	1	23	\\x8cc015e8c38a433022efc705f731dd063bc816b9a6ad827d3a6b4792279b25457c375f5ca096bdc5ef09b4dafda765dfcb5d6f266e4a2cd66794c223106dff0e
183	1	333	\\xd5773303f672ec6325a981f375895e89c7112ed870cbaf768dbe5b1df93a9956453d1ce012370eb83818a0f4004467eb1d466935e1be55d13013a27261410807
184	1	409	\\x043e8954e00cb2e5d0cd452c6b9250623eb6242175901f3dfaf9157da3fa7413411ebdb6e9fe19da2cb90114d64efc8aeaf30ad33c938b489b7b9a035974ed07
185	1	338	\\xe15ef8af9d0f842ded874a932c385dbf5be41a5e97830fd7e51ff39f8e25fd115245596abefd270f18027929fe90fbec779772a4e0c51cbcbda87aaaff99580d
186	1	17	\\xd3d3e6a2f3a32464bcd7f20c0ca656b6245390f79fef7d5b5dee523dce3af2bc86186f79555b554c5fa37890db4a4f7d52ecd5e496aa9c53765fdf0da0a22801
187	1	8	\\xa32baec4464929fa54dc599791c708da348bf3b300e3cab693016453ac3ba764cfe1b3df8d9ac35bd5348ef224097dcfe14828f1b0de659ee829e0dd7a18c702
188	1	414	\\x859d94bff3312be84c8dfc4ac2510e3a3c6d52055958bd1f1c9c51690e9c700ac95040c50b3d6e90e0bb8c4a6dfd6e18e02393e456210b5c9d52eb782e282403
189	1	350	\\x5da95cc5dac02f5bfdcdab7ac6bf5d5d74c560693a4c29b1881ca7384fda9c3c7681c9a761a03fac58092da733837cb4059a6428386990fe4e58b6c89806f104
190	1	127	\\x9ec252758e1eecbe8fe6eabc9902e79a6aef963a40d041f85a6c7e855156f24b9d8aee47b9f9a26bd9e3d4e9cda06d52f59d6f162635ca8c78bdcdb1e486ab06
191	1	2	\\xa184cea754c0318a478f19f36113190ccfbd93e94dbae0014a88a93c60f35dd72277b90ab964c13a5adcd245c4a35c49f604293697b4dc65240e3ff99dd3c600
192	1	272	\\xd2f01c87c8475fdd8afe7ff74ea0f0073a0130c644cad25778c0c2045aa804fd216c1c955610f26e63c80f5f7cf7ba575778ae9c0bdea611f6b1fd67f6739906
193	1	198	\\x395f7c8f980aff8f4e63bdf38fdaa41ee0469ab5486d2f56bd31fcb05472bff79e5d8821666145a62bd871f801d9f9e9cec7bb6624f45328774680b7ae5a0801
194	1	369	\\x6b12c75f619230e083421fc70d184012ecde67f516c7f664e4b83a5a7fcd9b1c691732068b71d11e02b5acbace7b26d02bc1c9bf88cf873fc9f5e997d3864602
195	1	401	\\x95d91afb1bcd214f61b48c1f0db3feef0b462713d2d4ca04910b53b418e6ca9d1b4809a0b033e19b4404a2e1a36a957f7008b30e99aeb5e9d4bb67e43c11f20b
196	1	366	\\xbe4b74f6a51d9ab6a07ebfbd6b90bd86466f748862a75cb7a888181286eec517aff89f832f221e269b9b69a046c85582d83944206d5d44958b760ece172b0406
197	1	400	\\x1387bfdd272ceb9ba55d1e718227eb4a68e809db3400cf829c5f23601baa0fb3e3892c12f58d91609d6db4e7db6e68f4da402e78db09e3ca853cae716c849508
198	1	84	\\xc9fc2ec7ed7d8e7d150cc2c7cb939a2cb828dc7cb956cf13be4eec9777f55d30fc7302bd76a2faaf8e4a5c9b321855b5c95af421c6eb3a3023438ae0f42df109
199	1	175	\\xca8e2a2ba31759345dd737fa2b08b4db7faceff8ea9e752661f89eebe752d4b187131b32af3233d5c4c6ae90e4fd3c4b89b89581be4250fdfed8484bd6727101
200	1	374	\\xbac3758d31e73cc17f3d305bae1cefe963d8cad3ac85566c0e130adc3d250fd96cac398aa2c3781c2969b4f113c4de3d00c83d0f925ffbf0473d6a6d0ce4440f
201	1	417	\\x736220f9c09c15c52815ef819561a0fbb5f11222250b8e5d5ace4dcd9b1fa78024a81a747cde6745f5efd68bac54e3ccaf43cc3d093f6b42a52154e1fbe0f502
202	1	381	\\x23d91c88a4ae0d4df65dc085cbd1224412e271c84b54a7bd8e933cc80cd7eb03a41bf7da72d194c2f7f68685f55287fae5170e2dd70903256c3885b7c8564108
203	1	239	\\x4c8ec1d0c0529a366276c05c8a1140f5a3eae177b50d16a9690160d54875ed0c60962db8e0842a59777969f74836065fcbf2739283e4a9db25f863e02c706605
204	1	279	\\xd4cfcfcfc2836c9705e41f512efdf78810ca653b4589326ebcfc529cf2a749014e06327f212e57f5e99febe1fa2ec563571970e621a5a0906465a6f24f6f2601
205	1	274	\\x35355de28ef727a091213cef23b45605e7b40774c43795c5c5bf5e067c79351e9afc9bf17c534a1b9e423e04f086ce4cc61d2caecbb78cf81c668b700c086c0c
206	1	288	\\x41f5e7466049d8c7cb323e29a8ef66419d49574129708f5ccb4793c4ad0a8544728f4bc09b2d117db798e21d314c7cbe43c0b278a38d8531baba730f395db30d
207	1	411	\\x0c6528288f4239d17031e02e97b34d1ddef797fc4e4018fb4582ea8ccb61759e9b386fe9806dc69ee626c5b211cb4e247515846cb6cbddb890234becfc47e606
208	1	210	\\x09293025841545dd7eb9c0a9edeb1dff45b7976b703eeb7f09ab16196b3154339d224eadb0cc0bc05b5dfe426a7c51fd94582602fb57cb46ce3df332ca50d700
209	1	19	\\x326021d91b262180fd80e508938c6892fc4be5a9cd9d8fd84e38d649799d8083a49deff7c47fb48bc1ccf3a587a563dc21eb6db2cb132be9428b1f14fdb27506
210	1	180	\\xa051490e564718f6469be7d3eea08da78dd3cb0cd652fc1d75ea8eb0cc3915279f0a6ddeff5e6d3cf5ea6187b511220a9f8372e8e09524687b52f6a4b5e1850b
211	1	13	\\xabee5ae6b382da4d490e6aa928372cf8be526f236a10772278b3c8dc36dee80df92f4c5f8f3aefa8171e8c4925346168d776400c05181b954037d23c182a000b
212	1	111	\\x332e931c73c55eb043bb2eca205d1856c5f87be123eb871688200217072eedc301e814c12050e8a59eec0676b4f7da872e062a1535c79996aa8f21c28cad5100
213	1	112	\\x9f5438b0ba6257183cf2771fb58aa2174852314fe1bffece2658b4aa869b5e1722c6014b5ec4e3d195e76cc54b17ade0b8b1e8af31f996358594e62ef118a20d
214	1	223	\\x6714f2b2aaa63a18a5f194a1d1adf635b1a374ccff2b4fdca1e78d46e57a1cc2284f844d8898bb59461d50d0c2613c3ef85c131f2ed15cbd74ad43601707ea0d
215	1	39	\\x86a34f073c82680f32ccee2bd30d40bb72690c4e9e203563f4576ea8651a0ce2d5832a5c19911482cbcf717dd01bd47488becca7c981a975991e1239e44cb403
216	1	245	\\xcc526d6db19bb2bfc717765cccee731c1e09fbbcd261d39e42a35e3b92c4215e616777c9774d0d12efacd71df94a842d416b5e1fab7763f88658f7402f50920e
217	1	56	\\x70da0a9e779641fb7c0df8e7b11750a64ca4a8077b8db5cd8241d4307d50debcaa64e60fe1a954187d33f91da6255c9ba98e648585b34ab0178e31f73a8b5b0f
218	1	250	\\x6468bd6c21de2ae224d69e2acc9b53c04bd750ae2ebe4659c35c4aabd85bb92472f6758d95c81e6a08ac7ec0b4e981d43edec62ca019bd6b3c44bcc1ffcb380b
219	1	247	\\x0311ab4b5eaf90f783e2d1235606901bf8171b2c1cb3b06ee063e480c82a552761acc7803c56f75bf226a5bdc7bab61cdcde5082a1ff5265938264ffc1afa201
220	1	199	\\x96bb9795f8a50ddca6ca1c303b668126b6d9ebebc2e84d3780462bbeb6b7254df78028ed7bd4c74b85ddaff8a9158f95cb1af7538f53bbf043c2973161a0b708
221	1	86	\\x10a4988e50ad776144d85c9b508f9827ca710388ff25533e128c233093d71a54dce1cd7dee8b3da0232cfedf2d4914312621312f7eaaef530968da5114f73508
222	1	238	\\x15519b0280bcebc60d813585f07b74e6b20ee24b84f929753145eb59f3c55038bb3434eb3ed5efac24f57851fbd03b3c5353a4e54937b1cabb3cdefe36ade101
223	1	179	\\xcb8b1d38fbcdf0ff7ab6af773059a29dbb4ce625cc97d20d148b36be9ede69c617e4558cd96937eec9e5944391509edb888b83ca5669ecba0cd2d742e5593e03
224	1	160	\\xc08b50465cfd73220b1c4aa6b2e8984d686054e042897975ea0858403c924df97a544b40b029f00c37f98d7f5113493dbc5e05dc2b46a03f5db2840f9501d100
225	1	282	\\xe6ae46213a3e39df58680f75e85fd143a2dcb552846a1ed7ec74b9f795ac9f3c64e5c20065a843aacd8638c21e9c3723fac1ddc14e61e54d14c24b4a424bd90f
226	1	54	\\x2647d7fd1c770394d6727d2adc9458b7d7c12024c63634571305450b1113e9c70e90cb5d742f1f1a7cd521047374f1736ad0a7b78bca056127e97a17fa39bd0d
227	1	64	\\x60b050c5ed1f10ff6d18102507243b1e9c0e1489f35c1674b9ef7d79b00cabce971e761f6c7d25db29c4f1e2121c18c93f33a2d663f5867166d839d76d22a601
228	1	67	\\x473520e8eaa9efc56f744c1d43985ec9cfe35c0dd96ed718fa6a5ee6bf052ce9c550c78eae97d38e83d8a19d563c61077ac03967fcceecdefcb131375b709d02
229	1	196	\\xfacff46496beadfcb9e5dc5ea1a88c5fbb911f4f9859764ce211d6b9965d931e0e6f30ad682a1f38adee96cbcfc6545d27055f0e138a3a1bf2f1fa29f7ddd906
230	1	407	\\xedfbcd89a826cc8ba98ce0bc92a94c6da0607c3344ec60872b90c585ab2132c1b00fa3692f455e28314d07d0a9df5eb34eb813afe067e21dc7399faa00436506
231	1	133	\\x4c76c57758088c2f24a5e7fec9406ae9984dcb05ac3e154692d4bb86d38e7f0a7a726c79620875d79116c24a053735e2825f51fbd23a985454d0a192bbb4a901
232	1	340	\\x4af7c192d8820134f6e858270ba6c4f030fe05aabbabdf4e7d70fce77dcd4db5e115bdd4582ac2e0d7261e81a1ff55f50861e37112e6bbf5aaedb97ff90a4f06
233	1	313	\\xe574b4226ad8521355c04da4da6b82589663e3ffd5d122a79f079a8ae36d14d1893d0c1200580f6d74a5e3d62a80701698b6252c03180ce83dc0f0a3bbf1500a
234	1	164	\\xb88e5a80f47de34710080e0c655b7a3385729c233b218b6ec3c286bf31096a6ad99aabe9cff1e92f538e4e367ccb6106d5d82edb88f155a9e43640be87ff4f00
235	1	50	\\x5b8bbec0220c4fdf22d97547d7e02c6b954c6a1f6358208a9668ca48ee8b408b2f843879afe70bc55d8a40a99c31bf2b7c4a2db61240502ff643561b9a7d0503
236	1	278	\\x686ade333ddbaad1239ff90c7bc8550af6036057a35f7fd735157c6995a815ed25d4e042a1be5377fc0189141e8bdb95acc27b36053069cea3d637d89003b80c
237	1	294	\\x90a4374959a79d5bedb5a7cb8cbc3e8905905ed5a4327d2a9c0e65c972794923a9d4286d71fe12c7f01c46dcba77263c371112f8c3c04fb416c43dc0b9fd730f
238	1	242	\\xd50a09de58aeda0ab00cd801c7099b3c77a377d2abdf303f05c3d801cb45a7213eb7fd45958628eee8d8625cd45baa83affc1f723d4962524305b52a8fba850b
239	1	100	\\x45519d145f4b1bfb2c6b89845d4ce6b6412da4d249eb2d992e4a764c9b81e70ba4ba56e2dc5539ba21fdd58086b3b4f4bf6a8b9b036a6cf6cd3e2b7d1d544c0b
240	1	74	\\xc8ce7237ed2e1eba5385fb65c0282814306b46eb58e08d781ab7195f8e1172ed91f31391219713eb288b0f81f19865f104c4d6558e1466600057a0144460400b
241	1	234	\\x47dd564dda22ddf6f8d3428b7148c065055af13d5ad863302596a18e93274414f7ebe720ca78ab917cf30023e7fc614d2d33232ccdc827350c18116034cdde05
242	1	217	\\x93357e25a4e1196249fc0da67c7d9aef3f166447ea1f7ea5af4b360668a91c0bd7adc6144fcc98f427536bb9a67c6b415ea2f07db95016bd2a73a4ccf72f8006
243	1	415	\\xde56f9fa84dd52acbf2ecb5f902c666952bf3fcd3964cd9fce0fe975d10f8817c71fe8a2f1549323fad582075c171cd6a8d4477e74edcf4451e01838d0de4a09
244	1	232	\\x05a8f90680d6ae1d8d3ae161f01bbf55ae752f9561a22bd08cb92ef64daf26bc3986b1eb5ed1b771b802a3dbf849f244468e189361484426c6335760cd493e07
245	1	287	\\xb8dfdf83304e1bc51e2fcdc698257d0924b20f667701c4acde44173e23a8d00d63bee7680241609eb1ed77ddad7a1d08b74cc2bbd4e1c4fdd4752b911608c90b
246	1	124	\\xbef9f7c599948a9d5e0e0e05a34b4feb418eb74b736924091cc9df191bca33bfb046da93e8280496c84e3af1f58fcee03ebbf9b8f72161e414a2f6d20cdef703
247	1	190	\\xdb9a90d73bc935bcb1a4db9ff4a0b84f3a4f9412389525e65825885ef008ed806857d9b58a4406ee10511d99cc9c78f5e28129580602748eec5ecde3d46dab05
248	1	129	\\xeca3acc040627c8071eff5e2d52ceff2d622f1d88a2c0341f37f0b464706f3cb8cff6f50b259675bd376d96c11fc0e3f5d3323932d31ccad9195960fc9fa5407
249	1	14	\\x8020e665a2cb99fa9cbb7dfb0aa451f40b5897b5a14abac20decd4c3c5eb3834ee6dbd8b513c8e0c3b0f057f67ecb35761f80fff26db31fc5fe10899b4137c0d
250	1	159	\\x03c07837206f3994d9bfb506b5d820acd5b27e3d9778945a063534cb3cc3d72a698ca37c3640188920bd939a68077e18106896f318bf3a1c48b186a3f75cb804
251	1	40	\\x84e13ee1a1dd18f262e1845a7cf1d9e437f66bb1d0298bc397a06f57ad69c8b27873a5e9f39e3718d3c7892180ad5547779ebe0d63a249a2c4be35486d26c809
252	1	359	\\x20677d8e8cb6827cd3a4df1cf551812ea71c937d55026bb1f9a9987833d88e22edfa3ccb0d841d932af621cee62c21b620668d1391d20646504279e3a71c3106
253	1	187	\\x1c2f911f52f7dd99e9ec8c65992bfaf680a10f3e4c5b8ce4e0c3fdc2fa0718f9dd1b391028f8717abf2b3dfd37bd7e89510d38cef1b732bda48091f7ab6c0702
254	1	48	\\xbdc6d92b1a0d33bcf5c0bd6c80241febe164d1bf0d929d25e79195aaa7355c3e8bff49600be570c95457db14de2b2f9684bc0e8ad5211f43d4225d784a94110e
255	1	57	\\x0c6aa254d433cadeda4e8ac908b5df0e5d53131118638ede437b9b1b60cd2af6f8a069fb996ab8a67dfeeee27d5c3d38cc76246b74f926f80b3090f89cdf1901
256	1	254	\\x2b4211f01ff8f62188e9d62d09bb530a3f5b876d6be6b7e82ad9bf53ed7f37572e39c4c70fce711df646107d161817d01a0844d087eb7942221c6d8a9782f90c
257	1	403	\\xf5c58369614e239d4e9b2edbcc6d772423e9bbae7b8b0092d96d1628b4979ba128ced313a6923a29007f7151a8d99af7743672c8c090418d6b0f3d52ed7d020a
258	1	107	\\xd3891fe962ae2641319bdb0e1ba094a386914a30995999a2cd3889d057d01ff39eea74b3059e8ddd8caa756c3c465a50a343f5942a4a1537c2574bc702d6e306
259	1	55	\\xdab97049146ec3bacb902326c7323280b4af72d928f11ddde03d10c7fdd32a2025d4aaf8188717956d50bf318f792df2ed248da15a1b3d836d15831ef848f107
260	1	204	\\x437cd95ca0fd0c542b101dfb860eed528a9be4304a8e83bc859d7e8dbecfeac065bf77ba347d99d309eccf94526b5ffee7f8c1e909608fdfb277515441f6750a
261	1	18	\\x3c913beb979b22d8487aade0a841f0e7ae1cfb35017c3c388762a0c25b01ad5a85671937065625e28cc7c3067dca569dda8ca7924b7dcc3619d86c6782a4a309
262	1	108	\\x67190fb82bb09e60aabfd36ded68fb0ea6f52e8e8b12c83c00fff563ba0fec9a9253f0b6e9666cf991ec8c4453b433907c22613a51ef843003605bea8b542803
263	1	99	\\x46079b7b69f9f14196f4b25a0984d18eebb95d9fa97eed2e27ac8f5864e5810ba5a2127e9d0ab6dcb13656396288f1e32e99f716a55dfbf40ed7e8355bcc000d
264	1	392	\\xbe9008a4571f07ca518af6a5010a4e7df7d0926d7662530b52972607e475ff21b5010b462415a091d967c3f01c3ce6d08bbc1dd6c449f468026d269833073908
265	1	268	\\xb676a3683676971d19ccaf25b4c1c84d5ab0933d15b6aa724d5ba3042a150e657b30a380119aec440567ce716f97035601b88ffb9c153e64e15346e6d7d9ee0a
266	1	384	\\xe8b86cc2388f4385d9c9cc00c23bbfea0ec932a79d1875967d4f2303bec7b0f30592bc3a355dce33350da7750e868500dcf69ea0c268f6ad57dba40af517060d
267	1	352	\\xeb621fd268c0a24aa1e8a2e5bea077804d94e7a396c37bf7f56ac964fc77cb8182d54f00ea1682a47ce8c6de5e8e719209a8c198436ee43f48e57fce6452c601
268	1	185	\\xc180ef0d8baca914b21d4626c7e1cc85adedf7914be0efb7651b39f0e856b879fa54f9f61b08d357a2f556fdbabaedc2775559e1e750648de1a515a20d9b650b
269	1	151	\\xb2f6f8dd5b427e7c227f9a7a08f64b269439bce491a4af148b932fd61119ff98beff8ea27839918f16ec447ddfa9c8dbd363b1a88880b106821871de18cbfa0a
270	1	351	\\x706cb9ba9a4a5311732594424a6706b7fef36a0ef6af15d96091166e9f1f7dba6e4f2aaac8c366b3d49f795f20250cf1688ad95d6af3440cd2b255259845f102
271	1	276	\\x660bb0089dc8b18bd27569e1c683d90f66833e57f1012af0aa8b7a316d96995afa8865711265618de84d9f8312dc5139c143716e44116c5deb8cd2834e4f8a08
272	1	120	\\x695235fc2304e0e116d4383d79e4dd1eb90b6769d75203d557f1839ad8c0eb0571ab0b15370a313ee5648c9c89e57b8046779d74201f0439043e41bc20b58c08
273	1	183	\\x94b83925ea20967a758d6dd4676e4f4d62bc0f6ddb68a9373774dec19f12746e6d8bb244b2d5509a834916d65e4bbfa265a78d2dc802d1ee56eba688b381890a
274	1	62	\\x7490f9d5c830c883e23b1aebf3d715e9821e065d46bf672c8a4b421dff52d39737e38ee3fc2ab857550c35da65ffcb0d24e2bcdb374820c235183eff21510103
275	1	32	\\x007f1156fd3f52ded825c675598023fbf1b778048af1697353d20a6d6deeb950d6b17c17e925b71f944495e40478324ebcd04537a016fc2ca48cd24af470eb05
276	1	31	\\x98b5295a3dce2751ac23f93fd57fb565e877c250e1b7ffa4f7380437a695f5975f56aa9e9f4b0f0371209478e594d33c76a3ed4b57c757cb8351ee21f4b47906
277	1	68	\\xda697adda66b4eee7f958c378f82a4168230866a61ae6854afa06592136ac611ae0c6874c8bc0e61cc303ca97d487fd962ccb2a00490479a1fbea8869d8cb301
278	1	408	\\x46de21bc60deb05188f7ea6906f2c056ebfef08c6d892fd837e91a53b1ec7e7ba54ad7ff7f24e87c7ccbc1c521f072716d35311444d2d0d27b4ccb1fb95fab0b
279	1	106	\\x6cf575a6f8a80a53e86d7a408156ac37e4a7cf1262a60f089f4b4ebfe6be3a21265b267956a12f296be8797263bc59c0f4b0f405b9e1dacb53c13cc625285d0a
280	1	91	\\x0312e0c9435a42feb682306ee71b1507eb592d4a2e9159d60cf269e6ba694818e0017bf350818b8d61895752eecca2a9d20b4410bf9ee09813b42d00fd96e109
281	1	361	\\x790197738dc212cc241195d8d4360dcb758f5744ac7cf0212445ca7705c25e9a1afe636a33cc54229d8035827131f7d54947f56538752309a7f380d6faf7c302
282	1	243	\\x12f566b89b2a0aff650dc38d3e93dba77a4760833223017a086d19b89f7a91f59379bfa35947a2ff8f61ddf385116269b34685d863d32c10ae7bc71bd4ecd805
283	1	387	\\xef697dec19dbd4fc57a1821f15646aa9eacce5e698ca5fe958a8ec964656762af28ed5ece69321c7a4faeeb16f6031fa76a192e703b8f217dfac2ecc8543da0b
284	1	235	\\xd30dfcff50258c79106b8c3b988e47b4a45f90bfc2ca6a1326d1802b3883336ceda0c47fe8be82dca8cac3fc46489104e5064fa18ae8e35180092189e34d7908
285	1	140	\\xc4dfd594fcbb66bd1036300e0865bb22fbc9aaf5399bb43057f3bb71159e154c7d3b8ebd90f3524f3bd64a466f9e384be4d8392b17a444ef404d454404537309
286	1	38	\\x111b2a24d1dc0d1fe25f5541102a6f7ea466a9afdf095c51c019874f801793848abd5df33e220671cbcb51eef4758c3d28532645f93bb01d35c66d891184f20b
287	1	117	\\xc5238a38dc27ed614b0af2f6e150f7761e94f54c399a2f34bff4c2d4e91aed5579bbd7b775392550243f82ce6850379360da98b045fea4c77b89bc9c31c70f01
288	1	405	\\xec8dfded4eb79f485587b5b48aec70f48cb7abc0f41804a6d05f23bb82dabea2ff844b419492ce8eb8fada39b25e782e21a27815d199bcce1435897d263c000b
289	1	296	\\x5078f002c12dc0031454720acd2d3937a5ff0c6efe72b9da88aee04e28da386c5e51c235ac5325a772465acb1da99f040dcf384f87db673f41653d2459d39a0d
290	1	172	\\x248b3c4ae23df779a106ed28dace91a60f3d075093eacb81ff0190ff85ec6220503c3c25e446cf68be28f1b126faad1b2e481ea2725b55a0e1288274f654f007
291	1	171	\\x10abdd481c122d72b1754ce04a653b88290f2d7a826321e1551b77f5e40fe0e1b2dd8cd5e8a37b2b26c4471448a7dcd53abe2673be08babe9bf99bb45a59fb08
292	1	379	\\x96d73ffbc554682889a49c907c0758b79278b4c81d93a969901c4da413be61759d204d1b4a7801472eda237e369e605c6073b73551f9de9b7b9a109965129c0a
293	1	394	\\x5ddeb7d46e3ec83b55c37069d44d2213775edb3ebb5766dbbe60f07b91adb66e735edcf22814507399e380b6f46693eddbafc411d404c7c1b185d5de814b7f03
294	1	364	\\xb1d582c491fc7ce6ddbec254c4847f37656aa113862c9565eb0d4d8094864f295e17bab13796ea073ff8ea5c5b5ebc4c2c10ce9564b266c911fd0f5548d3b404
295	1	215	\\x90f64b2f92df1ff64382d40c2164f827189320673ce381c03cf8bd891815e95bc30378dcb3c5b1d1cd655e0b29a2c16d13bc65421f44ab90dce66605cd21c708
296	1	412	\\xa7c5c268ad653ecf9e61e3f797007b62faf939fd5c761346396fc36178ffd0d07f2793de51b8d3534049cf5c5f8f8003f06aaa1a57ba9fb1a279ca05b8073d04
297	1	116	\\xf11e4fce858392d3bdaa617ae7cd6cf0cf0726330cf33bde0be8d420fc30d10db92a52fddad5ec507cfcff5cd0df1cf14ed7996ba5037ecb9c8a9b6459a56808
298	1	240	\\xff6304dae7070182af09bbebf2f89668e6682f648f33ab7d6a17410e51cde8b60799dd2c92ce52fe6feb50aa657528ef2f36d0489a40001d402f5467bf56fc0c
299	1	153	\\x00fa3a587a239adeaf966999c85acc49b0724ec81023dce9ddd84c1c8d81df3bcb381ed9a9a009fb968ee6788d77d07b9e8a0be325d7c2495bb48ae47abd260d
300	1	295	\\x8263f39112d371b7f2978d17119302de36cad00344eb500c198d153e5ef36b8873fd4fc33f510bab5c0a7ae58a36bfd875b2999595d302182ab5ddf569edb90a
301	1	6	\\x316ea535e9a6f65467f27aa60fab2c59e9b8846e488fec2c10c3fa86692544c5206dce4d33f8372c75936a4c38d317a2fcf0fac0da55def6fd2bb7780007aa0e
302	1	348	\\xe2688a514962e1f7b4e5b0c6b138278d884acedd1c2443ee235fc1acccf742f3181572c90c27b6cd4a4c867f4f2ec7ad2c5f673ad344e595dbc92eb004572709
303	1	335	\\xf5529b0501bb0228b09653242c5a53a9af71045cde64864603ecacd11f572f545976027c51ae120cbd96254cb8ddedf16cdb591cf66a53c1bc6bb830baafa705
304	1	61	\\x6d8aa1696c527bcc85de5b4ddc99adbf05e3760ea01d355bd7a6d399255623f7dcfc94fdf852b9ed1134d0301f42ad0b5a238539dad7bd6c1d9ff7dc74d94e0a
305	1	37	\\x567c3d91062b4c957a605465e139ac543a4252d383a8549769be43507808f6c82f084dc3778b90b9165887a465f8d177fc91c545f26919b716fb765e3db5370d
306	1	142	\\x6a128658dd445f11ea3fec96d7f796d880ef8781ac44cb62448f60dd62a79066cf7833f8efb30bdb942d8f232d60b52ac54f31653db9e66892517558a6049e01
307	1	314	\\x177f6b49a20d80e2bd5e0a4a8ab7038235b7aec45335c7356562a57abbdece23e36a98f1030b01dcf39a7bb2c5ebf7a7155929d76b3eb2c85c3c809512aaa103
308	1	36	\\x922db48d9e7180f9d0acf5c6a51b483bf1b8190296f7bb83473162101f35e39ba5fe5f948929bd2f7095415c1064101d851c5ae29eb525e2d54b6c62db2cd004
309	1	353	\\x0954847b5cb91ec359212e60f8303fff863e1c1e2fecd7e8c7d241b1fb2159f93498b9e351932864593cfe43532815484fd55bc8d2879f0c537aa5ab6fa24a00
310	1	45	\\xcfe46ba53eead9c6a29d46c11f4bef485959fbac8f9dada661f3c33a2e2c9b7b11308698aaaac0492e5e168b39474bbfb14db3f6fc57b515c1d648d3b1af9a00
311	1	81	\\xbe371e0abf0c7e192d0569a94f300e930ef8c6fc48e19a6e15b6448e7094935609cc6d0bbae1b86ae43d4443e4b73d4576ed31cbf83425506c3fedfea3f0840c
312	1	131	\\x816011506d847ad99f8001f04fc744c305feb5a6da8db1c5550502f942ce54e6330c593b845847102fc96b5939504944d72c8670840cbccf8f67a26d7c0eb006
313	1	102	\\x57b1e14d80e85ec2de78f553c167c25656fee4fcf2df98ccee87eba7e3f4e361e9e26ec96b376b33641656082d269c53f7950ff997692774211a989e56d05e0a
314	1	355	\\x2e5d285869a7f103edd2bfedf998eb2fa2849437587630022cdecdb4ea2b8f2a86e9b0e576b6450ff4aef67f4ab455d484c434c146c73d748e5bef1e0cfcc80d
315	1	363	\\x6125d08bf352b4643d6af2dbb60b2729f8037ae937e5c8b13f19974ec6dee90e61876c2e9657744920e37ce2bfdb6667cc0cdc039e4b1a8042411cd1d7019407
316	1	121	\\x528a0b1b43e11144311314f98ba33729ec47023846fa9c3f4dde7d9887a5abe12299f54bd9bbc5378dcf249e76cce309942a9a97ddc9794044d190cdf29b0407
317	1	423	\\x9fb5d76dcbec710ca81f256c71acb5dedbbef2b79dddd21c2905df7044f297f9b65253b1931a200087ad4ae38a6c331baa17507ecccaabb908d8143a6f5c0b00
318	1	229	\\x78fde533554168cef1affda3caa96520634d0fb225c0932746608e7a1f9de28bf5ae28c6cb66df05f4cc9d80e3e3b4aa3dbb0f663c2d5c1a583aca76bde23304
319	1	155	\\xed9539a94d09b4c783c27b04c4b66c5ccaf6e8a6f9059cea69928890f80d55d158abf979046d814c555f819687260470a9589a7fafb8bd97829f0362e11a6d00
320	1	184	\\x6aa0f1dbf75622e8ae76736932ba23ad1106bdcd8703613b81bbf4fa21ee8f9875af5ed4b04022ad3ff095bdee4e769d4838446176d4be6f3bd2c4c4b4123101
321	1	73	\\xdf44f5b2b484890b90e603e991b6714beafdf321691af21db6a20b1f9dc22306c09d11541b3100c2cca69ecb66e5935cdf8aca5bb1ae5d5e377aa46a4d1bbc0e
322	1	182	\\x61b113cad0c104fcb7d2ba7784950f503292b287b5ed90ac88dc5a493bcf9cb23dc81cca5749196533d666ce2bf4bba50737fa1b285da1029af2fd5db4db300d
323	1	383	\\xd8a01abc2239f00dcaeea37875ccf57ea90504c37817fad796c5ec84329ee3333585f449f450bd186042b9ad95bd0c0a6b144e438bcb8db0cfd05ab910ffde01
324	1	162	\\x5bdd2797d4fbaf06310f4ac4aa32c4eea5a8956ad2cafd6cd85bb561891bd6c22975b5a4b2e65955d0150f03c004f12a38c31731243a5a466c30ca60156d1605
325	1	323	\\xe9ac86a7c1c5771d92724edc7e9828bef731061a932577f341750f6e5c04a77f61668a5395e0f2055fe5a9f35bd785b13e968d2418d16fa6530d6322c803880a
326	1	225	\\x18d6d1760fb048bc0a87187c88f33aba56eaf76377cc6769d58dee4327c953017b7f0b109a01100d4e6e6628d1ae091c301ec0376ae6686a21245c49d9349e0a
327	1	77	\\x283c2e0351321a09426bc76b2b6ffbec73fef41713cdc0c29164d55afc9a859249bfc866144548858dec72009d1c7f4039a8114b2e36c96d3f67de2e569fdb0e
328	1	122	\\xa4dbcfdce526c05e6275078bb9f2c1627547fea9267006f936febf8e417a4701381d9147ddc87fa9a372483e3cb0252bf9e26ac0fcb07ad7e507f39d9c4bd705
329	1	166	\\x8d58cba4e53f0ab5ce77b834b349a4c1fad6b58e1614dea27823d38f57885724371aaf88e8e78d59fc4e9adb7cbe96147a441a9626ff0a96a057a734d95df80f
330	1	41	\\xc96deb5fac510bc3965713699c74b390d2815412d8680dd5121a14ee9b47567aac96d2c6748dea6b2acf4b2a6ba6868cb217227a6cf173e77cf5c4606c19de0d
331	1	141	\\xa2e2bdd7e288f43cd6988ac0a57b05868fdc4f82367f6fea85795c8ebbf1233b213382085b5cc5af6eb14dc6b5a7b7bf850fa9855a69d131d4dc6105aba63a0c
332	1	207	\\xfbd717c9af81a8476a730c18c4b723cc993a3edac0e000149ed71d109da1c9d0fe05bbdca3b7993ef5a689bd462683ce4e430aed122cf597b88cfd1db002060c
333	1	89	\\x398ff34d43b23e3b9edee8c2a25a4204f06d0b5c8cb1af4ef866758f17c7a0d843e7e9e1fc29660a0150f90a95c8703efd8bb920a832847d06620773f3211d0d
334	1	349	\\xf27cdc193888db034d4b2c72a2bbd19a1bf8be4587052ef4cf5fb1435df95209c811ff42f1e6ae84aa8c8897ecfe68de7491598e04d838f64a0656ac6022290b
335	1	53	\\x0a822c4e23f2b9a7cdb7689f0bce793386af36795075febb6d07654b41db4d93eb91318137cef711591cdcc15f5274243b4317b79a448c79124b8388eaf33d00
336	1	233	\\xfc2e8c5653ab8aac71daea589fef31d9b602218e16e0c3a03a1665fd18801b4074332a929d162d7282b7f21662955f678a2e909bd2338c62d3b4af8024a40009
337	1	244	\\x98f73274fe2e444d5cb8abcffa90cb0a9d8624a32360abc69703a2d9dc236fb6d20b7bdcc8fd1b50685a85c898a32d6e6191f0f7cfa027368bedc154c0075506
338	1	277	\\xe093a4800b1f63edbe966f0368da1836d96c197eace56cbbd69ccdc9cc7c638511756e8225d8a72b9ff448a315e3827d326fbd90c28d0de5c1a61a18108d9806
339	1	139	\\xc9529508e1c6bb3a8fe5bec366414c73c6969f12543669eac6b4cd79e8eee22bf96fb6ec5509d24f5832f93decfcdbc7ae43f23127e9553e3f5124a22c63c30e
340	1	300	\\xc0f04a21f138be651496da094c0d4a56581bf2d874c82181d0f918f03fcb20078df7ac3fa8a3b32554f23ce9db2f4f28edafa925397ef4a3d88895f39d17c90a
341	1	421	\\x7b4628895906924b94e6c3a836bc25feff2ce96109c132812c6cc0ea86f8d998fd8827d2b70033de7897530c5e514b5f34b20772ec8c8dcd269ac2ff88ec6205
342	1	177	\\x6b82ed7fe0aa05ba4f1e021337a9f20a99dddf5db739e33c666c3b41bfc588667cfee4db6d22d670920d3bc720de1f72376a1c3078f61c0e7f0729e14a9baa03
343	1	404	\\xd6aa49fb38ea56e23b9c267d565f35e8f9e562eee8a6097e37cc10775ce1d5ef76603027fbee14a05cac7f8f483d7bd19471af294c51c8b6a8d8d70394de8805
344	1	309	\\x37d16491fbd793a7459a8887f4c0c7dc76371452d1c91e3b17a220b6618d5f9e8f79f4d6713197665da0790e5db1bce21353d7dc4a7ac34ce790a785b8edfa00
345	1	158	\\x848cf147c42b2c6ef57805fcc9baedcdcc741d75bfdc653d8b732bd1de478da51eafc8fcc568c5f240a6789fa62661931a92a5ac60153490438199657d300309
346	1	336	\\x4ffb673f798b536dd7e82ed4a12a22cb9db438d4b544126eb9a1f6ebeb653f5de773fdcac44b7448330303d7bac716c65d8a71bc1f4f0727b177d13b9b715b05
347	1	420	\\xedb094f0ba0346a3d0f4d7efc554eae568582defe5d9fe2921cc67af3ea2f9ea101b138204125854b6ea375160f86a568ff322abbe8bf3cef44bc93f5bd7c909
348	1	174	\\x657bbe0416359fa22b72b9687dc3c34e00493ca790cae020e9fb99d7bd2a0f1089291873f33a9667d20f4eaae2456ef89c51e5b08df3403a2055e2f9e00e9a08
349	1	181	\\x9bc2e0d9b7d3fb05888f02665eae2fb1cdbffeaf56a7c497f4d6313afff6e34f6eea0f8db222b9360dd843101b70aeec3688d6579544935f9d00360e5385f00b
350	1	150	\\x51e86b57e358475a995bddf2ede17162d0ea55b5e7b3825afbba94fea01d26dca9d64bc36aca76810826632333073085ac74962d45f3ecf92fd2ae7ffde42f0d
351	1	44	\\xeee181cbac8d0099b812e62c3aa6ac1e9ac24d4420b066e8b987967ffb33aef51989197f1e679165a2094a979a7c0a2b3a02a8041bb8f1da3cd91f1ff4b20f06
352	1	144	\\x7d9165311cc31a5435bab2b9ddd25c95276a4676dbc0d61cd738060ac69a202622434af6cd887ce16c687dc97a33cdfef32701297c8698085c4223da88994f07
353	1	169	\\x324197f55ec70bc816243d77ef65e1d0870ef9b82eb1c7bdf6509a202bd30ff69aca4d42962fc1f28e0c74454f4c5f9b8d14d53985d75d2ba763ffacd5835105
354	1	258	\\x376d16a5d8843641c108504c725d571f25867c34ed8e29a8fad46511cacebb2cc04f77a2e0802064911cb5dd852953a60c1641b37be4dcc00661fce4e0205e07
355	1	306	\\xad2014d6b582e36420be53c64aca7f81ffce55f0d76cb565d9037b7ebed3a5e196f8d8c171f1a34ffcce4c16f8e3c9440ceccc0c20415395c47fed7d5c6dfb01
356	1	418	\\xbe141b06b2fa208f4d4241c892d90122e78a94ceb556358490ad14eb86e95321cc47952730168a0035c9819fcade9ea1063ccb24fc37afba7ee984c5d2c1220f
357	1	410	\\x00ceee4765fd2aa15a1ebcba3eaf595fec1cedb857e3b3eed31fed70d686a77772504cd1d4c22fdb9ba46095ae8fd2cb7ed923c4880bcc1830a51394b64b710a
358	1	230	\\x28797e5a76887df804afddd26b9af2ff9eb5c086e94da98800134a797a0185b3270caeeddfe002738ca11f01c0e98b4012466ee06b7b946edf2b2f8abe870905
359	1	362	\\x2896d3ff9670e827299748cd9b677580751a7f703abfc03718f0be917260939ad0403ae2b2a6396b94e0074a4753355fe7f5e70a10513f1a98f0e913085bd90b
360	1	327	\\x93ae6d6734fb5f2861d6cefb77a02f1c73369365494d1e95293271367cc0085284bb067a9b3dda1b086db9ab6aa7072e759b4af7b5e9999a1eeed15ec878380e
361	1	298	\\x1d16a54fd5d9233c148310d1793900595085fdb10b35fe4c8db55cf1c879d8136caf2c15868666993ea46946659f77bd369829707208fcba535624f9fdd90f02
362	1	237	\\xba5801ee28f655aaadf253add6447ff3e91dac03b6b8ba7ec865cb9406af15a42539e0048c7e85a3269f61422e6b00bdc2e9fc019d454837498487c803f46104
363	1	311	\\xeb596e7c3acd74ddd97f5c4cd2371a2f6d406dffc5351e358ab319cc22326b4f214c0b3f3acddb1089fcc13c6eee750ec0fcec5efa3ac92db8d27ac6cac49b04
364	1	222	\\xe63ad8b6e9b23e580696f62af130a45e33cf932d43d1e8a409c519ebee058114562c4fe25049bad12b9a4566f9bfd7a666cf24a3299dc0befcf7c1c4126ca30a
365	1	365	\\xb6160327c78bc90c18bfa3e0841a3e78ef08833f9b658cd531e9d6af082a655dbdcf6ee56cc44c6353660330161556dac58070da060ad68f3010788d01513a0d
366	1	115	\\xbe0ec72c63c9fb61e41106b0425bee8e393b47222de287f0299bdaefe32a1be12c4ab1c400881e673a83d8696a8e136c85b4d6c4bf34ade991777c486c03ec0c
367	1	34	\\x34e569bed6801e141143af6077689bbf5d55b6cb3c171689579576c0023dceef07120e1c29f3266ccdf4c9c1e5b990f23ac25cb15a5e33a2ac57525f7a96fa08
368	1	382	\\x45ea454744b9b848dd1af26176ab83a610e4623d0a99e606903ab2f75b9fe12d3ddf88ffa3dfd21f4f111f1c82c1f06a8941f5e05472c4f4c85ed8d86356c80f
369	1	26	\\xb2f8741fe30f6127281a55ff9299a0f3dbc968c37139795502a78ecbf4bc0c41c8873f3797c7cebcfbc9d7b8aef7c967d2313f6afb202243087580ce2458fd01
370	1	16	\\xfe4680c158f349e11949ad29751fa53556dbdf2b85d633c86a89dea89c068e19148068ba3b7f7a598872cba5b7ebb3ffd0128f53b9c460d2fcf873a76fb79f04
371	1	380	\\x2a14744f05d4b40fac691140b703b1f31bf0bcdf3fd97f089bb326bc45c9f380c23240c5b6deabd660e0fa460b8e39005970e89faadf73a073cb6caf9abb9e04
372	1	65	\\x3443e030f8b02d5754dc0b5156aba020cb0a75a1faafad55222f4a04ec93ce1e990667c6b1f2e42e5593b18180077f23b06113f44d229aead9f309e9bc0aef04
373	1	186	\\x7fccd9ac00efa171c8c0c573e232e2131f6cd6dea3e9f3256128f09282b000baae6fc0b2d207f4acabefbf4be3fa1eb6111fbac73b1fc0338319d66dc02ced07
374	1	12	\\xadf7576c10e9c725f332968f667d55ad622946d2e508cb5e1eac3935e711f28cc9514e9d260d0a693b1f977987e3befe5a919366cbe61cd2a5a54c89a98a5009
375	1	29	\\x8deb14a69d8126abbcc3ea1d77ce7028f2ffea1921a723ff84bc0c3f7e60b1a344ebbcde9fb8cf97fad8e855b47a212c1f06000d5f8254e8072538c0321d6109
376	1	337	\\x6bcd0f4b764d0e775f30581590be697ed0ead94b20d6fc4d2c8a8c8aa8d95242f532f4b1b2459854302db224a633994cd6924c702bf9df8011475e8a1a78a204
377	1	205	\\xe7f2e45e213c7d769c7c093214267d29652b71c72c977f366b58a34d17a43863753cc8ca8dfd48f44d9f86d1a3cff452eca36dffa1293bd04c7a72e1b3e30d08
378	1	265	\\xbb69a65d59fc8e597f830dc51d8b1d27b994998c0f16eb6e5baff5dc9d638f84772b361abb8fc4468fd55115d12449cf96d62d80d9f17b0f50f4c8e770ad4304
379	1	319	\\x285ff2a24474fd6f571adb16d669835fa301ae7f373559cd77a0d73ca3e9721e6d6b0f82d7e6203b9ca0db7a6a6a70892edacb30eaf29ce3647be84a285c9d05
380	1	3	\\x63a238e5f554eb56b2efffca28cdcd2c379bb7b6d9673f9cebb2bdefba83b1800266f573a7604c70245eb256f7cc68cc92f34fb3a1d8c4a81debc468e73a6d08
381	1	416	\\x3165a907fba40efdac313595d9c88c45fd81b7c9c58261aad8e6dee4d906c0df5bfb3d97c84ea255c9b3482f868a4e86d0f1c7bb8d6e81fcb7258d8a37fc0006
382	1	163	\\x46a850907e2ab20c5ba95ec7fa50019b328251fd788ea5977f6244d8e99c0b47db643d5f71b68212130038f560caec07e09480934369c10d572bbb4705efb208
383	1	25	\\x2ce15187156553d2fbc3fa2c9d2bac04bad2af3b7471b11e9ed66d645eef37f8f9acb2ff6cb91b1fd805d3e8d6753153e7ddd6f63493f1ff1af31703b7bdf10a
384	1	42	\\x746ef44c52acefc09df5aec3f99d34514cf93b26544e194274c5174d61eb9f52b229d641a51a4d0edfcd2a7451c77072c2447a36354b3e38e9b5ac994adaf807
385	1	212	\\x95b1a424e9601ab9e1ec5fca8482534bb7cbc3bf5be135c10cb1968c73712609af35a2962c88f19813c4ab70f6d396d1616ba7a417a4234cf7f71dbe036c6c07
386	1	110	\\xf5b02f8081d21484a48b97dc21c10706afc4774b6d31f19db4e1407d40f5b464f4daa327ffbf827ffa9d0f19a977472bd210873d9fb4d83a61d1d77f74a98d07
387	1	147	\\xe71c907149858df258b5bad35f621acb50fac41f2ec0759242e61ad3f1718680bb1e6d197111e38e100d4e594fdc8407591fd850935b29814b31d3455785650a
388	1	200	\\xcb64f558edad65dfd26a15b7d254bc11a552d41d402b25c2e476a7fe94eac54c739bbdb2da1a45e9be11aebafeba9c8ae654fe5665c0b83e131b01c6b1ba810a
389	1	126	\\x4989fb892d10a6c512ecb1a9e142d717cb5ef29a940ed997d52933833090a0a21044ce0ccab8381ce193821679971c01f1a127397eda0f6a48f1eedd14e4bd04
390	1	330	\\x18a9d73a3d2c919af29f26c68572fe20ae793f836bbbb9d25e47876cf9f8c5cac19a03eb11078eea3659e8507016768e19f90d9c063104e097bf5b29b3b60f0f
391	1	259	\\xb08b1ebaf21474911c05c01daf2e0e7d656e8439ea0bae911fe79f5a73ce80aec1ed583abd83aaef0f656d59bdd28d2ffc9435ec4ba0d097465347f0d6e53702
392	1	78	\\x5ffc5a5a906135f1db7c19e0cfdb897f7e0386dbc68b4d17b980af3ed583f103e63317f0db8c02e9ce301476fbc3142fe0ba0475c3578a8f94c9aec98781d103
393	1	202	\\xc20bd2e17f2a35a6dcb6c959bb8f70f8dc6d32041203ef3c1368e4be297c417ff20385f863fcbdf5b8ab168909220c9944893529f1f81b54973aeeab6620fb03
394	1	302	\\xd1f3dce468c60c711e24b2cd991c0c3c480398ed3fab1275561cc13ef7bf9bd55a196c6c94cc21b8471fcc7ce717fc78fc4ebef7d1ce12bfc822e98bfc60b30e
395	1	299	\\xfe84a0fa32c85c57431b2a9d514e6ad40908bfd6cbe8385104c9edcff65ae1c4361956086a635096d56d6891f78298899db30d76e9c423f1963cda6c6859a609
396	1	35	\\xe07f731bf5b59201633964e2fb0d975d44a61616063d682d12de553499773625f82abf441c12d7c4b74544348988f2f51a2a34a0d2b54b0472819ee30bb40a07
397	1	135	\\x9560d33b0f19cdbdd375f65d85e54ba7324c4755d2bb339dd1384a7c424e46abb23f86f8539041c870dc94399dad5aab1420f4398817e5ea5683b29fd746c901
398	1	105	\\x0315f9bce8cff843edc823d474b138db08816f406bd7fe6152603fdd70a70b3203b4f108900428d775c4da019b5f77b74ad08359d192366f3999f2334d6e0a06
399	1	118	\\x695068cd675671043a16f208a8ae8519748eed1a1568308cc6390264bed64ce4d962a303412ae3ca70b595180674833d87f814fb1954d3a53646d8463711e000
400	1	290	\\x76ada3c37c9b3111aa00fe01d71f77d16f540206da058bd3aa80768f9bec4803d557a10cdf9314e0b3faf98f9338cd032622052d21e80169cefd23c115b4d306
401	1	303	\\xe4be4a1fb99acbe8321a2964276e75cf6c4489644705964eda7d9976ce8194411c97ca6a0794c301df08f055f7dd4d9d07f1fc3013687b50dfe65bf65d3f4005
402	1	347	\\xf9b40e7a5d3d256e8fb56f2f819402c12be46c25e087b9205365e084951731856f413aab688dce55818ba69b72425560dcace002ddfd80f707f18bbc7a1c7908
403	1	270	\\x659b8da30baffda6dfa0aa759642e1e6f6bc7efa101835393b01fc553c43b5b9b5c5685648e7ab2233ce35f485eff0fdec0f1f2e29b6cdb8af0ac915420db80e
404	1	51	\\x56326b39432ad0ee441f98bf64f07abe595b5468f7820a42aec3eb81053792f7f355b863f90597678031ff701f9d34a7c7c077102cb8fd38d18a8c2b890d8103
405	1	189	\\x38c8153d9063be86aac5802febaa146858acbe221240d0f67d28622ea10a61650cdde5eb582e24c0cdfee2fbec08706e6414031e51edd8fdc45d95e5b0ed9103
406	1	167	\\xa646a204094a79c173f933717553b047bef68d304e723d41e26d983f2d162a421338ae809927adfbea059eb7a6312b6d1d4f40724761db8fe5aa95fd806ed20c
407	1	399	\\x5d775be58b074a1fadc7a6d803ac7b8289e4d20871b2fbda465511bb16d7c28bdc232f1573b6ee25b6814e1753a6cada16eafac4baf97ea2a8e7e2ad07585b01
408	1	385	\\x4fe93314133b785a71ea8c0e27f92942433ba96a80d345e5a550b147f43af5ce1fd3c4eb71d64355df4c58c4661682ddc09724f3302a29fe5e8fe2524b959b01
409	1	334	\\xc887c4aa3c192fb739b669a5237df3c8c76ea7c83d2ba76e7f690534bb48be50d92b3cde9c3e7e2beb975b6e1b95a7a4bc3f542e13ed2d0a7616758c7bf7690b
410	1	398	\\x7f1d8e7da6e392e69c59d05ffc514341f795f39649340e906a25c5b91f962f13de4d1757254499160990f848667fca582908d1bc31b33f5bd1093b3607c29e0d
411	1	90	\\xc3b153787dcc8c4bd63cca849384ca9a288797baf76a6d7a13bdd75c82c2c707451976865ff549ccb6838539e1b1edb30a41157aa4fcb0e4a9e497799c524707
412	1	211	\\x6d5a2e1c010f33c7dc3fc69428b8937994f1091c8a84d3d994d1c17ee4cd045e05c462253509385c7777304cade5a0198470e5cd4614654208c3b8a37d45940a
413	1	307	\\x17eb4895e21d7f72d48061049f8b00455dccf6f1bdcfb59519e95c05c27e0590e14b4cce62ccbff9ab37ef03076b9749fbfb40d628509666f5538532c4adf00a
414	1	125	\\xf2050cf29498ef88889b4bd6418ee8450125507443caa46b3f0b347ce2e1029daef35c3160ac97dba5ca1a738420c2132972d882d54ef14d9df1f24ac39e3909
415	1	267	\\x3ccdcc23ca87c70031d274191c03d5b0bb5a133951434d2929d05283f3c8e47246847e665018d045fe344ad682e7043a3058af7a5a6bc926f1b5e4de7d05760d
416	1	87	\\x80d389405d3683d2f07dc11b1006d3e8c46b17b427a86f0e057ad9fe7e0b479235d3146af2ad85fa0331d6fbea05245c51e08415e01ed0177e6efc676359f603
417	1	5	\\x2a2d666b1910cf1ca438fccc91649c295cf593b460860e58b5eec3b4419cc081a6d4b972f23953d8ab2397d07fc4e4580efe2ebad5661912d0bc8b281e300a07
418	1	402	\\x018220f94d1e7f2b8ea59e1596edf44c1086305fb5a9fbd545c265ac6107f1088fb3c1506d2628e2598a1b7cfe13737371daf4cae97f7d8cb945fae20c962404
419	1	354	\\x56bf892d3820ee3743f85d341632fd6a3f88a24f76f7c402d4f1f7fc3650dd8a3fdc86a63d18e2281a4d9af1854d99dcb7caa76998bb97e444bc8947b6c03608
420	1	132	\\xe596b228a1e9664e056d5fe34275fdf8b58a9257f572640aa4ed9ada6de65fa7d201afc1996494428080a80f36ab65cfbf2ec6ff3e003fd429f1eee5b0e9330b
421	1	326	\\x8155f275427e8f3057b2172b40010297d0ee143e6b0f84193ebe138f174cfa029371fd63d2f25091d6973ceb0526b1abd381ed5f30728c4cc1510a6575091006
422	1	82	\\xb6637f9e5c1682accd032a16cebf9a1a721726ea111252ecf72ba594ed19a0590549779fce123aae878bafbdc02606874fbb9be5b55aa310c977b14d462c3b09
423	1	228	\\xb396931ec7d262efb1468fc3c6538f86ee794180df196a4737341e8503c212e5dfab255bfc61b309e4e2159fd0c7c2388f9daffd1762622b5fc37457f6a31509
424	1	216	\\x07be7f65a57ecb793a8f2854fbda3519bbfdea076c2d7318bba2679b141208128d4a1b454aff363f783a42d6da2bfb364caf95af86ae8f33b0fa12a164c8d60f
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
\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	1647525758000000	1654783358000000	1657202558000000	\\x02ce09f924810486ffddd0e2ba6d8d9992d0bcfb67381b8d0aa970bcf45671b5	\\xf3344d69c11a7ffbabc1475d78e3788991af95c5e45c0cec3d6cffdb145bc88c8add5758d8634f56f17f3b8d9d82ad62e12b9495454d348bfae5c6aa96539f0f
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	http://localhost:8081/
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
1	\\x587221ff78fe8fb82052b9580db7519b7c94fd5eb1bf86a5c2c7d3ae3bb04fc7	TESTKUDOS Auditor	http://localhost:8083/	t	1647525766000000
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
1	pbkdf2_sha256$260000$322iNg8AI7nUfrktwwkuEU$3gtgJZeTObWlQidnXtkdta/zKP4A4DWRZ9IJjCZOzYw=	\N	f	Bank				f	t	2022-03-17 15:02:39.167116+01
3	pbkdf2_sha256$260000$RSu0FUSdU6QYWTi6RWsthH$e85soX6+Q+Zgq8o/zXPKT2ZA5Nyqqp2s7trULztgD6A=	\N	f	blog				f	t	2022-03-17 15:02:39.458838+01
4	pbkdf2_sha256$260000$c7qPWI8Wd93QxK1lJ9ppo6$C/CqKiJ41zL3w/DCJCMa7T/Gh3tzf3JiaJg1Vp7g7eI=	\N	f	Tor				f	t	2022-03-17 15:02:39.605687+01
5	pbkdf2_sha256$260000$C9aTBs8JYUb8KXxp5Dx3zE$SPc8c+kCnZXz/XutS6gvBftXH4zO5bKtbfElPDE3rmM=	\N	f	GNUnet				f	t	2022-03-17 15:02:39.752071+01
6	pbkdf2_sha256$260000$qMhadNbZyda7OcrKkK8uKM$lXcAPQfddenCkEWxX6AALGbnBJqLiuKzcf8KSwnSxzk=	\N	f	Taler				f	t	2022-03-17 15:02:39.899351+01
7	pbkdf2_sha256$260000$Zjwx2wTYTQ7TV6XrFynFmk$TQbWXOOQ2Qz1guHjxmsVi7WodzdFPQ3eUaxhjQyg1H4=	\N	f	FSF				f	t	2022-03-17 15:02:40.052436+01
8	pbkdf2_sha256$260000$tUYqnELfktkb8SlSgPPEzR$sFafTLxXymiqybvY4iAFG4SNaK7GSA8Rihv+t1X6kJQ=	\N	f	Tutorial				f	t	2022-03-17 15:02:40.200347+01
9	pbkdf2_sha256$260000$RYIGKxG0IefEzdQeTCkvmY$LTlP65j12cAZQUsdtjqTqn30JxuJEN+KXu1SzlaZbtw=	\N	f	Survey				f	t	2022-03-17 15:02:40.346973+01
10	pbkdf2_sha256$260000$ztZJ8Cudj8r3cnXI7oNmDk$ON+/GQJXDKOLzjvufwuMtD+lWKEi6+oHkx4kc5ijTK4=	\N	f	42				f	t	2022-03-17 15:02:40.985647+01
11	pbkdf2_sha256$260000$ioYenU1lKPiceBuYI4lN2A$Xpmv7TDexYoyb1GEuDqv2bha5Q1ssA07esBB2YAyW68=	\N	f	43				f	t	2022-03-17 15:02:41.541567+01
2	pbkdf2_sha256$260000$ETDhSZKh31KSHpUbxoQL9O$g3LvtLrIze7PTnmwG2J1eiZkwtBEptCR87NJVgmZTfM=	\N	f	Exchange				f	t	2022-03-17 15:02:39.313688+01
12	pbkdf2_sha256$260000$jBQkPbr6JMVIUAFp186vZM$hLoy0GlzZ3ZcEjA2K5mFhZv+sffopFI+huiT+7x7Cck=	\N	f	testuser-4j9pnhrs				f	t	2022-03-17 15:02:48.923163+01
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
1	228	\\x9abff17c1c833abd47b01af12cfe8f8111736c83c275c307706ddb720242ef8565083546a4be0aaec5212df41371722371f051b686c64401eb99dea6f8790609
2	398	\\x5a706277ff57b0933a1ca6058002f89468a5ea460e0659a4b46663f957327e00127d41129eba2a498a2038f413111c156226b088dc810e009a0b5d64789b9802
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x00f4d9389f8508f51a2725c56d07b3a5e3644aad420fbaf320f6f90b23b5f116fbf646fdafd6a39fe699499b7da13aa03c6d2d27b148589bea9811dc3007df9e	1	0	\\x00000001000000000080000396af5cac9f6c6896629063c59312cdcea4dd8472af30c874ec27f2904155c4fa74f30a21264753edd4ba83ba953c2347748936f4a72636442c32ebcbfbe986ebb6c77f0a6db7db6795761ad23c2b81fffd34122137234f291d37ea218edd2f0ab38be9f70898084a4713120b9b5121caafb3c4b783dc58e3b43b5c59188d8d63010001	\\x79f91b5030edda71c357955a3a58178ee984de05dd83879ff765865b117a50c9c4abb2041bc366b9404eb1fea7d20a9f38ae72bd01a9b0644936a4202729d805	1670496758000000	1671101558000000	1734173558000000	1828781558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x029cb98186abda413e157299ef9cba54a6274b9efe1a1956b5a6cc26b5985047d17aa12df9e6c904603af559f81c4ad8849a3bd5539bb0e7d60d15ec0fdac9e7	1	0	\\x000000010000000000800003d166ffe716fe21a2701d41169a36a8738b3fb129658e066208d57f0d8983188fadc4129d35295fceee21411ab650cc9551f2e8b660c020cd992a0ffd6796a4091ed6209a4ab7dc783a3bd2bb60ebf8ecc5e00709fbb91645148e59d6d28fa922442edae714e6760fc887a5e5f400dffaf065f45b1c87d5a30a8afc94b09b9fdf010001	\\xa40e065b6886aaa4097e1b549fa76bdbf445d2b8ea496645d4c40bd302af1681bda17aa5d6f3920d13238ff1a88c344d809271c96d62ac9c3d31761cf320fe04	1665056258000000	1665661058000000	1728733058000000	1823341058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x0430fc60b93692f4f6c200483856107bbc0bcc3c88d191d4d59e364d01ef5db056d6649e51e71d4eaf46e6f13296c3fb441d84edd4ebc68f77d71a4eeaebd5e3	1	0	\\x000000010000000000800003d1c134d48b9404c0ad49a34c73c0ac465a0d03ddff361a8b1838160b1b0fac081ea083c0e57ea8718079fe69abe09933f28a40254ac161fd7b201c12a8182bbca55a6a9b17268a4bc7e37dc90bd23f8d7dc282cb3fff78e05b9f08771df96146986a1013938e05ea89ce1fdf284c77ef62f4eccceb0e1fdf75a9f2889a1fd6cb010001	\\xc2fe7d19f9ccc75851bd2c240fd7724baa2a5e331ec815e5d482cfe6f9f64f475b72aca32dd5f31ef1a4b0045a6045ce8fc670309fbf32e771ba7575ef51340b	1650548258000000	1651153058000000	1714225058000000	1808833058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x042c1768b829468d7818c4806902547755860151be3915142aba9374ad945891d23de05c48e08e2161c976b4b47908079f817ac30b401aec030235498d4f5fab	1	0	\\x000000010000000000800003c56ce74be370fda0b3730cec1c606c319543a7db67a983cd3a0d7fda29054140875c760a1edc0abc9ef854180413550f3c14dbb880fa98546378598916bcaa3fbc55409c60bcfcf4065e91f4d7322d0732475effb91a3e002399203553aa693cad80e497f36356d0158a6faeaf2aa9f4f23a57495fd8232a2f4635c9eb48b5e5010001	\\x317a671aee8f46577bb7f843f942ede0182d72797e6800fe23a18ab9bb38b434372a8b9c557358f14624ab4dc52b25ec875ef568f7807a6f2d6d293800b99c0f	1673519258000000	1674124058000000	1737196058000000	1831804058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x04346246b41b5dcdd58fc4863aaf0dc3fe0634f254feffb7a815f5b02fe69c2ff6d2198ab9e02bdf6d61d560b8e4e658ec149b053dc170cb91ae31db7eec32cc	1	0	\\x000000010000000000800003aa703c887ead5f1ca1ab996a8bc621b08888cbc89d12d22d882f5b82f7392c5ed758fa923cd397123a037daea5a34e3e89834fa30c4fd3e4320407d9f1002ba5d8e1d1fcbf4c37728e4b45d7b43caa4dd3d8891246fee12be095ad2c318f72eee937770dd0709d3a7a37a257699fdb2e51836e6bfd290a0d0d86b699ee9b38e5010001	\\xbc50fec5aa0ec78deb3b5aec34b04672006dc7d5fc2885b0f8eefb6d1928658f3ac1b60a3e53dacdaaffc6404fbf0f7561d835b6db468d98e192a60b9bfb1308	1647525758000000	1648130558000000	1711202558000000	1805810558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x0660061fbe06dcfc22953bd97ae9510b9be7953e34f97b587e125da895911c1c9cad8ea6960b3e06ade5d1cc0363b586cd93abb5b6716800d22f7e00955d746a	1	0	\\x000000010000000000800003b7bdd80fb8136ae74d7b3bf1992494b3bdc6fe48683cbfdbaa99ae7f7e3187edc3246b77e9d55904836924a3768d5170c1a138cac903419aeafef4db22f50ca60fb93e4b7c9cb46e7b88a3b5ab3147f9d72346b3ad57d358afada8b445971393da6c62e0840b6a24a4611102017746a369455f1b7ca1543529b8fd18f897cb49010001	\\x6f4be95fdd4d092fc7b724f6eabd407b58c2a298d78484b2d6c96e026a74685df12f3b9d3844a65d1078db8dac16adb0e5b83a650d6cd17489f9d8df33273209	1656593258000000	1657198058000000	1720270058000000	1814878058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
7	\\x09785c4de9128f310b0f7a578e6c5e476796086bd4d32af4d594ddc17b9e95fc7aa5a7341981c5a9df41306624371c2312ca682042786c153c5a11a6deaa1c48	1	0	\\x000000010000000000800003b47de15fc528c5a97e1b0e431e64f917b2127e8db7a2a4b80ba0be0f1135e5e00d3832d40b5fb434a55fb2403c655aa3c127af20e340ca3cd77a175e418482ec5980d404a9465a60de5eb40320bf7116fcd297831a8f1db3f50af346701bd11128165ba5717420f23680dd4b3ce730cf04da79a65736db76305892b9343a97f9010001	\\x66f757286f96071f916df7a76cb330fa17ef4c1294e2b7d182923e5cdd82f367add03bf5ba80e461f16e1e3a649c170ce5d4a3fb84b3171b139645ee663bbc07	1677146258000000	1677751058000000	1740823058000000	1835431058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
8	\\x0c7c4c5a305c3c09f9fc77e743f52c8cb3c1c3ee8d7bd8617c399368de048c63f9efdf6dc08fb2079fbb6340aaf914053b73bbe777c8a863dae9e80b59120f87	1	0	\\x000000010000000000800003c2b801cc8c1aa33468f9815e8413f839f893fe2120fbb82db44eb6ec1f5720b1efef8ab1e54acde3f11aab3bae59b1545994a9f7636d5508a7f9df08a34735b2f6c92e0df2f9a5005e223763c3469bb9def9796efb770cf2aa4a993cb26e04cd2bd41d9335312ff59405cc354ead6d03bb609080b05709a53b9932eeb91f2845010001	\\xa193288009596da03fa13a146067d1e28264ac0dc7689981bfa7912da1ea3ce9dc9b35a8e923144d2773bf013e14f33d144a6fb657793d2cd7f0d70a7c8f0608	1665056258000000	1665661058000000	1728733058000000	1823341058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
9	\\x17989e4217866467ab49434bde7aa06ccc44fc6265560b28b4c6358d2c26cb4adfb5ad47dbbaaef31028308ac6be3183d30ee7362a837fd5d07ffc8822f04b2d	1	0	\\x000000010000000000800003f8940406f914d62ffb6d4789f31a61227e916405c80a9a299d0d858c5ffa942489fe38ec3cf59020b6083e424233b2bc9a58d47b6cc0b2b3288ee9f08454ec2889fb7828dee4453523fb7c0cd496b051eb363157a5f95613320a730875bcbecd3d5465e9399c9e3450c9f6ebda2e41340c622aa49ce39dc80861c9eb7e3a47c7010001	\\xe8f98084c8264577f428771144b8f767039faf0e8a7cf640790ca70abb7d27d3c818db86d5008b63dd3d29631320172d74644d8e13f9dcbd73965bfdb347050c	1678355258000000	1678960058000000	1742032058000000	1836640058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
10	\\x18085902a6086dd59cc7db279a0a895fd69277d2ccf0121e9551aa47601b8ed318607c423924a1248eb30946428031a5801d9e28e8a67636a6877e72bcd80104	1	0	\\x000000010000000000800003c02b7b9d71525b33e3e62191cb50502215953d7a0bbd4f877fc25c99d3d5b45502d433b7c04fbc5d38a5bcd29f7b36f1754d4609c82faceb863e88ca09d36cc6807316b4dc61013de4a9a80e599c30bfb001b414fc41738e0fdc55adce090e7788c62674e9a9b24a844e5c53ec38e99d755da2b5ce3845618ad6dec61769a73b010001	\\xf8da3fcf1230c5c14daff0947a0aed6db541b1c3bf8f102bc8019e2acd62ecf4431f3d95d329105d9edc1a9f0a5ab0c7e0a2b9137569f6987145556ce166b20a	1666869758000000	1667474558000000	1730546558000000	1825154558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
11	\\x187c0534c65f9d8f38fba3682adafd956c2ce7c75f3fb378daab5a15a4876a823e35da48c8346eaa728d3e6d34e744b1e165dadfb3dead5005f6ccb3530e73e2	1	0	\\x000000010000000000800003c9e360b16e22236c15d28a865291656582ffa2b0eb738397784ef3a18b39b6b74e682b723151565f031e5038abfa0e3f1d3051fabdad8ed5bd793be75a94413d23da58d8dfa696aa9c68b3a18b0d8392201c0290228dd67d08c21b6d63d55b9d653d204a77d9d42aa7d9b079628d964656aa86929c0d875530779e2aa45431cf010001	\\x1561e7c3f031bb49f069960377d3022a85c220af587c285928d2f08e3b342aec49618503be183794442e1908ee5235604a0b3b0037555b0ca630ee70a7dc8904	1672914758000000	1673519558000000	1736591558000000	1831199558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x2354cc4b8fc72ae2cc4b9319b38dd6c5734b8b8563124fb95feaaa464f6fe82f2e8d65e9fa289306a512d561f87771927648c21724caff042c93f93b16fbf72b	1	0	\\x000000010000000000800003be9ba578ca9f6669db6922437d2c06ed8fa9a92f6c081afe729a669d6456a0cf48cd491feb7b684d6f8cd4772169a90c9dd54ebb25c1f04b63e06fa8b95ab505c07b26ad7f42421eae53202064c89883525bbae5204ac2f7267fe7ce5e6c83e3d53d643a2317336edf50367ff41490af95f987857db8ebc54635f84bd688b8c7010001	\\x00542c64d101469aeb24f0ba8465715e041699e3e7e1d53828ac23e0da5e4ec8a96ccd69b0e5300281f000530e24919dfe0456fc3efe91da7e205349bdfdf807	1651152758000000	1651757558000000	1714829558000000	1809437558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x23ccc60aadbb55f4fdafb07e811518c9578117ed63367ef67b6974d344311a0b750da058450f4ab074c91b3be2aa213ab1cc3955e4c878aea3059fb7f1fdc70a	1	0	\\x000000010000000000800003b8c3f5c029e86628223b8b14626afa0f86925cf613e95844d9799df7ff9818e17576c72133de18720f65d718d0f85ea427f9d981111e9483ad7b06faf817dfe8a1a6d7597a87a7d5db51c4b4ddca569f1a8171f9750afe7cfd52701fb1bf310a90771bcaa119d00351aca65e58eeadcf8b89fe5a634fe4432fd62912ab782a81010001	\\x7f4761695dacdd87ec8aeb66d1c3d58fc3013678ffdce4ffcd93431d891e9d1e17391dc5ba9a3adbcbb4dfebba3837a28eababf71bd863863f3ed7d5abf17b05	1663242758000000	1663847558000000	1726919558000000	1821527558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x26789826ad2dbbac4e090e2c1b4de12991a056d48dd4b67e946694d5e414e9e47879c137dc09fa6b66790deabbcce4fcb3ec1a5eaa782387270008af1e05ed8a	1	0	\\x000000010000000000800003b89d67ff1c2ebe43d16b40eb52366dcc179be1a73ecae34e2efd66950a51b64237a5dad4fcc7781defb9b6b5c1d3f2ccf407276ac2ad1157de0e762a5c0040cd07e13ffc6b2aa20fa78255f7aa7a8e340836c5524a721623fccf36f23bfb4758e0f873c445b7e4c18235b07ab66c557112bcc59aa74fd3ef9e1843f039c4b85b010001	\\x7d501a550e65e27686c8c9989192066a9c3e5785e970e373783e7f7a0afdfa393239ed826bdfaa215a3b4148f32a2c6b25145b2e496ee26510c36d4dcaa9eb08	1660220258000000	1660825058000000	1723897058000000	1818505058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x2804f54063d280ff5b99c0afc3333998a456bb7ccf99935360d3a51edb36468b4b92e6699d740faceabcd64233e972e0bdec7c458bbf23d7fc1ffc479147a002	1	0	\\x000000010000000000800003afb4a8cae24a806798536687c8294202824d4f83185cbbd053e04def87631d1be325b6da6169641d98221b5952d1d50a22bec468940f01681381fcdcfcc9fb2e35735f3d7497133524716373069ad6b62935629541a2541b38bb380dceb13007541a63bf632d317c75e1bc7626b64585bb6931f2e361def7006bdb56946df6fd010001	\\xb70c8b9bf3776fa6e338b026be569dbdf31a3a83c41b688956390be1f5ed313240c84f5d48cb67920783896138bc267907cb1e77ee4305211bcfe47fd912fc07	1666869758000000	1667474558000000	1730546558000000	1825154558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x29c4282b1dcd93004c5c4e5d2117bfe7b0caf9610c3737040f04e0da0032e83ca48ca6a676a41485afc22f7f30f5831c23c91ac5eaa694e22557de3002236675	1	0	\\x000000010000000000800003c01c86b6ad79003e2b1907a18cdad30422902f310b091e54099950f38fa4945b6cf2e5fcbe7ce4e7b9744ebaac3e737129cca3c5a708e400a676956e05bc75533074be99094bf202d2f6afc85efa3430d16b7294590b2c0a6fad595b334fde33861e15b78f5375abd6680fc6c955ba1153da5de1e8a98d22439d8c70c8523c0d010001	\\xa9bb7f2c4546f00d55a8fb2fea1ccf66b926e8337dc1ae93b8fb356a5429fde31e874dca822fbbf297e16d893bee651128aa11fed7f6faf28f0e0fd679b5040f	1651152758000000	1651757558000000	1714829558000000	1809437558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
17	\\x2a18104a90295b48d331d8536ebfba81a932032b64a57f1d4e50369d24daabcfd7aaf32504e21c72aa7dd7a6a5d76d7bea5083dfdef51afcad77deb4f550101b	1	0	\\x000000010000000000800003ade39fc7eec75f657c8a8f7b6e03e2dab41cfc671dcc6b934335398574db1c1df2902e851e0d18bfd5c86a380242e9533a0507d1c480a28c7e20a208038aa6a7d02e3630678d4096b8bf3c73d82132f2ff5695d4d003575dab0393c76acfbafb95764555f9f1afba0724d3d068200c43bd997d4fabea696602f2c006d5a7b13f010001	\\x4b7e26657dcf08149229383552955428be17c712577cf9a8bf4d6392fd7a635d49d4ecce3bd8741657286292d950adb2c00c3d86100023b2d092b7fc452c6700	1665056258000000	1665661058000000	1728733058000000	1823341058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
18	\\x2b687e5dadc2ce51cd4d0a42dad3d3e2bb91725cd651993da1945be5865910214d9c3bf5cb1b602149607f8067585941052d845e033bc502e4f0a25ca830764b	1	0	\\x000000010000000000800003ba5bbc71a15e750237ced38749323fe00f2d5f1e74a8873e60181360ce43a6386a66e39d2b4db3b90a3798848abcf0b61a93bc5daf65921b4b0679ae5f52e1375455440dcb15c5a442a861b0fe1bab11df2d7e368087d67fac6f775d46968b739bdb082590dc55c5e42555fa68aecdda442ce5dd387a6d1ce9edad07c0201791010001	\\x2e2991bece16c93435e99b601fc2085a5cf8a11ced927f824ca5f32f15d4590314a79c781932316ed4cd40e936149b2a7d7618cd2dad9a471e1878e4ceee7d0c	1659615758000000	1660220558000000	1723292558000000	1817900558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x2ce019cc4dd6ed305fe786042f81c0baa7478a8571d341e3644310086219d082558aff5f9aab8c16ac0ac08c6254bedf7804313f6cb39225185568f58ae2bcf9	1	0	\\x000000010000000000800003dbdcc1eec89093db95a483043d01c8e8aabbe9f29ec438f7572ebadf164ba6a673327c49d8ba16ce7a9276c278159b87e6a7ae7ac47b244ed3060f89c20a7b27651c824853afee37c2997479b43886ac98f04a7080c1f3267832ade717921cc1d78973394ce3dc46404c29760bdd21d741220bd3e61f189017bdff56206fbc3d010001	\\x3e14c8878d273e8228e274e4935631a4f5618f4d74ff638b254e9ca84f52fb02e7bd075d2ed56f305e079b36f5a9dfef59232338c7b453b4a1a8a5d1d8567501	1663242758000000	1663847558000000	1726919558000000	1821527558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x2dd03340050c9f6f562c9149d3474e3cb551d9d3ea429d62cf1f81a91f5d357f7b2fde3e717a5e4a64101ec97851e57b378c0f2dc7d331b77511223edfb599f5	1	0	\\x000000010000000000800003b04069eaf0f220f2f20be3acf31e20d251e68c45b699d602fdf7c9d01f61955427c08b368cbf8aee218e26e9ff7b1f1bf1d5795477555964a00a452c1c75b63c13fd2cec5d7c3e968bd432692f015b964a8f879f249355e38fc7abea5babbd5725dc1ca380c856308fe7b559e66639fcdd4a66965bebd43220ceb3ef6091aefb010001	\\xb02b60ff80c271c41c7b0f298df41d4dbf9808a53879ebc824fe428e2f64893f04888be7732ada60bedc87a4052478ec29139058b7a57a589fd1dd8c7e37ce0e	1678355258000000	1678960058000000	1742032058000000	1836640058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
21	\\x2dc8c9b1bf4132a6127e2f54fab828c27abedd5a16d21cf558b64cb63262579ddd819b7c181dae95946f933e93179271a5eb5e7ea39db459fb9186ee16b17156	1	0	\\x000000010000000000800003f43781c3a89d8aa13d5679cb9c331aa3f4bc2d8e194cc1e73ac5f7198e02041c6aaf0fcfe56c606c8342c4779fe73f2e2e62324f53e0f30b5e86357be3e5c3f19521e8dbb2627b7f541d2362db8c93e01adca67d42480981733f13b46d651265bc3502811c1dde9009a11b2d0555726b0f4228b2e5b7e4b76f7f3257063d428b010001	\\xb9011652b15f0ec813ef6fed560ed5a003c419439dc256e17d0d6c33feb21c646d77a038d95dc85e7a7677a9eb6a7f05acaeddef36491599ce5b70a2c15be40e	1677750758000000	1678355558000000	1741427558000000	1836035558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x2f4002a00cb32e296ed7c0cfdcb20149b1f4b8c8437d73417823af0aa33b3a658f484a810d4571ba50a74b348ce04ba5c56c96d94dd6e21d98ebf907ac248d1d	1	0	\\x000000010000000000800003d17b8b7034c4cb13a12aeb43893e133c941a5543274a477c232c3765ba8aafca964b9963fd5d83345d5e03ef337e114bc28e9811357280cc146088abd4f52b349da41f35dcd6d2de6ef2123336a946205a341a3b32d7be344a1358107d9666bb7f24fe9e17ad13492b4c7360c038c7012c35275178a02f8731b14fc242e53a77010001	\\xf01343baf513cfe89db55b1463ff4d9a109dc0509cd2ca120307659c7105c66566677b5031af3744882909f32f6191c530af21b4c7100ef4fc2bc094b5181700	1672310258000000	1672915058000000	1735987058000000	1830595058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x31848c662b698ccef1475521f097d456af8d9ebdd24d932164d82820790d7f974dc890f614f86e0a8680d875995c16121e46314e052d3682b80fdf6abe3aa251	1	0	\\x000000010000000000800003b697fd96efec70b8b71cdb2a74e4141392b9d7bbe225b660976bf53c49dda2d25ac2f90bb9873bb76fb776d8f1cccc2816307237d6959c0bab9f7344a6ab30a3bd1ca34246b64259f623b2759704f1b6ddfe0e49103f849b908b3607194624278e064cf4fba875c4742829b62e8671ac6363d7b3fbaba1aa70222cfa7b8dd9ab010001	\\x850cfcbea46e2e3c989b69b9ccb8bb0b169f14bca73d116dfed7adebefa67c3aa43255d3bb0848d3e66a86408805ea6ac4e04ebe5792564d15b548c249b07a03	1665660758000000	1666265558000000	1729337558000000	1823945558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
24	\\x315c12989e6422a252bec41c3bf01b4c017f0e00aca2a5ec6fc978e2aa2ca78f2a66520d22c3217410908eb79a0a63ea4b0fb61e56bb160215de26ca635639ba	1	0	\\x000000010000000000800003a4434ee5a3af4bb185c465c2baa7c7e0339d4013eec1b91450715e1b5c7451eb5afe9947d4210bdc1ebb79218602c13e7dd3025a4808e18abdb52605ef8f680745d991755330a0a28e2abd7ac3b7c96317cebdf7d28594b1a1a5647ab174520b0df7ca2318dd5f86dbe82d92789ba56483b6da25f1189eb6109622b3d31b43ff010001	\\x00054b4f952c56b3f5a79c95f5ba70eec58d0606f3ce15eab254855bac576d9f6a8391a0feb618d851241e3223ab4ff3bb3a4046cf3ebcdc8beaf64358086a07	1669287758000000	1669892558000000	1732964558000000	1827572558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
25	\\x3408119c92be92bfacd4b6818a7b581f1f968d008da9fc98275fdaae8a0942d2c6bde9b4a9bc5d0edee21298e4cefb9fe948f4a4a9f197f730ee760d35f648b5	1	0	\\x000000010000000000800003ef8adae41cfcd215b7ebfdd202a02c3f5b805eb9072322e06b69a466b2e03d50ff7c171c6c97579f0e6b1c2683ef8ba98319d7b9bdbbb3551677466cb26ed1b1eff2dc802ea51ffe05656d8a58c3b5d55d67eb27e1d19e06bfc124625652ca2e91c50d8782b69c54a8965061158befea2bfa192afc515f792e52621c97eacf81010001	\\xd50a2295f6499f0a9c7e6a77619854f23c82111ab081d75568be96e4ec4805b30b6176dcb001cdc4d63bec98a29872eb00eb820c34ac7578870641ecd32eb008	1650548258000000	1651153058000000	1714225058000000	1808833058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
26	\\x34a4131fe869164adf0473b7072ea8f0e32c2630e595768afe75ce984078d45083d25d9b00272b4a81014a0e8831fc63a863363753b633b09382d59dffdce5ff	1	0	\\x000000010000000000800003dc2b0ebce7908042a896b98edd0c022e5f719f11bc144eec228b775cdc6e46be0325f6e14740465a59e96bcb51bb89d7d0568de86cc946967f51c8401d1d92ca1e9b9bf8f96f4567a1f915e286ae41a9b725b282cf725c31e178cf5a5470f169ed255720bfe4e23123819020c90767d1c4569fedb3df82a2e9b56c55c9379f83010001	\\x0787bbf49e3f97e23f7b63443da3e157fe1716971dcaccd5cf11a16a8f342252c97abcf080dcc3f0616f1f1a8be2ee17aea9dff13fa122333f88ad1f97b60601	1651152758000000	1651757558000000	1714829558000000	1809437558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x3504e1b820181167b2930a990fef42b10962d64fec585a870f5f93e3cf5dbe94ab8b5998a3c1172d32a31aa705a2338b466154c14518a2144aa3a990411c3fdd	1	0	\\x000000010000000000800003c7943265e9c8b798f5e71d5a0d19da3a80790172fb53c718aa5ceb0dbf6689b9276fa50535a1396b7c95b5b1f9355ade439fd61d06b38457ce46dee6fdce3dc331b3174c4baab32b125a2283365936e4d5b396227aa1173d1a68f57bdb844aabe436c6d9ae4680a4babb1482025014e6e9d14f2c7b9cf764882edc9a9389bb93010001	\\xdd54447a89989d9c0b5ef78e4b91cb3c75d94fff87a77f1536d7990d65d0c811dc59abb7d8304262c20362accdefe3f0d91857842b2d3be5467116af0d6ccf0b	1671705758000000	1672310558000000	1735382558000000	1829990558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
28	\\x36b4925e36900cfd575670716aa1bfc7a53fd0ba4d5771f6cdf2e1cf745b1c9ddb227c7ddf8a538c066a18fdee1029c4ddbcfe41166d711a88ac7ef891781f41	1	0	\\x000000010000000000800003cbd583c0d94475cba4eb4f4d1b5c1e821bf3b83efff6be28277cfc614bae4689000b96110ed471d8790b038eba1cca9162ec45c27551372a6a7685b3081d5cb68995d89a6a94321b188b7e992d95feb22c9daaad3b990a74765e4210b7af2d5055ee56b55ff84dfe0a5c41aa759b4da4c7dc9a69294c0adff346e92c607a9dd5010001	\\x44db93411d00ae1a87fe2a98f47d5573628f4a2ccf94cb3dc56c8f646f66f1c040c0e8994c7fb28b7d9905f89980a21a431d0247bfe701092949c949f3500002	1669892258000000	1670497058000000	1733569058000000	1828177058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
29	\\x37e43d4dd834de64a62db8fc61c6afa0aa9190bc1450b5a5cf94e29275eb760e7cc2bb65a2469edc39957c01d2462fc306491ed5c953a5243fe15a2a482fe3d7	1	0	\\x000000010000000000800003b8ebf96599bedff66512e671c5b260c7d3d7b5e6d7165e22a61275002baf04e7af8b20f3121bd9b334150c68b5ab67be09b0c80ea7e4cfcca6d9b6c09e2cc828ebbc99381758fe2d0e4deedb5086d3222409c9b752cab5c9c95fde93ded3551657d3dda23875c381798891d95aeab5feb2b33d475eebcc48d9fe0dcb5fc72be3010001	\\x383fab531d3f553a5b8982c63d34b88daf23ba2459331c65eff8e2efde6824a19a59074492be82f13c95fb80cd9a4a9a0fae13d42676d0bafaa5562ca7a8c209	1651152758000000	1651757558000000	1714829558000000	1809437558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
30	\\x3844eeada3aa435a48f22d51dc3673bd3f7987aa27e742e4615b537939429b14668156464e4f63d214e2d53cf625a9a45d61bf50f9ac357eb8a72584c6f9eda7	1	0	\\x000000010000000000800003f01cad7da18535e1141e5780cab0f34f369590014b3f9a534ce33b9c10d5c9bf90cbda95235628574fe9a1951c78691cc1418372e41c2e58058238c8692d0ed327ab44960fe2c7af239b352946c8a4f8ec6424cfb90e7a661cea4097020878e9cadca25e6bb9055a3134ee045b3630c0e14f9c115c26570ba8cd0f4a44177349010001	\\x7662ec58fb12ee869b68d5f55cb267b92b01744fc3b252fc9bec8ccebfc1a2880473da0c4c135e49a0f287095da750ace410575eea78008b3d062665e57dda01	1671705758000000	1672310558000000	1735382558000000	1829990558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x39b43bf56c60ca1e483ae41cc53ff30106e95b12a76b7c92c3f02f5698ec44e04026b5a9a59c0a0ee052bf347cc098bf8820008b82fa3da31f7b9eca7b94f309	1	0	\\x000000010000000000800003dfc032092c241694742c90818a319444f2b27cbb82e3c271fd61a0625bf7e61a1223b37e5f2a77fff4abae6103c63d8a07daeee9edb4458c8ab986ede51847af5daebe3b7672bf3fc60f98acdf8fffc20d45b5e9ce8e9825b2e32d58d6d351d884ebb3de97d8892cc988210d4b03a1edb602236fee8ea70fa066176f3bdf43e1010001	\\xec5cda68d31d4aef95bbe71783e71aa6d9b9d30bfa7b0033e6b8fdafab3405f9ff3aa035a1bccaf7a30a8ad88fab603e1b8bbc1be546b1a87cc9876dd810640b	1658406758000000	1659011558000000	1722083558000000	1816691558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
32	\\x3bac31bfa02ec66cfe29edd488a1e23fae4c6a803f830a063e67a67aaa46eb73b64fd4bd2a47346915a8cca558b0ddd9ed9a5cf2d12d9760be0b801e0a9682d9	1	0	\\x000000010000000000800003d892163cc69c23db0f879111a683061801632ff8f9c3090abee151a3325383908c0274453b8b79ab30deacb2c9c1fa17158c55b67ed8416f22183ae886a5d326177fdf5e7d5e403933fa758845d798c67bae60fe1bb88794d82fa96a55e2e55af83b7c2395438347ef163e590b2cfa4bfc3ad9ec9acaa4dadcd076a197029d9d010001	\\xf840be0ece499e7f2fde0adfd0b68c1b5571a5436f84d13fe4471bcd807b8ae8dd78502bf33c719420deb729b6d2d448ba5ee875f44f36b9c9369c3ef944cd0c	1658406758000000	1659011558000000	1722083558000000	1816691558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
33	\\x3c38dfb77fbbb2e4189495336efcb767f500bf41c261838f4806a80f986dd89b9a53dc038d7f389597348c393ad125db6cc7709a7fd968d142f5d65afc841e44	1	0	\\x000000010000000000800003e4431a1bce953cf5965496550f2d5becce958e91e1afe48b36c821076d7e5f4637cd28dfc23b7d9feef9b504f7eea4c18a18ed82f743b0c2ee9ae429d1e7834cb5f9f90336ed0a8bbac6fe85d44df438bc10e44e9f76d4b44ab3e2a987dced536e8d5c485b9eb9d2566265458cc51ca126ea2e6ecb2f5e2afdbefcc8e95150ab010001	\\x4a3e25a6dad945456c1e22821c3ee514deef51a31c30a4d8feedbcce22a2dbe75c0b5a7029459a194b231097d5159b5bb7fc77b15fd12fe93db2b7183c607e0b	1668078758000000	1668683558000000	1731755558000000	1826363558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x42f8c3cb33f3050b19e5164f4eb9d2aae104dc1887f973d1a824444c1eec7d77bae2047cfbae65a5787733a937b1b0b2ef1deff8ff2e4a92444c0b49331c1a56	1	0	\\x000000010000000000800003d99b8fea373ec829c8c4a38ca4bee067e1f38d96a888060bab01e059a0773c5ea288743ec2c1841c4b4d1afac72b2e516ccd0f8b82e4f4853b93714d0e1fdcb84d1815ad6a0a3dcdd211a13238c170edbce9360fc5e6688e4b0c402b955d109d77127ae9f7660b32e5f3893e4a334e75766ffeeb3673ed0343ac8a7bf6a7c66f010001	\\xbd089035ba246c0f6b7df602e357cafd56eed7a924573c21c166b1aa69405a77bea1cdb24e6788d43e59a127d209ce281704a98929aa3fdca6142bd8b24c3601	1651757258000000	1652362058000000	1715434058000000	1810042058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x4230882cc3f98ba199cf73bf8eb5b86e483f18f158d5c2746c343b45a8d4c8019ae66862d2caa3c37540f2dd0f7b398b9856fec667ba5b4c35f6c9efccdb10ee	1	0	\\x000000010000000000800003d6b9163f05c5ddb34966c766e5ee9265b628c14af64dd1c3a675caab3ab2fba630c5b56e4a500eab786cdad8c85bc242baba470968320f875116d4fe42b149755b4c0840b91c850e14fb49ed940be1cfdd6547ea9a62c98174b7a2c214ecd62ef78fe9834ad246ad586678c295d3a09d1a8766c4aac1fb7f6ff9f83577157ed1010001	\\x844603af88f965370cf2479d9bc0b397b0dde98d66d169104c223a4b6d4c63f44e3d5ec5e293297703db2bd969eb5e74e1c2b0e5a19b8114162c2fff1cdb4201	1649339258000000	1649944058000000	1713016058000000	1807624058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x437065f0f342c891f0c342b2d102c7b17014f5b25e61104f1b02932e21e9bffb81ff1d22fd48fbb2b9cc59e2a989d10646e577d43113f81d500b30c23397c910	1	0	\\x000000010000000000800003a91066799416ba41f150248236553205825314522a825281107dc35f94a5fcebdd67c082ec572ffde2e3823168d8dc72aa8e5c884d4e78e15afe8ac798c94e179a2070e46a34b8aab790f29ae7c002602ec90ab2237041c38e01e0ca279e0864c8510ccaef57156cb534add2208b2ab5155b1a67c7e637731323a7b86283fd27010001	\\x7dbf045a895d5a17bb954a5e329a39365a9a1a98c19463e0a965e98b60d83cfdd2cc7e9d0e4d40e6a4cec4e54cc77bd5fff074f86ba4718e396ff31c7247be0e	1655988758000000	1656593558000000	1719665558000000	1814273558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
37	\\x43cc77fd32468c18eb34fbd1fcb6e05c6ddab8a9162af3635dcc57da3b8c33c21797c87c9de5fcb4b124061ef10d728da267d321dac71ae02db4da3326ae8321	1	0	\\x000000010000000000800003db41eacf01f61d0a7f1cfa38b0c465b2ae1fa36cb7c319823618e5d466e304419c736a93599827417da0f8d0c724192505d407fab9b22828965f3093db26ccab96f6687a5aa104155ab5642ace3fa4adc795a3a9ca765b2c973a04a42e565575d29e67fedc4f165d6088ad670506b378a428880793f80109aa8a09fa6cec6a0f010001	\\x7a43c4a46a9986422e95f9adff5f3d4a547ac88d1b2c4de1fa4c988ec7fe66ba8496b50febc260153862c124b01a6a7f1968d2858f351c81b95aae6212d7620a	1655988758000000	1656593558000000	1719665558000000	1814273558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x45689a84ed892fa1d7769b58ee8680a200f05856f1112771ee036a9fa345fe3fffb256d24bb04f5fce342383afb65eda11e8dbdf07917d70735ca508cdab97f1	1	0	\\x000000010000000000800003aab56bf26f95f3690e5f06532b4ca01ddcd1d71eaad2fc11527a2dd634f7c4a978297314179a1debad77a57c5c4faa7555855435777f383a790d13dc8fd740487c2322251844723fd28198dc46f731cfe153cb56dc95bda2274f9c15e9fa5b38443586b464109779cc79c947d3b8b5a6232975c55a42b198274c3cd34e2265c1010001	\\x4eac4df7da34c46c8fe79ab9d1f5b320827f957f0c725c3c6dbafa9165b36bace9ee73337803a2ebc01857028c36adac6e268d9abd6c4d395e21e0ba07825605	1657802258000000	1658407058000000	1721479058000000	1816087058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x4b14626a2b51fbfc158e104e39b545722f36504c4f0503636c65c19665e2ad5bc46fd6212af56586d4a60fdb548c25e98091fc742154e5957946390a72cbe4fe	1	0	\\x000000010000000000800003b6d1e528f363a62837200396fc0b590819e8d06ea2786e2cefdb298e3f1af4fa32658c19b342d8eb4e242fa560b743ad17d4e8ccdc623ab9bce4cd68091f1dfa0f13a8403483b5d75488463bf29ad493e48b06cfffc7e52fa0ea6712aa6938d0c6d156fab0ee45e41c3ddd80c6a0657a0f97b6b8ae987b0c3cc22bbdcd8726c7010001	\\x88de7b7b16d9da9162bb48a0cb97df4e29bb7090c736480f54989b339338d12f6c31475326b8c33cdad238d19a598f3e733d004226ab539a042b3b90f8d50d09	1663242758000000	1663847558000000	1726919558000000	1821527558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x5560b03c90a0c172334523c5829e1ac7e95f9de48b2004c33ef0502a0be908c87d8be4b1a6268a69da9cd9bec22e7047550413fd48455dd96503c4b00ce5cc90	1	0	\\x000000010000000000800003b69400dcffa0181832e5f50815bc21f541e9cbe3dd709475ec3e45b8924763a5843a270bd5caa031dbf346c2d10151cf38026e9e55add131ae714002eb503a02ad3c66957e38d2cc14dc035e64faa0daa616dcc9b855e36d5a6d6e1cd6fea15604c8c448cfff60bd321e87b417fe4ff46370c57f032d2be97a2ff2e9090fe2cd010001	\\x6957ccc4c9a42789db58f962d75a572deaec930972f6dfe5ef76b9a58f1b8f638f35308b7173d8b1077bc85785a13a4ff56a3a2d725269a93f07776e13313609	1660220258000000	1660825058000000	1723897058000000	1818505058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
41	\\x5790e4ba3075cafb27cbf9ec302af9ceef93f60a40320df063f97a04ac581c7614e84f6a880ee045a9b01c5ed55072044cf888b233aced713d97bc0664e52947	1	0	\\x000000010000000000800003c07e157bfa100540943c9481a0f908424874c8b7d06230366369a164dbcbd92d1ea65d45bf3f45ce6066352187297ee8f8b453ab948b683bcdbef858cc8c95a1a14379ea2bd8d2ea79d701dc22793e48e7a5d0f7cdf874f9c66a04cef57dad126d0b39c8967c01d2a54bce0cfe4f6760797f56a0da1cfa9084774b96d32e8e1f010001	\\xa977a6e6eb8edd69704c3e64674133c5389576d2c334587292bf5266b52775cfeee8a511dbcc5d230fa75d9d3334fcf1b1c4c0cce1df2b7ff377c3317ecc9c0a	1654175258000000	1654780058000000	1717852058000000	1812460058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x5950cb1459e28f31945f912b34f943980a3251c5428caba61dabab4e145835952405ae71459bc9936ee7ad761470bc3489e3e74ed219884484793f7c2b01569c	1	0	\\x000000010000000000800003abb8d29905f296e7ce9da0d8c91051c4e225d11c5dc2a1e93129578ee751387c774484f456a3b3c5b1ae958f474d12c2a8373b0a7a829a6907fb180b0105d9184ed60ba12b6f8eadacc541a8625b0e693fec97865cfc97a899db642cbb969b8835b17349a463c1907454e2c6684e8f19084291ad2e77033f8f6cecff64033dc9010001	\\xb76df833c3086862bbf8d378e6127e31e0f4bf25d921009191b56928aea84e9e562fdd27d96c310e3dafa246b49794f8cbdff2a02bc634619861cbee0481f501	1650548258000000	1651153058000000	1714225058000000	1808833058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x5c8877dff94c1c9ea409f8191f605d717c1034f28bf17d7c0b106d7e6134731acb41ddc5408b17e7df007240b162ceccade1bd401576ac8749a4d6932c08b9be	1	0	\\x000000010000000000800003d36e0f61bfd7d75b81b6d6bf6ea89d8856dde10a22628b7439ef319a023a115797d0d1d050fd3333bff16fdbf69cc8fae09854476e45b4966e87f144be0a6b0795ad190a0199ecc2f04c6d69912d70374eb18c0a91cf9ecf6fdcccc538696f5341ebf1d2e0258f1e70406fd67905fa2e2a19d9c12386c7426617c0960a1f9741010001	\\xd3f443144606d73dffd5434472d6612ee4add82e1d4d3dc16a3d47f30eb46f1d71672f655c5de85585b8683fa53b5ab9454630c157836117ad6ef76ebdaaa306	1678959758000000	1679564558000000	1742636558000000	1837244558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
44	\\x5d3c0bfb4785aa11fa6186c9b6592d4f4e5cf3816e83ba1ecc55106dd071947f3a913b74d80ceafa2d1090ad03fcafd8c926c2ea4ade048a920d26f5e8764202	1	0	\\x000000010000000000800003b7bb199385580a5b102604d4f112a4d68c7f65bed8f65203584970e11a2d7a674f63b7b4f5629cdf4e384e4a63e7723892c7cbf121c1b85dbafafbdfc64af47f5557288725615dd27aea002894867a34bd48f8478662749996d7da0781c66c6b2b90c1952cce29d1897ce49f9a4257461d0cc888b31687373922d03d02dc5a19010001	\\x99b609b95975d8b0d32a7a54ab4101c6f99060f4258b51c7ab12e39302af505b70e56eaeea056a7a4a7221f202100e44a7cf80c9dd9b36d9d273a33c44323e00	1652966258000000	1653571058000000	1716643058000000	1811251058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
45	\\x5efcc4d11874d9ed669b81da01a304ad90f59961b2ea0d429b0f86846466543a4148b4ea80d24eb7dc3b696772eb629b9b3fa63e662fc8c5626a80fbc419423e	1	0	\\x000000010000000000800003dd4719eb8499748819d4ecf034a4465674ae56b78cc01b7978501e53426cda15e738269550845e328fb8f502586458e6861ff5f20043e23927f407d5ca06b3b030e27046d9b18e6bca6bce26bb712113406db744e83687fd37df7d9fa65b445fee753af451c7d549ce01184468583035424d6f6c7310a8f89368b3cc173bb905010001	\\xbf02ba5a28e85f7832f859f38d657b9059d7749d6470ad5fb88b5d8b03136c04ed554221aef8b2ccf99b80008ed77c19cd987a6ed36ad356143f55f22e565d07	1655988758000000	1656593558000000	1719665558000000	1814273558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x63d4e6ebe202c956cbf8b41e409fa6a4df3a88d4188b6c43666c8d979963c6a47e29bdee5767034400bbbadae4fb3fde06e14fcf3dca135f8869dac12f39e647	1	0	\\x000000010000000000800003a212d082c833a369e2e46d16ccb2ec9be9018058dfece840e595859b628a7e6a0fd70f0b0e4219402faddb001a89e9207b4f140a1b6e952997bc61087d4165e72e0ff2fbc8a5f08bc14d4baa3e1d9cad646531288e4c9b7f1d1b345ca697fc8241d0812082b4e178f4ac7a9d9312586fe76477dc28331478de619d41955ba5b5010001	\\x304769e5ec7d799ef9cfc85862e6f5161b155fdcc5615ab558bd3e4e1a2bef0f8be840a8eecc34cb0d875bf852d36b5da034f14917f33470ccf72cf521a0b605	1668078758000000	1668683558000000	1731755558000000	1826363558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
47	\\x65fcc4b71124feca02d2016f11c4116487bd0eac6a11c2d2124621b1f9299fcbc5bfd851a795f5c879222a239e7fdbf89ffae013e45801552a6dd2b4412190f8	1	0	\\x000000010000000000800003b6a1368c216594b0b990f3aa664bce8e88c44a0fcc9185ca44cabfebf4fa54513c160cb53613d3c6a7cf3af2144732e2b1c444b7eccaaee22d8acb975fc39429fb8fbfdfc46727afa26ec3e48fdfd97c9809cbf7e51104be046354b53a028c93384fa2f1fe7613bdcd839a4ccaa648c3154a39003632260130a09c3a3152cd39010001	\\xeb3a2b629de808dd180425cbfaca4929e987a8bc04cbc6d2c77d209516fefbde60c417efccf5338fffa2c28725c192f828ebc380f34718effd61bcd328926706	1669892258000000	1670497058000000	1733569058000000	1828177058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
48	\\x67543e7dc1aca7dccff1f03c08969a37ec9f32b0bf5f7d2e5e72e393aadb1b3b050a0bcd5078c28d61af8a3742a27dc823a056a253b01ba5a7773ac68af6bffd	1	0	\\x000000010000000000800003ba4b6c4246973329b69ce4a8c7385bc231120bd13e3b7ab5a18c6d5ddae915aea36c72fb134800156d28a5f59d3cdc071aa12dc17044a160aa8ee4699e76914395b1d5aa742a11aafa4ac626c95bff709c6e3b2218e53cae985cd99f0d7fc3b61edab1f5011c55b1df18f3d7491d274c7d60527fe4446e19bd7af22899bbad99010001	\\x029327a76f330e7d9de5bc2db4835fda8574c71ec3b61d2a2a93c6a5caf431374fba97cbbc039df3dcff187696ccff55b098b333e7c9654e159355ae00aed901	1660220258000000	1660825058000000	1723897058000000	1818505058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x68d08a539ef767e5759e026d8138e6bc65d454debe5c857f006cea4e70aa6c6355887a0cedf68a738b9b7ccbd88b10ccf5ec2c4a83ef505b365366ed9a53df97	1	0	\\x000000010000000000800003b7a33a14d6ca9987e8f1ded901b2c0612ba5154db8b53723ef83f10e72f8fb18c24f6244131b27062261e0024b8a2420071b470a75ccf2fa37d8b36f555ae58ff403a4446f14c1068868c12e6d4cd1f74706b21d8fd88ada0e3e40bd340d0c18952fc3f5d5c47a7694e377afa6f8eb06f4eefc056903989d4d9788eb20b56267010001	\\x1ab73c5e6d88a2aee4108e594568b39c60494435f6cbc15936f374ef3ae315895f0b9d31d19a3783e80dc4b4f9fdfa5f22960398645cc2e0f5973a3fcbced208	1677750758000000	1678355558000000	1741427558000000	1836035558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x690ce5f7fbd39899e8fd3b14be18dc52513a8422c888482eee47e0e7175ee28144ee9dcc6de8135922d30d933dba69870d46004e81bf30de59722194a9527ad6	1	0	\\x000000010000000000800003c517ddb653cb26952ceda5d590f3b6e2736bede0dd8bd68a5207f7b597bf320d6b6572c567f57ea7458c928e28e2feb1d561ae51734a97e804180750b409d1ca74fe555a7fb94cdfe8b4aeba30a3cd2a87009d90bd1d22a715e9cb9e7871b270b454e6fcfa17b3ff726328e85283ec092af25203d92be58b3437fa5d8288cdd3010001	\\x78e0f06cec6890352cc6579f297cd7461329eaaf713009a09b6abfed4a96301e87e528a89dd387dfc6658136c146200291af2e33a135a723ee56375a3ed37409	1661429258000000	1662034058000000	1725106058000000	1819714058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x6cccc802bc339204a9db1b07f41dd1602fc2b361c2e4590f08bfb720db1921fbfd3bfee30c4105b37df64eb40631009dd63a1b469c2eba19d531cf7e24bec07c	1	0	\\x000000010000000000800003ae1299956b87ca6de8c768e55cfbd99fbfa503f1d417a7e13c78fc9eb8281d9567079c1e53df674a96f3c01f9dfed37fab977517c316987628fb320c24d9e62eaae65d2e3c5f95c1808fc738de3288e27337237e7ccc4f8faf8020630b0f5f639334d0461e53e9269326aefaa5e649c5113d6d455a72e721ed6494154d089eff010001	\\x9a812d77a45b53c62b7ba1b608d20f1a8ffee36512241ba41470d4501023c314acfe76c5d6876a26321273b7cacb880908b04ccee14bb5d9bde5583b346b7501	1648734758000000	1649339558000000	1712411558000000	1807019558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
52	\\x77b03c80de7a2b9a25ce2ace71412ea3af598dda641c2d085d147564a70d17825f8e9ac4f2884eceb8cab54ce2f5b89261592e11d32e514525cf0a33c056af50	1	0	\\x000000010000000000800003ab70dcd1a985e1e2e549e980984bfaafe125d40737f344574e40e36a87ef05e4e4acba326d3f99965bbdbebd62a3fa6e29c7598910a67d3b04c359af821bbccbab175b7339210228a16397047266076987d64c7d19e56e4937cc0ee6819f47faf4c549946e4d8c924c21429bb735dd8eec6c29fa9c9b139f2d0f70108ea08b05010001	\\x450d878d36b1f157e93ba0ca0b1c27b6c867839e99468e66cec6fedfd808f8537821ddc839c645e13578df20de4cd64d759b932d5fb923d230ce9416bb9b4a01	1668683258000000	1669288058000000	1732360058000000	1826968058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x79982d3332d25e6e0d5857cd4993e93403418c8873ba0e33f7e7927190c4725bed6bc382a0d8001623ed9f79600d7f249feeeaed36f10a02bfa2a59a15ac5db1	1	0	\\x000000010000000000800003b7367c7517d97b4c3564fcb7933f8100ebc43b71eab3e7003d82554dcb3ba8956fdcb760d9729382a294658f570dee1ed12adb0e733a00ae36cfafc80a2b2ada7e184c555e74ead684d80669061a25c334325bba06ec815147a0c59986fd4794d0b1b23b5b1ed301da16404a6855e5d1f0d138c71c628efad978d26f1f6bf5f5010001	\\x8e5f64ea07bc2e08bfbbb40e8a2afa6a6b13b60ce5bec528543b0409fed75350744dad7deb617ad801823b4b7330e96d96b8df2eed54e33fbcc9089dc2d9290d	1654175258000000	1654780058000000	1717852058000000	1812460058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
54	\\x7b507556f5aef95375e6432a42c67471ecc273cf7bbe3efbba051f3a8b81470b3a33e3a0d6d71f685751e7f44a37ac292587f7a9d6c03339be5f134749fc5fc3	1	0	\\x000000010000000000800003e98e832c3afa732fdecebc01902d5abf9bf747f583668dc0ea6a13a6931ce4d689d82746f699549cf92267cac26a51a21afe3d389f2e4867abd33409b33648ce51ce7b142e250719de29806e6f4a29c1e6a5592089769441d130d4bf24f69a40a120692ab59a1ebf50862842d5c579e2e39eae8cb272694de50f91132e3d5571010001	\\x6ec26c8000b92cbfcec4e637dada496a704c39ffa47c13c0858887323fc43ceb04c6a5597d5936d6d7b7f91dc4abcc23198706aa33936cac0cbae3ed3993140b	1662033758000000	1662638558000000	1725710558000000	1820318558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
55	\\x7c90250c4311035a4891115f6fc158c080fc30f6876254a6d9cb774855896f8b893a43599f96778ca9d4c91fcad0e878bb25372a2c2ddc610896ea781e8433af	1	0	\\x000000010000000000800003c28c6783c7826e5a0285cfcb6c522c4d0158a33e3496d95a5d010386b05ad77dfd061fa9662cb4df8ffb02611d6db57368dde22ca5771ed1d25f0bddac9ee47bdf0f55eebcd343b4dce1d45879daff0b6226a0cc790d7271c41ac3df17cfad8e2109fb348c3a660d5ca1285457fc60d0cb0589b93a067071ae5576bf261f4c8b010001	\\x8f0b1c4b26c5463b78dbc06aa377613e066cf18ac374166ba5f0d657601b6c2c222e93ebb0e730c04a7c04e7192fe34c7b8d4c24662e1d485944eddd5f646307	1659615758000000	1660220558000000	1723292558000000	1817900558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
56	\\x7db0b3cd03f4abb0fe5d89fc431ca0d6be7993eff4c7b900762b8a778ea76c67d47de17f53fafa4778f5713e829cbf52601a17af4fb2e8b1b49c4a5b1c85bb86	1	0	\\x000000010000000000800003e3c4a656268b49f5f228a0630e034637ea9153c79248601c58c5427a8ee67978706f393461708f9e6a640b4a0e90c4147474cb138ca219f3dc463d76a825c455a875df09b68a091bef9bbe4afba9cb94b6066e183ee58daa52832c95d4dd2193097730bbadadb2245216ea042e7f92409e0fd4d1b91b8c4bff6228867e4cad4b010001	\\x0b955a75a95df1eb6ecf8cde4e61f756a8fa84987da58dbf6bb848c8daefc4f8821de97aa10cc50cd0f8c9caee6f83e76b480ef65f5c373dad7c1344106f3a01	1662638258000000	1663243058000000	1726315058000000	1820923058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
57	\\x81d87cf8cebe0983ee34581330b7a94f4a75c31a6387a3493f974bf49b42da26d142718911b13b2e565a86ed67735090f80f21316f480a6eb3d5218b75a4a1e8	1	0	\\x000000010000000000800003aaf973b6dfd13bb3b21987028412deb484e398584fafbd498bd247296f0e24e3f6798a977dab485139def237f6dc97b6f931dc4eafb029b17a4f6f6b0e39c4ddff821c7fb53847f27c326ff089048c318d0fcf9921564d0e4c8a4d2d99b30df7529466ea155a51e9a88fbed85e8ba7e980b39c6e1583495cef94e720ead75a49010001	\\x970870f481dc8bac8c65f5efc9874774054db6dc6b79cfdae42e84b60e03634771fdc45afd9539f4b6336de10ec5bd48a755ff2994807a934031d836a7c20501	1660220258000000	1660825058000000	1723897058000000	1818505058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
58	\\x816813be9df7f1c405c4248d02259b5f734cfdcb5e52262ce6f74f0c82633d8bc5f99d4e0629fe5a08bdb8f73fae6bb51a6d4182f63a0e4d63ab92eaf48a9c07	1	0	\\x000000010000000000800003a0485f6a9e1f568ebcadac9e90392b75070b5c977b1953c5f00a6154252073207d126533717016d415c29fb7d2bc3b86899aa94edae135a94aafd458f556d7b2be0f4c51cfa68a936f27710189ab15f3509282e99629d57f598f0ff1e90c597fcc6435f495a17c71e39df3781d3e41ccafbc080aa425806e18278b50d1449433010001	\\xe314411454eba0e97a1ccc160d40ba5885d1be66fd420788331b1ce39aa38137081159d678af5cfef5bbb8d1b597ccc457558f8081f9bb7d736cc321e5dd3e0d	1666265258000000	1666870058000000	1729942058000000	1824550058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
59	\\x859428b83cae01de2fd6595370cb90a7ebdf83bbdb73be4f605112c0c3e6885ea0faca6bd217855e006cb5109ae1f17e69d25347bcd58f4a6c819edae388bff1	1	0	\\x000000010000000000800003bceb108bcb1dfe52eadbfc9a6623e230d9bffb1f1a4db602f10b91e2fb9734f006c69875c1a4963044437125b913fecbd524b42b1be3bbf4dde5981ffe7eada4ef29eb080a0e05722e9e0f2f184b1cc41e9179ff592976812e6ee8398f423105c26a1753339c8eb8ec75237651c109a1d047f07d8ffc613219b294186e446d89010001	\\x89d391d62cab42a9f0884e14d33ca7eaa4601f97fde99803983c068101e014ce5b392a85d94dfbd07392750b0989b21883b4c7e10e827e310c09480b85832f00	1678355258000000	1678960058000000	1742032058000000	1836640058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\x87984015aa973a121af8cf205cdb8ad2b9c1250ce2852317db20a273c1f9e567615f826ee668d552e6eba9170b0a9378570a12f5cfcbf1f204fb0e39741cfdbf	1	0	\\x000000010000000000800003c416c1cc71b04bdc5044991fe4813623dba58b259dadfcddc3e200dc0e2dedf3e6ef5e2a22d1f2f39cbf2bf6d6907ae53aa5fc9a4acb828b24f526e3699f6396f3c880248d6418f091b8215df491254d02d436d4fa50156effb490ffa0ddb7b5466ed9a9263ef4b2ac9e7ec2256414266fa134efce4703fe574336d1050dc6bf010001	\\xe76a11687d9b94e4fa9b4c0df5015cf8dbf740d739ab0e56f3e5347668d540320f2cd176d9099be1470e7cfa4f214a7398b6a2dd4323839b4643e5dcd8769a0d	1677146258000000	1677751058000000	1740823058000000	1835431058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
61	\\x92ac5e6d190651a4592b34dc279bb30ab4a18d4aacfb1e13f4f59fe904db8771e333cf6b9293030003fd9640f563c5ef7e49f392a0c83b4f4987fbcb2e43cde7	1	0	\\x000000010000000000800003e1a5a68363ea97e85fca899b6fd43600ed700ec3d8544d5bb2cde4af80f72bc03722723c621817a0895bea18769bbf639816063165be46deac51c5f7d544fe04acb78844dcb7e4daf7d625f6b22c2a57f4ba327bde419c3623469466b26b974f48b38174bf14dcdeae05731228208cf59bfd33929f4ce9f04fce52ffabd33f0f010001	\\x75946e18691378c7d5a3ed3be380b408ef09315d0e78ebafd35b0c9899ebd879aaf6eeb3a741de26bb9315a46b0e9adec9de2def0d0299bc8bd55478072d7e06	1656593258000000	1657198058000000	1720270058000000	1814878058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x93d4ca092ca129ce8d751b9442dda7b7b8f3eccee91de14646e3d68dc18ac5b89403e5158fc6c58a3072fbb34350539db341101051063700431831d4892fbbef	1	0	\\x000000010000000000800003dfcc60bc3c27e09017d7129300c510a8075feba3d6cc05dab6c7c45685557bbe6104d8916615899b2e9fc3dd80086260cdafd291eeec91f9b0f91149a36bc46b6bccf7b6350289123e84f336158b2077bfc34e8c8dd6b4e18493b045486297cbecf7e9e5f9b65e18c67337051b140d4c553e1282895d9e1240287420a7f6f603010001	\\x895e2c59a136427e80e44fdd0fc016f4a9f4b423b315205e8b6f8d8509e3da8e98ca35e2033dfd2f63587ff0e7061377a2302261f63f900fab87d9b31852420c	1658406758000000	1659011558000000	1722083558000000	1816691558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\x93f48acfe772cd41c326ca616a290167dfc4a8121efae0cef09dff2a2fe248da7711375eeae5233c171456068a740c2a8adf77a5d570704897652fb0d1fd44ea	1	0	\\x000000010000000000800003c92904585070112b9e7c95a4cfc5c0ade2749bebaef387025b77e51d6cdcc3ac9ceaa02f13ff0f48abd2b45ad079764fcff8a20377f47529ea5a4266fb0723096a09de7506f34020126a37e9b0976cb20db8c71bb6b917c253fe6af3556f4a39a17fb98a5054ae61773dec4ad0e42c8b6cf0ed0fed05549e796d9c52e4781f69010001	\\x4968eb49e34d1e0b3412298aed2d4aaea979e7843dfb97a52ceeeda7ebfaa1f715298520a15a2e1d3ed678f9eee1a3caeb848a5722746a2fe3d5014abb642808	1678959758000000	1679564558000000	1742636558000000	1837244558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x99381e063ef65a01f1c6d216101996aa2492e757a67c2d40a34ba473b4b662b4cdfa8b1b406734b7dacdc71a0a3dc168d78c0d4cbee54f212fceea2e952402f6	1	0	\\x000000010000000000800003ced51821b2fca573c7b4f7e2e33fbaedeeebbe8fc2b63937e9f2959926df9ce7d54e8da61a90f7ec6b56c2b0ff77f0c0648e95b89a0074133ad79c85d5aecbdea438c28052dbd2f46b8f446fa82c59d3da7e10658d4a42893f0d3fd0c71fda026ff108968805e10421ed5079466858abfc07999ef0cb6d25a5563b63109d29c7010001	\\x6341f30778dee266ef7b61246e3784d426aab1806db75c5ce50bceed568f97c5839071bea650b722259aba2b4552bf14751dec4ca23977d7e8dcabfe1572fe01	1662033758000000	1662638558000000	1725710558000000	1820318558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\x9940c5aec6e69334557c165e1d249c3c8553b268fdb66f408049d17b7be9798646604f123422d9a3c9fce6c7d16724115c5260c30053f25f006843c2595fcd64	1	0	\\x000000010000000000800003e1c9dbf34124274b740c1a63d05150ef25fe2cea2d665eae8bc0da8d44b88636c67ed29b6877d8db06dff8641745a9bf4cbd00d8e0620975bb756ff58648657a15f4d3ea99bda507b3092e975dc0192c8217be78da60e2cbfe4f3ee1c788c66e9de7a13554cba4a6639dc67c411da1d817359fa3e14bbe7f347f6216ad904609010001	\\x0813454448a7d1ff94a6c532b418a3f1d62a63b13ab1f67bac9557f81f6ff1648fe5bf6dca29cdeebbed075679ea294b2b619c331ceea5aa5a8b66e70342a806	1651152758000000	1651757558000000	1714829558000000	1809437558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\x9be0934d09d708004f41d0169d4cdcff11c691df16b2fe437497706357f87cf761c1f6bca805f0093c9fa696daee3f65f16984f65b26d25ed978d65d31dbadbb	1	0	\\x000000010000000000800003bea8e33e01511a6532e1f44be735bfb4bab042f2a1c947daed14126e31a663fe39dd50c9bd4a5a0c3011c342a43032ffa1d7888ffe4fb77e10939feb89d8595e9e32c82ad54950badbbe34262ec656850e8499ca5f351ebdbca7903029ac4e821a1795ece1179e7d95d529e8f44ca92bea857364f1b547e73be956e0ea2f981d010001	\\x231521574cc13302c50bd8a1898351fff0dc3ec5280c484b4ce4028a548088de9da498e871ae5739ed8a76ee995c179a638b2fae84900ae1bdec5648cd4a570d	1674123758000000	1674728558000000	1737800558000000	1832408558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\xa00c1e7f5620c0e91caffaac0c7374ee002228f972de8f7ebce5d7d897e35c8f71299af81fc612b1bf7c8ff5416a2e7f56d4097ca65efef40749df655a02304a	1	0	\\x000000010000000000800003c5145a4605ad673966acedffa8a02dfeb40d5c6fc23e8c0b92a7cbbceaaaa9e500219bddbe4f8a6c4e7a1555c07e42b67bcde1af94ac034e70d0392c54b3585fc8f0e5710bfca30a8160e9aaf0c1b1c2221bba1702a8dbe0e6dc94b041ce2cf53b580aa85fb65b7fdf32a2111d9763b0a49991255036b8e4250d2b02ddc0d0cd010001	\\xcf399d7476c2a0c8afa4459059c8f4a0e7b876b18f4e2216c1b4df3b868cbc328f540a901a03530cc93e5e84a31de9c98fc6bae033cadc8e07588006d679d801	1662033758000000	1662638558000000	1725710558000000	1820318558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
68	\\xa1c4ff1de43cbb25bc61c4da624f9348a99eacc9b15c70a863ec26b225b3f4bfe0987049649070a4050ac2ca28105aa620c79d7c91316b98f4923d2187f487b0	1	0	\\x000000010000000000800003f024895f2fa86936603129044116042c6803a2fc413ea30359cb78697f1d93c4e10c8fc0d69fa27b836b65e105dbf7f8381b9fc0163dc9b3e47e210269b777b083475f70f26d683e9803756f435849e94f21e4e4f16fac30c35658bd1ce9e5255f0b1427a7544d847e6899fe3ddd851e7a0897233745a3d6d281638ba2a9421b010001	\\x7b2778ff2c10e52a30acd81eabe80244707759721f66a2e877d10e3676ffdea84ecf83e1023870fd44272b8934fb8221f93b1eebe2475b88d5f26610f38f890c	1658406758000000	1659011558000000	1722083558000000	1816691558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
69	\\xa41c2b6a94dfcdb1e903b804fb3567c56452030966b62484c6c3cb2d3a8d46534b40251d7400e7bb0da24c8da3ff5476bf86d0c015e2937807433cf99a90c7f8	1	0	\\x000000010000000000800003943d346ead1b703918bf7cfb9be51e79166349604318726f3070ec4c79f9cebcf6aa28f0a69d72b3450e570a54e61627a80917e1ed79179784ce88968c4e8dc30984537936bf17e1952a2ae493bfdaf0e7a0a64737ab62145b57c90f3f50758dc719015ed0011f27155e90a781505c1c26de1e5da8330184834c2c0e82ca8b6f010001	\\x46f463b047c68ac1f36bc8b99a8ea5d630f87c9e91e59d174f398d54ee6f61632f8613f6ce6dfeba59924d11ca06fe47307bf92afad650d9dde0d2e6c61b6f08	1675332758000000	1675937558000000	1739009558000000	1833617558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
70	\\xa804470ac25213f3c0ad0bbd0acbcdf816c48af43eb00bb7cfeea51a6c44398ee7bd77a9f4b6dcaf984d9419fd117879655d68680ecf59a75760e0f2354d0b6e	1	0	\\x000000010000000000800003c8accc1d5f49bdb6116b13a2906a7763b005a226dbadbb1e5a01fa96a0b4fabc141165ca76cdff92cec57824e8d509be2cc68b69b6168e88a16790172131abf07acee07143781bf8c9ad0577b0b182720aa57aa9e5a5d8240670e6d5336df31545e6e9f63abb2735bea44c4a3a37caee49f8ae8c04e4d65b2c8b4c7b4dc09bb1010001	\\xcd25acacd03561e8112c8f05bd3fcf7fa1004c77650c4ba4083e45ef0f920f72f04c63ba499e5dab39527c9a8779792cfe15c7fae38e813214f80294e8db840c	1665660758000000	1666265558000000	1729337558000000	1823945558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
71	\\xabdcbf9e16697118ffa2b5376a231a7046b5cca4f7d305594da3680c2e91e94d28b58b8fb39dbdf2b32148f87758bb13eea9ee98c35b1526a48eb564b6a30be7	1	0	\\x000000010000000000800003bf7a4cdc58abe16ac1cbc9a276daeb669a9aa687b8d569e6883122f9057e267e19f5f1cd1f74587e8961cc18bdc89f9888e5cbb8acb4002752d43c01504e3814806af87c2865f9e35e971de4f6d7677a0453af7c6341d378499555666017129b8fa7b86156a41cc20e594b4f48bae69813d0c72b9ec33b028c480e93b7afd485010001	\\x8c0ada5acf25197b90001f3e65b5515e981e2880e151e438a557995f008ecf187f3907b05a16c2f6e7cbda5bb91a08e4a5e9b5dbe4765157c4b950c97263b403	1671101258000000	1671706058000000	1734778058000000	1829386058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xafb09c7fa7fa72e9f607aa0aaaf9ecec4d286b12fbd73910dc0dfb1677230aaba8ab74b60c1a82e1b90eb81bfba57ea2b3609e1d1b4b0dbc362ff5e9376a4da9	1	0	\\x000000010000000000800003bfeaff3f58e670ddcaa7f180a1673d8cd75847951a86e3047e508c69a23397124b61b2f2a314b0540f7b8d1aaf0dd4c5a680c6193dc344840529b38602f943c6e2b88679adb6034fcaca57c99132e1cc58ff916a0f801c827977b20e272b5417e3262c8de1ef99cbbaf6d1fd4485c2dde5489696bf96dae334fce9388d9ace2f010001	\\xcdb5f6b16a6cd44897c84f3259fb78db6719e7ab2a479957a14a22f2518559c9809a5f337f0ca3b9e36af42de2b99465d2ef41b18375653a1a3404d5828aa90b	1674123758000000	1674728558000000	1737800558000000	1832408558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
73	\\xb0081c154103086480bdcf6d86a2180bfb2b38cd84cd9fc942bed067bc2c69fad81b7614c483cd5c3c1c5846b84871aa9f9d9b39cfd3dac273c23de00c8e99af	1	0	\\x0000000100000000008000039cb8566309aa0ad4d7e6c10060a709009341ef62a3443143ad6a32ce8ff2de8dfee7b189fcffa4d08b366de81033381ce98da572f840c81cd7577f03b02f6ca8c7bfe6daae952d53ef8cc6e41b963e4ce73ae3c153aeb1319399bdcc64e7cbe7e521283f53aaefd22d3dc116723a9396f73939522aa64755c2596d30ff876409010001	\\x648fbc2119e356692df902961496ead841b7141cdf06a0907f24cf621a4c8d2f580ad53d801ecb8ec8ab38d8d172c03ab05298a702c9869b19863dd6769f140f	1654779758000000	1655384558000000	1718456558000000	1813064558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
74	\\xb590fd2b551ee7dccc84f03b0f2ec9b2e100f2be0d7b94a1129fad953a35bc9ea86b10c819c090828716dbbfbc8cfc6d549116c1c5174e3853d305c1b24914f8	1	0	\\x000000010000000000800003db21e21f11b965991ae3a59c2a51767dd16a7eee52e4cd88a9610d8e66b08b0bca0d6ba0f3785cb52ef928594c6af8f485c3b6326d96bf6b43955a63c08d413dcde34457320e968bb97718c785a3f5466d72d813ee68c8164d7620a7296469c46c271806236482fc9ed7ff35cb00f5dba1fae95e5567790bd214505b8e3a81f5010001	\\x0731239828ed46f8a83956914fdc399585958837486727e7bb41d8b2d9fc7cfa6a23d1b68d83fcf6c4e647daf202c11f3d40664e603d283d76e7f8bd57ab560d	1661429258000000	1662034058000000	1725106058000000	1819714058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
75	\\xb7cc640a3f87d2753afb4e3df173e25a02965c79445d5a0af8655b68abef7552d984e5777f87e4fbc83152888e70fb642786201536e6108824fb5dc94a819af7	1	0	\\x000000010000000000800003e44607b4861c7b5ef36eec4f21003e745f9df08bd094bb9a7280c6b08b0f1a500e50e6327d997f4597bdbfaa35ce2ac12f33a3498db14f9a08c3a16f3e566071d747d60793dbba77a0cd4631061a89832f3dcc4bd58703ca1314b14df39ff8ce18c75b504cef0fe0f925b5bec25955594bb01b349390956797fb7a63154bee21010001	\\xb6ded5c85dad4124c4667f356b9750fcbb63a225a09eca6301041a6e4c8e2afa83139228b580bcd982ebae60d5c2810335680e7629599eb8889678d0c15ec901	1678959758000000	1679564558000000	1742636558000000	1837244558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
76	\\xb9448ee73fa477f0935bd612d11f50e7d321cb7d6c2b6a977c203cbf5459ec5e54f75c7d891b35fe576f938a7d3136c06b157d27875239bacd207e66dc3c9301	1	0	\\x000000010000000000800003b838c5144272c9c68942e8f0363c1ba864c177de9b1d0b2ec81d7fcb2579879b501b39c9b1790ce6b380276d940ea43f2b5c17768cb8e9b7432b0a460bb3abe8ef400da56404e0984f495cacc60583c700c9ebe7a7176fa6f44d0a88e28c00888c6f9908e9593fd606b56c479b5c048e2ed75d468713cea7df2eff5a53346cdd010001	\\x6cae0cdcbbde3246053ecc6dce663ebd371e5d6abf5531d75388bc1b2431f9501fdfb2c83482e12765a110350fd920a032d7040c72c48bca283e4d09929c8c0c	1676541758000000	1677146558000000	1740218558000000	1834826558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xbdec991aa3891b4cfa0ea4494faa8652c88243202c5718d145565f9b45a2682cc07f1d60698e65bd04b64f6c1e6a793a4248e8b19e456decdd5cac0335fcab1a	1	0	\\x000000010000000000800003c2a7afc9ef87b6dd0091af30a2c48d9f5393bf83993aee1e9363e4ebfdde243fe337dee782e287236adc7c08968d0bd18346a3569a92164ff96cd05623a9940ebe297cd7d999cd905a1d866edaa46b748d81e69d39a8422c0363e1669ba1c88e238653e5882d7e0f7efefc43470d50b5fa0c095c7ba3cbe63e080639548e9c9f010001	\\x4e85bbae4e51bbfe6fd7f23481383fee1b1f0d69136bb6424a836aaaa18931878d70be1367efd314ee2c3a9354453355c3f229d338d88359bff14b3dfbee4c08	1654779758000000	1655384558000000	1718456558000000	1813064558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
78	\\xcb202839762b8ffb29e18209ee5252995a00e4c815beac0aeaa984c3701544d48d58b31891bef42b2097a86f20594307b204acb1eb3afba939355ddcf556b93c	1	0	\\x000000010000000000800003c0f49e4d7cd80ac062fd9da83391d508cb756a2e8e48bfd9f1a17f646f4c8a288d2f25651463044bf8f8b7f4c35c2c84516096b529c0056741027b6b96d9c3d387945ec0f58aef356722aefbbfb76fd1eb6a5dabc7bdc3dbbaabdda60f84ba3df09be1944d1b1888f1a4c54ecff300478112fd18e6712d4c954012b5e1005acd010001	\\x7319c883a7c14160e612852390c1fcb5693be69cbda9b8498ec7e201a1c0184ab0d98a6097662cf1276ba7c8292ae860ea622fe95023f6c0924677f0acc6b70e	1649943758000000	1650548558000000	1713620558000000	1808228558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
79	\\xccb8b787cae4cc9467192ff62fccabfe61308426cdb719ae2d68212cb1f9000f08b4e6fa990683205009b62bd945f569afb845daedba309a14456c5b439ba56d	1	0	\\x000000010000000000800003cfb22e0e8373ea57fc95ec43a0d3eff32b350eadcd650e9a9ef6b98f62b98aab395facaeb0d0e1fef90110e8598c1434d4f5576ff582977281066c7e1044f3f0c8c43768f1de2b14919b492585736c1e4c3e815ca54de5f3b5df0c875d51d2d97a5eb1280344bab96ff274a775de4f601345cb9b71e49b7644cc980f23898c89010001	\\x325d8227969327dc36dda728e24776c6188282e377fdc040b0eafc8ed76d0736c96d3a07bff02530d2318143fcbbb8106ffd5d29af472e480a2e6de9c62f4606	1669892258000000	1670497058000000	1733569058000000	1828177058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xcfe81f27b047e67c926941b347c1f2ab1550f87888f216ec8b2aa5f320d97d0b74e53f469ac4ef52f6b2d95a2c15f78140c951144747c327d21072cd384f5eac	1	0	\\x000000010000000000800003e79d5081cb7feed104c14ee92b3d9fe959e7b1b0a753d93147489ddfb5dc1c0f1d16eea90f97e15fe50774a957e24ecb62b33a1a50e75ea6fa174ecaabe8e1824e570ce9d9ddc3417c4275c1350117df25a12424ab7021891630414cb15576fb08f8bcc1a04498652337117fceabd1e8f17c2919bfd7976b272854df040a534b010001	\\x2303188d73930de415c3b6b145f778489c86e4fa26dc0985e425cff63ec8c5e0c2f0f8bf981fa3aa2347a90eddd5fddfe498c1ad56c6e758b18a305eb8316301	1669892258000000	1670497058000000	1733569058000000	1828177058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xd294f81ac58867e81e5091914aa161857ce70e1e8126dddff41f09e9202c78c1d0507a0177eda41d7166a0a1110cf2735095e27dd97e6fa0cde727a6870eca9d	1	0	\\x000000010000000000800003d1955159cd7ad687199463c82cfb6df6e941cb34583587419fefb6ef31fc03c4b2f059bca27e04cd63324dbcecee365e642ea94d7621789b2beec85d46cae94c627f8b2987c3f3d59b14ee5391dcb9f989775758dbf1e5e5177d94ac9a4edc9cea7d2fbedd2c11a8b76b8da682e15ccc038ff03f7066207e3ba10623787aa2fd010001	\\x8c2512f0c6a0222b1e45369f9069a731f876cc5716fc3107239659ce534fb54c6ac6b3389ebd053d25f905f2d2eee6757be74b1c8c79a2d0e11f98142e0b670a	1655988758000000	1656593558000000	1719665558000000	1814273558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xd838ac4120caabe58c4b8361e817901ffbcd4cfa9fb2752493ab6ec8fa54aa6ecaa13a478ac08f8f8442651fd3e91e5a9de2d2b8923babf877f36578b1e5265f	1	0	\\x000000010000000000800003b6409fa2dbf3fac930084ccad5098df665f229d02f6865a06494eaf0f218c7be6ff7425dfaa498987ef13d1bcda697d6009e54c7f0fa4cca1651d42fc9c99f1655fc475ff2cda5bba652d481f06a6b2eca350c307f980e7354b18aaa1cf1b5534e357d19df2c93791b6b1b122b55cfe3e3dac30922e90357970632be21658a07010001	\\xd8711abef3db7af53163a1fddfb7efc66e80526762e9025444cd3c57d2e6a5ac7dad48a131dff008ed6ee9ec6a333c7a93556e908a71e7ffab0a2335c840a704	1647525758000000	1648130558000000	1711202558000000	1805810558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xd8c48e8227ea08dce45f2a649ecb8e660382b5cf7e842fb0f1a9ffcf769f0007e56dd8a55557a062f8501354b4c1198a7c64cb13aebc8266525e036f5d9ce9cc	1	0	\\x000000010000000000800003c5784ffa09403c9fffba4e273568686968252c63aa3506f9b7160cc0482667ef660e5990e5a5a38205c942695b5169f85e072bce7a2caba402596af4530885a3a5f5db265c4c7a7f8ef78a90af54f23fcb4bf65903418135809b3b62c8c5cb6a2db88aafdda4df584cf93846d850d03e1e18e0fbc282b4442b37337b7727ad2d010001	\\x770528e06000154decac1ad581891b333a7dfc86a9cb31c94d397c98c2049e737a50c54ddba6d7e42d796e69e9c1e29174dd393460da11e803ee77c3ad6c7305	1672914758000000	1673519558000000	1736591558000000	1831199558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
84	\\xdbec20c4e3bd5f676149a7db5eed3118380b4b33b7d837be61d85df6768fe87178a6c23369a70d74e98291b90cc0b58baeedbc817ab84176b890aa83cf4b2662	1	0	\\x000000010000000000800003a790bc097359ac39d56f6a7bea58cc91e3c127bfa051fab5397c7a43cbc5af029d50399dadf78702e82cd9f3c96aac89dae95701582c3d96a9c43cf8d60643ef84de451e8660349dda8744d55fccdcf49da19731575dafdec5ecef2a854e1a928d592e6b6a7cda692d938b6c5af4ff196a544f5c48773395c9806a3da3552619010001	\\x99b514e08b62d2907177036445525d73f7d82045cde6823e07e76897a2b18f37a9e8da592ff40e8e3c71e9322004c4624dbeccde95b18d33ce785f3d3dc19707	1664451758000000	1665056558000000	1728128558000000	1822736558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xdda806d7d4f7a2fab2e6fa5a0a28f0de8f7c4a23afb622edd7a551f378bc2fdf41323c9e4182966d7521ad84e7c1c2b5dbfcaeee6704db76c2fb4a4d6e46e05a	1	0	\\x000000010000000000800003c47386604a6b320ad0fc4278e4d704ec9ce99ecefd05475c14d1f7639a67da8d8731c821e717947c8b44ae1133e7135f9f31126f7769456fd4afccba8f1454608c9ab46a2e5ab4ba2a6c4af303287da3a61b69f98e1e2fd4302c61e15d3fe35dd853f3874b2b2dd0da8c5e5c67befcf1a3d9c0b9b395f44634cf9704e3e5d3e5010001	\\x294b8ab831ffe7ff8732b19703810d8478563f9014247918586a5a6c24112b8ba37ad5b1545a7228eb825efdf73351d9967da3ee099674dd49c179c12f853402	1667474258000000	1668079058000000	1731151058000000	1825759058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
86	\\xde3c2c1a34d8e56b4d5451607fa1384bbf26f803d06fe26fde58be5bbbe16d6210bf8dc437eb64778864d719ccc35377bab2d4a52ba6ab3263e603c4c0ed6bc6	1	0	\\x000000010000000000800003c48dfde43ff433e332332924f98157410c7385c83d3bbc802b7c1c8671f24221e14bad6a365a0bc8fe06da503f6a043525a55275de76bb3271856eac8fbc1c4ae8a3b2391088f7074d362d1bbcec1b7a21c362b01714f1167192186b6ce5cf146be9ca54d3ce6df1128060d2fcfef534ac44c5421c43084f16caaae01ab38c63010001	\\x0b75b49c19ca1e87c3d495d69c025d13eb371e8ceba967ed95c1fa8cfaaa0578e2458d825b4ba0a97c94c8f728f8780010a591e40f9e86f670b3acf4bbd18d0a	1662638258000000	1663243058000000	1726315058000000	1820923058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xde408dc623a6202be51f3af0db80c8a81cc2f8f0f86a1659a560e02e95449e4648183a6bf1a2e7739a19c2f3ad5130606e49f1448e8ccfcc9521547208011023	1	0	\\x000000010000000000800003c610366915df58242eeacc241d223ead32e069d86b342a4bdac4cb2dcb89135643e555b3f6042d799fbd85ee5ec52c0023d81ef8c4972c2ac8093c61ffbaf2381a1accf0f24fab19d1193faf8723685569846c189c4b1051b468eb5670470592b6a4f939dbcac27da99accbb35fe2ba1c11a0c9e61e3a0db60b397663509353d010001	\\x57ebb97054afa2f2a6e840f6f708cc85d3fe193f92d0cda29d939556ab4d2aa200a42aeee4e42d7084d09330a7250668f840efa5a5f38c20b41803a93427f806	1648130258000000	1648735058000000	1711807058000000	1806415058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
88	\\xe2d00257c7cf409b33856a02f62866b6990558acde74cd78da13c78bacd8463ffc6b35f8e0cdbbe18d9400080c19d72b5b345d01768bfba5c660f99b4a39a432	1	0	\\x000000010000000000800003f7374e1fb2221c7370118b0604e45f4e8560f8b58624e36131426b35a36025464c05a0f7e6b3ea484a2bbad0350ee5d2f2971783a4f96cb006ea2005a868bb94bd49ba136a2692ccc4c19c3d959fadc9bd7a3be4c53260e158933e27230ee1b6f7f0a03eef6dfeaa549671ece448a8a8e8c97789065af457f8cd22568a4bda47010001	\\xceb3a997441c57ff3d6e33e3dce158433309eca6287ab5b809b4b5d29967e22505f073d9ab3bbce82966126478c3c48bd640a73240041fa1bc730eb15147490a	1674728258000000	1675333058000000	1738405058000000	1833013058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
89	\\xeacc9002d128430d24f620aad772062b8c26921c5155d8a8397ec47b7fc70827f40865f8dc16dec3db5c03f49f6822bf5a6adbbe2d0168204effdf0396f86673	1	0	\\x000000010000000000800003b22270b692cf34931c2a53dcb91ea98ae8976aa157b1a975937f8b45505827d940129da3eba8d1565067f1d91c69136c6b7f16b67e2da11fc8985e5d8f2835ed348d709db6a52dd18e617b8076f54ca508f68497bad2a69ed45b8b9a0a9c2fa3d9976b1d8e422c6ad692f4a1356a3bf2c554802a2a1b679568d744d2947ddc95010001	\\x2652247a6143d7884500b700e9522b2d939f71867c2f47c2a49f884959d903af8349ab36fc8b0a90aab82d094e8cf4b14f7a3dfd7618ee2133200023adef650f	1654175258000000	1654780058000000	1717852058000000	1812460058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xea942880e39044e0854f2b29c82eb57e26ef5760b75ee0e3fb79fd8bc2577c3721d9972c46f8c95645640f82c008d78141e990b80d70f8f59c177cf408786d8f	1	0	\\x000000010000000000800003e42780e0d5a45d83adc5ea2e4d064069845839134ef849f5edb4764643b0746592c4d859167cacc739157e30497afb70c40fbd210617bd59ccb7da9818a7104f08f0325af26638f6b2295b38391a558e748961a609865309a1dcf8cc6303f3471bddfc52dbbf42e9ca39ec7453c971fb1f4c400912f632062687bb2ab8141161010001	\\xccac49e5216f637c41ac5c76fe0d9709e7a4012bba5a0969774d4fb5c93081e1b4a19ecb1fb1a9e23c475f1fa66b65e77111e7274324a37a25e7829c260bf105	1648130258000000	1648735058000000	1711807058000000	1806415058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
91	\\xeab4a7531e495afdff611eeeb7debfea53bc574ae43719ca8ad559ab3b55ee5ae0e6c3028e18225ff6830c0ffa549bd54e69bf2970af987561ba4a9849d8895b	1	0	\\x000000010000000000800003bbff4abdeef986bf7656a21c83dd317b0e65eef091de57cd134bb2482c71c90b90145cabc53b23b8c0aaff23d3af6161f512ab71240632e86a2cb1e3495f6d05127a825faf57bb81c10d41896b0b3d1c30e5e2bc0f0ab7ed8ca9a381e5a375e6d3696e4ec2a0013ea1af8a9c6d303438ea1f0c07b28476a5145953afacc5c5cf010001	\\x9b10182132d5c0a576ba56afbca8903e59be32ef3a0c386735637e3951afba6b5c6c3da28460d8466eaf363f1f75e40711f001fdfc93e62cb8d78bd25dae6d07	1658406758000000	1659011558000000	1722083558000000	1816691558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
92	\\xee88c0498141714e6c588b54d898a8244cfe3cf18b348b094f86d8b60df59dcefd10142e7251122163a83702bbb781ee1fea132ce52f229d4ff9ec59d629da27	1	0	\\x0000000100000000008000039904efa9fd2a90b832e0c6b15493a3cdac634ea4864be6913441d72ada0855493e3dd51f1398793f45ca0b526e4577d1e4e9d1cdb7e6476800028e3b0feb41dd319fbaadeb558693533e3981462835c9771f316408f045edf179ce609b39201592d9224b8a62c7f5737bef41fb1c287d9f7dfb09b8a351bc1864a7f65b7d1d3d010001	\\xd604448e81bc7be1704f45b511c40429b7b6356683a45629ce9886e45d41dda39bd018e84b9bb76d25eb8ddf4aef7601f4a5e8842d4a131fcda0b33519223705	1672310258000000	1672915058000000	1735987058000000	1830595058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
93	\\xf590364b122653d17bb8315338761bad45d781f41bea1c71abce36a346753893cf8817164808ab579235fb703e699191a0b3eac0174d8d1275c7f6ecdb3e936d	1	0	\\x000000010000000000800003d373db295a3f3b3beb74c5e823204e1c2007282ff265ffd8b2e0a72b04741c85ce3b2a11a9adc139bd5769d2e7d02743917a4825bc4cb9ddba2c46d7ab501271db6aec7fe5ec7a046d5c74e58b4e870cdc6c0f8e786d5aa28cb3f9d5ffeecbbcf18ef7c57abe734b159a16fde3fb5db6d869109e307e4505e077af67f97b865b010001	\\xa17b2bdc8146c6ee02179cb3c6092ac82eb743f19111d308ea535158da953419c26b44ba73af75f5a839a3f55ce76624005e0c6df68c2e6e184cf6c0a347600b	1669287758000000	1669892558000000	1732964558000000	1827572558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
94	\\xf85844b3b30a0779eed1bc92f335d62ae263133057a8db4fe83958d592cee6e03c10a112162b2a4b7640da32203dbef6cd078f26454ec9510a57cb262914645b	1	0	\\x000000010000000000800003cf8bdf9d400a8043bd894ac34da6850d8fdc6728464ebb62e52929295a5787f157fde81fcaa8aa22c2f6ed1340f984cf76b2ce93c2eb67990d9208802d50a017376c470075b72cd3a93c1b2add98314723b84d1535783b4a29ed929c3e91547b34a9e3f1adf234e8a09114126f5443b7d84f655d2b8271b8c9d8cf43b8856e01010001	\\xcc7355fc6418d0c824d5c3ee5e7ef3612fd06f88242087b50eb3b12587f0bd7a62c1aec86e54b7005ac05c866531337200b60a2dd6a35224ac968c5dda866703	1667474258000000	1668079058000000	1731151058000000	1825759058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
95	\\xfa30145476209f9340ea282abe456abe94cac7771496c4a5c0bba586baa393ce02d00c3371ec78fa81eed5275e3f40308caab7fa1a10ee399a5a73e5b91c734e	1	0	\\x000000010000000000800003bad70eefe12c22b61b5ea633220e4d840d7f34b03cae7537a6e9c0d8147b93b1bbe5c1a89d4c3805f51f4325276cf418876ba5722afcbb63e1797744dfc12ffbe21ff50653929e4f3178a35199430a687fa1089957387ffee58ad5d173bbf27e76534524994a944d413b34793d127fd522f914f2de29a1b0b90595168d77a53f010001	\\xab04d32397dfbe4cb6bb88a69b09794cfffd708c744529000467c8cd0bca3b41014ac0b65dec752f3b6652afeb55fea3bb4f5ae4369469162a7ca35df0c76401	1675332758000000	1675937558000000	1739009558000000	1833617558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xfe08bc428cc6bc0d94745065f4f1b8c0097dc2f251a60824527ad4f80016c1a035b12ae9c02dfd5cc680f714014c2a547dc353dfba44547c53608a4a331d3126	1	0	\\x000000010000000000800003d841e8e883716780b276941c3abf5bd1d47399331164a2b77fe5e4f7192a3a776c6a59bd27e1e1ef2d60b0b6bfba58b1debfdfa492b0cae115ca8cf47aa8090ee605c4f2a2e90b43be4f3a25466408cccdf44cf97b2884ed12f5e9f24742331fea278bcda4f045426c4e69e2a3fb5d99973099bf82e7eee4f8b084bc701736b3010001	\\x15fbee0e862b47922a2b4844f2055aba02d721e00d289f9feaa296dce1be1a1b50a608bf859c1c22b0474613dca6e5a736d6efb569f2e02a4759b59cd8cadc00	1675937258000000	1676542058000000	1739614058000000	1834222058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
97	\\x0485f2473647e30d8d26feb94c30153422a95511b4723c343675cec287728140b9c2dbdce076e0c683a6e0eeb6af5fae0484d09e1006138ec2e760c7711f5c87	1	0	\\x000000010000000000800003cc5cb5bfa967abe0a5ab57b7789acce55b5e8bd3f7cf754389950f525c456885684b972888ef18219ae85397f237f9b19236f75a1e959f971f12e4b968cef9ed8c9fb7bad77f2db1ea96fe17ea3d51d8334bb4b68664556f6c14629602f9449e9332855c3f9533da96e61962e261789ccf3065f6a226313d206ae24ba6fadc03010001	\\xb98e5d44a16e12885fdb227bd8e33526ea119baa0fdbea0026727ddaa9760017e36b925d8b690ddc83d09dbaac2ba9ba2db032e19c45fe01eb790e8081e46d0e	1677750758000000	1678355558000000	1741427558000000	1836035558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\x05dd1cf8dc070515820473f3595012e23fd56f6922853ac4b501908f5357399742fb91c19cc98e85f124d776cd3d6ebb5cf74202a03d70e81baebe0f4eee33ef	1	0	\\x000000010000000000800003a5cdba31dea509d787bdd21afa11f037013fba47d433b069534c028c3884ab467cf577b4a0d0417aa51414e3d13f57059566f27bf4bbb02eae90631ce5c66c586aad3a56d71cb8b47fe895cb3fe1a7e43e8f2fcfad3c9425e474f62a8cf723ea81ce195df7b967e374146b03bf8797962957a77d10cbaa59f257548895de02a5010001	\\x39c349bd9071098619820a6c03a9d3c06a818f29430b654308006d1b76ee99407e0d4efde0634d7f48139ca212b61058968c694efe51da52725bbb1f02d11201	1671101258000000	1671706058000000	1734778058000000	1829386058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
99	\\x083537c0f7bc8b3e3c20f4282e75496b45dbb14f740d820c36fb3e5888d2fbe916419e69c5eb9ccb61a1114a404faf4aded35e4b9000364e12af8c36d23bb1de	1	0	\\x000000010000000000800003b35bd25538dd7954dcc81f86ee1034898c2fb3decffa113d741508c1958ad218d4928ac6e298cc77fce4f8e4c9f468fd8ccae512bdb6c78e3f0fed52122a711af377cec0d2f4f14daa3d6a1e9d8012c8746173ea2fd6cf601ed065c1bfe96d5226ff1e871fe2db7831b2b865c6a0344b663afa35ef88f2580da47eec38cf5fbf010001	\\x081a35a37690f7663f9455cbeba46f20ce7af65ee6ae78116d5a7e4378c15d1c483d8b3dc4740bece7ad7ebdfa9f3b40e0a2100ce7896a40c218226e113ea40d	1659615758000000	1660220558000000	1723292558000000	1817900558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
100	\\x08b1c4b26cee1f55988b72f3cc4c846a0f632f5cc8ea8ccda25c4fe2c22a4650a7a4a8c54a063bbba2723f0c5808ec1544386b50bad37c018b3365066dbcf8cd	1	0	\\x000000010000000000800003b82cd133fa203404fe01eef58433687200c1dc4a8eb04719af20ee5e5fa5b93dc3bfee60b4e0eeca03a192781b27c8c03fc332a5ce3d6e088c1cd4918965f87f93148baec4ec8052100834c6ba17e09bfe1ea246dc44f6c64db387ac2bac1a7772d4aeef17a389237a59e2b259809305cc022515706c71de9ec756b8428ede19010001	\\x6f028630c48ca6e40a0f0d19fd2e22f859525330ae972320ed56576cc4dd20b12f1065f001b7b3105794e260cfaebee276b405b780cd2cec5e9f6c5a871a2109	1661429258000000	1662034058000000	1725106058000000	1819714058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
101	\\x0bc9cedfea25e502ca1cf4837ff41f74f4b6e81cc5ab11abe1e5bc61291f6c831f44050ceccc69c9de19d0cf41d66f5e80936c56017424fe5c2ae832af0b8d79	1	0	\\x000000010000000000800003ca47f782da5164c456529b787124334eadfe9578929923618db3e2d2c6bc8ddf6b0efbd6e65634995ca46e4ff396e66bdffe5d3e59560d7d46c746c7ab9894824a425002e26ffa32e6e3a58a89c0bc0a3041f648569980618cb5b693d442b49d4d8a350366c92272e18e4657210769be458aa08a0d42f94d6b3c98f90f6b623f010001	\\xe6ffa7134af6e7944461cf7bd5f2dc4f6aba4839e9c6efdedbbc9dd1b2c22a4c4d08cd1324aa41ffd515e5295194a3a1c2ccc92bc2fe888410eb6d24a26d8a0e	1671101258000000	1671706058000000	1734778058000000	1829386058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\x0bd1e6fb4c2b53e845dcb873398179a3a83da05b8755d50354488f0b8b2fdf17ff93122acd75fd42b22acac73402f5c3c33c56152fd30abea6115de23a33791d	1	0	\\x000000010000000000800003ddfdfd548de52bb6c10bd30c82b5807e6faac4dce7c2bb1951554b9ea2cc7dd93a19684ad75338ee67d85ff7dafb1c8bc8d1120e1cf22b1635bd0104506ee32c9c73a129f281cbf18f5d6cf994c521ae942d1bcb1f4d9b71c940ef38820f6859f8a9b865cf4d8e2592364f54fb17be9d00674b019f163b6d4424fc3baf0812a5010001	\\xcaaaf51e367017aa7da3c91c4d7db882215376790b4feda6dd1b86814783c6875427e87a85faf72f1cf4c5ca34da0d83754dd7e87fd3ef5f6ac4ead80ad83704	1655384258000000	1655989058000000	1719061058000000	1813669058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\x0bfd144949dad0db8484441c48bfefa9e1af887bfe6ac290bc6e30a3ee77284d7383f0fa396b3fff801c1e1d8315d6bb2ad20fbc12c157f342d3bb1d04bda56b	1	0	\\x000000010000000000800003b676961889ae071c890c0d64e2821232e00d3394124644d7f1b2151b77bc29e37b1a53b908bbbdb9acc275630e89d04db585af550c5c207a810ba654a74a902dc501ff6e273c319f7d0df2a3679102bea82c355dccb51d875829b835f7f73ce66cedc854ea83f2eaede744e699ceff411e57985c0a820e31b469f471a40ea54f010001	\\xb90a6621b2044abcaca1a4e5a9e6046b9a374f99c40e35fe4fcd4899d8747bba152ced50f21025bd6a1ce9b96f69a05a5950db0eeb6de63e00478de3fb07f204	1675937258000000	1676542058000000	1739614058000000	1834222058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
104	\\x0c0df4112e44f490e65e8a08bc228112d101690545ba8fa724026d1e489583f539ef2363b09a53e794bdf8dfa5b502dde4822f57ee62916bafdc60b6b4143a07	1	0	\\x000000010000000000800003c139b2753d6c03b77cdd7bf0c891d3f85aef5879f544ddf5fb7f178429b6c06ed1a7bc3cd4a8e003db91e249331710241379b3d8ffa83b9506cff1cab18542d17dbdc2b1674809e2a06a77e5139ea785c67f32bbcaec4fcfdc08e07a25b72bc6cf9564868cd4f564dda63d4410cdf278de73e0f6717ecf715dd49eefd007a08d010001	\\x85160982b8a21167aa9cdbe26bb4bce2cefea88348d28028fb69325a5f6010ace1a210040560edaaa0fb0f08526f6a1ad6eb7bb6a400a9a093b0b1eadbb5070b	1674728258000000	1675333058000000	1738405058000000	1833013058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
105	\\x13456c95bff269aef01e10caf68ba34398b0609c7a28044b9921eaacbc7931e7d070ca0917b1e977967139bb258e7ff2391aff0ab40fd2784174f1264f3e90e0	1	0	\\x000000010000000000800003c73949673d60499d2d96075b638706ac9b98eb38f9429578e465004936f37f05d6c81bf36310cb7e65c7d951a17d05b92f412f2c4378f29001ddeef1a5475eab1b7babe6980916405f1da87da0f7e3f47dd898203adaf12448d6906698bff926dfd24d0df05aa3724d066cdb6cc404062aaf79a47726df1f281030f90f62d335010001	\\x7e425a1e2c129aaf1ab6e6e5c2cad48b23059c50368be2519f3a17c123dfd149a5e29d534ca142bd0d3403dab835e89c8374a0d29c6eef09604a268e7030670b	1649339258000000	1649944058000000	1713016058000000	1807624058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
106	\\x144d8206f8128e2aeadf36d5dc19fcaf7911245170c0854a8bc7eaca809f1f55d62bbbf274f8a09ab8688e99f6739b34eee3c511aa7c2938303a1fbc924d385b	1	0	\\x000000010000000000800003cbec7c8ed38afd5809cec50f1cffb614bcd927f942a69986cbb02ae39bc720a918f4cb34ebb9469066d16d1ea11768f8f7d583fbf7f35cdfed3f86526787a309ce1de5ebd19639d78fcb88a08895be535ce2f8f49fc71d07584d4e7d40b79f0b78ce83976547d126d968a2f5a39437e82cde01eb3ecd9e6aaf96e93652c22cd1010001	\\xda5184eecdb2d28ef14711a0e26b70fef4b740325dae09a505c15a9023c9e078a34000060d09422966a110ad030b1c93c1f36d1a68c801ab9f7268029615060c	1658406758000000	1659011558000000	1722083558000000	1816691558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
107	\\x1675ef38efe419c0ed7640e2b1374c5d50cb18f29d800172d2249a47c80df22ddb02a1af56f46885ec9c4d716b5da50c092b9d4c517b5f05d5492a775315d99d	1	0	\\x000000010000000000800003d544271e37e1e32faa26ac691ba486f393cccdb8a6b9c6fdf5e3f346601312b8295b8ddd7d5f6478cba09085641f3dbabe0f6bcc2c4b8e7b8f604219bdd33052422f38e12e66dacd5fe6c64636abce46314f1758646e1853e5ca0bda5d1171d6abc48817ac74afbeb0cbcca662ef755cc63992524d98f319b460e4b2b887bedd010001	\\x88b7ca9d84e076629017270a50b1a3a3ab51c9683414a0ddffbb73dcf918b93eaef0d3188856cc5b0d226f7b75343be9ec40f9416b955eed430c5dbf38011400	1659615758000000	1660220558000000	1723292558000000	1817900558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
108	\\x195909fc1c027588e32965b88e8de5d63d4be10fdc0823d9b97c34bcc37bd4434a4c9f2a43f73e7555b07a6576eb57662b93d70f3a8970fd2618a3862ddac331	1	0	\\x000000010000000000800003d65fcbed4aef4c3f3533b6a14a58fb24a8fb815f6a4dab9a46de17e118a3c0bed66e6a827f5709d4e710502ca336915dcaa41bc21883dc4897719e4008f840dddebdfff546b4bbdc08a94a1382b2e65f3db1244426adc34cf01bbd7c38c75312cd155154e8be388edac5677d409606f26421c278e876f9ce41328b5a8c8fb007010001	\\x13bb995f46b08a52053176bfcdd62ca3c745f094b4dc2ffa8f473e16471e31008e7c7a07ea1b1e3cb504c8e9d38173ac13a97a26d02a93e8d7a35accc150e500	1659615758000000	1660220558000000	1723292558000000	1817900558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\x1e450da9a626bf6415f350137cfc1891f5388be09f908251dfc7eb8ffbfbae9b5e36a484fed2792e28d5ee04ed97d4966e1afaf24f7e321f4fdd29184efa3de7	1	0	\\x000000010000000000800003e8630dc6e266f7abed72396750401dbe76f4b6763ba11160dbd32bb3fca06d720fbe83e333fa4a529ab214644c97a2f31eebea97537c3a4141e5a14202b4e2707332f2120c6e5ae1ec944ce7a534d87549654ca5bfaf5b5f34ed357c8aeb3ffd4dc0ef173347ed51ff18040da3a10e9fb050eebddc352d56258055d9b103a32b010001	\\x9bd33663da6d30eef5fe6a0f91bad2b4c0df1a6fa1393e64917b7f17d805930fef4268ffc2ca8fe977e58dcc37b4e5504150c1c24fa804db7fa7fe54c789eb06	1669287758000000	1669892558000000	1732964558000000	1827572558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x23058d977431222731c02b06e0d1d3da095410dbcb0cd6713cec5ef87bc9071ab538118987aba1d2d8a87e564274d0b0e0273d88a49d0093ac37963c6ef5c8a9	1	0	\\x000000010000000000800003b7e7dec74d8b336745df3dcc8d41eff119515faf9354143881b52f72bd47fed440b3407dc862c2ec6969441730eefc99561b61a6005341ce5cfbe832af9cc63c52e56b8da637591100a3cb95b356bfc2c9efdc712eef76b7802ead2922064561f13eaddf11d2ee3cdecf07238ebd496b38875f5dad6bee304f673c4a995cb129010001	\\x4ba95a7b0b8583b1c0108b2819073d821eee2d5b04a2882dd082f0e5fc66e934449c1ded7988bdb9d97ff024ed4169d288f02e1042bda70da4224f81bc55bc04	1649943758000000	1650548558000000	1713620558000000	1808228558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x26592c81c48c1eddca92dbd539262f8767d0888bc9660a2df34b2807e1f04fbcd17e811ba6c5be4c89bf2e1422722860867d2ce77560a98a4e57424942a9ed46	1	0	\\x000000010000000000800003c469283eab10a5c63c19bb4d2a5ad31d7d2c465a93b437e30c031c99670377f5ccc55374652b1a770b8e2f456cdfa94c37b7ee406d9a001ab42c4b063448ef3a1ce23d251a65e9d1c0f3a7ca45f61943022444d67bf44460696bd6a1e4366a2800d792d17ab037771cbd048d29e01a21df2d6b55c4b80e935eed29ac2421bf85010001	\\x2b0b4ee1ca2243f2cd8bd665ad04bcd915e61a04087f6ffc0db13702108b5ab4d96c7ec5f6c5b5c0676fe1fa7064098814868925868d08a4a38e3be6b5bcab0c	1663242758000000	1663847558000000	1726919558000000	1821527558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
112	\\x276d2612e4ca0be9ab292571d51cb90378d4141f872d16b16672959e8168c7757c2ce27c818b62d0b826db1c58426d06283bfd2d0e31692088ba0fcbfd831adf	1	0	\\x000000010000000000800003bd2d50d3e901a6cb503e4e2867c68c860e0619c5bc5dcf9dd476fc1da2653a405badb759bf07094319bcccf6320d1a2e77ebb3a04da8d283b69ed4b88083d3aeddae8fb7dc2898eee6c7c0f5fb34846193ee757049e4c7ff2de1bd3bece18495a09f2e6f634d63360ec3806e0a480e23e5f13d89de71a1b05009d94215bc329f010001	\\x8558a8356eeeb7e35a4b07ba248c16cccccd1cdc5644494cc1efdf4b9e64b9561699197b33caba35c37d1c9bf55a7c3667184d3e6d66bbf6280c052629a4270e	1663242758000000	1663847558000000	1726919558000000	1821527558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
113	\\x2a99f3f6ce4e9395245bf707c5acac5b61e2e0e2101a78217de1f31c9daea2cdea62bf1980a1ceab7582cd593d7bad644ceb621056076e9fffdcaf366e4c9eae	1	0	\\x000000010000000000800003b1060ea8272ba6a43c14b696a8526de9de3de65c913e490f27a3fbd58d0cebf4fb65ffc5514429271042b8d78ebd09a2408eeafde971ca9366a07232a2d3d1ad346ccd257503477f10f08b764ffd1bd33854673a9e449d5f3a31fd12ed20fc78b7cb7c39f4c8882e220a55e32aca9c3e0de85f14358128880e6d4b78fff84d79010001	\\xfbc210b59220bc82895cb50efc63c028c96f5634d9ad23de88ad096bc73e457cf199b34228816b7d7469d0ff312a577a4f5c109b88107376d66d53b573d85508	1669892258000000	1670497058000000	1733569058000000	1828177058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
114	\\x2d2173fb81a9efd255257b43e5a37a1ae71c4ffcb8cbffe080a8428b04dfde26893fad744d8b0e8d140ced9c94febec1be81d29353f59c61edce8a709d8b3277	1	0	\\x000000010000000000800003a4f667b1300715faf72bfab8485174851540dad17b2e62cd8470d3eac46f27ed8035f078cdf45c782364b2fed3f1a0b14703a37ccc9973d5ceb72054b05fee95e1c7427b51803fc9bb61d1e4740008477ffffab2a31091861efa1c8b450915d574ffda699b3b310397f395a1c786a8533923da3a18b0ccdac32ecf0829728fdd010001	\\x1ad121b4c85dff5fadc7b8844283e03819bad8d0eec50b89ee4b353550f79761ae488061c53f1050aa42c5af0f3a531eeba7479f2a63b10575f00d54932d0002	1674728258000000	1675333058000000	1738405058000000	1833013058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
115	\\x2fb5e5878b790a39b4d50d22124a514ae882cb32bba7512fb9e3ae904bac549d9187f18b3818687bfe871c09e24dcf88ffed58f37010f63ac0e20f75f14f96f9	1	0	\\x000000010000000000800003d89fa46bd5983babef60cef6713ccecb058803307773a6b1bddad650944225293766f8cebe904044c2140dcb11cc2537cdbc3637e3079ce7fc7e184f5dbf9d2a9cd38c15837e272b5a5f41ed2f8a3627f1c1a28788e999ff58f51d00d6b1aec894d55f4f28d07e630fb4217371640cd2c4550235f0614dcd8c742f40371a2051010001	\\x1eb70a9bb9a51bb25249bf6b214f60cf187aa5540c0cf5c21eb9a7508bb25c678ed69e4eb88859f6475ea1e8deef72bbd25bd42f9cbc7f67ce25996a8522ed0b	1651757258000000	1652362058000000	1715434058000000	1810042058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x3ca17d612fe72509fe02dda1dae2f80ac227796f88821e4a6886f8ba6d88d681fa3423b32c81cb7398b32d2bb97f2b7b4c677f45c73bbb01681d993c00ee7484	1	0	\\x000000010000000000800003be908c1f573c4039c5000ffcec114b32b8f2ac25733a4349790c63ba7e837e69164e966883ca6d3baaa8ac2b45803cc0e02604f1269ac8870135ae9b8ffd638b8866840c151571b1a3f5229354bd9c4cb14e7da6925be2320abe773e5509d567ac21c5e6570baf23dc50b4cce57ee70607f2346b8231b7892f1f909881c56959010001	\\xec5102c01fd38febc8787b94d6bdb51ff97a5daa123f50819769c9dde48f2aaac9c1a160a70015e78c6daa443033b1f5c3f17866d7fc4c7d405ded9f717dda00	1656593258000000	1657198058000000	1720270058000000	1814878058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x3ec1f6bc0034d9dcf075ee34d40888906ea739b38bf4e7ec0b38619518b331058599a0f833acc201f5cd9144abd23cac95a794ce8f20f89e1eb4698ae9ea69f8	1	0	\\x000000010000000000800003ac5c50831442c6506f0d4e05a1b92b76e8a95f4193720546660b27086c3bee3cf0e5eb2e634c756d1daaa13046b94e2acac701287543d6a47313bb7b65c5a753a66fca91d6c978cfca9ee4050025c93ed4ffe978f0c81f1bb21d6564f8198158fea9d7c6a7af095650813c39b2350064819d730df4484e6a17aa13760e68668b010001	\\x5b3e98f3dce4c5a0a279793e1bebc2c0286a5448744501a50e85e07b9dd8208371dd9df45aec40604550855bdd016a36196b8b1b3ccc97620be001b2ba4f1805	1657802258000000	1658407058000000	1721479058000000	1816087058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x405538d43cefecc21a58329cc1390d08ea83d85734b06a315d106833d918024d48d8b58687d4adee5177fbaa32388d2f637c3be15620805472ac873a14ba0aa8	1	0	\\x000000010000000000800003e068110d3b7a2e0822bd25b0bde22976d15d39f2866c3d1d1eb574dd54b62c6a81d4b13d843ec154153daceee227df0d320cb0e66ec0b5d986c14919404961fcc0de747d5d3e8ca7484ea5da841e7c7805e666080f87ffef7cd6827b240f26457a70eb20bfce3ab6ae0107df6ddb0be1c24c9433b1494991e4e7d648eb03d449010001	\\xadaf49be7f63cbbb8a492164629daea7dbb5b97df80640ca969c1da0db23a3ecf4d21fda216c8e6fd52cd900ccc930fdaf1fc8ad7e53f13e8e74e20643007208	1649339258000000	1649944058000000	1713016058000000	1807624058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
119	\\x4171a15a0955346bc2b6ac53d4c69cd5d1b357a433749fb352deafcb79a06e89cd37e9ae3e657485b36a1a48920c75846330098ce11a1af13c52ea3e227de51a	1	0	\\x000000010000000000800003d5d86f2b9111177f8db8a9be742ba949ad02d80571e53d4fa48fa2649bc269c52535d3b0fdd3a0be088a2de75042322d53d0ee8c11206e4ab976a12db29543ada3d72fffea4bc51c20afab044648448950eee0a4f18b90bae34b4a4e250b95ee97e7c3421c3b827280dba475ddefbbf680c8374b8f222f79f79824583b1d0ccd010001	\\x1f58231cc30a26552f22b3444d287e8db64ac513e920ba2550ec8360c8c3e6231cd5f944207466e416ac3ccca50645edfc6abd15bd6654860748160cd726d901	1666265258000000	1666870058000000	1729942058000000	1824550058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
120	\\x4101082744d067588b89a9128144b4b2d22953d1b119b6231232f096472cc17daf320f2f35b696f5bf72c32f449cc498a5669ad2d54696a699de5f9948b43dc2	1	0	\\x000000010000000000800003a8fcf49ce3cdea598d15d9a3f4ea8cbaf6fd1cad593cc27b2837e328c64a371d42772838d3cbd01765b37d24154641d977baebfb5f5f7dab12f1653811a958c49ebb59462c96e2e26c28b2b149fa33a55667835621a7fd282288893e624b5dfccfbac64c059564900612f4b4deb31cd9c9e6b268394fec37bd87dbae0067bb07010001	\\xe65417229a1cf6efb8e6e0ea4f56b7335579cbf17909141717a99ff1135dc234948ae1eb389639ce841c88b5d65e0020c564af765675d62900c052e2b8c1e402	1659011258000000	1659616058000000	1722688058000000	1817296058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\x42adbe1d9dc89ef890da21514273437e68902e6dc9af87d3a47073f96b5400839733c21996185f8ba0246f6380334233d582fee10bc4b816ce67ad9cc5f436e0	1	0	\\x000000010000000000800003d94c121e9deb765144acd9cb54f0c19db18973b0f332eeb297271195fd3b281f5535ccbe750ca4f1b9797d2165387189da793ebce7678da09b1e6e4206b0253083ba366514772a556f76d8e49a42da3a7a0a4e8051c5a7e2144e69f62fcecec194d0aea3a9889fb4083e0a0aa9cb0355ed86ad7b2bc7851cb62d22e244a18f71010001	\\xf0d80f8bad4258a421c931b328a957c99135612315a33b9e75cdff9f87688aadc3c94f76e5420b14280368740b42258971afc029f03145fd1f418841e08a3705	1655384258000000	1655989058000000	1719061058000000	1813669058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
122	\\x473116b9f29ee9bd820fc03eb85a06f2744c6af504bd302811b21b53df1ee5eda6ba613e416c7e16eb068498493f16a0f0a630e745b0a5a88b750a6627c18022	1	0	\\x000000010000000000800003a131655497126fe9d0bc483415277dc86e775caaa9aeae56abde19e2fc20dd6b831c8f265c3ca4df69b31980b7f75ed9414f84c3f581b8e5da8cf0b8dd965a66377695a66b45a824eedb2d04b8d76d7765ed73d1dfeb44c720767071d03a04b8abd28feaaf683f915926fec68a240930f7ac8bdad0f38316b9367b8008d86e43010001	\\xba911465695b25d44a32658558a17301abf8b416fee14ca4bebec138230f7679f4f52b6978a3df23f5ae1f1778513e57c7e004f559e611308578ece9c099f306	1654779758000000	1655384558000000	1718456558000000	1813064558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x48857f487935c5c1df5891715ce37e7f2ad0d9b6b7541ef578cd588f6c54aa0f37a990bb5bb15894cb7c4637c3ba53ea0a05a797fe16ba2adbfc8d749b8f388a	1	0	\\x000000010000000000800003a1b0f08ac67f0e25ac7f9cd987ac8630a2a0b5fbb46aa6b62cc2a23c596b37a96e27885dcb5468099f07ca7ae2531111e065001ed3b87bb2b495520629d3f83b6bbf7ac141e9577d469477dcb68902d08834a5f74064fe25946bce807b334a816e28663b3b54e291045ddbc86e0fed0a185f5950e91c16738c766229ac5effe5010001	\\x7c5e57045ac11fa260c12053f0242b946448805f84417fb9114a91ee2d00f3e33657df5293341e644aedb1aa536dced82a9695a4c9d72c21a28e63131d1db50c	1670496758000000	1671101558000000	1734173558000000	1828781558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
124	\\x492538acb8487556f70a1f1a43dcc9389f3f3baeedf0340ecb5b21e0d67a8226fd4ec92f73233dfd18e36e797565c98c2e54f02ba727a6f0c918c52c781b59f9	1	0	\\x000000010000000000800003c3a0db86ed7ab93870dc8f470ac09a3bab9db4a56de767792c661fff87f533220667c75ababab9e03e1ec64a1ded863fc3d4d4fb46505858bdcd1446493eb34da3f25450fe0198ada8386717e80ee7229a39fb88b7205f1f49d89b1d80720c7d219dca8533d94f8b61b1fb0ead43a6debd82ed377f6a2316198ebc4ab56fae45010001	\\xa7fe05394a5011186a1ff6617ace5bca97173d8563012db9395b31bea9e48438e48351f2324bcc01bf3895cee9f519dadf5e9f8885c05e3ce4a77e4fcc281508	1660824758000000	1661429558000000	1724501558000000	1819109558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
125	\\x497132b0a4049f14f8242e509a00a8544d4db8b5d7afad14337c28ac61e92705e6ffb2f1473c4e50b307a37b1aab7c2e5d731323db685e9f3ef72ac689780451	1	0	\\x000000010000000000800003d0fef1509b4b7a4564ab85dfa05a56aa4d59e70fc05af993bb402275b7762c674cea2e6ef55488741afe8bba9a5420f254ceb0429275c96b17aa124b92b059c3917cbbba3d3ba371a581f4fedd6a7a2faaa2d862cc97d41a8539313621db18aaf60617fc74994ecb828f1c844184e5cad86375e855472f870ad17db662da74b9010001	\\xa0cb8d5a4bfb3a4809200782d13ad086bc965505eb36587a9e4b63db33422afb5fc9ed23058cf54a921ab23e072f171d50cf912d9ec88c745c2fe5acf233740a	1648130258000000	1648735058000000	1711807058000000	1806415058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x4a993407315eaded380c036dbcc6f8a347e0ad79487be48586501448ca13d2d463f478c238b44a1180cb0346adb4022540fb7401c11cbd40dc722338797a9ac4	1	0	\\x000000010000000000800003e6d51ec17e620d1c3c36cc5a8ff5adc8a887f5eefbac0e4e377f4800b3f07fa86a989a94421e0a084462e5255ec5721522f777209a6113a36e7a8ba98dd4d30cab75589e389178b587ab3858e04caee5a2d1a14534afb0d4e569e6fb3e0838183700ebce060acfd6e2841ebd134dde10ea0d0959fb89486132e98e65ac9f484f010001	\\x096e8030251f2cd575fdb221ae35dbfb30b7cd31655729c3daa8b5bd4f1f1d3fa54210aa8a0a8470bc2797d989564ff20462878b9ad0dcb4efb34c46636fef0b	1649943758000000	1650548558000000	1713620558000000	1808228558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
127	\\x4c794b32e596ebbee2558edef2d6c21a851104826e6d9dc8cff8479e57f5ec926bf4779fbdb9b6b7aa5fa849dae5c0dd504a5e31844aeaecd5aa59595253c56a	1	0	\\x000000010000000000800003effeb3df780a1f3b806b4669b25cba65048144c6f2465c7d20170941d4aa0a1f7ddad417d46bf9ff22bc60efaf5eb8c704ec37f394276c3e7c7a1bd8100b66522381da484d907601da5d7bd29fe7275ad11a98a34f5af89a2b50d1804fb56f43bd39319508ef766c4d2fe7be96fdab82f1ca1aa1764388a1b8ae34053fa9c3d7010001	\\x5aa3e00cb931c25c1064ba9d224f0b9a2d557fb59cfb12966788be7c14d18f2e336135bc1cdef72d533f10cf20bb58954b793a9fbaad0ec9b44ae19fa1466d09	1665056258000000	1665661058000000	1728733058000000	1823341058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
128	\\x4d19fecaae6b4859646bd0643d98ab19b34d01a42607bc114c81aa96b9ceb7cc228560e97f0adcd82bd1a9e65de6b10399705a9d059b050736c5c8ac38e0b570	1	0	\\x000000010000000000800003dd351d72bdc0fe79899f232b176380f13e7796f6734c2f520fb226404059da4283d907b6f96d92426d9d6e6e8b9b0d0e9e37129c2fc381fb04f8054327df7ac7fe4625a18472ef11be55282b01e2877db50956c3f4d24227c75cbe350d4b6991feb4b9c5d813d2ff07c9b9175ca6f10f5df530e022604ed6e624c81e69235167010001	\\xb8f3c6dcb29613a4a16dccf34a7b7a3ec1301ac31b939969d5bd818d3dda3a8b7ea4fb10f55a847f87e1a2d08cb86fb2b7374beeeff484fc90a87120e067090c	1678355258000000	1678960058000000	1742032058000000	1836640058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x53c5b4236335ada13a520d054e6815a63f4c6ff3d9efa333c4630fad19400f7b99ac5e65e1f8c51be3f2e1a1756e05876f6e52bf698bd3afea3e5d1bbf283fe2	1	0	\\x000000010000000000800003dcc31655c994e23593303e2625938b571e9b3a7a31826595f2006060242434d894fb5d786785245020ecc0ad98be78073a90619001c579bb34d0f554e9eadc96ff263ea58f3a3682a23d5a0ca5e8fd806dd53c9d8f73b2a8c3d5fbfc73078da6e7a8d3579ad8fa98321646f79d721090da5d8244317b5065718bdd4827bbb319010001	\\x2b2f2536423e652ecd8da4d3a55c61a7ac00a6101d9258092c3742f95f73595e18452c9ff6a5cd9686263251515579bcc0bb8b9f6a73b8e8e73166f7e8321301	1660824758000000	1661429558000000	1724501558000000	1819109558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
130	\\x56c5fd5e7b7869da0474271aa3188d2dafd99908fba8e78cb55fdc3b35a919a0c29d72defa2bf4b765efa09b0237f068d82492bc7287fb2b5d9cb0924851faf4	1	0	\\x000000010000000000800003babdbbab4989012111ff1c0e4f79ccc70ebb1673d4d0414d5bca28816123a61d533a26944f18ab704387408c3f1afc78b31982b2084eae4ba16d4f6f27bee62fce06f653647cc2e721bb406b8c2a50f4c442102285bc4b2fa16f0fcfb86840eb299642deea218710d9f05e997bd5e1d9fa29f6dc72246102a3d8b9578ddb4ea3010001	\\x9704103bc0b8a93cf5e0b31fd10abfde0860ea0f7a6c21e63239fded949ef700d6f6298dc3908cdba312e5e48b8c16e157b23c95a7ae083ea321a93f0d6ab209	1674728258000000	1675333058000000	1738405058000000	1833013058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
131	\\x59198a92e506ca4eb3d8824cb130548b6b48bce329b5f5c285119c6b91d6b77d83834521ec1dd7f44b264da017e58f6902f46eb3ce6a5a3d13fdac1bdc3604b2	1	0	\\x000000010000000000800003f4dcf634106ede69abb8f3ab29b767ab6fb69c012e773e77d191db87ff7c58a14d432ddfe54f8ae932f25f36d4986509ba951d07914633b3da5016dfec3db0f394473893396a331614adf13677db458eb1ffc9b39b0bca7adf82a574845cb31622f36b789a265ac6a2c50a30c6d6b998124ec4d49874e827936d65799a1be92f010001	\\xf867b84a8536e816eeac8f3ac87e6a5338dad1d6c84fdf97253d7943f05d2bfd7181a67411f6c056cecb8dc942491369d84849a601cb38dcf7f9e30c2199b001	1655988758000000	1656593558000000	1719665558000000	1814273558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x5c11074b57343862034567ec4184177b7bf08191b058a2f83de168679c53d32ed0fc655b0cba6b009d70e5d06b42aa54186b3e1a4f270ced5272a999033a0c13	1	0	\\x000000010000000000800003c644503fe51bb7b6b7d1e1f09188b74de0d95f37f625169f79c2a69b2888b4cad2adcd11970c1edbbe4ded2dc3c00e4ffb57f15245e60ca0dc13be1dc6f60b8b46bcc37600c27ecab55daf9d2e7cd21c45e166d03b182c08c278579e92bb35355a03cb46838702c6804fe348b6fbd0e6df7a1485f9319326b4b41e9fcc897333010001	\\xcc1d3373e45d542be4a256dc110597b64d1f3cb9a70b0d52ee1dba26a5873d670be6a796019e5ee34bdb463ab332c62fb7d3badbca45ba97174bbf78e94dbd02	1647525758000000	1648130558000000	1711202558000000	1805810558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
133	\\x5d9d6ddab568dc586a6dc93cd34f616f66c247a369c1f04c361c5ffff9f0bf3134d10e88ac28cc3fecfb67b03d1db4118d7fd198e14f96cec854ed30245b5434	1	0	\\x000000010000000000800003c58d2e8a152f3d1f0059b3ced51c40f47010f3fc12539a88de550a376fb8150a18de7b9d9eb3b1c63b7d74ed11ef322b0d1a2b2f2074c85164c59197061b9fbcbb20274749e96aad81fbaddb75bfa7b511ec2b5ead79c5080ec53b5ca4b14e873324acc36581663198ee0b947586395fbcbba9ac7200f369057da4bccc91e863010001	\\x41051f3a98960c2aa984d5c96a1d06dbeffe2178d2232faec341a679eedf08a34581b9ba6f6fee16f869877a65c01370826e2bf14e7485c92b892a707a85fe05	1662033758000000	1662638558000000	1725710558000000	1820318558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
134	\\x61bd7edc8a964588e22134b29b6f9707c570185199a12fca668a2331515c4154cc759f5133ef7c1aea5340bb98a265dd6baa372ecdebff66593187fd39eb3505	1	0	\\x000000010000000000800003be413d2c5e02a1c0a833f132d0b5501617a67302b430c60de6601b69c6ebe6e46d3364f6b25904043e58343d1bfb1fba9e9e02da66c7f86663f514113da13be720407eb6d4f8db4e1be54f60035e6529d7a96c3fe3d5ffc32ab581a1e544c0fa697399c9c3760d2237ab3fce245d7c929b4cd2752296b3e3344d92783c0c1673010001	\\xe434248da8958d1314de04b5eaa8366848220befc02450fc8dd88e7a19cd435eef89f8ea4f29fbdeb0a62eeba52b7865394ca63d39e921234f07f3c676c27603	1674728258000000	1675333058000000	1738405058000000	1833013058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
135	\\x63f19a69d4554f1088b86517245e2140fc90b1eb659dd8c55ffd113a8251626e0bdf32d654d77abec22e42d0e57fb7d8d78a1112ed4fb0e6bf6bf095ffcc3609	1	0	\\x000000010000000000800003df01030176e67eae0d4615d41507f7512def8c86405650fc12262cf2c1502440ca50dfaa67def5643af51fc101ce04ee21d3bab78dc748c6de8a342ef7136b1767a1d2d3956c018d8e8ff82c84539e21a4265a731aeb6a153a0b313999f66159ab7fb25d97b619d0b71bb1e8f964d53e60d366e0cb2863e1a0d53c65fee7d8ff010001	\\x766ed5b16c546bd444fc9ce5e134bd872eb888f902f3c9f5b35b0c580082658c23ab332847cefef814c53439729ccb775151f3326ddc2804ab6feb9487053c0e	1649339258000000	1649944058000000	1713016058000000	1807624058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
136	\\x65a1d8a81744743ff27aea7b5afb6707b5f45711a8c1b450b7a13590168468b247215badb0f040e109576082785f060c8c98baaf8f263705c076a19f2604a836	1	0	\\x000000010000000000800003b22e02d6ec96f6412093acb1422b8847df2e09d4c12bbcde23f3a9a96eac76e7d80181232aaf2ebfc4bcf44d49518c461d767680b2274e11f78256a71c6b1555cc342e452b500490dbbc634d57e66379a691f703679fd4845dc14be5c195f181ca15aa5808dcad8f35a5cb5637286c40dedaaea8f5da517c8066ae9803a88b8f010001	\\xf58504e4e86368dd72045be3964ccf87e06b8bfe7ab915858f2f0ea97775e63be450566e98cd18aac8beb16a84b3d78dad7ae6377368d1959cd8bb1d70777407	1675332758000000	1675937558000000	1739009558000000	1833617558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
137	\\x6611b9a0c572479c4a790e86d299b346c85d0c65abf2192ffde775cd87add50a15e1e6dab0d1f82171d6b6bfeffcb36c5c5780f2046ff7248a7f630e865e5792	1	0	\\x000000010000000000800003d7ed7d022becc7599272e16258d5abe1680244b96b76fe25aa7c957711a9efb14f4ba66d7a07f1959d26616b8880a7b51089425d0cbbffe72dd2254847308deb7280a58ac198dd9774a5dec9d0262d585f7a301f73257ed6342767b8d2ac11e6151316822f68c047d893504bdfec3b93c323188455a9a96952fbfd67e9fcdf21010001	\\x2a06e09b17607fd01b0f005a66daeb239c5643596bb0071dd5e3c6fae77364e8b85e7d75e7c0b98bb5841bc801fb1d7516994596f5750def3eefe574fbcb5a06	1678355258000000	1678960058000000	1742032058000000	1836640058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x67292d75eb9f4a72845fc2fe6f290d2fd7741afed587ac544dddbcedf308669ffa22408d16642a6bd335cfb15eefa64e9ad9a13111557d5847a1dd466b65e491	1	0	\\x000000010000000000800003baf0ed580c009d85ada73deb435b4f38c974d67f2b0c42d3af8ecc8abae928fb031c4048e26269582f452b1112161c0825b0833ad418b34fe8bd58672de00f722e7cf64bb448768653b7de441e8d2e7b5565aaa42986a3df3042c02060aaed391c1e771001f58142c609c9e982efedf26ff602186a12267c40c4f54514a4f837010001	\\xdda8c96b7fca45be8fce2250d15167bd259011edce984e362a4409cde6c9a9f0e3e8d3eeb3dfdd697b0b49a1c568d71484674ba05c27f8551784bccf04c1c105	1671101258000000	1671706058000000	1734778058000000	1829386058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x67c17853cceacd217dcd5edc9c364ef39892f0dd96fb15efb6fca3075200efcda7cb6128b3c922e8f2b49c23739276546b5be364b3f554597bf40223082f2814	1	0	\\x000000010000000000800003d857f40351c06d6eade8e10119dc7b35b4a5a179eb166ab559c4f5cd1f17943666685952cb68a9ad19f557b3b9f93586740ac3f03a2574f5bae895ff381cc9464634703d60af2ac5d32e69a0e07577174d3ce70959ef3c909556bb35f20bb804ce5a5386490df02cd59d5c94aa34e8be2613b97de562250d51a423c51e6e8739010001	\\xa0b6dd3964a63f9a55df4efa512943c383a58fd21940b270c0d19ce35a06e0306d1e0265eee90f1561da892c84fe6490edd747c2028f7dbb0edbca197cf90001	1653570758000000	1654175558000000	1717247558000000	1811855558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x6a75c5df8975b6c178fa6e03ecd14f3feba1a36d153f0ce0ee50470d456072629160b6f3160cd34a046809230dd18e6c73f05aba7f3d4020d0b9f243abd6eab3	1	0	\\x000000010000000000800003c7e1d4113c10de77ebac76325a370b32b0e56da44071b2e285c158fb3dd305f1ef133b1854bd28830a5fac272506659c59fe2bb714af269461e310cbb5f0f3dd54c6b2f6dc613f0815a1d8ee6f6dfe6e2c651e8e7d68418226c3cc183f5c5c8c787c8fe61c4dafe507638ed4fe01bf4f0c666ed64cb88a138a8d97aee72fe277010001	\\x2353c0315c01720b83cbf130a93f1a2383bd021720a7a67b23c9e7713bee471f7112703bffc85fca11f7c78764ffc9c26546c851419fb56e2f2390aee0f16c02	1657802258000000	1658407058000000	1721479058000000	1816087058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x6a497a1bba982669300483802866bba80e8e896c9ed55ee8f01d7beddd29b15e6c192f9848baa8b3964cbdf3763ec3e8efcf8142387e1e90cd36fa9ded7aee15	1	0	\\x000000010000000000800003ba0aad9bec81e5776acc0bf7f298e8cabafce66e2a2f189eb3973deb28575fc14c7b8e87a5787a794c9d370f07f8d0c6fcdb4a262daa14dff392b3d6a218813de3baa6e7f429b051b315c2e32ca5618feba6eda428d0d482078843b029113eeb8f9903dd5b0b453a4967bf1ab0989c3f7ca98cb2c25100228f62f1d7ae0e94c5010001	\\xcd5225ec0850566fb306ca0a553f6260eb3d20412185e7f7df413c67a117f437779bef47506b778c2cc5873fa842f6e7ae8ed0bd1c6e9f68062b2f2b6050b704	1654175258000000	1654780058000000	1717852058000000	1812460058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x6b7dee56cd04cde7beb843ed1c4b4f84240d5d867ff4b3d0333b2d52fbc4b2667d4d3a51eaac61907ee9536e5df7487bf2069eb8db7abd4dc41a42bb8e91fa66	1	0	\\x000000010000000000800003c4a96f901b8667225d665630f986ec090f586ce52508db822c3a80f415b4f2d0d6cd1b9432d3babbfa840fa4af0d6effc6a6531dead9efcf7e51cecf12543eb07830ae13cc1b6465ac339deb051dd0601c77a115f4f2ed5b3670d5db789cccbeddcf426954670aa6ff1f6194a8ed00874e6a98a547f94e92352d30efe7b3a181010001	\\x2c300b2212922c92845b18c4b0e420b3df19072d05120e76e3bb707596dd02c5cbee2537d06f6df8b8bd4c88db5e755501a4bd295306fe15fbf82cba69db9c05	1655988758000000	1656593558000000	1719665558000000	1814273558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x6f95c56601515ca786e14b0872218396c06ed3a2bf4db63fdc059b95a11019f762dc653e8de0a04692f40e0bca75a8738287b048b2f42a30299eefc8db0cbc1d	1	0	\\x0000000100000000008000039f140991cc8b0043e01ed97c44965f3e76d3116d557d9725e1035a3aec45037e0dc3b50f36110f385e84e7bfd144bd1b89e12dc7e376b1e447180878f12ab030bcb506f9a33ce131101dc83c50299963d48bad8367df605e22f82b130540d11216ed14b9edc4bfd80fac6181ec91607193654e901ec809f7213855845075141f010001	\\xf4743b0f03a323057a60029b78d13c8ebba6e8fc249a622a8d23503a0458618b634ed56d5af100c497e207a187e41107938de7088d4606cafc17a79ed0068703	1674123758000000	1674728558000000	1737800558000000	1832408558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
144	\\x756d4efa89d9de354235023000515c50662de3bbef962d4dce7c260c15d15725fa44f817a1d51840eba6335d2437b4dab511695f95b2dfe790860dfe9dd7324c	1	0	\\x000000010000000000800003b88779055192eb08826ae5b33029593afa5bafc7d75957d58ace7bbfa69f3d085bfb65dae14d447f3dfc842a4483354c8bd5cc8e6bb72644f2c97a96ab8b3cd6b677fabdc0d914830062b3f15aec7a91d9cb0dc3a4e516d1184bf8d9af1eb3182016a2873ebaff558bef60b057a1f7a084cb1e7860e5ea21052b8e4f25a396db010001	\\x7a335654e12a14d05c68a8c88ccd4e21272d3cc6b5808aea8ff3192875c6f7b5a4d1e5260695c6630a9f9d0444108e64e2a2a9b3030ae71f0b6cbf6c4874f700	1652966258000000	1653571058000000	1716643058000000	1811251058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
145	\\x765d4d42cf73595b1a43c848f89da8c3fbe20d2b2c8046a1a62b1e5bfb69d67284ede01a91451cdd240efa5d61a3f742eaedb7322c004b7261cc34ffe6d60eb4	1	0	\\x000000010000000000800003aea25556c7f3bf31d441ef66d26d12b8bfae3468de06b18a0cba7d700b9504f21f4df87f9a3d225704ac5b396ee393903a55b56b9996c3d2e1a4056f43a54e68e75d12b6f95d4f7d7a543042152e3c2816fd3d0366287a98c6d9e5c6e71eaa9b793a9770ee4b02f5fbcd72cbf027b9c4cfab391893e426fc8a4dbf4d54ccbbd1010001	\\x2b8253910533c51c5defb33f4f424f187e4aabe78620271e30db878f24454a03c956df27d416e3f35ed394547b8990a0ff8a7888feb8979144b4f1817a597a03	1672310258000000	1672915058000000	1735987058000000	1830595058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
146	\\x7921a2a1aee503316deb90aa6be21353d07f85cd878bc1b825d9205ca816db410ae90c7eed6e0b97b5c78a39e4342aa6c7213de846379dd318fd87c68f7105f1	1	0	\\x000000010000000000800003d55c94349742f69ce0abcaf775c47f54166ccb872a2cb1f451485d20d8e35fee483242d414a4a15fee46bb30cabb0eacf05a3797620b6112aaf50afd8d7e53b83d54dca640baa06d07d79b464c45fd46f9f5e936a0dc081da26f9542aaaf34fd913dbb90689e26e314e5feb2f0b8dd13b2352a736cc520fa71272bbc8a29274f010001	\\x1833cc5486749c72b3d160fcb7b99bee7150c98645e90754748a2fa43ab0927ed0f0163fb46183775ad31ac0fa8b5950dc91bafb388528766d69f26904905208	1666869758000000	1667474558000000	1730546558000000	1825154558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x7929175fbf5c8762d0f7b6c3419db0fc11ac0708eb1392471cd3daed493e0d06abe6e7e285d8d3485cb11ef51c8d99e87580ff8190c3791cc031105c523dc151	1	0	\\x000000010000000000800003e6055b268aa59b2793e6df422cd27b4a0953920e21679f5d294ba955ac38fba241b45a733eb6defbde747cf55af407a7789780228f8b41a8216fd66aac9dd622f2a98c86473b5ad178cb7349603137be505a64617088005d4af014b69fd1c74036007e15cf3879167febacd103c8fe0751248911ee2f596a18ba39b1380ae5e9010001	\\x0ffe834cf70a5f17d4a9f3f9435f4e6a1a83a6a93f45974d3ecd92b9e07f9a0f22fe81d3c3753ed11a13ce9eaf09f2d1a6b9625f41ef5d69f6bad41f5aa5ba0d	1649943758000000	1650548558000000	1713620558000000	1808228558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x7a9517bd1e970e31f4bf17f279f90fe756ac4b22f156db25b9a088a05451f19ea4995e81171a82290cdc15c4cd2dd72207c0f0c49858c47cd8172dde630041f5	1	0	\\x000000010000000000800003a9385a3d279c15aef8e1fcdf1aa9e466956d7fd9335d7a8a526086be602c31054798dacdcecea655c1e74dc7678106bd72dcf6ea986e426bb8fb351ca84bca199efb36e7efd8d3cab6c64d8190dcbd8947feb4d1aa110d5f1f21c2158445e52c0f31216d1095c3c6c3344dd992d56297cd1cb5d59c4bdf76a1e58c0d3e5c8de3010001	\\x0f8e50f849e884e420342e997c9485d25a476af3e6e900792d2a58c1dcafbe315cfaa4bdaae92a25cc4115ae7f36d3b644d8735c824ef172fe7b1321de21b50a	1673519258000000	1674124058000000	1737196058000000	1831804058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
149	\\x7a91f69d673e337d7c58b45d212cb6aea4a445139256e93ab0b208ea627928235c0380119843e12fae80e7eb74206621f7f81873afd5b09492423064b6c54fd0	1	0	\\x000000010000000000800003dab85eb4087ea36754cde922b3f18dcf2cf08c8bbf45db0d23d8af55cf88a4d80a1d0110e2871d28bcf4d5bef4216d6a9a3612d3dc7bb197458705f0366398db8e43b210969b4260ae118d8818842e1ee175c45cc7635e8febcece77df6e90acb4520f6caa7e68f259a3180ac5a2af73913be35e5ae0824d6cf2b4c97b070523010001	\\x4c973a088b8d57c68d6b108099d60b3acc3e91a7c9bc3b3a8f41109ffb4c10d5cc82acac6b2e26dac6d6d7aaadad6dc8be93c080c4440d26461fb3b252250902	1669892258000000	1670497058000000	1733569058000000	1828177058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\x7bd5bd2bf5c850c9f97f3be2df4464aab59d2797c34a3c3f90c40cbe880904dfd6614c93597a21608015c37c51c86dcbfb422d22ba093b21c1dbea6531278f7f	1	0	\\x000000010000000000800003cdbe5568ed2010a4eb99992c8bf2ea91d5c67d85a785b102ca6ef31ca2c32c36729eace1aa64d8a7f64d7f8e2b420f564053e839f78244ee6f1414b3ca46cf818c8c48fa69d444e5a97b7007e73f951d805b38c8ff471a22d36c1ae87b29929d358aa8b354ed5f4d934a8e886cd94bf50b45843218e8b7df0ba3461afc093441010001	\\xc005e6d360f509fbc9884d92c701cf159d698f503409d8d1a6a7d3349df67f12f71384018c517fb8071997b47dd1123a0fa6285a89d4e0f69a2e4455c8a7f909	1652966258000000	1653571058000000	1716643058000000	1811251058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
151	\\x7cc1d0ca219470e23adf1253f20309bbc62066bd334a1df2801f9cb37372eaf150e6ae3de3036c3a51f3efe7591e7b5854474d00ad0422ec1b2f95aee48168ae	1	0	\\x000000010000000000800003e990494ef5c1366e02c897b88086e573d2824c1c63d9b92067d7c40a8342a0bd1b4b28ecd59b6992d509fd2ff4463a0f57e7fa42dffd873335fa7db7bfe22af062ad5db0aed8ba5953256345ef416900bcea1a41b9fefe588c690960f628204221e14a2121086ddc7f58f94416978d1c6fd073eaec704d06afe63b12266a44e5010001	\\x0de09989d84d25d16f999a19763dd81a26a4625bd5d2b2bfedbb5fd543803a1a2f72ae9c6d5dc5dcf6c1083f1d067253e6f77aec0a42bae4cc1f162c16e46201	1659011258000000	1659616058000000	1722688058000000	1817296058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
152	\\x7f2deb5e08f5b64febd20601b0f95f804dcb9c7ab48dd34b55df511f9cce8af7a1c15fda4e3f66ab06eadacdcf467c9a9569b48f11aa815271d897a9d5efbbfc	1	0	\\x000000010000000000800003c058120231b6c421e6aa798316e801477418d9a51507a1454eacf3a6e45467e3c2178b310862805f250bf65d8fb122c2c360ad0fae9b63b36cfcf53980666f6a3a3da19f07cd846c0a3d70384f6ab3b25f248ff001caa6a315194fbe63e02d8d61ba51b80a7eba63b67dc3257f437c5df1d7fdea85fdbeedd9b708737ca3633f010001	\\xb1a7312f71f368ddf03ee9e6ba8970fc4d78358ab68c7aac736c1ac4ea18be528e90adb52f6493f775c536fd397d65f9e0e2c3f3a4653ed919c33dab15996e09	1672310258000000	1672915058000000	1735987058000000	1830595058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x8101fbff1c12e20b5ea5a6653452af951b6d654f82554801bfad242db7ff14bf8d8ce113c31c425b41d14d42e23ad8832ca86cb8a680b1ecd6adf48fd6200ea7	1	0	\\x000000010000000000800003a52cb61885f231537a0d192fc074655b9f2075fbcf1c674700bb7c5c3c4f2f72d8cbe55afcddaf7936f446f60d398e63f199e9446ac75ac1bcc70f0a245e766c518c12b7d99118a3a2df29a19557bc9b02aad180207cdc01f6d136101ccfee01977263cdecce9a5adf0c6f8f299279857b76aeca9f671f110a0e8a6843409b81010001	\\xcf3ab4b22b05bf90010a387d2583889b5a0753da7891dee3508812fed6e4d28b0b315bd5bed4d3b855786498a85f401519562dc21799998727e6fc2d2091b401	1656593258000000	1657198058000000	1720270058000000	1814878058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
154	\\x82252646dbe08614cd4fa53af47f3f363bb5797716031a84c45a1b488363dbde688b06c12145985a93261a568a4c8ee9442876a505cb95f863dd20513dd45c93	1	0	\\x000000010000000000800003aa4fecfb8df89e0a0c7268fc281150bec025f001758f9ddbbdc9d4ae63bec555ebbf23421532f569b86735a20bda1d4a6dff036371e71bbbdddab686585d4e592160109c71e7edf248f6dba8311b01a8d865d339a4d9bfbda249d3500c8b3564791fd9fa4719caef038e71b11db7686007aa528ed08c01c0784604aa9c6fa577010001	\\x47a53171750f6aae09c6d39e0c344e051f93075d1c4a2d71bf633392ab89a938c8e2e94e55522d6d2b1f7e0724f10c626a1b435bc8d86e9a3718aa6d1758f00b	1666265258000000	1666870058000000	1729942058000000	1824550058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
155	\\x84555b13113143a4b0f22a2465ced162663ef0dc674f1fc932f05f1368ea5f385da8b477151d50daeff10fd5a54ebc01828212982da831ea02fd7712afe88f52	1	0	\\x000000010000000000800003c9e7f4d2e2be7246414219a0f87607d08a859a1535f6a5397a1d461d4124b6b1ea9ba705ac6209631312dfbf92f226b527d308e48e855691644ff67de35a39d3bf173a093eaea78807cf07210f64fbba4e96f159c83d01bf20c40f30241d687df3a32b1ebe39b091d139d8f2a92af60d2eb95bd15808659c13c08bda237a90f7010001	\\xe76fe94b1e989faa8c167c471a362a884b8fa6bc47a849946165abae059ba462ffda2fa3f2080e8f171cee9110f5e7e0e63eb74e6c0b9d8a23edfdf5c82e9d09	1655384258000000	1655989058000000	1719061058000000	1813669058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
156	\\x854d627dfee85eb109315084b7bfbfd748384fee61bc155178c2c66997ef3f1e37154da8ed166d503793dc6a83434253803f177e628c31ac74a8b02afc8579a7	1	0	\\x000000010000000000800003ee028f72b7830d19ffa5d69ca2f9f15858dd848095f2b19ca92ddd4f07731affeba145cfe8b68772d9798faef889759af84fb59dc2841b55b646b3c9d6fe3aeac6ef2531ea7fff44d2d243d4f278bf8402f1f074e7e0cf878e43e295941bc1f03c63899db4202c654d7e12a83999039c06849363774e4db5302646b44c56d595010001	\\xda7b2fcc97e988a2779adad6ffd569d35f5bcfec5f81e664ed0637e3624f10a352e5fd3805dd3556e2a46467c606ba84182002d6c89d3084061559ec2fd41a04	1671705758000000	1672310558000000	1735382558000000	1829990558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
157	\\x86258a3021d0d00b127cb6162f9d6e3ab4a9929a4e614ed59e6dadd8a04e365c3dbabafb1acac545bd85185096b5224312c4dc77724e51f8a36c8a5a964ee726	1	0	\\x000000010000000000800003c6bf9227348b0876fb27be6b9089aeccf601bc72956e642f154df002e2e24a6c3bc5870b51be4dbebefd8afa2949a66b65e110c971af158f64357f6b080a42dd209890d7b110304aea3550e8c35c190dc063a9fe0c588a86624c3d92106e9d10fdafccbed6a412466208c6ed7fdb69e255490b0c281afd62e1e4883989aca673010001	\\x5fb663484eef9b482051cbba00485556949b41ad995171261a2fd9cfafb6d185e4c04e1eee446eca07f2316698f6f587a9e299805c852547edd39380a5a0ec03	1678959758000000	1679564558000000	1742636558000000	1837244558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x8741bfaf504fc15de959d838c506617913c92c688c904eae726add8a747bb776f0ebb327f30a88bd20a5fd5c9502af0fd959cc34dcf01b8af842f1fda49f7aec	1	0	\\x000000010000000000800003b748262a08cfa19fc1875507f24509dbccdd71feeaaa5411ff64a67baaa1d11ee9982e589bfe21f497b2d69a534817862be7ee7de4015f800e59b9a72bbcc35d4b5513badb6f9bfeb3cd1377817d07057c3be7dbf69d43227114c5186155f9a586b90da2ca77c35f0ca4b9c8e1519a0c5cc88147d4fb4cc2ea4b55545cb39667010001	\\xd42ea3608b613420783f54c42b2cd919a17feace00aa72c18ab9dad8191383ba7949d4157a18e513ebe3bd4f294823924de5a5ce2dd29977a9ecce19d6da1c09	1652966258000000	1653571058000000	1716643058000000	1811251058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x8ab5191573548d9bc7b74f855ed0dc7d37495b153d049f6d88caa5bc1b15d7afff6c1533dfce03ba50374a69f3b637a60a2542fc6dbce7eb529274605a664599	1	0	\\x000000010000000000800003c758238e06c20a9b585ec8f084351fe3dffeb2905be2c23cc005f52547d85cf7acb7ff264c9ea0f1da45a3195f776c53011cd1108fc8afa84bbde97ed48718d558e43cc6a273a5dbba31fcefdfe81a83446a02604a13767983e070e7201fb1f146daa7b7d251e7e4560af2095e24fb8d9f3d9ed46f3a7d04f0c7d0ce0bd28f5f010001	\\x05c9968c2167f312150ed40691c2a85f4744856d0cbff7d65523a19a56a89170ebfa54402872eab8e570d89156d013e685f6fa38a49c380a010751e0fa045607	1660220258000000	1660825058000000	1723897058000000	1818505058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x8e414082c4e27fc5cf2dde392c111e6fc8d44994d9a914ce40502bad0ec359248da8b3a97df796dc50c7fbeef2a6121bc72eb878f65c0e969a87f172417cd794	1	0	\\x000000010000000000800003d10ae3baed50c9eba25ae06befa4b6b5a2bfacb333f82ab9083df27c2c1de0eecff1df9959ea4c8a7e8a7ca37729a67361fa40bbc8aa9a2e6edcca0839652cc9c423c734a39dd896c8c3409574e351bbe4d56c13962cf25a0aab2e427238f00e6104ea81376fe23c4b91203cfb5284da04e45db997de3ed80706fcbedc92b3f1010001	\\xb5d3f988248931e262ff8d0d547b9d7d48acbc6e909d546fd6904cd64c8fe03a8c5709e2809546a23daf7ae5c0b1f128602e22e858068fc22fb6253c50fbc604	1662638258000000	1663243058000000	1726315058000000	1820923058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
161	\\x9035aee94c9dd3d8f7a30615c0bba9ef6e9e586625ab7d11c9131dd4309ad0962f6af8cb558bd84d09776e392531f29a71a1bc9b387cec07f2ed82fe8f8fa3e2	1	0	\\x000000010000000000800003c95cb200ecfaa953224a8826842879dda96772722a61b47ff8c1d87548e5805c644175d83750e6905e381e705209e88ac18da652b4c7d9c8e5e49641ddd449996c2c4316be5df6f31d662839ee0879ba9e8689bd95904d1a6fe186913952e987b3467c5e9d9c28dbcfca4292b085a4e532ee1cdc864fdef79f2d2f1330b23111010001	\\xc81a26000061ed500010ef8c02f3bf1c84f86b2a59b066402a2c71088e37909b8d3f42cc8fc4fb7af867dfd838c459ff09e1d28cfc652ff4266ccdcdcef6440f	1667474258000000	1668079058000000	1731151058000000	1825759058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\x90dd2a7a0cfc89b85f78903c1f7d529d2a82fb23e0608ffff64665e1d21c116b57bcf4164f3676c1f0082cc4e6da39a3713d8aa36ae285cb6ae9dcf799239ab8	1	0	\\x000000010000000000800003d54487b42477c2e12a497d0a0ee9a72608a10f09d5db975ba64d47391ae66dd391888e96fc743b28313f65f1bd3f8c45cd0dc80446563e0a62a053eba2b7021835b3722664a009ec97a792003881b9716cffdd1d6f3355acde791b208936becdde954f0e7e1b5686820771e25f1e4ff04e2eaf40aeaf05240267b51470b7ea89010001	\\x799439fd94feb274c03db0fb5231d930a027671c4a8084b91eb906721916a5f12a8c5002c4c4fed943650a2fb3dc463cc42d38c2edbe2ceb4259996637582a01	1654779758000000	1655384558000000	1718456558000000	1813064558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
163	\\x96c9715d95acfca97cab8959f07b21f204d47ea8db36aeef6a92eed303b4a6677ceb09bf61135d629ef1ff888e5e87c1eca0a63e227f76f122ecfc4c9ab63022	1	0	\\x000000010000000000800003ca51d5aca85da62f982adc5c0972ecc314ef99504c01d575d2bb8f78d195d15740162d3f8cbbabf9cbfa18c25e39c603ef634d07f476537cd7f626c75785f307a3d3b4e4e536f55dafb1dc38bfff71e3fb904af26684d455528b189f419518340565337bf64dbcc7af8af9492a65ca379d063add8ac6e42ff5270455796e062f010001	\\xfba8e5e6e1710ccb92d51d287793ac20e0d857112bad01feb32b31bfbb63ba1b496ab814fdf031237011e7c5731d262f61bbbed998434db4a8e19f07dc71f60e	1650548258000000	1651153058000000	1714225058000000	1808833058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
164	\\x965531354f11d9d818f0e0cc259d87116d2127ea97bbbca638f8bc91f56d46d5ffa19f4adb46658303fe61052e5c1e5f91165f65cf9c12cfaba47b80555515ac	1	0	\\x000000010000000000800003c5270010e016290e2b7ce3693efcc453bef8f5cd7c2a8a7957bf6abf77c9752210db9ca8984cdef0adfa2cf0d315f51dd04f56ea5ada46bfb62c9cb89cc78503ee9035a8d99aa32a6dfa48aea372cda201d8453dbad04b3c8ee439fcfc55feb344cf494e24210287e4a5172926ac3ef79074f68752ee833c5d6ff0982f89c54d010001	\\x30b92c6e1b8782c01cb732a715aee9a88f23e43ca50d1e6ab67e0b55e4af73bee5497c2ac398ec75f3003310182fb5fb2498db008dde36c1956ce75b3a23e104	1661429258000000	1662034058000000	1725106058000000	1819714058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x9a49f819588b84b2dfb5293b0e2cf72721b5970e3ad16ecf49ab76865f745be4d602be867f6cff7212a7e6a0f4942237763556efc2d1f764abddf2142d490ae6	1	0	\\x000000010000000000800003a94cbdfe60f7700becd8dcf8d51f6f64dc6ec9d4987306806bc4030cdfa010d806151445abae44d79fccb4be6e263aa16df8fb4fe1743609993f6bb692839bd72ee7b92bbe6aa322b3265436ad614c293f70b310a3a139ff9950ce3fbfb9abb862e979773a3d89d972508977199a3009aa7c13f35e84a642e133e3020d2d5055010001	\\xc7e19c2634f34f1f7c719b61682f2078cd8af8c9bcc3762e3de16c5f95835caf106eb11e910499dfe9766c41d7d3a32ab8760a75d7deef58ad7ea8d95e0c1e0c	1675332758000000	1675937558000000	1739009558000000	1833617558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x9ac5fdb18439cdda19bd6c6a9617e362bc1410d58afd879125d5ec529f95b520cc53359eee8b5d00c9ed5c5b711ff70e2febb970d8e353322319fcaf48db74ee	1	0	\\x000000010000000000800003c549d5e769d854ceca6ec25d3c29b2779c0155cc7cf7475d7ed0932b6b83e40321957193da01eaa9a629bd752df7783adb4ab2567fc9de33307fba63745f37ef242c478b04301398147b502602b3a1d75d68d3cdff6d2f15dca0c3f02c3d8fb413901321538383ab115bb71f406330d0579759bd7927bf2299f32971c6fe3e07010001	\\x6fc95f436130b1793e18a368df0b60857ae138ebd7a6163492a5cfcd9ec5f9a3d3743aadb1dc524ee640d0153bfc0ed077f22179980c69fe5da3b49c67fd2c00	1654175258000000	1654780058000000	1717852058000000	1812460058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
167	\\x9be5b814c89aea9976a50eae8ec5e3c2d6da219fa44161cb89b8d6efa3d9ec3ff3e1f8fb6dce5bec3885326b8e16a2cf0e520bd82d020afa606606eeb9a2c05e	1	0	\\x0000000100000000008000039fcfd7984e372bc64636631cde8df747709cd6cfdfe1de65ace07e7979d1f037a37aa3679891ddc5a4cd07914b59fb2581fc57e6254ea2bb8874af3e4f2b6e3fea5cb55c7981a5f51d0410f413417def3ba6a9808c6512a710a73a92a6df9b8770606743d3545e427371e7f0f047bfffaa727b397569327c246154f977d457bb010001	\\x72f2bf982d2c13357da0f80246390f79348bd7c4b40c75aa7366f43d9ee9121e03d5042554bf984ae8ccfa36f4d1e820d75e928a3b6b9b758742fb73ff7c6d02	1648734758000000	1649339558000000	1712411558000000	1807019558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
168	\\x9ceddcfb0fb20bfd7701665051cca645c95d310f89ad61c49735f265fbe30998a12670940f15804be22519b598a9f07b8215c2d79d36284bedd750aee6985a82	1	0	\\x000000010000000000800003e7dbe32d3564720bcb970e34db2d78e3d96bd847fda9f7247763b12f34d1dc3dbcdc3dc7d29e2d2994b2928ad4468aefbaa9e9eca123b733da1acc1fec6c6defb1ea9e116aafb6bdaf6d7cc02f8e838b401ca26fc65636a4d5bd2d349a5a1371138112f2b71b31f256f3383a5affd5742efde526f46b0147b7f5ea4bf251d9ad010001	\\x6b6e89fc8015b84e5b0eaf370ff4d4c57b59d70d750d4b6cf409195737ad1ee55d661680c292caf957f44c5db48b334d1307286f237c3792550b6c49881efa00	1672914758000000	1673519558000000	1736591558000000	1831199558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\x9c45586a8da6c4ff5134f57af5d086135456b269fd77ca95464d78d5a2b9726ec3d67aabd587ff880ba2b33de7395c2999771e90b3549dac7b069011c5e3230e	1	0	\\x000000010000000000800003b2cfcf6c1398f3bff1cbf55d87e4f5e4a6d84a59646ec600cb0825a50218d87d2d251739ba6a4eda000ff4cbc5a36b0f69afe42d13a6cb8ba333eebb3be7a333bff10c73e68d81b1558617caf43c98f3c3b1abda4be57c0c3b1bed9c40b82c286ae44e0e3a448693ae315f597c1938dd2fe253aab1f190ba0ceb2af0e845c9b5010001	\\x26c22cc09d2812ef4469f928e4ea00862a0df726ecfe1e064b0fb667b4aa7d1c69d2370493a76d899cd0d75c87a743194793e1eef734b1db176901e5d1990802	1652361758000000	1652966558000000	1716038558000000	1810646558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
170	\\x9f3197c658ef09a5371a93e62579b6867e4639812df1e8fa48da105ecec005e4a14b94691513cc793c1529b61b6ba185afbcf4ec163517f93a436f58fa430c8b	1	0	\\x000000010000000000800003c68f7f6847f80bb2779948525e5e724012ea5d7b66bc80d8da000ee4238529fe894b59f767f9bf07ad756e45f09b8e209735a22cc06bc68885a7fef01bb3a6f600fa6314422f252fa0ab857e3ef69348c74aef75d7b16c4c93d0d1e4c88e5bc881ba4a6698ec05b36c74438f6cb8a1e67edca7e3d97f059454e18e41f46daea5010001	\\x923fc989b5c434b263d0b3f86cc1cea04b5c3d09aa87104212b9d4f1ef777b7e9bb8ae37744389c799a230d664f554dc077aa78cea624d033dd8391eba1b8504	1675937258000000	1676542058000000	1739614058000000	1834222058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
171	\\xa2dd73b73e0894e780662a482a25c363c2553db343304328bd0c7257818b4000695a5ca368ea2103ed0076dc3ec1ba764f7d6cd844f4105727035f415d4faba8	1	0	\\x000000010000000000800003a4f3d71bf73135244c21b69b91d1a81bac2579d8718aad630e3d30c12fd0f8d9ffef3b34ada20121e050ba39dbee7b347fde9157d89715f91b4329c04e3c143d687ba8c92fc11726f4b0a046ad4c6260b836ce0b700c865fca47db0e2e06365fdfd912c15bc3d8b68906e8d4fa688915ba5a9d4643f6300a09ae7df9f454bf4f010001	\\x2e45cee7f12b298c955c4dc26120bf1bedb6aee92e36b17df387e69cfa2383a8661904df20031c09d2849412831d8e8d1683e41901f07124f6437c233af80509	1657197758000000	1657802558000000	1720874558000000	1815482558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
172	\\xa51dc45c0704f90e6ef7e95ebad5fbab366ec0df4e27a8e17ba598a6ca39c38526bbaa19867cfa8d9a65822fc446fa316ce85127319cd270fbd681a6ee44b692	1	0	\\x000000010000000000800003d5af124d8bc307e7938788bb3a7c2ec2a0a7f8958f0e64b58fe997f049f0363e1d1fc2317f6ed3360cde5f8684bdf514d255b4c9fd253c48ceba85a7d975f09e74b66b08cf11a1851a4f9219af4da029edefcc0cc2b04cdc71067ca4a1cbd6f98ce5467e6d4fa2af33aaafb41c6a596a668cb9e63dd073e666fa79f73ecc0321010001	\\x53fbf63886186d086c50f310f424e06fad8366f9ac3e0a747ae6028098199837ce4179b2a52c79032f87da7ccd42f6c5ec53f0ee9f6e982f93745cd303df220d	1657197758000000	1657802558000000	1720874558000000	1815482558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
173	\\xaef51508bab18ad259da79c9015ee9012754e3c7fd957b6bdaa199e748357c71a7f4c9ce41c62ebd5322775da6cdb23b8c58384c3815a7640e764fb784e7f927	1	0	\\x000000010000000000800003ad82ae1f7170141efa0d585b892bdf4cd3bb0ac9fd46d80c081c2204aa62884d593ae50a272fc4fcfa8a5ac2ca8470a86b1633d23cbf77f62aa813bdb9c8e73abe071f1a69e600f464ee39ff48e4cf8448fe6280cec12b0350b19336bfabfc9955aa1440088a9fef9c5f9ced8502138a91979ccdcf89183e51fd2cad2997572d010001	\\xd7ab90616f52dd7e5e8a09b2fdee199f697af70ed783f4093cdbfc7e62e204ee34908e1cdcb82b21db805d597c7044b183d3fccd0ad04966be3c0a2bfefb6a04	1672914758000000	1673519558000000	1736591558000000	1831199558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\xaff5e16822342e8473423c1442b5c05f75c34fd81b16665a94686256830594b2c247bd84a21f1e91e06d548c522e9350603bb4421cb7bc27344ac07237fb6880	1	0	\\x000000010000000000800003cd068eadb65fc99327c228030870abb8a363b1d0da101c3c0e7f6897889fdb1cf0856e59ca525410fd2070a9833ae69383964669f11d513c057df5e591b208960bbeee9844003c90969d3c317d167efc4b9f88feca1f037e9b0163d337782e0dbeab3897e71b4b97bc20e98e823cf4b6b446abc6490a096c7f483a87dd55e51d010001	\\xbebb05e2776f5935d03def132fb492ad2417e7d8c9df2240a86062e81d99f8bc91978dd8b1008ae7b9fc76f939fbe90ec2cc5c8f3adc557501f3d99c757a3b0a	1652966258000000	1653571058000000	1716643058000000	1811251058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
175	\\xb1bdea3531bb15bd05b5e6f767074bca92aa7fdd12166b2c1b328fefbd8ba072b27e877c464881514d9273d4e33a030b445eb682909892e7eb71067031978a75	1	0	\\x000000010000000000800003bdc9d80abf5c3134a44d0b78bda264ffc0d21c41a4819f0facbfaf66c1e70072449b7df932ddde9cb07d85e8bb0d1283a90ceee23954cb30196d22f4a159efb1af5529d71b00caa11536a6ba8b4326e130c79a771874bc99fcb1984dfe660c6732f22c0e91cdb4e12d08001ce0ca882c7701bd7ca4e23c9349b7bbeb348bf969010001	\\xc809dc2c8ac6716e6a9d35e94060bb96738ac652c430b2a76e6082547888bd46cd72bbdf3345ff386f2ac3cb563dfee41e8489d6b4c03dc17267911fe6c7830b	1664451758000000	1665056558000000	1728128558000000	1822736558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
176	\\xb28d2f4405acbad30da4d5a695114c870a102c3d8cf188c47a3d946e8a5c802e7a9db3a5aa7d43515639d32d13b00d81eeeb9a2d6416138975a944b542d6e24b	1	0	\\x000000010000000000800003e1bb226ec6869b12991ae160b71a38f675694fe7f328b9cd9be199fe2d29c2f79a6bc18076cda45270ef04bbe139c41ea95d32473108fb0801413f23a1bf5c3298627adb84b506347b32072bbf24328c4dd53f790a20cce58072afdae341aba2d506d9fae56a84988a68d625d50dec52626123abb2589d4492bcfc90c76d8ff3010001	\\xb12987cffedac8f25c5c39590a2ede2875addd849cd6fc3354c1541f1fb1e2fe3b46d72df200e7cafad698bcb61f6e5f8353c98a118dd67bf9fd0fe22853ac06	1669287758000000	1669892558000000	1732964558000000	1827572558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\xb739f64335ab2b0e7dfca7a897042b6b6ff06282907921928c3d3a4ae2cd12ed89f9f822f23ef80a44328fadd06202a81d9f5b86a89308102dce2e805a6e0ec4	1	0	\\x000000010000000000800003c4845389ad6ff96b25e2c1ef1f6b00a153e094f212967e828d082f6d0c9e3b44d06798ee3290748833964d39947e9e31348a3bba70f9d04d4b7aa855b61f0c4ed716bd4519bd6358fd916593067b965697b0b9d831c7f61120dbe3c2ec43723a8cc18ddd5dd91c0ae0740b36c4122825920e2dc9f506cb9bf1ba4c50c77be675010001	\\x36e7da86fb62cb3344764a2109b276e15e3e2249704be8f9346ccf9015a4b6a6d12611260061a7fb1e1a5fb30455e0312f6d62aabba988f4ff0418d59595dc0a	1653570758000000	1654175558000000	1717247558000000	1811855558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
178	\\xb9b97b058ab97b2dd76b726a2ec0a85d7971ec66705384e36fb5c1f8e854b0f8a4d2a5834b16e8a456735a621ed0d7ea5641f14415b1a13060e0d8d41dc112bd	1	0	\\x000000010000000000800003a99145cdefe5f26b6a6212965c5c0a19a90c050d4c901644faf3b60c364ebcb2782612197c15c9d7c7761946cfedcb2660f5a4e089f0580631011f9d49199cb3e1a37a970c163be587381d8d19bdf60c001d55548464623fe75be6b92164d3455d7e92e136f62737000a815b0b8a002bdb497fa5c29dff02e9793285afa64b27010001	\\xe3d3d82e9ff11572e9e97a6740b87f9cf73011acbae0c83db0c9cb59284827f63b32944561f68637c04a9069850b49a2a56ce9add5028cfc370bfe0a21e08f01	1673519258000000	1674124058000000	1737196058000000	1831804058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xba2d26701b67c3619a88235cf304194dcc201d33de96580137fdf92ad6c8f0f9ab9e23ac2b9ce867dbb6c6577be48f67462cd685ff9b6744f1763e786450ad8c	1	0	\\x000000010000000000800003a05fd2deee374378b7abfb115cbf6217f26c9a703cceaf3b33efc582ca45cc9b45750f768d67cefeeab432ef9860de5c3d4d6de149cb57cf1a0f9d271b893fb567529b4243badbb02c11b2d882f568b63d54cde3d8d17d05094b9cfc34bc20f564c093eefa47f508724cf71332090813ea4ddd15feda9e085b0bc94ae4dbca33010001	\\x31b89aabad569ebe713fca8f4cbdaceac3c77953eedea0f266f258c3df1b76a9823bb7445335fe63af1afcaf1c6dc9d8928842410246f550acd6cf53f581200e	1662638258000000	1663243058000000	1726315058000000	1820923058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xbbf1dbe8880a6e97288305f1b471ee06c04681722c4dd4c092aee6e1ca52538acfb9aeed9e7d58836e3c668d7d48b67d7b0ec75436be76b5ce4fd4212651bed0	1	0	\\x000000010000000000800003b22c5e8175a97332c6420c4ffbaf1edbb4267a8b8e6966e3ff2795d51d5b8371ca4a07334bca0e1bd2543bb40c9df24f4345fcdb54500a732b5c3d105664ea19489b8f70a674e32bff8631beb80b56e8864cbd1ba269431efc47b1b8cd4467b6f6f0eb5c728a6fa507aaabcc273ac800444b2cc18acbed25cdb18822d37d8835010001	\\x90a63bf7398a9392dab8f0358ed22237e812be0938101d42279a3c3ee5aab69c521fab936c1ea02e53341e848d0e98701223b9426cd8e69b708d0ef59e627f00	1663242758000000	1663847558000000	1726919558000000	1821527558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
181	\\xbc2940f2018bc613148273c33e985c2fbe257a4fc3ec1be0113d69a471bf43ac08167354aac2ef86c1a8d3958ce3b4e8c522fa56eb980f4a8c1d5b286858842c	1	0	\\x000000010000000000800003cfce26e42d4d293dc8a5e9b043f5d0cf5f84f212b199fc4a00f25972996f9e44e3bb64f24f3cea416e34d90ec22775fd42859f1543fd66978e37a8f27b36e4bad5ff6c85987678a7aa1a7798fc750e8194e1a2e2a05ca385c53b381d6c03aa38efad0f07999adb58e9e2f6a7c3645b42d326f391363fd0645d19075226a97193010001	\\xa14eec8428217e4006840223d771c38bae8485fd5465a4ccf73b6444ecac63128971f90d71d4bbe1fa6efeec5ca5fc361a8580ff443acb6a10f62c1d01583608	1652966258000000	1653571058000000	1716643058000000	1811251058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xbf559d5a43a458a320c7fbb4db86475269671dc087cb9841ef1d4daedf25eb35e30780963479afa50fe98d84f87c504416c72c0969c89b3cf7e828728be5cae8	1	0	\\x000000010000000000800003f2ee92b1dcef4962c631c06f3dd3e6e792868730914c7a63beaf2f9fc1f417224c6bbfc2c63060570b5dba7cbc737fae9e864b6530cd6d466a66f31973567021467adf458f42a304b3654b3fa205c9d30a6ac9f2028ae7948dfd937f96a7beca0f3a8f8d0c3a0c767cf1e16fd103b63c840314082973b5e2fc3246d391a5f4bd010001	\\x25506700a4eaa44ad336df165330993d8a40a8e1be24f6f821f939145b37628d71c70bd08971a00f03c94bb39c8925dc0e7da437e776c4910f6fdd1f826bcd0c	1654779758000000	1655384558000000	1718456558000000	1813064558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
183	\\xcad1b7314870d13ad9b5772f3a373853c0e256d2af731447f983ffe36ec0db6bcea5eb005fb1cb654b4627123b73ee3f04d24438c1cde5e8454cdd8af1e0b52b	1	0	\\x000000010000000000800003d4b7067e855a2e2ebd87eb4cbad3d4556a9b4c4096c3b435f24c16ef484ae3c67f3d45059735e3d0b24dcc5bda4fdd0f48685565f53a167d41f7594fa205ed9e6b60280f695d547c8bc015286933683b2a6ed14d75ed58c59de77cc24848d8d2dfcd0693961ce53a1a5c292b81068ee1d8e9f13dbebc2e989e3bed7a42212bb1010001	\\x32fb0336d1cdc3e39e9122fb5318e891c1d6111c6d9c106b06076b7f7674beaa88dcbdc8342978c809e1816e93fd989e71e0ef52498cbd72474dd53c692d4603	1658406758000000	1659011558000000	1722083558000000	1816691558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
184	\\xccf16e3b1bacdea274d6983d602acdf698abf6539f30931db6dbc6a6e2c63f2c7ed85a3e71a3dcfc4a68c87bd59aaa8813d09c0449040a8019d0c6dbf1cc8cc5	1	0	\\x000000010000000000800003cf2751a86a467d3359c03ee24fbaab2695e625536aba9024ae396b4e95cdd32e468144f0047c839f34a8f16388df9019d5106d0da92f877d3e610430a9f97e83d2927c9d678b7f2129d17ac209504b3a97f904f9c55630c18b3b7716a096c48a8510249d2773341c74e2f564908bdcf3607aba86fb57035b01e4e739481ce657010001	\\x13b4a4822deb42ba124fa2fcc8a9befa6d5585c2e80bcb4fb3c22c20a0358a4e3e4ac2d3f0eeafab429843084f2cd68eb88f4f1aa30cd0d5d612c880f72b2e08	1655384258000000	1655989058000000	1719061058000000	1813669058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xcd096f1cb344725c03d060df114a08426cbf0c2726ed576a46a1c550e047bf15ae935da78a7dd68aedc8ca9667a51cb3a60f0eaad42980dfea160915a28dd49e	1	0	\\x0000000100000000008000039f0427fb174fc1cc8499744d474b7c9161f0a617e2b59561a93a9a888ada9317db65f8f9ca036ef5d6921fd32041e750a749896f7fa3bd79ba815bb0682fe7a06b4389913f59f44e6a8779ffd62062847e64b9993bf68477c75b6de5a5ebe4ddcee31c2890d5670af9cb6130f661cd5f44afb4c1ce82018f0216758d2d5d29cb010001	\\x9043b97687fdc6fe116d32a4f431008a830c7c990d7ea4057fd9845e42c59ff21fc9d0fd18d90d4981466606b7f999182f4e1d59e0bb3efcc10e8f65c8155a08	1659011258000000	1659616058000000	1722688058000000	1817296058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xcd89546efe83f2934b2fedb1812ec8c30b3a425eb0df51b436fe960d7052f53fb054669cdb1570218cc4f498169aac20c31adb3634da55b4161312cf3595c08c	1	0	\\x000000010000000000800003abc96ea4996aad659e16800cb312b8462d4009657b8fc1238791a90fe3f5175e9f8d79179d46b492c41335ef273219af2665331fd787db7742fa75b1191c7d15923ca902e8891df4fdc4519327237349e1c5a87757b5acc445ec401cbc4656aea659330f7054d3816f13216bdce7190522d4be046ebd11eaed4b69abe616ef6f010001	\\xed4f69de5d7e144c7a88bf78dffa7aede00cc9d6805f6a443ee422fc9085c386ea43bc62d5aefc70288f85cc4e07207e195ee83beb149f0ceb7ff1b8ce42070a	1651152758000000	1651757558000000	1714829558000000	1809437558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xce3dfe76414a6ca91e265652b9e6dcf1d879b338ba02210f2b7897125652dd6a61d4d59ba39c56bc4faaee9e342d43f395ada055d1c610877d146732338fe1cc	1	0	\\x000000010000000000800003c0cb7e6948ba0d9f5c549f722c3140ec3e8f4ff4d8b7054b8f96e27f61939e35b99ca8073290d22a7def31a249012d0a4c99c0c9fc9bbf47395af393f11de7a4217baf79086a4352f9f4f3811dcea90f174ebf9d4b23bfec8be03610238623b605eafa4f9b4b681044da9fb2c3ae41336e14da45a2e798272a90bff1bf86bd19010001	\\xf2b3abf5864bdc30f4caee9b6ab8076d5dd9fe36dac59bc2bcc196053b870cd4635b68df3e81cd1eb1c9c9949a427dbd496f8c3e5cc14a2d27e0ed6d7d39f002	1660220258000000	1660825058000000	1723897058000000	1818505058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
188	\\xd5d1bc452b5f9dfc6213b5559fa64a358df31cb390b39c582aa37d9e961a84daa2cbf2c5cf95009bae06fc6e7e288cf4be341fc71fd16a8923abb5b42c406680	1	0	\\x000000010000000000800003e0586b8d1955977d1d1a12c36ac31c7912855c2938c05ab340a479f8bed2b437f3c106c0817d6a948a2bdeefad3d5245afb7ede82fbccb1d00bf75594895670d52d048795185c18d26b2862ed5327b13141600145ca454bae3291648aea833e1d20f34a680688ebb16aac6a2694ce8f7ab725124e0c6c889ae9cfd99f264c2ab010001	\\x76fc522f6aa6b93a693dbb36cd2911431206e597b7cb9876449bbd164eac02791c20ea1cafdcd5da15b54c1dc76fd06a61f4ff4cb1ea061a231970972e157b0a	1677750758000000	1678355558000000	1741427558000000	1836035558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
189	\\xdd2909f643db3771efe6e1317a09fe3c1c14a4dfb0b60c7c36f879de17df6a4b6dd0ddc69b6a8cf8acc38b7685d7d94d54c27db3b2e0acacdcdc47629b5bed1d	1	0	\\x000000010000000000800003aee6e853d0cec317e6ada1f6f8bff3f593e4f07e2258aa3afdc118ad2cebc87218346eca0e3b795869b72b612df09837fcb70a4afae76faf33be9cf42fa05e74babf626d15015734a3c29a177294ed9e45141f0dc45e7da62c81e3569ba5b3ece2300440f1edcea353924b7d189ba8faeb0d1c4a7e5718516d1576c88aee4c51010001	\\x337a0b5d94e3ff2f7ad3a1a216458097e12cc1cc972508915772d53ead84b31a1ffef07b5d3cb9e3ec4e2044af4bd5416d6781071a5231618c9e9e0b38a49c03	1648734758000000	1649339558000000	1712411558000000	1807019558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
190	\\xdef5744b81a4fe9516d93a93174c5c0a5137f534a8169650fdf2db61310d8535dbaf4fd995bf4d8b63e0b71ae94b667a4878aa56f4c9e896b5cd571682f23289	1	0	\\x000000010000000000800003c0d115fa1e41226dcbf7ae07c95346eb432383195ab75a6d510ceeb2ecc80348c96960ecb722d91af24639244578a7558728d6beb9e265e8f3a1344a6ff730f2726747708fbf9d56af97ba16c2d55f002bd79657e3a013051bc98da5e0bd1f81ff547d5640e9e233d014b56037b697067f866c26dec940de73abe73c006def03010001	\\x08c9ccd0b5107bc7f152cd3f24dcf1e579a64b8f743c71f2defbbc75351aa0e303640453369e1783f4780678588355df8622ef7aca2c387d6d902f0a357fe40d	1660824758000000	1661429558000000	1724501558000000	1819109558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
191	\\xde25029ea2a584b122b39ca888f2b94e648c63e92a7fcb9b26b3c1814825397a440831fde56d0dd559bb9411c75376ed21ee98233ddfab1f263bc8344b467b31	1	0	\\x000000010000000000800003eccf795723ca5f9a48b582f52d2ea7d179b315ffc65b6c9c129dcc68469848846524f79a5bf0ca2f20e6e9eef7b32ac69cbb9b251927aabd78cb10b79e3139e5236c8454389933825b3a4170b5634bd8c9d70b9011868df6d5dcf6a65e3c862410cd1a16e4c37e3130a2c0aa05034859c7fe73361bc43e2a5d69e2f11cf34fff010001	\\xd5f93801015cafb9d946794d6524d85299f922d78c1da0b07033c6c2b5c3b26497ee33df06ad8845883b2472a69c48f1239b94e80904149bd38da4e3a9b2dc08	1666265258000000	1666870058000000	1729942058000000	1824550058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xdffd1dc54fe581a8e2ff73842e37fcaeb991f81cfa19fd77d7b2aba6f3abbc87451aa92d4cb3b80c63c650fef974dac5a2b2c4e74ca974d39fdd3fd306f773a6	1	0	\\x000000010000000000800003ce98c52950b35078f339eae558e1d4b8040f6e23f8bd831f11305dd9ce7830e4482cbe47527d9c547a35c550acb85901f42ed51bbaada886a8cbe0f53925136a3d6d2e742045cb973c56ade1e55aef32758f9ce10f7b977a964795066889cf286c5f339b6e9f92ac8ca2536d42f5ef7efeacb3ef7993e060fc0b40e68320c6dd010001	\\x49df93a9480d5d09323a20161e27a8f9c6a3af1898678885eb00cce9273460e1e49bfa831c10a0cb7d16bd22b0da7e04fd8aea6f46a728270fe1b710f41c0205	1672310258000000	1672915058000000	1735987058000000	1830595058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
193	\\xe73dd22cdcee3d606c5d279ff83bc653e8110c7e1eab2ac602c199e09ac92286a1d256a10d56861da82b875722e5221f0b6968d3f1eaa9ffb9be4451024c87af	1	0	\\x000000010000000000800003a1bc23a5fc08887378132fe1a6b8fd989092f2b598f6a45c92562e2015b1137c73801be1c27c722094487eb609d524dc35ebf0f74c340e14e0f465b9a42f97fe2fe58aa06aa33b2b0db06afda28d373a451a15001cf81479feaa8465fc6b1eef8373dc17ac61c48e6dfeca96e5aa718dc937c1a5c643ffd68a0dc895c4e84681010001	\\x7257f838087fc0c09cffab63d195d30a526a3651b8acadcf72a58e19d5b300c9cdc6d58aa982273adbedc1bb35d7fa033f2ba4ce95027429fdf2a5bce20a3007	1670496758000000	1671101558000000	1734173558000000	1828781558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xe83dd6ba6057a1ccb6fe049f9bfb01cf5f9bcb8525ff7be9a8264da2992e4a235156c9be9b42127429cd19d707c30ef23f9f32439224d05e662af8563675764e	1	0	\\x000000010000000000800003b0249cc19fc8f94442c48ab52cefcb87bbea97062738dde993283cca26bfa8aa3722ef341d1ae9a229e845c7775d0cbefa7eefdf03615a2e0f3d3f13fa84bd813ff65b3ebbb2b789bce7298cab8a793af87cf24cbdd64c9b919d84629530c7e5784f81b131d74b915523779bd6695775c10aadb3df3234de5e837a640c3c4a11010001	\\x91d31a64a8cc684153c0bea9b559f7e6627c5bc572e67b6d8e55c0a6c0e76e61808e9ad34a7f79aa8a733905c2697c1d6dacd2e00de185af6e00000b7f59a20e	1671101258000000	1671706058000000	1734778058000000	1829386058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xe899b0c1be97a0d3b38262aab8e7cedb85d7027273955d02888b7c1a367f19d56aaeac1c4ea0eb9a37ac86040f86335383591e7469f63e3c34fda703c6d9ee5a	1	0	\\x000000010000000000800003c59b1f4b98468ecc88297050d993c41f3d3058ad05ad09919ea0b973ea0b914a450b2289cf434084e9c61f6eff9030c0a18e3651e868b82f2ce90fe7851e3b2c34a01c3cdfb3f815c0c3573fdefd8f851f08559e94f890043d2db8a90d1d07290c9c769d112e8d09b1ab7163aa3b1a132b49ab6301f1fa69ec1d142d1f8df5e5010001	\\xde14b367cfbf771caf6b550f5a28b5dd9d86312f3664a005b6c470a60fa52604a28eb778a455a10ba35fe626bdea5c82bda6806bdfccbaf2496f4b70acd88904	1678959758000000	1679564558000000	1742636558000000	1837244558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
196	\\xef8991a57cb65f18b8bde2289b9574097193b24efd4da734cfaa9681aed47d230207d7c13eb08f662539233098edb940e3884ae69631dcfd0c87abb32841d1fd	1	0	\\x000000010000000000800003dc4098bbb204a632b32e9553c1872551c8889237e8aa58580134d16e82b6f4157b59e9b48d25157189c0ba2dcfc4ea32fa920e17fa10ddb357d78031b6817d694aa465bd509af4dd2752747707c2d8215b8b060015c5949a4c8a6d98dfabb342fdd3cf2496c95b76e00a90f4896ede5b30828ac4d07d5844148a3f7b995634f9010001	\\x5b852e8cbebfd06c7cf442599b44037b97cdcc4029f8948530443bad2652cad78647b58197b4012723d040089508e9446ca0d3d7b8edba3bd080b66b6ae96503	1662033758000000	1662638558000000	1725710558000000	1820318558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xf0b1ca25a8eec27ddb88367c4ac474500d286a5ea88ebc8bd03fbf6d4ab6a22ff64606c130803105bd90b21a1b01c45438297e99d50526756b4405b780a727dd	1	0	\\x000000010000000000800003c806b584163a5f749d90a43a6dbf6df5dc2fe094f3dc873bc62b38a4af57446ce96566e7f83804802227ba5480de37345b0eaf176cedb7367cf99cc673503662d45b68ec0c055fb3d494fac71accb1c9f70f413f38fa7dee935dab6a676d97856ce3e2aba1c5dfdf189a37308c22ee89b846959ca070291540a92d82d081ddbf010001	\\x7c7e4518385ad4f5a45600a2e820f547740b7c53cfee3427917acb6d3be6d8c031d5d87df19e19196187aee83608b8c7d979f28a888c2569559182e92094c501	1675332758000000	1675937558000000	1739009558000000	1833617558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xf2ad20d48ccc944b3c26e8bbeafc3b858757bd8466188c45c383edfd0176d331669cae0f50abd3408c649402db6c7ab0aa270ac188c8d3f96fdab6cae3f798f6	1	0	\\x000000010000000000800003c08cdfbdef99b5dd47e19e20af63d4fe854f74ef4c93838109c108a6d0bc2c10a87720a19aa0715b0ffb269634cefea0f54e58b99ae43bd1f8e063971b0c3f208c1fa1fc904fc034748d5495ed5a2338ae36378b17afd679aeef0f81f6c1e72fead5ec085f732505887f8f68ea14eb900275b4dd230032a70ace27f29934e8f7010001	\\xfca27c3ca6c9c6d96c5852ec5f301578e91fc25a7de6fb1d1d65a3ff415dc95c7b41ee0c943815887db509f76ce2f128e8f3304c40dda67ad8bc3d125ec77c08	1664451758000000	1665056558000000	1728128558000000	1822736558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
199	\\xf781adc9c139bfdc29637fa89746d5a9a3d88c4e4be5b9bc769fa78c4a295aa40aa20cca50a32235d2f049eb8c062e1898d9811a2ae0c65f8ac5d7d8ec99c271	1	0	\\x000000010000000000800003d15b06db10dcf1eb9171063294ddad98d11d6c68882cab54a01471a73cb45e67afc2da21546c3bdc0335554b628ab6a13c16a038b9480325bef34215f899afa7fa6fa87e3928a4b2de68b355bf0c69f0bb3ac230cb83152af0f4ff73d586ef998f608d89d5aeb9fac7b8cd9273579dd41b436b0ca4732f074e75e65a4240f74d010001	\\xeeb51578e5b7363ca208632f83ec85a01a7749393130c1dc03e84163a3eb51aaed4bd628a75dcab31700b4a1ff90208474597a3542550d375c9ede7c31ebd90d	1662638258000000	1663243058000000	1726315058000000	1820923058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
200	\\xf9d9bbba04591f7502524cfff9080901e74c0dd1e26ad5ab672f7e5365f7ba82f402c5e8654b9662c0c2979c7eec06c0016829ab7e44182be163e3cddb6573a7	1	0	\\x000000010000000000800003a60d54b03089ea089127cdccf9091fd114e047f5123e92f59cdb888517add34d0a9b1330672911eafb5d83b15b8a68cee129eeb28f9490fa4aabdf5e7d42fe675fe03a0410978cc52ebf315e40859bd23a7110ba95d57e48bdd83280662ab2ca212628a5cdc04dd300d9dce3ec59406275847ae1adf275e9a9fc6d999826115b010001	\\x001c0e6979eb7a7db93ac4298ea9a9dada165504056ff314144e357cbc5b526193a776deaf7f24bf46f5076a1c08015191d1997c1e248a66cddf935644d3a206	1649943758000000	1650548558000000	1713620558000000	1808228558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\xfaa55f63321fff1231333205f2372d1a9f4d175edc6713fbdc623f77286ca36cdbc17e9f0def51b058dece51b2d2db99f82c9e8294d8ae31403a6af6e6dabaa2	1	0	\\x000000010000000000800003bc9cf3cb59b0d08ba5a0291ee3eb97ce8be0c4ed7a88477c131493ead149da56fc3c51585b12ae6dcfc2b1ce579bbe4247873989624d3cc8d626e67832c20f9660cef0bbf71f59cc16236ca2949018ebf4b90d4dad68d965a925e9387dcc201fb7aac8e78f1a75212220d80e94a16d76fc29249e8c96c06f17e8e32079f773ad010001	\\x7ad93fd3b4b2840804130840622753034c7e98f5f0d4ed24fd79cb9d14c9e29030cfc9111546c2ed1817910a93d80c432d2b8c86ecd1897802ba06dbdeb06103	1668078758000000	1668683558000000	1731755558000000	1826363558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
202	\\xff3973e2a372707aa80e56ad1834ec27a982a22b44920b8c176dbd4fa54a322bc6c239fa8886cd3da1674a8bf2ecd68564ab9b6c61d0d69be4463648d2901608	1	0	\\x000000010000000000800003c164e4e5568d06cb7b9baa312389f35200864faf9f921836ea9ea6a05a8cca372c7f6b707dbd4a0efd057016a883489b545a6226228b8fd4b6198380183f5bf218b48c59360d231330a7e4c84173c487e50430c7e051da8a4078e47632efb296071ff9ff63d01e615c24f900e4e97c8bc0e4d0f7fc3e65779b446b3a77ddacb3010001	\\xe38576ddd8479d3c74a84ffe62b814854fa89eee34a23ea050cbf6c8452d1548f717383008da7cf2a3d68b195bbc55873537145ec8666eb7aac679049362080f	1649339258000000	1649944058000000	1713016058000000	1807624058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\x03be679420735dbc0ae52ee60b7577a7c768ed14300eff2d225b724bd492f1c4f1bd573ab12e766836a3e4e984258aa2268dc9e28cd3a08db628b6a59ed1bcca	1	0	\\x000000010000000000800003b91d31c7b5a82c346f5ab7bbeb69ea4b2d4e05d30c54b3910b71d1163da104a0b1810edb73a593cd533aa4fd6cfb6ed9668088fab46c74cdaf8fe1ae18a8f3b2e280de3f78061d88b0c8bab6add7883a5e32f8c408c968e1cca5b52a3281f0a0b18c24d917203599ae47a4db7c32c3634f0f8474751399e61c7ab5625fd3bda5010001	\\x42da87a3ad2558d57772d52f5e096dcb5815ecdd7b0c23e8ceb49eeaec9170072b467e04be50f79d58ce46d6dbc640168328fb901ce3c242eb604f43ec599503	1676541758000000	1677146558000000	1740218558000000	1834826558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\x034654691d8d6965ba047341501a8c81cac3992ac99f0807d48719b3afabf5480253e4cf0ae26229da9481108e9875c4484e0b9e3bf584f1bbd6b28b2317ac2b	1	0	\\x000000010000000000800003c893f598ff642b2b26ff510db25d9b689903e912b2b944dc5ddd6df316471fa4fb767c3329c84e09350f56c34665aec6a79f6c2819fbfd89e3e8cb7149b7ef14faa4533c6f45c349abb47aaa1af31a2e95583f3dbd3d78b6b9f3d7bdcf265d95be18f9a7ae19dae8c2197a706b5c976bf068f78fa07ccd621c4c51dfe228f16d010001	\\x5671684d6fb250781936c3b178f51f7e6e1d65c6ec9b587f87bad382fd15d987d96082ff1d9d2df08731491d94900ab468f688af18e7e42c984957d34aa8ad03	1659615758000000	1660220558000000	1723292558000000	1817900558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
205	\\x0866a4db78054da289615fea3267156bc658856d9aac28472f40e1b15d13a97a8023490643a63283dd6ee9d258ca96a20a1304b82490c98169aa2dfd875005bf	1	0	\\x000000010000000000800003d3c26f838ecde162f6b45841196ce131cd12f0e6b67743e10db79379766281ccbcb32e7d548dbf1cab44f3375fe81d45b5312f9c0c48a29a0d9c65754491bc5e38d9960948194d378511828550989a73193fea14ba7efb067aaa89fefde9b0b53e8ddf7a9234fb613c876b6aca1324f9fa6d1d5f9596e10280c565c7a144a525010001	\\x61e28c745a21929342acde35f72496b015470db169a2c2b969d4b75747ecc61f7f32d449688602d2047ce4dc8019b50b7e15cf391d442fa81e555143e3581b0e	1650548258000000	1651153058000000	1714225058000000	1808833058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\x098a75db79ae45bde9a7e390bbe2a1383394be50e932d37570350b213f33cb6abf3004f07f66e769ac206afc8ef03d976410aeda7daa46ce977ded06ccf640c2	1	0	\\x000000010000000000800003b29e4679454bd609bb1d1301d054333123889aa8fd4366a273129a38499dbc5e86ce118d780345d6dd1b4241d73707c11e5205b863fd1a3525b0415d43f2163576f2f76239960d2fe4fdce36fdbb8ba29dcd1f023853178b24f1261086eff2ea9f08b66636e50b7fb59d22b69ff748e8bf6e36d458e31ecc0cf53a0bb64c42c3010001	\\xb7432d6794613df88bf8ea6d9b27a5af01f70099293710beceb7e744130ba1863b5d99489f9d176c3910a4aa6defba26d446be15170e2719e3103786cb1c7e09	1667474258000000	1668079058000000	1731151058000000	1825759058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
207	\\x0a3679a5892a801eb3e5aadb037ee8dbafaaf8576f5fc90929fc89b0c3d7cedab3e909ca8b54479d43b8feb26e3cddb1eecadd6f7a58fb02ad4234574050c5b7	1	0	\\x000000010000000000800003bccfbff2d60c5a591c71bab810b022b7baed69392ab8ac26f0bb0a99282b81666c4939a2490aae9184912017895b677677829e9f1afcab71821e6ce41909d9b1c7a954d7f21da7a0044c7c0e09df3e3da69a522eb9f6cbddaa89bc7767b27fb6929db4f0e83c50939a4c2d510ed32d1d39f2335c4fbb88ed8e2f8bde48150121010001	\\xf526ef2471646180aba5fee3384c3d109b5e767e4802e8b88e0a4306496eb96d42b4db4825bb60672fadcfb8ed89f48e32665a3520baaa194a936e36bc382a0d	1654175258000000	1654780058000000	1717852058000000	1812460058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
208	\\x0a3e423a4b62c8d8ab82720225690ebfba6bf59f0c38fd519d4de9403026cf0ab98e5d639318f9cadd9146725e0185864fd7a517499f26337da2ea904670c818	1	0	\\x000000010000000000800003c7904d9147fdf2529baa3c617375fb7874a3c92e65435b873dddf605b2c0576a4fc9f66ad5aaa3c3f8ba7b0cc67a9cfecb05586d95585537996643878b48320b79018e14f4e5ede05ac912fd9b9f26a17175de9f98c1d398b7d708d481dd1349a000c8e2f3201a6c00853bbe4e4eee60da2d5f7daaab76bb0fc2a8418a68c655010001	\\x703a4c976129de9da39c9dc95a51fa1c96113367e6b7a5b758a91003b605774bf80ab3466d453be110de80fb4eaf395a0ec411d94f3a2166789aac241511760a	1678355258000000	1678960058000000	1742032058000000	1836640058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\x0c924ab653e66678116070391656d8a2f399543fd7da8b0d06e668dd75666cd564e8b4df095a5eb3d6adb91cd7622ba8590b1f3198a06ffc9f5e66b2fc3c61bb	1	0	\\x0000000100000000008000039f1fd3d2b171c6c4fd811d494154f995645f60d6e641c68a10097d31c754a444fc1526cededcc6d087b46503221d509fe4c041f8209345b5f40233ae62aa9c45dbe762dfc75c2c14747621dc5b879553e782bf2c147ada8ca14570511dd7b573448254cf8c651f3cdba57f1786e0522ab87a8e203a6eff08190b4835bf79155d010001	\\xfd43c9063fcdc29b7750f7e5fe9822247bdf05f2c60945f34530101f6036c3d452217bce85fbdfcea3c214d48ea39fcf442bbb90285e3aba08ac09dccc5bd709	1668078758000000	1668683558000000	1731755558000000	1826363558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
210	\\x0d0ed8b64d3bff38c5f03b8c8edeffafd770fa3ca68cc6c04e75252a2aa09eefc46f09ffe60a5a349478dddfdc3af722a1e64e243096e900b38f020fc96efec5	1	0	\\x000000010000000000800003c2f0354879470ec70a9b758bf20d1499c3964ec7034cef20431e7a8080894ecfa72761d29965c9e90e72fa011823de7c2a8d8b81ee25800119a7daa09c07a951cf197e67d4f1bd37a3c496170729284ad52b31c77b5a0cfb1b8cda461a37598a985f15e2a87af2b94011141e515f5cb3d7993dc9fef9cb7b27aecfcbdca28e71010001	\\x246d414966a660cc115485031c007780c28efdd67bd7ebf131a3eb72aa3b3ca74a16408c3a049bb58c0d25f7ba3cde4694885f9fd763d0d7b019bb6d33bd2a05	1663847258000000	1664452058000000	1727524058000000	1822132058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
211	\\x0f6658172db78e1cf7a7daf0fd75cdc057d27871364dcedf70ae5cdb930a6694b6b5789b6e0ddd02a7edc67701bf7ebc86eebefbe5e6d36a555c1181f71c1cfc	1	0	\\x000000010000000000800003d055619842be2f2fe3f8c9f836d6bdbd44b6c814f256dd6280252404c42d3afe9e5bcf2612ff1427e7d36d4a2f09aa0e11ae8ff0bdd26474c6906e86d6adad4bcca27c4dcf415fa0dc91238222a712317fc9f8a325491cc63b30aeeae1bfdc113f2998ce60237ae29b926a60e4ac3b4b3730e58e5c953fee06d371bcd97ff103010001	\\xf5f6be587db16f7aa5234719b042bbdafaf7e0f46eb8f781591d4ad368f12f7f0b406ed7aef0210dd9ea5b7f40dd842e360e00b4f7009c59c5e70b8789d1230e	1648130258000000	1648735058000000	1711807058000000	1806415058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
212	\\x14be8a81c85c4e9bb2ba232d0a790af356315936e09f94c5e85b89d8dcaef11f9f4ccba5a2539a35815bf30fcf1c1684172b8d87f4d6907e4f94b9a3169e3f60	1	0	\\x000000010000000000800003f760c92a95290d5b6aef7993b8ad82e6408892bf344b82896c2b4c088f88c333a52911b63329c5d5ca4e0fcbcc5e249ea241c1b61ff010b4188f27d8e98c4966a5eeea622513ea85bf6f06683d9864a61e81a526ba0b8373d312f9e63b662519419ab0c9a0edfdcc529057934222694f3773bb25fab1d4d91754d160ded41ba3010001	\\xc76a9df3c50a0d5c311152bd662d9828939d1bc57ab88c043f8f88073e8ebe263c55b086a7f228fd103ad9a04c1aee7df43d0fe4a81acf6336b2cf867e98d704	1649943758000000	1650548558000000	1713620558000000	1808228558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
213	\\x15f6bb0e3613d1312f468794b1d92fd75c2828ed7c955714b1d3d0a3f599ff64306c90d770d403a0416b15cc5b7360a32408403458f17eecb5de0d40a94d35d0	1	0	\\x0000000100000000008000039ec5ef056f77cfa1033495fba74eb1f28f86a91a279089b5b9838fefebc89220d6de5ef5cd41c5ddd6da3a029d1c2480565fd49427e5cd75a8afba767ead7dfc32fcb9da9270a0ae7e51867409cc1e9b48c36c1682164627cf9fd787df7b19f5a8020df80ead0acb4f246f183f63232f18b1ca23996f0e11d4c20957fd6bb65f010001	\\x623607062de33783a9cca5f21c253d8e825b71d42c2234e3735b37949e84412a2593033b445fef606c5117da7512b8cbd854fd56a26d0abeeab90231f73c7502	1677146258000000	1677751058000000	1740823058000000	1835431058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\x19160565b383d5052c6e079122359f75fab3e4ee3de0ba06eb7e9d746ef399cdf3beaf07cc9df3609f7a0ddf073a7b86f8a528e87fbd583d9c0af9476f9d64d2	1	0	\\x000000010000000000800003a7c1ab3d154b1f2947908c02f4ac20fc01063e4dc914fd5d605a5626c828414f95ff68d09a83dbbdc2bcba4b5c0a543663da2802ccef470926a04baecdbdf13f5392c6c45b2a00c1035948dc969e1f1465ceabf620796baec22f333a15707353491e8c0502c23ba3475f6af00aa2bd977968a3986fcea2c8fc5b3e3ae85275ef010001	\\x43aae77ff181d173072b1750bd12da43dbf23a439baa87459e80b5d11088f7f4ff30fe883dd06aeafecbe1f9eb739346a4240d7f7ade4d18dfbf346d8108fc03	1668078758000000	1668683558000000	1731755558000000	1826363558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
215	\\x1b72bf88eaa15bb2baea0964dd60c907361c1202256eed59e77042c4760a05f067833923a59e755a833ea9d795442742cf7eb095dbe5ba907da94aa784ce505e	1	0	\\x000000010000000000800003f6486e83a15e9b5c21866b6ef2f14423b089fad3e824d247f78a5970973d9fbc9ade25cc562d65ee113f4ec40a3b144d34c4ad0eed17df7ba14b070eaf676eeee72b4ac839095f1d596820d2f9c1c9df356421f0749e9e86459a73c14756dd269365272dbc279f8c992dc8386a493a80e7f5773546fb012c9a2c0d96dd851d0b010001	\\xea10fd6b4fb83b3f9b543a921cc7c2adcc8bf8ddbc7018694dedec0d06baca3ada49eeacd12c3d50831b1036a2dc7570627a22d55456f5659fc635b073070e07	1657197758000000	1657802558000000	1720874558000000	1815482558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
216	\\x2026f14e93841d8110cd13b2c55668c193dfc3d6e33aa36e3ce22f4e77096c18e5a4e61ad9e17ddaf0d61da33a29827cb97e6504ff33ae697d540d70d2f68ed8	1	0	\\x000000010000000000800003c93a9c01ff31e04976b9bb11de1d480596f50641691c3abc722db22261c43c0639e5a517377ca21863dc9044c9e59977200435f0f4663be0ae3534266602f3787df3b1f20e3cab87e0442e545a9a8a6d8d54ecb4baf8534c48aac0f1c1b469cea252c9ba8ba44955162af9adfe13a94721664a2ee80c07b67d2ca73fcf15689d010001	\\xc9b3a1b01442489fcfbe46c8e5cd2606a33198acb2bdf845bd54c76c30de5e494885c66f27ea6ec1f80349e64b08c6911b5a29734c14945f36374a156272a005	1647525758000000	1648130558000000	1711202558000000	1805810558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
217	\\x21c63b0e6d8c463a1f563fb789ecb210a4cf6443f7d99d79d1076880f20fa35f21db84cfbce970e18c7bf91fb30e5218aa1a16bea324dd7d3a2cf2a6a6a0be1c	1	0	\\x000000010000000000800003acd15ba8ae97b0f8ee1962ee3799638845af9dce12ef2f9f6b22f277fc0a86369c2c57d2436a9f9d276c217979ac81d23fd8bb25862dcbaa03ec6ddcf72bad90205b6df4a39b34484e589a357f596713cad1f11a4fcc5b515cbcf8836995a0aa6ce1c40748b16cd4ee6b4c97a3502543a3c26b94fd727c2e9a298b5721d97ca7010001	\\xe67da7b8bf47827a040c9eb0ffd1e550755dd7bb190a0d20a1381fa0a7a5e6244932ab9b8768894e40ca78f65d8fb7d73a5eb8621c2a112f4a1dd4d576402704	1660824758000000	1661429558000000	1724501558000000	1819109558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x22c65c96a73688fc9b7a2d51448aaa71e6d0ae6e3ea55fb2aaec1251aab74b611825f1919f0ba92de548255f15ade5b54a4c09d193b3c0715846123e34447346	1	0	\\x000000010000000000800003bbc8f505847f277a1d997e425113e8e4a1a947068c69a2e7abed4bb2dcd74c93fc729f9b0dfbe1fd43b6f5addc6b598d3866e0d60165d66a67da411d2193d36bbe520c57f1398f2194a73be74a0ef1ece8b3128b66727276eb373e7e0b333eebbfb79968b038d4d2751a4300e9f53f9ad9d8b92bd08d69732416022a217fc061010001	\\x2fa5782eb9fe8691a66552a5e308e623b8fac28d61a7692ae1d7be1546af531c7b1928be2125fd259a7d52224c61fd8308b645df90b051951fe432c62cce4b08	1677750758000000	1678355558000000	1741427558000000	1836035558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
219	\\x246acbd89b22ab3194a91e9a2657431a8766cad0bf6c03de7516a0e86d255176370a608074d04c117c8da457aeb4e2e9e4c32915f2d276ec65851a85be91be91	1	0	\\x0000000100000000008000039c2fa6e620f95be285758b83bc65d750360af15fefb1dd9c781ef542704baed431fbf0e379b6eecf4a41f8193645e0396a459064f20d6aebd7d901ad371a007458a7d21e5523aff27076d5a65c2e982431c2f5affea78964a387986aaed1b3af869d1e30fa20453b3d8b18c6cd72c50b2ef7b81b65712b6801d77e1c764d1b41010001	\\x058f3af301c449de44e5c7c5e139b9bb4ca426e775f30f0b1802622598b58a311153dd1be3f0401c33fbe2a8e3306bff72dd777f705b0f50c562b70c23b5a00e	1672310258000000	1672915058000000	1735987058000000	1830595058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x24faf0393422e3be2fcdabff07cc85dc7309f36989c28ea18479b3f12452d80cfa24dfe74cc0d6bb35ca2d155bc10a297feb1a4331d2ce95de8ddd39bb87689e	1	0	\\x000000010000000000800003a249d5918e2dda4449cc81f94ec6c80179625413787cfcf73f509e9e350d35df8dc6ff618202f3507c9e6be7682eabd2740b59f5e59f1cbf5a926c4d346d955dc068da643842733fe4e80b23228c78dbc003de853b1c82e187a65220923c9a12388cdd4aae46162469811131a405adc24bba964a836aebe52ad4158d6ff5d9cf010001	\\x66f8796b66b7873b4be7d0a7a0c0b1cd7261b1676d1135eda512fe1a5dd7d444c9097035bd4fc6b0c6eaecfafbd727f5d2ee38b8793308e9cab7ab56688fce0f	1666869758000000	1667474558000000	1730546558000000	1825154558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
221	\\x25e243d63d4001174c7d28effb8918eb138a2b83ecb8a6b92b70959b237f944cf9c74d99fabcdc2df2498bd9e820e69eeb3010cb1c1ac35a5414cc1ac1b24598	1	0	\\x000000010000000000800003a831de50c4ccfd4e71720cca13b7409517e69ff6070812292696f2fa2baab2d6f66e9c20d76e15089be86daf2648235c696231530757b220749705abc03108b35645ff3fe45d5510a3419fb51e7ca7434c84ab3eac69dc78d0f0957027461783295f8f997b689e993257c7b9ee842fa2b6f3b3c650bcf7e4baac9e181744f137010001	\\x8577595847c28bc51e1ddbe4eb6228ecd3f797abfbb29a4eb3dc688f2d4651ea164e5c208e045db55690e6ad56517b61038a8fcdd509db4023dafe1f9ee1fc0a	1673519258000000	1674124058000000	1737196058000000	1831804058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
222	\\x25b6daffc77e592a177db0035e57df2643d775c0f6c47e91bfab324797d01d39331db3b2e846d9e9d9ed87e9cca1524849f57302b6cf408b03da4bec31a036a1	1	0	\\x000000010000000000800003c82ddf4cfc019b86d431f975f06fdc1b8c23ebc84f8db54110021b6a5c3db13eccbbc6a791ff1ae2f00c85dbe34be775c9a8fac38f3ec76952895becddce839efb99ff3a1bb208eee5343eb2ce6f8c8cd747223806d7e07fed60ac249e5c007a5936bce667f8f795dccb30420a74063551e01522fd5d6cce14981b4b81fd45bd010001	\\x49be1f509d7f32affab40a91a56a343902eac14abc8217e8e66aa8b715df850eb3495e4066fa18331b0bf073ce34bd44cbee6ebda03cc3e7561e228979e6b70f	1651757258000000	1652362058000000	1715434058000000	1810042058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x258e2bed195a5f840faaf9de2ab2a9069a906cc9ba784845410b115ec3ea8244417e0414b704225bd2b9875078b4b370625fe68572f2050650df33a53d3d46af	1	0	\\x000000010000000000800003b6242d8937af518e00093cbd2195c9b70f4d887d9f73ccf5b72d14af066cd24490f4af5a9e77db95ab73600b72463ceeac55d3939bcafe09785e0396a59ae065460625a9ace94e49fc45627f7c993c7be224b34b4386401e7088cc5980ef0edf18e46b5b0ecce6cb9478da75203eb26af7fe58c2078cdb8b130d285e6cfd3839010001	\\xe8fca97187cd8a1aea163a347d6dec4fcde6269e9f5c0fd2ce6b4f54d313179983f217f7d9102f2f9630df40b08eda763826059520d88675fc767390d0002908	1663242758000000	1663847558000000	1726919558000000	1821527558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
224	\\x2642459adcd664b4b117f66714474aeb5f62815d6100d27f0670de5b162318833a615f28eea69151698866a0eb12e97e3f6ecf1e4a47c3e485405f5f7703696d	1	0	\\x000000010000000000800003c5f785db57a3b0e544e52ad858e46816d6eeab19ce1bd2dc396082807432e9c5b7fb79e02ef0379fb8c6dd14596a1e23c96ae74f09e21bfa0793a78ed6bf4b87b85eabc89d5f4437c9869bbd9a46953581bedd30a63f7c7fda2182702e9d586be864bece646aa8b18f4e0073cc32906b9d7175bfa065581ed278f43514ba5411010001	\\x7568b272d3f50f093082c596891b6fc43209899fd6fa337a1f5a1b94b21bcf30bc0463e0714728cf50c26ff860e474cb55018674cba7e45e63e167aa52305c05	1675332758000000	1675937558000000	1739009558000000	1833617558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
225	\\x2b1e67349dc9fcbaf4270593b15c2a5a9321b06c60ec8b2f174905006388440ec285125ad10fee4aa3f12e29983ec4123cbd0076b29ade3001bfc80988ecbcb8	1	0	\\x000000010000000000800003b5ae0e89b69ffed9d23f7fbb7dad65bb1beb063517cf64121eba94071e2010ac51fd35199baa5e1d71b5f863c9dec90437c8e8377e5ebdb27c904a5e0dca0bc3525cbe8a926fee620fbfa86f7c7715819e694ec10ba59206d3453c96e4c314cfd73c09bdb741afa0b48830af12ca7ecd8cf159384a93b97f6c69f5c577e76d65010001	\\x6487106c3a41eca0990be37d6d724640779b02c27d3f2c7795aac67a35383d63ba98419b1bee8239ba7fa674b94406f6bc15e8392b86bafa0355006ed33e7103	1654779758000000	1655384558000000	1718456558000000	1813064558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x2d222d54af54a809119752b9d726d6d56015d83fb8d9fb7d5f198a7d914ff73760a1888fc0c977d6f99e1c2b6051ceae0781456daa297a3214a2708af59c025c	1	0	\\x000000010000000000800003bdc23c289372192ccb3b48a4bd73f9f54acd9ae89892301a9a76e2ddc09e5be88ec375543efdfa837a09975df58ecd581234942083ab9e407b4875240d25f3fea1dd3c6b43bd2b68979b274ac0f798c41af71c0fea0bfd40fb509feb29aa7b6ff7c450bb04fc134831fa2a4747c02612d2b1f730ef72ca7f9027d35f928c563f010001	\\x8517f2ae91ef811675ca734ed2993a8c677ed0c8b31d4c9bce413484f927aa304bd5334eccd410145b3e8ba214575624a00607e4cbf356043e1a0751fa8e8006	1672914758000000	1673519558000000	1736591558000000	1831199558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x2f2a57d02f9da5cf20649e3248326c2c0ef9d216da5a2b92cd620eef540b7238f7c74290e7f90d2afd86076c29ce5ca14c9a7f6c652e388f645a633edd3157d5	1	0	\\x000000010000000000800003baaa5d6cbb1a5e4076890d3e50b83db338bcfacfa8d4eb20da76518636165a37f7142bbfabe9ff0624e742ade5128f91d4d96d458a6e335f08784acb1f97a2f3182f640d88da3417cf2b9667b1d7ad312d9e418f9fc555af3b18b672444df25a9c92e980888342038456eebceba0b8a758e693fda809ae6d726a45c0c6b8ddb9010001	\\x33f3d1a9d022d64eaa056bbf076123f111f0aba0a1214771210f51b537961485d42fc054427540b4a553c01fc284d225d6179839e931c33fbc4dda9d602ad008	1673519258000000	1674124058000000	1737196058000000	1831804058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
228	\\x3166d1c7678102815a82fdeb9ded32fa67f23e50d7ed35eb23c4ad655a22610a07ad65ff656496e7dc1381145937f357620b60e3e83d0d69def894324d4e865b	1	0	\\x000000010000000000800003dd3071e97d728dcba4bf791a10a97e5d6d1524a1264d0854cda2fdd8efc0218746eed15274050d0fcd11707f29307a15036d765df1ad11c37f49f596f80487a11c462e5db63a7d0703b39206bc286175dd83d77156df5da78a014233eae22175a3ccae09425105a80a19490f6dabfde17997e9538d1694353d29b9f676a6966f010001	\\x96d91d599e90928611dc167d96b622f41454b87661aa4338253a710c438f3924f960f5809113c77d23050c74c01e9caab35ac6df601514ebfab694d5a3c10f09	1647525758000000	1648130558000000	1711202558000000	1805810558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
229	\\x32de4cf5ea36e59013d54245ae4d4ee96a3a4e7fa58a63a7c9a6dca0a66bd200b6ce3a0cbb80996fb0d8c13a4b5bbe44105dc9b2f7b04ed0f3f7d73b94f4c01e	1	0	\\x000000010000000000800003cd04d3f41a7fcf25ffe62aa750302194bdf6ee6a8f24cc118477f75fba44c6aa3c73c90a4ea86fdb296960e794a31bb9f72e595f1cb54eced3ca3f7947c0537ae2a18669742b8de8e8da25b19105d29ecd3638ce20391b259691a6eb42faac1525dc8a54294b1126a3c2e08a08c6a6ba3d3c70ba9b543d1c6e2b51895b300395010001	\\x7ccd171cc75b8ab52199f4364b5a060ce4648ba22eac9aeedd14d49612145cf5411084f0127bc9c9f50c939533d5ad00dc528a22d159a0e0fe8d1b9eaf69f601	1655384258000000	1655989058000000	1719061058000000	1813669058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
230	\\x33821d846ee48c378c7ea352beb2c15af6ca1ce6fb6732e2d820432cfb21db174c6620c0b664593552e05f03fa273ee15ab0d65365ef2952276eab307ba09288	1	0	\\x000000010000000000800003e1cb3d482d09eb42936aa00178c9c2efeabd486c3456939ed4f3f768328c9cc7a2e560a72d86ddce21596559b0beee603db30b3abd431ea5a618a405a59e9e7b077b35b01d65add35b271cd735de15ca49615502969dcce92d3701ba4e0b8f9ebdb218b3e2207eec0eb57cf056f21ca2bc38c0aa3ec4224e6114c6fb66056f3f010001	\\xbda92a3263a963a6a9295ef16bad4376191a8a56f3cb76b28ff8b1f0d90d55ffc03df12b6cacfee4267881cb03eab47433dcc7f25b090899a681f23ece4a5306	1652361758000000	1652966558000000	1716038558000000	1810646558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x34225ab3ab892941b7d91fcfb204ce4728945eda513575bbb202fa39ec15d0f5c8916fb72153f9dd6e88aa79428141806c4c3dd8e2f5873ad6f5cb45afccdd20	1	0	\\x000000010000000000800003e755939e36f37eb3f770f224538ff91f578d8cf9c7277424b4374991037156b4b7b6fd0c884a1c486cfca5625e9bdf39d81ed83afe094faa669d4d717873c1b3c11f7ac7c75df7a02aa6f409a52c675109acaa51ba7a1d90f87fda35041499e881859b0c904924841a1d5eabeba8959de10a3f82595fda1b103b1aef17cb32cb010001	\\xfdbd37f5f4ba5bd55a7c659350a886339d6678977d3016251eefc2c0ebafe2d22eb67e45430ea74db9a9a3b3c347af67a42e08a2967f05452a5bd50b3cdc0d08	1677146258000000	1677751058000000	1740823058000000	1835431058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
232	\\x3792ce9ecf066117e200b9633d558c09d61a245cc0da5bfe7a78f3f5b368a7f47400777afa67dd6e8e9263711fb25734d11def4acf6ffdfdd2d406d8e17adb6b	1	0	\\x000000010000000000800003db78d3daeddf17a5b0b253929b8b8065cfb674a2e2cbdceb40210997e5ea05757aa61884878daab7510469ff0c1febbc7b06ce0095f1016961fddba485e2992b7b18515e7578ed800cc987ff5c43466c07658b73de642cd4b8188549638b803c646dcea54af73d014e5dbb3a5498450e849d65e34084724deee1542c29c1aadf010001	\\xf818dcab525d0f6e2dacc247ad7baec8f083448c21e7f1db85bd79b075b9f4d5138e4c56896bf0a3ceed19f6ee74babd4f7e26192c109e33970b104f10d93804	1660824758000000	1661429558000000	1724501558000000	1819109558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
233	\\x390a29cd6241c67718d694cd080d7ec69eee98f5787087decacc559e114d368536fc487adc7ea553f085ca3efe195c55edc3aafdf065a47934b46a067c492d2a	1	0	\\x000000010000000000800003fce057c81e46857a5e84ec923c210fbd43cebce6d1408fc7efaea2d6664094d9fee43e4de8cf20b275460c97b7909ae371e48bef3d0620ea4532b770c5310385542343c62b103ede654b6057b0ece8bacc4b2e0d95ae9a5109a593c044fc3259b3b479c0885b823d04284d2e7bac693a6d6aa08058aacccc4ff96bade60b6ea9010001	\\x578b08543b79d61bdeaf35d3b9ae1342e8b6623b77a6fddb811d1e6d6ebebb4dad0216506a4e5e72c26eb140b4b3c051c6222d36a87b729bec2572dffb433d08	1654175258000000	1654780058000000	1717852058000000	1812460058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
234	\\x398669848ea028f0ddcb7562b0ea3f26f31c7bd4d956e22292afca539cfba6cc69fce408f5a7a39257baffbdd35ef0e25b931526b2b16392b0a7c4d34008e2a6	1	0	\\x000000010000000000800003ab6b50b6a7c21597974e8777bb02d7571e170b77daf28edc09290012ee2ae58bd2c1ea544de1a33182fc6c03da2afaca4abb58f2bd77509960178883da2c3af6daafb9fe243a298dcb26ac68aa50c993098fc3c2d27ed64d89601d5bc871f20cf31d7c64ce5d3f32d93beca118a89e0bd687ece813fa94c88413bdb3aeafd83f010001	\\x7667a1ef4ec1df34215bdd07a75713fbe366ce6d9d9e5a2e00d87fee8ace2face23fe24b8fe6ed500396da3da7c8784e1ff6ae024c57bdf9c0db10d005a4c309	1660824758000000	1661429558000000	1724501558000000	1819109558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
235	\\x398e302a20623d5be30368fb2c48748cc6ecc1a314111b2825680f5838d57e76ead683d210d2e7a17b9e519c6b0680c582e70cd14333a8cfdf8c00fb0ff60db2	1	0	\\x000000010000000000800003c2a359090fb3bb72b65b819395c494418c2db2d1e5a8e9f99f561193daf8502f1397f4fd7ddefc207d2ec02683db1c659afb4203ac16d0ac13c81253a63a9b8de773da84120ea69074a0a0deee8952a5353274972270df2b5bfd77187ae369c1dd74818e459e991fd748f88c2de7920beac220c26f12b4ca14b1e353e990325f010001	\\x1468a7901ee7c9e322bb6a96bf4e2debc2bdb3637632ee8d3fcb5a2a8b7569b7c75ccbddc7ca5d08529ecaba5ad90c00e5d1c60ceb956c2faed170645594da09	1657802258000000	1658407058000000	1721479058000000	1816087058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
236	\\x3dc27bded03d72e3a57c8386a728aa70f4dd81277db9f6b3441bf8906d2601ffb811f04eaa10d3eda16cbcaabd3379ab9c293ae5b358d064bf64e07c4d7b024e	1	0	\\x000000010000000000800003c69c39f99ad133ccbb4aeb4a3074671b06521e3ecf4ecb72fd2eb75eb50bbdb5f42bea7a3c02651a143d3b1d830498ae143584db82351def7089af043796dd61a6781eb81222b406f480c4f576f26562348ddb98a6dcd1615ef299a5a44465e3bbe7efabc19d055792c8c6636ee912f7c5f748de17f811002a95f0d41a82c729010001	\\xc46b17c8dfc0d18058bd006e47fc267078206d8430fa86fc76b54f3eb9f4cb11fbd0cb8418004fefdc0b1d087f92afa58f9f36ab6ec3f9826ce030af582ee903	1666869758000000	1667474558000000	1730546558000000	1825154558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x3d32cc1443285b594717c933d49c29e37cbbc79b4e6d7eb6c9dc2be391fe0e893543cc9b5695b5291f872b027840982a332cad2b6ea11901dc914fc65d7ebf39	1	0	\\x000000010000000000800003b6888e7b57d95f21faffc38d724e980b77a4d01b17e4028bdc69df2ba112aefd1bf0079c4962b5f179a99c66fcb3ff18a797a65ab3a391ebe6bf1bc49ebaab76f3c93d265aac6787294785d3111baf6c07fefaf2c15726eda1ec671eed48ec13771cec16bee8db79247d374e4060e03f66b790201d0b6aace51ac70c4ec01221010001	\\x5c95c5914e0813c2d16ceeed067caa884285553436966b8c469621e019f4c4270ee851552cb8a4cf4b9cfdf9e9c319e344b50e9bed639f7f6c8d2cb7b1979e04	1651757258000000	1652362058000000	1715434058000000	1810042058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x3e362fed648a5169e37183172ded6f3e58eaecccb725cd918deba841050c70e34daa5b4f34149bc122f7e5d0bdf50ff74985c7ea1e7dc28de3c0eddb9cc4addb	1	0	\\x000000010000000000800003cf038d41bf9c25961bab5a9d73bf2e30ca15f804e85dbc73258f2a48147a2bb40f7831ac389cd0bc17884109538f21e3922f05d075883486055577b7de8031b1a37fb2e41b95ae707fb9783557f02316e4d72945afc916dcf85326dbfda2878fefc3c56ed61b7f46c497c4c51befbb8e32a9ba5e5b7455c423ecdbf5e819feb7010001	\\xafe684bcad53f043be3bc120fef80efc52db735a8d8bbc84ec5a662c78962dc533abf92d50407b2f3dad090de21e8a1b617de26d9ee2fa76103fb0c36e082a01	1662638258000000	1663243058000000	1726315058000000	1820923058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
239	\\x422a09aa1de99b01767029eb5c748d42d133591eca92600a2162e49fcda972ff4cf941573f756b31e79636c09163cb040caa82397e5ba403fed0aa2182c55655	1	0	\\x000000010000000000800003d48c9918ad26f02970ee7b707aa212fa53ce35a5415484eeefee22802bcde7ff9c12da60f3ebf137ad88e5409f8ca7d9da9f0d397b988f8f89d9825d8901882d97d1106c26c3d64b06e9254e70182adb7eece11524c7c143445da984e573a4fd0be6dda2f2377504d0679e62c8994ce6e59719ebcff18ee2ec0f13586ba2aa9f010001	\\x6cf6b166a58169fc6f32af052b97eda224685100907ab78a7043c8ee843cd794ca7f5a86c4ece0a7b2c2c9658893068e6184695866b64847eb6244a1d5f6b408	1663847258000000	1664452058000000	1727524058000000	1822132058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
240	\\x4356fd8cca92334655da01c2e48e4435c9c086f412dbc91aa024c396d8aedb6c43a71900c90265b05074e4c193fe33e62c5e2afe0d48fcc17bcde2b05ced5f1d	1	0	\\x000000010000000000800003c395c866842c2d609f5b0175b68f79e143a4f8cde8001ce623bdb5ed8a38c29198672e6e04c9f38d1ff4c1e09ff75dff4726d6adeaf608741ed6bdb2f371a31b75446f7184fd28fd6547a6c2d5dea073a9743eb39531d9fea121383e40c413b12879bb2d0c3318f7c99df5bb63f5ba53b2b71d4f0fb9f98e641acf2bb3f7588f010001	\\x67588d5323dba1f7e4f814bd45165836031c4818ab7a94911a4609f6bbbbcee91608f0ad3b757d0acf623fe145501f6e1b34129825810433a430e3f07a01ec09	1656593258000000	1657198058000000	1720270058000000	1814878058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x462e8a129f0591a170393120dbb9fe48dcd8e2bf161ac7923dbd8e7e2d51c23d9a5b8824529fdab99db326e73c647dfa13813d75c9360620a0e36de8c834985c	1	0	\\x000000010000000000800003d1df15976ecc7cd986e63ccf70a1acad1f4f417629dd897f6ecde8ac64f162980fc0dadfdf8148e0fa4ffa0b039fdaaf1872d3fc72a74865dca75ec58ed7ee62c33c855533758f3d5900bf1b44acbe4170051386018b63562197084d359050a2add0081f719a5129533fd0a716f1cc65377417dd6bcc94c8d64d9ddbf10fd101010001	\\x14a12ecb4c7648b0586b129c0b17396344c6a4251e8f1c735dda3215b491d44fbe9d062db2d9c77490884ac9bd82cbaf024a9e5697f2fe3c522d02adcb3be107	1675332758000000	1675937558000000	1739009558000000	1833617558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x4826eb3d2c0e1c96f1250dca800ac9b3ac3eac73484e109f7747d277722e73d7b7a3b009f2290d5142dff77bffa920f4c54a32a6364364c1e28db01c5e8543aa	1	0	\\x000000010000000000800003a550f5d161367af7866c0fb40933f7969140f10a811cba5623a2a578b79c3edd3cf7bbd6e4f434230c0f2e4d10b72a4f06d2f8b70731481ebf8919961a130d655432fbcc76fc669a18936a73dd99053b61263d8168c2a814f536646e2bce78f025e2710335fb3be7d13099bb738b2ab707e6f0062c8745c49fe3aa340edd5ae7010001	\\x1afc19d2e193f44bdd305a83f9c6be58c6f838cd9d33bca8cb5c440c22bca20df517a051902a5d117f5bccfdd29ae6e16fc89b9c259206ee2d74ec31f3ebcd02	1661429258000000	1662034058000000	1725106058000000	1819714058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x4846553b570f60ecae01b044ba3bc2522166c4f69f01ebc10240b296cb3a427dcfc20d327141ba359b818ddb75ac0b1440c04421cf7e780f310293cde7008850	1	0	\\x000000010000000000800003c269343017fbbfcb1568c0708daab9fe298fe72749d01c1984293b09bf499ade7f59e29ac60b4e48a0ae064d9e336c73213275c4694014e45fab2aed6235a29f06d750769a6901ac38bfa17d16912385fb3961c641b5269d77d787503db81ca92ec0c01c0089db07c3c5ff60cc89781a1fa10117e8b25dd08554240e01b3b0e5010001	\\x79d08d89a86d12a1b785ffabafae29141cb1c6f1956e45dccb6d0d10411a508973c4a881bf14a8e49151787dcdd76e4bf98bd124200592d4a8bf06bdba7e1702	1657802258000000	1658407058000000	1721479058000000	1816087058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
244	\\x48a61622c8bec7fc5f8388cd1b2398b26f2a113af8045315fc2de4887f8bfc7a0a9d22dc1e95fbddcda40706398cdd086d84e6d5fcd03646b45351292868d52c	1	0	\\x000000010000000000800003cd5508d6819a9f906928f9bef42fade08334c8afb13c243a11d035ecf5af8ee8a2171bd8dc720a07cb3f63f96b5e66bd52a29fd17159bcf46a90b3f0cedaa4e2c8d34dfb248788f46f28a302d9635e4e724ce977576f22d52ddf6bbaf14bb7a526286d81994d7062e0aa2ec84284ad8ab03e7cb608cd5127c16599a6ad03f25d010001	\\x4c826022a8747da246e7ae7953fb36dc6594022c099387371ac39992e2f10195c758d09eb388b2fcc97d52fd243d632881b6d51836daedfb0ac0cf006d420e08	1653570758000000	1654175558000000	1717247558000000	1811855558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x4b02efc17a28f5b43e912fa9d3eb392d5edd5135063f321c8f0f5c4a213654118deab67ff3e384190770bc9812bf1a11cdca97ca7bf2a24252a97eedebec9e6b	1	0	\\x000000010000000000800003f63ef9c3835665bc579290be8fa9d15b27b643da1e4b62e34126e483f74c0bfff00013154cccea2b2315d7ba08fedaf79c10287c7202b75d775e5730b8383d37d5e531c57066f30624fad11189a78fda9327d613b1623cd36cb2022f3db8434c25ab4c4ee921bc50293421de00cb2ec6b5abeaa64af6b8bc242148021c819f27010001	\\x74715fe9f1dac91bfff812d9cf4faf8dd2b8e737fac8f7eb3587bdf034caf60b4da74b49908f492d0d32e9232ae06003579d87f32f5f6863139e2b70cdeea70a	1663242758000000	1663847558000000	1726919558000000	1821527558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x4ea64a41cb215f12f69dfe4a055113c34327738cc50585a9727c4e2536c4c37538c9bd76c0f7f5181a7be92fecddb5cbbbc6dff22776ec978470143635aba5c3	1	0	\\x000000010000000000800003af321e6297effcded17bb5e4deb9737f7ba8f2a04a2b45f96d92396fb0242ab332316e63e47bfcca7f40832fa0f38b789cc59cc6fe779c62366b55fbab69249418ba70ad98e3387286bcfd3b075df8f98c8b6c8a3f79e45e46bb81a780bb7a48a62bfe99fea30bf225d7dfd3baf663ee23ce8746a369d0a809de095b5be74239010001	\\x3ec5b350b64884c1fb417b898a3544d34f9e0c23c7d434f80ab761d3248b08392e0e156dce8921424722e233ab094d1bc73f86590949f8b8dcdae54bd740190a	1668078758000000	1668683558000000	1731755558000000	1826363558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x55d2b833a0aa34709250bdae624910532756f7bb1f45acc1ed72c80562ab595064189be07380f48da6fd500a8cc535a29b38c6d91b8543e28a38971447b5093a	1	0	\\x0000000100000000008000039d1955dc26bb62d31bc81b43b0c06b0fd499cd9132d5709505a9384756ca42431cb8499c4ff031c4e019d20c14bceab54de441f36ef6de1e68b0345a1d8db73ae299027f5c2682f1681ec4be095ebed5b3bad9509cf2251054671f28e79288ae735c75524604cb9a68db29bd9cd5ff40f12f3d5b1078ad1d21915e49327230d7010001	\\xa52e2dc80432784e3f7b20d2128673db856234e2cd76e3391107805cc9988332ada0d64a86d59f4af010ad7785458ea0e0eb1959eaacdae734922454166ac202	1662638258000000	1663243058000000	1726315058000000	1820923058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
248	\\x555e7e559e0183ad133d736ca073df4870f8bcd49257c5800abef1ea925e9f5c6ede201e16e968072c80f1f04eef9b224ac43131831d0d82bfb7c0e506b9fb63	1	0	\\x000000010000000000800003a35b364cb126043cc43ced525eee3b74c5c3bce850eae55716b373e156227b54e88882882c7dd018ca6ea23b6dc7b0bef346807da16012cfc2e5b225cec5f9400d7c7aaaf5bab5a02224b7a3701edb5d09967a31c17b07e0a94837243d43c677826793e4320ab3e94848f2849e4d6e473b4c60072290978a4aca023d80cc5503010001	\\xfb45dbea74c3dba37313e2b7dd1c6f6a2a9f88a8a9d75d5c050ae4010280e03c3310386359f0329f0db62ca6729231a4213a528d4327ea16f0c2dc1c35dd1c09	1671101258000000	1671706058000000	1734778058000000	1829386058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
249	\\x56fa4dba9241c4231e6bc9a4e3053503ec7c5c0698f52e4ec9ad7b6a09a3f8a74c6f8f833cf6c67a4872b0f74546f48e5f29da89f371edf805f456549deeb07e	1	0	\\x000000010000000000800003adee1a0c56110e487cf9cebec4407d5220fd842b4627479d06f5cb3d7b62a8ccb13678f34c1f074b47bdc0c87f12c088b387689c7980c6832a8b64441e6fdeb70411461244e218c0365a5456895e4fde5e558accdb8bd2558b0509b70cb593f2c57a23c31996b84b409b088a998850eb9fd0482394954f3b15fdbce55fb4957f010001	\\x85fd50644c315489799f418300fe1100a0b3f0a54d638faf9fbf9bf891a7b828945742c86fa03cdcc0f2796e849bd15d55f6743b6d8bf467bb068cc654618709	1673519258000000	1674124058000000	1737196058000000	1831804058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x5976dd0d3a3935a83358e41969c0a211d327c0b54689ae46ecf7e550b230f5331e9c74061bac2d03abcb07dbc12c9a52f58755704cc8ebce83a82219bc769f48	1	0	\\x000000010000000000800003af49722bff36c71a5198b0fa2ddbea96c75d006a621dba38ed3f95a3b73dee555911e2575bde67e45ad8127b4f506aff29ee70bda9697e54aaa023d9768d7f1ee433a16ce33c0079eea7b7fc776389420b99d9c3a1f2ae0518734d81494e2dc00c3025d444845d49cdfd6e91d78be148bcf8f9b57ea94d69e598281fd174f3a9010001	\\x29f87fbc15151df4080c80b19769d19931988279089343687b63ce01347f9ca18d25fc54fa0799a122d16c51486b56063e757ea8109fa812405bac659ab1cc00	1662638258000000	1663243058000000	1726315058000000	1820923058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x59ce6d03b43975ad45a70c20e792ffbba4d3417fbe6b89f771cd801224ec709c46dd7607924e3f8e55d269390d79f647c634e53e9ba4bcf7c5d19c18b3487485	1	0	\\x000000010000000000800003d40da96aafe99b87411c5a98aebf63e9d4872d97c291d3674c97e6d0082c7df23cf39b13bb58bb45ea08470e1c2fb731b77c496ad53c2416c7cbdf548a8bf7fea0352dae11712daa77ed20642dde0259ba5ec1ad42d79ea5d9b7609669401ae1bfc4b070443735280efa232131e68f07df717f14738bfdd99564f4e5203cdea9010001	\\x1a9eb62fef1563bd4d755181aa71ea957d3630679d03e44bb85e168257df6e512fb2eb7859c9c971bf698f71dd13de2d23d75026dfbaa25a749506602221500e	1671705758000000	1672310558000000	1735382558000000	1829990558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x59aa4db73eb5b7bfb3b1582584e56b2b4087eaaabbe499fab9c3a99b3489664f9cf7774f453a2d29e57b5daa924a60d32fcc20ec51f8756b2ba62c07cd4ebd91	1	0	\\x000000010000000000800003d1850a827d0c0af35f2232985ce604538eb7655af4499668d78d12ecd81ce13dc1de1a29d2d0ac923370fc4d3e753f2b62b98d8e52d17f3091088f601980f1b973b255ca589da2b7503d828e7b93ad75c48dc3984e9c06e3c29ab897ea0b1f4815cd48e100f2150659ad5dd3537d7671229debec5d5e536c21f916ff63b365ab010001	\\xec6be07fc35f66337bdbe31253be1470b6c4e7aded4c37da1eb40e4ef89f130cb1059c57d0eebea60fc19a970610150775fee0f63d93c54a068216f5b46d4b09	1666265258000000	1666870058000000	1729942058000000	1824550058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x5fee9cf0123e7d31f90dc1a24ee787f24ece7b5c2923715c6c7612da5a90b98f0b6c90fb3fd14eb0806b16d31fc2c81a1590e9c0f6844f7659f39f5a3b55a4fd	1	0	\\x000000010000000000800003c086d86bb5cff0e2e7d52cf28c3595cbf8019879f5794eeb1105566287f9e6059def7b1a9ca812a20933474c18e5786cfdcbef1ccad97eaf74acc2e342d6a16ee75ac79fb767ca614100be03578710391a50da2f250e9bf3dc395ba2a207c106df815c9b7d2921cbdab125f2340a4dd3667e8700268a9f271b605fa22ee9e237010001	\\x193b9f013954fe426106540d54b6fe348766b54acb237f68a8e6934a3f246b8c2298e912d5d3c1a8a0740245ce6abe29ef1b6cecdc78f442c7d9447136407706	1668078758000000	1668683558000000	1731755558000000	1826363558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
254	\\x5f6a1dae616fe8afe642f4cecc8a644eabc14633226bee34ed019dd973cb88703edcb685ed9fbb4b70f705adab7f5c933899124eecfe06bbd9816c960f9b41b0	1	0	\\x000000010000000000800003ae74d2da47909ec5b412fac0c2b02c107584a9923a91e4d3f42f95d37ab5f1af1f00f3b77e3cd86a1b0c4936a48778b584e6267ee72216dc820a84a40e07a7d05aba0a8febfaa574b1aebd9d679e6fcd3ab0aa2cc7a69a6f3f21a24bc156f8472b4960fb0927473fca5544fac8782a2e2a385b33b4e3028a728a30ea2969d9bb010001	\\xeafd236d16a08f95db09783f726217d2a393e4e0c392d70c7dab36c1d94609f25e966dd3b7837644e8001a9ffe913715ae59f7d90eb92eb1d5605f896c9a910f	1660220258000000	1660825058000000	1723897058000000	1818505058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\x602e018df3a6f6af8cff52f669f8531b39692ae6fc2bbe372b2e63620660abf015371031e5aa5ac80bd198cd43fccc85dfe8eb5a7917ba482e224c95d57b08df	1	0	\\x000000010000000000800003d485be5d1341ff888fac901fe6a52e6ea88814a0e59ff1599394468f4cfa7ac7fed72614ba836cce33f4ee59ed2b614a9c8eb348e3aa494bb89dd46b435783836d8573b34ed3ebd517b343cd91e97e07c3b2e9e568fad867ffeed139ebf5bd7dad5e99c2df31063fad05a60e22573ec1065a85d7df57d5a7848bbe674033cb15010001	\\x15c8ace34142b0695fb49a24b40fe726692b1a77b90d5bae57aa664a84c68569e8898a572503bdf32018cfbd4bbe74349e8799867bc9ea205b8729a9cd9b340f	1665660758000000	1666265558000000	1729337558000000	1823945558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
256	\\x61c67cee19e2f0f8846af124e1b617ff6d0eae6e7ec4fc121b1de32ed87e2a75438e025b8f019e6161f413eb2fc7cc7f13279925aa8bb2480b3d3b67e6fa8cf2	1	0	\\x000000010000000000800003a99cbbcaa05f21a7e3bd7e845d8d62e607f65f8c4b6c95c00c33a0f24a7e2126433381ce66cc803f8d375047d0c7094ad4487e0159fcc08421a10d54872e6e43d8fb70d9259442aac15ca92c79784e74e1cf35def2055e97568e41a004b85c1b8e733fceb9d0c45ea168826d41c91f254c523e959edf2e71fa481ecc6adf111d010001	\\xd30ed330723d6c1d8c741113f570cb25a99f1b6f1a0aed500bd454e69d4f22b36b434baf1851a177f9db22d9304e5fad204ff5eb30aa948d8de80d6f8d417103	1676541758000000	1677146558000000	1740218558000000	1834826558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x6c5a5589d0ac5191dc32caed3ae5df1ad6af6445cec238cfe5e96f0026c0fc36f8cbc6af9c9f02c98f7baa0d1114e61b9b313f12498d8b1dd968742c3a72c865	1	0	\\x000000010000000000800003b9f4d14ca08679ae7d0d7ac45b401c9990010f0bbd03d9f77fa137f832d86ffeae2e8eeb258e1b291d7bee2b9b9f5554bf298b59d2cb077c37c1e8bd15ccff778cdd11b7dd7e92a9b355c732f5511f6c6e8a5206d55fa40b4e57d8b95e934cb78caed18d4e3e1a886fa59a502a4282b5f8d3c25ed2cae5ae63599b18c43db86b010001	\\x2c46a7bd1998470ece165964b60afa8c3201603b61ddaad5c1e5151b3d34b52dc1a1ecb1f686f5067194e3c8fd346671ced823f342f50b10c899345a80edf105	1670496758000000	1671101558000000	1734173558000000	1828781558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
258	\\x6f4a1d891fe0c1f44ca6e14bc0a82a0b37bbcc5cce6ff19d39e7ab57a4216e974a1f2cab0ac374f5b39f53ac8efd52531f6604f405884cdf0a2e037b00ede9db	1	0	\\x000000010000000000800003efa736905680eedecc259f3c257e3a5c04faa2b2526b4db892c683290ca810212f89fa4856214f5c63324def70d203b0c1860a6c00a658d7de87976ab7aed0a9be6107794a29e8bd61f0c13d571e95936a365a74e0791188f306266c4fb47df3c1bc16eaa300e85045e511a158ea5e5d37a4e2c3c67a27907602215e0da02d3b010001	\\x4e0efe131a1a9f407d60c9aa7f4ffec2d8a276ae489da5a64de01408d381cb6338aa067d02a4454cee756eb4c2dcf9cf123090f35ecd1bfdbfb1d40d12726c0e	1652361758000000	1652966558000000	1716038558000000	1810646558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
259	\\x7122135e4eeaabd074d6c0b055f1ba157a9d38208c90ed26cc8cc4a98da5d34a0d31a110bba2e9ca67b53a498e6779b1f9cafc49637ab087d14900ac9d8a07aa	1	0	\\x000000010000000000800003bd0f699d952b7c3c59bbb83d6ccd41f2693d83b1188b89b2d240f679eb7fecb89fa22a25177a73fc47557f6c93a16e3a4b3d5f9fa87c8483c3b8d957fa0b5e2e30fd86a79c99802c842d32bb8ada38d272ec11ac08df3ca08148f7c1b9190bf03fff08db72a078422ca05ae92c10e4b2d099d61f9cce2bd070bd557c57e82cf5010001	\\x63c3ba46451a39d26180f8a4d2d7d3387c8a4e3e97b2b67e7488fcbe40afab4b051cc236f52145052c7cd845233d112fcfa1db3d51518c65e75e1374e4a42509	1649943758000000	1650548558000000	1713620558000000	1808228558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
260	\\x79cecf5f6c212b353de3a13d0750029c0af678f70da4dfa0a6913dfdb04f9527de0e83ac956712d52deb4cabf595d800660c72f6e9dbb1d746064bbd71c236d1	1	0	\\x0000000100000000008000039d22030634b8c8d34e401771bbc33141ec333cca19e7697a44fc24b5f13594d44d3d46ef18f54ab414114b40a5bb541807e25b84a65cd59129af98442c23d6f60366078e369c32a884ee0e2c530d17ebaeea5a6d06ebfb666221e3581853dc9c366ed0b9277ef962c8d21b0cc86fb25c54981d352319155295c2d19e98967e8b010001	\\xb6d00607568357046f03e6287d590d880a4ba6803924d0faf9e5a8d15f7637b424022d54836c93f71483ebef07b5cf87085a14e7876ba2df985579046c20f105	1674123758000000	1674728558000000	1737800558000000	1832408558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x7aae6a5ef42568ba27d7792a0e695f6e0e32308de9369281172cbb236f39826343f4e8399bae7d7ccb9d11fa3cfcff22c917a7c057d2b9057e2d1b9b7788c5c2	1	0	\\x000000010000000000800003cb34b4218e9a14bbccffb615c98621bfaca397c2ab09f7417408323b6cff031fced136b77ae09f374e169ca33df3f9fc485b14a8c0133ca61769290b2b5de006055eef09b8720217de8f6e482dbfc85e3c21de9236a6b49a721101752d99d568fe662ce7f1c7eaf197b78dbbc963cf4c20f4c566313e27482589d572a3e809c1010001	\\xf23c4948cad2f53aa333e3ff0bfaed89e8c1d8817b67ac0759102e14c2ffd7bbef7a534d0ca7ccaa4b7bafa2a54933272cecb3ecc164c138010227c8f9486f09	1674728258000000	1675333058000000	1738405058000000	1833013058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
262	\\x7c5269e8f133c3e0f3f290b5266db8e42e1d28b8fa960846cee6c345dcb43e30cb7aba92b5cc201ba46894fc2ba6e23f31020a759ffe2d0cebeb9ead390f91bc	1	0	\\x000000010000000000800003b1c4bdefbe998ba22be76424cd71cedd7188ec4d2e3830ae49568cffe0419385443793df94c2521a5d6ab2910a26562479a82371c0dba30893b530a6c487a862f017342711608da230f8b97b8ab04630055b937d865411f3379f6ef17dce3955d4251ef5c23cc6713c849f36c80c7d2f067ec3d31f47d39a5849df82e7649039010001	\\x5e081db204cf3af9968b0294e6af69f812de365a23d8a6504ad5a68b779edd60efabaa0e06ecfb6fd54a8ba7923dc61a0d1a14e5713b0d1124c7ae0e90abaf0e	1666869758000000	1667474558000000	1730546558000000	1825154558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
263	\\x7c1e3afee4b67d352c5d681fb6bd03182276b2091fa0d09461b88779e57010d10578eadb00bb7f417406cd9eb2a09d6328f98d286247186563d510bc99320aeb	1	0	\\x000000010000000000800003de892ef5d34943540f8817df35d97487752f7a73eaac53cec0cc692beb0fe8d42f082ff1b9e5d322de21b8d0e5e650d2ad05514f2bed2ac0196f402801e09119d5d68998b30944e72ffbf07a8e8f29f21a6592f39a2c817239fa8841f3a70abbd1d0b76f6a1cc19adaf901178e82502ecf0aa6d7d1aa90431d820f5040b4b23b010001	\\x6a5fb2a88402e2b8d3f7a8dd44363c928edd3e4fe9d2ca74cb395fa7ca749cc21129e0931bfd3c86c24e5c2b1dc908560a80c33dbc8120c1b04e1014c9d24f07	1666869758000000	1667474558000000	1730546558000000	1825154558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
264	\\x7d2e38107c161231601014af90bade6c3bdeeea4b84ef24700e2c21a54ad95eb80d2cdf809d78af37179d32d1bade47cb5aa6efbcb84196de0a083b84e52f324	1	0	\\x000000010000000000800003a965e14413a6853ea5e0f4d7d1906d8c40a74b1ed6cb64ca9197f947d608ee7260adf210c862b2da8685682fb0ea0a140d5960e6af3c3c57d9b3a8eda78f95a8b9a0299ba37781e6ff11cf3743b1b3454cb89ea65fbba86f4280bb2698e0756be6600d78619ffa10848956426133de26b3c090a634a9489817d36f2fec0e5cdd010001	\\x32d9e0b70d9f7c3946e10cdf29eedfa40bd7bf5cb6a4e11fbee1bb75bad8486420a8491f6d377c8baa63f0ce3643b147b92b206992b87bffcd3e96e0217fac0e	1670496758000000	1671101558000000	1734173558000000	1828781558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
265	\\x8192877f2178e8933c78d7999f04a3b3280be38fda99a2c6f98d8a9d373e1d6ac61f5865b550784642f57d6cd7e503e8e45d70c7fa245ff82a6840607180629a	1	0	\\x000000010000000000800003f20fa1c406bcbbc556d16851508008d07aff65df1e90d8f9503a01556b96f06260a9631419a80ff65662bec771e4c582abb62174aea8146f31e80fc14cbeaca6accc5c162bb9f3c71a619648a49336ee12d1850ccd7b8beeddf7d4223218226492faa708c2620afec2f82aa4b943a7f145ddfd8e073de2d180055eb7682bbd55010001	\\xb63051beb6e256a0cc7f5057b631884e063facb3cf51e07c5901c84c7939f81ea11f2ce3cfabac085fedb6baf99a2102502f7f5f68cb9fc1d6a86d1f91fd7b09	1650548258000000	1651153058000000	1714225058000000	1808833058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
266	\\x85fec408179471627c6d48b4ac734210af6375627054108b3b758e1e7de144e16df6759444e27787bf6e0d7b9bb26f56f9ae0b2d9732d2ebe569c5acbeb3dc8a	1	0	\\x000000010000000000800003f312f84d1225edadc64f4bea531605ecb106fcc357132c10a1cd91f804ef13b852ea7f0da8a510f041d86dcc57647ad87867ca8ec540ea0af972908c7cd4e7a65434d5e2cef9f250594171d98a6eb53070051da88fba93e6976ca5671653cac7cc199e61289c22fc2687f10dca7f22a5bc8fa346532550b82976d4f3475e9db7010001	\\xf6273d33f1dee7d5bdc68f187a652d8e1df296d49b541851152d360b49407d4802d688a6661face45f298854a77ed8357dcb7aba1ed513c4400cdf26996c610e	1669287758000000	1669892558000000	1732964558000000	1827572558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
267	\\x887a417c19e0765efc04ab720721e90aff11495056aed576edb5534e3d0adbf718e6bb7244ee834caf740fb380c0ffd15c2bb091d7e78667fbc8fe356cac985e	1	0	\\x000000010000000000800003c959b54aeea92fbe72392ddb00da68241dd28daf0988c9245abb894e1a384b78ec5cfea2227c9662276b85a7576b28db5d52295736e47c2f20084f960c1fb02126af79b52479d76071e3ba45d32c07e81fd8d4582e0416a25883bc06c56d89d2aecb88fda98c6a8c7fae4fd16f3d683bb05b7399f2ae2dc40dd93a2fded56c5f010001	\\xeb84f0cca4dd3d54c897ab923ce3e5fc7a7cdbbd889204b8efe8eef87b88030c587c50e4c939d07d577af4d55295d1f78b0a6c9e6765abdc5aa5574ed2192901	1648130258000000	1648735058000000	1711807058000000	1806415058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
268	\\x8a1a34b19e21d8a2c1279cc044cabee7c4fcb521a11ad058054f71d1ea2b22230d170898fd3b5f6b4927f90278145ca40cb397b490e5bfe40100e7d9ce114fdf	1	0	\\x000000010000000000800003dc1d0a70a0253ab7f40b8e8c7843555ba3e2f5303e3ec4f376c07061068d8bb82b88e03006272ba7fa5cbad31148717de46807782d1b073fe0f5d0a6f8dd4d14d36d3353b373c3a99d9d4bc9a2ff4332854465d4aa21ffa41833e07ebac1569591ab481a337640d26bb9bd504c7a196444b2e69d6ccb811b24528f458ec9b7c3010001	\\x3ac4f9a491539d6147d5cdd5a8678a482d59f3c6d7f215425df7b5fa3b241262265c9f6306d48d6be1bd82cb19541a31e78368a8352c36dcb565441ea8140306	1659011258000000	1659616058000000	1722688058000000	1817296058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
269	\\x8bfe2f3f90ae587d709bc3fc41cc8293323435acc29f187c89c01a4876c8b9630bad7f9033ee1de490584820a6d9cd63abbb5ef0fa36eda0bfa1807baf8d11ec	1	0	\\x000000010000000000800003a7a58c8a22b2ac66f3490ae6a620464ee0b3ceef6aa249353b0e49a60791d6a83089cd8f54ee0d219703a84ddc1d85d73e6a1aa6539d38df05fcdce2790a71b8a67959e82f51215894a08bacb39feaf5801df121b89a8eb1a2dc1d8e909b3c59bb7b61f282347009bdaffc1db82f1487cb26f45fcfff5c7114ed4553a71b86cd010001	\\xd7ee05ca4a0746dd79019e57eca49ef0a8c67b84bc1f51ca763551d1f8dc6165daa254f706d622318cbd26fcd6f6b3f0b710c7a0c68a3627595815712ea94f08	1676541758000000	1677146558000000	1740218558000000	1834826558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
270	\\x8b16a8eb2da090a5377abbcece6985dc717cb8d427c32819f83a5b851383ee4bbe2193fdfd547cdbedf0741f79bb0afff07f315c19b4cf10e7e4c38825b96eb5	1	0	\\x000000010000000000800003d83ae1820cfc513509098dd6fdb299f1ebdb96218888574e78aabbafb7ee23114921db0858596e7a69c38225c19fc4781ea77925087e9677c86e094d3502963ad70948382c8efb2950a0abd7a56c6ef7a1342814909a76caf0ef8831e005fb29fab11c3edc556197e67e8e9de8a5a9667c05c9ac1a0daaf9f34f9266eace2347010001	\\x8f0f8f05b786aa12c6e1ca6e6d1bce7989e789791f678f6d8f0f775c8452ecf6f6080ec358f943c2f462cdc5d639c4b5004f88b8f5ba14c7dcc2b55683fbbe02	1648734758000000	1649339558000000	1712411558000000	1807019558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x8cfab9e0cdd1f344ec368c475e4c5f0d5fe22486eb47a9be9c88894ee345d7761cc7b7dac833828d0a9ee75f65b4cee09878e75b111afd1fb79fa37df05b2baf	1	0	\\x000000010000000000800003b85aaa7d1e1ed7fb25eb4c313d3b68c0cf99ffdb734edd9ac071d82b88bb70bad5029b4eb2e3cdf576d6508270095ba1b266e4745a5d81d9ed19e39498fbf76712b57197f49ec53bfe13eee77743c6e2afd3713881da5c163af3a9f19c37bc4fc0d7c42b6aae115fb024fec755431a93da0dadbdb87c42c822953ce5411acec1010001	\\xb92916042d71a554914b0d7f52101b3ce4ff91fd901c9fb43903470359d463efbbdbfca7b89b00ed32564e44476bc357f8131b548f3cd09e4142e4789175480a	1665660758000000	1666265558000000	1729337558000000	1823945558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\x8dde937c478c41635b4104eb9177c34504d14709a79ab66406e36e11dd3793c2d739c937672f71f36de770871959f8111fdbcd4fca8159f79125b03d3c0fee42	1	0	\\x000000010000000000800003d692af131152d2ead591361e0b6555b8a71f4b8d36b302a6fb83652951bc2f9d80a482059ea276847a672e7531bee22ebd45ef8f982807d9f74cfef536e11888f5b735482fbf5441714e23779568f3a21a709109b8d51530ebdf4a39ae55639f4a016e71a811e0ca84c46e8e5b084a91a6dd0a636d969f0913c3bf82f2086d1b010001	\\x341fbd8579cf2a49d223b1090bc51143ecebc9612fbed9b6015e644b7a2858bf352d1657611594f21cd3d07aa0e7765a1ca0c00d4aaa877aefd573b5d26fea01	1665056258000000	1665661058000000	1728733058000000	1823341058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x8e024d2f1402e4a031610d7af7cffc5f146c366b92f01223bbb90a056fc2065125be85fb120ac543a6a22d89217831f38e0a7cd76dc410adfe8b9a87dbf76534	1	0	\\x000000010000000000800003b0bafac001309a4e0252591b78c13576b39e772a515ee5bb7fa31fe477334fd0cbdbdf0926dd1aceaff4da9a4f7b7ee774c2623ab7ff62853484382aacaeed417a418971e179818d70e85a1e5aa8a4f6d261202fd39474b9341436ecb0e773a9a0e28c901463aab4ab7aad6fb67ad18b880ae71f037be34f68779d90002d2023010001	\\x8d089c69f7e1676e43c254adff2ec323b0d529f60ff92fdddd2f1b78e1d509d3d00e090ed29158e99811faa3422268272df7cbccc81e5d0a890a759a8dd6d20c	1671101258000000	1671706058000000	1734778058000000	1829386058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
274	\\x8f8efa2c3d871be1ceeb1bda74a4441afee0798dfd1da35674b8ed53a81bc3dff784fa7dd1fe1a8c5dbd8370e971ae45b00133e93fdb4ad4a6e7cbe888b7e062	1	0	\\x000000010000000000800003d49b44553df5a9ef984b45bf0a0e0c267d6529dfa30ffd1ddce93fa2aa2242695a8f7c46939eec3b5411ed1b0d974822be73573fbde7567b2dd50ed67fa49184cea4f107f028f761e36e4e5ac6ed578af1bf63f534c1019f52e993baab2167b53594e919eb06e522374e654feb030a5e2905d17fddd99bcbe1de6c2e8945023b010001	\\x5c50cb13f140b8eab8582cbddc46e2725bc7efc799f1f431c11443b2c82e553c209082fa7f76bd11eb1d3339e0b946d44e20b933a6a9b7957ab606c70c97f203	1663847258000000	1664452058000000	1727524058000000	1822132058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\x8f32891b96b3b1ff08223f35c505b15eefb5b59a4ed347e5e01b4cff9088df05ab8489704797da941f3687d92d28ed147f5c62e59b43f9d58ff5917fa467c265	1	0	\\x000000010000000000800003decf8ecba4684c8b0d935eed86980ab3fe0a240c149fe5a59b769ded1a47f47e7d06a792623a2df4ce4f0fce7c49b0c0750bf2882c53765cafde36987466829f75bb7c6cf5ca0643929ac5f0757cd568f6cf69267bc094287bf05d325fa89d3d542cfe6c51f870d6911996701fc9798b337b0e5fe0dc69f328f9ca03af9d11f3010001	\\x55551dbc5108c2d03cb9b95842e8e63d88d0aa5f0c35f72b799371aef502399c48c33f8b7fb1f47b4cc799f2b1a5a407fada5b09bb4e331ec76e2d197cb4040d	1672310258000000	1672915058000000	1735987058000000	1830595058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\x90deb076ed6d3b0a6b2272a2332a6b2f72d16ff4ae324776bc9de0e9e8272b95a42d924b62a322f658bc28bddda323fe71ca83606d03a3b3dd0ed4ec8b4fc59c	1	0	\\x000000010000000000800003a46c454c496f65f49806a4613a91f4e8dde4d477b8d581cbe591b856488d7ab3a008b42cae1e5007f83941a529142c121b0185d5cecdd536b21b954787024868e8c8513801dc80ad4280284c48b714532196355bf488f5706c1db09c44c9f8715e396207004ead2f65e725a33f6474ba37d88a01703fee9069603ae6e514a7af010001	\\xc998c288653368c7fffc5080733cd30c9af6ea579726023133bbf46b9e8692a5e38abc271ecf9d1e571455859514f0140eed12585152a4b2f4a73400945cf809	1659011258000000	1659616058000000	1722688058000000	1817296058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
277	\\x93a695c0ecccb197b4bc65f43971a5f77c02ca17a8ce30bb6cf6e337b0d1945a71dbc547cf6c4c678c7c268afaae7259abb433bf187e8a3bb3b788ee86592dcf	1	0	\\x000000010000000000800003bbe2eb7b3376277fc773aefc662a769390b926c51715bbb9b19aa03263a13dad270c6208385bd525930509dc60c942fe05b236236aae38ee9d7b6cd4d7161748017e421d9e9c6d06282a83da611256ebdef0a32b80c5b9c10c88ab57b481db1c716d25bf3bff058dbfa056631861d29d02a86c9df2c64d864d94f3c2d14ab35d010001	\\xbc0a4e1be8534fd7a6a1f42a7824120d3dc20a3576a03dcb677fbb097d76e1e25c5e0a9f1eb4c8f7c8d488184e01708caf3d30c56bf7bb799b4238c697f05308	1653570758000000	1654175558000000	1717247558000000	1811855558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
278	\\x947eb20c86e6152201f649f8ae6e601d353eae82150040787248106daeab273c6225bf7353f34d3363d59b1a658fdbb6beadde0001643c5ed38bc84066c4a3ef	1	0	\\x000000010000000000800003cf4cb36da37d9d08ca18e62347158752489f3d24df1e04748eaab38c646ae0f7b7df4f36341f7c2470d01091a87732d14fd0353e854289a4374169a6dd5c88d062ac0df0c09d26373c5fa1c39dbd0478598f7d68741f76d672dec872ad31b17f950449e3f14e35985584234412e01dbc39e504cdbd078e8c63c25c0a4456ddbf010001	\\x43147fde9296a639a43e800d6d81dece9a9839251244a5e3ba6b72c471e7753b7dd9a51101ff89e8b833709f17d797dd70284c720ba6c68a39c3331923f3780b	1661429258000000	1662034058000000	1725106058000000	1819714058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
279	\\x95ae27cbf9ab0a2931290aad002704658f7f12658e82380b6594810aff8bf2b75e5c254b771ae3f8f86348e480f448cff677a263f93f18cfaba84e1d1ee64b20	1	0	\\x000000010000000000800003a97a45bae999237465713a75ad11582b9809156261d84e9de0856dbb8463636cb65efece6e94c02c04a7cdb6d6f462047f9e7f9f54b3c675c914ebffffbe2f33283d8d442750295734f205ccafeec9c925e561697a73e0a1697cf3d8a2589c0c4c81322cec7598a867330ef10273f231fbc9b205031ea76ecafebab2da79781b010001	\\x4dee3e9d279b0b847233bfb47ddc7d020e0884ee803ed4652a4b1d6bb2177572fcbff25cbf7182c214044bb483a86a8f9e6575b09ef1abd54eec9804b1fa0a0d	1663847258000000	1664452058000000	1727524058000000	1822132058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x9892a5f12a0cbfc41e07b00f1383951a5d3506bc43af8fa450136140d219c2d4476f9af3b7421ffc904eecbdbe2a3f61791368bd5d7d7dc341c3f5f1777e4161	1	0	\\x000000010000000000800003b77861c62bf3826fa0425c06b91b73197ad1a91ecf9274ec7bc08d127240d4328361e59991568fdff7778fb33795664c7b6bbf44d0abbfc7f4798607a11403aa6adf8c0deb4632a7b2bde05ab2a6a4b6e598e5544da260a978e5266379259fb9e4bce5bcee2a4ed7d0371e12f07cd150be089e0fe810e221398a8ab51f45e50b010001	\\x2949e08414300e429af6eccd1621b63384a0a171e5ede1933da001eb5c7ebbbbbca3ada17c5358538117ebe66d0bf17334483f279d6c759f4ff618a4d5aab904	1674728258000000	1675333058000000	1738405058000000	1833013058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\x99160febaaac79d2f9f425a18d68537b64eaf759f1a0e7b6d25a89af81bcbc67a76b2cb0f50b7bba7c74d74f28580e7c3e3a57d601d58c26c77c38e79f147225	1	0	\\x000000010000000000800003b67a5bdc0b3fb47197ccdc24bb644b2d64a78a96f59c5df3ac6660386fc9f8066ca99a97f357895cb9c7e5e6ba112e7753ce4a93dde55f6b793da04657cfe20dd56405904a8dcf120fe345921767f2a4e5d9c1130094ffa114656363c9eeaf2811c31e7cce4271a361a94a9b3fb70859a3ccc518a4560b33b2b4d54d37d7dcf9010001	\\x030c364e8e1b6c036eaca55a33de48fafb95d28a38f1f459f2ef9a5c9b3c322b7e10b9e9f7e8d2e2498945b79cb94b696c84281b30dfd52e1c5faec5dcf55506	1669287758000000	1669892558000000	1732964558000000	1827572558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
282	\\x9c52a70869f4882d34c814682362445cbfdb5c75e787c63ef01c859ace1c28eb3508bc7cfc93da10c11467f29b16ede5449a006ab760b1e7ce19280e4d1f7e3a	1	0	\\x000000010000000000800003ef2accdd71ba1a5c36f6d6381a14053530d7e616a2c2c693062ab5a3e8de14c583fafb2c9763ccfc1edad8cac4bf3a4378ec903306b2d3310cee34c742cd543f3cff8b037f622c5288a9b040cdeb338dd77e0588f435d26d24d4eead8fe801b385e037da6dd2eaa91e3f2095e46545eab2f477ef7085cc46b3525d01fb6088bd010001	\\x4febad376e1c68ea77427b7e0f0232a43f878fa9bd1586947578b632246fb90af2785b4cf50735b822641c7266dc37f705c9ab2113f2579e46da200f5171d20d	1662033758000000	1662638558000000	1725710558000000	1820318558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
283	\\xa0aefb842a469c343c3deccc4559bb4c3a1965c7724d3ada0bbfda1b872323e8713dbee9f45291480c872632152d0a15defcec3f16252b77d0c43542798e72d6	1	0	\\x000000010000000000800003b0b2a96a0ebbf7959050ff1d3a314bbf62e4034a806f9a4b8d1e8af8afcb311d1d469a9053cf546750e817121286fdfabe1fe74915cef6c18a9d8ae784d7356950b54d0d4c84c975e6b80ce3844f38459959b0c3879026d0be54f958c74e0e64727416c63ea7789fed74191c8beb7d18947def4e2ad5797c2dddea87eb21cab5010001	\\xeeb20e75f193c120acbd215bdf89ffd784e2affa91c79d772b32d7924f61516f740fafa1119ec72c327831a3a245829a2d4b0e8c3d184befb464a77a9eced701	1672310258000000	1672915058000000	1735987058000000	1830595058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
284	\\xa1ee6bdad32e38faec949f6f4db7a93f13ab51629cb8c209318a861aa2529abfe0365a2d1ddeaffc0c2b01d1f2d1864d3757e50d8adbab0203c01175d9c01f3a	1	0	\\x000000010000000000800003b9f0a4e0a35912a5f21ad06b32420e6f7a64fe100a6b49e854f6d8dd4f7028173de9d7a975baf249745f06fda9364db1916d53265737b94a1213504babb150e34ad575b77a6fbeb88d822b9aa3939e1b5cba853da753f2dde03e6dc8add8b7921abfe0ef50701a3f47adfd21df194a549da37566aa7b4f102176c9eee394aecd010001	\\x8120f30ab806ba9988bd4e3b1700bb60bbcbdc2df21bf703b5673ba918e049aa8700cb6d51d58a32090a9a4ccef4b8d8e4c39766ab8dccff189e6299d33a480e	1676541758000000	1677146558000000	1740218558000000	1834826558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xa3c24498a81f27d8f8ab3117e043ecb2497fca654fb0fc6d8ea173ff17e2c3417fc3337dbea6576afbf7b800ab13bd55e75c348c060c3459cfee0a17c051cca4	1	0	\\x000000010000000000800003c7101878f32d5d43545b1a0db87aa26abc3260ce7857a2d05cc133698b115f498a59286afec250df812977d563405106b0b0c772c6cfe11494bdf1c54f2c68ab4812d675689e9b77745ff3deca979f2b4974afa5dc2ef19f7805474658584789660a6642fc1cfb44e289dcd527aabc5a81b5be019271fff615346fed8467738f010001	\\xff34b4bd6cd9b1481308ecf643169ce728886af46ae0532604fda79cf45f637798bd27900c2299a334e0f6b09cfa72a22f363d6f2252b3b608a36f20c7735209	1672914758000000	1673519558000000	1736591558000000	1831199558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
286	\\xa6a67e0f72ac16101a77521be2fba411fbccbb3b00b9d9ba93989078c896e3ebfa6336f64b82b340318e6037c73e4b5c07c9c1ffb4a5997c61c055513c06e4a3	1	0	\\x000000010000000000800003a97423d70d06738a934e613565f4ccd13d2975643059cf768c86f2f2c36e12e9b4ea7a798eccb6b397cd5c7d25aaa37360613bdb6f4d3de22b9d414f678870b6a8b08a14ccfa5dca4a8850f835df06858f28af8f6041b2679f03f8eaa28bbc078f0dd7f1586129893009fb40e54d06ff6c2d2dd2511e269bbcc771e2d4efeda1010001	\\x49868c5f94053598959138e0e0ab8383684636eea4f1da5309c682b088401b9d9367737806650d00a9130908cb95304c6e4d742ebc07f148e1ea0600455a8107	1665660758000000	1666265558000000	1729337558000000	1823945558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xa81a678962a96b8a2272106ded4bbd29c252fef2866afddb23f6568f132996268c695f56bd13cab95fda84a6f79f0dc1031431e3583ff44e0046afbcd55ff8e8	1	0	\\x000000010000000000800003b9778e1369c8d187091eca281f9318b92dcbe3a4df01489f87c7765c5b05328498b157a67c795e28bf14d86dda678cc6b197a57b155b1056e29b7737fa57f44be6642fefbca8a99671b982f3bcc455fbd3b1e05ae249c8c52da0185248be36a3982588366817d93a4294f106dcf39d5e9d637a4ba235a41761b7331e7508b78b010001	\\x6064ad3a5b3cff3d17cebde6ba7f1d624f889a0e78a85d914bc6c5620b8e5be83fa9606f52c79330b6db675bbce11743d56936adb8980bb6f8a1f348eba0de0a	1660824758000000	1661429558000000	1724501558000000	1819109558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
288	\\xa9eac06a6090ef102fab75ee68740b41fd621d1c8775708a6acfdc8449b87649f66d08dd5a5c25aaa5ccc024f0e877a9a5505f47db7c1a3c0dd2078d2b7e8346	1	0	\\x000000010000000000800003cb6eb90757a83b6c8022fe426b7750d88719a8ad75ed1fa7c5ea0f5b961baf1b441acddd0f4a08cbc5670deaffd82a38978fb8622fb2c7a873e47b933efcaaeb2f243a2556253a28b82eb8c12718d75ba783608dd19583281a3694d7019635236c5ad96597a52f8e0ff8f7a0a7e787c0eb43dededc2637591265385db156e069010001	\\x8e3058f0460fd420abb3f0f9ad5c1a5256f35cee144f6f67564aab389c646ae919b193907009314997bd636b69f1a63ff3e19448bee9bc391916d79612a70501	1663847258000000	1664452058000000	1727524058000000	1822132058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
289	\\xad86e3ef9cec634bdc9b1b296dce38e373a2a06ea28463c35dbbdff503ab1c86215b057d4fa9d22bf1f5a3031d63cbc4138032fa832c989f5594246dfabebdd1	1	0	\\x000000010000000000800003bfbecb955f04ec4599df4d2043459c046311d1f4f751bd58552097faea9e9393caa65d1330e35ec76c595941018c24ab206f7fd53dd2a0a5f4e08b3d6fdb7d1463bdeac6c69c689d414062a815e8bd2b1b3b2b547e7a60ae427636e0ed4a1e965cb41b6420147fdf0e1840e4272cebaffc1a1f6bc6a9fb2d7fd954100c190457010001	\\x88e6d201829ddddbc30f840ee33a2e6daf210d8fc031083556825880f03d13092f0d73cad1c36ff42aa8fa307325296d187d3f1c131ff8accf1c20d9eb822204	1668683258000000	1669288058000000	1732360058000000	1826968058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xae968db339dddc9dd03fe492460017ace7b99519ad7d390c7265600a50823a3484c2806ee08767604fad7f3bd8b1f4b179cbfa61267d1e5a8ad8873175acac8d	1	0	\\x000000010000000000800003d26334c567a4d6cbff5b20f6cb4c38c2a5da4aac41a955e6ee29191fa03a75738ae5acadd629456ee9f257583c4a7e7ad0795fa641fc9f73d6ce375ea2ec2d1c87e59a286d9b167e9daed192c4cfd0d715d4aeb96926ac987d36f088bcfe3d408db29983bdc32193bd1a37d9e9b4810f1a399664af4ade17c32aeba58404b3f1010001	\\xaa01b72ea2886013a42aec08efe39090087e709d34704258fb7b38c8f03e973883cae2d2a6557be466a84f04eb8f8d1762efd2a095edd6573285e135f662a70b	1649339258000000	1649944058000000	1713016058000000	1807624058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xae3ea94bdd45864283d5f4707fc59020f44fae69eed728c1485a2a428a4155f73d048ccd54e267d396a0d2366c9655d38a753cf3659f915803d6fe558ed12115	1	0	\\x000000010000000000800003ca07e78e8b010745ca8eb31e9649e6ca37fa167dff7d0186decadc94d9ccb47c89a1471ef1b2f0eea39603c4fd5e170c4ea7ec5f9cbac0e4a4f7023d09ddfcbc487baf3a79b9be2e3012354e3e8f4a0365fcb2d03c119adfcc311e1b24121d14e980f2cbaf8cd7d634db5e14f5d1e392eb53ba6463c0819ed739d7b44af10091010001	\\x5b1cd759a4e8ab6866ef14011f7c3ba55bb95ad10735c82879e20aadcce9be21099eeea22ae4214807c54b532fda33985845f08d9554c767577cd57a3ae24308	1678959758000000	1679564558000000	1742636558000000	1837244558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xb3822079ec54b892c02c77f28875233aa55d63950910fc53a3802f5f3162b3855d722cb605a3e0cbcca209e5cb589e20c3f10482dae6a598c7d4b2940db85c6f	1	0	\\x000000010000000000800003b773ea1a2a721c5d508758c1f290b85e131bcba0908c9aedc8880d4cbd98272983e34f05c07dc708b5f49a00d930ffd3e1869efdf05f0cf22610373d7e3e85a48f1122c8e5779752dd20cf8815cd8a7120ef9804c7f7eda1dfd0b5536a88f752766c45682c4b4c1768d88254ff35eaf58e3d1efbb01ac423cc7e973337a61f4d010001	\\x3d7c7aa2e50c05b45d0c71355d01557090ab72f626afde5fa78a13eb33091b92688c8a256cf0dbdd1d1c15cab573ee385f09fe3f32f5bfa67a0812aba815a705	1677750758000000	1678355558000000	1741427558000000	1836035558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
293	\\xb44e3c821fdc5e3f29c1c85cec6542b782728719bfebb2624d0d37feece14232fbbc62c1f2ded8e7b8ad02fa7a3e951ae1e10e3896859a8bf11ce2fa2c6684d5	1	0	\\x000000010000000000800003c5e5190c2c88959557b69bc8396d3c51289750ce6faec98bfe8eefb642c40500de2a37fd6cf04a944324e473c96516c6783479aefc8f576ef21c834476583c04ae44b61fbfbf4068d5ceba6ff038afadebfa8da4a2280d439aed6774f27b4ef1a82d6043bf836ddddfa8f563dcb70bec0cd1ac41de5eadbaac6b7475916eaa93010001	\\x3e5bfc694be253102bb42b8776b364d9dd81b1501c0f69066fcc8b0d07a009474301a56548b165923cb82c73af63e2323dc6de739722c877d034c5d6ffb1f507	1674123758000000	1674728558000000	1737800558000000	1832408558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\xb496bba2c4db7b8610c1fb933e0f73e30a623ee740ac3bd783eab27f13ca381dd2e5b7f83503112ec12732f574f8ab80d35e8e1a11d775fcb0ec49f9432087fd	1	0	\\x000000010000000000800003d5c344895896e52446c5660a227615ef7e8d4a4c9592ae0c6b802700297644b128db5809af8417a2e521d951a482e81ea1b7abf44610038045d213d77bf8129f245befeb2e2adf22bdb29fdaa6714647817e3c9b600f48d9ce87484114a7f2a601c3275e27a83e9beb9839e86796cbe76aadbb2ba972c80bfec8f98e34b6681b010001	\\x1ad635ec787f40f0d29cc552c7a262d562d3372298d2da687715bc44ba57d8763fbc64aafb7200a5f3d4470eb5f8eb4e05c2facc1d98996df903f99419111c04	1661429258000000	1662034058000000	1725106058000000	1819714058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
295	\\xb436ddccc594796902ecd2df996ce9fa806a00bab863079c8d3c1fdaeff6034df4860be20115bc71c61292a5492d6eba2cc47e4ddd3f036715b20dc92c21916b	1	0	\\x000000010000000000800003b5f73ea046e6241980501022581b88672867403c94413ea6e0efb87ccc3b99949ea56575319c913a14795c3b6ecb591594202f8f4932b53b71c988396a598c9527d4e16c2b9885896b2082ad094935b31d9179996e208a75d4f3f0b69f618c44228748ca24656dbe8b0afc51153c0610aabafbe62740f46cc002319e73f7dceb010001	\\x36286795672e3974e3c4f9f53fb280369f2112a60951fb403487f59313aae3119e667995868117f841100a285c7b9b8c0e214d053622ad73c7df8e9d1c30a90f	1656593258000000	1657198058000000	1720270058000000	1814878058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
296	\\xb4eae1da3f3e0becde50f76707f2a0c6247ac51ff5a659846e83c77c4e9a0f49e672e475f4fdb10c609eb85980363b291999255757c3c287cd9643e54567e17c	1	0	\\x000000010000000000800003c289e4fffa96e0a1c40209927fe506b99938cd2042a77aaca84b9b2109327b0f596075df6af995d6730a289c9d375f77c658d2be5f945014fa29e8391f8722bdf6f06f9020acd5ee840d8d847467e450bab1571b49b6894bf9c91c67fedede8477ba8d3507f12770329c1f53357a3753cf338d2378b7a35f406eb8dcf1c60453010001	\\xd912b0a6a93980928b12d2cfccb715aae9c23a796d005f7bdea389e17b7ab866107b858ad4b9751a794b051e8aaef5d0eb12ddc8b33d0b85657dd9e59d7ca703	1657197758000000	1657802558000000	1720874558000000	1815482558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
297	\\xb62a68b1f8914f8b39bb251b1f540e4c6615cdbdbafb2f1857d1a7aacd297a860d327de89be2d8159574d35d3bad6bf0654a64ca5fa2946c2ab370231382f305	1	0	\\x000000010000000000800003b01dae88c6cfdfaf818a41371119f7906ee682b7cadf101a55fbca9eab42f86c90b9d2801c71fb1a23c9028c8b78448fc867c4e676a0f4e07284bd949de8fef5ca8802ec3629aa48fef34099b3716ec66409bf4519bffb0da2cc2a9f983ab26bd9cb43211c4e51d3f1bb002b752e9ddcc21a2a656085b60272097b72dd17c4c5010001	\\xf153e6451efaaf881b56e29e5f60a5f94a287eb991633aeb0c69af0172a823dce88c452c741928bcbcf2dda02adeae0da51fdb30bd975b9da38712ea901e720d	1669892258000000	1670497058000000	1733569058000000	1828177058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xb91efdf3ba57188d57a3a2cd0557c0ccc37c06a0732a56ca20d7ebea0c5966d43529b0370bd5b7cc31a25e069caef563899443f0892f46f3d185e53bda13cbd9	1	0	\\x000000010000000000800003b319155c9c3090ba818f330bd6d13b2f8a0a054d53a6ccde0f70a8515376beeead87e4058704155ec622c12a4adc64c08b24793a84924d876fe7bf77298ab31ad58a5c979d10d53b13e68b9e97c0dce7347f8f2d9ec6a9b0cec86b418e17b6a4ce185606663dbfbfa7267d1f6e32eb1e627fd6534e1044ca4be55bb6cb3eff8f010001	\\x5a8f0c0cd4e031fa54be01a7e5ccead59fa62db89db71b5c8c502e175a56187cba47b191feef94d120c62a39e1bea516ed60f1863c8d1e1d4b666269cd4b800c	1651757258000000	1652362058000000	1715434058000000	1810042058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
299	\\xbb9e039f2e08e00a235af25ef011e6d3941217f24c6ebb347ac99d15dbcc503c66a99218cfe8fc169e0f7667905d4260fc11d1094a401feb0bd24b5ebe0cc0b8	1	0	\\x000000010000000000800003c9d15180915b1cb75a3ecd3a9857bcccc8104e787aca2e21c74dea4f5270ca06303d3882bbb0655adbd421e6d565c4c936c156b8394c51a20c729f354b1c61889914a93b23174afbdfa688d2fc92272c8c1d7df728f8e4d26511047503430f75b513d725c52f0cde3de16b29fec180f851a162403edbb53013f0bbc7613dda3d010001	\\xa56ce212a4176c1f39834d8b703b027ee5d2ccf993751f9afd333456efdc534010a2bcc0f6a38653d77716803507f7795c7cfc044d52391a012e1c8f0a88dc0a	1649339258000000	1649944058000000	1713016058000000	1807624058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
300	\\xbbf21a5ea3aeb80871b12001e1f49dd2e3c3bd3f4a7fe80d3752306858cee32a4a90edbfdbc3bec34280c27567361648e1f559f308a252ca6c5294fe6d432bac	1	0	\\x000000010000000000800003c6697dddbf35d74bc187da42140151011fd72770731b485bae8ac44df2bc4d1ba7bf66f164fc6a8068396adf634bc3d9aa3e077c0ab59b3038626eb56847446b80b78a0a4ab0f26934fd39be855a9351b678b7c3ddb656c973d987913f5f56e63baa18b37528ac0021b25f6fa2654eb3bdef27d2e3ba238128fe89c80373dfbf010001	\\x21ac580eed0073823ea4873e07890f1721e37c3c0953eadfad28dd9165806ff7b507bf7610f5143fbcb714481fa64bc8d5d9fe3884d2dcc79de0e37a423c7209	1653570758000000	1654175558000000	1717247558000000	1811855558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
301	\\xbc0a43441f2f2168538f8304e63e8b1719c17d2b3fa58a6418309dee8b66518fb7fac764a0dcefb6cce9e2313c38af360d4b27d8b6402bec12b525f029aef01e	1	0	\\x0000000100000000008000039df9146d6af7f09f34301d9432a7625bebf03d7ec3940434b1e9b80e3e8ae8cd054e803f98b2572e2964d7c8e3d67309dff7d0a41e762db551d2768b3654e0b7c386be753b3c27377f03f539606ce4a2963ba6208316f88a4341914bf756169520f56d11f8f122482e7d9be4861f7fe2a895dfcf06c21016f517e9516bcb2df5010001	\\x36e33d69b89d50587cab4488872c18d6a350341f9bb1d9a11a435c20137db4e60b46f0c449b663924b8f53d76e5c8b121e293542839c1e64e0d36a4e4c6b660c	1675937258000000	1676542058000000	1739614058000000	1834222058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xc30e114c46b665ddb44602538f4756bec1b2f5a05a55ce393d71781c6c1701189626289edf5835ce22a898a9bbb8bfe6a4128836b9bbbb09548763b2329eaea8	1	0	\\x000000010000000000800003ddd5002e5743e77a64e3021c1eb0b04217ddda039371fcb84e910f7e03f1d12bf21955521560ed6cc730dc8a00b3a0350d98497bbad9c5c0eb163e71c1ee32979828d31a9a39ab5099c89548e7016a67dc7bd64099c5162c13cd6f82bbe779f64e018d05c07b1ad46dea71cca62641bf791fbcae56331a154648fffc442d7771010001	\\x315f857eb3d39184140ad4c5894cfdae3f99e52a05c2648f5a02801b782e3f4c5b1c47f5c4c0e6ce55237eee2644b9ae4c03327e8fb5b45218ad7b7c3ce85a0d	1649339258000000	1649944058000000	1713016058000000	1807624058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
303	\\xc4366a6c51707485402f872b3d6977ecec6f3b02e75643def9dda00b27aeb830d3ee068d439cd17f8ae7b03a6ccd277ac9720ed0f971325c0cdb2d06edff2b37	1	0	\\x000000010000000000800003d42c70a4f29ba0c225926fd9d5a127f76206e5fda7d999c7eb5de8d0de91f654c63b55c34c1158f055300dcd11e37c4eca46d87ac2e8fc77ce45c94f388a35a384b63603cd4dfffc61edd1b9859cdd3bbee94f0edb3dc43295c958639def2d5386d4888f647c90151ec82f6838c5c9998d3a14ecfde41c2a7f0309b122fa5e3f010001	\\x718bb755f9f84d877e20194fcd75531e4b126ea3d64ce2fa0491600a7e93d52b32637ad95eb24736e665eef3a0f8d4c773fb4109f180aa8b967340c785157a07	1648734758000000	1649339558000000	1712411558000000	1807019558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
304	\\xcaa21c2d1619c8d7e3efa646c8f263a8c02351176e2167d54d68e56d0b2c99fa7b88e02990e52f3664b39031f8a9365d10b6d71c8bf9b046d564e52cbd920dd2	1	0	\\x000000010000000000800003b33199aee9c7659a8070d5a806c542f0545cc05d36916797084b4f9b2a083645f3bfd68764a2eb59bd21bf7bbf7a1fec62b37c51d1781dc99a05b2567a2ec8615119671747a913226d9ae5af43ca83b627ff47aab4e8059368c30f8ced756df0289749cb57e5ff82ed69b5b36b958b877a54b23ade09acc8cc9855e070eb22d3010001	\\xf8a17073149a9a99d40780f4486dbce2dfaf0e7fa913cf5476978ab61670cee34dab472510bcbbc9c6478b028863e1f5ffe050841d15ddf5cad9820cc1457803	1667474258000000	1668079058000000	1731151058000000	1825759058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
305	\\xd0cef9b033ffc0ce321ad3f9162b37b7355ae24cb28fed52f0649ddb31b1182121768bcfcdfa7a983c015786eaf37e26891ac15d7457fa79d4a9a13cce7004d0	1	0	\\x000000010000000000800003ccc7774a84752107e17c545a868eaf08f5c89fb67f59c3a6e3e8644649d8327f007465f1c591674a8785226e5f9325f6009e3a89fccf7386ba673ba51abc76c03e5d8e9827e76a1f163de711740733a25afdbcc0e69788d852883ec724a836d560e5139c2b589832760028381ac5370d52d47408aead7282caa189d902b97039010001	\\x83e3d0af9257103dbe697e660d18f52126c62f4109d7b659e74a9db4d42be452a8ffd1f3b1bad63009bffb7ab863a87dde4a26d8c9649bec657a8f07c0d9ea0f	1669892258000000	1670497058000000	1733569058000000	1828177058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
306	\\xd516d6a5e52634ba2f30e643ec1bafaab7d27b52bb07ca5ab0a2ac378da9aa928b42f0adf6042097d99ebd75fda2d41100d8bdedf01c2f3e46ead7d11967dd4d	1	0	\\x000000010000000000800003a9c6cd00dde8e6809dbe598fb073f86e479bb10dc553446ee12da1fac9ad16986f9063a6c69c1912bcc840686a42885d2aeed901679f2cf4fc6a7284c921d69e951572718c32f994ce883e71547773b7086b9529d2b01b44d561743049022a715856764d82e05f553d96be9e0c5e3662cfc668f5e475ad210de1e067e80d9269010001	\\x112cbabc56c8bfba822db98e33724b831a374a363b49486b6082fd247919c95ced8fdf3ceccd863272b9d2b03e46d80e4e0f18960677d9c0394c025b13ab9e04	1652361758000000	1652966558000000	1716038558000000	1810646558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
307	\\xd95eb932af875f5f4ba29e0fda21b63e6133aa29a879a06f0091c787b05a9dbc80583a94726ae4281f88145045d2d638ec926c6ce5d485fb2aae0d63c6e396a0	1	0	\\x000000010000000000800003def570fd1ecfe6822ecda0d59160231448968843a9464ccff615aa8d7e241520aa78b5b6b40a13c832da24c42d4dc6480f7240e9ad0752205e8b2d32993f255e87a5f8e3446c9f04343b84806a7c4bcd86f238adf64816b0719c6b6271af2af6f64302959dbfc2d88fb514e73727e51c6e5d046aaee5eeb59ba165f7e5e94f79010001	\\x4dca07835e8ca157a4e09bb54dd819cec91fb4f098e312e316d0ec5846b1f3af1fabe720cd1cd6d7883b443ab1fbed7eb5666ee79d86713ddbf629559d28a80e	1648130258000000	1648735058000000	1711807058000000	1806415058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xdc26b4d6645972cad4b9d095d65c449c814b892a3b5ab50f7aea8bc3a2addf0b957c7fadbeb37f264170c8e187a087e89307f47c7e29375999986c18f2cbf786	1	0	\\x000000010000000000800003bdede5ac3d59b3f74f7808841e54f529686d6dd93a2771f7f8d6df72247ea9e660cab533bf04c098d316c3f074caad0102d77331ffa95345ccada7ad1a8c984183c6269dcbd2e4af4c1613fa3276eba1b7c2c8ce04869bd736c7c454e2aeb838bbddd9fb5915d3f51bb85cc89908f620710aca56880232b136527f73f5c7a32f010001	\\x7e399898d4e0d803321d967b77373c47bf5aa41b5ec8c7ceb3654bfe8ce337b9b97cff625aa89396bbe356fa0a6d056b48c56c9bdbc961091c4901effb18ab0c	1677146258000000	1677751058000000	1740823058000000	1835431058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xdf860d45df882e7c513e56833a7e8366ea366843d2e2a10fe09b66ee05fe0d5d9c77877083610d2cd578e137750816d40a55b22b8b38733a7d0c212a7b735a3f	1	0	\\x00000001000000000080000398ebccbeef5e4dc80eb3555a1b92d28d86803ff12f15984ed0e917ec49d0f6eaec1a8949d34eee13ff79242f5f2e0177f722e2c0092d0906f8214862e6f6cd7a8757bd802e502c1eadecd3a3911c60cd492d84e7a83fa6c637f5d33dc66090b9f479e998c3abecb06038ecd46dfc46b6a7e6e7ed89470c69be892821cf2b44ff010001	\\x2dfa14319fc80de91d51fa68fc6958792fc605cac439492b5ffb91a8921d561ab9a16f0c24b2b4e86a21f5344c2afd848a673114164266537056d3ba0380b709	1653570758000000	1654175558000000	1717247558000000	1811855558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
310	\\xe0daafe7be6ff2f7998a94c53053b269bb4b4da2eaf3d09515bb825215edcaf2b4cb9ff364c5ba28a3b3d7a03ea5d3d039e4f47ba622617e40d9731c92a0d2c7	1	0	\\x000000010000000000800003c23c2a9a4b22e2ddff18144e9dd11a85a7c99f08c5a2c2ba9991e8ad5d5b9e53ea25766c7259595b8242682a85d0052e0557b186cb10494766f1e3a435e704804828fe223bdb16aef43ba69392f5c66eb08654a390c2819f9987300ff189ebd2d5effc762d148908add76e1958decaf0b7cba4eadeac6a23e58029b15131a0dd010001	\\xd01869068d9d59b7a6f8e97084d9e36f9fef04649504cafb5297f19764118da092f65ff529d59a0d65e281290227c9ae49c3552a7e471708c6738cb6623ee601	1673519258000000	1674124058000000	1737196058000000	1831804058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
311	\\xea5a0526db0d0f48c05250e77050a40453e45543f6897f8b3de5574832f2f04e044ba8a67aecb7f8fbb722b8dc95107f041391010e78d83c7b5918e322c99318	1	0	\\x000000010000000000800003ea71916e505dcae1abafb10e9ea87a93b88657514a07420dee407d119b7d26c84e0c792550b4d70eff18c526e71be6d38b448178657138a9807f6229c7c62b9ea2084388329c1598bf8ed57fb149382382321d02168ee247a425493b6c0226f7058b08ee1ca6681fbfebe0e6fa48c6106c02d1ab13beab31856caa00ff5afe61010001	\\x997096530791d22ff051b9849970167ebe8248a2f2671aeb56cd3da48b331d70b46b72abb217b78d122ca30e99099067b0858fdcf1ecbbf9528fec64b0882c00	1651757258000000	1652362058000000	1715434058000000	1810042058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
312	\\xeb122fce4f2106fb3c6c0c74b24f24947cb8e0676e59a74a51d38ff3b8542f0ac5b43489476b6b5cfb0e8433860855ceb882c6ad91bbbfd36df7b8d2d9975665	1	0	\\x000000010000000000800003b2e3766c357b8e0421ccb484675ce148fc7a1c9f854bf5bb6fa83023c70dcb1138bb8bb6b82faedfe4a36b1d0b0ff122aca265555b8b4e4905d6cb397d13ecab61bcda00b1761d29bf7c7fffcc18266e86811ec4c0e93fa267ebb56b85558d96b6ee324651154c91cd850be16022aa3388d1488159a65a91d9826f878393062d010001	\\x3cd56f9354d294e4eea213e6616b91a0d2181edfcac91bf686769a2c6ce3b842c4162d69ae0f6bf6823acfd761937e676e046e5491a4edd6b058d69d6cd47f06	1671101258000000	1671706058000000	1734778058000000	1829386058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
313	\\xecaedffba7e8cd840397e0e7bcaef1daf90b0413f1d54a40fe0551f2000bf2a8886230621a277cecaa6e6f22211da20222936d1d5c2d9aa5b53618ed7e91abc4	1	0	\\x000000010000000000800003a32fd96acfa0d03406e6b04def7898ad7d24ee91a6c681f32188b50d5f0a841b3da652be393b9d0aaa211221938c658899fb15e9fd88383b4b5718a1ea4e8d8db703312011a71966b31e8c48ae195c0b35b20c9bbf0b877e4437536bbbdf0d942c75978277f06825a0740e8b139b5a1d0f7ddd3f7e6259d0707232b23e4191b1010001	\\xec51f0c2d5c448204324704a6f4c933dd64d0d150502b6862218fe8f678501a97d8f92849019b835f0abd5969cd2a52d3175c8ac1f2efa90f867fbd3a8d3b006	1661429258000000	1662034058000000	1725106058000000	1819714058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
314	\\xed8211567cb4fda1e1099b67344be75c50e0906e4bb531317121407140b24c0007b82fa50bbb2560e00dee256b62c146a8501b9a241972a9920ffaf1bb32a2ff	1	0	\\x000000010000000000800003b95d49f7a93262dd07d853aa5a88754a9786d659172630c86de762037fd968e7575fa0ec4f3d4ff51bdedafb4fcdebb1d5c52e2eb97ca02511fb629a00fee2402a1bd1851bc6a2fd5342c9c3d1b6eb901ed71fbdab2edd3946e963ef45d2c598770a0bbdf2d2f0fcfe190df9ccd990a841f04671df55971828a6cc3ddcb4fa31010001	\\xc928e60b61d5973e87093f7b4a198b2aa1d95d95bea957e56ab7a189480b5ee61ea142fa922ae249499c3c7ce90cc08785bb15302b93f03cd1d467769641ed00	1655988758000000	1656593558000000	1719665558000000	1814273558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
315	\\xee2e68c0b13749ceef700390b5796c0e6a0098593fcccb425d32f9a368d4fca0dd7f20672163320a18ae1509494a761b230dc7ee3e313b87c4dd9a74dd7d108a	1	0	\\x000000010000000000800003c43edfa535bec1b7a86bca0867fb8d0e461ff74df0640b05e3b3d0b8d2b23a15f18e1a41569406ccf13adebcc2defdb078337a69a7e99effac83756a13cd28ba9e6e7f2905b8a9a5e1d42ffbc40baad39c7e16ea6253ea51cadd5ff6dd8ebcc00ff045156d23d59f9ba57995584e3c87d49c9920872fc48c0c86db9b77fc1587010001	\\x11fccf17793f9d0cd0aad91224ea74fbeac7222bd021fdd430ddb1b0470dc723bdc22a110e5e9c6d3af7bd404dc98c1f36b38cf8750ba3df317d4aefcaf1e50d	1674123758000000	1674728558000000	1737800558000000	1832408558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
316	\\xf246fc59bf5408c846c3d436bf4e029be5965da1d526c6b0c157734427c9de84177176a10a2ae1d739254b9ac92eec439752dace42198294ca8a9909472b0052	1	0	\\x000000010000000000800003c798aeeb97976ba0ca156f069d3e0fadf67784f4094cc1284b190b35bb2c793c2dd768d39896afa931873571d2184b3c623888485d02def72784b3ca37433701344e838c5d8e62803444e8714d905d0ff227538b1ecbb8a3aad09ff87adb3af8cc38b0cd76711df65b0642a942135933450eb53e783dd4e9cbc71d7dc060cfcf010001	\\xc393ee3473a2db14d34d13e7167de8904dfc0036f2a788a65915aa9a746e8a1d1c2cc1e21ed41b13fc5f3432d22eef7fcca130e588bc9542c10fed702f4ea800	1667474258000000	1668079058000000	1731151058000000	1825759058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
317	\\xf24e6f73cb77fb6869a4557553b3c5542b39498abe079bdbc79c1d93c052968764e92f3328c5e2127509535cc69856f34e4ab3bc0be3aea07705ea9543b55cf8	1	0	\\x000000010000000000800003d4f71925dad26f5d7812e3f9c699ebcbdbe358ee1081e188c0286fc1c51f98cd7b0e4f1003169e6038378a3827469ecea2bab884addc517c8091a59d8c66c17be4dc2abfc2d987929d15fe06648f7a93f487f653f322f354c0683e4fd55414b137ecf3deaadcdc8f97fcaea972f7c83c042a5056ce5144437189c449c3e90209010001	\\xb9ad7dfbbb35aaffebb077db9cf28f27d4255b0ef0f64a1817b7ebe8f52470def1650de45a69f606e25d0d173196c40e3f168d22fec17063bd75c0d0d21b000f	1678355258000000	1678960058000000	1742032058000000	1836640058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xf986e5a22162e0ea5fa1bcae20cc17663dd1cc60fe0bc9875d0288b3dd474fab551e71bc17144a6bc1af9e5316a37b3ee836b7f809112f9818ab9cfac7339ca8	1	0	\\x000000010000000000800003a35a81f268a63407ea0b12e437e8382bc4488c5836db3e2b36ef720485696c1f5a0c0be0e6c26b31256a29b5f822ccbaff264d6f9153cc0d6625aaec5f05bfd44b28c4ed407c3c2b0cf95b3651a672d386edc2a4f56ada2b5c968176ed87dc4e135b29560e03066dd577b84150deefca53a70e8cc1efe82bc8b41cbd36f3a039010001	\\x7bf72799dcd8877fe3aef48c178a479b9d6ce0276b0dc679bad1d5a20a97106e850464e4ac7f3f332ae9b26d17e5eee5daae81163523f89a0c393707656faa04	1676541758000000	1677146558000000	1740218558000000	1834826558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
319	\\xf9760a790805e4643ea270953d2cfafeae72ef44eb3c6b08e6e549007d2e2cb9f4804343ca52a113ade985817a400c016a9dbec4290eef5b7c494ddf4c03cb3b	1	0	\\x000000010000000000800003c90a26ba40c85826fdfda42cee0b09946f214d632d8fda62cb39349fedad5fcbd485ed4fef5e9f64786a69c0a40142ab021598e3dea2c64f0ccd80acf8cbfffa2bfac2a6ebc9efd82358db72f134f86dc8242f4148e807da460e04fafa95b59529d1ef291d808a52e0cafd145daf57a23cb9496999f301ac4eaf97628be04a61010001	\\x18d7db88f00ecd1c15ad79af29e4a65dcbf6f486f232c5c53a0101c0a4f83fb7028181864c85400d00139886c14ea02de1da8d97784b99cbf8c0ef4b9f557b0e	1650548258000000	1651153058000000	1714225058000000	1808833058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
320	\\xf91a39767cfd0b2c10c010a8db63361c33aabd57a6c8e9c39990b0f753380774c79cc95b64cb4159324576983f74c64b34d3eae1de7d54747aece869c6100eb9	1	0	\\x000000010000000000800003da750f7413d6cf7619202b98243ae50d80af93751196bd9f97bce403f2ec4244b8e5c2d227632e6330cf2deee548db4f036c5394a12890c99617ea2d77587dc8987d9cd1ff6844e5aff9b2456763eee55a766d8ba246bdd4ece0f6489adc6423bb86dbc5403d383dd1c6b748999ceb01fe4be9da48f8128361b2d34ba64224db010001	\\x688ce0076447efc54b5fdd3ba84c0da090ef72309f70bd199e8d41d3da8f82af59e87c72b05ee2cbd1e43ec556a1e8b03df9ac1daa7be8f184150ba60e7b0b07	1668683258000000	1669288058000000	1732360058000000	1826968058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
321	\\xfbe2bd0d4567e0b3b2fa57bfbe2f8df7a1d819bd553937d14ab57f920e54d61a26ff8b8d31e4323a25b28422f298f74f49d3bfc1b4c2a2cf54f40439ee39448f	1	0	\\x000000010000000000800003ac478ff2fe276c6dc5c017bbdc5eb058c9f661407a8ecbe63d05d6b72d2bf841bbf9ca93b40de8ec66f7b90e6cac06e2519fb518f0c0d059b8e160c0fb4804ec4f4ecf15ec57df03c820481b3ac4f260b67a3713e0aeef4c8595bdb8854a8f89159e9c32a59563fb871a5409dc4e3d0d4a78b156a57bceb82467b77f4ebcef67010001	\\x62451c0ad9660107fa20468ea0827fcdf1f5fe2deeacf6371c0cb68d462af1aa2eec922a66d3f25d899243621bef2044458bc47bb7d3b4da3d6b8bbffb25cd0a	1672914758000000	1673519558000000	1736591558000000	1831199558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
322	\\x012743307e2168948cecd41c24ac691bc95c239fa377a157ffed889742f6cf2ffe9296fc7bfafd19b99364c105d91c6cce5ce0cdad2c18ddce19170dc960bbe1	1	0	\\x0000000100000000008000039938ac683e95fa113f70915688161737f501b20e4984cd7ea980a9b853d0b5c4c081de056ef61a5713236f0137f8455ded1bafd25ce2420d9171260a692408525409c000d496129875a9a74ba0e1b4f8ab7979da7f3f6437db94a7ff8e590d795e75080caa49e222fbdc22b469ce8f8d7fdc0c463922fd30cfb89621b2ad49d7010001	\\x369ff6065bc41780d85e7b68982e6e4540624fb29ed137b60f8527ac869d87fafd30aa2f00cd9388d1c4acff623187829934b8a3bb199b293e910ac161c34e09	1674123758000000	1674728558000000	1737800558000000	1832408558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
323	\\x03b3ed40783edfc44d8ddfa59ee36b6edd15ebe3d457aa4a541af0c1f683ce5b72acb4dcd648068551550e4e6f1e686e3abf2ffad9120784be8e9ca7ebf880b0	1	0	\\x000000010000000000800003d9cce3ae3e18d489c9999506c381e75ccbf00a10e616be2fab716fca6a51fc8b5b64d6c36135c4e2f04a01e2b0df378a19126b4121f4caaee507b2b6ac8d22f8ba1a0b8f5e3868b112999bf86b394631f8bf57a9be983dade092fdc82be5bcd309deac003e75a090059b298731bc1844ea7b196590d27604bc8febb4ffd1c4db010001	\\xa3bf40f8374d88ef826bdcbd867295cb5b2b97ff85cf9bd8c19e1954a45d947bf6f0138439e3a2a453183614677677c5ed79cdcddce00205dd3823cea0f4ee06	1654779758000000	1655384558000000	1718456558000000	1813064558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x04bb8daa388b2a645e66f22220da53e2948b66681b6bdfc039dd75837961bff0c727791d634647a1b938a10fcdfb593bef8998fee7dd2e15648dc529fd4e3bb6	1	0	\\x000000010000000000800003b5190c343facbb411226b6377d21949f18c6cc43d5a6cc9c76588315b225a379e9c4b37f5d70aaaedc3e5911fa9d85083bdef7a41f30e46c841c95b1c302734d605b023b09e92bc6c4f0f7de4f59c3e8e83592941f964b8142f34288c350d506605245114e17a55888b5c052a831df47df9f4b2a86c30b98e49f2ceb5d276dd9010001	\\xb26b9e8c2a3afc1326fffd5c8d270af9143ce2971964cbc33d7735cc76413730f9feccf7580a15be49e459a7563ea37846eeead5c80eb35122792e95e41b540b	1673519258000000	1674124058000000	1737196058000000	1831804058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
325	\\x05bb3c4c381ec8f0bc6a99aff67e779d1ea427f0c937425abfddde19b41c9902c4938e503713fda5f37286e558be6fff6d140e5eeebfec4c99fd29e28b0d64a3	1	0	\\x000000010000000000800003b4dea1cd22ed0e328504e039f5249b3ba617615f434205d96dc86492204148cfd302fa64e7c00067f304541fa8b7c1c5e4029961cdc03c90d6331dcee5c92b28f1ef6dbdaf44c8b729a9289f8c62b7fcf0f626df5f312a2f33689a31ba6338a87e5dd00f835d4597c5235ecfb53ce834ade9c2eb0af46a9555681abf01f1d691010001	\\x894e83d92bdd5f18eafe50510f82f7f149eec5f1dfdc52d769b23f3818b427fb0bc07d3e235a54c19df871dbd965f7f8dee6819d148e178f40e4b69f8092bf00	1665660758000000	1666265558000000	1729337558000000	1823945558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
326	\\x08e7c1aac801b6c536d117d8128ab0784a088fe73eca923719a147d01ebd4159a88fc2061a108a13adec95a547571b16277267a26aae7e1ed3da1511368585bc	1	0	\\x000000010000000000800003b5a367e33dad26024743d210ad23b0bb0ee979ca88d6ced1cae4e2991623f120502153beacbd2aaf1f71ac68f719f6e6721b8e05c754bb98b0da8c395949b947c54cfac29d885a7c5c60c1427d70ec72f8561d734761250aaa4655ea440c5aaa1a3282837779aa4f9cc5629e789d6c2361281cdab3d0940ea55480d461901a73010001	\\x03b032a561c93c44dfe1883d623a00fdcdac640d924b44a6b025a805d7568c25365d6818cac7c41e7c5d57120488e79cd8c9c0a12acd370b4d3b82937764f40d	1647525758000000	1648130558000000	1711202558000000	1805810558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
327	\\x0cc706c2704c3526e508137935e897b072c19b6f987bfa042ae2c42a43b823957126b764e310682093c508a9fa9d5d349327b9f3ea1a76eea2604e9b8865f6fb	1	0	\\x000000010000000000800003eb77763c787dca1f01d603e19b0d18afa0156737bfd324f81a2be7a9dd9b5bbb9cda159726b9b1c8624c41360f8a34418fe9c824ea791b8cfe77a174d804266d0dd6a1d1b0df221f343af68c0bb8bfaf9df53a768d97ea635c3414b067bdccd52a0ce9a7883381e84bdc73c441175a32e5db56cc5c2c4d713c93f2fb8e5dffe1010001	\\xdb9a94cfa040425f2b27598930632b01555f0be54f51a553a4f5174c9e1f0239ab5f6bdd47981f45514849f6a9077127c81522a6fc910acce3670bdfc8b3b00d	1652361758000000	1652966558000000	1716038558000000	1810646558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x0f37599012e40bae3c7f0ff3ca5c09f23daf3d3293ecffd8fdcad575ea0282cc82ebe3c319939557685c5124ba1973f227b11d45dd16658406fd78e519f5707c	1	0	\\x000000010000000000800003a9ec01011ee2dcd85f74db38b0f804b45d79552b613e7fb6c9959bbdfed94afd7d76581b1adca0dd00657a5a6930160db8e5ba7c74397f6069cafeac20d58cf869e97d30b765f756ff468ba8c4811f04ba87f3e9a0d375e845a90f739c7563655cbb5f8050c992b3113d7da0871b5478a74a36cd7a5fdec32fec935cb11b2c89010001	\\x4ca5d0458f3c9466c9062b0e8e92522ffa0376daf725708f6228b2a5b789d18dc0bf05776b578de7ad0f1a9f502fcf252632c4dd403823538b9c5522f79ac103	1676541758000000	1677146558000000	1740218558000000	1834826558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
329	\\x10cf080ea754338804c3e7db95c6136d53096864b59445fb4f81b0f49991887127eba2b30eb817d0d3d55d0436d2b9892f291fc302a808e98a46c3bd0a076021	1	0	\\x000000010000000000800003a114e52f2260b702d53463eba33d92f55a5ce952a580c606f6108f9e49eac0b7d0abb9a5a2563764995e561ee1a9b3a0372e68bfaad6a2edeb949071b27a7af02644df85f78910771696d35a6eb0270dd0b1bc448464d8e06eda0a8c9e10fe4e139afe4ec001845ee572a1bcf6ba8fff18cb85d4264926fe67f8aa7adaa573e3010001	\\xe20ecc78d4d333ff4141f52c86716f2866bb240db288e87587d77845e505a490a641a396ee1d2761edb819e6561d4738fff0dc55692d7ca8a2e41ad426c8f202	1669287758000000	1669892558000000	1732964558000000	1827572558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x1313a4207ba4e2c92a12068e81144205e0e1346b3f804d0bacd1e2bc9b57e7c95be5a19c41d52e4f24d186c234819601161ea2dc7a1e30e3d37e8067bdb4b856	1	0	\\x000000010000000000800003b98ff293da7c13632857f812d92141bba089d083cee8cafeae67ba57723a8856d840210c629e7e986ac96b2374ed82ddd7dd555c2948010ed89ddf1a537f058a9c8783b7fcd4f3d5098437a3658f39b3fc55f7de93390eb21c405cf2bcdc7912c254917a3f5e3a528d4a38acdc53761f64fee4ebd8c37ea5cbd72ef962524bf5010001	\\x46a24f75aae4371e323fc568ebda5d61525b8e31c230ec39b573e658eb068255c119dcced70a61961310afee512160cc3567cc5d767704c3d44f41c85a23010d	1649943758000000	1650548558000000	1713620558000000	1808228558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
331	\\x14ff26f9c23a09a7189d338aee38c3d3cb0b9428e3cfa124a4cc5b34967aae71c8a1d7857c50cb34bf169b04b223db094e56e352c16b55c58d7b2776c195c866	1	0	\\x000000010000000000800003e769bd1da14fc700336e554483c588f47836dad2690e592810ca37303bd38deb9d7be491f9e37aa8e362a1e115b439f9604c35ec8c7b508c9813be30a040e1ec15fb7e72770ee15f0ff8ffb1de17cf0dce7173f6077b13d3ec81980d408cdc61629812c81e9dc965976c79f7347346d4f5f1359f11832ed30c158a661679a8ad010001	\\xf14353f30aab59913ffc315899dce05087f5af414388d6d84181b1d9a2e2d8c931047e6cedb87a2bd5847c7c6a01deff615d6cfa8f928f93be8e1fcd1e8afb05	1677146258000000	1677751058000000	1740823058000000	1835431058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x1507507caba7fbe2b367328e46eea069cf7683e93978a31254fc214db2c12a033f4ced6a5694cfdfda073d696dd57b9ad4d8448f2000fba6124a39ad3892dc92	1	0	\\x000000010000000000800003b8ec42021aad919d23ce132caf0e2d19714a8b5cbcbed3c1c2ccd88a83c3a677dff4eef31d2ba12b035c9e28d0f832f48c921bf52bcf34b6d691632d76f3b919ccec475b1be7be6573820f8a4e0dd8106fec0763e884089ee2383a92f28a849dc2a6a27666a155c6bb6bc53e1cc02c32214a3e45b84e0f57f9ead14924a58533010001	\\x24349f5b550904f3f7f43b9baded795f197b6f9ac9e12ed29eab2640982c0cb46214fafbbf7c9e022029566cd4682b9f54b5a54322052868b1b2778e49556b0f	1675937258000000	1676542058000000	1739614058000000	1834222058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
333	\\x178386fcb9167d10fcb58c4a4fc95d31af49143ee18f2ccd63f000b1b4fd94e3a86dd96dd98db036b9e9284f27d1e4ac16bca9da1b291ac63298bb2951aea963	1	0	\\x000000010000000000800003baa777da1c9c91ebddd78ec089b99c43cd48fde0d675b869f37e2b7ee248a4883e663bad5f76aa1a19d4a2d8d38517de561d03fd0cd42a5a3e1618add2e02f0dce7833ffe9a0c2b1e71faca94581667dae082365faea55ecb2d43fbdc79829ec3f48e04fe2475471d46e2ff545d94c679605c8d47a1a003d92b5d7d4f187364b010001	\\x26c174c48eccd8e2aac35f1fba2f95328dd8e3398efe05c1afff20a80c3936d7e885847fba75256d1663f4aff9d66daafbbc9a6eadf833b49acfb5ec30f06f0e	1665660758000000	1666265558000000	1729337558000000	1823945558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x19f722cedd56985aa704979ea8e6af3f017399afd79e9d9a0231599f9d852ce30d9dd92536ac27a5f5efd794adad9079e7e51fd00c2da21e44ad55aa18914a82	1	0	\\x000000010000000000800003d05d8aa3ba7183fac1c259d59e7a394cadbb63dcf207e0b0ba41d1d2a6b74f514a97617607eb44632c11dc959db5e5e5364a227e414770b6924c52e991a1742728856fae1498f52c15cb3eea5d6f99e611b311daee12dd39fdf7449554414129366daf737f2be78ab2de0b1cdd8a365b4c5b66266cc3db20cd870496a68c7a87010001	\\x4a34f361865a86c58d80d5096e75b1142a1979d9f80a2162e55443829d9226303b1dbeb6ca9e28855c9f3909cdcec77d033e50025021c90f711ceae0a2b1c205	1648130258000000	1648735058000000	1711807058000000	1806415058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x1b0fcd791be226b046b22b56b731c8ecbc8c13f9cc309564f94542003dbe0943f7946dfadecae218d8b9763fff482811f7f4eb31992be4adda148e774e499ccc	1	0	\\x000000010000000000800003e37b80778370e01e117053d7a4cf39545784b19dd1ea2c14636ebbf31ee9173e80f083b15c88c00be2c10b87f867344bbdb7ce22aefa56b3979f367be7096f217b18b0377590f5355d20e8146b739d53208ba7182b79c8e6a86c7df07dfa4d9cfba7da13e87f637969dffbc65c7ed1f332df6e3e079fc2275235990ef3c72811010001	\\x3ef3b635a187b109f9c7ea85ae78d5032427b949ebc9cc357ceda73ffd0e574544d5dd4de5e25b8883ff4acc298cbc8613b1a2c76ba358c4666b45144b682101	1656593258000000	1657198058000000	1720270058000000	1814878058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x1c0703d9dd712b6ed571c8b9850238d5f5050710049813d40e4364fca22267de7c841796d2aef30e9ba4fe7218679ab06f647581f5e416c1be5cb8b53b1f3277	1	0	\\x000000010000000000800003ddfaa5a6686f47cfbe0dea486b3b4a4a1fa77086f531c5e108e34ac5a02626f09d21dd10b4165366dcb4883183f7cac5e70ad7e1bbcd8648798ee84a7ed734d001d6a95aec48e43c6e7c953b5e78da4b5474136bf897fe01bf75b7e2799c67e29c3f740863a1b4f0c811c482ed8439694c6c1af1dd184cfe7ee9811cec7ffc5d010001	\\xc91b762cb60a73a1a6a3548be20b6bb5ae3f4c5326adf2d17f116754768ae8428bf7ee82a3c3c630b432e39ee6fef78ce98fffd58e05c87ada98c488defca105	1652966258000000	1653571058000000	1716643058000000	1811251058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x2017de09025f42baf7d789b1579e01521179a6043fa6361ead0b63876276f30468608181c79082560c369be3d032c41538cb7b65d29048c4cadc5ec4d5d7fbcc	1	0	\\x000000010000000000800003bc3baf672a9841c4775177a1042953ddc560d3083e8c6f6a0486eebf713f9e1ef69e96212a8addb1b428e117a9eb783352ff8fe6d83474d70990a475c98b9fe616ce7d1a9b630ff1debb7d2dbcc4d9e7df0f9a6fe02cf2d3d17f3021c410f7098a1e0824e125bceb686bbd138e17953d1305d575d75cc50f138bfff2d3de8039010001	\\x530b77da1e980fa911dba42cb6af49f7ec6681bd79ed3efc9df70c724b109556c6dd20cecd79e5ff9744e33c16684276517895b70b96068f4a92f948a9cb1905	1651152758000000	1651757558000000	1714829558000000	1809437558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x202758e7af07da000ce47acbcf9797c4003e006d921e748e1d5caf2361bbce4b77df83ac0420b012e5152db50a4172a3370d1054bfc329c78b5cc48fdea6f74b	1	0	\\x000000010000000000800003badb18cace821716283617be8eb29b43e7789d18e17dc69bfa8f544f93c87d5969cb600acd97b0b02999a354cfe669bb33310a7c407aaec59b57523945cb2cf2f39b9443bdf848cdf10b0fceb08ab2491f81188e4ff0389d3bc0044d12808ccbfe80f105b9823642af95cfd05d1561985b347577a3059a534e099f21553830a3010001	\\xce412484195ffbbfea4225d66772f17ed901300566e6f6a8fb9f92a8f5dbc351cbc08333c06ee0310c01a89fabba7b9bad590fb7654284a76ab04eb1e8814a05	1665056258000000	1665661058000000	1728733058000000	1823341058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
339	\\x22b75c06ebf720679df2dcb666d1ecd02a8c123d97df7775e26f02ebe687e59a30bb738928cc5d40559dbc410ec26156d3693f4bdb8fc1896dc91b5d1a08f1b2	1	0	\\x000000010000000000800003c157a4d730af4c28cc15bbbbd1ded75fe7ca684169506d57abdf4339cd395413710547a6d1492a9f2be29941d59fbe106cf8625051107b157f05f0dfe8002602386c754370647fcb51ef7c464fb45c6bd18b04096abb29c825890de96c5de5c0df067c28a9a4aa24a139543ddddf9410eb76575ee208bd5f62790470ef184485010001	\\x85ad655b2b90901ee4da5f83bf1b3863974694a4bdfe0cfbb3414f892902c0aa13704645f6139dccc7d1f9338057920248f2771cb28cbd295ee2e101eb0cd30e	1668683258000000	1669288058000000	1732360058000000	1826968058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
340	\\x22879a402b7cc700f0322bfa3d100d64068c92a6cdc76d11c027c4f11c7a179acddb060762fd8b0540f2a5fab928674e7b4f94d533015d19ba0b1ff02a99b798	1	0	\\x000000010000000000800003aee7c0f60bd72e55205742ca3dce4ab28ebffb6dd3f7ad9ad1889ebb447f38294af6b61ac0a87c18f156a56b21a1ed57ee4b5b2a0c54368660e6b06c4490312caae8b032e48c63fd44d2c2bd9c5501adb7f53bd5354522b62171e50be859081800d412b5ca72309eb8b0806dadb4a09f3418df1eca2e87254f68697d8e9b5675010001	\\xf13b9226ce84fa259ecf616f83f4bf82c3a8bd0f1717a7e02939e2769552235a7f4b14fade8b65333352fe983abaa29fc7d13dd62ce5aee67374afd48e9e5501	1662033758000000	1662638558000000	1725710558000000	1820318558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x224766a99195dec098994872d76d320baf8c2bcf291b59cae1c8482f710c31927e66b0b96927f287c0914c5d318663c21aee710198a8661ef8a5a0b701700199	1	0	\\x000000010000000000800003e3a3ea5d1ef160157e417da4b8ac4b768706ef38442ca649bfc7121d1ed9257eca32b5aa2400289a8e502190f818d3dfbbd3bd3d05539cfdff477550ed14210e18e9aa00469ff002e5ecf5386a469fdf30fa747527c1d368c49cb11a3c1754b3882417e1e0738015139eb302a2674f4898c09251a639c57697dc0dfd36d10257010001	\\xeca5edaf8b20ed02556fb4236f9167d474685c0ab6a45c2857dff3f0514c4bcace62385853816f98406d10fa6f92e207fd4a7af8930d8c32678d07460aedaf06	1670496758000000	1671101558000000	1734173558000000	1828781558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
342	\\x25ab552a149d20266a67184899f086ea6ae2dd6ce5df3ce110f4c9f77994b739fe742b731874d69a688d062f82b9d55be0e511444bfba53552218ad0b89cf94e	1	0	\\x000000010000000000800003c8265b469deaa1b4a1d0e1919a72b797b9688a641a442a76b10c7aafbd3a39c8033548dc4f3b44199ab92a969c42132d47419db84ef224dd1745f1d40666176e64953666c3af705080529b8531cbc342e8cee68ac7a6a65b44b29462cb2399d1b86eaf4f0cc059974785c83218ac0ee4df65d57428c48faf03299d4112a46de7010001	\\x5e2a2d8f430846bf2f9ca26d638083c3e4b8920481b9e0ac4d25ca6a61b0330f45ad9d23366f2398fd8b7e7845580abe68c4abf8e6b3a8bf78c15e6fe7a37504	1668683258000000	1669288058000000	1732360058000000	1826968058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
343	\\x27073b29046232f809aa6d3793b43059f2c2405519b4edd76d36acbeec05d02c163e0fcc552437af22d7c07e216f44aa45b51b4fdea5aa199b8420c8ad2eccfe	1	0	\\x000000010000000000800003b59ed2abd3ca4ee3edc3eb7a8db59ba906f73f2519157ed39f0ebb20b01328e6063f3f1867df63a55e3c540e4a2a38a19ebaef1460e55da56292c1064c087f76b8c81e09629f18dd4dd07f74e54bbe878ba4b88c4a5556ef4ee905d56734d0574b2622bd101fd9a0ff6770ea426aad073b07c3356c15870a4110129e7bb5cf37010001	\\xfa56c3830b195df64f4f67f8dd1c5e43cec649ddd7b3ce1b667aa22e9f3b4a0e1daa3bcbd9f794eeba85b8f9e41a696f3b43171038fe9fab005103f1901cf70b	1671705758000000	1672310558000000	1735382558000000	1829990558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
344	\\x27cb89989341f81871e0232695219b68db81ee15b83ab49183e3fa1fcc40794a9bddfa996e5b5d2b2b078e2cee3201391b5b9465b0e3106d276f282ac69f280c	1	0	\\x000000010000000000800003afc1ae08e40ca47bde1fc8d79548e4a6dce249f0eea2e51c0b6ef3305db9067aace744b32c6a1489a6dc6de3c9d77e4cb793fd5e0fab08d340271599e3a2f8777d9b5c15dfd2f6a0e475887b097cdaeafb472aedd40f17e5b73d4f697cfc8bf66595b2467749b2979dc30d830bbd651294285c20737b03d2064f8a451ba66db3010001	\\xeb48ffd3254d5a3c6eec815d59a3520ef766542c84272cc0528ddb8f1855557afb9908dc40832909f90a975d62d9359c6105cd1fb5f3499057756235db0b9e0b	1669287758000000	1669892558000000	1732964558000000	1827572558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
345	\\x2963bf9ee0ca94a3ba2fb37d48aa29ab388bbd65d35570c62c0125b50b65b332e21ca9da0ed6135be993e836adbad262e68c6c35d6c3320da2613ac7f66eef9a	1	0	\\x000000010000000000800003eb9291e86b3e1d5e24e33d63f86ff269711667b22d65d69dfdabc40f944f086bea387a113c87672e6f9ac6b2c6d679615a7bfde652032d752fe023772e1b0e1f935216cd37b639fccca1151239b96b14524061c6b5fc707027a83f561e7bd3040e6a5a866cffadf14ed167108bb89d9ab9b51a8e96f35ba998657009632a905d010001	\\xfe03feb4ee9d69d0f6d150d37173d8ecc9e5c9e21ff26cebd5b8b00314f4d176b4a52cb2cd277f4e9a99e2bc6dc6822a930d3eef7c435d2cb4f737d79be7d709	1677146258000000	1677751058000000	1740823058000000	1835431058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
346	\\x2e035c8fc93cf75cb3562c82fc1cd9fcacf8381bbacc32ff12522257f66c9dbf95f1a61d9ef556a1f936be2673cd4f628289bf9343eeb7bdce9eb9c2b431fc84	1	0	\\x000000010000000000800003ce97cde1d0fab95c3505d7ceba484253bf8853baf6901753825a5a587049a88a7319ad4172dfc90e9e329f64fefc7390a12a2c3b4b7ed6315c4d5d6eb0f628ddf42fdc2441945634af303517b560458e80972e095462e1d86eb8ca96eeffa02179aacd78d22c6a8e0b0baaacf690eff7300354b502093d84e25247d57e68c965010001	\\x01818b0ba5a3733ecaefed9cd91209b51be3f637abf185349d47bcf0e6ec6c2945b9feb69159acf7a03b6e776763757863320bb50b5c875c8451352003624d0b	1668078758000000	1668683558000000	1731755558000000	1826363558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
347	\\x31ebd459aaaea3c0e4923cd3f8001b4112f24433a8821d4910045e97578783f577f0395c24e7295f90e584dfa5e37e287c90bf4d3bf2bc33fc8f022fd7a7fb4a	1	0	\\x000000010000000000800003a3ea35330003ef96acd9e1504e5c08696c9bd1da40b4096bbf4f7a0f315b86a140a3806c478107f2454df40081bf6790763c35dce5fcc9051baf6915ec88c562d010e74fe46f10257e390858244763be91d15add1ba0a6fa2a9effbf8b9e8bbadbc5d6474ce9dc55e04d1fc635dbdebdf4bf97bc6d53817898a6e1d28fc20dc7010001	\\xe2475be4f7c19718fda979d32f6155c25afedfe14dc1a05166c663fcb8b0aabb2f583700c8a6849084467b94e5e419bd110038a6e9c5ac6b0238ffeedd42d30c	1648734758000000	1649339558000000	1712411558000000	1807019558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x34c743e7d3c2c1a9b0c0ebc52fdcdf6d3da8ea3bedd0d9516abde216a18400b0090edf1450f4863ad8ddd293fcb3d7f7333d3d81040048f84bd99d46dcd09953	1	0	\\x000000010000000000800003be679cb33c2863cc66df67d9653ee49a5af9d8e068ca33bb0fc0e98f91dc46d1e7b288b0fe3c756eac3f09cc6d5780ee9f682fdb62688642d410faf4a67eeeeb03b347371cc19fdf80644705b6a26219645ada80de1c5a779016c225c7e77648a2973103c20edab4064f4e7def848b8162801ff0a0c8fd1bf359270d8e5ab6dd010001	\\x4176283153239d600a62d5bddf33cc19b59dfe2fcbeaaaf2ea70b9e49c2b91a30490de7ded8d872c67c3f30afe1a78ff2dd2faca08fb288a61c325bddecb7204	1656593258000000	1657198058000000	1720270058000000	1814878058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
349	\\x380b3eb328824076aa93feec4e9d801430d87b29707157e13b92675e8c6e337a13bb5e4097d3128bb86b8df17cec42c5060975266c6d5fb6278c6cf64636617e	1	0	\\x000000010000000000800003b871313fe42699f6ee906ac2fc3752cd3973719d2c330a30d31a51a3ea4933c8a0e244ae6ee0f62c9004db7419e20ba480f960aa61a34106f9992e55e2e4e78b2a7fd2fcdbdc2f6b38de78e4ec414def161a717cabd213507018914b9a2c5d6925f3016496d2c752b8778a4970b57c7533ecb045695aaf852a5c918532dc0fdb010001	\\xdc7313ceae10e547f60e7d270b1320d1b718a3c8017bca414ebd6b51439c4cda7c62fb0e40aeaf1a6fe5ee14fe457bfdb6b7a1188b9cc4eb50199facf4e23301	1654175258000000	1654780058000000	1717852058000000	1812460058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
350	\\x3b273e1b4dac61fb6b7730a42ea3297b28b4410afead5991698254891f3013921791f872ecba3689542baa8248124cd62a0f928993ccb1c9c641a7b5908d059b	1	0	\\x000000010000000000800003e1385c676741a4261e097eb1f2085bb095b3d3f081a7c7c6a9527f735321f2cd289b1fedf39bcab922a7b4222af150297c4a364d92d98b3b2e57ffabdeab6a55c9b9c3dd519193d6afc625cec680cbdf57294895d050e43978bf0e1a9b645fc9936fa686ca33ccbe37d11fe8ccb54e619bc9f78c38c6857ccd5c78741fbd5789010001	\\x2c3fab97f22b7532ab051d5aaccf1ca3520cd218f081beed109d1488046378fde2f47552e83afdbab5f63712b3bfd630972d1ace744e15131675afa9c226ab06	1665056258000000	1665661058000000	1728733058000000	1823341058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
351	\\x3b2f42b405db9a76b42041f6b2490a8b39bbf007512e57363eeeff60709e6a776f875aeb3c4063704d030f40e1a163373949906981d142fec124180a26cdd555	1	0	\\x000000010000000000800003b6e1758675b92ff287a37b203748db5e20f96cec21fb1d27c2b8663c20d0a8e2ca4eb7eca70d83f6ccf90b340a6052dd6b40b2ef47d57b3b3bc12d723b45a9069487dad9ff3b3c803d62d62a7b4c396616877116eef3c48f5816c1fe7c492aff2947859b77ff17d76a1dba4535fd0520c284220f6af19b610a53c05660b650e9010001	\\xa98629114bf7dab44a6b2a70dc5069afef77fcca249ac9bace2eb12f87f52aeafa20cbb5be465f50a26009b03908978db6dc96a14d639c1f4bf6a26cacb46e0b	1659011258000000	1659616058000000	1722688058000000	1817296058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
352	\\x403f69a163e69c5500aa70f35fdd5a8ba0fb54d8540ab3082aee214c2fcceb2d45494653fbf5250aafbcb1ada67cbe154449d0f59b25f1689d1aa7d6f0491afc	1	0	\\x000000010000000000800003b8d0f64513a5d03b048d71c8dcfe1a9c280a89f5aa41e18a62a51f4d61cce6f040789a405fae1aad4650eeef4e31466c32cd2215c635bfce7aa6fe14ce2f78bb85bff1a989c31b51fe3e3ed834c3db009a4aa267e117f288ba7a34504034d581e477de09eba0e4583c57e1908cb1d6df44dc579258c6515173995d13058572d9010001	\\x5723ca4b87ec6fe6f0228b461aa6cacff73e31c8a8425dc979b180b4e3badaa796437ee6d9583a0347944d8139df99b54f3f50dcb8918d30d65610d93ff9b40c	1659011258000000	1659616058000000	1722688058000000	1817296058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x407f0871749d137795fa836ccd5d4b62701dbc2fd01008aed11a31cad0c67a56e1c873ecaebb9d1eb0bbcfb9c52f8cebc1e55b3d885b372df5b4ec8b62b619c0	1	0	\\x000000010000000000800003b845433647cd879fbb12b07f303b4716dc35b43c2e8ff7c830e829ff75f138c27aba34c895025b87bbaddf6893da4985fb014cf751129780588b5505d773bb3b0ba030ce5e9389112a1560eed719ce11832f8677f04c11822c6f2f744f7ce5d235ef8a9f99f1f0de19d0008543fcdc20ebf3f719328758223b68863a7bea672d010001	\\xae131adfd0bc71388812957c9ee98f42c2dfcab6c103e1292d7a53dc639a13a51eeea92fcdb50bec94f5cf1926d43bdf0a4b7e4097200eb53cad1265e4109506	1655988758000000	1656593558000000	1719665558000000	1814273558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
354	\\x411b707c760620d285d68d8a9657d60bbd0d7f8442ca78e3ecda5ea13efb7c07c03d5313ed50663f84599dbc0317c6c5c2392153d195a71cd70ae0bc3aacc0ed	1	0	\\x000000010000000000800003d253ca3a7751c68f9d29846513b854b18ee4185ab0733f308f0a0123c1fb408a8c303a3ceffd4e2ec364a0dc170f1e1f093d07480450b23958e7f6b930df8c5bf4d0d614f4841a4184519367ab7be96ddc542e49af00aed2a421ee0d4f88b03dcb87cc6039b619db371c28bb1dfe63645e783f449313d6d364151d84448ccff3010001	\\xa725175e2f26e8fe059c903e82bf0ceb1d4e79394e6b5c93c6265fdb59ae453a17f4e21e970139f81a028d12d8d874397c7b4019f4adc2761d58638883e1db0a	1647525758000000	1648130558000000	1711202558000000	1805810558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x430b644084d23ed3d72538fbb49cc821dea3568e77b05e5588dc4a57f2952549a7d8bec0527d971b74d15dc41b9f1ff6881500e6c37932dd478776f09a69a002	1	0	\\x000000010000000000800003ca25d8f2c31d7ca16b675d7a76c5b3fdcddd4be25effe81952c2c64b078781682199ab167caf4f5b791a4f30ce4674ea85e733f758022b1cda454dc0e4645149c0148d3a8b2c9a472b978eeac5f9325d900cf6620f1c7f8dbad30cc58e9af36fb5d626651afec89936917cf716dde96ce46bcac0c2469b33c60104725b5d95ff010001	\\x8ff60f07fa6dbad28dcb11272f82375eae7403edc39a81933b94a656920c57bdd452c6de54162055e0644a09bdfa6f46e052502a1d3a7792ac653be68ef6250b	1655384258000000	1655989058000000	1719061058000000	1813669058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x447bc9d34f01e6b799ffacef544ae6ab3a569f289c207531c78639961a9bf0d65ae8b378eb9a2f63ce346b5f4595d6b56dfa5da8d75656909fe6bba372d5719d	1	0	\\x000000010000000000800003cc9098de398de381be6ec8e8aa5907432f77814c22a4ccbbd3f70138ee0d92f265426a090869a969aa29db986038f01dfb4b24f8e1e5b688bb2796696570f6654f693d27aa64f8e69795defb556a3151bdddd5226d5190faa97010f63b7fe1acd07c6900e050e87632d99f9a6acb11959fd35b435c252b543e2f72f05d89b149010001	\\xa71cf453c2ee5e0659761215f31557e267bd541ce7f80a1c6582dfb2a9d945c82bbcaf09766a99e269c67003e91c679fffe029b3ba6b9e0085c0efde6080d008	1675332758000000	1675937558000000	1739009558000000	1833617558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x46b73fec6f216fe65cfa899607b36cb5c1aa697c6c618e9a97d6e6cce0460644ed1005e708ad9d1b18774dae51fa83fe888729f6cad8d18c0058de0eac5aed0f	1	0	\\x000000010000000000800003ad7d7146f586fcf90e41511bfcd2efbb21b80eb11560dcaf4cffc22149c976854954f05b6df207af7de365dbfd8b8f848925cb4f8e88ff3d73c38659c6dd3765033779455a3b794e43c8361607db13a5939a7e2b6a2d228db74a98fa7f88143a83cb0cab29d9a1170371c265f2d548a1ba50c1da2e6efe93dafb9eb39e22ef5f010001	\\x03b9213e70be0735d1a6aeb12f16c660ae47bb45f2c5f0bfec315d89d0e006b219a24aac13763358870663b051ef0285c8d960be4f7a9ad9a9d86a1c3100fc0a	1677146258000000	1677751058000000	1740823058000000	1835431058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
358	\\x4853e01d19098589eee5947b5705d54e2b1dc53527289a4e604b5980b99b9c5e47fb5aa5dd2b551dd5a34ddd0143262229ebd53c81bee61f0a7046365e4cafb5	1	0	\\x000000010000000000800003b525d14d829088ac4b4cd20d98753823a9d51dd1d779b4107caf473cbf2563180e8a7fb0039daaef3efe6b1221ca609500f0c3698fbc2af48a0bef5210169833c5e563905470e4796336296136d0afde1e79f40c9d17e471a3373868f657895cce31cb78b9417f1362fafa3aefa8b21333ac464311cd24979ac8b90bf6ed0eef010001	\\x9f48afe121f63eca709eb3e56e30216d1af7f6d7304213ba07900092934f2340065a164a77f2fff2aef1e9b3404c50ed36987387d0955ff194a80317da49b30f	1675937258000000	1676542058000000	1739614058000000	1834222058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
359	\\x497b16e62ea48acbf67cba8c36aa22e37ee4e0c1a697a4ae80ef67f707df8b096a76a9c87e0a7609a6a585e31f3c7021b844740bda7bd7ac3ac7d0bd002815f8	1	0	\\x000000010000000000800003d09c859bab472b8603dafb25f3cb2110c9503c27e30dd6b745e182fd290525004116fa2f0d4c65445ea8d98c757a18aa160694b4cdfde07ae861fa72c575de8a4373c3bcc0fb7d7e8b59706dbc7911786f3a1e02ae06601f62c9862c8ddd7dde4899574dd006f6671055b3a6be6ecd391c0300740f17902865b5799981742ce3010001	\\x8cf8926bb19f9eb89339a4d71ddc5bb1c983afa045f1de9cfdd5309ec3f3a8dab014ec488aea8548d98cc10f914a23edf0b0781895452f17d635a413f30cfb04	1660220258000000	1660825058000000	1723897058000000	1818505058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
360	\\x4a2b4f4572140a9337bcf8d5397e55d81eb31ae480ce19a1806e59d5400c79643eba3c13c9a46b49699fac61b3cb70405649c67861eb7c8c65d461d9ee0300df	1	0	\\x000000010000000000800003a6633666a5596cb2ebea42442feb8a2150cb4341518ec879813ee690b4fb2087a85330e650335e67f711ea4ccd36f5dc5fd4b69c2c39d44beb9657bde02cf41286e305b5435e1b0217a0b69437bb408187dae7000cd917486091638351c7466c3522ec23c77d59983e8338a1dfad4e55a549fbc4be05f2b644545fc3f0d498ab010001	\\x033f419bfc37a90a5dbf8c9cfdfb0fbcd53650b18a62c4b8736035ed3a274282a894c80adbef70125e12ac6bd8ca9f491c697efbc71cdf21cd24f752dfc62c05	1675937258000000	1676542058000000	1739614058000000	1834222058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
361	\\x4f13d87414b9194e1eefcdf3c49033d3e41437f2e8fa3a58b38cad5a7090da572cfc0c96f170430f2f839cbddcc02ebf40fef806bea853fdc6e42ff1ed3b94f6	1	0	\\x000000010000000000800003b7889c13884af9e8775c20b88adc97b3b98b941bdf75fef7eb975f5ea25ce7e72e210124f174fd5ea3ddce47bb5b946c9673a03468bcd396044793271d5617cb58a2efa78befcab90123e66e58c111f82004b997f7b9c43dc39399156077598eed0e9c4eab1a831768431de26a24dafc7477b44fab35974ee6e5db1d89bf1639010001	\\xf0794a3f48f10f23f586737929c62b60303daa8c65fa21234021b5e8a6a6bcac5024dcfd9dc80edacfb9d7db4fa26bf9ec1564b3f0ae05cac3250242bad0a509	1657802258000000	1658407058000000	1721479058000000	1816087058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x51232173d53331937e05763cb7b5cb5fcd2d957ed892977aa396ef7f0a258b73cb6e38ebf21c00b1311ff654906cef18148a2e40a8b386cbe252671a6aa6694b	1	0	\\x000000010000000000800003c7b3850557809744e9f43f8dad65280c5b647fc87437f7a0a751551550063e5c47f1c5ba5d57f97b9ff1ea3e7c4dd67f7831cf7248f55d308324b59c067e9297ee1461fcebea7cbc7fac128b473f7d7a2c7419cd23516a2224390452c99bf090e8a171b156e26d7d4184aa19b5b0b10847998fb98576f881331346f0db30fd29010001	\\x0bb94321818b198b81b894b2ba29dafae16f8f55564bc4c31c3d7a10919f64f70261428fded12cdea1ffe46612fc894f8f78f3b4644811b059f5c4398eba7609	1652361758000000	1652966558000000	1716038558000000	1810646558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x53e7924fb6e886df2d7f4fb36f47f6c2e11a6caaf77f7f66930f799e3e0e334c6b69920cc796b956cb18b058941974cc53641bdd3434ba1e1bea10e204c40445	1	0	\\x000000010000000000800003e53b65d1241ebbf6c9af1abacad5387ab7122cc87bfa9846ef825b8ec09569cef01c0a6df4d3d7c85636d299424540028960f98397888ca9ffb05ca86d257f891acf692c041a876a825aebcbf847fef6468434bde1b6d40e85372486c7a0632a17f4dc34a2690873ba1e512f95fba8b7162bef122995342e4e734b5a023526bd010001	\\x2821c07a1eb55ba7edb6318b991d19ecb6f525776d98ac701b31a5f3496aa5965cc8f048ee346a8c72cb569ad681023ee72d273a49ab9d45ed8684667c44660e	1655384258000000	1655989058000000	1719061058000000	1813669058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x54f7da4d488c7bee7f45cd5a336ee7bc8bdb453cc5764dbbc66a2d448af17273f8694d68401ba35c704a2d331d18d223a081381c93c72f9bd9c87b9b4d17c4f1	1	0	\\x000000010000000000800003b03e34a3154c8749888356be855dc949f89e9a4619d9a172a2e1081b43c9bbeb2fbe5b0ce07d5095c3db16b6d0cc91576e30d28873bd5a63e6928a62e36ff7b40528b222c64d0c3689f717afbab413e086a5c6484fb20ef17f5e15e00b41e6017290be20ce5f37fde53dcabf1ab1b2d6817a2a4d40be2d70c21417d4c32b43bd010001	\\xe0a526cd84003769ade5e9f0e805eeff8ca8e17b2aee64a9bd7ebaef8e566c20d66929ffa13df80e350cabda1988a83b990549c39fa0dabd084fb363efdc8d0e	1657197758000000	1657802558000000	1720874558000000	1815482558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x54d7d42b795f364e0601ddd478fa82eaaa5c8b35633c607abf0b315e046d2dbd6b4102fc03620da90a3e14999f05f25a1464da0e79baabe8b31e41dcce8d13ea	1	0	\\x000000010000000000800003ebd4d2c940a999777daea6dd13e41b4158361ea51ba4e26ffd068889f9c9c50f64c60b904cde3e04ed4acde1251ceb33b22de1f1d854460b1ddc794984171d3a0442457372596a9d60d4ba42fff9d250c8fc891276e7830a81992fad05b6d1fd6b9104c734842854ac1c581cd113bc3d36a7bb8e4302dee1e60a74ec34d6513f010001	\\xc0d6bf92c549e5b2597d28b3bb2028f86ddc4e8d5d7c48882fb7591ddb9ff1a5aaf1f12bbe2f8dd187d36a0bb140d36c8c3e20fd67dcde8ee578c71d88b49c0d	1651757258000000	1652362058000000	1715434058000000	1810042058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
366	\\x566f5b6dcc7522770207ce76e54ee08287a8fe03aff7c684f4afe48c76b9689b427f91d3a7b5f87e6c0caa4c119b5ab16e73a0d776d68fd6dc2cdc24cac96533	1	0	\\x000000010000000000800003a72b480870019babbbdeae602c7a7798f1bce0d5f35c75cbdb939e6e5ce07141774585e58b62a4317f24e9f51a4a06543622e15471fb2e9705fd7868c264385a6f2809026183f651f7017737a103537ea552bb4042a7790e0f127904b1f00d9804afc7854ce5d77e442941ee03747f4c7591948b9678bf687a10b9a95ef46291010001	\\xe6e1629c4596adb0d839907d15b3527fb3ff7a798aa8c74ac17129b2bfaa69c6f4510562197d5a8a68631ba41818bf16928860781f3b53787391422ff3cd1b0b	1664451758000000	1665056558000000	1728128558000000	1822736558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x584750eede085447f359c7546bc5a27a2291ad042ef30a23ee28f2b48348224a989e3565d5cd86e651bd71d3eda9db916bee139b2a63e1af9d075c6050fab777	1	0	\\x000000010000000000800003bd47ac04600a51233474b7951687610aa860e3e1c8fd59ef34f3011a7965751c7e8f429a9fbb34239d9a13e74f47d33263832efca9cb94051939f4b2d3cf717d91f1ea0b3435083c9e04f43c5708fa9a4e93b2d20b8a6ba6c54ad3447cf36b1b00b9e3ffa0a39ccf700204d458aa42fca0c923849c45fa7bddb0164682474313010001	\\x997752b60a878a98e6a0e8c4328441f0731bcd6b7f41a63c49b0e7f97fbe906c84bcc51a5b3f1fc0d150011192ed3e9f6404ad308660d14cf23487399b5c0b01	1678355258000000	1678960058000000	1742032058000000	1836640058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x589319a5f48cdeba281bff01c6c90a40b02a47716d9f17bfbb9f86b4cd3a474dd5800ed4e88deaa6fbabc401cd4b7b54582c485b2e81f9168dfed5c86f941c9a	1	0	\\x000000010000000000800003aa9b49376eaba47d6cd7c8db00c4f41468118d9ddc9b5796a5012c3e2038705c4f79929df9ac80426b394a2ed9cae570ed2b154a549570a356489ca2e3531c8b8a9c99aa3e9562253d5a8ba0af72a809b8adcc210b759d4dd5cef85972947979b384da7d49c3055df56a581f072426989f35cdc4f4d5da507e94f62288d30561010001	\\x92390004a6c512ae3d5284d0b656427e7ec8aa49ce0c464cd0bb429921765242ef18c4343be11144072cd7b45458c9aa491cd519e476a080da87e4b18644ad03	1666265258000000	1666870058000000	1729942058000000	1824550058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
369	\\x5a8b5ae4f429bdb65f1c005330d116294a2ecc0954cc4c6d22e747131aa323a5d7745ed94634d02669076800be474aa0478216693281f427a3437591279c2df5	1	0	\\x000000010000000000800003c3a99ee022acf0f663f186b441a44b4643d48d80c01b8151a147f605b8683b10ac98fa8f0391ac2dbb21a606fd6564f6b2f8c23957f3234871d4f18c956f410e1e34fd3ed5668d910bd432cd0d92c76be993c92e8b6271737226672fc3042f2fd053e20932e1182c1868e114725eb2f4ede2e68b7f6c98173c3e50db605ae409010001	\\x08bb38ad085017f5bc601626f451b853be0f224f06146c4a66d40a217804628b7df9b07636f827e07a1b0e84db21ca6af4e1b08534133513a866d7ea0d8f6503	1664451758000000	1665056558000000	1728128558000000	1822736558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x639b2537ac0db9dfce044366cf55eb71d2c5feb80236f1bde3e4ae923007a56ea779758de53587ec4984a322fc508db092f89ca930603413c9666c8bb7aa9c83	1	0	\\x000000010000000000800003c263c7610f7bd700f76b89daf0b464fdc949fd31d162804b9614d48208145d0970002622356c44f50dd33a602fc9f591e1c9d44c15d178edf5f92a34f02447d1f86a01030a9a1a69e79eb00476cd1240db1c5ed204b00b23062b3a053147fde47c3b4fc44848d6e6053ce11d44797a80bd02521f38b1f77dd92eced4dc166dff010001	\\x89732a198a017bc5563d48c1fd8efbad4ba83aa699f345928a0152527d41f533e4b6c1e9fe000539b9b7ec8611b3ebbef9e38233f791665a2036fa2ff2b8b20d	1666265258000000	1666870058000000	1729942058000000	1824550058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x65c390fc1d407c6f0081885332b95407c2064c1d1d67e69f7be7ca2d35eca179362836fc80ce0f1b0d13f8d0a4196b5b76fb9e3b914223cbd2c50eaa07307494	1	0	\\x000000010000000000800003b92f237903909b86170506a3926d7e561544ec7c62989a4f88a89d9b303719a096762ed6d32a59a6d477e3aca83037d5614c249ab89032b96dab5398f79c11704e730641a3d66a4c7946997411d27eed21757c2e2b6c2b5ba39b04903226173f6247f5f83c8984ba167177d01d21430aacf21fb6073976825d33e9ab8a6cf927010001	\\x36776b4ce5eb6e89cd91264cf627d3e65a937711b2976c8489d9f0920507485b610560c02e0998ae37cbf119dc8694942a3e4556c6a135b543567549ea8a7a07	1674123758000000	1674728558000000	1737800558000000	1832408558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x67877403a299fa8c3e3c453f289fb234105b290b329f9b87808ad54d67c57d770f7b9f51b49c799337d6c8138b2ecadf5b698fdc774cb098314578f09870073d	1	0	\\x000000010000000000800003e2da02006ccc1bb8d56140ec1729e2720fde290dc44da030d52ff841a040e32809d7ac20f2b5278755275e9c99feaf6b48943567d1e3a7a6bc42a562dd089481fe801227681be5c3ce3e1f3d44c6c35a8e622ce59c77a898c916b07a3b99f175b5ed6cfd9ba5fe5b309ce7e3a893903521c7f5a410d0709bfd2b654a627b75e1010001	\\xc71af19fca1c9b6c03041ee14576603b87dbdee8bb3e53a4f39cd8c4b0bee5945c32c12e96a41df69c4da4ade03958a5962970462a39553b130e256581eecc02	1677750758000000	1678355558000000	1741427558000000	1836035558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
373	\\x69c739a4d4c1b6a132cd2878b474cc5fb82dc98b4f21d12aefa5e1469671206ec313a19c55c04427da3094718e34fa5484b65e5249b4b4f83996dcf20e72451c	1	0	\\x000000010000000000800003e0bc6dc4352b663c6029477a7ff0a95d87994d850831acd745d621b8f11e101702a3aa89c8392e610ded744b853f70edbff0cc687f449d871e81d2fc221be6038a95da32a6b00a1b302003afe3137276971e83c948398035e44a163caff38218161c2194c1c8b6f86eb23b3e4bdf08261cf28edf7fce7f0333712061fbf562c3010001	\\x12a8362de16928a289e55e8479e33f494bf86b0e965a9f906987dc4d3f232f2fd78eaa1ae6f13f79350c24d36e8372ee572946946df1ca1ae7cb3ebfde0ea801	1677750758000000	1678355558000000	1741427558000000	1836035558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
374	\\x6b2b1e1d0ad21f4311e67be05e0c1dfb97956602ec88dbf437f294557d7505328e4f0eac1edd60bc5495e02728ea974df8d61b32bd1d819326cd99616a1f7d28	1	0	\\x000000010000000000800003c41c5a45a43f14569e6c45091e7ea808dcb8a90be15c74a8f4f575f2a3bb70af835f52ac18a4a27486ba11252bab7ed61358dcba560514c0bb9ee6e5b61dd79252f54e9d9a408c716ce973aa9c950007290783989d27e7ddf2abb0d1175e61ad1be906ffb9afa7a5d903ecf0c20c8a8079c6b0a6ed0876dc4a8c8e8a3a5486b7010001	\\xd4dca97b1f2ae4e3c2158bb755f3ca21ceb74c6f9a91bae404fec7575294430837f06825fc7acd9401aacb5edf95ba683f3f6b36026fa7ad9d2c4e4ade0ac90d	1664451758000000	1665056558000000	1728128558000000	1822736558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
375	\\x6c0b1c0e0d6d0dd7f6763dead53e1fc65de5c897e5747a8abae42ebb091f3302417b489548e421905e27aa2e5f8ae0e5e842c83be1c7b5f03774d98562b30eea	1	0	\\x000000010000000000800003d5f0c2c54883dfee41dfa6246a5b2e73e4bb6c7e65fa5c88eb279e7b27d3761969dc6fab2c9bd23fb2821b74e1e79b27018b5435f6915020363edd64a1c3e31a6a8b64bb21057ad7b1be1772a8838968ef7bb9edb67bcc75ebb810a4acf2257d504430b8e799fa7b0dc0b1e50299ab21fa59e68da659d79eabc944b1a8550937010001	\\x9369d4b3aa0cc24791ef2565287f7ccc5450e14c22cea40c3a530b88f511ad4a7cfc7df57b8f7398cd7df896fcc7e488765778da97f600f4abfab437248b2c0a	1668683258000000	1669288058000000	1732360058000000	1826968058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
376	\\x6d53f0ff363f91d677f3ecd3658e9553bf0e5bc93a301fb732f1ad90dfcd9f23393e8079d3869b699bb29beb1a41354c9188425a7ac67cfbbd448570f95c1bbf	1	0	\\x000000010000000000800003b876d0ab5828b8d7d9134fa8288462c0e0999545fd2338e12623737531d14a10e44bcace17ba4cfd123059d96085fe264b8ceed468c37f3265947e1acc1f2eb2f8eeed204f4b97e9c7fde1c913baebb015fac98e610a1182f28484d82c86652c95f4d4aa38d2122998b04e127b492571a84661c4afc49419731c53645ef64e39010001	\\x0d4ddd44dd8e1d6acc9b59640654ca91bcc501224ed1da8c2ab1226be80f9751dd33cca988d62927cdebf6653aa7e395cff0ef9121cd2daccae9e986b528f20f	1667474258000000	1668079058000000	1731151058000000	1825759058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x6e671c8bd2dc6410ad0ccdc01825421f2d9765300853bf8f3c07f2ddc3823cd0ddc06d44e9e96f8c0e5d6b58285d66d52aaa0f3aab07efbc8f3fed228021868e	1	0	\\x000000010000000000800003cc4152768a206b7cde4dfaba1c92aa7db69a63e6a83a85106c9712872a731a7b7a11b817faa4dd55a61ce53be258bdae21cc3d14b40460f79ce2d6a6fe35f3daa991e320faadbab93a0479240cff2c5681ddf10b15376ae12bb833b1defe8b82948bcccfdc89bf9c90c7b0d02677e5e36404c8ab597c102b793e6973c9d1ae7f010001	\\xcac5de6aa90b7ddd16acd472ee2490da506fa54a659a4331858cdfb827e78d1f01bd6a32cd5e52d692fd9f7b5b2bc70862c0ee1ac643e8d71f84c15e4ae36709	1666265258000000	1666870058000000	1729942058000000	1824550058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x6f8f02a78e87459581aa678e26053eb5e86ec3fe35a829e26ee90af580f4acefd0d4f104add0a6a7738d87043c2afbe049921b7cf87225aa05cad56585846f73	1	0	\\x000000010000000000800003b4fb3c355082a95a338ac5eb0e7a85e9f470cb697e69811be977a399b91fdd39e2323239d5838e85b74133b0a635732e32f0a31d825e2d0f1748c912952223f4e9d183759fba8948e10609feec4365470b7aaea548a03c67c39803f966b1811a8056d8a8860300fe76f538524cc88ca56c233bef2b7eaa80adb27a61a33c7169010001	\\x672b8a3e76205c6ce88a40784a7e5198504d2294d5dd3d8a8764c8ec1f214f241e00fcaebeb0cac46e135e99872fe1043beed73e03085fd7a69d0d7795e3270d	1674728258000000	1675333058000000	1738405058000000	1833013058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
379	\\x6f07f1e9dbe9606f5ee94a2b54ed077ddc8f6a5acd765426daa38372566eb7b95da6cac641f5a5628586eb44a23204348b96c22f2093115ea607d4014ef174b6	1	0	\\x000000010000000000800003b66d053400dd4280cdb9b1cbec0ebc7cbcefc96af39134eb4740484764330dd84a3b31a5a38a1228f67e17d787a343ef8f15d21ebc1f67e513a659c22acf35e5177b16088c655f642c6d5ca7c3a1685803f5cf1b1be12e633dccb902aca84e6823148d6b901e82e1b463827297540ed5f27d432827e6e880fa1bd9c817d12af9010001	\\x5b92ff6c06f00cdd02b49fe9aa36dbcf7efad100d5403a0ff4ba81570e73e3fb2289aa129e133b2cf0dd9ee228687bbf3791cc1495840af6c37decd8ab534d0d	1657197758000000	1657802558000000	1720874558000000	1815482558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
380	\\x715f81894447affa5b0728045801b5fa1aa867b1e6a50614579a563b66b6f284349fe71c13c28127e8b098032e62758337d3005ad5c0a86bba1ad9dbfaff7bac	1	0	\\x000000010000000000800003c1f0986fa86471c76acf0af407cb69c072f633a3e7a09a46fc5a027c6e33b0126e758c173d42d719afe7e4626eeccdbeaabe9653c3c39bcdad4da36adf8eef5f2329539e9cb4eb8ae5dd9ed40d94157b7b1fbc2b47396d246e9df89cdb93f88bf9960f0a5d1f65d987d829bd144c09a02dc0585b50b7ee5f27f70abee027a26f010001	\\xbaa9a2d7e9e68a8d302d62600e252e865c82dcbee3e9fac82999a77b913da1d09a08b39334a03c3a8329e4ab30f30f7698d85fb5918cc987d40dab97d5432e0e	1651152758000000	1651757558000000	1714829558000000	1809437558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x795392b496f08e693d49e322e4d9deac2967096ec4fc3459dc875a857a5d1ea126801a0ab26cd64f51bf2cdbcbb5e5c1edd2a721adc6538fe6c0472e01d946d7	1	0	\\x000000010000000000800003957f4428762249e112b1800ca76b2cd36dc62fc9cc2d542efa766302214d1ac3955c22dc307fd426f6a12e0cfbc275c15f01217bd9637c4597f03d1cc42c89eadc0546ffc4d75715ae9625d2720db7ca49029a298934518e58f963c41559bd74d053ed537a064f72435b6f9bbfee42513807dbe77d87677735118b7577363f2d010001	\\x4c16997297a694e89744de0ab1517b2cd934aad28c9cf270e5384ef832f42da00cbd5b7feec84c51a6884ea81be4b7cd651b100c39c4dfb43b2b5788b54d9f0c	1663847258000000	1664452058000000	1727524058000000	1822132058000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
382	\\x81f34003788f644607de8c50c8d5dad546d930a4973c7ccddbecd090ba40c265efcf83ac7e0ca2a804d713ac99e08caed8447cb41bf5480313cbfd9b6e87783b	1	0	\\x000000010000000000800003cceb5df9ae9e164515813eb8d5b79f77074a70b5415805c187fb8adcb1ebb57028882cb1186e5bf7f9f74f16b30118cf42319bd30406724a3b22346156e39ec159cf54872a805e4f3590ca308352d7c8d456a3a332ac77cbb027608fd0e978944e539c3e119c23332e69a2e6f5bf2c18047db3a40a08cc53be4380bdccadff83010001	\\x392f3f2ee0404900f4bcefad5c75d5e173b226c480718275900200b60f385cab71361af20f6147525580694038bb40fccc5e7df4933a604ea382ca8994185d03	1651757258000000	1652362058000000	1715434058000000	1810042058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
383	\\x8617f7918808e59d61d508b5e6ec3864627e39e7d5eba8b13e01880598ab0d446aec0e23897634d717537973d4f83c44bc553ad0a5ca80cbbc208f1523c694e8	1	0	\\x000000010000000000800003e902921819e8dd9e5c4670b0de212343c104a2b90e5cb76e81f767d7bfa7a2048af1a9b21ce2cf732bd4a5f74832957d54fb3d3366a22e40be66b1cd7e3f11c77f14ef234c8ea4b76d1c5eaf81ee5cd31a9f2bf2c4abe9c931a0d44f1ff7a5759104ff60c7087e8f8095ff45223de73cae7411415bdae087c082b0a44a0bf985010001	\\x4c3408d295e82672265819f24b7a53cb9c738fe5626c88a1cbd3cf55195a8d2d72223e43739a2b031cf17146fce5f1c904e322879c1de72cab437fca9d036d00	1654779758000000	1655384558000000	1718456558000000	1813064558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
384	\\x88d38c9abfd545e88d7064a8191ffeece8acbac36f68e90391dac6937566bd0ebd6291627e25ed97a09547ef978aeb4cb9b578657d293ea670c97ce5b2ded17e	1	0	\\x000000010000000000800003a61b37d9c6994b95d0f48f0b5f745edcef7e6ffe4552805876dce224b9d1b579ec329f6d0e5802d777b1c8f2b1a0f4d28efb1fe042bcc6a0fc91ce0dc5a10b3c359ce69a0a6021c2af16b13e8bfc2bdb79e3b4459913e626f30d86295cfb8f0f6b863f862fe4184eb442d024e4dcbb2af29767e24fd8886d01e1f069b718bdd7010001	\\xfe6b6d3188ecc1df3ee90fcfb85825ab2ca34ec3018cd5bc43e52ed9598d41d5aed69d960dcbcc4c23f27f5574763e657aa34173079db4c68aa4ad206ad71105	1659011258000000	1659616058000000	1722688058000000	1817296058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
385	\\x8a3bd9a03ba054bbea5adfc4b782720e98fff6f895ed8c669d350b0fd79edd5a88c47cb8f26b6fea540db83a13984b843998be8251391814329f60afce482aba	1	0	\\x000000010000000000800003fe7215d5862aa5ed4744bbb3801307f556ca68c623c98653e93e5ec9dea01070d9a73c7e1705ce23e749d7b8b6bd7af7efdd75906a40e9e15b8650174742acba512f202a3db70e982e6239fc9533f415de22d0567acba81b7044a9e9cb1c675ef4cf4c7a9c4551805f4d365f252686c6b16eec76bbd61771f7b5ef302b66d289010001	\\xc5ae8e8081edd16236a77003ccd37639cebe1ed291ae900360e78b89bfa59577c7e41039d4fb2e09a9b12017e2c2d39ed54d8ea17f08b530220f00c0fd959809	1648734758000000	1649339558000000	1712411558000000	1807019558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\x8a4387594ec09d1a90b070e6f72a6201299c0eb6cf60a166b92d4f454a7017147bb52c72991f60db778ae25fd1c6b3b31d5f57dbf1a06fd9dbbd74f188a13104	1	0	\\x000000010000000000800003c6ea8fae3c75b07c3de2841c562864812379603a13ff38e5e89c674014b72cdb8d7a3b0cee5f8203c5a26f529c199f4ba278605e888067ce21a85349195ffac2b9a020faa1a9778149e4a5c00867788a5dfdf921899f1857047a4a4ac03e47b1ff66b5509b43464775225d659248bc4e2e7437a1dcf6449b7cebe1084f16a52f010001	\\x6e58cddbcdedc7549ee3eccabbf926c79458ce3685d493074f949fbb0a570840a151717bc7a98d34707c053b2b772b1f869d151437cd97a1b87d4fa8f04f3908	1668683258000000	1669288058000000	1732360058000000	1826968058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\x8b8fa46544ed0e64e6ad7637c16190e001352020bcfc5b2ad51b43e904554aa34ff3594859d4b66037aacb7cdb56d2475d09847cbe0f12fca0afc3123fad48b8	1	0	\\x000000010000000000800003ce1b82dc84d169152ffb4b2bdaf645b2f41dfbba236b62b796cf2ebbd25048fe207d912ec2cf916f3e1f4f81ce6402f2d286869665369b5e6e1ff46e22947b6aebdbfdf07ebec472761d9459b7da979776c73c9035ab729d3acb3825a5a90305b3c623b5d19b86e9626f9a717d5efb589370743e31a4f5137c7f1faeb8795d4b010001	\\x982b3fa090f6d6d2cadb038a5276384c4802a65764855163e4706fe6141f5ce1620d9068a214ce3f52f33df8a47330963233dd5e960da38014a4ea4e32968a03	1657802258000000	1658407058000000	1721479058000000	1816087058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\x8c0f38772b60f6585165f2ef5a5b0525fb2ec1636a6b54abb51f9ea2be420693aa837b52afaf4ffc687cd2802af16e82286dfb6ae69656899493ee75cbdb448b	1	0	\\x000000010000000000800003ef2805999cee1be4fff087366bebdaa25cccf6b951e21f87e5dd3b04835a2750209afea807d54f0ad408da31556fe1829cb7ea517f43388504d547f778d8c1a1985f38b631c1576807e744aac2d1939081e7785d9f1193bde95bec60c1aec7856c834df021b42b699c1292ceb0bf2ddd5fd65f3b0e6281e35fcd974cebd4d879010001	\\xa947be3e8bc2db127fbacd7a77b93afba7f06707287bec13d7dce8e83c0b8f791097916ac4cea46822f211c9f7f128d4cbd3e4a205b622919027a730dd6cfe0d	1670496758000000	1671101558000000	1734173558000000	1828781558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
389	\\x8d27aafcf801e2faf148f37a4de56772b4a5169beec19f7ef8a4c2d459112b655e391b731010b162dbec5e348816917f1a9ac3849dd752dc683c90113ac76427	1	0	\\x000000010000000000800003a9dd17ce436e1512adc0ac4a9189eb26ed0244866899947cc1586de8f9dc8522ed9466b844b5eb27fc56eda4e29171597abbc4b1532ed4fcdddcbd4f955cd5a7c9f83990aebbf114494e82c072fed82118a75197d333ac7d36f17300df548ae3be57f7d4627a8ecbae93f47e62060398f327515a7775b2f3f5a08462a22f360d010001	\\xc45f4b4b8e08a2d066fc1ccc7a85ceba2c419227a99d7caa89a6461a0b53ce8c3aa49dffbc281264b16785f8fb4a53efe4c29afad8442c3d90f74e83a089190a	1675937258000000	1676542058000000	1739614058000000	1834222058000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\x91f3266bf7dbce49ceee934b853658078a8c3858ddea54be4f2129c89b4dbe42a5934a57ec634ad5291c95479be7c79ad1b4201f9413a38c40969e9fd7e96bfe	1	0	\\x000000010000000000800003a6c726bc856d35f18a4129c903991ed08b69c5e345eb93e9f99b76d2844f1f717b237d959ab0745d7f88254a34cb3fb1354b71d76ff0ef6e9472f04977cde6ad5fef88c9a85577a03838df87841889b40c9ac8f7de1605f316e5d0d61f8db39b1cf7b5a2c6c1e2df31b6e7ac8ae0babc7c23a1aab3bf1ee6938c5930aa5624d3010001	\\x7fdaa31d7b8bd3552b19e8f81871a33700fc09ee70b9b0fd20b30baf328f4688a1a523630c0a68fff746b2c089ce0a6c36396928542add94817235552a79e209	1671705758000000	1672310558000000	1735382558000000	1829990558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\x940b04942e80499fd1cb2733b35cf2d04d93e8abbb72c3c4d5c836b2c4dba489475e6d172a3499b6801bcf8185bc35f6baf2a63aaa27fa24493c851c4c24106f	1	0	\\x000000010000000000800003b90ab29b97991b82f3c6eccd59b57bf2916d96eee743ce39cab64986bc04f6922cabdd895d7988635d27bf7cb239f179f04cf1674dfa5a2019435929fd433c38c4853d978aeee16a9f30931344e0e038fdc73fd9b3a6e952d35b8cec60223318c5b55cb8116b13f9898977d07317305c6b7940f499ba29a904c0f767e02a16f9010001	\\xf30049b32f371c1c0204769520aa5679fc114774829d94e776782925e0cd80f40acf6ccdf0bcbc78c968d9fe8848918dbd7683cb4f6d89778ab2f4f642959e07	1671705758000000	1672310558000000	1735382558000000	1829990558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
392	\\xa3339f1ab6bebc4f9c12d2c854bc3bfff4b5b70973b1e4d8a5ba806669ae4b0ab6369f526b40661d394e8b93358f95410ddabbee5c1e086a573f5f4b3814b942	1	0	\\x000000010000000000800003befc93e4e55981a7751e0f51db19a709a21530c479bcc1612c62eee0fb06abe608564516180d1533913f7c11323350f19fcb52358c738a6408d7d245b0bc04c0ec615306765d9da500bb182ae4337fac5b57c3a0a5b5c1e81d9077e281ee5e21e17db60fb89e49dd40ff6bc2c32607f125c55985cd6acf89211e66a46078ba07010001	\\xac649b6f4af674c4c1a4e0aad3cf5c57dcd5e7c567afa510b8327b5d0dcec572abef3272ea124fbd000bc25ff34fb703b7cd31cca3f752e1b5e186d5c519ec08	1659615758000000	1660220558000000	1723292558000000	1817900558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xa7332711d13b78fb4570cf767ea67afb268e26192881e49b08eb9ce92fa7cab39cdddaf44e5addb79c2bc3ecf7b67e3b82ace64015f0faeda77adc28f46f71d9	1	0	\\x000000010000000000800003dc11727ef5c3704aec7e25bb73d29af28e11001af5ea29dee79b25dedf82e9ac96a26dfcf40e6245dc4e6a1a113cd162886a92a4f3cc558b15470af91f1eee5a32ae9dcdd2c21155da638a5473738c571a5c3b1eeaf19db069688b00781c2ec5112c90ba67d0b4268033f0311c073d7f5b997d064cfc5c066a943094e5d92831010001	\\x27930485a43ff48a416ec7a1250c4e62b4f1170bb586cf0a253aa1dd78d2302d105984ad9025c52820244b1c953e846797ec2daadcaaa69d05234242e138780f	1671705758000000	1672310558000000	1735382558000000	1829990558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xab63bcdff2db37187d69055e4d71335c0224bc47edb6641b84759fce5d9b397db5649652f4ec6af4685555d4052c5d3767fc115d68f06446fab79816f5f517fc	1	0	\\x000000010000000000800003ba4fe109c46bcaecf81e30c4a0f617acd2f4ff461c0d7e32063d82700e1769cb9a627341a8679a6cbc002be4c2d783d117530625214fc513818b0d6902ad2283a14efd95de7d3c484a263bd0f6579253ba21fb1753b7aa32609ca86ae6277ff4ca971de4ae11909dd52a369588e83cd2254319e6949ade6ab897184ed8a17aa9010001	\\x9ed488dfce45fa2772ee948c39e78e37555645b0713d28afd635d334f6935cfb58ca57ee5a44f03d463da4843355081a4cb8b30d39b897303388067f1490f408	1657197758000000	1657802558000000	1720874558000000	1815482558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xba8f5055fd500109f5c28b324da842862235f3b3607ff6c65588de3d935a70ba8ed60bdccc81a3bd079c4956475aef0cee131076f0e64c9da0ab705f2bd2c043	1	0	\\x000000010000000000800003dfe238c1280810b5084d2c4ba7fbe3fba0a73d46450cd29a6cc84fcf8f605d5d65d25b5320b11f6cf10dc14f8893ed90c3cccdd5b8c57656c977376b56cb9fcf5787c972f321e671e246f710636a5290c661b70a7e3feb05d81f3467cf7cbb5bebed3cb80a9d578aae1eed7c7df56fb2a2178a1341f1341cbe38f1b97332e965010001	\\xa7e25409eca8e5af9514b1fed463847caf5d3d2975ba7f84d97efdbff316af921f12ce10d5d8d1a0da3b0d4ec555538325fcbfec56baeaad41c3e432cdf48008	1672914758000000	1673519558000000	1736591558000000	1831199558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
396	\\xbc439500d4de593cb5406d5e7e9efdf5909ff398e7959e425305d2e405d8cc2df57cba27a2b7212ed93b7479728a0955d9a5f69e68279ee3d5cb78f5f67aecb3	1	0	\\x000000010000000000800003c4792ae4e166df094926b109be1935e4ba9403b0dbe5c876291210fd9e6665c55124c92781e146d7e2dc4b25177fc913ff62415c843192e75de46c1b6a06ee9b3899d4c8002b7b51dcddd1a3acae0c6dc8cb46325341b5af23f9e2acbdd04b4a2d31c3a9993361d3d8edaf68e563c2b85dbd3ddbb02f5d422a795e0b7031555b010001	\\xe8d2ca0b397319ca39633844951ca55d30768a1453351448a48f104ff62dd3601a35275339c0c579f75240fe8ffc22217d5c62b0df8c3d7a6176d8492447880a	1678959758000000	1679564558000000	1742636558000000	1837244558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
397	\\xbd77d6bc1253c25b963ad68c7a0bd26e4686a58827a0fe0458ad9a5fb90b9e59804bdfba96e1bc9dfb3b75b5c1188da1539b3bdc6b7fefd00b3b5720523db4da	1	0	\\x000000010000000000800003c89ee7b78dc513a8371ec3851f9a968c75ab519ec42fa9d5e184a61724ada14dcb4d4cf2c2f214be8cb2a3fe04ec23466e98e62085db7048bfb58430e4e23bb63a389fdf026ddf71e06a0b1757f404f1dd90ba3fb563172ffb4fe22c7723f4df03028c547c91faaac3463378efcb5e342226d0d04e1672a1c16464050501523b010001	\\x7ccc47bc169223bef5af38f148997e9f252d6d651c3806f7817026da883850e4edaa440c5f5160f9e1f60c7a719a9f03ffe9e98dae446127569cb210e5b8c109	1666869758000000	1667474558000000	1730546558000000	1825154558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xbea3e9a60ddb742ea6bc4fc26fa04e5cf8929572e29d1cb2907fd67bed3fbc537d7a16a964e528471210e69918721a28ff58a3b94ecaf80bb7c583dc3af1a198	1	0	\\x000000010000000000800003ccc4db3c8c46af2d24a0b339b80a43a70a3d5093c37109b47182b504bdb2d595d6b7be495318b831bee7334a9e249eff4ccf842b1f12baece4496368400a16907bc343433b2184e10eee6bcc87214bd0cbe91ac29d45d5abdd7c2a70b590568c3dcabf9625e4e9c03dc33d884e2891a259a9a17e2a33215d6cd1a7dd067e539b010001	\\x31b550adb60340759a715706d61d3e0d0bf1cb7dad6f6ec233c72a050b7ca20e1299c23d3d8b91c4749d9be5eba50b00003fa57503035c5f7ef6774a93a1080d	1648130258000000	1648735058000000	1711807058000000	1806415058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xc0e3638f9bcce917d3a211f93e58279c61522083148cebb97a1bac2611759ed06824184269281981d49d4fcba5f36a1ad1f53bb9f16fcd98512b1874598fa93e	1	0	\\x000000010000000000800003b48682b534c20d3fe171b75f5550de5cbb385a983414871c2ccc3305516e38f5b0c4ad8589a8b29da9bbfbc30e098be991507668b872df325316f10448c6ea137529d31db9e7f1f454d405d5c368609a65fbe40acab9c1ef5de602dad5a1ded323478e588d2be76878fbb93c58a95a42f501f393cfba39976d53c103434602ab010001	\\xe56ab60cd6724bfaf37148e5e8f9ec9da8fe25dad758abb6395b7ca80df7679ef855f1bc6470c5439596c924b3b55a36682531b3b7b991effdba154b5a4faa09	1648734758000000	1649339558000000	1712411558000000	1807019558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
400	\\xc3f387472690b54ae82df9eaf0cbc3317de189a6ece46f0aef6c444f9d259471a48257d30158a1c928d85fc83dcad73ce647a79e5b3b2e7c21a9e2fa60c6a1a8	1	0	\\x0000000100000000008000039a86fff7ad8af23a8e4f14f02e46ffd9cdb479562b76bd3f980d1c4dea0a58eac46460ad1afe63598b2b50ed3f9c545b9c627e8b635f07a0dddc025485df68ba80331bf5519740fa21d42294a7d3a3be65192f6d26cf74f26755e179bddae989a8cb56802c38bd9ffc87684498c546ad10f941336903f7340bb250fb854de6b5010001	\\x6aca6eaac8a6acb1462b3ebe9144debfc22fb817ba2e002c54df9690a659d55018660b225e02ed52981a431e42a026539041fe50e0e9ac417aa55cadb2d06708	1664451758000000	1665056558000000	1728128558000000	1822736558000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xc477540dabc845a63f68c51b7fa02c05bcbbe3263f5d4494aeb1dcf9a1f32ee58ecfd54ef56935621b637672fb53d14b5f98d3791cfebd947e74434e880eb885	1	0	\\x000000010000000000800003ce42cadbfc60a33148088d05ee26731c7ade0e1c6d30c937954a55187d3a6d8067d21bfe1cd55a44ead58ad19c8de356a1548a0f882261cf15f9e995085bd5bca79685e9a2ea52f2e984d6a655f302cfe920d9b0af77f3102ff82ba5265eec3965159477a48141524ea637147034125bae8f99885a22c5d9648495cdfe6312c3010001	\\xb775b86039a7601d2808101cb981c24789aff28409dde504aa89e72dd09a606f5ee727e05ece6714cce6eea3e2ecb9da069e6759fc13d38b66e5625da59e550b	1664451758000000	1665056558000000	1728128558000000	1822736558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
402	\\xc5b3db41b6634395c3fa9659557461527def525a52a424ddaac1a9b74249e4ca9d01668ba1ffa3c0d438c8989f26b4146fdaa2a9a34cdb2dbc8c70f659941a1a	1	0	\\x000000010000000000800003ee3ba63cd2316fa886707c6ef8529ea09f1037f51582eeec25587eb0cb75e0188b4ec20822ccfdf1c40e7d8cbee7e5f03adf732e4a5c1321dc208bdff2127d8a49db50c4a2c84672aeceb4d12b37a2b7ff14faee1814c76cd0e77152a462738f884523177cdbac1d2fa863da18eb807058e1c13d91271839a83a5aa3f2527e8d010001	\\xb73b393ecf6d0cf5176c6e79a77eb47b8c247c67667028739eebdf6f8ee963fa7ffc664164aae1dfb5bd3d19534062515ef27dd1fcde761acf0a9efcb8c9c70e	1647525758000000	1648130558000000	1711202558000000	1805810558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xc6bf5d27af6f8643fd94ba3e967ce8f202d9981ad4e962601eeeac2d6e836ebdec2a45c5e6403ae6f18fe130cf10d846fdaadd53e022d6bbc1ba133c22573eb2	1	0	\\x000000010000000000800003ae06524f39600b19ff852645685ecae36216eb17418685172e39d956722b70640bee15d68f6f2f76573a5f17671b576ab09e07c30d9faf17d90466eb617d0876d1e5d5cd856273fe95ed6fd93cf2c3d6675b43a58eb139bfb4d88b34770d01916e6c8113ea4d7ffb3c4d453616949abe0b1cb09dd5cf060418f5eac5871238c7010001	\\x4ee885a2ea5e7025f5cb82231ad5dafbc64114ff253da2e76b169234244aab1acfb1cb0ef702e2be4556a0defbec2bbd373a5af34c492ca987da764f8296c506	1659615758000000	1660220558000000	1723292558000000	1817900558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
404	\\xc6bf4e9bea03f96c15fdf41541141f32e378c25db63bd8a339184f229f2c9b8195363d50316e7f6f9c8a49a3905fdbaa5e68384c6f3d2bc15a6ba391c688488d	1	0	\\x000000010000000000800003ad86b826171f2128df71279a841b6a15e61dda8bc122b9d937f554c125752ca2175547de9f402d72a35eae7c75788bb8819516db7f4ef54ab46a77c82dd9f4d4039b4107a5cbd35dcdaa0390dd5deb62a3a03ebb4706c82d5086d003842a33f7b9ab0090d3c2513786627481d392a645ae01b161614b37ccde9a02ac922e282d010001	\\xd67978b972505bc80fd78fa2d7a28ee8b04b689c9ebe06bbdb9130be08e9b9c0807571e9fe7a41048f1fbd975fd74bbcd23cf68179d3b34405b4bacb2f5be305	1653570758000000	1654175558000000	1717247558000000	1811855558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
405	\\xc8df20a4a81b4c2648810fbfeed14857fb181975e72541f5bfb9ec5392919806b16e32f5c06d9dfbed274ab845136502969f31eeec2be0e2b0332440d5c58811	1	0	\\x000000010000000000800003c3f1cbf886a4e6f6fa6430daeb12756cf314e8d8aaf0014b1a00927e5f5fce63738cf0985277b875d5adbdb2a2f9e45fe75a70af7646807c58da491d1a13dc8dd1885a39fdf2c2ca5a717da19b200f72b1e5fae7ec8479e3273112a8ef975611906e9eaeea00b2c3dac5b228ef19cbb94442b84c4c3d1fcd3eccb8f713790887010001	\\x976e771ce7367ff18c07ef4ad0d601ed95a7511b640eed1b4cf4bcde01a7e706f27b27c4f7475a3d4e0117b8be855ba432f8bcbcf13ebb935d8ca9c2ad479006	1657802258000000	1658407058000000	1721479058000000	1816087058000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
406	\\xcd9fc2ed6a4369dede8e1d0faaf405ef9ea95637852d62951961af45fdc08e3c8b2ef0ad47a6c9b0e23bbd43659d0e573b26dcc0be847d5842b779df311bc965	1	0	\\x000000010000000000800003ca006b9ebdf605b683bea83a4f93ea9d51495f3dacdc3e7d0829936c1544f2b26c7fa9b85c2c34ff0abccf1394215f6fd92749bbcac9568c1e20a124af705ffcb04218ca0033226e0f5be320bdfdd686d8451133b9e49ff606ef75e2ea9c7ab4e59b6a4ba2a7e0d32472729f8d1018ee052ccf00eb02bf118444f90ded98579b010001	\\x42e632c8fb12adb5bf16aabf4cc3ca150a9aa9a67a2c88b90acfe9d5baae939600c6ff1aa73b36cb12d5be06e75258becf281c2f9f6fecddc382375e308f320c	1678959758000000	1679564558000000	1742636558000000	1837244558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xcd5bcbddd88f1bb0efd79bc6ab37fdf5d4e53f9997cc376542e9375be32888874ecd55de443e8442c1cda3965d20004d71e47f2e83141c6c0acb784104003790	1	0	\\x000000010000000000800003d8f2b93ef534d4a995d211523119614726f0ad4ad5273f4ee833ad944843ef92ad5f956149ae337ac7e642101a207c45d4e7577c5fd448b0f4a7bb7848544c98d93b57d4f18416586911574a6194abc57f8cb9eba53e5fefbc71193e3b374cf62b14e967014df38ff1c0533e035468ff8ad8e11baeb5a301044327c396004e63010001	\\x530eed1eebfc2103c4bcf4900ff51baec37c42001dda00fbde78e1c968738ae6d916927b4607ba3889698313282fead29a06c09411ab1cb29ed6c98f489e9a0b	1662033758000000	1662638558000000	1725710558000000	1820318558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
408	\\xd85f85b880456dd9c390948262db85d8963504d3032b3bb8a411994b4d5b1564e105e7d6b148efa1947ca39cbe06506a27006501ee1d0c003fe6f56eda8707be	1	0	\\x000000010000000000800003b69096b5c9287072da5eac5c27f79efbb8c71f218ee7c611ead503540bbc7df9eb4214c0438ed08d6b338e0f34ecb1b8fceb8c756cdb0814846f7998b68dd13e6539bafcfe015486607e7d35217fe16374c67a19d87b47ac980ddeb1be22d6311455a5bc29b6e7e6423697a2ecf70f7a022f32f389d3912370ac95f98825e6c7010001	\\xca521682f7ff81ebebf1328fb0746c69a3d8831e27a0a96e341abfae9a823f418f6d54214b7a9f7526e38935a050d157c20ee97ccc2a4bac26c2a21c704c8f02	1658406758000000	1659011558000000	1722083558000000	1816691558000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
409	\\xd96bb59e50d34557610f750d2cbfa88a12011d667021e5480a0a30e49f4fca97039ff03a2a260c4035b23e7ade274d8921cc6ee3fe4b064b7e4957328a1317be	1	0	\\x000000010000000000800003d11c5b11af094a220c21fe4bf31b02493a4263b4a32c0ff28e52a0f63c520ff33af624d04484b94639ee71adc33956f50a532a1e38ed43cabf39a07ae1148627c06caed758f1a1a8623db81da607ccc52df94c6be68a51af384a30f31b902f511dd06a708c52e14221c2d9187310965883ba3378f64d60ba154a7a615b65cb03010001	\\xaf1245a7756a01ffb3a41469650fe2a1f322e6bfa65ef9ce041948734ea0db1044cb9602d7d187ce360fa833e84e6601f582b66c5e722e93794ada2bf2985f01	1665660758000000	1666265558000000	1729337558000000	1823945558000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xdcc370595961b34df5bf9d14cd9903f02b2969a2326d1d63e692d428fceaf18821ab4dd566e282259c2792fe4c92d684d40de978184132561d158c1311b61707	1	0	\\x000000010000000000800003bb0ae9dc125489072b3c4c4fffca422a883964ba78f70cfe4a893c140cf60b640440d8e0f18f979c24acc1b0d52a036fe5f7f87edc027b468f3e39152ec40c93fe6f5c84113520f0d7f2015d765e25828cd7981abb0d9c4ca8f46239bc1bf2ba4ab1631c85ac38cadd2b6969d54a472e1bdb7a8a636f9af36894aa35a64563b1010001	\\x8d3dff69a41d57f2f0bb06a7384675228870c87a7f7aed75c2dd09fea458a757b6acf8223040b34f050f95eb7fc7808be9a05d3808f14e570a0f895cc57f4900	1652361758000000	1652966558000000	1716038558000000	1810646558000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
411	\\xe1d3f1e19b84c9794508569f77f812090d367e230ff8dfbd844bbfdc4146e1035c14d58f8c8b3a165f94d57a7bae01955eefc906bb8b6dd039f6328488f9c596	1	0	\\x000000010000000000800003b0350f860f3c433b52a67b4e75d1c1c5776bcca82aebc8aef41493ede4b15ce838a08fc6ad18fe3402abf335c7ca0ae8993d85c5a8ef2e270ac7e7d7717b167c9c2f247e9df121e27fe0a768503d53e821562021233c19efb24dc88d8abf6455d2924d613d0249d9dbde37d76411e49a35c9f0ebe53a59a86042e8fbc515c6d9010001	\\xd4b04c778cda08d4e0bbb5e1f2553d415369d15a0db4a2a78b572173b8c6259b8008578fb06698f7e388b9b7a4fb439d8f1aeb3224706cfe5407064694bffe0d	1663847258000000	1664452058000000	1727524058000000	1822132058000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
412	\\xe227e0cea4a3ebb5f4aaa7a639558b33a26b7e7eac82a51e953a16211a49ecff3e0697371a17c56e254a84b8e80ebe1c6e8a4ad8de973b9b4d278a81448e57a3	1	0	\\x000000010000000000800003e259628b905ca8d79a7b88f6e5449051497772dad2f6d8394e09a183e26436ba9f4509b067f6f340628da8c9b78e5530200a60b902dad24948f0db54036fd9c6833c4eae0162d72dff80a7f38131bb0ec45a84435fd694f8d4f05e245095e70f0570f580754b35a2e5fb02580572191fc20cae818ee7713ddb8c8403c2da871b010001	\\x06717ce042505a3d21b05cd2a9e824e65738799141415e24d6488706331af512d5ec39421161b44909d9ea0d46ce7bee549ce464f56d87997d32c6300cacea03	1657197758000000	1657802558000000	1720874558000000	1815482558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xe48f1bc0346010cf0cd019be174b1df4254623074a26b966f8313f216d6cbbb82603f739374acd9250cb853499bc3804d89d1717e3bf3610ed6766b7d60520ab	1	0	\\x000000010000000000800003ce3ab7fdb6db4da47a4bab1b60b2ba20f1168c25881aed73f08b3254d5029d33ed5610da0a1098eaca5ba8b894bb6b03be6695d881935f58923cca29945169cc4ecc28f9c977b0db8379b6242da0903c19e9778cd13b4c1aaf95fa8d6ddd5fd75ee98c980d079b87b77e78d029c826a493a14135ae746344b9445ecf31a548db010001	\\xac40df3893212c166c38869dc1161ccd9e82719950fe1735e5e996dcbd9bc2445f5b106d65d5e3341385227f9538c2a24840a5dc1b8ac2114ff33ec1e0550404	1670496758000000	1671101558000000	1734173558000000	1828781558000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xe6d3d725576a2b56598bc1a3da3c045af461b4b0f025a46580e9317896f5c7c0cb85e49af80c552cecea46d2e07377f17c70fca4b159cee6feca7c81c8b0d4d2	1	0	\\x000000010000000000800003b50c30729c08039df1db42ccbd645ac3e3b04262c8188bdde1eb0532537b85351d1b56e4c951b1c21c046d479d74cc7f05ab430e5630ef30cd142b0b0f767242f7c28a3b94d6c979cc0fa6ab0d3b918de739660b35e8ebad1764dac9d9cdee336d1eec7e6b38ff58980ddb1017c773804c8353cbe08ff9fbd112225ed68d2359010001	\\xc9d0cd67ddc3b7c7de8b37746fdec780aa58fb926e4642e26fd4a2d4270ca67befe23e75e8c848e8ec3ce0cb64a0b9e1c6c35c22869340eebbdb481be0cc0806	1665056258000000	1665661058000000	1728733058000000	1823341058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
415	\\xe9b72d6bceba0aff6824414bd1f0c3fa00aa85c9e032428936889da67097ff9a1d18874473edace086671bd47f9458f3ffa60daaca8c7dfd1246cfe50b18d850	1	0	\\x000000010000000000800003d12f377bd0b27aaf12c82c38e1f10bebc785a7fb3f66866666d96acf48164df29328a6df55b05802ba5a356cac1343548460bac60eeeb924d89b14c3ce230658651e3171bd914bbc17d22890e3eff48419064e7780b39723b09935fd99714194970897a50e55185fd01e595b3dddbc1f6f04919d2d88dab87b3c17d3b4d9e18f010001	\\xefaccfce54aa82e38721bc1a59a55c6f19fdcc214c0ceee0a569959edf10ff09aff20b34fba10753a27d6e33ceff20ed22e786ff273eb31ca433241367d1090d	1660824758000000	1661429558000000	1724501558000000	1819109558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
416	\\xef237f88793508ec1abfe0d49a47ea0c0fffbe72af0ad8a968f5453866ae9ef6c5759453f22d5e4a9253f9506455c41200a28b83f06ec1472c84808a29572518	1	0	\\x000000010000000000800003defdfbe7244a7a6fb4aeae320f3c77cc79a4646440288fa40965a78e069eedb2b87da94a72a81734cef9f0b4b643cc0b58d93616ec497faec3bf5c53c867a935db3c5d4eadcfd710f62cbe236ee77cf5e6ea707f458319f29b826b1f353627727c94c2532b38edbc82cfc0f3f70f53bac9abd1b52b4b1b2075b770d708f9fd73010001	\\xaa3531d10557670c5355a4544478f8fae262882f82bba223f337194ddd9b3361e236dccbbdf42a1fff258038b867e9b26c1472ac2ee9fb54d8a4e9f8dd611908	1650548258000000	1651153058000000	1714225058000000	1808833058000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xf3c339bb7bda9b4b89fde58368bb5e21da56517a8c91434eb35eeb87f9d5e13fa41728a254786824cde021dc0791e301ffe2eeac8879697d7d914804a1d58c9c	1	0	\\x000000010000000000800003c1a12962b73e1287eb0a07ae19165221ed09630eb9cf36403651e53bfb20d2aeefd7c9840cc169c341390772105567eb8328ad517546d14a93bcae748b49e9d50728584134216d8238bfd2754c3975504f898dd437a04e23151cff988bdce27157a179f6bcfd33869a013565abb96cbc04d0eee33245d9c5307748af395367fb010001	\\xa2439db86afe70bf7702da040d75d4e8c832b558850c7e46e3c85b49c0c77b5ddf81bb434da3be0f53e594ec66898b8f9f49ba0e090a043c181612a07506de0f	1663847258000000	1664452058000000	1727524058000000	1822132058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xf337aeccaaef714b26c4deebffb57486bc788483a29d7b6a1c9b6f7b327f8dc24b39c42718406e101e98bdddec37a0acfa9a0392057efbe2d580d8b729f9e603	1	0	\\x000000010000000000800003b4879668b94c24a8593389823f4e43b9745fb54032b10c4fa3841d212e930bdc61b2bcb70cc72d12680a64e161babe96d36432fefbb7f53e26a62f5204be18bed706b99a1f84265beb8f6eced19d834a73c92113c4e1cd9005f037acf991bb31e8182e094f4599f8eeea5aaa42ee320ae6eeed456bc9f09e335cf93cb0a839f3010001	\\x5d46a8196d087a0b956ac2cb04ff85adbbac8b254d63859e6bdbf975939c67d33f386b167553fd37f1ca0a1e498fb1116f61600ee26db8000300b8ae208ee00d	1652361758000000	1652966558000000	1716038558000000	1810646558000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
419	\\xf5fbe471323ed10c0c7623e21bcb246dc68187626c111c8f0987bbcba90ce82bded55cdf342b912f8e89ab3720412d4934726e562323346e5b443bb0e99d3132	1	0	\\x000000010000000000800003b5556868bbc4709e1a9c9cb34f4e8a9935b5c997d3c2652046cd2e80ccad66ce3637a589d5f8a66ee026355b6b5bdeb02cdc962c4833502abb4446335954e791061788766ae9579ad4f5e4812f54e9580f2854d297e791736ad9e885ccab09862e3e286c76b4220eb589a8ed45f6ef7fc089014d6238e52785035080d42c7221010001	\\x437367f4fc22c21b72ea122801b4ad5841a5c221057a709b8804a5fb10457a7b3900ce0551f29a5f244e4f9b680fa91c88566da35076841f3819ea66c5c7bc0c	1667474258000000	1668079058000000	1731151058000000	1825759058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
420	\\xf6a746cc5261790df15bdf0b6e9a307fe50cb32fe96cfbbc06c9aecdb8508990681f5d301e6b55c1ea4c4f0db9a01a2189146a16c2d8643910a6bcfa674e4ec6	1	0	\\x000000010000000000800003e417cb88bf16d3471f0537ea1090cf56e26022e2cbce4545787c2d4b6a21efb97eb9c90408927d91ab83deb96e3ebf2eddf6bb2f8cdb67c2c1929175c73f0801b2e1b1bb17e0c1fd0dfb028216f4cc986d9334fbcf9c23783d07132a67a70b49b004b5ab755c900345f8ca6cba9d788a30bbbe64017a65d2cb78ba03ee6789df010001	\\x7b72888a9dd4cee180218a7064e9aeccefa6da46698523070782e7e46534bc1df494deeffe9007ce937d59e63b27ffa1df69eb1cd11a72194f639211566c1c09	1652966258000000	1653571058000000	1716643058000000	1811251058000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf767f3fa74de1b1cd7a9518ee8eaca6329ed48643ff8541fb85559cf3b733156eb9507ce3fee84ff5de231ca7097bfe69cbec25c4e04eabf895ebe8f1078ae22	1	0	\\x000000010000000000800003d6da92ee0c5a0748bda3bf4721186de786025f80db06b0de6437a1bb063a05420a0649c6a79709f4e7fd8514da39f76162a6afefa4abe9a021b2227cea3d1902ceb668da00f38a87585ca9fd1eba9c8407792bec7c654e2886f21a3b5ec197704bce76314b315ead2b459529a1f0bfd82771ca1caeaef90bbbe081c46b6e05e1010001	\\xd2015d31e5d08ebfe725053aecca179940a5c9a09f0e7632bc5baa1d5cf6cdcb228a299face52e4405c80866870d5dc7c20950320990b37d499c9bcc01c0840d	1653570758000000	1654175558000000	1717247558000000	1811855558000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfd2b75cf0be8b416b5eb11a354b0de480422bb6ca22e000acebaee4a668edd37c37dac17a318b572a20e5bed154eb24c70f1d285f8030b4e4749f57d353a18a4	1	0	\\x000000010000000000800003beeb6c2ff47dd5e9bb817284cec675c28c2312dd309abd4b6e66bd829e78f3f45aa2f5e479f0c7602c6aad7dde69206e2416223a36955361a01c7d4ee78c72a4d30ee92b8ca7669ec0c17b8ba6ef93746b00b9dd35d84706997b8a9ec98ee6b32144eba80c3aabe0aaa11d5a6789df7317d7ac2a8bb8b5ccda6ab0bc4d7d6e61010001	\\x15160692b2c84052a6accec0bd966dc8f1415ff03470b6284fe9bb36a5dc94a5c80ac1e8d9cbadee258c4ef5039695c47192e4a3908bbf5a500df69653c42b06	1668683258000000	1669288058000000	1732360058000000	1826968058000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
423	\\xfd2fc35141235ee9f33718a5cc16e979632c0884a0d5df5649fa7ea0d9ec4b42c9e168c32767e7baca723fa926a978bbf5199ce718530390ad8747904e916759	1	0	\\x000000010000000000800003c5846b2c995957d55bf089d9093e234473326594c29aec6d0e0234890e0829b20028f9ae2821309d0467161c1afcf4db883eb6dc0fb7fb7c8cfd4c04d6b0f4c7b46607cd728bb259f538d9f8a2a866ce88281b5ecec074f1c4f939770cab746a77c7a9ad9040e4be891900a26ec4f6126b6f42f55838276a4ec1dd540197be7b010001	\\x9c0777116fe621d7793bd7b251c3158a0e56453af088c4062480d444fd2b83852a6ebc6d35c1215606764b3c19109b36a6ba953902951241deb66a6c7d7a520a	1655384258000000	1655989058000000	1719061058000000	1813669058000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
424	\\xfe536b47af61c51bba58a269b33c1719bbf3864d0621610f53da41cc32016f5e3d32b2a649a434de84210e3fe676292cea0f5b60a85d2d4cc257770da135b13e	1	0	\\x000000010000000000800003aef691248bb61b5ba69aba359b85791bda70b68b6099a8f0de3752128204b20d3921919939ff480c29a462be9dfbdd50bda07af6bcc80f9faa3865a39a366ffb3744e3d86b794af1ef15dbf9ff748c42d11aafc232f063fa3fe337e68fe03263ad969e7681406541b243b4b366446fd2280b3538c36e25a836e060ef178b46b5010001	\\x5df4fdb7130f88af0c79135dca2d0267a7c54ffa6428b4382b684a387533961f91a13a6f7fd97ab786fc3438b49f7ce84c870eb114c9084bc3045f58df370206	1676541758000000	1677146558000000	1740218558000000	1834826558000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	1	\\x246c6aa2951113ae467852bf6db313c29f3f5c2216ba104c2c58fa50ab1e19175687cf2b80cce5b1edd9ff8a7a2778476efd50fd34cb8677885c3dc18be34064	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xe19b52d999fd2f369f35b97aa3be29c118596227a44df3c27b77e104a312e0736d95496798b62e336676ef1402806533d703c1dd26ffe574324b290784b16d98	1647525790000000	1647526688000000	1647526688000000	0	98000000	\\x88cdf331f8e58dba584e5d683963a90b60609a3c171990f18abdf2f94ed55431	\\xd055aa7bcd760aed4f491216e9b02574624a20cfc375b7669754e0428ad86828	\\xe53f0598bb64e977d999ba43f56d542aac3f184e29f4a8faffaba3e405104f57c00bc711c936e496e0201efa7cea8a6f90e05d30a7446b3bf50844b5238b6f09	\\x02ce09f924810486ffddd0e2ba6d8d9992d0bcfb67381b8d0aa970bcf45671b5	\\x0000000000000000000000000000000064dbba88da7f0000000000000000000000000000000000002ff741622956000030b05789fe7f00004000000000000000
\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	2	\\xcb9c3863383edbb37eb07f6be844bd70e6592d4efdee2d9763cc016177dbf67684adb8192f685f13b937284346a45cb869d5ad16054a321bb8a644685ac81821	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xe19b52d999fd2f369f35b97aa3be29c118596227a44df3c27b77e104a312e0736d95496798b62e336676ef1402806533d703c1dd26ffe574324b290784b16d98	1648130625000000	1647526721000000	1647526721000000	0	0	\\x01dffa7fc179fccb8b8717b67e307ba7fd913a5f2ddb4be4113f5d3ee49630e4	\\xd055aa7bcd760aed4f491216e9b02574624a20cfc375b7669754e0428ad86828	\\xb081dd6e01f252b3fb69b94061755de5e023e3479cd93bebe092501615d4178e70667aa8c1cb762914b5e0f1b92ce36a8f49a69f0c6e7f37f5a18b4e11da0306	\\x02ce09f924810486ffddd0e2ba6d8d9992d0bcfb67381b8d0aa970bcf45671b5	\\xffffffffffffffff000000000000000064dbba88da7f0000000000000000000000000000000000002ff741622956000030b05789fe7f00004000000000000000
\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	3	\\xcb9c3863383edbb37eb07f6be844bd70e6592d4efdee2d9763cc016177dbf67684adb8192f685f13b937284346a45cb869d5ad16054a321bb8a644685ac81821	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xe19b52d999fd2f369f35b97aa3be29c118596227a44df3c27b77e104a312e0736d95496798b62e336676ef1402806533d703c1dd26ffe574324b290784b16d98	1648130625000000	1647526721000000	1647526721000000	0	0	\\x04ae9e22c92505bd0f95e045f4e209c914437dc5b13819bf4c8fb049b0069e2f	\\xd055aa7bcd760aed4f491216e9b02574624a20cfc375b7669754e0428ad86828	\\x1ccd2444d23476b15fc2a50a8ec99795460c66a407c3c442911fd59614e6c104507a7d46523e489f0189ef0af664f10a6171914f85e684fe150da2a74946870c	\\x02ce09f924810486ffddd0e2ba6d8d9992d0bcfb67381b8d0aa970bcf45671b5	\\xffffffffffffffff000000000000000064dbba88da7f0000000000000000000000000000000000002ff741622956000030b05789fe7f00004000000000000000
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	138777821	2	1	0	1647525788000000	1647525790000000	1647526688000000	1647526688000000	\\xd055aa7bcd760aed4f491216e9b02574624a20cfc375b7669754e0428ad86828	\\x246c6aa2951113ae467852bf6db313c29f3f5c2216ba104c2c58fa50ab1e19175687cf2b80cce5b1edd9ff8a7a2778476efd50fd34cb8677885c3dc18be34064	\\xd89c5f65ae4c03fe457250232537c35138cdc121687d6da093555c7e6960d9c76e4b3b7650f041bae4ac93605a2a97f6a679cb5e50491b4c8d4ea28a8976c802	\\x643e7421520d931729bd0f69acb30bed	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	138777821	13	0	1000000	1647525821000000	1648130625000000	1647526721000000	1647526721000000	\\xd055aa7bcd760aed4f491216e9b02574624a20cfc375b7669754e0428ad86828	\\xcb9c3863383edbb37eb07f6be844bd70e6592d4efdee2d9763cc016177dbf67684adb8192f685f13b937284346a45cb869d5ad16054a321bb8a644685ac81821	\\x640d3fd3e547f6e43df22008d0d7cff7ace0171301171ed3213d42b98ca0c89cfac5a8d7a3d133daf61c94c907c24d2cc19c093a0269ac1fb6869d723cc47308	\\x643e7421520d931729bd0f69acb30bed	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	138777821	14	0	1000000	1647525821000000	1648130625000000	1647526721000000	1647526721000000	\\xd055aa7bcd760aed4f491216e9b02574624a20cfc375b7669754e0428ad86828	\\xcb9c3863383edbb37eb07f6be844bd70e6592d4efdee2d9763cc016177dbf67684adb8192f685f13b937284346a45cb869d5ad16054a321bb8a644685ac81821	\\x5104a0e8f4e8ae1feee839b582bad1c10119073108ae97b77ee188646065dc33439e602552a01512c430ceb68b3286b8e80ff3aad510286897fe058c31234505	\\x643e7421520d931729bd0f69acb30bed	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
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
1	contenttypes	0001_initial	2022-03-17 15:02:38.653144+01
2	auth	0001_initial	2022-03-17 15:02:38.813598+01
3	app	0001_initial	2022-03-17 15:02:38.941206+01
4	contenttypes	0002_remove_content_type_name	2022-03-17 15:02:38.954349+01
5	auth	0002_alter_permission_name_max_length	2022-03-17 15:02:38.963692+01
6	auth	0003_alter_user_email_max_length	2022-03-17 15:02:38.972345+01
7	auth	0004_alter_user_username_opts	2022-03-17 15:02:38.981217+01
8	auth	0005_alter_user_last_login_null	2022-03-17 15:02:38.989178+01
9	auth	0006_require_contenttypes_0002	2022-03-17 15:02:38.992343+01
10	auth	0007_alter_validators_add_error_messages	2022-03-17 15:02:38.99963+01
11	auth	0008_alter_user_username_max_length	2022-03-17 15:02:39.014636+01
12	auth	0009_alter_user_last_name_max_length	2022-03-17 15:02:39.022441+01
13	auth	0010_alter_group_name_max_length	2022-03-17 15:02:39.03217+01
14	auth	0011_update_proxy_permissions	2022-03-17 15:02:39.04085+01
15	auth	0012_alter_user_first_name_max_length	2022-03-17 15:02:39.048749+01
16	sessions	0001_initial	2022-03-17 15:02:39.081717+01
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
1	\\x02ce09f924810486ffddd0e2ba6d8d9992d0bcfb67381b8d0aa970bcf45671b5	\\xf3344d69c11a7ffbabc1475d78e3788991af95c5e45c0cec3d6cffdb145bc88c8add5758d8634f56f17f3b8d9d82ad62e12b9495454d348bfae5c6aa96539f0f	1647525758000000	1654783358000000	1657202558000000
2	\\x0a665af5ceb6f18f76725f3c4aa710ab98e1929af394c647de6d5412080dbdcc	\\xd6345816fde8ddd7b006bf86fe433f940de4c4b252cb88ca4c37ef2b68602f840779ca1a9bfeb590d5a66acbb2a894f16cb99e1ab2b192d277f10536cfab3303	1676554958000000	1683812558000000	1686231758000000
3	\\x8ccfadc60450eadab394c68fae5f8fd58226971a9c0857ac0a799adfe3dd7775	\\x5b98aa1d79bae97ca3eba284a8214c5d8c158d5cec87ed4182f212279b60400dc5eaaf942fdf12217ca051c966fe0e2fac237bb02d0bf0092a07f2d0e8993b0d	1654783058000000	1662040658000000	1664459858000000
4	\\xd4dbd3e1b72489a2a477ece5dd7b48e2efbad6d822e668377c3e78252401ff77	\\x94693c06ea0374d1bc011fd090d49ac5b834cb4f941b9f4190ad7a6b217cc67438a5c49eb94bc5dda669d7917253ec7d8ea453b6bca93d62e3a18f3ef379d702	1662040358000000	1669297958000000	1671717158000000
5	\\x96e1c99b4741d3cc52798e525df3a6822a0909c1acebe48b8738166226c0a12d	\\x1cb0feb201eaab65f176c8bc0382ba679ffe7ad2dc7a92bd88f39e9bad29945ef89e52d147a5148ecf46bd2606149761eaabfec1175b8530f1d8d7d494ca9f0a	1669297658000000	1676555258000000	1678974458000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x4efa8e289c35f1ec669840393faffa07e26d107647b2bb3037fede5f8970a20d654cd52e2032fabb50ee2a68f85a090e1ebfbba02a8ab84223b5d4a05d8e8108
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	228	\\xe5de160eced84d256f781480ed2ff4daed86740fc259f995965fd51c18e92bbc	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000041f654a931dc1ce6101ec7c0aff6746caf235937aa7556ed5573a6cae1abb8e1fe658c354b56838947a5065b18fe407202b87c8bc9663bf8e955590dd26d2570c47569e52a238fc63182c40c8a3de762abc6c49aedabd047b6c18011a75d77f0840c0e01386edf1c0355953d58b6ae30384f5124a870638821c4f13f2f2cc06e	0	0
2	326	\\x88cdf331f8e58dba584e5d683963a90b60609a3c171990f18abdf2f94ed55431	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a82c671eabf281eb4ecafef0699876e1cc8ec1406c654a6f42e2b082104de77ed3c1631ee3bd48263f089f80064b3f158439ce9936b130f23e012368a75aa24c57369d80b39d22364594b682a9d625e9af283ee857c65804356dbdd5ded5976565b2b2a08beb5d2c02ddc8839edf3dc8f03ab82395d1b3b42396352e3b1bd273	0	0
11	398	\\xe442819acef8d1421fcba8e164af1f128a2f51e5b0b5e3346a7e18c084765c92	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000510d80542cd8d9216562172d335eecfd4a4c33ce91b5f713dbaf81850795a783bed9ae6edf2f8af7e2259cc4c1312ee535b3419e29cb3c1573e2fde270e5c2b325c5236e8e93e6eabe40078abd3a4c7d41c52c5022aaa8612f0ba35c2a82bae91b36f1b57deb2e03bacb8057523d8ebea862455e75e93ea68d9cd7c5f4392288	0	0
4	398	\\x20922c175b7599ac9dbb480a06a18b6f343f883d79ff6f65bb2cbbff28b12f48	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006e4d5f7ed93afec22bbc7f7af4228136772a41a0a63294b6d0920754b924024d951abac772880116ffae08470c823c5daaa6acf855f690cac78adba786a4417cfab1f143ee68bcd55922c9dd53eb9b704a4bb6667c42b29cfb2e5e475f4faf230b325f7537e56a082cc477e72dac9537aa983363e618f73e24150f00e787a604	0	0
5	398	\\xea3c5ba01c14479fcf90041e94c0ee3bccd6e55ca8c0b81b6d3428f49ba7aaf4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000002c7f7c2517e68f7bc693853c613f9849958a88099d57b0ea7627046a3f72b56c9815f2ade5d464cc0de949a0fe422af01aac213ddf3df34ecc0e264e3a84abc4bc8c271730ac8a1135472ebed8f0befbe92d0bc82d27733fa85b5e66b3d8bbb1d235d964fd969536c2f8481dec309f855c03d65a15f42537ca441f1f1327d0e	0	0
3	5	\\x4051aa40f39b5e52205f77d2ed9833c88efb037083d32d385f84053b28703be5	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000074cd018a42ccc7c95f0c2e26238ed0391c18cffdd6070353194b730949c79a3505dc14a4df47f97c8be5c62770c699e5cd2ad874e4b4c9d987089b670128ffc1b1f4c392b7fa2d7593c2cd1fef9c007870b947b61b23cf148212c6d1dd13077d0f13298d958983c1b2a9567224073dfad302e45cce82b5769f3155e4d2076f5e	0	1000000
6	398	\\x976bcf5f12a9686420179a83e43385324b389bf950185552ed4d75ee92486c39	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000233b50e7d34abda42ff335638cbdbdb8a9cfec3585114337ec9e44c7670cd35166c01eab3e05262f273b44f95d5458b10aa68b4cc8a7609edbac86965085555543cb56641deeaf90ffc85c57c45f9a1e546f162c0701018ad4f965caf1812286f287830dc159bf12cd99d4c56770662cc71af01bc088c6422c58e73e2a6a22fe	0	0
7	398	\\x5a4d37b03863064856d116e43680c29efdfb5f226cb13aed5a37cd911dda6063	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004d9a5f61374701764733f295f25b3d1c774e88da62890ed50db99ea5aac681da5fcb73fcc81f178bdf7be2d2d32da6bfa01b87ebbc01105bb61beaa5e66ddb7375e7a165cc2eddec71c9b39b61950833d8f472e90a2ad671939f3d53be33cc69e0780224b69f1683698ba99ad045932816c55f973fbb34828f0e3b5918b027ea	0	0
13	87	\\x01dffa7fc179fccb8b8717b67e307ba7fd913a5f2ddb4be4113f5d3ee49630e4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006c0136af4e18c5b674688bfccf7bdb95b4271a6a93209ca16143e558baa75f9a0338653a05559dad444cc1516d84f1baf704baa8a78978d99cc52d332b5f688c9255d5d89fa14e78c1f7518a735e2caaec0c50c09ffd3ba6620e518c1429cc2e5864e7077db0c57f912db8baa3a10f506b8689c9f33d3e74e6b8229c71f26ac5	0	0
8	398	\\x76421d09484a6aef4aecbf8e9f13068841edc8167b01dc4677587cce970c8ec8	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000508aad1f1bd26afeff361c82bfab81844afa199e0b3e77a61282e65cce64cad47ff9a9402fd6b0999c2f8ab5b9dbd405afb6d669f4d0f33b7020fb20b320ac0104d11f817e7616391b7706f47f652a4e806adfbd2fa049009d93ccfff2cac8e2e12656426168387ec279725014263646f2503e53fcd39e5b5b940ee28721fb44	0	0
9	398	\\xa1b2545f5acf834faadec7b64d6a5868b875ca8459b981e0a75dfa173c3178a0	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000077bdeeea8110ac73f2720f0d14c58e730e09ea1390f2c97b7da91db650bf872aa46de2f9f3e0a020b437b0fb65852efb6c1f2e2c8e3c16e9ce0a464544ffd4a5eb1aaaf557f938a72d4e72c8611e266aa393692d2507f35e6a759e4fcd12de78b35f7ea21f6d01fb3cdb551c8bfbb4f2c94d66ff2b858cda1a28afaa1ef90827	0	0
14	87	\\x04ae9e22c92505bd0f95e045f4e209c914437dc5b13819bf4c8fb049b0069e2f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003a6bd95b632be4e70ea4b9ebf1feea1067bd64997d1ca2e17e33b2fc7b84a9cbfcf87afbed8735a65e96d7fc2afc5ce19d0c79baa4a5bbb79597dbdee587a9346347a3252c59c6384747401a5f80c515f1cb84641e7241ccfabfc5d91f6f12e97a0e0143183c037ba975012a07df2249163c6409e1093676240a5ba17aa05b26	0	0
10	398	\\xb9b1810c65e99b230d09b347920b34364ffa5490662d8145323abb95b50df225	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b8f8e425a7a281293d95eb161fa96b15a3bda42776b422ee710e8cc3aa2cf3b695c59b934304ae4552a0c9898ed9a754f008df1d8fa9874d39aa76ec683ffeb7a7d295a7ce6e536390883b26de2c0fa9fa42bb60ea89265381df8140d5c5821751af90bf1224976dbaca383cd6c31009d5bca7b351771bad7a8796781cd075d3	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xe19b52d999fd2f369f35b97aa3be29c118596227a44df3c27b77e104a312e0736d95496798b62e336676ef1402806533d703c1dd26ffe574324b290784b16d98	\\x643e7421520d931729bd0f69acb30bed	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.076-00R0W6H1343RT	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373532363638383030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373532363638383030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225736444e355043535a4d514b4437534e5135584137464839523443354a5248374d48365a37474b56455a47473938524a5731535056354139435943424342484b435356455935303247314a4b374e52335237454a445a5a354547533450413837474a5250563630222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037362d30305230573648313334335254222c2274696d657374616d70223a7b22745f73223a313634373532353738382c22745f6d73223a313634373532353738383030307d2c227061795f646561646c696e65223a7b22745f73223a313634373532393338382c22745f6d73223a313634373532393338383030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2242325738484a4259594a545831395736305341415345333932335842455a46445651565941464e3758434a4b5a41595746333730227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22543141544d59594445523545544b5439323842454b433135454848344d3836465244545645534d51414b47343532505244304d30222c226e6f6e6365223a22454e565a5a5730594d533632335448353758503744535935383833303436303044385a304d415a3852384b574b5a544553394630227d	\\x246c6aa2951113ae467852bf6db313c29f3f5c2216ba104c2c58fa50ab1e19175687cf2b80cce5b1edd9ff8a7a2778476efd50fd34cb8677885c3dc18be34064	1647525788000000	1647529388000000	1647526688000000	t	f	taler://fulfillment-success/thank+you		\\x0c52615506b46732c6485615aecba66b
2	1	2022.076-00Q4PR2PJWJK0	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373532363732313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373532363732313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225736444e355043535a4d514b4437534e5135584137464839523443354a5248374d48365a37474b56455a47473938524a5731535056354139435943424342484b435356455935303247314a4b374e52335237454a445a5a354547533450413837474a5250563630222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037362d30305134505232504a574a4b30222c2274696d657374616d70223a7b22745f73223a313634373532353832312c22745f6d73223a313634373532353832313030307d2c227061795f646561646c696e65223a7b22745f73223a313634373532393432312c22745f6d73223a313634373532393432313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2242325738484a4259594a545831395736305341415345333932335842455a46445651565941464e3758434a4b5a41595746333730227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22543141544d59594445523545544b5439323842454b433135454848344d3836465244545645534d51414b47343532505244304d30222c226e6f6e6365223a224250354833505752585947595842474b50475036564a3954313630585a4d335a57444e4d4736384847354a463143444834593647227d	\\xcb9c3863383edbb37eb07f6be844bd70e6592d4efdee2d9763cc016177dbf67684adb8192f685f13b937284346a45cb869d5ad16054a321bb8a644685ac81821	1647525821000000	1647529421000000	1647526721000000	t	f	taler://fulfillment-success/thank+you		\\x30184a08b2f3d3b27e4d125c3cc5c8a3
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
1	1	1647525790000000	\\x88cdf331f8e58dba584e5d683963a90b60609a3c171990f18abdf2f94ed55431	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	1	\\xe53f0598bb64e977d999ba43f56d542aac3f184e29f4a8faffaba3e405104f57c00bc711c936e496e0201efa7cea8a6f90e05d30a7446b3bf50844b5238b6f09	1
2	2	1648130625000000	\\x01dffa7fc179fccb8b8717b67e307ba7fd913a5f2ddb4be4113f5d3ee49630e4	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	1	\\xb081dd6e01f252b3fb69b94061755de5e023e3479cd93bebe092501615d4178e70667aa8c1cb762914b5e0f1b92ce36a8f49a69f0c6e7f37f5a18b4e11da0306	1
3	2	1648130625000000	\\x04ae9e22c92505bd0f95e045f4e209c914437dc5b13819bf4c8fb049b0069e2f	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	1	\\x1ccd2444d23476b15fc2a50a8ec99795460c66a407c3c442911fd59614e6c104507a7d46523e489f0189ef0af664f10a6171914f85e684fe150da2a74946870c	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	\\x02ce09f924810486ffddd0e2ba6d8d9992d0bcfb67381b8d0aa970bcf45671b5	1647525758000000	1654783358000000	1657202558000000	\\xf3344d69c11a7ffbabc1475d78e3788991af95c5e45c0cec3d6cffdb145bc88c8add5758d8634f56f17f3b8d9d82ad62e12b9495454d348bfae5c6aa96539f0f
2	\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	\\x0a665af5ceb6f18f76725f3c4aa710ab98e1929af394c647de6d5412080dbdcc	1676554958000000	1683812558000000	1686231758000000	\\xd6345816fde8ddd7b006bf86fe433f940de4c4b252cb88ca4c37ef2b68602f840779ca1a9bfeb590d5a66acbb2a894f16cb99e1ab2b192d277f10536cfab3303
3	\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	\\x8ccfadc60450eadab394c68fae5f8fd58226971a9c0857ac0a799adfe3dd7775	1654783058000000	1662040658000000	1664459858000000	\\x5b98aa1d79bae97ca3eba284a8214c5d8c158d5cec87ed4182f212279b60400dc5eaaf942fdf12217ca051c966fe0e2fac237bb02d0bf0092a07f2d0e8993b0d
4	\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	\\xd4dbd3e1b72489a2a477ece5dd7b48e2efbad6d822e668377c3e78252401ff77	1662040358000000	1669297958000000	1671717158000000	\\x94693c06ea0374d1bc011fd090d49ac5b834cb4f941b9f4190ad7a6b217cc67438a5c49eb94bc5dda669d7917253ec7d8ea453b6bca93d62e3a18f3ef379d702
5	\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	\\x96e1c99b4741d3cc52798e525df3a6822a0909c1acebe48b8738166226c0a12d	1669297658000000	1676555258000000	1678974458000000	\\x1cb0feb201eaab65f176c8bc0382ba679ffe7ad2dc7a92bd88f39e9bad29945ef89e52d147a5148ecf46bd2606149761eaabfec1175b8530f1d8d7d494ca9f0a
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x58b888c97ef4b5d0a7860654acb86910fab77dedddf7e53ea7eb253fabdc78ce	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x9067ee1b0041148f1de0c2e31f6baa9bba133f8384cf76d12fb3bdedc769d7434a5fa9be4b52dd77f2af7baf8e1d05d76dadc10bd6a7d7ebe631ac5c1082a30e
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xd055aa7bcd760aed4f491216e9b02574624a20cfc375b7669754e0428ad86828	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\x133d9daff3874bacd541bc4ea3243b8ab386f893c8aaa3a67038c19f43debcc0	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647525790000000	f	\N	\N	2	1	http://localhost:8081/
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

COPY public.recoup_default (recoup_uuid, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, reserve_out_serial_id) FROM stdin;
1	1	\\x83de341f064f1cba179ed75d2934efe2808798eb67d6a77f2df6665f9bcb6ca60cda04846f082adb7be88d5af887459c6aeb2fa89e40d9e0dadb87c5522ed00d	\\x2764ebdeb63459ed9cdc6e8eff72c8e428fc2a385de25315a4703e84ec25580e	2	0	1647525786000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	4	\\x627482592fca07540cef744f797971cb38d26fa79e274514b49c453fbf184aac9bc3f3d18a404e3e70d29b1c60cde9eeb6e63061322f4b92fc31e3b0a00b2504	\\x0783ec15fc90a8ce43e33aef369fffe7ca54c1cb15041733f65302c6c226b892	0	10000000	1648130611000000	8
2	5	\\x94e939f93ea43e3bf0aee942d17bd88aaa5a9c4905fb3318306fff76d82f9586dbd27cac483e3d3f0ceb80843fa6e82e3e22bd9a13d75cda097b1a6db8b6890a	\\x392be79a8d10e00d515b092b84a0c38664cee81a60a9fb05fe5d784504fa4f14	0	10000000	1648130611000000	9
3	6	\\x2064fa2d804e5f1b46b0ab61dc3ead0746da6119d00af83c60f5e3fed7706cb1a1398ae787dd255e14d88ba14dcf09762ad5a51fde5573f33887f406b90c6d0d	\\xa5016cde06dafb0e7dd7b6e5d62023dfaede3978fdcee7b485bf3f14283c44d4	0	10000000	1648130611000000	6
4	7	\\xdc2a007941963596a388024f73a656e2e8824390a7cf46ea989f9dbe8b91b376f8f4abb5a159435d08f011fa2c0f0370281054212b3ea68dc3fae1927217250f	\\xf3defe1acde9b30c9bffa9bf41f578c3206c4be4cbc3cd8e5a2dd01e639f354f	0	10000000	1648130611000000	4
5	8	\\x99c46b6187e3512001921da0e826ff97f89d3c40b650199b1fc6d04adbadf351ea4eee0a001095979b22793470170f9a34b9f82f56e1684eb3986e5c7b28ef05	\\x6ab1b987bfe810e053b050bff082133b757f2da9052d57375f15fd000d49708e	0	10000000	1648130611000000	5
6	9	\\x143fc792cfd5d2fefe0d641ed923b0bcb9ba51dc8de137c596ea08905b341aa48f07937910db67c5767af31a3f2b5356786e19d6edb081005321f6e4e6a9a90b	\\x28051690c043b86fe3c66780e5edd1d812979ebc146ffdf4bd86e66514ef6043	0	10000000	1648130611000000	7
7	10	\\x10a6c90ef24c54de896f6744b7b749f603788297d61d839f3f3773a4abadd8deedea6cd4fca3df2874ca45b2c3e831c4cebce20933dbc4df70dcacbcc7c4ee04	\\x67307336a691ecb1f9e2ca69fa0b085b6bc6bf2a6dc83f59b5e71ab344e47b42	0	10000000	1648130611000000	2
8	11	\\xd448b823ab4d70a43963cc5cdcb12cfe99a7237ac79e66e74783a0abf7b5053325f1c6817df48c26be4dc302bd68307e52030f4c14f5b26abacac317a790650e	\\xc45d8ba90a247409a51f0cdaeefa8755efe5b18d3438d9e306363bcf248cbbbf	0	10000000	1648130611000000	3
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x98332b9e7191e388924300326dc089c68920044da189cf6783c3d3734eb114d7cb52c12c79b50981a70ba3495681982956cbed69f14e8d6279cb5318f154abad	\\x4051aa40f39b5e52205f77d2ed9833c88efb037083d32d385f84053b28703be5	\\x9fe408f36a290c4bb3180c516d803ddebeea9abdaa0df754c7d1354178bf3fa5cfb8876f0ad68db53fa1c3bb7c68b6a46f40bf27d41363d094a59bf3afea1107	5	0	0
2	\\x8b9df653861a3e356c2253f13fa8453e62d344f9c2d3250db9f96ac94bb2d5289be99f75a20049aaa71af7f5212580212a3c0690fa5ee31110c786f772131c17	\\x4051aa40f39b5e52205f77d2ed9833c88efb037083d32d385f84053b28703be5	\\xa9e2ce8cc21396c33ea0524300fc769049c67260625eb93e90e111ecd058a47b4be3ad890b0dfa33f20c61f2821803b186556f1ead92a15091c467bca005d30e	0	79000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xe67ad1b5fdc830290f35247b5b8bce5114978794e59abcb28e5a30912d49791ff0090d22c7f687d57ab7bc9ecf35384dcd49009778f2c7b3c72d993ba2c35404	125	\\x000000010000010035a19ddf37365d240945ae9c9e24d233a5213831372295f552d2519c9390d9e147a55089a187e4d5ae36e0adbd7cedbc423e4b27865be6e2d6f6a9ce9092fe2aa2da922af7dc04ccd6472bb94415bf9948ed89f843cc0577ac3b0a0a28a58442aa1c15d07817b133d1bbfeb995a6e7518c93018a0802938453caa76cf890a13f	\\xfc0dce0bb89639a9a4db03775db8fec6b9fde5b8cfe4cc70e0c1d58fdf7c7270ebcb3cc9542e9481367c659f58cea01a592fbf8d42630093942661753eef1516	\\x00000001000000015c21892792726ec3d3655274b6ecb0c6e5369771ae56398bd63509649387ce6bb15f165734942d456a26647e209b7ea8f444c98ae0cce5defca21abd4c9f701e55d5edfaabd62103895c6eca0616127f76c3be52b276fa2b34fd4ffae7564a6329275b94b2f45f95bde4bb1fd724a5a239d71f1e733f6ec3e6dd88c5c5255f78	\\x0000000100010000
2	1	1	\\x706895f2ffe32529d36d19e7ba78ff9e590f76b1276267e9f96c3e4261b1e8e4ee10242551c9fc948614a08851f4b6ba36c4c5847c51a147bf0c32a1deb65904	398	\\x00000001000001006a022c894db05f515e75779c4aafe55db5aead98416534ca7e4b8593c39de80be359b77c9936c083e509e7a5fc3493c9e33903c066a40193d0e98cd1422739ee33acba2bed4dee3110279eea6d5836b96620ae24bb4764a603f2b764b27d15935eb0b35e7ed65d6ffdd7dafd6a79efad7513da907999fbc391366fa8640b67e5	\\x30ec3dce130a422158cff1f3640215ed5b5e904339386332d96861c1a9f37734b811087ad249ccc0c2c5ed2af11c27cb721158081164be0893d092aee2fc21f2	\\x0000000100000001c570ab8671a7c7c0bf6fc65e3c6798eb78a88486d46b20766ea6343d1b5571dbdd4377788ee55555fc01a833da3a6376faf453e913b61ea75538033b50dd231598d24d4389983cbc8d0d16ae92dbf9a05294591fcff354a27d109e0f247e1cd8f2205ce738337aa918aa4fb50f0ca05d218464e9d21bf43dd50ccf054d760017	\\x0000000100010000
3	1	2	\\x7db930e7f628a1aeabbbc458abed7d11316515583b130e3083caaaa75149e0bc96278ab4a145bb46c367e623ebc37fec6002ec3610845225d9598473a56ee70e	398	\\x000000010000010080d3836488248437ff77a28bcbdfc1d7a39067c4882316c03e98be466f49a0adf8ce7e07bea0d7a356c293470214201ee4a0dcc0a0c6f0e455fe4ef04a9f427cbb8dd02b5c879b74ac718007fe470891fe790ba6ed5f3a00f3bc4833ff669ed02ea45d998efa5db96452f498402fbd98c7a7e701374cbc5d1c1db038a0020842	\\x7840633125cc897085c7f0cda7963c27b320d593f1984a35b659ad34b7f2258561984f16b500941b2354dbc19c4fa0be85e9f44e9a25dd4c9ef55e0f1e63592e	\\x000000010000000165342bbb06a4ce3f557afe10b6a34cf57228890a472da7481a3f32e1f88abea6f96955a7bfce7fe2f96880d597dc46e43ab64de7e8a3bd759cde352156fa56c72f5a9d256e8f25e55b47c1803eb3aa298fdf40ce062f769f48d3aa575d9d5fc1fcc80b5dcf7b83e778e957e3f71cde8fb48446a35f269e313bdab6c736caf762	\\x0000000100010000
4	1	3	\\x2976f01912a08a34a2805a5a9565c7c43d5a199fb44697223c90ae2ccccf81d1894c95cc047d1e232d3cf144b2ed027b039031f3af58529865d9b3a12efd2c07	398	\\x000000010000010037858851cedafaa9320e544fa447e6a86a9858e8e295b350d8c81592c344bcd1dc0764be9a937558c89ac2b711ff9fd5c4a4642baf91c03f4848368053a535ab9a0a23952c06c58ccad519baf364288f8c7aeabd22c47f083e62d9d54e6ded1fd69961fd6e6afa09e67cebaae328d12a534d2dca89057ec992ccbe0e3a55a671	\\xde01aa63f19db6ff2ec6756ae42e156e82c21c8d7d57bee7d0a5a69762a465fe5af04e55abe8b33b2e41645e98919dc3cfbba3edf166d16bcbc7202108e269d0	\\x00000001000000011640f495206e9185df1194d6e1edc0f7ba776c4ea79006c3eab9d3a41f91017d1952430858003392cbb5141dfc8c0b8edff5bb9d54e1e84b55959c8afb86b2abbbbd545a0264b1d04cc03c9e0b8498cb91d032499f10005c668ecf6d71e42b54d632be68d7d1f954d0d45ab309a77c4842dbc8c4b09c776c0948dd027d0a2008	\\x0000000100010000
5	1	4	\\xc4a717408e29f509de71616704b78c43aaa2c06358e3feec7b50ffca6081fb0b3ddffc9e1e7663f43fccf2f5149c0cde5b37a655129f226a5f56c870e53b9501	398	\\x0000000100000100bb30fa158579ab40fe8505a8aa0a1bc957285405e153581be941c34ae2ce41b8e18de8bb705a2c6a8d51a14b0483d7a868f9f48f9cf9d580d039a3256e89f07ac04b32ce02576e286bebea16f37ae8032056c999b199970007333976237e7465bbf37c853e38ef44e36ce98867baac5b98134df054042630c1155d14cf7de533	\\x5686796b5ba07547bb94d403de7d3b65a896bff9cfa7be12de1ca7ea4822f04f8c375d6cb0f6416df2831edb34ad6c761398e266c34fa190f2d31c6adfd44c09	\\x00000001000000012bf3d404115256697ae7766eab9560be87fd5cb7574d12b01e84ded730c0c8e23f3bc7550c936204ed7521319561bab978f647a2a75f7318204eb9ae089cce40bd30c7147f14f51d565b0873cb6121bde80e63e89b01947a7dd7afed50328e6418fcb96ad145f0e48a06615ee614b23888b9aec46a61d22514c40fe294928947	\\x0000000100010000
6	1	5	\\xc8afff42c92cdde6bd3d151d2e1a60bc16318d0cab949f969659a6f3946ca6032d5b074d09db99815756aa5c290712e09e5c54c3d07defdc0663cd48205ca10a	398	\\x000000010000010038b3edd9e7be85c7547b77eac58dc516598b224a0dee23569130c014dff6582aa20f8a760707e25b3d1ca1a0353b5d9dd220d6ddd1a8bb6b3e044ec2c76888a9130a2edf362c0379e2a230c7b80f6b08f31719a2e4b1e0756167818f7a0dd18bc8860111af3d5f804f7e3911c59427d14d2e9ca3c6450ae8be93f1f2dadcb1db	\\xa4c28637f82e1d0199eb489edabf1077373a080c23cc61118aa32e5fa1897bea9f9a6df5815449cae689fd54dc1ed5245f5d5867b0b7fcf788ea9fcd64b60045	\\x0000000100000001a0e1bc15f5dcd52f5bc17ec9a0026c00b92935b15222721e11554681003b90435c349947d53599ef80ee6e09a962243f9e5383b3019d65d0c49591c2ce385be025a815cbedc0e9fd668f29be644651d7af06353adf48e2430c7d2d75b3c7b76f5f895c756eebd3bd600cd057fe3d6c2c50b744d678439e12f6fdd1d147518734	\\x0000000100010000
7	1	6	\\x037486b58e8a929c4c58c068b2e6b95a1fb937f366883497a8252779a547ecf8b81afd519b31cefb13ee7341ae470795889bb863023332b9014032ee25509301	398	\\x00000001000001001afebc2e5eca90155e72dbbbde1ff8413abb2f895863a59e49c70b9e8fe9889003b0186764278bb2f02a6265aac6cbf17bbfd92afa8656e3535a279a46f94529482ffd4e58d083d5acee10a5751e4bd38b0d0645a0bad8070bb0bf592d86d2fb2d1d4a643084a2783c0f9b3eb1ff67c57edc6b5092242f255a3739473ccb4ede	\\x0a472ccaa8d5af79bb73bf429e5e340e22899dcdf14f8b199f1080cdfce64fe5df0305d26d531d4b9d42ecebf6cc032040d614055baac6eb0887ca78937ead64	\\x000000010000000137e1ae09a02241e2b6d178b21df34afb2b7d7e8340aac1ecb0add5770bbf6c00fdb4bf5815b506e8574643e1e24b15587edb3eef9abdb842c62debf991e68ed517c681a6e44acbc5e72784472effc5af54dc25b83860c8392dd8e067aa6df9ec7c0b5851c19af9246675f6ff6cb1323c551fdde0d3332c072b01e046b0283846	\\x0000000100010000
8	1	7	\\xd1882d94e30548d032c1c46fa31add6b6d8e3c8161066b9268476a0da14363551a2f94c015219989e1057a2fa1753996a9234dbc0eda0cd52c8a85b6f547bb0b	398	\\x0000000100000100a49ecbef292d44804b7987b3b6c49506bf9ef15fef3e219c84f405eb33bb9df5c2aabaeff7e3288a2f88bc09ad39fa3b09ddff1b6cb2aad573d40b58f799eec66bc4085c53cb73494066901b5c25b4152682744ab71cea1b7d81beaecd4e287fa33bce2bb6f684a7fa5b441b92e179aca773e67b7dbd853d9635995483ee90d0	\\xea14861fd8a39410d6a32d30ce64867ef7c9ea8b6a88c77092bee01cf403c2186afc7599b7dcced103f6ee2913f4fafc7f55e2a6acd42db0478e3cb751ca7bf0	\\x00000001000000018638f02fca2ed0625105b214fd83220aba6e9370fc8592a2ac0a6a0967fb22863386056b754ec0140d67c8ef46067315436a56034e882879ca0c1d4ac8a476785764a760985a9445514368604b671eee949080fc3ebdeb10fd2cf10b753a3673809f524aed80a0ff9597ca86ecb7c08d568c303fa6431e9f7e466b11bfef1c71	\\x0000000100010000
9	1	8	\\xf334b3f0881296b543b78c6c94f0e51ba438bf03e9d9372a089f48bbdf99a4ab32d837638be97dae3059c832b85f4d5d2c02e06d0fc1f8be5e00aa66ad987c03	398	\\x0000000100000100797418755e41e5685bd325538ed7e804b59136ca4847b9f5e370d2a3e8e47bafa84905f02b0fbcc02d3192d9f9cda68daf3719b6240c5aa8cf0e27fce3d1d4ad61db7505a12e41365f37ca40a3ac340ed34bc08af1dbf4b54b1f030d35325140aef67c5d74e68bfc99ad604aa6cee8e439a301f75ef84dcdb9a6f885b4d331c8	\\xce8114e51ebb5986a8280870420dbd7f9de03e6f970553cb89c2ba14a225b0e2ea3957528d5102bd97d2c9fe1ca0f8c480279f6cd0043543eb6b819641dc139c	\\x0000000100000001a34ae6dc1557dcc4c304004b3a1b344bc84cf20b8341e0ed09298b1a61924404c02c885f33a67ba00a0c2fad7cbdc1526a56a71e0622bfd9ac9a957eb648a80971d84a17e4f956ba4527a6733c085d016063b49a06af8d9987bf1186e314f4be5e9ae700eb95f8af4e4faff50b3908b5de754f14690ef569eddf3d9d894e0722	\\x0000000100010000
10	1	9	\\x4ca35da7034ebc750afbd2b2e9cfdcc2a8d56c64609e2c1becc05a268754a73012b4ea4d03cc6ac0768b1959ccf35c488cae938e003f98fe1975e12fbe688a03	87	\\x00000001000001009a97904931dc85a4fa007beba520f573cc847c165144ddd3439159c90194b0ee2e06b21406e7cab665573aedfc18cbaca27f2cbe581b726ecc735ab86a758624c454903956539d632b0c1faff107cbc49e38a45e2d6f4b289c5d760f17cd1e16fee482aded6fec17081b41f43b4509dfad1fd3e6393eba10a0b8f3d3ed6da630	\\x4d591f2efd2eee2d88a63daa335b94052b677b9307851cc8ebb65143782134b380020b43c1e74750f801b31b4a0a7fb27fe906ebf2d33131d7e0f8f544596829	\\x0000000100000001970b6a1f7a6dbb1813026b024d26df0b7994980b963dcbb66061565952eafc79bc17793b9b793c4ccc4519866774ba0cc57fe5ca3e5ea097cbc48e634df035df655b96e469111a7ec7e5b3dd97e4ba1a9ed8a8228890d8c5df6fbd8ef17b664b28370d30f8f36b0e0b97f3212abd9a4ab9d2eafc658a4bd4ac26c45d926063bd	\\x0000000100010000
11	1	10	\\xfd326357dfbf28193298af06b447d814b6443f14c5fe2b145d9ed3f846c887f929f39d4647b1b1b8b1b4f09c442ac5e4e8d3b1c047b62883d8ff5a397ec0b802	87	\\x0000000100000100027bbd06f03ba04fb29f9c3f30ec49024b2096f720ee8f0b609828a21de31df1f8cdb93d3043de1bf9e409d23227579d099da77b05b514aba48a7f421d72fabbf61a0e66a9e428ed071f04ac9a69526edc484216b96614bc746b98d3fb1ee6f3cebae8fc60b3d7e607b15ecad9868b7d2b2b532fb0aebf7c56f3a94b15e555ea	\\x4cb39f48f39c3ab75cb22c2fadab63cc03f6bcf391165bbc8c06f39abb4ff9dc9635450085a90aa910242156e87b592286548a1a2d56fe3317d6d4d07ad81757	\\x00000001000000012f98e6ffdad2dcc98b6e5d446a48b17c2d283053c8add66ac85561d978ca4ee4b277078be1a5273cfc96c71d5dd8848acd887d540c7ad6fd523be22444503c8c87ec8cd459a999ced341616fdf314e28d0fa25dc4aba67425630acbd7cfce8e0134c1cd80cfe70c46036ee13312ec2293ec49dcdb05f8e2302317d6ad34768ec	\\x0000000100010000
12	1	11	\\xb6cf010d04cd3821284ef05b92fb5095a828f583b68eac3b3c58f76413353c71b388ec63bc2f70699826f786bb4ca074eede1ecaef843d98656fea29090d1708	87	\\x0000000100000100bbace0eef52ac184ac55b87327a71fe51bb8775e2f065a2f89cdcbd93381fb661b78f0033c47b13e8c7e1701c043fc7abc2b77e4358ceeb8acd4538d4d6c5783a8fd329089bd86eb13e66b324d0906ee76220b2b9fa61f1ffedb96900b08eb516c4245c55d49ae0b3cc93295dbceed908f74124916a0b5d1857b0f83f7c70ebb	\\x604c525ebafbfa55b66fb092631ac72610416eec82ba69c2f1d25bd3324f06f5ec2765c8a4c295009718c32c950d3ad74c9cfddd3e657b2c35f48e134aed694e	\\x000000010000000160462a6e53daf4a47ca9a896c552a44f396a840e506ac189095f632834cc6ae27ea8ab3b04ba01c3a41bb4d4139df7f510a9076c379cbe66dc532a9e7805abaf5d7909c451d4362200ca10342407a3f13e1558fbef123c018a55fc84b82de9e3c29eb38fad0cd99c261199e4da9fb6d5399f3985f1e04c3df69d59548dc08aa2	\\x0000000100010000
13	2	0	\\x119e3001eedeb22fdad20cf86150bec0024e746cad3591ea6e73caa6ec95aef3d687ca88caaef1a334b62b7510a080a5aaf53b6bf6d9151dab01b3cfe330cf07	87	\\x0000000100000100a5cb6c02833648625902fcfa524b5a746c0cafd6e77614620aa30c71d99b39450dd95af82906d0032244ba32969388c0c07eb94307a0ce4d3c2923d39bbc01220d6d5c2d14ee1b46677c4712922b3fa04c79e17fbd07f098914aade7775e89d9619226d33e248037d48fdd6e744e1441d9633165865b06824db38bf85314259a	\\x2e01cf0fe3485eaaf67e7de0b728ed5af51ec3da717b33b48ef7775e495aa051f41ea45420eb25841de944bb25640112d704cc3cee8e71e01d32840adf58fd91	\\x00000001000000011ca25c283573472bae2e12cd35ca68d9e0cf8621e6351cc6231a648939d79daace2cc57f2fd23515d102bfb388ceafd3fac34c58c3de6d192a58d8b1a0e5bac087f4272ef908af2201e99dc6766b265876c8caeadf6a9e09071a2e880936b2a4306542cc8f9e29408cafbbedf61e1a3f0dbd9ddb82176f02d9e63f04e8423377	\\x0000000100010000
14	2	1	\\x65594aa48de261c144605e8a229d14d12d6fc6ce30f260818e41c596f2cba8008ca5520f0d8f95ac729967265dda75ee6a1bdf04c583746b0247b9bd9df8c607	87	\\x00000001000001007a0d002c94bd924a7a596be13a1e354d2f60427bf63125535c958a3be3aa170d5dded0b97cd1f03c98cb6b9cd5f9cb12666d1d9332b3bfc37492b04f9681500bbe93fb0e6fb682d6f726a15e1ce1befdecca3335ff41f837c6c81fc506d00fc0a2cae0266fee1b03b36a3cfce5a20da3a16cfe4df7f02bdd6d1f495b2c1dc70b	\\x5470b0da69b7e12a30ec35290982954bf9365f0ae94f0bd1e7f7447e0b5a45732a5a325633400d5abe24ce7c370587a629014be176b377b587c1550f0efa359e	\\x0000000100000001c1e5bb905c689354f35b6a564fbf9837f0cf8b2a0c1bc6030ba5f310340a192572964084b127e53c9e809fc2a63ae0b6717e8faf6f12486f36ced01c01d38f69bbf9a36d033245d8fa8971cf3f85079980afc2073138dd14af70baff91562c9221be5665d712a0f68c6d39d48e165440d61e3f4bc8d276222fc443de95924e10	\\x0000000100010000
15	2	2	\\xd36100597198234a9797d5631b2e3a0c49b055306d9e5656be681e0f014151822a946a04d7813a466a444e9f523fc228f6391b896779ad410dcb7cf08fa59202	87	\\x0000000100000100ae52f0d66338fdb718f6c3614256a92c43a4c6c03aa52f842d6aa59d9a82d365139a76404a684791397bd915af2ff47e12ff206aab504d0d86007da1fc4573d68503c19edce2a4a84870709dbfa3a251423ffca2cd05f748c25001874efddb9884c7b2341c56e01595f27aaccb97071b368f6851c658a4c3b1e94adc398d0894	\\xb75bb7e0d9df2075b952c740c281327ca26410f903b8bc2e844bf037c0e63e6b3bd6f1e5f6c2836268d2ade59448b1d01db00e321ca75f604e73b2a34f1f39b4	\\x000000010000000183023da9829ba380a68924849da1108d575bc806acb735a566505de7da8298c726fbbbe55c93176d22069749e1e7dde96cfe037f836f11180d97e0d044165f06d738d75a555a685e35efa410c365cbd2017f4e02f6bb06712b4bb993b2bccc59640ca36f528ec8df5d3e6a6ba4c07711aff14b109974f62cf40dbd96374e2b2c	\\x0000000100010000
16	2	3	\\x6142d4b18857101f74e303f4c026f8b025b99a21c769e118155b1211799a2c72dc330aa402204fd8b6e4cc01f47f447921f0e25026cedb577b3960cedd189305	87	\\x000000010000010025e1b25d7b9077ec84dc1f4d4d58a4bb1751de140176a03239c4535ff693817af221b1230542425fb4eff9de30fb17789dbb30d58613c6fa2ace5ea0deeff819317d8f0b3aea2f6951aba899a86298203c2260f5055e5178cf8d1aed74ed18b0f2c6cd3d1c1d3ee92007b8cc6df2ff375bb6074d4d8147f5f729bea49d8c5fe9	\\x27d5494fd8e97692525d1eff853567514213e241ed7653dd41ef412761b0029987800573973a389ee923fcc5f07dae99609d621dce01ffd5fec10d9c3b71b507	\\x00000001000000019a4d7b7ca4a2b9556a7f16458c8ab9147a68382a15164500a9ec225929305a3e2aba2746d521ed01d6d4aa3f77799184a3845e6eb1d74b6aca4d8d8eca4d2bc608a208c636443dbb39c0de5bddb479731dfa496ae0e1c27dbb7fd5d7e56921da9fff626f1f49ad92c8d687c9a2276fbebf84acedf2db491c19925826658f63ca	\\x0000000100010000
17	2	4	\\xfa4c10ca1fa5e02053b07d76387a683e0272a4aaeed131ade47772259a60445339775f63338657758f9399a684e960d8e52cd14b5209d0e06080853e3c42c509	87	\\x00000001000001002cd4ca5fed2f6c1a4fb1e7543b1683ae068c6cf36021282fa483023888e8a62a0a84b69d177f6d66c4acfe57459975f3a10731ff52e09634089d69979b7d61b1e4fea19c2dd094a9085c686a5cf11a1e4812cb37aaa159a04cc6d03a70cc3bdb58544826f44c77849f3156d8238cad8abbc59b611bc923dac29d27d9b3408b8b	\\x3e74c695491642b1a6b11edc18fc53c0e24988ad4bfa4c65ad9301a1289bcedb07c609a018d5e3abafc39e65e42be7727d49d6fbeda50516371dafaadf18d965	\\x00000001000000018e63eef8ab70419f39e1aa462d3237936d6cabe866f49f778d1afa5811d008777e47714ccf959c245f0eb535057c2471bf2b5c14611c3c91c894a79168128ce8d069c753c8f4d225bf3b570a4cb9d7a9e4af361352fc50c820726e4b77e93f4542952504151239638852c1e61df1006cd8e77cf42857644543121f98f9a3f9ad	\\x0000000100010000
18	2	5	\\x03d67863f2cb3ed44b91cd4ced6dc7d9a620e5e621b5d1b5c3e6d6eca5cb2db489e0761730d092d2adff49e8c19e7d4a0402822e9230657313631053a87cd905	87	\\x000000010000010036c835e49fc6f1bb93746eaee730fe78f2afc4da1801b4d97ebf45033447634bfb88f42a8938f0b04b35f57b9112ca34eb0b79c4012ce16e6a2dcb3f687981e585cd5842c89563788172057c0c8e1820f6f7d09d3a860dab4a1439cf27aadf88a9707116ad3e01e89ac98ccef0eeb7be2d42ad19d2ba7d719ecf0750b1cd40f9	\\x3c06ed48e194e3ff4eabcd1dac3a66b362c0cf254a96100b7cbffcdced74dbf6284e1f89d81a30ec42cc46a2f0ac64b8a5f8a1c01f125ad84b7900b0e1b4cddd	\\x00000001000000013b53990f8cb4b4ed17e6aaf25fed42221ab505a6418c6bab0092c02de97e5fa17bbddcce0a28ccd284a510db8d1d7d790b108b64d70bee1946d8cc64bb257f1b7c36cc3e9dd5bfc698878a3e3de39bbd5c822d4182bf38541cd6a2dd8b11cdbde987cb2efaaed9b0a26c7e235871add42fe9fc952f7046965d552bb0c5a9f3d2	\\x0000000100010000
19	2	6	\\x2a622724232de36cb86ac07cebf636e260e520411ba30003d714bc9fb928f3e25264d7d739fb316137602a30fb797c2aa4b67aef1a76b455750137eda2ce9808	87	\\x000000010000010090e83fac4b1c440c620107c89fcd5024aba404b215574be90590a915107e78224a1f3ea756458825669bf97d3c3569d11e3a42826a1d34e82247822248b37dceddce93a4c2a6589f13e2a176a3b137e5a4370785c47c06857670e82ab46635b1aeecad23f22b3ca88b8b7c23090e53881541bfd786ba93e210f6ed832012dd5e	\\xf4bcd59eef4ba9406ddc478b0cc047409af3b7b8d7827f349adc7dd98adc58f0cb4f83c7fdc0c3d0ffa2ea4de1bc0fb99e958a69008ea410f8f4ce6beabcaf07	\\x00000001000000012ce0e80315f4b922e2c35e3451b78537b3ce71021e04bb64d5839bb794d503b41b42f159fe6103d7e11021de0791abe9313de57c2d54288e1ff5882145d00a88fc973931d2669c7aa09a70367f44b5f8fe22920668b076a5d8284d60c7be985048e810c5461332c6a2c09f1789c883299a746e50c17a1ce161485190e80c82df	\\x0000000100010000
20	2	7	\\xe54a502ac576f05f63ec59365688bdfd414c102e2599e4e47a1b94d99ec814958aa6e4749e3bc16f7287a41be772800b28ff008a694a579dbf656dcbb5ae8a0b	87	\\x00000001000001003f88738ebd99030b6acac7791ff85fa351c2b80e44f6e8322106ea11ade30c41ee6732bbee194d7a3b51506fb0c4607fa9c66359e87c0d3f599a2a0ba382b414eca0dcda97227be3ca5be09a153b565fcb0f55e7b985eac4295c3af4dd5d6df6cfd2501caa3b1cb3235c99647c49501ff10809dc9395f199923a5410d3b790	\\xe5107258110783d884329dc24d803f4fe646a78bc0b31c95035e7d5d2fd76f9f6c2a8366b90736a08843b57b9b2596f8419dc663265b0aef7b83ee6ad4045072	\\x00000001000000018b37fcbb044597be25f08546c3f265ba341a380cd48ed8260bd0ea67ffc2f8e449f1a39be7d5aa5e9818f22218fcfcebef60c889118c09c1e1cb8eabd0c4a8e638a0b1d288c2ec8c9949387a4175b99562ae803738c75d5523e4c3270a0f1801184d993fbab90a6e36a7d68ea6258687b4389c2167ad14db0e9b00dfafa7afd8	\\x0000000100010000
21	2	8	\\x2a20fcedd28fa06468efcc25af07b5eeef59ff8b50ed4ce5cb140a15ef5010ef1cbad56e9df451a42bafd2a9f6656fae57088d6444654ad7df7b1db7951d7704	87	\\x000000010000010021330b0ac3d312c81a82d7c577fa36e61e33ca630aefe9c39ccc17a35c0aa5e0a5c5c4b29898bf09c845cf67d03721647a32257ca3767718a2f6717aec077b2ee04eaee338c44f53f0fc148bf226507645c942169167555f0f2765b0326cdbb445848c3abf91c4d7f73ce66ce8c9ce1bd5c052949a7ec1e49cd8e9ad1419a9f7	\\x4198ed3769d43c2ce9f4e734f13183d0f191d58a8d99011dcd6728f3e10853a7d09c5b009af64d4e815c178b17386ca2de1d8c7a032953f538d2c3f7db8c5d63	\\x0000000100000001b814865cac8c4d840601863002be22be7c1c88125a9e3e7670c7469b60b25fd3c4b2956795dbe70bf27e9ee2d84f8f5e94fb72d1e468da5af407d50a41b24ac18acb08ff5d13857208b43a9e646e451fbd465f21d6b5643f5ddd9d34a64284971044d05e333cd23e5d5c3480e3e06f448b9af5969c70dfeefc2fc0d467d2f4f4	\\x0000000100010000
22	2	9	\\xf045d366ab584c57770b3ccc9706cf34d9f7b3cb09536e09e0611ca46eec002b49b1fc3a61980ed6a47e117c5243540ac30e141df0c0cbe049cb16b55ebb9904	87	\\x000000010000010032a0de9d86fd39d125304d1ce19a4208306534135057dd10b2e33844dc056677de353a67a4ad4ce34d9bc43bbb45f34df087b229309fed4bdd448890dd152bc92855e43f00fa872bb0726f96de371886c5f8e1c2d9c50f219fa65d9ff9ee03580aaf6c01da9b8291882cbcc2417903f0b88686ace3af65f803479d0a12ed3355	\\xc5d09bd5e1a07d0da4e0d6433a5e683e411aa52e9b609bc5ed2ff79bc0fedf869d5dc998c6a5460ea8328af4e1550ce9fa9e9a52a722d0a07348712b908bfe99	\\x00000001000000014a32367327b608202fb0dae25e1d31a84f01bd44d4f01b201f2b4f87c7062d56e86f7f3f0a02f7be08436db20db0b10c4fa46458a3871819ebc32699a10f2a07941e792e568e253edd631ea68fd6c956c8166e082373763255a944d3fee89763a2d40f6926766f0982c82c163208a236d25b41f33b7582cc0307e3e7fd7fa1b1	\\x0000000100010000
23	2	10	\\x679cefc55439bb00ed1f6ee8660bb26e7dbdead43acd9b602393a3d30b6fe0fa3dcbb7e6b39d146517f50996f8f08f03121bfe4b2696b5a773e07a2cd9500b0d	87	\\x00000001000001000a1dbcabc538ef91c3d185e0f80542c6826c2526914df7ce17751f7aa99079428ab3401e8822970fe4b54c0983f2e00456b4bb02ec01f6e4fd3140df85da9607b6a4e758256230c6df7c5fb8d6755a8d56ee9b7dfb448d98820df9f927226222d4c933c62974af4c3728682648c151781b7117c18184b642505503f232fe989d	\\x558bea35380e6c3be40037fd02446e07a9f89062f2a68732c79e7589d21e95c7b599c04c30686ad071b05fd2afc097bc40481044441d7ab8d79f7d46cca572cf	\\x000000010000000189cad28fb356097b608cde23769f6f7d6edc173ce0aa7c2bd577c67bf322f2b3fb063a20876893230a6c27a199edc83d47714a70fe459962bd8252a8029aa8b869bd6c7c2cf17a31a3cf01776e643c1aa3d5fec0e142fbfbf108f6d748abfe5dc50bfebc73d74ad49bfe5dfbeeb37b55c74008782b138bb336b4e9b1f7a9e059	\\x0000000100010000
24	2	11	\\x0713ba41c9c051bc7a4c00942ead534afee23faf2eeff307f009e43f8479ff5de3904df5eefce85baeb7b00647f3b60a071ce8750cb62e0d9fd194f3f98c980c	87	\\x0000000100000100b6c3144a6f52a00cf11476b3e00d1e781c5dd24d9a7cdac0b763537166dde771dfe2b32eea9380343475ce213303400a9e9b4fd27ef7ba2ee1b1abcf6ce20ba99726a9856c9bb6e483e1408f8488903bfa8be54e8b308d8cf137f61642952e4a4d585f8f3e69017139ede6acd676edf26adf46aba5d3e949b5ca738abe7a58b5	\\xc4da1751d068c0881d02dadd17fa6c6cbaf701e0dcf2e64c71d110ed67c1c181682969dab5c6d6ce567f65629f57e0857f354299bdc02f9f127c4f6a2d53547f	\\x000000010000000116a4f3582827bd9bee81c9536874dda267b2d183970be66db6f3951e5794d55e7d5f470b061b086a77f96f909152f292f6f28ec48287ff69edcdebb325f282ec0db15dafa561223530fc0e550cff4c53f39f8433671be8bd2a2ab67a774f69bda4823fe5bf1d61e94932ddb2033a4ac6e57f946a55e5e2d470652f72d3f01c33	\\x0000000100010000
25	2	12	\\x395c4ad7de69583c407f3857a88d466d476962560df74f065c7313b2655eced8e976d90faa5736a0dfbb6782f0bc12b0ca7ca4c200df28f8f151375f4e5e5308	87	\\x000000010000010044f613ad445e6514c3f030d66ef05f18dafd9ed52b8f68028b1d733fa3a57a1546e310f0f1138fcfcb8c7cf16f73455a4fa46ca160798f0c564778e195ae27c7ac62e8c47701573443bc14f22480387f415e0734b36c850ccb9912b3732d9465fa2549cdaaabcecb0582fc8105eab5fff9f2712c99c600f0e6561845fac55d0a	\\x354fc194bc7b12a65c1ff6aa1f6df775f93330a68d4efbfc6c6baa6c90d850d1f8bff71183c6380bd331908a4bd776c06e43ff11a7ffb967c91abc4357a782de	\\x0000000100000001a72ddaf6038f5bc090429d981ebdff8e68d53294378c272afbd858a3a87402d7934ea8443cb27a77b1c73b8d08f1d23553dcbc096e8c3c134f6cf44ad754cf89ee66593a14efaa1c8e1e0865272ebb2d15595a315f85403275e12ea458c492fb60d5f15afe463f48248c8bdd8e469e2da9a98aa23ef49c7dab7dfa296e93cb6a	\\x0000000100010000
26	2	13	\\xa424b73a9751b8bec62dbd84d55f74f393373a859863a271787036c834470d80ae959cc718d81a7537af30021c6cea140032140dd36c733e4bdc088af5cf830e	87	\\x00000001000001003b59e04bb76b6aa2594f60b98ee771170fc8f990ea0894149189ef71411536e4799891c760d3cae0130284e9d13367af352958f41b2230629c0f0539d775de330de4a784c2a1f28d9648c4dc15bb0ae77eca7e50122d694dd96f59a2b5197f169719648de9542f9c31c793a93d680f6e0f90e224976076622a865706b8b4ca4b	\\x99b579841b4ca46762440407dd66133c0242c93d573b7bb1df29780fdfd9fed04a3f44481ab90cad8ba1ff5953b73630e5c2177fa6dc900b19a9264d01bafc30	\\x0000000100000001073b878ec3e3e439e515cc70c3a2e25e594be847abd9e5d86191234b4562a6b3709c95d1f98d720d5e5bc4add048fead5659c2f13ea3bd60d999abd48e401a8bf649a91194b5a581c92ec355ddccc7ff81f873cc5c8792f8a2d086a8ed2e9979ce70f296f5fe63ac8043505a91bb36cb421884bdb76542cc4babf2fe69dc9ff0	\\x0000000100010000
27	2	14	\\x707ecfa13cc9dfcf8c9ba50fc426ddb814c1c9cc3dd7123e7ecc2948ef27bcaa65ec53c8742e4abaa1c273adf0c733fbb44cc941383b3100c0023b77c295e509	87	\\x00000001000001008410c4c65f4b7c392f7adb9f6270f24a8c97b4fac192ec6e70c2270fd059076ca911836c23623f77de8f84af3b57f168058fa1d24e9919438705d65179d2b9cbc251b63bd73c8a46e8a65ad9cc27896da9ba03f08f0386abfb5d5d3b8fb5ca79ff7285819ca250bea31faef443775ced777307e202de6dcd503618e672076f1b	\\xad11a81bb3970f20f15911d3ba7a53283751b4bbf4cba2c3c3c7f730df615edff2bf2623797c0f56b689e584a884e06c39a605262657b8bef0738cfbde52dc53	\\x00000001000000016890165ac15e7a8403e1ec46d488baab0b93631aa949ba7d1e7654a8c86effadecf6bc2ae9a774288891dd4bc6287032134af2f27170872ee3073f8009c157839f35169d5fc16c0e6e2405f32e2d623747c58fc637bb0fbc5f51f5452fd78059bcc051079eef89e0cd76f2d7f34b80bacf2d2109751731a7c563351081e1ed91	\\x0000000100010000
28	2	15	\\x43a6bcdd998ddc4801b5c6248339a9d0ccc350b859856ab5ec9ce6195bab9c251eda1eef8596347a427bbcc02b8ac7f6c7959cc2f717b92df1e37e68cd870902	87	\\x0000000100000100359f920b2c4d67e3c8abd812b6b3567e63427d8bd117500ec4c71e566a3194790203815ab4934fa1e6b1162ee30bfa58f811434718d4528ca37c629d3c9f4da0478cdbec706157d97eb8fafb71f9d8b507f39c56ced8d06281df968f6f64d51bf20e257cf7e95b79331bff71ca876e5ea9a7c21b20caa5bf400fa4b496147d48	\\xdccc26da2647759499729d02375367a705e5c4e2c69f4710d31cdb87ce7733d39816aa42d696a22ffcb9db0497b1eda7182f6d688709d7c1dec8421a24bdb1cd	\\x00000001000000010e548b7038fdb7204de652b95e3a8c8a9d458d8d20d01e2cd7701daea6eaa4c7a42e8fbe44c3fe17798debdadf0aa05e291809b9b57e9769e77fcdcb78c9f04f83f0fbe042d22aac2fc34ef41c78f3ce9dda1eb0f04833c3518c0c0bf581cd68c530ff056a4fc0e6b7bfd4e8813926c54d63b656742363a9aef8332e94f62954	\\x0000000100010000
29	2	16	\\x6068956b538749c1986e6052f8857d39375e8f09eb08820a3bc40d6ac38b20ccc97f621616cb14a5da0d027a5dceb08411790270e15a7cd0f6575b45a4a5430b	87	\\x000000010000010068761ec175c01d41be5368227f85cece67402e597da4a3d1d30b856b9f429398c1679b39ea201bc827d9642f40e0307a73e6b06809a06153d4133b0d4347a6cbcf30cfe60153f050f7449487a56531f5fa692c92bd489334c77270dadf6c0bf99a6c2f6465caf543ecc3b7cdd737f89635c2dbe2f89613d44521a59a572653ae	\\xf46c34658ead9154ae78b0d88a982bdfb70ef6aa69f96ed599c328074b68ff061d29446a31d52a51c5890aeeb639ea517b0451ebec5dea28af25f22c9cbaf38a	\\x00000001000000019d16adce67c33324cd604d7c9fd08bc644ea0ba1de83212bd5a2c842843236af711d2d9171bba5676c05e7aa37555e3e1e717f18ef346b8ebafa86c6206dec4d01e869f296a18140d895a9b754416a45ba60836c5882d20c2dbdd126f62a07368760e7f72aa485c4c9a4afa1c785348540f27e48ce4a5df83af2962f36172322	\\x0000000100010000
30	2	17	\\x01a1889618ee90fd0718ba1cb0d9ac24ac5b235977f6032865dd19143db18b5d7916b14fdae730fb61bb66090de051eb81066be01653a607523c48131455d409	87	\\x00000001000001001c2ac3d783e2eead7d2769edd1486895518dc0755ffd145f0c9ea69c92d630f937b562068f4628dacb4ce70c7bd7b696850311bfa47d794a572de0fa28b4fc9ef2571d9291620c88648cb32f2c42bdac7538ed357a54cd58e5b741b20c7c935cd6b8498458b830e40e778f64cb823292cae4a36eda4e87d450bad2923d5a0bf4	\\xb30117d0d2fe70a9fb0660f573ff5eb4e7049177e690f9a7dbada50259e6f47b60f2a0538ebaaf257f9d8e7433d181260513f99834d7ce9db6ea2533623ff6f8	\\x000000010000000157a5451205266fad7506cb98fa0260f69e1dd8832df60c57da012b31434b6c829d8c89632e53dffb11736d51ecefca245008f805385d4c304780e6e498f1d65cfece8022868881a46ae80908f555ea7e20f53dc2aec463349576f9280e87f7d20591a5d6deecfa753f578650cd18f2b3d38d4fa4b599c0fca95c166eed25da73	\\x0000000100010000
31	2	18	\\xd17d1dd22d4e3ada90674e4102cf2ec7a2e67b98a1b6a9a1a32f33915e484ba339d0b9a897ac99d5d0c388a177c66e5b182547dec4c9ffac0be16b6a99853d0e	87	\\x000000010000010075d1dbd6db1fdcc7db4c60b4830b165735e2266516c10a0fbb3932999ab107cbceec1be0ef8e6e40587398af52e35b7794328f18dd02a98b03be25719bf0da351989ba10a2c898b01d0d02a3208b490c29213db8717504d36c6fea350441614b1ee197a18260a68348ff94cbc55d0e84c14334b131f6eda85010b9ecce2900e2	\\xeb0ad39f2b6df6cc6404e90ff827e7226d4b4ef62106d157503f11713d4ccea300e0887f4b43935ea1a013ef7b966afa3c3ccd84679cff3de1f24fcb6a4fbcf1	\\x000000010000000192fcc8277f7327fcfb09d37da567febedc0069780bd2cbcf539c60be1ec7eba07baa80ce7338c2f7c58415dd3d5b3a7148046559a05f84d55d82ed332e4a50685b91206e0dd25501a0744d5d2dbcbefd9d742200513e891826a35b8c25f5397f874ee4c7ad351b21c383644c141bc26ebb30f0691ccff5371f04b29c35a6529b	\\x0000000100010000
32	2	19	\\x9ca739af63e94c973b294fced46df6a8a2d6f627832576cc2330e731412ec2e3b99097576f15caa5a9a0204cf23e8f0324f3c3e196a7a0b65b2064aef9cbe800	87	\\x00000001000001009d2589a69afb2e965869288048ce6f6c5457414d2a59b1f21f48be78eb5249011d19f8673680cf89b4f7cd806005d8845ab182d0be9da252569a21d511ebbbb06d25e931913abc37872ad37c3f2c20c75ee3298463928dcba841b0341922b5754ae85a9f64627d38ba659db7d91d033b4badaccaeb7e460f612e0d2b6f891306	\\x3a7c247500b0c13e9c3a349e63615e6b25bc6449656c8273de3191be8d5d3f8ba184e99392ca331042ddc5d0fe27ddc6a97391d776e52aa6d4ba7f79f74ac98f	\\x00000001000000016790ed63ae69a5bda1cd4d844aeba75186b5e9e510f4e696adf026b3f63ba9bb99c9ed1fc0d2dea8a4c71bfdf9468a27ee943ce4e30dca1a79bb53e257e8bbdb0439b413c37ff61cd5fd84101c0d8adcc8471726dd48097633c2d542c9f7e9a61ed44d087f4db63997407af209dbcab33bda07be4896268830112873f42174ca	\\x0000000100010000
33	2	20	\\x24c55e71e759a67418a5e7e7573df3f6e6c00c19187ea148dcd63384bd018b8ef6d7f20206ad19eca2d161160b1f2c98252ea39a6a62eca3865a5049da71cc02	87	\\x00000001000001009791180d0cd9d603dda8797d52207039503ddcb71373a818d6cd2d363ad28b100b6145c42987af87eb49651843f4fc68754adbef14a24e19d6a45bd56abcbb6f168a17e19c26dd559c47815aebcdde3e2e9e92c81c51bd128071d2b74df7852cc8095a023cf6dded17fad42b4f06cb4427c0c1843de6df9cc78f9ad707c01a7b	\\xc0405fc8183c005bc43d0ea598cbc7d17bb47ac3656c9facb1db893685c452f8e55bf2d2fb4f9fb1fbca9238fb406b8bc5a4c0cd7cdb775cdc9f0cb7f42656f7	\\x000000010000000169aa4527ad605cde2f0438876be0558b2813cda0e016b4c345c72cdedc2f95696be9d4c6021f7db557db585023c13c174a6336cf845d8928f3cc61a44b1f18ea23dcd5125f92dc27dc85e83b482cead1d58bde26d786cef08502e0743b03024da807d42d6ca22c23ec95a62e31d6ba877672646d2b7af1337cb37b4e671d9d47	\\x0000000100010000
34	2	21	\\x04b4388e54e9d1e853af2f7c7446ceeec695d84ae33e7751a302a5413f846ba70146ab1bade257d46870eaad4dc960d95849682f97cdf8bb62e1d1841248fa0c	87	\\x0000000100000100024228643686a8d945fa5d3b089917739224c0fccac9a350b8afc988afdb4a9f4b95d4d9bac2c9bf9714ef35d19ec721f25b0d293b338fbd396c0907b1a259e5a9a4ff9a0bae9ab41a1026011ef40b3445464534ba675489037d3bb47c470f264c96d0c0d76aee7b5e91e65f7e1b0fb1dfdd71366ffb011a383b11b3f9f00633	\\x891427cb89b417df2cacb479da31e14573ef7acdcab55f84e9d2999b937f1b9ff47da0bdd54a00630ec0e4397fdea7fb528c129f0e377d61a22327434de9818d	\\x0000000100000001088d73acae5b7801c8e92f2e6c00001d886cbc71b6c4d24ba2714f9443634d86a3a06805e6c879f2a108d55964e43db73eeaa7051c1b8ad340761b2db9767bcf11954cf829e6608340ca4ea960c7116ac6a22188ee300fa6d846abaffd44d8c95b2e33751b844a0880c759c1f1a80090c4cc2d4802f827ad94e8def0030188c2	\\x0000000100010000
35	2	22	\\xc14e7436051b54b5c8d65b1b32a4da9719828ffb6ae2f9102d7ea44e89be1c433aed804a8ada5140d03664a9fc5f7494dc89c8e82fa35ebe2b9f0d4cd3c2120f	87	\\x0000000100000100b29cde9fc02e0cb45f62603ca13c7c962e2aa32a3b141ff986fcc8833e9710ebb71a24d4fc06bb38a844f6ebf6e7fb716865a6138e79421454a5bffabea76b44a1141abd5d8ec3d3da95cb8bdd73a7d3f25ec68b7be99012dda4e1ce1dbf94ee8eba3e79e77ff82eab8d48df2a1f15d0a7caebdb6217dc337655fdb9a98dc6f5	\\xae8196f7abf6e1d33d481796f1321661695ccc14be995b35d0044d06d2af15017fc7795d9b5d1c89a6516d261269137ecad723a7d1b0fa60bbb9cb1baa23fbcc	\\x000000010000000155b31a6577d2055adc9a77c67c97d96885036db2ac18022fc1579595f1b9aa265edc77d815ca8e5beca1306be3377fe7121fcc4776e6df1b7c0dd1f2edf7a9c6b62cfbc53a39457aaaef09b103b9e3e60d655577a732de0a711386b8d5987ead016b180335353889a7ac8e8a2acce4504ab745b19fc6fd62096afe5701ba1f6b	\\x0000000100010000
36	2	23	\\x81005a0018185f464348df10669da85ccec8dfb3e8487dc396abe8a3f40e3fcc93945ccf46ecce4571781f5490382015d1acc62e99cbbfe6a658a772bf16040e	87	\\x000000010000010025558916646bf96ac59671370923dd97c7272ebcf0b364db44d327facf139655f80b58b3a4fac98ac02f1ba799aa2315e95308031570234cc34bf5a9ddad22eed0d154849e8216b4e98f5b66435f95c92b62be502511cd733d6f92d597c2f16e471e84fb010bf2604fff068aaea53fdaf4d1330fc7bcb4b358d9a530e08351bc	\\x8d48406061a853fd2d566ba0dec95a31c0de4f524e448f338cfb154d8b6b819e06a9345b662ddd786e618e1a7a31d05e31012c7355a575909e18800a4ef5c703	\\x000000010000000134b35097a86558bcfb5d870eac0aa8498885a3299db535869fcf883577bf397261573ffb98f5e2f381c6658247951c09bcc5439f435c49ae04e0261e19e11080d4fda48918c0e2bb9acea9d029b29d91ab604d3746da01eeab01cbe676cbd318799a97b7e3f7ec811e7f226f3559cac27155e6d81002b44b7017c192c7921075	\\x0000000100010000
37	2	24	\\x080ce3ee8af25d6b794cdaec82cd9291ad02dc01e4dc42b65104ff1025f832fb7038f147d4798ad109f81d80209da1e6948b9330dec7eb848382b13d938f2606	87	\\x00000001000001008123935e02b1bb4eb5f780023a95809b84179e512c2f8fff60f0537a29538a90c8498899457a1c6a6e8735bd5a3fb9d5852eeaf338840fdc73709f0e7672a613e56dd71e3706f78be15f45272e39fbb8d4b1d24b93e6cf1d089cef612311ac830ad82c95633ef2acd091365eba3fa19f6c82e49fe3b6d74b1b029912d21b6e1e	\\x72a27e1d65447621ba8802dc13044f2d5ef36d0d470a5ba69de1be22afd25d47a9cca44c537650cefa0657fd151d4b7a164ee17b866862a04b53ecc22b73f386	\\x00000001000000014af20a80e274efc74c602b71daab3a24039b8ee0cb966d0b6e6ea66e5f5b332b8078df66cba85f8b24bdd93883652b7bd73bd3a57fe15705f4db485f3a545cb40c7f899a036347790782ab58f93cdad265870fff6af3bfe7eca7361096800e6a24dd44e90861826d8fb76ad9c72c254f45271069ca1d0cf71a6702cda2e30ebf	\\x0000000100010000
38	2	25	\\xbd7470d373339ce8102b4cdd331320c08bad355c8bf310606aec32e37053015805f1b148fe1a7a8b791c062020a673fc8f3ad862c256beedddd1fb28fcb6cc05	87	\\x00000001000001005ba4781c8acb92322c65b919fe98b7412b3f68e223ae878e066ceaca09b06d082b838aaf4cd72400ab97a86ab795b51880b0606dc7ec7fae5ccaabc89a3b0d425e92b50c72e24da77d41827d11cc1f75f5e58abb8c769dac813ed5c6780711cb4fc433e170ae43dbedc57684187b93390cb479e02ad6327f67c6e98103722e9e	\\xa7c655155cf97b686e53e2a9790913732408c2e885cb988f7fd67c7cee399020578b1f3b4f515b5db2477d79d9d5989fe4ebdd7270702d19e39f21cb5cfcaf0c	\\x00000001000000016908f49a57d933e7f4bb549d898b780d69f7057b63f0835297fc0bdf2bd06fa5b8a550b201d104a70eca91ee7e907c6f399990b64c5ec0a962068914122b0cd74a5d20bf23496122e4387ae76c6db221dc2132a4b6ae05dba30b6eae0b1cb735f2242fd22fe50c361a3ad5ec37671755516c738a4c0608b15e327f07364eb0b6	\\x0000000100010000
39	2	26	\\xf69d17f42001cb8001681bff09fd0d5dc94128212efdd153dc932fd4aa4f1b19b34ac7babbab7539ffecbe4fdabbb224c30be7848b3ec9dfa5f881855f0e6206	87	\\x000000010000010070f3a8f24841312daab056dcd7aec4e5e366261281b9f7253f5dcfea7da3dfd793bb7249621e42f734978baf8fe927bd585e83f9bc994befa2caea3a360b620ccd91d25649233d4b3e798c1156c4db3b40fcb356e45bfbd609c2e4bf52b8f40854cb8362d7e5159308f1c62745ec8a9b10219619c1d1dd4fd37e0ab9960af667	\\x321aaf9014d56fc91f63fe10e679a4d0b6adc40e82cd1c23e95dd798c0e9e97fe45d5a4315d72031e0e2f360ce52ccbb62284a8773ace61f328deae90a3d8961	\\x000000010000000132ba05ed7c863cd0b19a684d85137149ae00f0cedd079507b4c40961d3038aa737b02797cd54f94ce11ccdf323447ee526ee3cfd38936d598285af296ba44c6e840678e3a50ec399cb4fb565d5bec42a73e665440caecc8286a36fa82ccbe37c43ca14d8e5dad2fad7582a54fbeded2215f5998fe7f1845e4e3fc6137746a878	\\x0000000100010000
40	2	27	\\x1edad38434472a623342749e398fd86b407bc8e2a2e1caf19bec94253fc71440e9243e71e7d1e87bef9f69edf067125049fe78c2a807a34399b881ac88c6620c	87	\\x000000010000010065b5d14f029ee03758f140d20e97f3d86f939d20d0cfef95a6d831b2b65e3b55a0368f532ec4a78717b97277c892437428de340be0eb333f107151e601a39eae953a3737a73b3a22d2f76203561327c0cc2344c2090062abbf09dc02b5cc56634ff61d299dc6d5b6d53bfca620bf05a18a0be0302d2a48dd01df0dbc8ef4d3e4	\\x4bd72733f9d9b4bedfab5b40f892506bde164d510b956dae9d184d90975d1b3f7e6ea48189559179baacbb79f3f776d9eeb18e5bff46e5dff4aaefc5dbc1b52f	\\x0000000100000001b25fb4a50fb8f47e32c49412e67a35ab9060fbfb0a886f9b99ef2fb7b8271e0569cd38e7a3798a8ea874cdc071bde48a0a81daca06b5cba60f635a8a72fb4caf53da7ff121268c338a9446ff6c23f2868c24cccb89a03fc3e99d1d6f5eb24d4e9cf3d5d13605c1b3ca6aa768ffc3813c5aa25f221939e337ce6a364ff82a087e	\\x0000000100010000
41	2	28	\\x4a0d846853cb718ca3697bc895b629da7b5595767aaefe119af5a15785ffe3d8d196299f9d48611e1e9425398baf259e27ab918806dd92e164316f0c3779550e	87	\\x00000001000001002f6c391f165964f0869dbe9e9f1eedbb1d892162295b926edb085b4cdfaf0294be987b5fa30c04294d004dee97e1f3a8877be770efa59015bd64f2d7c579e6cc7fc93e7a51eda72e45be237082342092388b8d3d601ea27e653e013bf256aa9dcccf358173537751f5024e9723e5d6ed36b260b9e05ff06c77539ee423aeadb1	\\xc6283b019cbd82cb03ea53feb9e814b9c5655ee2a4a7dc27a17c0bdba70638316c8f2d4c8f3a5ec17c762a4a36c552d95fe46ec54fb7b79731fa29404c358e6e	\\x00000001000000015ba754bd6deeed1c760436e14fa760a3da76a587b5212839a279196924cdf3b3bb937a180d19f54cbf75392b5170a7c6a25d9cd24a22180b49731041a6caf2c6b399ded25b18e64714d74591c288c8fdccf1cd5075513f9607f90a1b7735e63226209478213afec6b0c1818d76426f6cf52303354aca120c057408f9befd6a01	\\x0000000100010000
42	2	29	\\xc7365cf4dae694bcea16c010d45f3e2fb6354a0c0f2c86fab856d9836f2782e57588bf914c94c88da4eadbc9f562840ae852555faa06d4074e4e2dd489933809	87	\\x0000000100000100705874a9ee7a126a5b461b10ceb333ecfbfef3f558a7725a40f14b88ce8e52c9df6ee41943f92e3228804ecdbfe8f5d46eb1ca89e7823f30be2bffbb51daa303cb8dec38a34c5548ab2ad8f5f7b1ad5df2a2071210ed074e1e83a15bd0055e2370f78d23d788850fa449c3b91a31537214ea978272cd5b5bd273cae88983c2b7	\\x3d418eaa7b891402257698ebfe8fea614f54ae2d12254f775c29dd0fb170189c35329f14e0f13cc8a3ef0eff1fad5445ede5e3e0aae89976b8018c22a54e5e48	\\x00000001000000010f18d6866c6388e5f5f14b5eeb63b8538ff9c6a6d4b99df1dcda671ddfeea912f5841abb58debb5a888e2d5306176ed074d229e45c200ad20592041744dc0167532f895049ed97cef00cfd795a60e3ddfe7102ee53ed35f080f800f12e6652091623a5f8dbbe894f571f25f7e22834a59f171f76bf269571a4eda53bf70dd3d1	\\x0000000100010000
43	2	30	\\x18eb9741aafb6e1b3f4960b3e05a36955e741d47ae5d77d27e25bcdfb97fa10b99eff30fda6ae84bd6379e346afc71423e3a9498130d26a5d5447a6c1c9f7e00	87	\\x0000000100000100be7c4d00e2d68149824ddcf9b16be38a196868cc599b5173a811f0d5e714489e2d81b7358381dd1fbb619cf02cfe9125c8a4b0b34b45d607714d5734a36ddad2dbf296cc13e6cac5165474b2cb6a63f9f9c2dc3fae008be8c7edd818d348b1e9bd53d78d930de7965de7a43e705684fab29dd91e1721650411dfaa2d4c3a145d	\\xadd4362473634ddb6c5890aeee137e1ded8788c8c4cecbb501ed715f72a82d8880bd34fdb2a3cbcc774f5ff99b089cbb98b8246cf1de4477b55edcb591e16839	\\x0000000100000001154d6ff4b7b02bb4b2a4ac6d14c1d239b62d9e84518edd57cb035000933dabb57916573a860affb720f6bf7dbf9ace3d5280dd695e5dfbafac2f06dcca5f9f89fd42309b6d694e936d930736d048162f503c076a9fd96ad2d856b807033236194855212d2d87291ebea373e7de9313cf642c0c18254ea839ddcb131b55ff13dc	\\x0000000100010000
44	2	31	\\x372ec0bedb6bd6a214e0c693560a6bbe9e4333deebb067897651c44a9e174fd78d06d6a1e43487591d04b97e9b77577a4bffbcd639077ca79c2c5f3d59b60004	87	\\x000000010000010071e86da94cd42f0fa95303babf3853b35781bfdff88a5ae242256dd4bad3e3d804e459fd88a1213b0b894f38f48360acb69755caf6c2101311187012e17bd190c8822bac48e8b4bf7df09610f98c05a0c5e3925462cda65c657ecabacd372038c38a45a600e2fe722c291576e64f6b5852f87e17b2366565636fb219ab3e80a0	\\xa5f776bcaf585675be13b5f3d0c0518c5bbaba002efe227d709df8fa60dc922e892d2da0ad81d2450376ec0362dc90495d099314311a81147b4796d19a84b811	\\x00000001000000014cab7dba9a00dba29e675aab5f64d442348815e955abee2e8ef2c08e463c53d4b58fcfe62c623c48fd59868435f95bc33c9ca62e2ae1bf02a501250acbbc014ca28765bd8f786b35d6a0a997dc86e961609d20a3d3317235c0ac6debfa6eaca750a746d1045eda7008f3e4443ad6ad3b3426dc1cea6160644549b888e84e8438	\\x0000000100010000
45	2	32	\\x4780930c259ad8e9224c85827156a284c3b1f38c7f0f6ea164fcc49035eead1adb8b92fc947746a07e02abff204014a6fb03fd9b3edc32def3547858db8c220d	87	\\x00000001000001000e7fba6ee48ff5d27a43c8fdb54606c15a754aad3bb15935c9d77fcb593b50982338284fd6573553248675efb887892caf41c99da9c3459c7fa3a1d085bb543e588effff3f8214274fb7d39edcecaac78602ea3464065c9f7688afade2328150bd71fd8adab23a49d612f6675579b615ac9c6baf8488226465348dda5a828ac1	\\xc38da1216692e1e5f911c6ea9d715aa8a8df5eed61a043a9d090d4bcd9af7035a7b483e4782c0a099687076174014bc660e2dca592266f906b80e36a46c793f2	\\x0000000100000001a08640767d65c0d41ac88a0fc82b4a368e1db30d5563ed741a8944850b8f27ad30870d0bc28f903de53a5ebd57345a90e40b46cb16cd7bc7444805b5c97f9a91ad151dd4ec10d5c5c04b2e12f1b37d565cbcff544ea7aa5de66dda2ec65a8abbe09cf93291c6ac624f7a32e6da6645ef64eb1074158f3e70ad40787fc12a7d91	\\x0000000100010000
46	2	33	\\x32110b44d33a6c64afb4ca3de2764b206c8f3342d6de250297a35d6836c1ffae0ab5412004dd0fa77db4a16e91939b4d465e2af6646ab2d5b2e319c1542f360d	87	\\x0000000100000100a8ea8c9cd18b8504523786695e8d9d5cb1f0584dfb0458978a0961586a7cef94ef6470a605ab477960bfe5da2f950f08f1f67b4d83104f8b0501687b61611270e5d3f2b28f3cd9453ab6abf46055f7017a060c6f7d39f2c974b9b5c576eacf7c2fe7d112af4322f9e474f60129d4ebedc5f9c41926fd44e0a13605a0e7b4b049	\\xc5b16bf1ad298b25f80c881d1fe056341375dcef3965a971a11f29d8d82a95e6c587e61b7f8d9252b4eb4341aead89e92cdcec45f9bab37e070ad7a24d8ac5c6	\\x0000000100000001501aac630fb46d387a5916c14c7b9ca71b7b39819b84dcd9cff97dfa20edfc51bbda05ba027a21bd6f69776154fc91a7f9417df1a854eb299ae1ca7e045c74c3abec51c9d7c51bb89605c7aa3b3ab7b9aff5175d63bebfaf9422f5ba18199d0cbc39e8939b89d299ecded0e4657dce92adda07742f637baf35870185927e9394	\\x0000000100010000
47	2	34	\\xe96bf09e65dcf712398b1aaf51f9987cb912697ee1a8e6d1f3df364b22fa89f8333989f75faf45fec707ee274c4b7a7319fee448f9710fd3fbc7bafeacbe1705	87	\\x0000000100000100913dd81c73732f94e4e241c03160afae13f6cfc0eba3b34608da4eca740ce3922f78b7a756f4c4d562bfcc79089e9aa32035732a08983b00029f3f71e9ac189bbfc4db5cc7a85f254b57fc93f0f178f0d5bcef527f62c1f613d698a46003b813e23459838ad0d733536a89666ac7e9bce973c30546fd6f071eb78fbc1f53decd	\\x5538974f402d172824ea59a55d5086585918edcd7bcf7c683a44284c4d8f165daae4648f39be0546979959f40e2eff11c66c1579c5250495c4b604e5db49f4b0	\\x0000000100000001b1e1931825cf0528598703b969056f2a76a7eca01490fe60e9845c59995991ece2b7a7e7c6d7227c38805177d020bdba343620e6c1bd1a4ccc623604dc3312104cfaf9857907fdd079790be242f604c2668ffc988e2dd9ee232ce6cce959c14156539c3bea7153ef9b7e50b29ff0071dde8964e2ccc6bae9d90c9f23adeacdcb	\\x0000000100010000
48	2	35	\\xedf04dfa207f324722e1004e9cdc1c693db3d68232647fc44781d4aff6560a43cdc2abb7eb89e180277e886b65a3b36ccb33b853304eb7827bd743fe50130f0b	87	\\x00000001000001001a328583a3f7144d495424f72fa09d322a60824cde1365974ffda371d915bedcf5417748faefffa01f0948bc437b2bd540ba6fe5c0a9f94db80c1904e94a4bb5d0c8b20093d26d84302eb3ac106ccb50edb7ac9417283a1c337a7392660c6fdc42e9d741c62c11585f67c3330a946b86181aa8cc1c6249f195a4fa56ebec3677	\\x660afbaf847608952f562433eb7fa1fe391ae24879b4349be0d51ce37294fe9ac9b6eb5b0c4f4c6a2116b0d899f3601f7f2a6e335a573d3cb4f047a1ac091e9d	\\x000000010000000122d2726da2bb6a3a90b321ebbe29808ce848e7f6709486e6695962d3685294f78896bcf9c8ed56eaa68180a4d852f1828ad706aa40308e88886889ed267c760d41aec9078bf0bd48595c4083f4fef0634b321e1772ea9a49033541257ea1680ccd5ee52c04535ba37fe386045f45144ccb85b1d3cd885c06a8eb3a4d56ed43ba	\\x0000000100010000
49	2	36	\\xf2347d32760f36832f9c096da0fa8a6746a45f989b1b390039ec56ebc7a5f33e383c9bbfd7e4784a51f57bd212f0ce386e3a51ef6b0e130bd081193470e92802	87	\\x00000001000001007722a8b092fc352f4dd0d8dc3b5ea052e6c3d350d25be0e547e6917e7ad10b1a67203291202f593e589cda0051202a88c02a500b2097d988f5e7cbaf4a81c27862cb627c95606c4472f018eaab9fdd428f3899ce4da5348f919e8e2bc0f1022b11477bbdeb3f165509b88545f2c66b005eb2e21561c5724da6e4e73451607f43	\\x7868f728a59e594df7e2cb0f0254cb97c465dd38219200a4753d574c11d87987620a82a25a61618f6151719223a9be9d70881c48fdc8389f884ec8213c3699c4	\\x00000001000000011929e3601334635e0b81203fadbe757c1191d61b94d60655629c4f30fde3ca453b255316d2507ff952de38aad3f8450fd88fe452b42f9e72e11f2b82dd0579f478ef0fd96ec87dfc76272b65d5427b76d77cec07bdf78144615f7ec6fe018c1f7af5cbb640418d5d6231b33ed10cf2d4d8715cee0ee80281d88cb19b4a35ac30	\\x0000000100010000
50	2	37	\\x01793ca6d1d2f872f52a7d3cad43fe911dc430e481b1e28f6e888fe2b4c3af1468bb721f5aa1162f594b75ecd0923a06652806c2516280e36fb419904e147302	87	\\x00000001000001005c618d32152b7980cc53d4b6fb0ac1669a2deadf151cd558677143bc8b740dcb7da35b91a8c13fa1a8c57d021c3d4862648dfb3eacf9fd79ed8ac35a05fb7d8d47e704ad4569bd1e369c0c0cd6868b05266adc647f58e962b0ebfdafe2dcd818933a8f30c587667e9f9da8901de5ce338664d603ff94bf9ec94db0d85e044e61	\\x510a85651d9ed793c0b678839266c625818e98b6338a37e26fcc5f356fd03803cfef6197d5b67d62379c7e1208fadd6603071407a6bcc98d9e7f568e9b40f806	\\x0000000100000001303516f56e5a17755ba3b44f248e331e30b7bce2ec01a88e73b1054dabfcfde9d1c1aa6f9b6e588d0c1eb77572090ec4c8d052b8d83f2a555aec1275a0c9abfbc0d22fccd83ab8c987cdf67b1b5c36e85375fbbc7945816e1a30a0eeaf752d1a49d8e70a0fc047c1cb6cd4bc3c59e072798c8fd2d6ddbc23cb27dd672fd87a95	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xc798e9220712cd05b280cd37a68e22bb87c23fa5ffe2cc6d9e131f7e69ae441d	\\xe02a028730b259196072cb9a05598503f6158f4be0fa36df2744ea111c344d2ba101bf4f242227665baebc1e464a61dfc6b08c4473db9b93ca86aad8b9df5bd2
2	2	\\x11fe880e8e88bc488def9f4bda450b9fe4e35f3707fea120fe834a15badca657	\\xd864ec14e7ab704a0057d4c007da844c4f9d6a0bbbebd573b2cf975edfe57004a7faeaefab722b7e6b6d2f05f66b666271325bcc825cfbe2290a790d7fb82383
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
1	\\x33af927a2005d8927810029956f14d586270aa8862b29d51db8ee9dc06980827	0	0	1649944986000000	1868277787000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\x33af927a2005d8927810029956f14d586270aa8862b29d51db8ee9dc06980827	2	8	0	\\x43b15b282f18c0573dceed5664cf8ced88b2854aefb1924a97fc3599c85cbfe0	exchange-account-1	1647525772000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x02184309e0b327cd5986ef8ae4f82b00729635ca33cc2843afacdc2a30d48e356732d2bdc90114508c8fb89df550ec7292ef7ee49454354118268e78c6f56dfc
1	\\x857b84200d56c618d1299175886392e4cf68e21ef5506f94f1702e93a5b2445125ed10756c72036e2a0d649f78db85e13556ebd632016471e0f26433a9a65a13
1	\\xb43798204943853078882ed28d37e6a566acdece620694b5d551f46bb51e291c1423cea1079085828d58823c63e7cdf944c1b0904be406342f0ac14c237cda12
1	\\x293a27b5d3089e324b656f7960172af0a59632de623e3326e7b3122fd03a1e00553b0d1d6b7b498266e6b83b4d79412098d4c61276bb363d6c2e0b13d3aaa916
1	\\xf754175ec33c5fe0eb042453d2fcdd6cdca7778390aed7f9d76434968dca3eed13a833cb9842192a9410a4c7ab0f55c9f98f2d564ad33a983378cfde6e58cabc
1	\\xbc071ba6506048a3da817c477ef9d3cb118b530477ab48e45362ac40562bb428ff4a97b98f8c8a896b7ee1877a85db2e75f99509ffaeaac1e760ec163ec76ec1
1	\\x9b11971f1d169807e22d9c6430111f0cd5057ddd394d206cefe3b0c4d04e5842de6fe935116f0f3f414f33034e721ecbdb4397ba28905b73d87d8aff5f58815c
1	\\x6a9ca533febbd9ad9e48a9c09417c0e918aadea46405261658fbb9969f1dba3ecbbd38a94cc9e088f5bc6b601e80d0287b80bd08781d592b98bf512596d5c0e2
1	\\xbf76ed6d4d7e270cab6ac1ee9d15e1db362ab0da41075e64914604ee7f9df2627cdbb6db68c3bdf63eef8f0b630c8a45ded98619153d2bf8476121301d925ce9
1	\\xcecaa66540e61373caa220b1d6476a497350b5aca21c2b8cf6fdad7f67175f47ebe3ec48f1fbcff7357a73487db40e9e4b64ff6db67c2498853dbb2d52344fa6
1	\\xe40a229a5f9c3a75e33d47f3605ce4f26b0e135aa4bf2a6f535fdb3f061f53c0e9cec4025a849be462664d78125788dd5b9b630d5b65320815eabf0e374614f8
1	\\x58d852f6c889f0d53a4e4a0dc956cd361044810fcf1489beed5adf6fd38e5f59396b35a395994230b8f4a98e389c38ad1fb3f5a03fe0615b6b68126e28aee40c
1	\\x446f3bfbd64dcd76a463d9e522bfaffaec66677b741c8a2a2fd501804dd5a5e6ab3c13b9a2bb211e675c0db5449cf0b5790405a7b5708aa9dd7152f79178e454
1	\\xad162a78b3f76c7af255e3e7915cb0da96fee2ce8a970ef7ec1a68cf555696b28e068989ec2beb68de4e611aa6de37a07b7a774c3af7578e227356f90b9a8ad7
1	\\x470e5dd544f13477522c82596af24bba856bf0a3bebc6f91d009f20862c06c210dcac4370f4004d38df4d1b7c88ecca152edfde00a0d76666dd8171857c59d17
1	\\x14b47e077cb436e4ee54f36ee3016466b68b2efa26de8913c3e543fe1ef7fb2cabb1d1a54e3f57c3759589d2659930f186da3af70b3cbe86d6646796d5f96f40
1	\\x8da8a1585013ea68190abf7a0e80110bee1f74e96ee469c1514be93dece05e266806f7c547dc75b50744fd1bb60184e61167c784a342b074b1e150d4d15111df
1	\\x31feea96c00e85d16eb8e3214c71fb8689b30a1a06c759857120c5e00aae0793614415168ee0250866bc0286039314726204eecee666354d0d82df01b2430694
1	\\x02bea694c63c0170ae168e00e3c87cd77c15f09097339340f3057c6d1ef931e927a6c02f5c9c3e4c6fcc91d7ebb60cfeaf9b7f76b172c61fd546b72931fcab9a
1	\\xb3e07a0765fcf69d16410d825aaecd75f1eaa96b2dc100ef71e2326571d9f249918d84ba0b58214018b9f044d638f34f686ca009c355261de20ef2b73a2c0158
1	\\x7bcbecaea158ab1976a0c45eeaccbf5cc0d0ed71ef4fe5aed4a2f37b6be915115b79b48f2006c548e6ce161dde823087737e38d978ef04f239b57340ccade777
1	\\xfdea00c3d09ee9d4a731dcc44fbc8b79779165cbf64492456000529e9231b3b82bc44ebb1f2a401fc837141b9cc19925f98a22f9003e83a779bff9524f31493d
1	\\x721fbd83528e0d9c9901d28f64fe5de93f78f5b66db685b430feb4732eaaac372d34cd3e339dccbcf0dd83ec3f40bc0c8a0fac304b0be9d0e98ff1b6f763ccf0
1	\\x2680382989cc9e768972e297c20f1811c4ef32a543863fe4880b0a9315cee79b0a00a445f7e1a4ec3b308e03d0f0bc8e9d24950c1c405e226fdc91055c57a7f7
1	\\xff117a49b2137f38eb825a7ed27f3025aa47bc68015f09f3cd14ca562218086a1fb95a119463f683632a4d1da2128f9ba9ad798a72477977293e4ee3129d0042
1	\\x8f05db7bca3d20cbd801bef18a21e6b205c4e498d4268d9def924b66c5bc7f0c190b68349809dca79592f346bcafb94762cf142d66d0d04ee69f6c6b10546899
1	\\xfdc2818f50e9242bb5230d334d5caf2d9b3fbb0b6182d23611b443c2bb7d335dd1e6e871bafa9c443fa6e5928b099387040a1acd4ece954409a577efff0f242a
1	\\xf99af08d2c73924496327c956306ae22fdb7a921e80b54c17fc05889dd3c63a21ceb8bc9c39a6d9c41dc4a3b7c01d6e74128c4176acf9f7361be9967b9561ab1
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x02184309e0b327cd5986ef8ae4f82b00729635ca33cc2843afacdc2a30d48e356732d2bdc90114508c8fb89df550ec7292ef7ee49454354118268e78c6f56dfc	5	\\x0000000100000001119b705e4b1a8cc333729213952cf3d20920fde846de5228c76f7de05729d7b9820239dd3528dd5b532dc907eb253c2e8ec3b3c69d06a437532d059ea01fddb86a6e18c0bca93553051a3ae5086c64cd3fd254c3e3c1e8ce8f61cf874c99d804934d57d8977a2c5dd59d6cde96f91be76736629b5059e3d68e240d1697ef5dd4	1	\\x63bd0b1fd4a4da1bbb1126c233b1915503f50e08488c26b0d23aea5468cb337e74220ed1a204df090c9769b7892107493d49ab6013324aea4730ad712600490c	1647525776000000	5	1000000
2	\\x857b84200d56c618d1299175886392e4cf68e21ef5506f94f1702e93a5b2445125ed10756c72036e2a0d649f78db85e13556ebd632016471e0f26433a9a65a13	228	\\x00000001000000019c68ec490be3bb438123725645d3ad87b54654a98b53de30e7b06bb6ce5eba5be318606131c36626aa28e1b1970a7b6150c138481569eb7bc35bf9aaf8ed30d1ad9fdfc378f8fcfe39d228a479c38ebf196c17668f593ae8ed26afe3211cb0ff6c129fa6ebc96b04e74cdbd524a514cabddc64860ac5b371cfe29cb66defd49f	1	\\x6b218edcf373bff96f1b21073e2ae0156cf021d1add3b11bb7f6e02539908ee4db41946310d5fc487ab5e23a03f0a859a46291276f9e8ddb52857a4126232f09	1647525776000000	2	3000000
3	\\xb43798204943853078882ed28d37e6a566acdece620694b5d551f46bb51e291c1423cea1079085828d58823c63e7cdf944c1b0904be406342f0ac14c237cda12	402	\\x00000001000000019bae94f7bcf7ce51f585603976241498e2fd2ab4eaa785888588ec28ccb27328bda33edc5d768951024b5fbefded2c66e250b4f4440727a009de427311a3765dedd22fe544cdf0e396849e35feb5fea0745532b732a8afb5ee27f5ffd764cd1510e21ad3b05b0ab993dfc2ed9356b2da782db51a2698415cb0881c9fbd216037	1	\\xa3682e00d548d957ba6cb120e5f7ba08c254c3f7600428b4e95603acb5fe8a3df9be459afcc7835effc8becb39fe5772657955756c29e444943a28640dc9cb09	1647525776000000	0	11000000
4	\\x293a27b5d3089e324b656f7960172af0a59632de623e3326e7b3122fd03a1e00553b0d1d6b7b498266e6b83b4d79412098d4c61276bb363d6c2e0b13d3aaa916	402	\\x00000001000000015b14ba784181bc09526490a94fa86081a9c4fa29fec1ea6294f22e7dd0d10f8a5693b4c4c37bfc90def043747ec9a9ddcbc7a6cc9d441a7aa3402216399688b640adfa080423fdb2c8918b1deae7df741c09324875f46c833ce4599c815feab223a15fa902257b60dd9bd9f10a8661ba6b4063aa6ca35bc9df007c3efac1be03	1	\\x8c4bfbf86ec68eabd9196b1e726fd02107946d14f3001edeedf8c2237297dc730cc7de994deddaad9ca12daf4377f30c304f2823829174de9351bfc1138d9002	1647525776000000	0	11000000
5	\\xf754175ec33c5fe0eb042453d2fcdd6cdca7778390aed7f9d76434968dca3eed13a833cb9842192a9410a4c7ab0f55c9f98f2d564ad33a983378cfde6e58cabc	402	\\x0000000100000001658fcee3b7b9d11b57420812137cb8253ac942b24bcbf1401b833d4dc48fde4b4c549e5ad63a465ba2a17f21a81e98f2ce2d4bb1ddc1979e3af80e605ae5d89f9a9dfe1830e314720ddb0de9c44039038186fbf5abd9eb2ba19d0107a4da3365be5e98980159fb3f1c07f5635c471fbd55d195c8436ae2bbf70c8f5cca2effec	1	\\x68a100c51e620ef0db34931a60a59fb7a57c7416333d588ea5394818a34036f290f86587c6de5cd762bdd3ab0c67f8c40ce90cf3523fe2694fc0b0fcad585e0f	1647525776000000	0	11000000
6	\\xbc071ba6506048a3da817c477ef9d3cb118b530477ab48e45362ac40562bb428ff4a97b98f8c8a896b7ee1877a85db2e75f99509ffaeaac1e760ec163ec76ec1	402	\\x0000000100000001da24409dec4845045df7f1f716d8956e2895a1a0e40bfa1ea5f5a0a30527dc96d9167b93393609d69569ff646ffe4cf7067454cc0921ec1561630697ce6f9c24cdf9d426484d0fe9cf45d78e6f31e87c489605310180b77b0eb283000b317616e24eab839d7241b80601dd13a7cbff4402c2054452c7bdb251ef318fa790d40c	1	\\xcca3d75d688ea76ca30c840a1081756cbb36552fa1a60909dc4913965396ec7b70f59544e5dc17c2e76b4ebe7ed4795be310e672b085460141b45740857ca403	1647525776000000	0	11000000
7	\\x9b11971f1d169807e22d9c6430111f0cd5057ddd394d206cefe3b0c4d04e5842de6fe935116f0f3f414f33034e721ecbdb4397ba28905b73d87d8aff5f58815c	402	\\x0000000100000001e09432ecce5c7a7339ac707ed3dff98f8413d1a5e0e0332880461f72c4fdb4d5c65535d1470a5c84af744ec24ee3457e69128226c6180134bfc73f9be94b4034e3df8d9839beb2a8c25b5b23d148eea152ea5e08713cb5030b855446560c84fc9ddc82972c32a6920e300544e9736f1941ce40c1c8ad1453cbbeb81ea9ebeb6c	1	\\x6bbaeaa3fa7e75deac6444587c9b91af93ca7403e5de4d2ba5bbd0e4fee3a915c28130809a75ecd865534859be6c48d2381bde5b6cc6566121226f20a198b00e	1647525776000000	0	11000000
8	\\x6a9ca533febbd9ad9e48a9c09417c0e918aadea46405261658fbb9969f1dba3ecbbd38a94cc9e088f5bc6b601e80d0287b80bd08781d592b98bf512596d5c0e2	402	\\x000000010000000114d6f480cf66b1adc750b32200e6bd0c481b8a90fd257139a5e6708ea4b1bef1757e11c4c8a7ab29bc98107003a80d66773086bdf4ae8583362a04f47c016566f7646b58d0028154ff4e75c1c10eb5bdd9bcc9193ca6060d1365337e863d6bb74b018253cc10e5dc0b412bc6f124e418c6f479487ae2585075d6871c220778e5	1	\\xc451e7aed159395e68b4596ae90ace04b7ae97f5f994040008000991fbe32bbd70390afb592d66564a4fe16275c815eea6a561aadf8f2350cd9afd048c45ea03	1647525776000000	0	11000000
9	\\xbf76ed6d4d7e270cab6ac1ee9d15e1db362ab0da41075e64914604ee7f9df2627cdbb6db68c3bdf63eef8f0b630c8a45ded98619153d2bf8476121301d925ce9	402	\\x0000000100000001ec121ce026b39d2f72b4209e126d6716ed910397264f01648c2d1f25a820d097a24fffd2bdc8e6af6abf006901d7275c8c3cced43597ca9162e84024b93a89c357f97e9673e70dbfe1f18b11dc0b678cb7a569dbecbc9711b5bbfd8fa094836b699b0ec775aeba9be6641e28a27e4ba3b31a6d8252b39c8f4cb5be5d7bd54be2	1	\\xc524208111fdf33ebe159c187e8d990bf6e2edf075f7361148a6667cf317d7d5bee95d5588ddc78f00ca8dd932be1ba084b228c3aeafbe392e8068188a028007	1647525776000000	0	11000000
10	\\xcecaa66540e61373caa220b1d6476a497350b5aca21c2b8cf6fdad7f67175f47ebe3ec48f1fbcff7357a73487db40e9e4b64ff6db67c2498853dbb2d52344fa6	402	\\x00000001000000017b1b872f62979c52b1637efff7e91113317e9394f7d32a68721533c1c08bc258b0895021b379782807efd22d1c8f34585a5aec23496042edd8a440f0c72da324c7d6574f4f8e09fc2fbb96b5dd57b6b877e1fcd4bc74f1a275b3b42cf8f3dd791f089fa90a2f8c81f56ef552a3d146a5ecebccdf8fcabbf2bebc0666ef1148a0	1	\\xcb88c9abdbe8b33c9193f68ba136001008ac4be2066d228e8e686a51a820659014aae398e67980e5f0df33cbf53aee6066b4e3166e9a1ad097a21b71f8758006	1647525776000000	0	11000000
11	\\xe40a229a5f9c3a75e33d47f3605ce4f26b0e135aa4bf2a6f535fdb3f061f53c0e9cec4025a849be462664d78125788dd5b9b630d5b65320815eabf0e374614f8	132	\\x0000000100000001752a4b2d491039ec09d5cd6e773f6522c84c88368eddc1353e1b8b265f5a73e0ad1d7d93242336dc15c60a2bc9705f4e637c3f4cd8e5fa86a7d9642ba5f077d38ff00f13d86c01211e477bbb6755b03f23ee3531225cdd5464b38aea0ee80075b8f1e63225d99ae1d040594a56e3b8aa6c36e9b78df4a7a3eb40c1e1948ff67d	1	\\x6d6f3c568cc4cf24cbeeeeb589a086d69ee4bcae7744969aeda63d32eea6627708a42af43713893412de5012a75e29a66e44df1872bce60453c63949a146f709	1647525776000000	0	2000000
12	\\x58d852f6c889f0d53a4e4a0dc956cd361044810fcf1489beed5adf6fd38e5f59396b35a395994230b8f4a98e389c38ad1fb3f5a03fe0615b6b68126e28aee40c	132	\\x00000001000000019b14b794d66684278560f274438370d94cc005d5b9b9124fe43f329ad4bf5cc9e4c834cc9a28f0467918abf348f2379d287c3be1a7e344af02f119b8eaaa9c7c36bc27728b1e8570061df0e04a95724e02925c91a34277559e466c77df278ee424f38c4384f756df907fadd1a9efd296f0f69baf410e6f6570807acd4bdfb734	1	\\x00d9ef9c7574ef4f73f931fff0a668f02ee605dc497455f9e885a90795b02679b725c0f89dfc8d1c142b3cba5ff065137838a375e15293a90f72334305dfaf02	1647525776000000	0	2000000
13	\\x446f3bfbd64dcd76a463d9e522bfaffaec66677b741c8a2a2fd501804dd5a5e6ab3c13b9a2bb211e675c0db5449cf0b5790405a7b5708aa9dd7152f79178e454	132	\\x0000000100000001a2b0ee8f4a7a2da66402af6db6e4dad4ac32843acb33507144bd2cbc5140cff939e38ef38d046703017a193d0b9fb03e3c986a6d252d16a8c06d510c9ba33426fdf18fb2cdecaf4d463e6fb40d2dc4cc3ac43ff169124bbd269de2ca82ee4819b8b4f195a497b21cf34db04e314acb5a59133f87aa8fa1a1d1a703984653d8c0	1	\\x00b7bce0120f2604fd3ed123acb4c4f681ebfe0e40f42be920c79dc632add0170b1f67b42d1aeb6f1827c30ae561d86bba8a9f1985ce15085bc47db958924509	1647525776000000	0	2000000
14	\\xad162a78b3f76c7af255e3e7915cb0da96fee2ce8a970ef7ec1a68cf555696b28e068989ec2beb68de4e611aa6de37a07b7a774c3af7578e227356f90b9a8ad7	132	\\x00000001000000012558be4164f340177c586c796b4a1bc8e890b5f118e5bd3ca0ac17fa569c2b9632546f12492eae0ce6280566f7e5c7c801659550710014add136603f6fbb8ed8b27089ac808a30c33a78d11c2cd27b215560c965669f8a285dd3b571d9d3caf2417acd44254d5427ac7ab0fd22a736d855ce7f881d3fc0b72c4c88013eaef4c3	1	\\x85071909c1200d735859e826c600a5d4441691e42b76e1cd0f8d5ff352c2aa68ed25c291fb7c867bbe268f8206df0218a529626e03e1e669c7deffd17624330d	1647525776000000	0	2000000
15	\\x470e5dd544f13477522c82596af24bba856bf0a3bebc6f91d009f20862c06c210dcac4370f4004d38df4d1b7c88ecca152edfde00a0d76666dd8171857c59d17	326	\\x00000001000000012b98689202c6ccf7f10c0b529b71532aafc9ba871063089df5fe3ef501fc20c6520d32bc4f67e07108f7232dd8e9ca8d870d3c57936a2d30e28e027584f5fb7dd5d5dca3a4adee6b32daca46040fe0b316ad505deacc935d08549d6666466b5396ed6d264320ad9239cbadd2592f4bfd7126cd0de66881a95523427800d3523e	1	\\x4b76f9a86fc10bcde623ba45ffbe4accec656681488f749add483b4dd5181a29606d5d4783d2a30d6a68107f1132f243082acca65f70c5652a0506405def000f	1647525787000000	1	2000000
16	\\x14b47e077cb436e4ee54f36ee3016466b68b2efa26de8913c3e543fe1ef7fb2cabb1d1a54e3f57c3759589d2659930f186da3af70b3cbe86d6646796d5f96f40	402	\\x000000010000000183159a57e312fc412edffb7a3afdbf3a0ffb30422f6b8602c66728dc20fa0ebf91fee0174f7bfcccda0e5c370d4a60caf0173cbcb7824203db7d60dccef2bc9694627e10427b3a7f7d23f516e33a4e7f4b56b3235a2d68a2d4ceb0fe5b33390ca615b904ea38af7f30df62ceac5e2337ae7fdc5180fb20381365ef49861a9508	1	\\xf389ff9d1b750f0b986843c92eb1d17e0637e5dc345943fd6ebee167582418c3f93bd55596cc9df93dec94b16423d90b3e163e261c949ee71b6c07f5d20c630a	1647525787000000	0	11000000
17	\\x8da8a1585013ea68190abf7a0e80110bee1f74e96ee469c1514be93dece05e266806f7c547dc75b50744fd1bb60184e61167c784a342b074b1e150d4d15111df	402	\\x000000010000000112598ebefecc5776a79f8ccf505586eb298c7858f725d4b03036a9418f60a8efa3ef1164d6a1273609f0a3cb2cbc02b3d4252097e9e9ed37fc4fd8cf63d5898a27c866adc486f746feebd875dfd7eff0bdc1ea4cec3cde645d1377cf89ed4c1f8e22588da63598216622b5928819a57795180f5734b1083e9bcafa90bd9baa3c	1	\\x39805f19016d162d716270b2d92cb03e68f37f7def69c5f47f67dd69d6bee9f50793c698c5b253dd580ddb98289f14adb98cdc7b69c87309a4d9594c3c82110f	1647525787000000	0	11000000
18	\\x31feea96c00e85d16eb8e3214c71fb8689b30a1a06c759857120c5e00aae0793614415168ee0250866bc0286039314726204eecee666354d0d82df01b2430694	402	\\x0000000100000001239e29306cfddfa65131fc2fef149af0b00d4d3548279c4e79e759cf0a6bba1871aa2e0bb4503a9c1a06c8eab679759f0b5e46f4c11da46890a0aa1a50ade6df979e0024cd4b155677ac7d966d8684719ccaa674bf468f017046de7c463feeb02be2fbfcbda2cbb1b598620187b5e60aafeaaad56ddfd6fd1306f85ea30df9bc	1	\\x0300cc0f7d290c8984263633202fa4cb475ba6cbe2c78a18f5b2d9215a32096be9da6f6c148e83b65bc3f7ed9d4fd68f830f487cec2957a39cb3e4709dd9200c	1647525787000000	0	11000000
19	\\x02bea694c63c0170ae168e00e3c87cd77c15f09097339340f3057c6d1ef931e927a6c02f5c9c3e4c6fcc91d7ebb60cfeaf9b7f76b172c61fd546b72931fcab9a	402	\\x000000010000000108a657836ec674e711bdf3b3d51b0562a562810c9133ac2f604364b4be66f536ed0fe455a4f008b27d45cdc134ed5b56483271d0ac5543341cd1c470589cacf7352785001db29a6505031849f6fbec8f494817be300f97f99b2084f967decca1859231bf2ffe6b94cec90160210a4fbaf05603d4c8117d8e8d75c1b1af6c6298	1	\\xc8ac7affa8b1dac0007c04f53b13bb8f9cd1f708b1e9568c60ae2c1cf248e08ffdcbeda3993d2caf75ef8a19fd6ad3a3ec813a87c3bb91daafa96b165c56570a	1647525787000000	0	11000000
20	\\xb3e07a0765fcf69d16410d825aaecd75f1eaa96b2dc100ef71e2326571d9f249918d84ba0b58214018b9f044d638f34f686ca009c355261de20ef2b73a2c0158	402	\\x0000000100000001d46842bf3762553d494dd341e49c191b54d1a679a942b3835851883d68cba9a931c5920b4e38c6a1d8563111f378299bc9fa66137c980cfc003ca5e3c10ad17141e7c34d6aabac9e552eea3f858ef19b0d22ba6dc10963faa8b7820d724fa4bd99efac60d8fabf50f109f2dc0ada21cff469c298bcc52bded91f5d82524386e7	1	\\x9f9eb760d95ba71a62088120f33d550f6c0d06efdde2f415052e4abeeed9b66dbe727cd8cd729eedaa99b95709961d2fd8d6d94af72064ec184241f704d8e60a	1647525787000000	0	11000000
21	\\x7bcbecaea158ab1976a0c45eeaccbf5cc0d0ed71ef4fe5aed4a2f37b6be915115b79b48f2006c548e6ce161dde823087737e38d978ef04f239b57340ccade777	402	\\x00000001000000012dc64752eaf6acb308e632212d2f9bafd5a8371bc2a348b5ffc54f0cd0bcd46a91f41c47a53399b24953a223e098be3e8c35977026b64ae48c3198d682048e57ac0e3e0f8fd5cb01821a2ec92bc3904eef73d099dd22f530c38261b6c276c7210b5d55fe521a267b8d6471d6c40b46a8fd9dca6aca7283401975d597d10b8928	1	\\x4374970a7f273f45fc21361c11c67e10dc69848a819b1efea7e99a23198567ba4d995aafd5bb07c8e521a986b695b95a48ee8ca9605ebd9758ffdc71dbc72a0a	1647525787000000	0	11000000
22	\\xfdea00c3d09ee9d4a731dcc44fbc8b79779165cbf64492456000529e9231b3b82bc44ebb1f2a401fc837141b9cc19925f98a22f9003e83a779bff9524f31493d	402	\\x000000010000000142569f31a3e976cfc13f0c32f488ff0a7da778615b7ee306a2358c00a8e11dda11b6aee8f8fc014ae32fb95a6b76709ce71ba257175e911d698e4b32c0abd6318117ee15aae958d0de5a0f7132eac34d25dcb4cce4d7570bb83615d895ea47599c2dd1abda17f3d7a4fa97cbc5db46ca71d16934d7212d5a5ef41d512b6bea54	1	\\xe9d8c093542f4e24baf101b4b4e4510d9eb736074bca20adbc4b475b5876fa5ffee843b6498743fdda6fcf477d09071640e3b170b6bbe22a360cd61dc0383905	1647525787000000	0	11000000
23	\\x721fbd83528e0d9c9901d28f64fe5de93f78f5b66db685b430feb4732eaaac372d34cd3e339dccbcf0dd83ec3f40bc0c8a0fac304b0be9d0e98ff1b6f763ccf0	402	\\x00000001000000016b6e6179e13f5e86cb599083fe2c94632afb3b16cc76011daad97171471144145968602dcfc0a681cb0597c18fc2eb8d775bb9e8531f96188429149b8ab6efbdb70b587653876300d4149419df2830ebbd1b046357d2720aecd33e553cdb764762b1afc28fec926612ab6a71c4c54b3300644b7efc52c17ad3b201b1bc1dc687	1	\\x5166d09267859d456a7988c3302d36263537c7473032fcd08a9bef2dff3b0c18a7791496d922832c71a31bf0ab1409c51fb76792dea4a87bc26d354a18b92f0b	1647525787000000	0	11000000
24	\\x2680382989cc9e768972e297c20f1811c4ef32a543863fe4880b0a9315cee79b0a00a445f7e1a4ec3b308e03d0f0bc8e9d24950c1c405e226fdc91055c57a7f7	132	\\x000000010000000148a6d97a081e1d874bea53cc88b24a9a2a9e51cbc3e084ce5969251748a76a3b346c4db00fe515ba5772cf7b0ebd133d9b68674d3022858d573d3dd38335e0646e8a48d769010776d5b8fdd9870c12a9566349007f480c821411f07ced87614530539e1a80e790af3920c91c1a4c21f9e629bb0a738c86bf6c8024ad3c8b7837	1	\\x2db68a01f38039f124aaf57d4377c91d87486bd3900227a801d0b77947cebe7f6f3a1c0e3fb22cff8028acbdc7fc027d3edb444af03e9d69a439418624b8aa01	1647525787000000	0	2000000
25	\\xff117a49b2137f38eb825a7ed27f3025aa47bc68015f09f3cd14ca562218086a1fb95a119463f683632a4d1da2128f9ba9ad798a72477977293e4ee3129d0042	132	\\x000000010000000171825a74d9b326c0fc2b7bf6494edd7b161e24620907a7d286562376ddec16eddd5be882bd62bf19dc81a276c5c386a22b81d6fd51b3bc5020e559799f0f34f4f5c5f36f79c7899ca2600d27fbd9ed03db584dee40e243248b2cd6690dab876c2ae04fe77de7e66a29c3e5c56b1758c2571e88e163e6621ccad95f4f2931eb5b	1	\\xa64a305afdd2639d137aae39fe40ac83731ac3272a12b66275a59af276f809e276925bb7d47dac0c70fa733d42ee9a8f21b66d8e25434f98ab912f83415d9c01	1647525787000000	0	2000000
26	\\x8f05db7bca3d20cbd801bef18a21e6b205c4e498d4268d9def924b66c5bc7f0c190b68349809dca79592f346bcafb94762cf142d66d0d04ee69f6c6b10546899	132	\\x0000000100000001b75a6f1496a74318ee6cd538b8271f0fc168b64d1ae36c84c616e03a6b7944aa284d01f35321ef6e025865bc33a96163b67a76cbc21b0278023b1d3deabacce16ce96a63d995bf8f3d89374815e4916352d7a7caa239f5650645cf7e251257d9925bf1a43a2c57c86f4aec0d08217f246fed036841358ef18c914b4eb41b7be2	1	\\x970c824978e0d2ba4879697b15b4eb8a4eca152d3a81fd835cc5a56ab968ee790976d453a028034b2cfabc03920f74b997bdab7c66bc3bd016fe5b9b5c2f8001	1647525787000000	0	2000000
27	\\xfdc2818f50e9242bb5230d334d5caf2d9b3fbb0b6182d23611b443c2bb7d335dd1e6e871bafa9c443fa6e5928b099387040a1acd4ece954409a577efff0f242a	132	\\x00000001000000014125dc51e6f07abc3315ac6d668204dd164881cd96833733b018c7d189f7826825ef2ab0d673077e2212fe7caf786c5fe4517f87d3311bc70255db61d1457ec2ae5a0d79d4e90c1ed6151a885e328e7d3e17159e5edddfb3cd8aa13c07ecbdd501f9c48110d23f999e275c2032f4ab0c64938537d8ad6e60ec1777c46ffb71f8	1	\\x58ff774beed33da2ce2b285e07458eafd5324acd50e3c83dbbe09f3e1744f1bd11ef3a57aa54ddded68814bd70c5abb8380d12f06613d00ea66ba1573fae7208	1647525787000000	0	2000000
28	\\xf99af08d2c73924496327c956306ae22fdb7a921e80b54c17fc05889dd3c63a21ceb8bc9c39a6d9c41dc4a3b7c01d6e74128c4176acf9f7361be9967b9561ab1	132	\\x0000000100000001b8c42f3af9f9c1be54c66c13b92803be39cc65c9febfb75e98a80181a718ed63738b34be48e63365def7e8ed6a2e37a18d70bf9a4f6c7fffef91eb4493a552715ba92515e03eac646371924b43b24a9c8005cdfc7527af152bcdd78f6eb93a1ebebf8b182d630e577e701e6688b37ab188297fd8306ff95905b2621a7eca4769	1	\\x57be4901a7deaa0b3d01f052378119a788f600e6043171d4ae8185ecc54f7149d356d06011c1cad26660ff68c8748bed5a54919b4e5b61b440df2eaca17d4201	1647525787000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x658d0988f41a9a53f3d1f6449dc61e61b2bbd0d226d8de8d8f6cd127429e0d36c69fad3d6f4a5916398e1f3df8dd2f131613041953d82113986c2bc514932a0e	t	1647525766000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x9067ee1b0041148f1de0c2e31f6baa9bba133f8384cf76d12fb3bdedc769d7434a5fa9be4b52dd77f2af7baf8e1d05d76dadc10bd6a7d7ebe631ac5c1082a30e
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
1	\\x43b15b282f18c0573dceed5664cf8ced88b2854aefb1924a97fc3599c85cbfe0	payto://x-taler-bank/localhost/testuser-4j9pnhrs	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647525758000000	0	1024	f	wirewatch-exchange-account-1
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

