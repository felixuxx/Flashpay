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
-- Name: exchange_do_melt(bytea, bigint, integer, bytea, bytea, bytea, bigint, bytea, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.exchange_do_melt(in_cs_rms bytea, in_amount_with_fee_val bigint, in_amount_with_fee_frac integer, in_rc bytea, in_old_coin_pub bytea, in_old_coin_sig bytea, in_known_coin_id bigint, in_h_age_commitment bytea, in_noreveal_index integer, in_zombie_required boolean, OUT out_balance_ok boolean, OUT out_zombie_bad boolean, OUT out_noreveal_index integer) RETURNS record
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
  ,h_age_commitment
  ,noreveal_index
  )
  VALUES
  (in_rc
  ,in_old_coin_pub
  ,in_old_coin_sig
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
  ,in_h_age_commitment
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
    h_age_commitment bytea,
    old_coin_sig bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    noreveal_index integer NOT NULL,
    CONSTRAINT refresh_commitments_h_age_commitment_check CHECK ((length(h_age_commitment) = 32)),
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
-- Name: COLUMN refresh_commitments.h_age_commitment; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.refresh_commitments.h_age_commitment IS 'The (optional) age commitment that was involved in the minting process of the coin, may be NULL.';


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
    h_age_commitment bytea,
    old_coin_sig bytea NOT NULL,
    amount_with_fee_val bigint NOT NULL,
    amount_with_fee_frac integer NOT NULL,
    noreveal_index integer NOT NULL,
    CONSTRAINT refresh_commitments_h_age_commitment_check CHECK ((length(h_age_commitment) = 32)),
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
exchange-0001	2022-03-17 04:21:25.586648+01	grothoff	{}	{}
merchant-0001	2022-03-17 04:21:26.928565+01	grothoff	{}	{}
auditor-0001	2022-03-17 04:21:27.759983+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-03-17 04:21:37.735038+01	f	8c9fd39e-e632-44c0-8af7-e3b438b128cc	12	1
2	TESTKUDOS:10	NT1N9Z4YV30ASDABR9GM4ZS1B5Z7GNCZGA19FRWKP8AE1QYQXZ40	2022-03-17 04:21:41.474968+01	f	b9f4c9d7-5904-4846-80a5-40404289959b	2	12
3	TESTKUDOS:100	Joining bonus	2022-03-17 04:21:49.079536+01	f	f680e638-a373-4fa2-bc69-008702e027cf	13	1
4	TESTKUDOS:18	4PVGH75DPYAJQVBZC2QR1HP4H87MVFWG54Y2V0TD3TWDRP4PR960	2022-03-17 04:21:49.643017+01	f	55b6b2e6-a57f-406e-b8a2-8805662f0e0f	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
9c97f1f5-8494-4073-ab8a-ec4e4613ccab	TESTKUDOS:10	t	t	f	NT1N9Z4YV30ASDABR9GM4ZS1B5Z7GNCZGA19FRWKP8AE1QYQXZ40	2	12
d3b1bd4c-7a0a-46df-b2a4-0f398f66b116	TESTKUDOS:18	t	t	f	4PVGH75DPYAJQVBZC2QR1HP4H87MVFWG54Y2V0TD3TWDRP4PR960	2	13
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
1	1	2	\\xa0cce6a77f3f5b52d2e408832e47de04115ea8494fe6d4d03c263d97d638f9169c711836fe06fb84ff8b4e531661359b64cd54c91c826fa57813d9214dc03003
2	1	51	\\x7b21f8e50573c9af97c538c921cd4dbb8e9dbb3d5a03f1c41bb7a1333d3bdf8574b05cba41997cc06241c529a736c1d758c7950aff40d8cc4f1e815e75b2b704
3	1	147	\\xa5c828d17cb2b178dfb2888015d94dd708bff9c83a58eb0ad257994a038375ab95d5368cb35b43a6b2e681fc57e6aa093cb8219f266a0ec41389d1c9b6724e00
4	1	59	\\x91c6ace7248f4130f63d092a4e676e8bcd43505c2f8c6b79c4531e98c6944bcc3ea5806737c9096f3b6cd04c76f7082b6f36bbdb290a1b1de0ac2bd9d250d70d
5	1	282	\\x7f66c4edc8f4dcca7213d52cc1500fc75918ad12f070e8a51e53a5772f9c11157ce79f19eeedbeaa85166857844898ca801cbfdc04fa995de3ca9c4990d59a0e
6	1	127	\\x5c9702c254dc3041b763cd7fe653304dda9b7efcc98afb5314c06f63b86f40f9bd02ca0ba34b17f3bfdf715a5c6a241a4edf66879d0511e8111584fef60f0f0f
7	1	191	\\x306039c104b2dd0d0b3ce8a05e4fa95bdd8c9f7e9cc800c774c0d481a4b8b8a3d1b9ca9ea42cabcdb057a01df87b0ce89950eba06e1c31f0e9faaeecc59af303
8	1	320	\\xdf3de84c3c9a259b02deba3973cb9df0dd34068b6e80a18e7a4273dc243ede9e39cb8cc05dbeba272a9c0f3f050113669a0877486716a16dbf99d69e6d2ba805
9	1	248	\\xe26849e74d8d8124b1576adcdf1653accf67fdf7ab874fa45ac43987bb5c463049c1b7fdf01b711a8ae89bffe138607ae08ae99b5b103f3fbcc8a2db1c996006
10	1	74	\\x41baa5412fe064fe548b60ec4b36880e5bcb86383476c8d970e9e49cf30eae5ca9e330de481b226de3163db8aefa32961f97039d86a4c633e0e0cf41277d620b
11	1	367	\\x53b12593fdd0b55acdcd575d7fae5e53101b84a779ffb1e07952489c40493923adadffdb945112cfeec9f41e1246204465cc7af451cdfb5a3f74e2d71701510d
12	1	130	\\xba582379d7eefc3477a3596890324433d7e895759c1438a442ec5720f3cdb008c3672f95833c102146ded01fbc436a2cc13627573eba4d340d6f017ccbdb2204
13	1	284	\\xc87ccb0ba53183fbb4bd23c1799fbd9cac8ca3cb498caadf9f0384405e61b49c59bf77d9c8034197cdbd018236f4b1fdd8591f07ce07a035b66a59f9a382a502
14	1	253	\\x4e019c25bd8b5b1145ae02c6a392fbe1cfef0a0cdef263ecfb774c3ce5e5f26ea5a0c5b71fd836195113dae402d04271e0cdaa15b18b79624522a04778bfff08
15	1	409	\\x1555927b64d3a5ea9fda9d3719717c0b729f27d5f81975f1dbdc448f8f29ee3a1829f0e2740c4ff22b87ad5a079864893ca314288b0a15ceb82e91f0ef2f1c0b
16	1	87	\\x75661b977ceb13bf2bebbf617bb60351cbecdb70a7664eb9898f757d23907396bc708b41205bf9251b3bbffd6c361243fd9b492ac173b1f2a91626a9eccc5d02
17	1	327	\\x4433827899be8c611ab510ad9b69009d1061ae4ef11666a65b9ab017cacc4a3f5e67a212559b3beed2ad64584d9cb42f50115f8c7a752b0ff556309d66acf807
18	1	365	\\xf9c60787064599599989756c3b7f94dd36b7483b2fbe298fd55fd559ffe4f88c59f74016d1245dfb45550f60c543782f328d0f0a352c2de071b8915fbeee7d06
19	1	264	\\x01dc1c76761886c2fb8774865bcb160a5eb6c689008d8fbacf70a35919e4f0fc47898d4ad6b7caa6db8ffada253eca1b36d62382d3a831539800afb7e6ca040e
20	1	341	\\x1e8003b178fe23c06bbd4bbd85c69a0a36938f6fb8c277ab344d06208f07eea8cd086a9a4aa2994cffc2f247bb6731b772121855364b41bf3535c4f928d7ec06
21	1	82	\\x93043b6aa2494902d111ef8086b98f5a533df736badff6c323bfecb2c9f575eb298ee801fb7aeadfe4d38e1689b5f6dc69147efb7f323abaea316b3928d81d0f
22	1	97	\\xe147aacc96ad93400ae43bc799648f4040a207dbd8db6baf06ce8c373fd921e68e471fcba668e1c03b3e6e2f9fcb9b14b9c9c7f28dbb5d294296be0acd226803
23	1	141	\\x4cd01461544f33c0e1d319c5ba52ba7e3d8e23ebee4bdd7e7082fd34368d3395f5f6272cc8a45ecee5beaefb46f35bc7d9070a53521bd8093cef957cb8a86f0f
24	1	245	\\x76578a62d133d8c460570938e8106af10c23d9c9911a4dc901c6859da74d7affa09abd05828046c9a0d7d32d9feffde1a58682e7d888461ca72141ee773f9908
25	1	40	\\x2e1af16e1e990a40d520da6469129097257bac3b8e0dc352da23cf7fcd350dcf6229d26b3655276b1da7e716eb53c6fb89940a9b2d8c72df3ae3a459c029530c
26	1	109	\\xf15f31cc326f783957560f939275df6aced71d8da23be90b7fd19533f2b4425f919ff80f25b05e07e33eb8075e09799e427c6073ce418e73016ec212aba48c05
27	1	78	\\x9d7e0d4c0d68b91906e0592b807ee9051e0173d24e56d7568c625ffb6266e31bbeeb798166320611b84004eef2ca8618a898e9392ff0384647a88e210be6b60d
28	1	163	\\x720f9ad1cf86d7d48c8358813f7c733546bf4112974e36e6bfb34e751185f7362f77fdfc45590f9d397425d7062c81d74422de2f685311a51f314438c85a2407
29	1	197	\\x6b0341ccbcf41f11c2a9e375e387f824e8cfff6c5e4569efc6fa7cd167c88bf7acfddbdcbe0b9f67a4aea0c6b25b64bdde9dc164c2b7a54f36eec58e98a9330d
30	1	239	\\x3b2a19ac95c4bce64584b8c2b21354ce1f6f91e710193d4f6bbb1cea4ef0fe9e555f146d637e66a0b05930dc2ca8f1ef19b53d132b956ba447408b9c6b397106
31	1	257	\\x52a20874ea2a8c06b1da105b7d3c9f54f62b0c2db2969e08c8c7f47ec5e3840e5dbafe8af78dd8843e02768882a4db37659ad4c8ac93d33d637a5bcb0603190e
32	1	353	\\x5ff88903c778f3dd0ee19d53234638302a334d719dbf965aa5f084a7e0688e52fceec409821e5c0954c7fd57ccb451aef76e71ce08bb02a659d212ebf9385000
33	1	181	\\x46528b919d4726048f95ef2f917234695f24701bc51ebdc6828fea2f1e0f491069a8caa84b415dd09905ee99a0250e342afadbd45e5a9cde7c414cd217d08308
34	1	108	\\x478c397de4020d1c7a3a15c2cc1952fafe554695f49eeb122a12ebf54db844aef8c530e5477f08901076055e6def28e6a379287b7310d6da58edcb15d2381605
35	1	371	\\x4fd93cd053da6915d188b1b0f9e015a2683ca605f075fe26986c00dccc9dc262ea58741f4890dfe14220fa3173b435051ae447b4d61a71f02a952b41ce883509
36	1	386	\\xc8b80824ad523a82ca7eae84248cc85d115e75e07f147d2573a4399f3158faa6bd9e1428c0078b4778b3a81346a131e7d1b5857ef59930b7bd5583b9c225e10e
37	1	134	\\xcb93bc1b97bfd1d859a31ac990970d61675b7e1c6a15ba95f49471849f052a1e9bc0ecabded5ea76e38c85a8165b6673c3de569736d59014fefb95a9f2316005
38	1	94	\\x124f6e3c1f61e75d3ab171d57852ac16ac3760c3a560370d0ccf73040885de7527530d37ef947ecbd6be1fbc0bc919ab5f8e4f87106d45187031e61fa2e92a03
39	1	121	\\x90e85b2b6646fb0d744ce89a1ae3ffa94aa0938424007ddef8c3e8fea0502f0d12a61e2e430342abebdbe60336f6c81b6126f861fae3a3878f0af712ad5b830c
40	1	252	\\x427afa764460dde65c0c798ec66a56dc9124af86612b81ae9af0b7be56c539626fa9b0b314315bce5922589f6320f848b934ae6648b24cd796045c1f3a61b707
41	1	158	\\xd48c4476bbcfaf499b4a008f20e90f1b20e3a7336176b0f636d9b8a4efb32cfe0085f2fcaf22c7f89357aa4f6c887f255d72a743b569dcb5e68fb10fba842f06
42	1	391	\\x84a87df18c95c5d9b865598b7a42a4e0b37ed2d2b0433ef66a537d9cd1f394a7cea0f2935f5f75f2ee8b09d2009b0a245dc4f6c656278483057efd4e3ebc920d
43	1	233	\\xbcb8612ba29bd016bc506917c9166dee91d13a9d7d0967287b680502938c25ff286001c29e4adf67a460378d4cd48db25bc4f449f395ab58b1b8fdfb64ef4b0f
44	1	101	\\x3d63a3f35719bc741bc92086ffc6a63aacb11a986589ced11f2ba6b6075c6d188c970bd19801bc445be2f9c8c8a4e67a2b3d232412839ee686175d5ad7a05a05
45	1	214	\\xfd033e234b21005cec330915d2613c1d36d7ee53846db6b53a055c92ab70bfdf2fca13592db8fd62affd73597849ade8bdb97673767b65ffd1c8a2135132b702
46	1	30	\\x63021a1685eed02aeac784b4af6b9cf4337ae6c50fb9d33b71d06c0cefa4c0e0e321665548b3533abb823438c8da08e9087923542df9b31545ec897340e84809
47	1	283	\\x9b37d399219e236ec3470a02f4b15d6cbd3cfff7dd16cd9e7a147e9b1cb7e798b31c38c26cf47906b136b34831574d997cce2586e1ffbf19f266911fc9cd0900
48	1	344	\\x188464f30dddcd0c14c2ff26be280f0d8481a515eed37ba2c97435dec7e115c683921335923040f0169689fbfa8d1f2b2b9ec295e14e9db912dccaefd6ab6501
49	1	190	\\x16e5a3c720186592adcfc7a57e1f43e009f3bea2b4d6eebf580f069422f8b6cae1b21f833fdfe24c79910101a650d89eb68fe14f5b692a60bdcff8ea04495e02
50	1	89	\\xf2571630948ebb793502ae0f2be20d15ff4cbf2d89cc1bb83d077bf7a7ea5f553d52e781cec1d5abaa328f3711e14c255a80a25a790383bddf6a4a8503053c0e
51	1	33	\\xb76294b5f8ea946effe1e05b6b23cb48d623291d427eaea118ef8d7d12ef06813d852f9a9c2e8efcc3fc52c9fd6048a50c1b23b7af1abbd3d90acbffdc7e970b
52	1	261	\\x53e947f8d0fc2f553b2dc7304c7babe005e04af474bbdcb52c8af8d2c634686dd9190e18d36fc34c7b967255843b7bc340e25a91a13274efc1aa548c21703f01
53	1	354	\\x20a957b1e69201b26b3f0b59bd50f4c9b9e93805151913325ca513f789395e9ba686fd548c1ad03e0192c051feb1061c695c9cb7f2d2a052e2f892937772200a
54	1	383	\\x3f0be26067d30c435b99ac11e004e5c5312b66772fdab13241e8fec46ce31663b389eca4338fc35e524fa54a64b109160d129e73d8e079a910136a4138ccd809
55	1	295	\\x318b90ddca0faf427ee9e7e9d8c9a313e50fc5ef9c91e441c80443b7245a620755071c0ba81a57adee0ab50a780868a092e284b30961828117bbeb67edea3b0e
56	1	272	\\xbf48253e6d6331f2a03f370e206ba6a456f398dfe94b3ca4c6b2ad739219689215cf6a98ca42cfa8c8d50b58d76787f8738c85270c5a897704106b0b8b89fe05
57	1	170	\\x77c011f96415c1133bbf00abd62cecd4b63b2fe8d197f92f9f9c28bc917a646e2cb38146b2417aedfb12f50e651cafd891fb0c78a77a18eb80c06b95093f4307
58	1	67	\\x06798ffa6ca3969c6cb384669b65e075599d98a4cc64434c62fa732b2d1f094af1fe2f4fc46895571aaba56b93bd58d5c36d32e18a07dcb6a24b759c119a1e01
59	1	106	\\x3a23d5c3ba7a1481d7a3e7e2c35e5bcf86b5d2030e53f6af22a411a330f5efd6d6833b03e3f028b7ef912e0fff16403279cafe006ea51708056a20a416976305
60	1	136	\\xb6f2f7001fb7820b80514ecb18bf3cf3928f42094abf1fa0be8ccc77e777f3d237fc86f7a8511db510f0be4ea81cafe7e89b46e9e394b88126c89ddab75b3804
61	1	396	\\xd160f7b27fecbd254b8f68fb98e1ff59e04fa03b3e98aa0114ba0ca34d74ce1e3aed5a850f1474c7e48380a52247423b3e853c47b81540b0a1c9be247a43570e
62	1	216	\\x5407f5f10fd5239bc677a414ae3f34490f235122a76d66ddff6f0fcca66f8cdfff93ca00c46ee3f553c648f707bcea1dcbcf1d3cc4993ef0ee34fcd50fc3e702
63	1	326	\\x827131093b48055be89a5ec5f72473daa39ce41a4156af387195d0b67226613d8136b42122de5c2f513095a21639516c6c5285505829a77bde8ae9787d9a9e01
64	1	99	\\x27fa02e1120a2d26611e39d6cfa83c7c70f57fd96b43d20ce456cdc2e7efbc94ec80aa42582b1c78b7e1f912d861bf763642805aa2e073eff737c3b578e67d09
65	1	93	\\xe39539cc14b2d3a6ca1ce0fb40611533e1b3e1d56c82ede332a36c78796343ea73c649bec9fea5d019bcfb96263708864da49f03e5f1f061f3c60bf41bb9040a
66	1	263	\\xe9b24f20f8300102dcb239980e81842cd30cb8d33e0b1c4aab27449b6ed5abe64292a3f7bafc10d108bdbc1406a1766ccac6ce8daf417568c4c41f7a9935d00a
67	1	98	\\x57a930fa3d3bc0b3f26963b7d44b29fa896cbef15572daad2d9e7f9e91f4f6086143fba20dcfd6c30d20f6419f968cca42bc1b083c4dacb8d0a91d5355e23705
68	1	149	\\xf1279fa2773d1a3c241b433dfb415178f7576f25425e8ae8fb56bb15a4d8475015ccd494e3f9b49d46c21ac8c546298b8116326ef1bdeb14b5ff994ae84dd205
69	1	58	\\xb48fb76690f5e7b8b57b141788e0b0ed9db0cd5a76264e2e8cb70419b7087f8414749d6fb5a6ca0750bb49d631cf29181c929ebd87d59d8ba1f2cda9b0a54b03
70	1	377	\\xc8e80042ef6ba6ff21a0a5e37b89c8ab5888b0a28a57187b69a0cac9485587453a8b993aceca4ce5af6f58221ac210022af6dc8e73f13882a3e73851fb3af50d
71	1	348	\\x13539327dc2f38fb861eabe4259bddc212251ecdab3c8c4bf0c50f6ad2ece95fedfec0efd0f1ac50dd01795aca5dedb0d2f4f6f1c1b321f93901bc38e30f6206
72	1	397	\\x06cb5e8823d64362651cc058340a37d9dd9428cbb82b1a0d576b1065410d5538fc91d07e0942fb0fa5a0f86dc8cd33eefae01a85565e2df38470bf815c939800
73	1	413	\\xf8215c4c2e8325c22ded1ff2c74ddcf38b39d3780b937d9fd6da38275996e2d80c9433848d709d9afa3b49f93c426ceafcda3f26c0c52718b9329b9a9e45d106
74	1	213	\\x0bcd892ee722b03bc021feac648a16e7e051ca7125099d98ad9b405ef643200f62e76de3f71276e0175dc669008efbcbf4445ac1bd0618d43648fcf68c8c0304
75	1	38	\\x181d66c23b58a08db2f6433900d06e592d9452dc0d55b4eb708866cc07e2c46a54af3cbf9944eb2c7f291ef46028f9449c97d4b186c03279d989d97e61b4440f
76	1	328	\\xff82a0f82278de28c24bfa680827fe59afceb3b6724a83b9a6135627063a8faf1cb8b603f2ad07aaafbeae99124223bec37fe5854e53c4d76987436e9469e500
77	1	406	\\x47228b1d263919e8bcdf8b239fb03d216ba27d00f131d4d74163015e68c6627abeefdf7b6394d97eb88e346a86e2e7335d5df9f9f83ddfab6b2f5fe97d30e109
78	1	5	\\x72bac883270e803b9495078f51a519ac67919e9c9c13afe664e1381c785f63a807bb6cbecc4e3a1618a140dc4b9acc9423bdac51f3ad26ecf61efc4511774b04
79	1	9	\\xf9ccf14246be43bf4855aa0fd7e68eabee84c7da2d53f80a90f61eed34f2c5052fd544af6a4b05992d3fa01a7d1a3f249e2a488fd63e1044c9939ffe33bbf906
80	1	21	\\xc1596c359b460c7f6e61fa028568b9ab3be824089ff5bf69f37b067b2332df40023f8afe8c5e003f9a3d5419dbaf50cde50f8736b43366910df4648a0e1fa00f
81	1	262	\\xca853b4e85fdc7bd75c9aaf4806c3bdaae6cbdb61cf4b6991268a740a47985fc6ac2f27d7326c4dc428fb08be5c398616ed69a40a2518d0db965003dc365ba0b
82	1	296	\\x88a5c1dfac92c9085dff6b43ba631664c1cb9187fd7a5dc34c3fb3219f762f9a54624dfb30d42d72a887ee7d31d7683245ce2a67b9a0f3a0c951f0aa10d5c20a
83	1	276	\\x3af12f138b61a7f37e7ca1e347d51bd2e142735f6cbafc5f5e24dd9bf97bc8463297e88fc6c9d4ae789118c9d9c6538e0ef43bb39f79bdba6aa1e43d7b6bae08
84	1	266	\\x3f07fecd0e044621b0c0f97eabe48408b033b735e462a214d2b861a6dda5c13b2203dfa8fa2a052abe30f7fa85b707edfb119e6419b00e62e81d4b8bbca38c0e
85	1	230	\\x9a1b15281b06db1e9674d60577476c7c7d2280ff048b0368a4116833a7a1bf2a2130e8c045835abba5ea716b72f232d66b729206e0880b740db815ad605ad200
86	1	332	\\x348e99bd77ed92addd0833aeaa5d80a0abf68cec0813ebbb31d51083bb281eef6d003db8c33336001abb41d12b2fbd3880b46b8e0451db66cc64466d360a1b0d
87	1	300	\\x0bd4c7de1ebcc1d1b49fde5069fc53e2c41c220683cd8f3780e2aae3107120a9aa15103a1a795da7aef624fce257cd630da17548aa4c7ba3d1ff5989172ff70a
88	1	112	\\x868bf759ea785053d73bfe9320ddc360c326348ac5fabff3d8de043dfa64189d486794d08d0d341f97db92504eaed2a0b1358534ca957abee6aa5cd215d91101
89	1	422	\\xbf98bfcd53b0857c7b8c347449ddbc86b2ab2c8873a235cdd7299aff6d32fdd525424a992be89496d3fc06c100f9737bf6760982bd96c25c0432b810db810f04
90	1	56	\\xa858772f958fc393c4ecc3102c7947152dae28ee9b01c7df2f3d5572a0be851beef34fd576551804c955446e609ead0a049fcb393fe845c931910b69358fc507
91	1	178	\\x77ed3d6b51a8a6640f924d03179df20b183bacf4c0f98655c9ca986ac801041196cae5e2f987da78f0b2ff47985150374bae182bdb83ccd48d594ec725d81e0a
92	1	104	\\x661417930d42d17d6b1089e88b07b6e5762811c2689e53acb6253e15e17b190692be992f6da02912aa67aea15ca09203e9cf2efaa2948a97de42408ee5a21602
93	1	277	\\x45a4dbaf715555420b64559f325a52a5b2ce2211f0a97b5bf1c2ddaf12cf693c097de237c592fa516d312f981583f91e0071859f1971cd798d3c8494e573600a
94	1	90	\\x963e14f6c00e330b90f366d346d52dae91f2a7ea3512b1ab5d4f3e595a3ada5695f6892270bbc67cd0bea8fc24bf7b88993e0e754453057d6dbf4b7744d90704
95	1	10	\\xcce2dd2c0b8a03edf69fc10758f8a8cbf9831781b48dad205071fb1842704f5b029a65a374056b638581f5bb562a5a9c0d8858ba7cb1e1d69b58130e2803f304
96	1	405	\\xfbc333ca20cbba485ff53396f546d0786b6a5dec65e1fa12a9a728645c17ba09863003d78f94aace13c587f74007edb5a47cc3e80a276f2e56c5debbf7651d03
97	1	260	\\x9f52510c66f8d8da8bd80efddc14185fb8c36477b0e0ec92cc59ec07d746f72eac9f26d133216ecfefa5b08da6f41aa069a784efe7c42761730aedabbf2ecc01
98	1	6	\\x5b691f3cd0fb682ea82136f0a0a024b61b2d47940d007c48309ca05502fd632e8ffd7c65db852ab291b553afb411459c902a5263c369bebd9cc1bdb0bda3cd0d
99	1	186	\\x978bc8641f464f5c9aa0b2f781c2552ffdd30285434a14c7f98efda547df4f5204acc599633ce43b7224efe03873a5ebedeb5b2cd67e2e76d1866e340fdb4f05
100	1	217	\\x4207c6586afc3447ac6860bc956be5a40a7cbcd3117c4570e94e9bbdbf5110fb2a86094cac54451ef1f696387bd11350c168a74384d17b8be1e46a6cff405a0c
101	1	249	\\x20daffa26209cdd302a724c3a450d7695ba4926e14fd1079e8977048544c7d9c38b52f63502e0352284e4eec7f09c98d3d652d805972443fee50b873266e6604
102	1	188	\\x46b4c50e20915dc3cf1c43ab001803ed17679205bcd7c322c576721ca8573f3126bb3341669bd4b4062982a4019d7a08260d7c4d47ee34b856abc764e6b12c03
103	1	148	\\xa3327ae390297c121e6c90ffc407bcd0388ec2e8c92d3182153e4111bc1a4f67a1a3a9f5108dab62179e9db621f3e8ae4fb5ae4c46b398bd67a1db81e1cf2707
104	1	208	\\x0e20d5427725a5618a304de2828d34d8818562cfd2ee30031ea422b6b8a7df8a62018d57ac18b2f4a9091cf8b071613b4e32c99ccc35968e9556c791a79b1205
105	1	80	\\x30a6fee7502e59a3eba819ad28bba474df51265f93fcbb4200f9a9a337af233094f4f4b008fc2893a401352e559e7567527811cf561b223d68cb624369a4ea0d
106	1	223	\\xa74093bc49b6275fb80a72b8b39257a76f9e89b469783d3ecdcea2ba50ff8350c85c52c3789667461dba19a9a0e55ef975b47cabe456a1da6be0dc5cab6bf002
107	1	167	\\x7086ac392b2821ef7ba0eccb19da447d12fddb153c830dbb92eca17768e8b65bb1cc2fe81b318756c42d95406d22b6aa2d59ef21d69ba7e7b925fbf97bf34d00
108	1	235	\\xb5aaf5a97651e0a7a1a3ddf529e36c32d547db6829851f3d2a889fd9c1191af3875e4cf4a9256af80b9a1bb1305e9fc94d27d80f5bcbde57744b0cb347149309
109	1	131	\\x525dd0d30ab6d58a7096512011270b1496b78a79b6bdb19348f33ecb63e692cfab06e4f816f5fe3c8bf24799cfac4566ed4a907b60defbbdb236bcce1e02a90e
110	1	362	\\xb30e025d81b5a5112249854afdf45b7b105317bc40b09c993fdf3c26142563d75b804c68da9cf5b48c1a273d5257668293dc574b3c3fcdb3677a89bb65e9c40c
111	1	243	\\xb13184b11311eb545f16caaa0718801015207c27a137dca954534b87c607717441e339efde963215c73127e238d83c27d0a0e7f68f341899e4db3dc30fe1c00c
112	1	236	\\xaed009f832282adf9275f4d34ec5bda0a6724829a57380bea0386376df7debb0d38336ab9fe5dc4343cccad65b06ebe90e3a7c471e52ff224e007b34afb7aa01
113	1	179	\\x0859f1301232b0374526feeedc173fc3c035e40f74cbb6e50b6cb2db2f0c1e05443bffda68f1e0b601224351af61fa4ce25f612783ac1a4383e8fce643f2cd0a
114	1	404	\\x94268b52ed07eb1eefb94a72a6efea84f64453fb2d7ed5093f23926075b631c857bc05d90d7dbe7a6feb0bd7364add6352eb3b98f1ee15c8ac70f314a0d32707
115	1	281	\\x6f6d48cb4c920585280ae07a40996b3af5d1e8cd05ba3bd8defa0f353ef5918f1f7cee901f9c859c5651234ee3fd8de5c4c3a91817ac027ab4e52130ecf1ad02
116	1	146	\\xf048321e0325fefebf77fc5c97366b473c3f5a3ed05dc44aebce60f36a2e7ac31e997a6ccdb099d33eb0a6e1297ea0b5baad8f63f47a5de9d7cc22259166e20a
117	1	285	\\x36e774907e868480588a1144d188428938599393ef6994c3c8806b8a56fd908bd95ff6ebee78df7bdd06b8277e49d5d3b8fb9246d1927be343d3957d6535460d
118	1	66	\\x01fc7849fdd8abf0be5aa5194a3e5a9e843f323169a2c732ec0ce2f152eee66d0756090fc10ee4c93dbbae9c3b1862ed9c579715c850756b675ff1499745ac0e
119	1	70	\\xa383075c9908eb8071631d09e828fa7b0ded173d230a47e9ba12564ac7d11a96c7ed1763ee7ee9bc8e63b865cced6496d8fef8c488fdd53032679c4da49da105
120	1	192	\\x9abcce81ed720daddf6eee025382ab86bd6d70db8c64ebaaf85fde604af1afd274882c6cadeb8decb89c6b3f474d2b3afe75d232b2e273d60c3047cfaaedd808
121	1	103	\\x8a17803ce0965a40224c1760ce73b46452e59a8707936c545e1c71c58c69707fb3106bbdd9c526218c121b456089ee411d757bf8f4182a16320cd9c2c146230a
122	1	287	\\xa04a5e2262df6aff3a40cdd057b4786cccc99bcd1e07b0b950e0dece75dd2447f9d66a0c1aeed8ac17a4893d4dd3f13513e38a65032c4ad59b1b9c92bfeea40e
123	1	135	\\x9a7fe988e416c91894c0b9f3516460c685907887ab9a2b969592c730c42efc80e73e46ff56de05211658d746d61e82d45fd8046e93e95f3e50eb9ec99891a406
124	1	102	\\x3c65fcbd312df9c3c7154e4f829aee1242720609b3bcfdf945cb994ab3163ac5092ba0797dbc3daa32d516b5053532e89925c49dfe9d275694601f66d298f40c
125	1	65	\\x60f4d33b3e95337ff62b3402ca49392a07f86a454b6b853b1070937e3fc3ac2a97dcef36d6bee23a68aa15fc92dfcc872c58fd48470474a1dbf60bb5b804d209
126	1	421	\\xab6e9dd832a06d27d279f97ea43da823ba19ba71ed5201cd72ac96efd2378bcdd47491e75be457bfc47277914c90619b5cbe5368c9e105f7c54bef77a7174705
127	1	76	\\xb671ea79c30c9f07587ae170fc8bbb9938aac4c991c857911e244cce632d15fe7f8bcbae200a18f11eb7184d26285f9d8f7e8453a228e08711f202d61f1e710f
128	1	378	\\x76968ef26c83f96c78e96f903be616b929d22c7924061a7a41f11aec3c3ee7147b780987a338db8b74dead265e0453925f9f72e79ec5ca4fc46292d0ecd67f05
129	1	240	\\xa6668a033ec6944c4b0f4bf44d05f872c57be77eaf94bce28086e391c60fb06cc19c7c1ff3a6c7ec247df8e16bce8e6d3c25a08dccc7eb354327e093e9e0c704
130	1	351	\\x8f70a6cfcc8f0951367ba81626bc08b824d640e64cac6dc1d0b9b5e951a250f084198bec606f0274e878c26263ee4c199452e3bfadb9e9135aefe0b3f55f080a
131	1	172	\\x97976ae4a98f50a4cbbf10d9008ac3c9f45ff8bd59117ac8defb7cf2f199aca703eabdf471eb024ef2a004627b38a6d09ad98c46db528e907fe7b13b48609106
132	1	123	\\xd57d9f575bc7d434fe33050efbc4a5933476e37dc5aa8ba672f7f13e5215b956c75cbda90954238078be6a8a84378a4dc13277b1bc3c7a940b487b06cf168d02
133	1	187	\\xc05a96c6d2716d7312961f95a6b1ee6514bfcc4de806b535b918aa9e5d1f341b99c96c7d8641eecad061880a915df6f37fddb846da008bd0b109e5b1a029c70c
134	1	189	\\xcb6f293289e713a16fce191756df532e5b40fe4be2a60432a8d4876b0e8211bf4ffe5ed50896377e585dff5b502a73f19d626e2ae66a13e96af901e41f4ed307
135	1	338	\\x0ac6fe1a74f9e040ac1dbee9ac3aa1e55042b420fffc8de908bacaaebd898aa835ccfb1b56de18d595163873376161500b99279d99e3be7811bf0bedd9e1390c
136	1	209	\\xa3041d0d13ee99917917c0397bd28a5f8480e906865435dc2ac8ed4de8efddb4994abaf5fe7a6f62ca63081c51d0c2dd32d524147777a1a0a32ec19167733507
137	1	145	\\xcd9afea6f15c4676add0feb57e8359afc4df96f1d38feddd11c28145a69e470bcf983dc696d464979272cf17648518260c090c245654e16d03539e3f8533d10b
138	1	368	\\xd419a18337de3eeddedde1a5c2aeac0b5170e6d1570e626e82441880ab1bc899af2196441b19c424856222702031228bd3acb95a2c62b2b34c91da8a2832a706
139	1	174	\\xf92095e71bac69b1488e7fd064fa7653c46106992a0e2d71310bb452912d672c10b86181a3485c5d21f0fa6823aaaf18bc84a03aea3dcb57cc2ffad57665a60d
140	1	156	\\x07c8384d22e557aaf9491f308afc762f6977b35d85069b88ddb079eb1be993e3622b17011ca643eff29875a94b8ddcc3c6200e08b1c2ae12266936591a65e502
141	1	290	\\x8edcab4d9d7217819d4ec9ab5e774518bef6a668a96348f40266d2846ea48e24a9c061faefc592c4267171e014f936ee7a77ea578a6d143444cf0eab77d6a80d
142	1	259	\\xac6635dd4eca6dd659fba25928873271beab1e83e295f6060c61eeaa8799f4516564360b78d54341be20d6e739b5177599fd4ed5a4c5ce04e136c5f0bb8bb201
143	1	37	\\x1b7c401627bcb8afb0dfb2e62f85678cc4e6515d2ea4b66c3a175dd615b54f7b3b5bffb0d850047dce1dfaf11608ca4b308472288b2300c4c085193f2503cd05
144	1	379	\\xa0d62ffe18133e19d7fd41db4ac40ac1b5b91951a76176e0b1541fc0051a6f14b2962a07efd9b9621cffd3ac6594776672c546067d84d9c881fc4e958df01907
145	1	175	\\x506b3e55a8a07841e13322d5461a65bac88cfc24ae707e29fd6f5296941a84091acaa10607b4422a4b7271981e1dfd46b3c59836888db671c5e0e2da1d1da40d
146	1	133	\\xe8cb2b85fe33dbe9fea6d1561aa7ded2eaf2da518e6400ccfb8ff7db32e9c61817d7c9f8832e30bc5d777bc1b35794a4ae169b23797f6f026afee76fadb3a60f
147	1	105	\\xf3373ad6019f08750125b6b8ce67ccdeca0c49548b97845ccac3cd029afa6c46ee234b96366c0f24e7e06d404d57fb5c19c81e6d5b604d4515560f81cf540308
148	1	226	\\xb52116a43d3b1a4faf97a7af05e307d8ffbbd71353f9f473d10f528b02891571dd39af621e22773a53cf38794270942b029b2917331ec9208904485d79016b09
149	1	210	\\x7bbe230a5bc4debba5922a36cf74984980081d4265ab9e86044b297fc4b78d549217bd17df2419e731ff47cfa6c8f91a2e892fbeac5de2472a7a83895af8ad0f
150	1	205	\\x24a0f242ca145914e3e6890e083e300e8aca0f3ced7bb59ae27e7fa2995997163e78ab0d42262d09fe4987aebfa579ba80a1dd0481b5ff2684ea331f25bb4306
151	1	363	\\x4c35c339538e5d1cda754e352651eb59555625b25108886ecfff301e1f605ec3369483fd73266a813368f30d1d2b8b3afd501b274c54a0055d9c981d1df6db0e
152	1	155	\\x23da34e08e1d03782474c27b446720f90efc65b93f82b6d667eef1da9e8c6d317e84846ca5b72e9ebf09f90a4b32ba58691b1ff12981eaecfe6f9c81e24bfe08
153	1	357	\\xce50f3aec86da6705b45ec6611c031c20f14832fefbbd0ee603fd4691e5dc02ada570556de8b8b4098f95008d98e8db31742fbd0bdacc3e27be3c76c76a75603
154	1	140	\\xb463f1dc1c8e695576bafe562688b9aa29b262069b4b784e0c39d62ebd3213e73303d0e0ae11bac963093e3adb5ae650a82e5f8c601f18f01d918eff3e3a8200
155	1	61	\\x9ae1cc30d27b18508f7469647d372c1b9375b7872c3067d81523b7329849d8f3ad686f6bdc305852ebe3791d860a4312fe7816ecc0c92d2a9d1755e6d1052703
156	1	91	\\x9c7796f27ac28f7ac938468b50114b427f7195706d2d1367b92c32013e368bfe1016c2fd0ef455cad4d9812b6eae9397411be90fcbc1a4039e64f223e7571b0a
157	1	180	\\x2f162a327f7bb461e5f350f7195ece0be63fcf4f28d682e38b238476b8b2032ad1254c1f74bd2f2ef706bd28771608d790044eda3b40d647ad609ee541fd3402
158	1	152	\\x8d25d65153017407a2b06d0ee552270c6bc3c37f84ea15aeafba528c4774915f85149f8f26358429d809b92b412446affb232e7e129c61cb957798426bd54902
159	1	77	\\xafaec63d9d92eff41bb883d02ad98ae9ef0591ba150e3e8959348023204811091fcd86343300c2f84fe30c0b47c392d4674148ac98b50e185bfdbba186a0b709
160	1	297	\\xbf23397fc0e40e91c29308b5f5c832204002d732db45077010a5ebb46b726ca0c268d36ea6598078168d9e5ce3551c18ff856c5114a0cc4466297e6367befb0a
161	1	307	\\x1293eddaeb7ba9ef736b7ba332b008126a3f6e93e41fa35ea42644eca8f1f36b3214279ed5696435dfdcfd264686a46a1c3796819c7106b1d1c1b84ab45a3905
162	1	218	\\x9afbc2fe992b13c316b709770e9f276f850453a8c57051f7c51c4fc650adb5fa7cde60e3dc7dd8f75b94fe2348ae902a5a09b037623fd7c1df4a0795dfe5460f
163	1	44	\\x846a118d7c51c62dc1caa927a6c2a759b83232129c76a538deee9a3f2bf90b9b68734652a4cc27387f2dc2aaa99b1842a3afa862bee362e18a50da00d8fe5a05
164	1	194	\\x56b6c49ba1702788276da4d37029f166d0c271240949f7f8288e313f532ba11c850394f313163e646d7ce66a86d46a35d9533586558bc3831e1270129e4dec00
165	1	63	\\xd4920bd6ec43e52a8f74032f8ad60565adf98e5ddde3206ac071525846e9224b9653ee8264b3609cb8eab2faf310fed13061a086eece35889c2b393cd3f4e307
166	1	278	\\x8802cca66d6f430a9f2268c2eb4434695e91ad49564fe70a1faa48886c28c2969c46d5fd10d8f556e3adb8c1c1d066549235e242bd901c7087a32785d958740a
167	1	346	\\x457ec6306fe22b26fb07c43a1c755ca6b6a541f7dc9c771f99101d6c0cf73e160e27876133a1b97d6db4d213581f5fc1d3ffce35e6f553a5d3613a51b134f60c
168	1	45	\\xd3af802cbf3c0337d20cb55c32f8067ac174ec5bd8e1cf654a64f3ac3bf2bd7be86f53ba8776dfcd596a9af5edb8abcf6d686ee654a65e27a3b702ba1a7ec80f
169	1	339	\\x3ae439d70a9432c4af1114352d66cf81812b706a0abc0fde0ff26de88982d8c37a89766d207b7ab404a1d82e7fc8ff4e5eab7112ce33ea09789752d7cfe31d07
170	1	184	\\x2552571a9ce2be782b411393814b6bffc59e5e54560d687100db78eb45e2b0de218a0dbd167b0e5d1fecd967f4cf7402c9ee2c29f086d766181dfcf9c312350f
171	1	43	\\x92a06615f57a99c4d459bc23d7018d614c56e5260df06e0b007216a986839f434b458bfe4713afa406e764e26b99a65ad07e56d6b1cda6297e1cb5bbd614bf09
172	1	238	\\xff221a19b369d65b32abb8377f4f164165984577f4d5b1570335df9b872ce410e71df4cd97cab56a50602aaf050cc8947713327af260be7c62984291883ee50a
173	1	275	\\x74da5c5a2d7e7283c5933ea58a62952284e6413884e53c8c0d70cbd2d9e90efeebec37d4b9654662bdc2e96de686337b1513333a5a622ce4e326732854101801
174	1	251	\\x77c4722640a2d7751d95986d4ac88e03381c15c6da15bfe8e7548d3da6b4347c29c5e7ddde4826253e59b8fa76b88ed5813bfd543b50fcbb53e7be1298f1c009
175	1	333	\\xb3f3bdbe1b7cdcc348984edc0e4925f3c54ce1bb1963ee25e2423efc91f232b5ae4f8e6ad8c78befbd9f2097bf378bf47c4db4765dbcf5687ad9f28e7ad9eb0b
176	1	419	\\x296e0fe4b3cc864f69b86c04bf1efa1428b711e1a18c35c17cd5f320ea914489d4e5704b5f064e8aee4c56cadc80ed04c00db35aeccb77c40efa7f731399c809
177	1	258	\\xd9e6e6cf0bc476cfc16c2c331de0c3ee805359883226bef86e83557202321351bf7aa691c55bfb5915f013c3215edf8437ec63482e98ed497c2dff064902130d
178	1	352	\\xa0d74befba7168abbd2918eb2bcfb397d028a107ab82556720b9751619c23688acf732ff20339f0018e51dc15b354d19b21f7d52dca3b7e34c85cb591148030b
179	1	407	\\x3f11a5e02324bf3cb44df05db59e2d8854d9dd05af94f6e40d78dee08ecc1783edd7e9de8c62dc3fa43a678f59a4c76af7c7f2eaeed3408be7e6d67d7b0ad60b
180	1	268	\\x0b9c1f80878ee875b7fd50f29abc0ba80725475f1ef17a4ec0fd9015e2f36b35c3c9fe17a0f864b9ae6b83469785d9980e6e09bff35ed25466cb85db2cd98204
181	1	60	\\xb90a87e6cffd33b82363c9330e71e1efc82e1b2e247586ce3081285a41335ee22307e9fac853488e79b826b91fc955ff4fd58e7b24275d8f6540e362d813db03
182	1	132	\\x036ed20b1ac87fda9233b69bf415890a88b1a4360cf322ccdf3298620ef4c63678abcec51a780193726813b941b2cae2335131501db99a96c6cb086d2876f107
183	1	372	\\x2d4131af3c1d893cb209c1be038b5a9c5e079315cf6e66b968f06571df957824dc5e2c765ba8492ef57bcb529ba8b124253784540c486ba09c6a010a1d18cc0b
184	1	17	\\xcca081243edefc9d260365de39c4643bd6dcde011e4d5d945d872e2fcb2e07c03a0de69a12ef2070d29668934d415b32a1f06baca3203e999c6883a3e82abd04
185	1	337	\\x1f9227d53f530c71900afd702aa8db44ee2a43956fb783703f8bc473172af8a202ee44bb2075b226432fcd74a17fce4b9d8746eb53e03ed0b0a6debe4029de01
186	1	183	\\x2a3f0b4c76780c3f2c39af7854e4e6ebc98c6dddcc402790b66c5ff37d7ff07adfa9f25b8aa919ff150d784847a4002d4cb5f1604b225411fed66f1a8b5d000e
187	1	222	\\xc2049cbb9c1130d38dad941b9b62efc4bba24224bd22a5f125d4e019119c3dcafab24300fbdf86d05f406645ec4b6532ad20d6f3c3917132d897418aa43cbf07
188	1	4	\\xe6e34835bc8f5955e8eafc3abf20c01295ec2fb86738d4e256b306dc10b3d85e1ed68353c1aa1c750bde02354c5a9cf8651f898038da4b1cb01a0711746a7d0b
189	1	75	\\xcd8994157dc32680df40f5a254f9e17da950b2af75659c6ca6f854d1acd52da7970ff987febe28ab7c2f6b37888facfc5f71a42b331eda81073b70fa8118b101
190	1	380	\\xd3827084966695fd7d451597f80107f1d502416d8c49a735853942d0c624445e90553708729d3078da30ddfe477effc7525b4cd55d97310f897e442b047a4909
191	1	398	\\xbc4bbf4e91e33ffc8e233a90f13520728e57c68c592247f4785410b09fc6054bdc6db5e8c7046d41bd0506299d961bdf0be1a9f6b48d17cdde14394da562c90e
192	1	27	\\x0121b11228ead8978b1c1ff015363909156d0d5caba319f9d0c36ccaa51b76ecee0611705435f5c025ae5da0c504920dc3b68296db3d6f1a8ec6e76227b51a00
193	1	293	\\x442343aa202d78140d9dfab7d943768ea125e18224f0b56f0312ecaca69a36092ffb8da6fdd598d73a7be8c3597f7ba342adce7772c91f0acd50e43b3655490a
194	1	12	\\x76c0eae24d6da55397d6ab27d80d482964cd51cc6b18fa424e6262ac1e1d20c3d5dff7e9d6207d1c7144bd847e5f7216073d184f75f731e9b3ac039452948d01
195	1	309	\\x2b9949c6dcbd3d49252374d54c72b90e6fa1570ba8865b2117e9796cfda227c3c4d51adc6d89e89c14cbce0ca5a585e9e775db81bfa710666515daab18657a02
196	1	95	\\x1a937fb9e298982e2b84d1dd44cb826571c381a022d46c4286624669dcfa1eeb3fe04b7299134e9ea135502e4ab9d1bdd90042a28ee7a0bbdaa14ff8f9508f04
197	1	392	\\x6e06b274d9bd0753343a9244afda458226ff97434adcde499f092f5e60165d2149c29827b07f5446c3f1b4cb4a3425003ca6fb39d8d6c1f8b345c10e53e20208
198	1	124	\\x8371bdaa305b041d85d550c44c15a45950c63e6d7cc817c575e778956432a7b89675a355b522e1e11ee5c5a456daf81c4c0901b64020d6a880bcceec0e03bc06
199	1	115	\\x7eb2367f7541add6b006831630ae2841866b698970bc382a9dc69410331eb82284a91b8d501e93a788552bec9cb5915df96c7e0ab47840a4a905fcb292444408
200	1	122	\\x687e13bf12654bbefa813e36e5e4b8fa9378c4fedb8c0c8ac23733372db9d78b00d4023a4492ad7f8b4a68cde9b578405cd104a786f6429ffbb316eb9933e508
201	1	330	\\x854d26dc33a8da53ee0841a7d33e9ec5e88e5f1399f5a7e844e20739a376b62fabbd2d3cc43fdc3a18733855975bf62edf10660d7b5e95857115ec4d5527180d
202	1	350	\\x695dd71b3f2cc54b2fbf75fec5ebf94f7b3f5ae7bc9be5c214eec4032eff6030d73c89c4c90ced4010a7e87287edb3c799940d57d96eeed73ec5ad133112c80f
203	1	26	\\x4d08a53b7ad2371ccaa66ee7343988044d761c1c7a5788462b9236ee0cffdfe99a6ab9c2f375129a10365280a606056e1f15330946845d10bf44f8226f8dc40f
204	1	358	\\x7e35eb7cad4144584da01498362fb0e30b65fbf3544ea68df9cc7bacea69ee43f8e5ccd49c2f50151142e4e870cef8788b168e4d6559176042f19ce2ed280503
205	1	201	\\x2f429e10beeb45e76fa39b53202c6afe212d76739554181989e4a363540660f8bd06376587d48cb2e767ba7a4708873a3e850ecf25a7b4e8d26b673fc167dd08
206	1	324	\\x9143ac776d6831e3d45a617cfa4de415df34e905a75b12fbaa497137c720d34086db8c2c9777281807b707478eb11072a6d67646d1e8baeac429b87c2a94880e
207	1	417	\\x675ab8297c6908d6266da2c3445989420a9e19af5ab980b04e05317b3ca493d7727d0c27c79cfadc62cbf8c9a02b83c91e16b9d1bb0eb2d79936b579f4e2e203
208	1	412	\\x661bc46ff0ce81cc749e92ded9e5a4f5113350c8f2f46e1c030d8f4dd8efb67b56bb1038548fabea884831fdf6453882d7d7b80ea6f4cb5c867695678a059d0e
209	1	364	\\xc583d3e86d70583e10b7df8e8d3d88aaed55548fa2cfeaae6a7be29ac80a3053c9b36d0533b5e7aacf68408307bfe83af54b3f7db5cabf733100a698865d6804
210	1	19	\\x63d98388b58e6a089167ce74355b9de50592d959cd80275a157b1463b3de1f4746f5aa3da4b9bf91c1a0dee08e64a8f7978d6b5b1eac6b358b7da13291ab870b
211	1	31	\\xff4b96b2bd9b8ddf272a0899a5984f50b91b5735ffacad8136bd298833d40f2f773c7edd6b7d6d2a6bd2d9992cec74fc1a144e86b499225760f034e131a30e01
212	1	288	\\x6c5e3402ef4949530b8a6c4fd868f64abdd94969a87f697364d72e1b01c1653e643078b9453f58cd1b9687399d07adf0b33740dc54986a599e4348b5d7d8c002
213	1	389	\\x879b152ce38c2886cb5b94eaec245e4590bd7566a1ad9524b2baf6a3652946f53eb089d212c46cb63ffc59371ed671a44ba4e8de0fa0bf94794b1d86e145b40e
214	1	347	\\x0cf45ef69c21556e67f40f9aec3e77c61e1a2cc099b04e7f6f48f3c05605ced8681c04f5f743708720d342ae6e00862120e1c066e7ce08e52811725b5a444e0a
215	1	73	\\xbf1911f5b4736014fe79c8588a042d1e2730dfd838db12cb97bbb008ccf1b64d0268cfcb73abd7b1bbed81022cd851a45774286d230ff93ccf3a65a542e7a300
216	1	408	\\xa86c86f50b38f0128827ed3d0a5b255f06eee6d84e90df34a4c66f14a7683de2268c4df3c91942187348f4ff1ab80e883f27999ca24381454faaaf560822e006
217	1	219	\\xd1e5f8740b1b57ec0fd72bfc0199b0ce70c32447b9cb78574fb4f0c6006afa0b58ebbc6f5918931072cda7bd931e395af1c4bc0b5c3929ffdfc80b0f97ed1f0d
218	1	292	\\x57b34a932c9d11b2c9de639015d246a59612267733ba5f282a78aab9835753e75c2030a342680dd43a4ba18d5f7f85d2325b37c5e7b0cd3ae87b7ee66c557708
219	1	143	\\x0f694a53a21497b79a112a96d0d8de8af67e7fa78fa13206350f4b373cfd70e1e38c8ce4c41679f2f201622b6ed854b62a399adc63f2fba7b4d28ffad028e603
220	1	403	\\x0c4ad1bc054f29ddaded07283d347cb60f3c6a10522e03c5249e2bf287e762d107bc014cd46011e2ca683c84797a5f242e0d6ba7de2b813e64dc251a1204fe05
221	1	411	\\xbba6d275afd16d94a7f2289ab36fd833bfaf5ce857628160a2e34713481b84fb59ca90066d611d8ffd6cbcb7fc56900c8ac4c0a4774630ad479c8fad6d2a710a
222	1	110	\\x08b7a2fe14d6ee75a6935012c51a203a5e9bb82bee7162438fd14542fc96bbfbd0d6b9ca3a8c6038a485711d38ee0d722470866952a9e4eea9b6ca5ab4b8f70f
223	1	231	\\x85263aca125e01914cfeebf651566f3c29ecf50a63c6bb8c9ddc132e2ed7dc00fb90ed89c8bb630f483edca0bc6fc978712b503d8a9077f89ad31915c1c38c02
224	1	280	\\xffe105335296ea0a81672c1b0184c5d1971f799c302587e2907663b7af28298bd76f8233a189d6990f16b92579f76088bec4a8022be112cdbb34f519734c0e00
225	1	270	\\x2344e603c8677a5385c0b70049442cf932e1e3dcfcf35de4d4389c7c459208ad2d98d5e664479a15cc6c159768f3720f13d4d5462af62919cafdeb13c6684602
226	1	107	\\xacdca3bd78be6360f68dcaf8e95a731174feeef08b258356bf1e59cbc768afd11b39d6ac7c4c75699118fe6960d9e20b08027a9628148f81438335fdfe0f8807
227	1	399	\\x9d0f8218228932020c1f63a5eb9a20223d9962947003240986f9297fe7a633ab142f31f6a35751fcd5af9a9e56eea192fc71aa1e5b5580d1dfb8d805b5ce9709
228	1	22	\\x13c921d0a811cd9726314a58c0aabdae382792d631ec301e9f1d8bc539664ebc07a38a614ee7bb44e2850afa540a8e7aee5aeebfc55726855b1d2c69864f4e09
229	1	36	\\x5bc868805986e9f321695e6930c3abaf501826854541f373b7a464abcf86fc6035244f90434536a4552b950168118364e21048dc8e7b249fca2da0e30f7f1908
230	1	394	\\x6fc56d4d5c1d5d7ad873d317c28843598648369123090745aad5e89d6d7978b9fa43f059cc6a76ab32c2a237227d990e17209fb31e0de99167ed5832ed3c6100
231	1	203	\\x40c87ec7a21c91f5d2e6d9c10ca0315b6e8bdefce74b8c9f1c24b66230aa9133d50cd750b0faecbcc35f65dcfe1c66a949fedd05c103e2edc4e0bc3fd9035809
232	1	85	\\xdf91389a1a8eae33b582b5dbddd161abab6385fc536b6902c8f374e620393839a34269eca35c00139e72c8ae3efd169e3b0d0cf5626cdd325c607dc11d074804
233	1	232	\\x8aa2639f7783d8704a9fa77444d629f2a133aee6e65d56c29fe7749f766eaa450f813e2daf8e2a3a2aaeacaf258517063b63bce408881d7ff3fb55ee728c4507
234	1	310	\\x0d86e664d40ce0f161c82cce0afa75cfcf0d198f47af1648b62b1c9b2950a174c4bdfa7f74e6e8aa0a12e0975e969a69ab91897a4238cb5e6920ed7e1ec28d0b
235	1	250	\\x862c724a1e0a2a99feb8c3c426183b25b165b20e4c4eb8e0ee02c4526cb7b77bd5d496ba27883ae67a634a560c8f785ae6a2e2d512975fdc0cf3ab4a303aec03
236	1	279	\\xed71bd17373e87deae11c7c58ddea9e803eb0293169754fe887fd13f2754d631bf9eb964344cebbb9b065af898df60600ce8d25144836f3492f93adb58433407
237	1	128	\\xf7e44767c72740d87660f53fa34980e032749ab038a13408ac3ed4caa9b2a1b3f88a228e7625a8646799307d45971a27ca7c2f871d76a80417dd2be982c0e404
238	1	241	\\x6299531647bbb9f66f3921e821612f51956d7c775c296b434ab107ef7f7387de599237ddfd42866fbf075a9e2ca986441fa9b2e13402c87453db8520f1d5bb09
239	1	317	\\x392ef3e431ced3e875c8fe04e3f089f0c87a22c8671605c2008639e42448e811583d4d064c88415b422deec8a0e8c00c10a3bd4ce5264fa9c8615c6aea6bd900
240	1	298	\\xa97d0cc6b99ef57702f913446773fbbf1b45983342e113a773b445a544f10037e96765767b4a8b97e1438b205ea773987e7c1256e34f94a6b5087a4b46611603
241	1	359	\\xcfcdf6ab0e100db9950f3f744f17c86cdc1f09cdf8722915a1a94a29a9d862186f418855e68fb51fec610c7095e3e1aba06e2cef4745c1683cbd173de6f76803
242	1	237	\\x6f775321249b91eee96b95ae6e2ce992bf3e6892f0cb31aa8c4634a7d6c6cd8bf2c688fe08f33d30e84fce5137e44265a3eac93c642f0671d777159ae8a30102
243	1	154	\\xfe54e53b9645189a18e719c9474ae410611898f250d40e8724b1e25c239d76b572beeb73b793210974a0c4cc324171ac9c89b4752ba247a73165d91e27835a0e
244	1	355	\\x5ff580fee90d78613f927888c6b774da832df066efe61660394746a97df8eee450578f27499908a6c17b0c72f6bebb63a4c14028118f25f7a829fca67453500e
245	1	247	\\xc19be7589ba2ad4d75b047c5baa3a309e34f09464b3ead69eeca96dd250fbb3ccffc049a0ec8c930c222bc77d643c30c87912d0cd5f64940cb56c7edcdffe100
246	1	88	\\x4ae2fc541ece59444cac44de5ada386ba37fccbfd746080e5c1dd1348b624ae54f19b5b38a80cd2f51bf4f615b30f52665b37791e093478ff9f87d24557e2404
247	1	32	\\x5d357a490b5a51b6461f6aefdb2558ddf78c488657c3a5752dec2ac688adf62782f04f92bc0718cc6eddbbdcdbb0822946ac9d720175db5e52b6db352148c20d
248	1	139	\\x37b94e54d4b351bb2425ccf66a88d06988e5b559fa12a1ba55c0a00a3d8e465eec6eaab28e865d983f9a0fba5102666fd443ad354cde8fd3f37639689c56780c
249	1	116	\\x3b50a672496fc63ae9bd8b5dde4846e483d27c5c7dbbf24587feb7bb6a47f331a04bec5621a273edfc03a435310148fb74c2628e494f2e7c94a2df78878d780c
250	1	177	\\x3deed29c508e8c6369dd21ab51ba5ad3b81c70330fefe09119ffb6115066d15d294f7dc8573f5f40dde03c50f57b224b6673afc71144568d41ce76afd730d704
251	1	335	\\x9386c0328b65f1bdffa0d1c539a01da93c25b49c916c1290803808876a1b7f564822b64a0b0e08a1d71e1a5e118c60b877f24681c9a947044c29ffa53bd07505
252	1	204	\\x42382cf63444067d80c26975cc3d18f9599c3b745b615dbae4f8dff25b1c572157faffaea1dbe9703a20cf903502551931a32e4c77ffc9b6fa71d33f31187308
253	1	119	\\xeb621873114c2787ee5e76f44a03b1a9bb82b1d6b0560f7d87d998450a27b688103469519ec77364e7d5cbcfe73c92ac34f283bf1ffa6ee3e723a24048b9250c
254	1	274	\\x147cf2efc2d0a4d74de4ec44ac78dda432d0f1448a80c5bc3df300ba2a7ea0e2b347cb87135b8b7f5088e82326b55cf579947f06bb5428724caf7cea12d34c05
255	1	424	\\x0bce538efce4972957ce63746f94c6dd9ae3024d764ba60188760ef12f9a9a4939d13c95e5e23eb6bb286abe30094351ab608d19a58b52a1248ce895a5dfed0c
256	1	256	\\xe12a4c2735a5476f786cd7560995b25e2c42393d4e26e46d81b4d1445c58fafdde53131873ac0cd29fb7bed17adf97289c185cec870fad700283355b0b088d0b
257	1	289	\\x76d97fa034711ed4b44f2403434c1db566dfaa86905f2cd89a45001fe9cc49ba08b878017d048a8694c34e69e4e8ec048cd11aa0b4b8fc82cad6c5b69994690a
258	1	286	\\x7d52aca25a677f14a5a078260e0ae33013bb96caaf7f4e539b8fedf0ba20fc3b05a64a0a93e891c03f1269575f934888f0462f1c9fbf5570c97dfbbe7405b70b
259	1	273	\\xc17f70c93b68c668cd97ad9542b40bb844f9d5526a8e3b70c8615ff8d1b6c2b60838d8cea66d77c2cc83de08c02100b7a859b5ff12f52cdc1d4696fe8e23f001
260	1	301	\\x347e273796eaab0eac469acae082fc217b3edf783b310dae57f55ef1e3c0185547663c7f46d031047cdffe2be42dd78ba06200a278167667943a7e47d2e8e802
261	1	46	\\x6f84f3c012684fa2717f9b4a44a11c917195259e839c192974b5d23c89646741bdbe75264a18b3eba559b8e5e172ae23c2017146d803f177b8f3a74cee25600e
262	1	414	\\xaa26b38afc6a94577952ef854bfa88ab0d168db09b9eb7b7236bb2ff78d0253e84c7a5f60931654601394a3fc4c006fdcb0c017929828febbae1c31aa82bc006
263	1	52	\\xe9fb704d63e2740400189592dd6a034f7770efc0b7e68ebba6066bcc93ff60233628a91f4865f52cbd58334fe2897ee19ce1e9839f415741367ddb1499405a01
264	1	8	\\x1b156b546b17271d9512db02b2b12492c88a4d1bf42a0465d026d561ba7e6e7ece33b4cf7e4a1c7d8dcb169cde2dc28b97ebc791a4343f52d0aba2149cb66209
265	1	224	\\x25f6c0349a6c1453a6126092d00f3ac0126a460a18ccb5d0186c97bb23c856b32da34c599afdaa3ffd06ed6d7db4766b767c14f9fc90a544dcca80a4016a2005
266	1	153	\\xad0be6ee423ee4b3da8f097fbbb6273bc042815fa9f3c08d7a3fc2f43a6a736791194af728cd9ff26b54fd45925d49ccc012608eb5635722088f376d2dd56b0b
267	1	161	\\x6e639c6b8640157d48782fb1cd47dfc737bbc64e78d9251ffc614c75931fb55c6893498bfff971df3ec63b5854267e3ad023c175c3234708610656e704e3cd09
268	1	331	\\x3fbb132173822e8cc371beb849accf128c7fd34026da079a1f45c26d65bcd297dc57afb2c21cba3d45baf42e2f9e035aa0c1ddf415b14d517ee8afbd6188e203
269	1	325	\\x70bbef97dd48980b7b4839470da5880b086c76374810528f9c91ecf48428f87d846e4f6b070b99a0d9550f89a45987fafcf64f8ca9f0ef750e8678b9c8d83b04
270	1	129	\\xfabeae799e45769970dd8cdff850b6c15a9dc14d8b2203d93231d3b2375acebd1fbb53e4303294ba1a2fc7998fe16a477a1940f2ce5775b6ce4d99a56f984f07
271	1	29	\\xd13ea93ffdbde2effba9dd8077af0d22b4916877d9588123af34463db62aa77511e24beafbf37a2c795fdfce565f6b6889fc693ebcd5bc064211f9107b1d0b02
272	1	319	\\xcc530f98b5bda3d9ff2fe3293c2474a3ecc68ba0cefa43d4b2bc87bffc95caa4068a3d606c17948a71a93c6c5f9cd08dbbb311e708e07b86cfe36abcc0af810b
273	1	162	\\xe7525c30720c0e2b1e6463e34ee6fa360c570b27b07b71f70366ad0c12bb694a9371286869d479f31a09f216417b7ab9eacfc62c5f34b6556b13f3f23102a50e
274	1	308	\\x944d6346c1179308d1a2edee925ace5ec3432ec2de5f1c0d1ac72f2254448eb0c590bf511d6c531e41be0ffe300e2735767068ffa9006a959e3f1b67d9cc6400
275	1	13	\\x912e9233428f03c663946d1eb0f17e7de70f1912001d54113bb623da3171b094a86547044aaf2deb07e7159d398d0bbb240e11ffcaacd97433a3362505e5cb01
276	1	271	\\xfe05b7d745c2e70affb35b1286700efae5ef1842890d99aeaec125ee397599d507b6bb720f9c1c71591e2a89f5629e615dc78b9ce4cd2d4e0602ff460a7ec304
277	1	164	\\xfce67e5a4a5ec4e0cdd3a17ee665edc9e9b984c930639c48670cc6314e911848c03abf6c13727d90a1f26eceb86fb0e7b8cf26c9ed659c5c280046bdb0b04002
278	1	334	\\xbdbf3ec8fc5a3974b480fb9a8f2addad78d4ccca1532d93cc89dc347ef8d044799ae62dad99d1cac7810b9982e5616e47c39f96641c5c03aa95e99c66415c408
279	1	173	\\x956748e0cda3dce166200a9d27701972820b1f74cf215009f7b5d911aa5b2e482c98f4c03c0b52d228b82cad827d047c2b6851322bde4a8b1adea50eba58f700
280	1	373	\\x147f1c2f45e0d056e42fedcf525678b844678d00874dfb35f6e350ccfee2e0dc8482b593b661cba3424b1af6985e574a7efe18ed691effb6f66ce3f505b76a05
281	1	314	\\x6d920f85c52624bb8a1b8fde48fae930d532f66bbd204ccc07a818433759c0d105e7df4e6a0dc2739b5f756ad73621bfcc50e72acdbfb25fe189bba1cbb7ac02
282	1	195	\\xddc7840ab59e948baf2c9215a71b7252b5325ee81e32b81f0c52028da8edeff6c9a80b0e1f488284d50686666eb74d613467c1d6fca3561dd5dd6584e44c0c0b
283	1	211	\\xfb66eb2723a75c033f5c8a669e618d058de0a439e92f71931c65f58896b463f3cf6338f3aee43a8a29b685f3547df831b9c8977c0f58b1aca2e627802a853704
284	1	376	\\x3298ace5d397baf2e340b67f475eeb13e567068376ef9377066bd0dad9a93977de0512b087f6177c5520c8544f2e0b7a3763e96e0175b2a834de1edc0e885a00
285	1	150	\\x948e7914a5c8eaf7cff3b0002fe05d226b77666e01a8f7097410e09d6aea1c582f19f0273c4b7513de26ce453b2763e6f2bb1923faccd6c99fde079f471bce0c
286	1	48	\\xc6cedd4abeb19da9634ce53eb752b952ea93336b1c4a82c3e3a026418818f56885bce19a02c9d4dc522f59f3be4bc36a56c66bd783fd9140adaeaeee68370602
287	1	220	\\x0a71847740d66e437ac7e94d1d0d92637e1cf90ec72e228fb7cc0b3889e661a631c2b4657700cd7a0d884a15bd27124e56b4e8f002a129083fe181cabd59de07
288	1	402	\\x456f29851b3f15b63d752108cf36eefe7359592fcd189d6095914cdd7aadec2bb38b00a1cc3382b4e2fad984dbcdc9dd8d3ab2267f4a7dc3b5c825924aff8d00
289	1	215	\\xd7e36678399f0b042489f4db95850fa47f0effa088741bd8198118031e59ff97afe457b1a1c712037cd18d3a9b8bdbe2a2273da42d61a916d3c948d4376aa00d
290	1	416	\\x42fc9f67beb49f0cfebd8834b7db4eb6456ad89007217a1703b588e9cd207bb7bd99bac9caa04c89dc006c3e0fb238b4ca5e05962c341bba833ec212a37af201
291	1	366	\\x0a0cf882865daee8e997665ff2c71b2e72a8d707361be38868112c73819093ea509f988a03eb53e73c10d349d1bb00a4c8c76174976c6a1c7e1281ad696e7e01
292	1	24	\\x6315c19d5d08463bffcfd0e1e509d33821a56449c154acbfe05b138c1511a4053a384f9c39b9d72bec8f33ff96ba0dcdcd773aab32e1782809980e3323fcf909
293	1	138	\\xe2760f83a3f2259499f8f43e19a01568d5a299a64efc970cd10c15a5439923051fee65f56f28da1beeac96228b976466c5259458641856a82a51e1adf8f17802
294	1	315	\\x7cdf3778f272f567dbd1fe3f8d4eaa0fb564de3dafb9c80eb60c9240ec205cce6ea76d974735ef403f8c70f32475dd8b3302753e2bd0c872a3cb73b04c7c030e
295	1	57	\\x64e23ec8dbdfef7020e655df38f1e48c660577094cbc632ad34aee99950b14ee27893f5bf791961ce7464499786d508b4f1b72f22c39ff562b5e208ff56ce80c
296	1	356	\\x3af266a067c097681ab28f6cf4de16dc462e71a8d2d90919214b1a918d9d40a4d0c5c2b2f0c3ddb101b9a48432976fbd57c2af98860e1d5b0dd969da1f243104
297	1	53	\\x4253477b93e9715c62507d17da59f928ca85b602290ff21f00e7a48df7e8ab754a910deaf01e93d602ca81bae41d99a08e2b7daff33d4244a332d869c9952306
298	1	316	\\xac8578c43a09fa80feda0fc071cb878f4bebd15b7cf32c8e1aaba5eb279653027bf8bd13ee632495421d9145a2b1e795a8393c5cc6f025c350e99e57282a1101
299	1	81	\\xe08ccd70b1878b0766a2b10f7c55858d7c2e1811e2c590c435b9cd8fa893388e50e562b23b273e8a9a268658c855163aa47a1cb6786bec6088d18d83f48d7006
300	1	401	\\x9c4d1741a78be415bfb0f2597eb031751da9852ebc7d93b9cec2b2a24e1ec597a98834c43f134e5579b2babd81dc4239a2a3d7529666e5a9620f1097dc595f08
301	1	62	\\x0f401724be316ddde4b1a89079867b8a99512e1ed56e4feffbc1d0e9d168dbce3af8b3e1f15ca4a33ff3e5e27a662e18532a8ff51c0d7e57549115bcbf733e02
302	1	381	\\x850ba93029d554f949f6c6883ee5983a7e4763a89497c65b5b3d0165b54e0d12d4431dca5f76bdc85647b742ce14e5c3fd5f845d88ef1e7130b4ade71dc3570b
303	1	71	\\x533c0f87ce9cd83d83fb5cb0a65b80aec6547cdb45a57803d89ceb1bcad88756960eee48ed6b78c6b6dde87ca5938c7a9e75ad74b603b9832e7abdeede068306
304	1	41	\\xc085480ee8b9233b8a7d94096db7e2cd97317767c21fc1332cb6e3b1260b74697374adb226aafc4e62be041f382a3d07f135bbaeeb0455c231e443ba5b207d01
305	1	318	\\x86939f7c7b87fd031f0c07352adfd308ef98445dfb858aeb5041405f13c04708c143704ec434593d13973058c6c1d159648f0d81f971e23b7028e0ff2f5a8807
306	1	15	\\x7d039cd1799b6948e3f8be6fe00683928867eebed4d3b00385adfccb44ffb9958e7f0671d8897917c39d8f930cec09c805a70bb7a85b63636653cdc75d39c60d
307	1	68	\\x19fce5b2ebad3fc9b017bf89c25eb1c28155090ca55d412c4605be3954cc541bcff472b8c81c294306d6f5d5528800eb46c742fb568fa7ca6880607bcf596b09
308	1	303	\\x9dbabc1fae8f0a5be5cb5ef8ceb8b474e9fef063e6f66e1fd5f01f9b544be69c22191a6b627546d14ed2d6467484c5d8ff0313769b32260da7a530b8c6e8a60e
309	1	242	\\x9771bed2580724e52cf28f661379553c00307ef5cb9c68097b88ccb76509b1f029519922f2563c1e5962122a3d373e1481c45012fcd7d30a461afe1beab4ac02
310	1	254	\\x3837abc28da9692b24f78bc3db2ce047aae15b3a9ec5038c330ac8a0819a928b9140b3676df7b1442cff9666eef4f8e1a26fb24fb82f0ca9dc0e722782295c06
311	1	418	\\xcda4eb080e025ba17d585310e0a0cfcb48900c8389e187f7f62a9794ac3528cbea2f031f6035aa7aa160552db69676cca41568c498d30021a14c31f7ac96e106
312	1	193	\\xf77ca4740370af22ead477470aecfdfdae13ee36e67e5b71aac8b0cf192f1af9b954dfc7fe4dce483eb226dea7b4bd3eb9be5150cb95a6dce99f2cb8590ca10c
313	1	227	\\x381dde1df6ca4427fdc3c9befb5919bfc2003f4f853df433797d45aeb8af8088c26c12ac544a3c878414ce18309e929f09a20436ca13f6263eee57459b2d0700
314	1	168	\\x80402f7649a4713bdf7eb9074c9bc9b041c79a9b90a047abbab89f87d6bdfa7b90f4f7f207d4c67e03bd2788f855883b2d991cbbad429843f846c77b2097fc06
315	1	25	\\x410cdee1a4dcc24ab4b1a3bd52c49f438f8dde5b030639f1248d1ca28388b620a5c8ff9d74c05f7348394f55eca544190ffa75c1ff08d13e39a3e5a8967adf0d
316	1	311	\\x6afc5306addba942802c45c1ce27de295ef2067c106f4cd30ca0b9c27052686e8f2af132636281e07248d6407b5a7062a4a58f641fba24fce221aba5a9579d03
317	1	395	\\xc2e35eb84b5b398157269b3b2812f8251fe2b82e540ce2b7b76d7911d677c75c9d0b166cc55c83c644b74c4a1da9ed865285ad0aa7d9fe2c4de008a196184e0c
318	1	185	\\x107e676686e3bc81258da3a02bcb66fd506c1d1e59a8e1046e0389101bed4766535bba5beb05480fdc984113054e9720390b3693714e9ee4c29c191abf1d560c
319	1	312	\\x41fc5dcba33e25bb61e21eef1424d0bd1f3dee426271143dd5e8000a653fc1f77b401971fdd2581e70103ccd3c2fcc3fd8c22a6cc8b3367f73e68cdac2ba270f
320	1	55	\\xd7843558c1b0048dec63185093eaeb3a0e2999dcd2a66505c730273430aa55cb577fafaa4dbcd5fcc8ecc216bcc61f517a0240432388bd9f544fa7e913fc9806
321	1	221	\\x91a500d5334eece9dbdb1bbc5a2fd8d563437e0b489f143a42a2557cee8ee980192e117533483d419ab93d9f6de369a27c8783ba4bfb1274a37820ec5cdc920a
322	1	100	\\x04984fdc4dc3bc0b06026dd2eb8bab5bedbd0e258c282f0a3374bab32d906ed58a3a8708d62d52931cdc8fefcf8b4ec7ed928b99270789a78c89761fb149af01
323	1	84	\\xa4a9586ed9e78230a5ced6e4ea99bf59fac8ce2a7adcd5e6536328feeff561f1301664c73eecc53600dda9edf9d2e9d3d0580e449903e9a4ce83ab9539d9d10d
324	1	157	\\xf6cbd854fcf370e0cd1e1d4d16c686a6a1b9f24f3ba0564f8a8033a93acf0978f2d935d0bf2d53ccc9786d62da91684e05e0ffa3b3d3d0a08d269edb588c4008
325	1	370	\\x8a47b9c63de7502fdc6d4c8f7e9970bc0637a0469d9d270a658a85c2d54fe7b752e0c0a7dcb05909d24f0fbf341179e5a0482f872acd8d45858b4b973d6f760d
326	1	342	\\x1ed4e3686e89eb635a691bf81633065abddc4d6b35643eaaf1347cfe434d663788b818bef1b085055604acce7da87a5ec08bf937a89ff2220f5052bad5244400
327	1	198	\\xdb736812c6728a93d07c923bfc79b6df324d28a72e5b810563d8e62b82961ecf7c6c3fd9dbff743cae79870d9b74ad72cc172c31a03e3cc7b7f9e328a7e91a0f
328	1	304	\\x391ecad8daf5deff48d34edadb640c1ee839c2214dd6c9a10e6ae1e93ab90f270c298fb9792f1a61ed501f15b9d68e58f6ccc3110319d82abc476275741faf0e
329	1	336	\\xac2d931bb241c89971c52105cd8a7376c13fc48d3f1a627e2ce3286bbf57a26106d29b25338df709789e19ae3fc52b74e5f2a8b8266d99f3f6b88933916d6602
330	1	206	\\x5a6183417c0d2fee2802ebb403a21a82d8ad835fc50d445b4f16e16b2204cae39fb1eadc7ec661781ed68142c2b07c95a55002dfe6bebd5a3a7fcc3262200a0a
331	1	23	\\x475f410e4e4e0418a9d240714c0a33dd37ff18309e7cd9cad569e72e244b026a5faa71817438df75d5e2d410ba80567d78aa3deff1d92b4a70fbc5024ce16404
332	1	111	\\xb5dbbee3b22b8d7cff82f7b34c8d9e0d3340e34b7aa3771c5e362b4816750d3e76038d6986966b60c8d05b4e0c75cd51f3cf318cd098c697695e4ad82840720b
333	1	1	\\x46ca986d95a7449e60bc384e8832dcc122dff7997e4b1fb3c4b64ee6401a7bff03d82007ddaa993e45838a5918feed9faa70f4107661a86b7d2edd70d383020b
334	1	11	\\xb27f7a357d8488a16e060133ed63f1af995e68b0a2bc0c1330067c7b9d654e6df83531b8f928e26db5e8a5920e218a113ad6fab23ea058cbb3a96b518cf36609
335	1	34	\\x405dde81034a5df6b2a9c72c85456a2e2bbcc536aff2dd3a18f9f4ddc00fddaa523ae883981ab4e32b0ec7e56f819237ffecaf54de90c46cd1a071eff444f20f
336	1	361	\\x34b53eb531ab478bcc724db852e695ad59593c737bf26d11300ced63e1b6618d0004935e21452902fea0078eaa6729df8b6767c09cdb0ae4a68b0f205ccf5400
337	1	54	\\xb576531f135e67586317aefa4526cb35f8d5ea446ebf404fc87a5966cce30aab2fa6cc77bf64716782a289f7ca9e080321abbc66128becc0e0faccf3f4964803
338	1	294	\\xa40f5fd0b8f14b5fbd0f069c705d711ad540b1b0fdf49b101c74d37c544a0188f657274ea638c2bc7d98439c47e4703f6e2e5124b7079220336cfe90ee49ee0b
339	1	39	\\x8cb932fdfd56e940bce14f9a99a981d0e69c629487ceadaae13cb35d60cd86feb5bfc12ae14084c789ef26cdaeb40a0f322a47aa4d4ae6c36c6352409e1d3100
340	1	388	\\x30cb882d9f573f7f9c288b4aeecb15a9e64a9ca2d872f9b25c29dde008df160a169cfcb44c59ee612b11f0b179c8c31da3546391a7d6549e26e80d67b7ca2b00
341	1	329	\\x056819d118b6f57cf318743cac7073266968360ec24c3e6f59e09cd8cfe4ff138e66cb469160d4af332311d61329b9aa4261b649f50bee8818181d37eed4b507
342	1	49	\\x9fef904dc1f37da8dfecfcdaa2d086b192f011dfbcb597e8252765dacdc4114818eaa270088908c0292f6eecbdbb30e1745d3e5e52a4c36e840c3fef8c0aea0a
343	1	345	\\xd58f23f71d298930d95496544e5891edd36cd062103b8f57a19b89e4b03e523b8c61927420b79c03272ca98d15ad0ff55fbb74a4ff3e286357b630e0a8fe890d
344	1	160	\\xbca073009b428e71aa1aa617084708d24c09fe8be0548400023303c5b5f278f5ba502d0bb6c1f96c62e73bd965a634994dc7da48d58c0e4bb6884b2d9ec3e709
345	1	14	\\xba7f218dfc589430004651bc234a9006e9355e5d78949355e2f329512c06370808fb9aa062a34003c35609df4752f5ee0e9e851edfabaac3df915c5b6290b300
346	1	144	\\x2cc46313f4033fd9c41a6e38ae16c38e5904f624d9395977cb9bb0debcb0aadc4db331c6dccb881370e1d3393b0abef7b60ddc1d9a4456f47c9057d82bd05e04
347	1	387	\\x1df3c9a66db1836cdb5de8299fe0f04c1fb214bf0f3700c736a387dda75f60b85cf3e870df6b713842f0926845d5a6294bf21222bb6d3e710f7723db0ad79500
348	1	390	\\x223e682b3151bdb6e4662279ff3a987bb94e360df95d0a73275b5716f24ecc70a46a1e9f6fa39690c332d421d153da93009e891eefe795ccbce5fe86d8516a01
349	1	321	\\xf975b733b4f8a0788f042cdb8b41bd843bf0a0d92b921dbebc061c706ac4ba50f2986ffe17c9bada8a37b45f785df25cc8c92974556f66ed3527c037d8596f02
350	1	96	\\xcf27044e59f5e3b479e56a61445a6a4f4c501b84af389be6ab747b469d9c7c4d7180f61822f1c39eaf20c0fe9998f99ba44aa674cdf4482ae34555d78fc2020b
351	1	69	\\x4af38d2d1015444a983762fc16490d4e790e98af6d21f9f3d00a0967dd803418b40b2806e4358a7d325d75ebc19c1afe2cd29b88a7980bb2c61838d983a5a606
352	1	212	\\xcd1d4570b30f05b6914e0be7072386703e25e60069e19189946038e3d84edbdf9e969eab6e5adbc2bc1c18ffd628a700f55af35740b4fa5e88c5ff65eb41bf02
353	1	229	\\x9bf059368c4b5da470515adaf7b681b23e1477d5f3d7655f28c7ae15513c513cfda24232fb2f3ec2bb41d60dae3396dbe2a1cd60770a8fc5e3f5ead180985a01
354	1	267	\\x09f2d82893001dba19acb0e6e711750670f6ddef4488ed5e635d815dbd652eca6b11f2944f385b902703f5e712349066f88988107830e1a2896fca879b2fd906
355	1	92	\\x3613415958300db549d513c174550f834146dbbaa7a23bb0544bce6d5ae17c6dffaef0e8e265f19f77bcdaa4f4747f371599186c4ca45dd96d957b617f3d7e07
356	1	42	\\x12a43cb93a368b3985e19e4aad489192818ff50ca62678264335c6fbe68ae37ac0e724966716ef455836028b04291d529472c09533017be94b2aa58277dc9d09
357	1	64	\\xbe0097407c0279055fa55d3e8491840f7eec664c13c4f862e3a9b4073fd50d690a96498f1fd1c1ef3ae4c5235b5404fce35c6363bebb5d45c54181f684234607
358	1	255	\\x4c857079ddfd0cc1fe96e22d47a1ef80214bfd17c9e37f11d730e702e7d7b27a115b5d87b18014d402370446bbf5e14bc051ab37aa949e32b4a3c7811d9dc904
359	1	369	\\x202ac8b3d2cc50a7026e01c91b392b8785aab30b0be0b101adfc33087d5f26e856ab5dc494809dc7299bc7685a52c061ed4291c34ddd57edab590341ae9b0c09
360	1	305	\\xd6f16733259bd372b4f9a38509b75a9ad2866cc0d358901b387c86de0638c99db8df93edb0b60372d6e41abe2fb539e74cb1d50c22f9a873c6a18e9797ec7401
361	1	423	\\xad869893305fb5bc56c6b0e4a4c55c5cc786ab36b534386f82ebb9168e129df6e3ce600716a3f22913c4ad6072dcf88139479f463dffec45095255f13db03301
362	1	225	\\xebaab2310cd71b72e5e63f5243328d96b3bc9b26d7148697668036c0e880ff791a325dd6d8424d853e1f6786c0233adc9ff96262523ed55a8ec791f986e1220e
363	1	166	\\x5861efc291bb0f5cc0444005045d7f948f57861b9aedc0c913117986f119270fa0d90b4d786886f4445159fe99f7a12e417322d3d7745d7efb98a73cd709820d
364	1	79	\\x374e759cbf4b946c31a6b21df59dafa7f73b35b2668878d6f0bbed24879956959a9e78f7a3c72f685d5f015955691563a8158c2f56cfc620c1d213627b452205
365	1	86	\\xd51d606975a1799afc311e9efa3b032be0beba0f23db6877e95660abdd03616f990830ff069f487ea22be8c94cc4b023dcaf7aff5ecde2bf18a8f6a6494efb04
366	1	50	\\x642be118674e18a58c8b97d3cdc81710925d4910a7359d82f81102cefff0f09a740052c809847c728b5a7662717fd4a684a34900f6a33bf46cf8dd8b7284bc06
367	1	35	\\x97bf115257035088dd40a75e98e5090242ad1aef46b35c9de486355780a00e9daca9a578378c100bfc0a625fa7ebed25be78e15f166a12e5d99d9f4d5d741109
368	1	126	\\x2e94b319c0e3fd898f3b6140a925f117cea4bc6f83fbbdeb9de663371621cc09c2c9249fed7f2b7e1b2bc621c4617a2700c4e489ce180372f51532831f55b202
369	1	142	\\x69198a55415a2deec80e7790590838984af5a6a40a85ee2d91eb00eb6553a67c30f3c8a3207bdbc0be9497aad6e742ee4fe3790de3401d6389d148c218fcc50a
370	1	182	\\x146959436928ad591b1afacc5d24cb52ffcbc5a7e6b79cea155b1bd21b00d719f8128d6e93145777d4a7fcb06a78b49b986dd573d58672d9a772cce7ee17d60d
371	1	375	\\x4569787f4367681f9cdea0df33a21dac2f775711d7ca4c8387697a7a4a0941eae70c295bdcd784fb55e1714b8b2fc9b4692727ea904b779b8e919f1e335a5005
372	1	228	\\x3f87e4e41b46e3d994208bc5e0665d8d8d5543faed5eef15e67e850a30259bc3b9f55a2f2a365646f7a61789ab3151630ac8ef8c8068081d0eb74cd0b01e5806
373	1	202	\\x1f0bf3ef7ae06094e294cddb220fdfb179056061c5455d59acdd49734313e5ba521fe83638bc694929dced06bdde2dc58abcf549b3c7e67f2380c6eedcbc950d
374	1	420	\\x70cfe1f6d33a4d2d29c316aa47a03135be76813546e2c1550d7850f3df11e55e28c42e701a876da35fdd6a1ed038ddbc9717d89f18db4e8871f0e71b4fa29405
375	1	169	\\xd3fbf898f5d5ae6f2981279c973f3513672999beea3403577a1829ea197763c362a697efdc4c4cd4e44f78bae573cf03cc48cd5f047e194df21a3d5bb8857a0c
376	1	360	\\x3b1b44b8b8e61052bca633a4fab5c9b91e5e2e18a4fd4baa9dcfb03f26f6cd68cef12d7d6ea154f140dab7f990be6b41180c002b363e15d94f92c6a44d407f0f
377	1	171	\\x6e21fed87e6e639ee0bf1085fed0c010edc8bf8a9a470e7cdb3b77abc0de05680ea2fdad4df62a85e6caad5441046982f20630cde0989c37028b2f4abdcaf101
378	1	47	\\xd540ca1768e6ed501fd712842c180a8521495027522424859172659639238b34e49b32b3f8a63e21b78ccead725267d53d8db6e2059d08bc05847c249b3d5d08
379	1	3	\\xb9c973109a4282e58482c0b746f436f1497aabc5e2be3fac4fd775bd80ee0bdf839a6ce39f84026e793ea3fb8855180ab37462b2536401e58e9f0f72302a3501
380	1	306	\\x1bb6a97aad8058cd443f460cd20f2d3e32317de8cbac5eabc6a049b46129ca98227d7affd0db7425646f5c084544363f4b4d185b58211b62e0601290b6510503
381	1	113	\\x4f763f4e0a361e20bd6b5ff335fe25a00f2fca228d224599e7f99386f19f609d8db7ace55d3d8e74d1b607c441596e33809a960b834a8c62e1029c77512d9003
382	1	269	\\xa027e05d752460b43834d6677871e240636e10b0e9b7fd0fbf281e946c67941eb640ac48e252b8521b9fd5f18bd53455f4c806157c984e0258d735b378af6101
383	1	244	\\x516e8ae058b7420c32830bd08f941cc9f42abca7c987fb193c9ca20510c0aa47d3d595eea2cbb41a804c1bbc2dc8262fc3f5d5613485cc895dacc9a4d2ca9b03
384	1	410	\\x32d6ffc90db3c06fa763bf2fcaa17a42dd88ed7a9ca99d09e8bc1dabc89c3ce304d6e3a1a4bf71dc03d30c83497123860792c92dcddc236524d913337027d708
385	1	322	\\xb7d2f7359c7bc6769cc380faa22cd8cb4442114b5d042dd3f9795d22e6905e833c4d5594fdd7513ebddb5e5fb5da80d6bee59fc6443cf3778ad8e0d6a4761201
386	1	265	\\xe42b2a2d96d822a17ae8405fb3981a0ef8f5ac784835d34191b777caf41ae5176c4e01e77dc452d9e435046ad32a6d51f064454444bf1af20dd1fb6f83b1c506
387	1	234	\\x4fff6c8cb456ca4616e665070485b8bccee9b95371b84b00b3a0181a07eab8c14a7376d8f88e352880611843060657c0e5280560d4be357126878bc2df0ed104
388	1	125	\\x1ba59c00205b2b3077dadcf21582249f2ccebf505f96f778fdd3e0cca0a23760f75cf6e6efef02d7d8a957d125927f927873bf2619cbdb297fc8d6789fed0807
389	1	20	\\xc86876d7ed5e2a6f50679f5e49f8d976e2620a77c8cb307526454ee5745e77778c7ed5ee4e07f3a1c3859d37f67aab85390f5e190de6145e69921846055e2800
390	1	199	\\x85f2adcb6b7d8778bd3292fb315783e7fc2fa2f3d3f29f8717a48d93417ec0e0adcf15f9e80040d734f5e1a035a051b0d7dbfcbac5d038cd6fde70e688636309
391	1	18	\\x9ff679915daf1ce9e38c334d1155b258cab118e915d50ae44da1db507040ef5977006e4324c7354841fa7cc5cf35f8528126b1a383fe141449b7cec8fffd2a02
392	1	382	\\xb5399e5376d5d332c06e87475a63a98f1ff18795f6d72608da0021738ca600754fdb76b89b0e533628426fb9abeba3f0472cbfa8506329f34e9ead0f5f96f20e
393	1	340	\\xce532188bb438aa8380f0a9c24f829fd48ad3388c3bab74dc7f6701c159fa803aee95047820095efec1fba6c234225216f7665fed23f188c902790d350672301
394	1	16	\\xe5a1831daac7db0fda94cda11ae81f356a92ec4c9c5059e2c812b6f37b9e15f761895f45b513f3df95962fcd0403b5c7b5d14a143a42eb2203abdd5956a9bc0b
395	1	385	\\x36a374c3155395fbff9b5f0ce077fcf74c522363a2736ea6fc81cc850b140392ba3556192b949594425631004c449515c5c07db6ccb516b15206331b8c598005
396	1	7	\\x406fdcfaa5bbb0c6f422b7992ca78d0b8e4ae8c2983a6f4c14fff5fc0b9a78d0e77f9bb2084c2076e8f88ea8115e5181959285720ce5a8f821de133267fc500b
397	1	176	\\x0d966a05e2d1a10f2b9f928a6dbd7bfa09fe9e2aae1f791797f29f74674c5e012bdd4acdf71bedad69e4432609b39d32ca6a924b02240962e33ded1e283ffa0d
398	1	72	\\x7b2c60869dd340e6441c600ac9be59ad91ecd22b6d252ea4496a17a6e935e43e6b5666a7ad9ecacb4e2a83405ea0465362ee7e96c6d6163cb1b8817c293ae103
399	1	302	\\x99a33a7a7cac1044fe09c1c46164db1fe712af7ee6d46d2bc574afa5a26fa62238ffd2a2f37b0283fb8e3b5c8f566e1d934a28fe3b34df1e7e651bd47acb930d
400	1	374	\\x08874ad392455d2989b93be7a7e8971cae374e4e9c339a16741837a35c7ab387b79899da6426e84749b05b9213051bae662964e5967875d718c7249159c4890d
401	1	137	\\xba1557433dcf0e4e6b5aca805c68e59377a6a4cc27f50282f11ea7fcfbbbf47df20f5e51a715431fd7080580a21280fa417f1680d5dbec70df9b9b6b970cb609
402	1	393	\\x86d1f9f80e8c2e319123330a9203b8183c9a8ae2dec6707c142c6f5177e4eaf3e6f62eceb3019e29295ca8af0e42fe7e362f7186ed712ba92bbecd3cb0ac9f02
403	1	343	\\xf30efb169ca183dbbbbbe4addd71471988483531b0a1fa37821f52e8c6c11b2b6817ae0597efd4dd89b333ccfbc8dcd6b2582a6756d10456612a506b892b7a07
404	1	207	\\xe2283dbd00c516e1545e69e2e4ce5efae2d249b9d4b0c77c1053acd3a6b37ae623602b7ddaf0fd28fb6c94d16eb0c77737b64703f1714c575b0b15a69213d607
405	1	246	\\xa07d3df777931481c7faf7658f658e78041e9e262052b44990c845aee20c5544c46d5c88e4b76edf384b9f02e72470125638dd63afc59ddcd392177baf3acf0c
406	1	291	\\x677f1e4d31f1c5d9ee65334d34eeccf345bf605c36beaf24c06a2ca53af1d2ad12ab0b2ba00654edc2ee8d903061c525562dd838e747a4c998b40a88123cf20e
407	1	323	\\xf8ffa4fb7fbfdf227ce5226d61e95ac56d63254ee5ebef9b77216918b1bf3574a972f0f7feee8a0f0b787134e87cc1ae6fab02eb69bbda0c52e7fb975b49f501
408	1	118	\\x89c9a2bdb7d56127532acdfa821d798b12df4510b84b6ea137d89ac7ce7397406362813bb7ab0fd69184d1fc0c687e2a1851e270d12097a0f37355b35bfaa609
409	1	313	\\xcffe51e90d7cb27bb69e3fc12def055bc8df0a6c9f619b9cc43c94fad8a5d6f432fccab2ec48b47bd009b348b7647eddafcdcb4432201d58c3cf09dcd7b29104
410	1	200	\\x25f02dbbc7123fdfaf9b11af980bf17967e1535999a34b2d5e2705767561e9f4c6045839ca018997701607ea0edef15cd79b79bab497bc6d811d9bdb89122401
411	1	165	\\xf613194ab79a02e64ddfc4e70d07f92092071dd27bccf848489e855b00e43e5a18689895601a1c07d386040855da60f16c4b88343a0c67e3aa2b030011bf4c01
412	1	196	\\x3b36e52ff13aa4c4031b0ec336500d1f98c03d7077ede8f532027dd16b30803672e60e98035e3a8a726b820f2aedf9738369d095e8d4abdc9d276e1804385c0f
413	1	120	\\x17453328a4c71f8c6b53488dfed7fca34181018d7edd5c9e43faf5b1259b6b95bea668ac3d864db8577164308d00fc14eb7e014195f76ec301e1a287a21d0f05
414	1	117	\\xe7c7f9fb695a6edbd426b35270ff89a1feb3851dafcd0af3d140dd61804457c518617c45fc6899b11872f7d7fe398ad0b667691551efa093afa16dfe7c5ded0e
415	1	159	\\xa87211ba704ee0043a06eaa1d0682f933e7044c19b75f4731dec3f7e6549f22cf9df0b280260856576342b5d0c4dd75a8f89e9efd80505a957fdb0593fa5d402
416	1	349	\\x0bf5c6d7d2aeaf61d3c8996a488d00ec649f11c67a11e8d7248bc1c51bd52dbea5b71a27ea44931abb063227cb76c1d2b96225d8e6f899c21ebc98d1293bfc0d
417	1	384	\\x46fe6d1363942e45528980c36f92aeeec27c4f2f0a97a16b808bf8c5c456cef13b6b405603b94949e3212b1ce274655389a3341a6e21a839d37fe2a686d9310e
418	1	83	\\x0e197cfd4bbafe4067ed3f9318e34f3357a2fc6ab3a511509e5f11a6f1044f7fe52c0310d514975484f3079e765958b913f9c1196e94c9411a39e0b72572a103
419	1	28	\\x217f305b138ae268c6ab9f8f1f7202e91ae731b536aef8b43587e450315960a5314911831c9263db865f6ef98717f4bdeedb29f0182dd4326ce4e26c36448b0d
420	1	151	\\x98238b39beb0e3e2ae5c34bc17bebd61bc81cbd31acf13043c0d5882be99f3a88d56db0f3bc6758330923d13c4a0831f48adc270ef616f51c8c0327de504ee0e
421	1	299	\\xa99f6c51b5268207b195f46a71c385dc0b8dba9c02c22da3b6616b76593815f85f27b02ac0e3718867bb678fa2a656ce56c3d80f6cd13b1b0cf6cd2a13b9c20f
422	1	114	\\x1295d8cba21d39031885c8ca21cbb2d823bec92b740d27a419b3c681777073b5ed370429d21aff4843b3574fabadf4f58be01205979811a806c1b9d2fb898702
423	1	415	\\x7f55db12c37ef8e0c790ddcd453943b0d7921ef7345025031ee717163bdffdfdc290aa522743e965a703dcdd3f85d62b909cb23c484e5fef7e074bb6b9f38404
424	1	400	\\xf1e607b65f4220710efbad182c2f1545810410ce6646d0d3f8c3866fde9416598e3cc46f96618d56f08897da45f59571fa40803a4f0f166fbfdc6f524879a30d
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
\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	1647487288000000	1654744888000000	1657164088000000	\\x9e6363499f5c663293f10efe7f72a7c76cf3bac925504b21269775abcc978d65	\\x024e2e010c08df2ba31b5799c0b929de4a250ce6199dbaa16f90ade681a3d6ce2311fe551dbfa0122bb5d6462677037f97afe10354f1ed1e37881524cfedf702
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	http://localhost:8081/
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
1	\\x2dd49e44e32b992a2a48214669ea306dcfabd1b2de59bb0ff5dbffd970c04b67	TESTKUDOS Auditor	http://localhost:8083/	t	1647487295000000
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
1	pbkdf2_sha256$260000$lQaJLEw2C8Up2cXTVlgxUH$+xPWykPlTlI52r/fwIt0aznyH0bLHRAoiYM5P2sb2To=	\N	f	Bank				f	t	2022-03-17 04:21:28.9389+01
3	pbkdf2_sha256$260000$jWHpn4FPSl2nLyPJgj5NeQ$HiOsOAnX2pNkMEfwgW+JOA5dicUEiGuJ5/nmOUvVqZE=	\N	f	blog				f	t	2022-03-17 04:21:29.224292+01
4	pbkdf2_sha256$260000$B4zumPSSTUQgB3vExPtSjs$ySlRIFQ6TpwxotmnF9Rbw4f55gHLIVIFTaLHQ8ugEEc=	\N	f	Tor				f	t	2022-03-17 04:21:29.365273+01
5	pbkdf2_sha256$260000$dqB2LfGlnfRlRyHpqSFyOL$OdXYsaoBlH5mmVUpMPkBCvEMEbHMGgTKw+x2I8poHCo=	\N	f	GNUnet				f	t	2022-03-17 04:21:29.507263+01
6	pbkdf2_sha256$260000$4rxIuO76cBB0boK1znkJRj$WQqcyZ4uIP5/xjnx9VGmseX530ntSKMu+zxhAw9kXQ0=	\N	f	Taler				f	t	2022-03-17 04:21:29.652796+01
7	pbkdf2_sha256$260000$yoF7tAeUo8lEInb91yv8C3$aptpSlxXvB+8wIq2Y4lB06UiTtvwU1PQlakXpWq5oww=	\N	f	FSF				f	t	2022-03-17 04:21:29.802261+01
8	pbkdf2_sha256$260000$hZPcxT2ZYl8cDUgb6UeeAS$zgZKi13urmxjUU9XICyB8fjOmv5MJDsex6/JshIwpss=	\N	f	Tutorial				f	t	2022-03-17 04:21:29.942522+01
9	pbkdf2_sha256$260000$7M1xlRRf695ZeMkkBuw6G5$n//pU1Hv99eElSEmDX72SAYC0K1+eqDWt8i1Zl65OQs=	\N	f	Survey				f	t	2022-03-17 04:21:30.085447+01
10	pbkdf2_sha256$260000$zkkaiknIGj6TNSJKDUZ7H6$zwNf5Af8BNetgcHWEc+459joi836EXNRlb1F5FT3Y6k=	\N	f	42				f	t	2022-03-17 04:21:30.590683+01
11	pbkdf2_sha256$260000$uPfYZs8nY274BXSahvxYJq$hDz7i2IASI7wo0mQceZA6a1OwlIbwbjFPAptnv8p2wY=	\N	f	43				f	t	2022-03-17 04:21:31.063875+01
2	pbkdf2_sha256$260000$CMYDB5shdB0gycOa8RLeAB$n3xi0HoJQwv4zwe5bHkNgkwhmbzPgesZJTsezNuQL68=	\N	f	Exchange				f	t	2022-03-17 04:21:29.082628+01
12	pbkdf2_sha256$260000$5W9xKo9TYXsvXJw9Oxkf2n$uvA0BNDd3kjPNDFK5f0Ez/rcZi9L+vG0xHrkvQiZvrg=	\N	f	testuser-6cts6znz				f	t	2022-03-17 04:21:37.611199+01
13	pbkdf2_sha256$260000$gSCF7gY2qnOcE3t8s16peK$Nufnf+bwIN9b9nBJZ1Pswdx2jvT9a9IymzcU/HydFpQ=	\N	f	testuser-e2lwc5ki				f	t	2022-03-17 04:21:48.948619+01
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
1	\\x09485a30798c831c41b788f698e135f482bfdc487247ebe09c21a707a3bbc06028a6e8151493387e94f3d6c1ba130704998fadf7b1b267bcaf4ef071f3093586	1	0	\\x000000010000000000800003cbbda7921f2f5189fad524da274598307b44aa2f40d491bcf91883ff1f65ce07c7fa3d2f7b15cf532e092d8cc8a2849cafc402e998a253563c519ca6993e4f8288b1ccb1af135889c4990f9b66b3bb8c399262a8c8453e072c7cdb5a9ee2ee9bc00c4f034efd2547dee3676da64403aa5885a379a86c6fbdb4436cd5b4dc238d010001	\\xa5b7d38bd467fb0cbc96d37a791cb848715f1e2d2a9651000ae2f39f1aabe606333282f3cbc2e54d30ad4924c3df56730edc5a34ae6110fe144c2735fb1b8501	1654136788000000	1654741588000000	1717813588000000	1812421588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
2	\\x0a50844a82e9a4915c6212ae02f9a465a0835055c5e47786878903b96063cf9d2c54bc7b56af45825ca1708c1e922c9ea65dce7ccab008e76440a2a2623a38ca	1	0	\\x000000010000000000800003c76da2c6845f4815359c9d9eecbe96574d56a5bb647bd651b2f9b1c82a742566bc866b7008a24360838cfdd442b9bcb7e2cc3cf0abc82594834f588c8c0fbf8f10f6431363c45f4519f1887f1704ad635754e2ead897454e83191d16133cb790b96dc63f526daa51367023bc25e4b2c1acaae9689fb0a5b9504e71e5b6726251010001	\\x5cf65adb558646c17d3c291dfbdc68f214a4e243a7368520e0b1149b65a08fbbab002fc6128dea8d3e6d7d81e4e2835fb43587ce365f2899b43043f057596806	1678921288000000	1679526088000000	1742598088000000	1837206088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
3	\\x0b2820b472679ab1a287b7b808c88d7936c13eebfd7da90b4f7b7682e7928a7195379bd095d02e93d4e05abc5994b901e4cf53c1446b9780ecd077d21992d4b1	1	0	\\x000000010000000000800003dd5f9df70f1df247987adb2433642fffd5d24a6aacb23d2222aec51e5b4e950784a0702f879f09c518d381b4aa37fa11dccfb99946143ad5856f28ec4db9810475fe2e87a2853821f96c446b0fcc0e4d94639cd2806ea800afc81a6d0b573f1c9942d3f69f31b08d71d61fd22e00cece6b1e87c1ca7f9865bf84354cb7df57ed010001	\\xda3bb2501981f1588c220187b25d8b3d16bfcd5ce269cd4e65512ddd47668db0576e7125c912974b8b25411cb3e70db933c598ca4a00686c3cbd4560659cbb09	1650509788000000	1651114588000000	1714186588000000	1808794588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
4	\\x0e8824a27965de828a47b92b65dcd08adcb5c2745909120f7be13239723466bf93a964f764cb2a25bf64c10adef5325cd1a5b24ccdc0657a6bf433f352c66991	1	0	\\x000000010000000000800003c1b5edd65039ca30e1122cbdd88b839a63728deb690bd19b899b2d9d1ccbeb7cc2b6aa3accfdd432ef03256fb6d35051ecbb78db4c4d58c518feb029c0da4e87181a43cde622fe6e267138edaca8d9e7f0d8128bbd3ed212f7ff02821b66add98501962c62cc75155650ea775aeae1d34a367734c93f210f33001b200e59dff1010001	\\x11cc3de0a62e78db319eaeea89ebff621040ef147fe99da103b2416a530732f9c97e09393544ec94e2f14827489303f3868792f5d9820798df6a9591d1905d07	1665017788000000	1665622588000000	1728694588000000	1823302588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
5	\\x0f345c7649845a92e4e057ed2fb170e036e6a9d43893fc3a1c33a0ac5f6d814b86942db554a861bedc4594d2202023b1251a741a8ca8f9e4c08b8371e8c7e448	1	0	\\x000000010000000000800003b1274ad35d4924dff38da1603237e780a1a9fb9fad1160489514c844847917a27dcf737e93244a8fcaa0ec402e34cb964d4bf1f186408e0cb1668ea9178180d663646c5d65a43e884161a9161f6efe4a7e576036fff1a6ee040a1315b10809af9cf0e3b17a430478af2870c595fa3f8b361cf63bf1f5973e8de7aa97f2868c2d010001	\\xf5c124e66f8316e38b27e176b7b9ad545c5716daf4cd73bea131de11dcfeba080db3e4a3486bf234023eb4f8f5af966fbd5cb2b4aca51470113af58973041d04	1673480788000000	1674085588000000	1737157588000000	1831765588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x11a4f17ccd34ab534c507a8f59be57176a6e21e3501e4cbda0d56790c363251c86e1ce0e5c442b15450567aad6cdef2c753ee74d649565ad6450ab2d10413eed	1	0	\\x000000010000000000800003bd85d99ec46665c858aa9f1c0a26e15b40fe6280a8bade9fcea04cf45bfce73cf88885256a26a1ac267e97c87b8f9205b40d66480c262aa7a7034f0dcdc10666cad4d1b942814e5802b9c5a4dd62c79fd4fb64958e07ea2031b531a6d28a72b9954fea42f07bb8fe4f3dd9cd9481e9ff1724e8aafc044de014aeac166e2692cb010001	\\x424ffef834d281a3b0310f5505c7c41e6964353b5768732dea94a2f59768383d5e92c87bb44fff95083c62dcb4188344ecfc5bbdff164d25706371c7180ac400	1671667288000000	1672272088000000	1735344088000000	1829952088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
7	\\x12f0a1e3c9ec3991cb3bcddc52f91c3cdcf379f548d9b4b36f6c2e793d966f9c1455aed486dc72764b4913daf1deac285632b30eb3b320066803b5a1ea0e5e7b	1	0	\\x000000010000000000800003d267e84783f317218deebb31aaade10c4f5c2df5ff699eb45a75d9a9c71eabd46644c43ebc44174bc2dd70c95765579a08ab87cd836362d0a45a8131469f9c2ba38826d62d2197fed5b6c36d72a4e886560155e7bd38f04ff33d2d2fedf3f14fd1e5f3178e04aca1ee8c886258131814e116e2d97262dd00ef40c1a0c4685c39010001	\\x2a97dfc4560ca580e6b274688ba68774e3fc3ddf9ca9fd279fda03f987190e1d0587174e0fd1bfa5d2e7d1d2385cf45e71e934ec71c6b9dc2d26b86e4c91a206	1649300788000000	1649905588000000	1712977588000000	1807585588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
8	\\x13541031778bb18741590dbf3c88f30190051ca54dd3e7fe4af09200df6c66e1af97fac4060b6f3de058574d934a40152c93823902bdb73d292c60f09ade8297	1	0	\\x000000010000000000800003a9b029fe5eddf15b0a1804ea049f1a9154b319c8e0045fa963f7fdbca2439e724465b8f1c2ca49e4df17546dcedcedec82781f536fbb9ac2b0a4d47a9c3b97a9160446162dc8006caf0ded3e98049700dcefacc346f65d70ab25a9d21eb0c57dea847393100e090c4d5b2f9dff3abf5ef9e56bc9dc9bf239f0ee2d2158799dbb010001	\\xc9326748b7ebf1bab353199f09a47d163cc2961608969b9f4668025774eaffdaba9d30b77af6a6d4ff3e30886580cf97448240835b8ca29ad43f6bb72fc29e09	1659577288000000	1660182088000000	1723254088000000	1817862088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x18246f4fb8b0ab5a1b7662511a345d124db03dc4821c741b7940de19ae2e992124b971c914b601b1418f7d7690fb7ee1620472ff3dc680a6c5f0e91fcda68a87	1	0	\\x000000010000000000800003e91e03c7d65d0be1f79009908372e1538387e3ca7f4fe2ed3dbb7761e33ded8c0463d6f5d55a9dd06e2ab86d0edb85cf3419b862f641f1d39f6cab3d0a2f0dcebf78eb7384a0f7083398b88959d8c8dbef76b151f0c006c1f055bef1204bc7f1e2f3721382258b95ca302126035924e64ee19a1d2ad47820374ad7d60c2f79d5010001	\\xe9b10be21d6a7a3c7f15bb3c15609c7b57d3564cbfa51cd2560e94107fb7fb56223f8c27714379c452185e62d95fff3dff8b211a3d4b67ae91d59ec99103c304	1673480788000000	1674085588000000	1737157588000000	1831765588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
10	\\x1bbc582fa9ad9a3c8cdc9a3fbedea95034cfdd74bfd458f1e3a53fc8735e6a7f343ad1322153658622b2ba284dac5a0061c8252a3c80215d607b621c78115422	1	0	\\x000000010000000000800003f3e2b846ff97d96f39505970ac4f80274c4fd1db9842ac4e1e971033b1a7e5646efb018098905415e84b78fe0d8cc70c2b1f279a9ca5c29b232a28bda84914b239be34dd9e19c900da5d347d33ab6ce506da448a5ebcfdf65d9b2f287dddf113accf7d02532c4b366c758b69c5fbbc0464091417ecbd6387fb976b436c079397010001	\\xcad94a5ecad6243f38e8e65517bf9b39e47aa47b0581627fa2f3eba525e94519b59a0985a4880f2213b8f3d77a4f1dbea88b2b067ce4eed4a12aad63329e2304	1672271788000000	1672876588000000	1735948588000000	1830556588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
11	\\x1f7c0ca9cf4501574a0298cf932e158ac80c842b2c90655f8bf9cf4e6e4624da030ba973222e2eb80a5b9099f63c687bb6768dbe031cfa20a75f26a83b7350aa	1	0	\\x000000010000000000800003ca7eedd783b5d57c6c7d90da01a8159906c5a1524a56951bddb29aaaac9bd213ea5dad74ee21debd06d1afbb1e96e56e261bbd907695db407a3fb6ff922bc857ea4d9b8257c636da115e639f07f540ba5e7f7f19a35bbcfc9547a04f1b074c2610d4168ed8542ccaf8f233d1195a614f35a918ad47e76eb04f679088a048b27b010001	\\xd6b7074aba1890005d392d84c4aed316fc89cbc8ce1c95545be2b8d4f7d437d5507f633e9ecc284981eb27d8f5b8e555694e1a3a17652849a705f08f5ae4210d	1654136788000000	1654741588000000	1717813588000000	1812421588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x230c981baa31a5ab16a70cec77181695a0d03c1b9c67040053d9ed91e0938c08ddcd1aeb222e989cde36d92c7dba2517153985cf68e909877dfa46874159b5f1	1	0	\\x000000010000000000800003b3a881682293d45a7cad59a5a95eb57bd942d222ef2f7812efba20bd8a76318bb7657f18604286ee812c4b7f5a194419e89af3b436d2e678ba25f8c8dbedcf94b0993521b480e1e1903b28a334d39c5022657a0ba959a5698bcf379befdd0b41ec7175dda297b5cf7d5d2e26feaeeba6295df306b1ca9b8b03fcb6bac2d25fab010001	\\xc1d1954c4e7211aafa2742f1522bfbf59da6c27ed50e675f32c26a73d8b7271f987570a87834c5e22c16d80254851cc8013dd3096ea8c5a71c53bfe11a631b09	1664413288000000	1665018088000000	1728090088000000	1822698088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x2408cc899713fcbf17b3b07b04090e527dfaced6daf47e16265d7b304007acf7fc23e9d6c23f63b6e9c86eb498bf8dba8bbfb867c7a2d95a72edbce4fe300bd0	1	0	\\x000000010000000000800003ad9574f3da0f26ee7fff672431f554529acdc9501c0b84146bada2beae288dc71d0ece73168d6ebc3b89a74f8561f24b3c49a227232dafb82458d6b30eed92ef1ca79698712b16d4896f36b9514d49705445263ee5fd4b6abdc30948bf11d71f55739e3829acbd8abf5b28d46d90729e27404b01a3af0e88a3fbfe6230e6714b010001	\\x80b2187f7b9534a7d013e8209e2f61285ffb7d803f09b71ffa66b2be5f97efabef25ac35ef1580fa22ade7bafdb81c8005b6e46f67f822e6a2473c26e5b82e04	1658368288000000	1658973088000000	1722045088000000	1816653088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x29b4de39cfc16e4d6c9f140927ccd14af7580c7971d1e6b7b5d8394530ab38872312825ad967c92f95c7b19ce5fecb1774794affb1a00582f6fcb6228c0e1262	1	0	\\x000000010000000000800003c21fb367052c35f0bf9ada0f7d31b9577f98fed0993aeb50bcba94b82049717cc9e5527274ad882f53b0aee95d9f1624691583f8ed07163b5d9d77dbe59e772c04eaaeee4e6abc3955f9dc86d22af22a3aa3a5add9d4560c9838e56ba55ecc85425cae1f1479e2b5fc735ce4f91ed4f01c64ec6ff17f0e00dfaabff7e04e3c05010001	\\x3f06d742ee6ff690ff977676b4d6d2f4542e2e28517fae2fea50202db7050075c01dbd4a66c3ca3c9a98539996c04d5bd135902c6dba3251bf950f5f5c46fa03	1652927788000000	1653532588000000	1716604588000000	1811212588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
15	\\x2af8776469f5240a564c0592db03eeb7492745d074bb4b3ac60e92040f4f3d4b5df7a2c0a5a39617e5e9a095642e34dd0cde2c7c7045bb43b875a25469b0cffa	1	0	\\x000000010000000000800003d73e42f77a5115e5c9af81ed97aba9c1b1bd6a328301aad4eabb00ebffd9a608f3de2053ecf0ce6dc97561d0938a663156b9035cf30b2d9cc3f02783eb7685e8cf1604511778913108a5ce7cc3940bac4bdcbd3dd06ca92ddd6fd1075e363e78863355215539b8486729fd37bc413c34d2cf2ec51a240010fb8944a8557446ab010001	\\xb31aeeb75c968a1e93daf089e523db9a256ebd0386e8f84f89c31ad6682aff3e638af813fe536232b9b414c2c28198b160237f873e1033621eb791e96c87a70c	1655950288000000	1656555088000000	1719627088000000	1814235088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
16	\\x2b74cfe2545d244cfcbcd8a056c673e42d262d64e3b49d20fe23a36d0839205cb76a8873030dd1768d68f812e63dbaa045b2f61a0fc782c0957b5cbe9d016ce4	1	0	\\x000000010000000000800003d7edb137ceb253e15fa49fb34ad2cfa75d0bd60ba0bcc2202299378eea8ba8cec0a7f4dd254913acb1a6fbefda86533ad52493e5fa5235568391e090b80f51aff66c3e04a312f6ea2aaf357e720f3c1f6a5f79c3da72f38cbe9a1b0d5a26f018e01d0f1a5d6fff83ccb2059c4a33f1edd1a12fe0cbd3a8264bbf2ad449254587010001	\\x02bb604372fa490720ed11c03a5a5cc1823ccaad521e7ae7be251185be368a27832fdafbbb4e655d1709c1343c7a93e7bd3b472075294f9af0d5d5d8c0957a01	1649300788000000	1649905588000000	1712977588000000	1807585588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
17	\\x316426f38707935698355c3769cde7da263696f0d7d0da109e6bdfc1ab928815bdf1cc3a7a483dd79b5d4711afa8bd038fbeb98e0cb935746d86755890c1f29c	1	0	\\x000000010000000000800003b7ed19dfbfdac8b62f39ec5b9306aac5ea31cc167582c8d71224db67eddd4f647fedb9aba2097a1521f2bc1aeb61e81a7f157ccfd738ab153ebe48974084d14494586a23e24a2af75388c481f2b729ad96f27aa23717f2ca96e16f45d063b6ce1abf5fef69f93458d843ff9ac84a5c0a0e0c60f446a198b0d63ccdae955ce71b010001	\\x2fab861523c0bc901f5963ad00a5a129a6e5984b14800d025aab87da8b94f1525f3fa32b19cb60863e3f18bcb9222ec10da1a216c16ba24c77932399ec55320f	1665622288000000	1666227088000000	1729299088000000	1823907088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x3248977493bfb8346f28421531491b07822aa121e51f134ba09367972aca5d2b4f6dd9ab5e0b5b549e373ce3d915cd7b2cd89d0a746f67a0d6ca19288d021e9c	1	0	\\x000000010000000000800003dc348fd537893ca279ac31b170d2955352bedc144fc807c69a3b57e36e308a00be39efa0db8a1a8703571771ebd0e89e651f4ea9817cf1177279a894921af7a3b5de4edfb9d27fb2a10855f0bd2743691f7ce33a828b299cb5322aa7c2c83f9d276bc9d162b83077b441f0413dae832015ef280b40dcb631de475dc613f7753f010001	\\xd507a570cc87989663139f23070aaa9daaeea9471d72195e08e26052766ff4a828c7fdb6f5fa874e2aca7a2b0844164f88a43f43ae91349cfeadc83af7287705	1649905288000000	1650510088000000	1713582088000000	1808190088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
19	\\x32bcde8c0e7d6019b98fbb8b0a1976f6fe2c16d807d9ea6537ca02ed6fa4f38f38cbb2ba2415e02e9cbe60d600a0c2d3cb9730aa366370a1617808e90609da26	1	0	\\x000000010000000000800003e9dab03dd3bf5d3301a1f1ea353bb5b303083b39c6375fd5a0867df07bb6f87a7763e585bc60c7a615cb3024d1495afb38b8b3e00b22cdd10296aa088c6c11e2052d7ccd14b8ae44b573fbaedc7d3b534bb6f2cd5847123bcdfacb83552d7d03e94667e903b25cbc8ab773ffca55b1fe46bb1035e4a047c5124d083a5bc99075010001	\\x2d2ac2ed180678b7416ed2e3ad5a3135a0f931adc26c6a39585fd0f081debf881aa23ee6045aa80a121b2105c1785e97936fa8e054fbe86ab96be32d4a30d908	1663204288000000	1663809088000000	1726881088000000	1821489088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x347c70e836f6070a3325338b0d89ceeb8db4afcb7dc0118f877795083784cb84b64accf1e5c31b01da00f4f870d7ffa23c427861efdb4bc607f8a396cf6ba153	1	0	\\x000000010000000000800003d98f9be5ea94409d3ac196d5662be2a7206da4cc0444d5cfce5468a0b63f6267cf0b6e30562624a0e967cbbc9f7d874f8f225e8921bc9bdcfd6b34022de77e22bb78461308c282db0306744a299b8b6f4599db0f5dd366bc7775756b12678c6db4e0b450387cdd740aaf8b5d375b40cf3bd83aa6dc77df37de5f5b9f2aad6b45010001	\\x070c21d77abd2a830c551dd5ed1de822a7b4bec01f24b6d4e0315665dc4952f60285c0ecffa3bb71208e101bc0e07655e5d7e4b143d8b507d0bca999d881ab01	1649905288000000	1650510088000000	1713582088000000	1808190088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x35ece9ccbb2d0f9534226ee4803b29637012cec29a81d901dad7dceb46e98e44e1eb3b3dd1bb68f43b38d4f77a48a925e21b5438fff96d0988bfba7f7908f39e	1	0	\\x000000010000000000800003d3e155e89b997163f1ce926c9e00c0f3294a720842ee608d6dcb050ece1d868ea55d59dc896a2a7b3a14fc1bcf03d763a92e98c4e611938418ad248fc6535d88cabbc452401a6c5ce9b52f7a9819c57f3a35a0470d87fa3b7450f60ae383a4fb56ffde329bd8065695bb2dc6cfd14768e2735ba04fd2773421be9c65363366ad010001	\\xa83da809338679df43b8472128ea9cd6ba28723648e4ff4cde3fb3a442a6732018e5fe1e1727a28d1bba20e19568a088728a8236a18e22f6fe44710543abc90e	1673480788000000	1674085588000000	1737157588000000	1831765588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
22	\\x3940b9d315e30ca42c5d754d02c9fbacd9b7c58870aaf873ff0af3c7291599f8daf8385a1e8d1cb8d5e279061c7d6fea10b40b6ef45e1b17b998dc300d294555	1	0	\\x000000010000000000800003d75653cb53fe1cca3c0f985fadbff1a6eabb1effe41a4636cf2d2854699f510a2f109f3a7a533d41b6c6f380f15b8655171099c3a791645e99bc2225f41152d24a62e108f1e59ef4acc30a5b9ff185931a7d83e4716ec72f8a5fceb383107a394c43bb852b37da49bcc28933451346f30c922e1d8921f858ae13f6489b61168b010001	\\xb1ae470561d1f4ec277a245b190ef2c77a5cdd87037f1bbe9832ac2b8abcedb9c0c288805266ed64ed1371c7a3319ea8746bdfe1366f965991f6f16ed311d000	1661995288000000	1662600088000000	1725672088000000	1820280088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
23	\\x3c6c28a54d14bdc82734900fd1f72d7f86a2e8f9583b0c6e5770030f75e4cebd16d00b6dc34f4554b945b0d49553a1aa6e51c70ea8b4f79281e575ca70856a65	1	0	\\x000000010000000000800003a30551e73fd1faa966a9d6400529de690b7d1a355f397a920cdc40ce372b4fc80e24caad68cf621e263261042bfdfe55bda00307b8bcaf9edea65394c294a41b6df3f3af310d0af6150d6cbd950364b56fc4e1545206cf4ea32a2eadf9445c2fcea7387a69327113cc664d6d2af74286b3160c7969faa69bcd5333afcddffa3f010001	\\x90aa67d7013eb5bc2a8a925389a8a61e866134c60815a3b0d6cf81c167714fdf5176033a553594edcc1e126bb7eb5a55cd07192455bd2f57ff413dcbf6dd570d	1654136788000000	1654741588000000	1717813588000000	1812421588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x4054ceb1d9009e44930ade7064d99ba690ff566852899548f7ecd752582f08d97f8408cb9faf9f52d529806842e15d949216f3b525669120592b722010901b7d	1	0	\\x000000010000000000800003d8442bc411076cf39553af755129b5a8ee1beb5ed15f72b06519578a044995de2cb3fa45f1d64a7862f431b7d866603c6afa4bdb1a0e05c508a1caa083d89f14f0f74e7a438e8a0eef129230574e4eb2cc806cb272fdc5fab75a1386527fb01cc51d717cda4653109728a07019761aa345a9769a393c2a57f9e88f44136a2557010001	\\x0f937d6a6325897e8374ab0541215537d955eeec5ac93d918dc13cc4bbeba3d7ea5d9cb046a25f6505e5f54be3bbdd0e2139b7dc2976a440c399537f4141fe00	1657159288000000	1657764088000000	1720836088000000	1815444088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
25	\\x4170c527d25d6f919b6a16f549097663f297c1ad1785c193bd8934dadc8577cd857bdd395fc73b447efc6c7b1e6f22062a86c8d19e43df683cd20b8ac3897fe1	1	0	\\x000000010000000000800003c1b85f0223daee0c814b602b2282874577207b83902541db3ef611b6d9bd651e9a739a3547e580a5b2301c6af33a02851def3822b6b379bcb5626d32c56833d4b72c8566833b19d023ca9c28a5085270b206f66fe95bf55e6f1d5656fe882690cabfbe7588ff8927934ddbd8a58147cb8cd88e0da45005f31606cb09b1e908f3010001	\\x8c0f9e77bc61eed9b24ea082608e912a1ebf62eaf6c7c0b65063185826e83a5b62a7793aea85b9f30038e0f3f8813b0e7cea75e2d83d7ecda442b4983e56ab0d	1655345788000000	1655950588000000	1719022588000000	1813630588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
26	\\x4714783e0902182e9dcbc7443259208b1405304f8f4780199272934d3e17501ef24d191f419ab536f93d8f749ac9f2f505a8e22159a684f9a97c169cf8f35d9a	1	0	\\x000000010000000000800003bf904538e5f5868cc6b84bfc8dbda2c79458ebda03a29d63136a3bdafb888a44d5dd41a7f11d31b482d86becf8095f6494abe099bd078676dce1c899ae7233b2c15bcfee71350715c2d2a13e79a652478b3f20f1c2a0006b49ebd6a9949b6e56a65878f1ce478787a931ccdf239259a77084b06185cd0b5b064aa60108af5123010001	\\x1d757be9557217606b0caba541bd48e3140fe9915a55b2d326cd9e86c13248db5ab589978338826cd39fcf02a2e144ad4bae9a0b06db4f5c90c36d8745cde905	1663808788000000	1664413588000000	1727485588000000	1822093588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
27	\\x4a3883d050ef6b7b4d59e19ad8bf311220ec569a872637918d96161f51764f61eb58d97e7645194afdfcc5e847b2af705e424fc9057b22e4c807f4ad48c84c92	1	0	\\x000000010000000000800003aad9d2fbafefa38b9246e88d4183ebd9cd9f1c3894494510571d23de4540a70855d95a290aa38b7f5ef8b6f0af7710592b1c74af5e69ea3a7cea4217509e1d715c866a4735ebf1d32a2d6ea05d964c2a5aac58bf7ff7a60b812ff8dce75cdf0fece6dd2049dcf57b9e8b3ae08a5d98ea35935feb5de7b901c0de3d6e3267a76d010001	\\x9ba03087a502d42763918b405630057712802e7ab1d925b95ce606c60c6962af82322ec0ceeff24d1371839fba8431db721f43c9de321b425c1d4c56ea819c0f	1665017788000000	1665622588000000	1728694588000000	1823302588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
28	\\x4c4874e90363d8095c31026374ebf13c05496e020769d59365466e395144a129a87afb4c00fd687bd270a49e1c9af13e9d3dfe87442a36f9e91cc38e3cd4ae16	1	0	\\x000000010000000000800003de8e214dc840900928ebd1852b03c4bd41a9690665bdb370e4bbad58c6336f607283d51e23890a92ab38397c69cb162d12f2ca09cc315ef1a6c4b20e526d91415bc6527b3a8ab2423733a591cf8563802628469e528912b6076b0c9353b3f428794ffc8f1b622a6f3b1cd901b65164e30861a19eae403931524362cf7182d6a3010001	\\x923ebf1800587c2f3724dbfca2f0866a25b4389c7547d6d02fd9f41b4b5c6b5fa910c11c87af34dafa225b1a6858bee6f2cb2896775dda0ddac1d8f95522a506	1647487288000000	1648092088000000	1711164088000000	1805772088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x4f90444372091c761f32e4ef04a50b354b8c42937abeeafff9d8859a808e56c7ad3ab5a9d3ea554e952aaf3c7fe1c96060fe3827a7cb988e073fda5f236bb786	1	0	\\x000000010000000000800003edf87c774c55d9dd456532846555decce171a5939dae5c1c0b14ded35d58c802520f396c696fbf2f0d173fa721116f9206faf2bc5611c1a17824f20ee2e279d3c0105641b3fc76515f28f64617f9fef0670714fe32124c17de962dd324d772def078c08e1655cb6286a20ef1a5a299e43ced881d6ad23fa04e1744d148c60b21010001	\\x6fce79f18b59fd08d776a7f7335a1a09dfeafe5bc5ec28328a68dc7724c7b21e2a75694a544a0bf4786d904866139885d57c16277bc5dd7dc122e9b379514e05	1658972788000000	1659577588000000	1722649588000000	1817257588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
30	\\x52dcefbd2f4056d0b866e67b8a9485d0399c16c0e7b6e34964cdaa5fc753891ce84b661005578c64b12aa7e02cfe30968ef20719e23bc09ee6ef45950c837d93	1	0	\\x000000010000000000800003c7ea8381e654749944d20a742f869761af70b77b67b93a658c5e80be1407ae47c1bcbbddaab64ad814d169dabf46637751c0d95de6024943dfacafe9e2c859966671a3d995a847b8777e5dc528601188335690757ffd2fbec5bb244ca436034e05f3591060a6740e571c724fa6c567399067c9a3d3b8ab61a28df0749b46433f010001	\\xb5fda94f9b8aa8c537262d6cb8da3f74d8742677b4c2a43b83047e473efecc77390c9498f4281d5cf7886047b569c61a9ab9b5fb1fcefb1276f21d0dcb50460c	1675898788000000	1676503588000000	1739575588000000	1834183588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x54c8e9252e3ee476bd233ce3f46bfaf9a3b40e80a1f2376ac40f0de43f18c9e1f06094eee7fe8d405e3557784d5ee41a052cd91ae038a10c2cb2e12da431f715	1	0	\\x000000010000000000800003cbdb3a56e560dddf8410316c6e1f86fa100c158c9946dd293382b87237c0c0360866bf1437f42df1950cded8bb6bcc1a275bbb2c0c2b56ad3749a4b96f23d1eccda4b2693fb5371b4fd640a21fb61c87facd9b2a2456ff031d6a9fcb99f5676a131e8bf423961449aa29cc0f77c74434a9aab1f4a6a6f9a8db765bccb906873d010001	\\x30b030424bae153bb239f57d69d1305e04689a5b8c85aaa4b61bd0ee188216a0213b16655c2c8b1760aa96d1c76401a46c6e01fedc724bcca6d4291a5c69600d	1663204288000000	1663809088000000	1726881088000000	1821489088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
32	\\x56b0b51e6e462d10cd94bdedb662670c26cce31de1cca388fcc4c1698deb55f4245c40956c5058fc88fbb795ff2fbbb0047875bc3d2f4cae872c6c70b33c85a4	1	0	\\x000000010000000000800003bb36ad95e7a712731ee56b9948f7942abe47e255f5e4d2cb95e6c11fa00efef1510f705be7af94375ed105439927007fddcd49d8cf47eaac8cdce731e05343fc34fd5f708f2206af83f653fdb4d9d6ad8c7369416377ebd8aa491f66535923eb59a56b86322b16b1de163855104ce455bca2fd1db5688d41b7c66c4de377d7b1010001	\\xab27fd700cdcb047fcfb5d0d2c021cd660004e6a0a2a22d296414dda3efd14dc12811ab93d44017a28bf89b71c71347e5faa8f6904e55b1a209ee3badbaa0309	1660786288000000	1661391088000000	1724463088000000	1819071088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
33	\\x57e4934f3b0ad7efa47fc1b9ef7ea46811c83af4503adf63083924c49cc5ac2526a066c87e4decee74ab686185c693be4cc3d7f607a9da2c6b7286a57f0e44aa	1	0	\\x000000010000000000800003c96d67ff15b35025ee2a336b6072fbb222309c15cf8c97d61bb54442ae57ec644b40b01a242cc161eae7814fd511cf871ad220225e173ec5be54cb7d3cbfda79e753d0f6b2141d7399576b3b1b7b4a3b525ac202a9d7b138c802747be64e6b15aa6da9e2dc36daf1f06bc60d7552766e24d33c0786226b91ede7763a5bd5a0a9010001	\\x7eb49474ec11e2e8379362e801359445199bbf2afc08ddebfb2948a77cc0d571a3cef9ee800f6032431dab27c55103854d7e44286853caafd77c5460e2c0610b	1675294288000000	1675899088000000	1738971088000000	1833579088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x5ab8185b3b4779adeb904464a4448a5c23996b456d9dc7b2b979bacbc872ba0933d6b11af8c905077199bb14e91cedc00e5cc333ac377e9f2acd944ea2448fc0	1	0	\\x000000010000000000800003bf0fe6fd14495cd3a83ccc74a1911fc76f00ece6db36865d9375bf6a9731b3219cdc90844dda3f49220e8bbc51324fa80a304304d2561f2ae1ba77eb8ed0d062aa6fc19b4be05226c20ed6d9d8de8651b029a6727e00676b0a06c3f9d50f36b52a833af43c36443551d82a4fe00137ffb9bd8b9ffbbf7dd731d2735048d6b0ff010001	\\xeffb31e6398284413e95a89e09fdbe21915985161f5f34ec7876d637cf9a69073afc6f587b9defa0d9c3cc76ab3f33cbb7a2096220a54697778b69a3cb52ff09	1654136788000000	1654741588000000	1717813588000000	1812421588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x5ab42b3f28d0e55dd38380bfe538a16c7fe0a9d58218fcb27c9d9f4bc748cc5f1f5cf1a9a43c3742a4a8455e53d0dca4d75a89f6f5af75d1eed4b7e8aea7f3dc	1	0	\\x000000010000000000800003e6331e4b05df089d6d41ac4ae40a30e426f5cf258c186edbff28b6412a09fc92eaea3f37ac09493acc3321771ce10b71522ba064a7967946aced34b2e6c44944981640fe9549ec36f572135a662f6af4061b0f9bfd51904ccf14642420a84fb1993676866eafad1bb00ffc7ae7afc06c65763ebc3bf964b0804b22c8116e2d19010001	\\x511317d5a28f7a21a70719a14d48f3a4984553d880e7fc226531a4e3afab68bdcb5ca4902de8cfaa8f3b433914604d0ad50bc74beb3766f640a53953e85c7d02	1651718788000000	1652323588000000	1715395588000000	1810003588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
36	\\x5b7859f4b50ac6b27b8ddfb2c1246b233942bd635ec58cb306402a8cfeba270c48db1577b401b744774b77ce4d268fc4763ca45e7cc15107607f0c4991a7dafd	1	0	\\x000000010000000000800003aae412f1926f3debcde045266943892a373613e14b748c14fc76fc00bd52c9d91a08cd79cd97e4e9cbd1c04dae522e6d82ca13bfb5b330ebaffc8ed64eca6cb377c3aef48db7cb1319fcf5968b92ff9ef9844b8d190b69cdac852ca07f447bd5b068db2006f6c92b575c0ea6c3a6d6b5bd5599c5286383e3ff299eb3108a907b010001	\\x1a651a4d7125e8317bfd5d4a685c80dad70d83b79358057dab26763d5a4adcecc4aab82217549e95de4ffe3aa39b6c74e8c1cb4c8d43c3375424f18d9d265a01	1661995288000000	1662600088000000	1725672088000000	1820280088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x5bcc1b2bf2b6f887ddb864bb14c4ecbfaedc55515a1fa0d3475d3446c309b58152c4168a558c82298f4bec834a05ba4e884eeb940e69170dd11b98d0e878eefe	1	0	\\x000000010000000000800003eacbf1fcfa8f6d4dee00bbda7f6a9568316bd3629d96aab1e09395546496d59bddde9ffcbf56b495b51f0a3aae970e0779b5d5b1bba03bd872fea832ccc34b1c24b19897d1e12fe1a0de2d8534e466fb9d5af685c99504e6d1394da4748427a936b2c7b7cb6d0032b4321e89d938d005b361f65398db43c6886460f08b8b4ad9010001	\\x7fe2fec4864655e0301b60e66238effb8939c269958609c253cd7c21d447efa5d2fb30302d7ffe622d57f9555623df20ed82809742d6eaad029b57bb58ab7f05	1668644788000000	1669249588000000	1732321588000000	1826929588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
38	\\x65b44ec258e60622020c3afbaf30264b70362ac10ab6231216bf0f16f4858d12d75d73fa923ec97a7228d5364f45dd4582e3da87c57c5eed27579d819262dd38	1	0	\\x000000010000000000800003d2620c77c09d2c3d5ccba681c3d47701266cd2b048dd8fd8741e77b26738c90744bea1c436119c0e99a1931beccae86e4f8a18e7f59b3bff1db8193f47b94d483ab02fc0f802a712cc21a096f940c98b59a1722e4707e9ab43bd581f394d86bb88e10a40b2f57746cc06531cd8498c409067f72fd614c01296801ba038855ba1010001	\\xcacc1c61842fc9a4631330de1bad73a3e18ceafc4ff8a02bac0e62dd72368cd2a07044c71642c362c9848a57e27c919f09971da055f355e5b2dd6db378c37e0e	1673480788000000	1674085588000000	1737157588000000	1831765588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
39	\\x68b4f0321763f67e37da85abb67363af48911fc6179b8ee0f12de9bfab427d22e41892df2d298e52807ab469548a00cf81eb88591bb63c12805098537e08eae8	1	0	\\x000000010000000000800003bc9404a189748152cf3ea61e4c7a6c5cf53453bef5383da29fcdc86a2e0c7cce8c9ab1736a2c7c4d005bae83a98c0a16e94ca3582a0c5ee2cd20b7ef310238d61f800476952d95f0e3f2c1e6c11274985672e1381355b29b96e2b968c22281e45d41d610c22b081ef51a870fdb1bf97933bc41da30af8312e493e6e8a3fa4767010001	\\xb05fb6ff40e963065cd2cc59fd16f80779a5faa17460c97f712aca2d9a631f9256428f5d120fae2d0e84788df98fe0ef2dc6eb1b9d2e90dc86ba9a2a1ee3330e	1653532288000000	1654137088000000	1717209088000000	1811817088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x6c5094d9a85e0d3b4442b91d69cf384ebc7a2662425ed784ce2a7b8f89ac17db48a442823738ec15f40a32d119c10c5f89a73843e07dd273036f6c00c200b878	1	0	\\x000000010000000000800003e2e5bb3034414f11a64121b6591dde0ebed3e1e05a57a459a55cf52c24798577eb822aba2be686bf727dda204c60c2471a18cd07dd47b7ed06f7e0322c10c01e99dc020847e818dadca0c7bad5ed410281e04fc87898b8ae09faf9ed2bef9652070358de50d23c22ceb3089387cd8de15554f6b57d305c726f5c7ec243df4f23010001	\\x1d4fc0f003a9b8c4958d5056f2464908a1b661d24a331fda2580479fc1e26d899c2c1ae5988f78613d32b0e99c0581508f2507c0ef58203b0003c3595c1ed403	1677107788000000	1677712588000000	1740784588000000	1835392588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
41	\\x70401124c9eb59968f7c6f17c7fc97d64bd782375e71efefe5186a2697f3656fd0af94f4d6b55044a88f6dc6c3953c160b285682017c1204af714ffdb453afce	1	0	\\x000000010000000000800003c1e722547f921c347ca5ed7bb2e9ce5abbb858c90d72363b311f11d222110c425a8ff2ef3e0710a488c122faa4310d4c83a75c46ce963ea02228c187df19fb89020fb706c16d9191ebbd1a4a006be5f7b8ad417e00af7a28fa53a3df304b3826c8da658c4b39bce430a0259097094b4b8059490de48f4c71fe0f503478295d73010001	\\x40c6289c98c83a709ffe43295b21301bd0054bb803dd8295aa2fa13bd8f9a5ee0f11090653fa99e9821c63a23e43cd7b6522fec22e9f553648074a448b9b6703	1656554788000000	1657159588000000	1720231588000000	1814839588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
42	\\x7060ba25d82f78aa7d6ad09cfdc07c75ad7e290803cabfb52f3be3deccb255f623de5f6ee96fd5993ce9a80ebce76cf9be4bb240b91191fba707b32fbb8e9b80	1	0	\\x000000010000000000800003ae2ca27a241a7d0efa4954b12e48bc5c23a7341f4a2d9ae0706cfde0228dcecfe99a43dffa2b56fc047b2a46b18ed6f4679c22d10668189d385cfceb49682e5ccc167d8fa6212b46a09a041bd8f95c54069b2e34646e782a9bc3177196f9d9eb0f261455e6aa284e6d76d4fc138e20f74506f13c36bcd6a05a6c36854451748b010001	\\x36512c4d3543137cf29944c91e1df82a7dc3d63a31b9a3e6e3bc1e2a7f59a3e2a410cf81d6ac4f3ff5f0448240ed312ce5c06b30bd9e1984e9b8c9e93ac3c00f	1652323288000000	1652928088000000	1716000088000000	1810608088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x72c01035333ede33e54b448e6e5f4bc18eedb0823bb554e73b7a3e783310d4b65f560fa672cb2097519ed969371e6797915e2d3f7b3e9c31b9cd71c43dd6ddeb	1	0	\\x000000010000000000800003cf5ecef8b81acd39ef02cd51c4251e904cabc7ed3508b76588c3b819bce4a0cd354fde7487d751ddd40ca25cbcfa04b79e9464ca8118a56e02282617955af3a028a659967d8c18bafd7e772293f2119aa6bd9d0dfdf0d30db7d9274ae11ba2a4a94a20468ea57403f1bb2b054db49a0e11cf402f5fadbf8716154eb553ce61fd010001	\\x7bf4862c061799b4160eb01c3715980325e8b16fb272a22ec9f92448fd3ba42dea508c676b458eb6b21c435a267af8bbe288dbea2c39b15c65fa97b1013c6608	1666226788000000	1666831588000000	1729903588000000	1824511588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x72c4cc4a313253f4885b4c081b2d7227e23cc5ad8e388cdd1d788d917a1690ef8b4b8129b4b86a6126b247463b6e406fc26ee70e6a913f03b3d22427c1abe3d2	1	0	\\x000000010000000000800003bff3eb5fc27994e9a44e251abb15ac08ad48decf8e37834d28076fc55cc65a59a736d99d91cfa2379f19a6488ad1f50fdc6e58ea3c39b99b0571b905fc6be7a208870692cff64e251fd3acfa091ec420ed5261815a490dc877999cc591fa2846fdd1d5c47b8b8a7f4441373349652849ac1a8f6cedf6afcd478f0eaa72331f21010001	\\xbe0360888541e7dbc2236d48e75873196ebd563b05258cf635b8b98ab41ddb6e598a267bdb837862e9fb95cb60e9dbc55d0933bd0f2b13e634ccd658b20b1e0c	1666831288000000	1667436088000000	1730508088000000	1825116088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x729c3804cab629111618b769525cf518c175d30bc5f587dd46fbe3a0874fd68ba3d45f92e30083a9ccf6ad3d86b3ffa79566ab5fb4fd310338dc5a57bf4c35de	1	0	\\x000000010000000000800003b8e5ec9ce7cd87e0b9861cac4f850f69f261de7ef6a8b7286e6bb4648185174248b26ef920d4a8e2d3c00d900df05cbf12b979eafe3c5e5c10cce35bd868992f585a91db391522062d9662f0eb93ad74c730fdb0d2cfd3ba8b96b0a50ca9e89e332d57825a72c6ffd9b32389c9abd259d76578142b98a72cebd8c26e1a547229010001	\\xe2c237e6fb6b45e24467e107d91a38e3a7d62141e7bd945ec7f0b163231b52615a5ca58f88f8c23b4754d02ca49098a11b2bd85e42b07327da85a84bc9cc890e	1666831288000000	1667436088000000	1730508088000000	1825116088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x7854ee550abc93a9f942d8635aee1e06e40b69a6527113c5ab1a1483a7644d3436651d6d256e0ad072fbea59ee7bcc4e8c833c4bbd02879da015d0651b7392d9	1	0	\\x000000010000000000800003c39aca38864b511b6d8122ecba22754e815c569ac6f8e5cfe8d1e06984e4156bbf38466488d9bc0508a539fc19ca805a64d91d73f662e38eb33ecc045ed3d38ee0df9e3a4f60f09b45daff545c2b23fddbca66d5199a35d8cab61cf5316898df58fd6123c9e6472fc932e325568612340785153777f7a2f196672291035363a3010001	\\xd20b414ff2ac186283193b9a24110844557f904136e16a6287574324ee48d92a50111774dc2561fc79e9777943f987152d048c755802665c0cd6b0497fc7fc0d	1659577288000000	1660182088000000	1723254088000000	1817862088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
47	\\x79e07c80eac2953aff2e2f73b148d727b720903d4f6eb0ff97180365d1c2ed5d78583fb3f618a0a5d596d91924917758d00151a72987f5eee0e094097a97b0d9	1	0	\\x000000010000000000800003ca38cd212f9cabda5d3201a318ea48ab6d1a1bcbd7ae229f5d42bc9a50eb1ddad5241f6b8fb96d4f871829931d341cf3beb632d27d76b4ab83ac6d220521ef6054f5aff7034eeb5e5886ed3b39bab817041c86f87b4709a85fe74c29ae8206abd78b06ddb122b3b85ac36fe0774c88dabac4a6d02be177268114300aa296d189010001	\\x4e85901984e2601be83d801008ee5de3320d903f9a41feff22a3a822803ea8f6b64c11cdf296bb218b66f1c88aaf643c401add38105264d1deb0cd688efd5302	1650509788000000	1651114588000000	1714186588000000	1808794588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x803868f8bcf72d80e6c228fd022d2adb6771dde4af265af3b331641bbe9ed24743aa63f458f8d37a8101885be8fc7bf9076be2ceccc0b7ddde19c0c6e3c00b9b	1	0	\\x000000010000000000800003aa84548f3dec2f5b29b8d55e54b956c169f95ddc63b4c783b5af1437385edbf3734b44e0ebcc3e02d6e36c8f615fa76ffe3047e256cc46a63ae753dfecbd357c6f26019b6e0fe9b3b67d1c4adc82ea847f3045e8c4470168e63572278941d950bda9972f03d71c6cdff68e036f2f5c9556dbb8fa7e7e2579e48d47db074099cf010001	\\x2210eb8b9b72364cfc72427bff2ebcb6ec223b3c34b0aac7752438d4096556fb638837cda0cffa15758cd8c1551fdf6afb819d3fcc5dfa1be35afb3abe883500	1657763788000000	1658368588000000	1721440588000000	1816048588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
49	\\x81fca972cfac8b3f9f698b59b0dae0b0b2b8139f2a6290ebfe50fc45cd0f78938afbe7de42cccb910adc605e7bebb8d4bb881fe4beeb11d3a87f5670790296bf	1	0	\\x0000000100000000008000039d7f53a539e38cbe227dffd04cf0661d84ce1662f45c1ebe2ec86cf99e8590c3e3fe2ea98663302b9b6495443e79b23e1450b9789c5cccb6125e774451c7f086f22f1836faf04eebe6d8d56796e94688fb4808ffecdcd5bd72506423fd7227628e78a483da350ad41a2b8eaf5b2c4c7ab7c537fcf1e161c4517312a5d04fd877010001	\\x7e0b8852ab8401b696e356c04e3094b19ea8e010d407764e4141e84e59c3fe940771e32654e39c0aa1ee9711a28acdc2b781cf59a843d91fb96b8e833961560b	1653532288000000	1654137088000000	1717209088000000	1811817088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
50	\\x87f0664a2275aee166fb2e652367fae67bb86abdfca89eaa69432bc4a37e8647d9daada6dee68e91a64217db2764f2b0f341f7182a0306969a9631681f61ce83	1	0	\\x000000010000000000800003bf310f61532fa659b1ede90e4e91d5ae70e60bda110c420aa5c2f39408b7c5b60d8c273f2c7a2f2e315253c630127378dda8172e43c5be3a39b1adcca38a5e29a6889a4bb6ef3b114e0a5735654a39623fc2c3bbca157ea2d19b8bf230cebd1900f06713b352b454b97b13ffc089fb8655e655d7faba7f51af040c98abde5909010001	\\xfb846cad677f23e4fb7db2629d4eb794d0b593fe3d2768b32079c3a9ac73e4555140215dbb3a24d1a315c62787fcc3afba8fff55accc375b6e3fd2268d012d09	1651718788000000	1652323588000000	1715395588000000	1810003588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x8aeceb1b43b374c8013d186915b153ece3126e7d4a50266780eb0b4f30090b4c3a6d399b3df6e265339e45b32b67689bb79835a41dc15a2ea7dc9a92744e74d2	1	0	\\x000000010000000000800003b4b7015832e533fbf3d08dabb498e71550c127727a0f5b11898bc5dcf19de34758776b231ff8c57a16b883193c660f4b3134db9bf85154f42f201cdf2921e11b75aaccea222cc11060df59639998b2397d95b78f2ff2795f4ba496f341caa27d37fa7cb063239927bdf701ccdd83d3931646028557fa0b0a53e79083cfb77bfd010001	\\x8001f2b6389a3e808955809a3e8788f400d3dedcf2044b0b5d0703b0c33f278a38e6be4f528e68e0b407dd2df4e94e8898aa610df699420e001bcc6e5112c004	1678921288000000	1679526088000000	1742598088000000	1837206088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
52	\\x8c0065409ed513ea9a45faa3694077800b40f47f68008fec7e538ed7486f20f24ebf49544589a25631bdb79525ebc541d3d7dda9086cd390c34aa081e1518159	1	0	\\x000000010000000000800003aa6fee02f10214c539ac619aeffcf803dc75917161ef271760954cfc7e80e65646a441b3a13174a7ba4c34780cf248a1ad1be4b5fc1a1c4794c73a1371bbf608891284b41069c4d56fd354f6b2da88d7e86a64becfb3c0fc2ac454eaca7c9d31b7afda37a3bc8db604c7ab14412eadf0ff8b54d67e693dd6e049d17b870ca621010001	\\x537425c4812deda77c11042653c597c934d2b2a77f173cea6d7a3152f53a27db0584dd3ee4afeb5596ddfeb2471a308068b899748c57f3324ded9cce24650801	1659577288000000	1660182088000000	1723254088000000	1817862088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x8f8445c464da0b75e3691e533b306ffc479ca28918ebabbb9ab69866973d6b0a965e7fb014b1be478b0a900df7d85bd1b9f3fac78503bd31dbea5cd8d259eeff	1	0	\\x000000010000000000800003a8fed0fae5cea29322ccf3ac0360c5c60bd58e578724107b5e4e53706ad4ce805a94cf0872800a8dff5d18d548760b9b9c87633439b93416e495c2a34feff3e00cbb869d3f95098233c07501c17ee4bc37fd5d459dfdf650b6e2c81052862f4470b02802c3b4b70d167f28a03ea49efd128c0c4203464ec98de0ff33f355a32f010001	\\xf75919a624d29bffe71e12362ff6fdfef3a5cd05114ed0c60f00b6bab0f022528c640e4a4bcdfd81025e72eb2ef1a8cf032e826c89bc24233a8fd8d36243560e	1656554788000000	1657159588000000	1720231588000000	1814839588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
54	\\x98f8ebdb439f064d1d8d2e62b4319732cb043a70bdc34087f0135bb293d206f114b195ea928bc7d641d544a3b450ffd05f9247c2d8ed6d28eb3a31fa48579198	1	0	\\x0000000100000000008000039fa7279875ca376204d71eddad671401d73285dc8896c9c55169f0d017a355660596c533028478e7dd664812deaee382cc7ff1fcece0863f606bf6124221535a5c0eb479b0ba549e9d837618f59de5e844ea147cc77d7685792c98ab03134466bd0a5ea412dbc64e712024cfc879a6bb799c45ad4d8c35cc51da6eb78d6a8591010001	\\x9bbd5e4313683f9098e54e419110add9357cb2654c527f3e350eac568e2c50e903131f94a85e62ea204fbe072103f029b52ea26f40c85b13cde01f4b8e12520f	1653532288000000	1654137088000000	1717209088000000	1811817088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
55	\\x986813bbf2421fa82cbf94a8a1a3a890a421faa637f10b03205a5d146fa80541f5e284a1c9c6e6a9f2714bb3494498bbb973e0357eba63ea73a93307cd839c80	1	0	\\x000000010000000000800003c507c0396ae4f26240406d90bb53675bc9e40b9ce817311bbf7d13a8d96955c2ee80334976b5240f02fb1980336a8f7904c4a55f02bb8cee9265de3277e7c189a139e69bee747d9c76d0fd806f79528d1fc6d8c15263fb7bde995a86e3166615f841f79e705fc4d7606a0b4a8ec8d16629138df6d2ea568342b2d7cf3648fa35010001	\\x013e06a949c6d1cb2f98b2a4d5ea990b803d8e91a97b741d457bf7ce6af9189264dee7a6192aa620617025966db1e6edf54cc42a527e0ea0364d05bcbcc62e00	1655345788000000	1655950588000000	1719022588000000	1813630588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x992c670eb24a39d434fee9ff0a252f49657fe3ac13ca032d6c7f7bfe1580787c84d9d1b1d55aab6028e414075cf36d08fd478bbae9186f4d85f9efeab1389050	1	0	\\x000000010000000000800003e6c2fb81a616aa366021b1a64e088282bfb2b9018bdcd8359acdc7d8ffdf08e81485002ba8db9f42e7ae91351d5c47eea3019679f3e5daa5bec5b9081d1ecd5e8a97897271a3b33fa952fe89384342342c73519c65ebe291d321d91d7315e1bdf99e67595e0ddeeca99f0c503d6d9d434fbb94638593d3b1230d0e21ddaf4129010001	\\x379ef7cb017996e957344437f846e8d332c3c3850e996d45a120b9b164ce077154631340e90fd8b71a8ef62ed746bc59d58f9ee0049b99184f164b5d0238850b	1672271788000000	1672876588000000	1735948588000000	1830556588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
57	\\x992c13d8220e3642d747047271bb900149411de9ae009cbeab1f2e77a3a446a919db0c0a31b9fc4dad97fea07008a70dbf40b54bf8f3f74fa4faa34058bbed49	1	0	\\x000000010000000000800003b3bdf24e9d402143767d255c5ff515b93ae8b61a1cba4240f85a1eaea2fbdfa0a179eb83bc10b37c659be255132a8bc6a2bf85061bcae8aeb3c1457f5c72eb6c758ac3e8f58e37b3fb86c456b5b8951fd2b955290719101a10b9be599b680815ccdcb7ae1e18c6f102d04891933c4d905739516972863e24e462d693f3bc0211010001	\\x4adebf33c274a7a04dd56fb4bef45548821e5e44da7bcf5baf63c150919f73063d62532ea915359d4ff874cb67311302b397c21a4fa958b7b91d4cd776c83b0e	1657159288000000	1657764088000000	1720836088000000	1815444088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
58	\\xa19c8456f77797604b0a57ca525a7e32d356007003da5e198acc82791d5b84af53488292afda715cb71789548405c6d16e9d914f0e79349158b5168076c68b71	1	0	\\x000000010000000000800003b7d80912218e63663622f3d3650fec70a384e323545b7cdc46554993c2bacf6fdfef1bc1c07e2a41ad4a110c326c2d54f89ec994424f770c235c5beaf50caab73404120dbc76afdc8de3d1d9461c3451c947fb4e666a6ebe7b291c1b6a4b75dc6bec3e273f66eefc8d6081285608f18682f68f18bc1c7573d5da0a90feaea601010001	\\xdd304a12c8223bbc588624dd9ef1a17f94a4b7fbfa0fd0574e6ac3b845a69466998fa59e25fc7d8474a4433fa027185d3f297765f34e495cbd0e11930df1d507	1674085288000000	1674690088000000	1737762088000000	1832370088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\xa29cfc4f4b99b827076730c7383c526730d40ea935465c2f0c1ca338828a7f20d9a94ece0a8989c956861595e3871f8f09258740c67eadcc328dcf260a009273	1	0	\\x000000010000000000800003bf2e933103ee72890e3759763b80335b6131f0ede4fc85156b91246512f22620bc44a89a8be084c69c5f77536165cab0208e2076d4623b14bb1ca0a0fca1e7ae51c7d2b0e37fd831a8d3f9ae62c305df46586dd119a56670ed5e718ada6f3b63a44ebf4faf67fd5e170270ec12feb992fa5c871532a48f56d4167c1edf255215010001	\\x688141e326e388acc3a83c70fbf9cde44fd14f4d986e92933e3b66330d7939bcf7d331346ae8803a181113126f7b67560ace85199484f3e7398eefa223aa3203	1678921288000000	1679526088000000	1742598088000000	1837206088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\xa37872f62548d20f5c01564725720d9a8abb423570218b40b25cec6cfcb7938efd65419b38afe5f11a62069b47dfef1bda17bff640e34e987e89d5a80a497094	1	0	\\x000000010000000000800003954289dadee40a6e7b877f7374b438c1c593d00a0ac8a0ec41e1d303d5645109b228044e239410bb1a0af00b15fd61dff8a0ed16a0f2242a5c9a75b8232ba021ee008fd176060e8d297ab37880e0a6a7a22f47df501f92e98cfd138e688b9b9f9be10382435cdaed752ab5e93ddecc3c277cc5940295eff6d6fc9ff48924c0d3010001	\\xcb8462cca98c422b0dd53bfdc1cf1d32aee6d1f9a8d435be208981e61da659f231cd4dbaaae6fc01deef6285fd4305ed32d5d351c97f9fc6c9a8804da7ac1c03	1665622288000000	1666227088000000	1729299088000000	1823907088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
61	\\xa6f86438dc52e346fd1fa776d91fc32f0c3f18fce0dedda13ef1d1f7563b3dfcb3696edb40fbd25338ce2d8721fa80e79019213dcec74a62bbd7d1287cd49747	1	0	\\x000000010000000000800003c95bf4b492b1291185086079e4a58760403d5cc6ba3a19d980abbea8c7fc3c28871cb6e14dd89d2b8d08f73a8f715e92afa33709c87b506a8e29b551656ec2104c5eaca6579dc2d236997837aa579d9a666c6a214e36b3fd6610a3db5140efb71d73b6005933a19473cc49e5403c538875067f96748ed1a8cbe473142a711443010001	\\x47d93e9737b6c4b934caf6c928e28a86376abf7b9e7c26dd5a5e5fc9639553b7b44319c5adab6d8dced344d418513639a51afaf41774f5b4aed678486921a60b	1667435788000000	1668040588000000	1731112588000000	1825720588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
62	\\xaacc5df063d5d0ed87279169c83abb459f9bd3c015a816e29f7b11f4db55170f66dd672003bca3d40fc3632d030ff2cce22db1a73050e756e6585a9f6eeeda24	1	0	\\x00000001000000000080000394b110a3c8510ea8c25372b5f3dd22122b011700b1068fa88ad81faacd4b9b518a9794cd0128668ed2d625df314ee3de7ec04b60a771269b4e9b7aca12e772aed846f0dcfc852e3b6f63bc391c126e37b8071ff8aebbe2e5b61dd548511ea412de56c210de4724d159e65f4a26c5c3c2db35c9f08b5882968d7da35393e5e6d3010001	\\xd2ce8ba6c0cf24dfaeec16222c5b8f8a3bc24161dfe3855dabdc31204808a8adb72cee70c52e2139bdfd82f4350776ff02485b7090f1bbd67fdbfe2265e3ee0a	1656554788000000	1657159588000000	1720231588000000	1814839588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
63	\\xac40e0399bf5c49770198744f73632e07e06eeaa396832e0fe8b1df45a7acc746c4e0759e90c799a1a6b63817b54f13480e607fa748468c29b1ec8336658471d	1	0	\\x000000010000000000800003d27c4aac7eecc7654f6274ab6845ec48c2e7b0ec8b6f9e1ab28f88ead4e4515d414dad315b719b4cbdc16a73d573e4cb51ace87666be5835bd58d60a73fe1926b8133ed2f51a0bdddaaa8f0e7071b1b57bea65c1b98548889a1594b23fc528102ec8a9aeecb8e339c4157b63df4939bd65fee5ad391b29d5bb5a4b6dd21ac8f5010001	\\x181797e90dac1ba8c6390bfc30d064c0aa67b7ce24093a5caa9e7934a630f7a38aba573888b745547645e55a6f0eec3351bbbda2d165643345b38bc5eb540c0a	1666831288000000	1667436088000000	1730508088000000	1825116088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\xad28263f63159a69a68765bdebab75b04b9a8be23376c48f1e428987b12e6e7f5bb9e0b84eacbfee25932d1db05727781c0158c525779272064816b1afd9769a	1	0	\\x000000010000000000800003e2839bebb1005a6587f8fb421994d194fb2ce77cb480f33f270d9e3b4d871ff175bd2943f6929f5995ad1ef2ab80a6c694ec3b2206409911a490721b6c78fd9175c1b250b430226eea0ff85c6f59029d4c2ea849e69b1aff3311e2f4b82da3da839357ad05edaf11d0105f83b69cefa016a442a452e9054e090b8661fd59bb77010001	\\xeb070345b19624c821362b8ef587a6f3b35d2ac3436ff4dd0a9c95ac936f86aa629936dee6a3528d892dcbb49de5c9f437dacaccb11fd764e317654b14e9b304	1652323288000000	1652928088000000	1716000088000000	1810608088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\xb1d8f0f4ed63a2a73e406d5dd9a0a8a4166e8d51aef3020eca150c6d14ee3e844d4f7a50bcf3dc3592724fe7f018ce6485bf2a1ff7bd739b425b0cacfccca9ee	1	0	\\x000000010000000000800003ae6f47fb281814b0ca3efe9ff0c7122273f0bcbc294c3c4c724ef66d8c671883fb2fdf054c6c4f1af55226d8e82263c9b1f881ac39b5ef52f02ce0725d1b2922036a0bee40c9d2668783dbae795fe00c15e1c573d44ceb22b914eb1c3c4152763d1ca37472e7a7d83d21f74784f94c511a1211ab96fa8240305db0f357b4f87d010001	\\x402fe3141b390639258b87295bada58850fa1adbcf14198c2b4f63b543f2a42ecf7fe49f4df3a4093157055021a85d0955417a704d58236f4baddbfbaac49607	1669853788000000	1670458588000000	1733530588000000	1828138588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
66	\\xb44800daed2b794ef5f9a7fb9e9f69465a5e258669bc16f9f8e678add3909ea6cf5a9d40a72b5b1813cb10302e5cb7a1808de873c4e9cdfe916479d91c807b80	1	0	\\x000000010000000000800003ca8ca3f306bc377b2f04ead88183b4f7db4044de289f567cdd35cc9f0e046dae4fc0deb4ffb5cc43fcc874340dff784231678a1c7607e126eb7ea89366ced38fde625e1bd0308a1b896e86b5501d8c2fcd67d29a274a8f948aa5b2fea9d70a8df9853ac18ac20e654be72129fd1e5f2127fee0ca5653c24094b7c9ce3e891895010001	\\x031b40122c8c5221b4b74a3cb4a7da5f16a46717aa5149e045f0c9779c582db34898176cb69757a55ff557d37d1a26c13c244858f5fccd0bd90a6fa304a9f303	1670458288000000	1671063088000000	1734135088000000	1828743088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
67	\\xb64c94de27fc15a7eaaf7114b86cb6eded9b81741ca591e4d68d48ecf196a10abafa122d8a70bee73e890c418b093278aba1acb1943efb3a1839c53914fb247a	1	0	\\x000000010000000000800003bacaa6b7ef7faaab66fd5130d970c0631094281e1adc71b96578e45745e62f74aabf08d3f55f7841f970907a822cbcde92f56d2dd4b460bd3a47de6446ca2df27a0a38cd67fc0c9fe939044cec9b54fbe97f30dc6f925e27705dc11cbbadb6fd5c046d435ae4410e33ba9cb947269b7002b30271fd3f8fd93595e5c8a29be4bb010001	\\x2b074a37e7502852bee74a13c52a540d1bd047e2d03cd54d98a4f23adb3a14da7c0b57531a9c53049ac8b3bfd39e422423253426c0d39473a71d7a893c669206	1674689788000000	1675294588000000	1738366588000000	1832974588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
68	\\xb9549174988be35f49445525c729b576920720e5283d183baf8fae864ca0be9884100705189b8ebc362d21605622196ebc8f30f021c8aedb80636ce22cfaffe8	1	0	\\x000000010000000000800003eee37bb6f947fba55ddbdcecba0d4554f94bf4ea95f259d23d2390b26e6aea5edf576b6001123c02093dd977178a723b37f491d903e6dd0e91f1ddc163435d40cd5ea41496cddcf137da8a6e5fab2a3e757475fb4eb90ae42d59eccf1f446d942c14356031472352b0d12f93ec0181668b040250ed009e50824dc4467112bb49010001	\\xc14a8034d15a5a32ebaaf6bbd6eea18aa3ade5666ff35d17282508c0b7fd39b17587b871f8c72b8261031e68ee5333a75e9e77e2db62711fe3773e1eb4a59b07	1655950288000000	1656555088000000	1719627088000000	1814235088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\xba5895302180d6b91067ecac09d81e6e192e3d132caf010a8db807d28b0bab7c69ccb49e01f57cb3fee9dac57a58533b1713afc368d6d553bd3abd0c7e470eb7	1	0	\\x000000010000000000800003aa7dce280420c76b73c9f27326e566dbecc5f4bcfbbea84de9254ec685837793820e2b99235d77ae7c114e1fe451a17bf1cdcbc528782a4e43ae3da47c6548a00a75463504c24061491e44b1d70099ab5c6150b1b7dff5b9a8b77948fbcc95f1331a489fd7e4a1c51d7db5996f37096f677ab0863b11e7d2857ae7b609a1c311010001	\\xa62a9dc8d2eb3fe73956ee246b24398332d31c9d6244333221a7654b36958ebc666930e5b1a540bf875d5dd7a2f947e1a49d9b5b48c589a4dcbf9b65d657c104	1652927788000000	1653532588000000	1716604588000000	1811212588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
70	\\xc0909c6b8ce021e99385330960e4f0b9760678f13f5d0c27c8d8f6d7f8afa524abf45e9e10ffdad8365863469be4a5090d3402f8eeb52cf822099dabbe158069	1	0	\\x00000001000000000080000399e47b3a008bea410e91149aed2d60a059a15978138c427c546b9779f90db283c6203e72f7155f0d0f68b0cf3ec47befd8935b8b1915bffaf50211e64f0a3b9b72a5b11d8725e89c711287f359080068acbbd11e8ff0125f679df632fcfa383401d255078753f2a5d9773746adec13a05b720dbacae391442ce2baf24863fb97010001	\\x77b4e50f389ed938375ab31d1b3eaa42abfbf1a7b036029b069929d016c4c7e38c913ac347f7d8f2e31603c1c25d1c4c9b5f77d834cac54d4150c1c057ab1a09	1670458288000000	1671063088000000	1734135088000000	1828743088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
71	\\xc1d8913cb273a1348fcc9180e8f955bd0767af9fd65d58f60ac185b6083f81a4414fdb634cffc7a0e12c8f5a7a7a77e90688adaaff22f10b5415ee24b54afc9a	1	0	\\x000000010000000000800003bf16231d2d040206f5e58d47a48a84bcecb85b296192bc6094a315daede20ae490ced44d5fa6717040758f77e7723281ef22df15bfc1a3ab344cc89dc6daeb4e9768b4273690cd489389da6935310add0d630190bf4d22dfbf6529c7d68c0927c7c62f92a89690e5b6a01c86256b4b6639e99ef5f7a53134e1a6f300734058cb010001	\\x3925882e438d86e7c62e0782483d99f0237dafaabd6a0dd90566d76f87afcd3b3312419b4cc54dcc2964b3466a68aae4c358d3e45aa1d09872b3e08dcb91a909	1656554788000000	1657159588000000	1720231588000000	1814839588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
72	\\xc2e4eadbf2ab3c8bc6c0d3b06ee852edcd7a38aa3101236d8e20d15821dc9b3650ab3247111399929dc38a1fab3a7e5e36f3c3f64c7f45708fc02cf2e7cef7ef	1	0	\\x000000010000000000800003aaa63e5ab096cba6714799a2038dc06c45f032e24792c17c0108da9c5cc08f53c5c970733c0d066b222a17f9a19238c6a7def6e1d1df3052d8349077cb9a38667680063ad8fce90c2406d00cdd6135748a7619086637fea27080951dbed74036946d176ea862cb88c31ecc6c44a933f8eb95b327fe4270481e26d4eaffaf589d010001	\\x139192306d5f33b665b48db6fe881571f690d19db3d0a1073eb11d799d09048b69adb3c90e99786b2e58de2d205f921a70774ba63f0b83fc03d17abcc1ea3709	1649300788000000	1649905588000000	1712977588000000	1807585588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\xc8683bd7637729e3c9953597da34cd332b3a8dd4752244df8e53cc598228f5d923d5994198a528d051aedbc468c778402acabf14d9deb0f87d65f7921204b1fe	1	0	\\x000000010000000000800003adf7b1b5002927398182a4cb8c63d1d66783b0f09885404d58d47fef0035f01ad21c7a56ff5a3a72375dd500a440d7ab0e6424b804d97236b593d6a8b59122ade9a1fe21b16aadc8768aa42c5d0d7798f79b15beb9ad0ce9f9c61e7c65e66a4d43d687f858cafb2f8918beb303cdb9edeb9f312e939fcf3aa108d92f6d6f3c8d010001	\\xa04a6a0f4877e1e0983c974fd0037297d8c4722ce0c0555eb6cb21bb02a28e8d1ee2b5d5b9377af6872def36b1bd11cb727fdb8a06c99607e6e951a8b9653107	1663204288000000	1663809088000000	1726881088000000	1821489088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xcc7037ed393175cea327b56ddf587038e1b4f1c956ab7d7e1fcbb8122f7123c745ba4bf3aa2a99746005b6ada2c086e49ad41ffebbd04c8c584d72cd2a39c4b6	1	0	\\x000000010000000000800003c47ba01614f5cb993e316c5a52a0f382cbc7637b9d86d902158dc74669c7a369b153517d8ef3d1304749a79013d35f7c44d16fb7fecb3b668e7602b86830121264ca5e47ecf74e02db6e60c8cfa9f0930e24702d69f3f768793c97f2edb2963e5776c03ecdb765d1955e0b6f5854b9cf7be35d47d978781c172ca07c28b34f9b010001	\\x929888f6f84f09bc1377520037e898d75bc2a698f46171d0117e2a0b5af0a882c8572250e9cd153acea6f83e6cf9a7395ef4e35452d625b66e95a4c1add45a0b	1678316788000000	1678921588000000	1741993588000000	1836601588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
75	\\xcd242a6244107c16a2a4f225d1826990928be75cd9ea7bcfe13054f658a6254e322f1ccd9342a21858e240b2800358e7d445659446664df66ef0997e82fd94b5	1	0	\\x000000010000000000800003d0a598c89356b587cdc20c378987a672d932e38d086ffab2f869a9d7d848b7ea2eb1a200772a9924fcdf05b0ca77d69076f50e879277ab1c9ac4a146cdf3d64b3870251380b3eeedcd39ed503e95c11b599561b5ae890301c568443923d21ef261547d5795d243d4778e35a9a08d259d2e4461804d01d20f6814d9329a39448d010001	\\x8c227965ac80c5e83fca8f87a2112c5bed0a5057b790b5fd604f41c387db8610064f22b0d2a102e82d130220fd922a2663cd4519a13f73da6216a195c6d1ef0c	1665017788000000	1665622588000000	1728694588000000	1823302588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xd5e8826a9b60c42467a5fa090d1751cd47668f5d54dc298794b372d8d0fc5e6473512498851f88566bf87f72edbd95ea80f3cea592d96b70b554919d0d3d098b	1	0	\\x000000010000000000800003e0a335ccbfe04fd8fd2be0e873a52cb3c8d0916f8175ef607a6b4fa455da9e785aea6a2310f5cb63ec364e0808d2f2ba217482538226adb0eef10852329e6b11777e70f95b27e478aca6c739e44e33ed8b008e918797116cd6b9f5aab6da85c89a9ff8b996720c6ba8f2e5b8e75b55e6701f2effb212c49a0461b046d2c579a1010001	\\x1e54cbc989aef78be875ee68917c16e2f43e25102b7a4db8d0d5a3eb7e54789413852be7e1b9e664d6de68d7f105eb7a916da6b03e6884a6cb87c6a5a7564e02	1669853788000000	1670458588000000	1733530588000000	1828138588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xd814c6277b144106b94ba19c0eaa9568e261a5348e5e51052cc5030af0f17022dd86f265b0a27ad97f83f023b4156217b84f08beda0d35026737950a7d52df6f	1	0	\\x000000010000000000800003f2637e286af3d18d982fd6b34bd2bb48867549ed7dc6c2452bd702543516ec47fc12bc4f4148e3f3a25622491d0cdea6bed63c9b0dd11c90e36380af0d97dceb765e16723cb8281741d2fe53fc989124f9c2b5e1ff4b63edb6ff948c90ecea34225ecf880240397223f151d5c73e1968a00c0d5d1e9d305ec2db15d40c094c3d010001	\\xd6225a58c7c51260b814501fe540fe77580b9138af238b6908f7a92e760e16a6dd3796ab25165b19a971ffb63a46e9a42d54bd81169f823766b8d54ab29e6708	1667435788000000	1668040588000000	1731112588000000	1825720588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\xd928af7b2a1a51c687205db2ed9d5b4cfbc39d4d4264838c1a72993d47efce6631a89bb7de1dd313335dce43b9aae5339dbc9ef336c1aee6e25b3aaf95070413	1	0	\\x0000000100000000008000039514e8b84fcd7a568b1392a041f9f95b6a95ccfb1f6b1a6abbd00b695dc2c03aefa84bd96f18ba5bb926a8672c68ef81c6ac43393cc2003273e404fb210f4cc32068f8fd304d5532ce6c631dd0b9dde4bb87bc17db4aec172357ff3695fd8c457a915e5591e78c59c709180a21d7e665ebe402c0c774abe3480cadfdd7dfe6cf010001	\\xb4def654fde5a95118ad83b37a6cbb2b9f313222323f4b35a6bf79aa12bb8e1bffc1aa395b0b409261683715d8cc13144ca06f68ffe8a003492648d07149ad05	1677107788000000	1677712588000000	1740784588000000	1835392588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
79	\\xda64f4c0487be273ed8794e1c031cf4385672f8c69263419f3c68570140439f3617df3f1941ea67157042490b480e5a683334420ef0dfd4102369ade5f4493b0	1	0	\\x000000010000000000800003e81cfa50fdf083bc5a1422421b5346aab7d4958d3fed50c16ba460512ff5799c5ff0c2cfe35f7e45ef9129751056c220c32669d430691051bf1e0597729119a6136bc6f549ce70bf4549461c3347281ba707b17769af436c1030227627af01af94ba7f7d1046c891564bea8ea3991dc84449cfbdde625acf8aeec3fab9fa8fd1010001	\\x0bad6c7cecafed62cbce5f9b96c6949a913583c14fb25b5b69bc8aca18651cd4186092c56e890976c7873b0d630e7f606c179c3877df33a1a6835c6ba1f8d70b	1651718788000000	1652323588000000	1715395588000000	1810003588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
80	\\xdc5cfed53a7ea669d95d1f31afc8ae4bfe922db29aaad7d2b0c71805a6ec3fd523aff1d13c520f61a2726b2b3aaa67f817b77b5ef3065da419266c782c4f2855	1	0	\\x000000010000000000800003e95cef58748d0d67736c54ba9e97901c41250e340e53e79c38d3132cd9cc4d7ad8480c0ab4ccfb6fe30b73bbb0be67be13d1fd60b50dcc3efa6ef01ee1be6896a5b3bd1970060242c67f176b1ba545d50a7a025d2a080ef6307d6f2b5425da67c937fd27c46230e44b35e9c2c34829ae1eeb0dfdbc286412ef6b5fd856d226b1010001	\\x0748140f43943de7c4b3ba3375b582aa6508483254695928f6ed5b1b6d8ab1602b022e8640a103cc0345b879955fe0cb73cc465e0a9f0cf41c1a58dd9f79630b	1671062788000000	1671667588000000	1734739588000000	1829347588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
81	\\xe080c8518de8ffd055fafef54ec9df04cffc0676d1b2b496aa9ccb1dbda2e812b6c2a1481160b7537dfe5023c024428469fd601a202103c894cff83d6ca5e401	1	0	\\x000000010000000000800003e54cc69b603734bd85da152fb330f4bf9fcb937f08afceb123ad96e1920ea4680dfb7633fe9da6f2f03eefaefa78a6294590a15e47aabb8b6ee03196de0a5cef4d615fa2f05338a4ea58c43a0d9ab5ebfe2c7c119c5080d7e1ddf96e80107fe397a8eee755652bafd5d33b262d8991be44702259d8ce869b447bc66652dca1c9010001	\\x31a5c961924f177cd5de96b261be8a8997a24890f7e74ccfb0e10a3ca575c73e3c183ff6f7e9ed9c008094f1d3ee3cb6046c7a7646a08bee22c5e93862597205	1656554788000000	1657159588000000	1720231588000000	1814839588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
82	\\xe3949c290a363e7025c678f38ad7d3c6549251f5a82b239c6e836acb50c40f12c1896db9c0176051b687fd7530af3f93e3b01b1a2393cc47061020b8142e53e9	1	0	\\x000000010000000000800003dc1acfc2ca54062bfd9b8860b3cd9321057a0599bad64e4bba648ca1956569ae33e54019798c17d76199ba697570e23f70ee903ea627b50678124db5eb690397ea4b187af839291d89f79e2ad53ba47e3f387c309b062d3f91b03b56e3affca2dc91d715eb1a41c435bcb99f47c662ace8bfca6a702ab971f44bf8e36fd5648f010001	\\xdf4f9d6d7159d099aa4ce2d28905fde8b20b1f2d97ea7685da8df11de6df9425e16c76a403145b4ffa719f3f4c3957439c84e1ebfb9a797383a57bae72bb3b0d	1677712288000000	1678317088000000	1741389088000000	1835997088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
83	\\xe588c055c68a69e69d7750b18489bd05683b08c33c7c6f9eab77d46af767cfc7874602934e4019144f3fb4d9aa9df2db3010b504abd8471e15e9cd3756352744	1	0	\\x000000010000000000800003c2421f9cb08e8eb1cc38761a66004852bd6f2afb11a347c3b1b82b6342bc6141bf18c18d34209806ea5f674facbc55e493631fecedbc2063aa02bbbfecbecb242fcaf320de55474be9913cfe25f8e92d3d6315d6c81829199d0756daa072f49c43741edaadf15e4931e1f752f689aa360ffb342ff9ce4aac087c1fc77d6a3ce1010001	\\x03630fc5b796d29f4b813da2eff42eed590f608fe176a79b70fdf60e100eb11b0b183e13f35151ed9d71ebb3f1f173f244a526836c9866f784b4f4396dc69901	1647487288000000	1648092088000000	1711164088000000	1805772088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xe8a47c26e0ea001d57f3fed7c536c892d7aa10b7d0d3a631d7e4b8caf175907f090ad93b8994a5500e898337925a791d5a322422a6a04bf0f27b6e737bf346fe	1	0	\\x000000010000000000800003b53ffa09756ac8aadc8c88461af618869f9932cca81d28f4c1c32814d7e55a6a8278c3f43660124d2240b527d4be06ab324823a46ed0e70e409776766eb8938938fd276b52ab96bcfa1932c6785056fec8816b8f8dabb6be7bd8853796dc40cd9643756f690f956a419d3d44840ddf9b2f24194d5d43aa0d1cb4faa688c2e055010001	\\xe5a0f297ed8503c62c71517c98af04a555b6a43bb1e20f112c1c96dbaa3c88628d7b3d1afb5dab5ec650219a53ae27153e8edbb359d37ed384894d2fb3079b06	1654741288000000	1655346088000000	1718418088000000	1813026088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
85	\\xe9a4a0c949c93a44fe03c28cb52f9e8899c626be3822de701ea1da953725d00333799c37dfce46b19dab11d2c01477c0a70e9cda5d3ef9bc06eaf0fda0ba6c8c	1	0	\\x000000010000000000800003aeead26d8c5de5cf5134717fdd0dde55a0911680f42d3ca3d51da547187650278def6052bee167aabb20093c4a9c772dc5916a3d757f612e6aee6c9b7b93f64790889182bcb688f8de12dde7023ce6220ea3c28bfa05c16d8ad1130c834575fab01e6d943f836ac85c0942526112f8008642c601ca2742f17130bfccfb6c9ba7010001	\\xdc5767290b1be3b2a28a764c65aa2c9408ce93bdc34c240b8410c3267654fe909b3ba0d359016f3cc9d2f5f4e0fa646df323c339eedaf15fd1dee2888592ab0e	1661995288000000	1662600088000000	1725672088000000	1820280088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
86	\\xea3830bd47063ca5cf879489af1a172777765132d7dcc00600da3cef2bafdd334f12dc0d1afe93de7f683cf05d5b54098247f042c3173b9a55c1959e499d0e2e	1	0	\\x000000010000000000800003cc866044062931125e1362692b4f26a79257fc5b2ef53ae35337af5637cad855645dcc2b0b04b25c8d0dadf3a6b7834914c0666a22c2d87953f2abf0edf88a40a07460f85a8c382e7dd1075e46dfc5f30f645aabc12a989a6126891dd41ad06901d952669521060002c143d1aa32579b683d331f49205481cef6d70b4416c6b3010001	\\x0a254dc0393f7b48f4ca1cbb4aa816e4d62dd6035f3865ca4bdbb8ba0797897b2dbd81696f9aa9c3d88c1494421d90eb82f98879bcf60f1203b2878608997509	1651718788000000	1652323588000000	1715395588000000	1810003588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
87	\\xf2004b62771fe5dd4ac02d19ee805dabf36c17c0c5dbebfef0cdd4e8f0b05878ce67ab802cee2f298bde33d0298901d9f7db17af17c990f945e31feea8749c6a	1	0	\\x000000010000000000800003a27759d6c936fb8b08d3950a44c26a15119639f226c71626f5f48d820934d53b2fbac385eebe42f1330c66f366f89cb2b7fde029a00a84a4a6f5c5bad288d1586da86e8cd56159ed248b113de7b8b1d0d426430e1e99e21203086f062085e3fa51d13e472f5bd0f6061adda9f5bfe80eca32c2f80dd60825c1567fd0918a0291010001	\\xe8f31e7cd7b5433469feef6750954d00c7e37d73f39c4d4fe97f5e7fc1008dfadd03c0094773a9040aa391b08ece24d0b123347e4c2225d3dd1537352808e60f	1678316788000000	1678921588000000	1741993588000000	1836601588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
88	\\xf58875a5473c764cfbfbb8184d21839856ef05b833bfe2634cfc0ace81f62b03bd2303bc9e31e40ed2762ab3c123ee5f5ac8154d5ef26497bcbd5c25495e4163	1	0	\\x000000010000000000800003bd4873ab5c528628c7273143b6ef384a8889491922073a4fd38a7ef4aa9e76f4defdafd9aacb41450abc36278605366faab610752454da55689ce7d52a402495a9e187a79ebfdc190682dcbffc13ad42bcfeb8c42ea8a041b3ede3ab9b4d2311177f814eced67969894c8b79ef8abd9956580d1382ce1a9a1204c31843cefe03010001	\\x4e95a5b1002897c5d2e921a19424debb919bf12a015d8428935215684d9fffd62ef79d352770afa0119019a72c763460375d7348c493f6f0f4c5dba073fe8c05	1660786288000000	1661391088000000	1724463088000000	1819071088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
89	\\xf7b0a7eb70a37b6e5718b87bbef1b7787633251ec7fbe9b5822e7913ef2bf85b1264a654be618f859467993e446135324c6429c4afd46877fa8a2fb1f0c58e0a	1	0	\\x000000010000000000800003dab51554e7f0892952a504bc3d61f1c2729627d99ea07e42a2f892e8623a3eb7cd58589a9565db21cfbb920ddbc24911ff0a04cf6efa8b3eb58ab618aae3990d629c5abae9e1931e1ba87cb30402bca8fa9215706078e05dc372e6c73c9f4cd3dcbd893a8c4e247d45a0fd1fae9567a8d1a4eac57975af9a4c93e0403a88a10d010001	\\x7536116e4163ebe8179cbd9ccaa1a7c356bc66bc54a44574041e4e1515ff7a5370000fe7f2a90aa296fe4aa67a20aaf3ac8d19428010a957498aa88462b8a30f	1675294288000000	1675899088000000	1738971088000000	1833579088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
90	\\xf8d0e9110be2cbd0688d9214864c84a4bcf01438a43ffd4577dddfb981a6e732a12aeac3e73b3cbc0aac3037e776cd1a73c5b9c5ad0d9bf59cae991be7e89e6e	1	0	\\x000000010000000000800003c7eb842edbf4a0d4ecddf3ff66893643c5745ad63d8fe0bb4b6e78201072b0518303cfd29d7c0a464332b3e1d2b30e087e70374b96c666a737c4a3e90acedf3d2a95cb0ec42b9b4f0f1b9ce3c68bb98cab6e219bbbbb59d04e5cecff2272cb0584bf371195cc5b06f9c5d080a54d021b369b86504c904cd1bf73666656f8bdd3010001	\\x0f0640c567120fcbb27de3c92dc59424f22a2363a3901ccf4dce49f83e18c74828b07218aa5bb2b4f90147953057d57962e720bd20f5db0dd42d940bc41fda01	1672271788000000	1672876588000000	1735948588000000	1830556588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xfa18fe9e838a2605fa06f573e8b3421bfa1363735ff9d3c938f25a96840ce962307fc7ef8143c43515ab7134fb8dc945f5268d6677d962b0ab8c1536b00f7a3f	1	0	\\x000000010000000000800003a8fe01a0c99141e107e9d416644c7f7607eb53c9a0669681805fff811e1952e906dbdb6a2887d188927e86d8a87b2b43cf2027d909a004626905e5696a43727c7edbbf8d70ea542c5d871fa658d5abe18fad70600ba03793b8af7aceaa7cdd1ea1a5f22800e90a9f1c68866bd84d6e1449ad98a640a5b23411102df191fdf52f010001	\\xc928ad0186addc6c8d12484f64196e12e3be9f613605a160161e0668ee3e0027a64fc671795119304179b0302381c4f56a6f0c1098214caed414748736940802	1667435788000000	1668040588000000	1731112588000000	1825720588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
92	\\xfd545f78742382a6dbf9e19c83f84aa8757391ff29e15dcdfc39c5c6337b4c08074c576ab4bb29d47dc0386a8fa456ceced76797592391ae5b0fa338a649acde	1	0	\\x000000010000000000800003b79ea306af2c839020657f119f7d641f45bd9f4549deb6e48969cf3ee14cbe2311fa4749e89396f1da16b16772e028ab6273a2334582508893e78239349c7cf4b3399144840333c3ce55d633b7d1f272fe644b07d210f61675d113f40a1dbe158094973d15873fa957aeb6e338f755ebea018dc529d0e6c96889519442b9853d010001	\\x0a78b36997b48ce531609f5021d736fce115123d4cd13d1f8f1fee196c90637a03ed418647d687b4125c07e90b711cd647d9fbeecb839e9503ecdc0ea29ec00a	1652323288000000	1652928088000000	1716000088000000	1810608088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
93	\\x028975dce3fc106d672afd6520a02479ccda43c40c389eccbf4c548fb1627d6d3e8758b94ff428bd145c98a87f78d42f3a23382a7a64d393dd624eb0fd4956de	1	0	\\x0000000100000000008000039b44a50c60dc1c65eeb902b0f67c7a11b5025bcbd6fc8ccf3f759f1a4997d6f7659c67b01b92b1510cf5e293ae8ab126fa4facb1121aca6d49f556a452d4eeb8c61e9ad7255c0b29a749477549f6ebf3f7ae47e1893121e29bbcafd84cbc7f46e288f0624307b27453365550a616db7756d700fe5c7f9df0ef693edb41e40cff010001	\\x0ebd15bc9014f64301952f1bc1dda3a6b7d4ea59a7c38c00d4e391317b064e3eab123d15134db3801f2de8225778047f975a362f16b501924c3266908443be06	1674085288000000	1674690088000000	1737762088000000	1832370088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
94	\\x03fdced790054967a7546c62a911467e409a8510fcf9ebd5566498d9f6aa2ec805efa65551cdcf5d8fa1c4828fe0304f6019a7f7db167187b7b796b810286ee3	1	0	\\x000000010000000000800003c5f9b2d58676fbf7ba6000a384a320f517871923cd4bfd20f4b97d81843263dfd1fada372672cf5af8b62ff94b822a50f51b47a258557730d1760b4bb64e8cf12499740908917e9b8d5a226de44740ee472c38e4d1d31adf15c1382525e9c6a37c0be52e543517088db0119bb8600b8a9b8f61f377914ab2592b0ccc204a5e0d010001	\\xe4a27b5fa4b00ac37b79a9f97b647acdd19667dc72cab58a269454a73e118f888e765ce9a321a941bb4339e20eccf11b8f520368dcf5ef8042d259dc2e90660d	1676503288000000	1677108088000000	1740180088000000	1834788088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
95	\\x04094380b437069d4274d09a522422d3e6627a1329e6ac9e980bfba84d4f323d4ffc29c1374d4783f387b362437093ab369ff98ad95c491001286af5f169eccd	1	0	\\x000000010000000000800003bdad40140cf1a53ff911979f581337f675b43474dc6830e8e8ca0c6b113af0c04a85fd087e0405a5a6c2cf7876cca98394a8ca74f40b2833a23d3f94e45a58096525c7316596ed314f844ab2776e7fbf78e74a8f122c6a7bc702dfadd527418579cc8cdf1b13713529c9e2c3a2a172cd5ddb6463942615912602870a6b16095f010001	\\x34b0512f339e7c802f292368bb417a97e968092046353de4b95419115cc254ba591198089a8ce8a971512a01b3a4ebfb6168ed51e6b71b31afb04e8fb8fda302	1664413288000000	1665018088000000	1728090088000000	1822698088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
96	\\x080d2de911d228532c8423de409a0d15a499f05ea39ffe02fb387097879f55952954862a1cc0bc442f1487d4ca79c40b6f8862ba675152f5cc4d442ffb4aa59b	1	0	\\x000000010000000000800003b77cb99ccf407832a71f867be81d354e182322d4890960612a62cbc00edc73a2bfa96b42be9360c12b31cfd7ed9ec1e311c6ac395bd4e365e7d204598a711f57c3b45a509287f9b03899efd888f73515df583a783da7bc40faa23caccab7afa8aa6b651bec5ea71c07c950469c8c12b7fd170dba3e4533549b19c3b1d30aadd7010001	\\x9010640f15ed130c8c65e4c82b91cad4acc767c3a189b2b507eddbbe7e32dbaeb898b0ef18eb6b683f4579172310fe4e7419948579337e8c3a0e839f0fa2fb0d	1652927788000000	1653532588000000	1716604588000000	1811212588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
97	\\x0839a73e7cdafafd460886c37fc6fb112073dd296b6d1aee90908b8bf1ba46b7b754bea088c006b628a713f49db2c8fd05382faec911dc6272a5fecfa78987bd	1	0	\\x000000010000000000800003e28ab0df377d52942e921d69d5e7ec6cc699878e98d428f8a40db163d547bd336cb2032bccb26aaa13cdf1d047e6833188061cf747a10416fe9057e3876d0b44d79f7c0760b79fe67b55cbcb075637adfbea644b18bf1c06053bd8c7ba00666080ed034877c89b2460dfa27d0b1893db28f8a2045b5af1743ccaa892f7663d67010001	\\x5dfbeef892a20bc7ae12d2d2f32a7f796306c412e0d5e3dd84c83221f2580715d224d2d4209ef1f0d010b6bfd56154020b85b20aa12aca3777fbf9c81ffb6402	1677712288000000	1678317088000000	1741389088000000	1835997088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
98	\\x0b7d0048fc8d4dd8d48045c930be25330ffb763ce54bbd3031a34fb19d1ce95f552bdb52c47cd0649df7ddc8f98a8a4cb02e9b3a50b94095b6191005ba41cc7a	1	0	\\x000000010000000000800003d2d160df4f67ab696e9702ca1429f18000d96ed7ced203593a69fd945a406045369295162a08a7a81d0be9fcdf585ecd6aa140939b1d7644741da62fef0e84b659ffc793cb4905591fb272892aaef3c58c249724a31369aaa5d95c11dd67c53b13c1f823627d2b91ee5a491e2f9d3b466e6ba1d57fbc535d9847d53714cde0cd010001	\\xff2711319d71fcb131d6caa04a987aff225ecb0c8dda93555b5cc6dc986734249e0af4592685a5964b6b48cfb9897c614001acde0df169dfb9ff5fd6f6b7d10c	1674085288000000	1674690088000000	1737762088000000	1832370088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\x0cb5c49faa88e683739d875b4a0d29f51a65916521b8896df8dcb6879a79524974ace305d1cb54f0e69c8b84fa878ed25cf21637229c38512640aa7397b55d3f	1	0	\\x000000010000000000800003c2b10fa0ddcff5b5fb1782a2c0f73c45eb4224c8f7a27a893e12138b91887665fd3d0472ab9de73a6fec661e5babf440b3ca9c9cc3dc306d03d6c7845fc28b062de61e75416eed920da5dc662e503fcfb0a8b3f70bea724d01c2addbc72386fddcbf0fda362653814517d10796a66a12819ec8f1e42c20d05dfaa9b53dc8ed4b010001	\\xf747b9e22a642c91386ca5e385cff36b4c1eccaca30e012e834beff7e1511fa3c1d8d25cbf02e36072e222342997f820a7cfa90401c8b2e5574368d1bbaf9b03	1674689788000000	1675294588000000	1738366588000000	1832974588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
100	\\x0ccde98f51d04c37b6a3d6d3b8c645e63d50f1fac004f0b2ded09b91646f162c694a3320082ffea38b6979fb036d522dd5a7f2d6005b8f0e4df8b5d5c08c5903	1	0	\\x000000010000000000800003b87f25802ae82ff814de0b1f40fe244fbec55a1cb205705648c061692babede1da075928ada3e9e963353a087420dfc89eada07ebab5e2f1a49f79f68a9b3eeceeacc2a306153f879cb6144254362afcac7df2de7e5401f763df1a9a8acd51a714ee49ae23838355ec958294d3610076e97f7059f3ada90f0f0adb1dddf59fa9010001	\\x50fc39f42030f8a388aa5ccd1bcb3d10c68a9c1840c04b851ab172b7d40a80ecd605f493023aa774f5562cc15764056296c8fde06f3215c18982d0bc2eae0402	1654741288000000	1655346088000000	1718418088000000	1813026088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
101	\\x1279b4ea74a6534cb30dcb12c98ce67aef032eabf2c8cc0bd2535e667a5c21e91e58e71e13454e9cab29b3813a2d4282b27fa83082ed5ab57e48270b66f9c3c2	1	0	\\x000000010000000000800003de945bc1b669777204dbc1c556f64dbb013934f2f490913a33737dd993b444b4a06ab6aacf9f28fb5f9131f9356b2438726ace81c64901a68d8117d0c060373dafb537cb4c5cd202bcccbe494dec63b6969cd3391ef2ab1173ee129851262a19715a9fe2332c5a430c03e75833784430a976c5764ac2feb37da48ace764c74c7010001	\\x659598f0664ad2e0278d1dcf37c924220cebd9efbfeb931a2d8c46ac0ceec2cbb26fac928e09bada237db94371e6d1e371d478168e18c28f2776e99ca6676a07	1675898788000000	1676503588000000	1739575588000000	1834183588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
102	\\x135d46a87a7fd05c5dc61063540344c9cab20f1d60b12f363543139ae14019abcc8e6eb97958ab3909934b9e4e8be7c74deb385f0cf6e80e142d08fb35055261	1	0	\\x000000010000000000800003b65c6329cefae0f9b04db90db2ec35904100de27d1a2be9a4e964039a71a27decf2423c94fa4754f7b8541e9bff857e0953f4195c0e38dd482b558bd573b12bfb46545f2aa0545873fc358d67fb62e28bb94786c8151ab4b8d7000af9ade350ff98d69927ff14584c748bd4e01965ca5fbea09ee1d51c873c3a9f9f6281a2819010001	\\x82a426aa877d146c0ace886a08a10fc84826a2a4364bb4f59754f9c95102cc3a6bc0ccfb7f6ab4c91adc75af7c0fada5b16e40c474b8846d1d09da6f3e973708	1669853788000000	1670458588000000	1733530588000000	1828138588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
103	\\x16c91d23df6d2966d231efbe05cf3ebcac905c94eb5bb1507263f620708916a79281ffa7782bfa921dfe69d6d4f635653dd44606eb8cf0a158d5c4ba1481ff6b	1	0	\\x000000010000000000800003d6c3619d2bf00c79e62452527ffef16e5119252ed62ed67215cd55f445ac45dbf59e067e268be80e6ad9e12ed107b0b5e6834df1f67b27ab7103d642674ac42066c4e1cfa1f7fc46775452a62841a87eab2140b54a39436f0fdafb9ca32a3c7150912d7a81397cb600bb27cc831e855118de0573464ccce20bb8d1a9d567b46d010001	\\x93ddbf0182eb8e9f06f5d3d02fc0bf16d228e52af6727da97412c249535a054895e66ede9063420a86123140dc76936801f34d3af10fca4abf864786f0145c0c	1669853788000000	1670458588000000	1733530588000000	1828138588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\x1759fae6291ccc29c22b81102a98863fff6aea74f78bf86d58ae9dd2c8a6a6b6211f34a8cf535dad7bb91bf828969532d97f03d61f6ac4000f7a966893755fe1	1	0	\\x000000010000000000800003ce2eed9a94eef3ebd25773d3e9a37b8c6e264b43c9820664881b0397aab6b3d2247d3dd36ddce87e393590362857cf84920136bc7acf1f18ca297733a9e74cea204fd0c975a0613aa974a11f0f8f27e237c5303b267411588ad7a00a82f302e93065f4e5a494c2cabc5d3104c5e4d3ca72b05d3be6610960df1f05d70b365edb010001	\\x860bda3cdc2f29d3f3d15d2e8ca3f5d119be0d13c81352315d3068525ee29a497380a065e06f3f1940e67d36c1fb1ff766699e5d131ec7d6c85a12d5a981a307	1672271788000000	1672876588000000	1735948588000000	1830556588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
105	\\x1865a0ee345c2b43bdd58447ffb8bf25d7c4be78a23f8631b886e27defc53f83f42b804155b5e4ddce3bfd91d82a5c7820b7af998e846bfc8b019c8d79b57bb3	1	0	\\x000000010000000000800003cf3755fd195be4ce0fd72063040f327b8b04585c40c056caa215616d9ee9ae8f62a45fee28927738812acef808b315773d99f5e038a2e2e645d7c8fd3505d9b3f8a2b7e151fa4347e9cb86dfc07b271245f17a78887a02c9026c343d8f6106d935ad3057ade54413a36d99e5769dae1f8ee0ef4c28499dfaacfa107cf08cbf89010001	\\x60e176e3bfb42e8fd7b389f4e6e8fb9f63e1bde7a30c406acd2320a0bc74075735435e85788b7b28019014a3db9e697b3c91afb357d6a864d2d5777f711dab01	1668040288000000	1668645088000000	1731717088000000	1826325088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
106	\\x1961c459b67fe7d7748ebf7a50982e22110f030de8cca793c1cc2b7742396d467d9635b38790d4327c4a2c0a9679920522ee3b12089ba986685618a904ef047b	1	0	\\x000000010000000000800003d0177b5811411f693a2209ca5e792215a062213edc557a1c7760fa6519473eead639c9e40d6561c9bb70e27fe1ec74660dd306bcf77b1d88f4b006fb18436b1d85b1f68f38af1fc6236ea1adbff7bdba5cadc5c786107a782d0127c10bbbde24788c4844a1fbca648b86396ac6b64e4a8caeac26440483e05c7766eb87cc4f5d010001	\\x1670b88ebf98a5ba6cf60e2c45f9f3409acee25fbf16decd4b54039e5851b88c46ac98e940ca9708c78142709b89568e923c4e1975a6313343da127cda530e0c	1674689788000000	1675294588000000	1738366588000000	1832974588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
107	\\x198dd99f6ebe89c76682ba4be65b8aaf6c24a28c5587a5042718a5d5921ad45b07f78dd90ca2536d13695bb763952b19625bcc7fed04852cae246015b2037564	1	0	\\x000000010000000000800003ce2f6f54c9da0c9d3692e6cc3fd89988d31349d4cab283360d8ab7d01e418ff615aa6cbe8483be2d91ed71ca46ae6765cce72e20e12f4c0710c76f305d2500a85c38200a7708c51f3bee92829ec1fc76478694d9a6757ab14e7c24993f3bbcf13db449a52d6bbe771536cec4a4e5a864dc9ed0041bb6a8c4f593a7cbe4100713010001	\\x1d0be99e67b9a9327cc81193a0a1f95716fc95af3b35a3e4dd467859bc528e3704d695d22af881795bce9cdd71836fe63c9056ae348679f6b5145835daf40306	1661995288000000	1662600088000000	1725672088000000	1820280088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x1ef515dcc01c289c90b7f88aa8627be94c9bf7f1fdc145dfeb04c16bd2d3b7426ea3266e498d6be93fdd5113e7e408cda5e3f2c2b32d851677c72fcd4e7ea092	1	0	\\x000000010000000000800003ec4399c2fead1dc3b57f5998f276c4343b87b2e6894164a268f6911a06b352cc8391212a1b05fb3efa75f075be6e2cc20eb56389386831587bd016cac5a5a33b6daeda240f4f9c8a1f90653efe62d47d62b758c2beabee508d00465d320557b3c2a1c38fcae080c9d765f212b84ac8e4d52eb4a4430841b97663f16932f6ce3d010001	\\xef1aa3480664a154f4ee8d6960f5806149042cb4f17aa478d2d1a1e12330a08eb80b32373c2a8f23c63c06acd11619553215c058ce5df9a0d19bd883be5b2f0f	1676503288000000	1677108088000000	1740180088000000	1834788088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
109	\\x208d745c6db67339ed43f5404472afa38c558cac1f43c8510dc7d236be8fb323d13076ce8cf61d9678e135387eea640e45e1e07c09c258a92457a501742924f2	1	0	\\x000000010000000000800003ef863036a66da6efaf3238df14f4b234b8b985fa04eaccceabfb485b41fb50bea1a15624d4bfa236f64bc97499d2aab315bd66bf250b7bda118ede9c899cf9d427fd140dabf7fa82848dd9c97a834908f24372a3c698096b34f38fca7af0833bc9be16008fb8cf363d5fed87808ec71d20b40da8656b4b60b9861f0a80b0291b010001	\\xd05aa0f7ebad9f0618d0992e7498d42c38141ac6f75c5b14153779cf0c3d1a4bc76c0e195dd2f981f8d0309910afd8a12efbbbb84c0c98a777a93b33e976380a	1677107788000000	1677712588000000	1740784588000000	1835392588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\x22d1ad09362331861b4a75c636f3b3657a2208958e47100cf3adf5808ac98c06f9a44d6547e1bafcd60ffd9396a827366227a0aa189eeedfefaa80f3eef7a478	1	0	\\x000000010000000000800003daf34aed75b074035e98257f89e9d023a1127e16485554ee2c9de713b7ff5dde36dcbc0a6cda916374a927c81514f0156ad3777162a448564b7521d3f6b8c0c400ddf23b67f0231beef5b36bd28060222401d690cf6c2f7ee257c43c5ce5a59c0771a940ce4d9e4a78adb603eae7ef946c96e5bd9a56fbd5a2a58d7069290c93010001	\\xc9212c9f470bdb02a3a6d73cfc8e7f705d9defb527c111f323515dbfc11fd288b1e66f95f4e36ee30ebfde0029bb3302ed24fc9f8c06de80903311aa32d74d09	1662599788000000	1663204588000000	1726276588000000	1820884588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
111	\\x26c981ae1458e49d3caa779a397136927dc889723835d4252dd46ef5c5d9bafbac9a165ad0ca62597b9c9c541910adf16ba51bcfd8b79af9152d8b79914787c3	1	0	\\x000000010000000000800003af272455e168b3c7f42f6b7b30f43932b70fed5d2ac006dfc69dc39057bb18226c46a79b1e446cade006bf255ecb79ad8e939321acff729fa3cf13b0e8c1d54dd0de40e7b5faa95e37d79de7baf9149e3a2413daff219b6e1dfff3c213e6a1e1dd6bd4b41b03d1e4c90e0bf84500f0e905628086e7b37e6fcc0639049edc7ad3010001	\\x140cb75bdf9d141c32a5de678236e2c6875b9216126932b68ed1f893a4eca46a7b99d5e161488dafc3c57ba8ab98187997b5764f46ac4795a150a9cbef096a09	1654136788000000	1654741588000000	1717813588000000	1812421588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
112	\\x26610811dbb78a382751d0fd8783d27e9849514425d4f1d1e24d658c1685187b66f116c8699d110eedb5f58a133153b01495a6086141fa755f83a4e517119c26	1	0	\\x0000000100000000008000039fe5cf9122440ebd0857d35800be1233cd3f837f3e66098fa741d3264dd9cbc4f39441ef08696e64e8e9e6212c259af9bdb8586bc0ae0b3eecbf5cd07e1a1ace787ed725d8ad1f6312a55d183075ec57d343a0fd38c177a5ec459140903097dcafb8e36c3f324465dfbfdc5d77238f0b0269ca822eea0f5ec04c01207af5cf05010001	\\xe915eda1775436f0e6f0d1176d855a34bde207fef1c0b4deff41ec0d58a82e272e0fdeaee8d95bf150e7cdcf03b0c124626309892a76eb33ca144dd05de66604	1672876288000000	1673481088000000	1736553088000000	1831161088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
113	\\x2bd95b01b15be8fd79b9145f3f028b98d6ad889db989f34811b4717be42b72d1088610d6b465f41958040dac2d2f2d067d0e61d8da470eb4f7af37c6dc33a9b0	1	0	\\x000000010000000000800003e8b4f96bac3a6517df4b1a2123ec87b24aab683b21c93e2adb416abfb298328d4c5f19f56f96d5e403e954b875db5d758c72eadc2f1d550bec8363acb9e27a9d5df276402db4383cf315bb0a6f648550ce72aa34db70de6d43c74585a780cc096086cbc41924b9e99fa290719b7969c808642270c412269f363cb090640aa1ed010001	\\x6c6460caf4d86d79948cdc03c9655260b3ba2e55c047b6495cb2e62e66d4f9f559bad7b85ef3ab2c5384425c26e4887b18328c91f79a1d8c6ba11830848aeb05	1650509788000000	1651114588000000	1714186588000000	1808794588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
114	\\x32ed4e62841cd65f90a7810f8020b58446ab1594baed936c149aed91fed732a08184f8456b4a00c4f8f816e0d4dbb26cee13bc1b8ffecb9646ce781e22f6d8db	1	0	\\x000000010000000000800003af5580d14ec25071b463e3d9737b178845d3db778c0cf6182c60425d459556a63996dc8abb2197702369aab29169fbea20027c22d753f23bf842eca60dbb546e15e473568e149623f09912fd39ef91bd8b14a9bc82c88f357535f5431baf62139f44b04b698d52aa1a7aab430e9820d19ee1e4db6ead6f8c37c8ee97a2404a27010001	\\xd3bfea5f8cacf448531feb977d8745769952212469a9ea52d05a9e8d69e1ff19c6fcfba0e9bc9fc4c056a48ee62472695e1b801fd59074f24bbb67f3aa5f4605	1647487288000000	1648092088000000	1711164088000000	1805772088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
115	\\x32e1b0d8ac58cb309e440baa1490249df1aa58ad2ea5b407c23f2ccad88950d99c797dea0c90197e7466ad69383cb3e0ae2ccaae4983dab885df06828bbee56b	1	0	\\x000000010000000000800003d693f02a17572610a4b343ae80debce245ffb45e445e3460698e06d04518e24a47100bc0fa289da0dd70dc8f1eb71b2122f9e5ab55d2298ac2cd72fc954b6c847a512604c5a6b3de4c15facabdd4d07365aba5d5f3ab613f8b6d6fb6f5e8e224c228c5f5a167fdf2b813862c8d0748271c15c6413eb6eca96711dbe44066beaf010001	\\xb878eb9af79bdc0bb6551c05ab7757f4dbcf9414ce4d1c65ee87a2f3eca1c70db554de6837aa823c064dadbeb66015185a5f72de6cc66ecb999345b63847d905	1664413288000000	1665018088000000	1728090088000000	1822698088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
116	\\x34253844cf1bbf4d4acbf15c2e53d58e229ef85d0255391f03df343a2d07e7a84f273debf40e35b3306a96bdc97d04302edee388d2aa5d1eb4a3a74562e836f5	1	0	\\x000000010000000000800003ac9067e5bf51c03b5201a2d20e64e743832e95945acd2eee3963dab77126c11dbfc092f3a84e6a8cacc4299fadd378cecf8cc7dd0af47b72184c1866f723b7bbec7ef4743a5c857343f58acfc6880394b6a3b8e042636671888fbf061bdb0254bd8c0fa671556bfc36ded88e5d544ab4252f90a5b8783459b46a81efb3b9fa33010001	\\xcb598f8c2f23f72b6716f035057ee553559ad974027e2f96c61e6abfd0e7cd0b9991a5251c903b805389d32895ef1112003f930c90af557ca6628604e3686b0f	1660181788000000	1660786588000000	1723858588000000	1818466588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x376d73929f5b07d1314c9fc90cd8a918953b43f834c2b4162fb5192a242ba99058eb700bf20770eeedd7b13e57d40b918c9548d7d4795de253b583642b38a523	1	0	\\x000000010000000000800003bdb5cd0b9acf842e28653259847363ef52c51a7ee8ddc70d4c9abce0cf5fcf7932cb6abfefca209ce7041a746ce7a1e9648c0f292096ff5ae9d0a47b566211f2e3259ed5cd196f64675e496c53563818784c803110dc14084b2c4b86155a427dae7c790957c0e7bb1bdb5c1d6ca2e6cd480b5efda4af793fd52f7ce343457b9d010001	\\xb00d3b51ba0a2be0e6fe588120feb43df2531ea950205a8edd58d163cf7817eac728228739f92100bf088bdbcbcff5fddfecbf96e2f1ee2f9438297c0caa0b06	1648091788000000	1648696588000000	1711768588000000	1806376588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
118	\\x3999d397985a07dd9a40dedb931d01529d555306a663a6d271f71be4a5648a0e2965bf1833befa9c3b8ed3986ee5cc4ab8205036d407d94ccac03fd998c18938	1	0	\\x000000010000000000800003b04cf19505d1bc25acc5b4dce87147f7bebf0aa499c36cc270b48f652f9eb0405868832112c26964141b10d3e907394d49fc82941bdd63920016174a86f989d50d06ec5ce9ca33a6c631cd94ad35ebf96432e55049c3064d6e743a6d354ed345a55702461d0962cae1b86b8738087bdbeb1da357776907f21a512bad1ec1010f010001	\\x916f7e88282a54e4aef31ac36691cadc25a1a1cb1f9bdab9e18ff4af5d9a1dbebe6daf46e2e776cba88dab31be2b0692065f2ef9ef195223cb307a6749dd3a0c	1648696288000000	1649301088000000	1712373088000000	1806981088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
119	\\x3a35051afb50f4df0e5dda4402e4c064a14a55c6fd955fef12a0901f471493ed17e7f64de5cc5b8a95919029b8d8e42f99add7111b7112d75dde6e4eb18d044c	1	0	\\x000000010000000000800003e61136e6be48aa3563c155f4d715332452060eb9d1731490824ce315a34864e9ae9125a151f3b9852191b609ff6fc2fcf9ab0703901c54b7194259cecf60d1c5dbe244f302eeccb45eddfef5483e56843ec9872226c5e3520c300a7598393513248f4d5a23adbc74a4b1cf22ab3e81dd741a2e3b5a84d12e8409506ed89e607b010001	\\x65e7995032bfef33231b6fc055b6c357b246a936fb010f45efbc28e5bec1963bdd02ec269aa23d9f3f4b03588c29d16b2277607758df5274c8eec3a83d6f3d0e	1660181788000000	1660786588000000	1723858588000000	1818466588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
120	\\x3f390ff91713b2331a6e9f62599fe5033af1608f2aeeedba09d1d394e5e91fa411cacf10abaee61b94f6dbbd004817b110f8b2192341de4263af91f19868472a	1	0	\\x00000001000000000080000399994f632a73cafd6ac117623e0db8da160173670585a252eb70c51799669820349465a0055a7a6a2c59227048ee6850e900855d72a07cfdfbfbcdd1a786419efb015d5a7aec170088bbf9e26400c9de65ed5dffdca7709d29b6f933670cfeda40b7699b33730af43b90088249b3023d579d54027b09c31873e1262c2c84600b010001	\\xed2b3b246adbe0451c6846109b40e78999681f2f9652dfdaf7101770bfd6b07c5437ad3d11a087eb019a0a1de3729290fc69a0060741217391cff3e0b6fd5f0f	1648091788000000	1648696588000000	1711768588000000	1806376588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
121	\\x3fa567a83ad1f20f1de50c4ffbcfd3d5dd99706350240e7e8bc10a4e832963ef37aa8fd47136d47b30458b57585f2c28a9f37ff5b4e0beae1ef04873c04e3325	1	0	\\x000000010000000000800003cc73a6f9d925c986ec6b937968ae563b4569580b768f35a01142d69b1d1952e06514425e70cb81dea4c59df49572f00d7de50d7eaf30dee75bb84840081fed79a083e0751b39b5c3cba2bc352436c8516325c83af6fd38032ecf7c68305a322ec3c8a724455cb34356b13e518df9f864171bbaea931b5fceb5a7ef4647195615010001	\\x7692d235d611f260f0e0f718c7f88e0e127a47466d51b377f704d179938d39aa9f3baedce77f7637d128aa356d71959c7212d8a7ba6943560c9147f1a596b80a	1676503288000000	1677108088000000	1740180088000000	1834788088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
122	\\x4551e77ea87b1442a8e0f14c22f4b5c720087f1ec3fb7a7cc1dd6baae54d24229d54641befa34bb96e3f186ba1cbfea036d4f902a357b6506ed49874a0185765	1	0	\\x000000010000000000800003d6af9c74a37586123f59e62afadb0dddd15aaa1d4d61f52750c2f8bac159b02ce5536da861aa42c246d4db21aaaeb72b5ad41b8ab52d26173623456ea8112421e02de87f97f6175a1b4a360d8e2e200444c1037b8c80ee50a76ec98b85d69cb16d20246253f492feacb2e416ddd66b14008a3e7e841dd83c8bef62082331bbc3010001	\\xdfadd2ed8edaf60e8e69f30ee4b19b4347f33a4381411571d6da289c6528eaa7b7e7adae8a23fd7e6f6d74149fcfe99c162ffd2e886a537286a0e2ab6553c606	1664413288000000	1665018088000000	1728090088000000	1822698088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x46494385f67e0b88d73191a928c4b2ec05252857a21018564b5ec9a82528808e6ae4938583d83784d9f9d9639c8c0675df3eee3322880b5bd032b223ebcf4cac	1	0	\\x000000010000000000800003cfec1a548077c6d67b33282258e5e16a28d59a5b5b4bab466d59dedd3bd9906a54593a0e186e3f80e5fa79b7a8f2519a4e580b31a55f7e76f597b94f219e86131a29f86d177ab0a3b5582f33dad8e9c87b17d41dccf12e06a4360b7e9f0af7a4474f22603f42d977d309f512c3250518483d61ca4b788973534988c0cfe41ca5010001	\\xa43c6378cdab5a1e695e7ed1b7d8b9080b17a0e3985d928a20afe35abf208132bb7d9ddc27f5f8cbf5d78dd3e5e0e84e436f9c0a02398bacc2d80a642e3de004	1669249288000000	1669854088000000	1732926088000000	1827534088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
124	\\x4dedc7936a3d92f7dbc689be1244941a11e4dea6ab0c10fc3a0cabeb2414f8e416027a7ce5eab2bf8772c7a55b23543ba6ac71f716044ae00bf7fe91d9ffa20d	1	0	\\x000000010000000000800003d6e20cb803b0e3e2ff4fa915c6e65e0a32ec0b96b22678c3d6f7de497ce6d9dea7ac5d8f912592148ca45cc6ce808fc3d6d4d3d55caad05555501e5aa111b1bd3a6f06ea9ec68ef3a784fa188f8243ecf096bd1adf7b81d05cc6c3fa3664ab0cdffb3f8dbda5f257992f7ee39135918cbc4cdf398c4d1116b4ea73778a829a09010001	\\x8e0848373706d5a04ace9c6391b68ddf08d9a29e22b45aa5de6e746d5d5fac9c8b64c6acc1a843fd9ff76ec17d6e1b73d3c1127f148a306480935145401f4500	1664413288000000	1665018088000000	1728090088000000	1822698088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x4d7996601e8c3d7d76a281eedac30ae02fdf1478a547754f656b30ee6bc59e7edacdedd178ff94efda1aeff0bc3ea616d520b56aa931db5c5b51c8bafe0536fe	1	0	\\x000000010000000000800003c35b330e5a8b3d71d3a666e8aef293a0acf0831136a82c208d3a3cc7646fdb58ebd938a88d4b3e08b71372635a67474fe82a0a105ed8465db335e55d48f948638f5aa7a5c4013f7b5639fa37f27e8a03068910ffabebb49ebc0bf4e26fd692982973180d7260c867f2dc1b9623a3f2adb971598b4887ad9a1bae9362187f7091010001	\\x17331782d42f0b3e7ab582404ffabf6473ea22c34fb4a8376205404b5faa8dd47f0264367ff712ba5f2435514ab87875d7cab2205a6250fe21a7fb63ec8a850f	1649905288000000	1650510088000000	1713582088000000	1808190088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x4e79ba8fd8a6d90fe155642f3af208b40682fbd36ece9e12db938173dc0770172b117b5cb5eb615cd5443adf5ee6c784a9837d999ce4d9c5d870cc437f56ab66	1	0	\\x000000010000000000800003f9d18dd2c42fa0153dc9b097924c7fbcc52e375845c94da2a12b409e3a590319e677ea6642a087c5e06a9a9951635d392df9a989ef74afeeb061e7f545c2d33643644091309f840a58b8d97c145b4068a69b828628f3bf91d7c2f7eb2870629f3a193e208ed02360634cd0d300eb9dd19287d9d562f9377b3795a01855019ec3010001	\\x071b44f78e19fbfc0ab80ce14219fcba84730fc0554d9f07c067803134d37877a4b9d216eed18dd028a870c1528b0b3e491fa1ed93b309492e29a4f57dfd4005	1651718788000000	1652323588000000	1715395588000000	1810003588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x4e21183285ee58284915bce2c94b9bb6bd672da26ce02717b71e26e19fd4495cddb437624e28abeac7afc1b0056c62fecff6004a5ec06d741195a92522926109	1	0	\\x000000010000000000800003b0bbcc509ed32bb459656d813e62af8d57c596506059e41452e9edd2169e2390e16dd4153d6c2a2ddba2c1e2b1ac9322879e3321462d8e303f735226d141ff75f7d138b80366e52415d28d5f28654069ab233facb09dda779f462268cbc11d2cb06db4c5ab2809e09cb3413d70a761737aab3edf0558d6c05c3b7eb4a5ac03b1010001	\\x7fbca9459aea1c9e088dab9e7064d8e76e34d5b55f84e4ba1b6e58e224ddbef31415775b5f2c917827ac9fd94c86bfd26ce3d3ec15692933e7f16c62fc12e003	1678921288000000	1679526088000000	1742598088000000	1837206088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
128	\\x56c9c129c78bb616916b20b509dffb0310c80010c8cd9f658723179e921c4d7c79583bde4111b1dea46be3f33709b098d6abc683945aacde3d489f22d128aa20	1	0	\\x000000010000000000800003bb99c91ac45ee8cae28f199b37454a8a560dc9cfb0cd95823d7ad2212c7905603c536f47375b1248c826d4bfebdfea398f45d5b6c87a03711a8b93368c6e4abf48b0181b96c181dbc28b251e52d19cf31787e24cbeda9b661d4cb122f24235869eccd8ee4cc2f514ac4bd237eb5a5baeb5bcd642b9dfcb629ffe34e81a925d19010001	\\xa81f937b1a126c629fe608d44f6ebbbbe531a2db0ad0b1ee77c6f9312bb9908302e35501b47248f0fc831529c6a4792e4f077293d387c32233a316e6d09cf10a	1661390788000000	1661995588000000	1725067588000000	1819675588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
129	\\x5981cbae30865884fe58350eafc9623a699b1c8df1ff5c72b959358336a834acc72609d2ce47a3c3f321a94ab8ee5ee526a9ff9351d034a07df2a45726023741	1	0	\\x000000010000000000800003bd71a2fc9a787db2f4d224fdc7982a1cf5b85352746b5eb1bc47d894149bc157d4db290535f442f07739896ec48056bba01713bcd538740bf373758de9478f3022d8f8e553630b4cb1e310b8b715920e747efa80b790cea1e64e30450b92b0efed9daec46153eb8edd57ba16fa7f37abce1fbc3c9b1d4ed5827d73f4f27ae14b010001	\\x774d15f7bbf1f950eb9718ff8ab6bbfb2a06e77e4468d8ce7d9385c11f323ca5a096ceec8cabb9b56258faf56b7467ad9962458db7fa785c2410467b8ba87c06	1658972788000000	1659577588000000	1722649588000000	1817257588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
130	\\x5ce503409e954ccfb5733e7aca2a9e70cca7ea9b21f98ead180792822f8856c30a6919b28b6ecf392a39930bf767308e547f9dcf18f9e6ead26eebf935c72fa0	1	0	\\x000000010000000000800003b2f4f3af8eb8e045a70d1daa757fa273d229f9f0bc89b4df92062cb814dc6846dc8aeb381396c598659d1e6fea3d36eabdc4ecf2f077ad80e584083c06bd5f528d8f8f5c34be658730400a925454a3f159fa956affcb0617031970eef3ab1bfe5ea8a53fb3b17ccea17379be49612bb11bdb2b4c86b41df0073dda46b7ef962d010001	\\x0abcf3bdef72c69e990f52731f4135d2e82a95a411fe77619fa0fc15d2dfeb32ae2bb71f78f1b886092186e9c0bd14f1e5d0d8de39d72ece3965a9060f681d0e	1678316788000000	1678921588000000	1741993588000000	1836601588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x5e79073dcc871f3087dd68c887665b967eb594a5b173162c28bfc3437fecefb802e6abc4ab9a56e6da9c83fa16727327a17de2eff68401119c7fc445603961bc	1	0	\\x000000010000000000800003d24b186452c8d9637b977cd85f27ef08bf1edea5f8e44dbf38b5621f7642ddbe3c26b60b51308af04ae486020fac2fdc542ae68a79db2443f6e6a51c81f56153e636dad7d2782db2e6d3e5f3f5657e96d70db68791f99e84f1a557d13015bc286f39f4ac0f3d3be3b0a8ef669e5111b093da99be10a014eebc9ac0cf3e1ca301010001	\\x1662ca37b75e58f4d8e5aac7e7892925bb8444597556aca2049c37ea723b5f450aa48cd5cee34f2afaf5f8c94bbf72cbd08af68f403ef864c7b4e3f0bcbf5604	1671062788000000	1671667588000000	1734739588000000	1829347588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
132	\\x5ea56be5e4da26e4ea1d905044a990068f45fc647173d30cadf25f79fc6cd2f44f528a11caea238aff3b41474bac58c0ad98d07a01fa7951f5e1baefc36ea5ef	1	0	\\x000000010000000000800003a38e558a6bd3653277b8eae68d35801d9c9958b607f90b127a0dccf7c8f568bde319a59febf0c072f94297142851fcc18ea511ca038f3f3614dbd208db633fb9502802e9e455b67713e62970841e1e9fbac5bc95dde4aac82089390b3e4b6c308e9521e473577a07081e69242294d2b169487ebba34aededdad555c52b41d995010001	\\x9d7fe7a026f1fa25d2038bd40485aed9dd81aa8e995f83222d727aea0672b4181c236b760b92a4a3e43df00ce20de0087051e6c4f871dde539241c754ed36709	1665622288000000	1666227088000000	1729299088000000	1823907088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x605dc17d7c5b38e124163cb74e3357648b1b726f501596b781bf5af40ac9343637be620c7288a65b9f00840b052bd0c046534717a7b051d70fb1fedaf5f84a54	1	0	\\x000000010000000000800003cd35cce4324491859e6af973b47e41770fba0fd8312e815dab11aa81fae9b7e85e946f346bc28086ba21c34a48d6b405057fd8e789a962b9366a280922121c0a31326a9f565f5c02368ca6ca14f7871aac1fa13af5ef7a00818bc01ee40438ae7272b18f45fcd3bfbd6431b52df1a0ff734cca4009508760bfbbf95819f87c3d010001	\\x2672323e4730cd742608ae0192d4aef8e65cdf3618d6ead128bf1008735c39e89138b8269cd76f41df993b8b2e948b68ded3860ee210c41c579114499e9cbc08	1668040288000000	1668645088000000	1731717088000000	1826325088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x60e56ddadb24a968f928d886bd7c00603e469072680793fa5d9f092148b78f790ea60a316a2ff0c2d0adec8bebac30548da6c154928272a2da7d14a78066031d	1	0	\\x000000010000000000800003bcd915e6c518d1e8bbce1b092ce3c8dd77ca95d93189a152d997d86a0325e19b55612af90db3018705114e906a2157aa5d6b3e4be63765d81c0e287f4c999b6e26531fb14af15489c98154105414e19d09ca7c00e1ca038a26083cf8093298c30c8ddd5009f87da010e9b38cfde05695b9f8a5a290adc226c37e93571750b255010001	\\x9c07bf4684128c3217714ee79280a7635251d1263a72c466fb0fd53c0bd3eaa5db7e13d44f28f9d8327c0e53f9a11f931611e2816fe508c0ca216d3f84ed000b	1676503288000000	1677108088000000	1740180088000000	1834788088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x625ddf59d20348e5b6d062d0ae48baa0e43906985324dabce4644b7775a1677394c517baf7650219f27a686c651e96aac7d351de422340aaa9f14ac8b7a40b51	1	0	\\x000000010000000000800003cb11f963c4a646449033e0f3dc0b2b777b13c72df3ad8d061fb0ed58287c3c8ffbf76f566c997e3172f3ff6a9030dfa87bbc3320b2a5e0a4a262d4da1dc0f807944bfcc7d4f60538a69f7c56d14ad1c061fc524c7a539f37b7ae0ea08b4531d76d70dd85f85c245f26ee0ba9e790d082bf3b87e0317a901b1111149e7237ee6b010001	\\x7bb300f5ebd0f835ec726fa8580ac22503e00981e0c44e5f3af00676c2da0f140875d7686f4bd7610279740c67cdec686580ad535107c936f6bfa8e709233a04	1669853788000000	1670458588000000	1733530588000000	1828138588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x6455bb14a0deb6961f8a4134ba4ca96ffe729820cb747573f2831bb89eb1d239ca32d4284e6401afe944e25289f3e5bcfe7d20a5f4b2ae6ac2340230424f07af	1	0	\\x000000010000000000800003d921e3982623635ca9d88c61f94264a27d8acc2d8b91f7b1aa97ef240fbe1836b7df9358780d1e43f20680d9201cfa216ac48a03886d12474e3bfa701028bdb676dce1035823f16f6ea36aae21713672ecb039969abcc23b1ee7803a8866b7f6b6f8abcf3e122c7824a6daf6a0cabac439601c1eb1d4ff4bbee2e358b4f50a13010001	\\x9ad50ab848c3cb62497d673018438e1bb6526fc63a5339aae0411e2def223e350b79c259269d8d840f5c0f19e3f6082f1261d54eb286513b5dc5b32f06f77502	1674689788000000	1675294588000000	1738366588000000	1832974588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x6495ba9d5e3f286f3f813fe640cf958d182bf28e7fc73897842b32eb3b775ffdd187a7f1524758eed7d74a05c5e6ecf034b2aa500344740cf5a62a8453d14d3d	1	0	\\x00000001000000000080000393f29cb8ce93e01a5185efb53f7c01f8613acd7fc4738a5a11f05ff9826d329bd54401031b49a18fbb65411853a2a14de32ea237cdce637c455f3bd992d4d425e82a64e332f7138e366b6c7fdb94c2d7b5f21ffa5f2e31268ecd9886b8879b660cd99f82ce613e3c4c420205fb910b99ae3aa6e420115d7b1bff980e5e25a93f010001	\\xc3482bea210654cffb857bb8801ac4a6144b2122e9c44824dcd7aef0695b4ea31d2780d6a40bb1cf9d1a4a7851856b70c0bd3e1e9823d9ae0161197285fed504	1648696288000000	1649301088000000	1712373088000000	1806981088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
138	\\x64fde312af98809afe66826bc4463daad2fe0d0fcce3ef4bb708d1145a9c2299e21fb89bbcb4cfcda2358b9fed209d85599161c70150543b85271df52dbf213b	1	0	\\x000000010000000000800003c4430c8154439d322be683d52b1ed57978c8e8dd4af091f065c9b5aaf7fee4aa504d505d0a467966d6b292a12501cb46c691b76d453546bfbbc9794c39ab6922c3ece144401c61431613e95da85f18a51823854872f50f2397f90f987d28ad1ab82d1a35fbdb0aabbfcfe839def6ea3d29420173cae6bdae25f164b6f973404b010001	\\xbec4178dc4215a240b39d268a467f6350d7c227efcecea7aa71c1c6e345ec787ecd6d1617058baf0c4ba4cb3a4a507673db8ed7d36c4d10e077ef09d8eda800f	1657159288000000	1657764088000000	1720836088000000	1815444088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x661db0729d4a4d5f2922383b23053270f4c5c14407f6e2d58c6b53dd244b3ad6a59815acc64d4c75cceaea20e168c1e427e15895284c3cdd98bf570093d36bed	1	0	\\x000000010000000000800003e19d6628792a1b5885c19cc47c01b85780394469bb67aff6f8f60e4caf1e11703921233f970e0998f11a6f67ab7af07e5ca92c6f5d0579acfef41c70174aad402b7c5129a41c2a50d9012ef004385da62fb0e64b80161ecdc226e9cd25b94db8b465bff61765e66c703cb209e170b765edd8143733a89501f2d13b57340d3185010001	\\x78a58ef7fa5108c0eab324e95ca223160f8b21861ccc76eebe9cf35b23330c3b0a8a1924cd6c4de40e552e8b4b3049c6a89bc5457b91a248814a67a60598a00e	1660786288000000	1661391088000000	1724463088000000	1819071088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
140	\\x67058363b1aa642a068bf898d866192d30ffca62195717bf29fb1564456087a2b66375b2621a6f253e3e747b17af85108b3e28f6a54c9457062d299662d7d52b	1	0	\\x000000010000000000800003a3bf92b86366dcccdc80e56efdcacee8b221917b7dd5d8e6092dd9bc453e8eff4ee7eab3b3f9b6e6bd54fd7ee98d48d96b07e241e62a0159d326a1714474684e42c96cc33eb80712791b7be0f85e2c0685dedc515be8e279b0f09c3878c32624d326e2237a0674a0feee6e47f4e128940725304fda87b01c490a656704fbf3d5010001	\\x648cfa5afc43395b9f2e9ffb7ff921346f07311c2498f350eea07704dc0d50416e85db4920c042d9051f9b199f85c7bc6ea2458dd86a6a9dbb7f8bb9c0af4a05	1667435788000000	1668040588000000	1731112588000000	1825720588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x69ada60b3d6e9c69ea071c786a3cd38cd07a53aa981a8ab7c5c7b437ec912be98b5c3845b095f3c9273903b7bce821e732fe96eaf983a1221cd421639ce43243	1	0	\\x000000010000000000800003d40df78aabd6585665044bd5817038eb7e272642ff2b90ab73a38d05d0b1fcc576014455aa98ce38b632277c9bd465ccb431cc0d756c9d8b76f6eaf096dd743c8a7a88c55678f31ce60a7dbba3985df32965e7daa9361b4336b7a460c2a7f5819991acbaed9d81eda418b6ecb99273d935e9960c4be0eff7baf9bbefe2f120a7010001	\\x71667b9191b208102347b3a36ba83e365ed6dca40d16e163c8f201ed1a25ee1073e0147fcc92e010c38a28ad5fbe09dd6003c502ec3ed05fada533973f086e0f	1677712288000000	1678317088000000	1741389088000000	1835997088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
142	\\x6bcdb7d3e3eda17bb0e564d1fe0cfd48e5140de51b8cbb87fe85cb2b1646999013747df89f15f61c26c79c001b9e1d4d2e77881316b756e8fab2c308384c77aa	1	0	\\x000000010000000000800003ea8fff5e6673d85e5ede30fb6610cce58846bb716e931751f12930fc5a83d16d8abaa693d215c987093b63c7709594b65141d7855b1aca28fc3cd8c1ee7a008ee8a6906d50455633916d567d72de3231500cc99ba6ce088c67b9af79ce1ce181070d42eb465011a0547a446fe8d88e4de6917049232fe89f11683ce335a5024b010001	\\x1eac801a2c88ee0186cf1506e079e7542fc6313053aa5dbd4b95b0d3ee898410b0e944ef6b0a276e9dde7b01c7fb4e50542942622d31f7e6cf1da40783d92a02	1651114288000000	1651719088000000	1714791088000000	1809399088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
143	\\x6e594d343e7802b5e131c2b6b92cb9bef5f17f241d5beab46d64ffd29f9325bbc2690f426a7d0bf02bc20d73e94ccbf286f85f2ce3d19765a14be10be745b6e9	1	0	\\x000000010000000000800003c4319deef6cbe811f712f8433ada6cd7f55cad88c9377abc40fd123b5ea373e26fefc6fcc1d5922d451410db18d2709b81fa8b3f3c8242a3ec3c9d83cc908e5825b59d00aefbe1b76422bbdbd2413e9830080740caaca983298383d985409d55dd2edae366fe1e48baa0b88f4b7641596b9ef9bf08ee3c6947c31805ff0ffbed010001	\\x614c9e37188577d8bd746b68b39922cd1c11f07aebde41c3f7b18b10fccc550a4d4ec845886ca481e151aab14653a00b7c7d955627640ea032dc22f822136a07	1662599788000000	1663204588000000	1726276588000000	1820884588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x738d50322ca30b9bc73ad1a4b56fdb325f1b8f3d49d5fe630f8fe70078f0b87a2595a4a6027a2155b0fdd3f34bdc8d53cd57c8f101851fdca11ce4ec2460d8f4	1	0	\\x000000010000000000800003a63f2423fa36a7003dda24e484f260ff87d0a955a8d0a8ef89d3372713cb7d068d130f68ef37d7af12aa954f692101a8edb4604fad7722b21543588051ac79e9535daa48baf16532b68b13c43c3000bd24dcd37ed47d5421c0ac684e589d45cd2ccba857079ccff80c1db78ada1469979d7082d77624a52a0def592e9b1ce98d010001	\\x0b675f1461f7cfb19737711d0c40b7494e6ff50f5a5ee6fc8e0ea7876cfee479b4d51c99026bfd2db41f322b10cae90680478ab25ad0348ef6910a0f32d6b509	1652927788000000	1653532588000000	1716604588000000	1811212588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
145	\\x76f99a3c0dea1e95477ed2760000b53459c40daa1dbf80e1a65ec9ce0eea0abd16d533deffc4f95fa673aae7e8fb0f5cb57e5708c06871ef747593e08fbce241	1	0	\\x000000010000000000800003c22724389602d0720c99e97580729fe686102d3ffe1019813c53bfcc0038de7c131416b5086d630e30d57588d8aba3191f55e923629ccc9f4a94121bb089f0ddf70f3a58f19fca155a19d2d17253c0ec72256e9b4dc4838c9b40ee739ac59a08ac0013a41b998e79b0a08cb403e300a4fba02f662e76f25ea6067574cd03ec23010001	\\xfb24a1ee18487feaa56742493df184491777d246271f131631ce5462492fd09bab4e456b73a4a3c1a5c2d6d19b59cbb60f63900089259918373b85de8a09b70b	1668644788000000	1669249588000000	1732321588000000	1826929588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
146	\\x7729eb4124be2633ea9ff59b463e99fb21c89b4adf233e927fbe67e53fe3b17e84e8873964056e19657df8de19827912d6e5e6af7d9309d3f2ca67c8a4f6f3bc	1	0	\\x000000010000000000800003bb284c937d9e63bb2a606b3e7489801661450b8a40a2935e97c1e7b26df0976d90a89c79bdede1eec32d61c23bcf8741fe31a98f81d93127adb268c7a94acc95b82e0a4c93e2de2307439cd765e706631e52af6674a840aba39d4d38d835c374d283c59743d3d969b45fae3fd9f17c49b7a3f2c2d20e9a923bfeace7dcaf1da5010001	\\xcd2bcb9230f658dd5e0d91cfc5e9c5cc728441150784bbc43bb5372a2147e49e0ecc3316d563473703a015300cb6d8c91e75bb810807751276f0488718a59701	1670458288000000	1671063088000000	1734135088000000	1828743088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
147	\\x7bc16a511d7b4901dc6b619aff739c60c378374f8d9376d131f03084d2b9de6aeaeef5ec380b31c8816dfaa3257d12819a5165a607d2c0066321dd8b627a246a	1	0	\\x000000010000000000800003bde7f11edca720d6c17ad70faaed6b55553004ed3885520c960ba885bc102029437deec5f67958908196091c796dbdcaece525b50923315347066aa64ede9978f192ca8ab960b3b6a7d4acb407904171c62274261bcf9584183469ce216893ccd34bf8b14272f0c5ee8923b93a10110d4639cd44cc14fba30bd82abacc2d0057010001	\\x75e6b4090f461188b33b4c5a9594a9c62ac64ef12c73203b818187e482b3fcc868c0589cf65cc2c982e9f604aaff93e4c11045843af18193d6be131acbcc040d	1678921288000000	1679526088000000	1742598088000000	1837206088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x7ff9fecd824db18199344164343feaf5cad7ce201a81d28b73be2b165ae1909a8b7e76634dc82435df455970976e6b86ed0c8f3ce7cbdada03cea71772613904	1	0	\\x000000010000000000800003c65230f9a2c8e713c99c2a60c58b5b89170af41946dbd61297bc53521a81a59ac387255e40c9170461115178da2471819ede24764709ba1d8de0c54fe80782e5738aca9aa1c24401937f43eef28f4357875d599b1430b88285ae0b22f16c9de3955a269edc8eb7f10524e99cda38244047885c4a7930aeacc42c4374b92bae53010001	\\x25c54b74275c994e2320768bba53c9698fd8dc89c8d064b886b578df620c7d623fe528dd8073e1890e4648ded34a70a269f99213f14e7353879a87e400d4450a	1671667288000000	1672272088000000	1735344088000000	1829952088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
149	\\x8c6d2324593e6168f4e5a766884d5ad17d546b6a542a73a5bac9fe681ee3d1e79856e98f520a1a02a234bd63a324702c997113c2afaacf96046de526ba30a592	1	0	\\x000000010000000000800003c23831b6286bdeab06042188b4e2fa93d87528f745cf8ba8eff4b6d72e937fadc9a35469ea20b4123b344d5fceffecca3ac96407324fe025f63f524870038c80f4f56cac1f76406f25419591f38318149d57124300772e219f73cb03ba31f814164febaeddd8c63943c53d9bb430ab87b8bbf5b756579fefc769c3ada2e32019010001	\\x64ad70f4a4285a1852ae02f3784906a2831ed4806a02b4cfbb9f2e51f9abf36601f01c2f14c1e659662366a245382d3846d690792cbf5e7642fc94638b328b03	1674085288000000	1674690088000000	1737762088000000	1832370088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
150	\\x91b98fd91491bc9b584e557fe4b4e17682bff08b9d4efe4047322ca566ac0a31adf8f431dc832125e5f7a2a11214e210b4747c949d9c914d33b32f912856278d	1	0	\\x000000010000000000800003a134ffee8f3ce16cc9605282909431f324c0b64e7e1105b321efd825d54aace9a16d23ed029033976a7fd33aa5bdc9051066a12cf35eb136490ccd1fd5004d7594c1d9278906804cd99acb214ebf030133c1b37b8ed9c34cba789c10cd490f65c88bad01a19b4153ad47fa6f9fab2e97ba3008b051c25fa36a16e92b4cef30af010001	\\x2d12b671ca8c6becad22a45ac150d14139543e6bb5b3a933839f5796a47b334011408ea1c87f5be12a02fee05b5614450190bd099b6de064ffe026f7ac925907	1657763788000000	1658368588000000	1721440588000000	1816048588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x97c97c7eea3aac32ce27f7c481388b9d9f6597df4f7f1349b5883727140468123fc5f44a37850b714bab83dc7279c859baa442768ed792ba441e1a11bfd7a9c6	1	0	\\x000000010000000000800003cc22963a53e65816d7b2d0b7ff732f55f8634cc25d0d8a388c88979b3d5a4660163059729f541dd2a6568c52570ae7ae5486da3df18143d619221c786e24020d4791cbbe7ee9a1b45e4854a8b86401f7d6e69ef122e4affc337ec4ca629dffec92eb23f673a6475c1957786d9aa05f0f8646979b744428a3732ec3c808163b35010001	\\x746b3583822f5930a15d9b8eb02f3a3c43826d534b669216faaf2d070a4c732e915943393098548cd075f60552047871ff58627e23a95e32746f2e36149c2906	1647487288000000	1648092088000000	1711164088000000	1805772088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
152	\\x9b0d0b89abea99a502ef714d04527e3776f3db0322b5389eed06f201e2acd64a9e575f3ee6a6159ca96e08e52a7f1bae8d8135dc05665b6da60d434cfbcc1c14	1	0	\\x000000010000000000800003c7c3baa3a4e765ad6a5cd3c0d6ea9d9ce2098b30e41d9ac0b8095a14effc92c44fedab77a8ab35f6eb178cb84215cfee86c0c52371b61fc72aa59ed370938a640837f6c119f6fa4a214e54fa36fd1550004deb387a0b7a4dc23de75ea05b7f1ab44e04791d4b7c96d4ea13455f60d7f92c4df53c0b87f22a446b78130ff38dc5010001	\\x70fd5e57d47f33628101de9a826b2e64fbf3ae69aebfc3315f7f40c302c4d1e7d1119d080298bc9e865db2d671a8af9b7b59700feba276fd297d887b86aa1201	1667435788000000	1668040588000000	1731112588000000	1825720588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
153	\\x9fddd8956687d22140c591bfa91972ea197019a99aba9e30fb1f674183a0ec1f48285d9fdfffe77bf93aea09c14e0ef6e09a30d6658d4d8979889a77f2ba21ca	1	0	\\x000000010000000000800003cbf376e9b1e5ce45330f383671a39fd925f1da56573c7c4ee9d601c0cf026020ec97ebc48a50a7f1f213a68f68d9208cb132611527221bc1947b769f5e007326c071cfa1a08d842a033011c0518c53f3823235e1c28a7d2f186d7133d2523eb2338410a9bd3442e6905b848dacad3b7d9aed48cfa92e63c6b0acf5aaecb8e5e9010001	\\x1d955952a57ea1679a7b292b5d10c6781d752d1ff7654fcf1270954d86dd9d13dc36a0b42805bb23c703fdf477b32ed68b7cff913627e912d13799ec03bce206	1658972788000000	1659577588000000	1722649588000000	1817257588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
154	\\xa611cc7f7b71081d20fefa082cc9c81c193c9603a1c9294b9895f5ff0d34803ab169acb64202b7bc204e694ca3fe452cee1ebb47dae684a5227bd82794edf89f	1	0	\\x000000010000000000800003c1ea60bd51ee55fd1b06040a1ebacf7f455bd280d6bc0c6f64ac63c1c966418a6e86280d5541f4e83114261cdfa93cdd3434f6d9e509730382446ac3ac5fe079a83f7a1f564a3fcd9549b8fa456a19de60bda0b4f8aa0b35e38f54e66e9fe96d65ebc926eb0f05e0c1fae6e4aed4cc884a5ad5e741915797f5c66c0bbc31b6fd010001	\\x31bd6a0f80b02a5ba6997cb641bf04eebb96667503c1ec6f53441061ba09fd5878cccdf383b0ee6e5a2137b369a4020cee5748c0a1d5dd348f51abfaad77320e	1660786288000000	1661391088000000	1724463088000000	1819071088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
155	\\xa751ec7bf355ca5ed5f5b77d4b43082d4f4c5032e42dcbfb9a1868519d8e1604963592829a88aa0fdc06beec418dcf7becacf7312cd551b2ca425d9788c43d0e	1	0	\\x000000010000000000800003b014e3819ccf2a0c261ab93315d8d8fed0bb169ad24881358207d1a6d1e10c5975ea344df26c73ab7530317701249d4d9eadda25396ac9ea9ffa11efac3af4eb2989bfccf2103a179c475b77a7c6bc4ff3ea3f5d3309249a69809cf306405a1c0447e579517bf3c3f989c1b36b65ae9f646800f50b616c8cb9e4728c07da8363010001	\\x6890b4834f27ac4426ac2eaaa4876b0e0200bfe86a8d58db305eaf29b24c0f05cb8007f98fbbc82b45492783c224486716fcbdfdbd01461971d79b0f07121803	1668040288000000	1668645088000000	1731717088000000	1826325088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\xaa813066b605d067c17bbb1e87c6f562414ee89a94d677fa2f072094c6c27ce99b31802a7036f4d12f8a62bc13c00554e55d35c84f27fa1d61328bb6c596c5b4	1	0	\\x000000010000000000800003b76b1ffb55bc5311317509d0b9714ded55b7e7b1994db1c91ab4f2bdd7d6d0878cda7f30bf0bdeb3d38de48f68b387fa9d0d0446d10fcc9f01609a50caab98f5985f1c8ff868a79fcc76cf1dc4c14d8d5e195c340a133031596237f5cb9b6c487f6df93ee5b296ed49abfcdd687c163f1d12dd1d2c536afd74176c0799542811010001	\\xaa335da9afa1b974d48db80138704b1578bfc7a245eea5913effbd8c37559cf7ade3e849c1d1a365feefc05a8fbf35c6f721279af2b2dd90b899bac0949b980e	1668644788000000	1669249588000000	1732321588000000	1826929588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
157	\\xafb1a7df6d61bb82a5259d90cd27b889ee085f97073ba79137c3d0878a15c1264e1531e52d623a839bc69a20ac537ff95c6f37e79156c8317b9bdb2d04b35ce9	1	0	\\x000000010000000000800003c8cd88362bd2c4deb7c67c4f9eef642d96a8e4f8c140d93b06b3c9441c52b453429a3834fb7b1d7d106137fcfc69302109458219ee81220e243385a2c3a66afe83b114aa3285a60e490fe4132748a26e89e88914112c986741d30ecf844b755a6233878a10b365cd2f89da8de0be8283cfc1f7ba01aca37e49b35bd064610a43010001	\\x16a892519f38492d335e4ac5faa75b482a1c1d4b4563a378f5c40e617444b3421beda2dbde565f232d1aa1d3b4b79cfbc6a2611f14607940caab964e28549f05	1654741288000000	1655346088000000	1718418088000000	1813026088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
158	\\xb6598f7481b0049bca4b8a2f00a4d9531c090854ae7c9c8a3ad69109dc075a3aab95e8864a70d128c3b4dc9f5d626e07eea28e726abec16ba3ce459f634cbfad	1	0	\\x000000010000000000800003a70490b776e129e39f4c9a0aa70d5e55c867b63ed8eeb54241e5a8e6149c4a1f0b5b07266aaaa641fbfaba610ee0807780e31f7ad9c89a7999bc539ad814101960471637eac37153401bf3395c9ec68df84853aece3a295b9e935bb877c34960ca8030b9176f8ef1cc235cea9688a4721bb5f6f9901b4f82176eeb0bb02aaadd010001	\\x58ca5816e797ffa11d127b83813ebd910fb62a17f87025295c5c45f8c5276ec9c01b62dc83d0b77e7bfad8f4d6d1210098762ddefe460b316c78eb0806821207	1675898788000000	1676503588000000	1739575588000000	1834183588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
159	\\xb8816bebe2aa01d3e503ff4e6b8a8b0795318077c31024eee4947727ebcfbfe9c27cb9eaf1c77f8bbebd9baaa9afe7a33dae11c391ef9eee8b2105b8b74b286e	1	0	\\x000000010000000000800003c1338064cd102074eee311597bd2b31275d56c081d574a162af530353d82b86cb08b4e16777bd4a24f72e2e871862ba345cf70c9a2ca667df7c4373a23175c04fe88a8efa7d66551b30a1b2892931ef9e5800d863237783b80170e581ac8dd86899d4f48f7d093525d354a0ea45a8ee2447aa7790fba6fd59983126b0e2664dd010001	\\x82995a279e588cfdb7554c0566d359277d843747104d7ef610b1a324795896c00fcb27f82b8b52b158701f441b938e76f277c8344ba81a3b21c522062ac0d50d	1648091788000000	1648696588000000	1711768588000000	1806376588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
160	\\xb9b9956564094c642f99dfce8be9b05ecfb9858d10ea07744babcb3569d4e0fec07298c8d10754a77dce774323e5b59073c52912eecfb2cf0d987a1ec7166ba0	1	0	\\x000000010000000000800003ab395b197b7be91cc28fe745d5999119b5f8660be33dccc2cb5591b6fa3ce5cf321ce41d77f0172166c1e212cd590bb3a33b2d9489a5a150445465f449e88d36f5f8034f7b6bf3c0817ec8c315adbec990c069e909d28021001b69d3a15b40ec42f62330826df3c9949cf4e61c501e62edf7656d8a29bac02e4192012afb8129010001	\\xe1f9b9207ad6db531821eeb340845cd25fa03302ebf547ec95f3eb9cbc342273d23c74b8f4cd0ac00e2569d88cc4115ce11fd46fbbc744e4097ca1d2ed00750d	1653532288000000	1654137088000000	1717209088000000	1811817088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
161	\\xbdc556e0122ef07aebfbe927e28737ced0e6a869c437ed71d365887a049c3d7b48fc4157bd8c39a9d6f8d8cb5a8c5fa8d8f1bc92e210803f2d64100722a72136	1	0	\\x000000010000000000800003d0ad65e2fc501531ca3c0024b09f56a3ea3a7cf5283c776626532b2006847b6d17627586bf9fd9193780274d03eb36daeb7d3f9dac0ddb0f985a4aaf8349faf9584ca97270d9c1e3264c67c5883d1b473ce228deb2c7158dd6f27a8a72d6ae4b8c94b0013ae2426c06f67d04b48d8cb5b32c68ba61d1261f9d5cc6084aba7339010001	\\xeb55739857f696fd4946713b9bfe34a1d5f305a74d478a51a167da6d7b3677379058f2d9bad58bda099562f90f759101fd2abda0a0f137c99158c249c30b0a05	1658972788000000	1659577588000000	1722649588000000	1817257588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
162	\\xbd7d55dc28ff7d8c7220b13bcbe3fa7b4943a9e68dc3f7a9b6d38d84d749cba2d3836de43fbaf896499d59209f13201afd2f2750c249991ac0641a0f2d3bdfeb	1	0	\\x000000010000000000800003bed183b2aecf52db74d5fb9b846adfd350fa3bc48ec37d4187b196735f5106c681ace688c2c686d1a858f6adad49a15e61a6478bd8ad885f0399c69d2ab46fa50a599c5e499f9742fccf528bc90c1bea782f004a43edd36c69d6d219ccf40cd555a07424578d43604c3c644115340498cfcf183eca24736019e9d26beb3d6a1d010001	\\x8e90524744b7e5ae88846a45f814b71a09f2103a3defc61a5dd931aaafd3e96508e1382773f8e1a42ba164489c914f8c45220c4b4654d51cb16135617a622802	1658368288000000	1658973088000000	1722045088000000	1816653088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
163	\\xbfd90ddac31caabc41fa5395627b9899f097b447570fb89431d44429a4df1ed0bc614ed81777a0446553de4004a72a23faeb69158c89b884fe0f019244aad50b	1	0	\\x000000010000000000800003ab04e77e0df3032377551d4d89fe6f02b7e7a6b51d9ee1297f71eb8f26b087b9ba25edf83beb26ed9e3956f6207a12c5fc03a55d6e1806f6bf769c57b83bf13d76ecf706e3c50e252dbaee93295afd979b55335dc8a02c07fac1411f6a1a35a93602afc25a3e731ab86fb0d9aaf6cc0c2df4031a772c20265a25e4177c29af5f010001	\\x645e48cbdbd613cdc9a5a3f816f13da9a55eeaeec3495ed47593f23249da876cb6038c604120f7bc77f430baa8d3e0781e0f519b099c5963412e56f9b87dbf01	1677107788000000	1677712588000000	1740784588000000	1835392588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
164	\\xc0ad4464467f26427549e9601c789b68423f4f3e423ae0ad5b8540577550ea2e877b086f64fa1faf7abd3729735964d265197ab36c7916f824080a20f9aacafa	1	0	\\x000000010000000000800003b2417e2c8c15fa77593d3f272e414a1ebd7947b3d0f216f062600b76566828b88d56e658261ff1a706609bc37198337e2b9aadfc83768edd999c6d232d0a26b662100eddb89c2c892144c1ef53a6c55bf68e08faee368c24412e92502423e7b4bca7e989ccc242c2757d17fbe5e20184afe3f6dd1b8f45938db47aa3a415df2d010001	\\x2f93e0060df96eedf371961c1a7cf35326326e490396c00ad4dc7185bef1edba6e93edba6140e75097e6484add8dcb764c6e0bca13c21567bcef21417b28a106	1658368288000000	1658973088000000	1722045088000000	1816653088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
165	\\xc21dbcbc6cbe0dc8789695e2aea157cd780ca193d328b183e4cbc2ee92ed4fe279feff96286126ebdd01e5a3d4fb497db0b8a6b9d6bf80dca91fa0adea090c8c	1	0	\\x000000010000000000800003cba336088a7a020c08f9d91de6416d96d6963806610fcade80814b5020f74483ff87b619a937acd275f0d1574f335662123f83e55767712bb14439d632ccca70ac6e79a4e538437a12f61c25f88cb4b1bde3ed70ed154f8b04a72698d1b707ef22d6e04424c06bcad07e122541a335750235cbf86baa14cd590e96bd1c480f2b010001	\\x3e8356ad901244a53e5007aa81762bfef7a57866b1a16ca21d16716a4df45f0fcbbdfc9d7eb9c367f8d97babbe4e96dbde1f6c1623e7078eea251fea38cdc303	1648091788000000	1648696588000000	1711768588000000	1806376588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\xc3e90133845646c47cb7e8bb8d04723f14e144a76044bd8ab5b231fe14d93350f7d6109c3011822a22ee0d5c5633d9264fa165260ea017344f3b8ce673587fcc	1	0	\\x000000010000000000800003fa9a77d58cb091446d551d46f1abd4854b374067fe88c1edb126788f50da3cd023c6445605e3cd52cbf5c1dc060eeec8017eb18fdba692d1b559d4bf0d93f691ed626480124889826a2930fe240886d9838695d0da885427220bdc633e04156c2076522ac195e5584b712c86aaf1d98a82ece0b1b5a7064cd6431f41a1f4f085010001	\\x9babda1b131b6719762c7026c3455fed2c042dfabe0e4c009ad91e4cdea77a6e08800347c7c24a5f6b4ff0b48fe5ebfa2ca33c48ac61a22dfc025e2e642f8009	1651718788000000	1652323588000000	1715395588000000	1810003588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\xc4ddbf586e3789b17514f1212245b3ab2d12b977d5c02c02bae00e9cd2c7b0a7a0eb2727aa42698bbffac1264e847cd09eeea99051b5857801534a1a98442e74	1	0	\\x000000010000000000800003b8b625739f6eb05bd2f77fae0a2e25285d2f25923ce9fe0c4b1a7d00179d1b9ccfb9b6636ac799401edbc13b43a82719fc6fb8b4423995f7fa08addde4ccbea9eaea2bfb6a9cce7af21bc1f06c52f3c8a064ee181af76e72a3ff4b6198a65a51551cb5df6876f1e25dc8cee2bd4f5f241d525ac4032f5597af857e76bfdbb89d010001	\\x56aca1b3b384f13980bc59bfaf9e030908366cbee932eb25ba55ef3f2835f63944d0b72dfaabd1995e91674bfaa050af28477f4d1a29847ee76f65e61543a808	1671062788000000	1671667588000000	1734739588000000	1829347588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
168	\\xc8454b8e3f1cb9bb09b144e93bb6d341355387a85c00404ceb4001a6e12a37cff13bcec16839e70947c8ceace226e97b927f85176835cfd7d1c09a4a36a61230	1	0	\\x000000010000000000800003b7f9e8a86bddca1939df2342a526496fc61c7b49b98ededc029aee43e32041d45a0d34b28039853732e136b139094f8104b6b8473a6b16f29b8585f7361ab6d205c46337cdba65f1bde5094be9f86c44d5b48fb5081cf50527feceb1a4ed6c9c45a23be6c595b4de7c3ad70d661880d8c112ad11ee79f203bd21b487a2411d33010001	\\xba24c87479fae6952d523abbe66a18dc6c5c36b92fa22390c77a645438729dca061f969c992b8fd3f2491b502963498cce5fbc8772e972cfb3f6c512899ee303	1655345788000000	1655950588000000	1719022588000000	1813630588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
169	\\xcea17c9ec395ccdd5d10b524de2fad18f71bca63e93a893fd96db3eb7519f77203c9274d6d70a5dcd3b4d6cd621fad3cddca218e01ee5ab722a6e6159022a34a	1	0	\\x000000010000000000800003f1a76311c2a57bbf7cf2a9f3b9a950e1897cd7b6cac89dc2b975982cab6b42ca1e542bb0884f4680890784af6e7afc2a63ade73349a56d083e2017555e043067e28e9b5de2cd06b3c2ab60ed8f838993540d621e9de1adbbf1d118c42ca71a1e47ca6a5455d7b48b22b8246480e1a44650995a3beed7808504194b40592f4a39010001	\\x8bea4610287b6017ce07048e0b1a4ad89843115d3afd931034bed51968aa87f927b0ec75815017b41fea1ee1561fd94f26431efb38b66416afc8ad410c6f4d05	1651114288000000	1651719088000000	1714791088000000	1809399088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\xd355ccb80671c93ed116b47021b97b2027861d253d4ef850f7a36261881dae57d4ffc1999d58adac46612b53926a6e06a488630caba977cc71d86f1e582c8e7c	1	0	\\x000000010000000000800003ac55e149b83e7d41d71ad6f03a6caad3da0e68137a6f64556fedda04c2e0012bb9345712166dd0297ef997eeb2f2b783144747310a303aa002e13611ea2f815b329b92cb0469ba3668dcb35472cb6f22eea2fbbd39003991b85d1917f5b96427d00c183d81a7941c4da74cde6e34f544ebb394e541f59bc262dafd7acfcb4751010001	\\x573b4f7c9b487c2daceb2f4800f4d27e8bae5b7a7f7d7a5b4e20e97a37c025e43bbdaed19401477b7412c16a399111a2cb890ecce5775638bf1117ca2fd04d05	1674689788000000	1675294588000000	1738366588000000	1832974588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
171	\\xd4f551464fcc0a5c3610605aadff82e58416758bb680171a068a9790089a1153d3144d559dd3488f940ee12c36249d9421ef420a89496943567c48e6378cabef	1	0	\\x000000010000000000800003b02c6eb6623a56ded92c9d94dc2d81d5178798b14efa8e16dc3692e172cf310fcf99c5d4feec93dcf6683e09f9554e83a2c1ffe8993568d54978d8e4b50a5d53020bcc8e07613aa5f5d36a77076c356ac86bba4f0ea87882783a2b57f384b942cf24a4377f172b2d793f94242e0f513edb36324c1ecdc82ac2b35fed6ef5e93d010001	\\x7c540f5e31221f953910d183cb805dbfda8eff112e6e10955da52d6b42564978adf9376d760bbb6e71dc447b164968ca2717d2c95d436e689d85ca999d8cbc08	1650509788000000	1651114588000000	1714186588000000	1808794588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
172	\\xd525945e8bb16432b15a7be8e31d5ff38e5a0dc9917f44275707fc430b0063f48e64f918b46d3eea1d127765ae52af9c24ef31e18540dda8a2e65ae62d5ddceb	1	0	\\x000000010000000000800003a80f66b66d0112ba0d450ca78861041ba0ebd1b7e3e474b7cd8e31f18c6625d14ed9c7d9281ae302064218d7e7b1d733e7bed0b34f7fd628917e5666ff8414856aae8cee01871e96646db6e064cd05891b71d10d1f79645d9c5c2ea62311530ab86fbef0dd9670e967bb9bc6968ee6ad3c9f7a35c42943f91850596edc0e792d010001	\\xfda42bb72c9168c3ef2071a8f67e7bfeb36f972358a582fbe8381926c36e77e4e7bc9f268e752664c0f13767fa14082871ca679263a78b3a67770620e50ec80e	1669249288000000	1669854088000000	1732926088000000	1827534088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
173	\\xd731796e209407d4ce7aaf11e8a0d9b2d3c337a5b563bf805827581e60cace85d4d90229e0de67386fd7f6e8d6ae1bdea7190aa6670bf994710c8dfc890c5827	1	0	\\x000000010000000000800003adf442ab9d896aa51e463ad08c19f97d6b411047f56f3ba61871d1432fa4cf140a40719028ccd5730465a098fd03869aad6dc6a6e93d710dad09ccb6f66e2472d32374d96823e3ed6aa5c5be8d61582a024e10a256b5187abeac176fa48f9d69f5c4a31a7ae9d1865e8df285659aaf9f2f2925ba83e0229da50ee2a966992529010001	\\x449a5208fc495fe95cbb0d65f8368147fa9b50459adde1198199460bf6e3814adb9979b5d821275e17c91b123fb0978aaa5ffa115d6f57ff8d48ac027b564a09	1658368288000000	1658973088000000	1722045088000000	1816653088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\xda7ddea4fb0f1f480d8237520207bd8d6ba568b9eb2ca28de1a76790644a5c50c97a1ee4774376be2458d49d235a709f1d294a237d9348297e7969b0633c0756	1	0	\\x000000010000000000800003b677fd78bec270cac2a72f7bd4ae86040930e44bd8e6505a07bb8857ffb82050535d9a4debded70f47775b07ba16b74f38b0bfef1940eeb334a14886ef1f1fd3d64e83c0e47273579c8c1bc20e062d5b131884fd2a92eb32def9fb0b1a06bb52f53b06126624ef1b37805a1eb7fc3d56fcb047c4449240121132290e5e072b7b010001	\\x5bce644ecb6695bdf393043cd92f93498d9bc4ffa7d89954134eac3cfbd45852c4715eb6ff2305e7adc96807b145c27e783512520bc6b3a784931ecb99131e08	1668644788000000	1669249588000000	1732321588000000	1826929588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
175	\\xdb913f5ac562c4d1a243421c13cb057fa28d91b223408336c8581233cf3087db9fa0408524e1a8f9c377db84e6a7919c48f05b59481e2b668ea50ed8dc3db10c	1	0	\\x000000010000000000800003c3d2bef81767ab793129f414b91bf68be508969d92139d88b9e5012cfadac4ba4d2d7763beb0eaa63c84f44fa01c279c274c7e8f53b555e089c0c3ecf50dbebef6640ed2927f40b6319032fcf05adf8d82a2f37c92ac1b1e64d36ccad3b31963f2cd92d4eadf54474966c18d09295fa6a317b5e4429ced6e2cdd77e2cad4c8f5010001	\\x6aeb89f35539b0622ed0b9e5564aa31ac02a8ed7d0c89d45979f2cbb153a6fb6858aa67a80973fb34667918ec786d1167cfdd246ec8617880c63b0e66ec2460e	1668040288000000	1668645088000000	1731717088000000	1826325088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\xdcfd032132b405c55fc1b4146dc1bad984739ffe1916bd5af586a093d3597c37a249269518e7861ff2f74419243d64d425734008be1edf6c460f99b150416ef4	1	0	\\x000000010000000000800003cc9d5cb41c07b905948e3ad9463ee196da2b83c8def5655214e526cb22e133fde5814bc787fe4642a9f79a270754844ec0c2d907a321ddc8c97947bf538e636109ec40624b1d4a30829e492c3599cd7a7e32e9835f4eaec199db3922d354a1d9d00d3c5683f504fa83a36990e6e64f214d95b30bab683c4619829a2925bc9295010001	\\xde6b09d8503790ffab1531e99accd9946e9909668e6047a42f52bc13331f78aea9c5e60db68b3fcb62702a3aabb1391b0cc3539be34beeeed914187c8e398c03	1649300788000000	1649905588000000	1712977588000000	1807585588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
177	\\xdda1e05d08b6a0c619d25beafb4d0eaf0ab98f75dcdd7fae9e81c22ab4dafede43592c97f10f28aa81604fb2270267e31a66f9197cf9eaa65be3742c57637c5f	1	0	\\x000000010000000000800003dde5536e30961ebf256cedd3b65ca00a3a46a8e1068d3002d79064b93144d8898937fe9f1141d9388dee077a15f6f09d4378c26faa6c8458b3c7c58be00286917fce8b276e26d8ae4c5dffbcaade2b47ae0a9fbc334d671732391c72e03d2f399e7fb9aa0c9331f26a6125f37af6ed2f43a3d2b4349305237f62094cce7c4e37010001	\\x7081d5a5734dc3e0d2586cdbecec97dde4d7ef7e0680516572cfef5e2027c30abe32528f4626b5055e1ddc635c3349c968304ab821ce375c9642e1fef3575b06	1660181788000000	1660786588000000	1723858588000000	1818466588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
178	\\xe10d0684d9081e725544c1a0252a21447d5c6012cd54d49f72fab8fba94da8ee8aa3dbd6f611d07d4122bcb89fc7e2daec821c842fee5b5524a00d81195ef3a0	1	0	\\x00000001000000000080000396724914fa2baf74497fdf48e5aaae1437dd03b7ad5a47eee9405527ed406bcfe5055335cb88486dfb434be6d481e8df736f402b5d748175652ca0cb20513e557948c223bdafdcfdd7168288b87b53ccbe2a6b683b1b00fc6953c7b13abd092eb921218efe3715ed3fd86cc59032371e95844e255f2b051870bb5883dd9f732b010001	\\x41863ebce2fb8977b27a789789fbc76fdd8afc1b42316f3007c2c1430104f90c86009eeb7addc69b730ca82508502706ed43a0ccf5e2892848d918dadde67802	1672271788000000	1672876588000000	1735948588000000	1830556588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
179	\\xe10d089ce7e0014af066189175805727d35dfa27a751b8ca5b6ca9800430bf2df1e181eb6f08d582bd9816b1360e782a65ca98e5ec71d95fe3ba3c393ade9087	1	0	\\x000000010000000000800003f7e489661b6d87b8eef6bdb4224674e0fd362b5028a64479528414a25e4faeb6d5de96c56e631539605801225e1b8bfd5b4b83c2d38487c2f142703e7cd912a789bf97945b4dbb08798233105afe8b09513b1b36ba956f4f2e93695363f6e1556b52e5fe93998db7901e694669c3d2dcf8d1a2e8506240f0f0e132ab746a2421010001	\\x2606dededc6ba035185595798d3d5b240dd1ac56d383450b50faaebe0e6016fa3f32c73c8ec285f3ea729bc6a1f005612a5be37fd71af19ddcbcb38fcecee30a	1670458288000000	1671063088000000	1734135088000000	1828743088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
180	\\xe151f387195e80dcb1e817f4916b3c6dc5548f0d0e0c312d09b330ddb17637b20471c619b6205d5367d66921861f6cacc9d103c0cfc802e0b8c83cae740dfacd	1	0	\\x000000010000000000800003d6b9293dfb9881839912724f07942ff97e5a5b83b1ce256648f8e63ef3ca63927125722174f678ee577e2712516ebe7b98a5fecf06b9c49dca2ba0415a8f0f8596beee1f19ce751d90ca04b45bd4441af0d026189cb8fd25b635757958b4563ff4e41dc6cdb3f2d0aa72a0f6ae5614248d194cb45ecf176b29ecf5bd3ba4dde5010001	\\x84fe964f8aad2d39ced8462c337085584109783349633c23e1d5f91b1e397cdcc603ada88eae6ebb1a88cea8245a7468388f9420774e490a01543e4ec0f9fa01	1667435788000000	1668040588000000	1731112588000000	1825720588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
181	\\xe2e5ef55925eda6526cb7fae2c486d15e4ec0680400d5e800a9bf7319b0a93440cb219876d0e0d6016070c9b6a85b06e02f29a5fa701210a87973d1c75216464	1	0	\\x000000010000000000800003bd2159f8c11a2819fd8dd8aa4bf0e590a2be55343f4c2a65f8fc7a109ad61b1d3f22a157e663a9ba919232c751c6ad25468d6e0730b9c0a31c235762b48ffaef53f9b2fd9fa31a9f9eb4fa367bdb68af6616e5999c9e4fdb869a2547166f5a461f6ed561044110f4a345fe6b86288de2e71caf635bfd75a893bd6958b198da3b010001	\\x817ba747387d683618a7bb0170f0985fa2a3749920382650df25e20fff3053dca74a5e39b40e076da4573fa5b9ab6166cd280b745479ddbb6e3291b2676edd05	1676503288000000	1677108088000000	1740180088000000	1834788088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
182	\\xe64549137860bee5f44c25583aba4f1d96a23bdd5bf14daa4cb92d9409027cb14f562d8369f7532f0c2b5517ad130b24c976eae0e660dd3ffc426fa189d68afb	1	0	\\x000000010000000000800003bf649f5963f67117f0da5fd381a424ed172f701426d91b475e105bac31ee3cf96ea27527a733708e602c24db0c0e8aaf1ec737955674696df26ec7e03714b7d666e76f40544de5b878a4dfaba8d2f1e14c916a593a8498c201581fad0c120df9a872e41219354f673d9369bcbee800125e0d34c097a7b20db0cc918728f9e5f5010001	\\x84f8658e1ad972a0829f34ba0a7ab7b71c77bd0a84990f9a2388266e79782c43fb0da16f34f6524d400aaf6443b4c3378224f00182a7e06e578fb3bbaa4e8503	1651114288000000	1651719088000000	1714791088000000	1809399088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
183	\\xe7ed04722efd05047f671a1a919ef5c51ff653cd6883248e70748d5b16f6b2885508acb01fb07d4d11818664036dd1cbf3e7a6cef72c79199da2c26eaed76b91	1	0	\\x000000010000000000800003f33cd08f7f8f957d0122f420c64e42aa1b342f6825562e97bb092a6a5d39594fc496790ea828614a5704a6676cad8857d059fa4a556e4eba8363b4d8dffb32aab8923408c69df5b3249b880870e2bb67a43202dd0aee7b3e6045418b08bbf2e463e25cb15676887d8763f9150f6a88164057a6dd9d9df330da057d24b8a444fd010001	\\x098e4d5eaa03fcff37afc9da5c04747f5f4a199a25593141fef662faec9b9fe7b20042ec81226c5942702053267b33e655d89c0a80971713a4d452693e31f101	1665017788000000	1665622588000000	1728694588000000	1823302588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xe819112f2746a2c1c45a1859b7ce551e493c6fce6a8b1b34d7ea2321792c9bcc725b33b5c86061acdd58de45cc092add718e3f8bbaa224371032ed37b71ce11a	1	0	\\x000000010000000000800003d20cb1b7b6ac55b2cecaeb1598562d089c5fcd97b2778e40611d2fed453fbf65c3290e19456edb8f49fb5b90970a2acc65ade9f41c85f059d25c005e979c6f59d1d201c208f4057411b51a526697fff981196e044f49594b72a42333c65466ee43700f7f5513a644976d033420ef7aaf970068c94cda14b01b3d4b4adac5ee61010001	\\x05e30d00f0074bf559623b44b5e996b92313c1dce1060120140413f617a1f1c83d8fa474705c417b8633a20db3692042162e9656dd4883ac4707c930e6208503	1666226788000000	1666831588000000	1729903588000000	1824511588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
185	\\xe949286dca9503e8a2eca0b98ce43ea16b0d91a169e58a3f16ee87846514cdc3e6c869aef9843fe8cfb28631dcb918137bc1792132f24909021cd73104065933	1	0	\\x000000010000000000800003affd3690d8a43e15b364612859a1c7e475f91a9f43419cfb0f2eb30cd5ee63665e45e42632602f64976f515827178235934ff934ac91762388aa20dd2ff8798bb8ec5ab5c9464f89d935ac38c4e97d191308465e9c199a967b6971e5f5a9ae42e5c251360bf58c49854fb1b484c79f08715e40903e2f6918823f58dad97a0509010001	\\x2ce2708e87ed675c5a5f736f0fe124ca23cb12db08e087c20ab672e3b986a30024230f8a9d6504e949b959bfbfd7815ff91d87e5ee1f00dfcdd8cc2332df7206	1655345788000000	1655950588000000	1719022588000000	1813630588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
186	\\xeb8dd49a891b1a450f0a5cfd1814f525482f49817ffc16c92bab77f37bf013eaf4af96ae444ccd6a6484ceb3afac9c6509657a6a8f5b1c2287ed9285c0e2c2a0	1	0	\\x000000010000000000800003bca0b586209869edddc2833b35fd1773aad01383f6a0ce4c3d27a41b8ec8baf67208107695d8b898cf0b3a3ffc1b8b4fcf9724e583882b14a7c01d81d684159435a96a81e1986e7a9f9af1ec0a644d76d2265b6963fe65a281e9ade4185bd4e00717465486c679f45c8b83c9565919dcb97efbef23e69057e4045c99919eb80f010001	\\xabe6b9f466978696f91e542186241df84efab2f2c1a27f31f3a22704148f365588f80991bb9869d1cd679279b10fe4457165611a16b21404d46ffc1bd7fbfe00	1671667288000000	1672272088000000	1735344088000000	1829952088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
187	\\xedcd33e023278de61e4c96668597b3817d5262c2aeadcc8339bc8e60ffa29e74ce134ff95f5152c537e433121624ce6e6278ec87a16cbf215894787e172de4c2	1	0	\\x000000010000000000800003ef2ca016e176c9c8b9292bc1163ee57a96058122c0e171c8673df1e79ac2383ad247fb16234c7db73028a82a4594c91952806fb45a25aa694563b1d9bfd5c596c348864401e0dce88ab96538e4d8ca431db634cae14d47cc02e27b2a0d2ba010c14e3ce56aad80545f354f9d15fd7ee51be2ee2adfabe10b7e0b18a4fd3f407b010001	\\xeb94d4a6de13c846ccf727ae68edc057dae8c1e2648e32bd4c3e471d783dace725ad0d25eee5c93d196ae9af9e0b40855af8b9213193ebba5c10522866324404	1669249288000000	1669854088000000	1732926088000000	1827534088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
188	\\xef85f2e9838d1f3cd50219b2a527d3de120a0e5fc1f009fee554db77458ea9e9aecb0a2838f1e482f86eec1c8c40f0163ecbc19ab7cb70d7e1b8821a4315b099	1	0	\\x000000010000000000800003ba1403023ce5e0862208703c4a7c89316cba26c49508798874fe199edb085d1a08ce63ba7ebaaeb1f3ea2319ae047ca79ae25de465f80261178193fcd3e86513255b581571d9439a66c912281c4fa37842ee3349bd8136a97df6fdc360490a490b4bb4a7e7f23e4be9a411392b3a2488b25d0d85206f089541163258b92e26c9010001	\\xe9e179119681de317ba08eb7f1ee7139900bc81195ab99b99de7dc0ab211e2e49f868b738ed4f9ec2bc8a41b079ccb0f3b6e324a2da8889752721c7a9e5b8507	1671667288000000	1672272088000000	1735344088000000	1829952088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xefb5050de88496ae16322eac71bb10f19c99e8ecaeac0b77aa9efe042e74f714de34fd7cc88ca9364380efbaff01c7f1d43640840540cd53d71671e827ad11a8	1	0	\\x000000010000000000800003b78dc42b7d36bd6d12704d07060db6ecc8a3bfb5ceee2fe141cc0ba456df1d6b267b9a528fd16f28d80a01ea23314300ee1508ea399bd5616f2aa5e3cb6acc9a579363e2ef106822a4e1dcbd2308c79a670dcd14a8406a57cfffb3083bc6bf6bcb7504bb05bbf07e6b6a81a04b15c1b1f9c1b0485826bd30dd15a1c0255fd66d010001	\\x569023a55069401156fb57ef0a9b5f10900f30cdad6a726e2c1e643ca19dbe589b8a9d606a21d0ab013fceabcd84c40b42997c76749b9c0887cf340a75ec070d	1669249288000000	1669854088000000	1732926088000000	1827534088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
190	\\xf0999aff65aa32cd2c252b770fbd823537b71bc1a959185981f8bb23e715e749cfb54468b4c1b5385bb044813f97024039efc117b817fa5ac20994119a698ab4	1	0	\\x000000010000000000800003d27e638b812c24457e4b9f956abd7334d7ae96ae596eddb9cc06326045486cb32a7d9c5cba1751ff8f18ea0845cc6a8d2679647ce1f875bd0f0b40c8d2b3ea42111fca4d2b89a7b88e87f44c3fe1ba772fb5693be533bb18480662ddef59dcf37aca7dc448c0c5bc93c9572c024addb602ded5e44384f7ffc5ade6a8f78d4af5010001	\\x10f33e92f656322c050e32467edc968b25ccfbceaef20c0526ae839648d25fefd6cf9809714feb14c11cb74341290a978e7dcfd2062920440bed7df0e2bfc20b	1675294288000000	1675899088000000	1738971088000000	1833579088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
191	\\xf09d090825dcdce2977b341f153eb307c602bcffb42b1f2ae3633607f4c4eef695ce1bbb79d2dd65c26fa60f6160cffa412b930422ac97a4da990970c0bb28ec	1	0	\\x000000010000000000800003bc0254a90b4f91ff4631151e25d63f7250c6cd0a49c1a85bd9dd37854c603fb8a9e357c6b3c7de25f43efff0530b9fbc0a518edc0a11c82aae93ff6dba420f1ff94ea720e452369b5332a3e6802c27a78f07bf1039fb47f046ba403e55e2d952b4d7131dc0fd93e0a7b6f480ea457c1d90eafe05689ea7080147a092c2c3759d010001	\\x169df39bb2b61a3ebf2f25c1da189a3a82b39c1e20d20bdc17d6aaf4ff40eaa98f2c8685de6442031bfc7db2e3dd58ae2ea08a81e031f078d6ff792dab6f9609	1678921288000000	1679526088000000	1742598088000000	1837206088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xf1a9149f207af9ddb2a11e98891fe16d23379a46ee4b53954bdf7cd6bb5e15c9df76201482d0023666fb111c9478d9d2a6afcd2dabdfa7728034655eee9fe12f	1	0	\\x000000010000000000800003aba52b64ef61e5b07bf54e5a054419749d65f7203deb33ef624c2ea5e5765b47610bf6eec716cb2142d81dc6a2c49dee5211f742071038dd78471f466475eb8d3a5061162b2b6467a693f0254d730194fabf9a3cf5a69e346f88eda573f449e2d85b38209b5e59d88ae53eb0325fe1fa02210eb2fd24fcb0dc7fd1289b3d0671010001	\\x94e768c376489682caba8bba4a590618e62c29c15cbdc7f71be845051172314d5747a0582e0de5a6802673c2091ed834264bdfa99f0e16e94bca9b0996f9a10b	1670458288000000	1671063088000000	1734135088000000	1828743088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xf27176cb24c502a8e06019d132a7eb734d66793424e1312549fc5fe9f55631b3475878ff4aa65a8f7786669a16675e9dfa15c45c71e2fb117ca6410f1f666614	1	0	\\x000000010000000000800003cb919cebdd2a56782a56337cac4ad4fb3d5611c4479e4b0ba0fa6501d6640f2ed6e3dee140f8fd37375bfccfd1fa5ddcb78464cd922f9e8106a4fc68f40ad7224fa923d1b8c0a8bab1a8de97e67b31a65f4faf611b9b723c0fd20db1cc1a4a0170c8f4a28c71696344eb3f1eaef91e41c47d4c06eb54cabc18f1972f7af0ee63010001	\\x6d9efaace3c7ced09b474a002d182c87a521b131ed8c5b195aa8f7b5af6cd8c32f5d63fa9ac5495943c88e58dacce71951f65f7366332adbd46ba25c3c83100e	1655950288000000	1656555088000000	1719627088000000	1814235088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
194	\\xf5515f28d13d54d5266d15e18326a67e0976e0b53387c5deffa08e1ec5d458e6548ff334b6287e92f62f0075b34e0555b4e8bde62f89f2a3ff652bbfce024f8a	1	0	\\x000000010000000000800003a46f94753754d7d5e3d55f5f5d53cab67b387f45508929f8af34317c9f48fbecc3807be6612143dd319390c57f3774f7589e264e4f565270ba55d5feb544dac3186a3a4ee56841a7def9596ef84694dc46459d5380bc92f1eb3676af2637acb6f219c5a5c29016f9345cefbccc9e8aae8108fb7ebe721e7e54ca09201121d693010001	\\xae67a71d7c7435a01fa7337c2112ca8c0a07edb7ef5cfdcc96a63718223626c90fe618583b843429cab6e016ea13640f43836372595b42ebe89f0d923831b503	1666831288000000	1667436088000000	1730508088000000	1825116088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xf9b9189aad5d8809f1c951edcc8a61a01bda52c96e579647e39e97d8be04a53fc2f4438b4b915f038bb435c75696474ff49a9de8e1b65ecb3d774d54f9d17567	1	0	\\x000000010000000000800003b578f8887f6fe2c16f4865f66c8ac78586ac947afcb6120141f244002d1176a971aa867d0f9333bb2bee945ef8c84632205652ea0d2c5ecf2e56bc504445c2c2caae9184158e610843d8e2066456f1b9b9ef26918fa15633a76121adbba05ee01203bb7eb846fad9dcddb4c2bf2eff2fb708f0df7344d0c1f91796a71d8e8875010001	\\x6e5b9f223da596df06b4001f3014d60c50af394ddfd85e47c5d277e81c17873e4c2a383565f456b7173baca1b1dcf64101f1eb7fa8b3487f03797b721128a209	1657763788000000	1658368588000000	1721440588000000	1816048588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
196	\\xff7519b54eb6110265f1ec563ef1a9a061330ddd54019209c23476aceb67e91452331be6b92dc46ee2a18b82be25c20e9e6b0303d57fa35b33c085b46bdeebe9	1	0	\\x000000010000000000800003dd1d43ebcd5ac14ca9614e077930026337730942a08eb433e9061833ece4f33363dced2482863a6446dbdb44712a81f70dbcbe2fb0a2dd2d575a1d747bd72f45f16dcb1ae20936ffaf48971fa82c882e3c8a116edb91d0ba0fc08a32ce92eefcf8bff513c0d9aa74e29c3f84aac7e301afcf3724cee8bece7c49fc19e4a0f0d1010001	\\x2588e43312f4c1c4fa7a13360f122701d25926170077eff3bc3c4e71c0d10c32cc32157ea04fd5154257efac3686a533746d4a82a007ba6b8815d042acfa9b0b	1648091788000000	1648696588000000	1711768588000000	1806376588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
197	\\x018e5606660854261380b542137992861a60bf373b753652184aff8129b601ba6a2fa9d647979d3198d44883b5c32c87a082d057f8b21df8436335fd36951693	1	0	\\x000000010000000000800003c0c0c379a932999dab79991c37538c297f0815ec0e3f9450d38339f453c30bdccc91e36b6fea5b024c0b6aa2713584b3a49d671443becaee68b0a4736289fa236ee3367b7765b9418ef258b0ecd9608c2a0863da1cbd681d4d8f364d38f38a911aa9b737c31d2da472822cc323a3a28421207c4b95212cee816bde476c285057010001	\\xcb1262c8ba12ba4a24082ec73353ca76b0ded7981c0c7a7929902dbf3f19a1f5bfc086465c54eea81283143fb248d19a13793cdc9aa8b50d47263204f4967102	1677107788000000	1677712588000000	1740784588000000	1835392588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
198	\\x01f224c9c63afeb6e5bcc1a636d039bc4c2cca250e337db9e8189f455c87d8ed889062f8a3d69f9489a8bf477b7bda49509d99f4591a3b12e653b05cd0660c4f	1	0	\\x000000010000000000800003d83e98c1efd7f5dcd13d5fa28946874c44c3432e8186a95eb4937a9f721fcc97d2667d1eca4d9037f3ec169cf788684093e1570f65fc9607d556c7a570689d285399bb5fedfcb32a7d6ea8e1074d57f794b543554215ad8bd67f2c595cd2fe426a099f863b11b6d5fe4e2522d77f6fe8aa010d557a6faae4d647b2bd3f1d4431010001	\\x676ee3c4ac2a38d330217d4f718215a8a0099565ccfe7fc2e03d1bbb985b0146a144a08c50e944c22234a81b8f52226ebf89435178734a7724777c611cd44e07	1654741288000000	1655346088000000	1718418088000000	1813026088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
199	\\x01ba53d9d8442e0aea3d1600a83785e45f2d6f93efbde6a2414158c2489373a4aea78a7ceaf7bd561a9fd861335430040f27e13abada499b02126e19bb446c00	1	0	\\x000000010000000000800003ba2ad61d66aaa098ff7ed3747b7345f640fe8d1ab3600c717fb2c7f5def3141ea8e10ae553a5dc75ebec0821bc33fda20bbfa8e0a4cf1148e8af687027f9076455df3cf69338ffb8aabfa0d18845c23c11d6ac3838cbc18276495f5af9ec3dea879013e494c792f458e3a94e3d60c3935534b763bfe62c5bcb4efb3798f96881010001	\\x4950b5213f59a15cbd535a75fe21cd6e8a2faa1ea9754af3db0cf5d5a4fe71dfb6bff75bbf7dac6d7dddef72cc15d458e3d04de5c8a9aff9cd2495b2a796f00a	1649905288000000	1650510088000000	1713582088000000	1808190088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
200	\\x02de967cdc25fd5c083ad836763e2dd605aac759d723167d063b910c482fa406e10552e472896e7b2b01ab2e5fea84b90bcf145e1486213125d53c37cad7d705	1	0	\\x000000010000000000800003a56e1f978e0839819935d04c543b575d2d0401fd8fa3bb1e143a1d1d38f4164124ce4b78bc7fde962acaa1e700dcc5f346f6c1c1268f7511e5a1df9b8c38dab789c298147c26dd509e4421d6cef501fb34540ee9095c400ce2544cfbe2dd79b1af5e9d547d06c04087a66aba9b59ae9a9a64237685e7ae67590cd5d185ea74ef010001	\\xc7d99c2bb3215c4c28d60d968bc5e8ef945115f14c15a12c91d4e0451a37a021de39f2294b189c7d3d8e7577144f2544a3a5c980c300face316d7eb014bc7a06	1648091788000000	1648696588000000	1711768588000000	1806376588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
201	\\x073a46ee65d2feadb3df8db5de9f8353e21b9b4800c9b2f1799fde25907c6b178c14bf9d2b8a62224c958b0dd8c99086ba74bff5939b3b13b38e067070e347a8	1	0	\\x000000010000000000800003c04eb6a947935fe805fa2eba6066e9647f15d747105af81059414f662343d4965a44cb3f97128ef8c863df6e81aa73d267406f7c44bc1641a606963a9546be6e633eab26490309fdafb13e0f6834a1ded01dcdedfa2def9fc5c609b03be00696627eb42997b73d7866e53491e0ce74bd0b72d9fbef8c707b2342c5f6027597c5010001	\\x432867177f93be02559b208d3a474b064b9c09fbb2fdb6d3ad06e7b8040309bc57dcb0bdbd10d4cfdf4ab5ebc9e28165561a1f24a2cf67d38833819caa454408	1663808788000000	1664413588000000	1727485588000000	1822093588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\x0ab6fe06e6559b264ac25f2f523687a093ef154607f42c685fb55131ec635b5836c44564625ee5cf709e5fd8c8040cce3a20312bc041086a4757a2cf1e245d5a	1	0	\\x000000010000000000800003e88c860f4b2e03ccb621a4c35b74ccbb1680a9a70c1e9770445ae415d6078db8ee0d79acea3762eab99572913f733b9ba8b0a5db676effcf5c08b14ec255671d79426ac5fe197d3c3874f751a395e74d4acf6cae4d192c2cd211535559b75db6d57c93d546891c7f6845781dad129f4ef37ec03e03f44d7523d55ade3888fdc3010001	\\x2b6fa41eadcb419ed66a30a2e412efba84009752eb14edde716f1e08408b98603d014477340bf60c3853cf30f7dd8f222601fd3b7737dab1228f92b8c41c2e09	1651114288000000	1651719088000000	1714791088000000	1809399088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
203	\\x0f0eaa672a07875c529027175fe5ec77ae5783b75e02506308fd63f299884f7e31865c84cc4383d28f71542a377fd30281b2450fc248f044c5b2ca320fc830cd	1	0	\\x000000010000000000800003b16d2e889cf609a055ff1f99be053c50082f9d118e464d0554be0c6fcf76f83f1ee79f98cb7e235c3d33aa217d344b282fdeb5c3963f7b02661194c48a158458df21530ba11b7be85c64355fcbfb919708c0fdc6bfa55257a70381db6566bfa498878718c5888e229ec2d310acdd2e46d7d255785d609b1ec0efb28accacb31d010001	\\x78737d0d4ffa1720884680703b1cec1a744497af93e0124b233cb1c107064f65b03e452d6ecdbb4b67c812310c76284e7103d8bac1d57107af8cece6247a6308	1661995288000000	1662600088000000	1725672088000000	1820280088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
204	\\x11068e31373c6d6819f8e06cdb39fb070d42460991923d5b3a9e292b9dae038d0fa883a3dd9386ea263323ee8240b01d77094a823edc522d15bb6a63c2ba32ef	1	0	\\x000000010000000000800003a0c779d978fed6da0488faa2ebf5097da7ac6d788ba51448e9d9a305848b0f4b3c1a2a721cba0514d2b726e07d29135072221cb758573535025e761692c477ae74d5a83779ce7512d44fd56fe26a392333e33e435f2c95928ba8cbb4b885879a320c413593cf48864f9c26788eb0244d94c430c3fcd6893dbdad947dc7d2bb3d010001	\\xdbc9b73e4bff0156aa894f4fd93cbda180d799ac00aed1ed91855162b0200e9f4e28db1ce33437026ddfa76368601d09f8db50c4dae288f086905cd99c19c70e	1660181788000000	1660786588000000	1723858588000000	1818466588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
205	\\x11ce7a500af9d95068c5fce0b1c0df04aa65cf788ff8b4dfb2d9abcce9c174ed738241c247f9fe4d93d24238cb3d8c1eee26f78602b4dd37f0f9472f2f1a13c2	1	0	\\x000000010000000000800003b293839719e04551e773869a1f57210ee95a98c882767742ddbc5e919da14ba8f53dee4cbf77e4732681fecde6afea833da0b3101c25c940e3a61dc43678a6d24d958a89268d7b9d02f3b219236c25d0fbb6d019888c0e4ddac617a1ca85c94e4a36c1243c9b71a68653e111285551ec01097b97747f5932ce54bcc93177e789010001	\\x3f44ab015bd4a0a5a963b3aa48d9004774911b811652315d90a6e72b3fdc18a8c899f07eabbe2d3049a3f4885dc42e79deecf638e51505f1684671a960b68707	1668040288000000	1668645088000000	1731717088000000	1826325088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
206	\\x11ee8c335ca53da8c3feb3e15e10a99ee518b5a8603a37fdc4b82736ed96b2196d740ed8817246ea3ea9da77c9b50eb02057d5bfc96e6e4ef3e638847c5b5dd5	1	0	\\x000000010000000000800003d3e188bb95dedc39859de2d588a3c2692902228bbbf5113b43f1930c3853de3571de116559107beaff5abd256d1848a5beb50d82eb835ab3c6d5a12646362397b4655fd466aa73c7c0a7797fa2bd8c2265dbf31ef8a738fd62fc37dbe0efd1617bc96de216c93a7bcc1c4ec67c67895fcb4304a549b8ae37b47c73200c5d7c75010001	\\xe89137aeafd9541d34018b14a83ccfde7c5fdfdcd3636f2f625a69c78969b51c6ecfc531ebe56b48d5b572398aa39e685f6487e0c7fa37fb636c324ed1a8f90a	1654136788000000	1654741588000000	1717813588000000	1812421588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
207	\\x1a726a8c38313f163abf86d1219923ceb81d1d46ff6509b0f10af8b8980de3fee1932dea9076c734fd046eaa83d1f3b411c536fe4a5f29e9177286fbfc728e3d	1	0	\\x000000010000000000800003d21b5bf65c136dd65941c3734d9e3eb7bfcf7d0be71c71be027f7d4dcd5e05a840c48512f38807bf0a2ba5d6c40431572c5e19cbeccc4738925ccde3ee3ebba96373d546bea003d4ff57cc37fa9ce6aaca1220d6157ad2835d42bf5c80eff056c253b14757950b7f2bbf01ee124bd8794a131a9a8d88c2b8cb11da47a43aef03010001	\\x97bed52044168a48490ab219fd823fda4cfe6f5e0e9e4ae87667f227b5039de7a69f20b9568ffbf257266fa567f243dba585d35cdeb5bfed26393b9457b72802	1648696288000000	1649301088000000	1712373088000000	1806981088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\x1d6a6059a3c08933b61870f1f5858a3a406e7347917009fc496b5abbcbee01dd27f7c24f300c0e3697513b150242e3a181554e8b1668ddc89bb0d079e3fe2d84	1	0	\\x000000010000000000800003d497ed68fe3cfab86bf20ce6ce7877d4d278de8ed76f094bdbd7dbab6165bf7637bea49b5a8538dd7c35c9421bba9811b3a1d685011fee70a0d5690347196d59fba4069fde3e3bef12d00cee741e49a8f990de317fe387f505d088c8b0d6db5321dd4a1d65db976b6d823fea536cf0764f458f7ca759ae138d2b9a5cdf8a1ee5010001	\\x91452b652e491ae6f231b894bb1c45f336e5da45f2069bd7b832d7004d852044fed5a910e60ca5818687aad2618b340013b9ae2601345fe19ab2a6b403c3880a	1671667288000000	1672272088000000	1735344088000000	1829952088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\x1ed2af8f71b0250fcaf972df39910a636cc60b0fd41ac0d937bcbf8ee5cb4e117124ccfc0955ae421d058bf72c8b87808a624769bcb063d09330b1d4e9a73d48	1	0	\\x000000010000000000800003d498dbd14a26818a36edb933629fa2363fb7cdb6e252e1c537cd18d029636773ab2cce9b0f2d86e1a0f337982cbeaa9d637fc19667799141148ddd26a89d763b8d6b99e26e7c201bd1f8b19abddecdfa0994af4528592b5eab4273dc094037d7c25c0d7fad230590d37b0f4a867324f09815ca4e72ae95d028fe0296daa8af1f010001	\\x8f4f4245260bfdf4238b5024ebc3b0bbb087c7d5739d0d70f704783988aaef452a349b236959d470aca54319b6bd341e132ce15b4b614690a8aeae7eaa5bb80a	1669249288000000	1669854088000000	1732926088000000	1827534088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
210	\\x21662bc27e41f528adce010d54eecbd52980d7b858091dacfbe8fcc030a5c3698841ff8b9389b25261a2f9910708ccd42efc03a462695d30bd1ba4bf17839e88	1	0	\\x000000010000000000800003ca96da0219ded0e6b79f25d96856827fd17f573d73374d2753762dd64367980bf33dcf6e3ae857b53b4535a32b72dffa89dcc3dcaaa05af15ac260ac40ec7681d0fda60f9aecd6d349ddaf920b461b2f30d2e5c1238f3c2e937d68182a7eb43e505944d911d77a0a2c468120f07d18b922794bac13e3cfa2355df51c05d3e419010001	\\x077846ebb1189f3d136653611a2d79bc3855f1bf3e54188128226aad658f50c93f0039d6e82271bdec6a0aa1a43e0cf03dbf04320ca4179eb27634704eff2808	1668040288000000	1668645088000000	1731717088000000	1826325088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
211	\\x2346489fd54312963ee895997f5c425f1854cef439029f71a5bf532a1b94656239ab2a9da75213ab12e100d50adb66f25ba6dcf05770bfa19a8466acbab3991f	1	0	\\x000000010000000000800003cc54b0f46a9b246125ad07b4fd6bc2a6a76d181332b3c422a9b3e099dca6398ef6063277c704c768428ca046633580539192ab413e59435dc5636fc51db5765cabceecd6e2abd6c7eda09aa34743e5fd8d1b98a2bc83fb71be66fd58c89affdbf9a8d68f56fb0d3cd1661995da5d23e188049419b29889980d5d9969ca1b301b010001	\\xf7b9b32c71de889ea9128ff43515da686a8dec55a833b280584376dfad287cf507f3c2e40193e26365129889f035dfe0bb28c07cf31834109b11e311f1b87c0b	1657763788000000	1658368588000000	1721440588000000	1816048588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
212	\\x2482ef60a2aff0bfcf468ac4d87ffc928e462d61f806eae957d788b9a9263ed3ca49ed3f2a31cf7ac62c2bca41a5d8ffc6ac5840b5bd59212e7a9a9c10d57354	1	0	\\x000000010000000000800003d27e61b961f1a7b20c2074311c206978e805be4fd39d3e629f25ab52df9a1445a2fb9e3d727f35dd509b31bb6a266d75ea7ed5c2f5028c64bcfa9f528bfd39a069e31ac1fba6465b7e1e04ac6a075c7ac412931111948732b7a9e3d1e5578b066778b0c6becd03f23606dc5069c02575a94e3287286b0079059a57d48a3d051d010001	\\x81de18c64f41af27170ff607fc131d0161bf79a683c3119ef376d8cf8ab37c73a895492efd3f52f565635bdfc14deb92b5772f192f5910bed39796ad34f1c000	1652927788000000	1653532588000000	1716604588000000	1811212588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\x25b2bb60cb7df0b3eda346d2daf639db1cc30c2326d6cf0e4bca8d08ccc0ecace2f24c7a3bae805cbc201b4929a905100a6c24e89ce11653cf332a6058c649e5	1	0	\\x000000010000000000800003c3cb294982ad29c8ce0061ae1bdd8c95fe5bd3b67014612a729ef7e95f9ec4fb683cbeccfec1f78239d151040fd37f0bca7a3fbec455caafb6fb0094624511e29b3a874eeefeecf4214b078b12c70e1c49b53fa216af96f706df50eb8586b35804bae9fb50f47d5b0dd039569b40228eeec297b94340ffc67165928034bb7bfd010001	\\x89bb02dea225c96ff72980d55d22ba93ac20658a2b97bac31463084d5288a71dcc7232afb8a3e101e16c95930b026694569918231fb0e213d074f73e6e6fe203	1673480788000000	1674085588000000	1737157588000000	1831765588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
214	\\x25a619a9d7508cd7f41eb978c2d872ad9a79e339f1020f8d32f662020f43bf2470833b8a022c5cdf38b8d4da2e1a1f1dc381122fc30bf2a8af465a17c3c608b8	1	0	\\x000000010000000000800003c07438a0fdf22288ade2446f479e5c097dbadc240953f20c4780f22b8da562e2b4808703569aba014e179e0a393a346751b46beca57d5c95f48a69cea715c8d9758a531453f7795ca938db5df73f1b936777ddb12bcca0565bf78953a48cf9647a141ccce38d4394747e489b4aaf6fe9e8cd2797d6da1b41ee9c3201e25fb7e3010001	\\xc2e73f2e61752d3217920bf7a4861078f51f984cc95628831a0da1703ff9478a3a5c20cd1e2ed539e6cf81dee14c67765e8d62612164e24438a280cda227dd0f	1675898788000000	1676503588000000	1739575588000000	1834183588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\x281ac34fd75f26a56d409a4cd06cdfbec747d821b67c8a590dd4a30f06d4b22410b5119bb3078b9a8a7cde7529101cfaeed9479ed1a6ec3ad8197f3ec84425f8	1	0	\\x000000010000000000800003b45309cff653aabd26a8fd4b6d5df1ff72acac2fceb9b0d9c3f7dbafe8370e3cac529adcd68bfb316fe7b51d719a82815123d52da8d0ddfc91ffc0522206656474844bd41d1d5b8eb38aa78518a3178297638250e551da23f6493284dae8bd827ce9bd7a336dc7f9993d6ab8f3421bb5f13dd25ea0e30a3276cc9537f8ef988f010001	\\x047bff16ae1c913325954d6f365501eb1c64f27bdb2c130619372d937cb7c3f82be85bd0c46ecf14b0373d5d1817bb1e87b7a09914ee6f3ae3c3e50fc724510c	1657159288000000	1657764088000000	1720836088000000	1815444088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
216	\\x2baa1c7afc66719da36881333811a8f488e9a48b09e8b11f59fbef98355fc42a21cf311c5bc01360c4c1eb595306ed784015bb8c3cb122b7fc646c0699cdd6f2	1	0	\\x000000010000000000800003a5550dd42226fb1f8240ff51f1ccca42c306e24d189ca8d32daeca831c0cb3fef1e052e6ac3aa9050e8e6336d7a2da9e081e81148de2ea60f0c266fd91ad2d513d13a985539433b2c1e6b6732b2046e3ec4808a36f87456b47e5fe416ed93baaf1a8b8a95cbec206de76e454abd809f8200ec076a793dd1631e6632e2727d169010001	\\x059ac1c2e7b68071a386126f0e59288717923527778c66fd4407b58af422f835fc271a8f3b41ec7a700cf4c63616dfb7c7338a4120eeb7978ed4a1dc0fd19b07	1674689788000000	1675294588000000	1738366588000000	1832974588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
217	\\x2eae6e4b3a13023a998d4352c58f3c36979e53993537c359bebdb05c0b7b85b796c8c02cf505b682ec69a159491dcb7d1ba27ba8ee02b39db2ae9b1576eec329	1	0	\\x000000010000000000800003b1b641085bc6f96b8ae6992471c6cfd6bd463eda0a0cddab1ada3aba645ca3467065bd3ade6f40b43937938e041f01868b12844be66be480f0ea8e71955ea9bd6f3b90e2b95f5f967164351b368512ac3e30c6f5f08ccad8b73586e70dd15c98ed7ebf7378096bec1d36096ed3a75038be1e27d4b21dd918e549fcbea9fd63b1010001	\\x138a840f03ea577feba20be1febc92dc523b976e5addb14417ebd18093cf35f6b08cab6d646d27f9891e61cd60d108ca11b84e9b8e77780ba28557186d1b9a0c	1671667288000000	1672272088000000	1735344088000000	1829952088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
218	\\x315e8799b6fa426de9db138faf4019b23720c06ba49252e01f8597ede7f3e015abc516699e668771360b74098cb7937a1a446e0d87cf373071972eb4fee2381a	1	0	\\x000000010000000000800003cddebe8d23de8c7437331be4e2b68061c114e52b4ec58ac202821222bf72db50efa83840ba4f2fce0d2dd22ef2a75490a782d62e6efee1e275edd60f11d3fb42689ff69ddb1296f63265dea93955a177d0e5c775ec68132419ce7deabd0d3f777e4789fe874ef159f5c84585ddcc3b10a209b9e70885d173bb3d432fb9960ff1010001	\\xc115ec2aac8c4b68f54fe1c6a7a05b865f90900491a0650d6fc9556379a28f5c36c49c21118bdd41c3f23d8394e1a672d7ac540fd753e56e7111be2759adcb0e	1666831288000000	1667436088000000	1730508088000000	1825116088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
219	\\x31463f6e472531442bf93bbb1830b628b78ef55107d33d98d01d8dae03ac1cc2b6a2b428e08b872d08040a7ad332202a3b3467aa9be28347f09172c9fbe00a5f	1	0	\\x000000010000000000800003d5286daf2c676898e59ff6d0ee6beb931edeebe0b6abe5b442822948cec29bb8b0684e428ac2529b500c5effdd0f20b1221449c652bbd9eabfbde4a613b19d44a513bd5d19f9d06c000111b6a31c52e0eb98bf87e26e09765ff38be99eb053bc06e3cd4703129e98ed12bed07046a70f753bac94340ece8886e4acfe66b8adc3010001	\\xad1f8ffa4af42063c6d40a4ce4bc5b72c9bb512d5424cd0221a73eaf41d0d18db9202d7b94e292c22455465efc0e6797533c45f466a0fb935c485db0d6567a0d	1662599788000000	1663204588000000	1726276588000000	1820884588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x3356887593a8b219bbcaf7c67fb6ead6d210fb1f3a9614d7adfa35e1747fb1cfba29c208a82366b174bec6085d45f10888ced290ce596d845844c8ce4a52dee5	1	0	\\x000000010000000000800003c4859d4f634d07adcfb100b8337099deaac2562d7e50882b881908b957b7f662498a5a187a6ece7be8bc9f5886f47ef7c3b3b2c83659b6b66c32f43f2e7e73672c565330fec5e9a95345e870436f76a77e91ee1f50e3d3f382b0cf1c8b11f4d156cdbab887990ab94b3ac31ce2c60ee16201bcf3cb117e835901dca27ddc502f010001	\\x98934ae5dd68af038cdf6490a7e374447039ebc634d3982d887cd70eecec9e6d8e887542e6c3d36d4a3b18e8aef23c187d4d51e9f18f1feba48001cfc7382f0d	1657763788000000	1658368588000000	1721440588000000	1816048588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
221	\\x34427196cd624cb668240e41e75742b410ceac3ade4e0e286497a3e92f965928a681a275f1c9a5b1ce90eeb2789c9083daa2a2f270987259e69196939cda4790	1	0	\\x000000010000000000800003cfcdce32eab0279967897f91c3693faa75c022d642575ef876fe8ebed4d1e6634ecc96f322f82e54d1716a3a221eb453558c1a491e1a598f5233b433dd9e8aff0038bef867c8be6971577c955abf9c5d85a204950ec4a99c259f9c45144bd4aecc6c4e979b76f26b3358dadedcc5d8525a494a203696204ca22d9e9cb10e7f07010001	\\x01199bf1d1cee9e3a8a822d4e56e5794bfa8c1c767194bcaeb265c988042a2a47f60c75b5f6fd485d235ddff28a5d2f5c58a70abe16c94a3f07792e6dd820703	1654741288000000	1655346088000000	1718418088000000	1813026088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x3abab774d9d20e539be1fc43b820f5397896932f78d388ca8e0295cf8283a332276dd80cafdc408efb34ae298eb6390714aa09f5493d771c8933261ce0691a7a	1	0	\\x000000010000000000800003be1c77d2e45232a04b9138efdd21c4499068ec536d11ad83d0a72fc93744c857bad473eba9d7e7984144a0c2073c00b8ee9eab59885898a89c18bc342b6ad771c5bb8e506b41c4bc83255f66ad2eefd132eec24c818679935c7bf4207ec64154d49c01a059ed66af2b36adf89e23c0fab68e83c35923da9d1c8cb35b83e32089010001	\\x5c09d7be6218eaf6afaa6d4d60b6e3809ba2a0269814aa97b48cef48509d981facf40e1df29ea535474ab6b0639831add8b3e043927a89d005d3137ae6007109	1665017788000000	1665622588000000	1728694588000000	1823302588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
223	\\x3b8abbbe2ee28a5111e6ddf35faa802f5b6cdbda48c65252561478ee510abecb2036ba4b2396821ddc7a63421192fc6250131a8318f70834a9094ee39e2ca3d8	1	0	\\x000000010000000000800003994645ba2a74b8c46532929c353661a135a7bfec01b7b5cc56e9e33edd957b80bba595ebecde3cce8fe01a31c935d200597c9ad3a7e04c3bb4a51f62ad208089753d609a79e644174338b10317501e1e6df663317c7926b1c605e1c6d414a0b53331130015aa70e5bef82fd92bbaecf8bdabde23ab639e03e581a05cda5a9cf9010001	\\xa35bfa72ccb787760945df8f1cdd38c73771516ebb93bd256a7753caa1ad238546349f8ffd224094003357346e2e582a5ca23212f0d34a821f09b64007eea806	1671062788000000	1671667588000000	1734739588000000	1829347588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
224	\\x3e86216b497d458ab3341572e54a1fab54d5acd6eda5ad7fa55d0c8c344da0bb4baf49ec5bfc6ef343eb114ba8a7c4273dbc8308534ff469fd8e630824dceba4	1	0	\\x000000010000000000800003ce82316b5e905acca2f155d7179508755cae4d7aad848a47a8aec9b81c677663866a053bbad75d6cede78b377b66f993b617bd850b3cc8c37ddf2586644b769edc657e2188c823b8ed3e17b9ef8c7586b7ed647773eb3fbc2de61a05a972491965cad4b88c99d89e8932e20d32c3a5c03b4c8878d47ba48d9c28fa0693f5fc83010001	\\xf5f70411bc0ab400a793a9e7f8453e9854e930d1f6d402b68bfa4a3baa8645b0f14b8d0becb0e17e218142132cabc191e5f0716b00a943a6a7a9b02c2bfb7600	1658972788000000	1659577588000000	1722649588000000	1817257588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x40c2a9247925dd9435088aacb17b93b04a84502f9660cece8f1297515a1fcf98bd0cf9d22561478ee41582093a95665971332523bdcd0979f8f1ec924b144416	1	0	\\x000000010000000000800003eb6b5e8f3b115f662cc9a0d8b3997cb5aa549a45be8ed7227633ffb2fc78819c7cbe8c08900da86124a97a21bd2cfb3298858d6933f23b0e8ce6f9cdece36dd9f45053ece59d8a4a5fa33afe309541d30e51c946b8067a36299ba2eb5fead3fb9924375a1fe09c995d062ba72fa0b2b696a2a3a3eaddca52c30b615ebdc8c87d010001	\\xd462ca1048385369556b64d26e11fa56d3b1a99e910ca2c37886b2512720ebc29a98372f71d29913323838f112efaab9269cc732f4805cd3fba0fc4eb0b01a03	1651718788000000	1652323588000000	1715395588000000	1810003588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
226	\\x492212776286493f2f6df4cec7201e0edc750b0e641177ab610b5675aec922f5e565039016c0ceb0f447e398513df01fed580dd1f80efa7d68b13843c017943b	1	0	\\x000000010000000000800003a630ecfb6991977833089ed2c84d12105def576616f38ec34ffad452d8068b830bbffed04b1c3a11a402fa1ded9ba6b3944f2e5f963d177e393d17e957efb7f0b8fdf197c0dfd8254279cab859a8b4927fbd4ca0d4aa1b950ca08aeae0e217c712a9f0e6aeacff2b137561a7f4365ad1f138855b8ac7d8f75a33225af857ca27010001	\\xf69eb2c942d3839007b301b85b45ef34e75f24d9f8eb71c02bb79ac03a9d033766d4bb0cea8610670f577fb90a79ff6c25d5028e0e162cb87c2d03a6487eda01	1668040288000000	1668645088000000	1731717088000000	1826325088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
227	\\x4a9a8392e5202eed4683c92c5f44446cd31fc7936809628d9b01e0352a620ddb4f41b6bbb152afdf215bd90963063fcc1c1a98954ddced922711ae1d447f57ef	1	0	\\x000000010000000000800003bd282a30fd0e753ab02b48e5303244580cc98cb0d22b0692c2ab7976939abcc99cb515832375aebdcd77cdf53859ecb9de9a031897dd6d6aa0b49b9c390a2b854a76086e7142dcd1ddea5c7c4044b2d18649ccd622346e4950169c89eada6b9878ce568e93313e1167b57f14ec0a712e7ada1bed99982be8f89e254b8febf7b1010001	\\xe5281904bc0ee67bf409acbf96b94a01227043aae9a0818df7dd3ec37f69dfd7b62ced0e479aa4311fe9bcd5af9e0a33156400d0c294665f30708cbb074c230a	1655345788000000	1655950588000000	1719022588000000	1813630588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
228	\\x4c7263a806481fa2ceee35f612f4918c18d962470b7f8fb1d88f243f4ff0316bcf5c118cfb87b122b67bb7a52275a811b38bac7cab76f7e88d2affdf74169aea	1	0	\\x000000010000000000800003cc04ca21a7410232126d90cf8ca90948b54e7b2864e63bfe7b5c0992bf7583415a15481cbb531c9485b14ac8429c58698c8b58bf922a5003197c80e36f370e754df037c80e819c235dc70f88177e6030afd0809fa0b74603c450d638d880253bd403ca360736dccdeafe33d758dc8f8122f63a678fd5b093d66c66abcb5ed99d010001	\\x9768ebff840deff76c13df3d4f8187f97b699e94868b10236e39f0a38840630d512c4f63437439366372347adbc58cde597a07007f73978e2a642345673ec902	1651114288000000	1651719088000000	1714791088000000	1809399088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x5356260edb3772081b9324e780fb9279dda579e6499b0728b0885fa55e3c03394400a3bd0f2e58b2ab00050e0664a9d343ef133b91863c9762c8cc4bd679dfaa	1	0	\\x000000010000000000800003cea3f083fdafdb3faf6b843ce67c702df6c6a9a6731553ba45eee59ab45f6f2616e1731519302c7c61b81ce903719e609f3a2df5f0059cca57cb95722798486124deb82acd0add658d4bf46e20befa2ebdca21f799508a1355f9083b5c5fdc74beb0a92f431490bd7f0c87b95b4d08fa49e3e5867497a4f780788ae246d969f9010001	\\x027f5559ff42f50a0a2ae0c32b581c833c9e8a61268cdbd83a0c3aa0b29396a76cff0dd783e617254896e6ddc1494c48e3ea2f6ded12a5ee4f585ae40a40cb0a	1652323288000000	1652928088000000	1716000088000000	1810608088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
230	\\x5dbec3a4dfb2c48bdac704d5e3eb8f5ba399d5ba24582bc4d61996aca16dc0b9557c2f3cbd26e688959c164ece9060a286a717fbd5e8d0e9df67d70199b5f181	1	0	\\x000000010000000000800003b8a69fd3133f6dd0af98b0d6446219097e15e46b27018ab637668714d6fb0f71bd85d84a1be3000e5a8ee4b7c0e6635f248e52cfadf98926907778cb3b3d98b49cbdc538bd4432f741308e1a39c522c0fc6166ae3741e80839320b648086147303c879a2e5595056e0c31d81c644df0e49c1ae7efc2dc6f040cb3e41569ed5c3010001	\\x3312b15c2b5424718e55491b2a6f69de1ad88a798ad856dcb660cf19253b3132fca79782d4cd0efd0423ded38d61a166d03ed75aa8440c75572516aa6c1c6805	1672876288000000	1673481088000000	1736553088000000	1831161088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x5e962e0059609e74cb3615ad9b641c10a051915ca72ea9cdb52745ad4d5cb8be1cbb50e637cf1ba2f2453bf8f3ba8fab9a2d1d804d8e52d177a19902217bab22	1	0	\\x000000010000000000800003bd67b3a969cd4d2f7b0a3945a3a3552f12e5068325093c678882f906f59478d360f59082fa3dbd2929646aab800f96a806bfeb43dff572bcfd0f2b9e99d01b9bab4d6c9902c3cb8c203036f29389d9fc8f41bc3aad4660b6eceba6f91dccd9219568f63130e812bd85a3f5e6acc1a8d57e48b6e84ac611dbb6c7155d6846bb83010001	\\xc80bf4b0cb86e8a981619f822f0f8e3f54cff11f58d57c01f4df27bd861d0cec56d48d2afb9672398e2f9d49c2f14e4b258d981e0b6805cc5f9f86c023366d01	1662599788000000	1663204588000000	1726276588000000	1820884588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
232	\\x620e75964492514376f29482329c0e7d3fd91c19280a3fb933039ab9c70b89f0d7f3f125c5166cd7dee226615c80e330899abf0c701b4857170b61bc74a589b2	1	0	\\x000000010000000000800003a25a5955cdd971b1cd07231b10ae76a11105af1913767217f9b0b8e322f301f5998b2b57d1f6bcfa55cdce147d545f6ffc244102f8ded2209243b05416d310c7587cd27784b4a55bd255f17b84b4065ad5755be91ab6fe9e82c69e951b2cee74ba75a1bc2093e5944b298a2a9943d318701543c55cce15352336c513f1170c17010001	\\xadfa86e29e0d3087dadd27cca6d31442f61bd688f6157c7367276d4425d54c0b12c8c63208eda812abcf1d9e6abd372fbe20ed266facf46ee0e18a1a1cd18b05	1661390788000000	1661995588000000	1725067588000000	1819675588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\x628e96250154299f89a6b764d8e7a884e9db54b9a9bc5ead8a04cb5ca21610169df9ba71f0a6d99d8d51beced89ea39e14a1c7d832a85558cb12b9e695b13b56	1	0	\\x000000010000000000800003c438e052fab525caada9388e011145c48f8d45e3fd2834a901ab0e7e22a00ccf2a229dda7eb8ca7c98e7150340e0b599630ccf60e081d08a734d46b1b21e175bc85a06b67513baabec8650f4a7656ffb743b721a9f2d3f67b85b379f92587b650f19fb31658b0432c3070ecdd4c94adf6490208d2e24bd120c34f0378c527a5b010001	\\x2a58855e45c02874dab132398603b34400d9759ed9faf89b54ba0a441bc014c7396187755a99c198240e6f707a0d3b49fc37765f93931d2d1d8255c55033600d	1675898788000000	1676503588000000	1739575588000000	1834183588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x6232497014428b3337291bc029615a22e332dea6e8ae6033214e136d3d1a6aca393865c25868f3f9a43de571f3f18a110d93f1cc1cf085a47d6e66f21390f01a	1	0	\\x000000010000000000800003b7ec059297303312214510db54ff87b0301ff06e1f937fe646b7c0a96a7aa95b2ce20a01666caa889f5ab33057e39cacc5246ccbd784d0e94772b43af7cf83f94a1133efab893a5dd7b0340283b8d6e93d8881cd0d0592e43d8ede3097ed701f54316faa4605e00f1421e8f43f1e34f1bf0047938f349657d598a80438930e0f010001	\\x30e1851c657de9d90eaf03d38f23fab9aa0e10edd87a59c495e84830ff70811c295281fb8ad7c6f1af289fca73f4cd556887ff949a7a7697193baa9f39ec4001	1649905288000000	1650510088000000	1713582088000000	1808190088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x632268f99e5e631e989a1eb617f976f0958448ae0d810b51e58a78b6ba68b3707dd900f072b8760c69feda9bcc6ea19902800ec419e28f6fc143374cf96644f1	1	0	\\x000000010000000000800003ed79e883ae5de8d7cc06b273f008d9a4d834da25326a4e1471d51d0eff93a4817bec3ced079ace7f467d37537fc274312089c409b0e15eb2039657da736c02d8168fdfb8b5de3c882240148b5dc037ded8cb99825c3c8f4ed6dbc098a804cad58cd996bd104dcd1d0ca3c9d371a7600ba888140d60403855a9edc8f0dcf8ceab010001	\\x1c3cd8a8967df3c3c7c636d0bfb581254c02f7ecadb8eed350357293d4178e0bd23abdd83658c67365c1ca9ef12f98eb2d35e970bfbfc57a942666f34780d50f	1671062788000000	1671667588000000	1734739588000000	1829347588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x68eabeab33351f6c7ffced3901b90f5b41f6215433d5755c931f95cdc350344be6b901a39bbf4c7ed3da917a5071b22c63d174bda007ca64758464584007b53c	1	0	\\x000000010000000000800003ca265d87cb46efdb1841775e1632bfd53dea3e53f0d1da6bf9b4934d2a298fa64ab95e15b02e4d6d63e5595042870917466d7d17153d748e0ee31b6ce831ba5feeed2dba45b9f5085d08c4dbf9cd5cb549ed119fb5d4f1d269a70eb616eaa0630c02b27fc1fad0a752b942e39185701fac97556f8c5c19bea11d02f556fc09dd010001	\\xfb4c04f4e8df991db704ef2199b65a80f2b8564909e85cafe2fd6c011a632565ecdae2dd523229c5bfe41f894baeedb29f8ab6c378a7c1fcc35bd92cb6a7bd00	1671062788000000	1671667588000000	1734739588000000	1829347588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
237	\\x69ba437a13bf79b117d64f3e94b7db427bcec799fed20580d084d857180fd0ef79b5c00c9b462ceaab9e62e5fa30638d21fc7dec91f0b00cfe91b3642c70c82f	1	0	\\x000000010000000000800003abc3079574cdac3cb517fbf10d74bd70492521233f5c81bb32b0eb3aecd9be83d7494e811d208954d362ec27a766c4da4d1ee03db67623b3f0391750868d04422af822f977963c0dd6ef2bb9f15fc47f7ea56b5f62e42e2355ae4d87471c49cb61cea04428a222d57a1f357d6e3d352ffaa69f1b1fe63e53c4c7fee67fd01359010001	\\x0082d4a63a253bdb7407d539a85c4942aef174196e0a67dcca9cd5c0b9d671c6a407d6c54933ed1952666ef89c393c1f3f69729340b7ae4c553ab194b0daaa0e	1660786288000000	1661391088000000	1724463088000000	1819071088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
238	\\x6c8e481a5513cbd27f051e67a390624aacf1ee83c4fae1704035a203538950c8d5dbcdf1048b20a101bc7b1b5f517e02c202502a42fb5f1891e2de85bc288309	1	0	\\x000000010000000000800003abd374572469388a50bd5e69e2153246cd7ab1e6b0f30fc162921f2384e966f8b315f51d3997ca4c0172df01f62af5c6fc7148940a2b185618a000c434d500759d8a3610eff19f6924a88dcabc75f786b8eb2b24f467947e5bd4890b043a264e9c94a4592fe9e7670a252b9356a509d85260795a29a6d582307b72814ed421af010001	\\x9a3609794254670e05659d40bf15ac0b7b72c6eea693e6bc15f876110d3a9b6c0d8446cb713290057ad1daaea63a18727b4ba12b36d2a69264b2d89a6633b208	1666226788000000	1666831588000000	1729903588000000	1824511588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x6d864265b89cc8f9df7dc8e66065825f798f10c4e6b7337278b480b8af764edb9f9416087388627b00c67cb434225d76a604f8d9fc64ba682837aecf5102b7a2	1	0	\\x000000010000000000800003c737d158dcfd5ab3da726b58a0d86ab160014a810dc789c29871ab6d2ac6268842c8f29b056799b07b461e2a0fbe2370db5b00f8fd2d5bdee1164f3d3172ab3914807ebb69e824f8813c9e30eb35fdc79a2a9b31b552016f85bc0aac8307568e943d1d0189b49c57f6a861d183570b0f6bc765f9127261c601de29f3ca897e61010001	\\x0cb5fcadd9210e8495075c3881591b8a319d6ca3d1b655035e4f2430ccafbec008178da524151d21fb1f79205a061a6194ac8df5682438e7a71c52b462f0cd00	1677107788000000	1677712588000000	1740784588000000	1835392588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x6e9ec46464bccd87c03c7a90f37869586e1ad9827501e0163c7356e2430aa599eae8a89cd0b2c87e7bc49c6668effb1a81bbf5dc84fafbf73c6e02be8661f67f	1	0	\\x000000010000000000800003afe7006339acc5a37c8a83bf3917b6417fe83f503f722e745a2007d0cacf1301396b1fb9325006af01bd78520260e9d297ff436e8bcbb856e16119c05302c9925eaff28f3e5aba9fe6fa8d97cac12aa25b77f5149e64d8df86b300b2d5369241a834d106fe3750b48a2f8fce40b7f67ac778865c3efd7eff96422a16340f9ffb010001	\\xb7c016f5efb230722cf70c14127cc3f6e5f55240986a820b9b722de14beac143a03bbe3721901bfa6f6316cb4a85c1f20bd0fdc9a70710ab9e6a42eb9e8abc05	1669249288000000	1669854088000000	1732926088000000	1827534088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x705ea163a4459b851e2d5cc060bb249b8217fe6c928bebc0d0893b59ff0de6da86b9b0beaf3348dd30f5b654ec5db65ec6e1140e658827e847ccdf74935befe0	1	0	\\x000000010000000000800003d562a650ed71322e136f84d1d0ea32976478925cdc81205bee230c99439bcfb76b9c47422647659a7359340426897154ab41aff93add0a95ae58102757188d76ec43dde5e077469b118fc4635cad378f9dfd767d456992bf49e454dccd46cbcf805325f76a72c5946efbcacca6a63a4819a5610937d40af33c741bf4ae141105010001	\\x48970870b2fcab31679b32d2994d9b229c207f03df1798814356c3b98289e4c3283dc6ee0a3107408ec6fc5e7e6971e1d18a00217085d4824f59334014160108	1661390788000000	1661995588000000	1725067588000000	1819675588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x710a8f271cbad50e0d30e678ab1b56b60e1e62e145712e645a498c9d97885eb2c0f967d11a4615b78b060eb160ca015a9d2b62e43c23ecf5fc995e02f8cfb547	1	0	\\x000000010000000000800003cdb2cfadf69137aa8a6be947ed064e085684d8b268af98908040aec0fdab96fcc4e2290d344def04b8906a961f402bbeb9d72c000f2ccbeee4619fc25f4888ec59eedd73b5db9eff0d0c7662c81d22c2732e512fc6c7a6f86dfae9cc9b3dc9c4d032ea80abb7f2c4ab3c57794f583f492f2fda1f3873591e31202071f29f1171010001	\\x4d5fe8954aba70ec6b2ac37d2f0d22f36d78899047c033d09ebe586bfba843e6c73d84a53167245e0baf9670d51bffdddf6e9f4ed35f829e01bbdf6b118aec06	1655950288000000	1656555088000000	1719627088000000	1814235088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
243	\\x768e4f4bec97f5506f5dbcd8b135f9f8bc6a8075cb320ab3cfa8a0aa57dad34c3d50d1627d8e7ae9dbecbafea9667a76ada803e7b2bf29793c4dc11deeba0875	1	0	\\x000000010000000000800003b45cde64ee65e390f4ea704c9684d2a68c1f1f68e364488082221248726979086b17f0867805fddbfbee1f0515ff06e932b42f16bf75de5019cf20dd28ba62010576a3de56ac66d83dc5908512d7e7347239d305729f77fd3e3ef97c80abacfda4a9597b622d9c321593c08f825d77cf0f5c89991f838cfd18b772f483588183010001	\\x77b657ea1d0be8bad1590f34a5d1d1e3783c242325bea156fab5020fbe677f54e2711b5bbf0398fc4df2503b3acd0800bb8e63146671e9d1a739bcca4c0c8800	1671062788000000	1671667588000000	1734739588000000	1829347588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
244	\\x77faaf63c731c7889ff95187ad00fc160523f1aaa26df007e025bcda29b20ef6efe248c00ad0b7f905894c2edc8201e25c3a9b9d6e576a0a759c008df1460104	1	0	\\x000000010000000000800003e525d0d3db2b4ef8fbd2158d65395121307c1a5cafe8836d103552587d9b472081222e810fe356bc63a10e2eac08df53270752d861d73ccce1ca9ef5f14ee42e7058ea006b6a36c4083394aae1b4a59043307a8feb1aedfc0500540a76c9b8c0951e59566aaeca47b2aa41d3c31137354c91a5b938212df93d534fc2de5a76d1010001	\\xe9fe6ee233e9becdfbee34ae3098b0f3f09d05f46cf8d977ce11d4b0733c80637d560adcd44f1465afda1022eea84fca12f84970e4fc9bcd0875666ca82f9a07	1650509788000000	1651114588000000	1714186588000000	1808794588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
245	\\x784281f04d0630456a101a4db8fbf4cee9d3cd90dcb579a8344a3ec8631a269417ad8eff752be2e1a2a404c3fc7ba377e9c9742a6795609a20bc364e4a20f7ef	1	0	\\x000000010000000000800003ecac0ab00a4789004fdeafb01702f782e387862f126b5a3595811702d16e86b700ab777f3360bac6c15d6b6749fbceeb5bcbb1c6b6f0037bcc304a687abd07045f6b288c1fbedec84e01e304c80874135d1a787141f9b02c5f762f9513ca5e98863717ebe1e8666972e1a31453de6041ad839617a04cd244508e642cd749da67010001	\\xac7bddaece1f5b12a0c964aa266e5befd573b920a1551c5bdb7243c1526931f079887d23a5d1a6ddad8601dd2245f24df4c38f82155a09a07e3d6f53b8447702	1677712288000000	1678317088000000	1741389088000000	1835997088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
246	\\x7b3e5929bba1893188d2f121e4104a93e36b99f308a1d2f58d1507f0f1309a24a45b73bede9f6e2389f3edee73718ec75b470f76ea5f62a50991430edd6f8c41	1	0	\\x000000010000000000800003d876353343c5292118c93c0a61ac89c4fbe0e69cb8e7f442bc81cad8b658553962bb679c5a51dcf70472de98b712ad8e9993d76c69daabc10e9b075d96218b6e6ff5d86533619d8e9b292485a5881196ce9e185cd21458366138f3b74df5cc53e6e5d8070fdd323ef1db79ecc8cd94e45e2b12a5905b41db51bdc1eab54620f7010001	\\xfeab3b78d840e96a6242d1a314f1ec5173eaf2e575215e0b0f05073a30c7b825bfb8de4437153945aeb2440b4236765ec6dbf9f8b6f9bf04af994e090721c90a	1648696288000000	1649301088000000	1712373088000000	1806981088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
247	\\x7b36ed9f095395e4f43950f6e6d2854aaab4ca1f3cc88ea0d51b58ef8bc56eadf349e00653161105531c3dbfd3c96448e5942eaad2b7dbfd2b67fd35a64121ae	1	0	\\x000000010000000000800003e4c7260e2416519dd9f2f4cb599edccfbc518e8143debabeb9b84665675ecfd815ad44708d40c0af84c5b5cb40544c07f847381a277d4bce094d5dbb55a34e327feca942bd8f080581d69937e74f88548a184eaf36737052907c0fd866eac0e2ec6c04467bc7d90fe8604161d99c6776ff1f000d168a02426e4d29afb1a2b699010001	\\xf88da5168bd19fd467e8019f6d71f2ec3dc9351796cb242cabe1e2edf36498adba3d062f2f7e6578dafdd7d7e973ee55abb44a9cf9a8a56ba99cb51ec1e39a02	1660786288000000	1661391088000000	1724463088000000	1819071088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x7ec2b5b4abf272d542220aa8f23aff307d0cbb76d066946dc257f81bcdef8fc827cd43964e9a739d50cd3de60e768dee97ebc4064dad9897d60a549947846fce	1	0	\\x000000010000000000800003e78f52b6473946255efad12f9637a8e94422d9180b73a105486df6ebde6985c5330189d3c1d982ad6bfceb0fd73c816b276f159ad4e509a153e5dae525856a09ac86dafc2076f1d5d020ecd565a6363f72856c0643bf73b13f3196c5ce5dd0b4ae4f02e511d9cb0c370254ce85e6175b0a4e09bfdd9ea50367a49eef29d390f1010001	\\x45d3be487a4b41fb607b7bc49031cbb5812599f66ce710422f86025e166107c02714793cfcbb383ff09ca4b821fb47cac0a5da308925616aab6ca34a7d890c0f	1678316788000000	1678921588000000	1741993588000000	1836601588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
249	\\x7f122e96aac7aae43a1a56d79dce00913cde998c28a271e83c17beea10722a22486aaf35e18d20a4b97d0ea699902b3d5a0724ada9cdc7c388029d39cea1031a	1	0	\\x000000010000000000800003c789303a7fa8d61d36e75dad331abf4043b9dfe7ceb72a3e6fab0ac9b7294703c0252967f53410d6589b546e55beae268a86b61a26ad0b26fbe33a8f894bfa4f0083ad56a0f3a4b029879626889c0753bd50b32a520fa110e86130fcbcc6091f3c5a4813dc93dab506037270fdeb97385f6d9308d2dcce9a2fb89e7e4a5860d7010001	\\x36079cbfe1ff42d834d5acf2b7c1d470daf23d976d3a923f8506d93b16a4e0d45ca98856aae1295e24c8fc608a43bd98517da3de6da9f40a43ab688317efe80f	1671667288000000	1672272088000000	1735344088000000	1829952088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x807e71f4687bf4a5ddedb9b47b0cda2d774807f91eb3e72587f4ddc8bf64e02bd8e9b83c201ffce8a9bd3f73c1f1e4f48c9014287bdd3eff86a0fefc6ac3348a	1	0	\\x000000010000000000800003b3bcfbb5dac05be8570a6050cf24b567e100716fe281e904f82afc35d26d8a7e3ec69a93e9d7dff48a91f3e84a11425b87d78a48ad436b86e9f93d5bc3350bd068519c0b412023096dd50f319214d88da86c97bbae14aee69eef217a346385981a05b580cdeb17180bc2252efb310e2807a1223cb7f17bb973f5b5045cff76ad010001	\\x4e7d29497fbfb36a5d8b4480acd67bf2743aa721d0086692988d3b1c2ba8fd1f7bc0c674b790807a496caebfa2ee6cfecffd637183a4c49b02cdee66419e8303	1661390788000000	1661995588000000	1725067588000000	1819675588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
251	\\x85f2797749006160db99d29212199be185e9ce4162707a74bcd5c27184d4bd16d712c5390c0abdaab26ba0404ffbd267d8cf6b2b43385d6ca2b5bcffbe8bb937	1	0	\\x000000010000000000800003d502d4370cdf4d52f23988169b229a12f2427c044d5f49c5d3957765a8661d10a686237ef1045616bb2630caabd95923f459a77dadd3ca464098f3a9cd6c99f21e961eac46d29c5abf3c218d7e58d461967bd659e639fb01986c5c6ae76369c369485091b8fa42afe342d0ee3cef04c531d6e55ab5f8e23a83d46b1894c49699010001	\\xb42cbe205160f4c55ae577c0a837b604974c38b2e355ee8b3755ebdf5f51a9fd6f1d6d4980add8fc93c1033b28c6c819dfc2c779b04824e2980429709ba8a60f	1666226788000000	1666831588000000	1729903588000000	1824511588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
252	\\x861e7288ffa58d351d743d110d86b10b5c52f61a681a138605f30f58062f71703a6fc1faf9f30769c022144379f14a2bee46b8bc6113a1ee12df9a04a69303e0	1	0	\\x000000010000000000800003bf08c7103b3ebc091f3aa54d1162d4fa6c056b33ea98888dfb0911a53c3e9ed962bea4d3e6f37e7430cacc20b7850ec96f78984401c101a1bd23da7220fddfdcccd2500cf7063d608eaaad94e079d53f7c4bbcc65ac921cab8d620939b8c9b97d1a7fb49992a38d384f0dd1baae5b46c2e2e281a87a3a4792c342909a7c9830f010001	\\x7b7f084f1f7d9d435de7b132281f6dad2b76572ffc9c85149e3ddbfde637a100bb5837eb878fcdc30f26ca279a8647fe47aaf034ae97dc7aa54f36065d2fd50a	1676503288000000	1677108088000000	1740180088000000	1834788088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
253	\\x88c2491b53b42ef63cafc6f2681b7b74bfe9b51fbc4d4731d3adedbe478acece21d50a4412b8b78a14ced987336dd955e60b4d61bc1be07380aede8555a0be23	1	0	\\x000000010000000000800003b60ab9406c39a46dfa8b9405aae7849b4832d7fead64dc0bafc0d6442b0f26eaa90dd7103a553c9523a01a0aaf99cf07ba721b484ffc16820cd6aa1e0decc79265b8e86ebe71ca154db3865ad3c044d52a26e52e9ee13118471e663ec39389f7485f7a97a58899c92e56e1510050f9d173d8b600f289a72154505ff7621ec0b1010001	\\x4238c69991857d39cec9a273c0f39d1919c8f919b152bd223bdcf8199ef1afa214596d211fa722cb6cd03e17c0484da98a311a09ec5d4eef257ffb7ae66db10d	1678316788000000	1678921588000000	1741993588000000	1836601588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x9016de4e160b17791b6aa73d0a1cdd720c849ff46b51e9c59ba4f3de944ec775f03e162ec804fe6118889d753c6f7b4f8a9ac266ba9d72eac8df10cbeb754358	1	0	\\x000000010000000000800003b98ab96c73b9506baf0aad012a998459981965a1c8188312ca7c65bacd3d5b9c32b821a962a241dff31b239a4dcc6984116d0b4fe2d39f35bfdc4d959760de6d42e8eebfc0f4242604d851dae16e31630d831e16690b54ec6d0cd9fd08eaabbccce2c6146d3ea42cd81f277d79f89d3956cb245b5b1a8eb2da5a01adfe7e44bd010001	\\x3693c7d269a045bf3a824185d88b886f1229e1803ddc1d4ebdd4a4b952ce06a4b75498c25cc72d8a72d8e1a69b0dcd78dc464893ef52fd0cd26051d77f1a1707	1655950288000000	1656555088000000	1719627088000000	1814235088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
255	\\x91e68c6481c1bc5eac6c89c9c1e2a4518d4b0719c0dd2f527daff30b857ace0a7e67cd4a6bda0bec6d63851d2d0ccc06c5de2f9389ce23b8c25b35ca2478dff3	1	0	\\x000000010000000000800003b0c75a8c1ce7576fb19eae601ab34e76a6ee1f6b4cd88ccf8ac1ead23449e3cd04d4601395603aaccc2696dab17ac039efb0b54c74ad1419fd87ce43667b32f7cbea6b57a6b86df055033fd1b2a6c0c4f1600fc35cf1e419239c3e63651c2c267df902a8d98b2ffb988c8fb4efdfd1331f2aaedde2144b22c45f7efc15b79cb7010001	\\xa3039caa72f1d88f010af47f2424339afaeb4d8f8ae94c6a51c7ff95adf8f93491281e7365b9e4dd97da9db94a3910e0378afef2b15e45cff6d58071758b650b	1652323288000000	1652928088000000	1716000088000000	1810608088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
256	\\x95ea17fc27cc276d512a35a8ccbb528549678cdb5a8738836fb5bff2d2a5ed61f6c433d65d578de8ff0bd706c263644191a5261bda0871245c724c47ab13d0f8	1	0	\\x000000010000000000800003b6c995074b6f19fa909119314b54bbad0c69950a2ea375af698604be8ff797b8e8bd7401ab0edc0179c800031bee2019d3eca79c2829236c1bf29ff291c9281672c868a220e7634b6fc79a49ffceb4fc16e92133b50c93815e2082f75aca92fa87a932cfa8976d6707d015f90140746b36d4a0a9baf7bb71a63f4b24ee79f1ef010001	\\xce7e34ac8e4ab0ccf014331f227d2bfd98cfed3f5bc8f8a04b4ac225008c9ec5bccf735bdd31eb80f7547c61682970a36e3b5367a1dc5351b34a7a7efdf8e90e	1660181788000000	1660786588000000	1723858588000000	1818466588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
257	\\x96e68b107f76bff7ee90c2a08106a681caab06ec3831500fe19daf7c5b7269d7d04b9a8d6ed6bff4de0fedbd8a14192f7d50a1b43887a6aa5bdf2616303f2f11	1	0	\\x000000010000000000800003a94dfb48046781159b51c6b489e2b5b911ef66b095d8e863ba4f12c5b89a7bd5487d210130b79e5a4e0c75a5ada5f50a2b3ab1d93b4ccf80a160c39bcf6f98a4b0ff53b70cbd6c868691646ce7d9ea4d0eb0f184a80c2f45b94f9faab9500f425788a7d4cff6f9661b2281f92cdb9e5cb96689fc88125b34c32d1b84fe1254af010001	\\xc2b29a945e4bf823c1f44fb2de52574caec78e4866de511ce99574419d33068fcce7592c49362eea117a6afbd107f05da4e363d7b3788f2075a3f4692f4d9b05	1677107788000000	1677712588000000	1740784588000000	1835392588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
258	\\x996a76f25233d412d09e7dca16622302bacdf7301dd5ebda5f611259aedb258117f91b73119c83d537a5af705940f5a2821326b155140f25483213ee75027f57	1	0	\\x000000010000000000800003a293d51cbfb5b2b6c6025bce99f5aec4a3784dd4ce9b1ed41327a59b2fff8417621d417282218316e8cdac6ff6ed8aed42551ba3a8436ef71aa297c79900e73392b3f3f21ca74402165be802d2ed13a87994ec715ae45215bf9ac3d61be2aa566fcd379e0bfeb4a877c4ef66c423d0920c6fac8654d758a79416923397f538bb010001	\\xae4f6fd6410946901e0feae0256478862b8cc503dfdac3b18f7d15711b0aee11aa58f52bdad294a5b6861d8f4c0d023ef91b258fdab589c8d5504fcf80511509	1665622288000000	1666227088000000	1729299088000000	1823907088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x9bea8756aed902f6baf2511e5361625b27b47f75394f7fb70dc6efb9fecdfa9c3878f442bbc3c092ad5f55016dd8b0d6555586f9f7770bff7b0f361d0f151caa	1	0	\\x000000010000000000800003be4b83c945e544e9159b514585325465ebedef6e1907f19ba17907b1d63b124ffbda72c1dd9a3dfd087db16c55f851e142a598209463f58090add1945cdf8a169a98fb806163dd99e6671c4f7c357f24fe9a4a0476b05b491e141c5824e3501f28418dedb9d3c6674e2f0f2d110a7e8be2a8c3732cfbb398e582e4f3e19e8f87010001	\\x4575b2c20eb8ca4cfd576f83ee092afe450ce902edefa04d8941e26f04e7a305c12009efd3c19fe33e86f5942e9b4227cf35ae5168faf66edba7a3ae72636903	1668644788000000	1669249588000000	1732321588000000	1826929588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x9b9eb23ff25281bf9c2522ebfaff6673362fe4be9cb5ff2e28bd3c3f45202aa63392bb42ed386baea4f2091ea60480d3f5d4fbdb56b25f69dacd526c11ce96d3	1	0	\\x000000010000000000800003e3da0600990885d0466798f2baa402ee8efcb0fc9b395b8f58e7544cf54a55bcfb7ce8ec953e287dc8eabb37ab81b77080027b50dbdd0cb985a57904a31996ce7239b8d2b206b25ee27e2f64a0c63e6bc51fac0e680b04cd9a6184defcfb597cd99c7242151cb896802e98bbb250d8b3c26ebbf88b60acdf27778a126b6bc625010001	\\x91541cb4c0a85a1ed4f2bb9e61a713e0319fce3a443a7c49c9c89a2c93b723d8236522e18a5477ba1eb67eaae4a4f1742186f515d77976f943fb8a291142e10d	1671667288000000	1672272088000000	1735344088000000	1829952088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
261	\\x9dd6485a947f05bf15153396d9c0356b6d07a18b8a4e4cf5c1bfa6e0ecaebb5077cbee1ccd9c8d80f1a1a0b4f98f7c25d9bb8b908f5fcb03c07c9f96958483fe	1	0	\\x000000010000000000800003db34901650f92cf4c9bb16d5daa9a62e7baf5b6807c11f0e5a79f62171abad8be93a384af5c5eb1454d6fc429d13c8fce56f99679e6f7daed6dc2932a36be3b68f7182482075081d29179437626289eb7b34dc551b1c3904270fcd9deda67072702dc49210187b55d17a4c89c788e898c2cdf1bc1eba0c03f9af43a471a3c755010001	\\x88861277b061b395d1a47dc4402b58deac97ac1702b26ee9777a0a2afad3bd916dd3cebf8642abece846e604f8aef8525c97cef8960121b8dafbe21506834306	1675294288000000	1675899088000000	1738971088000000	1833579088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
262	\\x9e9e89a1c9b5c13e0cfb3496cf0c8430bb90ebf05ecb9e975be9c2b37fa9a5faa2f96952e019e40db33d22c3f01fab88eef9dfff676c854962214346664c544a	1	0	\\x000000010000000000800003b605559505b6fb0234a7eb96256b56d0fb607a8ce63bff172db1ba948fef3f41fa89712a4de993efecf420e620cf8534bab049d0173c048958d482d34e7bbc6d5732b2fcf174b292dad1d78b6df85def732ba77e8a01cb3e42ee68036699dcfc10da2cfbd81ba211f162c06f8dc543889fc30d04cad91cac0711caaecbcb8a31010001	\\x3a121a5aeab226a4e1c83867fd8104a159d15d744eed508b6be2d197cdaa98b03fa13e55995322cd39e58f284dc31660915adbc62e55da5a54c80ab0e6bb0f0e	1672876288000000	1673481088000000	1736553088000000	1831161088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
263	\\x9f6e4eb8c3bad6aa16298cdf458b5ba2c5c2d10caf2559bdd3bdf3249bd6296e9a2ba82c6605ebf10c553321892b164ed134087f0085a422e88864908eee35c8	1	0	\\x000000010000000000800003f8855e52f058577ee997c45882d1912162745557fee2c1d8eded5654b81532fd2218b7ece148f329ae3ac6d95c8833351a6f799193d9002dac3a37ebc61d118b81a6a6cb76c6dd340bfc67cb0ceee67c4e1cd1b99eb3992f6738ee418de14b053db12b438bf7c8dbe14cce4889f0d22afcfe3c2fb301350f56ef731ec36b1315010001	\\x3acb7d0b11d16b368eb8cd760be8bf3f1bfab9a20b20733221243910e576239b8b65fb3999d3362554a6a5bee0e14c098af1b52cdea24dbd6f0071d69e26000d	1674085288000000	1674690088000000	1737762088000000	1832370088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\xa1ae968272dffed196b925f5ca73d85e9bc6d670f9187ebcf25d452fe001b6b64df638e5533146e4db2bce440cabd0a5dc11c55f128b202c7caa9387ed8158c9	1	0	\\x000000010000000000800003bfd00b22a5d67c2dc5f2df42deaf0d99e548a0a88a05baf3b9a26ef0d9fe9b5009aebd6ab24e033361f3ef8eb640e015f667afbc9082d6752671b41a716d705f4e3378ea253cd19e74e9017992f7d5afaa68639c221605a0708630c4c643d118fb467f215262d65b362a489d0733b684cabf30f8a16ae9350c29190834d57c09010001	\\x395e7c443705ae442d6cbae06ecb9ac52685ced2f35cf5e711c833f707f3c99c70bd35677404f6a361d97745d71bddbf6e5db64ffda1cba263efe0a69bd3dc04	1677712288000000	1678317088000000	1741389088000000	1835997088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
265	\\xa4fa6471a2e3588ab9853dc892a502506a0784dcc87efcc17aa6ed51713ee27785cf606cbe4046cd4e098ec47e5857f567c058ddf4b710d8db9cd27b684252a8	1	0	\\x000000010000000000800003e497a2b1952408b773bc0532e3f5c4a95ce015759bdf9e1b6117b3afa4867a722529f1e7fd108c364e00ed3d86e342d04808074c00d5b0e7304a393c4eacec4b7e8bbf63fcad46e79a54decece44178bbcd783b57dd083a1ce235782ab55bab8db6920dac30ab8ccb872a92a0601adcde79748911e1f2364467d6cc511f14b07010001	\\x8f808fee3e83cdc5d406189062c14556277398d33b194593f7cd98178eef087d65bc31d22197bdc192e93696fb188b646cfc8afa95bb9b401da34967907c9408	1649905288000000	1650510088000000	1713582088000000	1808190088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\xaa221a0c02289236e122d1fc4595e6064300fcf9a5b567571c6c3775d3188cb19bc65c78eb7b3a2e57be3b7c406a91e9f846a579ec98d3fa128e602596b932db	1	0	\\x000000010000000000800003bf90bb6a0ef16a5c48b8dd26bbb8ce197e39ff2505da2339b397ebfbe427a541d2de94c3c9a43f33bfe2ff580c978dbbc4b4e63ff343834bd0c58d820863a461d1081f840ff668abb69ec22ff7f0b7daa39f1758a48e7f4723235ac78cbefd4d7df4c3a5e1bd32ed587c662576d58977174ce36c9d23004fbec83431212e0629010001	\\xac840ddc3aebbfe33157d6cc24ba282edb4228f073f197a5ec562d8ce7f280c774a7ff8d6d146b848962b5449f7e70380012c7317d646bbda00073674e91ad01	1672876288000000	1673481088000000	1736553088000000	1831161088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
267	\\xab0e5d5dc1913e837c75096d2881777cdb62bc828618a1304f6e4b027228977dab415d2fc5fae6cd111ee1f24fc519b3fb773dc19166dc01638d11ec6372fa77	1	0	\\x000000010000000000800003dda903617f7ebe135075f8d0ad59cfb9d382673f8f0707e8deb1c8f5c23ef076a5852a835d88f2f83ebc0c7fc640a1d3f35fb7b74c004d835d30b4b5865d74272594a84f51f4ef1bca5053c8984b16c085bf8a5b67263a0db1d65b9891c85c8e9fabfc187d63886bf51a2ba5ce41717a8cb954000c4c5f6b48c4a1f8ff7013ab010001	\\xf2edddd90e11517335185ec9d22260a88a88ab7fcc4a430ad1452307f50361e550a3faf965bd5ef436f0ce7220476979c79f5d16719b236003721f53d010240a	1652323288000000	1652928088000000	1716000088000000	1810608088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
268	\\xabc6077c78969aa4902c42501eab866a4ab497ef97ac57b1c1f8e31bfe6e7e590229a7a8d389025c394ebb2398a52224e19f014142d5194cd0375a06bc5bc3ca	1	0	\\x000000010000000000800003d9e9e2a1839f768cd53bd959200c29ac44311fd4b83285be7fd3a407202ccf73aa1001f810c4107ab0ed47f12e7a47631b005ac3df759582ea800c6f2fcffa2d3ab4a061cb99731a61b9cd3c621faca23778475957fbb84d9241b5072542e44bc2829698ad3dc9f68511334ada13b8467cb75f251965d8457aed40d0d3413deb010001	\\x5f2c7c21392d0ba49af5cc75cc7d4976ec094b9d7c7194c5924bbbcaa0df0cf7100c0359b20a10d3957670913b8f86a480d72ecc5564679ea20c30c7ccff8203	1665622288000000	1666227088000000	1729299088000000	1823907088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
269	\\xb0b2700154f5bc1f528b3cf254c4539cef9d5df740aaf666a7422e7778b193f6f6858731d861d095b6d2b1b3123b755131e66f6c2fde08102969eb992870019b	1	0	\\x000000010000000000800003c8f00b61758ca5fa593ee1a755b6db04d6e02a102016ceee903050e718f3cbfb77bbf03a9a5663a9d109f839d632ad0e13477b6f40a8c3ea94d0c78f66c633b65e39e3a4be267bd5c8a6c47223a7ff3d9c5cfc7b5845bec770ce5eb24184e2f35d5dbf4854656ab0c001f653f49cf7cc3f4015f700ff4cfeac4e18afa6505e79010001	\\x7b5da8aec6898d32af5bd68e771ff5dcbfa57526001f82c4292e8f4134f78af3f44a3d0035e51e99a30a769f873f1aa6da7d55fd5e1478250c55247f997c470e	1650509788000000	1651114588000000	1714186588000000	1808794588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
270	\\xb48a5260c21d81be510828084f38cff62d15bedf460bd0662d6ad7eb8e51c2b8215205bda3de477a2d402f72c95e24fe74b3cb092d044bfb7a48baa3df4658f4	1	0	\\x000000010000000000800003d50b8e8094155df2a2370b9faaf7d96185dae33269fbd10fe9b2f98cf16fcc45906dd3ed4b73797d825df94b347dc4dff5951afb97d83187f245e748bf90175bc7db58d768fa6f80191e5ff31c6561aa2a47372491f8c3aed2d8ff6063d06efe887247dfbda54dad09200f324abb3230dbb5444a6982c509bd864d2022ea0c11010001	\\xca7f72caf7e8c54955955f567f837c7a2f671eecd72e9b100ff4633d8f7929d51be3f1e8baade59ae0ff51b066f2562a2e2dc265df530fe98b4ea7a2922f1e0e	1661995288000000	1662600088000000	1725672088000000	1820280088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
271	\\xb64600325436218e0a6a37e00c3ef3c6c6f7b9df96add9784fe47657717e15c43501753c07662df35b9c13c995828c1e1bf8d95b2368f8494164bb15d063db0d	1	0	\\x000000010000000000800003da1fecceff3654bb51b5d5026f98db5b227358d04cb35d8e7a2684fd9c0d3ad2be840d60ddeb3bac51254194b12ab5398c1020b358313631422e068b5961fcdb3e3ed6b731701f19c27bfb0718fb4dd3a96774a6fb5fbc378c95cb4b96da9539faa1895c9fdbf8368f1156ae584e72e7372eb87950c17669d96994ccac1b59f1010001	\\xac295d1377637f85c79da040821dedd4150d5d99a183a018cd100f886e923c3bc4f7cb2ef00d9c2784be4a122595fa3496ef3bb436e0f91db46ae9776d817b08	1658368288000000	1658973088000000	1722045088000000	1816653088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
272	\\xbc3e1b11da808ece628a3c646355193737983c0526d45ebcc87140cc73f9f803e6a44c1dfda28dcc7613becac91d6cd3046d70870cdfe302042a46f39159b940	1	0	\\x000000010000000000800003d4eafd42d4afad2df96b3169b96ffb7e827b23095ec7b329a823395c6418749e8d3729564430c0f91f05cf56e824459d387f10a4c443de34482de20dde4ae087763ff3e0a33da150cfb5402e1e6b4e7c37b94aa362f3d9e22e42af7c9030107f469e08253c6283d376ad0536d8171cd37bf4447f9fabb8bef16dab4c02a1488d010001	\\x2731fcd81b838a9ae03c4adb5832c695b7a2893d33b127853411ddb5559d436cda1459b9ad14c20dac474e5a73e34a5c03630e751634e88b9e4ec994bf78010e	1675294288000000	1675899088000000	1738971088000000	1833579088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
273	\\xbfa60ff1775978629f50546dfd060fdef917febe5811f8d4100e3dd820ccbb16999e30aef608b50e59dfacb17e308cd57db6f3d598ce0e03abf3295c1976906b	1	0	\\x0000000100000000008000039839f927404eb9693aed31c6dd4107ad122fae600e5c1c76839b939205c9c8a1f3aa5215ff534d547c731b222b64ca83283fe5dd9baa51b88d6a4f01d9b80848297c84ad4ef6f342b1589d4725fbbf743f711619fb433b605de9da19aeffbbfff3ed615c25e09a930ade2dc94c21cc3d712f469115c67ce75a51a31cb6349091010001	\\x687778b7a3aeb7c430baee84f1afe73c427cce69c86671a7b9a253e047eef9f93d08c4937108c6312ed5d24dea029ef5e6f6217e82b687db8267ba21b77e6408	1659577288000000	1660182088000000	1723254088000000	1817862088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
274	\\xc1ee96c2126df18e5df845817ef8176f18a6473821f3ca1865732a31c355488abc818081e564ca62f6abb4f24890e0683ca6dafdeaaf31d372761049c6058aa0	1	0	\\x000000010000000000800003b67f72c424403ec6148080171edf73bbcea1a0f919a8a1a35db9871d86cef7bf1142a9dfb55ca8f412b440572620a34f26733478adba3ca5272306bf1645a8996e1e2274eab0de2be0f14305b5267f9557ea2fb61b8a80d42dfca6ba081d44b063c9e52e59395d9d42a7ade9e4d5905c4ca2220db711fcab5479bf97db2a0437010001	\\x4328215602b4a88364f90ab660afef5c8e81c6792247a481861ccf44f33b4d21658760c3764c0ccd66812ccc32381532e5fa7acb30c2a4b38724a5a038e32208	1660181788000000	1660786588000000	1723858588000000	1818466588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
275	\\xc1a2ed663643f569a3dae6f94155266183fc9dc1ad5fa6c567217c9047363760f196c91fce4537f8a2d42ddfc3ddc3e245836dab5afaf19ad54eb923e356e3bd	1	0	\\x000000010000000000800003e3a66303614d88c9055852a3739ad4452e03662055aa19c5101e884fd04bfc7a72353d515d3c70021d44e136dd4613bf4bb92a03b4c385c725121ef0e0ea3d263ea8aaafff14ef8962ab0c335b0175890fc11e2d34ed9200bd06f468ad3777021ff932e15d4c12c8f66fcef6736058100f887d149b3473a1198b916f96be9d7f010001	\\x4e2c4ce5fa3ad85c1e2f9ece952a71d68e933f78f823b732221a3cff2c234d0d95333914a1a0f76ada4c87f9c323d5efc914bdee3b990bc5b39e7363afe25903	1666226788000000	1666831588000000	1729903588000000	1824511588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\xc2c6bc3d5910c944c377b5db8b1cca4f7ce3570ef7a6a535338ff9b692bee2a120f7e24f4027287dc35a101070ae507264e09e7d1f6d75bd24289af3c5a93894	1	0	\\x000000010000000000800003d7514280dbaab752e5009b34c524d34126183b6d7d84c22c4c2d3b5e9396d6ff7251666912b7c71497d075fcb9a7ffd36c12d46bab0b72c2294d87a6825cd637da3669de14987cb34e94af463e9d0f72b7f867031cd1ddbc3e8264fd458cc88912b15e593f1ffae992c2ef9827d9bfdd9ec1730fcfaab398d769459e2974bdb3010001	\\x74e72c03f8f972aef7b48f007b0e2f9bc231d3c69476b7490af188ba1df45a84a8d3cf445f4a82bad01614902635783eff81a8cd8b354c680843e69c2657950c	1672876288000000	1673481088000000	1736553088000000	1831161088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
277	\\xc28ebcad4447f7648084c9e128613bb316359eeb937b8daed1fa304d5af57c73eb2c55c9aa45624d314fbf6ce2a4181fc9b44e9b9a3a2b3c583e52bb239655de	1	0	\\x000000010000000000800003ba9edf4170eccc662fdd30b1c43246d901846426e0ae61d2b9c74a4f0e576f6e1f75789c4a49623011cafd3d2512a7873e4d817a0fdfde007f8993523dd6c629b3120dc3b712e94191c5b377e6d1c918eb87e70262b01b4599a1629d174dad58d012723aedb65450cc848d464fa78c183b16d8f868b3684c90f661f36a241273010001	\\x2f2358635315b5822b70e57e3f754c5204658f771868c41b463599b00ad1bedf7388c0eb810a26622f39e29f1d18fd5d29e78a24a98bb490c62d421ac1ce450b	1672271788000000	1672876588000000	1735948588000000	1830556588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
278	\\xc46a1c01d3a4177d57c62a574b3ab3b19fda1046f2b203fac9af1d985436e251d161669ae0c67a413f7e60f18bc3edce683d245b3fe56856a756031bee94db41	1	0	\\x000000010000000000800003e9d7fab350eddb88431e0cefd6a0c8634ad0add15fd9f1d04cf1424f05822ee0657e7ba561d121242f9eab1499b2986d98e291ffa38c9f7494489629e306809bd93828213ea9efd4b97eb796e2e7cb7de41e5f1c82273dbd88cf0dceb05c7e7d57ea2ec8c6543839d6e89ebc48f2d2ab9bcd5c4fa66aaddfc6fea03ecc8d28ab010001	\\xdb235d905156590084fecc9b512ce58eb1fe7bd7790b4a130761cd893ad72c7e7ea8bdd737ef4d3fe1190917645928372d96c93d3ea9f69652748cae6d2bfa0d	1666831288000000	1667436088000000	1730508088000000	1825116088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
279	\\xc6023f05969b9b573c6bb2e1d68cf059d85ce5276ab115caeaf4c83b98ae4ec7e1ced62beca9d4258f7b2235a3e978876bd7a30686a1160a9f6bf873df2ab9dc	1	0	\\x000000010000000000800003aa248b6ae3f838660751641565460933f05785a7eacb96684f4c8abd5c8edb00381f9af566bac3a5206f795283202576c763cad4ae5587f27c44e6c043d6ded1a4709757e9c76fd1f6bf99e9ad3cf534aff728d24fdf7d62a717612fcd1b5dcf74db771bc0961c173c28b7df8c5bf585db0ec33ba66514948ac652c5f87b2df9010001	\\xaaeb2b9f73d87351c33b72ea75af89b5ee63f3796c251d8c9aa5ec224e644c0909c2b1fa560bd5faf5e3d41427b6d7ec7d9fbe8d55ff23739ba714b4e94a4f04	1661390788000000	1661995588000000	1725067588000000	1819675588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\xc8a28a17473acb61cdfbe8ed7c240e37b0fb5aaa4c1796a0ff53815529285a2654d3b2b8ce1d3a625a09860b41a0d1d78bcd62a07635ab4fba6a6a5cbcb09e35	1	0	\\x000000010000000000800003c2d9ef8fe7e68aeb4487d3f65b7d6524ffa165a622fc08dbbc5309056d3a7f4d63411af4bc716f0b14ac45e99de7e77ad75fd907a51eb7d57725a94352fc304213c5e5278ec91fabaffc04ff77a6c577944fadda45469b5794ff6a769bfadc2f51cdcd7eac0a7293f012b65641e3923ac48b11f8103aeb66106df8f23cd82ef5010001	\\x242a2d25c1a9c63427df73530233a27c37e4cce4a35047588a550ef275669fe1a087bf4a730df2850bdd69b4c4c9a99b4316f86d526ce34f6d4d364f9957610f	1662599788000000	1663204588000000	1726276588000000	1820884588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
281	\\xcc5a3ad48a6ad585dcb157617d32b4e75b3551eac6376bbab639ba0afeed86e69be6d2f995ff0620f193f9b5ae260e8dabfe4469942be782b537b741b95ad680	1	0	\\x000000010000000000800003d737463705ce209330e3dad59a94e38d2248a340b066de413ed51650d685177f608f76b0cc581a1cf4e152c1285f4d0be41a6b710f390d80378d115d8353e45cff82202d54daf1f97f662bdab30372e0f8e1c256b1894234f225ef8982789ce2bdf515dc9b8cb1ddc388876c4b95f4fdf0db5a2686f7f9242c5cdaee5d8b2971010001	\\x038fd0331266c0ebf4957b6bcddbdc8cc29cc95507a7bb68e9ce2b26e8684133d6df08120337f31afee18c03f49037dd52983f16ec8e6aef9c9f3201844c470f	1670458288000000	1671063088000000	1734135088000000	1828743088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xcdfa400e3b2fadc42f8e55d903850bf19eb7c7c24b0ad3d5647b831d0fb5330b4d4be3b11902e3841aa922a14c7ad780af5cb3cdb8347f69b4497858438080f7	1	0	\\x000000010000000000800003e98fe3a9d4e7c14eca752f51da0eec29d1dfcedd0ce22efdac254a12907da71c972d12a3fa33bcf9bb35a151564599c125f60dc87c9585f27abd75005815f1bc8107efc9993e6cf9bba94c64639129855dd4f90915a33c7aaf2631a53bb586c5819ad77d6fba31719f5e83d51db1c242934450c132cbee4532fe1f52432b75cb010001	\\x76590bab8a54ce5e48860fe0f6a17a1b568c79ae1a9a256d1dccdd4e2e8db81388b057cae9d3b47b7a6e760273cdad23ad7516b508726104c0c766dac5914f02	1678921288000000	1679526088000000	1742598088000000	1837206088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
283	\\xcd327ef34c4013fc1e5ec1f977d54b2d2b1a73f6b5cd681061fb4059ed3abcf493be1fc5a9e5a8568501bd7a676243158139a42311b016dbdb6b37d1a50e757b	1	0	\\x000000010000000000800003b3dce2b83cd7a779d08d087cf5d3512491a5e06ccf4f183dcc437b473c943b6c4cc731b1835d65ec64e475205bad77250dd719161176f174f7a770f6932e74138ade1b0876f4954dbd0db325d711f3f5f040af8955eb696fc7e9d29529520a4279deef911104cd7f9fbef991c3dcaf17230025d8d178930ed123e3d80f12b887010001	\\x9ca2a397745f24876c1971fef2065594404c6b82981246202a6f0d5bc24949eaa6382a753ea8d722cca3163688bc63ab01db080550f20a842d57a279b1fa6704	1675898788000000	1676503588000000	1739575588000000	1834183588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
284	\\xcd120f641f28610e25700dcaacab75304ce445017c9fa2aaa846d06e7a9f1a06860911a3cd0ac3fc01d6ea5e10076f495a4374edd28b0cfc2bfde833d5ababf7	1	0	\\x000000010000000000800003c813dfc86815ced5c0bdc9eb0f235011d3439418f9cd8f248ec53e81ef87a6e0a98df260ec2a574160ede56891136227d4a3c258f0bd3d884348d7e3ea998d43ed86026c67e6d1ec805af64f5bb814d94fc964eca815c3872a8e2dbace20829ad67303dbf1e8141eb025ccbe97a17601e0b2b0a3d16275f05e619da6fe4aef43010001	\\x9be3f59786cd123f45b32c6bfa5e5396e028f0824804bc7080bb2f370e2d7fc571837a16020e34212a1d3ae829aeb021e4342e98238e7d1d9a1c227b2c2fb304	1678316788000000	1678921588000000	1741993588000000	1836601588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
285	\\xcd3a820379814b94238f43e5cf8333c2e59f9b14dae5935790cdc56ce812af1142f956ccd92f35c29547510c3127d488bdf137eaf06b569f996ce5f4baf16ae4	1	0	\\x000000010000000000800003a48966463077bb27989fa861482d1ef7014f28ae9241fefe0eeb708fb5f58d2999de6aae1492ef8fc84fcee1fa3e678ef249166e55325f42669de93c06b9f18c0dfab06e5e9b2b5f384fcee8c0412c88149542b05a89ab34a0aa4e5d52c0dc878f1f51cca8473aab4456b90a23545d54de45ff9b6a071a4a63e5e6460ee281af010001	\\x075aa3f298c09f5b3312f1e6926acbdda852460f98e4cc79ea68514e578ef24ed689ecdbae6ba51a33132351ca49de82ccb8100532ea55df4a81391478df8307	1670458288000000	1671063088000000	1734135088000000	1828743088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
286	\\xd0564b3a3989f33fe8a06e7b2ae0b784f3f8c807d558caf5d18f0793110547b033a27c7fc58f9fb4b9f719eef1ba23bd047f74747339713d168d4635d5e97533	1	0	\\x000000010000000000800003c38225784ef14545cf10de57d462e9ce578c79b8c32c2091fb064b31a1b803c5e1d47ad3a647d471edca74c2dc8c0bf54b742a9e81e008e3e2eaf3fdad42dbb868ecff9235ff2652a1de2576aaefdece9acb5497749630fd7de2e8687b033205bfd1efed5f45a798402147f4890b813b4b52c242f60130bfb65d01ee6776ea15010001	\\xccfe2505d2d503d5d8666815e97de2f044c83325284cfbe7fd1e42c1fa537a5b7752405402af7afc7f4172a37963a894a7f233fa282afa03831fd618bdc8fe02	1659577288000000	1660182088000000	1723254088000000	1817862088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
287	\\xd32e555ea028d2d19bb24d1d853b0d01faa3df85477545d9877e3f796f18ca749db047ec91f16930ced79f7fbd63bbd89fb092b42b393b2176d2264ce0038590	1	0	\\x000000010000000000800003cb17e4b786e366ac1607fa17de15b7fcff2cb02438f98ac75e57d42ef61a7599f4f2ca990902653f586b9a1192352204f29f0bf9fa0af74af3caa55023f6bdce1727a83dc20f10f86d8d4eaeb523e8c3d7f80642bec6edb2fad2a95a884f4f8b8e42c7535214ad8118da6e52922e9b90554ad4a7b8b7136e3fc57b4b2156daa3010001	\\x10490010d7b4ad300d97b57b9ca812c9ec792fbbe6cce57144823508d48a93cdc63f67f744a006e8545316db02ac0089387144302c830256bc09dae033610801	1669853788000000	1670458588000000	1733530588000000	1828138588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
288	\\xd3de20dfafb5e1722727c9a4d96a41cd5060e45f62c2af76d269f9b098a56e7fe6e751964edab6244763a5802e591828e742b489247f21d3ce4fab607890784e	1	0	\\x000000010000000000800003b85b2158b32f0236a2694ccfe8c27d23fa6f965bc3e9afe151d3da155154ccab169bfb6c60178bc33922df4539c2a480efdf949d2516abd5d4b332cde4c9b297c17d4eb81609bccf04eade2528d2bd2c335795adb3a7bd4ae5074121072c2749d3853ab3aaa873df31adbc1feec4be02b3e4b9d4c833eef58182d95d98e85f89010001	\\x4fef76956ff44f31e5309010338c9c03d00d8dd82c00506c538fe78465500b7e611821e1a7b347bb7ef4d5ab65a499a81d47122f1561c13cb1031287e51dd00e	1663204288000000	1663809088000000	1726881088000000	1821489088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xd3ea2742ca00b14e10980c4f27049fdfceadd70878b77e8be4e8ca7a662e64c6afeb6f91f7d3176bd300789daa31f01822d20372192b29acd1ffb29a16e755ec	1	0	\\x0000000100000000008000039da5f877dff71be5302e01f7e8dcd9023401492bfbecf38330ecf8ec719922809c7938a291210083754b710385ca6ff1a1f1102954f960de504242ec0426a3a71d818765d72784ceddd2ee731ed62608bfb1d32c4f7caa6cfa97e62b7e02776664119fc405866733ecea01439c1636bd1c9d7685ebf2a269cd454804d48e011d010001	\\x29ace5a92f5bd73555eb06effe2281e1cf24fb62927f256ce18fb803ed77367ab7609e73c29f0840ff62528a8eca4b9151560ff2d7dcc9f5b3e26195cd28bf05	1659577288000000	1660182088000000	1723254088000000	1817862088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
290	\\xd62ec8f823b808003f42b7ae1b45c42f7dc0a42860fef8ea43699c769ad9f150fe305c0208da1df938063d68e3e68a68540ec5722c23f375def04b64db3adc7a	1	0	\\x000000010000000000800003adb506c61da1cb3ba0f0465e64195aa2651dd24e259ab8ef3970ddac0252653383973946ebab163249bb7e9aa69592e024569aeb1ee811bdc2cc5bdd3af6ccf48a8122f96ea37de0851644a4249a986e9232c6e470af621096d1d2e808f3664c5481cf510c38d76c849453b653ce92ce9ee3e9c074bf12e7a58cb2c05bbd2337010001	\\x11805bc73255b00d99f61e197bddcdebc24b0682ed513c3af31ca57f104a8ef83ca482ab1c24ed78b5671d8e4e108bef3c79c786ed124b7d0f59bcd64ddbfb05	1668644788000000	1669249588000000	1732321588000000	1826929588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xdc7aeeb52d4f7d8397f349522701293cd789bbd2385c3707a061f80ad1920ef47180a8f4f66ecfc96db7b147fd8a75369a1be704a11c31bcab5783f9617205eb	1	0	\\x000000010000000000800003f4a93e86a1171c0970f7083d4a77a06d3413df9687875755cc33e8388af1fd0449ae81489966b4d3949aa71d18808faf7d080efb4f9612e95a2c78c859bee18309e2077c53a917ab80be1976d80fb41acdcf9da56b07ca3971cd3494b0a7d167d85d94348531b15a87cea449b83416edc8fc8dafb92a1e87e9cbc10e1c8f2a83010001	\\x431b62fb2381fd4017e51c5c346356c0244d0e3cf0a158ac6509b2dc5fa63b1bcc4fc6860d17d1b2e9bb7406637aa8ea212ebbe7e6fa30a2d81ffaf978301302	1648696288000000	1649301088000000	1712373088000000	1806981088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xdc16542c32b98daabd26e5df69a3b4137ec4a98d945587800d50ae9b520ade828245d255cda9953664f94f9f6de11a50d2c123c44a89724e2eac9137f0de0334	1	0	\\x000000010000000000800003c1d4ddf465748ce2343c5cc245981006425420c405110a0c938bd29ccd9efe653adfaefb573b15a708878c43e17215f3ef477ec1cbef6b9fcecf80cd545a21666200f16d14cceb7bbec768fd4a083fff9c469de8ae51c6a500aafd2ef683ab5f323a0dc97928b1ec4f3cb102e923c9c44984feb278091da1a1a8755c1a0db265010001	\\xde3f19b40947834c3a15d2c92d6c3cb8ea54d06e10b2926fcc73a7673938e1b2a708171467918da7f5d6f2395e7be5be3eb02d1d05f45defad9da6c130020500	1662599788000000	1663204588000000	1726276588000000	1820884588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
293	\\xe09a7a59d5bf861ef531e57c254c601359cb6ae88df34ba9092d198ccb200b0ea36e87f36ab109dc856b500521b380efbdfb07c110db2ede7f7d8b9897100dd2	1	0	\\x000000010000000000800003b20ad8a76ed3e392fa5734a54ede13c39c498da51ad7e41cd57b8c5cceeccc52af4e3203c32759423cf9ab96cf1fab07e6bfdf37382b7cd411cb45ebf5a80a5dbb760929adff82c094c523492ad09bbdbaef775e4394865cb5e6c5275197d5313cb85af5dd8143e4292afbf7b63b1c1f9b68940027cb6f6458029bb3eb72863f010001	\\xa937a5775d5cc779b48fdbf4eccd76a4685d6bee2d4978b162639071c75050cd099e6bfb395685344e5518c06afaf5c59ac865aa0e1bb8e57f61d21d11b09107	1664413288000000	1665018088000000	1728090088000000	1822698088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
294	\\xe16e540af1f6767b347d3d3d06e52107601441864837d553d1cdec27c95de3a9f7e1c210e8456910f3f9be8b81a513095b2a1737a82782b32c86a869f0a59e66	1	0	\\x000000010000000000800003e275cc4344e2226061e13804d34bb9394e1e63a96aee316251c5b89c09a91e89fe0a892692ec7f879313c296fe8482d2b4760912e00dc84f1c102d50bf81e623418266abd5a0f17382f492344100b74cbca030d68e1b1afcb7d8c9f959291bf9533e4752cd994d17751dbee9a7560dc25776d2206b3db243fd4b3d8c3ac576ff010001	\\xaf28ef13b09a5970a2046e6468959cfd349175ac0463d9619f8631d0bf21ae3bc69a4d00f55f3c52599b2a098967bbdfa2c5cb76583789412d6980cc14063b03	1653532288000000	1654137088000000	1717209088000000	1811817088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
295	\\xe24a958864b2518a9e304a548d2f7a657601e27a529d20e8690c656934960b83a87b973652e787bf765129600893abd411509fd6630d41fec66673e9446f3121	1	0	\\x000000010000000000800003b63dc86affef83d8cfcbeb23cf2033f34a5c73378759ba9df4bd484708664c856c82ce20b212fed4d390c6aa0c2ee49ab0def917af3b7f30a89c5d1df3aefa966dacd5f4315c8afd87e13f45f4aff547998134349896a37477cb6fbe4846ebe63cb3b7b4433cb76a4e5128c705e8596cfab1b1d50ea047213c9ca60d7e2cef47010001	\\x8038d149d8034ec24e7c60a24322092e637e9f90e6406c745ed90a211ba0d747b77a4d732af405f2a2607741253b293b0681195695230769d38e1936c414e70a	1675294288000000	1675899088000000	1738971088000000	1833579088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xe65a2d87a31a8818879d106bcf65c834c633d64f12c73e54ff0ca1f289beb31f14ef9c735b0d78811ef03ec4011b59e076509c2b22229902ae12254484e723ef	1	0	\\x0000000100000000008000039df2adbd39f0e88c94a75916faddb1c7fc2a6dc00c4ea63f587a95d6a355145c81142481bba35d1a4f06280172b818c3bc221abeeb810f0da558f4d092f8f952c0f9177d3a3445874ad17149318d2bb6af64992107e524be807498f66dbe76ec19da9675d027659c472d9c10a6cbe4f93d50a0340c0322816421e123b42b4f83010001	\\xbbe9ee465b7d6e02fcc40b96e6849fae09d4c67545b4eda21ee5bc6d4042affa24a2c0acca73a76f3e00920a8726b070c5b546163e10ab4c2c125a8ed9996004	1672876288000000	1673481088000000	1736553088000000	1831161088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xe9e6171acbe396c486017d191917e33b5457d649f14abce67e7afbe1e9e6031a31b173d4439b1d95934aacab307689210247d36475e8d9e07ecc3c9d3a9d8998	1	0	\\x000000010000000000800003ef82f70cc0faf9c06ba3e566b0ea50517eabe991d2ad38a06a420e517bd86b3ceba28b9474f577c45baa5d27f2a46a4ec8e19f95088059e7653d3ee2d6c69706084630079c250bd6885f21ac8c0422282b743bdc9608b6bbf9b7f62ea0dda7aac02059d139888e0f334f5efe6f520d4d0c2d7103d59b817cc773fa3287ab82d1010001	\\x59cd39858517585bd02a11801a1d9fae8b751664b7c7c52a1f4cb623d44ca47cc4e4bce119670229b42bdc2df27bb404e270d5181f2f3043421a79fd28c11207	1667435788000000	1668040588000000	1731112588000000	1825720588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
298	\\xec4e81b836d2a460f678204a74d617dc8e59a755668a8866a6c9956b164379c7af7cf8019e6642376b0a294833a9b6391cbbcc0e9e4cf51ccc340c4e43fc0ff6	1	0	\\x000000010000000000800003df2b1afe601114d8c65006d80fb63081b09920dc1968f32f6b34367f2bdbb361a5bb2a1247ce27f6af4e2bcef07d1fd98a4fff87c161e9e4a0e269b1a1130325ccc180472714112e01c6cfe98aa12378489954cd4f987762363f56bb982b6ef07e8045fe20ad6c86f8b8d74e98458886ffa887145cc1995c41241a67952f6ea3010001	\\xaad65638d64480fcfed06ad40c8fbcaf3390d3b69832f6b6a0f9f8c713ddc4132f2e6a8a746cd61c1e17016d287f51d602fc8de7ccee71125b2dde4e08bafc03	1661390788000000	1661995588000000	1725067588000000	1819675588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
299	\\xedae0ca715c8aef67d227a44cb70300bffee916569ab47febdfaf44091a3d828d0c75e148c26da536476d333d182a3529b4075df24ecbedd547c5f65964fa4d4	1	0	\\x000000010000000000800003dc876e9358e2f66c597bfbbe101651d7c0f179f93df499282133d7475ba2e595f5a5e0f58fb9f1b7a41fc602c6ceeb71fa92478b3a312c11b2e9298e0eebc372c75921394a97cc14de56aa23456b5c21ea07560b26eec0523a94502b951607c32268dfeb6b88c6fa1e948abff7d54799092b6757b9a5e287a30db9529b950c41010001	\\x19dbe495bd4546422f6d6aefc42daf199d4b9a8eec06494ba8e3e2b1c894658f5df5344c7d53b886bc4cbcfbb49f365812a0b9d9eae6b9fe2f80f617cf883808	1647487288000000	1648092088000000	1711164088000000	1805772088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
300	\\xedb21fe3893f83146a587ce593107d7efc91b8e218d962759748304a676a781cb995dbb45b278dba0e456cbabf3243fd34ff5448661fe27fe35f6988e6d4781e	1	0	\\x000000010000000000800003bec179f8d2c2b57b1fdf0a49b01a8ef3c2b5832a31306db9b82497ed002825105fbefeef27307ad02a9a666e1dfda334355d286485ac8b4221646bf8a1edbb17bc865135870041128e409c3326f49c691e8ed84e6ebfbec3cd96f8f9ae5f0c2d1c7800186ec8da301a0c11bffd9da0012b69263fdce162768e9d54fc47374233010001	\\xcb48c2e31dae331dc9d9c6ede4496df596021e811dde87642350468d8ad7a62afc744ddbacd6e2d6a558315c3b21c32050dbea729eade6121b88f5f857311e08	1672876288000000	1673481088000000	1736553088000000	1831161088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
301	\\xf01aae54b0eab3d29e6bda3ae3e267294045dda9c1b11d63ca71d2e63c1d16dca61ab157d78400351461d4908ac008ec84692cc9d21f0abf6faf0bc16d0455f6	1	0	\\x000000010000000000800003baf469c72150b220d65e5a0ffd3ac6c0839d4bd7a7eb10b7e793e07eeb9effab6eb5735a142b1bca8564a3da65513b576d48862693a9688d22ae8cbed414473270e3685c5e0c352cc9edb58c021b210154cb815dd2226a5211d13b300fcadce4c6e04f8f32d21fa72a9cf1b129c1df87d4fe900261bdebf8eefe06d8db2a2c05010001	\\x1d5cdd03d4aceaaf23a5567eee23e0ae880849174e7ea113ef7ac0968b415b12eeeedcbabcbf30f67daf628a8d8620acae180606189301163f19bf49f90bf609	1659577288000000	1660182088000000	1723254088000000	1817862088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
302	\\xf3823074176848cf6f637fe99a968680104e0b042efaaa6935691701259e06322d21b215d98c98eeef76673b2629ccd21a5ae60976625b4bc16098d767760f1e	1	0	\\x000000010000000000800003bd03102dd0759e74b798eaf23d4d41c7ed6fc66678ea93b634bdba5fda7451310f879fb5bf7af3cd008f787efea0384174fb3903255d6a5b24d41b4f168ac20d4e7f77894eeedda634aab7736faa6232c4adf8877537b9d716d45bda2568ce3a7ddd02abab9a532299e9fe1843c1c926e55391e75df9cb340c1abbe9d7940241010001	\\x4996deb9b639143e5d95ca830bb87bda31f3455c394f83969b690f8814d1eb1294b770bc7c8c5c7479f82627af859af387b1233666e9c7139ef38e100f6d3d0b	1649300788000000	1649905588000000	1712977588000000	1807585588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xf6a2a9a67890da2402b722817d26ade8637b098d4bb7c25f67c7862cf97317404da607d522adfc2bd8736d5dc25c578ada4133fba644add7a14a702cc8f377ce	1	0	\\x000000010000000000800003ea5f8929ee7db219b6cf92fb38d3ea12a73209a1ce56b7d3a90719e5226568dde3af238f3a4688c133973d74e96b9be62a3570c166a1a60b9455f4ccaa7afe78ba054c70ba5a8fb5fa8e1be192c9f121285e113163892667b58683c0b4d6f8c2a23790502d6cf87d1637664e8d59fb406335af7dbf1a177b8c3b75580666a5bd010001	\\x4fbe055d8c1f872121f182301eca3f215808a44e9a5aaa85ed35b409ac7ae3c870475493f5f161b554ca7160564956994b3d6e760a4d385ea685a428762e5e0c	1655950288000000	1656555088000000	1719627088000000	1814235088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
304	\\xf78e84ed9fb088a73157c809545aab51ca68af49758edeccea22b793c185a02742dd85bd7bfe95dccbdc37c57e1454453b5f35ff8b644fcd79e677ab330a1a4d	1	0	\\x000000010000000000800003c3f38235d3a537ffe5dcd7b850b08f5ed111b471f8d3e0517d0b9de0e18eb3a89af48118688f5f60ad5be4c1ca5f4636b81421b2c1531717ab0d80e950996843bcc2391c8198711a685f764e7ed3b5576224ba7785aa926b79a4cc3d9a8c6385c8451421ffa0039551957181b71a3a6227a1612dc0868f22f43a81869869487b010001	\\x7d655751827cfe6d193fe76241ccf4dd0e46c14f73f486c29f1ca038528abea5f8248a5f45959ab807a3909edc1fe5f971a78dc7e243ebd2de26094b13371c07	1654741288000000	1655346088000000	1718418088000000	1813026088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
305	\\xf8ba5d303e3e76b5c7d09adb8917dd549008bf61e182376138a1e472f12a08ed30ab8e0676a19d95787c2c9fbb289c0a8d6123dcb4da1734193f22e2cb5b4377	1	0	\\x000000010000000000800003b856ce7eb0edb4344ddae12693e8ebcf13be118399ccee79b68499a76e9dded28c06bdcb1b22c29f1c4cc17b997c2dbc4756f44241a7cfde85a4249d077bded902aceeaf57e3fd0c58d253cd16b3c89030b42046e156f01a7f72844df29425f30e97ef5a7c1dd060ef9df6353996bfc9115f7e8196edbf5784eda1a8736d5c87010001	\\x568ed5ba0239779f2658001c5b57999fb11a3042411f9449cdd1fec9498536c8b922b6cb39eebc320763d8c94bad02280fe909d7772484c4ab8dda1043d8860c	1652323288000000	1652928088000000	1716000088000000	1810608088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
306	\\xfa9e8c0e54f3835fbb402246764e760b469c50e2f9f80918f3b7a018f6c1c2a5ee4bd46894d874f89f7f5bcbe635881a72e12eca4afda2c6542945d55d3970f7	1	0	\\x000000010000000000800003d089148937bdbe82ddb7e1e69405799e246ac4db147e0723ac29e543949b07f9b90cacdc5954212c863391e5d4fba17afdaaf6791900e609678af2ef65dda18885b3f7668222ce0076d7d9d1ec497be9e5029f907790c2097320bb9743d9c2208f048bd246dc32d77aa8b6646f4a0cecdbe9702d62ce56075fdeebaeebbfef29010001	\\x6e17c2a4a3c03b9e91e2c0d112102c72220a6e0c163734e4e9d5ea4639788f904a5fcd64bf03096615a79e1a513539baa925a3d2aab848f28c1924aa7c704901	1650509788000000	1651114588000000	1714186588000000	1808794588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
307	\\x061fc7f7cd13d36190b9dd501e25a2d1ac8aee4a062e781f77b90facd343b9bf938ec572d3209643c7d813e7460d1e616fa76034413bbb382ebd1618dab422f4	1	0	\\x000000010000000000800003c99d38802978bdf4018560866c74514e61e2b7c3601e12f3572f957758d7c934652408daa777f0aa1afacad03116a3b0e22293c0e475676fa584314c368e32389d32ad31cb033c06bf0ce81579f041b37539ebcf9579f1d7fe87d6b2ba7db5d8c3aa23e5f455dacba18b6b35f550cd8388fe7d45d2518a4d363c06da89a27843010001	\\x8e405d418e56fb79abd3cd4fa77de186323d8ae1ac33ed0c58da2c090d6d2aeae7b2dd4a657912182bbbeb324d48134665b3ed2897536d4d8c1127bf20d28809	1666831288000000	1667436088000000	1730508088000000	1825116088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
308	\\x0f27252a128cf65345ac19b0d60c0588edaccb073d280a8900359459311b9076d67af3f3aa041e13e3c49d6fe800bbb0a7e36fba81a7ced8637f307924218178	1	0	\\x000000010000000000800003da3279032f686fd924ea35249f02041708ede4471a54221421e5774ddfbb1f1b51c1976bf7abcab88b23284b531bed0e0640212387afefacb03a9df73c415387722694f4eff3910e4dbe88d12704b679ca61c63ed1312816ce4132a3a345ec0acab0371fd9ac264bf2f19a42b113b3c29b00ab3d46f4294f1cc9ba391348e86f010001	\\x0dc4f43913214547a2b090f1ce14f137c1385095cd88f410de75e37ec62228fe19331b2fb63bdc73853d633424c69b07c705f45e5d3d33e72fd678fb77b5700e	1658368288000000	1658973088000000	1722045088000000	1816653088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\x11b3454f4dcf3659fd6d64f665f5c4ec9c175ba4bdb36ea57e40ba267c71841ca16c9671b1501c52eaf77622cf607a4765c256abf5ee3062447bf9398803f48d	1	0	\\x000000010000000000800003c71cbf3a012e1149649989ef8029348d45db1edf171eb3df3b4cada47367f8913d3e94a0fd9ad5edefbd6268987a0c211d7a02a46aa9203a4d105379d61b7b548438cc51fe63d984dce822db9c7535b6ecc70867b2c0c44ee13963dfcedbfcf040caac7f103d546c595aa9677afba0e3ec758631d51d2d8b9c9ffcff6ed0dbf7010001	\\xfc13d76a128a373b4bd80f220000e47f8214074d58d98c06c3208859aaeda3fa748503a11dd4412a0cdc45b2f10e4daa9c003af801e57670b1877fe5028e8800	1664413288000000	1665018088000000	1728090088000000	1822698088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
310	\\x12775f41fdd77deab487874b83c9dd9561572b4a5941dd072249d928ac06d5024b275fd287b6b98d8c6389f8e1701100aa8b3547ce1f4764ff5cb1d11eb101c8	1	0	\\x000000010000000000800003e46db09418b537357b01726c7a1de7f8ced800a1ff0696e007c09aaff10df0debd2a4e7512bf664c5bf5a8fbeb04641f6970a2c55b9c0d5b67527b3791590d027e58ace14962f2708711859e9753acfddf4ad22431b28fe7f64664cdc142137355cf18b6dc337b94b8934787f6a97af9f110b3ff28e0ed4de301d39debda1861010001	\\x920ee7c475e9b6c3f5c88e53bf17b46859c47e40babc05d3f2cab4c05ed9cafa540b6be88be66f1a1e14af304fc4c4400f442ac87055f5e1f0daa8901b273607	1661390788000000	1661995588000000	1725067588000000	1819675588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
311	\\x1227be38e3d99d5ceb1557e1e9c873f03a8d0df9bb7e3403447ef6c47537b50605edcb0d6aeb7077e82742db5098a2b2745f31d0ea80498ccd0f2b67b673c3d5	1	0	\\x000000010000000000800003bb5d25f1fbe2318c0a16120c793ba459732f3754acfdb4e4ff84216ae7af9469f1ccf4248b2ede9f7c95c0927e3905009b45717366768e06fe6ab9f530f96266ff15520e52ebb58a51cea6e737779b4723ffb87c89715aa04b392fff074cb31667fcc27156b301d9c0f81db6521c31e1321a0dcde33cb69f52c30eaa47011471010001	\\x7cf43e8c8aa244ac6e2e7008b2192ac88bc54f9f6fe13d6f31eee84b63347428b3e28914a6a6644483fa87d464081d2d22be30008a98db2e15bbc75f5d9b5e0c	1655345788000000	1655950588000000	1719022588000000	1813630588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
312	\\x14e766aa648836724d4145257b8ba1ca7f5c133c3c433a33522ccc385f35135cf6984944f8859eecd2d54b90752f6b1d9f8fe5dec98ee8b1255b0c2f749e0dbd	1	0	\\x000000010000000000800003c9a33cdbb3ebe1da9c1ea2f04dbfc468b6ebe9c6468c4d24845880d79654b3ff47c694f2a7c03fc260a08d71cd22765fd0e8ac7957b015ce9928044be0bdc045e4ee91b9980b07fd42224c0d7d7f56ce8e280b1e771a621af8277140702d4595b1e5a1e78a34a4f9c28c383da6e1cbaac36ec85d96bfdda24646584bb09863b5010001	\\xc871cf0542ddd084486dc7c72890d19a7b3411acd3c4d667df362b07646581a0818b5f10c4b6d0f33037ee4991c0536f82e5a7402722e08a710e3735239ad50d	1655345788000000	1655950588000000	1719022588000000	1813630588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
313	\\x166738a8a08e6f456a58a08b212f1a0a3dcc93f62a673cb04354f22f6c67d38556c26782345d9e91aa2a843a23498ceef37c1c2064c9f01601c13c742071c5ac	1	0	\\x000000010000000000800003b5ad99725994c453680a0edd635f48d8ddd0fc9ec7bd25eea2d585e581c59f0e816d415fb66ea4ab0afdea1616cbe10386fa040593eacbbde1cb395f88a5e28772bd6399d09921b1f443a4072d4d7607d2ac3fbb79d616cc33bb59c91bd96dd2f5e41a48e1e74b0059691a604941f20cece472f82288cd44d8c4357169279ebb010001	\\xaf0068bb50c5d30e406092add6520913c264304dd5808f4d7e47b36164b84fe865a48566c42b55ee98b5dfec8ef5b7ac6b68550c3560c0c77d4f94301f0bd709	1648091788000000	1648696588000000	1711768588000000	1806376588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
314	\\x16ff2636032a09d3579743a3a8518872ea984360a17ced685f12383c02b1401cef12902ac7c15547592e02ddfa7a17584568436d8e5e5f826a89ec725262fb2d	1	0	\\x000000010000000000800003a7d06a2ab0391f05b586d4ba41af47ec18a2104d9b3ccc80c40390e637c10f4787bb7b2413b295195ff1098bcba423a4f46d4a7f4181aa147befc02b5bb8927f15e9903edac6e828ce2958d52df30e30e9cd23191cc4c068db43f478a0cd00d1c34c7cc8dc15347288e93b5f1f6c33f9e68268467047f97d6699a9873fa0a567010001	\\xa9741658a29ec4b57142c2fc5d27921f57dfc3531aca6edfda40ef209f50e2e7d2000939baf9d74681e1ef21c280fa5ce216c8183fc27d64a418437752d34105	1657763788000000	1658368588000000	1721440588000000	1816048588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
315	\\x18fbcd1917270bd5c60e47a088a454c47cd1e1a1f0f90824b73ac6c2a0794788c4832e14f15316b49be76dfd26404ccdab71087ae19f314d6af2d9f6ec5b7bb2	1	0	\\x000000010000000000800003cd4d44c297158b8338267907c507c134296aa8b3c9169037884939f24a6c1af283a24115feb7037f4dc93fc96b9129dd27306db41a9094c5fa193f6fd43ae1bb3a84095c6b03df36e5573f711e39cbe1c0ba3f9f84176e89db5dd328280f4ec9ee284fea15609b47295f23c5a3fab069e6e2ac7a74fde4a638f926cbbbb1c7c7010001	\\x89f2c31633050029a76c3f076d8284627ccb49dcd8ca1da5511580882439f8e24185a9f7bb7b52fce82da1b15c3f7530d62f8c1f058d8f43dfde703fe1c05b00	1657159288000000	1657764088000000	1720836088000000	1815444088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
316	\\x1a2764429e3b9507ae7a81e882286072775c82e99b48e4756b1696248041edb7fb81adfb1ba30bd633794cd28c07995285cb4c51605d4b10c6580ef1b258fb9b	1	0	\\x000000010000000000800003c3fcaad249369344c3158cac01e121e9d0d79ba509991fa6f44a931dfac863683f7509b5b8eaa4ebfae6c8f5e5d1890ec0fcdd52aca448a26f757dcd107ab9073e8f6f506d98d7b70dfe1f6dd4bba255fcceb0a7a71e91561251af5a41003f6ae95ba1b84c5c0ba214717762e44704dd4a529825e6c197b2506e94a5c671170b010001	\\xce885363268729bd5cba0154cc223ad48366cc2937c05bf7954c177e5879846cfb3a8e36b69fe022f35f8f7483e727e83bd1d3dc0848fa2f2cedc3f68d4d390b	1656554788000000	1657159588000000	1720231588000000	1814839588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
317	\\x1e133c889f4783e265dd033db1907457e28aea65919b0a757e03f29260afb1dd9da87c0ed41ef25fe7dac68f5f578aedfe0699b46d9bf1717b3d99e36d0bca1e	1	0	\\x000000010000000000800003e621ed77ce4ee0a750c1f644a80d57dbc531dac0abba5c212c40d84f25e40e5d0389f276bd5c231ec11961c122f646eca8c11a5bb67ee11e223dddd8ee001b1de02ea88a6c6c3e7397ab2d0e68cf5985073be4c5b92419c8c03e5e7d2bec2a909db965ecce967cdc2ccf0f92040d26f7fa354c45547057a5140870242a637185010001	\\x63422091fd2252b4bda22e693a3f46aec0a42f44f5ea214b2383567bad92d1160aa0c710c59231d10a0de603fe89bc8349409045a1a92f58d2cde3cdff9a500d	1661390788000000	1661995588000000	1725067588000000	1819675588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
318	\\x25f39a1a25486a85129e95c952fbd023b302a26da464b43ea311e9d67c00f119aa6b25ee24a0990a30d21cf6234a15de255d303a29af2e3b9395dfe7dfb09e0a	1	0	\\x000000010000000000800003ba2edb2214a2f177626d1251d1196e2e283959d39914fca778552138f948368a58e3fab147795f0279dc79b5ca24f4d6277f84312537aa85bdf58a170fa9359aed429b4bfe151e778fc8020eae81faf6e95597d56cf86ed56aac426bdcabfb29c3fd22b0c077e7587dcfc91d7659c9fb0b3c2410cb267cc6ac4788f5b881b723010001	\\xdbaa53078b5018c358049d7eea36983bad4b24b9e3f1b2c9030526639fb62ca6d38f05340c2ec8b045267be1c6547fc5723fa42b0ed09cff0a80322353ba3500	1655950288000000	1656555088000000	1719627088000000	1814235088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
319	\\x2907559ef53c610fb76decc8c697b9e2d0ce7cdc52211be8c049656f16885cae9b38d5b63a2d8e21dd8ae342e33dd1a6cbbbd36cc4685d1990a24c856877cc63	1	0	\\x000000010000000000800003c2ec0846cd3cc0c00e1f4b2ac9e57acaedbdef0f6d779d126854ce6751e9f14ac81f7642c1028bbbd6cbda9409d00e73a5640398c0aeb7e16230566f11aa9702ad3d6fedfd7c1f5dc7f9760b986c4705c2f257b223d6061f6c2f51beb5b390c491e4bd7197104bef06e40049d8c509144cca0b1c21a439db2bebca3f1945d35f010001	\\xc0fc31200112539d857575a2e25b83cfef76d9cb447dbff2adf1aaff2babd4180578ae8212f49415fd55be13dedde542230e54a4a77713ffa9339b518777c00d	1658972788000000	1659577588000000	1722649588000000	1817257588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
320	\\x2a03f82b14603e316b1528ac512170464971542858e7ce740f7a2def9a35fb43908d215b9d4e9e197eb05a45d161ea3c87a4a54242596f5d1c5580bfc81c527f	1	0	\\x000000010000000000800003d3f134bbcb3a9fb60790cfbdb4640b384b04983b4c48712b5d2fbe69c40e276af6e892acafbbfe4c875480349a399089bdb38193376f71a047f4239a138cf65de078e9f5921ee6c0c72d9a927516c4ec0672f74702e1639eeabb5de764adb6d809ec2cb2224aed387d779337b458f816d1203f60b0436f8823020be1ce1816a1010001	\\x37d127160ba356cca9ff14285ffad2680a706d0912af8fcb3dce9494d301591b46eae62d3646f9ed67c85a3cad59706a097202be3204d5cc359069740a10cc09	1678921288000000	1679526088000000	1742598088000000	1837206088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
321	\\x2b77a2d3f1416c37f7bc9933ba5e6538064a5eb9df525c320cb487ebac761505d7595f9d235f678124b8f93e214625b2425eea7c498905e98710f76f4690ca37	1	0	\\x000000010000000000800003989b01cfc34462645219568dd55caaa4620b1edd987b7794474bc1ffa378c5a8e7f1e822fdc617ab4e547106e199e37509cfed4ce8db68dfeb3a189b0fdc9f2b8624e798c5a20007cf7a089bbda44489d389072d4cc7b5c178c4133d391a782d6b351643403d5c72f9be6b784b7f25ac355df5fe434f8dbd40f49e65baefccf3010001	\\xc9d841621bc86af172f6466a558c312ce86eeaef2c70d0083423e431a69954b070950d1adc0a864be5984d92a80058149b59fc25533b17e39da8b6bbba6f5207	1652927788000000	1653532588000000	1716604588000000	1811212588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x2b8b5378081161302f55eebd793845a945d1aea58f7c3c42fc4de32d7d27f941d92c6104856498067c04081fe8d2ae688451022b5deaf1090577e97516b718d4	1	0	\\x000000010000000000800003cb49f8a14924c20bdd5ce3132c7b2307e02349c98339c4f56c284da16b028762e321174abb943c12b11f7078d1e299dd1b98f546a8f2cadc300b2e93c0ecb1aebbc073d705c3f14042bb70aa6cfd2c1f9177cc06580cf2c722f9d99325bedbdbc2f526603671ad5d38596efe15aa91fd903f7861520178636975a33184461159010001	\\xa46bc2839930e9bf8cd0a963a411d354b28c6ae78b7ed5be5edadbcc3470e7e51934a74dfdaa105b02a7ec5217858a8a33927976f45148c2a5032115827ccc08	1649905288000000	1650510088000000	1713582088000000	1808190088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
323	\\x2e8b1c6cff912ab59e12e0462f960e9818540306d70b129ec558b0df9399928e68100f020b4963644de175fa5306ae661d0f942eae91d6835dde2d185c84983c	1	0	\\x000000010000000000800003b683ae8175c1f8215b82c11776087003c12200d389bedb13f021bc44fba642d7f59b0b1e803db44e3113deb343cbea525160fe6f36cf15b750faa7b29299d2a9c21e7ba67c456c4ed8060ee070d6435e191e22bd98faa09870998b410f09c07fa4d9b91d0dd0034bf2e5b185d83f327d28e49a160931af53a2242e8ecf2e2e0b010001	\\x057c0c98e1207baf353324c06ee1aeb7cc01c681962ad27e7eabba6790e669313f5ec7e432e40263b651a26425503b87e719e1b47250104726f7a93e292cc80c	1648696288000000	1649301088000000	1712373088000000	1806981088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\x305bb89cb2a616f4f2cb262a5366442aada4e8f1e740453f3cab1fc721fd8116b248bfd2782c711e8a26ac054f98f76d32227e824e3858ff4a8e19d294bbb089	1	0	\\x000000010000000000800003c6ffe0be2321a21b1815f0b861b52e008ff374acddb6fa3156e81cd064192db726eec2466cf824bd2e907a42142b0941d354e85ff8e4b89e95ab0c0e075d412c558f25c67175774097176921076a1e6dd172ee1751387eea42c5c4f38d52d6506e5fe9cfa287eb0a75481c9ed132a776cfb21c8dd00ddc983cdecd7662ec0897010001	\\xbb6b9dc8c0a1fd1891c0d7d6e655f38a79324fafd7308b56e7ec3b7022a10e28345d87c23ab15cc56c557c8d76e2204a116ff985b0252a4cb9ecf6e2a1f69004	1663808788000000	1664413588000000	1727485588000000	1822093588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
325	\\x318fb57ca41aba51724222672dfa3666ba0952d73896e3c1a237a43f4961b21c67daa6407306a62dd875460d91be897f840d9415529b588e69133ed166393a3e	1	0	\\x000000010000000000800003c85e77ff890026c184b4ae21f27d281b1bbd21f054b9c8a1adb3bb9ad114eafb3251b1877fcd082a2e72e9c0713caf5829b8ee8be918cdbe80eed808c21840cd41c95144f242967bb3b82e96977b829e4d23deb58fe5289931e834a8aa19759842cc96c7ab34ae13f9e628cff320a3a17eb0205f0efbf94328838bbc0de84bfb010001	\\xadd32f702d9a112fb9bb19634eb653f6686d365000340d9d0048477c18b08754cfdaf7ef35135d84ddd99d68782d80da6860121bbbb1fd0a443099859d175108	1658972788000000	1659577588000000	1722649588000000	1817257588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
326	\\x32afac928991e1a3473a1564da0b0e4ce7facc689087d35f3f9fd5e96ed0745786873a77aa80b8751d9a517b247d952a0a6b84643648907c29b3a38b60721d49	1	0	\\x000000010000000000800003d6273aa4b2bd222efb2895c0ce897374fa04cf087e980e01cd7a1a3a3fefcc64586f96cb86c3f19947c1d5344da5455ef4a24f3f0506c57b0284b95635379e14dbf1b8ecfae0cfa6c6a999bd0a13f2e501add9d256b2c8fac354f67ac3c09fbcdde3637682b0ba8e98194d444ecd338c701992250c5f59d6458310c167bcff45010001	\\xa43e5fe768e26a94b8e5f6cc784d7218c496ea12f9998562daf35217035ac3adc66cc2cfa24e20d1b4f86f46e7abde3882d19c9dd4e82936c64e506f5835e207	1674689788000000	1675294588000000	1738366588000000	1832974588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
327	\\x35572f8549e68880478ec060ca4c52d28e048400771f54a0587f438a55bc38babfd0de1f675e5ec2ba58cfaf7326103a15d07012552bc6b663f32491c4de3055	1	0	\\x000000010000000000800003988f2389aa174072e17754953edc70392d6f7837941867a75d0fe55db7cb122a5c9c680aad7eeeafb513f28cc31e92944c46a17db5f5a6c7b418d2a3aa0feab9571fd1f4de9ffd46a9229ffd2a82dbba71a99238f49da8be86156b93ef9f2ad3b1f449af43c08c4b325ba1167de7267180e6adaf34a64d4c908a375f94ea1b69010001	\\x9c8652d122c7a14350ba9b25269ff4f54b3163b4aec1c31c171539538eb0be1f8d7886e0428d9c5df3e6e6a066065d646bd81f72153b7ee7d4577df1c66ebd0c	1677712288000000	1678317088000000	1741389088000000	1835997088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
328	\\x363b89696b0fa7b8c04258ef676fc4722c93a2010a5886504f6b604722000362dca0682c1b058ab90a5cd4b6eb66e91a2980f37033afad7c48f6c6c88b0008de	1	0	\\x000000010000000000800003b93001dd96fa28bf507f63ce66d9b3d48d395ce534740fe223b7dab0240bffa6cb091eaefa383f5beb97ab2c09171f46fdb984e0cb0e123b091c65cf00e158a16e4ae29c307241aac6c53dc5d46713544f3fa92a4fe0b9abe8dde009cabfcada8bc70b942fa6b2196b3f171a5e62a7f7e983846df999f263532fc2fe86fb9627010001	\\xa6d2f6f528bd1fff5b32052b0af2d1aaa1f0e00b978f60bc98b4470058a395c5491e2ff04074d9eacd4b8a930697d9d3bb689e7035d45b67ddb7cb9a5e599a03	1673480788000000	1674085588000000	1737157588000000	1831765588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
329	\\x364730464e5eb2cd3a7a508649a763e6c951837c3487083460bc72024f24f8b0e23c3b2099cd412002e6c80862ad98037471a177eb6a3f79add379e1f50a6c7f	1	0	\\x000000010000000000800003df099b442d4670e0acff32574a690fe5cc8f58d027d44fdfd00a1de3571c6a5b3b99238eb68b664023bcd19fa1c555f40c3f0203e70a8c93c059b9f42d33a9edeb7ef4cfe3ce074842950acc4e62cdcc2bde21b4792112748354ed54f553edc879d41c9a9ec8c2836ecc7da8ff70c711224aea92a170e5ba762cf9db3d06b237010001	\\x18c9be63eccf47e2c2348d33721bd7781e05e1af5e14f97de7c5d71e2b60c0abe7542e002eac6a30a3c4ba8bb2b427a26a28fc4ccf49a5cd8af020238f101103	1653532288000000	1654137088000000	1717209088000000	1811817088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
330	\\x37c3fe236b2a4253bbfbea0f25d855696a36c378dc3e0166fe711793ff44ee672c5fe1f6afdb48c9a21430bd3ceb675fd98a7fbd3893f89c06e8b5cde3eaf447	1	0	\\x000000010000000000800003e1b5fe149d81872f3b60c80149f3e38dba31acdb1e1587a9c2de314b51e2561c01cd71ed16e9b9599b7172eb62ee5dabb7aded3a1632271c4f0f91045b29a38536d419c432bb3a076c706aa02682a2203dcf0b5896df0eda1b12019b25f1b1e702d836da3e7fcb1657625cbaaf31158ccf82773addcb8f411ec0d4041caa92af010001	\\x75c9513c33b61da4086ae587412d64055fa919734dd6dd8b1864d60b9b2c1efb7205d1c3a38d6e636c40ca48a14d3376b8324964c44030dcd144b16e059b4f0a	1663808788000000	1664413588000000	1727485588000000	1822093588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x37db9a414f9bc8f67f5f7a41045457a54b8858ad58a77ef5b6c020f057624a974881e16a5acee7915331a4e45c6212d25fc87804fe993e52a0ce072b1e41f137	1	0	\\x000000010000000000800003bb1e794b38d1db236ffb2541cac74caf39642b8727bc6c6eb12e97e9881a8eb5cfa7f0e08225ec151f1d3ba768e84f9d0374e53cee3518dd742a0e7aec353320ce0b9165c1f7032b5eab207cdbb682315b6f929736f5d5b2f66ad888fb0fe6620517b8373ac12d774ac91c31da7f162e88662c9a6d9ca153b7cee9e7c82564eb010001	\\x3ae99862de2211882b6b966b7022bb28bc33e3cc8c9c87c6d20a5115ed51b153bb525afe6de2c351bf93396014cf11e14a4160a79f1704b10f85bffec292a604	1658972788000000	1659577588000000	1722649588000000	1817257588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x3a43fee36b24870bcc48c852a9421a8c651d554a277aeeaf5a409761dca000d6235c7db1e7a365d24986ba707a2f59766d296256f8d46f0f6d374f6c226a976a	1	0	\\x000000010000000000800003c0025deffb0be457ad161f36f9b12bb155ad70f2a49e7c1b74f515dd65f08c05983a69e5d5e030d387a3c9d51f6c1ad501a828b1a193a06add0f2cc33ee28219be28740ea8f2b0794573bfb22f1bfc337dac10cdc8f5542cd77ece4358fe3b6d4012c5b92c65f18a4c219a19a501a647cf852bcf9e4f45dac2c1a9ddbbd48ca9010001	\\x706fba2faf19051a9ce1a1c7104c81e51287c674cc99f53f3a671e62086b47d6f8563312e7b8625f4b0481d5ba819ca03aa0d6cb78d0df7555266ccac79fdc0f	1672876288000000	1673481088000000	1736553088000000	1831161088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
333	\\x3a0b5421915a26351a3abca2a3761afefe37c9d3f34ac178c6a614578afe7c1523d5b1b887150218a47aec519483d02196a45b49c15d419edb2432be8e746dee	1	0	\\x000000010000000000800003d2c94ba8a50d8c0fac861e74c06c1b31c3849aa43bd93c840cb13138a5c3a7e98c2a9773b267c6c636cbdac39c7d69536eda6128889a3f27c21641eed4826f0fd807c0ff1117e2222b67e8257b7bdf8b0d3eca54b78175480bb1e971c85f7cdde1e79ea694f701bcb0c596ebcc9ca417f7a5daaf45b0bef185127d35e95be675010001	\\x945e725cccad451b6fb42fbc75b9193615328e9611519fd8a93278636b79c3779c31473e281faf38f2b08f55ea0413743bc1fbabf3e4dc8afc28f8f8e807210a	1666226788000000	1666831588000000	1729903588000000	1824511588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
334	\\x3f1bb5dafb8ebce36dd7f136a5449cfd28c287c94ee4da02165f16bb4d676290ff8df1b80ab1f94cec0969f5e48a5abf08c6f621fae4e647d243c7b58e4d8b5c	1	0	\\x000000010000000000800003d0a2815156f853b926ef359458c5dd2783a442e8dd7303fea7d28e69c131ffaea2f253f044fe983e1ed6ef9560f3c036bf743dd5e74c847a4de11cde3827984fd7a99cb69b5f85d046510f71c267b58aeb9db40a85881e22337d955aa432c06f8ea46b9c457d2f6c5c98ff883e6f2f9e38b64b87d879e06dd833f6149a10b2e3010001	\\xa5aad67a61d53f9d021a7a642f6237d55e08552e123b44c937e8bfda355dc20a5cecbf652b55e608477434b705f3c98bc5e69f6f0d7c8743333717b126c41b0c	1658368288000000	1658973088000000	1722045088000000	1816653088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x4a738125e43e4d998aad8308caab9ee44644a7bf68e1c728049c74a40d9be5c9d49bb0697daad2c72ba45ebc36a526d530429b5bbf698b2c709883806650375a	1	0	\\x000000010000000000800003a14feaedc893831c4ad860e7714c60e4fb0e4e4d36813263487b506739c809dc513234d7ddb85e449da691f83318ac0857f1bc155fac915f47d8c2be54a7a32d51f8664a3265c3860668ac64bf7abf6e3e96dd239e412f80140cb2132c92079e14881f779da8631cfe7ff8b5c400f726d0358a576f1c6a4bcc4e558926dc3f0f010001	\\x9d83a95b9b8c22d88040ca323fd6eab0ea37ad62ac17bd33e6b2b2f733c93672863142dee67b9513dfd562dd2804cc12d0085f33befeee9beb3febee3a43f30c	1660181788000000	1660786588000000	1723858588000000	1818466588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
336	\\x4b87085adb496a43aec22de58e6855d1a5af5e20a27643aa748785e17e136bc6b6425b8732256100d4b10a1e1f293dffc7510cedcc7000b9ab1d6845f048f982	1	0	\\x000000010000000000800003b20ec77398bf091a253ec296cfb81e0d02ca748917b38cdfb3f06840a9e937108fe1a36b65bb118fd90347a26091062d54825fd28e4bdd8ed803b58b6949907094edcc08cf4745528ac910db27ed4d21fe878ab79a429db118e528b8a7570a1eae2f2a2f03cebc34ee74bcbfe89485254e69e34f00ddd79cd81aec2d85746321010001	\\x3f8c147c81baf4d74f3a10bde885b9e42b801728dc563b94c2cab5ffb9667dbc46ee6cea69ac18b5866f975fbd5e0d3d61898bcaee40e8feb633bcb2bf07170a	1654136788000000	1654741588000000	1717813588000000	1812421588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x4da7203f42766c0118c68b17805d5fff2f3da23a672de52eaf2dbbd93a34d60b40ee46a8d90b04e8fa64d490084753675ed142b6dab8084bf23718e788fcec5e	1	0	\\x000000010000000000800003c8725511e58f70d4c6038cb4755684fe3f14c6a659ea548804689635dd2601866160d5069bebde62d1f6295062a8441a6920319866dbcff64a3e2174fc1cf309ea50e2f101834f8a53fde5f29dcdbc7347d63e775f8296110a80dd6760d1e3d3819effb71c5c8c15cf579ec8069b6c0053a397847d3e5c55eb3f65232234177d010001	\\xd2e2aa90e9ce15ea1e6f38e92fb999a5b2a1b95ad4451a81bafc39505804fbd9e4b4141ca88e7922201bdb96bf846f60ef97e66cb4d70d8c78739a64c2408002	1665017788000000	1665622588000000	1728694588000000	1823302588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
338	\\x4e6764b65ae764168eb3db2a884eadf17be5563f17148117ad6f18096b9ed63e236c4169edcf7dbc1b504edfee210cd0854e6c768530ed41fcaffc5c64440a47	1	0	\\x000000010000000000800003d8c4b5632822ffa5fcffc80f05670bc1305154c057f9e05ccafc5b91ac69ab1330439747087d19804ce9cb30049eaa4b95532c4d114d1908dfaf1833334cfa1d8dc145b7e488ee1041ff30e296405907250efca9d3d4dc93abdbea5983aa9b77603aaab19ab57b9aabdc5c0cedfcac764c99a6a4e5db0576f3d1554d57bf95b9010001	\\x66a02041c1a4292ab2c0780f5fdff33feec83f53f73bc458027b57315f8dde7d03215e78a959ba8f61ae243e81dd7dd6985409deb180f994cfab06fb9e968104	1669249288000000	1669854088000000	1732926088000000	1827534088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
339	\\x4f6f16bb7bc78892bb14d0d2104da552e60ebb56e551cfa608894bf4da3031df5193b319f90be5c324a83e1e905fdeb466ee3d5e755ca5652a0d1cc1c98462d4	1	0	\\x000000010000000000800003e5e5d59181dfbf5514da6fa8201e7a3d00cdeac214ed1ee4139637829e54b803b1512b4692d0be448053fddacb65b04869a85422527a3686d0d3d4d25d7098a9f2c5d1f3dba54e1f5b902dec89ffca21a76307c6f990835b4d289eabb1ab4ecbe8c26dac8c1263d019bcd7f1f9ab2039840c633a630637d01a6fdb0c33117445010001	\\xc2b84efc135fc94f951cc8a877e657bd3a3d0f901340004a8b9aa5d2943819799aa44365d23d85e8f977d2ef060392de45d7d39351324e55df2c9d90a6e41203	1666226788000000	1666831588000000	1729903588000000	1824511588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x4f07fd345d753e6a9b06a83bdf0bc8fa04e796812864f508a704efb71f14dc7265d75ef067572a3adad007b0683de96289893069232c1bedfaf6009c8225cd56	1	0	\\x000000010000000000800003b53b867fcdc3b2923b6442853a57e1679426b3f756183402b345e5e9b439e5cb3b031a212bf5470434d4f3a1b343a9f3822870c7eea0fca1c1f2c5a893c7ed56ccd7e9b1c9bcf8fdbdc515cb0cef7171f9cd3201533667147b1832df85b75eb6a046b615a22bfb850b6477b186a22583c5ad8bfbf77872d19389c84cc2dcb117010001	\\x8147a53ff04449554ea8e07b6ac4c4f9595c46e5b6ed728baab897c41626c7ade28a1075f6e8a99944241ca8203e9be871507ce6c51b4914f1533972e15f8404	1649300788000000	1649905588000000	1712977588000000	1807585588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x513304af6ba24d70958fe7365b363fb781bea0993584eec815bca5525c4cc5d79162c679aba8bad7d4d082622c916f00c31de4f93b5a679e8fb0a8b9b7f8b9bd	1	0	\\x000000010000000000800003d49fa45160668f792f5dec116624fd7960aea73bf89885b95962a2d410ccf4d742e92f4f9b93c8deb8f33dc1986654e230f4824997b56db0ccdd9e452cd93775c6a1aced408d8a6a3f2df746e47fb7ac5b18de0e050bf9f9226f6e84d5ec9370394000aa93d537fea38f48f9b06d0e9db5430acff5f899f5ed5e959107154197010001	\\x2eb2989d4988db348cc6b9df64cc409c9d9a41321eac82d339f93b69edf1d0fb64a91c629ed8ff36f74bc347c371aef7250b02c6205a5908290698dbd4a88302	1677712288000000	1678317088000000	1741389088000000	1835997088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
342	\\x5147c45528ef50fd099e50b82a750c096505cc7bfc32d8705bb80cc4eb6a2073838a2d776f6e3fe032a08139acf2e64c71032b010d9059250485833f39f1d31d	1	0	\\x000000010000000000800003d50750074a5ea425c59de0fb0796ae0b4f192364cf943615eec65ceae80769eaf2536ba36ccb636d7ac79759efe6c543d9bdfc184448ae9b5b8d05467b8ac93fca73358853c3fc5f99ff6eb16335d82d363203974cd04bffafacfec5bfdca08ba9210c93471f860ca57c6525727a56fee7b7922491bf0a0b27c162ec91fa6f53010001	\\x3beb79869fcc940f1c3c040ebfd7b8beb7e36af19134d7fe43700e220f15da704f2b336537076480700bbed47527c702c07e5ad0ecb2aedf68e3e35caa24e103	1654741288000000	1655346088000000	1718418088000000	1813026088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
343	\\x53c7db386ff8f69d8adfdaebf6f68432ce430a66134e40164200ee49769eebbf9d62fe7a545f85197614e0a89f797fbe7baeff49d32f0ccfc34a639e4a8e9e5f	1	0	\\x000000010000000000800003b8b0b6237a09c4f4b58dca8949aa990de7908060b1b133fb1fcd4219263222d1aba8acf8fe4f1f7e04c46f83a7fec4c4252da90bf82cedb938e923f5b774b8ad41c6d1f7d50e5421058a5c29e0801e202c2836c99b4dbfca3209b2aafa89ed50c6841b7629a19767e7a017224549883234cac7fee77781db09cc44fae5d9f463010001	\\x630cfebdce219a59a262e7fa3a0c34eebdd41e80d330a192538b2db2a21469121b4312d5f6bcad1d6911ecb5d476dbbc1f62171c91a6d49dc17c9d9f9d1ff703	1648696288000000	1649301088000000	1712373088000000	1806981088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x56479df86c8b1d45fb6cdefa6be208546ab8e46f1dd78d170cb17f2c17149e7ea71a9cc294ac708fdbba51987685055524a87d8cca920bc591c50e262757928a	1	0	\\x000000010000000000800003cb71ed8be5ac44f0aff8376a66c8ef2201dbc7bd9a418317f597e81e7330057bc00a28004731449c7b142c572d132dd2baab326da9f1e588ea7a9458e920151ad63bb6dbdff16b488b91e1f723cab17efea0fea20a13e04f6f8f0b2b4c492c79f660fb4a3fd4157e1465339e378fa35f7fe770bfb3f2fe745f84b75bd9f5beb7010001	\\xd320c225b6035f04e43952009ab1f5aac7f9ca622b4e8b80ee2fd15575f9ea03bc351063bbd3e5122b7dc6e45350186ef0e3465f24b05eba17bf254c5518810a	1675898788000000	1676503588000000	1739575588000000	1834183588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
345	\\x57c3f40c38e7258227ac6914ae8c2ba87e1d23bed162eac5d053a52ed0ec9866040a1cbc9f2d4d29dc15cd97a9f0916c3cecb486b2160c5bc80c0358a13f5fe6	1	0	\\x000000010000000000800003cc17ef18195a56b67d1a73a8ba234e990b2e0ebcf9d6c0703b53a8192ca5f4499840862b1339c87da534fe5b77b91c727d200b5ba4c760e4d9df17af238a7c05ec62b251f42c0d8f2f1632d98563838d6314f0534cf68888f64cfdc62d36e083004a6ef19f7ab59d5eb0619f95633403a60c47c3cee5bf3dc570186c700a2a29010001	\\x6858ac53b36a081abb55b47ff5c6e2c57e81f8b936af8798bb5846bd93c8ac43f1760832f0b2920534d31bb8adcfcbae6cce3fed79db6ee1e363852bee63e206	1653532288000000	1654137088000000	1717209088000000	1811817088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x5c0f6caa9725f355673861b738b0602d7a09202ec0f6312c7a9d1c4f567bc2bb55bf507b823d4ee0097afcb46f8b8043e3ec8355d3378279c35ba51e895a574e	1	0	\\x000000010000000000800003ca39d3fb4208aac2552c2c35d658a8694cfd9078842b984c59241fd16bd74d27bfd5801ec724c06ffdab290c4fb5f47e6d0eb2e74b9baaa5a2789a7faef43e523a40e059df038452e298b58121d1ad7975a503f8333c2a37c4d9f75fc385c5701681f5d4416bfa4bdca68823e52733109eff82d8b53129fda8b9463d6675a329010001	\\x92006dbf5a093924538b8d8b06a771513499a4cbe72941f0bf70f3cb347937cfa4dec831192121ed72986cc5f882213001446572dc2ff823d08a24ffe32bc40f	1666831288000000	1667436088000000	1730508088000000	1825116088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
347	\\x5d2bc0417c22bd2c3f25216e9ccfe7197861012c715f4fd8ae0b761672034f7e57b0ab60f0c76f691fdf0fa2866604ff90b8915ebc4665be93704998be7b7f79	1	0	\\x000000010000000000800003ba2fa6af72185ab64dff6989cf81f296a9f693d2ea7fb0863baf928884dd1ccfc04d8681393e43f7cca76e9e9eaa79afc014e81813c852eb45b17935eb294b6d0c4e1f3e74d461b475a4ca9a6a69bc07101f6cbf3578d398c43bc5b2c924aea63480abc850c2187d6b4809b32a1e4fdbd9cecd232c1f2c72eb7cd19854d0a073010001	\\x3f93bc6fde14929d6bcbd091c4a7e3deafd50fa063b5ef07752d59bb2b1baf8e5bad298bbeccb4c319f76a5e6e4673a518dc30108ad2018ec99b3712f0cce109	1663204288000000	1663809088000000	1726881088000000	1821489088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
348	\\x640f06322e6ca564af5c0bbf8dce6f842007743df7c92000069627dabaaa9e8c545abef0b70b465cb58277b0d13fc0a0713f59c7052d09487976a238579673a1	1	0	\\x000000010000000000800003e12670e379a12f78af118f9d47529bca93ddb311ce9a0a28e52fc039a9201685048226ec1c1fcfef1f11cf035fed4acb7765401c76669c959f2d02b58f7e2b47217da502c948813d56fecb9bb3be08649993febf619b98a357fc7d9ced6878b822fd3d726384de47b7085ded3dfa5336d56d528a8ee2475b1659c0bc4e5a7bed010001	\\xbd0d72c9d85144924832cec1c5728d2cf85810484ad35faf195346899156aaaa57bb866dbaf7f8d426a3c2592da2e8c2416d93c5b0ec30442ff0002226881b0e	1674085288000000	1674690088000000	1737762088000000	1832370088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x6537f764d068128ea7e917ac9dfa3b4f84ea1dcfc172690e094163ad98e01987d769d0b1b3b02d8946f9d9155513e0e6a470bcb48f004c1fce0758b1eac178be	1	0	\\x000000010000000000800003bd1947f0f922432718cf97374c88fd88ceb30c185ff5f1740d895f50a5688d7a03ed8298ad1f78dbd04c397eda8c701f382073a2af82f1e82b78aecdf78d332ddf9d7b3439cd0398612cf0cdf2506c88c3f5d776bcda87e170f0a44a51f5a4d6eb33afe8d4b93af02a780be5c7d04575a038a278b0eaa8cf476a1f1703c6fac7010001	\\xa83c46ddea0ca0ec498528fbdba8547a22a26a791b073aa8fe5a7b839227d3a3595f20a964ed555d2ad2b54a271331f30c8860a19d4a519e5812b2a0b12f640a	1648091788000000	1648696588000000	1711768588000000	1806376588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
350	\\x65a300bd08a9e9a6b0d2cf4b4dfec891a2a8ea1cdb9e68ceba2c321d549864d423c74f689e4459ec0d4717dc6751438d08ee472ed4faf23830b666094ca7f45f	1	0	\\x000000010000000000800003ccaf1bbd36ef9f19fb7a94fa06a9d038347c672121aaa81d72c7dc814ec70ee789fd6db1f891fe2077967284165ed41205500ff61ee4bea5e8f4c2230f9aaa486294200258bca69748b2e1abf3ef2d2bf48cd575eed927f0bf96621dfd605525f9729d37aba783eeb48ea555c6d37ee65fac17da10f6954ca5e80c1cd95d1763010001	\\xb9cd6ca5c7d4cef23d0a510e66f459d3a62e712d672314aa9d7292c03340d1e83e7b864b5a6352622ad1a9f4bdbe07324d6e8ff2d3d2bfc59d4c4a95fd65b205	1663808788000000	1664413588000000	1727485588000000	1822093588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x6883d4d071a9a9201cb897e33d5bac1faa917ff0a4cfd9d4c6d08b8b18c51cac40596d9af8fe60282f389b55aff3190e0cd62cccfd7f2f10827907836573c075	1	0	\\x000000010000000000800003c83fe98d911e0f9fe4ac0212ccf2e9c445b835c45df0376997ac595df7dedf61730b2e04b7dea4f7375353dbb021a12599bdd9b3c65dd8d6911a5a0da3e93eda236c739ca8d3c334065b28a72147008968b2cf530d8dadced568300208ed8b1948497f365b112519b0840902c35803b92e695892cf54e0b95cf08b8df072b789010001	\\x921173fee8872bd22af7de1a2944df2540d74990acf0ffee1dff1d0de784f6fb64a058fcf5d228dac4adcaf71af9ef4dd0ba9b39457ceb368f48426ddcecb503	1669249288000000	1669854088000000	1732926088000000	1827534088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x6843fabc9be35d923cdab3b93e3dd017398619e80ce4e2e150c06847382deb475bcce6047bd0ce2e364147c160100a813fe50cf2d70843cae3aaebe26ae04c9c	1	0	\\x000000010000000000800003c82b69a35d5980d0e2fe889751ca0360679ae74084c94865510c771c07b1fee6cf5c5a5c4d39426d613135c700eb84391bd6d3ae1c0b74a54ddfaaa2d4efdc1ba518cd7b55724bd4a7373b3c57154b4026d10d9b40ced833f8b9716f2c93713cf2bddb35633a9061f0b51d3d96dcf7e11a29a6140e5df96e591e5d8be92cc94b010001	\\x5b38605cafa07004e5304711952b34cf3d8882353989458dd3ae7bafffa244c5617aa6398165fa2f7693b0ce0d4ac94fba1e9720b7bdb9e1b684d913fbebb908	1665622288000000	1666227088000000	1729299088000000	1823907088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x6b632191cbb8691952b0df5ab3c528568b9f3c38f66da28c9d1a38d94aa224abfc639ad9536f9d5f66eb21a68549b30067d1abd8d9a4a3d99118bd21ca2610c9	1	0	\\x000000010000000000800003b57b2ee940bc076161ef7af86e0f2f4c6969b1bdc881424b2597f910f21322d9bf4ee844aeac053ec432a50121c4aaec1100d624de5afca699cc468212b0d3053fa9162ebcb97db960f0fc964b855dd01f5abfecedcc407fdcc48649214b30294b57b5b015e1aa3c65fa57c2a97c61df4dfec5506a1bcb78d894a16385cdb19d010001	\\x61885fa783759ef7d002b7ccc9771154f48d3e425c24067c96a8abfdcc7b8ae723d86fa1ba1f40d68db9d49f926bf89af01a02965b74ed01a792422bd223d004	1677107788000000	1677712588000000	1740784588000000	1835392588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
354	\\x6d1b31c606c32e283df758dfe9fb5f3e6103ed788a7ad4769535ee7f4be4d0f5f801b644a97019715155213cc59e436db4c0d685e937ac1527e152c7604346e8	1	0	\\x000000010000000000800003a739784161e24f5c28b6943b29ff9b58777f63da184c065c6cec2abc50c02e74d04092e7169d85bdd242bfe94a8d9a970c92a2588899639c69f30b3d98180b02eb74035519639f283d6ec159583af43232a5b401d8da3549bc58808e68b39f522ad618960aa9ddb893c56a1c89666ae7e5644862f5d863d95da897af2613dcdb010001	\\x4824f5f19753892cb6582d1a6901034c8e4da847ed4f7d2761efaa5361514b67ca6e4a627b7a3be6a1f5d8e609a1e53d3daeee9503c24392161807eb2a23bb06	1675294288000000	1675899088000000	1738971088000000	1833579088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x6e03074ba27e536409c21de9025bd67ad7a6e97cd44ad7b35248079f2f34efaaa3e95ccb716d3b043f82905d49dedb9a2445fafd91b755f58a6e2e893b52fb16	1	0	\\x000000010000000000800003b6259105e1208092e9a79520ac4320ef0566bbeca64ef54103c7a427479cb0d01f84fa3ddf190d5ffbdc432e959587727a1e992c4c4cc417be035bee9d24a73e08060853b67a319e19044275066f0f1d0d96ece96993b7074cc2d58e016ddacd917bf6788a7d9def3d186406c18704c940fb1fb4e935e606a1d654eec2dcff87010001	\\x85a9ee76abbc3f9bb85b50772dd437ff62f620e48f8e44910929d120c667081614c5e1674481cb627ee693f22a578cb0708ed917ff72d417126f588a406dbd05	1660786288000000	1661391088000000	1724463088000000	1819071088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x6ffbd1cb6cfe8b7f54854221522963da038f8dfe3e73151930e0c6348bccd15fa7f36b2d0256e3bd4438bf1285736f6aded9692383f17568af0f04fb6e7d7b41	1	0	\\x000000010000000000800003ce2703c8b191275855b5e6bea921b2810131d4df664a77ec2d231edad1440f4851f06b1de63f2532317254b89016f5e33b323ad0db7b0e35c90e1a5bd99315a1af5b915ddfec9d64c1d4a036d2808baf25dd8c9bb4e2a8b243c4c00744b813f18ea58e38c7a5d0a1437363053132d0bd749bf44a6887c011f5567343fedef725010001	\\xd656e6d44f8222ccdfa4afa0a468914d4c3ea3ddb92371586648ca989c54d00656b80f89f54ba9daf08f7f79bc45c34325e4b3a227db7a3652b6cf3562b5230e	1657159288000000	1657764088000000	1720836088000000	1815444088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x75979f4c5249bdfd1a514a740c6eb93dfc53fc863284205760015997caeca77e82c1cd88bb9541653bea6261f59e598fd32a5381aa829f785531e7464cbf7fe8	1	0	\\x000000010000000000800003b052409b4f7cb11fbfff4266ae18d480e41d7f77ad8189e263f00c2ffe00eca8d7cc0907c9197cc9c051f21ef26a699a50d9655675b10349dcefe1cbc7f233756cb4f6fbb1a740fc100bcf61c369256d1aeb4aada40c6913dd1ab0c5c2ca922a27e1123d56b21c4732e8fed228cfcb1d89fbbd485f182ea062eb92bbb078611d010001	\\x99deef39edb4700b49378bf034e58454e1d93fa7ce224a084efec8633432c668832150c02109667856ac2ab82316271d46028ddaa811f6c2ca47883bacac8006	1667435788000000	1668040588000000	1731112588000000	1825720588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x76bf01f0946012da79f2ccb69847653f14489fbf4e16634eeabffd050150fd2e9f1035d0f5bb7681c1511b8f8d2d158cc66bf9785668077f18f06e097ab137e1	1	0	\\x000000010000000000800003db0fb31df87c59d98c1dead50f0a5d376edbccbd4e0b29ed0ea24f8816992ceeae35d3ab4fd7b097e1ee046464b87b0423c8388dec8b36df480964f0ad0d0bcee74e9a2b19c27573f2c63c1cb044ab37a86ed8f9a53e44e4492b8a90461c9854520592e9d49a6d8c0b1cc37845709dc23bedecc3e317f64b766412b2a76a7f93010001	\\xed564b55332b63cff85f869d8a38b762b85174d5c19db7d7df96dbb8566a0809040a346eb99e2583a6b27a0e40c4c1b6e7a3160db971b1a85e3c2c7959ece402	1663808788000000	1664413588000000	1727485588000000	1822093588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x79333d99e0530543cac2aedbe5ed3a041aee7e1b0fbe5f5f93328672d8cd4b1e6bdcf7658034cfc8a262432efd612fd628cea2b76b3788d0f04c40acf9cbd9e3	1	0	\\x000000010000000000800003cb028cb2c9746c99e558e9633436b9d011e721b8281fc190413c10b4e7d7c250cfe5caef843a81c63c9558ad6feea4354ece030e86e39fa73345317b340712dafa6e9d9f71aadcb933e472365d901b4a100bfc7da32b96d3d9aaf090aa343825bc22d7af9f3fc1c0fa91a281c18230403bd675567ab5482307793a2ed6e2a9e7010001	\\x77cf3b22dca698cc5f800b83597b888a4747d66f80837dc978b86b90e6b98e2681b11eaa22f6848eb8c77b279f33bfb51372c1b2da70fc808eaf7aa5d127d201	1660786288000000	1661391088000000	1724463088000000	1819071088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
360	\\x7ad335e04c70959d5402a694e400ec6d0198526bca454343cb21302dc20d0174e8cebe8effea8d3575bdbd9e9b9cbcfa7ddfb34cdb66c13d805ac3158f45b836	1	0	\\x000000010000000000800003d399cf0bd3a5239607c274f593b24449f86f8e2d5f81e5033afea849fa15a16590aa20d3e82876957b442ddef04f4da364873774b18848073dc7e8bb117f302c491f9433ba83e116975ce69d186bfad1e9ff0e2bfea370eb8c4cbfc999f7a85a103310a5d3f4a24d5cda040d61de89401113c5e30fc706b1e765e42b4c41707b010001	\\xdac73debc2094dc62525d72c6d0b0e5480839e02f5fbe6a9f29bfbd43e5250a407aaafb52f1558ea5962d7b553e3956ffcfa07cfcd4f6c445da9c202a6e36b06	1651114288000000	1651719088000000	1714791088000000	1809399088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
361	\\x7a2b31d960e38e35b5a645967b846e39063a201301108530f413b96255657cace92eb2788ab573b38af03306d572abdd885e08cdc36287b21d2445199fb0e27d	1	0	\\x000000010000000000800003aebf0aa7293b3f2adcf667cd2267fba7be0f4d3923af403e6049cada8a6d3b1a1396c3f770ee5767cea790fbe518d72ab05a226c25aef90cf33d0cce177c34b8cd29d150127bf853cc6863deede2c033e0f125c44c925308016680e79dd399a0cba64910d577c75b680e28bb60a8d4b2ada6edb8e48052ae5b493d9a6ae3c443010001	\\x793a0763c630794b0d0849b5c7b4afeb93c63534e680b508b078a27549d660d5986dc319c8151aadacc817fa03ded44d75496fbe4296d69a0644b6e085e08001	1654136788000000	1654741588000000	1717813588000000	1812421588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x7d5f41cf231bd4731ed132f1aa79deefd0456709684989e6d50c642319e8a985ea31a518f91ba4a6f3fd626032ad104deb4f1d0d45ee0ed492fef37b06bc46b7	1	0	\\x000000010000000000800003ab7fe2241d2d2af7ba718cd987802fce9e9964bee21b1022493b91c4029762ddcd3372267b98c747e08fd6926bf715090b38e7ae2819addf45d7dc1f4d40f143c486ebfbed4efb4bb3a03c9cd8668e8e61a33985cf17b91108d555298241373b59dd34e26a50caa279b9930402824316aebc28529e7c126ffed651b41de12ba3010001	\\xc3587a1bf71d72e15ec30c4206a32e8a1fbb330ca998a4e7eec0d088bae9393cae2cadb865561c0849115fd544032c525ec8aad5e789810733686f2db4b13807	1671062788000000	1671667588000000	1734739588000000	1829347588000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x808fed83d3d1ba4b0242c3540ed19165c8ac389ad73b63512929887dffcc2c4efd0bfba8bb4d7ef05adef395ac83966709c5022a4a47bafb6b82023175ea8073	1	0	\\x000000010000000000800003d28d1f083c75a94db9f7df6352fdef5261e92567d4e0f127526172e89f7ae1322ac5a178eaf0c97831fe7dccd61c8e4489277f24ee118f2e1dfe135f7013f182406bfa68a9550e628b81942c40aaaf3cb4ea58889571a04504a9f721240edac2e78aae45b162382df74608b27433d61e10b31c4afc45de229752d828fa3609b3010001	\\x7c3c1517d0d0af0a25c459b777928ab1b51a6dc984298797a3ec1594752624c86145e6c550953f9a21ad5068f0aa6791f5b67455345906be35e22817bb3f0e09	1668040288000000	1668645088000000	1731717088000000	1826325088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
364	\\x82ff27280a4e7489e85cfc0e298bd06532371abf7a6f68bcc72b518281882d164437736fb1deed79eb28ffe95847591e29e464c670e64135a04ba8a47afa4b23	1	0	\\x000000010000000000800003c298c644f7b2b99555cc1ec4a5644cfe0d1cddbdf700cb22eceb26693183a05dd680074406176e6a3bcd2fbf89b8509300077d13ec57395e122269cb72deca8e5f156b6d189e33a8f40b758272d88cfc22e81a6a9fb82b71951a3dc417d92e3a4abac5c66b671d7336558d868e3419dc0d887db01bdd2bb7b15882e34f4aeb57010001	\\x9b5c9d956165415089bf15b85517fcf63b59dcc62b79e643244f0a6e7e333f5988cfc4570b930e6ce2c1f91fd96c5361a37122873e90e7e4bec38fc8d0afb302	1663204288000000	1663809088000000	1726881088000000	1821489088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x826710cfbe2d3b59b1ae14d72a3469e96df9eb552d6c7dfba6e7f8d02a7f28a8bca1f75040752b786ba0e887b467e3612c0bcf8b3727493a9227a1db20c81387	1	0	\\x000000010000000000800003acd7dd5ec02f25df131b2bdf75b30eca452452b9c9efb6d889f5cc3e7d05a6b44eec2ca1fc678f7da0a3479189ef0906aac44bc930cfa05b134f02641a4e43c88d73af92c3b550ef0b84a03131487e37ad15c56d4edaf6891b14a0d0daddcb8204645989ddb2b621e7c3643b3090b71782bc571acd458b13b64d74ca242b9e41010001	\\x792036558bf29b2b283f3063e9abe6b98cd25fcc7720b40346c3f9fe040975d98baee8586f73c2e255261d498b444807c49f9eaebd487365274a7963f57a510d	1677712288000000	1678317088000000	1741389088000000	1835997088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x86cb2d4c09aebebfc31785275cc07520e24fb1a4ef8ba036cf98e7569bf41c4a9d4883d7ed7ee9411eeda19d88d908073e9795bc63aca616e3b8a42de85a2d41	1	0	\\x000000010000000000800003cf396de91326780ae23bb7031d5506b78537d017cb3939a573575aabe3fcd2699c2612007ddb41df0b42b5895e63706761d8ac6cca1f846299deda081a9655eaedcf386dbba679e843010fd81d9da54eb3e9581fcfbbba4024e8e83e689421e1ed6603fb26b23b22dd1551a7481250b30b8e15dbe9907e7bff3f22aa558d5c67010001	\\x72596f2f14dcc04a4ad2e4f7c743e3ad906d4ad33007f939692c366a8c0cb3731d07dad06e4fcaa51d1c3be1e7e6b00270ab785d3fb6f6c89e6c390357c51c0f	1657159288000000	1657764088000000	1720836088000000	1815444088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
367	\\x867ba3e360770d8c67a98315b708dbfb1236c4aad40d0caa4247350bc3d9be6ba6159f9ff906f475f6f74f0b115d23b7e75bc9a270b0ca5670289808c7c2e1ef	1	0	\\x000000010000000000800003c0a758f5d457516168ad9e317f23dcf597f62ed837b818c1bd91ab21088ba768675d32be050618212429f441d4aa5f23176f3d35d68b725d56264c71c579cd45aa291296eeea187675afe769d79510db8d2b32f0b38797b97bf743bb8ac4710d536d76fd4720cdbc83261655caf8abab6eaf01d02f7dc79dcb7fe8e41936aa45010001	\\x41748b7dd48a3f2dd620238498ee337b47bd8857403cf66c31eb580aa44fd6f01bd87a7608b0b422ba1b19ecf465f09ff21bc57f48c0aaa5495cbc13c3464804	1678316788000000	1678921588000000	1741993588000000	1836601588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
368	\\x89df50524312520a00efbabb68e7767bfd55bab25316bb6653bc14d89cb275c9340abfcfb1647567c71ce690551e3f0701da72f166edc1d3950f5095cde614a2	1	0	\\x000000010000000000800003f8ae82b6189b4dbddeaaa762e3f1784d8ab772d29a6491d79575b518d68c713f9812e58d3d43629d1a3b9035b0c3ddd3b12959a6fae513427e3830985a63670c29f17f432e4fb870cbc1ac643b98fb3e47046dc750160cbbceddac94dae4ee5ecd438406d69210962e8ce28940d424845414c46636fab7308c6196e7f631c66d010001	\\x2e8973c9d3246286edfdd611a1c532c31cd6013746ac38ff900c7e6566f4c8e070bad45ef275aa4197210dd0a24910def417048f58e052460c353bf1b8fa6305	1668644788000000	1669249588000000	1732321588000000	1826929588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
369	\\x89d31b9a9809a0b8ce56bd0f5872d32138713f7bacabcef0be715e963cd2e7eefd8300637f1e5fe0b6811c6cd363bec22d9c2dd409b1257620388bc11b3403fd	1	0	\\x000000010000000000800003be3a35eb7f03a95763adbb587a6f886d0444e311d08028ef7a4d7207d8bd0e09a85503148a37a1e965b60fbbf53315ed3f055f4f911abe481946379ffd46a2e55bcaa7b344426a169b1ff3fe6842dd9c9215d1f27ba5a393da1534378e3cdf4b47a6100e6cf79a4127e015f3f410e7db27a6ef444b60aef70519b631b393af91010001	\\x443d3836f0fa73f075dd8fb420efb27aa28f049291d8c12b54577ef7167f0d73d73b560772be40c0408404548135766b61dbce5f8d93cde55cb0b3d8fad5b002	1652323288000000	1652928088000000	1716000088000000	1810608088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x8d67a18fd45a3758cdfaed369e600c01a4140f9fb3b12798eb5eb735cf1a950d36be687db51c50f068906885ca64391b61a9dd8ea00f8cf824c383ab87a0bb22	1	0	\\x000000010000000000800003f681bc64bd39945c93e3d26ec74c16c102c23b5f96a6f2d6ccd123ea836e36678f6ef22a072f17aea8c14cf8598ff7e787a9765e3abac64d448019eeaaaa61c1a592ca664298a2d8750e36e04104651cfe6d75b9d91b023438bb190ac3f42a9780d05434081112c342b9eb394a49ea0d00477fc7b65a848477fcd1bcd800fda3010001	\\xa57dd7ac434cfe255872fc365f6b0a44cebe6aca199e9570ebb91f443ad41442a3f5bc04653bc991a1b1a4c689ae36461f3f840478ae12437074129aae6a3b06	1654741288000000	1655346088000000	1718418088000000	1813026088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
371	\\x904b66c8a4e91c1e00d82cea0317af23365ae6a73aa89622f933342f5b64f898590bfe361972455f51a677728af18befabeeed77845a03528d9c6d572409bf08	1	0	\\x000000010000000000800003f063aff93fb1d8b13e94f0ec45c7d341b40c602878171afcdaea653bcb99dd142d1c0fca7b67cc11b18199a9f1b30eb57fe03d7d6e0b6c1477d555dd4318d656e2533755b3b0b7fc1eb32cf88fe123b7c4947eab39fb209c7b2e7a34689dfc16a491fd671d5b4e17a53ac981cfd6b36cd09669c360896639350549c85f3838d3010001	\\x252f8633538b9ad77aa528d5de3c2325078480042e5e3f87adc9e10b6a87f02f85ec5b984ebbb6b8ca43e252bfdac4d4b8d4c5a4c3246194883ca8ccd13be50b	1676503288000000	1677108088000000	1740180088000000	1834788088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x9673164d8d4c830b3668bf14e33d2afeec6d5ebcbfd0a768c928a010e48a940fc4179da2aa8688222bc31e8b05262226fb89749cb898500fff78b1607150d25c	1	0	\\x000000010000000000800003d074c5011b4d404bd6fa11fc64784abff27fe8edab24b227724ef686daed58abf1a17294e7e9d074ec5c8c7dafd7a0e51c7bbfb1f169f51c63bfc4a9af8049da69b4de1cb995232dfc3a704de0334faf071e581296c2d94dbf39d274c16c14829174328f35dbba549b94000ab32152f8977308c689117c6b15399711c39c96d9010001	\\x4999168438e4da7f9030b4855e4092827454bfd47ccaf262267a13437ed9b5ddc27bd30cdaa7b47e0bd1a24ba952c34a10ef0ee14c3dffc77ac369f26ccf0508	1665622288000000	1666227088000000	1729299088000000	1823907088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x992b63605b8a7ce899dab3ca32db4e414db02b754a35accb7070f93f5a1f2764e653ff60a33938506919e7dfc4ea5288ed6ac80fb863b8c2b47ada895cd578aa	1	0	\\x000000010000000000800003c1d4824eada6d0fc3bcc2af3d928ff019bd84fec7c837b4559cca00566e377b7ccb251f90bc9b8af8fa401417c297a638efa7b5324d7d8484574a36f8cca8594f688f9d87c75db2d4c9e1aabfd72678e53b78d6143aeb91a3e99be25e48530d9968b4b9f5711f0cc252dc21e4e777dcb0da3ddda6729ee3c970066d542dfbbd5010001	\\xe4b0384e2991b977fe7a659c0c747df8ba11e6293247a40a6547c6c823c65268a212b9fd34572702fad43fa06dfbed15a4e9b6eaf2bbe4c5c241a0076ff86c07	1658368288000000	1658973088000000	1722045088000000	1816653088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\xa07332e36194f602cb1f67016ae50cedfcae811ccd2fd3015f8d175b5cf37aab80fbe136fe6b644fd35217641966d513a3eed768ee06368c14e3a640ba0119db	1	0	\\x0000000100000000008000039ea07335ce839cadd70532738bf473d82ca6d5a38e189a9a3f603639b9edb14a1bdaf0b84a291ced25c7df9a095edf7ce226fec58ccaef1e8f863f42a72bac91f06bdd07416feb8ffe78f1205ee27da023c339e61b971cf63718f458bd0db354e5c7ce3514d94cab5372f070536617868da800c549396953d0b78a8e0d0f6941010001	\\x4cb457cbcbf44d2df76d583e8c3074e1046b51219e303c0e0cca5cd7ab75f4173d63f6fed3981904e0efa7ad0a383876b1fa536dff676feb5feeb1d758c97e0c	1649300788000000	1649905588000000	1712977588000000	1807585588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\xa0e7be06dc5ca5ab755427c3ac72a44adf9ef840b4711b06e3617bc777a79feffd359e8b92f2cba704d55e7021da22564b9f7815fa5d6ad7096656b464bba84b	1	0	\\x000000010000000000800003d23aa2f5eb94e84d159c18108c6d5df4b443a33e04c22a8cddee9972a7a84449b2568c8d290c21a7f7c411113644c4b785d809f303b68b623911bf1d003a4ad99e43b2b6bce08180f3be729f108d4a04784f7c7e24dbe0c5d283fb6824ee61f7f0198a8889c5be7d4dfc1954d1de7d127ef3fd86268de9a9cd72980bc8cd111b010001	\\xd569a78af7ccb409bb4aa480c277d767bd0c58516e6e93d6c4cde8f5cc8f1b320f2072321632c1bf349c09c2189308715fccf00367347eab5dfb7ff6bc858e07	1651114288000000	1651719088000000	1714791088000000	1809399088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\xa39f03e538ce02b6a5a5a8523d244a196ea69bf81b2934596a64e3a67b7d411e57855b37efc12f4a757eac3bac7c2b5cacb5ba546b3e3686bbb34687bb541bb1	1	0	\\x000000010000000000800003b7684c9794b3afbbf224a8e0aef272e197c8d094b5649a44c6545edf8da3076bc59555093801d5fd7f511511aded37405119bb1d27259f0b4aadd7bac9fec790f944577aa3b3c7c32f5f9b89eb8b5bb20c505bba11aa78d425431f5a4fd0e3af1b9e66525dc42704b50c7428a5f75f38b41ce455546327fb065caaa514251ddf010001	\\x3cef4e93acb24c81768f75f97b3a7337e2a8c7652b25eae17ace80da1e4e250019bef85366e91cf4339b01a2316229bbc823a84d2b44654c3fda9228bd984702	1657763788000000	1658368588000000	1721440588000000	1816048588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\xa3030d3f17e7f011f4fc0b806e3807748dbdb00f7a4c8765b95bb56a3a637d6ea86af8e4db258cad6c4d7acd706f0377520db9fd210994cb331ba4e09a01b993	1	0	\\x000000010000000000800003bb21b960af10e6f431031b3344e643665e940c9faa3d35f86bd7b752fcd4c87fefdd98ff9e1011e4580ba9f36993cff07c478a08596a4d0abd02eb7555974523897d255bac66711617c222d1658001cb06f1d0a5255552c710880d436b56df8928d41b4ec9e3a191a9506ce90d5b26bf04dbef30568ce451c945b9a786963fc3010001	\\xea49f5d95ab5136b1d422a14bb25306426c4697386aa6352024c23accd5c5c4286efb2c17aa5825dfc7affc677d9297d1ab7959d810a91a52925b5828e70370a	1674085288000000	1674690088000000	1737762088000000	1832370088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\xa613575867a7f07473fa34fcf3476f1c4d6e771d27b098bcb0ddbfb46f73b72888cb2bdef32cce559e9e74e05fc521ae9e3ad429888c715d6e8b33b004b0de28	1	0	\\x000000010000000000800003db6dda9670b458b5c360a69b3f637b4169967c6025f2a2ed8f16c8497c90f2cb63087cfa6d8dc1b34dcf64029042235bfdcbf9154a032b463813153f1dd3a389035990d704cfb0429d8d4b663253eb48f80fbae1e4678ba44191db6a273a06610725da99002649eb41a06274df37fdf5535fd74e6f402c89a18a0d0d0179be03010001	\\xdba2072b55b91ff5f65bbe5a93ced05e47640c57216140945223a0a771bddca485f0f54df64e8e30264b5fa703c6e171bdc5f4d8b996744e710d16f2b91f850c	1669853788000000	1670458588000000	1733530588000000	1828138588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
379	\\xab7341b1a2112d4aa7f279f5e456ee2b829fe79bca8eaea9ba950968098110b8479ce5e9c739f7182ef0bb5160fbbf0128f824d6b39ca0ba536b57daf23195bb	1	0	\\x000000010000000000800003b73357e5d8a02afebdc3b38116f8db01e075ce26a553ed71a0f2c919af9b54de881ee6cf23265a5f097236c1cc1e6ecc8cc887be138db7f3177d9ca2725b41a03df47ef5a102c76c36ebe2cfd272b69fa1679b65de835b9b032427fc0738f6c5f13e9ca50135eef09c424a65c5957f0599e2490bd99d2158291992774e5e42f3010001	\\x40d227f5cc9b9cf79eec276cc9f1e669331aef94faf323c60129e1a13db3ec9b5f41fababb443d8060f7e3e91f7900adb121dd8eb5b31378527f65a779915907	1668644788000000	1669249588000000	1732321588000000	1826929588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
380	\\xab47a85d13961dd5e2719e3d92ff4649bb02323d738e4d8c3ab6b75889a8aae89058bdd3abb89cabbae13ed9ff4d30e670d9fa8f0dbaa1f7857dd058cfe88412	1	0	\\x000000010000000000800003ae0e2f6bff6a20a7e9fe689b692f9443d56fbfb4b025641dd1dab7927620a5fe3781f06ded952e67ce2adb49d16d9c78041c0cd411cee85dc0cba810a39329cd6b665dde17ed2814bec447b5e96266d2283bd24f3918d48fa5b916c873e27bf6dbaa66d4b1e8138f945f4406d217e7f7dde39228699439ebb8c864ca10f902e7010001	\\x5382163a2edb7397108b57b53751a9fbdd925c39db1a13c08be814849fe26960628e68c3c2cbd0704dd10b5daf1376acc866e041e087db226579ea96cad89e02	1665017788000000	1665622588000000	1728694588000000	1823302588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\xac1b2cab0e0bb74d4cb4cde086a4d6fdd89a41649f18962ef1ad223edcca811e5779e3179c64aa9faa71b84fe9ffb7bfb60f4496dbd00cd5871c8d3826b67f17	1	0	\\x000000010000000000800003e79c6aa65f03167e720e82bd5c7f76f47fedefb1fcfa62fa126604f19d0d0099e5eaf2b3371c497aeb9fa93d42e5f83d40d9f8862882df5646c47b30c6b13ebe0874ecd0692343d76b74f62190ad3f86295e3610c24af679c82f9bbe9f5dea6ef5fad992999e1f671a48fdff8a3202fd20955eba6537b6b4f6c63c678d0cb4e1010001	\\xaefc45e1d881dc33c6b1e81f9c6e5864df9eb43441e88c554845a2e2851b513106d4dc785fc99a62630cd3a8aa4d46abe0090eb29d012d0b0e2f15febad48200	1656554788000000	1657159588000000	1720231588000000	1814839588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
382	\\xaf436cc7e917c9ed8c6c5faf562c03141e1f96f02a7750f99f385c770f48432770f0f14481993cf6b8c31fc202cd02117da1bfc27ff4e5fdb0e5a321829b9be4	1	0	\\x000000010000000000800003a5fe375c7a4e29e6c4a389f5d0a843f137639c147a237596676cc7a48b848afa297143af0275a04a0b25396cd5c176d4627ecbc2612236380487dbe12e751b779a12e2f80ae3dff86a038cf1b026bf0c1fa2aa70fcdd8e20819f116f4cf965579b06f6b599ae5d42e6e667202e92463285f3d3c7fcee84296fe471ab8af94ccf010001	\\x6711e97873da55e4fd315ff18d30c322157f024d7182ec76f83828e212af462ce9780af1b18b88a4fd67b78f4373a6b26213ba7ac185580d77bbc15cb20d550d	1649905288000000	1650510088000000	1713582088000000	1808190088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
383	\\xaf7fb546b1b509e620a3370c648859a03cad7adc359d339b951cc4d991e028d52bbeacba71729d64c563d8fb59fe2df91bff2213cba90af497a23df6f0bbe1b5	1	0	\\x000000010000000000800003da7ca7a6155fdca0fcef67be6a7687b0c946eb950acdcad61ad5183140216bc5aa3c9e14e57399c3df2bb1153a5ba9c5238af81f65921b4a25eea40571783ded622c3bc7dad819235bfc7353732844925026b850b3741116d62530e60c1c5ee5057b7d76bf6e9251bcd84c89f91d23789f09b61c962087b994ac0d301764d91b010001	\\xc0063b6efda6ad9a5b2e3e42d66479389d7d712e05b97a87ca8646822fb0f7fed276e1a408a3db1b51c12b605ab2b71d8c07554d671c9bbfe4433da0761a9008	1675294288000000	1675899088000000	1738971088000000	1833579088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\xb113dcc198a59cb1af82d125974c74f54062fc053ef943239e1aa7e88960d56e198a9f1cd206379d0e45831da1526e583cbe8da326535cad70fcef6006701bbc	1	0	\\x000000010000000000800003a514cff1d8643988e1d1b01c7445cfac0b7dfa38f882182a561349f68904ca49d3cedcea36c1152fb62bf919b1559d1aedb6966e003119513d8184bc986f4e928f41b82e27e5916b5dc2df54209a784fb58cda9f7fc58efa9325623efe5a30cb598761c13dea57fb4191f0499f04aba4ab43efce19adfce8d3093d803003987d010001	\\x1a07880cc6ca298a0f4dd8275dc45fd5e77bd738ec19040190901468cf1e468f811067ca43c77858e789322d4df095369e7e0f1773d15b92e670d76f89450806	1647487288000000	1648092088000000	1711164088000000	1805772088000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
385	\\xb59ba9d5821dc422017c24c91c2a5448a8bc818d4452183a58182457da914b0598018448c28439a0d9c9116ec6d1c20da55008132c33ee857957d7dd309abc57	1	0	\\x000000010000000000800003b564b1b704a4b41b77127a9f889edad1528930372c6cdac1cf475b1af3758c96252936a80638f2158351308251469b12c45351f868a151574c243d7db0078f824f2d74f7f5fb7b83efef54b912352669f122e794ed66ac4951d2218daa8ac036d47f14f3989dd26faac4f90a47837d9570aef1f086e5ff99d54c5de25b4171bf010001	\\xd4877c7a391cb8c9a49c57fe830a100699bf6fbf4715868416da899f58684cccf7699de47bfaa710b46a4a04b13c2d13e9a0b15ecd3ff786a833d945db27e109	1649300788000000	1649905588000000	1712977588000000	1807585588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\xb81baead9cd006696bc1f1fce3ab4274a8349f171c0414e4e4c3eaf090806847eab1ec7e4b277896de64e03b7b2e1bbf39ad1d8b97356b028ebd7469dd327791	1	0	\\x000000010000000000800003b30f78da952e1cc1b3eecd0c0b309d05279de589d8ebf659f22de534d30c97245db65a7303e45b7141ec96b4a32fe28106ded453a340739e1953a2bb53797d23c959330611cc3365cbe70c79066f02f37e2a46f5e3f2d8e80c5803a753072c40f6f58ec54146417d386d60135f7d51f8a097e950225c3db0024b89de54946065010001	\\x8a8cbec671ec087df23d24cc3b07d32ce79dac30c3cf279354a39fd86e415ff9d0a477441cfde58022c5d91a91dd77c9cc4438afc244fac0e26f8b0b418bb602	1676503288000000	1677108088000000	1740180088000000	1834788088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\xb8a7f8ac92e9b39cf4c2c0e782948b6a69493c89039864a4bf8d0963335f83a3ff961e33bdfb52d03199ec55a4874ea29e64f08a57925a3ffeb1edd2a4cf2b65	1	0	\\x000000010000000000800003bf2b83bcb78a1f9b1479ffcc6214aef138d1326de83279c65b7a610eaf6ce2ded481ceba5a651a4316c74822e55d6033f170663b96d589f4d7e79ff2890ff58ed3a504f72bccd5545bd52dfedf86c0ba1e4448fafc490b2fb727136f704d182401d97c74c9f6a03ebcc2ac563a8c2c7d11d5c68fafc6ea20e480b614e448da6f010001	\\x5d972cb2340d227b5f0272d41f23c3ddda890f3d0e4690c0f2d891d0f4a7096aa9ae977337f128e1f1451fe1caddd931bc53d606c3ae4f036d4877452720370a	1652927788000000	1653532588000000	1716604588000000	1811212588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\xb97b3df7605b7544a886db789cf496e395b57ba29fd6aef66b406f85c155efbb4b34552082d1521d08b378c9d875d8c9245d04d58357a825353331c9e54cce83	1	0	\\x000000010000000000800003d937ed309c0f9633df4ce2b7609cbca3b8a1be9e81485652f205255eae974d753887e4aa64810da482c5e2e52cf5b879e0a66975dd92bfabb356daee86250cace6a936052b81ce4df1f7ff6872b221cb456e287c810b54d18493267dc9e1d76f0c821e9711060b2b52b5207ebae33afc69ea8df1a7983f4d69d100ee7497959b010001	\\xf192a6b88f8963ad8c7663a3d414c8b341fa261180dfeb6ab4f4c1dd5fbd49b842881931c760093cbfabff8e3d5646f99ffe32c3af2268e0826906ed5c2af40d	1653532288000000	1654137088000000	1717209088000000	1811817088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xbcdfd0b2d139393e7b64010ca56af053b77e8708d7674afee45b0457af75b0c3bacb6487c9e8de42a522c94e686ae34740a8fa4c0b5c03aea71a081dd287fa79	1	0	\\x000000010000000000800003b478c3e8cf20b418ad02977637f2afc6e987c442d6ee043fe019a249d783bc3cd48ac57d9366707ad2f85acbf4551cf3b045444cb11d2511a3ec7d7991cba1ea6e7cee6e4013dabb5b477933aecf202d756bfa1adacf0e9e3736b3578a5109fb73ebe5a9702a913acc5afc3ad819d1ca540a3a3547be975cdc1c0e59b3a53bf5010001	\\x5124015d3ffaef6af6b666572e0ff9de8187d5bc159bea4b3aab706d8fda3d399882e64909d235839860852cd67183d718fa3bb8d34f7ac4698537486bc04d09	1663204288000000	1663809088000000	1726881088000000	1821489088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
390	\\xbe5b48c69a876637c54a71f735a2943fb01bccb9c30354c93ca87d67c6772353c1f4ce13bc0506b04e088cf3c7eb42e8969749b226c5d66487c3a628730b877f	1	0	\\x000000010000000000800003c81a3dbbaf5b4fc03d8c007577b1d8b2d90a8fae22a206cb94ea8af4277a9933580ab9b649f5c63dfe556f084ed7a2fd028c5ab28c864531585a4459f762ace8c8ee5a1771105bd5c14d2ad0622499eeaacea65d805681143e572617fc86e7a6db236343c9b4ae7d256d49703ed06ad1c99e3518e759a41a471b35449acca62b010001	\\xf35363982a3b8f43e00b016c36d7f99756cc917f25088ce88bcd32c667e7d8baf423feeccbb5c87e5b053b5baa903bd055610ecbbd915b63199a9893dd77d408	1652927788000000	1653532588000000	1716604588000000	1811212588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
391	\\xbf1f41d22c2504a737a9e9ae25ca7464fcbafc1274cb2809a90753954211bd679421f47468281bb9ef721857d511a22980e45bbad260fceb61619723ae3d28f9	1	0	\\x000000010000000000800003c189f76b51b528bd651a553bc7dfab1fbe5ad49c720df4ead43190f18c34940c924a942ef9e12dadf4bcdfed04f812c8d998b91308b4f4d1234689d8b8a581596a4fc5990d58854b33600e7afdaf2ed8e346c2d2fce9b16ea357e5c736c0b96618948d3f54eb8a5aaaba6afa09458460bfac08951864d9e1e59c2dc04b29518d010001	\\xcc598ffed6702c94fb2e42c007d3285835c58272fde5ef07396edf580856e9faa273bc4d957f8063dcc9ad2620d071f7cb7282eeaabdb8b9e3a675e60367140c	1675898788000000	1676503588000000	1739575588000000	1834183588000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
392	\\xc08fa7c9c9303feeb9aa995163e9f37c13a09d26c6738f5e9fbef23aa329e09eff81013abcae16c366c120c323b3bf44a43a52b17df53803c702995b6e4420d5	1	0	\\x000000010000000000800003be206d1d8d9fe52f89929ea7d7978d6e5dabc220b8923b7ff9a93b4153a43606c08f2af6904825cb3ca4712c8f0e6c266394efcde5d110b781e50abcd43887a1b420662155fbb469e4e2c67e9d897ff835801f99e0aec86d0335e53fa6e7222e9c79d490433aa600f9c58c66a71c62a31120178464db1384638bfd9803ac6e4f010001	\\x4523d590432bd1b7c12cecc9e223ab7a71ccb51db98b8e98da08a0b8ae067f30df9a53e8c32c48c18804ccf11725d80441abd3242bc11a1c8e6a466bbcf5050b	1664413288000000	1665018088000000	1728090088000000	1822698088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xc27b29fa7b5c7d24ffc6ca293d3ef7dd842305a2baacfae13c0809c4a3a54c62c8678ff72fe3a5dc04adec426901a3a7fba2977d7bbbec6d1f12bb7555d165ed	1	0	\\x000000010000000000800003d206fd3cc3a910347cda82fa4f8835a8f637a1db84522c4c8436486f32c9e18e7f9218719514c84ebff9ffefcca5323791d62c560d2b02be379ff2a9ce5d33fb2dfeb6e40f14c5cd50f182707ea7fc53304f420413445581a70c1b80c90be22a03de19a80ee03b14bc432b3edb2d763e0f704fa7daa21d8e47f8036b495aa8a1010001	\\xd0a0214eba8a1603d616c30f43ff9f149854c17be5ea17e8ea9e663202d18a5aef54d362563233dc025edaaaf49a5378ff50161a9fe9880203a22580c1425903	1648696288000000	1649301088000000	1712373088000000	1806981088000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xc9ef684c37277320d03aada7e44bbb7ee39eb3769c5250d328e15e14926f49c9d8428a2292e07009208ffa216a879b811cbb04a86fe98895420682d1305e1662	1	0	\\x000000010000000000800003e9a1108e6105aca54816b598a1d067c56cca594c00b644b822220b9ea609940c06b607f88da712722b5ae2860e87339c52c82d469378beba90af966950cc1210a2e9b30024ab6c75e86d2ca97723950b7d4a950012044aa3db8b14206ebb3e61b08ffeb7248f6c71475d37463b37b9ec895d413b78adcb5d44b605cc36416813010001	\\xfea5b27e9a17321953d5c1d24d21ed9a0450dc513ed9a185cd00ce36bb73dfbc24d7398e263a542ee93ebf9c055c93e4370e02295c198679b50a9736706bd203	1661995288000000	1662600088000000	1725672088000000	1820280088000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\xcb972e55a5328c37e82d8730fdfb2f8efaca70bf381997105a49d1d218d4004b64616847f11c1686f26ed3319f66fb7a990053d3ac9fb8c90d947a90f4c3d460	1	0	\\x000000010000000000800003997a54e63f37634721f46d98d5de4ff313ba5362f79d1d3efaea1c1ae624621c249b97da9f0fee9273f9cc1495fffebd8153f0827565e792077cf1590a87294c4f902a9e6f5868b04dd4f4a1a6600eb2a009c4f3335b1b0d89fead2bb9765e1d0a8715ce421de6da8b18ee5a37eb6ac558c0569de125725072a8f88d267d6ec9010001	\\x70969356952c18e6c9cac7e0b99ecb07a2127583f5044733e0b892e17ab90a9230650cc9722ff9881815da532d9af44b69395de490175552fa5eb90dd36d5401	1655345788000000	1655950588000000	1719022588000000	1813630588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
396	\\xcbab203ab7d69c486877c913c0be1fde09c0e951a9afade0d307abf1cf3bbb7a7ebec1320c5484590736a6ab06704474a29f1bf53826e176efc876db01348d06	1	0	\\x000000010000000000800003c1601d40cd069a9a4b1686fa7a0ce10cbeb74d51e8abc48da63ed5b69b9b502c22153813e2419325c43f08c14315c87e6f2a190bbaf211f0f17edeee00c36ce4b3393008ed87b43723f07f2dee3bd552b63dcf5198ffdd9ac2e5ad8772a1b83b66539855ad8c4adb2dc8e0bccab2c6724fd7f7c9f20b1f6710c6e9a90a18e943010001	\\x001f8de26ea1fce5c38f78865bd3a9d8417646f9a72d7c1670fab887fd7d44b16f2741b652eeb81b1f3ad6e943c603842d84a1a9c1b22f6d044080adb14d870d	1674689788000000	1675294588000000	1738366588000000	1832974588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xcc83749fcb0ca25ccb2cc0afabec127c49660a1e5f28e6a4a770fcf69063ac787e927fa897f0d6b9167a2730039d1c1223255d24e3f3fd5860c35646d3d8ae9f	1	0	\\x000000010000000000800003c56190c34984ea1e3cc097dccefdf52a825808a93329170c3e782a2b01e67f3ae54d6fcaec62de19f0f09dec24d54a5328ca89ff1474c39193cd488a05e19de33505821c874b2ffb9cb08db90837dc04b2b55ed9ea4a6455b10dff1eec4efca14057c122bcbebc2675706ba235d95f2a7231a1569d4b25d3c7b9a30751b965b9010001	\\x08341811e4a099ea58a01d1e7bdb093cf5cc3ca88d9f527418ede138852db9a934e5ce1c782e98da98417eed6429ed69e6d5e37e2af30907ceb3e7fa1a8f300c	1674085288000000	1674690088000000	1737762088000000	1832370088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
398	\\xcffbd45c114614d830d9475f46d1b4fb82a55a4a76f7062818b681c77306ab41dfb55d91483fd49c9ffcbb136bcc2c7eb9eb7502d876e25cc591476435666b21	1	0	\\x000000010000000000800003ce5eeb1bd84fbe95a09d2c1ecf67f2bc42d2792d36c53886aef2af3b86410286e9c405291b846d14f3143fe83ff5a2aa64a18abac35ed45fe9c3becc712f823e7cd40d8850ff161a51c416e11673d4c1d685003aea4b6fcefa6bac423424aaf1b11707822fecb2fc9ae3a552c0523d0985b6c9110b4c664b94a9ce1d0810b373010001	\\x19f8a289087e23774ae5b17025ae2236c6eb6950baa75b9ac325a87c2632e673794357ce4218aab6534c6fe8fdf9e1e3b61aae5d298c2674c524aa16dbb30208	1665017788000000	1665622588000000	1728694588000000	1823302588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
399	\\xd10b186fec7628eee2d8c7f8097435e91c9448bd97936baec21c907a530167f2c6da8c351a6d54ca8ebd409f1a00ec595a734142500621d391601c9aa2d29433	1	0	\\x000000010000000000800003ef8c435d3bb02e672a5451bca8bdcf8b279421055224aa2a3a33f73fdbfd5eb8a8877ef518a6e6add8460771c363549341df1688b78da222536ae92506f87a019a9882fec2aba317715908fdbe8db21b5a23877b437f189aa6b50148cc2b5129ba35721653797b18ffb26706bb12f06fd7a786146def8e96cd83b5dbb7b1a803010001	\\xefc987dba1f0ceddfa70ca7d0b28c6720923bd9b427893551899e22e5aa04a4366665af40c9b8680e805392dd0f694274b0a87350914c5ce44790a3a70c3b606	1661995288000000	1662600088000000	1725672088000000	1820280088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
400	\\xd2ef431be99c7ba35312c2cbbf080b4e735af51902b8f23ae223d9897936538829be46b7044f4cf419a01571abfb8924fd15af1aeaa15f380ebe54109e7f2b14	1	0	\\x000000010000000000800003adc224f1871bba0aa1ba52c4b90d38642876d348410b8b20c08ea5e27ffa464e24a96ccf4db40f6e9351b76379b7036d6bbbdd3bcb995095e13082b379f481b4c28949a3998d5d0b334b56b517588004cdc08ac2e2c74ce5f828d3e03575ef27323a9aa00a6ecb14b417a45857d30416cfdb8f45a19e2042875637ea4cf82677010001	\\x0c92eced855f73e12f090cd5c16daf9162e25dabbb75ea83a6eafd20a61a84d9fecc1a9b567b63ce812603bb9bbaef769d84af264671e24997b3a7a773207206	1647487288000000	1648092088000000	1711164088000000	1805772088000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xd4ab1d8e1fdc9d776eab125f8fa54cfc670c55b214ee01a2b4c3d7ef26b3b11269fd7e2aa898135faba2a49ed454ca2e604beb9c183940427a04ea71ad9e17dc	1	0	\\x0000000100000000008000039f2b324e9fc8390a9391c136b18d6b3d27f333af4567ef14d62910ea4ddacee1f01e42507cb990559b692151124ff868d22d1f8c6cc0a3497fef449ca6b9fd5259ff1a61f8f5324036863659f7516d786d8b92e551200f6769f3e772445f515f3614c4295ca4fc66a8fb8b1e10fc4c988a2b1da0686ac35b225e827563f7890d010001	\\xc573d1df78485ee882b4e77578925f9e6675cfab632aeeebc5baa1829f7f70bbbb5228da6f7296020bf2d9b1ddc38dfa155351dd7281a1db94683cf1f21e1703	1656554788000000	1657159588000000	1720231588000000	1814839588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
402	\\xd4c7cba06cd811dc944686d7056f953580f6779fff2b3b1d6fc92b864bddf669d2792f4c6583de8470bbda21d40ab98ae4fd75ddd3cb327a9f09659a99a8c2cd	1	0	\\x000000010000000000800003b016bbc033e5297aaf23ec26d03f21db87df1e750018df7f4c5e3679ef740bd7e5509088432fde80dc91359b177020fdced31c687965eb394d3a707e83aa81d168aa67f559ef25a4c9e511f8c570a0ae73866d86282786c43a60b392a8701ec0af65e716918c07d6d11e15196ca98cd157d0ac1ec86641c1b57e25962231982f010001	\\xa36707496917be15309da0ce1571fb8a456f79ab7ff6e1d534cb0bcf4640a03435e8b1f9ae2459a7046fc011c33af2e9d03f3a1766b0c22016ffce13036e040f	1657763788000000	1658368588000000	1721440588000000	1816048588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
403	\\xd577d7d0c9587998a26a6f96a2415f37065f8883c16e592bbf74e9b692b7b556df324e50b4b68245d0994d119e78631e7a87fcb69700d2fba53f5e500b068226	1	0	\\x000000010000000000800003d012ee34a4e9d542cff465bc1d34f99092d1b5959b2cad567f264938fa849c910adc86a9f30b79ab9702267a464fe98a989f11e13ee1036892b88f4698a0053ee729fc7142b6b1f838073c05a90cf4c8b4520670abe633502c376bff215f46c0aecb0e0945d9bcefe893a39dd49381387ab1cd9d960b0042517cdc0249d97359010001	\\x58ba25806a2ae8751d2c654231a3f7d9c851db61e5dec25eae6f49c1d6ea5e795f5e7f2dd0025b8f56d9cb6341f594e2d73cb239ddda69ad0d098c1487ea630c	1662599788000000	1663204588000000	1726276588000000	1820884588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xdbbb055322a913e0fac965b57a5665728597be616d331628a93890820e247a5b158e28f8310c004539ab778591347dd91cbd79a1e61f2f2184ff4900492a4e6a	1	0	\\x000000010000000000800003ac3eb9ae70aa2f7c535fe037e0b948aaf41d80be2e815598885d2b343002af17499e2b10efd6efdb358643fc4aaf41d1b7d825c062b799a4cc330dccbae17b689ab818a5cccfab5836906e2c72214e22753f62bac50aef0012f0100e9049eef9e68c2d7611e8ea134ac06d85894b87cd30498b015e3e6b5377bf71b3a3aa01d5010001	\\x69f836a4596dc09c745f33703a430286cee897b2f9b110772a6d3cc5604b2d1c863176ceb84e923d08ef5150cffef399d1cb597a5ae10bea83f3a6c00754990a	1670458288000000	1671063088000000	1734135088000000	1828743088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
405	\\xdd07911ff8e0d2f66fb122fcfb447eeb1bcba163b11f185fde5a9ef9f5a681a656fa625b98d03b03b7763c87e777fd42c5678ee726bc8fd0428fb80653401c7e	1	0	\\x000000010000000000800003c4342ca6a6a4a13a68cb3072736f21d409857f21639598a413d155d0b6f809cde83c4867718baf71b85d2c509365f2ca43d3926e2ec1febf5e19c3fd0e26279aa28869e8af2d6a4df7c166d076a3b20ac6894ce801ac8fc490f2558e8dddb0baad9679e8ab2deee288c13cab3d04ce06a0be5cca465fec6598c621754d58b5bd010001	\\xb76f9f14c8522fd6ba4c4d62f8d5060e1e7c4557c3523533bac9c27530856e27e9246e46418a1f0729eaff449c760bdb00ba79a20062034b99219f2de047a20c	1672271788000000	1672876588000000	1735948588000000	1830556588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xdebfe77d43c150c2ec72e81d9d750977a6e0cb7df2484dd1102812781e09462227ca39a14693d5c2cd0fe00ad4de7e6d0213af686accdf1aa6d0ef5e25efba22	1	0	\\x000000010000000000800003b716feee5ea85aed91db449d4ac713c9d2953cad936b35d8bc07bf1feb383fbc3856d1442ce3e01a3d9b62036a8972521dc804c3dd146095099ab5c35d3e59be24362305c5246fcc69c7afbc9089fd57d070683cc6fe8ef762f8295da728fd0e626b970aa7e3fe8bab40dfd55ea378557045ddf1c1884771451a84a6651c2ddf010001	\\xda51266711b67bc898aaa13572cc2a61d7a51a74c232407c29af4730c8a2d15af9c81b3073f03394bd48d6a1986f6de14fddcce6dc68a96c8b279894a739e00a	1673480788000000	1674085588000000	1737157588000000	1831765588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xdfdfbcd4da73cfa9d4f026ca06d520f4d6e68664dd9efb7103b7c16b8bab15581c82c35a694f86cb827874d5f0f201ceb79b79368a31941e1cef7bd5bee6ae1f	1	0	\\x000000010000000000800003b238cf74b5d0c03b98ede229548c7a75bccd1a2101ebf6ee531d1846f76cc6cd3280a20c47bc13ec7ee43317f76f96d77bcd6ac2caf8cc07bfafcd4c013540c351759f8c39dd569ef55405de195f094ac218f6729dd1f95aae6b136788313db022ef7918e6cc04b4e7fdf798e4bb58251025b05ac3e3088539f05f98070d153d010001	\\xa9efbb7ae1e9c493d1ece35c68deb70f4685ec6a009173d103a8522b278c93f0ecc07997b457f455f225d15c3eedff3feee5c0d5e6d3a30a74a489f3c0665709	1665622288000000	1666227088000000	1729299088000000	1823907088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
408	\\xe44f951184c9e1b533c36f4ec48232e6f2e479bf418244f5897e7cd954108cbec6d31a64d802878c5ea2130b87142d935b9f34998ceed7d4339d059ce9b1befc	1	0	\\x000000010000000000800003d9866003cce65135af339fb9785b9921fe9d3b76534b7f6204d3f6253d56ee5f33a16a413fd2fc462569d9da0804e271fbd035136f6c17b1376b19d5ec399782bbd0c00e1fecbf55c6b25a7d4c89bae38b45f40fff36761956787aa16440a3d2fb4c4f0ee20fee978aa7c53c176d7251fb2ccba3f7cb5c788cdc95509fff32b3010001	\\x5773048b22ffa8a39e2aa5e21d93a880061be30a8c5c7889ec9e1c95e5bebc13a2b78228ab32af2bfd1e756f05dc994df9fc28827fdf2f26077512b1235e6d0e	1663204288000000	1663809088000000	1726881088000000	1821489088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
409	\\xe5173d59552cc288f2764e68b2ffb950a442a8490468207b35e168a39fa6011f5e658032b219a782c6d95a53e4b4678311bb5f5615b145cbddc5531b0030939d	1	0	\\x000000010000000000800003bba4160756d636d75e010d6394a5c8d0cdc22b094685e302de726a3a5e383a6827fd05ee3541981ba0c63f58cdb7bdb186ec64258ee1fe3b5d4ec21f6e4a49321a7b779497720c439ca9a9adcc7ae654ebf7e93dad95db02bfc8c1b9c3683e990dbb0d9b544b56633ee5ce1e32b343b01ba311019484c842e3e44eb360791c4f010001	\\xd13aa36e54873e5c43411574be47855302f2e8da3793c090734599558b5d9d9999d457cbfe4331cb66cf882d4c3422cb1a7aafe643c1374b5e286509b8e4e705	1678316788000000	1678921588000000	1741993588000000	1836601588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xe5a7ff0b47f4b64f135c71688b0818cc8ff9e21f4ed85b0b6c23d256072c08281b69cc810cfd0e410fbb979f036fe2b9981c1ea24d07ca5818fcfa7d4b49e6c0	1	0	\\x000000010000000000800003c4d7b7820969821a6653c0061a07cb0f1102addf48d79153c78ae44de1b02ed77c7de4c0b74a6a043c028342a6d674c15312c931a89f28282ab7cbb325141200e4b9160072699e5b031461aa5f418078313fed68cf573c7a3dbe25d605a10acfd388d7e9356159d17ecaf39c534e67db6a3b04ed3e4e21e9a8bec44bc00ee0bb010001	\\x4588911f84ea3a98a281c6d0f3acb398278ea1598d3279f591d3aade0b357f087d8eb781dc8df758d6ecbb86c00b5daa1836d69f21127f2fce4fb5f6b2658b09	1650509788000000	1651114588000000	1714186588000000	1808794588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xe89b661f996d2d037c268e6960c41f914a8f088a90668817cf16cf849fe66049be15a437f086c003516ecac2979acf153543ec67170bbc24e34f0d770d290707	1	0	\\x000000010000000000800003d4a06bc3a5999979438e6d24650239a5fc2fe1301505e941700a324b486feeb44d38181be4daf343b89e616971e2fc5ef87e6397d96f4b1a79a3f806b6872b5dc5fdf45016f9c7149951bb2b8b7776a56f7af3351085d303de48166cb50e05a877f934c2a967c1f893c596b6c2a2567d5b59fc518f6ab226f734e3edd3e3f315010001	\\x2c0f45a73f94ce70452267808e4b615e2361473e9082b65be41d7cf96d50a3ff541a59e4e41bda822ff74788cf3f2bec77e09bbb7a49873d8ce220fa43b2dd0c	1662599788000000	1663204588000000	1726276588000000	1820884588000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xebf32b1e19b982a8c492ee544bdcbf632a2e41c11f65c48372fb89934333fd7785ff06e421351c0d863f899bba112dd872fadf37591ea5f43f4d47ed56c73ccb	1	0	\\x000000010000000000800003eb37e29741df3ea44f556b9c4509e539180cb719896d4302ea5eaf150d1eb67ecceb6cc30a4472ea7113c096ad9e92b5eb38f80658f7d1caf73bfd7859babf7feefe5b676095432b656721d6a624c097c6227c78bc0e85528a9e0f216954389f72f5911ead009032544c85566b5f235a9436a252fe0210648311f9ba942363b9010001	\\xad46ab7e70401c5eeb11e481e8889112f265e13e7f7bbb38ce83ce878b1bb389a821601f511eb9fa1abcacbe726d391e7e60c684f982ce006c9eb9f6d2a64307	1663808788000000	1664413588000000	1727485588000000	1822093588000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
413	\\xecf794677110e0037eda6859d318f3b594bf381f52d798ec3f425bc76c54b3830d6458ad29ea34e03761c77359607402d415d2003920a5ab5d6fa456b169ac91	1	0	\\x000000010000000000800003c3bd3b972facefbbd1f88fca49367efed9e7a328ddf4468d7de455f74c6ab5f1dcea978894a147d283c27393aebeacbe3ab6b80ee4af0e1c82d17f0af53683f173fbd66ec1924b5c067a5a4c10c152c297391ecf6aff6e9f26ce25ad2f7678878b022d242a45e3061fc962fe5e20150f71be259200ca8ecf1c1ba68cd4c9b769010001	\\x5a8e0d8c63966bc3c0c49f13d6988da7a7ab5643b8db11948a411c90d8701c03f6587560bcf56ea5dfcebd43036e4bafc0a038fb23c011114b57e911fab69f03	1673480788000000	1674085588000000	1737157588000000	1831765588000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
414	\\xed6f194710b6fe50e98afb2287ed7759e9f8e731e377eda2dd93317c98a6af3884706be1311c55e7d975dd44d7266eb184aa1c0d86f766fad12482cffe8feb9f	1	0	\\x000000010000000000800003d17d68fbc782755fec7a7d0d2c96ee6d80637036ca93f760ec100eb2e1314f15af9984388d9c66de6c932b89bac75b90ef883a337f461057f2a0d9a61b9dd3c04ce36c6c1a7d8f80399a72dcf3b460ac424f40a941e130533f5e721e2afafde401a193fddfc3e07195237b93d9addb3a166e8742a34ee14bb38285025d053e81010001	\\x9550211d3cbc89ac0b43fd1fe2fdd24b918cd23572c2075377493776a1e597e71cccc7ceb2a6802d4392e881455a080ae690fa9d7f269deee21451a9154fc104	1659577288000000	1660182088000000	1723254088000000	1817862088000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
415	\\xef6b4e44e528ac96b268f2c398a1ce6bc7c2f6fa12cbe45d14442aa00be578cc90975c7ee1e14b576fa7b768dc7c2e1838ea7fcfe4b9547065341ec725692e2b	1	0	\\x000000010000000000800003b7eae8643dda30f07cdcb242a67fd602e25fdf7a05ed793c8987ae5dac71bacf772dbaa23f004b254a4761d9477f92c5a91bc8680c8b528f3d924637eff3089b6038a8b53642ef2580b7e35ec925beb5bfb3a265d19f17fba2e3c11d97f0c5d29f2d53330b6428e1d1d8c91ad5166ffc4c2bf6d3f0af4c849711877486707417010001	\\x2016276d3cc704287d2d3a83b0981508467c729fb4fab4885bdac3261c98645d0353d72100f33ce45f7396c82362dae1c6fcdcb5eb71056e48727377c10fac0b	1647487288000000	1648092088000000	1711164088000000	1805772088000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
416	\\xf08f04e0c0db306c62a17159bf7157191435d1ebfbc6ceb2c17ff6dcee598e1c332b6c507a60197500618cb768565689a1c3b098fb4b8a4eb097c6693d8e0006	1	0	\\x000000010000000000800003e23c4cb6ff0e0b955e13bcea513ded0dceb2e76b8553ac08b6340082400e4d51a31dd3427fe196588f7b049b46f20774c9ff0f6cb596977f1b088d6bde4fd0b741d5a2b6e380250444b6f31f9bd62d2baec4d6d38b18c9c04b156e2b61ff6e22f01cadfa996cec2ac1a832698ddd29b91899898e370e8a2fdd8def6b4db843a1010001	\\xee3292dc3f3ba866d72849895c70eebb7e5f89cd3c2bedd1fa287c80156853b844a5c7f2c5c18d28e061fd1038da8e800a85e17aa6cc865e897b692e2e5b8206	1657159288000000	1657764088000000	1720836088000000	1815444088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
417	\\xf13b8e6192c059e24a88874c29787f27cd51606fbdb50619094ac124cf8c5b9fd2c5f05e2261f1f58bc29833a8cb8440bbff769d8d31ecd33b99cf57b3f6e6bf	1	0	\\x000000010000000000800003a844efde003f0d2ee0b3b638632b77e2f9f4a58e09618183ff713d19a8e184e9a5fb7617ae75d30a7e8df8835deee3e477e7d20ad7dc9431feeabe07f6bd3eeb1f345d4a4f2c6490295d2ca4d3493e8dae982b1a4bcf53621765b35e996d009f73a5cbb98121d79d445558e4a1f7461c3d7b85af76104a2b9c4befc30e37bfc3010001	\\x6b6fab6d75d5b2e6b43309bef9af773c389070fe5d655745686c2ea8604c7509a572802f95192b6301beec9df06001b6f1e296ec405a6456b1663514813ad409	1663808788000000	1664413588000000	1727485588000000	1822093588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
418	\\xf3ab77e74582a6f18219a47eeef969474a7620b7fd39c0a01f405ee26f56a243c7c1e557b01681aeae31b316dd6f08d8fcd477a413165c74bd04d32eceb1fa6a	1	0	\\x000000010000000000800003b987e9c8bc7fb6287c9a8744e966355d794d944e6a2db6ec63444b36c390d6f6e8dc869788526fd3c9a4c3763f15eb60c8954bee0a9f6b91a69db462ba7a750e81f6ac63c0fbc2e4856691b0b65fde9bfa8c94d3a255808e2f6952722b608f75ee247083c042bba2a8d5d80840e54bd0710b9da1ba6c85fff68d1efbdd396441010001	\\xadc36f8561fee4133adba746ed98e11c5c95dcaba1feb9d4cf169d0958fd942bfb63dee12f16ac500821e43859ea797a59a69071ad9cb604863233edb6d29707	1655950288000000	1656555088000000	1719627088000000	1814235088000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xf6a7082d9068c25c68ceae634f438ca5d04b66f86ffd2048fce7f28c0f4890110e52dbe357dc32b356897d19bdbcb55f207ffb342dc1fb8a9331b0ddeb5df9aa	1	0	\\x000000010000000000800003b496547f3b1d6899b1a5e1aac9779443fce0a72e52bff9b5e970fab99ddd58f7bc21e8bafdabb7853e716d1a05758050c01a1889aaffc83d1bfece151a0b1ff7c2b3a2568ded1ba5e13980cbc50249eb8d33a1097878ada5a5a70ec4f45b3a8fc14f0a7164dec348ebce3fda49ed76886558350e84bade1a60d884391d97b23d010001	\\x3238e5d07f199e242d240ae3ccaa464caf35c31f708b924d25870341424b9a6ea7b9ab68549da11b71970714b4551bf515f74ab78490b052acca3e9a7bc71605	1666226788000000	1666831588000000	1729903588000000	1824511588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf72feab3e90ed8947ee0c563a5c7b88ba6822dc9d02a6d5a7e0a7b9080839cb2b3cf161043dd60dca071f17019524543f27dd4b34f49aedc68f46b9ddc09d714	1	0	\\x000000010000000000800003a5336304a9c8879e4d9c41a0b0822a469132d487073ee7b74ef3f4c14a88b74d72ff76abca36144135417c0c7bb993e927b1030528638bbc10023ce973bee496673818b282342c2f9576ef63e1df6952423df404f2a19ce473479e0eb24c8638c21eadcf0d5743ac0c5417d5b965d47aac6c313bcbad50bee02b9d303a5c13e9010001	\\xe0ed7eb20dee3b89c6106ccf87c160611cf688e7f7667bb2426c8c5186e97daee32b1a2317848fdd9d9e636494f3f8dbc89ca9a52328f414b8f90561414ba405	1651114288000000	1651719088000000	1714791088000000	1809399088000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf743e2a094002ad5410cea052d7c9a795259674a3cb5e04c6c2d42a34859fd023a66e3f9faf9a14913be4201b8bb932b2429aacd8a14d3319b5d7db1ab4a3662	1	0	\\x000000010000000000800003c81b9c67e647cd05b3d3ca2ca9cfd68040132913f75a629146b85c64d88be15a25f24d5e40416a87e54d05f33d9f01f010f64c99d928112ae2c06c6f031760823d72510f2ec34fc7b8e608e0a6971ac4242e8d7dd2dfb16c9afb2d8f42f55ea2046dd3630e0b2c3c1a8cdbd9db664796840c90d74d765d249577e0c34fdb8317010001	\\xd329f61bda6461e6d71aa552b5479a29ecad40d7093249341d0e5ec80a631521453248dd0d8804b43a782e775fbcb66d914cb78437c0bfe2c4d5ca2e92ebb509	1669853788000000	1670458588000000	1733530588000000	1828138588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xf947af0e7c91eda351348ec155b2a84ecf9d6c0d5bb8b8eb03328492db524ecd10e2fa8b16074568f78940bea054a242dbad5dc4706d6d790e910f331e76674a	1	0	\\x000000010000000000800003bb193b2f128f658ef58a6a2cc9011e9d5bd3d290a8e55ce5fe66b0fc0852556090406608e678b636094662bf378db4423042837f823b39d221782d5cc0f0c3ed48289b0bae436f26ccd7989661a4929bc8bb2ad13ae944115f5cfd9e425b96f3eb7515fabdd5a1a9a9e7760875ec5b4534e5daef0a78990bdcfc778441a8d72b010001	\\x82a93504882d6609c8ec8abcc9ba2d565cdefbc072033ed3d06742e3a4e41bae49a42c645d09a7e4c94224d72df5a69916c9c5ec77414c148fc2a1c64816ba0c	1672271788000000	1672876588000000	1735948588000000	1830556588000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
423	\\xff6b7492e09cd6df840d7421eed8f145c949ac7d2e4d1ed0b609fcb07b042cf891add40e4e42f12fd691129f10b8c03514efc013930b2d6cfb80d511653c4f50	1	0	\\x000000010000000000800003bd26a9a172142dd9c36fec738f3c061a040f53ced257d5e5249bc14c0c025b0b30ef83700a3140c4fc8aca5adec056595b183a4057dc46928dd510cb23236c3d63be2d7bc89bebce0a7368429fdb8ee5d32a124c5f0584a88443eae4c153aec9d128174c7b5f1bde94e92efac834370612a6279afe464f7ba512ca4e184c528b010001	\\xfe344a2b555dcbbd4ec21dde7639b1bd2d3b5ffe9329b60fa61de84d29fe6608700ad11fec799d26fd0e3fbe7bb2524ff191c3821434250a6649f063f5ab8301	1651718788000000	1652323588000000	1715395588000000	1810003588000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
424	\\xffa7504aaafee9b922c564a4b66b6a1a55c9517736551839106a775929fcdda2aa59dc029f140fafff2ae92301f583266e6d73cc6b394df9f52918595f8fdc12	1	0	\\x000000010000000000800003c763dd6e678cc83f0ac0d0dcd12daf0ade236e98ec0c3b8ef674a3bb8c62d17e11fac8e58d1af077d00d9eaffe0a5201ee295b9f54e7c85fd476f37ad13800f0e55f67794e867249364cb3f6b712e2deca19f9412b4301bfdbaf5ee999955f5e0e52632d09d1a4f6f6a8fbaa7a0a0ddb6042e9f614d73e6e84378c55e54c8e53010001	\\xed7db742ad6af071169398599f4c2011b2bd1b59bde68ca6a54872b017edc8cb8290325a3e8b63e10ff2e5c63936d7389be86f55e6176b50e326a34f397fb701	1660181788000000	1660786588000000	1723858588000000	1818466588000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	1	\\x4b112269a72668e2eab749d03a23998ff596c9bc7b9977b4406bb9cd48e5e0510637a4ad5b246938c022b78ff36305bc160ceedb6c4ec961a8baabcff01d1509	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xfbcaecc5a4b214030b56396c4049f280128867cf03b8de7752c76c3e3e6867e9abaf73d9c82dc22353240808a05fbc57a7d76255600888018539d70c54dcef25	1647487307000000	1647488205000000	1647488205000000	3	98000000	\\xd5151b6010704cb936059b475736dd3bac001bdfae12db7c0f3eb7aeefa718eb	\\xaacd5c883c8109599c5bba900ff13f64c713c60464a0d2231d7cde4ef08860a2	\\x846728e6a5f99ea1b1fdc928ae3b22a12c39dbf6b7e3dcfffcc2b47e11b3a26c01b67180623622bb7fe267c3b8ae2f4f012c0a20470cea786213f71898408c0f	\\x9e6363499f5c663293f10efe7f72a7c76cf3bac925504b21269775abcc978d65	\\x204f6455fc7f00003f4f6455fc7f00005f4f6455fc7f0000204f6455fc7f00005f4f6455fc7f00000000000000000000000000000000000000cb09169d43aefa
\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	2	\\x15291e7aa8a63a13ae6f7e49b1de67393c0fb8806ac4940b5bc1a00564fbd6ecc1378cef019cf9a5e7f9802fa3a8f953f9cc4c3e679cccf229d3111465f81696	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xfbcaecc5a4b214030b56396c4049f280128867cf03b8de7752c76c3e3e6867e9abaf73d9c82dc22353240808a05fbc57a7d76255600888018539d70c54dcef25	1647487313000000	1647488211000000	1647488211000000	6	99000000	\\x31d096ff20502cd392e0910245298504bce983ff6111f77a7270410e51d0b391	\\xaacd5c883c8109599c5bba900ff13f64c713c60464a0d2231d7cde4ef08860a2	\\x16ced4c1cd33dcd65469f65e0931adafe79df09d8fb6953f8406559d3ef6e8e55e363e62064662b1bb7df1274b708240d080b1ca0ebbf14ebbefb8fce132720a	\\x9e6363499f5c663293f10efe7f72a7c76cf3bac925504b21269775abcc978d65	\\x204f6455fc7f00003f4f6455fc7f00005f4f6455fc7f0000204f6455fc7f00005f4f6455fc7f00000000000000000000000000000000000000cb09169d43aefa
\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	3	\\x662e9352551e4867aa5d2a2c5af50350f73fb3d1f0ae8e98f244753e2ff656beaec4a2aa7b4ccaade92bae5bd5cf332b086218a25c13b6c8088796bcb2d8749a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xfbcaecc5a4b214030b56396c4049f280128867cf03b8de7752c76c3e3e6867e9abaf73d9c82dc22353240808a05fbc57a7d76255600888018539d70c54dcef25	1647487320000000	1647488217000000	1647488217000000	2	99000000	\\x1c98b32f4c3183e7ffa0f825d5e2dee5adda9a6b5334c29bc76e6ad05aa74c7b	\\xaacd5c883c8109599c5bba900ff13f64c713c60464a0d2231d7cde4ef08860a2	\\x513080ba85144678a15c1ed8335841a3e3d377f01e99ca2dc25c8a4969757e90bc265752e366c90ef99ff4155720b26349fbd64601c1a1b0c2d8f9946603a504	\\x9e6363499f5c663293f10efe7f72a7c76cf3bac925504b21269775abcc978d65	\\x204f6455fc7f00003f4f6455fc7f00005f4f6455fc7f0000204f6455fc7f00005f4f6455fc7f00000000000000000000000000000000000000cb09169d43aefa
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	645737653	1	4	0	1647487305000000	1647487307000000	1647488205000000	1647488205000000	\\xaacd5c883c8109599c5bba900ff13f64c713c60464a0d2231d7cde4ef08860a2	\\x4b112269a72668e2eab749d03a23998ff596c9bc7b9977b4406bb9cd48e5e0510637a4ad5b246938c022b78ff36305bc160ceedb6c4ec961a8baabcff01d1509	\\x5b06a5b1b8897a72c582f6b553f3f4400843625f9e78135d90d3053a9d7ad0dc68030404aaecff5d85ba52f95b47ad39a7c464682b6a48f35b92fbc4b536c80f	\\x0a9d4cb4f215e705764ee55db5a84af7	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	645737653	3	7	0	1647487311000000	1647487313000000	1647488211000000	1647488211000000	\\xaacd5c883c8109599c5bba900ff13f64c713c60464a0d2231d7cde4ef08860a2	\\x15291e7aa8a63a13ae6f7e49b1de67393c0fb8806ac4940b5bc1a00564fbd6ecc1378cef019cf9a5e7f9802fa3a8f953f9cc4c3e679cccf229d3111465f81696	\\x0503d70e6fad2f48c21ed430fceca24b98075e6b4b1216f671646583717ccb3f5616d68d752c16075715cd43ed42c50b88e3eca7ec41ce97b9780dd071309100	\\x0a9d4cb4f215e705764ee55db5a84af7	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	645737653	6	3	0	1647487317000000	1647487320000000	1647488217000000	1647488217000000	\\xaacd5c883c8109599c5bba900ff13f64c713c60464a0d2231d7cde4ef08860a2	\\x662e9352551e4867aa5d2a2c5af50350f73fb3d1f0ae8e98f244753e2ff656beaec4a2aa7b4ccaade92bae5bd5cf332b086218a25c13b6c8088796bcb2d8749a	\\x338f8272c5b194fe5d5c575689ae802207971dcaa7c88969671c897d990396282e8cbd30745c61d4d3b09edcff77536aa1d4ebc62567946bb6d7b7fe5fcdd80f	\\x0a9d4cb4f215e705764ee55db5a84af7	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
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
1	contenttypes	0001_initial	2022-03-17 04:21:28.438903+01
2	auth	0001_initial	2022-03-17 04:21:28.59727+01
3	app	0001_initial	2022-03-17 04:21:28.723044+01
4	contenttypes	0002_remove_content_type_name	2022-03-17 04:21:28.73539+01
5	auth	0002_alter_permission_name_max_length	2022-03-17 04:21:28.744793+01
6	auth	0003_alter_user_email_max_length	2022-03-17 04:21:28.752525+01
7	auth	0004_alter_user_username_opts	2022-03-17 04:21:28.760769+01
8	auth	0005_alter_user_last_login_null	2022-03-17 04:21:28.768108+01
9	auth	0006_require_contenttypes_0002	2022-03-17 04:21:28.771729+01
10	auth	0007_alter_validators_add_error_messages	2022-03-17 04:21:28.779087+01
11	auth	0008_alter_user_username_max_length	2022-03-17 04:21:28.793999+01
12	auth	0009_alter_user_last_name_max_length	2022-03-17 04:21:28.801573+01
13	auth	0010_alter_group_name_max_length	2022-03-17 04:21:28.810943+01
14	auth	0011_update_proxy_permissions	2022-03-17 04:21:28.819084+01
15	auth	0012_alter_user_first_name_max_length	2022-03-17 04:21:28.826503+01
16	sessions	0001_initial	2022-03-17 04:21:28.860178+01
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
1	\\x861366879db7eff6374d19e3183b5bbab4f6db79f3636891313e425a2f135fac	\\x3755171c82a2e97cbf4d1a7bf2e10a9c1e928a79387d55ca7910043129d414e95303e5e26a814317603650c6c113ff7ce025610ffe137d5b18549a31696b7809	1669259188000000	1676516788000000	1678935988000000
2	\\x8f95dcc4778995a99e817db0793d19055e285fc387cda5d610560b1242f43e04	\\x37160f9e27d6fffccaa37f5315971b4c2ecf420dc948762ff9916017f4989dcebe61d42aa6a76e262f7fcc9f7897c6f9c697aa48d22d15a5da0d5cc3d3852c04	1654744588000000	1662002188000000	1664421388000000
3	\\x744c53a12b9708c6d85c8d67b58ea4a7916e457137ae1371e030f681e088e218	\\xc9fa0e1f9fb2f13a15259338e86196bf4f1579e2ff0b44922e8e24cc9a958b69605ddbd916481f0aa13d536f761637476655eef2c16755a007ad09800ee49506	1662001888000000	1669259488000000	1671678688000000
4	\\xbcda30589afd7203e1e9a1e1d3285951740b283ca7815648dc3bf560adb29dec	\\x31ccd5eb63dd3b9668ff2c095ecbd125faca6d49ace6da296819c5d22e1b6547dd047543f7ca198b88ba07e76c92cdd87328582e7d4828bec26caf9ceec94101	1676516488000000	1683774088000000	1686193288000000
5	\\x9e6363499f5c663293f10efe7f72a7c76cf3bac925504b21269775abcc978d65	\\x024e2e010c08df2ba31b5799c0b929de4a250ce6199dbaa16f90ade681a3d6ce2311fe551dbfa0122bb5d6462677037f97afe10354f1ed1e37881524cfedf702	1647487288000000	1654744888000000	1657164088000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x41e94e69c44f19a0a21a5ca51f7c54ca18f20c050af2b7aa37db0c5c9295f5789bc3ecde4564c20377bf7d334a23bb3d1258cfb5881fbc8b6a03c72bb3c1d502
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	384	\\xd5151b6010704cb936059b475736dd3bac001bdfae12db7c0f3eb7aeefa718eb	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000007c3eaa5b52b90b4e481050406db8b08eeca52d644034e60774741c3e05a8950ea51235d026feccbba003d89b6cfdf32fa46260adc16f2f9df2efcf059a98191f3fd02dd648092592383123f8541e30aa81357f5cc580304ff787978f5aee8b134aa4dfc0231f84b4be227544fb7cdd726d2572da483bde7f3730e1c1d01f8e0b	0	0
3	28	\\x31d096ff20502cd392e0910245298504bce983ff6111f77a7270410e51d0b391	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000a136b12fe8924c8bd85ad932e285d3053d047c2d3a4c84023a7fad0e3b76fd7d85ce33696a2b6f35e8f09d6f45a2b0c91083a72b7e2cc4ca9f2f18fee079e59033cac9b6b2da515e81da91aa4c95af336b98341240a8bb0663570687447264d2da932e5818a4ec8dad4fafa1c2ed910b1575c8bca77ed41a15e03393b21cb7e	0	1000000
6	83	\\x1c98b32f4c3183e7ffa0f825d5e2dee5adda9a6b5334c29bc76e6ad05aa74c7b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000af3c5be45ae05722d47495fba6d06e0e09e55f687970e42dc8f4d369b15f5515ae5a243320f46886b957beb585ffb24dd920124be8c3e147432b4ba3ae4964bb96664c9ab1722820c9956ce5eceafef0e485ea6c7b8279de008ffe4aba048504d8bd27c4a5b489abecbc6db8851fc156639d8cdb097936da72931278c06a27f6	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xfbcaecc5a4b214030b56396c4049f280128867cf03b8de7752c76c3e3e6867e9abaf73d9c82dc22353240808a05fbc57a7d76255600888018539d70c54dcef25	\\x0a9d4cb4f215e705764ee55db5a84af7	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.076-00CCCTF11BHV8	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373438383230353030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373438383230353030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225a46354553484434503841303632545037355034304a464a4730393847535946304557445758544a5258503357464b38435a4d545142564b563734325647483341434a3047323530425959354639595143394150303234383036324b4b4e5243414b4545593938222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037362d30304343435446313142485638222c2274696d657374616d70223a7b22745f73223a313634373438373330352c22745f6d73223a313634373438373330353030307d2c227061795f646561646c696e65223a7b22745f73223a313634373439303930352c22745f6d73223a313634373439303930353030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d444e454751375345454e46314e57324348315a565a58324d474e36484739425834563347314d4a464b375639394e5231415147227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e42364e533231574734344e4b373256514138305a57395a434b334837484734434a474434385258464b46345857343843324830222c226e6f6e6365223a225759455658563548464e475737444e56483148594e374a45344e4e58464d545a4551505a50584b5648355335435738514d483030227d	\\x4b112269a72668e2eab749d03a23998ff596c9bc7b9977b4406bb9cd48e5e0510637a4ad5b246938c022b78ff36305bc160ceedb6c4ec961a8baabcff01d1509	1647487305000000	1647490905000000	1647488205000000	t	f	taler://fulfillment-success/thx		\\x369f1055dad42697e40aad67228b3798
2	1	2022.076-03MD4NYSEBMTP	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373438383231313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373438383231313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225a46354553484434503841303632545037355034304a464a4730393847535946304557445758544a5258503357464b38435a4d545142564b563734325647483341434a3047323530425959354639595143394150303234383036324b4b4e5243414b4545593938222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037362d30334d44344e595345424d5450222c2274696d657374616d70223a7b22745f73223a313634373438373331312c22745f6d73223a313634373438373331313030307d2c227061795f646561646c696e65223a7b22745f73223a313634373439303931312c22745f6d73223a313634373439303931313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d444e454751375345454e46314e57324348315a565a58324d474e36484739425834563347314d4a464b375639394e5231415147227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e42364e533231574734344e4b373256514138305a57395a434b334837484734434a474434385258464b46345857343843324830222c226e6f6e6365223a223458364d54303351524e5343364d4746383943533859505151474b353348514e4e52425834485946433033435244463442305930227d	\\x15291e7aa8a63a13ae6f7e49b1de67393c0fb8806ac4940b5bc1a00564fbd6ecc1378cef019cf9a5e7f9802fa3a8f953f9cc4c3e679cccf229d3111465f81696	1647487311000000	1647490911000000	1647488211000000	t	f	taler://fulfillment-success/thx		\\xc498bbdbb82608831364429bb9df2ce7
3	1	2022.076-G0CQY7XTHJZGY	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373438383231373030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373438383231373030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225a46354553484434503841303632545037355034304a464a4730393847535946304557445758544a5258503357464b38435a4d545142564b563734325647483341434a3047323530425959354639595143394150303234383036324b4b4e5243414b4545593938222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037362d4730435159375854484a5a4759222c2274696d657374616d70223a7b22745f73223a313634373438373331372c22745f6d73223a313634373438373331373030307d2c227061795f646561646c696e65223a7b22745f73223a313634373439303931372c22745f6d73223a313634373439303931373030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a224d444e454751375345454e46314e57324348315a565a58324d474e36484739425834563347314d4a464b375639394e5231415147227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a224e42364e533231574734344e4b373256514138305a57395a434b334837484734434a474434385258464b46345857343843324830222c226e6f6e6365223a2252583241314e345432344e4b3130544b3747304e315a3452324252303552594d58355946454456413245515a5452393157565247227d	\\x662e9352551e4867aa5d2a2c5af50350f73fb3d1f0ae8e98f244753e2ff656beaec4a2aa7b4ccaade92bae5bd5cf332b086218a25c13b6c8088796bcb2d8749a	1647487317000000	1647490917000000	1647488217000000	t	f	taler://fulfillment-success/thx		\\xe80af076ac09810b3dd2845187d6348b
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
1	1	1647487307000000	\\xd5151b6010704cb936059b475736dd3bac001bdfae12db7c0f3eb7aeefa718eb	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	5	\\x846728e6a5f99ea1b1fdc928ae3b22a12c39dbf6b7e3dcfffcc2b47e11b3a26c01b67180623622bb7fe267c3b8ae2f4f012c0a20470cea786213f71898408c0f	1
2	2	1647487313000000	\\x31d096ff20502cd392e0910245298504bce983ff6111f77a7270410e51d0b391	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	5	\\x16ced4c1cd33dcd65469f65e0931adafe79df09d8fb6953f8406559d3ef6e8e55e363e62064662b1bb7df1274b708240d080b1ca0ebbf14ebbefb8fce132720a	1
3	3	1647487320000000	\\x1c98b32f4c3183e7ffa0f825d5e2dee5adda9a6b5334c29bc76e6ad05aa74c7b	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	5	\\x513080ba85144678a15c1ed8335841a3e3d377f01e99ca2dc25c8a4969757e90bc265752e366c90ef99ff4155720b26349fbd64601c1a1b0c2d8f9946603a504	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	\\x861366879db7eff6374d19e3183b5bbab4f6db79f3636891313e425a2f135fac	1669259188000000	1676516788000000	1678935988000000	\\x3755171c82a2e97cbf4d1a7bf2e10a9c1e928a79387d55ca7910043129d414e95303e5e26a814317603650c6c113ff7ce025610ffe137d5b18549a31696b7809
2	\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	\\x8f95dcc4778995a99e817db0793d19055e285fc387cda5d610560b1242f43e04	1654744588000000	1662002188000000	1664421388000000	\\x37160f9e27d6fffccaa37f5315971b4c2ecf420dc948762ff9916017f4989dcebe61d42aa6a76e262f7fcc9f7897c6f9c697aa48d22d15a5da0d5cc3d3852c04
3	\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	\\x744c53a12b9708c6d85c8d67b58ea4a7916e457137ae1371e030f681e088e218	1662001888000000	1669259488000000	1671678688000000	\\xc9fa0e1f9fb2f13a15259338e86196bf4f1579e2ff0b44922e8e24cc9a958b69605ddbd916481f0aa13d536f761637476655eef2c16755a007ad09800ee49506
4	\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	\\xbcda30589afd7203e1e9a1e1d3285951740b283ca7815648dc3bf560adb29dec	1676516488000000	1683774088000000	1686193288000000	\\x31ccd5eb63dd3b9668ff2c095ecbd125faca6d49ace6da296819c5d22e1b6547dd047543f7ca198b88ba07e76c92cdd87328582e7d4828bec26caf9ceec94101
5	\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	\\x9e6363499f5c663293f10efe7f72a7c76cf3bac925504b21269775abcc978d65	1647487288000000	1654744888000000	1657164088000000	\\x024e2e010c08df2ba31b5799c0b929de4a250ce6199dbaa16f90ade681a3d6ce2311fe551dbfa0122bb5d6462677037f97afe10354f1ed1e37881524cfedf702
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xa36ae85cf973aaf0d7826443fdffa2a42a68c12be9363806927ccfb4a6b80aaf	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x56045e5f13a2d02121b82ec3ee127e6e0279d6b491bdb780728115269164e2288036ec5f644ef9179884f08dab08d6e5bfed956974540b470e7a6872f3f58a05
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xaacd5c883c8109599c5bba900ff13f64c713c60464a0d2231d7cde4ef08860a2	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xea359332f921ff9fc0b21d02c1a68ca7b69233d7d1f6958fdd8eae9e7852623d	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647487307000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\xa403a741613a353d75674a717e585ab1ebe296a0bf4356aadfb3528c001dcf70e278681ae857d2838c2e41f87ae2fec75c053e9045a50807e4c4c60187f0a404	5
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1647487314000000	\\x31d096ff20502cd392e0910245298504bce983ff6111f77a7270410e51d0b391	test refund	6	0
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

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, h_age_commitment, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x82d7f085ac08d93a6c0b69826963c13a86b981c5625229043bb85a8e9a8d99d922939d4485f90387ea6c2468a20ff7ec0ae4dbde1f3ca33b70a59a80bcae0111	\\xd5151b6010704cb936059b475736dd3bac001bdfae12db7c0f3eb7aeefa718eb	\\x0000000000000000000000000000000000000000000000000000000000000000	\\xe1dde67e34d085f1e082315b9ce67461e652d8f6c9a77cb191593035cd6ea67c68815e7b230f1a96eb786c994ad5c771b91fe39285f5c2c2d2730bf96ebc250a	4	0	2
2	\\x23b902d225a6abce2d581f7fede7ac5a7a2f37c5d7c9cee16b113d57cf5f36bb778d16eaac51df0e32c3f143f684e4e41fb977fb50daac86ebc2c544ecbe1070	\\x31d096ff20502cd392e0910245298504bce983ff6111f77a7270410e51d0b391	\\x0000000000000000000000000000000000000000000000000000000000000000	\\xe3ac9e2ed2358acd9648f96e571efcbaf3a3f83885f732c8de5e8069243bc294fad654031fb25033b4be9d447a95b4e1aa274eea054ad3b5a1f03f4b20d47904	3	0	0
3	\\x2ad00cb08d7b5bc148ba37a25d763f5d442a43c0923bb8f3e1c08f5a3b84b42a471f8859ab396041f70cc904b591d513b829bc13fd45783c47d7d93eb5b2c305	\\x31d096ff20502cd392e0910245298504bce983ff6111f77a7270410e51d0b391	\\x0000000000000000000000000000000000000000000000000000000000000000	\\xc6365149fa80821f0b1db5c62228c12b9a94284236dadf706c613f7d1e1f3a370c9f03606cf8c5053fc0feb721eca7d4d1c5d1da43007480ed3d45ac42b15409	5	98000000	2
4	\\x20e9cd748ebfe4240ceb397934b4392ab3b453faac14e932a219223c34fe6ac69921dd74f32e8cc8507b4e1eb8cb6aff93f8e23a3f4b577aa915d305ebb01659	\\x1c98b32f4c3183e7ffa0f825d5e2dee5adda9a6b5334c29bc76e6ad05aa74c7b	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x97cd72efa27394b5908d2f1c06ba3e9dbcd5715f224227126957bf58a8553209c00b12b891be8b5bee12fd7c396703d7faafecb767365047ff80115a3460010e	1	99000000	0
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xeeeded0a2db1db5b5f10f657b74f8d8156dd43342dd950d30bfd3e28469a3f5002c872ac9caafb52c4a767ee77396a694279397b8d691eb1e272f110affda602	299	\\x0000000100000100aa6692404477dc1f54422c549c5360937242c00bcd09652879acf0d95f4181ff05a394a14002b8cec56a65b9ec57c9bfd036c7147cdd90cdbe6ac97523fdbeaa7a791484d697e2a66af7f4db924fbede61663568793c870536118a5c5e965a48bac1514159c7b43199f7467618bd21ba63750fd13ab8074dd260021e991d78bf	\\xd52affffd6d2332c5eb1e38fc7f9cd8f58eaf65f0443506c82585ae67d92236d58832bf30d4fdad0dd07fdcf73f57ca146d38806a94821976df325405d998227	\\x0000000100000001c6be9bab39856ef085eda86f5fe08c4d37b3066de1eb2e69036775e0b7825c99d64642d027dde09b06261360d300e4cc177b575d5cc9c2aefbabda5961981c603d4552f1af3ddd83ec68ca49107b672658e904b5f431aa6012c5c236ac5949aa80d4e75895f097130e56bb79fa00c3c76593ced68b37fc1a856d09346caf9565	\\x0000000100010000
2	1	1	\\x4bf02d99a90256aaf322936cad8ab7be0dbc9f9eb5eaac4222e340a4b930f1cb2732d3915f71dbc4b1df50b34a47d850cdd812f575bde21fd5a1f599df982604	415	\\x000000010000010014a509c1d7a2860f5f9700b9bb0046af8e2698236f9a346408a793463aebda5c5241b43460897f447dc575e79669f9155b756262fe7b776f052ed49c523570acf4809878a1d59627a8546b846a0eb81a1e665a6b1d2a9cc35f22388147fb69ef2ae07780d0f5e0899bd3715bbea86b798a77e6a7a36dd18a3fb9aa56d38f7e05	\\xe2b73e1e7e41155896d04ad64c9632ab7accc94ce066508e5ee5becfe0f619141c97da46de0e6a2a357d9ac08987f516cea0cd940f55ab5beeeb4b7ee3292e9c	\\x0000000100000001a67afce7c65b7889a5b0a5cc36a0b3577be99a7e27449dea3c477988bab42c5d3619d9047601b7cc13df0deccecc8632450744fc00e20f1c9134a30944c8992028a5e27f01368cb7360f29fff4c3695ccfd4da84df79c491257991256deb8a7643c3f3a01cb1a426d1fb8eb4a0452cccb8f6fd1ff027b4f424ea600a7b28a65a	\\x0000000100010000
3	1	2	\\xf779d3639713c7e504f78824faf81080921e604f6007f6439bcf836cdde52f0b6ddddde0be19e0ae06ff635658a7236e6c94def96681e4c21025738120f30002	400	\\x000000010000010029e7707dce863adb6f59eccbbac0b40d3feaba8bd513fcfb78d4d1d03098f52885fb23c0643ed5d5d87440f5e99d2c4dd4e81a9ccde9037da50d8d928df0b028d0b0872fcfc1e765f97b9b3cfcb38e78916d0cfca43bf000a4d2e606be13260cc090d6600e5cf0ae731f8efd5a720355eddde83aa2ef18aa0a8ab3537311c6a7	\\x38775a5d330db0c40e2321eddb018055c3a9c2362843739e68ddb66ad37480fb0d80a8daa8969e6e7cd8c82a8c466a4b9f357076ae3e80487b1c228c9715b66c	\\x000000010000000160fb73f304ca8d2d7edd68c5346080b17d4b4683f742c27920525435604861ffbf458003a05e852984c0ecb4d506062617bfcc24bba92a44ceefa099f77fe4de1f24c26b93674ffb4fe544afb1da5fca89d694f934660fa8af609e92b8bbfd792ab344f914a6f3946c70265860fa63b0f674e990c175975bac42fb79674e3a6f	\\x0000000100010000
4	1	3	\\x68415a1c44b7b7992944656403558749a4adcd56fcb8d32c785366685c391b4960932356f46787417c56da3b5cf3689fb50949baad74415d8f26282f7ca8000c	400	\\x00000001000001000a7936a677da8d60b5a7fa517f8797fcba018f8d0643311aff17a64c6b5b69768882e158e124cc999f6d2cec22e0ead136f0f6ed7d87d0ed61966aac5276928e757bbaaaaa08aa401b9add6c2956456fedee7b991e9900daaceb3e665dc5b6a4534e3daa694b8786c9a9ae1b7bedd90a29ba9491c01633a420ac05653abf7623	\\xec6fcd0403ca07b3db1f6f86300598956bf36d237bad52d76a475db8c830cea1e1a7204c5f54c590d57566ebe5b88e6899d17856ad32d24bf7a71e12df9f0d78	\\x0000000100000001a14a329b27029886889859919f1f40f0d11dd04dc52096a4f5055921c1123fb03633fb5e2c11cbba6a79bb0a161b983e7fe87bf5c4cbfd12d905aa9601ee08f5abe5fccd09fda5eee03a88be2619a3d904643461be97a8623097d3ab4a465be37438eaaac018834b587e8c9c109a1a1ab3df27fed82817acb1861e7649d8e183	\\x0000000100010000
5	1	4	\\x4d9b8aadf1ec6526cb9721777b888df64d9b487bcc96ae4952166fee769cac10a8e12f5f346d61ef62ceb9e47223baa29ae8f00e4bd3593843cb18a273b79c0a	400	\\x0000000100000100112d9e5e4a13c11f5b0756293ca5209b87b33b9db43e0ccc2608758937911793a3c63b6478ce340af1eab2ea974ec935d6c8f52527df5fca411024db2f24c256ea7c882033fac51ec5111aa0b0f8096addd9c54c5b3bee029c7b9edfe05bd7eb0642b36b79e2848bff8211f9faf69f1309bde6103dbb26b5b9cb95d3c9eac272	\\xd96f1de857db9a20509054198d6bf3a772cf81eb1c492156615e04015c67a167260657d190b75ce1aca93b1c344275fbff352120b2bd37459ebdc1b4b5cbb18b	\\x000000010000000150000289449aa2fd691b5a2d96616677a86abfdcb3e00b3f6585f485da753e9800977e0a87ff625ea71e53b4758917ac01da3ad6333775264d78e75cb2f920b92da754212756cb208e3179efb22549ebe265b60e6f7521ef9bb39608bf463aff9096097d5349b3a94412096560a5d0559b5c07b2498457b6d880cf5439c63440	\\x0000000100010000
6	1	5	\\x6ffbe2b15f14e25b606ac89e11d2b1b6fbd772a6a669c521d0b93ab329b359b6772d5b7d6dd5fac08e7517d62345b9eac1d1b4b8065d1fd53ab3222f37c97e0e	400	\\x00000001000001003bbd2a32f59709768a42eb0119958f672af01b2d5be26b4e687ef846f821ac2fccea8433f9eea66599b5f24b28917f10938ffea2dd82ab2de7c7769b77754a68e38c866b7f6de2f7a0eae6f1aef79bbc3fc0235ebcb681adb14f84527d48a53a9b177605cfd6330db5d953895d7b8545bdb80e9d8ac1695121cdb06bdf2f9054	\\xbdb865f8b41104a74cee0d316bdba126ec39f0c7d4e99fe9d31a05c83a15a449ec2d9c9550f0da06b658b66acce214d7825ff298365aff95449ba932e691e7b1	\\x00000001000000010fe60d2799e83bef38e5e180e850430f6018064528ffddb965259b728f6e71632ef043bafaf9798da99b13d077ef6a2ac3539c3e45db5c9fb115c0683dad8f73217c606424811e4d95022b2980cc4163e8680c0b93432e373d9abc5fb46a598f57b1f8cd73c4fb28ce7d10ec60119d0abb2e90296c147e28ee642e5411459ded	\\x0000000100010000
7	1	6	\\xcb66f3b5658f1f45ef207b08b95b9cafe19f62e8ccb5b066627c3b90bc0d82473efb8141ad14a950985e7a341dd28229385e553e82f61ba5fe5df4fed3a51705	400	\\x00000001000001009391c9edda8125c804c4932b878331fa779de694466647d9bccd34ee9ce348d85b0fa8f4183fee7163f7701ed13bf5aae99c3672aa89af36f790662744e6e9384f22358c450ec8439bf3e1b90f4d0ef4b2493d1a2fb962c4acb2683bb2da05ccefa70404bea2d685259b0cc473f5676b67a77bf708e66ed8c53af2510b318182	\\x53ed76a56fc06b1c9c2dfac580c3e24822aa89c1af3049eb51cb07860178700004be7044947aaf79af321b05d3ecd466a06eb889cd4892c7d5a0ba55f1143175	\\x000000010000000102ebbd440df6eb30223a5e282f7cc9d9ca73091b6768c5db07cf51e5bc3123e71d889d2ad51a035cade6ad0e0751af73128d33fbb4b482d89817735eefa2821ae39c8bcc506b18a2a0095886386c7c9b40ee9ebcf8b722ac33b773732faab3b778af94cd02b3074642d6ba34dc24c19879c60e2d7abd532cece548b36614fb55	\\x0000000100010000
8	1	7	\\x8fa729ad6cc9d654c591827af468eb47683f41de0b5cab8a7d841cc1bdf22e7a7cab885f14dfc714dade920faa44094e7d1e47ed2c624c9f0c838489cab9de0b	400	\\x000000010000010046486f0eb439426107df436d40219ae65e823854a6d7eab55d2890ea26028854f6b77720185a6119952c378b9c9fa40ce5b0b417968b3ecaa00810e5f64295ff71f00b97ff4d85293143b5e844f184e30268faf7df0d15e0d6fc9ace8c7565ce271a8b39ac428d230b30c589aca8419a9a90dfad62162578ede5e8bd9ad626c4	\\x4a1ca7855147c6feba378ea99a4439930bf9b3b680194d32a808d6f222a20158ff3a2f8bcc05e1094150aec62d725e664b5a82e9421f1c2c2c209abf0b3814f6	\\x0000000100000001565e57f80fbe28808cf110ec5f68eea6e2fc66dc9b66c430f696d32da6e4ac3df24f8d90a6b48b28e00c487a31e7e9612177a93c9bb222c1097cb093f3437dcdc2e1eccdc641d6d917d960b66b24ba189d393e7126c12f477613943de22cc9641d12a60646ca69bf045c7ceabc7f447835f4f35dd11e2e4472d5043aeccb3440	\\x0000000100010000
9	1	8	\\x20af9c99547ad56c205bf1b00220a01f35db343639b4cd341bd42a5fa21d066b50fa85e9956d9b07c7d19e87b89e3018b2ff3daadf1180154d951b5be9fa640e	400	\\x00000001000001000a9ed306ef921169a719e9dea0195a215f99842e55e5e3957af816014414a01f0fb5a33378e80ee5aaa890cb16ee645dd150d72cee2e06c84ee68e609cbe61b124adbfa7a01506d18860f5721f16b399676ade57a113f5f857e7ad35fb79edfd653f0ddb4266519035e22fa8d2938a5d2516da110a1c244a3cb0412e15417b65	\\x3bde29b26635f12c1456c7f62899dbda487d3c851e2c6d939b7309e18b9ac9e6d8eea48245fa50ed6423ecde32409d5052590e8d887d18ef5a002fe45868ccb8	\\x0000000100000001696c22767ff9ccc60b16d535f1c7e11035a4e44bed31282d54d1433d524ac6754b3f1c5847ceb6b08e56b223a6bf715cdcd28dfa93638e29965d811cf1c1c74f553c85a162fbd8b362ec33c45e46dd31efdbe4148b423b18569381c8e662afbb221a38831f676453e44c2a3f87944122610f2cf408e96582b3f20631dd29b22d	\\x0000000100010000
10	1	9	\\xf8b2faf01c6a6ecba5cc3b8fafb93a37b016880d52feeae17d578b66eaca5d31d74f6b9e6a20577f13f8653a1c0a2d7189872aa84517f517ad070377170dce0e	400	\\x00000001000001006f0796942504dcb1f8c308b0e5d39117167a6b23edd0728af40b1d42ee8386936fb2f758fb72a5cf12f9d5085b9c8e255d5677d82a4c5dfffe12e60242d0c7a36fddd2af348e83fd484626c5883b6401835b76e9638950427b2cd389c52daf57082046e86b9b7dab59f51384ad80e1fff65de453bf9fbfe03781d97d5884ab05	\\xfd7b1a19f32506693dca6d47c2111cf3617d1c7685d71b3583a7f988cafb4bea4e567388a8bbd0195606e67e40afae2f7aa03f315e8a86c2b5eff9ec102230a0	\\x000000010000000116d72b83d6c0bed321328fab40bd15085caac67871e030f34134c24102b8cc7bb207e134ee0c9ddcb2da16fd91f035f8c8efa6d9acf03c421912fe827f02773ff60aa8adade95eec48d9780798b96117ec056166a6657ae984efdca50f0eade26d4b8be74d76d3c74fa0566a7d7e4c70f667c6ec6088d667cfb2ea0b6f1dbcd8	\\x0000000100010000
11	1	10	\\x151855c9041f3e843d5453f88afd1c6d2144c296cc021ce961b1f08ea0709be00f84039c66b5e2de0635d872e3129991ca2ce78e5758267b32bbeb14a26cd303	114	\\x00000001000001005170b7c1c8cf56e0b5caf82a47f079d23243bbb27ae26538a561f600fe72afc5acf50f41be9e03bb587e0a890bd84c1c4848f32a58aaa2bda831ad66acab08a46b9a0d940a039ffbe4a5d8d1047325604cf75f2eb84d23e766db257c4640fd9ba0035d795dc57ea48b4bfdee38833f11b449c3f201a3732ea6f3b3a475485f15	\\x3704e63c1fd296dd85d5b919217f62c70736db7d92346afdbbb0d8171bf38951c08a2e68f2156ad1d71108df32b03e509f21d22f5871b791f0a0add599ae4482	\\x000000010000000153955ebf40a40848382926e7f1f1290b92f7262e90ee8a08f90a38397e6c168e68dae9ecca8a978c770e6f65b2be9115f8ae7cf13932ce64b085ccf07b2c2805057a8225184a7e1a0a90aa90779a5df0066d97723cf3830e83507cea6089c818ddcbdd92440d0d7f98383d90f163326b76d40d349e158aafce70c72e46cbcad9	\\x0000000100010000
12	1	11	\\x7ec76be8f95bfed63cd0f42aeb9da1030589e7cad35c16b66cc3746b52afb11e8b1670cad7bcada432c884368ed2ba20b7ef045714a422d52a0562b02c6b6f0e	114	\\x0000000100000100310d5235dac05e0235db5699498ddfd1138bd4b5b053551a085c775dbff8c0de913526f089d27be05c0ce5f10c0b24e66a188ff44523140f071790eb4139dbeea11fe0ccf5c72dd2a3d1d0a9418c4133660e263b6bf6dc79934bcda34e82833b6b30adb2f7c6e2b91779cf0abeb79aa8d0ab136059f386a36b66ca202d074fb9	\\x46492aaf4a372bd7f503b0eee7c4e4a312327c953551e7bfb602a4cf1bbbb327046b37f8916adbce57d83196e0254a0dcc22ae0027fd88e2661159b707f700a2	\\x0000000100000001a7c33a6af73264d6041a5ca96dd13c3d30094a010f12dfe3b20c0cbe1b62a9c9142f7a0c6f52129a5695a13f69ba7127c8326a60f3034eaaef9eb34a6677b5929633f262adad7f27d7f6c69a5f914573ae371d736fa0db49b877b229881becce07fbb9e74e455b882024acf56b6cd5d0fb7fbbe3d6be2abd689cd809377b5a0f	\\x0000000100010000
13	2	0	\\x8be9eb94fa441095a11db239e20029bfd927cf2ef9f298a0801f96cf6324888b45878980f30e4b81fd60690fd8b9e88cc461c3789f784af017500b099da2970f	299	\\x00000001000001006acf4cc1e7162c2f9b970e285c347e8d4290aa60ea3bd66bf72bb09ce5f0edd76db2995aa951be90e3e9fcbdbbe3574e956245db283fa98e2d59ff0dd05ea6f33d9c86157bffb8e940939e46ca2cee952d7ebdff58df61c8d65ce5801c84e76fe1b32bc0a221ec7e76f47a68f6370ea8f17b73204e438560e5b47aa732fe330f	\\xfad98ca10039be02770317ab39373d995e84c88779bd2147c26091baaccfb2a5981fa5470e482264d67eebfa5eb88ed340cfeced6667b1ec253525a57af8101d	\\x0000000100000001d97cd60b1599ac5f65af52be7dba9dba1fe82f2683da7eb3e51d57ee4f1a72f8d224959d201cf17565f6ee7121d93e818812d8499da5d7d10deb95bef4ca8054b54c1f534257645d9cd09466da3cba57e392298eb86c960d05e3b00d675f3569ade99d9709e712cde89c0297918dac40783792211d829ea549488398983e9f4b	\\x0000000100010000
14	2	1	\\x66ddeabc477833e2c54e5bf80ab6883b1f8ff267002ca4800161b9b09c105b2fcec291ee854a382e5e25379f6347223f688c1646a52e3f454a68109a7e81560f	400	\\x0000000100000100a9af1cc031880082c06638312d3761dadc36f36d618ca4ff478e67939cfbd9e322b52f41015a7d2763d4b22e4b68588d14f2fea7c9fd341aaf895957e96b0cc4cf9c7cd8ba9bd09ed5e713d2ac17cda4c61e2184572673adeb2ecd82f6c51494f5cb68c837d7e098a5c22ee46c2063ed78e857bbb035300ceb6ed95854531afb	\\xc14776679e877012b4518058db5ca421e6a97aeba5aff32218ea2ceb9506838033378ce410e7a016ea22d7bce89e72db978f16f9427f452d6fb9d4771b2513e1	\\x00000001000000017262c31eeb90cb33e7dc0c652117fd2ef4d2546b878c700eaf9a5231f491c95f708a8223b485dbcce6ae51fb434a20d40b20655566f5438c98f8e9dfb0ff76a9ebe86604e0e822ae685611e324b264183b3336a539e0fc6694ea2c625e3e8c66537ddb064b0de4180e383c86d26abdeb922e155e760b2b4a75910bbda117cfa4	\\x0000000100010000
15	2	2	\\xf79934739c8e7125d5552bfcfdf5dd8019003b3665423e5b02f4f7d3f598c7035203a83579af08d155e0a29ca981d9b05aaeda60a0aa87daae7dbb3b1990fd0d	400	\\x00000001000001008cdf4238fda276941843757c4a3e2d85da29ad6ef32c9101f0e69c0747aafc27b50c6c6e70774d054c81371dff5270469bef1b4407802cad53c0020dc2e6b58113ff5cbd82352d1e21f130892510ca0b1a9aeab90f143a125ed6ea53d28cd7651c29e5a6214870a061a928df8a48fdf7de8e6fdaa51cef7d5f2510b5527388a6	\\xa5693dda23104fcd5099a5733e9c817c93dcdbd2d743748869ef8eaade19ec2b6aa970865067e564016d1616b13e951d744569798cbb350a21ad68c82fdbe2b2	\\x000000010000000198b37fca9a3771105bdecbc04f4c71afa6c07c4e46bd94b7c09998a39c74b13fcbe2e36bdc0d1b18f016cc48272ef41798bcf912573ed0f0eccbab2bd7c58f7f2a5719e17730741da87203c92d3abb5a4ede751f27471869105e4feb43b3ca6fc804e8d84384163675d9b34d0bd0788a8181507f51b6f40779a88263212361d0	\\x0000000100010000
16	2	3	\\xd641bee734f8cfb885a40ddea01d69da94884ca52791d9dc9eeb3a80058999e3d79f71982dc4d2c5783e5bb8a7f28a8f7fe186f578016ed4cfae661247326105	400	\\x0000000100000100464ec8bb8e1da014135735b88dd7c0af8952184cc29822cb490ce75fff92d55fe4441f8160f9c5aa8333d4206d7b7abcd5721a7fd6835e31a0e66f6f6d4aac659b121a284f01056069a4e8c91ac37b21cae789540aee72a9f940a4049a3ecfc6232764c60b57fdbe765d54dbf5c2a4e8bad208c2217d68d2a17601fc0da0eb6a	\\x5f4f5082bc47f7c9134cd1bc1ab65b81eff7b12c0d1a60564961aa53b296a28a5ad7782efe74ef3d8b820069d315aa8dcbeacedd3a07e359dd084fb70aec88be	\\x00000001000000014f2e5b38c802fdc1d2f38e5130ea51f303e1800da9deaa563f8298b79dcf9313388131b6eba14e0681c1fb2f76d9454ae870e0fda882592a8ee7162537373131e21f310b1700bff07ef8d925b81046ebc2b229da32076c1a3c575da3cb5d9bef59f2c977e3407de970fa4385750448271f4c26176e693ed14f1684a654c9188e	\\x0000000100010000
17	2	4	\\x41907cd66e17c652daef6b6aca1e25ee391dae94e8f8ed88737958440997a359fea950dcdf34b44e7cabdb0a3bcbffa758c0603ae2008610706c4877fbd8110d	400	\\x0000000100000100707e2186db55c9652967cfc1bf9688bb796c890ee81be0b007ce8d45e935ae970ee9e06aa0059e009fc4bab0332007220143f8160a3098830417eb34ed53f6812664a7a209ac89bb4819467de6e44e6ee63f8a35d5d5c157f04f5e3be97e422cdc76f6c734e9e1dfa70990b3185940bf64ca2e14adba51b73365781de75b3909	\\x17ed3607588e6fdd0ffe307cc4561e92b7d42b831a42b59602d79ce0f5198a80c258025f1f32bb1a2d6cae00dee2b9588bea271d9abd03177d6290a10cf15a08	\\x0000000100000001a0277bd693a75d9eda1fe4ec9758aed40ba59cb5690b517a29579127a95939a5ec067c3ac18299e60ea4afd2a801e502c3abcad35db53f1316b57ae97a207a39b4def87ced1f4d81d531b46dda2e5d5bcd1c931db3a9836605796c5bd752b2e657188e5aa70afca6e8e6886bfb22644fbd5a8a1ab65e7ffa8e970c77536311eb	\\x0000000100010000
18	2	5	\\x5f8c2843110b6e4425c316d0fa1af63bcd4a4de8968846d8d9310e00067fa372d83b0ba3509c660808733384d260e12939deba97de6278d01c90509bcaf44f01	400	\\x00000001000001002b9345dd963753998f6e9074878e60ba5a702f316cd21d172384aace3e3609a684ade295949940be6ff336c0a34ed747eb4880896e7ac5ed74c7e79c080e639c69ec25211ad3868b47da6b1410fd61c41f90464ff9ff73b485757d864b1eed29037b2319032821401be925ae44a4a67a19ccb541ea30e248d4903ac1dc04229f	\\x87b216fca5b4e138f2e1fec22857d38e802364d41c522c6eec3a3f63be1302a611d6d7668ffaf0e6f8e21c990f28b50a57e9e9914791f61877fd1e1b16c0e284	\\x0000000100000001964794d5ac5ce73a69f9530dea70c3e8e3ab170d28937f997d14dc573c4ba582aeff2c5e7bb0efdfb4532b63f8327cee66b3d0fdd8557133505352df08399426d6817b6a3af94a4153dbc12db3447080da4e74c46c7469f0e9ae5ef3f5ac8a8b67b6ad7bcacd8ed3697816b58cd85d0bc5e2d8c00aa31228952b3488258dd83e	\\x0000000100010000
19	2	6	\\x7c335967f6f218a44e2972367f8ed294159af971c0d71edd0b6afedaedb8c7fa5e6e246e317f69b8ffc0a67ea9d83d7a740807a004205873e2f999da0a8be708	400	\\x00000001000001003ff9d9487c4a535909d701d8231d07f336c6d8c9ed8da5e2474cb42aa0682fb3923c366b82f7d03405c0424a4f18fb4a9b2e62b7cc54c33bf846eeb81c7d2a0fe1a674d8c7ee86a14603f448ec6be612523ec4b9827d279902cfa5e6342505897e3040158be773b5f8375ef37df7587d0028ad5e99efd09cc6dbb2e93bc32db5	\\x905cd0337f994fbcfbf6743d7cd0b7b2b9c536ae93ecd77021ff168db7b799d9f5fdfcf715fd233fc87ab1772a49e17d5dca72f8466f1a2b4c1f2bf52b22401d	\\x00000001000000015b99d24b2e9037af15ce641ca4efa623d90a81e64574ad0eb1f4ab72487dedf90b86cdc0b3b929745eef30dc2e68e2af1a04ae247591199212c6a70469b572e791e5fbb039e6555bab6d72f36a25a896a42ae4d09baaacb2c2f09d63f8b512d6690cd5a313ad7be4497e21bc51de2bb77bf70664f425dc14e9d73bfb3029c09f	\\x0000000100010000
20	2	7	\\xd805bf10c3b66e2762e41a799e2aebe271e9d2485744d93bd0bdc2b4dc8133a57cd4d194b55fce85122ce86c17bb7efc66107507d9369083b27753059684aa06	400	\\x0000000100000100fbafa5d4b9417c38372ddc891ed990de78712cbf8ec28c414fa591d84f0ca7035fbe4db44d6c04881fed8b446758fe6b9a6cdc7302c0f87cff2335ac3a621d1f00c5f25cb647c3ef00db29ecaa3640029ca539b27ae43129571a2295112e16e0d90ca23a0e3a5286a08477165adc6cbf66d3ddcca648877d191e152f816c78	\\x83a5bf9693401f6071a04d7b0ae6b6e0b0d6b964bb56823526a62d52b4f4c083e4fb692e98f924605cb28a5ca152cb9eb279628ac7a2f37ba2a38a3169c0885e	\\x00000001000000011f7bc1a589a325b93acbc67f0b8fd447abcb3bdd249729f2729edc595cd2ff8465e22e7f3eede8132ad578eed8da5c68891b9ada465cbfb379d96c6fed3e96adf1596e72b95905f01ae79b888cfc04429db55052ccb23e1a41ac741d0706e6e4e9e7735b3449ff419116682f5f43d3226c6f1676c07f61011255c118056d1b6d	\\x0000000100010000
21	2	8	\\x702c2bb1557cc625bf5e4a9b113be658da7f311e8cdaaf63663bdbc927b4291cbba21050a4fdc4dfae1c7aad1e88e1d8555787c6bec0084c9dbe7a63df04d00f	400	\\x00000001000001000a87b9688f87297ab6f9bf61b604a65ad3624c8e2a2379945fe24c298935c37a857e1ed6e49621761b054e1a1c273ddf27ddaca7c76215a5c2e7a45c46d74cb8c081a3eb2e3462278fb20071fa60424f319051d5cb5ff858e27b9b83ad9ed3c2b945a5475a136be1d025cc85fdd0f316bc279ceb385e925c4cfae713f3d2fd8c	\\xa04cf8997ec4a0ed545d4f71c4d963208a0c51185d17e04d506f5267f433cf0f13a303fe47507ad39be678f0676a84517602d20ebc83f40345a06ccee1aeb1be	\\x0000000100000001a97146fbb3b763d2556218babab98f46688eebc6e81c742e27e681fe7004409ef798971eb622189fc06d9d11f6b3f3812539c4c978b41f2339a5fd89da9c502c05699b82aff67f38d3bdf9a1818be752b9d2ac7344cf282b0a52b80c1742e89dab34219d75a086b72740d3e15ae2f8781d1402d123a389412ae5101ca69128e2	\\x0000000100010000
22	2	9	\\xdb20baacb3cf12f422ef3a4f0265991708f80bc5acdb6d7d4c71bc4854b0915c6cfdece3d5d726e757cba22679384f6577b66d48e3d5bb18953c6bea33bf1d00	114	\\x00000001000001004144441acc603be36f50aa996b861ec8e8274d68a6011a1daa4b925acff678efc3e69ad7b56ada04c583dc678f2c06a1f74c431a1813aad44a50f9eedb5d7ae7ec8ef6a7c7531e2047dbdac8fbbdd19a8e2d8541fe1b11ae9c3ec9464f4f3b8de0c654d5630661aa066c38f4fe794a87d5d100b0a58184d90bebd3af497d551c	\\xfccf80256130696508cc4a8e11e96dc86146d20a24e522ef608f65a16e9b165129e71203a636b780b9e32ca887cca20d4a015cbd127b3c84d4bb86b6d9068c82	\\x00000001000000019926fefd33ed67abd18953f4f939ebf7158c6a90616962ebb1f7b119106a160a088c915c93ec75b6083a009b00e12e09ded3a8a11bb79e45f659945da5f0df5d41b26d8e99e7f85204f08894aef3ab14a18e132626fab144a66c096bc2d129a398f236a98efed61275f40fffb15be1c58528787bcb59f83cfacb2d353dd31e43	\\x0000000100010000
23	2	10	\\x4341d9e1e13c3914b721f8c0d23bcf0635bb04015135130169b13d670a79d280abd1a34d8610b28838b008c100c828cd636bdb51a3c9ae319f2eb5bf9d05a604	114	\\x000000010000010053948261adc58df5655f704a1e0c6186f92fdfc6fbab6cfb06c11de0c51fdd6439f8c0a9f9f78a748f2656682bf76e318b2f633fd5bf06f95071c07d1636abb5269b302c342afb9f5ac390c366a88969e9eba522e3904374ba4b434dcb4db7afa0dd73e7aeadcc8f9925b4b977f541c8851099dee281a548d185d5c218eb6f6b	\\xc4d4e0f35206eb1b3f419351343f56fdf9b8e5871009b86fd9e257af1677261cd0e4ac879b522a166a0bfa31667c5700c6315b9afdb449d2bab1876e14a1c177	\\x00000001000000010f72438e64bfaa9a202de5efa1d214681b311ac3c3b915dc1ef98db093169cd301a334292f041412ec4355198cc0738ed93ded441f1b1d62a424126fc4b0ec10ce8753c617c7086bc3b7a9d3f5931a6e1aeb50b86f62b92d6c3e3058fb3c5e11945e199eb0f8bf9ec63d48dffc01d50d40c1fb917a6201cd565d75004b9ea98b	\\x0000000100010000
24	2	11	\\xaf04c2e5cbf638720638bfbecb4788a2ba14d0237bfdc47f911aa8c53493dec4e7b38752b66c3d4e46e61ce8b91af2077ca2556bb6f8d9046cd8fb8d1dd62a03	114	\\x00000001000001006bb094451c7e6349f786e757610681261d410649649c74e8e346c6216173d53debfd9055bf5bd01107605c1e201fed2a86d67e10078a1aa49a84155da78f6bf38405d58a81fcc92e17412773349187e4a5647b683ef41bc6c5decd78f2754639d86dffb621ba5cfdbd93853331d140809723aedc0809de9c91fb40cc4d757835	\\x458f241609cca8cc707b03907c4d89b51770c76340e3ca134236ee1a5971d25035c9b358d31e6c8a38389c7927fbe888584f9fe3312f8924126d750e6f8000ce	\\x00000001000000018a65c5fab381c1c22189d44e96d0c42c6a0388d66c6b649465bc8a9b341da6e271d4592e3f86980c5ad86fd64f099f08a0f667c0257a3a7497bda0c238f894a4c611b8fd422c45db363a84f0bd786fee2ce4103902428fe46e7cef63ea787ffa2a181046d46b150a77e3c0569cf51dae68a74a408b00babbddb2507659c2ec25	\\x0000000100010000
25	3	0	\\x8fc28aec0e83e59d2665006c3c604cd490a33fd85cf26e815a187c729840c22b96ba2f6c9f771e12d5385316bd382d60f20dd6bdf3494c8bb0f58fa9d0ff0904	83	\\x0000000100000100976ce7a5e3c2bfab10204483f9c2c886742fe3217bf0e7d4143f7bc0987a11128f554465fbe6ccee87cd8f65e2d77cf008e5d68c7c1604a47eb4e96555c71c5d1880f35a479d1aef70fb1428c18d0a45e9f0fdd8e1ed1d633cd1ed6de702eaee092a9a1455b3b9811326e32e44239a2057bc4a6b3715530f641d825d71b139f7	\\x74a2d3179d75209315b69da306d088fa4e971e54c1aa87339ee3312fddde0ae4aaadde8fb96c11ea0734be00b18ee20117f6f92dee86a316a118dd6f018ac561	\\x0000000100000001a4d791bdcece655a9e03069bd2cbef69679ae277096539ff9cdb8377d69ee9752dea30f9155bd62fbc7c562a7ac4932ed3c0fcadaded1c861c827f6292f6ce28ebc6199b132f975cf7bdb24f4dd82d55b0922f9e4ee2e10fe5f97a931554532ecc0ad41023e96c003f16e91a86e13ba44c2f19b8533e3976caf6ab2821d4cbf4	\\x0000000100010000
26	3	1	\\x74c0ca2a73d91fa7ffac63e54adf398d25843a6bc3ddb80637111a462ff747db97b21909fa8acdde926b719ca5e77a942b8d8f43efe77f8bac88766254a1ea0a	400	\\x00000001000001004ba8c924a016d1319ddeb641c396320adc65b41f7a12781812ae8b2582c8bd608ddba619adddf5845b3a6615e98ece730d9dcc158117a61ec73c024a0d3fef6d48fde12b473d82f0a4cf9a21ce22d77a5df3ebf6bd5a0c708fc0524172e6ea9c1da5205a8d9d3db57a29292634dc3e22e799ba60e2570299483813605ad17846	\\x7c8abb69e1c12e455ea0fa70eae767543c02f442598814ad12c28598fe49ece61a228bd6f965ef7df32dd9d4c5873f5cc26fc52688e380d570cac4ea6728574f	\\x0000000100000001592a308b34d46940f9a64f49e925b53c7a6c521e3e17b910b14261f66882e7eba4849af22057fa0db7907ed51489ca5b9b18f62a29157134a67502a9d064e5e1cfda5b5031dfe26d0809d9d76149583f50260c8e461ad070f2e50a6772a920a41fda8cc1b33a77d3da3f8c8c37df3258788b7698044e01cbb6db261b7fd0ea72	\\x0000000100010000
27	3	2	\\x3d234097bdb9a79cdb6536ca10670423984e7881c853ccae90e4f02543e44667887c8c9c1eed230a88ff899b2c8b80c03f7c5cc15daa5778e4413a6d36a69000	400	\\x00000001000001007e69b8a5b09813aca46aeb68bc3f1e315c6e84cfe03c1e3ccca4be7a0cbf9ab2d7f9f2a8d591c3d1cb2141588263a62d35541d8b8193c4aa72304b3843fb09ed5b7136e9050ebe416368097658be89eabf70503f81edd6fb95cd3a61727f9db077b75c148c74d5e13a811c2bec2ffea718eb0162e745daf85c57b8eda0d42581	\\xaebd3661f9b6f8434b2db0681d9a41ad530b1b7c81e93a68cdd45f6aa3469d37b2aff95b0c9a68fc35838d560da3fa3ef42693d5a9e22d6f0b368402fd86aaa2	\\x000000010000000151fa6576fae0d8b8664df84b25b286f60bcbe20251644a528ad0be82ea0594c777e80ed193b7640f857c6919d13c3cfcd4b01a074b31a0c0cc6bdc3730e41c622a0a55961ee2e5785c4dad1e464fd58d2b9639a568ed754a52fcab520b53ad18c23d85eeb87a7c83c9fe5577b40ef67fdabd72bcbb8441055952e85def97df89	\\x0000000100010000
28	3	3	\\x624580d01958a99a61b5d6d6b79873f1efb54251aad7241e1e2469ae7c78d80593a634cd0d2726e0c956df28c4aceb5276ffb084b977228a38727006ccd41709	400	\\x0000000100000100052504c196a6e9fd9593f803a2ebc7ea7fd8e639c05c8501adf09e36d377c0f71a155555807d4c668b1b7b70d092755a95ff02b52bbff9296e3031ae74c979b1cc1af27b17e5bcee0f97688714f7545d1d32fdc59d951da0af74722afad882b640bda3809909d3b11e9ce59a93eaf87eaf896550c9928efb7414e80d1af39485	\\xa48131601f198c472c701a5b3d9f33d514dbfd4661f1c295e84013dad8df274192ec4d6704bd1bdccfb35180725a6e2dbdf296b0de1d24b12f141d5815e88017	\\x000000010000000128fd50f8108225b4514b8859c9ec9f11e9157cc20e792f6e3e9ce292012fa37054c536a369a55b655e86cfb4d7591fbbbfb1a93c2b72e7683125f904be924a571210a5a2c3dfc25fcc17b1353b2bcdb1a088d0cabc4942d5baf8a46fee3a04f13c2a163e6caad6f5159f86db04dc4e7526822cf33290a436430848a6782adac2	\\x0000000100010000
29	3	4	\\x5ecc815d23c965497e9f06708a3e715d7570d4321b84f6d7957cf6c3ad4e9d773dd12a495a9ff45a184b61e055fcb3314704a176cecd278093f4ac2896f7e009	400	\\x000000010000010048cc291ae04a4388acc3bed23518a87064b0265a91c4a321ba243f5e18f7d198520cd7b35f88525a6515b4dcb0adde3b83200c38ed683867e94e2915e9de089d5fdabafd577e73aa14982db34e0487263ea000ffb561d118f05a5a5d7e2b8a364b8008add99e13ae6f8368d02cbe037af040fe04889ccc358cf8bd88626472cf	\\xdfed1af68a53a6e606281707cb1bd3a104bf6430eee4279d97177b914bc0907f6c1874c88a30c94c7c74b5a8b628720098a23f45475f9f7baa10aa2f0d21f329	\\x000000010000000103eba786f121512a41d31dfb66a8c64f1ad15854ba2c9f68ec8ec1ddd584f0e8df312fb85641996e9ec6ed84ca131c69d72968d41681eeb9cbd0c1fab87a714c3c6f334da6f1e4c5634cebceefc2898235a1aabffb77f374077ce3461e835ac1419a084f15b5ca51bc2e5f67bfdb3d358a9fa5cfeb370e3a24a1415ae520dbf6	\\x0000000100010000
30	3	5	\\xb1328c8ec039647473af5b2dddf41cabfdd73cfc97fd27c7102870e69b02c155a85be560b94efde76ca5840fa5b01be6392385219b31f5bc5f1a4bf6b1c7820c	400	\\x00000001000001001ff2368798c07d95989953b28f3ab1621d9777f5ffa366c827908ac05d1cd8ee99e616341c5496f869a8f9a2636ad68335f79a579cf626deb804e5f1e8060a3e551578b2604150280556182542faad62dfc3ae31c8c4ca730748b5be85cad26bd52c38ac1647034e097f28fe1fbab831a1b41ecbbe76b89ad67e153805b774f3	\\xd7b0b7f66b8ac2a02db77a5a9b30c2203d9d99f938a3f30d90e2c4cd370a805412c2dede62543dfc28dc0488ac24b002e182165838262bac32251203f8418595	\\x0000000100000001a0ce67907f209a518a072975a82fa7e714ba709cc606a0a06a85ee71bfd7ac1ae14e5f386160787e73ba010d91816546a6624e7000995dc6fd323bea12511df3ed4ed7d98a1a5c9f69fa65eed28e57064107f786ab104628347a47e30cd93e1a743ca53526bb12c8bfb48d36748e506f03dc2268fa8fee070cfa541877db6556	\\x0000000100010000
31	3	6	\\xd0c7f3d1015c454064a0f408973098389e733625900fc0fc2cf6ab76d6f6bb9afe706c98d274d5a60147b4fd97cf4406c30cf74f45e114b2bb3213ce3bc1b70f	400	\\x00000001000001002b1f91bb1f68b932f57e7400804a49db5bfcd90d9e30774c7b783e2a9c6f3563db22d0c47d8ed9677f4f145c2ff05a58a21409af290409f2fbec89ee950acbfa3d28c5030661bf1f5107864e7891e4daa489d89a86aac34b6dff6d3033911e7405423768f774d2ccd7ad51c77e3df9207035fe2cb56df9bbd73f0faeddb92a61	\\x838d89b7f563a6a4d918e56c0e9b5fea5e6cea62cb1428a7ede33c729ba387f899bca917e67cbacad2d912dea271065ac6a4098103947dd688e29e72fba28673	\\x0000000100000001040ecd2cfd8a5b781e37277d9305076aeed644e0fdb789e6ce7f7886fe6f9bc4ed9b6a5bec9d5b51c4852ff1609344832069d0ef29120dfcab853a20e2a68ba5b316a7d78c4ea9f6995b6f3e5bfed9d89906ba79a736176af436161bfce382e53cb9e3230e5538d68dca33b39e9d6303249e8111e5a8d5dd7575427085351eed	\\x0000000100010000
32	3	7	\\x806b1ab7e2e15a75d6c376eaee6f6263ea280cf1c64e3351bd559ad6befaaafe0f89b8532bfc103be3b67d8bddaaf5364296f6c369cdbff23f3da570bd016d0e	400	\\x00000001000001003d2ceff29a6aa48253ef8ab0615591a27779a86ba9c56d828dd0375d89ed0c3b9d64b19fb9881d2bdc890394b5a6c8ff28fc06454e8e7d4695ad4f856ff203076b72ae9e44eb3638e182ffa430bc645c6548916661d663b2562bdcaf11ad3771d795cf5181cde6fbdeef08af9f9dd7f63b651d15d811ab1998fe208bf54e5802	\\xd7c4a5f2702b8b96b505a749e659c842c2fe542a39a8036553cc740580045cbf72f09845be4058ef7960cadab9f29fdb899be626838aec534f4dcfad22089eb6	\\x000000010000000183d73bcc0fcee9965484beb4dd5521168f9a27cc30dd854397b9bc2ecac275a4f5a9217ead9fc882bb436e0a3b66651d7ee2de1897ed52c00ae5e66594996193ca03371de02054fc284a7592748f65088bbdd90a0b24fec0df523bc91f7e41e81e57670e3f434cd15a0f8383072e10df8201555f5a02ab70c8ce1f05834b3fe0	\\x0000000100010000
33	3	8	\\x0f863446dd090fcb0b09f8cf06752982a0983e6d144b6f2734bd35bcf7f5a6b2d618ad80b5ea982fa1a9a02cc0f6795d24cdc15a1686fe8ae50d20ecc7a99409	400	\\x00000001000001008cb64533d5094c8e169771248bd09cf063f1f9ac7822ba412f834ee5df59132fc9028a8437424d18e54e9b9fb53098c8f04838ed4b5a1cdbbb7f372c563e03af1907134843214fe58befd5dc66f9d222909f48ba10c75ca4495ee9103e73398bb9397a32956ee2b4984e5422669699ffa4204072045eddef7f932aecd5f08261	\\xb66212e0208d1be290c7da63f5128c15eb2c69621bc078d1c15b801e9b82a9a06fb0c3316ceae94b934eda3fc212dc47c705f1a6926d02157db18b8002fdbb4a	\\x000000010000000141f732f55fcd4bdb2545efb3029e146625a4da4be4e3f0706a8a5ab8e5456c694b110c903344b87fa72f910ff5045d52f752e43ae50ac1b8f9ecc1ebf5e2654d6463eba0bfa52817ae484d5fb7fbba8a07361e5c111ad7d9b2ef050c7a158ea220eed6ca901bf8969dc43c858ba0956ff3cac3659f456d6514a4f3a597ecae98	\\x0000000100010000
34	3	9	\\xc124e6535c1267f54c6ece2ec380fc085b1a533128dd48aa189862e2db65a5ce6afa7d5a842a4dc219e443e395f634ade6a0ee8966c2942a0ad615bf696f6807	114	\\x000000010000010083454421e94c6a26ecf0cd135351ed9c592674982edcd4ec55765838c799b3382c903832c07073bab1c39bf111d31fc646fceca371a83df02f8d43c2e6b1c6c1acc60e17c2637e11ef38f111611ee083c8952b66c6836efbec57842d0a26f98b6f0b806f4b2497071c7d809f2790fe0094b0efcda8564392d1a7ba9ca3891d8c	\\x0e81a00c100f3ad5d3b125f2a28d63dbe29f61e606a8786ba29de4b2983810e80525a63a72b410e04c1dded52edb0eab162355375d840d53ef4be3045db1842a	\\x000000010000000151d767a2d409e1687e027f71afa7346bcec348ce058a91afc8ca5fa72c48a881aeed431c009d8faee6720e7119d23189f28014e32175a022f51628703a5400dfb5d11b03933f89689b893aea6aeaa23ac36256bbd453ed24cbbb82e199e6913c84489ce45089ebdb67f1e65b46ef6674a5de0d0e2ada3bfb93115388d3397163	\\x0000000100010000
35	3	10	\\xc67ed7e0def5826bc9cc02b148ce5ced9a90d9924b79f3168ba5a3b3736792784ca92b87d04857268a9a16612289f1641d62ed9f40b0d863fe99eacd69f4220f	114	\\x00000001000001001c0859656be62c8a296fc5ad6b4b3bac9754ca992b13fd78ed3694a971e52ea358420af87025b2ad172a15e561922b137ae1c8b5483379dcb1de1e799c537d4391a858928f7281e7049ce90d96842045385bc8b351109ea68cb1c5deb6a3445db159e9023ee534aa665a9130811e5a2f74343c414abff6ef17be966cd317cbbc	\\x2c48afd294486e6072fb829d28fb545aed4598795a7521b852fc4bb1382ccbf99f381b830a73184f019217b4f6c585b9a5385914a34c38664659891ad1f18c8b	\\x000000010000000135054f71808d02439f96d77992e7f4224b135ea25c9ad1e969d24d2c977ad88dc43b3cf3845988d9d38a818c948bf52f507c63df206c4b16cce0baec93acc3144728820f4624e76bdfa926cd3eea499672eafd10705dc002d992758dc4de5d8c7b1af40c8b69c60e864dd23340e567983c54dd51c51d2991e18175446476d08b	\\x0000000100010000
36	3	11	\\xdad3de5da664e9ec9e0559c6840c03cf9dc8527f530013c711e3465e6eb4fd056fa161e36888a548e135a6f65294215ebda36ef877307bea112bef8760f91502	114	\\x000000010000010070659f1ff14a7eaeefb2bdb1045864575ef9d15ed455ea691b20c90e79fe4c99c111798f1ffefb0621c025a34f1172d360edd439685593fed913cc8655ea052a38ffa28c19937e67d937ab5763800dbd308d011ae66eb3943e1f11baa1ee54127ac470201dceb0322de4662672013230684b54c7035e987186129fae4d6a35d1	\\x64aa271de215ae1576a948a76871e0cc6c9240b0f1ad08785b25a98ca58ece5fc112d7c31322786395c9b323dd86cd882e8a345802660c0c4059b23059d18d74	\\x000000010000000117563539de5ef2a51e3d1dd853b0d4e72c036d39ec4596f62309428695354341840ad9738bd2f40e7989fc7194aaab606315e41caad91c32b26ecd915d03ec26fe9ee7d0b2476a0728e29a442b070f52daa82a910b5869ff9e5da987e5563f7e244736cc263b1f3807d3a9ed879064f344f428a1986278b504816b2aca9a82aa	\\x0000000100010000
37	4	0	\\xeb5c565ab9a203ff14c3d326cff5a6984a7b40454af467be0022a4ab03a9dd9031baab9912d1c6270e016c10e6c517c1296540ed01df5337b4a8fb3067c6e40a	415	\\x0000000100000100198b7073eb5f78176de175558f1a95780033e3e46ad27a1155c9ddb5169c65d80891ca263ce5cc2f6f78a4cdd34cef2e33f86320f356a18a3ebef8a97effaae1a8bf434e32df2b5b02fa8f50aa0e174869cb9ba6d0c2ee2369d9f6a34eb779293b22837ea55b3075b5a9c1cb8e0d58147041836325e79b20db66290db39c9878	\\xcfeb98f103b6e23ad489ed91b3d765e0817d41e23ffefb496afce017a2dc723c0d6033574f0ada672b6e31eb5de69ba1d7c1c2217934754fb67bb948584491b9	\\x0000000100000001b5a024a7505b6d22b8e02224ec6537a2a190a0912606c2867844e8744a636ad74504bb0e33492fba9408dcda2e1c2088e58f0e848fe813e0ef9673b360c7e1a3656c1521d1016914853df0d1aa3b76e26361caa8f882ccb80170fa8148a3a679507db9d8395d72226cd09d1565d711c53d2185d5ec08862019b93070ac9095d6	\\x0000000100010000
38	4	1	\\xa50eef6a7c24c69e96b1ebb2065c0e89bfe268486a0a8f4cabd2a7b14e615464e52ae258d93c274c848e0a655e6754c67ca0d73e54fbd7939045209533875b0a	400	\\x000000010000010024c7741f74e0a26e731a4eeeadeba3e1c98e02a49d744a2c53c47ef8d84288a34d5b34f504c393858bb8d4f0336a1a7625c4e01b52de31afeb09b7443eaf813f8366ca276d7edc9a78b0a4d4603878316e50e69ede0d6bb831b97ca8ba4ad705209972f3368aa60bd3c13328f57aac86b82e756878b280981b9e1f5d7c4fb492	\\x33752b0db2b8eade1bb6c45f68eedffeba06411e28327c5f184b21b4de1194742b9d957739ba68f3cff28b256f5c8c0e73277ca70f6fa241f2e0e9f56773bc43	\\x0000000100000001317f412ba1040d196cfdd45c92ab0cc90d1ccf378efe55631e555203db24eed99b52e2fbcb9e7624d0495bb55eea0ffeb7756f2c145fffd0f29c61197d3e0b10c021ef322956d3c5ad3d16e6f49a1cce773f38099a79d8e1de757be25937d74b064d9dc76c6d145262ab1d341b1eecbba64d192f631fb17cf5394298c90ed3a1	\\x0000000100010000
39	4	2	\\x849ccd31c44b60dab8207eb441bd2d85b0dcb0a63b1c6e0dd7c327af4dafadda39a17b61b840b9d3b238f17ce19e08e2c7c4c8643663e73483e3308035bb1b01	400	\\x00000001000001003ac83f86d2e654f894d324407334a8c7a36351e36b3562b6abe4963487a6cf12e31e5bceffcce865f403f6ac1f4d724ed12428570035fd1419244d8869d42e664aa89df25864b4cc2b08c4347bf18edcb357af11fca5078850e0c470f2239a54badebca331fd2919d9d600d749ac1a8041f61b0ab566f921dcd244f459e6051d	\\x44e7c02e1c6c5abde1293bd994cf9fb083665ef0ee9d0a6b5b46ff00cfdb98503bf6d40d6c2f9e12114c21809c255b7b5bebcad5346b855b505d76531253c508	\\x00000001000000015f0be8336f148ac659c9c2e11712f4ada12ea1b0293312dd7dcca57ec802ebfe18bb548b6dad4d4c6af60276eed99857ba7a2541717ca3cd47609bea623aee794ab070b7c5d95d86fd925987e20842bc2a93d0912206c15bdd7dd1944b5c21eaff8a7eafbb09fa8328e119624b4a45191234fb6ceeb9a0cbd70f737bb3554ee9	\\x0000000100010000
40	4	3	\\xa21fcd47859f087ad939458351ef2ecbef04b9edb8a7cb6a3986d5f84276cf8fb257eb9d94ff9a4b1dd59a76974569421def6fa3f6ceeac22762225c66be2d0b	400	\\x000000010000010012839de8dd74228fe87dacbf6082722a92306d89b129e4edff868c50459fbbd8e8620fdd213da6dda8c51b0ae58164359387d2dd739fc977d3fb7cb6d308ee5b55bf724db0aa74173e05d524980d94824a4f6ec3309a8917736bfdb566ba57dcf707e20a07bc475cdde9bde4f883af731985332c1c11133178df81a99d829443	\\x198d96f313fd5d9baffa825091f673c2ffed96b235462d9e9f8b1b97e3c49eb071ad16ddfed999f1983a48475435d0c01842aeb9d57c6d6fcc7a5e908cab2665	\\x000000010000000113f05be4a31f054b5e17b676fa8adfff20a0ff6ad8026d30e4bcd8c9fe80b90d203f29ab69a566cbeace73936e522d64d812a14789e511210b0f2817512690ad4daa68050533f3948578f460dad43de9d8aa077f71f67654f31b9b7a591fb3ba49c55b6421335c6591ca48baf13cc7d2d1d88675836c1e9d083fc7e3dff77aaf	\\x0000000100010000
41	4	4	\\xe5e21275f12badc55fc83483a0cceea4c5c0b9633b8272fc10c03b5da75c65014f49e4beb842d57df8c8d692a1d45a9223b51e4c1c69c0ccc4caaee85d729801	400	\\x000000010000010015b92b9fd38f15998ecdb98e70127cadb9e2160c25429a0aec9faa26053cdb34284079ec0ff22b4a5c51201932c0b6dd57ebcb5b6665135f80fe9c5ed1bcea7dfbb1eec6b1cd44a4f04f79530ff34592855e90b51cad46b2d835130f2d9dfe31a78dbe23312c734168f4eb99fb8eb20da90623c76b622c07525106ae1e1c08d3	\\xee51120bb93134e094f4cda9c0627f7c3e6b2948813dca0ea9c98569f0137a885695f1c84c78f9922e8008ab20f77d71973c68d981494ab10be38e8357aa0747	\\x00000001000000015a36c3b374a1565738eccc939423a8a91d2a202454e4895a736932e5a745bf5451c91fe60a87304078072c883b9053543abc972fb644dd617612e71935422ef8c159d493c5de2d11b7db1cdc85d806e245a352b42f4f0b214d5d7475235c78e1f7fd953004028afcf7d944a8114e2e800f274a3e493301dbc81b64c98bb427a8	\\x0000000100010000
42	4	5	\\x8fd0e8704e15cf35fd1bca53e69f8f709fe1332db68ea5acf6df25a9d375466a4a397bcdd2e999a37bc99ff9c59bda8205dbc632d60360a6889f82878994a802	400	\\x000000010000010076c7dd17581a42e1c59c13f0667ea6ceccbd0cdd8be4ebe16557ef256c9e83d72d38b34796bc839d6876509f5a814a714e7939289c88d504f972ba434547695bab01ee69695d09fcde8eb06680365cb37150cc9baedbb79d505bdec3a158c58a6c192fc4f856794a1c9ee7b879e34d91f5fff6512bee8f8e36fbd56c583689d9	\\x327738c863523f4eda9dbfc0edabdd73896df1ce54d9216c2cf0081b293dbfaa0e36883b04873aac25fa3d5c336b19b18849db192598398c6a06e4dd051e5cf9	\\x000000010000000158a11e0442f0e74654d60815017c61853d184e11c31cdee4132220656368d08d39601375b39687a4ac1e9a9cd75a5eb11bf963a6d65888554ecc7c6019841a8796cac4e657b7c9b03bc7d7df310ddbf9f2d427eccf717d7372d9e1495108374c258104ad95c5d520e193dbf7db59f709c9036f28a6b8a96abb7977a1064177d4	\\x0000000100010000
43	4	6	\\x6b236885d848e1f6516b81a21ae3584f1894d1dcb414a81956710f7e24f28663071bd9718ef53dc6a77b423e88e6a4a8fd842f989a74cdb04ccbbfc4d0694808	400	\\x0000000100000100a0598a9f16e328ebb7a9c5ced7666bfc6f69528186ab597575795abfac71aa35fd19f53b71317fbf690d402fbf29d7f33847622290adde1eeaa2fd07d7a02968b499727c5eb2b28662c26e054dd87b7bd3e97e53f4469f84dc71d10a5ba060cd31e4e18d79b0e4682d565dfaaba10d565c6e07dde88d647868aebae667dbe4c5	\\x5981ccaee991775f009d428d6cbc769e631f79ca4f2532ce26ef438310acd4ea35084f41e7dae6c62a639e7ce435428ff5053fde1f394ba12c9c7c424426934b	\\x00000001000000011a9cb11d360338c1763de98001c489f964070086f6dfcdfcd8ca996b8c2acc87ded5210ba6a7db1c448feea870c7f6b647f09ab96a4e70074bf33dfe168b485411ee196d523b660c42e98a8f425facd5d118817221a159a418ccbcaab509d86d7d3ff930cf85dfbdc20da0a2adea9d0a16783458e20f0c86c692a93c936a940e	\\x0000000100010000
44	4	7	\\x3ba7efd0c026e62b1a3583bb2dbdb1b0b3d1ccb7df82232d7f5b7750e658e0bca469f4f04cbfcbbca919639df0dd909778a8b19c1cd71546e0cc11c5cc6a2101	400	\\x00000001000001008648df7bc834516dc002457db6c26c1bc41fb5ab1dbb5f4dfdd4e8f351937bb8d93d3d54cc74b6fbc3026137458a25b613b3f460d022f5376d4baec1c6113c10ba3e5858c94b18566ded1a757e4545d3c9677cb4a31a1b4bb8970505020bdc052b1dc9f0c29d14036fafd6df26df6d39e99df09ddd5765b10ac01a03fb90bb11	\\x4d021bbd4fd0147a5572ff59e864078aaca84cf9f7da3bdc7548e8f5ee0509058d49161d2ccf70d231bc5bdaaf965c09f52a7f39f21a17a3f24eaf8f8dc80355	\\x000000010000000195db267b757ce6d04b5804f64bb18579f41b57585148c82aca03381571f7a5765f802069a84de0f0130a7e3e6b4f073a0bef0adddad16d0749a70ee48dbc2ea1574ef0c8472c177771d6d9eed760172024b4f387eab4aa0b67cc31a0032d189cd3eca61651b9d26d02fbf2b5cbef34d2f5dc232246bce7422c588237b1e45c0d	\\x0000000100010000
45	4	8	\\x9f0aed272903d58c0504eed0b6c55263f0efb128aaf31e66a778b5d4e2b675a0cec71dd67dcb3bfb3783d66ef0d9f87abfa65aacbd497dbc462b087c6d734d04	400	\\x000000010000010072f798832473eb8331bf3550486ea6a26c3d0c3a01f14a1fbd3deec9b69eedd4bcdfe763842452d2be950de8f5e330be19fccc6483b2d2940b1519046da058802c5f77675493e5ee8cc4a7f2868ea61852d45073f535ce3dca48a2ee9b93dde467b22af013e17d646aa86177baf939039607bc101224fbe3976560adaa5bd114	\\x3384f598c914f32e1c61059d7ee572608e78dec850334053088799ea0304a571f31c9a6ed943d6c1e05c1908aa3aaf7012acc861b2825db503e8a39075fa02ae	\\x00000001000000019746ab44e919cd9a2bb6f9d7a352ff8a7ab3294a612d2c481ad0868f8c9ae0267b70741585e400364beea0fce94456d68d76e843f649c5a7c30a62aadbef57660ad7962baf862377e40db63c3e9d59091eed93d66b3694c58223e685315c38c3534cb8f6fff89ddb13b26e95d461b7608b1ec4744090813e2fc4cdc1d95627ae	\\x0000000100010000
46	4	9	\\x966e1b5f82889e633a84748180e6d6ec75435741e921f6e9427fd65c83041f4f937687aef87b06c6ecdf32ecb90458b72ebf8094432445622f9546ab904b3f05	114	\\x0000000100000100427ca77dd0ed1b09076f9acf60e64a4d5b1a70c16d059cf0dbcc68bb4372ca803b8db65c4e8a4082a2dd7ce854d25fbdad673010204806c2d63c8e1ebf5df6179d1d83fa7fd4b17b5ac62de9e9acb7ca94d2b275766145748bf7fa1b031aca0c56acfd8e29d7de136aaae75ccddd523d165f9cea7d73ff65cdf332ddf87144ae	\\x42ded29ff108f8f4f0fe3a0458d996f1059864a1f02e5c6cfe0bdfd4ccff34fd169bf2228551a3f9909a436b404e2262155b6cbd05a461fc6d323557fdcec03d	\\x000000010000000103465478316fb87d68104e4e2b1e985c5d3a738e5fcbee08c4a64fc9ed1420a51822fc19e3f5ab81db26c0fb48f9712cae1f378b86f7a4d307f9902b9218313c35eb3150a6ab276e2a0c1d9acdc71f7272118abdf581b3c83294618eb2c85a047fbc61c3333027f7e53d371f9e4774141742472979f6011a0103eeb1a7f66d5b	\\x0000000100010000
47	4	10	\\xace3286ab79b973da04252bc2b83f0c95258013cd3536974be898c364d17b3d2d08e93e5469fc4a682c2e4de82345c18e78a54d19c90e7538bf9f547f9c76904	114	\\x0000000100000100aed9c4076af6cba59eebbd80d2cb4d0a7d62d10c1f65bd6d5be22db25113a874d664ff01a5c3a5b5818f628a6a94c5f5ead84e70ae96567ba9b4b08ccbd97263b440ac92e86eab2150cd310a78f17bc061bf97383281910254918f53169278c7bcf6567074bd0d77d95c00e701bb84b59a71683eeba175026221367588559bbc	\\x8fbb81c9fafdde99b03bf106ab1b34bac2080dea69713054c3af63f7c59b28ece429886bccaf53bfd5b2108a032fc01b98391a2bd1a260ff104d82959543d17c	\\x00000001000000015e7151f0f0172d18f5672a3547d228c98e6561687358993304780ad809e8d76cadd82d7c7a06890e136e2a2999634d9ed903b49a3df9f9fc65a0dac8b8631a5003b53baeb235d6eba8d176f579dcf712447a58ce88bc2984c8185dae8e0dc69bde51a96b6e1961fca636512b2078e0e7e788d35e3a407826e1e542954b9f1c16	\\x0000000100010000
48	4	11	\\x23f3210dbb1a5b1af412f7fb1c5bbb199d3af6d0122f004f41fe2cdeaed234e4d5953a1c0f10d5913d1eed2ba819cff3b71208edd992c2a3d7dab7cd02147106	114	\\x00000001000001001fa25673cf6685ff4fdcab564d6cc7a9285f9bfda7a44793e5a4c69ba3bc3c15a75d4c8f06bdf639105d4cd27b41e52b12e38dbeae82d1f400bf42ce7cbc833f5baac51d2c3dea585b58a6eb5d58904c4fdac4eca029a092a6e442f984900a58f3e081149138c0803ef66266677478f0637717f5e2866babbba6af0667f3c806	\\x215d487309a8873a894b5c5595b309f9ddf767934cc4a3107c5ee84a8c72291115f0933a12ad52e287346e974a471f7c11517cfd3751161176534d0eb513e5db	\\x000000010000000184e39feaf4474247e7dd40291074e40eedc51f77974628147c5b28bd9bc077561ce9f1927237f9a73e473fcf102641be4652eb017cfba9a9a8bdf615097a7339380a45e01b6dadf96faa59b4e0045b19e57f383264ea78c1240726f5315ab9eed03e20c8fda78c5e194d7addbcce2b5b860da3da9f200530dce1baf318ae8de2	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xeb72c829d0985d767fa0b787655c427f11218f51872c149e29afcd78fa9c4358	\\xfe8938d40eb6cc2ec7dc6603502040448e95457f155bd833cddaf11e3bf25bbd5309ebfbe81940675dc1a0494e460563b701c47853ab75dee4fa55359906cae7
2	2	\\x7372b33a0e7583299627b8277dfee8d9bf9be80f1690080e0f47d982d04f9632	\\x1d55879f4111366f21859b3c3c379d3fb4dfe30f6b16f33ddc0d722be1b838e241e28ee768200fd47cb2ca9ee6f14be073dae7d8843825218705234deef32e9d
3	3	\\x3f80dfcffbe3dc78cfa4fbd33c6509b47530754ae4bd1d848bacf8ac86878303	\\x62469e7bb2a2a820cd4bf2ff6a29c5a33b0a929c8f7edc59aaa4fbade90ab5e983c6fc899e3062982f860dc704f89b10fe3a98a75fda1c0865bf813392684065
4	4	\\x73cedb3dfec3fbfac4ccc8dec80f835e7e994fb12a33f3bd805be4e625a6ef49	\\x87866509366bc868a78dd4bf7856f8291007f5b55e57650bd233cacbbc9445852b668da28516c9d6a5ce4053d0f6b3d02b507c639670ad54c051e0597ced0cc9
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	2	\\x5b709efdacd53b40acbcc72a3616cd7a7440368b175bb3a2e4bdf0ef90b9536fe333f8e26cf99458d179cda8beab5f096e2b905c9d17e945b92df07046015100	1	6	0
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
1	\\xae8354fc9ed8c0acb54bc261427f21597e78559f828297e393b214e0dfd7efc8	0	1000000	1649906501000000	1868239304000000
2	\\x25b7089cadb7952bed7f60af80c6c48a0f4dbf90293c2d834d1eb8dc5896c24c	0	1000000	1649906509000000	1868239311000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xae8354fc9ed8c0acb54bc261427f21597e78559f828297e393b214e0dfd7efc8	2	10	0	\\xc1123d3a27ec6169ee856a6065cf8c133828b4cd8164ea53236dbf116ae69faf	exchange-account-1	1647487301000000
2	\\x25b7089cadb7952bed7f60af80c6c48a0f4dbf90293c2d834d1eb8dc5896c24c	4	18	0	\\x7a8a2d5f3c627474f1ae90a9ed2df69d3788faeddf8d614bc6a9039c1a1c97a8	exchange-account-1	1647487309000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x22ea9dcb9d89fe2d578b0f8bbf32ea91aadbe867e3fbc73da1035f7e7876b5ebe4825e586f7393771f80324be4d51fe02a616b7d91dc179eb7f82a966c44a82e
1	\\xa8c0f0cf8ff8072d6365b040a85f241bf2934b7e8c8766eea0592606bb07a68148db46ff4daabb28b1b1c456c48819feb57fbfb5c2db29188f6bec26dfe4da15
1	\\x4bc9b96f40cf92af00094732713ff822b61dba0240b397ff4ee7e1a4c781f840b80fcd0a24918ffcc8cbd468e7600c38e235aa4830a501187a24615ec2271311
1	\\x86353765cce191143157f331bf5063c62b18ca561186284013f33183beee1c10bc3f5a4dded1f5b0f038edb4dd625730ed973f0a14a18012d0d935e525347491
1	\\x141706dd50bf573f59d689d254585aa14e6c35b6f12a23b24117c9a923742f4749a59c590cc6915697e93ab60dca1eb6bd0e1b0eede085d02adae8e0c5bea7ab
1	\\x8e767bd3817179f38ad16e323a1b8392786879a689245491251f28118fa571196f088b396316ce84e9b27118707b65266f265872d002fc276ce660539fe71ef2
1	\\xc93c26bc0930e6c933fcf85b83a0f65cbfab17e75cf8fc40532c33393fdd971ea496b89ef7ac230378cd0ed1c91278609258665b22cec7d54164e724ea37c6b0
1	\\xc127ad4c9c0f52a661dc32779c82dad45e14f71521ee84397b773b607aa5094308fea5a411e72c1550ec5eb4dfa74b0339f0220fa8f3a47718238ff6508932e2
1	\\x76ddefc9fe44618d3d8e5639bd3e672a095ab5df9a0a7601185f1073454105b34c77758858a7c398c9ec4db02ae7294c5abd734458a41e2c777398e2f1e2531d
1	\\xea88cd12017c65208f569c642804015017ad6885b41d2aed00ae8a7322cbe2445fd13a754b5f4c3d43288a46f91465571ffa7b7c58c95dfa877502ce4d3de9e0
1	\\xd4a1ec7a21e4578e7dc6195c73e911960a7e8f7d6d8d50d4829b2824995b76cb384ea88f875440111c41632b0ef2d7e6896517cd2f7441973f42d64fc0ca9971
1	\\xe3328b76247b7fca81231da1329ffa9a24feeae484543d367dc9f242b142e6857a5e6689067aef6b88cb525539d5079484e8ca0dc12e3236864126c6c6fda539
2	\\xefcc94e5fbcccd58cd8101f383afbb97577f4dcd4d189774bc0d404ddacb272362dcc48840c7d724195336a0df492510fbbc8b32d932132a8de7f0a8657a8bc7
2	\\xf19913cdd15d3829822cda6af48e794ad28abd6c549ab6df9e764af35b94980e778eba020bf6fb48ea4be31ec6aaab2de64769d34d625ea0a1d7de94818bc7dd
2	\\xbd54563ee94a55dffd3e2c2b52568e3e290d0dcc111449c3fb3dfa4106979254adacc2fed19efd1fec6e418ae7be05efbecfe1ced827f2bd34d8f3101376a23b
2	\\x1d63b9987bc0c9b06bdeab0b311427ecb717878275c585b95bd9d496862dfc425d4ed64c855c0651cc3386a0417ddc7330e63fa4989eefeb7fad9c1b0da15f9c
2	\\x1bca083d511ee038abb9be5d8054938f2261d639e7d04c6e5eaeb771a64b26607a33583e9a4a98425d213e3dbc243503fa6f918587c7fcc6a92b4d8d98b7ab82
2	\\xa64bc2d5ce5bc391ec8d27ab224d0ed299eccc2794b2eaad4687b34064968a1c7d19727e50f76278d1493a2ea6ef7e2ab0e087dc8f2a08437062d10ad65d66ad
2	\\x76ee8bbbb5f6c66308eb7574c556fc4cea0a47dd4ff6f3c9da4f1f1573450e50a7f8fa1eca90c9060e0db1151bdcb546bdd695d3059e3d0e4404ab301a51f097
2	\\x8b2c91ce127377bff97d655d35dff72e6091bfedd1b14afc7b455fad4b5df38bb0e23231bf9990629c8770f666b17520e8f6924448e15f1d6b5951a4a6d854f6
2	\\x7f609cf9114f3b41335983880dc266719ebf713becdce7d39dba5d726c43bbaf45d923207235d361f9ae0a835e287cfbdfa355243ef6080cd35ba2c4ab5d2c47
2	\\xd7909ef606b0dcb4bc490d27555ce211f9ae0ceb9387816099e76b73b5e90c050ab7dd54e4cf6aa54f18274110fe15215fe32197fa68c37831426d308e4102ec
2	\\xd8fc1e1d1dc30250ec041510a42143e00c1e6c5af3b3db4091fd041daeabceb43592bb2e3cf9af0050ea3341949afd0a40199c4041ac3ffe0156044865ba6d22
2	\\x2eb48bec4d4b1cb95b1bbcc10bc120a65934ca3acb353db3f1b4c1a44446d2f9b06613288c1e1074da0b02b0d66378830140bb7aba6ac891a31bd3e840bf0619
2	\\xd126a5ebab42e9dadd495882a16797ca31a4d8d725a7ac2b475ba519166a5633155d724eac975a60b56b0800542ad6ca17d8a18122efd628b7b104047b2b2116
2	\\x4b8a8c86646bf20eb28f42be4b8777d9c5ad2f7f5233decb380ce97ddbfb44fe284115c2c0de7e0de4d7aebdb0c7c090c323d73d562ade851b9be70d22847c82
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x22ea9dcb9d89fe2d578b0f8bbf32ea91aadbe867e3fbc73da1035f7e7876b5ebe4825e586f7393771f80324be4d51fe02a616b7d91dc179eb7f82a966c44a82e	384	\\x000000010000000196f9de5deacccc1e1cd8467ce2cdfa5aa1ee80d1e002d44c71d639fd5374bb523ff29e6514e4aec44a03ca835f2f31ff545ae9266c92704dee3e7f5df775f2504e4c0febad27860f2ee519f6d6013dc1531ed4bec6fd01c2fcba3e729004881ede8e4adee3cbf4633ec990d21dd78c8e5b776d7806e5798398dc4504fd5d5240	1	\\x319bbbc479a6ccb24014b9b80b8d24f111382f6a9559a047fcb65fecd7c2a7f2349ebe183ca7031f86f2ff4bdc24ce815e56654521d086782fef5d04d2356209	1647487304000000	8	5000000
2	\\xa8c0f0cf8ff8072d6365b040a85f241bf2934b7e8c8766eea0592606bb07a68148db46ff4daabb28b1b1c456c48819feb57fbfb5c2db29188f6bec26dfe4da15	415	\\x000000010000000131e07dd4aad71031cbf79876c298cbd646ab5f9e9863793bec3aa97643f728c907aa416a40f445edcd3c97605d59d969df755c43aeb2ab52298dc1d13a86b21940b02617d5595e0628a167c7e7cca4489ec599fa954aa9b09098ae857e1eb7d0c5683c83631234d0828dbfde219e59347635c5eff8cf6a7bfca5d95ff5b8e725	1	\\x3097727078dc8f204599c327e46658ee012673ccf92edfc64a36d037276496b3dd96edc448ba3285b4a9bc33d901b3304d89f9cb8b8602099362054894c09a0e	1647487304000000	1	2000000
3	\\x4bc9b96f40cf92af00094732713ff822b61dba0240b397ff4ee7e1a4c781f840b80fcd0a24918ffcc8cbd468e7600c38e235aa4830a501187a24615ec2271311	400	\\x0000000100000001409dfb6831fd5ba39c093a8184bf5ea9de5a7bc9f688b750dc4e26361dd433ef6a0233c09d1bf9bc768330c6546ff07665c6bfcf506ea4070152588679530ba4b34b194ef7860a23c7b3c47e7a2424afe91b2e98dda1264b51e18c9827ed70ef3c1180cbe75ff2abab8ab860752e80190ea875492ab386d2a620a2f0a4621a16	1	\\xfbbbed4781fab9652839ac51c113f94348867c4e4a60e2b0d87874ae2ede769377d8ff19cb4a34c6ea35e0c8b72ac39338351659998ffd49437b6b8f4862940a	1647487304000000	0	11000000
4	\\x86353765cce191143157f331bf5063c62b18ca561186284013f33183beee1c10bc3f5a4dded1f5b0f038edb4dd625730ed973f0a14a18012d0d935e525347491	400	\\x0000000100000001433902bf7dba7fd1d75ce82a8eb284b603046a59c9f926e16b543e0bd69cc91ba723481222312d734fbc48ef86aca4f6036e7f8b8cda25c4ec2e9651a4367c38976c53067b4d9b14bc1568335ef2da7a549f59ac9980a8e023b24991f062db891a1ed7a00c7a6ba7a27e53df72323075d00b8cc09c45a97b2e86b69521cd3c60	1	\\xe62c0a90546004a48c352f80fb50cba3edcbe0e5ebbd1819817d9eedd6dc7b1d1bccf4f7c9e645908fc5ac029cd18ad66a51badced24b7aafff56f05e753ce01	1647487304000000	0	11000000
5	\\x141706dd50bf573f59d689d254585aa14e6c35b6f12a23b24117c9a923742f4749a59c590cc6915697e93ab60dca1eb6bd0e1b0eede085d02adae8e0c5bea7ab	400	\\x000000010000000144709bbe5cfbc296fcdd72d7477c48bb9f52d88d952c2094ae21126fdf404a8ef1ddaed0b95ff66e4cf6950cc38dfaf87d59fa80ca71619caec81862df729a3ee47033aece11d6e8ff19bbf82c825cd9e148f1e5add77e0c887975847879213e6a0d0a1129f8cf1c3ce64d875462ae651096ab018c332d604d2487cae158f11c	1	\\x647ce83aee7cdc5eb6b4610e7810500cf8658c6bb7b8ef355c1ed7f7aa6e2f71750be120ef0caa887790b2e77949e75708c522fca51ecf819e4c1f623e4f3000	1647487304000000	0	11000000
6	\\x8e767bd3817179f38ad16e323a1b8392786879a689245491251f28118fa571196f088b396316ce84e9b27118707b65266f265872d002fc276ce660539fe71ef2	400	\\x0000000100000001612331b2b586f38bc2d5f93fef413756c07a1266ccc45e06383cc626a40fade5fbc4434aafeca1f0cbf5a04b92f3939d48479ea03f63a2f97e68007159ec3f20a56d52c34e97628c511ca57142bc66ffcdea8ca7193bf1e94a8c52831f162e25e0d6a87315dd52c3a4b1e3761ef8e104b8ba60c46884a0445fe10417ec99c13f	1	\\x376fcdbc75a521f784175a264b1ed5223a81614926c54abe14bb69c51d646b4e548c0bb84db17312431b1871c533bd3c5706fd23014a0114c350bbcdb14cf901	1647487304000000	0	11000000
7	\\xc93c26bc0930e6c933fcf85b83a0f65cbfab17e75cf8fc40532c33393fdd971ea496b89ef7ac230378cd0ed1c91278609258665b22cec7d54164e724ea37c6b0	400	\\x00000001000000019f508e9106a8465c86b692081d75b2f356ae6371bca8cc19525425dfaa7ef08411dbbb7e95108f8174eb91e0731367fadb3f915d3263ee11b5616b3dfc972772cae834620bce402c42d7ae73eb1b603fa80e89968d2c7f66c06050655a905b01f766c5f1cad9122360e88586a38a77f2f4159bde1a18cbfd2731621ce782b9a8	1	\\x9b735e778691d70a5b19f83668b3bfc59071f870ae231ebe7872a30749ab316bd92f0f50993f34ecad2a8858d286fbc400b4c2bbb4a6d09a710c772c77ab7407	1647487304000000	0	11000000
8	\\xc127ad4c9c0f52a661dc32779c82dad45e14f71521ee84397b773b607aa5094308fea5a411e72c1550ec5eb4dfa74b0339f0220fa8f3a47718238ff6508932e2	400	\\x0000000100000001074f0cad5ff0eea46a5236ffbedfb04797cb01d04fa60207026f4e5910e6e853ffdedc0416cd3e244680c90032b14418d82e1aab661d56b027f2bea74ba796187412941f4ad5d503819226dd7339911fe9ef23dd66c5b17d17456901ce72fc98ed44442684ae10a10d6b3b8ce6cfe651ce4548eb93a1b09bc962344efe8816ad	1	\\x5dc0a3bf30de93ae382dd0e886656930fcf42cfa0e44fbc63c66fd349665b9022c3241ca30d73f4aa068a344d0ec6d436b91928357477fbe7eb45c3f4223df04	1647487304000000	0	11000000
9	\\x76ddefc9fe44618d3d8e5639bd3e672a095ab5df9a0a7601185f1073454105b34c77758858a7c398c9ec4db02ae7294c5abd734458a41e2c777398e2f1e2531d	400	\\x0000000100000001949b7a0c276c9748e89f9ef0614ee659f68631551d72d6a0c781a978ac64d3b100f3d6ad217e2c76b7f4b0a663bf707f4f7466942bb322bce03bcf467723c6fb2db70aba2d039a7606703d7971e61afe9b1e6519d938da0d76e46bb5514d09654da97da09b318f6c5e4b38ae17a5e1446fce373527409e0bb28f2fcfc7f94863	1	\\x6dbd27ffaf727f982b7ee30e2bd270a396e2c87ad6916f9b8a891a0d0e64f817430447bf04fba8776f1be618ec36ff0ccb0dc8c62ee9ae24a225b5b9866f8b0c	1647487304000000	0	11000000
10	\\xea88cd12017c65208f569c642804015017ad6885b41d2aed00ae8a7322cbe2445fd13a754b5f4c3d43288a46f91465571ffa7b7c58c95dfa877502ce4d3de9e0	400	\\x0000000100000001950593ef63b46feba2b4b7514ba919c504d2399b80e130e0f8023d6ab1dd713a9a25359b5b760739e25110607f57b07c6a670a480f6d519d881f9a2f0191b70374d70efc2a053b32894251d348674b5d3ee20285e0fff08319c410db1cceded18e1af89193778e4bb1695ac362fa95552d65ede10b30cf6110860b01b52ff7ed	1	\\x8fa5191f92db9d6e1c5368e39dbb3ecd1a7d1d117b96ea7f4c33c14eded7db18748da07ae3ff1defa86b497c5153fe385126005f2bdec8b07b3dbd03577bf30e	1647487304000000	0	11000000
11	\\xd4a1ec7a21e4578e7dc6195c73e911960a7e8f7d6d8d50d4829b2824995b76cb384ea88f875440111c41632b0ef2d7e6896517cd2f7441973f42d64fc0ca9971	114	\\x000000010000000147090b773c833e8eceed137480b2e4e3bf10d149ff567e469d5a3c0e8a8484f8f3514b41a4eaff7097080a72b152e368ad93bedb7358d78130a0469acc124d7a22132651bd722b00b1a7a505916d851fe41f6a8583a8966505d7d3c43a3291dbd9bf96f7d8caaf3463cbc9eff3b0a7f512510f5abac50910619907200c5235ef	1	\\xb4e6b1c8915514e3a30ebf1b290af7ee9067fe080e1c22875a84ad515d04c8aa7e9cdf2657927496c4f2056c10353a710a7a163c09e1d9713925b20724216700	1647487304000000	0	2000000
12	\\xe3328b76247b7fca81231da1329ffa9a24feeae484543d367dc9f242b142e6857a5e6689067aef6b88cb525539d5079484e8ca0dc12e3236864126c6c6fda539	114	\\x00000001000000011890396e08a811f0e5b5990d7ed823ea586cf571a5f16f87291b5c578ccd912b532f83c36e6a36023f268ec2b255533a1c5794c43aa937b6a21234113ea8257cdb30c6657afb09281f443fa8f02afea23efe9e9a5bc1ac9af68b3ed9180015200b9937a48d0924cca77f07e2f5f0149dd80be96bf2a3b841ba5c45e251d04ca3	1	\\x24969700a8a462f0db09cf2049898be556f0035936a606314b972e663361f32d7be416aa425a7f1d1f0eebb6788d86155d75cdce242e0c4006ffbafd26f1db00	1647487304000000	0	2000000
13	\\xefcc94e5fbcccd58cd8101f383afbb97577f4dcd4d189774bc0d404ddacb272362dcc48840c7d724195336a0df492510fbbc8b32d932132a8de7f0a8657a8bc7	28	\\x00000001000000017b1428f4d2cd3264dff02d0dc1f7066e5147e109c6c35b23c31448bc495db43eee85229e3d1e7bc72c5ff4fb9455a03979970f44f6724ab1d9ba0e5b5eca0aeb3a4b500a79ce19bfa87cecd1abff558de83132674ed7185e3fcb01fd86bfc6f595d9e5d7647cd6c5ae00c785a6fe535bee0ce83f32c8b74fa9a743455d916c6b	2	\\xc3866ee8a21f000b56a38cee13b8f915e4ebd6c5375dbe3b1a3fab928c6a02ad20c2c3d900ee8a9df718b59c5179cab73e386373e220ca85db64dcb3ea99fb0e	1647487310000000	10	1000000
14	\\xf19913cdd15d3829822cda6af48e794ad28abd6c549ab6df9e764af35b94980e778eba020bf6fb48ea4be31ec6aaab2de64769d34d625ea0a1d7de94818bc7dd	83	\\x000000010000000126354cd6faf626ff411e09a770a566f1465ecd4ffaa07b02de30c704babf6e6927e87581d4a6aed5d3aaf0c1e973076f35df09aed55a9c14fd57567a5589ca918ee0eeb4a96ebeec474984dbf1329414c37f57552c945b4a1c9938438f89af6c8a49758d6014f55849cc3ce50059ce699042ebc70707ded9b754d9d8296a92af	2	\\xa517f4382399a978af925ac34e6fb2330e99d67ba3b322721492254d02bd66c60c560f469ca5357d34768de270192577a616d551d1bbbfc71c701e5d0781b80c	1647487310000000	5	1000000
15	\\xbd54563ee94a55dffd3e2c2b52568e3e290d0dcc111449c3fb3dfa4106979254adacc2fed19efd1fec6e418ae7be05efbecfe1ced827f2bd34d8f3101376a23b	299	\\x0000000100000001161f37832ebbc1ee2f22f8778df03d05800561653a6b6fb7127207c524764da735fec5f4f60415b962785f71673a89137982d44b43e73e270ed0b142339bd260d7d66fa1959f51fc2c047777ad003c3ad15ced775a1238bb639f9566097b02dad1e71ff1cf6e461d7134043d1c43b85857f355aed202a81a5843162c8bed63ec	2	\\x2038e9695892d4eef58c67da28210a5948994e37aefc6af1977548c49f03b341848271af518ee10f5a2507c391e1283a9f2ebc741e238acf82d5e5665283e107	1647487310000000	2	3000000
16	\\x1d63b9987bc0c9b06bdeab0b311427ecb717878275c585b95bd9d496862dfc425d4ed64c855c0651cc3386a0417ddc7330e63fa4989eefeb7fad9c1b0da15f9c	400	\\x00000001000000011636cc68acf5b566e48eaee66a7f3ec0f04fb2044ed07a358b6c40a987c17d2723efb0d839501395541721026dfa26226933e0edada70d06a12dc8b95aa67e59279b61d20174446e0bf45e1012da118d3fded00c6be3371879ced785eb0ded713c53f9613f473bff50285955ee3520503481661efe20df9366e20e37d867764a	2	\\xbf03bbc147ee6293a5ec12034a6e6302ee8549fae6dc4a138187cb6030947903f54f2c4df7c938065720b3395488aef650bc69a3eaae01e6613cb020e120ba09	1647487311000000	0	11000000
17	\\x1bca083d511ee038abb9be5d8054938f2261d639e7d04c6e5eaeb771a64b26607a33583e9a4a98425d213e3dbc243503fa6f918587c7fcc6a92b4d8d98b7ab82	400	\\x0000000100000001a177bec5d5b98b8e248152674395177d29ed2bd2e215c68f174c6f71980b1a4a95aa2f820c83f2a81f3a6674191acc0b046955145dd067295e19da4a2b903e16285b5eab5acb873c0e08b0f7f7226ada7c94d44f5b23eee30ac102e55b0dc08a6ef7ff96784dedadc29a5feb9e732aefe152842dca5881f2c9dd3f074452574d	2	\\x3d67469eae6cc87003e334bb35c3338b108feb7c60a5ade04d313f56a1f971f27a9ff9c0ffd3dc28984a2027751ee595f71196d991002532c8191c058d528606	1647487311000000	0	11000000
18	\\xa64bc2d5ce5bc391ec8d27ab224d0ed299eccc2794b2eaad4687b34064968a1c7d19727e50f76278d1493a2ea6ef7e2ab0e087dc8f2a08437062d10ad65d66ad	400	\\x000000010000000116d4b1d547aff1fa203872ca7de6de6ebe1e7d4bac7b5c0c58fa78f73bbaa02ae48865dc4bba3b848ccfd477aeba9e8be0cb11c6bc1df67bc335669efce74919dffa150b19961f49595b2c88a58359377ad0d1456368501d7c69cc01ce04da971d7b3fccd86810c157973f5f8e4e55fd54ef66bd69f33e5193888ee6f7c7cb69	2	\\x9b3cd6ecd7d70621676daba63bf668f67da5f8b1a69c5737283865d40d86449241c2faec3590d890b244226735e2c8eaf124cf55ddcaa22ac73c719060f02d03	1647487311000000	0	11000000
19	\\x76ee8bbbb5f6c66308eb7574c556fc4cea0a47dd4ff6f3c9da4f1f1573450e50a7f8fa1eca90c9060e0db1151bdcb546bdd695d3059e3d0e4404ab301a51f097	400	\\x000000010000000130f1d2a20966cdb99ccf151b2bbba822039fdc1d746e9f386bb963a430c019a9291d99416f104f0f7d0a12a8fa637a4a152ee9cf4cf0903c0f8b15600c6eda2d92ece639a30efbf4e14ce4d283e9db289de03b765aa550c7c228b6a0c8b790f4cc65be6b73652384687c6d572a0c4ea733063dd4e903d312de63a4c9e4328e8b	2	\\xf202a356b204f1d092f6bf46cef663230f2ebcec048077c4103ab6296fa468278b027914d6da746df3a726a3ab6f9c07ba3fdafb5f09aaa4d2b8ca76aa118803	1647487311000000	0	11000000
20	\\x8b2c91ce127377bff97d655d35dff72e6091bfedd1b14afc7b455fad4b5df38bb0e23231bf9990629c8770f666b17520e8f6924448e15f1d6b5951a4a6d854f6	400	\\x00000001000000014c01ecf0e0356252348da42ad2c7569fea81efa07b33ccdb3a71d8a91939866193b1a41b64ed1f8e6582465b3fb87f5ba5bd7cd62f6de0da9f3e55d8613a694d9a166cbd17a3160f5ebeea98ef6e44edc1b33a260425ecd63ef010abd0a161d815fd26202eae6c7e0e0e4a61f7d79339c33ca6d231a71cf56f426bdff9571359	2	\\x9e2c68489b4c11124885c370a8e3b4a635a5c7c38e7e3e443b7fe25e5379d1b56ac508602d17fd99993903150adaf420f84f1d1f8fb5bd6ad719e2cbe1bf580e	1647487311000000	0	11000000
21	\\x7f609cf9114f3b41335983880dc266719ebf713becdce7d39dba5d726c43bbaf45d923207235d361f9ae0a835e287cfbdfa355243ef6080cd35ba2c4ab5d2c47	400	\\x00000001000000019f9a8a871c4ed755887dfb1c4b307b5a6b0dacdd9de3aedf259eaa1e2f1b7e4785054593e62fd7cd8db0652c3aa4a4b6d8dd9011c04c375c48c0997d60b6f69fa4c0850ce5e85c0e1f69cbdb228364b74028306b8a261b5bf11ce3a75f2e52c094c50c9ee4be33503bfaa912e283c1b5d8648a3e13a98f0cf5bb5de5147f69fa	2	\\xa0f1c6f6db9d67b8dfd92f1f20db21498766f2dd5fa5a5b56b861b8183754bfdec9f8709ad4f45ee4e986be97c70fee91bc88916ff1e381caf2449ff94ac0c0e	1647487311000000	0	11000000
22	\\xd7909ef606b0dcb4bc490d27555ce211f9ae0ceb9387816099e76b73b5e90c050ab7dd54e4cf6aa54f18274110fe15215fe32197fa68c37831426d308e4102ec	400	\\x000000010000000135d0d2265145fb54504f2aa381fc4a579dc3e3d11ee7d234037a1d81c36af19917a26eddfab866ee0ae8329238d70eed4fa3925d28769ab7e20fe8062bea9008e847e99972c0bbf89d6a32316b3d35bf480086a4b028c2f061fed6ec4d68e7c4604404c77f7bed361b3d2e78c595ab8cdcf1c1e6924f8b4c29ea46ee419da570	2	\\xf7500f460738bf5a606e2e11adecb228e15af4dbc167e8127ce82a6841b4d68b27ee11fa46967564d3cbb1cf143b0824ba9a9ac5f87c9a1c89ae4bf6cef42504	1647487311000000	0	11000000
23	\\xd8fc1e1d1dc30250ec041510a42143e00c1e6c5af3b3db4091fd041daeabceb43592bb2e3cf9af0050ea3341949afd0a40199c4041ac3ffe0156044865ba6d22	400	\\x0000000100000001941f3af868cda2c71dbe6087b06bbbc90afb64116403dcf6e2038111bd43fabb2473224ac01af48a143de2b85ac7261e9850c5645873ccb83f9db19409028aa9136b38a086943281daa5e038ee1430aac388ba1534fb5fabaeadeba3d822adb58359e26e6cfe695be0f12f979cf8ef15371811f714e2ea1788e4090aa80ac6b8	2	\\x038ea110493dd8437ce3a1851f2093dd4fbe4d3c0264ebec6177fee80052cb60018f240d13fd5fc84e878f51bb6b968f8e28d1ac3e6c927544e7e21c1c6eac0e	1647487311000000	0	11000000
24	\\x2eb48bec4d4b1cb95b1bbcc10bc120a65934ca3acb353db3f1b4c1a44446d2f9b06613288c1e1074da0b02b0d66378830140bb7aba6ac891a31bd3e840bf0619	114	\\x00000001000000015f3cd0e57fd9a956089261fe96d7f7490f997922208805d8811350ebfccb5bf61faf8287fa6bbc11aa25f275564c6c2e60858b02daa7206ec39dae8aaa30f564b88244af879eef8484e458da0c9da9b6e6c23679a3c2e68db0af916edef298cdec1fbe27a236dd309d2066bfd902324d34c20d02a2f7283d90683cce42727316	2	\\x6305f78cc39ec30099607c549e816562a553b47b5a934be140d6bb0d367c789a4a7735bc8fe98bc796536378e8f6c9e80d94e1298c6d68f43a241b5dd86c4801	1647487311000000	0	2000000
25	\\xd126a5ebab42e9dadd495882a16797ca31a4d8d725a7ac2b475ba519166a5633155d724eac975a60b56b0800542ad6ca17d8a18122efd628b7b104047b2b2116	114	\\x0000000100000001839657048a9ad072ba81e8ae542bf631b4d70650daf244d20291248f181532a8148255369303ed0ed61c080f6e0a5cfad0ef417c4be276e823d57298269a23e1c7d8681132674f4051e60ae6da70a7bad0c66e037a7c454c559bfdef7ad6d660ed73940a8bfa9faa3bdd5e6e4adc48c31b38345d84147cdfcdbebbec4b5ffac8	2	\\xce1cc15c695f27e228022f622de926f430ad85977adb1b1fe89164acb3e872f4c47a6318f47548ffd8fca824da5a51187c42704f68063ae3688a69eb322daf05	1647487311000000	0	2000000
26	\\x4b8a8c86646bf20eb28f42be4b8777d9c5ad2f7f5233decb380ce97ddbfb44fe284115c2c0de7e0de4d7aebdb0c7c090c323d73d562ade851b9be70d22847c82	114	\\x000000010000000159e107d74e9ecb792a8f4e9ca480372c9059baf7bbec1ba1042a647ddc1082e32128c41ad9792becde05a3ab3d8dbf898eac0627e3eef0cd770d1bf36f10b8780f948e2704ffda10ba240bc7e2ee010249da8566902642ee186c4622a358983e1edf9fca675f2c7c1a7e370a3c756762b8720ad9e295887fc0dbf48c431d0f25	2	\\x40dbd8ef5128186422bbc551fd38a13c43e83824363ab62f1dc423f5d807f9fd64febbeb474d22c347b8f37201ba459243774314ff5a674d144b3303e121760a	1647487311000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xa29d56ebfeffbd1bedef95284efba42496f74dc1fc8455ea67e26a9efdf46ff275a27f98e93bf8ac4d5fd08dad51d1f28cbbce8e872b6ce156ae75359a436202	t	1647487295000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x56045e5f13a2d02121b82ec3ee127e6e0279d6b491bdb780728115269164e2288036ec5f644ef9179884f08dab08d6e5bfed956974540b470e7a6872f3f58a05
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
1	\\xc1123d3a27ec6169ee856a6065cf8c133828b4cd8164ea53236dbf116ae69faf	payto://x-taler-bank/localhost/testuser-6cts6znz	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
3	\\x7a8a2d5f3c627474f1ae90a9ed2df69d3788faeddf8d614bc6a9039c1a1c97a8	payto://x-taler-bank/localhost/testuser-e2lwc5ki	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647487288000000	0	1024	f	wirewatch-exchange-account-1
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

