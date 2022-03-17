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
exchange-0001	2022-03-17 05:44:30.23521+01	grothoff	{}	{}
merchant-0001	2022-03-17 05:44:31.558179+01	grothoff	{}	{}
auditor-0001	2022-03-17 05:44:32.379112+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-03-17 05:44:42.475376+01	f	df0d92fd-6f65-4bc2-918c-8ca751bae4a3	12	1
2	TESTKUDOS:8	SP91J89T4M8JF2YAN0929VSNSC7EKRNEM64VM9TTB8S49JMMAGQG	2022-03-17 05:44:46.1661+01	f	01c41d0c-7d5d-40dc-9809-9c94d3062365	2	12
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
3fa4c3f1-d326-439e-85f1-0e110db5d267	TESTKUDOS:8	t	t	f	SP91J89T4M8JF2YAN0929VSNSC7EKRNEM64VM9TTB8S49JMMAGQG	2	12
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
1	1	1	\\xee713f6681b7dca7f0f5f2147c61741135af022dd197a8d9283bea40daab41a924dd905a727f480b6ff432662d97b3585cad00336a556f59e93b259ad8b9b70e
2	1	5	\\x1950be24235a16e10a3e65edb987fd2a9ac30c05d446ed11eee677ff0dbec812bebaebed08e7e2ec3662946e59dc73252e35daa317261b5252b5440d53a04f02
3	1	151	\\xf8e8e11185897712bab04580eb4fe04aa324d6c66a43b2a1ae343503b2e9e4d2c5b8c181dfb4cfd2cc4f6094e1131f15f726556758224d3ee125784b0191f709
4	1	42	\\xd3669016392736ad5405b137e1359d7c8dcb0bbfb62d8a5bd03d1701f4ff11535a1da509801a751451a8c5334783411a743c92bc6d3d25812ea7f8262b18fd06
5	1	102	\\x140d8d640c0d4b602a2bf022429fc8519a36b3b24c957e2b08800830c9cb1f29be86a9a91c1b689dcbe8060183c800d520e7a9f810a1ae390a06f3af17581407
6	1	120	\\x1b378595eab91ff501d69d8151571eaa4f973d54ce604bb125761fccaa59fb0e7da5867e3b0802a124c5fa46bbfc8b46f04a7cb15c345d4971d42128469b2103
7	1	289	\\x5c92ab6b764e052192db44c6d9f71543e060403b94e27ff6b1f6baf47e4d97cb3e74ecb1e1c11f58554a59261c367f6790538d0d27dad6a2541980236832850a
8	1	218	\\x276465e382031fd0409e352fa426012402fc81a3c4658671608e43c0d646057f9ee9e286d8e84705baa5b002450fc313b6cd27cbced1db508c4f833b6543cb04
9	1	107	\\x6a2a352fba59da298544aa5240cca66fa9db170a81942d9ffa2b359bbdf97868014d5829e7456d5b32830698b78f3f9ea26f8fe56525cf2c778821efd210f909
10	1	125	\\x2b060557072d0616078e39dd795f72b7615e72625111ee629a4524a7f8349f4f3e70f7a656ac5f2e397487e84b71d285dca1cfd82a7754ccd7a1910859392e0c
11	1	350	\\x9c03446af6c2c49287d31a146f7589f94b4855204489ac694c9fe19bd238e9ac24ee830557ba2b9b24a7463abb68de4e8467ba3573339a6373c5221ee1bd2d02
12	1	74	\\xbf6688f153b1485403cd94bb9ee1efcd140b8c9bede7d052ab6dd79cc1cd62069505661ab217a664e8269eb9180e9a385c080562d81b910cd5954f204bc84002
13	1	219	\\x48d8cb61957617a1df8cc9166f3b7fb677a26edf2b34c888c717d641bebb92512e3cdd964a8409c8741f9b66003c6e5598abffcb76f9ad326e379a4421d4c70e
14	1	339	\\x6a3aa32ebe4498a29d942eb5d80d738fa4e9a75b7a535da71184c75586dace49dc36fd35c661e8aeda1db3b01ac1605a16f26071635888db3f69c0d713a01108
15	1	221	\\x17dd8bab6b255e94cb50d7f596b499b9168b9405a3337010516e175a397fb617323d49d592bebd53e2053c50fb87bba7d2ab075b99edd299772e647e611d5602
16	1	382	\\xfc652c9272503635ef7d07ec28134bcebac3beb2a91155ce989901455516a302256353c51743755bb6173124608883b1de0945e0fc989017508f58bc1c6c6c05
17	1	384	\\x40064b4ef032b7869f1859960320595d5050af445e5884eeb996a8987814927f55fa1095114b410b5e6167fa7b3e66b3bf0d33e3b952e6465631be1629ec5f0d
18	1	251	\\x9f5c780bcbc8a3f1815eae179e5bc6089d816aedcc129fe030cd4c52928e1e93dc40420d867c626556a9d9c4f6938fc1ddf132baa5da93059aa976be004a240c
19	1	50	\\x3127a12387f590da1316700894d83d56978c3446bdc98c7b4bc31c712afd3fcd2a55931c15ba8ea2fd9874d62d0b0b198e9ec9a8fac75c722199fde7a68b4101
20	1	401	\\x48628f67e4367faa6e4c4cbac7e076a8a47df8108f9909ac39513fc56fe3a890fde05be059b02e91f526e1dc988588483c930dd720df29420516deff2fadab00
21	1	269	\\xe9e567eb752f376d859f46eba336be7ef34042e87dc402710901e8c6e2b6382c0f5073c84e085faf47a4bc9d1b2d690d10a9b5e784763561ede78d02822af30f
22	1	103	\\x49cddd26225ebeb172918d0aec9004ee5ade4cda64d45b610931702b44f6b96f206493fa6460e6d69cc1cbb9e58a0b7fc67e769fd382ececd3ab54a36ee0ea01
23	1	400	\\x28cf5c24d519b442630035108e1b6fa5403b25cf35d9b1bf1444b85385f547d92f237abee8f22028fdece1b5b5615f59f550099aa1905c0e16b2062819812205
24	1	155	\\xd9d7f57d421e7761891b4ac2d8d790118e20fe534f2234b394b6fd44cb3320aac3f54611c71c012d739506090841979ef1c1033f16b4c3e181dacd3d99ee8803
25	1	135	\\x7aa000661bbb67595e6bf07ee659295b8fe6ccbf1fbfaec93c6c8bdb7a097b7fff71431ea5f58e0fb6d36dbc290224f0ce848ad52c9cf4fa08770a5f3f466b01
26	1	320	\\x1bf815880c1a354a5d4cb361f02585753dd67d211c73d5db4c2d46089c699f0b75a7d09c98ea28cdf652ee1f3c99df4728efb5383a1b3396178e085c1f01bf09
27	1	43	\\x01e2ad1016b8eef9fb9d853c67cb6e9c0ab81b767da7c04c902f454176afd412e0ea43112492f1ebe7cc13e27ede6345af2c10bcfa95a24ca7537afd203a8202
28	1	60	\\x6dc93246cc42e63e613d052ea25281db061288fccedd7c4ecb1b75a1036fb91cb60e1372a1aa866fe10192f5f8aaa2e50aa1004ed5a47daf2878d68ecc5ef309
29	1	52	\\x1d24ea0c7f85f1f2224fc08341bf26d78da746e8af1ba27aa25e6219c4068c2e472242e62f24f3b277ebd52115e1feead245a5de58280dc9b43650768b5e2b0f
30	1	255	\\x8baa3f54d3779efd9295453ea8a24bc19a24152426f257a942f590ab90a4169ebbce88cda24da1e6f85d3983169e085a1a02e5e42e667535f514d8f98ef15e02
31	1	109	\\x7226a1c48da8fa22fb2bfea4cc026e690219e94cee538a3660a6906473e638062e6e90613689c1ff27e641d364207c7a89639ee82ed3e5bc4399dc572657ee0d
32	1	375	\\xa77b5a83470aed9cedb10d7d499edf6121e8029d1b16d1c6ce7be7f8c8adc8ef163eb753b19ef069f931b873f22c2a8616284ecd622bfaa0f9e5d9493cd10409
33	1	316	\\x4f5ecc39d6b498dce3cecfcc5bfd2ebcd0eef7e9e8b2b17ab8d8fb538188fea940e927d3a621e8509be0c2aad739ba454921d67b50707e92ef84592b096fad00
34	1	24	\\xc6ac445b831c5c303e7bb917302053676b10d93e47cebd591091d6a1d5e0ca1f65b96ffc39fba1a79492a14bdf6029563d50260d7a619bbfdac3f41532754b0c
35	1	148	\\x43711970edbe9f1509aabad08cb9a0ffea73ffb97d6818b1a2105239cbbbb6872fb29ed9ba4d77a308d04edb9add86a0842fda10c7486db51e74f304515ada0e
36	1	264	\\x80403fcd5369b75428116cbd4952719d519b72667daa0742137f2ca0c7607ea25dbb8a46656379f2c5fb677e31bc3a6b5619f5c650f179d2bb713f60a06ff403
37	1	191	\\xd72ce83c5c645e79c59b3942b4e82616f35f85bb07883c22f598749a7444315cfd448ffca3aaa78eda2a39fa1ca9309b4824c6a7e703e63ec6e592ea6432db09
38	1	7	\\x5367a4fc540415d308e38d10e34bf9869dd1e2cb7c2fc50c255a734f96a10a9c1551f9070b4de631d32e66fc59b295218885d192d6032c87fd76869a58d0f004
39	1	131	\\x964fc7a082c7fb34731c9f15d19ec5a7f7d4646be031ee8fedff75b8991cd621d484cc731fa9e2b87b8c078be76dc35fcf976b4d4a3187e694717102e3d51d0f
40	1	134	\\xd145499446b6f7b95a9f8e204fee69912c3005645b211d45c600389488de3a9d18436d5cdb1d0ea25dafb025bf61c72b5932b3e01ce59e29078a0dc3ed02de0e
41	1	245	\\xffde36e83275398306c3fea0c981a3af72b3afc53e20c37d38ae738fb55d7e346382388c52fbbd4990c256ff2e0ef97f02ecda66fbd5d9451b5ff06fe7b31e06
42	1	77	\\x56646d1b28423ea6cd2f05edb99a021a359aabf1d2d041962cdc25ca3032c9af5559a2931f3b55bc065f31f4d04ea7f28d4e11781871091aaeac201ee2e77409
43	1	337	\\x1ef6ca783e22fc5dc8682d0c31e37b956549b76c4d8e659685ea84c62b93501776a4fc8ac7ae89041ce7bb4cfcf34137f45cae57fa0d1cc22b89b04c76405400
44	1	369	\\xb4e27d2e582a2c67df830dc4daacb9642d62b711440dbfb54ef413d9460870b19b6db21aeab15ceefcb26c5925b9d0c01911eadd423a51cca0a0f189ac58a907
45	1	357	\\x515164a3ea4e10686d9af57a02350d1c8837786b3e635e1bd0a4178c1938c94d9e07845d0c790ccbad83d1974db420b139ab1eb2a62de42ac9882dc224bb3803
46	1	124	\\x488a57c9c957d595764b282015dfb192bfa98d1c74ffd0bffff153781afed61d5fa86551b6fc9cff1d5d56e166b96a7d76301c1772fc13bef24519169e6b620d
47	1	88	\\x35540765969d3ef85f2a365a9a29fc5c1b44ec85f04d4d882fd96750ff6c694f33bbcdc7af84eac4aebe4bf18dc39931494eb061a8509c6c74015182b5926a03
48	1	402	\\x734416f9360685e31afdc9cfac1d94ae91b0182e3b80684c061db7135df460efe220e85a44c50e7d97cc90bf28ce41b0cdacd6efdd9cc067bec46e21e31ae206
49	1	198	\\x80a96aa8b0d6d83a18362273e9b98bd97d48577874b305e4626707a106f5deec5bca9b77a9d0184559f25893330667e949fe395774b8aaf0668911992cc0380f
50	1	311	\\x7bf34e6655391622a4effe74cf8b116115060d8f2030685b1af1ecc2e7fe4a5a3a9412319131585afcea5f391f71c27c46a3dea512f46765acdac5a7b40af802
51	1	364	\\xdc40bf813f8fa42b76fccbb30ac2b5d4ac2ee3f2b59aa27e496576e0fbb5e78f7f913bdedd973027ea8b5657e6ec60775d8b9d578bb0c6f94a9817a123c47a04
52	1	239	\\xbcc3f8c2ff85524572e29fd22b455de88da556d3b09dcb4ab0b563b655394412f6e3552f26b7572bac5cda9cc3ec649239a3381055bfa222eec4520ca395ea00
53	1	247	\\xd0df66ded6dd9bd898a6f47e85a251532a70c6527b529cf6a6b720c3593d35ce9fd54f30eadbd75c2841a5ded875787140e39e4410aca5335ff1ee9c08147703
54	1	351	\\xcdca741de368e47b7bbdff393dffa05aaa40094a44e302f5d793da2afaff8f17389510bbb232394c85b9ed457bef3660a4842986c3e3452b286e6a4dae1d6405
55	1	202	\\x24717f2bafd65a768ce87aa2f83dfd17dafbfbfe06f0b9b9b21fb11f922cdd860722fb1ed3863a089655bab76ef65d67dead17c403f87fe11c30e11475a5f00c
56	1	223	\\x313530fd8792ece0435abf77568f5cac78a78e08cfb3d78e88490209af9e73e633d44fd7bc1b47f262e94ffecd17e8b16cacc867e63c5c66d7c6864059f27202
57	1	333	\\xcf5c1801b084f5c84c2217e4daf2f62795675714ced5a357141692e36e1d1ef7e62b4ddf4f28412340c7c001df298ecc8620c55be93bbea646f489894b80b508
58	1	161	\\xacb3a7b5a633ca524c01bf00c4a0b3ed3b193b0084df9c1ae62efcea270c4b69c736e7e5b6445309cfa2c6468939b628e2d8ffd900a70d700c48dba67b3e6e06
59	1	305	\\xe1237505b983e5a6408dde1dacf6caf18f6d0689001cc5c81db91ecdf44e394aecbde002bd295e3420082805a840aa132e96068237e682622129a016a7aec60d
60	1	207	\\x97871e0168cfccae43f721be962e9c5b0916df8e01b9887746224b388957d129895032b5743ef2e305caa8e11e1843f91bcbbd4b5142dedb6f18ace80e0d7f0b
61	1	33	\\x841a9a792e707905518db11fc7865bb56989f93c838800444651fdd8145ce88ae6058d14b5091d204bc1ef6e9d24c7d0269872f9c0026aa6a52cddfa8500cd0e
62	1	152	\\x74149314625e6a492f520dae89f3b098f9609d4f1418ba9b1f17ee745a08ae09f36cd1267e56d92c521cb124e0ce9077ee21706241df68d74557cb004aed620f
63	1	415	\\xaba3b8143c598644bbb1efc26e8ab0f4e865955cdf31d9ea92ed681c44aadf9f165bba46b6d1c321d77f8be72fca5bf9c5bf6d05666e14fefac3b9fd73288603
64	1	419	\\x00f025e511e74343b5414acfa7f3f5a33136d82ef537b040d4131f570dc876e81c62d61d3404d27791287441b1862d67520b2c7b9eb8f342cae61aaf0416c701
65	1	92	\\xaa709ffdb50755d7c7cd1f3107d786c4c7cf48645d4ad1bbca950803a8ba913c2cde516bdb95d36782b66cc826a5560cf6884e7155a1c4a242b610059a895709
66	1	149	\\xd17ede9f31f4c372c330c4537b37a11d21e58d384dd879b1063a92aa268af9feb26006d093f73a5212df23c8dab509ca06d54007f11aab7a630c7ce33baecb0e
67	1	246	\\xacacba5badf6c89ea40640cf0d18316650c6673ca5c46211bff8b6cfde68682765671aa0689e1aab05a57a5cb8dff35de0c9f3114d339f1cc4030296b45d6904
68	1	110	\\xe6260c0fcb9198bb4c34739c75249498b426972bf7f4c411204ca22caec45c30557f9b007ca5861cf436d18c29375c604892a8bce4aa9c7282dbf62912510109
69	1	352	\\x22a780fe00f8d371788a4d8c99694a77eeb657fbe380eafd110f8c64e1b98652f696c373cac95865aa1bea5c047e1af8905dce898c1f0379e92a93336b775607
70	1	147	\\xf9784b0c62b95791f05f8570962eeb713c9ac6578bdf2bdb66ed32e58ed7a1bfa67353fab0082f544ea182563c3eade88b259071c29662af65721825e3351f06
71	1	4	\\x6e0fccde00f4aa5db806d7543b264853cdd5bee5f9491fb6a434d01b00b2bda85c95782bab373e8d9ba2aeb5bf89a88e4e2c9529e45f7964e954133ece1eb105
72	1	235	\\xd6f0c45020c72de8122f69ddcb5c760cef27cca085a008a2cde7f981aefe78dfa8445c510524a7eac5230c69e46e1f60233c92ae1460261a2b451122d10c6d01
73	1	254	\\x88d506153aa31304501bcf905d293a6ce7eddc08f8040d4d4ac8c0a665970c8de100336a9fc1cf0291aab9dc458b989681906b8ee4e1fb1f806c8977f252c806
74	1	354	\\xa622b9a9981a5e9f5d4ab1f24f7a3dcf300153fa1f05f73720b48452a6c1a4a98cb851080e74bd7d96c04127b85e17b8b6c7cb57360cd5f41f90abb6c124ea01
75	1	105	\\x33eb2e46791f8e1f71dc00f9c1f87e00b0c96f92ef04cc4e2ad7c7c9c3bcf9320c573480feaafb56c95e5547271161e2d19602f88ccc2678cc9e9e3d0f7e6f0c
76	1	370	\\xf76aac43c493f8a9c2faebe4d920f617327f92a6267c2e9e8cabf1e976736b391f74a571aa33379b2636ad8d957b56a5545431c7efd7ee05501e9b362f658503
77	1	66	\\x602bd090aa89d0802a5d753dbacbbd29f30cbd7848bc5aa1aadbf4bffe22830fe117063c291638b6dd3405feba9ef14619673b4229f4589c20e8f5db7176460d
78	1	404	\\xdf2681ed7e7b8af0e4eb682840bb23adae0a4055408f6379790743b7645e7a375aa30e599e260484cb2325bf7c65311a49cf90822e026e58ec9acb3ba19b8a0e
79	1	78	\\xc1498f660b7848ee2c3071d907cbf32d47fa8c02bf00ed1d474abd7a8a6a184c38009fa0f73163d0885e25604cadcc95b956b850b7487e693af27063020ab20e
80	1	229	\\xced918fca58df1e692d480f63112746acd6c40681d20c73444fb44d0745a3c5a5cba606c7bf2a62c398eb005829ba8468477c6beeb37660bbcd0bcd610ec980d
81	1	174	\\x8e518019421f2ed9f065bce1d3a246d1516de5e0183d69ab800880a6446fe5908ec04fc72ab73155651884572a74abbe27a8916947c0d32efba168cbd467460f
82	1	181	\\x1906e20315ec36cb5dea4c173a70f44c7ee9ff301b9c62618a0b473277ffe3f82dd6426f3c1196152b90605260e44db579e6e3ed800f450f947290e173b22d0a
83	1	164	\\x660958c6054315618fc6e1dfaa43e2b077bd2e54eadc208cc8bd18f6b548869b0454e986cc9e168a6df8be40f1b47890318ef2dd3d4f1424f14c897b0d978403
84	1	39	\\xfb186ee053b3b687126e20fa55b6787070a2bca392f0d73f68f38c09f3a7a5147c3412b91a9ded457069b38da84a44241264a955fdc85ca2f451ebc64c8b730d
85	1	126	\\x27b6da3c041b5c9a1ffcedcf78a7ae462e7460da48fd35d07b34cd75210d88e2dc3b9cbb93920edba6f11b68b9e5502a1c86d4c84319b967fe263aac2922a906
86	1	345	\\xadfd2ba9e5bb9c2b6ffbb60a88e81e663c6b4a2ed86a97b68de00bfddccbc4327ee8f36e741cf82534c71accc9ae89080ff97f49cdaf1634d4b2e12bb6eb1601
87	1	377	\\x0c034058ee7f884732ee8e33651ea73d958250cba93fb4d7fc69eb3d080394bd1cb8afb6b8d295c8ba73710c814378da0567241fff42312363d60d69e8fda30f
88	1	294	\\x1a64a2fdc24cf8b3f66899017f68b8af57c91e32eefd99d6bb647c4f32d530627e22c9fd26fff59f1aa04e95dde828a4378beef2e369d310f17d999766a2bf0c
89	1	257	\\xe16b9a53b188aeb1fb3e0054d95290506fd2098c4c1a7ba5600d819385d9496a3a30e614f72f4bf1d652b5a5dd0e39994fa64a7f56caae93cb3d95c7132cd30e
90	1	288	\\xa6c5d59287db9c40f7cb5b02382441b29a796fd7f94ca36a209ca3317905d5be0f1565ed30d6f9e83c3eed3686d34fcb0cdb3e877ef97da328c035a071766006
91	1	234	\\x22a2a58458192de869a67cc749a99d25e2693a2868b64f45b1e881883a7eedcf4cbba80dcdbfc9ce80bd233a0eb46a3106fe7600c55c5e5a931327f3132ba007
92	1	199	\\x3600d749846bd409053499e7259bc63b695bfb7488a48951de305dc525cd5d3d79ebbdf053c734ea0138dfd35aa1f9e5ff8aa0d9011ccef925b5c200d497d104
93	1	21	\\x25a6506d5bceb3aece524b39e096a69f753f0280988b1f2a701529e0af1e9e41d6825df126314534ab4f1fcc636113507143497cc2d0a670b0ed8eb33cbf0603
94	1	201	\\xe9a4056e23ed69e84e7d5a95cc31957030b1289f879507782f00017cf8de5e59507d565d72de3128fa0f734fdff2b8fc6a3c85a1af53767ee32ccd54b92e3b0e
95	1	343	\\x82a6e0dd5995e30949e5749b26a005b6a103c15a027622c7d61c8c8edbf925b8c87ddffe67ec6b7cf16e205fbfdc2f28691d404b87234873f3c758d9d296b107
96	1	56	\\x208db5cf2e2ae806ffba11ce36cccc30ec05e4a8462bd3419c536722075107a01561b0c699275a061facfd93a05bfbf71b0f256bb2b42a9b75b420941d287801
97	1	367	\\x7d825e0925dea91ddb0b513b9afcf98401011b00de114ee2bf7b577907c1165e843dc16560b358b115a158d286ee2e720accc84d4ba6ecfccbeb49cb9b371704
98	1	150	\\xf7cd52a0c0f3575e216a5b13c6cd73791bc5ad959af5f4a95a296e7b94df3e5d2ec3cf258487a926617fc9ad17f0f2cb6beb4245e57207eb6775d4c8cc730607
99	1	303	\\xec9eca526dd24f8d2c29418ae54b241ed8b77f9ed76ed96a6a0a8720066802225622c64154e60db6f7aaded95301a241fd0c0b01b7fab90c2ff6a984d9c01307
100	1	346	\\x4837b8b9661698f190c6752644e40d000a37653bdbf2cb68ad224e369c96bf8f2310ce17c3a8a6728cb69f44df3ce85dd903cdea2035e086ac2b26d8ddb6970f
101	1	195	\\xf95749540aa848fa0dd392bf6a72b128b2b8dceb60e69e9ae23ba93e4742b3ae2b04acd366512906aef35c142c68b6258077441dbcadec9a81554d6ff6564f08
102	1	49	\\x48973010345d3de5dc18fb8dfe46e8d4d37decd44c212f5b850d8e02e88a3014e35e1cea95252dc39341ce412acabc333ce8412803400b9df02cfae58681e602
103	1	204	\\x59cf89aae397b580a3156528e077f6d4c4496e77834b6272e8d4097d61af7d67774b2e31156d0024b0d61a7a95e00f097a32608314a29ff188e7bccfb9a6d90a
104	1	10	\\xa83e41a4511a4ecbf48de1b0236f7534ead7f9fd6e196bedb5303b4355d554068575b10e891da669bfeba2d41a7232dce7e16143fa505f9667a91e3b583f2805
105	1	326	\\x32d445761b3ba1784342c954a828568e0bea6b69bdfc25a792c7f6d033e2bba2029d4d0763feb32756d90cc2fd6fcde09f5d3d54b8c24f466afd00804c884004
106	1	309	\\xb5d39441da09cf7257980f6678378a67e9ac69c4d455cacf7b09e0beec89f56f3aac504991f6213a5667c77d5e103768bc14b4946cf09a48dc14d63803fb8203
107	1	129	\\x03e0b8bc4ddcb8337350c288b3f7496fe662ed4a82aab9cd043f0ee49772d9fff03d06910279c3dfa500d327a3fb6cf7dcf09626cc9a68931073071646730705
108	1	211	\\x3e5d499e2a40a189336fb21d5cb777bcfa4ff115efd723a8031b08d0116f0660945f60f2ec7fa687ef1b745eb31f73770341b76229e4e0218d1f555f4a006504
109	1	408	\\xed8d3b3eebaf673fd337b57e2cc3f100279c96eafa8553eccafd5ae3e50064083903930813dae7185f38c5d80094fbeddd76ee3e21ad972844800df8977fad0c
110	1	53	\\xf3da26ff5fbb5744b48fcd1e191329384f73c16f35e29280d6e6434f0483ff3c416a0ef2f3a869e3c6f5fbc9cf81e5421a2f9d5cc6bd4d9f167e62df79451f0c
111	1	256	\\x9d1fd744aa9708415728e7ef803cc219aca23bb441299797f8dd1474866d1de0d97fe5561ae1d5627d84556872d32e094343c2f5281190424fa4e4d4ef1b6209
112	1	393	\\x9eda4e9e7d117271a2759e373e18d299b54e67103d25417fce17825922be970e7b16d020086f8b28d84c86c86ef7cce9c38866b03b7af46399ccac428d0b450b
113	1	188	\\x2cb2cb44d40f5d4c73682e56b4c4d2138ac25f3d10fcc942686445ff3d65f04f8acfded3f84f17496fd1ebcafa19ed0aca8172488f27dc23f1201aadae906f0b
114	1	261	\\x9b32a05652878751d738d9dc87b6fe28a34b1381fa681adec3166d3594ad656ea3b6b4a8431d517424b9701036f9e4e20720e3c51574bf18ea7f8c0554d69b03
115	1	366	\\x42a702469cc91e5d664e941ce10f91f89678d5bf2340ec44e5ee78ee7d5d8b71c59f89324a9ddbbed5523403ce33ed123865256e8dcdeaeb1178b11752f28e06
116	1	417	\\x70d4dff814f1abc795808a6a7ee0967d3a158501e2437844483ec8d8af68a906bbc5a87769f492ee41a27908897a16f63ebc94d361a008b9466b1e024e4a8a0c
117	1	421	\\xa16cbe46a0b2e18499515ea1c142cdecc0cd66200f57e41230e05f791910a5f2ca51ba81f3467c98d8d9877d6e3a0d50a3ce11039aec57303076facfd7ba880c
118	1	197	\\xf0aca03da88b5990eff682ae88d481f94a7fa73c2aeb6c88791137b67af60530b541a6e31988ca0f76bfb8426da2eeb154da0dce5f4d18814a2c4ecf4ef10d02
119	1	3	\\x6721ad61bcd3a004a2f1209e857e3653020e41a8c3de2d17f4316f7986ed93b01b6a9a3d85bf122565b7666c962ad74b7fe76285feee05da97a024fd17c49401
120	1	183	\\x5fb6f73f467eeb71c5d54e0fb2d1f49c46c570112b35015b381cac2c0852db993a1cfa03dab319e9421e8608f1d1b1c4b6c5ab22d90406b768be22bc93e7e009
121	1	154	\\x053bb2683cdb148e8601f7717544d6bc7c436c76efefcccef26672fd19a07f01b66e3e58ae519492f6972bdc13a2888ca2bae89f010e4eacd2350e33ccfb4a09
122	1	240	\\xd677e16b0eb61a82ee0f0ca333f7d7aed85d48cea6384e9f65e34a9acabaaacaf103180fedf46663b89d5d99a17d8a550dfaf4213b65590ea4cf81d5c981d50d
123	1	227	\\x72a9db1c6df246922a922f68e8b547326396e0ba381e1b8ee3d4d59851fd804883319f533c376b8d988e62189127fe505ebef9fdc43baab8939fbd7430554201
124	1	314	\\xfa34430de5c7436a7504e752fdf9a89af3fb43cc01d453b73b4e8d6c7e011bf4bc45de569ecfcf298f09e1fe103c446f925db42b99dc9e05bd5c0b9d6a6eb303
125	1	380	\\xb527f41660afbbb9b1ce7baea35574a86005dda9d03aa497d01d4dc15f0bfa805ed1bf7afae98e6927fc4a7ea31acc3a0c6e41fff2f8549eba000ba5c1e5af07
126	1	18	\\x9c6ac23ca34d2847ac07b5351d1f888346474e54936881b0131943957ce5d8a964d8fed39e28360b7da804ff96a8dd6200044f298d051dd524dc885d392b390f
127	1	224	\\x7a4aaa0c41be970b5b2da518dbc163df103e18f555c0542eaa11edc5d60b5354db2d536284a3ee3161c65e06b6678eb90859eb381558dbf60508b1cc33129407
128	1	106	\\x470f87486af4a45e346c961a51e97c51ee9c73906cc19b72d1295844940148e423ee66adfae1efe87e1d60f8096040d05544fe2b2ff2b3e282d89fb174e3e900
129	1	62	\\x014ada4753cabb4227c475d23306515b10adc7fbefd349ae2c86272eda70b7702420fad88d0a940032e54b7d918ae66b92418da37ea6e33101f229548d984409
130	1	277	\\x8e7c66aa4402b6285cdc64df99cd4168828a5bc3f18bf0cde0eae40816bd69cb2c129ee2fae203d112652a3e4acd2951392623404f72066a62f5043a5abb5e07
131	1	299	\\xdbafe6586fb8950109283c3c44c426f7368899b6c8f643e9577a7c7942f423a722699404c33177add74e6c5015814e75c349412a912664ff123407aca671e008
132	1	278	\\xf0387a575f612af468f8c16d470dede000206e9f8f56dfc23ae390825a5639d1dc800d92de33adc2f48f0a8d837c29030c327eca0e89a5f50d27bbfc3eee0a0e
133	1	163	\\xf9e5f8b06e1c6b592dfcc0275990e04889fe4bc8bc6a50fcc6c1a020350e303405b5961f5c7ab8f997164bef447232aa7f9139388273b48b361fd73d9ec0e700
134	1	416	\\x32109f7c158a72b49e5f61880d7757aa7cbe2fc3f11a2d95b0ef4268df2cf25d729f51d776b540c07bb60dab16d9e1d6f1996a004379f0f28da1edf438f9980d
135	1	46	\\x2dc1c8e0ba4098915c12f80ed7a1ac517ef61ab3b327258c77137381c8ac5778c74e8d231cfbbaee6bf70f6f02fa0113ca4656aa0c1667a07f9c2f081a86fa05
136	1	20	\\x4c378cc11cfb76814ec14d9a5244cd10a0b19df32519444e3c8999c15af4bd36f1aaeef72b8121fde4a397e83e065ea4f42a9b33119a5355f7e73b9a6fa77503
137	1	407	\\x322c682ebbf46117a7a3e2299d603c501b912073ed82499c05ae66628c95e8f3eee1800e565f44f0d7e2e22bc50e14bc0c23324df5b79dceb08f878c6ee5fa0c
138	1	168	\\x1a72dba96272b03cf45cb7cd6f6762cb4dfe19a9f3d57aabc937b31f70f0ec543cd06f202a52378806b7ee660d3f226ba248c73404df684ba8915f592742bf0b
139	1	322	\\x2543bb8f2c5c0112adfb80d8c93b0d6f63c74e9dce411e256527dd9bdb3e89968192695a076dd61f23055ba71e7276593e191eef995130378798ba57c3bf4e0d
140	1	189	\\x9619f058c48ad864c9145b5690a1becd2f049117f6c38268d1e2f5483371488a8e6202e130bfd999022628a574f6696c14eab54e4056460cdcbafcc5c0e9e80f
141	1	241	\\x3ae73dfe95e8c2c53152e7fa137b9a197f34d8fda14f29f40e0b8cb1a6503cdf1c1cee879e07c18b72a1c065bcb7664ea1eb043fee48501b9fb67d7761971804
142	1	423	\\xb3a2334b2d94c5bc83ec6dabf878580a5144b20b9fcb8bec8eccf486224b700346757473243704158127663119f18e33d742c20f356710f13e1156679297670d
143	1	213	\\xb317905a7458f5c1e96c9ce97246fbcf47307033758e5a0334a52672ed75d0599a6108c30b6c579f8df7e175e5793c81d44df4a957214389e593407fe1411206
144	1	371	\\xe05f196310843401d7b7291db3c5ebe02e6080ba4f162b1779160f4620ee5668dc35a94dbeccd334011dc249d1c9db7c97fafcb7a19a50af254d9c69f28bdb05
145	1	95	\\xe92740e094c3f36d3f7a415efc5122506cd5c0cf3f2832f13e0f5d0a30753d0411e5a337ac891b8767956bbd6e1acff0be4b7f4f28752bf49076d0e377ae8c0f
146	1	383	\\xdc5a6f61ffe7ecb0029ffcbd54621c5b1eb4da8994561b235f42df36b3e70660b0752c685539ae5c4cf896315a76b8b4dd84a370f951b924fea909537573c30e
147	1	63	\\x51c07049a0efe232afe09e799eaa8377560e748c43a670a7299222545048521cb3a35f631eb4fedb44b1c3c39335d289e2763e04cf56eecd3cd2526f0a077e0e
148	1	48	\\xced50d453bc5dafdaeeaee2f5f537996772814d5998aaeb1c5fcf04f71af9be688efe2f2d9407a1d2d060fbb5e4053e86c92b46bf932d3cf937cfcff33d2cd0a
149	1	32	\\xda45953e723afd732c2b5a447353755b6667bf5637d935d736487cc8676dcb58f5a4663078e3405384ae07bed24759cc70831bee90700a04f0063651efdf8f07
150	1	329	\\x7bd47f38158f2670e4c92506325e670a96ebaffdddaf6e0dce761ba8f5e0f784364e445fe136033fd7321b344d8627b242dd2fa18bd83fec8a3a3a95a785cb03
151	1	17	\\x546dcf25c72d6827b085a23ab7b618a448beecdc473e9fdae395e437a5931cb4a54ad845d525d92eaa7bbfb9463efcb1e871aee7f08994279a230a230b54de05
152	1	328	\\x6a96f2f8169f8a8073a74f621d21a440edc735b005076803781dcfcea4322e17a2e464d43bc5b03a6cb83849211b026d6f1e2cab2b889a542ac27798c858d000
153	1	167	\\x4073e6f7b1f771784a811bc774c93c4d0b318f6fa74e7dec21bf0e9fb9318fd61e77c7c6e1d0b0a5ab8d554f0de9a998ba1a3d2f9a8adfde362d4fb70720d200
154	1	232	\\xb9db43fbb28029321e6cf8f777bd0c5feb68e92f04897f6b483a08f02aec578ce3178a8c6324f4979d0db45d7568200a30397aec4074aa4c5ed59147a520de01
155	1	406	\\x4b1d3750f35c918d64a8edbe9ff6de469f949fcd8b9e17f410e6eca53ed8283a39b29161289e6c94ed3815086e1f6666beeb03df2cfd2d28e378072fede6a405
156	1	144	\\x144de36f1d66b2b52fc2c3ad255d479c2a2a8f6f22cc8547d6c2d7ea97545674bbe7a298ec6462f4f6f473154c14e6f0c2552da16ade5efa6c7a4760acb85406
157	1	403	\\xd97c8f5f52b01bc51053b1a5173914c32ab9fb0449e788a6ff419a8687c19add3f13e6dcf501f35499adecb536142928e0865ebfd12c329dcfd1c63722de4604
158	1	212	\\xab77e4572681dc39010798143b73ef2818750170ca2ab5c3329514a3d4eb968fb85a3f1709017dabfbfc39d90a8c924dc93d9436563b1fbd99aabedf95b3b603
159	1	38	\\x4c0a19578dc3ff05d94b7db0f12387bf1262f8dc4f7960a113559265e8950ba0737fd4efc17eb6cf2b764032851b5351420f645d7d07c00f5945d90530f5cd09
160	1	331	\\x507ed6b0abcc4dd0adc65fe0da086a84537dc8e9ae06f048e7197fbc83377524281298d877f2c5b6fa7293fb40d90412ee120c84b029fbc2626fc23a597ab207
161	1	136	\\x5337ed63884913490d333dc212059fdcbb7545cdb28d1a513c3797e8ef9cd5b2189699f9cbb9ba28f6c9516a3e800fc9690094ed171e5caea1e28c4d9c084b0c
162	1	280	\\xf7bce6244b8f6a03eff9098c669fc10a28fd021ca7f4b0718ef016d83780f0a6a04f121587a25acebf91ed7839704c985b5e1546038a4b95937cd30731cd0307
163	1	411	\\xcfee8aecbb8cb49188ad55f20fb1b2c2b74c8e2863ef4e08c0ddae8f239e59b1ee253cef7bcb8ad5536f8554c1d3f049abb805ac403a255232d99a3e10dda40f
164	1	97	\\xdbba16bf3838c7ac28373334ca0f44c4ae09429720feb26e5b9b3303e12886468c454938b487702ebf67045c67f80e0cdab09dcb2a49a56f28e32c27c1eac006
165	1	208	\\x3f908c7e2a9b09be0dd60d610b35449aa39f1c0e2ec1cc9f3fe1f24df98f2383ec25006b4427ddd80012fb9527f4e32b539ecba38de1c92ad9ed4d0691d72d01
166	1	142	\\xeab312cf9f86e869ea8adae6c92d852292c99df2d6bd2101a68396c640dc4acc1cbc0564ffd4fe6b00e563a868e395f1b488844ca2cd95b955b8bbc4c96edd0e
167	1	222	\\xd91a7596cd190be66860553f4d350c3c6fcce326a41e870d5a4cb0d4020bfae500cd812059551aa641e6f44b075137a8395b93441cd8020572430dfa47b23308
168	1	304	\\x4718b3f549d1c035d421001a72fb4bc2dffc7c7048ed5c37567c0d97fe17debb38a6938ceea1032641ca01f5dc427b5b55912f69903aa70308be88e024527c03
169	1	312	\\xd1a2fe5b1f3e086608c7ecfeafe5d301041e9a458c8e9cbc49c7caa0b0f34e45b5bf379f321b7d20b23f711f5531fbb5624d3bd148ebd6a64c7a1534c51f2c00
170	1	190	\\x74b5377c75e6263a6f5439bfbf2217fa799ca7168ff7d641c2eaaba02e4d03123ca3685c3672ab5ab839b46aaab3d6bb3571d879b516b650b43bcff2e5741802
171	1	65	\\x949f1f7c59ed6e8646b1c4ebfac8477feec5e0e650780983e4a5e642d230844ca13c51d2665183e98c7b0068bc86730dd5f86248716e64ccbd95ecb182ca9e02
172	1	145	\\x2c8b5ca1f60e8119b14a44b0b45122d332b9eb957c31e98b07973dea517d736eb45203e6220346bf10e812c06d0eed39925636e9684f7dbabafb5c80189ba106
173	1	112	\\xb98ab9adc04ab12e0cd7477aa7049f7504125f633f93944fedd3880886b561314874873163aebdf26db621175def08548b85fac62545cd99763932e75da40f05
174	1	85	\\x3b66c5446e4913168112fe9b59c2fdbd8c4575b1154190718a88536123a5e2b55509f0b1b147f5a21e1343f9122346ef474245cc12482433992d5ed70313ff0c
175	1	196	\\x49c30e3549238ca0244a3f6e10fc54361a05a529459b985b6e194027080df60ceb01bf45e59c19ad7781f35677cd542b32075c00997900aa38736483cf09e906
176	1	273	\\xf007dbe2e2c085831946254e18d0c40b18ef686c8856cf1a2124872b5337076698daaac34ac8536621f594f709bb22e549300181f258c0b4b7f65a0d1f089a0e
177	1	185	\\x3dae5f2a6b4aca78fb4f40fdf5c3a1c78d6e387c7c067521f970c5bd18bfc4570d16b4ebaf2cd997cde6f852c55c01acc0bbb24e2b6d510b53858a6d1b33eb01
178	1	137	\\x19b5cbf4011e7e17326485a5e70f4b56678f7a35f6114f464062917a3463f21c9fb157a459a6d2a65a7cb3c37e131f4276e94bc5e5e03d7859c1e824f9e54c09
179	1	238	\\x96b9353b98478d08a7c4e132bc970b5c4a166769d2a4b7060268df167f7c917e98ba5b943576a90d5ae382fe9d89bd9eeb9b3c8a120f048f7e18f0f18adcb50d
180	1	90	\\x01f6fae4cd27da43ca68ad85af81dd6af490e8425b0e579faa3cc31e218685b33a8912906b84ca6f578fe5bf1bf4dd35dcda7d656cabe4f66cd8764b0b123003
181	1	373	\\x24829901f7537e46e35912533ddddd655fb5c735e4529f05112267632f90b86c826011f23c7a58728b0dc9e267d4808f1f6a2fab3a9dbdee83fedb9cca3e6f01
182	1	381	\\x928f6d576afbfc04449eab3b9a388cc1fe0de6a803f642ff9ce16d30822eeea35c9ca4a590d343745d5abbae1397a90ff81fd80d4564cfe3a6987ca2f40e6502
183	1	281	\\xc7ce7a4ef89b1836612d96cd5aa529324ba81a29ffd71a18311d2f2aabb40f7db5095a9d8d354355e0d04a8e24175419659a6eb6fff39b82cc39d0c323f36e07
184	1	310	\\x1be2450a81cf73089ec7a65b72566eb3c208bb326d04913b1500f99c6b1d511a6ff56dd54533353402987a08786e68e4060b164454d2db929907a24370c4310e
185	1	295	\\x4373bd460868fd2e36290ca8f13a41f7922ef4083ad1b95eee56ca80d43c4eb6b1a7f54b9ad7d31b781222f7859454096a1360bbf4e4eee6bdfac0082961ce02
186	1	115	\\x1de80b8217bcef262bb0f104f4ff8c410029dda476c27c05b7cf483c764b392e25dc4202dae7cd5ffc0fda19fdd39fccc93bbb1f0d2dd0be9f0c4f66e836b607
187	1	19	\\xabd9a25491ad7d814c04fddbdc5c5653cec8ad004dd8613f64143795ec5caa626a42b2041dd4dc74d44cb0bff3ac7c0dc72e959d122111c8b9247ebfb581a806
188	1	325	\\xd883b67d3e41b71a3e58dba492fae22754eb4835c916cbb334f415416d9157d1cd5f1b32cafc97ca2cba5b8ee7a012b593ef9bfe148b4094c4055de79fd8980d
189	1	412	\\x028bb210834a3ddc02639a739fcb4341a7b4cbc4d2ee30cd1182cce26ae316cb03863123e2eec97a10f32ed59bfcbb6f53a9e5db6d508045be1fb76628cf360c
190	1	226	\\x7e8d5034fe8d8f095795dd10df86be6792e6799efe01567347d8415d88baa0a18d2c96dda4f79ca15fc3e73f1b06003cf7561b64799c11215f267c24bb96000a
191	1	374	\\xbd1ec145ce03a2b540a00d202ae7bf41b9203b7aabe7e41e318bb36d53d8dbff48f98a55289c0ee017b4e1f5f61b2b4f3e9ca1234a14eafebf583654da1efb0d
192	1	378	\\x5ae607162f056c9ef6c1d538a553b6da0f22ea1aff20dd3bd9aa502578b4f49a7b4772619205439d0cb7d4a1d55fc3260395f27d3432dd4d176d015b36556200
193	1	80	\\xe27918cf8d6ee468730977e66ad3387e2a64d0423e859dca120866c9f20bcf5e8053d9702d4a2c1221dd25fde1f0c3ab8c1300d7ce75575b8d9ec081a81a6706
194	1	11	\\xd8383b35a2847cb44078caf469c87c668ba312d61bc69bc1e3fd2072ff31e712b4637267cf7b005976ec188631353abbcd6962925f55edbe96d2e704b6a59106
195	1	413	\\xfa7898a38638abf280af95ca7be64cd232c1804dc5840e55707176ef92cc73913eeb7dcfe8c29aa68d8666190ac2ebeb12497a09ada7e0ad9436da4e7454a90d
196	1	385	\\xf080fed80e5aef6da7d2fb9b5166d3769c8e370a5d3d46147c4d40503b28e43d99683580980f031d27e9b79856e7ef647a0f2c0153c8cecb98b380e1e6435d0c
197	1	40	\\x0c08a7bc1f9555b17c544aa4922da5d307b2c7aae82846d1f60b0adadfac75e5d973faadcf848a2b87587f5e4fa80e1711e690ef61b547c8e267fb30df2b3102
198	1	187	\\x244a71825d83f3f53360ff0afa35a976742c9a2e148122b1d862178db78a3fd9fb4b0cccf370a11e051aecc5aa1b8880cd66f73b56c6fdc98edec0ba80cfb609
199	1	113	\\xddce5ba7d576f38474a6d8932a877d4e6e8f396a6c331f5fed87470731b4520a57fc71eb99aafc1b26a12377178561494c388e5bde1ab8679a1866275631ff0b
200	1	348	\\x21a5fd53b75fa31382a7029facd790701555623f0186433d6a6b376c55ab9fbd9624566d5192b9d7713770be17621dce032e1f2722a65562500f07e286299c05
201	1	296	\\x30de91a77e47c8d255e7ffed4228ca7170f02774d19c12766bdcc5f96a276debd6b4bbe36a60eee94ae258a3a875bf50bfa686600df23b9edfd8d8a62d326c03
202	1	297	\\x80f8a8985a1718b9c50fdb9907dde5d18db9ad48b84a28b65dd416bbecb51299af37f1586bd2ac947b90283c0fcfa932397bccb57282bc15fda89fac9a65cf0a
203	1	72	\\xdaf2cde90530b0e03551ae1c3c98664376074870bd3d366f4585b9361cdc84c828a7c96604bca49f40405d12ccb14645fbbf6eec8c65ce3b2e5fb32770055c02
204	1	262	\\xd0a7a8f2b90da5017e0d3135ee62540c16136e83aa72e2960f86a12bf3cf6dd511e00998fd3127f51edfc12d4b3bb1af22b79c0b106f1e35677a8f8e6924c20f
205	1	287	\\x32b18d24e0d43e196d07c13b309f9bc172db6b6bdfb255eef3bc8aa4fa7f656aaedfe4dcab643a1c8af746d823fb7debc9d824abc0143ba3867fb6ff5efeb10b
206	1	334	\\xe2f04e61d6247dee13272fbbcf52fdc25062c81a7dfeffe6bd92cd87313c4f0fb32f66e20a58b1b5541d5e55f2736a078c866b5194deced6a6d2222c1a19660e
207	1	237	\\xc63d7c4ef61e0ebd1d3baaa020b4b0e84bbd261356c0806b04645c2aea77d98ab7fedc15274879b173ebfe878da39344d9e8c229ec68393b6656387dbd3d440a
208	1	177	\\xeb639728d454d16dc48cace670d49d04077b244efbcd2547b10d0a8edde355ee024f8090e832360db6bb98c5f69c30e08dfdc8d26af6964eabf07820f841b407
209	1	279	\\xe3744a6083bf2ce06dfa8a43781d0b465bd486c506ca32992b38e56681dbf8500f445b9c1d836f12033faee2509cf723ed7f3577acdd9b87d822690f2cba5e02
210	1	86	\\xdfd32db729cbfbb5ee40af76343706f20b5b74b58c94661406ceff3d8bfd49991fab97632b14badbd65f52bae697464f8f81b65ef05c26552984dd9d913c0f03
211	1	27	\\xfdcc680a3bf5da2cc73ac43fc8e097e11611e9997643c43f64115fbc4d88b1f4676b32e15c3c4373e8f77a01d8874f56741defcfa885ae7adc3dd30daad75c03
212	1	318	\\x20ab07caff8e16cff86253e8ee0749fd5961ed5f0135cdd1de7ea8aaaf0a688062966bc0255bf175460f025cc1eaa7f42cdced64f257570803c9835870dcd00f
213	1	390	\\xdc29b28cad352d5e2be348c925d648ee924cd434f5f8c0208f38108ab33b95138b33ea0dff06bcf4ab45dc1608968cea737f55b658bd470b92e8c027934cce01
214	1	231	\\x3108d6d6ec8f0175c68301abdd4ce245ba42c984288a49bc91ba7604b74a0896972b9684e75ce31d7f23f85cf7aac9d19d9911f57f7b488f8e79d514ab78e10e
215	1	341	\\xfe66758bdda935a9b530373257a97605dafd310fbda8d777a8a85e16e2a8ed650a4c25ed2c11590b93ce9164c16a36c02d335797208fcc210b58a1dbd300600f
216	1	119	\\x70bebc6895cc774d9cd53d90ec7bdcf4906dd524f71aef9c32db301aee8543578dc3207420e368d3151253d5d4e50fc32746b54d1ad2ffb2d82b95e3521cbf06
217	1	376	\\x53f23a58d98aaf87808d6cc5d7b93fc46445a663a24f86c984269d8a3906bff299005fc6a45dcde70e1882a123245cffa5e1321367d35d00c19d7abc02e48e07
218	1	379	\\x0cacfb9b090cf5595797b3eeb5085a58a54d31210e494cbfb25e2f2174ed6e8a6c1f60d12f664b5079c41c905bc988a0326e0db99efa8c56ae6557c1a8e76a08
219	1	47	\\x43efb200415072ed4d27699ceb96c603009f68f623c717e5487779f5bcf20c6a1b619aaa51611d9d0c1dff64796ce2b6f6858cf90cbe0fff5838b2535006e805
220	1	206	\\xb7edfa6aeb85f6ce18ab3c899b4bbda70cbf0a2fe2974af3eb12bed850f5d2deca5978062c320d0e0d759201b9f999fd4dcba66541a93c4dcdb97c6476f7cd08
221	1	133	\\x0712fb7dd5605c7d550f131ba68303932c757243875eaf05f7a35bdcb6ce7d5f92445f93ba6651d508d92beb462f5ffd36a3dcbeb52430d264f1d30f462a1005
222	1	286	\\xcfa5056e43319aa316a387f17ba4511178742351f6032d56e83832700c56231d9a51ca8c761ee2a9a23ed935adb4320f6db8fe746c3ffb826b1dcf965ce0fb0c
223	1	45	\\x8a4a94333b27206ff219f6cc5183aec964fa234e288925bcd6f31e1889aeb3b6567aa9dec1846cd4e32dc1a5d15690032d7e4934c19d422532a20e36ea4c700d
224	1	68	\\xc83605837880cd885c72f256e303efae2c39dda779273ee8a5d64122ed7b57a2e6a35767dd540c006c453fa2e9922cd10af17280748261ddfe4687f9eb25ca0c
225	1	361	\\x46aa872b4c24814dedaa83996b24302ed089508cd77bf0508e18e9d97aa7d01c55bfa5c0df5a579fdcd0420aacf73be29364dd3e6b9e5e7921465dff24180300
226	1	217	\\x0500d74d3ab844a461f8c0f932e44ddb3f736fb23e9397a74ade7afdb3914250e30105ded23cd6968cf59a06c67f7f23ee1f7c2e2839c490104e51a8bda24f06
227	1	209	\\xb9327a16da465cbed6234dd52ff26ab7fff427cc0a22037c926205d98c77c46ff3608709a84030884a354aac4b3e7c0f6b529c0063983ab86c5096d9f1fa5406
228	1	335	\\x1fac1fb44c0bf7a19af7e5716a9450191a3ba6326906fc4f24858e94eb6489706d02ede1dcfedf1b640bdedf9705d7b793b71ad15097b4a8f9d35025205f200c
229	1	283	\\x8f21fb1eb2c64dadf46c5a4d046c70c66abd876091a6cbb78230b1ee175cdbe115c8b34f1ad32f47cf1a7368732c411485cf335a03bffed2cbfb54058720780d
230	1	355	\\xda14b620aaefcc4490f1b7cf35db7a0a482baca35462ccda3dfabfb5c6b3bcd15b202a6337f8c79d5bab25d07832cb95585026cf0b8bab6222c3dd7e3a8dcd01
231	1	340	\\x265b7d1125adea77600238aa7de6ec23931afcb05fb62702cb72038da7e8cf9735c07f4fb3d3f78a267df2d0169a919a93e050a2572340861d9745784db4ce04
232	1	169	\\xa4dfebfb225e2bffad706189b0d678ab86434d3c1fa314576101b614b6dc645c8ab3dac8afd31493c7947124291f97eacc094ad26e0a9ff708d768f96a23320e
233	1	315	\\x98d0228fc295ffbf50935f6899d1682246bb9daff491cff7d672bb9d36eb5612d5386d05869c26c74a0e2fd32798150cdde2ba9ff035ed9cc54ab39791b3b20c
234	1	122	\\x275b2d9524b8f9d05a77825cfbbde51ec7b40b22c63cf8b7a71cfce67a41c0e62e39b06163a448f9ae83b5182877d1602c973a52807ccb5010e91bce3ca40002
235	1	143	\\x92d80ed2ae4210514251bc7fa9d0a06b1077b70bdd5ccd3d8be33f07b27c7e4c6f31f5fa43feb6a2de99dcfbe93807102bb884dd3731ebc163ea1aa231b82605
236	1	192	\\xbcc776c296fde9a3f9410df4b822b7c9f337fb5de729a9340013664fb8a5b93f811d796aa9d938522dcc424c03f4e2faf77967cc2a46a6794e30c394ba9d8c09
237	1	173	\\x53b5d9d7e03c202151197b71e6c5578361d84b507eea836ca204804970890c8451f3027545c3b1f3713ee1e313e847b09c353c85aae56391a66d242b311e3904
238	1	9	\\x14f3f9bc4cc941a843bbd33137a041de48dc7b059668060a484464b82a58bbc82b40497330dc3f4810736df864ae73fa98257855105f064661abe4b37d2b8d07
239	1	8	\\x6e73e37c6790495a44aac2735a2fd706d173710aef37b65192b189063ca870d83be3365248d461040b8524ea8909045a662d3cb009c1c3affb623b693694e80d
240	1	162	\\xd4c8047dd49be8a3b5d7fe3bad8436c710af1b7dc344c64fd0137ca38b3da7cffd03066cb9001be73d74bb5440855cf86c35233f69ad8c028926db845e1d1505
241	1	166	\\x8063da19efbd101fdce5d301ca90117cea9133ea6972ea5657f73abbd27bf76afc7eceb3963c7fc9eaf0d3737291ff2817761224113b5f21645dc269cbc7c40e
242	1	193	\\x12b38b7b380da1819b032f1ddeb9d33410e84e76810a5299dcbc7870783ab947adb2193154f6e3614f484a9b464378827ae9ccd20ae2f89dadf7ece79ce57e03
243	1	175	\\xe3347837d6c8551ba50638efa0d6cf613811d0cc1acb0790c9a3864ad5ff68695b5a833aa17001f54b15b37fad38e83ac30adef9a8f9185b74029fe9e46c2503
244	1	398	\\x2adff55d6150812aa68c91cdf0f06e74d94a18a990f1db4bc7e4546adf46289b164baffdeab7c585fbed1fb2e774155d273196c3aa7cf44945c5f573bbfb4b0b
245	1	194	\\x70e90c779f415de94c26315879913e706d3b09e670ee2a8397dd39202b815493cc8acfd275ed26526222ded2b3a6241bea50606710834a8c598b33e5cd9b9507
246	1	54	\\x18927bf9a28673a12afa065f1bb7b70b3efba2f782f667ec8f08dd8a41361f682e2c1a190a235e0301522f654022e466e056d6c6b40be199843b1513c689fd00
247	1	395	\\x1757a1bb974269298cf1e35d6257b7324c218a9049f85a975ea7d4e769b417b4287fe93f5969959742d53f0d037a3cffe71b0a373d642618559b25405af43a02
248	1	300	\\xb5f1b4ca436aa5ae56d5131391201c7445040b21821ff3d0a48b813d384d62a647461d20b349c15899978b83895a435107e13b17dd8b3c5c6beb9e00c007d304
249	1	306	\\x767cc6343f5f0193c6ffdf57c58e871a79ac1b8763cc225006c2e40baa47d8b7185105f4ffff239483d46aa9797b9a67377b5013edc331d7ae0ffd987f621d0e
250	1	332	\\x3b06e6449c37ae394a2814cb1ea61829aae476ace2795706b2f7aa506f9903456536be55cdd8d7faa30d116150ac610b6f6d32b052eafa4d2fd63e0e3dace102
251	1	365	\\x78408d8705befb2f0c84bebd070bba42d722a4b9e181a650ed5adfe5b6151774f943bebcbcd1e7a259d9c4db7da9cb9fc21e00e9a9f80c9c5220068446a8cb0e
252	1	405	\\xbe51b61b8e068732195a8e7633cc5e34ca3f8d9d90bf6f67469b499e925bab25ced5b9e11741b1c4b7673ae2bdb11754fe5cbc3274a068a1249619f32813770e
253	1	409	\\x93ff25a437799bb13700267a6766b8ffbe43a6b0421afb830cb1c463b06e9708f3b840f0109466324124556e3dbcdda1b0de50dd5be6250d8007fabf6c534003
254	1	200	\\xa685188adf431032c8f840d529480b60e84748a9b3c08fbae97d7ed374ba3b4cd84d8bfb08cbcd2048e7191c08caf30aac2fef01c9475db9dd69d3656717ee04
255	1	2	\\x549b38acb02dbd4f21ae6d7e61595935188b015be7b6d9d82d65d94f4eeddc0e3e02dacb8f1ab8d17b6e4c3ce8287851380099e7a32daee3296902bfd3f52f0f
256	1	275	\\x2e3b299d0430932c4ced56b951925484b41b4e225349472b4f7f5b016e43dd86650d90419ce56d3332e779bd00d67a370c77bcb36c69c2d5c2c4594e06ca850c
257	1	302	\\x6fcabb954a6553a52cf67bf6e5d885f28a38b41fe34dbc0a6c02141588698afb882b4959d66f8a9789a61f2af585c619f6b78066f12b7b6c5bc11ff8f543e50a
258	1	236	\\x418d89ecaba313a6b258240a6f29f68f3645eac0b84907f26e06312857536312fed30972c0eb7c120bf5084470783f8ef09c85ed666b4bc6e9e7c6fde4334f09
259	1	399	\\x5a0610d9269611b3b1e3489712168f5bbe0bfdf2f249363060fa1626eb63fa884488803880e9f709ebfe6655c447d5ab174b03335f9f694a8503ae32678f2d02
260	1	64	\\xd6e1df7ab27a14b6f5571324ceaa59ffac2a790951cfa82521e404f1fd882db3f128b5394765efe32253796eb73e5b9a18be10cb3d2f8e9388115eec9eb76107
261	1	301	\\xd8bd7f342045c93360ca4c71e8eaa6b9bb835b3df446f54565e5e3a0f9f8962fa42e308fec512eb3373bbcdf5692281f82b0bb81a852e50ff14372a133c26003
262	1	87	\\xf531b21ca3bcc74dbe43c258f71e6cbe699d2db5715c91fac7f3f1a9ec944ffa129b0cf75ea1f38b13876e6a34216314350ab578ff5fa35e1256b5b626c5ca0e
263	1	71	\\x8362d88f91c6bb5019b2040ffe20ad2655082763373cf44a0098151676ac5b6b4dbf83cad97e700effbb155d61c4dc2b845acb41a78e2bc4c9f7e04710cc5a03
264	1	75	\\x6819cc96b33d1aa50758ae0e9eb9d79f52f3d62442150a51bf3724aad4f401f5a725fcdab0e77f7305d4a13bfd638ef2c3b0f35e3fb7d2b050c42ce652a54605
265	1	291	\\x4c41f5cc0f20b80d76dcccc1c773f5a41bc5fcb47ac72d357a5bc6ab9b96614c56a775b314bffb3de5251ecf1799a749e29fb4ff1ec2d96bbf2fa157f1f79701
266	1	158	\\x49fb80150a26c47a540ab6a41c5657d08c8129c96845b9b12e0d78cf7092a060274bb53edc53b8f30d64f28710039de181f15002e6759d89dc1f8bece9e84706
267	1	121	\\xa2a1c7aa45699a35333c1a2bd67969edc1efc63294755ba5675e2df04b00f810485f6042a91557ea77ada6b0bbcddc2ece0ebd39939b90d9c606ecc7c9a2fa08
268	1	298	\\x5d931034f8b256738f4e3e4c351057806c0314f4069bc9e89f5d689cdb84a31f91ebc4d06f21d6e1fddf18fb99533d94b051bfeb3fcf4e0c43915d771ddc510c
269	1	180	\\x9cb1e4d55596ae132519cc70f0b95effd028aaf0ba45ab1c7654f62085090c731f59a6afdd090dcc48e786b6cfc021e54b137ecfe8959bd38b63c8427ca1f903
270	1	67	\\x2382004f68241daf8cdd5c6ee2ec16ac90d1f48edbebbd26403e81260281aff2386ce2f38a3ab9f15295127fc41eb2559e3a7d0b011bddcd88760fd9af67ce04
271	1	330	\\xfe2edc467c83254123d8c469812de8e431a1f0535ea90a56cc7e2a3e1dabb1b52a3dedf97bcb61cba0c94bfb42972c02d0228717d57175e41938012a58d43402
272	1	101	\\xb7d229f456672e119ccef5f3fcb73d5189b55ae0b27105ec1f82bba293e15c0f58e91e0e8373d2afb2638d282e97af102d5615b30a2560c7d42db177b8d3070d
273	1	170	\\x11d0f75dd7f74d72a354d46398ee95ea66dfb1c60335ba9e878dab66aaecf853cf9d29756146483fabf255ff4b9a492e709797afa4eeab0cb00f45c10dc13308
274	1	44	\\x19193dc51eebfd4638b76edf53b109651222f991206a7fec0ddd62693f0b36fc7196eb82a65063170cb1b5d3dab70890671b391022ff73057406594efee7d405
275	1	203	\\xadcf044d4de81f92088041b83b6adb370e9f1173964dd8de7dc1c9960eea9b7308a0aeea8c61885a2dec3c466d6527b29e315a58e2eac76ff285753a5fa00403
276	1	338	\\x698becceb986af47684bdd257c1a067d78cdba8bbcdbdf2a6d94019bf0eb2087e841e85742025b26e091ad7983570b4a16b29963ca9a90a255886a1c0a940401
277	1	114	\\x5e52b59e39e4f4d419f80d2e3a093c45a790553af1084d1a9b0df17bcbfa878553e8792716ac0937742fabfa4619a456bdad863c73e8b98a07290ec9da936e0a
278	1	327	\\xe358d8c24fe23ce02706bdc7196615485dfb7ee92237f7e7b0b38422f8345feb1334584476e99bbd5ec8a618342608f436188fc55190fedfe22c13e35dea8e0b
279	1	285	\\xdad2363f08a4a64492fae65891e47b63ca6e0b767d265238dde871c44851ebbac73ab13498503f734a1f4cc5d12804220c9443865d3471d77dac8db8ed080605
280	1	156	\\x7b509d657bd5d1102b9b7b551fc19937a8cfd93bb94cdbf64899f0f1cdbe72c5d08f275d04b5c9b1044f4a65c9be0ef3b611abbd2da7ac3a9e6db8657d999606
281	1	397	\\x01410d6a991e8630157cb43711a6dbc11883c084825a9a40f13372bdd490a66c0a6e7b35feeb84feff81a89e00dd0979ebbd9a85835e1d1309664e47def9df05
282	1	386	\\xdf6bfa5a0da31a712a226c139acef983e7b32142c9468427630356edacca21e14a00b720722c6ea21e18d6f6cfe604328ff8f4257d152a56f5da6a0555592b05
283	1	130	\\xa9899b6839bbfeff7a79a6833da0a99e4c8c470ca9134e97aed8e740e4fa48983670f914c0f7142ca5e92fb1d577c12b9b549070a334573d9bf0d03c2233110e
284	1	420	\\x2c78ada8bf10af014a9e3c02da03ea73056c40f6f7847b87e1fe51da15a31f14962863532cfa7cf45b42102f454075f522a6507f4268f5b0a81945d99c777a09
285	1	70	\\x02bf8c1e7b0492b0e1557ba7239a600de2d12eef8a99bddf3779b1e53d5e9abe58962d78fca8b426f08107e70ad442e86ac156a97f2d9fc0510a91169031740d
286	1	248	\\x4cadb7793c859fa6e285da7fae1bf448d3f4020ac7740c993c25e247e40d632c868776bc950f71d1e2a920f45be57dd5733ab8bc1fb2ed80d17c0e9361a0810d
287	1	15	\\xfb4b6a1cd456e3ecd76891813fe3c29e7d10f9d418a3d81a82186d56a8339d0992405536c5e41ea73f877660662348fe110b9d3dc610be5b0d4289ea9bfaa209
288	1	342	\\xa5b6c0c050181fccf1854240b6f0966783d3e321c7c993bb15be92cbc7583dc723a2fcc161342a4b4774998a04514919bef72bee5a00c5f8f977743db2fd950e
289	1	317	\\xe9a8955b8c8200826bc90287bd1381863f9b87b86d834081b5d3b0dbd3465755ef6f6c5e765861810908c50a3bbc20dc212ecd87af01504699dee4b5d57f4206
290	1	414	\\x7ef57a78a4691c60b4b72210f58da5e8c1c2ac33436004e8f4d577bf9f5ba060936034a4e52038a6ff472764046779c3320b6d7036e9675d952da893932ab800
291	1	93	\\x31c8466d30cf1bbce09036246c0c0e7e396cbf20f84fca4941988453658a0e37d430d3e2932c515cd75ab8ba449c9167d7710f2bef3c3907e74a5df2315c3a03
292	1	81	\\x891975bd79c5774079dd56f780903725ac77f20babae81583838b40b5cce0dd4dfa7732fb252f57476691e8a9d53aadf98f1c853460b8249c69578c86555c30b
293	1	242	\\x0ee47758649e90451155f4cb5504a1bf3245c8cf69f90940f4a7aace0253a6e12c7ccfb3ed8fbc12d3692cf08cfc4010adaaa4b6b8b4eb8a823b769e14c76d0a
294	1	353	\\xc20b3cbada9574e9c7fb14cf99ff31f6a11ff203e7d12df1adef00043e500111c1ba7673d5331a8bfe2e950c8066670d9081b0f867ee689fbb41ba98957ec209
295	1	349	\\x6b62f986b90dba3874e1d407bb6722ff75824ceb7fb2ec66043759ca9af0674a136128192d8ba111e35644e122811645013a9ffa95711ecc04372470d8dd6f0f
296	1	392	\\xd2bed9acdb89e842fd4f45c5b227d2b0a743d4a290f3399147e2b0e467d4b4b7285dc21a41d83822eb56abd745ab283a1a7e980013241eb9cd630e6fe7fe2c0d
297	1	182	\\x066cc84a84b3a55e939300c894e74c2738248ed664e952ea9411a2c3df52793bd864e3898c2881b5577042ce9fc2b30e430a2149784ed53d95efec6a6fda5c03
298	1	141	\\x7811b07881f9e4daa70ed7e99329d6fb05073f87e6eae815c095361136bd09f9c6c9043bba8703a815f685fe4d54abcae01251d5d50ebf6dfc4a8a7dbbfa6d0a
299	1	282	\\x118a61058efe08a0cd3ee35326495814d8cb03da427afffbac795abae70ebe98b5d2d7d47e5a2272fb941ba0bf288274d4d7c98ea45b2928766d4627b159d909
300	1	228	\\x381a842da5e06189f882ead91ed65591989b33ec6c55fa019713c229214207f0d431419d6261b5cd8b1612694bb8e8c5037dc312a4aea1b1f0dae6e00aae840a
301	1	307	\\xd89eadb4df380d9cb197035334a542c018588142bda2d068261f825b08155c9d14de868dc95a5cf7dc440ab13cce0e9bdb01ec7cfcb5c21891b58398fb632f05
302	1	16	\\x1513542b5a229d4381d1de472f660ace85f34e5893bf1168203a18eb587c3f6de556269e3ba351bd9df7291484806d1a1328146e2e563937fd04fd940215770a
303	1	230	\\x1f18e249e07781c59e7b7d8e7ad8762b4de242e51771fb5741f56ca6a00cb66e6e9d9fc6ecc6180108c85c9acef01af829f2f37da7da5302eb96a5dd851cf800
304	1	34	\\xee3b33680b9d8d020c55a9e54780d3ab1bd572cc18687dd3852a5afb0285af8b0bde3b48fa71e59757769fd8e1bafe124af20c813c5891882b36d2e465bf6700
305	1	22	\\x6afd1178b477f2ea47db9b1f39c88900f739bc511c52dabfac3e266ae695bb2fe0bc4a55089b4c50c557ed11e63f86bdf05ff74ee5e0013e0c1a2a6321a33c0f
306	1	117	\\x65e36944f51a74f0d5798dbbd06f1a3d0bcb7e0d77b081df1dc416749e48b239db41120b1149d92f7ae9b3e47d4dfaaf50d8f45a373bf377b251340e68e8d30a
307	1	100	\\xaf991c5b60ee640173e2075e74cfe75eafe2c2aa48f4f88f139e7db80b28409f79761180bc41249541f8011c954b4b37e4cb95c32ded91ff64cf0df5b375d909
308	1	186	\\x9a18b43c06fca5842bf89d4d2c35673f2efe8c4b646554bedd90cc3ba7cbb0493de06e064abf964aeb093485c53a2776da10c848d48c0e489b2689d37c67180b
309	1	205	\\x87d390540aa5ebdf8f5ad3df9c7bf5a398563305ec0ac7b2f915bdec7f11d8d68ff0434d785b9a6daf4240e06dba380df47aee9613613a5b7f4077e50f99a309
310	1	13	\\xfc4466ce7a1a0a18a202cecd07c984461ad31926e353c7e389ce137c7061bf4152846c60ee695d48e564d271ebe8ab3a40cb49368ef9779fcb1062088ba4ce02
311	1	263	\\xddf74c715d7066b8066d56fd8a5a397868b1c7875b680710f3c05a77be08576859318dae31ba89c917474a17eabaa7acfb75b3a9ff24d7fb3b786db63904ec05
312	1	267	\\x4e4bf293559480497dc2c9b7f4e0f091defedc7f0a8b40f6a252ccc2251aeed83adf00cceb4e7c3c1944703b725d14a049000b98ac08e0479f3c3f669907df0b
313	1	55	\\x8e5cd8272f94ea5121a26bc810537cb3069195ef8954f677f1c9dbcccbfeef62c2215099f44bb00ba868d0f5147f26b20fb139a9956f67916db03d3ff2b2810f
314	1	260	\\xdb706678f88244ee4be8b504b78eee8761b02bb300632ee3dd3992d9704a8db04fde083e18b7ae4f94aba6d87b4f1c6e0dd34985c92f2d31a341e120d2ab2c0b
315	1	271	\\x4798391ea3f259b9487acc335d9d3bbf81cf86af41d74053ad444d84acf96ca6844ab39c11cc7f8bb6479b3c3b0370c70e3695bd8e758a0555b3d8e7066f7e0e
316	1	216	\\x1e93f6f71824499ee87a9a2f6e52463cabb602c4bbbe12126108c103aa7d531c983eb12fa5ae9cbbbfea0720cec00703d55e70def3577b4b2b7f933a2045420a
317	1	160	\\x7de1544424ef6ca95c4b20e8b4fc66a87b453cf585507589e9e21907726a0b9f6cc738b0ccb05fd33e8c3d8e17c46bd53299ec96d2100fac5757e18d3b8ed109
318	1	139	\\xf0038bbc1060e26941360148208659fcf5465bc6e0944bf2e27204f520757673765800aa5bffc0903c87846bd033b178f2cd37d7f3de0223426aa2401411a10b
319	1	215	\\xde1d83a8a19ef40e1c041364ba0ccd20c17a1c488ad2bfd1feb347409f9dcfc7007396301085ad4bbf6862cc71b828627cfd42f0bc36fc888e78a19ec225b501
320	1	59	\\x69c9b27bd2be5ed1be82d4b50963f018304d9fe9da79a3854b0ecaf6d2eaede3055d24691046990c1b1b0fe8418ccf5324092401fb2ce1ab0bd13654409a350c
321	1	157	\\xf28bb4fc4e1a8601a061524132923aff2baccca03c96c2a072b5de1d10c5aad9c7a2c6a856dc3ca7144ba3b587d0ecbf5c33207ab746914a48dd81849612180a
322	1	313	\\x4b4c5f71377ea393ef19823157b06bcb55d71ccff2b69b7e8495df36c65d5f23d20433cd0952e721481d1cda2fda9df457f3e92f71a33a41ec4abd06dfd68909
323	1	23	\\xc75da74dad951ab9f07a68c095516b737830e0a601a6dfc2f9cd464de17f45ad029535cd25dde3e7a863f96f36c67e2b080bca9d7bcd2efcefdacd79010ced0b
324	1	176	\\x688016fb87ac95cc0c574cfacf0ee5142c742f8af4e525a7d35e14153cb1636d27d963e4d0e0bc11e358f0d324d873943a2230b482d9f5c42cff0eaf54657009
325	1	394	\\x0c7b81c5048ee88a680dba0fe16482fa29a499a1a9e95956a48a2eff3a62b0c09bf29321951623c4361b576996c6940e491bc9b6a44d6d3991790f7b62b73b0f
326	1	252	\\xd5cfe190d912362fa7011be4689c2e06a1a27b092af72f9898535aecf18fee2d7a144a9fe0a6daf85523ced4f819c0f98c3e2d161f81d1053437434711cd800c
327	1	293	\\x20565a42527338114eec11415bedebd92fb28a6be07b93d57a629e509d4d004613b158bef104270e534696c08ec5ae350371cf33b6f6d3b3763b9e15ca30c308
328	1	410	\\x8e504a3f1aa1c656778975cd9ce0000e569960f39afbb27552d7dcd18ed236f178879923926f09ccd6c6fcc58cdf59cc0adb15aa9a90ec598b3a475ff33cc602
329	1	84	\\x6bfd0007b22ef7c2cf4289dd93d3ad20c0ea0f8d1abaf6b80b4ba5274547ea8c6b6230128db0060b14fb692fc0b90832686ffcd6c7c208c4c3748e40dd7c4d0f
330	1	389	\\x84ae0284fa01aa292bc18140bb79b10b272ed420fa6e18db13d86b2eab41ee3fc6b67a2238f8603a950aaab3ff72fd8f54ce2340541fb2c95d8f5760875d4607
331	1	244	\\x44e8a3ab03c6ceb7c3a906cc8cdf44c10b5b350fd87ee2c098bb81358cdff4e75d54babac4401c449fdce19e9515306dce957104c15841c03b11261b91208203
332	1	276	\\x116ad43a6ac4254b28f40a5b5b1b7fca2f61f5feab69499e9cf4648c98faa9c681e0dad20cdebb7f6c9da011616d4a1e0c84fbbc2a32c3da44a4fdfe2789bf02
333	1	184	\\xd64d7c8bb73efb02ea37b9b9583612ca3dc9d77a9986a20b0c7c61a4ebc916b8206438ef6d41bcded0749bc909db29f9bfa96d1cd1411bb1c98ddd24ce629d0c
334	1	233	\\x4b353d26ed39f830671234dcf96867907ecf4b6a15098313698a4e74f26b6a97944d293e5782ad61ec7c680776259c443565968b929ad0b3a75ed58e7845e300
335	1	396	\\x8083760879a26d9f9f856f43ce4737128890bf2f29a9d6c13f6ac562367fdc1abeb48f80fe8985475610950c53aaf1a1b5044150aac72b89adfe3123d9717f02
336	1	123	\\x0b6102f65fc1fc41f0a404e529718afd408362dfc2afe789ad3fc1977c12e9518c14b671a9057dc302ca022de4fab72c21aad7df0b93f82a87cf73f4d2337801
337	1	368	\\x7968c98717db5aef2d30ce246f162e946d6fdb2b1ef300d47d14bb651dbebe9f40b8ef3929c1fed23bc344b19b95d2af071425794dddeda6b0a3b7e6cc5d550b
338	1	132	\\xa76ad247deb82aa363c5e9770e8ae973070c454822dc1dfc599d40501aaa22472d32631a6ef8d3ae77cd62656c4d3bcef319d2e629d30e44521c25e62a63dc0e
339	1	347	\\xac621341bea22b999024077c0b1a8df7034598892e7be47cb90c8be58ec7240546a3bc36c849bb018a698c2b200d85657eb875cf9f919c8a28805f88799b6a00
340	1	172	\\x9f0abe6319f9bcfbe6f0399dd3bb4169ce431732ba65a3ef5c3f2b15a64b9cd4c0f93729df03f5fda86644914fb37f7ad3e39f5837e7eea762d95ffae8cb4709
341	1	25	\\x70c5ad14deb571dbedb7bfc1c5464312907bbea67d7d7cd88d210f3abd8ae940e195ec35d1094b0c1e078f825dfb2936a5a386a0dbf799ebebf4c50aaad15000
342	1	265	\\xa67818c13e59fc28fc857690856b688e79c6911ae62685b7862c992cac49f7efc7715d202c046078be122db3e12846a9e649754d6d84b6477fcf56f473760e09
343	1	94	\\xd0a9224daa309b6d749f150f3598a9fa954a9d9c1dab635e21356c421162e399d649381a6f800b90f0fe57cafc90ba75142210bbe3efa79bf169c9c8d7f4870b
344	1	358	\\x00f77fbccba838c4c2b0e5b5b23bb4eefbb1f000477b327ac63fb24346b6bf9fc95fb8c1d0811cdf903f103a3ed5e3e4326b3fd5db662c656eaea0636d503204
345	1	6	\\x481abf6a21b2c31582c543c226284866488f36e9b571c69ac0201720f993a31cc476f48840524162f385c81a4989f079622032e1c3980f74d83b46611677e50b
346	1	323	\\xe21d834b47a7de69feae89569fa87e82e79368eb8da2d493100bcc58f4d2e9366e2c6d35aedea72e72fc304124e31de081c3e2095db0082f3c3cec1ad3173a0a
347	1	356	\\x45737595bb6fbfcb2c5a6b49f2556f8b111a824dcc9b8f3c7ae14257ef1d46d7299271b24de9e9ec31888b3acb945007391090b14c91aeb59624d6723dc47908
348	1	140	\\x482058a0ff6c05fc93dd435cd27f8a2a9249f4185d0b1d0c92a215363f366cd9842e41815982a6e4bb35829db8fc18cd2576523565e86b611d639212711e6d00
349	1	118	\\x3cd414a84c440a32ee68293fcc1c358f28eb801fe0151cf19c248b2be991ebe1cc380bb9ffdfc8db80d0e9179c9b25a02843c5abb42930abbf34cdbff43d1604
350	1	116	\\xc1f4827b892451e790b8bda8bf264d05785a167cbb9ea4e04bc5ff4819a9e4c123897e86c3998899010e3ca40efd3b1c8e9e7a99f809b26649ac88a38167db0c
351	1	30	\\xbbc1242b7712e0ba97d6ddc326e31c93a0aa08a411cd20cc5c0872229f8522f81c75223609de95928a90f97cf7b438a3681e62ee36fc5be78010b66f217f8303
352	1	250	\\x5b549c99325cc8b25b9b4ec3eb4c1e6cf7b1311c41e744e9c11029782ddf213b761577390697a71fbfcb4f52d16271117ce7958894edc6ead4a09e7d7fe1a40f
353	1	210	\\x0b1c55c48b7d6b418385814725c91bc997e6b6e163a63b7a83f61d90c70089ede97f3d2fd6dbe5fad4c710a91985f6280e00016dd0b35a5bc2d5ff0b0d80b80c
354	1	36	\\x1cb63b4ea3c3fff29949cd6afd7e4026d9f176dd680738ce1b4a565dee97d0214e6e61d398cb42214b406029da01bfdfeaa8f35cc18eb4817c8ec5e98add3c0b
355	1	253	\\xe50bc1fb83c66de2ea3bab56ffab8bd7d86a23ca1abb98fd2345ac5cb7230b6adea88af0772464bc670c9feb66e365dcf4163827afc53e528113e049cfd44007
356	1	98	\\x3968efa8d775123f318bf4a0884b4003e672f2368a90e5e939bf44f8ee6085f120333168f82bd069f453efd5d2e544096eb202cfed83c5a8f8a1b44244868c0e
357	1	344	\\xdbb63cb6724d2494bd3bdf31af7a54856f788be01ec50a162567da6796f29831e1775f63e6385163f3fb7f59182f66df9ccd60f3bae780217779721639f8f70b
358	1	418	\\x798c0e0a89f39efe0b7b2035e8abdf6fb94e763a79dd90e498904f4bd334a099327d69e4eb5057ca50745b5b78322d6f26d8462cf11d80f8b0d777fb20422705
359	1	96	\\x50cec9e2c83d9011f5429776916dfba3b704eaeb4c7012263f9d12a11ade4745be7106031b0b6a2448dd296d3b60e137f47152e716c5166923e16b8cd51b2a06
360	1	270	\\x28e3c7f64659fe206517fad4a577ce605c90aecaa3cb61d09f313326bbbdeb524d162eefbe6488b5749bd2ad4771ec29b141a24d74cb64ea871a780ca6c71201
361	1	284	\\xfd924b20ab62784ac2d2561fcde043d3ec0354a5b98a06995dc37e988ef4a01465a523eb32fce4ff32790ed095d3868539ecd8fd170212c081c5ff18acb87d06
362	1	111	\\xd721da4c892f9225d470c6bd60473e282e85a8f17269562c2fe7d1c5af11ddba75fd17ef8d6976504818fa5daec8e24b3444d63c776066bdcc449c1d76aec902
363	1	82	\\xec406155d563238a92d208c8aebdaedaa719f87031ab238ec907d44987914e3c00b13ec600e852acdb9844b3cca38775497fadcbc89012b1c39da2f65c63940a
364	1	388	\\x20d897b2b7a01bd7f7e95f8d922e5bbd6c8382d135156f1250513632032b4a6153e1ccb917d902ae5e4932bfb78fdedd7f255c28139dc12ab7c5ea867254870b
365	1	99	\\x0b9f312951de658fb3f4423476689733448dcbc735ef8b7347873440bf4374117d95fe601dd866b74d582c0d0f006a25bc1d41457e786bfa4a28d49042c15f06
366	1	146	\\x16b6d8f45a95b23e2275f2592d3d85b427d9e3220ce233c126dcd4da50238800c9304b1fddc0b6996d8c7c01c90f74c299be66703f7821b1c1093d853633ba0a
367	1	225	\\x815efc5d9a3633df0f6a19d6e3cf86482cde6e095e4302e40ba516b63328573ddd6045fba08a29fb48f8fb164c83258e24dece907d8abe14957692ce002f0109
368	1	37	\\xa425568801f48d027b6e298e893bdff649c75690cd460684c71ce49fcca4deed135c0735d20a2241a59b016949e553289674f8591fc392b390afd6f3a9f9930d
369	1	29	\\x56d239663a711b30cfc82a9b50ced91584330b223c490315277b43078cfe18375fc5d9b46d3acc4ef00c69f90b6e56735cf3ab6b5c5a9e358951a68da71eb908
370	1	69	\\x2016580e4d28da9c0b786e9f40c19060df2afeaf6ab91791e860e2e52567ef929122c5331e31d5885f2b0c2ec1b0bbc9a30ce9267d38e2e5c8e6fa0b25ded60f
371	1	272	\\xe97eb34b07b8000549cac9443bba19dcce9668edbf1d6f868be065dd3db0e0c6a206662fecb92f128970279ebe8757fc59b3a6b03fd1dda5691cc68b163f680b
372	1	51	\\x6892541c5967f4e7901c6813e621573a47b71fb1a43daaecec12090704c1556d3a4dfeacaea29ef41f40fc49d8ea67f134f63dfcb8b5f45eb365b285328ae20c
373	1	108	\\x69ecc4388fdf58888f553b48ef6a7b9c990487151eda2df6f50b1b3cb111a7822d63d7c9509a882a74699c5bb6f374d8e315ccec8549753b3a095bde553e0a0d
374	1	372	\\x35a12cadc82a5d67f66e131f5c4720217a4a41381f36c82625693185c6fdb3845fee8b7468efb5a4fe1c27ce108eb124d4c3e43c82302ced834edf6dbe105900
375	1	14	\\xbd6343d240ad3e03752793b68b1e1bf8850f5db7db6e7f1dfeb7264bdd22fcaa518dd27180a815db59209c70506f057a407b84a2b63c3e7536fd553880402406
376	1	249	\\x5c827478e2a476655b6bb7401fec5fcf9a3aeaebbab5a7f2c533de45984795cf449ac429746d54824bd3111b3cb3110d0984763c1b8350b94af59759b57fa20a
377	1	321	\\x05ca0a1b417bdd14ea02bd27f7ab7693a044b5184fad1ba235e41a925230d1e6ac38a4afd5af1685cd0b56abdad3feaf715b12f3631e4fe6bf769d022beff809
378	1	91	\\xbcece62bf6b3f220aceeee090f0a6217fc21491c954ad5439145268454cbf4de81068360c76727777ca86b78ab95e41b97406cfc908c982b831e107c83e19f07
379	1	89	\\x844d418d75894e238228260a302aa942e48ade0c2ef899c9c995fa110b412b5b57e195d19db74c8b26eba77ef5d8797e25ab4e874aa55ffa48a5f2d99ebe3f0d
380	1	266	\\x3421f0ab56300bff4438e55a7dba1302f9cd57f0dc3d89b632feb9f89c7bdba9859411a064f593b2db33931f6b07d840d7ede4729fb758f27499b91b18bee70d
381	1	391	\\x916cedff84d363720d6b2ea464562d5959dcab6ac126c799e2ba60fe2feb59ef0c991dbe447ee082903b765be866a313cc0a8642ab191c2750338ba7cfb34102
382	1	28	\\x5c5b104f238200c566d678a5abe2b2fc64c72eb88299607f371267fe167bb6207f58f1722e2c7cfbf46bf5e122b7b7bddc3403c29064a0cc5ee6298cf67d9705
383	1	274	\\x68e7e3f936570abc57fa465344fa68d5319d2d3f7c5825709da0251043b9e6d86fafe3aa63c0c92e17f194110e1a07864888d02cd76b4b98170fec3de9f18904
384	1	26	\\x1961bb3bc658a5c0048cd10516fcfbc7dc0bcfe0fac576417c7a994bee4a462dcce1086ac3bf6f08dd1bdc3aae005ed54497a8d36bae5e934eb83baee6ce3502
385	1	268	\\xd5950691d2e9bba08feaab14cc2688eccab33adb29af8d7e3fc6c62ae4bd9b577fb4007568ebfa57284d918f036460b7b4b5e150c5e5a35b032745c84f5ed20e
386	1	259	\\xc691028d02439eaf27feb128d634ed4ce7dca8719947b56a935fb23624abd1ddc7262dac1a96d437e5db1cff60257f7d47fa1b678e9e56246d013d3e6a66f401
387	1	362	\\xdedd37bfe2f574f99682a23b58915b2b62d0cb529f4f42f3764bce0bffec9ed08dc4be417b764b375192590355774ebe6b4b0c5c3ac00f64eb12e4b04c69d100
388	1	360	\\x4a291d278d0a6884df3c4e3078f6da3286851ff8a8cc4f81212922c25d091f09ea019bc1cecc1a64ea7815c47b50941256292d5b06c90babc2138817611c4607
389	1	128	\\xbbe0dd2ce1d02d43b6be3d2dcd04b7e0ac11b60e58e92da0657bd9fde6630a99a110ed92e2c00e2816e8ef75fdf4263bce251d3ee819a417b95905bfd6bfd002
390	1	319	\\x01ad448c158e3e938808da939723dedb34a88fc92dd9a90d42333f97c3455e822f1ef6a5dc7787c66dd1f670659ebf82240e408537396f029a4f9e77bdd8b00d
391	1	73	\\xe4141f8f4e0491ad45dec694bc3acc4711464dbee12012a088208f2c1faf82fa0c13e77c64ae4bd4400da24f256cb05fc25c8a81e5e24a187e06c5be979cd900
392	1	258	\\xa262b28b00fc881417fd8526069f76c21639b42ab4ea66b22a10b2bc28afddd4e9e3c1a23941d7e85f6d943afe1855d78912d96c2033df7c79875fe9daea0a03
393	1	153	\\xe58098bc311450da86973bdbc2c1dbbe1806c65135b713e4cf7455f9dfb8117c4c0f3131081fd47b977ab2dc66df6448ce555e153625182182892e6883526a02
394	1	12	\\x7f4fb273e4a2aa1305f54db6350d7dd13be6f27575db1555687b16177dd219c4a4e556ce52efe87881f023c73f1859996b34de1ea03bdcf4eccd697e724f7706
395	1	178	\\xd47abaf1fe71b824a7f4a8deb480cfd6d35766b1ff4d92a4b9ed0c0280936ec144ccef6a32bb895700b196d6dca993bd6e6d22c10b802fe9f36f8dc15ffe2904
396	1	292	\\xa03f2f57afff4031cf6b66e85a576184602cf74845330e8a8ae43873ad3b0d462804769ed293c647e0f19a02924460774380c0f0268149ccf5b01bcb374d1001
397	1	324	\\x9df19abc6e41bbd8a0c86fec466d2aa7368bc48b4b455b6c71241f5f57ecf9710bf824f5771973e1a7013975a9b819b76a3bf2e5764f62fdc32ed4ca3328ab07
398	1	220	\\x555943d949fb7b4de22ca826d3019caf159ba9083a63bfe1b2f59747495717993f3cc7c9ad9b6f0539eebb10c5566e5f91345bbdda8ea04223b2950a8de0e80e
399	1	83	\\x1e3c58aa83b4135aa0ff8197c7530d3685e263251fb9dbf3ec7fc283142c123c3d3dd00ca9a4eafe2c66b41c9cc38500ccb06be4eba2b6fd0bd57c641bc86a0b
400	1	104	\\x4bb81dc03e4b662736e8dd26802917fcbcf7c27b5a29f92614a77cda8c3815e527290a7039fa8e8972ad0e11b3c3f897e744c5c04568e197b941899c23472a01
401	1	336	\\x914bbe7ce9e2451caeb592f33f73d23a4811c580390c16699a9bb2a32da2cbcef05df2ff0a74e8df8c63dca3f032e8f9ff86be5096ad15e3bc8182ca89e11b0d
402	1	127	\\xa03137d8db668b9e837543b9b6f519ab07600f3660d192ac8a893df2e4252c6ab2f279a49d0ade4e21b3189afb22d718205a29d7ed78d81bb41228cbc0a5fd03
403	1	165	\\xa15fdc7a7cf355cf20f96f36d464267e26e2beab9f342d9f098973329668851b17cf3e7700db69d3e9a1f94e04d3339143ddf5c709450d97e675a35f6fe9e307
404	1	387	\\xf2258b713b8bf989b03450d76205778bf238917fcfe0c7b8dd4bc9e175dcbe08c18c08ff8f95fea42bfef844e875ed1ac3078cf5d4c2d9d63fca033b4b9b330e
405	1	422	\\x866d8800a957c1cf9d0d67f3497da08616833e3275d2acee6c78795c69806b70861de772609965ca4792e048efbaa679454c664e7f597dfdb878264d404f2503
406	1	359	\\x8d344c0b48019edefc833b062dad26de0214b4f09c8702d86946f6c0b1585816ef53ce3e82d0726a9603a0a6fc3bb76db891011f393fb9bdd03d7f1e8633230c
407	1	214	\\x3222ead5276fd49e85ee6b599c60680863bb88b7dd85995d658542a2c55420838a5a98b65b054a587d25eda0b39f096c6ec75e617a2c05380b6a34da9865a108
408	1	76	\\x2ce1abaac06d18536a67e188184a24525745954f1a9229e9c8e9ea61c478dadb557095d8a92c1b9c62783100347e6340b76d80b655ad0ba61ee0c291d3a2a109
409	1	61	\\x720f2241c038044f3d053b006edc7629561b70ef0d62bdf40088b7e828af33fda61c890fc3c285fd15fcef8651a216d573fd2bb88c91d496bbb3ed624ab44207
410	1	308	\\x4305439400e90dc9543d1ef4f08eab866ca0d6713cd76a8c162acebc01f03412e12cca4a8cf90ef088e798096b5b9273026b50febf838f88e67dfd3ce09d5100
411	1	138	\\x8312e9013fa694260ddcbf62ae42a3b8ca9008613889c8ca3404894385d31755eb240b069176dc95d1c6d9d5fd4329d6226ccbef72996363985fe21197ba420e
412	1	57	\\x5da94090cc4c9d47adbb1b3dfdd551a5e259e3fad67b88f141df208a2a57de7994ac9df00378765ec5b4da88221e8bb895755ac96b12763e24db56f662dbff05
413	1	35	\\x545794e439420dde94eab448c280cae7148ea5cf58652b562fed979d80de9ed7f04704013dd59c5a50e73bcf6b26e7a49d549e6982d480c9f250031e20209d0a
414	1	79	\\xfbf8945049aab221d10ea0f5231ea2509c6eeae3ce1f2df1bd46ac31464ac8664c4d36b1bc049f66d9775e27d8ee1bca299f3b416ad8ae2302e2be0459f24b06
415	1	290	\\xde54eed2eaf391eef91eaa82d51a270007907d64184adb8be1001dd3dcbe02fd2b6335f2aaae1e5b9a9489a6f7ffb50575b108d3f25c3b6c59735981969e7703
416	1	363	\\x4c55d608a6bf253bef783556912a9661dc6c4458e38c1ecedbf508156ce0d17a3176369c8462d21bf0fde29747f2c35db5e64cf04b482008e48dadc208fd4e09
417	1	424	\\x98856d7ab1af1dae64a5cadacacee1f8382d2b71dd2d94a79a61095cbae590a03216352c976eac107d488ab4448c3b47ed5b13663e884679075b937a18943804
418	1	41	\\x3c1455f7e3cce084615ce128e4c321c9e1690f5264234bbec7bc1017c1a671db1b357906cb4d23eebf2b88c45f7cb2d20ffd6729882e1365df324f2c80730001
419	1	243	\\x2d012fbaf708cbaf485d7801cae501d7f00886a2ad9bda755d086a8269d43a9804430662eae820157a1e14e3adc0b10903625ef9b43095808ce3f986bca93206
420	1	179	\\xb7fb38e1e4a3e58bf12a559d657463721096d809ee79454290f8ed83eeade87ffa776884ab1ba889e5a9d4736f183d92b41b42497b648941a28d4f0b131cd404
421	1	31	\\xf9b0d25111d64664dc95ceba25d01622e457911553c88c7722ac46d8ea94f5ee9785b016aba13cd1410ad74efc7b0c8bffd0cd9015fa50adc2c68552bfe52601
422	1	58	\\x387b7cc54681d60de3bc812c21b0e46cf21c8227370febdc5626113192ab793101d5f5e489fd7387a534d9724310a075a43b1a3ccac82d9719738d8aa22fa905
423	1	159	\\x9b16200f776fc0c300726530717d89dc85d9e1ad8ef56498d077667280d2fe1609e771d78826c353f96135ef8697402ca976f76a6f9d7691800cb523547e4c0d
424	1	171	\\xdf7bd2e6ab6f0d4219faef916fdf2a9816aae3ff4c50f3ef1ce6f0ca0fd795393b2a8e0e0104c85485e01eb1fd8a9d0e4f9c7b46fde38a1d03ec9b1ea90b9f08
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
\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	1647492272000000	1654749872000000	1657169072000000	\\x830acd24088e67ae054263fd3049c93e598b6f50a806d3f6adaded78d3a80f6d	\\x7e7e027269f77579b843fb60ace069313a3ea1029cc657439d086d9d5a1d27e81c81916b41d280cf973480795266204f3b99b46448147aa9ff37c68d2801990d
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	http://localhost:8081/
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
1	\\x0288fe507e6a0791bdc74414397862baeb3fe3c0d72d339a98c053b8a49cef5b	TESTKUDOS Auditor	http://localhost:8083/	t	1647492279000000
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
1	pbkdf2_sha256$260000$oytsZrCJGJS7h6mMzCo9du$dYy7/qn0c3cae2Htsec273sdeDmhyuAq9Au1QTksCTw=	\N	f	Bank				f	t	2022-03-17 05:44:33.517377+01
3	pbkdf2_sha256$260000$mnhyelCVxMTzZjBNOTR3Eq$59+0NS82y0fVR2z3tnFIfvAeiDEbUkho+puJbAGYM2I=	\N	f	blog				f	t	2022-03-17 05:44:33.806695+01
4	pbkdf2_sha256$260000$QiOBVedVtHVOrXuXhMa0of$8WQoq8SBuam3CwBLAuk7BZhgDoUTZL1/weXElu1jb3M=	\N	f	Tor				f	t	2022-03-17 05:44:33.946887+01
5	pbkdf2_sha256$260000$98dOmvz66Rg70qshxZVZ4A$b6NR2Fx7yot4sqQQzjdtxoDA9X8rOloDjv560D0QGgI=	\N	f	GNUnet				f	t	2022-03-17 05:44:34.088903+01
6	pbkdf2_sha256$260000$iHSXwIrHOEODvAcYgyy1dY$a7M4Re2Gqqsm1rZHcQcsYVF6Kb2NWBqsVlXDSTLtemo=	\N	f	Taler				f	t	2022-03-17 05:44:34.230985+01
7	pbkdf2_sha256$260000$GmqZfgS4CXMl3GmSjCdBc9$qGCageaTZy9julRaAf7Nuci00YdMT+RWPKUt1bAd4Is=	\N	f	FSF				f	t	2022-03-17 05:44:34.372364+01
8	pbkdf2_sha256$260000$xY17aZxlmL3MawMK72p9c6$LYZGP4wIB2ngN6px/pnQpU0eQnIvSSQLJnWnSD9GQSw=	\N	f	Tutorial				f	t	2022-03-17 05:44:34.513143+01
9	pbkdf2_sha256$260000$0exaWawo5eEn1TyUx3GLtm$dbfy+odIVJF8opho1IQCL7jdG9FCfViDMG4L2g4BRjc=	\N	f	Survey				f	t	2022-03-17 05:44:34.655065+01
10	pbkdf2_sha256$260000$rAoTUej2jXAvE8MSqyCJUo$iK9wPa6MUC/ZGAsrvkHecG04fSOfzg0nKzkdzfaK7wk=	\N	f	42				f	t	2022-03-17 05:44:35.115316+01
11	pbkdf2_sha256$260000$r0wOJ3z3O77m8lnOD8XbF4$q+/UEjmnFb5xwpkZ/NhURhy+p/Bsi44YW8o9XuPiJzI=	\N	f	43				f	t	2022-03-17 05:44:35.569611+01
2	pbkdf2_sha256$260000$59lpD60k4F6qcz0ZsU9yXf$dz1/o1qwjbMgDWPF6SDtZmY3stYfcgtHmaxSN65kpl8=	\N	f	Exchange				f	t	2022-03-17 05:44:33.663838+01
12	pbkdf2_sha256$260000$63fKLldUMgAPvl0p1VtDgx$f5pEpP/3fP8pzrd84dw0l1du4s7JLkoLprCMHTtjjOg=	\N	f	testuser-4pdg1s6n				f	t	2022-03-17 05:44:42.356905+01
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
1	171	\\x4f81b910e6c37236ca0ae3b213dae8b46dd25315c8086719c412187a8ebca533470ea38bfa801e77ad9800163fdc676938144f047f7cedb145dad9ccdeae080a
2	290	\\x7f21c8691f77f1701681d5d3af1758c4b1640530806ade1e2ad08cbfcbf0b0e494d6d8065a7e84db6e6e7d91ecdc77b59696191e6e88f875c6f774b10c367d02
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x00880ed813dc622bbbd08d39cfd815fc6094fd31e6053d54cd50c6b7dd470ae33f10f92a620e2af03194928a0e3b6ff036b9e299b01448503b62a836c9072168	1	0	\\x000000010000000000800003b7f6879fffb9db0804ab192e743b26d9e8f3bb27e9f4709c6fee9bd9c1c96f6b149c4a16a510a1e253868c8c399ba3765c939c135ed843de82316f3a41adb23a76a8c83c3a3b4b242a059dbb4540b522286482c4a773eb2bfcb24c56296d43ef272818e1b2ef46e7f210d29d86975917809e182e6ca0e527b0433f59ddd5e4bb010001	\\x8b8fa40ce427ed071edfe0590931d31613b54cf104abbbad3f5ae6985efaa58232537cdd806ee8d560634c2d5b7efe4eed8033493ef43b59a1f329ff73809d05	1678926272000000	1679531072000000	1742603072000000	1837211072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
2	\\x02543e4061e26f10e9413afe25ef30b912a4b6613c31e9bc29cad7411b09ec8f8181b580db7d0875d9fc259a1a914cb41517422a755af7158fc346dfff1fe022	1	0	\\x000000010000000000800003a15aa5267859f9a2fea307b7317b6c2482a28f52fecd261f07d259362243c838d9a80eb135923f168f1711e0c9695ff8ae54eee3154ad9dcb3cc0e29574c501d0268e8d5a31e0d64ec4417b167cd885bacaa347cf0557b73bd1a066f7c9fcb08e05db87d97677212bae546a2676bce163a1b9e30cee0d293b411baeb56d901a3010001	\\xb218d69d2a6b9b70b6b299cafe66c26ef6ef1abff34e3c0f39f83cd79df56eaea3011ad7f040e21ed1d1f2e07dc73379b25514e6aa2e47e9181f8c7825923d01	1660186772000000	1660791572000000	1723863572000000	1818471572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
3	\\x04a8b136c40969b74beada4b95d08bc0f0f992d8b6a2aea2c2df2afed2f18f6d09f4235d47fb896526e8693b43b1499af57db60ea189f58f539e5e9faab323a8	1	0	\\x000000010000000000800003bf5fc925db7ff1d4cc3f3d246c4debaf3707aae08c0ed68ca8a11807880237958394e4db8c1f82597a8b01d0cc309f1cc57cdb2b636aff7b4815fa2c5fc9dc05d31649cecf2701804f51cbb5b348cfd50c7685aa4cb823a7bdda3f501125cb436317820c25058aa6206de9c3b00af80b634ca44732d64972b77e4a1a1602a4d9010001	\\x9ee79239a2a1b2eab51cf1c3b33f1900cb9a8352eceb4f5987bcf06b1f82b1d7019fb8a03fbbb91dd4bbbc3ff79ebd9579e0eb4195760aa0da64e74006f89300	1670463272000000	1671068072000000	1734140072000000	1828748072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
4	\\x070452bf683a7680900a98097b3820d45cff7b942b415c9a227b167e0722ad4e471d0c9ceffd0f9e8f8905655af612d109b4c8d4dca6b39b2c3f47e3ccb87291	1	0	\\x000000010000000000800003ebcb7ed8a67b362ddc75ecf10e961faac3db56596ef5a13984ae786716a1c9dc4b131b0a556ebe3eb6ab65c76e1bb9bf22b197e4215697d4b3988789f8312fd5d7f050b466457c8aadfc0e3fd977027358b2e8f8c98ecc95ee39e62c8fb75c61fd66019b7bd731d52c1d8bb9f0780c81f19d3159d1691ca3437c55748856d139010001	\\x561c0f739f8e368f23596aea4ebd5636a07304d8925e01c2e5378ab2877b3c33c409d3301cdcaf6bfb5e99bd8570ce9c3e4b6aac27a750dd31752330b85a830e	1674090272000000	1674695072000000	1737767072000000	1832375072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
5	\\x14700fa9e8acfbcb708bffa7d630b2ef176e119aa1cec2c4514fcdcea6356c668ff96811fe6d0ee8922090fb4924b01cf323aaebe1599ef70b76e9844a191dc5	1	0	\\x000000010000000000800003e5b526c7e92e1075ab952c93c81be17e8c77c40d5098063cecfbc41977b017c373acaf4147d17de6f29fda610318de75cdf970b34c5978b1ed587360b63768d5999e7597524b09ecef46376dcb2ba085288758edca7964c4a5fc279ee73e72638e9eb8a2f0132d79d02c70047773b08de7eb1ec8005213865c373ccd24d57223010001	\\xb9fc36d950383c37a0cadb28456e448c959b36a0338a20ecd6f76f9702e2535f67643e4674ffe881a99aed02838ac47995f5a16d9b6bbdb94fbbc6b6761f1a09	1678926272000000	1679531072000000	1742603072000000	1837211072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
6	\\x16ec31841fd15d6b33659cdb876e602ed5aced36bfab747876943c0e862aa60be2106abc5bbddeb62973c8be5751e150cf81a1031504d944b40f874b5fe1e4d7	1	0	\\x000000010000000000800003d0314a95b14cc588f701c93f96498b9847a185ce84c7482adfe31408bbdac9e03f40cf756ebdd3ce586657a8cf79660ad5168b411c207102ed6796e1d7b94e78a3f33c49884222c6c83ac99aa9dc503e96e99b8efdd87a2c6458e504380f5f203046d7667c54d11f5dc0832c43d218b269ffc7fc7fca40332f4efc516bfd24ef010001	\\xa2c3dd800617c4cb19b96cabc394cbcfffd915c9c1667892d3fea586d67c57e327c66f974932d3a8b273d0fd8827628dd04c9c1d138ed94d27b6b922ea502d0f	1652932772000000	1653537572000000	1716609572000000	1811217572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x17b07dc163cf835c167e2e01d682379d30bf6ca0cdf4844020c29802594450791740d8b87f33e0ca3683f4503c44a32bcb5e8e1441a362584a9f3caa5ed95245	1	0	\\x00000001000000000080000391a6a73b560cb5d843948ad676b9631bffbb710813548c20466474cb07caf36996591864f51a65c269460527c9eee2e9d657654ce4c197cf106abacfb438ae13b128c55308a84fff630c700a2baae454c31d390f6389ba4dbbbe84f2e4773e7404818d3072c76e8082ef5600faa83342ede021a76357810bc8551cfa2dd8757d010001	\\x7bad9f73058456d7ae496b0f42d4e0737de238d0729ac3398c391f39165a25816f91eac793bb467c107f42ec715c640d16902028c87b7a972c726803439e9305	1676508272000000	1677113072000000	1740185072000000	1834793072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
8	\\x18807a80ef33702e8b209b30cce16eb2cd971b59dba2a8c8ba628fd3f3de607e3001f30d9e077112d0902e197b1bdc261944495e8b786f4699e52f9d960a8df5	1	0	\\x000000010000000000800003ac2633d8f28f2739fa521f2125465dbe0919e33b3bb14f621acebc6c5f801107047d702232f0c2b69e2185a37a84847deb6369d092e7a46845323ddd5e97d242820c711e0e448ae837364f0db90255c530a730f35933c77080251c2d5020dfc33c68916e7bde72fd9b342ea5877ec4e88ca654d6da25b95837df12893a81e6f1010001	\\x1bcfda3faa3288ed8143bcabca1f81d8f339c9d5353eec2ff591cc8f53601306db261a0e718213e06e67d22024c7387f4c1da8725e0e0714f739d5397c35c70f	1661395772000000	1662000572000000	1725072572000000	1819680572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
9	\\x180815a656c2f3d9ce4e14cc18a94fb4329f70624da3d9263fa5bfa3f18db6aa4b1b250d2f2e03ad5797bd15ff7ca42b82d341b1bc4adca43982aaf333b99888	1	0	\\x000000010000000000800003b2d2f6a0c3ad4f68b9addf4aedcb635024d90feee6ed1b4130f2648fc31d0dd25ae5975a144b1c0744136094806d51c9cb0e76c03107096f025c8971fb9252ff4c1d77eb61705353861dbdcaf88f48d7c6c2644a7542117a366aab1556aafaddcf8b7e8099c34d0eddfa485cba62ff84c80c131dbcb372eaed7d4647c444c9f7010001	\\x4559d9ce20321e4aeea36c06a13e14a5a4afb801041087375adf4ec95453bfee457152609af403b807e104147a81642da49e87436110b7750725effc32cbb604	1661395772000000	1662000572000000	1725072572000000	1819680572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
10	\\x194c39e0bd283b9000a4e9d1d0f334c481a8fd93df60ffc42667673b85edddc6bcc050a6eedb1ff7bc75f781bb8c3a429617effd0b6881ff81bcfddf01d6b188	1	0	\\x000000010000000000800003b6cb8125f68b38b0005fdd781affff7ab0207615f0bf98a4b6976f916ddb600aef3b79e9613b530e63fd2832b7b19e29d2da485bbaa0323700e64e43df7ec7ac79d5964f8cbe7a326e0b33ed9d93c8267c6eb4ab80eb697bcf70df495c0ce36b9fbb0d4dae0c738004cd8d43f3a23c03eab74edbfdd59e07fc9ae8752b2ea37b010001	\\x7af61fd06a353d900ef8b193626ef7ba550eb242eabb9c5fce8c479e1f32f4f085d48f5e977adbae594fe67afc6dcfe4f198051a548a405b253b811853ead909	1671672272000000	1672277072000000	1735349072000000	1829957072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x1d0c14424796dee0829c3f62be228e5dcffe4c181fcdbbb3385fe65b197fd8b11b7882690539d6eb45f9814abf53856512f925ad46e2405aae9da47793b362bc	1	0	\\x000000010000000000800003aa2553f2c055505de9e32e7e3bed877f652e06cf8f500c3dba820c25e48c4421682f2144eab938d904ac8e26c5239f6f70f229b61c6a114325b459fd081438fbe15f6643533ee110a392b8abaf18da8119455da7cc2038e0644f4afb63b9e29aa3256149f949bcc427cfdc489c7c632e89923a4e821320bc0db0e8ce7340fa43010001	\\x2284fc2c390e38fc4f81c5f3fc4948ecf521d06ce2946209a3d7bd2d06885b59f009f7a0408575c48c3bbb147ada78292a70b16f58b0157f0cb66b86b9ca5a02	1664418272000000	1665023072000000	1728095072000000	1822703072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
12	\\x1e68da7b2c850837b3a518f81e4f879b334413dc07dca42745e5a06e9e70af1ee8b2ab9209cc40869004d044a4e0109c2738a9bf54dc9c214bd4e3c4a36d48a8	1	0	\\x000000010000000000800003b55d6cbdd50d4842cd9d79aa08c177f0f50ca87fef6c6fd397f0ff1e967cb4c70a5b5ea8adc4ece54ec192ba043c81537833f3b153cbaca305f37cd7b144c08776151b0d9406d13f890ea39977752ad928be9fff48432a3dc80138f247067188ae03b2d166164a74bcbdf4a4c6958d51191ae2ed1b84a6b1ebddcb783cd01ab1010001	\\xf0dccf533d1f17f399f344e654bec26406cf5bbbb65c9f28c432bd84b79606a920f0f6ac8422001c47bab65312764ac7b4482f8983b6c7bb823453d282485305	1649305772000000	1649910572000000	1712982572000000	1807590572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
13	\\x22bc370dfa7fb9494093e622db8403b0c91daa8323e3f88be02fd54e40fb115b63ef99aa3765051b9e3442bbe8b2157b0fb8c6ae0f331cdf89d590fae739c5fe	1	0	\\x000000010000000000800003a6c9dca1fe431951b7261d869e34b015fe59f164a3ee303bcd63c5c116f6144bd6aefab9a9bae4393119eb32abc56cd7213a84cf86eb5b7d8ac818f4945112e4e5f394452d0a98e23969e0ebb9d7fec2f35df0b94e76a797ac267f8bb592f3e14acfd0b85a472f2e9d1a6cabfe4a2b62d5ced82bb0068e895288490323ab267f010001	\\x7122bca21365e011ffa6c74c07f301506558ab7daaac14845273606ffade139065a34e86a197983a342574efb61357b78a47e39603d90814631684383924d907	1655955272000000	1656560072000000	1719632072000000	1814240072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
14	\\x22048b7bcce4487ca3f51af8089704f768bc764b478a6986b190588c9b99a974ded0c6d091b320290ba2c636cc94b1b69ff3b66f141a10dfb7f5af8c426f6b1d	1	0	\\x000000010000000000800003d71c5242e36c25284fdc14f336473bf5af60344168fafe681f9d3f12c9f2d13cb034a532189727215b2e988b77df24f0159626cda762ac0ca63eb7d5b00f60289dea59636cd1b75f9d6c6fb79f585d91b39b1c62e15981b8109ebacae0a1ac7437982116657bf74b54674b7b2a112ac74b37ac9731a11f968268d63d126aa849010001	\\x51fbae652d18ee4522118b9d9dd18bc61b8dd5870cbe3c3819d05a6a126aa6aa41f1b4e9486e7a802c4a91ce0367c1e35df749135a208135fbfca610a430ae0c	1651119272000000	1651724072000000	1714796072000000	1809404072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
15	\\x23c4e44ff7a71ae01c0910f0e796614c5fcab49d75805ece0d21ea26cc921391eca0bec27b35ce61ecf5ef81ea60246a4bd3adade3d09a58def80288cd29ac19	1	0	\\x000000010000000000800003c298112bffe35478320573098d3c687488c70b714c8455cb2f0dbfc51a6b238ce9c2a8c2bb7478c980dbe05c42849c656be73bb6a3492615bba8da3be4be21d60fb711f6d3c401a4d8c12a9ff00dace1e6783e1b12db37261280cb4a8909f8e3cf49f9379c056fa5523c304286fa41dd6c6b5f06622a96001ecafdd960e9ffe9010001	\\xa02a315f5d03f4536a032b60f1886d33ddde019b3371eb7ca776585fc4f50d15e57707a98cbb13365d4341be2e9c4d9a827375dc8aa8855b274ca9f8c9224e06	1657768772000000	1658373572000000	1721445572000000	1816053572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
16	\\x2530407539eed399c58471275912a6085b1fc8baae7ef3f6b05b8dce982954c6bf0440b4ca8181310ffba46e3e80992e0858b9ab0ae6fbd6de38973eb958ab58	1	0	\\x000000010000000000800003e359abf745e5aec0c08e38c0f239aefbcea98d3394eb2dc02bdea553af72b903dd3eefdd05c52e5d6d7eff35f1dddae60eb5041c1cff86d55bf650b35bc55e936ce23c624f96b6c90780b27ab73d6183bf54e17cb732f5c6e5f93a2971631bf721a74aaaecd3f0adee68260b42da12981ab0dc4b27d748429c07baab0b2325c7010001	\\xf7634ebc4ac5369ad168473ceebe095a1e6abcfc5dddc7fdaa15109b661d95678377d8ed52f8f338930f66aad3bb5df15f2474368156bb464a74847b81608a05	1656559772000000	1657164572000000	1720236572000000	1814844572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
17	\\x284c9ecbc3e29e2adc7e93a47247c3085f85f016b7f839cf00d38f19f9d65cb7f97f2c05c595b6053c09415c1a5d5650771bb2f8898c09a93304e9f972a05117	1	0	\\x000000010000000000800003c33e200d28b046b68cc8e6b23406a99a349b01d940417681bcd5bf38b3116ed711c71d790c8c1659af2b782dd4b954933ab67f8e6ea2d9022ddc3b05462f3970459e01449a987fafca7dcb4c4fc00fbe81e68f857ba85b9dfef5e39c48bb868fd3464705ac9eded10bda3aba857b7b1345d6530e45aef84922d71ec55c63d1a5010001	\\xbb885af6ad2153d7d4a7f877a149eefbd76511f31709e13c9165c5022b84d65c06bc08940f3a75582c51f6728bdfad73e0ff76c964861417fef1698bffc0ce09	1668045272000000	1668650072000000	1731722072000000	1826330072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
18	\\x2bc887d1edcd267d32e85c775dc47f26b1f7930b2c479b9458ac37028d8529bf1d0534dea09ce79c60469e208fe44514eca40bb6845d9424d78a43dc5847bee7	1	0	\\x000000010000000000800003ae9e20d34dee0697b7986079de39b1eb6729d4a053f9f4d61cf60c4f0a0bcc9bddebc6f43f12fe9ab4d51aa23c6654f2ad70d557539cc4c54822bc0c5c3046923cb71b1573085fd08c6d499cf358f0861fadbd4925882f0380e6865a0037a4f6f75d23adfa00c4bc93239b3961551fb6869b2caf46693aec09b8f4ded50dbd7d010001	\\x70068b18cb2b30c2845e2440607048f318b6f53226aefe7fbadef29ee468826fb25bb8c5c438585663c08d8f3c59c5d8ff1579c12639ba402955776aaaf4a70c	1669858772000000	1670463572000000	1733535572000000	1828143572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
19	\\x2b68be444455f4969c7907f2a35150fa168fef213937cb9dbbdebbced7fd5c7b1f6ca816892669d120e092f4ba8a64d9e562bb2bdc93d0da13da0dec55c7f011	1	0	\\x000000010000000000800003c467bbeaee535dae7495bd0ce499dd3957f3de700e042d65427fb35cf78235ee9a778fcfee48027851618e3ae48c4620fb3e6b5f6139d3ddab0e11583d90673773b76feabaf4e5db4ebf10309688896dab4e39266cf571b4f9a6f101cebe586d9606413da71f9bc14ac88decbe432efc5b8731a0b2f16480492e2a8715601f89010001	\\xdcb5cd6989442e4b93b0e7a341247e7f28418f6f9db9abd8527d0b9cfb9f072bc84f2afd798a9e4cfb70ecc93e3564f7ff186c3b6178ee5f2319594b96bec701	1665022772000000	1665627572000000	1728699572000000	1823307572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
20	\\x2d00a471c38dbe77c7ab7147668547edfd286564e3e7418756c3d0aaf527ed835d5af49612ff47314b9de5fb9df1639704e9ecd9bce73475b963274926feccfe	1	0	\\x000000010000000000800003efa2a523fc43987497a071cc5a082319791548de1fa644566c8f59d99eaaef50e94a6a187e308a5bbd13b635c0edf52c713fecb797889ccea87051233a1e0ea869826339323914e96d8afa4722d0dfdf267ec681cffeadc7500ce91ffda3832bc2a353583dcd3ddc294288923845f6f387d7628f98cbceec5469ae07165a269f010001	\\xe182b08a45e4754e55f7f515cd1d734776956fce0d6b12a8442cdc89953f4f237a08354f014fb8982485e9184a9e3a21b2ccbd2122b33c648e80cb888b463a06	1669254272000000	1669859072000000	1732931072000000	1827539072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
21	\\x2fbce56d03bc4b737fec970749e2100e1628c2b5c17f4fb10d1c5367bcaf150b6965d3b52e713c89421cf7be0deb1bb1942887adf9a4893bb0b59127c82507c9	1	0	\\x000000010000000000800003a6be7001d25f7b3e637400e6d9d95b0cf73193408176bc5327abe06a8d73f4c6b0b614909c9c7cb144f30be80d97a924e0e2533d54aa38de04ad7a704aaf8ac9ad3e30d9b7f98c13f25c172ccce84da904511a14f722788f6135c0584e92b9e3479a88203538f0a0e61e5f36a81106d88d3bbb6899b9512bd32ae827a3dae921010001	\\xd87121320043607153f366a349c4a0c3b21085b414df2c0e023b7b0a4960bd8a012e6ec7e6a536d738a152496ea16bb2fe1c30a336ea2f7c04e526751cb70602	1672276772000000	1672881572000000	1735953572000000	1830561572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
22	\\x32982f75e636b357ac92230d7c9a25997658f6aee1ffbf2da13ca8725fe69d65e9d44766da4a6203c663666e76c8e622988da4b93a4040cf666a2951b6623b53	1	0	\\x000000010000000000800003ccdc77984ea664b2008e5ae6e9a9aad8d51279534c0f98134a30750ecc0fcf1160e6d29c398bc191cfc5ece56e1bad17093edf218026396b1fe5e1c68a4eb21ec64d2695561aa7d03b03b2c1bc192a78bcdc1232468d95ad8e14c6b429cdf4a556df0bb51cb3da08a0ee373414c986aef046349393d7d7cf52eb6291d64f528b010001	\\x06e117aff68cefe171ef969f0a6d53928501873e3521e04be343f5133dfaab0ffe101a53e03968caf629c21e5248943c1ea317aeeabd66e95b7b7a19beafc70c	1655955272000000	1656560072000000	1719632072000000	1814240072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
23	\\x33b430fddfaa5ad76e830fbf9328473ce0f3626e6ec2a4eeefca6ef5b2393647c08f8546ecc42a4a2a5d1d3231aa4f4d9664e1c00ee5c88bd467b664f3ed72a6	1	0	\\x000000010000000000800003ab8e3ea4811928d43fcbcd61e8ede4e226a4cce685f78e30bdc04bd61538b0f27a738a7e0cfcd80aee0510e01f144a1f3533df6d2a52e1bc690dad62b57b486a01f2abc79db93b52f08a2ab32745231595dc9438cf07fcad5b90288be2204988bd1faa1f89916e5e62e8aedba584ed7e7e5e7477110312687f4e70a2dd0b4259010001	\\xcd08722f40584adb1c9c61198ea0724082c292e280e7f6db9a08d361e870f5a65c28019dc5196fd4ab750820e0b691ecb09328bcf32dc08d1b96b303c302df00	1654746272000000	1655351072000000	1718423072000000	1813031072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
24	\\x336c00b15302378386a857ab59694a2f1e636a9e870111372c8df016b08f6f894840435c69ba14463b1a06f500e3b2f2d10b0610218fec531f9c311321f1843b	1	0	\\x000000010000000000800003c02d9ece6637be23b0d5469a0021d6a64b7f46c002c5854272028850ac0be6c2c392dcd779859ef526184c4057003d47a76bae6f7ce37e2ae268dd8779a6deb593361c89fc656f415a1cf69cdc134508f57a3e3b66be4888ae74aa15dbf891b1a3d432620ebf7c437ad66e8636af753d797ab623e9865198f9a79d8e8be8c429010001	\\xc8cef8b7e74be5d176465866e2503b1520da9e63884df3dba0c82ab3ea94c7e79419b39a6abbd8b109e8a61ccc7d6714e19e06dee100f7ff4ab6af46c9a14408	1676508272000000	1677113072000000	1740185072000000	1834793072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
25	\\x35acf00594049aee65e6ef0732ae6cc8d3f9bd0036edd9b202a6b63a906320a94c8f4561f46021a6ec33d18cdbcd2bdf13f59762ba6381defde3199f57130729	1	0	\\x000000010000000000800003db923f14cd8743f43a2a8f2a5d683b9af46f0637c062aec0d3c4d765b9348828cc30392fe570e4d8abeca229c31319567c1c288f13aeb228c8868d419d4a15ccd767490eb08dd6272db86991d6b8946dc4b10ca4cb69c2d64a228f1f6281ef0baa658b27dbc78cc98ed2c7f010474ba1c938aa3a5ce497f82c373c0f085dff3f010001	\\x9caa4284a8f8c387fbdbf52b4335db387af09e9bd8fb08569e3eb2dcbef1bc2dd2832c5a3acfa9676eb17f031a21ed2e440a587cf493746adcf7c2ebb0305d03	1653537272000000	1654142072000000	1717214072000000	1811822072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
26	\\x373cfdb14e4bfd937004f76cc236882e1e21ee119245c55cb5f4edd37eb55ebbd806bd923b5d23a17e2a074b49d100c498ee478654dd14e8317a8ceb47f4c217	1	0	\\x0000000100000000008000039f1d1ace52fb54dc9cbc666bdadc02737b48cab1f4479f799574a83c70d309ab435488eb0e0ae5de6330c15cfcf3bbebacac286917297adb3439f11ba2f3802b3fc70cc0dc6666d6b361bf87fcb215d27f92ce1140e61e75301d480932d60c7ebc2454ec3359422eca9e490cfb04df6d17605b28a4e7d1d5bd80477bd842703b010001	\\x521f36b2781b58d334b233f2885e5891fec1836ec705d700337ec1722e72b15f5f56cf5d5376cf7a30255e45ce1ae233c6676959a27acae257fa476216d2fb0d	1650514772000000	1651119572000000	1714191572000000	1808799572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
27	\\x3b60186d0df4b29cc9dbc7088995230ab22b15ed588b29305b9d467a89415def84ab74a7bc3a34eac5d2ba63b2964a0773831c74d61445b470c0a0f3770ef064	1	0	\\x000000010000000000800003cd1a1f56cb1c51b864a73876b687ef7d8ada27b3044fffff8ebb7a3e33a4f9e12380833eadc70f5f92403baf72808ea438da69abfab0c2f7cc84c1872b2bafd56a55b3b9eeebb1d9e8fd61a7ad2fd39d428fa9b90c596978f6e4377a6737f5c04f8c19cb990a36cf8a4cd9d2b39994d16abbbd2f3de83e339e60d0cec3cb6801010001	\\xce545491f721208b806ce795f4d6a6aa1c7a3f8292df68b532b26032a0007346c524639c9fa96e2abe03d23a0189ff7549a3ae889540c05cf931690c17af850e	1663209272000000	1663814072000000	1726886072000000	1821494072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x3bd03387168f5a4f37826a10c2179622ac2341041a37c57865d483e677f4955242fa37c4eb30b710bea3eba9d3d9dc3b21da9511461b8ca87ef591a9f29a0c7f	1	0	\\x000000010000000000800003ed2c06ae2f1b8ec3745d9ae948a72211c38de3f0c1b6b7b36cfaa285b2dc5ea141a11f0b9b218af855558cab93d65528b9e1b1e05ad4bfef36bda91ff9ba1a0ed9f27aa02c27d5187626f7126133bd8dfc0007dd88c085fbf08d9a4f7168b2b0aebe7b4b650fa13b0988db21ba92e778aa25dc163adb2e7ff13acbc67f0ab9b7010001	\\x1c78e5231fedcaa27a7010fb2d1954b62979920f828ba6313a77fcbd39f1d3b686a634c5edf3ba3a428a9ef121ff64f8743e7933c6bdd730babf0139be30700b	1650514772000000	1651119572000000	1714191572000000	1808799572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
29	\\x3f58c1ac29db92c0dfcb56904c249a9602ee2e365f9d6076d33d2deb9e3a73ff72dcb60aade1c6a8b9f5c7aa9a710073fc62227e0a5d1b82a8d326dbaf26fbe4	1	0	\\x000000010000000000800003aa33dec11edb3dfc1963f7a0b43bbba6b74e10339ae2d5e40da4bc297cad4c939af0d935af4dfd0756af2652695f92e9b28a5b8d5f487cb09914917720df6df18fdc1cea687c1485eadd7bd06640bd36d6aa39ee2c484335d65083aa15df37b1363574fdffdb70fb27c7236c87a01136448b77e0bad63917315a565f718e5ea1010001	\\xa15299e92af01dc0542ae8658f4e9b9160eb50d725db97beaacb35cd27db9bb36829258d4ae27834ad2d8fa158f6e0b4a865360062caab8e4359a76851c27c0a	1651119272000000	1651724072000000	1714796072000000	1809404072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x3f4873d43f83939fb4d47d16b45d2df730a1442432761d8c8f6271260237687d002a50057351885dff0a521c7d8c68eecbbf371ed91d1a2a132f0c050c2ad1b4	1	0	\\x000000010000000000800003b5d4d4f5d8869b39e3832034400719308cce0993a8cb76526524f345a958960badfb7063bc4719692f59006a2daf73def970a4cff48e563c28cfc55059a5cf86be05b59481323607959742693fb423657d92e5966ae00e7b4c3541377f427129c3d14701b69ae721e5fc42e67001072e8a2316e5cd1726a04592130cdc7eb235010001	\\x3b641259eec93f449fdf8c7a172082a038e8091e3e2a3451a3b598632d08407c059719d4dcc114399fb9b7cd3f63a8560722c5859c345bb23c1de8aa7d5c440e	1652932772000000	1653537572000000	1716609572000000	1811217572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
31	\\x3fb0537f7bee586328baa95291ea6718e4f9807724e8e9b3b70f697390a6ce42c07e14e0f520753bc321b1d408970862b621e4f28abbe12f9d9e0648ec88d117	1	0	\\x000000010000000000800003cab6b929d8c2b4de48951eb9c4c6fda84de7cd48cd918fa220c7f7be5025c9ed0770d95bd2e3e78c7d2772d0653577c811a522950d604431f634de692ffd74f9985f9a14dfb9a79ee819ea10a06bc5d105093d9042f4573f11fad0a63ad5d8a9321cd595b562b8e62c8e3912c797f1499aff74de0ffc9d1a67e3622d16cce18f010001	\\x36ed1074b5d489218a827f01b069c8c3f5d12088f9c72c37736cadc8de151485cb1866f84ef914872808c2f5d59711f6d3b8d5e7845bb32c5beb5a6492ee3402	1647492272000000	1648097072000000	1711169072000000	1805777072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
32	\\x422489a139de3b509fd6e1610c28dd7aba51841da490a34c8d00a88b8f55ed047734eb32620c59b0c6537efb5a7793140bacbb12f32bc96ba05e1864d35ee626	1	0	\\x0000000100000000008000039910f7931e8885be8552b98b5add77ab82b55e4f794d87fcbbeb95d7dc3a61bf521b976105f6f8c568b1e474e1aa4e211b230d71492779b86a92131e6fdcf2c372032d52dd359d544847a237e1240f163d5567ff4cdf97f2567da2c66fb5d702f0e6d16523489ec8eee2346cc49efa8480cb7567f1f62011a1d471b8e1f905f7010001	\\xecb522edaeb87c2a0264791df8266d701c93b7ce2ab6b2e3298c2053cb3e4e4e1e6817fc6161a0c1ef85cbd56d89d5a7913d3145bd775972b46551b133b04b0d	1668045272000000	1668650072000000	1731722072000000	1826330072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
33	\\x441cc6b65114f58133be34c989782f733d0776394315b92313698a4da2deb347ef50924cea9ba71825581ab60de18a7df6d107cfab42e89da46d0216adc78cef	1	0	\\x000000010000000000800003f2c876853e35e0f63a37403748159337a3f85607252bc8d01014ea8e56b2038ed278ab73fd208c22babd396f143bb57ed05c558c897af73694d88ad76160ac221dfa69f67e799e986fc09d8a80e2795bf74647a099e57ba37ea5210090fbc6ddf8d782b7db263be07c9aa803b69b1428a08808a3c18dd68727de26f66c623523010001	\\x7b2b3d4763815a8cd077fc069bf2884e67ae03cd9fd578049821210f6aed049f660ea4c6232b50c81e40a1e0adb1a809ad3f2f26157790b8fcd39940da15eb06	1674694772000000	1675299572000000	1738371572000000	1832979572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
34	\\x46b04b3997d2b782a77fcb0e203c0872232a5bf835f4c6673a28967cc0b6c0534d16b6439dbca506821d8332d3d21b6ee12ac70a7272e76708bd6034277e92e8	1	0	\\x000000010000000000800003ade889d9e21b83d678de291de934620ba7ac7fc7af993958a60537b190597648970be6093567dd51c24bb8114079c6550b7056d183edccfb993d129be6a06daf8c9369b81c6f773258acd3b556b60421a7c25ef3f03b075b0998d9fdab7608b0fc473ce0e9fb99fa18b4c468d02259794f496598f86d0864fb7d084196b476eb010001	\\xa8feb950bceeb487cc515eda77ccb25173945be2505f654be03a30d723f463fa7e8d2333f96febdfa77882ed61a9b2538017ad826f29823e8459343bff96b20c	1656559772000000	1657164572000000	1720236572000000	1814844572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x4b10dbdc34240e537aeeacd86e33bb8987f59392afafd4cc56a56a43a479e793dfbac3eb904fc187eb47244a362494b84de904b5bd7f0a0788c405c5daf855b7	1	0	\\x000000010000000000800003d760518575dc16e69102706beed1cd8323c69f929337c7fdd495749ea6e410f405ea1ce88854277e0c9d684ebdbde7732a7a189432389efde660f1e636a0e9f344d46a464c75d801d79b5990b818df62d45884ba388043425ef364d99dcccede5d349c304617b15108868858986db915bb037060e170fe3ea8e56d66965b6343010001	\\x8c82c22a32e1c906144aed64eeccaf0b794f117bddf03853a51f13b4689e328a051679e03eab24e80fb90a329395684b0f6b87b9741475d60393fc3749d45303	1648096772000000	1648701572000000	1711773572000000	1806381572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
36	\\x524c7c287a8a472e5065e6e88cf44a2d853486ffbef4690ff84f419b94efefde74c6cb6d9f0931fa8e757fe1c6a53b905679ecb4b7fb75f861c5b148f3e4d317	1	0	\\x000000010000000000800003ae7789fd12b44085d78932e9f9bb19b74fde0c7cef6431994460222e3e4e9312d7c7a642622e84fb5671fffc70356571d659b71b0898960b354ea1a554cf772be6ae2121687aefc3c310d4b0fa5724d3ddd1962a0eaf5f602fe5f9238eb75823bef782065e71b2d9f1c4d862df4a3d0c2fade0b8efbc3f8894d0723c57dfd475010001	\\xcb4d1fa300375eafc8453480ce1f8e22d06b64eae6abd0418fc45c429d51722bf02fe945e3d4919dc7a0b1e7c1fbf913c23d2e25ace923585fc34fa487e6640b	1652328272000000	1652933072000000	1716005072000000	1810613072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
37	\\x53a48a5ccd8c86636437a8984234bd61b491367bff1422fb87be679c24f879273da498baa73a38393296c877ae920b4fb07aa7cd164f9f10dad4b87468c427d8	1	0	\\x000000010000000000800003d92681d2016f27c882fd3569f55d5e149bf5746294917b197fa303381fe00d5785e02f8def3ac8ef69347e1183d7c2956264d46e4126d90f1f702021eba56c55257faa3ab5374d41ed7fee1c6755409a9fd73a7f5251d712bb33659d5152bca6084cb82901706be9fd6b822e8a186eccc0a724d39a1773fc8a261c0878220f59010001	\\x11851ea0c85fb07e7682d07b0a1184d18c041749e1749fdbdf40b59139732dade6112a340b5236b4bd721471bee6a16149d871110646431936d3b19bdaf68d08	1651723772000000	1652328572000000	1715400572000000	1810008572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
38	\\x562093dc0d79d4fbc93557306df9acc8019fceb8a21430703ba267602491338854a232e9b122fb438f488d18ea9ca11baf914b921a93dcb8b83ecf66475c7dc6	1	0	\\x000000010000000000800003e87a9778435623e30827f34fb7979ce0043c9220fdcd1a166e543353428259a22d91261bf8f9fb3e408c830393c0eee22989e29793f2b95a6dd4872db880bf00f8d05f38198c618510a09c58a6549785b6703562e1c4d1a59c7fffc9abca8261971eb651f3c873337ba536db36e1c1f359c9f1864bc2cb4ea2968b0a9ead3561010001	\\xf5574c1fd7017b041a3f563d2a7c714c638d8eb2c0f98f5e7696f0c9a559150d61c96f087c54310b3410d7169d3517eaa6f04f895c4d8ebe4a9b1fe3a8ca9f07	1667440772000000	1668045572000000	1731117572000000	1825725572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
39	\\x5e740ffc65d6a681f322dea8c3f2ba185454151f82fe2c8c55a5a6aaa3bfbb35abef74f861859bbbb9fe7adcca8a8254463b491ca73c81b564d80aa50ede637b	1	0	\\x000000010000000000800003d09225735773b1a1aa2057fad17326bee3916c228b53ad52f5e10f9ed747823226f30ffbc43218823cf84306cd397d6036678f7e68b422fe90de7a0c94b2c5c1076d81ca110fa5fa8e6e524bf728877c2766920eec59dd2a34b31187a4f0eb64ad0ee53181fd6d3acbf819e637fce570ee21cb380c93a62cbf4c45f4f85da9a7010001	\\x8714b463746acf2a98bddba9bd8befb5fba8ca932c126f512da68020f3cdb14b588c1fd3ea16e48aaf3736f9fe75aa41ef333609c83c89be7fab9ac0fa343606	1672881272000000	1673486072000000	1736558072000000	1831166072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x60385d9a563d87356ed8f51745b87f300eeaaeba01149f0c84fee9add8517e484fe8c384530807aedb2abe4ed40174483897a5c27f894816c3539de942f77db0	1	0	\\x000000010000000000800003d701c2c4a1ba876d8bf2bf7200763b667a483de9bc5b2a2c0275677a25a95b1963c22be84dc926f694a19a2cbf6fa6375d57b17881afcecb29e7c1a2c5f31fdff6ea8c9f18691370dbabf9fc4108157b187110eab698b24f0edb69ed16226f40849862301de4dd14519bf342a659e56d81cc299696d5317a4d99f33566b6a5b9010001	\\x638c80320715b5b90d4682c6df0b6783cd216ae2d0fb6d3acaea06314218ec1deda6be1e5d1c43ac34b124d29d9bbb109c5d2bee48a1143590e5df29750eae02	1664418272000000	1665023072000000	1728095072000000	1822703072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
41	\\x607801e3d972fa966dc40be882549696a0cc7e3f8b6b71cca3ce57512e24c354a70c6bcda9c6cf1f0685fb67972b46c85bb8dd2cd050011286e921ce4569db7b	1	0	\\x000000010000000000800003dcaef57f58a7ecb35ceeb7d7980e6d06c1dab7bea589b3bd14648f31501a78ffa3e811baae658f86f78507f4493619984dd3b3db2a847c4658e9632d3cd33360fd7607a76e99620cb07a28df69109fd2794507f125fada6ba53083a5333995906613ba24236571628345b412257b8dd3e8a2703a0ee29860547fb92cedef8f31010001	\\x0722891acbc5c3f5932030a32b568c10a978de2ccb9d254388b0aee0dad17b4dc8e2eb2dee34da6e8744a98e2f7a0e78dd456451473edcb1a56ca9411f21f909	1647492272000000	1648097072000000	1711169072000000	1805777072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
42	\\x6124b6746f2e376905279da4dab2061351e18a1bcaebe4b2483238a6c0f8785f530964a9607561d41c6d23363f0478cf53ce8a3c1ccf3690efc34c87cbd9da5e	1	0	\\x000000010000000000800003a0368f12e4467652b362ff3e6d93443c55984e2248b43420ba4dbeaf22e6eeef71175579f92a789118ef28fdbed18529fa112b1bbf47ff25682ca58b2f7874a6fae3792773f882d9be2a44d0400ffb209ee3d8bce92e32bc94b96db4a52568a1ef5ee6a583e8f7cca06be2c8d38bccd5b2d9c65b9b9c5174539db53b7c51bc73010001	\\xf6a260786a00da983a00dc875b7b0459ed8a31fba9dfdf2c7da16afcd847f0a04e2ac539b011578830a939ae90e7bad37fc54b5b2e8f02e706c7c10af1733305	1678926272000000	1679531072000000	1742603072000000	1837211072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x625c7c541cc1ff7ff6589d13ad4a7230551f05c6622830266e0c94e1c86b3b4327436ca3a8edf0a9a641ffcde56008efa2d267ac6cb00f4ab8f8f35a3277b9cb	1	0	\\x000000010000000000800003b643cd0e32937f02f0c2beae245fd29ed5ec22fa43030f5bf3da75153b3ef5b07565a2c074a8e9c0967e525d3d7ca204e98bce5fd7de7927bf93c71c2e853f9f0d4572eb31dfffa8920bd39e476c7079696f1eb5aae8d067ef08783073c11f1b1a20a0a1c3e72c276e320cfd3feb2d3a9fef818d1749c9deae7dbcef49b4f3ad010001	\\xd1982c1d066f83716be5b7bbb457ea87cbf956933f7604c5ba08e1cfa78969c2fd08b372be807cbad4fcff72a73e09c006b990b212c164789c6404c219c2530e	1677112772000000	1677717572000000	1740789572000000	1835397572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x6330c8e8cf30d87941d2babf9b3cde5ec896c480fda6c6beb2b5178e6c1d34d59b09ca55ef91176f568b29e8d232cdfce67bd3bcc8f28de488b9be1cfddeb611	1	0	\\x000000010000000000800003dedbcaa682833d103c3efc490aaada25b2eb9f39c8902cc63c063502bc5cb008f17d3f1d0f90181d6d6cbb944d750592e3a5c3009834b4f425c4bfe228276bd195988c27c484101342b80ab857284e99a31395dd9f3a2df65ae523169c2a12ab3152d16f7cee701a09d3b28524c4ada5b56f67a3fbbe59521410a46846c789a1010001	\\x6d821d2d2da3b05ab442c833873a1c5303b5bcdf823cf843392513181969a13473fa6413f2420be9b1d6b3c17e8b43e53f29acc8673d9c8885b38501bf335201	1658373272000000	1658978072000000	1722050072000000	1816658072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
45	\\x63847ef41d36d06d3913643a138932d8560238c1e9bdcfebb1a970d1eae1161d28538bc8a0d211bd6cf420e73ff44c2a3894f65b1f1343217c0f32e1d8404448	1	0	\\x000000010000000000800003d88ef073a65571e44b20273d2c1184319db9b69074e8e06103e985516206f03e523f1dc5aecc3cf6b70daca139bd48d5bb8edc8088eb7c54ef7acbcb143d515ed79129314fe338bbabaaab8e219168becd019d669d3c2126c19f8a1ea52c1868eec95c6e4b9b7f4739a85000515b4afc2ab1ba8b25a19066b9837321e91f9e07010001	\\x1675ef3237fea684112d97805c291f9f346fcf92e90d613769ab36dd08ac4d6d05d672f303eb44ebc8a4460c62099c0936de5cba6016cb06bf7ad1dca511c206	1662604772000000	1663209572000000	1726281572000000	1820889572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
46	\\x64dc81ec5b4ca83ed1ca5e3b93792cf7f61021cccbcded399929e0772bfa81ec888ca7063a045b59378c5cfe57b7407265a8cfa7d12720f028ac41ba5b109a52	1	0	\\x000000010000000000800003bed1f11b1f1cbcd80230e0e488c7d5a64b24083857382f18d61d7f5865792e7e874594451ac11a4611bdbac42733c141ff675a0a04aad914a44565c761f3dbb7a14eb360142759e6c8dbe313ba0a4606ba7df37764bfee172841005cf4ea6edcc3a0e8e974b731b48978203fa8c522e52651259e7de6e0d981836e6db9d4c68f010001	\\x3f6cc636c4fc0529fc52f4c72263143f2a7640b9c4da76111c6464d4ac7b8e5417b50a01199e729166ba443a35fe4c41904a3682fdf8a01483c3447edbbac209	1669254272000000	1669859072000000	1732931072000000	1827539072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
47	\\x67a8d37062eac2aa51282b917d2d7146ea24bc27c47e19cf9fcec44587b05ae5c580870a6cdb5c16cfd0de0af4bd89a062bdcd25acdc1aab1546756286c625b7	1	0	\\x000000010000000000800003cc2e6dc2d3ed91730a34b6ff768fe891471d7b8b1fc258137603e1446daf1309a29667906747f5e30cf03ff6d10cb93a41ccd81537c98d02c441844374740355f8f168d75b89eb3f4fdcee1cad4abdd4683f4dfffbdeb1227895a4cf856bcad3b52cca3b4ecf31ee7e263baa4b412d44bc2e647078448486a4f4d3f5c73e5c57010001	\\xf4151bf9b7b815b204b3f7308b462d6b5f81d659fb1446318ffe19a829eaf454f417fe3f0c762ab60f2734e5b63ad82d1010ce9a5d66d61ee7647e8eb5b6780e	1662604772000000	1663209572000000	1726281572000000	1820889572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
48	\\x6850fa2a1a32f24ba46fe23c1a0152ea99f9d10544979f8e0fb22e34320f755ef7092ea8b5c143df366d78935dd4a1b25617e43e685074ac9fcacb4009263e30	1	0	\\x000000010000000000800003ab7ba5e807099efc7cba0d16d3da7d255e8a64515cc1ebab784d7d8b1942387ad123a6c3fd10b8675b885609a99c879c82dffa07b63235fb0e9d6fc189628cdf6bfba789135e4b9d2b9418b4a0349c87a3b2bc0dfa33af0f97a3f2bcd774ca6f32f7228cf07fb4b315eaeada4f334720ef5a5f09edbd4ac27338be0cee6c0999010001	\\x0ec10960eb82cb49efd7a727253fde431315eada39659f322de17fb011047c14ddb7aa880593146636f32bbe369f5a7fbbecd68036877bb577a0b1ed1f9dd500	1668045272000000	1668650072000000	1731722072000000	1826330072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
49	\\x6be4393e70754f49ec7588520839f99f644632a1da4c34cb201c590c8cedd117fd60199b99373e20584549d0901121253dec86431d61a818e5e5a0d9d4c31394	1	0	\\x000000010000000000800003c208cb6f332da01a24f62b7cbc4db8630fa5272240ef00bc4e510762395d7535977f9fd29479f5754c4230dd000a408966f89e7438f8a4af8f5152e1f1b827a01173d919cdef27ee469b5e5ea2ffec5020a646f805d3d815030556313afe74a095df16547929c2556566be77b6a680c48994ab163a8d57fc0ec6d186da37b857010001	\\x0b757c0ae9d7b1fe0df8acae2b4c1fe4d88892cba0a332b6e36f698a0d65302ca1691c02f5697a1d893e240695103a46d34899b9f0ab00e3dd97e8654f4b490d	1671672272000000	1672277072000000	1735349072000000	1829957072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x6d3873f488af650bf17b41d9a86dad878e5cc12195f34efac4255dcaa6fd3a0f1b4c928befae70df4107504321752125be153e025d756e28cadfbef946f74c15	1	0	\\x000000010000000000800003c465100212aa5779f6fd341edad5217c8e23ce6b63efe659ecbf6de483e57a4c637adbf74758bb5171a43564c1dbd675bf21d0797c4396f9092f50b5561820871580f6bc962fccc4114e7425b241e613c9e41e1ed9b7c5cad20e7bb1ff7ccf1f9b7a234bb6594b9bd2f53b85906e353c5d8a8873a2dd0e1e33172c2d0ca3ab6f010001	\\xe4295f6d443e029a3026c077e588c0398058cc5502d4bf351ca14312d4f5cccdfafe2dd45e333cf5801f325dae6a519d8457458a4421a2943b24949414237a0a	1677717272000000	1678322072000000	1741394072000000	1836002072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
51	\\x6f4ccb3001ade95cbf2dcf0449d39aa59dbb43fa82eb4bac2b3471f2456867b688361215fa7a7a705839be4eba8c6ddbf6f61fce0b4722c856b3c774c76e5ab1	1	0	\\x000000010000000000800003cd30a6744d2a72cf670084661733afd0407096fd81b4a1644e855a988b7999240e4fb7ff3856166c985065ad1143bf24be1ccb54cd20027021bd1f4638e0205e7ed988678bcf4bf398ffc1c3aa696e62cfb6f67c59d9e63df901078d6cd85fd8d043dc9a0fc2cf9f57cae7df50f5024240e5283f2d69891a32dcfd2f45d42413010001	\\xcacf4aabad52b43c46ca6bdff4cf5010c0e39ddcdb8c797f0898defd1c5f0f4c06ef5d79635536ded00fa9019bb4a1929e9a2373e14faf04d15f1cbea6ab5901	1651119272000000	1651724072000000	1714796072000000	1809404072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
52	\\x710cb0ddc7847bd4ecf0ff2a7d3f1fcfb1038831c1d2660ef6034e61d7db0548e0f98066d284e8f7205b76ef74b3fb27c85d7203b614435f67eb0182689e0a7b	1	0	\\x000000010000000000800003ae7197bb05fb1830d0ced0b494695edb49b29c41972b79e876ade1168badc9f7eb946bc6c632f1aeab37703b8b30bb505d7a9dd531f1ec0d91a0e3963b77c8c55f6a13ec053dff96f8b3850c5514e2000908570f7586c114672a5fa83a689187a8117ac931e73e4c57a38eeeac68385fb3f3c297ed9d4c487ad6b0bae58b4f25010001	\\xe3f40d006effd3cc2ce727e91742ec9ff9e8ac966bab2113a2995506b18a3a21325eb6a34f82b89df56638d48b246d94488ab85d99353a5cd503421860ee2406	1677112772000000	1677717572000000	1740789572000000	1835397572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
53	\\x750c2280c9d71aafe588be091ba4da5ba6ea2bb857ff95a5c213d40e72e2c6adb43a88a7755dd6216691e8a3ad9e032a3b614332ce9ee6997c1fc6a840f6736e	1	0	\\x000000010000000000800003bd1ed6d0ff8a696f7c56d27d64401c2c6079bc34eb893697a12ad75e78e6bf9c7b0bc40ac58775de260e4f624e54cfa8e7e34eb4354167ec694260f29b902abb95ebe11d705986c24a2034d4aaa81e904a24af5f65ec80a0c85a133673567b46a0b94b433ab4ac6e67ecd4fe24ada683aa8f3b86eac0a907696c77ee88885301010001	\\x9d4934d9ea67b58199056b663ee0b7e3a54cf1970dfff839f12c3c62818abf5919141e822a0dcbb4fa1230ef42c0e96e085bc3616d0720c2f35cbfa4f8e2650f	1671067772000000	1671672572000000	1734744572000000	1829352572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
54	\\x75c458a39a24c96ed1d56fcb587ce113bb9765659bd4744dbbdce7075262d8552b9de640fc4d1f348c6dbba7d4f51fa3639adcb84b3bb235874ea0965ad50374	1	0	\\x000000010000000000800003c49f3d6264017dbca6bd97324990fc2f054f785782d26b8561068d19c7395d9f574fc9f29b3af69b7b04507f982f66c97ec43105c10fb99d73e51e647f6ffde2d3674203b6e205f6b421cc7d9ca5ed60614743e346c36eb9c234c828780720160d8da1f3936992c65c52524f85cdf644d4920f47661485edd8803d7613d567e3010001	\\x5228200c892fe9414c173c09871a54d895b2a69fa47cfe122588f1a159dcfdb0211d7e4f058ce30d89c259ba5fdb47467746e2888d54338c7a4399c629c0c108	1660791272000000	1661396072000000	1724468072000000	1819076072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
55	\\x7afc9a73ccac46516a6827433e444e546d7df546f731d468b27b0a56e0dc017f3e4382b7c16db5c4e0d6550c3a9050332efea067b5b96cdad5905aa6b14b8ec2	1	0	\\x000000010000000000800003e3fa93edca9bf723093c67b753a047939dbf09b68f3d264c147aaea6a955fdc1b312ac151c89ee06cf5a172d32f4d5c96d242a46b26244ad8828c7c7af625579b2e6d8008dc1b9942be441b3788f3f61626ba256d6adfe6577884e36a46eecc0b273342f4a9d06582cd1ba2cba9b4afd5eb633cfa9376f0843fa862db4d21a35010001	\\x6b9afbe27127ce056e118f18f80c122d73275bfee9690b0374bf8133924ff9a8ac6369924c7e383d4fd03e63c7a044fd6255e311746decd6ac00e32dd8e5ff07	1655350772000000	1655955572000000	1719027572000000	1813635572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
56	\\x7a6c28da2e9f5e1e432264ad3adeafc6d553b929e112dc5b2054c236df74ab855310f0e854b24cb049b3352600268b51e20bae22e7d5b44e00716c8fc6c2dafc	1	0	\\x000000010000000000800003d0d092bc278554f06c98fd40d3577575fa014959712b59c0881d45b9f854594cf0e324a3c5a964308be082208729bb2d4b624c2e7bd48b0d69dea2e495421fac9387d187313b10456faf30d6408b3e32cd1ad8e1778bdfa80df82f30a27b57fda7476736bae285b49df94821760a0f751e644d51c2e67162d41ebfb4359465d9010001	\\x55568ff144d38db7b66a8cd8a951b2240cb3622d3ae34d048b0a19618e9a2e86f8898e8df26cf8b18318e9cb39f7c1ceca99114e8360fd77ac6acc91b03e8504	1672276772000000	1672881572000000	1735953572000000	1830561572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
57	\\x7ad8cc5a7babe452cd0a14aaf2614f77e8f91873848259b88f11f481dd160555a05256a5057554683f28046321e12f83d2410bc7a1b541220c60da0c4ef220f5	1	0	\\x000000010000000000800003bd8c6b6295975543907f0df57a4bf1fa490733e6ff0752a48e7900c7df3d4f36cce9e9d1bf65be136d316810c93723aa79ed93eb760e237761456b9daef6ae1e0d206ca497b8cea3c8d361c6d6e315602a15da62369d7033a44b91c2a60713d21a961082c4e6815d2d962f3d0f920fca8fc7b0c710a31b01c4f334e0f13368db010001	\\x58421940a14e5dbce55d52c6d61372993b44e5dc34279c52e99052fdda9d5fa2ded8390a6233d79b35bebd682f5abcea2feae07169da522d7e82e0529ced750b	1648096772000000	1648701572000000	1711773572000000	1806381572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
58	\\x7bc04a3e8d20f92d25dfc9d9a7e92894a512cacfe80a00521e13b136ccd8838dcc407f236854c77ac3c23e0ca9952bd11b7e267919b52319eb92cb7a6775fe7f	1	0	\\x000000010000000000800003d03ee90959d77c4f9c837055afb09ec8229a296d4ee2ff87d136c65f438a99c0b085f4811f0f93531daca988ceb543d155048c076f986369ee06e73e4c4e1f812d243088cb36b0d3021fd77c3d0f5a134d63cc72f543bb500b3050d8104ef4d4f31de060ed3b2d01e235179f03bbbb249537249303a022550b21408fa7cbfa47010001	\\x56bee626dfe9faf698724efa55923f5acc5bf5bb6195298c7d5c921a34f7ecd64f48cea524218397a1ca8debdddc237f14a70a96cccfc6f1187e32baedb09503	1647492272000000	1648097072000000	1711169072000000	1805777072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
59	\\x7e68f6fdebf1f58c62c6f70a02b82ab13023949a8cb807ba225f5516c8d64a61ce95abe6272d57fe4bfb1dbe5129ca23031cb7c5079d2eb18df8ce6d5ed4ab3c	1	0	\\x000000010000000000800003c2dd5f05f3a9b5e51bfa67570ff26f2a5d333bb1a6786c6e7945894f7776f66bec8530ced3c166b061b08c56de83f9eb8340f3d203912434310160a1f043621193e98ad88a399ad9e58637084c064eba696c5eb922d13bf643e5552b7308d396c93ca3212b239f9c968a684df2124a4dfee575e242beeb24a43b606af06cb0b1010001	\\xaf53c0ea4a0014465e6f9e063215626f5298e524668d71d6a5bec4c2905ff3d419d31cdbf3f0de416ba15e30ac183151867d109ff6bf6e8f15becc7d8d5e5d0f	1655350772000000	1655955572000000	1719027572000000	1813635572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
60	\\x83b40f032586edcf528c774049ca9d1b23ed18fb2ec74474423bd28986d2c31c049efe325e7a4dff715c0b805eac7af3a1ca51b193aae34313a038174539bede	1	0	\\x000000010000000000800003d2c0393951d2dd179d673ee00cb70d495ba99725455364a7badd81c5970a29073cf33e98e47bfa733918396015f7e1e25f4a66647b8fda1ec5e11fe89bfa97a0fd17246e7df1fe86eb0994a00bd47cf6d6a40db23294e4f535fd79f12863c1e5233944a054ed15278b8a5f34d87565fc25cfb2af96b3f0701ac896a7ceafce51010001	\\x9614505e589a04dd436dd8732d46e64b87ff7c205c57a6f1e22f07dae7dceee287efc2166def7a053c716db8dd8d49222cbc3e125a555d5d1d7719c9503f5b0a	1677112772000000	1677717572000000	1740789572000000	1835397572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
61	\\x841480385f70ab182822889ce45a5b7781d36db4c9e4af69bd9bd24e3e384c48d4ba036a9b8d352d372615e10419d7f73161dbf8cd9d560045ae40439a95a4d0	1	0	\\x000000010000000000800003d50dcf8a21ce48dd3701add3bddb64eadd5c01e74b83a4ed140db63cfc6376550bac33be3a7520db96b8904e83bf68bff44955cd87adbac2a672acd33a615d7b90e8bb15c972976335dbf348e37afbd16dd509dcbd849c4a47c3077d0c89e105428226f017537bd7ba1f2f9e10c3b2974a1da6a01d2556a95e40850cc2db4f1f010001	\\x673ed613c34cfd250ea511077b8a3de54678126682ef075183fc08036eb71f7f92c1d382a20155b8a2ddd0dea9dd264aad3dbd6f6076b06d378d90efb7661f0a	1648096772000000	1648701572000000	1711773572000000	1806381572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\x8594c34b801a181f01253f047a6c411b0f62ddb882cb713c8f034026530e551eb7b9e06bd23da73a9d3ccb60fb56104ec292cddea01bd7c34565d89ff46cfe6e	1	0	\\x000000010000000000800003df07302724ccd12049ba13ad79b75df92d2c3331e5a471ebc27036e3d4fa4592cbb247d62968234f18a50ac5f1aa6bd01e4d4c4bd567aa00a8f73fa766fe984a4f39ca23a1ff46ba4567a4a0081fda1b1e90e1ee10dc5aae237eb0b6758bb110cb6708a424809c83b60b7474f267526a0835c23bd25e60a863ed9229979e0bbd010001	\\x6c6e8c2e1eb6eceba64b1de2c043505badf2a8151c3807c92d2465ae505bef6ded80cf14784cc53f2b8812e28f5a797403b36a7eb3bcbd4a21db29ac33bf6b0e	1669254272000000	1669859072000000	1732931072000000	1827539072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
63	\\x8e3c1c532f104021246d76c5158105ca8f354e7c1563579f9d04822d30d3b4a8c3ac5ecd1e1b43599015ae03700642161987dbf6c402656a92489491400bd32e	1	0	\\x000000010000000000800003c9620ee4f20bd7009d330440c4d086e18ac80f45537d11a896a3db08da72d69b81fc047344cf525b1a363153d8039f16a113cba3abebb93bb827811a869259a4177a7274f1117b597b52fe3877293a238f4ab0c4bb053770b245db04ac3f284af18ee2476bc670641b36f56ecdd2fd33c3c50c4e131556ae8707cbbaf7ff6415010001	\\x5e1638ee7cca5b32a61cb951722c508ae00d6f9fe57ce202ff43746fcb320c6b8db51f63930e7b89460f2be7808c5dfb39ad6079047a583c6a788f8ae7540309	1668045272000000	1668650072000000	1731722072000000	1826330072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
64	\\x8ef8e857efface3a667b3e3da3ca4e2a9a7e0c59b984515197f02aec8457903d0524b90e98915887ed4b607474cef24a2a677f2a7b09290648834f0ca2288466	1	0	\\x000000010000000000800003bccadf750a7e35f84388dc7b9406f6887b4d0e43b4cd4ca908fb6728f0a41f625186073273ab8d864c087c9be02e90e4c0367f5ccf390000e609d0f6165a037413f993df1f5327c7512b561b54c0c74a91187e7c2920606f421274e44d4766b04dbfcf428f49a770d46c018818adfa3c73c57df4541593a2ece5fc407440e013010001	\\x720193ad14e55a564559e6283b05ea0d8ce88afb4d8fb08c2da534b4f3dcc6feb64a6613df736d5eefa4b1fe734af7bd383667e48de7201a36f3ea4f1b57410f	1659582272000000	1660187072000000	1723259072000000	1817867072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
65	\\x90f8e435e8f0f55b70fd6dc845a76834a662a1859ab0d410a4e674acc9f24bec850b28339eac5a8135bcbac3b149f50e8afa78dcdb7936288e33700ef09fe890	1	0	\\x000000010000000000800003a80468141f1a252293006dfabc8ab914d3be9c2d44fb95d8f24da7dcf062e122696f2be39c18f1220b2e642ee06351ab05409ef8539271667a63ed8cfa25344bb932edbc346f784142ad70dc023d0413b0274b2c9efed7854939aeadef235624aa0e6572777c6bd42f74a18f9eb25aa87dbaaec14f6613ca7ecf7fb373d46a21010001	\\x4d5d82fb48614a24708ddc5dc4774f3b5e1f876c372b21ab14c307e4f5cbe8ff2d4401376748f3f8e95000b89c0b5c801d0d20d79a67a26950c1a22111fa990a	1666231772000000	1666836572000000	1729908572000000	1824516572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
66	\\x9184da285e77019398e36a5298173f61ed126e50f71140fae046f73485baa70096c1d53a06a7ddd5cb675017aea752dfdd46aa3dcdc405cd7588e348f03760eb	1	0	\\x000000010000000000800003a1a1ee71dcb7c51fa7046daebeeaa795d517dd7c3e0cb2fa2be5e8a6fa31d98adc6a7f93163a1b4d3c5f6808694035ee03c38a76839961a21fad4e14557d00356704cd54a294df74db68f436baa6e91ee4f2fe77e214ff684805239c71bca4991ae51214b8ef0daeccab0f8f13862634db752207d72026f73b2f0408304bad3d010001	\\xa37f921710070e8a7910f7d80c83497ce9200d9d0d33028c3a798a47914502ef5792486740f83dbb1f570e3884dea697aef83d5df14ce7e4c09e520c3c74da0d	1673485772000000	1674090572000000	1737162572000000	1831770572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
67	\\x913862a11e451bc1a8e9db6ceb64e2cda3f9ba2d30ae9be022adafc11b2f783780443590de9395e2ead7563e2a53cd35ee954050a6cb40347cddb143a098bb01	1	0	\\x000000010000000000800003ee1e3f237add6009c742474a205e49491ac97bf4e7d3d5b5889e74b2beec99cc210452b91bd6921462c5aa39c9954d59e21c653453ad67da7f79373514d88901e7aabdfd3a8561e66f044006ffbb5c489adb4cd9ab905782a0e6fc140bf9cf2592175b9a708a43c00a7d5b4dde99ac29bfe3aeb86e434b2e452019072bb6e119010001	\\xff9b681562c4bec42b587a986824cd219550f49a531f570f30d8d1fc851a24990d4a12aa774dfca1ff83c625a4317aa4eea6a3fbcb37d878b6074673f5380e0b	1658977772000000	1659582572000000	1722654572000000	1817262572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
68	\\x95f881728bb6e1b938a3a6de18a4be218dfca55fbf662039d1c438c07a137d008d1f20433547e6dde2928651d432eb38e6e7c70ba29970054fb9a85d003c06ff	1	0	\\x000000010000000000800003c40095732e61622bd5ee67be474645a3d79bfb35915c416c2baa10b8426ad515d3a36f53fa7a73ba1fef4b174202f322fcd3e8fd128a1119baa660c59bf4bd3f6fae0546260d5b9b5dfae381151d78d56b4a866a9e3050abb6e39bf01a2a2f8822a9988d873e75997ce37df8c8817f2ef1c72a46da052e3a187c99d0519036b7010001	\\x3a612481350c5600932d676a8c415ed84acba30d781a6d3d4046f1a0161ad5ed5b0ee0f896c1a349d9af47d8f5431a5a017318dbd4d8ea73d34f89cf5323f602	1662604772000000	1663209572000000	1726281572000000	1820889572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
69	\\x9a58415f9be833891dec62b841200abe91b06f360a1c4d6ec13a8e85372243d3966f9f48e6debec6631673ca9ebcc4d2252d866586ef7f528f1990973567dfe4	1	0	\\x000000010000000000800003d0c2025e6e421c30b5bd89ff9e2c2a1bbd97c3afdd89c9ee2a22229f8dd114c2491f6b337dd8cfb985d3a31effdf9ebcff2986a039cc20ed26ff10c65228e8076a7a2cc56be6ca6fd0379b4855d8243c3100e38ef70df22d13840847fe835d31745bbe024ab8b131c8642080f3d2ba64ea89becc5a6e489fd576342bb5e06ea3010001	\\xbb72b7b84bd37408475e05c2b925d44da7bc3b6a96764788bd65adb89412b2ba964e2b0330be422af53ca520b7f555be73d0c898fd63c3ca4ce20ffdf9dd7e0c	1651119272000000	1651724072000000	1714796072000000	1809404072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
70	\\x9b18ee34951588464507c6bf561a127a883cb5da7e98aa59186ae93853f57275583ee4d3805af5d28835978e0a5fc5a34f6b5975ff3d11019804d8d30ec5ac67	1	0	\\x000000010000000000800003c98eff4e230d7a1a6b623d3d6030e3a5db1097ad079001d6c12a61c83687615e1611f09403132f9a3abd4734f8ef201d1a2bcd912eff45a8a4dcfa6b069c463f3770931cc9eca9c43dfb949712671beda9852cad94db3e6e3827fa8c502864575ada9d5e650bf21c60c5330cedb09137249aa4d9a5ada1c8883fd7eb38087267010001	\\x3ebfd10adc0b74aabe50164992e5d450ce735485ee66950b12b007bb2a3347826f52cc269a6ad71d9afd3db491e9206af0b40e34ef58f351ff3591cda30d8108	1657768772000000	1658373572000000	1721445572000000	1816053572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
71	\\x9dc01233e2330f1863488e5319b3542dd00751d2df3d144cad817bd28d1c7c865c4e2213e578cb3b14497f4d36971b3e009f6ab21630860eacc0af9c1204e27b	1	0	\\x000000010000000000800003b9abfa957293f1ea4dcfa95ca82d6cc0a3e93ca2410d25ec6ca96bfc7770178eaf27cac4271dcb3d75aaad0f8675b0beef4c1ccbf07879d49832417f7a7cbd1fc7f0956641588ad77693a4a31a7fcb56c25e0b51facf7387580483c021c1ac19f83ef94bb9b710766bae2a41a3c83066b462832f0dec031c531bef901ccbe831010001	\\x849e079d8291c773997aaa0eba4be932c4db6d3933e3a3ad4995568481a252bfc65ae938bca39210de21b4ed23d42f2c8eaa2c02903395c1a353f39cb4eba402	1659582272000000	1660187072000000	1723259072000000	1817867072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
72	\\x9f8c21c114191f75c1a35e2de410c61ecee1734796e26e17da07345ade20188ac96626e8310fb1d558341253e85b40b16eb0c3a94303ed5501fbea9c3ca3c153	1	0	\\x000000010000000000800003b63e3b93f5c1ba7bd5937455a4ab2652dc2fe7a26d5aaaf5629244bd25672c278d33f4e6079c71a64da7ac0549fca011bec71bf9ca30fa773d67c1007d7fb44d5c04e474c1fa875de3fe5ad7ac26a357149096369c2fa63874bb6d7d9427dc25cebca6ad8bf7b2b7fcd32a99455d138eb56045f72e6d92d5ed7ac087beee46d3010001	\\x1a1e53f488544c312516d0afef52e047d82e601e5d7167d82fe4e68abc068788f280af75be22e09f2b9e76e1ccbe062850a17af648a97da1c8a03c97ab85720a	1663813772000000	1664418572000000	1727490572000000	1822098572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
73	\\x9f94042d3713f17ac10297c8053e1d6cc2f6e2757d826a32a8805ee93f5b05b5da12fa94e5fa7853c50ed45ff83e2af45623dcdf620470ca11102d5bd80bf155	1	0	\\x000000010000000000800003f1ef34d3ea581b0cc985af7c878d9143eade5ad1b3a651c409fbb4bda9183652c3ad9f7e7a2b4ae9cd9d2870b3e77329c6197d37e0e999f7457afb0559a037d490d8d119e3dcc7babb8a560e013d809e29c2a770d26381b2b6521c748cdaff61eba1ae4c7469370afc6ceed1cbcbc2e231d2e6e19d4bf8eae532fc59564d0a2d010001	\\x3e50eb22ce41dd2dc578fb97c7e894ef699e61dda3e57f1e40bd9d7486ce370d5d05d836922b637bc0ff9a8c2afc1d0fb494df053870248e6bf5098f544d0a0a	1649910272000000	1650515072000000	1713587072000000	1808195072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
74	\\xa08c7b9071976f5d0b30431b6207c8bd5dd8a66a71e7aa68a02ad9ed77d5318953ccd218242d14b3e7515b91552cee07484e6fc59c9b5264e0629941afaa42fe	1	0	\\x000000010000000000800003a4a3bf38cf573c08543aeb12ad807f937654fc5424320a4193b63bd36f95e2a5ede14635a98abc2241266269da0740dd2142b40e3568a6c01ae77f6a64affcc741edaad3f0c79af5eb29d7c45423239289c0727bcf233a7da5182fbffdd512556a574f9adac640a4b7a33031be4c3b39fdc9383d8e44debf1619b6be6ff68381010001	\\x97d34d7fa4bdb4e666ef990ba6fb2c6e4b6ff29b96e3b9cbc63b5ba985909aacc80fb486abc18077521ef31f81c1f4e354462b4a7ef05994028025dba35df608	1678321772000000	1678926572000000	1741998572000000	1836606572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
75	\\xa2d4f0d0621b8f501790c5fce2217ea3c1b4c0c3b7297b12d1c2d15a0aa63e8e7082a9772a7f2488fafe62bd227af58b268de5458a6fb7eadf746bac4bf89d40	1	0	\\x000000010000000000800003cce7201d836b5ae7f1cca372b1f7dcc11e3955867a26c42d05a23ffcc745f9f76097fc1f4c9ddb8e82cb9daa4ae1c8c127d6a13c87c9b7d0722ebc64e2fed87d42b2692d2198b1a2287a32b8d917a42c00e847cd16b581beb775272ca2801dd6b385df4bec9ba7f22e7ee5d9553a9a7586dfb82f495c423bef41d26ff5e813d3010001	\\xebfda9cb20a28e102d28c4b1f4aa1b5053920c83e6cd3b19cf9018cd5925512af8964294b0f53542299d86de4b1d2b619f7a8c10559dceeae3cc9857d931210a	1659582272000000	1660187072000000	1723259072000000	1817867072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
76	\\xa47458eaf690dddb98ed81a9c07e61b211d2c5a39b7be3bdad8744b463e29bc496e7bc745f1d50604a9adf5bcb65e9ee02c44ae20e1d964828748e9cb919b403	1	0	\\x000000010000000000800003b9bbb8ebfd3fa0083a1ac2fb6b7e10f0a394eca58bde71b4c174fb029a005de4c18695e00517273f2e0b9a9d245c8f68355fd825ac69302df8346b87876306c70c28936817383a7b37f07708e72cff28197483329f01b779ea57dcb119337ea12e0273a526d405dc2c7744a1aeaeb75f7293c45c88524b06feabd21e66089079010001	\\xba1e97f6905746b6ec8fbff87e46f8ef560803b0bc47d62631cc9d6a7a67a6a068e79fde9073b8ae811eaf01ae7dea566d806ba90a2ebc0ec13f9e1f7b6d3f07	1648701272000000	1649306072000000	1712378072000000	1806986072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
77	\\xa48c7eb4605e26898a7f5c69825ad1a3a661d983b0ca9a72f0914cf8d78d9c20280e66df894796c4c358f08bbd0c80d946aa7c3686bba9647b86368cf1a53418	1	0	\\x000000010000000000800003eb9b0946beb35dd4d3075a317fc6a070ab781c76cdcd40f199dd134151b09566d4488cb7ff59cec4e2142898ac33e47ca26b5b62d4af1441dc794cc0638d452dd55298a7d2d11511173d56272806ba0ea4682315417db4c1b3df8ba99401c6087f1a553f0ab3800afff99b924f5328a59fd5f86d2840920a06d326104a976ffb010001	\\x3b3f02670bb516c60a5349a855051dea9262592e687b97527cc586ebb87a9a19637708792f8cd76e70ab104d7b00fa446369fd090eb9f7d7ecd00a723a58b204	1675903772000000	1676508572000000	1739580572000000	1834188572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
78	\\xa6f0a0af90a80677f67c8e58ba15bfd88094efd28546c34ddbc6e452e0b288d98d51206952f42cb7a83890d67380bbca612ea4c897a24386e285efbe8ab266f6	1	0	\\x000000010000000000800003ca4fe694939fe007db13838ac3b457d636e605503eb93b98f39420904d4e63e2e0e138b5c856777659cdf5688c1d8d8522512650bf1fecfe29a859fb0702be73f5f667b9a649f06fab7a20a52df5d94dcbbcbf5d71b41f9bdedb26f58af37f253fcf8736b98c153847d58777cde25a102f4b3d7dde003382e528cf306476fe09010001	\\xcd8e5a3bdb36bfb1ab958d2f9bde703543c46fc681c674b74138d7b91d7eb6c5fe815887567f4daf8f16215f927fb2825026b1248d021b75f4413aeb6b04830b	1673485772000000	1674090572000000	1737162572000000	1831770572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
79	\\xad3478d238d11e016d9007096de14102d2517f5c540b2366121ed63f4302f0167ea5d6f4e11e00747ed82c4ca05f7ffaebecf6018f54abfea33d090b5a780ea5	1	0	\\x000000010000000000800003bef4f910355047688603b7092fcac5d607f635a997b8ca317c8cf28456f12072a1f0d69ef8900b90b9f86c9d1708a0bb96171c03a2fd94aa38909ac07fcbf64ebc9c64ccf01b94d3d1f06530b2353957526347f7affc13261ab43bd92b367cb297295ab24657ea79992dfc1e203c90443f89bb1f37d081228c5e8208688172fd010001	\\x9e5ddb899c5246c9b9ba2a30f93a2a3740a2fdb64ba0d672b49a3d50cc1c15926eb66960ce4f2fae636b86af7695795df4b5fc4e26099b069f02c3535f9ee201	1648096772000000	1648701572000000	1711773572000000	1806381572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xb048f794c9dccd9ac7e210f2b87cacff1121c19d63286fe6828240197afda0b3b5a31461b2a55aba49841fcb0eb42b12403842b7975c7d0e25da3623de0daa8b	1	0	\\x000000010000000000800003d74bcb9f68f5f040368c24eec4ab86f7722af1c6e5de05be8afdd4920f29f312dc0b4a8ce34801edba901635619e5ad79b7fcd97dc54c13a853ed2239569f65a6019d6f645a6f52729d1c4e9ba77472600f032a16160980aa297c9c9aaa72e522b16708ea4bfe9343f18417436bf395c707892b7eb019c9df4cf1e966a1b128b010001	\\x812c6752a80aeb6dca70a92b8ef630e9ced8371d1cf098762f758dfb5e2b98f4eaf2db2ac4f671fd8bcc184c1c625cfdd67e2b773c3bc5366e472dd6fe3a7e0b	1664418272000000	1665023072000000	1728095072000000	1822703072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
81	\\xb224ef34cfabb39f697b7a7c94fb79ed79f661f08a65408cd628ae2e4be833a2cecdb5020cc70577054a2f1c1e4152e2d1c6407e90eef644cff10e05e7933269	1	0	\\x000000010000000000800003beaddb94c12f000074c5690fb4126f85a2c2a1b5446f4831a24c6aeec59b504e4ae3b766cc7fd7bfaa6cefc5ef3762ccc4e1ae29e4a4351ad6957f9e0c52ab3bee310ffb9e44f4d6b9e2dca335bfcabf80fb727ddca205634d069b1983b594cd460eae863e6b252086637a1056fb1f68abb42fa7bdae4027be8dc37e82c6246f010001	\\x442c5fba6ea54a5bd6b24b8058cb5586265257c76b2140f6efdfa1e40bee413ef482b97926225e96bda8fe6ef9278617917719d183345b320b722954c51ca00e	1657164272000000	1657769072000000	1720841072000000	1815449072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
82	\\xb5986b4d49e7b7aa350fd432b654c9ee952c6c073b160ddf346923c04b06c53e9c56781097728849e7516038a212496a6780169e7072094355bdd90c0d0feeee	1	0	\\x000000010000000000800003ce6ec9e4a8cdf377108b7d42ec50a71a87879808b1f48a3d7564d043431027d8a358f5db8b2758d4da27484544e8515f41c028007fdd33c3232bbc2edcbbc98ec98b653707f70099eba4b27f2f34cf52f10a318d42db87e09f607f6878ad6914b768e9f9f25200ae006cd913af8a30db7f7dd77a9abc82e8e7838ee2f666750b010001	\\x0801ccede6f6c2f6f5ea59edf5a85745a3baaf364cba28196fb6494ad9eeb08490f3bde188a666b2ae1fcdfdb80d3b613c5af4b5245c026139ad4ae012a3da05	1651723772000000	1652328572000000	1715400572000000	1810008572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
83	\\xb6b4336c79ffab8bf364d7bc56d2c031d6d1105d58fbb684e94c84f954bc93e46ee5cfbdfd632bf0a5ae8a9643a4e783fbeb9c8ba6e3a98768a136455712bb7c	1	0	\\x000000010000000000800003b7b12ffb7c96bcfc25926a35fc7ebe278df662e32b7cd400202474329e8e17e7cf795fd479e5f8079f580cd5aa3c079134afd2dc1b58dd9d4f8c7c636a66259aae2c070388b0a118efd1b0dbf640927d3706ec66901780a6a612fa155e56135ead9bf256e3c66be2f86d7c182add78b888a7e8a3150f4d350e490b9ae2edc383010001	\\xcc75387a44f34d2c4306b631c0194f3d7414d4449c3d4cd33a6ce181adba30f13f7e8d934fef929ed273af2c1040d304ffc8a743f5945ec74f6ce4f5dbb26c0c	1649305772000000	1649910572000000	1712982572000000	1807590572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
84	\\xbd8420d7b6c060614698f2e062a6ca62c3a47c633cf0764c0b2f60a9ea15fbdc46bb0304376e6fe91e09176284f684e698ddd2db8035104c0bccf980b33dff37	1	0	\\x000000010000000000800003c04022e6830610759a4029af14839a9fee4f68a484d40ce50c1d65cbc0e170e945e41734296c5024e0cb42594b739e52dd0bcf9b575c2705f52ab62062b5df24f9e3f7239949813522d2f65ef8e03058b151f9fd2939dc6be0efa5b1b8e98972de5d310d1ef72e14dfa1c419ab3178f55847528c72dee35ef141b8e29b9c5075010001	\\xdf21f643df80eb2390ace142d53f06263e0a0904dea22a951d22fd629478a8eac43799446082929468f583f4a5eb5e5b741f2b04bd478d07847aac70f3955308	1654141772000000	1654746572000000	1717818572000000	1812426572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xc7d018bdedb8a5ff720efd9532833cbd39b5914b78c1bb76e7c9c24e2673351bd927569f7d865c2452e7c6fda5a57f70acc4d086779ccee707a98fb2a41526bf	1	0	\\x000000010000000000800003d1e4fb4309b04f7bf0ad4c6f7529be27ce01dcc4822dad76cb2a28776a78a018ab742c132c1b41aabf0ac74fcabe85d0832e1c6278a866b2c7fa66a121c33d3199bc912a2f8b231f1a502a9e3b9d902b82fb1a2e5b9a7a8674955d6c16fe89e2f8b4e43c76766973087dc97c3db8e0dae01ad87c4f72931428ebcfd6216d010d010001	\\x7aab89e6ceb1cb1883626de21244c925c8f99fee97afb3a5e40226fb694803e6e635f2a2e4bd69aab478b4a8c39fe11bfff0140fa0d413bb266d1db0c8ac0f06	1666231772000000	1666836572000000	1729908572000000	1824516572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
86	\\xcc18218eeaacb7da84d74cc69827ddb9248729306e01760e3fca8016002807d2191ee36acc9dd22ccb6afe81caef5ee0e6cc5adec57828da06b2678f1ab945f0	1	0	\\x000000010000000000800003c07d2ef66a214c5e65bc965ef66ddbde30200e59fea3d9efb6b5c776e57a673358eebece9ffe0a3d5ed24d714bb7fb7d18d18115365440cd573642c8e4347d7f9fae45efda14ae885ef3bdaece2ef0aa87f0000be21c1997435a6a1e420af89e559fe5e1e6d18ed6802d3471b918cb50ec5f526d86ae9852e8e3d14413ec8037010001	\\xc13101c1c35bad8adc5feb12077e293dae4e4834bb43b30df6612eb156187282e0ad0bf48624ba39fb57aefcd4dc34bb11a8690e998e22f8808a475c7bfafe09	1663209272000000	1663814072000000	1726886072000000	1821494072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
87	\\xce40937d0604501245a3cc6ba0de1766fd1e5e6f679b09c2253d543bf7a2eb9e73b183c24e1129fc3a105eb4e65394bce4525bfc0c5388ad23fd93253e1ef205	1	0	\\x000000010000000000800003e433e726d758860c7887b2a7243f71057a24bca586ce9ef18acceb78e6af1107b96d7512e3d136975ae7f5799c5221a6ec031bd8b02c5a2521a383f5a6ce3b393075d4fcc0a2927a2043ed98d06e13727912d6485cef401ced7ebce9c9d945e753109bcfe22a2445fa2ce363c9b63cfa5c0e4d2f3c255229e80d0281f079c7f5010001	\\xd5fb77b37313e49e5f0d3d7e24c2502235362e1d2af9eb01d05d72730118060708549b76bfc3d23c276e9476e207a3bbd04f54f3d16d62a33ccad156f3b5fd06	1659582272000000	1660187072000000	1723259072000000	1817867072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xcf20577295ac1562b2afb6895131edb22f81828cb0b13a44019a7078b587ad63990830805a9f2de2933486186c852b25383c128b69661dce4ec3dcb076acb53c	1	0	\\x000000010000000000800003c4ed6548ed0444cb82f239ed7800c988074fa8b2d2190c99d24575e6c219e94670f8260b13361f2ba5161c868aec5cd31ddee2d9c2fd301a496651c470c71c5bd4af607d075772df3b5e93763f4a43df1489f09316bd29af2dbe26712aaefbe959c9ab55128c2c415d5d8c821c3d9c8fc461755048e7e89efc1c393d1e4d0713010001	\\x6a999c7b775f556d8e6e5240f490f0bc5e615d70ad6372a168dfbac80ca0cc2fe82df9342e0510fe1d6b0b7273a26fe2181f3ad7972a494d89d3fe3abe8fc400	1675903772000000	1676508572000000	1739580572000000	1834188572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
89	\\xd57471ea05ef15cac6ca85882d5cfb62bbf5505d3f919491528beb1dc482c450c5f3abc2c5c994ecf05ebc082f734e5376b581288b177009f3fa066add0f4abc	1	0	\\x000000010000000000800003af543aec5f78c898b9d2915b1a190a1a74093046c411ddc6e5177d8ddd5f286685e86d6d09ff50f817a6ecad6ae5e914be41940a903660bfe0599da4b979c9c5b341fd650d1376c3e65f03a53796434646ae8cac57573b5768ad46a5c51b317ba73610f8f6ecd2a9269f2f0934a6b30df96451a18dba6b4ce26c6348a1ab7bd1010001	\\x14bfe649cf228a3c2ded6df3f3ac4555ce5031fc296595238e59a6a7badb9191501f07a0c628d65610ea543fc82d6c0e6018a00af6e261be08fc2a9877fb8706	1650514772000000	1651119572000000	1714191572000000	1808799572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
90	\\xda346c0cd237faf0dda432c953411e180e46a461cd6bb9ee66ecd3155d171eb50af304833b73b56855f89e240a2604c3e473a606ca4f8072cbdedbba862c6a2a	1	0	\\x000000010000000000800003cc95ac2ed14d59285d270731a7c9251348dbbbc431892e60c2ed8762d911df03ad55cad0b3384107085d56dd719ea9135430a5c8b8aa69ce56d473f3fa42c7e7e3287218e2bc1072bdd6407399a7afa1338bcf9ac0d53d2a105c3cff8000d04da053012691b048035f3b95f1776fa17c15975ee6bea2a79ea458289d4c17490b010001	\\xd20e50f9a014b675b9d8fc4691b214906cfb3d3560b4cca4e8ca6e045145cef1f2c81535ce842f24a69e787f10821e7e9d25c122ca8d0f47bb5feefdda176505	1665627272000000	1666232072000000	1729304072000000	1823912072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
91	\\xdd946292fde6c230a3bd0dcfd880b2bb0b201e702c783b9f7994d3c28ca7ff2e34bfb641e9daf55832ffbb0df3c3f75c990999e12d12bc48ac08c80cbdbbacfa	1	0	\\x000000010000000000800003d95888ea0d6fc5e8e9983612b5b2325130bd39d43a24f1d5f362858d5093c348e16f2135fd4b2e4b4211a1f876376b779b6353a83ece6696c6698094632ac505d9257d79f000e6ef3962fdc0c27beee4206c604d8eeedc0a933c9d346eb308df6c1c5f085bde697ac4819d9c642023c25c564d10ceb2100af3a7b2c511d09d1d010001	\\xf03469914b3656a1df385564a548663b8abd426475e6686d5d712bc1fb5110b9ccd1b6a501e0c75784d73132a0417662ab19a681b3e428a0533d75698d029909	1650514772000000	1651119572000000	1714191572000000	1808799572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xdf20c54a7e107554acc02585e4c9f6370de5a26f98a6be9fb10ee44f2c80c0dd3277408df32aacd9da237fabbd9bc7450911c72e06cd5f73983e65723228cc86	1	0	\\x000000010000000000800003c65c8ac3ffea3b974e45bba05483963768297354f6200f297b19421aed78cc05fefd915dfa5014752053ce7021633779f95dac192e19a7351825a3dfddc5d0cae13e5da917ccaec571d25778c47aa3780390598998b0dd8771f2fddbc52fd51cd74450e6b68cc6f770ca548beb89ca4e447537a97a4ca57c0defbb45ab7d9f97010001	\\xc17abd5cc2834775b5262e92915977db2f9ff1966c043a3be35336dd1dec1546451b6ddb66ba671b4a5fe561b308e94840f8290730e546d2531644ae3a520306	1674090272000000	1674695072000000	1737767072000000	1832375072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
93	\\xe144f13a0cb715b45510c3f14b09998569983902754e595e5e7f90be51508645b524f68f05b92fba179b02e5ebb27159f03f7b251a3a434368628fd575839e65	1	0	\\x000000010000000000800003bb0c1dfe087127e69ef6a0544f551d4654c5ddabb11d9b9d2c93935759c1c671785959f415b5f6c830e4ebcf7b2c177f7c08f69cf79b8d46f76faa6ace7fe5d09ce65af5af2871168995048d4343b0a512908b6203266285731613bf10756e26c0442b1529dde22b00e051e22cd7ac4e21227dd23f31aea016897b3aba4bad17010001	\\x59ab51797219a4adcc87ddf274d8b1dd3b0704bcb3b3203e82bd8db9a8a6afc9d52ef3f7b3b72466b4d238185f6ad938e90c3e9bc38766b648d64657514c7e06	1657164272000000	1657769072000000	1720841072000000	1815449072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
94	\\xe14804c7cb5c9c5c95305ddf606d983bb59428a8d79601d7e508ce5276bd60662bde801aa44a8095fb8a4af1c1cf87509c2f0fbf0803d19eeef02926987afbdc	1	0	\\x0000000100000000008000039718b0342db1d60cfce22c15113f08655e50fb8b8f35b9a9b71bea289437ef1c2088043359c25365a836853675d5d2ba58100e5b866ba8187c012a571458d45016a56de4c6d51496958ec616e540d2d25a59a0b2474c7601a94a493af22d0584ff0881262b08bb9e340e8eaa3f947e72fc91e9aece8dcc7b0a63652b50aa8ba7010001	\\x9839701dcbe820c7e2beeed1d23130ff983b517e40ca8a9270a3c7d95b9a3d02ebd2866ac0e091eb2bb9fa6755bcbb2bc075a49de337bb971e2bfa907e15d007	1653537272000000	1654142072000000	1717214072000000	1811822072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
95	\\xe65840c6eeaeb67c899fa9d44f8899e72ef4de8e6db4912beec9320e551e568e6cb6b9950ba748a5d35b661fb80f01d83280878be17070fdb7b7353b7f2a31d0	1	0	\\x000000010000000000800003d6bf42775552672df8e00313468e7c1a9833840a4402cc8d4fa83d428a1defaf15b78adc61946235b2b763a60e601bb63674f00fd687e0e29c6f9629c4757df635394eed2b49bc4cfce0ff3ba755c2f13cb260172f6d72e6c4994edf1ed2943a695e622bb2651aa9c41a7cb2f389f4486241a5e5bbfce8d9bcd4333ff2c5f9d5010001	\\x178ef8a7795b46a2b3980e175a367a618b15cc30398c57aad98b299881f487fbf47a8f6bfb03184a71f8833d364e6977c66969a618fed310a63306bcd7098b07	1668045272000000	1668650072000000	1731722072000000	1826330072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xe8c088cd51efc5ad44e70a4b8b068f708f57e769ec98e4568ea3c37b1842ed11282b8433921e4847ab466ad296947dbca982024d652361391238c6c443064f35	1	0	\\x000000010000000000800003ca044f7d141312fb199aacd4a279d8730fc3b8b7f113b98de021fca8099fcf06649b3558f3f7a5b19a197249640e01c36fcf08a42097d74f15765e1b1e4472a43efce90c2b75ad831fced1eea1b70857f3b39bc84f3c503f423ea9325c3dd336d4952f256ceaa903df0a0ef7879b52e7996493febf782023625d353a42800a43010001	\\x2cbb0653e7db22f7670fbd53bd4d2485e5d5a54366400f72137f9686529fd212fa05723a47b746167f113043d45864347450d907213360127423a5f69f19360b	1652328272000000	1652933072000000	1716005072000000	1810613072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
97	\\xe8ec74ae7c5563604dfddd5f1f28bd038c538998588a084488a0717e0566620242286839d8d0f4d529310beb5a5cbb307a7af2caa752a3d49d8abb2aa5fc56e5	1	0	\\x000000010000000000800003be1de1fe7ec01eb0449656f3866047818fb3c79ddc21eaefaed50bf95112069a1a5aa72ce4c97466463c46ace908d365cf5896b815588fb0f6d53e2c678c1629e607af5fd58a52d2e35fd51429c8110288a42aa3cf32928974e3b670ff9a89001e86500b01b0f9f6f49cb553cd5f8db8b01ec819ce3bf0b749fb6b542085a581010001	\\xba61b5790441621651e64933ad630044874e2ccfbf043eb96a9e62a69b6abeed0fdc5fc9276915e928992d7c0b181c49c30c21b441327b6dca6f36dfa4b41903	1666836272000000	1667441072000000	1730513072000000	1825121072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
98	\\xe9b8544896abaa908daba380c02585f766030fd9e2fa2765d22e8f311cfdf594108f111dca73a7cb716d61be51422e8cc8a3186c634cde6110766ce13051d60d	1	0	\\x000000010000000000800003dc5623296f259b094726d17049166a9cf424e7d9f918fe4bf6b5db70b71d2fe7ccf3b248138b01748d027c2b2e7d5e6805f47a8eaf6e8c072c92e56f89795d8a1dddb450281006dc4b5eec76a2d949fb23438f295e90bbe4e4c178bd7b3d404fb5dbd1c775b340cdfe34925113cfad26f5af072e0a56a65210ca5fa43c90c79b010001	\\x525c023c7e9385fb280a9d00c011affd24173efd573179edc4da9151fa89b6905424179bcb6f97a8f65721e86653eca5f6740321e31f2013a0b7704e25ae1c03	1652328272000000	1652933072000000	1716005072000000	1810613072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
99	\\xeb90ec0e3f50c7e75ae34d7f3b9b094be6d47d3b0cf6b5eb30d68c6f3dc1165800a0de6173d2d1df3ca67aa71ee6911af432a014599df0520a034a1a58829719	1	0	\\x000000010000000000800003bf1e5d819a7afe2bb5212cc35f9bf1b6c59ae04b224d9ba623e6ac8381051822f7e1f9f8dd5a5f9752c6058d76da1cff91930ecb80e75094f83055b2ccd8e6ca5d44261d9e35d6ed2d2bf137ed23e386a4143351953a4544b89e7b3ca0208a0ff95e830312f2b699a8987bb688081f1ecabf4ec4f3add299a5992c836479b23f010001	\\x87aafe94c6875b013ef524aa8a973ed660e5a26c9c912e8cd04d11694e156df2bca9c727ef464060033872bc756e1fb46dfab305921aa5b636936c0746fc2604	1651723772000000	1652328572000000	1715400572000000	1810008572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
100	\\xebb83659c947136c214b7fcff5adb3fd0562428b3736c94f0576610fe0bdf43d5459be1c2da765fd24450badef13aaeb4c0b29175a6f23941321e3b7a1782502	1	0	\\x000000010000000000800003a32d3656a5a64eeccb23275a763ba1f7466c68254f710383a638f611473d7ec6b362996f99e77acd1f142e9c2fd0d152764ce41ef0988fe3d9ffcea2da3894a9fabb637d6eef4c020b31a5aa97e8f9e1bd99ed4798b349e576de6804ef3aedf294dd0a0bf8dcfdc612fb337944d91e902aeb5c752718da1563babbf57c06e19f010001	\\x7c48412184da1d160f7dfea28992201136a38e79bc80dbcbd5775a8f149b49cfc22ef3d5ef4e2216f3a0784dee9e2f5f7f12bf690c40e3c440eed4fd8b485505	1655955272000000	1656560072000000	1719632072000000	1814240072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
101	\\xed680b3ba81f729f4a5fd7220c1b29401db43362c7f773213eb61198e2261d04a633df9be1a617431bf8f31ec8e4b0814b663963de38f4fe4b6d9b80a967869a	1	0	\\x000000010000000000800003c095d0af3fcc68e63f264393d1175297ffaa6dd34ed4a09fc87b73bb5ea2722753fd3c583d12c455864dba20e80c933644ea6eaf0ee65a840d735474829a3d5753a6268883b5fd1241d0ea649fb250fc781b071455bea6ad1e2f2f71b8c821ccf650eba22f966716ef78624865e767de3c76d255b44aec57c1d658b65cb9cb1b010001	\\xedaa0a979241c7a89ad733c5f49aa4de13b3c385e111608b8ec973f3f220fe7b5e4fbdb95f689313da2b20104a41b5f00e73e70ab782e53833703d0d22ff420a	1658977772000000	1659582572000000	1722654572000000	1817262572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
102	\\xefa84077adbe19decc0ecde76deed5346f26d831e79c33cc55a345f8f5afca09ec0ae69f0ee376573529377a7e06d1dabd95f88c1612596a7527211c2ff3a4df	1	0	\\x000000010000000000800003cb536d5d7f958736c16f8711810ef8b35a2dae32a55c244934feb917c4b9a60c36f9c7be63acd3e96f742ae5fd075bf6814af6587bae9286052d78ed3300aecd0b858b8053ecc83a750f8edbe19b353fea4568970ddffb819c145b8a684f01690506d2775100415bab424d2096e0053a3bdfccf9e4dfc5ca39885502acb8043d010001	\\x18837c7a76170506242be7038a9cd0ce7cf13b0cb74fd214b06c45f2a69deb8bd5b7134b28b9ad267194f0a3345cc98d959453470105ba766dd8c8501e6e0109	1678926272000000	1679531072000000	1742603072000000	1837211072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
103	\\xf3a805803ceb1a6e10c41182944f745d33fd5d9f194f52ef414be2c4b086f0da36601beea7ed571f6579c3603fd932693a3aeb135f9ab8c711234ab36c161f77	1	0	\\x000000010000000000800003b4f50213ccee465f5bea714ad9c908849ff92fb95c42c9675dc3a22f9910eff709295a577fcf6f6f8466312e723856aa518eebe01e83532dbafbafd1c9172bfeeaa65a3bb0b52bc4bb81e8ec15717ca18d3b60d39b0384d53ead083b3c0bd0c10c00973409b8f57d9dc9234bd5a0bcc0c8fe82458efd6b52b65f195574933e55010001	\\xf5f2e07db03fae3ff8f309751165dbbdb02b22bc6ff29b756d8def05258e333e7b3a3220e78386d3edf61c72f6d12af9dd1a8a4427d749e77701e3be0e96a806	1677717272000000	1678322072000000	1741394072000000	1836002072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xf624983881f60abfed01b03d7fed5577ad0f55fd825c6c49ae68eb580922f51d32aa4770a027e037c94d54e7bf5ca607d6fec3d1a49d953f7aec02ebbfdddb87	1	0	\\x000000010000000000800003d933f5b54332e13df1638eee712b1a25ff1e68f8fdae1960aff9153d994a6fb6f1deb891b73dfab8b8972f3460a7a35f7641af255229ebdb0ff41877faa0d99e84bb9d35f5a70c308dae8ec156e9812f2b76c34dccf302c7b69f933151e403c1792cb0a17993949128c718a6ae4c6ab722149c9a3deba080cb1445b160946dc3010001	\\x9ee74cac7be5c539a38bd7875d9bb785bc015c1e42dc6e1035bdbb7f36e1a94233bded549184e048409279917fd566c4889fd03c7cd6908cd5286ec35c38dd07	1649305772000000	1649910572000000	1712982572000000	1807590572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
105	\\xfab46aeee362785041553c703107d8c689bef230ddf879591c5cce09db1cdcb73f166d5a588d3e5e1ac0ad8669e726df2da09680f1ded22743ae3e3f2747cd7f	1	0	\\x000000010000000000800003d57abadb40e71cc001302759ceac55fa673ea3028bacf70701450a4a8548ec033f6822b91b713c4e441b5d49aaab6ac344a53506ce271c2e58ded2a7958ce931ff77c7a41f674b3a232874dc5fd4d4b922d93a3368886db2620448d4f00f83100275af370965dd2ea91ea1cfa1a213d4ae58e738fce6a9238b8d47993ab9149b010001	\\xb73292d8dfeef123e8f845c5cdeb8471693c7e6a9c72f1fc3292ecf95add15d15c97b9236cfb2fe2b7934f630ddf952e7ec851b541234bca6a759ccc43b69607	1673485772000000	1674090572000000	1737162572000000	1831770572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
106	\\xfae0975a177c6ca5a97ed98bc5b4ffb620d02d368cd2e8b1d5a2b485a1254df62f617b3d4384e34c97a7748a1e8470dfa0e41fa22c7ba99bdc183334a1117382	1	0	\\x000000010000000000800003b9879114480f5b777bbb557e6bc0ba172d7a1095a5fe3cdf37ecb7498fd4bfb4633835b9a4a91c8457b95ac6f3829988728d5524a03eda5acae17bb99aa647ce3cee3dcfbd65ecb73d727b18ed4dcd76b219c22b36d0b3a6a2f83b1f8af699c74d79b58e470bb2253fa35b7801a1c778ab27b9121856d2b29a59f8e5c6d306d1010001	\\x92dac10d0715ae7306c5066556af3655836740bfaa29e5d07d6627adfc5493b964b5a3e2937c5dbb9eba7383340a160711c943bb93f925bbabd009526836a50b	1669858772000000	1670463572000000	1733535572000000	1828143572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
107	\\xfc10a65b9565576f7d18f10217f804d2da51dd542450367cf5cc683743eabf01dde442780b9522a345ba92004d46da2fef844f692b5c6bc68f48ba591d0ea104	1	0	\\x000000010000000000800003e7b54eb3ea95639215ac01486c0856952cb207073526708368179fdf6d56d8ae679d41c2c39596541cde0f3dcc45d2226cdc4f2e53c193286b29672077a9be35bc69204f526e9f689d73b6091cfdffaa555da2b88a0bb289e1e95ec32f954ed0381464ed8b050156632275ac5e4595c400abbe07bba9ea42ec01c14b9fd6044f010001	\\xb37bf509e4232dad513815f9a8389c30a1706032b6dcb2f24262ded2a33a4d1b600addd0d0ffc1ea94919e698c08198afd139242acdc0a3dec6364bcd1d00f01	1678321772000000	1678926572000000	1741998572000000	1836606572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
108	\\x01890dd4fbbc5410be1ea8ca5aa90c32e169ab55e0691a6bc35263980f8f42b3a977736f7cd034cac517765e8a11c24bee11483b1c1c3168cd0ded55051130a8	1	0	\\x000000010000000000800003d63eaff07e8f173262042ea723ccd00f16196c95d89ee86443519029d674903aed216b7393878e4c3f5609eea2082746944e885cde7db2df45890d678d630f427304bcd19c98222a166c760e377c84a71e5bd9d18d95ff5c37ae2d72eacd1206284427fd24dac8837c584083e63e88c5d23b15c0cb25b0693e9d5847f395603d010001	\\xe57e52704b36fc0d68ad2db28a630cf947a734f64bde641bf7382f510925716b7d6137f5e04edb943bcc1c491465ebb7454b8f167bbc8bd03f68baf2d4349c0e	1651119272000000	1651724072000000	1714796072000000	1809404072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
109	\\x0199ffbf5097f49fe3c5ebe3b94d14ba9bf9033d2902481100563c584b1a32f98dc3d6c67c7e62d3bd18c5521e6e17391f3be2f04badcab2940eb6c5d9e3b540	1	0	\\x000000010000000000800003b7d9ae578017fb95154fa3d2cfd047f1ac31dd7ebdbd546fb81c7fd1209206958513a1a9b2138c251a7dc2584c2552ec17ed1e52f670f54c525452ada33d6f9e9697bab17896387f83a55a3e164b870ef7865a2b0c05bc5bca724fbd6f59c819e8bf47c0c968bbe71ddd97c1507728b29dbee49566c5f3893d06d6f50909307d010001	\\x8cde909e77d3b8be7f42fe7bb889c295fd2d375a8ef09e262e638dc5f330d2bbb237426193e925e0df2efe674c3a645a342ffef1a825e693cfce3d4b40c3540e	1677112772000000	1677717572000000	1740789572000000	1835397572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
110	\\x0c650e0fbd625409fa7920e46760b1ad204ecd331e623ca3cf130a6c340a70a8b763e4583c64ebacfadcb6d208b6ebcbc2861e981c6d8ab80cf1089e0799bbab	1	0	\\x000000010000000000800003c608c7554665262fee463bc1c19b2ad60320c97c1ffd8681a59e74671e00b17752bed37c277483695353126a0b92232e5ee39107532a5e116463d8b1edf916071d4f6cd416d1764ecdde90de9499293397098cf08a727d1cb369f041af27de50a5fbcc04d5abf68a4934f880edc7eab1fd38a2f05422df34e3bd3ac30bdae721010001	\\xec720d3c461a92255a2930ac76465631f20c0c12196d0490617cc6472d3258815936ff5b5ef5c65099090fdfac05453da098c8c3326355759a8fb2ce9cb77e0d	1674090272000000	1674695072000000	1737767072000000	1832375072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
111	\\x106d75e0dcf2d17bdfad0d554336ca0a18d0fcc8dab8ea92eec9f2258a294fe22215dd2d7d30e45087fe469bae0c1938e6b65070a73f49929f3074fafb0cd2bf	1	0	\\x000000010000000000800003f2f7d46f6decf35a8196d41adf81ea602d856ad40fdf6839b46a45d21c10283eea0487294b69bf045c01bdec5925e4d221ed1796f8cdb4dcae71c8d98cdf5c759de4be86a588883e80e785a7b750d9d62e9608dfeaa87314d4569a0a0e1b9437b88c1fe3666fe473db9f499ae909e1b68b6b13d96b6e2d472238e59db581b69b010001	\\x59b16ed72aee07606e1b8f2e2f583288fe1bf0ba47283139248d53c2162da51f409d5786f35cee656ec000d001ee86fb99cc653a1cb757a48c57cfe1f86c3304	1651723772000000	1652328572000000	1715400572000000	1810008572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
112	\\x17198f5a22b682c1ca2ffe2279bf1ad049230af9967774d86297936a347af3a258c7b2dd07e30f8d02ceba3f478dd7faa3ca7834707da750b3fcfacd2b82799e	1	0	\\x000000010000000000800003a283ca3dfbfdde32535892b2ddb0b49ef7efcba754d7585a4c940d2c639026144dfa5d1a89c8cc134a9142bac2f6ff664bb94aaae29022d9f8ceeb22bc85bb4733005fa6d7ce0d2bdaab34476a02f2b1fe7f28faa5b5a86635580a4bc17e7cae9461464f30a3986271f4299070fe3e81a1b6c89963b1348e44223b88d8fb9345010001	\\xa6b666fcf06adeda1ea9c4e45af87564740e358100e88f1783f0aa79f5a24177f3f84fd0515d388362f6fb15bcf3e9e08fa756d232a01863c00b823650acc108	1666231772000000	1666836572000000	1729908572000000	1824516572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
113	\\x18bd62ff08af2eac8eccb14c42be141788011de8307f673ab3ce03d7fab44a7299314d8d375965d47f9c06192f1623f59a89a5883b4c3568921845013d63c2c1	1	0	\\x000000010000000000800003c1f910a56f42fd7e436af6384a3e2a2514c0ff18d519368a9c8b3bc584fa40e6ab0e87688a0ac31bad102c93ef01b0b7c9790ba76e27b3ab1f1e4f8e229b15f0ceb0d2cca316f15239d819f15bc75f269df1b61eb1115ee295db38d81faf95690e5dee7b781754e5bfb19e199d1c2507aca5b6ee1e240534d1a9057ff43fbd15010001	\\x6184bbd8da9962ed70233f035527c20ffa27a373a7a0436d5ab67c23134bf471ff4d0eaf0fba06144a003e412a7f27736eccdaf19dd59f23455dc488e0efd209	1664418272000000	1665023072000000	1728095072000000	1822703072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x1951c0f884bae1a79bca8c0808533f35970f269383fcf734004b295707915586e745a536ed22aee3ebcbf8669bd0c596075f1338610dcfe12e5b6283d7d7ef01	1	0	\\x000000010000000000800003bdc1908f1b917f2feb8f3542a8e0eb07c868a78a694437e5e3c6a7d1532d6b7a1eead36103032d4873e4ebb9a005ed212333f0349213dd84afb1cf85d7ae787d62db78256554e75d1de00d1e6dd19a842ee00a18f1a9e010b09153ac13f32c258e2acbba4a6d1df75bace2a67fe79564df028633047a463047010da0dfc7d72b010001	\\xf87018e2ea7bdd27453e468fcf7298e48d1e250ace31899d7a8fdcffa80d81e1d4b621c5ed0021c999b13e614de0553a7380658bd29296a896b88e2dbe083e0b	1658373272000000	1658978072000000	1722050072000000	1816658072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x19dd11d2bf5d2cbefa82d47aab6260ff8f232fa4d4b120c7211fddfa52b38a22c6ffd7e0c3df22f054818c09a67071eed4e24c7746d2ac508e3278a8c06008c4	1	0	\\x000000010000000000800003d04d70f069223ecfde619588758ae32a79bb216227a01ae59e0a60a449ba4a1f8e384cdf59bc3ca8357bb3edb7dba5ffc01def1e6551d875a1b3b53853c8afbd021dc4cf7472c1d7cd3b6cd61a6963ba3d36e9c43d982cdb84cbc00b805f8ed02e5cc99781719a460a1618440e34b922e7c1a20409525bbcc2f9fb1097370b71010001	\\x6270a831b2ee6f81c07d69c4742b5457983ed989f6a15688300860bb6a9c42a8e8ededb17730d477f4bfab967afde4fcc1f351bf97818628cae195d411100802	1665022772000000	1665627572000000	1728699572000000	1823307572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
116	\\x1b8147de94dcde4d08040908b05888461774eed206db8af2264d639b0c79793be62d969b5ca482cb470e501fddd899c10d25b3e7850adcae72bb235e8b62b4db	1	0	\\x000000010000000000800003c738125679b43589a8d28465891d7a3d850ea6ff27a3e2dcf774677f8ea0eef4258ab684c4d07bc153e24abe2502bfb60b143dc8bb6a265a1016ef8b4d4ef0e3841a04df6875294a75148e54654578f590faed74c4e50e8dd63f132ed7777e4826bc5790537e4f4610aa5d80521525678fbf2303bf8a5b329da46aaedf131739010001	\\x52705998a14d376b907f5bc737a32437b9b66c64876718bc141774fd79fce6adee3fa8ca46850a1105ea6b3373a4f6b42057fc59dacb9583783f1be4d0d42406	1652932772000000	1653537572000000	1716609572000000	1811217572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
117	\\x1e15be0e3cc62dd9d2c82c37ad4ba0b40d9c990211094dcd2bfc4f4eb2be18252ba2025b06d2aa946f9c7b962c4b3abaa3c26eb162407fec0b61232d29104d9c	1	0	\\x000000010000000000800003c39a5ba3ce96eda93134339d17890dfddbfd2d4df459bc27207b015044d1e1314024f7c76856e5f1063e9491163449e884309887a586feb6aa5a5fe2dff8c75f5cb37426b6f5214a68c17814629adf61efddaf4eee74d8de3f2f0230e17edce6b1eb9803adc405550e9bd8ba51f98a36c31daa6f3bfa55e28be5b80440bfd311010001	\\x55772c9403ee7a67e5e76eb0a1c1340c63e32a629a17cd79338b306e6ab09ed88372694edf8487847b4c07de6d7688f8ab09a9c9bcc1288bbc56b7fbdab12701	1655955272000000	1656560072000000	1719632072000000	1814240072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
118	\\x20592da97e49bee135c9c49b978d29c0903a8e0c9c62a0f13a76591b6b01e45c25aa061b2463c733fdd73aaa376cd53efa0705fe138e72224cdc0e59bbadc195	1	0	\\x000000010000000000800003d57f2e15755eead3c06eb27942f2daa8c833cbf631204e594a59cc3e239a0f735b59d91aa4d6d4318e7689eb5bb978b3af2dc39a1804ba79e2942e22a2c0ba56edca103f1c8d55360191c7352b0763ad2426c8a782b1d633540be873d843b475ebc43f69e997f44f6ab7cad28752e6dffd81be700c6dba311fbb687276466f1b010001	\\xd7423704b935c17118deaad4775c0f4aee79b76cc172da84fa4f11d13ebe7f09d2ee538078fafe5424f5bb00e20b0b9e79aaecad12f46914e550f94b602e3603	1652932772000000	1653537572000000	1716609572000000	1811217572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
119	\\x21d5e3235924bb7e40ea29aba07544e62121afdd78e48b8c908df1dee083ef1af455b1e8837bd4bdb4aca83c73e619c7db6e46bfac6bc82ee601baa063bedce9	1	0	\\x000000010000000000800003bf30e7e71c0c88b468f68a879ffefc4329842aa3243ab12507a5c301412c3726a11db47412b1de23a2719b5045bf4e6e8d8211029dc96529c26f9b9ba06e00721f15d1f71932cf15a2906d3bcd6812c51f7aeb88bded4392daf6c4138dd0061c337bae57504f73ad38802707f4d846df7e7a1ed81708eec9906677d36a883a63010001	\\x920f94059b31076bc883c2b1b122cccc934ae8837568edf2c82405c4116b19241c8079d6401338bb674f9067f4322b93048f6b05f0e48bf892bb18acd33eb00b	1663209272000000	1663814072000000	1726886072000000	1821494072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x25557f5dfc252f301afb97826a070a919ba3db4723bb3c9c18050184fb97d59744f7cc2cff798550cbab17b376ec66144dc39f29a0c222ce770cd986cd6a1d47	1	0	\\x000000010000000000800003a979f83414443ea918327b3b187b4ef45486736906da8531c6b50bff22754200e10b9b57003ff4c6279e2f92750f4bedf82a1d6c684453df7ca6943e23c19c28f9d6cc3326ddeec03440aff3e55c1d5c21e9fce95b0410db7f8b272f66d5a72702c66061486e3e191bbb39d109fc788d35aa68899ef493c33efab2c311520fd7010001	\\x59b10d869cc2467ffaf4b55ec511ce9b98f9a66cb3c353f8dc1ba0048bdcca5b06d2f5bbcec72523c380c96f8eacc1a0992c2f0a41019d1642d44ef6f6423b0d	1678926272000000	1679531072000000	1742603072000000	1837211072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
121	\\x2a79c745cf358bfbf9cd8a10124682bc98bbc67404868eb5cdc5206265b2b478f28bd7682b803ca1e3e2e8cc2f413f9f87e642b74e853572ad21244dbb98220b	1	0	\\x000000010000000000800003d843e77233cbbcfce4437f1f5e8f1adf59a035eda942d3ef76bda45d1f8d624d4d4401a7997cfa0f762740193d53ac8248ee6828137dd6e213bffb30c4cde69221bcb90c8815701627c3f14a77ac3c8259e5f18d7fc66bfbabdb6ff22be61f01acfb692902f8a6694cb0a57ea396097e67cc43c82be3ee9449032b191c1df195010001	\\xa9b9747e495855f8c1689222a06d7c625cf09a6d06c8760ea2223b8da14023b6c6dd3f279e1de4649d0e67d003f7e3d9cd2c8e5100da1ced8fbc58c184f70c0e	1658977772000000	1659582572000000	1722654572000000	1817262572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
122	\\x2f69d53b74069a6d7d49797663257639cee653cef8e563de5eeeb010a75d834145cc46fb29be2f02653f19a00e0b566559b1d941fb97c140a319d568de4cbe3d	1	0	\\x000000010000000000800003d8362cb395ce1394687068f12307c3033ca3525b7eac09f1f5c39703c2b16a671a7fa4e02f35008a22c486be5173fbecbafe7952d3ab51979f96c27dc933757cd8bea48dbc5f86afd046267f4f34ef670a82737b2b6fdbbe81f74d14651779ac76039f66646e61888c2e9d29f46230c978172a914e982cb53fe967a0306eeb47010001	\\xf6f3407a016d7c0a0e20cf3112fae3da736bbb4c1e8a7857bb9193508c0309727a1e9ad7e84addbfce6127473a4a2a64281ba804fde3589963823f8ce14ec50a	1661395772000000	1662000572000000	1725072572000000	1819680572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
123	\\x30b191c2499ffede47ac39d89c82f32bac89b841bce59b5de5f8d81f026fee71970f7d05a8b317ab259ca0f4621d485409981d476df80555ac2e2a75b50ea491	1	0	\\x000000010000000000800003c41180e5e3b2200ab9d68cdd4b496488a71f733fcb6926d59ec936d4fd936552b3fd9b060b7680a3b6289d43c4843bf2b8081b959000c7ee30aea99013038b081c0692b0d94aff8152d8c34de11d8bf1d387e8b67ee927c1487aa224a7c090552718c7182569ed959c5de8a1dbb264d876ea47d07b243d77d3def93dc370a937010001	\\x32d5d6d33b3b3062e2b8a68e6455ad98e19039044e10349a28ac55ec697d78858cb80a8288a1bdcc59d08259fbdb012fbab95bf3f75c93b63b206b4567726407	1654141772000000	1654746572000000	1717818572000000	1812426572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
124	\\x30e90bfad270b36870922d9c48b0816a7ecb89fe6ed22bc39e76f47b3de6e10f5ff5c64b0bcc18cc699a2e44b96c452f0bd0c0103779603cabe33f4b0a40cda9	1	0	\\x000000010000000000800003bdbb12f87efe6928d76e5e0a7f538b2730b818fb9a51a8240481c5b6e7d97c051bf537bac2db58ef14a092cb778f7040ec326de7757275b76165557a5000b7a5e229707ad1b963520829742ab92229d466c30da438ce091d06daf3cd00459f43a5f64bd144dfc13ad9bae2cf8cef1f6069a5bcc7096a29c076b12b13620f4ffb010001	\\xd151d2bbea34aa1b13799a5b3eb1dbf978e79147f4df642f56c48175cdf686a188b3ed4d54a0e611657bbaf1f1d6e4ae8e085c0b1c32d0e474d65ca67cb5d40f	1675903772000000	1676508572000000	1739580572000000	1834188572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
125	\\x34cd123368f070076bb66c70adc9cbb699f7804214699c6f23d1767a19525c4432f82d01fd23459a617696ccef80fb78d12cf5dadd8130f89e1227a174b60053	1	0	\\x000000010000000000800003d9842a01d1f97acef5d65bbea2f83ba243cf1f816c540e18048157364911a0f4fbe2e6ebac8d3e8cf1b4c7ed38103639a727ac08a2f10ea04633b9022de19cbfafda97beca1aa1f6910cc8b3deb1d95b3541717070d9d1c29879bb66241d42686fe9bc3eb733bf4b941e22740dd3caecfd49ce450d72e512f2c544c362846635010001	\\xccfb16e1f05b426a6614a9acf191835c73feb718af7b12cbc23d77b163804bc262747bc26fe5643840210967032e806ee8776d1743ad614a3ed717b9da416d0a	1678321772000000	1678926572000000	1741998572000000	1836606572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
126	\\x36f5a86df93db1d6febca72b04903522c2e8077f82908af592d67bb0dde69f654457af1ec54c9547cfa539d93de09d3b3f640d36b9f60a322fc63fd4f0d9438a	1	0	\\x000000010000000000800003c67b6e7feadb3e4e81d7d2a4d536d18c5f156b8ba36f9df7f2ca08887d3a108b8d56ecd90cdc6ed2731283101101e46c1e4b9782449b47de134a2da7aa4d69fe247a6bbd4412737eb349f8557c5f6720aac16961eae03882bbfed790ed72668d8ab8d804ef2dff10a30ec08e1120cee55712c34e0b7ff44b61e084f822e7794d010001	\\x27fd8da4f8283c14373c1676a38d9d6c5804b6d6a1831bb7c6e8692808b95d5bf73ccca1162133976ecaf56e14b4a3a4f1cc6e09c0d1db5dd8f5a98494168508	1672881272000000	1673486072000000	1736558072000000	1831166072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
127	\\x37f9b175a863934811722ca0c1401b8144ef750f7949708b075d7470a03c605163cb6e10fac7a4f32bc0155787399405a0c403f65073159c2be364b9d4df6b2e	1	0	\\x000000010000000000800003bac6d2c7e26182e761d204a08150594d0f1f9a36bbe6f6113e6480f8e71772afadcff1e91ae74ffee326ed51175574fcaa992d904dfa68528151cb41d6c9f0073d7c22fe26643abd4778665da818f0d68378885548b6bb43767284e94347285b296a5e3d71099f75a73b05012d2f700aeb7edc2edb69b75483dba40123df11a1010001	\\xd2711480089da2d6d258787dde85b3db50067aa7b01a2814651d323c41ac99160312567d03ba74d4879a0f6b6722030b5980cca8a8608be04b8f2b03a8f16003	1648701272000000	1649306072000000	1712378072000000	1806986072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
128	\\x378db66d72e103b65cdbc0126f5307928847f86ffdd48acafc64e124e97b4c55dbd5d9889c1de75da14f68747bf75f188b09e06585c91ba5b5dd403a617f2494	1	0	\\x000000010000000000800003c35b2009fa01d1a16a4361904ae0885f2bb4fd5ebba5cb8b25e34d778d2556ef2174377eeabd624e6730d861e023da83896870028e48d73eb60d98618a1d46f60435faa6c383bf9dbba7549ec79e621cf418d221d7940d8b92ab9fdaa42ebf2024f9808aceaefeab4cfde4da9cf7bbc5c0367f0ddeea91141c50500c0816f30f010001	\\xe0578260c4317eb413d25235690138ae550ace1ebaa57e23c6a3dfea732440bed4ef063542bc5b4b2dda2f10e347738940e5313c21f3a2b05c5403d240544b03	1649910272000000	1650515072000000	1713587072000000	1808195072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
129	\\x39e1aedd35e2d5daf92dd8d432a4ea9e54fa44d1e8f133a2b6a8b003f074ff37fd03302af3af4157bd8794fd8170d46f3d06a8f569c734c20a3d6412b331d7ca	1	0	\\x000000010000000000800003c80921ae6028c9d36da360f26cdc4963fd718f88866d56317e79fa9450a2f783d5d85dbd7def507f8f360c42cda589f58e84c96077315244b43ffcd6e01b558242315168194178b15689443ea66132b29ae5836847c325bc54eb96932206f1810f803da408be81c9426e9fa3e544c5470692a9012117ed57dcfb30a300ba836f010001	\\x312d602fdf85a3c3b4b9167600120c80cef7152b20dd7a8fa4f31af15f5158ee8d252d2ed4043bc246eb2dd0426392a65c33268a21cfade024daa306afaf9e0c	1671067772000000	1671672572000000	1734744572000000	1829352572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
130	\\x3a31a640124bda802904efe863f0707d39fb802a20901d6eddf4c6a55c6f2f67d10823933691abf400c2ab60479bf06b1bb7146a8e0c727db27c01e4966a18fd	1	0	\\x000000010000000000800003b25f38c48060a38b9eefb5eb4a9b6808ea26d50e8e03d8040dcac2ec7387080745e1274819ecb7c800a7db40af51b7bcb79a4eeb7fe801edd97e516736af5bf78adb18d20517edf5cf0e6422fd396ae78b35ebbc8cd6a26f6a06df77f423a42b56e72a9ba23a47fa15b9b1956936c7954e15ccf6baa6b63202543c77792fe61b010001	\\x7a8dce7f19bd9871c40739f66730fc8d49ff7e4e339e163cb9a38891c7a44db303cbef6704cf79f8aceec57b2ec36cca0b7cbf8f26a2753e64e339e3439fea04	1657768772000000	1658373572000000	1721445572000000	1816053572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x3b11f5a8e625dd5dc77a8a08c63b1f315b53f7d7da3a47cd82f9222db27efdac128cd8891ce2710bd31beb1c11a1d6618f6536a3296e528e9bb9f8e844afb60b	1	0	\\x000000010000000000800003a4dce8b4f750aa9e2e68eb697a08fba5b3836e3123e634d0f24d44da6a8a33aafdd62b40f5e570933b2dcc88b817441175fb3f6d4f79fb40d6a46ff0edf55175be7a5df1beec34e4ed9e0949218e5ed5c2841603f33ab66f03ceb738c2b71a6cd06448b9ecb621f503a2b6b9c7dde2c77e980c306b67f27c14f1a8008b3e8b3f010001	\\x4c96aeceaaeab578ad29a9148a5dd9b462f98f0184b7ef1deadb38206e5df2bd48d3d85e92e2324e239de506da90cf6635c2ea2502f091e070024aca6b09b30f	1676508272000000	1677113072000000	1740185072000000	1834793072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
132	\\x3f197b744c00719a5e31921d9e3aff7c4a4700d3deedab7e55960e1fb2e6bcba4499799ffad1f20bfe9477e15ee8a1380be91ce7405e2a0922165a873f523ba0	1	0	\\x000000010000000000800003b0fa525e3b0095c6dc460be0d117d9d58c26cbc90e50577025959f3477d07012330632bf40dbca207afd321e818eac48d97ef73106de1cfd6b54c64130de36e69170538097631cd4e230ff4fbf7a3cbeb77c2013066aac3787297582788d1f084e4c274549abab6c603da055a988ae0e237f6740df289d4dc0ea1196347c29c1010001	\\xf67d54b6f4bbe00a5c48b3ff06dc3aa070424b439fe7bea936b222e0c8bb543154d2079ced63f1914c9f951868607b03c639618a311a957d6a43059df7649109	1653537272000000	1654142072000000	1717214072000000	1811822072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
133	\\x40750eae98ff693b992319940e8ef6c66170dc5df52905a22b983701db4158dc3c00bd9450195c194939eceab8a7d46064b60bbf642d3ca12d8ac17f2479d84e	1	0	\\x000000010000000000800003dd9950039ac98bf945c662f2c7ff3a7748753681ab86a146e7910ee662d7656872fc10c7e6ea6d2951e6fffe3137337d021a714c03e987273d4cfedb06867e5a520591a7d3c3396ad42e14ee3043deef069bf5e6ade9473e777cd5780ff6bed515c9f726747fd1266ba398fc3627c04925a914721a042ebf3d87fecadf66e651010001	\\x4b927c237d51e7cc518a7bd10c114c8a261b9aea11a70157ee78f74b470ca9e3ca882c8bff2b0e5f8698079c460bee831ec189b2d7cbc91d210b71e4d9c0890e	1662604772000000	1663209572000000	1726281572000000	1820889572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
134	\\x424dae5d55a7acef778acdd932b6fc20e68173e5f2c0b867ee9fb72dfc8f0c21bd49e165328b48c4e0b63f513f22d6ce4a650a1419d39b128935719a5ef8a944	1	0	\\x000000010000000000800003ecacd2efad0dc99e23a3ad31539740fa122a10cc1abb080696f92e33d2afa5a4cf132e8d488d6be7cae5ae7b9c060bd9e734d01679ee08a0f1567d1d8954ed6d32ba5507bc468f445a1ab81f2f7f428ef587e089fe878277e949d22786ea989defb3fb61f0ff9f1af1d46832c78a1bb565b39b029527f42cf3c582abf72d3885010001	\\x7ed811e7836d7cbedc06ba6a0836610ce70e34dec7b41fb52409aa8fe4558a19a571ade98ec09645c26aac6966594cba505e9fa71e523ecac7d12076b773ee08	1676508272000000	1677113072000000	1740185072000000	1834793072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
135	\\x4679113a7325c320cd31df23f0cd10118351708b3931e4d892c80de2a55b04d1da29d7f86240b9d6243451bcb9e54019e430aed0b41d904a2a3f9191328bc438	1	0	\\x000000010000000000800003db2964dbcb92ffdae31ee347842e55ab72a6e7acee0f4e1ef2f10f32a2a03813fd7966bf5b108e1fdeb3d12561db317f8882aba4a530e51dde5c0de721f8bd2e84641baa34106ac58c10548f89b9b44be7b12e3c1b4486bdfa357fbc0c4452989cf9d18b73442e5913043823cbf48ea0aef3633b253a575a4f609a9447ba069d010001	\\x73eafcbd2d0740d06568163592ae1468960c9e2ac73e2406b846bbe1a8aef5c26a360dee4333e7575a388f914ff4a96544f9ff3f7d3f26c377e33eb7f1351707	1677112772000000	1677717572000000	1740789572000000	1835397572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
136	\\x46bdf533d0f59e45d5eb87bb88d8588819ece2385c868dc2ecf75cbafc7a235b34a5f01cf7e11a8a29cd63d5abf411eee8a911dd68ca6f004aadbce7226a9d4a	1	0	\\x000000010000000000800003aa7cecf5c225946e2aaec4b72c08df423a7f30fc103dc1f9776189524e1e73db7c335f57786165ef4336ba6774adf8c17e32729ecc47b4d5fa75e432d8669877147ae55df8f0e462237e48b9465cb7ecabe90b6b26d8cd6b727c1db732a0a6150b38adc91dd2a316aafbbd3cd12af19e7a91227b0f1a0eb84c298cffd1547c55010001	\\xd17f77b8d97bc41f00833634dcd95ebc7608b3761b7fe2f42eebe408edd3cc8d70df7b22a92837c259165b5af47d7f56b8e75f3b262eaf083ae23ef585e3610b	1666836272000000	1667441072000000	1730513072000000	1825121072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x48a145b098e3dbe158a33f5f2cc5a5cb7744e87f27509872a043984ccbfd82de9cec1aeffb9f2a8853f1bacf7a0bb885e85c23c3ee21c33080944edd5c1aa34c	1	0	\\x000000010000000000800003bcbe1723665c6999d29e133b28b3b91ff65ad1c78f73322d97894ab5316a886e0a22b325bf49a702a5d99bc34b46bb8860bdbee464319d442984b8cf5ab0ee7a71f2ab333b63ea680f26af7ec82f2261f271559d2c7bbe5a1c7817968ff299fc314316c529607bca4bd7784d1a7c0d8a02c30686ac030286b0a853dbbf559199010001	\\x993e87f260d9d43094df8c504541994ef742ccbbafb23146852eb367f5aff94e5700f1baee804ea3f3f2994f185c9f6c3c57a26e924a0ba2bacb2ea5c3ad0d01	1665627272000000	1666232072000000	1729304072000000	1823912072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
138	\\x4c49b90cad3a0da6c996d6322ee086cb1988d4a59803c5d0af73c7bcfb60820bac8e2bbe2316c29fc70a8e2271c505f21bf9fa47cb7f9b585393c080f48336a1	1	0	\\x000000010000000000800003b3892ac12e8c42d2519fb086cd31be7bfc14aee713cca168aa506421ef1885b9944af17afa2835e6412153ce9955ca6a186f157a6be97bc1b8b597bfa1e3d9669256f0dc74e0ed329f1e826d7c5ff3d2d70a4e7c8d10755214ad2b967a7d7a9ecc9376f234fa82ce18d44af7d6bcce46334c6cf02259852965ab15c14ef2de4f010001	\\xdd93fc194bdb2817f5936b8f4c7997a68288cdf640ca5378cab16ad5c2ee65c3d288633ec6a10bf16c8e5c329ec2c1c0ec1d76676b953c1015747f4121f93902	1648096772000000	1648701572000000	1711773572000000	1806381572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
139	\\x4ee1cd6beb40f24e1492e8c07fe0456ca47f19f6facbc761135917500e1133c1d436a73c0ce3a85936b1340a3fbc0904e5067c64c20990565197162a1416c9ee	1	0	\\x000000010000000000800003ca018f1c2c8c52740daae7fdd85359b7e5a0b593021298ed390d06eb135ee766a9be7874e79741c779789b5d6f19811a55138b196ebe4e22d5113fbeea81fdc1c2b669081234d01196f553e0009e4d780f4cfa84511611dd10227764bc11a20fb3ee11e904409a633066fd9f733b67cb428e508560fdbf21fe996e9e56465023010001	\\x8fc96975939bb71afded9061d09035b031a1814dc183c02f60edd33b75c6a3436659dc4004c85bed77d1b22df5af632cd0aa83feb031a891e00bdb209a601f0a	1655350772000000	1655955572000000	1719027572000000	1813635572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
140	\\x4f1d4e48f768615a2dc0157f2178794f6e905da88ce865e1bbda2bd0a48f4871290ef5234fb2ccf5a405a7643eb91c85335c30063ccb7ed02853f9db17ebda70	1	0	\\x000000010000000000800003c7488d90ff0880c7ba5eeb77c14c3b718613049ccb38596cb51d45347c3cd9be382b046f5b5ec2946d111f3f3fee7561e5582d6daacb950ca05be4c6d974f0864d8d84217ab38fb91edb1153393c784ffa02b1e00ec7c333e9ae4e076a121bd58fb92aac6b71801416f37e4782480804a524f1acb08becaee481d0ead355885f010001	\\x1d33f479435c4db434a4e989810a50476cd2641f2a147151aad27f16d546a38ba7a036cd2ee2dbdc634581002694d1aa000fb24f1353d4926317f3851133230b	1652932772000000	1653537572000000	1716609572000000	1811217572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
141	\\x554de1c18f4423566bb239f293f5d51b8755e4a68725e12cd190d984aa1d09c3643fb55a5be905fa5a77dcc7a24f0ea52cd13bdc5823f146eb3a8b9434b54d8a	1	0	\\x000000010000000000800003a2c163782305d78b5ced3f0a30991cdb687522a5f599c046a88a035bcee16d1138b127835a272125e42d45175401e4f65319df0b2f022a1c2a5cbd774fba271d5be2e73b1531ce0fe0c31687460eaccd1dbf56e22424444f2117029b8376c8541db7ea8d46aabd5bcf19a36f918228b9000b5052dfa1692efbb1ca7cf50e5555010001	\\x76723c3565d72a5bb81a5813abecf2b9b19e860b3dc4402b087898a0937f42dd2372c6d4edbb60f0013a0fc73abb09edec7e51e1cb4c4611c81712d627b4d109	1656559772000000	1657164572000000	1720236572000000	1814844572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x56717d00ec8f2845a128334e25404b7d035a4cc566653693055c890b872149fac5c10fa43931e33d1ec5f739a127fd324900369c7c72fee84ef1a5eb5b8e3dcb	1	0	\\x000000010000000000800003dcf2e12806e3035d769523dd126710dda4528d9d342f1f8219dbe8955ffdd4c729d664dfd7fcc2fe91b802c9d776ac841a672122ad248c62098b7af46f82824ba1d9e439dd42a0977dac8d2030ef1a557dc765a937984ca23698efe3d9eaa25119f55d0aad8cf457227984d952c61665c89e7c89f976516cac927058ef5a23e3010001	\\x9e22e6baada0154ac3cf3858e9d75aca172c12983435cea7f31899bd2bdb89b2a8f0e4c21b3c412e46e65666a09655242ca06f03855319fd17f9674597082703	1666836272000000	1667441072000000	1730513072000000	1825121072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
143	\\x59d9aec968d271e318a289890e282783eae75d50d3ac44934245412c81ab4417e20c1192f9e80c2056668be637e359cf7f7ad719d50e914412d29ef09eaf4b05	1	0	\\x000000010000000000800003b6d4d3ee61827585eff1eacacb610985cfee4338816afb1e762b138fcd68cf8ad157d5cfd9a95d9b25cd70e44d83ad52020a8d5ad4e7378c4763e95c5864b5b33937b67e84bdd9e9c6fd604c8e5bea26a0ef48cbcd8ddd742694176c3b812c5ad402702bfb3ac9ab67e781b3fd72b2bac7e1956fd63631eb60060d43902ee1fd010001	\\x18b3196ea34bcdc2cfeb6d6bb633369443117b6f40745d53f40fffd16cce50257d9dc01a7730e410eeeb385cbfc28e4c81abcb2e73fb577d0280a4d3bcbc5c09	1661395772000000	1662000572000000	1725072572000000	1819680572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
144	\\x5c65c8b3a895930d132f575390a189c978a3fc399a3ae18729872e55df4d7c3c090ee7d91fbafd753944ab54edcec11d05a732d201c48a540c1aa7e945d7b32c	1	0	\\x000000010000000000800003c5c0edc1a0585c6a2bf88ca202372c0d048ac15aff6fd025a75e7da865bec2f787e87bd0ce87e2e05677c671f9badc17f4eeb7357f8c303eb7db125fcae92889accd6d43df4f03c6b69cf10d99f1c5cdcfb9dc45bf86991ae57cb6885b9298014a1bfdd0dca508a10c5424509b6b07fe3767d444646a82a1c9e19efdfe745d11010001	\\x0b3340bd4b6e1428e4862a48b5730f12cb398dda322e5e4d597555f2129fc52a452f4458099b46067f41c2ea3a15dd51d242899fb6ad0bc5b7fe7c7f75b39f06	1667440772000000	1668045572000000	1731117572000000	1825725572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
145	\\x5cc5ed3cf4fd370429501f8b818567fdc262758262359e07bca71df45cd056d814aaf422943eabcd592b1cdbf0fce09f41b8cb8a8504b76bf57c543db65c57df	1	0	\\x000000010000000000800003bbd2e9d40bdd7a18005a327ebd6eae9f59f2d601fee370eb9c415b71a62fc82d747d89cd5b97a5377b59933904a7ae2a1ca509659480d81dfaac59f45e75caf5eaceb6826366146bd83469e0c8cfbd3d0cc1951090f9385515f04c635097a2e64f3ae14f3357328dd81de4731c59068a3281835177b44e64738c04bf6c03a1e3010001	\\x133133b4a3efa20c03159dcd2e128588866874f91f904a23426e502ab283d87e7d8a0c8e2edca42ce5cae5750508de2b18c9dbf9760ce46ba01f811dfb204807	1666231772000000	1666836572000000	1729908572000000	1824516572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
146	\\x64d54fc81d780a8ddc117e706a78b7bf83031bc85e7691b69a08bcec13adccad6f6bdf0034cae803be90a28ec7d7ba8c85382437d1449f9907313ddfd87ace55	1	0	\\x0000000100000000008000039bc8662de42e5113894320224637a845d7401cce5f34b29e9df03ce05df9ee32835da864e9d1aece20f5cf8fbc9c2ff0dbd8dedcb2a9678aa2eda63016f7971155b4cb7f65ac19cc2ded6c233160f11289f184c2d496425221e4322e59f5d37c6b8103108ebee16be645e5dfbb98442e277cc71a6784272781fc2c9c0c9e9ecf010001	\\x10ebd7e821a83af5807957c5ec31f0d914a372f419bdb01cbc1a7fd0ceb05b7618d12757653f57103e005b2b2388109588211f38dd68dfe85f36eb034cbcd50c	1651723772000000	1652328572000000	1715400572000000	1810008572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
147	\\x69a9ddc41f02b486474599126ae156fff6223ec684c860bab353c2fba0af3229cee99a12510080d41bd1dadbf5f52ce1202774b9d34cde781ae99fb1bf0ff8a6	1	0	\\x000000010000000000800003bedd241d5d1291277b694190d4bde3ce251d1e597bf42b888583b731c0ff424c6cd4f508616d77e17d8ae6b944080f934705ccea807d1ab84e18421004f6e617568e1078143cbbb42228a3c1423587aecbfc94d406562fd4169e090f7c4597b13776f2a599d55cb45e5acf876ab494f657bb281676f4449d4e8d138d51d7f285010001	\\xa1474e3e1180705619e3039096886bc9ea20630b74e7384ff5f9c5f42d72e313c9e3d1fa440ed9c42dea9fb1a366e9d348187657c1ae0c8d4222298cd840ac09	1674090272000000	1674695072000000	1737767072000000	1832375072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
148	\\x6ad59470f93acc447b8fedb60ad1442b8a0b343de68c260ad35cd9dee7a1393aca4b2ee5146a54127f599e99a15814bf6debfd4fb6ec27b2fd3d491fc1f3871e	1	0	\\x000000010000000000800003f6e8158f99e0fffcf3fcba7b2b71d373c9d556173dd419609885f018ab8276a38a270fcd00eb14dab0d0dd4b4ae08e7b401c31126407b04b54dee038b8791f50cd47e20242e9944e876cb59c695d7fa33290132992b37bd9c1dac75a9c0c1232cc3e98eb483dd945c92e65381976217846e49da2a42fdbf2d784e43511a06beb010001	\\x92b7da49e72256eb4290a19e579555ae5f39ab658fc175670cadc2a56461974bc65581b96d96ffc7a393d64cd7576015b603fe2da0580ce80b94fa03a51f4c0f	1676508272000000	1677113072000000	1740185072000000	1834793072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x6b498a717deee274006951b9865ab7ac6bbc2e7ea5ba70d2a1333d1fc8fdf0a719a5ca42b5c26a087913c5178484479577abe58667f9b9457951f7de1faafb4c	1	0	\\x000000010000000000800003e7ed7b3af1b73636a43e7b407a4dd9734a25b2509c60e0b274444f9ae676e2eef9d0c9947d7b68a5a7c940a92b2fb3c6238d072db22a21ab962748e384e778e1f72929d742cccd78019695a18ef4a3cb3eb09e263718142870642e3d4814c181aadbfb51663fd3ab256a8ed5806427228d40c71a84b3dcdc2712a4430c17e4bd010001	\\xca73b22b6ee4afe2f819c2631957ca73f16d46f9150e5df290646c1ae34aae3517dff32cd835787a09c1f71841272f69547fe3e2c2194ff7fa9c79f213050f05	1674090272000000	1674695072000000	1737767072000000	1832375072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x6c8555133259ca2463ac12ab804d7138839377ee0f4fbaeb8f243421b1cb6d0f60bde16501055ece8e6f5bf8258745972f7bd3560c9e23a7b95a257be0aa42a3	1	0	\\x000000010000000000800003dba4202ea86ef673cae74e0ae3df0a27022811f7fc02fe13555e2865fc29bc2ff7bcfc8df58810dd67c755a6b5fb117489fee635f08334c91af013832d93bf1e71031ad867ab26deb37c1279a9bcb542878b3183e3cb459631ee31f79671566ca87d968a4699784b264743c088564ae8bfb357de4213b5cfc0abd6a2d364a595010001	\\xd33844b3cb71ad3d9f79ddef91ae494f2d847436339158041b191d6274aa12e7c3e24aaeeed0dd6e9d40e7f484676700567ea21dc62317a10420693ecfc6c007	1671672272000000	1672277072000000	1735349072000000	1829957072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
151	\\x70d121551442e8e31a8912f84f142cc9df884cd0cec9cc317e5ae341e38769be6aae621db7d2550355b502c3ed14152d0ed7f802617007f9bd020c706675e27a	1	0	\\x000000010000000000800003b112f1cbc73dccbb550af2624a86f5aaaaf81cb836bdc2a8bba96aa8fe8a54db62149b872e839b6aad149e538a4c31e749134a0837b3759887af09dc0f96d44b3877a5a8fb0be07109ffab9aa6cb67f263b32037e34a4202cade8675afa458050a6d346ad5e5eb2bcb85cbd7ecdf1e887ab3ffd7ed8b54093403a84c8a2ece07010001	\\x7259ea5a5ef44aa8f6a5be0feeb93c0cb512cc229eba0674b3b3f930fe234cec0f8488d15e2d7bdab37471eb2b466ea8aa4d62b7c49dcde018bda084ac292c01	1678926272000000	1679531072000000	1742603072000000	1837211072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
152	\\x7219825110d04a3514e1e07f7a05fc2b5dcf2db3c587c9b5e2ce632e089a0cb93a4a5545591ec8c25ea08527c225eb8f456ffcf4cf0ae616f63060d62aedbb47	1	0	\\x00000001000000000080000396c266a12516951b6ab7b8aa287ea0d993deb9d0917d5bdb2e8667d2b133e4e9a596930714af52cd5e556534b709b335649dab662db3d8e0293fb4ca2b0b31cb219accee46c1a5ab200f53061f76a51ea15b9f184e8004bc7f136a113b0cb9470fc2f9d3d62f56068a4573f2886b090841f095353bc93582800ffc010a7e57d3010001	\\x60e633a4297fcda00ca078f0e78818066976e3f049fc126df4ff6e9a265f18b36306056e9053f7a732ae4a8e2db755792cfe7b344384cc3e13a300895dcd6000	1674694772000000	1675299572000000	1738371572000000	1832979572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x721144209be75ca5666c0086bf90f7232a5ee3f7d345eeed9f399af0516884eef4c254d0beb744a6b06d79c3b720b0ee912c776d59e37748e017261e1b7aa9e2	1	0	\\x0000000100000000008000039f1e48de031ed9ffdd3c49b5a66e1c1f209d2b1b1d61bae80638a183825777a193742356f41d311b90c35a262304eb1456ef2653d0539c42c7d577c7ffb027f556bff1f15c13c4650f4ec3d286ec55de0618ab2bda723062ab0ab22fa7fc90b3c79ca510f8b5e9a6609d3648a435a523174bbf1de2e9582cbda397dddc68744f010001	\\x15c603acc269d75621b22ad400df2848ee7c9f8ad8590d4a9f13e930b7bc9c289f416817c2a42985f1989a8794db456e37cd8677f4e82fa1b794a7f3e0b3a30a	1649305772000000	1649910572000000	1712982572000000	1807590572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
154	\\x76d1d0bba590952a5090a242b0e6cd1ff6bbafed9b90a1a5f0685ea324dc6774377983029f0423de60d6090199be6ffc884607d71346e12e4034732feab83199	1	0	\\x000000010000000000800003e9ba18c954390803421b7dbe0e8ceded7fd04e2fc57f85e28e81f6af0e484c4b9e0856ad5aa72a0bd478d670465c9e6ee3fff05a548ff6800a2fef276fa460ef0875dc68c8b88087fbbec7a58b566d60d00372f9f278392a47a8f25df5ca1ec8d098e04780f27d62b7ace9396796585a9900d61e1991ef79c8f21b3fa9c0fdd7010001	\\xb4f22b49124e5768e271823d0154889a71df72438f391ce4a246386417fac38c91024fd79cf1d77a9048aaa733cff022840558d0f211665d4de2a6243ba54d07	1669858772000000	1670463572000000	1733535572000000	1828143572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
155	\\x7845ceda33b459c44d2ef15dbe123dfd3e3be770dedcd45d6495b43c7c09ebc1865162b13d8776bd16dc08efb1bc5bffcac05d1eaf62983fee06f77c03949f8e	1	0	\\x000000010000000000800003b474e56fb943f0730f0ff9453068a349b3183190be40b52289cbe34fd98e4837ca6067b18e0eca48fb08a2b735a2430d55714fa6b0f9ade289e47a3bffb24d2b7b984b68571aaf3d92e57cc0df9ab84498725458d8ce5bf9c536650fa68b1a008d1cec25975ff8bf894155c917ce3f79427205967aaeb470755366696f7f8fb1010001	\\xfe2c5ece2926b50ccab140a7b39e6a8a4a0ead4025570669e537f69f6bcba496c2aa5c65ac6e82f1f25a4f2bb56e2067162c04b6ecf657b8ccb0c3a40aae1403	1677717272000000	1678322072000000	1741394072000000	1836002072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
156	\\x78c556f8eb83e60e44033d9d129af0a54dbdf261373ef55b22fcc5472f8ee843ac66411162818223c843ce356d9b4dd3dbe9a925aaa2b1115e86deb62a278ce6	1	0	\\x000000010000000000800003e4e5d658a9cebdb498886c0cefd6624ecdd30b899443ff3c384b113b4baeaf30fb09921f9a770a9792a993a8e47ba146aa12481094fcfa21ce5cce714149a05a778689650be3634da1ec6f85db52d8bf115472447295ab4b06ddd2e1f3704a5314fa73892d3de43604903e12908d2c1d4a9a0bfb9582bfa87e15dbc4a2f90063010001	\\x01aba11ab1b0947e05f5a7df7aa2aeb18958db349c55f179a13c9e8482a5d64c97f12de1c1366daa78777872c6d0d561caff53d0c5daff3e87b932bc930b5501	1658373272000000	1658978072000000	1722050072000000	1816658072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
157	\\x7d2dc2496b3ab33c0fe1186b97096227a352259f22714e9cfef731a4347b3a387671a5f6369aa497cbcb87c7844be2bb8c9f7e2a791975649f66d17ce0537eff	1	0	\\x000000010000000000800003d1315e7a470df364199aecbc05c73f2b6fe915f9b8e6f252a299df907264f99915fdca8b17c3bd1448183c0c57e1586373996cdde2202c18cfd9b434e1661aa25925fb0c33f4b9e2aee086036503ca9dfcbb2225367e23b193b1a14eff677a100314f36db63e5494f0aec052594fda9f2c1ccf3dd3ad007ed828c4999c6d6f35010001	\\x837a6eb9494aafd649694fc4decd312afea2942a366a9f9ab2b4c7f569c3dfbdecb6e22f531663d216d6973120b1b8b31cce428c56bcc41fd09df511b80c3801	1654746272000000	1655351072000000	1718423072000000	1813031072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x80edf598760b24700f47f1bebb7230035f4fd67ef80b200074c6f8e7ea59301b76ccd3cc82806ae6d59244ef4c9ca4087fbbdf1982be302840ebbe06763a4866	1	0	\\x000000010000000000800003d46db815285f4c49d2712df8c618816f0eca9776e3d3dfa66e1a8acd35897237578f9a1a1ed9737917fa88cadb8db085cbc81196125f4c7c3be6d120923498fdd2a009679997318f5635a518e61a20b69f0d72ccc32031ba9d2782e13c396d08475519f5f3ead7fd74bdbcfd6897939b5884b03d1e7c104acd8afe2a2e38bfeb010001	\\xef2d5889d6692e38f6cc42c29415c2ec14d58d389eb208ee5d40962fda7b10cee9cd1ab4763c708245b18cc615f9d2248df94036ab5a85be7991b93c40baf903	1658977772000000	1659582572000000	1722654572000000	1817262572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
159	\\x86693f2c4dd872777835cb1fdfee70155e54154f14232b7bb1c5277777d39437b48e2bbe87d8095e50e30501e8cdc048838402889c5fa7fbc34bd9c6e0c34aa6	1	0	\\x000000010000000000800003d878bebcd576a19268e985382b1229e0193ffd1daf0d7ccf7176c6d8d2162f702c21c41a0ebc076e4e21b4ce76445efe5e0b4c5a908e238bb378fb057bdbc066f84f8f57fe9ab0dd8544149b8f3478f10dff72858d889a961c23bb80eb0ced23a3f078866a9e6910743859d1120e57c000e88fc11dd56a98a8236e895eb58015010001	\\x4b74984dc3d8419cbb54fbd0b3e9ad2b1deec823847eff7a06722338e29875b1bda1f069647ef8a02475ded36a8327d18b6cacfe1010936e0447ebd591c0950d	1647492272000000	1648097072000000	1711169072000000	1805777072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
160	\\x8c61b4e91470ddb5447af0e1cccf8df525766c7974b835baf68fd122bc50150cba186e2552a9318897913a1ee88531683f5f711ad1e9e089e675709bcaac7ef9	1	0	\\x000000010000000000800003b14c160f86ebd4da03a03f26b624df0dc942bbf2f2a6c79ff03434f8f78fd3db8e88c001cbbe27218cf342ea81931fd4340043a49f17a4489682e6c13e4bc15074c6866941535193ba6852c4ed4be57d555296cb09beeace3e82347e01f462ea2aa3c12c53d7226db912e22dc7cc73e9deff10babbfc333de901ec6728d3ca2d010001	\\x2d02fb75ef30afdd33acfea5fab9c02cd0106851613fda809e6d8f9352f359ff7f4aebdc9f801b5a166d85402828ff5c42167640b9c4161f824511f5884a590a	1655350772000000	1655955572000000	1719027572000000	1813635572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
161	\\x9055c3f920164467aa113bb21fe4e566807cfce9fdfb5bf40b2bceae85b20cb8587e050c455a70fd61b30e2a9c9642ba7eeea72a8c457d6edf6c4bd7099b0abd	1	0	\\x000000010000000000800003e6cadeb5249d787e2b385e9b335dc88455d7643e2852a79d5d297116dba6eabf2a75f5c0067755a38f7b53574d5ecd5d53e67eb16e37593e4c5a6ca8e17a8561ec07ac5889eb1bf751bf8784e18cb32ccef914b1c2a0a33c30fdd29c9bfba79a8e05f1bc2730f9e074f7fd78b61257ea68401dd70e8f0194b7d15bcb3d47488d010001	\\x066152d74914282737b39ba96d9f063c0ff237400ff9a3ea1ce1f4c29d67edea5a8240947f8000ea97ff19639c545a9e5e32be39687d31eeaa5fa50645b7030e	1674694772000000	1675299572000000	1738371572000000	1832979572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
162	\\x90a1dbe8f62fc96f4ce7ba59f7fcc350dec192ac77e3b2aa2669eb9f77723610b5fd1ca24177bda83653b01ad67a2e8f16be4a9588795c8861e7a45bf5722dc6	1	0	\\x000000010000000000800003cb41cc7df4219c8bf1d59be3a8ff27f0c5e2675e87745e015bad2a27655c107507cba2df1e734284d9bf0bdd53eee12ef341ee7a8b8f38847f9db290b18a0e6b51a680df00f74fd8336356c626a9908785d07a7e490c8ca9bc46927997b9bbea89cc537cdf509f85d3901b15cb156885b8db7a7f95a2fdcc1b0799d5cb6b7853010001	\\x055a189d1c5dbdc4f132d5e2aa37ec4b35ea9cb1429c41a57a6cae5ff5ab3bc95b10c68d3d87ad173abcea03779798bf49f7b8753a1d70a4c6cd7a4be56fc20f	1661395772000000	1662000572000000	1725072572000000	1819680572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
163	\\x90c1e2f5ab483938d90b91c877143bee004b5746c9ca0486a13240805c5df2df1692154b3e39be4ea3a4c8c5bd8845145500b4452953421ef310f59244754516	1	0	\\x000000010000000000800003f4c69f13f147ec39c2f21fc46aedb60d35f71399e406845e1e9259c55cca3b8404f34126114be5924271c8fe6305bb010fce952df4b97e42e8bf6cf9e114be857131832bb0337efb694903f70434a8133153c7cd52b8ecd3dfa9e020dc86198afb50dec1971d7fd833410474ca88af0df847e6af366d4f33698b475c63705c39010001	\\x84c6887413b3b750346c23e4ea418921060ae2b464d0e311a1de69d962e714f20c244261864dc3b0e426b6f647de839c16cd07385ef42319e82b4ff8e4c38e00	1669254272000000	1669859072000000	1732931072000000	1827539072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
164	\\x910d3cd74e03e4abf98425fbcea9e927baede433c04e255ea55d58f89bca5aca5b8aa5eb3569cc9911ea465a5bedef1664699f793014b159d0ed12ccb8db274a	1	0	\\x000000010000000000800003c68adaedd88cf97311aa31f6f4667ff5b57bbe3dd298121f02d99245c5d7294687662f78246045dbdef62577f3c9fb52de7275701ff3b6e2c1fb5c87be898e5f813b2e974c0c20e5a3fe3cb1654cdf411461f79f0bd4d28815db1a5970ccd7138f8874fe7a4470b866403f240bc9ff2bcc695a21a190fcffa1a0f70ffbee9281010001	\\x20e5ef566eca9b2e185f0099821f77a8bb2feaa79e7c91ad8444afe3bd0ba600aa31c31880965b05039c5037fe41acdf4f1eaf0f93f160239bd22209fb002209	1672881272000000	1673486072000000	1736558072000000	1831166072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
165	\\x9e61ed4ebb8f27b4f137e427da48a5e513e45dddd7391b20a62c4ddfca9c3b3b0fc6d011da6a8e105ea31c1a6e5d029482ff7e1aeaaedb141469cb2998da8dd7	1	0	\\x000000010000000000800003c7302ddcc1864424f7b3a0007a6b8549b9635e184737bd922052f84239ca51b7cf0e3efe9d2a4dd8755f751d098537cc093b7f4aecdc48d4680fba5283f7c174573c339d54daf13946713e7285b00b96b0574957329b0f84e3ef4dec80f0151d1e27ffe910ab34f1162fa7dbe6723b2523d3a6638eba2d90f92c50dfd8898721010001	\\xbf4e4e1c45e82e5792dc9180ce7a9e25c91f2621283826bba87e82fd8e71f6552bdf35fb857584eded9ebe2ef75d1c6c319ef45f9c34a6a9c9dd0c672ae09a04	1648701272000000	1649306072000000	1712378072000000	1806986072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
166	\\xa5396cc4ff75c0ad2b20d5b8f7f24edaebf89bad4420986f2546d27548221e3a770f80ff0fd3dbb684c6bcf395fba1a27b6dcb407e998f8f4da830b300e6d1ac	1	0	\\x000000010000000000800003d8ea55ccf5ef315a63951eaef969a0441ca6a29ea054897318e968730e73d01feefcbf93f69a1ddd7b84eedf3ae3a33d5e0d780546e18b33de0f7b58d5df677224741cfbd4730b2531f1cbc260185765165a15a6d324569aecffa78eb077007d0214d490aa4a472f5b701ec4d047ade582f1608087ce3843037a9c961f4829d1010001	\\xc7e29a5b984d820ed72ba7cad229c47032fc9edb257435caa28d2f6c7dca28b34d7821a61b7d58a5c3528b874d4d18c51f5161c42c2f53eb0f9975e5f6a86709	1660791272000000	1661396072000000	1724468072000000	1819076072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
167	\\xa935da434914ba6272c98b172a7f949528eeb0e2f96019867228d7573a37f7ee8d4884758d81a37ff4c36cc6969dd99b337f100cf153ffe5f06aa65193c59f80	1	0	\\x000000010000000000800003d67cdcc04f37a2596c49810676ac80f291fefb512d84a24554dbc68978c5f667ec9ac47c762ce2a4f6acedc9293f44ca05649c8860efced5593bb6c594b3c558f657e7ed1c0f831eaa87ed4e6d0cdf5ebd845bbfda9a5905e8285334718d37a554f9000977c9e432f3f72d5aadcd1dc60589af1885f2ae9addda5a033a58f569010001	\\x5212373e10c1f279f9967d7f057b057f8c124518926c76377fa9e47a6f25f512d72b4444fa4688b4e5352b32554c0e6dd95c11c68888e083f15369d607611207	1667440772000000	1668045572000000	1731117572000000	1825725572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
168	\\xae3d0e86c0fbe3ed270d12e82338ae9445789a0cb4e476b7091744ee056da8efe204920c33fbdd9787beef5ac27d498a5dff527b7892219a7d2f895fc2087145	1	0	\\x000000010000000000800003b774f49a15ff8cf11c4ceddd13e47c7e51f09f9cd6289dc0d937661e18d74e26874438eb1d508d269b6e72ec023bcfa3a596ea5f3038b1ead353c6c91083b5ffb6c70853d4b1b2e8ef78e158fef00b7c1fbba74ba8885071f26dc860f0245bb252e680a87c0ad4d4c7d03948d6703411389c255a08a472dfb2399f7c28411bf9010001	\\x25aec46d07b801b3ffea0d0b0929e76f57d4d354c42a940134c903eacae53f18168470b669538e9664a4c7aae0e9268f256fe16752e0077a0a0a0161b5faad02	1668649772000000	1669254572000000	1732326572000000	1826934572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
169	\\xb09150bc1785ca48b862ec56da8059554e1337878552839233ed01f9e5538d54bdbb226a90728cb56914cc10faca3169779159e9f36a3d2e1089f1303f426dda	1	0	\\x000000010000000000800003d1a0ffa559a708575a5dce685da5e55f005be85945df57a164ef3027b0b35a4d4ae32b36072546090c1ec9305455555f73beb85f335383eaf6ef487d20322c54a709962c381a0bdecf9e9475a3fe2ab700432732673d876445ec63cf4aa778e5fdd45c5e3f9977d78287d8022b9e1e1fcd0522f0730892ea5efcfb8078b82709010001	\\x82ab1c69ec1b1b7cb4487c9ef244d3d623eda65e69b8ab728cea3b1a17f32e2e9b99bb9d1a91cdf7f44bf5b2db0056f4ae7824153c603ec90144b297cbae930b	1662000272000000	1662605072000000	1725677072000000	1820285072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
170	\\xb6c190429ae76e5e5867d47a6e6a81cfcdd006c3a29025a460327d0d30b99a42878825dc6049f7c841af60757e30155c66b941efcbfe3f2667c0b46fec75bed5	1	0	\\x000000010000000000800003b4f53d9bc91edb1cd0ec278e5bbb046b73d81db2f551b646a0057be256f41f1233d46bad75067de106046317d7b577cd214c3e33e7cb080a184982e8449afb74e1f35af3f309a691d7badd1ad496a22f8c71a6f5b917229dad5c3afa04d9f0859faf6d21e2b8952b0b65d1196f4a8fae27b6db7feea0cb3b6b7024a0d0c0f45f010001	\\x6c86904e778406a86bb5dd72ef1bf4579050d1cfcab30b854328122ffd13627357c2907f546a13596822e3f4afbb6f59a3680e89957299cb98eca5a4c5425a07	1658373272000000	1658978072000000	1722050072000000	1816658072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
171	\\xb7c9a731809755dc96834ac35ad9e9a08dbe9da3177dd09d1918dcfcf6f74aed4722573e592222fe31a63b37eb5ddb35f8ec32f93f0ab3cfd4a8be4e3bb4a874	1	0	\\x000000010000000000800003dcc5dc8db3e4dd1c229f1d136dbbc7e5792bb6f891c2fbcf0571516427fd06ad862dadfadc9c735b701824410f41459ebf591d9444580f57256de70e6514a90d29b1262a0acc1e9b34bb48277199d1abc65f14ca9d26c431bfe750c70f9578cbe8162205744dde0d20a57465bad4d9a623be01eaec14892cfd6152cd1583876d010001	\\xf088c0e720ea24ce96306ee00c570dfb3315a1d3b3c3db985dd047a0d7b4c844f15dd3335391d87302c9e2eba6631acd524f33e857c76ac0c8c8328c360a9d07	1647492272000000	1648097072000000	1711169072000000	1805777072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
172	\\xb7f5822e110bde50ef6829ac0d6314c655a3c384352e603343cd3ca6526e9c101998c363e84180ebba51f76f84bb4b424ea8e687176ec15ea1d48dae31ca9913	1	0	\\x000000010000000000800003e3b765b6bc74a0c153110de4281d53fbbd666eefe737060c8f048462588695024cd4a12f0716b3596cf2a5c5ff457e4753bee5c0c12de1519634546e085add865c22eb6e538cf8b4c941c91ec7ad0dc1d0d20026943c89da9ed4e5ca18699eadedc240f12e7ccc66314e88cd05418d0f57d9379280776f0050ef93d107f3baeb010001	\\x78de7037d4015c895f289bf918255c20dc57e8fe3ac9e48b6077374d66c6f59950e6cacad5152baaef6d552fef6a2798a71d7a8b3044e62377633edc4432c305	1653537272000000	1654142072000000	1717214072000000	1811822072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
173	\\xbb853fb75fdf7774a707b4ed7035514dfe2b2ea1ffaef95a26d8342bf136bdedc2817651e11dd142fb3ba6e5ce381fb1ac12d1f69f20e612b862549f63b8f900	1	0	\\x000000010000000000800003d723c732e78409d1ab75d1521ac53c254483b0da5ca3967f6c2433d6f1b3d36a250589b4b7879f257f7e2a2c49c66c167f553b9138e57e4bc6a529b26d4908abcf8592bdc20476b33f5bc8577ce575a653c01a82210e6abd24b1736765661e75c24d1e71d950e320827a2a84826c103603efa268dc3dd56741c455de62fb440d010001	\\xd1fe3ed54bd7f0db0f395f956a926c8c68806d845650b662b9e12115de1469019c11269d3a962e02bc4f376805d9f04a526b5599097c0e5eb958f0e622582803	1661395772000000	1662000572000000	1725072572000000	1819680572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
174	\\xc149d302eaf3b87f08bfacf9cf10684bde5a65d718f153fb6d405ac19d2b57e4dd5104c02ea191f2f902cdc4cc228bd692882295530792f05107a32fa4bd056d	1	0	\\x000000010000000000800003bec2350bc4cdd3f31d6e39fff4b9dbfd9f9145d5beefe2816b4b0bd0a57572041bad974275a10da6f52ab0203492443f58210b7142292a8d215395530a6d5fc9d232a29e201ea942fa8d89011febfae8d347dc8e7c9ec5bb045d103f13bd66e7092750ed5439e78de317a045b3e58f73bacb47f78daa5a2ab784513b5c6c00a7010001	\\xdb980756a773bd4273a82c77b63a75b703f37eed6a3ab81bf466a91a3c4b98c60fb20fa942d45e26ed8fb763fb98fe6bddb68671cabbb31b4f39fc5019d2310e	1672881272000000	1673486072000000	1736558072000000	1831166072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
175	\\xc32198e4f02a443281192dffe6b13e37af536cbd891d40272ae19242e3c8ebc3eafea90a4fe72749ce1d40bcec47faea92cf6804b5ec97669959e7782628bd9e	1	0	\\x000000010000000000800003ca0482eb435826b830945e4043dd527b259c2ab318387b74b595704cb7c550efdfe1f2005476e6b0031f3188fb400d3c2585aadb69761f4c11c48cdbc32428fe13e54b66d9e8f638e5381d8427e30f6d035e10252231bc18eb31cc02770f51b0cfa250602ba31479991adfcdfaf66ed689d415e3a43ea97a7104358fc61d038b010001	\\x280d7c1134aab6898e2923bba0a2117665a0b73a4c8eb52a8f19b3dd1b7d919debae1eab16b919cf75dda76e20d7a8afc5014cc0ec0cd04fa7b535956f963c0d	1660791272000000	1661396072000000	1724468072000000	1819076072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
176	\\xc37d8e35548766dc01cdc58f7fe56f78be23779063d2689feed175cd3a7da585d1685631bb50fe8d1619ad99b0659ce29c0790e2490a0c9154fe50bcbcf10566	1	0	\\x000000010000000000800003ce7e48e747cf1c07eed07a3b62f4457ebb1217d55272d73bc94803a67ba6f91937f3d90d140b21629c5fb7e24a79c22c7149ee060e166b52b458ca61750527e58c18b9b9e78f840bed0dc603b53a14e40593a66b9e86e39b739c351ab6c3796943fd72471b8d26a2bec178fa1f0e579ce14befaabdd387c493536f6a5d785559010001	\\x12127a930ad82f26c89f5735523fd7dd130b54645f88ad62721ba374039f2746dd790c0535aa2e61a04fe95647e8c1a4646b71115a623f26adf1959ede808600	1654746272000000	1655351072000000	1718423072000000	1813031072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\xc7c55adc6b77cf44d9284dba5c26f6b07cfd5d77f7f404aad938f4724ea1b2e5c103ef14c90daeb2be3ba6b0b06939bae005223be74bed75da21d46101d50e0f	1	0	\\x0000000100000000008000039382c5155f28c142d4ed492e76b55489966d520fc43c9e9b2c94cba536f245db16365891744f94c79e20297945e7cea546068a5bea7733fee351ac73a5cd3d1a7a92bcbdcb196cfd17d1a3201d2aaed1d49fd2623e1c7efbae2fb8167ecc8e28ed49fc449b42908fe860ccafae5630a6718b15a986b68466a779157e72452baf010001	\\x30fc52971dfbafd74245b4dbaef0ae65d0582f7cf0f28ef1096209691bc75d778c68fd3b8a72d0c524d73615f73f29d8c5aeb8e19b2abc14d6753818f8a87a0b	1663813772000000	1664418572000000	1727490572000000	1822098572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
178	\\xc9fdb82af45b8abc0b288f9473e031ea6104c300f4dff08da8ce523a540d7f057013e159db012d0294f6140292940fa721303922253109164fdc4a69de822336	1	0	\\x000000010000000000800003c69c1a1e611439711e59e3fb3f3a0a218afd90371cfec0c12019eb172b30fff796f01982d536b177e327413d3693109eee49ffe121d65ae67f5d0eb550d55391f16df4b730dea8128f809bc1166a8421dbeb8204b37851f725491b7056cf4b1252feba87936f5143f33fcf932980cd64c0525ad3c4fd36bdc762fb9b36fe60e9010001	\\x479972628d65c9255678ce0aaf570acfdbb945710e55a8f7150f9dfd52ba0b65b3901ce49d936ea0c6d579cca5ddb09d92bcb44ac062519819c93e34ca382e0b	1649305772000000	1649910572000000	1712982572000000	1807590572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
179	\\xcae5499e331f1e1f49f7193e512bed55249bb1a2bf981ecdd8e8b86ccd148bf7f58e32fd3ca6789dfd46fcd50a0e722fd8b8c091ede97d38ba520fea22d1f226	1	0	\\x000000010000000000800003ac5ec8065eba4272c193c834667fa3034a39c8e2c5411a5375c73842da400426c0b14751c9aa441663864379e097cb3e2d64efc26b5d66ad7c48df03a9635a2b8a7bed85bb476105b4942de57418745ef614062d62d23c8d5524e3795627e05e080d2c16dc445cd2f5a6ac0aac0d7768c40010b38966e93ecf9ad102820ad6f3010001	\\x07990355a4b144b76d3eac05858f9c3df91e2b2cc2b9636a1010c1a9801b578bc96107445e0751022c8e7f572365da0b12aa71c6dea837af1e81a2d4386c4c0b	1647492272000000	1648097072000000	1711169072000000	1805777072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
180	\\xcbe904509b8695b09cff784fd305c9849e0810da0d91637531664086551c07b3acb759034c8a01153020ac51b6c7468dcaa6151751b96178145bb1fd558b1721	1	0	\\x000000010000000000800003ce93359cc22de7f54e346aa1a328d78e41e57a1dcd4d48db56f3637c9f04f8717ccdaf7ea86800da2f7edc82b7322220edefa1a7ae21f5a9984f5cb3975517140fcbd21856a9ab7b584c8226ba380b05cdaa579cb6975668bb208f304e6670b8db98a187d6b1e5943ce2bcc356c00e34a683dfd09f4f5fb06b601bbc1554ffaf010001	\\xc3891b984a0d179a4edc0ae6f03a23e03f16520a4855283531ef594e8f3ac53d5a9e26ce06440a0e1d7523323d72f5682c107e1f2a7099e645e6b6ac3e0e5e08	1658977772000000	1659582572000000	1722654572000000	1817262572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
181	\\xcd614508bdc7bad8568a80a7221282ec3003821b3b9c6d4051f0b59d8a6f74fd02f03595062fcb0d70c09ed78d798e2e84343811bd5813b555ce6774cfdbebc4	1	0	\\x000000010000000000800003eaa8c7914403b487487b7631575711039419ea318d18b0ac01974cd1a4bcc1ee66028dbfb1b17bfa282042e809af49649e98ff4f7843a21f5c8b3704123ff52466ec0580bd3aa1630ad8ebdc5c551ca9855da4c25ec0bd622ef5dcf1fdb8fbe3148013441e1120d1a562f57c082a0084b5aa219e187942f406df404b85192ee9010001	\\x994579ac52d051204a60d3cdebc7e773b47da99d45ab304b8a9fad0ec9882487ba6642db583a6c37fc503cef7a15e15ba1fcf735f4b0f91680ba084f47539f03	1672881272000000	1673486072000000	1736558072000000	1831166072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
182	\\xcd6dde07663c62c71692477dd247c2c65e8b142e8f3563e8be73f7a0d012c0ec7087f8d43cae516cd7ef81640394763f43d2e4006b8440e238482267c37d773e	1	0	\\x000000010000000000800003de9cb94ceabd2deefebcb0d4161d5b07cf657ff2ee1b992df92c7fb422e288185a677698a33b7e2c274434a0bad14d09b7d7229e48bdc22207b997740615e9665bd6a6ddfaa4a6f6699955bca01100a3237687c20273efb311801cc230a168501f9dc638a9f29f70f7534846a5e904eceef96c9f6339a7fc4dedb7a9381d9571010001	\\xe42d878a781a15a2aea6fe794a109bbc70ac86f15992fc980466da043b8112c8fd0e88c379def3d83ae48ea41f1dc4c7fb12048d00d129cb7b742a04e70adb0c	1656559772000000	1657164572000000	1720236572000000	1814844572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
183	\\xd761b9c94a26bbb543162d3cc1d777ff58af46557f9e9a10e48604aab41bbf8eff1030c5393cb8cd5c1421b212ed8b26ecb5f8d916ace1a516e604b84b96a857	1	0	\\x000000010000000000800003a57959637c94aedc4e9fcc3ab7df04f230c446643862f08d8e3ea634f41e5858b8a7b9046bf39acaad49d62f55b247af1eb759d6d21f96943924286fbc82864d3db4ce0ca8ec87d5a87ca620675f0d8dcc13e641abc6d27e4412d3e7e2fa68dec5545517b6944c821b26473c88b441291ca5823355de5ef49f122b33144e49ff010001	\\x597ea130a0ff7f0c4496e2e375e58c5e5e940c69f9c0d6eb28666c2d5667f4bb1dbe53c6a33eba9fcb857e2c64d4c6936d3d9d9ff763316d366e383aa4e8710a	1670463272000000	1671068072000000	1734140072000000	1828748072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
184	\\xdb4d24e86fa7f598195e6ed13977a01265cb84e683c2dfa9e143cba4373d3b3fbfc7eed24acd2eab83dc5f61f9ccbcd9154e285b7f2c895d5190588fe945e2a3	1	0	\\x000000010000000000800003d8fdf73e9e99d2b231c7cc7f79cf9e9c0c13b116e8fa95fef12fd8ca8be6315a18b5409873551d27c14f11a09d1a006f2a9a9916453e20f7d4911e365a34e2d52fe561bddcd2c75d7fef89b75faf07f0da6fa3f07cbdf0af6b536e20088d6734d4bfe9613b69bdeeba9deabe86bdd10150cb654d3750b8ccb8082e449e0e4739010001	\\xc2aa6d422571e994ebc267c6b5cb69495a638f44ab50819b3eb2fdec403f40f15b37c3d183952fb4740891dec18f5a37cbb82182b6f456d1733c147c2f7a030a	1654141772000000	1654746572000000	1717818572000000	1812426572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xdcdd72dde4d6731fa8e1d8d2c1a2e75281ab3606b3480a4fe0ffafc7aaecdbe6f82432496eb2e9d63348de261f356737d9898b28b711749cafa5547902a74072	1	0	\\x000000010000000000800003aedd1b925754a429eaf09bcbdcedad1b5a9b538efdb15fb2b7ea1e6f5dcd40cabbe4a94fddbd68730832b613942041f296ba68c60d3e9033f0617bb2023e25aa6407a6a6348400a949159c7e9ec2ee8d523c71ccd18583146da62858c6761e54b0e2435eb5e61e6959dc05ca4689656bee58dfd0b6e60a363c90f8bbbd711a0f010001	\\x7c4ec3d0ab34140e4f23919e1a70805a6269a9a3b00aefc66fd83a920f0e1f61c80a89a0129ff6defb4a79ca5be9c08f33af88a924f2651c379c1dd24a874601	1665627272000000	1666232072000000	1729304072000000	1823912072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xe11560c3b49744327faccf627ad82568ee6ec5e5771e5918192963393b0ee909c4673bf8ce4f894f98fc2cbf82172b0ee4a9a256252fe585848eb7e3ff3cf218	1	0	\\x000000010000000000800003c462138cacf594a852d3cd867794045296579da9b42744326b1cf35582a8862ecca5365047ceca1dcb670334822619445382b800294f83e4235e69725dc9dec42317209bb2e2458a00517a3d658fc0c9969a35fd41515c49f2f5d72a93c65ed032eaa09ec786fe2a481b5d57a9e88c891892a7cd4d87acb697259eefb4bdc271010001	\\xa7814b3844f3932f0b31b96e1c5342ff5c4682b22f11b4ba97384e404a58b554101d2ef8a2fcfc6b60b8176b630f247b9741c3751c24de14b3d3a7766ab32905	1655955272000000	1656560072000000	1719632072000000	1814240072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
187	\\xe37119c480c45abd750c557bee6e34c1089a5bdb927320050d3450c99e868a2315fe9656f5a0e921fb44efb0365c3edccc206dca57bbf1a3d9098e976385e9ae	1	0	\\x0000000100000000008000039744694b440e42e2e23b3e69522a7e1ac68a6ea9476cae7458201d433b9200fdfeb934b7f1cecf94773b9c188628662cdd74d4ece45dd8f28da869e9a45c3b8aa66131567e81cbf2313ab1060097a34c2a7ff02186e68a0a0e10418097e460a83aa51069db2b677f3c69adb3f5ffe4c70c43b803f4e0aa5acca150665ab9b2e5010001	\\x23d416f951d3f29bfc69ad4fe82d4b551fd89eb03bc30b42012f9c5f844eabae57b4075424635ffa75bc51b6d012db96ed5f5b104b3b022da32b10843807fb02	1664418272000000	1665023072000000	1728095072000000	1822703072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
188	\\xe69dff90a3d0955bf00e5d06cdb706ec7da74703f5c9b75256db8ad6fb5cc439b3e2a20a2d513dae57bff0d2145900cb31f7975e1906b8cc2153140f415958a8	1	0	\\x0000000100000000008000039e34348811e858d78f150ab9f74d0ac7b1b8819f45b0433afc2f91d1999b25e455b0437aaae4eb26e859e6580bfabc3c23ab6ecfe8ed0556add0837681574c3bd36a895271135759423e23e751cd02551b5e374490cf47c8c04504a7783191dedefc27ca4ca01cf80fd4431770cfe69e6d9175ec7428a611c1dcc378c4bfc5ad010001	\\x93c3bdbe4fa1456dec3421834ba8b524eaafdcd0631da9ee839eac531abf74dfb4029ad307107534cc6eff08e4d5b3db50e910c4de2f2790af76b1ebfff43805	1670463272000000	1671068072000000	1734140072000000	1828748072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
189	\\xec85ee78095a8431488159c2f96fbb4b86d9f67b69de2e6fe72847ff075d1097cf59302253d2e3799de9abbdb3b729328b6f717d08609a5b004543eb9bc273a5	1	0	\\x000000010000000000800003d049d5dedf55aaaf490cb6db376ade127045cbdeffc221bf46490820fd8e69a29f3d69ad54dd58d6eb3791f91a13fcf3a1f2e864bde464def46eb84fcb818a65ca1a687048233e9ab81f385afa2c088cc606792d992a254e167bb02bfb9dd34899ca95d6685f6c70e414de0b3938454a0be57cb650e5126aa136a5eec4235191010001	\\xd7472a521a74cbde8ae74600902751c206a2f9489841cb787592e4e26ec86d14938c1e9a782ce632bb85068361d0a22514021af6fbfaead46629c57a56930b08	1668649772000000	1669254572000000	1732326572000000	1826934572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
190	\\xef99ba1a8b58ee4f0da4031a8bd8c23ef9e3d4087e31a2e7d06337d28d21f4a1c1efa75192671cfd831d01312205bb727852b5790345ddfe131ff4da0e1a04ce	1	0	\\x000000010000000000800003d3dea556b64a16903267f698d9936fb3b15f8557dc9dd3f64da993fc5f0dbdb459fbae726b84955f8c638653547e9076c3466fea3a8d41edab1182c6df977828a2f45b2a27de666ced94084f48d11c5f6e7702259c01658aaf972db6c2a9383987bb54e3d1fa578bcf62c2748b9a652bffca652c0863c384ad3e8e5074af477d010001	\\xf157f474a11c9925e2972d535002b87d8f076e729f05d9266d83357dad6855288f9acd6fe96ab10e68b69ad723c33fc6b67bf6c7be5304e157f18da475f0be08	1666231772000000	1666836572000000	1729908572000000	1824516572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
191	\\xf195f0ef41b4cd705018745ace5a314a206918a02d7bbaf50f2884af3e9be60d69f40583f2ff8c2aaae58184ea167cf6e0812d4b0620f5da75e6b655ac6b71f0	1	0	\\x000000010000000000800003b9d657511289516910efc955143b1abd0395f4c5180a64baa17b494f7ec722091f3aa51d3bc355fdbaa57d38ed0b2cd51ac78822ca17d1f0eddbb07d998e76d20a75b4e547469b346700f6d09b76698ad32da540573b35f31cfbe3d5f0045aebd6b269ac94e09f544cbd4758ff55aeefe4899e6e1c05bcec1cda27797e73c001010001	\\x6efd65e6970dc7fe5d18708630a6cd8134e126932c423dd3f4f6dcbefd3da58bf3a32e7c1e24524cda8ac389804a115dee62ad5bfe50ac7fbf3b590a080f3907	1676508272000000	1677113072000000	1740185072000000	1834793072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
192	\\xf121d6c648fb9d9d0ab53db7885315721d34e3f21fb0ca8f44a59b84b2d5f686c4df11620bb0112714e15744f0292d36f3199ff31457777d5be75011c88814f3	1	0	\\x000000010000000000800003cb955a7e94cb5ccfebda4769e06a32d3ad0adb9be7ea8a30e98641a3c840f0348161ec1f0f2883cb5965bd7d6c374afa8452c4935544df4a1db2d2fd676f99cf5e7576e33bd045a236ca47faa203beaea0ec54d839fee3d926273d8f538785e53d0cfd11e1e4fd41e54adeac0dea3b9ed67717f868543b319c74840fa8987729010001	\\x463203628913e5da83cd4530a47a02415f9d9cf9b7ef87ebfa751223a82e0d8434b1b664e38e27309af91ff89fe6ea0c9d5167db3cec8d8cb64766b8a138cd06	1661395772000000	1662000572000000	1725072572000000	1819680572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
193	\\xf11de33ebc0c064c046698d8376a19585ac9fb8a8cd713a7822b15192eaed67df56d713355794fc0a84b8b5ef4d88eb6c4081c151e2062580a2451589ab9655d	1	0	\\x000000010000000000800003d617e33b0f2d4eccd9a6a667670109f63ac9e437421a3e2a8c7abc104c0ea71479b2427c3e7d8c3bf368ae93c30b925b0380f11f8a98c690121058a64bb9480f7271bbb03bb2c5d54a58778378d78a9d3d3e5f86267afc605863a9400a412d4450cc0cac761640e0e372d444dd3ea40d5c4a6565b738713f899af390171d7ecd010001	\\x70a29ce69704160dd6361865e0622354e7eaf62ffef681c4bc7159b1713d50505f44df2bc5fcfcd65141f853afa8eef9e6388095ce9ab432a95fa18e0fbf7105	1660791272000000	1661396072000000	1724468072000000	1819076072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
194	\\xf3d5dccc5aa02c531d63fc956f31b2c970a61deea77fd74c3be83aa222c2894c80ee374ff298656f5fbfec206f789824f8a1040061607f94fac55045fcc4c73e	1	0	\\x000000010000000000800003c640ec5bd951e42098dd77953f33462454e1117cf97898da2b5cf51dc73762d0ff297a4b8059407cf5642fbde54b2c3bb64570864134a30eadde6e4320a7fcf43d2cf047843a9761e23af9258978fc8ca8a4ce0e464bfd93f00272645fbb91b03ae76f726650c70304edd32b94f3060cc347bf0858c41e390d979dc3c0034c21010001	\\x704450c31483c1c883d3f906124c3f5c81cbf71aac74ab78b253181c0bb554ab476929e69b4af49a984919d0312c3ecc800687a94d496f45930f5b3dd6f90506	1660791272000000	1661396072000000	1724468072000000	1819076072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
195	\\xf7cd0fedf917b71d46266c368f9d5e30985ccabe0f57c59151d255448f3a6943362a08206e770fdc7bf100389299523abc835dde2ce84f96fbc10f170a6b398e	1	0	\\x000000010000000000800003b6408aeb252d72743d787af0de32357a93916db9a27cad62319c2dcbe42437f8db8b5e498075d3e3196eb1f1613a467991cfd99032eda7cdb2fd2b8fd1ee3a3b60925bd244affae249d775979bf443a14617be6a0fe9f7982a0a9745cbb77984530fafb4dbbdf416db5779453d186cdf24f478293362e90732162cba59e5e379010001	\\xb0002ef791784c7be0730ba3bac372a568f735eb5e21129b0065c3e2f9f9b57d39eb93396e9b481031163f9afe2e18bfbb900dc3abed290ff928e98087c1b30c	1671672272000000	1672277072000000	1735349072000000	1829957072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
196	\\xf715e302799cb769043dbd81f3ed968070989aab68be95fd53e2d71a9cfc47e042c95163b1cd47542ca91218dc5efc81423dfbabefbf12032290257d7fad4a44	1	0	\\x000000010000000000800003cf0f148774f317c5db4591c39b9636bf4ad6310fd28ed5a01ff25c4d37c82f9ef3bd29772e36afa0ad9abafde65507a83ee4c9a1ff7c926a7f0b28dcf442f0633a95132ac933eb46bfe951fa386c2780f9354ce3979863f3531763bf034568f1ee000b05800fc38071d275c7619ee77f4dd130eb84a661862e6518b3485e0cb3010001	\\xaa9bfbd5068f019fa48f4e978e4543fae185d87fe0b505d9131206e409aaf8f240e8ea34cf24a79451172b1f9c4255ff99d44e655c1999951997d6bf71c8e40a	1666231772000000	1666836572000000	1729908572000000	1824516572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
197	\\xf8d9635d74ef30bb802b58b3b6afb7425eebec648203a85331921003f7f97e4d0b22f60a43edf872e8d1aabeae07c07b4ebb898e6eee0f090a38e3d540ca4778	1	0	\\x000000010000000000800003caa4715e148bcdb1de505dd2941bdecea616474477af8f5f900e2fe3b6bf65863f646ce0ae47d1a0439999bc74229464975da69e861ed44944773a08edcf848a9be2ad796187c9948938cc1c8a14e9ef97ca9974c867bb96c852b8ab76b53f2292fdbfd9e1ac1e75be2a0b4a2bace358da666a8e85e2acd53a4a1fedd8e6eea3010001	\\x703d340d6531083dc73ce5c678ba77838717381a4d8d3ffb104436b05eff442cd46472d5e21139ed15ab678d39aed586552a292cdabfd5b2440e468530fb6a00	1670463272000000	1671068072000000	1734140072000000	1828748072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xfa011af9c7499887ec4c59012e049e589baf2730f7fe3736a2a98d541b508bb881ebb7aa423abd1b007b83c35360fcea7ea4769f0ab4cb2b4ba7bac44c72856d	1	0	\\x000000010000000000800003fc584461070cdeec799cc016d7612e3d2683ea8d064b81b1965b3d0f3d229a4f4ac6565b0c3015937473f647b0d4485c5bbc2b32e398128d04541dbf1996803b2c8ac740ce6a77251c66d98f4c95d9a810b43f2da0c6e0b72f506427b48a8e635976cefe49c37e9fc3561513d0af0e4832d0af31a809e70efab5926e149d80a5010001	\\xa4e7e76b97a3502a64c85be2b91df47048ce9ddec418e29f0377c211e30583112648d2f1eee3963b46d17bbea23e84b6e3ad86683a16f5555a3ae604d68c3f0b	1675299272000000	1675904072000000	1738976072000000	1833584072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xfb05a2ce7be409239138d6de849b6f38eb756efd213815ddf607fdc6bc03d1a9a4487e8b3b748cb78109d4d3597ad2a9f915cb161fcd24793f18e1112c4bdc07	1	0	\\x000000010000000000800003b0829db63ccb74ffa273bf8aa3ab806cd72c0bb3a84a1dbaeec64621f0100fb283857e381dfcb2663167c8f8fc6dca67f6bed0e880d0d87b57c4d95f77ceef6f3973f880035a8a6e9824fc83e4d83173fbc78ed188937bcb9a07969c4014d196ff5d15db31755b5f63f653ec2b216f2aa5bdee66e3a419584ee7858435b1fe49010001	\\x28dec8f7b4a9cd6df923b5de3b81eb69597b37bae95bdbca11d83203cda07559f922d96c1eaa96eaa8068686e68af6b4bab1bf5bea3c768571658c8800cf1a08	1672276772000000	1672881572000000	1735953572000000	1830561572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
200	\\xfc0548638da2dba6a16aa5a91c0d2d49028e8431d84e704fbab8b547236cfdf97effedce079f7c99d66e3d2c5a7a9b6537026b63fa41afec1b5c008a2c3bf368	1	0	\\x000000010000000000800003c28d0acf5f166ab13d4772e8fb5d4df0f067283c1fda57830d410989dcccb0b4813c1ecad650cff1416d6ec68743c8ff7e4a82adc2155e3980a6c3054eddfc18e0d4d00942a655243bebba3c9ce6bd18207fa8349cb0e2c74c5930b67bab25488ae7d2ba69ce5da78ad720d95c55c99fd3403b8a32cb0d3c27b01adc974dda9f010001	\\x3ea22d6461f310dd61b464c6776183d90541845cce5007608331bdda42e63abcbac6f2958f866be817400f8aed2bf3bbc3b0fd75717121d3721b90370e812e03	1660186772000000	1660791572000000	1723863572000000	1818471572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
201	\\xfd11da5d52cc5f51bffff96cbf6dbd07d57460512624b12d016af04f09fd35d3b08da521c76eb40b30806889dab4396633f08653584ec0e47efa2085e5cf7d71	1	0	\\x000000010000000000800003c53555426cdafbf31b61a261a156af35e55a3c81bb567033907fb65e5b8be870e840a8b4d231cc8700f935b06799beb022f2199c15231cfb51366ae572d195323ef4c6d61c39dc357a0c1137a58b66ee287ac09071bdd4f5cc056e2503e16855e809dea698ddc65a355a48cdeab2c60d146df60dc6532ad53a946ba5cacd0f6d010001	\\x48355dd37c96e9150966423d9a3eeb339e972d763707080a67996e528063fd2f596a5810c5c886997f935aa52756265b45b14b83af8e5123fefaef3ffe1c3d0b	1672276772000000	1672881572000000	1735953572000000	1830561572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
202	\\x012a596b47ee6d57e105a66daacd4d70a8c9f86725544b0829fdf9c6ff029a38a09b7272a8b492656ff338420abb934813f45784a297b4b3a13d5b06422dae71	1	0	\\x000000010000000000800003c523762760688e3b1c0406fb06f34effa7dd494a7e9923ea3569aa367c2ee323c09bb6dd6670491a64f12263cd5d0276cc9a2ead3a456060ae2e48b6fdfb606d03348c288257303d8f4832c9c4f7acecd244c90c8741fc787ce2bcf8d7f5861912ad70fbc493f830a1a0a2fe102035516a29b73daa07dbd8011f7f4702a36c0f010001	\\xb0bb43679667f0f528849799a56077b7028a14ed72320464906cfac193201ee3ea218ef88de8fc55c5aba791c59e3f0264fb6a4bec1fd2ee65b9dd1375f66e06	1675299272000000	1675904072000000	1738976072000000	1833584072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
203	\\x0382653a20aa542c24a9369a9095da98ccf7a083516b58a43711b251b95ceb32b9c108edc14a039bff1f6e1c2ae2948708703daf86ebb82887150ff8d5629521	1	0	\\x000000010000000000800003dfd69b9ca6a381041f6b7f93dabd02ade9c34916e6fbdd2b78841ff2f1796fb9c44fb15e889baa48a9fd0d77311bd934e6c2cdcd51a85d6983990e86cd62a5b5115ec8f854c4238fbbfa1626df73f78f4ae86fe824e8a04b1dadcc69215f261dea7b3cb7c413ac1871316164eab84dc16a258963ec68d9343765ab8b370aa8d5010001	\\x7ca0d217932e7d950e07a8e7d8114ca8a692ed6d03037ff6a0e037ee543ee463e2f8694cf222a5ce25e94e8059d88ce9cb4c6b4686027525396e9f0dbc8d6306	1658373272000000	1658978072000000	1722050072000000	1816658072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
204	\\x044af99268e222c7416bf98517430349d103186e125fdd062d77bec808712ba6f94eec249ebd122161a4c46ee183fa0936861ec329101809ceda0b45c0b8fc91	1	0	\\x000000010000000000800003c5c58d67fb99f8c5b1576c554cdb5547f5561c8ac765c6c79dd4436ea84cd440beedbabe53f0316dd3d5f2320716d3bc36fcf5f2cdc45b9ed38a8888df54e973cc1e8ac9212e2acde4b5d9d8be469da70f7f589729c7eeef1873bad6b9bd0b969a29bdb332653ca5cc26329d522fbd1056f25c572f59e25a685276a61059b22b010001	\\xbff95163486b45de126475ee4b7892b5d60769406a54207bc0ca90497e6cef2af21792f129cd2b1c0af632bc5e9f85dbabff0bb83cf5108df5e8df75ea7a3603	1671672272000000	1672277072000000	1735349072000000	1829957072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
205	\\x070aa4b2a183365530bc6e88d1af68f0095cac17dcb44d76bacf6689e7967fb146f2fe3d104ecacb5e826547320bdf276ee8d0458cac210d9f8f41c0cc579030	1	0	\\x000000010000000000800003f1790073f4da4e5f4c30b70eefa5764a53322e4369f1d769af78d5afb4228a7d7a8377c393235ea3ced4906949792af90df3a8dc0a1455f1660285957c0c0517056efd958913196d8d3bbe68ef0f86b0079313fab806bac43f99548f3522cc98c36f2cc6e52eff6b0a69caacf930541b9526f79991c03db28e53e2314e61eab1010001	\\xd83c3843c057fe1e8b3619b2f786e2d961f5db642f552b82194dc20fbfe63b774418f6eb0d65011b5cc2d574ac4c8929defa4b2c0c3361e3a156d5bdc5e3a201	1655955272000000	1656560072000000	1719632072000000	1814240072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
206	\\x0856c78df8a7546deecdc1feded8a72f337557cd286541b08c33793f09b1311a4be53505de952d95006e4cf9071dbd2cefc140cdc36414b0fa51d4611596fdc6	1	0	\\x000000010000000000800003bb95e583fef2c6d75be9d5ddd64d03527f16242fdc52b1fab323f31cb350bbdd6be6308ff2b4c996b395b2218132271d8b6131b6fa13c346a1954ba35ef04d96901ea31d1254ebe1af85ecb1b3ada07bfafe7db2cc86cc1802e7c07bc4824e1519e611fa4ad1eb91b8357d02491f2dace035ffe890d909e8a15b5a3bd0f1bcaf010001	\\x9ef9d613a979b244e7a28982d067aae23ae5d9b16cbb4184877ca90fc30e6b4067987bd3126231fc120c1d2025f05f0a1b1e07030bf10e5c6ad85805c23edd06	1662604772000000	1663209572000000	1726281572000000	1820889572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
207	\\x0a86e52bbd0328a838b4869a6d8e0d21f7cfcd2d3955e6acc731f01bdb6193f29dc7723792526ba6aff1688a9f3c51eba84a6cbd24f0899f5f06ce752d5f14cb	1	0	\\x000000010000000000800003a92bbacd2970d9d1aaf91b489e24238e873e497a92ebf2dd4fac4d3ee87dca076a9f0934730474b14ecb9d2b86eb9ecd2f2ead72421eeaba06e1c7603a5769e0dc96f19ca0a1ed4e61e4b1a5af67ba1cc30ae79a0abbffe000a9554621ee79ba039bc66d7e4895a2625f2c6414a911b436882b17b00ebde03586847541b2b6e3010001	\\x7c9e21a8980bf673a36d6f82cda7c55bd5f4cb09c1701745972ba91201de41574eaa8a013e977983320a39148e44f34e4ec210f6914e3fd0a8a05dc74d94ef0d	1674694772000000	1675299572000000	1738371572000000	1832979572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
208	\\x0f0ec721127a5b8e3ed3c70f99bb1e78b8d720ec43002c3a4e25fda296a95087b90ac78cecd7626038078dfdefcaf941e3a2ece6ab57f9e758c6c5b7f56af750	1	0	\\x000000010000000000800003e617a6304407360f23f98e51e80f92d607239abd3548a91e72a7053290e901d49371c553cedfe330a48462b5ea412908520b1736f5745eb7769ffe8f2c9f21f53e45c196da99bccca7ce9ea636c58c85a6449a1bca2d00b9a9105457dafb08e1cb5204d67587d02e750b84fe79d3bf2ca2d347cf8740d3b6e8a384426244cc91010001	\\x7bd9de6d5fc1f75ef7f1abfe5d922558c2501b2f6a0bdf51856dee84800bc69916939d810499260e8fc52132c513844c85e10a68718917df73be292127cde20f	1666836272000000	1667441072000000	1730513072000000	1825121072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
209	\\x11c23bf416da3d58a1d1029cab55d20fd269c4cbf562eb79edfb0f6ac60c2fe5448dd5ce959eac7d77e8fd95b2b04435013cf0b74af32b33445545dbbaa4b808	1	0	\\x000000010000000000800003bc0a3f2f1e27e70bd3ba3e9f90bb2bf65c08580b6d32df15f1371fa9f8c5ec012591733f56939729f3920acd5269f486ae63105bbcbc12dac7304648291e3a2a85224659691618e051f1c040aa88fd4440fac73296cc1ef69a41449e919e4591aa8444461409107109d148f77ddc08bfb009cd96b0083b7c9fb40951c4e95f19010001	\\x7b55d6f94de29a7d16b4220f3a4403804e84b5ff0ff3828afb67e15649fe21ed0415c8a4ff0e8b967d7d868f32e84c6f87baffa7755f44d79dbe28f33193960b	1662000272000000	1662605072000000	1725677072000000	1820285072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
210	\\x112e15f65795b3db4b77beaaf34fc25028b67a62b6397442817679a1e1ce35388083455a44f9260778a6d1d2f4fbcb02ed9ab428e76e6cbcfa2a2da1bab4a79a	1	0	\\x000000010000000000800003e4ea253043de422e398a16effeb193efc378afaa75b1472b7dfd3d82e4d7b60a878c2a02e769b50b56fdbdf6b8a56a2ce8ab740602c11034b513680345568cf5d372268921a56eba982cd9897069e8758196e78e18fc5f057810209f53e65474ec6f6830e2baaaf884fa8e11cfef5b8d046a161e01cb97983f6bee0198b82669010001	\\x8d19d833021d599449ad5603ca7eb78b52fc5305e1d2e41594b17349dc60b125571377d72171300703c78416b9164b0122024619057c9e49240b2b62044f160d	1652328272000000	1652933072000000	1716005072000000	1810613072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
211	\\x136e43ca82ee8930fb1107588a5d6b6d359b6a0521f2a08950b5d11ffbe548c432bf4e92e93505652d70908513fa97d406311a41becde2e79a06d7947f51734d	1	0	\\x000000010000000000800003a5881aeae02d5f35e62f408655840b37c88f012bbd17a33383397c5afbe2dd838b96f8683e81c28b09f8c8fa719028bd5ba38d82a3dae84cf7b29c7f89931e0b7b496a7d3a4e5f26b42d8cd6e433243b68b1297acac15f7f1e57624f2b0fba42f4c5c56d344e07cf6ed2924eaa442e26774772217ba279921df4bae3084ab0d1010001	\\x999bb6d1c43d5bcc632f02d9aa7411d3511c02be1482ac458fa52119ceffa597c71c9f811716b7b47d0b29477517ee6ba103c0dfad2f2afb48711656624b040c	1671067772000000	1671672572000000	1734744572000000	1829352572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
212	\\x1e42407d0983a50de261371757d55a2ad21d8fe1088c271bddc9f3d7bc6967e1fece5cfac3304d06b718e1d7a3e0159f009fc1cdce2b9d15ec2f85c043caf89d	1	0	\\x000000010000000000800003ead2a7c38597041f545118b4b6a2510bea04f79fb427f1045a589c63b4b8c6ce111810994d65896d52864e104dd20e27e4ce81763bb3389c858c3be49524f72bf3086d8229f6bf4f4ff7ac8f6d0f585abe994b7836f94673017f26c861871c584c2e49a8235b631f0c0344d8ea5484f805da1058d46012a2b9a207b36bb6bb77010001	\\xd0a9adba6218fe452b86c766d7d950dcafcb6acb44d51ffa3789de7469fbf06e2b3dc0dc91334d0a27b506e760f4e1ed0367abeaf959bd6d18b9daa0387c590d	1667440772000000	1668045572000000	1731117572000000	1825725572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
213	\\x1e96fda5323cb07510443a89b611f4f3ff27005dc051325ddfc5bab7bec1cb7cb41187f7cded0d32fe6ee08453d95b5d662bd782d260b7f0fcb61257eac08655	1	0	\\x000000010000000000800003bbe76d88046000300e26c1ea998824a3c91ec59520bd147a105210dffa5ed1153584b64d0d5ca2ac846fa4117adbe19a87c35979c241b52ac61e7ed26818b8e05d1b573d6938a702ebe8e676f9ace17aedfb343826ee1fdda7f61d64bd73d6ec0e28abeb5e4108e4ae2b65f19c8cbdffc9ceb68e9129d94dd0841060619ed017010001	\\xed7a7e83829ae509da0cbcf6a5f6154c2b8f3cfa697ca120adc9a21ce3329c946242cf4a5c856ca8bbc304d6b6b8ddada9fbb1b6f76ef667c1dd9a90b899870c	1668649772000000	1669254572000000	1732326572000000	1826934572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
214	\\x1f720f3d9ea9c3245ad89aaa097e4270de14fc27a3d649945e29c936c7279ef8db4b8b4eb8e72836e06038eb015392f08af2e57c3b1b117a226cf3a223e10c72	1	0	\\x000000010000000000800003bb78b082efc1b17fce118d8091dec1a00c8017c0bb98dd0c9ce14df5a4152ea34b0cc7298d3f7793982532509f3daa0614108f5258d4312946e8e6bad7795779022f7b724a0c7fe72b227e318ef23dcbb8861f9b28e881afa985bce5a1e76bcb67e353639a699a55860f824ec9aaa34f1f9360d0534b84f303e6fd0653048e77010001	\\xf4ca9943cedbe174dfff7707571b9eb952be7d1977f302873f1b686fe6814a8358f81ceee3e285a64f7c9ba691ca2419f8a46b0759569ea86174ce33970e420c	1648701272000000	1649306072000000	1712378072000000	1806986072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
215	\\x2392c93803dfe5d3a40bc7fc3f7c676df490e5b2048ee5b23dd42147d0a5f76fa934a7e3a139b64303affcc1eded333589c784cf063045308cd2a1effa6ac584	1	0	\\x0000000100000000008000039a07e155ec1047c27f28925b57ce734e9c8534a80fd593fd6e31fd4c10b3daaa418340c4fc197faff0bfe5e60a965c342a1c9c4629c4de6a60f987852b9edf612fe8afe4cbcab1c9dd4f778d45c179ad4f5f776401fa31a83e4e26d5ce8710e901b82b259ae0b50786dda8b7fae076c6dce7f348effd9a744d21652b77e685b9010001	\\x840f45f7fd6cf7a88664d0a3859cf773d5540a45282d853e8ae102339c86032e011428cfb6b82463161c9ef6e7e03575d6f9dacf6d2b370a38b65fe0f1153501	1655350772000000	1655955572000000	1719027572000000	1813635572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
216	\\x239eb066002e32a0cef3e254d3bc0b5c0840ecb2cef90b9861218a3fc54f74b495ffed298e4189030f1253f366bc513c0bc654be12186c52fa9264b2c587fba1	1	0	\\x000000010000000000800003a93d587c04c3d598c2f880f29e9d137af4b5dd608ebf1430c1de19d81a10c2ea94984b28acaea4eeaa6b2134b028a5df9ce83087c5daa3370a33b46ca190a3b496a841964a350f636bbdaf34fe9cf7a37825adfcbdc48b39cc5f57ed6384436f193b7ab5d7084df2f7ae3165cfcefb896584961866f3d94388bf33fc0a944d51010001	\\x4b405b93afed342928971668ba573bc4849cf6efab192127743e77cc8dd7b070bf27b22f3002d62bfc9a2a761a11932a5ba21a5bb085c75b07a887c1c81d350c	1655350772000000	1655955572000000	1719027572000000	1813635572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x2bb64902ee97e6df36ee9604cda216a7542b9d5d1282abcdb8bf1418297a3ff762b10bda3962a992bb575950e6adefc2c5e65a7837631f53626031031dd491c2	1	0	\\x000000010000000000800003db9ed155f2a17af6336bd9b01788403e4aadcd201a73b0e57f24d6831f4561dbf76fd4c17090b01f59d72470acdda0b7e952fc0c961042cae6fda00376c5e26d65cbed0b1fcf64b820ddb31f0444d912aa20ba35b090a39fc22aa8cf9bf1904a71a8828ba806fd2b96e8f0feaf1d5954ed24bdb412794126142060a1740772b1010001	\\x19dad6f49e4fdddda792365213632d62b8edabfb9b3d1c7280811864a43c83f653c7465da460025871ce25a7459021cd75e7c6d48fa63c717b4d43018ec8b00c	1662000272000000	1662605072000000	1725677072000000	1820285072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x312e13cbc211e8f088fe356ff19b506323f2736c42d20ac925fa55cfec0ffe7a8040164b121664be539067bde54bb59f4ed3cea40a2761ff5836798dbd04580e	1	0	\\x000000010000000000800003c470ad8d4ae72e9ec95584a9abe7a752d081004504e0088aef563c7e00b635c4cbf92f94ae9b774c084c21bdf67768734933fc10e699d0b11e4c379253b71b464e880e0a79a87c2e460552667a17e4d4b621cf6a48337e5f3d34799737724adab27fa2c8d85d0918391ae2b034a1b6fc0cb93df3ff87fb7ec192aa663c92b2fd010001	\\x649602687d0f722d86189da238a508251941bbca3a67d6591ee181ac8be58847c8cbd573a870a759d96c47a5182c5848969d85770706329d4e5562d84a5e2802	1678926272000000	1679531072000000	1742603072000000	1837211072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
219	\\x34dab6ce1339fa9c8f6bcecb95eaf2af71c9b7dfdc8d8c2bf7b94a6d054426ab67a7c3bc834d922b81886c6450138f8c412a9bcf162e06e5324aed4825c297bb	1	0	\\x000000010000000000800003aa3dcfb11c8e8a827ba41e1e261d5831b70b3dc7d159ea99575096771e6271046959eec7242483b2aac545534080434ecb068f66c8fee82f58fc7634dc85c461a564f837adeb0f488b09966348d998d863994d0df835aabe4c71c307de163ab9537ddd219dd17904cd46d4a69d451f28c7420c4fc2fe10ba0c8557b8256c4ad3010001	\\xdb85e3ec8809db312b64bd945ab47a772584f0e3eb6f0a11990ddb892c23e7ff64cbbf8baa9a912ce4bf82aafb121a53d95e4a81afa08ba03ef957d7c8f58b0d	1678321772000000	1678926572000000	1741998572000000	1836606572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
220	\\x3992fb339adbfd625cbd2144effc42e1f33153f626f3bd9548bef67e230dff0fc388cc23a50588f1983715fff7293f11e37a5a89e5aa0fc9cee20783ef78759e	1	0	\\x000000010000000000800003ee7bcc9e36799046983cc3577b88be5d33013d3382ab49c1213c14cb59de9954b2ae8fc7c1d4a9e5f9356d4e997be9c41f88dc72b7a9dda688f58f3f72861021295b0384f2a2f16e6f2c8fe2baea99cd00420308ef769cf408da85b0e96b9b2e7535518311c972e9ec9becf3882be58faad5c6f099f0c3270aa9cf223e25cfef010001	\\x27a226f738c7802cfeed5c8ede7cbd1c2ed6b4ade30ca337870f434c478bf2b3e27d8d9871064928d72408f8def626ceb40a2055d69873e9676e2f62fe85dc0b	1649305772000000	1649910572000000	1712982572000000	1807590572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
221	\\x3b421948547308f62efc5ca4458afe5d35df306f6cadb9af99177df64c1a8457ce4b5c9aaf4795cc370c558a802016ca86ae3eeb2da0f97e8b482eafa090db3b	1	0	\\x000000010000000000800003a0fbbc46302a76414b8e2663aad53b94eda71eb868019269f2b90f407b0cac4fe0446bce1ea454a51862f9813732f8ccac296afcec58f160d2df74b77e02bc01b3a6fcc803c58659187fbc385cbf80db9b521c4da52c601bbe994f5bd693f0b391d072c9ee6faddf2e715a1804b39e81e9dd4867318afc64ba82e360c1d1a5f9010001	\\x6ce04dd941c8fb1cbc96897999374da2561895d92a1e56df16dc44d6cce859068bb835dc0168c5335b544059b1e142ba561945a1ce6666e067b8f371450c7f02	1678321772000000	1678926572000000	1741998572000000	1836606572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
222	\\x3be66cf736b6c6303542bd4705687fbcb766fd42912d732b6f7cb3efca27b4dedd388fe8162757a3d3f1a45c518724196fd0747c3095763ccff0d3c86585547c	1	0	\\x000000010000000000800003eee032be376bb314dfdd44efceb990b9e7fb0069dd0f40a2bc617faf0413e2632817e2a4937ced42edf7320c281be5faea2bb6617c14138655b6af1f9a84dd7e47c6ec35e47a91bfdc3ce36c8f336001ddab1cf12d7766b9316e62c74a1778b760e1f592dad2c6b1507b50acd5cd9ade42a67d4028428d3831ec2f4521fd2139010001	\\x2338f597b29994b6c6fe68002c0a57d119d7f72c97237691eb5d1b74be0ab80344f68809fef3d160cdae05e5afb5b554e68333f6e6d701d6de3d564c058ec30d	1666836272000000	1667441072000000	1730513072000000	1825121072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
223	\\x3e8661a7ee69176b3bd223a807b26f5eef5391b05367cee5f71274d8d93afb3909ffc9c98810a4b3ab7dcfe160abd1f760c06107df45af064a88ff54464940fa	1	0	\\x000000010000000000800003c7747406cf7c18e5319c76adb10eb382220814104ec55dc4e4c82575c2a015f607d036bdaa512c8e11f9de0eeaf3866c174b5e7ffbfdbdfdea27d8ddfc04f413ba0870bad73bc53882bcb264fc8268765965ee8b5e3cd3cdf9c57ffa47b901ddba2bcf66cf6b5d967dc2a2216f908d22f7f683a9149166a8bd868f9b528ce4cd010001	\\xd1d010c8e64c6b15ccc97ab97389e04ae7fa5ce239bc429db5da5d617682c98c00b91b4da25b5ccd4a128576553ab59078bf3032152a7cb1841f392b43f8120b	1675299272000000	1675904072000000	1738976072000000	1833584072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
224	\\x3ebe2e95dc384526070b31d50b93e98b002cee468f5348cd87bbaa23c216a4649e482bddc49969e6b0c20e550bb0e872244e8e797a0281ca5c0009deaa207773	1	0	\\x000000010000000000800003c628a7798805ccd9e326807428730dd8ac909e593e02dd21a5b5016ad82221049c97fbc8487bdffa92bd27bdb14ea5cf9f2cbed0baa751526de15476a54ccf92b03d0abfb0bf6f137f9dcee89e7ebdcfd129535682148a43f0b373ccd20bdba1da6f96a2d906729945e655637ca3c25b19825087b04fee3592ee497af5d6b807010001	\\x21ce99bd9c4f2c37501a0a4f370a22ad8f66196ca55413237712645d99c9490c12a9fd3b31bc67d4434600de4b9a8fd912e834100593842be19a0d987166ab0c	1669858772000000	1670463572000000	1733535572000000	1828143572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
225	\\x40c200d0baffcd0df63a9c30ce07049fc94e74c18ebc9fe6debe1e2c6b7124bd5cf073644a0bd5e557e420281f048a9d8e9325e783a611f83b770b0d28455585	1	0	\\x000000010000000000800003c2c95c8e87735783adb28c68ff206a1014c3c558a3295f6a9a9819645d3647e889fe2d07a96e151547ba9cae71916d0d3bf544bf2d1b4660bb490e3a7164e4560ac1cbaeaa6af85df27260d711aa86581662466fa564c9b415d3c647788aa4699e75f57533aca45e2f79f9d581acebef45ba2476a79da18718ad721927d0e061010001	\\x59982549bbaf87ffa30d9cebc951fac35d36f9ed5c46d57ef5c6165be99e4f75f26f6f3496b0caafb1ead25599a814a12b404cf76040e237f35181476c000f07	1651723772000000	1652328572000000	1715400572000000	1810008572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x409a8d8f5586d766944aa79ce3eec13a810a1aa9e7514fa3b36d639cfa247230b3af525f8a98d9191174da24edab6b6f8a7a5b0969f1f72e02bd78baa03bda2e	1	0	\\x000000010000000000800003bf1ff59e4e53996fd252075e285345e113c6cc3a27ee1280a245775f939d371539439ed877b5bd71098090433fd82aba3dd960bbe12c0b862a6892f6f11e7c652b377105151f57536a3ff11567eb40d051f3674d917fe7dd28286f9aa76198a108be8b8a9b0b0e59cafe24ccc1f305d7116fc030bef64db9ea0026229cd4aaa7010001	\\x7fa649651dea9bff28013035e982f11142184966edb340cd539d8f91876e9fe9d829e3383f870db2cc80330a2c89dc615f848c2008ec8bf920aabde64c16780b	1665022772000000	1665627572000000	1728699572000000	1823307572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
227	\\x41ead81b2bca31221d86bbca135c3d113c711e6fe5cbf420c5cb0b864a47c928b533dcc6e5b781980941011eaee73bde990cf904ba64785e00dabe7a051e8055	1	0	\\x000000010000000000800003aa57a83cb24c00356f5367258cc95a01af826184d82ffd74d522eb71e6a8bcea976146d01383c7d48487aa76e3044011157045bc29d2016b33ee350429e5d794f63bb6e4058b233ff06ae553641777e8d60320c4a7148ffba0784e728ad5c6955099133c6aff715232f650c587127fd5246da0e37ff5d08c88ccb63a6f2dafc7010001	\\x7bd87b1c74a91f8826f46db0152c8c8f786fc4abec5f256f085e634c61eb6475f4368ab53deed2e6511e2d0d7e4b34d67541a9d365a90d888d4832d950cd0607	1669858772000000	1670463572000000	1733535572000000	1828143572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x41fa23e5e2b29beaef556c3767fe8720ec2db6683529cbd8db673d4de88826bfc8a9fea12dd5781266728d02f4c3af05e25b74622d81bede2f9349fa3ea62530	1	0	\\x000000010000000000800003a0f39fc823fcd91e7702ea243976e846583be3d6b68097a5a394d741a0af2dd5aaf3c9b14d9be02efc081c20843ed9a933cec203b080ec48e77340659b5afcf7518e1dfc60ff0ba1e43f6ac5ead928ec83f9a15598bc109ce87643233889e571988213c448bc1f47fc397bc64d2b2f601b372921f16ed5feddc136c95847a9cf010001	\\xb78ad745ad6b5b1c27eded5a8ffa44b552141754dfc1cf23d1a2b1e66c445255da7c5c00617791bf30f823c4f792f7db3f8c1855678590029ccd458515e9b709	1656559772000000	1657164572000000	1720236572000000	1814844572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
229	\\x45a6f02bf5a269ecc5221a5dd29512307d0f27849873e5c243ab4560e2c35c437f13bcd3409b4658f4217dfb14c11b31c681e8a1f9906cf80eceb61d99c6ab79	1	0	\\x000000010000000000800003e1a61d0824a51d6efe4adaf555f929069e018be3fddea5efdf082d2435c569cd1e4a51e5c386998f9fb56f81c903d76aa05dfe2befca687a4a4861137e8dbcc51f3758ffafd46de9c169b04f139eab72a8bbf8cc3fb88dc5519235bd3dd9de519cdaf22b539a4b68f74260313d39e2242996cb1f8bf99f05bb644db13b9b44c7010001	\\x96cd7ad9862265e2e29527b52f0020e6264a00161a0cbda51d4cc24ccc90ca3717373cd2abba093bd33bbf4a2736410b19ba6329c81b83c8c5186f9ce7819f03	1673485772000000	1674090572000000	1737162572000000	1831770572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
230	\\x479ad083e247a384c1896b7cce4aca975cafafe632bf5e5d6a6de2806f7e38a45628053aa235645e70e9c9ff2690906b776ec2f18034f16bf07b3ad74dcb34f1	1	0	\\x000000010000000000800003e21d12dfe3492503c42fd867a7b403b472a9fa4723779382c71cc2e5e7b173fb5c9512514f2662aac3fad16336f8867abd6c2480825c819ccb0314b1b5754c8e365e8d14b290e75d0c8d223b7e062b5aa50e5b6cfcb415dc7ce67e329e5237f711fd4469e98ac130855c8d06369cf167908b1c5a062db0eda3e5f7fed352cd4b010001	\\xa56b70908cf8abd19fdee0c8f32e19595cbdc84179b7d4b83d8abc597807de18a63e3c4fdddd10b6dcc8d36a2e71d099ac85e76bd4fec453a515ea76d354c10c	1656559772000000	1657164572000000	1720236572000000	1814844572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x474aadde0a2f80800969d609591d19ba5b79a8080b870ea97c25bf18cda1f66679bf0688a365e4649ac482fede4f043652ade8fbfe1514b2ac2506ba58823772	1	0	\\x000000010000000000800003ec6942185f517a05a8965a4e90a148fec3b578ef7c69e5706aad97bdaf906afc9e9d13b4388effa523ca1dc23a474a2f10312045cccfb1530de926cf5859b658ce2e1d78cd70cddb333fdfffbe40d5771b1a1ef6b21673df31e0ee8ae1c12073807a1b7a0138e4933d10cd70b87078faf95045461f9bf2f62b93d16a4d47a3c3010001	\\x2168f544b8bb241bf32f23b25ad801a18008d2de24262699ce9d4e5291ee3653075dc7a474b095583e561233a7eecf181c42d8d130d0612f84aaabcf15fa2f06	1663209272000000	1663814072000000	1726886072000000	1821494072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
232	\\x55725fb2bb468a4be1c6bfd652ae7f4908dc71d396bb4f7eabcc1babd9810169dd1a4e9782fb927e04b39dc85d19363a48277d891573a94b74039a48adc03f70	1	0	\\x000000010000000000800003c6d8a60e7746ccc89dd4f8d12c7cd721a6a4b1014ed575c5314a2f35dc80249b733243b5288ffd213d6f7c68627262d11e2a981e7da180fdb3ffd5800e825a7695491120e62ded85b5e1852860bee3d47af3b68046055717ef89faa687e20c091596b8608ac7d79d0c23e11898530d494bb025b5ecd026ece58f237948e8d1b1010001	\\x038fdaff8600e340a126a0267f14485cb901d0463a4180e7f2b6d50f7ba001c104fe6a0e7430655b457665894780c66ecb4583b66c1a537223c8b9a1e598550c	1667440772000000	1668045572000000	1731117572000000	1825725572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\x5dfef097393cba684270ee6eeb65ab7116adbbd2aaa19b5cf8d479ffc1002567cda70836ec59c9ba6716d41c89be4ddd43680663ac63c37b79a06a95cae60d47	1	0	\\x000000010000000000800003af7c23d7d13a258a0f9c39501a615caf2f5ebaf72f474b5d3aa5b8db8db648e7f5956627bc5d2b4dc600a2386fefe8d25765b467db7c82329d31ba36f187f4a24d2f2bf216fbb66a00b18ba4e664820ed855229d637eab059758ba501a8d35253bbc0876e16a04bb27f35cea493e600c651f173e65740b87a9b8471a49804941010001	\\xc10c71ca6c946937d96b2fe9caa8a3416fc2bad72f818f7a2dd5e5f1cba4d0d6ef78c05c68d36cdcf3ee81be318e919dea00f32a8b07bd0b34345c2ef7a1ee0b	1654141772000000	1654746572000000	1717818572000000	1812426572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x5e62476ac83f37b692ea739aeaaae84787b45c25e608c90b9f7a829b1ed4051bd294bfa2f6388f51fcbd4c10de6564b219b68d7bce6606742044fc5df5472646	1	0	\\x000000010000000000800003bbdf9c6d7df6e26d962902b295d55d388e565a35147ab1b0053b387e8771dabbb633beb7af87b74ed319a38ee7af0051fe3d63ea62b74605337091cf83caad325023a4a6573e2124a27e15afa62f9d797f3e1d89de54799a7d3150a864d08fd8343caacbbd74babcf9bb20b062b5c03820a518a10e0e1a24824f25aa12b558c3010001	\\xbeb0e22a3e334607b1b581177ae72d06c7399e7c903a4b01bc81bae0da2daef194065dc6925eacd7b2f08a53fddcfd6e615c90781089a46c47c48fe0724fff07	1672276772000000	1672881572000000	1735953572000000	1830561572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x6176ce6400c62bf5068a1a442c2adc66d90d77513cc912b24df96eee1afe2e9b39e8faca9f11d46bb130a2c2cecd50377c2c9252c5430c2480a8dd383aa4c727	1	0	\\x000000010000000000800003c41918bb98df696d10921e93350289b1d8d8f50f58cd523c8499d6ebc3fc351d7ce4604d371f461eb9ef53d717f07d639a7d28089f119eae4df6c082960b9e31602c48522916531b3b30e0bdee051a8cd316187222c2236ea844a3746c3e06c834a17e4dd1710ac934643d3193ddc4ebacfcf367e39aea5486a2ee6ba0a84dbd010001	\\x0d06717943e672da598c04873aeb839cdddac9c71df4064f638d200c807bc133fc5a61d8dc83b282a6c3e56ffceac5df0fd4453f95edef7f2e8e80c00d908800	1674090272000000	1674695072000000	1737767072000000	1832375072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x6bbaae425515fd1300dbe4df25aef5b85f281ac79ad44cb27c5598ee7289a57ab2df57ce0c505b131834e8c712c30145db04459169cd11bd38b480b1cac6c628	1	0	\\x000000010000000000800003b5f8fc4aa624388e9fb5592d15fb4e42413197364f1e644fa02eed2bc5d6ea787905f99ba7f2106f27c63e6d58801fcbf8b60a8c55dbe6aec596ac344dff17d8cf6e969a0d72d02d220615eeeb3e6c11c1ba838bb0a37d162b95cfd7960eb0605e133d0f06a775fd0f8be77c65719e36014ad5ba32b341ecf591989b39f501d9010001	\\x7d0e7d2e47d5000bd763a166046308f5e3d1b83af10382c88c4adcb9d3760ebacaa6d9f19a02e4b6bc57e227f4dd09aa81e88737e909fd0e5c073a2827695501	1659582272000000	1660187072000000	1723259072000000	1817867072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
237	\\x6c2a9d182311f7dba67653f975deae5c86a23d216d95504a7c7f85c469708f187bebf10bbddad7dea7d099fec74a85a63b7b71c344a241ff5071ed137bdcdf94	1	0	\\x000000010000000000800003bd957cb94e5c57bbdf2af0d57396b4b2f535ae3f2cbac8a96b8cc294fc27e2ef14e242459a2871dbd41c138d7e5b94c32fad0f5c45f3ff8fb84b82edd96e85cccd71119aede590aeaadde3222e7579c9a217fef54f12cf34c0c6b023d20bc52a4d93712ac5deb0f72cdb587a17dfc46306056805f2a0de6ecc1601f03f7f3349010001	\\xdae072e62131ec9a1b65aadc5f656fafd3a1d428de02ab9ca2a73e7f560ddcfe16093e82cc862eaa66315c493efb36b3c820003461b4aa7f4e4707b277b0e409	1663813772000000	1664418572000000	1727490572000000	1822098572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
238	\\x6d6a112443ab5a2b0a632d91137533b74e6bf4effa891090949d8d703d5186522e1b0b56890224f488589320f0a6ba9a2ab27bda65f08a312c167189cba8e4a4	1	0	\\x000000010000000000800003aaf27d72ef6f46e9bb0a1d690fc4f4b4ab66bd3965c80c4b7842d57438a650fd545e42c81ddbfc6d558bd729369209531e8be32dc0e8cf5c656a088225d7bf789a1f692ba9c75fb0eaf3955bc759e2b91ebcd2b2977c8c4b0b710f8a752afee65c22c5e5fbce323be6422528db5b99b7004b9257ae7fc7465281aab20b5d26a9010001	\\x206a7b48e68060c32f01fde3c555f5b6039a3d2f72f88a509d8be487363b2c61b6706a593f428b86d76abee3501969d6e3988ad2843da13613ec625a699dcc0d	1665627272000000	1666232072000000	1729304072000000	1823912072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
239	\\x6e32319b893603f0990fb516f143c75e7d94bc808b3c5f9a13fc7d795f3dc5d2a6dbcb9e1a89f98b83d01e2e7a1411876bfde9a0a43d603d6286ecdabe6ba55b	1	0	\\x000000010000000000800003b6d44b4bd95f7d769c8906d056d86a5469b19ffe786829c186d4aaba76d1125f9f7f3cb19a5f4307f000f206aa69701a0fc3770ed4d6396cb7183a9626d3806955d4882bddfb90d55dbff5154e53baf44798ce67e80928c86801d56724a8a029e58768ed26f665bc5a629ad49f681f4f5c40ae7fe9cefa04a0e454bc73a95395010001	\\x9e4f4741c88eeef4d70a402871b80b9e6edec1402d2532d4f549334d5b33a62fd0f517db77fc36148fed5a3e69bd60f2f29d23f3cd9cdfbfacbe92c433133d07	1675299272000000	1675904072000000	1738976072000000	1833584072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
240	\\x71729a8cd64cec466fd3cccc0e8f3fa8918499b5d05fcd3e3fa196a24672bfb05856f002712c0f239177c7fe04fdcc6abd8bb2956b4d611ad6fc11a41231d583	1	0	\\x000000010000000000800003ada1cddbc755374815689de4bac6a89f4ef9d3a939a37490dbe40955a125bda83cb9722329ee649e4bf80d4941101797435ae42d35869855b4fec6f2f5dfc3e08c413e157b82cb8e03144c1ac213fe9378c20b85598f9a29de12acc350d96bb9752794f9b2824d127ee896f0c2a05a2ad49286e0b1fa009ec6a402d4658be2e1010001	\\x74312b365f5042e17234b984dc30748bef5de455e02a78c16aee3f4366ae8bd235da98e504289cc1cabcb34649815b79c2aa8e057da4739b2b68fc8a6f9cec0a	1669858772000000	1670463572000000	1733535572000000	1828143572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x72fec3383d331376e3aec76b906a5c6dccf79c14e5c0fca6b4fec2d5ede3b7b2fd34ef48b7a5330e47284780d5dbf03a3d3b56c7bba616fcd48bf79627dfceaf	1	0	\\x000000010000000000800003d5102957c9e869106f2ab86d4fe4bb7b1969b465617f619d6dd2f802a4806be61e1846e4a67cc688835e61a8c0bbfb5588f85e4b77c5cd8926ad9b5efcc8a7e290ad9456519f6fdf7967d1549c665e891a8b1aa99bf9fde409db5a93dfc09a4161550e101bc2bad11008dc0d983f944dc72cec706c9852ab66caf34ec5e614e1010001	\\x98b2ff6b9b8382c0b3145e4d4e7e3f38c8436f7c196ba63b6711bb85636ac1b1c32655e1ddb29da3f450da4646dda82f594b623e8798491b1e63423a9345470e	1668649772000000	1669254572000000	1732326572000000	1826934572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
242	\\x734a08ee1181f6db8268f19fce3428ce8d16b7b644d96e7a36a59892603db6597daa0169b01c7364164408be9bc48d313796040b2c9732ac5243be62e04e8e42	1	0	\\x000000010000000000800003ac2f9c0c56295673d47769972aefee296c2fd8f4d262bb39ee076e31dc976ddcf2058edb5cc63808a22b921ec81eb36722cca1da5c94b7ffc9f1e03487aa016bac9154ae33354301a3b8a5c7b1f3d1d08c18e358eb5c57f3b02b8816bfbb9a0b4b1fc580346a11277140680b7fe70b198106a4de87dc7c39d7a92bcca9912c69010001	\\x25509722bd91f6cf6e5923b14dc962dff356fc473b950f65358b38ac943cd3c2fbaee5f02ec75a46827c700c5f78c8ee247bea88cc43f02dd9880bef1e88ec03	1657164272000000	1657769072000000	1720841072000000	1815449072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
243	\\x73526d3262ede2a37fefc1db98ca0ea3ba91b8dbfea441bec6e991bde0af56d65ac4a4086187ecee8fa81c5b4661477144d21f6093f3233d5cfdbef8d3a81fcb	1	0	\\x000000010000000000800003adb7bc1aec0804eef9dbced8c73b7b8e0c766eb0db85b1bf22e92b10c2bde898c8309bb16c0bbd5a0ae2a839e661c326118efd45ddcb13cd6b54dc3c45ced5d654003a94e13d54b32c54df75f107ef9b9eb2c7bb490ee580a8b87e12b262987c618739c251ecffe0b54d9fb67edba6729ce93cae9fae1766f03068d674319aed010001	\\x315c769ac67848fff010bf18830c473d89e24b4d8e98c2c3a60270d197d83cb6445744967fdad778892a66805326c29242fc8bd4db68b8a4c15970e667155901	1647492272000000	1648097072000000	1711169072000000	1805777072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
244	\\x76ae9787b41570c9635694886690b9b25efb18f422797f035d28cc8ac8c0456a422bc62dd7c237974e9418a3a05a1302ee041f8738bc1470a2654fb44522aaaf	1	0	\\x000000010000000000800003931bdf4007d09550be1d488581a53a10435277e33440851751b3944a75851d1882f345b3c0d0fcb85cb0e3573abbaf4456602587e9e16b7a524c76a349e7316867f818ace89066c2ee3147ef59fcd5d2fb3bd168ac92c4fd5f53d9002c3deafc09b9e97645abfebf880a1c3f28ec67b701e944ed17ccf6860d543ff309772d99010001	\\x23bf8d9e412e38c8fbfcf2ccfe8a411f6b2b558d5e2156fb2c6f7226e87bfd95f4119a769b3d63abb872fdcb66de7c0468f5102b3c3e404527866a3367c2b807	1654141772000000	1654746572000000	1717818572000000	1812426572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
245	\\x78d28d804e447b5bd098fc014276c922791e910a914c8cd8d0c85034cfd407edd53070bd8b6103bef85a6337913d70b63817410ed5ba20026a2f6e4181f67ae5	1	0	\\x000000010000000000800003e2c3f10e705510a77a3446ac7d497ff21e5f7f481bc31f070f7837de782acc83afe916a5b60d9a6c8ea810c17b1ab164640578dffcdf0a5deb179399a7ab6ef56c6e8d94c34ecbc651ca35a0dc806b55a679acf2f0160558e3032906beb758de7941515aa0815ab2f119d42a89048a65bd4c2ca2142ec53ef644abc079d01855010001	\\xe6c4c5ffc8e39339c428a2dde655841c3df4013d5b597a091023ba469f3938f65f7d83838c72931054dc74eaf8ab553f3d17dc4f4d465132d7ec018786214900	1675903772000000	1676508572000000	1739580572000000	1834188572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
246	\\x799a1d02fe69a98e2cf0f9f6732e3ff74fa6769a4643f2d4f7c3e48000818f61e9211b3cea8108eb7f53a98e1b97c89d872674eacce010793e99c15b771a912d	1	0	\\x000000010000000000800003d47c390f522489500623ba9dd561ced4648c0ab76456f0e92cdf40b2e5769ca74a6605045bee5f3fdf581c5d0aec7d4a2119838a51635113e1cc47f93474e0dd726ec724d6adf7c27d654cafdbf405e1cf07e50971068257d0b4ff0e92f786cacf82b448b37055c167064f6ff3e9087c947d24de34b55443fdaa1672a80b327b010001	\\x9c2e9284c3904c0dbfae1e6aabe0de7a377dd71c87ee624302a542831de36c90d81211c1054a8ed56b96b057c8748410d6cff0807636b36ca45551688cfe900f	1674090272000000	1674695072000000	1737767072000000	1832375072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
247	\\x814298882d035165bb5d42f11e61bf6881f3c59263b99e924fc35bfdfe0f3db9965ff98fc4b86465fa2ecf3ab497e55c7ae789bd5b81bf545a221aabcefe773c	1	0	\\x000000010000000000800003e5bdbf2d5e89df9f66fcd9380174db910ab73ab8c8cfe7c2b5860038a998e1cacd5f25dd9881696d276fc0d16b679a3e07baa42133bb716d077ce807c8dcae28f31a66519ef148bfbcad2f7c50592f55dd5bcc8ce69cc98b279c2313b453f8ae10aa8a60229075d5dfe9d01251c8357e8bfc5cc31cc2f5c208e889e4d2931421010001	\\x97227853417c9f2779292ab472004a022c7df0adca55bb0067b19b69790078db41310e4b809beeb98272c198043b49b69b9bfd4928a42e8ec7c3c9010280930e	1675299272000000	1675904072000000	1738976072000000	1833584072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
248	\\x8e2a44eb1ac4f5fc7b61059c181869d45e6d608df0d6c56210835f406ee15a4d90b346abab1902d15bde26949d5da124b52fdb852de5e1989a0a0c45e1cab78e	1	0	\\x000000010000000000800003a0522b913c1d67043eb0fb9adbe3df5e3d98ebac790be42bfc9b3971e89100b1254da06125c74b3ed365bbd158611cab5d00030189bc98d5a67f43faa0e3b90d8b6bcdf8379a5c78d184020278324e3063118ca6a88b3ec33055259983b9091d5471ce6d31b8795f45fd37c600bbaeeae04a35367bc0637d257e3491826f718d010001	\\x167317a67bfd4ac5a4fcfcf729d6814ac8684d6c3c0f8a1f5da7df5f7925e68fbf8fedaf69d088d121f05586fd97c019b260e1000aa4834c4a6c250d7004e00a	1657768772000000	1658373572000000	1721445572000000	1816053572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x912a44bb520e187abcc1766b27b7a8ca615e30a14bf01f78bbb7b9ab61a8f659b78eb0e72ba726dac1642d3704df00a5ed144fdecedc82a09c928a9c222b3884	1	0	\\x000000010000000000800003947104b8cb94554d10b3bb43e4316d4a7858f718e28d1216ab551d2b6e8bdc29c71534f2a77e22ff13694716b70a158f70f92b37470e594e4d3edddd19d0d0d1659972d50f5e608eefe67308cabb3cc1192ac4ba4071a456e55ac23604315e70980d3226fdf3a628b57dc8a1dbce540820dd8fbaf3da6861780c7d8252499111010001	\\x6835ec3ca617a27b992d9372df051739aba1202fa374a50bcddbf3da188429efd0c2a8e0349d5ce9f08887540c4a45f220b12e25a7b2c97fbb1408baf1c4c906	1651119272000000	1651724072000000	1714796072000000	1809404072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
250	\\x96ca5bcca79e6993cc9ea9a7750d8d65ce225e37b04268bb17d762dfdd749dfe7fe0e062c5b8bf58aa32714e409ca8ec861feb6bd6cb985e4f850f5fb4eb2728	1	0	\\x000000010000000000800003ad84484bb87ac11953bb872d365e0d1891e92f90d44aa70ba80b9c1e50e24c4a45dee284cb4682c3aa4df91550be9a681c71aad17ba2a880891e2ffb41e4c44c48173c448d5ae3fe0e84403556845d8bb022cc8b6db9371f21f3396e0a2735eace7c7a67706c1f0d2b60c5fb4ab3edf6499e8c81b4e0ee58bf0e2e2b0e93d0e1010001	\\xf91bfccaab66b0c5590cec9386286f9d81fc4f4636aba949345f96f8b09fbd3dddd651865692a4047ae55e281794e48a398dec40ebb36abdcb2e681e53736b03	1652932772000000	1653537572000000	1716609572000000	1811217572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
251	\\x97da89480dcd7d96e5e8cce2a0f57184d9441ef96f966ae52611d416190f2f8b952cbe6080a3eaa70a23da0d6cf9d397e0abdb48199284595edf3192c42cb985	1	0	\\x000000010000000000800003a347e773f01a64a4535b3bb77ceb61dbf6ce8b697ad2272f61fcbae049ed9743f377c0493f5fe27cbeb0b3681a7103a6b8bcf7af1787e2c60c3fc15262572056eb3657c02b6ab07db3ba425ea7349f7ebd8f9d350bc8da268e8e5b7d4b9645a27954110233aa8dba292391fbfc2a3170185a68d9055433a49e792c925c91f877010001	\\xf717548ad045521e312bfa02c0bb2351af83a8d1a09d3524f603b732775bcd82f9123cf31ad92ee92b4dfd0867814ba3107d1b5b0f22bfaea6c9e724bd8c5209	1677717272000000	1678322072000000	1741394072000000	1836002072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
252	\\x984af1d4bb40f0949c117e0c079305d0cc7c05fa117e5d2c968a23dcd061e30867dd7cffec069576484c79317c109b0f7f901fd9f546bdc12a00c9041bddd5e4	1	0	\\x000000010000000000800003d941351770905f60e8035543a5a9fd995ad2ea837210352f35400053bd727eea19e558bb386b46ca6de1631d733ab1c282b0fdde09747224613b8088c7bc5a706bdc2986e951f4909a1db447c06b47d81e1850e598d9eb34c7bbab820473875f458f95a6031e2aafcbb3d7e917aa2c3322831231a6037041598b4f14dcf6f355010001	\\x83718fd6ecd1af8550cbb3c75cdc19bdc837b0a980411c151239a2c1195a33eaa8e2a6448ea11c5473e16894d07b21432d10038cfad4a7860177bd312fe5660d	1654746272000000	1655351072000000	1718423072000000	1813031072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
253	\\x9f4ad6035278e6c54fdc44c41e3921501ddad976e62710b209744f964bac6ea75511240b4545d23bb27cfc6ef9840c4f7acfcf9a0b56c94086b0dcca6c943c5f	1	0	\\x000000010000000000800003ae53c623ef9c69e01c5d9b593ea9408fafcd0aaf52d20ed31a49a9ca9bd63e6ebabf38d0ca7346d802cd49d5267a2dea850ea39c4425ad98a972494554b8e35135377facb23ba1fa2ff7e78b8ae6ed69cc743e7f0c944f8297352737360fd13d022df777f4e35750c6d97b8916bbd48650cb16ac0fca42b7c91ce574e0cb395f010001	\\x25bf83b4b19b76b4a4444bb3366d6be11be1bdc43e00425bec6deb274f399e4b14221e9b2cc79ba42e9da54c69fc929a0251a983ea35652eb9d37b482935b80f	1652328272000000	1652933072000000	1716005072000000	1810613072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
254	\\xa01667289a9e0bd7c28a3e765c082b8ea7f4f9b901c98bb9bdc764e38f2383b32a1c1b58c1e8d73a4d09cd3e427136d7a14b4d27aac557b54aed55ccd7dc5379	1	0	\\x000000010000000000800003c40a9faa095e4bc219d056e2c23514d287a654eb27a11a9587c4bd45adcacdc5ee5166bc2301cdb35a8526f5723d459ef9e597777809dc803411646a8617e0ff14b0f66c951e634e80e29527019a3f7256a7c9f52defb35f86fc57596e95969ce920c095f2f6fca0d2ad4117ef0f1c973ad4e0aad9e40f1e3b2403997b21c5c7010001	\\x914306f19ceda0630f15756107b15b081804d98a82151850f537225eb5024bd4ae03d04b064beb26cc6ea029a609aed9457f6ebe5fbecc43cbdc528287d5ac07	1673485772000000	1674090572000000	1737162572000000	1831770572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
255	\\xa116b0942a8b1a606d77d970d032aedd902dabfaf96db5972393f86079bf0675efa4f1654abb05a0749d6cfdd70e898e8a7bbffccabd6a8e2a5f12e42f87f7f7	1	0	\\x000000010000000000800003b067e1da3863eaabbd1d94b7b4040795e76c0e828083c562f74a3c353ccb8b8133f2ec764f94c9e26cb7c3e535fba373f1deb177029f36af19f7fca72f0e231d9363597e5bbf7ea6ef3f719a0ea7035275cd69320c18f908c0083747b40d72811fe322dd1f0785c639d29732692ae1cb0cc12291e68a1363f6c6a5807d6457f7010001	\\x17ed912adf13275b6007f27f3bdf161450260c055f38a7f68fabd7b9d9faafdcaef993c8544851c6fa28b86b6d14a0a223badcf576c97564499838049abba705	1677112772000000	1677717572000000	1740789572000000	1835397572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
256	\\xa22a0cd33cfe919dd461a6346083fceb5b72b8b1b95a54fdb8c30ca60cf1df7c3769551d460c9954d6fcf1ff986bfafb6633061c82a68258868ee7519a71c673	1	0	\\x000000010000000000800003b8099074719987af5ee50f5988f4b78fad53acc77e24cccff4ea4b4cf9dd2ea6cf6e76f9d3b285407ba16de0574bbd809b4a0b2acf2893007c465acad5fbe886f0cded8ec099a178ec4b6a0890a20ee90a02921b6945a1a739e48705607f70743f825b25f458f7fd6b17346850fd28f78c96d4278989057fae2f68ed48ad5de9010001	\\x282f643bb9e8c538896c4443744c1980f499a90342e89b1b204a167adbd6e698ec9cccfca843688c497d5c5c0e0eec4b9cd696f2a191c703b5007930cfce3907	1671067772000000	1671672572000000	1734744572000000	1829352572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
257	\\xa89207398ed47dc4cdad8a6a0acf0d643ecdd2297e403da94745b01b806e75047a3941a21b137bfebcdf16e342a5e8e7baad30b8ac1c0bcb532900a59a235d95	1	0	\\x000000010000000000800003cc134c60c74e0df7f5a28e4e6da3a9bd28a65b668f558c5e67964198f1c237f424edd153102f9463b0d348d8fa1aa6d9b7178b564b74d1b48058e78bd65ae75a9029d2bf83ed16919b0fe48e4476349db7ade472660344317fec4ffc7412a4fc23fe832736b3e878f8828e2de3456fe436bea5fd27c0ecfc5a5c463c0325a771010001	\\xe29d0bf099990822534c3d1090e86e3d313ec490d3ddebdd05399171e0cc73c5184af7a5d7307a1864c54d0f93ed183203c213553f3d900b59395cb5c0e75f0a	1672276772000000	1672881572000000	1735953572000000	1830561572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
258	\\xa986e0febcf2a28454430c001b00164d099737e135cc05058d37460d5838a03b77a8c95db9b2a7ec1749ffe52bb0550d17085b0b29d17c48cef93d53f45fad64	1	0	\\x000000010000000000800003bb7ce1e341edec5d42c3db323b98ff4ae785e23a1e613c4ae5445029345c69668eb8177c86a9467eef420ee9ef78081fc72cdf05709ef3591bcbd555a9000f18da24d612f73cf03a2a22f44b7de359842771ca0d927ca79d0eb3cbb133ff951e537f01e82ba53910bb89c78417b918a55e38834abe93a5fb084973b8708e5157010001	\\xc5eb714edb309a4c4730507f2e86db88576c2b60b043688ffcc89f8415627d0dca296c530035060d40f1bb6b6fcfd40f3f3ed934fead94fc8037b7d7cde56f08	1649910272000000	1650515072000000	1713587072000000	1808195072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
259	\\xaac6704c1ecc781dab7ec3a19395da3961b7cbcb5abadb026594d04d9d429f7e48060d6dd7c79c507fad21e0ab829f43ceb23f5c9e3aa48f5b4727b762dceb4f	1	0	\\x000000010000000000800003b00b40a32a03938e8bde9746ec2e132c7dc668f1b64bbe73bb71838921ef06f9475671f8f5d3bdee359f83e38bc01dea60f2be4252f7cd226c15864d0e7b839cb3b0827f58bb55a59be1eaf603352d2460ba0384bf7dcb9078cd307d0fcf85d04e1fb229176520aedd227843dcd837f42b18c0fe1abae76391b0dcde38d317ed010001	\\xd00c64a8c12298b63a8d42e2051d2002747b138b109c80b287dbf60923b93a06d989aea5793116fbc457c95cbcee36939da28e3f4872d154a72f1ee9c98cc80f	1649910272000000	1650515072000000	1713587072000000	1808195072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\xaae605d5a56e74ee0f3abea62eb62d6a77abe5977003908ce7a5014db0b0ba59402b1068381d46e58feadec51ac47af4c1dbd26a003e0bc99280356c267724ec	1	0	\\x000000010000000000800003b96842e724396b7a9c69b22df311247af44846a0d77142254d37f072a0c19aa2c20d82dd0dcd5254afb9a6ca541db83f2804e7ca1786dbde7922db57258c668125467fa85252c2e948a63a99cc1869a34cceb6ec5028c909d17e4c26af6e61ca2ac49b0e011f4cf3f2bd37a6cb0c979acbf7fbd644412cf9570d03e7cb982aff010001	\\xf573d7cbbb4156bc3a472fe0622272f8221d9cdfa95acf06088a7ad28105dfaad51d1c3db7c87515659ca336562d87a9aedfe55643b7a263d5ad9fb4dfda2406	1655350772000000	1655955572000000	1719027572000000	1813635572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
261	\\xabfa46faa673687300eb22e2cf4efbb6afc8a426b2c9d3c7f6845467d014959c97a21ca666eed8b62018a9d3d172d891e12efc4ad374cfdb00480e9eca1c9faf	1	0	\\x000000010000000000800003e64f976c9fed448aac288a29ac37a8d969af6c19b4ffd5609a942787613d72deaf95a31855ca2b6330ec955feba90539d86e9f45d8313224e39b0dc342b40a7abd1020b0a8f84d2d7bed2b0bec80eee9f52264afb59102b09987d0111d0ec43a48008abea86cc096edf254a49e3b2d7a5d38e3875e5de8a56dbb8c1b724ffe63010001	\\x9ad7b93eb6526ee57f396aebd2b5774e53cbd97681dfccf5afa847d471a2b6cadeb3f2ff016e0f207cd5103cb23ae2e746c036c28ce918ba1b2d20c87c308b02	1670463272000000	1671068072000000	1734140072000000	1828748072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
262	\\xb3325a5dce25b24bd9aea53d12d97e14669687d112a5f8412157af43786948b797d6df44a0b220116529d03a10388c3fa23186cbfba32f0aa304a390cc595cfe	1	0	\\x000000010000000000800003ab5af0df487226d8e4e1721ea3a203811e78ae12ee55b3f05ef7f5dd85964c7df1fefa9804ff502b2781fddbcb12a9391e900690ba6b1afd34ca19b4ea0ab163f4269e409e0678d3f073686aba9c4ee7f1721e2b681f3b711255e674a179e2f0a257a90149bcdd8376b0c8e4e66ce77d7fd9809fbd3d1de8e0ea10f514d5f0d3010001	\\x77f14ef8d8e204e776bf5652d7ae457433f32de9d86f8537b129e3c0ab3b7f781a92400cc7bc56624d27de9e46e75a0aec1493baf6d3c770d4d1890f570f6308	1663813772000000	1664418572000000	1727490572000000	1822098572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
263	\\xb762f55279c4a4532c7cf1e5aa9b88674eda6d555582af5805de8dbf906dc9960663306e9b1076f1b0667f1fdf25e3ec20c21514f27fb50ad12304b3f5fc50ab	1	0	\\x000000010000000000800003d6688510e3da2fb3f3d7b9895a3a05d5e21a4e46fb0dc6393ef327c9ed6d510b59ffa043401577d3dc3fdcfdf0dea7a75d375702ef3804e84f8b2913c36d741839a28b785da2454d00d70fb7bbd58b9b9332d37a9d00bd8836bc10fdd6a0001055b9b6bb4ba6e2890030b286826082645ee97ea2f0b6821eba281a4c8fd6c639010001	\\xc45f17c7974823357374fb36d503577dc1944028efdf2867a31ed693f78c0bbf07c665332978065be1c7523c3349176c10c2c1dcf8c47f9a12fed8e683eefa04	1655955272000000	1656560072000000	1719632072000000	1814240072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
264	\\xb86ec8710d0b277bff805468c2c164b490cdff145538b46d271fc720188f9b06892aab3842938784620d2c8390062d6e032614bf83f8cfa73133b6077b333800	1	0	\\x000000010000000000800003bcda157f996014da921e3131ca45bf88e814855c9b2b3fe82a98934dc59d8da92ee9e09315aa351f4aa2420ded780d69f0be8e3f4885b957d27502442c29209d7c68f61b261da3d9c5cd1d43f9ef329b8f99ce81261ebb57863b0f8105139d991733834bfeb873b20841cf3d78a97c2c605d8a4b98d805ff59281238d3b8379b010001	\\x181b27bae940a223c543693c866782e4f5949919838ff374a39e080b62c1e620b296039b338548a15dd0a6d505e5cfe997956912934d0be81c93478ad9035603	1676508272000000	1677113072000000	1740185072000000	1834793072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
265	\\xba6a3dd0b861c98f087f40f4d88c33f516156f473c0b50cfc9421fa6eff2244525d7e48a1fa882839f7dda23c0c9be31e61598dd96a23849d56a77be266ae9cf	1	0	\\x000000010000000000800003b091c2edb4eb4732e14cd972332e81e4723ca013415963027c2ad4d9cb09531b70b6fc00a24d87264f1a80954f4a8d363eddde9f982d29e89a5de80fd19f86db552c0392df54e78bc3fc45cd1075f8a7e37239b1f83fd24874aed6b2e5557aebffa11ee9b3594e3c37d665f18ad5095b27ac468ec2841b58c25f2ec8d7998303010001	\\xc54301ea322249fbdd0c0985d07823b639f8138898af4d2a56bf3c9ccf29a5ee6c1b9508c9ca94046cd1b6b7c7e292930e88d5c546da232bfa56142be1ca940d	1653537272000000	1654142072000000	1717214072000000	1811822072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
266	\\xbda62810f7bc47e3236d9260caf8ee3bc84d46278caa65c46a0db3b12bf57c330988f430f8897d76ed116c936f26a3a47a36e4535fba979f56d8fe344b0ed5fa	1	0	\\x000000010000000000800003c04fd161a5807cd21ea3fb0a4570c8ecc9d8f7b88f455c3f07527ea9cdce2016123d1d78d3b04102584c9120b24d09b2cf4ddb03efacee1c1e4c9373e23e32f5e69a08b5444a432e21c9ac6d4a5d1bdb1125c543259893589bb89efd9369700df18dc1a103a34e41680c7960f430ee369a07994a37a067a8dd2d1078a582d7ad010001	\\x691c753b0c2784282f013072d3a76b39b7f7a6db81e8703f8ce1102a8228f5e7627d1213f06915d31ae19f7d70ff247c23cf2c702e0ac6d7a1e72d84e235690a	1650514772000000	1651119572000000	1714191572000000	1808799572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\xbf86a8195d97d3e4afc06cfafb751fb8e021aff3d984859a5d9e771d583b09cc0102f3770c48666263700fcd9b23d6da3251413085b4c10e127c513f0d43c53e	1	0	\\x000000010000000000800003c17a59bba260bb8b7f210571f739826503dcb74e7f28336abbbba585fb23a18db3bf2973d89a46ac905aad23806b418888d223dfec87e5e76400abc43869eaae0a6dee0909807c27140b682c4771cd997562302498d4cd88050bbc4ede1ff8ca19a0d0e38f71a548989c95d2026aad47cb28ac1ce18be7fc99c89cff6566bbb1010001	\\x0e7922a8511f966b157933c5be6b422fc70c3725f53c7f2681f1ed2bfe1f7535d6aae0ef5d39d4c8c43fa72e712a5ac7b6257c9ef1bef336b621258a80c8be0e	1655955272000000	1656560072000000	1719632072000000	1814240072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
268	\\xc56e314f6e691a4bf28268e9602807973e041a04f63add1c0f8104c5842ebfd626e3cf03be0f45e232f287609e82fb25e9be310ecea802949ba99eca7e66d046	1	0	\\x000000010000000000800003bc4e1f830a00c884a0ec07c2f449a70557507053c906341cb4c8908d358c678dcafa8cca8bc3defd5b23a838fc4ed1adf0856186580220f73b189a3729976ba3f0eb3503f26200de83e51ce7a13d3bf4ef0a3e845e4323bb789baba565d2e6f58696a7b53703bd85f02a4761e6a9cb8d14d55e0f26eae79da20ece989d328d79010001	\\x623e6403f31c032eb0be32f1c2843f30f6a03ec7e6209641995d170458a07e3fa3b56b325e2996f5cfd6b8c4aec6431062315af4282e674ebc38f5061fd25603	1649910272000000	1650515072000000	1713587072000000	1808195072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
269	\\xc732e344e89a40b36b2bacc061cb9daa7e56304253e320edfa9d610dfab5bc8a2d328bca9d79538b953665d1f210db023bbcf78930f04fc4368dccfcc4493c1a	1	0	\\x000000010000000000800003da3b4c2bfa3b63324d2cba00901b31c0445f9d3fa51e762081a330d22e57f648e82e8266c60680a04dadee22e7596fae736d9bfc5cb158dbc474ea508e84d98d50ec8ae0e7a9d5e7f82c51749f3f59a7a74905401026ac6064f37aeaf9b88f7fbefb7794f855618a15d73d4960b3c9b93ca322ad1f9cb9bf091f8dfa69cb9cbd010001	\\xcffda3feef87e4643f8ac1117c5413b66f2e66851ea452f95c16a174b780a19c83fefc7a4d725278512917ac32c0994618fd6079b283edea0ef88df4863a2402	1677717272000000	1678322072000000	1741394072000000	1836002072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
270	\\xc94a96618f57ffd84fff7116859832181d1565b054a431657a2a5c0cc29adf5956b86b4036367c89648b9832ed2fc4f930c97575cabbde35674523d4e6ec606e	1	0	\\x000000010000000000800003c42eb13e75e3a9c36f22fe85a7991fce11503f3f6e311cb6dc7d4b683874b30b255ab153ce3f778b881813acadbe8dab5897479fb634ceb97a49643999b90e6eb6a24ba71c96526d66f85e085b1b2b77bde1bacdaacdcfbd263bc49f3da9d2f0737782a590ecb8d2670055956d02c490a7febff670b92b08022f9742cc95d369010001	\\x62c7f3066d2cb8c639a51440748ed839d09d6c5a805552b222c068bd1dcac1d379250f5e6b692918a6bc8b2ca4f42651c1e7035404a4b236938bab584b96310b	1652328272000000	1652933072000000	1716005072000000	1810613072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
271	\\xcae623003056150384904d7210b658a93ab1873d8ce7d4295217c8d2612d475f2f05013faab6d9a6e0f48615179510ac49be8b3e84e67da3bde75b8b43711c64	1	0	\\x000000010000000000800003a97b99a30f296b9100d9dc1f35f25f30667b4f86e8606eeb8078fe717a6e0c1f2c16bb06eb2c5ca4486c118c21c3b3358cfe4d65e40f8387c3bdecc702e45ad78efdef04dc8e929ac2a668a6d624185579fc78fe4631a032e4f472aaaeb1c5df7231b78df4269fdc0764b376e1d9964b7e161b5e2cdb5c6682065c799eb15775010001	\\xaa4ec88aa529488605e0eae07d7239106b9139bcf90ab37a130f208c1aa745b1234960588df2116e633be9e01b4289cce29aa195f4059313229a1a901a992306	1655350772000000	1655955572000000	1719027572000000	1813635572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\xcbda4d71d31382ebbb6ebe7d9b26453fe0f4b33aed6ffcebc9ff15e2068000408bb2d7e28672f349e10b90ec50daceeeb723632883409a18df3b078cdfc5df6e	1	0	\\x000000010000000000800003c3713e0086863c2b44768cd917f34da6e6bce1c30a32e7e43a70062ad5f756a97dbbe1a9593fb00f2eb6fd2bc1e40700a8315648daaa75cd977e27db49eab973538bffe88f1bc24b61426f0b3412c8127b398e298029ad3f0a87904e464d5d0866fc8e26346c9e4a850493ff06d403cac8d2370f729dfec917c898ae9df377af010001	\\x341eaa0882e6d5662ae21420649286fd925a884eaea760959729b84251e8f918c642da18d8e9750bc983965f9a9b7851ecf12626143c0ea26929d21e11dd3207	1651119272000000	1651724072000000	1714796072000000	1809404072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
273	\\xcc8e8707f81ac490fb6489976d0dc989426847accb0f3ca7adb92c6a45ec68d0b2585a6ca22e00224a84bff4d09ef4bf7e6053dcc25cf9269747d51298052d31	1	0	\\x000000010000000000800003d7b1b41808bd97a7f4c7bf436777776fc8de5cdda3bb4180798db4594a600a39ebb0fe183563dd7c675b14a5a829e0b72b31d241218a976f19a80d459576a817f3328b35706c1f34438714c2d2b4347f812aa90804657736523e80e560304ab19342e2e648c668fe335de84481433c6a176bf987decb066f62d34e332a7a54bd010001	\\x6ddb89caeaacb6496253fce0bbdd6bf261f35bf7f7c7cf80e8c852ec86a9b7822f2f63af357756b476b791b183f885f8de31b524e947bf1de6c41fc76efe1505	1666231772000000	1666836572000000	1729908572000000	1824516572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
274	\\xcfae6d979ea6ff0aa498decbf10018d0a2b88d40ca6b915de79eaa7ce4c0109da7b745cec20cbf1671c7d27d7a2874d002475d4e963256d6d5583a4df624e0d5	1	0	\\x000000010000000000800003b8036cd2fc9255927a636cb2e702e05607ace13701e9705c51fe90ce77a90385e3ee09c295e9adcfde888125766a9d4f774caa9ba0a921db84dc90445f0cb8509302ff6be728db4f6ec52e541df08b3581b361f6b41276f5df8eb1271bb3df1e944264b9d632b91d7deeacbd86fb46acdeda53f29f2b5f4f61d6451018c03f1b010001	\\x3c4c653fea648be9db6c81610b4648cc4f027d28d2a63bd57f1af52bd375111909b1ee1fb193e316d334a3933b0589d6c0d16de9285182a1276588a8bd148302	1650514772000000	1651119572000000	1714191572000000	1808799572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
275	\\xcf5e8292b4354ff5b34db21f48590f93dc871c7c3a9154cd86eb4e3f7e68efa4d73027daa088fb2b2af25b3ce0d6b0c976087dff216fa3c645a0c454841e4a4e	1	0	\\x000000010000000000800003a2537f1ec5dc370336e9e29ae50c0581363c6e456adc312b26d43375bea37c040eb116bc28357b5f88d5f95bf9d5bbbcf7760eecb2a38229031c0dd9e38d52ff67bc9f0b015561dde0278a5654c711bc1cbc850d2cabe97be32a111c97a9eaa04c2f1a34300b6d4ed4fbbe6711cc6a71af9c219af17680ad31040b5e428db54b010001	\\x96e9db0a8d80c667cbf1a8cc645cdf39613ea870dd4f048fdbe23f9dd632c7d2267465b2d8e6cc18dca15c658a430cec0987d418e393d62afaeef98c901f8106	1660186772000000	1660791572000000	1723863572000000	1818471572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
276	\\xd0a6aaf40f04040f630c2a0e5be26139326e23b42e56b463a7f7ee5317dc1a0e2029ba2e43d0c16af09d0f6c23cf61634609317315576f238fbd131f50e0a18a	1	0	\\x000000010000000000800003cb36442cfd27aaf91c780faebfb62fe0379660685983e10ce0b23a5f0dbb4a8825cc97308e63dc94ca3fca4569cb50189f28e19677a8106f2e79fbcba0f644364f8acc8a132d8091748aad725528f715b8c5ea50f52bd5da4917fc5d4f8b8eb3a5beb44536cb6ea32001bdc2e4b5508e503695f23fcc36425efa1a0b801feef1010001	\\xdcaf1b16bb1b488e959ab5920e58d4362d65e23483100a4215a2bb40dae4f77db41a7ef2de2c5346824c6b0e31d333617a0255ec614a4f691ccdb85a7957170c	1654141772000000	1654746572000000	1717818572000000	1812426572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
277	\\xd6eecc098073db970370b611faa6fe70d4f3bf43f2397abccae3c1e6175408871d9adfd245b1f92f5c1ea9bbf724efb0b5712ad097fe1e7f2bb723b3569f8a79	1	0	\\x000000010000000000800003d26cde5d9fb934ef3a73c218fb7b28a6d6b6f34eb7c5d52315eeb39472fb90c4f668e10a0047591f5a5d9bc88e3cd310d1951885355a87a8c6437d9358c33cd470d31e495df0491c652e0a9d93d21330eea3fc519932605df5a52879eea3a4e167c6163b74441a24f6c3b46e843ab99a8da1cd7da636e0e3bce56f08a4ed5c33010001	\\xa2ed291a5e45b18514812f39d782f2d2e97e0d6a1129fc4b9e60477fbb0158ce4ba3ad031b83360dc039a690e42c4a250a1bc2ccbd0f76605e6f73dc6a17d30e	1669254272000000	1669859072000000	1732931072000000	1827539072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
278	\\xd7e6993d8e97050b10fdb5e56e9a6d4eb4a2deaf810ca9c5172c7c32f8bab42e29dae8493774736f31b49f97e4c5b64e6163b39bf2976c071d29e8df6f5d48a5	1	0	\\x000000010000000000800003b35e049b4dd49c603ba3e710ca010a5450e93e1bc7fd09032bb19133683f918718d1365dbe10d2cadd95810bf524b4befd52c709815023dab120686fe88392a6968b553b398ff16fbb33c268a7d440d4b1277124bd8693b6a7217058327bdc563dcc3a308318943d0edf9e5a597b6011cef35a17598049d480223b6a23909cb7010001	\\x38ec46bdd727ecc01da7651b3e6745a9c23579ebb078c21b5a37e895001322f9587c34cc0f6ca4be288c1ad8752dff609ec8b0d5cea80697fb2e1098bfa2870f	1669254272000000	1669859072000000	1732931072000000	1827539072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
279	\\xd9fa5526dcc29bca739776da6bbc8347b1754680d3d3eb08cd0cc15d579e0d65185dd0e6954bca9eb92bc66a545f431b971aae16396e97dca46b7579d13fe5c7	1	0	\\x000000010000000000800003abcceefda6db1bee8c159500407c91df11e5b214c308674850229b681a70fbd25641b03090d37d501fd933e9b3fd7412be61e4468a998934c0cea568e389ca607849c4abb30b84fb63c8940f114f9d7a96f229b695106998cda3a4e37791327fe9b0552cd01c5934bd5b3ad147f067cff24d4d357e9001bdb5e83c7b23b81e29010001	\\x3c01716afdf0a68698ba881db201b04ee79ceddb60a0b75137ac968d5f9a1787f1457ec4b6f99ff8683bdf9e7695f4b2de482b774b57bed86b62cd04d58fb801	1663209272000000	1663814072000000	1726886072000000	1821494072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
280	\\xdcde80ad544f9e816098534cc5f3a84a4980656972b264b45fdae1315f895cfb33c9677b72c249b0cfa084db1cf5859df6c4ee4ab0a75d104aa406a9eef9d620	1	0	\\x000000010000000000800003bc2cae5d96207a423c2c0116379a8e505ae56c5b0dee30cd19c50b5eeb7ffeef3df96775bd33864deee8bc9ab2e8cf6979cef86f649703a40d6127c59ccf4724c1646391dd1b6e2cd87ef99b732c816ee854953991cca5ef3ed337f9f6ebc2e08ef41c7d0c58a024af94e2cbfb5a1519704f669d290128103ad051ba41c83b5d010001	\\x02c4d00eeb9559e75fd92a8e25182bc80f83617e2895104b77cdc8a24045042d1924f1b867426479ca9e97a276fe063730ace7f6e6b6c321460c515e273d3307	1666836272000000	1667441072000000	1730513072000000	1825121072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
281	\\xe21aff8fa3a47fdc3288b1c1ccbcbcea8a25b6d009c7dd08fdeca1de4640f64f3473c782d36d4f5e71e29ca4c9d594e6ed43dfc857e7f70756d823acaa6b5c9f	1	0	\\x000000010000000000800003b68a3cdf72d4858dbe82fd7d8e8f28633a137ae0eb3edbcc2600231208d587f40ec917fd019f666153e9f90cf17c23aabef67252ab2c438960268a0b4fc08792f1f150d589f33058669ab283982896db3d6b16c595b63bd2ed173cf83cc8db3c1186a8f5acd3ef90b82dcd68dd3b6a5cccdba68951920afa08b4be33567da919010001	\\x0807ecd4b291655ca8e1e1984d525ac7cc7801d7bef0c123aac2cefd397fc6d1a447f84ab6f54eb871db0ac3b9f88c2b3b28eb7d7d4870305a837003eb38850b	1665627272000000	1666232072000000	1729304072000000	1823912072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
282	\\xe20a60b7a5fe9ac96e97bcc81bd78f0ec8cac803e2f22502a763cc3a5b24f14da7903811e9fe210b994a1ee99051532e7b646541153b8f03c8c0933f7bf6d787	1	0	\\x000000010000000000800003b0cb12d69389ba596925e75216ad37fb36f8eb70125b0ca20c8aa2fe8a1730fc3529a14006cb0abafdcf8d4ee67b34d52367be277d222b765ab8a56f408774534e6e786c23cfd5f17e423d151442073c3b94e88904fd869b054ca245d81a5b2d76306b873782cd2ac968d23f22def7fc5d324e653cd3c19286ad6a367d4d9085010001	\\x5f59af234c054fc70fb50e171b2fbb5d5c045d1a0aa46c9e7c83ca991ed0b4fd62fc6597ae65f39dba58c320d3cd7f0ea58243cee77f3e6e5450e266ce4d9007	1656559772000000	1657164572000000	1720236572000000	1814844572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
283	\\xe8c6068b9ad0f4ae29af544405f09ef7a367d3ae1088ed5c4dbaa3ecd67fd15a1ec627b4ad9f63815c2450722542605bec2d46cf0f1877ccae09c62c23277994	1	0	\\x000000010000000000800003f3709f6cb6305f61a6a64f38d2fbeb53b95f141427042fdc7bec09f5a97aec630c332d9252bc73b300e6c037072aaa4842292ef0e0e014c9ae414dc297eaac828a698441ac4a4e45de1c30fea0c172062187dd57cf9914579f4ac0219c55989475a0bdb2291f9d48f374476a2c4734bac1fa75ba4db9634fafab33535b3e0195010001	\\x80c140990a18dd156fe6510d7d9b4c51b2b5bfb213e12fb5516cf02c5d7e263d6a595eed36cde7f91abc3365877dd5271c4450a84d7345d4e1855fe346077306	1662000272000000	1662605072000000	1725677072000000	1820285072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
284	\\xe99e767a0b541a6108c13a0b755cadabe77e48931bdcc10b72d4a8a4acadb2d1822d1fb632447709fa5e4d78356b0af41e0e5769d8f9461ae87b9733865917c6	1	0	\\x000000010000000000800003b55fc5a762dd9f421e7df134c744da7b37e2d7b88880f085eb54ab142210800c83a25d806bdf5fa843de8c0be40491598ce6e71e24f89798c171814921af44935e85ed9d76a48550853ec82ff9877f1ec04494952ff3929b38dfdd26a60f99baad34c63398771e5cd5f667723215469705f131785e8d127a78e6815830bc377f010001	\\x45f08bf6c6895d19f13a8d4da4518f2c3d54b1707349745764231d5af2c6474de4af0afeec6e06db0245f98d298936e5a3d4157d6ed347b282917987d2ba060c	1651723772000000	1652328572000000	1715400572000000	1810008572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
285	\\xef2e4a62bdc6f6f27f3f9ae498ee0723f8927b6d59ea3b393ed9ca7145d69a131953368575e7508e357f24dd2c96fc7571f1a3faac2f3cf6896c033891268831	1	0	\\x000000010000000000800003dda0fd5c41ff2ed9cbac416d268ff94e4067122993a331b861848bdecb8aad09058e0a3deac8db292862fa138f3d1c9c080a6a5d3aaa2a8fcce8018bced22f34a5ee14393a8414a7a534e335db9500dc905c4c903d38396bcabbb33555de23c1aa52772ae71e49d32fce60f501517ae701bf9fb8c8b6c64b1e9242e4f0d7ba75010001	\\x1be877a5cea19aba7b9e01899275ba47d9a37783b296598dfb7579a6665f8cbd6b5996abcb5a82359bdd2303c6c74ad3402644a1a68a28cd7b75e32dab1d3a0e	1658373272000000	1658978072000000	1722050072000000	1816658072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
286	\\xf2a608f9181a4d38467d2088e93e0b8d950460e5f1d67f8991808330d83ad668fac5539e46d73c33865a57a12faa7c20845e8fee12d8e516df89d8e95e5589a7	1	0	\\x000000010000000000800003ee7253e05618bbbe2ac89937e500d208b12290671e144759494ebd04820640bb87f79336ffa89c7f91d84d002670648bfce5ed1c739ddd4a613362bfec22e14e003f68fb4cc5ca8e73ac1251c424e8ac2f7fca23e3a4f4801e035e9fd0e7712531e5196d5da535b63f6cd0ae11c425d4841bd6302f7c66934adbc4019bd00a7b010001	\\x017ae2fe750b3b7ece91aa142d56d043c10d7d9b05567acb78a9749c06f12ecad068c2091e4efc27e6f8eb30e8f28865f55dbd02c049407dede9456c8358c406	1662604772000000	1663209572000000	1726281572000000	1820889572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
287	\\xf42621e8d26cf8c2d3cb5799cc68fb5612b101acc55534b0ccbf6a751cd96203a540ca3ab5c5d57e198c994650162fc78b11f86cb1f6178e1dee8dacbb4d9201	1	0	\\x000000010000000000800003bf22666f492c482f435a922b385234c098ecb0fac2c6bb4093054c2d771f3c86f1dc1f9ca47443d9fb1764f0145e59921a074370633a2fbecf8e343c18e3cc56443148f3b6decca6414ef98f4058d5d4f5b55526958cffd0eb88039583344be2eb386c9d3a1fe6fb14a406a3416f9826e4ac00c69e9416cfc97458ea4116fe41010001	\\xa65ff505288470a6f3ce82702b212a2a2d0cef44822d0542c601c7d1f16883dff17cab1846a611d9407f4bd48aa8624455f863f2f9cd23ffa6973b1e9d5ae90a	1663813772000000	1664418572000000	1727490572000000	1822098572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
288	\\xf5d29cdbf7a865231b2289394157122523dc9140a9636712917a98f16924a21081803c66bb9077b63a1b89b21bb4040a76ba73a26ccd600dd9d17724d4a8b1f0	1	0	\\x000000010000000000800003d0d3ed3fa9d3e82a096703a5afdb91f4bef80f3f95f25e1f585bbc0cb045a46705bbb65aa39b6b0c937c3a2181276ab684291391ca61b8c5b1d0833fa2bad92160000fba7974c2694f70494562c39fb4618b553d24d8cf879339f6a33c83d2c2e2ccadda0c15f482acf3151146f128470451a0cf38ab0b545628664c2a437327010001	\\x14758bd16c4619f5748768bd863bacb1e2e1454df74936e93ef32063618c1fc6492fd1bf51335fca16cc41b2dc03911d9dbd21be907ecceb03a27b7449eed103	1672276772000000	1672881572000000	1735953572000000	1830561572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xf50ad25c5df9c04f90472de93213d72415e6315cd377483bcf6dea824c78df9f4b403b9fd71cdac9ed9ca39b9f80ea5c83a243ff79cbdcaf0f05aed5ba11e03d	1	0	\\x000000010000000000800003a9666033c3f3b9eec216ace78eed0967c724d5c5960a7709aa730cef20bc536fda59da61879623eca25d53b2681e28f9ad7faff61f56ab0155caf9cdbfcbb93e19922e617db2d10f9c0b2460841d725e822844d8bf8b6b4aba4935f62cee1396605169c68cd04435d8dd3e0a0b067c78e7e8fedd23a8a6544e4f6fb25c46cd2d010001	\\x195e34a30532d3e868b333c25e692569e8b8d214288d835b644ea76206d285fa91cbafd01b4d45a4e6315976b0f66606a92575c7cf8c9f99b5e55ef58c120509	1678926272000000	1679531072000000	1742603072000000	1837211072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
290	\\xf9d24dda712986c5c10cca233d0099b4d6a4249cc6a8f68f6bca62132db1a21690ce99c2ea83b671bc61e38c6f7039d4903650c0997dd06a896f3d1d2e144dd4	1	0	\\x000000010000000000800003c7230dc7220ae4a889c32b7d936318ee314ce29b5c2830e28082effd87309bb075b632b6796d5857e7aa5aa88e967a60c33dff82b4142d4fbf0d0ac5b175d617d271d83f3e35a070152542a88a97aee9a562530b6c4de817503a6bfcb116192442138fce17410b74c4a5fa7c0acc21880f801dc4b77a1be668322a6cfb311dd7010001	\\x12b4885fbcfc3100bce268b4ecfc9766f409196483cb88380bd17d6e31a1c37ddcbffb6ab1ba5f59058109ff8953daaa245fd03f263b909eb205324c6fafd508	1648096772000000	1648701572000000	1711773572000000	1806381572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xfc365a79ffff71cb017dade6ed2319269d404c164a258913a936239614329de18efde069b1762063a88193fc2a76f955ad82b066f164db268b843a9bf44fb34a	1	0	\\x000000010000000000800003d1399e570bedf34e8a801fe195e5d01f6e25ccee247155cd9d3a3bed512e8a3d2c8c9b532b9ab737d1b1d728aecc7f6efebdd88ee21fb678a9cfce07b4fe00817700b4ed9e92d2566833c4792046dbc3ccbe4023deb3c1efa361b9a8d5b2458a4b035191bea4801ed37f343d78e978f97051b73116512915c0fae688c60f390b010001	\\xbd419ccaa87975f6ae6e6aa69d31bb235dc1445a749ea238cf77d6ee59a466573734e6af52481e76e8d9a39b6156f5db46c8db9aaa59943712ac2122bb221209	1658977772000000	1659582572000000	1722654572000000	1817262572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
292	\\xfd36e0909f8110bfed034a3f4d940803002c21717553a24f355133257c4d70d553ae2b9c69390df26d2199bd781e1d561a622ad0a66d63372101d3bf6414b1b5	1	0	\\x000000010000000000800003b8d362f4c8039f9bf16ab21db4bed0e60dbea8f18fc4152c414b7848a2bd59b2930a6705ebf043818ec74de05fd129c10411efb76292550c6fc4ac3841c1f78d54372f1f64355722004b7bdd3c25891477e57fa5d669be31c0976858445fdfd3c83944e7f83eb935de38afefe11b7f3346f35e896068552f7f820259ef26eb17010001	\\xc4a2ed7f4054a8c8a575d8e5a60a3f2f0cbe584f203acb5b50807735c858329519909f60e2dba00f8a5de43e396fb06ab546a8838326961b6b6639bb16e8a00d	1649305772000000	1649910572000000	1712982572000000	1807590572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
293	\\x034784a2c4fd82a04f77814fcdd38f04bd61788297c03aecfacefb891715110a912c90f30b389562826f343dee574f3478321f290b923c9bcdea9ceb348acb83	1	0	\\x000000010000000000800003ab0f41acbaa5c81fa6097d9220030374226a015d4751457011711c653f790b6e692632384b817e3340af09ceb70743fe3996f5502fc6adfb0e86d218e9662928bea66160558300a3146b7d8953e58e090ca635e9734f7086f72492ea24a61f06052d56663484e31a77bff5544bba8ddb6bf38ec1cb833c8a40e88124b3ad2ac7010001	\\x2bf5e99bc2d521555692ed05bea00fa075db5797c8d3f1f2ea44542a4f9ad712f2389fa41aa56fa5bc389a461c78342c51930e28314ca0febb100ff2be067f0a	1654746272000000	1655351072000000	1718423072000000	1813031072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
294	\\x03d390eb6b9c8bf068541f0c50c97190c46a7805cc2d81306abdc6c561b201f53f614a7b612107a024b02e9451a4e1f4cc8b7bb2ee86def841b146b1a4539381	1	0	\\x000000010000000000800003e8b2cb1b105731f57910a240e84b53a2db3fc2e3e3defcb246a7847a1500e8749c4e3f3f1c0742ec779dfaac9e79e95433c447f65e962378199a5cdb7beff2ee9db8e19d457deaa8303f0239e38901ce69c49e9b741e8eb63cd10dcbdd36e12696d7f4c7f36d700845c3f3a7c8412e67c8ea0eef24fcf4c099e8ee3abce2ad1b010001	\\xc2b3ef0041cc0ea4f14708c50c8f5552564c775d6f3d23dc6ba5854e117d13c8ed9dcdc7c4c8896df11915bcab38e641859039d2ac44e30cb8705d42789f4005	1672881272000000	1673486072000000	1736558072000000	1831166072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
295	\\x040fb4db589ebd14aa7fbc5385ab747efd956c4ad6f46ad1704ca22b1590d5f33e4e8e34d180e5dda6d71adea5df3323a4af2e5415ec4c574be3795728c99149	1	0	\\x000000010000000000800003b8df407fbffb4419ac6e1a4d0030ab7210c953bea6f962254bf673a0c2069ee523ac93d64d2022ca477f6e30b3f9911ce52bedddab78fa4c4b2d2ad430e44393e59999e8876212e5924c2c65e8153e95eebddfbfa8b10ffb3ef0ca2b81401599c5ea55d125f99866bf6687db071d1c22b46b8c90dd77d222c23002f5644896ad010001	\\x41b49b15253a3b56a21fc8bd647b6a73cb78222914deb59870ac59f5cb7817225a179d24b512fb98813fa3cb055e47eedd473b553ae3d77f01c61f3b75e87e0b	1665022772000000	1665627572000000	1728699572000000	1823307572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
296	\\x056f4c891a7fbb760c184a3a3627c08e769f658b96bde0ded4a8e89774907af207d5a644de79945ac75084ce676b206a71df8b1399f210ad505396190f503a0c	1	0	\\x000000010000000000800003c131203f73b5ad3e36c24b92c2d995754e3a7bbade8b5cfa07785345ffe2275c3762ed36b807503e0866140204edc3235a701ac6e2f2438bef1729a70d313b6c0bc93972cf38e705af4d433094728b7ca69c43682ecca12448a18aab8479a088a1774bb24b705adfff4a90fa6e844da93de3360ffafeb6aa90748b3d700a8719010001	\\x9b8754f400903534467a83b41c425d51730e9e4a77a579e35319c8b45554e20b197e2c5f2da10c4164f54cfaa8c6ea471c8cd0918d7a0b71fd030646159d3f0d	1663813772000000	1664418572000000	1727490572000000	1822098572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
297	\\x062ff863d55b8cda0387c12058d8d769fa5fd0ac87d5e2e4f8b24a1773447adc5c6a8da88838f1a58ee5472de65433080650a1114d380f8aecf3f3a81352baac	1	0	\\x000000010000000000800003d993fe72b13b00b5426e506fb5428bb56de31a65dab0e93f74a0a701ea19c580d610f829b295be07079e988712ce254aa7eea8aa10d9694cd430bebd3aaafb7ef9c2f0011709fc9523d5bc1e5b145f43aa7598efd8f4e3c298fbf950d0d711d546932c11d69784ad214f94625df7d01ca2f31274c4e6d16e05308b21bc9ec1cf010001	\\xd312233547267f67f27d8b16aa3b4aaf844622b7ba680550ca63f438b7cf72a45132868d280c5afb0380cf2aed44171192baebc058640745ced3981ef0761700	1663813772000000	1664418572000000	1727490572000000	1822098572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
298	\\x086785feba7f80f8b4d227ad969945cca9ac98c4f40c517705e2d740de13547cecbce85e5548415d99c29d4fa6d3022f88b96c6d6d375251bdcdfa69efc6da2f	1	0	\\x000000010000000000800003cac5cb65b8adc6a6254a10194600f0b69f906f92f1a52c569ab903e6143e38e7f3330fe644474253944e941365acacd48bede852be8e7ceb5ce0ac3401d94a3c6668427a28728d28c7be605b26f70c929379f267a1ad090beb98b9113740fa93bc9c3cfc52e9f04e4d86e20a886aa813ac7662d656aeb2971e8be0a6f465ddc3010001	\\x544d9461063f672ae083276dfcc095fb0df119a21b5af06ec0c991c3eccab7edfac5018f68ce850024311858df266d26b542dd7cae19d0675d903605b4506b01	1658977772000000	1659582572000000	1722654572000000	1817262572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
299	\\x0be3f4451426c23d04d713f9b932c3666ace0c69355103c9553d555ad7dbe8372904a2cd85fe90420c8281379eb4bdccd9117a4745cdae55fbe7bd2eeea30e4d	1	0	\\x000000010000000000800003df7445aafce4be60d9f7b3fc937f2020c4d5e66aab78c1a76871ac7e0a647339b580a4be44467727547da3c4a8337bc10a49e1bb3299745a11a07a7c4bf9b5c6a7d5f4942ad73a99d5ceeb361dfc34292551c06874b624ed3fb8bfefa8d0afaccc8df60989899388d0788792bc2e9effe388f093a73ca76cf95ddb6674879a3b010001	\\xb08c9b1101b08c3f63a70aabc502c2b6b20a040887f1f946ec0d726d5b8c9b990451b264b829819f4d0157f2e4ff3aef1b6c0aa6086604fccf20d21f009a8b07	1669254272000000	1669859072000000	1732931072000000	1827539072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
300	\\x0f5fd69a5127f72713bbbc6e77a8e02720065b7b00bde10f029786ec80d3abd18c9aa5db8507ca7f0a88f6e5a9b886733484a97829723fcf0c92db78b06e2d66	1	0	\\x000000010000000000800003baea97b211097a45ba38ce42285191fed1582e203573b0fe3d0595bab962242fbf873d6dc34405b75ac57dc96f3fa0454776c66c94f465b37c6b8e5a8ac23392eb6e35ba06eee062f5c26761a3dfa0419b88597148572ee911b4ff3b2a7438742a8e2215736ea10f4fd490477d96174954b97d3bcf12675aebda8229c799a617010001	\\x3efb7afaa346d84bdaa579fc4c0946d47eb95bfb66a3b83ed52a95101a4d7fb6cbb4c7502772d03a3f2592d7c67ec5eb6784d552db5cdc76cd4bf0cb84ee9d0f	1660791272000000	1661396072000000	1724468072000000	1819076072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
301	\\x10e72219be23ada927fd9d9168bce88d7ef2936633eae2cc8b2152198ec3ff4c8da606c046ec9be6293a0a086a1f6f6345d3ac43a8ab8eea91585c6bcb5313e5	1	0	\\x000000010000000000800003f3d916f340c1d1fd8e7d858579cfdc28f2d0f6cef223ea286d4aee1f12d389fdc47a21ba0442efafa76c147ca2aba624dacd8520d80cec6594d2f3ea5c08975beac5eea2a3cfd2fe6d30a896483fe4137492732dc74546ba8b3091b9115f495af4090e214d6105b1906d6b1257a04cd239b2ff5c1b001cbcdc9bd33fbc2d3c27010001	\\x345a228823f076124c6ea09d189d77b1b785fbde56e4c1d7360e8136edaaa871e0f7e02007d96fb320fdbe752317ed4dc958dfb8295c52d1f136ad702efb5d07	1659582272000000	1660187072000000	1723259072000000	1817867072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
302	\\x110bcb843b0bdce2bdb042965617e7c8e9846cd92a730529f7eba379e18266c61aa237e3bd2c380ebda9d5da84c96786c4e9531ab5a4980b7708e1978f219dfa	1	0	\\x000000010000000000800003b89039e67905ba9b4747853466fd67bc9fd0b29c951d579d8950b48927c3055daadf1fd9a288df4e1fe15ae278613e29d3180202ab83c4eedcb293a90d48faca20557aace9bf4f4914becf1b24bbc8fa3e63163e35796261febbe15d3758c24d82a1cb92a00ae965155998e09b18d76c11a162574b3ba70c67c494a4ed60f6ab010001	\\xd63e613c813413969041a7274f6c60368222fdf4b46cf7d9ba04623f7345679e0e9b289c0f1e0ec6c46af8c258f9ee69f44b83a6fbf8123d182eb76d571a5008	1659582272000000	1660187072000000	1723259072000000	1817867072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
303	\\x135b46bc581951361cc8906d84cd57f115202dbb40ac0657bb98054ce5348513f5a435060b1f376025af41750c0390f42dbb4c41d47825bdc5aba51341e2ee25	1	0	\\x000000010000000000800003ae1d4ced26b685fa077b43bbf4c9c7309528d6306b333f08735040442c880031c8e1ff4f13f421cf0989c4ac497672ee79d3a35d3a99b99bc0b6e0350a089b666e8f145073a472c715bf50ae472cd07df6556b25443937c7e18747fb3fb6be434e874939db1027ac4c702cdcb8c3a14fe57bb8acc33890e2afe35fed0b5f2797010001	\\x75d4eb89ece448a1bedb0b301a4b62ef717ef933589ceea987aeb8dd339c881f9db4c828d50b4085c11ce1994b14e5244220df720f9c807bd616348d5c0b8c01	1671672272000000	1672277072000000	1735349072000000	1829957072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
304	\\x14c3afaa36c3b17d4cad18e10befd07181dec46f1d5e9d9eaf135b9b9b25eae07046c1c8b5fc9d3ca3dd14a634dbd9add0b0e1ccec2784b2a7adf00c46b48607	1	0	\\x000000010000000000800003d18c9e3be2c7cf7d6268cdee19788e592cf09f3836c36788e8e488428664213a5c9b40cb6c73fc1134252b79ebf58f2b2da091ad6494e081ef335c262f6bfeed605ea53aed0957d5b0a7c964967b43b6eb810c14865a6d34caeeb70ff6f282c8269d23d095e66668c0fe2bbf0857c0e21a3cc16b58a1fdc3af91eb4f82a40a7d010001	\\x4f19e18905a0ec6d48b22875a8852680c5bc1861e1947f9b3448c23b3d03fd9b9901c388f52908138ad38724fbe9fc34064bf9a6a47c903584adffa5ab93b302	1666836272000000	1667441072000000	1730513072000000	1825121072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
305	\\x14bf98afff9640f5e5eb00a6c831bcfd3f8f37a55f2e085ed8c9c0f5bcaf0dc029131ab17c59bc19cfd24ef6f12053879cd2c55d5b321c2886f6d9b69c86bd98	1	0	\\x000000010000000000800003e37fb750ca4a51391a403ed798de8fb1e7af156f97d8213577d0530c4d3405d418d6b244c6c25bb682daed160e4f3925f43f031c8fc2f1fa8ba5772478cf1494511efe30f4502720d7a8e224902f114ce81cbefe02dc2941dbd6d000c4cfec192bd742f90dbb41d4b4a6b04f27dc9b8fc9b61a55d20393d38f9da260f0a40ecf010001	\\x877e0c89af44c7c9b11f8cb483400b914b087419c36bc55970391c9e7f8d1bd1946f8aa0f0cdf4a89f1e0f59cfd0c1c324bdb441ec3b5d2db49436f6928e8407	1674694772000000	1675299572000000	1738371572000000	1832979572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
306	\\x1427388fc27466a4e347c09ca20b3faf589665a9b23ab4201b6cb9d2c8e360dfc1238896be3569167a7c64171c23c65ac8b88ce12cdc1929c598ab1e6ed1fc29	1	0	\\x000000010000000000800003b875f9751e8495de7c77ae6e91a748d47c8d7ef13e42d7da18587c9a3ceabd0e549e9f3ab3296ac2d3d5d20e8b37f34dd00ba19c2124a3ff06d4d81007e1d6d3d2b1bf3c2cb2b91252596082e86aeadf613bacb0b8ee8119e138e1c3c283dc79c5de5526b88ce3e4e2e88421845b9bc263f9b51960aaf2c6956b95991a34c313010001	\\x1f17e26c72d2ba4a87e60c1de037f838bd5be8982bb809a27aff07e90c17e4b1b6878b80b9095feff8c14c3d39bebb841205e82c64b6bc65d79c052abeea240f	1660186772000000	1660791572000000	1723863572000000	1818471572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
307	\\x15a38f576f13115a03c6704fb58c3fdf286bb055ea48c4aa691f007a2dd26475fbd70336a97ac4ca346621e8f11ff8d3124f484dd615a42bb9aa23512e100e31	1	0	\\x000000010000000000800003e65e08479a54f2353c368c143a878feba4ddc228116b1506206eebee2ae4755603167fc3ce81d8d9aa52e586d6167ebd78cb4803b27f5572a3e5b1302869dd68555ae9e9960d5d4fd2b1f56dfde02d6f1aac0f50741af4d348e7e09c2903aff45439d672b40194628b2bd30139d7281fd2703bfa011ff51ed2d3304a144ef623010001	\\x80d8022fe92c2f9f167c4f4d2ca29f91c57d81a276760bafca920a68b29b6ef46609346de03a113269d8795dce146f9f7c6a24d44c03b369e58889b9ee928006	1656559772000000	1657164572000000	1720236572000000	1814844572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
308	\\x15576f31c34e668d6f1724ffe93b07c2d633218da8b07a35ceb500603b3a01d530447c97b2ce7f043a35e24df172affac68c4f7bfca07c9468f04e4571a19760	1	0	\\x000000010000000000800003a832deca8751e14dc5073c137f151890ce086cdcf51e87270a125b93532be65a13ea7f75ff302e5f8972b53c8870219980fdbd84b528df5245b5cf67f7ba3c2f995f190b11fc2d83359031ffe78b49d2f7f619dbca57675672384e3233c2a8b9a85c88dbf0b56494f7f93096554ff05f12188af9926601a831373fa024fb5977010001	\\x93455edf2655f3e59a9e5e17cd694d6a470f2dff956d86af96b05dd14d4e1cf537ece68527c137dc63a7fcf7e348e7dac8d05fe7354af3a574d35a2542fbc402	1648096772000000	1648701572000000	1711773572000000	1806381572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\x151f3a8910b6cb3bc7c79b3f6d1553b4f0acea4b5521513923b658f1ff33cc9fd32baa1d2113c00d6c960c14162645d1b6a99920ca472affd607273d5d84d0dd	1	0	\\x000000010000000000800003f4828f553b2a0c368842099d462414f0cfdc9db920b2fb0f45e73e1baa4c0ebb6a5fc95bbdf043b28a350cab9491d4d82f781c65dfb6963938b9a2376cee2a5834e8a7f73d000498ad56baa89b0acce248b93ed8fe75dfe30845d9ad079e97197267d03575a32042a8ab039a18bd486564e381d2ea11506fbfb663a8137cebe9010001	\\x88059f607e35c68575c4870cfb7bb623545d79d112be7148841909ae2c36a7fcde2601d94e104bcccebaddc38379ea98ed1ec589189f2326d934c27d2f17e104	1671067772000000	1671672572000000	1734744572000000	1829352572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
310	\\x1d77ae395b0e45b66fdf419479a5741446899193ad81a72d316bd02277f4b9af56061893559c9477d85fc23592672169bd31af9dfefa5ffb4a4c908db5a09dfe	1	0	\\x0000000100000000008000039b9085179b0f1705acf9aeb753c8ff7fa9577dcbb5078afa47ef3ead8da8e2602943f61c69bdb7c99aa060ee075c364903650c976d5f098a99c72252b700a70162f0b8efa2b35f82a15afd5211796d8817a444944b933fe0c1fe56ed4b0f2f549f35ac81ab25662ee935cd0e1bd5d6b9cc43c945679e7dd09ca515409735a111010001	\\x5a258ecc85e5dac52dfb36fae9310e17e0eb407f125b96084778a058f7141b71aeabd0322b6218a6eae144e7432faf06558885a2bc6acb185beb12cf11528606	1665627272000000	1666232072000000	1729304072000000	1823912072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
311	\\x1fabd3bb5db0854cc4ef197aefdca02e5f72b895eaf2402d1ed6db0657d28c39f16043c6a5413133979ced6a009d7cb86fc939650455b9eab5b557220239740a	1	0	\\x000000010000000000800003bbf82f00d4479e543d4a559df373c7443a425e9198923165eaf83fbfa624754109cb4afdac52bfdcc2701e46055f5f4bec2d4b85d9fd40c97c3f4240593e64d13661ef46836eb8333d10b041d480544e983f5deee7b2c06d332cb6bf0a98353440b3e66caf313df37b034110d99e2fd0629c47300f19ed7941fb70e98d593a43010001	\\x936e39439d3ebd29465dea287fd2748df187a06121d0084cf727b641b855b13afd9bb7ffacba2726acd95fb15c22d76f2001f175686425bf5b211be26bc13d04	1675299272000000	1675904072000000	1738976072000000	1833584072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
312	\\x1f07eb4845d49ccc622cb05b55611f906d3d61661d27c164c5438583cb7ab5682d3725d3f9cbc081361778bc9b02ddecac99747686f766d3ee1ac19c724f6e05	1	0	\\x000000010000000000800003ed3f4f5b7c96edcb0616391dd2034d032681431543c147a640c928f33bf2913b67fd6378578e9be22ba4055a4f2dda7b6c780554110e29c87637babe297d502b818294e392642c40cb7823e64d81f14fe1dd96905f4efbd9c5732e1ed4bf8b248d36556a4610be5a27a8cc6889520b2eea1b73265b494190b72ed9569416ae89010001	\\x35b909830969608c2957b0bbd639e96d203afce824fafd737cba14bdf450f0deebcdc19fc0aafe164879c2a5df7b9b6fa89b376035165f8f0be86ca567e7d701	1666231772000000	1666836572000000	1729908572000000	1824516572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
313	\\x2073eabf58ce47ae5c812264b0c9e153e3e1c98c47bbea35ade0999786a8d2f6535b3dd7066f806f59f2310aa8f76a58651300df57ca542c4dfd57e3d21b7667	1	0	\\x000000010000000000800003cb84da6416e864e6e61593ff13ca44beac10f3d80a32cfcd11ea446b58c4bc030e78983c67553c53faa0142d29448556d951c1657e7d6c466906a779255f28f719987bb02dbf69112688a4d2797ccfd145475502ea3f24c42fe7ce85eafd5c747e1dae5f0d36c876301908b934a4f0ec58b14a6a20383a138018aa44906a6fe7010001	\\xd156c90aade16c9d23ff69d27f9b4b66a4f4fd73ccd3c165eb859635dd1a91273e687a2593cae1af596e336196d31bbc887c8fdc8180de996f8df5ce9c28cc04	1654746272000000	1655351072000000	1718423072000000	1813031072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\x2223381688a747b6577165741b7a2bfad34e787a10d2296b95a03459ae8ee4d5bda85f70dacf4d73889a747e0ea992e1ece0545ee16f65ac00c5fc094d963dd6	1	0	\\x000000010000000000800003b56706b66ac775fc14f5ad62ad427041bb9fe1d5ab33141653c027e940470b4eb6922b366b3bf1923655001b8b220b1edf0ea5f9843c13c06b8d1f703e7b71b760789d4beb61375c3bdafe066e08b623228c7aaba5a6970ab606749f3925e2deddc61c384aed7a2ec7e36a5023a6935e2168e6bc11221ed84dc2684f9cffc8d3010001	\\x768e39205fe6e52b2d21faef2a51f5feef460164b6009e8dff54967a3fef51f052baa8a0ad6cd2f917b1b0f9ddbb828f577c3405e59249da6b603640458df402	1669858772000000	1670463572000000	1733535572000000	1828143572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
315	\\x23cb23eca36a1f7da7211c294977c8fb73b7ef9d079b4cb27b3f370b9182057558bdcd02fab2ebd9c876bc4715ec6917034e972e8cb1beaba56bb4bb72c89ac8	1	0	\\x000000010000000000800003be5001aca3c7f09f547bbddac3f53f79e76cd7676d14318e98672d45efc9bebf9fb26aa6246a1d3e74f24e2e421c93c2e91c160b6e4f00d5affe9d9f17514a882201713daf8a864f435620e1ec5c34c88cd0b80d578246e91704ddd36ef2e1742530280293b76026c589000afaabab9da8876d7526a3a13334ae2a1367cc9971010001	\\x84d27f7b5a496e28e93643e8fa1003df6324ea5bf5e22654ac5ec1862281c2c00f5c51c6cea084b60d9a4c48128e60cc2bebbb5c35d8929340e4e83829f61d02	1661395772000000	1662000572000000	1725072572000000	1819680572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
316	\\x25d3f6bdac8dd13087df65320833ae6c99bd813370376c5e55486c9cc4055d84fb30c33cd76cc3b06836dcb9ba30ddf8be2cda320d11a7ac875f5cce50c7b78c	1	0	\\x000000010000000000800003ddd3aa9f4386ab16c54232dd26efd002d78e1eadb9258ac60abeb3f8de815847ead1cd68cb2faabbded0b6deab5b45599491dc13d506c305fcaf84ce1ed88566b96b08ae07d0917c245817a1b5ce444ecbdee26372d69b6e301d4b72787209a51816992d7c2c6e3c9f19cd9ca3f1c567798b144ea982d7ed0ffed03823c8e379010001	\\xcfae65d991b58c4ce85ba2d9642b72c49fb27feb066896a6d47393e5c13b89a619c0f87176885c20aff75d12f3a2ab466a71f4c5de4adebf3a48cd8c88ed2d09	1676508272000000	1677113072000000	1740185072000000	1834793072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\x25eff1e65bc51be925e2832d6432e8a8e0743b401d7cad5e8ea90f4366114514ebefa07069e357d19ef6a6319dd88b2eadf31dc507f0d26ca2ad04ce3fcc447f	1	0	\\x000000010000000000800003d94e4e1cd6450845e7a23e33191aca730f797fde9871f2715e41d4d0dee98a40cad642be3e1eaddafa40af3fd2e8267e83392e65b9a9427ddad8d6a9b1d2a7ff555f2ab3b4c2a16da82feb097293393c78329f74dc6cf4cf000d265003f4ed8f4b8b9aaa6a61fdb3a8508f23d3c2b2aaced455ba2a53b6901a0e8e2090238c7b010001	\\xfc9c7e282ba421c43cc1b6ad8fe5c23ad2f476fd9d9f2b28e79d5d3be9d06373f91f09d43d27efaf38d76c92a4b0892456ef1200bf84380f4803ee9091e23207	1657164272000000	1657769072000000	1720841072000000	1815449072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
318	\\x25f34cd6b48f1b20b3706bc159aa61ac4c6380adcb87d223668a840d40f286848c1e626e96cb474682f41ff84cb8c3430d608bda334f59c319e3196070c28eac	1	0	\\x000000010000000000800003ca653cbec7e7e565ea147cfa3d2a075b81810b089fa3d6b77cdca18cbd2b26ae52b7b3ee800b2063de0587cc14ceff7bc17e1f347d5d1a1758937f96b4eff817d457dcec9d253c6f896ec73a7528d7d8b206491a03e605e469849f698edf427b5aa59f2b62b06c36f09dfe4de961aee56c0a53da474f976e204a9b5bec4d7e83010001	\\x25a6a53b92520de4b0f10a6773902240a8d1e77f9d6e089f72a8af3660cc2ed2ad8b11f8f7e650026706d56f5bd088cb0bf8098f8f528b3f18016c1502e7eb05	1663209272000000	1663814072000000	1726886072000000	1821494072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
319	\\x26632cbc7f11b73c31a88c1adf8461510dd19f948a59184617af1066d70c6dca5dcf3d311f7c0ad4d078585994a4ca72ddc7b618dafaf63cc3b315003f2ba214	1	0	\\x000000010000000000800003b2627378e05c45efedcbbe53392c2937c4483ceea7908c20f458a3302c9766c90fa3323abd2a0d0f0c8be591af87fd4c844c289362e2ee1bfe7c9f6bb862ff66a2bfed168b2c38f0b26bd1fa6414378162e71402c3a30919d9f7a2ab9a03b6a8994e449402fcb5a0c6ef84b6fd6cb0f0ddebd2db054231c9f9c7b40031eaae13010001	\\xfb19d140f6a33e1604e6da90da30ee09ff295001b2dd94ddbc51d091580c8208239f6406bb4b41b09ba74f67402869afe8bd7e1aca9e99f7ed0d5adfa63da606	1649910272000000	1650515072000000	1713587072000000	1808195072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
320	\\x2b4315389f35cb2d93e9db95e8237c3659a113f6095045eb868a3df531dea20c7771046e41ca3bfe5e7b0cd1284817ccc386b274cff2d79b1dbe5f080e7342dd	1	0	\\x000000010000000000800003d65c72a1e1f423727954c48c9dab2f08039be21c66093ca30c737f3a159e15cfab51ddfcf24f0ae78d8d3eb12021b185995852cc5bb6b1c8a9a6b79f13f54a8eef09d83a7d408dd5d0f503d92382cb2f6d862759e403c751729e1aa4387671cb6da088f00d1d94113f0d66c1c101031cbb8088664fddf1e882a597ee21c56425010001	\\x417a9b99ccddcc0175905498d6b0e49023c37adfb390819e0f41040e1a755cd040c183a7dc4a77c7834ab177ef68c3e44d5dceedd0290d93b2a1218fa902f104	1677112772000000	1677717572000000	1740789572000000	1835397572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
321	\\x301f56fd8055bccf13a3b599accfb911753e4a74f05ae032c85764a7f468785770609bbbd6034864c0fbaacfa34a167f420ecb1716b9b5b9df0c7af84a08ee0e	1	0	\\x000000010000000000800003cc0739dc177308a73e075e990c2339e59332863029066e0a52bd5b699230ae043f85cf73dc2ab9c0a326bd56f87dfceb957ceb3899bda50635fdbdca54a52e67be0f41ffa6931a10b5aada7904cf2685eb68410963a25801fba23b192b0f5e1190ecc132b8b821a5cca724119fe937cd21283b3db696a8fb7bc184ae910ca1bf010001	\\x4fa5c0e1021defb15cee6d0b312eb969a5f2c91125a316480302464c483738360d4578f3d0acfccb3332839572c3f6a71eac8ed27547f6f267ed4cbb7de1b904	1650514772000000	1651119572000000	1714191572000000	1808799572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x31274d6edbcbd1734532d561fc51c4c830ded488349384bbb907ebd7b5f05c9775f6ced24aaf22b4c6d159b35b701d397c7fd23c86382680a800bb4915efc61d	1	0	\\x000000010000000000800003aadcd02eb34af68c7725f94de72d81c67c904a634ca820083dd0fdcb91cb6b79363b37940c04ea3f0b864341441147625333907d7a04b79599d049bbbc2d7af57ef57d43ab1caea9fd0f28597de9e0b6b8a634425de97757905f6f583ffa3d7f9cff78a1d2b0de388fbf3f0e433bd5eef59f9dda3ef8711c36d2ccc7825184bf010001	\\xed69baeb2d37681db71d41c36fa20714678fb6aab4828262993a4d2ef8f25ec8c917189ac0ba31ead110386e9d6a2626ecb64a7f6ab32061e21454b2e990f70b	1668649772000000	1669254572000000	1732326572000000	1826934572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
323	\\x32ab12ce2dee73b6252183914bf89ae94da0fddb9525753fcec0e4dae3019119cb019e3f79c048d65f46b5f2182f841eb94b5e131ef65d89713620702a64946d	1	0	\\x000000010000000000800003ad6cb0fe263d71e3eeac255b1fec68afef1a97c38708365f733c4ee398ec144f098d5773300fb4527cb59c453f7b6bde56751481b0c7ca3a7f4aa7d2ccf13782a538f962404b541552cf6949041b9293a0e403487ffbf50df8e993bf2a4c24e8d905852efb99ca090c53e89fc4c6a020dba0e850700de6e3273c20a5196a0f05010001	\\xcf6d3f01bf2bb9c75034861b7600786c392c03c5bc9f9492e1d4b1cef696bf157d5a18de0d1d3a371b5e381822dd1a916bdc1d449646793815a55ea16e68c70d	1652932772000000	1653537572000000	1716609572000000	1811217572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
324	\\x33c748d61d9ee467e204d99a255310980d615f3025806e29512d496a3df7f1dc24cc5fb6cac0328064c9f0328735f15b1395c44a5303408f3d3663b85b343907	1	0	\\x00000001000000000080000394aa223a20647c4c62acdc1231eef4afc3a1f10c79461b7681fd3a5f9278262d4d827468d4a41996ee2c26b1d15c429aa0955f53843c1aab741d617d945c494c35851a9a12fb7a58ffbe043ad75d2dc6575b3fed000e3072f7e74ccac92b18f48662d220df2a6c51b801667714b001d468665eb8297bb07f794cd583720b986b010001	\\x6ae46a54a0a6201ce913c5631db28eaa7ca59e96e86002967b06d6c765f59a59f455d0834a2b6aa436c0485c12d412abeb01b4477280e5ccee8bc64b81da5d08	1649305772000000	1649910572000000	1712982572000000	1807590572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
325	\\x3c23fbbe165f8101280378fbf4c3440fdd0a433524baa5b42abe33296bf2ba40ca2dde8dbfb7a429b2f3deeb81e731b3efac051024ca8ca0e9c0a24b51ccfd92	1	0	\\x000000010000000000800003de433b21a93a7c9e4dc1e99617e1f11e12810a3fbfc7e646492ce622b4dd95e4e5c2b21f90e2f0cfcfad1f10ea746e5b331a7ccf133005b55523202fb0d06548966ebf8cb78034bff02813856990d1369446355d2abe79923e8945c964065bf7e4a05715f50e2b079fc6a8152f21e4cb64dd85ceaf6d0b3f3f583a89d24092eb010001	\\xb08551fa1ed1c2d5c48c9d0e0348a475a51ee83ddb261bf6dae12713b2fb2c359f11cbf33fa6becfe1c2903ef3aaee3e06d27e3a195e52a1127614dadba93c09	1665022772000000	1665627572000000	1728699572000000	1823307572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
326	\\x3d83dacc8bee2151f18ba63836b6963f2a1d201b3ac9fe00cacc058f6a0205334d0628a15bfa080eac460d9faa8db720c334fb1f959b828708933417765eb617	1	0	\\x000000010000000000800003c938f86a8f8087b74dd39f9743a264260c1c80d7a2c9341317a5e0517f5e79f3b08bcfec40fa396ed6614ef2fa0b29dcb2cfe3754f3a925db0ccf7dc24f3363700560b3ef04e6bd2d8f2427ec6a293b44562d17cf146c16c30a9e855d1f7bd2fe966ead6cbada595995370649a27336a53744c298191633d8668c03b0e08a713010001	\\x3b25e99363e95846133538290a2b698e1652253324e0e45e4415f6be7917bd00c2b820ae4ec8fdb830f718f539e335e3f8822a5624263e6a40a995bc93095402	1671067772000000	1671672572000000	1734744572000000	1829352572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
327	\\x407779f912dcc13fd3bcfda2e96e30555f0102fe71764eb5bf7b78ca6dea9b0b6513e79a1660ccde9fc8fd0d685fb6dbb6cef03ef0527431352dcf66ffe38f9d	1	0	\\x000000010000000000800003c194fe39a05ac78f63c1407a8b325fc0ac4801983327c9d9946b4fba5e7fdb353736916d4c3f923a665a5d2c96fc66b3a8585764f62a04043c2c6fa31397013cdafb091d7cba8d411917bfb9b3f93b82bdd07fb74fedb65e92635f96d17826f8570cbb54bcbea95dc99b95605192739987ee8ecd046ca90606a27ddc3bf0b6b5010001	\\x953eaaa43e39bb8fecb20906650222b7736fbd908a36bc5cf76aa5a1277d30aaf00bc8bbea4d5abd16ad3dcd54a2204eb2846dc4ade9cecd75c52ac7e45be20b	1658373272000000	1658978072000000	1722050072000000	1816658072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x408f3f7eeef9a25109264dbdb1a8f38085884c3f604410f43ee17a5135e42d7994fe5b62f0a77072876e89a987464bd95782b820a6666503714a11dbc4e0b8b2	1	0	\\x000000010000000000800003cc0063636a2d84b505468de50f6217d6daa5864292079d4b0fc93b351eebc6701612d51ce8259fd5b8c44fd7a06d9a26cb8b0f546183819ce8ea97e61002265dd2c678efc227b0e2a8014bc6ce0e8b8d9a8ca35e041f4c1c9cfdb94dd323ea38d4b321c6e121cc8cd0b2e6ceb5debd88f2c0595dfc2ac0fc57adb269652e5f5d010001	\\x889ce26c3863fd1403089d1ceeb8be482af7189b6d100f38a6d0e109443dbf6e5eaf8f51f41e2e061cc2fa261e4e2926c16638c0647b3542ee280014a1c1d00e	1668045272000000	1668650072000000	1731722072000000	1826330072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
329	\\x42a30dc7c58393ad788a017f66a8bfde9b1f5f46d968c7ebc9046fca35bb7b7a676e03cb45b8780bc28e18ff4907ff9d60ce390137f80096a9810135282bbee9	1	0	\\x000000010000000000800003d8f7cfc49ab8dee7525f471c712a925e8618b22dc5413b347c5c401747a13dce487d53a961cdacd628c02dec64a30447eedd15a7a1e5db8dc1c01d4b80a6a32b86c41c60b89ac22a8171d010f81d8d442b82355289baa3645e386ea0fbfc01a4c703916685d68bdac779272a433cb32a90ecf7a15241e946951ccbeb5cfddf79010001	\\xbd64ed6f8f17c92a2862e868c0fe67d9deb798c25e6a2c4e569bf2791a5c9528d137a128915f469785cbba82a67042ad64b2356ff84630152ef640464e12c50e	1668045272000000	1668650072000000	1731722072000000	1826330072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
330	\\x4227a8fc51bda2ad0bd576a82fd4478724e6de4f8dc1c2cbb0903973015934f8ef06f0da88039fc2acc4c1d2eec26e03f6532390b3261bdd8e50807017af5b04	1	0	\\x000000010000000000800003c3590c870acfff6a73e8f38ab662830d99cd25c235ded4587f32e0d60da91631abd5324cd3e77e11fc191e571207d297ac5c1b97fd012e244c196c545c83ff8752ae2709bb97ef41835997927fef5c0fa96fb11ae0072a9fc5c6b3a49315ed6ad49de915141107d2b723fe838165834ca5c858da182dbd7e5d767a46a5a86df5010001	\\x5be2551166383b3bdcc5787da6071a03eff9e83dc452f02178ad94b53aa9694eaa539a447d0760efebbe646333666c176611bc413c94fcb291dad15e5ba9d808	1658977772000000	1659582572000000	1722654572000000	1817262572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
331	\\x427b87169bd5599cd378499ebf338f9f9ad87725dfdb0584adad582c8e0d147829d17a54838ba57ffcd71d2b1744b2a801a68c67995fab6478769aefaffd4548	1	0	\\x000000010000000000800003b50746bf989a1811ccff940d57b02c5355b14e891026dd604e0e29296617ae9653bcf2f18c07939db90679e964a4282fe1744f5f5a1338954ccb4f5916b8230b525541b3b4563a4a48cb9ab04a914202572bb79d4a818cedb36fa1f0c13e59b244fa8572dcb04be38d04bc11782d5623b80a96c960561728cdbcac121c653841010001	\\x033af1a8b5c845bf29cc25f0e6c1a1a648fbb7a87e5f6554e99dd458230426873704f0ec26281f0506fdb3f0857111badeccd4adb0be1b9c4f18b7d706247d09	1667440772000000	1668045572000000	1731117572000000	1825725572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
332	\\x43af72151e16a2147f22ea101e9bd5ac6b949c9df633b56a47ae39b623e88351855b590012fc972aed37375e9f9e837453c7581bdd90b0569160c71587b9f99a	1	0	\\x000000010000000000800003df5fcdff860c38c10c04c90f616ad608f32e36680a5924753a09540cf30ee6c88a40903fb90146a6bf9f78fc5471cd466222670cbd988285fdbe428321314cafe1f8da29c6a682f7f96bc553b506e9d8b9a8dba7501947f9d102b3fc37a23365945f1119bde64252b8c4145070e308e25477514d47a7311e92cdf9f603553cb3010001	\\x6a80ac9dfae81d716cf2e19f8c93fcc2ede11dc184a56b33687ad04b704f8456156639f59681a2894e0bb7e15282755f12190c2c93acbe30459a5dd06a2c1b00	1660186772000000	1660791572000000	1723863572000000	1818471572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x45d34f7ca461e0fc8e0ebc4a573d13b545894c690485cdc22ec3ca148cc9de958418135e3c78f29a90ad5db74794fc37522e8c445cda4172fd67df16ef9d10d9	1	0	\\x000000010000000000800003be3acf7f3f1decd2bd57256f5f250114800c13f409e57936c520429972c678ee910b159f55c9a96b6e3dbd8dd307ebf42f238ae8d001b640c0f2e74344b3e52263007e4db5d4cb4a61c6adc26cee5632396e26fc773631b7fd55519c5c8b869288f5bc11c5e037d3c45c8fd3aeedee9732ab6c95bff488ac57874e97ecc2bc31010001	\\x00cb769144fdbf68d258896cb13ec744d977f493b32748db567185a9994cfa47aebae3ec892c8dd0d814f46e222378c59b524f8c120ee755a4a32ecc67e9d30a	1674694772000000	1675299572000000	1738371572000000	1832979572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\x488f084a36a8927fb33c2867079098abf6f7301e92d3c6533776e067896d94b4585ba028dbdbc70065c721c4d6e591081879ae736749e657b3e3ca32df65a412	1	0	\\x000000010000000000800003f9f39330865a19a6e89e8594381430332bd6cc5398830df95adc7b2809ce2c9321c90a00748eb9a07ad2ade8407d2395b4aac5edb511c557bbca0d776811c376dd1e21a5abd7033a5fbab2ce904f7313babd58b8319c72819d72736025ccb6205144df59b363103722be95bcee420bffda27e20fcf9938370e26f713dfd3d21f010001	\\x89dcc435d6eb235d6797abe36cc0759415983907eea6db23d25d2d9bbd51705b85621ea129641370d9c2c7c80818a13ba749ad700ca39a235ded78852adad505	1663813772000000	1664418572000000	1727490572000000	1822098572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
335	\\x4a0b25c2023762ebc1f51adf482dca21117b1639f45f482d60e5a37c139c11f057e74976eccb348bd3a52494a1e43a39bb2dcca1f7f99672a0e80e63f9125c5d	1	0	\\x000000010000000000800003c3740528ea183784d76ab81b13029b11dc3bb49df6d09cb54d64224781acbf0d37f1207fcdc51b0e37396aabb83f1a23071e62f0851d5e122230ef288ec2c3e163323365acea362e09961048b5edfa1ee794c812241fdca55fa9774c5fde44da9a010ca71243e04414c4d6e7adee77a072c1215eb29e45276aaca83b012527c1010001	\\xf0b478bccd625181a9f283aa1ae9b09e3abd4f8f18b79e40fb5efa4601426d011733f36c011fe99a00821c567c2b2d21cacab842ec4fab86229c8ae2c8c99501	1662000272000000	1662605072000000	1725677072000000	1820285072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
336	\\x4ba3fba12f594f8d81add8fc69064a799d5d94e6f57d255ebc3f1bd6b49fb1a238c631496a578a8435fae118a2e15c2db829954734cc307725c3923dba5050b2	1	0	\\x000000010000000000800003c4e25c6086bea1133da330f22acdb1fd82dfc1abc636945a1ad214a3829aa89f1ff96859d564451fa05605812f9b32c065bf261a13654a80158dd7a7a3f6d23140f7c77fb45d90cc6db8ce60752bc36d75a33337b0a7f2b3269083232621befc6c933a560091b5065b97536c7d29c12f2cab0c9110494474953233a4cd6a6777010001	\\x582d6000415041441b32a65c287d97b133ca59b3d40ed51af33f987d38e9ccf1251f65362870c4e7bf0082dda6115fea4a0ce15adff1fccd3c6730095f20c80d	1648701272000000	1649306072000000	1712378072000000	1806986072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x4cffce4d7327aad0942f996704de8730f31559e2848592630c9be52fec175cb1cb666779e4a92ae7564d50a1567ded89e6ad3e4c1d40e1fa31c1163e7689afdf	1	0	\\x000000010000000000800003b12dc7b6c5288c6b484ea413b58ec1acce5014ea97f4c78f170dfb03e385162f1a38cbbc2c6bccce1a561bf15738acd0c9595d143c2dee7c8feb99d14536660e73d89b96b1b634d352a16e3424ef348db1c80e04151b8c940bc612b4473151d9a94ab43299d0456f7a0e0fdafe7c1b2d3247ef408a5de273eb553f91981692ff010001	\\x6a6f2cc1381fd2fd39a5a6cdbabb95a6b288a89462286177f9abf16b080b82ae711171600aa9181e7f900d3b0d378f70340fb83ae4db16cd16e55f19325dd806	1675903772000000	1676508572000000	1739580572000000	1834188572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
338	\\x4de3231e22da12f975b4d4035096aecc81d7437519a2e537af0121af7d9cba0067790615347d71c999426b748d104cd6681ea2ceb41612bd4ddff535ea11416f	1	0	\\x000000010000000000800003b8a3f5c1e55a8c61b6bd62fc01e75ff76ebe8d5d72dfdffa576131453df5c4b322a82f1858c4daf8f9b62a9fc38934e493d1c8efed487de41c81c060d8dd723266abbf63633a81f5bbb481c42f0ac56ab54ca30b68f9454e748008612f7c4439fb3cb28f91ed4d5471f1f8c18161bde3687bd1c5f261bd2c06ada6966ca8cf3d010001	\\x43abd3134a1490786d61bb36ec8bd04264d68184aa84ce4bf5944134f6fb4eb3baa9695dcc1dfce66e7e68d1d50e17dd8937a483292cd11a4b347fd7f38db202	1658373272000000	1658978072000000	1722050072000000	1816658072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
339	\\x4f277310cdf61490a229a1d8d31d836d8e3e77ee2b62be4c83c89d61cb8695bd61ec7cc9e71cf3984c46738a072f3c3405a9f9e69c1fdabd00e5a252afa90ad9	1	0	\\x000000010000000000800003c4f71de8e1156236ad9523909c6b61f36551965a6b14c6f2eb1635872dff0403be76164190d0804756d3b7207c312b79f9076262c300409aa82cae558ad8c2ba01e1d82506719fb0a66001604a9a13da629af7b69ac1865a2fbfe836c11470f356e6d9d7f99ac9fdb58e615a8411f35e63e6d8b2339baa673928d5fd36660cc9010001	\\x2767dedc0e40050f83a2f1126b6a793d5aea6c3b2ce99a9b25c33909ebbeaf97954b2b8e56fc6d18587dafc77cbaf3d2277fafc45bb650ac133df6f3137d0605	1678321772000000	1678926572000000	1741998572000000	1836606572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
340	\\x52f3158de501d7c99c391e6065a598de176e3bfeb9e0029ff7147d6786a98faad13c2ed9b880fe4398662779531ef3325192b24e02749b25323a4db81f819f8a	1	0	\\x000000010000000000800003aff9372fe4d3c3e8e6cc1ac457337446f0d831d57ceb7490898159394fe7cbd0dcf97e96492b59b8f4826fb1127d8bda150e04224cfd548d63f954541f3377c23ff3723627128bd28f4556b7040874b0ba1cc1e647096a9037219f19b087f6fc64f04d08772e19271077a7cfc00e80e3f5c9b39202789cd48da53669fea5e6e5010001	\\xb0c749eec13c3b1e50dc9c50c2b55cb319bbe9472397735222ce86718b39fa0f7f269fdd6dc24e388fed21af8041203e2c95b87ff61ecf7cb43a716df4b4860b	1662000272000000	1662605072000000	1725677072000000	1820285072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
341	\\x525b6b8f42ed11dca952e5a6d67acbb0ac609bd2f1d4d4c01625f74a53cac21dd42ce60211a0db671dd8659173ca2595da4abbf4e26be1bf40a217551e0df6a5	1	0	\\x000000010000000000800003e75319231de50dd37427fe99bcdf90b5c15228fa59a5eaa6e6d619180fc3f53cc049622fcaaa4fee59bf378860af56e1aed1b7a6042304265b0336ffe2c393f6ca85aa5f1234bcd3537005839a78310a8e665c7d12c45a4f4af3c956c0f054fcfd4cc1a6b4552ac0c4b4f31b3b00b4544ea8e80249fe6519991b4f846e025453010001	\\xc33c981fb137f78abe3697d28d9b21019eb97cd9e2177b3bc9f949c46a52b2716921023d04a86f02deffd3ca1761c50e9c8396ba6d85a35094b7e7556b092303	1663209272000000	1663814072000000	1726886072000000	1821494072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x58f709569350d2914c0693a882e318449f2d6173817b7adbdd84a296df129074bd8f2741ec793d19838eb848aa2dec37bc48357244b4bb90a584c77a3303ad70	1	0	\\x000000010000000000800003d037ce3c44f97919d137840c1fda5ff0c0166d7823f79b1b95b2c945e8d1fb3e9913b0b6ac6bf3b207cbe7573d0b65b9f545a12909459fdfad185fb958e40f309a363e1be118aceb9f7745586211b4df8386bf7f357e829b0edff699ef283a23057a842ccc80cfd3e71c763ceb3a0f578d52b2a5c6c46dccf230bb7475d97e95010001	\\xb6e7e135650d0d69dbc530b84bda2fcc9409e1d747809d736c68e39acc76e45f63e4a57656ece8c8831a4cb5146db4cc2e2a3074b161238728d8cc909e2b6003	1657768772000000	1658373572000000	1721445572000000	1816053572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
343	\\x58bb2dbd7bf01df82a8e8dc563b5e4781e9432aa240c226054b3637ce2e252674156ae8996232eda8bb87315239bb3d69fe6ee17cd6ebc608c802d622a21b239	1	0	\\x000000010000000000800003ba35a2856db087cdf10782aba214578fccc42b104ff75c2853e9cdeb771c0bb96509f518e7fa5b2a5887dcfd9832c6faf3e7bd708cd76005101ac698b9218f23b189aae97843a749eadbbc8ea34147c9b8b97d37d32c63fba790be11608583304c819784f7e7e333c0a43a94abd4623be3ce7874fee71cf12e5944f28fd01983010001	\\x0db9b60e2a5672b600ef6e9f187e9d783f695af481e9c106aceed037def4c6bb841c29644de598b1a22c40f19af7895fad52d563ac43553a548917ce63e5880b	1672276772000000	1672881572000000	1735953572000000	1830561572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
344	\\x5bcff3cdfbf94602a8867f9ce871311ac87020ebbd88191aa868823385c5ced425adc788cf7f68cd5fd931d58bfe33e1448cdc4b117f1aeb44ceeb3fcbfaea58	1	0	\\x000000010000000000800003afb802dc723144b35107ac579a5a8455f5665caaefc66e9d5c7bb635846a00d70a5fb01686f29309b4327948efca12e1605c9e243a2efad78afd12edda9c70a47978f64d4c267fce8eda8eccd21f8e5909b654858f7c26b4f3ca3c5710c84f99e93cf0d3e1e6f407700b775a0e29f8e2bb6d09f6d0999d90b8297258e8f7f795010001	\\x7a29c92c08ef47945f64bfdcd0db72833eab3e63ae596666050e2fbf6e3bd6b1f59e3061fd5fb042ba9f5a03795c28dcaac91c35d586d5a4fe9874c1e1f59d0a	1652328272000000	1652933072000000	1716005072000000	1810613072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
345	\\x5cd778b6132cb0df3e8e74d70f4b090a22cf586530b023ae6fd1ed304cf7191c2b657532f5cf627076101bd22050085876d025f7cacb1df2c8a084a05d477357	1	0	\\x000000010000000000800003cec3b835bdfa36b609c2eb20a2c8a741c43e4114eb5a0299635229e5a6e582e3f1b3f97173f16fe8901cec5a1946cd1695f5f33ae31cbc88aa33d8871c40eaab065c5b1baf8c66f9e8486706fa89e5f5370571b3f960b5e1ec842ceee5f9053de9999833ad2b5379fb149d59d2d209007eb29bde2a50d37668fb662680a4c7ef010001	\\xf3dd0f0c95bb1d0cdd4f815558d86778121b071d46b752570193b1f720712b2823a24679083eaadfc01a6b058e945a6090f4462f672b529ea1b17711eb78ad07	1672881272000000	1673486072000000	1736558072000000	1831166072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
346	\\x5d6fc7a5fe293c96ee5ef7447a891c15eea271b3ffb7b5c04cf92b1c3214fe04a8b7a167998b87d67abc980a1d45e4367051a8bc3e67a4a30903454732ba3d60	1	0	\\x000000010000000000800003cd9ea649498e04df07356ba6210f9ba09ca27309ddf8e6eb9c11a1d23722a5a227194792f60edb86a2dc24bea71d8e5d792c9307ee5f6d1b016821063853ae7194835ece95e2e0cf2f29a527384762ddfb3a3449d63644f60ea1854500916228dbb91ea32cba9146c6e761e6aafe5ec556640667f3001e37a0749315892acc0d010001	\\xc8999c186d4cd8b4bfc800f815638004cc14e9a7abce48704b25d8ba7bec0acad8ebd173c6444baed10b9836d3490039705b58c6f14a3547ba683e919d81c209	1671672272000000	1672277072000000	1735349072000000	1829957072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
347	\\x5e1b131914eaf6cabe04e18166d84e651df8cade8910a9f000bafcb34ce34b54b90ce5f72f6cf1855a1a93e12f0e75e4441d177d67467fe7ad2fb75b2ae2ede6	1	0	\\x000000010000000000800003cc4292c429d33b99b4911a736ebcac9c8716ba652d851e7d80c7a724034934f462b863757b41574aff28e8a839cd4b97dd1176e2f54a81f155d7e6cc7371f8d240f0aef76a63e4c365612bcf5777e00cc2a03dbf455bc8cf1fcbd44392278b02deac2e065e05950be113139b3aef68f096c5d03808bc9c520ef5af54c71a8df7010001	\\x3ce94f878e5300e98b0cf1bbe45614f7b35448afe47c20363612ac25587a9045fdc43d1454709162bf311f8a1694b78b2203cb17e4ac64fb737c0039c4174907	1653537272000000	1654142072000000	1717214072000000	1811822072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x658b211b22b844058fbcfbd881184152f24cfd17cb756a3c9b0379ff9b655ab6c65e3497489519e1526f704d644b87050e443a500250d36d76563fb2835c67d5	1	0	\\x000000010000000000800003c148eeac3f5af70ee789270b943cce398891d895043d153cfa740c0b58003a2abca58d3a96201bd72b9c7150d0f41b98a16e7b854d8f761b94f4602987f52ebf3d8f85d594b827bd70d8e7c8a62234340b3dcc7cc7a85a4ef036b585b9c1215d0beb258ce9259ab2cd4e1b4232799814d939c1650778be39a94e0d112aa998b3010001	\\x87181cd353e084cc7f4d221d5ee868cd83c3e86b74353d102a980ce31f52a1246083aba0c40add0e4c64c98804604752a4d7fe7dce23cfd69cf15c0ad3cde302	1664418272000000	1665023072000000	1728095072000000	1822703072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
349	\\x682b0da4919fce421e14d326b8efc3753a63ce42d897305ff2b32b9a0428bfefadda90e79830129018dbbae8afc2f9a59576165ed05199ce203783fe20835f66	1	0	\\x000000010000000000800003c33fdf4f74c21ace71b0321886e78b85922ea071e6740edabf672199791450fbe648d368a7ba53a3264ca47016a2c311d038fabda99474b3627d9e919ed650d7829921c5498e0f3f20b417fd424a5ee6ac6fd884f8ff619faa21e12d58b9a1480c8e505d25c78353496959f402351ccd415a480e8c1ff9c2dbfdaaa08c7d0393010001	\\xb13c9ddc47632728a64299c5a77e7b3c128e43d13b7ea75cc75374227b25954e9636193a5892e61266d95f0687ccaec674b0006d30d0e66196d825c82709b801	1657164272000000	1657769072000000	1720841072000000	1815449072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
350	\\x6abb6775abd05e961ac79acf9796d08dd44b64d5bf7e9dc74981fde7a54cf4035e12dc0995dfb53fed64d244b8b0e64bdb1448d0ff128127e029e20fb779c05c	1	0	\\x000000010000000000800003c22f6d8dc39d77eafacfbabf986f066d2891d1efee5be91847a89078cfc83cd9ca32f215d2b4df41499444ebc369042a765c37d8d9deada94942ec53960aa340bfe70b26c568d2da1a3d8c9296b311fd2968d1a239be5382c078b0a7dad365aaf70825fc1c18d25242caee6ea39cb23ce747515a3bc194914f1f65a823639ca7010001	\\x98231037491995330bfd4ce03b65ab0bfb12d1535b170787c7fcdb86b4f09ccbbf31134ea37aa227f2581cb2874594f940b5bd0b261617d954a46f5c7fe02b07	1678321772000000	1678926572000000	1741998572000000	1836606572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x6a5383bcc91c1729fdca7c36975eced2d1b4648e2e3878ab34c3cc9629f0df6127516750572fa71b311439c6930a45841b2c29bf49b2f3e917fd7d424d2d2e63	1	0	\\x0000000100000000008000039553b981d7a6f5fe7c7d6d820275563125b4a0fa40666b8dca05646e0190c5255436b014602ed5fdbb9c99a16411e1b5f6ee29853a97a6920eeb4e8d8b37abb48acab0aea6472d8186a7489e61b0bfc0f1911581a61f1567d7d566e4bca2591e39b44e0813ab5e9d82895f0724b7543785746d93bfe3fe90790234da26b18f9d010001	\\x01bfbc72b02020c037b5c550021ac5a589ffb8cfda8ad7a1838993ff0aa201aa0fe945321cca9a12aadbe3f8d7c4abe99436e17e36ab228a726f3e2e834d0b03	1675299272000000	1675904072000000	1738976072000000	1833584072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
352	\\x6bff6cbe4409a2d872a49300779d511534ed750a54ef3d4d8ae9ca6416077f96236e83c0c2bc4c239dd39aeed675f6f891b90e7fe29b2dbdb5565c2511bf1d7a	1	0	\\x000000010000000000800003d023c9757ceb1b52e935b1afa4293dd626c63920da62e26d9d66ad8fde358b90d59c3b3c3f9fa2d9c50d71c72e1cec6b89cbfd95d3912cf0ed9e6a905e12460a013f707544c79cdf72612a9fbcea0099bfa65bb3dab716a18d8f2d5ef1784ca3bee798c32f02a0df797c0e71bc79003a4e352017d53021286b3bb468f53be25b010001	\\xe6b1fe7b24a7583b0012d598e1939cfcfe9ff7b9872ad1188322135ae3107cf173206ea3654bf5615b6539d6f02ec2b7e6eaafdd9369c44f1602648cc53ac206	1674090272000000	1674695072000000	1737767072000000	1832375072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
353	\\x6c2f4129eee3ed971d6be933aec88024368093f30423bca52803ebff8029c35332fb576a8ea6504c19467acd915c258da45c268c731777a2f161f74eab0f5d51	1	0	\\x000000010000000000800003b30915f75255d707207c0c5935e9341a78e37cb7d4855a0ab99b54d2caaeba3a59a1a5b45995267266a2a20284e389079ddd7c3affe1fbf9e0ed8b7e4d0d83ec224783d95a8d881cf010f05615cc568143b0a2ddead5fcc7c6bc8a17f46d07a81917ccced5f2bbe19ad324d9960fed895e1e27f88b19a8f363db3dbd78858205010001	\\x3364cebca1f8242698a3df20ac1f1db4a3703efd51fe5b1ec2a5c1b91d208ed1430f6bff6e3efbe072f892fcb1971712b509367ccff225a7d81bc945aa918a0f	1657164272000000	1657769072000000	1720841072000000	1815449072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
354	\\x6d9b99f7787793d5410699cc067293100e4c7fda46f5327689e731cfe5e9ec7fb017ebb02dda5aaa9df2dab6c23099431e9b1f0b1a3bfad26c3adfa33c0887c4	1	0	\\x000000010000000000800003dcfda0ef52ead679385f128547dbe5f1d76ccd5e12a6491bd27a1ab8cb2962b16d30c6cac06965757cef511e0eb38602ca0c46c7ec36476476458494b84e153ff84e2511c21b7172770f0738d9fbd59bd942a68371c625887933604712f82a040271af672a21a8e9168398c989ec8047d79f38e71924059927643685925cb271010001	\\x9b03d1c2a52b16336a09ff8e75bd3296f8d841f492af4c8dfc1e5c0db1dc15c467b1cdfb9e84cca2b74cea92699140b9f4dd081fd02f1ec78b3c92bce81db807	1673485772000000	1674090572000000	1737162572000000	1831770572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
355	\\x70d37b8293b2badb7e85f0e14b96beb135a80aa2919326dc1c20c6ce54490ce1750cdb19890b8b4a380fa36a658a5ae05660cc5640512fa590364bc90a5c282f	1	0	\\x000000010000000000800003c93e2050d3cfac175dc0ff41f074c37e4e33a038d136b98b3bf530086d3edd567bda59df19584b968b68fe831f5d4119bb4a6e7e054d9cbac970f3108ff446a00bf4729eafeb80f2d0139733bb85712edc96fd60468244c8159f82349fccbe61f6a3314531a43a84696c34393da993e6806fb3d3d114ebb8f3d700f2441e1895010001	\\x5845c965d6763ab1665d82d02a6a5e7ab9afeb465bb247b17412ca0b686ac1ed30d3342a77eb01e92ab2a732a3c464e6ad08971b9dc99e2b5c6049a50c100f0e	1662000272000000	1662605072000000	1725677072000000	1820285072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
356	\\x7173b24a0e24db2e384edd66466eef2872f32d187fe5a85e156fe201f622226aafd3bbf68643e16d95e0c14429094340805518e612b361525b2a99e5dd857ddf	1	0	\\x000000010000000000800003bb01412788ba3a23b5c06880949546cb009b5522a68fd9ab2d5e7307173d639a3fcb937575769cf95de70d0210065f737966fab1a72cbe625cea3f42eeb3e20c1a2dc5db2285dc11ddfb0c85eadfbe1bf3e6b943ae3adaacb7261455f7c8faa71ed5e14702a33b9ff874d3743da8d9ecb30644355a2319cfcd9b17aff730f485010001	\\x0e2bf050ba0ed2d9d890062bf310f0c17e766e6145e86d77fe79dfea0b396a8cce049514cb38c00bd248662875163c3571ea5e605a00c949889dd8db464ebc03	1652932772000000	1653537572000000	1716609572000000	1811217572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x713fe172edc6cc422bf60d8d8426cdf655cdd2980632c91fce6435c5dde0413d7ec33abf3d59b3d64de3f7f4bce860b4f59248b9c672f83283d737d9adfc4d73	1	0	\\x000000010000000000800003cf2f39f3c09e2328b796e098f08ee566cc43f02b652ee39c7ad6e97125fa05f5a500d915f9c975c485f3f29eb41200da6986a2d38ee9862962d28bab5bc504686cec65df6c7c96525e1c4fb7c13d04ef15c935ab4dca02d04fcec4086927f10cf4ff39a361e7bc1bee768487c91a79c53ba29b8bafd6948382cb4c3fda650a53010001	\\x64df8b43568928c65d61b94ced347747af77d831a03e24bc95400d062de99af211210b395c675cd392cfc3a55b1a332d76aae0c32ba2fb50d3b12119a7f93d01	1675903772000000	1676508572000000	1739580572000000	1834188572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x73a7f8620586d3cb717058be718b7c200452f8f7fcc8b7530e5f9a48cc6fa6094baa6589fbb61e08579375d5011fed7777426f4398dafcd86b5f6c408bdc9d50	1	0	\\x000000010000000000800003ba9f7fc6de379f9e21eed6abd33999bc9f622161cc86669572ea33ab0848b72eedc41832bc7d9c0a3da5edccb9a16b9e0653b94f5b6815000f5c34578f987b859bec94e460807be70e62f8ca630ab67c05781248ab59d007e06d0d4c4d02c1ca573c8ce65f2c07aec98a6fd3b80335a86719b8bfe61ee14230e81ded56c6fc4f010001	\\x15737a267631fd5e877b13e078b1efe229bba9444f2e5b59b849b6aaa24c80a6397ffbee7a0ceb698ac77195b5fa637a27fd393558d82232c329a75045d9d405	1653537272000000	1654142072000000	1717214072000000	1811822072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
359	\\x74ff9293d027a1e7814329c5c8d6f37dfa19e7fdcadd479068c590705089f5f2670f9223a474e8d14383e6ab8b3e12bbdbac8c73c7624f7c52d6cdce038eaae7	1	0	\\x000000010000000000800003c6870fb83788cdca4239cd012852d891fdb6d0aa7b010085f0e7854d84f4ef9256f52db236080321b353889e5db52ff82148fac8838d800456031871ce274460ddd7d440eef5c218f22351d9b8cdfc2867b7a6e0b735d2f18dd2a30cab7864bffd5fddb66dbcb4866edc195ea16fe8273b7d19c2e217f3994d10e26a4a53395d010001	\\x8733f2564e0539c087c4fdd20cbe1da9c9af96178cdc435e98c09644022c7b4199f170a1e05d080cdb43fb6a3285652b0b96fbc6b48be0c883a9ddc68521ee06	1648701272000000	1649306072000000	1712378072000000	1806986072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
360	\\x74bb5c7028f1c744e1c756b7f2a8aa6d562378e012c0ac083e7b89a58af49c344ae2683b1e32775922e6e0dd274e9fe09b319341f29df4cf7995263b686bcb64	1	0	\\x000000010000000000800003f2f156871fd178a78f5479de3c1b0dd0c290533f58e648cdf4607c5261a8d2f679fc1b2cd455ac923b076c030b7a2b38bbd615a1736837fcf726c17ba80efa2a28e472f8bd9f2af9061c170da7eaee2efbb56fbfddbadc14e5435436679fdd61874e93f8a42c38fe1e9832bc56e0dcd1179067d57ed9b665e7f9a4f2af83a44d010001	\\xe60adf432bb3dc4192f922545cecbbeeb3282ba9de842dbebe82144812619eb3de061b7b7b6b3522ebcdc42130ddcbb3cf51ba609922c9f1130d4ac65ace660d	1649910272000000	1650515072000000	1713587072000000	1808195072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
361	\\x7677fd796a79d242037ad5d152df95d0ce72b2f583010f16d15fa09259c55c6e5375f333807f742b9e2d3ddb26cf1a88cd53623ec73058cf7a7be8ed32626959	1	0	\\x000000010000000000800003ce3130c616b5446d0e6e960bf118d2db02b9fcd75f7c08b5288f2ac60707473c32e0480f9ccac7f492230ad54da3cbf7d9ba4d1eabb1ab072e9a1ad9590a4841b31ea007fe3018028ad1cde27129fb35246887550dc7500f25d4e8a8b918fbadc3610e0559c28d8f2bfd441ff4948bd9b364958276dc9cbf5293f893fe6a2985010001	\\xd1be073dcc3a5e16e7efc37c75cf98de1d194eea65e26c1198e2afff8ac29aeb27c9e95eb86a93706a5c78d8b51a57278fab17de2f033d182cd5bd72059bb409	1662000272000000	1662605072000000	1725677072000000	1820285072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
362	\\x775f29022f94b8ad3d13d15464f0b27c66e89b93393b67136e2ef86c3aa739ae62af115378c6dfc3eec54b2eaf0fc3eeedffef61f9d217b0a064a62669f9d4c7	1	0	\\x000000010000000000800003e7c372ca5000679eac21c7e37312872df5ad9893e00eda505f067dc6d5f199b0e96b4a9ce0c1b748176dafec341774cbe60ba7558c342d51b99898748639c8eacb647e44d1a779bc3785c052176708d35cb40db8dee8be18ce165090a51f7dccbd03bdb490b110e949fa3f51f9fe937bce358433cf2328132cf2d1c0597e10dd010001	\\xe32449d2b8f1e43514b702214d1a1005d06339a0d592fab64efcf7fec6a206547e90c4045234478d43f47566e0e93cf126f9a04e818a83ccd88b0ddc7833d907	1649910272000000	1650515072000000	1713587072000000	1808195072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
363	\\x77471951f74fba7d44ffd65e1fd6147614182b5af70df3bda979d476eddaac2afa9c309fb5a36145e4b2da6e67e6dc9bf61c4e1db6d93c5335b050af66f82b00	1	0	\\x000000010000000000800003b64a731a4f5593e51be930394b8a601fab17be8d08b2248ac8aa7a3d5691a39bb5eacc41dac8c2200ef81e56291a95bb49409cbeab850032f31055d850cb7e5e8125368f15bc6b3cfa2cf96f3cab79c92237a996b3f0cbbb86a261aee9dbf2642d31eef38497589fa24b8d8703a6faf5da1c8740004e5cf9414044220c1c70af010001	\\x87efb7e22e0aadcebbd3788d48916887eed5801e2073a916318c2a96df9b07ca1d6930e07ca95064dcf2b76a547b04384c6214063713fe87a383ef8bcab61007	1648096772000000	1648701572000000	1711773572000000	1806381572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
364	\\x782b363c31b59388e95afe70665630efee8e75f2a5a0ae57eeabf5cf2450fb6c42220046c5c8a1cb1d98c31c0e59a34dd1285f925acea62104c832df387e3ddb	1	0	\\x000000010000000000800003c945f31a6f72343b02d2b28a5e84d6c573614b336526f465ad7c80d75e698f8671f64218400f828aac8c9d868d9310ccb440641e8e63e6e4f67398f7c77fecf3c53ec476aca5306bc7a80b08eb66a6c26b66d41bc31719dea3666206d09840b7f9642a6dbd9be1de8e897d05c743370a9644ed9d6196db9c67f5777f6cd124dd010001	\\xccf4b2b7e4a2b8d26a16f95de6418383596afc63d91d759a3d110362c3f79ede692faf6a4bd7289daad6c5b3e64ab1a9126f65a1a6e89b46a069c1a167a7e10c	1675299272000000	1675904072000000	1738976072000000	1833584072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
365	\\x780bac876000eb13297b70e387c12f322310e8b54f92ff5f852ffa65cbac0321f045f1e025004a40451bf7f355970c2132c9ecc1e2600fc1b821c23c716db4e0	1	0	\\x000000010000000000800003c0e227b9e6a1ef87abb1f690231f373213d3675241159e7c8fb744d6812a1b37c34c6aa4a7c1e2b9b524989f4c1b527569f0d5542553de967d0807be28695fd698daee1abb6d09a3f9093e6c96a611cb1751f3719a2878bb2bf580222f283d5de30522f48ba1e66716329490004553fee2e4232d4197c8c1062cda4954d3f265010001	\\x36668797b16d288119ac4873ecad0f48739bb40490c4a70f032038f789d8d0ff61fab941e7149e526efb462b4d79e35bac93a55faa3587640ea22c1ee77ef401	1660186772000000	1660791572000000	1723863572000000	1818471572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
366	\\x7cc32e64303416b4cbb40b2f64d7735979f53b06e85cc289d5debaaf084ea8fa980ba36590029f1c30e4b16412375c57310cb0a2f2e92e5c601ce5cd52ef8fd4	1	0	\\x000000010000000000800003d425dc40dcbda8ba6a8de5261ca756a0f8c2bab0b7eeac17a4c05839fa43fee2f39e833736b5284ceaeaecd800280070a7b804eaec5a315473a6ab2f405c43e3a262c236d8035e415a91bb6210e2c9ef635a72067335eaa4523add092a4ac280a1308a34b7fa7ccbb73ad3857b6bc912265eaaea776be4cc63ccbb7a40e65431010001	\\x67f22488c409ec5b0296d99def512523a9d6407a5633ff9f81593b7d0862bea7c5042966abf46c8b7c421526dfaee189f82e831c01c506d849fc9688fe5c1d03	1670463272000000	1671068072000000	1734140072000000	1828748072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x7d33472bef6fcb30117106f4c819f09660df47a85b5a439307b92a1c55f54b4a7598e287b9398ee436a46764cb0c6e8e7b36324fd0efb88a88c847f81dd6616a	1	0	\\x000000010000000000800003ba5153e83195271f9ef9590a0a2ab8475eebc8fbeb0add09bee6029a8e7e230fecda0816c6e17a3d8265ebed1f79831b23efb01d93ec32d699785b4b7e20a37ba558164caa7b64cf676776c111b71d8ba6d90b02fe6f3860aa5669f89442c1d50254d313138845df21bb9dc5c40d0735e898c71ca177291542274f40b50c2697010001	\\xa9b7c532fc53ae1f6e3b1a80f061cafa91cf057020455481744b12a257ebc927f72724209eba87c3854d2690ffc0ba5aa97e2767c7eb240fe7b469f4ccf7b301	1671672272000000	1672277072000000	1735349072000000	1829957072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x80df6ea587cb13cdc15d044df94935c45cc0ef502a6e33dc5275ac123bf2dd4fab4025d8acbf3abe828dfeafb52920e024789078596b65157624b23f38e09861	1	0	\\x000000010000000000800003c1914f6d792fb81f79b30eeed5bb4f4c99bf743e9fb874097998991be306531d7612e1fec1bdf974f62dd8d435fdc5d5066618e148f6d5bd92ab7ddcaa2b3f125d431254c6d345a72320416401dea7041ae9d9aead55a8fb9e9fa522207d21f3a87e624799e5e5787870fa26b3e7c4bf2b783768910c9b37457c240b2720a861010001	\\x9ad51d5fc97e4140f7bec57e017d72aa258c0fc6b56a674009cb1dfa45568b931e325f539ae2ceb16ae4fb4a3ea6aa29f985c26f09161cad996b73096db15801	1653537272000000	1654142072000000	1717214072000000	1811822072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
369	\\x824f89b4e8600275cfcfacc665d1a90d535cfbd7d4b950b25ededf4dfc3c09da6b5569e511f0c155304a723acc3a5cd65b4dfd2526568f5630bdd8f12e0f3400	1	0	\\x000000010000000000800003be904357f979035b7589d9e1b778d74b7f557aa7c68598994ea8f14f91390f11108b851ddb847aff0d7cbd6512a2c32862e72e87e839e6378a2bb68cf7318a00760fae0d9d2afacfbad0c358f03c6c2d09886525e68ca79229919213ef1fb13992652db67d5045bdd346354676f9d9e66fa0ea0266291e8c94330ef02c2362c7010001	\\x7ea8775aeba61eab278651610d8142b69758bfd231320a869b47267e9da524fd9874ae9df33eb053e8fa4064cac252bde87587bd6970d8d94c68b6e0fbd7e40b	1675903772000000	1676508572000000	1739580572000000	1834188572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
370	\\x8447e0a819b3b88226c1b877d962f7e09fdfb181a480a5f385f111101dddf943f5810288c9216653e42bf1c2fe509b6de8f052dec37b92541ba9f08e947a967e	1	0	\\x000000010000000000800003c13f48d18582cfffa1f0713ed206ce23271abb5e9e9d02db34b6f20978c6301b8a61cf8bd703a31973c622f7d402efc3f6a89afba959f13136b53713d28355a50b6d57331f3bcc9afee7dfbff292980e874f095117c0a3cf3c9194512acf2509602964c0be5191be814d4e97371fe4717c4f30b6c70f6a2b4baac56b4b182893010001	\\x1ed754a4e3037b5c736c7194da4a008fb273ba4db17c0cf2a9d72f5574a4f09d8c73b15a361fbfb06ad22892aa36a248c98ddfb49a5ab17f1069139e724a4200	1673485772000000	1674090572000000	1737162572000000	1831770572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
371	\\x858b3aa845da4bd0ad4bcc1d6d310e8db541a4e91f4ab7e6c8561a6b74faa7d64139e58a9ad0667e2f3b20b57fe47571d7a7ad1e0313feb1bfb5584203fb5fa0	1	0	\\x000000010000000000800003d8bb4d44bf04a3c11bbbcbf9e383a120802ddb53de01e99c140499f9bdf72c24a72159725c31ceeca92f44bc42c223df70a212a8c2ed1759855466452d5eaeec19156cab86344be62ff04cd75238b775cfd502d502eeb6440e7769bb133b7b6f11ee393ee1e274b29958d49677ff0b59e2911766632c314f382e4614f02079bf010001	\\x49da0d02c74a1a6825c6bdcbcea4090cfbbdf893eb6c4e6311e1d1019bddf73d4f6e53355d43407a63b5220c3fb85553f18b562e7c2398627e1419e32d1b2106	1668649772000000	1669254572000000	1732326572000000	1826934572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
372	\\x88f7f0d7089c17fcf9e562a5da2671cb8a3fe0da678d34a07fe473c63ecb74ba0fdcdf2bc9eac01a3b642a90ddc5c9baf72bfff1529ef62017cc781438482859	1	0	\\x000000010000000000800003e66948eaafbb2e26303e3b09220e9025139873d67b36a4cf5143c018bfe23b768eb4562dc7fbbcfa13ac26c6cdbb6d0576ea887f152b38b7fc8efd53af08723846b1d51467404f67f83678b5f52ba7b13a4459a6c2766168e807d12b193a4814a22cb6d1d744b1317a07720396c56cc2a3783ae7e7ab0ebb9bea76599999ee93010001	\\x03fabc35333d39ff3affcae40c52109a9aae1ff14592e9186c915d8341ba0cbc6a52e037d08b6233574e5e5aac379f746fb1ec1e6de8e34df76e503bddd10500	1651119272000000	1651724072000000	1714796072000000	1809404072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
373	\\x8d93222cd0bce26d385fbb3c11f5fa69064c97c65ad522320e96bb3f09319a54eda71d70bf3ed894e262c0aa2a0e1661317395c6876a87f37547d41d7bf1c247	1	0	\\x000000010000000000800003eaf17b8da4dd66104ff16bdcea7b3155a358407444e1839f458f2e4c5aeb706e6adb8a17ac5b6f7e060fe3cf9572e2d7450d19009b326d182c06b75edfc99fcd9b558dd48e276d4416e49522672e6ea2e5089e228b4863a2fbc148a1d2c6748c8e3289d0a6d15392a7f714ebf4fa52315580789f530cd7cc66bac4c1b4c942fb010001	\\x3d61dc3146fd507c5328da91f0eea9ac778d3bc4a79c5ce8c244685de9a179e20d3dc21dab50877ccc2623cd237df03c9da665253755fa2482616229ad317803	1665627272000000	1666232072000000	1729304072000000	1823912072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
374	\\x8ec307aff5d8b1cd877b399f6323f83cc4789c315b568372296227a3a8097d31b900d788fb59bc19181413652e361a9aea4c765b996ed74bf3c8ba81230897f3	1	0	\\x000000010000000000800003b5d923aaf4c762ac03f969397a19811a32032d26d18423c065a772aefea0f72f223fe4a368fccbadb8059981cb13f3267331a636bd692a5c7ee5757cae4d58f53036bb231892fa6c382ba1b1309b4f9709963f589cef567882702da9821ab5d0de5e63c036faa7eb3be18062738848b13dd7469900bfb0ffdfe9cfa74ee44dab010001	\\x2301707b92fd15125fba441d4cd07151b4e09a6aa71b989a821bb33a68c049d75b8edf969683b2b45e587b77ea6563a44ae81862862da11f4ec86d12e606d808	1665022772000000	1665627572000000	1728699572000000	1823307572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
375	\\x8eafdac23e572648badb17fe20520419c052f34c20b1b5b25b091a6f6f0131693f5350248e69bd9244432daddebbe8fd1e322d11c07ad66b74746d3d532b9280	1	0	\\x000000010000000000800003ba49f6d7e81fc53768815be69383083a560752fff307a3e3b3f58720a373cc60780f7221e4f3c6d45a505a51423666c2c4f1467f480c835e7fdcb3e302efa31c8fb8f91df00a2f9a30a38c52cedf484cffb61af911f0303d18ccd2cecd3a4574e655bec1109fc2ee97fce99a2f9cd3056b7cd0e8373af13e1f21ce241b01460f010001	\\x692d5b4d148237b64711b812ca46a9963bc0799a93551096d31fd55c06a55c995db2e916107ab441f6a15e380d438c2c24528be67dfce4538cebadde207e4200	1677112772000000	1677717572000000	1740789572000000	1835397572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
376	\\x8f7b508a675491af7fc5d42f0778490a8be05716209fe34cb13789b6518ae8bccfbcb26673a8c6eddf6bb97ac0c13e3680c68fd656c3100776d4d5dbb5ab54af	1	0	\\x000000010000000000800003b86224cdba3ac9179ad41489b5eaeea7c6a01db8fddf78b7947a9d4be7307535627cfc4ba84612a98088c96f62c062602fc64cc5af8ee9daab9fe4b10040c6778bbd2b6b409ad3b225d817b5bbf7c64aad93e359405eeca3b80b199d3c5894eadac9648720a181251c2be064c65acdae8f4e9f5e80123c80776d015c8e8910f3010001	\\x6a69ed42f18701a88825ddee1e2fc1c038feca70293f003c001cd4bd60557e44a0671161b5a1e45b5496f9cfd713e59ada6bafe2e03afbf9f60dec975eb01706	1662604772000000	1663209572000000	1726281572000000	1820889572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
377	\\x9097397f0ec82d212c7eeb09da75ce5442f3bc89fa7e5d1b24109672f5f0424b1f9646561b5843badbe747095cdcfa274e1f7d1e83556d1d1598b9d65ff59c43	1	0	\\x000000010000000000800003c0df2582448b6c14afb0b4839c5391d7e3148ab8c28770283ea1e41aee231e7335675791598fad66b73f2b2a0957b5e267f5b336be0c9702548d0c50b147246f0a4455809741409936942873611f344b59425578cf4ef1f6715d5693d1f7874526aea78afb8c70da1959f7afe196964cf6f01e54b16a7d8345f68799a5c70ec7010001	\\x9c9b8bd5cf7b01dff0cd86bdb0f8434372fab9d607764e551653fd594207a1767543d30e23115f6c362e8466869155987a81ea46fb0cf5925c1c3f289c83ab0c	1672881272000000	1673486072000000	1736558072000000	1831166072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
378	\\x97734bf12978d0cd39a2e25c431c4a08ec6c3a646660111dc90162eef83dbfb53671d594a673c23f3f7b87ce8641d9dd460cec01a5b5b8b8eb13e706854494fa	1	0	\\x000000010000000000800003a347714e6aba75ef36210153f051ac0926a5d49544c00089699d54a3afc130b7ddf0ec91ac963a58db5d947270bbd4a1772fbbc9beda74d8e68e780bf789d70c7260f1c3809fa002059f34ebe5848e20bcce5091e5fe694ef528cff474c919155114fb2809d2bdea31aaf16a9b30b375f2d93da8ce364d099ca835bae9e47597010001	\\xcf6e2175346fa2d24d1c89e1f4ac6807e6fea5f634514dc1f3d592f32a874c656ac3b940d06af7d72cc3916e5682b05633e5ca37c0c6d9603c92a578ae80170a	1665022772000000	1665627572000000	1728699572000000	1823307572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
379	\\x9a2f1295e0ee6b45c94a27e9954a0add4e1e5c7bfabf650963d51e628a5642536c6eeee648f4ef1254326d20b679be37a1c0b952c9236ba5f34486b8c3647c4b	1	0	\\x000000010000000000800003d9d4ce06fcfb377f85704f50342a22947c34a730feecdb770d8ab1630e4ef2b4c2f90c605760b8ae9b62ca9bd651a0440149c68b9cff7500b3ec45f9410d47a4e50be5e25c5803d0c1399def670a2b2b2e06a83651cfc39111319026b1e47855e95d5e3a696cd6dd3b06a20b16403d777fca8666461b8d778f1c76a72e48fde7010001	\\x6d4ff792423afe6647c89c5526714b8114bb9846cc76d8ec22c65e89d808692c9a643ac92b978a5a6857566424e5f61e79238de89d80b74031fbd50171b5640c	1662604772000000	1663209572000000	1726281572000000	1820889572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
380	\\x9e3f107910121af9bddb4f8ae08b7a5726b2c02ccd05799076e19a4eabff5b3bbdbf663b76703d47515240895c269b81a4eb82a8f796a05d5cbe88c41fb202ac	1	0	\\x000000010000000000800003cf6e8cac826b8f1072e07c3716e43e5524d01588ff351a7ba533a268661aba8c26d397ee2c2f2b7a9fac1d9df39a11043a4e7fb642bc80fc73089106e1578a5e88ffa6ba1b68d7ecca58bec52a0674d01c7334acc270c3195e29c79749a0b32d13f184935861b35a654c1ca60fbf797434770ddf6ead8508c7b846acd091b6f7010001	\\x7aa72be06bf28a0e27726d148ce49c31cac6e47cba7778837e673ba9fecb057b77c44006d34fe94cfca9965941060babaafe965a4d37dfaadfe54ea1314eec0c	1669858772000000	1670463572000000	1733535572000000	1828143572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
381	\\xa52b562812b8f92eb35d5f732826fce05c8384d7ea2c8752746ada4520b5c847d77cc7f1b1823388274d6f1f9a30f3a5379c8724aac798b0545952ae30827dec	1	0	\\x000000010000000000800003a4d3aabf76ac9c4a673a7e13a36677dcb266389e6a677831b17d4afe49720b91f7637f2f07aa6c17b6db09328c99374b6c1e968db26d16d5c546e3c95c3b8a601dca47d0bdb6b9079c418e60f876cccf2d3b505eb0f1c12e4846934609a84fea045c93b80e7580de69e56c65f81ba6f2b438570b29594c7131e5b76c4ed3945f010001	\\xfeb012c1d57078964919c2300ece46bb345186851b55eefe7273a136088001c8083910f57f86f862b6a4db89f28f2a1442785d56f3ac122e4b015e13ad5f3a03	1665627272000000	1666232072000000	1729304072000000	1823912072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
382	\\xa85740eda6ad783b79ee23564226475bcd481223f2c076b748fc38e8ae9746b1a42b51fa47986b4165d52e262e589ed3cd6e64a61e2ea3fbbbd28879ea27271e	1	0	\\x000000010000000000800003c1ef82e0158b25197e65b2bb8cb5671ccfa239460118f375f6fbfb3242574f8f172c80222c7e71e5fcb9e0ad4638621b03b1b5c957cdd90ee658c0c15a0068a43f5ed06ac361425423a589b1382f3a0a3d8a8b61ea061f1dc16d5a22228bf47b39190bc548f350c29c8f8acfae324a12a3080879bbaddcffe564705bf34619ad010001	\\xb21a5ccc3ee9a599fa0bd5c634a08721698a7d4845ab2a01c9ed010f7d4c01665c8bd30318cba600b1251e3e9e3ef885053a8b51fd091048f90ef6309aa55f01	1678321772000000	1678926572000000	1741998572000000	1836606572000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
383	\\xa9fbaac545f20776a324a2f3b9d74b122e51439bb20448dd797837341331c0cd4963f8df3745c7910a8e331d14114727adb2e912461c971c64d16a6c8219261c	1	0	\\x000000010000000000800003ddab65773457eb782cbc0a4fb9021a955fa248e6f739e95715474191ed3e2bd8bd8d6285553ddbeb1b8537b832e95d35ac9b15cd263575a783710a650109212fa4f99e0f2eef1c2ef9c3b649925c46622769e7f2170c20d51e5362f589051ca37a008945ef21cc8ee9c99e07d4eed555c955a8e1ca60f1a245c9a5d942bf9bf9010001	\\xcd33f958da5d293cf9c920d64c30e767427ae0307b9941fb0e4c0e7feb42875a5e5959f50fa236f0dbe8711fcf86a2a82ee23d61b20069dec473d832731f7f01	1668045272000000	1668650072000000	1731722072000000	1826330072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
384	\\xa9331dfb06235166af8226fb46bc1a0a7422005a9aa653afcc61de6fc4e78b9d4e5174f3b20c742a9775999a370c82102d4606d6e441b720d84858871c975fd8	1	0	\\x000000010000000000800003ad7643b3da49df488935c3595e74a72a643be8effb0ce97b63b56fc00c41e81f1edcab688b18f10ad495462693a2daf0b89b93ae92b2de74ec043413c3c6b2b65b206eef65026a86aa74a334c49a598a1abe8527443bf1429b525915a97259f730a610e439e4990f66d221c9e179da3abbe122164bf57452ae73f46b49d7fa09010001	\\x67ac84f1ca6fd6ea710d6daaf34fac9a049096c94f8c251845077480741918596c6fc95e8ba417bded8f59394350c2dfb6879d1b2dee497fe72506ae70423300	1677717272000000	1678322072000000	1741394072000000	1836002072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
385	\\xabff61636782d2fbeb5c38c8a026476ed360254d1cb83ca5174bef2d9394995801f5feb8a9adf77d918c2a2dc7c80a80ed74fb15c61d30a56dd93a79e37f22c2	1	0	\\x000000010000000000800003ba94550255fa9ebc09948a8d4f41f8b2ce28331c0e90d81b045e88b4f74b59c8d2e604cb76a760b0252b443572ee21af4a5c6a9e94bb9a463103f3a4c56b735feb5b6433dbac116b8cc39251f16acdc701b1778d0e7b5447a6a5d7e091b8cab5c9f3f8d103a21ddfd5c0c1d6ef29cbb021445b53dc288aa4522c6099f9a6362b010001	\\xee0cb6a6aa3a1421002c1456e1ea5b0394544835a16914140f310e3169ed135ecc22c78ad3f7416353e54025016c2d6d2d38bfbf0596009f0a4c32f8fbbe700c	1664418272000000	1665023072000000	1728095072000000	1822703072000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
386	\\xb1af949e678808d872207e893c4e2b9169b67e9da4a4ff5aa5f64c2d7a7f46881de5ad5cd0bca2d47a5582fe810755d2eb302bd116dfddbf5327fede3445daa9	1	0	\\x000000010000000000800003d190aed01d489f2dd7b3e608a3ef1a4b1d40416c9b5d23ad1c58baa2fe4fdee30dcf0070f7c307d35963f1884723524f9c186b54229bf10512d747010a0695b786863f65083d4b416aca5fc6e94fd8616ba175dabeac7b576f5eaeed487b38e5df045787782a588509ce2b3c7310735d53a94323dcb03f9d395455fef648f8cb010001	\\x5a41f2f77dd18c8c9d15927fdbbc92c882924f27c9ea8d72900e951a7199ec8194a3e3586798bcc3e51eb74215e2d1dc663d85a08129c4a307ff665c5e7c640b	1657768772000000	1658373572000000	1721445572000000	1816053572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
387	\\xb4f3eb12efbe643670cab7e8f848231fec3dfc07e2ac72a05fde0b107bbdb27196dcde72422cd7485014f92ee113456208cf8a53448f212487f01345b25c4bfa	1	0	\\x000000010000000000800003c33be81307905646be85e0ec24255524d7ab12aaf8e293e8bfa1bb41b6f079639511e4907838d3492ee2afdd5634dbdcf7b33c067f864a89502398698977a8b3eaa95800e74b4b2b13968e8a5857ea0683f26a13547169babb144290a8212aa83bd5c41750d2b7b319429598f119743004a1148c7cef3abacf8a47e5edd261c1010001	\\xbc6b30637e5126695ef92dd2e3518b469477e9bceb52757b195361549838d68ca722c9ca12da3da82b891d3400f1f5c8e267cf4a612d3224175f1c4558264009	1648701272000000	1649306072000000	1712378072000000	1806986072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
388	\\xb6d31b021390d63c018f050c0ca9c3358defbda3adc3f4c64640e75ee28e06ad46d30840cff6bf628eff29408a335bff0a9ba092420e547babf9efbdd807a6ec	1	0	\\x000000010000000000800003d78254da7f8168d5f777f2dc0ee54ea026dfd8109bd6f11862809d6047e0cc9dd8d8909ab43ede56e645db369d524835506e3c91a8b22c1371261e226098b1eb4d877392bcb2f9a120dcf27eb44be2e67a858f47da9f1edb8870b9a72d18aa9aa3e72e47936f6fe73c61f6b1fa1c2f9013e0153f72d2ab659834f47873874a3f010001	\\x13b5cccadd108761fd926c1964e5b4346a0f39c720354a9a4b129aac0512d8e7047f790fda6607432dba766b912acab763c64cdcbf2b292fdbb6a92391d0050f	1651723772000000	1652328572000000	1715400572000000	1810008572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
389	\\xb6af94626edf5c67087fed8cda4d5612cb2b720447964281c50b58007ca29f6bd108e78088bc4ddefab8814a28ace94859650be59cf323d318b3759b47c62c42	1	0	\\x0000000100000000008000039ec8737ec154006cff07411e1a85a95bb4e07948e3a1094d38c9cda3478d01108368e9a9befc87aca27a1f04861030d48bebfdd0ab31a6ed6ecf6917366c9bab9403ed69a273c200ed2a22beb9b3f91896b5eb289dc3630495fb9d0d14d8f2045b56129077b262dc083ac33abe886344520cdfa4ec44e92c99e5dd6cbf493839010001	\\xa13fc4cf4f80602b372d7d67188515284c7b2ebfc8050706ef29a2357d780b6bf4ccd7b5e12a9dec337d286655d33811eeb02f265c2f700e9d23831c58e3af04	1654141772000000	1654746572000000	1717818572000000	1812426572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
390	\\xb7730ff755fd62e8924041666571948ce9ee49c336234c936a5a76565f27d9ef41b64fb91449e3adf01742bd8d19a7c4f44464cb039883140786dae691bf7992	1	0	\\x000000010000000000800003b84993552e914b27496db207e3594fd748964ccfc9d5e9495ea30f7150b49d4909cec0201b32b1cafe64bf553e673eb37839e9c2d35abb827dbcbfd718b426d1ccb3ca82c8b2c1a6a4d50f48c75085c2c013af0689eacd7da2eff5268f042764acca0fb24f4b3b13cf641d182fe6fc2c1ae8cdd47fd25690e64a6e08f2bad173010001	\\x5fdd2488d74b34a926d6c8af1d57502085071a72159e7d94a1addb1ce9dec150ef774849e420bcad8bcd33cbb2487193ad6afdadcdbd884e513711c0c5c03409	1663209272000000	1663814072000000	1726886072000000	1821494072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
391	\\xb80743391309eeec459cfa9d75711b25e0f3373f154b554b227d17a1443cc4c1bc5f4ba9b58c15dbbf6adceb11127432f07b59ffecfdd329b2845cebee48ab97	1	0	\\x000000010000000000800003dd57fa6e80e8379707f95af36ce1253c1e1530e9a99eb9987cda6f2d885d8d1206ecd4bc48fa3cfb76b8b06fb6cf51fb72b5e55aa362d547c388d401c676e968512cb7c96710e20b707624702b6273287f6fd6ce304653d553e5a1612c597d712ee6b1f029682bff323a5959aa6f3cfde41755bfc3bee7ab6c5bf0ccd5cf0111010001	\\x21d2af0f7c15b4dbd8b6f83f5a3af6952ee72367bb582ccb8deb1505086932cbe64bc0f2a34ec2d3364000cc8ef3ad4ec5a04542aa3ad8d13cd2aed1b7e2d700	1650514772000000	1651119572000000	1714191572000000	1808799572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
392	\\xb923dfb6c2848516e36d1de09a23a1bdb3de053aea6c3db29ec02f95d63964ca4f1ea66f6d4d828b531aa2d40efab449d7f6151d420d658ef1f55f44b35a3312	1	0	\\x000000010000000000800003bd80e56a17e31914c2cc56f8b606ed898296e74d631580a6eaff24bbb007de93a8298bc869cc4e80256fe95a467ca187044d22e222a51b107fba88a0a302633a5810cb0855493d5a50d1a153056a44c0f4aec87925d7bd64b3efd0d08f127c51b639db17dc1dc8ccbfa59f89f0c90b2e08099f5f1bb48078a01484c726969769010001	\\x24c7c68c6be01ff4239cde4a552f26e1f59bd24bf0f9645689d356aa5fa7142aea8e5deb0bd491875da67cdfb0e08199f4475f2789e3c11ba4bec66fca9b8402	1657164272000000	1657769072000000	1720841072000000	1815449072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
393	\\xbab75bf78a80f9a0d4138392586deddb3a3cb77807a5af26ec0a2052a704873882af74b742e435095fe49e1bc856073562115832b0f71c686fec597dffe4eb17	1	0	\\x000000010000000000800003bf29c5f1e897c7ad613453ac1334f97179bab57f119d8a00f8c7a81094ccd2f779db3e56bd13b177fa76dc418c65d76d3f47f768856d312a635fbf0319dd5a786b8099313ba653137d9500690923cda4477f62b87cc93915f1921cf1b1e980a0a82e991371ab0dc0cd8941d20b2a90b3215cd3197bb07428b86e6ba32db52155010001	\\x1a990e7accb0937a3be8044886269fc00a18939d639adf51021d27c6174824c2ad529f52998499e22b76a0a1220bb9c367e4fc80954d0e5a522568c5fdd9fa05	1671067772000000	1671672572000000	1734744572000000	1829352572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
394	\\xbc9f5c68d500cb4085ed7129ed476f1580a0c5695fa0a0a189b5dba9c6ff6f4ff6baa3a9632468688f04b69d425c67435d1938a1dff40dd7fe160eb489346677	1	0	\\x000000010000000000800003eb557bd366519decd84875e48db68c30fd29c21af13baf6521c3174742d2227c8972b15cf6f75b61c328c3cac5f02bf9a693ea7506951d64e61e50dd900bae6632e1616aaba9c3ea67a8d6e57eeb9f21a8762d4f755657db4a8e5ade139b3cca6268e30073408919e9cf95907293ea85db2e7117bf6f5b204561be3487be799d010001	\\xee97b9c75878696b1ad04c33cc6901ae21b44a477e8e93828090e499322d78db0b782e5a69ba65cbcd9e935081fc6c2dda346ec258a0645fad32b5c6a8f41202	1654746272000000	1655351072000000	1718423072000000	1813031072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
395	\\xbe93478e02281f9e52176256f5047f3a26fa7c3faeea259ae5f404fbeead16df8a9a4b0fd079f19d1841a5cd7c2f3ec09c8651a0dbaad647712099f621b52e44	1	0	\\x000000010000000000800003b6c4d8609621613737c4d0ae2b15aa96d6c176d5c834a4a9321623ad2c9fa2a1001d5c984633580944111c01f16a0d6e8248c2320dada232aa6d024eb6268aa8f5e42b98a29b7d92050b57c26119c44bbf3b9bccef1a13ae4b7b5811e52e5d7195c37e4dacdab8c5050208dcd6da750814b5aafb9524896e0549170d482be26b010001	\\xa9480228a776c62a42c66786760b82ea5dea18c636342ce554f1ae63d2f0754315424aa78a8dc572bf41828839b465d553cfea3eb03492f4e71bc7dff9c30803	1660791272000000	1661396072000000	1724468072000000	1819076072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
396	\\xbf27df56fc935f88141db08502a9d9c40684d11ab948e1c4ed49d63db0a48df68b04a35e5b31589576a333a995b3cfbe4a550a119a8a331a498f252fc74cd562	1	0	\\x000000010000000000800003d9fe21ff406fe2f505c1813a145b75a5e92755e1d5643861bfda89e1ea3d3cb48010ded9eef23452ff362ad21cf605cf10a4b2eb5f4e84296888a04d38eb412407228ffdabc83de0ca228c519ef4e7a21712ba5ab8ce891e066a23e3509d152e8c26bff27337be069910c16098c2586fad90abbaf6fea7445e790fbc75d92c1f010001	\\xf02766516685cbe02ad8763d8470718348c41683c5d4139e56e57f02c47d7202e6d7f7685d6688989e676eb7ee4ab3e8b69be78cb681ed97089edbfbf2842703	1654141772000000	1654746572000000	1717818572000000	1812426572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
397	\\xc28f23167e87113d42e74b6cb223f8deba7771dd8f41eb10f3d869ea1636ff5d7242235d6b5489cded8cd2aaa324cd5e8d1f4e1f537a6765ec42a28a0350c57b	1	0	\\x000000010000000000800003fa67ef0fc094d197f24901ec1917288fdb8973810239cfaed3efa19eb029c15cd6c58fc49333295455ba3a460b1b9d221aff339f38518b612b8f25383ae44352c8d4ab61075d974e0a61868164c418b6444dd0f1c685cd5e5ca190ae4121bc080e0ba1bd82676f6a191de664c00a116753d9745c038e7aecdf0542b19cb33363010001	\\x5eb86eda129983de1d93593b964a1c8189e853f60b98814be03f301be0355968ffbc63bd90527ed1973feda7b2ba9f33fd1fa02d29afce7537b33ca58d4b7909	1657768772000000	1658373572000000	1721445572000000	1816053572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
398	\\xc2ef34d5de1d2672b3f5dd1469d01b23dba2b695309118280821a426b638085fe0ca8d1f6aab3d977eb8389a64e66d5561100f901b03b2c3ded4de52c04f6fb0	1	0	\\x000000010000000000800003cda2bbdc4230f1d72c76151b3bc6fd377a6b6815568f66dc188baac507bdd9086f3de11037ffcf7601a4bcdbaf1850f9b3fadde187d74c3b7409743dda93a63b390871090cd1ab0a266efe3d12da8ad5aeafbeff9932dc161b5c6e52282fde450c3c61ca385d5a33ebde076da225434fe757ef9d57bde9c74526b6b565cf9003010001	\\xde2e1f04bf18beaaf3ddfea744d84d275ae327d5e84f840096ee0c3cbb44dfc9226969243e5c66cb5ce6128411282324a7d3b4d4a5a83f073b5b47554d956801	1660791272000000	1661396072000000	1724468072000000	1819076072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
399	\\xc32b0444790897c274cdca73fda0508a122ad3d345ecb9ecd537461091a823f7bce3c008230e946a674697f88b9d6bc66c03c595921c5e43fc6037961d057858	1	0	\\x000000010000000000800003d1e1d0718c7887942f79eb467c83f586fd211d4878687ccd40f6021b36b28ac91e3c7d50944644dc2c2ea199b65260940ce2c8a81f8224e21a60e1daa4a3c2fccceba6fd9cb9546af400cc33d5ea91e224c6621d043b7ec1facbf7e39da123ab78cc18ad21305134eca44f15b5f2ab641973769e8af23f5c99a28e3a60e01921010001	\\x2de6e480df220b45b2e401604881614b15849a78101c77f4d4927f32c2cdb6feea802c02d2795c7ba53daf065f0d0307bd8612a08628e8259314cdee81f79907	1659582272000000	1660187072000000	1723259072000000	1817867072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
400	\\xc523d5c3e0d05b1bad910760e807dd65e75c5b0eed7c1ecc99416663b7e0913c1791f3de2a542cadef54633cc3436911787766a494bae3d487b1ed245c132472	1	0	\\x000000010000000000800003b00b986081c453d8721617837953fc3bcbc9c7e4d56b3057f2b5d44d56542557819fbce42d1875fcb94fc747b55803817879aad875fe719537b01c9a5f1d9bd000bad497e68079492490b1648cbe1889fe3edc67f3eebd8bbe481c009fc6736c93cb8e475621ac155c6a3ddc6f84e130b0f57c5eb6c3c870ee94bb7f371bd32b010001	\\x872951da05e36a5cbe000d652f504568903c4a6bf2e653c4cd0b40be0211b01eaa48e6b38513fa0cf84008ef95ca5aa4b8aad7d7a428c04bd0293d32f1744301	1677717272000000	1678322072000000	1741394072000000	1836002072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xc743b0da6a42c898b4f5fd874e84b31fe3217129391bab1eafb3f3dd81afc4232181457e2635ae4617d88b12fb214eeafc36a240e60334d707a4867e14db6661	1	0	\\x000000010000000000800003c177a48e09f79d9a9deffe9c68e43e642909497bc353739ef379f069ca838da3e08cb4b261f6e96ac80c16b0193e6503a4eaa123e45d94930cfd0cc68996b6625490fd41d9183b1373697850b1f4f58e1ba5647b5666016eb65dfe07b6054cd54ebc4df636af3081613fae6a217af2faaaecc040eaaee071579838c435b76bb9010001	\\x1eb9c8ff07d8ddb99ba10fcc5eee2aa3641abce3597df5f1e4c25e2f1857098b11b2b0504da59b89d3661dfdd5212211185131210a10152fc0f7b6de6d3db704	1677717272000000	1678322072000000	1741394072000000	1836002072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
402	\\xc86b2a4bb48439f524960bd09bf10c3e5cbc978a0946e3a3765e66a3bc5de18138c8ddfadc4d59b9b97ca754d50a2c75f0b0d58c35e366d7e08bc95c6bd7ffcf	1	0	\\x000000010000000000800003c527cc196749db7e7cb9d658c3dd410b1bcc4e04267da3bbb951284946da865d5c3bf9c2098e4e333b4e45e9266e0426097607484be00d6ba8e06090988e0f4a79cbeee839f1ac619f6f77bef4e55cdeb94cd19b39e6038319a9181e592f4b2915f8a0322c497c155fc0745b28bd5ddecac183250335b6942406bc7c11d7c0af010001	\\xf7c7afcf5c9d2fa43b68abd8d11194c85ab225d8e7163bdff8141ce39623a305862a7180c441d3eaf8a76c6b12b2b2cb0697b0514fe2e6511e74267b7141850d	1675903772000000	1676508572000000	1739580572000000	1834188572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xcda7f0e7bf58baa771ac83923662b46e72adfee227d41b0d8df152129185f904776377ad0bab7ebae65b6e82cee90aadacd745d4d15b53907847f45bd2a904de	1	0	\\x000000010000000000800003cf3a4c5fae4529e0f1b11ba4abe307fb41690a256f3c55e6d4262039b8ef85c8d1a5737b35d501e3189561caca7d052d759aa573e30700bbe5c0ca62c989b08f7444dbbc9b6a5c5aece497430b35a98e1bc4a0ff6d9ec31ab7a54ca1adc26f216e9790f037a6c1b737c4b227af6a8e10c6d13495d43a0c771f928d3ff0a13a31010001	\\x5d0a46d751a3e2d1fec2a4872daefa7f5fa1194e9644be07fcf16c1b9fd5529b73b9e514509f99e9867e7970178fceeba26a2203463ed14b33308f578fb7e900	1667440772000000	1668045572000000	1731117572000000	1825725572000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
404	\\xcf4b7bfd155adabd51813ae43bbb4df81b8ca98fda4f668e3f4814de0466b97f178918e1696cce6cd27ae391ac2a3bce7029dab306e4621a99196c69c87867fd	1	0	\\x000000010000000000800003d1c8b8f3fa32fd4c465c3c9ea645adeaef5f275c2038b2da074417fa863f5dae1fd7f46c8f198a6b9480c7dbd3b11de4d24d1fc338248c12e787d850879700b651ab791014f9f05d09721f5d5885fd1d21165e37cffe7a490c65162aad7c8187140f498334069b86a24906c26317e45ce6c4f8d3257a92161514d1bbe803b7ef010001	\\xfd0cfe1a44eee67bdc4988af634b45586b9475c84152d09db439e48e4b872a683f8b8452858c82e702f33aea23c88ba62e05af3e2d64120612e98f5ac93ea90a	1673485772000000	1674090572000000	1737162572000000	1831770572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
405	\\xd09734996a2f8cbbed5a8f5f08a5cccd84733a715a2311148d70bf23d856b1f92442f7e02f6f7bce9f3826c042e1c75b126ed95a6b5445e8d2e50a759f7e23fb	1	0	\\x000000010000000000800003d1f2fd0a331d2d9c344d9229c0b1bf2df2afafa59750086c662d519ff69e4fee0a1e724b1c13c1709fcfcb6ed14a23d3efbefd825709eaa5ef861e0562fb4c33c62f3a2bfff65f3e057cac9943976562e8aa9cf3bd334cd6f2979aa0ae0b7220e31e1854d4906c6a7c3bce70088c50062182bf1bd6f1768b030af7b0ad134c71010001	\\xc6e083a2e7b2443e996c35b04b2e524218f66766bb1ba09696db6e03b764c3622003580d4bacf2c135a3d79de579c97987ce87da826ce51745faa34b35994c00	1660186772000000	1660791572000000	1723863572000000	1818471572000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
406	\\xd2e364d509a0225c7514d1b2d0c6afa21018b16551713ef7d758304072a475c3f612b1160d7b61f53065971043703bd9ffe983c8ffa863ace317e495e7c788b0	1	0	\\x0000000100000000008000039c42d14172753b9ff996bfe8c53de30562c157d52c9a540be734eed0666dc204ef12f6cf6f4bc8d58da3873916ea2a78203a879e1c41629bcf4a58fe6f98af323bc6589b6a9f2c4de8679476dca423a44869eb9d06268ca50313121453eb4afaeb62b091fe9ac4a953df23d6ac4b7345286a86dec18fb90fffe902c74a2ca1ad010001	\\x38321ea82be38d51c9e56ba3bc3369d1e7625872764fdfc6b3c712e28a07f253083eb7c56c70d7ac705f098c3d8afb5c9df05f7dfdf010c1c9368e177d4c8b03	1667440772000000	1668045572000000	1731117572000000	1825725572000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xd597ff87de1ad1154e25099e50597294ebbeef629e2294c01e2471412df7dcef9c49bdcfb0af1c88e6c0cca74e63453d3db255707c697edf970699633000a65a	1	0	\\x000000010000000000800003fe430f01eb7439ed622235f81f65b9e34727327a83f86dabbe1df7dd55a183a09d5dda6e4d6089f4a0f1ea3f8d7ca75aa68a61413aa08daba817bbc8df6a00fc5b71d4bd957d2241224e66de28bd00861d453e67e29b2f70dc660b228f47abb9bd9c87f6091e9ddf0caec3384815228fefbd2fc9c1eba5d850a0f31eafcfc2d7010001	\\x8d957037d8b6733e14283beeb2eb29409c3a5b3ec5f30e71a7b86680a384d26e4a9737bfbdcfc54323d91e97767ed3c87ba0cdfe25faaa780ba2f0ee9a3c9b0f	1668649772000000	1669254572000000	1732326572000000	1826934572000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
408	\\xd5f7dbb5a9bc303f7ee9241a0900b2a793db7e9360ddeafdb31ab1d3015bdb3c1ca43bef7a5efd4fb8d647214eb3b432644a2767851404eb28eb2b07214cbcef	1	0	\\x000000010000000000800003b9415065a05f1d237620fdc553d96618c19e750716d25ec2f25f9c0a03658a8dd302bf33a40007b2764032b8cfbe7af76645c9ddd66e4fe1d143fd076340f0e2a75ef51f556165aec103eb0ddfbc138691ca7cff60531a4515ff6cee2f8e7d44a8bb6dd9e0658a5a0f1676674eedc2060ebd1e571c3b509c6313d4ff103dcd37010001	\\xfc20e542d7caec1b9c2c582cdc5de60e4ea4dca05670cbe0e077d5517e2f388ed2520c1274d4f69cae6c23ce56d1ae960309a53afdf06f2ba4956dc3bafab70e	1671067772000000	1671672572000000	1734744572000000	1829352572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
409	\\xd527cc6518d7ab48b4d13e1ffa72ba4e612a8039f52c6c231b2e25459b0d34bb81d2bca85a595c21d21b210030388c17be8f27551347aa0233063368638c2acd	1	0	\\x000000010000000000800003b64c015573b9fb254d781c7861ef9872881dd60473f95107acffc6b6664b52adfc7b4f4fff6d80389f6355acdfaee4c46936b9083d15bf373217c1668dcf5f3bdc1c267741833706b2778e4f36cada373725b412549c0b6a73d46cb272836d1acb1b06eeacbdcca2d7ea167592af9ad1637b5faea2c993893c7af17b4d2e8011010001	\\x520f0afe9c1ee31aafb941589c35efff23c9ce43224465aa697e1a098aa89f1cf345457a4ea6b5f43475b8c7ab2876ccdaf37cda5d6559e1de0efadb0d194a05	1660186772000000	1660791572000000	1723863572000000	1818471572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
410	\\xd9cff2d68c2156aee364f8f97828149f6497dd6050f245fcb547fec0902e9319508af9a535e5ed91af0d217387e8c620ed88fcd6aba6c7b5f2e7b0ca563c5ada	1	0	\\x000000010000000000800003cfd9272f50c5fe875987973094f1e8762aed0f37eb20a21b648cfdd09d325e5656b44085405fb3b1e07900b7f12692c25c0d9334e2bbbc7af04f3355542d61915153121657bdad8f473a95409d4ba177d6a5f5d061651d68d893cdf7dacd102febcec6796b9655691e8e411eac3f7cc0dbcf0c72c36bd9b0edfef46cedfd41b7010001	\\x67f383e30d012cec54d204ae8a44b5c25dbc69d1ad8ba95eaddc061d71dd7778f41de88c1ca9a918264db3291928e7f6a34be11d0a5dfb1de7bd1c48aa1d4500	1654746272000000	1655351072000000	1718423072000000	1813031072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
411	\\xdeef54d38cb2f368fa6ec219ce100cae83eca1173596e1daa5e98c4a2ae3daa498c732887c259d1e8805f2ec1ac0ef2939f4b0490f198ff1a4e9f8cd16286a0f	1	0	\\x000000010000000000800003a149defc5d365be3af85efd7e1a4b121129c533197285445457ffdb782bd465bb17da9d66beddedf2374fe633b7555450b59a233c92b2e3c040128ac39bb5909b25db35a90374c31b261e91f258012ed622f971098af0425029050ed29c124b855f8129a0aa920e44e2c45826525cbeeb0142e8179bf6272cf8f99e0bad47de5010001	\\x106f462ded6557bcfd56b94ac0bb6e555c44a73373a25dd99f08f3136ed374c6ccff6f98ee56b7a4a018934a7a33cdba4d271e73c2c76c2f16984be793ec1d07	1666836272000000	1667441072000000	1730513072000000	1825121072000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
412	\\xdff320636246f94a3229826890ef54244e9572d98d9aa152808b738f1d0d52e012f91a2d2cb1ac3c0a76ee6e7120aaa68375fb1cd3f24a3c862b60f1c66cc792	1	0	\\x000000010000000000800003a9dab396852675dbe2a1a44cb3f09ebd15733f16f9f6ca53337580701b474e518a3e152cfcd5f7d56adb82c23b891c91858d7c1d82ccfa7383ab923b001534bb157a898cd972a8918082c7e10484a9fd0670fc7d83ca42b2fe627c18c71043fcd68cd846b65cb618a0f264d06f4e4468f985ac1a3542a02f8bb0caa7ff61807b010001	\\x1453b4414364f01d96f09f2a90e0271607ee1afbc772dc6c0c468eabb93b7efb59e04b8f8abafedfa09d58b4be16931dc6a5e56b821c7e71f552674648331d0c	1665022772000000	1665627572000000	1728699572000000	1823307572000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
413	\\xe0db59b1d0b67890b38f7474b1af511e685d20f49ee14948f401314ccd41b36073a147f92ab7771e24e001d363fa1593cb32ed9dd95470dd38e08cb22780de3f	1	0	\\x000000010000000000800003b65a26c39fb6a85319e28cf82ed8841b7341c9d14a0fa055264580241322642ef32dcc9b94f682bc3a5c2cb85949a51a01673addec1c0c68cd098c499ba39828431f7d28ff2fa677a0c7e6d5b601075435e67cc313dde3387afae31c82a1738b07cddfded38711b90971c2522d6b7ebd8a5c50827a11136cb0509672490f0f69010001	\\xbae51d3a0d5997eaf690db1d56d338540d607f20de332eb367193a6d1628c86e887e9317f1c308cc639bff1dce444a2f8256ff5e658ad96af8993ff5952fef0a	1664418272000000	1665023072000000	1728095072000000	1822703072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
414	\\xeb37be46179f6e5d03383006798df2e15500c6878ca24465135b2c974703c3e503f5a4285a459d765a53012f8e4e5c34fb9edd12209d31386e633c2cf2311bc9	1	0	\\x000000010000000000800003b120005a484e066c26b76d1589605e461f6e2ed2dbb231e84d934d4cdda30d7d722588dd67c6b2006d3c2d022537e8a21ba07218c18d63063ce4b4b670a41b815a0c09f229f4d49f75e61241799611c5fef35b28ef2248d8a6384098fadf503d783228bda2fa8dbbe78c75808c695385f1ab3b365c3426e6402f60f442cc4139010001	\\xeecf6390d9bbaf665309e1c896a0b1b03064ace677fef82c1a8b623e23d8d289284aa074b4f5bc4332174ff7e4190f229ec90b496ae2a73650ba4a851be05600	1657164272000000	1657769072000000	1720841072000000	1815449072000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
415	\\xecabfd62f0fc317718e364bf3cd2492eebbfeaee5f9c308f237fa6be2efb5e13d9778ec7ab6056b80205b00ca79c090a865768fd0647b560270dbfb87bd60bca	1	0	\\x000000010000000000800003da26e4450ffee68ffa22bf90341246f75add92d50347bd49d236f4f155f4a2aa601aa01f7ba7eae4705114b704b7f1db00d890f115e025c3cc0a69599d1a6df721b1763caf719ef35fbbd103148c0c6bacb8af4663725de12c7f75d3ee4dda51812ff7c81e2f020d2bdf303c8619143bbd11b9e6969163a2e601b31a59de87c9010001	\\x9f7d0b1beb0c97a77f1003909bc2d99fe9b962c2864115e910494f2bf8cea2ba4db51de69690dc820bc03c1175e60f070122140444ac3558384e7389ca88e30e	1674694772000000	1675299572000000	1738371572000000	1832979572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
416	\\xeebb549cfe41c75793ef7cf2da811052d9e50b22e09ea635b9bcbf914ad69ed102d86113ca2f199726c9ff7f34076933ee4b40fd9f7f0bff313686427766428b	1	0	\\x000000010000000000800003be38e0fb35e171776fdc5b283836b30bf720b1b7e6ac37a2f25ab0e4c05c4edd139ec547fcd308de7f7f921b54d50b4d7475077fc6afc7b51384dfba04f14976742ecf71dbc1225289596bdbd12d6e779a2b5070428d7fcc64d4beae557ff9a0dbcfaf2ff584c8effd9798d127a239caaa140fadf3f060c12b674da26d81f68b010001	\\xa5455284cf54e0cb2587e9ea30d84d0308e389958123108f47d4ddf94b8cece19dd78015fd7a826238f1b87d6afd7fea0a77d72c7389b5ed5d69c8c849c05304	1669254272000000	1669859072000000	1732931072000000	1827539072000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
417	\\xf02fe9d1525142ad05cb8a5ef927cc0204ab9a33583a3821002024182d26943a05c78f6a02db6efe34bf41f05841663f58d43d850dc564f7e90f4cb413488875	1	0	\\x000000010000000000800003c29fcdc93bbe3c2f9178d40ea9d74d320733c140fd916c0de46d0e37aad1a76f0b6b5282b05d72363a03c9635421148daa3b34b544f7bbd6bf19ca213f739119f42c7dd98ddd3acd9e24cf2fb215c27b61a22d4d6b17df72acd8985763aeec2aae6e434d1146863fe84a2461d6d3d57cc33dca9a3203025c360e61d7d8169b83010001	\\xbd6e4917413bbf8ba3940c40053af9c5b01336de9fd72f36ca9e60a9b25263dc36709f158c40c61bae11973d92eb2ea2767864a1306f215d261269558feed903	1670463272000000	1671068072000000	1734140072000000	1828748072000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xf1cb6496b4cfe044c499d5e77e34a7a88381ccc24514e58bb9624df80f5ed7f961a64cd423aea8d9267e431754780a1a76ede76330c266e657e1eb4301419f9d	1	0	\\x000000010000000000800003c50820df1d15d35b4701f6e85a7c4964b1c92733cac1f0588527a84829fb7894ad5a2a20daee4443b3a76a4ee522f7d1eed981bd028a220f618b01248ef092701de75160d53b7dba440347e93096d237f4b0352024821fc82e604cf95955b0a86e0d759779a886cdc5c8ebd84a35c33368c91947f2d8334f1860f7063227d79d010001	\\x7ca23dcf1384c9d7809c796fc36210dedae89723aa03dd21d9152e0b01cbfe3cb4b296cf09c3ebbe8342c6a6f6b396c7ae021504583ccd2881a044d05ee40507	1652328272000000	1652933072000000	1716005072000000	1810613072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf1af0fbd1bdb4441a7655a6972581bcb8f76beff37a151edb7b820e786d4c825bbc3aad5eb7d871366fe75a5b78470aed6db40494b47fc6fb15d4eb1d08a2411	1	0	\\x000000010000000000800003af01f81697e9cdb9877043b2e6aef4c28a8ec9e650ed1672681deaf0d0e217a56fb676d20b290af0dfcf1b77e966ec9d513274f12ed91673d35e12719712eedc487714b86dbccf36fdc1cae72feee938ccb4229768993ab4f7cbbabab8a0ef6d50b6b419dd14a8388d9729959f537a2fa651eb13e5a39a4d52e866f94ad8aae5010001	\\xfe18083fd409900574ca3648bf25acda42a50767cdbfc97dcb1315f097b4b0ba72739c26429d1cc67e823c4ef03ca8dc8cbcdda632b69c7f7a0a7edc1c89b10f	1674694772000000	1675299572000000	1738371572000000	1832979572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
420	\\xf18b662551cb83807087febb6adf5064048ab085e86b47e67b3fdcafdd90a13b2f3be73c74691ef554bf34356e7344aafd24031f1d3d02a2604c3b1713c17edd	1	0	\\x000000010000000000800003a4cfa7c4e7d2e39c63dffb2d23acb6077f6fddf2175c00ff141c715bc7b9a71d846c231dd23db2da9fe4560b074f1af2922dcf4666407a8a8dded6dbf0ea5477aa771b3d952aab1338ca1ccf07d318c1f2fa9b9aabe94d538de6132e3d39a23d6516c102911dea33d83c60137e0e7cc2fe4e184d4aa21f54e5ba317a91e1236d010001	\\x4f00171fdc7bb604b35d8d3fd166898246645726d09cae86dee2369d8cf25c1d0e1b4f165302329c3d4dfcfeaebc0ae55e2d4ffa9c6118c951c6b384b54bac0c	1657768772000000	1658373572000000	1721445572000000	1816053572000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
421	\\xf377828e2f1c92adffcb3c6bd5d3ab4c22f916bfe0e39902aafab7c80610f67b04f2989464701b2ff8740593ef8b2f2f38e697a3388d3921232fb5d4b6266ab3	1	0	\\x000000010000000000800003a2b62a23c57d35fe85ec20dd6ba05631161c15cb87ad39193530896af69e1cdc94eefd8a3e118101977f77ff0254a1874fc4b70ceb269e0d674d3f0ec6e77299bbf6fcb7bf8ef395a77188e7e5cda73994d3ec4a981a00f5e61b801e985d8ec5607775a00f10b53a955e6ec65f4d52548f4d35eff3481c841513e805543e7f17010001	\\xd56441f6b4509ce71db3135be9af5e6b3f17f65b500020845c36a60c547e65ffd581d6facb4bd479f88c57e4be621489af3b6e8fad7237fa1a87b8d94bb4190c	1670463272000000	1671068072000000	1734140072000000	1828748072000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
422	\\xf49b2320fe64265252bd01d19ce0e775a323388925eb2574871eb8162d5b78cc9bea4b0af28692fa41e43f73f5678a293b6de2e2f8b2822b91713e73a5e2546b	1	0	\\x000000010000000000800003aa48a7fe1e6ae3f1e4511a19bfc600d5b92db4c0e17085eb67b933c94d36411314e55559ab029259f8bbeebd869c02cac55bfd5acae7dafd25b4bcae7a72d4456f0f28d196e4e2b001ca3fe4060742a52ba9a9e6145632727263fed0e3b57d1413d7dab79c1c8ecdb4855d6e5b04af1ae1471674e83702b5bd6aa2c582ded7b3010001	\\x2daa47084ae90311cfb9ad598ec2494d5341527030dec67ba8fbee4721146e178f878c4259de0087aca687b3affcacb94d796721f5219cc5b4e87daf4c4e060b	1648701272000000	1649306072000000	1712378072000000	1806986072000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
423	\\xfa5319535910106eb8e7774087961f17fc068084333e450185e3a4fac00e2c557fd63c299c063400ebf544fd03652145c122d68c4239f477c0f6b9a9b09a1834	1	0	\\x000000010000000000800003cbe7ccd3ecfa06669ab827ad775c30d048a4fb72202bffa7cc23d733160d66145f234ec694ff7c22943023eb3b3c2d0abec98d27507c5b93d807a0f5086b500042b7fb269d11f25d47f3925f8d5b7828dd1b8077dc2fb6e5ba6dbf1ef9946ca65e9e0e33ec6da6fb0ca9b1c232387928592b6f17bc6deff3a3f3568c716fb48f010001	\\x707c6149cb4063f52d67fa5b6ca19f2126ec8d07773a3e0ab645593d5a81479686a252a9180e79da38a5f9a5af56a6a5d38cc1fbeb055faf4a9eed1c986fb702	1668649772000000	1669254572000000	1732326572000000	1826934572000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xfc637fffdceb79a61cff55fb71e9a3a6e586122920c2f7adecf43580ec02c69a36ff1c9a8638d70054498d2ba2d7b6eb00b52159fb5f8dbb5d6b53caff901b81	1	0	\\x000000010000000000800003b8e677ec459e545c46206736765007f8ce2155cd994e45dba4d42d7bfa2be27dfd4804dc9040f960daf20609e9c927a931ca79d13cb43f39ad1b7374870c35d86a3a9d260ce2c49e2d495626c9281d27f2d82dda5d863184679f14a85e11413f7a5eb03abe0a511de449688a333a8b0fb8ed1b61c0f58cc7cafb337962550ced010001	\\xf6d298fe8ff115260c9160a0582b8fbc641b4b426d16cb4539978b06ac24cf302e5fd1bbcd276defbb7f0f50491e6e81f4038fbe2c1e97053feef669cdb6d102	1647492272000000	1648097072000000	1711169072000000	1805777072000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	1	\\x2f2e2c5c1af4b9428d1b109dd145d4e2d6c0733e7e101110f8e9cb68f85ce83dff33a049986ebb4547bb1e19ae3d9f307edaa91421ea06a274a49e0f3f955fa4	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xc7964e8f34cb06bacfe46832d125dc669154b002f45a7471c35143ed72c260367768ee2880d39a9091504d6ce9dac430a76f86abf7e996f21243371f5da40e27	1647492304000000	1647493201000000	1647493201000000	0	98000000	\\x3b4639a5c3a20253b5ea4207239939ea0d782950f4652fc177e0de0e4c29646d	\\xbcb22d31f22935d05cf57078484900df0d446ce17bf05c64f59a72ca3f429a9e	\\x68742060ef19d27ba32ec023873faa9b18c4cb982df2b858dbc872562271a8afc140c5a5bc566d7ad87836692f42b537a362b48bd77d7677f905447eaf4d110c	\\x830acd24088e67ae054263fd3049c93e598b6f50a806d3f6adaded78d3a80f6d	\\x003a003a20006e756c6c007472756500645bd26e497f0000000000000000000000000000000000002f57303e9f550000805629f2fc7f00004000000000000000
\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	2	\\xda29eba3374d16f0f0e325cf71ae13c439479a4cb73a7f52d36be258fb8e85f038885fdc3411ab4645e31c91ca5183b8d9d45a897a93555d8f00d7a5b241e79f	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xc7964e8f34cb06bacfe46832d125dc669154b002f45a7471c35143ed72c260367768ee2880d39a9091504d6ce9dac430a76f86abf7e996f21243371f5da40e27	1648097139000000	1647493234000000	1647493234000000	0	0	\\x02edc46336a9e4d8636a582ff001d1de3886ef9ed905cde190cd5f282acb59bd	\\xbcb22d31f22935d05cf57078484900df0d446ce17bf05c64f59a72ca3f429a9e	\\x316f301d71a8e2adc224e6274b37bae4f000679f7df872b404933aaba99a4f10c0945de0f73b83609861b31a1485921bd5193a863e2104ba7c258945ac045e0a	\\x830acd24088e67ae054263fd3049c93e598b6f50a806d3f6adaded78d3a80f6d	\\xffffffffffffffff0000000000000000645bd26e497f0000000000000000000000000000000000002f57303e9f550000805629f2fc7f00004000000000000000
\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	3	\\xda29eba3374d16f0f0e325cf71ae13c439479a4cb73a7f52d36be258fb8e85f038885fdc3411ab4645e31c91ca5183b8d9d45a897a93555d8f00d7a5b241e79f	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xc7964e8f34cb06bacfe46832d125dc669154b002f45a7471c35143ed72c260367768ee2880d39a9091504d6ce9dac430a76f86abf7e996f21243371f5da40e27	1648097139000000	1647493234000000	1647493234000000	0	0	\\x077eb7b757a54de526f010bd8a3e5fe8d013095ce179457430b6c39cb695e9c4	\\xbcb22d31f22935d05cf57078484900df0d446ce17bf05c64f59a72ca3f429a9e	\\x14229e6aa8724c86550068c23edf99f9d5f52c610dcdbf25a0dc50e438f818d2014bf248bad61e3bc262adac541aea7f5b6581781b47b7d50e2be5548f0a3b08	\\x830acd24088e67ae054263fd3049c93e598b6f50a806d3f6adaded78d3a80f6d	\\xffffffffffffffff0000000000000000645bd26e497f0000000000000000000000000000000000002f57303e9f550000805629f2fc7f00004000000000000000
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_h_payto, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	477681973	2	1	0	1647492301000000	1647492304000000	1647493201000000	1647493201000000	\\xbcb22d31f22935d05cf57078484900df0d446ce17bf05c64f59a72ca3f429a9e	\\x2f2e2c5c1af4b9428d1b109dd145d4e2d6c0733e7e101110f8e9cb68f85ce83dff33a049986ebb4547bb1e19ae3d9f307edaa91421ea06a274a49e0f3f955fa4	\\x2e0dd107a69268d6bfc3a731e3beb779ad9a12d563a0eed92cff20959573363f9410d27d9ce3c0260495deee4ef3c03c61328998065216e2430107461127cb0b	\\x650217706ee42bd2c7b1983ac6aad6e9	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
2	477681973	13	0	1000000	1647492334000000	1648097139000000	1647493234000000	1647493234000000	\\xbcb22d31f22935d05cf57078484900df0d446ce17bf05c64f59a72ca3f429a9e	\\xda29eba3374d16f0f0e325cf71ae13c439479a4cb73a7f52d36be258fb8e85f038885fdc3411ab4645e31c91ca5183b8d9d45a897a93555d8f00d7a5b241e79f	\\xdbd0bd58e8161d9df3fa6ba1da4d0f248a0bfdb3273b3dfb0863a231112e27b5cc674cab3cdc617ec3dacf362ffddfa35b4d69892082a75f9c287beb83470c05	\\x650217706ee42bd2c7b1983ac6aad6e9	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
3	477681973	14	0	1000000	1647492334000000	1648097139000000	1647493234000000	1647493234000000	\\xbcb22d31f22935d05cf57078484900df0d446ce17bf05c64f59a72ca3f429a9e	\\xda29eba3374d16f0f0e325cf71ae13c439479a4cb73a7f52d36be258fb8e85f038885fdc3411ab4645e31c91ca5183b8d9d45a897a93555d8f00d7a5b241e79f	\\x2a2f55a8f66aaab2108469210f15a9e0c83e83fddd9b07298abc2d2c50fd7ea5878ab29f315dd3094612f22a0f057c4cf00224e3d9eb47073a91f9bc30e8b700	\\x650217706ee42bd2c7b1983ac6aad6e9	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	f	f	f	\N
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
1	contenttypes	0001_initial	2022-03-17 05:44:33.020509+01
2	auth	0001_initial	2022-03-17 05:44:33.179052+01
3	app	0001_initial	2022-03-17 05:44:33.304748+01
4	contenttypes	0002_remove_content_type_name	2022-03-17 05:44:33.317111+01
5	auth	0002_alter_permission_name_max_length	2022-03-17 05:44:33.32563+01
6	auth	0003_alter_user_email_max_length	2022-03-17 05:44:33.333046+01
7	auth	0004_alter_user_username_opts	2022-03-17 05:44:33.341435+01
8	auth	0005_alter_user_last_login_null	2022-03-17 05:44:33.349304+01
9	auth	0006_require_contenttypes_0002	2022-03-17 05:44:33.3526+01
10	auth	0007_alter_validators_add_error_messages	2022-03-17 05:44:33.359622+01
11	auth	0008_alter_user_username_max_length	2022-03-17 05:44:33.374531+01
12	auth	0009_alter_user_last_name_max_length	2022-03-17 05:44:33.382395+01
13	auth	0010_alter_group_name_max_length	2022-03-17 05:44:33.391777+01
14	auth	0011_update_proxy_permissions	2022-03-17 05:44:33.400002+01
15	auth	0012_alter_user_first_name_max_length	2022-03-17 05:44:33.407466+01
16	sessions	0001_initial	2022-03-17 05:44:33.439709+01
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
1	\\x2382f7f847b983625fecb1ac613e06d651294e8925f7aca329a0990c7a043272	\\x7ccb533a8ec1394abe5684129ed448c23132cf0d9f1a64d7d7af03831211ecb721695601870de80a348564314ffce138d68b87a9885d0b99574455e29bcf9002	1662006872000000	1669264472000000	1671683672000000
2	\\x830acd24088e67ae054263fd3049c93e598b6f50a806d3f6adaded78d3a80f6d	\\x7e7e027269f77579b843fb60ace069313a3ea1029cc657439d086d9d5a1d27e81c81916b41d280cf973480795266204f3b99b46448147aa9ff37c68d2801990d	1647492272000000	1654749872000000	1657169072000000
3	\\x4ab8d173606287992d347b8379d119c6ba5153c2ac46a2b93fe4ffdf78a4b919	\\xb85069a1f4a0c84c8c8473c783291ce11ad2a9d2a9196ddb76bc294e7147b57ed89a3a2f8dd24f92b258ba51c9949f24a530d7409d74a2f1d0b0a602f31e800e	1676521472000000	1683779072000000	1686198272000000
4	\\xf846ba4709f38216d582d1594301743ab82ee17150cca8f22cdd7be1c1b9560d	\\xc578c2bcffa8634bdc6c96bacd4c6335bef7f96c686a275952a5ed1e769f753b8f3b2733627a121b7263de0cb8a4f6bd04b9caebb4e3a475c455b1315d7e4005	1654749572000000	1662007172000000	1664426372000000
5	\\x1b15b35af5b985c3d197a5499450eece86c591b139acaf7b745d31ffcf66e8c2	\\x2a7402a8865f9bc9be25993bb3ddd05a2e3ccc1aecead2b1f67c897238859b58d8258f4abacdef4b64d4b2b32cececcad64da655783ff2451437186884a43a07	1669264172000000	1676521772000000	1678940972000000
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
1	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	0	1000000	3600000000	3600000000	31536000000000	5	\\xf5e925bc442b2df0f9a9230985707db88db7785cc2f6979936c6c0cbb888b89bc2e46f18e8a50f9f20d12e0f47b96991f3f153f72ec6cfc402fbac9958538a06
\.


--
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	171	\\x0fc9514fe20cecdb13e22a9634bded1bf5c4f21406cc3f86d4dad5e9cfff1b4a	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000011c54b1bcad9c3fc6826840c74564c0587f4fc896e597849b1a5e2cf003cafc7ade9e63cd7d5a5dc1d2f38b82db3e36111f501c3e2400e73d33edcfcd54b042371c3d9668d19432c8b9f5e9d23db9e88db886c4a9e4fe50532f885e7874cfd8f93f56174c149c68440bc3c465fdb646789d730d75a1e18ad92e5807f424a10e3	0	0
2	31	\\x3b4639a5c3a20253b5ea4207239939ea0d782950f4652fc177e0de0e4c29646d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000003db9fa8b955ce13ffeaf2607b6f125cd63358fb0a636940ca2c507ce0bb4c66c7bdd17c808a5cc47ecfce6a0670bba22e0559dee124b511f0498749a00b97b9873081c4a659f145d70a6a7a3e29780a2e8a0404908cdbf601bf17c3375d0c497670a2e546227ca89910fd61c438b6af3322a80cbac892fadbe702f18c6155af9	0	0
11	290	\\x307c8be655eb57b3f6169a515eeceee28e16f5ff96d2ba9f16f9956613b40c48	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006994d6b76a97e32d5b125cec19ccad02c8c37311f1552950856d03545dd4ed2a7c11ddef9c6ed693cb1a209490ee40193ce8aee397dee42b86581139e00c74e009d2c7898f75706501f525a0f72911c09178bcd034e325457dcb522f32aaf7d7b0bdca1673ce299b23f4dcc9b4d452d184d4ad131b713c8b7d703699dc0060e4	0	0
4	290	\\x10498c7b85f64b72ce0ef08f76f39868bfafb8e26728bda3c16ab20057906c0c	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000a021e57a746c0dc0c9b3dbb49fcff3256822f77f33c0f9f8ac53dec8776e03e0aab5b4aa713d75555cbc5451d55fa5e6a9771e9ee1b1c0be85b36a46b3261a6fcdab022a21dc73bdda5be9693ad42fe70651931908973ca7a920c1ceb6a5f6b979e2eb106788585848bc933da7002bb01846217e8cc0bddd2ea4869b3ae84370	0	0
5	290	\\xd373495b6753fbfdc4d3675c540721a6f60dbe45b5fb7fbba17468645af1442d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000043dfe880fe885cd6fe7b43d1ef0ecb846a6e41bbf74257620c4ce70cdec986b1c1769c3156b5f2a7532319fe29cf7951b92316d3e3c40c40500e47b9d5fcbc5ba967e61a8160a6d64e1f68beceff7678eda385a7e419b07e05c3d6d35d986b40feedced5838e5035dd75e9e26f09c49e75a464df95149a94074b7e5a083159b8	0	0
3	41	\\x251d52b7d1e2ef6985639ceac45efc5a27d8e3c56bf589f97e46ba926f17b7b7	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000afc4d412233f6d2430af8edc55c41c3a52ce1186d79dfd6011534b0033a3bd1f2dc3e23d481d53398e2f3c71c5fc3825b557569a48a86a799a2ccc48c012ecc5816bf8ea425a76525d642079868bcd9f4078910db008172d5f6cab18023dc1cf67fa1b275ac8b1cf80027a9a098bd8108262fa2bfc07c68504eb09c11713f90f	0	1000000
6	290	\\x56852017b41b59f323410ec34334d817f5d4d61a7a3cb4cf596c40c1ff3974e9	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000007057d52c43c059d85ca3c91361698e2700d57c5bf892c40dc8c2e7bf23b7498b570c5934dd778e6a4d67eed887f4a8befe3d569f32497fbbb3925f144b9c7b47f5129f106d45f86c3b982def06175436d8ffe2e47e4fb4db112d203d65a957eafb8536e00d9d8b7eb3d67b2d0f094ab282a989557e041567d096eae6d5fae36b	0	0
7	290	\\x9b8f8920a2fd7778c489161dce2c2858b508333c1e6a1502ab898abbafd59591	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x00000001000000006025bd94dcb876efb24bddacdccbb71ac736c3102742942e7ce15e064c4be34e1ed0aab714283b527710e1ca3e27f24f4d379fad93023d15534ae7409e70d969504f32db87b912dae1ff7f63d2094d274e660f901d4de894ec7131830e6ba59ec61ef88da84b64881ea76009cb037101f7c7868ac8d045885f3f06cd8eacc9db	0	0
13	57	\\x02edc46336a9e4d8636a582ff001d1de3886ef9ed905cde190cd5f282acb59bd	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000081490b3afcd50098cb7aafc44f30569c74a92988d2d0d96c83c2fdfb6db692d45e433ba6e17a30d673b37d38959cc4fadb75ded9daef926997a54cbbe8c0ffb3554647d50c5a057b5464040df432bb861e29823dd8f8f96ee13fe0b3c2ec4c7443c6b2ecc3ec14784fc50e40014d51a0941ed159c3cf4dadc3bf62a195db4df2	0	0
8	290	\\x9d17fe6af979de7701e01813d0909a3e8749396ab6b1e4b9e6fcc538a7fd9e51	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000017cbe2c7002fe28d556a54c6cb2cff13b5e927a24dbdb85b9e5809ffc6aab3c663d53e436228b6b205552ebf4a6aea23849a64e00329ce21ce0655b0073808ce6d67ad75e2e389581a31394ab12ef19893cf66d21042f7db79e285cf11b1426bf5e210bf877752dd373b8918c9303c215367031c6e0ea74a2c4f90c65064db5d	0	0
9	290	\\xa3515e395e199f7907403fb4e896b3ee242f9c157e3010b2143981ba35b35bdc	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000054175e1665fa6fe5c8e352a17f8e18fb1c8d9a14cf2e57eab145a19ae8c3b867e51090e7364c2b2690a2fad1d9117919216fcca4377c770ec0ae0ea409772cd4eac6bec7f0f2c6522262a3d9ff7277e600aed99d767707cd6bc459b261b479ff5202be56b1ead9afddfaa30e3c6fb07de20a4fbfba10760a4e2db1c92a49256f	0	0
14	57	\\x077eb7b757a54de526f010bd8a3e5fe8d013095ce179457430b6c39cb695e9c4	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b90118c743ebbfe9a5ff21abd0913ff05160b0749f0215072dcae9ab753dab045c943d92777bb5826bb588e39cc7354d5e79abed8380c3169974d98d9300b9c07dd08e686e0396c09bcdcdc9a01aa0606d1d31e778c9808a45dc6b2e26f971ba9e9bf67a6ed3dc8733b1689af8bdb3c7806a3973d8821ce678c3f21e5bd52576	0	0
10	290	\\x700f7bef165e075c4c8d189c6f53cb54aba1f874e28eaa915e4058dfb54fc44d	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000b6b40d0dca61f815999d264d73ca430f0981453579449287f04f975d8f418995bfa60ef18d67d597afbd24f48e04348dbdfe362d1b206b1ae0fe4be2677587bd907c4dfb8e986e80950010d822affabbac082fb18eb3117f33ac01642b37ff53a9639317e8ccb18902cf7c7e5979249fcdecae463603235be761d6f00b8bc911	0	0
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xc7964e8f34cb06bacfe46832d125dc669154b002f45a7471c35143ed72c260367768ee2880d39a9091504d6ce9dac430a76f86abf7e996f21243371f5da40e27	\\x650217706ee42bd2c7b1983ac6aad6e9	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.076-01B6R9PG58V16	\\x7b22616d6f756e74223a22544553544b55444f533a31222c2273756d6d617279223a22666f6f222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373439333230313030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373439333230313030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22525942345833534d534333424e4b5a3444305344323945574354384e394330325948443738574533413531595457503243305637455437453532304437364d474a35383454563739564232333139564647544e5a46544350593839343644525a42504a30573952222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037362d30314236523950473538563136222c2274696d657374616d70223a7b22745f73223a313634373439323330312c22745f6d73223a313634373439323330313030307d2c227061795f646561646c696e65223a7b22745f73223a313634373439353930312c22745f6d73223a313634373439353930313030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2246475246364a36484d3841514e474631324d4258434b365a575356564241523448504753543336574256514b584d5254564a3247227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22514a53325443464a353454583051374e45315734474a38305657364d38563731464652355253374e4b3953434d4654324b414630222c226e6f6e6365223a225345445752533136424d574e5258375751504445353357424a464b5a42524d39305844324a42433246394e3458393758314b5230227d	\\x2f2e2c5c1af4b9428d1b109dd145d4e2d6c0733e7e101110f8e9cb68f85ce83dff33a049986ebb4547bb1e19ae3d9f307edaa91421ea06a274a49e0f3f955fa4	1647492301000000	1647495901000000	1647493201000000	t	f	taler://fulfillment-success/thank+you		\\x5b526be1b7b73b8f9237bd17c4292f58
2	1	2022.076-03J2H0FPEAA40	\\x7b22616d6f756e74223a22544553544b55444f533a302e3032222c2273756d6d617279223a22626172222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f7468616e6b2b796f75222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634373439333233343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634373439333233343030307d2c2270726f6475637473223a5b5d2c22685f77697265223a22525942345833534d534333424e4b5a3444305344323945574354384e394330325948443738574533413531595457503243305637455437453532304437364d474a35383454563739564232333139564647544e5a46544350593839343644525a42504a30573952222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3037362d30334a32483046504541413430222c2274696d657374616d70223a7b22745f73223a313634373439323333342c22745f6d73223a313634373439323333343030307d2c227061795f646561646c696e65223a7b22745f73223a313634373439353933342c22745f6d73223a313634373439353933343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a2246475246364a36484d3841514e474631324d4258434b365a575356564241523448504753543336574256514b584d5254564a3247227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a22514a53325443464a353454583051374e45315734474a38305657364d38563731464652355253374e4b3953434d4654324b414630222c226e6f6e6365223a2253445834424b355857593359354e534d32583843584e434658313450385659534d594e413550564b353232474437594641354447227d	\\xda29eba3374d16f0f0e325cf71ae13c439479a4cb73a7f52d36be258fb8e85f038885fdc3411ab4645e31c91ca5183b8d9d45a897a93555d8f00d7a5b241e79f	1647492334000000	1647495934000000	1647493234000000	t	f	taler://fulfillment-success/thank+you		\\x93bbe00fa23e6317f5c6cfdd7f0535e0
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
1	1	1647492304000000	\\x3b4639a5c3a20253b5ea4207239939ea0d782950f4652fc177e0de0e4c29646d	http://localhost:8081/	1	0	0	2000000	0	1000000	0	1000000	1	\\x68742060ef19d27ba32ec023873faa9b18c4cb982df2b858dbc872562271a8afc140c5a5bc566d7ad87836692f42b537a362b48bd77d7677f905447eaf4d110c	1
2	2	1648097139000000	\\x02edc46336a9e4d8636a582ff001d1de3886ef9ed905cde190cd5f282acb59bd	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	1	\\x316f301d71a8e2adc224e6274b37bae4f000679f7df872b404933aaba99a4f10c0945de0f73b83609861b31a1485921bd5193a863e2104ba7c258945ac045e0a	1
3	2	1648097139000000	\\x077eb7b757a54de526f010bd8a3e5fe8d013095ce179457430b6c39cb695e9c4	http://localhost:8081/	0	1000000	0	1000000	0	1000000	0	1000000	1	\\x14229e6aa8724c86550068c23edf99f9d5f52c610dcdbf25a0dc50e438f818d2014bf248bad61e3bc262adac541aea7f5b6581781b47b7d50e2be5548f0a3b08	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	\\x830acd24088e67ae054263fd3049c93e598b6f50a806d3f6adaded78d3a80f6d	1647492272000000	1654749872000000	1657169072000000	\\x7e7e027269f77579b843fb60ace069313a3ea1029cc657439d086d9d5a1d27e81c81916b41d280cf973480795266204f3b99b46448147aa9ff37c68d2801990d
2	\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	\\x2382f7f847b983625fecb1ac613e06d651294e8925f7aca329a0990c7a043272	1662006872000000	1669264472000000	1671683672000000	\\x7ccb533a8ec1394abe5684129ed448c23132cf0d9f1a64d7d7af03831211ecb721695601870de80a348564314ffce138d68b87a9885d0b99574455e29bcf9002
3	\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	\\x4ab8d173606287992d347b8379d119c6ba5153c2ac46a2b93fe4ffdf78a4b919	1676521472000000	1683779072000000	1686198272000000	\\xb85069a1f4a0c84c8c8473c783291ce11ad2a9d2a9196ddb76bc294e7147b57ed89a3a2f8dd24f92b258ba51c9949f24a530d7409d74a2f1d0b0a602f31e800e
4	\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	\\xf846ba4709f38216d582d1594301743ab82ee17150cca8f22cdd7be1c1b9560d	1654749572000000	1662007172000000	1664426372000000	\\xc578c2bcffa8634bdc6c96bacd4c6335bef7f96c686a275952a5ed1e769f753b8f3b2733627a121b7263de0cb8a4f6bd04b9caebb4e3a475c455b1315d7e4005
5	\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	\\x1b15b35af5b985c3d197a5499450eece86c591b139acaf7b745d31ffcf66e8c2	1669264172000000	1676521772000000	1678940972000000	\\x2a7402a8865f9bc9be25993bb3ddd05a2e3ccc1aecead2b1f67c897238859b58d8258f4abacdef4b64d4b2b32cececcad64da655783ff2451437186884a43a07
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, wad_fee_val, wad_fee_frac, master_sig) FROM stdin;
1	\\x7c30f348d1a2157ac1e11517d64cdfe677b5ab048da19d0cdc5eef3ed31adc85	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xd4bda7e86a2b500df5398cd4868870ec82be79c137221c3c48af8fc8951c2ad33dd2dd0adb3e542ed767edf639c5d15c8720e4ea286ff8bb050c3d7165ec9609
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, auth_hash, auth_salt, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay) FROM stdin;
1	\\xbcb22d31f22935d05cf57078484900df0d446ce17bf05c64f59a72ca3f429a9e	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000
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
\\xf18b3d79513095b7c2610c2f010b5247f9b4d311fe703d3e0648ca6cf9dc2097	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1647492304000000	f	\N	\N	2	1	http://localhost:8081/
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
1	1	\\x41d62a903f196ce1862b49b2505807fd964def2c86acc9bdf9c37fd1fa3cbbb7bcfc011a0c306bbd9ed6309414eb4878d15974a01fcbf004fd6935398b19d101	\\x220e99bd9426779e9a067902763df6d3311baea16a3d0fd5a517307e4468fcf5	2	0	1647492299000000	2
\.


--
-- Data for Name: recoup_refresh_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.recoup_refresh_default (recoup_refresh_uuid, known_coin_id, coin_sig, coin_blind, amount_val, amount_frac, recoup_timestamp, rrc_serial) FROM stdin;
1	4	\\x46fd893fa89cf612beb26780ac2baa993a7df57b6a186360dc363e8729ade6ff90d77d68be2a169f15dacd8b3647ce37371ed84177d1d565a1f7315f24013005	\\x1e8ffd6f648dddb18103670900395bdfc8e26f664b5cdebe0042eac51c2a8306	0	10000000	1648097125000000	8
2	5	\\xa5aa217834e30d74364173840e82e0ac467c79cb8abe772839210b30b4ff24566c8569efeb4fd15dc03f86b0eeb5a3b522a14b29ea16d76591f909806ecfae07	\\xf399c5255bf1f15502e0d03143eaae352a2113ef5525220a397f2d9922de3339	0	10000000	1648097125000000	4
3	6	\\x0f08121ac7fe919a1e9a9bf772271ca3b3e878eac9e1aa4066c8127d123f9126f056a5860c2f1288d9d2676fc509d2ad01b9d534a3443c144a81c618f1f6c00d	\\x87ba98789f3f6d930858b6dc7990c125be91955007f03b2db24f4075f78fc11c	0	10000000	1648097125000000	3
4	7	\\x6f357ee211eed7ebbef1bd62189dd62ef86146f6887f205fe322407ed63c715f73b9e49955cf2368e3b1b2624fd2c56a66939fb248d94c2565b3e1db190cef0b	\\xfa5f43a99204a9a64bc23adaf81d5d11206591922b65836bfddec166d3a287dd	0	10000000	1648097125000000	9
5	8	\\xa0c6ab570f31de25e7c77ad2e16d0982a98b777621f0d2c066ebddf8b14ec53850195e86af88b66688d92c3185f4e49fd6b5330ffb9a58d9885dcdc10ac38a0d	\\x84f74dc93d1b4c88c0bf2d9438f75f94735531c1b4d83b1ac23ecc77a310daad	0	10000000	1648097125000000	2
6	9	\\x098ffff2c444720fb0de3fddba70256a9bae1326c53efc6bf4943607bbfc6a6c29fd965848fe3c54a1dd94b4af47c458327097b6df354d7dd3f75e45a4f9e707	\\x6c61555eedbccb16fa5ec3304456d1a30a89c609ff6be07c681358126b3496ee	0	10000000	1648097125000000	5
7	10	\\x2e1a1f53a94faf6ec34536d42010bd09124b2fba258e9b973d218aba657e057586b69dade2e0b79bee50090f7b11539e6d1fd6fa70a0b394e0ed055a9313a204	\\xe9e5a17cf5c611032b3efc7d1c13425547ce00389afbb919b20c9c09242edc71	0	10000000	1648097125000000	7
8	11	\\x593e3c0ee7b1ff64dd306a368b9ba8f8a3c23f55a1cfe966c4d0cea17be6091be369680438ef063d04b5fc00baceec9ee8a27a6d43da4ab06c875fd68295770b	\\xc3f34c9ab434d6b96d4a78fd434e05272ab4aedb5764ce3fb6725d1ec6e890ae	0	10000000	1648097125000000	6
\.


--
-- Data for Name: refresh_commitments_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_commitments_default (melt_serial_id, rc, old_coin_pub, h_age_commitment, old_coin_sig, amount_with_fee_val, amount_with_fee_frac, noreveal_index) FROM stdin;
1	\\x36606088b6ff48ce034174504027e76c2650e45c7cab73ee16d315a381e012a6585933d6c62aa5074fdaa91ac4366355457d7bfadbac81f0feef0a02bd0339e2	\\x251d52b7d1e2ef6985639ceac45efc5a27d8e3c56bf589f97e46ba926f17b7b7	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x8cdc07ad0ed9d4b5a8c88df183103b75b0fc044bd7e7272e344797820d1bcf906323dc5e8520fe60a464e68cabaef5063f2854ea961b225b9ed2b4d92396c707	5	0	2
2	\\x20712e21dc0f5b25bfb85c4034ba3c313642bcb64fc259046bfe0f2ea1b305adb7b9b3df47402838c7634c45f4d5b48a99231f4284c15d4bf923e4e0c9d55925	\\x251d52b7d1e2ef6985639ceac45efc5a27d8e3c56bf589f97e46ba926f17b7b7	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x6ceb94d6f397aa3b6a8ae7bc4011f44ee3c63f2dd9c4040d94d6a269c16c0f84d325d02b295c007d0664d07edf7bc10320ead10d73504fb07a03dfd10ff7730f	0	79000000	2
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\x75a5be673440181710277aa51bbbaa04d7ae61c594765a02ab8cb146f15d2a37025233fedaf2e73b6a1b1ab848a212f4c2d745163670eb97f29396c552e20d07	138	\\x000000010000010031818ebce31f6fde0315abd7c2ea99f91b305c6b015359913545456dc26341c028572d0fb19d74744c1307f54e544b3e5c416ea4c3c5c9e566cba81014f6a79e2fc6871823a040491deced2f06060c11b3c0af63902370e09cbcc068012b147dfba303fe22b83b079cfa528c78d079d46e72825673504a5ef62060a3d2ae523b	\\xeb07297bb5e406403de80edc48e2210d1ac0985585703d8f149e5fd24a30a626a6d17c5cf11fc8746b9283d9ad40b1e49fa297efe86df8c76ba125242bde92f2	\\x000000010000000136b4437205255796ba7256980fe3158156075904d156e8c456e1385bd75bd3c7b918003ec7613cdcd746a626527812cde59405264a0c1e35a4795619167408af5833c8e421dbbec99f5295d0b472a28fb9eb3f4c68f3eb256739c5dfeaf82c3d8146c68012c9044cd285aa1f2338a7b1a2c98709e1daf554367107d4555c5514	\\x0000000100010000
2	1	1	\\x91b09e4379ec85fbd3ff1faa0a37d1cc37965a2296fe8b31772c28e2d245ba320e13e114ae35746f8078cc9b46ad296b824cb5cc6401877bd1f509b9af86fa07	290	\\x00000001000001005b16971c89499515bc61a87cf7c73d627dc2c93628203ac58d610173ac13cdeef6d44b6c26a81d85fe3c528332cc3d6dbb46e06fe38cba6885f0f2aa8549d90a5f5fc253da75f2e1d5655ef8f60c952e916c412423c867dfe9d0a8e3c632fd4e1b452a233db079605efef03122cd77ea536b1deca3e3cd9df60b9ba721a96a3d	\\x970ea74193e8d1dcbd89bb9b69793f0689c28132cc97599f3caf5760a0e4850cb2876d0b9b92978450727fa481acc241f9abcdf7ae242970301280f1c8a854ba	\\x0000000100000001452be16081ec6fc742bfdbd08c2c145b5b030a717fa71759d0a46b6026bf52c0ee103e13cd574fb6568ad98419ca097529cb973075bde5344096565d067b97d809eb587ad56ea36b988b16e3462b05c464369470c57ca346edbf3e0f98af29b323bcb92abbe3cd1242480f9f2491c943bfbb615e1996fc4f52c3c9d86edea2d7	\\x0000000100010000
3	1	2	\\x18fca6a5db0abe1999653b3f5ee922df1423d1973420cb2fa7618ae1a9d6db20f465cc1b9ed8b97acb6c529d21ee5b805ae65389901700a94ec9dfcfdd2f4002	290	\\x000000010000010007105eadaf0f0e7b9aa980cee5fb43d1b5181015ae83ccb18e27dda3e415110feacb3ed8a64d877cb09de54e4ea174e68021761aeac2839d7e2028edd158557dca34e5c8577f18d087ecffe815485c6e20134ef379707c6b48bf68875725dc8261630e3092d30b8010fa9fadc95bc865d72c731592023f8ec6476216f769ee9d	\\x75da15d045c333bea52d9789a5ae8aff186f7ffc789c37bcedfc40be069bf0d31cb9fdd036cd397940100431dbab8af9b379e347205ba98b5b2271e74aa16cc6	\\x0000000100000001403f3410c0b8b378f91ee47ebf17c0dbb4517e46e7d74c9cafed53a1d9650bfa0ad266a0c4221482830354c9cc2b7597dcc8cc4a27a264e857d4a3fcd00115ddf07841ef114d37aab3709d1fca9885db87a016b88493b3297a7558c303dfeb80c7b795202fc1bb66e5101439cafb26fbcfc3f4beb922c75a8a7a9d16296a7547	\\x0000000100010000
4	1	3	\\xeb277181053d821a51e70128d6a467c5dafbe0f771c0d6e1e1076a18a32b1f584a488b86ce621807a494e8a950b8f3c066777bc5b936653429b143ca2deceb0d	290	\\x0000000100000100b6d4c2baacaec2c1ff7f21e16ab9c117bf7f7100b0e665f99bcd4f640e25cb8563112923e1b494a4e159236a2f802170adab3414f8f0977b98cf55d334dcacb3489215ca9f95072a1de787bc2ac9a066131df4d605d9c326c97b1798bfe8e79c8f5658f3806c01f8b361791bd40140798bc13d9d12f8dcde84a9cbf968708b54	\\xe58a75338d9ba73f247d5789a0fcfbde11a6b437de6ba8082bfcda6dfa73ce0605eca71dda6cba94d6c932388032afd2aba4c7d10ea44ddc20abf56d07aac6c4	\\x00000001000000019cdfd8f9569432d23e7d61f63e576c280d456dc924cc24f81e6be3c12be0789388f7a055b334a5a5b67d6224702fc82c654884512923636c48562c5216d649a2ba9187cfdd7aa92d15f39482eeb1aa57d9e4ed0f1d69d635ffbc14a5fc0c8e9781fee474961bcd308204e56c0dd6593028fe6c587cd32822e8c0ee4b954d5be0	\\x0000000100010000
5	1	4	\\xa067c1c99c8c6d9389de3720994914f83eadce1e903fbc78e6ca1c4cbf460402455ef56ec20ca8c971ebdb781fa810bc7241ffee04692ddaed978184e63d4d0e	290	\\x0000000100000100a6a14d5180d64217c0d6a2c2ce27fee6f6aab319a095557832803a56dec577c348c011eebd2a6c69118a5b5e9adbc135ec2e9323096a133977769f53229ac8464f1d856fd8e29df4feb5d26b356aa9d68075ae2471e002db9717bdc8f2c94302d28bc3ab5cf0cef77c8baaf8a09a2fc98a5e313f7ab8e1006a9172d8c384a554	\\x546b15d7efbd8266747a8768194e2d97b98705043e7357098e694d09c1efe796bffba2d2805237af5c3debd25ecf91feda5db5a2bd358627c16292884d621a4f	\\x00000001000000010568c46dcddc9516a3ee57fa11082335247d57033910f168ef163c9a63be645a0ebf926d00228b6c1a424d7a242fd7b680aaa77351787ff70b996692c16237c7478be4495ec300c35bccad67585a59b96ea6c96abec34135752c4fe21558db5d136fa3a729b3f529b41c3deff326208adb0560d168b5f2879d11e4f0fb5f60e0	\\x0000000100010000
6	1	5	\\xc67b951e6fae65085f0445d359d4bf6e3294c02938f4c3acf36bb7f03f80573fa0ed0428a33158fbe8347627b9d9e97caad5b6d64893d7e123bdb8a352d32406	290	\\x00000001000001001cf0382c5cd2acc5e77fb582b2fbf28d3d7794557a91bd59ba585f7d9c49c5acb9f71f9e3156fbdbc7c5666677c498b9a11d366534a51f87289bd1c3c74525715eb78d6e8e7d44f609cba93713df25efade01d9d813bfc13079558ddaefc1476fc85e5896fd140d42b80d747e1bac8b5b7eff519c73e482e06f5c6de5f9b5729	\\xd370eb9942bce2dbf102e61a671eb1078090269b730816a1cadb0172c54581a65cb0c42eac73452f3c328963bc2f5aa2f00dadba29a24c3d04520e3e16e96636	\\x00000001000000015e573505fe033286b0eba6ca34380aad99d406ea7d0aebec482d7cbaa143d6a509bb6a6c177eefa077a232222185be558271c4085c4aee4821a2691db31207a36006c7cf3b2e8ca3250304a38d80dd6738cd08f8988e01039ef095f352420b3da068db77c9fc046539f3d95d0bf846ee6dfe10dd1ab7102eb9cd74369fee5cfb	\\x0000000100010000
7	1	6	\\x15a5dabcd495b4af927a7f2aee19f59a406dcdf1cae1a5ab0b09059e6b027286e9460ba509ae55e2f06661a37c672a001559dc87433a2c2c35276a2b39cc3a02	290	\\x000000010000010069ad5b033b62c1b906dd8ae010c360bb0f93930396fe9348c2f4c7c2e937a46220ad8c2444199c792db2e2cd99be1a09b35e4c75f51a6af78f9ca752dcb05488d00e7f32f9bf1e66aa172416a5c6418ac39ee3f473b0ee2551945c216d90c04df823832a59483852e3cc3b33e4fd2532745ca7da1d354fbdeb7bf7b0b08e897e	\\xa3bb173b8cb52b6717475ed1df87df70c5b68c657c737bdb7ab65668dbf26cf4cea1016cd1aa548b32b0428b4447359867f90fac1250773055e87b824c7ee158	\\x0000000100000001c28906785b5b7e04eb56fa9b9b0d993e26fc4fbb9ab167303dadc7a23eb5011bbd4c9d5e18294458015ef5523ccd557c3c4c4bf4018900360683b192128bae650ca65473549f568a1ac33e71fd103d0968062f587ce3515f07e951e8bdf14b6a991d338927219566b106c3618fcb63b17fc8ad5c037b9ae113c08d114185f99c	\\x0000000100010000
8	1	7	\\xf7dd257a4d6d1644a07cb01b77a07d3d2329a7103ca66fa16aca124a5b8f01398aabcc53d5c8fc958bf252f14c85c086b4734e29f55a47a1cc162c18e7be6d0c	290	\\x0000000100000100a6101ac4cd9373238c613c988a6609284f963f11d67ed64c610f43d1c3f8c9aff4f079f7def4024648ed5257ba820890728d24f0aeab0cf2a8417f4548d0c271ba5e691cc372d56454a55d57693797bc2bc4dfd43540f1c63338c1aa13923c692b31b33552a95702bca51777f3ed0d311be944190b94d4d70863d7d834138ccb	\\x7b3073093ad52a3614027b72b38f03703d638b8df788b38b47a985cb1dcb9441645ffcfa80ad840bf193c2eb33914509d2ffd0968da4dcd7422d60dc416a5c54	\\x00000001000000019001283e1ef9496c7eaf2bb477e814b1c7189a872abe093f3515ff94114f3717eda9e41a394cdc2ca388603f55380b53b3cd8c1831e3c1667555dd3d00c11f1f944e208c9192ceb0047e66f349dc5f03c194b49b8e6363eae17d00b8cea04992de8db018c93178b6c37c0d3480e307be01ebab232720392760ffa177f64c31c6	\\x0000000100010000
9	1	8	\\x8ad2d34afab38fda5f81f3fe8800f7754c5a69d4f9b463fbd6a794cbe04a07b17c44cccfad535e73ae03c297900ddbc997daf17ff4df1b74fe1cb72f22d6f40c	290	\\x000000010000010079e08903003c04fba2bdc2b001f409465520dd5a8d7a40cb7c8019fd40b904e5b0bd03ac5f5837864845d33359b7d097c752d8b78b20bd95ea1642abeba96ed5624d835446024c7c4a9a20ad0ea6d8e3a10d6c9dbdcc8cb3d4fc5dd419183fa547b98885463e5011c4dae4990c693753abf66f077295feb363f098b08f26e6f6	\\x692c5194d223a8a2efda7717e5ed8437a7cd38949969344bec24987fb5c9be0a66db946a0b685d614663426ade4ed6fbbcddbcb32b7d7366dc2c1920bb8970b4	\\x0000000100000001813398dc68499d0960a57043abe41ed48e523f28be2c62c00349ab89328c9bb9a8224be4929a79c7fd56a798077fadb58612dbdfeb562925e6970ebaa6366d6ee8352f35ee87804d4f96763eb8dc69982118a7a40d65ee798b44091cb00143dcd3356daf0db0dc940d26a8c2741aa431be5e51b63a9b05486a0dc482aeab1b06	\\x0000000100010000
10	1	9	\\x5198629814f69d319580d6d82f3f29856bacb929a4dbcb45dde2f087b19746f04b0e43af80efab0b15c0f9a37e6e2105967fa420fa03a013c7fa5af4714dfa0a	57	\\x00000001000001005b64bf116531483e2cd59d9976aea2c9e048f0477c1f0ffe3d7ddef4e6ac19d72dcaa6e0366d8769dcf06aa695d73b1eb11bac395dde74040454a019c6a8ed766dc0349263975923fe6859c8fad3c52c6eba526dee06a11fe3791f014f818cff733966a1415b42681d4178645ebec95a785f7e5c3bbeb221c5aebc91ec4dca12	\\x3504e2159dbdf7704adf819a6b4eac01fe40e954ce1e4f6f1c7a8e3be655e2348af2f5f94c6478ed6d45dd2e6612a77c50421dcbbb51c269cb1a176976d87503	\\x0000000100000001a4a390ff6fe5e7cb63032ebf905efd3770b5103956856482ee4266e9170966981aa7a90735f36159af4af60fb3910d8ec5f319ef9d996bbbb9aec4b130e8a9d7c369bc3fa27687fe3d6cc02652b2be449c96d7512e91df8f7216e8e1798436a2df9e02f13f04f907608285aa7612048ed45ac066cfc3feae67604067ffb8e9	\\x0000000100010000
11	1	10	\\xe041446c110df2a70fe0ced6e37ee71a7d2c2d02f26fe71712822b9c554f4b4e0aaac5c0ad0a1e66681ecc573a192615695fce11bd0e513fa0e4b66a9647d60f	57	\\x000000010000010085cb5b74113b17b8de4e67f1716eef2ee14342950ee6e7d10848b4c07c875722575b14cdc3d8bc26db15c2ac141534ad279874d0caa04bd646c9cec1ee58caef1c0dd37e1ac82bde00d857b97da04411a2dbf74b404b03100d52122bc5387bc49f50a5237689bc6b69da3e007d6bf3564ec159ffc142d0826f8afe45c75d0545	\\xddd3f433c70a5b131fd0626c0464a65fe8cb1eeb228ebf34af246ced7a73db88accf3c4c17d3ea58b387bcf9e17b540ed2c44cf512f80c19638fbd222fcc5aab	\\x00000001000000013c2d8baeecfd67146c730fa682a7b42abe0616c9edaaadab26f566a07f729bffb4e4ce1faba86b99f462a382e50c4ef0d517b1c6795ba66c47414c2a3056d56553da16f3f446b5dbd2331c455eb7907bfe8d52776897c026db680b50c839dbbf9fd9b0deed88971f578121cafb72685fc71aca96b0c1f00a2eab990cb5b54904	\\x0000000100010000
12	1	11	\\x3ea55625b410890632f3fd2aede48b620a0473cb2a4511fde5679722a45fc83e5a3ec7c238076f8f928e86cdd3c4a55bfb58dabe9a293a9569543da14ce97202	57	\\x000000010000010089706400176d537b347eedcda89cff099e5fbb1765c50882c45825a6f345aad334225bd25daa88855736608f99ab3b2bdb7a643b424429b7c58b6f1c59e727d3a1787fe85954164df78aa3e6c0d854370407d41ac47497d77723b4d9cab637d27e39c76e32188bac138eacfecbcb197261fc1caa7ddf6677ea7157afe04c0b87	\\xad5fb943520cdb7557f9ed8cdfe29fcdd21e230644617f2c6c345ef3a1b848bb684edb400a40627e2d2581e3383414d89f0a8583a5c2db0cddef4f07add87401	\\x0000000100000001ac55f49ffcf4c3527fa22e0bb9e8e41feca83336f18e96a1bffc661f5299594c36715aaaa49cb39618faeab326400bfa85e792a0684ceefeb8999c78839b8e57ff7c4abecea652a438d0ce39da8f7d114d168d5968f3232cfc459da08365e974ce054bdf98152050b429fc4e385b4fe1b1d884547599ee2d64e35785ffd2cae7	\\x0000000100010000
13	2	0	\\x0fdebde96e4457b6c517cb6fc72edb06330abaad747bb27add4f7ac397646defa000fa04bf8f93ce9cfdee9041187d584406959da636984c9af413fea3dcbd0a	57	\\x0000000100000100aa946a0f54cd5fe08b5832faec07f591dbbb90caec1a5a10db83a8139746fca0bef1ce66019fc0f2868997fbca9fdeab7ded1e724e106a1671a5ec2a3fbe229cf7c716e842428d3447b73409e0689060cddec89f1284c29f1ceaa70cc42c0780b07cd580facb76f6f037ec1b33063fd652ffc1a7de34dfe6d213edeb58f7fd7d	\\x939fdbb493b5ec2fe20a7faae84ceb8235f94b18d2615d7e34e2b750d037bce4884c6133837e51cb03245764e3fb79c1a1476f9e0e1b393e64ae30671eeac5cd	\\x0000000100000001623f4330299d93e54301d1fdb6460e49a9ecf860ae97fbe55b548cf5e607991aaf266b523d2d406a9ddd0886188aa6bb1ead916c2c08f202c24091397abc45060f04f3b362e81ab55dd81799442dd2aee7cd964209f70211d7ae173911809dc6d3a9ea31ac52e51ca60e6b84549f1846d9e947367cac6728021ae3ba0e6e2742	\\x0000000100010000
14	2	1	\\xc832f8463cc03933d122eb04e55f5b2292e824cf8b59cd4ea9c5a87ec8602c858b18118f6cb38cd0c3934aed7a71a405cb06798bf5f5fecf773a21cdbb5a1802	57	\\x000000010000010050e64793eff0475e03bf57611656c34b5d0257e72b2fa1353238bb19defc81177d38e655e6e474a55f3bee365cb3cdea152db972e2c963aba06c60fcb373dabedccb91e12697e3435852d05033ee0f21e58cf23ccd0ac3909efde7c62915b81f23c4129b6a68cea900e5030fc4bb8c95e9ceeb40080734a40c4cad202c471e7c	\\x3b6419c2c7186171b116345398b0ec5ac0ccb5a007ae2b11dea9bfd777ea93afbbcc390f0ffba203587d72d840af13915ed57d0a3c22a4ff744d1f1a9245cf41	\\x000000010000000178a3df58faf66943397cbb67eef447351c874c15ad039769593c20c5fe4a597a9de422dd21119af2599d085abe7c550f29d98a385466f53bb21ef791352d56e88fb28aeb44b70798c237d6cfd97f26b569662c296643f38c14bb7d99d5fea04f479354b1d02e9985ccfab50070b5977d6c14b83fab9344ed9455013c3da2359a	\\x0000000100010000
15	2	2	\\x5a997a40dc6a8b7336248f21d2bb519285446d1d91f5edc59092efb3eb819909da7b4b897a0741b30848c246537c89c89ed60e23d5fe57383d6fbb8a7aa3dd09	57	\\x0000000100000100abeec8b485dbde1c4598fd8b1a0ecc0488dd4cabc9bc944b5a74480714d36516ec18117b2dcb144f90a324b1fde534355cfda15e407747f06ef180bbd5a61bb366285330053662585b25825fdaad33fda236e6f76cfc596aab7ed475042acb6874edd9b6073c2ee5e4c198e643ed15d20b21040635becb8ac92e088c5628481f	\\x12ff1c926542800c3e21cce57aec48d817e916f76c9d6cba85635bceb1aed3a05f84e9fc2ce4b189a886c1b8cd2d3b0021956cc6e78fc2da4be26f35258ee2b8	\\x000000010000000181b4687622be74c0b51455ee701aecc3c9b3c3e2c79a7722d892e24e5ec7bca25e69121b1551474643917f58184732ad7c8841020da2011bb6ebd6a511357be48cec2448bb6ec9bee13389b5bdacb6631e4bbca0bafa116b9f6156cc5d4377446e3b6b7f43c85267daa17341c0212fdeac216f77173323db8da6d1ff332172d8	\\x0000000100010000
16	2	3	\\x750043db65231cfb9fe4d9d69d872a4f7a54c6674e9caeaaee41177d3d1e92b54ac17ed57e639cc24944d0fdde242dedca49e19f0723704f79f9294833aa240f	57	\\x0000000100000100ae372701df35fb5fdef5b2ad2008867ac14627145ba6361e1456b5aa2f03cb851e04d77a5a8cb644c35a01580cb2416098bb0137358fe500b35b080b349ddda043f24b33d46a536377acfddbeb047bfcb54e3d834d9c6d44321df76719185ef74149216e55d397c6d451fd3d49a7669fdc3cfe7813d52cf4448a325a41b5f5d6	\\x4a8bf9c3c57d028bb807c19f5f942b034f3805e21f8d7b6c314c94b0fc7819107d8c49f508f7e29037f8e61a5ebe218ab87ae5fd84f30b971b204fffe1c00a3a	\\x000000010000000165800807a70693670505b915cc434985e1c334cea86917870d69e8ae1a4b08641138d5c516d0a3b01a9aaafd3afaa033c01e878aae7ee74f4ccb9ff89ae2ad51e8b622556da3f3f3b68713a3cb2c51933d654dce3945916e276d96382757a8ca4b0e3303a8babe1123e9e3706161c9f1b64963d90cccead75762db9459242090	\\x0000000100010000
17	2	4	\\x6f5305e40dde32637bae2a5f529aaefdd1c08784c6fc19347783101f25132e7435afe936dbe22536d5eeaf7c2170c499829f10f4d9cf5220a29781cab33da202	57	\\x00000001000001004897f2869faf06b46f7712f3051264f880efa57fdb0cccd0dad2da15e0223ba154f7eb3c3308903e76e8718d9c326365640eea607e68aafee5de0f420667595c4c0fe9718368e8e29054c2b3051ac0d94953547d0cb9afa81b917c46c70c46d33c460c9607d2728af35754726fafda62b21e8675deaadec9648a5437f3a76b80	\\xc24a0da63590c9614cf7ccd7345dc4b2ee6306bb6a18e424261c4522df828f1901ef4061233a2269ea877e2af646295c061042bd4cb63c28b637ce4c1238ed11	\\x00000001000000016c2c9d8a520909c2032fdf0cb053782d9fee83b16b7e2d16a08ca4caf46a2587eb3d0a352c0a87e7a7ba1be3f6fad548003e52132e9a59f9edd56bc64a711888a863cb4464a6cc0410b8dbe531d3681eea6225d73b36e6a30845c8dd43870f6f13dd10cb925cf515ef7fc37973ae3bf581ecdd64a39beac01796a71e6ccf1b30	\\x0000000100010000
18	2	5	\\x3c8bcbba22e54b4bb7289f6750cf0667f1b349731ffffe41c4d08c5eebdbd125426e55c16ac971f90a1317cce624cd01979890f6661419958f50bd2852701604	57	\\x0000000100000100a2f5ce6fad0705c8b9f125011e6d88f85d0adda6cfcb24d28a3221f2aefc99ac2a919c02a2ddb8341ed7276d90dea556fa1816daf11336b6ef2fb3185d1123e4ec8a0f0a4dd800eed9dc344d6afeed149c3430315f7ceeb9538c3f3d7fce37b03494af4abe153b060224c0a79e5492c51802f0d7f062fee97d3fd9fd06f85e4f	\\xf06f73869f5f2bcba9df621302588e490badcd18c83beadb48ad91a9d43d8294068626e6c020325fc75fa7bbe77ee90b3c3c2b9b0dd36bd454eac4d1ecd1454a	\\x0000000100000001756e6e462e05f57f7f3f4f3a2d42ca7fe707eee41caf5ad952e09155a36b79a583fb43658f9635a236e21c1ab7637b455e4e272d21473603e5a49a7af96e27309565eacae96fb00f2e7c29d062bb27697a5add9689943cac5746083543798d357cf01d6c1598fc74c8cdff1cd20afca4ce48903565e5d929fb51a607143afc3a	\\x0000000100010000
19	2	6	\\x2c4daa0b7987e0802f3306c280c9fff4e8299a89a0781e0bbc2d4df3d2bbb37423c48855fb46a52e1e1799a2fe532491543efec546f8a0416c862f3a0ef7ef0c	57	\\x00000001000001009b12c54ae54098a898b6c4082753d87ebb43b911403e45b48099d67b32d759b963553858aa23f5cc7c1e15b1ddc19ecfc2575e5ad31c3b9e3a0c0f90c9b5361f54e36fc3d4482f1fe980a68fa4b2c2133a0a2cf76013a2232a37fa10c7c1dd91893bd289e76cf3063baa10de76b02d6b43739bde04795c4fbc3f881dd78d149b	\\x8434983183bae307a5e2e30c6e47ec750c49cea770b748ee714aa9491d1067b11c378d6bace849620f9317b648dfac0fb5d2958c689ba4955acd8834efb515d7	\\x0000000100000001311edd71a5136d6d4d4879f99156a368b66001bbb3ca5c1b132e8fdc43a588cb148fc26c36fb0df13b2d1aacc8bcc001ffa0211fdd63b4d6705a6f6dd27bf3fdd65ab550e721276efa88dc565b1c09823112da05ada9bc6c9ac2b62f90022e744a3110a308ddc017d18425f1716201b9466fa169ad1c241d4378c585b8ec5073	\\x0000000100010000
20	2	7	\\x1fe96558f5767df6008394e834557d26e979533f280cee9d03e380ae26f6519f69839eedae3647fef0baa831ba5fe969798e510240c15fd3755d3c8690237004	57	\\x00000001000001000483f14624f52c5962b53cc80e42895bddf71d7469552ab4eb555212a98b6cea7e2bae8a3601e002fc8f8988e52c48944898d800e144f6393d9d358df2d236471bedbb8c9971dde8844dddce8c79a785f31557ce376234d3847928d6ee5ccf2d5087418ebd077178adabbefc58112a30b6702cd00a13a580380b690ecc1b184a	\\x283f1b1970d0fa5e520e9c0cee8ead549f1a0200e91774a957e23427ecd1c4dd7705bdcd3acb838c0797aa4354d4bd91e15e970413c23e71e2e893a5278599b3	\\x00000001000000011c6e38c47b52552b6e83a0bd61474bc502f495b175a61f51c6ffa6c6ea11655cd0eacd6ee7906efc80594282ebc21ba251b8b5f5619732707471d85a6090bd3326d9336263e92a934b09a875e0551318a5c784d3377ca6dc2ae3c7981464e9e9f9382e03b3410658cc430d0bf8b3067b59de946669346c5226ccbd3aec049bff	\\x0000000100010000
21	2	8	\\x8668b74442ec22375f47e414bd93ea1495963390236b5615b70da18135108696b99f22b02ed61d85aebd4fd2c9529c1d33b4c2e468d0d9c8ec97c1615cc2cc0e	57	\\x00000001000001000f9f1b881c57a8785dd148896221db38e11e11289b48461d273a207a4f3c22dbe1a1e250b4799ec6e2a9a03dd93b2849ef6b895ea4caadfbcc8428cae3820881dec9c15fe78e85a91416f9877acc7ed0c1da95cc145d2a4103e5ee2f09883b2ee5f3f10678938f9a2b07017dfae1e3cfee40f474fe81e373dd6eac278b32670a	\\x24b7bce5d51f8750cbf40bf26c04bff6b01c796f848d7137a42125bbdced945811725b9eae6cdbf661f3df4e012de9a87e014b9f91e29c6481899e5c66aea2ad	\\x00000001000000014e5a7b56fa676ccd469358872cc4752990dbfaf421ba1aa23fcf0a380e7ad211ab0a81fcb077fd4fb6f23db62e23cda72c123b0616b550db945c4162cfa430e2fd72ccab58feb1d22bbcb715320eeaabf05f6cf9187b799f5b8800b137cf0b471a616cd84cea42e929dd2db46760ac039e793345b7acd820104136dc6b5e0d50	\\x0000000100010000
22	2	9	\\x8e0f44754a53cffa0400c122c374551c5a063fe122392e2bf3e7ff86c1818b0273da26bf2b0ed64c066854f47df6a2a251e1f632c858d2570a879bf3548c220e	57	\\x000000010000010086b80fb528a1773d7b9b64758216522affc8ccb2696ab7d93b76499ac494727f959b227893181ffd94ea9a6d5e2488b8644fde50f7bf9ffb4d40b5d842b47ecbe7c66e8ce6ca4b953537f923f5d84b7bad9637d0ae54ca023cfaccd6e06edb6ce19571eb5df31cfee3cdf73dcb9a92c58acff9d0adb517c92f1d0a1b5e00ff42	\\xa58d66398b2d9df921ee0a2d6fdabaa1987685250342b9641fea78c60a772c0e09594f464afc4fef42c68fe04680300e661161526fc3f2608c3c60028a38693e	\\x00000001000000013e3b1444ee6b42947ae2fd68803ee9ca1190c94324fe1926f9493fb90a0e5c54c2b7899832d71aa2b9110cf1798c800dc475ea3f41c56b3433455b27965a3e345941d37da37ba5d78e742b7c9c54ec0db5cc582f2a47941f1faf5c8560c52513c3cf062fcaf10d058f1053908090f0b8c03f9a0ad65d0016401e31eefd685dad	\\x0000000100010000
23	2	10	\\xd35e346892567991409c5509bb30e9b757439b4b97ab150d3aa7b45510aa283bba52b6b75deb8e1db9e1de39c9c0a353c27ce4c01ae65f3f04c79593dad18904	57	\\x00000001000001003de3d1f20be2b0671070b97a50e512f9f65e0781f7d471199b63c5e0e8d19262ecee392b8e0f833b40055bdaf6fa2bae71286ceaa1423ab238741598fe18bcce6eff57abaefa006f35a8dd10939147686eecc7f05c0795fc97947274d413038cb963562ddbdbbb84be3fe693c3d3394e0513440999bb3db84c969e805d5c7f60	\\x932a7e6e13ef05f288b29f88ce129e76a9e1f96273195f83b21d8d4c53739aff1180f708bc02f0c282dc767278dde92eadc479014e5196acc63a50fffbf15267	\\x000000010000000122f79a2755467e70b27d21be7a0ee9bff8ff93740fd62c57b6f0cef0d09af3a02a2d0c2eb5d404296f5c8a467c24f7ca7c6437fd064677683e7e3d87c2065c5cb1c0addc0d456362bd72ed806d8031695d067a1d8c25af7d9531a9c40985b14e910933263cf6e06c034740b899d8a56dd8af14f9f42037d62031a3b4c1e08960	\\x0000000100010000
24	2	11	\\x607f42104c1669bb3a07289d7f5bfde17ef67705524ffad21f35fdad5b1b0885d4be4130c98fe0dcc53b3c970132ec04e1f39a96e5adefbbe945461d8a6ad305	57	\\x00000001000001004fe17461950d4ff167b1e9037d1d636bd953b5341ff35aec6f9c14298d710f6f9a05ea3cd02b604f68976ec4a1c37a6a4368cfc00e43c8ee1705046a35b5689e40b9bc5fd3bf692e1ec8989cc2f1711ef6a210a3fe34202e03388147d9b06552862133d552bde53b5ad3b23893ca6003be8f80db4b95de5c2627ec31cda0ed7f	\\x76726540bd16529dd91299beafffc5f85694bb18b0e77bc0bcc7bb619e26c7806c79cfc82149f61f3a554198f5917a31651ce12d1b009835aed47af1e6280dff	\\x0000000100000001ba8dfe14748f796036d38164f16af9cf733a16b0458d630de7068bbfe08b2b249be8aebd5f99ac4fc38e63f9da18a75bedf1d3ca30bee58b0d053ad802c176765b4b6dcfbfad9f0401716572360d63a5cbce58d0bc7aa8f5a84d5b99bd957baeff8aac35b9a61fe0ca4693cf821093a6732ab43f9e4cab202cd06012fcba2bf7	\\x0000000100010000
25	2	12	\\x490e39eb37b57c5a19ccf908744c668bbdb86ee25aca6b284411f54a91ad512b6ac06290f98edd269208d36ae694b441bde9a3cd82b3e98ed2e2d9b3ec50840b	57	\\x00000001000001007a43cb19d1bf1f521d9932b42b79c456cb9c1c556a0fd40f3daac8bb4cad16687d2dd45fac54e107694175b725f1e25424b64c7aa19082ed15039e32b71274defb5ba42f370d50eeba74b1b4671fc435bc981c2b745e7ea3c814b11bd7c7f50f0ab53419e576ae96d8eaea44cdea5fac3197b3de43db8ab097092c5a6a98f034	\\x19db49e342d1b81a19337a4b93158dbfcda51ba4994bebfd2227f93a0381e8314ea170ba1ce9725734c1a55a233189aa32897586101a46f3fd35572627569aff	\\x0000000100000001227c644e4f967be236cd0b3bc45835998b5a1bdb11272b51be76737267e5e7a28450150538b1cc93205417beb04ee6d7530331995c0a881682465ee8fca879a57d8bbe6239715a38665bc93e5c68486ed6b5a30b1d969f79ac652261b7d128240d396aadd95475b44d0d6262d2ea72d7cc6c372862e12edcfe2a87c52beadeb4	\\x0000000100010000
26	2	13	\\x28653573d35db9fba98ee4a935425acbbc885dfa29ebd19501880f04584561313f1d6275b615619847002c796f8e361877ee3c35bc6806e72f250d1e47be7c0a	57	\\x00000001000001001a6c2dab6debcdbde5c7a929cb366e78a428cb149f3f88b228d558ad9965e6c8c47fbf0a528212f773f68ea11d705b40aa0c3c101def7da32ea2b7427e3944a63da4f869fcb92017f1f601d48e655747946d7a232b72d22f098a376a71ef022a706fb3d1f485795da0b93a0c4e64321907fbef6eb2c1c1cbdafde60f292808ed	\\x3d675ef8d3b84fada94555b57e71b61cf940779cd379e2ace0d33ccb698b633c65b5ae0eea85166eab8ba5d24192cb5a6c0986fdb8929820050f6a595b342b39	\\x00000001000000012bce9f2a9f1343c406b31f1d9acbf832ed90efe3a96bf371265d9a912c124260c3404a4acd2828b9aab31843ab88b62a31d21691b5665007084c66378b48fed18326cc3158dca7c6978de983f8ad48b363873052d86632894ad9511e022974c2411e5b26d635b3173a7aaf68e52c205c97652cd7f08945abf892320fb72af531	\\x0000000100010000
27	2	14	\\x206342fbbb82a0335ff4296d5ef704ea34139baa1a34319fa578f02bf299deb3d90f428ef2f9b9412570974bf96060b83cf06a6b845a918b9c2114ab40d4670c	57	\\x00000001000001002f23f562d4ae75c50c210860da6204ae0535b577bf0b08420bf18aee0a53adf8de2ae6e170270da3eb0fa6b5f147e09c5249b8b2340089756a9ceffa135a1581f8a8647bceb44681cc6fe5ed411a3ebe829acfe20d32d455b88cc2a94c9e72fb9361515a21b1b37b1e1fe7b1787aad69c212a3389ba4784784a4e099640a88fc	\\xb90d5cd823e5c63700fc42bfa7f34d6e06ce6283ffbd6c2f8e175ca888761cd81efac6a547851a0bd85d166b89795a28069af77470bcdcf95e9a5daa84ab2f1c	\\x000000010000000173baddeba4765e32066ef725365c9cc1605c7b7ae92314fbddc2a5a0c996f4c093a1589ea869499da0b61937596dcd3d55cd7eb7c7a5b6d53bd36d39cec62d76c768afd2fde9c3c15a99b01a1a37d401546cf098a2de7fcd488def1e040336471daff0e2072aca67291d20847cf92ce4c930e2e80626c06cbb98a784fab1478d	\\x0000000100010000
28	2	15	\\x5fd2c3d634d961164946c4bbebf185a08bb87f8133a21dc4bfabb4a73f7e9a240240835c3c9e101aec917f6358c554917c5b7b08a5509c31267df44a440afb08	57	\\x00000001000001001b5103d826ffb2ff385b4a593fc7b804131ee361fe5c148597b86ded02a57601779220f13fecb568320ef243da5e395869f3b8abdd82c9b2ae898ac318d14497548d02f41627cd28a0997ee94463e3fb5dbb81c078e46a97068ece3126c8a57a67b1eb72fd71f09b7446a52c1a627a836540a8468b733216b6f81214ac534947	\\x50cbaf556738a4cf248f2f2184cb925b2abd3c8f0baf25ce6c92260ebbee909e8b2a8b90ea212bd5f427d3e9d63fe8fcc085f6d3774c073be01fbcc1a220a5fc	\\x000000010000000141cacb10487512dde87515d5ecfc607cbf7931f647dbcaa869f8399eba0c1448b3ebda6138193b07a922d2f168c59175d23c63a29fde2141e36ebb0353d55ddb872306e602a9e4a0b01a650a382ce2e88bcc4008896cd6050df4e1d7cb396e2fa0253e1b4789b51263d3f07c0f79ec8c5ef1759b3fca77d7da09f19696ff07fd	\\x0000000100010000
29	2	16	\\xcdc653f7dfcb0050c5d9952b18aaed19a9875fe5b5ef9ebc9c4ac3430c4219943f01ff0a1237eacd1a098956ac4d4e2db884aab97997da00f18b1c97cc3c3a02	57	\\x00000001000001009c279b141c77ba22b8a565e1b4f381dd524e3b81df2460a55254f8ecd01b8c62bc9848a0d9432788e373011161b3b4954f0b9e2b7ca870c2c30ff38d49ee65b77dc460c2d49b3fa0b82c3eaf5d3009be2a860bb88057e9c0806fc50196eac46a603fc317c0cfec3c9dcf5f649464f775beb5baf51d67e5212db173188a465a11	\\x3d9a8acbcdcce62f258b53cf9df3b16fc42909f0962e50fc5a101151a9812f577457639ad24f26c98a7a01c95e9230a8dfd298d590bff908bb9dbfb7f34b0282	\\x000000010000000102d59f7e4f8ae75a0e79eaa79c52d86f7e9d98fe5e6d52da863dd1b6872c8911ae97e2e61be08800f54f410a6fcd399f5be4bb92367d9c2dee4436b70dc8312ff7d78f364ee9eee486313ac7e9bfc2c024cce11728bc820cffe3139ff53da5d2b78f6ecf484b4a8653627a299eca43163d9e71d92b5a377c8eb46786f23f2dc8	\\x0000000100010000
30	2	17	\\x65876f10f4198fd5db419f2efb054c0b289f8b3124ce8a98a0e9af5c64670100b4c8f82ee9cae854734a97570ba236549e9b4d868d528c3696e85c75d8596204	57	\\x00000001000001000fe12c8c6146f2b150cdd2163ee76be9042fdf6e5e826e538bef37f6c541f82028e937d2c19669f430ff9f942f6b7a334af54c53e818bfcd6b72ef6d1ada4cb612f1bf2c6d13bacd96560edfa805768557c51fe57a247218cb22ae2a69969d130da6dbd031c340281d12422e1af822867d26db0dc047ddc9e805db16f07f3c17	\\xf887b4ac71c5d24d368618dc4aeeb70f006720eec0cc9926782e61bab0629f3eb59741141a64e6296c6b4a0b830b3d0db81f20488c49ab686d9b443fcde0d26a	\\x00000001000000017283f0d1459693667bc2d0050d5467dff002e09ac4e11906971a83dfe542587deb3fe4a0b78133c38beeaff42cdab6aa9e9f274a3e136f0f782c1a04f910ae20662f619193f63ef2f18f0389a85ed662aa498ff7a136da98dabc73efb6d84abce9f1a1cdb65957172930b19a06d17bacbb07c157f820dba5b8413e14da189815	\\x0000000100010000
31	2	18	\\xc8057cd30bd1234972cecfd7022417ac72f886cde34e87e1dc9fed49e819b16f2d473daa4ef03176c8f3154fa83b1a4c375d1743c2fb34467e291db9b701fb03	57	\\x00000001000001006a2f229db24bbbeca8d27c9ff9c5767ff9f939f13565ef2476a4b37b2fb4ed09dfb811ab3c78726798db781e2e07b29b251575853d453a01baa4991832dd5e41b2db54274b28db2984aced708277c197edc3b84adf00cbd761b7b56a9d726a39820f738edaca8bf562d4f8571d9a813bd11da5d2df1d4ef81e14e0ed441588c9	\\xe162fb28623d5e00ce1017048a858c99c8c96a344d650e91b157249500c29f3fb907880ace06104d62544fdb75be62abbcf6ed7a27e3fd3b98dc57dd8de41ce0	\\x00000001000000011ea98110dd05f16f9269ec9769eea5237918bceb0325b504e1d9bc524bb2c879cfa5f97f91ba57d42587dbc90a5211edd0aba92299e2352ada51a53b322f8c6db6ef45050f785add0dbb0d26ac2da1324bba0476e9aa7a62589e15495bb39a29e8d8a5ef8793954b7d28e63cb899f86f00c542151f3ab3037e74091298eeb7ea	\\x0000000100010000
32	2	19	\\x261947b2fe0b71f73ea5e0793a44cec28ffa127851dc553ea61ef89a82fc844bc4200b39abcead36b991be4f79cf891222229dbcead15b41a983bbed8a57600a	57	\\x000000010000010061c0caf6990b89d084948eca61ad5b9a84ea64eb75d37fa5de9fad1c6e3d13198e717994bba55e1deafeecd71c9e3d9dba31138c785425ef028fdd75091d8e3c0687c9eb7c89a55844ffee174f58534ea85e0fe86a5bbbead30e6110ab6e76a08915282520da2e4b1520ca6d5cc6c53babecd83ae7ba37b90f006f96ac21b65d	\\xf4bb13cc7ea77a25020f34167c742ccc2805490ea0eaacaa0b52d3bcf27a2564252be557439c308b467b431e790d3bd67e4ca13f241bc182e185afead8da9e6b	\\x000000010000000168ea9e1229992abbd4116f84036140d7877cb5de9004fbff6b2143fc32600f0489b13b31f94f84dca822f364f5e33dcc630bcb43c0240e466b29f5c2cfd79a8475eda7b2e25f8d8f24f7e477464a0d06706d2e0d0bd980aff9edb2c592cc6c18a6e47473059d2293ce1df151758aac814466de5868e9d0e0478032fc11528036	\\x0000000100010000
33	2	20	\\x215f90db3eab96b09cc19b7123e80dda6949a0aaff0d3ee0380469dbbf6d2eb65f6adc965ace6ec64c05b770763c368eb50c4461e8220218af9059ce90d0fc00	57	\\x000000010000010048948b2388d544638bc964693a384ac3884efaed8e1c0dadd095ffb2e2c5fe2ba9414b156f0260428ff47aa18da45377271dd25f69376b8aa873b1511268245d95a08bdde85bce17a14aa0ffd24ee6664fdf4c7e72396ae5f6fa392f9dc87c801c79a032cbcd69fb50070f2de11c26db30f52c4b29597d9b07432458d4fdb2f9	\\x903ef04d5f53982587e2fa7bbf36a869b05a7e4a22f28e87776cf03ec9f9a02a71e7516c8b88981a4fe24a86b87f32c345fdae247fddcd2bba39930b4bb90a65	\\x0000000100000001759430a8977562a26204f41d0a412ceca01d9d024c3cc0f711c611d5514a8889fd164ebae1b952d75a25fa1809c7c9ec6237273a203d141d591f25240d206c495d5c3ba91c6257de05d8e31495f096d71c8e8d13f55beab43b918632b2ed7aaaf2dade04669944b0fcbc8d035241b445549835ccb6978169f998e50cf98cf1c7	\\x0000000100010000
34	2	21	\\xcd1b3cbd555e1f57c50c72191ee6aac51db82feafd4f49f4f0e96a09bbbf1fb7cbc8bb2122eed720c08d9ef16a68e12daec0971e6541f4742b9053faa92ea305	57	\\x0000000100000100a8b51af72f49c1fe0acb505aceab41f0b8fd031a3bd1840d48b702fa64fc32ea64748dd65e8c9d4f57dabac18f59bbb4e2292a3c2994d3be663f9f3df839d5832cd890a7cf52a0019d22f8d6979798366283deed81be016cf52973769845b484d3ba63bb605d1261d05a9b923548ae8d096b5978f992fe8b072695e5e314ea20	\\x01d8ef55c639cb964c5f13527d83ca13331abcd76f62ca915c8ffcef385d60524eea0818fc04545ef7aec38393c037aa06aad7b2c27e32ee1ade566b3bdc3cac	\\x0000000100000001654945d1a6e59fa508ae9e05b2415c71c77539b8f170e2d26b22d1e9903af057b4654c1bfd3659aea57af77d01e0f00aaa20c7f730a91c95212bf8d2b116a97d98f414ca53cb3a28def0ae3605f81ef7bdd8523144fcc3ace179b0d0f946ec26b64ee860f2fdb73d7d99a045b0337377e760917998c8b9b46c3045d24a18fbdb	\\x0000000100010000
35	2	22	\\xf5576159073086f573fa2fd11ed742f608e172c89e8ab175db88eb34ade4ee5a65dde6eeecea0186e99869e044b01d527332739935d398b985afc69df357bb08	57	\\x0000000100000100b556a235f5105293c3d3ecf95d3ba169a959e79e302e4aab5a468e9505d56805249a045e47a95febacf21917e9f1765626cf62dacebabc7278f78fd60893f4ac4c73c31c35c98dff3c7b9f4614156e60d13d71149771e450fa4c3bbcc32157d4c53707eac03f11bcefff01254d6ebf3eec483dd4d3cc02ef014d2a9aad7b0f80	\\xf45c4d969d6406f202c64e6d19b8eaf0fd3301f491197c7e587ac526dee483aa068097fd43633f078b6f5b6e391e89d14b23b7f4f8bb1ae50e99873d02a50b87	\\x0000000100000001490a72ec786e0c5acd22bb1caf16de30e37ff548babae75540cb2699cebda5ea536b0dff85dcdfb0a942e21df40a74a9da4908313623a1fcd0d6906d1f940853fa83e67f415b13356dd1eea39284d9ccd8d7333344b640f2fff92db87bcd61cf7517d97a7cccfa59887ac3af202ce94483e0a169facbf0ebd8f65d7942d989b7	\\x0000000100010000
36	2	23	\\xca157f3ec6877cdc7b7331ec98318951ea5e0302ded417c471cb04755cf7a0273353263831de1dd4c738df4e1efe340bf519d5abf8b7caf14839824da515a505	57	\\x0000000100000100a80633db122bdd9ab8b81d6a424dfc05e0133fd241c6615b3188b80bbdef347dd18d15b5a7fff5c89ac4b2d75e7f041d4b977750b8f7eee2ff3ed51b61bd663edb904c5f60a2bcb4dab56cf94fc22d9fa799a247339ae15d30310781b3a69ae3bfc847cba2e259aec38ae30e6c42ac2585774cfd173b2ddd5da401842da7b771	\\xb46293af1377b7006ea7ba78b8e94ab563825d93a76180e9ca5526fa81d9534c18337f882189529f3a32b89b076aa65715bcd783e1e419f0bf48decf4b52e8cd	\\x00000001000000018ef23016339f12228696b045840be55c57bb271faebadb713373da822c9823652d93d2bef844652015cb308ed8a6b47e31ae8137164af762c351a292562416a41e995a56b1cb0efa3ca43a4dc939975df57a36138575adf689be108a313473505776b3971cb124905b335927751319a7aedf1279bc2195e89c360ea751ae6bc7	\\x0000000100010000
37	2	24	\\xd239345a0c7a30f3a84dec56e23cbb03ec28bed5d3c540e6abbc2841abb4b817f04a1fd303a5086c6c8290e88f27f8684dd0382946b6273b4a5472e3aeb49d06	57	\\x00000001000001008e653e248a60fb9078d37c7eae743887a947d26255487de96e11bb62a0fc5d1b26c197ea9947aa1315a64f9ba04000c32c9281b1c149635b5593607fec6d9e1ee7b01a9d0ca89e54965cab2efa04d8632408f289175bd2a1578b548f46a07b33d64b3e631b2d96c1ea5c6a62460dc869ac20867c7b66e77a2e7232d6c1836139	\\x1bf8728d77bc5d04a3d6df0f31320d28ab95faf4ed0bc646885fc02fd48656415a9e35ddf8ff822b550744ac19a1078f96f1fa79aa5c10c17f570fe5cc726c82	\\x0000000100000001a1ab1d02dc1ff88341d58b18e4a991234d1c143c64cc89030be457b6327602d5d1af38060fd4495303109962f22b7016a6fa1d768936a099ce3cc400311250b69e4647f97ea2d8936a71eee0b9c8a54aee3828ca90003c50092b5128961ff3465373f38fe62746cbcb34d2a600b80b34c7db338f2a887e1dc26cdd6a12e7809b	\\x0000000100010000
38	2	25	\\xb25293e9d2c043455e98e608e39eac4cd2c8c26b23b3baf9adc837072808ce575cd778a0287f03f9032c4c403ced91256cfeee50e01f153f6f73ad525d773409	57	\\x000000010000010005cefdafd3132a0c4874e2e624a8872a0e2aa6cf0dcdfa99b017485a2a679ae963973a0e790cf7bdc6b97b5d2f22dab4d73878d98dc7dfff71b70db2a7cb276d8b16e18c89838c97f39252bd23b467e1038eb4f7287a62bb675b45460ddcd4972d7310e07910cbe4e05d9c936ecef1f0c7d07793d34a163ee7ee08806766b43e	\\x7adfc7e48cad1af49e1f44299877d5c9b6c1e17cf84e5e5e58073b1621116096617b8d2c52b028faa86a2452c32fe43c74bcecba5c325f8d8c93781fe878e60d	\\x0000000100000001b4054bcf06e143f3f0e2269bfca16909f9f5601892c28e0ecae25c194f5cde4985631ade981aafa2ae44d815ad2550237bedb25bade9014de78d688434b41ed158be9a9e16e11cf5c880f59947fcd285e41c18f1f0a041e974d76904ae9b4a579a6698258fd447a6d4673f08f10486f293730846f3a43e7befa173aeabc2972b	\\x0000000100010000
39	2	26	\\x70aba1fccfd8b2d83d4ebd1b685dcdff5a02cf751800a906ef31079ce2323e830710fef8e43d8a230db57a3a1d2a9a8b461651eeee3748c08255790989e17500	57	\\x00000001000001003131db7d8c32a30e3af9af4b3099392142949024280361b9b2674ad3d67f2c5a35deea8bd502f27fa8a817e13484e37686034a705d33895f072d3ee69cfdec3bc8e6fffb03c4530d3c8878d028e518b921ad17f8381bad3dd2cc2c15a9b6164e9de792084cf72a9b1bea7a4f2549892a0af92002d17897186d8c2da958d87a79	\\x297312908e47069392555c31e0c976affa859156731603d6f1cae1c560b997bb9d94f9223c2b2fb1a6acd1fe62b54c4d290690b243db938a200bf6966c1ad279	\\x000000010000000157a8ac8f3fe599807256c8ce21e270847a5915043c5724efc8e9f89a5c1b3ffc6ed18dacbd1fbeeac27515719e37182cb55fa879c9f75bf531f7312018ed885195eb90f3cc4bfb91af5d4e44a2d0d8c5591571b605c43a06e4dd144061e23789146a8b37fdb223bf7f2760ad46f775d635a5a800bb78d41ff42067285dc2ab5c	\\x0000000100010000
40	2	27	\\x837a2434c5ece4d40f0e41e1f4f4a356a941dbd9b345c84f523d5ec6ca7ac32312023135fd6c59c9d508672642a4b4080bc4ea74accd84ce14055e95407a6907	57	\\x00000001000001001965ddc62073da3b9bb5fe659f68f32440b7ac7d2c89e82ba9e1df022d7aa1a21234820af73492fc33709c77819d0c4455457d892845de7b28d2446dafdce8c32a044328194369eb415db1ba08817fa2a035f68f8d2746a81f407856ea893d501530ff8cd206c86c8bf5b4f3fadbe1eb3c226d2c30a416cd15cd3c8d38987698	\\x99d39aa1de2970f38eea311d57bb2937e8c2f82af269c1643076f35363bba2f6fa3c3c307330a6e59b1e4356843949d22ed3bc43d39508ee9e43882eb9451b8e	\\x0000000100000001a0e028d01bc51c0c78131048acd2beee00c2b38339185b85e04e37b8d6a8a387e207fd8623c4d254d5c9ad99f4c02a8e25571437eeccd86c3d5f79031cae1d70746fbed4a3dd961a4df8002e430b9964596c068c13dc6307878270913a929cf2e7ab23ca7c15105500bf271d17edbe776c213ff7a78f82c041bbfdd323c5389b	\\x0000000100010000
41	2	28	\\xa9e08b3ed3df8912ad8bdcb55a3ff32340b346359dadcdb971d4b1f2649ad825cfecb9f7b42aad9031f931ea671119dec49b2a0dad317aa9fdb8cc8951f62002	57	\\x00000001000001005371589845c4edf24ec4763cdccde2f3501296b2564e4b14da154f82da3c54721a6933b95fd0095de562fd4b7f629ebf16ad8a0ed5c4c9cc91c6ad8193220cd2862b009bec586b4cee8ad1d9ec53c4d0d3cf29138049c25ea6b948660597f18ccb16fc32c404027af18e6e17782a932a47a56f6585f466c2501a0a58337106b1	\\xd4332d9e0eab8d5db8e4f59ed782626823986c6b8fef68969984f7dc3524a329355827800565ed4ba262a87c433a5cfe35e4d3ec5df972484a6f48431ea8ecf0	\\x000000010000000185de20b279003f48f9d1042e734c7eb5cc3a3bf689c6a0be1f81509a3cb7c1cc75594da25cafbfb95eaf32758f88d9565a48f0c4c8e199780059982c65a387aa4827bed7c37e0fb3822793f05dcada87e57dc0465afad8e0c310b32a4ede66266f3a2b9815c2fecfe77c20512f26c9c5edc9e631400827908a0eef064b6362b8	\\x0000000100010000
42	2	29	\\x738bd30f5221b1a71862cc0d5766b3d9141802afdb6d25c51a427db190243137c03461ee103a3dec735cc1c554131031b368b121f2aaa035cf46677113579104	57	\\x0000000100000100b19fd3da0d35d1f79a44831c549077343bb456af9c321cde78dc5d4f5689d74a587a9d8682b61da4499474f5c6fae90e5cc8a7c64f9ce849b4372cbfb595b53ef2bb5571a1a06918f6cee01c55391fd91dc1a0b80c624d47f44b4a06a0f0ee2ee58c03473de5f8445b5d8b82a28ce481f4a0abad87b53c91d67067e3c8a0d7d7	\\x2767db0778205b96bb6ef0ec372cc028e576bcc0c939d61f121bedc7810a84ea31d61b1ab1d0d6d94ebc1da7a3ed2dd0c6e2aa03f726a8a945514887820f080a	\\x0000000100000001992b273b97bebe0566e087d4de9eec9cf1579f9ccdcb0dc2df1dddbf8ad527dc566f9ea8370603ce5e61809014a985aa358cb5a208575adeb7b8fe906a84f87fd2bfd490834f4db6de91c314499bb1f11b2c1abe59ca45cd31eb5bfdbdaba4805c54035baf66236640815e66c1b604607ec8670a855f9e60b2a9117b227f2153	\\x0000000100010000
43	2	30	\\x61cc4e4da5ce3d05788679f39bd7611214410ebe46361b415b0d9e3d87803b8ba10af145a2aefc64830be1779ed1156a17723f7cee138f4363eea2971a364306	57	\\x00000001000001007b893efc5b81a872690300b1d669806a07b8e9520184ef9584fa33218593735abc2375b7616b962a5a992e428647a480427967e897ab6f6377781dc95d9b0d06324825aa49b52492100aad112f49ee1aa8313e501c622b27e9f1abeecf3609ebae51d5751b6f376c48938974d5657499fb4bf4a176a9707fcfee8a5be82340ca	\\x431953c9a41e08b98737d5b0b6d03ab8d7550f9a7ee13a4735dfd9917181572608e4a87bc4173ea3fd280032442e47e5a0ad855917d7cddc3b5116699012590f	\\x000000010000000146e8d45d8f8fd3160aae21787910a2a5240bc7f030b040222e1996638a62d0227145482ff59b39b7d9efa9e63718297b1cf5edbffd763a4c6f62a40cfd3687cf863c9b5d533c1042b6835e1c727826615715a6c4839e448a32d17de7e2ea10ee87e84f405efc66f9d45eadf3bc787b24a8f180e444bc097d42c5d962e66cf424	\\x0000000100010000
44	2	31	\\xc3053210603940b61a1499a336cddb0bb61c22f08527e527471b764b31c82ac8989d28d820a5b3486960a89bd7b43865c73373e123de1a2d5b5b42f4c5f26203	57	\\x00000001000001005ec6193eb6741b696db97598c527f5f44817e24f394b652502e96872997ec2b59d1de654221bf076368d2f386fe6fe4899b15842c78146b36a5c43df9a544fa2d11afd2ec84cb978b520689bc2bc44b0ffca4cb53bbc184d64b45cc1c33c4795a1e0dcd6ce128b0223a7719c2dcbc81dc878acac30e851b946acb05cf0c3ba81	\\xdd7c1bb5bc98bbf07ae1644091fc93746a8682f909eea203f21af89c6eadb6d58d76e3f2702b39d7402c810f98677670d09d1332733a442aca9ce641a76c9eed	\\x0000000100000001666c2aa54965e8c8cabe592761243b4cda04c3968f4d201a982a99e72bbdcb99d3af6cbacd6448a0e667805c9b80e78f1fd7e61bc400b3c62064a83ec8a90ec69103ebecae7b73afbb3f0fecff2861e221bd2bbf9712780cb3e2507eb67763b632db8af802b21a11a012b33a7cde716c588a639291260414ef19572deceb2d3e	\\x0000000100010000
45	2	32	\\xb192a9a644605e78e381423e03d02b4960c56bb6152d493f2b4c2125cd3d50b81ce1b3c87257d2f750c2473e29bb075cb044aff6e60959435720a5d24f26bc0d	57	\\x00000001000001004c5fa8bc4f25b412175bbe09830ffa8337670b990c2cfae0e713131ecf1a62aee637ba9f3bfafd20f732b92f51955913d6c6722fef0facc8c48edfe6c302814e3d08b5e195ceaf88510426f9496f9c4d522e4eb85e87b8b8682c40996105a0aabaab131018f2ef0842c61f62ff21bdce6c258fedd54c80ecd5b5b0ec0bfbe702	\\xafdd35fcb0618cdfac0f7f166a8a44143f31e86f27db172a53ee9959d9527af363f8f5d99b8115e1aa59c10142fcfff66e701519a4cf6a89f28a599dd5e5f8a0	\\x0000000100000001b0f71011461ad16ec9ee1dc9a11cca6cdd9e3126e59d95a7444ae8eec0a1623e3e675b1f8cdb3d3917df45773a86b69b777b06e749f1e665c08d1eed5c7d7ccdc5d7e3ccd5b34a9e6bdf70fb781a8d746d25e49b5977f7a193f9759239cbc7cd8380c24648b27cd5e2feb19a4320141621586524d60538103b753c0e5c5ce18c	\\x0000000100010000
46	2	33	\\x460e9ae2055c382d986aedc993328d20726a41dcf7d132fc6a20a1dcb6d235581fb65282eb30a38cf234a3a1fe886b442a3085e8ca8f488d5f7fb60c1f8be90f	57	\\x0000000100000100a98a30575758b5a005d33664c2090cb755095474b45f6f99d4f32808b48c265336bba9e14ce90689ab869c1adab3c9e5904126f2f4e453ce4f058b91fdeef041dabfa3c513414e7b4022d4e3f54d5971c5888747c0f43481060576be8653fed324c9365c63183dec39b54d2561404c346679d15f06f5ba93bdaf3d56588528c1	\\xc6262c40337d169d2346cbe81ef0305c9ff2ee540029904ec32121a67af9542aa4c257d5fa3285b59c1ede177fbc726bc86e0e622c462994dcb141fa171edbb4	\\x000000010000000130b0274f68c6efdc37d9fbabc5b4673c3c2677917cee33f50ddfc918a2f57ba38b99133025444ecf7b2f4e0a1427a11697463bfe1d92f1d5a28ecb4789f219eaf6982f46a6fe52b698f55b4d94db60575458e3fbe860a5423e07578b63bac927f304b1825a3459dc197417bb9dbd3872e3a18ed10afa73adb1bfe9b49563ae97	\\x0000000100010000
47	2	34	\\xe1ee192ced962ea92143218e27a61e1b0002cc825b3ad723a5865517d0e6847e0be98db75d4ee68f508db7134c131a5d30c60b113749859a548c852ea5e75701	57	\\x00000001000001008f210f389082fb056cee0661bcfdad3b50027b6aa5918ea56277665d0d206efcd6c0adf41e191f0f27d093cc6550f90ed1cf093376f9802f5579ca569f072c8bd137612a413af0f75447f0cbf41d1bc0d99e7b6d9b1814125859dde8382a7cc5db446762888609bb02bf2bad54cfbba2e0a2cb52d107ca657f62019f01f9ba80	\\xa2897e14996ae23ece29bea4e07da2f7d04f6d3c75151328bb350d303299cd62c014f885d86dd4ea3a015dd3b8045b5f0a3d04e5c31e9180688ef7e7bf7fc6e0	\\x000000010000000115e8ba99a5a52754f8964335576dee0687361051cf5454bc406b7de9372e6502b03803b2f249516218b7fa9f951b7c410530737f74bd3c53d31a7728f59d8245fc2520fc343372fcb5a6f25f2d19d5b3e69ddd06f060b2bcfd1f2b764def78f5abdda69b23e01b70f91926d645c8e8f8e955e5e812e66c94244f2b8df2486c62	\\x0000000100010000
48	2	35	\\x150f978548865cbe2cd38e06013ec270f4e7b5950f5cb774fd5bee0f7acdf056960b81c73e7d0c12f58b7e2c6529ada173d6530c21239399ba69c6bdbd095d0e	57	\\x000000010000010042cc2ac662c9aad91980431ed607a8711d4bc9cde5dc0539a43aa99b5b2c48ccf0a780f0f94ff765e677d62ee65b847a2d424f798158930ecf866f4df62f3fa129856b36bdacb57d7b7a4e2dd0e114f8e480790e8f41ec3ea4759ce83e7cd104f4f5c151f531013de72a8e40910b10efdd233aeaff4c23ee29c9d27e821381b7	\\x6b1c0ad9f5d51afc5dba23741d421a6eb1f958797d2d847b3e6131c394552f7cd86dd344cf27efd9735b7c1db9522b4c6d25f00702479873f2967aaa7f7c7567	\\x000000010000000138cd505b792f54430fbf046ceb42ff663c676936f178125136f36f7fecd8321232a8f24746eee3b3797ab29000c8951a5c61cf79f3c5bf700d4fa4442315ce057fa0a33ca61e6d856a57e7d8c68c33d49b7eeeb27552815c0ded45c24f3cb714695888efb283240880887e196542b81e8f4e637d6712823c13af00e31d35e11a	\\x0000000100010000
49	2	36	\\xd20d1a759e972d3f14ea3153366692fb6a5d4c3a37aa54e91ee7005f550b657630cbda33129d6d9cf0c0fbfe5d9461f7051165a0bedb0060c9d3e9a8ed2f7c0b	57	\\x00000001000001008e08b0f23ac00bee6ba94f0c3f7a7fc0778db66ae0e75878869bb3ece15a52fc101068d9cfdd3899cef7ad8adf8da5c0b3506d62a4e7cfea5001d6f92da59f1420dd5bb1e623d8b86ae1066804cd608ed6df68b698fafb168c07adb255b1039edc233af68637bc9df9e1a1d6c5cf4cdecfb753b97ab5bac992a60b8b80be6ae0	\\x985454497b6f7aef9d1ce92fddfb0d4597d812179e50071154eaea4f6e0fda381d1b40fe7bd3ccd56fc792333ce4b8175ec48d11d1b015be4301a286e70a399d	\\x000000010000000159923a2e436b197618c434142b86c7c6a25055db3347010e49f600c84fdc79eda4198db9fdef1a7bab61130356232fb4062fa5c1c789db882aaafce8283c1a4d14d37909d4e5191ca118721dc61f1ab55e0918835ebdfad405d899b59e8cf15bc020a69b9ebffcc9749b35e976014c731f9d349c863c74c5f6a0a0166c0896c2	\\x0000000100010000
50	2	37	\\x686ca8763983a812ddc008a179e345655dd337a5a303d45caeff7f17307da830a13bb23db9cde5caed43e5510030ea848bcb9d792ebe3b44ff60a2a9a9829b0c	57	\\x0000000100000100a93d5369b9f40831c77e173ada768263c3846ccb7d44803f1e759b1d72c0755b22c9d1db745d8114b7ebd97d0a158e179eae4fdf8750043bfd29186711805b7556c4ad3f0d661953b445f7ac4d2498bddccc2fd3509104a92c49cb8804d8c3f2bf92d11c4a91e8ca6235a0404d1c4ef893f94a82d8fbf6ddfcb2a71c9df19a13	\\x5ba146b750218e196308f56c6b44320491054ad1e6e6332919b9798c5b6e23816a0e3f703cfc1c188babc02e9c7c461d79fb5f3f208d1ccc64e406adfbba2a0f	\\x000000010000000155cabf025cfafbfc0f3955556eb2150c27f81eb295f65a3170e25175e18295f6c0f19345799d495dd91775746951565def18787c751504bf0b94df8ea145687c195464e46d0f085070ee3f5e185726a8343af56e22b08b6ba5295c1e8b8f3e413b08dce7372aff6087c17696e6f7876ebb4e43505931ef4eb9584f05331bf0f3	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xa808007e19b327aa80711602607d25d382d686c2de9717f2f1b6e484604dab21	\\x0303b8b6f69fe3600ad8a78b861152035a453d565f8f54fac667a3ac96c6d48cc6e3f4296d5e81c9f0a2a09f1c4871dfb835a88daa47f35a748d7510f6f61012
2	2	\\x597093622780d5bd58d2caeb1676e7d6c5d163df5071a57d8c0af2d20a5c6a7b	\\x51e8457ebf056bd4f921ae6acc00a469294528ebadd5d666c065841ebccb66528b132a6fdfb51537b5f62f1a02ed3fb9b558432676c8c28e56456c5fe5e559cf
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
1	\\xcd9219213a2511278bcaa81224ef35cb0ee9e2aea189ba275a5a3244ca94542f	0	0	1649911499000000	1868244301000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_h_payto, exchange_account_section, execution_date) FROM stdin;
1	\\xcd9219213a2511278bcaa81224ef35cb0ee9e2aea189ba275a5a3244ca94542f	2	8	0	\\x381a99fa9c05f43553706af4d8970a4ed5b6423e64677b7e827bc68baa4b79f2	exchange-account-1	1647492286000000
\.


--
-- Data for Name: reserves_out_by_reserve_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_by_reserve_default (reserve_uuid, h_blind_ev) FROM stdin;
1	\\x6fe2372104e1d9f9965a24091d2a7f04d980cb1186c8e0e6366c208e658f03baccb13273ad07395b807b329cc37a0b07632c6a9dc36be28c19668fe9655d89d1
1	\\x419038bc83a7125ee61043f16e3786c93d7a178533d30345465dd54eea3657f31b54599ab1fdc1c1e482c4faa0a0d7671f9e6ec0063802bc5ed19be83ef10244
1	\\x43665a1e669c46f7a47acb8cdbd157f48e00d6a6fb3a9a7ac407482a6ddbee53d167b4b254edc30671cc106754f5b5f9e32c523fbd5b8f8f712a1f92e9d1f0ee
1	\\x411451f999ec18e89f1c28c799e66a1d3fb6e5098cc2fc67f8fbcd12e5856ab03844cb29c8a85dadc6504eb3d29a4c3ffde6c654aa485b51b2496f34ebe79e46
1	\\xf7fe3808602adaaf176616e21f383a9ed85e00cbda3af874c01adc4ba7a78e84090f3b26315b61f7bd1b58cdf7b951c53a307550c4117cb6c80300d01540067b
1	\\x60798ebe276b6a801681012f42d7e90d0e457a345db7b845c54326ff9b016c58976844d796b781eb575dfaf0adadad7b9e28de69576162218c8e64244aaf72d8
1	\\xf00c05171611363434fe73fecd17bd668c123cc969af03a5638879858958924422acb245a0bc392f8ba1d83cf59284b13bb7b50fa2fd161dbf7e748c1e34f5b1
1	\\x1735441b6e058689a705ed14971925149650c676a451603dbe7257faf878730cd63fd209324b17fcfb89411610f631a12a96255fffaa104da0870f777397796e
1	\\xfe6d387586b8df45fb014a1a377ef47c76f641bcbcdff262df0ad9dcf2c25f0d23ea396902ab00b963029c6294940506d48c5b0b3a6217c46ba7280e5c875f46
1	\\x54576a3287898a6f0107f54f977447a6eb3abbd7b0df66e9e1586095eee5fa5602f1b399d041e4afbe0613bf16a37c14439ff4d070946c72c3960b123bc01bce
1	\\xbc1e7e6dc43397e13c798c38468f12584bb69bb0dcf351e5677d9f97c16b3b43ffcb2f59a8c015d9da6641609cc92b30dc2af55b2e3b8c5053a900806c184134
1	\\x5499650ba7c24d7f3b59187d6def46b5ecdcbcbe504221da19a781cec5e9bbec04cec4567c9e4a6978a811f2dba265d52a01c927238b326f105a35f7c5f5eb2d
1	\\x75b7b2969675eeab2a5c35caae7b5cbdb50b2d096617319afdcec64bc872079b14d2048910b13d8838eb281f9600302b5b0637e59af63f3f7a9f8acddac2751e
1	\\x69d033c528089b59dea04df37c3ce058868f6fcad3d0bb772a875e5dad8b09bfd63a84187321d9adf7d3af9c112ed33812a3a9f2ff2631e4f54c9e183a6bf766
1	\\xcb0574ed5c1a80c8dc8b6768e5dfb44e20fd946cb1fd405ea47e0904fe5ab032206d7c6f6aeca94ba392dd3d40ab8bbd6ba20849791f5f0328c574a77652ded0
1	\\x7293df86a2f25097aa44579b3b5efdb69ff4df502c86ee7550b7fadab846701a11566c2447afc78ccb46988f2086b7c87ded3383d3168978730b82af0e780530
1	\\xd83ef0f20a5b2f4d1ba5d2fac8514597a08e541c8e535ca4643e017d572869c690a9d871c78075a6a71f80fb3e94f82ccd38974b6746f739e5c5cfb1cd7daaf9
1	\\xf664556863fd4ea2c31bf9e387c96929eb4a5b5548ab92a3a561e9bcf7f6c6f38435b664b259768a13b11b54b1562a69af8379988979b8a04507c4ddb9e757a7
1	\\xd0f2cc30239b3734acf12946db0646dfef43b8ca21e460bb73d909667bdcdc7fd2aec9f4bce4429a6ca19c45be9f78baaf19f1ccf2e68d3547a09aa46877affb
1	\\xe8654481b508c9489fe55c868a6b886d7be72c9c8e6a712d34896fe0d74b71db651a2c7c7e1c27a11c56c603b529477aa68759231e9f63ba942a9f476dbf6a6d
1	\\x97e3573b0ede6cd0f1820a9b16b6f4609c2c78ea0b09f6b808fef6873bcd0c4b0f409a3444487516846b21c676966d5fd24e975cdb32c16ed709ac6b120e2935
1	\\x773d3ad0079c78ffd2887d0f0eda31dc845f231c80fcf479484f1b6fb08462a7f826b81d63f11bf3983451c76b2e34bc3938ed3cc85849420bb81be518c37be4
1	\\x981871572948b6cac631096e7ca2774650730753c1a4d9763a2bd951b89b4370c82f6bee7b6f48cb6d04d0e7ebfb9bcb05967e5460e75ed2328cc65f3924e39b
1	\\x525d42befb4d9a07b40f11f53e8248be5eb7f067fcd0806112468dc069c89bff88bb34089e41e3851020e5a3b81740e67a8b70ad7a93e88f788fb62f1ee662de
1	\\x77b33ba2e1056ce2205a8578634f78d5f96ed1c13381df83b4fdf8f0a8e97f5ddaba68f02c885c572884189be8ea621cd16d8e44187970f6771a319eb69dc6df
1	\\x3c7acb968a954ba59ebc98da18e3a9d8a16b97cf35eb83f4d99edd872d6922b699952ef194951a9bf091477e66c8f962924bfba1a8c5ed16cc00a909b8bcd66e
1	\\x59085b0b7e0a16739d11a0e042e8020b4192553d78f5dc45fd53d5afe3f80671b0b58041557a17308739249ad7ec10be01fb6de26f2a4160a592d12c18d7dbb0
1	\\x0a6f040faad0805b2afa0516c63b5c110187518533b933a9ac0d7bddea6e38cc5f495d52b36dd6185e0388a38e8ebed99e7538b84f6256ccc4c5c8f20fd95bc4
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\x6fe2372104e1d9f9965a24091d2a7f04d980cb1186c8e0e6366c208e658f03baccb13273ad07395b807b329cc37a0b07632c6a9dc36be28c19668fe9655d89d1	41	\\x00000001000000019c86dbf5d6fd91b9b1f2642b2618218f638de2b45fc1231e1140bf439edd341a23f2d1d4ba436180fa7fc3131f0c0f09487674689ddfbe9b4d14922b89ce967674c2bec19bc986e49d3522adb6967517f70993b6c59ce8e844935e149af29d72b304a3fd7110a157f5ac185db6e936553d1fd1c22b8eca3a7e82041a429305d3	1	\\x27cbd3bf9fa4c3f5058bbc211c850f9bc0d06d60fa49fc8c833be776bbed0227b6f5b634841a274095af761104524530d2c77c7c631f6e8bc77c0476b447a90c	1647492289000000	5	1000000
2	\\x419038bc83a7125ee61043f16e3786c93d7a178533d30345465dd54eea3657f31b54599ab1fdc1c1e482c4faa0a0d7671f9e6ec0063802bc5ed19be83ef10244	171	\\x000000010000000122d29f3444dfcb9bec8cad5c00cf358a566296f6115253657a910ba0ddd9e82b4495f6e37714ac90db9734f60d1677bc61f95a4aea4d0f0f580ee027d70bf06199475376ba4b3c2c4f5b32cd4456ab530fa80f60883e8c8a5a6fa84c213b65d217e664f0c82a04d36f7a155e0a3f57027857628790a29673f30d1ff8d2305051	1	\\xb37ad88fb082c69078a2f1a6331fbf428817449626563e2c87ea37e55270af356c1f4423a72398e1dfa0fc69d5f2bafa639d4bf328f955f7037172ebfec8300a	1647492289000000	2	3000000
3	\\x43665a1e669c46f7a47acb8cdbd157f48e00d6a6fb3a9a7ac407482a6ddbee53d167b4b254edc30671cc106754f5b5f9e32c523fbd5b8f8f712a1f92e9d1f0ee	159	\\x000000010000000151c81d6d48dfaecfc44bd20e10a27d08cbc9baed03e363b91c788bf32655aa0d32035c00e5a24e345d68d21dfcbc6b71cb26ebae67f985127a1d2ee48dc5f4e8b1a473c9a42421753999fe5a32571d183e2ab218400f922484f16b40e383e30553eaeb7330f212ab2f88b81c557d1c4ddeae534e14cfcdaec4c44fbf0b144647	1	\\xa2e6276a09094df0f429c5ec773e7985750e3e756a1def499579a1144bec23d7afb70c3d12855684e9db8175ae28068bd6f78a16027cae6bab3038e404d10c07	1647492289000000	0	11000000
4	\\x411451f999ec18e89f1c28c799e66a1d3fb6e5098cc2fc67f8fbcd12e5856ab03844cb29c8a85dadc6504eb3d29a4c3ffde6c654aa485b51b2496f34ebe79e46	159	\\x0000000100000001c2ae470f5781613e27aeb84c162e1c0f6d863a9711323c929afe13cefd83a8ea3fae31de8198c41fe6ad980a09f8547b53925999befbab6c472e8b831f0a3f05dc989e3dcd513bfca227a1b5888f431c825a539266bb9f299fb3f3d37277cf6c32347e7ee44b03b3b3d5e29052a9c1e084fbac1548dc11e565a079fe8ae6ede8	1	\\x68c3cf0e1c90bcf980608215d91d39870377056c6fd8bfde85f289c00bf5655e25f86c5a347e57f7deb391681bd1f73cf60a278192bd8fd9b450fcd42abfa40f	1647492289000000	0	11000000
5	\\xf7fe3808602adaaf176616e21f383a9ed85e00cbda3af874c01adc4ba7a78e84090f3b26315b61f7bd1b58cdf7b951c53a307550c4117cb6c80300d01540067b	159	\\x00000001000000019deb0bf0cf4a1f4f1449b41099a1aab907cae7a0e0dc568635ace47fcb370d160c0814c81586d9e80701bafd55130c976eb2cd466332abe5f9796b671485e23fa9daaa9367e62d6a0f6d555b653aa98a9aca96c02f625e868ae0630d8359eea5be36a60975f8c6fcbc6bbd715fe0ff32dd4d89cceea22bc05a7f2dfd41b5ff66	1	\\x5a23fb127ff3155d229a1bef2819d2b101a5ceb6a6f8c8891fa48f78628964db5ad863dcc18e7c3672ebd74913dc44304a821eda66a7e7628d191d9438fcab09	1647492289000000	0	11000000
6	\\x60798ebe276b6a801681012f42d7e90d0e457a345db7b845c54326ff9b016c58976844d796b781eb575dfaf0adadad7b9e28de69576162218c8e64244aaf72d8	159	\\x0000000100000001c1c9cb3fc90a1ef8f2b45290654b59c66df09f51f904a03a491300a727d7c14886ad0dbebfe29970f91b9e5c4d11e4c288d4be3054921369303174a38164950a5972aaeb4cab2b4959e6230679b2853097660f88372f8ff721e2bce034931263f9d857c3d15468f3fd7db98ebabfc15e588eef54e580cda7496416055fbf18b0	1	\\xe562ce89d237cfb53f7f82945acb7c133928e5eb0ca2192295a4f71794d9cba38723c93b44043fc102e9c7bc01433a85f8936e34085520c0cbf5f209e665a606	1647492289000000	0	11000000
7	\\xf00c05171611363434fe73fecd17bd668c123cc969af03a5638879858958924422acb245a0bc392f8ba1d83cf59284b13bb7b50fa2fd161dbf7e748c1e34f5b1	159	\\x0000000100000001b7a3ad6e5cded4654ccf8ea7e77ab15adfd13225e1fd2b72d88c56167f868c052194447ac062760566bb50abf1c5044a48ce1239cfa68edb79127a8eac4699b25c7a3404dee28c1182b7a95591ea3bb567b1032ceb84581a6a7114d0e79427ea5a887d992d4b8a802799a1bf479587c64f4cd2e04a97f9adbd9c048db52d1e52	1	\\x472f3cf9174e29bde276e463fb8d041a0bedccad5e312f65cab2436581c04b05703b2dcd358e083344a32355e74e5549cc3d033be27861e08dc761ef270ed202	1647492289000000	0	11000000
8	\\x1735441b6e058689a705ed14971925149650c676a451603dbe7257faf878730cd63fd209324b17fcfb89411610f631a12a96255fffaa104da0870f777397796e	159	\\x00000001000000018618b840607e0a33cda56feb4bb5343e14626fd42079bfad9db3cb2e4b02010ba3e4c845b1bb4ce56601105c3d8126a99afd60e013bdc78dbd8c6bf8bafbcfa2cb0ba1dac138521f704e2e2324c7a70fdf91ec6bbeb7871fc642835079b089058b32227fb1c4cbe026897fe2a7fe593d60445ad57ecc5766b05ea518c10f1ce3	1	\\xab3b1c19b040a30bf04fa7989db7573ec731c9c9cfa618f5ec7023baddabf234481a80feba7012d77ac501725a33a9f7aa8c99dcd3e08bb17acc9a1af56cdd02	1647492289000000	0	11000000
9	\\xfe6d387586b8df45fb014a1a377ef47c76f641bcbcdff262df0ad9dcf2c25f0d23ea396902ab00b963029c6294940506d48c5b0b3a6217c46ba7280e5c875f46	159	\\x0000000100000001c711803a4a6610783b1c62013be390f15e2f51a604096d8facd8fd95bb3ff63144abdb2f572ea8984c951dd360d7ea7ead409172888e15d87e94c0059c790e08532bb3b72993ae9ba6dcae9ec5fab45a978763f06b9c2d7c23bb60c5368822c5616443958ad4e919dd989a1269bac10f64b2e37cc264e67a58ced1f74787fdb0	1	\\xf3033aa540caf69215bc7db6b5fee18f3b7ffddfb9eaef294f45341f4cccb588eeb9615cde4ea48434732a47859b90ac857a19fdbad30ad75da73b9eec7b570b	1647492290000000	0	11000000
10	\\x54576a3287898a6f0107f54f977447a6eb3abbd7b0df66e9e1586095eee5fa5602f1b399d041e4afbe0613bf16a37c14439ff4d070946c72c3960b123bc01bce	159	\\x0000000100000001a4cb137e91a4a49c2098d28e3a076c7dcab62cddcb53e1a85c59b73ed886bafc123bc6a6f417fc73f9a3011aab294052342a85c22156c7ea990b86858be7637b28c4d3f815e8cc4ccbc3bed58e73780d1b38eb9989b347735e8754c3128768e82cd9eb40814565e0840c367694df4f31cad8cb2a16dfcd770b886cab8522b519	1	\\x541ba127832a03d0626532c25d5a4df7f23fe9c496d0309eb6895b30cbd01a826b575830ba66d6440cd7df2f007d63a6981e6e4b7ca536c50be2ebfed000f401	1647492290000000	0	11000000
11	\\xbc1e7e6dc43397e13c798c38468f12584bb69bb0dcf351e5677d9f97c16b3b43ffcb2f59a8c015d9da6641609cc92b30dc2af55b2e3b8c5053a900806c184134	243	\\x000000010000000108bb39d7f6254171d10a0cb58617e1d2c3bd46d9ddfc3fcef4c12e4eeac239edb7ee3007c7c05d9bb4263db283f48570c53b0d73c55d787fbbc2495fae73fbac92b955d831a61b1855a02a0345192ada6538677e0a0a9b24fb03506d148d156bfe4cf9338257c68b69141ce38877bbabb326ae75addeb05cf69d9a3790adafa3	1	\\xf14828e3ab2a747ed32ea02e1e1414a9f1ca79363764fccbb66b43de6b406f309d97f5deb610d9e9c660699f3550308bfcae33ab6bed8b24e57ccf271fbf3306	1647492290000000	0	2000000
12	\\x5499650ba7c24d7f3b59187d6def46b5ecdcbcbe504221da19a781cec5e9bbec04cec4567c9e4a6978a811f2dba265d52a01c927238b326f105a35f7c5f5eb2d	243	\\x00000001000000012bbdae382f8040d6595876292d7045947a6b3658f80b8ad42f4fbeb5ec22a3d3a096d2df7f47f0b14a74b8d1b4ce8741182e38e79b2f6865e5f5a0770fdb2b30a266f14b813f52f6bd7a22b59116961bc0c3744ea84105a703b54c88307248cc2b0d18a7989d3536aa0ff4795249fa9f9faece23fb1f5064275ef1ddf193fb28	1	\\x860f8271cf8ac2193d9af612f6dd9703e0860f46d5ed3daf0cd9d3378ef1ab86ef636e713a9dc7cfabb843f0ae88d17c466a531cb0a786f6b61e0db765b4fd0c	1647492290000000	0	2000000
13	\\x75b7b2969675eeab2a5c35caae7b5cbdb50b2d096617319afdcec64bc872079b14d2048910b13d8838eb281f9600302b5b0637e59af63f3f7a9f8acddac2751e	243	\\x00000001000000010e6720f6a86e20a1900031dd0899a5c6346f8be6240e94a463a0bb49044d5ae00c77bf4adfffb45e419506dfb3c5cf71ea4ace2e9752e1861b4ef2ad80d015d212129b0a8bfeeb4e5d934f7e738870aba5155daeb7cb88977fbb52d1b348a9277fc1469cd160057331fb2d338dbb8928e8a57825372e9ead5bcde48ffcd95e35	1	\\x4ef8b13b039f175e955c6741fbface94d7ce1dfda8b7b42fc8aad8dd6f007738c64b1c2c09c9aa6ec916ad19a7715795dacdf3e67e29ae1eda694a4ae41e200c	1647492290000000	0	2000000
14	\\x69d033c528089b59dea04df37c3ce058868f6fcad3d0bb772a875e5dad8b09bfd63a84187321d9adf7d3af9c112ed33812a3a9f2ff2631e4f54c9e183a6bf766	243	\\x00000001000000013e5494bad7b334060815fbf96522fb48fb795acd7c70f4f4fa1070629407087edc7d7cc8efa8eb59645c3535d615b71780fefb3d07e5fbff3e0bbfdc8f5b10928d3551ac8a51b4742f6fc20a98a532f67deab121dda62dfadcc538bf3b844992140cee26d84be6dcf717138b9278082ad66ecec2590e2c30d783b00096b05a99	1	\\xccca0c58dfed5f860b31c7d6c2c5022fef13029f7da8954eab46b02c05d115d00f9f63047fcbaf91addd2cdd70db97f42f99ce441d5c0de7b7c3e82f2348a502	1647492290000000	0	2000000
15	\\xcb0574ed5c1a80c8dc8b6768e5dfb44e20fd946cb1fd405ea47e0904fe5ab032206d7c6f6aeca94ba392dd3d40ab8bbd6ba20849791f5f0328c574a77652ded0	31	\\x000000010000000122aad1e643cf05e7f4f9d7fefebea3db1fa8c7b64209cb2f48f1eb9d82e360a73e05ca00eac18a942343faaa1012ed2e8fe6d688a2423b9296faaf30d234f57c7faaf98a542e7f07dc7ec42f949a2030dae57f75b01bef0c68924ba5110a43d487a63b60747e22f4a96b7c047fb7faafbfb22740dd3b7ea572f7d928f226ace1	1	\\x854037709f3068de5210dfddda732da010d6149c58843bfe7b7b678999cc8386a8c2cdf115d96e853d798bec0d9dbc05133920e5270bb83acaed31bcd1b6da06	1647492300000000	1	2000000
16	\\x7293df86a2f25097aa44579b3b5efdb69ff4df502c86ee7550b7fadab846701a11566c2447afc78ccb46988f2086b7c87ded3383d3168978730b82af0e780530	159	\\x0000000100000001455e1b7646dc2f45bd51a005bd6baf202ddc07e03bf82d723200be3580f90a3608641c97dc71ae03b55f69bf74e4676e3b48119a2b123294ab7739fb3f14b072b3e40d139d54f766d01a890795dd1d5e2c244334ca5be4e1def01615209a5c524e58bd91dd18fbd4f5d3c01fe6860d1078403f2d82b1e96945ae80984e969bf5	1	\\x6133e616fe1b4155e9cddb90503e2584544141023cb1acbb42fb595f09436a990d4c582040ba1b63cf769bdb6a3d1d5d16899936092701dda744618a3c61d50d	1647492300000000	0	11000000
17	\\xd83ef0f20a5b2f4d1ba5d2fac8514597a08e541c8e535ca4643e017d572869c690a9d871c78075a6a71f80fb3e94f82ccd38974b6746f739e5c5cfb1cd7daaf9	159	\\x000000010000000193392d9dd28e9e4b417caa4e956ff966eca2fb24390c1f937f0d7ab3991967b14680f57b651c14c6e80e90ab884fd7e3c804a27b8017dfc2a1ac3e6acb5fa544f6c37368473e5dbed6a0cb1f04a55407733d5baa13ef6bcd08301935d0f6dd25429413cb3159e6df668ce229aa09d4b788e653d1c2173c054338ca44cc15f8f2	1	\\xd1138e1ab93c60f371f06ad851acfaba66dc0f183f676eb3c11bd5228d826b00620d5a3abfe1ecbfd12f28508f08726580ef25a090e00722c1c920b33cdc0000	1647492300000000	0	11000000
18	\\xf664556863fd4ea2c31bf9e387c96929eb4a5b5548ab92a3a561e9bcf7f6c6f38435b664b259768a13b11b54b1562a69af8379988979b8a04507c4ddb9e757a7	159	\\x000000010000000174e2d2896a8cb6b4f2f38abc7c1445cc1725de67b0b21c93842081c0bf9a1759e9d58c2489c5ccf30e70f75955d7130bd007ebcbecc4b31924a815ad11246126ce8a954a586f0310ab30ef9f1e30905e70cf933e4e9f414b4ff13b5c5e132d4c7ce8695a43bdbd2d082915c0683f41c7e61509acbc8331df57344951bb37dfc5	1	\\xfb41d806b81e17787c82332908578cd65c98917b9b03613b7745c959d196ca5da7a8e2531f1f80e2114372727abdadf610b03ceab75eeb5c8ba242210500080d	1647492300000000	0	11000000
19	\\xd0f2cc30239b3734acf12946db0646dfef43b8ca21e460bb73d909667bdcdc7fd2aec9f4bce4429a6ca19c45be9f78baaf19f1ccf2e68d3547a09aa46877affb	159	\\x000000010000000149e8d658103beb2a019998b3a046341f58a99039389aded80683de88021db87e0eb0c599447e3483c68101ca824710bb19d7c1404e24425f0199d8da4cf61937b7e92061061a9c38b75000b9790897fbcae747c02beb94cfd64b3f625cf915ab03b3585f013c99e9775b3873dc97e56ba2bcf45e83b2e4ee1ee880cf223f01ba	1	\\xdb6502b1fd1ffb63f4a498eca9c69d1475e001c7f7c8dcd32652f6673ab163e23cc865e471ce04c13d9da1cccfa205c6dd3a791b47326e23a52b9fd447402301	1647492300000000	0	11000000
20	\\xe8654481b508c9489fe55c868a6b886d7be72c9c8e6a712d34896fe0d74b71db651a2c7c7e1c27a11c56c603b529477aa68759231e9f63ba942a9f476dbf6a6d	159	\\x00000001000000014dfce84d8ae158039ba13fab64128343cfec298326614f8f3e550e84dc44436493759a575b3ed4261a790e2a103f1ac58a0066bbbd9fa47f8af67b56e43e27fce0fd90aae5e6ff5ab8bdbfd5a360d31d381a0375efabf6dc71ba71553202613c8b51eec85a9ea7d9e3c2d0114445eebb2703eb6eb985f8204ca877a0dc02e848	1	\\xb5e2b0c9ed6b88b847fd38065aae786c60d54f9049590f7651d092d9a2c32df26c2792c5757920978a3a029790708d4ebdc8c0e6ad6be512a49ec9038b9c0b08	1647492300000000	0	11000000
21	\\x97e3573b0ede6cd0f1820a9b16b6f4609c2c78ea0b09f6b808fef6873bcd0c4b0f409a3444487516846b21c676966d5fd24e975cdb32c16ed709ac6b120e2935	159	\\x0000000100000001d489a1b3ae26bdd4026c6e0296ded5ea49441669c451fb68d139bd6600a153d6b0ef2976770f4d8693e0c66450d25e3309fc18b7fe0eb0544114c89711f237842f0557e8974933b2dfd24d5bee71fc726e5b751915dc096360460cd03b76e44877b7699bf5caaf17c3a1b6e6ff0cce52c0f61b4dc7efc47a0c4d345babfa79b2	1	\\xefd39455da88e66067585a7ae97a27c0d17036b0dd81aa34bb9165e1524b788ad2d59ab1713575ea0a466aaa4cf156afbddd68638fd1b2d592611f756a6eaf05	1647492301000000	0	11000000
22	\\x773d3ad0079c78ffd2887d0f0eda31dc845f231c80fcf479484f1b6fb08462a7f826b81d63f11bf3983451c76b2e34bc3938ed3cc85849420bb81be518c37be4	159	\\x0000000100000001919f06597a7d9116094828a3fb1e92a2867e0162ec12ff807d3e62e2a9a646e170ed325bd587972f45dfd437bc5e1fca314801ca1f4cef46db8c5560cc54f24ef9db4a5fe693cb8e059712052b9ab4ff97ea45029a5b52ad27ff6c43ad90d8dc483609d695d9ae2fad8b941262feb04394a5555d13edf3c9573565a1b7027f69	1	\\x070b56fe7300ef6b1e4844a02ef151ee45ae568f28f239e5fe0864cf58453a186f0b3bb80aa73b36055134c17234284315d2006e9048aee17f07d63e9ea3530f	1647492301000000	0	11000000
23	\\x981871572948b6cac631096e7ca2774650730753c1a4d9763a2bd951b89b4370c82f6bee7b6f48cb6d04d0e7ebfb9bcb05967e5460e75ed2328cc65f3924e39b	159	\\x0000000100000001121a4744f0a8f705ac551c4ff4c8b55e7d77313015b18c6294f36215e61c28c3cf8df4b9ff329d388ce9058652146b2d549313ad79270778c4db631568dd40f4d8e12cfd0107fe4c85c4f04425f14fd023ed20ede29dcd8285da4afb47d07a2c1e78bc89719df7ed87f0d5417bbc7830f56d6fee69b1f085d105a501aeba67a9	1	\\xa030c3a1c78e2381c9becc57b439c2bf72c3ca291b8fd8625056468e6b10b9112e63796ee264b426f4f90be36156c450059168881b8864efdf6d64642cf0e907	1647492301000000	0	11000000
24	\\x525d42befb4d9a07b40f11f53e8248be5eb7f067fcd0806112468dc069c89bff88bb34089e41e3851020e5a3b81740e67a8b70ad7a93e88f788fb62f1ee662de	243	\\x000000010000000182baf0544e048b34b17e79d80697faa522ed6cc126310661c876a7b5fe79fde562fd3ce0fd69db67048748d833c59680a04daf48ef29eadc89a49fd12da689f6e0aeaa0dda7d90ad82566bede41c1abd7db61eb78880e7c76e383c6c81ed6cd42e2b17171372355e8bc46a7683b121a799722a8661fa0bf49586cf1511f9e73d	1	\\xb3d87727ad2db00376735ce3882ebeccfde2951635d111c0fd6fe783a17a506e498df1bd7ee3cb30ac0d7411a6ef8d7cb553277c3f6f1bc65a6ec03ae2551d0e	1647492301000000	0	2000000
25	\\x77b33ba2e1056ce2205a8578634f78d5f96ed1c13381df83b4fdf8f0a8e97f5ddaba68f02c885c572884189be8ea621cd16d8e44187970f6771a319eb69dc6df	243	\\x000000010000000110b1bb6eb4167d7b1aa1d67fbc29c3ae9acf716b86eb2b09b25efc56a68c569eb7b44e36e057160117171e379bd52b9a7454b27e7c6aaac8d003f8eb7ea123144144d8a5a82df22a040e8252649043b180f69bc29cbfbd0e8f95978009289ef3f91bfd64011f201810096c9e701c92d71017a5ed3fb279dcc3a35510855c70c4	1	\\x1f80a99f05cf41ed8ef806d29f1fe4d541d0d4ff86f40cfe457c16788437d1b52ebe9b38818415f5e91f7ba2e40be79f9cf4437b26493cf0fcf8ace5be351f08	1647492301000000	0	2000000
26	\\x3c7acb968a954ba59ebc98da18e3a9d8a16b97cf35eb83f4d99edd872d6922b699952ef194951a9bf091477e66c8f962924bfba1a8c5ed16cc00a909b8bcd66e	243	\\x0000000100000001389988b6b031aa2fff75b9032de8730d4b23b8f06b82067bd245b200a0221a7fdcdbbf71c6561d74d3d277a7bae2214e65afd235cafdc981b061c9cf38e162c69cc12db27182a829f505aa381f341489242a651e0cc05a2111d8efa6ddbd6f3d543952c778caaeb4635ad974ad4949c535e696e41fa1466c70e7fdd55ed7770c	1	\\xadb86fd53a48b2631e15843440c17477d793ddb9bc7a00e0d19d8ca11b006f013da916b8816e6d76725cbea0dc8377ade500be7042eb204fb124758523ac8d05	1647492301000000	0	2000000
27	\\x59085b0b7e0a16739d11a0e042e8020b4192553d78f5dc45fd53d5afe3f80671b0b58041557a17308739249ad7ec10be01fb6de26f2a4160a592d12c18d7dbb0	243	\\x000000010000000166e604778c124b8ac0e91bfb3c367c35bc7f463295cd332f0f33ba2329c5325629015be5070a64f531af1430be3201807ea37b517be5284f2a41d57f9174625cb62d59c0cb313fd42c5ce1551601711e10d486917aa7fcf2b05565e60768e21fab2cca16f826601e2e17a06c43b547ecff3890f1924bb3ef357004539fad2750	1	\\xb750524e1a09525a5f37bdca8e3065503d755b4af56c46dc9aa31185620d294de82909541bb213a2db9138e2c2144c14fe2ff64b056f5d92e7df386f3bbd100b	1647492301000000	0	2000000
28	\\x0a6f040faad0805b2afa0516c63b5c110187518533b933a9ac0d7bddea6e38cc5f495d52b36dd6185e0388a38e8ebed99e7538b84f6256ccc4c5c8f20fd95bc4	243	\\x000000010000000195df8ecfb2e45c604e5eb527aa1f04287fc3538413d79c43b4fbed4559e706a21fdd4ee0933b881ab277c05a71308b2f63f120499396c14200239917e436d2836894cd33f17c117d9f45169e342a090c6b7f5974df4165f4da4df7aaba75a4648a9f542602bbfd4d4b01e198c5e68d0aa6c6cc2ba6b15fd8e41456e7dfeb6ac5	1	\\xec2d7aa040668b4d9f5cb589db413ca6b1d057b3c86279ccd3fc1acabd17c8f533e56c901b11b47a7d56f60e14ef0316c3d10125ba89824b9672f69a84bd5005	1647492301000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x412b779be2f7b2df4f489221884287db260f1f7a75d0470a4c0237564ddd863fe9a7f90dbe169380e34a87afd0ac82dba6da14f2dff1df368b998fb6f3abfb0b	t	1647492279000000
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
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	0	1000000	\\xd4bda7e86a2b500df5398cd4868870ec82be79c137221c3c48af8fc8951c2ad33dd2dd0adb3e542ed767edf639c5d15c8720e4ea286ff8bb050c3d7165ec9609
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
1	\\x381a99fa9c05f43553706af4d8970a4ed5b6423e64677b7e827bc68baa4b79f2	payto://x-taler-bank/localhost/testuser-4pdg1s6n	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660c	payto://x-taler-bank/localhost/43	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1647492272000000	0	1024	f	wirewatch-exchange-account-1
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

