--
-- PostgreSQL database dump
--

-- Dumped from database version 13.5 (Debian 13.5-0+deb11u1)
-- Dumped by pg_dump version 13.5 (Debian 13.5-0+deb11u1)

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
  (h_payto
  ,payto_uri)
  VALUES
  (in_h_payto
  ,in_receiver_wire_account)
ON CONFLICT DO NOTHING -- for CONFLICT ON (h_payto)
  RETURNING wire_target_serial_id INTO wtsi;

IF NOT FOUND
THEN
  SELECT wire_target_serial_id
  INTO wtsi
  FROM wire_targets
  WHERE h_payto=in_h_payto;
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
  ,wire_target_serial_id
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
  ,wtsi
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
--         wire_targets by wire_target_serial_id

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
  ,wire_source_serial_id
  INTO
   kycok
  ,account_uuid
  FROM reserves_in
  JOIN wire_targets ON (wire_source_serial_id = wire_target_serial_id)
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
    wire_target_serial_id bigint NOT NULL,
    tiny boolean DEFAULT false NOT NULL,
    done boolean DEFAULT false NOT NULL,
    extension_blocked boolean DEFAULT false NOT NULL,
    extension_details_serial_id bigint,
    CONSTRAINT deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT deposits_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT deposits_wire_salt_check CHECK ((length(wire_salt) = 16))
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
-- Name: COLUMN deposits.wire_target_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.deposits.wire_target_serial_id IS 'Identifies the target bank account and KYC status';


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
    wire_target_serial_id bigint NOT NULL,
    tiny boolean DEFAULT false NOT NULL,
    done boolean DEFAULT false NOT NULL,
    extension_blocked boolean DEFAULT false NOT NULL,
    extension_details_serial_id bigint,
    CONSTRAINT deposits_coin_sig_check CHECK ((length(coin_sig) = 64)),
    CONSTRAINT deposits_h_contract_terms_check CHECK ((length(h_contract_terms) = 64)),
    CONSTRAINT deposits_merchant_pub_check CHECK ((length(merchant_pub) = 32)),
    CONSTRAINT deposits_wire_salt_check CHECK ((length(wire_salt) = 16))
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
    auth_hash bytea,
    auth_salt bytea,
    CONSTRAINT merchant_instances_auth_hash_check CHECK ((length(auth_hash) = 64)),
    CONSTRAINT merchant_instances_auth_salt_check CHECK ((length(auth_salt) = 32)),
    CONSTRAINT merchant_instances_merchant_pub_check CHECK ((length(merchant_pub) = 32))
);


--
-- Name: TABLE merchant_instances; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_instances IS 'all the instances supported by this backend';


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
-- Name: COLUMN merchant_instances.auth_hash; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.auth_hash IS 'hash used for merchant back office Authorization, NULL for no check';


--
-- Name: COLUMN merchant_instances.auth_salt; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.merchant_instances.auth_salt IS 'salt to use when hashing Authorization header before comparing with auth_hash';


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
    execution_time bigint NOT NULL,
    exchange_sig bytea NOT NULL,
    credit_amount_val bigint NOT NULL,
    credit_amount_frac integer NOT NULL,
    CONSTRAINT merchant_transfer_signatures_exchange_sig_check CHECK ((length(exchange_sig) = 64))
);


--
-- Name: TABLE merchant_transfer_signatures; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.merchant_transfer_signatures IS 'table represents the main information returned from the /transfer request to the exchange.';


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

COMMENT ON COLUMN public.merchant_transfers.credit_amount_val IS 'actual value of the (aggregated) wire transfer, excluding the wire fee, according to the exchange';


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
    wire_target_serial_id bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
    CONSTRAINT reserves_close_wtid_check CHECK ((length(wtid) = 32))
)
PARTITION BY HASH (reserve_pub);


--
-- Name: TABLE reserves_close; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.reserves_close IS 'wire transfers executed by the reserve to close reserves';


--
-- Name: COLUMN reserves_close.wire_target_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_close.wire_target_serial_id IS 'Identifies the credited bank account (and KYC status). Note that closing does not depend on KYC.';


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
    wire_target_serial_id bigint NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    closing_fee_val bigint NOT NULL,
    closing_fee_frac integer NOT NULL,
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
    wire_source_serial_id bigint NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL
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
-- Name: COLUMN reserves_in.wire_source_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reserves_in.wire_source_serial_id IS 'Identifies the debited bank account and KYC status';


--
-- Name: reserves_in_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reserves_in_default (
    reserve_in_serial_id bigint NOT NULL,
    reserve_pub bytea NOT NULL,
    wire_reference bigint NOT NULL,
    credit_val bigint NOT NULL,
    credit_frac integer NOT NULL,
    wire_source_serial_id bigint NOT NULL,
    exchange_account_section text NOT NULL,
    execution_date bigint NOT NULL
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
    wire_target_serial_id bigint NOT NULL,
    exchange_account_section text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
    CONSTRAINT wire_out_wtid_raw_check CHECK ((length(wtid_raw) = 32))
)
PARTITION BY HASH (wtid_raw);


--
-- Name: TABLE wire_out; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_out IS 'wire transfers the exchange has executed';


--
-- Name: COLUMN wire_out.wire_target_serial_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_out.wire_target_serial_id IS 'Identifies the credited bank account and KYC status';


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
    wire_target_serial_id bigint NOT NULL,
    exchange_account_section text NOT NULL,
    amount_val bigint NOT NULL,
    amount_frac integer NOT NULL,
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
    h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
    CONSTRAINT wire_targets_h_payto_check CHECK ((length(h_payto) = 64))
)
PARTITION BY HASH (h_payto);


--
-- Name: TABLE wire_targets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.wire_targets IS 'All senders and recipients of money via the exchange';


--
-- Name: COLUMN wire_targets.h_payto; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.wire_targets.h_payto IS 'Unsalted hash of payto_uri';


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
    h_payto bytea NOT NULL,
    payto_uri character varying NOT NULL,
    kyc_ok boolean DEFAULT false NOT NULL,
    external_id character varying,
    CONSTRAINT wire_targets_h_payto_check CHECK ((length(h_payto) = 64))
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
exchange-0001	2022-02-28 11:06:49.525645+01	grothoff	{}	{}
merchant-0001	2022-02-28 11:06:49.708094+01	grothoff	{}	{}
merchant-0002	2022-02-28 11:06:49.822778+01	grothoff	{}	{}
merchant-0003	2022-02-28 11:06:49.866841+01	grothoff	{}	{}
auditor-0001	2022-02-28 11:06:49.930487+01	grothoff	{}	{}
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
1	TESTKUDOS:100	Joining bonus	2022-02-28 11:06:58.059401+01	f	0085091b-7342-4165-bc70-f21804f2b8f8	12	1
2	TESTKUDOS:10	6FG77MNNDJQ3K29DTRSA74TVEK8RVET1J4Q4KK5Q8A0PJKD3T6S0	2022-02-28 11:07:01.459596+01	f	16bf1796-f78a-4121-a867-cf5c3a601ff1	2	12
3	TESTKUDOS:100	Joining bonus	2022-02-28 11:07:08.435485+01	f	5344e52d-53b3-40ec-bddd-ed668ba34aed	13	1
4	TESTKUDOS:18	BQJBEF0A5SV076G6P29K2FBG3QB8XR47R2EHXX4M6Z7X9A1V6GHG	2022-02-28 11:07:08.996924+01	f	3eeec308-b38d-4840-bdc8-a9d1d533d5b9	2	13
\.


--
-- Data for Name: app_talerwithdrawoperation; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.app_talerwithdrawoperation (withdraw_id, amount, selection_done, confirmation_done, aborted, selected_reserve_pub, selected_exchange_account_id, withdraw_account_id) FROM stdin;
7ffbddb3-faf8-4718-8a5f-c65e58945dfd	TESTKUDOS:10	t	t	f	6FG77MNNDJQ3K29DTRSA74TVEK8RVET1J4Q4KK5Q8A0PJKD3T6S0	2	12
1ed51e6c-5424-42b1-8c23-0b0d7568292a	TESTKUDOS:18	t	t	f	BQJBEF0A5SV076G6P29K2FBG3QB8XR47R2EHXX4M6Z7X9A1V6GHG	2	13
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
1	1	176	\\x923a6d8617c9e87831675415ef2f2b45f3ad479f3263f5427b1255401fd8b1f8102f8a1f898612db75b4810c600715a2fa342f4b742eee6d47d3779972f59607
2	1	405	\\xf1c9c050db3eb524d1fa74b84b0c7e08c95a64cc4d7ec080a3027ca3f7752617fdb08c846645bc0073cc3f5ebdea268442c1741e652b9f19cba80fdaeb3f7101
3	1	215	\\x15f5a953a93a1a433687c9fa9c9d6beec64dcd17c264d4facd9a2ac2eba66c947888b3033795d9e2c451555582629fe675e0f4526021f4558a51bef2fe29a108
4	1	307	\\xf5e0482d5c58c17379bc627700b3473acb3fe1bbdcc62d2f23cf286c947820d4b0205e178f215bc1ba669eb86443d79fdee1995a695e2ce9360876afef20ba0f
5	1	332	\\xc25a5e64042f221a3b4eca49bf83690d1bf4df2dda03583983e2a6da4bc20f74a58db1995c45814819ecbd0e50a195ffba053198a0209a5f3665bf4bfeece40c
6	1	337	\\x11c68cce02f7ec717b5e1c18e0afb61a795c8f58ec4348a6baf60674f7dfb6fd3468acb13ebb5bd2883c3b0caaa26e4b750236363acaaac1205c6cfb4838930d
7	1	352	\\x71db4fa198c966e76f71d6e574667bca0e6d4f4fec07608cc8541f861cf18babb94061c1859ec0919cd8a46820883c96ca45f1631313508f6bb0588454eede09
8	1	416	\\x17d46c2bba8c1542e5e8e8546982608287eb30f55620a04568cdfe4d8bd45833b0c64c3a464362e0e5ec881f9dfffb8d6723536fa989a48c674f8203b5b6e50c
9	1	404	\\x782a9fcbe0df23e33997abaaf1401acf073ea802dc0d4a4c84a8131f94e1c567482289526c32c2e0255e6c7b4aa1e75c67a546c1d2935ab79837ea41708f620d
10	1	95	\\x33af51e4c3c5d7c4ef3a8f431daf888564e84943ddec10669826bee941837d3fdb09a4b9396d6aa2c9cd689de62d406a0e99fd621a777d952f6787f1f87d800d
11	1	126	\\xdee10dc144c98d0d2f0ba90ecf2e5fe053d17eb7c2b716c53d18ee10448da24bed12777a885969ad4913f5ca610da5c3eba5b7e907ddc55e00de7a3d5eb5440c
12	1	220	\\xddcd64e43ab58c4d387af0abc635b0340b7464b4705007cb76530e465b6911de96ce9f578632fd74f9c5d2d2d11c1eb397fa8f7a1e823104bbee9986b352ff05
13	1	194	\\xc85ee8d7829e1b3c7296a26ef5df382789173c94d2f0c77411c639b1c752f53caaa22354250fe5ed114aaa16e3c58e5658f6a0e9415d2a4205861d4818c1ce05
14	1	214	\\xa3b451e9f80594f34cd9cdc748a4864912de37d34c0768af1e268a5aa78f81aa97b861623a2a65c5f63f67e0fc5969c1f2720ed556efdc14dd651fa9856d3902
15	1	305	\\x10e6c7d28780e66ce710e44b483a17d66618fea61991b8fe18d97affd759d9b27fae624eace68d03adfa5a787d85f3796b75e3598861c5b4d819826cc6979001
16	1	397	\\xe141d753ba9424967718369118d2fb3d1a16c503f9cd55a06efe6686129fae0e4813d4afdb25ff1a34ff9627ff50f5c316d897428db4674475a007debd846808
17	1	138	\\x6cc923cf91c2d9b87360d6a73197860859eb75efc2187ce96ee174933d9907596d580b856262f4e949e5a961144b5ac67a6fccac2398d76134a4dc5865836205
18	1	178	\\xb8a7dc28ded8c35323f10fc81f37a80481b44bdba54d24a406731657ddad8cb26484a19bd482f766bd90e153c4bdac03d2e9a71c7cef8241f32492a29a27f304
19	1	199	\\x574b1e5708fcc01464f869cd3fe0866050757e73594518d26712a824904ef5957969ae2038049211bbe902adf4920312c8011dd4dd69f3ffa0cbf3a336568f0a
20	1	188	\\xd0f8e7ecb36032312920f019a8de92f221078bdbaa957cd03b6d1622281387a82f8f964927231134b9e2fbf065ef3b33eb6d9c0c413921f0de3d52110fa38601
21	1	258	\\xfa981500efd496853cec166997487fd7c193089a6ae930f8c98c9468b7fac398762f9e3bb96e6023689b7576d8cb19da81c0957c13ccfb4173f9bb27a3f7aa0a
22	1	306	\\x8c4fd4e0c76912ef5392e45cc4e47117e90971ba972d404f9339bc0af9f2dcc2a3072858e842b655783ba475710ab818e0ebb35f97c4004330dbad6950be0604
23	1	42	\\xe2eb5b3fbf38497742aa18ace44aedcbda4a0c2fddd706867d76fc47eb337bf2f16d55787858ab264b1d752447a3d6dc64843f876d74989d3ccdd4ff7ba50d0f
24	1	379	\\x0ef27c19e5e0583567e4a91b58262de3141c7d9d44ed6dfa2b4c57a22e52c79e270f20a8dfd638e014e5546bbe97289bb1fb8ce6e0b20ec7792d4dbdee16cb08
25	1	46	\\x73823343025c84236fe3a001353718ea811bbf6de3001eb5756284cb0a06df10e67ddaca63b7d20c385830bfbfccc8f1c0839cf3b781ca45182f37bab512d105
26	1	72	\\x36214b68743b1d5f9355ae28fb52d6d41c9e6f96278ca1803f238e089b079a1167012609d2a9eeddd32d4c6af070aef5f21aa8c0332225a9ff1a7863f2f26900
27	1	119	\\xb1432c9cf05f77ea5196402593cac72799f8a9723dbbff0938ba721a7ff93fad8e4dde74807b987c69cef39b3163d96ee6f34cec9421893cc34442f05d31ce0f
28	1	381	\\xfc7b4c2fc87ca2badb67e708b947cab26e734747b6bf60ca193de842a30c013e9a9584acb15a013c415b7f295d6abf13ff4c1f0ca5cb444f1baa669720a42907
29	1	32	\\xc1a4fd91c18fef22cdd449c2d2fcee51ec1f1d7202db385734cdcad25a12a84bddb82356ecebec8886bdb5ac038bb1021145f320f7ae86ff4460e910d64b730c
30	1	277	\\xbfcf74f7370367e959a81d6a2c6a5d6f18a181eef1bbff00f35c6267b3165a2ab459ed6879a42e9beae8bbe4dc64b8e6a8d1791da94ad7aba3e606eb06973403
31	1	422	\\x600ba71da43dab23a52ec2bda50b3374a6cccadcc06101cc1434b09288437eef0082d6abf0302ebb881a09c204aa107253e0f49cbb980a38fe68132df405a60f
32	1	222	\\xb0cd5cf827dfbc7cc54fa07f29112a3aeb2c7f1ec18a452252cbecec0c64fd43a76ccf193576884a7260c00850fb9211a90a0591aff58b509b162d46952e8403
33	1	130	\\xa5678262487bb8d3b1d343f5735eec47237ca75d02cf48380d10b02b1ee8bf451517ef3c501c27a8835b3c8bf68c6420352295f1344e6801d01ccce0d23dd80e
34	1	37	\\xac18f44db409143ceb2255e95c0fbceb1df6d495afc108862d1fd8d0e1290e61406468ede1ea5a2929b4d170f3c76abbedd083ff973bf2022d970aceb7eb2007
35	1	43	\\xb7bc8ae3bd90f964428c928753af6116312fbbcc63191d8b5c45d5814417b46b2187f5d32bb7e5dab6cb8fde65c1c97bdc80cd355238d873473e95dfabaa4a04
36	1	293	\\x2fe67651b76dbcad595a25f39747a29c54b2a55fdfdc38b8bd8e18725726484db95c9372f5707c4002d0f96e47dedb6d3fc2cc49bc0415e84c55f33902758203
37	1	127	\\x2b88d60700f6ee88b836a274ad1b66be1eb214ba5d2d90f44fb3864619992d8cb43242841f46a0d73062b02d42ba0c09a6dee6c9244965cc78161bebd65ec20f
38	1	259	\\x2965661c677f9f6e7caf75babf62485968307055cc2adb041b9405c38c59bb0aaf5f9748ce7d153644a38f69429cb0cac87b0d5ff0527e0b59913dc3c48f8f0f
39	1	23	\\xa88608de92567ebb846b2a8e8ecedca3e5b801586ad2eefd788de40d8159efc7f924d022fa5a6f4b690a44d81e7ad734bc1f83924ec9dbce8138997a12b3970f
40	1	94	\\xa5d9bae04094cdec378a5361879c3fa8acd3c3986af9b5eabe38c38183d5029794d33d969f04476fdaa660253685ebba935c31128b9798f02c47cb1a06aba908
41	1	104	\\xcd34f2a7559c4041736a6488c3dc3a6e2b9eb2fb943392e4a643200e42eb9503a06d742ca8b7a28d2796ca75b8bb3ba8c3e3855368bd877fba991500c611ee06
42	1	167	\\x396f5fb888f908a9dc0054a9c5591eb7e165f5d9aaf6f3bd609bd85ed0f1657f64ede26b9912e2d0290a63736f2d4f78158b1ee8888054780bc687684ce6a90b
43	1	36	\\xbdaddc006bfe900f50947bac583fc045bd39c0b3ec9e6f398f8cdf1e843cf09552a154f8a2cc87853a5e871f71e157a522b4403f762cd10f83eb283f25fb1c0a
44	1	266	\\x3940ff929b70e6de9dcc2ea99e5d94f9616ea8fdd247df33d03399eb1bc584b525ba87330e9fa26efcd642ac58a8346b5afece69d5da3c3d102859356f741404
45	1	321	\\xc5e858ce09c68e9ad38a2f123a054475e02b1c7a0b20ab53133f25bc886455efad43209417a06fff08e0d4e30017cee8eb66f83ab4fc8815d730649ff432f108
46	1	421	\\x909beb6955f19459abcfee3a1028bf3474cdfe905451039c0311321d4b4900e35b977c1b3b3bf1732a15943bb68c2978b580455a137d9a66578357720283250e
47	1	201	\\xc126a7b57c546102265212719d52bb8b6a08182bf5e36c3a15512133780a9df31f13a7b8e40ef4e83f1d74f9db1abd57922a4a35b9253c853874df25d6cf7c04
48	1	183	\\x64b3603d3b6aed89b2fe99e22247ce046d14de21f2203d9146980d1d42435a7353762d6de0c8bf190de2175573a28134ad87b55957190e58e820efd446eb1800
49	1	88	\\x3b0350db0b85519ae5884bc9b28f3cb44e8494861a1ad20e04e86ccc7b8985bc412c96605187d7845e7cc2b6caa6753b2806cf403d0bd56d654dfd857bfbe30b
50	1	118	\\x349fdd2939483016d3b3409d2786c398901007be345762af959e9a90329aeb1ff25fbe60d0e8f35befd22bab1d9231ee6dbdafda6aaa78b025c7371e7e50440f
51	1	52	\\x7791f410a912ce4b4dd26c99d02ece7e8256512b644762fc48c935bf6225835d9064c77c0d84ec2b50949c83a91081f29fde99f532184e2b468fe69e98078401
52	1	375	\\x7e487d9054791a86c73260d3375925a7bcd9770457da7dd7cb2c3df202f15073f6adff8b324405dbbb922ee82f5d518dd9e683d3766a82cf6579c5b2d3334b0b
53	1	64	\\x02a6652dafe1bbb28029350011bd41b974cd038d94b03210a70e1df714fbe5cdae6cd84e0bdfb56bd59aa3f0b1c168a0544a51b4a456444a9b441768d49b450b
54	1	348	\\x318b504934ef508dd272d9208e12c0fb4fc81d6e856094d481fd51db84bcf779fde68a52bf96c04341fe19241cdd380c85eb83ddfea73f74a57dbf8e137a0e04
55	1	59	\\x00344a241858ac82b9fa15e5e95f76b20981de4c2e5b713bd0f9f1235c845ae1b37c1003ea12b681a5826382917fb0bb42130bfd38e1b5bc10a81b76b17b8c02
56	1	331	\\xfb3e5d5a98a2a04c5cf149d77c2b7c0cfe18686acbc3c47fad0a526730797cc73105b953e6edf6b87a78cae3e76cb90e3f29121dc7ab2d6378f329c47150f10e
57	1	76	\\x89740cc0c5cd0c1383e8b4c8c92c8170e7e03335d463801c802511ecdd52b8fc2860ad64acc224f5a09569afc95d23831ae5b4f4a291e6bedfd66e311bf3db06
58	1	191	\\xa15ad37f36394f1c06aacc6b791491eb89ac7cc13f9ed389b93796f1e5a0f8f147bb484f65bb865b99d715391c59ffb04e78dfead25bea787a35147d31ccbb09
59	1	77	\\xc441a14961b343fe8a13ee31e4e7642ac134ee745bcd669b0545537ff56fc7520198bbd5f8757c4bd993c96fa9c5d346422aceae886abde92badedca4df1150f
60	1	218	\\x6851567e74481496c50261ba2efd72143f9c7d1e4be6d3d0ac7957183267d33de501981428448dabb49dca18a9d3eaf97ac66eb8c6316903c710be93320c3400
61	1	108	\\xe4fb4c90111dde8d046c20f4e9db5ac8a1d504764a4f0a2d0affe014399bfce04a1122ee166d5b0cf6b8e4d1984f6cb7e9f0d76365d93a222452757ad7b05804
62	1	406	\\x5ae3876a95705e5c801f1548e4643743d0fd06cc09f7adb11949169df4985457bfd7b63fa0a983851cad0187489c1d5a61ca00de8b66b71af69b8b8a4f8b160e
63	1	16	\\xf92908eaa077632bcd3c2c3a34d8c6c6e9b9f3c7e014ebee87cda47723a56d33b9330e37a298d9db42a65530fda67a8c2dcfda7e417caf3ce7c5db582fdcfa03
64	1	411	\\xca0a0517482210121c521f2e9ddaebf0aa10cdee0cc38481bc7b1c19d33bc5092d3aa3fd2ddbe1b20560305fd0cb0d8f89ef7a258f12890b7e1c703bf9021d02
65	1	287	\\x68049293b4adab8cb705103de0cc9da337e985675b5d64440e4400535f062678bd04a90d4b504895772e27251045f5ea6e6184bc87dcd9b85fd73c0351eccd09
66	1	410	\\x976bef9e6854c99a0d9bfc7b1203be31388fad1437d98cfc5f40bdb97af9b687ebdc251943b8813bef720dd32f973054d3f404a4df3bcaab5138baecf2e55705
67	1	338	\\x91d0c48b9e46a0fc0751fe174a576f6b9dc9b839b20cc1d44c556e47b4dc052153ca7e3e48bac00a0103aa66363745fd1865f379fdbae21f7b75217490e6d30f
68	1	219	\\x418032809636caee027f276035e1c2c208b09aa86db6999286abf899155da2a3419e5e98147384408a516b1237689b4c92c6203d19d9a2baba644ae45cfbfd04
69	1	342	\\xb9e35127b1e1bc619dc63c6d900714e5efcd1d82a8979d7557c441d20ff0553907b6d445482f7ee250021e012f71596cdf0351e009f376ce7fcca882c6678f05
70	1	67	\\xb6f8138d0d443a64330d7c9617ef6d9c9597b3865665f56d0506c97e86284c4a8f9a57e3b9d662082605cc071bf5a68406694da7793f24ba577dbb0d29eb0e01
71	1	253	\\x2348b18651c914ff03d79615a0547f7c6e715fb511a36e7814500aa8004003f1e7f03cd614d5dea9ceb6f2159b05a932a981c10fc72a33c3d2c71c4466962f02
72	1	84	\\x268fbe0b425ffbea818a9c8e8f9831061f28e0299f17ed204cf454f38c9d4621a5294e8da40886737b4a668f39f7e9991529ef64e6edc407784251c4d8ee230c
73	1	238	\\x049893e6525eb9faaefe7f7821b3b4d3297bf598e67505ee806f306768e7d4cb13452a3a9ab1be62a1afb29d41fb9f5f88d50addff3aeb854f83141b1b31f306
74	1	63	\\x11987a602eeeb76753da6b9d1a4ab84b60f404defb8e5f7b36a52c9599c17ef84d83363c16caad7cabd542a1a0070a7bafbfe47a9d02ee26614f842345e58d05
75	1	383	\\x6e3a299e8c88de85017470d7400f7d00bae645f2a3d25fd09e711f730a8368af80b34c980b72f5d290c8b5145c18ed795cdb2295ad458772b67f5fb3edfa3002
76	1	75	\\xcd7468308c68c20dcd651f419751921c29df2c58f85d87269ce4750b68ff6be09e733c47bc1261850935d169d3d71a7efc00d8403831e95c2c018e68cd8af105
77	1	418	\\x01f02d2ce3efa91092768adbd1f6cc35fceec802c6d4ab27fa34bb5e87b364b2157c989ecb2de0839318b9f6547cefa69206a37f6f71e153016e1fa96b0a560a
78	1	40	\\x28c80a77ed07c95a27a91ac4789befd70add6f448f6ab808491fb5340b85efbb9c2dba24ac41ffc80862a963c3c09fccd491da79870036563c818f00820d050f
79	1	271	\\x3f54f9c54760ab3c8086e5764811b8b2c8169454742af15912ae1bb691c40e796f583275b1a7c40359e2c51a819e686dc928d96b7404d9527f3327ade235c608
80	1	396	\\x718bd1c1a700725de1c36603920ef5820729e3013ff6745d948ac765e55a20b1f07a6967db5405b9963a3421f66974253741945c2029cd8448fd6cdaa5a5990c
81	1	19	\\x619691f2312bed79eb65f1fd92a55de1a4a6424b55d2f9cd7a6b53d2d47afdad34dce97ffd989f7daaa8683ebe84a71f9e462287334f82d63541b84b2e305e0a
82	1	386	\\x6751f0ce760ca7d8b752b4f07e465d183c983287a5cdcdcc38faacdb1a552bc77cf5584cfbc75a39646364b7d5fb5e0bbf0f2f7b4daa83c142c62bdf26444a0b
83	1	393	\\x853210f4d1762802b565b41c3193535514d2af5c951cfcc6d3527d31fbc7155be46934efa86239d55cdb4cc73fc0d9e709f7a2bb0f57e938646a3aff8f0c880b
84	1	4	\\x4cfee77696a4b6efe40f9d67eb3b625c089d112093aa521dbeb02130fde7db4fc151ab81d04db9a8ebe8b78fa8223a4ef1a46d9fc1ca3063cbe34d671e732700
85	1	283	\\x7763538673d102b0d71eed13d6e955133f24934c0827e1e16fbaf3069248bbe2e99002946ffa19eab6bf37706ac15e96270d7baf5af5f8e543be7dde9619800c
86	1	103	\\x6ece2081f1f854527977641ff2035dd5ce685e1216ef902079fedbfac17d6635ac56fec4e07d7dbfbae7d16ed07685c4d930f08b99d3ca919020b54bb1b0f40b
87	1	417	\\x674347926ad2a6a26efcbf771a2df4003310a334533a68825d2bcb94d943e37fa9d6071a89aca3479faa65b7e55b127ff5827ad22bef690585c77112e64c1904
88	1	203	\\x6a1471658a87edd8b7448b33589ed0939ec529a38240149fdb937dcd4f5ea4d131b72951795e356a3c4c16230c881b8de8cbd866a94bda653d6dbebc8e070907
89	1	400	\\x8c4a0b96eb799c891540e9a841947abd995a9d9a1772c355f9f9f4c9bc93c2a504316cf06478801fca5ea441c54613841a5628faa047f7fa76ea4874103a2908
90	1	333	\\xffc9994e0f0469828d8f1bdcaa10ea35f60f68da47fcb5a5f925644e313f06fb888cc5edad4cfaa878f663e7b8a827dea35da832c06107991539584214258c04
91	1	295	\\x0766fbdcb75405704088fdc7b02e007d34ad21ce289654a18a476a459c0b8e1ef60439a0b49be9265b178abb9bbe1662f8900bb9e494f6e082ec78539e0eb108
92	1	300	\\x6bb57fe48ec0bf2e41a34334c2d1d45339b3f0a799bdb9e882c2a4940be3cc9539a5f0ce9d163a0e8de5624452df6386770e8e853b7a7c63913570e716a60b00
93	1	244	\\xa45074d4a2920ff9432aa295de4f337befc50f9c6d5f3f853761c171c7ff93e83dc71b93757d8b4353f6783c37ef16e487feda611fa717999aaa6e08e43c0800
94	1	47	\\xaf13f35cfa314ed0c55ecf6f31e0864c8e5dd92a07af58bc9fd8aece4c5105fb76c9120d4cde9f70c075aba25b41ff27373d3af7139edaa8386c4ee361cbc60f
95	1	391	\\x2baccc098921acd7033a4764e6182ccbbe8088807a658ee27ebc13860eef84e638bda4ede6f0b21373d182a65f89e84cf4db2eb70679ad5ba05f39b32d5e2e02
96	1	275	\\x3aed09677cac11739f5ea03db1c3fad2b7e8f365e4a0a4e8de39f87da4fb593534df74d5c3c890c4d53d4cb3bc1299e10e0a9d1dfa6385f104af12558ae96809
97	1	251	\\x1cbd6ff7e491d8549cc1b0d300237f30626da8fbdf0cbad7b628f0aa75b3f54d6114018c74d73f1b4f35f9660a4a7069ba8057521bb8f6de730f343e21f48a0e
98	1	230	\\xbb3736e0ef1fd2d1ea2afa99531d0d760ee0a17dfafd426799f16b9e40a8966aaeb5fa59bc8c00a097b81d3e547a8a5dcae4619232f281d677c9713a35b3fa01
99	1	329	\\x483894134d109bda7c91289f0479787648820b8af9a71abb620f3f20fd53c1ba7213630a16b06c4d983d309d9e9ca1b1ee342f82cb3341946ee84c8196466408
100	1	297	\\xeaca7dcaba6436863ea87d9a39fc363aefcab538f7f016257b21a875eca3cd9d0ce0c64228902775d3bf506c950c3ec25a88906dffbd4f2e1215bacd95501f00
101	1	301	\\x156701cf9d511ec5c3b3931563dfa272177d288b36e076be611b70ebfdcf40ad71c99a9d201c386d7ec84e00aa42ad4b982a5d6ce99bbdcb29eea12229d3a30a
102	1	186	\\x6575dea138dda783aada73f3c5bb7636c3324f00e561edf9973e351160880886a573f35557f7b96127b92ece82cc87569513429cf5a7816c8848db814a882f05
103	1	392	\\x02ae6997ff0c8e1762416337e372f55f13a9e12cab4573e36d60f3e74932f7b616dbc214ff00889fb02c5b9d3e3b75ff8632333e0eea943bf51b47e6fcd67d03
104	1	66	\\x3a37f75387abccb461c6a7f31b2880ce4b93642f1d0fd3c1278300356439f21622d156765c15abad68558129944023159c2b44d05ac12e9a1158bd30d41f4f07
105	1	209	\\xcaf0eff2cf2b021ad1ef94108c1285481e3b8fa883064aac037db5cedbf4f8b357d2f42756c033517d9927be630f9d721fa07f69dcfce91b04f67318f13e9206
106	1	13	\\xb3b775269e605a7f06e5684dd5f322a064d72b24447856f5aa8a335f9e26a3d4e0a041c1843bdb86f12ad692d4c30c3c6dad5dcc76a30ea9f196e136fda5070a
107	1	216	\\x36550d46b1470d055d67d286b87a0d720dddde2b3f33740ff90a6032e8bf9989e5c36dbbd07626f26f6f3ff7b7297fde5720c4f27ecda5d8bc889ee0b7b9120b
108	1	125	\\x96279b477a130c35c1783ea7982c95b98a58d50c1e8534b569d099fb6360297d8ea4e566ad74a6bdc4bca5d6076fd886e28ff3cb05d164bfdbd15e0bd648b804
109	1	403	\\x2563c22559bd8b3188564ea2182a1efd147c3c1e09d4bbd8286c7035e3601fcd25b1ceedc3518fb15331cb7a92c9f3f7c9e5600f10db1bf2ddcbf9ea08cff904
110	1	211	\\xe4ce740e3c29cd5eed17e55ed875afd9e70df23a9e9dcc135339e048ed5a36195f74fbfb753eddc4a349c3308e2717164a36d2041290bc6d646fe83cd42e0f0d
111	1	143	\\x1d0261632ed7586ca2243cf6c5a0fffe4716ff68485c9daa4c1ede1f46296a227e96ba6cd11d5cf77922d7981313f58998df222eb739eee084222c1741a52204
112	1	179	\\xf01d563f552b0016f6a729207c1b4a1928cc7c053a2cd03ecbf1521e6c2d25c01819146ab3c0f014fbfe2f39cdd4a554afc41d34ac92ba8fe3ec1bc5e47cf60d
113	1	31	\\xbf9d2838eaec17486d1d5304803a3561f16130b1b0c1e27672b12076cd089e9cb69dd9af5493723956f11dbf72f0327eb609e7cceb35a027994e2ca782df000b
114	1	367	\\x6e1854f48d9e55c90e4b5ef00f549326f613cfd519db3caf58d1c490434672892b0fc641b20651a819e80ed088d34ffdbc07fbecbecf3252c5f93a78b2b23c0c
115	1	197	\\xaba66cea97dbc3c101f8bd23c5bf1b2ecdcf61c0df3ef0f10e70ee42ef0c9de8aefc07857fd719f936983ba1206941192c39d38e1c546c680b62d0dd0804ac07
116	1	269	\\x1655f4d40a3de1d3cf7e2af789870aa52cf897c95bdaa267cfd8f0bc8b05d1f333196992a4689312d8e0f69a2fdef02361f5b38dde5df201701830f986d1b302
117	1	424	\\xb795729c289b55b023ca40dda0b4bd24a479532ed564801d53597f684fa2beb53bd51d1e4e279694072db0ee16dc01ea0ede396bf89758e551a1b2994f31e408
118	1	279	\\x7079277b7609e02301eaa5ae851cec0c3b77fcb2b6fb24ece2eda33bca67f5e6d4707c8a9565e19452cfa175f730fc46989355188936e47722693f14d29a330d
119	1	190	\\xf81041ca36537bc9ba5a5306fb124c6dcc835cfc6599cc8dea24a6720edcccf08350db9f9e8c83110047951e04b8c886cd0ff5841fe02f60c0c1f5ecab3b4401
120	1	136	\\xccb6a859ba81a298d540df9784a4948dd4073a7c632d5fe58a3f764f379923740c2734cad2305c6f570fb73d054ed5ca94ea1299eabf5fc80817851e64ffa00d
121	1	92	\\xff37f31df54519ad779098193141607adfb55990e27e5083755cf611ba3bec54dd62c623acddf671799c07a19149b879c8df457584b4c1607df989531c0dc501
122	1	145	\\x552edf7678bc4d9056b9489bd26ae5d7631ee7f04f81af5d1a65d81811477b9406ec5b639b1425addcb9e780442332d2823bcf968d000132019f2b9f41136a05
123	1	223	\\x12ae961f1acb3a4e8b0ad270e6766f7bdf143cebe0691f30abd51f07b0648d43db139cf09fc9cb2b225c2aff3bf8fc9e2ad99fcf43de8fd4de063fd360ba3602
124	1	14	\\x9ad751dba49dd0b1c36585fc035a6f1fc61aad21f293588d043d7dcd42ab1009b4018b82709a709daa4bed97c4566bca264ec0290f561dbaf06c3c6b34e25809
125	1	419	\\x5e6446f37871ff7912a8ce5b4506960ce717fbae7da0b6b80d24ca7dbd1bf134e5d662b20574cbbe44e735d6827d5e94174455fd8fc491fb6d5543e111825a09
126	1	173	\\x9fc23484f4c7e986f2d910cea3f68dc48b16a691e12ebebd1b3229e36999f1d855ae5adebc8ce79decb0680d41ee239748807158d5edf84d5ea0a9b9f5b49e07
127	1	423	\\x6a1c47421da6f0573be58346dbc4b8941e5f7ef646a88895f809fd72196428681ea9af4e2ec94864ed5af39dff4ef380ae994e9bf34866639c8977c70a124900
128	1	402	\\x6388f8655865d5031500af42601de9ba36a1ef66b2f54d9630e6c7e0ffa3863c63af2528ffb286fd032c6c9fde9a6d33a4f45d324039f780480aa2f87e61e108
129	1	407	\\x484a4112b244a3aa4446f8bf5086327b7c6a9168ab93d766e88bb19cb38ffbbfc4f2cecdda9a3215fb684842eec95a394d67cbf3e84d5c77192dba3aa8d5ed0e
130	1	343	\\x50adbb3d12f337de0eea5793309db08960bcf32abe36b1893b0ba5e84261a4b1dfc277fe496bc2843841923d41784d59d5c13083bf6e51b760d48764cc5f1604
131	1	129	\\xa0b87c02b571197da3145534a5ca1c7e4db53c1778635cb4f8cb06ebfd0941306cbf959383dfaa2b2afc12291bff2af7c33a135df5e313b7b9e62e9be23ae808
132	1	182	\\xb3878c2ddd2b08aff4b0eb5bc8c4ee660138388ca2511be8d02ba508abac6cb32f1ad29b3707d046b811161b4b90648894a7ad75fc43dad1d996b1e74cecd202
133	1	281	\\x7aef95e0d6dea2251eded85125e7b4854b2e1a5c00f879fd0889a4b963ca10323da5aaf31cbb880bdeee37200ac6e43ef82f59a26a0309f37788ad8cc2ad100d
134	1	25	\\x79262dd96e16debc7a49b42752058c6dc0033606805e15aed492112e64e4b1f710089ac3ae1db9db884c08fac5f8f1f7a463e5bfd1ba1662c314513bdaa9b502
135	1	250	\\x0a49afbe0a0a4be4449d3bc7104f05dae52ff273671ed695238c571affc2e78a53a1ba7268c67bccb0d8fcd0f8bb0f4828d40f6799ad4cfb34b16e9d0f95cf0c
136	1	60	\\xe5697038931d67cb0d38d538e2d72142cf870148c854c5969e09e6ca57f41551150a17de507bdfdc93df822f53fdc352e7385c812e0782e8d3a3a5d19a39b80e
137	1	365	\\x2dec678c31a03f6ccfd176076dd84976872398e4d635d447d7491d4848c020382bf7a1ce99bbeb5e45817993649f71532f46e9cf545022e1e9b61419b805d805
138	1	148	\\x20dae2fcacc12bba5d69748d389e392059e00cd1fc9ee630eaaa2b9f1b4a05a49b9e6c0ee8607f30d0997507f635383d1287ed943982eb5e81ff402da2950a0f
139	1	164	\\xa5634ee529fa7e0b1226dfd42a7c91a7a56288a76fc89ac5b7b13a3faef063919eb87ee7aa9510388d7ff7956abfbb7ffe268a00ffe11f4f03ef3c79463fa201
140	1	370	\\xa02a9eacfde09cdf0b73b30d94baccd5db024b098cd63dff71d6b302f8854173d4c637064e37b46c2511e3a1e48215276900de9e0bc4035148955f1b0260d301
141	1	195	\\xf0ecc478d1377bfd35d8ac9c09435faf4deb2cdba94a12a237a6b0b9293dda7d29d4114d8fa67c57bd16ee308a3c2ee18b29869d8353c9dd99972c1645611502
142	1	53	\\xb45a696dc1237f371db8a7800a1a2119c587efa07756e56cacaf69ba91b89cc8f0f4a6d4171597c03596a59c9e6a6f8331bab361bf0b3400dc2922d4bfee4902
143	1	221	\\x858a702a6602bfd114e634dd67c7f653d57b51db4c48319952e2e851caf1a1aa2e56c23c2809066ed7efc6ab09e7f56e8c7927e8658012710843b74c1d48480e
144	1	57	\\xeddd03c2d19ab9da19ede628c3f255a3807d548cf42dfcf56aa9148fc2a0a6c317f7f884d99f71ab9ec1efb95941bb5a01e1f053f1f133ca10bb5af910523200
145	1	311	\\x31b0af6ced2f7a73905994fd4ebac60847aeb3faad8eb7182d16c267823c28dbb4791f717f47536f3c73bffa9299b397182902fa85973ce685dc99d45235500e
146	1	133	\\x4f820223a9a51572dc676d060c281aa3c3a67eac8f3f851ca0ff10de417b779bc3e383002ab27a0d27115a1416e68f7e848a0db39c7cbd23a7e7ecd87d9c910f
147	1	38	\\xb8fc5ec1752bc156e62ff4d20cffda8580446ecde0369ce5efedc5a92a44b336bd858a5dea8a0a0ca599f73a7925056ccc99c46a2db09c43ae62573d3e367203
148	1	177	\\x39badd821bf3ca66a3390cad15cbd188dba29df3aef2706421ebf5c270ef5b532819c98720dc08812a59b4fe7790bc4023a7b768509dfc84c0bcf5383ab03e0b
149	1	187	\\x8facf747c19989f97de4996d514c648f4d05c601b1f9157bb17fd74315edfcadb186d1b884720fb2e35612331c383baf1c71150ac2e820a06e53e76ed592dd03
150	1	26	\\xd7e680e4d5bf66feac82466fffdf666dd11585ea49e6b10133129ad28dee840c841980edcf63b43d2408b269f642348b0299c5ac8b2edfa6d70d02af5775d800
151	1	27	\\x9fae1dd7c890f0bee0ecf66501adc3cd966c7aa3352ea5aeb4bbd2abb5f7e4ff8529dc80c4506d714554a08ee343aa6e360c7f5c68b491086e88e783423b140f
152	1	372	\\x0ec3ea67eff8c98a44b4137bd46f626a96a38462ec960125d7ef0c1edfcb1a58dc9bbd8b377674f0432e32a66a66a796cfc78639422bfef80f1c30e224e31c02
153	1	236	\\x6a6fa2e6170cd773d91eda0a3c224c2389ba77a710a25920b03524be0b4730202a024e21e21c346b0a1b8e7dc7d0a9a58a2668523937510461a5873911331c04
154	1	150	\\x4915a7ef8b1feca1c756aea890dd88352d2865152e3f2abfc7617951f6114f557736fda5ee3ef3a1369301e62dfeaf9499d9b48f8b0d69e71f2bad2bca14df05
155	1	371	\\xcee0b492200b76c3877dc229af9493b1605e160f3cc9f1cd13fa41438d08e016c33c39260679cc942e26cfba96e008d7f2fda8b9b5d171ed7616fc8fdbfd5005
156	1	413	\\x3ae4b0b9e42e9421c6c0de0642b429c9bde73cb1dcdb42b4d3e47953929e012622ff93d628cef40e2a2be7488d6abf8fabd677e89aff84e56fa455a079fa590a
157	1	24	\\x4d99a91c6e203f4138c176ece3c3480fcaab49af319f77fcef5f7053875614a75fea5ea97990cd30ffba594bfa2b18aa52206a88d171f6779fdc1413afee550b
158	1	312	\\x84914d58f9487ccf79d94dafca9f8b68a327210433bea21835c8ab893720e18e45a0e1b91d4e8bbe95463ff27da81134c7e7120b4aada050eff4117ffe318b08
159	1	248	\\x4efb5e77c5c696d5d552f0de3b874b33b6ecac882cbf1e96fe9d6968214dbe5a898844f3dfe1d8451e1918dae0b18b9b177f0b2b28e7d53558b09d78ae269105
160	1	291	\\xc8385a2031c93fe86db793daabc24da21735bcd3cc7e63f5decfd90e6af865587b89dd394304eaa8c8547e836177b07f6d9a48712410f6e9fe81947d169c9900
161	1	232	\\xe7badc09e554bde673c022a42761d222f94a1c9a9c14d0cb1a8f53a4bc8d37edf09cd611235033aa42546550647b3efc66cf83d289e91ded5bf4d4b270c91b05
162	1	9	\\x0dd72fa0348d92e80e4597d6eede6448fa5a0d19d586bb686610831f220a6ea9c8fc8f1a099f39005fd5a4fd6a22c8b1cbd42acdc930e544921952e7b5b88906
163	1	193	\\xa0e722e2c086d4ae6d868b77856c9c7051c7b8910d96efc09b2761a46679bb84e119658d7a972e80cc6f360568e75d6ed45f9b7e683ac74d3947d90e82c2810f
164	1	180	\\x090ccd1ebf1744af2fa8829b370895d37c3e56e94a9d8bcfe8978f98e3524ef6b4619ba234bbc125c2504a9edff09a21f80fbfa357454218170514b81a9c4609
165	1	249	\\x639e52c003abbf323933c8c690d182c1c791032e2103e62a09a092ae1f2e6e88f1f29bd276d573050ef9171cccd4205f0244887b0ba4746cf6193eddd1b2b606
166	1	224	\\xa2e8aad917d3fa919a936ff0a35c9cba02a92670a7faba3df3e858a467b876756450a0f3649976f612ba3198dde94933ffb39395a6f2e94a99da36515e358b0c
167	1	282	\\xf395bac50c936768b8d7f7923992a4f013a0b66efe0884cc15562678d78bd9668e19c56ccec8cc20bd587e7f3b7e7a4228fdca826c6dfbf3ed1e52ff60472d0d
168	1	89	\\x8db76e921a9356c76112176a99e9845b12334bf60c017e35057782d7435f252806aca3fd21f7293dd3c64a256801cd16b50ca89326febd1fa47042bf80eb7903
169	1	274	\\x072b17d71c3277e1b8237f42dbd2d95b940d2bbfff300de56de0add70a29abb0b2d19cf9d5172a5dd9fd9947c8caa615e1936e73fc8c3f99645ec46b4fd60801
170	1	93	\\x4a4e2e84e7c85dd540b786b18d9a2286c85ddb1b83c9548570bcba350fbe69f88b9513da125fb0cc6e8c3f263299ec69a7e317fabddc040bc927e23684f5670c
171	1	147	\\x7b0bedff72b0705ba3bc3ef2aa974f7433bfea33ab3862b1fa48e5b714d5a3354bd191e0c3efa84fd190b259f1a73b3db18a58c192b133b09e1cf8bff112d00c
172	1	184	\\x4b946cd80bd50f45d08ced7cf2b2a23d28db2dc8bde28b56ec1d9d4e817a9e760f6b0bd76790d2d2b5e4742da4d8bfe029555f08e1c131aedafcdfab56d40f02
173	1	39	\\xc7ca0a28b26845e53b0400fe2ac0d486d4237cdb023e6858c25742d775313f993f23f9f7d149459efb6deab4c2e3313c24e882adeea9f4ec99009304b7bae509
174	1	229	\\x75b7c4e5818757acc5a60a0b3ccd53097dca96f8751045b450b12705900d10f7b0272a574e9fbbc36fb94637dcae61749e22574cbf2eb8eceb6b103bdde98c07
175	1	273	\\x46f525241295012d6fcaec56dd97417cdbcf5d13211050a968721a0526e79a5b642f8ba3b9021e181852eff654ad80c8a54fc956b6e94f7d2fa5a48aece6950e
176	1	139	\\x05e755b1d528ea5822922487863378244d9655461b6348a2248f9e1539f551eb9999381681e1d86ad7208048ba97dbcb88c66ba7dd492dc2d38727d6e2995200
177	1	44	\\x4499ff30f3e9bbad0749161a1393597ef8d1450182d813807cd0ae70e1baede92eb3a8547dbd53029aa4b70e0ade040eee81a00369b8cb16971d1fc32f93db08
178	1	110	\\x18894697a5af1856f7d2dd064da5c87d30f27b86866d2c091732265bd8fdb417a9262c9b00dccc9731cc30180236ec5aa9645c364f78bf38674e238dc0e5700e
179	1	162	\\xf89cb1cd2facbf89f682c5efa8c69549ce36a1e4e392b85c0f5d6ece51adda8606d0c154ebb78b5c49229e707f3805ce1e8747b288475c09ea4f678902f80e00
180	1	79	\\x0fbdd0e57c7dda5e5e960e6542d6725f0444e1b201ca46b8e5bff84c487c69dda43baaca1b50a387ae1ec9546fbdd95c3a3854ce6741342ce9e4e289b7ec4702
181	1	289	\\x7d5aeb9eebe7c459edc3bbd4be40a43d49e38a195902d888924d842b1b3e6e4af806a899ddd447245334eb4cd957aecfb3bbf130e85144eeb9baa24f04a18507
182	1	292	\\xbb16d6d13ac54b04fc44662b61b3486aa2bd3cc317c4dac0e3a73834ad6698484855c6bb503b4e2661bd27657bc849050d844d5f255947fe9aa0f936bd42fb08
183	1	339	\\xbf3ea0e8bc5ea17bc5a7ac91a438c01652d24db3207900e6e73a774e9cf2a85fda819da88fe1863da1b03ea80deaf8da62994818b63f1b30a8e05b1febe13f01
184	1	33	\\x87abaf2df35cfeb7d124b8bdaf9c9d72ce6a2a847c49135068e1fa0531701fc68ec4c0aff6fcdd049480e9038cdbf2b583bd740f3d6727142b122f94a1ba6f07
185	1	322	\\x08ff2d417deacbc9d41db85b682691cd97c270b7427a072497c67ffd35c4466b87b53cd29a425db76d804b823bf1564a28b74392460c9d843fd29af1daa3c401
186	1	264	\\x0b2156c6a68eff7b3f547a09fd9c364c0b8a6e0581a647ab946972bb1da9f630a1ddb9aff224bbea698a9fc2583f2778aeae4939efc9d1119c1c1510a9ec6c04
187	1	20	\\xf5ed3b4ad8430c3cddbebf22966125741741f81b9e67fe2d06d873aa2de2ab1474a23bd72d70c1e62094e6522d2e4bb1a4b1a03cee16138c93bdf84ca1271b01
188	1	70	\\xa3c3c387a1c8592bf584c39f99937a6438bfdf70f4136972bc63da8695639d4551f1d4fc7777a60a763f51b670e79267a8edb414cc819861f242851cbdb1bc0c
189	1	202	\\x7bba39ebbf033d151f9d257fbd9748088e7df70e16f7f9927ee6ecb6bc443fbd7f5f344695252ea3137c41972fd3b6e8ec35699aceca1e5d90efb996c565c202
190	1	205	\\xa23b1b1404ccd041d36f58d40ff0b2c51b3867a22f31107a74adde42e818fa9de0d129375de502e260834efb36083bc63e3c1634d4eac010faa6c8578c570108
191	1	228	\\x54a93cc8e4dff98e1ebff2b0d9d03e548fa0e50a6a468c268fe554189e2b90536863b8b5258fe6b2a47b0414c28dba38b4d80dbcfe83f2b38c8577f32a4de708
192	1	246	\\xbf453910c079166240562b172769305a502436d695e81cb38574921fdd909de51a077f07e96425ffc5a2ec8c94cf57f6b628441acaf184ccfa8432cef0496307
193	1	131	\\xa080f40619ced23471362a93865adeb64ad0707aca069a9c3d3efa5faa6fd53b2ddeece28f88f97f6acc4a23360068b9df7da59f46875085060a02a949143f0f
194	1	351	\\xb5ff0fbfc0508e4596b94b490d862f516024521dc9dfb5f1b54aed02b11bf1dd66408815d0ae1750fa4a4462c8a46fd27fe0b06fe384def911a52fdc089bdd09
195	1	22	\\x7c21e11068947ef327ad0519406e1a584380dff94a7cff08d05ad12898ee84c0a7a4de4e367ba9985be6bc090016766876aa2b7359219893414485fd0db8a607
196	1	116	\\x9241af2c088296881bbef770a966a46ab6ce8bfdd0b721ee45958674e20d24dadf8b962e40688a6af5b340c413917d23f7cbb97b063dafdff8dbd93117319002
197	1	29	\\xf96f6273df1d3906a73e6f9a29e31496d8c7f9f7e2620b7b5cbfe02603b5a090293da765a057a42a3cf79d0a15e55da6147da9a430d9d5ae10aec39b98195402
198	1	159	\\x29ecf2346066a83133c50ebfd681e1598d8217f7d95d8aa9c05198fc156bc60ba10f22e12f4da3ff6a67c4a71364c6d9dd38039bc8b6dc21ebac49660c2ce00d
199	1	137	\\xee2c6f21ddf741d40abd7aa6a2ddf550a3b9d4a09c79f3685eaa6bc32362ff8e29568c37265d397c184b17e47a5f2157073602a6d8968b9d5d99e9c3b1d7ab0f
200	1	225	\\xed17aea5b92eab7b9ed49b4eced983fcb2cafc19719825f27aa368559484b1daeb9cb26000ba49cfdf802fcc06d29f7d30ab60166db788ee81ffa708fc789002
201	1	41	\\xf88d7015f48939d61290b2d019b5532703d16bef8797d88dd0b43f37106a459ea085aab48ab657e793a5ba900fa977ab586336d02ff1f26e47bcb8eadc80be01
202	1	270	\\x1f17cd4b3dd17e1f05b7873ea4717bc1841372ead4e4f92a1f6bf9ae07b78b20e1015a96108c257109b66951e4e446e380949406193219a8db01619f4f5e0e00
203	1	54	\\x393c86620d52ac1ed80a03a45207e6a03d0f26675b92669436953e5012843beb0e267b8944dce81e7d559fd3a6927237de3474e3396c1a5f41762c26906b0d00
204	1	11	\\x59330c79904c758588fe0355cc6a976965391eb67d076594dd08b875b81d75771b71c74711db0dcf93266f7bae65cf95aeb88eb48ee8220724c3f53e1687e806
205	1	152	\\x3078b3643e55eabc1d84154b57466004f5d1efab60f8d36d4f0676da4d03527be2b95e5ea4a970b5e4c28d9357bc50192b21b6f759279c5ee1eeb0776204180f
206	1	308	\\xffc2fae85791c0edc9b2917ef33b61cf4af35c5f372e38e9119e190708fc6cde68baedf095c25d280f013a29b98eb88fb7cdf0344c0d910d0717666de784490f
207	1	97	\\x323eb9c2e1cacfe483d36f4f0f6193b946e2370ea56b3ffba21037770b05138381c04905bdced1c2734ab69b0c02023be69263decc3dfbfccef5fa53f0a6d50a
208	1	142	\\x248eb8f0b5e13fdea402f4ae4d56cb64a763d62c53bf8d5adb4ed485ebc9fcf12716bc88733b7d480b2492534050d749378a308afce3986e351aef6693d47b0b
209	1	3	\\x541f8817c91e89bf4dc82b59a709dc56f8c5c0f19fe343aaac194c4e134129752d5040db302ed6a0b4053fa5a16b2f5c8e96eb5910b4ce76ce072b8fbfa3140f
210	1	355	\\xd756cd31159773fcf577c4d54ee18553a5ecbdcf47eeeed1f55687b19959c4cd3c35e4388722d8e419a678733c9e1cf9f67d9ddab79f5a5feb7754eef8c5f30d
211	1	395	\\x56ae65bccd7a7620ed259090eb1639e0a630bac24e7e01f01f0bc416b446574a58d0f12f42b0f403c75e7f6c6088d4233a7393c5009d3e63b195ef060720c105
212	1	85	\\xd7e625ae7ccb4aa6b89a26f0835c21a69e43e8a3e517f046bbe147f7e078fa93c2ec9ab1d741679c0a8a074477f20002f2d0b9a82d0f3e0fd0ce1ea73506ec0a
213	1	241	\\x584728fef4005a8356ba71f114b23567f36dffd92e04f31d9c9b54f368426e170ed13d6769bcdca05485d8088d1a5471ba9ea660cdb3088a0a34a601d7f92102
214	1	394	\\x5883bd3903d50c0175091df2bb6034de37632d61b36dd9f679f5044fc0682cd56f0ac0f7170c088ea1698d5a7d6a65a9c8353a5d4470eb44ae0c3b8bc7da0108
215	1	124	\\xa24e0dc9f8426f0ff7f56f0f9ce6e975d151d561b9e0e44dc029ac0031065fa89240948bb40bb2fdea63451a592c2da0bc4c9639b961d3315012e2e879703001
216	1	389	\\x5ab27b01698f16f0b29339293c29d91dde55d5dfca418a043e7a59978f4f8c3201856a6375e1c9b0422a682c219dce08cafc429f1c6631175c53fb9e71f0ca08
217	1	247	\\x7b5d0fc972bc534eef055bc7797063a100e1424868005ddd554c76a5e20402e2192d3d6508c7ac40921dd099e0e21e1ca5ef5c4df93b5045e5bf8aa649d4cd0f
218	1	8	\\xf023fa0cbc1ed6960418ffd2cf0601edba135d4c0fc93097c138e7fa8e89689f9ab90fb68dcc9f56beefbc0b632d7649c9aa27753ba415fd46f64de76b605107
219	1	87	\\x76e963402579dd76dbbe6d7212043f3cf1c7e42a10ebca311e218671707e826600c24a118c04f27bb357b47baea524c94a86c59543acb64aab12bee6bd9d5908
220	1	17	\\xff72d1f68780dfadc35b95c3785ccb157490c3234b9edcbf8a7ac1851e62f5c0300773b9cf15d5199fb262e545c5851a7f4fc04a5905f1035614236fb07e7901
221	1	122	\\x8f378b51016ae2d619957aae0f06827cf475fc06f80e93bee37ead8fda384f4c86d3b9aa06b0f1d85ee4cd658a83a7c12c87a923d76474979546f25acea9a007
222	1	165	\\xf11f34f405843a6d3ed676b72e9bdbb481e06e67717d6ae7b4f367a71b5d93bb215c806790001a9ae758b13cb248b2ed031645f21b7512277d64e87a33a38b0e
223	1	361	\\x92faf6250a871662cca8b8defbdf7b32cf4207be1d81d61acb91267ba338b2eca91235002862231e77387b7e9c9e86983299af8fb77b6bc3216b7b6479496d07
224	1	68	\\x3a70ac7defaf2935288d24a9c2c613c1d1f90742c32640d6b5a7401a04368fa765ca88266922fa604c114b77a24d120a309f3d6d41f2168b863b5cf954887409
225	1	154	\\x8c799b0df85a9dbda65695d8824ec1951650c97e09f3e745e19eb2605ba8580fdaf1057880356145d36f641be0b6537a7d18835b0d637ecb74618de641e0a909
226	1	114	\\x1be655b87cccfd24e1be83687c9373a6af29ae9e937b658c9e7dbbb3cd10d4f78fcd15819ddc17a27c56551fa33b9667606b9dda537d50daf08547c68d1bbc04
227	1	115	\\xb19cadc402ec2da4f8046662aa00d55bb9c9fd5f42e55d503d74c48f6ce2d042052101e39a4a44258de72be332e5ae43edd35db0481aa8d0ab1a8a382966ec06
228	1	335	\\x3cb3fea806e7801763718b9ab3cb41a5b8594f83b1183896db543d740454e905ed19c0d24a7d879308b6df1595f1c6b534f09d2d612aaa4811904ef5c059be02
229	1	109	\\x05978ca97fe5091f6a59f8252f1e2b788cfb94c1ba9f912c17c4974c385d4498335a962fce49c6ff1d3e12b4798fd689e03e49b60fa62b82581c53b6d9ea4802
230	1	18	\\x1326614a160257a480113512f0b50d3536b937f5ea39b5fba0141c38322b09a2fc8ed9271cdebe0d2a650e0bf6d42793b0d272c5e260bf605d29aae459be3805
231	1	290	\\xf2ab6038f435c7e48066da6ed01c0ea44f560766eddd8914230ca3d45149e8828965fdee7cbf056668792153d537c5ec2d6378a8d7a61ac9a6456f44d9b0d303
232	1	254	\\x6c0d1b27cdfa105dd290cd7923f0317442b19f018aa3caed5efd81540c6585bfd6fb1efd0d5b69cc909525654cd081528f06946ba335265340251bc8b15de102
233	1	234	\\x09723abde1ca300f17efe07c2453d86301600a60c165fa2bd97ab63c870ccac6e9820eef3f56654d867065965461560e6843c017dc2cde2bfb5c322163a8e708
234	1	100	\\xe054e411da032d4fe602c7e8604d3d3c23ffd8af88223d6ab08472e8f761ad05e93241ef75b5e613a93da72a3bc74bbae7cd1aff72b72be716479b282cb4c10a
235	1	414	\\xc4d0e35a2240618cc167c79b9d0bb7b7e6d9d43deb998e9295401ba21f18579ad925f7dd48d3ea90f76496876a15b9e3aa848bcca51a753675c899f4d04d9509
236	1	6	\\x0f5ab85ba1d70e395738164ebec36c85cbd01adb9a7a88d9fd6e88567ef667ffe4b4dccef4a9a4dd7620b174a141d20fc66b79e5467f07c3706de5b061581d0b
237	1	161	\\x6c0e3d27f0a4bc34a2e92b07c5363c4e90ca01162b51bd58b76ef9bf49dd3d34b0445bfdfc1fadcbe11bc6b618eb17f2e738878e6b6e64f36ffe203df6f67803
238	1	140	\\xd6c19d7dadcaa36766d6e4e29d01644b5f5d9bbbf4bbb6502c23a2cbcb6416cc74a01cc3438e8df9f269b7ed7fb1b0c3d4ab1802a5ced7979d3feaf18a9d0a09
239	1	91	\\x00a1c2f11aa0caf2084d9ca57c61d2eade633b236cc776f81ef5cd207dadd441ab62ef53c8208b24036da5c9c083bdaf1460c1c7d968bae40d21e68398437905
240	1	149	\\xc64e07302ddf14a0a1c908104e1fde6c7977799b271b38fe6b460baec7955d6f8c02d96b7db13bf26c77d3571bd5e008e67cf7d20f15afaa785d154a9c9ee900
241	1	373	\\x1c0c208c1655c7c064940704cec552906f067b7a9a65d73e399cae3d6de9edca44a3137d374013247016f7bfb9a59f61fcca22db48c5aaca767ea5eb46da4108
242	1	334	\\xb5dabf3d05f103a0ab32e135c6380f730ee69648d44fd29e4ccfb35f58a188aca71c1cfdbeda4d9a02cdb6aae4a8ccc583335ee6d0cf2c2ab923b324b7477403
243	1	111	\\x52d220df4d34db5c4af0433827a373fed737cbdef665c6612ec885cc7f0c8f93fc6c4dd910025bcb0023ac3b125eeab947b24b0a0a1c9355fe7dfa8e9c87d208
244	1	35	\\x6564874e3bc6631e0cd90fcd77d1bd4286c6b1f4b2fdd0301530e8ad3b9bb5ba9c7337ec12283c4a36ac942029d9f1c20bbed593f3ccb308b180d2bd37ec6e0b
245	1	48	\\x2359be17213f8e176b4c727bf63428e3f3b0992fb9cdf071dde97bae34011edbbe419b411b03a8a45bb7817a4c2de562bcb82b7e3e356eb7b98058f610b7a801
246	1	78	\\x684525320d69b518b2df1cd7da68c161199f25f3a0aeb8ebe7cbd441f6ef454f5b88298522d7e01fb37dc9a88cf58e6e66294466df4738868401e75221e6a80b
247	1	257	\\xe1173ed444b76ec25b66a3e3d5631395ac6c201dd6df89b2dc0627ff938b96a8f53f1b6feaa9a835afd7266e3fae48c3a446d31724e8880aedfc1e9973830b0f
248	1	388	\\x0319e2c49b93e2b2457f556aa1f8fcd9eddb22eb9b4923eb491e315ddfbd8f7b22e7faf0763278c646fbf4a13dd53d4dfc6a18fd36482cb2cade0eea254a8505
249	1	303	\\x6c1d2076d259c45d350e97b3fa567d7fffca1cee0be9d09c5985f9de1353c7704d7e86cd9f9fbf6cdf93018e765e012d930c39611b565d092cf697e1aef4df0e
250	1	107	\\x1081ae02f08ac49d8f240f42bc380dee33706fd505b8a24d7610460a1de2fff85f0bd54930df8d8564a04605a8fd6d1df4d7eaf3815f1b573237ab1fe870c905
251	1	15	\\xa0a816519864933f9994886b6eba30c9d7b97e5869ea63430f1ca9e97398f0ca99985910ea08e8e68aa853aad2997671f011f9b80897754149ca5f9981329e01
252	1	166	\\xfab257934d791a18d79fc48766fb12e0f63a1d31cb18bb100b2906993e877cf43236512e1049f0b52d13d6eb76e26cd73685da1b27f782c48c67acb2eb5ff008
253	1	51	\\xe13e87fd3bd51d1e3522cec4c17d5b09c73850034aa69cc1055242cbbcb9b3d5730115c2d1d26f99550f77d47415607abc4f1a17325444fb7aeb7e824b86c70e
254	1	304	\\x1a24d560bf90c637f458d92b5d17cc29718366275785d4ede70280abee3fe86f5e848a5c9a1db3463adc7a14524fd0529b9761c49f00c5cbf1c7183310dae608
255	1	204	\\x9a1637361c8b1824aab2419838cec9393ed90d16bf992192df89a1aaad516faf4ac6179258b7fb58f068dafb8f3b22f97ced78f2926c6e973562176a64b90f0b
256	1	261	\\x32e83c6c66bcbebd64f113a68eb45bbdb356a4a2775c45c0d8a7800376f5164b7c2c27a82aa7797da27f1187179a9ac5ddbcdf8002bcee42a741e5e84df01609
257	1	1	\\xe7f52bb0eb41e9601e3363a865a37d56387a95557f8d22ce584db4058473838cf75cbcf48dcf0a3aec0b1e8b251f92230f25fb670767c24134be00628b85b600
258	1	81	\\xfb5bac920d71ce9da45b5aa88119c90645689df62abca680026bd5812dcd8fa9ee03e9afc6351e2aa19fbe3d6da628126cc860b810ea4b3b03f8c0ed473ab20d
259	1	382	\\x2a266d848499ce84a6c61ee65b5645032f28dfb00b5bc196d6cadeaa710fa7854943396552822cbc73f776aa1305ea07f13c9e9751dd6679e599a4a34be47f05
260	1	146	\\x4d7e905609a6d54c8b05cda9141bf4783d082bcaa63aea609ad7ad83368b79bef5e4aa4b3988d6960c2ad60769d03681f740dec0c16fb0b1635a5a41d8281009
261	1	255	\\x72747e860e613cf874664e9fa4eaef89ed21808ab153f70cac921170b10de6ef7b72993554b9a5b4c9e23cf78f468e771414e16fdaa92cea6c668b7926477d05
262	1	134	\\xdee3ab11b1875b0f21331061cb8d32cbd2eb6f51e03fb5bc053435e63e7977fa7c0ff82d2c723fe7d60517511a0563073afdb53f481c703b0741f6c0b4fa200b
263	1	340	\\xaeac7edc5a7546de9cbe64acf0690de32a3b5665d74a841e23b0b5b0b808e2ae6695587968ee7b9a3592e2b27fac8691baae2d8ab020c9803cf83f85e89e040c
264	1	384	\\xcba411148197e1f54fd06b861fc1f268267bb5d024e0f4fe8c12b932f5f13744b63433fe99d8aafc9367d0a9ad3f4c1412eacf2cc98e0dccff72d89486644509
265	1	49	\\x1ad146bb273a2347f903131288aaf872d06ad06f03da0aadb0a2a76af3d15395227652c140bf9fb18e6993efe5f05e8f684374a0d2057e9578d3d643c1d90506
266	1	390	\\xb47679b86cf1511c030b1928014a1b08ffe8a64db79cba57c06c3a9e366869769435744c6f931e4eb14d7c6c1e9d030e4eb560e332b49fb75f68d1a8e2ecfc0b
267	1	398	\\xcbec0163f3a66a1b2f1463d741120d6944a2b5b1dfff0167de2cac9a1739518b82e4102a1b89c44b38abdaba141b8a5c51303acbe093d2142cac76d2fc6a180f
268	1	272	\\x068bcbb5743fbaabf0ce0d8cb1ba6fbbe3d8cad87c047c131eea87f841927bc85cfeebde70ef536a504e3859775ef9675a5e60c99bf0a9c62b8cbc5c9ef92503
269	1	330	\\xf1e4fbf8957a2769c4d18b5267e1e51517a327e30bee47b2c0b3d9d2e995865ffee2f68566b8adce6cbfb545cbd041c59b16b2b8c10257e4987a43b1a6e87704
270	1	263	\\x4d3c0ed77c4b6a8056cdf3d61955aa412c072422bb8648755f049519662ce8e308ba88bc0bd3e809d00f38882479f0a3da45754818d182d7d7996c136790710e
271	1	298	\\xefc66f5424c4b287b636ad0de98f77fbaec35c4dc9fc4289962ef3c00b0397e1a92f7213971700f76c2cf4ffb46f39baf5eccf3796e0f0d77b84cd05fd51cc07
272	1	157	\\x70785c51d0515e1d9c073e5c4b4373ed85b67fb2e75af22e53740f3fa987cd8bc6ac4f1af894a3c01007456b3a342f8db740aaca439c92d27f0301172ce4450f
273	1	240	\\x7c30acfed8f972745a795380944f10dfcdf1bedd45565cf41df3d18aefc123cef61504afb3ad14a4e1e959487b6ae95d711ccace92ea35eb0a1a9e62cc57a90d
274	1	420	\\x3e5f90a7ae8374c8e69ff216afcc9673ef9baacbb977da0344de14a89f0a5bfd3e209df72368ae634331308fe47d4fe1128039e19ecd7a144382f6eeaba08a0e
275	1	12	\\x1ef645f11b83a73b3298c63d9cc2100047d6b237a29c9505266ea3806ed719dcc9f5fe932cb3e46f87e96047e6619f1989bdce899ab3f4fb666abf6a9fa10b0d
276	1	74	\\x3b71bc336877a602c90d5c7342c17ac828ae0e2105731eee8cbc2b0ce1d20986c1f8ce70bfdfca39673efadffb9c41f500cf66bcb688fced9057638b5dd29702
277	1	296	\\xf019c6929f912c1eb9b367d69bd756d936daf68034d0faba9f58019cf47822cc4e41fa29743fb582d0008bd32da8056e2a4d4150eb56b761a7da8d04ce5aa200
278	1	401	\\x08396fa6194abce27a758d43d2aca0b3b811efd60d3698cc85eb2338d3f8fcc50ce6ef9c0a09d8892a3fe6bee0dd2ad9ff96e9b1ea0b7abd727b3192bdddcb04
279	1	62	\\x29a086316e978dba62975e0e881acbb6df9fb652f01bd6d5a220475008546dc231b5f893c067a4e756ce86b3a0618068b47cbbe0bb4e3fdedd220eb94398f30e
280	1	309	\\x4f79471379d9d628a136b53ff3d5a078248472479e2d0f494fd022c95b6acbc3ee20e6f33b3fdb4d77fbcde6bf34cb1348634bb10ea988067005a0c4ee7b7702
281	1	243	\\x997a756df5b34e952fd4bdf44278349f4180b81044730cf2ee34f5ddb14f5edc510b8a8641bf4fd78bbac73ea689874df80ebf2e8bad75fb533b0344a64c1c0a
282	1	325	\\x0c39c0b63d60af0504c35971d5eccbe4cfad65a8d51e4f109a67563762675d482507d63d0697627484c5f9ef766bf0c37b8b9b6900e8e165ddcc37c7da05fe04
283	1	376	\\x1a7df62b49c6bb6c945e7b59aafb5fe6b704be5189db8cd31b262a3a35b38fa582671b88ab78307f60cceb18cdbc6c9ffab50fb64a7235d9364bc5bdb49bd60f
284	1	141	\\xc626aa21d9e98bcebea639848917a11d2555a7c91082792202339c6ed36cfdb1c232c3dd5f0e2a40ac23ff26acf94a68c82a19b32531be5fb8aa593391850001
285	1	90	\\x71352a4843f9565abf516e46aa5dc916052ff51c53c5f5ab217d451fb6da8dcfe269024c73f5131d84334e481cc50b2d71d9af523371da24bc0c4ce78877fb0e
286	1	163	\\x0ef10bed7bc6cd8f596516ad46c9580e63876131a5321d9d8b267a0496569ecdde9c8a791522a89f01d4bd52f7da549ddf6d0f85c2e8e57fa4efdca1ba258707
287	1	316	\\x20d0e53135bd8e40ae73d7c937176745b5c13ddb80537fca3442d4af2dec5547cb7d9905ae1db32ca2a054163c55adb454fadba976699337760b861c5c583b0e
288	1	320	\\x86e329b71eb6c02ff1b11820e08d73dfabf38a9c62cdb2d5f11438b8518a70a11035f96b6d84b42e647c3d4370220f1770abccd8794336f17f11e9bd10082103
289	1	189	\\xea356c9d660336528fde10b5312afaf1db49c210f8407d014a2c578846b77f31747d44430ad9fc63f3085acb039036ed2ac2bbafc5882dba6e6a910e3d80030e
290	1	326	\\x9ed10ec2cda8cced3f7f9b8cb90b2aee31fe8f71692690f65a6906b315d54f861ded359fd2f6276c439e6ff18b1a93a9c9717d54c886e0796504d8e13b756604
291	1	153	\\xab75977e2e0fb1ca09ebc83a0b27627ae0d3a294bc7f43055e8f3235ac6b45cbcc5a92c00a566a31cefaf65d309ece29d55116b5c88a3acb6c99d3a84aa70e03
292	1	117	\\xa0b8c392871b241bc50978dc00ed9970c6d5d52471911fa2d01432dbd1fae3fcd5ebeabe834078238c56cb60cf9ccef11af4e2cd7e5f1912abc8dfbec2433008
293	1	344	\\x847495556227db2364af47a85eb43a7bf53c70deb294c49e356febb8f1349044bab631f9b1c262a96adb55d80b58f3b183cb318858d450fabc8b4c8029ddf408
294	1	310	\\xfbf59db552531630c6da72fca6a882ad6b6f031566b875341912e49a2ebc730695ceb8c1ba6bc189a924db84c6478c7ebb95fc8e7b10479b39f192c47f7e5f09
295	1	409	\\xd430ced46bfddeba23190b060195ec02ac4626eff48e6c223ef3896a34dcb755030ab4495a4f6917ab67a0003778d0c0f322793648a707c1bea20aadaea68c09
296	1	50	\\x9fe330f257bbe4416c62ed5a9c211ef408de88ca692feb1013de6ccb28861630feb6aaab9aec0c07e363c3c9d90e0f16507ee939850db8dab6be6a3386252b02
297	1	86	\\xc3396fdf539fdb1e9246996eb32b9eaa0fb34b9779bf4f5e75820cda5d29cbc0846dd4e2e29c51acfde9cd51bc27352ad876260f20dbeec8a4bd7c91193b0609
298	1	170	\\x53cb9853d427f17e54b18746dc29fc05b1a6bd81b064c1713974dbcc3ecf7d7664f4a72fff5355e9945c64f3ff99523f27b7528ce71c91ce92056996f1739d0d
299	1	315	\\xa6563750d054550b3127668b4236c2b676d35a97245b62374e72a434b5460543f2c45cceac23071d0a82413e9c9ef6b06d75c3d966103c57a7872cf701666800
300	1	324	\\xd2aac9c1d3105f0b98c0060a9c28f5c705447823284245831570156602c76ffa802eb99f933f87b32c9297f91e7a4bbb1c207eaef232d81fea0903ac2cc6a90f
301	1	387	\\x4ee2f072c45ea7282c70cc37ad7bc28fcf166961176de4291c4101b205beb4a38b7ef6e6cd060fec8658aa65ad9e9bb5cc39ed8ff8ef4338019452595db67300
302	1	10	\\x63dc8eece60ef70a55650de913139a59647f7b4bb805a3f8bd316441653126a233f1f0236175b3b10ccff1a0bb71acb67023b4820f9a62b408b62efb26d1e30c
303	1	237	\\x12a87d9013f5bcdee9b43b579f379baabf1ec86fec581013f874eefd10d8f4af797acfd2277540176dd6a3d2761231be95101608c1087a3a6c91a17be2d7da0b
304	1	156	\\xc2a9d7dde6149733c9493f77d64df5a9d7d658574f86e681244fbb58df8c5da396ac2c8e4f7140bee5e30b08b29a562229470b2d9d613c9c4331e22287c8b40e
305	1	5	\\xf4c12f564e27877718138843dbc7812c480c8b4dc1b4f9be1095c64c215b7880ef6218fafe05cb28f3b74e4cc9c24a4bec34befc4b27eacf5d9167c92b4b1b05
306	1	377	\\x35e7c692c1b6183a31bb81ebfdcdb2df2d0a31656e55ff69f162350e18a349743175102a2c08cc5c16a9a1359396aecb6c935b2059d6c5f39a1b0e71c9242a04
307	1	368	\\x79d8bc3c1b0a51e14aacb5afe62e40dbae36cf98d53743c3b6088b65a028ee07dcaf6d326cb3639831258e9aa08828afe82a5e7ff1d6a663aee4fcc895bf090d
308	1	185	\\xddb69c63557688172b7ffba67f0356cb23c4784152dcbe760a5a3b45ed75d4ca5011c103508590e4ed47e2a2a11de94f885e8b2cf02ec4f906421a31c0d45e07
309	1	175	\\x6a7942f23f2d0f3a3832019a066d6a5a35c803d811bed209085d026831c1d59f6889977fbf70053eb2f535dd79858c18eb055219f98e3ab4fcecbfbf15cb5808
310	1	245	\\x176b2d008d2650a638de5169c6ea14389256247ee461d4c5da6327a48349b04cdc82d2b17b2addc6ab18a70835460d6769a2cd3fcc52c9916a1ac0517cb42001
311	1	354	\\xfa53990ce1c8aea70e9996fa403a884eeb3cda8081c1372eaa0a039c3c3da94fed3edcf983dc630517d1f30520fa31ff72ca01cfa38f82c5a1c9dfaef5d41500
312	1	207	\\xbe68b4eaf9f938a63f4dfe1262e593c7b7d70e57f14cf7064b6a2095e9ab6a2aa9607519c7f1f4fc0f66dc065b288cec170a3370a31324db91bcac15c3fe3309
313	1	385	\\x3748205227091615a6fc10e7c7971c157798232f9a616620be4db28f34327ffac99357b7683a29f6bb9c6f8205e87aa5ea5aa1c57a544ec9b5031a950b0a8205
314	1	323	\\x4ce0395a96e224db690b996a49776ff73bc02ee94834cb3b8bdc5d76567b06bfb0dae3845b0014f8e2ec3602f5d9006f8eb268a5589a123c2df1bd8f16e98b0b
315	1	213	\\x9c633a9ecb8dd8570c5aa26ac0149059cabc94985fb3c7b89f0b179646f456a5d3da9de1c761a3ad8d82ed52fc515a347a28a9b8c5e0c09e6d7458fe81a25904
316	1	155	\\xc578bec174b136a8d0d8599f5cb2f1c220063c37008a43c1233a118dc63a29d6ed0f8c1143e5c638872baceb7e2c955d38c13a84aa8ceacb77e1d08f5b3eaf0c
317	1	317	\\xc319ddae2571118f9262ce4e1023c170e76ff4f018e27a047845384bde86d276e590fc5a4b43bc2fc3347b7abdeb4d3b4a6026e7902773fa011b40c4ea26bb05
318	1	374	\\xee400ef297567c4a6ad4ab4a8279a5c39f0f30454ca500e69ef9b9b8e3509501f7a1aac2ee43204445dc4145fb9e7c2abfc7ba67e10b22d0b5b3acce9d4a5304
319	1	99	\\x0105774498701880ede7d212cd9e6a1b557f46cf4c8fdc3f1e9c07789d63d05eeb12751d6a530db2571899eeffb31ddb471a51a80f79324452276967ecbb4008
320	1	113	\\xc8401d70148a0021b01f3e952dee82aefc32660dfdec5f4a12d40916717aa2bed11f91de001e84faa7a56cdc6e221830a175e106555239816aeee45eaa72cd0e
321	1	105	\\x7b1e187298bb0d71f97c359caf3ca3824d6c3c0516025ffe1fbb75c33d404f29674ce18507714c5f454b782cb20c36c700429468ef3bb6eed2b7092f5e39ba07
322	1	341	\\x90ee2ee896f8003f8b65a29ed127535aeef61855bbb5699f2385f75443d7a331b782c5e6bd9b43f54ecbf0dc005998536a4d061ed3643dbee66dabdc93ea550e
323	1	112	\\x8d4ea8c410226b878c938b91128de2a0910926d67dd98d8bd3fccad433fb893467393873e6982a8b37e42a538e0a730ceba6ace139cd4f14f015a60526520c01
324	1	319	\\x838601554ee6a5402fcf56a81b8e4b8942b4d684f45fe07a078feffe48c7373e7da4f4f8e5344854b5b0caf2699bca7b2c71b1ed1b421dfa50f8b256cf4f4a02
325	1	233	\\x80344267eca2c51b5dbdb3a58e3a466fc7756d9f2a045dfc988ad4601f8de778731db8ec097ef9b905cb2dd56a0f8182fc4d6915fa7891cbc84216b49e05420a
326	1	378	\\x8c5f121b0a3edde0e14c679a5e4a1d670a1381aa0bd95acc746a8a6b239d211c790ed7719de5d84f11944bc38b695bb7a78a3bd4e2180b04d0f6fa91ccf0ab04
327	1	56	\\xb1c5d7ac350eff3e1e4bef0dbb0a4f32cb1896247bb04877ff1d64542aa558ba60eabadd27fe66cf8ef230d315d998d6ff5f42bb38adc745fa6c7a494ae23804
328	1	314	\\xefa015e4d6d482def86ad2cfa7c9e7e9e9a017f15f8e2c66ccc8c048fd87819f15e94c74d3b63775c00c4ca7ca1d8ecd38f3706488dac9440ed4ed3401039202
329	1	61	\\x4198461e6b16607160cbc9ce8b587cae96b1bfb31b5a2adfe6d7f97aa7ae01b3b7aecd935ddf4d211c3b7f48d5dbfd378147ec252a102f8f510772dc693d960f
330	1	217	\\xbcd6524249dfdaa3fdfe55dd6d8a84516c3cf4d565d710d2a10ca1d5b1c62b1ae1386c46df8ff71a6e1e3c70c2c2da0c86b502864f45ab619310bdbe0a3a3c09
331	1	21	\\xd317635a709dbed67b3678a852dbc51a4f8e5fb5143025c8ff46b4ade05f466ff02fc7cd4b3c37e88960f7fb36824c7d2d4af4562e1eaba0ac6ad523e4936403
332	1	294	\\xd2a2f53cd63a1331bf05ba48a0c029e051e802ae6444979c2101c2a313f64159e93fdf30bbc6b8b278ea651e2db7e06a14504fa87213355ca26732fbcea8b301
333	1	359	\\x51b2bfdfee288977f148cc8c0a48b3f0e30a0358420b9177b618def2b9354a7e0c140ad97b5f1e17e1376fc32c598be2f869ac72a1f3062f5f9433c139a04807
334	1	2	\\x80c02a728086d3150e513a8c45140483aff36bac1189f1400a64fc385acb3da15b66961d65b52b4898f1e0aa13fa97bcdf4bba295a5aeec43de07e3d36b09107
335	1	242	\\xf4316be6ee3cf9cd3ce7ced90abb1c3c041dbbf67fae9af2473ea20915ee5fe20bc3a5f5fa14292b75809ffe9ccb863024c1d0da19fb40d08855f29d55f91903
336	1	347	\\x03dd6ce66228e40ec4e002ea27494ff14f94e26ef7fc0f6be9c3fd7342505e389c050a010a27095a2d4ea5f551d1df122e115a5dbff7e7d782716dfc7289d908
337	1	226	\\xaa6c907881a5430a17a3da77ee6bc0595d9d2f65afc7714f7da602b6561b0cdd777b33d83f684043965d189e0355cee27664a8977fcdcbc70e5fa90caa75a70c
338	1	412	\\xcfffaaffc73a8b343bc5f80ce2235122bddfd669b55973657d8fce3b6ae394c7d81b4f9d29c01d551004a051b6eaf25c55d59fdccaff750b4d70b6f0dbb85504
339	1	288	\\x5ad3c0bc6978ebb711e4af1622409ae24567918b8f90b2c1c84bb79f37142e5d473de404393ee46f3356a82420500313b3aa03b68ee4c1a5d6e429da4bbb6c0a
340	1	369	\\xbfa02077f5d672a793f0def60519f01d9d07a4fc9677705b4a17b2eb20ef9edfc4c2516845a75fed26026396940a50e0c6c123175d356f0bed7056e7dc7a5003
341	1	380	\\xbb72f1f3c0ec0a743f473297a90d25f2c9afddbeaf5531b24e0f7458c5c0547d9b1e74f210e3b0d3f95a155d1cb28bc063b659b602531d7910d69b42c194d002
342	1	7	\\x8d36715f6394c89e39882d7a2511cd5dd54cedbb6648e3f1a70242a20d7395f8ce84b0abfa5e8c52fa4e4eedc68953a6419b8448b64c8f3fa59db3a654cd0b01
343	1	363	\\x0e16c6983a0e64595d5a7c008bf07c5946c9079622e6d93871582a806f205a55e4edbcad05babb1b4acd09773b43307b1a514960bded81ccdda79028f711920d
344	1	353	\\x4870e2cc1c522181dc397e1a69f0aa04f06f4f2d4ec14225be9a8017826f836eb30c7bffca7a2fa3a1d200adfb37062eb3b205e265a8f721a022ac551573d806
345	1	30	\\x13dbd0d3921d528df12c9120454a086da1452a17c66d70776023d7ee7fa3a2fb84f3e7e2c2ec74173a731092a7e6cceaf63b7047123ada1dc00beef874364506
346	1	135	\\x6c60cd91c2afa769d10ebc7c0777e2a7d102e4c9b2d5901264811ec1aa8a373868f44bd158398cb9f8d43c773a9f22d9bafe456009d43692ba16b38fefc7b306
347	1	55	\\xca4415fd4ab88449037f24cfc203cf43cb001ce3f4114ba6c85800a95479cbf673f6872a664a9c9f0ba499c1b738e0fd83a10739fa1e8208965609e3aeec0e00
348	1	349	\\x11fec15ba759db2d399ea61903be4903ba433ee1558f3f7db80ba0ceeb70b3eb8d807385f0ce7a69b854e4a776d26be82a6baa4040789f6ac5ffb332bc2eb70a
349	1	102	\\x27ba320fdd87efc32563f87d502ae2b776b340579f93ad36da61a9f02e6a8212b1fab98738c5dd29d8460cd021a6b7eaca3f76b5e86724d7782c5f9f786bf005
350	1	276	\\x4c7deea9f91f196a080917f6d778f4e8d1396551c1ea4832f5efc4c6658187fdf35090567564fcf56ec778853755d29b28bc5cd7ab5d8cf9e2ab557f0d8fed08
351	1	285	\\x1ed3813f5c258ecec6c26e345c5816438a309c6914a0d001f7eaf6860cd5c7125bf66cd31dc51e5f5fa0f758266acacbda961e6d6d867a0df0338fd5e2343700
352	1	96	\\xf53b07a53164eac0f15bf638b999ae0d83467be5b2da5b45ae081dc1ea59774cc04a2ce6336e32dc09a797e5b652504c83b44552a5d6c988c30a730f63e8a10d
353	1	262	\\xa2fa85e1c4f149dfd18bb62d6ddb930f330b3c54947d0a7460d6a2b8117dabadec0dff1e3b10869ae55f30fcbe8b7ac1cc0cbc41b116db89b079a3a5055cc306
354	1	200	\\x275c4c0922a18f36c24315c6aff98a02061f5ae1f0c078631bdff020d7460b457f49d9a09f00781637d91f6a4c81162fc29056701ad85bb149c6e01e78800c0f
355	1	128	\\x502534cc963b4433fd21c61871a859dcf87ac91d003c80e7892dc56d78fc65b0e04781bca8b7a01ddb32b530c00e4f3cace742550bfe17d653c08e52e55c280a
356	1	346	\\x9a85895921dea59e55ef46721130c14790cf310b28a85f20ba6cff610ce0fe2d1f178f8d2356aae1efab5a66eeb6e63992feafb9186f94246271e8f3d4601402
357	1	34	\\x102331424d673613f0a9863e82e695ecbdebf5aa16f6bdbd10de748bebcd8d9930de0d56b65edaa71f37e2c7c480d9f4e015e0b82b8d0608416bd5d8158d910a
358	1	278	\\xc6284c085783f1f5c10889235fc76b352c2a4d3db537016c9c88b8b8a9a36f0dd852e574af28e8fa30ec64b8650f7e58c697d9cc49d4b9e7fa6a5863a25b0305
359	1	357	\\xa31b416d46b4728fd78323b4005eebca200a9da1046dbb8c0ce393710a8099da7221704d3b3e1d8833682b7f032c16311cd43caf80a69c6793f1ee6cb4046e01
360	1	169	\\x8cdbe211f468bb65dce63f4141bc8cd792f50c20a5977b76006ef6a649e4459c39a34734d410edf1e351a8e852670600bb9e06c491fb0c10d6aacae03f7fbd05
361	1	171	\\x56630c845b36ba8dacbb092beba1f501ceb718cbe2ca94bb38303bdd6e089d43f492fb187daee1324ef1795432fc21c4f42432825676d7d2d54f4b38e62d7500
362	1	58	\\x8f71beee283e69cafa1e77a5406dabf27f1019355897d470122f4c5e74c335ab8dceb7c6cdfb34cbaab9989be52167f541d7b583e5436a98e19ba50b70f3ca09
363	1	65	\\x23ea9fe7a24c893819a3cab61d9f88adffb6b2045d82cfd8a4ca77f7607ce50eaa8cfe8b31d467916be2bf3c1ed79b3491c7011be3e4423b185c49c9efaeac07
364	1	172	\\xe5132aafeaacde8b72d078bb77a7dd52bbcac05dd16af5a4167eaf19f14b3af39afa6490c020f7025099832436868f882dfa2506af5a18f22033bae20f7e5e09
365	1	366	\\xff64e7040a5de411d89463fffa2a58c3138906b4f686570ad22d45c3f3bd2c240a4b8212485fae3670e3af209edb73c990b10b96656836079d6fcc91984f060c
366	1	227	\\x13a9c743f51686ee27b2ff3ccb048272e81d0185dad6d4c086b1eecd7436509bc98a69941d216efa6f136def1fb8827022f88d699e06278943091dd79fe3c607
367	1	45	\\xb662fc568b5b9a1fec694c9a0d7dc989418e8e7696e89ede7c86f75602196077fed74154ea42094b35fa068d3226245864290fd0e62594e9377f18fb3f18940c
368	1	280	\\xfcf4ba0927736a767f7ff2d8550ad1707bca0b112e63a4eb942366315d5d5de76423b7793c658a82814f5ea896c1b72f33c18edc311b4d8e24e0b29d16f24000
369	1	318	\\x71cce49dc4a39c6d67d78845d008551508c4acf344ef2c88b64efd5d6b1851240e8cfbbb7bd1ebd5b51c301e890cdbe1a17d7c847bec874357cf761e2f002204
370	1	231	\\x978420d46e4f33d69923aef63a70de4f7363434aa5d269e55729c4cf9b269d571c71aeb9fc7d6e8a791fe226e4afd9cc4c7c87685e73d458160d78bd4c96090b
371	1	168	\\x85d079af3f56c58a07e54abb17f28cb3c99d363c298c37e4cd86f9117bb4171498144a11045cb19408bf3ba4e2bb5e99bda7d9430d849896ea9a8f7384b7ca00
372	1	239	\\x154cecf85870a02d4c281aade978a6e04f30ac175835f18b7f3ca78bd8e35eabbafcebecb0f9a8984662612c3d1524b5d2d4162f7240108709d00f633ef27c05
373	1	73	\\xd25de42c3279b1d11d55ff08695663b1539e3bb43816feb7445ce1103b8670fc192e38eca0b761495343a11da26fc9e6bece4b12664816dcb8af78d0ff115f06
374	1	256	\\xe2f58b102e3f60acf5533cd4862c4c2c3e0d597ac8aeec5777c5a7122e11482dbd7df95910f11190d7cec69d9a1f375ecb847edf4043664d2f1986fc8132dd06
375	1	82	\\xabddafa4232e5fe6e3936d5dbf343b929cb5b75e7abd498fe450a90e95122711273d48444ccaab476fc6eddb5f1973eec39795b3c2b8f2fe598011b22ccbee0f
376	1	267	\\xa1373af6f418530df867df1aa09de0a2e141078a2e81d6bfea36c1282d0c690949b3349a391176b7de0c1a461979b38b9e2b54335723f128103940b238515605
377	1	360	\\xee5b6f49ee0e09111573d183d5eabf66f914414fa130b2924b85a226922d85141c5f062d492a6f35d0cbd165a964a237f5a558ac7f0ad04c840f4bc61d442f09
378	1	121	\\xbe958f787440894692012514ea1ed2b34989dee140da6d461b5106ebc921586ad95d1a90f0dec363a43060bea8d228fefd4b5b739a87cedcf54c265a0f1eef0e
379	1	364	\\x30d111738cc9c040ffc270ab9b911af271a38ddb41a4f279dca1a67778315d9940f6a025885e2fef08d49510b6ec4568e0869c22d73d670e9ad9a742260cd200
380	1	356	\\x449eee92fade1e2fc113779b269506a238a17f37a24ec6c30c75966fbb1fbc97b81a4b5068e7473d7d463dd53014a099d35fd7d09c00fae45a79d79c3bddcd07
381	1	123	\\x23beb92af3f20579442a568b02b380df9d7f2e18a8f62f1340539b20f67bb02eea0a2a7e5d9933006032b439883a1107f1527541c0b71dd3d30d2d1f993efa05
382	1	260	\\x9b57db8058668a67c92c528ec7162e817f810de28d0c933f4692e5a1a78085718ff89f866391d522ed622f308b096dba7b63a358246d5ec2feefbe42ba1b4c0c
383	1	302	\\x44798b41ce60a80e7fb148769922469422f612f12abeee1dd1fff01a15dceb87d923320fd856138190e4d2ea139962329fef6ecb942a6d7ae20209a098d6c400
384	1	415	\\x211c00696bda245c9c8718680caeb9ff3a595bb7edffcd6d4c6ac9ea7eac9ad0fe283b97672bdbfb7658326f387223e810ebbc1f738415e396a398dc0434230f
385	1	399	\\x4c2d2da973acca2982753b0ff5a7414d6d3a2c59f4218093a865477f92e62c9f71b229032f49cbd2d8ec07fd62e71e42871e1efdc43c6cc77026c66af2ad690b
386	1	98	\\xbe5666e862fb8a9182642dd0fe4d6bc259c0d03299f8eea839e27481bd3054fa916884b1c18b8824fe040874fb35b1c3225eff2c50d49e020f5170540eff7f0d
387	1	106	\\xe99eb4d3c9b50564cd591c64b633762741c7144cbf8e4dab73e74bc1ef4d86082dbb79f5b1fd841d1e754256c871fe4fa0b4fb6f99ee9e9942d77388647daa0a
388	1	198	\\x2175a1e54e6f48d39b881543cea8bb45e5e1305204ffb3e5fca3c9d78652c05c515e5d89808abb7e6b7c41065fbaea8db9483aeff09f24c875daf550b317300f
389	1	210	\\x9c0e4016fbfc9edc37fcb40baf874a97026f0299dcf53970a015fede7db7fc4567ea5bce2c2c19ff9e421387e4b0268b1ea195f16a0b8606bdeb3aed50c69306
390	1	144	\\x62ddb9572fab9bf1766d39c66daa6f0cf87542822a1fcde1cf631ba759e2c758bcadc5cf3843d14d6d25b603022e33a07874836160545dd73ee3fae2fdd57e02
391	1	350	\\x82062b94e29f2bec3597ce85fc5669d654d4ac14a42198343eea965140e735319385ea1fd66964638911f5d8ab487977aaa28bd0ce9d690288b95574bfa04402
392	1	158	\\x08e40b94051eb0da90eb6e8245c7ca36e07539ceedb573a45625dd4a3a271d2c7c9f00a495df2dbc1e7b1ed709d896ad6c0e914855d6910a43e7ae159fcfaa06
393	1	313	\\x6ecc4fe5c913f4c9215489482629057d4cc2b7d36f70450d32efffaac48b077c0c1ed176be2efa2c120724847d4e499177e5fe47937c7c09c2e7f94bce987e09
394	1	120	\\xf5a83ec0407d11db2385c87bc09dc2ad16c7d19255a48b6b191d1d667f8df0b241f3e31357312c716116782883ab72a22bb02d49b1b150b63742740104c0850d
395	1	235	\\x7b8be5dad8642b512ecde34c79422a79339b9f6383dfb8f0a2a3b04c42ee75b9dddad9804371977e222cc679de9e84f4675ec5e33ae9886da1151a7cd960fe00
396	1	328	\\xe019792b9953e4b50cb4fe07fac70b4cedf6042d8a6f2d506d5d820f2ead3a3c0a51f3224801532d716c5bd8267154d130a1dc87e8d737f9c1887019c1330603
397	1	345	\\xc6d5a5eb17ac3aa97e10e144d3a2bd982eba63e4c54916a2d011b4e2855e254a9a1111c8e5a5379f4dc25f5e0d2e6c19e927a91e0bc79aedd05cc2015de2e70f
398	1	265	\\xa596717a5940cbe5c6efbaa6543e7d2b9c8743f19ffe910e864eb26bd9c5bc6ba9d8a9a9d01190931c7bdec55d6288b3c050b11c385d1c58829e0145105e1e01
399	1	28	\\xb861260736e96d5b6212bb76dd660eef13933241176a2ff7f2e465b6a9100e237e1d71c08d8e1b07930d693cf14693eab9c2c3d3ea14541da47cd63e44107604
400	1	196	\\x4d74980b1d0f90143f7593de461b47a861523ab7beafe5fbd66913d94dd80e66266c7a3540fade1132619c7f158a82a78cdfc20ce0c7c714a5d362d8f039df07
401	1	71	\\xf02072bc1b5659c354e6c1805efd38a2a353ad0376c361d29e3ecf4bd94bd64a02fcadb8cd1fef6f3cfe8855f3563a4fe5c9bb0cd23099551d01169c1bc6070a
402	1	69	\\x50baaed04f5520de0e5a3f40a6fe6891b87f21cbc6b9627a2560192a20cb0a72c1394699167731cd69c531159fd144515ed102fbec8f7d2cdbfe281d461cfc02
403	1	212	\\x62ede26d3b3a71c9655393edff21f66a44809e8567d34777fa77aa8d457fe6db4c934a3049f292989a29e28fce714867b040ce144feb931fc8d3ff388d7f8f0c
404	1	160	\\x14b8e87693bc38831ef5c1d1a6d6fa84ebb241454683704bb2222b7d3c8b57a1a27c24f42dfb0be0f98a6e76eb19e6687f84e8f196fad9cb6191e9eb458b8e0c
405	1	362	\\xa1d92bd565e399ad09473b06117a6e0c69fb63baef6aa9f33f5a5e16d3040fa550ff29290c0da6f2ae336b3865c35f5ee60b1c340a5c97f2f95a8e5ded393401
406	1	80	\\x9e8a26fec2f01ed9f924b70aa391638ec7e3691a6bef3fa0eed36c3d03a4a70efbde2d86b2ff40026651a8b8940db9af28c3d811592200c787c2bf132c355f00
407	1	132	\\x30c164aae15bb0ec680276139f25a5f949714a5f37226b6cdd86dac5f56ab042ddc77a30807db651fcdde6d04dab42b3af510ab62cbc0b650610c004703a6602
408	1	174	\\xa16394f891147370b853e3c7eaca3db8277238cebe3607f7893dd0522eae8759a027b7ac835816026eff8f30444cc8c8a58baba7bccaab154adfb26e80572001
409	1	284	\\x1a4678a0e7d5ccac78f6d14e72a3d590b68ea733170c12b4cb96e58fc9f506d2718e00fb3e0ed1ac712410b7d23dae271f4d45e2cfe868e8bc3842814cd8210c
410	1	299	\\x9f7b32cf7fefb9dc54f419dba7c4229e544463695460adade91168ab51537fc65e4327403c39b6098cde0b1ff0fb31eeedf12d1df12c9b12f1c54cb6978af30b
411	1	101	\\xefa0d36d6da20811cb98b1daa0f7db14e16d5a1eda2e27d2fde0ce13c9332fcd7886b865310e34f56b64572d1714fb9db94527ad028b9e6ac1da75005831da00
412	1	252	\\x8ce69e332a9c683693fe5b7363caa24f29f0ea93b462385237cb2af9944b13fd726fa5159c585f43623156a931b8fea7f5f829aae7a8cbe0d8132f4419362f01
413	1	408	\\x5d720e224c6d3f163b7746134e1421713efa3f834ab57e247917d53a8213249443e592093ba82a99603dc7a148a18f701f0537195a82624865a1a61c2a15c00f
414	1	192	\\x8fee629ab073c98c0a538eb1796eaa451c140dfa0bf50c5999b6cd31c54e8eb2539712ef92041a65388646aab4ecb45c4c6d58ec11b85f3a8020bf62d8e96e01
415	1	83	\\x7fc77f9421de7378fe05411319c6dd46f6b40e54f34c07f03354d983a51a687c1020ff93d0255c90b451e19838d7190948462db487da0f73bb8e8d52d3533d08
416	1	358	\\x8ea7ca74daa75852e501f654073bd9290596d3319e66fd21210a865b26dcb5aad9ddb59a5f35a225b0465a109794ff87b06896c349a11768e7bf2410befba90e
417	1	336	\\x39fac382f9292ddd0cf4e2188cd3f14af211f57df2744998cf06d67fd925d448b6f2f51230f76552292732f02f6bc9c2cc385622d4484b6314fe320c49d82607
418	1	206	\\x818b7963866d38dd7454ccab2778dde13285486d62f11f0014972200298d03e5593fc401c6222f688c3d6f1a43e1d5513fac4d0764d05dc76b998573a53d390b
419	1	268	\\x31c9138b353de4c6d9ddc36b2772d3e957d1ae2f2b939636ada9ae2c9ab95a8b8ffc89de94f5a464c6d7f60545daee2666d29ec328c17e514c60caa2662ad10c
420	1	181	\\xe55b36b93f94880d1a2f1df85f23ba41b1b3d443d6ee3b203f3ea2d86903bcff396e2754311a0cbd44bf0e98e3093e92b97723afe8740a86aa8f66eae25f9a0c
421	1	151	\\x747dad4e2abaabf040bf785fbf395d6f4c1066a69e190f9fddb30f60ffdf9c2d1303a74a63feb10ead6cbff435ab05d692f239b1498d5a591806fb0871c31c0c
422	1	286	\\x401cc71eb723e1bae0749187872a6baa8018a467141c9b3f6adf8b5ef8a1994ccc6f122b31b98c5f90d0271aadef6436d5830ca0960c54ec52251f20e79b050f
423	1	208	\\xc9e280d6d58d1e9b9fe4f8285e2063aa8231b057827466e4c52e38170e7151b8e2aff9cf5df22eb693fc21eb30360b74afaa0b6a0c084b57deb06e3efd8b8906
424	1	327	\\xb262590536471caca6d0511c08a5c5204de394d1502dcafae8e9e00798ac538a549bdac8d37a7de332592ed55a3d2fbf0a98b0dcb07d868f94f9bd1965e4e00a
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
\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	1646042810000000	1653300410000000	1655719610000000	\\xda3d87c23c085ea852d3e950858a3e08dcb4bdd4711ac3de8c491e516bfca722	\\xd23722df48a0b99187141cb15555b1969f3bcd016dfafcf0e90fd6248d64aa678d4f2ef9f6cb187a21345ee88cbf7b1f32058e7135145cc31b011cb7cd0ac102
\.


--
-- Data for Name: auditor_exchanges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auditor_exchanges (master_pub, exchange_url) FROM stdin;
\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	http://localhost:8081/
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
1	\\x495fbb469c204208eadbcc29a17a8d70979877eed9799d834d0b7b478b172c6a	TESTKUDOS Auditor	http://localhost:8083/	t	1646042816000000
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
1	pbkdf2_sha256$260000$nzUGLYGYyUuvLGXaO2jE1W$HIYkuoMKcJ4Ozf5lhSJ6kD/ZBMxd6jMRxFj3XuAAeVw=	\N	f	Bank				f	t	2022-02-28 11:06:50.47649+01
3	pbkdf2_sha256$260000$SK6TaFNJS9psx3bhIS4BZD$AwQb0QLrQFWimZ0G3xpsK9viJaxobYgiPo2ajU+rp0A=	\N	f	blog				f	t	2022-02-28 11:06:50.660968+01
4	pbkdf2_sha256$260000$kn865xa1cEMv0QzeIXaqmR$YzVhg43JuC45SMAjr8P6SK7/bDeyDmJQZeotjEsork0=	\N	f	Tor				f	t	2022-02-28 11:06:50.752583+01
5	pbkdf2_sha256$260000$LE0lSewFLFxNRwA96MMqHv$z5hDfGMvdaKHoyjOzf3huBd5YZkcqufVFfPyrGvnBqE=	\N	f	GNUnet				f	t	2022-02-28 11:06:50.845214+01
6	pbkdf2_sha256$260000$LLYrAyou0GQ5DGfLfTitVb$3AP3DUcXnLt96OX9aX75r2KV55OO2YmZq53HSIt9sPE=	\N	f	Taler				f	t	2022-02-28 11:06:50.940065+01
7	pbkdf2_sha256$260000$GxqCZQk7DWxQrU1Y0rsFMK$LW7n2FfclgP/wkhP/0Vq2/cXkkc4AHrU+TxCLZM3MDo=	\N	f	FSF				f	t	2022-02-28 11:06:51.031617+01
8	pbkdf2_sha256$260000$nz33gLImJEZkvlXBxzhAn6$Sc1Z3ed518uwoLXcuw1oCXcvWFiddgy0Orn5KirONZ4=	\N	f	Tutorial				f	t	2022-02-28 11:06:51.123881+01
9	pbkdf2_sha256$260000$NAEf3O85N4x3IY80EgcULi$9oFAeGtXpzrznKdjN2acaUgk7YueOlEqhb+c0SZMuuI=	\N	f	Survey				f	t	2022-02-28 11:06:51.215689+01
10	pbkdf2_sha256$260000$fc0mrxkoGGjClRZeEuUEVa$H5VAubhz2eo4IdSN2hiKar1hbgPA54jx5eriWVbi/n8=	\N	f	42				f	t	2022-02-28 11:06:51.674234+01
11	pbkdf2_sha256$260000$m4kZFbHaFAtx6HMCKQZeFg$0XWhNQXNX/d8tXHf3c4941y8zExJ488/jtMd0ZxEoXA=	\N	f	43				f	t	2022-02-28 11:06:52.13049+01
2	pbkdf2_sha256$260000$vydipQsUrQ9j2x8FqtLdPh$Mc6J3ir5QB45nBj/jEZPeB87PwQeksUStapPRsvGSuc=	\N	f	Exchange				f	t	2022-02-28 11:06:50.569036+01
12	pbkdf2_sha256$260000$AgbwHf2JAtgIPBD8ICrKYV$TmGw6PS0t+GJGJWMa4HRe5SVpS5PZ+4U1yyQDrq8d0A=	\N	f	testuser-oj2rpn4p				f	t	2022-02-28 11:06:57.960287+01
13	pbkdf2_sha256$260000$DtyGa8e7ZT8k2iJlJHVtMJ$5S3EmWbjFClISsk5q3VbL+uZj2Pda9SjYsxc2b9/KRM=	\N	f	testuser-refluoxm				f	t	2022-02-28 11:07:08.341213+01
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
-- Data for Name: denomination_revocations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denomination_revocations (denom_revocations_serial_id, denominations_serial, master_sig) FROM stdin;
\.


--
-- Data for Name: denominations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.denominations (denominations_serial, denom_pub_hash, denom_type, age_mask, denom_pub, master_sig, valid_from, expire_withdraw, expire_deposit, expire_legal, coin_val, coin_frac, fee_withdraw_val, fee_withdraw_frac, fee_deposit_val, fee_deposit_frac, fee_refresh_val, fee_refresh_frac, fee_refund_val, fee_refund_frac) FROM stdin;
1	\\x00045be87a6207193238adc01d0557ae8b62ab60b6c5c8fff8003f0faf00e7c0e41a44b9522968f2476c332b40642c4cc0c9861db92d5b4484786d82a53fb08c	1	0	\\x000000010000000000800003db7dcf591d67485a476450d6f30479ca91d21e8e04505b7ec161fd7a3d3a38b8c2811d6a6d6ecef469934889d3a4445b80caef47e3bc8f4f78c6d512ed886321883443da37039e10eae75cb87a3b3fe79ac0bd8a5c73af4e65896a70a639eb60858f0e75a18b72749d7ecaf0040e5bfada3d01b2b0a6664ca253da42f780718b010001	\\x40338c51c64dc17c1896ae6413a6a0aef969f835e5a115575b3bcbdcedb7fb6172610e0a1f0be056d41c0039c19957fc20b2729ff1975d87e75f11ef57173408	1658132810000000	1658737610000000	1721809610000000	1816417610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
2	\\x0010f4762159007288367fc308b21e66d8e13d82ebc045ac4aedf878be4ed5aa5c3823755a5975f91cc27460e6556889eedd6a688fd25f4676b0d2fc0a819437	1	0	\\x000000010000000000800003afcb2d13fb25eabdb1ca6b46bd588bcb58124bf7d3011285db917c8670c5268aa97f9a7d464f5b2fc36125d0aafcf935b0b4413f39a27c0bb34846736e27279c1949932fff37499e23646d24b0ced5b514ec15e9c52c98945e0e4175716b0285a52270155e6a858930435cd740b1575e9a4a7e008ee836c9f2629857774221b9010001	\\xa1e8f7daca98d01af713054d1206efc4f175faa59757dd2f7df40d0897e4d9d776bf7daa962c1ca19d9dd86ad922eab1a34a56f8e81ba6cad1f130956f6c5e05	1652692310000000	1653297110000000	1716369110000000	1810977110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
3	\\x017c9fe087773b6ed7d14f347a2f32c831ccee7f87f4c3bea3db9385cea041ecf62bdc66090bf938c8334b48a58b7de47be38fb1d661121439ad9d4fdcf096f3	1	0	\\x000000010000000000800003d861b4abe369cd9e81ef5887df050ac758715d607f5bd54a37e5abf91659ac0d33e8e48bddf5f9334a1bd0d647093bcb57acd63a76ae8c39eb7fdf4d2bcdf37754833c4a8ec90d6d4b3b3580a075b9648d8a123f341784aed5661c0b3ac4fef13177a70b41f9da8af0d48861430f2ab06964102aefbda7a3a5166a8c991190af010001	\\x5227ed1da5b65206c79c4ad29e0d619c088d8a0c7c79e39009584addd7db3b7a51503e02c370f077556dc3d576a61b6662e64d587424bceab1f8b4bc4a27130c	1661759810000000	1662364610000000	1725436610000000	1820044610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
4	\\x05fc3f9dfff3fc85c5923b3109acb359f9f449832d1b12e43e18a3aa6b274e5cae32d31b28a695681e4912a2d7fb1b83ee9bd63f2a730b7d9101e05b8372809d	1	0	\\x000000010000000000800003dbb31860c9b2832929645713648e54881bb85f548738c7075e7d20d09ffbba969fa227b5138ad7b57c9b24b432923036c46c7825d789a5dd11c70c23c667907dabccb809d21af128788bb30231d838545b8a1502daaa73f55decf52a7748b1241e8d567b93802010cc8bb177b3dc168312a443d2c7b0b589884a08b722e42417010001	\\xdbe9a90cfe2a7064017ff1c5fd829697ce535cd9af9d554be2b9e44aad0e68a56767683c6cfc26902570dee675e2871c79c28aa100b7fa21c9f827762316a509	1671431810000000	1672036610000000	1735108610000000	1829716610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
5	\\x0684c74dd4e66ea80237cfa07635431447071c74238a0ba8d9283b84116b6883fcc53169e439538ccea4a2152371e8b8ef0127b2d0e17e49f1fb124318ccff28	1	0	\\x000000010000000000800003f57e462cf9e5ccdf7861d52009f8ba634cb7284c31bc1b6a128f205063809456cbcfc691538344810eb7ac21e04ef169d82e527598bde6becd0abfeece87625d372c55986fb2a9c02e4f99efa298e2a50ad2ea684cb45685a43d41d9ac2937e538c253fe0d9a447bf6077934562a346f1f999b0a92b7180c98c7358da0676dd7010001	\\x2c489fed138d8526a017123bbc1c215a26646efabfedf2a418fee5dae1e3711fb92c8f1c9d6ace5a6cefe127a8b32c6c93d8e102a58a05c349d88db1824d5308	1654505810000000	1655110610000000	1718182610000000	1812790610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
6	\\x0ab0fcbd2ae71f409d74991d28b8439b8eca2a9ac66bcf0966705eccee688f946e3317d9d90c1cce2c490184d3b0c8098616a624a6c1171ed06c346acff5d557	1	0	\\x000000010000000000800003de7fdecc72dca6959dc905b1738795892f548614a575c76b9518ad2cae46c50747d5642e7303ea0ba650c39a09f36040a78456e4fc59a5997dcf0fc82a2cb4e7574d428bd80b5a0677fb8e111e2bf8c38965ab19865e71f4d71933f97d3147963874e8dbdea18e2b054d3227962b7af7dcc7d48c030164b5e78d9a2f3551e647010001	\\xd4a17387721e65e45584a7396cd11a1ca17d41e8d8e2fea5b482728a5578610a3294ada07e173931c3f6102cf926b5e3efccce09f015e67ae73ab12ec411a907	1659946310000000	1660551110000000	1723623110000000	1818231110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
7	\\x0fa0a5019fc0c0a57598bb8812e241ac7bf4471bdd8a52f7a953f8f70da1f4f0e883eb57557448764f90c4c00fb8ffe8db83dbe7f59afe68eb006bd595247dfa	1	0	\\x000000010000000000800003a1bd7b8674b40823f7ca9922a8bb5a0a6a007a984f60fbd4a1bce98af1e5bd0ba879b5ef9a1bffa39a2b3c310fe849059ea01ce797439b6b9b051fff2004400864adce6c666d3f07f2969c6d3025817e09a00b7ca71615c62574ffbf6e255b9bec5c0da7b30d5a0393c1fcc0a8ad6dd2f173514673315e740fa02f8e654f98ef010001	\\x849f0e4a2774b7434a91f8e02c2ba241048f90b4a0f2336cab848f38489a6b1fbe8381f191f54a3dd1bd971334d2454114b17e791d9be1cc75b1ecb1989b8705	1652087810000000	1652692610000000	1715764610000000	1810372610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
8	\\x1174beeb08937a4ff7208ffafbe549ca03b5ec33284c111545a9b4006516c3dcd71291ffa9de5e7fd09a11a17c573aad73e59bfbca3276696f9e3e1a6baa5eea	1	0	\\x000000010000000000800003c3b0ba0de60cbc2e2b307e8c70c63adf549dd7c26f350f329f87f80b2cfcf4e3c9a7b7837734f1648f3f8caefbfa211d2ec67c9707a8d04308be159e707e9f3a3593b26b94a333f8cbe742d050d03a064bd002dcf457eb4853089b2d61a254bcb43e18fe4fe6dff364e11d4edf7d53e6310ec61fb77f15522ec1b35c34423d7d010001	\\x5a350723fbf42cb22b078f56c919d2d6cb9607d9f1a5b013fb2ee60e4aea442f025e988c8a96d98bdb85cbf07cd357495a0496c7b93a08d0da2e8613a2bf4001	1661155310000000	1661760110000000	1724832110000000	1819440110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
9	\\x13e44220dbd3a45367db34b26e99c0a837f85224f8ab39091b70bcec1bbe3474e128f7e53f4957411d3941185680913be21e3e16603fd690d1b5f42aaab94a71	1	0	\\x000000010000000000800003e35311c318707a1d69c59ca1c5dd6e842e239362c7d1d5df502d763590d101735af2f6f6842b3bdcac7ca1a9b3c0c5bec3da34ff2fb1f41c35a94b948c7ed0fb370a043419e3aa645dca9fc49681dc377d68440d2437e06ebe4e5893ec742a1621ea58362819c9bd085e5aff0df5efd60eeab288349d75fae3bbffc00e809553010001	\\x128420e73cf1eb66b175f92ff1667dc742c0992ae31d1f1a75021979a88df986c07f7a9a9ff47ca07ec604b4999246f216d98eb41b6c512009c8b499451b2508	1665386810000000	1665991610000000	1729063610000000	1823671610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
10	\\x15a8ecf22e5ef27e7eea5e6fc0eae886b2d03e7ace7f94250295c4cf056dcc3cc94e0ee18ed8a30a68ebff77cd18c43728c05aa3fca4a0068159657dc08c0ae4	1	0	\\x000000010000000000800003c42b4a775c7f70b2a05f7fe939a9abec2cf2328bc406bc065ebf281068822714c795bc683433c1cc01d182758d0c966e04fdae6cf43fe97c93ab8c90e8005e6b29640e8ea642aad1c72affb94d76aebf4abaee8e72c1827b49314a89d30e4347ff870cd0b11c384022a365848fe47db0390b2d196e2021b8d3c66168be231f3b010001	\\xe4cec14e9ebeea1933ebf6a8de3ff5392735dc01f1f7943df9994a226509b5cbcdb23f4956eb444aa726b0617d0c3c4e2911d5fe92c08ff474945c5f12b3cd08	1655110310000000	1655715110000000	1718787110000000	1813395110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
11	\\x156863246d0eb8a0707f7fd300c472b3161443063da6601bed2a0f039606af6a008851876c081453bb46de1bcb13accae0acbe3e913e83bf0118be9870e63149	1	0	\\x000000010000000000800003ab92e6b2bc1678fa69cfad06318fcd8f203d65b8021cf0b87148d826ba902358b229ebe1615d0e4e3c002bc26484b029fd61bd392453142f2446712919ec05240d4575371e4dc0e71ecdadc1cb97eae1fb9ce0ef2f3ca6adabe3e3228d464fc91558c2799f82420747b6ac539e783b19410a9d09a9254c06cecc28dbbe92e0eb010001	\\x773f2dba956073860367c2dc3eebf5bf44c86354c8ae32ac1665831f87589e3f97b86f0a17b4dae050ed49e738b3d9fc924ac604be5d8209c4c2582a667ef302	1662364310000000	1662969110000000	1726041110000000	1820649110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
12	\\x1598f78ecdc06222e7be66aed042e44c86abdd5bd9d7fc4a467a402d259532c994749aca59406de403f86121bca729e2d91700750357331f3e8fc5daed81d1c7	1	0	\\x000000010000000000800003b440c024120cb5a98eadb64cbc6b61363a45eecf6a3179501babe426d4ee9c949f1896f8720c8acaa3b06b9dbb377e85dc8d19bdd460e059437dc4dbe86c63c7bc03f1fdc66ee0a25130d830ff8158a6819ffda80cafce1b9a323696be8a61c482b7c870d4d6a5ada41387e845f4c8a28279132327e0ad70942297292616a2f9010001	\\xd937363022ece4b6bd9684f8f7c5308a78e0b4d638e0edfa247d40f4333a9abed167d7d6742fc2bbec96ee8f2df9fe9f7f99a85c59f0a78c68cb095ad901db00	1656923810000000	1657528610000000	1720600610000000	1815208610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
13	\\x16d87afd64503084783d08ed24214a4f3e737d3a6489bfca377f7b6acc30144b09f104273712ce309459585017a266b5e17a4becb4f0dd8da737c1c8380c014c	1	0	\\x000000010000000000800003c944033dc08d7a4ed8393712e6b11373c41851595acd92bf4e3e43e5cfaa6bfbe847d26ffe34134ecd323fd3548fbdb7561a9e40c3609d081463dbe881a527c84acc624bcb7658c92d792a9059a2daea0743675c64270770e6d62ab2ca804532575b9f278d1072c4188ac5b14a7fe3a6cde77de4b0f19f5134d25f9a706fae25010001	\\xb36aad190ab00f9920f37c6560d299b06c4861502a78498a6a13a2341f38b0475151bc8ac999e19b29eeab5d5ce60d0a999a228316a9c3ebbed8ec7f1a62a70f	1669618310000000	1670223110000000	1733295110000000	1827903110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
14	\\x18f0fbe7c0254ea881a7722cce13556cb4d09fbcc6d43225b58431d12a931ca41447c38f0c4ec254894d170c89b54dc9af84e03262001ca3c14cb037e2099ae6	1	0	\\x000000010000000000800003c4c383232142f4b3f50e32ff455e2c0e5867a4f685e5c6ea24753038e2fa1938527291502153c58bb3b91095c10421932f136ebf0843ea69d17c8579810c43f5bb8852849b00ba5498235227ade101df2021715ca0c6339119c6116cb09bea463dcffc7986e3fde8e3575a5ac76be895925219492a4114c81912e31029271617010001	\\x4ab1b664679f7f4a88f4591a3ee7fb83044ba35da069ba0f5ce49b595c2441fdb6b7e9472992070f00a98f4fc93b45d320affae97f9f21aeb4875385c655990f	1668409310000000	1669014110000000	1732086110000000	1826694110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
15	\\x1f14e8e98eb83aaf448dc3a4acb00fbdc3ebc840e89e3f39c5c71d011373c7037748cba88a6e0bd54f0ef72955b2831cc9b7a45012900a1cfce5834fe20deab3	1	0	\\x000000010000000000800003ecd46eca932bda329aa442a7dc0e30cba70824b59514dc4d832a080f75518b3772bc656a7ea428d8d7d9448b8f359897c7fc4af802819abe9c88975e6814f8c3a6479210e9a0fbc22fb566fd1df269ee50819331a3902c48585197568efbb3c0d9300e3e09406da8f9022eb057befe47341e001b869c8a89da563194a8c82c07010001	\\x8ed7a01e901b24b08de5168cb350678cb86f9da366231e9999637b71994f20a6053caed9d29385a92aa6705db150dcf87a2a8ae628cc28e475579db83915c209	1658737310000000	1659342110000000	1722414110000000	1817022110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
16	\\x20846fc6c8d3f5298a5f0a6fd766a56c81acebe0934f15a30907d02fcbd074f3aa3819233e5d8a9883173bea57be41f1b6cdd581607eb746fd3b871e1973063a	1	0	\\x000000010000000000800003cd343bc9d1c19ed9f8f39a22b00ae03a2479526c87407f34029dc5e0d6b3cda523df32890345b01f70b4e8882ae2587424247091583ba0a174c6a9186a0a51a096c2762add15fce0052755aec39b988bdb9081cf020d1c43508ca23734a31caba94cc21333b14a6febce9700ae866cfe79fb16a5524ba100bcbb803717863187010001	\\xf8017f91ec51afc3995c23aadf709fa9cabdfdfc47a478e515faa7bdd3abc32311a218e5c565e9fbe88a338680fdc1c83d5d338da3ab5c1b90d8eca96758af0b	1673245310000000	1673850110000000	1736922110000000	1831530110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
17	\\x233c53fc53e4d79b51240a3c2c02aa84af81b4944efc6230f85636adc6378dd387ab97eb5b068a96503271683c19ed522dcd42df8a24200407599092384446de	1	0	\\x000000010000000000800003c886ae89a32bb7a3e1a3e4e91ae2b0a7106eeb64d8ef0cbf804e0484d6dd0ce43681149a26e90338a8d5fca299267c62ae69fcf074118e63a884a338fa20a872c554907215ec537c3bbcaedcf8db37ebb929d3f5220e5f611349bf3a59f02c79b2c9550a54c12788860c9285fa1ec9339cfaf0a49edff37adff48d508d03673b010001	\\x0cd8a983ad3ced37ba7d2fbacb13bdadc835b27cb43cd6eea3c64bbefae7584895394353953e25ca61c26a12446d4e7aea80d81e832c05efcb02f5933f2b5b09	1661155310000000	1661760110000000	1724832110000000	1819440110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
18	\\x258c39236480e81b943c35c6f4451ef5ac08093ea1a915c3771733d1610c031e269434686f048437496153f283095b4d58b24b29171ad4e9fea2d358feb6915e	1	0	\\x000000010000000000800003c5a6c090609b0b16d31f14a414f20e6670fc4633b7abee9744a1fac6fe46f9fc596ee0e632a9c2a7374cb24c605173e7405090286609dd28386b902d833bbc98b35697e1a3863f8bfe664552c607a9d088eeecd1369e75db012791f2daf7631115dc420fb6b2555dc02597d6fc72e8913d06b785527c100f2d58235fa80099f7010001	\\xdacc6184e0b5b70550a518e600dd0e80a15f8f726a2b30f25ecb8872aa78c4264692f78cdf7bcf2dae043ce8539cdefea660315bc18de57d6ff5be562d69390e	1660550810000000	1661155610000000	1724227610000000	1818835610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
19	\\x26789ad229941bc0cd75947c302fbc24fbbfc69338d6c96f77374c1337c6d134b157debdfab4039efb2c30189476f5c7717a1f34d3009aa64d46278f7b6dbc72	1	0	\\x000000010000000000800003e0b068493509e172f85af19b6b0ee3e79a69548358ca3c367b1f3dd84fdce980547fd423aaab1a9deb95203ef2e5300fa6d7977a1c53d2de90d380d8ad6280dbf1dd3e4c993adb639c232166adf6b00363b3a8caaeacd59670cd13235ad2b8fbe782604cdabc765b89276555f69e971ce2b56d099e4128499d129d5ed5bc7b0f010001	\\x5946d55d935094a5478fd5b4e4fb5d806952238a3bc4d2b145b62e3b56bc0f73bb2f22afa42a695fa7159518bf3bbed94764a633cab808a67153d379f8e67f02	1671431810000000	1672036610000000	1735108610000000	1829716610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
20	\\x280887e760211c102277c84d8af5fa105681ee0fbe249bee7f6406d9d2b5db73dc0232e97347d703168249d47093bc83a4971460d3084081c6a9bd3bc741034f	1	0	\\x000000010000000000800003b1b37329215b9b4c7e0105c5f94987aaf46e531b55fffbf967c79cf01fe813140bf67f9acdc020a7c03072427acd0f5087fea11765665af3849e96644cd10e33c28e2999cbd688735dfa84f20ec413db9496fa80763325d9d68079a4090d706ebf5d9f07adf62efb9cdb559ba38d90e605f8ecaefb888ce275977e1d4ebc33c1010001	\\xeb610a8cdcf31169e0aeee845be7ea4d47fb56ad59684049cffff9e5eda5f79952b257823068c4132d09202ecbe05dd34a4bde51a95b2e7d32a9200f59fc100d	1663573310000000	1664178110000000	1727250110000000	1821858110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
21	\\x3058c27246a9aa965aec4313b891c485401c8b6d8a47f37b5d88c880d111fc07571b196253f0e8074106b128c74c37603ac80a1ddb1c5ca6be3271e97088dddc	1	0	\\x000000010000000000800003941f74dd6f2ce62e9ee1f27c183c59d58c28e79788f132920247c71603b1ad2a49435509af21a8fd0a6831685f6b2116c0c69b00ee6b3e709f3c0fb9f0ad349709305a87a411d93a72819283007d0ea84b7c17476a39ca7df20e8434f70679dfd517ec40fd304390d34c8399bdb21f9c1e2caac004dc53ea513133a033707393010001	\\x84690fea8ccaef93d23e8859667792037cd9d52a5f7d8eedc90265ccab52ae548277dd10131c4ec7654081879256c3e2442c400c315733f6ba0b66c3cbe09104	1652692310000000	1653297110000000	1716369110000000	1810977110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
22	\\x30b0a56dd4b5f8c90c03e2877ba6779e673f1a7ba0c0f99295681dc6a25797f83f4d0a0084bee80611994a1f2779d6fba801aac8952642f87a58b37c7217224b	1	0	\\x000000010000000000800003c31022dd5054d18a8572f0330334025c80e22cd370ba671b0e10ab0c86da82b399e93794fd6c11d132f12fdc9fdd8970e7a17908604842f677a6866b816e1c80b3b4493a2607e1c54af200f0a24ac12c24c2a52034b23d7bf49d8933e415fefaa4038a24672597a4e3a0f834090543d399f3a95f5170344e495e24ccf09f2741010001	\\xcc64f7e11c73b4ef4dc7acac50a155abff835c3ee396b0045ef9c4ad20e6a7235bc758673d598091ca15294319df7fc1330936a4305fb70a4281aa76fa2ca908	1662968810000000	1663573610000000	1726645610000000	1821253610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
23	\\x32c0d60c7714b05a1558b16c1dbe3e26e84eaa39635e91734cc7663f2b3b3c5311c06e77c5087530206a1af64d130c2b86d534bf97dbc1fd994cdea1723adf5a	1	0	\\x000000010000000000800003a169df19283b4def19c47c94927dc22db7f67b7f8a44af8703bda4967c24bcb9122ef2ddead8ab4af0d96cab07e755e9da942c47f814551e483284e8ffa545f5f7fa025c5f2e8758204c27a43539cbfb4c0e1c06f2fe069774338ec12ba20e7ea8ebdf40864d81f44758b9daa5b7eb1361f66d6d4e3b39ed412fa719a5773337010001	\\xf46d4da30a7522e5a57deec1ce1c3df96eb693db175e13db8317843f63726bbe700cd20f27692de1e99844a22351524a5aeb3ccd8f094a6fb59943fc5f9b6b06	1675058810000000	1675663610000000	1738735610000000	1833343610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
24	\\x33a0fecc723046d5c57b152c5b3b13f991a48a28a363849c1468ce9b7e7f083706e040d41f448940795fb5d06b8a07493e6d205bb4a268dd4ecc26951997deaa	1	0	\\x000000010000000000800003f40c29c1204b3f83df03b5dfc1af2b9b07be544a9958f22004177f4759de5e2b27ce9fc16f17e38488e0138fbe309ec5f3cea343d85d6fd2b698a675f04205d7f36794cd4ccd57f25c395c2bf3aa618ba3d5bdb40f4a0b6bc1f1c29d179e89d194c1b53e581e01a899bd50431f4f74f3b2538ac5119317ad882b232af183f773010001	\\x4042c720ea6866165e835f50d686c0bd66c5eb5bfef4a7783a9514a2a6cab9a7c02ddebdc0fd05162f0d1483cad5b13350aeb5af4be873bd38cc7e10879b5d0a	1665991310000000	1666596110000000	1729668110000000	1824276110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
25	\\x46986b35788126ee8d3112d60aaf6ec963c42ea67a6198b79130c58a7c3c12a5da79306cdf32a4ce4141c2c864e678af1b4927d0ba91487ee8901ebf696d952a	1	0	\\x000000010000000000800003b1986ff9e6c3890849367cd76840da46aae541842ea5b6a49d51484a5a41a9517a6da91e7229b2226972bf218400660b8349aeea2b14a486c87d8fda544c29b42671d54c55b993cade83846941a047db8f3c0d05eebcd684e3cb21235d1d746812936b4f2f5627c77dad79d61ad0bd148268fec7053abee737090be763bdcd7b010001	\\x1442a3bc49496947853f6fdc121d3e6447a367f0ec79ec7bf167a30e05956d15d34838d7d1c222e7bcf264f593e5e43bf69a36f41afe471205cd3aa7e20d5808	1667804810000000	1668409610000000	1731481610000000	1826089610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
26	\\x4768cdca68dddcc94838066c84ea869d5445bfe32f8f2724a168d384879e3143d8c8843f09b1a00f76462e3ce4f3678bc00fc7c64afea3c1603bedbf0771ad31	1	0	\\x000000010000000000800003b54d5afe2c61afa9aeb7754c3583f160d0225b835763e74b4295ef6d3356df09b1d0ef5caa6f022e335bc61860a36cdbb31722a1e64a8db7a00a04d3b935ce90e84a1b9151fbe6a4aa3b6409227c22d88065abb21315d070c0a4abee410460d284e51b340e98593af9706a60d9800d3134842c37b3c82c33ec76d5d592c73739010001	\\x117b29b4600e9cf863ca03cab922fc76e51ab93889da064f90bfbd0dfaccd0502c65975124ccee22a5b38344590b1e5727215dfe1d01f2d6c38a4e4bffb18b05	1666595810000000	1667200610000000	1730272610000000	1824880610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
27	\\x4884bf9993c00c74ac350b2f49a467c77b11707d8201cab984840498d4efe0345ded7a214443b7fb5ded2a31039248ea3c81c13c75258d3ddc39a354e44ca4af	1	0	\\x000000010000000000800003b074e49b88243de054bd4f0db53101867e18f3b94033ba08425bb500f2ac37d8843e5e5f0397fb3d2721d8d23799dbfdfa9456104592a5024bef5ab9c601b4cd67985cc1c43581256d6900c80b160c71964ce74e414685d38fd1cd2b1e2c6ee51afb9221d093a7f606e388ba7ec6128024f8fd9da6a0919af952597727a5ddb5010001	\\xc3256c7940068728c2e7d26fa824fd1619e40c78849ce2e85d23cfbb32f8cdd60142be529a786b1345d0250be4d43ec05b4a175ee732cd9d35903e6498f6af04	1666595810000000	1667200610000000	1730272610000000	1824880610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
28	\\x49d098301a282305fb35e7e1cfa6d54126350024d21506940aef0a5ead9ff3257cb3f099e2a5798140432c045624511682c4a9472afff156bb7ec4c4d4d0b1c3	1	0	\\x000000010000000000800003d2bee7885978d2d65d6c7530f986a0d9ccd39c0cfbfb24684701a37ba11e9d5bd57cd46d8288b04517803ff5e9a3ba41a4f571c5864d2c235486f53be161d040bdbb96d5eaf2ef5ed847e97a220859888926d565fa4030442e89aea27bdab0930b5d65e471738ded16357e48d3b1cae03f4712de35815074d14e02e2f68a0b59010001	\\x829d9615acf3bb6d1f2123d4b6aabae7701f342d96c551710451c6464e20299c1f37e3b402900e5b0bd7a6943174e3c0663e197af27e59ebadd6af7886644e03	1647856310000000	1648461110000000	1711533110000000	1806141110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
29	\\x4aacaf631b3667396e1a8f49e08b0d6d5253ad2a364dbddc91aa8d79ff34e2f31c369ae0c1851314a24b6b2c0c5e6722b1b415eb8f09ed34ca7951bb1997395e	1	0	\\x000000010000000000800003e2b8dac5e210e4a9be1001971097580817988c9d735ec7b25c34202af49a6b397dd724a9be6767c2b0b5a442281bb71b0be7c1faefc708e381b3b5fde920aeb910c60b3828f02435293a5acb5126c4df93e9c49b37e5d6326d37390bb0dc8bbf4ce118f4f1c30ea15f34a137007b7995f25c7b0213acec2f70ee6b9127d27ffb010001	\\x8556da78549c9c57ce4cde8c833cf0960fdbf9dda66a625b4de48defbaa8dd7161a442804686a32e6470cfddf5102dd2efd4dfc2a3052440823c7dc24ef2dd0d	1662968810000000	1663573610000000	1726645610000000	1821253610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
30	\\x4ba4e541aa8893240e8d8f2ca76b87f59805693ecef61e3ce630f189dc14499d6a1180603156e0357dcf54616d8fc396c8b9086d6f55cb6536694bdd222d6bdb	1	0	\\x000000010000000000800003eeab524f1d0ed6e4ad62b733a06dea229df56e3d4f5e901a844da95137a442e9c2cbe3e45e51d57bbde8acc45110849519f844ef80f20977d4966efafc830e1dfda611a5e7862016a627c2c9b3b5551aedfa6568033405652cc968549c95a9bbab4ca212355ce9f4fa04730397e85a00e915a49d3e364687afeeaecc77660bbb010001	\\xe5dbc4b60f4f925b64e2c1e99ec3bd2be1eaff570c2c8287fed6a8dfee9291e63a4998a30572450e86e3c308dcd40a9a763b83fb8f00c2661f9dda7311aa7d00	1651483310000000	1652088110000000	1715160110000000	1809768110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
31	\\x53d432d01f761e03ac230cca363c65628f8f0a14658b81ad103bcfaa9ce4922d922675b4ef80c64d95515c31eeb4db1cf34d4b94dc77e83cb97f1ace094ec658	1	0	\\x000000010000000000800003dc0392350aecf5c2c4364e965b626897caff886ddc2ca6e0bef7b7ecbf5b68f5c26ffec09e3a52179de9ef73bffa67b3f6af14fb10696f2d11d798bce0da160bdb0addc46d940bc514dee8244f2f1d1572d73f4f005c54e63d5646fa1dd168d017e8cedb67b73eeefa2109c4e83623419f7ab5d0def6bc1e39108dbd0385a01f010001	\\x9dfe10948d19a66fd81f1f2c8a71cdb90dacb9f9a21d203c4df7793e758ac44d620984c95b8a47024c621cf02c165cf1414deeb6a05a4797139468629a81800f	1669013810000000	1669618610000000	1732690610000000	1827298610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
32	\\x59ac639ffd8f7de29b40f3775109720b5ffa8bc669495907af906aaf3a396355f37b8e7aa626fd1a5cfca0d6c3ec0643677003eb5dc786e267cf20205f5cec30	1	0	\\x000000010000000000800003b4ad9995f9916ea153a8473ffbd9131ed9bf6e54f10ab62997e926aa5380938e8cb73cfd872e3baecbaac7ab8f9424853bb2a5798299d8604bae3d12a4b5787f45c5e8576a434b8bea1665573391cf6a20bb5a41880a83df743e279da08fd018a537afc8b9e104837a1ce094fe0ea13fc7c61e1b8156232f6d1d3ef5938227e3010001	\\xe9f2a4826376d5c611aa2f45710e9eb1ea8c2f269e200d5064c698b791bc806c1e6d3142e2862a9f918c5c483d32f181eddd319f7af3095a6bf3b0d24c99ae0d	1675663310000000	1676268110000000	1739340110000000	1833948110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
33	\\x59e82b7338cf8b405f7458f12043ea63c6d63aa3982b58a0dace7b36b53e795dbc051447db2aedd06b05fcff583cccbaf526a38f096060c0f389f86112c8b9d5	1	0	\\x000000010000000000800003d60b9ea4bfd55517d7b6e960c3896ec2f0d615f8268b855a829a5573ded65c27a19da966d6d61426bf9f145bd752af6d56896c15968dacdd530a7bed0b328a03c46834b63c77d6beb61deab0629ad058074cebf50669780e0fdf5ff409e9cc8f414d2c3d5f415998e59a3f14d678d92d1840fa6b17c0b804c99a5ecaf36eb839010001	\\xd4ab441d7f6398fce345af7d302802659f0962c4f4c273c77732f5b553003c2c81c2761aec630bcd6b8b43d5bcb98a2062cf416fa0e92b75e4b84a99a5e86406	1664177810000000	1664782610000000	1727854610000000	1822462610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
34	\\x5a787f63813ec67c1b6d4d39934ba2d83dcd62db395a710ade0d3221953ea2f0f33dd6f14d72541436cd8a02f731453ae98f2e9903c0f24adc3b64fbc4f13e2d	1	0	\\x000000010000000000800003afe9939bcedbd098be4683b40148e9fdc1e5b5c6f1f10152cdec3aef8db45a4b8ec498ad5aa1b041839537073db78189eafa2135522af6f4bfd789ee2c6944d4c123214ed6e1dfac200ce625da3f68f915b28f8c4cd0024c188153708d187e7ee319ac08dc2344c7de585766837eec3e6b1aadfba2b212bdabfe64f93e2c20b9010001	\\x47d5352cf51e77dd24c7f055cf75ddc13485c698ff362c89934b9cf318a48a5d11c648b13dd2c8bc4ab01048dd644c765b8f3f2ed65ea6a0e980af7fb2508f0e	1650878810000000	1651483610000000	1714555610000000	1809163610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
35	\\x5b4c53a1fcc7b452189bf792d711c4a5f86233ace0018b5b0cf601c02fafdfe95f74d47f72b16cf8efa8a19cc2b0bf428e4751b751088c32a668574d51c0a71b	1	0	\\x000000010000000000800003be00241bd0cf5a4e089193459962f128bb2291798c5b28b17acf5cdbd32eb5d138e5e7c45dbe118108e3610871afb609d3761a5ec5fb96a46626d05d1c5878e6a2511de2244dfbbb0b10d90f8a427832a3b8ce9af8038e7ab7bfb6a858afc4b580a2cb42a280e3f64e75a6bf4d447f36456ae9f2220d7911750818045b278591010001	\\x4e1fedd1bbeec437dedb42029c7382aae1b79878583f9985fad1a3041314a6a8c269e550cbfdadcbbfbb4fae4d25e7b01e6ac5534dd533b576c300b41fda6908	1659341810000000	1659946610000000	1723018610000000	1817626610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
36	\\x6df03c7d0a779cd2011f71fd88e2603772c6dc00c724a8d444525fbe1963cfc5ad6cad1bb00472a0fcad816ac32589fb3eda511e3188a595798bb55d271cabd5	1	0	\\x000000010000000000800003d9480a2887e9fd07694ad9d0e01ed22b3fabcea12af23f526a5c03c3cb12ca9c5b65a0a1965077ba39ad40dabc3913c405f88ab15accbeba6d55528cb31336127b59b7f3e17d19c256fd9cced3dd7af5c99be91f9ada1a94156c66340d7993784c4d7c3b1aed2788877347637e2d9b0d6c02e80ea1a985e60d3851f57b855665010001	\\x41a4c551d72c8f0a890a8e972db569d7a6baa56536e556900637e81a4fe68ab82f7ca0d20290d6e311d0cc7d03dec42b818535dc97b504396e2606bb9508c70b	1674454310000000	1675059110000000	1738131110000000	1832739110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
37	\\x6f105d0816b6141c828226833ff9e3290c63d65b23abae9c5e61ed60772e5ecb7ab3565ce77aa913ac2afcfdbdd1b3f7614167c71d53eeffd5edf7cf6a257822	1	0	\\x000000010000000000800003db88bf5d16e61ebccb0989b664ebf9700650895f683597fcb256bcbf080aab67c8e00d3a7e55414ec3a8a9116d283d4aa6f7fcbc149a8d33fe11128c1b9aae6cb640e6287367ba87685a827d3f4be5b65a8aebd55540d87de52da6d61d3e353617c37a172c26696272c3fed34b6e64a4ed556fbd9c5fec16c7cee2b7b6cc0593010001	\\x8d41896595ad15e614b374f332157d9101995bfceb7d1340da14eb56a21373fda4e52b142e27e956e6a3eace9a5e643972e261cf26011778a58ba4a70938e60a	1675058810000000	1675663610000000	1738735610000000	1833343610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
38	\\x703024185742dd9c859495280f1c4a15e9ead298820bfa299e13cc0e3f5128ec4faa0c5ba9b35cc5adc276e1dc25a556fa531d5f16498930f9320e5bf02ec2e1	1	0	\\x000000010000000000800003d45999caa526d60916b7578759c58a89e0d8c8e47865673e52f88b868fc487b9cd6132d56b854b3c895b8ac9c3402e0896b21e81fc63daa89dab7c2a571a37c8e5a4a82d381b36485ca7c56babdd53706058ac4dd2d71b09ed71372f20e6318756aa01ae2c49b418d199840f937bdf5a2451740f505aa968037495a0a3434855010001	\\xfffb4221fcec1508038e39810f90ea22230ab058e68239e461c541e2ca715d97f5e235b24da309b97c48e04f22911b71b6a033a26b6baa78665e9a65c6926a03	1666595810000000	1667200610000000	1730272610000000	1824880610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
39	\\x73acdee739c262e3531a98b491cd16afc263b61e854ddc7abcb45b1062380b9f684b26d3863bab2023c5cd0b2763d1d0e2c059db779d4f47a464cd1fd1203aa4	1	0	\\x000000010000000000800003be18ac9fc19321ed2c63451389a316733e8b77c6d3baf3dad985cd6133e152c2c6e457ed4f79c7b0e5e11b61c4b67519e94696fb47b00c81ac5d97e4e57afda1e74930f4f114938d4d44835ea91afcd51676b578b7978fb759145633287489bb83fe35291fa33b7f502a4261ab40ab3aae2eea56c04d6a851d384199bd07a599010001	\\xf082198f44d109c2088209cdf9948e3e4004f13964ee51b1c7a0cb97776cf7c6018e4537c3882bc7626c7dc40f1b5ffa9453c51d47b02a36ebf71e7393eb960e	1664782310000000	1665387110000000	1728459110000000	1823067110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
40	\\x76a064a5e9e2fbf03f5c89e9d284652f6932d6594faef4e4aa7ec0a862402b1afb4dad95ee88999cf235a5db101194de1b0d3d6644a64c21b9d5573ea4668fcc	1	0	\\x000000010000000000800003b121a3fd874a27e39b8947c66f9bcd98d28b06d87edd22504d4808bd9f384856aeb74d7f9e1208402f44b0054d2e7965e00c260830e64ff49fc38dfeef6e2b60b8634db0ecddbcc8aa7cf66692600d1a38784ddf1aa5d0d17bef06a16da7f46f2b6d35482249c36fc0ea74af5e8382250e257433b09a37749a87fe9ca5e5e7c1010001	\\x88622ce4ba3952686434a26b94f2c36e51919fa82dd0de6e8453e3cf134acd5f8259a3d45a0f6783027fe24aff4eb9a6e1182e24233f7eee5be5f7b5a48d9a0b	1672036310000000	1672641110000000	1735713110000000	1830321110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
41	\\x7714e98ddd85798982d6ef93cd97a206ebfedbb62aaded941ed7a3c0301277d39ca6b347c8d918848e51a82feef8d50d93ce514afd1c964cd6453f2072732dd0	1	0	\\x00000001000000000080000394d922e6a435dcb907776f0c5cf589321812736597a298567cf5d308164c2a655fdb1445bc0421d0f671f1c770d2c4d964d51def00209d51f0a94957f959b2c3f4f6133a52b62695453817e1d76fadcf820c4b23b9e768e3be58120d6967b2880542e2df6b23cd2628a5d4d1edcba99acf5f104dea269025787d6bc9151bd317010001	\\x3ddebc04a831334672ee001b9e97af9d2759dc7f4fd1bb3f037a79baf1ac4a66d38e89ee1d8ea397264d4888dbf7d5d75be43e34165279294792cdd403a6810f	1662364310000000	1662969110000000	1726041110000000	1820649110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
42	\\x7d34a654daac5d94c16587bc3c5292e0e3732aff95622ed8045194becbd5d57b12fbbc0c57a2e6244254eb7878509e78742dab30ae5c4e624d423581c67cbda6	1	0	\\x000000010000000000800003bc68757db8fb061f9e9fb7b54ffedec93cb9509a68a01cbdcdc0300e49db379c4c679352dc45dbabc476b5bdf2386dbcec4d2dac433b2711ac47041676ae9db63e570d7c87e31e1bbcf71a5e6cc8005b6bd7e1ce92e40075f0a0bb3b2dac28e7d7e6251e889b9e165b15e0915940db2ab7103fba24212374bb7abac97f53045f010001	\\xf0cecb67d765d76a29f7ac31bf8508f73f825e2aa587ed0a853580c070e27c010db413e68407aa6de3a1f6c2cd7043dfaf06feb589384b545f5d1bf92218370a	1676267810000000	1676872610000000	1739944610000000	1834552610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
43	\\x7d94b3f4f83afd14cd92809ade99d39b2cdaffd900f70995dc4adb4b5e4b0b0012f667a5a3392c8cbcf05d0e343d3f74d26d319c06c0f99f306da403870cd06e	1	0	\\x000000010000000000800003bda642362d86ca28f0819a1cf91a7a3d55b888b0bf3573b64c6cc1e650990488df97301e13580a27ae62f6a0fc88f2ce74597de76ac561230f7804e7b2af9c5867b9ceaa47df6e2d154591825e685f6635c8bd3e96732909b5dd1364e58af6d7ae36212a36d3fb732d7071f96721ca7c495a35d97e7570e31b27f5016aca6225010001	\\x8376f8c8250ea861d1a6a2b08c7522fe2d6a370b4ba3a147d15258eb230a93140ea17e49b12a842f02502fefbf0474c471d7d0ad7eeaaf865c7aedc2487de004	1675058810000000	1675663610000000	1738735610000000	1833343610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
44	\\x7ee87709523e823776bcf342ebfd0202a4cc5786a8ffa8c596826080db2c8bcee124da8df9308fcbc10ce6bef2c9093cbbf9a488445be6b6272305b7fd723b7d	1	0	\\x000000010000000000800003c99dd9b5e99e902c2b47908ec8a474ff7c1448a1912065f08c9a82b319278509923e2b9c5d98d43f52296fea128a8dc558c548ac4b40595cb9b750292609a5bfae6907e1e720a192532e9c68ee350cf16403dd59321ef4f5b386b89d1ece6df133efd4d48d67f6fecd53c41a4eaa7584b1b2242578274fea0eca10d096cb7cd1010001	\\x62a6f38dff4af0b2a8363050f15de708103b2e692b6f0ec4435367d680a5842bfaff74c1da684a7e4c271415c5f3d8e1897aa3a886784206f64da1ca9aaf8104	1664177810000000	1664782610000000	1727854610000000	1822462610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
45	\\x80c4899c8ea04cd5fd875984adf671df046be4553bff1e85f7a9cbe6b4ed3b787d6daa6f74833a4d5cb580eab27d53919cdbf396f0131ed895e525e1926f8de0	1	0	\\x000000010000000000800003af80ad93d4148069a29a71042407a2281811b808106909659fcab6db3aa0f99ca5d2bfab6ab2c6992719faf5d993fa7572f6f762ea90316ed6adb681f0333df1c3901432aa07c0cdb0c4134e55f944c6ccbc18671c7c85810c2207f7cf2e71dbe92dae597374f89b2a427d54d6c5898ed325e64a97758ce7b0cf487d365e8d6f010001	\\x70302dfaae088200fd4192bb5978676740621aedafbe4f3ae182553fb118339cee9948ab869032e19a93329ecfdef3a9fe75c8d0cb6acacd3348f818d3790b0f	1650274310000000	1650879110000000	1713951110000000	1808559110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
46	\\x8170f55f782f7de20200a961a874b93792dae9451c1cddc81408c6dd22d762f9157d56766b46192d3f55f50769d20146a1f4c7f2b1ae42ec05b0f04308b4e189	1	0	\\x000000010000000000800003d040dfe4073278a094f7f334aec2b642c655c95063775b9ff3d73a2e2f1e9562520d49b47a2df02a56d3ec4f427f8ac3e2cd67bffcfb0c15649b459160851b885d7d47ab190cae7b2010ec44b57ef5ab751ca4cca7d816ac970f2fcbc1aa8247bfa38a447058f2a1e5d54c6a0d6bac89107c307cc579ed83c5f5404317fef3bf010001	\\x986d0600e6d53544eb0783f8dc5b2cc22c8238b3c14451179f69b047e0c649d01dfa510e3a9b21dedf10207409ac8f45d16ebfa0ea90f2654544044800a3e605	1675663310000000	1676268110000000	1739340110000000	1833948110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
47	\\x8478828d2e3004bace02d8d3a9bd2c6d50ed135897afe9b835ee68dc4f434b689ce438735b5d19e70e5a3ec03b33963e1903136df5e18b03753823d7765c74e2	1	0	\\x000000010000000000800003cbdc98bfe13032bf1d515372936da9a214da3734154ee63df14665849702343cd2a0ca3a106a597ec5cb41840ff5be70a18c5053da287576dff8b755e9fdf8446df0b2cb65d7faa46a26f3779659fe306ba821f71c14f9c7f06a1c84075310d30b1b38a742e4d6d48335ab1a98f579293088e153821408176a55d15761a45033010001	\\x8a65cf178fa2c38ea1319756f3b394badd2a5a3b35c98807c7dfce0dc530e8cfce9a17f9ad206bfc0345118065d41f9fe4c30f1f49781fd5673a9b5c4767780b	1670827310000000	1671432110000000	1734504110000000	1829112110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
48	\\x88aca0e5fe73dded21b06934245509e8f3f343ee12e834c44ca98b8fd95869be449e70e9b22aa0375409038fd2d4330f51d56eed9408b6c43fe0ea6454ebc1ec	1	0	\\x000000010000000000800003acb80ca57877708d8e6a42a75b586f32529529f297c2398c10faaee40989af6ed43e20b10084d2bf897b8c673521d3328f725ccc1769038ab3b60cf332aebbb172c839a49c2fcc00a2276a36108c42f5e1b5d11b618ea3980c734b9c09f8962274b04307e717fac25d6db80018c63846bd26ba9c1480e2c6f55f7a51b9762aef010001	\\x341f187ae2d099816df1800b3c5a48d2850e11e81eb49826fb11ceb2e41dc095ca28c9e4a9b45ee665cc2dc73b6ed85bc28c626df644312942657d0033f2a40f	1659341810000000	1659946610000000	1723018610000000	1817626610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
49	\\x8aecd84675a95bbf69bb55138f455f15c5d58d645f15cf5382341a9317d1a1cfbc78d332872d6071925daf9c38e79ee4dda9422cc596bcfbe790c019b15051dd	1	0	\\x000000010000000000800003be4e1899975cc6a87387e5ae9ae2c4f1542260074de3b57d7f9f1362c0b83e8c2e747dc5f09d140d346fc892234d830bf1612732a03022f63f847cd3e26fb472b988444d09bdbae3627b9d2dd4173fa60e869472cf2659ad20318df877556cb0797811317622ca4f4552f59ba8b68af573026debb44bcfd1538f269e6ab3249b010001	\\xab5c577e32e5c3e55b69e863594026140493fc521e535d58e2cb0e99979ee7417107580da764690bec3364a2b4013ba83a4994a38d4e6589848d5a6100508006	1657528310000000	1658133110000000	1721205110000000	1815813110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
50	\\x8a544d7b7cf54e6046562524df05504decb2ccc57c3c48861d7ed32c659e3fef681da50794ab097d32908dac5e8906b2958d7d25cf601e1222069d10cd2b6a8a	1	0	\\x000000010000000000800003a83bbb614f5c812ae296d925f20fcbeca2856511b40133a26e0959c347f050c46f7ffaf9d780e953a77b63be26f5eb978e785593f79aab65b1a931463eae6ed3e8e250a733f8bbf64e9dc6e70a63827585d900eae9f0c2148837bec67e899eb762c9ea2208c742fab8c29c37194121cf8d597b40a6c91306cbdc33e965350297010001	\\x482044a2b77cfd4eefc990c17ab248acd684af877eaa1710dd6e2068c74cde989669d6cb5452586076c84c25d0eef0bf9237154e3f977560dc39034d27adf203	1655714810000000	1656319610000000	1719391610000000	1813999610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
51	\\x8d2098024ec21f1fa7338976e8faadff6e7cdf1a2667f45ae0ba0ff95702c3ac8e60e223c09a48ff1419339ccf383361ac1a1726e8d31606a180c400c5051e01	1	0	\\x000000010000000000800003c594d4263bbacd4d56cb067b2624f6b10395b58673c9cfbfb40d2e76fefd112682f21bf7aae7170ca6a019e43ba9b0c83f599420654ab95e6204cfce1532bf5a09cd5e63e38aa6e27080f0349dadd626bbd8d99bb22d1d2541fe6d58f8fa33f47d89dbf83aa8eb5212cb2a0f17eab3c63af32e7974e97831ef21554f645555d3010001	\\x1aa7504dcd4024d40e2473d0fafdfc0ae6800adcdbcedfc6031ae87dc251219648cea2fdb7934a514b6c5c3c617903f51a1b94d38cf932305899ed756e07260a	1658737310000000	1659342110000000	1722414110000000	1817022110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
52	\\x8f28a9422e2ed39ad3a0044ec6fc90c8f6c73e2f9674e60977506b7f98ba7b523b9da5a25e37a33081ed5c9700c60e773231352f9258e3b2cc6c11e8d884598e	1	0	\\x000000010000000000800003c37323d745c259fb4f81c56b84c721ff7d938c778de76f66e709f894a390e4e823192e0126f67adb4d1064ea8e6b164e310d2f07d70f42333ce31617bdeb48fd4837f6cea4bbc232b85fb745a6383c63caa772c98eee56b4221e586c5d80446f9fa5c5791ffa50ec074c2d1a5a32d4277c77d8d34a8479f57079dfeb3264f2c5010001	\\xcb14b8c3514c2d787ca3ba57a3f82c188a3eb25d8aad5556a11cfb780cc37deb25ddefa775051861cfab3636ce03704a3a7bf7bf70bdc1d9057f0d17a22fba03	1673849810000000	1674454610000000	1737526610000000	1832134610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
53	\\x9754e3596951295ba234dde391eae18b47dc3ae166c798bd0ee83d4ad20fc43f89863d4f0d31b00d311df5abbf174a890a50b627ada3fde0d0c018dfe6d8e944	1	0	\\x000000010000000000800003d43d201dbe767b4a79590a8788449bfce5773bcc85528ca21145d2e31eb51ce86c1c16334642494fca54bfe5f3995a316445600fe6a4b71c38d62a9f3441c7a99fdb37a6690ce0415992e2ba294c194fdf006363dd82bbfc2df94a086e869949b85cbfb3c8c25c7b959a118a5d8c4faa8dce6340f396741b0d2a0e5ab20b6277010001	\\x7ba12b48af33bf120ae94f929d20d1fe840b54bb91f2f67fc397732b475d8a6a038eee657dd3c6efaf7b15e06f6647feb4fccdbd705f1d42d7a6018c7eb9a106	1667200310000000	1667805110000000	1730877110000000	1825485110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
54	\\x98800657494f259c1a88419af75ca45c8ba9de72d2f75c82249946a2d290a3d68e891f776f8298173de6d6af76199f267c82fb3e14f9588154cc9afc587df514	1	0	\\x000000010000000000800003cca733d13441f9766a0406645bf76e9aa9558c0f212192acc182254f948998a8f8859b19acd910618f7e1a4dd52eff58462fa37c31f5a24fb0be4e9e91a06ec2d5996b59cac04715667e64506c646cf21030a3063792ffeff18e9e88d376a5297c772d7399a04d4616e10aa24f08abc9789cb6f843a3929ed2a81a24bb510855010001	\\x10d12be197813f88724b05010efdc4d1dc7ae1a43ba64ce75b455ec0d489500584de9fdc637e82982972978190df017a71016a81f04feb264684c3f2789cd602	1662364310000000	1662969110000000	1726041110000000	1820649110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
55	\\x99081f7256cb0ccc377e1d0e63f5c4c37ac32dd65167795e478060438ebd6dcd87ac54104c0562829053530b47c482fca9c773c3d4f04a283adfab15a83747ac	1	0	\\x000000010000000000800003dfeb98b9458ce709be3b3aa43bf457c29a59cfb1ce531000d28ef2a57c7ed1c52dc54ebcdb4967733f919da4b7201e03918bc419eeb729acb766e8009d1716f5257beb6166f151a01bf1d9310ab37d0e17469631df231da84dfe078fe097b97ea3ed8b9b9e4b49ea9c90c385fa1fa457c5024ea139f5dec1a89baacc4cce3c19010001	\\xf9d9e8a93600920606cae04acda62eecde0652a348bc0393ec0753f6e9d2e7f87062adb70e5d33b41dc8c5bef91d528567a967b733b151d441f92cc38db78f05	1651483310000000	1652088110000000	1715160110000000	1809768110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
56	\\x9e1cfd4fcd2c5d4db275c0f59dc4c33b945824cdd109703b4fb1ca34061277ebd66605d195e00aac20f43ed45911c4966f316451e2caefe305912ce46ded58d2	1	0	\\x000000010000000000800003c62063081c0a713f66def70c539f8de070dbc2cdbc20a4da266af99039ea1e72bd815abe2ab3d4c18a28ad61e020244802b500440c976b3eb67daaed2da8247fc02d8c3d5c9ea04102ea9802b2b54c62b2793f8d41837c47791f005a47a53d06377932b42251c0289a3f5ca560c3814fd709577535bda0d3426c4ad4121ab95d010001	\\xf0ebf7a93fe5e19a969533785327bb3e55d5f85684cf215baec1f226c2e5c56d7bb613042aaf89fd8a65813c0495ca8b6be450f1f88c5222dd2ed60133a2520c	1653296810000000	1653901610000000	1716973610000000	1811581610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
57	\\x9fccde1a48145c48eec83df16b6081a4cf8c4f12506587d84bc8870912c0cad0d1cef9edfb2d8b69478e06824cad647f9f363bf789912060aabee368a968ee92	1	0	\\x000000010000000000800003bd5970d3689c14de0f1c2a02c668f9c71ac6aaa6976c594ddf90f5b0d65c14dc348161331eae5738af8260c363c425a8da9382409aaabab667abad52f3705c481047b07ceac8b9b67200e2310372a52ebcd3e0ce7453eb61ef1dd5fa20ba99ef49b18903167025cfc974e3fc3f4f45c97c41a82f38b231f9db2256f04193e17f010001	\\x618950adb0f8d541b1f6ab70fa192d12d39bf9ed67f6e3d8d24af7db99fc327efcc09051d8c4e573770cd92a83205cd0f0e0475db6ebd7ccc789df2a3e30620f	1667200310000000	1667805110000000	1730877110000000	1825485110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
58	\\xa128aca3b1fb19769b5b8d4c79047ddf4bc0782efd3b38a58bc13f7f68a734296b69a6b083278485bdf0593c1a9ca2a9259933abed65e784787e50ce0ac25376	1	0	\\x000000010000000000800003d5a664cddde20e7de98166bc772584c9b05a94ae9730642a38b8a1b9cede749557d845f03e3f456d131bf82b9f0fcc1b487aee2466cf4818fc6e5b2520bc5f4839d937ec952b5bf7c6a64f8aed872969d9af206b265e11629060e308a570269c4d19c82f94a101c103c2adef43fc3069642fac08e2ae9870da41ec11acaa0485010001	\\x9c887b2567c95411c7b684f50baaed6f3969c0e5b59a2b7563559d4bf547ee77e0b4b2dcc91b6dd42d45d91037a51a4afde48324ad3ba415edf791c85119e20d	1650274310000000	1650879110000000	1713951110000000	1808559110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
59	\\xa264e3f61d9d7d40d3ded3546c84a97e0ae7e8a63da9111d81ba939278f9d43a7a9806f5a50bd327ecdb553facddc332afbdf0f062c384324e0b9ed79f8d2bc8	1	0	\\x000000010000000000800003b8205d3bf91f40d7d182277ffbd7714a6c1625e70be1ba1271477dde157be4cf8ba7d5507dae7e9fd15cd6240b5469e2763271d9a31353b56bcbb23725567dd9355d0d1522f79f10fb3fd79b9030683aa11139c1b57e9b29b4295d1b5e35f257a6a6d861901d48d9830543e81ef683c33d149d49fc58dfc14289fab44c2da287010001	\\x08d8dd923ea79a184a8c86067e23dd3663ea159918ecdbe917333176af87db2bfc43536680d4419fe32e41f69f39ea5d91e24f16afdbae7127e8182107d5ae0a	1673849810000000	1674454610000000	1737526610000000	1832134610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
60	\\xa998430c7f08c8c4cd35c45e249f2329c24168661977d85f9c23e70dd899aaa232561239ce4d90d233dedfca14d83f357d27375816cd18132294030aeb2369e0	1	0	\\x000000010000000000800003a9e7678b572b8415043377e45d317833bd623fe3b75e4bddcf396bd78aa10b21830964e627bdb16ae34b2d350b8a97f26606d261f94d1de13ffe09f0dc0516921c3505cecb375c5d26893873eac9e41b2fc53cc32ff98a2f8bf6e6c61a5b181a71dc958ac56363b48685c75e5d88b58dbea8bac25a3cdec0c486493c2bd360f3010001	\\xe075efd95ec993470f34f6f74a698c5a5fab90dc8eab0d0c39a41cca2494eac6152a53a49f7c8466e8633f154a888c963aec56e7c2e50970c9742c1e889a300a	1667804810000000	1668409610000000	1731481610000000	1826089610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
61	\\xa9840e55a1d29349dadcce13bd47a30640ab4327632211c5341e3c0e1ce8ff8c7e476c4052ac149d63765b8e640d99201bbef13df8c604337b8e5f2a1823b1be	1	0	\\x000000010000000000800003abf2ed168fa56ba9bfd268eaf91830ff657e35e236aeb469e119e155d9c9b2789090f73c3e23a851735414c7562b89f8bd879488d1f9e5e03d9b26d562285eb9bcf7280c5fa4952ffeb361ae71e453f516815f536fa8324ff88c9c779d56ffa16de818c278788b9bb9eadaa1edb992b7df2f9dc4d83d64e5df1f3a4ecd446a53010001	\\x0c7a48250cbe8e262b11da4b5e42653b5e7719c911682714e44f6a0b9a80319b0029a913b77387df509f3daa1d8d74b5d57684cbb7953ba79dc67bf9ec7deb09	1652692310000000	1653297110000000	1716369110000000	1810977110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
62	\\xaa186f4bf9c29bda69b4f248ea1900ee2ef465bddd9b1e73036eb9c04cf2eaa8faefe5866abe21ff4e41888822eee6824056867ddb448e891870cde3c1d6b2d1	1	0	\\x000000010000000000800003ce4338611aadac7c509ca1d47f3317983e6b114ef41401a7ec14a930cb8a99c951734394524ca97518e30ec745713c6624c4342d2afb69c092fd11b4e110e95a211143b1fd4d3e2f29800478f92bcd74bd4176e70e67ec00f7ced412bb9caedd19e2b2fccb515bd4c5406584a8964fdcb5659e01fbc2031707ec344bda973cd5010001	\\x21818be8eee562be6917752d0ddfb1d45bd915a49967b6115e77c603c62d1ed802f75f7fb9a2354357969422918cc62833031836d82db5ce35f4a19cb5229507	1656923810000000	1657528610000000	1720600610000000	1815208610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
63	\\xabc4c5b605097e3cfa89c60151ae0312ac5fbdf225efc87d1b5df7042450532a77228822158b188a5808e0bd64735bfab8fa41d2e9788d3e4882cf76f4c1cc14	1	0	\\x000000010000000000800003e8cdba78d47b95844d1a20e26a1a17ec77fe92d48ac60bcdda55dcde2a8b2c747abe9443e463c321f5fe1a646c2d3a86af4263b58997581cfc440a5e6072210d495fd13b2c03dacfd65ece3536034ab745921a633eb84149fe8a28a477ffad12c1ace794208d7dd9436c11fe45bfac4a9d8ba99ce3fb140dabf56cf821bd7c07010001	\\x8d83eb138328c16f86b28616d839d7a737905d9acb8e6558614ad3d3dd2d6def8b22a4c26a6e8ee736aa1bc962f50e2caaf62d5ac2bee1ee5d8897ea76458e0f	1672036310000000	1672641110000000	1735713110000000	1830321110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
64	\\xac68ec6c0cc327f4fef6019b671b14b385efdd924d2ddd6ee01cf001a5e43af084715b4ce26d5171dd71e0b95b34f4ca025c520c83dcfc05a87e36142d8b5e7e	1	0	\\x000000010000000000800003bd9de3090092b1d153859141d8d3826309376404d5c458f55731eaa5e8e95ad813ec15ab9e0e0e51b5459a36e23bf2b3fd570da4753eb73b8fcd23aadf3732a155137e7bdb7ed734a0a327ee3cb9908b7f80b0316674384bde566b73e690f990da1b730bb2816fd799b5f31715bee9d076c4dbea8c4c8ef64697cd43bfa02989010001	\\xfcb24ba5de953704a7b2f2873fc68cc1970ac76487bc095da9282a3764914ae82b502824a580e8ff2617e87c671d5efbbf7e17d8674db2bd97d605e39af64f0b	1673849810000000	1674454610000000	1737526610000000	1832134610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
65	\\xadb42625b48d4b52a7d89f918fbae18594d8facb5ccc2582f0e9ce0915a8f92f2dba7b38a30b97f4427d81959b3fa9bb1e3845b75a5cc6e631e08821c634830c	1	0	\\x000000010000000000800003bf9eac2a98c10c57ccd6204ba3137ed733c6c921d0f631810eee3e44edba5ab91c7d0fb87305678cfebcb308aaf67c4f2f0374375b5bfb1889ba4e9015480043eaeb059bb9581810fa3b8e1a7282812a36f25714c993536f636d990bd89a1a430cc23f3a50a15fa878a35d9ad439c9b6236ea95fe7ad473cecfb183933676a49010001	\\x8803b7bf72fae99885898821cb4a417799c69c5edab8fdec4f8c8af4a88110f3592704f2b6feb50703fe9643a0779ff661cc50ad3714faba8b2061bfb568390b	1650274310000000	1650879110000000	1713951110000000	1808559110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
66	\\xaedcef6f152268cb53ec5b9aee13274bc2be5bfccbd17ea6099e4f47e5d446aeddc6e24a93a4ff24f52ed120f3e85eb80dd04f482a0c0e046768eabb3c0c7908	1	0	\\x000000010000000000800003b7cbe28ceb9eb3b81cedc8aab1a888fc3ea0d10f31d1da563c554a5fab7f88dae396036929605f05a6216b2dd6c9b5a215a8f2d24eba0c4a823a6d12e175cf6ad2c1b7a883b475f0a74fe065983702cf2e53c2d1f2fba1192e4b054ce405886d1e0e3f755312e1fcacf56a89c739da0db98109d806d38d4ea4685790b9ef500d010001	\\x00d97780fc352638ef9b05677d4909d16e910d72bdf90c4c822e9dc889d50c7e69d3d714397229c854b53eaa8c8900480495ddd84bca0f8131976d124e2f8d05	1670222810000000	1670827610000000	1733899610000000	1828507610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
67	\\xb1100d5fdfcd1e2c42a2fd87be550665a3c8255a41a23add21943a35036a29179576d34a0d8a78b0d313dced61fe86638dfd836ebf98c9fd0ca0678792476f03	1	0	\\x000000010000000000800003b07b6cb4f62bdc0319db49d653e9fc1bd0ed8715e7bb59787a342b879f43cd605410661ee80a8dbde5b021aae83153e88e783644306954173de96f648210294516ddba866696c351e52f52d24ab51a51097546e54f02ce93705d5ddc5566c2ae670af78081853cb3dd24750f076c5e6b8f53ce3a252254f5917ad9c5c50caf93010001	\\xa4d4bfd49a2d1d937ba3bb22ce2de22a14e5514669c00cb7f75704bd2b2e8dd95caca44afd6b261599b3977305811c7fa122a40a0ed4a671714f4d8d7f51d502	1672640810000000	1673245610000000	1736317610000000	1830925610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
68	\\xb59481c134bb78ad795e67f23c5c364176169cfbca597d3daf3e6a1abcf336d643af3d59e4e7905b7d9d04e140aa47b633e31e434e1a04e33ccd9811cfae3e19	1	0	\\x000000010000000000800003a30048b42444812cbf0b653b2d846cde66f8af76562484ef7852d772d381127c521fcf5d29acd22c344de48ecdac767934943baaad5226a79b3d2d7101ff8e975a50568fba6ca60e99a6d0e133e0c4fc0e8ae12c3a3945473891d6b833411fc78c08e801f270c4b964f45f5dc9968b169411ab35e22b64f795c2e25c2c60aae1010001	\\xa5a2b0c2355908ed559615070034c90c442579c2c388b61109d95d638d0921e6381c3ae6ad03444aea0d30c0b681bc91ffe345eda4cc65624639b97a86f0c90a	1661155310000000	1661760110000000	1724832110000000	1819440110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
69	\\xb5fc21e482bc2c4013726a51c7c0a817c31fab5e1a30b10ea08de136952be40baa8a7cd78f4d58bf266ed7c3ca293445b4d94c00f6bbfec57f0fc6b46912e0b5	1	0	\\x0000000100000000008000039594e4dae972a555968268c09d4963a7d21d4c89967a03aca1b2c2b72fd894594026f19c6fa66d3c52fc0c09d48e335bd70dfda61543b654690936c25bf419b1ab3a9945b1baa3044e12016807dd48806b80eb22fa67a2073f886c4439cdd94f4be4af4d4ed898f10c5be86a47a9ec2c8f916f8f0c1ff4bf51927971798859b3010001	\\x3a7e55bded6be69538522daaea3e391d1a598bcc6ab42de0d0eb464548982226bddb732a67d6d370c70817d8ecfd23aeba1e5340d0bedf2024c4c95d1a7bc408	1647251810000000	1647856610000000	1710928610000000	1805536610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
70	\\xb6ac61c54df27d935cbd042e92aaa3e65ff10418c406aec9c105ad135aa4ceb8117aff441a3d56335dcd0cc2d17fff3e448046b61fa425378fe8c8b1951e9e54	1	0	\\x000000010000000000800003f095129440d0eece61f67b84cbdb80f0fbb9c2c95c4b3ade917e5b0cf4708483bc197262c11c649c361a601d7719eebfb7d870856efc1def1ec62f312659d7fd0edb892fd989fdf6def01ae6af531c6acb0492fbfb39113acd7cb747577f3bb20ad8f69afc616c4efde47c4f7c20895e0736986cae655e7a5f8217c4fc2885b3010001	\\x7f0e15c5c269728cd61e90b31ed5a385364478c8dab47d54f1c768eded81d6a94bab4df9fb9bb00ea2b79799e689f106cd7ab9c697e3924186677dcd1ec3e005	1663573310000000	1664178110000000	1727250110000000	1821858110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
71	\\xb634f9442beb3b4a1850cd00460b48df0bb79d419920cf34dff7327edb21a6139aee4a16b9b383ed9e192545658a99f3341148bd31bc97c036867f3a99b8fc21	1	0	\\x000000010000000000800003c80c9fece24c7b99d6448eed400c9fa9e1898f4149f11eb859544997cbaefb63497b9d4caf3ea5d196c587d1b98c47ee7f7a9654f40180f602e1b38ddf575e794a1c7eb2e963f9a7916cb454430e956d0a65a5219b9468db24a39e7d82166bd7278a08b10556bfef89a75aa1c3f294710669639d5fe55492946a95aac9f1382b010001	\\xfa1fc9dc0ba2c58bed54a15d12f1ad08099658bbfbe2a2fa52fc3c37cc7f4a32704e4bf14f8284b8e1166bcc303188751872c5ed7fe5f9611a4b7b838705640e	1647251810000000	1647856610000000	1710928610000000	1805536610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
72	\\xb8e098db4bcf8ecfccaaa0ee9bf990ed4672d86ac6718ef6adc55b27f5bfe9fdb46036933ef2ae48d2d5e43b20c7dc3bc5908f67b440b3089b20230c5f451069	1	0	\\x000000010000000000800003d9696c7116bffaa480df18ccc4245692c4a2bfaaeb9fe91b4fd165deb1adc552ac737a899389eeb476ce6ac69b280adfe0a543bb90f34ccf5b0ff75cf5fcb6b0391b4bf79851b7400da5f993618fb73fd47f726807f4987137f8844e7ea3c99df4e3c45efd57615d873b9c8ecff7601db1d5fa0e6c4b7af07a2e74f552efe989010001	\\xc6ff8344a2ad6b0db49f010686503e71b4e3d67c0a9bc16e15fe3bb2601ad61a160ddf73323d491f3d0a38fef5550640cf25631097746cc6235a733324301005	1675663310000000	1676268110000000	1739340110000000	1833948110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
73	\\xbdc87877c52c11b66a7ea892d17e5c4d9ee6783fc1cf76ce42667fbc3eaf95eeeb73ea24150e24d343dbe1671574d09bc3a7b2b8a5a43e75f22b89ed1a85f480	1	0	\\x000000010000000000800003bf8a716272499f8c53430bdfe7c44ea3fed68d886c703ceb93b1cd4b3e13edce8a9d09afa181f10b2fa571fa4ba36e0f2f40372f8b88878ab4a2e77f99aa2070816499985edb79732b87df76acdf7b73c16e0a05dda0e66230252d8ba9ba42d81bb7318c3dc587c7aa91db971dc2a9aeb1472629da12cd65b87a463d42e77c39010001	\\xbd895456dec24cdd6ef4f12985d688bb9b5a8f50784f303bb53c2f6458b950183a11fb84d21c01a941f5c3207f7fcc0dee6c5f3395ba8da7d75b20e9abb3c10c	1649669810000000	1650274610000000	1713346610000000	1807954610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
74	\\xbeec09cc333ebdc951829a3cfc718f41cceecaba9793455150227a11d4ee2e639d1f12cf89b52a2d2cf0d690e79224e3cf519a8a2596913107d377d6468082d5	1	0	\\x000000010000000000800003cedbdf48a987bb2e3e27b53cb7927010572536b5c388ad985ba77e87d3c358f5c006e0e116dc7ca640db883aaca8c228b82320020c3b853f3c40374989084065bfca32b62367e38c7cde118ecd1f4db6bf675be7ab04b1890e623035b706d4be6975adfcc870e3d95614e77dc7e97ca38d5595af4dd13ff0239bac54364004b1010001	\\x8b93ebb0328d772dcf1c17334c450604240ddd57b5cf38a079fb9dffdd7c11a949a05c14763d8f7efe0627aefcd4e54ecfdc31e076e465def277969488a7a40e	1656923810000000	1657528610000000	1720600610000000	1815208610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
75	\\xc1246601d15c2c0aae3e68ca3dbe316596a79581551c96c16a7bef17295f3afa366450353634e302e3238fbd087ba5eaaceb15c0c2519ed5a89486e1b427ee5d	1	0	\\x000000010000000000800003abff4cc2a5d620930d569cbf7b1e9722b0e882c68770f3055a5a4624a5c52b03534af34bfb24c6e90cbd6d3c2c35055cf882a95ba29bb1ba46c579368d0be52a4e9a3d62a2c7586b65a16ab1a483ed1168b23b13303fb894ecdb526443c02c003af358304b597b879fad648de67c2320249d0c10481861a91b8be283bd98d6b5010001	\\x6ee81f0c589d3e84b59f7c5b6badbfffd438653dae079f99136a1803fe7f0b42da38c75aa664f138ce6a6ee486ecec98430a6615c58d6c28d4617a6b7e903c08	1672036310000000	1672641110000000	1735713110000000	1830321110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
76	\\xc2d47aad04bb80ff8e9527788bd1c685629999d06127424a22cd3bc305195a59d280d18176e402c883defd31e9b7d95a9b154fb08bb0e515c41ba1123f0d4325	1	0	\\x000000010000000000800003b2c8062fd6b62a2196e87fca754e2b4742198f72cb97033465c8bc1b3ed60303ec6b06ddf9e4a3758b9002b3f6b4ae090e762e7c4beef5eb5c9f7132a7adb6769b3f375d4f508eb7e716456a844cfedd05575798cebf77f26fccede3d9a92ce650f9b192f764f8c11d81dd5bb6c329bc4e37e224922fd2f707bdd95db99a033f010001	\\xb1f580f14471ea7e1b8017f4720da939a424376cc14271a91bd0acf2ec6a53f10923adee867fb38ae44bcea6f0bee6fd186afe6cf44c6519cbb37d1a6aaf0a0d	1673245310000000	1673850110000000	1736922110000000	1831530110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
77	\\xc5ecaa8b607307e53405c01a39656a0a08f3e4f095444e69594e806f2287c7dbbcd9fe483b01684e68de8f11411f6e00f0b19c4f387b0420b88c0876dd1ea217	1	0	\\x000000010000000000800003a4c59b7c7226bba820465bfedffe1a778640d62561244bd237800e6dc7ddd4fe0cce7509655a1b4f90f9a72721d1c415827ebae7db4a79ea40298e8953ea31d33cada36a771e0c2db80c217cd29e92178bdcf4d72de91260011b36b7f63da1d2d2a9c215dd86c8dc32f9d28d944d5881ac3a0ac665c1d2f62c29b06dfcd3e959010001	\\x5f80c349169318d8b0f518725f19205e78a618bd35da1c2954d2f0f6f357d248e3be4e8368d7e6d0d4481b75973bfffd7bd96c3bb621b7aa64d4422ead633f0a	1673245310000000	1673850110000000	1736922110000000	1831530110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
78	\\xc81c12bbe7923d0aa99195bf42b64143fc675913c26cffe57310f2707b20392813c697b1c35eaeb081cfa117d8a529fd414daccc558336b62e0ab884908169e1	1	0	\\x000000010000000000800003c66e45068d3d1e067a98fa5ff1d9ba4c723c972e95ad144daba00a5f12cb192224065f6c3cf77befbff221f5a70e5c5c96da75d215664a872acd48632a9edfb3861f4c267ddd80731fd6b8ed810aa3a321b53afd9d852af282f2b47e42ae166a188f678a08cbd34a7f87222c0de85ba1e04629a5c7aef66b8b8a64c5a7f26419010001	\\xe3ec850f4afed0cf8388510e669216ac3d9244bb3a30bf62f7631e6e0d5543b35ba4b325f0bde67dc47cfa3400c76ad27973eb3455ec59e82768c2e0aeaa2f03	1659341810000000	1659946610000000	1723018610000000	1817626610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
79	\\xca0cd61833b8df484d1c18991e0de1282e34ba7a8f37c47835f4cd30701045c88c533740df58799ba6a86046848ba7dd879b03f27500ea4e92dafb81d8845b3a	1	0	\\x000000010000000000800003a739fb7f70e0566b9601e96431f5ceff3473d1981b942c94ba1879a224d67653067aef367295a3f9a536ed07951696dfcc0625f1c9dbadf30dc773b5bb88f4a2b0985d8a63fc5223e94bd0ed5aa8efbb830a4a91d47e8d0f9f0d0d00c21d35852e8d4c5c85fc8f1ee50b4a003e8c0254e1a03c355a7991d409d32562a0974321010001	\\x55f59fadc1791c3c7ccf4d38be47b448c97ac9faf0a896b4824c1d6de06ee765af791d81caf5d92b7823e94217a141b7a8de04de45fa8dba63228c83e3a52e08	1664177810000000	1664782610000000	1727854610000000	1822462610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
80	\\xcbf4085e4c93bea6c7935311f77c8019ba086c0cc7deb5b5754f26774ba77aefff9df260f415e7d9731104c03aef1480452b633ee55d101b2b45238859685bc0	1	0	\\x000000010000000000800003aada556523c1ea62c9d10193036241692257112c95bae528e45859d2ede9e5f5c56542f1dabbc9d24fb8ef5895574b188497a249251e8a8049efbe3d8e4ed4c787ca292258c5db15517dbbc674191e15e9b1f1730a4c34d36207fc982b3277da14ea0e460dc1631df505c04a41c199de6b2abc9549e95e96b29302c4e39f4b23010001	\\xaa16a5b764fadbed59fe273aee8afc2af5b58721325445a9d8ed5411efd72d3e73d56a6eb63ab194db4771cb154063b87388e1f9df66a0b54f1d28d25506190f	1647251810000000	1647856610000000	1710928610000000	1805536610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
81	\\xcc48e13d48c876530ca1fbeb93399a87e69e4b36c5fc18e42bbee07ea542a260553cf5b69956c60bcbcc0e5e14059b852af7a7936898eba01538740b929a76dc	1	0	\\x000000010000000000800003d0868b2e25faec2a9228a67c693ebeb1aaef3351cdce9f4c5477e65ba77e37a92d968752300faed21f8f1b3a25aca78724acacc3d57cb846837b4db34f510ad5cd96b8d64df1ddad884bc04bf77d4a900898e1e2087e06bf75d1e15482a632d0ec4a126171940c27a03456c0b2ee48ac81f9c61b0c0d4dbc62fdbdf062976dbb010001	\\xbc1b20b1a7f998d0d10202f04927c873aa639fb0e8bcd44f3ec2dfd290998ca22c8cda3b36c8c6efc7618d04f1451f1909113274b1005e45bde84f5de965da0c	1658132810000000	1658737610000000	1721809610000000	1816417610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
82	\\xcda8036d8557995f31a809e7aac666372de38e161cfc3ef020648c03ac9cc1ecccce014ab5dc9b88f19cdc769e750df527b4fbcbc5524fca50825f5a2624557f	1	0	\\x000000010000000000800003b24317f64d39002046ef06ad4065d3ba61d064fd41f2194458e05e499e0fa51d36709725e451e0ec332c9b2c4c4b2d1fb87f2c39287c46291b8aa5d13bdf83922cfc7693f47512948400c5fbed21814f460dce9df57d3f354b7d6be1cd959bafa15aa1b8dc9284b0d7edcd1ce4cc9f7b3205aee97216ea053d95f76df461ff77010001	\\xad54e169e052af48a3a6bbe54958c77e009aa937f4f75801ce2cff2a4a65af9fe3afb0f3d3b2cc4defbf1b25a96de54f58b004295b7f7a1edfa83d8f0ada310c	1649669810000000	1650274610000000	1713346610000000	1807954610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
83	\\xcdf05aa0d61c40bf403a6d77e893118cbf0ca734e669cc90e83f4979d433a759452c5859a7a7ef3dae88b973e7a016850e7007d6380fa6ae5e8dd1b547310250	1	0	\\x0000000100000000008000039746065c3e546c26dc199a614ade660cc2a17c29e80b85012507a9287866d89a5df8515b83b85bd3bc7c3b5dccc9a5f1a11398fb8d218d16006b6a404ad9c195b10b30e4bed4bd263cf0223e2129a256c713127f307ff102ba4e4eb857c78886da24bc0674f1b44bc2bb0a30e33f84702ab004697715777c2b87a9ae21f2c139010001	\\xce6d968622f7898438679afe854c193dcaf20a05de1775c47a9941999890e3778a6bd8e2a96c47f0f3869a810a63502e99bfe22c1433049bf075b4c4f3dd660a	1646647310000000	1647252110000000	1710324110000000	1804932110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
84	\\xcd40c0f3829ed066a078d67e619cccf22caa54c1e1b774a0e6ecb0fa86e51bd1d5067c4ccdefc14f5ea05ba4c715891e4bb1e330d1285408e4d2851d63bccb6e	1	0	\\x000000010000000000800003b9c3a3a91604484c7d4b0c1cee55985bbd264b1d330a62953212394427f0b61c3f44822ae253c14a9fd1d8ce10a11c01d447feee7a71e1c483d9e40d0cdb5a97d64c857c0ae534d81274a4b109192eb5474c6531b5c6e67836bad2710d1140958d4ccc86adb3cdc5e691b5c3dc3d5fb34efc691239a85ca231fca44a7621bd7d010001	\\x352785fd5a5d64afad9a624b5509db1a4e56e34a4f85253ff6f714d20f1e22faac08593c606e9dce505d23bd4b35bb75fa67bea99cc897be3106d3a4ab1f140c	1672640810000000	1673245610000000	1736317610000000	1830925610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
85	\\xcdc4694a2ff7f4605183f94af232bc1429dc200999e858d902183d7d61164b00812079bbf11bbbdcabfae9723bd2c2b0307e02f60dbded90e66e359379564715	1	0	\\x000000010000000000800003c5ed1ac0b1ff6d139b1a6e8bd094f9fd6bd7ad2a63ec4371647e3661dcf5141ab7a3add4180a96a8e8d39bb28a6d1f53b53bde97304f9721962460caaa0e5e7ef238658e9482cfe59cc94701ddd877c2098e635a983217f1a7bad472f19702d09099e8c1e3b8e24ce17aff29d330f2cf6b38070ed1bba4ee691e77d4e737b11d010001	\\xf175b688c16bce3cb67887fbdf04ccfdbb448e84d2f6e8073a2124c1fd74aacdabe254121af5e6469a366bee71fcdc375842efb412935e765e666bbe3ff1500c	1661759810000000	1662364610000000	1725436610000000	1820044610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
86	\\xcdb48cb1cbd14db7bfff41c4a6832cd7430b5094c341af874109ce2de93416df21cedb072fad1f5bc758160ae70df2bf9f02974d677bc98e99e1257052356297	1	0	\\x000000010000000000800003b9634b32d3befa25f5943f72b0014e5b372fcf9a167636304d39d684a48b6a3399753a26514c3c2250459676d421a2112a78a0012fb3c3f961431fe8d0b398806b003b2cc8276350633a3100cf17e83666010b608fd0123a211d19bbd534f8aecfad89f02a0f328c296544665059355906ee6e29c7e74677349f6b83b4ceb6f5010001	\\x043a410f7603151586add97bf5bbec2f1dd23f61b4594d3716b2c9ffd92bc559eea60a281cb72ce8541cb65dbbbc287a98881d6e935d3cd3d899b72160448407	1655110310000000	1655715110000000	1718787110000000	1813395110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
87	\\xd3e808aade64284b0e1ab48e6029deef8a5f74897141f51202612ae38b3607436d5770875320f5b4c83845e1ea987b82e4487c80570d9ca2f9ae285026cdcbcb	1	0	\\x000000010000000000800003a9d458b938650544d4e216633c14c218679e472c7b5bc6ceaba15582e06b5fac6668bcd7ffc7ba59d4282f3e13b0710a2f98c222d40e9e9f52f9cc6ed4f81c632ba879abf6c60b76258eb27b77f298091bee49ca9f6bb0ddc8b15da2c4ea76e05a9058b2871b1d010c7d4a1835fa41e99aa683179a9be3a6c5f8aceaff6f40e9010001	\\x2711990ae55b90262a30609f983c9667f326b34d917431f68a45319e13767b83d5a0f9857013ed7f4d633f0dcad682cac69d7f483aa7f159e878e9674246980b	1661155310000000	1661760110000000	1724832110000000	1819440110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
88	\\xd308f94eea8533ab11ccb9049a886a687baa493d981ce053744bdc2e03dfee44eff6fdfab6190217c2b933635e5934615916c74147d9bdb0a66d8632c05dfc01	1	0	\\x000000010000000000800003d03627fbc07437306f2edfa65ca0ce427429d5286837df7f21f925a6cad9c99aafa20b59cd2d9a5ab31d7624fc9f8b958eaa9d8192fbe4ee85afc630baf4efb65cf579e2f309ed4c709f9464a8bb284ade3331ba73aa131ddffc51dd47902486ccb12720c7e57effa7ac5563d292627c67bc2ade95b0b10c398c71f96d7c57fd010001	\\x1d1818994deb716ed7202a7a232ab2bce98593d1719e6c66a6063d96ae473567ed00c69c9d7516d6549cf4c701f996d85d839bff754a1df5530d12aa848ef003	1673849810000000	1674454610000000	1737526610000000	1832134610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
89	\\xd5f8371c0a74270bf346fd20c0902611aa2a9eea32e3304d0b9f8b2558b94370655a30df4f82a5caeaa9ba191ab8527486ba9eda0ae68183a18ad209a4d1e156	1	0	\\x000000010000000000800003a9b00c778f705fb9311461a4b0bf7d4f4dd37dc4af907d4c2fd54094d9c909ef45d90db51e092c322f85804dee10170173dc07eeb72fc198707900e1a649df1e9ec97493c45906c7ebba4890bf9fc8ab8e2dc3312984e1ccb923eee1614e6e671a58faec5603f0dc49b2ef3f5c84430d723100e5cc500ce79f0480bc4de27015010001	\\x547c2bc328cdeec7e0ec5d13812b67933c5a62057015968c0464b84f4b0da1c44b9a9fbf93c6baa9da3f467698f3e32cdc69c31607cb0d0a91418437e9875109	1665386810000000	1665991610000000	1729063610000000	1823671610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
90	\\xd9c45a4466caa65a8d57fdfdfe2664aa9350367a863562abc1beceedaa4bb7c511a883c31ea1754c779285b00a2fba46da174ac64a3500406c0d9dfe3c5a44c8	1	0	\\x000000010000000000800003d8ad1134d5b70f6f9ecebeed722c7b19f6456c53e2e800c3d06fd5027002cb0ade04d8771b829403ba4e0913c4232bba35ceb66b244826879268288ab9c1ed64fd22db78e3bbcb1f2e17463d6ef4b289b2476d55e4cce6810b1fd8e1a5e98f544fa948aa4a395f6cec67128fd8bcfb2e7e39742fee52c67571e36da72bc88fd5010001	\\x24d9f359c7fa9ef23048a941def7db2f49093c6c883ceb5bf6755d9a31a9a1fab22f5b8e5107e4b955c6415fe6845bd135247190317deccb744388aec080eb03	1656319310000000	1656924110000000	1719996110000000	1814604110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
91	\\xdaf8dce4d9e266390ac52ae7f621a4658a8ea453f2f4a2bffcd14cdb3c932ad37beb9f1bfb58313efa8d42e76d97920126bd523d974dd4908b8689bad9cee44d	1	0	\\x000000010000000000800003d849dbba6590c5385e8871ca5e38d0ae18ffd83723e2674166d96ec639b347c3315052c8c05e303798af04cbb004fc5200c99fd13e5cd2e2196e344f8b4d8bac6a28565b36b7c0e25de4f00b9761f5a6bcfe583e1fd096608bab7c689d94423cd77bb83a4e21488540a7c11398e0aed40babc26787038bac1b30e51301ecbd49010001	\\x3bb78f385a5b905825b05414aa52ba00706a4121356f75f64ea769865c6894b08206c121c82e710f3fed309496c89c281e614b175da6e01ecc8f82f4b2083506	1659946310000000	1660551110000000	1723623110000000	1818231110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
92	\\xdc7cc5571e788b66e83f6885e33a317f35f672c5ea2e8f5f6f40f70ca1c74b4202f009dcb6365e450274b2dc6a5461c07e0f723dc1e460f932170d3735c8c90e	1	0	\\x000000010000000000800003ad68a22bb50945249db57d1f37e296ac8deaecc11c19999fb2aaa5ed33f55a96b177b6e89ffe64ba8a25d834f08c80d6a70ac479144ca6a2b19ab8d337c81b8f3c31fced242918e690e2038348b9cd80d126d5435c23a7ec3b55c6d883eec716312edd0e372042b31807e7a3012f42fbdc2f7698b48b0358fb5c52581088ae9f010001	\\x3103e9387aec9767818182caa65fc216cec7deb37eb6ee26212abdf5f53b61188fe8abeb93a6f74f9eb35c1ac8a1e8780f7bee8557b2c2f3cc4b421667155a03	1668409310000000	1669014110000000	1732086110000000	1826694110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
93	\\xdc48041fe9fb9d4a3ed1e8fc730c0e0bfc280c402dc302a06f03abaaadce832481fd579e60b130e5eb48ff49c50ae2221468143ac6d2ca6c66d00047d99fa2a5	1	0	\\x000000010000000000800003c5964e8cd43e6ff2b9018ff83c04c67236e917aa60af40673f79ecb8841a7edb7461f94e6b24d3b2cc22b08a579a7353c47a172a0bb138c71a87b033ea8e7f1b672db4c6646d2d105dd8e75110e110ac819dc5845720c00f42fcabc27670c5e0c53a43755e3df58213ab08f32bb6056497f37e25aaa187479334d887bc475f75010001	\\x3e0d3e306793f73fb6e1a3705c6e6b775de4b7d42db4d5a21c71d47928e37ec73d6bf9ee7478ced45f467cf8b9df4b928509d05d3311a4b079358e79ea4a6809	1664782310000000	1665387110000000	1728459110000000	1823067110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
94	\\xe768935e2bc76ad78bc689d6f02765df38841498c8a233c088d6795f78ccedb2f3c946cbe9175e4ee19aefb3bf221f882df7222f256b19c4cd5babbe174872c2	1	0	\\x000000010000000000800003a809653bcef13495818839b9c6dd56c9399500bb9dd1d2771e760a24e198e471ea0a8ff98ae70c15997a28dd6fb6ef9bece1b64229faadc6037812fbec6668f9257f1ee69af5988767d2449490f4745b74aec8dec7067b5fc4ea006598602f01053f7f8c95005ed528bc2f52d2bb8af66f53c2226f0b2fbdeff2b07a0328108f010001	\\x590e08444d0fdb594a036fd65cb676d168de92962b6a9530f70d6956fd89d44cae82c0fb382e4f6a7e1b4077afd1015b4759e4c5414aad6a79eef33c76e5b80e	1675058810000000	1675663610000000	1738735610000000	1833343610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
95	\\xe70883aed347ea0164b0fd9959e4f930546a3309b57fd7314bbbcef76adaec073d0078da158efecbe3b3c579b8f4b6f4de88d1c914946ddcc25fdcdb7d6f5c54	1	0	\\x000000010000000000800003b5ebfd51763e1be755bf998e88272bc5a8d735d1c77a5209ac76885a0756e12ea062750484f44f7a32f3bd9374989a54e561eaea55bbdec00708e3a36487a9f6483c6ea96443a2595e7e9b78945f6b7c8495f40f2d324e81a92d31f9b29e111bf9b7d6d9a245d2b9469bd52dffd4901421fef79e943f17e69571f0b843865c4d010001	\\xbdfeacc47ff7b142bb44d3130e8a6a356c807a8827e5cd458e0432581e90e5413f7aab76df5c4180015f5bb1eca65c9fb85c59237d9baf47e73c62c7fc1ea50a	1676872310000000	1677477110000000	1740549110000000	1835157110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
96	\\xe8ecfe5c64fd169d4bf28883348edc0636d441eb09633734e9b64d1f98ee0e662b17dd4177a9dae675fb4d644a754b0f623effa3bf564aab9808e5b552cc63da	1	0	\\x000000010000000000800003d17be6812c04cc2ff86a809204c72d3d7dcb8fb7ba0f328b99b771fda1d48b921af09fdaac68773813d6c817c05d3a7ba735baeff81dd00362db1e3aa071f405cf0abcce27985a97c4f5f0464333d5190422a3e2233f816ad79b925ad2cf26f6a5721e338d4089115eff3c802ea62938418bd7b980de43cc565c689081c025c3010001	\\x109d3ae8b620a46696ed3d4b47bbfd9f2352973544f4b4ca9331ee6603ae65a1a5d32f92cbf2b58b6094127278b33b35bbe61efb598c04d883bc646291a2510a	1651483310000000	1652088110000000	1715160110000000	1809768110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
97	\\xe9e44a34c2f55c2d345d55d0314c2019b1975e075a0ce8030859c087ccd3f708876c7e81cb69ee90392c0ae813741c7e58c83c13e045d0a4e9ed74e0ea0adb36	1	0	\\x000000010000000000800003cbe352cc130173a710b8e58076a282779b43390e028c1c9dc887cbaea273c8ed11c8cc739a35dea2cd9f5bdc425373596a84a909a184803ef3e5d98276fd6b00799a13a07d2ed13bc2e6d262aa8a054bc624afebfb424f03c3f7773242b231fd004b6a3474e8bafe872d88440c2892a75fd961e00a8c64d5230f29b063eba48b010001	\\x373653f09659156518e0135228bcdcc9155dc0be17daca4d290770be7cc0a268202fdaa2524a6436990a20614fc013b73488c42f90c240f8f48b32461351b60e	1662364310000000	1662969110000000	1726041110000000	1820649110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
98	\\xe924533f2672c59950d29476ff77ce1e8540a3506a501a998c33a34179e01b9a8bbf1656faadc6b3a5c27c45f562873b377fe602d30a6dc1048d8b4b81de7181	1	0	\\x000000010000000000800003b3441236d72287877b715d98fc730c30ffc8f39ff688c2833cfd35ff6b86fddd20cb102f04f1a7b4e2442b66d9f4fa6242830de35889fa07e28ce62ad96e895fef987c4177619db8d7c375b2aa2e4703d1ee32624fec9c2b76a651d2954057c05438d9dfce909d84b2b76618d65ada9abc795b3a1bee2991d5b50b1d32b6cc4b010001	\\xc8a99a4a140c22ca47938818118fbfd5969afbbb72d49b182c5a3009d36745453d3dc401faffb76aa6fdea7d79528a46b30c1df559eaa8dd18bcde3a00fdbc0b	1648460810000000	1649065610000000	1712137610000000	1806745610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
99	\\xea9092118c6e2ac97c470faafcc004399bc3e43c4c6020cedc7782a87a9c7655a180cd1d7e70468cf902e244dbea83884fd596fcf114b90ac488946bf80e2e23	1	0	\\x000000010000000000800003f3349a063f0b65467f187eb1e2a9695025c303ac927895ca534f0cefb3b3abb868882b8b92f99fc614b97cecb3d8ae5838aae87d8c2d1356e177c2b2463339c0e5568381efc1e067af08a1596f0322f6136597d208425cf03cd1ff79f4f0fed2d2f7da85259f3a75ede4f65b8d546a94d749a4f324c006583e19ccee50a49e87010001	\\x44ca96c07ce9b9927f1ded46b569a3c46e54a4463f9d91fa7df5fb8e4825f7ef3d7efcc69dbb950d5d918e504ee59720c29bbf13857a45c45a79c382004f720f	1653901310000000	1654506110000000	1717578110000000	1812186110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
100	\\xf2c42e5f34114db4d98e020529e5decbd2a7381dc31d5e952ad6817d8a739a1d2eb149cc935379e3d8ce98445d018c2e580789d75c5ca8f00c6b770588218b7a	1	0	\\x000000010000000000800003a40bd2eeff0cd1e447c642cb1de5bd7097826a6e326967226cc9d27eb9af5c453409d287300b7a17c67c237e8198a842c70463f9097b7fb1cf4a06bbc491129819b7ec43eb2f67483faaead5233e9378fbff650b6aba12b7e50e5b0a0fba3871d72c1e70504742206d658466c16fe450dac22e64c8e2cb220ccb8dc1c9c121ef010001	\\xf2761f663beb2200bdd0f811c8e21dcea0280f57d59bdbe8d157017bda80fe42de1b2c683d749159273618124003042f8ec886a1c4b5f115aed2d4955de65407	1659946310000000	1660551110000000	1723623110000000	1818231110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
101	\\xf8444e14560ac9b06dcfbd206686dcc8c2f6555a452100f8a76bc15ad89dcb4c32a70d7d5bd32767129944279f9281912623c7ef3dfc9ce51f808b0a53610535	1	0	\\x000000010000000000800003a5f09dc14d8f854e8d8afddd0b11cc05858bed6e0d72ee2c6d5570885b0c2dfd67c201a5348607fc668beccb7e709ca8e8d392881c45a499884b6462d5ae3da6253b586257f5b77bcdeca559aaf72b1b3cb93339975d92cdcb4d45867914898f475ccc8434c2947fc538b78b2754976fc7b54c3a749bf0c39bf3e8479d7db183010001	\\x10c0d3b69a569629d3742d4aee662f3d80e1623826684ffe86b20748876d92b4802b1249166d968f3fc1f06e3f03d93db8f3062dc75a566cf64f951b81e5af05	1646647310000000	1647252110000000	1710324110000000	1804932110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
102	\\xfc3c27a9092d25802377822d2d08b51dabf59f61ef3c4fad832667d380c08704288c67e3143f6c0a1f2f4bf2f564aba9555c2156dd3c48ebba9da7eca4368d77	1	0	\\x000000010000000000800003deb36fd04e02d3077f6d377fd20fc18993f55e21277bbdbfdfe697aa787032f04347f5babaafb4b4e926971635496ee2c6d218e4218e87b44c828029500f4c70176ca0dcb54d2b718b7b6230295d3e47697f78d77629d932626bf27a78f8f3804c1e7373627a3af1af602a20b61e98b5d8bf7727e3f7243a7cd693720a7055c9010001	\\x6d514964ecdef8babaaf811d1b5d8376f72df9fa2876e169f76e49a6195e2a6a987f0d7cb26e2bf0e3b7d896d02f6843994b0f9c60558942f035207f9fbeb301	1651483310000000	1652088110000000	1715160110000000	1809768110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
103	\\xff2cf85177043aff9cdeaa2fa9312381346ac1ba92e36007bc87ed5e285ba9fb5f2c9f8f3273d5b66bb89fdc8d08a10c80936ed4f7e2cebd2629e83f36ac5e90	1	0	\\x000000010000000000800003d2caa95ac52ad4d2272053af1f4509fc97b54246d5a8cc23fa8396a152c9f1f7247d4f1fcb2648dec9db468c3a0932273eb56935e4aa147e5c0fbf6279a84473a04c8dd91749adbdf0de7d62c4340366c2781832bdf691aad7c387fb6adf53072e4393439cff4a32e6619e0c48025bff1e0c13c465a5638bf36eadd521595d47010001	\\x07a449376c55fa85c29e745127f2640ad1fefaeb68ec2502de60558c9257d269f4e4d692f71d3633d4c41daccda5de9fcd64816e492de470d60965f65a4c580b	1671431810000000	1672036610000000	1735108610000000	1829716610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
104	\\xff947791f3c3014455f2edb5c957a8059ed9a1e332178f81413db8e8fa6175e336153c795d11e9b71dfeeea6770c900642f9a3e0fcc201d58b69938a42fc8909	1	0	\\x000000010000000000800003aa255bee1900b141714be2696c8df27d8b18ab3fea20b0b9a2b83b5506f0fc886b1bca3c85c79f4649c3b7e17703e51e2d42c7aa00eaec695e6fefd53d59d59d2e9daa657dd996b4b89c13eed2a3ddbed6327cfae824ddbb709d921b72c6e8cbe21023e99128cd7e2087b123f34ce74c68a676429c5fc4e2b7ef05b014f410a3010001	\\xb9823c13c0b7ca1dc89f7e7aafbc9d78cb58099c070df2330efa58cea5bf1922e82198ccb24c66af2d0422f93ea06b63012b4ae89f4a7213c9bbcf2d2d4e6901	1674454310000000	1675059110000000	1738131110000000	1832739110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
105	\\x00ad1c01e9288f290e24bf11e4cb643a1d275eac76e062a49d0b04285c09335a209f766280e3a950d574f4f7516240c17f492b4c9d65a6d1fae0ce7bf772b8e6	1	0	\\x000000010000000000800003d620ff2a17b02a6841f1f6e3665d21cccce9632704b0c3d01b30962db515ab7a4025a8fc5457b7b3511a061c2388b07c6624152a6f97ca48fdb16be25188ac0ed7ffd0c30890ed8df0f062bf88e9250fa29690daf0f0e47f420061b99ac9fbd0df0a2e1ed01070efb150432b37104dda04bca785c66e06f7c135790232a9dc6f010001	\\xc6003753e5b95e24376382f1bfafbd62239d2be9c0845998a740a264d0cc9cdd3fa832b9b95d70e123eca4c1b2b129477bb9a209598e335f6149c0ea8c0c300d	1653296810000000	1653901610000000	1716973610000000	1811581610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
106	\\x01a5461b522194549b031feb332a78ef9e92d04501f7477ec25144e97a1d1da0c88afcc0fd0489620f80242fbd04eb5d33467507ce2cf13d2f762fac031fdd6f	1	0	\\x000000010000000000800003b1002a344f336859017af7c923810a16c3f640d325fa096e5c0c8051a7d7ce116d0dfb259b349a1df55c9d300088f10a1fa5ab794ba7c1bffda3788b54682b2eeb1c9dc6ebd07497e26814c221fff95a8b9299ef4b3a643e4eea1503d8f09e9e47ddd9aba61a3f71e8379a29a5fe6b28aff928141816b084908c700ca53d9c57010001	\\x4ea873ae991f0fb4ad3127c393ad0d027755d6778ca893f806f62d576e3a92a951511c16bfac7e155bafeafc1aabee08a458fa50dab7282f599ac737ea05d606	1648460810000000	1649065610000000	1712137610000000	1806745610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
107	\\x0585cbdce3aec54bda36d309d4007b5f31fb66aca23a58dcbbdf52e3ea3e9a052c9264fede5c798f400a77cf80e1b53fcc12a672198aaf285f9d46de2cd8ff7b	1	0	\\x000000010000000000800003b9a6985b6613aa81773ec1636a652cc9ccee5e4478452a0a4640c0ae943388f8e342d7af4078fbdf51e81463f80675d6828ae75f6e3f6dce34997ee96c1017ea949c7f4add0c393a02b1cd7f6041ac66b78b7902b5e581ad8a02f39dea4dce39fd887e9b745a5dcec47b42b35e40cb44604f7eba7feefefd3257bd7a0e4eda51010001	\\x32115eb0f4924ddaf57ba03d8c988d113f8a698d4e43df48b18dcc81191177dde05a43fbd7d0ff43b08c8869c05a883b590d6d6f10f37e974ba75a7031f44d02	1658737310000000	1659342110000000	1722414110000000	1817022110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
108	\\x083d529d91c10eeed0490898245c5694c31b5c2d232a437fa84a450751d76b5461adaa0bce6b84bd53bdb8f82594d2e62c25f7c7de2f0f52eb1f550ad0cab449	1	0	\\x000000010000000000800003bc10de6ef16106ba5fc99d8ffce409d3aca5b43984afc40e3e4635229b70a8c6d42ab83df3118eb4dd47970eff9549aa00fe3e2ccf21e5b15aa89d5f6e65bf3f1643298b7ef0dddc47cf4fcdec1351dd7e4ab2d25b892c683422a83f9bf623098b42f070d36e149f81bd9176f6985b5af93025703035e66f61c96502e9c0bd2f010001	\\xe6b5f2e5355c34fb5b9c1f07834d1bb78326c9c0c88d29009872524df60f2c9bf47100be0cab5326d91b4c9f4156d79940739dd5807481f442f664738e303603	1673245310000000	1673850110000000	1736922110000000	1831530110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
109	\\x0a51f2f751c9aba53385d8898abc2232c64299dd80cfdcefab43ad81f05c068c18deb0465dbbaca3c771f7d7b771d8225a27e40d73e32a89e56b3c2c4db66985	1	0	\\x000000010000000000800003bd3d1d4084f0e30010c84d49fc637fb6720fc649f6a3e4f076f84f61fa9850ecd8f61630a78355922b748fd7d91acf3fd089e1ba30e4f3616bd98b4154b05dc5a8d6bb88f962df2af96b984fc7751de1dd278d9235bf13b673d9f9fd26661442ff90ceec1340f2e3413387a9c56268272b17ce3d0e395bfd179384ca6f158c45010001	\\x05fd27860022657883e59a835e0ff590ed82021ca9d37940f951c601bab8b936d451c409a1df467ed916ab5fdf58e39cf5f867907a1d65f29c5cb2eea2e63702	1660550810000000	1661155610000000	1724227610000000	1818835610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
110	\\x0d2d98be0af52c0f624f8b12cf3b05e4457f31857a1f704aa7fb1d1d7d01e44ea31e80cb78326d2e41ecd5fb85e9c2f2f4345935c41b091417d96923966b5411	1	0	\\x000000010000000000800003f4ce2526f9490f270fa24628bf37b234eeca33984edb6e2011fd3c162a131ba8ce706eff4026d178e1c31547289e71160b37a1f5ee69a448e44669053cd917c4226d92d22cf6ca8b78d2510dac49c79fcce0e097c387a667a01db1e360f8d9ef29c7f9f7935eca6a59d94ce743357528071b1da3e72be76ae0688164a7d86671010001	\\xad2387ef4589c8473f3a1d9c08c9e7c112aee3aeb3d722966f0b06b2c96d715aac9cb884fab1bcb54f8021f02d3d0ea0b3fee7a001098cbd24ec1dca05e8fe0c	1664177810000000	1664782610000000	1727854610000000	1822462610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
111	\\x0fc99ae95922c1d4c97c719f695d1a64f30dad9a3ee3df9fac16fc11534e0ebba7bb0e0b0886178dfc60f9dae9b4006ced8c74f373045e4c9f4912448fcba832	1	0	\\x000000010000000000800003c89234fa87a0b6fd8763daadc58df818c90166383928e4dbe0d600c1f8a5973412858627961402c6317f649bb38833acfd8bbd81bbdb918210625d3d6c212319c6fce90e22e6b4056007627771ef104a39816acbb2304bfb95bef193d67937adcbe2c9a63964425420400ae5cb0dc94e97a8c94db5fdf27a74cd444561e33dd7010001	\\x517b7cb932d0143ce689c9cc74229c0b64cab56e579d9590c6e1d882f29d5c8099f2828fb9a661727f1cb19578508648fee6c855d6d7076034420c5503611f0c	1659341810000000	1659946610000000	1723018610000000	1817626610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
112	\\x14bdf18b3bdee0ab50e82321f0aac83f0259ff49adc0afcc6f88a871dfb6e410114a78c38ef3f53bda2305749db4aacc8b01ee148579163acfe87f6fb324a56f	1	0	\\x000000010000000000800003a9e408bc376b1fe9f5a4d3d45cf41cc165dbb71f50bdb5187f48007f129bd18375c68e21a73e6354736edbe69146fca10f0110d5276e217c3f36514ce476ff7d3a00af54b4768973f7ae75bcd35f56a09343859b06cb8b7f6a02ffecee8935d4c8da168ea932960c6953949e0be90c7c6c79be425614d1a7e4d1b2a8f41cdf49010001	\\x612b494ef654722f18fa8e643905bab04f0f5717d6edf94f258aea6cb8d98be83b0b6d8b02e005d5721738562af27023d4cf81802de906a1d2652cce1cc53f08	1653296810000000	1653901610000000	1716973610000000	1811581610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
113	\\x16dd29074bfb93cde915a36bd14e9c835fe161731f5ace86d848f75cfa04e5221a4ea8de4089bec0e872555a25030d82ff03f7cce8353ed46db035cf2fa8d00b	1	0	\\x000000010000000000800003a02a0748fe3f94b7500151ed67b4f2edc4ce5bf0d659f9f74b6395e3328d47e6bb8b4c79a82bf3f05f576dff28c204bce5e37e4a43fc1189d09aaa77bfb22d5bda8af34557e7a31ef2f675d15f81164f3dca3d9f702894b77e4c285d4cbe08aa75f328681bf3951274ddc1ec6d3884f24adba6e42b8f970b1f88f4e5c5950e91010001	\\xfe5d84ee6deb9cc36efbd65df012c4487d3050f48a174e9714e0bfe77b475c526e74125a40d85ef4510ee9d452d67a1c8e0a027ab11ed641990a373f08ab5801	1653901310000000	1654506110000000	1717578110000000	1812186110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
114	\\x199d1b26bff6e3b5e35bb711e63866b2f3fd29ca2967945960406c831305735e0688c32b7770f55843024807537e3365d49e2f810fd4eedfae6e743805b320e7	1	0	\\x000000010000000000800003e31ccf084e08965e5510b1a252b2c5c1243e4d1f26917ee7bf1e6f7996144eed9cf5e1517eeea0fa02ffe77b24c7e582f1823383301405d582749ea0cf4d202e97999d33e2753228789955a742aaa96cfea5d6ad129bfd1469f6728c6663db6e302f6e83af71cbe813ee7dd91dc75541d1a37ec4775141d82fbc9ab0799ab207010001	\\xad45fbfcde43563834a8ce80a7760c291cc0faadd1fbafbf030206dbfb83da1dad2fa817dd19585be76a5d5e64e76cb6350f5bb8bfd1efda30d1dc53efd0cf08	1660550810000000	1661155610000000	1724227610000000	1818835610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
115	\\x1c81854fbcd0941288d1aeaac5f722c26f60704c267ce7e41618075c6235eed9a26c3da686a2ac9ec9c8557f4be34d8bd62ddf6237fa0dc72cc5cab5afb96d3e	1	0	\\x000000010000000000800003bacb44ae085b2623cb254c3a2c0cb65f126465e9f60b867746582610cdbd31efaf25909bd13e5c3b542f6925837c3455a401f7d0b4b5aa49591fbd1eb22b0cf1b5fb0ff55d3ab966908103dee00d6b423ffb65ec3ab8842acab0f33c7fb96f485514d7044aa68df1a9639cd1a657ab5a5800a073dc8a523ab342b20b9e82ee19010001	\\xe7ce1a5b1b3aef12b91e6c97ea90ad7d74a140bdbeeb49a691723c81db2b216385e35b4ea497f39253911a52cba0c85097022d435e8094e4d11b83cbd07d0103	1660550810000000	1661155610000000	1724227610000000	1818835610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
116	\\x1cc9881fc9237f858bee16b082c7818492e7af86c27acc32f166425f744fe82def95d7f1c047d8094eccb493c6f57b7ed2425d7c9dfb2723812f37cd912c99be	1	0	\\x000000010000000000800003ab6377b4cc70ae1af4b18ddfa29162812afa69113aa089bdb3bb4429b6b361d69a8f8d793ed8f7a4372c957b6d89ac45311e0b7cfe2fdafdc66da43345763b2de77ca74dc331bc00b640b1a962aac65b3b6a2ba93d8c886f92d5acb559df6c3455ef9b86ca66a13b918a83cd120df70c090144bdc8b940fa7573ab94330bb4ab010001	\\xb40e648251f93bb0dbd44b640ef587b6b63527db62ae9ea308dfebcb28274c098ef009ec125b7bda47b24e7d1231fe474083b3bab137fba8bc775a5b3dda3306	1662968810000000	1663573610000000	1726645610000000	1821253610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
117	\\x21e1b014b05a7296164b8c930947ef1674ec78edee04a39f4d6038c95b1dca7bfc7afe77aa7ef13fa43eb4dc0e034f4adbff7bcd5bde69690ef0c8a283896283	1	0	\\x000000010000000000800003d1ab27e2724cdd963b882c38eb2279c0d5558a435c32c6ddfa8132ca895c01f5b3d3df31fc9ac9af725b077095f244b9167573fa921a13600f9566041f87fe5741351ecb9df15e1feb5a74fc149e7b4d7ad887078ad51229e7d1731c02326603cd719732e07bc21167068e99e1961914bb8252256286ba64991aa1c49d9bec9b010001	\\xa3070affde6181543dcd7fb921356aa39dd07b9335a6c66473737dbed3ae0c0290bc1423a0d562d0d9bf90dd182fa2a49112e42a7e91494737080c95a3335702	1655714810000000	1656319610000000	1719391610000000	1813999610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
118	\\x26099137b93362a5fabec3861821e21d8fc5445c12e4d1af6eabca6df46c5d70551c06d4d89c6e3e2aeee49c9c2fc278eba81a8e59c092e7aa4b8f774600afb2	1	0	\\x000000010000000000800003c1023fbb27e22046a77b54b70f2a81c91f9c2aaf6ff95d5a6211305e9ee653e39f24beb34ab6fb0836c1808eaf8567814fdf1ea47e7b64c0c70afe69586e4904b4313b81d7cec422346253b8c0e662f3c95aad447cb341a007d3a607db4b2806ad668fd1292e5b9945e85505286ce6461f43c0df56363a7c19da8ac0462ec40b010001	\\x56c9e1da87fd25451a9cf176e56ff75b7468b1418a712321c9f46a7c2983f3275c7ec4ff8aacd58156ce9febae725e88cfecca26828c355e42466dddaef24d0f	1673849810000000	1674454610000000	1737526610000000	1832134610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
119	\\x28ad7de7b0830b782cf7c195f12eb94fc4039b6418849626a423a52f91c5ed83ab83a6afb92b44acecd1470dec4019b64ab876d9b7d94b05c5b763b9b080e822	1	0	\\x000000010000000000800003ca212c389bdf452ba206be3047edc99a609868fd4e1be4fb4e8ef3aa07b008934b19cf2f47b325f8b4aef31d3df6d5921c21627569fd185a16c237ca94fea30af44504758f5675d6ad60def5b5703ca91bd10d8b801289fd3d1a25869aac1c944266f355955be05d258ac0801ea31ce1388d5f989b59b4b004e0823f40656a07010001	\\xeccb0825bd1d38e5bea4501bd57c44e9d01222d4f87561b7631b5652772c0ce277de5ccf747cfa3462857ad07206f29c31a5c458460f8d489a27f0d594edf40d	1675663310000000	1676268110000000	1739340110000000	1833948110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
120	\\x29a9a4b8f1b8117c1c64b351b53f5be1b6e85fd0d97c0e166986d3061a82f92139c54de3f473191d75ae8e791d0dea231d7ee2667427f23d87bf2e2b2ff78ed2	1	0	\\x000000010000000000800003a2c972d17988202e857c32e49221a6173935480a62fb554239f30d25e368c1af372831235c160454b789ea75b62273e0fd42e0cb591f50e6226c5857f4e3163b0ced172830befdf73ba0ae5a9353fbc7fb7b478a89222b0b73418cd8b0b7cf025e34613f658dcde672f66c9bc0fc2e46816cbd51cb61f7736de910a93a07ba6d010001	\\xf55712487ecaffb604d1410a78176b7f73926068b834069cdfd23750ce980179018429b984d292e55638498da350cf7dca2283935ee03d73801a5526ab16a709	1647856310000000	1648461110000000	1711533110000000	1806141110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
121	\\x2c650e0b388ec941fb54efa9886a34e118da44eeaea2b5d6d95b5654c6bfdf48c6fc7a6c4230c019de73f1ad76459b607fd1615309ff52ce7713078ee83193ae	1	0	\\x0000000100000000008000039fdbd79fac93c728f24867ab8818778a08d70e39d28e08514216ac30a0a5893efd04c88dae67a984eb0a41a160ec38a790a772e9555449b18c9a56b35e6f0fe999b0aee7ecd073895c5e70c9155b29e670d24254c4293b62438ae9932a6ec95879d15f04e3bab4a002fc0f0e3591f5f7f966168738de1938b0336b2a171cc35b010001	\\xff8451d713b3095f17f60798ecaea7df6e8842db6edcef4ba0952529a48774fd866b4765fa7f0a718bc509b6715392dbf9af03604fd54d4445ba848c417fc207	1649065310000000	1649670110000000	1712742110000000	1807350110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
122	\\x2df947c9c0b4f4aad3e0204b5057cbc7dc8a6e3d7b03b3b850e8e95f0ae49089ae1fce41c5ad2c1e6a7a67a73fc1aa45e3062fe2be8150a9e5a2caabaa63c70d	1	0	\\x000000010000000000800003b41b68d6fdfdc941dd7010b020e0c899726c3e8292fb35a56b4ae78024a724731fef33cf6a59bd05c0d08bfaa03c7518d7cb66439ebcbad11af5d490851e66009f75eb389d964411f7985dc8e43340b895d5de3cc0fade799dbe7199affac51078bd1795de0f721d056114e2659abb56879f1787ce1ae15981889ddbd67d3371010001	\\xd7e48605e4d6023b673c0050efff2ce304c81a7e268bedcf266fc46a5edeee27811052e9026b7bde4ccae58cb21b3c4823054cdf77ca0938def9279928738705	1661155310000000	1661760110000000	1724832110000000	1819440110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
123	\\x2ead95911d09e72245747e6ff1978848e4ac68db7b033c3f824bc2e56166273ec53cec2856f7765516d586b28bb56a2a532a9452a8ceb3c07a247e91e2e2458a	1	0	\\x000000010000000000800003cb23e2719bfe169aab2917ccf8846260165a9ef2ed77cc93e487cfcdab6a0bad9d2f6e5bda669dd4c3f0bded099d275071b1ef338b9bc96dca49f9740415f98dd1abbfa476dba2246518488a1c93b79340449181d772c2c7bacaa1d885fb39222344e91a4c54cfb757e87242fa698a50259614bbf189e285416289cf808d4993010001	\\xcf7ba84c1d4f149d07ae5f2c318af744659a0786c9765c78f07e869386a8f7d559b6f98a9c9dc41e9613a16139bfb3881cad1f163a092338ab2ca76b4a2f860f	1649065310000000	1649670110000000	1712742110000000	1807350110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
124	\\x30dd066596d5dd91462386e1e931bc0408943ba5bbc99b3831edc020ab649e7787a0faa4632379877b37334398d667bdb4ca64decfc0f6a3c7e190332ff819f3	1	0	\\x000000010000000000800003ba2c9def56f9034c50f2079c521fe0b51f30bc194e610a064014ca3f5f1b9ccf5bc96010ebe2287148e48108bd1f670045dcd271e39b3bae93c17a029373832809559b6d671504f3fb2041d6383724dfaded469d4b65ee8e9d352301dc8fd7e2832375d6f702e0cdb6bd9b8e5e0aef1cb2b07afdbfcff74557f033cd3a4e6a37010001	\\x206f6112d0e20169b57e9f116ff8d28f84f415c4888f21d8c52e7fa9d8e8cf8689c12686b88513ec075ecdc0b209522c67cc79d6201a13ed918c5d3424d07007	1661759810000000	1662364610000000	1725436610000000	1820044610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
125	\\x3225dccb8e6625fc6e771f317593a3f9e8b59a4103d2c422b7ff95e4f5ea6f2c51e5d3f085639f5eedf6a30985d0267081b56b17ca3dfecf6c47d7704274047c	1	0	\\x000000010000000000800003c8d66cbd126648cf2d09a6c6bf9358412547024442eec50a5d65a75064ad2ff6f03eaa704b870ed1991eae41b9616ca37e949aee34885fb6bcad8618c210cdc74de44ea85e6e3a3b0cb8c60007d440063d327b7871ab2aff546ec9bd90efb1e3ced68efe5bf13c70058a8eb89838fa7889fbd7e07302190f6f2cd7c013b03d29010001	\\x335ed00baef1fcd4057b3ab5cff0cab06512282602db5c068f285671dffd92682a0718bf8692323ca2c29fa039465f480b4a679e55b5da27d18abc7de6bde900	1669618310000000	1670223110000000	1733295110000000	1827903110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
126	\\x336d96871b11ca1d1e1438d4636e2976e5d5fb267227ca215a1cc4ce9a6d0e5c4df111c38e3c8b97fe73262af9ef384660c253008d44811576949932e73b558a	1	0	\\x000000010000000000800003cea83cc49d22d95142d6af87f82ccc87d6abc7d13edc6b56b4b09a7be38cbf62c76c11d15a68bf3434ada83ba8301938b8a1c5f60970ba02ca106657d6df2359feea12253669a85cf976b96d65fdd8fb86353f0a00d5ee646128bb7766f61825041c64da54358766dd06acc54169c0ec57364e452a6441fd77f0f40185bb8d3f010001	\\x135e2881d316a01d78dd55b169fd50fe0b353c247b6c4b78e9e1719f41bd2e799aa382d39e6c6e787b1848c0c3bebcd85e6c00679bf830f295f3e9e2acc3cb00	1676872310000000	1677477110000000	1740549110000000	1835157110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
127	\\x33a10b8ce83673e7d63f073aa6e3b9e65e1fe37b53ff5727394ef0670b335e2d9c1329ed702ee75664650cd9fdb5f5fb777a719225fa18960525359e4e918a32	1	0	\\x000000010000000000800003c74babc2d48004d3fce109b588e35e1d3ee0bc38f0b58b6fb551026b78ae3c1ad689caf799570c41240a3b5ddc9c70d85dac181b43eaf047e4e61c7466abb926e65af371e529ec86795e15fda628d72e91ef9b09bf3544914d06af3b60b4b00d9a37a5e24d6409045184880b1ae60ad7a7ae9e7a379767597df8d3dc49de2563010001	\\xf8c5d86a11f888164b01c27b1ceef23b2d221393f68b105ddc7297fddac3c9cad499c8ff280881c7866f58da9580274cb7d78db4caba31ad0239b044e6490b04	1675058810000000	1675663610000000	1738735610000000	1833343610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
128	\\x39315e499a52f1863c53745fbbffcd58ca580e710254543858d645c020fab38fd8b3d1ce4cd663fc475919dfffd92a70aca8c5c9f1ace24a491631948d97cdac	1	0	\\x000000010000000000800003b8257544ccb2113a37b4cc659840076d4f3ec29d0062073982b9cce3057c3bf3b8b484db83c11aa59949467d90d74e80cf17f8e1faef2b0d7e546cf04e1a4a8d91c61c1a456fedd5213f68e6b040bbd712d6b4e88f915718a139e94bdbaba53bb07267367a5a0302fdcb1d3489cff722f19147060f3e228b28d34896d80789ad010001	\\x69c4f0153362d89e3eef7250d31633c5ee300373d98be2eae240d05085a8169337a9572aff8d16ef0143f851f6f44f65b909e50cde36920091994741152cb30b	1650878810000000	1651483610000000	1714555610000000	1809163610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
129	\\x3e8595a66a9f31a241965610445e185d544b2da7b08a44acb241143aa7318c16f101f75aed5ad9d2ba06d983294b7509bf9a7b310d19dc37193e01cfe622e0ca	1	0	\\x000000010000000000800003c2fc6fca07c6d8c47c493966db1ba1111d3bc305125a0a969ae0e869f2dd73a011f1bb898de718da3dc355b124dbd2607d901a13679ba885370582983918dcd9ac73ad60b8c26cf232dbac036b90d564c34634a797d0da9459610ef5e27156c29d4b19e5a5df34a568f18761c7f89b94e237e168b1ea029605e967477d249c91010001	\\x088084c83de9e5ae096be4ddfce2e3002d47f92d2d8abb3f9aed41d79e0dc888b88b6973fd46955ed55b6b62324ed88f666aa64bc4f9372818069d4d697b4e0a	1667804810000000	1668409610000000	1731481610000000	1826089610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
130	\\x416510e0abed29bdfe14a3c9d00495d614d0907c7315a26181e1404984729dcdeefa2cab008857c4a06999868d810789abcdb563edb9ec68b28d8664faf16853	1	0	\\x000000010000000000800003b759256afad57a1371d44d1857b6548b2acf589559dd6efc5cbf4df8238dd61c746889458db9684c5fd32ebb60f23f0313bf03cae84e0a037370584524bd918bac289a48272070cdbaa6fd2ca3a2c0d576131b6409e3ce1d42bdb1ee414bfbf69a1ea3167f971df7773973cc3e873d9d185bae038de132bc5fec7109ffe3e63d010001	\\xf2f4a10a07cf3c6c7232c86415fededf7d8939a7b35420485736770267fb1a7dc3cb06173ceaf7bcfb226c2d1454e8615b4943bd32dc48d13e18c304e34a7a06	1675058810000000	1675663610000000	1738735610000000	1833343610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
131	\\x42a10e2cb49d99750f58024f1fb2da24664af596e8ac5672fd981fe71d565d2d4a50a3c359b6fe73c121be405d335552415f357c97ee94211c902006237f7581	1	0	\\x000000010000000000800003cbb14aee8a6e719e2954a9349a8f6f3f22b50574d4974785fff50516046652a5c7004500cc1a498d96785633a55e9bb3fb1712b7bc6e3372429c6e6a8ed6e295b3672a7ddfd768ac5ae1238a30d98f4eba4089abe57e2e94e0248bf200b5cfee56f5dac87eb94557e4ab90f4cfdf3b996817326353cc01fc14929969f21888f1010001	\\xf5934b742e49d81a82d37cc3c71b756e5e48b376d95ddb4ac97c883edd8d26be4f7efa370989a4fab0195919252ab62fe51639f02e42d5979ae1bf1a7a4da602	1662968810000000	1663573610000000	1726645610000000	1821253610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
132	\\x43a503d16edd63546e2cbc1cbfcd27434b389d10df7cc334a70b3e747b66bac87213b596f83ed5c86204d50e0cd1c84293ddd54a8600e622f442e6fc7ea7302b	1	0	\\x000000010000000000800003c36139580d67d27c1800f0504d9e6861e53101812c13f49f4e72ba9c9d9156659eacfb5e390da09ed551057dcf7d39b2428e6a83561ec4c7d282a58442cf5021b5a3007a5ae431e85dbfd1697fde2acd5d548a503074ce037eb44c0816c2c0d4902566de2a8abb976c628998d63c29040cf6d41eb9a250ede102d64e9505d583010001	\\x34afff51d729ae8b859f2fd838abc6061d50fa11c7e98a56984f121ee30c4c068746f198f7faad4e48ba255d760cfe2cd6ce304a1af1c8b4946d13854ba61e01	1647251810000000	1647856610000000	1710928610000000	1805536610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
133	\\x49cda0ddcab903a6c5e5fb77ca4b0ad4924cca151d12822c764edb9f20df7f747c20226bee8b0f621355161080fe6e5ec1ec50605fce1df0f2d81595389c11bc	1	0	\\x000000010000000000800003d71078feed776ebd357b10ea6727d607673af347f2c3dfd7d0c2a9eefe2f489cd0ced5482136860845a20ad447c7422a717a3d7b292eb625cfc363f8262ca147900f63cb6450ce566abccead22ca96739020aedbf0639f76e006f2e3b34b4f02754dbc25d3c7e8ad7ca8cff9bda0fb05aff521f6c96bb2c4d3544525863fff75010001	\\x08ffc0a88282a814088a7a04a7b54836b71d6d79ccead7ca404f6d4ac63bc1c22d6225227e2dc10b0c25ab3385ae453b08ee3f55f7c290d1eb710574d176950c	1666595810000000	1667200610000000	1730272610000000	1824880610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
134	\\x4afd6b3bff10d5e4d12d81fc6f6c1b9ee8000165aaedb13ed0bb4795aba6529bfcec4567d0837d6ffe0f4a7948ee02a31bc6ca5b0d9c7f061bdaf543cd2b6de7	1	0	\\x000000010000000000800003ac20a41d57a245b140b62f6f08a80c8b906d7a1fcbd6e684dff2ca2f3eb692d83b9aa856f04d2ad50630ee50cd01ffd10c7479ed80a40e152864fea40c048437833e3d4abe00076db60231606882e45826d7a882f25881ab79fa3a8c7ed44a95a458b6b0ec3c9cd7bd9dfab7c88e19d3534947f93ce2157ee0e30e1bf2c0abef010001	\\xf67a0052b9c3e7e2dbfec5ed6eab92960d5b0c64f62d191fbb6d7349d7793aac47815105e06f46e494fec128c0b607a06f0e1c8f7a098224e10561a6e063da0b	1658132810000000	1658737610000000	1721809610000000	1816417610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
135	\\x4c0947f86d03ae7028544058abbfd04bc72b16f97238e95bc34f85f55c94a9b5261f20c6ce7e1d169079854686913235336726644864619338984a55f49e3e00	1	0	\\x000000010000000000800003d68a8608425e5487efe844df4105c1cf45bad31f4c73860403f2171aec6cbcdfc13433b243763f4a16d99be0c5f8d4d34c8db45d1dce3dd6e9177cdec51d94e9c4f45d15dce1492837d7c7bb72b5b96216c0e0fb21dceb2d702d8f8e08fb6ee668d0b657fe8f5f65ff5f357f0bf64e2626229194033b2ead80fc04336db2ac2f010001	\\x8d1ef3432ecd4d605fc2bc38f09984eac66080a4d488c38d7d65c5c6c9ecb15065e90a7809c2c4108c6f14b3c45f4d30ed61ec9662b4ec87e72557c2a5998108	1651483310000000	1652088110000000	1715160110000000	1809768110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
136	\\x4d85ff71286153179c889bd71be3d97c7aa421ecb168399efb731c77d2ee257929d281f11cb597f7ab23bb491849696c943747411f2bcccdbda078808f6afb40	1	0	\\x000000010000000000800003bb8ed4c858586f194cabcfb57403c12233e867d42e013f34471794c52960b167d42a454f756402a848e5021d7cd289682033dc5cd948deaa1a66242b81000a97185bd7a12f6ce170b2fb402519706210f488a1d81b902327b97c3c230b3e02d6d2e898a955d611481dc76c570282f3aa25e75bd7c47a641feb81226809a4c4d9010001	\\x3486aedcb5847f5220a413fdd2a0c80ec5868ce77451c9d1d94b5843d7b26ef882bc8672cd11b0d82a02c142c615bfc89278c128ee5e7dccb37e4406ccf0930b	1669013810000000	1669618610000000	1732690610000000	1827298610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
137	\\x4e21453892427933787b9ae4dc7ebb01f13307f261c0906470e8f41d848c5f8f09e8cad513ade5c58c8bb11c0fc7973f534fac755712b1b264d6f3bc26c8be76	1	0	\\x000000010000000000800003bb76acd8c32faead8e1f6db92b065ce1d7a8a23bc8e27e17c1f1caf9a083043780724b4c1549f41c344db723ab9947126ab8911f26ca3ffd17f1052f87d6f843277fc95cd0b633b59916f5a05e659cf54768d3207926ea5305e62c5296d05f9ba979d6d6fcb1fce2400d9675aec866bdb317fb17de45f3bef1b7684fcbc3508b010001	\\xce7ecccc9fd9687ab9fb3d612ddf98606a5d8a8807517181e1d3348227e29ecf1f30e864c0a4fb5f44524113eaf6d2c2958632dd2e664e0fc5db39213f5c070f	1662968810000000	1663573610000000	1726645610000000	1821253610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
138	\\x4f4d749a5c3806c75907c1b66d198303d383e27c49a8124dd920a77de337f97ab0de7ddc24d174018e83688338a4952318d08ea265a4d8170b110ce0cbec615a	1	0	\\x000000010000000000800003e5a02ac127f81b29211a6fb3a3beca0ffdbabb1a99f233026058912fdfe68493d5ee906c8781903c303b0c3fc9f3d94fa2b6fbc939191f81b3578adb4a78336d9ef9a8007a4bd3a22145f98ed4ce8fd22cf216710b0e90580526aece6dc6c5348a7d1e020d045799375a1c00808048ce30335d02d99811e692540f520318eb91010001	\\x21a01822844e0f8752d2838d93c5a53852d7bd99500054a01d85715cfac2d6f312632471b00c6f11bdd4d4950981da9ddbe962531e6f5df13d1242b60b390a0d	1676267810000000	1676872610000000	1739944610000000	1834552610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
139	\\x529122298865c41a4df0d195ea6cdf32d1d4841e649a8848a645dd564057f84a1b2a7847c27bf8adb706fb8d277f00e767b6eb1c4a336fd74dd447284ec3c7c7	1	0	\\x000000010000000000800003bbb372590813440e1a66680d659f2ad17c9bfea4390768907375a952d064117888a6bdd2cf66e31d352ce63980a34cb83e032d7f9eceb2e57072a750d82810e1ed2c30b40d4c790487bea3c8b310eddacfbf175acfa1ec1314690374f149c266e913f36ed72c69f4111e5e37ef0436ddbef678b64f035285559485b99f09f475010001	\\x70bcb34312cd19eb3db0bbd1e7fbf33010a7cbdf96da5b5b127de5e269f9c020f28a51889313c3b9333a360cac10978760ad115cb71d47c54e799c0aba4ff400	1664782310000000	1665387110000000	1728459110000000	1823067110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
140	\\x53fd4e3989476c69ed4bf4ffa60b42f576a540653fc3b472e0dfe419f12c5d09bdf53e133707697a51492aeb892853da77585fbdc81cc14b577cda7d480e4f7f	1	0	\\x000000010000000000800003b5b3a05a44b269a9d19df2017887694e91b6d0e2e148ae4507f21238939b9d022553f8a523b9f888fd4600c1c76a478ef7dcc81ad061d371767a2c871ba7668b8d9c02d80df6bb71844d2e4990b0d35897181f9f0b436c3599d7f114fae4aae47c6c57c6cb76e76c93990b5a6fccb3febc7c4e21bbd187aefe1b334296e1f05d010001	\\x0ff58115bfccda4bc2ced5c4e29aa996b5ae5d86dcac6b0159feaf021060cd3bf66f918e6c205e6a76466c0691484778012ed7a4fde6bcfa07b8142fcaab5808	1659946310000000	1660551110000000	1723623110000000	1818231110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
141	\\x53c9b685c6b00c42cdaa2ca504663785c7de367dccf6326e6a0eeeffba67e8e4c52a153f889b60bb6cad9e09f05467db5c7b10cddfa9d12ea71e2bad9c654fbc	1	0	\\x000000010000000000800003aac07740c58c184147dec5e8d5badab2bdf929ce014c2c872544f64dd3478d141b009b313ae77b308e6472a255f5631649c5daacb009394d91a49f4b22d8bf7112ff728aa5111414d224eb37cf6978c1b490b7d8e884387f9e5bd5ddc12707fcefadd823b61a5c065263e89290d9a0db0298790c4e4466a978380c099ddafd6b010001	\\x788a34844b7559610f68604bbbdee94c54689dca213d6326a86187794a5a6a836523011c111b69601b509f2db2474fee79a8c999c2f6e94cd16e8c72fa7b970a	1656319310000000	1656924110000000	1719996110000000	1814604110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
142	\\x58e948ebe13379130f7c2813cebc91877af45d00e2e787a95f21da250b35a3276426ec447944690344b0340348c06e45a7ea99452795aeb614f441bf841fba54	1	0	\\x000000010000000000800003c9ea0be9eb351eb479083d8d5181d0ce66eeaec192a34fc892131959608c6ac8a07ce3f4971d9ee8a2872565113a547142faa47346d971c48d167ae39b9ad055c3f708a3cab93b966649adc22b00444f81f084de10ce3c15a74ed2085dac7f688b419b51137b7b7b97b7b2f87b3e60bd17995f237d54ea8f161be49c010197a7010001	\\xe4d0d5accf62b6994a19bc8b1fb98d1acd893be725264ee670e2e261cc6b84f0b8a771cb2c1376fa2618404c72cb4f1cb4a15b90537de9b8ce3943902018eb01	1662364310000000	1662969110000000	1726041110000000	1820649110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
143	\\x5c09a68acd91dcb888394956b5d5ad4b1be028f4fbff528fa5f84deca4d93002f02f8370f4a2dbf84ce07af54fd2b7fc938073f7d5f9e42974321082d9a846c0	1	0	\\x000000010000000000800003bf7f7dafe5b3d57867b1f9bb0d8ba055a320cdd5f9b341e887bda028c5e4116080b47f89ddf9d0a1c0970b235ada171f53c9ac57bd51a09c354e666119fedd725d897032732297b02c1a0135fd5f4fc4708df498e1a22a53fec3eb1959802929d69d4961ff723483dbb380514901a8c17a928d7b2cc5236008bbe1d57d249587010001	\\x9aa583387535c4a30154be20341991f77cce6104153edb5680243b2dc444c2e26fd89112e9b965d0bad225f8958ff250bb5719a6b3813d5376e5e073b10d0805	1669618310000000	1670223110000000	1733295110000000	1827903110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
144	\\x5cfde399bde9a641cbd6fa2a63cb9a54a9ecd5538c1146d084a5054f0c87b81c439dd9e9dc61f6202be95c6f8640f59924a016900f6e0155edb14138ca095c85	1	0	\\x000000010000000000800003bbd8ed2ae421f4d609e31a3e1bb95fa1403b9dce43498207b638aa2f864a3b936a868e790d9373b5165bef286de4fd979e4e234cc65e290f4cc3da3690155490af63432481cdc4c09bbccc8c4db0b533e1bc9f3f6cad670402702a2db27730e78d4c578fc56306095f50224e665ea7c95317c2c701240857a2850bae5ca9ff27010001	\\xdfeeb6a056070c5e9a5f9f99b6b33a21611ed782a832e13bff9e0cad179dba8dd2cdef90f935cbe09901c3dcfc55a5f4f92754271ed46a48a3369a3ac7da0807	1648460810000000	1649065610000000	1712137610000000	1806745610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
145	\\x5d69b2fddcc0c875a6e6e111e25229975be94f5a1855c219d3017d6510a7d1121b2f145f66b0ae916c250c573ebf3a6cc3f75be0f27b4ead6c1ce2005d468d1a	1	0	\\x000000010000000000800003d60efc0a0e787b04bb47ae7d229d145412872289dc0e592a2b6455a1b59910fefd577a4055f443b38142792cab364bdfcc20b2eba6c66da326a36129d197c3f255e43f9225a6ce23efdab4bdc1fd03776f377883db69f0c68401013bb11c4afdd5335239cc61ca4ce09b7bc58bbc308f07721af0f1952c855f60285eae7520cb010001	\\x51e014c05703f940282d7766adc30c4094c68071717ea62f9bff0bd636b9cdf7e8d4ab2a90cb75ab5ea59da79d3e63ef23ffb378fea535311f4f19bcec02af07	1668409310000000	1669014110000000	1732086110000000	1826694110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
146	\\x5e8d5326c5a3e756f6dc80f66af559bb54a7331ff56be7b0c41ce78f9eb9b0ccacce0b1fc14049027279d567057e7d633f3c6d761f309b3956bb2d7a0e92649d	1	0	\\x000000010000000000800003cc8ee02b3fa8e7c1169d4f82eb2bc02a046c5acd85479479c49b75302a0919d651d02ea6703373ea2941ac151204beb1df01a9bd0fd810c0e94085ebdaa2e9d9ed18e5f2228ad7a76fc8912f0ccdaf3f185a3fcb4cc12c88f88a71e3dd5c554103019cbf21e358ffd1c2b0bf17b933b6f3b95236280d4db724b6a2ed5f60947b010001	\\xb075257f2e346bdd572d596cd608287351dd4207f5f4d999c922e2823d421ed35d6102f9e1f0f27c34d99a9f93290526e7bb7d4266cfb03e69e1b7efac0b9009	1658132810000000	1658737610000000	1721809610000000	1816417610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
147	\\x6211bdcc4f7fde9a5ed1086b862bcd08d4ed0d131240bae0fb48408d81fd11c5a6da7fd5e669e3553141e33bb81ff0597bc54a76175bde0eb0bd4cba22b20e5c	1	0	\\x000000010000000000800003be8a1f3d746f3198f308b406a37d25c2b9bd92176902f14e75f53231c0755aae82c3f8215024e16c69b8da19586af919a36c30bc45eb5f82ff1e1a65e89729d2485f669819758e5da870d7d93571ea806881a97fc5f7ccf95554f176f96123e94267ccbf08690e94c8a953e9c65fcb9ad5e1675983c746b26696ae46943579d3010001	\\xdd4efc0360934bb3a849ed8ac45995d1cfef4fbf0abc2c1260c2f76e9005dc133f9d9633f80148a1e9bca416ba189c554c1df006886affeacd34d19ae74ff008	1664782310000000	1665387110000000	1728459110000000	1823067110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
148	\\x66a5ac7209a0dde9d516a5f8146dc369cd49ebb4c6d3496320e3f69cfb32ba13d36cd241768283875391e37dadb6c8f75d571f6f7ff8caabc4ae5eacf289e993	1	0	\\x000000010000000000800003a87a23deef314f5158b437ea6b94c92ad6b938e924606e73d07fcfa8a86e0e428a53dda79fb00c3f6183cef219f60e278e38b01faf52177a2e2369506c37b2a1e6d8ede68c86bd1f629b53f970d1c548024925e0ef92d878e23e50652277351e7917478fdfd4a385acd601164ce0473add3a35c6cb2806799c222474c801614f010001	\\x9c8e8600a01dfe7e1fa7391ed56eba54768ff1112ed62733276d93e451eaa6dc28b21b9d20c53f3e472d4acf55c5ba806d719b031dfcaa8aa26ac84f7e481505	1667200310000000	1667805110000000	1730877110000000	1825485110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
149	\\x6a09422606ec54d41b2cdc4eecb72b0f7a773f56fd964a1614e2e3fcfec42d18ebe3725f30f547e1611df62acad30a5dcfc0301e98b1f783f1a1ee394bc78914	1	0	\\x000000010000000000800003d5c82cb34c181361505f78325a6b0e83f4bd9e469b5408bb5644ceeb5bb66f742f61d16aa882b244a233b9bf6fbf6822c9dda74d685e06863ec26c77827dd20494fcb81ed10423dec5679a5d41ad75c7c5aaa78979a6aa607f1f514c8cc895233e2784b93d19ccb6ecdccc0a45a6dd38b1e31ccdebbec4b18c39cc3a08a66b55010001	\\xd8dc998112977e2c54c0dbd371e9dfbeef74a7a979ffc204f1df82627b2cc753c499f1f4931c7758d68d04d87036c74c401555cab1bb66381b7b74648c8b9a01	1659946310000000	1660551110000000	1723623110000000	1818231110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
150	\\x72656dad9693537eaeb26f8509081a6add0e21587f1148d9be7fe18b5ecfed45efea23ba7b1208fcb3d253325f14fec1b86c65ecd9f43deebe1f0b9ea4e4686e	1	0	\\x000000010000000000800003c99b55f9565c111334af82fe5f4a2ec2181c0fbd664c7f622451e10d20dd69c07278a78310d2319a264e1cb3361624fa8d5a0b4db8f164b86a78877c69f510689cbc6232e7164a1a7b8781568b201c0d60e2fb1da014d97e1397dd1b2bf1b47261095040c8985dd0d8a921ff411e514fbcd8d0e3b02a21c3522f9c03e4323461010001	\\x48fe425f0c18d2f6bb3027bad0d06b9e25643a31b98a1aa4b48a10208d23f7ea69c9f825ef16bbcaed93835df9b56c6462d8b06acebc8be0da5d49175d213c0b	1665991310000000	1666596110000000	1729668110000000	1824276110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
151	\\x74f163022534e89849dba61e47a75b56df87fa5ac163edf595c346b5773d91e0942d96d2195d8d745a9db0f6994f9ccddfcce6bc988e933eb1a2b1f891ccd1dd	1	0	\\x000000010000000000800003c3b85f8990a1077a4967947ab9138b93c60dbd83efdb18fdbf0b5a5ea8a0982f56fee10f5a3197a02bb1a6d3f4acbd003addf94266c462a829d1ce4e8898a6c2b425cdbae01c40442d21201fc81f8dc8f168f356b7e4919c194aa356ed65fcabc55cc0153e06c4d04e7ac95795d2a5b8fd1e85e63bffe39cc46030673614b90f010001	\\xd952cadc14f5b5e09e0b8633b8ffb7550eaccd1a90f78b9f1bbbe1adfab57f507e6d73879aeadea81201346ca065ea037cccd9f1cec6172ce56aa8317ce76b0c	1646042810000000	1646647610000000	1709719610000000	1804327610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
152	\\x74f59a9b4cf2b6635b3b11019bcb24f7d03cb02fd52fbde1fbc0d54b968e63aaa36a4785c7a3b6ccfb8812421899a42390e986f562edfb8900585af633a60de5	1	0	\\x000000010000000000800003c9870254445e5cd478e59433c8fb44fc1f4e7f6ece109973f93fe143db3357183af14a41b46c3dc67b4174019e803f065183b07680bce24ee83ec4dd890a3259eb879b357e2eb1b2320bb13c8f4d14284d4230cf9c094152639d94d38f515120f8ac7c9b445bf556ed13041a1c2b23102e3df76c5320bc37ddfc130a518adf5f010001	\\x04919a71fe00ca03b2e494d912ad56680078fda8a2a6ae5d62ee18045628a74932b51aa9dcec4491af8543a71895880cb062202b9920c2fff3a03684c8e3810d	1662364310000000	1662969110000000	1726041110000000	1820649110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
153	\\x757d1ee8805f39077d1bac54032992821c03a84d55e11af4cc491f71a943d87cb4da4b3bf2292f7ad620847bd391a2589c6762399f00240a4fcdfc3f15cd89d3	1	0	\\x000000010000000000800003cbe3fff78bdd9b76144f131deb274e4cfc74f6360f70ae952d21a1f2ef1bf491adc5bd1b8d2ecfa4e158c81dbbc6a6f713eb9d0772248e9abee340bc6f2dba68e42e7c5f7b97e5c32d58149f415b4ebf4207355c6c04a4a1793278b28a42e47017bcb9cb1aff752f931b869e573d54be106fc629ba4fbf1f1c542e9100fea1b7010001	\\xa0e3d4ffc1c3ee750fa0534a6b24047d1d1e4803e2228771c7bcd4201380096714e04004eaf54071004d52681896111d352f3ee8af593002e942d74a7561b20f	1655714810000000	1656319610000000	1719391610000000	1813999610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
154	\\x7685bc9e9a1015f6e01f1704db02e62d91f8e6be5ab0db8d83d7c01ff7c75a7e1d1508ec16d5ea48e7e73f0f7e451ae58ad0e5f4ea178af14c42d7d72b80f297	1	0	\\x000000010000000000800003c050e0b7311277fa77985fb13a67ff13c3759dd6097a058e542b283a5443f6eac3e90638447cd0eb7c5153c9db4449258ad8ddc11780dc1432fd5c5196ab7565af6ae2a3e951b0149cfc7cda4786308d24190c9ed8ca3a1c44c7b9f9cc82cb9efdedb08c366eed0bfc2a5d9437717e7ec221c8b0bb8b36998940f4b837d92c7b010001	\\xac85d989b4adf30fd32a3132058a9f8f53999b9ae17a19b6fc4adaac61462e31a5d00a27892cd2c7c90dd38246262aa166b26772400e65c41b1b08a6b67c3802	1660550810000000	1661155610000000	1724227610000000	1818835610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
155	\\x76bda2d5f59fb24a01c9f49baf14534b32d41751c124fc42c82540e1a0bd9017f047b08cf8a2d4a9e7884a4bf0f46460632a2cd509bb85ac3ad97ded2801792f	1	0	\\x00000001000000000080000393adcb8a06f74533013fa2d70ea50ad8d59847dbbe9ae592c7f519ef0c5daae8e1d00f4d02278b760350ba7b10c968fc24b51514ec0c00ecb8f308423bda0ff343f9f7b21ba1040a75bb483948bc2218bdf01cd2d307030df891d5acd0f662904959e574e09b4f48de4d798ec6855b90a7cad0787a55eacfafb296e078141b41010001	\\x461bbb283d6e84f19eef1f758a5eec5bb5ed81037d76c3c427537adcbac566af2747ae18d02689983d85a72de752b718c296b412cbfd2a1dae79dfcb0077080d	1653901310000000	1654506110000000	1717578110000000	1812186110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
156	\\x7d89fb4b0e1b15a5b89429271fbb3330f8fb682bfc61f63bd8d0fb9ca3dba1dd8e08464551c0bad23bb8b635e805c74bf26ff4220a61d1f117f57a5f716293cb	1	0	\\x000000010000000000800003d1f48647553718aacde2636fad7009f32fb4a285bb7cb0a2842e94958d38d36c71824c382c3c6649f052dae9358d835b76224766ef50be5318548168694f36470940c2d4ec5779f46855ee4f1dc468b9a6c624ece7e6559a4922b7ea9714bed5ec7e43a812a845cc970efc113f24890bd7f3ac2a63006f27995901692c547743010001	\\x0dc0e038014c82bc956cec6aa8c018c6e965dc391931c63b5ec5dd4be2c4f2db013f28f14498ac61148c876a634d9655e2d42e820078d7b0d014a32649a58e0d	1655110310000000	1655715110000000	1718787110000000	1813395110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
157	\\x7fd5ba551ac19d87d934ebee6c50a3e24093169e531d0769ac506ab9a88ea92b61df99f589c11b7101d89a01aee29e4052650cf97a301ea65950b06515ab8c34	1	0	\\x000000010000000000800003dbf62c76eb09ee16a70f7dd8b51585a4b7b8ab70dc503260549392e0778926bf8c6ee3bab5aa597c9c9ea309aa952ce2d0ca4753e2e205ffd5d200a5732400dc84ab3d6538b60c60ffd6a8896fb6ae05e40b32fa083a19f6e926e0ac993ecc02f982b61459fc3eeddc01422e699984b66b7cf417db7a7aa316d5223cfdeecf93010001	\\x9476c16d6ec081dde98d04950f466d833c302d4b303785ecd8c791248090d7719852c87a20bf72426c3e8a7f37d9b2a144c6b90f5eae0d824a8fb6a6c662450f	1657528310000000	1658133110000000	1721205110000000	1815813110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
158	\\x83d5d98d3bc5c5109718e467ab512e557f70b7756fa4f15c2c542fd49ebfd41e92f9820e06e7d268a2adcbd40c91a064bb12ed3adbd04f1bc42172d5020182e6	1	0	\\x0000000100000000008000039e236aefeb4a0b8cee86d82945f70fd715fcb64c5d2b0eaf5352caf2a61fcf4dead00105da659c75cee1002d0c25ce6867dea3dc3d444015fc8c2bdb9f81a459d9a9511137f6a01dff24375e2e2dc3ed00f02dd50d26d800513a6047d52bafbec1253769380ebcfde85f6c6ef55456e417b042e772ba055b6258436188e604d7010001	\\xc9abab994969c17211ca899d003a7e5a0a71402b01a6dafee5668529eed2dfe165baadee8c662710b3182de756901dc47a72b971d7567d38402248a4eed79d0c	1648460810000000	1649065610000000	1712137610000000	1806745610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
159	\\x852df1554367d3131589e270eb368b67d8fbccfdb6a39068ce59cbec91f70321074fb5a60e340f684c7b2bf2c194b29bc60ceaf59b805c16f79d2aa3e8539eb4	1	0	\\x000000010000000000800003b61ecce4996418a187c02a1346a28175dd07148fd755fa50bcd61abf230099165eb66013045fdcdcf5a6b30e0d1e66b68681c4ee4a7b0e6a5c0296c6e7be88f6c862764dee9c3cb0b88939244f69cebb273062518832b1d3ebc54be710ef593486aaa458a6f73e64f16eadefc220e265c9192fd372914e76a286a3c1d1e6bdff010001	\\xe4dd0516948f6fe18aeccf0a685ab4f2540f38d5d8793b8ae4c8c4545a26ef5e788db74eeab25878524b7a48f9b603577966698e7f75b67bff73f812fb71ce0e	1662968810000000	1663573610000000	1726645610000000	1821253610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
160	\\x8889b74144de1fc44643ba0e572564c33c15c8bb3bbb1829e3302eda322462fa7f18d2015f009a25dee054091405c24b74279df7e205cae9ea71f2e0518dd7bf	1	0	\\x000000010000000000800003a8d592aabfab32d961ed2457202ddb0035c43c9ec3791a5c6996f4f21f5407f236aa212f63ddb2d3c66a5473fcc0b8e13e39fb6ac9ed1826838de0aa997421f723b40d31c31c1b5ae5225c61435054182ea80d021072176ce75e91c4e11ea56218a5537d45d19ecbf12148df855adde3c8a469d8b642e51d03ffcf5f1759f1c7010001	\\xf3da5f7f11b5f0903f1b95e0f6253350b3752b538aa1aac5f3f77c351fda277a6f5c399e278b92a509522de97d3e6e26e92e6dd2b0259bfb77193943b83f6400	1647251810000000	1647856610000000	1710928610000000	1805536610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
161	\\x89d57c5fb01c99c4a9b336d6c8c3d88e49dc135da752f9f7082ae821792b39df6709d8afa49e0e1649e391dc10132fb8491002e48fa680c294a566858bfe2802	1	0	\\x000000010000000000800003b6886980877528f2bb98cc991b02766cfd8e4892c8cc68c6e644abe0310c3b50e2f37e826007acbb95d7379504e984986950a23336136f66287f73000a5db9c06b7f68b9ab49bc9775ac63e31b9625c0b2881441cecff6a7ef696413bc8e94a8aedc26b6214f7f82f236e6ca37c6913b44c50f128f20f6d46b3cd2c140a26a4f010001	\\xc5c11984db61e2cd4987848622cfed01731352d3a34b0c138d0da99df79e67bae83b1a1c35b565467e90d30941f5d9c1b3b242aa9c29faf0c1209b33349b7b0f	1659946310000000	1660551110000000	1723623110000000	1818231110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
162	\\x8af596df4de99889ac7a373c0560f3b5cf85fcf47bb88a3e1b2b6f0209f5aeb84ea10b64cc481c3808b8b96a62ef596ea65ec1b52696d020419ec298bedd3d13	1	0	\\x000000010000000000800003d5bebc19a3076ee868aafe01aa5610c77e3a7633b06aa3d17b941bbfdf3cdd2d705428ce7352783906950bd7fa75c37b2c39ef3befd5bf2c598a3c944b985e671e32ecc2eceef0bbd2fa10543c264970f0e88ab07183250d93046f6f1bf00ecf56b3a6428293dbd88515cf303cce2991c24ce5f73b09e679f39a604aca103ddf010001	\\x3f8d17b7c307a3c6b258692b7cf55ce6b0584e3a1a7ab46f54d7abc9e064dfcfab4e2ec73900ca15a2eb61c1dd35bffca104a9466827bd55d17f07965f01ff00	1664177810000000	1664782610000000	1727854610000000	1822462610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
163	\\x8a4581cfc4240d61cb1d02874098972c952c866a8fe988c31e9a4797379f2642a3f39b98c39f83b5577be99b6fa8f7be6278fb6a5ac940770dd8009a12d7a5ed	1	0	\\x000000010000000000800003b6bdd3b7365a8fd3dec5399180b2254e5977d107072cafea8f8546113c48ffa04e622e918669cdeaf4270319e27ce55ef1dd8dc269594193ea7c13314a8a1e0fb2f9257a629d547860dafab1a0b9ff5ac66f3ccac122b99ad060e1a9c196e24e1898fa543ce89d0ac872a4f96b89e5c9ef73884c0e3174a8ae5b44a2690b14f5010001	\\x47d08fda15bcf5f49a41f63612aa759489a43c589b7246a2315a9dd9818c5b1c14b650efd30b860ee47b49eca12226e137c24b35b0d14cb321838615bedc7801	1656319310000000	1656924110000000	1719996110000000	1814604110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
164	\\x8ea9da2f8eacb670466017a8d33ef7d44a481fc6c454d0b3912d8669f8e825d6acd1f8b181316d7312e98520e42efd237caa8bfed009d2d0c263a2a55a4be992	1	0	\\x000000010000000000800003aaedeaeca798112b44fe2546e83284c671cb0c82d633510f4ba5faec6aa6c0501f092a01abd49c8856269a91c406ba9e9f21309a4a47b1fa88072492695020733e1bdedcfb49e0337a5dba81d9e2dfac6f260ff992f832e9cf8d6316522804c427127771159767276c401b0ee5eeb7849a3ada0498bd9c6507c23790f6b55f51010001	\\xdd38d95393fadeb2b5167e363ea8abf2a64cd51e9b66e47e02112c10e3ff0df444579d34d7b236fb75415b21347b6007bca442f7a0e7b8510c9e693d10344d0a	1667200310000000	1667805110000000	1730877110000000	1825485110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
165	\\x91255653a690866f4e67787d6c69a7c498a7565e5d143672b467dc89adc7958a3e71ae087e589c49cda3fd8039824903895f9608eb6b868663f4ba52f73f6ba9	1	0	\\x000000010000000000800003bfffc45d05ef9594767473013d2b04b0d11d743a4715c2d2ca32e2f71aa4675a668d5bed9d6def31d316734e00237570edeba389ab1848fc3c2c2467064d2ceb7e2997ffedab53960c5d91bc6934b2aefe5fe5041e63dbbf96a253ad160d59fe1832b21dc973007eb0a3d052d4d53d1998698cbb9a15dbbd050f0b5c17441aad010001	\\x7cf567c9f7e15098fc2064bb770b801d71ac995064c39bca851518f14f0087a966fb05294e39d4a073636aa1a8157fdd0b559e8caacdb0bc1869f94152b9c403	1661155310000000	1661760110000000	1724832110000000	1819440110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
166	\\x983987d3a22bfe1f0e9955a363f006098acce166b07eadf471aefe9ae38406fa4c7498200ba2f2f2e41b5e13b62a7f972660f7a10e42e05435209de8041febb8	1	0	\\x000000010000000000800003b7247bac74645cba8561e380089fa4157e2ec1689e47fdff002ccd07ed3857eb52f1fc1c711b189aea68e1f99ae0a487bd3cb0d88b86f38b0f813d20f752b9e53a08b849023deb48a2cabedcf38665580350b973a96a604023f2c36b7295e21459a798d043fd07889f79057929c3d28271cc1c9f2aadfab7c9345e773c12b027010001	\\x0ca18e68bf8c15b2851a9ba5fc56a699a08c2c1995513bccca991010e0818fb50e5007ffc969a620904c9efd93525ca4e841741b6475b6bdd9352882b01f0d09	1658737310000000	1659342110000000	1722414110000000	1817022110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
167	\\x98a9038940a7d76cfc5e313f8ac11d49697ba7c1a8ca96bc57d1b429467b9f106d62fba1290a29bb187f8463e0a969643d02adff8a837b9976d73e5f8ba97924	1	0	\\x000000010000000000800003ceb200b1f65fdad76b8fa37dafc98fac1dac56ce19618a7961190ca3c2842d7d268c669277621e1472eec8db7d2f65072bcec6fc361be34280897333eb2ada75f9f7a542e6cf344b217cf497866ff94292372f1a5a4bded135411dcb3fcb48446cfac111a9f13528e14b4fd08c084cb7c38497acfe7e609d4c6dd23c421cc649010001	\\xd4cef1025ec4ca4198b923e91ffe110c27ce39217759c621833ea03e95d8aa723863439115ef5b5ce4c72b1a0c142e87e626c7c2b143325acf2d2c768f6a530b	1674454310000000	1675059110000000	1738131110000000	1832739110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
168	\\x98bd7067a07668a3aeab4c426c2a67046cfdf00e0fddddee4ecdc006d338e8aa138186739586e3ade7101829f8414e6f50e9c0dadb7ae2b79ce146eb222bfbd6	1	0	\\x000000010000000000800003ce50a595fb9095daa41ee154b908888ab877c0088d8bd7fc9a0df86c45065b243943a5b2082205ea37cf9316705e64f3c31d703a453022f1090a147686d6f82993a86037df452b2590c0d136e3cdc7578dc172239cd9fb698faf005ad43518b4e8687b7e5ef7fd61f41366fd955e831aeb4653e5d5cc3db25e6b55d52aa8ea0f010001	\\x0dc292b3c8637dc5068f8a822fd131d0cba29272c208e39037b3d0c7973582d75b64c78498345a382f47d143a47a6d384e29df77972351e26296218cb8f07608	1649669810000000	1650274610000000	1713346610000000	1807954610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
169	\\x9e6d5616b64df94fc1f124ac7c41c2d2c3d46fa520b207d38d41b4d609d757e37d1436c54419b54d7cd84985d5340034e9fe156698c8b50206cd2573c63f8a17	1	0	\\x000000010000000000800003dc806776298a884f99c89a14d3582e13b0a0edf4ec78f7b1a43faf35483bf0e4c45ac52d60b82d79a765ac414a144d0d242d7b1713ec301e39693d13060ae180eba72aa83867bb161a2f24eeb86e307dc6e5d99fa0cfdfc8a7e348b21e4464d4c6080a57e7c0a071aa465ccb83c2a27cde181985292e3559bc893087ebc1f453010001	\\xa52c2ee12820e3322f6846be5d246f8e0e9bbcd8d72a23e18873c4555361527676504b857e1716c257329e3eec60ee6081b8a55db8a75e7afa580bc31d87b408	1650878810000000	1651483610000000	1714555610000000	1809163610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
170	\\xa9a56cfd949bcb945a2c9362157027d057e32949f7de3e77b6b833d2eef88c4113b43db6edbb4f50c320d8a4d61c4a155bfd9a8e841bd1af35d0d02a2ce70eb5	1	0	\\x000000010000000000800003bd1db386419e733902e453a095a8411397312fa88b80b62a11d79b04f881a88037974f71ac7024d46d8ac1a7db4739e62b9eb1fa54d1042e0aaefb3fc1cb230a28b2f68dc35585a53783944cd102f2f0f478a9f24533f517ce577258f1b5726e48319c4f9acce0567bb97198ddf212f6b1383348d2a1847d65baa232352bbf09010001	\\x1d51477a48dc2e40257bc333873b83c810cbf291fba9f880e88b7faf7c1abd36d23177c5b335bca2fc45d5e6d605b3ee78928af860f235424683b995d36cc005	1655110310000000	1655715110000000	1718787110000000	1813395110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
171	\\xab4d408a37aeb4687db9186f668d213199272ac8cd8cfaeb07febe1d2c58599d58ab586f8d3bf13238390cb49b16e3bb686073d81dc62e786d9ffe585704630c	1	0	\\x000000010000000000800003bc88e2774e9c23b2caed6b4f19d41ea1f641a1eaa4702ecf21d3fdd4ed8903962a45f6f8e92990523d4e0d6cd680273023eaf81f2a204111bffa56dc2047877c3aae9c8acd17371e4f6811d78ba8eafef4099b187d7c570c753f17d26768b9431fd90b0f3abcab8fb9a4257f62c64e818988ee317bfc3e1e5c65288ebb715d69010001	\\x592b1b4f0c4db0f12ed7a460bb013a90d1575f2ca3af9bf2d5c202b62062a12ca713bf2f45a1bbf011f0da2a797ae4df7b5a487d501f6b16676026205aa5fb0f	1650274310000000	1650879110000000	1713951110000000	1808559110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
172	\\xac85a77a48789bb33584f7aa88fac8d7a72631e2bd7c7269c63a1d33fa5dad7916448a349973553c8220e3ade1f9d03ca12a61f03625cc7010ab61884f982a0f	1	0	\\x000000010000000000800003de40a13c9f978ff916e421f52ee04d0f6aa0d25d47a3f6316a57e9336978ce8a7a9f2e1986c56324a0a66690702374233f6bcd127cd1cc76a5deaf05cad7d7686b1b133274c9ac5075d4f2de919e8601764961b02d940f091b5d518e76dc834b6186b4b7aded8b439956903527a42bfb9f9e03d220f4be0263437dec253f6a6d010001	\\x33eff28806c8b95a7954164787f22222822a0d1263170af886e601a28e5d98d76ad8738512b0fe7d8e2447463cabc749ce5b07e86fb77b04d5e3f529f6e9b806	1650274310000000	1650879110000000	1713951110000000	1808559110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
173	\\xb719aa02a8e507c751a2fcf8d4c0e1ac58cae7bd645b27da0aac7ca52531601be39b9988ea33ed31cf1748f2e8e91fb45e6c856656dd3576dc0bfbf7170ac46a	1	0	\\x000000010000000000800003baebd7c9b9e08adf321ec4e7ba8020e3aa668da202c6e4023c25b628001f7d1ccc93c3d4cef45985e9c39defc2d962e738a8bf13ca432b3c6cce50877393a3b019bbc35ea6434e46936a27fe27e1beaf44352c211b24ae228294a6629579db81260dc1c2f5eeeedf64cf5609a392adb8213831a1d199a1425bbf6631af995f25010001	\\x70d5feb0c8d1f489ba1d85b712b4a85e48aab3056113be90e3072839eab5af2cf1aed6b67600eb5f4bfedc1517102c8f2be30b25d682175c8962c7e34b67b104	1668409310000000	1669014110000000	1732086110000000	1826694110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
174	\\xb77146d34594c6d9042a6008785c581d6cbb1c5c080dc925c37ea8c45dd611626c3c30aafe3663c05ac67f4e0937eb8823416e053faa516dfbafa225cd1088fa	1	0	\\x000000010000000000800003a7f9cfc0cd9baaf0c25098ee57b5ceae2fb082750b16160925bbe8cc49db6e9fc6b092c652441bf802edf6c3413c418e59829faf654f8d15365efde43284f08e4296b73f493ba415dafee5321da0207a3234e44c77dc9a10146ac0220e670368d55be8669e9ad940e3cc8bf6083bd409e3e0162df6817f104f55036c0f1f9391010001	\\x4b7caab208b4ead75de5b38abee737ea4661b23592ce0468cd5ad48f4879ce4bb245eebb80dff3110d81ea326aaaa615912a0b1314fb3c77fa70a9035c745206	1647251810000000	1647856610000000	1710928610000000	1805536610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
175	\\xba5913bd29788f0eab65cfa3ea2429cade9a8cfd22b8a51a47a0a282496e43b574653b4319073fb038891ffb0254f27c4b7db44a704bb5964cd57211ee95048c	1	0	\\x000000010000000000800003cff4c025970685a95ca07be7d22414b96dea50d9888a6f565e637e480fe7643381d2020c8a98843d9e45dcecfd98508e148627c837ccb39fa59ff57988786a1386aa4603e1a3fb158eaebc245c7bf3a5330eadc23770e1698040bb6b0750b00f5667e0c739c9a56171aaf48b9dac754b09569eee8ee2a975b585e8551164100d010001	\\xe345169b4ecda648f9f7f8a7d8dd3b1f82b9155146f7d8f1f3daa976dbc52f9d70e226e06c9aff10aa0baaf922989e955ea7722bb620db9e74a3d70533768c08	1654505810000000	1655110610000000	1718182610000000	1812790610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
176	\\xbc6daaa75eb0673c7281959c93d038bac6cdd9052af3aea427129b70d542c331e161305e38dd604bb4eaad27091962e3b0c740e7ffe056eb8dfb673cab88acac	1	0	\\x000000010000000000800003c3f969d161c705df58c49fa3ac002f927ec4fb553b9d88919539b46ad8749d5dacec4aca452140783aad7e47f3fb99241c0499f0f4f90dcef55ab6d4751488de3485df31f0f2244f713bef16cc2fcfc907ec3d06685e102efb52604bb30ff555c6f44bdfe8be565508eae42098a55b24299c8f329258252faea6dfe34c9fb4e9010001	\\x1a8d39639f26fff9cf4a4fc0feef28e400215617cf955335f6928d507a6d36906dd81358501df326dd2fa695bdc4857ea689c820c7c48d2c5a54945909082c0c	1677476810000000	1678081610000000	1741153610000000	1835761610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
177	\\xbe81f034b7e1a4047d76b03954be1a40be2c2629b9cd9f02d2fd3227ea54609a43632966bd74ffd752c3d556e21dfa61b0919d834dedf6eee3f37bb6b5f8ea85	1	0	\\x000000010000000000800003e675d7812bcd07675ccf347833b88e21fac4a90842fd0995df152ac5eada3f594b6bb50f6f3b5cf6c52185ac24fad2dad88dc1e9588537f4df40eba7618be6477ba31b23cef299400a85cce7e5e17be6453c7cb02bc8b1ea1857f56bf68b6cc4a1d60e2a7f72f49e03926794a2723e838c92b6379b2d87acae4113419b25a3a3010001	\\xab3549810361c674050480c25fce4d8bdde62f534d7e443f7d7a99e5a91ac260790173bdf9f64a210e4f00b40bd9a8cb1c07c48be892503e0e84f4ad42a03a04	1666595810000000	1667200610000000	1730272610000000	1824880610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
178	\\xc0b1004884d4793425869a002e4b0a654c6409cf8c4384fa2aa384eb00e52b2b8ebb4253cd78244695e7f6f85f1cfd26dd258644ba93dc972c5a18883bd216e3	1	0	\\x000000010000000000800003b5edda5a353ab51d2c7a1cb512f97f6538a3d57a8777a0a5ee27e8fa133218e422224d217a374252e632e7e5d8755c5ac68a5ca59caff0311d40f985aff08be50e102964c05a5fc2567f78ea8eb4bbd2d7534c858431ae537ffb53d497964f654534ffe14108e4016c54225ba5364e2430d122f08a0753d70862bd1f0393d087010001	\\x42daf0f7134da14efa3375d23e6b0e857f25e4c4a861847035d25d300ab6621b3a08a65337cc4c662ca8e3be850ba0d554be8e84d3e98a66e892c2eaa42e500a	1676267810000000	1676872610000000	1739944610000000	1834552610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
179	\\xc43dc942c90963ca03f2ff4132e0bbc9fd7040867cf24ee5501b2c4d04a09fcd0314edd32b6a22a51a3675cfa2e8b7f6fdbee33a1795f97551f7d68599ea5835	1	0	\\x0000000100000000008000039bf8d2c100f698e926d5ba7407bcb9a9d3cdcaf8358d5fa0543cb7a294a085cc9fdc641cb679a3a663501785dfda767402d0ad41812669ec81e43719d13fd1ed415d5dbf226c24a2991137f48e4dd54ac7753a564edebc6b9a706de3abbadece16452182bbb4d8566909a7ff54010efbb0c208ce23624e29e47a6f00562979cd010001	\\x679c7409f0872288038c60313dd0d11ef51c268ba609e95894faccc3a9e8489431fd743ef1e888cf194e9ed613b35d6891640baf595309255b9b60f06c983b06	1669618310000000	1670223110000000	1733295110000000	1827903110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
180	\\xc66d953baa30422a81b456b573a5be07884ac4a30ff2d82f0ec4077facb013a50738febc5a0ebafd1b2e400e690d46c96db26326aa434cab06eff3eb92b74f8d	1	0	\\x000000010000000000800003b9e86f092ef19a059b6eb8b08b3bf19b4b7663e21c4a14e8511f3c2fde35c576edf254a15978457ca95269813c496a3f8fdd490b49fdc3fda29fc30faab031e3dd81e66164a1ee11ac4f15844e0a2d6e9b8270ea026d5c2debdc6eecee705acb84bfb4736ee326948988626dd54733687d6ca60a5b6ab85aa5ad79eca828d40d010001	\\xbf4e9c6919c301a2c1de2b36941c370578ee2be36c50ececb3525c4471d3f8fbb2b9343301fd6e3c241a21594bb54f1319b4cdc72e95eeeca5e4c55f0320cc07	1665386810000000	1665991610000000	1729063610000000	1823671610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
181	\\xc6098ab3ab2d242f2f386cdad971e61eaba977bf1241402bc38729646984b112295db2572aa4317316aa200119bad6a46b5d8487390cf4377b1a5400237e7028	1	0	\\x000000010000000000800003d3fcbfc163b1321105c62bbd0b5af6a2fd6df477e44e11f637525b757d93f61cf4280ec8c76ea5f9f4af27fae8401bad463fe397c1ee439365161dfbc019a893276e7f1123b16e76661ffca3c8d2542918e69188ff04478e964f666bf50edd4d3d9d584473f438c5204ae959b5f2d5d11fcf0b90b0d87901942bd417b6172f9b010001	\\xad92934f50b1a28af5bda17ee76f39ff7fdc095ea872e7b76f617907f6c0b440a205815cfb293f42cba42e995740e964de1c9d8802466c40cff0d190f0efd20a	1646042810000000	1646647610000000	1709719610000000	1804327610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
182	\\xcb4d0246b53968a959a04ddf9418ed65ec410e07c919b27aff14e8b5f45cced216269cb541d34798f71aa56f784eead08b788d1837ae10c060d2f6eb71a8822c	1	0	\\x000000010000000000800003b1c2aa07d3a52162bc72f2c75ed4555aadeed080618a38b746df9ee79fe019f35490c8d232c8c1d9936748aaaaadfcbd85e67828ff0bc22c7f5b083cca854ef704121a8288cbdb51358be6f5ae45e894ee7663c40d5742ebf41e8a73ff374a44f5189f56cf5ce6a57c05ad75ed834aecb3c13942cb2e617fbdf3ace1a6410903010001	\\x6d934bef5bdca3811b77d823df3be4d6aceca42961a15847028bbac8fdb5260c6dd6dcbb8732a96178f72be7826b9e32ff80495fe402f5ad8a48b9ebc3ef0d09	1667804810000000	1668409610000000	1731481610000000	1826089610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
183	\\xd109a5869305c41099a986ede9ae19c011b4f0c8e8cb5f76e582db64f015c2175ffc03022e809110b6eaa8c2e28ab8f8288f42b2e2857de30fbf5636f69a5a75	1	0	\\x000000010000000000800003b42be02536ca8aed536199f21cc1cd76e5fe361a7a62c6c79a02e54d7ff8114a6d9ba5215da5963f618a6126187dedab942ce1ed5449a9aec8c4fbbfc9120ddfdbacd27ebcc93783fd0d59396bb2c0e1a4ec7b1b2566bb69590a636f0f9ddbc159da0cb04db4faeaf50f8f8e33accd58c9667b58a15d165b0280b72e5b914d75010001	\\xc78946056b3417511903768cd49847ba13085375608ff367e6d323aeeaf190d440126978fd825598585c5b10acb96758f22f0d4cb82e400ae0b792f2a2a41603	1674454310000000	1675059110000000	1738131110000000	1832739110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
184	\\xd1d15b72a47b2418a283a1ced6440726d2e48115fe0a22d94f4fbf0b69fe4b9f4cb2ab46abd1c8d2585bb6ae2c93d32274fb30e3539ea8353ff7d53aa872ba9c	1	0	\\x000000010000000000800003bf246b74b04635d281e9bd2d6de98d0b57d192eadb4973ab2d1cdc48a5e736ee9a147c5df1f1777ac1afcec559e3c5c8735f6d7a951c57df22dee8d519f9b10cb89e6851875581bc5414a953ea2c02c955f2eef61243b83f27a93760b148f90ce095b8803b65ff3c7f343bd9c4a592d4f3a99f61b989808aab46d770b767a30f010001	\\x5e695873bec482d4e003fb00c0c4776dcf2809019e8f1154a46b819d168e00b9dc17cc0d3c0d11f13374a55ba080188d7f535ae45f5d067171e793c1ab5fda00	1664782310000000	1665387110000000	1728459110000000	1823067110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
185	\\xd319b042d567b1e210b802a845b80355bd503c63292f9a9175bf0425feb8973267f270850abafd8fbbe4696f32656c290579c20a23aefcd0c55b4aa047d0cb73	1	0	\\x000000010000000000800003cd5fbdbffd9a31b1306bde4b527ba9e2f6ef964040be3cb5d1239fd2910cdee1e59011ee3aa797542dd8f78632e0a800d7907a97a73b5db80016d2918c4727aa03bfbf00b0f8d012d1b9a357098e7aecc77fbc60c66ffb91acb64f7e7ec542a6e54492e50ade89c8ecaf946885a27f989759d088e26470be604dc08a8185dc81010001	\\xbd0cf3ffb612ec9b8ffd7fdd6740d62884d626e7e60eb6d8f6f50c4012ab94f2f7cc17e55c9f2c2dd401bc81e73c3caf1ba3146af21cc91cc45dd4a0dc9b120a	1654505810000000	1655110610000000	1718182610000000	1812790610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
186	\\xd85998de2d8d9218b67a0aedb2f2859327b194135d5acbea9ba49ccf553007e6d0077b37e30cae7cd17d6d6ec08b31bb4f9761c005e77c96454de298e25ab77b	1	0	\\x000000010000000000800003d98f3c88a2f3f5661823d9d2a3cd0f264575efaf19ae6a5a18a85cd05bea88747d78b0de87c0f258fdba01a4364448d75b87e663dca2d0639e8769d8560f307e77234a99e1c689db9c3cd7dbca45f419c4dddb8d5d9b82a21d4dfedc59e378b8860da30bb06f94ccef3086b21e4cfea1ca4673e1d959201f4551c50ff27ff4f5010001	\\x096764aac238921027e4f45e2a0957ffcbae0aaef253911152a846380a313b5b9a03fd7782bb6c5a3a4568406bc795e782cc6c736215c7c9eb6722eab7152201	1670222810000000	1670827610000000	1733899610000000	1828507610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
187	\\xdca5ba87263a33091bf342de2f826bfff627364b9c262ff273b3f4d5eb0b93f736928a77140ec756edd44ebaa3edc688890961572749ff97617de34ff0c13482	1	0	\\x000000010000000000800003a1938ce93ffb073b1828ebc9e1aa348da5b69f4ebfd1b9dd7fddee065ade63c93a7c22532d570fd32df1339a6687c2d7da445750a5deeadd24daa31e4f39bfed2beae561ba6f8c6d0995e508f53e826d91e818a0c80b8c9c57862ad8621317ccffec19568b9616cad4ac75bb0f051b71e85b99025882c3e120d50d3086750057010001	\\x9202bac18b3dc32d10df85e0dc17616d7daa93914ab323421698f5f97f53b0c9dd757bf6619e95c604f68a4865ef78159085b26df3a6da0d03b4d555a160090d	1666595810000000	1667200610000000	1730272610000000	1824880610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
188	\\xde75a48b813199e69a55f29629c3a77106e0994dcc9469ca03ee82a243ca0e73cc110a317b9fc8f4ba291aff49d3d2c8bff898d2d83eecd59df9bf97ef421ef2	1	0	\\x000000010000000000800003cc6c35444732ecbffe93d7b9c47d3f1d00321142e80d68cc4e9eed4a63291ef94c13e5a1abf30d40dad5ce50298c460a7b70a9122fd563e0242b5bc3d9fc4c3caf932f56d19ceb52e2c625c73cc2a54c89da2f5ec36bef0009443f7f9f78727e89ebf3df497dc8b90b8b3e764a0292c01eeb6dd0a827ee01dc3b8f21571265a9010001	\\x2744ee338d4da94ee1f93c1c57752a9e89f65d4675f1b554dd504cb914128e352c7d60f8ba241634a186b246f1d39515a4995e4ba6498ef229d9397b0fb6990d	1676267810000000	1676872610000000	1739944610000000	1834552610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
189	\\xe12118ed31b3c346f3ec992833f48a4a5754d173501f5487d5547a478f9c5b2870423aaecfa0d50481a5be6ff40f4357c50d65229cc01d35022787dd36eb2401	1	0	\\x000000010000000000800003df050b7140155a7d97e3e5842dbbf5960ea6369ffae65e0b412d03e335cf8c7fac47d7593140a3e4b0bae692b7a28a565b589240a918316f90d83edf0cabcd23768885dd9287701fbb75e7a8e2c3e80fa7010d9402b34e8eff8cd041f681ce491046062b39aef6511a1f4bce3f8858c22ade621728b9740fdffd2cb705ad8cb5010001	\\xa05fd85eb6c0d85284eac773dd1d7fa1ef7414b1a6a20ef726321c8e0268fc193045d6c603486dfeee5e4ceac03980c97cd753a8333917ee8216c8ac2341b20d	1655714810000000	1656319610000000	1719391610000000	1813999610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
190	\\xe4c1bc11b14f662aa2c1cb2328ad006832fdcb4f41f260cbbc49c55b38e4a39afc2b7c9a5891316339d73e818f81ea444e57e111ac8d5bf6c7298477ffb895c0	1	0	\\x000000010000000000800003be883aab32a9d7bee251dd8ee25fa68aa782d8ed59ed7584aee59290c6ea19dc80e66e4337cf585dee92846bcc0b9c2c42bcd10a8751f80305b9bdff2284578fe68df8489edea453546e92607c84b9881f6e7f456a530c64c5b11224f7d721749c3e62c9925f57154b9de088e80c269c7103ffbc04738a4b9f124b0fd523e1ab010001	\\x9f82795764f93176029b004a2d03c97e1c86ac28d76d5d41f9e72308749492dd936d5e2255c862a51732f3d9acbd824a227ba3ec718b4ac1335b2bdac22e7c08	1669013810000000	1669618610000000	1732690610000000	1827298610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
191	\\xe935a264d1949e4271cdbed887c9fbb9f70d0582137ebd383b77e1b9b60da35710cf4e1c1e6748a75025013522376d33cd2b9af90f29d1a80582779651cc15ca	1	0	\\x000000010000000000800003e9e4ba9a49beac4e5232d4f052962aeb021d1fc2d968f3356ab8c251f5939a6fd4dcd93d44637453a5bd66e853969950853c5b73ba72d1da72675b219d397ba703a70a036dea36c280171c8786d62a4eb4d7eb20c0cd8d3e78355c446284cd0a81f9c02f324b6410947ceb9f790858bcb9ade776380f3656c76642a620d7b84d010001	\\xa76b5341c086a5edbec2acef045c7b934d63037be2a4ad9e257896c1d2fb7085f386dad6f7185a1078dacc776fcfc5a25554985be63c79c1c2aec99ae7baf403	1673245310000000	1673850110000000	1736922110000000	1831530110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
192	\\xe97574df51d1d38e0b4eb931fa12bb62baee0003033b872501c084dc7ce121506a7c480708f0a0a8e2b8ea7bff29db1e59ebcc72463cff27e52842c64e32cec1	1	0	\\x000000010000000000800003e82689f53d6976f9e69ca77ec2772feb69552b801b5fba87641031af2a7a32b570e264b81c318cf3bbe11e54a686dee936c6b7c6b6ea71ba6872de361819cb0d48dfa424f10a031942921022558c10646c4c302b57632b8d126a76a2dbfe86afa4461b2df4d86b4c9ea090bb76dbfae03070992dc2eac8b2cb5fe108706a43e5010001	\\xf045cb619332321135310d3ba07286ff0d0692c92ff0a68743d87c4246dfbdc9dde60c741972e89ec59ee26048c500ffdc9e032d3a73953db23470f1d119af01	1646647310000000	1647252110000000	1710324110000000	1804932110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
193	\\xeaed2256d97b897c7e9d142d9ada536e5f73a2771ebdc31610200904af8ae6594099ac5eee4156ab5edca06b834fabd85cec40bde5b0a1f2b38674f20f5a6ef7	1	0	\\x000000010000000000800003b1312d4ec32903f1dc493e2d1612b76643949bfb62c070034fc96930f9695a6352a66fe7fabc24a0a45b29563e1b7dffb99aae08b04115b84fee9a453c9bf691cf7f0b536e0fb04c35aa1deccb126bfa6532d1429b0057568391a3db6470148bbaeffe7aa6db3bbe29882412a20caa77ba11d336ed0aad944b9f6e3d4546a235010001	\\x5468a55e589ac0f0d7dacf16d2fbc259b2b52590ec6ad5fc91cd31ff6b90500a26037cd9733b0d93b1b818ed3cff2f1d8c061398ad810f56b2b80bf308f8f40c	1665386810000000	1665991610000000	1729063610000000	1823671610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
194	\\xeae5a3f9ad0a96801ea8ed0117de658de50d04d0c9d9f6d952e6131d36337515a739650c0a544c1fc6bdda9b95bf0313404de63e1251571ff16048882c13d5c7	1	0	\\x000000010000000000800003ae1bb4fd9a74535c8832f2a29958030fc26d3817cad54569056c1e06906e95580b11e9e242d2f3f829da5a643fdb769d189dd5c03202000839b0ab65f10fded1de0d7f8d39acd279ea76ca0f4c1a09dd871320fda5c9b948e45245705938e3e25b85bbe2786f29a59440da9af7b3bd21ae9b786cf94bf42213ec620f98111791010001	\\x4374fa5ef533603b1f798112ecdfc1af5e58e064d9ac3e6b37f5d6d3059c529714d39fe24790fbe9d8df84caad6dea0ee8267909616104b586cc6673e8b1fc0c	1676872310000000	1677477110000000	1740549110000000	1835157110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
195	\\xeb7951491e3401afaab9686d1a5cc34e3456aa00592ffd0b549a062ad85e028b26d144f46352166388dc11afe3ddb4b6162f96fe0456c1fa3a712a941c0a3287	1	0	\\x000000010000000000800003ccf7b42ec0c01caa7842d10373f6098ddf5cc0c794022fa00c7da462cd4c17f7e80898a8829fcbd42b9cc0e686e1a0adb39a7b150f8db39f9ec4fb87ca8db4c7f287d68fed75335cd6eabcacd4158d67bd1557418b6d27132afc91ebe6f1eef4547d127cab6776ac16bc98d91f0b6603b31f96ca88b2df6749124eff08068101010001	\\x31be2d0f77747a68cfa49156bf5da57669df277fd69384c247f5ac499066aee958aeea3bf65c8ba86468a5896208004d26b26fbbd4e8d4c85ae74e062994ce05	1667200310000000	1667805110000000	1730877110000000	1825485110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
196	\\xecad84c72e9ca0bc36cd0860f7971b3beb8a65198580aa2c513b1f290db18d6c3f8f13c39bb08964c4ef5ccf2eb9de05aeba0533d699ea1c0f1887d2f6a96a66	1	0	\\x000000010000000000800003d54df733934960dd655117f5fa7fa53ecbd6773723ccfbb8fbf5d03dda4b6f7a93b8e44d58d91945bc9fc539bfae0a7144900a3f2427dfdd27ef3ae2e53daa5f7450e308731dc1c741a00ac900f980480ef7d9fa498e20d9f5d77d7ff1f6eeb1589fe82324d184c825a836a82228e68c3bcf0606829e81c17bd584f5299b23bf010001	\\x318219d7bc4b7a71252590044a08f0bb78e203bbebd72d321944433fcf0a3bbcdd31136f4e9fc71307dca1277ba0311f7346269a958ef24e043e311a50952008	1647856310000000	1648461110000000	1711533110000000	1806141110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
197	\\xedad991104b8959dd943520a9c03289d14aa8db7479b18d2e603bf78a32168e29a899c4c5c817fca8352c704c830b9f8e7f812b156908f1178905c8cfd373d95	1	0	\\x000000010000000000800003d1363ae1d389a66d05aad24dfcfd15d6873e1e3974fbbbbb4a02bd3daeffc4a4946cfcd62b067d37e909fdbca47a1df830b8ffb1bd51ecc700d6b91dcc10ed7bce8925ddcc17ca33f8b10cd6bc1a13325f78b996f95ef41d72f91b294ed242b7bbc3b48af2e93c96c24815992e9f22405f71c480799eb23f6893f21195089b07010001	\\x8e28279d16cf90fb1091f24442ee796c874613408330c1efbb2c548710c652a5759efce8f2e2cbc2fb6e573aa3a9449ef002ab24b54bbd5bc4f788487021850c	1669013810000000	1669618610000000	1732690610000000	1827298610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
198	\\xeff1a7fe888a532bdfc19560f26d415328604c5c0a78abdaba1cba800735360127f5dfa9c5fc90eb4d969bdb197aa3fe328b8905f1afd6aa950f5784b6b0d855	1	0	\\x000000010000000000800003b7397c09df1e74e8cba102a71f0c528438d40874d63e1c315092c626e14dabb1ec54288eb35c4dd103118807f91735b85db62fa8d42a6c0fe74908d9627483bd12a898ac1b0eeb2f60ea5925f991179aa8c1e72894a6b1bea485ce6862a462906fd7d974f914632cacf371ffff763850648b7e5d75a68e96648ec39b694af3b5010001	\\x9e8adabcc5c223d92512029457ac43b18711bae5f38c4b136ec5d5c05adecaf5b296e420e8e79b2e20ccb3161f4207b404289bfe2b5dfc35e8593284df5c7805	1648460810000000	1649065610000000	1712137610000000	1806745610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
199	\\xf359fc3c838a1b23f7d23480b415308b6f828ec7d8de22d45a6bd3e3c0d549692783eecbfbdd07fdc3723ca182a91bd148d189f9d1770ea57533db610c293b88	1	0	\\x000000010000000000800003a154451accc97446e028a728c304615df3c1636320c3bfdd28958bac896cf5163fca7a4c3667ceb19f5ec267d30362c002ea012e8b5d01809e12f889f7465b690467cfbc6cb2d196d830b1619d56b5a452f4117dad7b4351c4f34056534fa7444aa3841669d015bde3becfae8987f98be55b26ab6c5dcf6fd50118923be5e8ab010001	\\x85d6a33baec8bb28c834f9baa0e5ad489e9ef3a06190137164a1db8ed7fee5c1aefab2d6fbb718ce586ae51d419cfcefae19055b38f8771e01258bb021bd8b04	1676267810000000	1676872610000000	1739944610000000	1834552610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
200	\\xf87ddd43d706ab7dbe864a397bbf3602e9943b52fcc8afd6d02650b7eee36a8549ce21f37479de5e3ea6d8e75ca6f027f0e54fb94c144f6d3165dc1e05b5f5f9	1	0	\\x000000010000000000800003a3e406357a2110dd633f4ca98404bab67049ef8b074654fdcb2f99dfda356d07e4890e0280592ef806c56d914fd3d9ac6bcf973a2c127cdef4c0093accd1b540d236290ce2950de201be2ab3ea85e45222e2c63aa6b21d12cf87312cb71e99576eb2295e08ea80fc3e7aca20af1639222a1f482c068a260dcdab297032a55f65010001	\\xcf9a3ca88975a98519d1e9ea484cd2cf706164635a0e11437ac772b9bb29b97822272f542c040701754880fdf197064451d333e5c6b000b205b237352a25770e	1650878810000000	1651483610000000	1714555610000000	1809163610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
201	\\xf9f111a824c21fe3d9206ed74bebfb923e5dab9de09af7b2856767f9b4d658b9aae1ce8dbe771ba16055a0fb9fb606821732d97d4d69e2985c5e3bbccda175a4	1	0	\\x000000010000000000800003c357ad2298c501009bf83e761f8e8160f632f3df9be55e68cb2c3be6f21860b1953c5b1594a37524576c4073a55a7bf86f62c15a6ee8d9435b5c54f80887e95297195a750ac3bab7f64a8cc0b4ad189b768b715b0ffafa1865f33478c2d2d767362cd31d5fc5d8401fee9bdaacd4cbea81db8e7e9f25dc9e1471eb6eb1794985010001	\\x0ca21cb358cf8711707f5d7514260996dac0f60fe8f03c083ddef842f18b818fd0303692157a7f5cc1655c58827a05e2002c12359326b40bee7081f10181a902	1674454310000000	1675059110000000	1738131110000000	1832739110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
202	\\xf9ed949300a35bdcb84913247a960bed4969cad5ffa9be1ddca5e4823dcfed37493f460b0acd028d4da571a6bff549f1642e55af451e4785547c5b2223170a19	1	0	\\x000000010000000000800003d878c6a97c394b4a2e087554c37c5759a134b9f59409e4fa4db9b97be19c9ddfd2626376e6affc69892c1959093fbbfc09fcfd15fbae486568799000b457bb6d69cc7131b2adaa69c10db79ca1caffc8f6cf49feab759fb4610db62e6432425b9bf8aaf7890f96e6fcc779486c76b4377374145f618d3d476f182f84363aa965010001	\\xdfab586edaa8bbb3baccb94b45a8714cc7afa76245bda2411ed1b1973ff8a822da6e245960d2d7f707bfc34378d4ffba81b57b64a5c62b4bdc860da629d9a00b	1663573310000000	1664178110000000	1727250110000000	1821858110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
203	\\xfcfd830d529976775f9282360b014644fdfbb618c11406b80b6bcfce0cdd6452cb58318c906729861ecf05e66cc11d4dd47c03f3451ea009f3dce087e6ff0975	1	0	\\x0000000100000000008000039f569c8ed37d197290146139e3efbf9f561f18ecf71e42448f1f56ec064636ebc6c91fa533b7be25ea2ce0f7ef82fd5805df8fc8a5b2b601c95ae77aa7d38a03d704c23ee195b7046c709ca7a7a9f74453613f7afdfbd40aef0a9f68799acdd3be5b4bee6cef77787511caaa8b93812c09c721ea80a86f742e6e64184e188937010001	\\x388c90eedb5b38c0abd39fd5e8cda1854b83382ddd10190c28bb5ca8cb43944ba34324247b5211a7564a182954d58417f10b9854fbd7d4be2b5190583309a608	1671431810000000	1672036610000000	1735108610000000	1829716610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
204	\\xfd45be7bfec76909c3c131586e747d3ae49c33592b5c25afa9aef9243465ce16a2055d06ad16e8684414a1c3ea39965ba441f45d817aab28229c762737363090	1	0	\\x000000010000000000800003a9827af836dcc7b62896f38d685f4d6ae8385b0b4c23baa79f910d28e2a599b28e54c4f5c73c7e01d9df41d17d3083e77b8caab51dbd3c1ccdc62914dc0c158dfbca3cd76803bddb847957fe436a21448161de12c9dd99001090d82d9530817a070a82b18bcd1fb565d27841e20edf3a23f57ba8799223a2286e3d5909883153010001	\\xb67f7d9c80bb4a79b14d56fa9b35e974b47c8f0552f9fa86b219a66e576299048855d447b9e19e4cd3ca8b7ad6fa405a6df8e4393c6fec4604be8ed50bd70f0a	1658737310000000	1659342110000000	1722414110000000	1817022110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
205	\\x01c2e3ddcff6c0af2dfbd5f47277d2775fa6b306dad4682fe46cdcd5a4ee3bb903d39d012f21b73cfb440cb7741fa17665a785f80574ccce65ce1c444764363d	1	0	\\x000000010000000000800003bfc2e4589af06a833e919cb71f2451c26b2cdb9f1d2bfebc16729a01b841789309a51ba30b29f64255fd9390516c44a377b15847bd73da18e32419921c7bad47f24827473204c862a8e9991b141ff685a4076f2952542fec38597315015c916df5aff682dc88d78a1b7f330a34ef5e99c4d41029f0a8f7d3850a452aa6ca0f0d010001	\\x28fd1115baa5ae2b50e526b1f24c3437696a477aea240426d213cec1097ca96b3b5b60cb340297bfd46a162e0859ad8e27b0e9d1ea280bd7eb32db94bc0b9604	1663573310000000	1664178110000000	1727250110000000	1821858110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
206	\\x04a2bb3fa8e56de85558d4f4ea7386f1ee385890214de7ad3c7dbf2b31e7018db2949bc3ce6202644b56eba8057b721593fe624fc4ea02d41c1597db1f3e3c15	1	0	\\x000000010000000000800003b4aa35e03b6bda8ef10a1b94a82ccfe5e7184fc32f8d979ed2564a754a252a6f5fdce342d1de9e156b3f854be1a1c25cd5fe0cb1dfbee435e19c4310a31a917735b9ab9a477923d6f1a463c2eee722886a0a1562762f251213c924160e4990766239015ced0b8c7ddf303d24f80b5d7abcf73cfa0fb7a7e34d073407c5563771010001	\\x106d4a65f31e73a1e6d9fcabe05f2e4e84bf6692d97db94723b3817bc650633afce58a368ec958080b5897f18c0887e97b9f657f6ffd58bd639dae02c2d98f06	1646042810000000	1646647610000000	1709719610000000	1804327610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
207	\\x043a1d50275e36b5d43a21c9d4e93564afcac8c1f0e02567209f947a6e9f8524054b6dc9956e798b03c4ab42cf564435b2b372068e75bb6247482108afad3b89	1	0	\\x000000010000000000800003b7482f915dbb8a2283c5951a7c0d7b965040e107b1d198f882316816eda7826e7510b3e70270fff5753da3b61f08e469b91ae311210ea165055f62ca331311c9761abdf84a92be07fae31288c42e097511d8dff91d1f71df97d990522650041e1caee1156edcef0be30f63580767a9bb50efe86b8a196641aa272bfc16b877d5010001	\\x46b6d30679dd9fc50f64664162ccccac31f16c21087b1423795ea15dac887a4a40f210359e516378aa4ea7f0e99cc1e4bb6d311d297d11db5a9371a0c346bc0f	1654505810000000	1655110610000000	1718182610000000	1812790610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
208	\\x05ba8903131d26edc2129caa910089a1d3274cf8bfed7a52ee126b1565bc80895db197a425d4540bbd01984a52fffc6bd0780524486a22c516e184eb6b8a3e13	1	0	\\x000000010000000000800003e39b884dd55b5e81398f5036cf11a40237fcf65a8d092bf0ff9f18d8937f28173a8a29623eb71439df9f5865f3af9895e684ad492e2fec37fee6363eee73f8ca25ef8f8d75a8df614b0ab8950ec63a1b525d811af4d6b43e83ebf08b81af1addc23672ba3e57e36d3a82b08a941926dd4012fb80439b7b9ba6170af53aa4bb1d010001	\\x651089b540d52c5007fd878a6e3e0aa2f75e472d7f44c64d83789a234679af4668c2cdf6d2f09a78e50fb493e8a7b4505a4df0dbce279d56825912582e1c930b	1646042810000000	1646647610000000	1709719610000000	1804327610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
209	\\x069a5a600924f08212466a6da2a9e05360b313e69549e807a5a6b93c648c023f6871e8bf7ea665c3aeb59309011dc4d036a6ced34b3a2ac8f690cfa881f158b8	1	0	\\x000000010000000000800003d17082051dc0e15f5b4fd5b8b35d4dfb4a84f773d1add7613baf6339058bf16e8bd8423b4cfbf7d0261ee2e807b9fdd2a05dcfa8eb94eff86e66b63886a82420148dc2b69b9cad95d8a59fe1f869e4045a4f9d51d9777eb6d635ae4d65c657e7a15293890381fc2ff3db824768ce2769326e5a3073ec6409eb17321a8602c33f010001	\\x53a92d52cb7e9ba3fe053e1e59efb1c53291ca840b03bc3c41e91fb9a5c8cd9d3bd8709acc2f42f4c951c20046953158f68ed854889c14927f03398963e4190a	1669618310000000	1670223110000000	1733295110000000	1827903110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
210	\\x07c664dd4999ae809bec9ca8f091fe7caa1b2dc4fe1ecd10d362b4b1e3fef097fbf0be3d067a558f73236067e409553d37d0685fc18dab7c54a132f463893f38	1	0	\\x000000010000000000800003acc56edfa2d829cc4b2fbeb0099faa613989fd37c62bb9775a5965333c25bdb6a018ad237bd78f59256eec7f86a0d8274319fb06b2bddea6153910c2aca5c6c6e59243c137b4255e63804b3c4dd73211962883d3e5478ef66eddeaa7b32bfe52634c09c4d773be426223f0a495d3c5f7c92ed681032d76d211aa5ce2270bc4cb010001	\\x65f22c07a590f8719d029062d369bd2218de186f2817274f1da395feab10f653e40a6e3a71587f87c5b29749dda260634fda72ce7317128d56242ff2e525a704	1648460810000000	1649065610000000	1712137610000000	1806745610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
211	\\x0702e45abeae3c5d3243accbf45db57059edfaae7fed2e6149c84a4c90647ca490eb1315a5ed995c4ade070d2497e73a2cff8e227e524576606dc8ec9f1b092d	1	0	\\x000000010000000000800003d8a90dccd2bb11b2906d20e12275abe47b479d3d0d3f9dd47fb0f2cad2712e688db543f5639b7fc3a061ec601ab2039e6ab630b78d49ca5e47c647ae50c1823331475cc9ff0e5ccf27f096d01ac7cc2f2d6d351416046858de15fee0a25d9e5b83470ce67a10372152bd856581ff5230051146bd60d22a9b605be9645596063f010001	\\x7389246f364ddd730e500b737bbb28cdc0b283be0b219352bde686a996a76eadcf12746503f3d4290c93437bc9fe26d7eb1432bc573ab02321e3d5207ad6590d	1669618310000000	1670223110000000	1733295110000000	1827903110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
212	\\x07ea34453be3c27e30a498014593553e8175c3c77905cfd129cbea8bc2e1e9b0d9642cebb547f1dd2e960f8b6be5af2eaf52e71ce6a3bc059053dba67c5467e2	1	0	\\x000000010000000000800003af97abb49b1bd0e6ee5de38ddf8aabf932a47932f5333b091339ca78d21668cd214825aeca5114f3f16025e174d485ed7a16aaf57a7d4a4eea6a61f7d7c54a69f132f5540f1738eff3828ad6f5f50edee66275a77b964fc39d210dd64804f233814089f5f8d92bca0ee01716aa4b8c3544cb21b1ca0af47b2bb9e44c4ee5d383010001	\\x18110dee73e6cdc199751c3e6e13bf578a6223e230a3bdcdf4dfa5f0d5506e7c9e0f2252f4f962802230483b447cfc8cfcd3efa533009393267e3e3ef2e6ad0b	1647251810000000	1647856610000000	1710928610000000	1805536610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
213	\\x09fa7316695741463573e6b21a25e469ffca0f6aaee7e84d11d2d3a7b51fa1ae1c79160666434daa60c8d645214264d9b1927a172f360dd3754822131ce75168	1	0	\\x000000010000000000800003c16c73c8078fd986e2f5d8e68bc369be2f72f5314129c242818d0f56ed83b82c756a0d0ffac51fd52aa801b7740d17fc01598e1f42955cc25c55c87a31221c070d2201a8f74a35bbd5874577a5736966b181678c5fec9d7da299068e0a8c38191ef1e78f69972bec7bce2686d77342ef74b292e44e88456bb4610a320a80108f010001	\\x8d7b38c7a83575a0c7b4668a74b0f3540730ccda9ef84e866387451ab71c919fe6d08f29412ed53b48d2f5160ded4720ddc07f34296d41f68863ca87b797d602	1653901310000000	1654506110000000	1717578110000000	1812186110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
214	\\x09f24bf5d67dddffaa417a975d0d7d804bed7b3beadb47612c954120c00d5cc6da99084951fc886c94c6be260046612aed555435527bfcb2a2ee69fcd1a00257	1	0	\\x000000010000000000800003c91b1b66805fd232dc1ea80f68b0258fe2f0d1b0e9a69dc076627581c4d3d3c052c097e9922582bf1fa958ec40c6c5010b6f83193f198182f24afc6839e8892f31f66494a426b9076d7fa3a411881bdabfc1b66c9bf5c599e60a60a9d512cf50ebd0cb196be75493c5b7d16c1b17b5428ebf73759dae4dd7d286bf7e0d3d4297010001	\\xc8c1a87dbd8a1d80b9da6533f10a664722869679470a87c0af58ee0a7d42f0e5ef09c30b6f8f92628cdf1ad35bb69d8193a47b180a1bc745aba37d73bd043c0a	1676872310000000	1677477110000000	1740549110000000	1835157110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
215	\\x0a42230c0d660ddec471115035e2ef90a79f5b923bb99d8f6a1a9f468abba661155b1b32bba0289784130f2c0fecc77b19b2b9b11777a56424f049ce8a1fd00a	1	0	\\x000000010000000000800003bc54545c9cd8197cac995856ba380518b1d609520bb6d1c6cf3a0051b4bcf0f4166761915b8d435dd0ae3ebd109a59cf0a849aff1d0a1c1e6849e3b3ac02fdfc652fc01de4b6f576b8fde5f15cdeb6eb242a7e4240026df7cd9a23d847d219f9976fe45476ba5a39d4f3af31e748119860fbe1a78577698082213dd6839e9371010001	\\x50675f639867f3d839cf4732967ea1ce39efe05c3222cc64aea5b62d557c922d663db3b388946d77d21c667be09f9e80c527caf5458b37f1133d4a23e074d602	1677476810000000	1678081610000000	1741153610000000	1835761610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
216	\\x0f629749d9b22201bbc33f9485d5f5ea4297eb88198dcc73e0b97a77258d92b3595bd6d3e995cfc8ef895a86f0750e4e4a219e4f4385a0ad0d4c1a78eff3d87a	1	0	\\x0000000100000000008000039552c4cc1513bf19ee0c596d0f60b689afc516c6e0cc53e71ded50e3894fb010746e274307b18c4d70d9553c8314abf65ebc61ef1452d72d0440c0170b8f54dc10d314775f3ce6ae6596de6b84a735482fa5e0f55ea1541ba1efa736e433fd0cd0c028c4dcc4d4fdc4e24a27683cde911a14be7fd9734a66f464675bd52d78cd010001	\\x3e4f2600152254f4790ee76041d3e16f2a97edf3fd760d8636cab6c777f073696f51a24d9f77cb92fd69573357b0695c756cc12aab7bcbf3aee7e2ebe622c00a	1669618310000000	1670223110000000	1733295110000000	1827903110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
217	\\x11d289651f9d848499c2b87641685445a751cb0888836cc9277ca5b6071c06c1a118e11982399e97e3165919d2bd96afedfacd59ebb7873fb6495131baf40205	1	0	\\x000000010000000000800003c45ee2e9ce207ac69a0043bae684294d0fdea8e0d5c7aff3d853d7ea86e5e78b40b4bef2086a7641b5239f96d0600ff2f842f0dacde3cbd20dbc756f8da40769db694d2745920f35424b61c9be3900596f163703a824795847633cf9ba9838ba665f1789892a8b8d93a6aeded6d711434437e27f4999740343dbf02d3e07f245010001	\\x164d2fc0d9438f52282a850f7d63ad5d395a7b439b20cf2338a69751da7e0ca0e0c464da86ddb7b98aee6f3626f5b462874f75c6830a8de3dc13a9e486030f0e	1652692310000000	1653297110000000	1716369110000000	1810977110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
218	\\x1176850baa536cde4cedd0957da302b1d55df1aaaff1881bdf6fd10175e4bab4a11a48c8a24a071ff8ba55dff9c9081980cd0d59531f58365970b9ae0aea99aa	1	0	\\x000000010000000000800003d9424a7dfed0c7b6028ec5139d09101aad3859784c12deaa1f3a825276fae8cff103bd999ca7151e343632eff5f2d63b74af470578c972faa93b88f0064144e76b9463d1883695b58d51d786149827e30a256de4a4194f77f13ff606d0dd93b2bb5fee7c8099094e1f9dba26f26b1666689a99d255972e0cf1ab31bcad98cc27010001	\\xd6208ad0e86a4fd07922c8eb5817c891d88efe27e28e96a953e2752d5f367c350aa6d1409269248a37805df316f02cd802974383ae940f352cd99dd676513a09	1673245310000000	1673850110000000	1736922110000000	1831530110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
219	\\x120a980872ee2a57c86e05b62c0b23a4fec6d6298fe7106388d8d88ef15204a3437ba1c0cf2e114763f735a368630dbd35b239481e698243a022ada1cbd64ab5	1	0	\\x000000010000000000800003f003bfcec3501a66626704497531d334a3d802c7c19b5b38d1408febf999a9af1a67c4153388455aa50d14a0cb1b5fe973f0c72d07a5c4bcdbf0b7a7f59fddf25108c939589e6380c10caaef51033fe9042ac7d374c92ce0267403274fc905231044bdd0a4ffcf00f4b708dbecd9f9a20ac11b8571ba4f9c6ed91b5611422ebd010001	\\x9e9c697af979403fabb80f4b97eba30b42feb343611b62e87d379d0559ec2f150f58be9cdd5a9fad82f0d1e901c5e696b14ac03baa95240106264031492cc301	1672640810000000	1673245610000000	1736317610000000	1830925610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
220	\\x138efcb71e5d8604fa047b69e6200e02c65b921181fc149f04e22a5e0765e6df0c7346420a1e2905ca0a03936b93d6c140d7c8f15efa134c5e85ffac1083418f	1	0	\\x000000010000000000800003abb536286934b420ba7ae77ea059cfb54553356e1279dd210aacb8b2c6871cb6bc4f882570fd25bc94388c617c36dbe55d680da142ae36bf24b6d5838f5fe426cc9c4f0d69c74de4edd55e4f51ff9c27f3ffbfc6968262bcb282fb04e43b13f85fe1e517c6648ff077141843b623bc087f7df04ff798487110c1aeeb828d95d5010001	\\xbb08d4ce9cb7c17c897b0f6b07bbf8b293bae0d73fb4e727d5b150adebf2731252293bed7a5aea4dbe085d97a02e9bdfdddd1fdb7df0a94e5db265db0eaeaa01	1676872310000000	1677477110000000	1740549110000000	1835157110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
221	\\x15fa59c0928dc1ccfed166258d1a4966c21f1dc58b92973be983dde1ff8d2162a80008821047b995d70bc3d642e9411518bf83ae2745cf6ad45e81163153e4f6	1	0	\\x000000010000000000800003dceffe9be34a7c0a13faf54af54f2fd2361385e42dd9c5da09d3bda3c394f73985d412dff8cff8d54cc180addee5deb977c4adfb7e3f17824173ff10fa126ad512d17f792a56b38447f87a70b9ec07fa61de47f62bd381368ad2fe09a22bff5089e1d9fcd61ca4e38ad450f34a0250f376fbaccf5c88ad5488701807d42c7bd1010001	\\xf10ba01c2ff98d67b986f894a23671d7abc7bb1d087d9678669f4731fa7734e9e0779cf2afe22ead57288fd27a08da517088f48bb793ef7c5f2ac44742f9aa07	1667200310000000	1667805110000000	1730877110000000	1825485110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
222	\\x188a01a7175412d9d45b3efaddaa0c34bfedcbafdde0f6bd4ec307d9ee3fc4734532fad829673a72937f15df211b18ecc9035bbdd309e65f93c44a9949f74447	1	0	\\x000000010000000000800003d9adc14daba3d4a4dd18638558ec2b145151bf767679b6a0cf6153625b834b08b5bcc90141c4a7fe408f672a358189bd2a71e706f9cd17890663d24c7d760c00dbb339e14a45e67666ed70ce78f3bcd2bcf1e03f79da5e34f71d7369e47a4129bbc4b0e788fcf5c26755cd97f5e704324bb3561e7e34ba36a81d3608e0422ab9010001	\\x4d6f7a6bbbbf2016e300691e0cfb4d397ecd3dd0b34db1117fe22b4ea0b0506888cdc028eb933449b3f6f9e6eb1ca3a6aae7dac400d60f1a6a73621b415cec02	1675663310000000	1676268110000000	1739340110000000	1833948110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
223	\\x1aa2ef45ccd6cfb934d1ec915fa8ff0533660991d5ddfefbc08fad519adaeba2cd96bbb0abf6700fa68710fb23fe3c5303307b6c3756b1fc221776f5956ecb55	1	0	\\x000000010000000000800003b64d29c1ae94c799d81214b721e10b0ebd334813ec5c80113316dd44fddc80dcd1e62c57c8f9627cc632c2b14e4d50c7837092d753a7a3138b69baaa81232e48cef24caaf064489ad9f249bb468532b76b9967a39a1b3e781f965d623ea86aca6730cfb22e2dd102006dee1788d2752ee63f6131759a399677329debfcb47c3d010001	\\xcec9137513e1badff56e2c1b2ec12dacd0458e035fcbf6dcfcddac7fc587a09c1b82dd16b8a3733bfc22b49288f657b009cacb38a234d8a74d3c721509ea9c02	1668409310000000	1669014110000000	1732086110000000	1826694110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
224	\\x1db6aa3ec10f601e1e74f45c2523dfa90a0d1f1b365efa86c1569a708a7eaefab4f26a680cb465a8b2ebcbe2207d762d8350357e469c11135034f5a228c54ce9	1	0	\\x000000010000000000800003e7be294e95b38c098949bd7568941e25f5112bee5d71c27d6cd6012eef47b84507b8ece2229e93945c904bdfef9c35a83af97a48e4d262f08af46bdcb1e34a966248293cb18f810e04ae7c66a0c78666bd1ec217b38f639053abbe67a6027f5fb06ef94ab699f95effcece7e5902ba13fa6c39b917c7b37b11b196693b757f7d010001	\\xadad3ed42671818a49e8f8a80126c12ff7425363d861d7fa10bf0f4c9c700094041d7b59690e2571768142b1b95ad856b0bf7ba375be823b450cc8d69a1f640e	1665386810000000	1665991610000000	1729063610000000	1823671610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
225	\\x1ee626af4219ec0f9cea443c4aa8c64a3ff300df1133cb733b4b9eaa0ef3ddffaab84c29cc186ea1bf5492b5717998d8d31b6215c6e87c0831865380be4209c8	1	0	\\x0000000100000000008000039de525c53369341b0903dd39a4f24ed9ad1939421a8e4d250732e046217144e8219a1b87ac4677c5aefb235311e1fbbe667b822f9c9d4632bc336a3c3feb9ed819d138a87ef5bb393a52bf3ce98e25a1ba08e55d37ac4c69701ce28e3ab9e5dd021ff36d72288d53fff299e505551b87831ccfd346efa861567722b99aa4add5010001	\\x41e4eb583fa36a719e134df06c38df4a84e9a03ea1233bbeb48d7ea85527bae4154336896cd70a71cb40c0f0396b5edf996e2a6970cea21daf200bbecb59d40a	1662968810000000	1663573610000000	1726645610000000	1821253610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
226	\\x207eb8671b0d0d9ba830e1025795aa545a3a616bf7830931d1fb19dc995a7775bb172c5850f34760b7ca1523f4bc9e2d374e32bcbc967de5edd552f515dc59e2	1	0	\\x000000010000000000800003b8068d237b70951572b5fe03ff3f96909772cd1f6d09f6038f2aec5058243aac198584256923c7e4231e22a7e0d6cc4a02ef425b00ef03eb68941c4032de6d5a06b58c0bf981e4a6128324b517c59d742872cb0ed86e2a2e7d6184e7cc7e4ccb14ae26e25dea43e973ed3da4ce55d80100b55d3f112a29f1a67b7a02ce583dfd010001	\\x105745798ea72887246a5ce4460ef10af86ef5814280857eb5c7375315e6509b38268b2a0cac0e08815030a6a39ab797950d8bff0abdf0d745991345cea5ff0d	1652087810000000	1652692610000000	1715764610000000	1810372610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
227	\\x2122574d2bb12b80e3df8d2ecd47dd65805aa04b9f1692328648783c8b3f8e92573a2bc058902278ea075f7d70cdec548d4f71b63b4bcccb321f30b3f847a220	1	0	\\x000000010000000000800003b64e3712e87b24acd8bb697ae19637303d279ad6b68d9b04a4a5b36422c9e2d2d44bd32cf2ddf57fcf931568072a55303d13bd0834b980ea1c651489157dc791ec919dbc0abc71f719593fb540a1e2a60f918853513af1663ac8e4a146a1e8e12b33004a9225c9f380b6a43d76ef794dcb5314a9a80ca70dfda91a9f2dd540a5010001	\\x60c264c07414ec9fb20ea7ff993deefabb85e04de5e68c61a42d3da6337e020d503f29fbcc6dc36186f81f6364882c210e1534c707c4714a9bbd330c9f4eb806	1650274310000000	1650879110000000	1713951110000000	1808559110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
228	\\x24663fbf7109e00eeb8a6cfd453d62582e7439845b358d6283417a7e8dcb260f8a648e50ef1efe2579a09f2f87e7b617e715833a5dd1270ff3fa6b001bc21914	1	0	\\x000000010000000000800003a427e32c0bd4b9b0bc7a6a17c389e2fac34027a05937bfc58e540fa78c021510f17637092a5e261c7ee3ec61ccef503f659e6ede59fc6fc3d16e8e2583f2dcf3b991c02d79fbe5851d1d86b51081bdcb1ef1db0f20129c0836720060b059b737ab6ca84a2e0d36d6cb81404637c1df9457ae479f730ca5839411a3fa72d17095010001	\\x1d8354a99a93ffc234580df438b474b01ad1364a9020b73f5108607a1105ceb46e34a556a1e29cad95f97f77af546d4b8667146b99510b7296bbe9719991160c	1663573310000000	1664178110000000	1727250110000000	1821858110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
229	\\x28ba7de09de12de518d380682fc9b383f851576b1f2a0a4e2230af15860737e2941ff343c829a625bd58f1558684787961ebe6f6f7d6a73e2f4a1fc3560705cf	1	0	\\x000000010000000000800003a44480408da3dc954c3e9825f2be53b2fa4efa5c66196b5f8a305a9f8d082ab1e568e2cb20193a8a7855dfd94eb35fcf46d72c2e51147b9c9d0e3137e832986b0e5092c42bb2fedf49120e6384821152d50367ebdab67b155938678cce4546199d2e77c6259f5dc1921b462eb70f0bcda8dbbd4f7f29e0996c9a6f0ac37db3bb010001	\\x53242d28d96489103f5df1f54d1049b642e6401cff53ac2b65f0a72ab394b9aedf3dc0444f3fdbbcd8bd85383eb1f8025fd23b7103c69ef49e76201acabb4806	1664782310000000	1665387110000000	1728459110000000	1823067110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
230	\\x29bef9ee94499f0d0007fedfc3d1d0da91ba348860d100c4e78ce54ef2f86c82a51f10093a09f92f13844778a35af5c826b475e0dc271fb166d07d19b1dd3f84	1	0	\\x000000010000000000800003ade5275434ce3bbfdb847503bfe8c2f3f03f812fe80ddecc225c26b6a93310ea05ff2ff12477f3b55aa0ecf07fa1cd47d91f05e501b34cd712b14815443bfdd162ca07948e036dcd40667458f4caf94656761e97c6f2f0c4c5b4b113fb7123cca279a3fd20b1dfeb9b0d942e42a06b6d69e078aa32ae93af6c6e796e534bc85b010001	\\x2348c72abd16d626a7a0c69e2fecf49b77676327230261964d5a0b5d4921979dbf4eb2a931332f31cd5b50cce86ea3a5973a5b37d6de185848d78493ab46e70a	1670222810000000	1670827610000000	1733899610000000	1828507610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
231	\\x2eae9789c1783ed9c1803dff419fbfba78d987a35fdce1ee890473191cd8d6457d4e3af907da271593a6d48d2086f0b9f08d4783358baac220b734d5b2c00512	1	0	\\x000000010000000000800003d36d68354b2ac1ec8759282976a387899a476a9c7f8ef334917a4f4b0cf41ba3fb7475d575007f0dc26f3b06f0ca3a1cd99a4384e50710e04dd8a6f339c2124e142795a6557f973a80219665b86775fd7c55b5782d5d4aa9fdec28c2f3f1ac410201675f4b0a9d541dd86cd383f269c669c4b652473c55408d389112ea0cdde3010001	\\xabaed63bfb0cd9730eb7d28b9acb660b1be784cf6f4f69ef9852393142fb6eefa8b1f1c110491fbc9121787ad79cb1cb0203998782db59da334f729d61b25702	1649669810000000	1650274610000000	1713346610000000	1807954610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
232	\\x3032d0df0ecd0b0d1b3714eaf2e914b7cbc1cf970f2858a59ca2396cb06172684c82816373db1b4d77bf974d96af2a26b8c2dd3b4baa3220a1db5eeab2505907	1	0	\\x000000010000000000800003ca909467aa41c9413894c565f40328d325d43d481822894cc9abb15f73dcfc3c6d2bfd5dd7cd584692d8ff9fdc0f52cd48421e3713cb3506f454138abc8acbc6a6047efe99cc031a4f75a6edc41d2d5ba56a0c85f52e79f5b49f7b325bfe2f7c1bfa10630138200416e0bcf6dac9cafa6d393e2ff3c9f25d07d1c69b7c4a91fb010001	\\x60aeb43a616df8ab9b28016c25fc06f924fdbf4524a1569d3508fc809947c992347975346e6c1b8677fdf09889e641494d24a7d0eff3ba0275e7ef7284a2d808	1665386810000000	1665991610000000	1729063610000000	1823671610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
233	\\x33e61b054bc5080612dfb4ec2985bfa3b063ec59e281f49743178ba1fd73a37cd8eaed47bd12b24701be9bce113981fa9a8fe2265f279e80b0f302e1114b74b8	1	0	\\x000000010000000000800003d3eac23a1b4f0ea7341a729e2bc67c2e91684d1d9f3e94bd069b074b449573ef532279dccb350300009dc375ed4f5218998dd6c1a60d14abd06323be152f7ccbf75c51c0f664289cd61f92cfbd4eee228fb090cbb64ac8a4ff9d9d18226059be9a575225cba241baf18cbbf37d0c60cd18616bf1319230664ee63de893a1082d010001	\\x1709f605ef0fc3db423d36affe3e23ec49ff1285ecbd898561411c5874e629f2b07359aa804369fe74ed2efa8e57c3c2cb393f7a5c8795b743e088151891f102	1653296810000000	1653901610000000	1716973610000000	1811581610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
234	\\x345e0521488452e0a32f201c62c753916b5dd1288aaf9bb5c849f7deecba37ff8f1d7472f88174744d7f3ce6950f604e1c9d17278391550f8c7056783741efa1	1	0	\\x000000010000000000800003cd31b253b811c357dd97ec68d0cf6f1d274539b947b486ceef905476e9185982252d48ea79e5db3cb64b7b5b70c49563575f0a365963db0bb75149d5f4f81be63c841bc8cf5f0e071138ded6d06bfd535c7d83e7d6ee9e319382e451ff6ff50bb5a90afab05333c58832c093ba4122d0aad6bae3d000f39ebc26c9e5f74efce1010001	\\xf27c68f50919cd4c76eff1d6ac3f2850fa0a82b80ad2cf40cb5e8ff18a19cf9ca89c22d7399a1557c0064ba701208bcd46f77f8661f860cb3c0c77dbc84e4b02	1659946310000000	1660551110000000	1723623110000000	1818231110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
235	\\x37e6fabc48cdf46433c6e80f46553b26d15ee00fa7a81cac22786ebedb7bf19ddc6fd11bdd0032b571b68e694423521e1509dcae4eedf5091cc5bd8463e53269	1	0	\\x000000010000000000800003c30b30f8fa45ab9961a5053a85bd343a94d141b997e70e0d54015f09244877a8787f52e2cc29a84bee8f2fbbd7be174912863ae3483dc956a7e02c1942ff42a02789214c2fb67375d614ac9db3b3242ac42a455008833eeadcac8e0b0ff9138b88cae73658aff17e333fe1faa78aa33022338ee25e9f9999718ee625446c5d09010001	\\x49e64b6918ec5b4e6abd8ed9ba042701971b16f214eb7a555f9d51f418dbd30439bfffa021082960375a5ebf714ab112b4726ba504c0afccf3567736bd68ef02	1647856310000000	1648461110000000	1711533110000000	1806141110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
236	\\x38a27043f851c6e7e6f2019ae4f48057964125a6bedfb887acb66966c328e3325ff60fd0df6f376ccd322f01e526ee78d8b10d7b49b091c59b8807a749e1ce8c	1	0	\\x000000010000000000800003a65ec395a76b906d157695fe262979176e8957c31f3f2c6d43a15bc9b1756f22077175271364b894d809273fb8854a0bc286413515499ffa7fc9c64f757e9f950df835652ee57c5aa422637b8c49b3f3dd7040e23f27156247a11760e1cda5df53be0b4b73cd08ff0c78fc48074abb6b0e9d5fe6d83f54121402b15f32e03445010001	\\x784ffa45d1040688a49641e05cb827a9cfd109857271fab80a22550a86fa3f278b4343bac5173da68bcb2d1d54b5cadf5302e479276ad45da578ed8e282ad106	1665991310000000	1666596110000000	1729668110000000	1824276110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
237	\\x384aa9f2ad8a1a228ac1f1ac5f0474ef2dc19ba36ff2cb2a2f6ab28730b8c9ef9e32e82d6701f64b80266e814ca38bf6fbc5bb465c17e3ce66ac78aefce20cad	1	0	\\x000000010000000000800003d86bce31e18942421b4a3208d9be55772cb914f12d58cf7c25c49959e7f37de6db635e7df7e66467090b4fc2d11347bcacbfdbc94296c584d5424a6f41b76a09ad8cc7b38ae71b4076cd73d9eb3d6b8c47fd01095c80cf7af0e90ab1cee328e53d0705998ad5e7abe9be83360c1e611eddfffd65f26e158732bdd8dfb189e651010001	\\xb54285ec1fb23efae9774f5d8d98e16eabe8f403f7ad4829a77ea679b616c3272699f2bb24d758edb85832f8f075fbd131aea38732cdf9324c3efb6323ca3b0e	1655110310000000	1655715110000000	1718787110000000	1813395110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
238	\\x3ae220db0427a06d50c2a0c224b02ed80fa6eaca3d5e6ef61c0bd9837d959c52a0125242c1627f3721549e2eb18d8c484f319013cf7d192b390a51209949c722	1	0	\\x000000010000000000800003d7e619e36a43cf26e65b488f14e5951676945df5302105a7589f9f7c31d70f9eb78b7db573b7261d1b9c954fc81f46b38e6b4d8b9b5e9726b41102a7efe1532d3de480e03dba3c18d130053bd397e70a646447a4b71ba8205a7cc7b8698a56dfd0d49f40a6b3e8da79633b856e4d2b3f2aeb30514391e8e0af896bd8d865a8cd010001	\\xeb7218d341bdc6fb1cf246a23d6f51c646b68240a91dbc79d76ed16ba779e49a67caea04b95023e179b62d7b866266c4b1b8a3ad8b358d4a273fdc3024bda20e	1672036310000000	1672641110000000	1735713110000000	1830321110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
239	\\x3ed2d13ff4a34540af25155701d7ff98826819e58e3b180e570e60da4ae81bae48aea41d144a697970a8cf35eadf3705a80b4a2010ca2e2d3a90bcbe8fc6619e	1	0	\\x000000010000000000800003af2f9592123150a3ac219879df4555bf1787584fe29bc0af623316395fa08d739731d6e4ba589f6fe528df849549bd8af516d1ef2e90a37a7f664ddde70def480fe098cb69f352b4f3e114a968c5ff0f7a93c638be9a4037b331634aacfeba73674a0f918d72a9ab6025a513b8696f1458dbfe68dff3cd2b4e6ef00bce64fbb7010001	\\x5148ccd04ba3c125e2bf27de7fb1bc6ab66bfcac74873048b80a72b6867fb0a3e1c27baef5e55246770026855101248c447acbec3992e082c0a79fee6e1d8706	1649669810000000	1650274610000000	1713346610000000	1807954610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
240	\\x437a80bf1cc9428314048c0231b5be7144b6033a2c986929ef2db3ea528236ef84b0a04778a9c24057fa51bf4fe0efbe9616981de688b2a31a1cd4ed0d61996b	1	0	\\x000000010000000000800003c352748139c71dd0eff7d14e4df298c578fbd16b3ad175abc72bb057cc171748e3c7090ff54a3ae4aba25995e69ce8c775ae1a38adb276dddbff541a44af0e9e874b7395479aeefe7e0106702e459dfe47999bb25103496f1c0fc26dfb1283b5e7beac7c99c5ee1083f9bcaef13c7f981779c25c50aeedc2a4b3228450804cd1010001	\\xcf9fcb687fe3c30e015eed807deb4389ef47a2eb3c72c2f18c8a4b49131af193ce44d0f8fe2a0b97e96bf212b1e80729975c45d5bd314a2634f8fb7e32f1e601	1656923810000000	1657528610000000	1720600610000000	1815208610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
241	\\x449a2ff4d4af0908d83d5fcab6fb921c915a221ea2f658babf0d50f94e562854f07a44f9ff64a5a358d0e0e835e7517cd2de41ba54d44261fc43d7c881aca92d	1	0	\\x000000010000000000800003cd91419fdc643e87d410a6d4555ffe989863a7960a08ebdff844c81d4b8b620ffca87ae15b8a9f01058899f4be3577c990a853e021645e67badbf6ad738b0cb5666d582312cf7093263f492c34d7adca5eb905b2220512e842d0e02807cff4ca3b87dd28ed4e0e4081c771db7cec9ba592034ec514ddba0ca3063e28b90c69d9010001	\\xc37a61639c0458022c245bb03d75f3adc2555fc71845e5ba65fb774af67a843cec63010f2132fe92ef8057f8db9240a4c40693fc8b1475ef935c1390f14b9f0d	1661759810000000	1662364610000000	1725436610000000	1820044610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
242	\\x46fe403ff272bbc005a58e6119059f2099b1b7f0b94a6fbc854005fb7f982ea362ed52ba2b514ad200844562118938c1e3eb0bebf9c6e823672489dd2a9a4c5c	1	0	\\x000000010000000000800003b06546da1191f7049d851a9520c06a217467ac85072e26e1293fe614abcffb96189d0dde00772839e0adfa8152e8fc698f03637b61af6af6b298b333ce93cd80328c85268c2c9f39f8e5015c6fae6ad478121d89a12abf8fd14655129e30fe893b9782f8bc2917b276e98219fddee2758cd4c2cd8e0f12fb5c92eabbc1648a4b010001	\\xa7164188d3fb58e125e215ac7ba871b87075fd16c27e465669d496539ab7a1a1c5b0df99ce25e7d861542be8a4a0e71fcceb8ff115f9a1a1a5e6fd903de6a303	1652692310000000	1653297110000000	1716369110000000	1810977110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
243	\\x46fe6a2d72aed0767c00ea8010b83bc48df4444aaa5e0ad4d09436b97a2a82bfa06148ea5379f49e5097bfe3c1ab60d7b6ff24d16a45989cad4d03f9cb06ea5f	1	0	\\x000000010000000000800003a1e241f93ac6996e2314222e4f6169e02017a43a7aa8e86e4f62591efc06eb8facc3515085e10fec6dc46712f3eb1daa7fd745263fd5ecf96d651d349cbdc0409e60dd2bef80893f34229b9e095f1aa9bc5ee675778bf182cedc01efca800c51dae3894b0e8db840010b529096473bb0a3137af0a190d2090e9265c44eb37221010001	\\x5e591dfeaeda09cc9acd145b1a1393478bacccefc50a0c9852c416b7d32617f80750ba0f20cef7eeabef98d2502f1eebdb4869ae8dfc3183342930f5a39def0e	1656319310000000	1656924110000000	1719996110000000	1814604110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
244	\\x48e6be7711539645a683fb1602bfe2316c3ab842760be46f0c7c4fc0b881dbc1559f273c4198104b260d639595b68446329c7c3591f48f511f4af59b11e44e18	1	0	\\x000000010000000000800003cd0759d2706a85149301f494573047c1dacac1a8533efc4900c4aaf76098437d93e2a942c293a764db9a2f09417c6222ad38ae17ac694066a84a969f708445be6c9eca12c7b9c2a728569cc8c792f538d7a20c0fda9344e85ed327c270f514e911872d0a2e65cab74a1c4d18d55164d7e0379b4718cd83319e60cf4c10ce7c77010001	\\x417d004edad2a70c31fdbfa3dc0923d904a32cf3e06fa804e7f42de03356549ec00f8fd07470b1df0ba9cd457ebbd1a60f6ed12cc100b035f9cd6b4fd3e1d405	1670827310000000	1671432110000000	1734504110000000	1829112110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
245	\\x4a4281128617342490a0100515be743eff6fb1d2fab9230e7b6f7734c6459d0ce07b906504a570bdaa04d536d7f77946468bdc428ec8d4754dce7f487c846fe3	1	0	\\x000000010000000000800003b85b4a2a177115799535d8c55aa9c5b502143081382c527f064a7f4be3118eb5b8fabe592214b4b5f63fdd50baddbfac2f9cd4d98c4d599097d35f581c9977e7ad53106d8dba92fcb2c9360d9b431f16630c580f77aeceb95f9eb861a145f7e3609cc8c6fa3b68c73c95ff4fc1c6251e9908c960bfa99ef56d80f9f3de928a4d010001	\\x6ad517d0e395b3ada4fe47b1566ff6d24396c0b7323ed85de0fee76b952ca1c9fc6220353f9965975037b23f18e571e92f5eca7bb4d2b3332a96cf6ef8c78408	1654505810000000	1655110610000000	1718182610000000	1812790610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
246	\\x4baacdd2d0ae7733bb501956a85fa900a440c90890fd7fea0d393eff406b806f11e031cfef5c317e5a1934ede74c286a94c98cf42e5494e58d687a1be1010ad7	1	0	\\x000000010000000000800003ebb4504d1c74d519702a56e6518528319e3db2c83801eacee4f2884fb9d9237fdcd894febaf3c898fe28e0a13287c595d21216a0336a4a886cd8b1f55efc96ae3c8b80fa61b30e16deb22c34e1316e33bdb94cdcd254be795d54bdcef78ead67a92e19269077914ae8d77f4fde048f87e7c0b80ee41267d0b7f3da8d6f2e1375010001	\\x8c8834695b45644b1259c8f045e029e0b08940ac41e7e29c6e65763a12e1297397527c62fdfaedb18b72b69ff9393299b24b42592425fc281b8880e60f8eb903	1663573310000000	1664178110000000	1727250110000000	1821858110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
247	\\x4c4e2fda7d7e4824c12882de54e5580abc88a974b8fe9a1361c12866c4f32e1dcec0311f282d7c78d91d788cfaeb0217d5f24bff523d7af81732a18296684115	1	0	\\x000000010000000000800003bfa363e9ec9f6d8d5e16f578eac76ed84c453ed594b91132b4b2d07d964194c9be8beb0b668191626df0f580ab26524c96eadc30f9a6d6938abf36389d1a67a276791d175021052b9ef2ffd9677c5567965079a01cc51ec61ba72a840112b8117ce59bba64c26a717e3df9e7431cdade12e0c27810850c1c8c8f6668721f5369010001	\\x7386b1244debff7e391952bc93f1e489b519ca83ea86fedf3a854ef4dae53849f5f20284ddeac612a681142cf707dc5bd26431464af9258435b672e6cb96770f	1661155310000000	1661760110000000	1724832110000000	1819440110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
248	\\x4e2ea76f117fdbb08a09173e750ec12dad67dedf2c31011f9826e6f6d424dca4aa757c556759674222231140909612f1db1d1f15214dfd9a9c22ed122977b0b3	1	0	\\x000000010000000000800003d3ff80d5c66ccddee92065f1ccf3063bc9c304aabca52e74f40e0dcaab69d8f14490aa5c116ffb1d7f5f5370b9550d0c022bb2edbb52f8e4e07dfa6f64a629dc3ed188406c6019519eb86cbd7eb5ff099b2188662b340bf205ed71f382cdb5849a4736245655c3f15cd16d5bd6609ab9dfe376b65795a49defd8867a3a2c3471010001	\\x39197f2867e4f61987acd886166dc07a71bfa5bdd45522f5796889c6a61c8d6c6e78b0c713840b628b4fddf1d33b272af8be30fbd943e1f8b51a69fcfcf9a201	1665991310000000	1666596110000000	1729668110000000	1824276110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
249	\\x503a5cbc54783bbc9db83d9e1d4526bbf6edfec74b45697c810d81dcb5a9b5ce735fba3a75f87090168a22a06a29cbf81ddd6e04cdcd9d9d64a14d521d9ff1d2	1	0	\\x000000010000000000800003da79b19dae2b655f95ad6a9a4d4badf29eae1bf21df1e3870eb8fda7e01aa28fa804c804663e2574f85e416cca248a0ab055dc4a00674d337e27d319525414cbe2e790bbadbcae309190b7c72da6aa47cf31cff0f2fdefd98566af3ef86a42e1301946f7eb1a4c3ee18aea0d50e6f5cef67c79dd9ef92afb76fcab790887fdf5010001	\\xaee11ea8f19687bae437e3c9c09f80abfccc709a798d01731d6fa7571bfaf0e7df9444afd344753cff911ca418adcc59283ba82a60d406878060adedf6927000	1665386810000000	1665991610000000	1729063610000000	1823671610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
250	\\x51dacef7c0d0b3a360749e6fd93aa51737f9dd37c89646dc9b31bf259670865d37ec8b163c8826739b9ee3a2fcec950833776c05b2ebde4b57a7ff0835821999	1	0	\\x000000010000000000800003b64e94e362398ee71142545809867440d44f47f9224a1a0afcc313be5e49b2188700020105efe4031c06f01bf919e03d086ef2c10830269c1f1de64387b00d1ab37ff469c62b413fa1c84a7af38dee4de5a903305ccf11e82b6c734563a26f03552ee01265f81c33f27df1d64c42e9cb8ce42376fa850a18361e326580158385010001	\\xa7d54388235e944742275faeccab79fc4a39d89fa3489f283d28e7c145d11e1a3d7ebdcda5d0be18cb66c957c76a2a9ba8cbf493b8c6983799536b3b216c7808	1667804810000000	1668409610000000	1731481610000000	1826089610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
251	\\x56aa872bef88327b2310e62792b444f420299654e309a4f92204cbff5cd05da4f6920e2862599f93d7974d59dc36f4d86374b597e97faeeb84346208207c03be	1	0	\\x000000010000000000800003a366167a5fe11d237b13e4447650a0e73b42f20a0e27aedca4acda7705bfea3e2705efcd744d07c09cc113e579ba5f5617f5e9c79e0396ef4254c274602cb933a9adb730efbd54791394c0fec4f0d61a4ce6abd31fad0a8a138443dbb97e402c50dbffeff04715f4acad388e01ed073f4cf37040c3db958d9fd384c5bb3491bd010001	\\x2a57d4db3cf32ef7b0a7405b48064e1b555ac57ff757d6b571bba6e1bf04890d85858c2122ef5497a5c08b78a15146173ee51a9ab5036986debbb6188ec44b07	1670222810000000	1670827610000000	1733899610000000	1828507610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
252	\\x56b2243ef038ba7500be5807057026030ce860c5db408531ac619e4b5b3e418add9548cd289364da6628612228bbe03fc151b639c6f6d76ad3abdd3c6cb36864	1	0	\\x00000001000000000080000399c214af505be53446f63a2b51a974b6225a9ce5d6a1ee4de6102ffc9faff81ba312f1c33ab4df9febe5e82dc15c03be46b29b604bfc559dae8ffb1767432326a7694f3e00ab491dcc7d2f7b224a349c23824f006d92a3ee6f85bb9c44326bc3bcdc0d7037879852eeb18f05b958d65be88763ad731d7c94321a709882a6a4e9010001	\\x6b089c837ea9afc088e9833dbe55b345d8909d2a4b53b1832ee53ac7c6074ed3646f5ab7ed31a579504d9cff6047d67dd963c68aa127eb0c4159ac0ce13c790c	1646647310000000	1647252110000000	1710324110000000	1804932110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
253	\\x573230b2a135b4c12518efe2cc1eddb67ffa1c91c4a53d826c13d2ebd11be59cbda3383fd9148438eb8e42dd14f16c734c6f9c2c3e997049a785f31cbc9557e2	1	0	\\x000000010000000000800003e0553a3f7e54c3f7aafe4257bb48eb9a1756f05672d2fba9de868dea10af085d3033af7fcd0736f69e15c6f067a204d9c0c25f1d2e917c1b93ca4fe6c4d57ac4a25a34db7de9f517312484dcd7628287c8ade5c6735c6b7e61d12f63372fec37d6aa6cdb4e05e658d3729712d36e295b81fb6baf065de7bb0a7cabdf501121ab010001	\\xdbf938232344e20045f385a47a47b69bca552e4533874d5d959125ed8cc84a2cb2a65724fb9f3474cd979c7d36cf3837c98cefc5c04fd12a07e7112099defb0d	1672640810000000	1673245610000000	1736317610000000	1830925610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
254	\\x572e755533b7edebfcb63a7f178579adff164d5bd24368e73419f6015ab19b5d80ffc529d40b2b523a147346b491709067ff5b0d5f6f9c1f2d42c18688208a7a	1	0	\\x000000010000000000800003d9af0ad73df542e5ba88b59e6b874e8147239b0f99da936e451a8d2edc6ef177b13abfb0d8dca6a5d3283af345daedee97dfb2a1acd58b850e41968b0bf2fb744ab103eda71ffa007f2465f3d894c3ffadd203a4f6af17b4b23c0f3300d53c575f9662f9687829503313e145bf2a011d1eb3d4762f933a6200ce08c09fc31205010001	\\xd57dca9986987f99d52c260ba1a9df4ba947c911dcf2ea33c81b1b8d341cd479e47d2e98eb4c5db482fa02147f3db1da2ee32be60037dce3ca5ae7868f7b670d	1660550810000000	1661155610000000	1724227610000000	1818835610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
255	\\x5a02bea950f0c536a12b1e0423dd66ed2350bfbb876f68cc08e478eaa6e7732636ac6c7198a2270cc1d9d42f3b6176e2e01f267a9089d16b397fb85ad4a6899c	1	0	\\x000000010000000000800003d903df5f99599bac694625f6a0b1f78076742022fe91d415be1098d26ce80753b34029ffe2c26fe2ce73045dc174f60f3264314243b4555ad8bf047c8d7ccdd820ed1ece7b01009f87cac5f3b8fac40e2a419728636b2b7e457e9349d3e9e68b73310c3b5f6e100f5e903cc406b7210aafd34ade3fcc532edca19fb5a0ee35d5010001	\\x3f353a4b674e4cf988702886bc10483a3be48252a035a3e5f543d4c41fd72432cff00f2666f45e523c1ec460ffb71985ccc689dc8c116df2569ccf889f0c2c08	1658132810000000	1658737610000000	1721809610000000	1816417610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
256	\\x5e220c5a76f45a7a053ea65636f883fb5f8476e1adfdb760e7764f8b2433660328c9590b8c3ba21e722522a3fc4055bff2e6e901810f99c89061939fbe6299b2	1	0	\\x000000010000000000800003b514f0cc44ae56e290d253ea20c809fd21aab19e96fea21651bde9ce3d174592f43d6ae862cb28fb9a4f061c359249b10dfa4f57cbe524a7b7ba8f09d59404fb8f061e2c37e9837bf01e5bac351dd580ed30e99b8dbfed4a5fd938b7e0f1207c384c43da9e73bac7b5d0e6f518e8048e597af10ac9583125bc548ff928098055010001	\\x123863ef85ba81edf691c7931411fe02dcb6a7598e542241d315bedeb7624005bb17a6da357ef1b5a79230f1306b4f622d4afdf3c2838062787375f35cf44207	1649669810000000	1650274610000000	1713346610000000	1807954610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
257	\\x5ed2beb7f061c938e16416a7fdbd23ed5640ad05ef18f132935c6ec4ffeaaec9556787c8e2c8d56033e71adefaa30cd0d88d50216aca2671a6a2e26e65b3a7a5	1	0	\\x000000010000000000800003c3ab21ff0edae495f545506826c36d532e8505f084d09789be08a5c70ae833fbe9e5c67a13b18413177f59d190477d8d47bfd2991fff8e2fef872fcdd0ca9577c681e37a710e4e9837b43e5d905d4dde788b08e4cf9e39174661e51a55b22500e0668ccdc664556b5d1f48bdec4d5d6d003ea88299d5724189ec9d8e4aac3b65010001	\\xd832b49cb77cd31627ed659ba24252fdece3fbbb95ae579fd34d77a2260e144d0ce017b68596fc43386237c2ce06678f06f6be5e479f217d3e901307997e580d	1659341810000000	1659946610000000	1723018610000000	1817626610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
258	\\x62aeed88b2716f61d2a61f3a874b367a9c4a0c1277e4b6c6fbf018c4961088b8b3e0ede67adf28343a517d05966bb381a0f1a676fddd172a8a5bff9c9fcb0dc4	1	0	\\x000000010000000000800003bd497a8cd3436327f86da45a78eb3ecc2606faa77bc2b0e28a71d2301c82005131c4057a7834724fe3d193ce89712f9a025a54cbb19cdd3a6ed8e60b5431af02c2ac9c06a34c8aa4f5662b4ab6fbd81e9a48087cf109ac30aa815c1572ad1dbdaee02e76f427d157830f07c51f5a871042868620d91acba461fcf94d48e24a3f010001	\\x2078c421ed9e5c69e115add0c27e47adc4df611f8f30954bbe7d87d0267974d10a05c6a8db36bdd768107bd6afff0c631e7fae8b0cf8ba43decfdfa6c9bcd10a	1676267810000000	1676872610000000	1739944610000000	1834552610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
259	\\x650eddffd36817d52c48e782e3797af336852c2c34446ab40a364a455d3e713ffe9120d6165ff9c9d9011af10d12b007cc1b1c4c5b3071b270414ffbe1e0c8bd	1	0	\\x0000000100000000008000039ccc552a9c7c5bfdc8d3765ce737dd55b9be9d59890b1c2286a3221a75e581aa28a73afcf23a1929e3289c22203cbc7c593652e5826d1be975bf6e9b060a6841d39163ba8493ae38df254f9e114414f1d8c2767bf26f9fe7b6116b0695a6ec6d77d356c75002fd4b925889c0cc31849983b581ce3f61ca3546a8fd6afd70c1d9010001	\\xa336414d8d9771fd6eda10d4c99eeff50ae6c916fccabd97275c2ea46792e525ae4795267fbc6a7e338bc1d89952584dfb6be8580ac920b510ecc8f4e78c450d	1675058810000000	1675663610000000	1738735610000000	1833343610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
260	\\x6b46ecd55123c2a8418f86159b2a0ed8df606beb5af96df12f04b3bae0820e80c66a3017efc781b8d2a91dba5281910d0a91cbb144ad5a2f3b2601f6f0d16e61	1	0	\\x000000010000000000800003b2aa983303f80257c60638e66e15f47b40d120acee4d556cabcd57d8aebba594284d834b6476ac3115f8292d8997d765ba59e2fe7e6472ca71f118d3962ad6d0088eaefd9a872eef53371e32115615be55dbf57f44efab639448ca0f9fe37dee630ec71c49c55f6a53b5ad9661398834d29641f5723d0c05f803321e05912445010001	\\x5812a2e09b2ffc2926a76e37b37752dbf03986014bfd41f3649fbac506c62a4658b5ae9cb01ac870afd28915adb292e596b8d7fc342407dbab7a939c1d170009	1649065310000000	1649670110000000	1712742110000000	1807350110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
261	\\x6d66bd91411a647f0d565390ba1fb0a9d4ee04d8e3fdd90265b9a92a8fd12ffd1454a3320c3ce8501e591bfa141bc91de48357067ec1e5a7b18e5855f2441d30	1	0	\\x000000010000000000800003d3220429d96e33cf9e9addb8236782f68442fdec7577191bf37401c5be5de49435c96f7390c1623462e04ca1bd5fef143ed58fd8133297faedfb5babeb99964805a8f45fdce51f54a90608517e2dfde34bfe463f2750265afb5e50f1529ea3a032355bb5bee38ca770669998336f26696b94d11c09eb00b372dee75ebc20edc9010001	\\x45fc07bcf457535cd725d60928973f3cac209e5f7a58c1ed162caf9b661eb12d6c76404638f25368c11abf1e50396be66a2de3e61f2283ba91c54c2c8d46e106	1658737310000000	1659342110000000	1722414110000000	1817022110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
262	\\x6f8a15b8fc1efbd5206a80ce045b07881b242e0844d993a94ecbf9fa09c5e1834dd71880ef2b33ccf76d26ddc255fbb3ccddf8a0927d6dd086cf4f69da23a76e	1	0	\\x000000010000000000800003cb0d9e58cdee51ea67d7cc14470a387fabb9de08bbe4a4aba5b353579f21ffd768f53f9814db537f85854a8629384fa26172a1c37119bb760c302b3c20cbe145897a1fbabd1e0d48230dc52fc08b5941509062805d4db9c7b2b9717de3c93c64fa1a3955ee0abd38539de694429a57fb37bee8a703e491bdc633b97378db3efb010001	\\x52ff71775ef881b5215689a01fb7495ff1b2c90cc16ed774146fe9ffd3b0024f0beb89da222f6c949457664c07a7154e7cf40eca52b0fa0d5686cb59dd36ae04	1650878810000000	1651483610000000	1714555610000000	1809163610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
263	\\x70b2402f39024ef3469911b658905fcc5a7a468d9cebc7149a6d4e3c818eb783263fa1b63152ef140a294aff405431c28eb3875285e83b224fbe9c710eb9a843	1	0	\\x000000010000000000800003d0d309aacac2b41ed4562270e80fc47431d7191a982b80de6c5ced4356d2cfba3794a41b518ce06d97e116f8450f5613299816c902a3143289dc0053b59712a3ab8d66222600828605ab0d501bbfb39349235b94b3950f289da50149518701bb16c743fa1f07b280a9590a4a20d7be6bd78d59f6d9ff4812bae7f691e988f4dd010001	\\xac2dbde0d7fc01cc5f17948671cb3709cd6c9171236ecaebc4b79a7d772caacc957e0dc07eda6056b80a9fbe4ee7fd081c2a1d7f8237eb676e65e2556f13800f	1657528310000000	1658133110000000	1721205110000000	1815813110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
264	\\x710ae4dd8d06ca6490477c7fa76672cf0cac575fd7168f82e3477a6ac6b8f55c4fcb4986dd29b2798a785ed253fe7aa042cc89234e8cf880d4be956605987aa3	1	0	\\x000000010000000000800003e1174b514631d22b05c23d00049162e10ebf63dd742b7a28ee3456cf4420f1f801c4b91774ca1b57be27a03eff17e643e59acd6fed914e06634037240bba633e09aea61299a0959ad4cae6107f45ef7a5ef778d711c87412c6db03a01972feb8e1a9a5cfe59d1da84c061929a83dc0d8fe15b194b9ea0f59ba886a61d5fbad85010001	\\x48d7dda23b5240498aff3f079f58b99f02dd27c1f50c58a19426d942c919f213ef68794157ff47be5b1ae9f9f9e4fdb91e7e68e341352986a0a3cf9fdd0bf90b	1663573310000000	1664178110000000	1727250110000000	1821858110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
265	\\x723207dd573ef395103df62c46f06b43993a74c9380f909225edb4740bf375e8d73c1549282f35bbd70f89c1d6927999b9a16451ad44512a7d5b586533d19f8a	1	0	\\x000000010000000000800003dd33b12d196aadc646d5ddf59171d2e5472241da0df92d7db82ceb30944a3d02f0d88f2d4dacacc91a0da47130b28a74a02c6a41e2a9f106410b9177f35e1301655b2953903b1f508fecdf549b5cf88e63dd9f3b6e87d0a660998f1dfd4dcf70d084e6a8c51e7c6e1833fbf8e1786f64e72ce575edec19535acdcc3c80eca149010001	\\x9291036c7d4976a7a41bccd8ebdd1de42106f48cc997e5c021b48e82fd81530a2dab5774bc90a3b323182a14e4f2e603f926e69b8be3dc55b015906cda1dba0d	1647856310000000	1648461110000000	1711533110000000	1806141110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
266	\\x73662afe788aa7cfb04f3935468e32dd139071f607f492c8b9e0a493f4276efd4524b32f3dd667cf81aad6df29769cba9c24625b247e3886938ee19e668ea6f2	1	0	\\x000000010000000000800003cbb90e8da969768332638c13d4e2e38cd20a54583962e5ad3b6c0c98a90ad4be41b8abd02e838aab5374113ff18b3df988d11af1cb124cc8573a36f10f2a0b9ff7ae263324a07d36f388c8ba6cbf31f35dfa8d271f6e13d05efc1ad111095373b879a09cf71c1d09baaadd826352d8997d4a4f3d6ecdb72e67bdaf849f9facbb010001	\\x0317683ea58e4e0ad3adcdd1282a2fa261eec5450ca1f199ee961bc2bd0ab741deb1e9a89b5ee5f97a4a03de2df25b112ad5d0d73023a9f055a73c4105d6740d	1674454310000000	1675059110000000	1738131110000000	1832739110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
267	\\x7586293ad31560341bae95afdd7cd3421f91393ab1cfec82e5d64f69c58123dc51508e38ac757523362dae7aba20d49285bb1ab7bc82c14e5041c9d06dfa08c5	1	0	\\x000000010000000000800003bb477779def0c3e14beb1f4657894e8ea3478b407be50bd71f032021fad3034c8945130660db2af55d70fc0372712adeddeba70361d865d84f3f7f5bc34a9864ba0381388e689fa38c5e5db210d782130c1419a15bb10fd97b42c083dcc677056bda36fac79d6edde60483991c65c2b78cae7b66fd26a7813eff5909e504d76d010001	\\xe333f126153e816bfcf1dee0b725224d623b6efbe7d9a989bc3d38522784fcf933f79ad3a51254ba2b6d7e6f596a7d6f18846a1da89895e3ed80078e5968a30b	1649669810000000	1650274610000000	1713346610000000	1807954610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
268	\\x7702a0d34a258b8be12449de214e0aa212f03b9c9dd26153f8ca292d3598cb859b7a7ce7b08df5a50134ded276168f7684b2ef46606e21d54dc3f3bd04f828d7	1	0	\\x000000010000000000800003c2e62ab49399447d4c3533b30fed9f597c86b260987c4ef1d89597d34c894c7cec165f3cb87b2fb96a4a18744e118dc925138ee6e8f69a2ccfd8f56273548c5fd525cb607c5e48081d5ce8343d3520cbe97502c9a5163ea19f23a06c74c9945ea8185049b4df2b085c6903a7917bde9786d384da104e501c8e055f99d84ed51b010001	\\x7a80092e016d3a7048d6c0157e080700f8ea98f0e1429dc09c2bed50cdf79cd41eb2272b55c18df68d66fed06e4638a011ab05e8601ecd2bbf0d4b226167ad0e	1646042810000000	1646647610000000	1709719610000000	1804327610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
269	\\x78d2bbf6954ea237a6979864b9c7679af7ae60c706e2f6c0b96d7a0cf7401769b8cf9927bc31c2e017b328db3d0075878848a3d66038d29c1749a0115e7114a1	1	0	\\x000000010000000000800003f9ae8a572beafa74834e928f1a4706ca2a0d8014aaebf27d0d7462f668e409d32709ee4e096ff11852eb48f3dc9c7e0c0dbb0d1f5b0bcacfcb967af89515b870755eca3a9dbec0a74afd2410507ea62b06b63722e7e9bb7dc36d79380f61028303dfa3f0f939d0b0241ad45ccb9e778d3cc47a86f902261b4a672c597c22b8ff010001	\\xf3722878860ec8eb4da3d47d3d9e5481cc7546ad1345e061062b572c9855359309d48adf6eae74e72e5c3209a36780c4b9326aa595587ea2438e3bd5405f6f02	1669013810000000	1669618610000000	1732690610000000	1827298610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
270	\\x7a52b2b9c94cd95fb9ec5c379a833425ee06ee1b70dc05301293e008248f54631d6f85a8fc1f35bc591f89e2322601725c1154408c2e719d6c0791928e451383	1	0	\\x000000010000000000800003ac79100fb9b56e53a125b740372e6b10e7171186d8abc3f06fe10f30112f0b4ab4becd84b7acf24486f7b1934790841e1c7e2f2a2e74472307505cdf3624b96a72eaaab57aeb5913d681015b524cb48802e98fcfb0b806084ebd6189c459761f0fcb1d1f1dbb247302e439c8ed9095c25ea8d02ada6bc97ebb83e7c538e61921010001	\\x5f3352c99321ffd3ee3e1565ae1a02254bf44ec93fba12463f0df8a774f5d395e9116aafaa5e3eb8fa037fc09051e16f87b141b08b04a738e89d22ee07eff607	1662364310000000	1662969110000000	1726041110000000	1820649110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
271	\\x7ce25a9f295eca932f41610cda76c767056d059d3b521fa2b2daf0393bf590274bd1ebdea38aa39a10ec1a434dcce98c17b194c65adf4bc2f0ab3b82e522e51f	1	0	\\x000000010000000000800003ad59281a15f03d025f8ebe725170782e2947326a0f166458f12e5ab610887321417d5938c2f48d2aef4e1a7b824d4d224d0f51ef4bb18b8642eb39af8e662ff3997eb24d465bd2b92042d8b8e78b8bceab315635f000edb692de6697361e7b1c431d93360a5f12babbd942177718546753e8bfb95f0ee5950cc324a88afe65c9010001	\\x0eba6f6f08c083f73a30b581bd6a622cc84c3e87b4ec1aaa10602320e2b8b0db9c47cbc855172ddd7b5a6d30bb7eee34a464edc50cb27a874b2fd89892c22f0f	1672036310000000	1672641110000000	1735713110000000	1830321110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
272	\\x80e2999f3e58216abc203165834ae80aaa188a6c52a1d4cf904114e8e1252c4f851a1dbc075133100691f508e38869c5cf4ba03c27c6524955c7c13526876e0b	1	0	\\x000000010000000000800003beff04ecf4959c2b7427663dcec7e75620fa0a2d40169a325d871fe5563bf65db9ffd970b7674b153195b4e9bf6caad9624869bb4764fd3e44f207f6c07814470c93f047f7ffb44029302aac504da401f208b86c02da43862bf17e803eb0292ae649120fc23d379c7cc18dee609dd2791fdac4befc7573a3986e8c4e6994b96f010001	\\x9a39937dbea232a1988606e01ef8086bbfbf13458ad5ec1c40ed38abd94bb717c0f180ad208136f1aaa08c3f4c43d5ea26628dda25310da69c8632e4a8839d08	1657528310000000	1658133110000000	1721205110000000	1815813110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
273	\\x8b7e52b9062478cd3c5383aefc7641e547419855295ec62c0b2b2835b35eac2750fd528a602bb6e02bee0b522af9970be9d1970c3d3f01f5794517e1aa921177	1	0	\\x000000010000000000800003cb7aa4709b3650ee2fe5b19b283604fbf2c74e93aa3d5c5fc841c16347246bcad0b9974c5d17d0aec3c4061ad6216840da716b1e0cd2a4a34a47f38beb626850422a4db04a7ce5ed6b0a76f087ff51f91d474f703b6694180e5268016be031bf850d8d7285e9dc9a49e586a86a084ab04930e9f2b82ab97e1036f3db85e4cecd010001	\\x8f7d2387197ea63c57bf6a34d45e3ff0fd0b616abb7100ce9cb0ab5653e0e0d2c471b88dac489e708b74bc9dff517ddae8aaa0c86e7c5339f4035419715a5900	1664782310000000	1665387110000000	1728459110000000	1823067110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
274	\\x8f36042761581e70219a30b2381e6d4453ab55676192aa0801a4ba47fc484c62eb04dcfa479e83f0943a5f315aa999d21b58625e4088e3a3c864896adc7e5b92	1	0	\\x000000010000000000800003bd1e8ce2a0d6eb070eaa3b86c5cc5087fde2212d3f3be896bbf912dfa7b26be996e2c29ace99164e9285e9515cf1f53ce2b8ded7a36e3aba945edaf056a9bbfee6314c76cd3f746c0101b7c27307d68c1688c69c47b29f8d1c02faf6e90bacb93e5fc7cf733a96092814a89787667ad88dfd72d74c204625712038f5e9ef395d010001	\\x0307ed040c6d08cba8023edd850b0b39da60c6aba110bc70801347771455c627417fdab7df89922bdf8397cb813a45978f1f4fdd0759c024f6a947224869b804	1664782310000000	1665387110000000	1728459110000000	1823067110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
275	\\x9542e5a7b787d0b8c5bd27b3a23ad7615b6ba568694db3d960781df26da2d0229b52874c18ab10a6469eb2d259ea7e17c59edb20a03968d65aaad8de7fb233e3	1	0	\\x000000010000000000800003bec9807733df6cfc11f044a4735f2e5ef1b4294782368caf8ec9af9426bdb3602c4c2e632c8f4506dabdcc43ab0bdefe20b4a3e21361599feade53bc9bc7f22895393267b20cfa82e58f44458fd29e413f4152a7235f0b1fc609108f4d2524fdaae80e681caeeb5cc0edc25db1f53dbd54b26da71f694417cd2fec72e8019c7f010001	\\xf719022a381059d4a6dee39f48bfedc4c59fc4a034cb7f10fa8d2b87984a4233d0a300bd2a584c5e29091ca7f42b39a8a62163a7645c4f7054ef38ad6bb3150b	1670827310000000	1671432110000000	1734504110000000	1829112110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
276	\\x9b7a94c3ef37c512722cb362cad89534cbab4a6677481abd5f364d5f68df939977fac7017ae86f3bab3cf5c5a284e6602a3c1749819821f9d2b5d17c916331b8	1	0	\\x000000010000000000800003d017b841f128ad17b358f0a2555690f3b0ae03fc5f61d81aac258d1ef9058df23dc1a30182670fc24922dd98465a4e73e9be715161ea503b3fc7ba476cd62fb6bb479a7877d645faca0a6912177379852a172f7381cf2053887dfc611df389abcb265eaa34d88fc8040acba61b63b079b2ad3de17ddc667b661d6399fd26c5cb010001	\\x943b0c2d7e478259333fff2e60670119665a0dd408cb7e9854a9ce7d339806dc3bc3b9c4c0659dfc69da38704731f6ec86e962b1376d8020e4319b74bb2bec0e	1651483310000000	1652088110000000	1715160110000000	1809768110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
277	\\x9e8607290ffa9a3a65d5a1d29fa12f23b1d4bf6a9c937568bb7b1153e032dadb133eab853828ac46f5413c69a745c782ce04c8900c1321aec777806daca538cf	1	0	\\x000000010000000000800003c16e8d3f1e07d89ab61ff03dbe6a5a53e518709d89324629405f80ca0cb494e45fbc9c799cad9a1bc2d8f11932a961bffa5532dd87bb9411887d8e5158b8e5036ef78b8b807b17d5f8904447f1e65eb1a04339e4ad98ec5edc5db7c2d31f09f8268da4ba3e226d592c7ed901f05c32a2511117e6fa280121c8f666bc1f447e21010001	\\x1098c9d51617751ac046d0973edf7ae57cc1d5c819acfc6ec1e0782cd9e08e8ee07dcd3a329aa66c550d09595460233ab614cbf8d27bc6d21d51e9583a514807	1675663310000000	1676268110000000	1739340110000000	1833948110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
278	\\xa0067aa4b27da8bf78e33ae42339cdea440174cd40516f885cec2a4583784100b2e1a0ddb36cea2822033473734a531c6871b6c19fdf5dafe70c3ec7754d7819	1	0	\\x000000010000000000800003a84a685ccf01dd304b3baab31abfce668befd827b6a3aef84edca8e1013c7d28e2340ed88f802740a29087c710919a43174a63318ac30863b9182056030bc3e9b21a2d6b7c70218170c0a7b799507a78d62cdf3a9b8d0948bcd0ccea2c82db7805fe90c033b8e1884f1a8b58948fa7b698039de7c018ec8eac3e71cbe33cf27b010001	\\x9a18d41c9163015aeda56d277a5f7fbd125ff14cb107d6f922ba4fb7fcfd3632e4aa38f2bff0b71b57c3c2ca05d36f83ade0a19d6bcd3db785a748f9fd57f30c	1650878810000000	1651483610000000	1714555610000000	1809163610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
279	\\xa0ca50933ae2edf55e90f5943726d2b654acc60aeddea5304991d036287720dab30443778cecf8466f9d65be1ab2902787776873b6addaecda2773d733b8b675	1	0	\\x000000010000000000800003cdb27dea168b0b0f8fcb8b3da67fdea269f9aebe22114ab24b88f29c97915023d41f9a759d5c82b11e2aa83361a6ff928d4c3a8b0a0f91523fd6139b2e173cf649936a19f708a433b5c101464c4a86c2233959eaf3a0433b7240adab2fececd66e469a0da769d788951603445d852ebc405c0bdd8b103cdba983ea03c9fcb7fb010001	\\x76bd5ac392b27b0450ef8f6c249e29014a55383af656f79a8a7bf163a78941dc17dd0a2ad1968f6a4324d128388b32202c8548e9fc370eda5b0f1849a022f10a	1669013810000000	1669618610000000	1732690610000000	1827298610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
280	\\xa46a97839e316b3064eec6c375c5c8599e5a1491fa44c6ad30a750e44a172b83109607e0ee0e298ce29c13ad54e77f168a5836a7c9677e6c0e10dcf85e3ed74d	1	0	\\x000000010000000000800003dceb3f9f147afb0fcdaaacef2650619a71ec749075b370fd8574f91da232e771259117a51d12fbe0ecf285af5e05f58df92033761b0196a8fb4a211bd721bf30af9afdd2a9136d8fd0a2b927eeaec8d08bdd0a29fa27afd4c43157df8fced0822fa091f393e68402744e5468207b098388d71ceed3912798c8193f3c2445dc71010001	\\x74c481ab58ad77f9dffd736c1eb56765f64af8141c912671cf66abde5fb0e580d1511fe486409c9794f87fcd8361a71aed7e7b7a5093795621c328e4909e9a08	1650274310000000	1650879110000000	1713951110000000	1808559110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
281	\\xa522168c655e35260a9c3447ad21a2d40260b3c3b31e88b7ecc2cfd8948ef2c5b6f33b00cd280e322a4318aa0ff94c4788588f487ec7982e3ab8f2885af37b62	1	0	\\x000000010000000000800003b1c9f8e613dede028b57324ddc91e40bfb35fc03a6da25fee43b888aa5ebf0120cef6cd997a0abfd9ce80a5add3d0ac94f709b80cf6360525f71afa6f20991907a8867387c599f600decf4222acd114f67196be6c64855438c11bcdf8e9d3ed83f6af89d2222ab8fb90c64f4bfe4f2fef681d9304cdff47a5b983af84bb6ac0f010001	\\x7a29eb5dd330b83a801f5f8e7e64e03b3e99a7971bafc7128abac27c83541cbbd4f54680e217ed6d3426035a524ae25ba4bdfe93e7aff1a4d877c616601f0406	1667804810000000	1668409610000000	1731481610000000	1826089610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
282	\\xa6fe6d0cb1690cac58727a16c8fd2709042b9bd6ff8723e8449de9a38b7522447f597842f65a1b66edd2a1f2a511d417e1ae61b16e5168eef7f7bd0c7ff69b61	1	0	\\x000000010000000000800003b315b225925734282adc0056ab82ecf324d2002f5960b877cb3f6a40a2dfcbbb4fcdda18228cb7bf9055992a162772b7f98c7c5b237db94f917742a3f6932d6ad8d2982e05b9a74ca92952250d85dc746ee61af832d297bb6febc145e73dffc90c20f4fdbb0d73010d529152d695f70b14e0d2a9579982b4893575510341def9010001	\\xa3708d398074845a5dd9eb27b3ec24399d0dbfdcf3617a3b19178313d035910e40812484c1fee11df1e218b4bc8f654c32362c6490d02c13a231dd29029a7703	1665386810000000	1665991610000000	1729063610000000	1823671610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
283	\\xae5e6ddd6987d89e7d88729a4c2f23246b0af790a8ec8a8a039ff16aace4705cbaba52f30732ffca661aa63a3d6d189a5ba440725f28faffb66561ba98c589b2	1	0	\\x000000010000000000800003a8ff9163a9e6e260170fe6fb75530667f687ae890cba224d37a1d44c45feadf53bb907b5f3bb3f37862c6f9ce2c3259b85dcf44d1a86c73f957e4877178b7a4bfc86bd0855db4eccd85c14b3e814db4288c5eb9f2e0dd223825f6981a6556cc37c47509c42628d57c4de30f8258f44587a433feb863a9e1e11b99fb2c59b2529010001	\\xd31de3c4ca8a722c884924b8287dae862d88dcacb7a010827d89961e99d950beb5005420cdf2d22dc5536b189e8343a30b73ecd366cea58131af14c71f9aef0b	1671431810000000	1672036610000000	1735108610000000	1829716610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
284	\\xaeda066f68dbe9cec43840455378ed3c5a001d78ef28ec48f42b5b0de347a8ac222151c42e0dc1081bbca63ea86444ce946874e21dc19edfa9776b955240b4f7	1	0	\\x000000010000000000800003bf00083312e9b5c77e85ae0f9a34f6060ed8e71571371a2aaf79c9a36d9b3a3b6de4b58820ade4b4b2e86ceec7df467cfdf6d151a23c65313a8ab789d31313717fc7f8fa5047bda954d3b75a72db08822e939b451f683eed64a35950729c3fdf21e135706470cf07c28088a825b55e13ec899346da247181c71882475bcd1f85010001	\\xcc5bfe271a2e190638837a987b1bf04b81c5b4abfdfc18178ab1fb7219533ac28f2de30916c1e5f0a0d66ec5524055e2c0d811044ea8f07343f753a7c5d78403	1646647310000000	1647252110000000	1710324110000000	1804932110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
285	\\xb15a0f88549dc0a8eb7fe6eda455256a72cce84ee35b2f6f1dd69b7894aaeaf4b6212da2a9d7e368b1b52d462f2d18830df772fcdbb01284ed81e084c18c8eb9	1	0	\\x000000010000000000800003a9611a3f30cdffa80520c19650d8daaac668741e51c2ae7982007e3c8af8a3f7255729084280b6855501aa3940f070b29933af06c1e99c78b2f017a8adf76356f5ebb33d8d2cdc8ec0f466f6c197a72b551812d722e1ffe0f18d96c311b5ca57ad73f2c7e9f779ef11a74d592a259094a50c1cae17b3a25cfa7084557fe85c05010001	\\x21593e08a62d28dfaa7ddc7cefed42ea966f3c67f0fc7a1a2b59e21cffa9c2d7067d4e9cfff5cbd954c11d94fa9730821c0125b36ffb97dd57464e07846fa30d	1651483310000000	1652088110000000	1715160110000000	1809768110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
286	\\xb31e067d08a0ddf8e2d4978eecbe16cadc159d6a51c84b32e497aed1ff329f2ff33efdef82a857cfea7e5cfaad4dece0edcb0d673ab2032e2105d1230b935821	1	0	\\x000000010000000000800003f53d35c7e734e6c859c51ee38f300cb08b9e4d71042825efd975c4a9b512caf5122b292990515c66ad0b3c2f25e0241d389be1ef428c648761517b5cab5f6d5205c650490a33d392a1e6708492818da7762b8e13e94a7041fe62f2b1e1afe5868d60b4c341152fc9b898826e1ccec3d94a1358fb56f758a31643ac4182069221010001	\\x93858ef80dada668e7dd2a8925f81082e94a6363e8162970554700df06db10cfed2b149c0ab363e3f5c03933f0d72c5ee3befad6424d926e54fca791140ed50e	1646042810000000	1646647610000000	1709719610000000	1804327610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
287	\\xb7c6cda3a19eda3a6e5582856ea5959186b1899e653f63afa5ac3b9a156fede905d87dedb7ec487a6b47f6399b242e6181595b5430ce966cfecd1c9d2efeae37	1	0	\\x000000010000000000800003b6919e96f29ff255754f3fac615ededa1ef8ed486d011d79b039195eb3a9a8688f2476538a56de87517c7a9015a11e2fa054377ca182e4102f175b3777cd3959e5a7c7d05bf00543d7a6e080417913bc7a39fbdbdabef141a83417ef31a5a439224fef68346b16e615e3d4a628077c12e35ae7d8627f9ee632e35da6fe86ce31010001	\\xe258b1b643fa2fd39df254963ec512881c7a2733366b9fcc679cbe8264aeb83424a19ccae6b024a29709bc17b13314d69eee04aa40ab358ee4ac796f5ca01f01	1672640810000000	1673245610000000	1736317610000000	1830925610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
288	\\xb7eaf433fbfe996252202710cf2a43c3621bc23f80079fdc863158732a6699849890165d6574733585fbbeb5c6f3e9fb60456394002af0d78b10e2b72e2fa6a3	1	0	\\x000000010000000000800003976e8d742db57542db7641534de4b918e384ccad1cc09041b4cfa01e8c113039e89d695386cd3c0d94c10eb85844ca744a3a8a0e8809f612f1b9a3f26f4cd5150f08db70634167255aee151f75a02406a8c57290121c5a6b0b832f5d94e207b4f47ebabd6da2ebcbd0ddce16ed4dffe674b5dff64463040e346b79544f2bb91b010001	\\x9034fb7811ef74a7c130dcf1eb08f8e1193362a5a7acaf3997d84eccd1e5b3ac3a9b72112253f2a5d7ed4bc089def6c60ff704aaa0551a44025c4417628b5e01	1652087810000000	1652692610000000	1715764610000000	1810372610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
289	\\xb8aae1fbc729e963abae963268678c884a6d769ce3621b84937f71c84e45b33fc228b26d811cc8e28ec274e3e4f99b8aed6e613e6a7e87804585a2695ece168e	1	0	\\x000000010000000000800003a172a3cc361fe3b0e39991e621a95939f90cc985918d9dbf687aaccd94e2eebe4c8a7bc035a3de67e27810ec303409d8f520704fc26305ee97b690c75ab70885e5e761700a12d8b7595d1117f91ba8428edbc9367eb44427e0839ba1d34e2524f09a2b9c931ff136b66e9a0e1b39513bec4441708368ced969a4774f7eb67f0b010001	\\xf7551d418fc109a5c7d96d78480858411ab8bd2291cd84d86f355dfeccc0a802f379a5437dcf7bc5e9185bea59f702148ebef368ebdb0ee488cc354348efe20b	1664177810000000	1664782610000000	1727854610000000	1822462610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
290	\\xbaee36a74a1759d574f4e36fc2c7158d433e9702b4aa9f84466e4eaf765f35544b6b696f2f0b8d274fdb1324917a9791ee8fd0be923d39c6fc1fb0ae268a96a5	1	0	\\x000000010000000000800003c6e926f8b54ad6f95a9365d8490f06b1c25e1924709619f6cfb54d32f75b364cfbd40d102c496461bc6eaf543c547f2568916494f089aec19d680b4dca13e654babb07c9a31ab223658530ef8b4c2c22dfbbbe6fd42bfd02aac2a6beb23990c80e91643298eba230ccc749b6fd4a40bc0f854b1b85cd3e1dfb5aaef1c17796b5010001	\\x03c18a94bfb41748a13b1f11c1fa3e811652ebaa744249806e9ee234f49e15b5cea6f30c42f4b52e0b782b6299b5c07c058b9a60b91c6e5bf57805d1f5fd9d05	1660550810000000	1661155610000000	1724227610000000	1818835610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
291	\\xbb32647ca1e8005c49035e61c5e084f249a145298751785502d121f7a18719df5ccdbf78512f67666b9e1e955af641034fab7eca0247ecdd91a11b8ecae53754	1	0	\\x000000010000000000800003c8cdbd7de651b245958e0dfc3a8506509e8cf34667ffaabb9a90fd4e79aeef7469516e59c534d218452737000c18840dbe3757dbd8f1dbb859d8c39d97ba16977345eb28bc288f6bf7fc912589283f91059b282a6283cce00b723acbc0300fede45d4609813f1bfad933acdebae6eced8df83462e0b643098db53c9db42e90cb010001	\\xd34eeb39f95cad18d6f9d9b765b0b96bbb2bf994dcab14eb17c669f0c33276837019410611b17932696a32839618521791444bce9ae61c41083cd25a3622620b	1665991310000000	1666596110000000	1729668110000000	1824276110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
292	\\xbc3e15775fa63a237cdda3cf10ac5d0910d3e328e12d1eac6296e56230ceea5f32f102536843e38a62e6433170de7bc6f33816c8fd7d586804917f57a42283df	1	0	\\x000000010000000000800003d8a6ec76898a7c691c8e53f7553b57244b48ad923827910ec3290ed1a8568883b5e6ecaf9fce2ec1fadacd210f59dec33cde02acf3c59b5b84e085932f63587677254840efd3f52cfd48be529b73770de5fbf81be1baf7396fc3081f0adb631443a95b7f9bef422c61ffdb6dbdeabbe9595a9f034f65f64a43b44db9ab6b254b010001	\\x281652edf0540dc92a7350b4cc577c7de0a8d363b8e2d522c8cbe209009d147c1ca55e005f0ffb814c14b8c5a69770452ff8a955814ab6237828609b13648903	1664177810000000	1664782610000000	1727854610000000	1822462610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
293	\\xc0eaa201d96b0d4ba5e099ea95ddc830ebcf3e3dd12c613cc2fa78ef3095675de95e0e280ddf2cce628f4a9bf472a6f988ab28c00b97234fe794fc64319202e0	1	0	\\x000000010000000000800003bdc9fd47515b4f94c93c8e83c434746a8a5457dc429f2d2a8cbc7f01bc4d33f170d21c4114337dfe232258551e442742fb19ca3ebf2acae2752b314439539fb0d3d7ccc0ed32ff530aa352c39533b05149abd62d83d0de4614a56d6a6d708e298d155ca28b9788dd8294e2c6048c50306578ee00aac438b93c4c1948e90ce165010001	\\x767b77aff094c48dd94187664ed84411be46c3517ccf96269fc72494901fec38a6496a4e416db05023e52497b9848716f5116a5654109bdd5e37a8c536732903	1675058810000000	1675663610000000	1738735610000000	1833343610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
294	\\xc03ee600ce87cb040e5ceaf9716b75139791ef41c3cd7710c886940e978289dbf8efa296ef16b5fb779f4d7e0ee37c17538eae390dcc89607da903c0a466af94	1	0	\\x000000010000000000800003b237bfe62abe34176d5b1e9a14fef2f0eefadc20de42febf72f512dc09d68041fc5748b6667e22dc9be0f43ce10af94dc7bfa89547ce09ae350cecef38105dc826620e949089ce51ed56e566f8e6f19ef77c96575eb26bf779b6e581f80c78d4611d7490287dfb0c31c48fa0505f2f489d5f12cf28f9d7c3771d42f1cedcab61010001	\\xa00cd9fa22430bb6b7cc12b4ec73bb7b29cc2558e51edcee4ba451d80a81bf97c6d79ef5796e1a6692f977062efa2eaf5fdfdd75ed4d48b0ae5dc8b5a9704503	1652692310000000	1653297110000000	1716369110000000	1810977110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
295	\\xc2b6ceb18052427daef74094c7cac28511f3d21d800fe510b7fda38c9afbfa094191f3e65de31bddb948e18d348a11a7fc66ce2d0ac563b135377d4542114cac	1	0	\\x000000010000000000800003be0929ab9a2f926aa113d47c1988871f391d0882770b4e589ba15a4104faac8e15277e18c5780e953de1e71a872bc04bbadfb7ec30794b8477c8cb873dc5d52fb2f24c2047ea5ad777f116ce147b1dd355a7aa834801336cb400ca301e9800222e37163fe2653c55e6e345d58310a375807f8cecfde3e0862315d92c5f2446a3010001	\\x34c9d0424732e353caa698c11914e53e9952d12dfc6eda77a4dc92ea70b98d1399f2c6d753749838c99d06b0ac59c76d46c10863d42cd4ebd91796df89707709	1670827310000000	1671432110000000	1734504110000000	1829112110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
296	\\xc57ea8a5803fb9d525b906afe5393ec7fadad204aebc983295f829d75717ad3fd72640e09501ed48a54cc2bd7b58f90654b65c70f968e39536a221acf5108874	1	0	\\x000000010000000000800003eddc277833d26a739a806daa16afbb20b67f3aa51539e415eef5c6dd3f60e63c793a936b4dca8b4527c0764e84faebfa7ed5e349abfdc5b8ea605c96ca9d0e83c5279ba5e7a608cb03e29b5dcd1d634122b6619661082a42a078aa93db0cad52178b1de9e821b00cd0e4e9514f05ada5e23bee6762d00e30da697b31a760fca3010001	\\x4810a373d4d9163112fcb9a1adeff1946d6040d35bbcdc6555f4db049f7fc7ea0f43e63ea9168331a1d33ada0fc4668e90a218a20676d1e5b0f6823a4c595806	1656923810000000	1657528610000000	1720600610000000	1815208610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
297	\\xc8328165f3a07621467bc7752010c710520f3acdecb69009d77a5b1cbca32e0d6d27e112044b2bc54660ddfe2224cf421d688480821a92b5979663acc48f870c	1	0	\\x000000010000000000800003cf1cff7f134cc102d052bc67834156e080dce28e4f5a3a6320628137731351d3177af262a3aeb555abaaf858e9d2d9bf72d3e2da95ce19fa4f5f6afde66eead253e2407c5fa08a743eb0d0d29eea27266bf2a6b0ad097e0aa3292bd5a5fe6198f49bbe6b3a954b9646dfcd5a6c804d3a70877f0486bb736d7ecdfb819f401b19010001	\\xc81d3556b4ac955212e73b8a46f2e37cb4e71c90ee3e443a03ef451a8900225495f391aae1fc0f5c5e100570d67104753d144a1e2a30138e1ca0dd5611b8eb08	1670222810000000	1670827610000000	1733899610000000	1828507610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
298	\\xc82a0bf77e42a9e6464a8c8846d65f139dd5f0e9b5bad4fbf8acb44b22aacce6075b6700585bfde85ae78ddccd2e9fe8d0370d394f7718dc880bd00db458bb70	1	0	\\x000000010000000000800003e067be223694d79c5ceaca6ffb7ed551010d71f49386ae192f03aea1df741297209dc19fd11ed7256e0dbe9d1e463b0dc36a4f512f51f2482ddbf5d1c889123a9378ce27b92446cbb625d33694b5775d97c61b912b79615a66e4925c5cf2c2f6a9e581a4586e1a1158ca691499f1002942c1ddbd1f864b33a66e8fe404125807010001	\\xdcc0b98a414b4433248e519e96aa297c3f570dfe5e8ef4fd1ff119d7c37e6d600fa7254985642c1f7f397966f4965945665e22f2708a5ff947cb682235028306	1657528310000000	1658133110000000	1721205110000000	1815813110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
299	\\xcb5a2cc0e05e6599b9a9a2d3718a13ddd5f9beb114a4ea29ccb874c5795e36e8dcd5dfdf9a693bb8ee57049711219e09de381c9140f806fe8e21ba1d5c38f2b7	1	0	\\x000000010000000000800003ebfc624362683ec9d13eb3225973e853e512e9b5c404a9fb31886b5e4db81b9cd4539002fe7cf154d1add671cab16f062459d656c9d95753daf91ef64bced5c591297448c76f2b19a5f467589cedcf847de65986c1995bfe1169d34800de2de04533d5204d1a4d1b8dc58c62601d6e9cf6853ce32bc9351024a41f445ec6fd67010001	\\x53d83e5a27078a6ceba1d3ff48a55b346b7ddd58c5b4e54e32f5f59dcde1683d9463efb34dc30897319467356b5807fa2517f022318551770e02f70bf8967b07	1646647310000000	1647252110000000	1710324110000000	1804932110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
300	\\xcfb2ac00c6daea905df195f1f57fc4d86ef670eb618a540bb5f40df9468d6826ff74ac715974e7067f1779b394f6b608fe9a13487f1d6236db932b062b9e7ed7	1	0	\\x000000010000000000800003aaf958fafc356219bc4ed33a11f5897e2f87835a86d52b84b6a974c5dc68d0081df57eb0145ee5875ebaaf5f6c5b2110c9584c7d878a246eb8590c8a1542da48b9ac2b2c1f61921216832d2e1933072c46f553e0cfcb7862e49bd9e95ae854fcf579a4c69449ade6eb7c3ae6b4eccf434329a4474350d52dfb15ff3490d43c31010001	\\x54ebf35fa0280c51e53ba0dc15bb0b374e60a6386a66c2344e2c46204d76a51137c6481476a152aa96c96d247bc4bd4356c587ddbd631d8e1334e4bbca719100	1670827310000000	1671432110000000	1734504110000000	1829112110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
301	\\xd116c743f1653e94a0a20e4fa34b4026991374359ad8f98e38046c4d66285c0391934c0601adb6058815be94aeec4e493645855123d0890b2dce37505cc332c9	1	0	\\x000000010000000000800003b712737aeef8d9b3b5e669eb3033e59af66147bddaa947b50013c21ab2365785be8e3ab49e75ec761a4a9c8bc982b87033edfe48f1767e0344ce13c011ec45d903925ecd0306a0c0cfaa20e2f63c3d4c982cfb474cfd367ff7c449f315067ffcb5e17b72eeece09793dbbf8b90e9d0a4235102f89b1145a740c73f5ed6bf107b010001	\\xf7c5be68d5cca3257002b89776e43d3f0665b5c114fddc041ce5fb6be3b95aeadf160404195161e65da94a140a260c9a3047b977395b20aa9169e403ee84e50c	1670222810000000	1670827610000000	1733899610000000	1828507610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
302	\\xd15ae61d5e81ad3282064ff5acc515453f9bfe0273f3711dbf6782a5abc4859b9a72cf7ecd2946114a26c9ae6d079d782629f55555b58703a182edac51eb7f21	1	0	\\x000000010000000000800003ae2fa3ac073bb36f942bd9ab96103c8347c291256c06d2f4d1b9a11fc36dd6c0bc5ebe8350a74bffa1f52f9f8608c5e5297216983f3b5d83890edae69d7033b1bedd8d5553bfe6908cf26992d1f21c1d22033c26d58dd88df49ef32ab24aa17820a55f81a696beecd69f471c007323518515c170161cb15c7aeb75850a71b3e9010001	\\x5eab160dba23d512eeb1919d1cbeaabf22d38065daa125acb6aa03feaa74e321acf6405728266cdfd393147e3ad42cd3d6a27d437eb4f04051b2e650fe5a4e01	1649065310000000	1649670110000000	1712742110000000	1807350110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
303	\\xd142a9ba15d26fcd98169a3e1f1be8d7c3269463c85b05298600e9e2db1ef00060677a810421225a2a527c5f426d3fc77d5f66bec53e5ebdf556acf35a1a7991	1	0	\\x000000010000000000800003a68c27d2cff33ff8604743da24e7ebf5447ab4821783826bc3cf6e633762becc7b09cc901315a2f941d7a592e421a77f3bd942b5215448405caf1d487d7150a77b9226c07442f8e5774bf407f92c80065f86481afad165538afba42f7bcb57cbe7281936f389e389468bd607d555ade9b5bd4c7328924bdf43091f367f43c6f9010001	\\xa0e1768445abd38a2a3bcf7e1dad290d7cf72a5aca27fe6abf23bdb566bddcc816f35ed45c06c4226eb67771a536506637efa71061ca367ebbc0f7b636801b0e	1658737310000000	1659342110000000	1722414110000000	1817022110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
304	\\xd41eeeb9b3b2806c25895cde9fcd8347cf72776a058dd52de120e6a1d49ab4549927b6d8c88710ecabe0b780f7398fa70141f623c69533c9a1da0843bfb12df8	1	0	\\x000000010000000000800003cd747be5f955242de13bb87eecb3f8034306087d41e583227d678b555da63a43fce06a2e578175008263b5db1ae237b7ee9b010d46a9591788c03f7ddccf265644b5ecdb1e31990d5694c1e7c68c93cf42fc90bbdfb6a8eed2795f7396a94b1eb104184094d071b302a8b4e22f1df1504f496fe0c7046aee2a486df8cb151383010001	\\xfb37c757bdc89ddfa7768e0ce2c8fb07755f146273a40ffb409fff8b94c79d0198eac47ba508bb89df2bef136f44547bdea08eaaee6903c0eb4365ca4e862701	1658737310000000	1659342110000000	1722414110000000	1817022110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
305	\\xd4a2431e5b64044c01b86c3a34383cdbae7ef7335d3bc31b6eec911dc59bc2502626188907b7b7cf444261582394a0a10dfa974cbc84618eeef22a2b7971d5c0	1	0	\\x000000010000000000800003c17cd070d0356c5091fce13942d9a24c4d1074f418eda89755fa77a35804818b72047566ea95a381363db63c8891ea868537635d5e2c8eb0e6dc4c04e3933ea89831940c26692a5e6feeb0cb253cc1fdb51fad9af328de16b0944e807a934249628be7a7fe12ee432c85a62d31ab5fc03f5356cb41fd5c120e2762523f83669f010001	\\x903f71a9d282dc208583fbdc1fba323ab65839455cd8d18839f47676ca08b879e868bcb823904e36324e74189739596410e0484537093bcc3a90938e7b79fc09	1676872310000000	1677477110000000	1740549110000000	1835157110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
306	\\xd516ffd50a209705afc61cc775ba02132a74dc1413319caa8ddb22471a714d39ea5f852c7adf6599205a32aba30ccdcc523f0fd6c2dd5865691f5dc141ef2b71	1	0	\\x000000010000000000800003c8aca3b3738b53a3c303fbc115634ccdb1c58ab132e0653612bf84aff3856a960dce8fa22a32cf28dbfaa629ab5f415bb24d292129080fa47eeeb73d4f92cee7db108fb0c2c830b7e000c3925b7fa26c6aa533d0dd081fe8044226101d62ea48e040fa718dd928e28cb038df2ec61415a27d0d8985624d876e419c659b9a2eb7010001	\\x5c048c782c06d7e2a410be14c2acdcee831042886df0785ce4ac9ee5b31779f7f20b57f7198f8b98a38f2efb99fcf4a1941b061443a34432cd3d31d6f2fce40d	1676267810000000	1676872610000000	1739944610000000	1834552610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
307	\\xdace55bd0402eb194be68491f0b6b176f45b25f20317658cf399b7303e148bfc8b5c7ae168c4321e81f4165a51082cc740364c32d11442ac1cfb8f13ffbeb492	1	0	\\x000000010000000000800003aacf41e001b73c351932694bc6da92de43a4556f2dae6a89f051a864766213a9d66bab512b8d4ef4e94a043abc8a2c0876e3e3fc0ff9d53b8b2d24822106d888deffacde5993ffccada520edfc0692e6d2f55797553cc7f4b7217a6e090ccd931653e5f00b6d1239f515d287d061e1c786e095e26180dbdc8d3dd053c59748f7010001	\\x92ee0183bfd95e788997009eac10a8f1e810d293ada76e344d48a3595d35a11769526784d5e040d1f861d466d6f81d0a6cead96702a9d497e6b4bfdcde96f907	1677476810000000	1678081610000000	1741153610000000	1835761610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
308	\\xdfca7df91a4cbb862da884237e023a05e682db6eafea8716cb8861a05b57b52110094211eb3372a99753088a84218edbbefdeb69c4bbbc8974e91dc97460ee74	1	0	\\x000000010000000000800003e4da26624cd3bac91b0160cb01e7806be8cd174e5627db652b0a578f82ac3805bea1e69cfef1cea9808eface182b788a280bb4e5d76cecfb683a1daf4e58d02c362e3a27ef5f8028eb29a99745b8bfc9edf708f0fd265f298618b738270dd766bc46bdc700b7a549cf3ec3013b03ff93f0f79a55c7668b8c8af19024ccb1d479010001	\\x35aa79f427f3842b4238de491b4e652573bfb3a0f0c894dc73c7d65c4de220df73f0a7f6fd5bf3cd9d18c2de1a880c5106e4fe24f2d81eea9db033d9380a8403	1662364310000000	1662969110000000	1726041110000000	1820649110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
309	\\xe002274aa00cda61fff18640f721b20813b99a39ba65cf1a67fd2c13cbc1ce01544f1a8e84c45a6d9e47a3fcfdc68f77503abc9a969b2b455d58b5dd8b71dedc	1	0	\\x000000010000000000800003d6c0ff44598365cc0105c31b42b1f50653e25c124000c14f64233ffac0999590a608281f299d270ff9f57ed9eae78f5a35c4df4cdf99eda5636d5d570ee3ea792aa43f00ed2be5e51ada751af605bcf4e94fae924eb37ec88fa5ddbe546c490ab7af6b740c6057656762ca7285e7c797bef91691b8877b31a33f2fae5c9498c7010001	\\x619248a767fc99bccc91f37ba68491c255065f12e17c745c481e94fe99bf3dd0594f4044470677257b866171b262bfbcad917857ef3ba65ede0a13672712a006	1656923810000000	1657528610000000	1720600610000000	1815208610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
310	\\xe2f6196dee557337cac5eed83779e5e099a7bd85946e68b1f958d51b420dafcec0e5cc903c5b69a012e9bcfb8e5f1b597e8927467b3158d9f52ebc6c8504107e	1	0	\\x000000010000000000800003bc40f5a4310a98f60fd6030a204b610f6f81c509db3690fe8de82534ee707228b09f11b91f6def2ce78715ba4e019be4b8eeaf19c1cfd74c44cd6224e224df5425ff1662e424517c81bc358c4fba0e4b163f9b60dd5918cc6205502e1941d597b34c4b8279eeca1df912a61ad8e79cc38b8c9edace49f00963a4d7debe5d070b010001	\\x52886014a85d2fba178164f23b7b934b81f0779c0c9af62455c662225ef78b95abe24a3d98f4f97c37e55e1046a6e6d1fffad012de8aa8eff1f399c9479e2b0a	1655714810000000	1656319610000000	1719391610000000	1813999610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
311	\\xe2e2924b1fd44b9f54f52a393e3cca993bcfeb9506aac3dff7224d86ba55d14d1b076f15e6b08d71f83def6c84a854520b7d82baf842521a21e7ed07e11a140e	1	0	\\x000000010000000000800003be5eda54dc64d0974adbcd5f41c44780c9e9de031115e86be2af3eba876f4d2001e566ecf721495bafa036f9e943a5209700d0954a4669f7376f9a32e731c76f5b02867ecf4defd823dff0f1c27c8a9e8c1ea4ae000f0abeca75931daf2ea4ad961490dcebd0924934fabcf20ab5e6f168922ad2c54cf3bac647a117611f4e79010001	\\x362ab6e68bde347ef3e2cf116266d27522dfba0add9a252a513aed88bc7dc959b12b414baccda9a2ee5cabaab4a2e58dd46797155ec0e332cb7aa0cf1affbc00	1666595810000000	1667200610000000	1730272610000000	1824880610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
312	\\xe33ac2094e8a6aea3dfebe796dbf55e99e21d1292a8339d8646af6d2ed2d3d7ff4380e5d720c4292e5d6136f559213e306f0073b809a2bb803d41e2248940af5	1	0	\\x000000010000000000800003e8447ed56b9f1583c501a71405db5f5a881b1078ff0be26c746617d2d46d615f1cdcb015e8e8f91d48bea6697c69a82269f5f60880156103148845b025a0b56b9c5b7f9330063c383dce0892a4d29cc428fdeba96b44cd72dbaeb453ca45eefb37763f6c4c9bb097b57cf27f5cb6e0258fe015089e1ba14e749528cb9b8f99e9010001	\\x34a894e9e7e4c32f2d575acd44dfed812500aef2219fa7fe36c7edd72aaa96b9383a7514db557454e3e0ebe478f7d7a6869b59cea002241b71e44a5b0c32f605	1665991310000000	1666596110000000	1729668110000000	1824276110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
313	\\xe7c65df181fac73f65ff8eb83ce6a7a447715761771bb39b6fd66438470c3a920572f525100cfc367db5b0a347c670d790d014eb62a7b49da15f6ad3071d3072	1	0	\\x000000010000000000800003babb0d336deb93b92d5d2cc161ebd209e20f0ae248633ded054daf880e9bcaaf078fdbcf9b3b343e9cc411dc3f6ed0ddf52dd360001203c5616f7e258faef876ebba3b7eee60751f61fca9ae2fa7723085f570826481b29f19e6e0cf0d5553255cbe263728520e80e39f9139d5a339b3c7fe05689b5be6442f253f9ed88c8541010001	\\xa08a912703b6be99e84fcf7a66a785c14e4cf199f87e713df7c18668751758fd64c4bc7994e19b691fd5e7e74e9624c85b49da30aa8bbe9865a9e8f5d97a6b01	1647856310000000	1648461110000000	1711533110000000	1806141110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
314	\\xeabadee48c0696f02f7f14ea5c608a51cc7b4a56f8d5345dc499c93448d1a4810aaf1da9b810f709d1d91dfd42f5024c32b0c449bc36ee0e6eb00b118c0f7127	1	0	\\x000000010000000000800003d35a3360fb7180a53dc1fdf6efa23fc0381386a30a54a794c60afe88cac8d897acd998bc41c01e814455beecdc66dde35a87572fd12723c46b8454b8894fe665bb8220ba72b420d055c7622b9ede2f588ce471b4fd5068cebad47977a93e6288239ee530258e29ed45b1d54e3088666ab807ca676c6f1bcdd255291d0491b205010001	\\x54539e79ded7b4ae64adbd701cbc0b46cf4aa021daeab085045fc47fdaf809a469d1075b488dcc67b9d0dc95637748c35418490d02ab36eee22823d568dd8a0b	1653296810000000	1653901610000000	1716973610000000	1811581610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
315	\\xf03229dde281bbeb00f393b49e6a0ea419a9265d710aa860b097f3cc4181e6cd58bd04a13f06d2a06130af4149bc521e5733fac5048e3c2b1d5f56fdc55b537e	1	0	\\x000000010000000000800003e285d0a89e33b5f21085b5cb6b09d7bec66a0ddff8be7c0173d9472df749d9e145a54249e2fb10b6acc786a67417679050722a9266a202e32153708e3fce8e031d841b8a8442879fcf1026462a86ffd901d20a705fc94763deaab90ef7a2ebe55b2ef01e4bc2a9f5ecf044fb3bdb36725e9d86ba4667a0b6650480b144ada181010001	\\xd486f4829bd1f0d871e8b1e60f15e62a3db4a4e457ca61c7fb667dcd691bce6f4ce3fb3f3465e2b689dd93693338b68611589b854cfc010444f3c880693b460e	1655110310000000	1655715110000000	1718787110000000	1813395110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
316	\\xf2a6eea8ca4042f9979cab1f6e0ed8522d3c2fa866ff5bc84497b20e13829a7d25a23d90ba833b6742379cc8395c59376784e4c193596a105f4a5acdd7de0e22	1	0	\\x000000010000000000800003de2f2c38ad2cac0bf69ce59563911384b8b1afce25973eee7a845061cf120702034bcbe22754b0dfff378c5336487a506ece914a5c83427c9ed07e6039b23bb7658b6c439cd38f2f75df4202ea14d5d21962f8175548edeb2eaf929e72273fded556f54557b396697511e549f7d5949f1341e240412383acf15fd8967c753551010001	\\x4e7f5b20e8f7058c026a0cfb726faaf8ebcc59d2e2ad5b72041e735eef3648ba3f815c482190280b7016278dc321c2014a222d892cd0fa2476477f2c5a85ae09	1656319310000000	1656924110000000	1719996110000000	1814604110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
317	\\xf6467ebdeb9adb01ab331e3120b2d6892cef9a93be80bf6f36ed92108a1bb2a58208cccb71a26cfc5f5ee6118e07328c0cbe72281392dcd0e85a57ca8c0d6302	1	0	\\x000000010000000000800003b376e3afdb566a1b2053a714d106a54fd0e5631b369c601a0b552c4ae551b7b26b89690040635e80d5b617d269ee0c66e55b9bf9a964e30998ed13420d4055043c5adda8bb510f4b6946305456ed3dd7fa14051133f3a97f847581bd9aae614ba14611601863a1f245f7347d48ba9e11862c33966a471fd9df0d15c72f6d1bc9010001	\\x6b75f07f24f91aad60247fb7ded6b719f52377e60ff6e97d1e085a225db154700fa9cef820a8648696046d955891b72fe2516a4f6d9dbeb1e211367b0c80690e	1653901310000000	1654506110000000	1717578110000000	1812186110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
318	\\xf8faffa60177fb09d7ccd0ecae3a823ddf33392e5832b56af1c363700081294d2469b49a4498adae3faa509d81c72e45f602e5b6429766ede60ac7ebc746c297	1	0	\\x00000001000000000080000393cbe06d70fbc9aad6372bff153650d4bd17392b677006896ffc0c0c2d3c77d9a7c1f4ecaa133b8bff4ec6fc4d26c497b3ac072ed883edc8950776a9521e8eecda0e059fc13bc0bed2a60991fa1c33c736551fbeba50ec11d28e12a61bd83ad4bd92c619bf3ed81286f6a452d3689c650c5ec2da8688d3e0328b7bb42eeb121d010001	\\x3e0fc3c512b63dd46201aa30fb6d0e1d2551d5e29105f7f820893fbc0fae738f591776a4d8b8a9e32493f35b1569d82036907233862c53c4583757c522467902	1649669810000000	1650274610000000	1713346610000000	1807954610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
319	\\xf9e2383f0b7df44916a27facc78186c68c22a3df8c4c58fbe0f7b57cbca998f5ebc3c5f0f9485eb97f072ff92f4b5e85f6a870b33623536035f7b50294a01f4c	1	0	\\x000000010000000000800003c931e700a80978c78dede05d4de7c22a45ad6b31c573b25d6c66b68df0e4059f7f649cce917b48e3c130ead57ade86a4d2dc9d5ebcf553c28757bf338acc5c2549c18e871a6e8d088e609cb0dc64f21432a8fa54d3bd96e76fa1559d4ed34ed11c2acff89bf2120eb6581ab28c2678df4eeba0fa89ed44660a159e7ead9cdc83010001	\\xed9c90b50caf34b2eaf0dd27e73341675878b92f8e59d23af8551a65deedb1d28e1d3fa779fb9928da227aa449bf00cbbc68e670ba8402e457f0d47b6fee050f	1653296810000000	1653901610000000	1716973610000000	1811581610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
320	\\x04373964949702646a5e33fc8c06884826ecaf50bd8cfb9ef55d6fb785fe132c03b85f8844c04e3312c404f50deecbc584e8e1c9c07b1d074e288e6f0b42ab15	1	0	\\x000000010000000000800003a33d2479125ee543f1bbaf7e097ceafad215b6d3066d999f6e6b5a6780b543d954e56f903b4223cd69330f76a3334aacdc4e0bec3d622dc9291fa4fb90561bf8553fe447266c2ca77c4f7642ee5ad2bdbfdddc21419150ba618b72428b5c61e2da77841ef51e54fd6bbf8f9b84b5e87e186492d3dc05a534da2f285b6ee5f6ff010001	\\x0aff5d1a843d87e729417275c33977840d30ec07f19f5eb3b42b63b08464f89d26568690677d78d81dd0f0dfe3bec6a44de0d4abfda1d1341b6f81aedd1b1105	1656319310000000	1656924110000000	1719996110000000	1814604110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
321	\\x06cbfd7a9bb6101fe9991894e86c0eed1252d25275e1047b8e1965402faf17c994797a4ac1b6c2961824ed078310d5d99c7ee6801fb2858c81cee0132a4626b3	1	0	\\x000000010000000000800003c3824e48f61b90ca8cffae5f1bc73572798cceddb4fdd1b50961d5f29feac5c548886012711f3e85eb33a2db10fa435a8e7cdb0a49c90df069dc4cae3957f91bc3680263fbf9a8f8443ce91ffc1f1b4bd138c6fd867e1d953a2736218ed3fb2daf74c5c919c045b8818040c55d011c67bb2f2e6bba0ee6eaee32a69c13656695010001	\\xadcf54abb01c88fd4d5b08210456f30127acba1bb2ccc4edfdf23a5c8570fd06d26beb57d9c2b8ee0ea5a2ca2a7f118444d6713dd998c86868f5d2053b1ac80d	1674454310000000	1675059110000000	1738131110000000	1832739110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
322	\\x0b8719690208a8370010c00bf052f59fe78aa2dfe0a45ef94af9bfbe006972a13fda93e6fc153912bcc7d52daa27c8ad2d81c27f272e7c30347636f942ee395a	1	0	\\x000000010000000000800003b0593bdba2e3994f642dca1d9d0dcdd1b12cdddeaa86b6548ceb91fc0fcbab2e51ace132c5e2c33462f763922748ae806499c13d0356655bc3805dd7698985ee8b4a87caa978f7154fa58b2b2ba80f5565171f669d8b7a06d74a5ad4ba375741924434b283321957942a40c7ebc0c404943165998a74ee4fa10a219ef37b183f010001	\\x07603bd2b1f25bc390ff0dfbb6c2bb16cd42b154b769ec2069ea2b8c39e69acc529486e3870d793cdd8db966dd5b0907b31b69e30cb03be46384095833f4f603	1663573310000000	1664178110000000	1727250110000000	1821858110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
323	\\x0c971a9c184a4b0cb216d7403e8db435049f3fbe33b6425f097d6632f6db4a450f4172dd9d603d65e9b8141e50dc8b78e4335650b2b3d8699f02d0d67c739065	1	0	\\x000000010000000000800003a6639971bcec762bc6113f7b881282888eb1c854a27f6eec85fe4b63ad4893f6bc26ddf6024a34dc6511dab6c08361905823947f75d6e2ad078f20d118f0c0eeef500b13e57b2e2890f45632b5d5d3ea07139b55808ea56ac85c7dcc59e4fe0a5845734e1fe420290d9497587d1fc4dc23be2000ddffc89ff0bf723bb46b4e59010001	\\x9e39b3265c0ac616f8d4e2f4157002c1c0f4e36c8a1711dbfc090ed49cd3a032fcfb31159db333e1a22981d611d92598af5fdfec1760bccd67eef7b18aa71e05	1653901310000000	1654506110000000	1717578110000000	1812186110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
324	\\x0d43b7b8c8a56dbb73b463e280bd73f186d4ecbb8008a0f40ff9c9f02f410a061380ace389bc898a3158f52de2c35cbdc139c143a1a52e63c4f56d4fbbf4a867	1	0	\\x000000010000000000800003d038c3a818d83ca8bcc0bdf3daa3c777e938f06392562f197b07ad5e758988dce9ec229dcd4bc8a4af53900e79fe0b767b7c43747e3efda5a2c3709010474031b4a31784b4d9a0c174cf1919bceba0840daa6018504adcd7fed12a1786a8c4a0cd15ea75925a74046ca01a5f4fce7c0c9c304c31a42eff333b4f5e8fc823aff3010001	\\x409aebbf3577e8e1dddf5dfc652b284a970681b53e39b8b3bde5ee1ab67d6c681eb3c0844bf2c8c38191fc4067ae750201d463ad3ad9ed1bdcb3009d38301d02	1655110310000000	1655715110000000	1718787110000000	1813395110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
325	\\x0d8f3db9520198d98c4fd53b885403259173e72fd4179ecfd9dee656c06d2a2090ccbe768f11ce5bf6d15330e4cbbd99c45ca400ec76f2b9d31f506113ab3292	1	0	\\x000000010000000000800003a8d4afeac7d46cb6942fae60c09d31abf7d084e61afe2704907c724708ac2ea7f840f09fdef1f0d0759d46ddc96ddb2b6069e25cfa8c3c75b0309a6b47964758dea338320d204c304fbc6127fb623258d27b873548b5ccd1f6478e61543b00c5ae18044137e6a7243eeb91d0a9943f2c2fb8b5e98dc70fa0d4b3d69af4ca013f010001	\\x2b3f04b7287874ec59fa83de9cbc36bb574ac859b3e58777484e97df842a1b4bfc080eba3de3c8555237e45b01443c9ce8d43a1b1020b79652604cb5c0512405	1656319310000000	1656924110000000	1719996110000000	1814604110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
326	\\x10f3bf24522ac5952e1d7d4a8fe641729c1e86b1f6b283f503db1f5f786b2b39897c4253462b485c0f6f26efbc433572c679e5b4a41cdcce082c0a0544935c14	1	0	\\x000000010000000000800003b3fc20372efb36928813e7fdf0d8acd46c888a4ce0ed1543868afd141ed4b73bc1d3d488d27a2ffb0584fefed1b458c6a95b7b52451d18f1d3a71a6b15c32dd6db4b7791d1e19e4c906838adf67b4e0ee4d70ce37d5f0f3f85148b231d03299158d89428d19f1f0fb9390d4005b98d83652bbe85e0b9e7904051d41df82ce34f010001	\\x33c466a2f7426ed9aba12564b9a9f2e961aafcd67cf36166be8956b6f96625f2fc78146023b82cb84e53d81d848eef50896b840c72c9b27d45f1469ae05c1106	1655714810000000	1656319610000000	1719391610000000	1813999610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
327	\\x124b20d37a23e052aa97b906f4aaab3acc1df3e4fcd051e732d3fef70d8e29993831e9f504417fdd34b7880757a7624d9262088f7bdc54f082f65724f88b1691	1	0	\\x000000010000000000800003b3ce3aa4d0d553d99a5b188d73ba01e945f282d404658bc2952f4bf86e1cced8b2a6aed1b13a61bec381d40a9174f00ed8aa5541a94ba50be606c226565e8cee8d58c5f915c1d3c298b16c87419eff7f9e4e4425103c0c98dc6e10f21df2e528c445f810a613b28a5539bcf82cdf6043f23e02a185fd513354a01006c3f9e965010001	\\x227eaf2ab498352bc4aef02a2769cae624ddf5ed880e554d4075ff58c5d5851633aeedd0499e83f775b4d8953a6cb250be29d00331135a6d76cb31e3a87a530b	1646042810000000	1646647610000000	1709719610000000	1804327610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
328	\\x15cb5f34cd5bd7c8fa94b07120731127ffcc720daf5b7d432ff8a7e81c972d1268dbddd35319b6d0ef24d299642654bee562f7cb27420526bc8d0eec5749656b	1	0	\\x000000010000000000800003c3b443e38d06b17487afbfb3987dddcefb9a7047b138e2694a44bedb2d5f17a3dbb1784eeac78d48fc66b3562d78b42b8db01c003b1f7ccb38e4f98a99af0a2bae9cdfb8f3826685bbce6d68437a8c99aa80f3e10587d54ded5d8fff6fea0f3da8a8ac6030e3153d97be47f847963258cd72ea0f671128d9876e1c43f933769d010001	\\x3277a2c32c90d7e56f3ad52f6d6cb88799bd95c96b5500c87fe08439c58ee17ba1e5c0f0bc2e9d4d5beada0b3645fb665aeb77e76b668405d69554c5b247060e	1647856310000000	1648461110000000	1711533110000000	1806141110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
329	\\x178f5bfc6a1cd7f90bd5e4031ea1308a25df65d5b4d0b63cb53979e551181583d9e55ee6971bfb3ba6c79b0d6a57a17a04a7c89db9ccf1e13596a743e8df4c72	1	0	\\x000000010000000000800003cb619c73eb01c4db5b6b8133de226e6362a2362b2de1ab747bb109c4adfc11d132db69cc4debdda14bdc936d11fc10d42d328e6405743f058bbdfb33eb2fc92f79c4569b9118a9d831b49ba1745c3c1bcbe397b36c5b5c9ba42313ff0541dbca1a14dd7e58a012a8abe45a6eec59b57f2a139aa59c7869f10d91ed87e52e2c8f010001	\\x839f8ea84f048a9ddef6aad695f2da9c95f16b27502375ec326c802ce85125b26631ec3315c629ec574363a680c57493602bd008c81eb55eb033831193afcb05	1670222810000000	1670827610000000	1733899610000000	1828507610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
330	\\x185fb489244223b3fe463bf9b3e8f0071fe285e4bb49f4ac4257d2f81ba3e6d9ba5b609e7c2d17a22e95b05e4a70924bfec5f9ab3b5d04767f8bb0b7fdef4734	1	0	\\x000000010000000000800003eb11fcfbbf70a47c20b90381d074de2c630cec73e58209af8417247f9e19bbafdbd8c8ba69d0195caea9bea99394c9aa0620acfd218c8a1f47bd5016a5679d76df6a5a588c2af3a1fc1f654ab97ec7fe2744fb1ba3dd857ef006726c01636a31713978cfe47c3f162c3e85b29dd80d7f7a35483e7efcd4156e4b45616ed127fd010001	\\xadabb47a58be35e8f4f7d2278af204f24fb5e7e97933c7cb842dd78398824352457f7a1a267a619b926073f66e6d9749fc15f166d4d214b259337e152b54f30b	1657528310000000	1658133110000000	1721205110000000	1815813110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
331	\\x1bc7d35ff4af634192f3a59ce75fdba02eeb20cf431d1f5d122b5a2ca7400b2e9644ced5373f064af6bafc353b44068a9d10cbaf72fa3559c79484762676141b	1	0	\\x000000010000000000800003a7e02d802d1a27d56aafe9b7cb517b2cd91b39b5886be902c2ed53ef7892b90e08741868e6d72d6f2fca9069959715d2a0f9bfcd070f8857095808354df066a669aca3a18f988f87cdac616d3fc93f976242f5c2cea5ac4a6dda05f4aa0fec87c04f4701fdd444ddc0dc9d71982fbffe09b1288e8bff35282c20ff8cf492ad6b010001	\\xda75dc0098b522cc8fe53958e4734da7a9f2d20094eb78dbd9d8959ab3a74ffcb7005406b8688f0a534dc0846a1b1a6803389cb4b941a351bdfe8a2f67560f0f	1673849810000000	1674454610000000	1737526610000000	1832134610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
332	\\x1b2bf3fc41b68ebaf39950091cc2b60c519efa229b73d848e386f0a041243b7d07967f908207feb0fd480447d90a89829160940cdb4cdb980cc85ceaf2eb2c8a	1	0	\\x000000010000000000800003e80e22f93026eda8986c1832249b3d1009407b394c21222dcb9d9a9be7f978e421739db3fd469f053daba6194fa0273c8c1cbc7b6bd015a957cecad02e4f691f7931564895ae98abc6713ae2cfe9b15b804178d11932f9886bffcc0cd8e876cb774440007c3015fdadb6d86e39802577dc1e665743824bf263d33801312bb7f3010001	\\x38bbbf8d3cc3cd8395e95782406788675e65c1154dcc3a0a50414255a437901a8ffac7ee1fa475c8d2deb727322e8d81a65ffe8721dfa5b14e87d5af5dffbf0d	1677476810000000	1678081610000000	1741153610000000	1835761610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
333	\\x1c6be65df2f3676cd5c0baaf18dbd8442ccfe5faf8078134a3aebf9f24cfc4f115ea60f6a6e9e2b3ee340f9f048f0e37c4b9e61bcfa324b7b8ad5fa68026c06c	1	0	\\x000000010000000000800003b9f52629dba9f94946b473dec3c379159fa1ef3b4661fb59be2da5e132d99f21d364e27cbc3276fd629c863b5afb68953c6b5d09d18f31876f445d6c843d058dbce3aa825e6c23305631e47097303605d6c7b0c650f9dd6709c9beba402ea5d9d0155dd0913b77fbb52051673cd2df0a04a70883be873c693865fdb064355561010001	\\x619103a94d0cd07be33e1a4c68c9642efcbde7e85c00305f5584377ddd635a065d17b8d4355515fec37e10d52e95f63fbfece9b3d20879d63a38175cd1077e0c	1670827310000000	1671432110000000	1734504110000000	1829112110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
334	\\x210fceb6732dbfe1354df7c3266624d9fb11b93e8fba970fdfb12495e9634378262247be75dea213218638ead3095f2a2d9736f8abacd9367966fc294627981c	1	0	\\x000000010000000000800003b498427b74f2864721a176d47a5557a63b18c02d506d94798d3260c2598dcdbbf32a5e2edccabbb5aec28b51a055ee2481e7a2abe3716a8e71e4b04188067d3eba1e91162f6989285b0552aa06d14f5eb6149cb25a5f436f37d6c58469e24bcab90c31a0767c813bc17426e271c46cb65cc2685439d0554718a722898911fdfd010001	\\xd275139b0b4824b6ceb788f269b690fc301b4f95eb0175d228756bda31209c68eeb7945e64166044954ae3bb02f3adc596f11490e4850d0f2df3db798fe2010e	1659341810000000	1659946610000000	1723018610000000	1817626610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
335	\\x214b830962e4372e85f34a48acbca4dd595b5e681142b2f445309550ba0f95712ec63519135d311c02f2db1212a9dc6cf198353c57879ff8ced911ba162e31ce	1	0	\\x000000010000000000800003b7b3f15527ec8cbd18b306aab6cb3bb9c77837d392fdad1c5d2516ef656a1a3117603438cafbd0317f00ac5d72080da2d95ed1e69b56be0c774fe9c6d4d840b52aacac31f1961896f4308c20e1e11062d45ea7acc862758af6bbc64693f420e34c81c4ab3037ed642894b5b32ad9cf3c0793a89661a4d432ac2993c7d3a21a1d010001	\\xafc111bbfef56bf5fa6d12a6817564dd121a3b053be3ba735cd3fbc62ad23f990dcc86349bab0db757722be7c4a6aaea3cfec3901532d91cdb37e1ecef5cc108	1660550810000000	1661155610000000	1724227610000000	1818835610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
336	\\x236f7e1c229b603ec5cbe24fa9e888d0e99364b6683b0452371eb001b2d77f2fb675e4f515dca6c0b9f39cf66c5c56791825ff13a2fe620ce9572866c6ecc4c2	1	0	\\x000000010000000000800003cd7f13a8157d26ebc1979c0cd242468e790e4628e31941007ffebc0f8b8cf6cf50e09fb6183aa63ede62f5e49c7e1d9fe4fb34cd91a439af4318d2b8b7fd351628d2cd3ed3760b72bc3b2baf31196c9ed425d53d976c2ff66c403112b0906baa8c92ca72593d1f47b14a6cf0b7ed0aae5445a2566d8d4e0585d978f943501159010001	\\x8cc1cbf2c2d953d8934d7cf1303d4af76251cb45fdbc24ac11039b79e6508c89c7f41477b69dcbe3b6811b454572b71ff7137462dbcdb8617a918f41febee60a	1646042810000000	1646647610000000	1709719610000000	1804327610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
337	\\x259faf8c8145e0cdf07316ec33679abcfac48ac8cc645931aafde3bfde3301f7df08e7bb73dc53b95984d58e0ae19a86fbdb4a703ea0479c7cae23e143015887	1	0	\\x000000010000000000800003ee3396712d5323a7b9d58019bf6faf47a0150c7627c888e4db859e3154cd6a2f851ce387a83bd06696d1ad9d7d7cf9f4f66e33b4bc335de0e130eceb8c7d13d2d824e07882ca35ecf252c4caf1a83d5099b07ee7f629678e7229975c520bd0632f3f47c2f1fcc3883f42965e85814d73da461c02a88443664adf5c674522c96f010001	\\xcc631bbbf256d651664f66ed727c610d921d24ae5d26bd39238c436d070bc328c0dfc62d853ae770618f97822b71797a62080713974c4f9f9db80d0f6c34a601	1677476810000000	1678081610000000	1741153610000000	1835761610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
338	\\x2a231179b4c98dcdd3d565d34378438c20a9aeee85adeb34fe1189d97f2232a4fde4fdfc09907c4497d237e57afdf9eda2c02d2a214ad2e71c7ad0b8dae85111	1	0	\\x000000010000000000800003b4ec03f6e03208aaa9906773b7514a9208cb05f9cbaa38c984a5006cad0a173e38cab5e73cab014be5017b9526ba6839af6a5f3f21bb199ca445c781786cc6252f88c34b6589c5382f90903a496c2fac8b3b12e81341c9f451d65d0f72922f95e420198d7593a511faa37cb71c105e66da649a5b7e2a1f17f9bebc883994c70d010001	\\x0cfe84ac13d7f8ad1dccd7eff61bf4450083f3886fe69e3ea5a9188c737a593d9fa059e053743e02195f955248f1589c1706c43312ea359ad793bc05c01b2305	1672640810000000	1673245610000000	1736317610000000	1830925610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
339	\\x2c13e4f150d7c596ea10767956089a4160b7292c1eee0b331e5c058e0f779ad5ef10b6b4050be859a038e909748d2a337bde084ad01d79c060b32f21042df3a1	1	0	\\x000000010000000000800003c3326ff960dda7e10852d88384397f5bfdb95ac266037dab24b13dba27ef3dea7bd0551db3dd60aad62c056a80e0f4ebfbfd18dd777b8ef575335b887aadc7aaa31ea8da587d15cead0b03ac9f9535a44bbeddc78625c6c9f88e8b332e4eda2b4629e5ab3d327f720dbdb0f69b5165273130e8264d0491156139fbc61454bd27010001	\\x973e0032cf2fd217ffa288220eec378a8f59988257d205b3544b5822194f9ef1fa09c7a3407901b4cb1d5d4303aeebc2de34e2afa2e6e10d5d654f9593c9810a	1664177810000000	1664782610000000	1727854610000000	1822462610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
340	\\x2d93c9a507916ffd187d67a0031a1a2bbddd7d6c2c9874b97d021f0236ce2d73e0cad726b354d61aade3bdedb6b47f594e01ee6a1404ceacc9ebb97a72b7bf9e	1	0	\\x000000010000000000800003c7ed535d2896aad1697aab98f8fc6eb009ed217e7df8a637dc38902477a2bef51a3ae119e52638178646dda7c4a28cb93cb1a5379f0f31cfae610620219f6f2b195b58bedb4f193d9302bd3d231534f461a9ca3babefc41df056dc200775a6afe9afcc3e117c882d5c2e903fb995cac28dd77edfb80e2b6695193dd6aecab429010001	\\x88dacc6d8ead748642a80bf5ab15d5c1a1851434c3b67628012573f6cda90dda8e3bf3c0f10990f53d69fbb4611bb8cac863d3bb364eb00b2812ec83b8539704	1658132810000000	1658737610000000	1721809610000000	1816417610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
341	\\x391b91e84e44c3bf2b087ff4765eac48cac507c8f0dd394de8c5384e3fc3c6fabc73416fbaac09c93ce213c64525050d93a6d40e62d312e9b1c531e4949ec7db	1	0	\\x0000000100000000008000039feee82a8e0b8722c97e3592ada4a73d83bd5880009b84a3a71121c2c773c5337bc1445ff00eeacaa37bfa3ade6bc60577ca74dffea0b7772ab43fa2a65e8d625852e0533a7365d43f92e055c6460cb524291bbbc246e1b9729b811c183cd6e59942118e91cd63eb6708a35cc427e97febb8c493d0992ae09df189aef04457e7010001	\\xe0d03079469ed35cf52801d12e10125b7556ed5e3084229c327a914fc8d8ce49a7e6b3b2a225df4cc38f02aa9363b655d7fce94ebcc985115653a96b554e840f	1653296810000000	1653901610000000	1716973610000000	1811581610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
342	\\x428fb6cbfa43cec4b4e04d447fc373b8f13a3af1ba8a38f434266cb17311486e8e7c7ceef21c0e60e39501965e0de2fe6eccb7e757cedcf107d181da9257877a	1	0	\\x000000010000000000800003e32c514563ee5d2d92aa69e97089cc39123ac6885090c48c0dfc772e3ff74456337286055c9a58dce04e64765006c6a04f2d9f732b959eef6d76d372ff325f2aa22eddceeedead47554d85da80fdb9597543265ca4de115795825624fcb4c1c54172e8ff817d1a29458680bd3328580288eedc853aa8ef3166f6a6d1a1b12b81010001	\\x6e22bba23d24fb23b572a9e5531d62202a9dd3801cedfbe907c0f58348ddeaf7f63a0e1f4292d2b4c27ca73fec88bc12512a35ff67f6367b2250205337d42d05	1672640810000000	1673245610000000	1736317610000000	1830925610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
343	\\x431f2f6e9fbe16014ef1940487aeaa96cb0255a9e87b683f05f8572750f2231b3f75826288ebbad78ac052e22fe44244e47d69fe407c5c2d56ee89921af6d35e	1	0	\\x000000010000000000800003d71b157721785e20d728f6e6244b769927bbf73bc2d41b89c8dcadbf73773f0d7fbf06a1d2f955dd638204d12b38ed940da3f2ee1ad257bee97b75463cb2777501213f5b23e48099c34ed38b38c8f67f9904e9376e20d09855d32fdf4ce4cd785927af6f4e9f90de4fdad61c35f20e4c7ea17218feb8484f1f8f98f2d1ab181b010001	\\xcfe188428c31330dba0d62e8a1fa0c0fc333e7eff0661f71c52c6a60d38a03bec72d7103707b85dca4dccc85df895d7a31fda4101d659d4302ea5fc0c3a0280d	1667804810000000	1668409610000000	1731481610000000	1826089610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
344	\\x43ab4a90749c7e1a6c781c5d9d8af39c5af3f2bf3b472b1141fb66be9bbfdc5ac2e1fa3dd85a34c8a04c64ee8bd8c9c52494d331f7c0240a58bc5db3859a7f53	1	0	\\x000000010000000000800003bbe0014b6fb81967079121327b361c77de63ab1a44f556caad5be17d86f1f5d92144acb259fc398be03b4fa08115a12a30ce22ae6c9ff322f521025e5a14c4d8cf4003263beb97fbd5f96debfa9e28e2fea75bfd76aedfafb3b2e98bcd0385f6093f95fadc8865003ad943ef59985b7815583a624a00e8645e890ebbe885b725010001	\\x49d982f3836ca0df5a58fe99819deb623ad0fb41205d4ec8ccbeddf275df0028778fa40b77a2d08f07a209d036127dc1ec2896fe45b122f64a76a0581a306e0a	1655714810000000	1656319610000000	1719391610000000	1813999610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
345	\\x48ff5ea4be5730017a67909e76f6656b74ea10b465fda5622d54bcac6f7d7f943acd1fa76f62bfeb270ef5ef518aa60d1e229a8778072834dbfc903cb172208a	1	0	\\x000000010000000000800003c492b1ad2b86c862df146fe9b77dfb4bef13805199fa466c165556b7873d30a1f68c2158e5da29ce3458c0b41c935a24170d829a4873e181fdd17d70b44efa3d6008a463542e86e68b6fbb2aa45c42424a46ab5b074d005d08371f22d2f04c677de9136266068d74892e2092798692f4e1f32a4507ae1ddf5c811d5952e59da9010001	\\xd5add6e12d76a64408eaa221cef5ef7d5d2df621bd074cb30eae039aa8dd88080c78c0a65fa58511f0a2c8cb80c36eae90ba73cd641c0f03d3b4a095c2d36a0f	1647856310000000	1648461110000000	1711533110000000	1806141110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
346	\\x4bd7f76576961489a410143de6bb93c59cacc29a542d3eeaba7a266c247f8a8bcbc2a00173ee8f32713f3c67ab41ef87fdab71d8e38a1c7a2912c3cfaf275850	1	0	\\x000000010000000000800003cee8dda41bef0c1ac531440fd3ff34bc70584c21287e2c73cebf325d8bc72e05c1c08e75b2202219c9cb0b2aba3948a9fafe4651a7c23748ab67d187b4027cedb2d13a34d1630bd15756d952e0ff35b52f1e233694cf6cbbcc746e02bf01266023726f78c305a429b5075b45bc798009adb376d1ffe20b17e97dd0d44363d321010001	\\xdadebd247f93eaeac5556bdde60abc14bc335742b81bfab41cb69b3a42f7518840e41f29247eb81fed1a29dd7e40a0b4e79bc4e592fc0c544e252aa157fc430f	1650878810000000	1651483610000000	1714555610000000	1809163610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
347	\\x4c231b0d4d93e3a1c8a160be50dfd6fb87a560a828302d4d035011a83e5dd1ad047c3f20fbb15e618c2094c5c2babd1e96f1f8104704bb4319bc67821d385bee	1	0	\\x000000010000000000800003bfe40f540fce32a5004985eb273d4e8cbf9209129d5fc856d11cab86c4bd311b1fc7103ad0787158fbcd8c697e44f285910b89bf202b7f22983c375359cc9a0513092e1ccd78e5dee8bd913927b5593ced0155878b31df3f81cbf74192f1164befa6d80ded9aa4b9f70b56f7abf80fc5598fd3e16aa41de03873c04619e3670d010001	\\x1d369024632c8bd718675ae2a42b66e92424023daa93b602385e9615f7f4a811bee1e0b296edf2f182142f3d8d8590a904c60aaaf83e822ab539381b5f18a30a	1652692310000000	1653297110000000	1716369110000000	1810977110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
348	\\x4d6b1d9a9796cbede5e2ec9a80459f8977563231ced20d73f7a02c3d833e4edd95e91a860b1f42271860aa1575a5412a4d1fc526c16c554915e9aa584cd027e9	1	0	\\x000000010000000000800003f563ffd583ca98b1abdb00687310b9667129c8b8db5db3faa52383b6ee5ec75b42f25643ee970c1b244a4e7bba9638c0cad340152352097191bd520f548b329a8a71f6ef8c6ced7663104e4e18066c90ae2cd53b58929f6c1900887b6397cdbaa6232b3c5e018e5e1c435694dabc63d2600f42d33bb58afa5c19b2a22a9b96d7010001	\\xd9f6c432dc28316bd241df1019025a14cdf66fd6386485dcc4a58bda71fabd210cfe7fa0282a7e1b3a760a7e8ebdf89fa183d047d2fc6dd0f15a9aed7fe92609	1673849810000000	1674454610000000	1737526610000000	1832134610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
349	\\x4d6b32535249efed51f78bc2b8eac3bbd1d27f4b3e6fef8a80d70d29222f8af81f95a8a46f37ef36841d50b095a03fbbcb3ef106cfc8d21e82de2a87f22c538a	1	0	\\x000000010000000000800003dfb1bf5a48ff2d4bcbb5ed3102686476bfede9b3c3168defcc77525da6d78ddbe13fda742efe5e290030d16bd6b91f55592a170ccf297d2dfb3ccc8deba32b721a908baf05a3fe9a95a2c4020ca09658dc6dd007ebd4bae12c4d6dcac244d069e73e5da706af08a93459958b861be248080dbe652bca095c568814b31d0e82b7010001	\\xe1e462b7624ff8670d64f1b03914f282f10097fefe0e9b60433e695d260a563c5bff4352461110c68e2e9c4f5b957fbde157136ff788799ffecd78c547392108	1651483310000000	1652088110000000	1715160110000000	1809768110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
350	\\x514bfdc80ce7d3fc896544441c58e1e3307f4c90fbf0b3049c0dc16f02cae3f2f3fca28b833f688cdeb8c508981b628ef84cf797153370bd09834d9d9f9eb9d3	1	0	\\x000000010000000000800003e35f491721792fab86344600e90282104e49626c586dfc12a0914a5387b98f808c1566a175f28dc6e5e60a6d0075e8f242722e73d52ce121b3c859736bff4bdbf4491f9a56d93a0d87dc2a2ecd680d5cd842c4a846c44feae8c40be49dcf93f9f08262f214858fe8ff2a060c73d4053e0a60a73a7b6cdc37ddca5ac831a75483010001	\\xd724a5b6134e67136b73886c695fc28e4cc5376e2efee614be0dd486c88565e2777bb587639eb945291e2702686b7221003eb82210cf28cfb83b1f35593f410c	1648460810000000	1649065610000000	1712137610000000	1806745610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
351	\\x529b4cdb2c663c484f00b0cf92adc9082686d6ac0faf523b217636c96fbc4990f35498951988e3b54eb36da55c66d52eb180073424f2eceefbf578271688e2d1	1	0	\\x000000010000000000800003b6354abade55e589a17e2d0b7fe2f1e667a9bbc67382fbb8e4ea57dc874a9a5a1bf622f97225b811fa0dba34051f28157274b18e022a157782786339e975a7683a16f0d32e88dc5d551855b840c65754c36f501f6a834f890a6414a1fe24c0a71baf68cb641343afb4133a521dc7d0341fc083a062d868e40e495471259f871d010001	\\x002b5b56a5f31eb8f2b6278c1b171af9098124d1c3ea67ce7940e4496420b302ccd98ef65cee9fa976ae1d340cca49d81da0465bcbd9f58ecb9233eeb6ebce07	1662968810000000	1663573610000000	1726645610000000	1821253610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
352	\\x54e3729ab39e7db929311eccf229016043b6c10923e8a0bfe5e81bf17ea97323ff14c7f8d79758ec98efacdc360356f94950e9bb6c9927f9c0e22f1bda01362a	1	0	\\x000000010000000000800003baddb075eb4f8fc0379db75ecda156f0586a6a23812b5061012b82010e1a21b8fc092bb1b14121b24acd26bef24da793ed8ad531000a34f9a3b7f87262d790e0b679fc543b141bdb0dd4ff0e8503261f2db2165eea12a63766b330fe0ddfb4fa6abe26138c3c4e85e7857d27150c2e18b5043ffb454bb4ce97ad46e509ad3e43010001	\\x9f0daa01af00fe1f4a1fc01085e521b856cb567e7cc627c59f05c0df42833b998c54152414ccedc752e9890d3034f70262577f5644b3ef8f5d0157f807d9a10d	1677476810000000	1678081610000000	1741153610000000	1835761610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
353	\\x55437d82cd04a3bc80045cca5cac95a370f04e37e5cbc97d0b7ec7f3537d51d99f172225d83241161a793247277bc6a122df5428d24c59acd26248e57b53a05c	1	0	\\x000000010000000000800003c90852de940d1215c09db505315da341ff861a171ad2e9df0aa9dc4c20d271e363452669c40619f0d59b65e75b634dfc496a76a515dbf7040a593b29dbcd11a45d5a95e9683fd0ec2d19cc1848f5164fe2dd70dead0484c3e0db51ff11cd139870682d06eebb12d9aad3cf7fde73ae8ae55d340eb0e8178a1b35ff331c0be691010001	\\xd358c1ab84e63a01cd086f1b950d32dc3f4a0726a91918b3c4cdaf71dbe56df34fe7a6d295c4adf14608d1b344d0902516aea1e2f75aae8471431229d5ea2d01	1652087810000000	1652692610000000	1715764610000000	1810372610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
354	\\x5593d93fb21f8e1c4f7461652731525eb0c8bef27ada369ad90985d39c6d1b371ebace131ec9ccb84daa8f00f33608896ac617a08dd1742d0f70d5ab17f433ae	1	0	\\x000000010000000000800003bfdb9edab019ed30a42640a005e78c6720042da781699194e7d845b485b4ade44687e22d9e0d5295adf54c0a541a76e3e935776c0eb66f5622786a79412a96076b031e9fd4d839234a6114b76ab9c7e588aad07ae30887d70375c1c848f3e55077d2c540ea3c2a7c2d2eedc2af26373a692f846ad85e2aab786154199294f69d010001	\\x7b24de472957dea2e5681c3bdf0ee4216ef560ad683fa9aa24a80a1543ca089039cb42bdca012caa187b3e4e278593c2916af23d632091f51f997377cd645602	1654505810000000	1655110610000000	1718182610000000	1812790610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
355	\\x573738e8e033f62559dba7c0216234d823c5b433c069725d72d9ce5150b243aee057ca50b4efc515ddb0f9b1184654b8d8d37e4d622860a210d354b3bd33e4bd	1	0	\\x000000010000000000800003a7e9ec767369d1014504e0d70133567a6d48480eaf767185fc62bb3b16371e80d006adcde8f2b6c77aaa4a2c2c88847f1cd3a727b0e8ecbca60023cc0e0e5c3001cb99118c997e9c168d78993eabb14ab2292f1ce02eb8ca24cb6c50c0ff8137cf837c715019509e1c766fcc6785f541e8b706b8f65625d58cf9a7a9bbdae76b010001	\\xcedcca0232b8b065dc4b83e8498229d087c32dae830cffa3066b5c3403d70b7ff959a41aa429324b0d37d76e771649ab34661fef6abf02f2d712c7c633743504	1661759810000000	1662364610000000	1725436610000000	1820044610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
356	\\x577bf1f7a6ccc2340dffeac61db3ee00f4e7f0290f9786e932ab0369d7a681a182230875d587e4632e82be407f3559fb947a1f0a9ea0e236cc4c32bcdb2bca18	1	0	\\x000000010000000000800003ce6e4f6b561f938b613007bfc9916c9675a447e1d6b96d62a71c62ce854f918810c043a5fe6034bbd65965a2a0be3fbe4b020e56fa668428c560856382e60247b17cf611eeb0ba97f4122d71aadc3ef385b8a5b3b29be1ba74a23abbefef6ffc4111657cd46a5ede60e6af5b1cd3f64e110edcbcc6a81a24ff67eb7d989cadd3010001	\\x5e14c8fa717722eb407ca9051cbf004f06abb444f87af24b41587e7b9587dc29f3de9e16607c184c2f0a3d87eead0115f3f918d50cc5bd6452c096674f8a9b06	1649065310000000	1649670110000000	1712742110000000	1807350110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
357	\\x5887cf1a973fc0e8824017f36eb898d1eec1298dbdab36c89a1f224cd49e6e3b49125b57b76958563c8e257054af31006c70e7669fb944c7fd8669ae3294de02	1	0	\\x000000010000000000800003e4eab7908c4fb061a0a581419d8f6fb3f6a15fc41952fb7caaaa64a18c7fb79c32519b5f1e4c265805292613d987d1c84d9463c9299d3dc34e318563c2c1dc8bd942127eaaacb38247ad51be349f7c5607ae84c84ceb93707c333c8cb9cf82347399f50d79b1f3d3840863e38c91ea0bf3769a589711c9b10bd7580793e923f1010001	\\xa295ae971f4b65287f9603c18bafece9abca43ef51f3f4b75c649828dfe221cefdcb32392db1bcd1ca65cade7012a9a3cf5f38ca7184ec3d5e02adb10dd46102	1650878810000000	1651483610000000	1714555610000000	1809163610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
358	\\x58437dbda57916731eb00956acaade0ba053a4275fcf8c35080ab33b428c981d27039d4e3e7e3b5b1e3e22ec664372763e16cfb8d4aed5815deec1fb0f774d64	1	0	\\x000000010000000000800003b46bc8c1f0c3da2040d99901047de306172b003e9fe3bc8e65b96a0d1e9eabab9065d8b76400f73558324bdd4b34c40e6eddb4231eaaef9317185bc511fbe5e6312a94981d80a703dc61be6fb238108b54b76241fa122032ce9a72436ac33981cefa7dfd8b001de57527798335370339da276f4945696010ad504d987fc593d9010001	\\x248adabdb1a5bffc5cc2b906f9c303151c0de51f522ae91105b53e00b2be5c49785898f92eea4e00ca0f59a6dc7ac445c7c3375c140f27e27e27b6df921cd100	1646647310000000	1647252110000000	1710324110000000	1804932110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
359	\\x5cff906961b690068eda0e15d7ed8d1c2364c0ca9674cd46d141fa45560a773caca35f341e0639f046a0fd111158c11ad9d1b5020690821babe86d3e4656a27a	1	0	\\x000000010000000000800003ae127bdf925953410409989941be33131c4a73f84c169ae50c0d6e506fa692777f415642fc4d1594eaf327cba8919654206c16114f3c983ac095e235a5950036fbe802bf1fff31833c3be93aa41e941e6442a4a895eadd70ea8e3635bb70093da4a77a69b928fc06c81fcaca2b1025fd4a11e97e55a915a1c6aaece4f97119e9010001	\\xf4bc5fcb5dbf9c3eb73d75d18d84c5af4270c3adf47943ef14cf92b3f990cf38eac9ffc0abae1403c7b771b9f7671bfafc0aa5a3681666a729bd732885d5cf01	1652692310000000	1653297110000000	1716369110000000	1810977110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
360	\\x5f3f643d49cfdd87905e7d167868f0efd8cebf221034d369e06e0c51d7dad5a2552d11086715439f308b2ace4b005e9954aeb705664625780362ca5ea07c6072	1	0	\\x000000010000000000800003c01e3b7a778cc4ef494402a8a940b8131aa17ce4336b2b4178209ea37686a795421bef3320a0a3d4aacc7e1a4143ccc7dd439b890349760d870edc23ecc6d90d7b78c733d5a210d33869014af37b3e0e68fb3bd9382bfdc00a5a823b82ab731435f4a6e89b3ede238784710b310896e8424ec9d29c28782d023c116a0fdad793010001	\\x052bba89d4eda21d1106c1efab5d0ea5e48706b0a78a205601e4af28c54d588f3b3f74044afe63d89cff11a350fd8dcdb3217e10330e13111d3ed1d0af400e05	1649065310000000	1649670110000000	1712742110000000	1807350110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
361	\\x652f54a139247774793274fd60ccb04f1465428cb88393c642ab90cd9b32d7732920bc6c0c4e53f4a07cfadd3b9a9390b93de89644abfdc956893fe5434487c1	1	0	\\x000000010000000000800003db889f93572e4a55d3a31f96b6026c9534b8a7b9c5f2460424975a15efb03080943e39e4c4ae4ac6041c0c89edb2e08787112d310fb74366f3191f5f4fa7531163b97e4eb0c25513b3ca17b6c6b9af8c74587111596128b4e318c77d778044b6baa97525fbbd82f132f0a46b5919f0e5af70f84b306570dc09f06c45b035cb25010001	\\xda0e28dbcb7025f5c45d8a9fc5cb39bdd483fdcd8f9800ab7af90f7b7ec6a8c60c3f98ce86ee6898b89e21f3a206614033b2f67060a58416deaa97dfb656fc0d	1661155310000000	1661760110000000	1724832110000000	1819440110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
362	\\x6b9f04f9b1d3101e299370df0081690b0c84bd4943d5ddb3fa795904f8b1bc4dd1da47518776e773b6bbe21856df0dc08d497da75cb0bcc5d35c3944b512dd79	1	0	\\x000000010000000000800003a23ff5bc688362fb5ba739aef832025d419ae1c5abd6d33c945fe7d69a53124b192f5d9d9e6c8017c9d7cad57b017378c8cc393d33e8826cf24cf43559d5058c24d7d4674967aab361dc081f675a59e13ee0455ce97daa74f789abd13bb31c22c1d535014740724f5092c3060ad19825fd2b30b2d5fa1bb9e2f4d60b20ccf2b5010001	\\x73421c6edfd91cd8d1f58d85b10c252fd12dfad81682c7bb0863846ee56f05a36efa9493e17bc66347c93c669da1000c3356dba4b0377e4fcb8d6bb25bdd9a09	1647251810000000	1647856610000000	1710928610000000	1805536610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
363	\\x6e779d4822541dca978eac50ee91aad924d605ba3fc156cc48573beb91436841784e2c11e6e0fd4adb986555a832428ba6f3def02acf8bda6f6f1a95af86c5cd	1	0	\\x000000010000000000800003f2637e7100f47d90071e7ed7dbd10f5fdebae0b1fcf8d413904ee65c34c3ccdd904633fb0a33b239bf76c900cb09c1d20dfe8e62da92f9b5d0a42217fc8ac365082107c4827dd3682c27562446720d1f60c9d8464c262099a4e5e1fc02d3264722bcb6a494976077a95179749b20917e1e1f4780d8a209068f6512cbaf336b11010001	\\x4e84867771e341f840b86d1a78a231a14b7cd3cab68ba7dbcddf76560bbcd6e80c71ac95b85c7bca9ae81aa0b200df159e126f4789a5556b535c7b7cf733bb0b	1652087810000000	1652692610000000	1715764610000000	1810372610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
364	\\x71ab9f06ca7e7acfc3f998ac348a8e312e24c78b8439d2f34c855b8d5e173210b9c73235db88c109f0b8bc00669abb0018848fd91e162ae3fc322d8384142d16	1	0	\\x000000010000000000800003e7cd209cda2c7036ded932987210fd3b4769aaf21357799be21c06fcf46a49c904fa560f687b3f78e2d5431edde07293fe323c8ccc39dbb15362df70eeb0ef9307a7781d249a73d2761cb4b7c8ddbed8be77ea782a442d9e89e3a23ee69e613f2bf7441b2c9a52a2182c97113f9cb6bffec465ecf7e56b77b912aaf1ce5db4a9010001	\\x26af9298c5d112352263b31c68539cde8830713428584f601423783f898f1c5e43a09b0c0cf3e222ec05eb8c90190cf9d526d84f7465dfe5793556283952d008	1649065310000000	1649670110000000	1712742110000000	1807350110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
365	\\x76bf7042eb960bc039f3c31941fa27d33d6900cf80515e940368cafb464962ad5d3196c7d1bf94430ab465298731ecbd6c82be3faa80aeb15f2fb3e9c27afe0a	1	0	\\x000000010000000000800003b510d4151cbe039c25bb8e8301291fcac2e6ba0b78ca2d0d412a02634a73eba205741b9dd52b60f7b0105ca3ab55543ab2caa83d447eb7a7c12a566748eccede9589bc80df8af38bf50be355920ee01f822b1c2e406612f9c2f8c8e62deccfa01ac068e29583103717306042a03fbf3c3d21f9098712e91f0ddc60d988141b87010001	\\xf45c459c560ded84ddb9c5b9231a4f3a203abc2ce6b66afe890b054c74330d95e0149502ae12f17761af7aa05f95e3a4b483e7bea97f8742bbf5b25721eff60d	1667200310000000	1667805110000000	1730877110000000	1825485110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
366	\\x76270125022723546de366b6674f1f57eb222fd02968c8882acb14df495d1910b099639ec855209ef7fdea762986830f39047f7dca6183c5089616d87631bf56	1	0	\\x000000010000000000800003c0c60210b14f23f1090ce20ef9a4333dd66f3e898d6d00b4623a59319e89ff44d4410163469cca06044d9fc52d2268cf68585c53a77accc80c8c10ee27f4cbed9abbe22724268f6fd12288ea0805a113be2c9a9f50d819c869c7b41493b468a2eabb4d4d7c5c286d41cbf6246e10ac47900e320752d97b547fb90c26fec125cb010001	\\x022c6484223532372688c8927716fa1aa8fb58ec6a98a84ed9c7c31c4eb7c382de4ab5885785a50d6eb4b38591ca031bde1b973a27c47aa283484638d7048905	1650274310000000	1650879110000000	1713951110000000	1808559110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
367	\\x777b991b7f6ff0f79f972d859c57b924730506d256b3030fa3f2ed73f3e2e44f713bc90104361a90a1bb5c522e3bc33febdb8bc0711fed15f92b9105584f2246	1	0	\\x000000010000000000800003bf19a3e70a697c636b4d6f80dcfc85783c6bae1ea7305ab210d59efac6dc78dcf07ff619788f962606e1fc4cb84ad778f6e7c639980414b09cfb7b887d1af0b8a37d96eb2d28660a3446ba94fa7e5fe88ffece572099c03b3621c23d8cbb85f12c22c2574e929bb667c08c2f500dcae8a359dfb99eac20e5b42d732c4640e953010001	\\x851650513529de9ff1a312797a08dcb197cc21d287db16a5cae9e294b60671dd60ad002cc0927316f1610906ab049c200d89007ede641171f7676d5896d47905	1669013810000000	1669618610000000	1732690610000000	1827298610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
368	\\x78e33d45acf30af65f1b14f15e35cf8b69c05cf5f241f8223b35965817a102862a3c9e38b480dc0695d7b0e5cbddd62e30bc113b63a51a24eb65492219dad760	1	0	\\x000000010000000000800003c33ebc145958d3f686abe345dfe1314db882c602e157aba8cafa76bdf69035d19b5a80ddeece0bd93e1694ac4a06b4f2b07a987846633e95d8b8cef7d92e2f97ec6818f49807e5045da0799d9d720a1b0da245d26866f94fcebb0f31b8c2cd88f85d996f6fe6ba942a8fde9856530691966582990d4c11d0dafe40336eacec5d010001	\\x63b53a1141c65ad23ca59961debcc9dbaf800f917be1930b2f267454f9423fc34a75d2b438c84d4d1bb2d4bb31b2008802d6884e8ec05b802ffd085b9f58800c	1654505810000000	1655110610000000	1718182610000000	1812790610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
369	\\x784f91858c76353ecff363dc958b831355145474133788b5f00a606fda13b30b5f6720da1209e2fa091fcdec195f50eed1e1a095071ccc985d496a84b4145340	1	0	\\x000000010000000000800003a03796b2e1e14819cf888359938353cf64efb9ec04a6aa01a14e281cfeef3e28e2954f201f90d77f5bef20f688279baf14dd1faf53cfec8ba6cc6556fcbf6ee86276a1deeede9e2e7948753efd7123c810fb7b27e2b00d4eb7c0b94b1aa579aefe0cbdf41ad3034fac2f6414539cde8037e11dc36371268339cf14503484abb3010001	\\x1958157e9d575e6c76ed27922b23f8e83eef184dc87dfda2e4d2f38d87c10b6c2802ba55c0d81769b29b3389a0f44f35a250762b71781a4b2f6985726f1e8d02	1652087810000000	1652692610000000	1715764610000000	1810372610000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
370	\\x79ebae6dda52da690d58fc87f415f787a2d907aff1f762413fea957f92797fabba7ebfac226ce0c08a0fbb81348c9b4023d264a625197db04254c0530ba35e5c	1	0	\\x000000010000000000800003a64e7697905b6e3e838192537186176ce88c8d808b099dbf5578110f46a914eb4e3ef5c66f671fb6b6ebcbe06f6bd92eb455e4539630af73a4bbb97148afec7d40a27bec5429d85e5c987057132ceb63b5a3901ff91ec000390259707bf2e7685b7e6899e0b76f90be31b7d994ed2432a2a94db5f64e99372c2b4d6a2d1e93b3010001	\\x4edf9e1a626f98b6ba3263ca3fb0f809a604efc8f2ef90354f81e8de1d2cb6d27d5eb05cbe7bec9c7467d765971a1d8afa08bebd653e6d080956b85bed31890d	1667200310000000	1667805110000000	1730877110000000	1825485110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
371	\\x7dcf46be4e64966c26ae97cf557ce22dc0fc7cf1b2667626f34da912b7533d131c788792e1f366cc1a436bbb6ceb8c2f05f06ab05e353b213c728ccae79e6ed0	1	0	\\x00000001000000000080000399c7bede65ddcb817a89bc7f528d9640f6ac6bf0f741a9c234232b1850904264509898d905fa69d05f0bd89711b1636c14e565b59f1b5f75dbf47302ed582a575c5d7d9b59da28e6b4635c34274e9765fe68c44ac5db423c23100b517f4d57820892735afdb2e96dbde44f9eb0df9f34916c6db93b029f22d32086473e8c6557010001	\\x23ab5dabd1fabd15b9574b5c95a033c577a2e8eba9c0bffcd0c6d9e4d2537a6b7389dc70e932a12a5185f827a5f081357aeadc6befe9a9810302756e9a8dae0c	1665991310000000	1666596110000000	1729668110000000	1824276110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
372	\\x7d3fed996a8528fde261766d2697ad035e4b347ee9ff83b95b2ee87b735c25846ff8732eaddaa1874caf9b5d3aab125d2dd384de0a7e8d2867e2c101b1ce294b	1	0	\\x000000010000000000800003ba4ebbfc0e13dc1c8b8271f33c58aa51959ab3cef847ada10911841a4101b3224aa24711c8e2e23cd11a0cf476d7b0db9c9b4c12f17d0bba18740e8884fd9e24ceb36251c7f5352f70c60394c6c801c5042e8c25f3e51c61ef9147d5570ade859aa4e6caa43ebd89d47d618dafa0a903bcd6716367202f1ead97976473e22acb010001	\\xef4f1516db676bc96fe8f4eb5b60136575fce7027075fbc5087ac36775f279c3755a819a358cce3039207b867eee66b2ed469a0bba7f6fb475569cfd74d98500	1666595810000000	1667200610000000	1730272610000000	1824880610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
373	\\x81fb172ef5d5fadf0703de5ce8b2268a4142fdf6e3a3250df6e1b98c46b906c6fda37547d6806dd1620bcd7f0bf5625cd53ede6b8cc9f036b72a13b5a5471991	1	0	\\x000000010000000000800003c0dfa3e4fa94dfe2f53035ec32745bf171fe3e6019e48bb2ad2910e607abc74bc3c03e0bccc8c02256f959ef3563bc4223166f20267e35ef5ae7e18dd9244bcc9b4a5f0e258cba668efa9ec3a0d0ae6766acf813bd2255afa0d042643ed66941ae4c9d759b1fbe0394b089838aa21b4023f301c2dcea56622077ce4a40df4105010001	\\xa53ecf4b0f8bf186af6d6ef6a383aa65abef8de68ecedfd7ffcc47e4bcfabea68e73cf6c2404149638f9bb82d6c5d530b15089578193add5464c888a89ed7600	1659341810000000	1659946610000000	1723018610000000	1817626610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
374	\\x8133d211c0fa7aa3a9fd87ac759f3b6a098fdf012f89181bdee147bb5238c64cab97d232c2b17c68723ff49c1a3fa71eada8f8f2c707aba0b9737b05ac53539e	1	0	\\x000000010000000000800003ba2c2e132671baa89486f245a2b3a066420bad8f8115b82fbbacfe6c2e5623202ddb099f4e885d41af0dd774ab93ee18059265b5edb99ebabcedaa484629298aca0ef54e8fb541a778d63e81c29424cc0fcc4dfc7508d576252f5b171c3e7471bbaef7e33cf1a0dc35b55158dd5d2e487194d7229c528fd299580a298c2b19b7010001	\\x0f1854d4174472855a6a5562f7baef1e7cf0eafe008a93749d9c9c26e2f71a4097517f4139636dfb954c499e3b14cf1c62347f57d27eed07839a07b8708c2c0d	1653901310000000	1654506110000000	1717578110000000	1812186110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
375	\\x822beb62d3155af8ebaee5e590ec38488bdda250d7450acb653b7a6f4fff536a6ac84a6d54bf8e13f9b46fa0260f70186e65cef8bad350b14531667f5acb4b4d	1	0	\\x000000010000000000800003c8bc1b251160287871c7ed55250a972bc2637166151e32be37dffbb785e97e76be992e79ce110ccc02ef36734c560bd68f990f14d6640610eca968c9f553ed00ffb06a6a9ba2f621c12aaede4fa795bcac151b2068377b94774a52027f7b1338886182c22b2a7a21de0989761466ee29f60e5b83937b7f07b1a6a927d3f38b5d010001	\\xd24301a338ed430def6c70dc7df94617f106ef56c8c11deff27f06d8d74ffc6013989026d4d4044e91ea609ed8f3dcc261243c32cc3ee0aa061bcd9c8a710905	1673849810000000	1674454610000000	1737526610000000	1832134610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
376	\\x827740e0a04a8a73827726152d7e3d98e95bacc39fc25f418db4a66ab637bc2e05ce2e59c1a306d6a55a07eecd60b7f9aab821f1518b37345bdd7c0e35f2d2ee	1	0	\\x000000010000000000800003ad9e233a42df734d450392d62b61c3da1e55fd78ff521e26008ac25886d07578fbe870bbfe71ae80b6a6234da135a739d200c289f2d401e4ce66597468bca90477ef409c4db4abb42f651ebc682c352132e26118840c24aac677b936c70be04ee2871446640c356186c538f9972a039684f002626d50fa7d8080825695ded443010001	\\x037d7b0836765c7c827a5dea3faff6caf91f3c095fdc64d12bfe3ca8803478a2b6c2e092e2fbb0d391b4e8847584e9086ea63cd3c7855c128672d66fb9086207	1656319310000000	1656924110000000	1719996110000000	1814604110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
377	\\x8627ddf96c9264cf952932802f67f532faa06fab4c5775429e7af5c67a0a5a0c6b9c570ecb37e821124bbcb804c9558e9584284359aafbe3e8286acfa4fc3725	1	0	\\x000000010000000000800003c375777c4ef6feaea1f0929d1828e66cdb932aaae8c0ddb161d35097857b1e0557031398303ebba2ae2b334069c7375baeef043132011de55c92e803b584c0dede80f9cf2ed33fa5aa9c3f9685c16d4e33595d793808a30d59c315e5d703eedc684427e389191fe4b4ebf7d506e6437e5797d3cb5bcbacae60b6cc819ff67be7010001	\\x3cc77d12ee662fd394a7c526cc3ea967db445061fcd328cb5eae87e756608906418268cc7465782560426c3dca7e028064756db2ca0a7d4fab9fa4996a926005	1654505810000000	1655110610000000	1718182610000000	1812790610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
378	\\x87672225afdc9f106991567a64476b50f5ac58d9c9004fa270a31efb3b46daa14214ec22e37461f6fd895f549e458405a503254817586ca311d04df1e815837f	1	0	\\x000000010000000000800003c43321332f1e03e1eac0baf77d8af410c681506269466b8cdf2f75155db3ebb92a57831a2343530404d0cfd851c5d2cdb5efe42854ec9afa7ee70d52b4e3a710b0bc4dca43d49ba976a4d830dc4e18da92e2d7ec99abc532b9bbcead7ceb0cdeaf1f80c44ae328e1e1bf8fd5f09b38056e56d1e7ab0b349a8a95ebd72726eb3b010001	\\x0efcdc7640aee574ae1c2fc4fcb0b2c84c83e3886b2c16341db57060763955a4134b80dc9958c7ee8bd3bd93fe83b29980f9c709c98140ade4af9f3debb4bb07	1653296810000000	1653901610000000	1716973610000000	1811581610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
379	\\x87c7678b4bdf4a39a67670ac44d9555827a43ece523944c534273e076c1b1146946ff791799b974c425997a30c776cd2a4d597cb5f7d14182e87358b2471c4e2	1	0	\\x000000010000000000800003b5d42e42ab366e40fb2e0ac3270334d7efa594f4cc516d680865f58ee7306a58448025ca4311c8aa3c33e90def10c26efa8ab516d549395d2558d417397b7933a54200d740edcbe40bef51f6af8672d7c792e2828c0ce0a9c647f90ae151693aa47c8a0f851267b2b2cb0565d63477443a83e9f4287e27a3c8b87a7524f374c7010001	\\x572900e84d67002c324fb1f0a4c2b7deb9dc191944d42052ac3022482666e3baad4933b20d7c509f8aea473cedd48b5344e1d1edb0afe0b402c9000e23ed4600	1676267810000000	1676872610000000	1739944610000000	1834552610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
380	\\x87e72c0a473d29c6684d3bd28b3240c0ea0f969b3780dd135d99a34e826a992bae7c9c849404e01719e0519f0c8a7d51309b50a4f15ef459d1dcddaa2da74f45	1	0	\\x000000010000000000800003c87e05da6a6f0136591c71eb01ec930448e1f4d508281035806eae1fcfa8e9bcedd42fdda50662a5c6cb9f179ec146d16cbf7c20fb64d3f1fbf6c2e1968191b8603239db9731f7ff124d620703af03396cf3fd4a6d64c6505be534fb10ca9f0bd669a21bad8c04eac6d6ba99ed3b0be513d3138b4fc1c6dcaff14b1e45e4550b010001	\\x322586888d28f75ac2ff0ef3ca566e61c55b2709d2f87e8c5e0672bc4bd4b64fec4efcd58004908efa647062d36127abb12053024f93b906816009e6a16ac904	1652087810000000	1652692610000000	1715764610000000	1810372610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
381	\\x8a1f704da126e0babe656af499da77cc72fd32cab81898cfdec9bbed5f63882431173410295e7620c3c54a77625fea46f9345aff51e537141967abbd32d1d75e	1	0	\\x000000010000000000800003cea04a2d54e34bdd4e687e34a5cad12bd2597ec566e1742aae13bc2d4346125e2d58c9ff15f87096478c1857e4513b9aaff3b0320ad2379caaebe2d53de187cf74101c601f321f49c75fa4bff1a402b8dff6520b911e1dabb7760de02dff9f8e8a6917f2c61c5afda79effebaa14fc3a363d31fad34fe21355a07c5d7950f953010001	\\x80a65b34a1b83ace1306b8f6c8cdb61c5253eed394ffde6849bffd706a08fafcfddc3c233ef69846170ed67c2bda50cced6b2c14fe039da2c4f89b77be2a8507	1675663310000000	1676268110000000	1739340110000000	1833948110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
382	\\x8d37e9e1cb7190b6aa99563ac20bf8328fe72e45f0215a6f4560aa16d7c8633d7c09000a019a33c488c446edd57c0b30e22d8f5502a7dfa5da2d36e22b514b61	1	0	\\x000000010000000000800003aecddee0b8f4519444203c7b0dc6d8d2afceff9bdda9de19e7f319faf672052f86d9b738beb4bd5005def1a372f851e4a47b74bf96bb336f0ab88e79bd651bcc1a7fa1d9ecac1e83829a216aea056483392b06b44b764a8e078121e3ca033887f862599e267fdfcde30e0721e1b53e649d92f7b024cf4f9ddbc87d53a76f1293010001	\\x4b76a33aa7d6cf7f04cf232c8ae9aa1ed0983f22c465094a72fca3cfbe85a020b847281c7cb7557e8c2716846b33ec0fde980c2c04462639411370fe34036b0e	1658132810000000	1658737610000000	1721809610000000	1816417610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
383	\\x8ec3d6c9bfb816a48e680ce25bba35974a53eafe0af7970d861271a31591af24234c4551a6e3e7405bfa1608f1bf58d48d0e1fd0de7f84b800875c46fa2dc4b2	1	0	\\x000000010000000000800003a3ec7500e4732f59c7971bfad2187a81ce6e05dd81ac24724b228df09f331e68403e43752280b8c9cad4192fca1d7ea58440fedc596ce071aebb0e73930451f541ea76d062ee9357625769cdb227f270055752a95f286f59127013b7d1ffb7f97dabd9e169da525fa4318510308aa51ef2cef50b5745f98c617f87d00ea53ffb010001	\\xbe3eb971b0e011d108a092890b243a5efb696a6ecbbe22d64a5f1d948c6116ba002339e7904d6cff89b52434ca6c45806c9a634c6f60f1ee084b5e08522f5f01	1672036310000000	1672641110000000	1735713110000000	1830321110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
384	\\x914b5af016a2ee06efa8c0a2984f4c66a07fcd3fe76b9221ca1e4d7e5cbe9a35dbeccd27eedebeddd319daff884a26e30a8e157088be887a75e01981572ed3c3	1	0	\\x000000010000000000800003d6db0da069803b2382afd630a13aacc2068363a4c3691434e4f25838998e082545769a395f0cfdcc2cef3cebb4342f229ba5c953efb0b1a95d7b7d113b31bfa9b648dd061f45ca0db17607094da2e9ca23724655b035f4f8508c616cc4d87d8d6d0acd53da2871f4e4c80a329063c619297af21324a66c3735b1c50f81803aed010001	\\xe74d2cda2fe1992cbb50bc4240645ccbb5c1b5a1b50519e0538888c17c945641b49a3dbc82877d5231b78340ca682cc3bec74636947efe4ab7a4b3b8263b0f05	1658132810000000	1658737610000000	1721809610000000	1816417610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
385	\\x93cb427db79a954ba4919e0d34e8749df8a34a7cae55972750a8e84199ea7b68da011573ee9e72d848171237e9092da2a530313cde3618be9383345388a4ce2f	1	0	\\x000000010000000000800003dbf059b93d47df6d930528e3bba6624c784b1d56e98a458addfc6d3b3c45f4ea79292615998f5a9189a9886e2db45fdde2f3969cf3ef46760a97fff61faa067d30fa11e92f605427c357f26cc2c523669e29594b8f51c6bf7a9dca5ea0fa3d1bc69d3b593ee105b95d8d2da3743e4dfec883b0c7c77e7a469e84c29e7bae67f1010001	\\x7663a26fb8e92e448296c6dad4ed5c47e91c539a56401f298beb02314dfa596895587870d7473effcafda906f603b4fe56053c6e5eb92749049c8f2991f9110c	1653901310000000	1654506110000000	1717578110000000	1812186110000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
386	\\x940349ad18cfef5d0b7c4666fa3d48499e1fc03bcfe7bfe0c16056342bdd57c706ef683898e4a7d5b4db1cfbd0189f511139cad2f020b8cab639759619add2d4	1	0	\\x0000000100000000008000039b381fb00630ccae0f0f4585c9c9ff51d5ec6d63562db8199629ae8db80481db455449948ea98923685ae483f7003b175a4596fcef0e7f32c1621b5963d6219a0cfe1b0811fe4ee6aaf0cfd8654ceb4b20a43aa8890f9698d7b40729743ed98fb7a250557f33081371fda388d8b345e7d04f45168a4672f75c4a29507df8688f010001	\\xe982a04ca226643b309a6c3676e7f08ce4eea0661f204c898718d3cdd8c2bf09579114b05510f32f64ec6993a41cc0a0b14c2db0de49b191eb6c4dbc4706b909	1671431810000000	1672036610000000	1735108610000000	1829716610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
387	\\x96575af8a856731e664e91a1779cc71ee26bc1fa256286d3cd5059097d1dc46153eca52cbe416bc1bc0a85512b2ffc280a6c8dc98e01d6f2ddf1bff2d5f8579a	1	0	\\x000000010000000000800003b6f7abef25617a1855845a8de5ef836a39d7f57cb21682c9a527cf3ee5a53e446bb30c4ef8cb24f91829e2eae6a132f8582966c722e29552c9382768f66bd3292121c8fafcd5c585c50348f13de52365b49bebb2d4f9f880041765dfbf2184462bc5fedd716252f19e2f48eaa62de9ee07ddd09e128ad2113d2143c6aa10937b010001	\\xc549553ce1c11ec38f4a4a081d9d30344fdcad6b57f9aa33e58be0ca1b7029b280c41ba370816a0178b733fedab84351f6ac7951467adfe40eae78eea8eb3707	1655110310000000	1655715110000000	1718787110000000	1813395110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
388	\\x99e70f77621407961ddf2d7ced2144e24cf2565530e1fe0cb470484e80891ee223d958b9c1044e47955d39d3b9af0448ed8feda2ba134cf2cf1082d0c6edd60e	1	0	\\x000000010000000000800003c9e4e002d8530d1729045e3c1e54be5d42c3d2e8c6026eac21ae392e66e50de43d3ee49381a5a0a379ab78c52f05d5f8237437d25ab56ec9847ab3c5b4c07b6401ce95adacdc4a97dc2ae7779ae3dce06caf3338d306ed6dd82528c65de9431d5876ebdc0aa058dd702fe15e880c714245c4218b7ab9920069a2cfc04bff4e39010001	\\xec717edd88349ebfe77406f48ec521c3b813044caf4abeebdd2eb4bb37a4cf927873482dda97394a08c42b2feca0e014d723cd1be22a70a28f834579343e7b03	1659341810000000	1659946610000000	1723018610000000	1817626610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
389	\\x9c030e7fd83939767d4a5ea2be92b2ac5353e4012dd59e3e93c85f4db287d8a1567141621beb1d8a1476db8c0e6e26e96d370ad7577ce059a440adc02d73c729	1	0	\\x000000010000000000800003c1f6f8413828541687d225b3b1fc8b2553628c58fed84df9a8e68f7962acf4c40b474eb0ca67ddc3bc7611cec64c49bf2f35cea90fa681dcba1d94e48eb64da9859e07c415310527731e7445b15fbc02767ea378692a7b3beef436be48a221ef6f5d4c0c850529acf0abf935d9588400f623e98c5d8ec0ed34cf26c329365329010001	\\x69df2a2d4c7946809c085a2d8cf45387842503495ebec2ebe52ff85939fb5e1672c1fb47794d31f6686d96c814d45c98224072910f6f423719b11d3d16c70a0b	1661759810000000	1662364610000000	1725436610000000	1820044610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
390	\\x9cf3bff57c0eb9be82cfbcb4c63da7ccff56dcca0974e7dff95262a7e8c65ad9aa947e62b16189cd86fc0fa18b4a48a85347b59d3cd4760e86739f8c27b0c73b	1	0	\\x000000010000000000800003c72826c476ac152f4c8ebda734f1ec2218fd5577e6093e9aa2e282c3ca9f7e2f9fa728a07db3fe93a111f1dee2249d267aa14cd4c0a475e79509d5f5fd75c1c1299e4ba4bea41fc2db09c1be41093258a597e32ca01014cadd36a8a53b4df0841037bff519d7aa4fd4b2b619636993532628b969448db0bdf9e3987114768ffd010001	\\x8b5bac7b01aa4cbb5b2453808edbdda4bebe9c22b0005ca73ba6faa0629cda8f0fdb42c0280cbcda6895fb1dca4433353c05a258840edb767f8e8ee525e7ef05	1657528310000000	1658133110000000	1721205110000000	1815813110000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
391	\\x9c472b298370965c7c02ee1cac61112d5e0a4feaf44c0df17ef92376008215b0b890e47511e1289199328c1823cd35cd447e50fda460cd812af3944c1f4313e7	1	0	\\x000000010000000000800003c12489a03e1fe1c98e8b818ba75a393c57b42ac1b096fd4972fe417ba0ec2bec686ca072e98f5e77b137114757f62f9535270bcd018fa42e942a89c94bb5431e881932ab62df95e078e05db789bc1a89e1edc544260bc7d65f07e57503a0912c20579c1d09403e1b902af2da6450bbe698902d096d93f01338f5999be177099f010001	\\xb0fc5fc3284a22a0777821a2ae964334e9137184869db4f3b5f494d90e7f6e4b9c0aa64dbc09b0c3a84cbada950b0c63fbf9936ac13ae6f809723a90ea15db07	1670827310000000	1671432110000000	1734504110000000	1829112110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
392	\\x9ef31c69c7e46f2a6e4d58364d32afdc07b25a546035e50cbeeb02953f95ce4ed54c1932d0011034e232108fcb127e01327c256e9bd9c62a17a60672ecd8a6f4	1	0	\\x000000010000000000800003b963d2dec35a227b35fcb4752086b43914ecdffae327a6bc3d6dc4dafd0ebc564583031f19b528ba51eaf3e1432ca64b6cc687bb30fbde55180feb4f7ccaea2819898cfa2216a73e6abf1da4b3b003c729c91c1f411d8b677de6aa56746435296bccd048daf83683fe219805462a42a92ae26166758249f1c54e03114bcb6515010001	\\x497fa628466c8ce84f46c15fe96133814067bddcb7e93ff0131805a8a06c46eeb837f5f1bb64d2f0d9d15e56a90f62544db2074813b751e2e5b1f8291fa0920e	1670222810000000	1670827610000000	1733899610000000	1828507610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
393	\\xa1d3f47107d2be2b7464b665781b77672d3828a11b69b532ded6ad53ff0212ff42c3b65e881e505e6db9996a1132de3a0ca1d1160a2b63ee3d6576bd466a95df	1	0	\\x000000010000000000800003e7db322278d883200f0e28e5df22f4885edf597e6fab627f568ed1d6c15f2c8fe7ffc14ab739538f5e826bfca027402855c263de01ea2ae679f6130dff2d4d41cf6529bb96532227422511c6b9ca2e8e52170e2053a181269a4904e721c07eb17b736de85ac2ffc736366e4c974b3d5b8cffb65d837c78ae5999b8109094299d010001	\\x3276a7035249ee0406f0ee9ef6c8dc13173f07f2f520501cc21d811640ef9b06523875f4d530ae743f97bb7bfc78becf8833a2e75be3abab6d96a50f7f979202	1671431810000000	1672036610000000	1735108610000000	1829716610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
394	\\xa30b3e387176e9fbdd2d14a197761585fad4ad8c53e778fc1af521fcb6bd1c6d13ce2494eff532cb907958e09728d331c451146a124936baba511c583ca49b22	1	0	\\x000000010000000000800003df5ff66d8eae9f6823026003afc9c37fdabb638543364102c76d03cc167ded8803a44e2332f9ad0e499646c83c21a95e6e542809e161f6c44ded6fe5242c8cd9a83de154bb6e15edac3844d9c4432091e83c2c1f1104015c665902eb5056486dd48baa2f48d1c5b282ebbb331238916a3af51b4a0e3b54bfbd7b64631ea559c9010001	\\x1451150d182acca7a97c707973abfced2de3561ced6ac4ae33a0904ecbc6050f73d7bc4982418dabc1f3185cd70bd1e7a145e7a553763a376e5464aa8c3b5100	1661759810000000	1662364610000000	1725436610000000	1820044610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
395	\\xa8873b6303bb6d02d05840054f064976a71d6189956050db379f3893d5fef5b8f5c3bbd8f59a998daad0b5127cd1b114856f1546faf3d3d332986d7ad91d5c3a	1	0	\\x000000010000000000800003a7997b14d2540860c48c1fb6ebc56a53687ab3845e642e51cc5ae7c6a50a5fd9aa06ebdcb966e223c2d3636a2a96acf337b19a4d97bb6de0029a4fa93dbf014981de9cc856f9b875749b9a1f524f8340662225b5265436ee0d89d97585a05d958267dd6f503430b819127fe2934af782073f11d2b256126cd40abc28889c2c63010001	\\x33f69b86d3f8d580f4c54fa98b3731edfdacb010b1ddbe22462b930df701a446b2f76260eb3f85d4d065999c21cd8caf9a93d37e797e936c14a2ef0fac92ec0c	1661759810000000	1662364610000000	1725436610000000	1820044610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
396	\\xa96739c0dec8041464322a09ee67c5637d52bf9cbec92a8067378d73e7b7847b47176e673e7b580ca60694d33cb1195d2d732026c14d0dd73fcdc9790ddec0b8	1	0	\\x000000010000000000800003caece6028f366090ce3d5c24eeb651c4bf615c2f7447617599ac20a11cfa3005417e68096dfd2b8b956ce036612899cc1edaaa2fbc6bd1ce0d3c91ad3060df25a493eb5e9666e4451ba93b35eccf571f87c8da091165e6acc9c620eaa0204f9302a63efd469240ed7c4055a7ea45f3b00883c35228d4a17e1fd9f3f0334be48d010001	\\xa3d6c6b404bd45336b6592e99cc73454d50b8fd9b5a6419b72326ee4c04f02d8f2201ee24abff3e7f31a3062f72dac71d7292d992678dffcecd13f378a1f820b	1672036310000000	1672641110000000	1735713110000000	1830321110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
397	\\xacbbdbd646bec4025a773e13fe9897d7a581be236f1da39be2a40ea4913ce03a7d43332ace928354d8f896d9684bf78273903f52e86f773ce682ec6efed35602	1	0	\\x0000000100000000008000039f4505610f2e4b815be694d93086cbb5560a0fa8896d22164829c126d0e05efe7e08641d66bdbfdbeda65148af4691e1786d9b7e079ace903a9eed7e43e631978631b541dc3ae55981213c317eda22dba5699bc588b656b1f1c812d2cbc67dfaffff7c3c8d44d03d969abe6936e90837291e827e0d5f90e859ae7a9ad8c455d1010001	\\x2bbfd92130d5e35064618cb60a852b367aac067742b35a7d4e003edbadee2f6ec839dbb713efdb0c75fabebfeb0271e4b6e64df1ad64bc30481d23d5a136810f	1676872310000000	1677477110000000	1740549110000000	1835157110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
398	\\xacbb1477f9442f4a93f699bd1ffab681cf7e0fcef534555e43acb438afe3221457b933e44894cef0aff949bdd8315fa8cafa43490ee56665817f022a9390937a	1	0	\\x0000000100000000008000039a9151f9d209219beec7ac7f1802c32a88420d93cb8244facda8c3c07633b71a783ab0074a02ebfedd5d3d2032b829120b390b36975a3ad765273915cdd5b3bbaeeb6972e77f36dee02301e898c1b44843b34026dbf1325f9d85baefe0836bf87c3faffbdd0fb274fa9b1bc7c24ffa22223f6d7cda747a05d910cb9d2715395f010001	\\x0083bdecd04293065243a9e2b8c40fd0dbf9ccf6ab8e027e4aa715a913182bc6c435eb53c77702408f3d1aac7b47f096bac8cb1eacafb98d59c448c1168b4609	1657528310000000	1658133110000000	1721205110000000	1815813110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
399	\\xafe7b30431df0b34d57f4aaff2055c3dbd2658c18a23df3d51feeff4322b9880db9976938d0f15de551935b3e64feda78a609644422998bdeaf4347ae7f7765a	1	0	\\x000000010000000000800003d53e5e71767dd1ae6f235cc6e4a89faafee811b482ab0fccec083683539a4224c6574c01137e15158149df8147a0c93720f61b25a5cd6cb143662b6c24f7249f12089ee4cfb15b41db77a56c7078406542a5cb80d45f62a0a95d48fa098afa1fd7fbe0cdd9f2da9896d00e56390b6146f4d56591148ef4eb7b231227e14dfc2f010001	\\x6f7ef24f6a7d23222e6d36d4ffa18086c0c1c6cb3be21cd4b825fb4bed3b1296a173d9fd16ada87a1d91e0d49182902bb424a8089500a6ad4349b3815d59600f	1648460810000000	1649065610000000	1712137610000000	1806745610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
400	\\xb3e7d63a81adca3d2f837833ea1a3cdfcdce8177d7cd587a9d55dae81995a1d6a4f45913da364ac1ebf2324c49efde7a91b7967d78250494d1c156edd2f7e812	1	0	\\x000000010000000000800003e7441bde439bc757ae6b93392e0f6a026af24abea5ee38f705fbe7c5ec9b59a291715721f845f00c0142224cb28f95a909352456d376fefcc36771261da1b95bff99efcce18e13bef20f160c188de0c635af6153874c91f597032ea14deaf166f80f00dd833edfe50b4127429545f4f48bef2c5affb06ecafac15b8328f9c36d010001	\\x1e9f37e656e87ad1ad022484c7e7799e9c5dbd2ed1deeae4879ea8c87dedc512d8e0f269efe3c7d06044d2e755f3a43cd6fcafeb1286aa12f99de90d1483fb07	1670827310000000	1671432110000000	1734504110000000	1829112110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
401	\\xb4b3666c7939438aa9f3a75abe08d348754fcb81fbf3ea88613ba2bfb889d510b56186d902e3a5cf3948e9c05966deca7e31b6cdcd2c48a5d91f513785489fa9	1	0	\\x000000010000000000800003ca3c1d0040bd57f5871c858f0c1a56c83f50c89849bc61b2afb9807ceeb82ae643a469058db370e7a51ab10aa1bfa359cc8b4ab8c01cb23fb257b2ac68661612478534433b2c38465635d8afd2c9cc133335659b371e73ddf110bbc292f767d794f88b21017747a4f2d6d0e53b389a8741b301e27a855a493b7ce2e8984f62fb010001	\\x064ced1a4c109808fbfc119aaca6b7c78d19314524f7c2e713f16b36ccf4b8a0e7330a6d901702c860968525df17ea0513a728f63947d473e2e4025ccfffd709	1656923810000000	1657528610000000	1720600610000000	1815208610000000	2	0	0	3000000	0	3000000	0	4000000	0	2000000
402	\\xb46b4651d24652fa5b6e44bb3f27587f9a7937e047b4fc4fecb9fb22e0d76a24ab3a958365502c5f9c9d517de57289d3b914067870c5f2e5d8c7b748fafa728c	1	0	\\x000000010000000000800003936e5bae845dd7aaa0fea7bc4aa963bac9d5c1972cfe063ac3954785b35e11132fcd6abc3757b257e3efd111243c0c0d71c69687c47802816d37b04853d3e474a1cd618b83406fee763c6aeb6a3f5bb86e8aec98f0a639cfc86ac65ad19dead119739e1d94a6784e0a845715783f04ced61a14f8ef160a45ce05b5cb7a8b9407010001	\\x8ab8a459878d0ab8c8ecb4f23d8b3f477a72ac13fde0eff49ac24b9fe1a7af040ac57bccbf293a2a2b5b6597eef2d2e12ea3f67f2be880d43ac0b16e2b419f0a	1668409310000000	1669014110000000	1732086110000000	1826694110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
403	\\xb7237d76f1cfba475547bfd7eee5db953f01e4718acfd7c805b9bbd0990fd47207bd692479cccbd2e5f41fa9970b6d599a17e4295b07475d686e88878b229972	1	0	\\x000000010000000000800003ef76e300e957624248578e793e08bd877c9a8f64fb76d66f4e82854e6ab4086e66727b7b5302fe488ba1d07acbc493e385a3959322c80eed1c774495a1456ed92c71520c9bf17fa4b6f049dfa7f5e15a92b0bd9b49e67d5c91c122125e0face9a977f6b4ad13d914fd0ba0b76a48c2772fdb8565d3fbdc5fa2f69b3beef50da3010001	\\xb26a128c2ff81bbc96d817764a0898cce7821bdf8ac1f477feccc907f9c40d4af21fc3d1f8536f113670f57d63495c2c99f1afed3ca1910d208b5c3e974c4b0e	1669618310000000	1670223110000000	1733295110000000	1827903110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
404	\\xb91b749939db98208b8640327f554cac13f30fdd5d7982a71ed1555a3b7a76431d6b8299b8ee808a2682fdfe973d13c77ae354e56f66a6d14b1e961b6ff0fbed	1	0	\\x000000010000000000800003f2eeb85e4027ac626dcd8270f4de19da359dbbf890d821f2ed801cca8d42ce4129b9efe59e5b062ce0003eb8f4308c6a655ee224e65918158282096ebfec96a5cb1dad531923d2f9247a674b0a6e8aab93bc4d3e8c5a01177cdfe3f814caef6f35e79ec38624b016a62c136d9a6acc3c2a5442e7b24c05f29aef4679ecf81811010001	\\x3378f50917ce2329e0306c613e82c81a1a0cbe2de90fd14d54876fcc1c6b143f11709e3b92162f1a7be20a0e6c511483d60ce4a9ec58fef706ab245acafc4307	1676872310000000	1677477110000000	1740549110000000	1835157110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
405	\\xba8fd4b4db111159a8cea9c157f255e4bc283a787a4c7fca15dc2b711e9920a83f64bf6f7f9ffc425b94245f8973106d135b725d15170d2f9fc5f8fee2e47fa0	1	0	\\x000000010000000000800003ad11de440eae6bd9d3478810e5303376ce1bbe2b19451890fed21995692a5cb6643efc832265d63c02e7723853f5429e499c8feac4201e66c7b2e3b0c07998ae95d6bfa398ea0127f7cffcb0580104dc0792f02a184c3734b741e89e4a2d17dc9fd40d940e6878a0c9e0e182c1fed1fd066ecd3d10add1f3a292eb9565040579010001	\\x0aa3aa69ffe7e3d9dfa4eeea79289c5bb8cbf2facb14cbbd9c2188d148656cfef110e3b2cb631b9dcc8a769f90c26274fc05b3914d7a8f303a68ebfd41808809	1677476810000000	1678081610000000	1741153610000000	1835761610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
406	\\xbddfc6510c93c29217671fa56ebda128e9213f28202650b0fadea73aa0aeede6186c733649865429176c38b205d3eb1f053bd4c42ae3392598e5fbf337b59af4	1	0	\\x000000010000000000800003b176c461a03ce2920d2d8f6ec10801b5826c9233f54d7c06c52e3b95056587abcb748f2779fa4be6f3e79a0567691746f8e0d18c0f7dae6c6511a1cef01479bbcea33b80914af2b487c38d3f075871814db4e403567f1d10e7c98aeaeb9f5d78b9a6f4fd7a67c7680ef3a94a3298e21f1939ee243d01da36320d64f06a334d13010001	\\x9f58d68f108c9f50505889a593a2b08769f32b95128b05ac17b17f75c8ec60953d2467019b9492829a90b1e446207a25455bbec48d5f3fbdc21509d8f725d104	1673245310000000	1673850110000000	1736922110000000	1831530110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
407	\\xbd47a03e36013673d9b00fe404323bd27ef1741167f9a2bf5163fd6e3b93bdbc032bef23e465c89749ece3c4d381ac14de247d563087ffb38e6ffb53bc77bdc2	1	0	\\x000000010000000000800003bdd3b66b66c335f623585ca004d966902b9313f897bdb8bd6591a192582b36602975da22a70034b105bd3829b56dcfa0dc0290a8c5aac985581c5d4721f75daa3df17a06e4c9d75795e6ee9cf3acb0a1f164e4800b53fc95d7137e43fdad4f7bb85fc455f60e5b42f05e1e511e1bc46931dfeacfb3475143c3530506d41bf46b010001	\\xbe2f9a09be1192c3656afedfe2e824af0f9916f91321a6db341544df13cc8b44e5cb72534753e39add39ea5e9d4d40466fa47615f45d8deff637a4432394b305	1667804810000000	1668409610000000	1731481610000000	1826089610000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
408	\\xc8cb539c20a101e840c22456fd52c24ba0c592800036f508a16918447b8fcc9a13bb782d37bde535affe9e984674d5e0da90fce90bacdce503413f3c6b68f709	1	0	\\x000000010000000000800003c21d4a6dad7688a6a14237fbf6ae5cc42a139b0be5a5dac620f72aafd02b6d8ff2edc8271914afd11af6606094c08337d0b83f0b6baf878f45993da64bb11ab633a927d521074c1f64d0424c31a9a1beefe3eb8f1705a8c5562f537f5ab653ce29d3142f7f1f20ef5b01095168271971d5c2faf23959b92e2dc4717e3728184f010001	\\x3f34cf63eeaead963e021c41ec5c3ad0453010f2a81e219ef7e8f7506719f38252319b3ece7ade08499e6300d0a91a61fbfa565cf5d24a21dfb83b996d52ef0d	1646647310000000	1647252110000000	1710324110000000	1804932110000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
409	\\xc9fb1db365bfdfddcc0236fcd2e75886afadf7af5e142bf15282e5773e10b66471024e84f8ea60ddfa07c33a3303bf2eb779c412536c7cbefe6eb12153d47142	1	0	\\x000000010000000000800003ca2bb746c9fe00d661ae01699b2f4fc5bf683cdf33429421354738f09759124f2d9011a98b4905313bce29b8fb1a9d39a50b99df6d8a7543fff944b30e7391f35c8f6bf80a4486d0e96155afe5b1200aa6699718cf4d242845f132da950c20cd399a2c09fbb4ed5dda3ffeb93a2104765d8506c42a87432df08a04aa369b62e5010001	\\x5640130da06111ee9cfc10a694a8df8e0d86398d74ba51efe33639bfa73099810a7d32f30227d489d7f81e23db6530590015af6020973c8ae9674f0ae3690906	1655714810000000	1656319610000000	1719391610000000	1813999610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
410	\\xd9570666d18f6eea7bcaea01b0e93844621b33823c30371ee66a42933b703c1e70def9292e4b37b0cdd38e237f4f4b2412f1aa1e77f580635586e9155986a00d	1	0	\\x000000010000000000800003ba8c1bf772fad2589fde2b0c18eb51ecead97d4936b95c45bb71599ea6be47ddbe0a37313430a0f3e7dbd8d20356a0e62e963146e65ae8984461a39c25367b061f74bd5e324c64bfe37468014f101523fdae0574ce9eda9137bcee7d5e1a2d0a1d2419ea0020bb0c323a87ac2f4585869c5ff4c59e0936f83d576686cfc6c919010001	\\xf39b1e848861345dac5cb8e12e2cb8505f422e13318622c21002885e0f7bb6edb20cc2e574e4e621966c6ce6688eb3c7768d13a698ed4b614063fb56cb399a0f	1672640810000000	1673245610000000	1736317610000000	1830925610000000	10	0	0	1000000	0	1000000	0	3000000	0	1000000
411	\\xdb5b4e1092b853847f2bd0b8554f5793b2f8f68d14f39e002a79231e13dca543beff2b335ceeb39656b88355b03386936186bae7263fcf889fc1b0b1dce1142e	1	0	\\x000000010000000000800003bd042de3a6125f0314f0e1839d32cbf5033c1e3caeaa57e5ecf64666ae6205050c9a9cafe14ea1c73eb898ed97f291726a74634ac7239e26a6e23eb0d727c9106499a2e5538a482e816ff7fb6e213767191699f74735a3dc489cd7b71e8cfb52ffc0bf53f5afd7f4974d9cc4c173219032ab9c9213807a4d881d281f6f47fa75010001	\\x413cce40f652369e38d680904217808b94e5135425ef2feed3bd3532b5e04cd896854b182da469acd50bf2869c9f415c7763e2cb34ecea419a8cb4b17f03190f	1673245310000000	1673850110000000	1736922110000000	1831530110000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
412	\\xe467ba03a4cd463afbcb41239a0a6f6a1c692a327546f50eb6fa5a2d66ffbdfa46b4a162cc92eda26bfa9a62930aa3aed423094592c1beebdef825fdc6556584	1	0	\\x000000010000000000800003a6efc83f7f1d814b95ee7a6ae279b8aaaaf5b177840de893f9c045f6a8ce2fb4ccc7318f54c89f6d4aaa23ff95bab60c5ac3cf13f3c7b8baef5acc82e00c04898dc321a24e75ad66477d7c77dd72fa36a05ce45dce0676e3450cb00cf9552850966159e695d268d2349d4e00b4ddc578fe669e9d09d786f814e07cfa18f02d2b010001	\\x625ed6a069536ccb655bd6e60922496c6da6ba18e09fafcc028d760004f301001fd15580da5efc211922aa474988f280ab4217813958aec1dc80c6855a4a1c06	1652087810000000	1652692610000000	1715764610000000	1810372610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
413	\\xe4ef355f50fbc8ff371702e2260d8c3b85e1e25d6c9707d67bfdb4e73546c8a0991044b190949c9fdc2ab79f9f7044e342e3eae02871d96c59ca44dad7949bb4	1	0	\\x000000010000000000800003c5b6aaa03be4e190d97222934df84634157d39e724d1db590563c75e477486a71afca850687eae3f2987eba1a8860cddb69ccad9d1248e54e001d47eb53e4cb488a559649d3adbdfacde2fcf389d952d59f6b427cc07ef5c82a9e2b90c5b748f57ed3c843ef9a4e2fb3a845b3bb1798945305f28907c3c67b869e26745682a0b010001	\\x1d793157e62f2d965e7131c03abe30416552d424710ef839146d80a52be366024ac811a6bb9cf11e0e96c21bb8a2cb74bf1efa1d0c8380cb1fdda9759cb8750c	1665991310000000	1666596110000000	1729668110000000	1824276110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
414	\\xeae3990bed05aefa6efb65629de9c42d56ee508c44f7b90c5306e13d5edf0e1b3d6cbcfa520686ad9b41e49b992bed6dc1743ba2b7f42480f2ab2d0aff5c68bb	1	0	\\x000000010000000000800003b1d8ddc3102d435be0bd08fbee7553bae36e97edb5e4787eb33dd2e4634ea99cbdd926e4f0d8921c3e62c5aca051ce0045493d86edcbc9f7a526110730005e4f995702ca2808b2b1ed1698b25ddeb2bd2f345d9145f3fdecfd780ddea225b2c152f30715103870764c97940555e245c2001c07b5ee777f0aa9118dca891428f5010001	\\xe2148d1e1f300f7bdb12d5e06185dbd826b24e76817a2687a02b0454389628bbcb6f685085940e340c63e12bac0b4e47fb53ae8e29c7dae48efa4658c6c13a02	1659946310000000	1660551110000000	1723623110000000	1818231110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
415	\\xed4f10c6b0f19a490d6f24eeb54532fd4506cf4173d5b4572c5ed537f4220557d43c06325bf1d99c6cf7361708f817c881c3e068db8cc02210d134480a673ddf	1	0	\\x000000010000000000800003af93eb2c05721b1fe1e4ff4b79c3da3dce4e63e4bf6cf35f597a0c295451173ebde7becc85eb0317395e9a0835e4ab956ecb07c00d722db3e7c972f0baa07ef558efb7021216be548d56f9e78756b2a7591c3f77b8b6d535514d6b8fccd751da904ff266325a8507fee696ccc98c446d4f80ef307cf9afdf4d3657ab4aaf0875010001	\\xc697843090589eb4df24d71ec02a9c579b3764501bb352110b3d977bf4fb0ab040f0b663042243b8b2cb4a0c536a88e0a9adb469926841c38b4371e281c67403	1649065310000000	1649670110000000	1712742110000000	1807350110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
416	\\xeed31e74d9dc27964c81d01f978c2476ee51ce7e936079bb25ace40838172f08e9ff79d2e2d6fe22fcca394872e730fd4a9b284685801aab582cf3e212a83027	1	0	\\x000000010000000000800003b276d36fdab40b9b56800ff24641a029580b2b13138e3e1a05dacc5916601bc854ae58e21efbc3b6db2f02c5e2193a2ac058c17a069ae2c5a6f746e52fe069679f15b808e003076d752fe12e5a73ea72cbd44042f5b571e2a89119c9975dfdb2d7c3b4d24357e18069fc9a782191677f2bc081778ec172fb66c27bced51fb7af010001	\\x08c8693548199baf049835939515c1f92b28e10a53c5a9fb81c20c4ed51e50bca2d0b34c2d21ef4c5d64b030885db47619594bc3e4fca5b4ad248ff43cbfe408	1677476810000000	1678081610000000	1741153610000000	1835761610000000	0	1000000	0	1000000	0	1000000	0	1000000	0	1000000
417	\\xf147173a50ab39e4cf95aadfc66886d91ed093dac111a9ff86a971aff1add00193b8f167170140c5eff0a5f20feaf57b7def0457e356a1db5f1a0fde95e85877	1	0	\\x000000010000000000800003d5e4c54c093756e254974a26e7b2d3f1035b6e2763e532e07dde35339bffe74107637365c212528d3e8167a7eb685adfdc6e793bc6ada0d83a87f3bad1f65b5726f955d079c96e06bcca02aa528171a2e1163ffc09d535734c1e56cc27e28136a3578f4bfa999eb6e74af48549ebe15af20718faef799fd34566d805d2bbe177010001	\\xabb34ee6fcc9cb8876b79cdbdff02c56d7a5e7327e37bc14d2eb352b992412d54841155f61f1ca8235529a3c680c86c1c3da104b265903a013161418e4d2c304	1671431810000000	1672036610000000	1735108610000000	1829716610000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
418	\\xf17724aa74322d0d9a336a21905eb773e432e850edbec3bc627bbd291c957218cbf74450dd5c11717e853dca9ac92c36a9123bb374ce7bee8ae6d8a31cf49f40	1	0	\\x00000001000000000080000395714bd023b76a5ab357c5be88a79e08673c4a82029d92a3dec4254c1fe9eee8dc71fcea960a6b4c9e450ec719724eae5bd78a78332aaa9905f33f36225a6bd0412ee06c75a620d1472b02c11d88f1663b08d4c9fe4b02a977688a7caf9f64469f0202829fc80b8e0e69f40a88ae98dbf0430e500c800f5555b2433195ac5521010001	\\x60965d00b658f420cf3666a7a987dc4da20f9e230e7b72b08c3bea4e6fe80831be579f289a9ca9aa4929e32c373879432d3925ccd04d1d1e44b1df1b73d9e30e	1672036310000000	1672641110000000	1735713110000000	1830321110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
419	\\xf5f7593f9723252e2a1f0ebdcea7ce5a94e18cfc1fbe1b82429173ff3b0df8766079391495ad150dbdcf22de2a706f65499141a21108d688db6b735fc5e6a294	1	0	\\x000000010000000000800003c04cba988eb6b4bef47bd76ccf4419f98fc29159361f14bbd730f90da0bc61c216f5def154f6ccb1eb4c70dca3ed639540968cbefd17d9ab84b1549a6e59bbf362d014f0a9120baf42a411f74cfbc6beb7573bef5943122c4a948e8a4693fc6de36b5170e1d075c81ba6e6476c5b3c8fadf6ad1ff4886d8488148704affafdbf010001	\\x72eed71b027c34dd653ea1081664fe03b0534993c9e9233a41654c145fd579b70811cc667df28b5f299ab8e792e6bca8ae0351773b4ce0ac5b2678bc115cb601	1668409310000000	1669014110000000	1732086110000000	1826694110000000	8	0	0	5000000	0	2000000	0	3000000	0	4000000
420	\\xf62b76678eca8526e0566c8937eaec3ceb5c30c785118ff8092b90fa029c94558305c514ccac022f36f8b4107396b1953f1887a2f354bed771ad3919567cd74d	1	0	\\x000000010000000000800003aeb94edd814eb0c0fae58e1ebc38cf8e13251f115ed388b51c653796a6d7a1fede957b1286137ccd6cd1fedd42944de3181588c81da233092e46f7ba6b7afacef4fe32cc2298ce5244fc3dde337e813763a5297b415255044f668a76c8e4fe9db1b8e4cde51dbf7891f2b0220da423d05ed57fe88085505213853aca31813c6d010001	\\x547fdfc44e7590b5cefc5c0045ebad7da7f70b98b0016faafae46253f28cd4f246f80f76ecb112dd1648361398710701cb0793901be31b6a9ff2eccab8087705	1656923810000000	1657528610000000	1720600610000000	1815208610000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
421	\\xf72f04d482cb7ddf3e7eacacef1b51cb564968d2c277396626ad392a3c9c0ab9bb400600cadba8c150abcfcd06ba895a6ef2ffb86392f3b5606ba3baaf70dfb3	1	0	\\x000000010000000000800003a99a3a90a5fb393ee57a5b6b93d6796c3735299e49c20152681529573662f41cbdfa8dea48fba935a5194bd474aeb904094aabf3f894c9e8166ec55066a139c049b0590d5e04b16b30a05c4bde8fcac169a66d277abf0f05c3e06adab09decfab77ffee2b5e8106aee7d5dedb8dff580aafa05d7215e5af4e8520e6b9d5b03f5010001	\\x5914cbf13c7425fd09b82dcac5f4573655f8a4dc2afc2520ae5d1a6dfeed3105aabbe855a299f7830ba0081509e6a7f8070667ad91b2e0039d70eafb61f0ef0d	1674454310000000	1675059110000000	1738131110000000	1832739110000000	5	0	0	1000000	0	1000000	0	3000000	0	1000000
422	\\xfb13b8311e3f2b7a0116b2dccb5a8ce5ee31d882a8649741056578d97d34096c2d495795981d02c30125c71841ad1939c05f7e665bd93e6cd343e6cfe6872c6d	1	0	\\x000000010000000000800003a90981ebb2f9dc0f95e6159c9ec82c2660187b515ab3f88ee74351bbb156fd7177fd6a181fd8054e554b09204892d5cff54a7754000a124fa56fa26b6227dc850716be55f4fb9f52cce05faf2ace51d5133f99c3e44e384b8e293f099a95ad2d8f0f2652c84480d611711d16e8bd24cec3b783c8dccab755ed52992b753df0f3010001	\\xc2a164660a3b5f81cd1398a5451044812d7b0a326ae98cc0fdbb14c962ea99c02322bef1d35c3e83f3d813f8f48b76af1d3cd89a7b21b579e6eacaf70ab1ad0a	1675663310000000	1676268110000000	1739340110000000	1833948110000000	4	0	0	3000000	0	3000000	0	4000000	0	2000000
423	\\xfc5be5e4731933006719e5c0a09a3fc0abed38a9d73c7fef48e47c1b5f236eccf5496d44d4f46dbe975ec53b1aa838a67fc03b34e37355b298e96aa4e36407b5	1	0	\\x000000010000000000800003df5a5ab5e070e24f22426e251d084c62812611005952fdf43895d2bc07d02f83146db326d1c72ecd5b309adfb55628768269b9849231ef7fa1c1d2f3c5faa4465783453d9105ef9866e46c423ac2bc57372abce145246e982eb30dd50417463e7451105adc0a38527cd9b15a637d5023c82accbaf41c7caa9baeed2638946655010001	\\x3831577ec9d7843bfc9e8b4e2d040ed5f17898087d5501c6657ae6b9c970cc44b321f4cd4c8a10ae44d39b2023adeeb54e31c7522a303c53a5306fc6f32ef50a	1668409310000000	1669014110000000	1732086110000000	1826694110000000	0	10000000	0	1000000	0	1000000	0	3000000	0	1000000
424	\\xfd338fde567d8aa5f378e136c877aeee9c64dcf57e8edb77e8fac01d37cef9f0d8c5d0adbb6e224ea329a61fe9b8874215cd4dd45ff328ee3a24a8e4b1f97c2b	1	0	\\x000000010000000000800003b8fdfb61027902c1bd7e484128f2599889dbcd70dc5a5e6ca8696e490b71da9ef5d8714b34ce4fb2e6d784ac9963ab9a9e043503aabf33ed134a6872f5c2e04683421ea2f17cc07009f83e829498061f2911036b40ef7b246d29bcf98a8057c487e6b127c78990d5de6d2f9d33081bad5e5c357008b5ba731558da3e5f6ae79d010001	\\x106898dc6f3b11b1a5505b608b71114fd89962739d8892eb9cb61dc9ba033252eb640fd2cf3b3ed0e849b6cdb273b0ed2e6ad6963a8ee370f75338c9deb87304	1669013810000000	1669618610000000	1732690610000000	1827298610000000	1	0	0	2000000	0	2000000	0	3000000	0	1000000
\.


--
-- Data for Name: deposit_confirmations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposit_confirmations (master_pub, serial_id, h_contract_terms, h_extensions, h_wire, exchange_timestamp, refund_deadline, wire_deadline, amount_without_fee_val, amount_without_fee_frac, coin_pub, merchant_pub, exchange_sig, exchange_pub, master_sig) FROM stdin;
\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	1	\\x340c54a4398351e170805ab1b1b020e9c19a503b6e1e03b4fb6ccb2d64c79739ba07380f795616c3114036c1369861162d55a0220d6cf21326d7a561a7e7de75	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xd6990c9a2f41d90997f23c5b0afb31681c67abd4ba604300d24a29a50faa267a2394a3daadfee78f4d14f6cd80e915812c3df4307742e559ae601f4cb17a4872	1646042826000000	1646043724000000	1646043724000000	3	98000000	\\x7cf66c6ed1c0deb0016b53aa4bc5a11fd3de9d499b9a0bebc4c54a322bb312b2	\\x4b1f4fbaaac2e84d7b23bf8dbc702576dc11809f947b23427e8b48d8e419a9f1	\\x9494ab9c0f74eff12968197b3ca0ad639738703b0fd6fcbbdeb7af23f73bfe7170d9241d6fbcc8484a2ca9f7c745238658b0c4e3e39c95441215d8c42d5c2b07	\\xda3d87c23c085ea852d3e950858a3e08dcb4bdd4711ac3de8c491e516bfca722	\\x3092b1d3fd7f00002d79dab4915500007dbcbbb691550000dabbbbb691550000c0bbbbb691550000c4bbbbb6915500000040bbb6915500000000000000000000
\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	2	\\x42fd3277a4b00b2146d2ee6e25d6333bfb490f8f42453deaeb81e028fe595ed1ee009bee0079b8bf101d553a0c1f7de00ac8d9671d91b89ee9694b7553a030b6	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xd6990c9a2f41d90997f23c5b0afb31681c67abd4ba604300d24a29a50faa267a2394a3daadfee78f4d14f6cd80e915812c3df4307742e559ae601f4cb17a4872	1646042832000000	1646043730000000	1646043730000000	6	99000000	\\xb3773a2d55264926f0bb235ece66958533d91feff53a50157e832118ba31a166	\\x4b1f4fbaaac2e84d7b23bf8dbc702576dc11809f947b23427e8b48d8e419a9f1	\\x178dc84294759294e1c301cb1a59424eb73c1f60b0823614b435f32422cbff2258a0ff584964bf9b3ca23c41a66ad36b0cf057edc4874a1b2067d9365b2fc40a	\\xda3d87c23c085ea852d3e950858a3e08dcb4bdd4711ac3de8c491e516bfca722	\\x3092b1d3fd7f00002d79dab4915500009d7cbcb691550000fa7bbcb691550000e07bbcb691550000e47bbcb691550000a09fbbb6915500000000000000000000
\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	3	\\x5e2ac5b1a6c173d0cfef242e385c46c523733f535ef611dc150fe1c768dc39a860c45274720a48bf2f04058203e12fd326f4e449432e1cc9313554c576303a3c	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\xd6990c9a2f41d90997f23c5b0afb31681c67abd4ba604300d24a29a50faa267a2394a3daadfee78f4d14f6cd80e915812c3df4307742e559ae601f4cb17a4872	1646042838000000	1646043736000000	1646043736000000	2	99000000	\\xb3dda5f26622b6b7d5b512a3ff4919f45e4234067a4223b12d17bb7d05d61a47	\\x4b1f4fbaaac2e84d7b23bf8dbc702576dc11809f947b23427e8b48d8e419a9f1	\\x3c4793e4745c67025c72a3a4847913ee16acc42fc1367e7e88602ef5bbad1a1c8f2b6c31d91db2ab8a3d7c22589e72cf1cde91422ba5cde53063969e3df73e09	\\xda3d87c23c085ea852d3e950858a3e08dcb4bdd4711ac3de8c491e516bfca722	\\x3092b1d3fd7f00002d79dab4915500007dbcbbb691550000dabbbbb691550000c0bbbbb691550000c4bbbbb69155000070a5bbb6915500000000000000000000
\.


--
-- Data for Name: deposits_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.deposits_default (deposit_serial_id, shard, known_coin_id, amount_with_fee_val, amount_with_fee_frac, wallet_timestamp, exchange_timestamp, refund_deadline, wire_deadline, merchant_pub, h_contract_terms, coin_sig, wire_salt, wire_target_serial_id, tiny, done, extension_blocked, extension_details_serial_id) FROM stdin;
1	158807622	1	4	0	1646042824000000	1646042826000000	1646043724000000	1646043724000000	\\x4b1f4fbaaac2e84d7b23bf8dbc702576dc11809f947b23427e8b48d8e419a9f1	\\x340c54a4398351e170805ab1b1b020e9c19a503b6e1e03b4fb6ccb2d64c79739ba07380f795616c3114036c1369861162d55a0220d6cf21326d7a561a7e7de75	\\xf2b04c9bbb6aaf6b50abe63b92764b8e8fe07a5dc1f3785e08c01df5638d066223389485bcce00d6ea18c1a3d0e592ac641a9ee2c73ed865b970fb68c2c17e06	\\x1197cd7f7b0e13ab1905fedb36c536a1	2	f	f	f	\N
2	158807622	3	7	0	1646042830000000	1646042832000000	1646043730000000	1646043730000000	\\x4b1f4fbaaac2e84d7b23bf8dbc702576dc11809f947b23427e8b48d8e419a9f1	\\x42fd3277a4b00b2146d2ee6e25d6333bfb490f8f42453deaeb81e028fe595ed1ee009bee0079b8bf101d553a0c1f7de00ac8d9671d91b89ee9694b7553a030b6	\\xce4277c67f89a582839b013e99769b93a76619e7ab1b71c5d38188c049e74790a4698e2b67f3afdecc0ff47b48cde48426dab71493d8b2cec5031fadeb3c6701	\\x1197cd7f7b0e13ab1905fedb36c536a1	2	f	f	f	\N
3	158807622	6	3	0	1646042836000000	1646042838000000	1646043736000000	1646043736000000	\\x4b1f4fbaaac2e84d7b23bf8dbc702576dc11809f947b23427e8b48d8e419a9f1	\\x5e2ac5b1a6c173d0cfef242e385c46c523733f535ef611dc150fe1c768dc39a860c45274720a48bf2f04058203e12fd326f4e449432e1cc9313554c576303a3c	\\x36a6dfa8ba734d00568246ca114089cdebc18cefc322e0e1138ef7454b97c0ee3eb4a5d16c8430048a6bcaf351d2b5670049b87c1b9836d7b04efcb3feb78c00	\\x1197cd7f7b0e13ab1905fedb36c536a1	2	f	f	f	\N
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
1	contenttypes	0001_initial	2022-02-28 11:06:50.214309+01
2	auth	0001_initial	2022-02-28 11:06:50.270159+01
3	app	0001_initial	2022-02-28 11:06:50.309302+01
4	contenttypes	0002_remove_content_type_name	2022-02-28 11:06:50.325252+01
5	auth	0002_alter_permission_name_max_length	2022-02-28 11:06:50.332401+01
6	auth	0003_alter_user_email_max_length	2022-02-28 11:06:50.34084+01
7	auth	0004_alter_user_username_opts	2022-02-28 11:06:50.346466+01
8	auth	0005_alter_user_last_login_null	2022-02-28 11:06:50.352607+01
9	auth	0006_require_contenttypes_0002	2022-02-28 11:06:50.354083+01
10	auth	0007_alter_validators_add_error_messages	2022-02-28 11:06:50.359663+01
11	auth	0008_alter_user_username_max_length	2022-02-28 11:06:50.368974+01
12	auth	0009_alter_user_last_name_max_length	2022-02-28 11:06:50.37623+01
13	auth	0010_alter_group_name_max_length	2022-02-28 11:06:50.388918+01
14	auth	0011_update_proxy_permissions	2022-02-28 11:06:50.395279+01
15	auth	0012_alter_user_first_name_max_length	2022-02-28 11:06:50.404319+01
16	sessions	0001_initial	2022-02-28 11:06:50.410793+01
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
1	\\xc3c06fd3886d87928160d84840acf4fbe02c61137f42591831a7d834338d14c5	\\x1c79cdfd2cea6e0b6528ec7f4cefe085ef2f45095b1015f5edc1a0e49955049d361c9a740bf48d20c8acaef45a7f93996ec48988fc6cb1e320dc2a59981f6408	1675072010000000	1682329610000000	1684748810000000
2	\\x63fae70267143c95f5c4546302377b9a6cf581affab1e2f6150298cec5572bd1	\\xfabff3c41322d536ca0dbff8db1ef831b6d156c1686de167a009ac7e336b6f9653b552bd2c1f6da524592c8d7655df6492c19e0fd9ff3f4277cd0ae9d61ffe02	1667814710000000	1675072310000000	1677491510000000
3	\\x6e4f744b8f275c4b42ea9758178c5737d296bbfd9c9264663d8c7870f2e0b8f1	\\x4cfc909421a4c532b7c21af37c046e82268547a0a92d0d3719843ca013ae47e92cfbe31ad33a24b7fff36e666df03ce627dfc5f937d18e3201b6807c067c670d	1660557410000000	1667815010000000	1670234210000000
4	\\x6f84544b3003723790459bdbc6a68fc43a40965d687af23d83d6f3ff0ddf121b	\\x1c75f85208ce95a77a3030c3e81c4b19054a720a077f82eac325688ee8d103b47be7ea73ee57ac509bb63094974ac426bc1f6cc7fbfb0a18a85401ded698f10c	1653300110000000	1660557710000000	1662976910000000
5	\\xda3d87c23c085ea852d3e950858a3e08dcb4bdd4711ac3de8c491e516bfca722	\\xd23722df48a0b99187141cb15555b1969f3bcd016dfafcf0e90fd6248d64aa678d4f2ef9f6cb187a21345ee88cbf7b1f32058e7135145cc31b011cb7cd0ac102	1646042810000000	1653300410000000	1655719610000000
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
-- Data for Name: known_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.known_coins_default (known_coin_id, denominations_serial, coin_pub, age_commitment_hash, denom_sig, remaining_val, remaining_frac) FROM stdin;
1	151	\\x7cf66c6ed1c0deb0016b53aa4bc5a11fd3de9d499b9a0bebc4c54a322bb312b2	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x000000010000000066ad383924d3282d4dad460b6ea988cab5a25c3b875d63bbfbc78a39b375bbcab3466d4089ddd1465b4d9c29dd4efd80d4489b4237238c48dbe89308673f5a3a1308f5301f878ace9127675f3ffb9f5422988cb207525ec0d75c5d7c3df62483130c526f18f557673e94b0d693f8e0045090f95a83e45cfad8063609af15c0ec	0	0
3	208	\\xb3773a2d55264926f0bb235ece66958533d91feff53a50157e832118ba31a166	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000c796575fca02b2690a714902d7f64d12e89e21892285f850ba0f0aa0d2e86fd68f8466e207c420666017eed53aca367e56c454c8268026d7429bc7db9d83d550e08a90c47c7d7e2cc614bf15110b83d82363a7b114edbbefee0b0ea56629a032500eebff8372dbb448646b8c911f36ac3914a5cf0a58c853b892b29940fb31ca	0	1000000
6	327	\\xb3dda5f26622b6b7d5b512a3ff4919f45e4234067a4223b12d17bb7d05d61a47	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x0000000100000000ae34dd781bf689d5332644ed8e4e0e44cd28ecf5752a0454e82515a0751316d746683be7ab47ab7d4eb6974014b6dad6ad287a104bec91186b30e319db7bb7c4be292ac4e443548528caf7f650b2195af40abcbfb8298ecee64e6e3bb99d33922affaf6fe8a512f526e14367607739eda849182482cd02cc566e100e20818ea1	0	1000000
\.


--
-- Data for Name: merchant_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_accounts (account_serial, merchant_serial, h_wire, salt, payto_uri, active) FROM stdin;
1	1	\\xd6990c9a2f41d90997f23c5b0afb31681c67abd4ba604300d24a29a50faa267a2394a3daadfee78f4d14f6cd80e915812c3df4307742e559ae601f4cb17a4872	\\x1197cd7f7b0e13ab1905fedb36c536a1	payto://x-taler-bank/localhost/43	t
\.


--
-- Data for Name: merchant_contract_terms; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_contract_terms (order_serial, merchant_serial, order_id, contract_terms, h_contract_terms, creation_time, pay_deadline, refund_deadline, paid, wired, fulfillment_url, session_id, claim_token) FROM stdin;
1	1	2022.059-00EB3MHAHSC6J	\\x7b22616d6f756e74223a22544553544b55444f533a34222c2273756d6d617279223a2268656c6c6f20776f726c64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634363034333732343030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634363034333732343030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225454434753364846383743474b355a4a374844474e595348443045364641594d513947343630364a39384d544133584134535832373535335641505a58535746394d4146444b433058344152324231585947523745475135423651363037544350355834475747222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3035392d30304542334d4841485343364a222c2274696d657374616d70223a7b22745f73223a313634363034323832342c22745f6d73223a313634363034323832343030307d2c227061795f646561646c696e65223a7b22745f73223a313634363034363432342c22745f6d73223a313634363034363432343030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22544d51303944394731385a3854464541424438333353444a364a515752594b46485054575436444d50515335345a433636524447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223943464d5a454e4152424d34545953335159365652573135455645313330345a4a48584a36474b5948443444485330534e375247222c226e6f6e6365223a22444457594238354731534a4a435939434245535432563651455448583258515957584837454d4a41455a5a4b454b5046484d4a47227d	\\x340c54a4398351e170805ab1b1b020e9c19a503b6e1e03b4fb6ccb2d64c79739ba07380f795616c3114036c1369861162d55a0220d6cf21326d7a561a7e7de75	1646042824000000	1646046424000000	1646043724000000	t	f	taler://fulfillment-success/thx		\\x278d1a92c0c6557a258140327ea94d9b
2	1	2022.059-01W7FASCQJXNA	\\x7b22616d6f756e74223a22544553544b55444f533a37222c2273756d6d617279223a226f7264657220746861742077696c6c20626520726566756e646564222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634363034333733303030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634363034333733303030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225454434753364846383743474b355a4a374844474e595348443045364641594d513947343630364a39384d544133584134535832373535335641505a58535746394d4146444b433058344152324231585947523745475135423651363037544350355834475747222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3035392d3031573746415343514a584e41222c2274696d657374616d70223a7b22745f73223a313634363034323833302c22745f6d73223a313634363034323833303030307d2c227061795f646561646c696e65223a7b22745f73223a313634363034363433302c22745f6d73223a313634363034363433303030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22544d51303944394731385a3854464541424438333353444a364a515752594b46485054575436444d50515335345a433636524447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223943464d5a454e4152424d34545953335159365652573135455645313330345a4a48584a36474b5948443444485330534e375247222c226e6f6e6365223a224d575a38543456584b51513047594e31524b4d30304257464e565939524152544d4b4d314150595a38304b3356335a5933534130227d	\\x42fd3277a4b00b2146d2ee6e25d6333bfb490f8f42453deaeb81e028fe595ed1ee009bee0079b8bf101d553a0c1f7de00ac8d9671d91b89ee9694b7553a030b6	1646042830000000	1646046430000000	1646043730000000	t	f	taler://fulfillment-success/thx		\\x137d5307ffa7ee48829557d956e8bc61
3	1	2022.059-03E8BYRJXQ17T	\\x7b22616d6f756e74223a22544553544b55444f533a33222c2273756d6d617279223a227061796d656e7420616674657220726566756e64222c2266756c66696c6c6d656e745f75726c223a2274616c65723a2f2f66756c66696c6c6d656e742d737563636573732f746878222c22726566756e645f646561646c696e65223a7b22745f6d73223a313634363034333733363030307d2c22776972655f7472616e736665725f646561646c696e65223a7b22745f6d73223a313634363034333733363030307d2c2270726f6475637473223a5b5d2c22685f77697265223a225454434753364846383743474b355a4a374844474e595348443045364641594d513947343630364a39384d544133584134535832373535335641505a58535746394d4146444b433058344152324231585947523745475135423651363037544350355834475747222c22776972655f6d6574686f64223a22782d74616c65722d62616e6b222c226f726465725f6964223a22323032322e3035392d303345384259524a5851313754222c2274696d657374616d70223a7b22745f73223a313634363034323833362c22745f6d73223a313634363034323833363030307d2c227061795f646561646c696e65223a7b22745f73223a313634363034363433362c22745f6d73223a313634363034363433363030307d2c226d61785f776972655f666565223a22544553544b55444f533a31222c226d61785f666565223a22544553544b55444f533a31222c22776972655f6665655f616d6f7274697a6174696f6e223a312c226d65726368616e745f626173655f75726c223a22687474703a2f2f6c6f63616c686f73743a393936362f222c226d65726368616e74223a7b226e616d65223a2264656661756c74222c2261646472657373223a7b7d2c226a7572697364696374696f6e223a7b7d7d2c2265786368616e676573223a5b7b2275726c223a22687474703a2f2f6c6f63616c686f73743a383038312f222c226d61737465725f707562223a22544d51303944394731385a3854464541424438333353444a364a515752594b46485054575436444d50515335345a433636524447227d5d2c2261756469746f7273223a5b5d2c226d65726368616e745f707562223a223943464d5a454e4152424d34545953335159365652573135455645313330345a4a48584a36474b5948443444485330534e375247222c226e6f6e6365223a225031513353464637504a4451593747384843354a5a3143575657534743344a503856533752425635334741523146435639425447227d	\\x5e2ac5b1a6c173d0cfef242e385c46c523733f535ef611dc150fe1c768dc39a860c45274720a48bf2f04058203e12fd326f4e449432e1cc9313554c576303a3c	1646042836000000	1646046436000000	1646043736000000	t	f	taler://fulfillment-success/thx		\\xeb808dbabd96d79540bab8571da4cf9d
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
1	1	1646042826000000	\\x7cf66c6ed1c0deb0016b53aa4bc5a11fd3de9d499b9a0bebc4c54a322bb312b2	http://localhost:8081/	4	0	0	2000000	0	4000000	0	1000000	5	\\x9494ab9c0f74eff12968197b3ca0ad639738703b0fd6fcbbdeb7af23f73bfe7170d9241d6fbcc8484a2ca9f7c745238658b0c4e3e39c95441215d8c42d5c2b07	1
2	2	1646042832000000	\\xb3773a2d55264926f0bb235ece66958533d91feff53a50157e832118ba31a166	http://localhost:8081/	7	0	0	1000000	0	1000000	0	1000000	5	\\x178dc84294759294e1c301cb1a59424eb73c1f60b0823614b435f32422cbff2258a0ff584964bf9b3ca23c41a66ad36b0cf057edc4874a1b2067d9365b2fc40a	1
3	3	1646042838000000	\\xb3dda5f26622b6b7d5b512a3ff4919f45e4234067a4223b12d17bb7d05d61a47	http://localhost:8081/	3	0	0	1000000	0	1000000	0	1000000	5	\\x3c4793e4745c67025c72a3a4847913ee16acc42fc1367e7e88602ef5bbad1a1c8f2b6c31d91db2ab8a3d7c22589e72cf1cde91422ba5cde53063969e3df73e09	1
\.


--
-- Data for Name: merchant_exchange_signing_keys; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_signing_keys (signkey_serial, master_pub, exchange_pub, start_date, expire_date, end_date, master_sig) FROM stdin;
1	\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	\\x63fae70267143c95f5c4546302377b9a6cf581affab1e2f6150298cec5572bd1	1667814710000000	1675072310000000	1677491510000000	\\xfabff3c41322d536ca0dbff8db1ef831b6d156c1686de167a009ac7e336b6f9653b552bd2c1f6da524592c8d7655df6492c19e0fd9ff3f4277cd0ae9d61ffe02
2	\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	\\xc3c06fd3886d87928160d84840acf4fbe02c61137f42591831a7d834338d14c5	1675072010000000	1682329610000000	1684748810000000	\\x1c79cdfd2cea6e0b6528ec7f4cefe085ef2f45095b1015f5edc1a0e49955049d361c9a740bf48d20c8acaef45a7f93996ec48988fc6cb1e320dc2a59981f6408
3	\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	\\x6e4f744b8f275c4b42ea9758178c5737d296bbfd9c9264663d8c7870f2e0b8f1	1660557410000000	1667815010000000	1670234210000000	\\x4cfc909421a4c532b7c21af37c046e82268547a0a92d0d3719843ca013ae47e92cfbe31ad33a24b7fff36e666df03ce627dfc5f937d18e3201b6807c067c670d
4	\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	\\x6f84544b3003723790459bdbc6a68fc43a40965d687af23d83d6f3ff0ddf121b	1653300110000000	1660557710000000	1662976910000000	\\x1c75f85208ce95a77a3030c3e81c4b19054a720a077f82eac325688ee8d103b47be7ea73ee57ac509bb63094974ac426bc1f6cc7fbfb0a18a85401ded698f10c
5	\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	\\xda3d87c23c085ea852d3e950858a3e08dcb4bdd4711ac3de8c491e516bfca722	1646042810000000	1653300410000000	1655719610000000	\\xd23722df48a0b99187141cb15555b1969f3bcd016dfafcf0e90fd6248d64aa678d4f2ef9f6cb187a21345ee88cbf7b1f32058e7135145cc31b011cb7cd0ac102
\.


--
-- Data for Name: merchant_exchange_wire_fees; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_exchange_wire_fees (wirefee_serial, master_pub, h_wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	\\xd52e04b5300a3e8d3dca5b5031e5b234afcc7a6f8db5cd19b4b5f2527d86361b	\\xf9099467bd884e86871559a62a7f23b6e876bf084a30371891b5129ce4440d3cbe27afe387d39b2ce8d9625abd388517c81bfc8da9f2e0f8c9471bff65a802b2	1640995200000000	1672531200000000	0	1000000	0	1000000	\\xde51615105348bd84c0473a2815b9a07854bd5e16899d7c57b4ba533194c329dd8d2278c2109558fe593109fab9b971131ab9e6965f8e17c7fe04a0b34efe103
\.


--
-- Data for Name: merchant_instances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_instances (merchant_serial, merchant_pub, merchant_id, merchant_name, address, jurisdiction, default_max_deposit_fee_val, default_max_deposit_fee_frac, default_max_wire_fee_val, default_max_wire_fee_frac, default_wire_fee_amortization, default_wire_transfer_delay, default_pay_delay, auth_hash, auth_salt) FROM stdin;
1	\\x4b1f4fbaaac2e84d7b23bf8dbc702576dc11809f947b23427e8b48d8e419a9f1	default	default	\\x7b7d	\\x7b7d	1	0	1	0	1	3600000000	3600000000	\\x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000	\\x0000000000000000000000000000000000000000000000000000000000000000
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
\\x85261da8a4ab166584429b914c48babfe2c384f7e6b6dac17181519c97086e60	1
\.


--
-- Data for Name: merchant_kyc; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_kyc (kyc_serial_id, kyc_timestamp, kyc_ok, exchange_sig, exchange_pub, exchange_kyc_serial, account_serial, exchange_url) FROM stdin;
1	1646042827000000	f	\N	\N	2	1	http://localhost:8081/
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
1	\\xcfe7983a5adbc4296b8501f193455c0daf8cc35c718f2618f77ee6c555add5451ac72b0cd84815405a3b1c1a979d23e955ec92289d568e7eee76c62a5f034f07	5
\.


--
-- Data for Name: merchant_refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.merchant_refunds (refund_serial, order_serial, rtransaction_id, refund_timestamp, coin_pub, reason, refund_amount_val, refund_amount_frac) FROM stdin;
1	2	1	1646042833000000	\\xb3773a2d55264926f0bb235ece66958533d91feff53a50157e832118ba31a166	test refund	6	0
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

COPY public.merchant_transfer_signatures (credit_serial, signkey_serial, wire_fee_val, wire_fee_frac, execution_time, exchange_sig, credit_amount_val, credit_amount_frac) FROM stdin;
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
1	\\x1ee5bc4576e65f8ffe20b8dc1d9ddf0932c5a24637e2592d3b9a623c13a9ec4654faec870707b6d269b07d651bd1638fbb117327948a0d85f2ed8e3a0fb99bca	\\x7cf66c6ed1c0deb0016b53aa4bc5a11fd3de9d499b9a0bebc4c54a322bb312b2	\\x0000000000000000000000000000000000000000000000000000000000000000	\\xfbe018563cc7b54ed1143a9d297059264b4ff5bd01f82d0596a1310c8ad5d6214cbbd824f94f6d0964187f92d77524c2df6c558b971ab27200384890829d4608	4	0	2
2	\\x1ae825afc3b5429119fdcdf4604f19db56e3409296c793579cc4e22afefbd639210865205324a025edc5494e0c6b686d0b97108c9e8001c7edfe1303592d391a	\\xb3773a2d55264926f0bb235ece66958533d91feff53a50157e832118ba31a166	\\x0000000000000000000000000000000000000000000000000000000000000000	\\xe2f3e367a86d85b042dd07694949c7a10f520af95cec6e1f48a6fbbb0acd830a2782ae43276fa2a8b4928c20d16da051bf31cddc4343f3d12a7453f9ac879f03	3	0	2
3	\\xfb2cf384328c92fdb0eedf20cf4f3dbf2a08ea02db7e094adcabf7136e38f1a2e62f6e917309124974ec189d180480420107c2cbcaa574c138e651fb11002bc4	\\xb3773a2d55264926f0bb235ece66958533d91feff53a50157e832118ba31a166	\\x0000000000000000000000000000000000000000000000000000000000000000	\\x83d581bed35fc69a6c6ad3ee9ba18f28c17f990a44dee7603813b5b7bdd9ed2832ec94484e216455d489aa2e5c90673cd1dbb3951ad57928f2c8ef37d77dcd04	5	98000000	0
4	\\xdbd7043b47a0e9ad4bf36b21c7edebf45501f2deb7a1a048f091d7308a380fb4c0186e68b5725c6657aedad47996f3de8ecbcf6503e03c7139f2cfb1f13ba3e3	\\xb3dda5f26622b6b7d5b512a3ff4919f45e4234067a4223b12d17bb7d05d61a47	\\x0000000000000000000000000000000000000000000000000000000000000000	\\xd08e091db90607191bd22c8064ae5515a61679adb2d6df5637f94b79e85209eedbc8168a5ca791362199ce200a679416e3e32d71cd84b277cab6506fc65f340a	1	99000000	1
\.


--
-- Data for Name: refresh_revealed_coins_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_revealed_coins_default (rrc_serial, melt_serial_id, freshcoin_index, link_sig, denominations_serial, coin_ev, h_coin_ev, ev_sig, ewv) FROM stdin;
1	1	0	\\xb566a40b3f41c1fc25a57873bd7282a5b24c45e25964467820a697775d531f46f40ec906788a8dcdee40c9cbe936637accfebdbe2a2f56503787727599c3640e	181	\\x00000001000001003c8b939164d4d95ad4cadcaa8d5c799102ee65ee6fe8f71f6a165df071f21d889709893eeac28a5cad2a36f2ea4fa1d339c67cdfaff046b12712e45454c178e85c3e886dccb564bf129b53f0c9ece818bbd14cb03f85d53e6a2d4e2722d7307f44e0babf59d791bcb0d188c1c7f02096ec15688ce8758b627bf5dbafea934cb7	\\xa734f159308ab9241580aed47ad2ebd07fd634a21c0082a6e1c452362b3423946a86a4cf2fff20bed5de92b424ee69503d4575d1da7b713c10c792ef9a90fccb	\\x000000010000000155babe0d27c740b7a5e4a0fd6ddce65eb4e7837b3f7401064fa4378389a6f1c564bb6e12769ab0ccfbeb74faffefb2497b2efe87251d4af84bbd957fea138f28457b17145fd9d5c5512171f75a836a3420ecea3bed785e3bbd1d45baaf43d662092f9fbefe175780e765994312c3934117d48be53fb1a1273127f599b5761e44	\\x0000000100010000
2	1	1	\\xcba38d0c4a6b5ccdcd86e1628a28e64b76461a6a00f60167777b1010fce59dcfc0d9d5005534b8aedc701ea5d518a7827a352f7ebd70e816c6fb04077a894500	286	\\x00000001000001004276b7c97d8afeafa5a837a8274338268077c8e82536305311ab592f3c2a2d3c4dcc0a77fbd12943c568780686c123cbe233c68d92f1436c9ee0508b24e36e9dd9607eb6f5e0f05aab0a1dd2b5932ada3da025fdeac153f650ff9392a5da4fdaeef165e6bcfce20aa638335faf6148a20d254574beec63e2c464687a5dd30ad9	\\x4eb3f0d756fe1439f12a9df3db20bda9c15ba1636e05bc541935422447b5d1cf98478fe9c2b6965606340a92f64b62d14704f6a0cb5e9b335f9e7320cac40942	\\x00000001000000013632cba9280d0fec8206800e5f37b029def100865438babdc224b704a7e2ff3d3bac1bb60c8acde9efdf581deb14e6aaef6ed1d8db1b85d71e8969cba4641cd2e11a7d89bb1496e843fbbb5731df623537e7037e939b1125aff212218e490e6486a3b250ff318fb13cdf5f849e753dc9dbbbb7449d6299efa946ba3db4a9186b	\\x0000000100010000
3	1	2	\\x89dd7142968f5bc262532fb7eba0b2013cdb6b31332f1610d980dece677a2a65b840df63cf07ecde6010a80e0bf7386b049aeb774553b0151e65745349c8a707	336	\\x0000000100000100a4de37c8fd1778b164c3effc0b34fa4a17a7440a13330a7730831612f33c6893016fa081226e179bec184b205e0a80700ff66fb9cebb4046d016cb81946d580f500a969a1155d58f54f091d2600c9680c612d8c7443e68fc46ae495a39dd14060f59dcd4e5a1e8bcdd72577131dfee5d12a58f8a4ec1b602a02f157f96530727	\\x00ab78fce331cf4258a15a222e9ec60eff81fef2bc6c75f0159c34665e095e478c655e299ee3b7817097c4845dde083458f0f588ab9c10f174034874d49a3825	\\x000000010000000134b80d56d0bbd9d3be05cd250d6dacbd885f4a79bd3a255b8c2ee307d5bbd3451ef54302b29f7097c454300eac27c6c1304adaf99981f13d1193af3f7486d3fc84621dd406b00777916589f3cb00110e05f91ab791947fbbd10792353a0777ec2ceed1864c09c9dc0a4532aa4f90344d7c9da755b0e93129f970014df781f5d7	\\x0000000100010000
4	1	3	\\xd361381ea79cc9c892368ebb8f2541386e8b2019b7fe1d0e0217fa023876209839aa7e99e12384a3da49239ad01ba0c2ae91f0492a041aa64beb9b00c54f1e02	336	\\x00000001000001001fe92f936cad28bf61f6e675c4dc210013646f0c94963992006a1e7526a630acab78ca90888fed6a363e4e14c39bc0d21d88e17ec4c9ace049bd700a6d80cde3f0c7b8b794e4c0ebb817760065c37213febd703fb4f53ea18888508d7bdf17ca21066d642ab895b16e1eaafae907b8ec7e0bcf70ce94ead232e438e37196da06	\\x164c0927c6d01fecc213e99362dcd1400b42533962afb33c8a7e8e115ed627d833a2334e81c1064a3ffd3ee71ea44c66e85d5a73731bc6e0c66b026a0d803981	\\x00000001000000014cbc9f8ec364055bc475d8dde3c88be715c9b0bc7fc6f4a2d525bc75e3762e31081dc51a621be09ded8e01efa352153d46fa86af172712597a23cbe1aa8e37d7a9cd826d4646d0cc4c2033b7329a91e3cc49a72a7b3943c3892753ce58e8c321e0ae4067d98c1a14985d0dd1871ee59480703d4bf9f03933fbb543ebf263ae1e	\\x0000000100010000
5	1	4	\\xfd7acb2971b373747911aac88cbce18204acf3fcbd929a27d40a71303bb1dac635cd736d98909fd6e9f2ace99cc03feb6b0bcbf4c1a2af91cd8e3443cd7e2d0b	336	\\x00000001000001008c8f1799975cd3b2388a1ae2f70b62c437067ffcac16b2c87c766d96846844bd3222dfe21f07600bc70fb50502d8c4e6ca6cbc3748adf1f3e4dafc18111b0d30668fb340be51325d31b486b89e97364b4c2b2736d5cd59df42779f75a42968c3f9069e80b174f0a0c20633601204abf090d9952562e5a832c2a735faaa821f72	\\xe0b236324b5e6b42b9140b424043195c9fbe822b7aecc67e9871fc61320253cdee5be5b12254cbb364498305dacf21f75f45a393a46ac1f00cfe3ff0eb154c7d	\\x0000000100000001140b2cd5a899a41f89d9546077b9a4054c42ff3810eec4063703f96f77b0c94fe53a7d304a84d8b4e7131fca7ffcc39736bb0346bfd1673308d238d05f30be7329350c5c47026f9ab198e1b90736ff71ca7244de4e433190419eb5a184c585a26a7f51c36e8b7f7a635510e0e517941946a0a0ca172ba5d1bd5af6673621df6f	\\x0000000100010000
6	1	5	\\x40614b62b3be4b86ca8577e9fb9cf6c21d93040c00ca988b0a31543f632682afd0d401bbf8f266aa75ca99b413fb2e3b81a165ae4d191c7f63eb0882f2619200	336	\\x000000010000010006d7075d8005979010203d145bd1b0c7af219adafd5762eb0bc674e9784293ad8a862dd3eca349a079915e7d11c232a33bbf99e8e54277576e03588130ee8f9d29e7e3a9576d143c71fbd3587f568cf183728a034f7a11127dabcbe28c72cd69d2dd5e742b86ffa7ff1e5c20c7d643b4b07ab20285f9e716499d810057624a4a	\\x1c40a0e078daa6688f3ffce80b83fc13bb30e8854f3c62113b5e97ad39b263ad327c53eaaa630b7f24bbbd533999105e407662068822f3f6d200439148722057	\\x000000010000000184518beb5a22e54f470123eb23ef7167129fc8c0e8748501d2ff1207be2ad1f875c913a4895577d1a102e9d3b6a4775ede157dfa02217a42f6fe0786408388259fadac8866c2cbc1040d1bb8a82d0df4379fbf81b44881271125dc2115247bdead9b144079557a8937877617582a45f9b02e5776e666bd890eb25fdabbc4bc35	\\x0000000100010000
7	1	6	\\x49dc9594dac440954dde5983e74d9b02a3c89531622ed989f5e00023916790523c44221abd7b19135810a911966369298dc8fb43ab10f01e9f27579992dad70a	336	\\x0000000100000100461f21eb2fff40558a35af37d8bf232269408d9f36c76265ecb9685e3f769f7a78bbc77cd91d4307090edfaf7dcfafd273497059dae6e0c908bf314433691c2bb61083421de8a93c96bd2a38ff8f0a1b4852dde029a47681d4e98e79be2cd05db10edf138f7edc882f300f01c3450aaad921e8c68df3051ec5f7f8c80bb39e6f	\\x115663cef06119d4e75018adae3003a7e6caa901d3dba86fad7be69fcfb3f0aea616e515d91cccd8d7686f89c7bab4d503e27de29e241f7a3398033f8d6e64c9	\\x0000000100000001a7b62ddd4a04129d65ab1916b09c9992db014087bf9a1e58d842d00ff0fd5b4dca9901aec58af1f11354a690887f4634b7e1440c36858fa6ae0d4d53fbe2fe387a6f49db7e2d18ae0f99511d18b9110d1e37b65e92f162c566a983bb9acb0e632df4a42f4cee8211de4192d8ba8f2b02ef09185ed95fd6fc7e1c9f2b1a15209b	\\x0000000100010000
8	1	7	\\xefbe6569163025cc9f2b772a742c0bf46557d66ad1018ceadf6879cd3d4ae2996f0e8dbad7e66e4799f959d1e5bd38bcc0addc480f8e073504aa3943efaaee04	336	\\x0000000100000100628047c69df076833d496ecc073b5e5e4d0e55ec6a548e6b2a75b5210ebfe8fa0d5a7f101bf58e058e6cf96c45f5a1707efbb46b93e66087fdcf1c2f1fe4eb5edcfebdb053380fd8765d9560d30a7cf6251480e1ceaefdc909eba6b1834ffc3a133a9c6a836daa83ee1811472527fb221ce84f55cbc66738c62f8f66c5a34778	\\xd8e4a9d7f8639390c3876e50209be9ecc4f07f95aa4406f4fcd709bfd68688c8ae6380bcb5799a38e6299c3218107c59fa966506fd6a4b838e3d0a5d2df30a6d	\\x0000000100000001a2468abdd1fa7136ad01179cd217115571de00f550e7a1eaf24454e5a54c6ab43d6866a425a3212ffcd2766128cde0648e07b88b1ce96580e5de8ccaab9c0bbc8cc782152dfddcd22595e341abafac1c5cb7d65ffdfa78331a8b7556fc611e0c76e09562bbd55bb9631d9610524ef0c00dd2251c811dd8c5a73f230390d103de	\\x0000000100010000
9	1	8	\\x70db3b11a11396f36ab9664ca3845c610aaf7282f91371b51ad4f3e40570ab6ab78622921ee9498f3e53ecdeb749ff49ded5e87e233d05280da0ff169c4c450f	336	\\x0000000100000100c0f4ff408e6c44717d2eef6fd4195a0923320a481defcd42f7a0d40a089e2553b03cd629a1fc934b7a7ef6a4030f0a68d42f2e708760b6e7076485738e5d7041aeccbd620041fdf3e1ef91983138ebabf27786ed352b304c5fe8b3e6ad5e59dc6645d545c66ae838f3e0e189fc38874d543f608349611fda6f22910a3f10b269	\\x2141494813bbd595a8bda63119c51aeaf559f62e05a30f4633fc5e5b26cd58dc3ce9c6929cd17f96364eb96b98f204f60d6b1a7854260e793c5b6793c3ba0b3b	\\x0000000100000001acedd510257689a3589f951b7a24d177e5ab40e4beb0d9eda0b21f9bb5958908ca53ea36fa735d882f705b7109dc5431d9007e3c24c7d76c89303c983082739208827b7aac9012edd248e8fffe33759320ea38f93daac2d739456f475f9de02b042f05149c0df3491f45fb630a0391215cbd880dfb7dcf5e807a9f255db8d362	\\x0000000100010000
10	1	9	\\x00271446a7535016758788d3ec164d2764d5078cb77bd98c6ce0c1abc26cc4e416fa389952f4b6b3349a5bfc43e9bb596cbadd1f2b6cdad22cc9eeca563daf0b	336	\\x000000010000010070dd0b51c49117a1d7284fa541ec38b673a9ec847c4e56a2067e7c604cccef05a1fbc602c6edc75a398fde43d97e78d31441f9540ca9ff984c6f3dd56ce63c9abdcc9cdd3ab46a00eff909bc75b9f30ec01b2b02a7c3e33388ae179f19badcc6bc340423e3b4613ebee10226ae79f8de80defcb293bec77a614bf4b73537aba1	\\x401521e5dea4a2ca819e782202b7437ce55633be2666b66f742ab18aeabbf1e31b7111a92bd4da2834b5ccc75e0aea48c30a00b44bd418e2245c9b5d5fea5915	\\x0000000100000001acce373bf3c2e7d48f342875b8727a212a188a6783f4ce81aa26a5d87cffea4cae3b24103bbafd0344cb6aca141fffd5cbd2cd335523ce66019441752900d0a93f08f1e73615a498acd7803d34ee25437fceb2edd909a2edc476fdca3376491cc82196319625b07fd01c865ca2dd4d86e6710f7622689bd08ded4aa725be9eb1	\\x0000000100010000
11	1	10	\\x1326b934cc7fd61b0454793d8b2088040ae939228ddb40f05c1bd2f9f21f283b43d51ec32ec03f9052bb501bf8db4094106bdcf8ec29f384909044ad104c3002	206	\\x0000000100000100b180819be587c39967474a261522d9e1e42ac93780f78e3a6daef9309fe549e359e1562fd863f5faf40272f25e0d886f007b6de4e408457f9aef1b6bf04b582dcd15e2f3b3104664ffc3fb19727105e177899e01c9d37c14bb49517bd2677cdb614ff193934c612ba7a31d77c650e487acf8f112ec2b51347ef16b7e8b547a06	\\x801dff0b1a0bc492aee4f3313615da3cf37a41751c795e44ae067e142a57b2a67ef89ab4e34d53995de83697769d6844685fa816aeb109fd660f9b2f238942ab	\\x0000000100000001aa1f8c4c816abc6188bc08ffa47f037f53b29645215c3b97477ec0fdb0229210048f92fc159077f93de86b5a39d4d8e3360e0b6f8c255c4372ffb83de630fb865815ecd3caf91fc19a183efb1e1bbd6dd267cb1143e8e9e2db235931da2e0eba683e7697de3539f0d7f393e0d873d33ffb7007c20dd050efe65a914eb9d6c872	\\x0000000100010000
12	1	11	\\x6addddeeb65dc898ec805468662e325ffca48adf15053cf2e22234f54d2e32aaec7ef0693aabe3d8b0b65bbd057219ee164ebf76e9a8c15276f0bb8adbf07009	206	\\x0000000100000100503757907ee1e2c1f9a02e5cf3ae23f21e1f1d80568a5ac229f0ce876bf7d5da53ca0e11b6ca812d5a04d05102fcd2ada4aec4d96b353f3bd1b7f125a8d81ad1b0918defa64f28ad29d3b429974a557cfc040cbef1ed4726648e62c50ad835333d9fc4ae6c2c6f287163bf6c40049861c00affaf4d23bba425380e01195aae66	\\x476e94ddb66acaf21ddb3f83bed68cfeef0cd0a9e5f3ee18a399538ded03cb88c787dc7d041eca74bba4853a37195b6235114c22c1b8eb7c91831f11f1574c97	\\x00000001000000010af07148646ebc6b25d674e27876615e8408c5bc84a3bf6c2622916b0c174b99939bdfd78acb8e604774e5702d172e145da46e8f19c004ca320b57b7af493d916f0a997291058739bc10e80cea37a67c07a93dfadff6829da623f70e0c0874d5417121035416ae8a5a3b0de29106e76bcc453e54a890445a47e0b7ddd01bd8a1	\\x0000000100010000
13	2	0	\\xfe405efe163271d4a5b1f4733565d5b4b11aa536796409a0e7ca8bfc467fa6e857909e4ed13ed4c8002e551daa66100be8faa259ac61554623e9223d2c0f5308	181	\\x00000001000001004325fce1153acfeb7bf3a94a3845e20fb9871e7a6754ea92ebd4fc358e09856922eaba5327a84fa00da87c986d7ace4575201f0b61a91c13c899cb473302c4d98c9d80ccead9597a401acae78f7d3ffa0272c4d5bd5b3286078ec8f2b161e1c57852b6d54d964d2cbc93e10aaa7289da1b61c38137d6fa19658eb97de3f325f7	\\xf4ac5a1607e471a5921d97bf65958b4acf6a1e051ce527cdd00a75a77f8cc373b5d8a420e23e970a98f93ff8f93c812cf847b7f1e9a4ff273ced9e2a2dfff525	\\x0000000100000001ad9618d1f673d8f7483f03fc15731a857c1bd906d33f3501df0d0e0f43f0b64850c98db183fbda11da6ceca16a0fd8133409ab18374969810cd200804f6ddfbab112923d3d81be1d05a6d1ac0f2004de31695176d57252e7f4038a1073dc31f7728a994bfbe28b0128285ef266c0ff639a12d1e0b67b45169df80bced2cc555c	\\x0000000100010000
14	2	1	\\xebf0546b2c9947a411118546797889bb108b710ec485de5d29823edb148ccfcc03b31784fc7e4eeb24fc8878da4a9e5045e145f194e098857e3b4eb30272e806	336	\\x0000000100000100bd93b04a9e33df27f05e7b3433e11b307c256b4aaca47273db3cf635c46aaa879488b9f2e45be193481e74a20150bad2298540c2ed45dd3ec15ff88c7561ae89f1a20d666e56931629175805edec55e2827ec23256f9d201b98648ea7ca3d0ff1e8516007838369741d60f47240ed0feaea10c6d828a3e093022aed7f7dfde96	\\xa687cb3d7a43ecf75f4af1c96a26f2b91bff17a4a66ff03dc6534e6be76e037fc975d15a02cd4789e8b1ba4eb7c3544cacc9395ad8a15ddd02756e590284414a	\\x00000001000000017250c532fe04de558dbef52e1a907798f28152ad2f8d44cc364c7d11af7be63bdf43ae8fcca08ea54a0e7d87059ccfe00b227493a5a9687c8f466b9538b6f1b28782d74642d2e66706f845237fba41ddd19772864d0508c6e790997f14a13c9faf32efaa501ac672f9620e287ef2529454630fa52843678255c5acfd094212d3	\\x0000000100010000
15	2	2	\\xe0b3fad5a8cbc85263dad6ed3813790ed743e68b1bb0727b10a2f7e3f9b0072a1edf93e7c51039bb32ae6f2ec4d14d1a6a8080735624c005f76fdadd6803840e	336	\\x0000000100000100857d0694907ad2f105dd7c30665169e201acb7c244992369ca83e4a47683fc7f9e58e8e6f2e76518a9e4172eab84e4fcef0aff68ca039468e1b15281cfc5ad1b5f5ddd3c0d3d68888394be4718523f8ecd49b6a6b7b94bf782cf93c7dc03f5ae91e12c63726e994ad3996bc76a174ed5f183f315cd06e654fbbde522d900ec23	\\xfaa9b35f6f9e805b9065bd146200d6666dafe42049082123e3ce3ccc2463507d2680a098fcd125a0d59e4d5719037974a9305721ce92cd5b55a538ff36053128	\\x00000001000000012ce8321ff11c24fe7177bb9becd7832655bf0a9877663155f90bd06b29a69817493847da5968c93c344496beac850629f4221a8cfbc290947f9c78da4d6a0b2269360b75046d1a4e57af3a40f400b26e8b5a21635f0d55b0067970e6224804ed8fba5743a39a72ccb52185a5431629d172dae40ae1937365d5dd641c9c49d0d2	\\x0000000100010000
16	2	3	\\xea7f4680fb020bf5050b9f10ed0002161e68e2fdc89b41f3e6c005b5f57d4d4ac4a2a4bce015acc029a3c6664ae77d208f68da5fec94517c19a036740055070d	336	\\x000000010000010098a42db40900254934612d33340478bb0959af0224b2aeb0196173efd0f41fd53f7ef2e062fae9fc738a95343523aecebe6e54611eb89c3e96447cc9c67c578d3abdedd2705b33b6c9d25bee960c91374baa743b70f3ba813be113b288d436c87c0404ec65d8e2601ccb5ddec9383b596a4b579b49c054d7e6c73049a4aff385	\\xc400938a4316b02ce74c547015296f50d9635425b7ff7fa5130b9d8e676afc47845c6ed15de1c08a7811b5ba4a3ec77ba78231d79f40c20d9aff9f6055317988	\\x000000010000000137d31922d1b9ccf6d187f1404d8fc7c64114a995666b6fe2621e910b8a63d69837db71702d49ddaea5ddc904b16a20771357510f56d8ffe0bafa88976a1330ffc2d451e257e6af81d29bda422ba2dc5660e842d07d20079f14dcb60ab8efcf90e8586de4b47903a3cc0d4e9f32e9a8bf3b39c25c10bc6fcdf739c0fd1bbe625a	\\x0000000100010000
17	2	4	\\x76a5419593e817c0336e433487332641a741f348b2f5f2de9d81d0ab64d05143dce35fb2c94b804e7066ee7dc3507c931501e5751c753f7daafae3f89770080a	336	\\x000000010000010047ff0f12f1fd6ad187a074bab3577a54580564400e8e41cd8e15e6c3e47ea7b3663065254674c5a83714dd9a466f3bc5e80e994805e7cd18f39fe70ac2363aeef5e125f7e2c73eb6da3f308f86fac2e287e149b25e2723f3fb9cbd1dd62d6fb96bf01bddaa98be179c84c39be14bd1d5dc59275de55b64379b02b29b71c6602c	\\x9905bc943a8bbf326a00ac173142ae64322e33dbcdef2a0bd8d386bd046a670979c6088f31542f4be765d67ee2fea63bd7cc3a5c11d809465c543b2297a955ed	\\x000000010000000150619c846c01a96951e910c4a940cdb0eb3e6daa249dbcfbf40b8ea7b5095df92e938b599cefb8032423a5235b315daef7da76100c536f7b0043f66d03d4f46df99333aefac1175596275779bc85a1abf5f6fb7dd673fc168ceaa3dee3272ec8f76ae769b966b7f5fd2b7f1f30354a882de7b0f76bcfd6172b9b429bb07f792d	\\x0000000100010000
18	2	5	\\xd1e011d4c9f241cbecbbf29404c5a782ca48d51349d07edff007e048d28b7400fc00cfcf57752a35a1e20552817b52188e0bb42c4a78f6f3f50e0066df31d50c	336	\\x00000001000001009171f02e893482db8aaabd1fad28f8979cae23cd2761f1343c4daf73406586d60320bcaece41643c872bb3d1da765d0c97fd77b33ca02f4c6f56d0469cc2b9bd664b42f6308a28629bb07d9798b81b76b4e65352811e430f310accc5a0c3ace80f5b878c3461deccabce3be8684879e43772f740df1ded5f0d5b68566d363925	\\x9626cbccf09ad30e13c61a3e3cf8800e65f4e6963f656af50d7504175054e3b982ca9a5a935500e2a7703d2ea82b1b1f39b44887e5b580c49dde2b216991e1c1	\\x00000001000000010bb11fdf7308bd764e67a76ca8399835ab197f0200d0932d66629e3f99a87e82d3f168c79b640c3ed62bb3c1359045a6c3ec2db330123dafb1cdfbfc71363cb29ae44d0a63d5b8dbea33fb735a45e857c3a40ef4088f72f7547c3070d8217f21ac1c96cef079c1e0171fee8349c34eaa7c24efe4fc9ef474098465037b5235c5	\\x0000000100010000
19	2	6	\\x94fcb2c8d46ba5c39ba894521f40e2629d49b945740319e221359fb0c6289ea266fd81014ca170fcf3b7e057dd449ac5336269fe01a30a1b14536f0bef78df06	336	\\x0000000100000100707da593ab78e6133b613ae5e37425e4f9936780bf901055c8af2349c8570dce8b49c7228f2b5703cc40371c208e9268060559eda8a0ff9cced8918e9818cfa1858a809ab1644d65da67ef91ffe4098e04546fcf9bcb3f0934f0e00bcae4056559dee5230bb75912194e6aafd69c8af7b1271144e3feca9183e1f364a6724871	\\xfb53b0e8e5444bcd49e6be1c131f5788b9bdc12eb2647745f995d15e6833f0f87b80e97c9c3ff128f66471d47d6ff8bb40bc3ebdbe3aa21eb406d67cd691fe29	\\x00000001000000011809e46acca30ead2a1d64a569fb4caf7804ff5c63231517ad99d1128aa81a3eb57864b2e13e1b48146286ed9fbd077bb4704b2d6c2b9403306e706853b1947bca69237a7f421d11afc04e5d4a3079850b77b621dcf3b0204590638ff21d55c585dbd57307458e0142378c2d4717ff9762f60361fab3df5726ffb06221668724	\\x0000000100010000
20	2	7	\\xcb822054eadd88574d94a9047b5520af65e24ecbd7379089ce7344aeaf1e47051c0192ea615384e73b43d2557d0baa734828e0f90e6294e0271d9e48a57fa407	336	\\x000000010000010062e9192ec747d4b68e3b47b0c4a12566fbd73fadd4b8cb709b312462c40811e0b36add7566a9306b30a27ab6477ba17579d73a83f8d553647ebe6a6777de09c1eab6e172fdb9fb021d46865a2fcf79ea92a78a246050b1846d0768d51a137e965127b471bd7f85c8e082a727ce5ef9999c9d3a37beb166a970bec0b37ad18e8b	\\x4d49e62cc152ac071a9483803fe0d1ddb55b6db9c4de5b65221048b4082d556b76984073024abf1f9e5b3a2977ba0bd8f9c6c57e98e586b8c07b03ace0cfc3db	\\x0000000100000001c2a666eb74c4af572e2a2420a495fc3bdd40fccd14abc9029a728fee28faaa5cfa672eba9bb2e8a364d682daa317dc715b2aa8f4987b0458b0ace9d2214a16787df367f7a3f8b833102b59d239385500e3ddf1347c29ddeaceaed13c15aa0861daac242838bec666126e4e279f4a9be7a627ae5f3d77982f7140151f32f46a52	\\x0000000100010000
21	2	8	\\xeebf4557bb2af1618eb6d3055b06d45dac869b1d3251920c3dd0e6efc526d23e3cf0d8279114defbc854717931da4e941ad594b0b9aeff3ea1b81f20c3620b0d	336	\\x0000000100000100c6f77f85d5cc494caceb195e7d6fb83dcd42b255c656b6cc16ef9a588dfe756406659df755dc083d5a14c352441486d10e1ca082a3915debe4b1dcdf41d031fd8c587a715f706ea23ac6158d48fa230e43e81cef9d3f5f291207dfd05fcae8283070f36a6d6c941f77e9760dc8738364f7a02939971fc514de625f7dca47adc9	\\xf9e613591c4641e9014c1945588eb45f00d6d82833051b052b00790f90eec45a4e2f7ba03bd90b41dbe0e6c761b3a15f70e41ca245b13bb557c871d0228a5d3f	\\x000000010000000139a584b1f07eaab72037b7018064fae3c97b49c554061ab04ddd0977f959a875656a2dc32f21dbd7d817aa3cfee7906eb683017b9baf14559c1cb9b2199a6d3fd239aa1974c2d26298d33961dba27ed97fd94898832e10b25377088f56d80f579157614ebf10169fe56b9a19c45a427dc6f3bac5b37775fd2c03eaa5ab7af726	\\x0000000100010000
22	2	9	\\x31735c2b1de56639ad816f9f9259a76835c7a75706b6f3089ba8d96d7998cc6a10d469ea5c430ecb0bdcc069a7f7a1ac1a55e209078a58d3f329a5afc24ea501	206	\\x00000001000001005438a26255abad1bf574bfd4d3d87e69bf5d9e2dfeb1c22bf4d19c5f98cc79ba796fdfb0c99c805cc55e13e8e68d3427aab2a1944224b522839a2d0f8919a7364e1670ef7d20c8555e43e6d97cde00f010909cc08810c35f98b9c22890aa90592a5b8f72b90566a52e1ffa65852d8b4f74ae8e072c13b271b837bfcb9346043f	\\x13cf6bbc9fe74d4f01e21de6514a48b7d090e9b6fb1c4bbcf60414b16e955fc07ef9d96d18262cf70cb75f15004828daeb722287d6c7a26736fb13df2e9cfe9e	\\x0000000100000001716e42bc00930f49e0ad336b200697cee82f769c41fc527f3573ba14a31a08bfba0021954da5f20ab18414ad541d70810884505dd4012bb90ede846355a4258859f4e5d9ab9daf14481c6628840e752b354b076e0d4aaceed92fb859375556b0f7eba9d4f13f22e22012b5a6b85e30541b83648675292fa839ca6e740ee8469c	\\x0000000100010000
23	2	10	\\x0ed67ab920ca94daccfc0a2a65f4e69c58d3500f3789e38fe2fbf7da4fad92a3b7017667413dc53a4d3c7bd8de441e3cc9174145c4239e272f044e7518995604	206	\\x00000001000001007405341f75fb47b46dec51c1da3fba001fda7b4c7826de1612b9677b2c2d69031c266abc795516cd3d7abafad8c5e50337c61c00fc2a4feb60a4467a9a199af7820170f89c3bf265fb5ee77f5cae6bc392f59a0fbd7f3f934eeb98245ff56f66e0af95fd3242b8d277dfdf8ed008e9eec89efb218c305a10906ae18f16e59b15	\\xdc8058356af53231b0529446300cdb7791f23a1c4c9f73609ceabd2840704d142b9f11449ce6fbadac6b28bdac4978805f5a843ec8c8d1be74e59b623d0f3853	\\x00000001000000012543c38a12480f15eddf857666f9074093aebde8fc895172bee389aa5e4933c7e1f1f7e88dabc19a7df5a9c4bba6d0855cefcd96fa46fde707d335965041ee5979055afa35746df6bf7025b42d925ec79e739a029bc30ce9195d8bdbc00eee61cb33b0a0ee9d2819110f27085c50b10077efa24717534f697a3cc80ff5569498	\\x0000000100010000
24	2	11	\\x1546d9fb204949437ca0f98b7b14abf2bce43787f745cfb662dc7981d31cd5c7515ea57211e68b46228f9a2d4619590af38d0205ef751065192fe68f8ef7000d	206	\\x000000010000010023190d7aef384b26eb4264b79db8970259a6cfd1c52c61a86321f827785703b1864a80180125da6a427c41e58318c1f44a59ade0ea4db08bf858d2aa04311cd9d960ba9daaf360e452d900d34efb418656b3f6038e56d4ac01be63d589afd19ad30256d27c721d1fac8b64cb69d2ce18b98511e3df754e2419c970ccac8d5991	\\x5bd7e4196bd9fac0b142c1efcad886e0b7270c300c6674866d115a0007227e640bae873752367485259c460a98c9393fe710a12b572a15a82e0321b4ffa24034	\\x00000001000000014dedcbf68750461bb833848891a2e9e6effe8c05d9287ba63e2fd381f9c1ca345c41548cd54b8ebdbdbb3fd299a43219219bb84dca0c0263d1bea402078c73cf3a003c25ab7553d18c7a78ad274e607f802372b4730d4224e858cb38db453c34a8b2b1531fdc45f67b4543aea071bd1f5a16d2be9c4588958a59659d699a7a4e	\\x0000000100010000
25	3	0	\\x94c120ea50115f7391af0351e9abeaa6f64e83e262a0a5d3fc38c65ddbf817a7cea1f9cb4b9f1a71ded0abee901ec48617b3e73d3e38539b971903ee72262d09	327	\\x000000010000010087965bd8521883fc1da31fe1fa61bc62c28d82f8eedbbf965a54952ea0ebe89ccf2383347964d3084e1e1a8f2eddfe3cc1b25111d0ade42775ea9520261f9ce97b42ed4daa427595aec072adc0a8eeea4045282a13eaf3d62a852ccbcea7a99d2bb234e4ba03b14d6deee7ccc9cbb268d171206193f43260c2d2cdcd54ba7c68	\\xe9b05b6ea7442e274dbe522c78d3f8b0a769b6d79e7718779c3a0fd1886791c8f5df9272c6acb93644223d42f42f8700038cdc45439f4564394495a51d578429	\\x000000010000000170eb2d1e88a9c51e7b12c30de55c2ae9a58001584a573f681e3992cec20655be785432e13e9d5e874ad63c30e8cb22063bb07d7526826115ae5dfd3d8f5e548b6ace03b046cca938012f9be5c6a4b6b9eecf25f5d2eca528d9b8305a329a31289982bf8c4e4e0e54e82ab86f1fdc4b8ecc2bea54a7b7b32bc9866eb8efbd189e	\\x0000000100010000
26	3	1	\\xdcaa335949cb21be3dbfc6e01a6ca8a3f663f8f11b7b2901a4b7bfa805aca2fe899e012218100f703e903591d4ba0dd234a48ddd969a575362758aa0872e0405	336	\\x00000001000001006beeaf68af65f9f496f4cbafc53f4772a60993dd4df9d025d779c792b1450519e7e41712b9d82d17e35c3240d387ab2116f3c43193b19b2b0fdf0a0abbc6c58be390c20bcf8dd3195d263a1f01ec1e0e2e10e7b1e75487d80fa5aadffd74bb0c56596b23a7e7b114b1b7541ea597f66eae35654e088e18518c7089ab9bdf394e	\\x4a9f1383c940d8feb4f58c830a7dd364bbc4abf588300ffcd054dc5c2fa0ee137137c1910e533b5a52287f7885a64649d0583a6c330cc4d29749b3c2a3ff4086	\\x00000001000000013c00d85db6e950d5879fec6463418b00aa7d9b1ad9c9c2959fe6104e0a655f996e6960c8155258d9c4615678380ebec27111fc812a73df56275bb3728176d69e890bee75608babcb86dd9f64d58b547f1e66624aa3073d9585d7ac41cef19c08c84000aac4d246ce9d2fd22615d204bdf6e2f593ad41a165eeb5ac298cb68c0f	\\x0000000100010000
27	3	2	\\x2fba1046cdf9fd97856bc9a216958b313c34334e71f889b86bc575327bdac4783fdac04c141ed9e59921917695f79e4b824075db71e6e7d2756bb3d85cdb9c05	336	\\x000000010000010094e373067ec3fea2e9a8fb3e0c6f8952700e4c565e94501fda3e57fa121d04098ae5313ea7574c15b967805d49b7658d67fedf6048a381950f62d217c39d83aff358eca748929edc2c9848c859953d9388f43359cf90ae973ec2503353cbca72179f0a7f0d294c2762a7b71209b6f575b3f4b3c137dabaf453acdb73147a509d	\\x1e1fb05154c66bdb80fed1662bc734cd3b3b85206d54fb5e40850522882cc584b7c525aee0bb962fa96fd828b53410cb787b8f459caad96872e7a07684332f9b	\\x00000001000000018694f9e19e494f8f841598f05ee766a9f371034a47c394928bc715fd0f1ed017f8bfbad69bade77be7d06da42862226b23ce0caeb1ca2dfd999641b9b7eca1df8c82315b33b999084c1af174436e092a956cb0d3da139a3b2164a82d5e4ec28c9c2c96c98814e5a9fefcc41ef3ab724d51412fde91100505fa31a913da45aa68	\\x0000000100010000
28	3	3	\\xd5ec507aaf379a3bbf5f444a426726553da998404c8378bcd69a5a75f794a59c8d3872f3b5a43ac9af1aa8e2a0cc420d6bd318a52968eaa5eb5e206bc08d8905	336	\\x00000001000001002732305a717843d1049c0c537155c8adf27235ecaed7dfba2ac1fb85506a82ba1e583267b876d6d982f6b32c167493fddfafc8dc012a45d123c0f2ea3c5e6f051e25ccb79c5ef9a5a6da9e0f68ba85b893fb8fec271f43a8fad1d0ad85f12ab768686f9214b3094fde218d1392e062493505c8f24cf8403dc0ac8406e066b850	\\xd1af660fe96894e2925aa03a2739b9bbeb14f70dfa5e6c4b8960eccfbd00d3757a9a9fe3017fd70f4050c55fbc24829ebc58b0d436067928c7387b4500be21f8	\\x000000010000000158d47756b661b8bb6c67f43867e13608030bb878cd314e555089567a2726abde9b7cd46dbb43f6fd456895c01b0b339bdd6621e4b6b1bf6eae3445de72f9e2cd88e536ca9649248c79a28c91a64395556d49ce6e760e47b5fedd8b2f83a0ee6ffe777961dac1a9b3ff966199ea946c556ec79344c222e68bb3154cdcbbaaa1b6	\\x0000000100010000
29	3	4	\\xcf2394ff0c87ba7fa0b96b298893a97dc17929a6ea3e5f6d2c06f6600f3e466043d46e1c3de44b9316559eefe1501c0c16dfb3ea5b6a7fc46cf07271f5ff7f01	336	\\x000000010000010087f585c2f7eab57c9eb50dc59634abcd7799d21ea249499f901a4f55a00a7dcfd504882f28d86e6af96672192d040927ea08032a51ff4f5ec5e3fc289d468d023cf6bc44a20019d915aa3ed87659bb23b27091d5198969c471b593c547702cffdf97d44bfca27856ac35f46728259acbb326b5a638f1fa2896764a8cf95031de	\\x19ba2a420994fb39d06bd669b08dba4094e6840521ffe4040c6fc178c683e55d5100f04ea5d5b84509cba4a15e60afe8f883f754cf416028679f127f0c8921d9	\\x000000010000000115383f6bb20af06a744519c2da3c320d541f9b708ff0ad4379738969796d4b630ec7e50f0e32ef5039070ed938a8d9bcf1033bb21fb17c5f78a6cc6efd78d3bd48afb7ff2be0f66ff62a4039a937bcd75640600193972cae81b1085edd03a7e4df383380f4c447c8fde44c6cf394dbfce2a509ae6a39064918b701d319c25517	\\x0000000100010000
30	3	5	\\xe9b6c199588db28ee79579d374d2b8efbb3d87bebc38f7d2f4624b75a3e81487f577cbae8252c031abde15ce6bd37473580ce91727aa0de8d68ec449e93f4706	336	\\x0000000100000100319755a237f76993ffa717c52e4723e586af2cc89aded25edeb3f73cf06db6ace15c32a15c17847458eb4a6d032ce7dc7817eb36963e26541d6535275a451d03d9752b5416fadd5bb78407ed8bdfd6a428a05dd09abba6318e0fa0a05bb6c5d251aca426ab674a566bd9154b6d77294cd2911991412be7ac603fd0e3f5661eb5	\\x4e7837d9ad9d3cd47c54068e1d478d0b2c6c24de8dc5b5c914a0a0e7f8d210f8e7429e9d7925e5b92f12b209a3306efe73f1a59a5d2fe996ead1fcdf139ea8d0	\\x000000010000000142a3d68fb857a76bf7c857a3a5b9d8e3e58dd317a53d811ea3d7ceb0929dfb57aa31c072c44e6941b04e957254509eeca15f73f69dc54e52370363db5488059ba35421cf0dac4f1316b4b8ea336735027620cded5f29c35ca40a14a6159e6d3a322c96b614ae61ad0201796fd71608651de4c07904e694ebbbdb7b575bab0a24	\\x0000000100010000
31	3	6	\\x83710e9e2979e786b961a166445554d7f6a79c5d75f3cf0adcf404d804e3d0720ae940570f27a91c5a485b1b7ddb6a7767d26da70b815876d4a912fb815d070d	336	\\x0000000100000100c0ed613045e26497af1d7f25d2388b471502790d923ef601100dd7e78e75c734a97fb0e13ec9e603cead31dd4d2ff71fc21db6aff429bdfed86b78537277e1b7d5e3b3f2ba814547ee4c88b4461e348408865711a0873673023b450971b2e5b71e201734355b2b1ff4194358e6c1420f23c174a34e121721de0757fbeca45722	\\x9af44725271fe501467bac9b27da7028da43e26bf589d57068fe7dfdfbe8a016c96cccf25c27a09aa5e09828a8acda15672f22096e9d7ef8e99b1149c68855de	\\x0000000100000001ccc6074bbb0bc9bc6c8ee2708abceb03ffd74338790f0a780ddbb8eee50f86ae27398b43b9ef4115b591747e92265ed825a1c3e5f74ddd0fd4641ebbb70036f82bd33166be985e3fb41ddbf3cc803eda641aede4c4e20a703617b15c3c30ebe85cbbff120905cff162f7c7064e38e997b71c5ea365e8d63ac54dbeced4fc877c	\\x0000000100010000
32	3	7	\\x9686c084b975adbf16faf3d6dabb3456e18fd96e9c58ee44a899039d9b8417f191f6b6f77298133af31a3648b633a1acb83b234225d8f8efcefd714a13ae700b	336	\\x0000000100000100c331ded74cf5e6289741f331786a60d826656f694de578430c1f40f707a48919c0ea343884291176144e4d672d15e5e577b2168bc3419e5c6221aa87f8ae903768db00862324c3dc16a9e144bb96d0ce2df4565073d7801deb796f65ed11837ada16b68d6de420eeb23db88e28eaf976ecbfddc3ab0e243c98383ae76e9d40e1	\\x1fbb64c29106237000b581abd81464183ae47d1812135d6e0ccb60853960d64682a77915c84a5099dade56bae509c57e60ff80c35e298b3f29251163ec01df36	\\x000000010000000107c6df2978ae1a1131c193407e8a1604253b8d5465f0c9523554875ee67a56d87619108b5b3360e3ee8730ec47c2a42edcd7fc672b6f85010acb14d852f67a74042d003206ed9dc8b44de898d714d1714e5d15ac9ab7e61784139b127b357f3dcc89892c864d7f5f3a676aec5e4bb288b4d6d0bad6fd78b38f126065a087cee5	\\x0000000100010000
33	3	8	\\xe72ef3f2f802d917e2efa4c6d82382b9514757545b69bc566be558b90993bbc4aaa69b04f6862b2a0fdc571e76ac22b4e28ee9cd00bd6a33711b7cd5c87c3f0f	336	\\x00000001000001002c1b5eae44b867833e59e4a9a54b8946dce158c422f136262c4982b18f1c39744730c5d6eab3bffb54d0f7aa0358421ca8ee03d4da215562a33bd6a14c6ce72d7feee36f98f84c4cd9bfef74478598493e65ffe3bf423b9851032f4d22e1d52b5c2ee438e22c0b0406c4cc51f5dab892604e0ccf925cd238bd4bfec3c931f54b	\\xa1bcb3f8c24a02c06f331df98cd479e522d77e6e5827ef6fe78712d6ded42400dd1dcf273d85e6c5dd1f00333227fb2492d15d941ed59f08e157d3e92d0e639b	\\x0000000100000001226a6c7950a33aff1dfadbcf9c0999436e54430abf759650414c343e131ce34fbf8a9d98fc26c68682dc6a8b9cbf015ac023591d475bd005e2f4a6ffa752c9a1991bec9b4657a45ae14d5ec4885faee11ab40bc9e85115bac83593739fc7527bcb389a7b275ab532077cf0f720e9b0ce48377f468586106458d75210bbace90c	\\x0000000100010000
34	3	9	\\x8de9b85e83b9b47e01a21f52cc78815136dfc3d21914abc8c762313934fa22197ef1863290b70875ec35f053ab11ee15b83c1289eed5a6129e87d9f50ace0009	206	\\x0000000100000100a868c8a0d49597161449804d4e7df194bcd548acb109abb7adbaae9d219485b81078162a878450372761be6f9564dd6627793c94bf88908e9d888377c08ce748750d893ba65529e6baef48efd7f2394e09a5222e30b2b3f2eeb9329c6a3898b5d66e90b963294c24871813e7eb377358b06bf042aaeb235f4fe4748b2773b708	\\x5a88baac07852f4492e5e4bea29cae34858f447c4b96c40739101321ce9f4fe6b73878870fa1808d8350904d183c56447ab588a735cf44c58eb117db33c814a3	\\x000000010000000196931c0591165c072195afbedae248998397e226c89879eb390d58233ed208972d25dfd5b1d28a18ab66ebf8f6a236371ed67c1c8eb9637fe6e8205beb828501522a1ead632af13eecee01fa34e763777f7dca6e504a30386dcc73d2d9c95ba0895b400f3b6d883dee2e95bafbd28fc01c71e086ba607574e84152ca40573eec	\\x0000000100010000
35	3	10	\\x627f0aeeb66d84b49f554eafbbb8139f5e32c988cbdf698e1195d8e39e864679041111fbfad911bb4ad715cd54fc76e0a2c712f7ee691b01c549cabde10c7e09	206	\\x00000001000001008f7ff34c00d719ec932406d50b6afa4056849a6affb5caff35bcb24dd556505b25a49c77a92abb34c65c6420709abfb36d07be70e5a4e6b37dc1e6cb742649fe70ae4b5bc8d22c4ccb35c9935cae394b78852051ccb6503700cd9cfe7eb356f9ba8b155553642a1fb618fda8d65b2eee913b87c4603cc20401ca5ef757732d89	\\xbfa5fb56455542a8cb8297cb9c4f8ed93ae1a986d9bfe0845c8ff7f38f1b7710d211d70be81f5483e6f0181caa559109e90ee89b8b3c5e65af0128521a7d3f40	\\x00000001000000017e60786fafbe796fbe16580bc2bfdc76dd9f161f1c79a9f0317faaa6a353b1d31c02169c87c7392d21c13ab098a5dd3e3870a525665390df8946d6b78fcc619ca226bb3afaf54dad33dadba551586c6079c28721b9a9fa3e0d137945d8ae91073d64b7cb85e120a0114b03eebeadf583f3ff8284d371d89d88ee4849f3a31484	\\x0000000100010000
36	3	11	\\x2bfdfb5da71e7ffcb3d70951092a3f65ada047e6edc3b4412ba8c704904819f537440fddf6f5f4e7a0d46d721bbf9b0add4f052926ec88ab874df1edcdefec0e	206	\\x00000001000001002ac1c8dbdab936e532d4d17a87f82ba94cc0f2a969ab1c9c02e0154362f82944c1ab3247f0855b2331b100733fb7934cb6e79cff0bcdd14582820efc8bbd6b069753ca85986fba35b0b47f487b2cc1622315433b5e305a6a3f5a2d11a9d0a26e35a937cce941b84b4b1750f3198b9854913d7a251115a369046f1418f905f917	\\x3acac30f9f5560e1a6883436ae7f4a4021abd1cf93d72ddc8eb7eecefe9c42acb8ad38436c7e3f7ef45266abb2fe1148fcb4574e3a047f39b59ba2ed76b7fddf	\\x0000000100000001289a54e892418fefe3f01528a7a3ed8214b9130a0f7f9830d1b06bebf8924aab22c86d3786947ba228224dcd6f292e333c54d53d28b0688ce8773489f9d8780e69f1e5471d869c3e9e354052c4f5c6321776ec2722cdbec4404c089fb186d030a1e7f860437a7818efe78ae96218ff2207012e299e426a153eedeb9a99ddb805	\\x0000000100010000
37	4	0	\\x7835868de84723c42eb186db32f26fdb631a42cb8728a3ac0cf60cec7b9f023c29576999c7d64c8211ec60dd98e4c06109d7994401c1d07476e77c7e9af7c20e	286	\\x00000001000001008e2908487d45e42a18c0db20c32e835190de92fc5d1cf4cd6205e1b7c536820f5e7279aef2532c1d3a041b7a910f958b07a02034a7beb90d616dc4c3e7d9c34fe7489a90e81aa940b359107e65cfa7a3d50f73353276222a75b7087f52dd1b2c3c240b0263f5ee666fe2445da85a6759447af2c174505da41df6c90291121911	\\x4b73c2f44fd7377ca9d2530fd1ff3677a363e137f875890736156fc8b7ccd4c00d0a674097a153a902ac35a1b398ab7818764a056424b3a423bf936e6e16b18c	\\x00000001000000010432eaa07982e9b3f254a2ecc8dba423ab7b698c169dc82dc9d7a1c1250d9aa6ec50aaca077cf0787deed745daa4346a7a18a74c7b839b4ffb0858513821d95c8c7e94a91a8b7265e93773d0bd3890c12960dd23d8d679b4bd17d744289b28e65b4e8ff8ebc809be755198819e8a59224410d079151a3348cc2ff1057a0196c0	\\x0000000100010000
38	4	1	\\x9ff79058491232f585f3dc61cd7dcb117d9fabd8fb69306357525665907b4496c9f1d3ea337ac26864cd4dcd28d9084e7d14b35f4314c20a093202da11152303	336	\\x000000010000010079e229c32876a7ad9ff4a2199406a69294274442d90891b2b1c5c543c32c3610e82496ff33d0894e291b665f969cd756b40b44c1d37f604dfd5efc1706b52d0c94d4610e499929acaec5ce617eeffd9f09c18c1f34061611832e6e95bdf324d99ac69c32ec570a347c0354d073ef48e34387c2a5dc3db2bf49bf776ec973441e	\\x66deb1b9c4446be51571a10243cd3d7b660583294f6d22b81f66ac8680cbdfb635a1d5b31577cf9c1c168f1e6e2ec830e6e29ae87337d066945fde8478e147a7	\\x000000010000000153cb2f5040c2a4f6dcd73b56f0d8213afb42c505e1bff911d880a90a6eae609b2ccd9e31caa204954faaead3271cdf4455a0351994f9ba74f20e4e98f50135f067180584d1b8afc1d4fd21a92983ef107d1a5ba856291df395fe7f4c61efb71e77bd03f88ad070a118290241a26ba989b55dd8d92a594ccd0db16cee86eee23f	\\x0000000100010000
39	4	2	\\xafdf74b3b590e684bd545c0995b0d135e6adf95cbb3bd4fd8b85229405240ee3d4cb58e315f2b4f1f320e7518208de0c04f5d6a0a6b5724962ba5ab2cd9fe108	336	\\x0000000100000100645c229fb49a783bbb4b19a2f48356cc23b77f5f3678dae25275de79194a29c836028a572fdba98b2fc59a9c37012a77b634bc3ad4972b021d31718caaa787b9b43d865af3729e141946b6eecdfdcec12f65a73393bf656678a5ad73844ca197e90d8685c59a4517c5b5fc06343a14e79f67a24c982f7c449d44a50df34191dc	\\x343262a61ecec4c3fe88ac8c5e866cd41258e1a6915c9391ed13e4549dc839c9fa8d75bdeb031f4bdf6ad691f4743681b46c02f93acc3e079a93eb7162c44990	\\x00000001000000017135fb9de2f920ebb857a1380e18336ecc50a6e080b367d48d735c12b1263f83555a81e419d414b7486da1b8559a92b3765bb5237c1b35024d7bb10357ea12722abfbed9749bcbfaa5ccdd9954d36e7756854c79ec21d7c718839b9cda27f68ea8a9d3bfbd7c6b8f12ee3c2e4a20b1c890cc685a18194d6f8f8392688bbceb46	\\x0000000100010000
40	4	3	\\xbe16a2036f88eef68167d2c60950b1f983ffaecbd16a60348e11a25ffdc4fc375d24f648d50a8f9ac1b64b3b577639506c9638427cc85db68838130a02f67801	336	\\x00000001000001008edda8a1ed260323f18d3e6483646737c412cd807f9e15dc87413c18c12e5bbcb8dd5ba7aac848e9bc5dc87c5e8ebf7057178b441b8e6d33b082936005944eb91ac3213916d74ac08f9ec3adbfc3186256fe8e4b136cc58d1ea379ee4cfb600885d66d7ae390601f107028e125ec1da92a2656d1be0a46b3bd14931a70627976	\\x782af268e6e67ba28e6e92c325e9be721d75180c03d2567dd421f4fa374eaa6e543aa1d31cc5026657dd7cccfd5cba1888af0f60baffc0ee4a33513ccbcf3afb	\\x00000001000000012ca35e5565cf6736e88c6a046c277cf21846c90d8198b24227831d45a7d5dea733a8e5e76deda395a3ce7ab25195ddb8b7276dbb554ed15e1f496e5f33fb629a86f75831f9dd255dd3203ebd6dc6a7df65e9aa8e06d1ecd76a28c6a3fb2281f0a225ea7efcd2673329fe3db94af718bef347a3a42627af75bd86b0720dca514e	\\x0000000100010000
41	4	4	\\x7d7c1938b91d4b982520d57fabcf94ebdb965acdc3a4e980d9c0fd9953bd5675ab444549eb1ab522f578ec872658446161a8a24da6fa5772af816a804f24ca03	336	\\x0000000100000100b9afc496871bc0f23aa16f32c6eb1ef343ccecbb1b5801e7a42400d8489101de47bece47f66000bcad4a46ac1a36ea40dae14b2eff4e9cf4040e886bb77df585c316263303dc768d535f8bc436ac145203cdf6979a77fda77b6ec35e0f06ff1d01530ccdc6866740ec1d92dea6d50870eef9fc5b8de3ad16586e96781000bcd0	\\x855999104c681395fd8099213b9cd753edcefceb43327395cf11072f82877ae3fe407f7f1c712d2c438db7cd1d274ff43f397635106e4746c1f6d1d502fc5548	\\x0000000100000001c4dd6df61166db6b4cde3aef8d95872aca900e6e3b195429555ad32c0ae23c2433534db9b9d9a898d56c5704f2edfed2fbfeb12a88731f10ea1b19cf55c5d0345767ef63981524ccfe9620bf3a9323549ad180d179d11741ac9bc921c806d913b7a6abb11d8819490e80c24e68f0322ee8469fa29785b9bbe9ce4fdcc9754e9d	\\x0000000100010000
42	4	5	\\x6c6e557a4b64ebc522752c65ee37cd5c7d3edead964ac450336744d80ed1da4f21650e4e530521fc5ae073e285771d4c0c55e3edea2d22e144be549760cb890d	336	\\x0000000100000100b5a8997784ef7e64ef767dc6a826be4f60542d49dba4c0a37630fb54e14569b4ce55c5110e326585d380b22deda2fce00155665b9eb977d20103685f83ee3820cb82e0520babb3d4851b5b2f6260165d7818cf7ba758a3fb8883d4aa6a23bb5fec9ba2f6191b0ea7820ea591ea2182bb409689b973a27495ec99eda6bcc3bbbe	\\x430c1e92f9bedc72fc969d85a7722aac3f4e7f87e63f2c007076644c9c11d8e45d80f39b94a840122cafc543fea12c6b0180905cd02cbbcb83ffd77da2fc3891	\\x00000001000000016ade5033cbe021b4cfc5528f53ce48854c7e3dbb9e26d2c97db0779389ccd031a6a878938bfe93cdc4d1c9e3cbf5252dfa9e76cf92ec1d297be86064d2ee0557fdf9255d5784c2e0b72498fa4158aba42c48837ef69e3478d7f08218372292369007c94110e3d4c1682793674a251a6aa63822d46c5f12750883910d982b83ae	\\x0000000100010000
43	4	6	\\x990be704b8134b90c173b83b6cca0809f284ceef6a636fa38e68a7d8d0735a377211defff81906394973fab65a92ec2ea78b3795ffb566fa602b951972076f08	336	\\x00000001000001002ea85376fd8b9b11c3cb48ea3076547533d9ccfd9dbd0619b03a957a0b772ada457b8ec4710d311758a84ece012c9271004cb5088607cad2cfd952ddeb91b5e0ef922f5e7d09cbd5ce71f07cd3002027903e17a536e4317b3d4b721b25ea3fc637f6d1b4082e5bcd46c197b9af36714134035937a9d0d2e8af870c2a949fe760	\\xf95ff7cb587be62d80a4a419a12c1f30d608b49db095f616e21fbc6489fe46576a196ee9c0a50c42c34e25e10e0ead782dae9b86f0e6b5af61d871162146afdb	\\x0000000100000001c4a0116141ee569e7475eaa9723bb817acacd7c1cf9c9b1885babfe4014e6933ef0347c17c9b71d73c5df6791f80b955bfad0f8b1c9147cd0a680adc4c7cd879a0ebfd3cbf6e9ff97fb7ae5a2da5f7976cb8aea5fa34e0f2571fcaca92246418947061c7ff3bf5f31f9f11c6db01ed5e9def2ca66bd2a1530fb4c3cc21ec04a7	\\x0000000100010000
44	4	7	\\x62a545d7987dad458f0ed2ca8982f9657c4866d9bcebf6bfb7f20e30ce7cab030494c1e0903b043b18ab9957db88be396094c237f9354fdbd6210dbce1cc9008	336	\\x0000000100000100c4508f96a9171199823f5f993b92e4a6e7da14edb302ccd219ed41a9cf564dacfad1de34e8a57c5631204e70cbc73acf142f9b7f2ff78f71f303b5380f08df4b7cecc08a0266eeb99769175dce04fb77ebc4d5527652154b07c8fe2374c7b42398949c02b528c7a1d72c1bf7d6ece3f96116f4884dc6851c072a00e6a726fae8	\\xc23c0441d1e563c9ae7f130a4cba14256b6e6b3ab4889015dd05ff8d229594bf501df8bd31c0fce6d05505ad2600f3c8bcceb53f44cad5308563397c351c0223	\\x0000000100000001b3cb8116dc85f1c85de8b25753c65c9ceeba67482df2cb14e61f1864b13d61dd05989206c51a84666c5ab3ec390d4ce5042f95df72ba20407d3cfb4b3bd7ae24741980bbc392676f56010dc31639517ea9663ec0bbf0ceb76a1464a3f00e5fbd88ce3e9cc67d052ec5f1aae874677500556780a83b3dc9a5f426fb29596762e3	\\x0000000100010000
45	4	8	\\xaa2b4d6a465ec4c8c823697cd80150fb5e306b30edb395c67169f715ba7754e1cdcf53fd7b70376d40d62987e900748dae516978de4b1c5c864ef660e4c66303	336	\\x0000000100000100c4c9d2211fff3961c2d1c5029400e40be40d14ec9579b043e68e94c713a9a99081f7accf3f2d1a678e49f26ef2e4693fe5d12bbcc6c838b132f268a6874693d0dc7f2966588cf5c84a75ce6f9beef23b853c92c4bd990b1dd2ad293e04c96b9aeb86d2cc20ce546a6291cee190722720dad39d9707bebd92754a239096fa53ab	\\x357068c19ba245184d8e34a298f4e0b1c0e37a8dd2650063e608ad02084c92d6b373c3ae9f4bc6c6944ba80cbd693bd39764f9d94c5a4faf1eeb8e1c331590b7	\\x0000000100000001a898e4676d58dbba1770cb6fc265612ac0288be0cf5dd4a9b844341cf02698f5f85278a91ca2bf7b669a58b103b46418c50befde5344d7ff5cf939bb9e7937508a893b3b36f38d884ba25b996b9081decf6e87fef824ce49bf750af94d4b587d9750d406f000945b1664f8afe274e8e5f5cddc6c3a1b10c84241d70743a2d1ea	\\x0000000100010000
46	4	9	\\x3da9d35a0a1a5bd1a5f0b538678fb5f044bf35fa40dbb8307319560ed1e2a9937d3c45b8e93fe036753bf3052e5a014f0ccd941ad76a87191f349d05539f3101	206	\\x00000001000001007de507b03f27284fa23011ca994c225ba4a3e44fb2203e97643f0a97f9efc3bcf48e70d1ce2b9565aa4260b2084961b6c4867a306267dad1fde3ab2e911a408417b6c7b5f0ec1cba12ee0a3b8010ef9f6d365b6dc8098e52cd1e776862b1888f28b8ab6eed91e708330c22adb4cd30d8f9249cdf9755022fc1d3cbd18abebee5	\\x88e17880beb3a54df3a82bf31891af443bbcf5d4d2c2e372a23409adb2acfc60eeef554a6a5d6236f0622804d21763fce9cb22aa90c00aecddef6faae84134b7	\\x0000000100000001634fd7db6fdade9b13183701b73d1ebbbcce907bd02c0287abebdfca61d96b03d074adda8228c88c6a293238e1ca4dc34d53f6a982403381f515c6e01ab82eb4a83138b0980185379547dfa36d254578463e7436cb6872d03edfba6471e9941c8ae903598224a83def0eebc2d415ed2ac9d390d7b33f3a981040de7d6caf3041	\\x0000000100010000
47	4	10	\\xeff24ac23df31dbf02bd866f6fcef632881127568f843953e8f7c0033fce7cd500c31a36b94b734954b08edea7ddebda1115e24d0e55ae8c9ce7aed424805108	206	\\x00000001000001009cefb80b85aba7f01b67662d55273e160637775046dcac46b74706e80c2c8e9b60a23c2c5fdb5460bab77a7cf8aed5bc7f6fa49769d2a2b1cd6781a0832662f34b3ae4d13d62720e1b76108f6d8bd666531dfad4db87d27fa3c316352a6e00e3401f6339e8f91519fa66525eb0828c3559e1e3453b626f7185528faffbfd5243	\\xa560fdd0d06d980fd9a921552cf41626c155b1e9cf82a07c538263714dd45f17449499f1e98b593196ec6cfff34096d817c390150117405b4cc0ce86a4ededbd	\\x00000001000000018226335cfe4000d3ea7d2c80af3d9bc5704a997df4a2fd3aa5fea642f74fdd815cf8ce9b38675957586f4d4103f31b36f427ee67696375cbba89f74920802b449a93fce952f9114219458549a06fced64ecfbb8f746d7b036305d4e9e4b87d7b605c7b13b8d3cfa53a12d5cce109e289feaf87738d634ab8cd7821442170d09d	\\x0000000100010000
48	4	11	\\x8adcbe7b0848f5f6721da37de71a7da20b677a913aa5f36db0d3f5092b94cf5707d33cc2681ec37ae5009af0f7835e519ce15c925284cb78cb9dd0908af2a10f	206	\\x00000001000001000293ce91fdd8fe598650ded31c66c2b7c0c596e61375dca05979c864084d57ea204c08f2ac22bb3548795f5c6eae13ea074b4d7441b63aff3ba8da86bff7c9445f3f54c5730dea555db5586612aab53b0667eedbc72325b3d77d1e9b172a97987898fa958733d2957429fcace6a4af96606f6dc1b87f5f2ca844ecc2179d715b	\\x9eddc27254c2ea7e3a15b01e92c02d3ae8ecf34ff08d320ee90f712d4f9e1f190d42bb8b5da90dc57c96801aee8a5784ddd7578fcad9a1f090a7b4540f07e6b8	\\x00000001000000011697880749519ff4ecb07a2823496102409038aa2eeed9395c8d0c7ba59428d70dffa65468d11747dd192d7b05c445005e7aeda28700727bfed7eb8e819189ac37f52d8e16ce36653a756a53b221679fdcdf8805707f397d9288a901ea95891535c058d8f8cf770244e3883c6775d37c7a3fe794138f9d17a3248242011b3f9c	\\x0000000100010000
\.


--
-- Data for Name: refresh_transfer_keys_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refresh_transfer_keys_default (rtc_serial, melt_serial_id, transfer_pub, transfer_privs) FROM stdin;
1	1	\\xe77220a96fea06ceab072c5c6cc71620c0354c109299a0eff7873456161e131d	\\xfe88d313fe89d8c79e96a2c0c5027d108c0556e8046ba2845a202c11b97f1271d3f1fb53690de78a7db85a6fb30a7f202e7efd592b22ecdbc7414d9d97f7e38d
2	2	\\xb0cae42fc52e068c60ad6332bd40d0b0a2a9a4d4508996a66b239d1eeeeda340	\\xc4ee51325c769ce753d4cccdecb695be7bdc910abd65b49542edabd5ad92d9a0f4cfbc2938dfe5f9b48b7b75f9aeb3743ad694a1aebc767e3d20581ac0e7df0f
3	3	\\xc8bde238f93ad88d152259c35db2e784fb382f2cbc7bcc686aabb9a10fd25523	\\x4a95625c45dd6edff67ed8f13f7eb8037b252ec448f0c2207e48a50c1b3db1fa99b6487ce582f45455f731945b7161db317ddbaf2e93b2b855543e6dacbdd624
4	4	\\xb3043d344e90bcbbb40511a86de455398dd08c5e6cba18dc85cfef051d167635	\\xad307bf3a544d7dd816a305ba38d381d4db9ed10082bf7f0487ab6a99c964c9e5a19f9b7e6ac1cd5fed5cb74746e5b22d7187b6ee80485eb9e5ef8551c912417
\.


--
-- Data for Name: refunds_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds_default (refund_serial_id, deposit_serial_id, merchant_sig, rtransaction_id, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	2	\\xfa47074a4acacb35b7521ed463608e41281dcb8a789e0813a0ff2ebfa4582bf827266e47871f578c7c2ba1670c6d68a29a300064816dc25e7cc43039d01d3203	1	6	0
\.


--
-- Data for Name: reserves_close_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_close_default (close_uuid, reserve_pub, execution_date, wtid, wire_target_serial_id, amount_val, amount_frac, closing_fee_val, closing_fee_frac) FROM stdin;
\.


--
-- Data for Name: reserves_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_default (reserve_uuid, reserve_pub, current_balance_val, current_balance_frac, expiration_date, gc_date) FROM stdin;
1	\\x33e073d2b56cae39892dd632a3935b74d18dbb41912e49ccb74281694da3d1b2	0	1000000	1648462021000000	1866794824000000
2	\\x5de4b73c0a2e76039a06b093313d701dd68ee087c09d1ef49437cfd4a83b3423	0	1000000	1648462028000000	1866794830000000
\.


--
-- Data for Name: reserves_in_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_in_default (reserve_in_serial_id, reserve_pub, wire_reference, credit_val, credit_frac, wire_source_serial_id, exchange_account_section, execution_date) FROM stdin;
1	\\x33e073d2b56cae39892dd632a3935b74d18dbb41912e49ccb74281694da3d1b2	2	10	0	1	exchange-account-1	1646042821000000
2	\\x5de4b73c0a2e76039a06b093313d701dd68ee087c09d1ef49437cfd4a83b3423	4	18	0	3	exchange-account-1	1646042828000000
\.


--
-- Data for Name: reserves_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reserves_out_default (reserve_out_serial_id, h_blind_ev, denominations_serial, denom_sig, reserve_uuid, reserve_sig, execution_date, amount_with_fee_val, amount_with_fee_frac) FROM stdin;
1	\\xd1cf3946ee1b71ac68c8d8dec6ddefae7286c099a0b87372834de75b9d6353589150f8270db75e94bce5238476a32c1d969084c7a30532fc7a04c647cf726e25	151	\\x000000010000000156e2d6b2fa87f45e23c516131b0dea07b942604d09d71efdd249410941568c2022ed2a0323cd52f5c69c00161e2f7cf3e74c881a459867f180c553223b2de6528afb830316cba5c565eb9836238f3ddfda7245cdcfbac839689861e41c65c2e351b767cfe7babb7517caa3906a5c3e61cd6d3f594f394f76fbd1342219b8f207	1	\\x168783a90d5cf930b829292e107b8cd57d78916a8e13fb5ef9609e3033ea5a807464e3e1d1b350befc0bf0a5824766df7ec1b36dc9e918acb96d3ea2b06c300d	1646042824000000	8	5000000
2	\\x2ba05c0784165f0d3b0a76d9854c950e31a60a0afd4aea6ddfa1c5c058d7b1268e7ecf8aa4e4817052e344b8c95df54ed1335e1f50f34cb07fb861e4e70595f1	286	\\x0000000100000001e3ee3e8ec71d260702410e4461705adcfff72293bf4b13406ce8748adf75fe82e6b221ea5af7cd9fc96764e5e005c8c09713da95dc90c77857cb3964183a74a22e1bb903faa9e888d7a46961a56960eaf93fc778989b4b65ac521c5159e00702f2f268db0d05f21c1f5e4fa8e46996819b982a0411ed147f4001b57b6f5b3039	1	\\xedcad0e23895ec140191dcea14b93dc85e4d92965bc131d479a249d7bf5c95ee3bcb92320d4c68ddb6490f28eec34f8f43276d0bdb1821f14c5179021a22580b	1646042824000000	1	2000000
3	\\xc2430bcdb753d8e088c5b0614be5a43abe3cba224a189a1952983ea4030bc0794ca7bbd3b3a1c7ec95261b956f93906caade23067701529a5eac862f55fa597f	336	\\x00000001000000019a1230e2e3672ab3d136c578f7625108a1584372e2f2a9fcff6934d9a043694c69818fbc77d2ed124b6aa7fa145d371e6446ec7378df1ac3aa72a37b074804f92ab2c5f073a06269e22af666bd62dd23996a72d74e9b7ed08477414411089a709999cdd912ad910b52e31708c6839390ea26ee2b9055d7d7fdfa35a119ea7483	1	\\x831ad864d15c0c61b51d4e15bd4a0079742ee86e7f9bbb44885af6a5c4925a13e276fe11eff2a7476b57e04f5fa49ebb044f855aaaa9413cb3e04c179a54da0f	1646042824000000	0	11000000
4	\\xabd2c35a20d975be7536097af525b8cb5a4927b77bbf5d3fe532fa2b6d050bf05a1a4405312090ff20c19d4254ce49f09cb81a1c0f02e87d8a929bd57ba9b5c4	336	\\x0000000100000001a41245842cd3b10bceb9f3e3bd5d12edef228b7c76e478e1977f22ec8b7f6450c4a735b4d3c9705966a5849da59b199a71c182e58eeb1509c3a396b17dc3f4e086bf80a5b08a783ab58bb3f656198d90019b91878f5ca5c5c4a5b925568368ba58b89e3911c5537b473c20b5c1d7e53842e53f59278b5157c4173983ad8f9470	1	\\x96cbf30ae38e01e5b9628e717527633e2b93964d78ee60c4151a937252fcd902a548a602c5a5b48f33bc8304c08f91340a5920ef3fe9a86eba893b063544280d	1646042824000000	0	11000000
5	\\xacf89d3c8594e894f79a560323df96c6a35f6776fe58dbe2c23f3300889b4f3e684fc103905fb1f44868a09ff6480dfab4525b7043f5a7408fc8856d87ecd439	336	\\x000000010000000139225e3736ac117faf7b4a2f6eebd043ed98408a12733982a0982e10c0acdccfa647f5df33157f3a16d986e327f70cabaad035a42e5c190cf3caf1ef3caaa1d687bad34e9ad627e92a4551d7cb1bf972a05b7a5e093e17b32bfe879159c8338f9cc0af14caad660525c5cbfb7bc8ed93d59742cf1753700d688b87debe067cd7	1	\\x08d047e25a0902d4b6a5a28e50a62acd33d3ccb68e248c394475b4abb9f60e6f9a9e6d043d984eacdb21f6312d7e527550681768dbb7ebbbf079a431d2036408	1646042824000000	0	11000000
6	\\x0adc744908494195a29abc4e867f311859e4dd0761cf68d4da56f464fd1d50079803abcbbdf7db04890ba4cb46cc383e7770713fa8ab3631c8c942178b8c0392	336	\\x000000010000000163101178b313d4f58615696ef66483715a0c63e3094cfc4c5654b1533a0b99431a75030386cc7188543ae174855cecbc780405c41334381a4103ccda32a5170149e3049f1720ca39013f22a13edf72d7861b1204fd0522f1d96013454a6b084c170f665d3e064f2bfce730511bd81cb304bb7444ab46896eaab7fa45b29215bb	1	\\xb0e4b91c573553d3c8e6c35f343a1b1d4b36961941eef321c0e25d7bb5a76e27c2e73f40ff6834297c266cd295663a48484533706a9cb7dd52887fad1069720d	1646042824000000	0	11000000
7	\\x97e48d349cbf2676e37384321f26341487865d0835f94332b1d82cabe5524f11cbf202731bb93559eac118b692ea656f495f62f1a9e40f18ecb3835a20c1ed22	336	\\x0000000100000001bcf77c367988c5d8ee6083d45517d5475b5bd4545f56add291b76474a639c7a62a5e907c70b435437624f52c5e19ce3d7dc6d049f9374501fd6ec119c5bd1b0930847e13ea42e5236c0c21fe1091d393ba752af651ac5cc09d4559c612f37e6480006bb92949b66252f71e15c51ec89765c8bd80b3adc6869d8a2ec6e99fa18f	1	\\x048d69564b959760f467529d93cfcc76930463262919fb60902e5e0246ea9bbb841d5acba8911d46cd1674e2d873e5579c1d3de411b803bfe2791c813f16ee04	1646042824000000	0	11000000
8	\\xc0e006b3737114f6244ab55e6e5cd0552365b5ac70add2f1fd35cbe7b1ee3a77d166d2832e1f098d82399860cc8e7c68b3bc09224ee1a3dd7b0d74631573b180	336	\\x00000001000000017d28092c66a2ab3eb984e29ae140e2252dfa5a8e44c39d848f1c99d3ca41b70db3f62f494f3bc08d35e466c206809c5f3c132ddf396bbec1942855751c946348676a96d0b6150bb25658a9ff2c2a1b44c61373e90d90c764ec54b61f14f02c0ffa39278ecb6057e1126233aa346f15033ac569045258b1abc86128c0fd8c313b	1	\\x6249fa70f533d9fff75dc2877f814a2736b39898d74a8cbc35848bff387810aa690e63e9f23a06a136723fbaad0abdc0b871a0cbd86fc328e1254cfb4f51c20d	1646042824000000	0	11000000
9	\\x16ffa3b95a30a253fa7d08a379afe472caa14e0a51c6e9cb5ebfbe3bcfaeeb141c1ff619ecac2ccb5731869e4d60cea65b7b9c3c1dc3586b5ad73297e0370fc1	336	\\x00000001000000015826f03a353596382b8d85c8b0f3c08ea3e900f715cad17da64405998115e237beea62d3daceea20efca3fa0ed86b727594ec423f42145d986be4b9736fd7980b81787bd8cb35af5869b22a97fdfa793ee52c30c2e78164e9cdbceff7863530e1099a3c1d436b75e20b2faa95c4d7ec4eb225104dfcb79b40a32a9683471820e	1	\\xfb315acc1f760840cb58d75aae460a404c374563cef76dd7607b1756a19c3659ed506fc992c5bf352d4ddf3b25cd775a0a885f731f0b66ef575364a070c84d0a	1646042824000000	0	11000000
10	\\x11d52d731b7fd74906968baaae1567e5e4fe24d1141e1e8d3794cc04fc64387441dbb6a8c5df03778a2d3e4cd5c625e0b209b7cb0dd82e733d56768c6530b47b	336	\\x00000001000000018272eb2189a233401fbb1b667014216281fac32e07167070a135a2fe88c425cf6365bb674c69672b1a11f5ad5eaab3af03f4f3ddb0a16a2b1850a0d55dc7786a16632646bd027fe2b307133b2dd5736a386046dce029bfb18516ea35dc646dae62d039ace051dd940bacae5e787979cde53892be1f9ab900b46f5d9213587b62	1	\\x1510141a70ee2bdb5d8ddb78d417b0d5e7a066fbd5b28e72aef790dc4a4e42c0210c4490193bf3197a6ce1e58d02d130e3de47b038a4c38353d4c9367acd0105	1646042824000000	0	11000000
11	\\x6d5a2bc345b38d71fae619c5dc35c7fa232a5739df5ee4e7300b14ffe90b4b92f121ecc2527fe5f3d21a2a2ecfd380f4f85bc274d95c5cab89fdd71df4fe6abd	206	\\x000000010000000182c181946fac906b42a6605f0c4f4af46bbba8c25210c26432636d60eddd7605ef0f78899c8f0f1841aa8d892787362441acdbd201ab6cfa8d3a1b345ab910381243c15c694ce41e43aa77b51e2b5fab3313a4aee74dc15767721623e88e486c1bf73f5d14f233c21b4647fc2bd21fe17af3274984d3a7050956b8c053938af2	1	\\xa898d56c87fc544a419a3d053d3ee932616c90799785077a98e408873bacb90cc8c13dd7da30cdb8716d7c6d08155a6398f3ea5d6ca9d85f67eca61a8c00f109	1646042824000000	0	2000000
12	\\xb686d6673fe372325b65268c6a5eecbec1dff0ee8b5184196b9322e51454ff18432c57353615667fb063998b3d92183a82511658483bc428c976586456a985d1	206	\\x0000000100000001697c05344df39e62e79ea2010df350a89d96920e5a2f8787891e80592e28f617f0486c2525248d64565cc41a6733059cee54ef69430b5a20912ca1494db99646247112d04643317bc52339731fa7e31c2dcc46411860e830d20af9b66693b6604fd0a6d6f18f38d5c136ea97c18bc679b2dd846faeab116056571d420676acb8	1	\\xa2794f8813b7fa5387ecb63c2454767354a6c9732dbcd7beb832021d22fc6eade918caee58ec61802539283d871db622d19316e6a33a04dada91ac5c42993409	1646042824000000	0	2000000
13	\\x3c414901032c465ab6d5bce5f7c74ac5d537b20c9f9b6bb49fea0e0926f625952cfa29d325c9d169702856dbe128a8d6b7e850dcfc279392f3d6694fe350b8cb	208	\\x0000000100000001c234ed33ca89724c631c1c9480cdf0bc3c120146c726a54ea0ee8d99df1e675441bbc30b21cfeb673c58cbeacc1c582aa88309748214bec77267de5fefe2c280ad2d3a043b91902835126a17218ab5b46f64f9a3b7f384d431a985e55af2b99ae0320c443bf96b834316b236518e335d837e0aca367c18db73df56abc0bbabcb	2	\\x121b1e928c108d7594329a0d460931d774f9d005d95f0ed4a2b86b1dee83436943a5cc1ac96f2f8b9ab6587b26f35eba640b7ba5cbc05b025b1ab563cfb7a204	1646042829000000	10	1000000
14	\\x9edf50abbfd136481cfdf5e518ff80641bcda40915759feb6eb34a54cd30469434e17756a5a760340b60f1f38cafc36b414bfd04a0abc9cd3d89fbdc2445aeea	327	\\x00000001000000014598d5b3e15a38d6b4a28604abcb15de9ba41fe7317bc0bf4d1f77260b28c74b88d20011a65fe960e61d15783bab31ad70557d10ed5d3925c2da803519fdd0bce6ec6d5ddf2e385751171b25ba6ea0b2702fcaff7e59d7fbd1946c758f15de306e8b6d69ef32f2a56bc3b9ce5e5152e9ddd53ad88b0407df491e3042de1934de	2	\\xc8b959a17c69b4ae20802c2276698bb4cf6e953648c642088e327b26e468151c79ab6127ff57c2fe8a26403442bce1e11c785c999b2e2cb1827a0e582bc6cd02	1646042829000000	5	1000000
15	\\x816fb6d432d55075d3a3c3bb9886f172c46b04237d3c721653fdf2cb9c84849d09f340380a11c36668533c7bb28875da75c3eda1ef07c0a369c8e1263e045a8e	181	\\x00000001000000013e8a64ce60a9b5433e416ace135580cfdaded4579c4674244fb3322c3bfd1a63675c457810480b7f4351fb7a67e0f8d1528b580d39b8f7ef380e9d15fb1b1ace044b8a996f0b8ec41b93f1d21b90daaab26aaae4b9b52dcbaf7878feda9f3c7d454085f31cc8d162edb0744c6a2097d4e36ed5da4ac64a41c62b975e437f028e	2	\\x29bcbcfbf026cf749496b4c83d66c816a6a07732532b4029a309df85190c6d17b6a8dfff12be57e48bb3e4d18ee1adf0a5b72d0f2e4cc9bce5849ad73ea76300	1646042830000000	2	3000000
16	\\x752c3fde05f71e58eab86c85d38752ba5706809a61b010b171d981f44b8f9849da4ce080355f53a9f0b00c8b19ad3cbf77b0ef5740f13c0a0839f154257ffc70	336	\\x0000000100000001580ef4a4e5b9363377bbab648a1523bc76075d3c16d84049665a3e99cdacb874675ca77a8fc7461d25f170d1dfa42d6c3cf10b9ba8381692d1e1611c5fc97d4d1a7923b52df6fead9fd209523fcfa1ad9b003b3d0d2daad5c03421ec11ed44bba779af5d75634a3f7eaf73646474eb060817f90c2726aa78d45da13b8365addc	2	\\xfff8ef32b056c221b8ee8a1393bb4d573b95f6ce887ddc844c79d679f8f35d7b5a2ef204404f6d25c29cdcf12b544bb33757c704990c2160e1b1d71f641b1f07	1646042830000000	0	11000000
17	\\x09cf0b68ae6fa2d1b1284e89bea671d9ea552fb82b3d41b17abb0f7f9e134d4b9b984b95e6a27e09976390997311becf346610681c25a1e95cd958970477afa9	336	\\x00000001000000015d4a55decfd8f8b010889a76c2dec05637bddb653dd19bd8bae787e8559d17435f5c6c79a62a117f71388c19f3a91d61cc2c0a9cfd3cfdc732066b2a1b6b81f3b2248b2c4782f1f7afa26da29aa7c96d6666f3fd44212be2a8e41ab2fe3280622698f877cca4922f3def1506f7e360083b3ac8484ecd6ce468b5389481916e63	2	\\xda391d09482eb90e5bb69a859b7d1468bede4e4995ae647e4f69fb912e6b7de3fd108381469a244ecc3e3e42b10fb4542e9d6c88c7004caac4681fe88162bd0a	1646042830000000	0	11000000
18	\\x01bff24d57df7be84c51137c46e3d1eab452bfbaf5a10ca7522f08be1ef7291a2ce0c2833f1e75b0e2aab14410f96e3343571612578919ce65bb460fff2fe1d4	336	\\x00000001000000019c7df44faf2bc0200b0c30c44539898d61eefc3a69bb43dbd3119b8bf2cb312e8d7f1529ee851c3cfa568d9ef03dbfeb3c4cc21eea01222852aa6ca3c7ce0bb3b4f187129c09af537e19295ce1f7214bcea2e00b05828461042a18919fa6d9f7f4d701857b8b60abdd2d6027f29c66bc3dbbe369061ffeeb9e59fc6203bd09d8	2	\\x339b3ee885fd12dd412233bc53227c1ffde290f68be7b5883e3663ab76fd1f816cb990636c132bd02ca7fe5d733d0e99f42a4f19f22c0ba1c524d1d3868a160e	1646042830000000	0	11000000
19	\\x1269bd637cd802e4c771796e9966f16582148aff5e7fbf564db23c12dc79070ea25ee7eefffaae20c13574fd0ffd035e148b011bee644b232908e8e95e9cc64e	336	\\x000000010000000189ac40bb4e86af86b54c38724b8d2f29ddad2a04acb83c205c144051f8e34e796417877f000bda624a794f8afd4f56ff7d9b134c9cebce5b2643d5fa746493d6d0bb1b540f34ecc3bc984b8d7aa7e7c7f2f6ac1fbe73aab0697bc3f6b968adce83ee053324d03810c3d99d11e93424bb1da35d5494c0abc3c835b64f93b2f1ca	2	\\x65a1c0edce90ef25a76e5c44efc7b3efac83f7249fb4f7bfb65e62f6765ac02695309be4dcd9621be9562f188a6085815845f7e38493a512d392195707c9ec01	1646042830000000	0	11000000
20	\\x0bf2dc6a011e5c5a9478cc4ebbde5c908d53b830aa77598c94aa01988b110325eead831f3637db8458b044ef383f30e4ed2b2233d9bb1c4f496b066194a5fb30	336	\\x000000010000000167bf32d1789979b01e1e2ddf49b021622a7a6bdc102fcb373dc02ff83383e6fb0b41aca4446cf3a4b25341dd08a2f2adc95466fdead346a1b65b9ca6107a7e9267bb76bc705c4542a575af02dfe0f995f70275aceb0cfd513649227e5e871831626ce347439825c7f048008b7fb9c820cfe7a0b88441686f4ccf37590d39d416	2	\\x4b726635d5c1a0868339c44a11a34e999d218bffb39948877c8190451ff93803b71e665e186ecfae2a71d3ebb158052f5d90a2019ea54ccd94408e17e708fa0d	1646042830000000	0	11000000
21	\\x7fd7e4492ec9018d0da04a4e6bc86a74691a2205449948a757f96412cc3e708a234075d15d7bc3b71513124678a21ba3c941e0908591e65e19c11a09561928ac	336	\\x0000000100000001b30226c8ad7911e1487aabf63d4d6a0de6a3c6158080349ef7dfe87c915790e68a6784a287f6a8d40dcdbbc0167d5895e8d8e1b260553b4ece94a678df3ab2b57f860e860d825b6a4035e7982cc5266790b07415e023bb90a9064df4ddadd3615c26b0c32a4bc0b91f3b54e472d4bf3ac9c8519ed5ac2a5ba9566d0f9b5fa4f8	2	\\x2d7f8202366a22c222b7eb26dba000ae90c16359048a1b3b1ee62af3886c825247633f363b61316af4be6b0e2a9fad93773429048703bdc92eea44816afc2e04	1646042830000000	0	11000000
22	\\xdbf460fd290decd16cc8a592bd27606cbb8817ba1de6ceeec4f3d6dc2034a15c93e09ef837cc5a95b578e12d0fb760fb6286bbefafd310b6c4225f5ec198cce6	336	\\x0000000100000001887731d1d1e6433cf3c3e6df85783d5d866fa649d5c3bba1a19b22ab3a88d2633b62689301be375e2483d18f81f020d71a7c8f55c59dca3cf6877351c3a2117638b25988240805da116d275417830bc4fb5a2d3ebbf7fbefd76cc0a228bd8419bca08a6c6c0aa5bdf151093e37b04c2a3cee2b665ca9be4e9665d351053389e3	2	\\x89efa591ae62c64680a7435500b077c7d41a36bb82f02c24dd889563f4fc440aa49497505f495a7e77a24d9eea772c1374ff790e81a0788109e376f1d194790a	1646042830000000	0	11000000
23	\\x067b16d3aacbbfbb22dc086a7741c36421ca528826d311f0c4b7a8d80108d91b9cc435bb5b4384b2f090c94f426fe40f8548576af27af9d96c5165544f59e4b1	336	\\x0000000100000001b37f38683813db363c9ae5d847ed1b0890b99fda2e4710b2e287fc364323d981190b6c8f5904c9ab23be4d3a98eaf8afa0699dd98a948b56bac90d331d8a20d2bcea5df42c4c9779a6f953c90e149d10a994b0c4e83a7db92b177fe49bf516f0d5e3da7a63db76449f23f9f70a98ca76c24f33ec4714c8964e036ff00e0250ba	2	\\xd9c293019250ae9ba6d816877c2c52b0408f3dccb8e4ba86d802091ccb9cee4c3e4609d2ba703355f3f544c1e82602b0f0420b78d349db898b807dc115e3b406	1646042830000000	0	11000000
24	\\x0d28b196dd371fb7b23ac9d87705fe598549e93c1f60922130f74eba90568263880f7e6f84dfbde8dc0fcb1d37f5246f310ad31478731658e168b2d6540245bc	206	\\x000000010000000111cb50538db3cb019618d930ef696d884659d6c136268fc5db78123046a7481b497b848ee3c3bc8c785263ec4a397a1b26f6015b12a6c1f1a8ac1aa898bfee224fbfb165ace31b14dd1bf510dec066099350ced7979c7413ffdd56582ff700041d87c334d4c55d8ec9550e220ce5913c42804550057071b3265cd9c0499bf7cf	2	\\xf76b919a63c049a472da3ecc853e2037a2eb81b7def8417b06a06daa2352cc886088e451fc71b1999f0758d319567026edd920c31dd9dd584f48872be9469902	1646042830000000	0	2000000
25	\\xb4c460ffb1ffea85eee3621a7fa733ba36b0b240db60530724aa9b7efab9f676854d8f8534fa2cfb9957f845c3c042e927d9d52bab6e42f8ced3b989ee8a2915	206	\\x000000010000000186ac37a0376080c9e633d2e0d16bec26e15da59ad5a9aefda4ea9cc1ce66be3bc6c69d4f3dbca3badb250f99532bf0e23b301ef2232eea6c1e942537a30f2a2d9331f52dc466903a2b6429464df29a383259aab77126633319799dbd2bf2564f5461e3f7c48fecafa0737a189093182d1c61f2c39f4ba29fdf235b5debac2564	2	\\x931ba6c0314470abd4404d9affd23d6cb8c5aa1feb2d23959ecb0e1cc1835c3a7fc8efe4acae87fb968f9de9d5f1dc87726d558844d9e639036650c27ae8d408	1646042830000000	0	2000000
26	\\x6033b78ec7a6630db53366e8c94d97a64c8ae256a97241082998e5603576fa7a9a93d3ea0efb918d3565a92ad51f92881fc400ddefca8d52a0af6a8ad81c3e9f	206	\\x0000000100000001972a54f6e78ab6ee0a81dbe34bea8117ef1c2a54e02e9a51455bbb43a4219caa0d297833ed0c0a073b4be36800604136d02676c1507fe76316e5613aadc239e40a98c8ab6c6ac05ced7dc16873d5bfaed141a40ce8e91486f32dae623b71a92c90c17a40ecc99920cb44813caf797cc84c6a94adacbcea5f2ab91668c9dd977a	2	\\xe4c4d5cde9c1a0ee15f07fc92f8d28c5e8027b48f306c0589d3ab6613272c29b5cb51652793b66918dfceaa26e4cd9a7dc25c277bb6042e403a7eb268c6a5807	1646042830000000	0	2000000
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
payto://x-taler-bank/localhost/Exchange	\\x46c37ca9d1b64960d224f9ffc4789981b076c5a3b0f1c6c296374bc866214c76048858a38e1633b8231e384707592d8ba186ee42ca019684b711b93a3c591b08	t	1646042816000000
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

COPY public.wire_fee (wire_fee_serial, wire_method, start_date, end_date, wire_fee_val, wire_fee_frac, closing_fee_val, closing_fee_frac, master_sig) FROM stdin;
1	x-taler-bank	1640995200000000	1672531200000000	0	1000000	0	1000000	\\xde51615105348bd84c0473a2815b9a07854bd5e16899d7c57b4ba533194c329dd8d2278c2109558fe593109fab9b971131ab9e6965f8e17c7fe04a0b34efe103
\.


--
-- Data for Name: wire_out_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_out_default (wireout_uuid, execution_date, wtid_raw, wire_target_serial_id, exchange_account_section, amount_val, amount_frac) FROM stdin;
\.


--
-- Data for Name: wire_targets_default; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wire_targets_default (wire_target_serial_id, h_payto, payto_uri, kyc_ok, external_id) FROM stdin;
1	\\x62ca955eb086d43659ca20217ef532392191311576953bd4efcbbde7d1c278c035e4a195e1e2c323213067494bd12daf79140095c0d8265588c577cf29b95be1	payto://x-taler-bank/localhost/testuser-oj2rpn4p	f	\N
2	\\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660cb3a8ffd7e9e69c646815045edc179e5e7ea1ecd9584550d202ae951ebd572e98	payto://x-taler-bank/localhost/43	f	\N
3	\\x2eaeab8bc7201ca19af6301cebedab9daddd3e46d893c2522773749aaa9cd46b848787682f0aa4c0e39ffffeff886acbdaa15186f08214f0d3717749d1d63679	payto://x-taler-bank/localhost/testuser-refluoxm	f	\N
\.


--
-- Data for Name: work_shards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.work_shards (shard_serial_id, last_attempt, start_row, end_row, completed, job_name) FROM stdin;
1	1646042810000000	0	1024	f	wirewatch-exchange-account-1
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
-- Name: cs_nonce_locks cs_nonce_locks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cs_nonce_locks
    ADD CONSTRAINT cs_nonce_locks_pkey PRIMARY KEY (nonce);


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
-- Name: refresh_revealed_coins_default refresh_revealed_coins_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_revealed_coins_default
    ADD CONSTRAINT refresh_revealed_coins_default_pkey PRIMARY KEY (melt_serial_id, freshcoin_index);


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
-- Name: refunds_default refunds_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds_default
    ADD CONSTRAINT refunds_default_pkey PRIMARY KEY (deposit_serial_id, rtransaction_id);


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
    ADD CONSTRAINT wire_targets_pkey PRIMARY KEY (h_payto);


--
-- Name: wire_targets_default wire_targets_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wire_targets_default
    ADD CONSTRAINT wire_targets_default_pkey PRIMARY KEY (h_payto);


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

CREATE INDEX deposits_for_iterate_matching_index ON ONLY public.deposits USING btree (merchant_pub, wire_target_serial_id, done, extension_blocked, refund_deadline);


--
-- Name: INDEX deposits_for_iterate_matching_index; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.deposits_for_iterate_matching_index IS 'for deposits_iterate_matching';


--
-- Name: deposits_default_merchant_pub_wire_target_serial_id_done_ex_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX deposits_default_merchant_pub_wire_target_serial_id_done_ex_idx ON public.deposits_default USING btree (merchant_pub, wire_target_serial_id, done, extension_blocked, refund_deadline);


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
-- Name: wire_out_by_wire_target_serial_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_by_wire_target_serial_id_index ON ONLY public.wire_out USING btree (wire_target_serial_id);


--
-- Name: wire_out_by_wireout_uuid_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_by_wireout_uuid_index ON ONLY public.wire_out USING btree (wireout_uuid);


--
-- Name: wire_out_default_wire_target_serial_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_default_wire_target_serial_id_idx ON public.wire_out_default USING btree (wire_target_serial_id);


--
-- Name: wire_out_default_wireout_uuid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wire_out_default_wireout_uuid_idx ON public.wire_out_default USING btree (wireout_uuid);


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
-- Name: deposits_default_deposit_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_deposit_by_serial_id_index ATTACH PARTITION public.deposits_default_deposit_serial_id_idx;


--
-- Name: deposits_default_merchant_pub_wire_target_serial_id_done_ex_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.deposits_for_iterate_matching_index ATTACH PARTITION public.deposits_default_merchant_pub_wire_target_serial_id_done_ex_idx;


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
-- Name: wire_out_default_wire_target_serial_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.wire_out_by_wire_target_serial_id_index ATTACH PARTITION public.wire_out_default_wire_target_serial_id_idx;


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

