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
exchange-0001	2022-03-15 13:07:31.189054+01	grothoff	{}	{}
merchant-0001	2022-03-15 13:07:32.580552+01	grothoff	{}	{}
auditor-0001	2022-03-15 13:07:33.444254+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-03-15 13:07:42.353961+01	f	dfaad7b8-0bf9-44d8-8fa0-ad10916ccdda	12	1
2	TESTKUDOS:8	WH7DGTQHQPXKEA0H7C44CCXA1T5VZNYZNMTBWSY5N4BYPNRD8E5G	2022-03-15 13:07:46.178391+01	f	64a13cdb-ab6d-4b31-afc6-209be0af2d3f	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
e9506bd6-0799-4338-bd35-9bf9eb9f5a1f	TESTKUDOS:8	t	t	f	WH7DGTQHQPXKEA0H7C44CCXA1T5VZNYZNMTBWSY5N4BYPNRD8E5G	2	12
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
1	1	58	\\x93585de3ad3f2220d597d3582213ffe7bf98e23a9a70e28933631b121727ffd53e3abd26634437aa074b1aaec1a03e2d837a7e2d9977f90c98e40abdc2a9b005
2	1	390	\\x94a16c252d37cef102ba045c36c74d220d4feb25a1c01e7eab59db1bf7825780381905cfe3817c437cbbea3804b7cb5d7f01a0624f28245d217b97493c42520d
3	1	86	\\x6f16c41f5a1fb9de7adf6e90e6bea35b5c16c8cb0d5ceadc827a1adb3bf89c0f8e99df244c84e040998f81e789b8767df18885bd826e3390aa519b3d12aa7f01
4	1	378	\\xe16db65129e13138c77c02576010f71d8865ca6041d3c1dcf32afe5ff99b006cb68bfedd486a228f183e605e0174c0c78b3f7fee4c65db5e5bc6cd9c91a25f07
5	1	418	\\x6bb1a35558d9c09910516f6545d682e16f3669a5aca18a09e69af0ba0d0cd27a0b668b67166c9723b8fb67796e7a8b4b1cb9da74a5a50fa7c0eca5fdfbed330a
6	1	90	\\xe2ec30c4622be7c52a7594e6dc5f85f495c5d2f359b5f71b9532523781b3dfc2d3709d3819fd2912e40ae14d0c2740ef51ca8b5bd980d588c9ffc3342859b400
7	1	125	\\x1701a9fd26d5cbba7780c9ef91e3022ab6161835b88cd4c76040366f33af2a07a87d2b5a5650a0c37aa444b223287555a967bbec27370b73dceb0468c5f2ed01
8	1	412	\\xd9c7c914231e862ca267b94d59257206f90f243f4d751a24628f2c8a2ff23f37ba60d19d04ef1cc1ff797309c322ba376a35caa4072483335f55c7d792686a05
9	1	296	\\xfed81945f6a437970204c54c1727e27a5162330280950490247a445781d5040bc5a8d7d9b8ac77150b422b038f4e10d98168b568aceeb1e9a36712795aedb604
10	1	56	\\xdd6c00e91f76752350c2eb242a25a956e60c6e15703100b93839bff1c16553034c157116820cafeee90dae78c6fb77d94fbecacfc9fe409ba267af4d5f490608
11	1	247	\\x27ee83be32704147ad15a0f81157f08ffd2b46a09a4ef944dc66cc1bf1545790cd5360740012461d995705d8e0c606999d878d79bc4f46d6f4dc6fb488e6df06
12	1	178	\\x3b5e60d91ff1a61221519201874624058fa9e1f20bef339d5fa822211e01b287a56822169fb99859c5a2ccbbbdc60f4c76d479f3832c830e2cd07ca5a4defd05
13	1	271	\\x0d34f1d3d554c7af95736051303aae24baacaa2dcbf06af58bd1bb36985bf275355fb29fa69a0a51b28deef44a07bf10db604217e1e1e65f24780c08949d9a04
14	1	202	\\x3ce753df5ca370e3b36685d2ff52a5f6c068f333a4aed99968ce5fa8299a6b1703708c5c0e67656036665a516c87621399be316cd57b099acc81817da4bab107
15	1	237	\\xe0d9fbafd993e04d6f5790d0a336965bccc6f4f15e1492528a15146d18fd7e32dece09dfe265dc7050b2e2718dc07f79042101c3ad7a4eed4131f95170acdd0e
16	1	336	\\x7a1a300bf89bad96273ac933b9ac164daa1e8e9a7b5e000376475f98e9e2bf28009cc05f279410effbd391f8038fb2e74be5c486da883e5b506ae69749db0b09
17	1	311	\\xefe4b4b209d69c3aab93123048dcaa86a7eb30cf218e7399e1a6565f1fc2d0a6c21147b6b4c582c6aca6c446949319f6cd4a297476cd1a85800e19bd0c5c8005
18	1	146	\\x10f47a7ea34c47bcf1f7d135e4e6d3014a17f450d64f0c33afb861d6e45fe792d8fe8c65399deaa7d84d27bf4cee8c617b0ba836f0bcfbcc9933434f0a4c3903
19	1	22	\\xd77d300b914accabda437f27caa5902620aa7ca2beba49f5d57f6952da1c210c4876859d61c7918ac15395916b282de01c5c5843ffd0ea2b72d7dd93343c310c
20	1	93	\\x8b91aa5cf210980b40fe6d1d1b193e2269638af9fdffe9859bb83c44b3b33b916d17c4a2b3ce52f48e6d527b3f6eae50be6762061f33c99c18cbace818b5f500
21	1	107	\\xa00418fa1384a88870127f8062dc120f6eb7ce4ce482031ffb98da5acdbe70f9768c9d6d9d8180dbffda4d59792553acf5c67f4f0e52fc34ff8de27743ac8c04
22	1	374	\\x473792bc35ab5d2d1cc5a58cae121728acf6facc6e2cfb2a5223186f5f1e9d3291bb6f69fa66e2a58c681881ae8adfbb9f10db1eb06ba5c6861823aa133ccd00
23	1	208	\\xcf3fc4945a2156fd584ab8e566c33def6f61e1fd2a3700d17fd435b35f71573d162908357cc3e659745790303cc19ea66470b8a56f4c2059498bc5ebf9fe370b
24	1	101	\\xed02ebeb1ec72692a41678d8aa113e1538b265bb6cc7063d4175cd8c4fe0f3a50fe119d7282926e76198ef8edc5c663ad485e22e8cfaa2fdd41583adcb427e03
25	1	77	\\xfec3e9e2e8f6f58bf7d91aa7abb32ef45e04461403bcebda3d12377419ccda5befdff467df991fad3a5fd8e518f6b138a8cb3eb5cba3b616175239ee721afa01
26	1	318	\\x1a39ba45400731e6bb00b704384f0dc7e9ac0b54e50c8a21b8f116b9fbe0b2f563e4b182fc5c45372016f32727c694531ef2777026b30fefda9acdb0c8f98809
27	1	155	\\x8107a3ef4c30cb133bfab78262476d00959252cda5b695809a2a38ebca8d98258ad6aa1c1dd00fe572730e7d1cc5a3bc7acf4222c2550decd68d7f42a467c20e
28	1	263	\\x76563f81f366f1da54f29d946f3e852c1c30a3238944d15528d06612873712689758292d9a4af22e7e23669a27ffff42858bce3eb36c2ced6177c092e5909a05
29	1	325	\\x037fd6026bae1c4017e131a47a0c233a3ac7d7aad47a0085166bdb3acc2b51989b0849180cd085c142045d0f38db8a508e951e4fb49daf784ffbf3e1d5cc1806
30	1	98	\\xae64b5ff407f995fb8cc8ca301ce36c74ae0a1099d58539c5580022b29d000e2ddf75a1e6667e7e9b4ebcba11476be190012ace6d9e03663a3593d38a8590c03
31	1	103	\\x5f9b13fc6d8d2a132f194893206b09d1c9f4daae84a95fe9bb270fac71f24448eb3ea172d75a0ad72cd35d1162e6c5b4e14fc8f781d9d383eb23c013546d460f
32	1	232	\\xd4fa7d097f45a43c0b11c0cc133cfaea5808b387b04c5537499f7a759b4400ee09bf226a43bf6bb637a31884d9349275039654ce85c16ccf46d1c01ff2c7c00a
33	1	367	\\xc3c21f5b2439d1958ca0ed0e9be1cdc0125246c73076cf26e61e980d9a5a2245fa49a4fc2fe5891a07970b8d06e1a9e8493e3a22e1ef22b1b9952b09f8786f0c
34	1	314	\\x4ae153b7686d90f1c5c492ce464b651da105abf60ce3c987cd24b3b258acad36cd9bdeccd6314f821d0d89b63199fbc425dfd223ca68c8bd28bb412ff2ab380f
35	1	37	\\xf2a90191e6ee4065b5d3cadeb43d313fddcd92af0a7c79995a7a928ec2527c9702816d6e7dae1b9362dc0e208fd136e8005161197684c2120c14d1f1bd290b00
36	1	124	\\xdf48cf036d577d5aa3d9e741e9e8451ed84da616d662f8d4957275c2b2f26406f2cd31e16cb114749f1986d25ea479cdbb7e696b6ce722cf2fd826adc236aa0e
37	1	163	\\x218839e46d6e49ca410b7334c51d0d99f668da79164a39d501d3ac513b5d17b28201fe5863db016100e16389bc5fef31c222768339b429204b5f3df0e7cb6a01
38	1	287	\\x74b56d6bab80b4a46a03efb58d514fc50a3a16ea3252f553b29e84456776a7d6efe09cd99546bd25c114cbd962bd88b235de0d9ce1ac4f97a844baa4d3542b0e
39	1	138	\\x4612cc19d1aa3c357a1f962b5f6fc5fca4931b2bc80800675fefee3924896f2f883ba07eae5fed27e3f888188072c3f025cbec20d39c7d76e05a01db76ee840c
40	1	72	\\xe7d7af4db47a64dcbfbe8033c25ea92438094e0251d6a1dedb8dd86da681e5360dcd8019cba891aed3de2040268d500140b4365b9c67c143c68470fc3bd68502
41	1	168	\\xb6860ec684514114273c767da9dcb35d853a2c79bebeab4769652844e92aabbecf0dc7d9002253de603fadc75d7c0ce75e0959860762029ec08ae47bfad6ad0d
42	1	115	\\x7ae8d238c49a76cfbb8f8c76d182d09f4ee6634ad6ec0313d8d60d723069d06b7bed3bcf84b1f875d41509b6e6c71612f96240a5c88da8640c50497c56a67e05
43	1	133	\\x5f28ce9ca438540c64c63e0718dc92656e7579ec2a349b60e75bf80c43eedd854a042ae0a404d5846c2b293c913ed2d59648a11f1043a40038b52a56084f3b0d
44	1	141	\\xd6582b627500a40dab870281ecedf6de0eb062b007a62c1f88e3553e74b163c36a4fe1352f672f753dcf47380a2980db5fe110ebb0879d6a870371cbe6bb570d
45	1	356	\\x486cc35e4859a6005b3e1694657bf4613674605278cbefc3906e0f8905499b59809da2948cbfbf33e97ca49f3693c9618500459cc09d57106fc769e81a51730a
46	1	260	\\xf547edef0d401199e492524fedb3341985de52caf634afbfe1f244cd50fed87f3d646b373198cc517c8b28274f26c3e74726e7f4ce67b74eec009ab887d44106
47	1	253	\\xcbb80d74552ec4eabc8b2e50d3d80bf61812edef92a1225f8f3fe433d2ace4121bf5b7022dd26c9f47130200169978f942c1a7de597dcc6463360c7b2da33a07
48	1	419	\\xe3c4b1e9539b535b68523f6d19cf3c727bc31dca51479b58619fa6aff9cf4f25c1792b6c81798de966b7ecbed788f4d919744da65a333b4a93f39459a4f60d04
49	1	117	\\x3158913a807778cc46588b21ef78cd335db8ce8f061b6990add439dba160bcb60d3a17e5b2608f659be9eccee87e8311f83cac1a66bed915c22d8607048a3803
50	1	194	\\xde947c97388a56b26303da3ae1ab1986876c220ee86ed4b78f58cafd41b80d53cc66dc45a8be813f51dc66bf0a880b9bef92a22a0ee2fc9fc4b6136879580e06
51	1	364	\\x04c2a6c25e9ded7dbd39d6bfa8f0bdf74baf44d4461da5c771641580cebbf1e746e602dd9cd26c981b9c7698593ae55688844270842865840b34c45d5271c50f
52	1	226	\\x5f75a0bfe74fb3d698cec536cfd2f7ee04607a2688d9db1dae5f1b331d2a4779e9356eb94ee6e85c51e021e7d9fefddd3fc6b5b6d22f8151f5247918fbacb308
53	1	244	\\xaf03737da581ae79c15b1ab3a8b821812de3099e73dd98e076fffdddf98af0833e7de047ccdef6d17dfb0faf5d010fb57b9fb89f3243acf1167a168a35e4e609
54	1	350	\\xccf4c34d3c9d553e4944e2028826b226504eec8980cf29c4d5ac5e982bcf9934a88eabc858a704dc552b9e357f52dbd1202c37d192edec2c1671e81f0371f004
55	1	4	\\x8567aa6251ef2810e58f7f0d086d97f6decf9a554c6308408129ec527535b9f702a20b60862e1d14a0fc8bb781e4f88f02fd1227b5a5647c62824df222097904
56	1	131	\\x160981f7415c3069dce1138a117aed68e3c8a5d774ac362eab31b934ac8461263f1e458236b1e9703d3497b7616c73124ce2329a0103460b3a538720ed838d03
57	1	157	\\xf523f251b7eff59789e44e9f574b70cc02fb332c9cce9597b76328019d075f1b4e9bd7ccac59b2c545f76b42fc3c2ed5f5d54a0651f924d23573f06eac098407
58	1	313	\\x8fd436e32a506d8bcf429060ae6da21c677f5de8dd47d347d7c00cb853e5bc6c8fa89fa467f419470f982609940d2fd3818dce5c0238d877acc2c6af5eab9b0e
59	1	188	\\x83371c6450ee5746e38b551b26fce4bd99ecb9c3f080f3a9582dcc7be63b6800a743716a2380a491e80a2b8c6ac4671896f0551dc5efbb0dc1a8322a6361fa06
60	1	377	\\x12c4f6d068408ae3afa263929a7e696eb9051035b1688fe1fb75eda6ae6007bee46627767b865a028c9f577cc51da6a6f31991263cc1da6015efcf754835640b
61	1	332	\\x6024dc13a2c7527f04af9332ac723b446d1decba599549413f7d9893e8a898332958c63e982c79d3d93ab212ab48fc429b2616e3c536cb36f4d8807225ab4b0c
62	1	127	\\xaa163a97d53a361061b772b270c2d891a92d98833197c60480bc0613ad6688b24433973ece68efb9c4777614f2728d0742417c8c8ed136f9161fbb0008099c05
63	1	186	\\x7f47b7e13c25b560de8760f0b899ca69e38f0f73b2a489203be801507603eff4de9e04f45ea5fa162379e47a55fa1766a6c3ccbe02bab7b36be654e1896b6d0f
64	1	293	\\x4d573d2e2287ead29373194b3538698ce84751c054e85b01093f4f9b8712fe5c40a7ed67a9bca91242cd8e5c7c3f5bfb7fc36a6b185e03454aa18b97e9ac9700
65	1	29	\\x552d8439605e9443e62d903f46e7e198bde7b163d15cafdae2c263e6b82890b7c02c851bb60ff490fb7cd1f883daffe25db82fa390f85c0f42154e71266c5708
66	1	402	\\x3176ebd86a597c7cc247d4531476103c3a365d49ee52472b91cabf3926c9e8719ff353548a28d154c0ccfe92f1fff3b542de9e20b7e416cede62fed6de1c0a05
67	1	320	\\x41ead37e321c62a44db65579b37349d0d865650a5d696ab521c9818d50fd0e867cfc85633e03f8bfd3cbaa96c4b78a52b2983f898c8e0bc438b1e92cf24c8505
68	1	83	\\x3a64169aa9f41ff1364e8ae97da3379444f8a9c4825349b57b9f7567b0a63e80c905c538582f4d6d7ec8f999b3607db9978d189dc79fb777d01f3c73ef813803
69	1	289	\\x92443016ed5ff8999db72696494b7c4544b15bed811474ac49f0b11b016a82c791a838a333e8466870ca0078fae132964b7624fc3ef399b57da5dd4656c0b605
70	1	203	\\x8d343c1240179a58551ebc5402ddad5cbf96cc97b10dee614184d817e760769a10958342178d1f0c345dabed3f202992fbf9655a8f3d61ce553ab60abeb37000
71	1	330	\\xee70770df42728dd77ac370b3f766a207d16148816c3a678c406e636db3b17f17c484051231d2b814f1d183f4968f86d8c3fd4a9da8da35628696e10cd58d009
72	1	46	\\x26a2fb19575967476e5c297b4be61fda4d5573a585fc344378c639b47edd19d86c5284c4a25007f41591cec405907e35cd88f4c5a566378b34d91877d412bd0a
73	1	329	\\x9588c18cbfa6b020fe1f6f9ad3256ab8dc51e61a5c4f23f965753dcb751a0aa528bedc5692cdb49986585ffa79d9656a7ff6e738f555ffe7e0cce2bdb31cdf0e
74	1	66	\\x0ca73eb71bdb9bbefd2964ea7a049038a13719be67da5aae8101aa70997aa7c8723d08fda3eca16424ed4ceb408832a82c2f968047006d89802ef4b86c62060f
75	1	308	\\x0490e4c9d1b13c25d8370cb65ba4b7b4a6a8f7292288a5be1b142c6237d79cf5cf60f23801e83aa3ae928d2f71a6b2b61af2c01eeeb9f7fad1c8d3ad8d5ab504
76	1	424	\\xf09d5db0699c4ea84d854ac74b8920cddfa850a2d40e4e965bb1c20e1aa4385d596ccd254ca65ce6abe6a39a36d3a911acda762de01bd410f94fe798a616cc0d
77	1	238	\\xe484af5a7e1915ab01bf67aec6be789cf52ec910f1f2386c6a976fe72860c98395fdc4c571a03a7f2cf638e138619ea9edea1d7e3d9e3ad61f1e8b94f7277d0c
78	1	223	\\x92e18a2ef8d9eb1eb888b10556583e688820f3dec729ee0c4058200926e132c25c177dfb832698a9436925984a76edb61b9c4cb8fd70319581903ec66f14400f
79	1	57	\\x4aca1b5ef96af8309e199d01c43470987b5bf5738c730f623a658a27e2d60c70d957f1538ea8935db5ec657c8c95415633a3821807688d4dcbd783255db64e02
80	1	385	\\x0cb60b7ff32b3bbd95d8328447082fcde7d4fa0f9343ec45d643e6fb4b595e4e367c14ed03d12c3ce811ad5cc85457e86fade412074504959ab81c4661227f05
81	1	227	\\x0935781fa5de23940ece1beae277d51890cd1a5d9b77465e081c916a5d102cf4bea5d5149d129fa45aa3b470649f88d6124380f69e3266b5ae1dc5f58b3fce04
82	1	305	\\x8cc30951b7fefdca71be19109f8bba372f99dc265e90d5f9eec644b65b1e0740eb03c534d5164912c4506a92997e48afa472af1576f6859151238ddf69100903
83	1	370	\\x489c9eb230036f4f173cd09ba210c4a5c4b70202f20a15970e7eef084fdea3f25b65ec60d3b23f063463970dd9d0eef85f0311ba22fb2900db88a1fe4ef1d503
84	1	386	\\x5c9bdf28b4ec224433a27df5d1e23f3290d7637faa17fd71f32cce0416bc9aea0ed7ba1a50056f528a43e1cbda881d871312c7a790818e1d8b1fe8f9b04e6a0c
85	1	291	\\xf68253f759620f84a4747a7729482ebbb107aabcdab997f4a80d0df173ba81ee83a833566c6f6252246df56f3de708476cea60db2c838ad9fa2ea03c65358a0d
86	1	45	\\x59edabe75d0abb385d373d0854178fabd0777a9ea83e47312dc11a48b4b7d22998a3b1149c1e0671754706519e46f13e57f8e068170fe930841b17ee3f2f2508
87	1	262	\\x53ccb9bcc2d78bc4df132a136c8d3fcd10c4638f1ca28bb7538011de867fb3e4b857deab36d0e3845b8bdbe58323c211f9cb0e8d735b493dad80318d01d6d50e
88	1	3	\\xa4422920082d6074b00cd08ce590cdd83b6205f7dc83fbf97b2d2b8eb199f33daa7b3a94c7705aad4b869befbe7196371bc69a054bd3c1cd0b80414fdf32180b
89	1	331	\\x4f25cff3af340d1fd23ee3eea9109592daa928c301edd803f7378589b4535bf38aa1aacb7d24dcda9f6517683675acb507428817b222eec989153148987a6703
90	1	360	\\x9260d75fffd00e823bf7de130ced45e46701dcaa8cc4416783ecdc634ef1b489da203f563d15b8228ddc9b225fce2135ef73ab0c76dbdeed4d65f747bffa8d04
91	1	55	\\xc7f82ecdc3d4904f8db3f9bd6863799e31eb9af10a573f530d21fd9af14569acd5285cf150e7542391f0db75fbfd480b9b6f24d3dac066422522723fecf6400b
92	1	190	\\x615b8ba9121427f5780966230fec9a7551886c5a3df23be144fea515b6a7e59a2cd30c37ab580fd20fdc270e289010bbd93bb94422176475d311f5874aa9b90f
93	1	214	\\x015525c98685f0821253a6e96db374b40c7ae233ee941da2f636146f7c7c02a08af37aa63726b84a2ec1d9e6bae62fa0689009c853c929c055181a2f14307f01
94	1	240	\\x4f0214845d79ac44139e8882b65414e8139518e161a6e3ad305b07d6b6693d2e1bdd279f9a9be1f5fbf7a256373f9d07d6c648955635307409836d78cf0ceb09
95	1	62	\\xf103cb0c83aadd7ffb74727dd8046e61fdae5f2625b85103012316c408f29764853909b5dc0c1d191b739223dbf46709d4e152f72fe1b693561328bc9e65ae02
96	1	104	\\xcb3e99d6e792ec02632797d9460dd11f0e15c4334fea50cb3ee317d87a3b8490649adbd1982b2823851046772fc61fb3ee540014671878c9f57af84d26576009
97	1	126	\\xf7d34faa91b8f83fbe8c47f4f627f5f3ebe97af2fc0661f12d2e902b5525a8ec54a218fd80828f6c074c83cea38abf5de825b9cfb6118cb9fff95c4b5c9ae60a
98	1	41	\\x9c6a6c0a7f3790c2427c41975b5b78a5f6e09869141be85e9454c61727f61955090864b6fce2fa9cc1aa0bdd1dd58b3c47d0e6563f32a919d76d7d49d43b9909
99	1	108	\\xc5421f19a5b9bdf1c1ea7438450a9cc944a895a9228474de773fdcad3600a130a5ebd7031616f33d358ba94f6fd3e7f5befdf1dcd8cc1727d3a7650bbf20ed0e
100	1	204	\\x808f93aef3e6be567b9f875b1a4560cecf749e585d614de9a0689aed921f9edb379684340a7ccb688b5af618ac2caa1f4321ef63a058340d477c97ffcc72aa04
101	1	221	\\x3a557127a2371ee9220681d90f3a90de32a89f6d49efe5f4af3a227ec27b1edcee278cbd9696ff1e872ae993c806e1bb44e49d843a17af9809087861e71f9a09
102	1	261	\\xcb2bb83bbfae69774203ad095a324205a90e7931b44ddfe40f492553779136aa9af019334d66271ce102400f053d4c442242ea656abb11eaf6189c1b10f98a06
103	1	40	\\x1d817ab2d9312e89e080ee5d3b51277f33523448a84b31e6fdf5d06fbc4b9ea9d1bb1ba6bb7591f70d4b5daef4874af53bbeba5ea11344fb7d2599c1cc900c04
104	1	277	\\xfb45064b64a9edc27e12d2db9fc39cc32bf9216c7f474ae6abae1dec838614e384faaabdc4c13eb74ed6c20ef9a0e22b254eebaa342a7ee513ae19101af6c00b
105	1	280	\\x2fc85953467708063a30647f22ceb814aa38a193f506cae36f0a5cdc87c9821304bcba1e1a989df17706fd1861b6eeefd5b4dd76583a3c203362a95a9de1c102
106	1	164	\\xad5649a284908fd1ff440eac2031479a285e09002467b5f3037d689f738022bcefdd2e7d200d549cdfb6427268cee963c3596ee60fdce13c44f4e24dd1d05a00
107	1	384	\\xd4ae8cb0a9c06d4f96845898ed361c36c256be64a8729fc04362dc75966359c6f04b8dc1dc2962a1a8491af266caaeb6d71bfa66965e0139df91af214f642104
108	1	79	\\x92173d72c1e10525b90e39ecbc6e025e02e937b4ad184b5327160b182d74bdc2dcea0fb5e18153008c2e88f6ef2791ad53b0f1e4c647a044ff34e465c0034b0f
109	1	229	\\x1c1fd7ad0802d908ed1a7cd28589971e316050d15885fb044138c16992f701acb77c2b92d23198b627d577136674468a2582d60c69efa48b42431c43f2980f02
110	1	19	\\xb6f48c520579459c5726caab85c0677116f1ffb125f67a9ee0c44d4246cdde31c6f2d89385c48d5428755ccd102fa8d6efbb550212f3d6b935edc7eafb84de01
111	1	251	\\x58913276fb59cc33075bd7693c5d00c0fa4a58fcf19f9de45569f237b968759433cec523363b256cbc11a455a566a0a69440fd5b479e1be492b383d9ad821507
112	1	228	\\xbb50d47186902e00a7e439483311f3e6a01811643ab9c1575b483210d03419016ca7446835c21f3e37ca64a3cad8eff400d4af79105e15275a9f1b0c97ce6d00
113	1	249	\\x229b8cf89f20a21a54ce29cc13fd9e8be8a24dfc0a01a90fe98f4ae35b85358c276dbe9697e9aa393a9ee6eb277db5231bcf0c8e99b7675eeced7cd6fb536d08
114	1	185	\\xb0f64eecfd7e0c6b6372d79b65ecc1858777c15ef6d362d20b409869a69d483588bc0aacf4216c72b403222b680283910ad705c4acff242076dfed88fc16bc0b
115	1	309	\\x991c0b04258ede17f8d80ed2219ed9528016b0fd26c0514c6f1a31d2b5a89f6729bfb62920f00f94fdeab52874e0312ee7a6e5cc5318098afff4b86ec6cc9806
116	1	248	\\xf50b5d8b5911078d13f22aebf0ba7156289f1f355e0da4fcc4c8e2f0f09458e50928fec975b31225d94eeff7eb9017084aa68e12389329cd05c8714eca9c4604
117	1	363	\\x2bae9e7adb93bf4583cf6f2571f929d74317c0717a0ca290788dcbcefcf71ec9bd5606ea164fe21703ce2971d2adfc4bd99429917b5d9d84bc19415fc8c65701
118	1	60	\\x0742b6e0f1f0efabd5eac1c46c88665c38b41af74faea1bbf918f1849927a87ce12eef1b6a391290ee78f3fcf08ea9c28a39a65a1a01bc18b48eb03fbc68b40f
119	1	50	\\x45a41ff0291ecad793ec0b4f5cb56a13be5185488e3592e02e69027577cdb2a0b3b1910f2c76e66441bf2cd8570d7013cbcb0fcdf5cebc5ed68d6b24c61c4f03
120	1	399	\\xeda07b92685195d45f2fc8d576baf2b561d2e97b3159e6a561f16ce0cec67bfb4695a8e3798b3db9ad73f2d9903444f318abdedb16a5046024f384b375560902
121	1	349	\\x878be87f593f3ace2a0e82ac763fdfe58a7b496b5918dcf19c908661cc5016af014d2a221846a065dd0257d9c161e137f8fea6f7644f96c239754bb544c59004
122	1	177	\\x6351efcbeff61be2cc66f264e2e30bcc5b1dc9aba1758c0c080315b8855a987210f24b1656e0fe14a7e4994df19150e50e3e63ab711d04ce392b3d0cf614c002
123	1	210	\\xd6c740590ee2d3965c892850774a0086cd9e7c5a2845379ebb1f805545af6b29558faf83bee3fdfd13cf705d6e2240e0413e897d9adc113c98014dffb9760e06
124	1	396	\\x26712a8fa7a3740688fa8cc122ae7480c0acd85a7bcbf85a317aa5953300712f81f9a3f09e7962e471884bbd37ebcc8153c6b1325c22154cb4a7f13e5b7c2002
125	1	128	\\x2d7f71992a6cd79388a52d96a6795de297463a589001dc1c949f2e2403c9cea454ddf32fd49ff50c605277973c718227a73c10c2c112daae2e19d029da088501
126	1	64	\\xa2a2fae2db13b961b8811e8e7dfba090a256da7d5e82f2f287165a8e13993fed79ba44c6b17dcb44ddac69bd512d5ba81ea365ca05e5ae724b90544756f83500
127	1	34	\\x541e7f698daf1dd509f3adeba62399b76c141e88168b3f7b9e33dbe6409847fc6e5258b15abdcea19d3e4d7cfd3ec3015808c81cf5f4bf25863956439e196c0b
128	1	275	\\x0ba2c202f9bcc834f2c8a7bd7ab665c8a4d929283d4d9596b7c5019a23976e690d8701e54c6d62828806f0ebade673843ef67f927b4ea885598998b9e86e1001
129	1	171	\\x1e52d0303c5e266d4f26536cc0a6350759c9b11f102416a411820a62a36e5199dc3831b5bf94c151c54522764a553e016b7a241aa1ed294f2074a7edafc15b08
130	1	105	\\x67a17685482769bf99d91523990dd4df2b098b05534a43706dd730b1e0fdf8b2c7e8b3419b4ad20f36d8246896e5616899ece705ecc9bad1f7944b68c2ed6a0b
131	1	106	\\xf658cce4107ccb5e9468c1dbf6923c1924c4797248aea340803168c0732bb953a32b31b8344e4246ed523483abc32ba8362cf0140a7eb54bbd31330b0be44105
132	1	112	\\x65d9ac6c87b1631dbc8d2684bff6fc6f7cf2893b3eb8413d69561b9f1e778970f5a85b3ee8efb38c2bea7e56af30cad85665d4210e8ae2e24ce82f283eab0f0f
133	1	49	\\xc989f6bc536ae5d40d804b531826df72a17be96993fc7f76328ce9e8e6acf42759e1df0f2c7ab81fcbe3897547e2e40151bb70160cbd436d92ebfba895b0e007
134	1	96	\\x4b174d47f3ab22af7b76279677a3b8822e4bf96a720d07128e84d1ca5a34fba0d9d40d5bd9f2858d35958ce80bf5e3c87d6f3db3e306949185a81cd5665ee10a
135	1	48	\\xa39e6890468a77b36673bdeebdf3b32344aab61d30cf4ad41564967f14da9b230296e25125533dba32d161fbfd97467ba0df04cf8c865dc85dd41bd804011607
136	1	159	\\x897e20c2b153f9e7d1486d1cd500c7376f381b06a92f42ccf320485fc51401d389b259bef4001789de96c81c0812a5415cfcfc3693ee6cc0425452a097e38e0f
137	1	392	\\xe48e5b4789d19b4fd6d5f58b351a7f34e86e7f717d8b6105e4b94f06ffaa1337ef18b7266ca9e37eb2333dcb6768b7943669725193bbf1cbb8212012ab1c2801
138	1	2	\\xe3e68e1c1dce4b7c18c1746a47d996cd05fe113f2f9ee4c7cc11899f8c9108180dc5b4264ee06b8b98a530f64e43b596ac1be429f4500b5bc171533cada74b05
139	1	303	\\x7ca78c349b411c0ebca31575a4fa264eeb2aa9c089708c60e84d7c880f884d27c43397d9dd21e924e6250916b4ada869afed5d3d9848d528117eb37a4d28dc00
140	1	176	\\x54a37f48ea2362b34bf6e242bad50c919d576d9f2e22884bbbb86e09199b8dd22a5d03045753527e9675f093a7314d1a8d1b97d8e9d3a75bc295c6b0e533a504
141	1	241	\\xfb3b47f4df9eedc4480ccc6355f179db6f024f6f08f8a35794024eea8cce2a856b1ca4afd39dbc2e0fa4595640a5faa225b645c6802022806dea6a52da46000e
142	1	393	\\x1f490c9fec3ff868b854796178e46865ffcb57dd7744c49b70212508b3a7c5c92f50814917a2210bd7d5562ff53fc7c5460cb846dbe9444c10714bf19a36f507
143	1	47	\\xdf7143c69a8237c4f55e5d7cbf9e83a5d331e4d83dd484cf85c25bdab2282ede80ab30b17e150e4f3bb61760d8eaab3d2232c3b43fac554f181c3b87ab099f09
144	1	398	\\xb3cdb948fb3ab2cacd3c9ea7594b6d358a5ae9dc6c25341f2a8ea61e0ad345ff42d872caa472cce01a268282202f770fd8740163e14aba78119e75e389ff6203
145	1	217	\\x7103255ac1f2ec9b4056c5aeb55f9c91f7b9eb8e88ab142b90808714840f5687efa8b1bc1df8d2f9c26a7adb29526da320680976f3cab632e7ec7d983926380a
146	1	88	\\xab8b13973667561404713c62f70341ff11e96d9a40f8e25019a7f8a26f35400df8d3e1af5fc3004b88cb1ca799cc74cf44e415ce8a5f32d61e27d238f285de0a
147	1	310	\\x8c83fedba3c57d0c3cff8f1bd88e67385d06446727860c3eeb1c47fef999bcdd8a41a714c8b05151aad27ed3922cbb300c2e3c47765290e5e3a5015b68401b0f
148	1	368	\\xc02145ca21493a5f5de0eb56c190e3ef4c63ff592e8816aa6d35665d3d1bc2dcc71aeb52fac0273c1e086a4cced136535995f60945a751310f545608bee37101
149	1	26	\\xf8e1443ac969b18e4f4c96de285955e8355a180133028d1911a645508dfdb7d93f597b95ca31b22b06b90c3c88a53a13a14bab19e7aafc47d121011dd28e410b
150	1	358	\\x3ae172316c225f9d9f962c1f579e8fb22f8928e42175ea0818c5284dba0c6d9496c0386104f12bdc0cc38d2eb2bdbc9a7b6afc37e18f4529cff7e545c676520b
151	1	167	\\xe9c726d49142c5579024beb9ea7e6ca8afac9e8b01cf7fbb421c988648902f262573a59feadaf8e19363edc4b713b23f3cecc6c0a1ffbd2d0ce80dc786186d02
152	1	36	\\xb5055a87406e96d2e221dd5b7974b13f250cb8eebd3bcb5fee88f7ad78a02f8e718357648e0e9d1837a90af6b3b732cdb7207df4c27eb1d26b29067e3401450d
153	1	5	\\xe207a91d62ae4b31ed702fe1703ca15ab3ad1198dadb30283ece44adb1b30d2663bde8823f5b774040ebeff1f1a0bc7e9e87481d80ced324e4279c0de4aced01
154	1	252	\\xfa857ce4f856d5047d5e27b9010cf9996a840719d1f83eca3fb6651e5dda73b8b0ec19a375e515ebd442cd3aaef96fe28cfa2350ff03c2efcbf7ed3d1c2df10e
155	1	319	\\x1f83a12d3232df90a79d50e1f4451bc2b51c783bd801d633f7a4de59da7f0a330bb450447f127302e00ac32ccd8b541850db2ccd5d60ccfa114b84f87cbdd204
156	1	282	\\x40524d58fedbecbf7341eec26151db8143dfa49f9253a50eb8d3a5096cc5724079d0b65dbca7ff370c8a06a2865e0f4df1bb29c67e4e592421274b1e784e0b02
157	1	53	\\xde8e044f995fde32e3de5ab29ef586921c2d3bab5b1fe37298a426afb5c6776cc563991e9f1fad475f62d8bbb526f827c38b9b1d6edcb65262e074d49c3dff08
158	1	87	\\xc715bea14707f3f9ebd387ea19a45774741b551fb905b9f9e05b8fb75d4e33eb2d98c614f15662bd460cd9ee559cb7432f41cfe645b7808c532832b8bf2fe40f
159	1	200	\\x65b713003e2f70098c490724b7506fb2ff255f6c443b18e539596b241e7670f08d3cd105b12360ca851af2d8c4d30d10102044f337600acb2635dab2f0ffcd02
160	1	213	\\x778e83c3426e5a8ed01721b134e781454313ab56d017b97bb39e9153aee60b51b9540a7fa92485d805851b96dfd14f4d02b3206eccf68c4db5a389290b503004
161	1	122	\\xc71f7272e8195167b3d271959056fb43124118ff0edc879938b5972cd7d304c941742027d24eba49ea21ed8debe723d9dfc147cba03278e0a1ff004ae002d40b
162	1	375	\\x01477eb5d6ec73862fa18cc13aaa8f38550104c3540d27a58369a2dbe351ce1f3ad2aa81d1173784240d7f4060fc7fbb38943cb4b2d0bccbaa74b988a5d13a09
163	1	222	\\x332a2e02b3b79be9fb699c9c14f75f35425b2be08361ebc4272537b36c12e262115118586299346706fe1a04e879ff379fd6ccad37d6cf66ef4c3445fbf98d07
164	1	12	\\x4b657dc1aaece5e5384a88cb1c7461d23b8e3f8525d6f48988aacc7d53d9b9a7c62327e0c2061927fb0ab0015a1465b744db40e44981162c2bd38fe44f955500
165	1	408	\\x87f766fcb0a74cfd4efc021b6e26ae0dacefae260b9f0181ec20008fa52dd3aadfc8050949508fa38862aea3e72b50f4279550bbbb5a9e6307bf5535829ff70f
166	1	75	\\x9cd3cb779c1023b9af70924b70a780ae94c6175862a3344904e9f14b9d6c5fed768079f1424ed28c67c1a36569b5a649dc5e3b2257385931e8d533f7129ae90f
167	1	324	\\x14e18e784bb7af1227f52c280404a173b58cf6a1868fc96f8f0ae0c89fe6d4d56228a48db4fdabcd3ff55e4164a7565681438b545234ef1463589f09cef2970f
168	1	129	\\x8c0ea8ff19e057ea7aaa7c027de286b89feba33301c3b91d6c69eacfd41e918d76af0f09386c4ea7403e7aed229e09778a01f0c46df6c0cdb19b63a3de39fd0e
169	1	409	\\xa225cbc2232dd2293efe45490ba7067ea10d6b306f9730bf154e1051f62e56c07ac2433f0e68a78ed65172501c6f438e618a76663d4a8f71bc77603394f6620c
170	1	165	\\xc12c834bb865d9ad412a570ca2bdca81d594d4ea8982c85c9608ab9968022f2ca6d328ddc2cfb9e539cd964782b2aa40591fb30a27693c67089c6119a879e708
171	1	258	\\x5d4248da63ac48a41eed8f4af99c85c90c8a54b3846e81486be134bc2dafcadd048ca90b932022c77f2bfa5d47e938f4175a477a77044e0126dc410c3233fb07
172	1	334	\\x4ff93214e571a5a02595dc91c61cd9b1fca209e467fac665874f3d55e7d1f72e68516f8c2c8f399a3380c13191c728e98bd6425d1ce9b455ef5a8779aa007103
173	1	120	\\x8da98eea316afcc3301d82b710267e2280ca00988c5f1dff939b26f87c0fd05e8d4199a8682e7fa190d3bd03c7188bafb412a73250ef2fff43c89e365dad6009
174	1	121	\\xe3bc59b35d1b33467386db30c18a7de59adc8b3fd1279975e76c64b3eba15d9c576b48f44b308091d9db8e371009affaa6917569fd963d97ac0149e9a973360b
175	1	134	\\x76c72e02df18f5eda06a42bb30f632e070828c70c03e31df0bce71376301c9a5a3372f021ccbba1f7d81605302e1cd0d874d923261c9f8dacc1d037a724b2a09
176	1	199	\\x717e41e34fa736abc49ff30156aaf8c48c7436b0d6ceca5cc2aa552c3f22f6626a264f85aae6bbb8d8f6a298a037ffcc3bc6c5e78f5e933ffe989dd9169c8204
177	1	231	\\x524f936f48f668feacfea87889a25c281c018943694de5bd34a31a72e5c1e6c3784581b977eced0c5f88bd27ddf6c94c6ec06a802920bcc55b5b56d74baf4e0b
178	1	230	\\x35b149fc7b18f5cfaf7344ac7253f57e36109aeef783a64f71a9160052c0a5853660f9282025ecff75fe091a14b3c8406d634fbe9cb201011fa9dd3c7a64090f
179	1	156	\\x6141f7f1be43ac6b71eddeb47d4beef76d7cb2f624e11fa0e926e3fd2df401e89fd14cefd2038f6b655d65c223aafd3238855514ebdcd04fa5a5dd99efef0d05
180	1	16	\\xf5ecdf8510058f8c4b36806b9356a8a1be695ec720f15a34d8d944a937738f6f51702c837f7096e9cf68de57b4c200f617b9c892778706b95b296ec047dd8b0c
181	1	174	\\x1d54ac8d6603c8c59e3e1111a6984942207267cefdc9ca4db95157fd84c5f5c034be64e24ac0b21a0b24a0ad64cb23745d43782b728d048cc58504070f8d8b01
182	1	211	\\x6ecf253b43909a31fe1841274ff1d59df262e1b4ef165ffd98f955bca99c04eaec050d5974d934dc583a822b3b11e638d3ce7e0259ac13eacc8a715879524b09
183	1	76	\\x8a8e72b3feddced1fcd32fd36de2f27430cd394e6538b6ed6781f80ad4cdbd06b5bbfecf16dfabb5ddc9ec8cd402436be7b51213144904bebed583a9c4c81e0a
184	1	300	\\x3aa9c79a3e5a03e3a40a45bfcc733c2bf5026c16298edfb69487e0ef9f5bb1f1976314bb7905ea13a3e893d2a4b040bd0dadbc98fac8d5b6f6d8e4947eb03903
185	1	78	\\xeab52298e068fb877dee8409b1ea6665f4d20dee396c17ba90d14e51ccbeb3e169fc9f0949949398cecde09f115fcf5f5844ddef8d5d53b5491aa70f1443f005
186	1	290	\\x3e4110d1dbe395d8523288986f733bc07f51b72adb2c104692ecde6dbbb8a8ade33d7249f16732e71cb9af410130cbe9a67bbd10cf95f6892cc166f36012b50e
187	1	114	\\xdb06ba55f1d8c61b7e32d92643683681b157d5ca4e5af069ae8e4a5df8b12d6b978a8aa5b5d8d3f0909578efa741fe0945ad3c71a308ae61ee4528990cc1840c
188	1	405	\\x08c0e48e6876c139879ba967887eb36993436f0cbd8b43b4584020a226909053cbccf3709b03db16835b0a2f7acd2d9b90ad1a9d9fe49de38a14585bd518aa05
189	1	328	\\xe0b95f5369e83c06d0c6d0994008fedd9a48de12120aaa500aefe2fa008d5981d84d964d5060de0e250c7701d6f160aab8dd721acd7cd958d23d9afcd7502a02
190	1	347	\\x609f4a9f542b8789a86a5de65e3a51bcd33447c437d82e9d36c3ffa6caa195e34ac7cdacd7c287ce7e06b5c1a884e54172f577b4b17b4f7ed524e94dc6c6fa09
191	1	191	\\x094b62735856a1e77800f14b1cb36177b77ba04902a45d04a2b9e335036bfcda7213f722e30e226f51969b7156ae62ba3f32f48c47e94fb31f95b57c42c40a05
192	1	184	\\x4971cf0427a02c0f1ce9599c34af686e3042bf812c3a37eee6167428f86a7ec5c0ae2fd8fcdd7f67e6f24768ff7e04ae864c255e14f77404dd3d1db34ab1d602
193	1	373	\\x8d21a55c08f21b84a99098f2b57f533c54906478f2824c10fce824b778968bef9c79dfdd5bc60424be3c5ae1447930061ea532fd658504ac36b2a041844ed90f
194	1	116	\\xd2fce131427646e42d27e57e70577b854f717cff26ce78a2f5d4da0e0d970d9320b2de8dcac910e07ae5aafdaf66af95ca5720ea055aa01a4948b990c146f50a
195	1	337	\\x2b55e84a1728997d81a639b57528dc8d44ea6bebeafb578477d9bff83cf6b7d6b4e51c3e0873c9fd15b61619aec69cd642d0bf635b111c8e885a081c18fa220a
196	1	283	\\x999f9080dca9d02c5bf18a9546e2f8fa2c50b483eefbfbe349fc0b380e44ff41015376fa44e0db86ab5d3ab6c3c2a6b13b7e7053193d0bdbffa9ba504a066c05
197	1	137	\\x8fa1f9498c0de62a827798798da91d666147d52c6d3bb2cff3ca7fd293654951b9fef833475f0a17d397e76ca5b636edc552007aaebad46f763a7be67730110f
198	1	326	\\xa30d639dc9bba4f4fd0194396ba1c560eac81d91f050c837b3a3c80cddbe19251abbf6b4b0a0a7860f90b7cbb26de4f582332c64ad730a2afd25aa2fae45550a
199	1	136	\\x74ff5bf675148336ef481c2c080ef5d2ff1348b6c3fc6048e84224cb3dc7fcc4d0b7cf3aeb25cca6047509e6650fa52e02d1185747106b3bb7e427c67f503607
200	1	197	\\x2ae3d2a0490c7c7475b88d69638fd20bd0a497daa8a20f4577a7705a30e726aa328d3109c8fceb9edaf9d870667622b145bfcc9a7aac7f3dffdc583c1ae93c08
201	1	254	\\x4dd17f4829a0da181454eec37574192dd310b324f23e504c45b0b1fe22fd983faf4395a6551abb64cbb5dd81c2a6933e406ce4f891fed60c95707ced5472010e
202	1	28	\\xec937b05e2c55b4fd905dac7f28ada77477202d41138fea5a19abeb68056835757fe43cb17aaf03bb588033f124f3ba213f7fc3bed2711bd40484c9470d79404
203	1	355	\\x5fb598e41928fa7f2d02aa9da7902b7b1df63ff15f6b339ff515fb677ca92c51061ad6f1e006cdf64787b80282a84149178ac77911352b21a541500a3ed25c0e
204	1	417	\\x34fc5d8e4d634af206974ac8810098034ac9eb234b7a259effeddfe1dad858226ec82528d673a44f940ef345f10e5cec6772aab9e07fc1ba410ed525cafb8308
205	1	352	\\xe101e192fe65cf31f0043a32e89c2fb3c4c31bfd0a7f5abb72fbb045474389b82671548f1adf308404b38f9540a4183accbab9dd7b50f7e1930751a36957ec06
206	1	84	\\xcf487124f53ad87b7f32e0dfd91ff2e05166282b39555da42f573a5dd39eecf6199d9319a1c24c8966096945bff98e71bb2b24b49a150e4442aaec14bbde6e04
207	1	67	\\xf542c12da303bb359406ef5d5689851c1066c74645cc4d5fc2d878a3749ca322a96d5d643817dea4c7d8c14ad4087c6f881a71169c8adbbf6e9a9fe02915cb07
208	1	353	\\x0cc963f533ee375fdd6c0c59ec81ca7c6d4a33235be6ca0d9469a38ba6f50f4a62b738c7ed0cc71263d56d5d920079617865006f3ffcd67d33fb5f9849d7a10d
209	1	110	\\xe7d456827e50e59deda40855b333758b4bc6ea0056ee2998bc358bbd9bdf95ae952830213b48ed1f5f5c0c836fab3d2b4fe18547f55755cea3d0f0739ef5fe08
210	1	80	\\x387379ded10fd0058b5a19927a62cc136983563b0195747d8535ee31f3a2be5c4df12f0b5f5200f481b8582b74c53053007f67f0d92fc9647388cf30bbcfcf00
211	1	301	\\x40e7153c2921bf268c0f68634aaa7761b8027fd17bb56d9330628beef0291bda2fc40b919f23d2117fbccf3680b294df3ab8172c7d660a85585a1e938a542c06
212	1	394	\\x6312b70143e2751e8e9eb899ea2b8ca3f205336e89c76c05facc2ccd59da471f4378da7ff9fa5ad523c39d7cc8c7c3affb5fe771d563f76a15d0b806a62d830d
213	1	236	\\x4e098ba7dd1fad2eb9540f0cc302fe537bb761008e3b84350131e99bb7c8c80e06945ac77ff191a9b5e677aa5a9fe0afb6c903d3edbdd16be5c9db233e048102
214	1	219	\\xf63f1600a53da134d6098e829687f6d0093a2e0c5ca8dd5e4dccfa558b53340c6d56271001f871a1ebf0bc80709f1d49ad1945d0b6183e5c6214529d8e8c6200
215	1	73	\\x508672740219b59a45371550a93fdd7bbdceccf79f4f04be2f5ef94fc3938e3d49db817e9ad52d6d6d1129a0d94f5cbc2d81fce5954b51790c804afd296beb0d
216	1	43	\\xd8113450a25c8f6b53d8beb4df6c52146c1b2ed1617592e76062275585b7f2981ae979508c724fa786aad710dd7ad8e3e340d816f40df844270e5bbd7124140d
217	1	14	\\x66acb9d7a3d77640c167c7a996ce76bc67629b6840c9f5db6608ba302bcfd82a8e9cb689d85fcdcc32d9981c03186e8a68881dfcb1fc80172dc34d80fbb8bb09
218	1	315	\\x149ed376cda2b8321373591428f9d8a570658a1f844d769bae6148d4ae4b8c822e1b11ab26571aa18bbbaee41091057d8292088df49736e037bd3bd86e58ad06
219	1	170	\\x6ef11c962b9f0a4c26002c3b103b089abf4751df5be549f115a03becc9cc6e52cfb8fe2e787f4bc63e91e97d156125e161e7a0f804c49567e69041c153cad007
220	1	295	\\xe6e7c5055596432751beda79fd9ae1dd84912ce139ea85766ea82ca654f4bfe2bf75a4c7407151301499b2da5aebe23bf415100bda777cce58181f9f3cda4205
221	1	348	\\x85e87f96f31a194e73f01ca338f1ce0895c8d1485e8cf720599798ef81b48aab8c6fe3d2f638075b1a91281e6229508a2444d3c63aff4b45898ac868cbfd9806
222	1	182	\\x33eb860b002142f95d569589bbd72e9181d42f77fda2c9525a288ede07a27fc5bf8732b9934a1d579484b732f7b81825b90096bb983f1dd40d7d050053fd800c
223	1	193	\\x13c95a7c58b11612324b4cb78e86a922bc09fffd2f7e6a6ab824771b46a5f2fe8ee6dacce8da0d96c8c0977a279a20773c62fc99ea6e6579ec61766ba1eb550c
224	1	183	\\x0cc27d982c1e0a38d77f667ab65680eb6a984ce1881b16d2814a10da04057ae77f42d0bebb15b723398d5d78152e1a91a41c1f362df02ef5b605dfb0d93f440b
225	1	298	\\xdbc37df70c1e1d74baf2519f80f55de7f6976b5182335d32e49463120e90c35da311718282887069c0a711a3ce23b27c91de32aae2081ec771bdbbef65a45b04
226	1	343	\\xa38e7ebf7043519f29ff769ac5ffdd0aefaf660893e8e24f76f3b5f499bdf43b613d33720ab7ff9e8f2ec9bdfc844ea97596da58f2c647ed0b9e72b5bbc52800
227	1	147	\\x5bc5e73d7c6f51903e8537cb43a5f720ade3d8074a36de53f41cb302230a0c709f05ccc69b9d840c89726208681f12b282e19461dd49a902399b167755800d02
228	1	189	\\xafd32859da4706e374fcd57c8380d35f57d646fc82d2f32ebd514008b171c14726fe2276100cb8a9bb05d12b9093fb09ebea38c6ab4424ae8661911e2c429304
229	1	321	\\x2bf547f7665ea7696c3724c8f9355f02a4399af87f325dc2a2eb278cfd3483a6548edbc9c46384c9ef01197f5d573e5fc6a2296a7810ace10544ecdca2211f07
230	1	395	\\xb6546f2ca0a8dbb64777c2e8a902e7c5396353f56aac8127953ae28c8ffb9a9d729db236cd1e3666e39ccb54538b9f36e492a651ea816ae6965f63fe0c08aa09
231	1	32	\\x003fd402f72eacfac68c6b2fcc084d8a892641a04dae5a12afea18234793aa5ad16866b4e4bde0c303a791ed07bb9ee99bfd9c65ae768ffaa0dc4bf21dfed509
232	1	359	\\xbe5d19e930931e30ab74cc090052d4a8d2888d180494872aecaae6b00e9290360162f54b3a545465f49dbfa05083088074c79ceb6e2355f47fc09edf9df29d08
233	1	218	\\x1b338025be9cd62d982d58eac79c169963c219f9be726e99ca938a4142365db63aec280db38d4a55a2527f372306ef801301cb18d91449b43cbe437a03f4150c
234	1	288	\\x27cb75e2851982ec8e0fb03fde27863fcbb0fdf1ef257f8755d882447320dd00c67b78f4867d250e361cbbe45b74ad5405fe20fc66e776d269da92f7003b9f0f
235	1	380	\\x75dd791c7717d2954fb8081da24cf9fa5d67c36e3d77dc308a5b95df6164642cc342def2f98ce9516474f45bbd4493d8902592bee465727839643e840812210c
236	1	333	\\xcc0fa574049abf3c28bd546068b82a373c796bc1619521943169fc28635a0253644661f8fad925052f80a15c07dabb57a2d21ad5afafa25875d224b63e38c50f
237	1	7	\\x3430231cba567654a8d2bcf8219a58f72285ffd773f95064adfc1a847f1c8fe6c5a4eb50b0bab128aeb854c89b87802a9f6a9285e9380e900b6ba4deb3849b02
238	1	404	\\xd5baec782a8ce9f6156a6dbe9413d60352fcae9db8e7bfdd127e1c38cf0024736a42ecfea601ee9028f33857957abfff21f20e8d10d25fbb1cf776960f5c4b00
239	1	338	\\x531fa716801d446d05e3abfc06934ba4508250a6443b634184fe73bb69e7ca0df40d6f5badd10d057217a5d313b23a1f81de8c7981f6ac329bddf23f83bd6c03
240	1	415	\\x7f43d2472a8f690a0e7a6884cab21f866ec0387e6bc50e00b84a2d550c46d03c57bee1f754ad7793708f49fa5d18aa3afed653a2c0ddf3f2ede586b9d4ecc201
241	1	354	\\x45ef88ab71d20218537b9d54489a76dce10cf5e6469b28e613548c7ea32a25e6a1cdc0b1639d65e6caa7da39106b28eb24fd8a8f6f889cb359beb079daaad104
242	1	196	\\x6c2c0868089a0ba6629ccb1535b4acc503c58658fe4a098f3620059fcafa5985a542a16efeda05190fd1dc92700c67d38f2dfd6cf87075f6597da338d07c0707
243	1	362	\\xa8fa2785baf1757bd6714cbf3070293af4656287b64ad5ce451d148f11d7b9f11ba5c36199af33ab00c46a7abfeaf96b29cfb0d161a84663c22dca179aab0001
244	1	265	\\xcd9b55fd5b29a7390c7190783dd8e5a02c352168ed1b45afa862a9bf0b7b191c839b5e8ff34603619048caf41300eef0c8b321d56ac4e8c843cd81cb8e21ae07
245	1	39	\\xe8d5052e03787f8d65c82ca88004dab960702e1543ed6e659089b81e5ce4f0e91c6054a7412d220b256b1490c05896b2813adca8663929382102f896576e8508
246	1	65	\\x46b6a4885d1e454316c45e653b29e8137d0f350007a1c486e3c3f3fa8bb95b3c2ca215c625256e2fc609c3d1812e9ff7e6dae897c0d8355a8f46bc774eae640e
247	1	341	\\x5eac4f3c8111f672c562f2ff0433a0f1ad92f616492811a5bbb314ed2af65c8eed9b349d0180013e6fd23500d42f3ce0d9aa563050023a8c749d0a2add68ef06
248	1	273	\\xf18a1e0c1b9d31b6e74c036c17c6a351947ea498c4eaad5f2b4f32c11e0c6e2095f8f405e0d3a15e9a2f7d235ac850dcdf91199287dbdf1532897a5138bc730c
249	1	357	\\xcec4dd2d2dcb6abcb1ef1d28104f70ac87791a87df33fb96515d07f93fc0f381321ce8f4ba6b36de005f2396dd7c45a4453ff7dc103ec80820b4dcaa4af46103
250	1	71	\\x0775b09ae06492d4fc70d55238f158f5ff14a17a5c0aacf421e714657132b45b07ccbc057300e2cd5f76f0c3f3578a8ebff8a28a175bfa034d4e15189d056403
251	1	250	\\x42b0a7dc375f1680d1eb5d98cb828ab4d4b2b6399792f79dca6ffa760b8b29d5662a1c69248f1ade5f91869d589ebd642ebd8180ac9e2bb4bf25ecdfef33a80e
252	1	400	\\xe2043566749783adda5b6e5b8180957b6fe99c417a40765c8ddf5cdfed19aee0d5d1b2508880503ce3ccba84ba2389ef423a99dbc406ac911898f2eba33cac0f
253	1	70	\\xf9d293dfdd05b73365c3d0897107c76641d6fcf6834552330ec2b80aa7bf56ba454cdea87fbc56855ad962034af18def24a16663b623d94fedee3dd4eb5aa304
254	1	74	\\x013b199ef55a1bbda9ba26474e804f1212cd17c0ba81035fb1bc5271da9b6ee95f8906e9d059f2cd4cef7a5a74c2d231c2b1af5168714ccc883c11f4231c5805
255	1	201	\\x0df9ef9700eb868f3910fe95d4d5591d956013b335662f47ec29807f9c7cfc7c4910898cff8ac1360a5e742f1d13b3e9b5fccbdb5c9e2e8738235fedf15e740f
256	1	195	\\x6bd7312f5ad50e99dbdff2b4dddf7acdd7706bc85c650db558c3f2e0966e643cd937347f1d4bb7a43802aed5023f32f27cc3edbe54fe9f8bf24d549d6e845009
257	1	172	\\xacdf6930eeb58302a4cf6b1242f9ac4d5b49ee41bc211c8d1220e89d2896ab8681131bf30b633fb00b562f8e50a6a7bba0d10400e9363943b9261075ab28d505
258	1	143	\\xe046741eac99e8a6bc6a41f49b4dde02fa63af4e3a47a1c7c0d5dbaae28ee575460149f3814e1ee1e199b728e6c5a3d871e440539a91ecad92ac3d9fbd285c0c
259	1	299	\\x47ca68c379f7a178b38075d8c4c6de80624493ae337821549c67fbb56a6ea5fefcb2ffe0b2914ba7b22c953177a1c53f778c0ec9856bd652cc7a0634cb953201
260	1	379	\\x445f1524e244b3d8ac6231d6e2a675b70742165da1e5f29b8f964e5643ff6fc69a3f2354eb9a2c7de3c0535fe54c003d4c2da0bd63cae991be6286814bb8b00e
261	1	407	\\xf1d9acdac23270be8bbf6dfe2f9fe96664395ff7d26439aaee8b52d68ad021044dabae78bf6561e0ccf125a3dbdf88bfea06b3c8739893212ab8e045c391d80a
262	1	233	\\x491a8978a5a947ee9d93c409142697018ca9b844c40d26c480d4c12e175dcf2dff1411fa3ade673408ac9e2b4663bcd2d568d335215e8abffb3b2960c959520d
263	1	388	\\xb6c1c0ae6efecba154420a4575d253c07197143cbf65bbb5971c8abde530a123d1f9b4e29f022965672b06935f713fb48380bd6b914557893b53dd88cdd92d0b
264	1	52	\\x475da7b99ff3dd59ff5eb010d0f4e23b2417b263aa8415680cabdc7ac70dfaeaf7f80bc593d027cc8af6cb8b9284accaf2341fd9fea5d8136a1b1243094da403
265	1	297	\\xf5b00400c36916f773d98615ede3c9a168655fc9b2f1375e88204263ab2402d418984f14dd6e0c9bf6e08d21b6a6d7fa58c0a6d859f239a84cfb87924c582905
266	1	81	\\xe74479dce951e7be6312322bdafa1645068cc5b442deb5c7b7a57f6c6871b69cc67b8e01f50e16c546d80a6e0e056aaf2814f633337006a8cf123fd87f96800b
267	1	209	\\xf184e92c43c023ef1304dbd8fde2154623115d16faeca936cee02327f6b121f847ab992da453d6c6adf27b864c1d89c4b978aaff23650f78bc8b8049527a5b0c
268	1	411	\\x0487e059b99f5a05ec697e9990eee5a42cfc955e751106ec16ae5fb9f25831e4bedd49cde29ce5f051fe3054dd50f59e78de37cc96010c2a1a6afbd6e335dd03
269	1	397	\\xe8ae8e2d44c7cd188b637f4aeaaaa4d82abb306b8ff8c095ac3384ca64bf03ab601cacf3878d8b69ca4e05e4cb4e54bb482431703f450abcd102d6fd0347ab0a
270	1	69	\\xecc366845bb77b3654f21c84b6f3bdf11db512297e18a601f7fa27b797f416ee696aafc7089d01c81c680b46ea7b8b1aede10ebbaec3044bf32c6d44fbb44b06
271	1	15	\\xc41d91d91570ce7936574ba379f357d9a592976961155c97d1abb1a8e42facb73f64e949f3decae0d8d2c09b7b2f19bf94450c6736cb88eb607d32ff3c7f8303
272	1	335	\\xecd40f518385b4877d1a4a09809719d11872c557ef186298e39eec3f65fbe25bdabac095d04982d5104dd54ce5aa37675da031fe0d9baad9fc21ac6e70b6770d
273	1	376	\\x339452799e59f4011d554629769618c359fa757a2b24d0f96a2c6feb42ec957e8de2846a48a54a20189816a4a194142c4ee60ce94486a4f947b989ed11c41008
274	1	245	\\x75cfdb83fb6d04a55045bd2cdbd05d1cf7ff47f9c75ea9eb4637ecb24a1602d4e3a8255831a5f7a9a1f393f7e24a03953a4045c7807acf20ff09b2941e159700
275	1	68	\\x99564fc12b038e819bd79b245f6975c15c78bf2525f02dddeeb3140f7842f7b34d014aee45f5f7d8207e555c9b73e09ea9b51a1173a2fa26a8a14a4160a20802
276	1	23	\\xc0aed5bb2e6fa6935d3c11d85bae625aa27d7bd8b341fa209932712c5dd6c8b264b05d7f2f7b5a4f4287eb828006d6b0f40e59b3785143f175dd0d3e812eb60e
277	1	97	\\x2c83d41a3ce42bd98058c21d9c7eb548e10981c9a73b6cb8d105a3ad0c7240adf0a3cca8fdc493aad3e4148988c90671c547967e78688752c1289e9d3194700f
278	1	99	\\xa6f51f0d82b2189bbc79f868a30a3db6186b61e5e34c6d5ab9f56e3ea3674f97d336bd2d40a13cbbfb5cc746411f9995ad5565b00c00a157c35c984d5c2f9d05
279	1	403	\\xc57e93e09e464627aaa289eec26e4a8a1ed8ddc15fbbaa8e3ec7eb3bfa18e2d4accf85121d12e3b64a04bd9e08e93bdeb99e3bed3db105f67c71cef57106200b
280	1	342	\\xa8c1544e36eca17473aaa833deae4e05f97609a4a290f77d4b78262fba73e600b26f0c5f5ffdbecda87ef434c686aa358cb92f31c310a5f94e7252786f455105
281	1	100	\\x79993a8377db99c62658a3594bd57087d12445e0b21363a13d01a0bbf97673939252106ff42a48b5b0adfdf19ecf17efa20ea7234052cbc74be8e2c133ff1003
282	1	312	\\x5c9b0abb96dbd9be0fb649ff9a282d082b7b04155ef8014cf793b7f73dcca9cec7f0352f2ee86b7eb9922d0afeef3cb21631b4ef3a3df381c3756490a174fc08
283	1	123	\\x92373cb1afd53507327e6191997b10298c7f2acd6cbc237c363ddba6cb11dcf94d326bf2cbb46386bb407ba517c32f7ac0173b81f09c40d172ab17858f89cf0e
284	1	421	\\x4c0e2b8442331dbbe36f93ba5e231c165ec81046c78d9cd01ce4d21c699b9816e776b98a9a819a7954a1a29763d2332b75bfe880a90c569927d8b2b52322060b
285	1	286	\\xed302a8dd78a618e550459885ffe88b810e260be09a59f260c87bd9b763bc9c4e43ab441608ba935e6fcbb21b8d3cca34aba9dea917ba9acb65885541c28b10f
286	1	255	\\xc481c10389e613820a09236a72cb86a4667cd44eeac332d17213099688d74c4e9eec98fee3740f64ae5ffa5c0db9b4fedcb8d74704e1160a3f47b26b770bb40b
287	1	51	\\x5be728408b0cbf58f299bb57022ef3072587ce608c57a47a9d89eed1bb6f10f11b5860f47c536245b6cd381c728489fae9fea7648a62e5af640c280decdf660c
288	1	95	\\x65779e9a9eaa970dee18ca06d283575e8018ab2ea20f94dc132a09384562a82521d0ad6479ea0fcf32b397be7b781b4ab87208409f1201393e863cd8850c2401
289	1	270	\\x618d5894340dc00e9393adfdc5a84781d957db5a2dea2b5fcace8bf35fad0666bee7513febd9c7724cc11fbe4e4f903dfab0785a0b8cc9049f042704c9dab607
290	1	266	\\xb65125466ca85e4198bcd72ce1a1a98b13383857ec448be0acd9746355ae9e16ac740360027d45ee921f89b0f415b47abcccf7c80a506725d76fd2e2c64f760e
291	1	92	\\x4dc4cb64ef73fca2d9703c5365a39629b5bcd6e97dc8a27f970ed9dcfd4d842b974e9dec11afbb7725109f7311d5ad7dcdc4d785c90318a568ce6086d1627e08
292	1	145	\\x5b5a5d1a4f118f2e5269b90190a03c412a90a8ff335dea74c68deba3b93230e92ef6825363252135c02f6a317690d948919585ae3c50639e6e9b6cfe86c2e200
293	1	25	\\x347685bed3c228800e9787ecfdc65987327ee4ee7f34fa64beb31acdca504eef2677d93769b2e6c6586475cd52f005d454aefc34a77e87390c2fefc84257ad06
294	1	285	\\x133d984f01d3bdb0587af5203f2abc73c74347871cd3a09920b126eefe6461c39a73d3af6c90abcf52a6f3e773a294b7ed81699c1bb224244fe34363c348f608
295	1	406	\\x580c4d0c7881aeec6c12ee4f3983231027194dc87d215d8f3394c68e843f922c4fc14db0d8cfed7581b99e361736ac695a11a58f82493429af8062b6ef3aea09
296	1	234	\\x0bc5cc2d9c74d254c3c00cf4173a7a3fbde9a9cc93d8aff39bbe70a6584219638b812be378c3c1b8395bdc7cf6e6075dc07783160d6f0cf29f22da1cc0d11e03
297	1	242	\\xa540bb498f6c30a8f03487dbf3a9dcf3ba3e0d03b411a680e9cb12d2e068de21514f268a930e1dae0873877ea0045c1a59eb3b6f00580c74d3b9b60007418505
298	1	278	\\xb229459e3cb4576c1c43b6109fc6a5c9147d877022c78e56e8a88b513fce51a8adaf115fd235c74fe7a0ebb47737c41387b1f0d72b86d918464a0499e42f7807
299	1	38	\\xc8a1001ea493e6006425e1821ac09abbfcde8c1b10a898725059ba6a17f08bebd3f77b2f7cec214f86715ed651facdab895118c2fce8a999fa0ac9cc153d0006
300	1	365	\\x28fc045ee1f0b77a1b8e6bcbc111ba81f93a9134c2f461730a460cbaa2f76f48f118796c8a74eb0ad6f99875acf0d80a5412873dc75eacc31a76c05f97e0800f
301	1	6	\\xdf06f8f4ecea346bf109fb1bf0eabb586f0503fc490cd99bc697326004f89402c78a8a17a5a64a3b334a5584ad5bf78f296510a9bce2a743c399bbdd81703108
302	1	109	\\x949b0ad8ef419909b74c5515be7fd8c362a1c62bba5ee91e8adfcecfbe6baf0a48e2ed7fbf2eb5e18e14d36eb42d153772497bb73e90aa0c5c7784c6f441140b
303	1	54	\\x42f40dc7e0a0629967f5e48b76c720ebcbb39725d4b06558b75f8a1281956d15cf9aa36bec931b1baed16fb2c78a5b7a0a4d01c13b00d28314a05419bed5830c
304	1	206	\\xf8856cd13e6831eaf5a035f9af808ca313003325eabd09b0b789fea7c349e7c9747a34931950e21bd7480a2b128fff8afcce05e7fc4ced58f5bc0e65c1841703
305	1	198	\\x07bd273d5ea81a8d9ea64ed8430b85d55bd1e087820d320c57ab2241c2ac4afaffcffed4e5dfe81f3f38c23d15dad626ca339c9168ef9dcdce5624a52378a303
306	1	304	\\x441e1d081806a71f8ff20e9fc6140c6430fd8555cdc680b30fe63a374cb248465f0f12986b1c43d65e8d26c82031b7b21e13374c955ab707cfa9a8fe5547c30c
307	1	153	\\x42c3fd2fac4cceaf8866feb3e3dbfce79ccc2252b56e7b063590f8136ab4c7994f0693d6ef7e6da2b42c269a7294c57704a43591f9c2aa347d2c4b320fa21c05
308	1	33	\\xea250f8dfda8e42cf211ebf4c80c1cf0d0bf98917f41b24ff22e7c274bb914c3f2b1a1736718971b3aceb2daca464fafea1c1697647780d009ff957d3fc0460f
309	1	192	\\xe1d1214c5449e8ab211e7da482a7df48e349083fe6aa3e78f523e6012817b8a94e04555c8c57c39b606415ef3514f0adcbab16225bf83ccffb961e5b72e21309
310	1	205	\\xa4c490a1bb62879ed0b914aad83e99425412fd6081294b80512536ac455c093f359323df049deb225d703c1fc84b573cbe48442b38b5425a2872338e3ee66d0e
311	1	173	\\x611d356c17287d0bb677afae024755da5224f053305b3fe20a1e1420802e22955cc54476c2338e3724a47f70766b869169b3651981172a4cfdc2cbefd944870f
312	1	118	\\x431b586b8c03aadaa651354a77317e708a6b8276df84b4ea39c1f0e47b765e32fe967b5f2d9b993f2cafff7f18cf167974fb03bc54bb64c50bb6f71cf588140f
313	1	132	\\x70110d572d25cae0bd1492da7073e97fd1584b55e9403933b429a42bbe5a51409c0e7f5f89229f4c5464ab07a48c8076c4ac235277b1fdab41f489edd5126006
314	1	294	\\x32e509c0f490aec4c4f36e606033c177d8d64c7fae3fd2cc73e9b80e198157b691ea1b53ba7d6de23d6dc0b59e477311e39541da5ac890877724f8970ddab90d
315	1	9	\\x2a0761e5131303dd9ca8a0057ead742f4843a0896366b43f6fa78b71e9af7ec77406b07d96e8b63a988487a0526f7b3d6454f494542be6f7553612db5f16610c
316	1	413	\\x9e6bde11fe3b6274dba4e7f14625f23a2ac6d77eccfed1cf199870f8e450752994542e3a1e4d1c5384b7df1143e1e4965a8a7413ee2205611df127305255030c
317	1	220	\\xe3c3a73af0291e49d0629cd6b1fe5c0de7e4ad64a65ae767bc101414829d0d84377b4ce9050b2fd338773728f7c2779819cd37d1994da49c68093c9ff2701d0d
318	1	119	\\xd3d72eb0b327765cc2dacbaacba2763364724134d6b5e8404cfe26eaefff30c47a8a462470f4db7940d63766552aeecfe1b796332dd3f283c43bd2e4a0ec4304
319	1	317	\\x6c53434c8ecacb7280e30867c8354e8a0294812b6e7ca0db7c6f7190beccc9158327cfeb078f5a17108668bb5338e91910fbe71ab88742055664796ff42e5d0d
320	1	1	\\x2b43e6425f1f313c7f4c7c481b33f7ee8a42f9fd50149d18c5817a544fb0de37e39acce746618163cdfbae5eff2117398a9b63eaaf90526b95d2c7ff644c7009
321	1	135	\\xd42eb35ce698614327486b26804395dcc15aadbbc2ff48042dbbf0409c72335b6743e5e72f1b9bb42de316ff1a2d0aa37d59cb29ec2b659e9f6baa1a20919506
322	1	140	\\xd7a56b71de5a94295916bac577488ad0dc9fa058e3ef7642e639cbafd5100dd6060548efacb1937903d0e0360f4c53ea2c5ac729b75bf944d2c962f895353403
323	1	175	\\xd8b9a39e7b97db780d44863e9b553c6746b1b2225fb9dabe7865d691d5b87d006b9efb912dbfff7ceda824f1e052f82b27d35a33d0a6e46b02ab65c05da2090d
324	1	361	\\x725bbc37d7fe69b361ebfcc6519760b26952790bcb3ed8d3581f84bee59fcc75ccee2d347ea4280473d1ccb980ece1c8a3502f3e26b9298e8f36bd867a83600a
325	1	113	\\x7b34b9048d2b4788dfe3d349b2048967c5a70ad3e26136003b37e369bee4850f5df25f11411562cee929ef8c5491244fb31bce76fcfdffc838b9764f593a3a00
326	1	10	\\x4528ca387528194269ed722b8444075a38191cf3e6e80d9817147352f840a01ee1b3874dc16eb3f21e656bb822f8a71608d55602e6ab229c8949b9e71b895e00
327	1	389	\\x041e0ba9d51a9f1ccfe5e296400054e7228c3203742f4cd43b46841285a8ee895bb6f8644f564aa7ad99eb22bddc0316486be018ffd371373fda3098f0bf6908
328	1	366	\\x55090747e0e48571f5cf891101ef20f3a489e8869af68c14cc03618fd32b98dc390f6afdc686af6915d39cdff9224b4d00aba3408193cc5b79b7e4c980771508
329	1	322	\\xe715b3680de7ce31d115e2a12bc6689fc780ecb53564af79acfbb4635ffe3956bdad4639d3f4deb84af36a45ab8199c8a930212152606bbdbc4b41d1b115e20e
330	1	235	\\xcde9d327cd23cce7b3b7fe86fb9f1212a4bbf453f87b17d47abc253f51c737016a1f0a950d960edb4ba607fb66b14d36c95db9535ccd1e59ea81769fa1a66806
331	1	148	\\xdf957386bbc6ad19f58398415649c00e6ce452c741376fdb001beebde760ccf2b6ac467be0e3c2183dd8904dc0ec2ffc007782e2bca9c8d6bf2b4d2425650802
332	1	169	\\x627a73eb2efbd2d74a1a03c196a09353e7ca70439e314099debe445e9b40ebb2ea9cc02415f73e8cf8d613899a91f0b9547678a91fc817bce15a511efe386f09
333	1	13	\\xb26c7059229ee8358d9651fbba316436d917637aac162ac26dc5f2f0999b11f99bc0ba92fbfdc96c1fe8d0a75d8fc5e5677f7ffbfe14409a67931b515cf25d06
334	1	381	\\x69c0ddb0a4d0e1775511b357cb5f6c845a08f17c4b889cb14c082420c5a52c4b622be65825c078e96ddded2eff6be20b519bf1978135d6788293a4bf24095807
335	1	269	\\xd326f4f3338cef6a75269ee00d22c8fab4783f18590bab36e62101425a428ad4142557c4699a15f516541f1a100e2bc781182561e94daf239fc9be53df4a1108
336	1	152	\\x7f41910667b8b5105d247eeb8680357c40234b3c737ed14b6674c4f36faf07e26284b251ef788ac0be35c4c0fbbee9599e061e46aa666b3c769fa5cf13f44206
337	1	372	\\x300cc4d654f3da7b3e5a0321c27fe7f22ffba0b44111e0919c957ef1a8aabe2c5249568a2c050f0b2401442e6a198240722dd067d1ff1dce9ec633e5560f530f
338	1	246	\\xc2657653589b1eca0f5a6b4c5332ebeb2a3fa3007e12c76d5c16a066ec0d5aeb352b5196ff11fe477b078403805756290e16cb4580bc8fed8dd1d5afccba330a
339	1	420	\\x5adea015fab58b0f36b5f908f97f0b687217145f036734b5c2f6aabf2615bec6e132a6d96e38af429ff9d137a2e62d91e1a2f17fc3338fbf8dfaadfd7762a607
340	1	21	\\x704f44cbda3f255a484d8e1ff71347f1367e301e372b9cf940208f22fe2fcd1b5d242824eefc14f3f2a5032b71d28f5ca3bfc465b38c9020d7eb6216d7692509
341	1	306	\\x7dc1cabd9fe87d25dfda361ca7341e6b5fd8b0e88582448497fea69443f9e4d2cd151e6d21f8781b4540de9a19350cfa84cc6d231c7f15db4339ad88f0749903
342	1	216	\\xfeb59e5843354d77d069c5acf7a72aff8022882acdc16f41fce09690f9ca733b2157f6e5982fdecbcdda396d206b326a4061783e12ee17184a43f659b2e08506
343	1	316	\\x49bcdb6290dc417cc88465245bdb94e4529de81372678835515cd4d24648f512a7d44daa257ae069b1bc58539d52da93a058104638d1d9277c7e3888168ef201
344	1	391	\\x17a403b809163b834ef2c15bbd7df563fdabce564b015e26e2ab5a379aac776d8319949ef311a91a64cc31d90b4e3046e46493aa4e74d52e6dc1ff41a8f51101
345	1	225	\\xbf88a9be1cef7c35dae4f3238d5fed09d962284e2954e61c79d6ec3cba08b8eaf2fb1efa476014d5f0f22ead27a592ac846f2dac2b82b007506baa8d28206904
346	1	307	\\x8adb1379f8ce6d04a8f12d4628c8d71cf9e941b41fd07ad227e2140e2564b4299af645a6255fa791247d864a7729c9b094a714bedf35aaaeb7b3afe134d84a0e
347	1	383	\\xad8fea011b716ce94033baafa1966c945821c6e636d8e5bdf09965f3e0f690c5c6e638ce6a7a8e44725e9631d6ce1392970976b04b73414eae4f2019c7dd410f
348	1	166	\\xa1b238726276db995db6fbdb5b4552925242688279c440aeae567319b508459b2531974ac46431d4e744d5ff26652dc83df6d9c92ac0d3a0fe823fc41baa6505
349	1	323	\\xdb7d44d5cd1fa72676c86ab64058d97f95911e4a7d8a6e269fe39e2b22e62579e08d696e7631b287518b66e9ac1f55fece77a2f4f3766414dc96fa3f7044680b
350	1	89	\\xaaff0fd500aeb178ad8128db19a660b90ede1d3c930b9923566124fc35d4668532cd5731f6023ee5903936b20ac569ff705249891cad7f7d9a54416e81ab0100
351	1	239	\\x30a42d1aa0da396b328a2977d478c8eaa413fbad53530143a7b3b1e77e68776682fb0b3a73f038de3c85a8ec365bd54cf72e96212afe31d78a61c40dc1a8bd04
352	1	272	\\x39ff64566777587b8d9dce52214cbf592482afde3a3579f69cddfc95952fe530daf09bf8c2dd180b1c65d87d6456e4c82b46f5cd9974de55a9e276095f70a501
353	1	416	\\xff4aa3f260ffccc1b47774c4c0491dc5a0ea3c440320987c2816aa0805278dbbcdffdd40ab0c49d006a34bf2a07d164c2d751e59d8607e9bcf8a018e8f56cf0e
354	1	423	\\x3310a32cf7591f9e0077b9e6145a1dfef21adbc2e66e8030f5af991aaf3ac32ad59e726907c796968f7dc4763d742c48dd4ec76b53fd6f031dda938877396c04
355	1	339	\\xc884c3c79d116d96efa3ff4878793bd8be57f64d2905e36cda2418b96739431fede5ea09267e74d71b4f40a85155ac8538e99163dcb5bfe6428823221302dd04
356	1	243	\\x04c93458ca3d3c4e81df940ab1998db00982a96998dc727d9b8d4edd39394972967cbea5aea4301f95c2ebbb34668899a8abe371da99d790e740b11b17fab702
357	1	302	\\x6b5c0f02494bc93e2bfa77d80b1607c79b326521accf3ebf1655d9b4689b660c6f1133206fa11ca2bd1cb0d7773c6a22c1ce83933691d4cbe600bee56732b505
358	1	422	\\x85547bc35286413f2b62ff0b921c7651a5a22f5908f5a0b0f8e3c4a79a410ea96d44c37c870a792accbff3c33d40ca5ae073dfefa4421c2445116335ea1be80d
359	1	179	\\xe67898dc589c708e75e04c5d4bd67285bdc2c81b62df22d9473e23125c49f4769bfc49a09723f38e822c04515e4c7401e0822caf8b0ead08105ed0a5147d250a
360	1	410	\\x5e1dc48d01f1b83ba842de967333438953eff340270b51adaa41844487b0c467b03701de66edccbdbe244fe583d011a69b365425d6b5ae993efabbee49f2560a
361	1	382	\\x5fdd4180020f6e5ab60b40fd3d829fd199a1d00e9a70a1b6ef3c968a22f9c9a2720de7110e7ed5d8e0076ed9ca78c550a86b8c5e64bc8b5761c35e20c49f6803
362	1	346	\\x687e6e325795ab509d84c77a10b9f42ddc7a6ee51871f87ecb64e5481c9e1d379368d38af83a9c5bc3a01833010ed3f92bb5f7b847cc96241e26ab6565ee6600
363	1	18	\\x95b45248da499a92426da3fd8e4ef7807011861c5710e37a348360be36e6478b588a237d55c7d85c95bca7c3487a615d02149a9f612cafe018405b53479d300c
364	1	281	\\xd515ca46b88737a381476bca58e37ef9f7a6859b67379fab7ac4ebca5f3da9b415239169786d86fc42966c42cb10566d6b212ef82ed903aeba15f6f6c44ed600
365	1	31	\\xe55172f49acc49c3cb0c9ebf1b5cdee28106458ed4809680fd5776b8e86e832643ee71d0f8497e758fb34a0757ef769f15849adba6fcfd48b6c46fdb818d6004
366	1	292	\\x51c941207a53d9b0c521a8642a98c17f04b53a3bacbbdc9473595124330fab11cdd1196d99d40f4aeb4c687062c6cb4c5e37fbf81b67b3f7824bd57188538f02
367	1	256	\\x5db4b8487a922040d408639f444eead9600395819a35e2261780567d71fcb4a361b825eb7546f492847420122b42f1f1c82558509ca5f4ee8df26b87f02d1b0d
368	1	59	\\xa21d9cea53cb62ce7b7d11c20f42808ec0f0807c91bb28745d9d0b4e69d6379c1446d50f3be8ae54f079b26e60dc627607c3e9e501fd4127ab86e6e042c68d04
369	1	340	\\x7abf40e1db782269b71b4cc5157eaa8359188a09f3e04dec291ad108aefd7d731df13af7a91dbbe35255435aa476b601fa5619a83d00eaedfab45b36fa3a0e02
370	1	224	\\x5297ed6f83979eb050986a08d83ace13cb4f2ce7f49912782798c5dc88e5af77bc0934533ca39e60b07f532f3210269a3c2cfeca7098fa2281c2a9ae0aa39106
371	1	162	\\x0ba6bab5b3067705655f85a4d13b8024d4efdb257d0a3507b0abce62b5ee9277236d4b8a6acad480b5a64d68f499cbbc6ff910d9e726be556fa21564479f720c
372	1	20	\\x0e4cda6d544eece9d6f9257ece240c6812b50b40668902767573194bcfde23d21fb49d5468bef9af1a967ac3403e80afaf0b7825ce84dea75d0181552e2b9608
373	1	149	\\x0f849f73f50dea7801c5f98b8cf5189f8ca1f8de206b60009c19da157e3d4c8e5ff081c0c0fe12b4065f3c0401450d7f57c61723955915a57b2ef3d8e63c1101
374	1	181	\\x16330f51da08978e5f8fff3f83e300a40c5b534ddc9681c547cc1cf4b7b2b29d951b422d1e437ad31e7f2b0cd6f69aa6b8567c2428f564d46ac01fbab3344d07
375	1	17	\\x4bac71371664f04f5fe3fd8bb54f8ab6a17c79d8aea09ad74f9282c56fd3807ce4d0e52118644188805542bb7365667321465b7d2d2bc4be9301da4d5c7d5f05
376	1	279	\\x03045d937edaa1dff34b8ad233716cb51f7d0522f094f6921e3e62f31bf807dbe3d0333401b69cd55b42b5223ceb625eb8f4cff8478ea1d7ae9a49b87baef00d
377	1	264	\\xeccb0bf07dab3730436a5195b7403b1713196b56f4af3c9b3c0c787718bc7b830330899907621459d95326fa22ee3eeb10f7d2b205aeb465ebf84b7d806c050c
378	1	150	\\x13912c5d5651a273fb31919b24767e9f902bc3049f35ae2b449dd67b3d860e6548ab3ea92d3750bbaf34a4b73facf99d830b4f57b031b15b5412d31868dc2d02
379	1	215	\\x85b374749c8e075731a9542582ef66d6d9b761397ff2d9eec6c676bcc89fb16610a08ab7222d1fc9673b5da76baa34e0c138c850588a7099b46d5a45b7970d03
380	1	371	\\x3745db2b115e1610e6ccd1d3fd8da8a1b6dce7718390066641fd8461e10ae7ebd156689476c966f0fe57feb3ccfacc3f8c3663b9b81797f73ef09e0d1d73240d
381	1	130	\\xae3204214cd8ce33fd44e4de64f31e28a1aa1fa87d8345b7a73e31c4c2c22983df47186160804e587898bb751b7be4def6215fb2fce8d8207b4c5afc20290c09
382	1	111	\\x0d79478e07bcae68489d796f73943656668847375c74918b0fa916782e4c0fb2c67c3e7a20ff5e055796c0afe2b94ee8086767d32f9eeb953350d48f58698102
383	1	369	\\x158d39f39fc4057a3bd887ebb7ae9044f34ddacc486c9708a9c75a6a998c3e57dc3783f0b95c3577c55f59d8ce8abc0259c3ba25f00f4bb9070e5820260af00b
384	1	414	\\xbc2efdcb8a1e08b9bb40b4298b05add8d41161947f136ca979854932db35a07fd61f79cd372ef6c2ce1588dca85aa7e99d7e811f23330432ec9df334c944590e
385	1	212	\\xccd6500baa6e4844ec4fdbfe3e2560ed3405ad9dc0727f93f6dd5780b203e07abd963db3724151d1ad366218551da5d767b0100468ace0642d011fc7e05f3702
386	1	276	\\xa1751a1c3af6db55406005b87333721c63a4f3eed09c57bd27632d1252a1cc76df62c60dbed36e71b72f789b30297167f86e62e71bbfa4c942af5f4e205ef309
387	1	274	\\xa956209fa292187cd127294cf408a86fc0795bea803e88481cd3234755f4dd3b5c6aedd664a069af0efb9bf64805bfd41b45a4f44bc610f87b70050c2fb4190a
388	1	154	\\xa828b5d1cda5523619a252889c81f274bea29035bce2df281ab4ec5e5f41bf1d2d63ca05ffbbeb037ab98792592384077e9955973e0706ff0afab05e60cbf30c
389	1	144	\\xe3f200fc7d242f9439324e9600249012e4e74b6b7fe1dbb8dfdcd47579996d0729af3d758ebd30866bae0cc87bc58e2a48d80ffa61c1664875fab4fae869c50f
390	1	387	\\xaab04603b3b593b40a94a023eb72e3f868aee8a90576a200145f60955bc4401961ea84385e22f0aae31f485cccb1b2af189581c1a5e93b046f75a500624aa10a
391	1	35	\\x5b87f581e4a4f0e196a154c85dd0f9b701a62ced09838b6289da466426a7b3d0eab29500c3979195637273211c06381b92ba9f77113bbcfc36ffc358c15ca103
392	1	102	\\xe9dc6b6b5d4bc6e42bf02d83b44c637c1933cdae415550981362874437be648ed248c500693f420692f211cf3b8dbd520292caf58a151fc91b78ea945be78d07
393	1	91	\\xfca6a12b277c32a429baefa38a9f1732a1b7ddf1141de9401ca43bcb791f03008c1153e6db88b94c97dfc1ea02064ce00e187f5fb1ae0345459f7310fe48ad0e
394	1	30	\\xac533caab94db882a97f92da02c495e2637f86d24152ee7b40afa92f502450d57b21acedaf8ab57aea6a40ef0a6a9fb5f5badadd431246f3b24d85aed5eaf50e
395	1	345	\\xc3e26434f092f9cc9c6c82ed6c57061a8e04aa8d808efa418e855fd0459fbe1740671c385799a7693c25fe06a0ad48e2954531fc56b659058fd4cedc7760870d
396	1	63	\\x33a0ca3a56904a84eb8ce784a3ebad540df04b6d645992eb9cd6fdef297f05d4148403266de144dacd01f624f4a777ba3af6f0c5c08790f51b07fd57d7fbe902
397	1	284	\\xe59eb30a0589b6fe7049671a42fb5c4701a4b692d3a9b34b4b8e04f7b48fa95441d448dbe894f617f335b6635a49467fbb39a28d553cdd5f62f857c997994909
398	1	344	\\x99b6fe1ea5297e02a836dd6d1cfa0c601de1c52f93d2a8ee6bd48dbede8c2eb5c22ea07fa1df55333d0755fd3ac9fb121e4820e590905ae463678ae8b4c99700
399	1	351	\\xd64d9ea270f285d3fb65cddceef9f383ad8c03ef187f7c7f62c99c31b782fbce9ddb30a32af97a716f44e1af81cdbc5e1431cfeacc8247cccac40d348d463305
400	1	187	\\x12e339643c60dc21299014606fbd6d7da538deb25035a421af5aefc0a48022e8d5716047c456b5ba3253cf1eee5526e4bcc066ce7687f6496b07fe61a992fb00
401	1	8	\\xc27836531f81e487a8857cb70d6d28ec1163bc60d5e8583138a5bfb9ccfce6eff72f5d1a175bbd735f7d64efc79c9f5db361abbc429debcff0022ea36ade360d
402	1	11	\\xb246509e2a9498724fb5249f9807560315c98bfebe2c737309798ada49403cd312af2e912f4aaabdff47854dcd1da58b1dd80ff086c2ad8e299c23b6b540640f
403	1	44	\\x642d320e775e509a4732c3ae4ceb5000ba1db919e9656dab9d7e86cf5b2d6d156c4e37450f4a66d6b85f6e66591b3ab21f8988e85bf9d74390a96b9e5b75eb02
404	1	82	\\x583b0f9e5009a99d79c7ba91ecfa265352c3ae2228dcb994d53945080f65fe70a4e9e5c27611a5cb8d38b3d5f6ce894e05266b3fb698b1f7ceb12188fa261d04
405	1	94	\\x614176a432e96fd52456498c3fb31a69c6d4be4c8f011bcf5e25b91cc8b4f92addbd28f3f474d25433d6c991ef58f8e2a6f2f0bffd62e416a3e33dacbe77970a
406	1	327	\\x344fd5b103d02e7421d9df401b0e5d8026c650bf2609173bb817fd4e6b5aaa4bba2d43811d4ece7fe0f7336decd8c4bc977255083b63a4aab4a51e343a1afb00
407	1	160	\\x9211fbf90be69e951e40a73e5435917ccb6107b0f85190159f7661b48a61766e02580cb3df7245e8ecd5c0cf14b7717e060a8255b474abe35ecc079e021a6d04
408	1	180	\\xc388eccf3a4c37488be1a190f51d1d83e548a82562d2bc8c464595d5a65b940585f2c85dbe223642be82e07a46b013eac3f76ed9d4b50060b971ed81dbffc50c
409	1	24	\\x398322d44f1a1c9d08152f805063e94bb11abba08d3105d1418d23676c2116b7fc3f54b4525e38d5c5c025aaf821a37743a0309337fca34b2413f88cb37d1706
410	1	27	\\x3d1690039a728d2d89fce1af424ae796c9dd14ad1ba5ed9042f98dbd4e73ed1918fa151043d6d5e8e112c83de5c05441708e4ebabc87a4c17f73ecad8456b200
411	1	207	\\x9a523050455893ff574ca87d474110661559c685e5e7daf9b8951a0ed634949e4748e311874096e6211338d048193e2e55e1df3a97c04da4f9b5ee9033154602
412	1	142	\\x381d43af77f942fb3a3070bdfc6a28c6010a964e6a3bf61dab4904af499689f97b2561ca5920ce9dd406a3c09b369766c6b2eef911bf1ff5c5ec8f300eb2a403
413	1	161	\\xd823911b9392bb8818c28bc20520cdec6ed4984913947950f818e4812790d6ab1b9d714e94b3dfbc03421b88c071d13f0a0bf664a5137ec4c3f7ea0c52622d0c
414	1	401	\\xa51710062f98b0e1c4475a8c0012c24718985505d1379c6955c0c8f2737f0c07f39c2fac503707bcbe3cf28165641bce0842b895b26ce7ecdf09a213adca1e03
415	1	158	\\x64a4d0dc48adf5d19ca2ef89a0e27afd2045d7a7373a01d6563be84e97e5da37f052c8c25f91f7ea1f88be74c9c682cef175c7e8566b3cc6164d180eb397100f
416	1	151	\\x4f0740677c5ba05190b6458a045433cd54267d5ad9b18fe9fa216c8ee706fc1601c15e5a7b9fdd4008cdbdf64e8b6a9e26926b3856c44688dcffa481955a5502
417	1	61	\\xb6d017114cbf15c1e06cf43b20e4d6a5b7d2671db4bf9cc89c6f2fc65a6cdb2754ddc3a1ebfa7c8e113e4822626ed86cbc30a15a2cd75db141158cc801aee300
418	1	257	\\x54862f0ba491265388669d4ec5f9fb279ee01dbfc5e23075bb0926f079c903b797d94a0496513e77ca1ef8f266b147aa204b241ccf516d632af3796461f38c04
419	1	268	\\xc3dec331f5df7ac63c64c91c324776a5006383700a0980a91271b7942a988d15b8403f7552890488f6a622ab7034939388676e5858e647a899035130c4b2d105
420	1	42	\\x28beb98659953938262a4b295ad54a4d633b8290e05625ad62e37de4aa6e67cb848c0c3ae7d436603d7f1694cebdbf0ce12415cf179f8b3028b97298c02f0905
421	1	267	\\xf49498434203d9a77a0c8148b9d0b9f71126ef1fc978841f625f1c5e2d33099fa91547347dec475192d117abc51e487d7d44b5e2690948d5c2ace4d6a41c4e04
422	1	259	\\xa971df13706d1eb15929900909fa3c6a1cbc93de4cdc4973ac256eb702c122a362e15bd9f5157bb74a6a2c4c6c807dbd23aa3e879d11524d1eea6c95bd7b960d
423	1	85	\\xcfb399bba65ec62494c028a2edd418d681841e2420e8ccb0fecedef580e13c558d97eecf195785ea167b61caaa40a3da4a2e1e0f3fa40ba58d08be39ae24120d
424	1	139	\\xaa97a367db4221673c6b8bbb7bd6abdc48147f43b20f888c375f54f4fc3f3f242890e04900f212355e95b224d9e5ccdff3c2fdc595d48ad6b7587cbe94229907
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
\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	1647346053000000	1654603653000000	1657022853000000	\\x180f826c6c0e70e1c77ac987e7d4556fc8516debff1bfc3a372246551d4881a4	\\x8ffe5238e8f881cf64a84991f7e2455b011164ffb9c8ca3a8fc86627a390a29ef478e2ba0de3a5573620199094865aa124b9c8b3288950282be4c1c505b38d08
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	http://localhost:8081/
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
1	\\x11be387514ad6d1473ff28bafddba9d024a87cc9e74c483aa7608861ae9d2953	TESTKUDOS Auditor	http://localhost:8083/	t	1647346060000000
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
1	pbkdf2_sha256$260000$cOLaazBGdKixyIClaXGFSH$60tZs1Yz6yn4iwCOtDV7OB+VKuKUKAB3VzSyx/6PHII=	\N	f	Bank				f	t	2022-03-15 13:07:34.516562+01
3	pbkdf2_sha256$260000$AJsqOC0H65Hgnu0hqsENyb$gCbU8LN7ZBHbKRvR20PXKFTyyL9WAeaBeDRUO03DI6U=	\N	f	blog				f	t	2022-03-15 13:07:34.762339+01
4	pbkdf2_sha256$260000$lfP0ZwTSKI5yhcdIP9qN3h$R9uqVzwjH2Tyf26ccrtRZT6PagfP8WOEmzQltmLOQMM=	\N	f	Tor				f	t	2022-03-15 13:07:34.884652+01
5	pbkdf2_sha256$260000$dY9VgpDTmKHHMZe1LcO86d$Rb0NhHt81iaP78HPCss9Pz/Nr1mlkbX4GF1jntTDmnQ=	\N	f	GNUnet				f	t	2022-03-15 13:07:35.00827+01
6	pbkdf2_sha256$260000$kn5K6bOCn5OJqtKbK15FaG$GB1rmuRLazF/9nQZv3lED8Oe0qBLLHhdj1OOp/50r7Y=	\N	f	Taler				f	t	2022-03-15 13:07:35.131183+01
7	pbkdf2_sha256$260000$6qsNX8ojrJhT7On5uPI39g$DXkFGIW++YHiqbbsN08jKFoclceUIXGMz+TjXZt8zes=	\N	f	FSF				f	t	2022-03-15 13:07:35.255135+01
8	pbkdf2_sha256$260000$4CJpo2prEND0g3t7c5WD8o$g7114O0Dd+SBbFfJRFQOk02W3cM4cUrS7krNwGNUeKw=	\N	f	Tutorial				f	t	2022-03-15 13:07:35.376038+01
9	pbkdf2_sha256$260000$n1BGw8hDTEHA5KJjqRw4QK$WDhEDVSuRdIG/m2zsVz7929pAOMc1+OBTZDh0qkWBf8=	\N	f	Survey				f	t	2022-03-15 13:07:35.499534+01
10	pbkdf2_sha256$260000$p7dw2WBVrkKxUsl7xVOPuD$smrx6B6jCh3DIJlFb+jbxKXZTGRadHbnGJPYQsKXJPQ=	\N	f	42				f	t	2022-03-15 13:07:35.915514+01
11	pbkdf2_sha256$260000$n37RH4bdDJEp91BmMzbaon$v8WfNgPZOhaV+fgtxI0OPmOsASUPSn4HrcQv767NjmE=	\N	f	43				f	t	2022-03-15 13:07:36.329811+01
2	pbkdf2_sha256$260000$wvUsu6rVpnsBP5a25fBHBY$oP4wzBCGTkMxFsu2BVAnusxIEwnduYoFvwpOdFoegSk=	\N	f	Exchange				f	t	2022-03-15 13:07:34.639647+01
12	pbkdf2_sha256$260000$gMyg7N9BCLEDdDRSC5HYWY$+rUUTF8L47NjCvRNvr02QfAUQ8kSIXnteoELdxvbIZU=	\N	f	testuser-fd7nox2m				f	t	2022-03-15 13:07:42.231743+01
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
1	259	\\x663fa7b98ac811152fb7bf04974fa59f586c421f9099e621de025678b45ebcc9e719e008e3f738f3fbaf7bd098e487feae24d02ab2c784507f0810fb64578603
2	142	\\x2420c80af095230fbb782d0912a8c6a49b753b8b6332bf3226f25cb0fbc51dcdbccd5c50cd432454ffab1a0cf61157b694fb1feaf1a01a2eb4a1c65eab2d2e00
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x00c011b9183ba709f59caa4ad7dc4add666e3c6465fd93bdd3be23ccea496e715df4ee407cc2e6d4fcdcbeb543cb88ea2e3d8a4480405cf57246f9b4bd056cac	1	0	\\x000000010000000000800003dedda83c3443e883efda6d5edc6318e82b25e198ab9ef88610514a19fd6d9cc532077b61d65eeb5de8d8fbb7891a27d7fb43fc14f27fd74e673724026a22041fcd128564b28829604f0bf91fe707820f2924399f065d97522fcab9e4843877cfed4b89c2540398301078798108f5a3f82e33b6bd39c7a6d541f9d16fb82dbb83010001	\\x3fc7e2105f4223d64d145a345761e2f29f12a748bc34bf4962c7e605137ccbe7cdc2373a6c935d1fc8e32388c9af9c7e6f6b1d63d8794bcbf7e00a4e457db00b	1655204553000000	1655809353000000	1718881353000000	1813489353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
2	\\x01c45552e3fdf05dff51795c754ce2f0381ded52169a3c731f714be99097c7fbe930cf3e99f5a768907b0f6333214d07729e434dc79683f54bd654a1790bb224	1	0	\\x000000010000000000800003d3bf3da8228e892f9d791ccd8f244d71abb7268a632d9f333fd14eab5a2d24bfec9cf2637466875339b4e73048104939b5dee43355156af3354c166e732ffa8d06000f6337ee4c3b4f71ef6971023be85d5c9340d48811ad038b66e0c366183c577ad1edacec46382309c7335ccef19086e0fd0c162ed275738689cf5a61a905010001	\\xdf7e2b0a293169453bec1d818a94716b81f91fc6df29da23cf0247969baf33092cb494e8574fb1e0d2e4fad99dda51ba988a6bbd2b3415cab5a0890950a1ff04	1668503553000000	1669108353000000	1732180353000000	1826788353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x02e831184c067b2d145d5d266cf4616b5e076295d283aa949e047b1e0a07c549d9a79946d981dcbd4d1b7cbc1de4f2a04a0131ee737e0f4e6eca71d4635015bb	1	0	\\x000000010000000000800003d7bb96727874f93d8dd8b0974cc34e5a7f11ea7e034dce7d466e6fbd7a39e8b2c31b8f892146847e6d806537a26491bc6780862782c5743399d8c456a47111ff0a21ee7aae5cf8d357f786fe4dd8d498bd38fcaca7f733b29d617f70eb0dab26a0310bf3cb52f86e2c873256f0db11f9080127d6542437efaaaf3f6bb8a3b0db010001	\\xb79aadf7f5c2552c60e2bb43cc56db052c7050e558bc0db9ed99f0744df8098e35fa114405beb145e1f4a7e684e517474d703714886e64802901711911b3ad0b	1672735053000000	1673339853000000	1736411853000000	1831019853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
4	\\x02a4b533d452442bbfdd1a6081774208b924321e334f273f56d5c5c757117ca309849527996e29de4d4d7ea4984c10c9b31f9a53815d42861ad1775232b7fd9b	1	0	\\x000000010000000000800003c984e616222d4348e04cada586dcc84ee366a2825a55a3598298a928de3d138fdcd8204aefafc8bb7de8a5fd5167b686c53be474488793e9744d29739cd9bddf610858832309fa11803c9fd16e509e87fd67aa1fe7862fcbd70476327680d9b8a594a4fd26126aba2cbb708a9f368e10c4818924f34e8fa01106a2d3b961293b010001	\\xa02259eb79c0f603a1ca06526bd98d0a31871bb89195370d32b0209dfbc537dea39afdd2ed4baef283085e3789bec43e8e5286fc7ca218d6b9000b9ac154190b	1675153053000000	1675757853000000	1738829853000000	1833437853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
5	\\x034859f424bc492910f3282149f79ec8432787159e1d55f1c3f40a3cb54bc8013c658f829ee18dee93d1f9792f858b0e44a446cb1f6d193d0dbcf4b4131f26ab	1	0	\\x000000010000000000800003bd9bb385a00ee35081f46e9c5b72567fbea0a023058f774ddf21f55d19f2314e104f7654359a719f53676a5caf00896dc6ec4354b2419cce34a7a5e2266d57c8eeebceb0130b6e30fc4f633067560f57fc006483fb62776d7ca3a3f65f2efbc901276bd32c77d388f50af7dd74ba438914916662b0cb22a3ab4469735046d02f010001	\\x27493cc5b695aecf2c6b742aedec0b991c10fc03c166b894a5718d82747b89528c8326458b1ca9c5859ff65abac4dfd9b60dc099cf598429c1226812ea593e04	1667294553000000	1667899353000000	1730971353000000	1825579353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
6	\\x047089df69f45d25b7abeec44595544ada4ffc6d9ca000b0d8493ff7af5afa28ff77c7e49f998007a2000226e4e13eecfa5629b1dff8b66c97abb01dd7770de6	1	0	\\x000000010000000000800003a1e0e6049c08695ffd0173d8befc9e1c0b81de5118665075a003abb905f80726916f8692d8733f6b5c1a6a092d398bb599ea55e60b817d278b01fc37e1fc55e1efd8cde4e988dd4496496f4f06badae729e1c5176c24de576878c3fce2f41650a0036239aaa78bc52e7bbdb2f05992d0a33e4b96df0969026d82073f3846a717010001	\\xeb90ec55510c1d4a097bc2318d99e9e2a30e08b2348bac59e82530f0e5f9f006a34001d8ffe15837255573f32b1d7d7638805df194c1e889a458997968449301	1656413553000000	1657018353000000	1720090353000000	1814698353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
7	\\x0514da2341ae1de843d51ece89c88c8c812ac2750b497f579e73e77cab15bdcf3b603005241472f2309e23665a2f61aefc3d723d4d2de6ab9f74e991b37119d9	1	0	\\x000000010000000000800003c8bd054482b7fe9c3e254a8f9a7507bed41f4e3d9fe461dee304a7250c80acf6daa6c4a030dd67849442f70ddc7abd5ece23eb2786b04e419de3df94259d2fd0830b4e04a3fb38e2ca73da9a1843cb1548db3cf9fe136128c896a994db113d20397c7447d09718486573ef9c998c1db3f2d0f6d00698b54ed9d5f1d362992269010001	\\x8ebd1e3b1fcf56cf3283f19aafeff230bef323453256f594ce6f0ca2487dc445c01ef77ac3ce33ea0df4ab3baba59185bf83b4dfcc74801890f9597b87b76d0b	1661249553000000	1661854353000000	1724926353000000	1819534353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
8	\\x09380e8dbe28563ec913f8355b852986fd1dce8553f5abdd639994c237ee11ca587848c4e125fc9e15cce9cafb67ee79cd7499869963b89e0a91c68809d533e2	1	0	\\x000000010000000000800003f4c18fd9c0f831c9951d90195352a5060447f1235885a04e786bca0d3881782f0e60bd3ccdf86c7088fbbb0c8b28f29d7d39a778d6d9b75c816b6669dbbf5f9eaa4e5baca85e869a86dd8e9c9e4d8609284c871af2b7e1953efcad4d527447befdd98b14f6616916a9d5602d01aabda44562f81f50d1379191512554a46f988d010001	\\xbea149f111c3b27b25af113b845ec08c125e20314fc2b961adf5d1c62bb62775fe7b8440f33af68070bdd9452ecc07014b7804c8f25b9e3f4e20154704e76a0e	1648555053000000	1649159853000000	1712231853000000	1806839853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
9	\\x0a14f04c2899011498bfd33d707411547b79d79e759ba741cd7fdfa46cacda7352435ec44acefb34960fe9a1d3de71dad67d0bf7d130ecba3851d3d6eeee0ff2	1	0	\\x000000010000000000800003b78381725ec82945d956e285da49829e4e32e839ae11a98aacd4d4dc584fa7031d7200431563222f28bd99e0a115934e07cfc862c656812f8b33e20d56678787bdbd3b1320ddbb73ad4aa7c88540d3bec25ae8a1bfb7dc46101b5fa017b222a9f487e3224a8e1ee22acab8c6a9c920476acb656665f877121c29a61b55d979df010001	\\x78238bd78394e696a06622c54deaa36735be5a8ce570d00f09dff4a3a33470ee493e1c029a2ad05f7a0340d17d63076ae2ff7dafe854b2efb90c76b7c2cdc902	1655204553000000	1655809353000000	1718881353000000	1813489353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
10	\\x0a8854f37e031c4e016fadead346725f69f2748105166e9be8cb9510151484b6b90ffab75f5affb08322ed8c587d87c7f8e7cab7656f7348a470ee1c4b26f39c	1	0	\\x000000010000000000800003ef4c579ecdef76e1e27b9fd14dead85307018fd63db2fba9087dd8a68d62836d14c00a17ed76d1a4c8133371656e76ab587beb0a5cc2cbb73c87eaec3e0dea7df314e65f404c83e2699b8c30f721e280510c1608b80dc39dad96a3a19a680e040696ff63282e22447a9ee25b8e69bad85bfcecfc04cd592975d962676668752b010001	\\xe0f6f55d7a6efafe8813e22a504a9c13094459ea51b9b1005be506a5c4f867b41b65729b969f29ca3aeba458d27c3844f8691bae629ac5978b22d47785e18e0f	1654600053000000	1655204853000000	1718276853000000	1812884853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
11	\\x0df8dc6f0a4d3d453827a91d968f503de9aa5b1897aaf3908bd8ef1c611ff26752464a477b6c71d016b63e3158048167cfc265698cd928a744f34658b7caf203	1	0	\\x000000010000000000800003d8475db0901bfd16c596b598a2ece596f54b21bb211b0bd3efb5c1801894f48eed5cb70b15028c2f6caa7c605124d9bd47157de7bb2e5c0f9e51a413ec6d0ce2a8595cee6751df06f42437d67ee934246b282313b395a9aa543ab8905d852987626e896e1b602c5ed95807958602ddc9c7e69dc9d03b4af9f803695bf60098cf010001	\\xef273365c14cc4d0d29cbb6bb0bc0578ceccfbcf6ce5f00824381d261ca45986dcd431ddfebe2f51f09ee05b552511627987171461a82fff84941ef9dcf1d809	1648555053000000	1649159853000000	1712231853000000	1806839853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
12	\\x0f5854833fbf7421392e6080bc7c50bb711949024d4ea6152338b6ec98d192dcb0eef7af75e8d28d6fd748d8788f12da126116171b7eaa5df9a3a11d3a86bece	1	0	\\x000000010000000000800003ac59b19c47958395c4bf950ffbcd0707ea40bae4f9fc6a07ab03e212848b6d24147599436faacae22fddc25956cfdb1662ce7c74f0bdd826877c0a419b6954faec9d249aeed226b66fd9a5cbf1a332ea79129545753d8e152f8573cb4b8a665c1709c59e357825d8d0bcb533fb5a407bbfba850bcae4d919014d3460d8ddcc71010001	\\xae93cf110182b109d59e2dd44c92c9812824178824ebda99b067e37962833029c836b6838c47a3fd84977e64e231a09b4827acb817f714092ad722dee7290002	1666690053000000	1667294853000000	1730366853000000	1824974853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x1200056f2a8baa311222d652290cc662a80d98695619aa7aa32f082a4f8fef3ce87de0fe093e4b38e892c833383335b8bd95dcce5d64ae7e4196f7a05dd30c24	1	0	\\x000000010000000000800003be7ec664bd5b3a0a5aeb2b92052b93906b2dff40bcd20ca1dc4855d24081397e7dc96addac1000841ca7d1dbb0d18c4c94995051f7dbe06277f7b9818dd1b9939e826e620d9d08cd403d7e7429c8a383c6205a2412b6447c94a4ca4840fea90d6e25e6dd28be27d1aaa487c553f7eb5ebc5152b851c3fdb555d9c948fde15393010001	\\xecc7c45a281a08d75cee2e59460a8a985bda82d60d0b6874995ef20117ae07808cd43b3b843f3350795b4794a8fa8e7e996286cc3a293f52c718709863998d01	1653995553000000	1654600353000000	1717672353000000	1812280353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
14	\\x1458d8b48d79bc7ac13733b9609648bd12952c8b99eb37223c3e8de8e772196367bcaae8fff4a7a73d677a3f157b91c3270510470f9a90b8ce9ff1cde7024293	1	0	\\x000000010000000000800003c522435a031f0e1ef024e8057b0683d10aa20918de4e865091bb3bd051340e11214ee5eff27e1e39466997bb90e40e87f7bc7013aac020732aad0ec3747b137a72bf5d8cdfe62328595ee53a0ecb05138e73e5a59b74a6afe6cc988cc0387e6adfe0abe1d55bfcb8bd99501f3d26f85fb23bdb14934633bd4670d69a33e21863010001	\\x9044c1ed17437b39850cf59a7b069eefe70e8c0074d1c2a405d3f895e2e269fc68e7002a85776cd5d7005bb3e2011b0d6a499f4bfc5bd102b568e5898c5f6e0b	1662458553000000	1663063353000000	1726135353000000	1820743353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x180825d17997e927c673a3d8aec1993d4f0ea9edffb271e6ff7d8412c47f80ecdb6f3e6c768d7d8f2e3bea6061fbb23d7147ff340e056dce686da12490d204b9	1	0	\\x000000010000000000800003bb7fd154c6cf83596956b19e3a800fdebde3e0ceb691e27a2856bc10aa7f44652dfddd3a4a2e00a11e1f7b5f25a36428a5a549bcf49067adf35e8779fce72ca233249559b9fe36be4ce322146677a1f65dace0599201120f938b0a08d4ccb639b5b91b46d33a29390e72a0be03f84208a3273a5ebca89fb471eff025896aa413010001	\\x33cd96747cd16410f5e65151ab9d17715d2b3f6f4fa787b3e73ba5862b6fce5b920ba1597645cb8074fa37d9c6a128924882ba7d50e15b16877535d93743fd0f	1658831553000000	1659436353000000	1722508353000000	1817116353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
16	\\x1f8ca53fac04872e18e9cc76dab2cb97329fa4877715e6d89fdc65ceeabf0ef58306d7453688b3b44f3567ee1c2f4d8e19145cc38d112b071a588a0e19c8ddcc	1	0	\\x000000010000000000800003b45a0fcae3fea3429624c02df33be00c52ae84e72e1c613efa0fb1c1deec0b432cb6d014b97de9a1acbb85dc3eec6d30c79e2abdcd1674e61c3ecafb8e461fc4ac2ba4bd4ebe03635c02552c2e2e5ad1522f7848e7c768a5ffc1b9b8f61514c570ddf5ac5d97702b6e72db797f821903f3446c6f2ed0803c7eaa17eca5b608af010001	\\x5c92da310344ac64c8536ef6e5d0cc8f9b3ff08641e847f54516a8da91f056edec8be084b4baf3613e82390597fbabc26518b6e7ce56d53ed8b7a64b529b2808	1665481053000000	1666085853000000	1729157853000000	1823765853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
17	\\x2244b2ecdb4d7b147af8063b8742f193d2776cc8798d87e801114e626d1beefe2b81bf5d98967ab24034b89c63621953c51d4f961e8a6c62577492a31feb4d0d	1	0	\\x000000010000000000800003e14a610901e725bd083182ae06a550ae76c53afc36ec7b8bd1fcadf1f66236a64130c2c3410577c2188bd2625814f96a212393fba25630413d512a37eaf96942bab4ada02adf793a473d4d32e4d627a2e84b3d474602f2c7a7a1eab2ab85394c0f08a2c7b827478333cd033af64e1b08d54ede48b14117947f23d0a9ee98bc5f010001	\\xedfb19eaff2846f064f6385423d24852bcf5980f04913da3810d874b7a6b1cb9a2b82843c08e9700b1daab4e82713227d5ed06209104f90163e2922e75b51300	1650973053000000	1651577853000000	1714649853000000	1809257853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x23fca0770c55428daed0ed5d2c531a1724851af117c8423919a710755f2b24bac13e72c90fe95bae8219f22dc599e94954b6415a3ac8c8f6ff7e3374e544d764	1	0	\\x000000010000000000800003d32f1e754af7563eab71954af03416f7f658cc59794b9ffa4b9f56f0ca763c1ac781bf4582ee5b4520b38f02b9e81a580ddf613d59b37a08b40dbaea49ca3e32cda99106cb3df233783914883086386bfaa16007c5ab1ddfec131c7fd7c18faf0e986bdc04c729f84d49905e0d9b72e0142f3a5a15c15de0fe8601dc7a1920d7010001	\\x20035e75bf69731080f75f7628f278b961368fce10a8f92d792b1a55d86d3859ce66c0a44810782b23a6f59083a9341600b50bee8f0593fdaa30d5d6131a350e	1651577553000000	1652182353000000	1715254353000000	1809862353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
19	\\x26acd3bf4075a6129d1ac4de5acf55fc6e0a35fd8227c0cd054a5a82603b4e09fa55d2d5deaccaac75bf4689b8dcc3e579055b75e5e48b45f43db0a107a3dd87	1	0	\\x000000010000000000800003bff33301b28ef7d582b574a919d86de392cb7ceb8ad316db74e94020ec937324516b3ff7ac020e4ef80845fd1a1db86e834bfb73328ee050f92452f39c3bf925dd666ee97d4ad5a38de285febb27bacf16c79617ce67052e00686e206ebde49a5f0e3ba38b3475f0c2604df47db46ee0c69eff934f30aff3b37fbb5f4264c8ef010001	\\xb4f810eab7fdde5c3a8a25b9c81483eb3ed8275a0ae3eb8bfa5bf5ca57b27165a1ddde108046ad7b2932785d081fd72880b4a3f2497760cb8724e0461150e302	1670921553000000	1671526353000000	1734598353000000	1829206353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x283046045f25bbd6a911323b9ea6109b6dc1c76c451d6a0eb3e67d96944fca5b1942df0c6ebdd01e090c0599bf2fa064a56d9ce64b0e829e41007ef80cb01702	1	0	\\x000000010000000000800003c9868c3a175f7fb219c2d987e3423edec28e50f124e3a3a0853dd04eda8a8753b2ff33c8d694fe83d904e1df97e574ff6423c558906ca007050afd9762987191fb5c86eb85b84ab0ebd7e1f692b10571ebe3d771316c3feb2825ae5ea151d3173f2bcb2cce6014af2b8c4f153d3c81323fbdba0460c8f71e09838fc8cc3bdba5010001	\\xba5117987b3b49be998bcd7f47f9b58b4dc0caf8da0c07177a25bb67a74b3d59912eba1ce9cecc40563e8065ec9b082eb12b58aed39ed1ee923598bf0ba17b0f	1650973053000000	1651577853000000	1714649853000000	1809257853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
21	\\x2ac005e173100ad2d08a316c938ca5648838ae2507f5816015251c0f0176c11faedceea5be5d35a39b7d7f9114830f24c3cd19157817125ed150bf9e93b9cd6f	1	0	\\x000000010000000000800003ca808c18ac8f931cd95bd26870660b10fe53223753dca37e6c9d32d6089401dc4e20def7ea090611b979b11c8cc1fcc8d1d0159e47842e09ff44fec972382979de7dc74d5c717418805db9a3cd15eefdc367d90a4ed6d9da69a6af1153f040ccb98f5732d804739e109a097dde7bde618187763c6e2a0c4c8e704a5ed93e11af010001	\\x5c4c1937af7410c3993a286db7bde751ecac0b140e6d9ba6108911319893a24e418a2d643691f97ea2141eb78ba7df61bc59c375d8f96933e22f6ebd588bcd04	1653391053000000	1653995853000000	1717067853000000	1811675853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
22	\\x2b50b3d4d890c422dbdb3dcdad51ee180eed0587ae3d8a8ca972e9971a7f987d714c6c5bdb3c94e8b6a858fe3847751c2d964b4ee91f633dd8263c8ab0d71527	1	0	\\x000000010000000000800003defe3dada5d2ab6672aa61ae86f05c4c09defdab2f59b290959c7c15f6e92cdb348defb9f771b7b52fdfc9be20b16b81f0918e0581958659caf66b9302ea448b4782ac728a2c1778c7a700a76d233ca68eec46f3db6fe7173b00d318377cebc4d340781d0c2c18480d6b466cc15e343cb45c21abde8e6f327c766a2d2314f0a7010001	\\x884d30ad7c4030097e018863b3abf71332dd703dd251d952e635d25c811bc4cd51f2bf6136c8ed0aa053b9ffd5b0ccb5277c13fedfe5198a28b21feaa1f19d06	1677571053000000	1678175853000000	1741247853000000	1835855853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
23	\\x2b883d3d43b69b8ef9234b85c52b198698b5935f6acad3dcc3a525200cdbdb41c99b55f91af1bc681653b20f376d50418b49c03ac3567a1b601770cd80c46bb0	1	0	\\x000000010000000000800003acbfcd8181efd6ab6711cd4a89abb472b08502d913b26bf2c95c568b0c46d3254dfee5a3d61be63d35fd48d250b45567424cb7755ed7bd2142e5c01626de35a174002ff3a6d6f8bf377818fc8538675ab403305b62dd7a71a8fd80829a4a893fd53aa78bf325af24453cbcc910aefddf28fc2953b455b4bd898b912900072553010001	\\x8f484d6ebfd5d101692fc290e00b2bfc30389b573fd61be3f99fee78ad48c575b93454a110b8a2e2d9c0d5f2ddff24a133f6f6009b0765ceb733f5a832dbc90f	1658227053000000	1658831853000000	1721903853000000	1816511853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
24	\\x2c78362bdac2fe9c19a9832cd816bf453f2df7994ac3f347b329b4d8104afba3ab0b34d14eab059647b65cd8b66e41aba38780f05ad37f54408fe35670158b89	1	0	\\x000000010000000000800003aa02713fe4dc4d12cd57293299f2ef429f772272898b9b853f41ced18506c790dd374acf446984e3a757c3ec13318bf99885551b6deeea810bb00e7fbbc5a5ce5bd32ab7673bea2a932ca38260c702abc82bfea228435c73a9cc9b71c2570d4f48c5620ee823881639c8b8c30782eedcb752030cfc24ef5cd2bdd012de200dbb010001	\\x8484011cf5b1a3463cc5c3538e4234eb6a4d543036a5c62f355cdd8a997d65bcce45babc9cff422c715f01e10b128f2511a006bb567050ee88e837202fa5e30b	1647950553000000	1648555353000000	1711627353000000	1806235353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
25	\\x2dc81b3279f86d48c85131e75d62778a41f708310f4de08b1f377ec621ac26a8f1c1603e0493c34901c2ce4261adb85d015c5f399c616d8c616944f658a4be0c	1	0	\\x000000010000000000800003b3c42f04d6289772ffeb550100fb1de0eb2d60f29809a056b3ca4688f5b20474fcdf53e691a488f84d80dda9a7288becb45da3cd76ffa9594a04fcc7db70b4fa1065f144660a40029477acdd59ee345b207ba9d0c2cd82f3761c233f157a3e147dcc404825c105ba4284319420a17e67f9d5ed979bef00eec94315601a5b0061010001	\\x0b587ed0aa735e39829d18193dfa9f239497edbbb7ab3021881c2de9dcb4d6576f52d7d438be8f2b04eadc8f1bd877313749f743f92636a1b8729cc914f28305	1657018053000000	1657622853000000	1720694853000000	1815302853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
26	\\x33e0908e6500c28ab1105293c54baba455b6c2d7a6a5dea53b01daf27df280f2a5ac9c52293284c5d2022c9a82fecbc9a19b20d0afb0de31cf520404e2c01ea2	1	0	\\x000000010000000000800003b2c27d775e50846a3b0304c672d8890b04a1dd5b42d86247ef25a21be9e1fd4ff73211dc42eae3b0b7f045e3bd84577a994fb1ad8e9c3858cee44ea37588a21908bc63b6ffd1c0726259ebddc4b24b0286bcda8959809ea16e1a96b26d6678ec0b3ed3905286683b1f1ac26e1719fda7667fb71531da1f5baea48a53c9d171f5010001	\\xd73d80f01934bd59e92c383aa6b4657e20faf830ea33cae5b21b58486ba8eb1cd56ba0bea7ebbbe16d14f6f3a56ddb619890c9f77be3f2c7e97e6c6c5be0ef0e	1667899053000000	1668503853000000	1731575853000000	1826183853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
27	\\x34d0bba9844d281740afd3dcef2e0d745194321f77a2193baacd23d6ed075b081c5e81576e27e835434d033a488cc3fd39f993b30e290e06581a97511f92076e	1	0	\\x000000010000000000800003bf05a8bd0255664a35c0d69b7f0a5489105883e7083bed93ebc8f5a3272422f6f9099eeac060f662cb385e8c8270ea9e920729e66ac9877ecc5dd02663b0237417e4077c34f039dd3b67ae731399dd1c14c527d4a35d8a0a3e6ed4698359c75da93cd4da7113ae6900264fbc11314dcecf61797992fdd892c4f06b95e75ef76f010001	\\x2c1e93437406b4c4cfb5b11f3e88f73fa44cf8d71c0ee3c6ea1f754554371c2e9f5a4dad4537626cbd8b1b9ce5e6f01e9d90023212a1c0d24d0b58815c87ca09	1647950553000000	1648555353000000	1711627353000000	1806235353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x379893541a3a0f17c6815d214d40a71eb0d871083465b3f6a4a6560b868ce77b1c4958cd879d34033e6f1a8a9d0717036214a67df98cc8917eaeaea350dbd3e3	1	0	\\x000000010000000000800003a1851cb350803c69639040ac63d4886449f6199d3f1ac5ddf1aef96b4c2c2edcee440be631e7d1fc23b5b7b060a9b1dac215e77a98d21e5fb15a1df7f25fd11d9f134aeb931e975e6b91cbf892bf2ef869450fb568b582cbfe3a0ca2768132a954256a833f6cef013eec99b24b2eacca74e518be0d91fc49ed43af7197e16cb3010001	\\x76af3763de431de5bbdcaa878224d82511fac64db1d1eeda21078bcaac7a2a1e979c4b791d466fbe4efb986f6260edf0111b67487c8a60d894afcb7d2e52b201	1663667553000000	1664272353000000	1727344353000000	1821952353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
29	\\x3b2816c4f51821ac0d320d737e5f70d8edb0262deb341867032140cb50cff507bdcce6aa6b80f6cd8f15a82f376e029e88e77c712c62cc9de418d25fb4657d51	1	0	\\x000000010000000000800003b80aa1ead30827314f2a98a76a35a7bcf426108bc55f394c8b29950e6ce204ab4e2501f97e435582052697bcd8a1bcf13ad1a761364aed22a5cf8128cc895e9cc3e97d6b0ab185233c6fd95d93aa0d096c36422b30c7a3e6e86accc8d8d56da3ec444942ac5fa868d0a4b0490741817fa8e2358a0ce4350ca7245e4ccf91e2cb010001	\\xb7dc9f65fe283b7c012fbed4fe6c925218981aa87a158b7ac36e8d86f56f419cb1084d132b6c6a8e1963f2468a3ab72c62fdbf0d37a09c8c7245a00df6504607	1673944053000000	1674548853000000	1737620853000000	1832228853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
30	\\x4404d75ea4564851ae2482a1646e439bfc5a4004ef7b9ba82d3223b0bb78e9a22311fdbc9625fd11310ef002424ab2cbc52403e6ec575a2ca01efc2ac42b82d4	1	0	\\x000000010000000000800003aa47452609f5f3d1ba7620b1bfd0525f905fb090dc43fa38d8b03fa8bb9825d7596098146659a1019d5ebcb7652b7f113a5a33610802c815b5d645394203832ed02848650d00e352ebec8d4a18a7a2a1737c990c3feb316e762731eb7575fc795730ab77b85268963feda09e1912e2d4e93304722a45731ef17bd951d1710ed1010001	\\x549a60ba1a6f9bed1b05e14d9e49d8a281d3c94216f2bff9dbacf48df311ec8850065e92b6c20469d81cd58c18ae20c067c4c0fb7063861fe6a0f5eb495ebd0f	1649159553000000	1649764353000000	1712836353000000	1807444353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x45f825682284db0e04cf17cbe5f0c8065328082002ce7c37574568ca904465dc4c4965aec4a595082c8ac624c5478d6796770525e32742711b96fcccb1f0e792	1	0	\\x000000010000000000800003ba14186fde6b7e49b95c73cf0f783328f2a2f27fa8572f5a7f7773681620210c4a47fe1449a71ac3ed1fb4187061033cb64d2c37533a426c6287953b65fa469840d7e0e269539118d34cab9d61bbd06fe8f7be13b749894903f5f4896c5e2352c3e668e8ce2664766268fdb8b9f942800af4b55bc726075f179f2e2099a4d543010001	\\x3e4bf17dba961540d12cc60ed9031fd061a815476dcea8585cce0747901890157e69f3e2730cfe8ecceff3930d05370076e8e09ddd83c0a5374d81ee278fb00e	1651577553000000	1652182353000000	1715254353000000	1809862353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
32	\\x48ac45ba2377456ddc272c43c6d0bb586b48e514ae2a79b7be6ca444b7fd9f5c32f87c33ed67ce8925a4dbf5e9850bd6e40f345ab2c27bf1f18fddcf3a4b3b76	1	0	\\x000000010000000000800003b2aa26173a9b5cfe2164e65a08ed67ef9bb5b107b2306a7710f940030ddeb14466eb08ad0f2f4faa5d3ad25292bd001959819c548161793b126a873d70dee74d4b28b11d2ead201828dc5e57aebd6cd1ccda760e6de02ea3a14892f2b1b5dc03aa82833cc9c97e4b3cb24ee14046fa36214ac9bc773fe56f53cb88c39eaabbc9010001	\\x6f3e7a6870e1980655e1a4fc1e4da12083d036e845e704ca26191c64d6f93fb8c0ff518bc12194a6b1b73baca2494ecb248d653c98b304f53a82b9667bb5b30b	1661854053000000	1662458853000000	1725530853000000	1820138853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
33	\\x4de024a1a70afc84e5535f7eecb4388e14888fe24523734db0f2201020f44861c7d18b5103ebb6095861422dfa0eef695266bbec5e2bd70adc54b9de314d5d5c	1	0	\\x000000010000000000800003c87aee543f4fe8fae3250bed269bcfc5399b738bcd695724552b5586d219eb366ee6328e79f3ad76480f32bacac9c865c943b083b134fcea864649745f6c9d5ffc1cf321799b347e92736a84f0a5fb574743a1162b7383dc5da14bc1e02a757aa3cd4d6462d179fb76101feb30502b4bb0561ddebd89b050b9dfaeceaded2e6f010001	\\xb4362e1470c6cb70f92dfd4a07a43add7251bb1f19f4707e7e0128f98ea8f9f6f513616a715df0fe33892ea8ebfd00d4f83198614fe633ee939815755b8c2705	1655809053000000	1656413853000000	1719485853000000	1814093853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x5164a5502fd87be99416cc0e976964a6a2c8fe8f3e312ddcde59cea11a3c90cb91e8e2b2d34e35d1681647b4ae8af83d86b33c11446543fbac6e4c7a78cca26a	1	0	\\x000000010000000000800003bd6c407040c861a3e309afd53daed29d709c3db30b890a94d3c53568f4e6dcd8210982508eb828d8b585fd91b43288bde01655a2d8d0d91831d5de5aa9acd7823d5329e0e07930b37e4429495269a08f5984f01b1fc9a56669cc8a35a0bc8b79ceea27b818d028aa40d366e1a07dc97346621f3fef2d4143506bf3c2623d72b9010001	\\xf18ace7940e0b2e90bf6a7c05192d0c80fb395394769d563ad49de22d7cfff9e778e45a52bf39ec97b400845dc4ea21b50bd940ee8553d637ef4df3bd6e88b02	1669712553000000	1670317353000000	1733389353000000	1827997353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
35	\\x5198d1bb609f3a3e1985fae43479dac664ec7c99faa73d9d66f6bd0a978efb3fcfab964aea0718f59297a688a67ad2f478827983cfc8730dc66e31d3b0384cef	1	0	\\x000000010000000000800003c33684abd78724be313cd371c861d5d457f1e965bf05078696a4b50f3a1a83f57f66ab551d7a9d1d02f987a9a85f1bc0d2e603e5f39d26c2cee0a2137637ce8c8c9f45eef481892487cdb09704f5f85b2d476a03b531e3fdce47729500e83a2ea3fb36db26b531db10a8c3b568de14b1fcc44af1bed07779c33880541ecef867010001	\\x2ad565319fe0b14e1a6c3af1e64edaf5e4e583195ed95264596c69f15dc911cdcbb8500f6eaa85201a8a5c1c14084a4d721c92bf8f784296757424371f92e706	1649764053000000	1650368853000000	1713440853000000	1808048853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x52048d746cfe4b41c02abdb6367fc2bf2c3ce52ca2fe60daefc45fe6f00c490c49cb7d9fd58943272d441b291ec41a004e96cdb5726617b8b5d710cb0bff6fe8	1	0	\\x000000010000000000800003bf3385a4da2efcf6866c0d5ecbbf0c94367756808afd1df89af519912ee2a1926dc5f9187fef055173f7a258eadaea516d78d0d7f7973388f70b41431cda1609c431507ae2004a691311f44ccd3a66de1068d07dc4214bb84171893938642f25f7a692295207873d3ddc73d07cec00c906c5dc24da12163a96e065f541777c2d010001	\\xa8759943eb18db9679ab575eb42c67e4879c16abee9385f79dd20567cc6b223505b56505379fd646adcbee56431aaaaa069f3503ecf1f6cb4f2db227db8e430c	1667899053000000	1668503853000000	1731575853000000	1826183853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
37	\\x5550142291dabc90a552fedfc24e73351fce31bcbc8796d9f53ae90b07f25d27ba4703a6935db1334dc96555bf492e66aeae4a55653dd874f882112012252e9c	1	0	\\x000000010000000000800003a8a97d5a9ab887eb9161a60c6870a8b1cff2ed147b8fce719e008c7024b00b5ee152988b30e741b3e7463427ae06837779089bebbfa4db63d6a55b84075c49d3d4bc03d20cdd2f9d05122c2d48dc7e055b784533e3754c3d08d832b1418d11c4b9f63b23415ab5baa73f5ec6f75983cb8955499ff7679c6562880ed118296383010001	\\x7e670e78ce176d575902cae7a6e1834a9f8a018d3748ba2217bf398d88db150641b690d94d86b95cf198a74774459b1bdf551985c1a997b294acf814a0e9870c	1676362053000000	1676966853000000	1740038853000000	1834646853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x57e06a598944db1836ac8f63794fd37caedf367191a1aa0b6ea30ddfa6a76df3b76d29c97dc177f3a178de4e679ca8ae7d898fe1476d01a54e84c5a511b80fef	1	0	\\x000000010000000000800003ac714d0854eeac6089620011778cd7eb4e8b84946d890679c4cde6b370502040d5bb3485100b2304a4d1b0136d37951f6ed3361b08ffb46995a40af94b6eb9522dfc2258903f5b10a46ddda6c7565c9f7641a081670ec20b57b1b519b190792cdc40a7408ae54475849c50af239946915b3a143fc6ef77c35cf997596f05b84d010001	\\xb6a56f8996f7a1155eb086104d9966835f34c52f2437d59df16a12986bf3dd334b96634552a5f84d1b94b7cf96a6d0ed65dcdf3504d52f5447998eff6d7fb60f	1656413553000000	1657018353000000	1720090353000000	1814698353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
39	\\x5ff0a89348cbb977d127ca0de005248687e5ef5f2a88b20330a4a2c1de81cc8de4a6fd72ac37b0cac8ae0f533e3f7ecc8f724da746d493155448a45a212b120f	1	0	\\x0000000100000000008000039ed813c0b92bf51930c77c0114b6926f504b2edfd0c0c5a692d41c0199752a29c879a2978def40ce439542cc3e0387a075c91faa753a98da4a0331f3f2b13eccf2eb3583bd7a35d27cbc5d7361f84c6299fa8f0d004acd5638770b3c22a2b05af1620961296228e48dea2ec0039ffe0ef53a8b1e09eb0bb6edf1e8ec968bd43d010001	\\xba34318226ad66b44174471b44aada7edfb6f2f74c5928b0e43cacac67a3746e177c599f92e6ff0d954e22066441b2f23e3df0659789319ba215c36bef18bd03	1660645053000000	1661249853000000	1724321853000000	1818929853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
40	\\x603847a784890a2ffca135cecfe3df483a1eca97e5c5ba34ec2338b3cc211498398c447d02f62491b4f3f79e3b2c989287c181fae514da3c59ba848fa8602816	1	0	\\x000000010000000000800003c458b4b7b9277e30e0e1a8714eda337be36d56492a83bb511fc7146420aa952f800d0d438c95a4c387329e3f0a3346c1cb4c44e24badfb9eceecb5eea43f44be89667e39b855e8e7ab649f3b43f2ea4c7b61628759294152a73c989cf23a8ccbf3ea61b78613cd1ad392d6e71d3aeb686e50c67c91207e482712ea1fdfcd2ecd010001	\\xd5e4bf22c9530f9c5afd14783a2f89e34db907aa523286417535b3945eb3eb85af862637383e4459e369155a379ab061fa9941f9cf2683c285493bd82b3af603	1671526053000000	1672130853000000	1735202853000000	1829810853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
41	\\x601c762d01efeef1dbf6dc64aadf683d859db876048ff5254614f5dd5dfb155e19979aa245b67a833ef6c9265c1c9cc51402485652405ff95b0bac6d5e9f607a	1	0	\\x000000010000000000800003ede151b1de06080882130c8ddcd59249848c0a9a735a90d02f416cb2817779e1a4d432b21e641969f367d325718f682a856ac8892b9fa0a958fbc16122b5e0a10d4ce2ab285858fc0ae19ad4fae170091a7258a7cd8431d2a568931a14aa109571370be3eeb9210b1bc440503428e77c8978948cd33c66471c2dddf5591abaad010001	\\xac9daf5289afc6a25287297c3af4b7652ed13517e4e5f76ae67faa36575caff76b5d9a079c6d3194aa9080663cf2c5911a2529f0870ac5abbb0a07af24a64c05	1671526053000000	1672130853000000	1735202853000000	1829810853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x6394c77de51bcdde42e11b0ffe52a449b330efd05949e3cbd0ca29ad661f4365dab9d490705b70feb5defe5558a8c9940ced08ecd1cc92365baee13483734f01	1	0	\\x000000010000000000800003d662575212fb94ab509e6bd482899c686d45bf114bfa616308e301b22ed38133850de16838d11b5294a3d15e0b3e8056b3e134cb1a10bef109f2bb783ee7f8dd0fa870cb8287543bc7ff718939229c4594834fab805180055c1fdaee425a417d4186d812ad1fe16bfd51cb058eae8cf9f2f8aea1038586f426340d9f56f67747010001	\\xb1725761a3b66335428f930ad39887f0cc68f4424292c9445dac6000da1742fa5736f7c2d78c2822d12c29ae3c6a3c9bd82c25fc5791173d8f27525a018c5c05	1647346053000000	1647950853000000	1711022853000000	1805630853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
43	\\x65945550f8f5b4d4aa21cdc10bd04672cf7c48bc193cba85978951ec68ce604c6caf0b5829e140effed30b7b6a0f7665253c2dcc03652a9c7f97bda99b3d8d6a	1	0	\\x000000010000000000800003acc962674f51b975f561688dda5f1a2c618f6655a7afee0dbae0e98b1a5cf68179335ee3b92e01ec700d85886cfdcb4222fcc72bb2e61fed251f49d8240d660492fe7184df0f7400516ca611d928dfa7bc377a1a71c7464671ff254aacd0dd6c29b035b8548af97934d7b8cb38c2dfd4d6a6a181437794495fbeaf5c25479b47010001	\\x744f7e00f9fab7ab7661a564962e0b031b8f0bf0c8840873f0b8fc5a0e50e80fcb676f0c727e4799d8ad7504812eeec1a0f53a219dae7509a3efef876231570e	1663063053000000	1663667853000000	1726739853000000	1821347853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
44	\\x6ba4bb15ea30602db23ddf1a6bbfdce10972f55ffdd83e2bfd401c67a4761d87f046dc32b098e2a31afeae7fa4c4a35f4183c4ccf267061623df3d8a3ef808ae	1	0	\\x000000010000000000800003b5018d6e6fd0e2b2ab9e6da5c4e944e5785d0ac3bf50c8d4b99e787455aab4a401bb3a87ebf727212c4c93fdd340a2d9f58f7eb2198e965faa100a928a147776b97e3f6192a0782ede7471fc548aefc2f4c6792df974e2fcde661ff9c850e979420d34ca3b529652026675f9f07853f4ba5648e068e401194dc0b3e8d73e03ad010001	\\xa869d1bc3ef19363558d1eeaa2fed634b51d77e36d32880f6463b22899b5fb66cf63dcb2eeda7269ec5432cf37b7167fd7d8eed0b21dcd29e9060324b597b80d	1648555053000000	1649159853000000	1712231853000000	1806839853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x6b9c4d7ccaa29c21ebae4f00deb753f02aa4887bc9ecb7479965323b8f17dd352b0840d6c031128b6b8dd0fc370943452a24668bb6524ae9ee94fb1bbfb61c2a	1	0	\\x000000010000000000800003ef9f65b95acde236b6f6dbd570cf1157b212c0ed9d0af61a97eb7839610b525575a51dda5ffd41d543df2f0fad052ec2f04cbe2c762bcff511f8840d04091544f9569e77342b4bb3f3b825eb8cfde345b8fa730fdfc233dcdda1807fd57489fcd8456c5baa88384a8ed033ec72eeb10ecce1b73148f1c16325f97c2f14247b25010001	\\xd383dea583ce84b5a442b7149e5709e8ed375cdd80a650efb8c8f6b60fc176f0709d4773b8723958d711e2fda8ce282a32427e39bfacb547b215d2333a3c4501	1672735053000000	1673339853000000	1736411853000000	1831019853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
46	\\x6c28f89e7f811c25cb9354501c93261df2e2b7077964be6aaa5eb3609746205422546d6e64abd8a5930e04fdb8712c317fff1d413a9906888504432d0aba6796	1	0	\\x000000010000000000800003d5fb782de7fbe4ce2a17485215a6b23a26af9c7ab6450098a343b5afc1f2b2cbc10212c18c21867ed93d254759ef47b07a9809caaddd54a5588d6a73addac4a8e8b1130267db00374993942bc0da174e5bb9da3b7b6a0727bf28363908a90713520662d7ad2d4961bbd0296f48e47975c623ca8326090699eb8f9f8e061a2b09010001	\\x9201faa70ab30117887f58d5083a7fc80367a9f1afa6454bbafefaa964ad8560a390aa1b258dae0f9de665a0ebcbe7094e450ccd07fad4c2d44e231b3e3aee0b	1673944053000000	1674548853000000	1737620853000000	1832228853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x6c80ff91a6d0dd84997cfaaf42ae572dabe4cdea2cf2391bbec5e18b49f42189b2d7f67892998904a95944b96d26321f034bd5afbb21a914fcb58bd12516deb4	1	0	\\x000000010000000000800003b6c12a149ea057be6f37cfb7f58e361e27541dc6e83a74292fcdde1f697e03263045b9ef254936e6ccf752b7f371375d900e51df15915e22051fa37540799df9ea315f62c76ee191147237f0afb882d6789208fdb10c4fb2d883bd4bf2e3d7a5957f45014cdf4dce2cdaf3e95b58f3cd36fc3c7c487ad9b6abe38dd813818581010001	\\x5eb1a503ad0dde6f2968a5e129dac4c2c40d5b89c9b544d8216840c9d45aa1afa5054742796a4921228aba13a99a38222e42ee36803a2a491e45d1845fd68702	1668503553000000	1669108353000000	1732180353000000	1826788353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x6e34a4f65849241bf616b075e360041a9ca4e0cdc2b2b6bf3de11acd2c9975e7704caa3238162267167ecdc309a851e633ade325f889de6ef7984d006ce17daa	1	0	\\x000000010000000000800003ddeacbd0f7f4d26f677a614a275640da56a8cee3ddec0589c9ef932d9ca5e695c971d0d218e2cf4992a0dbc3e52917562959cad5d6c45a53f7884f791975c4640fd3495f74837c2d83388fc28e9a07f61afe718f23f64640b170b6ff6241ed832ed486a5e8f0f4d1a7629b0cd947afe108be61454280a449a46be81adefcd149010001	\\xa98864f56d5cf8760c97bde97ecc152dcd39440f6da38f17ef147c57c6d71dae22ad694bdbfd46935acada875a6ac4ea1e859ca86ba98ff07818b7d27ec30f0c	1669108053000000	1669712853000000	1732784853000000	1827392853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x6e4806d9a33cf6947421e4aa4f336da1fce9c13737ad655f01e830b8e1417f6b75cde7d6bea0ae61859b5ef2a0ae44d1bb0b926fc169fd9cd49a1a86543024f3	1	0	\\x000000010000000000800003e703e394cc163524370fefc474e92ddd7b50093d366a856356169e1b9b6769877efe2deb2ec34227487fc5853828e9bd595d79f9e8c7ebef59020943c7355f3e96b4865ca73269c69961d333e851136ba744f2aad84798c0ca10de5011c605381c625892d84e34b6bdbcf1f94cfa128a1f18d559edb4a2caa28550cc50697f7b010001	\\x6ee7fe93f79de46293694aed0b42c62c43cb8dcdb7a5c8be06b791add8095a0e4bf7579fbbb8bdc3ffc2f5440de9db897b941650af06f36b111d77b548f8d708	1669108053000000	1669712853000000	1732784853000000	1827392853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
50	\\x6fccc53273ad06badfaf3b5834a615547f114e78cd9358c2f2dbb7c1e478270d9d36f7ad6c380336b282bb45ed8928993432b0a2d7403068ea118285cc9986f5	1	0	\\x000000010000000000800003ba4ec836cd654a016758fd9e80b1f767684e361b82e50406605e9e58cbabe3a2afd7f4a5d14dc866819ac6af76aa8c1e50e58802434c6d36bee05c62be6ae5dc315522aa09172b44bcd68d9040201c7791532ac52bbb9fe1ddd648718c06ccf41c8c1c1c7fcb682497bfe789349e000092848a1e022e97705108442f008a63c1010001	\\x4b9f53e6592c0aa95d0dc98a123258466b8de3aa1ed6994aeb28b59418c32031f933a7acbcca94bc946edf85ce9f6c27d27500bb34be4d2c839ad929ec735e05	1670317053000000	1670921853000000	1733993853000000	1828601853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x70d4abffb5c3ebe8d8e5f8c07c845ebf6ff2f30734b92174f825e129bafe536b5b576116a50f396e11afd06ca23eadbc34ba73b9d664c3b232bf145878e185c9	1	0	\\x000000010000000000800003cfccda769f8b0882d078bde9b4b476a963dc4bb0e8d21b6e49b3fd6162eb0dba613d2478182ebc28988be4bd379677b2fee004ff8512567cd0bf29346524b649545a9fa3676b76570608472c7742895a9038f472174386549e2fb7bb68cd3c5a3b94ce7c60e0b65e1a7f3c8388f83e73c22bed8df27c6588b642eb41e6e1d9fd010001	\\x4a9eeb7b7dd261d06a237722c888688a155e43c7518db61047a86f5be3e6fd97572bae5819b8b1b8eb057c45a9efd34cb6ba31b6f17020ee7c6da2f03121160a	1657622553000000	1658227353000000	1721299353000000	1815907353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x7810e8aab2714881c0a9533ff853613670ac410db6b7a6212c9e19f0c3fffe90759f8a3ed751da439b170185769f712bec4995cdd17804184e95df09dd932708	1	0	\\x000000010000000000800003cc8182a24a7cd7dc8855c36927383a5870899ae9fc3dd292c383508def39c489d6be40e01b3472b34dfc39dc50321d995a5b7973d13cef084485e235d0311c4c7f90657d5d63a76fd37e70f40bf6e3b53971e86b6b3450e45253dca4167107d958ca9daa9e51a0631d6a3c7817ab8e7e42498912d1918e23257a3c5848275aa3010001	\\x4c08d7e6a3afb103f779782413d2b2c8b74976a47f5fc23d27d22005b94dfd63ed60fc4a8c451949fb63ba59c2cf1f4ad70fca698a4855303d17778437d80a02	1659436053000000	1660040853000000	1723112853000000	1817720853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
53	\\x79d0d1ece68c39a49f4a6ced385c7d030b0d29ae0a9383bd17692ca5621155f979c80416e89f650705e8e9cbfb87483b467dfc36853d3c655c0f1c6461a9b913	1	0	\\x000000010000000000800003c03357c5f612a01bad25afc4f33772083e2acb36c6a7ac3080629a91c3c48273d32596fdbdd5be044d2c3d18f36359d3870e78168839b8bb4da157f7aa1e32e65e6d990435bfd5c1aa7a7dbc782244cc81e950e8e64cc55f5646592f0fe07436a139fb0b25de4bca942925bcb7c0c19d64a5407a0e2660bec5f4aecf0a7710c3010001	\\x84773f7d9dc4676a6c41aa935a183f88102d37d54f071c0c0603be707700b552c2a072504c7f9753717052f93392bb6610b5c808fabeaf0f9aa6d32269e6460b	1667294553000000	1667899353000000	1730971353000000	1825579353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x7a1cb79e4a848565e1127a0ef9c123df9c3967fb541d2ea37dcd85a150dd4cc69079fd7cdb31ca70b067bb38f20d31d6d49c4cbb082f3d6cf271780443de415b	1	0	\\x000000010000000000800003ba2e42d9660675cdff77b3cabea3332c99467354ce5fc2d036752b4e4a72ad9d01e76bff0f1a47ce63ed834cde7c8cebd7e65fb3b58e8365cf391f3d48cd75ecec0b82a366d0baa263878514c74df35a4c1f57a691ea7b58bad4f2ed2ec38f5b17a0a213f9079655f2289d4737d76ae4ba3fc4a3de276a79ef195e81cf497343010001	\\x93ba229fa1696a4c638606e72585f2adf300e2d8c3c599dc2c4d5c65a33d96b5ea203f6836ed48afb960e4d2f0e9626fc0e360fca6f0efc4dc9ff2e00b288904	1656413553000000	1657018353000000	1720090353000000	1814698353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
55	\\x7ad4aae7be4bd8facbe89815aef4c3bdf532e0302fece5ecc0a658965f10678544f5d1e40f0fff71cc54c9b0602c61dd7925440f8116cb7cf8c48dc2015a4bcc	1	0	\\x000000010000000000800003df74859eb4675a4bb989d26203b74879d1a53b915cba1b64b96e5feeda892eb52951fb23893618d547ea7a78153484d95ecba5175b86cb775e109cd484fd3d462f6b3e0285836cb70dd3074ccc4746fb80a346dbf22be0451daf0793930f554ef7dd0028bb44f4ea233145a1cbfd4d16b33086e0a883cd8a78303095328d33a1010001	\\xa8db9e97af47cd929ad0546d9a2bce8245a8964e55e8aad869714308e9eafbe22ce9cdc18bdd57f69369748c32426db70759899d912ec8168c68133556310d0e	1672130553000000	1672735353000000	1735807353000000	1830415353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
56	\\x7c3467d2d87c06962a86f056c54117a3b843fba040c44bb9facb0bb391f342ce1b3e4e085cb3837ac094539c6e288b34c03aed950c64981981459685c2d3ba67	1	0	\\x000000010000000000800003eb119bd741d9e191bfd50ab5eaa99524c44aa8c7dfcdce243c45324a9e2a97189b0b8653b4123e061995c49dc106e658cf64eb4aad3a2e237e779c5262a8ce2b49d9eb9dc286b72bfffcf0f4388c325448cf37194448981828509510d400b40c93edaa21ecf512b380734f012dddad76805b301a353321d1f3b39517c56b7d99010001	\\x71e55a49a923c6358e7549e5b6bf3dd4c476777563ac87aadb9ce66e61ff40beb21a65eb7ba59792f94f2e7723af23c7b9bb0e35542a3dc34550ec4e33ca080e	1678175553000000	1678780353000000	1741852353000000	1836460353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
57	\\x7ec0e26ade8f8dcfbb01f62a5c71fbec2746be0dd93157faeca3af382d8f16009cbf0fef811b4ab888986457eb4ff782722d4a9aa0d487d794adf720624a83b5	1	0	\\x000000010000000000800003c6cff81573ab95cf5cf6ae3f72b0054de7b6906d5838119d28655c049f4ec64922dfc913258e186cecf43a9cbaa485f5469498a4db7fb9f7fbb7facaa61d07e0cbba6b7d58a87b298c2374c8ad3801f187c36aa876ed5a2e40db5835287ef7e11ae9a09c69335def28da05f7b4c5c897b1f9024dcb38d65f9c26943ae2649027010001	\\xa78c710c8bc2f4afbd8fead08e7bb3b0ad2c9bd76ca3b9ec31ce8db8f07bd4e7099d6e4140bfad89708aa8e40a9b8fe7a953a49a7de6943812eac789f991af05	1673339553000000	1673944353000000	1737016353000000	1831624353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
58	\\x82d48f7e41fbc2daee130da65809c20288cb64bbb9c0eba8bac81262863af76a8b55ff5def8b6001d501c4bd32a27b0d2c96ea9ec2a6982085b1481b36473764	1	0	\\x000000010000000000800003d19492195d1de1f55ad5bba9ffc9f3afc94fd06751cbf3a69f4de8453d817b9ad0e4d4a4333e24c763ee791b3b84d0af26962404c2482f19b571ae6a815afb385cc8bbf73dd57944dbf7dd4943c6e79ccdd2352c442ef4f63ba4f97a401d71eb403a9fd4cdb8b3bccf04ca0a51290a085e984c68d7e56331c71b5336df5b722b010001	\\xf6626c7d9c88205079a12bdf5f26f4bd68c2ae6779bca5ed6a700997227820964d794275a03529030bac94897fff4067e6aa5b04244f0e6bc95b2180010bcd01	1678780053000000	1679384853000000	1742456853000000	1837064853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\x82b8916fc325233ebeed86bc0142f5d32db82bdf4262d8e0ba8353d1e16c5a5ca39d5cf2ffbb1a2145429cbbf60c37af46ed8b5ee54c90dd3e04016abc9eb1df	1	0	\\x000000010000000000800003e4364e82cab1eaf744bc5fa0989700157e3e2f1e3d9f0ae93b9971f01d53273b127a6b09f5b54b1d3ec77129aade0993f40012d97c4a8921ba9f6948920ac452872788e5b72eb0e992ec6b3107b58e008c2960a69da5b286c60d1720f74f9b75ec59ceb9089cea861e3eb1c2ba26c9c1ff2a7488f8d07284ed97acf3124c75bd010001	\\x6b7c563539712531bf1f4ad2cf91fc1cda69c0d50eba4ef337c83249662447075f4554375325501cbb5ca14679232add85ba178611c2391853d29c1bbf4f7f0e	1651577553000000	1652182353000000	1715254353000000	1809862353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
60	\\x8328f86e8f12e5b1e2e956c028d77805e7177d44436abb51552e054a866f831c27c111c93b62d74290f13ae20f816d042db8b7c5b4999b46938d7113e2f6779a	1	0	\\x000000010000000000800003d302efda1f79fc5bdceb29681983dc372ce4bb76cb112ac41d21e33e7cc4d23b8d834919ef5d792e51f76362cec26d075b1227ceb144442104a41cda3bcf0aa53153c7a6c91734ccd8dd1ef18092ecad6176935dd159f9764a9c3f22f4e17a8c75bbc708099e108d5339252533f8efe90b69ccfa26b1a8fa4e50bedfb81bfa09010001	\\x71ce75605c3606162f8b4bf4638cc0db6cb805b11432b9904c317380891b2a05c2aa1eae782cb7734f8d5bb59d02801f2cb8699ee769aca4938bc10baefdd60c	1670317053000000	1670921853000000	1733993853000000	1828601853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\x86509ea102ca5510bb31f0ed51a46926cf87da9fac8bc0301519dde90ef6dbf6c3b67063e60d9fe5f36e10b32163349e5b7a8198f393d7b9f729113bd528a253	1	0	\\x000000010000000000800003a639ee5950d27f9cb0b40193abb830dcc04d31d11d558c51d45cf91a9c591193414de05372795847dffd09b3ef1f235ebc3a6a75986653e0718cc06c88f16145322b6d767eb38d9e78dc4cce962e902c8ff77d242599dd41ee6872c93a184c5957cbcb3fd839ef2e01c3fbb738b7ade5d2ce2fdf24c160445555ccf4a56a71bb010001	\\x98b8c63e9ea4493ace01e553c6ccadcf5e648ef2f57f08118a8d5c6d2ccc52187371e41cc2ccc082f62c6c4d54b35e73e34adf94df427876d0cb9a9673fd7302	1647346053000000	1647950853000000	1711022853000000	1805630853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x9210a9e055b83c71a628a3de80bc7b81577623f47dd327f14860836e834c136c6d5c3b95930affb49313a40179a4bd422f8538c4414068f9f7ad368ab9e8f954	1	0	\\x000000010000000000800003fd8bb26fd823286f992bbae7cb8b8b78b42698354214df553a0ea7c7d0d103ab1617fafd8d62fdcbe3e2aee42b3f1bb0e1943efec10112578f290a7b6c3782d7b112b58b2e4d8f5a393b921e8029b166928e0f5dbdd6f620c5d3a4864e98897303a21145b16577f8b6cb9eda4258bd0b934d57d7e2dea1cd3397dbcc19d7e585010001	\\xad62e8b1c37fc76913d04491fdd58a804594bfb2ffa0978c002b02fc527861f567b957d372f232ed2e56485dc88e3f85a21773ef8795ae8f7868843a6ab54403	1672130553000000	1672735353000000	1735807353000000	1830415353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x95d0c3ed9bb08983fc4ef324c390f6c591f6c993c7d8c8e1b6b792448b2bebd6cb0a36052aa703370690d2d731a5c72306ca31ef790e5b58076857522cd897b1	1	0	\\x000000010000000000800003b1466f9b545350b51abe1279d38a945fb71df9f671b9757e357cbecd82f0cc287f18428efc0b1e446f30bc02d942e9144ec352725da4afdfe0c6a57948026d66b52df4100b656774026e6e951a74194b5a851e82d7c30654989e43a887169e58330d18c0a41d555e1b8b7600626e9818f0b55611fa217e7d86ed6aa0200c4f87010001	\\x3ddcec8ea3c6caae04d593490ace0323c52996478982deb17a8d2eb718669b6dc2b9a0c14bcd3e74e7acf5627d98880499ec2ae144aaa29a98c5a46046e9c109	1649159553000000	1649764353000000	1712836353000000	1807444353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x99a8ef78e85b7f4e56100b2c23711d522fa5b204ee0e8514079593121000903d1e004b36645e18059c33ffdf47052bce72902164fd8fa1a84cfcbb2e44cb6e35	1	0	\\x000000010000000000800003b1b43f508b99356560e951563b9629da6397982957b1c1e038d7e4b9e7686df8e2f3499e496d505db151acb5dbe99466ffffc46370a357b516e8f3259922a038b5daf01d45c036f30356dc17a36bd027eb260f6e5ff1d7cd2bf2dc860a6eba3cab6c7d0624ae7c65e955d5df0ac5fbd74304ecc1beb5c4c1b5a576321085050f010001	\\x1917f7e208df69e4ee2a9146a18b14c79770c03f109eae1450495dab850e6918ae0104c041ad2716ff69e118469bd24fc489fd9c072f272727e0cb573cd77a04	1669712553000000	1670317353000000	1733389353000000	1827997353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
65	\\xa1988b8a0d2d81caaf9bc48e4fddd7e017d6b32a62845ed4bf83517803ead040c065de216abc92ffc362fa05824a1f749cd7085fda1b248aef15174722cda79b	1	0	\\x000000010000000000800003ea6d96796a293e718d920a3e4aa3fbbbe078e182764d6a75e732b3f30382d82bc1c56708c6df06d633a5136d87e4521f51bed83a05780d013cd404106f6fdf6dddeb87e7374c90a053d4f8690947985be1f570ce0bd04261b2329e3674a99494cb5ff24dda650f9100a7773721bfa1ff6608dc5af833cffbf3736365de913b5f010001	\\x94d6e84e84c9451685d7d8ba20d9c0d667c0f420b6626a097d3ecd0c69ca2b9ff3c0003a95c3c9839ae56134b35f779a13acc11ae7496ca8a551bdbe70f9240a	1660645053000000	1661249853000000	1724321853000000	1818929853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
66	\\xa2fc8e046d2f4a277e9e4a7f376ba46097270abe0e7611bb56640496883247b67ca8b5d45832325cc03c63a6fa5642f3fff14c2f9d38afc845bcbe5ef7f92295	1	0	\\x000000010000000000800003ae54b4cdbc693b3e575f02fa07f90cc6a5e2390598077c75683ba3e0220e99b2e728a33b01fd319956a05ffa9eeb8b260f24e83e7c282adee798b0c71aa9cc0744eb67814fd49152c584c5b1cbb253809371d249f78915a9df750e6395fa9d141065bc6c26c71116a737e8457f9083f253b54c5a4edd50d14898a06885680e83010001	\\xc4981321c0f01ead579c18043c6b69df1fb87cfaa3a0daa55e273a227c15d1cca137aee7b609873886a8626d8cdaced551a0a07c6862aeb3885e33fe331f0d07	1673339553000000	1673944353000000	1737016353000000	1831624353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
67	\\xa210004befef21b5efe0625ca098f52885b50378b99e3db70da5d4ab1b1c4dd359cd4e1a3753b4f5993dc01426eb48b0b1c76b5e305909cf9404d5b3427d2861	1	0	\\x000000010000000000800003ce112ef1c499bbced940044dcd64206dcf6f79f127da793ca7c3831515db122736ad373e5b103bff2da0d1b39dfafef7f36886e13ba8e60d0871c6ec512fc68228444ff07c75178c71c31d7ded7b6dab5b3f58cc167ce3183f9571e815b6c2537c289a10ddd905be15796eba797aafac95530c3232dccbdc787995c43647b3e1010001	\\x14de2065b0c08880400add6e778ca0ce4be30402e7d497785dd559422b56fb55b67dca7cb58e958a9ae96fac7621b78a913d487d7508309bb21b0be6d83db003	1663667553000000	1664272353000000	1727344353000000	1821952353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
68	\\xa3b458d2588fadcacf7bbe432feede38e296ec932a01747ce05c530a539b2487279e87ab858592de6648a6e0aa5f0e003e05ee28373ee829c2d907d74f8347a6	1	0	\\x000000010000000000800003c26ff74d5a62e155d51d701ad6fde0c23c23a5f74de7d696e446dfea44c689d0e88e50a628843c2aba8e81e1541667a9234cc813807a98b155e6e0ad252531ce6ea82a9dff42d798439114e8c902ff8dd7ded6a658c31798f1ebd9304e9564421b48854cc9b58a10552345969f2f85ed77a89c0a84a5cabdba44c7edb762bedf010001	\\x252a3d2149000e874ba9fd733e16c4c7471268334d04a66913152c9da57b818f49812b583c852af6fd291425ed8f086da05799a0b8516ee89e8eeff7d54a6004	1658227053000000	1658831853000000	1721903853000000	1816511853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
69	\\xa4645c0a2559b5e6616d94807f6890a8341ec1649d56c45f2a6ae8b9f4b74df605650d36f36e57b03c81654b870588e43dda702e0f83a25b67e8570d2bf79f7e	1	0	\\x000000010000000000800003e0873fa95a15d2a13c20adea7a8eddfbfaf363e24f2a3046b187a2c9d13425de128e47eb0b9ffd9970fc8c06ef45a4b27b91a8380ab62713f9b83fd708248962c290014cd075c3ee9032ab4bf3e6270a8d8d47808b47a8e027dc2e12ef7fe8be506fd3b634940ce7bee8dee0d8cb870d3ecb0eb6147f043e04294eda9d868eb3010001	\\xbeaf585bb5bcc1459197bd7d18b0ec2b1e59b4a22753d11b6460f98205ea9490b036e57f50d230568311b80ccd953f73c029edb9a17f7711b499445da001860b	1658831553000000	1659436353000000	1722508353000000	1817116353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
70	\\xa5e41e11ba2af4ec9a1bdaa7f8633d95039e11254f73eac2d19d5f9fcd0ae2a3621fe78b9025e587edf561b8ce5bd511c90c383555e9ff4e9a04672e6df3829f	1	0	\\x000000010000000000800003cfa0c2eae67e428cd363e298b3e63adc765288b1089bac1af381ea4b6cda17254bda7db275b2985c89ffda5a6afe246302de1ea73cb6e3fe5904676e914e998e461b07d341c4f34d773749a714c937f2365d7bc42a11b3c682ddfd5071a432585a7ff1ba9df82279cf4802337e9962d72ff46f792b3392fc9c37b3129cf2158f010001	\\x2b313ee5b093f3fe2fb704d94fda8d8490a931c6e12c7a357d79353bcb3244673aa9801e802028860bf13698c8aee60fa2ac2212f463452d2cbaa72c9a0ed402	1660040553000000	1660645353000000	1723717353000000	1818325353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
71	\\xa56ceb3a0f8c353551a9893cc4ab08aec66fabbd139ae089b94d8fe5455690aafe9382902ff765d9b5245d5ae868e03648ad06d52fe411469ee3cfe18232f301	1	0	\\x00000001000000000080000399dd7245341359996a415c6db50ec605724d759e7712d9bbe55252c846db75ec0aaab2da210a4c07d490e32a8ea3dd1cc272009ab4e9fedc2fd9f434d48b683b96140aa19c78578581fc5e57334d6f99ccf4c7c6bd20a4f1fb1a46e8b76caccbe5b248da1bef96360a326f7ad8a4631e00e90e06c53618899d39c37f37548d35010001	\\x9071be19eb7eac32909798cc0e2ff5c7d6ec9d2a91862e3cad0df51bdbaeaa530fa032ef9c28871de2cf02a5bcb5e2f93e4422d1543963107808e6718024fd03	1660040553000000	1660645353000000	1723717353000000	1818325353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
72	\\xa710afa6e0f7993370f308f8e235376dfa8ae6acd09a8c3428541cb295533a105c9ff6f16897008daaea42fd5d38fbd1c41a8a77e9a0f8bf85ea31dbe65b5d02	1	0	\\x000000010000000000800003b656a5cf0d6a822ad88d0b6471fb32108ceef088b5a609ddc01ac3ecf986fe5b72bb4e0573c10bf7688415a6d8a31ac210fb50dadfab10756480ede826b9e711dda289fc4f08a014f0b95d03dc5ce5445a64e50f8d22296b4c585d1a9adf6ae6174e854fb329e1737e8e34ddf34c7987308973269904a8623591ac82e15b38ab010001	\\x687b916230ab911650e388d6d829ddb48961a1ac05ca13cb1a42316884fb46b8f992cd276f4b0f68b433f956f5e6c51367ab9a32663fc78ecf0dd55721a53a05	1676362053000000	1676966853000000	1740038853000000	1834646853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
73	\\xa760cc1e0ddf0d5f9a4e8fd7c526fa95a34630491cd94b32942deef2f1fc02d195a8994dc85c79a7ffebaaa187fe48473b3f705420e1217e34e57f94bdd3ca79	1	0	\\x000000010000000000800003d3e7457e7a8ae6a02baf919df5dcfbf1cd29f0e3b4d234315f0392af13caf44d78330e03da7bcb7b616ae7c68060e4d800b290c1e1744f8374098f0ae337817452fd522bdddb7f493eaf1bb79c322c86cc831f4d6a83b343b1667fbb4e1b808d88a73da03e18b6b55ad38f7436bbaad2a32697e1acca4a61216214988cad8c6f010001	\\x30d4ae08e26f753d53887247221c2845902581aeea0e71b945ee65a1584a7ef32ecb9b9844db963416746adf1de214d909df1c13fd3b9e2fa5e97d9dbed8200d	1663063053000000	1663667853000000	1726739853000000	1821347853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
74	\\xa88c9ca7b35f84e834edcb2e2099079ea9066052d4eb311f1c834ffe67bfda7ab9a2087fcf156412b6fde28e521718aed7bd90ff2f2aeea25abd8adc788fce92	1	0	\\x000000010000000000800003ccf7d0522b1e1b625186ebf04e86c8283444f7b17cb9dfc2972d0a3fdcfadaf9a9695771e8e6efa235140a46e6a003eb84a5724ee773bca4b088865c5cedac46622d4d0753a3380f6a064336e63183a71d00742324ecf6a95f280c6a36c7cf9acaba2319e55f8ea956329ff1ec0ba77d674dfb4e3e8f3e2a4201857d482ca92f010001	\\x6479927dd3348180df1fd589d5a369281f452afd7b4f138c47e2d82e6b78faa253ab974771accc88684a3be80417a2db813ba890ab7ae3b031974e2ca8e04405	1660040553000000	1660645353000000	1723717353000000	1818325353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
75	\\xa9c8dba89d4e955b615a54967d31e95bd4a90f6f40aa74833b37dbe3da95e2fd473750effd4d4ef8364b2ffdc8a052eff8c2449f4485fd7afc1c0906dc0f3b58	1	0	\\x000000010000000000800003ac23136d3c6f1d15600d5d0a0ffb6d72b6a7d7fa787d917ec4b490300877f702bd0bcefd0c069ab17b721f9fc3db11119fb9fe6b03af23ef9610770f0a3f7a77b7294b48cbce53f946b46c9913a4551bf9f7a0a125b53beccea8a62147acf8eef37316332a0a9fe96c6e52bbe72fc65d1a02a4602c90ee3af77f60f2fd3d921b010001	\\xf806d1250c09d954965ed059ac103079073a6d191997ba65a026d5aaeb65936f17487b297203b641c65fe064f36a3ce02982893c11b51f8ee383c7d4d0c08c04	1666690053000000	1667294853000000	1730366853000000	1824974853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
76	\\xa9447d68b0c07f4a1f31cdc6f81dd6a135b376a179c08fc8af6ba2e1b7998e9561b67e22d50d7aa583cc7677d8492a403583a4c19ddd21c8b164a9191cd10793	1	0	\\x000000010000000000800003f41819d6d7815ac7acdbe0fdb4e7573560b2ba88f56a9c64c17df0bc6d676091d981d0f325dd7cc7cefc0d82e485e259b35ecaad334b19c1a11efed0229d6a2291f308ff0f385d9214e9adda35b9e92b071094c230f4b5a8cf515380df55993058ee7ecf9f947847e5253b3ee6d1b99a2a0a2a80a5cbdf011f98cfd0f6f34029010001	\\x6684cbb23a755cae9190fff2c0caa3e135ee3bcb5b5f495b80c04c832ad3ddf257dbe88d959c3d5c07704efd7c915a0bccd3fd92c63018c893b8994786adb904	1665481053000000	1666085853000000	1729157853000000	1823765853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
77	\\xab301840d467b1eae4f7b1c826097a4e394ffbc7aa589173b0d453cd0a08e8b8b1fab32cf99788f340d128298f298b30b1dccb49d189964f4c7321c3209b9ff0	1	0	\\x000000010000000000800003cb81625f42ae094d53813a7b50d03d0fa63a1a11be687b9bd6867dc316a48854cd9122f39ed183a25d12cfbcd027977ba43e8b43a827026d65021e213ae0236188b4b50b074889f68a7051537a2c34dd76e1e25067786d9650360840d244b141d4538e7d07b58c2d94329a5ef92626f6a9aabaa0483abe5d96bbdbf323f2088f010001	\\xa0b0cb8fb54f4fb0ff4e40157ea108b14cae79d13863cb1d1939a885659a23ee500520cfb4c18d243d6139470ad782b586ade358695d9c7b8baf361589a17e00	1676966553000000	1677571353000000	1740643353000000	1835251353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
78	\\xaef4dc4e9d895fdc36c1fca83ecddc5f7e4489b7615cd37eb1e42cc2d1b0a0cbf1f73edbd8267ba63d580d740a9bebd60b6508c4ad666002aeb0e8b28bf4083d	1	0	\\x000000010000000000800003b157a00ae16b45d5bf69a68e56f4792926635948fecd045aacde8706259f99d99ad55d44960e44334cfe17e27f79029d8f51438918199f5d93a1ded92206f6c6d53c474cfad38c10b272bbcedae92652d7335e2f5b86005754ec195fa936d8b6db0ebad09aca2e478f66663482fed364fab5f02d5bda919244fa1a9db090bb27010001	\\xc49a27e2128ec56aa0103bfa7f7814b91ae00f98df014b0c616d2af9dcf7349df81f71543cf307cd8a0a38de5c47d8461863a15c64880f8c97131c037b367003	1664876553000000	1665481353000000	1728553353000000	1823161353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
79	\\xafb8f685466f70b9dcb30190316d517dbaf7bfae25b1e0b401a99ca3e85485f9dfa0dfb4a0315eda4152b2b8ae5a4c7379627b623c5b1f220704b87140f0ee97	1	0	\\x000000010000000000800003b3723fc84a4adff2f10c59181ce5e41c68948014680d5b91792bb265139dff6ee0c776cc41484cbdadc2c0d34f51a8f4595a3c0d59f76c68ed4818aa50d9d8a0f8fa818816f99e3ab413879f7085eb1c5ddf36d85723cd816427a175466c8b48deb3fa4f7b540769347a8f844a5bcd77d36657bb1586ae0aa9c16ce2643b44dd010001	\\xc2f60a48f13cd19399a8314d67a1716a3330d3f44ff825f11dec8ac76504845ba3a0b5ae88d39a375c897475a436f3050cbb4a44153c55c8da508b565207ce0e	1670921553000000	1671526353000000	1734598353000000	1829206353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xb0ec062250daf3662d5259270c2983136fc5a7990a358438bad8137df74c7e4ed1295ddaf77fe58cb0b33405968171b954c9428c697ae1fc150408327153fdcb	1	0	\\x000000010000000000800003e99b4e734888c02dd92f628fb80c8b82567284f2f8db804c40f771ee85c1cb8df6cab4450b9d8bdb06d6e2302db5d861a329689cf0addb46b64a8cb1f39ce93d5e90e09c80402fde4f47236d68641308a20eea9c59160699e8317c205c2bc4b7d9d821ea326059bf3193bc83aea0ed9580556a829e23f6ad0931e006ad881c07010001	\\x2730602efb95be6bdf5e56c82e57a66f46b51e781eeb2c3bbe329b308c473c09260fdd2819521fe3facc6e997d7fe963f8c58aab82b8fd3b58450f81255b6106	1663063053000000	1663667853000000	1726739853000000	1821347853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xb0881e2eca924a336728e467b984dc243fb870e80f8b06e46ba99301ae07d49e7bae6466612ad0c7c148e4dd8d5558c4244aaddc9ee076654c983349c9c09dee	1	0	\\x000000010000000000800003e4c9385945de6a67a8383f00468ae85f01b243a1e3acd485c9fc521ce97b6ca66a4a506a84702e9124741d3766c4bcc93da0fe3fe8704a5079b7ec579134c1c234a55c030a16efa6b64b4bce22e0b08de8b088a97a043953e41267e1cb05f1cf6dd99c98e6ea6f007db79b664a64c2a6943b60dcbd5e1d4632c2b435218eed67010001	\\xbbe7aaabc1d3d87514d49b43595166b90c59285e7d1374f9cd5560ad79b0f49bbdc0c3be344cd9acabbe20717e9e8947a91fd0b3dc11669ce6aa58bfad21ed0e	1658831553000000	1659436353000000	1722508353000000	1817116353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xb1ac29b401872b17b0ad8e02930546c5effab3147111f13edb1b8f33f743ff0f62971c65cbb44a8326a0157b9830426005dbfd956c069098647e37203a5310d1	1	0	\\x000000010000000000800003cd10607790b79dfca5cdba0d668b44b31e949257522e8696f4aa9e39934662e1b0abc37b8a77a2b508c77a90bccd5cf3f45ec9c28feec905a6f0f912f2bc5ad45cde0d4d756a26d03eaadcff3a2203fe64408ad679dac13a62c0652c20b491cf3d0bd9679e7d4a0f8be9e6aa885db5a783ae3b017197778cff513bc5151a24f9010001	\\xcc843a525b556ecc73c5d5c8283b6f1616b6fa8ad3a923593b0f0d75c79b2f7a208f719c3960ef56f71ac8f9102c47c6c875a87a1a28867064f76b7bad7bf10b	1648555053000000	1649159853000000	1712231853000000	1806839853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
83	\\xb27c886083b051a3eab85a5c2b0327418351f571377d4a7d1aaabcd3f8a886aa3a5a2dfe5c63ee2e908d875ff105229931584c062adccf697cdc676d861bd1cb	1	0	\\x000000010000000000800003b5a24422794bd7136ba4dda93a5f2bbabdc493d163ef72acef39f00f25d6f0fb487e415a56d8a89b089fcb482026f73188149de8f6a2b3fcacf5eca408b4acfec40d0a2bec751e950e9f93f8cfa892a786999dfd3b8f85f8792ade346b5ba5a5a180d476baf02342636a54349877650ef7c4b4f8a6cd27469276f56f9b934b1d010001	\\x93e93a25475c4fc8aad97710b36461562c1e724c010226127e4238d6463a5b31c24951ce28755e9f66d5177219f6e64a5fbaa2a5983d46738f39b9ab08145a0d	1673944053000000	1674548853000000	1737620853000000	1832228853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
84	\\xb3a8dfa6c13c01a3eaab8a57a0b50845acacd4baca6a979a5b889b830fbc468e60fd23a994226a275867814a62f4cf9efbb1d3271f815895992aad502fd2c728	1	0	\\x000000010000000000800003c7a157d15f2da7c22458cc7a93109d637ad2877a9706f1344a4d64a3d44d82425c9cce2f7140311a221e3188e0bd34ee97f8cde0a4f6bb04e511ef3ee3d814ed6522682b109fee92a40b0ca36c3720c24f5e65cb0b74805e1074921bc62388ac105f42e37a3a1be7d28703b7e9f1962bbe7afb40fbbf6cb2d33b97121df7e625010001	\\xda9ba1e6bc06bbe5d239227999c250b86820bd6c9101c74e691dfa92c88e6c26ccc29a3f53fd0eab52bb2ccd886fc5409cdc01cea9d08a20b0f0a05b441f8002	1663667553000000	1664272353000000	1727344353000000	1821952353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xb35045e749d378809a79e992de44579ee7702003d4fa238c4cacb990b129e8d211286559fe68ca3774a301089302f7020f0a8b2123dbe2fe47ddb18765fb1c33	1	0	\\x000000010000000000800003b9715503e9355a810e30d4058690e46a13d90978ce090c836eaf1579f63a5c0379171b50cc0e367b16ebabac101918a8f6400529a4cf9e0b2e60560c7b6fa536729142453854cb3939c4e43ba0d0d83771f5e258c9a672a49f678b8dfe482e46bc5f8a03f470d7c5f898641082cdb74fa6b25dcc9140c4b749352348fecf2437010001	\\xe13ca981e7f0655a518a31bf7eee421c45f873733d318d3d38cdec58c697748d51b18d5e3078626c3dbbc5c9ea5aa847b9f885d6d16a0d4005b0bab613715108	1647346053000000	1647950853000000	1711022853000000	1805630853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xb62093d586b1f1b63c12821a7ff921fc04a6240b165b6859445435c91a8d1bd6b0d153b9ef15865f7b756a15f6c622dce5b5bf33146449b8c24f51240b162a46	1	0	\\x000000010000000000800003de6d4de3adec633b1da0960eb3b41f6a49496ab051674acaf50b3584add206a1583756d1b6d20cab18dbbe8734780c629cb1debaf0cd2651288caf2a43572eecb96f14a09c63535d70717cd0b386b7b77373d8ebf5a082da2383f4fd4fe60cc7fea52f14685cec38d56ded549449c8e2d0fc8a185766e667eee1b24a939e9399010001	\\xbf70ca9a5d1c06295a1637085edba24be115acd389a69580363919789fc528849a180427badbaf0a2cbe69ac4b78474978d793e06234b759a2d8d9af7b6f7e05	1678780053000000	1679384853000000	1742456853000000	1837064853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
87	\\xbbc461cd8d4e05a665efafce579f985a5fa0a13f0810f718e7d55d23e054763644aafdeb87ed0c5ebf49edb8ccf1f94fb39e5d14f78861c595e4ef43efbcd93d	1	0	\\x000000010000000000800003a78abc136938074ab1bdf34702bd002617fa4f7506dd493fe96fbb36b76c26b30ed16dd900690531412f4fedd58618fed3c0601801d7e5989699e2ebf2838c710df48b375ecc5eb5d71417ceb8ae147c1d5c0baaa25b981a372a3ac3f11f6322c32447142e672e4ed4403773a7a5ac2b2ab9bebc5c1e9a091d4ae4cb84786565010001	\\x8db3b7cc13ab79feeeac6cd2d7c821c09375d7e41c0b6d5456c03e326368a5bc73ec0b2dc10f586078f68ede22272c5582a7807b4c5a6c71a2b7c10b4037a303	1667294553000000	1667899353000000	1730971353000000	1825579353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
88	\\xbbb0de0ed4655c4c1bfb65b3e6d10c6e6a90c8fc101f5ad9a69c0644cb231744955aaa359da361d4846ab3955c4f5a01ca302551eb184dd7c391f819961d335b	1	0	\\x000000010000000000800003f4ae338f11b80bf8ad58b8c7afdf8f950cfa3e40c27e51eb905b5e2307677ab5d3c6ee855ccd6bd47f44e86ab9d5e67b33cce1ee14eae096cd76d6ccfe2668074e6a9c177c6223a0d59d0ea7ee814b74e2d2f17ccff9421099749464720a4dbe46318d3612295331b94e6dd2bea16624cacacf63ff26c2da043d6887b7517839010001	\\xaecd482d16dedbc2f85b44a52f9ee7410240d6b0425a4c47d2ab67f58e80e03210aaf41d53d45c37040ded5e9863dc5d67433be1388c5fa0c207991452a41b0b	1667899053000000	1668503853000000	1731575853000000	1826183853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xbcd8d6676f8540a8e63fcb51f906a6ede4ed7520f44bed32b02bc26dd8d211944932adc9e9b3ab920b05f69a767d9a1fe31ffe65a6e0501836e4dcd45205e4b2	1	0	\\x000000010000000000800003df709446df848c5c521cf072eb9ae7bbfd03539ade89acac857b8a6df83559a7afc0b1ec7f444782fdcf4469113d21e501194fef589a2a116dee125694316f42dfecf47bcf6e1d21541d4a4f9715456016662e68acf1bb132d5bb7db03d418a6e3edb9a143396a97e63b9c2871a0a57ebe1cc321579050648f5b86bcdfadc049010001	\\x363da4b862452de398cf4e6c61b210e9673f0eaa648828aea46de681e5be09c73093b2a31fa2afc4d345f805784cceb792580b4b4fba707ebb3e18dd8ace5f0a	1652786553000000	1653391353000000	1716463353000000	1811071353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xbc54f31be092e1e363137c2297269f161f737e581acbd2118dec0897bc545354928488fe99fbfe5645bb6ca96345e6f8bb095cf31825da459dae522623663c87	1	0	\\x000000010000000000800003e22d6e3825f66281f1da403641165b483b283d9997539ffbf03dfb6f1a2787ebfa11fc7c6c09c3e955b3b6ac7c85d952d7fd432ca848564c52b5dfc6b9bce0636a8b569cab00b6fa8db398d69a880ac7c1e6f9d0ed5e3d1ca53c1da0b1c7456ee97763c6522053abd24e10dd70a945d7bed32bc120d72214ff42b71f9f4af5cd010001	\\x0a6f0ca122759be6c5257eb7594b4a6f216951a7fa07334f266f2e71c54bf05827eb388413897693aac02a23e9bdfcfaa25ea64f442be7dad616d2b75ef15304	1678780053000000	1679384853000000	1742456853000000	1837064853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
91	\\xc020eaa09528d9c8a8415933b90692a9fe3e60f986e1b059fd981739d6c9a0972347e0c32c2ee08cb45ce3f633822f4ad40737ae0e91c1fac36ac4bb0e8c6403	1	0	\\x000000010000000000800003dd718b7b855386325e60a3fccbf4dda3c1aa52f9a547f3b7ba39ff08ee27f9f252c931694ca03d83f76e6cb72091d852b743e1a64f2c2282236f38fe53506a3b37d76b7c53724dff98a932ec93ed18195f74f9076ef845aa3d6eeaefa038a899cd07f422f9180ab64fab989455db05345688adf6e8ff01a9e34117dfd5b09b13010001	\\x555cd4caeca213ab614f29d34f9710d4e55a4e40e71b7ac279f43fbb6e17f4f9c291f4a18fb722f4e6740bed0f7ef38d266db7b7ebc7d65c4160fe11f0c3e70c	1649159553000000	1649764353000000	1712836353000000	1807444353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
92	\\xc1e871d3dcd1a622eb8353979df51b6bd7211b16c9c018e57ae96842221142cd6428853d9df50756107a9b60b4e3efbbb8ed8831743f788a70437112b3b5c908	1	0	\\x000000010000000000800003b5e98b316e1d8f6bfb25dac31cd1085bac1e62b8217c3951edd0428f609cad08dd4b65fd08fd12ade8d273bd9af2629bfc16c311b9678ee8b761917a75a59f3015303c3a5246d2e88329925060943e8566f6610df91b59e597d8734f9a920fa47c92afb3feb05445328e8a847d4f88117aea16fb9ac1aaa784b4d9428623e825010001	\\x2d995d2e6c1601d862d78327b687ae44c210ca941c555bb798e4083abc923e66d5a778ace69908a2c4a2bfd6fe549fd29f56dbf13a4080df79fb7e9868daa705	1657018053000000	1657622853000000	1720694853000000	1815302853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
93	\\xc1e41fe0fb3a1f52a4620cbc654c220050938881a99bfd2e336919beafc5a35f2709c05390c6805b0f714f94e41f6c082d3ec36e5d019bf94f55ab9a023dd4c5	1	0	\\x000000010000000000800003998a77ae989625dae260aff49a1fa637642bb3a8540d2dfca7314e8cd18c7631d99b6b8b0bf8e53a5b03434a9a70b07582363e65dfd7548d5281bd2c7715635f6e62b53f5d1d3f677510943f848c8f2ff830c5adcb6b9b45e2deecb6c009d0b69b88bcd7ec0eab42f33fa7a1880e8541954e5436098df4ea7b9d8b5cc3aab517010001	\\x064b9ea21dc4563bc133a0d864173f4fd89c521c5973f74a9a3d56ea8b0d75ab26a0233a0a958198e415217eec32d16fa07cf6147d0bcbbcc0e1b524d3daf107	1677571053000000	1678175853000000	1741247853000000	1835855853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xc2243107289ebddb362ab63eb83143891e777d71a9f4257021f3e8846d601d54844d694edcdf587bb8f9e3f74629cdc105151b3ea092d210f69637f965350911	1	0	\\x000000010000000000800003e311afb68054ba101b3884249881495009da210511a94c2231813d2cd9c10e97a8c57d63a37aadab6aaaab0eef5d1b12d86717f54f0ca4bc245d057ebd642d965643698d6adfca742a68a3d406063b9ec019f3765c5aaef25bd06abdd6808f23d389dd7731fe72aef365de29e83e28cfb5458bea9dfb31bd785f7ba093ae9789010001	\\xc9593bc7dbcb95b2635ca3948f3b8638d34fe0a31bdabfb7952fa9748d46b780257f74b5b9c8084e4cd0795edfb0ce59cde5c50920d11a0102572ee98a6f8d0b	1648555053000000	1649159853000000	1712231853000000	1806839853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
95	\\xc584026677ae10a7aa2895df1fdecf6130cf6daa67db666a9242ce3a084eb2dd338827ba92eacdef647dd8097114876f17c7f6a2cfc602023e8f9e53d36ebd0a	1	0	\\x000000010000000000800003b2ebfdfdd9a0e41baec404d45e9aee51575a9f0ee5e979668f20f6e3b3e0687b7a2c8fffc5e34f6fd4883a86dc4614cca9213316d493be5073a30c1bec76de70cb9affd878f9fec17dd479457eb5179fdb7aef6e61872105fc5b24af7f2b92dfd9a073c21e815811468e5d38cbc23c7fa7612ebe3fafa6612176c1698e5d52c1010001	\\xb764b072acc0280857f4b5678c83df0a380b890541533033a0291a4570634621db6b4d43d28e6225a36f4099905b94f1486b304618b975d3971a8a88a762280c	1657622553000000	1658227353000000	1721299353000000	1815907353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
96	\\xc578107242ce0ee050e6cb4b95b31b69e100c4d3a21ebef7fdb4382befa4ca74c52562ac17ba1fdd78a957dad4721054f08093a2975ab4177439b55635893451	1	0	\\x000000010000000000800003985f855f752a73c16f3a09b208f8ab58e011ba43413cbeccd607dc34630991dfcd7fd3e626eaf597b7149864c242783e987490a8730d99456daa47f7ab4366b443905161f6b8ef8d7131cf5124318c1f05904d7679f95087855939a92c71eff8bf415d2822cea91bb954b66023df4035d781aa58600a8ca871a4ecfce9b82e4d010001	\\x3ca79217f215f76c81731d794017721f5016e2e10d91a4f507912486a1b282d5807e79d0713808c9980cf560b815cc1399580a5b3c4bd875ca8fd3fe6ec4ae0b	1669108053000000	1669712853000000	1732784853000000	1827392853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
97	\\xc92465b46140a718b09e8741e3734fffbeb6c50d00bc03ee1d8e327fb4ba98f0c545e8ab2298ab09998c898e36a389e3e898bc86e5f4ada2860ec296b6b75f02	1	0	\\x000000010000000000800003c4906917b673989eae15a38afe3e48396544497a109d38b8f6e41b687a358addc48df67154d910f803df05a67dc47ca997d380db31f95734f4e95eb84e40437475ae382390532b83a3160499691b7f3d24fc43d1f00ef43a9d0111b5d530fa8d728efe476a0a5d2bf769aee2915e711e7919c03e30f1b3387d4519575971be27010001	\\x212e667d3050930a63448e8a5ee65c34ed5a463b5e55be33be1d3c085e26c327610c256de86d8c0ac7f67e364602aaed1920b1fe89285d5bb7859b4ed7763b01	1658227053000000	1658831853000000	1721903853000000	1816511853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xccf07bb72fc4858c2a833766a44fd2a564f990fdc7d59bc82b85b7fccf17da9c52e0fe033d639ace94b233ec774d351c9ad1e8ff1e7a38f3f516a1177445a820	1	0	\\x000000010000000000800003c4dab41b65e75189af12e6578682a9d68e97dbc6bbcc4c41528cecc5c3e0b202f80222d116900c9eb7e5e50e3e5fed497a2444eef48e612455375f3c7f103ab436d1f56b8878c9afcb7def7237d53cb92f35e1d8e10f70f3abd8ae72ed997527d439ea3ec721a1b99a2264cc487bf4cb1b9c630d6beb5b0e7a69e8a2581d8807010001	\\x6fddd34bdef144a39c1886ab0c71f0c676e41bee80cd71fddd25815fd23b4acd9186ec929e5c386375d7e0ca168866f2c48a5b13ab1f94d1adc3140c12aa2408	1676966553000000	1677571353000000	1740643353000000	1835251353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xceac2a1afe71507c16f8cfbb135a03589931d9ee9d88a82fbfe40664ee4439ddfc9b17892759e4bd6ed88d9725239a3ac90fcd021af92908daa24be0ffb9adc4	1	0	\\x000000010000000000800003e09bc1bb7b948cd02b85f546382da0e55f13a2679d2b0625134c59fb540d715f7b1aac1a5b78e36a16fb777571415501d15a4a54d24a5124a92cbb83a92243156108bd960b468ddc75cf0b96b88df2f87d7ee12178270098e3d6f3a7f5524c23fbc362b6545fc63373942d3260fd68cce5248fa4fa854dc2626a35835682aa49010001	\\x70d43351e2361047ae2d7af0d5611f0c7f43a577fd3babdb1de80eebab7ce7032cacc4dbebd7d90fce197318c0a5a93f671a3d20aa4e4f06ae5bfc09ea30ec08	1658227053000000	1658831853000000	1721903853000000	1816511853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
100	\\xd18455db5ff5b4aa0e358e38f3cea11fd8dbf44f8d33c3b24f58c4485188b98bdd03c538d454ce4149f635861eb7c61518d2fe638e3f5cced4b7582a88bf0427	1	0	\\x000000010000000000800003bf5c6da079638814b29446dd246bfb1ae468826a6126478c95ec288e690f6f384fa1ddcbe61aac3b8500914b4e303feca5d0b00ff662432426eea851af37776339e9d4646da404df8eac50b0af6c2acd970da4b4ac6fff20df1e976dd2189740681034dbcec7160532f474ccf879ffd7652f8ff0b88d5a3f37f32644659557a7010001	\\xe936dd0394b051e52b6671682389e61205e0edba7b71507432edb356656b8de4d0659e38f215d4fadbef9585d1e2902ee6b3df0d4ae54d2c4676d85a2662e40e	1657622553000000	1658227353000000	1721299353000000	1815907353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
101	\\xd2502acf448ab74b7a1228147b04c84327b539d596a154bd7b6ad4645124d2cb1096a9c8314fef2a19f219e4020eb6841b3b49a3d32f6b368585edde887fc4c7	1	0	\\x000000010000000000800003cf6f8bc5f54d275c2d1826e06b7abcf26038771776ac1d4551ebd6c09cc5db3c93aee42a89fa6421708dbf2ce99887af5c3812aa685be2300628aabbbba9dd3f82bfbe70bae6835227d8e88a83c5c1917d9e02896258e81a12001bcc2e27cb626911061709cc14b2c723c4b796d9c7fe6c8e530a54e8be477387d5b5bcbc25e1010001	\\x8e9fb303979e11d1ac96b0ba01bf4e5932a15339423fccdcc1db8eac609142afb36d8e244005de524127ae61a779bfb62f4dff61243660d3a49c8237eebda709	1677571053000000	1678175853000000	1741247853000000	1835855853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
102	\\xd4148756d36db5f2c9438355ad88c8e1a58b9caf3720f7b6231660aeb5dd5a0c73d750c6e9981123afc0bb186feaeba8db7e97d3cf9c0b1c8503b5e8b11b50aa	1	0	\\x000000010000000000800003d3f61253e04ba26111eda7b51b47be174ca9d992f0aa93490400661e94c1dd9ff25967ec2fc9f96e6be3794dd0df3f8d9599dc1e32b3cc0c470567c66b190bf5cae8bc486d1a67e0d282e4d90ca678828e86cd9ee6c70eb5838fed6f91be58d493b4aad8a85c0f4144d8d08b56b06f711ac8fc9a7860d893e234e8d018ab5c0d010001	\\xc7f1cd96524fb3745b8d510ca729249e062b1131e156f496e109600728dae1d674d1e492c5b0728cda94511407558a6bc447e9cf278d0aa0928fe312134d2f07	1649764053000000	1650368853000000	1713440853000000	1808048853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
103	\\xd41468fc0970e51f0b14f5bfa14c78d072c77c65a6f7a5cf188c9c9d891022bc064f07ba455a4aad5916db281b53c24fd949df24cc5f2a49ba026f814471ddbd	1	0	\\x000000010000000000800003f49db41cadb123695020904a5569ffc47b730ff78563eca014543a970f0a62b5822f2c1bac5ae8089d08a662919235f6fd624bbdf1ab3970274de5fd155d5b36483729f933ca6bddebf732671a43eb78d777a0f46240a14afc99e055efaadb3e0c839730bce90880e05b394789f01007ffb718d5a78b3b4bd0ca9b27275a27c9010001	\\x98c7b81e60e1741cc1addc049476e3210bf693b33665ad7b04eb85418f4457700bc308fdfacd66912692a248727fd7d2dde8c0a0d27812784776ef211d789508	1676966553000000	1677571353000000	1740643353000000	1835251353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
104	\\xddd8e834496b327a161a4c3cf305990dfb2908580a96f6789fb3e5adea01067e93d7dc6cf412df236801d19d78820e5b47b1b226fbb79a5ff501bb35dcc34bdd	1	0	\\x000000010000000000800003d0968fb136f38170b8acf3c388f607d67116074f8818f87f48e3a466fced9952044b158fc3523ed0cf6550129cd86590b4abe79fca27f27ce170ddf03c06775932badaa3fb40e1c25fc4e8fc219afca7b103803a81006f004252f3987e6848522b18f4c0b3dbd6112cd0943d37062f33bdef28571a714ea242a3d2240599608f010001	\\xc14065b06a148ff30c40ceed0af566ed399d9bd3626943c9818399c9907cecf74a2979068b8f68bf54526ec84f5d3402249b20c407bdc07e4a573314eaaab60d	1672130553000000	1672735353000000	1735807353000000	1830415353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
105	\\xe0705dda13b99606ff0854db184e39cdd8e2f79c7d2b1715672e5d15c6e0a939c90477912ab003393f8286415492be28b31face624ea7cac9755f0cb9d7b2018	1	0	\\x000000010000000000800003ab86be630bbe7dae4a47a43dc58af17e933483c69ef8015bee6b96bbdc46ed383b6f81e7657ebfee52f672bea994057875de3bc5c88cced11d045c30d33fbbc9bd8e2b975e0c00e68486ff05b55214bae9644427e036d71b9f56c5696f6294dddec19f742d889220638a660cfadba759c965eb09946d3b17acf06df33813fdbd010001	\\x82dfe523b3bf72c92653e09067bc34a4da626d22f66b28e2260e5e6e4ebdb44733fd5df7461ba764c5f8c0de53803bfaf095b881c07cb8f6862a3bf00d423907	1669108053000000	1669712853000000	1732784853000000	1827392853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
106	\\xe1b8b719cc181e2f3486680f05a04973d0f2d3cfcc2bdad607e04cecd38a93a55c1780a4b1d0a0d5521bf16d191aecbc86390a7f254e7859df6b5550da27e542	1	0	\\x000000010000000000800003bc1721678a6b277593bc9a9de94fbdb6cd41ceded0fa11864b0520dc2b71f840169115fef72dd948e195b9b80f137944e3e4b7650b553defc20a6ef19bc0c031d25ba48d58d10f7a1e645b1413366de25c18dcdd3cf03f4ec23271dfce37a51cda01e01f8554733a55034c7cab4d8a66e5bec2165f17ccb04dc2230fc9a25931010001	\\x632abe6ebbda8e829b4fe33d3986b20cdf91076ebf20ccd15b03ebb6cd48ac650a03d6cbb6595d9bc6620c220fafc8f2e3a34a074da24c93ebf99e709a17420d	1669108053000000	1669712853000000	1732784853000000	1827392853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\xe2fc02f60a7c7db403020667510a4a73b66b1a4c99157187d7450ccb394cf8c910b3fca4137399d21cfce6067a0ca07d9a727359273cb752b5bec5dd8e2093d8	1	0	\\x000000010000000000800003bb70970b5f01ac28a38fae244192d79fd49f7635eb0954e8c1ccadecc73f9403fa0524fc126b315878c5a960f71ababebd43f2553459fb231c2bca623e8f809a3574662a212ab17b7434eabc2526850ac31b90a33f42f1deeac978ac69a93b8a09af37310d439e651ff67351806714f9164a6cc17a75759fd2f84b821f493ff7010001	\\x40095a6652481d9d602e750039071ad9247e7b86a3914087eab7fef86ba68526481334257003aa6be3967c9ced1d2e4840694dd360dd7cc6bf04a74ab5568003	1677571053000000	1678175853000000	1741247853000000	1835855853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
108	\\xe24c992e80aa15b2552ca24a9345ac1def16800c8ec615fc626c540e009768519c05b7cd664f203a18b35e0bc5a1ba83dcb2c26e483431d03aee5b248272fdc1	1	0	\\x000000010000000000800003b82832f1ff28f0b5ce59f09c825855dc83e38324622ac211c8255407d6ee680164ffebb9a9f2c8fae04ecfd4b9ee863ed329285de1847abfe89c18ac6ca2571deb977e584cae75f4ff9fc8ead502878df9f0bca4bba55ca6c563e4d5205d78f6cb6d66d628b65373f343ef95bb27d9d484225980b3e5f156242a16078aba1e35010001	\\x3f1697edf0a875e279ff462c98bab2abf3e8bc126439e2869d9b832f7c9f3ca1222e7765b0a9c98eb379b42a56895f52fcee6c56eb278e40360c30bd4ae9da03	1671526053000000	1672130853000000	1735202853000000	1829810853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
109	\\xe3d892ab8e0f72478bf0fb09e166b60a7086d9aac0e289c1efd2702b76f717a313f14ca500568c1317f5ba2cd1c468c434c2e1fab07c37f9eb639c2e2dacb0bd	1	0	\\x000000010000000000800003ad86337f034071ea1a3efa8d056e488cc8538ef369664e567bc5faa83585e6b35d1e6d7a2f581784de21de5328ef91632fd6d4edcce5c0b311070792a76ba9e5fc74850b003e0b4261b408ac4956fcf820d81a8174bea94534827b0b31faf54637ed6b09ecd7e9106045ae7dd938df520db47e1774e02b50ebede266ec74e039010001	\\x3af4c4c66995e63f063f3fdefaed6db95ea9588235873011f54762060d525f94240695561291cce3b528ee5841e3135644c4f405552c5196a5799be4534a5c0b	1656413553000000	1657018353000000	1720090353000000	1814698353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\xe77867513da955d6c48609e5ab563cd48bd4263edbdc458584d121eb6e3d367fbf19b47215005decc80ec60aa4f071ad0dd5283f8436f9c2b47050d33d53ba11	1	0	\\x000000010000000000800003cea6b3e869826c316aa1a49eb7327759d3a50df2bdc63d704eb8cd4b0dad7d996a83416ca81568f8b4f11926685f19f231058c4d635c783898f2e67ae0c9bc4ab913ae7297563640d1b2b2ac1fa6ead320207c7c72016dfb99ebeb87c8ed133763c71b6acaaf419203d49437e44b4e0a625779f3e335042ad2809bc7e41acb95010001	\\x4b4d346fe70f92d9d4b6cc0f1ffe86d57b21375faeb493e265b62f8affefe2365a7fd9c0c0404e4751ffc974b38d15acea2b202277ce6921e2ca8c2a1fbb6003	1663063053000000	1663667853000000	1726739853000000	1821347853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
111	\\xe828c3bcfa4f61e4351257e68f2b9e6372e617f673009fdfabfcf6e4b2832f72d9065253beb4bad0f5f47efd499bf88c90c34281af1162956cd425a54288029c	1	0	\\x000000010000000000800003bd8492ae585a8ff12296e34eac9182f18c3a2023073a46e76ceb6571afa9cf2b35f1b146064660e8adab0979782df834b8c1c0d5836a55fac1fd5438213c8d037b4935c6725f68decc85200390cd36617d97b90aa50abf2494d1fb046fb30e7923eeb35e93fe8a14dbc28354f7b6bfa6f5872fbebfd4bf546215851a8c62ecbf010001	\\xae4c344e765b3da21ba4f396444058dff254a6022777b2e6567122acc6cbd06edd9a6e727f9f167e20aa34e0f1fc85ba9e0c9073431140ad1b1e239fa856ec06	1650368553000000	1650973353000000	1714045353000000	1808653353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
112	\\xe9dc0b85d481f7d9875ac9da1ac7a629db39f1001815ded01dc422176c5e12481b16a0818d0c63ab5513fcdc7783f7fb4dd1feac9b4172ff4cee34248d4e0a6a	1	0	\\x000000010000000000800003ecf313fd55e316af8954e7c48cfb12f57c19c093a67abb01d965745e56fdacf93d9f375fc71487e597cb1ae15cf2d46d2b8b474070626ea50cd09de75ae32205b96391e5f33988073b986d9bd270114ffec06f977ff6ad2a9fa30b0c95f5bf2c98d6eb4b870471a986eef3cd92c689847443afa74b73b2e9a52574dd22dc80f7010001	\\xc23b3b25b178b3a5880ec6c96511236cc4be724c904f88d965138c9ed7a59eb16953286b302247cf4c538cae1587c9778f968b5ac9935d4f4cdd256cb67dea0a	1669108053000000	1669712853000000	1732784853000000	1827392853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\xeb4c4801f6e77e2036247a7c0fcf4caf857e559683f8123997effd70ad7e6c092299db68745ed840b78069b187f9ab8b7bcc71edabb13c58ac89cb767d88dd6e	1	0	\\x000000010000000000800003de92ea8c564c97e54de61fcbabdadcb1ffec26b93b04261860e7bad00c8f7049240d860ea4c85c8471595d7a328f03a0bb1cfb0bc3cf32ebc91f0fed1232c0067b3f3c78884f551f66137d9229e43a39c47971d91a50f34b80e4f52bbc8fd402b019bbe8938ae23a92582d6000837dc43adf24f5e7ff87ee5a297cf17863bcfb010001	\\xab0196de35bbfb755b5f6234a644508f76a7f4113047e714c0d8538bb48f1a94ff9bfde182002b42f8e05c329136a055eb6a27cad0ae6a5c8010a91a9ebdf50a	1654600053000000	1655204853000000	1718276853000000	1812884853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
114	\\xee70db4f3cc6244588eba5880d2e24f63e99e19164e746400776edc1bbe91145d43751255b64a92af90ba716d7158a642e1258585a598013dbce0018d56fd23d	1	0	\\x000000010000000000800003abc239f8e50db66922d472743c65b5c6e7a727753e912333fbc83d470a0447fe8c3224d4f851d23325fd850a8b34e0625c0a1a92ed41a1441ae199c52e940ee98ba859cb1a1de3b76ecf5d03b3d8a26f7ba7aecda0da88a36306da11fca397d28fa0f9574d08ce85e8095e8d5ca991819f7ad9565bd70d693ab862b943c4d24f010001	\\x1bde2da161cb7632d454e0e22d1dcb242210ee6eb247269710b42e93a42236439b5073742b2eb30ba85b4d47a8746de60cc64e5b964d09ec7bf45a8f270fe003	1664876553000000	1665481353000000	1728553353000000	1823161353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
115	\\xf584f01396cee397e8c4f12b77b1e23ec378eed7b34ba5aaa9ec6a4a62d356af98412eb12e873dd7f0e9a7a34715f1ffc442617be3682e65cc87936329e55a80	1	0	\\x000000010000000000800003f439147144f024ab382207fea6c17d55bdad96ca1d261d53a81cce2469beab46873affb2d28591b29218748d444fea9f1b16124e29483b38898716307cd6f5fe370c0d67a0925ee933c071e2149634120246156f4abb16b7f79e930d22e0ccdcc4b7cfb7b644d14503a5e2ad175de752484ab340e056b17af264d5a28747b2c3010001	\\x1965d691ed61b8a9cfa4d9340aa5ba7d09aaf1b24ea553dafd78799a49afc9bfe5b8487be569dbb625a9160901024103762d5172927f8b7f0163238384708a02	1675757553000000	1676362353000000	1739434353000000	1834042353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
116	\\xf9e844ff338a51952378370eecae77148aa2e4e92dc5361b5243d000aca8dd280db363604996bf0815f7d3db08d4d8cc4e6c07e0a36fd1530d5b994d8d92a122	1	0	\\x000000010000000000800003cccce17c2905c87c1edfcd4974b1428e9af5f617c22d97dce67aeb808179748f6a0740c2e52b062acc75376b72b1b2767773782f0405fa9e4cf2029074174acc374085a3d7c0a2260829b0d0c873e274892d87b3999531e8f66181889d690c358d525af047df1bf2f307fa274ade339e5baa6a24a11ba03e3c25048b6f526cab010001	\\x5ebb381a3fc56c1e74b6a0e979e9f1bbb8647bc8c48dfa3cb9b330f2b09fd537c6779f2df10ea66a0633f25e191b8936efe1b2f0c0e5d234e0780a918f87aa06	1664272053000000	1664876853000000	1727948853000000	1822556853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
117	\\xfb30ea77074d7e3a40067221484ec64786081ae421b993083622d4cd10d920c4c904aaca60a4ff1ed315988d23f19ba230c252b866b493486ff79cc4021d06b9	1	0	\\x000000010000000000800003b172ce7917efe88a16cab62ce54f9161fc1cf163783c2ea85218448d09360df9de72fb7d7a7676d4e6762b3464f3c151408fe5f7e5a7c3003cf18bbde6992b321a3850aa1bbb57ce7d805b0d766cb12a83f05cb130b592c21c4a059d0c16ddc1895bb1dc14fc579130bf9700584e9c5f4ad98901e65855404498a4ee61467d31010001	\\xca30478813528c44de4d9073f9921e4ab57839775a557bea4e17fdca5b2f3bfea4601fdac4f53ea587955d05a1912f7d5dc80bb16184d378db82eb97d8b43300	1675153053000000	1675757853000000	1738829853000000	1833437853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
118	\\xfed820d4c7599c2a11107df7b16c5846feab0dc5188667a683f19936bd9af559fa5d0c5d64b777d7c12497645371ac5f06d7ee60424141284569e2ac8c46e843	1	0	\\x000000010000000000800003d53938c19d1e98c53760e03aeba329d53c0a77734a0db84deb62862c0ba9afd6587c32d16853f9f55454719a4078b3c67565a9f39497b5a70c4ae9e10b37603279b05699f690c0b75e81fcd040a0269dd1ad433c21a834b2a2f0a9cef299e8e05ba23e3d75ee1d1d72b9ad2691d9699a4dae184f345d6a40e64fc743ac800f19010001	\\xa4ecb0048f82b0189b06af2d343971e5bc79c92409c0dc6ddee8159bd3e1054fea6fcc62f3dbddb121632bd3edc5f72672c9ec63c8de02c195fc7e6d10efd10a	1655809053000000	1656413853000000	1719485853000000	1814093853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x00991b2b32e992d436d5261c1cf04961210be51e3de4574a217473b091f01f1a07d411d8fbdbf1ffb1fc7a67dd9b821a9bc186a9b6f60ec1d04b684dc2b66762	1	0	\\x000000010000000000800003b4205f6fb45dd48cd7fbe5d18c9517b16e4da152a94c4c7092b482b7403014635e3ee5f1626fc89a76a18a6280020b03b2ed88ed0a1ebcce076782ff077a4515021303442c6c6b8124090b2b81ebd300a21ad4a71031357500ad5875296d2decd678d6f53099319ab91e578d1bc70aeeef1da8bd51fa8449447c2ceb3820c839010001	\\x803ca2a58f377efdd80047c132e656c18d0a348d15261b09926f8c331eabe84fae9bb842c67fe6e0b3976f09bb771ff0035a5c71417d2a69776102da34c4a80e	1655204553000000	1655809353000000	1718881353000000	1813489353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x01318a5c61db2c5095c5561676a95cba5f5d1d9103534db6fca5fede91f3d31f4b0310ba2b5e3e82e2388369a708738564d581f3fc16fd91a56d62f2525aae6a	1	0	\\x0000000100000000008000039a8e202e573d9f96ebcaa0c03465c98f37012aa800cb17024bd8a0603cd5b618a555c7a04cafd09141510b22a6882522a8e7b7872bad391279e460931bee1564629445bbf5d8b66286696e3f8fcad145e533836d6e49ffff9ebba95769547e22206ea72eccab0c3237cb79bb79ba06dd97592dd29beb0ff3cff78849b663bd57010001	\\x2cf53f19499b8e6dcf90a8306a5b048d67f688475572e77acdc5bd4b1d8893537a304758434edf38e380d175fbbbd40c592825ef2febfb3fcc7e19469c28d90c	1666085553000000	1666690353000000	1729762353000000	1824370353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
121	\\x0a5dbadebddaf88f5efc18b71867fef4fe52d384e938a3c2c79acd028a6779a09b82aa3e86bade9c0cf98b4c1035a17e84b7068a69b93bc53d8d726e9501efae	1	0	\\x000000010000000000800003b821ba63422572301a02a49a8165bea55f3a07a23e7101c4e9abdd000227dfa5afa892c05dfff176c23655a909571a4383dad1edc94ec689ef090196f266d483d03477a669ed74418e1d0a4b9fa8c666835698a0b55e742334a4b9644be7ec19d6ce6dc51aa9363af54142a7f9515d2e7544b574e4a18af56fce566ffd4de27b010001	\\xff9ff7bfc5f3033c1d79d5f012b1d2eb956d8c6e1efb4008ba5da346b345e788bfc399df09a38023137c650624ae8c4e9c0758c6293b44326c867180b1a8fb0c	1666085553000000	1666690353000000	1729762353000000	1824370353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
122	\\x0bd9945e5c804fd6ea593bb961c6d5461b7edd4b2fd137ae38ef121cc45806e7b8686f6bd9f22f3390dfca081f2e61af78ac9022e5c2906eb001a01c3422eb1a	1	0	\\x000000010000000000800003da541741a729ff365e791cf59cbfb717d90b4d7ae2b7df8c87e7b0d2a82943d66ea84a83d443e14e5161fa838fc993f745f5e2a422f8065c211a229e029608c8258f7f6ec9964a94b1773747fb04b99c0403ca367257e4467a365e8f9592c2852443c7d7d2129bd8d7623f8832b140f35a7166a773cbe1e41e78e2e6827f2d0d010001	\\x806a216c3b58df99c017133d2d499426313eb4dad67989339ea360483030b2d58f2398f8d8241bc3f0f587d0d5d6e75c5c151c6a3074ad17a2ca8e20749fac0a	1666690053000000	1667294853000000	1730366853000000	1824974853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x0dc90c04f22245f68c564d2fa7262eaf04854b37083bc00a2ad60b8e577732db534c18e2076650a8ede8b5c9e7701114f70721a9e23bcc7676231781b51be2ce	1	0	\\x000000010000000000800003d00b6612eb9df71dd377d95297fd7d73f693315923ce750304717179e53c6bd386fc7092ce6b46ee0ee059b124aff7d27ad391781dcd1412211b5b33bc7e4126fdc5c64e0387b1ff01b014b31fd968980cd199408d6f3e4ba96493356fa53378affda8e47714189fff247eef7a61f8540c80173af8a5ec25e292f23db66d0481010001	\\x7e69b11720a1233ef773222d76d48f8b81744ff8e488749342e0426e0d3ff6d322904e34d9da4261703b315e6153f37912628735e7008d9cf79240878c37a50a	1657622553000000	1658227353000000	1721299353000000	1815907353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
124	\\x0f456622d0ab9f7f93d12fb8d55ae8127fb2b423d08165a12396a5e4baf15547b08e2ee59c89bf78e987f04a4f1c7e3cf9f02470ce8300b296c3470bab80a37b	1	0	\\x0000000100000000008000039442b70c60425c5e6430600abcceb4f496e6306d8d7308e9ef0a356ea3badd6042720e333705c7bb46001bf638df9b65420565bb2bdeac7f1e4852c6a594c8f2e3e129d22d2893655b4d519651656d6c8fc34dec05a1fab72669f862f7d47e316e76b0ad7f97e15d0d81bee42859e4575486d9814f6bb29dce715200b7fb4c17010001	\\x240fe40949e90330858bbf28566991ca827af381e457bcddb26bc1119aed9075437a5e7416d385bafd9618e64965d688c264ed90aaf4f13d8f9afb93f0ce3800	1676362053000000	1676966853000000	1740038853000000	1834646853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
125	\\x0fe9fbc62bd6f9f7e384267402611db2c813ef633366526139c25986fcbd46680e7307b12918045c76234da82cd8bd616653586827509545e226cf5681dd26ab	1	0	\\x000000010000000000800003c5fb0744083b2e8575048f5ce3098059ed3953502d2bb967a1707a1b7d9c611733666ad5433d2906d20d458a49282d91937cf84b75e3ba65d1a395ca4dc80b53938e8ce4f916d0074f362a2e5cbd90f44451dc3065d8391fc65c3cce3ba596893318b11c5b8dca6b0dfcecc2a7a3e7694b58135dd3813affbeda1cee367f42eb010001	\\xd2e68aaca811b293283593ee9a1cbee7eb8872b107e3ffd113b36c48a9ae762580a28ffce77fe3d98369664b62f553cccd2b4ba7b1555fa43cf1b47d222fb308	1678780053000000	1679384853000000	1742456853000000	1837064853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
126	\\x11c9a4616d4da91b2e8778e49c058149919e130d43b923b6a81161f568c60ada8e95df70ecc72a2b27999d8a002d27981f7849c58cd9f64ade000b4b10c6dd9b	1	0	\\x000000010000000000800003b49ef28cd0a21babff03acbe27c32e5c8decd56d5f94f032de501f363134b8e0944c064b28b93105c36e5640adeb6dd06c53d5f5a9b1802f6528571ca8119cedc493de6f7514745c9a5943bee3199372b41e76b94a8d55db8e02fb71121843334a808de6a34c6897e2ded9cae3d1e0e145377e0cf2b5dfd9fc87347d88f38b01010001	\\xb44067132d71106662131d3101686136ecfb7a9fc3e404371b370408fab79a60bdab560ad52e89aa829e76dc7219b55c951a12c600ffc69dd2cc93b94a2b400a	1671526053000000	1672130853000000	1735202853000000	1829810853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x19d5bb856655813927b7d0d5d5e847c1f600abf58c3279cdfbe2e0118e1cb2f1d0d748f98e35fe0b5c1edccfacea85460f369702fad1d099141ac12165e85919	1	0	\\x000000010000000000800003bf8a4866d31ae2d7650a67d1182d44e11bbb3e22d3820e0bc740da4ebd0f5030836f973708018fd0dd636c0c2eb299ccda6aa80c6ef3c5bbda28db3d62d484dce14a0c8b9fa8d98340fde75bfaa198d89af560f2bd0e68fe8d0555b611af8ed67d473ac25c5f1444eb4bf4ae82102ae41a584cb61e15a6ba0bcd3d711377fcaf010001	\\x007dc354270710968b8a892110f8f50d1744f9254344932b9a8897ee86be49df4eca3b22f70a40bb69a16ea7446a3cdc698aba361f478622da27006b8c7bb600	1674548553000000	1675153353000000	1738225353000000	1832833353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
128	\\x194937ba0d7a2cf665545612064df5ae4b41dab3368e4434a4e74ee2bf01a4b23f0cafbd81bc31403491d5de6ceff89f375a1bc64aa2a30fad002306f0de2ff3	1	0	\\x000000010000000000800003aab6eed0649f5ea5892539ff35564f91bd6fe0761f2d1d3633c096103bf319377d12c13c1ef4c1a46258121bb2be967a75301d5e93ee9c42e4644f874e3e42d8cac63ad22a0d461458d207ef8dd3e2e62d2c5996798525b93604518f15ad996e316c6016275ea081eeadf707322acb830dfa204a125182147168f4e4213bb219010001	\\xc3fc2d6d160e5cd786dff065c3b0365948003d3cd96ab2313a0a995ad0a7f376aa32460c37535afb31f520387b801c64f6cd1cd455fdfa1df95d069e0168ed0c	1669712553000000	1670317353000000	1733389353000000	1827997353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
129	\\x1b19c0f5ae62199fd84677c5dc7f510be5272e8e4f7ff2277d0a0d474c48b15325359a09552508c4b9d760bb7313a4ab4a633ca89cabed8366739cd87b10d4e2	1	0	\\x000000010000000000800003d28bb791975c471e07df1b2f500774209e14057f09e51d4fc8602a41c25710889a52593394a89104816035f80ad81ded832b4ddd0898e92a8cfc7b0ab5f46588fdc2d7b689ec8e62de4743c1ff7f1f6f9700c6c85f8881df73611d43ab3b95ea36f265359ec183abfc06d121600b17920b1aa2fd817f643848f79e2e41e52d0f010001	\\x323b96445cb1b50870925ecf0e4c9115a6429aa18f82887a758cc8dc1ccfe637936f00dfcebba0335878302d05f31b11751cf03d519905031c9b71b90ce2cd04	1666690053000000	1667294853000000	1730366853000000	1824974853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
130	\\x1da17fa91a9e9c4cff3ad9b799506b2e6f3f9d6ef39e9b6ecd02538018205d244445e4e0957c5f8c367c29b13d526e8d07374bd9b318354cd9e446f5fe10ad3e	1	0	\\x0000000100000000008000039a6102f3080ee107914917ff582b5eb2405f5a67b4fffeb6875de13639dd7287738c56fd9322b4cf5ec4f47c7d79014570d6d405b1c0a8e7125565f1b672b7879496cb61f9cea3507481241edd271f09195888951943257d51b119fc6e753a817dca141bac43b0ab9ff0087f79d2f6d28ed2dc30e8adf245200ec4450679f269010001	\\xf9a8133e07cd3c4d45a28c45df1e08f0f394010dc1300504211c613978e8717db1382f173f841b1f8a11af74d07de0609a782dc368dcffc971f1bb7fbe587403	1650368553000000	1650973353000000	1714045353000000	1808653353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
131	\\x20f98f32628c117f052b56fcce66ddf8e33d39b8d20f387195bd05ef74cc9c2cc251525d0b9afd3792e3584df7556c7ad8bc8445b94608c6e72f28689ee32c03	1	0	\\x000000010000000000800003b01eef9733efcf9ad22485095a2533b9d3a45705427cec94563c5d22240bf2d03846d70eeb3a40219a41850128bbbe181ad2664706c16b49717c1356dfb3f96a1e1247a0939fe98d3142a0deffd5dd591feabe3876ce99d06547c357af458daa0ebfd955a227d876e90f523ec0dc028485becfed1051a0140238e91ab2b416d1010001	\\x9672a46b345f5f64b3ab61f84ce11941eff6d069dce8536d6a09dff4d727447062d4290586bfd74fb5591297b612c32c697e3287e1afa67e2e5a3195e3c1b80b	1675153053000000	1675757853000000	1738829853000000	1833437853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x21498c2ba769e54176725f59d031e0e815f4e06f2fc69d44e0fa38b24bcae9fe13ee7aa98733fc333c513b93ef9e98608a3af4036fc5525fb521621e4b571168	1	0	\\x000000010000000000800003db9f1f4aadbf72cb1dfca3f4d4d502cfab78c494631e6afa4a3236274285ab7f81f1dec9d9c5da45380fa8a0bc5bba6a332e3947a923f4b92b3cbe7dee9b0d00f3fe65fc6653b832be702e777548b1ea9c258d256d67d4fce4dd6b0d6b6a605b139a305987ea2a536eb87b6c3b8d427f7df314a12b269aa42f9f497e3402cb21010001	\\x5bb7c24f9687e959d1f84d0fd396d00bfa2ba5ff1db1a1c53bb970b9ab06fbe3c2e73f51f2547f102ceee6de8371294382718dea6a28aeaa6e82a2af01deb30b	1655204553000000	1655809353000000	1718881353000000	1813489353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x2991532f312e985cd1945b5278ae1bfeded3172f31c10b5661ddaadc10e15a2c4246d61e9103a35d1abf34b09b1e1f83afb323795113ba1767b1c98f23ec5c68	1	0	\\x000000010000000000800003c385f3491bad48a812236a570e8899e286be804740f9fa85756c9e5ed776011c62b3de6e9ae47e78e0014109f768c12db2e21d1a7ddeb514464985cd730c22a5eabb5db59c7fbb160c5939a281086745ef11bbb7508764294defdd067d296bdea91a42eaf32460c978dfe73d34d597b35f582709941493d28ff2795a25d2f547010001	\\x0a478c79d772044e6e86d21e6f56eaa83fa54c12931ead291f5124ff63d71661c4832b16c329212a141d0d675f2ba385bdc56548518e209173d1a936aa4fc702	1675757553000000	1676362353000000	1739434353000000	1834042353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
134	\\x33252a56efef0e112e7adefcf4b6c63f6f0f371af89e7343fc027bb4216823b7fe6fc62c02a6c36de4a232364a2eb837c254292c042a4f04ba72ae3379dfb7ea	1	0	\\x000000010000000000800003bb43872d342644682601d08568893a61d56137b325e815a5b927e2803d32e5adc79e4b3f5f9bad59726ba32332bcb1272ede9a31a5c5fc2dd50a9c9abf32dec93a14933ecd099334ddcc09dcc7748a6e83258e0cbeb97f59f3eb47e8a590462e5ee0ba41e2320af4617e6267a494f0fbf4264cc462d81faa27d8f7e020fe970f010001	\\x2ef4415767ffe6b71d274c6192beb9701d5555fec16cd665c871d2aeacbeb793b91b4291f4496a26dfbf29ba160fef9dbef7aef5b9d6383c1141d8e923ce3802	1666085553000000	1666690353000000	1729762353000000	1824370353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
135	\\x35599351028bf66237e262fd413e9f4899dac1aff664d969be16a178d95b7fc7aa77730cabe67a64599bbc764149565c5331cbe42ca84438f29f26f571c04933	1	0	\\x000000010000000000800003adf64ef8a1e12d9ab03f502ff3b710932936bd37e33b5ee0794251d2c6d83539c5e905db369574c0a9bf08213e4ba1e9c726a24d3cccfce510e5766011fa137dc766d1af8cf7006113f4ec793f03d628e1a0b29238b2bf9cda59f4163764d126529dab1be3e9b1ab8680de9ea4dc7827c77739a8cef9664afc198967986d9419010001	\\xc6868c54849f43ee05f35fbe0648f4902c2d06d6e2d1b55ff24013e5172768c811783651e61a067f228637c58c3f2550aa3ff1988d264fa807f1bd8bd8bd1403	1654600053000000	1655204853000000	1718276853000000	1812884853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
136	\\x36e5d4e05af4b2812c32a704f5dcb1708adb0047bcf581106ffb185dd5bb5db25388e111a1bccdfce10c0e23cd8291ad5410b78508132ece097dc4acc103aa81	1	0	\\x000000010000000000800003b7cc47653357f85948a4a22819681df9c169f5911598a67684135f22469faef0ee0f727590c125ca57711aa9b07280479b0f54751b4a0d45f6b5d52d6d6509445dbfb15e86bdef58a57e13ee3f63fbb1e7de29e3b7cdbd7c0971be80987be3be1eeb9dd65d5114d88cf64ff60c1653e3f204377e75878866350e1380b5eb32b5010001	\\xca5fbb8ba53da4943c15fd4594e018370f4a22242cdbf32721bcffe92cfc5c45bd07aafbd93cc8acb428a422beecbc081752f77326b20222a4e56f01fc259905	1664272053000000	1664876853000000	1727948853000000	1822556853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x3ae5e76029894c4f0cd28d52f16c74b6af63c131d9ec385719782a2709c55a09562720777727d72d3917ed8ccc17c20b9dc1662b6e1f9afa853409cd5abeff8a	1	0	\\x000000010000000000800003a73b5dbd1f06f90a09b461359c51514c14e00fb08a7bc9611377bbdfea39d0ad41f47de4b091d1cfce6c2cc7a088536a87ce818e41914eec6ec444c5eaa8e88d720470945ef46eda2b6557d5caaecf1bee07a27f76aa5ba77855142331a5336dc7f7dca7e5b61c59e8170e658a8d1525621b62ec1fa262678c47951475f6813f010001	\\x7d81e5f9de61bd5302093677206c245be2f0444e76b0893092603b46aa96cbd264e5a85813adab0c1eb4718c65c6c2d717ea599c5b3198feb4004846bb41ac05	1664272053000000	1664876853000000	1727948853000000	1822556853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x3b09274ae83905a07b3d817944d34b44f765858127ff8e73057b2eabd13603189aa468a4c852ca5ab6738de945f4867c7c4845010438e554a05e4a986525911d	1	0	\\x000000010000000000800003d44eb61401da7abe726c2ed91d75726f3516d7083bb70790da3d221d9f856444558cbd093228d0597c392d9fe70ac8f7a27b0a77297a9e70b10be2c008d98384ed7edb05bd02f2305da5b98a527a1d0b03b5cd8ac8aa3df5866edd72a5b334a02464d280c36f19ec15e97efb8c4549072f723f37cf2464f4cc093aaed8621cb7010001	\\xf3235351408bf762f43a7e0c24f4ad544a218d58cb0733e5c6b7a19e53cc11900b80704048676b9a285f40ae4e5b7f741963b1a583ffc344e83d841e0583080f	1676362053000000	1676966853000000	1740038853000000	1834646853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x3da9f8bb0eddfcc5e3df2a40f06aee839beff0373c92a359939799712c3c198e0c5f99704f24777ee087b3f475cd7ce44d6fd7fb3d488cca206f78b2f7af9a4e	1	0	\\x000000010000000000800003b12c5cb425748216158686c145455ce2b83d1fa009c4aa82c3426c2911baf691d0865387d22b80b407ab425c8fe0a1014b4ec858fbd7a5e5c1779476770e12b65ed869df75c5b541b6081a74529fa85bc47e18f3c3a6550f3ad0e9a4a203a2a86a463625c10eed36750aed998002c10716430aed891aebaf79029c7c306d5a19010001	\\x6f14e0ac5950ad182a51eaab44859aa834eeb1f3f7734c4fd2a8493140a452b16b58bdaaddba2ec1236d3290eef1b530ad6817c4a2e00835eda6a412786fe804	1647346053000000	1647950853000000	1711022853000000	1805630853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
140	\\x3e8575c612f62adcd06d59fa9d55f250c8b967427102946cdd21ef364ecd825c8223ceb7c0ef4370e2e9c6a001267f67d4b8a4d9eb8e894383096eb659b8bc7c	1	0	\\x000000010000000000800003c2d81ef5190d21c7456738fa35e12cbb8744654fa6e98da0a86b9f044cb96f36a9f4e53c609c155a2dd618519c0e3004d24f0e3b194e8bdcd674c6a4fb346f2104a043357ea290c3d8f86d745cb384efc95ef53148dc937f180efe2896d1efec2e1c38054337724cb6ea8b219acd5245375e63abe0105439c11cf58f70316a57010001	\\xcadb344ed52cc33dc41bb22e2129f3e1da519eef70bfffab00c5c2507bd799248eb3dd6827634071c6dcf46c9df198624d0ee23eae9015c8080e2047c883f10a	1654600053000000	1655204853000000	1718276853000000	1812884853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
141	\\x418db6890c69cc3a8473d2323253c131160b3f5aca5ec3a283d00f78382d441146481fedf911253830c2926cf50c29b492b095d161e17cce7c6f1249e7446108	1	0	\\x000000010000000000800003b5ace9d81d94bab1e612e0c568db88bccba935f2803d78acb66b582f326a8ac1b66dec182601daf2964a58e36c45c7aed3ac635cb84329f3f186d2c2c414a3f3d6087724e25a5f5b0cc779a727eed2614d649549059d0665f093a97e47b9f81982f9979bccec3c22e8c425c3c415d2b416c230748f3354169779ce11fd8b7f77010001	\\x872181aece565eb09061fac29d95f758bad13f0744e3a811d03e813af300f11509976c34e8256af23978054f909a2aed331a5b2a0af2099ddee04c9c0698e205	1675757553000000	1676362353000000	1739434353000000	1834042353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
142	\\x436193cc4530bbe0314dc255b0b1fee9a26f5f6a7d8d444b540d34a1fd321e738b35cec0ce2b021988c18f308a1cb45b8ad32653409263fe5cff93b10c819357	1	0	\\x000000010000000000800003edbb0928f4bf75f696e694b46a2bfe70c5e047e003b5a62474fc52fb96818695643a1659a17164f403c42718b37f449413f832a07accbd34101f61a037a710737f159d9372bd763fe5fc5685e2cd5565fce2b9d5489e9854647a2288dd55eebdaf9ca364908cc64346d4d19deae3057dd2db218e2b1ed19c009d74a60189c4cd010001	\\x58aa8b7ff8ea9aba2761fcef1e691bcaef62b88163d4d316d36f5d6c91d0efaf61c0adb6d1286fc587e812e46f5e2c1835642cee55a5b46e974fc39aee6a0b01	1647950553000000	1648555353000000	1711627353000000	1806235353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x44a514fd1f647278307a0fd92918a6020fc86533e946ac44161f6ab1afb53d199996c7fdd22b5d5baf2fd1a0e08b516df4145bc38425a4fe612d29018931bef4	1	0	\\x000000010000000000800003d11223ac3ee096a38deb5521e97d6a36ed63d8f826026f9950054509443eaf0e7a6976f68baf068f7bb4ceb504fa26bb8292b93e5b461d18ae007b267df4766da52696dacbd722157e826cf16ac4a9ca4bcf4d6520a54748e321523b2506b687284fcbe8ff2a03eeccdb454f7314ca6ed1a318bdf8ed67c1f60e55a1ec85bd6b010001	\\x42d6a5b408c7dad64e84e4f1ceefb60d206bbe3219eceaae51501d2336856e487944727b50ec03304dc6324f68ba171c481691b1893205fa5e992359647c0a0f	1659436053000000	1660040853000000	1723112853000000	1817720853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x455179e2b62c6c5c677f2366decfb18fe1bbb9909f9fc247e6c5840c29eaca4e5618d7921839c3675c087cea72d4f5962490d6c19b93184fd7ebdf4400a31e1e	1	0	\\x000000010000000000800003e19cc759a5f1d4e70319d094403c2aafd23e6d04697db24fc9bdb1f51e76afbec437c092eaff44c7543185e076b571fe6af0205cd1b7b780320037e0894b637904d07fd1170b8f653ea17844162b4aba0278800163437eb2a0f991912b74c08853755d7c8f37c38eb880318791e22f8b97e7e89976a46cdf0f49d57d6a62c3a7010001	\\x0f3b110f5337dc8b7c5c93d61bc913f84948a2aa4e8c8d420808063dd2174e4448f33d9131398929a9d31d1ada90144b3461f8b6cf0ee5f8deb0bc75f2930803	1649764053000000	1650368853000000	1713440853000000	1808048853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
145	\\x47910ff355574f0ba322073c64c5895de8e6017cd6c92b2919e4ff9059cdba77342722fa996987d7e43613867a397468eae772778731465e19a8945a6abf62d8	1	0	\\x000000010000000000800003bb708a08495ee2636c309dd3f443723a2a9b3aa6d27a568b843cab42a11b6ebc2b11716784af743decbdb1f6daee86eff306bf6c38d736e13313e1d7934e4082a1c65b72fb4586aaa89510f8dc945f4f6548b90c9b2b4e4c4993fd424f612791b7a557cea256a54de9ba7c077be07f3750a325486a6bb8e2a26f5101552c4ebd010001	\\x99947ffd9a00ed1dec688509cce5047fa7ae327a2dc486b531fac76db6bd208b6ee22fd5389b1c7e2752604940feec7f3f841d9e06a51c8de66f0f85ff104001	1657018053000000	1657622853000000	1720694853000000	1815302853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
146	\\x4cfd92f27cc538b31a8f9dbf0d700aa4bf77e94e0c4b7a01725d811bf77cd1cbd84463174d0efb1cf4cf24b4904185ee092cd00fd01406737da5d1650940cd17	1	0	\\x000000010000000000800003e2b9d1c578030de9a574006e3d494436abafa642b8065aef2c8b2c04941dfb5a524c95eaa8f1a532b918113774b3b24e8c18716b0c37ab3b74a6f172e3714cfc06dad6aa1929f7127df3bb03c3d4aa198c06d2a60070811065325f99eba74aeee2a5471ea7e0b52000cc92587539aa3ff2653b56a3586efd3d00914349a07b4f010001	\\x3a2bc248f94e0e8002767ee792dc66e276d98463ab13068cb7ada6226600579aaffe70d827d05dadb3578f1c914297303d0b33c3017a10b6a1666506d610130e	1677571053000000	1678175853000000	1741247853000000	1835855853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x4c9daf3434169ecf40fac804306e2f5e8228c70e22185feb870f95b958d0ece47c7419437453fde3ed7027a9ab91d067bfbde699ffb221851ab71e9243b76a52	1	0	\\x000000010000000000800003c08d919683ceca58648bc71236970603bbc306b0669b008bdb135de1ebc40db16b2f8d87e4399223cd8b427ab1992b91c96949aa2372d4139d67263a6f6cb446a649fc5923ab032d50b00a295d43e0053d4fd98cde7c8575801a83f3e5fac864d820ac15f8d9d3e2a4a22a10a39201af0cbb06e2560b810a104c843e464ae08b010001	\\x653e357122d369db4a3c744d04d7cbe39a1d21dfb1a885ba474c0c3ca18b01801d4109cba61a0039070468fe500656842548446d5f36fe1db14b4de1de77e50c	1661854053000000	1662458853000000	1725530853000000	1820138853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x4f69510541b73a1297ab5c80abee61a3008c425d58f5813affe0ee7a92d8736e660636053cb8edae7c93b81db3fa824a3d0d81e5a20b6f166fed8c82c954cfc4	1	0	\\x000000010000000000800003db738271573e79945b2738af110ce6bc385449cba1e0eaadeeff13dc4d9d8b1485e24f0ef1ac87ae5c3573d7f1cba1c70a5992e78dff436467709c3a0e4f1d7471b1154c2ccc1d8eac0643c6318b0fb15245f1653cfe76395724cb3ca1c7779de2678f487551e75b8db2c9f0028270dd775a265c589527fd308a95f99ec226a7010001	\\x253b0a6aae5df00de9f890de57996afb25a311f80eef099634b3069748fbbb568e0d79c846adf48c711b781e3b0c4bbdcd8d84021a8012a845ae95bc7267a905	1653995553000000	1654600353000000	1717672353000000	1812280353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x5741502050f7bd187a74babcf652b797aa601f9bf4929d3f84ca1e75d016383bb87bf402a550c07b886ba726e0eda53e2150324aa1e2db0fc5e021f5f50f2463	1	0	\\x000000010000000000800003bfb758209598c7ce17ed3444e6e6d2233db49b8acc68b401a6b6abbfcd814583b62e66e3095e914abd46d41e7b6745bb572c376904d8307ff034798016316b812730c41cc0d01e4b760a92088a8283e9d8bac19123fb924e9c652cd2640c782346507cae4a8783dad597a3fa15c65f0a6e5c861da963c2fa89c254f0f38f3483010001	\\xb2578108e04669f3de1821f1cc72fe1f5ba3628cf0ed8584c43b7939b5aa7974bf0b746a486492b7345e4f1e160f218a42b751a42edb6366b66b1e1ede22bc00	1650973053000000	1651577853000000	1714649853000000	1809257853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
150	\\x58012b5cb8162fb2cb6955455bf6bac3574c136764ef11044f734c5e19940b487a8e88531c4041b88b735dacc0b525b0da9a65426b9dee24cda83bd4b6697d9a	1	0	\\x000000010000000000800003ae43bb00c44195e0ff0a36211fee6fb339765d609938836eb43492a4b8194409b1121422562c079b558c00e33c1fb00338d7cd7e24478a3e7c18d92bdf80339b0309d0cdb9c22d2e93f43bd2dd834d2a7a7c90f5ead2e523876c68ef9f629d861a7b7ef16da30de60d18a029ed29d5bb74e813975787de5a5917f94a529f68c7010001	\\xa6e9a367c645c7e0f2240748c2f0b90b61e34f8cabf72e08082fcca53c7f702bab196a0b3e11a8b28b69d0742bac9eac5bc756941178666716310017d8561b06	1650368553000000	1650973353000000	1714045353000000	1808653353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
151	\\x59d9fc2750ac4742ec74d0ff369db1a6d6c38c730cc797624e9a8f6cd9a6a78a9327f2ed003373d20e8e07830ae1133da793c1dcdfbe73df05751b651ee8d58c	1	0	\\x000000010000000000800003f87f40c813388ea3a623a7b4b82f64e68a18cb1fde5a70d8386eaa1e6bff644b8cb7cd07f87e409da19f773f4f516d5397a2300ee1d1631885cd6d81419cbb09b171d8be84f3493c01c3bdd88566eaad41f3046bc277884421fe6dc22524d31c4f75b324deea333e41e3e139433c275fc7bde4bcd554d85ce7c557590ebe563b010001	\\x3ff2591c618cfaba0313c37597a61fcb652f016e1c8548c4c88003bc6c12f6eac425d786e7521c61bd4dc7334cf577ccef21e0efdf4d480a5dd79ff2c1f8790f	1647950553000000	1648555353000000	1711627353000000	1806235353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
152	\\x60dd629d183a98b4566291a79ebcaa3ca32e086f5ffd7c2188ab1954402aaa9f1e79934d65af1611c775aaa552a47988a10e4ff7eaf38493d9d0decd681bc68d	1	0	\\x000000010000000000800003b3c4e1ed39669e0c7c6133ffa849aa9988531aa6e889d87e1ef6bff7b7fe449ef157289923ae2a2de2fe1da03721ec089922e17b05862964f51a57ca8e5b56ca71d3d2a0a88347e5ec0e1e77e92b0ed2219055b3d44bbef6715d5e9946b808a17a85b058088f95480dc1bfe3e752d3e13dabe562f62bd4c520f758b72db7be97010001	\\x3c7241c70e2a36eb8aaef509aa65bd1e7b6169cc4529f92169e3db266a6b3b2e5a0e0612d6ad153c1a76d1c93ade306ba5cd87a3008380fe80cf32178198790b	1653995553000000	1654600353000000	1717672353000000	1812280353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
153	\\x625992976228f599d428ba614300610c3ad4bb9e04db9ac8da61c6a68081967e0835577f3dc8235755be1e3f35d3f1837f42e057c7cff6aaa228c4da8bd231ff	1	0	\\x000000010000000000800003c866580304adf9e7f7f0dc9f7868bdcdbe1696ca5a4ad1c7199d60ef6deca138ff5b0a835e95b6f090bd27b4c154ab8df143a7891b2f646f883041bc36cfec5118ed8fb34c5398135914f5feb39e4b034d48d73ce071d3386e919541efa74a93dc103747fddf888cb77aa51b122007b86b2549ff18cac8a8311522b7f81c7f11010001	\\xe8003e7ab0b3a7b52fcb9b8e8e05d26526e282e8f6f5147d1e3c68bb7f3e11f58493fc56a8eee90d491401535a837cc4a82f090c331eacc033b8b20bea901707	1655809053000000	1656413853000000	1719485853000000	1814093853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
154	\\x63854968a664fa7a2ccd27e1503a7ba1aa3f11ed5f7c379f06fd545aad811ad0a4281bcc173f1dc904474fb239fea8f8cf710e7c74ce93f668111c41be2a2d1a	1	0	\\x000000010000000000800003dd3a95fe06eb0b99a023047ecc30fe4db63c056510aedd60a5040e2c5e567e379f02bef6a5b4271e7de40f4409f619305ca8c08b62e3df4a5c8dc5ff4a7357a6c1e0ed6c0f1053a6e0ab940aeb4708663d6460d591bcbd43fd04dc2f51340ec054e4a7cab8b1ec2854a899ea9e340709d28f3754cfedfbbaf7560c5d3028ec37010001	\\xe3bb34febc965be0f5e04e16f26312409ed1ed905d31e0de0f087b84a3f65948dcbc36681242262ca670459acfdca7688737307e8feecf6a6d48a001704be50e	1649764053000000	1650368853000000	1713440853000000	1808048853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
155	\\x6525584079bbe6ce5fb6e6446dd0ca3b83b803cfa5ad4964bd5e34e07b8f63284613ba4a05e1107dd59f7b3cb3e3fe6cac2b4790d7a99e6b624b034c462d722b	1	0	\\x000000010000000000800003c3806f5e8653f0983f377843addda2fccb2f37b9cd35a6ab6edaf78ae4ef197a8cdce812dbf1b5cb5e3280c17c6e1d12302a45320bd25184eb146025c0dc6011e27014d65aef771d0b4bb45a3606b35555bce1ca04431254b3a0ddb11bf89dec9eb986c91db81eb5a5b6674e60f0c3bb1d8c1172d823bd793dc96c2cb08259ad010001	\\x179918a1c4f468a13e4529a9f38ef71ce3b894546f05c585d02d68d1aff267aa8fa467f69f83d0eb3cd1085270df6ab949d86e9a365d2b0bea27de1bade2a601	1676966553000000	1677571353000000	1740643353000000	1835251353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
156	\\x66218ea822222992bb052072ee3d33b7c11b8526d0bcaa0929d0c9c7d0234c7c05eb23801ae09e1597b280c12086470a109bd4b627d9e8e67d93b175d1627542	1	0	\\x000000010000000000800003ba8b8df1ae3a3bc884bf0cdf0222d8104ab3abd9a6e663988f5a45a185d4159e3fd2cf932e46a3d31e42b4a0237fb42fd17b19c36b958bda7e9631411dd5ce97f99534e8d5ee203beb51e1a61bb292623fa573d922a8f5f11f2492bfb92cc50f1b1571555686e01ca254ff260caea5d0698332b7e5453a798d8b19f8943be1a3010001	\\xaea8830fcc7aa2cbb3882bfbe23e18b951a42bc41e67c1c8d58135636424f5a2846ca3425d2b57488fe9dd69b81a504720e602063d92814b3b56455158f2820c	1665481053000000	1666085853000000	1729157853000000	1823765853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
157	\\x67799e83a2c785e281ad0a5cabc3c73bf133935e02c429c79122f2399a7bec31114621bf9908f89ad08e414364b502e7f1b95e76eb3d55672715e7b3cd73d2f6	1	0	\\x000000010000000000800003deb484818be19eda65a2dc78876282ef4b12642b4679328860655af7b422509331e79d581d060ad7a0967f7dee368f8f9543880eed594f80ec1e6f8afe71e391a335ef2f58d664e2e5f671a8e4bc71e6850b3454371b14d37b6b908934fec44b632ac2ec6d9a9ea7643584c88b2c05ffea113a3d51beb21ec36185b95ef2314b010001	\\x377ea853dde40bf52e68a0f78efaaee96d90df75e599647526c54ef3c87f07df06436cc8a4f187a0772d1d93a76ea8f9c314d7f2673e2c733ee9438715b6ee0e	1674548553000000	1675153353000000	1738225353000000	1832833353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x6b8d32e82e9e22eea104283e03642359a52561624710315260d4d91bb67082bd47ee8f0829d059f764260f544bf49d4a41a0763e26590de9c4705b863a7e33d1	1	0	\\x000000010000000000800003cd6bf71de250b7a2bdd5b7821d98651a5478654aa65a226f7ad93622046ef9b6241a58eb4a8ba0ca2c530ce3dccb169fecd8d735e6103f83944d974e7e21414307402210ca967e0c669838492a79dd0623aef5ffb846695bd08d13c9b34d4de53c06ee9e06488e482a461a54244b868d436e2887f6103d5528142883f565ec97010001	\\xa55200cf2854131dab77d3105783e7be177719dc005916b0542adcdfdd07588e1886c8059a5b8ca3b1b21d0a1520e9a21f293ed18cddb6e99c564542579bc80a	1647950553000000	1648555353000000	1711627353000000	1806235353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
159	\\x6cf9dd6455fe3124679200d215eea47f7932a6df466cfaae32a509c07c0940ef48e86afb2991c046e4e2275a4946b6c1698ecb7156f9ed6e9c388809f1a1f462	1	0	\\x000000010000000000800003c01c30c8d8938d83dc731b8bdcda9262ab799cc0941615b51c469a08481b319546204ef93212d3c7e72c6a4e2ee7cd0c06ac4ff8c725d36042c9f2804e673f09677dd6f1a416d97f9a63b7a72c4e15d5ee779cd49fab9f793726c9e10f0ad4b043eb21227312e4ef5716884f46a352af14a16cd0b6509e09b830d550238717c7010001	\\xaaf4d639c71e0460cadd006fe2d6e0b3b182217b10ac28825eade515e889705ff06a496bb894db42c8a85159d9595c5cfb9d246214548eda21b539b4e486710e	1669108053000000	1669712853000000	1732784853000000	1827392853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
160	\\x706128ba70b09c15e988c696c92e3dc14792f62cccc6d34f74e28245b83aa769e8b0dd566a7b0540372d0a251576403ae84432a9cb4355e605007a2ae9abf09b	1	0	\\x000000010000000000800003ae8fbdcc0e309748dacf3a66d35c21f45d41bdcb22e18114170acc6db4f99eb5b936f39ec4ca108662417d4fdf72365ab2d5270eda8a14270df61364f57c1fc836d7ad5f1a31991ae1c8d5cfbc6b5ce523bb3cfd4437c44b3e63cea6986bb0f11ba7c8c9acccc333e2ba5d3816191bdc6f23244332a6921cfdbebabd85972759010001	\\xf9f42a4bb9e51e575531a0c148cae4d076c1493fbcb2d834867260aa35c8307c82094f4301d2fe1e53c2dfec944b5be27fd7383f7039ec98408b31fb23fd060e	1648555053000000	1649159853000000	1712231853000000	1806839853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
161	\\x7065f1cb3d14cd5c3c379249c645b87b8635f7328c7408797fb8bcec6ceb8b0435bd4e4172cc91b49e0327b937bc6468b5b83d8f193a46747edff19d25c91941	1	0	\\x000000010000000000800003c08019ba12b56196be3240adc1c1bf85805e37c82093463d17aca10a0eef7a38622bdd2775945f14cd5ccedb5689bc0031f4af0e7f052b14c18baab3971ffae82893f9c1aa1d31defa81ada5abae646a2dc11d8b7372e844e0ed7ea877dd610347bad940892b6e633c55b28b05034f2feabde0b8ddb55d7fae762ab4477710ff010001	\\x6540c7772e5d9d7d9773827b84f7170c05fd7923e15428ed1a5e28705d4963f2cac7dc1528f3c0b98e17a5abb5064562fd39af33d4caa55eabe7bec246ddaa0f	1647950553000000	1648555353000000	1711627353000000	1806235353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
162	\\x726dddd8ab441d1ff56c9c4994561d434f121da16770efa5b738bbbc07f85a6123363c5399a625d8cb49cf852d4afada563b06345d66a3824290a995769d1bc8	1	0	\\x00000001000000000080000395ec999bab624299197c5d476e1d52229ce25e1ef625ebf7144bdff901d36e6c648e6adb2d6c7fa2305ae65d1231ee6c57e685001b35ab1aa1a1afc8c282c2f594a32803a2ed96c3d234808be53678f5e2b745a61292510de6f4b8c84a760e807a7a7a1654f9dc037391c0f02ad6237144e450d4a7ff0f317669bbc0e38605e7010001	\\xfb44feae11b4a7869f2c030b83592280c4bbccbd89ca13708fb41e40057fa84ea70b0e2e0a7bf390930ca5b61f0c4b9dcbdfc318e9ca16a5bbc2c927ea6a7d0d	1650973053000000	1651577853000000	1714649853000000	1809257853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
163	\\x74a18ede5164de3211cef16c338dc94dcfd0741178fca322f06f6965a1e7d6a8c9c872e9162fbb2186c52b43f3ae57c98691294c938cfe8447741749f94d04de	1	0	\\x000000010000000000800003e0b4a65672894e034ddaa06d1709e1ccc2e016807ff9c3c3cf89b3ca8f64c15cdbe258a0569316f7ecfce88ca8df771171d699be2a382780e9b8a4f247cce77667b49dc2b9c9d1ced78ebee384a5ed060139b99692a722feaf2a63adc73275e911038a38669cb8be8fdc9ecf0c3c64bb1dd1a911c2c878024b1d301018cc8b3f010001	\\xbe883f90a56cb6e6029d7193ae44b837c9fcf496d5b113e912ee7d90d891afc2c6ebc3ccc41501381bd597260324762e6bd37bb0d157914a4102d41cad253d02	1676362053000000	1676966853000000	1740038853000000	1834646853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
164	\\x77e52dc8158aee81564c0c8df92db371f33fc3510a7305d23b571446315dbc6f06abbc5f287c98c78c6590bb5ba2fa50956ec7dc796954f90e5a5e700a49ffb5	1	0	\\x000000010000000000800003c00bb27e2c95d1454e67555ce60cc36addb29c8913bd92242fe60be77d831668a61a69c4aa22bc1cbdc80c66300d5b2b79dcf7cc330046e0080dd2fcebbd069f8ffde7d065939bfc794a3f3540a260415f12b4cde2c1ab400faf43f1e2829c778f71b5d01775e27abed4da39abb8d23abfb1b5f166d64244e7bfb790c284dc9d010001	\\x12a28b715d7809471cc44fcdcc910c0cbde770e73ee24e8e99d4de582ff1870e08829364bb1069129e7bb5439fd520e371053f1e8fe9a5c098c8dfdb012c1200	1670921553000000	1671526353000000	1734598353000000	1829206353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x7c291ae7ecfc13dd1e292d5cb356c69f54ee169729c2fd39dfb994d39513d6f6f788b659540571f3995b04f401507802d66ce419984f00a2e6b67ec5dac0a278	1	0	\\x000000010000000000800003c1d870a8238d7243917b4267f247de8f8270b2afdb5153c8e0e19c6c03b1d1a0725ac7749189a77ff97ab423d9e1375d75b16d668548a113e50d4053e5a1d25589b78430da14c1486f346d3eac1f2650b86fa9e0bba39d7335b0cf4ce211ae409bb713bf92d4b1bffc00c6afcd1edd65fa3163aef49813f8750b644ca15512a3010001	\\x0d803815b4bc3409f1be9ea78b6220b04e327fd501e5b0ff271aeea579ac690d30ffc84592578beab9a1feb96dd64da8b8bed86327685d17ee87a6a8ff5c0a07	1666085553000000	1666690353000000	1729762353000000	1824370353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\x7de54bfefc026cc8d0c13161627452708e66e7624f3e65c191f3ee4e13bdcd994a46915eac1a4f9f6eb5c7e89e3edbeb280c207c3b215e388ad7df722f3e6e74	1	0	\\x000000010000000000800003c4463a45fb030a0d73ff48fb8867d5fa1a5f84fe61b83c96eefde36b02cd8aa860b2901ea6d49f78ed77b544ff57a7bc6c4b292eed8d4170c5e77f2dbd200665a373e80860fa215743e211789dfe9339ff8076a7b348382744c75e66ce3f4886e69182660a6af84b86eb87223a2f0a2b48f3caa98ac03545f69cf6dd672007ab010001	\\xb2e8c2b30ea07bc52470a2014aafd103a7c4d393b8385d066ed29ab890dc593d5f3af6b0bdd973cd6914237510b1f1bacedbccd4fdffb1108ee9af1c616ccc04	1652786553000000	1653391353000000	1716463353000000	1811071353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x7db96ef1590920a662caeb0db9387a3e69ccf7653a6285877efd47a08c5097a7a9be1641d7e92e075a951813d554fe7ebeff8d36e944e1d61c5c24ebbb3f36b0	1	0	\\x000000010000000000800003a7e5ece1017bd9abda63a011cf54e64cddffc0c7e5565caacab19f3ea29a6d0f754c90c2f48c467d3781ffe4ec4812dc2bdf963d4408c454e8292bb976173d2d85773749e70a2ebf070170a79980fe149ed090e694b34734c41527bc00d8beb1d8d7d36a2bb3af6db54383b3bf478018d4217af5bdc2f9f9064bf27be0f2cbf9010001	\\x45292bbb426441b865093fdf726e7a6a5ff116f330838d78499aef4e721102fbc35a92f1bff2bcb68e42ce13ea6b060bc792baca7f0f0a4b9872f09997e9880a	1667899053000000	1668503853000000	1731575853000000	1826183853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
168	\\x7e5d7a6aaf432c509955362546837f3b6a3b0ea484ea64b8574b16f32bc05d2307e5c52b96269f91cfdedfa4c637f37398c94306ea9dbfd7f14b44d0e4192f5d	1	0	\\x000000010000000000800003935613c93c41a6d0f8e5ebde55b44267108f77d1a9f40d11afc5c5e10cc78ba15c817a8ecc8f68dcbd389d3c26cb2e5c6ec85f697c23ef3d0ae1537e83f6d1e02970a1d363c24a2b7c72f8504b2c074d1c6670298ee876cb4ed04a6a092dbcc6c207c50922f53a838620fb9230d1039f59ba1eb50f49d669bc10df984693b903010001	\\x773512c1bb48fe314fb311fc73b06e30b2b3a4d1a6746b77bb882f173a7a2906559c97b35a8bb1bf347d734f149d00178e3dd74730fd627b21a0d3f258dfd108	1675757553000000	1676362353000000	1739434353000000	1834042353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
169	\\x7f3128fb83f735a00004475d610906747bc3167d1c137b744cc773fef9ca658c76c404267c4ab0634ce361de853dc9fa4702cd4974ec47f75a962bb8ca3176e0	1	0	\\x000000010000000000800003d8c0ec598495079b3bdb88621cfcbdec1f211374f8d637020430682babba5d8239444cb8ccb24a1139183351231d6986c16e426f85f19d3f7cffde7b03b194749a09f15b4974d035c462d57bef1ac4870d676862e99d1771b48ee26763d8c1a2a63caca8bca0cc3fe85343d9c27f16eb8579c6609a7f3d41d29c411cf46081eb010001	\\x4f95b46fb333c05f0116131eee58784af36b58ef3329310a52b59f3ba306864b7ac5a7304d5901ec0dba8a8edaf495bf3cf848dcf23f03fb525265c7d9e1eb09	1653995553000000	1654600353000000	1717672353000000	1812280353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
170	\\x8215b270c07d03bf92992b4ed583ee275cebc9b4d892d376a0c3df10a04b48e4983f9c89c81de964c61067d6211c6d7a03628dc2fbecc44623a163af1088cdae	1	0	\\x000000010000000000800003d1ad5d559a79a17054fb02e08b27daa9f73ddafe17876c5d4a695897e4302f7d7ad08d17589870c0101239f3fc131ee1f1501ef497e06c9d190e70fe69feef7aedcdf6d34d41a324b8d48095a9424c0fb893d00c81d32dd21ec417d16f19e378a7d3069e310c36ff09e460012ba01afb57a8194e5a923c05e9a5935dcbe60bc1010001	\\x654f71d99a809be1f8b26bc79737b3e0ad207f167397751c69fd67f1aeca2e9757eba7fef87abe4ee2a341d75eff886ba030cd2431c7c0ff4e5679d1a7371b06	1662458553000000	1663063353000000	1726135353000000	1820743353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
171	\\x8405ca0d6eb856ffea42e0ec3f1354213a4a09fe3f5f9a4fede1c0fd34721a4ff962b52d5c6512cf2a70f87fbf8ff6d97cefe8bcc32bd28800edd179875bb8a9	1	0	\\x000000010000000000800003b4079d8e5d6489731b837ce25cbe0815e4f7c0af0d14f0fef53a55e8dcd88d95c85e48a24954c0f24e04f320fba5bcba6bf264360e96ca9f8e791b1709bcaba3c0787bc4f7ac3c0c5ef61effc56e5c8b59a383be5dbe51daf54fb242df5dc05cfbe490316eadfb8b7da56e54e28f8af92f072a6c06aaae9a36bef3010380b5e9010001	\\xd49212e37a9f6b7a5770c39d6731b07660def88908b6031d2432a71fa4c120b764462ac7c243872154fb856d6e9629da46354dfa35c22b1b61a577379e1ef009	1669108053000000	1669712853000000	1732784853000000	1827392853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
172	\\x85b9d72b66639e3d57042777db556237ef973dfb3753b5db6024cc8da0d69d00278a910f56d43363ddcb0ea239812d15eca95f79b46ed3dc3599cd963f797577	1	0	\\x000000010000000000800003b7c7c460072553c1db21cef8a8e40b00da58559671584642c9f32b26f1cee72bae815d7c2ffd762e79a21bbf601bd4a5d846357293211e98dd19c2bc63e1f28bb055c234841a49146afeb68d23e2faf741d7dc2cf1c39f3ad57e2a4b028aeb109f77c6d4a8eeb9dd0bc2d2d22cd0be3103591aaaf29256e192d74d9c025fcd47010001	\\xa6b9982dc1602a9d8d241f013b56df9227e769277f6dadffeedd8693b6f521028bd402c757b3a3092daa397fc54dacbb576a280d8df6ef6968c1f57deed6cd05	1659436053000000	1660040853000000	1723112853000000	1817720853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
173	\\x868dbc945b42b6745d0b4d0058f892f4db92e361494d6bdacf5fdd5f493dcd3ac69aab5061d26fea6834301cda6bb1904fa53a52d26f8f3b884b96edebfe50e4	1	0	\\x000000010000000000800003e43c92a11f787bb90d6209b6c048fdfbc5ca992d82c995fa9fdb1d9f0fde7e2bc2373400ce094bb2c3c77b8f87015ee3cb88da6785ad921bc4976af32e85577de611ec6bb3e93b93b61f5f6f45a5d71bd62ca1cba9e818c75c1f2eb8323bd1ed00d1f7e14d793373ae5ea45caabb314b87be819d0b525ff13a6ca0836731aa11010001	\\x8520dca70d51783d76ac69d93e4442bc251fed530e321bdd277d8930702c65c97711512fb8ff1a4987e7c5cdf459bc732c4b86ec9dacab37f9abc3d5b453f60a	1655809053000000	1656413853000000	1719485853000000	1814093853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
174	\\x8711ab9932026fb299db9b1b66b4beba0906335abd61369e4a198ccb7f0760745e0ffeb1fe5efa265ed3ccd749c3186bfb20e036086e01f42c334e714420937e	1	0	\\x000000010000000000800003e517e51a8dd11231ba4a45d9617f95cb70baf674a3c53b40a5a97b55b4451c5c35636ba83afc7c098f2ebf16a629c57bb85c0481daa4bc124e78413a05a5cc8b224865b0b5dd742064a5cdcbcf902d316b3c830a648916b1cf3ec76b79593c9f5eae5caa3c1d7d3f27cf1a708a639e9a9200e94ab8f018941c6917d93b2c02e9010001	\\x2283a3dc4f8456f7df27c157a26d9a40f4165e8e3e1ec655806cabfe33034333846d205053db3d61c431d3b05cd1a7db569d5c81161174e1599c8cc189921d06	1665481053000000	1666085853000000	1729157853000000	1823765853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
175	\\x90fd4da51f1021579921c3e0ff2b40f81f517c523185d4bcb90146a7fa8221a9a9d06e3edb80f146a3fed904ed76b269307bc454a91f528ea20400797ad6653d	1	0	\\x000000010000000000800003eefd18786304920de1516fe632d2e1441ff93a871ece2a2dfc9b32270193803133ec88a45b8844bcfb920ca34674cbf53045435ce33fab0e851a92c917f5519580800093bcad7438feca0770207926dbd106c0b6052d57e6f792ab0c5af79971170a180acfbaaa00ca4045890469ebcd119a509bea5398b16ca905eea1e8646d010001	\\x62f098c80b11d7d79bcce305809b22150353ded46a8973b852bf684cda0d905aa51f8a03e2bb25c83ed991140ef52018f851c3d6644a137fc8b600aec432af06	1654600053000000	1655204853000000	1718276853000000	1812884853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
176	\\x959d32212b338772f6ed25ad21cd3fd9dece857a38e0047d1a373dac3cec305939d3c60288d3aef45ed3fd8ce9c2a80b0cd2d9735405be6851df2931cd44a69c	1	0	\\x000000010000000000800003b7024186cc14a82e317fd69d1a151b172b0ae27b15046b7099bb2e5c56eb6d8594bf2d371e6319febb5f9f6863cddf253be85e09dcc0bb038962bd2d769dafd80b500533d54f93ab94211f955f99d64e83521d867ba665c552d5bfec68ad1b43d3411e285d58117d30019ed759d9a22699de578859d6b88ac6eaf6eab815faf1010001	\\x804b377e0b106d387a8961f7424b0eb10bfd9ca6223fa8c07b4660d820991805b2e7a45ba586e13df3ac0fa6602bc1e08a3cb6dfe60150ec6208bc72cc24b400	1668503553000000	1669108353000000	1732180353000000	1826788353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\x9735880cd32caa25720efaf80b75c62223cf5dbb35b688c17bf018265131359dd36167fd245144275825c647132bd2bc49ed958a4bfeb5c79d3b1e50c76e8a68	1	0	\\x000000010000000000800003a20472257df8bfd0df95361b2d80f92a5c89a85b8e1e33a60e556f439c23bd11a5dca873f5d3244509e641bef68e5e704e2294a53c619c9ecc8dafca0e50c4ab989403cccb7c879591e3abd22e51d72e97d7bc2bc515bad8b8351633f4b3acd5f95afe92e7a06c158153adf0963c587c61f0723b7bef9209548436d7b9668309010001	\\x280a36947b6dabd5ee5c757e389b11c7d3782e7dee0238f56cebaad7b900a152a0729f11928fbee52a9bcfa8266121d3b5dc23881e5bd1b375d758dfb886e807	1669712553000000	1670317353000000	1733389353000000	1827997353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
178	\\x9741d0b9247315bbe57e344d05e1b797b674d3e52dc2a9b45b833d8bde86f96188c526f6e794fe56339ebe7607b53dd9886b663290b2da9132642886b09f186a	1	0	\\x000000010000000000800003a9a908692d67576ed713a630da60f00341ac8e8b0572e7ae07b831fae72af634a9e8dae69d09183dd004dd38a0c96903905bb2ad009ba696afa231f00649c489b8111e0d5a074bdca9666858b64300d91dfdaa91462969de9ac7221820d5ce63583d839709bf24ad38f4ebf5768d0a5d7b30c945f2f8bc2cc814de47f42ebf63010001	\\x9cd28bccc01bc8cbf672edee625ad99370dd06f0f45dbe4442d0d7e5f1240e1013e8e878920cfbbe28c4e31f82d4e6bd1802aa8c13466152f6170ed3c5731a0d	1678175553000000	1678780353000000	1741852353000000	1836460353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
179	\\x98d9808a969d0708e598d212b1dfd184efe2b8a18b2ce6e65bfe5e298200d37e7d9b536d65facadd10b803bed21fa96f9170969f0db2a69197823290b3efb7b7	1	0	\\x000000010000000000800003d1bbd833cf14ec42e1006b838f66f5ebc3607658eacc16dff36fdcc359393b730812dcd7a1b380f8c40b69006f4ea4dd5507a45c9f66e317c20d97dfc76cc814a5bf3b7c7d6c1f9e59efbdb5811ee106b00e7532625a74ab3e302068ece280d70086d7c7bd45fe5fba2b991b2340598a297e037b37caaa81f9a8eb8cf4eec11b010001	\\x73b276e08ea2f97c6625b17d061a715ed931465b4da2726a7bd6ff20ba9dc4865f36a86c6c02404f1d800919d0259b8b29829460df257eeae1120634b1121a0d	1652182053000000	1652786853000000	1715858853000000	1810466853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
180	\\x9aed6638928444b9da08dceca51ba97e13cbf68719965030f3425e2a5e6ffc8ed55471f6caf13bae20b6cf17ea6077e948ddbae512ad8d1412803c1e632700aa	1	0	\\x000000010000000000800003ad39827842d15e507b97c9f969ead8a597050025829f1da3d8f4748ed7cbfb904b1802697aeb5232f63aaa3909a074c0052dd8d03fbad1eca99b4f20364350f49a9d4f563d8a39a74670b447ed48ed587527328ad7b33732230021b94d8283e12a40bc577c7fb470c78b8cab368e6ae553ae997da2aa382ce86b205a023293ed010001	\\xe23941460108406b73678c13ee83996e5326ebac73a110e540b277012ede8afa69f4ea3a8eebe59a53291125b0519eb79fad9c43c966b62f3d46dc208822b10c	1648555053000000	1649159853000000	1712231853000000	1806839853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
181	\\xa3f523d3068c35a34492275484de108f41852270c9cdbc6a3069759ec7d75389ae85bf91c33b987c4611ab2d0d74cb5ac04410bd61909f55974d8f6ee76e87f0	1	0	\\x000000010000000000800003e22619452a781509b5bf133632baea576d0f22332fa98095a0c64b2d734cbfb7d766915b5901ca0d289e0c2774a2860806e333e76cedb0628ac3d9bc65cc1d1a02641cb8c9944d186e5d2ad29855e170a37befdbc962f91bb33b5ba019cfeaf4cbd3df304552571210558cba178cd1b9e447136b7717592debe42d5d670406a5010001	\\x0f6b787fa62fbb5bf370e4d8ab855f035268cb40122829f62a73df3e0e6c18ec4c1a80ad0c69d3e09597463157cb834f7a7471dd9b93af2feaed34a186b3110b	1650973053000000	1651577853000000	1714649853000000	1809257853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xa5894ed5b3ab4497a772d54d3432d843ddfd68def2a23d89c5d2e048b5ca9d87a37e7108efe44b00dbb9b637bb541476ebec3e3bb3f64cb811f0048b551443f4	1	0	\\x000000010000000000800003a8c3690f294d3c6be56ed5aca236bd0e7a76ca102a3b24e66b887b933317de1c13462eca39b9eff3317f25650fe3bf4a2ddac4237b605d29274c5ce598131feb68297286615028cf89d27f90a1e7fba985b9fd7178e11f8440e873c25336074d5759ec22a857941fe292f937f97f53a7b5d3f23aeabf9e5407387b8184844af9010001	\\x86c64a45435ffd44e3e75ba9110254f786c66457d39e3a48eecb1cbf36dd653eb23036bf99e1340eb8e96ab4f4abf1d9619507ecf99d0c1a2760f7ee3a08760a	1662458553000000	1663063353000000	1726135353000000	1820743353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xa635a1f78ddfd40cdd7503421b9d176a89fd4e1af3f9f7e5e333cd2407966021540d17ad1a1adbc1c0f8ea65743b56b8f500f1c8055b080c884df09a04131282	1	0	\\x000000010000000000800003a0b35518fb12b4bc61e8e59442f899f74294224aa38f967d195de1776badc94dd92a217e5fa56fd5a25846b749869f4e826d646c82d5bfff66d053f7099ca98c36fd1035523255511ea7fc6210bcd5817a50e6df9be1a750053692872865e3d24468497f1c4aa220dcd9375fc8fe26742d71665cc297e8f3f6e5e168772e3317010001	\\xa4e378338c5ba6d5b126fa4424ab6a596ab2ebd014e026a3a3b4df821f550f3063afa132c13aac96df67f3a60a03b76cea8954e79649cf20a1fde60096567100	1662458553000000	1663063353000000	1726135353000000	1820743353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
184	\\xa9f1ba610a21ab0cad4166d13e75bc5da8b3c9aabee9a6b8f0a5163584787fb48af9640478a3aa1b93f039837cd9b7a979682d36f4bd305468478cc5972a1bdf	1	0	\\x000000010000000000800003d40e66b7354bc09db27fd073ac4406145f37952ce88f64be843ac878d69d3ff478d6bb3ef30f7d48f697cf515837586e3c6b81456873cec8a6e2fcda40d4d5523e8a36bddc7cc900bb70ac8ad4b34393db46f24cd825a28efb2805f60e2d5b668f6224d282e7a6b058ab1e8940b4f584e91fe1381e96fb281e94d0ff0efc4249010001	\\x7deb73263732c0fd7e5026d82d80e5b42d526e68a1426319e45e0ae2e138e2f36d9362ee10f864b3d943a834df3b53e0234c6014dd5f32705357746fe916fa05	1664876553000000	1665481353000000	1728553353000000	1823161353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
185	\\xaa0d7b29eed785cc7bc69998acaebcba826b09fa2599306a22e2a129bc32b0349af5d35669b78cf73733b0b617b84c9e6180cd7ae0ef222b35a25e8fd7a50435	1	0	\\x000000010000000000800003e28bc412442df773874037201866ec92e1eedd7169e2d28422b5f19ef0571a2b87b926dc4b7e94bb18ca86a3f7258ac488592acfaef2b95345a7dec5410ec39769995343dbcef866d5edb2c91b049463859bceb26d9a636082ee68d764e1fa5ecaa95e940e2b310e33add0ab1226dbfb668075044ae9869ff3a27e0ebcc8556f010001	\\xdc49b023d35d47b19bf4b338cc02b24f2188adc4ebab9c91a4005948f54e52d074b058b1b5f95de586451c5fad9c15163434a44c1b96621b4e66e93f4945360a	1670317053000000	1670921853000000	1733993853000000	1828601853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
186	\\xaaa9f412aaed5cf56a4b712ec418df1d82bf1b29a4c9580d874dfe8a61e12a5d9692bc9a75701ad23e7d049daea5f628b411cbf5a55368bf6733c1f216a29778	1	0	\\x000000010000000000800003b725327850056d12e6c8ed39b0bef75a5ee6368c0ce8c8d6bca74749ef576f659c670e3e24d95646a245e8a79bbe9ccf7ffe972e9c4a5f758b3978b16b690b6f89fd0c3a77e79afb60fa32b4a74e3659ba87749a4c45c93c113e08bd7ad63ba87d72eddb85b02dc039bda2d0c3eb225001a8d8354bc918bdacd44c5409b863c1010001	\\xa4b8095c79118bbb1b91b45f2b558ee5d8e97e4e77a4965db86b413a8d2c867aeb15445e8fb2ff329d5d7e9b8018e5edca6c4407722793721f4008a33260b603	1674548553000000	1675153353000000	1738225353000000	1832833353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xae69a452d559e4fb084a3b320c1d3d408ddee0b7012e92b9d0e5280fcd6520aedcb9b3fc17e09875197edfae6e427d5603683449d2ec0466471d7530dfca96fd	1	0	\\x000000010000000000800003ae60aa7162578a7f5255951bb3e783cbb39c87f7dbe5f64e66e4c76a279d6733fa648df250dae69a7e002b84aa03974477dc126aea7a7c4f50c30a65c9564ea2ea6c3e9fb86d8027e78b2216d0ebeda0650292a60f10b2b82677a31df6a9fce535221f8817fffc5d474f9865b3d91ba47df0b9b82a52df217dff0e1e3fbf146f010001	\\xd312c4722953158bfa177550c7da06c72c3e74113f86dd7edb62829a6eb456966019e1bd0021da86157445ff3efb94bf0d65d3192fdd870cbc31021293147b06	1649159553000000	1649764353000000	1712836353000000	1807444353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
188	\\xafc1c4abaf4cea380dc5d48bc6d4f4f118e3d12aa76e90812f99d66d23094acd8c388add58ed4dc077775465daf8a7e8ae045b4d8f157cefdc944b67c2ebd2f2	1	0	\\x000000010000000000800003c5beb3b237ea136c49a9f65674f3fa3a4acac46e47ac443b2fc6f37eaca55c4046236ed748ddfda861c5e0ca6a5f77f0186eb24b449ff251aadffb99764065ac262bb2dd0cfaf651c7555eb1e36274a146c8edeadb375845394087caece7106147d4f7d3dd6497667bd5d89be5cbe5a95179585e8e97a03702186e4db5438ca3010001	\\xf1bf5b7f16a54962f07bd6fbf97f094a744f6cc21964534e7c8db6476bbf97756ef14407a5e067ab7c6917180fe53c07c0bebe006bd6da6b59d2c8b2ee0a1d08	1674548553000000	1675153353000000	1738225353000000	1832833353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
189	\\xb05101b19e21d47324502ac0310fcfb1f3845aff902d90b4dfbcd7c3cec3d7b6707ad91aab226d2b337a137aa429f20ea85452f21c0e14ae88025ced8c814c2e	1	0	\\x000000010000000000800003c3722af7183188064ab21e2348fe03a067cb760d98947896670cf92cf29e17c01ef8b5ec5dcb3f864735ed1925efb965543ce6dab74afeff6003cc1454aa17eac7a861c24c7f9cb6966115a461858f3e843f54151cc43aeb53ed505c38930fad63a8c73af31b40ae185203531848736bc9855e355512c8cdcaaf1570df544995010001	\\x5e1bbb6ade5f677445d20fff72ae8cdb60ea73af8c8817f09a63e3e5d612334b1eb3ac47754bc2a215553202f3e451797da9ea983587802fa9a92e637cdc1307	1661854053000000	1662458853000000	1725530853000000	1820138853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
190	\\xb169426f2154a0e9f4919839b06b4375d98db0bee5ca4715d4d808347bcf0237b8e48561ba04fb594007df5c1adb2040f09faeef0687fd437c9a711968d12242	1	0	\\x000000010000000000800003d9c218cd3ac3d0a18c48948fcc30becf4c2acbbe85c95fb74ef43ddd311db84c1e9be1061be779b07bf27e8dfc43789402237d5603e879ed8c9ed6016dacf4a2904bbd8fb384b059bc037a2eeada1cd9684bea4cc1bbe2faf94a512a99a81d615579be072921f33144b869f37ea675a26e5f10fa74f4cde0946013c842efe7b7010001	\\xadc33bb90c22ce520bc9427ace58c17f6d9055b2f695ea303b7e1326eb5a338c5c96c22d09d69fa0d6ecea827ae70f0bc9989dd15bdcc6712699d19c7f9fa900	1672130553000000	1672735353000000	1735807353000000	1830415353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
191	\\xb721f9841617fa12b8d7de61a87a78db8b32a9467861b9de2433b5a66c2c3b6e68975502d51db5b33aed762fa41766e74d43af48727bf25d8b8e23cf3cd43c4e	1	0	\\x000000010000000000800003aae3935e034ee1ca08d18abc1e88eb7aae7ce196c3cb311ca1253cb5492a133c9018428db18b5cf682634b975835ed7cd1913f919ab59a7efee61ca0ebe26eee57eef0112e08e7473a04990680aae8ac047a1f6a44218bf702afb5f58e46931826a746cb1e6fd11b0059bebdac98df15f9486d0027c207f0bd01f889c3a5cc2b010001	\\x8e0351c1b1ffc857e7783b4943d3e6f488976835a4dd3d31ee37d887c632d8ef85a907afba5db7ea26aa7bd7f7e739a161b4085b3d145f60a26cefc01f18090d	1664876553000000	1665481353000000	1728553353000000	1823161353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xb7b580b817fcd0cd269da841df156f3d9cdf36e5ee2db4c6163dae6b7435080180ed72730fa47741c2d9b14ed597bc72c330939b48ef45ad1b63c337eaef6d97	1	0	\\x000000010000000000800003e405895c29e121765e662533dd5e9e9506f077a3483eb891163a432968d7a173578478c6442a69f77fc15ddff71c30e4e9a82478a5c6d114143c8dd014ebd18191930abac60e8792315ae29fa5a1c9a5eadb1354e6d45d529960c0a46369b253a4bc5d3fb9e2207cfdcc65c98f8ba0a78173796f5ca2c9db222726ce49dc5651010001	\\xacf272a799107d3bb06389b546c3bc99fc1d96f4660bcc36d4ee92f8f5605c7dc948318382e78c82d131ed937dfc628659c77f4b31282d0a56778bd19b71be01	1655809053000000	1656413853000000	1719485853000000	1814093853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xbb99427b2969870d9ea0439f7beb56e0c33b3a21d7269a316b2b46ef1a4304aa4ae006cf0797111d0013ec92b853aefbd8658a7f32ec8777f4f4ed3743af2432	1	0	\\x000000010000000000800003b610aec9c7f37bcfaef91a5a6c739ffcf64c51be48ec10c86962172abb4af181363e194e34992d45f6dd982fed245cc9321d6c48503591cc832e48848f8957c2aa6fd30153db36b9d58b6cc72ac1b52a3757632fc2825e2c0cac451ffb5dce7622c5abf64ffc42346a4c4f8662e7b8f5ffa291ec6cb58442dbc60abfd6f6abe5010001	\\x6091630e8fee9ed0578a49d20f5b5043d6bd1ba13e927dd521c29799045a42a452a0415bda08dc652eba1828469a217a27380815546397b12e9760a1e232ce0f	1662458553000000	1663063353000000	1726135353000000	1820743353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xbd351e7661fc077f522376cb13cc9002425ff36cbe55d58ad5f87757e442c8f50abaa67d67a48d54f8eebc219169e4cb429ba0ad9d0c47e7fd6f1077208b1cd7	1	0	\\x000000010000000000800003a76c02fbed7b8ef56744caa8ca628e07ae79bc2912a0919a461dc3e88a646412330ef6e4854ec952f369a7317ff6a9e01bf0661a57ec9e9420fe36ac74f1d639512ee88d2af8537756eec79ade4deb73eea2eb09071a2d002562f478a7e621471720cae6a27252e02768cce6aedc5a13a99df3b624a06106aebf2d180f4c0635010001	\\x2ba12f9dae1f2d28c28053d755024d4cf5de8b28aca798a90b052068b0f62bb440a077bcef87e19c15bca222dd25089a4de92252d64776a94e3d70af205d4804	1675153053000000	1675757853000000	1738829853000000	1833437853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xbd79e195157e36cb5e7434fa8181120963a06bf935e1cfed292a82862088713e7787d9c8dc1ca49f48b0e000df90ec33f1cee3cd94819d6ce34e52f3c15eea19	1	0	\\x000000010000000000800003a50f9d323fea0dff8f998ee34746b9c27dfbc25abbf13b071405af44247ab25b128b19c508b32683fd77981c0522ae98ab04cc44f921305ba0aa7deb9d0f97cb409f3644e3504bf844a8151ae4b0df98fadad83e93b810d7d5c3ce12e8988995b545343467ec0e1578c74152c8eac4bcf855cf885df1db6f9d05ad46ce463db9010001	\\x831b7c1ef51e25bebc8b07c69a0a5d970e3634e9d21d21ebcf3c88e4914986b97e933aff8080dcf419030231807b2469e7cf8242f5cb2f57a97943c65fe6f302	1660040553000000	1660645353000000	1723717353000000	1818325353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
196	\\xc9a57cf46df2b407a159848c00024ddefe636bac844cf461dac9387a2d928c11d765e95e2132210a25badc97ef098e6250ba4ec5cdf15071f0e3bb092df409e5	1	0	\\x000000010000000000800003c90f3ac8e2e36f8c5004fcccb0ac9538c39f54cd4f62a99d276bd6675fb623279de2b683275ca26e15e0b5b56d308bed5c7faf7fafa9b3210bf625729d4b12de33c18c481a7d777e18cf44b5819096d4f43650bf882b70db8315aa2463de64b791318b639548a448eb1fb87131c20cc590b2fc0be87dcb09530bbcf6e4ec508d010001	\\xe9e562ba9aa1eef79e2ecf385acbd97e64fd4a071a64007606b675c62ce1dd2981751c848bbdfa4871629b0a96f0fb37b96bede57b05b19cc48387fc0f3f160a	1660645053000000	1661249853000000	1724321853000000	1818929853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
197	\\xc9c56a9af21a06f8a40bf640821d15609e28fb7a9116333b5b7903e718a4c749dd22c4ed309573d40ef454270975ff524b17a8625ba12f5e49a780cb9582fdff	1	0	\\x000000010000000000800003c13bd831b90a95b9461762d3f6528b98cf437a9120291d9d80260e87c9eb99ede61d64cf2e3ba294c9ca80aa949baa8cf4ef044f9bfa12d9217ba50f11b185551d65ac055e64ce17545a48e0ef34a0c078846e4e129bb5eb9773a03c798bfe454044efafa7a28dc2380dc7c5e9ba9fe870b51d5bdf7295702a54524f599788db010001	\\x6d9c499c52e4b1627b78514980984262f11311cd482acf44f82ec9ecf08184fc3619fcb64edfc79b752e754b15a56028bc2393678aea939d66ca5a0dc5f09b0d	1664272053000000	1664876853000000	1727948853000000	1822556853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
198	\\xcb19e4c4e7778b2fda13556adca9d02d340e773f1de0c14e052d3f30affa553c170af61718cf1e7438350d3ee5de7e770015c80b489fecc4ed2410e6c39e5d48	1	0	\\x000000010000000000800003ed2962e5f5000621aa37545bd9deb8488e86a879c7a2b78f8920218625627e6d5460eeacae9df79214ed2490b870ae7934b40508b87228d4c2fb616dcf67cc3fa73048d3126ec65142f0444782d76a2970e9d0135e4b19febae5215f3372ed95e858fa993a9bda529672c473bf994c9920b006888392833ef75de172d6a07155010001	\\x360e69bf96c5efb405c29bea0dfa9ef0bea6bbc91e30244bdaafcd9778c899992acb78b68de43bc8b66c3f4e67886586b3c788eb243c29d924f3bc7026daf703	1655809053000000	1656413853000000	1719485853000000	1814093853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
199	\\xccfd129dc5c4482029084658537822311dbe46a618e1370ef62422fa0950ae85c342b58e24d0e1b508e5d5c75567677b760d939786b97cc4a55ed592dd2d3f47	1	0	\\x000000010000000000800003dc5e7c15a7bedd2d6e55ac4ae1c88fe7401189ac710ca766fe176e14c658822df6f72a80e2230c0dc97718439ccccf1a40205adeb70319647838435787e1cbcd7d2f050e0e32634ad5f042d91c9ebe59c0e570ff720c6e3c8436dc8c53ffe13bce250cef2b240a572a4102d8fb7711db4d0710cdd296214a67c9ee7bc2c78945010001	\\xc66e067a8e17b9400351313c84d4381ca4f66a42651deef880ebc428ba6ba38f786f791a334a71c2973bbf427600112e18a2c4c0a0735af1ea46a8790e9d800f	1666085553000000	1666690353000000	1729762353000000	1824370353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
200	\\xcc95b5f540f293d78097b29988d48a0da50c0011a7154747bc3d1b4a5269b6c2ec4f987b429c589dc056f3388d7be38b88cf85c2dbda0cbcaf623125075d15ad	1	0	\\x000000010000000000800003cd65568d02c931cacbab8b3cfd5dd1c796e03569f133be5e57ea0b4fb2210812d501b3a69483892a53c3a8f35d59c291d690de851ee7b00797bac0c1dc020fd91101a3309a0544c6f620441b0e2236b239150ce1ea553564072c091573cd0e2b09c4c1bdf76adf9ba82817c76fa36a4452699995af7f1a550325d4bdae6b9f0f010001	\\x7f0dda5973b200f0ea7deb877985540fef7d31feca3518d5d388a284b43de7cf70706b57d9c584f6a10c90423c6af8c1e04d40f74db1ef72d483a5505877fd0e	1667294553000000	1667899353000000	1730971353000000	1825579353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
201	\\xd4212561706867acc2a00320ac56089ed3cfb615a708edba9ab8c26312930fc7c545e3bbe31c7dd05dbb795efbc5acbb68c81b8ac1b1c41bdc910b71b9b0eb6b	1	0	\\x000000010000000000800003b4042cc7c9cd78ec9609258f70ad56625d200fd1023c31a1ec3b7df0cd383d099c223c281c16f02488e5a9f717580dfec5c64294927b2a934c1c394a1e38dee7f9c3e192ffdd9be1c4fab9027fbff3906e2e1a1cd42637708e1a4019893bf8a6a6e7e2e853e479729c405d3a22a18afcb2c11f649bb1f021b7c9fd52101ebc4d010001	\\x00a4c36195d31af92036ff84b22f21a851394ae5e6bd04c8cf64994b061d1e4c10d5a0491f8d5c0e9302a3cb28a22df2da2dfbe996a157dabfb97fb241de1109	1660040553000000	1660645353000000	1723717353000000	1818325353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
202	\\xd5215d25e596d87e747a4db4846488b9b124e8f1daadd792d7e6177ab06d1e3f9ff65f3d1e60647337317eff2029d7d8a2aa1c72296b244267e69a0e7fb6d388	1	0	\\x000000010000000000800003d1dc233a4966fcfe527e7ba90b4b9cb595a6d4908e67e9042ea4fd0650cd65a7e11faa4aebadf76b0a604aca4b90c7e34c922b86fcb943f73beb4b5866553c801394901784a223b0b743b0666d7bc6f22bb366ce66b18af0d2b4c53c9f6f98ab921ff29d80f8c349761516d5b709009c161b2b8e57f2ce823e348aee9b5cb2f7010001	\\x9665908e83a25264fc9b26aa932711e734563dd73c8a3e8fbef007c88b33cc61fb186a1ae23c7fc63719438616bcd50e686c1df0ca3430aef1e8fe85f0f4fe0d	1678175553000000	1678780353000000	1741852353000000	1836460353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
203	\\xd5316037aae6c4d754510990b9e92b382b5c4e871ec1f4b8d0062ed5f6451e915395107d41cacebc756c030799d45fd8f1b74c292d055dfb64e4a1dfb283555a	1	0	\\x000000010000000000800003ab8fd2f307ed631d09e756c6776a0d95b05e70e3aec509ef0d8d8ac7da1d01b223be2bdbe33d48e1dd7b4cc6e165257cf4f7f1698073a11d68e23a4d8d820c6dc16103dba13a4a23436efe1b38b7298564325bfcaae8459e08860d93bb8e602fc582939a8c4b97fe8fd5cb243ba001262ba59642f08fd676888df73d9919d60b010001	\\x6e3b9c25b69656c050323ed36d5f8d30ef336d4edbebc5adc87bcacb08b399a0ad2c2a6e5531c7bbe748c47e09ca983e83cf108756cae0f073172d9d0b251e0b	1673944053000000	1674548853000000	1737620853000000	1832228853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xd925c2f1296eb408f50660bd7974be15ed572af41d15aa5b282547c2acd170328d8e67e76e8080a74528f22fa1f5c1125a56cc25278d1dbcd8a45382e0f650d5	1	0	\\x000000010000000000800003aa2add0af81fcbee4a70ac8c5dd2afe13e97e3e3564d0b3f9095ce70fca173e617d1215be9f6bb2b4edf1847ac457e17e53bc2259edd2f0eb6a4730a42c4d4762c60cb9871d3401f9dafbac3efa1c6cdc441f64e931097fc47da1854264cf3711b229eb22516847b82720bf470ddcebfa7fd73e81e0aa751b4ce1391b35f68d3010001	\\x0decb3622369dfcf9a7b4b69c6981bcf7c5cd3a4348196503385b8efd1f670f88f0e22bd59cd81eed628ab828b68b10e62dca11c2530dfc19647a4481852310b	1671526053000000	1672130853000000	1735202853000000	1829810853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\xd98d04bdc08da59b63bc78b2715ce92ef5b6749b3c4b275c2b789b9742094d465a0143fafa3868a7958f3080312075b8030f701e5c230f3fed79c30b3b9f207c	1	0	\\x000000010000000000800003cb27673e5d49f81d3c56c4c325449a2bcd37abe02d32c7336a31d7b41d27da2ef6f7263aed6d1aa8ed1d3a3be99eef300b1284c8db42c72f4ab428a5ca5a044daeadda3cc4332ee8bf3f2bee826fde96d5436e5e769b932e37fee91586adc2405f8eedc6df61bf0f9f9f1e8d315446298c159f31a2b5a2e46f7d6552670b6079010001	\\x9bf00db31d703c96823abbbcb38aa8a430a8fa675cdfe118c569769ebbf706d267b6fc16737c8ca6ee04418986559029a9c23ded8da829a7fcd73f16e0d48a02	1655809053000000	1656413853000000	1719485853000000	1814093853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
206	\\xda6d914a7448144e09120bdec29b38d294b482aa09e69686e87e4cbb6af5a1248518bd92b44ae50c6a73dd7a8cfc947fa95449a1f80e476a5378fc963a7991ff	1	0	\\x000000010000000000800003e70505689f0bad561a448eb7128c78d27621e95173dc5d3010d334652f9a72e7d06acefc82043155076813b5c113020d3f34eb7b7e32fadbf64a90a4fb380bf3617e349a2cdc9d6389d8c69bab3b3239e62fc2eceb05d004f2f8eab3f8d9f07d54dc0171187bf865c35a1fccbd8c5c5f5fdc090fadc39a778601c851a27c1845010001	\\xbca089b74b2994ecbbefaf5f5d428c633aced784e1fef889ecc76f786a1791192f0a3b0f8b064abae25db63aa7a30e0bf82b7c70621772e298ccef7830544d0c	1656413553000000	1657018353000000	1720090353000000	1814698353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
207	\\xdbd5db6a30616025b52ded383cfbcb748c2ca4848b03acfe1c8610bd8b87208a4c60f59c8a5f5fe22400444d996ca01e6938ea84b4f232e46f12c91c5684ad22	1	0	\\x000000010000000000800003fe5ab48e7d9c8192e784bab73fc2b2fcb1a125c33aba5569de97be2ec3823f5f989b6ce6e59b469dc08662d8ba5f71819d787a50514248aebcff9421934e84d15a3d94a628c11f4961668d060af6e2563bdb2667b542ab4c266bef9d715f6cefc02f26157a46f59310bab1eca5a0ac2fe0ee124a5b5eddffd854669f50203a0d010001	\\x22a7322ad0a7b30bd27de16c9e66dee2d96c709d912504bc711feb3a5179620335ed275cfd366a5bc06c9510942efa6c1570866b4b8e3bbf5f0fa653e3e73000	1647950553000000	1648555353000000	1711627353000000	1806235353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
208	\\xdc85c27421390ccbc3456d1842fbc8d1397e994f6eea75ad669d7b795c59346b3da6587bd244e9229567f115bf32abbbde4a5c9f434cbb8ef274d383fec60c6c	1	0	\\x000000010000000000800003affacc8578bfeec8b760917f108363b06bb08203b0e1443b874aba664c426e441f9d0e5224b10b6ba00feba55255d495d13c7a7e981ab2d3b21360ee04f40d0d12a0f96a1a5bb6a372af38db5bb0f76a11c5dd6c97c845820b515780b1c1483fda76b1396c84a12d2ce836a9dab59a51c4ae07275e9698a9570e0e9323be1bc7010001	\\x561e5fe53eb1534378193eb5ce7402b308f0fffafbcd256364776e78fd0ddd3bc952268f2b4c233413ce832198b26a93401df1178d6c3ea5267de32d282ae30e	1677571053000000	1678175853000000	1741247853000000	1835855853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\xdfd582a55b2593675c1d03164b9699c622a506f3d7ddf0310a22c185fb57c2b15788a8de5c1bff93c80ef9c0d6ec7da32bcf2c932db6954a51b9aaa5cf4cc245	1	0	\\x000000010000000000800003f205128dd192e11d710d0cf90e3ebe2ca4ec47adc342a6b546e9051b83cd8be571b13d92a742a4b1bbc252e9c316a1dd0d4a0cabc8c7e119b863e04bebdaf7c07dda1aee79f8a43304b6a81b3bee6fcd2af50233b07d3fd55353737b6c7382539ea80615814a37a6573a9dee3ee8291bbaf2d7e7b4202de3b4d3ddafbf743713010001	\\xbaba42d899a6db326da5627aab930a0720af1f6a4135d98441a66838d5cb4a0b0000683e78fa4fb1812d72c14cf687e0eae0d180ed321ddc8421c1d0f6184903	1658831553000000	1659436353000000	1722508353000000	1817116353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
210	\\xe22134ec9b4b723d66becfd7309824d6726750013a8d61de5f13b689d26fabc589c8a30cfa16f61422b058fa16c520e81e33ea15498be997f6ab301ebfc28209	1	0	\\x000000010000000000800003bfc6856a367de13869c2a69c09b465a58ad1d4d1308cb76be8cd3185f3def25b3e1bedd47ad1bc75bd3a3a6ff6fb66ed102d8139606939165e058154c1a623eb15df821b8b50a58e3aa18772466f93262716599fcd3f4c2d5c6a946af06af00242e86c20b7be67eff8361dae124b35636ba8ede99e4390fd47154a6313af94c3010001	\\x1a4e07afbac97e6327a846d5873039d961a3f8e4e80b0e291529cac8498026cb666ad574fa2a7e088ee28347136ff3399a925906e4b7cd1af6f5ce5c966bdf09	1669712553000000	1670317353000000	1733389353000000	1827997353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
211	\\xe21da176d61fd206120fd36ca9b6d388eec3381eefb5399330e4065e8501ead720872e49beb9d550bc94dea4051d45a17c3ad70bc62e55b2364cf979c30a2317	1	0	\\x000000010000000000800003e2c51b108c996468aaa0e7c0c13a5072a124c5cafed41ee6ea87f681fc791c23a8ceef86a006b5f7a561b07328199a1ac19e591f074cbab16b5ac85b5a6163da17a1501c31a75fc561479d266f066af7e291d87868794b9ba07e675c8e30c2e17c63f7e1416c218b33cc351e0317f54c390c54da64311edde5e25040ccda9917010001	\\x3ed8b3a7f3dad7ec44423ebf42cecd2ad76e4e8453287f778c9c49e9432bbc4f1d92570f35500b34e962ebeece1e53d1b2b3d5b422fce774f7c7ffb15880740f	1665481053000000	1666085853000000	1729157853000000	1823765853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\xe425784fa1e1fef79d187fdb58d4b23a016e3d3eaff28ffb8058ee9d60f0789600e9a82dcb5b64b2449de1e05cc2f7ff55749572ac20414402d12ddb3c51a78c	1	0	\\x000000010000000000800003dd5cfdad2d145c4c466caf0e0e5325c05ecc5f52a09dcd350c53abd4faab55e035e169dae37407d543b507b929ab6356f88ee4376df1d3e994452e0ca0eea8d758506f5728aed0e5ba511e718f164d457cc63a4a3980bfd3162537b41779123277664a9fa665d8a36ba51e2f487e7bbbe3fd8cf7c831932f720e7dcdd123da2b010001	\\x9c2d255322a7b3af5af3bc264b5fe17b9bf21ae1aac2991b6c4608cc6879ba8abde445c77150d4c456752b9e4569faca0f0bb39547f2f82a106e7ca9b518b707	1649764053000000	1650368853000000	1713440853000000	1808048853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
213	\\xe591dc04917661b5aed4685930e71273dac315ad547c250958dba803e29193d57069ff1496f5b48e1b71270fd3612f551c337e3130e5419d5d452187d68a6e83	1	0	\\x00000001000000000080000399daf1cc5271622ca13da7f8275c737c909bc3647b28bf3e07d846740b05ef608d2017d4f25395d246c5682ae8b1e8dc5a91ff954913a1767790801084463c40f1fccae81a81924d85daa08ce61462d3611c4acab996a7dfd755162d7ba320418b12ed3663e998e2c42f777514f28e994ff155e6d77a0924f919719c630c9aa3010001	\\x240d5d700a02f3fd56f0c525ce04c838c266480fc6050f7df046af75cf2210b33409ff409b35b6acf0bf945dd7a16a38b9c7eeeb41a4619427a81eaaf912b902	1667294553000000	1667899353000000	1730971353000000	1825579353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\xec55898538e43f71609f95d2fc8c42f79a6bd3569942b0758b7dc5e1a6c1a6c9218639a9922d9da0d5151c9731ac82dea5e0c32686d00952ea355265f1ec63b2	1	0	\\x000000010000000000800003dac222f721d9fb94feeee1dc34fbca970f5ca1e63bfd1d97efefc9a1980b3f0bc1289125028d84d834b43e0a898e91b9beaa9f8e816f1a9f1915cfca870515140373665d224329bd347ac9507a58445e98bc159e77f12e40d008c1d16831e688862a3dc9ec464313a57e9a31126cd59746903a4d69bc3e77942f07c8ae1d567d010001	\\x8167ccfc28b07c49118a53c0ae2c2a34b0801bfe379f4466ca0804dcd99aa90eb5b85f6d01d04fa762de7c4a0a3346ee2ce542c65fae2b12572caabdd533b50b	1672130553000000	1672735353000000	1735807353000000	1830415353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
215	\\xf551a48fa0fe1ffe6195f40c8a64b3bb905829d1088316f80db56c443db471b6ec42332f63b21b404012b21bd5acad4fef8df2f7230447f6fb658c8a9f8daaa2	1	0	\\x000000010000000000800003cbeee926bafc7a998e9445a8f65cd3026e9a3353214b91f8a3f770ec8f79d42a5818b7bb3aacd0bada97ec4788e0a11ca0f23f4ecf1e954aa1ce72dd5d3b1b0dfc409adfb8f47e7a1d80467d1d9b78948a4be446554cb0478819dd267af046330bdc02818d2944cd64e20f0221db8e7f5864c9303c10575cc2a8faad97c4a3b3010001	\\x8f4a2a3ffdb9ad3ae6cd00a8bb74f681012a95f283d0fcd57bcaf1a748f6f652a02181f2b39299aab309fda6922a351b61b2b8263d29a90db80cb75c49188104	1650368553000000	1650973353000000	1714045353000000	1808653353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
216	\\xf6e93b489f0fda2389db9aa49ae8a4de349175699715f325a3f951a09f5a1e399b41057c98738a1d1d476b2497c838e131075ea479d8302e9a72abf432baf0d8	1	0	\\x000000010000000000800003b7e19dd5f2117855cb174304dff6f55f880e8b15535a1bde8ea18706fb32031d9c8902978f305c2be7995ad1e067c94977982f8bbe1b9699818e2684e3168a688cd2b533e88af8beb4f2974ee8de5d781b10da747a8c09022872b8858782c8a144c9bd4b26724c4b87e3afcdd610c618a0c49d136385642efcf8a027ea469969010001	\\x1630cb47c1bb974886f95da5e3053d4e7f12a04a236972a627ea84cfaf33710e736e7400ca434a172aa0cec68532d62eb0b21eb70b2a98dec9f002e9e2cb7303	1653391053000000	1653995853000000	1717067853000000	1811675853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
217	\\xf705529681f9b610e4c6161226bacc014630aaad88d725c65085f169c00e2819a74ba4965b367d7fe8d30d95fb322d331577e474d72f5b52a982e2668676e34d	1	0	\\x000000010000000000800003e15c7be12c7c8f635decb9aa2b2d73e598c06971cbb6c8b404fdf13cbc8a7c170f22208cf7f29ed35ef6fe9ba8d6baeaf85fff5ce44fcc991866c2cc35e9f56ffdeee5663f2c8ce6d73fa1b51ac6488a14297b7cbb0df641487adec415825129f27b01fd5f95b96f51b1cde7b872df0f932045129766bbdf552e17aa3ad50d7f010001	\\xa7ae372a1cdb1c75c25c12a6d13d806ed367ec1c2afa0d47492f6fd3e64b4fd74952d045326f471ee707ae291c4175e23fceae8eef56d9d1c6e91d2f6f243c0c	1667899053000000	1668503853000000	1731575853000000	1826183853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\xf73113e6b03b378792b3a1b580cfa049583f68593ff3dbd6f9701a0f837bed747574668d4c08105302f33a706d9abf6441f078c6e659503395035f40809d2ae7	1	0	\\x000000010000000000800003eedad704120b358ffddcb6ab7fb6ce7f523f6af6091e913d7f64f1ebc7e8e6074d05d900401ac1e5d509e4c209f8a7ffc7dd17ee59c502d5434f9100fc52143c9f7715fbe70b034354d8da75d3248e2c437ac4af606a8ea8f02541ca881969179ba530161f9828385338da8af86bb9ef91352ee5718cb624a7df5bf5c6edf5a9010001	\\xbc831a00560b3a5d316bc8169293be6d8ca15f02c635c695c8093b773aae11e0ce696d58444c228ef9cb970c01026791efb45a5895da07cf994fe999f5f58c08	1661249553000000	1661854353000000	1724926353000000	1819534353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
219	\\xfd516541720cf03dbd81b0ff99105c9484e7a2b903756e178741fcc85f6691f43a389fe1c251127fd51a4734b4c1bc084c10353504123eaad826e9eefb4c3d39	1	0	\\x000000010000000000800003f8b3529d2866ff3c17a088190c3f38c91ca33bc4fd46ae7577e5ed0be55555c06eb7737fa6f9fbb898759ef30b78103ac8efa911a81e7475f4d6b73841149ef4055a4be0243889fcc99c65f895be7a7998f84bf07e814731386d34e06adba14c4d5ddf097d3bb8530e8a759d80773ed50aff8d4946b6b1f56684e8bb5ba10857010001	\\x55578e1b28759a8bed94b769300a1fe82a1a895b847242e26c1dcd46c4375c974978e64acdb178e7f40e2e0e2b2ce8ecebf903b6f26630f971777c183c1de30d	1663063053000000	1663667853000000	1726739853000000	1821347853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
220	\\x05068e64e7f71dd2b5a0901dcacd322121628b43b9aa57ff887f29480e30e01b2f6b73ec9d15e19a1e2a0daa4dc714c525a2fb77234378e05a9819bf4a608966	1	0	\\x000000010000000000800003ba3a933b1182f324747f0ff6d17d288af4cbabaa867b6c341819efe3514512ba71de79a6c5ab91c2d60461c38066adad249ce48f620607071c355f47263c75c07bfd649aa5482aa59b6dd324abfbb651f1d553b134d00a85a434edf640639deb8a3a3ab2664fe18d3c4f4375da792e5988ff4d38e2df49b295074bcd9c646071010001	\\xa97a11410e3ad9d6839d9bfcfbe39acb056ded1878496ec00145a44ca511039e6fadc7ba21257984af9b73797c444ccce41873ff953eff2953472cc4c292dd0d	1655204553000000	1655809353000000	1718881353000000	1813489353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
221	\\x08e260202c53775ae8a89aab0b143e697421e5d656182b38ef8cc1fe94c1cc3bb79dedf6cd84152dabb99fea250823143e92bd3096181349e2065ef08197f74e	1	0	\\x000000010000000000800003c690507621ed5521fa0ecdd9eaf3ebee9bfc01fcb8ebc5c28858af280916206d392b49fd4d09ccbe13052ddcedb721340469210be72f485fa3ac48d68aab37c7895d3277dd8e98cc3d7a36876d2150b7e5c53ce87dbcbdd8930a64a61ac0cb2048ee5a9b65d1cea9590d9925198af4295f8099efba05f3f5dcd87f071349c0ed010001	\\x23e8a3af85a576e08b5599cf5d4ed3d8908bb992d4c26039ba626df55c14f1c5a156bb7c35ac467b4098185ca3d1046d25e15b61a8d4b78ba9a203334bf71c0d	1671526053000000	1672130853000000	1735202853000000	1829810853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
222	\\x0be21a74ac02571a39da49d27a17342577af11b7653bd46fae9a7400446d9d9e5addb9554bdb99abaa328a5da76baf0e6f877a6ed71abc36103ef4d8fd92197b	1	0	\\x000000010000000000800003d731a52ccf510daa6614c7aa24a7ce0fada93e1c2f4d51255cee7be30d8793b53563db903229f0e360d7ca551c689008e801df9f351d4fb038926e4004f565e4eb7c99bd69b0aa5e4b8fb12cca0fe9b39d410ab680045e92679572ba2772540677d38252c1d0d4b26c787a6949419af5b2b86e38854b778196e1e89cb240e803010001	\\x4a25ca39acbb3de19e4e2c7a1e858971a7623d616594d806b0f20273818f874428cfbce20761ec40cb718e7357032ef5e4c3f3434f79b9f4aec6cb62fb43cf08	1666690053000000	1667294853000000	1730366853000000	1824974853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x0b8e77834a270e038374fc944544f55e9d07233fdc37181f8033c7b439315d8bc53ecaa05d575148a6123667daf870305a4dd0c245307626ae4a720bd71d37d9	1	0	\\x000000010000000000800003da0313054561fcc66477fda99dd4ec421dbc5d69c87f37b279931e0f0959fc2ea20406212c5c428cee307c9c42399962dcec5d42fbeef190830eac77f2851f195487aacc7fda5183682fa4d8adc33858fa6daf8a3a840c14cb7c611688a0a8a30ad20a09273984c0155ca7c3380287fd85671063feffb1bcd656cf59e3df62c5010001	\\x022da9b6b69965df0057983ae1972dbcb79b42d03f2d726209cc77f4d027193bfb06079521a08c34529c2de74ca877bc96dcca84e3232e19d3d8d10e45d1cd03	1673339553000000	1673944353000000	1737016353000000	1831624353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
224	\\x116ac8bf81e91c9d8cc7e95d0cdce0c09fa2cdef508994f56b58380429baa069867a671c20ee6e56425ad12d37ac636c9f644d76992ed2d945dc9b931145d8f2	1	0	\\x000000010000000000800003a8234639abe2d95fa1ee13b0518a3b5618c0bca92e8580f396a53c3344f28b6aecd2cdf1ae73382647962b20918b385897930356be9d13f374774fa1da4437971e74b49076fa366e4002916ec328e2c4ff4f87ba7254abc46f6ca48aa8f71eecb6b82cb2c39247477d84a647a3b531e91cea7851c5de3302bb09297a3876f59d010001	\\xede10d6c85662a9b46f9d269364b252bed4bdc0131bb8ee0281c3820f958d5dffdb93022037c15b694f02a55062ab68a6dc8912b43a64493ddaadc2a5d6e5603	1650973053000000	1651577853000000	1714649853000000	1809257853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
225	\\x1462c706f3b4c8e988f8b762bddf93d8aa50b757e1c401cc81ae66542a48153cd72d9cd52851df5d26ce0a4ab7dc966e8243f5dd01d5c6dc0bcf20bcd05ec44b	1	0	\\x0000000100000000008000039a9b248c70b288b9bb9587f5f71028bd8f48bce378f1317bc187e425e1d7104adc027a7e9d35fd15c3aff1fe331a9c4051df68d03cc1fbb5a72548b9097712267c7b19e94185eb9002c665a8a69192378e5bd7bf972ccd3af6b08d5051dfced5ae0a6ac69de0d6696c542b3c1c09522f0a534281f3648803675e88c21ef895bf010001	\\x50e859bd932eda83b3551bf1afec161ba8b5abef7338eb99bb3c2b4117b36608af1e8ea085fb7e6850b373bb2e07dc856595d6fed1cd5007e470e993f9b6b105	1652786553000000	1653391353000000	1716463353000000	1811071353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
226	\\x15e6b1b128c03f8f28a1169ee200ff97687ed48a3b4d67177e9d947f8d59b6513602fc5b4f2704e3eb91173da4e5c2637688232d54a5ec8d61e70bb0acaae4b6	1	0	\\x000000010000000000800003db1138bb996b20da5b56ddae9b26db70f5be4ea3a063e06bd4855f6e1645df7a90c4397e56a198598303dfcca7969616d984410eb4e2458597ae0a0c910b1126a5da92cddff1767c2c38db7453abeccd725cf5f6482daec200723b283efb83df050afbdbe09f448795a3c23c3220a29579ac34bfbf74b71acc8d4606998c1645010001	\\x540a82bc02d464d3afa74849abf274bf3b7cfbcf28f406624b0cbcfb3b66149158fa577006f229e8776e6bb6b4715bc5bc27fa4a4fc965d1d354924b37758209	1675153053000000	1675757853000000	1738829853000000	1833437853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
227	\\x15fa64414eb828a09721c5727b1bd7b8c85dc02cc6ab528f3e54d4c97df793b0cae0c306f8ec7626d8be3a4f7057629568301b7d2a7f6f7e38fecf73cd8415e4	1	0	\\x000000010000000000800003b51b813c9cc168cdb455f8cc3a55a82bf185d48ec5babdaa5724fb76374bb8d1f310fbff9e1183d5e40875a3bdc23de33c863c08f981fb2966025e6e4d5f7a14210741424941bcb047965a86392cc6e14913118bed8cc45871485cd8ef52332620cd9d8a7426879f02e6b6e755d9316b3d9021154b7a130737e7dfafbda0a825010001	\\xc3ce2e7a50c43a13d14d03a3cb9ba67bd4fb749bb314c098b554ed850049c4f188cf4d0a75609c1a0211c614eda94ccf455c59ee5af00340a57422f64f4d2c03	1672735053000000	1673339853000000	1736411853000000	1831019853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
228	\\x164af63b6257780c6eae587ee73681fbb466aab13124999ecdffd73a63cc241c866eacbe9949112443e9e351d51222289ed87b8fcacff94af0836813b1cdd871	1	0	\\x0000000100000000008000039f44dc8053d038c4eb3ab851b8686a6c55558adea53e53e3cb9f015b8f0b367588fc17f0aad3a4b187a21136bfc013b1456c46b2e5b538cbebc6921e5117ed39df037a92e4c9af22d81d39f9635f232bdbd0c5124ebaf5024ec8c305dd511f7b3fb2de94d24bb32567918adb8895db43708c49eaf3edbbd4a9f1993ad80b52f1010001	\\x1e8087018f05e114f238767c8e536c1710ffc188bb9c956922699faeaec38ff8f867695a3a9bef0072ae78717b7bd355dbafefb02475af81c883c21417edb900	1670921553000000	1671526353000000	1734598353000000	1829206353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
229	\\x190296d2f84fb1513aa6c5c0df51874e13abfa482a21dbf5b984a3f4000fce93a16c0ec48a9ac23010c02fd9b8cdac97d9bd9ff97eb88f75dc4822c97200dae8	1	0	\\x000000010000000000800003a21f0a57747acc18ff030b8379b930048387ef8dc073d8123cce48305574d4057a9b3f60e3a859271c38ca5b3077cc9cca9ce2c8c8f88449d22b8a6b946aa9b9c369a20595de012fad70f814aea769acec9556ccfa799af9f2b054a8e18910c5f227c039ae036b48816cd941a94fc568a4a8eeac40ecebe4fefcd9978c9e278b010001	\\x0c1912e79124befd1ab0ac66b7e739ae99a060104c5bd1c15f9128ba03ce70d58cdfef1cab6d2af5cc5ed34f700f0a9b07dc36067e0622048e544410c2f43105	1670921553000000	1671526353000000	1734598353000000	1829206353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
230	\\x19fe35ae88204716e1c8423f864cc1ee084e03f186c8154f1a807c12df0776fd393eb19af1cf70fdf21b8e94a789c4b17e5bcbc8f8ede01c8e78d7987d0a4ee7	1	0	\\x000000010000000000800003d96d0c7538df1804f19695805c7164825a8d0df325924975dca1c1448e0eac82b3ed0ee5166a77ac995d8985e09f835709ebb22b15e250cbbdc54b0bd1e4278145f06f63da92d95ab66e0ee4eef6977d6b5b7d40aac612d8b2b35e28244c594515acc07a77781e09b420e484f03b883ae9970131c7b23b67937e43ddea9a5759010001	\\x55b65673d9acce085eba9825c5a6a59147008c2652c2e505aec001a3f8fc2ca5a45d9e87b2d8e5bba4a2d3aa36035d3c6c1006851200e46eabcf977c800e700a	1665481053000000	1666085853000000	1729157853000000	1823765853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
231	\\x1a7221add9429a710477a3b1ab0925525f0cc0d1f92b36417fd0a0f33c46530722b2c91a9b36f7a79a822c8e9162eb9ddd6f75db44e55774301723f7bd84c731	1	0	\\x000000010000000000800003cc2c877f935f0f362b80464e73cab164b9be3a89b728f31e4da25c4d15251d8210cbf6085a44b3f8c53eca177d139c3f20c89a6e6a96fd8872e4408f85a81acba7a79f552fd0eead3d2279ebbb6edd1e86b113d9f54cf32db2698df1799a40cfc715852e08d3aa751226433b8bf35569975b90760b2ac9c025c3ba2a12694f89010001	\\x523311ec0dc41d359b5d386c53282c8feeba715cbecd176dd47d5edaa7f05fa6b9be47bfff3a7c1ac6a295141b3a4c70f81cd74d86aaf033ebbf9f94f9598108	1665481053000000	1666085853000000	1729157853000000	1823765853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
232	\\x1aaebfd820f2be991990d339246009c40a528e42ce602d9938f335a974368e41a2b3c953d0f31610802a4f19cf9832440fa8345ca2e37923e50a394be534812b	1	0	\\x000000010000000000800003d146c237d51ae41e4d55db0995273fe8b40926ea6de50a4a68716ea3ed3858266912e287f529b9f1de48adb562aa930326264791477f3bd30e67392782b4e367151d99f1de78355f986a054e5b425f6f6686bdaf689e1b57ab605e23e04de29133c41a70e546f96ca0415b4696eddddad2d520b17739412d0d64b77ee7d32497010001	\\x41de8f96fc27bf79e284ba727c933f6cf06ac1823970b3ad46bee98d9e2573044537213dbf611760d9b53a051addc7bc696404b8cb77ebf4893755a1c351a203	1676966553000000	1677571353000000	1740643353000000	1835251353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
233	\\x1dd6af24cbe785f92e94b103afda624a46574461a0bb6e49fccb543ba3a5e6d1ee6960389000d19a449010652e1b34df2be1b20ed08a1510c1e535052c9ecb87	1	0	\\x000000010000000000800003bf581aec99f15ebd0141b81920310cd6c215285e44c3b3c45e622385be5d4842d4da631c6dd643dc8bb653ce4ea4514fe7a091a220f61e21fc763d8ac7939c0856ab7e36750d2d8e6d29601e61aa617699a9b6b0d657b47cda764db08a66dd5fbd59afcd67719e91fc10318bb56f16138037da9009e89e47a21952f7fe59353f010001	\\xef29fea3f63052ba77894ce7e45bf77c942b0107141cdb3408b8fcd9537c02848325243fde3f9ce0bf206b11d522b923ede1f38fce33501d7a76ce2329df260b	1659436053000000	1660040853000000	1723112853000000	1817720853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
234	\\x20f6c1b401f434085c69e72982e75744d62238f7bab8f471ac2ffddc90d93568f502c800cfe46927b812eaa829503fd9a393198bf408bd3cc56a7edf61551d79	1	0	\\x000000010000000000800003c22816e374deaf1201a3f48ce3d1bad9f822b09b41c72caea9243d1cbabce49fdf8551cf9c48196f7a0bf7c7273d40c9474ff1fbab768d7219785ee8740a3f941dfa1a842e7b539d50141511d58c9f3255140ba2a91be80361e15a00856c361bcbd880a7b31c01bdd47abfe657bce5df12f820e130d9842cbea762a866b99987010001	\\x8e27b7f0de87058461de2aa65372bb1287dd1ed62c7a66b22206ab40b5c3029065cd13b8ceff6863df812074f3b4944a06e3f17c50282ceb0c80b8f330812205	1657018053000000	1657622853000000	1720694853000000	1815302853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x229224773404e86581538f0ee32b3ab72227828159c4ad0be448f61f8705040a6732ba5739a13c85e48174e9c0ef45191333fca58574b8d31897bed6bb60177c	1	0	\\x000000010000000000800003a8a12db5485f8a0981ac1e6b93faf371e1811ba4de004923a42070eef60b25f086e7d8533828ecdc1dfc6322231c00cf4e3e383d68f0b9a606f0a9e55f817fa6c3f87ba26eb7fa6181435c163fe745914c96ef0f55309dc78fefce485e78792febc97e3f49106dc2670d042765d4f8429e8e447a53638036fce4af5d7c5eec49010001	\\x4cc4f10a64a1275313d3a6c87735e64325465ddb78858d297527a41d2d8c7dc6c8261740ef6b863c31230892e8f41929693a7c240b0b3ec6c5309d1e9592ba0f	1653995553000000	1654600353000000	1717672353000000	1812280353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x2aa6ed11ccd3e44bbb7d43b33330f0fbc78e8728c20f1af1b973e296c81e4af76800c0ef1edefcea6c342ab81c6f8eb10a10f7b0da88067e5a0b448f990dbc82	1	0	\\x000000010000000000800003d5a87dd23e6d1beec1389c8b25c0d2750d8b666c33216133eab223e9baa4f3bcd466e52356d22e5b682a16374bc26df50c3f30ef964d0f836d7cd12c617214f15c858f22d9b7a3df1e7575fcb9b9592ed6750f014924b6186d370d1b39853974b8eb7501ba7d1453113619a4fdeb18ba47ed3f0814637e65206880baa7c104c9010001	\\x2750715fbfcc5c21a70992fb89217559931723bcdb41cc08fcaa1ac6dcade04e43ac3e944325ccdb9bc390f4aa7c4c5e34151dd461cb774ccd71f807dd124406	1663063053000000	1663667853000000	1726739853000000	1821347853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
237	\\x2cbada43e7589852cfb49fda05e0488ac3fe6f89cdeebac6bc9d82d59e415d0710c82cdca70e223f5dc3f0722d7153229bfcd4bf1c0b1e585bfbc19cf0f63269	1	0	\\x000000010000000000800003ef99a5fc05d6151079ca29ce46d2edc40778c9384f047b0148753f6811b5d3850f4b9ab4ca5ce24f98b345f76ee0c54c807643291f8578e6a20ff63d7252db8f58343aeda24f945c80dbde73a3f67b376766dbec3041b7058020927e139d52494657f215b363115b8a36a017ccf4d62a1e58ee3b001566fddbdc6b864bc662ff010001	\\x4311d53670efa704b97233e799e934bf59d3cb19b2b9a67ffe03b881a606a329eab3d950c788f834afbeee9e39fa81604e883f4ca834e7108ac73ee627fe8b0b	1678175553000000	1678780353000000	1741852353000000	1836460353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x2fc60d25d560e261d83b0034763cf03dad4a45e3ad848769425afe1f7120c3fc23256ffe073ea6ec115f08baecc238980e6627598f35cd0b487497e7b17583b9	1	0	\\x000000010000000000800003b99aeac2948500793d1fb2cce4d2299c8b60351a0ac490a22f90619d1555a5ff47533dddaabf1cd393e7f6ed9dd398d9cd295aae777aea76003671897ecfb66d3f08b6ceec8f615189b5597ba2b2f750679e294d7475d55b82f891e1f22a5b5e925540e97c13d49fde0888f121b70ea4bded3114a32e4eda8680d25fb9b56795010001	\\x90037d304a44f6eb9ab0392be41692baf6b43491c059a5961e70452eeaf0f1f2b00835ede9945a05569cde704d4d016f00fd03b255b3ab4bbbfe7f20cdc4150c	1673339553000000	1673944353000000	1737016353000000	1831624353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x307251816c6342cbfdc8695dea22008e318ec3343b7cb161fad2f6dc43efdf9482d3f5cd5f12faf0b40b29197c06a38d2ec758b9cc5f91ba2cf348788024cf19	1	0	\\x000000010000000000800003b36498c9c3ac73f46650e4fe337632aed013551673142e31c4f6cc7563f5fa017e4934abac74f289e68d4dfcdbb3132a9b27b29f25c51ce64ad6f9ddb324ee5570adacbda18df98839c38f08d345a42e4c5969ee8e0243970d3ad0cbe9bdbd47b462d46bf7134d3142c70ccd3f743a66223cf6e05bbd691de2adab7e76b5bc21010001	\\x072f3c5a7a026df18590c6ca6f68d14132ff180be945694fb238b44ee58cd9303b84cb3d37bccc45eb3bdff52081a95a1ce1f09609589f574e899796be88f502	1652786553000000	1653391353000000	1716463353000000	1811071353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x3556e0a461277e0724a369991099d077b7655fc5af2c1667cb375b18e6f1284164b0fc7cbeb888f4dd2f7e0905cc7a0ce0b1ec76fcdabe8bac8f3f133d3d5ad5	1	0	\\x000000010000000000800003bd2c2cf8eb1f2116981a12aa9f132ac20ed6f5e1fb55506e8abdea7e2c16216cf44ee8f41d6b06ad935776d5d703589c0f60848c0d4a0651e0ca39265d1eca15ce4c451fb0a034ecf193c25c54793641ef8279aae35c19f804832b832d14383a723ba011ef984047a8c0e1ca8fd928a25c9d195f6ed3ff84f27fdb33c7f676f3010001	\\xef37804f2a7c5f6994119f04429bdb6f9a67038cdb9585a12926d7f58f703b6bec512ac3bf55cf1c812f92203f525a7c667ec02cae73a5da8991b617c3829b0a	1672130553000000	1672735353000000	1735807353000000	1830415353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
241	\\x37365a38d7bdf3c8364582f7a07bdfb3b2357fa802d3e84e810d63016053408def071729df10bbe3aa1508eff37606bac79b205df44083bf96d6bcea04fdeb38	1	0	\\x000000010000000000800003d188863558bcc28aecf407d3d778facc551ad66bb7269234c5026a67dce94104fe951a9ae824775415fc7d0ddf1c7a39d6e0098c3ed5a714a783115613e4bcd1cc7dd6e23b6b2a41f725448009bd73cf5b9d3a056b1aa1d5e128ebce60f7840a99906bfa901072a7785238b6d7c8e23a9bba0adf8f054c330b744cdbc86037d5010001	\\x5dad19c56f1ea0bce921a334c6c396b331c3f2f989cb3e6f71f25726204177f1fb336b5dff900d07e812bfd12f817fa736315cfde94ad19fdf5cafd5df341e02	1668503553000000	1669108353000000	1732180353000000	1826788353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
242	\\x3a02e85bdcae7c85c938df270a85868740e84579c9bc7016371dab7222ce7b5b249ef0ac1e74affc6af612ef908fd25dbbf87f3ddccbda6a23e6c935099bfd13	1	0	\\x000000010000000000800003ef2baf958cf7b3501b912c25cd44fe1b536bd14e6689d28570c15b6f031aadf8ef8152a828c6fc4db022212b797a1c05d354f491672b06fbb4e813c74ea4b606d37164e1d9394878ae1b2ad0fc26ae75f6557604d600f96a250f976fcfb6bdae551119cbd8f2c4f82d8791f9163cb425a5eae1a269d0dbd68bcb06b25970567f010001	\\x0bb2fbcbf928ade778bbf284ae5576fd4779ba997b66983b34268ecc6d8e34a6ace0e3985551d94b09c4342a4e66e4ac2260b374c2e21a2e73c999092db8ce0d	1656413553000000	1657018353000000	1720090353000000	1814698353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
243	\\x3a56c6f66df22f257c02d28281c625b15bd5199b3f9c55fb0d358015dcd110c6afba4796810f7064eb8666d0bd70d7765630c82d94c411898602374b5449a53f	1	0	\\x000000010000000000800003c95761e2a2738efcca7a93d7228d2473746ddf6e06835ff7aff2804835b26655455f7942eece31fe1db0946ac79c0f8ed7bca023daa6195dd47c95ebdc57ab6d2b3172e16ccb1629f5d49255769c7a3ce5a9aa4573758a85ed8e1bfd9a80786f1523268917c02e4f3019c787294506061a7f16a86120a441746ec11be8ee9685010001	\\x880134f0b71a5ce92c057be8cfe70f4b90f92972fbb067556afef95947ff9dd450f6b472d83d036f0ddf3f76af4835ad439981eacb5514cb776535577b9c020f	1652182053000000	1652786853000000	1715858853000000	1810466853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
244	\\x3bba7973bee29b931f7d3dfd48d8940adbbe6be524e41ff5b477fd51c611991a04009c14cb574e35dc40af0e2573324e66e5a1e21f3aa1fc5bda493ba724bd23	1	0	\\x000000010000000000800003af65af8c8223c6e17aa3e464ee4fdbc7909901fa1cba0785a475fe0ea6d8d9186689cbe48bf3297ddcfdc27670e573cd42e66ea01113281568d3a5cf808ce52ce8764093ba72a5d581d2f8c0d1b8f6ab10fccefbd451a6037821659b3226541006711d41caf539849eed2e1ec8a695240a9f35b938b2ad94c78b1bb876d7dcad010001	\\xa7f97ccc461e3c24e27bd63fafa2ebf57dae3286a2053a1a6b893a181b64abc0c15a755982e6e6a101f970cea49bc3fef2933831b0bcbe8b6f4eb20c7d939f0a	1675153053000000	1675757853000000	1738829853000000	1833437853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
245	\\x3e2a855587918c3db352c6e8b48bf591857c9498a40211005a0a7c8096eb14589e63a1fadda20a2b6e7f6d43fb6a0b6d968a04263d127af28554f1f605205445	1	0	\\x000000010000000000800003aebb3c2955821a2174defe70958cdaedb9865271255519ab63c14efe00fefd7cf43fbc6479f33f14991a9ff0ef6b85d68c3d3ceee2ea34604a0ef2276d50a256d47d6fc8c68a76b5f213f3d12c379e136bf42c1a229516ebf8b34ee0df96ef7598a914970966cdbc7e215e8d708a79b3c45a6574c28b5ea58e7e0c11ec73bb05010001	\\x1a20571de22d1e525154449d026378225450af0e0a769bfa4e74001be8f79951155e7b254df28bfe0235c2c226ece311849875d04c48a625091e0256caacb20e	1658227053000000	1658831853000000	1721903853000000	1816511853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x3e32dc1a35a5ba1aa5db2a9e80600c39a3d41362758aec042077928bd6d889a8c5a96588092e88b499d5f6720f3c2ec2089f5691ff362bb056378d3506374961	1	0	\\x000000010000000000800003a39b9b827f0955e615b59f7cf3c8bb8ce65605a241a540b6658510c6d36dbb5344c1a24e55cde8ef1be1ea6a4248ff7e67afb214f95591336582870642f26aa4967d891a3a80865e2f815c3c91c83a6cf3959c9b4fa94be59ecdbb4a262b92f4c87801cedbddc93c31ea3947a67c5368be088334b0c7567a22cef1d49c800a53010001	\\x41629e158fdec675ef4664a0ce9b99d0cb1d7698a2a103bd6392146a32c5c8b27f497f924093ebc15f2b541d1171f3626aece3a909d37a2a1584e551ed0ab405	1653391053000000	1653995853000000	1717067853000000	1811675853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
247	\\x41a6664959be30f3a32dd3e29bd0489558d1cd2da92c799e798d2777d066f259f7b52c54cf8a928b0cf17dcbfb6897b0decda91512e5d5df74f8dffc2ff4bdb9	1	0	\\x000000010000000000800003b621d7b6adbe31767c5bcadb5837baa67b636480bd3948756e5ddaa747607d441e07d3a165afb43564fcf70097636c6c6879a9a95419b7aff37849802da3ce1715afcaeef42af0d139632c35dc6466bce45b5fa95f5e8a1432f3a197e38d1eba2cd8511508e451aa89abd50f727928de33a074904cd680972e9f23b1ef8de4c7010001	\\x0d01becb042c2d213dde0eec548f811b13298e9be0aa1f218944f209ea4f44bf513122fff617be5da4d7a444930d3eb6d0756eb3b9d20b1bee88f3f5915ddb02	1678175553000000	1678780353000000	1741852353000000	1836460353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
248	\\x42c23183e13c5a263d1eea4ffc165148e65ecfdb98a2033c381b94cc3c7e07ab0f062cf173202ab00cbab20fdf127da76e2cc9486f4eac29109055f55cb66f06	1	0	\\x000000010000000000800003d9417b385a49cf22209265a1190f5145e57e0a4bc0099ccdf00525e1e14a4cc7fedd8028f7242e67ae5419b9cc25402686c356c5e5ce380bcdf58025168bca76a13b5d932d17607bec6211fd2bf93704c47bc32b07569c0b777a5024528e662d8443ee46dcbcdab7c613948e13cd248442c4ef80b58334724d2ef9952a0b24dd010001	\\x45e66069089aa0a5dae98bb35c43a556b7489cd1fba0eb3b0ed5c235e3ed6e9d1f2c39cd244f5249e648461496f9e97e3421f3c31bdbdd3e1f5e192a4b8b070f	1670317053000000	1670921853000000	1733993853000000	1828601853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x4462cfb4431e3d27d9a555eedba3f7e8f6544bbc8b30f4681a5e6be8ac0b913e1cdad981db3f0665a134938310bb860b4e5b5df650e739725f01dd3533e6e3c2	1	0	\\x000000010000000000800003c9bca5a7b51b8ef3adcec9102fafcb2217a16e19cfc57e82ae598a4b93d3bff02a24ffc1d6875eea20a9fa26e296ce83e15318d66ab33ab418e04230dafc120a4b9360ddb35e2529046841c417b9f48a4589289f09f412305c2ae638105fd2229d7378b1639299fd258200e55071378b130b7fc9f68d455b165f10b500e1612d010001	\\xf08e40c483f7f7db8df62930a4e35be2811e3d8e9af657dd82d14ad155f05e4fa58da76e081360a4d856f1504c3546592821c0154b12cbd818e199ece8752c00	1670317053000000	1670921853000000	1733993853000000	1828601853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x472ebe046489b5effe97e6e38474ab9560f6682be9299b2fea66d9c5f6dc587efab44a1a2ef50428db7690ca74ac68bffc37d026ae45e332d611982bac321ffd	1	0	\\x000000010000000000800003b33c925f8d67a6edbdfae279452365b0af27ea74896e89db652df83b957e6fdda9a528ef6feb213374b6ac978dfdb02a6035f111114f512e519164a1ef9e9d42c94ff6f1a9f6d8db381463033175e45e3f32fb7bf52aecd89ec7e482afe525209f6bab526048ed90304cf8e456b2e29a4a5faac7f5a0f38bc0061a2b3129dae7010001	\\xb331aa4c0a0b98f574c74c1237f01c24200c56ba695b76577e8bcad85311158153f30418f8b11308d0754911115bb5a55293d5426911fbacafa9f32f04b4810a	1660040553000000	1660645353000000	1723717353000000	1818325353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x488ec87d140d6458c5a01d2dae9715d170b7a74121141042cd6ace5bf5d28a78b5405ad3256c44baa199d824409338eee61eea48dd8ba11a0b8fce319dab3a30	1	0	\\x0000000100000000008000039dc4bedf33c51bd19dcad0fe8f792f72c1ad4977110f2857bcf3cae49a850b5bb58d623a63359ed5abbdd53aa2c1a9140b83a7f23227710843c508fee632ad940a4409e71a9c5984b1d3381764ee011edd7c591c2fa8fc99fae7f05aaadff7b28e1f592868e74ab62612ba267e6179e987cbdee1d2ab8a9a7bcbbb4079b1ec75010001	\\x30bc84817b860f1985dc65df74ff47338792502cc25e637ba45d7b597ee06c2465ca0d324fcf8ede6bd85829ebc8a882b6b4b302534935fe23f81ac40445e80b	1670921553000000	1671526353000000	1734598353000000	1829206353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
252	\\x4982386ef6841d139099c8cfab52bdd6f3341866835372a2f3cbdbbe7977f4014fbcb8f64af600c2fdecf7d3b9be6ff02ca365a478b27c11570ff1511a345425	1	0	\\x000000010000000000800003d9d07e3c8855181640cd5548e9d59bca9f5c5eac52b6eb885ffec3d90f0ac7538aaab71188214a490d7c40c7f13376226e5f37ae483735caced4a6eba9e79fe8b932f6266d0b655c3660a547564488c765e5f0b34b5003af2b2d548502607fc19f65243b8aa952614ba1e45bde3c5846ae3a459836add6fbb2d31c34f0a57173010001	\\xd5a3460dbc681ccaa36c241f9bc574e28a66b9da45d2b587d83b8b56930de93dc4ae54f3d0fd1101a281b74a09f73e4c23a5e788d4c42b76778b2d5374ee9006	1667294553000000	1667899353000000	1730971353000000	1825579353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
253	\\x49facb4a7b8ab8d57950cb1cdc2731447c137624f7ef68f9b2482a1fd936549db56067728db751da0e2a6d11817c5579c5c674503bf0036a39ce7c428855448f	1	0	\\x000000010000000000800003ae555274e307c13a578962758446dfbeece20ab48ae68037ff50c38b552d62a2e9f5d995504556bd1946eea3b01cdb85993a985a266d8ca918c616e12b7d14048c89ba45b8a0e61df63e7def86816c3461e5f30999b15adb7524a75701508ab4edfd4f9be8b9606c0500bb6e824a590d7c66023d227a5df184d71efb6e1484cb010001	\\x4838000b16d2fb4069185f398aebb495a88cd0c74f377886632b088978e724239f589cd66579c7189b0b01d963a36126704282e7c85ac589c92abe8d6236c607	1675757553000000	1676362353000000	1739434353000000	1834042353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
254	\\x4afe20fa579f0faa070b879b857fad24c8d29d7ff9bb969172e5821de4755dee1220034217851dc4674887ded6d2113fd42cbdeae60c40671ac972173c08f984	1	0	\\x000000010000000000800003ba5a375725de0cedd2532ccd97c5d2518a1fa5fca64594abef6861fcd4840d0a029026756a6d8c16448e2596d2813639be6307b88f3f9150de5b19d815faf9b5a1a3a6519d01feaacbc774af68ba7f8e473ea8e91e2f8267e1833921e61a1b2d2f3e2108599dd6dfe9dcd1845bc89d3a536ea03bddb882dab0a82c0dd0e59b2f010001	\\x574fc9e6590e7d8d9eca812c07fd0470fecd169ce342780598640f81a11e36b9d0b74019065bb22d5284621e0c5ba13d6fb43a152e37c1c1b2ee5fd36ed5aa00	1663667553000000	1664272353000000	1727344353000000	1821952353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
255	\\x4aa667a46afaa0d781867e35bc0e79e8c313655b78a8642d3b11bade38d541219604f00fa4389fb4824f8cdb55bd461aba8a29fa005798341f2397cb39bf578b	1	0	\\x000000010000000000800003ca82afbebbd2b87b12e96bd6112eebdaacdb5d53a9e5f0f34ec37fad8ff0fbd42349e054ea61a13f952cdd01b937b40ab3ebdc02d7c635e52c51ed48fb5b2e89888dc374cf632efaef968c50bfb411f9719b7398ccf9323a67e351f3b4dc2885166ae48f6487b2ca7394b533dfd2ba99709551b528a78c4cf96d138976b638a9010001	\\x1a864c3d0e8bc8847e5a71c7a2ecd537cae5330c36f8a90b2029547c324365183907e97c6b31fecb23d228e7bfde903198e49118d3c38f6327f3c84e6cb9740e	1657622553000000	1658227353000000	1721299353000000	1815907353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
256	\\x4b8a6f794c1a509ae35c0bbaf2fb8aad92e8644e40022017c807045525f17789ceab2583d3881c05d363ee8e8e4599f3036cfdf8609ae979dceb933de6ab1f32	1	0	\\x000000010000000000800003a9f4350b0a9b9ef04b1a433201c4c79cecd5367c32e34c65d3b0ef0572e8e16097d66261d11515b1cc5f018e97cb9efe76b0355b761438e155092a1e1e2ef2560da9ab8f578b0154436ff7fbbdfb0ee9738e486e1085093c1456d33a77665898efdc64b41b802f8f38fac4cfe1bbb4c04656cd401bdbf148bb6396b9651154c1010001	\\xed99086260c0d9e197186c3201d8e6d3ad649c579e892c0a7db3811d098b0a98e9fa23dd9e7335ff0a52a6e0bec425ed66b675ec4045f4eaa28f0dca12bf4301	1651577553000000	1652182353000000	1715254353000000	1809862353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
257	\\x4cf25325afb32cbec1803a78c0c282aa88bf777bbd61d425337b41b13167ae698bc82282e42d2fc64d4f6cd6ee83809ff945a1f5d6c7e525d242d739bc90a287	1	0	\\x000000010000000000800003b63efbef6ea547efad088a1e6ddd28579271bf56f4060a34db0331b1668567265e73d94949b88bfbaeae1352a56971f048354eea6f68b3e87df565596ed037df15032574c0ccf8a2689ed8374d2f4a30349f0123d554f93ae7777362e30ccec72ba941d8fc87182a884f753bcdc2e399ce659bd9a328309bcd6486e516466625010001	\\xf120819a6222fca07195c9d412bb0d621e0a7c3a88145b83e90260927421fef94f64e6eee7fd4ef7e265d1623183a00c517d3c7854c53f56955bf342617d2903	1647346053000000	1647950853000000	1711022853000000	1805630853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
258	\\x50b27ee83bdacae828a1a1f64484aabff9eb1d4f2211056db832e377ba01829be560f5eaa5ca7bae3717bbcf8a4da8ed2b85f271a2b80c1dc3b03665d3ac5eb3	1	0	\\x000000010000000000800003c31c6801eeae504d747cfcbb9977432404131081ffc4c69802a0aa3d9b600384ed7f646eae8bcc3fbd896050195099bb392c39caf02d7f7234c69e6454cee8692d05435972e9391daa5ce590fcda008e62a0ab8707a9ab340cc65f67f95634294f0171abb405de510d667e8c045a8e960ef7e87070369dcbea1d6e340e060687010001	\\x10efa3e13ab702e1ee54b2ca686f8b43ef36c4eaf549d16d67217cdab57de31ed45dab9172f16c7986f953e6ccb01d741ee6253b3d47d34dd1e9c19a67b26704	1666085553000000	1666690353000000	1729762353000000	1824370353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
259	\\x519a693cceb1114b74eb25d1d697a23ca52572f98436caaa75e2ab2c5e885967f1e048efc8d7db30d7b3a3fc598edc4e1dbbddce36a5126c8be408fc6b1fef85	1	0	\\x000000010000000000800003c051816f3e7c68d36968e2408bf7c0347080459dca1c55aa7de37c5949ac768b64bbe6c1cd03cdab17229109c4b707746e33add56d346d521c4a8d53a054aceef8234733bd466b329556ef939606a2c8794d27fc984f4923a11d42ed336cbb5cbb8dff51a754cef32145c4d4027dfd5b6ef3b237eaaa38e51d9987e70a6111d7010001	\\xf29cee9ac008ac1749f564bdf7d04f1f63bf53f5a1ea0dc454c6ae201a685a9cde438bc02c3d32e8b1d6c23f96ef7f2e69e3fa4d69ca49e3754b91087de0f402	1647346053000000	1647950853000000	1711022853000000	1805630853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x524ec56a66699397e95ec542155512973fbaf6f561262984fbcdcee3db1cb397f10d2422b4d37a9014f0a260adacf58bccdc22ce8083a0b6c91cbe15dd09d76b	1	0	\\x000000010000000000800003b1b2f4e8f9f5e7feb507a1c1df5006c3b47f644f879f98f785f9d15a914dd735e5b1998e42507d2744da06a927479a9a37f835d558e03337bc66318fe0f59d15fb35c1fde436caef025a210063cfa3e4216319b7a4e39e70a4a77c42dac38c562a5729cbc2b679ff8843b8a612dcde7fdeb22a4aae87c802db857f07032194d5010001	\\xf7f742136f015464a4f735bd80d122626c0429c9667e315449c9f241e7b1d5f8d2c06548a317afe9f997fdd2c00c42ebb070038fa30405aa64f447288e2cf70d	1675757553000000	1676362353000000	1739434353000000	1834042353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
261	\\x521a01fda6c5ed2d752fd592aa3cf04ccd72f799008b2bb48817e942379bf027d866f794556a1070c43815b424a76f6091e712a4819c64396e8f4acdf9aab29c	1	0	\\x000000010000000000800003b25d6d8ebc900eee49b3b91fc4c49a90458a36666c3cc76063bf0081dca165e44efe27501582ec63b73950fdc706da8a25d3d1fda48e9709aa9f9f44c8337df39fce3fdc0bae4afce4bdda2a9af700380aa1422fc71bba7e6bb1eaf3f4741e1a980cd7a6707ab6748cf5785eb77ba7e106682d3ffd1ba67c6c4dda610648ed15010001	\\xd604338b527450a5d9e6e2d907f6a9c2163be8d11cac297999a2819ba12d8a52615db7051523bdfb10a85cba753f40b11c8bd4cb15062c7ec4fcddaf32d37600	1671526053000000	1672130853000000	1735202853000000	1829810853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
262	\\x538ef3193bc538b0e733d19fc6578a73879fa2a0ef5a612f67ba5c72e3b22bd59bf0c0624f0e36072424622d7222294cf42f9a788e845e542626b12dc606f0fe	1	0	\\x000000010000000000800003c8b3beea593b208152550fe003fb7ea29a0856d3c75f5b5c3e1bab882b8bfe95d26132eacb43d2d5ae40966310b3f758e3e10fa42946f6a8ad82d8ea33cc2f0904a54c285f92d16a64c991a1c659e8f7634feb7a275dda3ca3aeb8dccdca3b44ee72906716f705f317b0bbaa26dcfe8ff45f1f74949d95596bce95e1a35ae199010001	\\x0d53abc3c4b8d40d8c75fef1539f1c96dc751941fe407594e3e6057ae7175ff13fbce7f2c378934e5ab1db865d49cb874b99e4a623e2a18822c5712cc75e3602	1672735053000000	1673339853000000	1736411853000000	1831019853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x539aa26c4af427a702f0926dd02520747fda54e7d7b315920492f46ddb96e637c379ec1abc199c7cb18c901d70132c1b7ebd46589a34a4ee0ae9200fd6350a28	1	0	\\x0000000100000000008000039bea48cf2a0438b951dc5a84e73acbdbaa37fc726ae0488fbcf4ecb82bdc60dabd76333d3438ebc8e3a630f19c4c3083a413c6be1739fe5ba225c95ae9291c3cee7f2a17ff51457ba588c592dbfd8951c5a62995f4ba3a1105889526f7661c4b5221c622a0ff9ad658bf9acf7f4a95fa79837c80ab4ad3f83535c25b56e42d97010001	\\x5250411c6233de700614afadeaaafdfb81154d88e5c065cdecf74bd1c372e0051f08366405ee3f1cc3916baa4742dd26c24930003f7b1beddea5954591d15e00	1676966553000000	1677571353000000	1740643353000000	1835251353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
264	\\x53ea79d3a0c5dc85950ad12566a4a01df16d0202e2426f1a82240771f85f3c1c3abff802497f758c4b5aee880750777cb260402f59e6a9e74bfe43748674459f	1	0	\\x000000010000000000800003a99946848544509ceae265d795d5904fa3c5762f4b7ba4d5daf793707229ea5f733e9b28ee55823fd01bdc62c9ecbc5c9288991c88864cdf7b65648a135f2b4476cb6bcab6bdcf996c1e928de3bef4fcb08a57a80fb59dcb80f74fe2565cd0923c91bf332629bcf4445e2ab7c3f5ca297ce1219a34bcad61de571aa8f6bc0c21010001	\\x0b72b45ed439adee01230f343dc7050544cf8f79ed2043f68da0ba30bc263f8992e0efe273dfa80813c7ef3f18951a6217786fd307080ef91094c8e740612d06	1650368553000000	1650973353000000	1714045353000000	1808653353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
265	\\x5632bcaf0cecaafb2b4c95f3540fd866cf63ec3db362d4eca1692e1f528bca07519617fe6bf232dd8e2eb87098cca4d0c1c5b5bf154f91ed4230730fa2e89d65	1	0	\\x000000010000000000800003c43ad4d2447074f9e5bb0fd1b96e4e74cff37b1ed829d7d337ceb959e394426112583cd051f8620ada97719bd9f800c28a46cfec7bb0860b0d4440c004d4fc167d5906c34f0e84d7471b42fb97e6d7984ba575a909958f2f38291259e5f1039e08bce8564ca23bce24b624fef1284592daa5963078f21d609e90d412d1c401af010001	\\xd75aaabc8b1faa4e4389103e5c8fb58cc3813d66532c00b67bc5dae3c246d1ea3fc14da584d7ca806e9b8c7ff04525f660974f93dc5600ab9926448db3f4b60e	1660645053000000	1661249853000000	1724321853000000	1818929853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
266	\\x561a030f88e04b7283d4e673a75e7ed23c3290c0e997bcf25236b00f9cc02bf1cf29e4925486a9b46fe6dc0c62f2addfe32586c2a50563f7ef0602aeb5618723	1	0	\\x000000010000000000800003d36a2f749f1065e4c4fd495e14a2bae60a8078696d70294b3d9747d15c392575fe99f33983c4d369948b492f2282f660eb20766b56d20945384c1a835af201e38459d4968bb677fd1fd4677059c001e7e38d4309c26bc27145c5ab29dc9e1f652c0bba7a31c5d51f36ce211f980dca2e7b7f7fa8013a33df817ffc0c01049ef7010001	\\xc90dc380e07e35706cd69eff65d732a1122bf1e05d8ffca24fc9b4ffb73a5a700b04b6ddf62783617d5811d9c066ed6a7bcf4d75cb04e11d9addb6916003150a	1657018053000000	1657622853000000	1720694853000000	1815302853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
267	\\x56faf77c034f8aaa9934500a6805aabc7dc16235ef471114bf2ff41ca86859dcf6a2b99988b53f894f7c8acff5647b39c2ffcd35e12dcf632aabb8fa7ff2aced	1	0	\\x000000010000000000800003af5ad4b4ec37b883a31e259659ec26a09b19e411e30b9ad6be9387131c69731a936ced888940fac482f3765c117b1047c6f06514449a2bc7da605925b594d8295d91ab54b01320186d5a53e7a0c02c88c8a61ed5c311f2cfcc5335e74a64a9357aa2cd6f42ff238b38fc7b4301abfc72d5fb8fae943ad618a090673cbc5c3ca9010001	\\xbfc395aa02ff2f73ab78164f61d6af2970d252b4efb71fb10eb86ca048d3b118ba7efbee831c469048da89477b11bff3a647566b899661ec9c837d7fc6682b00	1647346053000000	1647950853000000	1711022853000000	1805630853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
268	\\x5c7e83e4977156fe7c240a1e559176cb8e491dabfa409264a86c33f75dd2ae6f226023803e02e4a5ca158873cd513a27e8d8b596d6f39e485b028fa1c03f1a72	1	0	\\x000000010000000000800003b27b0c2ad74644a9f48fbba815ee8165aa7e5a9f42198fb8364a13b110e8c57758d967fb15249d387274916f0a1f29b5286c5088c529b5aa2f29575233477115bd8bfceff29289646c8c903a3fbbd33dcb2b7151e427e904a4f2a17a41a1faa983b0c91073a34f4dd4c1285d990a6866c823416eae0bab2ab99fd0b7bb2a333b010001	\\xb58c4296088092e4fe1d7d2f30cb34c718abe82d6e71793c9f5e406c4cc0e72b46e352f1a8b934da2d86f06b17421dc4b22477affd06685f9de589f7e7ff0205	1647346053000000	1647950853000000	1711022853000000	1805630853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\x5f86b583d9d67f669c429d983f4653e5187512d29fc34ed9208f49fd50f9d5af99e7ce0f6ce8a7c78062f213894b2398943da9f96b182ad1d8742d7635f76167	1	0	\\x000000010000000000800003e52cb9ebfc95d9d2368806b285470346ae7a76ef4d51296aa651337f57928617eacd03d74db26389ee0e78805b1ba7b97d77c5fcd161fc027cc46b3d174077eddee7e9cf990ae0c08d0b0980a644498d939915fd2c81c4f6e16a2859b0f6952d60f91bd76d4dd17eaa79951707863c5fc3c2bdce336cca7908dd9a59e967f103010001	\\xb1bacef35e67694f8af33971a8c9922917d16180c001899ea0983b82263d2568b2082f356990979dea678d5609c5421194355530d0144445305b6924585df208	1653995553000000	1654600353000000	1717672353000000	1812280353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
270	\\x5f1e09bd28cdca21c649644cd2bb1f53a99226b0115f5f47304e4acc1aa5cceb2b97bbfe94fa40eccb81b90bfd85b2b34c4f760584fca873e6f1e1724f2dd327	1	0	\\x000000010000000000800003b92561621c4d22dda453317ed8c94c91a4eaed103242da71e16c6578bd0768f9bd6070081702dc2455b562b51f10c314492113a16efaa33c47d945d318ae55c91f55818d245ad5f66f947a93c670d84cb28e01048d5ce9416426409f936139378eb11d767d1f3a0c9aa9d5256a3a224caefbe3f73d20d93f43b1002c7dcdf185010001	\\xdcbe2889bac7cfd737273b2d86f5d7bf61d3a2953f66f0b20a8556627c3e75eeb6aed0a3ee5298a04f26bec7c63f6b9e2caa732c6c48a1263c0f62e9a3f83907	1657018053000000	1657622853000000	1720694853000000	1815302853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
271	\\x642e581755233479c985a7cca8ea9184e0f2ae24e4fad59471f254033125f39bc1ecd54f3df8e3d5759fd3f951416ff17c3c383752c6a7d22f7ced29a2387264	1	0	\\x000000010000000000800003c940ef110ba797684233648b932aa299a507b76ed11e117624e219153b96c8e84e2e9f764de423c863e0f87c4096fe00bf6030962a1bbea8a98fe3e84233e48c582d3612b845e4411c48bcd4f08d37053ec09d8212a2fc4350ec41e5c4482a242ea2d28894dd93bfd47eb4f34276f7eeaa33714468dee9678f60b31a79ed949f010001	\\x58398b0c01541d72fc7e9faf54fda09d279376ae152aa8c2496f9e5614ee8f445a72329af73e9e05a7e5d4fbcf731bb80c02f60fe9bd2f545614dca27de5cc0c	1678175553000000	1678780353000000	1741852353000000	1836460353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
272	\\x6dea2d80e82ff61669ac7e397e2360c50d927ff3ef2805f90caa0962606011791c9b7d719ec693e028e3933a140a4a174c9bc96abba669f69937b2776944a7af	1	0	\\x000000010000000000800003a35a9d2a4d92ee0bb36170cc5a40919fa1fae07ffc5d02ee0770663c677599eb822afdb99887873611648bbcca1e212976ba0f569dfbb69eeaf68887a1a38ff205c6ecdae77ddb255104d5d8a1f19f6e479208a826e82baef639c79f2f4882b0f3ad126cf5dc1e508c7461ff4679cc2fe3258e9f7d66d1e95af0837b6e0d82f1010001	\\xb29b2ec147a633e50d9b20eb83ba0990a5de17240cd4f539ca795ccaf507afb81ced4ba5c63787413a96fda268efa5ca41a9e75945ba46862e2cb0810fcfcb0e	1652786553000000	1653391353000000	1716463353000000	1811071353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
273	\\x70b6fe6cceac3e977f8a68044a91cd83241bb48c4e9e32a9b4928e3174c7d05dbfc073e9a3275c5495474cd3414cfe5da1bf764cf9e2f8fb78f9154f1900288f	1	0	\\x000000010000000000800003bec0460b1acaf9aa03a08b95230706beeb098a4fec6c0e0b0c63bd94afdd5d51c661650665c587d06f3868f3527e6bc84880327bada99eb933f23a770995d6b319dfced7b845d405d1b06dff8e138ee184dadaf6a3cd7dfe7359cd80f99ff2300612c672890036d99d8abd9223a3988e5df0442168b843226af1296f8bcedb39010001	\\xf3c062462635f2019cf9851f6ead77fc5ad637ff71b658c5fedecbb2b81465bea453ca0567ee80f33dcc4a42324d857ec98745e115de878b732503728d0f1c06	1660645053000000	1661249853000000	1724321853000000	1818929853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
274	\\x71a65415233702797fb742c6760d713e0e1eb0cc2dd597c875fbec2ceaa71b54970131ab5d45ad07169fff198aba0b18b314a903fa68cb1636160298488938f1	1	0	\\x000000010000000000800003f1f69f78a00bca0e6e4fbd490bda49c3d30b1c0c03b37ba630410105304bbb1e51898a13def868783d70b20ede57e906c764c361a13f024177026367583a8c66d811dd17af6d57f2a9721cbb14edc6d20e37cd859a7c19dd5c0ec27932c7a78c6aa1e369fa0d31f8072998636723e1bda4d3d404dcafe26574b7aa0b6e4568ed010001	\\x34f51ed815ee0d1413b97f7f3d538d76f9660f40d9d5b77618cab62a7ad89f8080e0872420960ec0143c966bb0efb9764f74a7187e5cc965fb4a9afd1a8d6707	1649764053000000	1650368853000000	1713440853000000	1808048853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
275	\\x7272f0315bc47f0db1ebf86fff0b6eaf42aae9be426214558a3eabfc6d28af61e0830f957a644abeaa03cd6be2a2b1015bee88437cefb89e887665a3bf1e1938	1	0	\\x0000000100000000008000039a2ffd9df7a87540f8706dc739b89bb021b302653e20fd98f5425286d43ea5082404efe6e0d501f2e14153c0470814ee8a1fb2e23ab11950466235b696a267379b6e46cac6a8f98837897fd110916aeef23fa693af195d3a1dbb31f02d5bf711f204f558ef860549396c266dfaafd3d70e73728b593d55912ab4fad89ed4b5a3010001	\\x74102840f5c162167701f26a3d8d2288d658d84222416ceba136516333a7e2f173e50c7ca1f4998e849310fa436432c5a533378dd47885f19cbb44b20c30f90a	1669712553000000	1670317353000000	1733389353000000	1827997353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x7402a08664e3377693c60698af92e415b91f6ebbd01e2de6f6c312378d8302bb7bf79c4707405716ad34409386c181f9012e375f9b079eec73457c01f127b168	1	0	\\x000000010000000000800003d16aa46aa1c6ab4b90d4d7d26f8630e37370defcc4415fc6134fce6114af3fa51391f9b68a4ed9895831f2db901e871c15d21acc5eb9d2f6aae29eb3c7f62afccac1ea0b3df1eda6941177892583bcbb09ecf0065bc2434d8417d58c49df3cc17338223dcd33ceea672be128b2e812025cf2a02c7d613b60858622676984ee51010001	\\x26bf95514a0b12299ef9f9c9948eb768aaea5bac66f422395a300f2cf4cd35da10e1200b60a81e76790a4a664067efa749b01a68166502621909e6841be86203	1649764053000000	1650368853000000	1713440853000000	1808048853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
277	\\x75baaa70179fc70df7a8082f85900b51484562ad41c09de20fab4ee2e9440fd16f192672f2e563e15048b3a03ab2e540b9e41edab7b96618421ba08a56a51ff6	1	0	\\x000000010000000000800003b5cc6351f424eb4c9a615ad2b3d9bc5d6473b28fedd460b0191bf7269f7de3065b8b4bd51901a2a63874100fe337b8470f106953f9ab9a0038bd5ed116cdb5eeb7be5b015066ffdd394868f7cd05febb14083a987ae341655beb7f9083883ff668047a35b5aa86fb4c7178a58be7059d1a5b1d83159027a896febce0d9f535f3010001	\\x607628d733bd35e82d086e7815cdecfcd7314259cf7f9a932c58da3f4347497e48af06eb4cc916f0ab4a594d4850b3dd980e18bd409f686225bb97290dd55402	1671526053000000	1672130853000000	1735202853000000	1829810853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
278	\\x779e1608d2a015c9b5c283259e50b9e699379e05033bca1543ca622284c5e0af97e50b216a920cddb9454bd498da31f7fbe09766e8528f3ff03f737ecf89761b	1	0	\\x000000010000000000800003d83536ac19af27afd8354546dfd72167117e9ce459f1d4176501bbe74f5aed4d254d879ae4f498db4822575aa402f457088d0dd76bf2e3fbe48d9072b45368d557bdc578b440a1b72f290238ec7733dcd0dba12f276bad4ce48115ea089fbc3319ec4c3b5c4eb05dec6625e1a100345b08e9b11daa9bd4208ef2519f1515a6fb010001	\\x8df12658518f06a1fe45683fb9c51e555391f8cf4b54194023b16893f59dba0c784b2bb33ac2f18eeb5dac3dceba4721cd58e49f22c28d4e0bf23db1ba3b0300	1656413553000000	1657018353000000	1720090353000000	1814698353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
279	\\x778ef45d8c3b774005ce241ffe213f691998c7a39aaf5386794a119a70f5e0980813316a5a084015816c929736be5d8398d5f3de213cf0b2633d3c95a56f30c9	1	0	\\x000000010000000000800003e278f6b495afa8edb16a18f22c1daed49a0d667469c74c26405fca33335333789da3c352e44cb6a8ca0b57fae7e9c56e698f28f7a1b71f280a4bc029b4105c612502b1b7039ec639baf5b5d3e5b24491ae920370f60c146063f987238fcdea2a4207fa537ccdfd3bb7c996acf5d60d7d7a3e116d1da59b6f08c3954c19929241010001	\\x24b1650c8f334bef674a41ae73896c088cfeb87d02e3eab0d7dcf1f24250981ad03f442dd444c408c25b49716034ea3418c7dc368a83d407770acdced7955b04	1650973053000000	1651577853000000	1714649853000000	1809257853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\x7886e94849e4e9b4a99a4745dc3af79663551800b3ed6043ccd439a4b6cf0cb50e57217d2b055782236f54a3684894851a04e3741083324cbebe53c1eb83d1c6	1	0	\\x000000010000000000800003db84ca46a4c1eea823e91d6cf7c708359635a3abcd845d9e2b7da6401beabe3de0d4275d2070f9ad456e46bc462d4457cedb010c6f2538e6c92876b1e3a5c12bd05d0cba545c9a424031a7ba832c5ea6442ef0b5dfec54b2f7f879d3d4fb075cb3f436afd718b7249e32f60f64d3070b81566d2d5585e58e5475f6fad0a3a9d7010001	\\x7cb4883b02a8b167a2bde09c5fb3752fa03247a9b25f78df0de1db8cc19d9fafeb9e9756bf9a658818705dc1e22ee9c9edbc60802bb79ab8176bcb2aaf783904	1670921553000000	1671526353000000	1734598353000000	1829206353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
281	\\x7a26f4573d75f6240bfd291fae1591b4a4001eb2c458f730fc0298257bb7f1b5e2c350371817f0be7d87ac52b77be574e9cec4befeb145eb77b531b41d3621b4	1	0	\\x000000010000000000800003ebb4c1c72afbaf3cd5296330e901057daab7ac027856e760652abc8db13d9fdc7bcea7507939f81ef2e140e1d9c864484dd2d5c0e091cdb73aa918760c518aae22951f7d7ffa4d6bb91d68bb7b5e91e65a4587381da2de35f88dd00f5d21f56d232442a6cfd493abf562c1c07482fc9c6d8d61dd6c5be3f9a7e6c5acf80d94ff010001	\\x25a3e722124ad60eb0a5c95e0fa63447a6b1bf4cf4f145805a1e85d4adee133d778342b0f2f4563eae0ae31af6366f40efa08ad31852978f0f52b69ade0cab01	1651577553000000	1652182353000000	1715254353000000	1809862353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
282	\\x832e0a76e58adcef147af1171e048985d49741d675346f9ce6ac0da5efaa7c3d42e025e3e067764777c384c189df0ae5de28efe4e42e5e4f642e0ee4ddf62157	1	0	\\x000000010000000000800003c2985b7dd3eff5b67b4902b5e1e01f62153c41c9f8f33639d5738bb45fedc87943b2c1180fbc9c9620bb275bf49fb3753675c7452d29a5d543f100749703854e5fad24b3341dfb18f448190e0c7bea294c3dcd8c75f39e6b5dc7f3ba8ef21f6ed1b21659a83ec3c4c30115821092d968f1843d82b332e95e2404f7ff493a120b010001	\\x5c3a5baa1358bb97a0fb7a519eadac5cbd17b2ac735eb572e8001e5b8fe73ddbc9b318e1c8ac6015750a1363d021234880140537e8e9ed14f2c3ff7e8fc42607	1667294553000000	1667899353000000	1730971353000000	1825579353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\x8542f72c8422c0e9e85480110535ad17e6d17c8cd8143dce4b2530e1b3a6b7dc17fb0adc7f1aa52f84327a8785305442865689f9c98995d6c0adb6adaeed281c	1	0	\\x000000010000000000800003c05a51546f0e4754194718c08a1f0455c75aaa351788a54eb7843c1410e524168ffc341529fd9f37fb4b88ad81bd91aba8824d43f8215dc7e10dfb9ffda9a4f6c4ea132a333b34e007e4129bcaf2efe0a7cad154151be3c0a512887514e686c101b00b3edabaff5b78feb9e68efbb7a1f1a81e1fbcdea1ec7067bf752b5e7423010001	\\x1419def8bda10382b447c6d7fcb0f07ccc591d4b3146dbb6bc2bd92a40280c184d16ae4f9ef50cd1155558edb8113c48bea6c00a31d0e335eee78672d313ae0f	1664272053000000	1664876853000000	1727948853000000	1822556853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
284	\\x86a68b081d2aa8cce88ea50887a829726325036056707733d7feb5dd6e24add686b8bc384a37c5c4835e4c434bfdf3aab11b7f86b7df57c68a11f80d52de5fb2	1	0	\\x000000010000000000800003dfedd1db40d17d109a89e45a9c24f824ece52f2c3ed79b3a500183c4a4673dd9b2c6cbc2d0368ee34a36e0bc2f6990c97da0b31401f4c6edfb4f7baed998d618124b5617f1181cf42b26a77955e728eb1a034fcc5ffcc440b62c3f77444fbf056b11f07382449d2eba77e92a46f7ce594e749f3a6debf99d462a06bc7334e005010001	\\xdab45e8f236653dd9c268f7093b2c7818329745d2a5af7d0dd9243eea61d6ab20e287f7d0b22a168bb623861a2c46e7ce67b9194fba2d5c2d5e0ccde6c281f06	1649159553000000	1649764353000000	1712836353000000	1807444353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\x88965ada61038c4cb3b348e9ede1fb9f63682af3217c0fe98b0cfef143ec0b55cb2aecd70f653a6390feacc5c37f8e3621e35659e2c6d1764468688fcce6c26e	1	0	\\x000000010000000000800003efc382d663955200af2c531561de3efca11fe978c7a2971b0443b2cf9447d7115f87ad51148db0f34d0fb54c5386e9b9b2670d372ddf25ec0c2f5fb4648337a1c6877849cbc1d4a9f03ca45678068191974ca2580d55a8e47fa6806ba017e067cae577a08928339d247514ccc6074b05987502a8fff384a4c2559e937b23e705010001	\\x3294ac1765086c36f064e7aaaa22e8c2ff6dd073318d117f9c5ae490adb7216706fa126b0defd685224490a310569a67c7e7c36baf6d00d33b6c3247cbf7220c	1657018053000000	1657622853000000	1720694853000000	1815302853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\x8b96765940cdc90412e35f406977a766c4208bda63d3238aeb91e73ca46094e6cc77f007dfe7800f10b490f09596ab6a611196014217d43a5cbca995dd7457a1	1	0	\\x000000010000000000800003ac7d75a8c5ba8b3517327ef36ff075c763f399dfe3727b32601ddc84762c996fee3eaf5de817ce03e02845ba73c4e2412e17cb0e899b1e2c26ede2767e1f83d228407f1235be5883286180c39c080619c8868f56bc7de46b855c353bbfdbca90aa52712db74d0762bbf11f2007454096882f097ceb1f5953f33c1e6ba72ab85d010001	\\x1e6ac8e11ebe855ede9577cd9daa9991106e305b871e3e02b030b83ea2461b4dc8a0bf0fb118271d86b4944c0feb0dc5a05edf8eb001612c4d81c355e284b301	1657622553000000	1658227353000000	1721299353000000	1815907353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
287	\\x929ac096895abec5e72b73d4bb092243a36df0fb277ee9053513f99f6c9f25c6ced4e4c2d4ed2bd28734b8886147b7b6e758b547bfac840f8a3d03a9494b1ab6	1	0	\\x000000010000000000800003bb35bc5c5a7b1258cd77d9f1fc481980a3c9f002c21b5462a334b362f1cba6c8e1ab732523ba906b34431f225c93ad950a50f9cf7bd531efed61f14e1f558dadae593132ec2793608c6b66b79232e6b404f0695c408af49401746edfb91f1099b05fe0a31fe1773dbf90d1cd11df7c4188a459f8210300d1888b43c138f53571010001	\\x010517ac6ba68562514b49f029fa7093555e281b0df4d52a82db799f8d92062fd3fa6cac157173090279b32106ec9a4194dd897648004a3694959a19fee9ad0e	1676362053000000	1676966853000000	1740038853000000	1834646853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
288	\\x9a3e7984135e9d346e7f667aa23403063b34040a25f6cd38ef6bf76587e34fa4eeede0c4005cb498ed433ef4593e4c9fe9aec5e88f6f176eb3e7a5098160af3d	1	0	\\x000000010000000000800003cc77c7d7cecdd90bee4f71476e3be9e4f7a124230b59b36e1a50c264a83e6063d6e8db46f939f6c72c537c842b55af4b54f0a473a64093385a9836d5d71a8d2243d60bd9e3e715f724687571b5ce85feea32addbaf52111ab4776ee2940ea15427844152f2d3051717ba142a8c05fe10fe5259d07fb282c8f4da08e60de58849010001	\\xce0b904d826568c67263228691d360b0b4d5882de24e490b2d000dfc2c3c9a98e2fce4b4160c54f4af8dcf9027e05ff5246f6afb00ec40311adb4a93adcaac03	1661249553000000	1661854353000000	1724926353000000	1819534353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
289	\\x9c8ef7c0ac2e89efa35b91b89f5bdba230d1a2414190a92867189ae04cdc98946e26d170905716b1e77e37daf9ad1cf8e62d4000194500a705950042ff241467	1	0	\\x000000010000000000800003bd6df21e31a615a3774cf281cd36d5670d1f111b19ef9ff858c7c8238c8012fc87d095626120995b2a2fa9e0e7928806bbfa48af39cb02912dfd3a4b9e03da3d7b50c1fe213bd7d51a3f83cf54dfdf92adf8ca19155b640c34d08f33c27f77d2f624a50ae2d06836d140c5d2c5cd2145f1d6da711b32d4f0ea794b212e9fb10b010001	\\x8ee4137543d6f830c2c03102a68207f7ca5219316de336742fc95f66949512ef0f4e1ce31cf9086c3639f8777887eebeb8df6ffb3df4ffe451e64400b857e207	1673944053000000	1674548853000000	1737620853000000	1832228853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
290	\\xa08696dc8ffd375bbdaed886bc6d7d8ccc9463039393694bf74e6783d82c689373451754bb78e989468e29e466a8b6d89e5638f3befba49959067f72f41cc0b8	1	0	\\x000000010000000000800003eec65c0762740e3ab623f0abc92e3a147c7adfd4588ae88f89598464750bd08f7c632df12de513665876616d991c8cdc37e47bfc06b46e56d353121333aadfd13a44d327b1a328b124bb6de0f31819d392fe08b85d589bef1e9a36ef495891ab105711e694953dff2a97d6558547817216f810f05bf1aac01961eaf5ed0f2063010001	\\xc1dcba4328452839a654c3069319d4cca9ec55c1e2d04594d5473cd6ddbfb94d78c9122579a29a4028f0d3b7b666596cb07207c8e1a8516ad7f12e0b60378b04	1664876553000000	1665481353000000	1728553353000000	1823161353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
291	\\xa0be2192f9756600293dc78fb09c2d16332e51e6c49338b90b617f4ad79b2a81211a1fdc6ae64af3f778154fe18f1dd0333e8843975807ef0b5a1e5d9ed89fa6	1	0	\\x000000010000000000800003b11b16fb27b11ec2b88c20ef0f1c70a61106698870c23a6e5b3d0b38396fa2f339591c9b7ba2a2cf334549515e5e320e4c136ae8ceba9eb41687a33bb0b05e6410c3cd7caf5a48fa864d5adfcbcb6601d2a4125975d54572836b2beef53e834e8479d38a466e2cd603966b62f27080afd87ebc2c1b7574b9906d2b5f4c9e568f010001	\\x036027f022f5de000bd1207804acbaeaecf7f2037dd583918940b4f2570d151373a4bdbb0d2a346d5ad88e51a9174386a0f01b459382fedb9f80029a88795808	1672735053000000	1673339853000000	1736411853000000	1831019853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xa0baabb479399bdaf0c444ef432e6cd33ee70e6540034cfa53a4e3e98c3738aa6c2b62c956d2c0f12b82a72033f464ee3d77970950f7172639786ad1636f1686	1	0	\\x000000010000000000800003d9eccc7d5e975fa7b3c71e595f9e7a2239400f4ba6363e37ba105dc74b9b2825486a7319a700530256b6653a6848c31ddb775f20d26d779749a1bfa286b1719998f603c863a2127073c2c7c9b4e2c720f96abb55a858f4e02497bbbb8f842f09c0ae7f7cf1fce26bc924ed76e97485311dd1f7af71567bb995ac8a0d7b8548e7010001	\\xde7e9ddda3b4581c6b30454c34cd5aa81ea86260755da053d76b9cb124084bb66a7d2707bc9a15f36f95fc1b705ae82668842a6b14c2769ba34716abb926a605	1651577553000000	1652182353000000	1715254353000000	1809862353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
293	\\xa14ede7d0609cf342019ee58918b1bfba2dc59e3dce58eb04e0a9278ee2278f5c4f17f1939093d57087bac139f4a667bcc7e3429834a96ab84e84bdc9a169cb0	1	0	\\x000000010000000000800003c7fea3ea8406abd14e38acf4c4533d9201740bb63a51971ec57be9784c88854bef2626e9d106ad8955c0b77ffe471ace93285fa385fb40c9c455019dc75b255bbd5d6621c58bd6b809d424860cc17e97d9fbf36c929cc3ca96072e72b6791d45c3166673e61de63bac2c43f72f3436eda8f5e90520f401da21c471e42ddb4337010001	\\x579875b8bbbdc2520f0e7910fc7311b672fa68d5fa4ece889a7fc60c1760a4c59c1c1daacbb1abcf7c663513ed6c55facf5e3428f16024e6aa154e11a60f340e	1674548553000000	1675153353000000	1738225353000000	1832833353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
294	\\xa41e9beeff49f25bc9ffb3aee50af255680bb0dc10204bd86f7f189241370bc7396edbad21a6b77c8d38f523c5e880bd06eb83aa11bab430f809e1636c8f11bc	1	0	\\x000000010000000000800003be0a4f41b3ef876507599418b133bd2f22917860f1d1e5600b71353c94d253e46eedab38303ead7b5ea0705447b8545de240de7b2e33b2b6e393a02c4fe530873f375af4ead50ec6a6ecef6e2a8ec5c95316f8ff32b126e954c6df1054b15c4575511479df7158ecd2a54f4486ff98fd3d8010655070c9b6ef07045027198a35010001	\\xb05e5bf406f99dd0165ba1eb46046753dedca1577fc991ef9da5c7ac4fa4284f250093927d169de11af62532f4472dcb0697b28f74aec5d02a3f5df7e93ff500	1655204553000000	1655809353000000	1718881353000000	1813489353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
295	\\xa52a0ee0f7bbd4374164e007f6a151834ee117ee8fc9fae143dbe81e9722fffe00558ab6d6816746f3e6972f936c0dc198a984a3b6719c855189b1353a70a90c	1	0	\\x0000000100000000008000039fcb299d1829c9d6e556c281c65877d830e9921d40cefc6c4a51e0aa107639a8712b45c3e9a6a6048cbf1fce4ce7db105cbd3dd06c0d46bd437cd4199d5fbc02dc5084c82d72b6247daa19d8cc1b5b1cd96dde8d01e62c12dd0ca8a33e1b56454b2b5505d1a88116229b74eb519364dddb524e8ccb87f0ca5e5581f6fe87d467010001	\\x42486fc695e70f022a6c20352e4c4cb8e22ba9d7eac6d05e9ffc8f5e6d6531aa38e44827b857e35f4ea44abac609219e73c1ef0f9f515e6ccc52fda2a8671801	1662458553000000	1663063353000000	1726135353000000	1820743353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\xa6826a75a10af246ded4e74bba972223094e68a7fe1b0f3672bd35d511223e8f4c9a2e813825f26cde20601178e07188a882af61ab4ceaba242ce37324bb813d	1	0	\\x000000010000000000800003c32f54a72976c46f174ab462b7ae634180830566eadec7ec063c32f21ddf0ffbb77760d17a5376f3d3d744297a86662f084d8921e88a29b3e9e6f06d9529dd168235c8b5f41bc44a18281992c1ade2471168ff074e7d6db5a9317ab5a67e227a3bf43968243b9914a8739626a13456ab24ca0043b1b5cc578dd408a5c404209f010001	\\x3e952d2d5d9d3b606dc3e22ed8cefc87f367cf4483bb304e1fb916e00ae638b43487a9f81648f0067b40926c7d7e1ba29dcbd4febd7109895ca695de2ed4ce0f	1678175553000000	1678780353000000	1741852353000000	1836460353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
297	\\xa866405d728ec36cc378e3ca46d765cbae68b79a42f161a93954bbd18633a8217090578c8e72a8e75847d376887602313c01538a9b4d08665b3dfde1bc24a089	1	0	\\x000000010000000000800003ff2a18ae765b3a8e5fc4e61a2cef7b4b8243a94a599ca81fba65c554f5a3b8c99eb83e651c10db507e09df74aac7fdc619dce8cd311fa9e9daf4f0180ed56ee25b4ee5ce5457a7c9b9c3283ab43671a6695b496ec4f4fb98b0d87c0e1da95cb4ebba309e817a9112cad750bafff4a45c7cca56cb3827d9bdada94ead1017bf15010001	\\xac0c12932f2a32dd4e77b3efeff55d3b1e86664d5a0d1b06c1d6552f3ea822d19c944cb1e38b819ab89ad15446ab43a30f6dad962c2e03d57b92424abf1ea50f	1658831553000000	1659436353000000	1722508353000000	1817116353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
298	\\xad8e4ac81446ee2219d2ff043a55d21f39f6ac6a9c1b8e32bc633dd8bcd677ea1be45573f1ade70abe28db4b005078f37710c21f435860f77abcf58d34f21a35	1	0	\\x000000010000000000800003cb6875e8ba44b6c7484bc966246831a4c00ff036b09ebc069d50fee1e49c9cf2a93a59f7826a8de573fdb50c8cdb3487d429ee780d2ebb9e993748a852f019b90c6c48d1df8476a9e812eb5e1733a134c952c5be2f4b280843a2495c3db4009ef06d5f835ec24dda50d85f02b711c07c009df29fa7c58ddfb8a9d236ef922af1010001	\\xdca6eaefe6ecbba6871df3526514064e638fe4ae4f5d3fb50d7ae3df313e9cad6544435eaf691d5f39d09739b76c05dc39f313abef2676600b6855d3c693980e	1661854053000000	1662458853000000	1725530853000000	1820138853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
299	\\xb15249bf372537b0ad6cc7c4ae46f721ebc1cdcfb85f34507331004b97445a09b2247b6602446d658b7664ca27e012773949864b40852bcec1d1290ce3096d6c	1	0	\\x000000010000000000800003d0dc39489bd4cbf54a41d17fe27e5f05caf5afbcdc15ededbcefa0dd8f860586ab54c7459c7e3dec3fbce4287844ec334d14f940291e4d8d500c789683726fde33b39ea88f623fcb87c1dfe82d66a5f677e6c7bd2ec7d970465fa0399824c12e62da3af7acfd7b453c89b7ea3df8d413bd42cb65632853ca4e0cadf41a77dca5010001	\\x76b6ea9b8e4fbc2b441224cc6451052fd9d4554869deb0da2580900bc5b94e865fff7c88056c865d7b7f3b049a746b3c2e93491a507cacfa1c73629c63fd060e	1659436053000000	1660040853000000	1723112853000000	1817720853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
300	\\xba1eba25a74c1d865df6e909569c7369aea37c4c34570fecf37580f3726812facd583a8c852e876e78cede816c54988cdf36704b439c587b2d5efa6543783ee8	1	0	\\x000000010000000000800003d4dcfd080910415f3e027883cee56ccf69d6100c342f6b6d26c4a7ed67206621a861b46c1019e720f9f900290c46192bd3994676188f5dbb6587855a60af799d1b83b1377fc28973354c36b71dca498cc844f210ea693e4e22566860b27926bbbe83e4b1ed09e40e5b9fa749f848d392cec14d254f4550dabcf3dc9740ed7eed010001	\\x1f12c4b6814026c0407e0ea341ce8738ea8273a1254efd9dd60841b130897bc809389b9121666930af6207f3c0075b05374ed4241d5dda61cebfa17eeabfc209	1665481053000000	1666085853000000	1729157853000000	1823765853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
301	\\xbb4a4e344469d77618518270d957b8caaedf8bf9aa1d98a94af1e8c6452597e62b70cd3cde70ee07d85e239de5a296c481d4decb8d1ab685651d3ecf33d4efd6	1	0	\\x000000010000000000800003ca95ca9b1a4540a7e2357d915dc93c104537a1b0d4149f576417229f74233dae5014e30f22a33bdf116de608bb043c5521b4ffa4683c15fc8b5009747edeedd99139f5303fb611725a6afff3ea55987925e8149026744bc22fb929b0d07a06501d3f591ad8d34a322386db9b13ad59e828fd5321fc2fa0c2fbdf2b4055abc611010001	\\x53b02f52d75d4ba12041eb210329ed4ef586c653b302c8dc335679b3f4353221b839b28fbcb542bc70bd16fb4b9161b97efe7f3c6e3331ed374e570706a14d0b	1663063053000000	1663667853000000	1726739853000000	1821347853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
302	\\xc1f247e4061f4c6cc9714966101e942d5df9bcc9afb94bfefcfb5af337db82950cf73c5fd812def3883c0edb872981ed53f0c632a82bf910c5989aa90e46aaa1	1	0	\\x000000010000000000800003f3b82bca07b714610dae19232756194f7e3707f6772f1697247a2aaebe62af7ebad4d7bf85bd39b1477c6cd55b0cd5eb5831f92d6a3121df65e9d424994add7ebc44d468e0d730e8833587c83767ef3c174a4d0de89355246bf7cd4f41bec73fcb0bd004e5e8202a6642e6ecd368a14614c0fb35f50d0f4df1d7c9673663d1b9010001	\\xf1fff48c45735ebe18a124c9387134939fea02d2e3357b473f52fccff97d3acef50c826aed2c968f213deb6d087465df4112a56d6f0886440a69ca869747800a	1652182053000000	1652786853000000	1715858853000000	1810466853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
303	\\xc3f6285ef896ecce2c1a4eaaaaea7984cc3e63613a5408a4d7c05a54ca2e9f1f841b75469fdc2ec569ee4b46f23cb0a7f23fe11c8e1f3b9ecac224c9c60db175	1	0	\\x000000010000000000800003b7be15cf1baa6823956c7af4abb4e073bcf9ee59ddf63b33f178042413fe61a9bdc6847c11ce6e3c15654d2ace550db24b07f1601954de054608276b0bf2fdee38c451033a828c7aaa0b6225310b64a558051d4da318fd021a5a42edfaf03e543e4776b1d6b3443f017a7f7ab6aa57aa6054e6c15f955e34e856b950379c8e87010001	\\xd3799d0cd75f6a9e560d737cbebaa03bbdfec8d8d2caf84f33109228090ec280743de737cb99ac40661bb8ebe4484a0b16dff1fbca7c307eb73dbbc4e672ce03	1668503553000000	1669108353000000	1732180353000000	1826788353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
304	\\xc7bed8e6a57d5953740f2f2a51ffa9ed833c5d446ef8812bb472402b8c8e953ac55ddef078c84ec484cba206b17dd30be78e0f3ca47f6d62440d8c10903b53f9	1	0	\\x000000010000000000800003cc9e8ec1d0ee09d9ff65b699c68ae56b82483007396a3893004368e30408d5ba427d77ccc3c364485323b8037307f0aff4438f6bdec05d6a4afa89add67be3c6828aff82029e238d3f31bcc7426a3110cd32238056eec233e7d74662d38ede865865fc67e25f6be13aa91cbd5991f07a822b349be58a05ce9b11b55c376b38a9010001	\\x06d8ba5bb41e5bf813164330d0f2f82db06582d381fccc095f3ee76ccb82ebe4082f147491dab5bde69e970b7184d0d9ffa2a1e10c0e077019c5646b0a13a509	1655809053000000	1656413853000000	1719485853000000	1814093853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
305	\\xc88ee851c2a2aeb0026a8633dd131c18b0fa1a58cbcee4f6dcec6d3bed166c1551ba42ecc6258643fa4037191c731f6daf548be6cd4c3d37397f0311e1a451bd	1	0	\\x000000010000000000800003c9768469d7e8f68bd3b471fe8f24c1455cfa84449a27437bc38e93512e580e2bd156c2ed6ecea3458afd4a14fab34569ecc3d7558be5ad63109038345031c6a717227cd0d27810a54ca973321105d258bb2c722830fa78f8053d49710b2448469a549ac7fdf563c7d44e5a927c189b252a035dc76e9f9fb387e11ee3bbc4d797010001	\\x93f9095ed3137904b1044b80c41da4a8ef700d49ea589323b567f9c67e2673c0dc555f4566c9c77ffa3e28245604030d8db6b22f3e372b3f15b787306ef09803	1672735053000000	1673339853000000	1736411853000000	1831019853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xc92612af1693465186bf29fda69ed72176da0ec8181d2956f16c55907ad813a04703e96a0361b2422693286383498cf7e47498a454be6b5dccecd1d18ced5788	1	0	\\x000000010000000000800003d7b7cf51056443ba9e3f87e0d233e0f1fe13a20f5efddaeea58324a3cd31482aa005716738d6158aa94ce4a78edd5c576a816573a6b89450a9bca9011014f1fe6d4469831e81dd5fe3106c1a2debd059107b7c921a161df9e422aa4c9e98a6497ee69167d8df89688d7710d9403b918b04f89e374b777975e33a2af730556433010001	\\x3b25a121610ff278314620cc0c48ab4323cc0d7e68f8af1ccdb2e75592db41a8625d8b8c1a715b2040cba5d7d8beb5ca9ba124ceed95c1264c2eb65cd6b7e80f	1653391053000000	1653995853000000	1717067853000000	1811675853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
307	\\xcdc223b135663f739fd09cf3332b0dc63826422b570eeda2f6fa9410c44c5258f4a02c8be952e969967324e77c39b419b8c0662e052450b37291613195274b15	1	0	\\x000000010000000000800003c1c6e22435bbfff4aada3f6570c7890b4a00f9644ad359ef598a9ab823de9c24245fe61114b05ee7d173be9aa27a4f114225c031046ef54f68bd58b68b4caa621346ed81750964686c7ac58bdd40f6c1000dd30ee9bf353a2fecc5daae0c3c501a07ac1f4afa3d5fac43674442c04cd044457571c5d048103875ccdb16c9fc6d010001	\\x79d3b969d81633d53af22816eacf0f12a4c4d9ba8b2c001727b7e3dc3b2e101a674ca6b4d46f4f50ca1cd35813c927983b56c2bad9fa9a6ca9d276760bdeb407	1652786553000000	1653391353000000	1716463353000000	1811071353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
308	\\xcd22cdf3e58b503680f392acc05e8d56e74c5cf1e39948bddf84f2576fdc3687fc6370c872790306be2fef837fed3ce5220cc0c9a8bb05a5cd2c80f3ffdaefe6	1	0	\\x000000010000000000800003ad5fc81d89930a7cb770ad32377c963c9437959d82d7a2fd4a7d430f2490ecc3ec1d9a0104dd3bfabfb4efce74abe2fcd83520e0e914bb65eb5249adfb1d862a1856a3d341d462cac8a784f11d11e999c0f245ec8d9e1941556cca590a1ee286ae76eb20ee4e313b74b9f60dabfc01e67594f17c4d2eb815f770efbf66aff741010001	\\x869c08f5017df0ab8498997810a79d3175597a162263129e509fe6831ffc5067eea94371f969857cf959cc4f6045820db2b03c363fe9327c6ef7c8f5b03d5505	1673339553000000	1673944353000000	1737016353000000	1831624353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xd05a2bd04d8c5fe0b019617f5110ef10f4ede3046738814267d6489c6f9e75f72741285a47428db8f5de448acdab157ba5ebea5712f1743e9b054c8689eb243b	1	0	\\x0000000100000000008000039f7d0bb2c58ad950f08aec5b0a46e61f38b78bf3b2a88d086a929c0c0440584550c48ae08a19705ce59e4360026fdbe6b65acdc75d446589d1bd7d263795c1ea290d6ac59732ca52523839102d86be244f2cf0bb50d51b6e708ee05b6ca4a31c1d34b4518b4ea08060753f79925e7d7cc50301e66d8ff14c88aa27cdcddaf825010001	\\xb53d5b95735537e067ac941b018a650d83e04c3438aab1ed2da8c636f7d19dc910dd666ad77e1a3154252cef559a5a014b04e8e6babb608bf84f49d7c2df070b	1670317053000000	1670921853000000	1733993853000000	1828601853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
310	\\xd2f6e5ee17c7d60bdb6d12e32d9c6cb28ad15234a601d159b5a87403e864106f0a21ac41a6ed820f202d5faf69ca67ed61fee9a2f36399f03f60105b432fcf3f	1	0	\\x000000010000000000800003b305b9b02bf8b92a26aa789a8da9f5c612d2aaacf6e99af87fb8334d096f22315f40e0cedb00927048d726352f235490d8c1d7e169ce2a999cd16ac06f317b27e007b1d2d558e2ca9bf9aff88a858f138a83a752c279b08e116e893186d5ae0c134a81715b17f89e6993979e43e1c1ea78d70a359e9e74150473477a2d40dcc5010001	\\x412e98fc83596e5c3db7732e509e30efcc9094828b98353f0696e7818100a908ee7aacead4029e28dfa32f59e057e56e7905a8b709b3ac467c75692ba071f909	1667899053000000	1668503853000000	1731575853000000	1826183853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
311	\\xdc727001d568b959fb2893e5e842383524f55cec34ecaa5afd5819844d3cbc45eba6731515cda2bb6a9bae2e4affed5393c7735f525f70db85914204653ccf86	1	0	\\x000000010000000000800003c6d596e1a67adcb19d4f3ffa1b73f7d18ab49028d0a27744ac1a88b02cc8e0004148191a427c4a4d250646108200a85389a503cc177761a5df988e218c6badbb9a57463a9ac001369a6c71ed17ea10fc19952afb5e147b123ff3c46c5846040bb3c4093cde63a72eb53a5860b80c6d5c3c9b0ff2ebaefdb3f942ef476571bafb010001	\\x68a9098a1957a16120f15289711644ddc39543a9eb9ff2d4267a702869cf286b2ca49571fca9feb7ecffba079674d7335c27b2d395bec471a3b0d1ba35313d04	1677571053000000	1678175853000000	1741247853000000	1835855853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
312	\\xde229f5779afd1a26fd913042bb8610e4579c99a3e12e16fdca351222ffc4e644419b8c51d158cfd0a8682712a3e18ea3c52d641b1f958f7e6bbd61511c1628c	1	0	\\x000000010000000000800003dc97ed5dd37e20ba9709e81a1583e1a2c227cbc9f836f159b1682eadd650ce429e77ad4c312dd37fddb695dc2e85590a450f5d37a52c0dd94d2439e8d1f877f74e0fd1a096ac7c58b18ceeb92cdd1f265eb6e409434f7d4dd394296518f1e0da78c42642360c4bc6443ac4a143927bb385720558f4309bef555817eb339af6d7010001	\\xe4619d42af653f28c81028c81caa6623573aa5bd3ce6af4a8cbe54ea1f833f8acfd18fc73a881cf8dc9a997331c433b71504ff2ceb34d824f61c8e15c534790c	1657622553000000	1658227353000000	1721299353000000	1815907353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
313	\\xe2a6c46284894d4ef2f935ac4d7379a757f64ce1181a598d77802c20f2aa58c0591dd3a93e687c6517b2bd72d1761c798cb57ea8a435b346c25324d19b36ee0e	1	0	\\x000000010000000000800003f9207e44566b0c963b96ff1471255e7bbd25abf50742504de385fb78add8a2a84aa9c96e706e270f39d1b086c7b4aab56331a7b23ea8e95351dbd452aaf48d589543d538337929ff202298c3399eb677522d6d78263b3b46fde68456d63bd9378bec2607e22fc9e35f0c1f6ea2c0199973c25345ca60c7e5da8654be0daeaf3d010001	\\x2531a5b1b39fe4a17b8d5080e01151b68da6884a5b38f2270e6f96f5e226455f38d22fa14ef3de869c64896db3d3aa44cd38dc95e0928d1a3a9b9607d3b66805	1674548553000000	1675153353000000	1738225353000000	1832833353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
314	\\xe7fa6f42fcf03008804aeaf5f29d9962cef569e80c588af98d054ab382d45bcdaf2346a6024a5a4a3382dbd0bcae187f532a5d087d9f498939e3307a32c34d6d	1	0	\\x000000010000000000800003f3aaee5ac3f2620d3b32eb15e3dc1343e4eed627ba5a619b05837381f9203db789cc3fd2630ba980f4b6ea0ee373c9a5042c8be6f0e511afc02c33756c63fbe648bd22b2745e5ceb8928a659bdeef9cb19f4b3ef71586f5604cf23dfa58704a7a2c8744bafc9b90f721eea01305dbd89f645b7a31d6e5b68a56e8fb2d43565d3010001	\\xaf6564162d63b8ef5fe927387fcb42c2848665ce587cc0153b98029433260e76c991ba864ee9ed170b7fe2e7b7fac8a5c5e81d7218888bc2878b9523683de409	1676362053000000	1676966853000000	1740038853000000	1834646853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
315	\\xe7224921bf1a4f97d8bb39a3b2a011cb2b2df6f1e7a7fbf564568ab2e4467a34be19ea8d15da5f62ad861cc82db3392403f05cf7611fcf2b6040042602020fad	1	0	\\x000000010000000000800003a851572f3169ba2dacd835963609f6c983a8b80883718a1e3827885591ece44092f63198c954717c389a6aa5440436891db15011dd437963ab338b292c241ff5f7211b370376797e76c1bdcda1749b310775d20541b42e53eb93070cd6be868d844280fee98f08d3ed263fb0c54fcd85dd1c1c299ef4f241bb8e180555fb42a1010001	\\xadc1adfa3bf9067eb77fbc60c8804d91bd2d0541650e2cefe914ca68de67dcd1d3ad3fdf9a4330b13a3b7931186aafeecb838ab638ea3fb1d599b2fbf69dc106	1662458553000000	1663063353000000	1726135353000000	1820743353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
316	\\xe826eb55e4fd90023d682ca34e6bfae7c3a4c0fa121c97cb956bf53db739da9b420fc014401db583bb22f28dad569c6e0c65482063e64b4fc27f9a41566ccaef	1	0	\\x000000010000000000800003cc7f5687e299aee98e18615219f5acf77aa6cb75176e3960410c283fa689a1191966e381714be5861cc6d0ce0d3fd80e91033b1d3db68bd0aeb70bfe1532a6538ab3dfa1ef9374476f0564e92e37f42e0789448c7309e1d15b1f75ced413f7e25e7da00574aed4859a0c07cd3e03e2d6d5fddf979991bb4799f2dad9a6b241f3010001	\\x5f792c1248fcfddcfad2b34ac45ca5f0eac9faa97fc6d41c9db174abae0c7d5a349a3480b73d0bf4ec0e5337e8c60d79547203fde2326ebfd98e8fa0adba4a0b	1653391053000000	1653995853000000	1717067853000000	1811675853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
317	\\xe8fefbdca1f91f3d6d31380fe19df4f185ed8bd5a38c62520f9ec4dbc0eef74b5854d91621822867872e672f3e1c9d0e94103d596d7cf09fae5e39485c08e982	1	0	\\x000000010000000000800003bc567007af80eee6e99bc850fdd25062f6e1d25be8f29aa1880f151c8698ddae838f4a214bafce61df2a15c07dc88507cbbf1f9339f3ccdeef69ddde34cc10acfdddbb7119fa30801e409277211e8da9e8807cea5e2cf448017d23134ac7a4fe800639025ec21eff3561d4814eb94639aa0f427fe22893bd9cceabac12b6e183010001	\\xc8c8fcf02eece7a1d726f4f685213f2065bfce47e2a02bf2f541587e8f2648452c5507a6c9a6b49e8ce16830a9c94e21e20dd3f821baab9947fd280f02936807	1655204553000000	1655809353000000	1718881353000000	1813489353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
318	\\xe8ae93e2311fe66c6567459378e6bda6e93960997d462e75f090e977493ea91cd56ae195c629fd66ded9cb1629d1aac7a321cd29725e00d44c24c479a8d9fe10	1	0	\\x000000010000000000800003e1d581f383df1cc6e94b6307bfa6dd923675048b4dbde8c19b93d7d2423a88732f57e0ad0fedea8aafd00f44511ee6577df3c566e9c8049d0b4e6e1d07d22abbde93a0a80fd0d4b3e119de427b91b814ade251d416fc5f83e6795fc34f1f446d1861518510d0618b30574a5ddf4c3ce856d9cd8200051c8440ad5584a3fd582f010001	\\x317f3e89dcde0f0374dc1f537c3e25e04b21b0d959673f7996fd5cfb166a74af1053e301b25695328af1a08c60439a39b514ffcf6967f0aab4c2c5277f13a306	1676966553000000	1677571353000000	1740643353000000	1835251353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xe822243c5e4e3d8abc9baa5a29967a13681c7ebf4cbfaaa7a20ec37ab75a83a8dadf7939498581273910e83c08568f44a9f9ba242bbfc4d265429078b024e44e	1	0	\\x000000010000000000800003b4ebe072ab6386a727fc8c1249585b8290bb0ae3fdc9affdb0d8705d4f8d7c6164dea41414716ec7e9641c2b4e58cff09efb2c85896f60d0ec1572a55161d42b0fe181deebfd6e9e192c8cfda90140622715a944a3cfbc95b806d06d869df8ffe2b6fb81ef96246f93d11eaf05fbccf374276e2b1edcbaad87ca44c65b77e475010001	\\xbdb3ae58f6ca5d0627a024dca882bdd81ae610de56c9b009abfd44a986c263616d1300ab416802130135439d47f6b451eb8e8a31ca6c71c679825f87d1527302	1667294553000000	1667899353000000	1730971353000000	1825579353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
320	\\xe87278f1973ff1f3179a8034a839e9f0cff7b4ed3e987654b664165a75c947c92bbd77603d7fcef8728f07b42f37080e62488d7cc9209de2b8ecada4ec70ce4a	1	0	\\x000000010000000000800003d4af6285a1dc5b7475d8308604ae961f9734c03eeaa34e166af997dfdabfc7a551680b5545da878601a6b1e5daf060aa65dead65f7ee19fd21698636a3a1bab4ae00a7b9869b103c8b82efffad4f03c8cd118fd0644ac4dd71b7e6e8b5e311fff326d47fd5fc5a7cfaf6b012dc4807e0adce0ad4bc830f810068aa87d75b2cc3010001	\\xca71595a2f3628d4e23c4a6cdfd04cfe972c5576001b8a63865be49cd83edae9eb059dee0709c063256ef8ad229705d81625c2a50b16b4fd74903a69b144d507	1673944053000000	1674548853000000	1737620853000000	1832228853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
321	\\xea5add8c22fec3c04b8367eafc352c0c33749f992ad723a6efa679f5cc8317cd7c95300c9d4ba26df62f5ecbd67cbb1e9c4d7fd912ccfca0a547cecb98c6571e	1	0	\\x000000010000000000800003d27526889363489c8690c830c22f34a41c856b276c1318944be2a63ee052e257daba7b3dfeae9bfb9cd9c0341a292fb65fe637ffeac6bd7afadf9e5e1c4f2e0e50cea76c062de403ea955bcebc8c24be30572f4ae8e063f93505799ececb5b3eb5ce2da4fac2fba60979ca0a586e83c81f06f9e149ad28b2c6fc6ce86fb816d7010001	\\xd4a31fe8fb384ba2535cf8790b5e75af16481205a36e4a4f2a9a1344800b174b7e55331cbf3dc12a5ce20751d196888ee67e555b7047c1babdc52010c3917304	1661854053000000	1662458853000000	1725530853000000	1820138853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\xea565c84ac5aa584b572a5813ca337a40de6c878b8958fccf3038b830bdcf7e19bf71865af931cc1feb993f177078c7d07040913b555d224ed081bbef15929a8	1	0	\\x000000010000000000800003cd57b7aad4ca92a2fe25b3edfdbc67f9af907727c885a157a920bfd259272f1c7d3cfb8dd6ba1275d08cfcc46aa752bb0185b9be3de32aa3c99db7886b11f272fd59ce4ab7a098a843891ffd1e5f19d9df1c31db06ff60281af99bed3be76ea8317ec848a47f196afe2376b4bb0818841dbcf330b94a15571a14e3c03c64d60b010001	\\x5b36313277c4943c132f0a146f9fb1b1d7d17f5bc8e434ece6bf1ebae1b36eb002405c3819754a5f8e617e831480eac23d389d85a6dac2adb8979b8e6975a301	1653995553000000	1654600353000000	1717672353000000	1812280353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
323	\\xec9eb889375e111cc92b7f347f9d9a6eaa123f75c70644758101e0fc8bfbea19035a7b1a8fd3eac5ca30815fcb36015126f7b258e4183a74dc67f7a76abdfd44	1	0	\\x000000010000000000800003e1b2b1491e8fa5434df5bf8af81610c19624a226e4d05e317c323044eb34168a0eb48fd9dea0831abbcb7722929d3424bb90a1ca29c5fcb230ffa906bb82d4ab76715392dbd2c3d72a6408a3abfc7878bb4f6c69fad9be5dbea664721198831a00a35f704e3c0e27aa2d720536e73999e7d88dc617637f6b17799a6c1860a1e7010001	\\x8b54436770ae52657819a479ac4373309ba97b05ed2db109e4faf792a3d7cb32ad1dab49e1d99b4f86f7d647c4b0c95f347849ab553f4b8815e0f6f01e62e808	1652786553000000	1653391353000000	1716463353000000	1811071353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\xec3ab54e90f3fcfc1bfdac5adba156ab2d18dce5b55a7d278bd6ba46ee9f931131dddc3cdf7cc1f2e87c2d4f9577afc405069af1a580628b650be85c313b0e39	1	0	\\x000000010000000000800003a3805920d6cc0866ae7b57f8860bef561bed638209c1a25743303aafd2689ef733ddc9f249d54381e8b3fe99e40e6cbdf493ef92f64c965025f598bceecb5101531489507a81fd3301a27bf908b868f13a4c94fbdc77263e287ce9e9dfd00125aa697b9a8469f607e60ae5529f222a98f68132fc530295244cb33d6eb6b428b9010001	\\x815f2d4b26b8947c4e0f5d9a5ed1e7c3ef46546394ed9ec7ecbb8447975aca7b90851d4534ba130618e518ec57d8ce45c431d55f7ab208888507c5a261d9170d	1666690053000000	1667294853000000	1730366853000000	1824974853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
325	\\xf16e02e8f70a94ebcd4838d0f63f83acddd58117c002a9129be8f6cbaa05165451a9bfb4e0662d7fad8f93951b6505af957cbd0ff79cb86e3fd382b03c2a8364	1	0	\\x000000010000000000800003ba1e79e96c40a57a191b391a25f42425e582d822fbf03ca527c531ad6000e4572879d26004f24bb200469cb279958a06171b8ff2b015946b670b4da5d0b053dba6435fa37e78914bbb7b6bd08db131989b762b449dc8ce5f3e499d757a537f1cf8f20193f7b8e7bef7af5a86ca740c2bc9b33f6925fc04fb710e2858349b9b07010001	\\x09538dffeb072087f3e4b61e945aa569c316a2bc4d53b8ff07239bd8a0083595487f6986f5e6c8a83d4e32cb29fab003a83f8eb878519da60b95d87ef8cad203	1676966553000000	1677571353000000	1740643353000000	1835251353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\xf13a7242ecbf5a90f769699f4a8092ea8ad9aa049155b3243011ddc67880e307fb42c6ce1fa5c056d30aa0524c3051474d766dcf31bbb89a943498872df6b740	1	0	\\x000000010000000000800003db47f6690e03baf80f5864e4ddc866e59b845dfa220cd083f92722d9119a5152e753e9742137fdfd762de2d3126f2af940343c318f31b98c6f4616ddf1021292cf0a73b258d8d12f283b0ab33611ea686ef6c11505da513bfc12d7d3bc4a284b23e65619572aa197e9c33d71c2e93ff674df5ea460a113fb5460271724b6780b010001	\\xefbb0e81e2ddc16d617f6376f2cf24139146146d73b7ad5251ec82222b4feab072db46a00d755340b31b846167d98e39669797e6996267f065a17c63752fd906	1664272053000000	1664876853000000	1727948853000000	1822556853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
327	\\xf51207b7d13ef495eb7418b1be9ac711b2424e1ee1d83e4db78dc73cae03f8eabbf1132838c81637360d232b876142ca7291e20ce6c11e0ec1b39b9b71006cc9	1	0	\\x000000010000000000800003ccc789b2dc4c49f6769b41aa83de50ff535d4401658f400162dfa63747d7251d385d9e198b4be76db746673071dea31502342cc8e0bb1095009f4295e53506f81008d5f66293c13e93cd76aebc29b45d872b04e4bd1b64d3417c164edfd4b2064759bf772765e92fb75d808a0bb60b4557c6eddecb2b3fcb07f6234577a015b5010001	\\x1f0a3ce02600503252d9927aae8471af04c2421bbf34757b0cdcdc25cd200de0ac09ed1ace3c50800a73235ec417a64b411ccda647c0575192520fd06169f707	1648555053000000	1649159853000000	1712231853000000	1806839853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\xf986ccf1692a39e0917611ac32998cda6d505ab7bdea1be19d5b89a517cb6d1c634a6413dacc34f9a264a44c7baaa33d400fbfb3362b8a5d4a10b63e011ccc8b	1	0	\\x000000010000000000800003c8f3381ded8bed6bf75732e713c22ed077888faedec88f1858c04c86d4a60eaaa84ab572f96003ae052205ab51872b527a567a3cf11a96f564e50aeeca6fa50ef4112f5fd495ae67b93974010ce738e0e8fac707656cebe7fc9fce42799cfb1723fa4e3767007d206db50b3efc17295939806e9423800d82cd3142db3fb1130b010001	\\x1e3f0ef020136cca6734118f5e4b82d8efef454c4fb1665e4436e21c686f069126794c7134ff9e97ea1eed075ea7c412b0ae4e4f4b4664ad0061346cee23a404	1664876553000000	1665481353000000	1728553353000000	1823161353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
329	\\x003754f04a718e7938e514e1e2a37d056ed2f084bfb7211808c49d853984c938d4e02b19ea3a746daabe4e54049ff0fabc0a45251701ab037087a6d1e1cfe3bd	1	0	\\x000000010000000000800003c19a67d9c801003eb3590018c6dad2c69cdd5dc59bb95a3fa8a594afb0dbcf3639c4f07ceeecbd706f5882b45d8540eb00dce052ddbe88da357d4448f237ed980e1f1e664df424b3e6c3dce5f26ab27d2c6df31b2c53a6ad4f72fb559ac117ead1d5445a97d7f402109ce5d8a7d9c1797e479dff7eba23b2e07f255a0e300e49010001	\\x889966617f024b73851a4c3b31457a4f7acf435057241cefbe23b5388104df2c21944ae89df3d9f5915576e5d8f44e5b8c8bff0157e8a3612afd666f6318a20f	1673339553000000	1673944353000000	1737016353000000	1831624353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x0193b7390cca2373f3e0abf157c8b1b1828e6ee9bb7aa36e8a3bfae9881a4e13bf0970809e1539d6761d6fe08f6fc0be9627adc69cd747f41bcfba5e2f9d5881	1	0	\\x000000010000000000800003e7c263aa4b53339a8421c4e54774635071a7202b4e4e78234189b21df9207a1219ae97db232ee0ace494a1caac738580afee1883309a8f0d4cf8b09a8654920133d0148aaa0ab6a4a1d70d18a56ca92f7121ab18527129a7273f360e2821a95022e64a52a4c78775e13fd3714698b026064d754031cc2d78a9e66a2a3042b7cf010001	\\x027212783e56bb6d90e2f9d65e3373eea505a77261489add72b7e8fc75dcefb3bca052018075373ed4843461c9702eac3533c93ee91b35761f1019fa3bd0b20c	1673944053000000	1674548853000000	1737620853000000	1832228853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
331	\\x040bac18c50aa0f9fe5224baf6e789d12fc338b94355f7a74be1e0e817addf49165b55d84668e91c9ed6b85ab9e4b5db36216188daba223b22d4f5320d020849	1	0	\\x000000010000000000800003db76f8afc25112c31bf88ac3704515354faa5676b6ec3f4ee6dba8d9d053b423837a6d509318363105d6292218b54f2930a730bc2ccb1959467c93ede898ba8ec7b7fd0d090835ee05e4c40b1679ea7bf0c43b76474464f1cb416b301fa1d8d76f8590fa502bce596be34d5fb4541b4af0dacbbc8cadffc73e15c928c89f1b71010001	\\xd0c81bba500c6a6ac234ed6f889674241957f9d57c7d8891aef5818b1ff61f941b721d635b2579dc157f5c8e55195bc4239135cae85a8755a483e712f452240d	1672130553000000	1672735353000000	1735807353000000	1830415353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
332	\\x0617dd965b0c2a8e43b79cc14545a3bf4e406029bdd19e34ac42cfcedd9056981e219e0cd00c142b61c297032ac00199199c7d3014ddd875263a94b1dc86def8	1	0	\\x000000010000000000800003d1e805faf2640a598fe670fd269134d51523e270ad7913070ab61e9fab311cf72b092eb2bd04a1a858edb8f36a995ba6f2f69b4476060b5fd8af69bccadca1d9777a63d5199aa868da9825029c0a82ffe41ece0cfac46b2103eed37192aeb4374c0f8161005b5e71916b6067d5bc5029f6d7aea0472515a74614f15d142c6a2b010001	\\xe77b3bb64f688a0418ba5ff74fae5d2f4540382886e549a4b4ccd1af09c3135aff8441f1cf8d3ca197dd398bb25cd7e3084a2ae952d9d757b1762a747a9f4e0e	1674548553000000	1675153353000000	1738225353000000	1832833353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x06b32ef790d1eb4b01700552d4845eb9561cb133ecf92ca8c14e0178bf9a3e3fd6d7a6b4432a8a8876fa67b186ffcfd806b36d06769909daa07d9a23c9e2721d	1	0	\\x000000010000000000800003b2d86879babeda489bf0b5f0a756bfc07d0e271340bb3c07ba37c2aac881dd01354f0eb36440a3e212d5fc1c22d00b70a9d48cf6373e803c9e95e6d20dd0f99e8b3575e02f3078c22ffd65336df38481c3e602d9b3494d0889f150807c08bda0482f60f2fa3761450dfa9b358e846dde5bc8f2d907857c55e45ac1e348c8153d010001	\\x0fa7670066b16ca7abe1fb8b249d12eb44999310b5b05be139f6a6ba5231a3d4d64c2c37f9e90c6f9ca8213ed92acb3dff1d3059d3445e06385e35a064eec505	1661249553000000	1661854353000000	1724926353000000	1819534353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
334	\\x0a4f3842fb4ef78c0790ea136aa81938ada35cd29eca3ee4218eeb07ed90d11a09ca7f4843e5628abab5b3be7e8fbdecdb85bb9d6ab9139aa1cc52bd353e9c7c	1	0	\\x000000010000000000800003bbfae7159d9ee622942756e3851cb238e748cb463062ed009b1cb9f159963e25d7d1039e4e47cd7163d6158805ff533729c09c77433b7e6d06f0a2731a12d5d9c4c0012a9b53f1c7b4e995584bd2f9c7a7ad34121dabd72c812873ab1ff81569f3f51b8fa92d6bc93064ef44d02b93d2079a4c766aa73594f7b2767307f89399010001	\\x6757f03b09faa8038ea5784ca9273143ce59552746e504180d5fc912f5f2642c21638d5e4181d497e257fddfa0c77dd812a763badb194c74858fb023660f5304	1666085553000000	1666690353000000	1729762353000000	1824370353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
335	\\x0daf7358e84b4329617b08ecbfbbae8926637d14035436663f26523216e6a18ebb28b64ad92d52de298fbcb450f06726d9dc87e66594bfddbc87fc7c94d9b656	1	0	\\x000000010000000000800003c12ed1878ad9e1ad8c3ca6cf37ef1f937d9394cdc229007a3ec9872c341fd81e17599c43ae877db49e1b76e5201944e5bca7310395104f1c3e9ebec610c64b80c660dca5058c68faeef393728ce9b9833462914846244ad5ed54e522d16c190a37922cc681235762f03dda172c80574e77cfd90e1956ac26057dc2e8124f83cb010001	\\x34cbf225d07f3f7126c8763ed6f6e550629473e4f2bd99b4a92c5b52130e9509b6d11951be9a34cb657edd6c01629d32f1291d0916a17afd55f361779c121a06	1658831553000000	1659436353000000	1722508353000000	1817116353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
336	\\x13f3485a278937e00c2ee310f687ea7d1fec8b329acf334f14b28ab5d446c20ad344fb5ea80554ae25c05b6e61cfe872bc956df4c2726ff0faf4b54f65428532	1	0	\\x000000010000000000800003c2789d5734227928ff27b6cef9a03d617732dfc153d98cc1b0b7dbcd5a987e045f031b00f82d9c1ded4a9731f1c3ddc04ae2e90121769ee555326d1e240332dcec9ffd397d5bb381c7c01be586951f3bd7501b8b1a7aeea5dd2b814a315cc054700242961fde1f5c6a533180886c377e946674ab1c28b2055e96aab1ed8928f7010001	\\xfe02cbe33a6291b94ae775c7c1d514ac251c6139e671a57d77d77be06f93769c3624b2445d9db76823c04dcde792670b6e920514cccca0ab093af8dd6ddf5306	1678175553000000	1678780353000000	1741852353000000	1836460353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
337	\\x174ba4c0090d8d3d3af664a945219c71f7921312f10405990ae8442de620eb38f0b4d8e09ac5c6ea4a842eeda00d9b0d0dec4a59b2efb9363e0e0a453b6f67eb	1	0	\\x000000010000000000800003b6cd4bd38c2f268f8be80d3d0c62533deed9313010b8247cb032bad73aaddc98d9acdc3a31f6d5b413f15e3d0584a25951fe9e90f546949665d3de06e72f98ff5972a9cdd040f02fddb2a9e86d5f291abb227a8b6fc2bc9531554357c6ead18b5813ecea6c2636ff691fba4c7aa42b14af8d74a32c1b3e138f337cbd5505f8f3010001	\\x82d931eedf2381f091091db5c094c4edc4dd474cdd2251154eb23d1d5e382a6e24721a98f693906834d22fbeb08849fad989a1447d678e5d3f535963e8874904	1664272053000000	1664876853000000	1727948853000000	1822556853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
338	\\x1b935b355cbcfadc1fef63d67e1dcd19422ad2366457f4cc873e738b1c8ad1a7357aee3bfa74ab7028216f8db5c5bcb2911707ab35fa95511cda6d57a9d88663	1	0	\\x000000010000000000800003ab8b0e44cbc402e02960b60b054d49f58fa2b70fb3736d4db3f89d647097ada1949a9d60579cb4b11f0dd8d629bfda4372dd632264880107324e0397ac7801a4fc200ddb4dabf02a3996326ce0c3c5f70a36ff566d91405edf9a51ad413f0cfb5d73bcf7fc59980fdfcb7487d588b96f102cb26f127517c8101ff878d0f151f1010001	\\xc772c2b5aad1880a94591c72adab7061ee3fece6b73688842e661a99c0c992044e182693138e7a09b71f605018d9cf722b70932f5c427f3052b5fe7a8dd71f08	1661249553000000	1661854353000000	1724926353000000	1819534353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x1b9b78827710114a5d383ebee78db0d7c832e270714081c408742088764963b662e90482818b994e21dbcffd28b60e3a3b594700aa21abd59caf96146151913f	1	0	\\x000000010000000000800003e593602ec56cad079d14008d7d27f5fc94473ae6d843ad3e4ee17c86b3eb7a3d4a33f679e32feacddc62a92a48fc3b2b073dd004361a0cc05b42fb442274f2931d1ea99cbb44bcaff580ffc3e5b7c27883a8cd23987f76d3518605e2395abdd160a5883fa46528ec17e6147c3a67e9810d2f1a0e2a4ed33ecfd568d6074cad6f010001	\\xeb40ef07fbe7c04b648e5027e73488f1f56a4a4cee4700ca212b4e3ad8a471114309376fb31df26fa3fc0108975fe05b87dc0e9cf0a683332af04dd81d249a02	1652182053000000	1652786853000000	1715858853000000	1810466853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x22338d8ede157215f8aaf70904c2452230d528a89668c8d66b00907555e2acd9eb75b14d64e451611c10339d49364299921cfcf76fd3571e19a040fdd102be3b	1	0	\\x000000010000000000800003b081202803f16496d69709e6e94b65b2659ca76555a205fc2825d6ec119e89190414b9ccbb1655abdce88003cd1abdd292562afa1c6046d3b3bdf1955374a207a18b42571a90721d17157ef550c8490eb17b8d0f4e5db2e6a88e92a366faafae95aeee000109928f7b192ea99317550bb843273b326fbb8859838efc9a2b0e79010001	\\x659eadb9e75d1f104176df7b618f23cab01804a194b601876f98aaec065b1e68053f758e0522096881828a23b3f42d71f039c1c73bb84b9d452e3b2639565407	1650973053000000	1651577853000000	1714649853000000	1809257853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
341	\\x239f2c5ecb2a77793ec7d660d74babebf3b75ed9cdcb88915ce7db3129b1da612b9ff09f59d94ee964f03878d73cc592e33fd8032acdd97b8654f04d2630eba9	1	0	\\x000000010000000000800003c27038dc0a700e951c00d3110621976f8ddd6ffbeaff340b8d893ee9a6510455579e9cb389cf00aa8d0404cb59ab18d785822aae6d50e167f15b257d48cdf69826d32e6a69806206b601bbdf3e76358ac5b3ca341c3d224ef9360f152b6fab543124c769a60c055abfdd98f212981049c3781c837334b17b5f9d8c87420e2d75010001	\\xdbee3def6db8ccf31f82c79f158a407afad55486b8e0de981fc0094acf1428306691c783c96a24e68b4932ddbfbf8b310a9d3fec98a653845354309d67431707	1660645053000000	1661249853000000	1724321853000000	1818929853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
342	\\x277ff9522ffab6892ae2dcc863c3b634ea7c1ee68e685cb5ba7331b0302cc72e4321367a6d8e4caaa9bfe7d5482850d053e348521aa275ca58d6e87cbfe44eab	1	0	\\x000000010000000000800003ae9a1b61e4576b87240fe2eda81dc58b17e5361e013cb651b03d7fd8e86e1e9ae92f11ef9e0f287ad8c7c1572d9fb45b05e9dd9326134da02060266a1667b6a6d5b9e36c5d816fac11ed6ae4f4d3833f372786da57701e46b79a44e4a9ed6c4107c92e698f1c9a011e64f908921d5341348ac9dd8edbb5182e42f7202b40e27d010001	\\x3fe7129aaa1d80d4c64e1f514493d3290745ae02dcb5a2d57f0cfede3cf929b089fd9bf1efba83a2084715bf95b7b9c19317d627b0fe1bce3ed9ba5a8e4d2006	1658227053000000	1658831853000000	1721903853000000	1816511853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
343	\\x287fd76ef81a27ed3df992d7f14b2297916ee7cab30d931a30fc7e37a75412f9e38e33f46ec56f5c1cea731496c05756fe0f65739f2e3d72fe83c6c4cd0ce585	1	0	\\x000000010000000000800003a8d4e047ffba0886c54c0874437a61bdad029d3fb3c2b3437ff5f0e65cbc71a21e56bc3cf7d4ed598e2bac7fb4e3a1882ff2c77f25ae777ff0bea65f0a9cf466ffa95b201a721e0cf71c9d7ea33a28d0560bff42b96b8d66d779e0fb8f7d90c2a25cab10594238ef94c75e8dd1fc7c06250c3f83a08d14b558ff273151ee9d85010001	\\xe44eb2bd9af79c543525ca02d50c4922f3f941a7081e2471c6d7b9a55b7afad4a171a2999b0c5a37b835dbe1d290d3aed7597dd0447fd4942c0c25282ba6ab0f	1661854053000000	1662458853000000	1725530853000000	1820138853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
344	\\x288f0ab6c449d64a37067c6abdef760f4dc830ebbd651050ea0d1f6bd25951702fd1cb08744141caaf0b56326ec5dffa01ccfeec04109dac2846b8350f08669e	1	0	\\x000000010000000000800003ca74bd6a129d1732781d59ccf54d66318f172bcd293c8e3cb132f178712f665ed41a7ebd267c3f42644ca3577b05675f7837f3e5207475e6c65b7884707c11dd86f06ffd42ddabd130ca67b61a9a0ce9dc715c25c6c773dc47d2d628dafb52b9e81cbbb901f52b76a9e97fdc2aefc4bfe0579b6204264414df25b0c37c785755010001	\\x64cc12537d2374cb6e05cf9da20ce34010571cd2904b63abcb84c81ec53f3c9ef09daacecb8ffd9cdb52c66facbc094634aa17da738a91169d26bcd23cb3b90a	1649159553000000	1649764353000000	1712836353000000	1807444353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
345	\\x2fa74625ffb9983d4c34b271158f60aa10e5ef7b255a99f7f8f69704cc0069fcf428d37cc80b4ceee3eadad87a258bc858dd65db6afca5959f1c92d37adfef3c	1	0	\\x000000010000000000800003998c3c28294ab2ec58a67c8e8fda9b2991594045ef01834900276b5e5e85769bf9b0a8fb035242bdba5288ce6b1b060e850d4858122b6f475040f516afe415857736bf9188d15c13c61e3c2119a22b957083cbfa1be54c2396857c1378dabb4f4cae397871cd0da83fa2c22dd0e95ef5a3baa134c620b06d3f504b64b3c74dc7010001	\\x3ed17707c01a890418985a8072e5e055ca16bccfed83151a47ab17ab82f4c7c9ff8c625bd0e96671e57915dbcac2bd813ea335ff1ddd66c96d8c798282bb5009	1649159553000000	1649764353000000	1712836353000000	1807444353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
346	\\x327faa4d614f3ad007a3cd3b99b0cb1b9c1ea5ca1d556032a135f7bde2fc690014a3ae6d69aed2a458fb0e0683c10a7ea81e48d02ebf50ddd43a5d25d28a2c09	1	0	\\x000000010000000000800003aeddd0fd619fa446b6e7c008c943ce0b960965bd91270b6a640f117c14009d6826b035f91bd4d98df386123df7c725f2ce9a7eefd8ec4cb808bcb72ea7885b9959396aa2cb4fa1cde3b8aea3e8e424cf66719eba162fc06940c874f0becf7d08da6b117628291a2ffa4c7d6d28ec45b6d1872386451883faa57d184dedf936af010001	\\x5ee9e5a9b771dcc4d47273dc18bacf52ee0a79e7a3ca34b592d64b39a27a79e1d8b20c2fceccf022555935e5215ec3f4106401d9fbcd3eff87793040d60a7f04	1651577553000000	1652182353000000	1715254353000000	1809862353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
347	\\x3343062c6364f6e8ebdfb628d61dfd06203a1612b9eba1b98ad4443bef9765ab936183273a8461da6f19d3442cdde383e7b68ca1abe613af96de8dd023a9e399	1	0	\\x000000010000000000800003dba21a3f61b0324c903ab800def2c5742ac7a461cc932ce0043cb483c181f13463e697d5fabdeaf838440d569429c9813f318242bf3e331fc1035583f6eedf33c9306de960a148c141acb21a8a6d1bf29adeba90608d222cf9a68f8d6606208ac27d064a7b26ee26c362aabb0f2713f3a89b2812009c4fda23231160068e574d010001	\\x4b6e8cddc6404e80e7a89c99910661ed3414d841ffd3f7a76f85c386bdc86e77a2f1ede1b3f8d272fb46b647240c03ae358520c31245eea33f941626ae42250d	1664876553000000	1665481353000000	1728553353000000	1823161353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x34a395196928974655b2a09eaecc5ed3faa450872cabd1d3e1fefb41ac15d5e356bc0d87beb74fb63bdf7e8761b99a4dce6939a1a24c454714fa16a2fbf76f1c	1	0	\\x000000010000000000800003b4728d32aa9172db6e85d99ab02ff72a9bdf7e36736508f4f0b13cc452da3b9ececbdb2aec13a80cd69f94746fde45e0930c136991995d15af1f1120879b417e246831e37155079cdd81ea5e1a4c6d751a3388e24d1a09e5856574691896d7a1e0fbb872550a9e07b7ce6307b936e41701b3c4a581d1f7fbda9712e6aa17afbd010001	\\x7b4ed667fc09a5ef758db18658da25a0b1fecec97a57a953855d4dd9bae2f0b55e43fdd87a6b746c241e403a1cb3b3aa2ca3d3ea28c45f951022460eea09780e	1662458553000000	1663063353000000	1726135353000000	1820743353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x34f7c8c7f1026fad60ecee3eefa0af26d4535e9b512c44beb016141abeef3c52814ede98bda10e741731b997b089a71f41e373e9b08330af2607a1653b525084	1	0	\\x000000010000000000800003ad9ad1bce6f55252714f877f5865c8afdf7e13846162878f5326277c75018b55692147198efc3a2a159a9f47be0a30db744f2de9727bc1535815c197f9b3c08e9551d9f438da994db94598a1f5567b46253f8714907842b92c1b100cb10a1bd5c89b4d2ee676dd916f882c08c712f54ec7a7bd31fbb0b51a12132ad6f3067ff7010001	\\x434842b36ea4045f61c77281c853dbedee9f5fe1cf726330109ce8399f5ebcd602c42825df1437a2cc9197d5dc446233e4c853c33a8ec0a4c19bab9e18b21409	1669712553000000	1670317353000000	1733389353000000	1827997353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
350	\\x35776e043a40d4aff1e1a4365e8942116be192f1c8b2db9d3b2640d2f30d761a59d708c39a705f0f6b5b7aa9ae2bf98445156bf3d1dd731bd36dc8153f026f51	1	0	\\x000000010000000000800003bf4740e98967cd89ce319762794ef9a29cffbcfa0d7b6623e2689982d5ddb0d5e7bb04ab3d7365155f6e4d54a757a6de54bd7d97780b6f5b433acf1d92606090294f36f72d66ed34e85d81f6fa95542c3cbb58f66e8e09a2e73d243263a76633afda547d16587f2882db1e57409271bbb035d4268813ad67452fa31b8886bb75010001	\\x3cd8ecf3ddbc3a8de220864592a0e72b00db61c2ea5ce4a7d0fc6f7735f4d1fe626b3c7e349130354fa75c4ed11b50024b46712a43aea63fe1d8662da08f7b04	1675153053000000	1675757853000000	1738829853000000	1833437853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
351	\\x3957990e0e7bb7686773416e563eaff445dd333a001dda5afe728bb73b86669f03d38fa94f95d4321a0ef500fe43383ec6a3a6ad0a3d21891461e0ab5f23d816	1	0	\\x000000010000000000800003bcb4746e51b644c2e21b5a5eab8eae8019393b5c0ec20af32b62a525bab3b0ddff75e16ebbad6707961106f1adc951adf25579cfd33fe37cbc467b54e845fa3d07b20da86cf13c2f803729672698b8058d2f0a3053e14a29b6eb10f6c6895b93ccb18f83b2b89dcf01aad09c14365a6a474d1cf41c28f6292eed3fe47f207ac1010001	\\xe0d5ce87ab8e698c6713c939d02eeb4c5a8823c89d5b911e283ec2dbdf2273a9ebfacc7c117d71d7af32047e24fcb74a050fb50c3e51830265238fadfa31ec0c	1649159553000000	1649764353000000	1712836353000000	1807444353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
352	\\x3a5feae2d9e533c861642eb0480c16ed8aa49a18dc64be1d65896ff24228b87b7aaf4b728ee48af79ce6ee58b10708137d316f43f226d08973cffc805ca0859c	1	0	\\x000000010000000000800003b8eb3df431577dbb544a6ea5d0239b2de56d824d2d980d5ddf6ef0f5a382416d1730f1be642f9595554395cf6abe2c4872d0a67f8144141b662fea2aafc1d2bc8d5bd74bf5faa6492c32ca2fd9f5e0f6bf4e4cb597a86d6bfbcabb24eea07111a18d58c28e0784860093a0ee59668f7863f214162c2975348baa891122a74b51010001	\\xec27f539024c4995408c8c00ff32e899f8acbcda3184c0f0f31d63c983233afd0e4915f156c7c8b4bd4b71cffdb931b52afd94f3b5953938774d08176c5ae50d	1663667553000000	1664272353000000	1727344353000000	1821952353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x3a2fc27e1d193f7f63506d9b7c76e573c7d69ecd4ec0dde117f330aada9373b488c4c5c516ce03a89f21aedb001239aabcf16ad8a98e673158baaa70fffa3115	1	0	\\x000000010000000000800003997b5058d9a62a4d8340c4087a3c2d0e70f459ba0c48ef55dcbed7d6a2f6009135dbcf72d9445524254ac0f09a4cfdc2bde3bf5642c7fff8c1bc050a085d77e0f37c1480597bee2991d889ddadd260fb841af91ca970034c950eed5495ecfaff1e9ff6d85887b24485bfa7f0baf5ed269583afd73808b9a5cf2ccdb15dba0365010001	\\xc02d188cd834cf6fd3023345bb5fc06f3952a1d242c697ca7eeeb6414b01befd93266e37c3e1ab234e2f23755ac89e794b3b195ed1eb82ee1e7dba4b8f52f601	1663667553000000	1664272353000000	1727344353000000	1821952353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
354	\\x4073e67f217880c18901b3675cb1b83fbb1bacb2c46f6d977be987df2e0c75e17e2aee014e0a768abc5862dd106bfdd614eb5c2ab4bf81dd4262b02e84d4c14c	1	0	\\x000000010000000000800003c863c5a01857ce1f5deda782689c767bb500859d76dda5571b243f3321a021167a68c30131847fa1387d226f660c1fdcd5d3f9a5d2bf4ca050b30829d8e5401fd477cb70d7810f67fcc0d2f828d9aa975e06c1c3897813e9b19836da902ff105f4d40abf0e8d6a59ab97b24ac9e4d03a1c4cb626cdc4ab14d359f37f2f6764ef010001	\\xe5f247b3a06a85d00d7b374563954f1dfa857c337f9000b7d18dd6fbc90407d0a07d141cba94c90cb51a3e1d5a65be1d57382a470ef3ea8f52a93e556ef2450c	1660645053000000	1661249853000000	1724321853000000	1818929853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
355	\\x40fb92546390b38d183f3e43ebc28f7923ea471ad2a83d637a4f645e6d8b6b1a60db94f4385fe1b81a3168457881005518f67b48618ade3f0194682e2316eb03	1	0	\\x000000010000000000800003d373c5136c5ad3cda5f8eb565e3fb93fd6fe6f14c2102a05d2639d4305a8b17d93688c47a128023858530ef69692075463c733296383e3f7f0a6d91068062ff71a6126de33e72898f5bc2c8def706c8424dc90ed1f7afd8aa20b9f9dc4680c1cc65bbf8ca792e71ffe5f2a90bec40b88734479653fac2989678c8edfb6ceb557010001	\\x2c76e052ebb2c5f66c090a091e2c7d1d3149cefa5a6c2b68c1c0e45170aae981574ed363d28d1c16be2db24e72daf510d2b9e4f4375f6aa9c4ea4dd7c7133f0b	1663667553000000	1664272353000000	1727344353000000	1821952353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x4547862766423451d07f5b412231b6f56dee131be3d4c575d3d764d05dc47c48cdd25930fff0ed476421caca826aade091d2d64cc9a71ec28ac4bd6543caf8d8	1	0	\\x000000010000000000800003b0e356afddc75eeb78a9627dd27f86e14571620abbbcc0881a5d5dc87fead41f7bc046871c096aa3841a9b08425e623cbc1e0120e96e6650c560883150d7800f1d196498b37a7abd3654ded3043e76b04c2150be5d389ac8b957dc38499baf8778b7d44dcb13e38917eae83bbcd8d8ca1b684cabe04b4ecf8476344258771cf1010001	\\x6a9ba3516b172ff68441b59a09ad4ffe6b2f0f7a22b7bcbd2a03b5ae213d1ff5a05a5f75a2c5a916c5f41062184343ce843918b810fd9b619cc2d2fa9a036d08	1675757553000000	1676362353000000	1739434353000000	1834042353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x469fd8b7f9d450262be95935d809277be82f0224becb7877a89892213818698528b6f86460ad81fc2760dfe631727edf5871d2b084a07adccc73a69144025fbd	1	0	\\x000000010000000000800003bad47470179c57dcef3ca25631fb6b1527c15016c23f6f9d4bc197627294d30a3a738712cd706e63728c7cc7f231b9b6a7c12a2fa6051294930258bcfbf7f8b181b91e1072eb9aba0973ee63830d6ae834fdf91aead1914f39ee9a653b1a5bc1c61a5984332515785a0d6ae790042dda574eb50f2b99907a27d6a648c6c6dfb3010001	\\xae4157604f3756736d858d0ebb1b0247d1d011923eb87d63737d6d38f3a96b46c1ad4bfebaa53afaa4c0ffba05f007c5a2d703ba66163bcaed46ff3889b24400	1660040553000000	1660645353000000	1723717353000000	1818325353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x4a0342cce5af3611d5769847fe7f082c92a60ecdfc878eaccf714106ecf1a74a958206df6a6f0ce0b226716bcb597424c8251dd92b498d6af8de7246ea1d18ba	1	0	\\x000000010000000000800003cd644962c4ae017d53b4e1bcb89720adc42292efc408789cc3433262636c5350a6f20841f83388a5141efe1da8b4f1f3a7633626f4c46dd90babccba668410aeba022d71106ec364a1c5c8989e8a7186815e470371c543bf0b902154f48e4593ccd30b9662873eadd52e1b6875c4a922870e011992c47973145c4adb92ce23ad010001	\\xc4f28a79ea8127d2afc63944c3fe192743dee8f144ed7fd92dd2818e733f0355eaab957dbceaa130691937234c384968a5a9e0de2cb28505d41869aea6f7660d	1667899053000000	1668503853000000	1731575853000000	1826183853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x4bdfbf2831b3b486d14c364ad4188f081531a2098c78738eb25b85535c4a05ba7ddaa51122146e94ba8ce954775f4b29450f91e801104a29f346d0089ebac75d	1	0	\\x000000010000000000800003b0eb64da0cb58a889bccd773e196b774a355391d9d7813a5d9928de593e570ce2c94f87a9b85f59280dd10607462cac42de3bce566cbc079602c6ae44fb4533685ddea41df2b7b9bf18f4d4b2d8ccf62f03289f4e6090c9a902baa18f9c14fa713a11c8cdf3f2a2b45309f81aba2affd40650fb8002019fbd882ddb1773f74f9010001	\\x58c1603d27f0a8497f8b1b11f4b04d62959212f895fedc8957d99c7b70cb958cbe8758f0f55f6dad7612e706514424c0238c717441fd5bc02b1ce6b6277b7002	1661854053000000	1662458853000000	1725530853000000	1820138853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
360	\\x4deb8b1cf6177da3c6962bc0747889728043cf41a70d5ec85c5d01ff788a1091deecaab81afb7f9e53b0b053f20954228f8eab9768bf1de16a91f19b25410bb9	1	0	\\x000000010000000000800003c7dc0626163a2425f9aa3ddf443ca0843b7ffe42bd5568c9b72b8eb0d52f16e34c343d82b53ae6b21406e7904827c1a4b5bbd84d08231db2824030bbb8cebc4caef01685e0089d64e7c6e720c31086669da9ee2deeb40594a323a41d50d692eaefd45ec526fa496e4858fab1c569c38d56ce461b41797c90ddc8fce87cd246a5010001	\\x905a83581b63b04bc5a5cda77c26a2ff5e7301ea36e2cb05d338f7af0948b37349a7ce78f505eabf467ab89c947a3534eb12d8e39550c1809952d1aa4d7dea05	1672130553000000	1672735353000000	1735807353000000	1830415353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
361	\\x506f9c7212528562178b805bb817b66b4d75bd38d5f85db4478386b4291af4f833f7316f5cb424504a01dbdd4145c0bc3d1621cb967f605bb349638b6a381295	1	0	\\x000000010000000000800003e9057d6880028354838eaf7cedcb171d40b14a0ef3a209bfc309f0262897e886a3ea104c70918b1c3a39b2e96cda92760387db120a1f9abe4baa8ff2f03a30b88a094810b79cf8d9e726ba76554e097682c2e411bc8b563c3076f7ed3afaa6729fa6317a0e62b896140ce887d98733ba3cce2273354892c3a3b05c57646c7d83010001	\\x25f67579dffc4559a85a83266cd721ddfe50960f0118ac787ae6cde82f7fb129b94fd4af19040db1c070edd0931ed8b2914730cf3672524ec469c1d10b773807	1654600053000000	1655204853000000	1718276853000000	1812884853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
362	\\x53bff930806846cdbf45c6ca4b84cd5ccfc0d6898e85815f766333d38ba246edf64a7922ef0fca364c2fb03ab3ab3c302c19e56705770890800e02c6fa01f48d	1	0	\\x000000010000000000800003a2e6e6cc5dbd803ad417641cc0c18b640a03dc9668717f84eea67ac31c3837515908f29ffcda01a47244ee7e8a87f61f7c6be0dd408754fda93301ea93eadc75442aab7d3ca3e16366c63c733c784710af5064ecebc33bb80be68bb7e70af1f46bcda745d444bf2eed572f3def9cba09faa6ace432a2b39b6b85ce74beb587e5010001	\\x0673560cf256d5da4dfc23648f351eaefa233b73656637f31eb497eedcbbdbaf6c99c53d81977092019cc81718712020c83e195c7bd6a47b25ef9b2c1f42f900	1660645053000000	1661249853000000	1724321853000000	1818929853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
363	\\x55838406df5b9a3c821e14ae8b951051a5412f571c6755b0147b3e6ea5f2a0567ad8c3a8647a981e97c4bb0cfe718b6ff86ffa6d18b28847fe94785341955f35	1	0	\\x000000010000000000800003b8c3fb52a9ed7bb8914250efdd1f84d6d6534dba8d3e23576968206b4f1b3f35039a7417e54b1ccd0c0dc5521c1a6e0ff0d6b96def547c348f3492760ed5a71b195a73a32f6bf1a3c26306e7b4e6279e86584024ad8410f25c62ce11e339dec60c4034796daa52e63c8236f6b33d0baaeccb747b78473055224fa7accc424daf010001	\\x85e104dae5624b2ac13f965226aa0c8ca5390c5fa57c6165d497bac35fcdf9f8ab9dfcf393f34cd7c475c8445508b9780dd6e33219f9e7218f53c1579b3f020f	1670317053000000	1670921853000000	1733993853000000	1828601853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
364	\\x5527cecfaa0e9ffab101fafeab926ee865c4901950edf7fb9c97351178f11af73ef7112f9719dc726a0ef8ae1def45cba4425317cb6169ef413a3369509486e3	1	0	\\x000000010000000000800003bd98e52bf0dbc712cbc98f9bb7d67d2ca1a7545590d8cbedb977c620fd38d47c195cb1e846a32f5d8ef50e3bf2e34c65ed264498a045c8d75c1b04cb7f15952c31c995af9041427071781c9ef0983c277c1cd1e755b022606e75f0c45290b9ff0171b853cda73fcacad98155c9278861b2853e525246824b7e368e7a272160b3010001	\\x823a1c10f8ac8284347e26c6dfdb99b8ca5578b3a7031207a2c0d356dd2e29d84c5bbe944af7166dbfcc7b058ba45f4d5898d697392e37d7d9a1e525cf728004	1675153053000000	1675757853000000	1738829853000000	1833437853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
365	\\x58bb577c263ba5233ba096ba94e62143e2f10ddd23371ea32ea9de8e4845c537fb64abe8f9de877d579a31afd61122434fd0f1c2bf1175a73910af468479cb8f	1	0	\\x000000010000000000800003c08f6be1f0e0648db91be0d93d6183fb339a2fa198ded115cba67faa71685c8c3d24cc3478f14c1507f9ac02d1f0f3d6d08637a63fe33861b70f00e737867cb7f8a373ff593289555200270cc4d5c151691c16482d768a4301051a5b812f84d9a535179c6b8ed4eacb98c063e69d86e8de1d4279783b190fad4eba63ddfe968b010001	\\x9997e75cbf87bdc9591c4bc366c0c76203308fedac381dd6cf0c0c63f163be1a3142862d765681a70859a8ee58bb23d604a5e9cb662d6b8c4b2f474817648f00	1656413553000000	1657018353000000	1720090353000000	1814698353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
366	\\x584fbfc921c8aa6f61c2869702a00ca19589e282c6855a76fed3c983042421d00da3d2c214703020639f4fb480bf6172200738ebfaeae468a5488c8e240e472c	1	0	\\x000000010000000000800003bd76468f933a9226e48710997a255766f32501ee1b2278fcaae6b76ba5322fa277cdb16c2fe773e7d9b70e0aaf46ad35aaa76b7de2f66d241f6f8ae9adf283cd9e958185b9b37a69707e25fd918e120daa888b7c29ffe354b4aa9171efc078f9b4c3220964d9624240a49e50d52f316c7bd0123f544d1da9b36e3ced84ea4e43010001	\\x7d900242ff0e5d2db0f82908bdb5aee0f01120942a9bfe04ace755278e90c68b97bc1b836c6dee7f4c428ef4e2f7c4953b0204a9cfd632e645d9fd67db643900	1654600053000000	1655204853000000	1718276853000000	1812884853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
367	\\x5eb74a8c4262ff60c686731cc8b4e94f533f763c1c17ea8f47976a7bcb9c065518540dfa975d5455c4aa4f36df517a1000f79e09cb3bdf1a9005313e1cb6d943	1	0	\\x000000010000000000800003b85855c2ddeaaa0182303d8bbaf889d3d92a3e959ed406c78d3d49e78a810d0c1321d4c47fcab9fa5866694baa3feee9e4265b2b6c3902e853fa1d8d0d3573bd1c583ee0248c784d2fe332d9625e38281ada431c103b21f1181d3707f6ee3b593a018a5265511e82c934983a78a1822482796b21959fb051e03e636201cba6f7010001	\\x14aed22ffb91b291e59d470c442fe0ad8d76bfdf3ed255425c43fdbeab7446ca55f940572d94728e46f71392b549f425d77f686aa4290b0a933434149c3d6804	1676362053000000	1676966853000000	1740038853000000	1834646853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
368	\\x5fffc2ca97e54b63f7c7d32f4f786d48af78911c206a2259844e45cbb5d3c63881bda0c42e8b2814bac3af15ffb9720e3976c213e6c28e2eb684cc9cc5f47749	1	0	\\x000000010000000000800003b6ce611a11c1db7ef73820313a042c7b8ee8a398788f6d5860ebe67eb51b65b6c5ef09e0929f88e20016ca1efb0fc3cc52f8fd7a89df631e34fe22652fcc327b9b41fb2c2b2a6729d22d4a32c93daa2449b3623d50c9a2b508f25bc8208b31d16796277eebcc72a8606c3754f872eeb15e4439c84fe2b57ef289fe9a47cb68e3010001	\\x5ff2b72648ea8d2278dd24951a54b880c35a49f152e82de39d12b8ce6ea241d136676b29ac7d250bbee0d307729c81d6c86394ee0c61b05ba8a18173434b6b0e	1667899053000000	1668503853000000	1731575853000000	1826183853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
369	\\x60bf852243a0a70bbcf1a3af7c927727586f16aef165f04cc1ea2b3eeef9440be09c8b1b3e491fe30e8ea9d4aad425b028c8f3831fcd4bf80cfbca533b4a072b	1	0	\\x000000010000000000800003c3fe82e59bde50ae5a7aec3a7e7d48f48d996baa93a29b8480ec6e25917b15201a52c8d7b1570c0a81252946b54ca3faa022bce8423c92d2e14234e27e6c1c2ec46b4a95d9d976da4babae9fd2a6fa8716137d3a9dcdecfe362e4067def9694d99754d0522146be303c3200ccfbb2f7e7aafa11ecdb40e8ff706701975eedc83010001	\\xf671d6591502420a1ee54a3e04d3286f446e93ee241a3181c01a01e5c2cd9e1fa848d2ae2a7d67271a5adf1e7c31e0713be3bcfcd6be1fd60177a14dbdff1402	1650368553000000	1650973353000000	1714045353000000	1808653353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
370	\\x600319149bac43424160f5bb7d48d716fb9a0e18ef3c7118c79503da5010b50a0fb508a6e18fd677ae31cc84bbc9dde6bfc4f582523b614e3f7b54e7d8ab19c0	1	0	\\x000000010000000000800003a4939935e9d77f75983935da73bf055bc3dde9bbb6ed4902926cf184963658de25ea69d44cb8d0ae223029a31063977277b55c63d75d6a63936d16e6ea29bfb75d72bb7c88d97571f3fbfba1a891a53b804a17409596c8a2eab446ba80ec770ed8025377ca9b728771f096646fe40dd91815cedfa2412a07fc7058f9f5e9c0a5010001	\\x5b36bc9d10eca22b28803b50696b1cc6c6e7f2aec4a1fc9a4860cd2152c6df4a2e44f738a0e7c021d1211c6b3a30f0b648077cd70b10dda8867e7b13a1d7460e	1672735053000000	1673339853000000	1736411853000000	1831019853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
371	\\x618f4eb9878df8ab158c917d05e2b70410c4a893c2794e02c0ec9ba7266c020dcd1d2f347ad719d7bd33812a1467f7be2d220b66a7eb0eef8b2626f56c08cf5d	1	0	\\x000000010000000000800003b7e20c4c71074e9c7d2c8cc3a66de2f8ef44377ba3b856d13124a3d5a4686baaa97c40e9f590ec62730430be014abf53d77a16fe0be96d0a754ab7da8bccb1a8a49e239c4efee5c75f5b73c382c096cf7306b4491bb5d808d189ece1a720327d312b275645bb5092ee7a98bd66202be113620ee0e1daacd3c2d0b5471c333bb9010001	\\x6b5c5a56f6575aa2435173d772ecba73711da323662f8a4aef8d94c2c01564e6410e127d261fe9fa48f08b20c0b2359b28b287292d8a1d3136db8a032e043506	1650368553000000	1650973353000000	1714045353000000	1808653353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
372	\\x63cf4f5d33b763fbb0832960d525bfd50668307742b70ec35dbb85bbc4c28e9cbb77fc55aca005df4881e48aa1e84656d4fa500d02d530a728b0020548d1243c	1	0	\\x000000010000000000800003d5733cc05c97b304e66456efcf8b51545da9cee8b6c4a6b1528835b505d0bc9f95adbbc67f58f9d65ade89fd9966c3b3ab17a1c7831f7325a4c2afe52d6690b5c876234d2cd65942d89765080b5e138d4614c5bec87a0792f931395240c6bc046be42fc13ea9cee203fe4ae0db2ab96cfe2eddbdabcc9648e4f62b999ec15fb7010001	\\x30311cd373a8c4ef27abe1ecb3c32bdfeb5c5057829cd736cbefedd7d7d453b42acbb5649fbd21ed779f5c1c3ff19dcb9d6839508020a157d96e3120f86ccd01	1653391053000000	1653995853000000	1717067853000000	1811675853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
373	\\x6667122caf32ea2b231d81c0e9ca3788f54670a7b174d32eb7e7595d0290e4fdacbe804c583f13fec3c1db24e67a356bd05962bdd4e5b5e8a834f71d948effb7	1	0	\\x000000010000000000800003bd816bbcd91975c480e62d264951bf0f762547e9a6b3359d44a315cf08f160f0b59f354ee1dff6e51dbab1b8a9abcc323ee4188e6e30934e5b9939f8bfb38b720bf79e2c89556455b48d469c165b56baadbd5ae05ba52311aeafb6eb70a68c7268f1ea96a9ecdead981b6634841b1078557ba32c58a4724451f9392a8f6842f7010001	\\x8b6021039fe4f9edc3c5534ac6fc154eaac6368e91bc1e050f8d1ef5a9b33491c03a137a346e385a2206033700d64bbe9746de5dc559294b4d0e0be30e36b600	1664272053000000	1664876853000000	1727948853000000	1822556853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x686f3ba8f0aecada2c5cc9082e8eec8fdb52f12c288cf059c8729a356cdff9050517e4a0ac3d81c9de3502d7ab9ca45c60b8aacff6a57be40f7c9ea284f07261	1	0	\\x000000010000000000800003aa7f3264286f1077c3a278f7d18fac2ad5b0bed2a436ff88d92277a763e96a241bfb1b9676bb8f13400f19fffc1f85bb84aece51127bacfaae22dfbfdcab89e88d3a2885c187352bc52aada857426251ba6623d8612c3ec766d4ecf91a98b181843cef803e1d761c68a1226b4fa6aef976dc0498d3a7ac917e88503508b924d1010001	\\xc508915ad151502e93bd5daca095ad571b6c9019467782f24a7ffd505a34f2f34a8fef8a494f211f03c6982c213279da01dafb395f2802544a2896b227b61c0c	1677571053000000	1678175853000000	1741247853000000	1835855853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
375	\\x6943e791f90c797a06b943420c341e5bba891baef444f154f11550fe31f6598de7844df76a1e8637c8600465586ca8203a87c8ae1e4cafa141cfd1db45b1719d	1	0	\\x000000010000000000800003bb605b40f2a95e2c4ff90f2577001b6b14e860a52f2d8a2464066631b1d2bb339148cfc120ec04d7cebc8f4f3ff4954cad5c5e2d9562bc6aab41a614000fa14664b7158ab3b9342d5edb8a36fff29af62afb1aa211ea1ac37df6e88ee40059b1cb8e3d5ff6c5a9cbe66faedf0764eb4f415acc9c1a49ac438224fff5100517cd010001	\\xe8eab6c80b28a82ff9fa4e08e5308031e9cf5fbba6c1285efb0397c514ac0516a5c5abfa354d34db47b0b5995600a12cb62807ea9da833c82bbd9ae10ceeea02	1666690053000000	1667294853000000	1730366853000000	1824974853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x6a4fc4d28c1ec76735fc41c50c6b55274d24daf5215a43d6ae389f15d51b6466f3123b09cdb4fafa008d82b22452e7f33c3278df611dfcc9c12d8d8181c3d6f5	1	0	\\x000000010000000000800003abebfedd73ba9f00ffcce1ca54ecbc5dd9de45cb276a8e0e7cca3310c49136b3bf366793664bdc955e5adf647c91e395f61ec998e4eab9e520240ae2b72d134cb1eb6046bb2a2a01845a744484c84fa49bd2325085dead9f14a0c818ad909f5c3948808ad57f7d769bb12a4b672314bb2c394e434609729f0655580254b43137010001	\\x39b6ff407bda90a36f833cc154ee2ce707aaf8c496b411777b37a4f0d98daaeb2fef77177c0a4779c29638cb6ce5d58e2262db14c067770df6049679dd940b03	1658227053000000	1658831853000000	1721903853000000	1816511853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x6c7f1a6398a6623ab3d4dd250d0f8cf5cf9df5103f9fc3f312f342a0cf9feabbbd1d3d76539e805ccdc730ce25fbb16c0da6ced090ffb83101a4c70bb33280d5	1	0	\\x000000010000000000800003d1d9557d00cbb7afdbc716be464b2446f69dd0e62c4ca1b3f9f669fde4f5bbf6294ef8ccc206a9ccac9eed82b38517a23ac30a809142ce9fafbb68e0fe4700fb5696b8bf91652660b9e4cd394abf9fa2a98294af1e7c41ef3750a88bcd92b55b4243a15975cc40b5f7cadecef0f17f095c0cc5eb00815c564847fab85d00801f010001	\\x338404ad17600cfbf64856f5a0b27014c248e35222a319a3682c5dc2211b8cfe416c85deb6b00faa488be5429dec88f4c7a539986dd50aaacda55924ad27ee0a	1674548553000000	1675153353000000	1738225353000000	1832833353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
378	\\x6db7fbc759dc24b45c2d44a6fd3b48f929ef419ec71dee4b6844f5b3e6f1141150b447a2dfae35e86fe4c4234942fdbaec1a2107d2c6e73b58ee71cc3e25dd91	1	0	\\x000000010000000000800003df82d23f9337a821de5544b99619ba3753e91cdd5939aea18cc08772b21c6a26498014507856dbbd1a75ff1b7ddeaae6e82b18b8f1a19b51cd6eac30ca6dd77adead68e66a6d273bb14c5a68baa49d8569a6fa0e25a523f7fb170a52bc97593f2f3dd95a59af57330d254827f4b2b664385291d80102b7ffbe08f3b8d1e2d141010001	\\xf755eedad9df6bf0c4e34c23bb989054ca4b41652f45e9b8ef0007bbc40f16cf5da85df47f1604cd97a66e247463a2f38b787b035c6d3d5468de912e48467c00	1678780053000000	1679384853000000	1742456853000000	1837064853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
379	\\x717f2e0e77101c6891c433f931caafbdb425c89b78338d97d6eeacaec3de29e34171e04c9b3897c5d0559c983a2b840f6d45597459fc0a5bfc0f3835295ceadd	1	0	\\x000000010000000000800003af797c643b65db44e8eb271f2bc67b903a2f7e04f8da5e1267d2959ec5a876af75f8ea6d109e57fff41394da06fbb992b346720b0619be98cba4deb4ca4c6611ae9b6843c09a4ecf9852d803fa1c6dd719bdf5e379df1ccf4124133df7bc04d38157e82e08bcf032c2f58b604713730490ec45ec227ffbbceecf7cf504615b3b010001	\\xe9ae7e5dc25be55afd7548d07ce2f145aaded70613df920094501aa1901814295499dee154cb09092639bd8bb57064df8276324b2d0af27b18c1d8116e80e00b	1659436053000000	1660040853000000	1723112853000000	1817720853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
380	\\x73836fd84aab0ca79b8a00ddecdf38e11dac77c41dc47827a9ac9d8e080dace829a49cb8044500dcdec0a85952a005f49387fd358dbda0d8cc716399b4f19345	1	0	\\x000000010000000000800003ac842e915208c9e885d9710ea0ff3bf77de75d95a87934f6fb9c4d14da823834e59324bb9d1b41e1f17ed348b8ef6bf6de6d0457fdfc230da978eab5e2c7b0fbfba817b0fdf5e675bfae25236c582d273cfaa733b0d254f0a52472bf5fa3db3a4585e9a463fbb7e6ddff370fcbf9bd111dbeafa0ba87e8cbc403c7ed78f7258f010001	\\xec9c08a7fa95fa5d9689a0d2ce9e894ed8901d7180e9cb74b15d9f6f74807cf91f90f090338b200a21d4f1d378c1fc5ea3d51c44506f596374e200f52707aa0a	1661249553000000	1661854353000000	1724926353000000	1819534353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
381	\\x7973e5e7e6472c69a1100a5e7161b2a9dab45c817e7c94ce529768a1107f6f8c40e68855f5a82df41c8bef4db592ba8c69e584e2afacb779226c60c6ebe89826	1	0	\\x000000010000000000800003b54bf2a8311eb1255605551f42e6257389ad6c8add36f59278d59183bc7c219a826d55d5bad52bd3f602728723f6a98cccc1e64b67b21a62afa39767f4d565c79f2b66a45b05af055d136a8777f14a4dcf189b3b76a7e6cd6a093444bb3b881f225b8f62944098ee73106a723ddf87e64581f3b1b2726634209dbb9b4e7e9055010001	\\xaa7d0cbc917ce3afd042a3577a69d21de66d25eb5aad7cb66d40480e922d0fbb47c8698ecdd68a4d265dc683d05ca1311e20ec17a2a1a432f57bbb0bbd773a0c	1653995553000000	1654600353000000	1717672353000000	1812280353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
382	\\x7ce3e8a4063fad7bf54483a3773cad86dfad6510504ef06703797d7cdc67e194991264c4d9c2a8694c6a05eb5084e266c94dfc0bfb212850c27013236b418e23	1	0	\\x000000010000000000800003b3d911daa6ec024b7d53e20d61a46c7b33f3abf6c8d3dd9fd20cf5cafab87a2f477fc937a281f026cd87a3d9597128db4fb0793c3a603f0772036691e8a0c1ca685690944bdfc9823be83e73c3e1146272383087bdeacf0cec3459880e26f4cb15301fcd2e925bf1a8b01f8a87961be5e2df2790c5e01b9e3d7366531f83d88d010001	\\x530d6a336cda797513f8eb98223a46702c6cda92b44575bb487b6fcd394c627a85d76df7e1c370f29d457b80c0392d51d646ea665027a17ef494414d7f717c03	1651577553000000	1652182353000000	1715254353000000	1809862353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
383	\\x7d0756a557b371c1187925d38900b886465c32efaeede8bf67bcc67189077eb00cffea100ebfea4c1370570f43403be359fd4a15eb14ccfeb86f63f262c87009	1	0	\\x000000010000000000800003cb0bbe63773af8e5265753acff9bc7df55746372317e379f155379cbfa494c264503033a1561adea51d458f62ed51eb98e2fb583a17e09df2527c42ffdbfdb84dc7b8256fb353bdab3371b6604bb6f4f92df63b507b40f3f2ae0db5d45c7a236148178b5412259885572bf4d44f9abb19f7f9ee6dac4a3b4eef567c7f2fb4c0b010001	\\x78868462120d63583765bcaa7579532e906944e631be94e197ca60386d446db3c3278386962e311ad1a776fdf2ed3fedc7caf41c721e0134a711422837d85e08	1652786553000000	1653391353000000	1716463353000000	1811071353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
384	\\x7ef7fcc78d9869e4990bd72297a0ff9618ccabdbc715bed7c41d36c0c4b3755e34b025c09ed2e4b49523f149162d2de6609a8784c23b55e470010b0e2a27af9f	1	0	\\x000000010000000000800003ac21ca8a729e4062cbae47efeb468f7f44cb48685ccb8e6b6da25a0269c56595d02cf94dcb1438aa97d3fbc04f7dd959e4aceceb786314d97007a49e0b39524313396846d2f55b1fe852d4b199045b85b723fea10fa8b0a5c11466e347c7f5b51c75a85b348d2b3fb4c1376a2e29f6eb068c60a4d644a4a9e03fc8a436663b69010001	\\xe200e7fa51bc15ec908b698f2d05c28c3f380c308aeb6415d5a656713ded0ee7cbdbab9a19ff0eba355764a3da80f027f84ae9eebd1aee9675f8063f09ca810f	1670921553000000	1671526353000000	1734598353000000	1829206353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\x7f87cdf1145bea220b546cfb2cf2fe45ceddfe4a5483d19a7ca604164e0c903308c20628c52c218ed06d2793db0670c49cf776ffd55125c088f9408cd0d1ec5a	1	0	\\x0000000100000000008000039a8bf65fc3ffebc7908b04b6507c17aca9daeb9266889a3fab1b4ecd4674eb236a3375a3e6f9363b14a84430feb4ab696bf03ec422c7364be5cf131984c5693c008606f320f10cae1791935d5e7623eba186338ab5302bc86c2fb5b887c710915b798f58d833c4d8ed3c4f959df83a3841bdd467a30de4b0efded20ef7257d7f010001	\\xdb52cff8776df4f6238c796d7a07223c838ae1c85e88ad4b2369e6047af0b9eb7b0cdd385b79bed0d2c8c53d606558d1f6833dea68b697620d96b8f5337a0c0e	1673339553000000	1673944353000000	1737016353000000	1831624353000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\x7fc38204c556bf0168d04b3ebde27df153a12083a400881f733fa919ce7b96bb8d33fc331772852a32e74d835c42d31167f35e1cef8f0c16102be8f869af793a	1	0	\\x000000010000000000800003a001e62a18dd60b529bfa24bd2b469c00fe9a29288b059321bac01981434404f405e962ca3f6fdf72f8fda0d18dfb1fe1ddb5ac20fba8f94d011a5d8c10443d7d35a8e7d305688600e62215cabd24d6363082828c0844dd54ca93e6ae7fe905db808f77059b3fc493712a5f9eee173dc9be6bf8a80614e5fe4c8ffe1211b6cdf010001	\\x0dd48e7b7eba04a6cadf489a8f99ea6c5be230f111a6d367c909b6c54887568251bed3cfd1859569eae59e00f0ae3a8ef899fb1546d53455f863413a2880500d	1672735053000000	1673339853000000	1736411853000000	1831019853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\x89372ed4f1e341b6557d24c2650593e42c55c27aa21222f932a21dd4020b61795c7ba9e77153210571ebc88de5d65e333932006fb52d319fe547a8eb501a8945	1	0	\\x000000010000000000800003be75239167dc205af785162f8b66f63e7e174f47fe4cd7de75116598c63a20376b53075b665704237b097b18663de7365b94bbff6fce5c3a2f4a0264631e1957e5fce84d114c60abd8612ae2ac1dc9526932e134d035dfb1b0f2b3be6960bfbe3e5c58e5cf9a3ef3c4a94042b56331b6573d810be8f5ae33fc70750a2460b30f010001	\\x7f6db439691e04b82a0929a20483cccf792205448ba55fd0ff6f4ead225a5f5bf24c4a296f5c5890993d9c9012a954b4dcc9198baae52d19f5f285dbd0d8df05	1649764053000000	1650368853000000	1713440853000000	1808048853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
388	\\x8ae369de72aebab5f315b7593e2af7ba7f107e5f1138a8a6089259871bf4043c599f6bb3aea440c1af0cea1598ec57c2ecc7e00e2434abae29800b3fafb009cd	1	0	\\x000000010000000000800003d96a3226fd2927b67abeab8e5316ff98ef3a6474903e5949debe419f1df57cf3d28b389296a6f7db0807ebd5a0cf7cf1111b7eb40310d781684ce246310cdf540d5f5b3a4b2a7f81e65ef1c1511b0314ded72d8cfa8901576d3600cd90eefa78a55bc1d875ff273554a69d352ada69063165724f79227cc20ca5ea9024ee671f010001	\\xb34eb0a75094814b225e9ca43957f3cdefa55a085f0b10f5d5eeaa9665ae3656c4cd6e414dbe8a028094e18e11aded0784742a209212304c68a48cac24b45b09	1659436053000000	1660040853000000	1723112853000000	1817720853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\x8c5b8752f2c53daf4b5c60e715332f256df752643fac464d4e6bb59d2907c0a6318a9928668e86759b5d8a038b3106891d5f309fb37b6bb1ec597c478a51d374	1	0	\\x000000010000000000800003d9ef3aef5a6004015d532690ea771c2e8d17ed8c6a2fa1eb592871e2a5f14b86c812f82db610be4882c546fab4802ffffcd25c095474120e77130f877d99ba71c0d8691c76b96b61ec6c28ccf5ac444eb9314d30909c2b36a321c29b7093525c7c5949d0e86bfc3c86e475aa41fcb764b522cee2cd2b87b3da7f243d41b3cfe5010001	\\x8ff71dedce4fff2bd5968bfb1cefdc7a18e70af61c478763c4f37b75a33e57b5aaa764df3e99ca9a65c3c30eeb29b1dbfb516b21cd991fb85e189c2a17813302	1654600053000000	1655204853000000	1718276853000000	1812884853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\x8ed7f838006bad683f5ba7a4fff09f1e6b2f503c8c4ef34abf8cecd1cdb860dbe5ce8ec7c7c4ddf77d92d01a29ea277f31933f1c8906258dc37847d0109b4b0a	1	0	\\x000000010000000000800003b955fcf0f47fae0652871ed14a1c1431b99b0f6e49d64896b11445f880ea9aac67b5a1dee368fe015e21ac76bdb794b69725ccbd7f2b7870bee4aa5ee8dc0bd5910a396d1461328d2ff72af4bce5f330cf8ce71856454f3e2532fbe2fa48ef7f770dcffad2ba2403a155bb1992ace2f364501cf828b6267558565b7463d360d3010001	\\x84040fec41e3cb72cc065483af3014c89d7a1e22dfb38b8f3f2931a355a6e2fc4c51af5d7276fcb640ca4292f070a5df7b978890e6f762d6622ad636bce6e903	1678780053000000	1679384853000000	1742456853000000	1837064853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
391	\\x8e6ff38132ef982e1c1f7570d68ae4d02f4155c881db430489fc79bc30805063d0c55733e1f1782129666d684bb97c655d1ebf8b0c4131da94256ef3697535e0	1	0	\\x000000010000000000800003ca63f6ffb3a724225562f558ef366bf1916cab738f17835e2fb5abe0eec897655d38adba86ffb60d69bf51006a0cab2afb210d915672cd45110485e96eb455082107e047630155051ef2bed0646878ff0a7fbd6296ccc12cd598a3ddd81797f8bc6bd4f9322c94709c34509b298666f3b3b364f44b07d2403bf6c1f4742ef8cb010001	\\x9b0a5b91151c749a9917958ec72383fd7ccdcd961e4e057d1136f29a4ef2456bc8ec12f9254702d3597fc5514a058978774f28b81a002eb745d0b5f789acca09	1653391053000000	1653995853000000	1717067853000000	1811675853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
392	\\x916f230bafbc894a49f810d97dd81c5ad01e7a3a1081d09130963b6a07152e694a742cc439735001f71476ab3a3669d77b7841a9668d7dda0bea81ce76085058	1	0	\\x000000010000000000800003c504b6169f5eab1797282d9a2d05d112b5c6236a34601f2d14eeab41257d322a317b5f34c8218e9b7869ba1413a39ad4afc7067f11baac79f0f8fe78fb78b0ff5c5589c802607c7e76fe15c83290a67336656db4ffb2c2c122125545da46823e96bf4e760b1fa162ddd975bfc32d2af8fd0f7619e9a31bc973dfb8dd73b76617010001	\\x742670d5e74e42f05777ba2670efced22fe702e996fa5415c71a2e70bec6331376d850599922946a94c5148a3b58f69d719cefb8beffca91d376390ca736bc09	1668503553000000	1669108353000000	1732180353000000	1826788353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
393	\\x9627eafaff082e2886e8516b6dc6e1da26866e8baa9e61cf6d0782ab2475b865be1486b555edd80dce46facb42f543f90146e8b532b36711835924b86b93fcbe	1	0	\\x000000010000000000800003cc36764e149c8994af273307b6457a60a27eb71aeac4c6b3465f5a2dd9ec6a98305382520c30e1eb436c962d741336df747a21ddd59ebeaed11986ee23daad6862d550ace3715868bbf43e757c6f8df8a7d79241fd619b190f40fd02c7479dfe66dd96183c8cd5b56439cc9565c1d4fee28bd49ebb570946b4ffe8f6eccb7073010001	\\x2d93a51a91ae008c9dd4f67576ec1dcc863e713c578444b6cac36fd648ebb23b73bf1a0aaee85bfdaa1bc09f32f191033017c6a0aa7dbc1b82b1ede117272108	1668503553000000	1669108353000000	1732180353000000	1826788353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
394	\\x9b2f05c103a6c985aead75a4f0d45ef249e09f901d94fa562b3fafd5900bf9639c2c1f29e6767c1bae4a08cddca2312a1c04a836efd8e913062bd762c0b902de	1	0	\\x000000010000000000800003db3ed0fbc68d8813a454e42c90e0a01545cabd9abeae4b3ba02eb6e51c86cec217f55612dbb655f1c2319b65e00c78a14c1b9d49055c83421d5ba44bbcec80e037d9a2a92c4b08bb2e05d00e48a2a8555b67cca3349900480535ebd4b854ef281ec1c9e2b5ead28446f4c59f376ae9ab616ed40b8092630ff87a2ad8fdb1f029010001	\\x5be84cb8ccf03bbabb43cfba69dc7eaca60526a94d036a9901e4b73984bbbd56ae73ac5da27bd00823169eb0d387bde35c942804d506ddee054d2c71ae652c03	1663063053000000	1663667853000000	1726739853000000	1821347853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
395	\\x9c1f58027a5229501b6166e6f232f2e3cabbca95847231934731786d65f319ca4ebc4467c8c7c7b2de0bc7444980fa802307d4916d34745b7e0b6a40ae2916cb	1	0	\\x000000010000000000800003c11daf3bfb0271ffbdd3b70355c9e0ff25ccf7ec7417f1dd60d467476443e26c996263b54538aa8b6136ecc824a0d2814719f1bfae439e6f43e9dc0de2941ba8f45db3d8202a6130add59d7a760109889316066ce84caa77a123d9a811fbc728a9b82a6e91c8363504e73271e669d7e898d34e002b75e7ccab2dec74fa37d29b010001	\\x8c9ad6cc55a7398c74bda73109068195ecf8b1f8272bc4e05cd81a0db1e1e97d8579918122a5a4f029c0e5012474eab6681a4625bfa4ec5b4667222fff20c607	1661854053000000	1662458853000000	1725530853000000	1820138853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\x9f4fb986b7d1443b945767ba4b8a328fea8dfdc07bd2d8df02999948badfc0575744ce7f83676dda41889ba4f0692e55f6d6f792c6074352e2158a3a7ca26c70	1	0	\\x000000010000000000800003b4cc3ceff72f117176928882e013acaef559a56e8d613fd8388af61537fa7508a57e0e7dc63f33c95f5672324804a24cee14a72525edd3dcef772b9a7a6231f194108eafdbf6b887125109011fb02cf4cf2836b3ce138d5a95abbfe2be352f8630d9ad990d42b0887f9cd0a41e2cda3b82c44cb8d0adf95bfd0ed665865a453d010001	\\x8f896221501b6bd768ba086461130c84fc20fdbd9423d9923fd2c4a15b56d62e3fcb8f75e9c46b04a923b5739e3f587e51105ead6be1864a22ac9a38ea495401	1669712553000000	1670317353000000	1733389353000000	1827997353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xa36fe12d6608bc594057265ba6de4f311d41468837dd4213aeaa0f80dc4a9ab5930d5f9be0d09190397cc2739e348988f79152d3735e14758dd8f3ce3fd80ec9	1	0	\\x000000010000000000800003a99b0711b9f15ef84e1012981b34f70fbaf17784e6c0e1986599e13d8a09bd480a124203ca2e651c686158d68744d34df6e06e77ea99674c29ae4135aec30f02d4e5808e23b90d8f419c559c36afddc21b3c0a308936750c6c0301617e4ed76460dfdcb790c3d251f841dca24fac779638fefc50a22d391d6f16fc922919ce27010001	\\x7a8c239b0033910645b9805bc4766ba260d76b4169308fdacdbace9074407c98b5d72f46207b862f1e1a10bb4b2ff318611b1d383b684229a3cf60b8ea9c5905	1658831553000000	1659436353000000	1722508353000000	1817116353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xa55bc24112b2e0bc0da3003b18faa64e6a908c12c43f5836fcc41f06bb29ad16c0a45925f1f48741e142562ed6fb333da27a15de38c617e4bf172dc5056bb6bf	1	0	\\x000000010000000000800003ab4aa2ac7a6276da022503440d7988e3396332641f7a4bf645be9067600db91dd588d38fbb6787cb51cd4732fa6194989a8f59ce5292e21f0238da6ad87612077903e6a6bc927bc41467531690e350083aefc7b3647243a222ca3301796622d46c825eaa224cab52a035ea4df74e5cb1d757e6294c7a3cccc862ed6737cc21b5010001	\\x61ca905510eebf58e601d14b1821ece758c43cc8f88efc5de6ce8dc955c7a853aa2827c19f8746cdac0b3e0fd0ebf5e675da45cb08b0ab11e3414c781b749504	1668503553000000	1669108353000000	1732180353000000	1826788353000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
399	\\xa5476f73329723cacbf64855540dd3b143c5652110e25bf2fb0ec4006f4b883dfaea3db900308b0658c49c945baeec14bcce5173c480453455cf66d4227422f6	1	0	\\x000000010000000000800003e207755cc1fea8c271c4eb328764bdc59c9039d4e3c603e962ad80ae2e06e29ec70608ab82b66ccfacaaa5ab6c2dd817bd33dc52e458d91c21cb3d902f70fc0ea17200a78046e26e23cf22323fb535bb61ea94d652d06dbd42df51eaf9e24591d97340903d7686eb6dceb503b67ae9440c8e45bdc4d876da19e3c654933dbd6f010001	\\x179f7ced09b7e93f25001356411521356fc9360489946c4fe14127a35f591d9d8f03e57ae03614d04aa1d0a9e226680662cf94062c38c597ba72537f2c1a3a03	1670317053000000	1670921853000000	1733993853000000	1828601853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
400	\\xae87cd0df053e86e785f1179ab2d153dfe4a49761c47882908d08dc7b486478019566b8c8f87f430e2c24ed4c119f3af1ef8be283f6359bb04b48170886991ab	1	0	\\x000000010000000000800003ce7828f5107a624da833ce220119b8a263af50f345224e5a315813f45372e5202c78f34d78bb032571d5784bb753a4503cfac0190ce0b66acfe4fd652dcda771bb14b705d9e428d56332a036b83010f768bf0af74151317cfb5240d8e01bd7a5a67b8e190c75d21c75f4e8629a975b7a6aa7df1f7e05c546f4a64bb54bd99625010001	\\x04407b5b89497f3204cc2adddf825520f8bfd402354d01e75ec3514b0bf8587029dc10a9d17e800bf946e491c2d30cc5a63fb429741749962dac3b017817040e	1660040553000000	1660645353000000	1723717353000000	1818325353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
401	\\xbfc3f5e051267a968795a96043ab161185375c55e3a9672bfb6d2f27dc86b41401acd938fee561c504741606f691d333b0a3114f695a04538232783e0c54c706	1	0	\\x000000010000000000800003d6f6defe77779afcf7abad5018995d7d1ff3682a79accb337c2944519d77d4087b17719717e98b89f8e24aec7ca60943c07cecfc01aa46fd9f668a6a89832142cd6f88b769cc8387cfc23f2787be2b8dfc1d5c22a21f339519fe11ac3ee9c10b14cffa24269329afea7d8e8111eb666d46599fa3c88c4cb8f12608a8cdfd15e1010001	\\xbc708da8b62161f538e4244f5d520947de9a889b138e2811590a97e764eff7221cd32de3bdccbb5f5966e8336f7cc84731b4de58f2bbeb72f14aec8e13e9cc06	1647950553000000	1648555353000000	1711627353000000	1806235353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
402	\\xc087c84de8b375032b9fef51b4d6c5c62decae618f5799061e8021967a7b97e83a2197f532965a006d384de32d2a160646e4f9decde76d9a06ec1cb4cb57d469	1	0	\\x000000010000000000800003caf0af7931d461fc9142f72e4b68adef45aa70d1a33f35ac4d3281250c5ee22877a2766ba1f60d9fbc983f4c38c3b7dc6c252ea329ba114159dc2d76ba0aafd9090cc7768b3392b799be6cdc4857a710787246c1d3a8edec0e23a869c4482ca375d354a57ef6ed225512680212e0ab4e0e8dc7e90437c38dbe5cad96eca3034f010001	\\xf13cdc5197925133dc798208d52a997d9e074a6dcfd698e4965b787e873a14d71145fb8e053ba8a88b8d601666d46f8b6235f89ed291416448728878ac87c703	1673944053000000	1674548853000000	1737620853000000	1832228853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
403	\\xc85723e7765c8bdb406a8449e4664d7cca9c9e3e9d7c1936abc79d8a861943ffe1eedc7d79f85f90c2c54b272c34e6653a4271009d7c27c71f4f6cabe890ce48	1	0	\\x000000010000000000800003e0f12ea1885a1a82431e1f83acf31dea35997088573891efff6542836a565e221103873b540a12ada988b0d0e70c6d3746b27730d6b74d68c9c68fc355d0c7008c0751315420c49428a63be7a173b628ffc7bfdee092d2aa88fdc8f4ee2aaec2084a4fe2c51cf50861859b7a5fd8208ee49b4442a0e4ba85b1b83658547b235f010001	\\x77191f3bf6627cffd43ba74b7e57ad2fc82caf515a9d637a0a58221621bbe2a5c4fbef7aecd2af6f93a7324f44365fc2a157067799f5cd623ac99745a7bd780d	1658227053000000	1658831853000000	1721903853000000	1816511853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
404	\\xcb9755faea8b8cf7f8de4a0303552797d64bcec7fe711822104589a4a6c5b6d4c88e135ee7bbab12d2b42a251779558eb336f8e7b4ddfedbe0b9fd6f14827099	1	0	\\x000000010000000000800003bf2fc4bafeec2b9c6283244dff3db3fcafebd87d8e528953200ffdc8c67c12f1b5443207f3b1048e62186b2e54d7c62c45365566366ca34b75d0d48ef4caaca9743ee9b31e95b491c36cf1f30f4e440951f05cfdfead1b0950fc0a3807b7c4378d3c916ad54fb39902600ce0a4a1b148667ff4e523636f39c2c5dd745dc2188f010001	\\xbf8ec07fb5b58bf5e1d9eacef8504dde46790eb1b0f43f3b580461b7e86b0339550258e59b03a968fd01ef679d89d2054a4f06fe2f92d891dbb0743d1e502b04	1661249553000000	1661854353000000	1724926353000000	1819534353000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
405	\\xccd362e39e67a097b76427c68b3f316efd2a928cd76bfa82c81adb2703babd4e8b5122fcadcc6ed75d1cba592098f671add4a1bb6a39d00c06552c52c7bf1346	1	0	\\x000000010000000000800003d385a7ff4dca4b25c8aac39afa0c0d3708384592b18cb3c1904bb279cf9cd12d81e0acbc1dfeb0f7089ae2ff69d0433d83fc5fb07a286bd11aa9500e6ec80ce854a32cb5524fdb20123c5510afa33f7e22b0bf29562d27c8d0bc1fd5e1295a5004329fa758d851dc85074aab56f713d7a5f4feddb1433aaeaedc1a5979c126eb010001	\\xe59ed37d98fce313f8729f307f1544989ab190b13b9bf94247a2c7753cd437f2a435075356d87926fa91fa660fac17ba4404968da883b58d55c52a10d3351c05	1664876553000000	1665481353000000	1728553353000000	1823161353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
406	\\xce1ff7937c476c4462c8b88dca532db5442c342f0e780ec47eac2e68a303d0590e7ae0486a7199db915f2f9ebf154525b7d5c16a5c8dbf021f6a861881e01141	1	0	\\x000000010000000000800003ce1f1b4a19eb417eb18d0df1524e8b6ea37d13bd45d7e75feece9964870078f77081d6fee8c9cdb9d7e01f2bd9dc7a6f472624b458bfc4a844554eadf11d8e5d4487519ac779e7315da3b73f0ded538e2d807c434265b0c2ae181d2f41dd9b232735cf4edc59c869f22e9ba62acc285322722b3c9605a466411556e052035d6f010001	\\xe4aff9661ec898de1a38769b9f1606a5b5f37d62e3719a4e08ee134fc6e44424b647cc5fa6e6ee329333cf187e4607ec36cd8ff3202fb93c0282b80f27625900	1657018053000000	1657622853000000	1720694853000000	1815302853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
407	\\xce6fdd880eef13b51fac7bf6d302d1f5d4a15b934ad65ea22aa6099bfe718b8fdc91d6b7fd80e1b274cba05b9833810d5773ca10a9c01040e5570f4d3c789fc8	1	0	\\x000000010000000000800003a88e819943cae3fc6c900771bdb3969e6360be7a5908f00c72834c5bd45283ba602e0dd1509854ef54640dad9344c48c44208567388d5518374daa70015f38248cc1c71e85884617f5e94b0ff3d933d2b1126296d6e1fba1c8a49dfee0b140f8ab49c416f669b3d753ebf907dc99b8fd8a218d25467df392f6003e7631b27367010001	\\x8ebd3ad4c1fc9f00302a15f609f241e02b936e621eaf0b4d83db0071a999a1ee232568994b37200401c5d95131af8e8000f4e176f9dc1e7ab65d56f656224b01	1659436053000000	1660040853000000	1723112853000000	1817720853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
408	\\xcfd391c9060b68ae700bdc3e44d269058b453be7e241d3f20792b7a273dc8060436a632f29193d253cf275279016eab49622eb5471630c597aa0db87f7166f27	1	0	\\x000000010000000000800003e1bfbfa12ddd87f761eddf39a25808fad2cc50e131b30fdbff208e7e21469ea62eb85d31d1d932aad5aaa642b87d92c32d5e5c2984a28466ac8fd1517385b0f3d76f540bcc671cf2b4fe7f26fcdb0eb626121bf948b7c6d6adf5477b576b267aa313705f5963f5f599db516c3ae67b5354c5abb3966e9431a8fb2a618cfe2fe1010001	\\x08dc94977d76976e87e1b0fec979d69dc02fe52cce124ac590a80832f2b0b3278aa5d40071c89a608f8bcb3a88fd5a48d600d7b3a607a4d8530bf3b2fde57b06	1666690053000000	1667294853000000	1730366853000000	1824974853000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
409	\\xd4473d003fa6907ca153fe6f3bb712033d8fd4c3c484c7115ce371fbc6086cab6f3defec831b4c74c4476ffedd4a06925853e2a58f042c0cd5bd6233b502227d	1	0	\\x000000010000000000800003c1759d00f4453901dac840a5ab715c6869c883ad3b6de9c5b91ecbf89eacce766c81f20ae3aceb34eb1346a5ba34bff99a590aca208183f4625d7de3ad289220adbd36103a20e42cd8b11d2bfebbb92b62ccfab86380ceec079eea7e47735b9fc6d68969c1c955a82d89147f1faa94947050353309fe20ac3fe915a1be172a69010001	\\xd7d08e9c19bf45450df5e09cf99cb3bfef7e5c6aa621f9b96a2c5bc2f6c0b9cd8dda236554defedc2d509a43ff9f96fa5a514427fc56bb397c445b6d4de72603	1666085553000000	1666690353000000	1729762353000000	1824370353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
410	\\xd553df7495d4a9521e43dbab6224a98bf99eddec6e67593eed0059060c4b91f012c9479579af76049d230e52a78ccf9419db19daa438b6f4659af4a7f12d9c02	1	0	\\x000000010000000000800003b99aa02deb379a7952fa8bd3a4268e522d35d6b9c78046337d4930f724d57f602404e9b3a9f6fe6c0a89cff146bbf30b248b7eb3d033e73ea71500586ec93094e619e9f921867995fd7df0d505cc1d69b8aa3fcd48b64f9494eb435488496e0b3021759c72c9363c4faf04e6cc0d8146efd90295af3880641ab2d4478f6872ab010001	\\x4e0f81533353c19a64b11a450fd96a23610916efe7d507450c2964e1aaa2ee4cb0b30a87109e1c775e30067a43f006c9699625ae653ed75dcd096c48ac1eb502	1652182053000000	1652786853000000	1715858853000000	1810466853000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xd5a38478761723b43b2bd63a35be1af43f72e2ef454c9d3feaae8378462b241141f7ed4303ab0538ac0dd9301f3d5b64ec16b7445b13e3b2f33ef588f6de218a	1	0	\\x000000010000000000800003a9c1c3d43b39f8bcea32ceed31099e8063576741e015a67aaefd41cb21d79f18f2a8478a3eb7c00e331c45b83e9a2509bca5169eaa147d8643a3b17e004cfbef5994b7aa23df9dee125e19b8672bcd8c3624840de7832b391f415c7569e63801dcc6af035a784b7b452fc7d519eb9816f43214306031eb5dc4cfa543746ae1e3010001	\\x48a990dff18406750aaccea80b4f4dc577770d16c800ebdce5d034da353e78835731040d04676a3dc244a917087a633c628cdcbb4a801053b291d50225915c06	1658831553000000	1659436353000000	1722508353000000	1817116353000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xd89b0a8c42dd57430ebcabf7ca5f96dfa024d1afbf0b928a155b575d705dfb2e63afc3b116ebb8690fdf4eafcb140b4f0cb8df2d3092b8ca650a5f579199d7ff	1	0	\\x000000010000000000800003bfa10b0fad13e34d5da2d66f781b0af7468cd1bcbcb5056c40920a4568b6a89b7d9934e6585c1e2e1910817aacf37fb82f4826db4e951c9557b86d19c6dbdadfb00b4affcec39ede3233a078a28ff970a54c63718928d0901f6d2943b9eeb2a1dca50115066eeb088d4a04f12fdb13b5c598f102c794cef851d8bd0d2f61ab41010001	\\x1bd89ccd507e3a5365ec45b59d54839d95609b2fa1e1c314f954e2a637d0d26b758547e418853015d08fdef6c32ccbb85f6aa8dcae9b89128981b92ed5fe8e05	1678780053000000	1679384853000000	1742456853000000	1837064853000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
413	\\xdf831d4303c70bb2045b8ee3a3e517b515aa1daac0b0b4755cce0905043ad5431b217ab02514493be0dc8b421fb9196bbbf16d1682040a2f8433e6aa8ec2596f	1	0	\\x000000010000000000800003d188e1dd8d828b4747becea42fc0f09fb67d09c3b3379005bba30478a95ad14a8078c4dc7f2613cd41c30908fb7263d7674d2cc725698df684cedc12e952581790e60ea04dda7510a75e49bf54f460bdc46d6ec727e6b9bf400db5d3ff225ef688bbe183160b91bf34cda6aabec8b9eee7892cd04b8a48736b05da94cbf9d62b010001	\\xae150dee1fd5b5bebf7f329fc7a678df604a646d2a7a3e5c5e03b16c3d6ca5b3b5b1f4972b759c8229eed40f36a191048f71750a702905aba02a780b515a4904	1655204553000000	1655809353000000	1718881353000000	1813489353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
414	\\xe037026f55e4eb597b50042594b2f81d1258c729b2091fb6929b80b7bf8bf289efe46e7252884ce4533784a385a6ca3b6af10ce1a7baa43f2f7489d4bfc8e7a8	1	0	\\x000000010000000000800003b7da1d326bac8bea285628560f3adce08d86144d78f02df9a59b807fe2aab96dabe55fa412f4eb5507788dc67f6edd3733a6e7989a82df9b2de734142d7bd129386cffa815d34b81211117a2b8bc5da73380e8d9488d0c3c64d42947278efd1dc3ed280dd1f5694a380894656edb877d61ff3257793e8ce76a3dcae1d3d7a3a1010001	\\xe62a952434586032b606329c4727adb5a557a2ea737c6fc31c4215526d8436083b97bd56dc9f06a4c56d4abfcbf7a67881ea04cf2adc5aea7984011907d98602	1650368553000000	1650973353000000	1714045353000000	1808653353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
415	\\xe3d3c0178f4838a21706d06c03e28cf960e7758b39b4407165962047bfbbb8400e5f9f299f2e002414a125c1ac6e93bde361d81c571d30cd7938414ae9d429e3	1	0	\\x000000010000000000800003baad0830ad57ba7cc97ac723ef1850bc2a162214a9dee5f04660f1f3c3908eebcadf68707421613d6ebab60164e64b02454cd9bada7826bf966198737e8df42a8607c5d6d80ee8986e8ab0bf3c8c24baffa64bec1fe89fcf077e7f70dc99199dad11cf6dba527dbc1328146f9b77959a68ce1ac5e32fa7818dc3a9880e19930f010001	\\x1f65d25c2304d77cef2e39146ae2937b4723d6c61cae31158ccd803356b5ab3df456319f1c54fad5c98afe53e47b010e8352b02133253c59fedae5e1d2d03103	1661249553000000	1661854353000000	1724926353000000	1819534353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
416	\\xe4ffb286ffe100712a3604ce5f0918842c3846f2dc1079dfa70fd12dec7545570f82bdca832e711aaaac917c3863dc167d7f8769ace41cc5fab68aa9c981461a	1	0	\\x000000010000000000800003cc59ff85b4bbcca061ca7e1266f600d444c170ae9c8b56b1a06bb67a006d29e0917663f30f6e1bbda8064889eacb40ad11e8070fc727d25b6f989ab104f0f6e3777cc2e3c2e225f91ed68e3a04e89d0e8543668e9c8d64fbe343574bcb765b1a10fe0da0f33718d57adc2ecd051c8ba74953f1163a23b702a88e83ad5543a26b010001	\\xb3b6af6d964673c6a33d81bb42285b93ec2d61a3ddb69fd4cf41f7340b81df0402e1109c579f36db0351f212083005860d4b9bba9fb35ef0d60ea149ad6d6609	1652182053000000	1652786853000000	1715858853000000	1810466853000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xe4439a91c0747851cc960fe83c04a38f50b6db76d453a7039f806e2f096b1cb77187328c5cbf2e36be0235001e3e03b207044e1ff072c86e1ffda8d23952f677	1	0	\\x000000010000000000800003bde72959823899ca82462b5de206a63f15ea39ab584e9d32aeebab5a7ff8860c407d27e632bb7857f484dfe3d1b9798de2871a3ed9da2ba3c951996351c7062519ed782a28390b7ad928a34b698954fc8aebc0898bd94f8550c84ce077b61dacfde19e6ee56da45a0d0203cf60044508a0749420b07ef34db46bf1d97249099d010001	\\xfac7c41b6a04a1f8efb61fc9efa1e8d907776ac34f5fcf70867b9905cb940d4a6f4834e83c375975dd4741edae892a7f39863e0ca4471fd89a4f4ee5a32d3908	1663667553000000	1664272353000000	1727344353000000	1821952353000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
418	\\xe8c39fa0c6a05ffd994b652184cb2e660668a4436dc3138197ba71b748650d2f8473931c8a58beaa72a6a896c62a979a63acd34a20bc852567f9403ab1cd1fbe	1	0	\\x0000000100000000008000039d7efb382fc80a83f7cf40a5b684e6ca97852d697c23da66f8fb2246e30a12ae075550ec9bf81b4b85d6c88c339439fae8b3c4004d3e2d5cd8d4240591f7c3acd3d9d354bdf11584772d9d40e8ff0953ae141988b4c6204fecb4bc134f0a7be3c6a3121eced9648af2d8080214a88318034b07a8e0a4deade16120ae04a41653010001	\\x4ccf43edfbe36708dd59442707e8d239b1292d9322688593393b0fcc30103c232a62215aade367d55da0c13005a0e0f3ad99281d02e46b6907292f4759b0fc03	1678780053000000	1679384853000000	1742456853000000	1837064853000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
419	\\xec078cceb4aadf81acd49fb068ba856f337bc0efa38ae87f7c1008eedc47a02a5362b1f4904f9c49f9cc383e093be09ed914b14150cc0fc528695b1121de8729	1	0	\\x000000010000000000800003d272bb86f04f939ad0c487f24aeb60bd4b9f8de537cca665b1ba89cbd7f98d758577e4f2a5c306e3dff75acfd9c93b9e608acdc2fb8c9bf51ab7008bdccec76e1d0d240142dd1ca820b0f34bb3b7dd864b6c2e181a1d86cb5f576b15faa37ae5de6c8357d12cf7687889d8cb6bc0bcb065b38baa22b1a0bcd1a6f90ddc5ca1db010001	\\x84ae47ec4ab57e88a60ff4da4e97709c1f90b1cd73626d573242403a10ce882935970f4dc4270a329fbed875d976715f778a6260db4f41622b4f22fb9d44fc0e	1675757553000000	1676362353000000	1739434353000000	1834042353000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
420	\\xf50b4ed62f93539456faffbc7287ecd1eab1a9b45430c124442bc8583f40b7db3c397f0dfe5470084c36bcfaf7ecbc2c1327bd156eda617304a1252b123ec8db	1	0	\\x000000010000000000800003dace27ce54f40fcb1a1400178b2104391614c29dcb70909c092cdcb626791560d0a80852fb9e2f98abff1e4b3511568c526f3f7c89b91ac3a97c9aae4180e0d1295ab513cfaacd052dcf9a68503860165d4f086e1db473cb79e1a3a556e31af6066f418c041611ae4d735506814850a560758bd39575bb36b6d4c2cf65e9084f010001	\\x26e894b6080a1c9899402e9561e908aed79110662ec804078f2fd3eeb423e8129bc439dd940e3be965c63ed3862b1b9a8cc55f3afbc5c6e666d617ee1715140f	1653391053000000	1653995853000000	1717067853000000	1811675853000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
421	\\xf9370a885743f1256f260c0b393f83302f2ba5e25c5320a2f663b0759c9157144967bed424199f1b7456093df551b230759c92553e7b6b264c6ad0c1a567f370	1	0	\\x000000010000000000800003c9644e6508fa303018c23d5807f68db0a2e4441f750731b15168aea3a1d1e262dcc16d217c81902a9f2ab06c8a739fe4cfdbd708a358580ca86c1feb439641a5c81a52d553bbda55b34eb147fa33aa7dd1bc8c310cf912376c2ce71cdc9e3f029a4eab3b8e1d78047cad6131da04fe308508719dbb0914f485267c996fd3782d010001	\\x2e194985e4ea9efb68233894d1e6f961aeb117861c9f840b65c373037e52a15935f44e5283af764183b31f64a0db2bc59631d1cd14fd2e9fda991af7b6f7cd01	1657622553000000	1658227353000000	1721299353000000	1815907353000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfa2fd6ac874fe7852bb9a0cdf48fc2b47ddab6b849e686e0fead0febf043ae8909c7a4583c59830d72a8ffaf5587a5ce328ccfbbf2105b49765f811c6df32deb	1	0	\\x000000010000000000800003e49bf26b694618485440445912b8fdd8cbd56790acd6095a59dea2be59ae8ca952c6d749e279c3a559fdf8420b2a87f2ffbfac5f53c53c54e1dd6ce71b05b9a0d66bbb253bdca89cefe54f43aeba43ba791ce55fd4e02d774c7a54e74a208856ba6f4eba67e91807e20cfb529823200767a635429d8b1e5a8af662da165dbe49010001	\\x30844fb484837652a9012b52dd039047ea038e475d819e2ea4674120b5137034d03fdd543e07455ef1ecba692bf27496e092eca8e50908a63b6ccba21c29e406	1652182053000000	1652786853000000	1715858853000000	1810466853000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
423	\\xfb53c82f2a0476878011f126d3846d3ef7f27bdb5f4629afb53431c19767aa641ffc9313a4dd8f2716f730d0b56fc9152a44c6175efc9d6c1b45dc2c3e8652e8	1	0	\\x000000010000000000800003efe50f3030ac99c13606ddff5498fc5cd242dac51756f5b22545704b9f7bac59a24b89b4cd707fe90eed14b71d7f65efc8095ca4c1c3e8ae3c58a4a0418aaa403a00320fc663d86b8fb80a2bf5f9ae1e2fd72743c507acb44bcae489140334edb02a489ad1ed3d1b310525dea79a56f0ec2d17d82e84ae5927e0e2722974bdc9010001	\\x2fb2e49cd832ce1acc9f06b859037a22a75a90f2b81479e28289a3f8f67b95c467946f2096c845c6c52cc81704e7b068e2584fb4870b12d349e3deb51ff82a09	1652182053000000	1652786853000000	1715858853000000	1810466853000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
424	\\xfb43284e8957e9c214e38ff4f3d35f5541d22b1425fa4165233b0892e1537e5d3ae6d3df9e20c15c7e4024d37e368c89ad1eca5f4d5b997e4b277a756dc69736	1	0	\\x000000010000000000800003b1e6725c42d795eacba4185b34ec00c74addee40a90a40156c5be2540ed8a91fa6dd325bb1256f77c343ef77aa51a5363ae393f84523f12f3213c31243ab12580179f0c2ec24545a44bb2bdf20988be4998d9f505b1b010f48f8b835295bca8612ffcfcd8996d4c918fd5de26d952715c5cb9038b03301ef0c3ce15301dc25a7010001	\\xa45da664552cc9880ebf254f7c9673af030445eccd0dbcae5fe86419476046ca7772bf62c905ca112ab33ce9cd57337b873fa5adc6a13d5a59bfdd774fe1ce08	1673339553000000	1673944353000000	1737016353000000	1831624353000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	1	\\x63fddca2dceb119de34b325176a1a5b948aa952fe26ddd5c92e83e67e94342520d6377a972a90e6adf0860879f1fffaf899e1f7b36b4195b840fe0b35aa3d36a	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x13cf2f5238b6464e05e52d50ff5cb894ebe52839f256e49aa02b96600054c2d722b517b299a3ceebaac36688328c08248eaacbfd81e14b9d7560ae522b56d92a	1647346083000000	1647346981000000	1647346981000000	0	98000000	\\x2e84d06cad6f7f3e16c4e7b6b21538da67b1490c6d63ce533fe76539a01aa9d5	\\xd2db617408cf8fb42c9fa0bca10a0a45dff9593fc1bde4c58148db03f9565182	\\x4769bd1424e75c101b1d4c937408061ed78afcfd2b7c8b67d4857729b2ef792ee7095ade5e89723c58f73d62478e828f33e0355513d6312e8a85c9fdd1fe8005	\\x180f826c6c0e70e1c77ac987e7d4556fc8516debff1bfc3a372246551d4881a4	\\x2020200000000000000000000000000064cb1c0a6b7f0000000000000000000000000000000000002f57196608560000e0c3fb52fc7f00004000000000000000
\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	2	\\xadc15fd56b56644b3cf515d489c788e08545ab8cff4a8f1361a2af98ca42357d647049b5239b18c8208a362da4a6e27c2a1734fd26c677beeba94a01084af3c9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x13cf2f5238b6464e05e52d50ff5cb894ebe52839f256e49aa02b96600054c2d722b517b299a3ceebaac36688328c08248eaacbfd81e14b9d7560ae522b56d92a	1647950917000000	1647347013000000	1647347013000000	0	0	\\x14ce03aa2441314766d18018792c9a03041fd409474496283392a2ec940bda1c	\\xd2db617408cf8fb42c9fa0bca10a0a45dff9593fc1bde4c58148db03f9565182	\\xb6c978020a645e569df7db6efec2e030b59f93e454c42e4d81cd077a3970d34dc25746187166b77422049518408d39971acd1bb31c21e61c450a9ee09138600b	\\x180f826c6c0e70e1c77ac987e7d4556fc8516debff1bfc3a372246551d4881a4	\\xffffffffffffffff000000000000000064cb1c0a6b7f0000000000000000000000000000000000002f57196608560000e0c3fb52fc7f00004000000000000000
\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	3	\\xadc15fd56b56644b3cf515d489c788e08545ab8cff4a8f1361a2af98ca42357d647049b5239b18c8208a362da4a6e27c2a1734fd26c677beeba94a01084af3c9	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x13cf2f5238b6464e05e52d50ff5cb894ebe52839f256e49aa02b96600054c2d722b517b299a3ceebaac36688328c08248eaacbfd81e14b9d7560ae522b56d92a	1647950917000000	1647347013000000	1647347013000000	0	0	\\x1899d894a2643201a66b9a31a357954d526d278a6897a11fb00be8274f6a7b59	\\xd2db617408cf8fb42c9fa0bca10a0a45dff9593fc1bde4c58148db03f9565182	\\x31aeed16bf9abc426df70ea535470bcb44ebed3ee5be35f5ae4c2e1d25c4ca29b5f6091423f9dbad5b544c8da966514730170f63434bf2712336651b06f32407	\\x180f826c6c0e70e1c77ac987e7d4556fc8516debff1bfc3a372246551d4881a4	\\xffffffffffffffff000000000000000064cb1c0a6b7f0000000000000000000000000000000000002f57196608560000e0c3fb52fc7f00004000000000000000
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	116625567	2	1	0	1647346081000000	1647346083000000	1647346981000000	1647346981000000	\\xd2db617408cf8fb42c9fa0bca10a0a45dff9593fc1bde4c58148db03f9565182	\\x63fddca2dceb119de34b325176a1a5b948aa952fe26ddd5c92e83e67e94342520d6377a972a90e6adf0860879f1fffaf899e1f7b36b4195b840fe0b35aa3d36a	\\x551f28c69e5c78fc5c6bea3d54a24aeab809a12d29e31fa3d68a4f511bf104fe47621202b92cc9415e354e480793ae6b756c53bbb8fef7edd9e1347b4a5f910d	\\xed2a386678e6e432fa3c1916992cfadd	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	116625567	13	0	1000000	1647346113000000	1647950917000000	1647347013000000	1647347013000000	\\xd2db617408cf8fb42c9fa0bca10a0a45dff9593fc1bde4c58148db03f9565182	\\xadc15fd56b56644b3cf515d489c788e08545ab8cff4a8f1361a2af98ca42357d647049b5239b18c8208a362da4a6e27c2a1734fd26c677beeba94a01084af3c9	\\x5d0645bcb9e322105f58abece2580a0979497536a5f952d226d431d707ba827c64267e4354ce517709f44d37237f4bede47ab5cbed162fd92fbe59915048170d	\\xed2a386678e6e432fa3c1916992cfadd	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	116625567	14	0	1000000	1647346113000000	1647950917000000	1647347013000000	1647347013000000	\\xd2db617408cf8fb42c9fa0bca10a0a45dff9593fc1bde4c58148db03f9565182	\\xadc15fd56b56644b3cf515d489c788e08545ab8cff4a8f1361a2af98ca42357d647049b5239b18c8208a362da4a6e27c2a1734fd26c677beeba94a01084af3c9	\\x7c6ffceb242563aa66395a1039df0e8cb3816fcc97e7e3fc511d72174ba71d069c5964ec3ead92e4fb88a95cbb5b968774043b4d13dc269264c0c2dff1e6ef02	\\xed2a386678e6e432fa3c1916992cfadd	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
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
1	contenttypes	0001_initial	2022-03-15 13:07:34.033667+01
2	auth	0001_initial	2022-03-15 13:07:34.190825+01
3	app	0001_initial	2022-03-15 13:07:34.315786+01
4	contenttypes	0002_remove_content_type_name	2022-03-15 13:07:34.327374+01
5	auth	0002_alter_permission_name_max_length	2022-03-15 13:07:34.335602+01
6	auth	0003_alter_user_email_max_length	2022-03-15 13:07:34.342504+01
7	auth	0004_alter_user_username_opts	2022-03-15 13:07:34.350094+01
8	auth	0005_alter_user_last_login_null	2022-03-15 13:07:34.357206+01
9	auth	0006_require_contenttypes_0002	2022-03-15 13:07:34.360283+01
10	auth	0007_alter_validators_add_error_messages	2022-03-15 13:07:34.36703+01
11	auth	0008_alter_user_username_max_length	2022-03-15 13:07:34.381442+01
12	auth	0009_alter_user_last_name_max_length	2022-03-15 13:07:34.388428+01
13	auth	0010_alter_group_name_max_length	2022-03-15 13:07:34.397104+01
14	auth	0011_update_proxy_permissions	2022-03-15 13:07:34.404632+01
15	auth	0012_alter_user_first_name_max_length	2022-03-15 13:07:34.411945+01
16	sessions	0001_initial	2022-03-15 13:07:34.444459+01
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
1	\\x839b08fb1f0893ffa26c7509648f8c7fc9229986180b7758c73e8c93271a700a	\\x7be531791c6101f94cbbfa0f0036e0f30074b83580dc9cd80418cfc3ecd84e0c6b34c248f8015c44c5f3cb3f3e66e95957ed28167be613b9df1ee39599b45001	1654603353000000	1661860953000000	1664280153000000
2	\\x04612f6934d16085f4b058efe55416c49bf4472c801500450f002c10e0c7290b	\\x7f71b18e43b8143bd6780cebb124c55e805d8d4cecad7a795187c539f70d17b33afd6bea4987621a417139af511d7d89b8b6dcbf2e9cac2c438e4eaaeb15f80f	1669117953000000	1676375553000000	1678794753000000
3	\\x8501e3dee995d5c49081287d6707e61b997b2ffeee7cb3d4eb3789bd7efaf22f	\\x66e3711ce76257c42f49b96cb4d139aa7f20c0d269b3c3150fa9e57015d85fa593ec49a26751c46b6b7577bd153636be28927bbd07cdee5bf60ffb87a1389106	1676375253000000	1683632853000000	1686052053000000
4	\\x8912fb7798d3adf20f7ce2a8af26c06241815e9d266ce22172b170806a3b9f1c	\\x543c6d3c05f490926d9466633bffa2b36b019245c3d287f92105e1c8537f41b0015323fbf66afd45f717a213a00b63ec0c77a12e395d3b6060b8ae08cc08160c	1661860653000000	1669118253000000	1671537453000000
5	\\x180f826c6c0e70e1c77ac987e7d4556fc8516debff1bfc3a372246551d4881a4	\\x8ffe5238e8f881cf64a84991f7e2455b011164ffb9c8ca3a8fc86627a390a29ef478e2ba0de3a5573620199094865aa124b9c8b3288950282be4c1c505b38d08	1647346053000000	1654603653000000	1657022853000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\x3e09e82afcd612e7609a186107e85125b9373c187eadc64a5677315899bd588e03785d5b58cb82efc028fa20e565cc5a414953849551472ad17bb305b32c2a06
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	259	\\x861e46c8078ade160070f4be1c6710bc6c38358ebd0a6d063464b7e9d812fa73	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000afdc9e499a81fd16727229583bf6c31c2526c08665bf543e9b9c1b53dd0df38a542206894092397505ee16ea02ef6ec16dc024a8927c99f716137cd21209fd00244360982f84fc88e98d9b2f1412f4abd849570665c78276f04fdd427dd01556112b28849482e975f67625350f68aa20bbc83bc9504660dd384feb20c509bb3c	0	0
2	139	\\x2e84d06cad6f7f3e16c4e7b6b21538da67b1490c6d63ce533fe76539a01aa9d5	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000000f1e63129f36c367f2c510b39427d76f399d84e82b87ce65d13757fc902426dc89826a6b52ddffa4d2a9864b509819d3dbf71ba61788df7232fee7969ab2d6ac29eadce0b644abad05654f767e562cd3a89d4dfc3431f80fd14f1ea16d3626d8a76d8cead793df26e696dcecf1aeb15da46ba066d28d98c51dd6448a335541c7	0	0
11	142	\\xd740ad43d6728fe4030d5b0ffad571c00e2b5f55b635d396b2ab3023c7521703	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b5a5ff4b6c489541243efa9ca9a6959aab3f52eee5e0c71628e9ffba37ed8eec5e7b1c81bb3da9d96354f2df0c80473167a7a645736825e29584c7771282b7040ed2f753c056ff77eba8b59d9603324e6c27928a37f3801f793f214af88c7c554ab7f0a5462fdffd06317297d3c23f0602bbeb4a12c8fd75f7527a5a6a322aea	0	0
4	142	\\x283e6e090db549dbf103ae6e2c0d19a8761be9148ec0d0b016df36cfc689d03a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b63da6cb8167a5a9381afd9aafa82cab4821e4f07808dca6b7b6fecb8f9423c0c33a72b487a053139d15dd27e2874ab37d173679ed5dfe78a5d214bd9ee7059b50efe2c73735bdde4cecbd78252669d3b2507a0d7c1c455cc477fb00cf28be38820662a031f2cd0a7bc54c1422d130dbd53d4c2738e6c9a95f5ad3572dc817c7	0	0
5	142	\\xdc111d016789856ca4135d74bca25e54366db0983e4323a847d2e3e8de125a54	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000010efe571fef56250490c7049666d0e977a24a2a2f1bf925db0b5a6794b2e1b9a1e2ab37343ea8b909848a0406dde4d1a805aae129df6c876d203647cc06d69495ed73dfa3a1da9b0c3d74d5088c6208c86449fb5bfb8d613ec7f0ae90529aa8b6f749f7ff557dc09bc3726ac98aae895723dc815e7c4e6c2231b9c8ec51cdaa1	0	0
3	268	\\xc42469a443c3ec139ecce23832676bd0eec51c0654b650606f04ac4bb496db8f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b08fdc05c089fa2e58f09b88b83e52acf5352e88e4b04b1650e1a3b739230d1a79226dd9ebfe8ec402edbd0570e2e0663740556a5f5938687cb54b9a21048bcb1faa82ba8568a14feaafa3d873724b29643401b0b8744d5f6688cf455f64acc7849bcb8f1b4be560c7b8cb7e945ab771a55f9eee2b5b7f4f0a546a884537276c	0	1000000
6	142	\\xb5221805887ef4092c562d757643b9d989a605cb27ef08c810827aa2f7e9b131	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000004db152e65a84396149509db2613aa9663b4500c36c96c44c6a5dd735e5d94adb90ae48b7c9f98852abe09121861afe2aadb61178d02c58864d501210e8cd08f8bb1ad4743dd323068ec761704e1724a6a708295581dfb1f366d29247039d2922426c5c5e625082a9da4ff93dc4e6c14a7c2c63a012385836b55faaaa64204176	0	0
7	142	\\x5d8655f5cadf5a080ebead1f027ffe9a8f579ed3e51580fd0776605ab4e32557	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000311b07b572ed7cfb69fd12f6dcf4d5a1f171112a8b2f5349e7e3c1c60e4c521ee6dae26c4b7d430cc0905c81a0f662acc82a2ead2be7ab7e1a6f986922cb5ec2cc240ccf9107c0c840ccdafbe76b206e230a926075a8f46612a0c258115b72ee20f17cca1713da14694485ed0dd064918c680170abdd57bfe5dd15401168e310	0	0
13	24	\\x14ce03aa2441314766d18018792c9a03041fd409474496283392a2ec940bda1c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000978144fe8eba451cbe6978e8a809cd0f32579000ea01372c7010ae689bb2cce8d5c7e8dcf554cdeb3634352abe503a915ff338028f370a206157d1358ce0a9067037444c73f3d74afb5aaa9fea9bda1ae0dbe270853238fce391e565d2c6a7b09d99805c56d8ca7aa66830012c5ecfab65b385b9479e2c072fe387b35d882569	0	0
8	142	\\xa304096e9569ca100ef0d541267b949dabd378a9002d7cbbcbade759ab4f1857	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c6e8c80ec04678acd354c0b70e8ffd81c5581071cde18302e0eb1f010a446ea52982a2b647f14afec652a88a6656ba74ae69655f8dfbc38fd5ff92fc0a7889696b2c4e8a90a6678d00fb5d9f06634ea71759b2460a70ad96379bc28aba23a70f5bdad418e0539a5ed02eedd1191e3ac4223621de2953a3bc629c56d43ef07857	0	0
9	142	\\xb765c63299cc4357f58ea61b00db3eb2261a9ebd6ce4b17726e54dc3d24954b3	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000009624ce59da233f3ec8f454384b098e615195504ed2fd15187eb071d380324297ea700e780a5660058eccc0a6fe7a82dc78f875a03f22878ee108c0dca228793e93880d85e166939b68c211f68019e7b2459e235c1f7c54c46af825994b2097dd0228aa535c6bea02b7c3732e6d69d760cab820d2a659ceb8b3002a3166db75f6	0	0
14	24	\\x1899d894a2643201a66b9a31a357954d526d278a6897a11fb00be8274f6a7b59	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000402aa9287c8f2a8376c1ce2930dd060b8a071b8e850abe6fe3188a46c7b80d14833506c1ddc26eb484a27c01582c061a4bfd2782cef1f97fa4ffd8b3afe4eb812b84c99e98816a14e526330750a08882bc520287ea783c3d9f39bc23b9814e560c03f34855faaea3b2cece33a656ff49485cf7cf947443330a21c39ba984fccd	0	0
10	142	\\xbdbac7c79a0700662a76db1349b9824933b16408193f73b71bd319c3102d6449	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000002e6dce694ac97b6c64cde26f318477db3b96d57d9c4f6ee374125c57d138e281288c951f369a353abd14a4b335609072d0ef8a0490dddb36a050a739ae982f5915347864aaab93735cb7e2fbc2a66095cb41620b6c6a0e23b0018ae0288efe57ca6b8abcfdf7302284d13d07b08f75700338b767fb3e2667c2a8925044d375d4	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\x13cf2f5238b6464e05e52d50ff5cb894ebe52839f256e49aa02b96600054c2d722b517b299a3ceebaac36688328c08248eaacbfd81e14b9d7560ae522b56d92a	\\xed2a386678e6e432fa3c1916992cfadd	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.074-01C4C2WS5AHRA	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373334363938313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373334363938313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a223246374a594d48525053333457314635354e3846595135524a4b4e59414131535939424539364e30354542363030324d5242424a3544385150414354374b51424e4231504432314a4847343239334e4153465952335241424b4e545031424a4a354442444a4147222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037342d30314334433257533541485241222c2274696d657374616d70223a7b22745f73223a313634373334363038312c22745f6d73223a313634373334363038313030307d2c227061795f646561646c696e65223a7b22745f73223a313634373334393638312c22745f6d73223a313634373334393638313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2257354647514247584432384e50585231345a565259425147414b46393642515442454d345153364b463057435654424d31475347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225442445032583038535937563842345a4d325941323247413851465a4a50395a5236595939484331393344473759415041363130222c226e6f6e6365223a2253374b4a42535633434e324330314845304745464634344d4d445a4e3142594353355a414d324e4b5a374d485759534a32505a30227d	\\x63fddca2dceb119de34b325176a1a5b948aa952fe26ddd5c92e83e67e94342520d6377a972a90e6adf0860879f1fffaf899e1f7b36b4195b840fe0b35aa3d36a	1647346081000000	1647349681000000	1647346981000000	t	f	taler://fulfillment-success/thank+you		\\x1024ca4453271171198867a606a722c5
2	1	2022.074-000N43KT00MGE	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373334373031333030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373334373031333030307d2c2270726f6475637473223a5b5d2c22685f77697265223a223246374a594d48525053333457314635354e3846595135524a4b4e59414131535939424539364e30354542363030324d5242424a3544385150414354374b51424e4231504432314a4847343239334e4153465952335241424b4e545031424a4a354442444a4147222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037342d3030304e34334b5430304d4745222c2274696d657374616d70223a7b22745f73223a313634373334363131332c22745f6d73223a313634373334363131333030307d2c227061795f646561646c696e65223a7b22745f73223a313634373334393731332c22745f6d73223a313634373334393731333030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2257354647514247584432384e50585231345a565259425147414b46393642515442454d345153364b463057435654424d31475347227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a225442445032583038535937563842345a4d325941323247413851465a4a50395a5236595939484331393344473759415041363130222c226e6f6e6365223a2239484b534b374b31345232305037313241303536525a4d4238384b414d43535830533450464244483947415a4152463557345147227d	\\xadc15fd56b56644b3cf515d489c788e08545ab8cff4a8f1361a2af98ca42357d647049b5239b18c8208a362da4a6e27c2a1734fd26c677beeba94a01084af3c9	1647346113000000	1647349713000000	1647347013000000	t	f	taler://fulfillment-success/thank+you		\\xa9daf9045ed7618b50d4ca8e068a5751
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
1	1	1647346083000000	\\x2e84d06cad6f7f3e16c4e7b6b21538da67b1490c6d63ce533fe76539a01aa9d5	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	5	\\x4769bd1424e75c101b1d4c937408061ed78afcfd2b7c8b67d4857729b2ef792ee7095ade5e89723c58f73d62478e828f33e0355513d6312e8a85c9fdd1fe8005	1
2	2	1647950917000000	\\x14ce03aa2441314766d18018792c9a03041fd409474496283392a2ec940bda1c	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	5	\\xb6c978020a645e569df7db6efec2e030b59f93e454c42e4d81cd077a3970d34dc25746187166b77422049518408d39971acd1bb31c21e61c450a9ee09138600b	1
3	2	1647950917000000	\\x1899d894a2643201a66b9a31a357954d526d278a6897a11fb00be8274f6a7b59	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	5	\\x31aeed16bf9abc426df70ea535470bcb44ebed3ee5be35f5ae4c2e1d25c4ca29b5f6091423f9dbad5b544c8da966514730170f63434bf2712336651b06f32407	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	\\x839b08fb1f0893ffa26c7509648f8c7fc9229986180b7758c73e8c93271a700a	1654603353000000	1661860953000000	1664280153000000	\\x7be531791c6101f94cbbfa0f0036e0f30074b83580dc9cd80418cfc3ecd84e0c6b34c248f8015c44c5f3cb3f3e66e95957ed28167be613b9df1ee39599b45001
2	\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	\\x04612f6934d16085f4b058efe55416c49bf4472c801500450f002c10e0c7290b	1669117953000000	1676375553000000	1678794753000000	\\x7f71b18e43b8143bd6780cebb124c55e805d8d4cecad7a795187c539f70d17b33afd6bea4987621a417139af511d7d89b8b6dcbf2e9cac2c438e4eaaeb15f80f
3	\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	\\x8501e3dee995d5c49081287d6707e61b997b2ffeee7cb3d4eb3789bd7efaf22f	1676375253000000	1683632853000000	1686052053000000	\\x66e3711ce76257c42f49b96cb4d139aa7f20c0d269b3c3150fa9e57015d85fa593ec49a26751c46b6b7577bd153636be28927bbd07cdee5bf60ffb87a1389106
4	\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	\\x8912fb7798d3adf20f7ce2a8af26c06241815e9d266ce22172b170806a3b9f1c	1661860653000000	1669118253000000	1671537453000000	\\x543c6d3c05f490926d9466633bffa2b36b019245c3d287f92105e1c8537f41b0015323fbf66afd45f717a213a00b63ec0c77a12e395d3b6060b8ae08cc08160c
5	\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	\\x180f826c6c0e70e1c77ac987e7d4556fc8516debff1bfc3a372246551d4881a4	1647346053000000	1654603653000000	1657022853000000	\\x8ffe5238e8f881cf64a84991f7e2455b011164ffb9c8ca3a8fc86627a390a29ef478e2ba0de3a5573620199094865aa124b9c8b3288950282be4c1c505b38d08
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\xe15f0bae1d68915b770127f78f2ef054de932efa5ba84be4d37838cde9740c33	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x5bca23a8d87e507828b1d18e7148d63dba66c97f3ee2cde3f4be9ad00010ed49463342a7f7108d72bbd99fd073bce0ad40c8c5ac1ea90abc5cff9d5e2a0bb70e
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xd2db617408cf8fb42c9fa0bca10a0a45dff9593fc1bde4c58148db03f9565182	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xed82314f37b2f1d0eea88235ecb8a5181f2ed38e6e8691d143aa9b830dd2f294	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647346083000000	f	\N	\N	2	1	http://localhost:8081/
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
1	1	\\x11eed52f51634a24be6721e7d00bb3ba7487f52390c10bdfc7db6a3b6112178f3600209de768aea99025968b087993cb0dc3270faf524acefaf9e24b59be980e	\\x1e658d197333a682912c6d55ee7f9e290d0fda36f3746edf73293015ef63e073	2	0	1647346078000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	4	\\xb75ab2f385fe249abf9a8ffafef74b5e896070a752660161188c5876c5fc06eee3bfafb1f0448c51868aebe9b70753f079cc3824de510dc6cbe27ebe6e0a4504	\\x60de3886d5f65dd203648d3112b1452b56d7f8d1e6ef2d0291b5dd17f9248750	0	10000000	1647950903000000	9
2	5	\\xc91b1f730828025e0dc190255c2f2f9dc1675260fe6422fef2e012860094e48a61fe3373bea4604471827d92c475df8a0337f6e1fc0d02de0ed998928ee86600	\\xd3da2b3e4c89a4984c7cf78dfa4b9e78f61f7546c8eb874398c1cfb77f80a093	0	10000000	1647950903000000	7
3	6	\\x8b9a4b12e3679a8d82aeb2bfa6c08f27fa3451a7ab8df73be96c7475a4724320659f37a5beff90cd6f829c6c643b8c0351174dca44171da6837245b14c520708	\\x7c4092ab78053eb4a5d31e3ad20a2dfeecc00234605c198332ba64178e73a7d9	0	10000000	1647950903000000	8
4	7	\\x7cebd8f1c87ec01697de721e81a13404be21b2ce519274a9338f1b2ebf39a25585e268df04f8c6b7b5c69357ff27d43513fc077bd9ef79faa90fc43480550b0b	\\x306eaeb8e8ea23fcc437a3bbe3c3b8afb9aa69f30f2f3cbd119cd35ce9ac0f2d	0	10000000	1647950903000000	3
5	8	\\x432f34969f1d78fe6712c0e41e21bf413978eaa3f7122750c8174dcc3d9ee57f64a14b9b1624812133a7df364c1dbf020ffd9cfdf5f563beed0f76611dd3f900	\\x7a83450c08040069323bf78e915605b383a84b5dc50f75fd8c2e4497da4cd37c	0	10000000	1647950903000000	6
6	9	\\xebc4aee84c4a509ea5f79ef25935935b80e64c717602cf92b0934bf1dc2e9aff06b90029030a97f97e42bf67c94000bbf5a439357680bcf4d9ac3ff708693102	\\x9371116d9d0c02ea7a27e6263315ad7c43b6bd710fa7eb08369002121a1956f8	0	10000000	1647950903000000	4
7	10	\\xc27ba31dbb1c3d65cd56630558ded64368cdfe02f4e3057e86d6e1bc53230896ecfba331a6f57a5d148c43705c0144548ae949b6712192bccb3cd98577de120a	\\x8d7434114245a34c64672a6ffa29a7e498ed8037c970f06ccce2a54b3835c35d	0	10000000	1647950903000000	5
8	11	\\xee247ac0276c55ac9c061f1d1fa28f3e5f4ca9343af4ccae40f5c48369e587db5a3e1d8cf4c850d90f7c89b1adea8d808ead4441bb327a37a5634f3c83c50b0b	\\xfe98a980363e1164e0d45dd7a218e6de201e502526220a09b9dd48e67e5a568b	0	10000000	1647950903000000	2
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, h_age_commitment, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\xae76301c2ca618dbda453d7c494ee2478a636ce839a64e10a68127586b9c3551cca1b63fbd2528e49e4c0f7fbc2ee794df32a197d4e83f1c1edd6f46531fa4a5	\\xc42469a443c3ec139ecce23832676bd0eec51c0654b650606f04ac4bb496db8f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x43806514f944f91a36453b7acda043b66269c8018ea914d13ac4e5be004f1f4d3c373e9620000107e0611125e34e55fba4e95ec25a8b7463173e14a5dc66db0d	5	0	2
2	\\x482d88a18a8b05657f88d92bbdc5d35e292a2448cdc1bc80c910d7aded053e89394a3337e30bdebc0b319c9cb30e4862b3166a77a9c30d3a1b2305bd0091bb24	\\xc42469a443c3ec139ecce23832676bd0eec51c0654b650606f04ac4bb496db8f	\\x0000000000000000000000000000000000000000000000000000000000000000	\\xcec58e91f17e1b258665cb7862c8bf1f1bd6b5a9f14a7a80254160857cc0419ec9cd2eab7f9fbecd960c2fe6bd8404f303a7876cedd15529755301efaea92904	0	79000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x577b79f0fc958f3e22bbc1729816308fd0ede2c9be68a962b35c46ed18a0a546bd777a740d185af82c7ba25f45a154446a332542358cf65b77f3d5528b48270a	27	\\x0000000100000100b8226eeeff993fbbdc9b03e30c570c40fb34ba14f3640a6bf4c2a7c3382e595a58a8f682efb11180c8de63ae0f8243c3d63cf9cda7e659752ebeae0164dcd527e4dcb65427a7844694c64b44359c3465a7e148bb7fbbaaa3a6d620cfbf4a46a196a72ec9696c619976954d75639ce120501784e6ee43e306361866328c8fb33a	\\xfd123000a4651dc28c471b932d48e3412a9981cc9448466aa9e871283ffbb097374d67d61ebc71d4fa4d7ae206dcfaf8ffce300c0a236b5087bd539a6d0224fe	\\x0000000100000001948fff77fd8af091a54522b82e3569ade126dbf042e1cee1185bddc631b768916127256662df016650bf0d34927039ad25cc646bb89b79b812b07f07ba2d5356fc29718e44cc3167e37d629bdf1f21c624622ea7c00cd17efa4d9f40dc86bbf71da4ce1b606ac7f8ae65cab1b8ec8931ca01e5006ab3447e0da3d317187cef0c	\\x0000000100010000
2	1	1	\\xff9027993ad504abd33a0c529332600e681b12ef3afdc8b5459df22d188b47b11fca392a02122541e5c7917099142f8a08ac9777d4abfba74e8ae28e63763b07	142	\\x00000001000001005b1444cf27011f8453d8ae85abdc16ac1640f12821fb2464f4b19b0fc015f6fa9508bffada3c2a8bf4cf43082b1438b648b8bbf160ef477a1b6651d6a362b3161830d1bdcaa7595e4136ec0db7be53ed7634d5fd65753747bbac436b4dab418e64980756ef14d0a6a79b159766f7f1727e0a1bd6ded23342431b92be6788877d	\\x3a375d7b95d265aa90d232ddae09d8685d0ea362ea2309e171948c27ea0668cb837d870002a2806ba37e9e086e1079141a527b43415b1c9ef9abf4b1a3f9e9e5	\\x00000001000000011877e57b18117e080a10e2b1023f23818d990bf740f8feb44f4baf555b2fff16f598ec3e2bb944613fcb0f140c9b937ecacd08ec9d2be5a4a07589eee5b79a81ef56c4c87802e42ede42c82af33766d7b87b01273763afc133cbf5bb129c760a76c5da225b0c2431e491697abfb1f69cf07f20e8e2e89c3bb1c1edd0c3818c1a	\\x0000000100010000
3	1	2	\\x76b778dc77ce0b1ec452d7b5018630a3a01d7c2c7126813744f0462b8c8ea7ed3a563cbd674dcc653c32a0855ac07310db1063fef0bc335425aaff4c06798207	142	\\x000000010000010041a0d24e846c446d3d7db2fb5b1e10404bbb7afa32bc6016b7bca94f0b88fc76e94cc65b1c9968a4c063c457924cde30c63a572dff2a730701acb87f9553235fbd5806d693440eb529d5deb301c3e4d8afd4acb9c70bceafc060760979657134034828ab44428eabd8c7e2350f3fc28702de5fb80dd29275efb1024561762e7c	\\xa4cf1c159644f05fb940865d0c9d5c90267b8260dd8b1d7b415958e21987288c6b14f3bb49aa5db60873e315083530ae4a09adb3be8ce79a146c403d283f5c5a	\\x00000001000000013f37f34dffafe5667947e37a8aba347be78eedb9d8600813a5443077108c5d9fd139a43334d5576b65a7bcd374c3d16043742e9becf27e33aef8b13e7a38dc3bce119ec2c9adc7d9520341ddb370eb9ca1e6b65d7f7acf01d4f0a045a580a53064393f265be912e24989892141366df677ae142b3e0e94433756997f6ded2696	\\x0000000100010000
4	1	3	\\x17160fed31afd0b3365c6802f580315b742161ba2dc2c1b597ae45d866f9ffbbcbd2643aac3a5a5d12d5f51498ee31a0bddab404d97df5f06eacdbe5bdfdb104	142	\\x0000000100000100c705c10893a84b58f9c7fde230c20cf93acef63349afe51aef58c9ff26ffa0d13fefeb2cddcc5bbe838a0cefe9a899e2d3dfeb77c410e82cddb359fbb5c1e12a1c2b53f567470f3a7155f118aeb1de441c9d17ddfad8f292730939e9d178ff582f73baaa838ca104a81607385edac03f9eac2195de1c2fc4b671bc856a67d881	\\x43517f2db210f2328bb627345678fc0cafe8ac94f74c5b3994ed0ac5166771499412b193c1ef194f8f4541c2ab3c758468e5fca7018c627fb8366794c3bc9abb	\\x0000000100000001b7a5219bf99f17bff4bb9ecf844d76d4245bbff6305f943b6c58c4d974f734431cbbd8b2f5e4e5ce897dd3b05a290473ee0ab0ba3de83aa31ee70f82b5f8ad68a7e5e56118e70730de89087defde01de5071b6cd274b4621acdae1fd716be5acca04c484bc892e9e6c18bc27da2094b40b3b61892dd17aec30083e17e658862e	\\x0000000100010000
5	1	4	\\x42a71f68e5ae110483df03b6d722489b9c020c99bcd3c733772d91f232db9908658ced811ac44ca894878db46628d0389f9ac4e528048eeaa00dac585d18710e	142	\\x00000001000001007d87be53ca987ce11026bea75fa3ec86234fa14fe45120ab4834c0642c96defb304253c796d2d2acca1dd8f16c2f0e0b3192396dd0731733730dbf8811c3f20531a3ca598d70e11583934899a47763c909b868f26d91ea1e4d28884895ffba99a5b8c43955984cf005be0434ca5c7f7ad458846c389ef29eb50325cff6ffe601	\\x4b8b348e4805d97ea0a1c0eef1254c5ebb048ea4089ca709c0785838861ed90a2060fd0227745e523949de54f847c613c6af1ed9b1fd272337549af7f6a7d347	\\x00000001000000013d288519eae874dca41a4a695d07c8ea3d9bd4186f284ecb2ee41ada188096faca85e3b8b593c23fa35526bab2b393d48e89cfa69a1dadf4fa3a25df980e72b1be38badc7c2910371b861a2098a9df472bce5351618855c508024158ca811b52ead7a2e7c00c73ffb27d8717701cc8dc5284f1a90050f4f9713d617530fe4cf4	\\x0000000100010000
6	1	5	\\x3229956d943c3619f16ed9447da58df5d63cdd7a240c2bea0c4db96d2bf294c7ac522580abd30f2c527d86bc125780dd729ae6c8e9bf65d5ccd9608a59b72108	142	\\x00000001000001004002492804d44891ad9fe71f2de5011935cfd262849fd8bf23fa3d7db3547bd4d49582c3aa0026e33891d45c2a1f15f6b6350e402eaa1069954b5cf6adf9d513e7141bd5475c3342f885bdfacb02ec4d73d40290b43cbd839c2be0c02efedc3289356468a1d76e904906ea1e421d8a2db1a5087cb20eac0bbc7a805d43b79b21	\\x49543979f266a6eff7827d6de8b7b0b04efc7662af561dfe2c1aba827e215f3b40432f197723074941fdf3b945e54816f68becf58649d9854bd02acef04cf86c	\\x000000010000000120bf35efa23546afdc3e446b76fbdefaef0c0a26904df20be5f4f370e0387b76bdaaffbb9a764e350f31a3fa8af10e21f6fd6a99173fa766ad2c1105091f73a06278986b1db1248a9f9c97e90e14ad311e2eba6dbc8f794abf181e7b721f34f5809c17a45812d2f23c9f92b23e61be7b032e9387f774b26093b95fe671f1cc28	\\x0000000100010000
7	1	6	\\x6c1d7132440937ac51b0cb1bbe51e45f35f5dbd4baad6be2a56ab655c31b64f219d6660f8f67de8787bf72712df6884d46c523934308ad5a43ac37d9d0b01600	142	\\x00000001000001006cc30a8204f68004ef4d1bc3787e8b04e71a57c4aacefe29130d8213a9274093735179fbf21a0ecd7f90b99ef6f29187ab595510e153bdb1d60888ec37a008e1a803f3f62eebeda3b7c82364602b7e864dae904b1b0233af40ee5c8e0276a9d895a6a527003fbd1511acb0680f514ee57deaae5d0fc4980f1f89d3f19524e852	\\x83320d2d4a5db744423e2e5bf293c7054daa21ef340214c8389f2875e7a9b47e7150a5877cab6b72d3b62e608d0964847645c208003f12f1de7eb5e6adce87c9	\\x0000000100000001927aacb499ff62d91ad03ab49857b2993b04903bb9699f4e130b9156fe494d4eb9c5291d360e6e995da36e131c30cdaf937fa1ef2c47e126ddaa9dd5b2ad169a95c1fc424abc972249a45b8d99da889df3477320a8908fb2db5a9fc4398c45a43d7f5b762f24eb6b6ca522e45d8d7e8ec5a74b033ae3112d4382f683e96987c3	\\x0000000100010000
8	1	7	\\x2e02880da35e2308a3c80794e12a0e731ba223d2fa316c17580a2cd8a7bce4841a9a2ed302fb2a73d58844e884aff700570d61336aa6e2c30f512b95ae83fd0c	142	\\x00000001000001003e3369bd010e85c5992d3e4c66d406badfbeaf76b7d2a75f750a6bc76a572a4b4f3196223bfd3b7fb161548e5c13f1db06f8b71f623f1518314e0db024b9cc2b8e79afcfd8a89977e4bef7919bbb6c55e288b2ad65c504d250536b2f2fd9ace86375dda646cba55a15f2b95875a992a00f9ab8fcd575c05947b4d53595f21593	\\xaab86722751e0c6a5e864b5a6a03a4cd7fd0aca39e614d5b0ab8f6218159c398a714db8be65bd608cb466a5d1718fe4116a7546047fd143c1e9a8fc7b2bb78b9	\\x00000001000000017bc0828efe99a71e3f39bb33b970179717201fde40b8c98f2ce38a2bd5e28e3ac667cf6988e9bf77dd35fd6d86eba3f67f755372dedac8df39318797c4201c62bbef80ee54bebb2fd8e7363ad71ebfc8d388f9eab8f1b86fbeea3c7e7ad15261e31264b27732a17eac6976492dd4a8b257427dc48f338c24e8d6f2e4b11bde6c	\\x0000000100010000
9	1	8	\\xe1c756c3d10d0bd916265e8b0fbe5209e1b8e5eaade9855634bae72e72cf0bf9a190375aee067f41c36ae6c0b45eebf154a992c93ebd7b3d61b7bd8153524f0e	142	\\x0000000100000100c4e7dee917db769371c20dbd815e79877669610094ccfb5d774d0285d35d2b3a7cea3c7852e0b0af55eb4cbcee976f596971596dae1b3a7a2fd506cc8577b4afc092098052ad27cdc268d3eb8b65a7be7b779189d5f50a378f4d874e8000324f99f6a0a69927727127b0f7ace5a09a9beee036e012f7a32fc8ed7b236988f909	\\x24feb07fa8032773c6e700718cdbc653406306620acea526b8edcb136db69a39f3abded70ebdaecbc2ca7f3223284870d05a56dc31e028c7f596550a2160a45d	\\x00000001000000017d668413388d62cc6b3fcdb243a70ab3f9f26cec227e1134f2e950c6d9454895ecd20b0d9c2d1bcc53907fa267938b3d06f4925666edf35c9a25938fc5d45ea7ffd8a3f140a4f778a0a104c71510059a4207aea868a6d78c55ba1069ee76838790de49bac5f011663722d93c2e38ac4836ef6104ae0194cf04bace80c526a264	\\x0000000100010000
10	1	9	\\x774b21d5ab1798f7bd85f6a84f695f68054e7b3a276e818e45c29356b1d987cff7f47cfbf669062c1ab2cc878c36467cdb93b542755dd9ac6a8a5bd75d9fc500	24	\\x0000000100000100703c7534e6916475679cba9d8c9a717814e7606afe7a501193c0df914112ccfce14b2ba27a5efa7ee2c28a21da7c41db533b1c61aa4121c5a7389b769bc9325a3be73e7edd96bf1de96fed98ec53752b04dfd3291b1125bee47c7d71893e2104b3004e083b122410309d9bb007babdae5c61247a9da6c58b71894f12960ed3cc	\\xcb5718104d97ed17608eacdaf4502faec2dc50d19aeab1d73705951162a3557bf4c911c8cb54a4f0901bdad2c692a68d854fedfad8ddc405949a9f1d56f24558	\\x00000001000000017f61cb5b6f65a8b99b18010b99e3ff8c42b46ed9550387d3e121f8839a8161b2b3a45ce3aea7b3291077302421a0e881aa099af873d32759552e3ef4de81d539a1b3a4150388e52853df55ff7399ff5071e350c88451ba5528d11a8617537c4b3119685b7e8ae109d371f05ec9e34bf8a0ef884db72785e4d544ae7f4d7beb39	\\x0000000100010000
11	1	10	\\xa441d6f832e38616d3782668b60d4114dbe77241be16d6226e15462bf6facd097c0e2425f7f16c997b5d9430eec66c7db4bcaf7688ee4e882fa8c3a0ad182303	24	\\x000000010000010095a5bf06d070433b52823bdfcbe1c2dc00b6bebf4ae20165b3c81488b2f700fccfb8b792f43f11c8166ac0c87b34a87eae647d183c86b9627c27abeb6b9a7a6e5eabfe3a96f117c55f5a3756de2aca23e059c16efa724c6818db21be63c898a3f8c93dfc9bfe0507c31e7e9fa4165f6a188c503b175329bad5b46a9b3857253b	\\xd0ead732fd02122d768cf4894bbbe10a2ef67c07e56b44a18d1af67e09dbafc9bccc8e0b24f70f4fdda7ff15710ebf3f0b9df2b561901f84b25d4ad73f6ba4c5	\\x000000010000000136134f9ed339f0e94f4e402be78d0f4124dea7077361171e6db920db5b248f259d9b4156550233592ac49a8616a2a63461efbf6c1e66dc3b8c24cec11b6aa2b5336425c9ba5fa9aafa36cc0770ebf5ba28301c855d25b0414a0357349cda9475e040df5612d943eaff7949d90161cc27ce814bc63a1a54712a41cb3fa1ee9b6b	\\x0000000100010000
12	1	11	\\xcd996806dfa8c2eb836ad1f2ecb4ea6a0796b560704ac3752a89dcbe15b6083f726ce7c90cc7dcd8eabd912d04c197f743d407a3287667f28a66c4ea932cf305	24	\\x0000000100000100765b532f3e7546cd784bbff6610c437a70bf1b5623239970d8039c1ef29780f860e67856b645f68c1074d0f2a93f6177250813707bd3dcc4d607dc9464183468df584fdeb085b35e906ee517f1e31b683b7059cd2d85d44320a73bbdf90d2ff298e416857dedf840ffc6b1bd2f6144c4b6d84897475b02d08a99016826c6b448	\\xbd6b657f88a6887aa2eeafce55fcbb5b156cee2f87f3cd588167b8ab08ad436e3270e82e0f32424feb593f4ba2b7d92a5d0cd3fd278419d32a60585fd5f639c1	\\x00000001000000019205eae86c825e2ba5c4e752267780cee8d28f7c31404fb51ed5d6d99fbd1a65d97df6da8990d852bee3931e5661f5cab4d4fff9cd81db55219071ab809a337243ecec3d20207514bd65902f470fd65981ae7f6aa35b6a4f9a6b75088ad62b412f74ac58b1597e11db2f0f92638716ef3a853708a718fbb201a1be9b79d8d47d	\\x0000000100010000
13	2	0	\\xa43925b3d53db57d3bad303e19099c830d5988440f035f7d27d12f6fd6644f00b2c75d58412a633db13e248332557be090975113cca6b093bca446c3c7eb4805	24	\\x0000000100000100904c05e70f51715f4dc4a82a8bdd1e2eb06425d4c4ca6601ef19c8f8b5c6cf5c95197a9232af4c5f4441b98835e39ebf3a9bb456e4c6c235918d782a9ab2048dcefc02e478b7feabe66decca942f65ba87f714b5920e664d7bf8db4dd6f63bd29b2f70d8bfb26940482864c2366c6fed5adc647cf03d7d2815153e6cf28e537c	\\xd14a44b698a5afa734d096a23826621da34cdb8a1d3a45ade32b6e4d8b43b53fae485e7f8d02b697c2648742bb98bd1ef0b1760b3e4bcc5274110ad8717965c8	\\x000000010000000107ae8aafa1d5ed350dcd7d4a41f56b4acf1157a7f28895ccdf7fdece1d6a8b1c7dee4e99763ede6b854709f01ab5893360e2c71a434c645176e8de90c9a0a0fe3180d4eca32a48673ee581193c8162fbd47ed3ed05de608f8132b4b79f0ec9140fdd2fffb6c015f0ff1095eba3bc01c72bad91436e6d6959599f8c43cc1831e9	\\x0000000100010000
14	2	1	\\x269ceb867fd4e877ccb357a7b086617171435722aafcef6023187bd34c2ed58664dd43879327d5582b281b059a0195efc3b4598f979eac1a8bf7f887fc219601	24	\\x00000001000001000bad1ec3ba038e54af7cb06820120b0583735a2e7b9ec9dc2881c7e5876fd3ce7dc3683368de10dbde3d5b279be230435ff4d6fdf2505a6291b28538799d23d6f5293ee4f44054665181cda31b015b66830dc09ee8e6ad2b56dcf0b0a1e741f6cc8c35276ccd41e6d4312b7047009e8d5012f5f1289c0e4824fe7e5243b1a225	\\x1cfd3be7662252bab3e2dba64626f26d64eb834e292ffd45acd6c2a56f2768a76bbc4a3e62c678ccbacc383b0001657406e604878910da57fcfc1ab186c09ded	\\x000000010000000150146bcdc0f0e3437d5af24a2b087dc128e2d2d988645c078732c8ff2fbd86b78b6156a0fd6562d508ba142d79fb0f7fc9045f027f7d7b717b838e3ebf0432a6a5e0a9d649e88d2b2c1349e5a49154a9b75c89f89c44f63f3088c4b2a088b817ccf1aa5dfd6f9d6d04c91955e738360f92be52d6fc9a9b4e7141a06a176f37d5	\\x0000000100010000
15	2	2	\\x86011f4024238ea649c496e5da9447399897aa144805f2758d62ad087ce7e37475cd0399aa4fcef4454e50c75fce13ec94c2338c449c085685ede7cc53734507	24	\\x0000000100000100a3dca7359150166678d662e3f36fed53e7870c36f545f742d6ea276b9608e91ff2753769ae8e2199323910dd95c3f0b8f38b18910d2fc64069cec3abd5584453de4a670573c13c403921305bc03f4f0da3f991ff86c464c2a89040acd28a636f90fe0dd883b9bb477b7af2baa35d2dc406439c477b4f1c205caf900a7a7f41af	\\x1dd86b5eebb91f5c7376552bc1549da5ae827363c30008b8c566bc0fa3ed3d591ab9cc184c18476d29be090cd331378952fae450f9e233368e31fb8fafecf781	\\x00000001000000010210b32dea7eeee9536f37b43a7d6edb34a1d960e458ea26d5f344a72ee8aa5be3f714f0df38384d49e124273f4996238325b6ff97ee588fbdffcd3c852e13fac55073ced38982de8a9647d2a6097c787c15e82d47b23570005a56b22c9d9cf3b15832072cff7f845792b5b71171811e7233f11cae09b99fca6738c945794fcc	\\x0000000100010000
16	2	3	\\x2751d1b5d1c71022fea55896631d5def3c22f8f1816250ddbb9a88e310e9feecd41ad4be6a0d5a7e34f5532a2b94950006ba329bf389f2f923255fd18fe3a002	24	\\x000000010000010053ca74c42bc6d8c145b3199f34df4f1304ece8f2466f82138140df0c374fb42077315e5eb7a2bffa7a5e7d7ade595f41380aac6980298397115cc377c6f53b867491476d6dcd9afce8a77f61898ba917a3e511fc0d7ad11cb7b12352f491be9f318f3026eebf6a081e7634adf34633592f7cb7e11fb4d0cd5215e9345ec6bbcd	\\x2441619b6c539db5fbd53fbb3798872631626edabb28c12ee989e784bf07852415370929e9f1c92eaab69d0bbfed8a1a775053f93efd7775832b892410c6e506	\\x000000010000000113014888b9a8fb320d21942a8dda90578b2298a032719c2165c5ad25c4c99711e4376a229532f4b6d34fadc6550b902543e61d9b76496a3fbf5bf2cf19bea11d4593f5838a07414e5611c8e6c133f1d543ac4a2ed9418defd9b6aac87ff860e5d99ba71e51f8350f4af2beff4cb47059feb629a5704bb413c93dd17d9ea52b44	\\x0000000100010000
17	2	4	\\xc23810a46aff1d9b5dce3a7bd0b6c9ac9a8dfa9c18d2555a38f70a28401422b9349129f292bd3cea4e0dd06464ce9189355b7ed15accaddd64e4bf2bd0f9590e	24	\\x0000000100000100020dbec081f447881f419e5281042d94c639fe8fad671bbaa84989c97b7367cc2326b1aa32dc88e1bdaa2b6621769c3adb94cff6fc7850d81aab686d77812dfe5af09a96a75bd8f04df1c5a6ab81d345c13a063aa8cd6e9693c8243ee8aed5ff3a0e78a3e578fada8c759a09d6f991ffd0d8366067e44cc8b7a3f12b2b2ef0d8	\\x026ab10a50327601bfbe8d44121789af2287787184c4798af3552a5e898e1832660543616e43b2f6e1232001ebae15fd35ffda37639f3cf7f2a40d52177e4b51	\\x000000010000000191614722c18391fde0e4257e20a8496453b1df523e4d401806eef810b18f256bf46e6c92bcf2ae8f40314163f8053c7671ff116fb68f29541092a94ef95cdf29946a039d76af008d4eeafbd33bdc01942a74fd3fc7dd361f84e8adc3031fcc9a7ceac4e20c53d9be495e83646e675a72fec037b3e02e48fbe29f7c93b15fc85d	\\x0000000100010000
18	2	5	\\xf4e814a6f59883e13d11a3085b6d0d4958522e6e827253c2dbb6e16fbd028207cdb59ac55cf8de7eb907f6869b421c07c83f99ed060dfdae8662e27cac13ff01	24	\\x00000001000001008aee27931a98763bfb887f7e136c36e8986bfffafb4b4189f00ea7b6203a79556746f980004f187e4a12a0b3f87ccd9757f882feddeff40e67475c8585de72a3c7161b2de5e1c0b6de7e69baac1daa3a60488a15531417658673188db6d0d4aa71ef0ece67ce48365b1b6f9f1524d461f996f9dcf4c9268828f5ec8552258032	\\x6aca4e94994828a290a1e780197f23ae246cc2066cdf7dd2611f0f5137825586b588a0a5bc65cddc8832040062bacaec178cd3617d64f65b548e63ecc01e5ac2	\\x000000010000000136b7736445e8b2ad4c0b68d44d0625d4ac4b763c342d07a95817f5c46fb40dd49d400e07d53c1a9714f3dc06fb8d282e9834a2c805ad08394ea44425d387f29c0ba756d65a6e1fd1499a481bbc133ce05bf661955dcce35fa0372fd5d3728429dcfad2a0f2c6748241489aed9d572662b0b68dd353a127fa4ff232f0377c7372	\\x0000000100010000
19	2	6	\\xd450af9559e3f69e42db7104d557209b1bbe6c0de5e92dbbbaf1f92a2647cb91479f60b283df3ff2e0f6be3360bb134f5ec932c9aa078fc00a34680b14ca9e09	24	\\x00000001000001002aafef6e4a90e9700daeaa1ffe3d3747448896db2acba4f4e538251f3e6b6601e8bec75a7468265d0b1fa4a2e83745e970d01185bd42e4f65f9462abd2b33064c5f5e983e895e2d7098edf2a339016f2ecf014fc63365c66fe0697c142a015fc69331a9c33c3e6fdc1595614e7751ce5482caed0a2f7cc440980ced4e2e1eca4	\\x2c0ca18477680b73de4d625a58e32f8e9b5848b97bed6009d5bc9a85ef3ec14f4fb8b40a560bfb64db0435a884575473139ebba7630a9d9468089fc3b63617be	\\x00000001000000015117b44a3ec2ebd7aabfa691efc6e575fdc394ce29fdc353882c5fa3ea543713001567604b2e3a336751b67ae35a0d656d3f8d979358a00dc18a3a40236c11e7b3f472faf2d2891a90c5ebef0a03416d37e78483fcd5d098bf6056f6838d6fa4e6e31089b6393bf47f6aac923797f00d0d8679f752701b62d2181b261554587e	\\x0000000100010000
20	2	7	\\x8b72be6062e3151a365cc70d8aebda267f333ebda5d4f52409041ca370189942d7046a5cd880c0928dde5d5f4181ef9a971f8a4a6da9b8556493cc0b8eafb909	24	\\x00000001000001007d834bef699d84a3d855a4ae6bb00bd2074f7a25bd3882b6516aa3034b58aa4f0904472ed3d9334870fe296743da6b58fe03f1b1ffe99447a460fa189eb5419892d4b0e8bfa68212e36bae279f22caca6b186eade092e9c3f7075a8ac6515dc4ebc9cd8a472219486cc0f7f35eb6af282ee0a1718225aa641a243fcbe8422943	\\x817d13d51260649da7275efbce76dce0d3b27f3e0c2931deb802684a714543c1e8f011e0b2e5daa365a5904161117ddfd746a7197f85ec48e8d304fbaa7f8bf9	\\x00000001000000017a72ceb6a9e6c627c5fc6b0b5627b1a2a9f174d3c857881c8fa0f7b487421c962742c0e22c80719ed6f1fe2cda2c794a5436dbc9a795dfaf913809cf0bcfdfe878785f625c0cb6a3aa0da648552af641e69865e20c0f613871ad17fe79a0e61e7a188498451e833b4630248e14bcaaf08ffffd7b1513875599697efe0c12340d	\\x0000000100010000
21	2	8	\\xeed27dfe414beea101b3200522e6a5e051a361e22f5e9beeee132dfa1287ab6b112652d98a7e4a5602aaa81b77918ce2fc9fa059383ce4d8fc8d0b53c50c2607	24	\\x00000001000001005f4fc3beccd86de6a55b74551eed9aaf7a72919a74362c154806529b09cf98bb7818f14e4532c2364f32227b0344e6cb26732461ae6187241fe2671d329d02e49881729430ca90da5300ddaf74410b5bfce8f88076af714aae429b296d61b7603fb2e2a4f3e4a2324e4b5195e5ab76945ed007452e75a728ee13907379db1246	\\xba18f5543e301cd405d130dc122cd0504f16771e346276cc8986363be935f84b1a0e69b6350b7e81b616a6d5a9695445864827dfef749f9f789b653df7109129	\\x00000001000000018141536afd3f3471e48dd530d8ddd8e537b15c87e1edc3260f7183a17fc4942ed4f3742321d9685b2ed06de928522ce2746785fe597b87d097adcb70783f221894c45ec044f6b1a1ace68e833cdeacf70c10bafa5afa220effb273c0b275ec14ae49e612a4801f84537307b0f95d8d9f8cb1fcce298d4fbd81eae65ccaf7b463	\\x0000000100010000
22	2	9	\\xffa31ed7cd93bce162e5fba4a39b131da185c1472c8d3465abb8637a30ec83fb8aff2efb895f4d1400ae2db1b2bc787973c338ebe39a29162d004c02b137790c	24	\\x000000010000010049f79d823b481d1c20185ab70f29f8fc9cf261799b247169844d554da5d2e08fe0f45b2151e455884e8b2ede1675125fcc1dfb7ae58f953f3ee1d1fbdbf21f03ff0cf67423665ab09c4c25d7ca88195cc025889f2d567479918705a3be9f94f88e2a9c45f08a47ed56ad7dee6d5924db4491169f799a182f0b6599d8d40820d6	\\x9aa9041559fd8e026b9ecc6dd2289828c37fec21a2c3bab297907799533e832bef29c5f7d9ee57c3ebcc506caea604b0d67c63bb4c452e063d4cce3654b9fa79	\\x0000000100000001957f9320ef4a7b048d127f572d62774b4d8e67c47f72b1aefa94b205163be0b6a3b8f86cefb99f925ca7045fddb131b122187f813c92cbf116260d4006d924edd77c39a4ce663325d63345699fa8d3caffeeb68e11dc4108b08536b14086eb4255210daf58ac9811d593d217c9647e65f4a0941cdbd551ca0543fb7b046c086b	\\x0000000100010000
23	2	10	\\x7502ae1dc4baa0470b65aee498279095e2dd4dbd9584089045558832cb5f4d8ef66ce9410198dc9e813433b9c318fc058d56df48d90a74daec31f9f19490f60c	24	\\x0000000100000100a8345f5c869b9bcb9a1c93113b49f8ff4313b3b09d2d6f32e58cd16058d5c5c518ad22d1beee694382e3cdf24278754c2b580300932954e7b93f552903157007b1ce2a82bc9431fcb89838b80ea32dcdad871200f6adbddf2e65d8d1f7539118f980066b04a9ab8bd41a359db2baa7e074ebc2a09982b064df4dc4ae85658eaf	\\xb712eb9d914eaca5ff6405ad0168279ecd17fc8009abde7ea0998549782ccaa6aca4a2cb0abdcb1bccac4b4d42946ffca5120771205d2f4f9bf672b9f28946d7	\\x00000001000000011b7bf1694fcdb8ee042f5f6ca5446be5d081ee99e4d5a10ede67fd28eba492593b1307caa7131d3d07d9566670e328676632ef7d8de6096ebdd693e8213efabe96504df1188baae5796ca23b6ee0636530c690e4b2e6ef9f63a645906d006c105f44f0417fa9a731e3687b703a174adbb7236bf41429cee22b6fe7722296e0a9	\\x0000000100010000
24	2	11	\\x0101b6643e2e6e9f71f5958ab4d2316338d36c8589abc137dd73a1aed2485290a92c79da2d89613ae3732f39d1ce20ed179a71b935abdcac4255b725aea5f50e	24	\\x000000010000010021fa44a889f9a183cd5be2c77c6244eff5d212e15990d4c9cba7432bb73973d67dc61827edefaae3f12cd2ec7f5c0e59e6cf375bfc8c5bd169cceca1e84689f4817b9a58ac4423c12feca4225f7783919de454262f966ac2209bab3e8bae350ba167e5d0de0da02ec949f71ab648245ea0c3b05faa725e1230f7933d97a6ed59	\\xc1d760cd4594fdfade22ae517d8a66c83507e0953c92b66204c581970143c299091550b7aaf1cf4e8d5108db8f741b0de00aa46ed90fd002ee664e01519647a4	\\x00000001000000015678ca65d273aab02101045e8fd2c1d7fe0a85998dda9d88140b2a0885e8591f8ff8872006b5c26fe6d8f59bcf51aa206249d32a5c0583c48dfb32b8966133b333bd13de363ed7aaec8a7066a06b21aaecdbc0eabbd3d5a5fa1eebeeebe81d526be6c5dcbd4429011b7706f2a2ca9e86f939fca13c4e404156de0bc31c57d7ea	\\x0000000100010000
25	2	12	\\xab9b4f7ac9b9815159f98a96520a92c64c35c1e33890ad660c4d8776a60081f5308019545e6864dc7c963ea8e844e88aecde49145f8f07326817b4e4d4d66405	24	\\x000000010000010001fecbf2eb5c95346edb0827e6abb9e0df0b8697f1ff886525302a3f96375c3a1e71de8d8d327fef3529acb2b92b04cc091b6cee077f677dc6ad1f40985b09868e4aae3d62c8cd6d6790ab5a4f32387d30d282a48782a29aae10a88ea1d660d349905bc12d21a6026822539969d0df5f9a7b6256f6953c6fd7c20b15afef86b7	\\x85cda85636eac9cc56eee7d2b3674152732a3cf69850c01158aaeffca3acfbb1aeb6b2b3ce66da9161280192bb05840d2c8705c5583315d4c5daff5f06db0c68	\\x000000010000000116691ecaddc1cfcafef744a15e5b287f7ff26f360f8837222456047dae1b3f501dbaa136121ae1bd0a199ba82e762b0b9a12a3031d8fe6fd5a970b9e73985d64b306b502039dd981fd15f96e86699ada925ede7ec53fd1fa197522c419e1fa8975299f52dccda7bdf65d549457b155dec6fbefe89ef51e7016cc700f71279b13	\\x0000000100010000
26	2	13	\\xf08e2318d4f9d31e57dcd308e15c1af5ed6b24f4642331c9db50e5bfbdb5f5d1a3a66b80282ec6c76a6a44e306f820c7259aeafe22f604512f8d6184e2dc5704	24	\\x00000001000001001972cd4ef2a53a1df987cce0ac7eac85328e9f9d188c74d59b86858f73323384f44c02726d7824a0aeefe297de485dc09d830c23c0cd906a64772dcad8dd0407f01e9999699e18c6a00b98290e6a78d3f38cdff9e3c137ea5152e457446f7168dc685e39f7c90d0fcf2725af1ea5933ec0ca816d911ce5b8e8b77d0e47c5cfa5	\\xccdfaee85de5d674addd8d41a207ba9ba3594805e2e0ce44ad2e7c4f13979462028f72de61286dfb962151c6b0ef21d23433503070f235da1fdece638390aa65	\\x00000001000000018bffdfd97c4785c1f65731de3f5df5dd113bfe67e9497a0c5deb28a73322631d66ed883c4b819b08871df42e881a6c7bf8d93be78cf58ba3312f5348d53ab6d5ae0dc0e01fddebc6d03b8fc0de4373ed750fad22aa87082ceceb85fbfe01d2eb32871441aa640d5e2279a882721be0f49304709fb37a64122fc86f0eb1f68c75	\\x0000000100010000
27	2	14	\\xc0fda562ae0868268b59bbd3dab5ed4580ca9f4285367c93355d52b097e65d6144bd8144d7fa636301f44d4056cb19d4fbbcf7cff642a28244092a3dacdef40d	24	\\x00000001000001001d10955fd968c4b3863ea3a327325a4904f5d2d8cddb54583d9a7b650b7cbea7a4fcab82f2bc692ed4568e299dde7b29bb70dcccf898ccbdc708dc5871c52b955bb113bc2ca9f75006c845a45579c2e241b9c95117511c20ab394d777bd547f17c26d3298e4c9dcd10ccee2fbba28825a92fa91e60275eb3c1ccbe755f77b483	\\xaf034a4bf3f2d92779710f8e10c2c161065b8235fd7419e24a85511eeb00afe8ab5d697abc4d4f65452462e6c7b087b5afbe4d757ad32b171178479d6d7fd183	\\x00000001000000014c47207c21d3957e9a7b7cbd974de5d2627d225207a74fadb7e9858e64335de00418ef1555e7638b2ea83c793e06615e58f75686aff0b460e55c88fd181ddb8e1a4f2cafe42563e73d30dcf9fa56be7199d65fcf44b26040e8c4890c7990be32894fbd62b56bceb2faab16616d80d590aa914d9f1ecab864d05ed1798c012a5f	\\x0000000100010000
28	2	15	\\xac7741cfbbf63a11dec6b1f18e14206b4d8d1bdcb4e28b962ad9cedef2896beb95a077aa843688b102ffda8911c9e77438bb614db09d3d19457e0a38999d6207	24	\\x000000010000010019e38d88b2d7c479ba004946c861b218b5b4f431b13be8320b9710f85fb9d8e3f9d74b276188c7068339ca9a6ddc5114499166b3d657c5a9f7a00e3d87cffc2c98951c3452706bfcdaf8b71746d29699b4f1a48d39af3dc055e9b649719d3ba37601dc5ed11fdfa0e3d9d144b3e5b65f9f23afe5b45015aef2dd169cd90f4fbc	\\x2ca2cbf2d04fb4881bbe75afee66ea3c50ff8513b29e35e022d0e84c486dcbde06412da9aea0566cd532f475f2cd9e5327ea0e7fa3ac8025346e9ecb2fa5fb8d	\\x000000010000000184815eb3238596599989e2dfc0bdd017eb3a433a527917f33f6b3af7ee149f5aa7cc464daa2514a21ab4240bfd4728cf90b916a3ae1814925afd9577ae8f7bd0355b20294c959c8750745d2a665944b56fcc34d378549d2fbe919808b3bca50535e7e999a5d0255536a95431e016e4d171b6390dd9ae246c9d9f09658a251e54	\\x0000000100010000
29	2	16	\\x61f894b37b058a05df074c5b98254fca3c9e40e5c1edf76f9b839c203346e90a3da2d05665418a25cdc2b1a718e93e439e897e472a57d7c4eb054c41e282c401	24	\\x00000001000001006f090eee16ff0f643b511dd0d0c63b3536e0c0788c5b0d433882bdcf12ce465edbbdf4304d4e4806d7b24591a8750b81573a7a650151034e26802b7d29b3f33421625a7569475eea891c4df4b5e3ad6a7f461b818da477ee57a192424cee9b4eaaa009415b4630b8fd4dae4979c47f43126ffea1405f2b6abefd4da6575b77f2	\\xa08c71379b41ba0fdf80df982143c409a39862b3bbe0ae1ca7441a2b3876a7ac71b0b891592428a30a173e4592b4637b95e16ef43c1c7b99934dc71ebedae5e3	\\x0000000100000001206bfe12b91ec45d1606e4822c11560a1a0203e25a5cbee75a47d0ce556bc504bb78af9a380288e77f500fe1bd6accbb11ab5609e2d6cbd57dabd0a538b9d2ddbc91dc50099c7e2c6c4b0313731a708b67f36d2f2e481f1c98fa2c6fb71f0129eef7a7b68c035fba2f88e0385f1b6df77b7c8ff677e7feb106fc146ad56e62dc	\\x0000000100010000
30	2	17	\\x38d881f15f03d668289693ee8c429c6a4824f4fb148aaa86e364684e000e5307fb39a2c6f50033d1e2a4067723e25757a95386c74c6c1a93ed858d51e6f31104	24	\\x0000000100000100a458672857bf44fdd6b290d0e79a0534cab66985da9c298597d468e0aaafcd4d5aaec13297ae190e9d795c91664a0c205596355d3a9a3a757c08a613d0c79b7e0e4854117aede7ce428d6274198d8e9dd235c7d0626001640128b640d1606afee59826fe2419555c57ac17e4255ab5e90283490316ea04a3548bb759ae401e2f	\\xdb68d46196851e9fff69221b301db00a55ca6152d3b5ba273ea9a77879587fcde05dc3616b704a60ebe6e2f3c23748fdac0e91069f5d18aab1bb18dec7e71a8e	\\x00000001000000014559a58ad9f7ee9df31f175de9d8154626141314f37106d711cce43aaa59e2722f2d18e788fe031356cf7e159470a131922dda1134ece007094f6ad8c66b46969918c1cea65d221c8861f6f3cb4358d1f4337b9c67d0f7ebc4edab75684c58f6af4f241383b2b7b56d5ca61d0df21fd6ff188a067a60102143f4d4a81105bfe6	\\x0000000100010000
31	2	18	\\x9de4fa48ee3a06f32b03d778faa0a6a53f5e48f8a731d8de07e6732cfb57d77b05a92c1f1d2ad77794dd882a1f3b0b19b6bad6be7f14248307ac2629a928cf0b	24	\\x00000001000001002bbe7cb2b9cbe028469d63a04a35d47d41be53299eed79b2cfed87e049059dcac45ce616fca37736a45fbc5898cde4884ee2d8d4d244ed20d35ebaf7cc960e8b4673a66ed2482a3a07a1d86229a1d8432d950bd2a50122441acf421d84e4523743e8e0d0c4d4372ae97f34a5f2b264d0d06f875530d59950d458bee9edc3baff	\\x656a2745c6aff839e006f7f92f8213ff2183fceca4a82a6fa10a922499d1abe7d55bfd2b3606c66681dec7f3b4cf8627e1d8e8ad3cc7523ac626dd0892f98594	\\x000000010000000177c2efcac7bbb06f161a4293ba34dc3f63f37eddc0d1e469fe49cd79f0fda3d14372648c29d453004c6ba72afb4c08ac01ac34c08e9ac45e9301501e0518bd9ad7ee1bb391fe7adc4e97c8731b3a5ae3776a7276aba436fbe00a7b605dda4353c9a20056bd1fd5e8d0d2c3ffe3ed23501953b24b7127e8a46f029c5ea8b8f05e	\\x0000000100010000
32	2	19	\\x2c995dde08b0061a83cf21a38964d330f217f70d09e94f4eec4feeaf1c26806d237d38995fbc94dce0d7014369262e5c1ff0bee8c0d06d5cb7ef4f3888061501	24	\\x00000001000001001341fd68e410f9b574b956bcd37ac705785a9c97ccfca0a2558d701f53c995fc55a018e462dcad5b3ebb71efbf61acb5e2409ad74bfe5e491726b21ede58231108bef2d5aab76bd5ccbe72c7ba960ec29820ee1c1189f100b3fee2a19896d0ea2b75e2c2d00e87c26eb15a8a899df2ced60ce73eb56d726fdf7d40df8acf306b	\\xe8d6a8df3fcac04810ec0165825957fd5ad0eb3984363fb7c2a226582bcbbe823c2ccbd6730d89b7e94456cc0ada06d2908dc61a0cb99a1af86002a418bdb2ec	\\x00000001000000010dd650907a63399567204de5929726c0ca29f6bae76c8681e70f487e6210d9648c8ca22321b3b09a25698bac487b92c6ef5ce6eefd9227f0092f7cf6f2d5780a45b6198b9fd00a4a92597a57276eb0f6193864ca10aea365a9fccaff1e7699554b2f37b724945feec4979af02387198b2836b44c989cd26150191313620e8346	\\x0000000100010000
33	2	20	\\x7eadac067a0eb69af5dfc237d1b89bd65b17d10c459c8f52e5bc2f9663301d0f8337184b11b74bf9bd8c89dc8c85b88abdf7bf2624bac4c34785d211ba0ea503	24	\\x0000000100000100672a9f31e8dae2c4afc91be7c07f2247f963b5defe642847534e696bdcb4ab4c67faf615786b47b61fbb54b7aa9ab5885e6a1d1dbd0241661b3150e5c106c4847c67a6a54662f797b5cec02e9a2ddcc23be741804a98848a0004e853bb0386dadf19aec14a4a10a121023dfb9290232f9e35215316a013ffb79ed12ecc27d51a	\\x19074e9d6827574d234ef2d384302403649dcc9a4ebf077a70b6f1945eb23c6862d121d2783c223acc8a67db4043a9de650754ef83028cf26c3cb9545cd30183	\\x00000001000000016fa6ad976a8d6daea14eb86afa196f69dcfaeffd76838b93490c779358ea6b49e39816b2c9090fb207566e06b0ed0e3da9ee047d131e80d3d26d26fce44f4e3b1657b523fca92b317fba379c330f3cfc49f254d1e0d32a9666505ace33338c30213d94226b8241b508bd2f1a2a364a3fc02099dd6ec0602133f85d283002c7b4	\\x0000000100010000
34	2	21	\\x006dff1148711003e9ddf7d8be853bc11b929cc5653e190be58a8042c69c5a6764559661b9a196f2a4d5028cc6e0e0a39d936c6ffe51a3ceaadb9120ddf22705	24	\\x000000010000010004fae88ed7c7baf16c75a9e5d2f19ee68d33fbdbb124e013332068050bcf0fd37e023a6d6f0fe7bc0fe0b2920162486313a3e07655f3600815c3e243d88b496da4adf5b2f086cf3dbc7d3f4439ab5d3707da54576a2b4500e4e69b35ce41790876de0ad7223fe4918426fa1aaa3ff5019da1aa92d048fe6b7c9eeb1a5098e9ba	\\x8a64a2928a932d11a205912277ccc5c14c5968309072e314c846aca6b86c0a50978ce8b98d46ef4cd1c29102a55885b46bbbfbfa7ffeae40c632434765c01fbb	\\x000000010000000150f3ebf87ed4a559d34757be43b654130894a5665d4548b1e6ca9dc5e40da3a030b284f69a057d24becd139b618084260a9445bf261136da35120a1e836e7f2cbae7223253c2c71e726f247075a85d5faa3d102b7dbe46c0ee80d839291c647e2b6b84a0aeac562e833c2faffab0990f2737470d0bd952dbce2537580a220f40	\\x0000000100010000
35	2	22	\\x43e70178f61c9fda922c8f82c931cd05a07ad419991350288a572461c3400c57d0da38c7778f36a085514a2632739d6afb11a1654132a8c7fde07f1f3d271d03	24	\\x0000000100000100060ac0d28bf1190ebdfdd3ec1bf8a1f4a2ffcbbdc6a4ed61e055c1130d8ec3f9e810202dda84a795fa0bd421e111ea5f36ef9f864680997d235cbce5802ff419c7910b5d21a5afbfd14d7c197947ec5fac2bad8a1e585406592ff4870b21a8dd7338c605d7079e7272385eae1a92408faccffefad01b15a19f11805e027a245b	\\xc7cc47476f0747cae4248e9d5e58feccf7bd1feaf74635b11032a823e70b2ad76ab22b958e79fa864e966e789a783fbd99d5156fc8cea935857886b94b2abaf3	\\x00000001000000011295e357026f845d5182ea0227bdea2483838df2f9ae71410a595f5f4b6df6abb3be627fc6038efbe840835f6a9c1a63008a69b12c1a77a763dc6522fd50067c9f14691dd509402030f449083e5d60c3c5ae704ad80a82afd82f4990796d6fda1bce2884500415f9cb05696f050d212386e8089ecaa5aee7728eb90bc3dbf8b1	\\x0000000100010000
36	2	23	\\xb66c003018e6e4d305e5e89dda6dd0d16ba117cfe368156161d87f790dc7c87715cb6b234d4aa5ce34524d0a35fb4e2b31343a6d533c12a63be92e8cd3311b00	24	\\x00000001000001006e15d12ffd7b31092870d21fb1a9c726aba53d7ed6ce9951c9a5dfe573070645b3ae11fb21f3cbf3b7cd276aed052b19039bd111a8bf9e1db3088d481d85e23000d3b48b3f9058c3db1084746627273d16c7afafcb7ae1d8fe2e0235115a2a7538c1d02f7bce2f460cdd8c79fe30a42ed2ba59b88498d88bacca18b0679ed074	\\x2ea1fd87cd8b83d9c568c33f990851ae5cf92fd2a57304f47d606509e800ec1451c6876c903db7cfa2d9d9f23f9e9e879bb4aad96892dced9c26d58bc58ae007	\\x00000001000000016705ae639882943f2df1058c4c9ef9d60dab0f25357a63d4c5a3cecf7664061387c5f38abfba1bc700b505bbbcb99b73df216cf8bf04a21610194e1a7fce7529db7cf76688e3838ae4f097b364f7d6c57cb9ebdf05172e02604d0d841b14b32f8b7b6c171df2054a3dc758488fe3fc0f631df45bdc9b9edd4411512101f2a4b4	\\x0000000100010000
37	2	24	\\xc2cd1ce00457d84b1a09f9658d4ac68585d2ca663db6e0fc369256023f51d0ed2d4d1e5568ccbebd0d262222a30ac9d4552bf7ce874011b747e17a41cc863f0d	24	\\x000000010000010026f2bc9e8b548b1a34e707f2a6465b92d0de43312ae2012b5047a5e4242dece4080c4218e2a06edc6488b4ef76f0106b6c744dc690f074783ddf20196af7dad78c85e4506cf372365af7af63c7c5320e5500de07c2a1ed82a65469530088ea6a69845b8af1e36e108a7b7d62342279cf1f91377bdfea4e6765cb417e583106c6	\\x560e978334fcdd6c364609ddc8e51a7a06700c9326d2df7c8a65d2d2ebc96f9de770644e39b9a4ee8a19e027475532b9f78fb02e52bcd3096442adfa1097d39c	\\x00000001000000011f3a712aacb2f712797737ab9ed5bb540040abcb9f056c2750334545189aadce1a81f1e76e2638f45b19b55cc55ce28e11ec8e1877575b9f0f5ab6ae3f3bd47310f24c9a042787d2e8ddb2f46aff4ec4dbd3cf9d8154ae663f25600c68d98cd494faa1f5ed10fe6be5224f348e4f27870720a51ab0b1fb17e09f0047ac363919	\\x0000000100010000
38	2	25	\\xcc57d2d0a81b6e68b4cd4cb5de7099267636956f1cac2498463aa1092e6818ea0e15776e54c10235eb45d29130ca15f3c9462418134bf9077a6ed403c2a46006	24	\\x00000001000001004a99596847f9889b3b74e396636b67f34be7e15449ed29e441435c28671553a675431ecca5f1733358a76c9f1822e3a168329174bdc110364a2770bed6f5175cd09cf55d955c76b4e6e2cab6c4bcd705af0fcfff49dcaf4e99344e91f9ea5ecb65a4a1ac86349e51edf6411204a9d6c289df7c991bd042f4d9b612e396c46f8d	\\x41d0e2fda7862fc74b09a49bbb31addc94c0ab8f71fd1bca72806ae75e8f8135c1d2e05c8a5b1bc78be9401db5dfce7224df5369071bfd8581dd78517ce58b93	\\x00000001000000014628879ddde504edca98ef8aa5e1c2222cb018be1112fdb2b592943d595e7cad20d3b20a317d3f1fefb3adc68f4dc070dc14c83025e486074fc1e6e85a6d9ba90722041bc909e31412b99b2876821a73e2a10446c9df0ba8a88917283defb673174d9283a9ce03b4cb4a2cd0ca1ec5e4167bb8adece0885718b9c52bace2c5fc	\\x0000000100010000
39	2	26	\\x0c0146ce514a475a8426c98de5f1c422318bfd632be7e7d5248de185dc108db50b122c25fac427dfd2ab93d97c8ce0391b6b9e2900168f32d0b8bffc9d2e3101	24	\\x000000010000010057a9d5657fb52b676c2ae3edd5a703fc325bd220b4fa25daba110af34ed415ce4e10b980b12221e401802d1f9d94b9faa6933db618175761fb4c67262d7c4a10a48237b3988acc011a5bc507805f56729b2f4de97a9bf05e96d98a60d192af838a973db95c2fe02d22d2bbebcbdcd2e9de7d693df55a723e416ba06fdf3bbbe3	\\x93ee32e4b41ebd5ae77bd04f9e1c213273feccb0014febb1f705c20509e28e6afc6f7a0667c862428eb9d92b7f67cca5f8730aee5ce7174154bcbc4fd2369c6b	\\x00000001000000019f7e8b05ec89b29f9604f4da1c4a631ed79d86d0cfacbf0c8a11e1776d709b1ad53e3ae67ca6fac8f4a3e1136b3b07e53f3e275ce5e89278e6c5d836f8b729349815e8ecaa5838ea763965a83e661987524047905a6b551647a47dd8e740985659e651dc75ee3f41fa632df29e473c42a8c36fe19677db251f2842cc50f30659	\\x0000000100010000
40	2	27	\\xc6ab1f38dac82b4dc5c097883b5ece4c3ee418762a5bf926deead67d408df155fa0d3fb750d4a9d2ca4dc8ca1c0473f8a2aa7311c0db056c329470a53a05a603	24	\\x00000001000001003d774658cc6116d78fb82866c65fe98a2bf8509e187697ef05d43c872de7c7a32ddf3afd8f169ccdbc199a8ccc4d4a4d9a5b2e807d6ea05198e92d51757f9fd60c14c3246aff41c6f1048eeee92cee41c26246062731804d422f1e56939650738abee0b1288af6743290056d0794ab31c14a0a360d9a844c0ba351d0e0241048	\\x42497844491e81aa1b00bad6f806a5d29b55c57a4aeb4a78766ad6eef0ec8c2a4e275831093440a1054589efbcd29b2805da6a45341100853b09adf97052a917	\\x00000001000000015eabec95bf6c854c724f9274308f8dce9253e7fdb67628f33b21eb259f5aa708de42f6d019205a9f40b2830938a026692486cabe472b813699560290b6f0c914b0be0c0112366cc8e509851df0d1aa9b28281e0be2dc75aa5cada36a6082c99bc44c3823f254c1853951d006ba10c6dc15833b3126b9b47cef315550b229b5ca	\\x0000000100010000
41	2	28	\\x84fa0f4c93f1583001b32781533c17c8b4c01be5a254d3aad3a79afcab67d4960c08e67fd062a14736b6cb12433a0d0faae146fd1b594c056545cab109b88100	24	\\x000000010000010067477125ed99f3cb37b670ff75c6196cd7d377b4007f69cdd8b0c5b17769b419b7f8e0a92d2e7816de405e2b96539aff3090a662a236c09311d86167d69add6fc83657a7130c0cd542ed4b534d7faf3174f7ba41a471d7e3bbc381122bc602655e8aa046235866f8f79e677cc6c333221d4ad205becdc37d823ac50ba7c22929	\\x0719fda3ea80151be90fa1c8321173a9314f39acec5480eaecac43e4a7c3c5110ffbfd1960a543b47904bb0b74c6f47d5b39b4ce79da02dd4f54093fa10a5fca	\\x000000010000000181e60fa8587aa3bbd29eacc67cf113541fe5e8e4dc86fff672043dd40eb2e19ca746535a1746c521d1bc727998b5a0e2b4d64f454c202c84f68734262817c10ee18fb025d9503d62bc202d867246494d92c69789ec54ba3fff84af48c84c22367caa8e3b770da08582683df8e9dc9a77d9866a51e056c62d47d2d56c5f1c33b7	\\x0000000100010000
42	2	29	\\xb52930e32f636e19c64afbe5526c577b217e5c29b332855ae4b3f09a1cff41a805b58f252e76b6f2e372e7ed50e007ed025bd8bce3eff3c3145cafeabbff1c02	24	\\x0000000100000100210842aeeea3276a48d87417717fdfa9c6afd087e142864c035e23c944303472597b2edb766dedae1397032f059c131c4e6f7ddb0559eca2b3b9f8fd78b2b615b8db3ffff9c055ac3e4d08053d18584aa5bc725c0b3e4388fa473af768b73b6984a8d7795865d0ee6eb24a016754a4e7d2a1fee34eb64bb055091405f7d9bac2	\\x0308873e6e423a93ef13355887fdfdda3c1bb72ea67168e588ffdab864a0d9840d4c962cc0beacef6d2cb6808decc6dbe8659bf57ac9f310a808af36d5e6d226	\\x00000001000000015d7fe27e7ca53e4fec400d275efa39e070707efd6e10ef7b67b6140a8eba1a3d9d129beda49757f8f41e23efffa60c933edf0c938c214399b00e7413f1c491528a9e8a68cf8a548f64860501737e5ce0aff03c4f35f6f4b10579e6640e39170123f983cff999ead6e95d1de45b4898a0df4c14df1910b84abf41abfbe938a894	\\x0000000100010000
43	2	30	\\x787a655a19f44a7317ab3e92e5f5b417a361e6984979a201af8e53d05021253798b1039db8c6ade87b2f2bba8825bcd6fa291df6b8950c2dfe8e01a1984a9c02	24	\\x000000010000010084b923920f86886be0ca75b59b0c14261eba64388cc3e4fc57e4c6eefa2a61d3347d5e22082533db138406d8f1aff1638789f823ec4a1943c4a0e7012d4d0bab1db7724a23be82371fca05b9795d145efa4aafb58dd26fdcb6dec1d815bf76e62a23922157fc0f2a9509234fc927628ba7c55cb6839acec7d1750974d11676f8	\\xd640dfe53c80158c8468143f5ce59b820e3da62cec4573fccdf82716b5eff86b77167a6e23403cb3af8ffd02c988d96f046a54406d398b43e88fffa67be5d0d7	\\x000000010000000176a929da5cc2a3c5f2a92defde084fe492135eb4689dc13c5eb0c2fd7a3d07a21a93d6564300f99dfc2da270464955631491cd41471a445259bd5d6dfe170ab756aa4f170af1c9e0036b5c39c4af7af83a8b225e8c22622ea1c2268e227bcf6be77dd44686d3997ef1b7928e81d278007e2087fcb92e571f2b467a8b98fee074	\\x0000000100010000
44	2	31	\\xc9fb40dae4c6cc168a1aada6e9366e83c532546d227570694ffce1067fcb563a967d5444c3151343b6d5c8e450d6865bcd10776348f631f9297737d5222f800d	24	\\x0000000100000100976267a9f54ac3e4704781e952001873d10324607dd735ca2975473f83501bd3573d547f53cccf23a085fc88a0b7a0405008e136f4efb11da5e900f45b540ed5bfbb36d296cf50e2d8180d932507763f23c312f157ba3d697eca1a6472e107e5361909e4c8ae14193d398b1f7e61e4ba6764b7819c6e324e4b2fb96aa388a98a	\\x564feda5658b31be32dec51af7add3a5226c25a7676af174cec8a0b077ea290537f07bd5fb7b516e8dbb81bcf97715cd98d69ac9f5ed60f52eb9ea31e6a1684c	\\x00000001000000010a058d457d68352da18f3b97f07a2f79b5ca06a07600e1bcb0d059692613ac8f075161e8557b893a6dd3c37f93e22971884bde695747087f7f397f24e5d3d027c0953875fa4e200060fe415c3ee2f3c08c494bf360217ac1e47512eadca7d3df47ebabdeae26db27be9b16c986c0aff1ce0fbbd30f83d4a8e77e1001127323f3	\\x0000000100010000
45	2	32	\\xbabeb268b40c97ce23c054eda620ef090149de967d81b580ce8f4228a649722e69a608bcc5e599d63543c5beb2668861c03409882d7ce9e57cf909c490320e0c	24	\\x00000001000001000bd573ecd5d910deb04fcf7932a728cbc50957b755e9596a9f976269dfa4d9488863f4dc4b6065f1ecf3b4c83b01fada798d8e15027c5109483942439071b4690b6a556df23784672b02c34b2a193cf34b0131973ae71676184055143d059ebb47897623e379500e8995acdd4ea888b8f8470d77bd60d4e97a0257f0b12bb948	\\xe41bf7848ca3d434357ab035c6d7d5c976f044c7922369dd8fdb1257f45456fe2fa587e6de68944eb3f95c37a1b1706637b7d4832a9b846b5552d425cf99e95e	\\x000000010000000177ee7ee3a6828867f1a15284c842d0b42a2229f6b8478f7efc5c2a0928768cb51504f84cd982351f9d206b39a283674b07f3253a09a3d9556a7d9d6057b65c855632be58735998efb1df8774d00e2b2a92f3691120a28a59609904af3dd1a26e24f96dd7a637fb1b28f3c83f6581f7a8ae847aa78f78f411aa32c07c28420ac0	\\x0000000100010000
46	2	33	\\x0e3aea18d7a88b08c9d56ee5182fa44cd6bda658e62a08a6aec49fc129ddaabc8b0aa3cb9f409a29668342b51cf9cfe3e07f1479addf186d2ca3d7581e358e06	24	\\x000000010000010001f7539d4f70843b1c83ae07431cc87bc2787de7a6f003f1a522dfbb37cec7c502a598a1219a63e1b0f3ad5ceb86bbe5d41e5340719263b13a6f2f80dc4f824ffc070b855a44add677e7496b3e80f73ae467c5091608a42c7c37944b4affe4accd77affb5787655fdcdfd211758b9fefa8609cd5d09cca00f2dc20b98464372b	\\xe26e6a91af8702af0bcd056a3ef913599f600e0e0ca4d6b5f0b66dfb078a753ca005db0169f7ccb5a797fe25130a155dceca1e1acce823ef9a8dbb046047790b	\\x00000001000000014e97c119ee116e3c5354b33a48fa75c0a42f69e89b997fee456383c15aa0ef52103e367e51df94fa5403bebacb40c763b256519f01ce6fb55dd19238ecc3d879c2d02317118059ec9d1613bdb6ad90c0ce82fe6853d4fefb4f383ba0561ee5b32bf58ab6204ecaccda02e6cf11a2d9821f10dcc23b5795051b80b328fb7aa857	\\x0000000100010000
47	2	34	\\x352c0f0d499dac186b07dc803bda6b15db8b542ad02670f6e59928f00455c83ef830e8fbdb20265c201b6382581efebc354ad87bc2d8d18578f625707d1c2802	24	\\x000000010000010014e2ef1689a7621283e3fefe0de76a3bdf6037fe73a8b235aaf6ba5cd3328b68e302eb769df058a3b0ff4e791b67b93083bc1f12f691841c5abe757803a0524c8931df642989796bb0717f404f313896a47d51bd65a3dd1b9b665ab630b75507acb5359d429095df1e15449d69bab6f9341395ac8bc26ee74b0519d9480a54d1	\\x6c02b75c8c92f7c45afec7ede76bfc6dcef8bb1031eebe98e3023c1c9617b29b05870e6cd17dfd9b1d3898e3149e3175f4bec1b244e9b07f17fc5540e9db7ca7	\\x000000010000000191963c697594312b85b433b881659d3f038513668aac49d801a5984ce8d3bdd8486d608aa383d30bafd3f27f20acced4b089ba44ff7decc13340b0c0be5a6a4ebafd0b5f2e9b04ac890deaca9c1492c9a8b4c05697a34368472296c5d3d85ebe641084ed8b86f1c4727e0b401f367f21b44a23b4cbee4f6ac8ce4647a3bb3cde	\\x0000000100010000
48	2	35	\\x02db3572ce777fe115b15e632920307097130e85c8beb62202d1723ecffb932d7d210e02759cd3c91a4a1441f39f468614642859c19aff9ceb0033b1d4749b0c	24	\\x0000000100000100426ff94847b63c451aad219c939ba15d01fad312081b549027fde0347798201867dc32296e22f2c0dea976f86c7d0b4403b187cc57c34d8c0f63aca99a4bea06feb5edf3ec486cae893f3cd3aca8a71f75f6a44421fd6c6e5dca50f40ae540ddaa9daab11eaaa5d01e209d748b3845c9a35cbb24332f943f37007152ddd455d8	\\x65fccca48685cf2166c4f5814b792cae06bd898fd677b207c9759f29b34ec6ebe687442a36bcd090c445a6e8261618cce6e3deabea15d16447e60df70ad89376	\\x00000001000000018d25ae8d681ed06db8b7df4f15bdcfecd898644c8d72dd415f29a07e08d95c6e51fd627f75b23346662ab2d75bac2170f39656d6bb3b096aded64c61b2e92a9eae4067d67d72057130eed9001707c3fd1f9f87fc30b095549571a3d1a7827d74eab306284af5b2ecf40d5591ccb3eb5bb72826fd070c939bd641dfbe058172fc	\\x0000000100010000
49	2	36	\\x744ee1c8b4a537af2f3ebffb497075a7a623b1a2edbbdf6ad2f639ca3a2f22c79e3f617798ca9196a6f086a8f5a51b8c057b3feb6f5a8a3ff363eb72835c8306	24	\\x00000001000001007d3b0b3f6af7c46158aed423e82e98b087a5bf080e5201ceda938cf5e288a48e908f4b67090ffd662112c6e74fbae05751f1bd6e97e3b97c3f0bb4d261885b6022ecee06c3cbf242de94b5bb6fa05cab02411a9779e2aed5ad0186d3ccb638b7e2ad2147fe0d7650c98f0295b3bad8a8d4f005204247f47902d28efd6caf9142	\\xc12d0e743a1efc753048719f11fd6aa27cf7b413b111a4b77fabc6a6c6c9eb1048de13cebbbb7252b2ae0063beb5b05bbcb0cdec21ca81c29fae067e31515aa9	\\x00000001000000012cb00da2916ac64c1e8ed7cabbecc49eb22687a8dc1bc365bef574a4035c69a0e9c61eba8325c59e39b1c0c784c5d5302e062ab6d52ba483fb6c7a0e6af7a074fb584d0ab423a8a2d973be1d6d30d8f9190ff8cf18f72d35cd896a26210dbc5385f7b05e57b15cad90d0b665cba3deafed421ccf69776a327fc4ca761b85dbf6	\\x0000000100010000
50	2	37	\\x93135d54e2afe44a9f1da54021ece54cc6f42825d348d2604b01405c56d3d073d4021cbec0a879cad69bf3e54a52e2f02300c1f71d9c5e1268678ce2af02a605	24	\\x000000010000010040ee4957c6d3cc61e1396ce19bae66b5242478c6bb75673c5ff3e32e20b09c9d16f8194ef31b4fca58bf3d504bc7f2711e6b84d0f881b4d7a91dc851ad4068e93441abc89a29ee9921457a3877440031b6d90eaf71326e76849abdd45830941b737849466637f93e125a9fb4cddebcd62fd71c2ee553b7ca34de4b03dc6f6d24	\\xd441a51fa8f225a32bd92ece01c891960b8c16e03e55a7ded853d1ff532aa649d0a47741c6af9ca96c3025d77402db646895c629f5c4b4ccf0d54b83f7868703	\\x0000000100000001684150b41701f1170d630ca14bac00ad2d7085344c2ab179d921dcc62d858341dc6dcc04cd0b60ae6631bccfb8bedf9311a41c4323dfcf60ad1ba4d865a3f25a49d52ce6adccec4b74a6f4a57451a7a72f3d5736a99f9c5795e13215b28b73cc624e1f36350a588096cc1572ecba34fc0cf4b83fd47404bb74ce5eda6a989de0	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xb322ec916c6421117987974f19611c26c699635f495ca923b162893207b39c0f	\\x28d9f046c6478fe82970ede8fa7a6fc82ac4abd166d5446bc26e16758f656cbb2491af69062aac9f27842516412a12c2d2c96e06707fd11f307af0828ec3d30a
2	2	\\xf086b4197395ec6414e4913ced43b66519d74b889920c67aa282d79e0c5dbc14	\\xb34c4e0459f3c23cbe9fde53efa8dde0ed690710e61701078af571cbf02cf5e978b01f04150f27143161fc1735d578643dac553c6fee78afe7bb71caabf5f250
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
1	\\xe44ed86af1bdbb3728113b084633aa0e8bbfd7dfad34be67c5a917eb570d438b	0	0	1649765278000000	1868098080000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xe44ed86af1bdbb3728113b084633aa0e8bbfd7dfad34be67c5a917eb570d438b	2	8	0	\\x3d23e5c0bee9838dd92e267d7e9e0298b1bb0d5efa575baaf150c0060821574e	exchange-account-1	1647346066000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x6ae20b1a4682c03220233499dbb698d0753f0cd28b7e26383212d5d79830eab97bf58862242fddb7e91d8b5a21ca97a27c1362c8a15549e786148754ad9a19b6
1	\\xd02a0a5288e1414421432b9697ddf2aa3007993359bf32545fa552a5c91c39088b309966dc76f4ef9558913a36a4e3be667c85134cafcee08bceb9d15aded5b4
1	\\x03fb5a74932a6de796075730922603e491985c5c4a01841eafc69bacd2ebe891c0647e37e3a851198905b47df148c592356d0f794ab5926a23bd3e58d8160848
1	\\x4e02a59071bfecbc9030732cccec426809185b84f378240e7d81fe37f1f8cd34a13a24fab8ae1c9fe0bec35f9f0b7f175a255204b8a54a5001e5f9c0c39f4b44
1	\\x7ecf5fa62be0171cc64800f5f60d6840610025d6464dbecec151f8a48a1f33fe0b8c26f4472b8c4e851fac188bc708bda1e790fdc01d87fc442a2e6221cfd858
1	\\xba48cdde27f5ef34749a4b56b45476480500a78892da34494e01bc5d6ca39ff59c578fc65cebaa403800befffb3ad7aa9e6d4050c203da474e199e59331c6227
1	\\x5e896a5ce290c7c6e279a66561019b82c623199a81afe98ba958a853f98898a03fbaa177c39a73ded4c7be28492bbaae2148889a2a2ce0ebc0a351f5a6e75f08
1	\\xbaa0db89b7cef3a8116995c553dc44a191c01851ca4ed293bbac436360314a53b3e7302dd8eef1d661b00b14c7d5dfc12d0e045d524bdfc6bfc18d93f4a1c273
1	\\x1e5564529edff6f9fed06e8355f6269765004104fd2c1b5035c1950f77a0831a1628c634518275b3f3d0eec82210380bf8c6bf96ee46a7a3e186430899eeff03
1	\\xb9a50b2b440282ffd024ff1c7dfb6877277e6de18fa862d9e5e8136f5632fa97aed79bc724a61e33073b31645df7c13d045635ad46fb2e58a40a8f717ca2a4b2
1	\\xc316a88d68ea54608dbb7c31a761aec63b04842eeba7eea8c5a65b694392f3bcda8ccbac0ef579453230fb54184140a986a8f59ce8fb30ba9503bb633817c69c
1	\\x461962471a93796d0ec3632d375bc3a5fe54425ab57d3bda0cdd0f2a08972a3114c9182ce4876c5cad701065df795ebec1ff47211551e9d9394d4c31dab1c719
1	\\x77cb0c26d8d6c74ade48bfb198762c44e404b0e578abc71300a6cbf0ba2ffea5ce9504bf70673c53aff5c0833f5de73e59b7d27809ae2c6922ffe65777737c5d
1	\\x71a72ed4f06e897d4a47182f556a6d90bf5918e7f4f3fe511be83eb1120694319b5e1515f0f0a5abe1abf8b082c41c9de03ada0975bfe688c8dbfc4d27db859f
1	\\xc1c5f02324a3701ce0df9ba503d0f0a70855a2937792e0dcbd80ad3871f8569c30ab9c224bcb06fafca894621c58f4203f3c3b70d4256af7dc59eec1fdbeff3a
1	\\x8bf2503aad05adefb0cf3dfbbbb68dc608407609b44570213a3695602936fb7772b5aec9b3cd6dd8878392bda6da0da16ef2a5b9afa9df056d46e7607b09c0e5
1	\\x5e72e81d33fa62348dd88195c9311219af94264204e035fe97ca4084b8aca54187a738dfe15b04dae24786fd9503b87b73728eadfcc7932af70bbe12d3d2c410
1	\\x41cd35697d0f5050ce4db5d96614ab9ddbfc2c0305b77e0e1b5603add04df822ce6329b14b84c7b4d18e99fbef691527d9a73665a577f875985a08ea3dddec93
1	\\x1e080ae3c843337c73cc7060bc6e991e77d046e8b257377ea6f05c027d088251c8e61dde0673da2c25321757d017686f3480314460b043b5f3e7d29557b57720
1	\\x25bd9d9eb6c4bbf2ecc34e98d96d4a1ca28982d095a51dd79d38848d04f0485b6f8d9d9563b3d4b883909fb934a9f873968660a110c0453b1aacc23d819d5e4b
1	\\xab61d5734a5d2ca9a01ed85c9ea7b326bca2dc18fbf4ece496b7c85863a3687a70f58d85d8efdc8d114b9c936e3928bf616193a7ee39702869315e94e8e6c2ae
1	\\x003f5420b1cfccf83352ad8be6ebcfbb77366181790a01da58416e7fb625438a502baea47e0b62f269c9ea8de9266e49e869b39d2ea072f5c08740555383db73
1	\\x7e911d6299864d9ded782f6530a5ac5b815a9d94a6f9b049ed300730f2b1848038d4c1fdce60e6c62309bb4917e8a015c0b80c0d2193f5576de18412bea7e865
1	\\x6aca6b478327ae2f47b0a79e11cb8220142bbf259b55d5d7319cd0fbc5a8046a2bcd51558c24f01b6f10005bc30b74262ec068a49bdcfdc40f26cbd84be94252
1	\\x796aa3f7ef54054d415c39ea487ee0429d320b1c44a5413df465318aa04d22e83d1e8766d4cf24050478035d4f7434f3ce3e0dc9eab3475d93a5c81f25c806db
1	\\x291c33ae682c271ea60823b7b208fc537dd49b0a8cbd792d9ec176045df9be4f13a5a6afc448caddb7eb8b6f686eeb7bebe24e43b884eb1a5409b4da2dec605d
1	\\x57c758f067310abe871ba5183654728f73cf3d5b7ccd57af7e2b68824121cc8f03647f2b34f391cfdfdec38970429bef6bd1aaae84934bb8cf396514b7e74914
1	\\x45af8f3cdd1e3e5b5e9acda092453a8532d0582bf5c7065c9b3bd159f261e6888ffa7932243a2b9b3097c3371896853784f32e53bd746791cd0e129e5ba9b12b
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x6ae20b1a4682c03220233499dbb698d0753f0cd28b7e26383212d5d79830eab97bf58862242fddb7e91d8b5a21ca97a27c1362c8a15549e786148754ad9a19b6	268	\\x0000000100000001997d8e1cfdcc0d0ec06d25f7721159b7c6cf905849f779625c4a798388cb3b519f05d7924972309f76841650bfc5a63b9fe4499d5f9842bd2a4c75e2a689c4683eb18dd09759684cdfd07cc2783542ff2aadff1744cd60bc82948c5ef8b0f5de94a9f0554064cf5e38951a16a724fa90f7d0d4613de7b30621ffaac6693f9a98	1	\\x6a083ea61b216fecaae49a9526f52d0ea7e94b4437f55ecd5bf33184d439dd5d7c65185c20a495418f42412ab76b2fd0bd0f180111f20fba8340c1e6dada540e	1647346069000000	5	1000000
2	\\xd02a0a5288e1414421432b9697ddf2aa3007993359bf32545fa552a5c91c39088b309966dc76f4ef9558913a36a4e3be667c85134cafcee08bceb9d15aded5b4	259	\\x000000010000000121adc12a4645e164648a839d09185e363f68107adb34e5fc51992b3d41eb48338664357a05f1cfd6e6a3317ec6b41aeaefe1f741bd3febee94cc6fe0355366b4d81ed367e697cd302c30843cd4359d37c5f5be646c8b64fe86ad155a35f9ebed9b379a4a562739a59960d5ff87333a82e799c8569b6e26c1df000435a7b21958	1	\\x72e87d736c8ed454422b9ba741d2183d35342f78652cb393690992fefd74f67fb476c316063abb19d91ae997b2eb370f8bda279f853d50d61afe62dc36e21709	1647346069000000	2	3000000
3	\\x03fb5a74932a6de796075730922603e491985c5c4a01841eafc69bacd2ebe891c0647e37e3a851198905b47df148c592356d0f794ab5926a23bd3e58d8160848	85	\\x0000000100000001213f447d79f863bff325d97eac45bac59e78e4ad51ba2985ba44fae6c49f3ed1219e6f95ef8ceba86a9dc51c9cf105d3c0c926246f7b505abd3ccb2b3e088e0572f6aada65f08c93db46c5b0d3e3d7bd1df2c2e806bfa4fef44a11d4cdc605006a03f92496c6aa40964718178e54309fdb2d7f2554d03325f6450e95dbfae9b8	1	\\xe5c58e3e0a91c3e5d04c3ac30e34db0fd534a820225ea0b1145c4aacb6b73e516ed51f37bb8bab283b90c507c09dfa5bd871212b795806c601121a47f2c27f0a	1647346069000000	0	11000000
4	\\x4e02a59071bfecbc9030732cccec426809185b84f378240e7d81fe37f1f8cd34a13a24fab8ae1c9fe0bec35f9f0b7f175a255204b8a54a5001e5f9c0c39f4b44	85	\\x00000001000000018a44f6db57e6e92d4bebd70b53ad11c35c620b68c7b4ef4baeac4634b09856063317e5b8d121073c96183cb8930d4a94507ff5613addedca1144316a77a44d6ec1969a1d16fc1c2e0517e7ae43ca69d2d0bd0958fbb326e484a82a0426d7b7b9e0a8e1e17e44fbc6c0435d322f3d68e81424b43913d8f993d4723ad35e8fc8e2	1	\\x32a732b8c87a2cae7d2ebac9607f53dfb6c7bfbc4737084ed552156e708878ef172349e6918be4c9d3f001c0a8d2a044e55d4a251992bd379aa1b91f90639702	1647346069000000	0	11000000
5	\\x7ecf5fa62be0171cc64800f5f60d6840610025d6464dbecec151f8a48a1f33fe0b8c26f4472b8c4e851fac188bc708bda1e790fdc01d87fc442a2e6221cfd858	85	\\x000000010000000137644825d5048d18f142e0d247a8cd81635756a8a1429128051e09d88de1d821694e2cf06bc8ebf1f153e04743ddd21f9ab992398ffe404086724de7cc16fe5e7a68606d8b24a1c12395ff7bb8d2666313538486675b981eca521656c5fcd6d22f761edda2875a454d92ab08d2de00693bd2e4e641887fb27efa31b430125db8	1	\\x7943801c4227bef408068dc2e1f5fae16b35a6643ee340f95fb3198933cfe0a43fa5fef93f82a7b35f9bf205ca4cd73a03cc8936537206cd86dd9acc8a832506	1647346069000000	0	11000000
6	\\xba48cdde27f5ef34749a4b56b45476480500a78892da34494e01bc5d6ca39ff59c578fc65cebaa403800befffb3ad7aa9e6d4050c203da474e199e59331c6227	85	\\x00000001000000015a64dbd3415253c5bcfd0746066c24e4e1d8321e4f203b8fd8b9edb11d949c3e70186d3cf3fde0606a8ed3b8b02378f543936fa1c8ac6bfbebb214a16545af676b3f4bd553aa4f8bcf00696235514aa8b2fc727872020aa77cf507a690af23f34150888e79c239862f05cf72dc7cd543dcf8a4f46f8eb0b854c718e3a117ddac	1	\\x17cb0d9772f2865479434c86fcde77bb191de79efb4e5de11f7f6ec4b3ef5c615fbb13f43df5f379e66565b1425f1bc2a8f7df77d86f2b7910a46a312fc08d04	1647346069000000	0	11000000
7	\\x5e896a5ce290c7c6e279a66561019b82c623199a81afe98ba958a853f98898a03fbaa177c39a73ded4c7be28492bbaae2148889a2a2ce0ebc0a351f5a6e75f08	85	\\x00000001000000010ad472b5d51a694027b12964f9771f300ecff6c2d1ad3346d9da07899a2133e1c32723c65c4f4f4819b15da184ed67e8bf9aae07eaa130a2108d9d46ed14fd7de16bd5755b70e428be5ebc8047c815b50518a259e6ac0421401e915aa78639dd98fcdd7a73e50cf90e8fee88d48d0bac8533d04078700f0463e8db94bf890d84	1	\\xd1d1f633460233f031bb9e16704ace87de3c72d5081ec510232ca2a7b7366edd275ac1ba6d1932b47f951e8086dff6ce71dfd9da50f4a7d42a2393a7e4e84100	1647346069000000	0	11000000
8	\\xbaa0db89b7cef3a8116995c553dc44a191c01851ca4ed293bbac436360314a53b3e7302dd8eef1d661b00b14c7d5dfc12d0e045d524bdfc6bfc18d93f4a1c273	85	\\x0000000100000001b20f3d1ca90ac3f8a9a3bab07f52c019a9f1b7f6100a7998c1e63632281c62d741315cc8f83e597df0e4247b6c55775f066f79f1ee0ee8bc8608614f25b5b8ff4196beb3fa77c1d9d3357e54fad0bf00b4ca9b38d7a20e746622d8cfc07a7f56147b074655faabdaef8135c019ad7d169395c6bea8b7656464ed5a11982bd627	1	\\x6b46998013462d517601d6e5ee57bcdd1b2c37f7cfd075e486869951766db11c80b71a42dfdb6fc3445afa2e90c68bdc8459cdd7db27fb507794a67a1c47f70d	1647346069000000	0	11000000
9	\\x1e5564529edff6f9fed06e8355f6269765004104fd2c1b5035c1950f77a0831a1628c634518275b3f3d0eec82210380bf8c6bf96ee46a7a3e186430899eeff03	85	\\x000000010000000152c050b9e1d84d35198f1fa5a4309d452a2a1d2d15c074145942c123ef2dec3388897085224ab1d245844481b4ba92d50208207f141f73cbdd66aec3c35a10ee790f78a70ac9929955b17c7c6941d40a05ffd88800389ec93b84eade17bd20543212e1c2b33c729f0fff0ff2b0f80c8ed5266fd40d4d2d709133cc9a4c4586b4	1	\\x70cea7945064bf552bdd4c966b5ac8d70e660205cd88039cfba7529d913a817d2df5dad60aca4175d572bea6694c3e9be249fe9a41b86b2994cd2c3b345c0006	1647346069000000	0	11000000
10	\\xb9a50b2b440282ffd024ff1c7dfb6877277e6de18fa862d9e5e8136f5632fa97aed79bc724a61e33073b31645df7c13d045635ad46fb2e58a40a8f717ca2a4b2	85	\\x00000001000000011484828c1e89f65c41e6bb841f1676aefc72ad7db8970ace23e4a858b2a1acab293dac114117563d6f7ff0d2bf2626a3aa9022c6bb4ff09d315c77634b17ebac20516fd7ea573c11b25998b168326d5a437e3b7a4aa6e2c5ea9ee55b0661de38ff139e51dc7ba8c00cd3bf7d134b4eac4bfd48df3c7f762743dd2404295df39e	1	\\xf5cdbc10e01a526f8a8b8a980800ac650d900dc046b667f7a181e7d56ed436d89ed427910defcab1d509671a1eac3b84ed21e97b16c1a1e295ba205081974702	1647346069000000	0	11000000
11	\\xc316a88d68ea54608dbb7c31a761aec63b04842eeba7eea8c5a65b694392f3bcda8ccbac0ef579453230fb54184140a986a8f59ce8fb30ba9503bb633817c69c	267	\\x0000000100000001ae8b20eb296481984eee2f64dcdc1f0a40341b5346eec2a88a8a0590d93d8e91bb4a47375634255d2ef5d610ef26bd6db2146728a89e6623092f34043799999962584917381d4d6bfc5b9e8187a326210b9514c36a1370e487957aa01d9966a32c5b822aad6fe3c865161312c32d4e4bad733330b07412a5950c445208a63a7a	1	\\x157c6b857e7073750dc97b70cac3230447dc3925c4e627e958fb4a9ec6ef7f3832a0511f9e7b5a5e7edbfa717a38afedee5c63e0b175259d43c3e85ffff9370f	1647346069000000	0	2000000
12	\\x461962471a93796d0ec3632d375bc3a5fe54425ab57d3bda0cdd0f2a08972a3114c9182ce4876c5cad701065df795ebec1ff47211551e9d9394d4c31dab1c719	267	\\x00000001000000010447d6ce01a826f2fa707eb1dd756bda0e62bb7b6ee980111af77efb47502ab3f18503c12fb551484c24588f66693c0d69103c29c402fc70c8eea21d442e559c5655ce3f6432f8dfe51d667d135caab81a2525fbde8e384fb5e670380f0d6adbad15385cda20c5617ead736dd11bbc201cb519147c33af69e83dda0218d2ee8a	1	\\xf331ba2ab1e3b1b1b72cb88e52e0e5a8ecc9487543a5247a193eb1126680198b5ea063680af08f8455797ad4e49fc30947e8abeb38dec07590ee384e03a58f01	1647346069000000	0	2000000
13	\\x77cb0c26d8d6c74ade48bfb198762c44e404b0e578abc71300a6cbf0ba2ffea5ce9504bf70673c53aff5c0833f5de73e59b7d27809ae2c6922ffe65777737c5d	267	\\x00000001000000019c333baaaedc4f76f19f227a354da0ecca14da84e62d4c82796a70f008be27999fc6fef51f01c4d9c42fd4f72cdb9563cdd65cdf220bb4f48b6de7d55fa2176e712e33a19b64fc018802c2a02609e3ef205d5965cece8e100066c0d576359ce9c80bade9880d1146935d77afbe64e70eb97afb371353d490478df525e4acf0ca	1	\\x2e4c318466c26ac3b55f92798e4d5fb145f182804bbbddce2655f2b065f87d2f228b4729c9f5df1c3fcb435d960b3d2124af925ba30a76dfb9b04b0096e6dc0e	1647346069000000	0	2000000
14	\\x71a72ed4f06e897d4a47182f556a6d90bf5918e7f4f3fe511be83eb1120694319b5e1515f0f0a5abe1abf8b082c41c9de03ada0975bfe688c8dbfc4d27db859f	267	\\x0000000100000001a62c6d81305373b7cdd35195e57c230244ab00c0b09059757156a3b7208fe89136f64c3b65e0686c73f39373639b28b01ab3b8e2282ab071a5e6441ad286e62929f404084af5ef9d5efa509a6882bb23ed92329df8856b64298cf2ff6a6daf3c41398059beab70bad87301a2be4f743b29b5b3d391a4b80f003cc6394453a67b	1	\\x746c12ab3b61735c6e1edc74d7eb53d0ccb6a69169b771d162f7f60b856ace8021ffa51e95f3b6c74452195a9b82ef78f444c0d09fec75a7e4365d214d80f103	1647346069000000	0	2000000
15	\\xc1c5f02324a3701ce0df9ba503d0f0a70855a2937792e0dcbd80ad3871f8569c30ab9c224bcb06fafca894621c58f4203f3c3b70d4256af7dc59eec1fdbeff3a	139	\\x00000001000000014a4b12a068b886d033dbb8eebc9da80a777f17ebbfa58b1d1013d6a03e259da72b96e34d8f0c6174666ba52cc3e659151515f1de5ab54e49c801bb780b365b01b483b7670e31502863a1110b4b6b5d938914a4dbba9a96b41dfbfdc25ec2e79dc2b936e854d6ec8322563b316778093ed81e27f154dab4f6d9de06685f6d6a5d	1	\\xd2707a5c2c1b975df8463d87a05471d31ad964dab4df8f0bca11f73d760e3eb3cd7f164f0f1e3ebb75d762be4859ca2677e4663bf59566289495b302c7a1f003	1647346080000000	1	2000000
16	\\x8bf2503aad05adefb0cf3dfbbbb68dc608407609b44570213a3695602936fb7772b5aec9b3cd6dd8878392bda6da0da16ef2a5b9afa9df056d46e7607b09c0e5	85	\\x000000010000000179c500cb636e17b083b912b0ab1b92636c319a71dddf2f345b4b0ca7fee41f18c91e54e31f91d74171215e44c2b9fb0651301247271d09ad244a7f512213d4a0ccbb905f16b2775db88d7f973ea84e500aa609263059f2054eb3b19b6bc3df438cf5acf06e5f3ee55f37406eaddb4e3480febb1e2a1f90584a160bcb918d1f91	1	\\x8a9a283475cae680dbbabff780d8ac36c36b76d6fbc8e4921beed2084458789cb76dc53e1b71ed2bb2b34505df90a28d9738c3974a87ed45460added3a0d7505	1647346080000000	0	11000000
17	\\x5e72e81d33fa62348dd88195c9311219af94264204e035fe97ca4084b8aca54187a738dfe15b04dae24786fd9503b87b73728eadfcc7932af70bbe12d3d2c410	85	\\x00000001000000018ff02cb1caadc8f27eb638791e9a7294e6d7a960f8b730f6e35502cd3e4985e61e229025af243c0eb88e9524aac6a44c3b1c2e1d93e7e6aa1e0824516c380a2367d1367dd75cd10c415309ee4593d7af8c1e8d7639e7f5c70468c706c1ea5ded0b0a8135a447389686c613feaece1f868650dd6f86af4a141fd5e26cea243e7a	1	\\xb26a036288af75f85100068e95610b49bc78a37e901bea7070cb88bf082a1252865dea6290397641742d50af3f8ce4dc5235efbff9334aad49d8e73370804604	1647346080000000	0	11000000
18	\\x41cd35697d0f5050ce4db5d96614ab9ddbfc2c0305b77e0e1b5603add04df822ce6329b14b84c7b4d18e99fbef691527d9a73665a577f875985a08ea3dddec93	85	\\x00000001000000016010efa1987f834e8077390f0a9499853a43a13bc93054ee1b6cf7740d2d17a98ffef261c546a3e95583f29a2b77749442230624b077e51fd56ab122194ba5c0e05411ef5f081f309aceb65e5fcbd6b8dd4f5913deb673a0bf6aa6446fc799a5c497b15df39b60117b809879d9286181548a6592b7b64780d59a669b89a3e685	1	\\xd9be0307068c79e057efece4243d3e52e36997953057ce3e0e3ace66813a47b78582fe4eda55b09db6b26d8741b9f56acce57a4d306d9133ba84305cf3c0fe00	1647346080000000	0	11000000
19	\\x1e080ae3c843337c73cc7060bc6e991e77d046e8b257377ea6f05c027d088251c8e61dde0673da2c25321757d017686f3480314460b043b5f3e7d29557b57720	85	\\x0000000100000001113220d383a5898e711f9264b312fd95a332fa8103edb44705855f6a2c8501d4916b5c90e4d700d935e8a39b468f08e32450890a43abc0db5bf726e6bcf7dac543081d58cc0d2c9886f1b8ebfaf04582cd035fb6b7dc07a884e2033b4d5caf48540a999c256274dd9a12a73d1733a989baf5a16c1fd05aa236d805033a55e061	1	\\x7738746884b9a99542ffb970ebda5a1294db44495a3988ffa23638ff7acf06c7e9a74c65c6ab83ec199490602719e98465a5e289864a54005486982a1c0c5004	1647346080000000	0	11000000
20	\\x25bd9d9eb6c4bbf2ecc34e98d96d4a1ca28982d095a51dd79d38848d04f0485b6f8d9d9563b3d4b883909fb934a9f873968660a110c0453b1aacc23d819d5e4b	85	\\x000000010000000152258b08979dfe88f9a0defafcde137d693e14a775fdf9b9023479671112c419b59d9397cc36d9d6e8ab71cd33773a5fa2f09616a8dd3b644e4c5e2f85cbd51af6156d382791ddca9bece78473db0717c41cee9acce14d9b78a1a10e8f83ebb06cfee8090e594b62da4cc7c833733bdc481fc063462f564043ef9715828f90d8	1	\\x501fcb86560e4b221479cc9cbaf790e7500a5b6beb79d2d60cf617c2b339de8e063d7dee4d9524f756cf85c68e78609174fde142fd0ff955ad142f7219701e09	1647346080000000	0	11000000
21	\\xab61d5734a5d2ca9a01ed85c9ea7b326bca2dc18fbf4ece496b7c85863a3687a70f58d85d8efdc8d114b9c936e3928bf616193a7ee39702869315e94e8e6c2ae	85	\\x0000000100000001b6df0cd62e0216a2ebe3923a3ba55b0ae36120d3ef43335ddae3e7ed7b4e73323b27c13d90d67502da482de1ecff3c20c90fea83327e6a4bcc10661d3565f2e810c37abd227266e00d7a9bab4141839aecc869065993c00934a022a20e93dfcd78629cb7b7efc69a280e581d72d9040a9d025c16b8d2d5f88876a727bb119954	1	\\xdce303174ab1dabe0e19eb5cf446f2dcd9d4a8e1b68982f66e63c3f5b5c968d3adc0e95a4fbea1aff320f7dc193bec99b738bda59589fefe87c33aba88be1704	1647346080000000	0	11000000
22	\\x003f5420b1cfccf83352ad8be6ebcfbb77366181790a01da58416e7fb625438a502baea47e0b62f269c9ea8de9266e49e869b39d2ea072f5c08740555383db73	85	\\x0000000100000001a588a617191dc4097498548f744d86efe244aec5a6b12fb7de132370ee21814253f19bf762806cb806fb370e3df5231aee6ddc47bd48ae00502ca56f5f8aa86620eb93932606d9e59e5a17fd6e1f40ae2e0116ada343eec8ad5f12d626a9cbdfb70e5edc0dc5d3b3ec0be8ed6be7a2739cc7b3b61801df48350ed3a76c406a2e	1	\\x729f1ab11ca297feef68fd387537e9b75ebd3fb5e67163ff2033b17dfb4c72d0521fd2fbe97495fac378722c7568c4939e4da30b73c35b86799ae3d713f08402	1647346080000000	0	11000000
23	\\x7e911d6299864d9ded782f6530a5ac5b815a9d94a6f9b049ed300730f2b1848038d4c1fdce60e6c62309bb4917e8a015c0b80c0d2193f5576de18412bea7e865	85	\\x00000001000000016496a4f3cc44b1de255fd66b87dbaf8e1485c9933f4c6d72be3f64a993539fc170dd709831ed32904c30d61101c83ba9f17dcca68cc5110b388013a1eea34b24ccae1e9b9a70fa00a093bbb58446eba84f95298bd5f56877bc2ed5864874224430419059ae8c3b34bd7318dcaa6fe506d5f016a5acb1c9a45875e15f9d48dbd4	1	\\xac637456e6a9c0d4ab078019f9d5d083b55d0c07a35d9206fb31abe7de6ec6dea3b73c5331b9d3858b72c10697cb9e8d61790dadd2462c46ce2714499696a405	1647346080000000	0	11000000
24	\\x6aca6b478327ae2f47b0a79e11cb8220142bbf259b55d5d7319cd0fbc5a8046a2bcd51558c24f01b6f10005bc30b74262ec068a49bdcfdc40f26cbd84be94252	267	\\x000000010000000105f175956b93fdc8c1f0145ea73e51af455972f650fe13c911fdc2ad9e4ef844b0982f7b694f8ac3076a8deeeb10a49933ffbdb37c28574ff70173d3a6e8bef812502206da6e69b9a9d5b44547e5a38aa6a441266ed88334f657b65f1b80a3db642e41a4d93a2a328d8e19a4f64ff94df60d8de453d53d328303590fc0b23777	1	\\x716e01d12eb8efa903474a10bd3f1caf3037ee5a6512620d64ab6f26855b53fb2a402bb847ccd6042a42622baebc73d1497bb33b12a20db8fb732b1b2c68880e	1647346080000000	0	2000000
25	\\x796aa3f7ef54054d415c39ea487ee0429d320b1c44a5413df465318aa04d22e83d1e8766d4cf24050478035d4f7434f3ce3e0dc9eab3475d93a5c81f25c806db	267	\\x00000001000000013ac904d514a33311aa73fd59d5e16b65a63a71168b2efc9258e85ce945e8b9d62ba6bd7da26132262fbb39e9f3f4e904d6b661484652b1159a26f96cc6e3b569219b4218fd3f630959ffa7f0d764fe3b16a9b49e863124e30521930bec7330658a0920c485390dda1a9df8a07d20147bac18606a7c04b493d80958e004275014	1	\\xc76a70102ccab0d152306aa44b7a7bb300799f0eafce815ff0e54305a89284b9289cf745dc7e86c9a9b8cf63bbf2383d60f5b1b46cf922be6200c05a01bf1b00	1647346080000000	0	2000000
26	\\x291c33ae682c271ea60823b7b208fc537dd49b0a8cbd792d9ec176045df9be4f13a5a6afc448caddb7eb8b6f686eeb7bebe24e43b884eb1a5409b4da2dec605d	267	\\x00000001000000012f7d36f17a809d379ea59f2c631e97a248ea3c71d0989020187dcff5eb3c3b9ea0987654ebdcbc3e7a3791e44bcfaaf49859f07cdf13de1432743d65af3dc938ef67d323a4c4d86fcaa51b495bb8583a4634a1f2fb265be20be2afa02e484153aa17e74d58a685982cdb6319a43898554b87f39fd8514dcbc4395394c0eeac4a	1	\\x9c202730d59f80cf3cc7846f54249aa421872b642083d0e379f28913d0693338987cb3fa5f7b2b7ec95d4c07897fe1781314412ee398062c5a3539b1ce0f4c0a	1647346080000000	0	2000000
27	\\x57c758f067310abe871ba5183654728f73cf3d5b7ccd57af7e2b68824121cc8f03647f2b34f391cfdfdec38970429bef6bd1aaae84934bb8cf396514b7e74914	267	\\x000000010000000114d232d6401a8f1d48d1d3ceea34d6eaaaa8292be2d50f9561f7247204fc98514f6c7025349e4d33f86dc6c6fbb5440ace5b0d5ed928d9f1654ae2741c2d3d6820c86c2060c763c0a67cc101e00aa19a3525d7aaffde9528519a8f9f12ed247794edc03b8e6ac0178df41f7dd385de1b861933d99704cc1b09f6de10de669557	1	\\x7f42f824e7a53374e7ce9b293457bf9ec63692c7e059e09bd66add15bc07b05aa925d96b86218c69821a82fdbca15ac14464d57366b2b5aecce5dc164bebb30b	1647346080000000	0	2000000
28	\\x45af8f3cdd1e3e5b5e9acda092453a8532d0582bf5c7065c9b3bd159f261e6888ffa7932243a2b9b3097c3371896853784f32e53bd746791cd0e129e5ba9b12b	267	\\x000000010000000144752d8840bc59ca08910c32908186eaa474d60b8c5d905a7db3de6a77c7e985333a362d54aefedeedb87ae05a66498789221d817f97b4bd07746eec2f08b9f1118f2879bb72ad2aa2ef5b90c86fcec8f7f907d14b72b65d5fbf980e5fcc89681e664fb6cf0e95420a075b1e0da26230019fe37baa903a368b0d946379a0bbb5	1	\\x0e48347cfab294d1cb44c38d613ffa79e5b4875692ff5ba47b97d6ab2d5febae327d299749660ea5a7203bd077ca2d03e73c1aaad21856f2783cb47d22e7ac01	1647346080000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\xa50dbf4182890241d76e04ea212687f1afc600fc070c856d767668c80049cca583c1c3123111ab334f76142bc4b8ff3ef7bb9438ef59e29a967a1bbbfff00b02	t	1647346060000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\x5bca23a8d87e507828b1d18e7148d63dba66c97f3ee2cde3f4be9ad00010ed49463342a7f7108d72bbd99fd073bce0ad40c8c5ac1ea90abc5cff9d5e2a0bb70e
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
1	\\x3d23e5c0bee9838dd92e267d7e9e0298b1bb0d5efa575baaf150c0060821574e	payto://x-taler-bank/localhost/testuser-fd7nox2m	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647346053000000	0	1024	f	wirewatch-exchange-account-1
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

